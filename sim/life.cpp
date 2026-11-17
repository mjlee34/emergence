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
WalkPoint sidewalk(const City &city, const Road &r, int k, int side) {
  auto p = r.path[k], a = r.path[std::max(k - 1, 0)],
       b = r.path[std::min(k + 1, 8)];
  double scale = side * (road_width(r.type) * .5 + .48) / distance(a, b);
  p.x -= (b.z - a.z) * scale;
  p.z += (b.x - a.x) * scale;
  return {p, city.street_height(r, p) + .27};
}
Entrance entrance(const City &city, int id) {
  const auto &b = city.buildings()[id];
  const auto &r = city.roads()[b.frontage];
  int k = b.sample;
  auto p = r.path[k], q = r.path[k + 1];
  int side = (q.x - p.x) * (b.pos.z - p.z) - (q.z - p.z) * (b.pos.x - p.x) > 0
                 ? 1
                 : -1;
  double d = distance(b.pos, p);
  double doorstep =
      (5.8 + (b.style % 5) * .47) * .5 + (b.use == Use::Housing ? .32 : 1.55);
  Point door = {b.pos.x + (p.x - b.pos.x) * doorstep / d,
                b.pos.z + (p.z - b.pos.z) * doorstep / d};
  return {b.frontage, k, side, {door, city.height(door) + .3}};
}
void append(Footpath &path, WalkPoint p) {
  double d = path.points.empty() ? 0 : distance(path.points.back().pos, p.pos);
  if (!path.points.empty() && d < .001)
    return;
  path.lengths.push_back(path.lengths.empty() ? 0 : path.lengths.back() + d);
  path.points.push_back(p);
}
void walk_edge(const City &city, Footpath &path, const Road &road, int a, int b, int side) {
  // Stop a sample before the junction and join curb tangents around the corner.
  // Straight-through trips changing sidewalk cross the approach perpendicular
  // to traffic.
  a = std::clamp(a, 1, 7);
  b = std::clamp(b, 1, 7);
  int step = a > b ? -1 : 1;
  if (path.points.size() >= 2 && a != b) {
    auto prev = path.points[path.points.size() - 2].pos,
         last = path.points.back().pos;
    auto first = sidewalk(city, road, a, side), next = sidewalk(city, road, a + step, side);
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
        append(path, {corner, city.height(corner) + .37});
    }
  }
  for (int k = a;; k += step) {
    append(path, sidewalk(city, road, k, side));
    if (k == b)
      break;
  }
}
Footpath connect(const City &city, const Entrance &a, const Entrance &b) {
  const auto &roads = city.roads();
  const auto &first = roads[a.edge];
  const auto &last = roads[b.edge];
  Footpath path;
  append(path, a.door);
  if (a.edge == b.edge) {
    if (a.side == b.side)
      walk_edge(city, path, first, a.k, b.k, a.side);
    else {
      const double near = first.lengths[a.k] + first.lengths[b.k];
      int crossing = near < first.lengths.back() ? 1 : 7;
      walk_edge(city, path, first, a.k, crossing, a.side);
      walk_edge(city, path, first, crossing, b.k, b.side);
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
        if (r.opens > city.tick())
          continue;
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
    walk_edge(city, path, first, a.k, n == first.a ? 0 : 8, a.side);
    for (auto it = chain.rbegin(); it != chain.rend(); ++it) {
      const auto &r = roads[*it];
      bool forward = n == r.a;
      walk_edge(city, path, r, forward ? 0 : 8, forward ? 8 : 0, forward ? 1 : -1);
      n = forward ? r.b : r.a;
    }
    walk_edge(city, path, last, n == last.a ? 0 : 8, b.k, b.side);
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
    paths_.push_back(
        connect(c, entrance(c, key.first), entrance(c, key.second)));
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
                                   : 12 + (18 + int(b.wing * 2.)) * b.floors;
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
  if (r.work < 0 && r.errand >= 0) {
    double walking = std::clamp(paths_[r.errand].lengths.back() /
                                    (2.6 + (r.variation % 8) * .1),
                                2., 120.);
    plan_travel(c, r, walking);
  }
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
  plan_travel(c, r, r.commute_minutes);
}
int Life::access_path(const City &c, int lot, int stop) {
  auto [it, added] =
      access_cache_.emplace(std::pair{lot, stop}, int(paths_.size()));
  if (added) {
    auto &s = transit_.stops()[stop];
    paths_.push_back(
        connect(c, entrance(c, lot), {s.edge, 4, s.side, s.platform}));
  }
  return it->second;
}
BusTrip Life::bus_option(const City &c, int home, int work, double start,
                         double pace) {
  BusTrip best;
  best.finish = std::numeric_limits<double>::infinity();
  auto &stops = transit_.stops();
  for (int a = 0; a < int(stops.size()); ++a) {
    if (distance(c.buildings()[home].pos, stops[a].platform.pos) > 70.)
      continue;
    int access = access_path(c, home, a);
    double reach = start + paths_[access].lengths.back() / pace;
    for (int b = 0; b < int(stops.size()); ++b) {
      if (a == b || stops[b].direction != stops[a].direction ||
          distance(c.buildings()[work].pos, stops[b].platform.pos) > 70.)
        continue;
      int egress = access_path(c, work, b);
      auto trip = transit_.departure(a, b, reach);
      if (trip.from < 0)
        continue;
      trip.access = access;
      trip.egress = egress;
      trip.finish = trip.alight + paths_[egress].lengths.back() / pace;
      if (trip.finish < best.finish)
        best = trip;
    }
  }
  return best;
}
CommuteLeg Life::drive_option(const City &c, int from, int to, double pace) {
  auto [it, added] =
      drive_cache_.emplace(std::pair{from, to}, int(drives_.size()));
  if (added)
    drives_.push_back(drive_route(c, from, to, .98));
  auto &route = drives_[it->second];
  CommuteLeg trip;
  trip.drive = it->second;
  trip.driving = std::max(.25, route.back().end_time / ticks_per_minute);
  auto start = drive_pose(c, route, 0, .98),
       end = drive_pose(c, route, route.back().end_time, .98);
  trip.access = std::max(
      .25, distance(entrance(c, from).door.pos, start.position) / pace);
  trip.duration =
      trip.access + trip.driving +
      std::max(.25, distance(entrance(c, to).door.pos, end.position) / pace);
  return trip;
}
void Life::plan_travel(const City &c, Resident &r, double walking) {
  const double pace = 2.6 + (r.variation % 8) * .1;
  int destination = r.work >= 0 ? r.work : r.shop;
  double start = r.work >= 0 ? r.leave_home : 405 + r.variation % 545;
  r.mode = Mode::Walk;
  r.trips = {};
  double best = walking * 2.;
  for (auto &leg : r.trips)
    leg.duration = walking;
  if (r.car_owner) {
    auto out = drive_option(c, r.home, destination, pace),
         back = drive_option(c, destination, r.home, pace);
    double cost = out.duration + back.duration + 12. + (r.variation >> 20) % 22;
    if (cost < best) {
      best = cost;
      r.mode = Mode::Car;
      r.trips = {out, back};
    }
  }
  auto out = bus_option(c, r.home, destination, start, pace);
  double return_start = r.work >= 0 ? r.finish : out.finish + 45.;
  BusTrip back;
  if (out.from >= 0)
    back = bus_option(c, destination, r.home, return_start, pace);
  if (out.from >= 0 && back.from >= 0 &&
      out.finish - start + back.finish - return_start + 2. < best) {
    r.mode = Mode::Bus;
    transit_.reserve(out);
    transit_.reserve(back);
    r.trips[0] = {};
    r.trips[1] = {};
    auto spread = [&](BusTrip &t) {
      const auto &s = transit_.stops()[t.from];
      t.board = std::max(t.reach, t.run * Transit::headway + s.arrival + .45 +
                                      (r.variation % 101) * .010);
    };
    spread(out);
    spread(back);
    r.trips[0].bus = out;
    r.trips[0].duration = out.finish - start;
    r.trips[1].bus = back;
    r.trips[1].duration = back.finish - return_start;
  }
  if (r.work >= 0)
    r.commute_minutes = r.trips[0].duration;
  else
    r.outing_return = start + r.trips[0].duration + 45.;
}
void Life::assign_school(const City &c, Resident &r, int id) {
  const auto &f = c.facilities()[id];
  if (!r.child || f.opens > c.tick() || distance(f.center, c.buildings()[r.home].pos) > 145.)
    return;
  auto [it, fresh] = green_paths_.emplace(std::pair{r.home, id}, int(paths_.size()));
  if (fresh)
    paths_.push_back(connect(c, entrance(c,r.home),
        {f.frontage,f.sample,f.side,{f.gate,c.height(f.gate)+.34}}));
  double length = paths_[it->second].lengths.back();
  if (length > 145. || (r.school >= 0 && paths_[r.school_path].lengths.back() <= length)) return;
  double walk = std::max(1.,length / 3.);
  // Fit a class between the child's existing household errands and visits.
  auto overlaps = [](double a,double b,double start,double end) { return a<end && b>start; };
  for (double start : {540.,690.,840.}) {
    double leave=start-walk, back=start+120.+walk;
    if (r.shop>=0 && overlaps(leave,back,405.+r.variation%545,r.outing_return+r.trips[1].duration)) continue;
    if (r.facility>=0 && overlaps(leave,back,r.visit_start,r.visit_start+2.*r.visit_walk+r.visit_stay)) continue;
    r.school=id;
    r.school_path=it->second;
    r.school_walk=walk;
    r.class_start=start;
    int absolute=c.tick()/ticks_per_minute+opening_minute;
    r.school_day=absolute/minutes_per_day+(absolute%minutes_per_day>=leave);
    return;
  }
}
void Life::open_facility(const City &c, int id) {
  if (is_service(c.facilities()[id].kind)) {
    if (c.facilities()[id].kind == FacilityKind::School)
      for (auto &r : residents_)
        if (r.school < 0) assign_school(c, r, id);
    return;
  }
  for (auto &r : residents_)
    if (r.facility < 0 &&
        distance(c.facilities()[id].center, c.buildings()[r.home].pos) < 112.)
      plan_visit(c, r);
}
void Life::plan_visit(const City &c, Resident &r) {
  r.facility = -1;
  if (!r.child && (r.variation >> 5) % 3 != 0)
    return;
  double best = 140.;
  for (int i = 0; i < int(c.facilities().size()); ++i) {
    const auto &f = c.facilities()[i];
    if (is_service(f.kind) || f.opens > c.tick() ||
        distance(f.center, c.buildings()[r.home].pos) >= 112.)
      continue;
    auto [it, added] =
        green_paths_.emplace(std::pair{r.home, i}, int(paths_.size()));
    if (added)
      paths_.push_back(connect(
          c, entrance(c, r.home),
          {f.frontage, f.sample, f.side, {f.gate, c.height(f.gate) + .34}}));
    double length = paths_[it->second].lengths.back();
    int preference =
        r.child ? int(FacilityKind::Playground) : int((r.variation >> 11) % 2);
    double score = length + (preference == int(f.kind) ? 0. : 30.);
    if (score >= best)
      continue;
    best = score;
    r.facility = i;
    r.leisure_path = it->second;
    r.visit_walk = std::max(1., length / (2.6 + (r.variation % 8) * .1));
  }
  if (r.facility < 0)
    return;
  r.visit_stay = 18. + (r.variation >> 8) % 25;
  double total = 2 * r.visit_walk + r.visit_stay;
  double depart = r.work >= 0 ? r.leave_home
                              : (r.shop >= 0 ? 405 + r.variation % 545 : 1440);
  double returned =
      r.work >= 0 ? r.finish + r.trips[1].duration
                  : (r.shop >= 0 ? r.outing_return + r.trips[1].duration : 0.);
  double early = 380., late = depart - total - 12.;
  if (late < early || (r.variation % 2 && returned < 1150)) {
    early = std::max(450., returned + 12.);
    late = 1230. - total;
  }
  if (late < early) {
    r.facility = -1;
    return;
  }
  r.visit_start = early + (late - early) * ((r.variation >> 16) % 1000) / 999.;
  if (r.school>=0 && r.visit_start<r.class_start+120.+r.school_walk &&
      r.visit_start+total>r.class_start-r.school_walk) {
    r.facility=-1;
    return;
  }
  if (r.child && c.facilities()[r.facility].kind == FacilityKind::Playground) {
    double arrived = r.visit_start + r.visit_walk;
    for (int slot = int(std::ceil((arrived + 4.) / 4.));
         slot * 4. + 7. < arrived + r.visit_stay; ++slot) {
      if (slide_slots_.insert({r.facility, int(r.variation >> 28) % 2, slot})
              .second) {
        r.slide_slot = slot;
        break;
      }
    }
  }
  const int absolute = c.tick() / ticks_per_minute + opening_minute;
  r.visit_day = c.tick() == 0
                    ? 0
                    : absolute / minutes_per_day +
                          (absolute % minutes_per_day >= r.visit_start);
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
    r.child = !r.seeks_work && ((v >> 14) % 4 == 0);
    r.car_owner = !r.child && (v >> 12) % 100 < 57;
    r.leave_home = 375 + int(v % 145);
    r.lunch = 690 + int((v >> 8) % 69);
    r.finish = r.leave_home + 510 + int((v >> 16) % 41);
    if (r.seeks_work) {
      assign_work(c, r);
      if (r.work < 0)
        waiting_.push_back(int(residents_.size()));
    }
    assign_shop(c, r);
    if (c.tick() > 0) {
      int minute = c.tick() / ticks_per_minute + opening_minute;
      int departure = r.work >= 0 ? r.leave_home : 405 + r.variation % 545;
      r.first_day =
          minute / minutes_per_day + (minute % minutes_per_day >= departure);
    }
    plan_visit(c, r);
    if (r.child)
      for (int f=0; f<int(c.facilities().size()); ++f)
        if (c.facilities()[f].kind==FacilityKind::School) assign_school(c,r,f);
    residents_.push_back(r);
  }
}
void Life::hire_waiting(const City &c) {
  if (!waiting_.empty() && !employers_.empty()) ++job_revision_;
  // Apply new assignments overnight, when every old itinerary has finished.
  while (!waiting_.empty() && !employers_.empty()) {
    auto &r = residents_[waiting_.back()];
    waiting_.pop_back();
    if (r.mode == Mode::Bus)
      for (auto &leg : r.trips)
        transit_.release(leg.bus);
    assign_work(c, r);
    assign_shop(c, r);
    plan_visit(c, r);
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
  int day = int(absolute / minutes_per_day);
  if (r.school>=0 && day>=r.school_day && day%7<5 &&
      t>=r.class_start-r.school_walk && t<r.class_start+120.+r.school_walk) {
    DailyState s{Activity::Walking,r.home,r.home,r.school_path};
    s.facility=r.school;
    if (t<r.class_start) s.progress=1.+(t-r.class_start)/r.school_walk;
    else if (t<r.class_start+120.) s.activity=Activity::School;
    else { s.reverse=true; s.progress=(t-r.class_start-120.)/r.school_walk; }
    return s;
  }
  if (r.facility >= 0 && int(absolute / minutes_per_day) >= r.visit_day &&
      t >= r.visit_start &&
      (int(absolute / minutes_per_day) + int(r.variation >> 28)) % 2 == 0) {
    const double elapsed = t - r.visit_start;
    if (elapsed < 2 * r.visit_walk + r.visit_stay) {
      DailyState visit{Activity::Walking, r.home, r.home, r.leisure_path};
      visit.facility = r.facility;
      if (elapsed < r.visit_walk)
        visit.progress = elapsed / r.visit_walk;
      else if (elapsed < r.visit_walk + r.visit_stay) {
        visit.activity = Activity::Leisure;
        visit.progress = (elapsed - r.visit_walk) / r.visit_stay;
      } else {
        visit.reverse = true;
        visit.progress = (elapsed - r.visit_walk - r.visit_stay) / r.visit_walk;
      }
      return visit;
    }
  }
  auto duration = [&](int route, double limit) {
    return route < 0 ? 0.
                     : std::clamp(paths_[route].lengths.back() /
                                      (2.6 + (r.variation % 8) * .1),
                                  2., limit);
  };
  auto walk = [](int from, int to, int route, double elapsed, double length) {
    return DailyState{Activity::Walking, from,     to, route,
                      elapsed / length,  from > to};
  };
  auto commute_state = [&](int direction, double start) {
    const auto &trip = r.trips[direction];
    int destination = r.work >= 0 ? r.work : r.shop;
    int from = direction ? destination : r.home,
        to = direction ? r.home : destination;
    double e = t - start;
    if (r.mode == Mode::Walk)
      return walk(from, to, r.work >= 0 ? r.commute : r.errand, e,
                  trip.duration);
    DailyState s{Activity::Walking, from, to};
    if (r.mode == Mode::Car) {
      s.drive = trip.drive;
      if (e < trip.access)
        s.progress = e / trip.access;
      else if (e < trip.access + trip.driving) {
        s.activity = Activity::Driving;
        s.progress = (e - trip.access) / trip.driving;
      } else {
        s.last_mile = true;
        s.progress = (e - trip.access - trip.driving) /
                     (trip.duration - trip.access - trip.driving);
      }
      return s;
    }
    const auto &bus = trip.bus;
    s.bus = transit_.vehicle(bus);
    s.stop = bus.from;
    if (t < bus.reach) {
      s.route = bus.access;
      s.progress = e / (bus.reach - start);
    } else if (t < bus.board)
      s.activity = Activity::Waiting;
    else if (t < bus.alight)
      s.activity = Activity::Riding;
    else {
      s.stop = bus.to;
      s.reverse = true;
      s.route = bus.egress;
      s.progress = (t - bus.alight) / (bus.finish - bus.alight);
    }
    return s;
  };
  if (r.work >= 0) {
    double commute = r.commute_minutes, errand = duration(r.errand, 36);
    if (t < r.leave_home)
      return stay(Activity::Home, r.home);
    if (t < r.leave_home + commute)
      return commute_state(0, r.leave_home);
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
    if (t < r.finish + r.trips[1].duration)
      return commute_state(1, r.finish);
  } else if (r.shop >= 0) {
    double start = 405 + r.variation % 545;
    if (t >= start && t < start + r.trips[0].duration)
      return commute_state(0, start);
    if (t >= start + r.trips[0].duration && t < r.outing_return)
      return stay(Activity::Shopping, r.shop);
    if (t >= r.outing_return && t < r.outing_return + r.trips[1].duration)
      return commute_state(1, r.outing_return);
  }
  return stay(Activity::Home, r.home);
}
PersonPose Life::pose(const City &c, int id, const DailyState &s,
                      double tick) const {
  if (s.activity == Activity::School) {
    const auto &f=c.facilities()[s.facility];
    return {f.center,c.height(f.center)+.34,f.yaw};
  }
  if (s.activity == Activity::Leisure) {
    const auto &f = c.facilities()[s.facility];
    // Enter at the gate, stroll around the planted court, and leave through the
    // same gate.
    const double radius = f.radius * (is_landmark(f.kind) ? .91 : .62), stem = f.radius - radius;
    const double loop = 2. * 3.141592653589793 * radius;
    double progress = std::clamp(s.progress, 0., 1.);
    // Some visitors linger partway around the loop to watch play or enjoy the
    // garden.
    double stride = .48, crouch = 0.;
    if ((id % 3) != 0) {
      const double lookout = .22 + .55 * ((id * 37) % 101) / 100.;
      if (progress >= .32 && progress < .66)
        stride = 0.;
      progress = progress < .32 ? lookout * progress / .32
                 : progress < .66
                     ? lookout
                     : lookout + (1. - lookout) * (progress - .66) / .34;
    }
    double d = progress * (2. * stem + loop);
    double x = 0, z = -f.radius + std::min(d, stem), heading = 0;
    if (d > stem + loop) {
      z = -radius - (d - stem - loop);
      heading = 3.141592653589793;
    } else if (d > stem) {
      const double sign = (id % 2) ? 1. : -1., a = sign * (d - stem) / radius;
      x = std::sin(a) * radius;
      z = -std::cos(a) * radius;
      heading = sign * 1.5707963267948966 - a;
    }
    const auto &resident = residents_[id];
    double above = 0.;
    if (resident.slide_slot >= 0) {
      const double arrived = resident.visit_start + resident.visit_walk;
      const double elapsed = s.progress * resident.visit_stay;
      const double slot = resident.slide_slot * 4. - arrived;
      // Walk around the tower, climb the rear ladder, slide, and rejoin the
      // path.
      struct Mark {
        double time, x, z, lift;
      };
      const double q = -2.65 - (id % 4) * .14;
      std::array<Mark, 9> marks{{{0., 0., -f.radius, 0.},
                                 {2.5, q, -2.6, 0.},
                                 {slot - 1., q, 1.2, 0.},
                                 {slot, -1.15, 1.16, 0.},
                                 {slot + 1.5, -1.15, .18, 1.23},
                                 {slot + 2.2, -1.15, -1.12, 1.23},
                                 {slot + 3.1, -1.15, -3.04, .22},
                                 {slot + 4.4, -.30, -4.08, 0.},
                                 {resident.visit_stay, 0., -f.radius, 0.}}};
      auto end =
          std::lower_bound(marks.begin() + 1, marks.end(), elapsed,
                           [](const Mark &m, double t) { return m.time < t; });
      if (end == marks.end())
        --end;
      const auto &a = *(end - 1), &b = *end;
      double u = std::clamp((elapsed - a.time) / (b.time - a.time), 0., 1.);
      x = std::lerp(a.x, b.x, u);
      z = std::lerp(a.z, b.z, u);
      above = std::lerp(a.lift, b.lift, u * u * (3. - 2. * u));
      heading = std::atan2(b.x - a.x, b.z - a.z);
      double since = elapsed - slot;
      crouch = std::clamp((since - 1.8) * 2.5, 0., 1.) *
               std::clamp((3.55 - since) * 2.2, 0., 1.);
      stride = since >= 1.8 && since <= 3.55 ? 0. : .55;
    }
    Point p{f.center.x + x * std::cos(f.yaw) + z * std::sin(f.yaw),
            f.center.z - x * std::sin(f.yaw) + z * std::cos(f.yaw)};
    return {p, c.height(p) + .34 + above, heading + f.yaw, stride, crouch};
  }
  if (s.activity == Activity::Riding)
    return transit_.bus(s.bus, tick / ticks_per_minute + opening_minute).pose;
  if (s.activity == Activity::Waiting) {
    const auto &stop = transit_.stops()[s.stop];
    double along = (int(residents_[id].variation % 9) - 4) * .47;
    double back = ((residents_[id].variation >> 6) % 3) * .27;
    Point p = {stop.platform.pos.x + along * std::cos(stop.yaw) +
                   back * std::sin(stop.yaw),
               stop.platform.pos.z - along * std::sin(stop.yaw) +
                   back * std::cos(stop.yaw)};
    const auto &r = residents_[id];
    const auto &trip = r.trips[s.from == r.home ? 0 : 1].bus;
    double minute =
        std::fmod(tick / ticks_per_minute + opening_minute, minutes_per_day);
    double step = std::clamp(1. - (trip.board - minute) / .55, 0., 1.);
    auto bus = transit_.bus(s.bus, minute);
    if (bus.dwelling && bus.stop == s.stop) {
      double yaw = bus.pose.yaw - 1.57079632679;
      Point door{bus.pose.pos.x + std::cos(yaw) * 2.36 + std::sin(yaw) * 1.12,
                 bus.pose.pos.z - std::sin(yaw) * 2.36 + std::cos(yaw) * 1.12};
      p = {std::lerp(p.x, door.x, step), std::lerp(p.z, door.z, step)};
    }
    return {p, c.height(p) + .38, stop.yaw + 3.14159};
  }
  if (s.drive >= 0) {
    const auto &route = drives_[s.drive];
    double t =
        s.activity == Activity::Driving ? s.progress : (s.last_mile ? 1. : 0.);
    auto car = drive_pose(c, route, t * route.back().end_time, .98);
    if (s.activity == Activity::Driving)
      return {car.position, car.height, 1.57079632679 + car.yaw};
    auto door = entrance(c, s.last_mile ? s.to : s.from).door;
    Point a = s.last_mile ? car.position : door.pos,
          b = s.last_mile ? door.pos : car.position;
    Point p{std::lerp(a.x, b.x, s.progress), std::lerp(a.z, b.z, s.progress)};
    return {p, c.height(p) + .3, std::atan2(b.x - a.x, b.z - a.z)};
  }
  if (s.activity != Activity::Walking) {
    auto a = entrance(c, s.to);
    const auto &b = c.buildings()[s.to];
    if (s.activity == Activity::Work && b.use == Use::Works) {
      double phase = tick * .095 + id;
      double along = 2.25 * std::sin(phase);
      Point p = {a.door.pos.x + along * std::cos(b.yaw),
                 a.door.pos.z - along * std::sin(b.yaw)};
      double heading = b.yaw + (std::cos(phase) > 0 ? 1.5708 : -1.5708);
      return {p, c.height(p) + .20, heading};
    }
    return {a.door.pos, a.door.height, b.yaw};
  }
  return follow_path(paths_[s.route], s.progress, !s.reverse,
                     std::sin(3.14159265 * s.progress) *
                         ((int(residents_[id].variation % 11) - 5) * .06));
}
uint64_t Life::digest() const {
  uint64_t h = 14695981039346656037ULL;
  for (const auto &r : residents_) {
    for (int v : {r.home, r.work, r.shop, r.first_day, r.commute, r.errand,
                  int(r.mode), r.trips[0].bus.run, r.trips[1].bus.run,
                  r.facility, r.leisure_path, r.visit_day, r.slide_slot,
                  r.school, r.school_path, r.school_day}) {
      h ^= uint32_t(v);
      h *= 1099511628211ULL;
    }
  }
  return h;
}
} // namespace city
