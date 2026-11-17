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
} // namespace
double road_width(RoadClass type) {
  constexpr double widths[] = {4.2, 7.2, 14.2};
  return widths[static_cast<int>(type)];
}
double speed_factor(RoadClass type) {
  constexpr double speeds[] = {0.83, 1.35, 2.05};
  return speeds[static_cast<int>(type)];
}
uint32_t City::draw() {
  random_ = random_ * 1664525u + 1013904223u;
  return random_;
}
Point City::street_point(double column, double row) const {
  const double x = block_width_ * column +
                   8. * std::sin(.53 * column + .89 * row + grid_phase_);
  const double z =
      36. * row + 9. * std::sin(.87 * column - .41 * row - grid_phase_);
  return {-40. + x * std::cos(grid_angle_) - z * std::sin(grid_angle_),
          4. + x * std::sin(grid_angle_) + z * std::cos(grid_angle_)};
}
double road_height(const Road &road, Point p, const Site &site) {
  if (!road.bridge)
    return site.height(p);
  auto a = road.path.front(), b = road.path.back();
  const double dx = b.x - a.x, dz = b.z - a.z;
  double t = std::clamp(
      ((p.x - a.x) * dx + (p.z - a.z) * dz) / (dx * dx + dz * dz), 0., 1.);
  return std::lerp(site.height(a), site.height(b), t) + 2.3 * std::sin(3.14159265 * t);
}
double City::street_height(const Road &road, Point p) const {
  return road_height(road, p, site_);
}
City::City(uint32_t seed, Site site, int township_through_tick,
           int old_roads_through_tick, int old_skyline_through_tick)
    : site_(std::move(site)), seed_(seed), random_(seed),
      township_through_tick_(township_through_tick),
      old_roads_through_tick_(old_roads_through_tick),
      old_skyline_through_tick_(old_skyline_through_tick) {
  auto unit = [&] { return double(draw() >> 8) / 16777216.; };
  grid_phase_ = 6.2831853 * unit();
  grid_angle_ = .62 * (unit() - .5);
  block_width_ = 35. + 4. * unit();
  const int side = unit() < .5 ? -1 : 1;
  const int wing = unit() < .5 ? -1 : 1;
  workshop_site_ = street_point(1.55 * wing, .85 * side);
  nodes_.push_back({0, 0, street_point(0, 0), {}});
  node_index_[{0, 0}] = 0;
  auto found = [&](int x, int y, int c, int r) {
    auto type = y == 0 && r == 0 ? RoadClass::Arterial
                : (x == 0 && c == 0) || (y == side && r == side)
                    ? RoadClass::Collector
                    : RoadClass::Local;
    add_road(find_node(x, y), c, r, type);
  };
  for (int dir : {-1, 1})
    for (int i = 1; i <= 2; ++i)
      found(dir * (i - 1), 0, dir * i, 0);
  for (int c = -2; c <= 2; ++c)
    for (int r : {-1, 1})
      found(c, 0, c, r);
  // A founding bus circuit and two staggered residential wings.
  for (int c = -2; c < 2; ++c)
    for (int r : {-1, 1})
      if (r == side || c != wing)
        found(c, r, c + 1, r);
  for (int r : {-1, 1}) {
    int c = wing * r;
    found(c, r, c, 2 * r);
    found(c, 2 * r, 0, 2 * r);
    if (r == side)
      found(0, 2 * r, 0, r);
  }
  for (int pass = 0; pass < 4; ++pass)
    for (int e = 0; e < int(roads_.size()); ++e)
      develop(e, true);
  population_ = capacity_ * 95 / 100;
  for (int i = 0; i < int(buildings_.size()); ++i)
    life_.open(*this, i, buildings_[i].capacity);
  plan_facilities();
  life_.start_service(*this);
  life_.settle(*this);
  for (int i = 0; i < int(buildings_.size()); ++i)
    economy_.open(*this, i);
  economy_.update(*this);
  if (old_roads_through_tick_ < 0) {
    // The bus circuit is already occupied. Two outward approaches tie that
    // small planned quarter to the open land the town will grow into.
    grow_surveyed(true);
    grow_surveyed(true);
  }
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
int City::add_road(int a, int c, int r, RoadClass type, bool bridge) {
  int b = find_node(c, r);
  if (b < 0) {
    b = nodes_.size();
    nodes_.push_back({c, r, street_point(c, r), {}});
    node_index_[{c, r}] = b;
  }
  Road road{};
  road.a = a;
  road.b = b;
  road.type = type;
  road.bridge = bridge;
  for (int i = 0; i <= 8; ++i) {
    double t = i / 8.;
    road.path[i] = street_point(std::lerp(double(nodes_[a].col), double(c), t),
                                std::lerp(double(nodes_[a].row), double(r), t));
    if (i)
      road.lengths[i] =
          road.lengths[i - 1] + distance(road.path[i], road.path[i - 1]);
  }
  return commit_road(a, b, road);
}
int City::commit_road(int a, int b, Road road) {
  const int duration = road.bridge ? 1200 : 480 + 120 * int(road.type);
  road.started = tick_ ? tick_ : -duration;
  road.opens = road.started + duration;
  if (road.surveyed && road.lengths.back() >= 60.)
    road.available_lots = road.lengths.back() >= 88. ? 255 : 63;
  int e = roads_.size();
  roads_.push_back(road);
  if (tick_)
    road_openings_.emplace(road.opens, e);
  nodes_[a].edges.push_back(e);
  nodes_[b].edges.push_back(e);
  return e;
}
bool City::develop(int e, bool initial) {
  Road &road = roads_[e];
  if (!road.available_lots || road.bridge)
    return false;
  int slots = road.surveyed && road.lengths.back() >= 60.
                  ? (road.lengths.back() >= 88. ? 8 : 6)
                  : 4;
  int start = draw() % slots;
  for (int j = 0; j < slots; ++j) {
    int slot = (j + start) % slots;
    int k = slots == 8   ? 1 + 2 * (slot / 2)
            : slots == 6 ? 2 + 2 * (slot / 2)
            : slot < 2   ? 2
                         : 6;
    unsigned bit = 1u << slot;
    if (!(road.available_lots & bit))
      continue;
    road.available_lots &= ~bit;
    Point p = road.path[k], next = road.path[k + 1];
    double dx = next.x - p.x, dz = next.z - p.z, length = std::hypot(dx, dz);
    double offset = (slot % 2 ? 1 : -1) * (road_width(road.type) * .5 + 6.6);
    p.x -= dz * offset / length;
    p.z += dx * offset / length;
    if (site_.inland_water(p) ||
        site_.elevation(p) < (site_.geographic() ? 1. : 2.5) ||
        std::any_of(buildings_.begin(), buildings_.end(), [&](const auto &lot) {
          return lot.clearance(p, p) < 11.6;
        }))
      continue;
    // Preserve rights of way through undeveloped blocks so early corner lots
    // cannot sever a future cross-town route.
    bool clear = true;
    const auto &node = nodes_[road.a];
    for (int c = node.col - 2; !road.surveyed && c <= node.col + 2 && clear;
         ++c) {
      for (int r = node.row - 2; r <= node.row + 2 && clear; ++r) {
        for (auto [dc, dr] :
             std::array<std::pair<int, int>, 2>{{{1, 0}, {0, 1}}}) {
          if (segment_distance(p, street_point(c, r),
                               street_point(c + dc, r + dr)) <
              road_width(RoadClass::Local) * .5 + 4.9)
            clear = false;
        }
      }
    }
    for (const auto &other : roads_) {
      if (distance(p, other.path[4]) >
          (other.surveyed ? other.lengths.back() * .56 + 16. : 42.))
        continue;
      for (size_t k2 = 1; k2 < other.path.size(); ++k2)
        if (segment_distance(p, other.path[k2 - 1], other.path[k2]) <
            road_width(other.type) * .5 + 4.3)
          clear = false;
    }
    for (const auto &f : facilities_)
      if (distance(p, f.center) < f.radius + 6.4 ||
          segment_distance(p, f.gate, roads_[f.frontage].path[f.sample]) < 6.4)
        clear = false;
    if (tick_ > old_roads_through_tick_) {
      for (const auto &[ends, rank] : feeders_) {
        if (segment_distance(p, survey_[ends.first].pos,
                             survey_[ends.second].pos) <
            road_width(rank) * .5 + 4.3) {
          clear = false;
          break;
        }
      }
    }
    if (!clear)
      continue;
    int style = int(draw() >> 8) % 997;
    bool yard = distance(p, workshop_site_) < 43.;
    if (!initial && road.type != RoadClass::Local)
      for (const auto &lot : buildings_)
        if (lot.use == Use::Works && distance(p, lot.pos) < 42.) {
          yard = true;
          break;
        }
    const bool high_street = road.type == RoadClass::Arterial ||
                             (road.type == RoadClass::Collector && style % 3 == 0);
    Use use = yard && style % 5 != 0          ? Use::Works
              : high_street && style % 4 != 0 ? Use::Shops
                                              : Use::Housing;
    // Hiring pressure attracts employers to collector frontage within mixed-use
    // districts.
    if (!initial && use == Use::Housing && life_.workforce() > life_.jobs() &&
        road.type != RoadClass::Local && style % 3 != 0)
      use = yard ? Use::Works : Use::Shops;
    if (use == Use::Works &&
        std::any_of(facilities_.begin(), facilities_.end(),
                    [&](const auto &f) { return distance(f.center, p) < 25.; }))
      continue;
    Building lot{
        p, -std::atan2(dz, dx), style, 0, initial ? -build_time : tick_, use, e,
        1};
    lot.sample = k;
    if (!initial && tick_ > old_roads_through_tick_ && population_ >= 2400)
      reserve_frontage(lot);
    lot.floors = target_floors(lot);
    lot.capacity =
        use == Use::Housing
            ? (17 + int(lot.wing * 2.)) * lot.floors + style % 12 + 12
            : 0;
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
  double visits = frontage_visits(b.frontage);
  bool frontage = roads_[b.frontage].type != RoadClass::Local;
  if (tick_ > old_roads_through_tick_) {
    int main_street = 0;
    if (main_street_corner_ >= 0 && visits >= 95.) {
      const auto &corner = buildings_[main_street_corner_];
      double d = distance(corner.pos, b.pos);
      // A busy corner is redeveloped first. The blocks within a short walk
      // can then support a middle height between that corner and the houses.
      if (d < .01) {
        main_street = std::min(b.wing > 0. ? 26 : 15, 4 + population_ / 1350);
      } else if (d < 90. && frontage) {
        double demand = std::min(1., visits / 420.);
        int rise = std::min(7, 1 + population_ / 1750);
        main_street = base + int(rise * demand * (1. - d / 90.));
      }
    }
    if (main_street && population_ < 3000)
      return std::max(base, main_street);
    if (population_ < 3000 || visits < 110.)
      return base;
    double proximity = 0.;
    for (size_t i = 0; i < centres_.size(); ++i) {
      double reach = i ? 140. : 168. + std::min(80., population_ * .001);
      proximity =
          std::max(proximity, 1. - distance(b.pos, centres_[i]) / reach);
    }
    double access = std::min(1., visits / 650.);
    int shoulder =
        base + int(access * (frontage ? 4. : 2.)) + int(proximity * 3.);
    double maturity = std::clamp((population_ - 4500) / 25000., 0., 1.);
    if (proximity > .28 && frontage) {
      shoulder += int(proximity * access * maturity *
                      (b.use == Use::Shops ? 14. : 10.));
      if (b.wing >= 2. && proximity > .56 && b.style % 5 == 0)
        shoulder += int(maturity * (7. + b.style % 7));
    }
    return std::max(main_street, std::min(shoulder, b.wing >= 2. ? 32 : 14));
  }
  if (population_ >= 6500 && visits >= 530. && frontage)
    return 9 + b.style % 8;
  if (population_ >= 3200 && visits >= 260.)
    return 4 + b.style % (frontage ? 5 : 3);
  if (population_ >= 5500 && frontage && visits >= 140.)
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
    double rank = gain * 100. + std::log1p(frontage_visits(b.frontage));
    if (rank > best) {
      best = rank;
      chosen = i;
    }
  }
  if (chosen < 0)
    return false;
  auto &b = buildings_[chosen];
  b.previous_wing = b.wing;
  b.previous_rear = b.rear;
  if (tick_ > old_roads_through_tick_)
    reserve_frontage(b);
  int floors = target_floors(b);
  int gain = b.use == Use::Housing
                 ? (17 + int(b.wing * 2.)) * floors -
                       (17 + int(b.previous_wing * 2.)) * b.floors
                 : 0;
  b.previous_floors = b.floors;
  b.floors = floors;
  b.capacity += gain;
  b.started = tick_;
  completions_.push_back({tick_ + build_time, chosen, gain});
  renewals_.push_back(chosen);
  record("Neighbourhood reconstruction began");
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
      access_changed_ = true;
    }
    while (!completions_.empty() && completions_.front().tick <= tick_) {
      auto project = completions_.front();
      capacity_ += project.beds;
      access_changed_ |= project.beds > 0;
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
      survey_trips();
      if (plan % 48 == 12)
        grow();
      bool built = (plan % 60 == 0 && redevelop());
      int start = (plan % 24 == 12) ? int(roads_.size() - 1)
                                    : int(draw() % roads_.size());
      for (int j = 0; j < int(roads_.size()) && !built; ++j)
        built = develop((start + j) % roads_.size(), false);
      if (!built) {
        if (grow())
          develop(int(roads_.size()) - 1, false);
        else if (!redevelop())
          vacant_ticks_ = tick_ + 192 * planning_interval;
      }
    }
    if (tick_ % (48 * planning_interval) == 0 &&
        (access_changed_ || surveyed_population_ != population_))
      plan_facilities();
    if (tick_ % (192 * planning_interval) == 0)
      plan_public_sites();
    bool service_opened = false;
    for (size_t f = 0; f < facilities_.size(); ++f)
      if (facilities_[f].opens == tick_) {
        life_.open_facility(*this, int(f));
        service_opened |= is_service(facilities_[f].kind);
        record(std::string(facility_name(seed_, facilities_[f])) + " opened");
      }
    if (service_opened) plan_public_sites(false);
    dispatch_services();
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
  for (const auto &f : facilities_) {
    mix(int(f.kind));
    mix(f.catchment);
    mix(f.responses);
    mix(f.frontage);
    mix(f.sample);
    mix(f.side);
    mix(std::bit_cast<uint64_t>(f.center.x));
    mix(std::bit_cast<uint64_t>(f.center.z));
    mix(f.started);
    mix(f.opens);
  }
  for (const auto &r : responses_) { mix(r.station); mix(r.lot); mix(r.start); mix(r.end); }
  mix(life_.digest());
  mix(economy_.digest());
  if (main_street_corner_ >= 0)
    mix(main_street_corner_ + 1);
  mix(seed_);
  mix(random_);
  mix(tick_);
  mix(capacity_);
  mix(population_);
  mix(vacant_ticks_);
  for (const auto &n : nodes_) {
    mix(n.col);
    mix(n.row);
    mix(std::bit_cast<uint64_t>(n.pos.x));
    mix(std::bit_cast<uint64_t>(n.pos.z));
  }
  for (const auto &r : roads_) {
    mix(r.a);
    mix(r.b);
    mix(int(r.type));
    mix(r.bridge);
    mix(r.started);
    mix(r.opens);
    if (r.surveyed)
      for (const auto &p : r.path) {
        mix(std::bit_cast<uint64_t>(p.x));
        mix(std::bit_cast<uint64_t>(p.z));
      }
  }
  for (const auto &b : buildings_) {
    mix(std::bit_cast<uint64_t>(b.pos.x));
    mix(std::bit_cast<uint64_t>(b.pos.z));
    mix(b.style);
    mix(int(b.use));
    mix(b.frontage);
    mix(b.started);
    mix(b.previous_floors);
    mix(b.floors);
    mix(b.capacity);
    if (b.wing > 0.)
      mix(std::bit_cast<uint64_t>(b.wing));
    if (b.rear != 0.)
      mix(std::bit_cast<uint64_t>(b.rear));
  }
  return h;
}
} // namespace city
