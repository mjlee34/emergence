#include "sim/city.hpp"
#include <algorithm>
#include <bit>
#include <cmath>
#include <limits>
#include <queue>
#include <tuple>

namespace city {
namespace {
constexpr int build_time = construction_ticks;
struct District {
  int col, row, threshold;
};
constexpr std::array<District, 6> districts{{{0, 0, 0},
                                             {-5, 2, 2200},
                                             {6, 0, 3500},
                                             {0, -4, 5200},
                                             {-3, 5, 7600},
                                             {7, 4, 10500}}};
RoadClass hierarchy(int x, int y, int c, int r) {
  if (y == 0 && r == 0)
    return RoadClass::Arterial;
  if ((c == x && (c == 0 || c == -5 || c == 6)) ||
      (r == y && (r == 2 || r == -4 || r == 5)))
    return RoadClass::Collector;
  return RoadClass::Local;
}
double segment_distance(Point p, Point a, Point b) {
  double x = b.x - a.x, z = b.z - a.z;
  double t =
      std::clamp(((p.x - a.x) * x + (p.z - a.z) * z) / (x * x + z * z), 0., 1.);
  return distance(p, {a.x + x * t, a.z + z * t});
}
} // namespace
double road_width(RoadClass type) {
  constexpr double widths[] = {4.2, 7.2, 14.2};
  return widths[static_cast<int>(type)];
}
double speed_factor(RoadClass type) {
  constexpr double speeds[] = {0.83, 1.35, 2.05};
  return speeds[static_cast<int>(type)];
}
double road_height(const Road &road, Point p) {
  if (!road.bridge)
    return ground(p);
  auto a = road.path.front(), b = road.path.back();
  double dx = b.x - a.x, dz = b.z - a.z;
  double t = std::clamp(
      ((p.x - a.x) * dx + (p.z - a.z) * dz) / (dx * dx + dz * dz), 0., 1.);
  return std::lerp(ground(a), ground(b), t) + 2.3 * std::sin(3.14159265 * t);
}
uint32_t City::draw() {
  random_ = random_ * 1664525u + 1013904223u;
  return random_;
}
double City::street_height(const Road &road, Point p) const {
  return site_.geographic() ? height(p) : road_height(road, p);
}
City::City(uint32_t seed, Site site) : site_(std::move(site)), seed_(seed), random_(seed) {
  nodes_.push_back({0, 0, street_point(0, 0), {}});
  node_index_[{0, 0}] = 0;
  // A small market street and incomplete side streets provide the starting
  // frontier.
  for (int dir : {-1, 1})
    for (int i = 1; i <= 2; ++i)
      add_road(find_node(dir * (i - 1), 0), dir * i, 0);
  for (int c = -2; c <= 2; ++c)
    for (int r : {-1, 1})
      if (!(c == 2 && r == -1))
        add_road(find_node(c, 0), c, r);
  for (int r : {-1, 1})
    for (int c = -2; c < 2; ++c)
      if (find_node(c + 1, r) >= 0 && (c + r) % 3 != 0)
        add_road(find_node(c, r), c + 1, r);
  add_road(find_node(-1, -1), -1, -2);
  add_road(find_node(-1, -2), 0, -2);
  add_road(find_node(0, -2), 0, -1);
  add_road(find_node(1, 1), 1, 2);
  add_road(find_node(1, 2), 0, 2);
  for (int pass = 0; pass < 4; ++pass)
    for (int e = 0; e < int(roads_.size()); ++e)
      develop(e, true);
  population_ = capacity_ * 95 / 100;
  for (int i = 0; i < int(buildings_.size()); ++i)
    life_.open(*this, i, buildings_[i].capacity);
  life_.start_service(*this);
  life_.settle(*this);
  for (int i = 0; i < int(buildings_.size()); ++i)
    economy_.open(*this, i);
  economy_.update(*this);
  record("Settlement established");
}
std::vector<Vehicle> City::vehicles() const {
  std::vector<Vehicle> active;
  for (int id = 0; id < population_; ++id) {
    auto phase = life_.routine(id, tick_);
    if (phase.activity != Activity::Driving)
      continue;
    const auto &trip = life_.drive_paths()[phase.drive];
    active.push_back(drive_vehicle(
        *this, trip, phase.progress * trip.back().end_time, .98, true));
  }
  return active;
}
int City::find_node(int c, int r) const {
  auto it = node_index_.find({c, r});
  return it == node_index_.end() ? -1 : it->second;
}
int City::add_road(int a, int c, int r) {
  int b = find_node(c, r);
  if (b < 0) {
    b = nodes_.size();
    nodes_.push_back({c, r, street_point(c, r), {}});
    node_index_[{c, r}] = b;
  }
  Road road{};
  road.a = a;
  road.b = b;
  road.type = hierarchy(nodes_[a].col, nodes_[a].row, c, r);
  road.bridge = std::abs(nodes_[a].col - c) > 1;
  for (int i = 0; i <= 8; ++i) {
    double t = i / 8.;
    road.path[i] = street_point(std::lerp(double(nodes_[a].col), double(c), t),
                                std::lerp(double(nodes_[a].row), double(r), t));
    if (i)
      road.lengths[i] =
          road.lengths[i - 1] + distance(road.path[i], road.path[i - 1]);
  }
  const int duration = road.bridge ? 1200 : 480 + 120 * int(road.type);
  road.started = tick_ ? tick_ : -duration;
  road.opens = road.started + duration;
  int e = roads_.size();
  roads_.push_back(road);
  if (tick_)
    road_openings_.emplace(road.opens, e);
  nodes_[a].edges.push_back(e);
  nodes_[b].edges.push_back(e);
  return e;
}
bool City::grow() {
  struct Candidate {
    double score;
    int origin, col, row;
  };
  std::vector<Candidate> candidates;
  const District *target = nullptr;
  for (const auto &district : districts)
    if (population_ >= district.threshold &&
        find_node(district.col, district.row) < 0) {
      target = &district;
      break;
    }
  for (int i = 0; i < int(nodes_.size()); ++i) {
    const auto &n = nodes_[i];
    if (!connected(i))
      continue;
    for (auto [dc, dr] : std::array<std::pair<int, int>, 4>{
             {{1, 0}, {0, 1}, {-1, 0}, {0, -1}}}) {
      int c = n.col + dc, r = n.row + dr;
      // The boulevard crosses the floodplain in one project between dry banks.
      if (!site_.geographic() && r == 0 && n.row == 0 && c == 3) {
        if (population_ < 3500)
          continue;
        c = n.col == 2 ? 4 : 2;
      }
      if (!site_.geographic() && r == -4 && n.row == -4 && c == 4) {
        if (population_ < 10500)
          continue;
        c = n.col == 3 ? 5 : 3;
      }
      int b = find_node(c, r);
      if (b >= 0 &&
          (i > b || std::any_of(n.edges.begin(), n.edges.end(), [&](int e) {
             return roads_[e].a == b || roads_[e].b == b;
           })))
        continue;
      auto p = street_point(c, r);
      if (std::abs(p.x) > half_width - 18 || std::abs(p.z) > half_depth - 18)
        continue;
      auto type = hierarchy(n.col, n.row, c, r);
      double near = 100.;
      for (const auto &district : districts)
        if (population_ >= district.threshold)
          near = std::min(near, std::hypot(c - district.col, r - district.row));
      double score =
          -2.8 * near + double(draw() % 1000) / 310. + (b >= 0 ? 1.2 : 0);
      if (target) {
        // Reach the new center along a through corridor, then fill its local
        // blocks.
        double remaining =
            std::abs(target->col - c) + std::abs(target->row - r);
        double previous =
            std::abs(target->col - n.col) + std::abs(target->row - n.row);
        if (remaining < previous && type != RoadClass::Local)
          score +=
              35. - 2. * remaining + (type == RoadClass::Arterial ? 2. : 0.);
      }
      // Connect both banks by a second route as the northern quarter fills.
      if (!site_.geographic() && population_ >= 10500 && n.row == -4 && r == -4 && c >= 1 && c <= 6)
        score += 17.;
      candidates.push_back({score, i, c, r});
    }
  }
  std::stable_sort(candidates.begin(), candidates.end(),
                   [](auto a, auto b) { return a.score > b.score; });
  for (auto candidate : candidates) {
    const auto &n = nodes_[candidate.origin];
    auto type = hierarchy(n.col, n.row, candidate.col, candidate.row);
    Point prev = n.pos, end = street_point(candidate.col, candidate.row);
    bool viable = true;
    double clearance = road_width(type) * .5 + 4.3;
    for (const auto &lot : buildings_)
      if (segment_distance(lot.pos, prev, end) < clearance) {
        viable = false;
        break;
      }
    for (int k = 1; k <= 8 && viable; ++k) {
      Point p =
          street_point(std::lerp(double(n.col), double(candidate.col), k / 8.),
                       std::lerp(double(n.row), double(candidate.row), k / 8.));
      bool crossing = std::abs(n.col - candidate.col) > 1 &&
                      std::abs(p.x - river_center(p.z)) < 40;
      viable = crossing ||
               (!site_.inland_water(p) && site_.elevation(p) > 1.8 && site_.elevation(prev) > 1.8 &&
                std::abs(height(p) - height(prev)) / distance(prev, p) < .24);
      prev = p;
    }
    if (!viable)
      continue;
    int edge = add_road(candidate.origin, candidate.col, candidate.row);
    record(roads_[edge].bridge            ? "Bridge construction began"
           : type == RoadClass::Arterial  ? "Boulevard construction began"
           : type == RoadClass::Collector ? "Collector construction began"
                                          : "Street construction began");
    return true;
  }
  return false;
}
bool City::develop(int e, bool initial) {
  Road &road = roads_[e];
  if (!road.available_lots || road.bridge)
    return false;
  int start = draw() % 4;
  for (int j = 0; j < 4; ++j) {
    int slot = (j + start) % 4, k = slot < 2 ? 2 : 6;
    unsigned bit = 1u << slot;
    if (!(road.available_lots & bit))
      continue;
    road.available_lots &= ~bit;
    Point p = road.path[k], next = road.path[k + 1];
    double dx = next.x - p.x, dz = next.z - p.z, length = std::hypot(dx, dz);
    double offset = (slot % 2 ? 1 : -1) * (road_width(road.type) * .5 + 6.6);
    p.x -= dz * offset / length;
    p.z += dx * offset / length;
    if (site_.inland_water(p) || site_.elevation(p) < (site_.geographic() ? 1. : 2.5) ||
        std::any_of(buildings_.begin(), buildings_.end(), [&](const auto &lot) {
          return distance(p, lot.pos) < 11.6;
        }))
      continue;
    // Preserve rights of way through undeveloped blocks so early corner lots
    // cannot sever a future cross-town route.
    bool clear = true;
    const auto &node = nodes_[road.a];
    for (int c = node.col - 2; c <= node.col + 2 && clear; ++c) {
      for (int r = node.row - 2; r <= node.row + 2 && clear; ++r) {
        for (auto [dc, dr] :
             std::array<std::pair<int, int>, 2>{{{1, 0}, {0, 1}}}) {
          auto type = hierarchy(c, r, c + dc, r + dr);
          if (type == RoadClass::Local)
            continue;
          if (segment_distance(p, street_point(c, r),
                               street_point(c + dc, r + dr)) <
              road_width(type) * .5 + 4.9)
            clear = false;
        }
      }
    }
    for (const auto &other : roads_) {
      if (distance(p, other.path[4]) > 42)
        continue;
      for (size_t k2 = 1; k2 < other.path.size(); ++k2)
        if (segment_distance(p, other.path[k2 - 1], other.path[k2]) <
            road_width(other.type) * .5 + 4.3)
          clear = false;
    }
    if (!clear)
      continue;
    int style = int(draw() >> 8) % 997;
    bool east = p.x > (site_.geographic() ? 116. : river_center(p.z) + 20);
    const bool yard = (p.x < -70 && p.z > 10 && p.z < 65) || (east && p.z > 0);
    const bool high_street =
        road.type == RoadClass::Arterial ||
        (road.type == RoadClass::Collector && std::abs(p.x + 30) < 54);
    Use use = yard && style % 5 != 0          ? Use::Works
              : high_street && style % 4 != 0 ? Use::Shops
                                              : Use::Housing;
    // Hiring pressure attracts employers to collector frontage within mixed-use
    // districts.
    if (!initial && use == Use::Housing && life_.workforce() > life_.jobs() &&
        road.type != RoadClass::Local && style % 3 != 0)
      use = yard ? Use::Works : Use::Shops;
    Building lot{
        p, -std::atan2(dz, dx), style, 0, initial ? -build_time : tick_, use, e,
        1};
    lot.floors = target_floors(lot);
    lot.capacity = use == Use::Housing ? 17 * lot.floors + style % 12 + 12 : 0;
    buildings_.push_back(lot);
    bounds_[0] = std::min(bounds_[0], p.x);
    bounds_[1] = std::min(bounds_[1], p.z);
    bounds_[2] = std::max(bounds_[2], p.x);
    bounds_[3] = std::max(bounds_[3], p.z);
    if (initial)
      capacity_ += lot.capacity;
    else {
      completions_.push_back(
          {tick_ + build_time, int(buildings_.size() - 1), lot.capacity});
      record(use == Use::Housing ? "Housing construction began"
             : use == Use::Shops ? "Market construction began"
                                 : "Workshop construction began");
    }
    return true;
  }
  return false;
}
int City::target_floors(const Building &b) const {
  if (b.use == Use::Works)
    return 1 + b.style % 2;
  int base = 1 + b.style % 3;
  double radius = distance(b.pos, street_point(0, 0));
  bool frontage = roads_[b.frontage].type != RoadClass::Local;
  if (population_ >= 6500 && radius < 78 && frontage)
    return 9 + b.style % 8;
  if (population_ >= 3200 && radius < 100)
    return 4 + b.style % (frontage ? 5 : 3);
  if (population_ >= 5500 && frontage && radius < 270)
    return 4 + b.style % 4;
  return base;
}
bool City::redevelop() {
  int chosen = -1;
  double best = 0;
  for (int i = 0; i < int(buildings_.size()); ++i) {
    const auto &b = buildings_[i];
    int gain = target_floors(b) - b.floors;
    if (gain <= 0 || tick_ - b.started < build_time)
      continue;
    double rank = gain * 100. - distance(b.pos, street_point(0, 0)) * .12;
    if (rank > best) {
      best = rank;
      chosen = i;
    }
  }
  if (chosen < 0)
    return false;
  auto &b = buildings_[chosen];
  int floors = target_floors(b);
  int gain = b.use == Use::Housing ? 17 * (floors - b.floors) : 0;
  b.previous_floors = b.floors;
  b.floors = floors;
  b.capacity += gain;
  b.started = tick_;
  completions_.push_back({tick_ + build_time, chosen, gain});
  renewals_.push_back(chosen);
  record("Downtown reconstruction began");
  return true;
}
bool City::connected(int node) const {
  const auto &edges = nodes_[node].edges;
  return std::any_of(edges.begin(), edges.end(),
                     [&](int e) { return roads_[e].opens <= tick_; });
}
std::vector<int> City::road_route(int start, int target) const {
  std::vector<int> via(nodes_.size(), -1);
  std::vector<double> cost(nodes_.size(),
                           std::numeric_limits<double>::infinity());
  using Entry = std::pair<double, int>;
  std::priority_queue<Entry, std::vector<Entry>, std::greater<Entry>> queue;
  queue.push({0, start});
  cost[start] = 0;
  while (!queue.empty()) {
    auto [elapsed, n] = queue.top();
    queue.pop();
    if (n == target)
      break;
    if (elapsed > cost[n])
      continue;
    for (int e : nodes_[n].edges) {
      const auto &road = roads_[e];
      if (road.opens > tick_)
        continue;
      int next = road.a == n ? road.b : road.a;
      double arrival = elapsed + road.lengths.back() / speed_factor(road.type);
      if (arrival >= cost[next])
        continue;
      cost[next] = arrival;
      via[next] = e;
      queue.push({arrival, next});
    }
  }
  std::vector<int> edges;
  if (via[target] < 0)
    return edges;
  for (int n = target; n != start;) {
    int e = via[n];
    edges.push_back(e);
    n = roads_[e].a == n ? roads_[e].b : roads_[e].a;
  }
  return edges;
}
Point City::vehicle_position(const Vehicle &v, double &yaw,
                             double fraction) const {
  const auto &road = roads_[v.edge];
  bool forward = v.from == road.a;
  double d = std::clamp(v.along + fraction * v.speed * speed_factor(road.type),
                        0., road.lengths.back());
  if (!forward)
    d = road.lengths.back() - d;
  int i = 1;
  while (i < 8 && road.lengths[i] < d)
    ++i;
  Point a = road.path[i - 1], b = road.path[i];
  double len = road.lengths[i] - road.lengths[i - 1];
  double f = (d - road.lengths[i - 1]) / len, sign = forward ? 1 : -1;
  double dx = (b.x - a.x) * sign / len, dz = (b.z - a.z) * sign / len;
  yaw = -std::atan2(dz, dx);
  double lane = road.type == RoadClass::Arterial
                    ? (v.speed > 1.02 ? 2.42 : 5.35)
                    : road_width(road.type) * .22;
  return {std::lerp(a.x, b.x, f) - dz * lane,
          std::lerp(a.z, b.z, f) + dx * lane};
}
void City::advance(int ticks) {
  for (int i = 0; i < ticks; ++i) {
    ++tick_;
    while (!road_openings_.empty() && road_openings_.begin()->first == tick_) {
      const auto &road = roads_[road_openings_.begin()->second];
      record(road.bridge ? "River bridge opened to traffic" : "Street opened to traffic");
      road_openings_.erase(road_openings_.begin());
    }
    while (!completions_.empty() && completions_.front().tick <= tick_) {
      auto project = completions_.front();
      capacity_ += project.beds;
      life_.open(*this, project.lot, project.beds);
      economy_.open(*this, project.lot);
      auto use = buildings_[project.lot].use;
      record(use == Use::Housing ? "Homes ready for occupancy"
             : use == Use::Shops ? "Shop opened for business"
                                 : "Workshop opened for production");
      completions_.pop_front();
    }
    const int plan = tick_ / planning_interval;
    if (tick_ % (4 * planning_interval) == 0 && population_ < capacity_)
      population_ += std::min(capacity_ - population_,
                              4 + population_ / 250 + int(draw() % 5));
    life_.settle(*this);
    if ((tick_ + opening_minute * ticks_per_minute) %
            (minutes_per_day * ticks_per_minute) ==
        0)
      life_.hire_waiting(*this);
    if (tick_ % (12 * planning_interval) == 0 &&
        population_ * 100 >= capacity_ * 82 && tick_ >= vacant_ticks_) {
      if (plan % 48 == 12)
        grow();
      bool built = (plan % 60 == 0 && redevelop());
      int start = (plan % 24 == 12) ? int(roads_.size() - 1)
                                    : int(draw() % roads_.size());
      for (int j = 0; j < int(roads_.size()) && !built; ++j)
        built = develop((start + j) % roads_.size(), false);
      if (!built && !grow() && !redevelop())
        vacant_ticks_ = tick_ + 192 * planning_interval;
    }
    economy_.update(*this);
  }
}
void City::record(std::string text) {
  events_.push_back({tick_, std::move(text)});
}
uint64_t City::digest() const {
  uint64_t h = 14695981039346656037ULL;
  auto mix = [&](uint64_t value) {
    h ^= value;
    h *= 1099511628211ULL;
  };
  if (site_.geographic()) {
    mix(std::bit_cast<uint64_t>(site_.latitude));
    mix(std::bit_cast<uint64_t>(site_.longitude));
    for (auto y : site_.elevations) mix(y);
    for (auto water : site_.lake) mix(water);
  }
  mix(life_.digest());
  mix(economy_.digest());
  mix(seed_);
  mix(random_);
  mix(tick_);
  mix(capacity_);
  mix(population_);
  mix(vacant_ticks_);
  for (const auto &n : nodes_) {
    mix(n.col);
    mix(n.row);
  }
  for (const auto &r : roads_) {
    mix(r.a);
    mix(r.b);
    mix(r.started);
    mix(r.opens);
  }
  for (const auto &b : buildings_) {
    mix(std::bit_cast<uint64_t>(b.pos.x));
    mix(std::bit_cast<uint64_t>(b.pos.z));
    mix(b.style);
    mix(b.started);
    mix(b.previous_floors);
    mix(b.floors);
    mix(b.capacity);
  }
  return h;
}
} // namespace city
