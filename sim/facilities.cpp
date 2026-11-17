#include "sim/city.hpp"
#include <algorithm>
#include <cmath>
#include <limits>
#include <queue>

namespace city {
namespace {
// Bounded shortest walks from a frontage sample through the open street graph.
std::vector<double> access_distances(const City &city, int edge, int sample) {
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
    if (d != cost[n] || d >= 110.)
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
    if (distance(old.center, f.center) < (f.kind == old.kind ? 60. : 29.))
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
  for (int k = 0; k < 8; ++k) {
    double a = k * 3.141592653589793 / 4.;
    Point p{f.center.x + f.radius * std::cos(a),
            f.center.z + f.radius * std::sin(a)};
    if (city.site().inland_water(p) || city.site().elevation(p) < 1.4 ||
        std::abs(p.x) > half_width - 1 || std::abs(p.z) > half_depth - 1)
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
} // namespace city
