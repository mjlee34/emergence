#include "sim/life.hpp"
#include "sim/city.hpp"
#include <algorithm>
#include <cmath>
#include <limits>
#include <queue>

namespace city {
namespace {
uint32_t scramble(uint32_t x) {
  x ^= x >> 16;
  x *= 0x7feb352du;
  x ^= x >> 15;
  x *= 0x846ca68bu;
  return x ^ (x >> 16);
}
struct Entrance {
  int edge, k, side;
  WalkPoint door;
};
WalkPoint sidewalk(const Road &r, int k, int side) {
  auto p = r.path[k], a = r.path[std::max(k - 1, 0)],
       b = r.path[std::min(k + 1, 8)];
  double scale = side * (road_width(r.type) * .5 + .48) / distance(a, b);
  p.x -= (b.z - a.z) * scale;
  p.z += (b.x - a.x) * scale;
  return {p, road_height(r, p) + .27};
}
Entrance entrance(const City &city, int id) {
  const auto &b = city.buildings()[id];
  const auto &r = city.roads()[b.frontage];
  int k = distance(b.pos, r.path[2]) < distance(b.pos, r.path[6]) ? 2 : 6;
  auto p = r.path[k], q = r.path[k + 1];
  int side = (q.x - p.x) * (b.pos.z - p.z) - (q.z - p.z) * (b.pos.x - p.x) > 0
                 ? 1
                 : -1;
  double d = distance(b.pos, p);
  double doorstep =
      (5.8 + (b.style % 5) * .47) * .5 + (b.use == Use::Housing ? .32 : 1.55);
  Point door = {b.pos.x + (p.x - b.pos.x) * doorstep / d,
                b.pos.z + (p.z - b.pos.z) * doorstep / d};
  return {b.frontage, k, side, {door, ground(door) + .3}};
}
void append(Footpath &path, WalkPoint p) {
  double d = path.points.empty() ? 0 : distance(path.points.back().pos, p.pos);
  if (!path.points.empty() && d < .001)
    return;
  path.lengths.push_back(path.lengths.empty() ? 0 : path.lengths.back() + d);
  path.points.push_back(p);
}
void walk_edge(Footpath &path, const Road &road, int a, int b, int side) {
  // Stop a sample before the junction and join curb tangents around the corner.
  // Straight-through trips changing sidewalk cross the approach perpendicular
  // to traffic.
  a = std::clamp(a, 1, 7);
  b = std::clamp(b, 1, 7);
  int step = a > b ? -1 : 1;
  if (path.points.size() >= 2 && a != b) {
    auto prev = path.points[path.points.size() - 2].pos,
         last = path.points.back().pos;
    auto first = sidewalk(road, a, side), next = sidewalk(road, a + step, side);
    Point u = {last.x - prev.x, last.z - prev.z},
          v = {next.pos.x - first.pos.x, next.pos.z - first.pos.z};
    Point delta = {first.pos.x - last.x, first.pos.z - last.z};
    double cross = u.x * v.z - u.z * v.x;
    double lengths = std::hypot(u.x, u.z) * std::hypot(v.x, v.z);
    if (lengths > .01 && distance(last, first.pos) > 1.0) {
      Point corner;
      if (std::abs(cross) > lengths * .23) {
        double along = (delta.x * v.z - delta.z * v.x) / cross;
        corner = {last.x + u.x * along, last.z + u.z * along};
      } else {
        double along =
            -(delta.x * v.x + delta.z * v.z) / (v.x * v.x + v.z * v.z);
        corner = {first.pos.x + v.x * along, first.pos.z + v.z * along};
      }
      if (distance(last, corner) < 16 && distance(first.pos, corner) < 16)
        append(path, {corner, ground(corner) + .37});
    }
  }
  for (int k = a;; k += step) {
    append(path, sidewalk(road, k, side));
    if (k == b)
      break;
  }
}
Footpath connect(const City &city, int origin, int target) {
  const auto a = entrance(city, origin), b = entrance(city, target);
  const auto &roads = city.roads();
  const auto &first = roads[a.edge];
  const auto &last = roads[b.edge];
  Footpath path;
  append(path, a.door);
  if (a.edge == b.edge) {
    if (a.side == b.side)
      walk_edge(path, first, a.k, b.k, a.side);
    else {
      const double near = first.lengths[a.k] + first.lengths[b.k];
      int crossing = near < first.lengths.back() ? 1 : 7;
      walk_edge(path, first, a.k, crossing, a.side);
      walk_edge(path, first, crossing, b.k, b.side);
    }
  } else {
    // Both ends of each frontage participate in the shortest walk, including
    // the partial block.
    std::vector<double> cost(city.nodes().size(),
                             std::numeric_limits<double>::infinity());
    std::vector<int> via(cost.size(), -1);
    using Entry = std::pair<double, int>;
    std::priority_queue<Entry, std::vector<Entry>, std::greater<Entry>> queue;
    for (int n : {first.a, first.b}) {
      cost[n] = n == first.a ? first.lengths[a.k]
                             : first.lengths.back() - first.lengths[a.k];
      queue.push({cost[n], n});
    }
    int end = -1;
    double best = std::numeric_limits<double>::infinity();
    while (!queue.empty()) {
      auto [d, n] = queue.top();
      queue.pop();
      if (d >= best)
        break;
      if (d != cost[n])
        continue;
      if (n == last.a || n == last.b) {
        double total =
            d + (n == last.a ? last.lengths[b.k]
                             : last.lengths.back() - last.lengths[b.k]);
        if (total < best) {
          best = total;
          end = n;
        }
      }
      for (int e : city.nodes()[n].edges) {
        const auto &r = roads[e];
        int next = n == r.a ? r.b : r.a;
        double alt = d + r.lengths.back();
        if (alt < cost[next]) {
          cost[next] = alt;
          via[next] = e;
          queue.push({alt, next});
        }
      }
    }
    int n = end;
    std::vector<int> chain;
    while (via[n] >= 0) {
      int e = via[n];
      chain.push_back(e);
      n = n == roads[e].a ? roads[e].b : roads[e].a;
    }
    walk_edge(path, first, a.k, n == first.a ? 0 : 8, a.side);
    for (auto it = chain.rbegin(); it != chain.rend(); ++it) {
      const auto &r = roads[*it];
      bool forward = n == r.a;
      walk_edge(path, r, forward ? 0 : 8, forward ? 8 : 0, forward ? 1 : -1);
      n = forward ? r.b : r.a;
    }
    walk_edge(path, last, n == last.a ? 0 : 8, b.k, b.side);
  }
  append(path, b.door);
  return path;
}
} // namespace
int Life::path(const City &c, int a, int b) {
  if (a == b || b < 0)
    return -1;
  auto key = std::make_pair(std::min(a, b), std::max(a, b));
  auto [it, added] = route_index_.emplace(key, int(paths_.size()));
  if (added)
    paths_.push_back(connect(c, key.first, key.second));
  return it->second;
}
void Life::open(const City &c, int id, int beds) {
  if (id >= int(places_.size()))
    places_.resize(id + 1);
  auto &place = places_[id];
  const auto &b = c.buildings()[id];
  if (beds > 0 && place.beds == place.housed)
    housing_.push_back(id);
  place.beds += beds;
  int jobs = b.use == Use::Housing ? 0
             : b.use == Use::Works ? 52 + 24 * b.floors
                                   : 12 + 18 * b.floors;
  if (jobs > place.jobs && place.jobs == place.hired)
    employers_.push_back(id);
  if (b.use == Use::Shops && !place.jobs)
    markets_.push_back(id);
  jobs_ += jobs - place.jobs;
  place.jobs = jobs;
}
void Life::assign_shop(const City &c, Resident &r) {
  if (markets_.empty())
    return;
  int origin = r.work < 0 ? r.home : r.work, chosen = -1;
  double best = std::numeric_limits<double>::infinity();
  for (int id : markets_) {
    // Nearby independent shops receive a stable preference per household and
    // worker.
    if (id == origin && markets_.size() > 1)
      continue;
    double score = distance(c.buildings()[origin].pos, c.buildings()[id].pos) +
                   scramble(r.variation ^ uint32_t(id * 71)) % 35;
    if (score < best) {
      chosen = id;
      best = score;
    }
  }
  r.shop = chosen;
  r.errand = path(c, origin, chosen);
}
void Life::assign_work(const City &c, Resident &r) {
  if (employers_.empty())
    return;
  size_t chosen = 0;
  double best = std::numeric_limits<double>::infinity();
  for (int k = 0; k < 4; k++) {
    size_t i = scramble(r.variation + 7919 * k) % employers_.size();
    int e = employers_[i];
    double d = distance(c.buildings()[r.home].pos, c.buildings()[e].pos);
    if (d < best) {
      chosen = i;
      best = d;
    }
  }
  r.work = employers_[chosen];
  auto &e = places_[r.work];
  ++e.hired;
  ++employed_;
  if (e.hired == e.jobs) {
    employers_[chosen] = employers_.back();
    employers_.pop_back();
  }
  r.commute = path(c, r.home, r.work);
  r.commute_minutes = r.commute < 0
                          ? 0.
                          : std::clamp(paths_[r.commute].lengths.back() /
                                           (2.6 + (r.variation % 8) * .1),
                                       2., 150.);
}
void Life::settle(const City &c) {
  while (int(residents_.size()) < c.population()) {
    uint32_t v = scramble(c.seed() + uint32_t(residents_.size()) * 2654435761u);
    size_t index = v % housing_.size();
    int home = housing_[index];
    auto &place = places_[home];
    if (++place.housed == place.beds) {
      housing_[index] = housing_.back();
      housing_.pop_back();
    }
    Resident r{};
    r.home = home;
    r.variation = v;
    r.seeks_work = v % 100 < 67;
    r.leave_home = 375 + int(v % 145);
    r.lunch = 690 + int((v >> 8) % 69);
    r.finish = r.leave_home + 510 + int((v >> 16) % 41);
    // Arrivals join their next routine from home. The founding population is
    // already living here.
    if (c.tick() > 0) {
      int minute = c.tick() / ticks_per_minute + opening_minute;
      r.first_day =
          minute / minutes_per_day + (minute % minutes_per_day >= r.leave_home);
    }
    if (r.seeks_work) {
      assign_work(c, r);
      if (r.work < 0)
        waiting_.push_back(int(residents_.size()));
    }
    assign_shop(c, r);
    residents_.push_back(r);
  }
}
void Life::hire_waiting(const City &c) {
  // Apply new assignments overnight, when every old itinerary has finished.
  while (!waiting_.empty() && !employers_.empty()) {
    auto &r = residents_[waiting_.back()];
    waiting_.pop_back();
    assign_work(c, r);
    assign_shop(c, r);
  }
}
DailyState Life::routine(int id, double tick) const {
  const auto &r = residents_[id];
  double absolute = tick / ticks_per_minute + opening_minute;
  double t = std::fmod(absolute, minutes_per_day);
  auto stay = [](Activity activity, int at) {
    return DailyState{activity, at, at};
  };
  if (int(absolute / minutes_per_day) < r.first_day)
    return stay(Activity::Home, r.home);
  auto duration = [&](int route, double limit) {
    return route < 0 ? 0.
                     : std::clamp(paths_[route].lengths.back() /
                                      (2.6 + (r.variation % 8) * .1),
                                  2., limit);
  };
  auto walk = [](int from, int to, int route, double elapsed, double length) {
    return DailyState{Activity::Walking, from, to, route, elapsed / length};
  };
  if (r.work >= 0) {
    double commute = r.commute_minutes, errand = duration(r.errand, 36);
    if (t < r.leave_home)
      return stay(Activity::Home, r.home);
    if (t < r.leave_home + commute)
      return walk(r.home, r.work, r.commute, t - r.leave_home, commute);
    if (r.shop >= 0 && t >= r.lunch && t < r.lunch + 2 * errand + 25) {
      double e = t - r.lunch;
      if (e < errand)
        return walk(r.work, r.shop, r.errand, e, errand);
      if (e < errand + 25)
        return stay(Activity::Shopping, r.shop);
      return walk(r.shop, r.work, r.errand, e - errand - 25, errand);
    }
    if (t < r.finish)
      return stay(Activity::Work, r.work);
    if (t < r.finish + commute)
      return walk(r.work, r.home, r.commute, t - r.finish, commute);
  } else if (r.shop >= 0) {
    double start = 510 + r.variation % 410, d = duration(r.errand, 120),
           e = t - start;
    if (e >= 0 && e < d)
      return walk(r.home, r.shop, r.errand, e, d);
    if (e >= d && e < d + 45)
      return stay(Activity::Shopping, r.shop);
    if (e >= d + 45 && e < 2 * d + 45)
      return walk(r.shop, r.home, r.errand, e - d - 45, d);
  }
  return stay(Activity::Home, r.home);
}
PersonPose Life::pose(const City &c, int id, const DailyState &s,
                      double tick) const {
  if (s.activity != Activity::Walking) {
    auto a = entrance(c, s.to);
    const auto &b = c.buildings()[s.to];
    if (s.activity == Activity::Work && b.use == Use::Works) {
      double phase = tick * .095 + id;
      double along = 2.25 * std::sin(phase);
      Point p = {a.door.pos.x + along * std::cos(b.yaw),
                 a.door.pos.z - along * std::sin(b.yaw)};
      double heading = b.yaw + (std::cos(phase) > 0 ? 1.5708 : -1.5708);
      return {p, ground(p) + .20, heading};
    }
    return {a.door.pos, a.door.height, b.yaw};
  }
  const auto &path = paths_[s.route];
  bool forward = s.from < s.to;
  double d = (forward ? s.progress : 1 - s.progress) * path.lengths.back();
  auto it = std::lower_bound(path.lengths.begin() + 1, path.lengths.end(), d);
  size_t k =
      std::min(size_t(it - path.lengths.begin()), path.points.size() - 1);
  auto a = path.points[k - 1], b = path.points[k];
  double len = path.lengths[k] - path.lengths[k - 1];
  double f = std::clamp((d - path.lengths[k - 1]) / len, 0., 1.);
  double dx = b.pos.x - a.pos.x, dz = b.pos.z - a.pos.z;
  // Slight lateral spacing keeps individuals legible on a shared sidewalk.
  double spacing = std::sin(3.14159265 * s.progress) *
                   ((int(residents_[id].variation % 11) - 5) * .06) / len;
  return {{std::lerp(a.pos.x, b.pos.x, f) - dz * spacing,
           std::lerp(a.pos.z, b.pos.z, f) + dx * spacing},
          std::lerp(a.height, b.height, f),
          std::atan2(forward ? dx : -dx, forward ? dz : -dz)};
}
uint64_t Life::digest() const {
  uint64_t h = 14695981039346656037ULL;
  for (const auto &r : residents_) {
    for (int v : {r.home, r.work, r.shop, r.first_day, r.commute, r.errand}) {
      h ^= uint32_t(v);
      h *= 1099511628211ULL;
    }
  }
  return h;
}
} // namespace city
