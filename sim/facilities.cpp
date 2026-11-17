#include "sim/city.hpp"
#include <algorithm>
#include <cmath>
#include <limits>
#include <queue>

namespace city {
namespace {
// Bounded shortest walks from a frontage sample through the open street graph.
std::vector<double> access_distances(const City &city, int edge, int sample,
                                     double limit = 110.) {
  const auto &r = city.roads()[edge];
  std::vector<double> cost(city.nodes().size(),
                           std::numeric_limits<double>::infinity());
  using Entry = std::pair<double, int>;
  std::priority_queue<Entry, std::vector<Entry>, std::greater<Entry>> queue;
  cost[r.a] = r.lengths[sample];
  cost[r.b] = r.lengths.back() - r.lengths[sample];
  queue.emplace(cost[r.a], r.a);
  queue.emplace(cost[r.b], r.b);
  while (!queue.empty()) {
    auto [d, n] = queue.top();
    queue.pop();
    if (d != cost[n] || d >= limit)
      continue;
    for (int e : city.nodes()[n].edges) {
      const auto &next = city.roads()[e];
      if (next.opens > city.tick())
        continue;
      int to = n == next.a ? next.b : next.a;
      double total = d + next.lengths.back();
      if (total < cost[to]) {
        cost[to] = total;
        queue.emplace(total, to);
      }
    }
  }
  return cost;
}
double walk_from_home(const City &city, int edge, int sample,
                      const std::vector<double> &cost, const Building &home) {
  const auto &r = city.roads()[home.frontage];
  int k = distance(home.pos, r.path[2]) < distance(home.pos, r.path[6]) ? 2 : 6;
  double along = edge == home.frontage
                     ? std::abs(r.lengths[k] - r.lengths[sample])
                     : std::min(cost[r.a] + r.lengths[k],
                                cost[r.b] + r.lengths.back() - r.lengths[k]);
  return along + distance(home.pos, r.path[k]);
}
double suitability(const City &city, const Facility &f, double demand) {
  const auto &r = city.roads()[f.frontage];
  const Point curb = r.path[f.sample];
  for (const auto &old : city.facilities())
    if (distance(old.center, f.center) < std::max(f.radius + old.radius + 2., f.kind == old.kind ? 60. : 29.))
      return 0;

  std::array<double, 4> neighbours{};
  for (const auto &b : city.buildings()) {
    double d = distance(f.center, b.pos);
    if (b.use == Use::Housing && d < 48.) {
      const double dx = b.pos.x - f.center.x, dz = b.pos.z - f.center.z;
      int sector = std::abs(dx) > std::abs(dz) ? int(dx > 0) : 2 + int(dz > 0);
      neighbours[sector] = std::max(neighbours[sector], 1. - d / 48.);
    }
    if (d < f.radius + 6.4 || (b.use == Use::Works && d < 25.) ||
        segment_distance(b.pos, curb, f.gate) < 6.4)
      return 0;
  }
  double previous = city.height(curb);
  for (int k = 1; k <= 5; ++k) {
    double t = k / 5.;
    Point p{std::lerp(curb.x, f.gate.x, t), std::lerp(curb.z, f.gate.z, t)};
    if (city.site().inland_water(p) || city.site().elevation(p) < 1.4 ||
        std::abs(city.height(p) - previous) > distance(curb, f.gate) * .035)
      return 0;
    previous = city.height(p);
  }
  for (const auto &road : city.roads()) {
    if (distance(road.path[4], f.center) > 90.)
      continue;
    for (int i = 1; i < 9; ++i) {
      double clear =
          segment_distance(f.center, road.path[i - 1], road.path[i]) -
          road_width(road.type) * .5;
      if (clear < f.radius + 1.5 ||
          (f.kind == FacilityKind::Playground &&
           road.type == RoadClass::Arterial && clear < 18.))
        return 0;
    }
  }
  double lo = city.height(f.center), hi = lo;
  const auto [width,depth] = city.planning_extent();
  int samples = is_landmark(f.kind) ? 32 : 8;
  for (int k = 0; k < samples; ++k) {
    double a = k * 6.283185307179586 / samples;
    Point p{f.center.x + f.radius * std::cos(a),
            f.center.z + f.radius * std::sin(a)};
    if (city.site().inland_water(p) || city.site().elevation(p) < 1.4 ||
        std::abs(p.x) > width - 1 || std::abs(p.z) > depth - 1)
      return 0;
    lo = std::min(lo, city.height(p));
    hi = std::max(hi, city.height(p));
  }
  if (city.site().inland_water(f.center) ||
      city.site().elevation(f.center) < 1.4 || hi - lo > f.radius * .24)
    return 0;
  double enclosure = 0.;
  for (double nearby : neighbours)
    enclosure += nearby;
  if (is_service(f.kind) || is_landmark(f.kind))
    return demand / (1. + (hi - lo) * .23);
  return demand * (.3 + enclosure * enclosure) / (1. + (hi - lo) * .23) *
         (r.type == RoadClass::Local ? 1.1 : 1.);
}
} // namespace
void City::plan_facilities() {
  access_changed_ = false;
  surveyed_population_ = population_;
  for (auto kind : {FacilityKind::Park, FacilityKind::Playground}) {
    const int count =
        std::count_if(facilities_.begin(), facilities_.end(),
                      [&](const auto &f) { return f.kind == kind; });
    if (count >= 1 + population_ / (kind == FacilityKind::Park ? 2000 : 1450))
      continue;
    std::vector<int> homes;
    for (int i = 0; i < int(life_.occupancies().size()); ++i)
      if (life_.occupancies()[i].beds > 0)
        homes.push_back(i);
    for (const auto &f : facilities_) {
      if (f.kind != kind)
        continue;
      auto cost = access_distances(*this, f.frontage, f.sample);
      std::erase_if(homes, [&](int lot) {
        return walk_from_home(*this, f.frontage, f.sample, cost,
                              buildings_[lot]) +
                   distance(f.gate, roads_[f.frontage].path[f.sample]) <
               (kind == FacilityKind::Park ? 103. : 86.);
      });
    }
    if (homes.empty())
      continue;
    Facility best{};
    double highest = 0.;
    for (int e = 0; e < int(roads_.size()); ++e) {
      const auto &r = roads_[e];
      if (r.bridge || r.opens > tick_ || r.type == RoadClass::Arterial)
        continue;
      for (int k : {2, 4, 6}) {
        auto cost = access_distances(*this, e, k);
        double demand = 0.;
        int neighbours = 0;
        for (int id : homes) {
          double walk = walk_from_home(*this, e, k, cost, buildings_[id]);
          if (walk < 90.) {
            demand += (1. - walk / 90.) * life_.occupancies()[id].beds;
            ++neighbours;
          }
        }
        if (neighbours < 2 || demand < 38.)
          continue;
        for (int side : {-1, 1})
          for (double setback : {10., 16., 21.}) {
            Point a = r.path[k], b = r.path[k + 1];
            double len = distance(a, b), nx = side * (a.z - b.z) / len,
                   nz = side * (b.x - a.x) / len;
            double d = road_width(r.type) * .5 + setback,
                   radius = kind == FacilityKind::Park ? 8. : 6.6;
            Point p{a.x + d * nx, a.z + d * nz};
            // Local +Z points across the garden from its street entrance.
            Facility f{kind,
                       p,
                       {p.x - radius * nx, p.z - radius * nz},
                       std::atan2(nx, nz),
                       radius,
                       e,
                       k,
                       side,
                       tick_ ? tick_ : -720,
                       tick_ ? tick_ + 720 : 0};
            double score =
                suitability(*this, f, demand) / (1. + setback * .008);
            if (score > highest) {
              best = f;
              highest = score;
            }
          }
      }
    }
    if (highest > 0.) {
      facilities_.push_back(best);
      if (tick_)
        record(kind == FacilityKind::Park
                   ? "Neighbourhood park landscaping began"
                   : "Playground construction began");
    }
  }
}
const char *facility_name(FacilityKind kind) {
  constexpr const char *names[] = {"Neighbourhood park",
                                   "Neighbourhood playground",
                                   "Community school",
                                   "District hospital",
                                   "Fire station",
                                   "Police station",
                                   "Grand observation tower",
                                   "Beacon of Liberty"};
  return names[int(kind)];
}
namespace {
struct ServicePlan {
  FacilityKind kind;
  int first_population, per_site;
  double reach, radius;
};
constexpr ServicePlan services[] = {
    {FacilityKind::School, 1950, 5400, 145., 7.6},
    {FacilityKind::Fire, 2400, 8500, 200., 7.4},
    {FacilityKind::Hospital, 3100, 10000, 225., 8.6},
    {FacilityKind::Police, 3750, 8000, 185., 7.2}};

Facility roadside_site(const City &city, FacilityKind kind, int edge, int k,
                       int side, double radius, double setback, int duration) {
  const auto &road = city.roads()[edge];
  Point a = road.path[k], b = road.path[k + 1];
  double length = distance(a, b);
  Point normal{side * (a.z - b.z) / length, side * (b.x - a.x) / length};
  double offset = road_width(road.type) * .5 + setback;
  Point center{a.x + offset * normal.x, a.z + offset * normal.z};
  return {kind,
          center,
          {center.x - radius * normal.x, center.z - radius * normal.z},
          std::atan2(normal.x, normal.z),
          radius,
          edge,
          k,
          side,
          city.tick(),
          city.tick() + duration};
}

uint32_t mix_seed(uint32_t seed) {
  seed ^= seed >> 16;
  seed *= 0x7feb352d;
  seed ^= seed >> 15;
  seed *= 0x846ca68b;
  return seed ^ (seed >> 16);
}

// Look out across a continuous patch of water, or along the axis of a major
// street towards the site. Both surveys use the current site's own terrain.
double landmark_setting(const City &city, Facility &f, bool prefer_water) {
  auto clear_view = [&](Point from) {
    return std::none_of(city.buildings().begin(), city.buildings().end(),
                        [&](const auto &lot) {
                          return segment_distance(lot.pos, from, f.center) < 4.5;
                        });
  };
  int wet = 0;
  for (int ray = 0; ray < 12; ++ray) {
    double angle = ray * 3.141592653589793 / 6.;
    bool open_water = true;
    for (double step : {46., 59.}) {
      Point p{f.center.x + step * std::sin(angle),
              f.center.z + step * std::cos(angle)};
      open_water &=
          city.site().inland_water(p) || city.site().elevation(p) <= 0.;
    }
    if (open_water && clear_view({f.center.x+59.*std::sin(angle),
                                  f.center.z+59.*std::cos(angle)}))
      ++wet;
  }
  double vista = 0;
  for (const auto &r : city.roads()) {
    if (r.type != RoadClass::Arterial || r.opens > city.tick())
      continue;
    for (int k : {0, 8}) {
      Point tip = r.path[k], base = r.path[8 - k];
      double d = distance(tip, f.center);
      if (d < 12. || d > 74.)
        continue;
      double dot = ((tip.x - base.x) * (f.center.x - tip.x) +
                    (tip.z - base.z) * (f.center.z - tip.z)) /
                   (distance(base, tip) * d);
      if (dot > .96 && clear_view(tip))
        vista = std::max(vista, dot * (1. - d / 110.));
    }
  }
  bool civic_square = false;
  for (const auto &s : city.facilities())
    if (s.opens <= city.tick() && distance(s.center, f.center) < 73. &&
        (s.kind == FacilityKind::Park || is_service(s.kind)))
      civic_square = true;
  if (wet >= 2 && (prefer_water || vista == 0. || !civic_square)) {
    f.kind = FacilityKind::Statue;
    return 2. + wet * .4;
  }
  if (vista > 0. && civic_square) {
    f.kind = FacilityKind::Tower;
    return 2. + 3. * vista;
  }
  return 0.;
}
} // namespace

void City::plan_public_sites(bool allow_building) {
  std::vector<int> pupils(buildings_.size());
  for (const auto &r : life_.people())
    if (r.child)
      ++pupils[r.home];
  for (const auto &plan : services) {
    if (population_ < plan.first_population)
      continue;
    std::vector<int> demand(buildings_.size());
    for (size_t i = 0; i < life_.occupancies().size(); ++i) {
      auto place = life_.occupancies()[i];
      demand[i] = plan.kind == FacilityKind::School ? pupils[i]
                  : plan.kind == FacilityKind::Hospital
                      ? place.housed
                      : place.housed + place.hired;
    }
    int count = 0;
    std::vector<int> nearest(demand.size(), -1);
    std::vector<double> shortest(demand.size(), plan.reach);
    for (size_t id = 0; id < facilities_.size(); ++id) {
      auto &f = facilities_[id];
      if (f.kind != plan.kind)
        continue;
      ++count;
      f.catchment = 0;
      if (f.opens > tick_)
        continue;
      auto cost = access_distances(*this, f.frontage, f.sample, plan.reach);
      for (size_t i = 0; i < demand.size(); ++i) {
        if (!demand[i])
          continue;
        double d =
            walk_from_home(*this, f.frontage, f.sample, cost, buildings_[i]) +
            distance(f.gate, roads_[f.frontage].path[f.sample]);
        if (d < shortest[i]) {
          shortest[i] = d;
          nearest[i] = id;
        }
      }
    }
    for (size_t i = 0; i < demand.size(); ++i) {
      if (nearest[i] >= 0) {
        facilities_[nearest[i]].catchment += demand[i];
        demand[i] = 0;
      } else if ((plan.kind == FacilityKind::Fire &&
                  buildings_[i].use == Use::Works) ||
                 (plan.kind == FacilityKind::Police &&
                  buildings_[i].use == Use::Shops))
        demand[i] *= 3;
    }
    if (!allow_building ||
        count >= 1 + (population_ - plan.first_population) / plan.per_site)
      continue;
    Facility best{};
    double highest = 0;
    for (int e = 0; e < int(roads_.size()); ++e) {
      auto &r = roads_[e];
      if (r.opens > tick_ || r.bridge ||
          (plan.kind == FacilityKind::School && r.type == RoadClass::Arterial))
        continue;
      for (int k : {2, 6}) {
        auto cost = access_distances(*this, e, k, plan.reach);
        double need = 0;
        for (size_t i = 0; i < demand.size(); ++i) {
          if (!demand[i])
            continue;
          double d = walk_from_home(*this, e, k, cost, buildings_[i]) + 12.;
          need += demand[i] * std::max(0., 1. - d / plan.reach);
        }
        if (need < (plan.kind == FacilityKind::School ? 12. : 85.))
          continue;
        if (plan.kind != FacilityKind::School && r.type != RoadClass::Local)
          need *= 1.4;
        for (int side : {-1, 1})
          for (double setback : {13., 19., 25.}) {
            auto f = roadside_site(*this, plan.kind, e, k, side, plan.radius,
                                   setback, 1440);
            double score = suitability(*this, f, need) / (1. + setback * .012);
            if (score > highest) {
              highest = score;
              best = f;
            }
          }
      }
    }
    if (highest > 0.) {
      facilities_.push_back(best);
      record(std::string(facility_name(best.kind)) + " construction began");
    }
  }
  const uint32_t draw = mix_seed(seed_);
  if (!allow_building || draw % 5 || population_ < 12000 ||
      tick_ < 24 * minutes_per_day * ticks_per_minute ||
      std::any_of(
          facilities_.begin(), facilities_.end(),
          [](auto &f) { return is_landmark(f.kind); }))
    return;
  Facility best{};
  double highest = 0.;
  for (int e = 0; e < int(roads_.size()); ++e) {
    auto &r = roads_[e];
    if (r.opens > tick_ || r.bridge || frontage_visits(e) < 100.)
      continue;
    for (int side : {-1, 1})
      for (int k : {2, 6})
        for (double setback : {36., 44., 52., 60.}) {
          // Survey the full forecourt before committing the monument. The
          // perimeter also reserves a promenade outside its foundations.
          auto f = roadside_site(*this, FacilityKind::Tower, e, k, side, 29.,
                                 setback, 5760);
          if (suitability(*this, f, 1.) <= 0.) continue;
          double setting = landmark_setting(*this, f, (draw >> 8) & 1);
          if (setting <= 0.) continue;
          if (f.kind == FacilityKind::Tower)
            f = roadside_site(*this, f.kind, e, k, side, 34., setback, 5760);
          double score = suitability(*this,f,1.) * setting * std::log1p(frontage_visits(e));
          if (score > highest) {
            highest = score;
            best = f;
          }
        }
  }
  if (highest > 0.) {
    facilities_.push_back(best);
    record(std::string(facility_name(best.kind)) + " construction began");
  }
}

void City::dispatch_services() {
  std::erase_if(responses_, [&](const Response &call) {
    if (tick_ < call.end)
      return false;
    ++facilities_[call.station].responses;
    return true;
  });
  if (tick_ % 360 != 0 || buildings_.empty())
    return;
  const uint32_t draw =
      mix_seed(seed_ ^ (uint32_t(tick_ / 360) * 2654435761u));
  const FacilityKind kind =
      std::array{FacilityKind::Hospital, FacilityKind::Fire,
                 FacilityKind::Police}[draw % 3];
  const int lot = (draw >> 3) % buildings_.size();
  if (lot >= int(life_.occupancies().size()))
    return;
  const auto &place = life_.occupancies()[lot];
  if (place.housed + place.hired == 0)
    return;
  const auto target = building_curb(*this, lot);
  Response best{};
  double fastest = std::numeric_limits<double>::infinity();
  constexpr double speed = 1.;
  for (int i = 0; i < int(facilities_.size()); ++i) {
    const auto &f = facilities_[i];
    if (f.kind != kind || f.opens > tick_ ||
        std::any_of(responses_.begin(), responses_.end(),
                    [i](const auto &c) { return c.station == i; }))
      continue;
    RoadCurb station{f.frontage, f.sample, f.gate};
    auto route = drive_route(*this, station, target, speed);
    double time = route.back().end_time;
    if (time >= fastest)
      continue;
    fastest = time;
    auto back = drive_route(*this, target, station, speed);
    int arrival = tick_ + int(std::ceil(time)), leaving = arrival + 120;
    best = {i,
            lot,
            tick_,
            arrival,
            leaving,
            leaving + int(std::ceil(back.back().end_time)),
            std::move(route),
            std::move(back)};
  }
  if (std::isfinite(fastest))
    responses_.push_back(std::move(best));
}
} // namespace city
