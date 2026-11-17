#include "sim/city.hpp"
#include <algorithm>
#include <cmath>
#include <limits>
#include <random>

namespace city {
namespace {
constexpr double bin_size = 64.;
auto bin(Point p) {
  return std::pair{int(std::floor(p.x / bin_size)),
                   int(std::floor(p.z / bin_size))};
}
double square_distance(Point a, Point b) {
  double x = a.x - b.x, z = a.z - b.z;
  return x * x + z * z;
}
double turn(Point from, Point at, Point to) {
  double ax = at.x - from.x, az = at.z - from.z, bx = to.x - at.x,
         bz = to.z - at.z;
  return (ax * bx + az * bz) / (std::hypot(ax, az) * std::hypot(bx, bz));
}
uint32_t lot_hash(uint32_t key) {
  key ^= key >> 16;
  key *= 0x7feb352du;
  key ^= key >> 15;
  key *= 0x846ca68bu;
  return key ^ (key >> 16);
}
double orient(Point a, Point b, Point p) {
  return (b.x - a.x) * (p.z - a.z) - (b.z - a.z) * (p.x - a.x);
}
bool intersects(Point a, Point b, Point c, Point d) {
  return orient(a, b, c) * orient(a, b, d) < 0. &&
         orient(c, d, a) * orient(c, d, b) < 0.;
}
} // namespace

// Seed a blue-noise survey of dry potential junctions, not a road map.
// Only the demand planner decides which sites or links are ever built.
void City::survey_land() {
  auto insert = [&](Point p, int node) {
    int id = int(survey_.size());
    survey_bins_[bin(p)].push_back(id);
    survey_.push_back({p, node, {}, false});
    return id;
  };
  for (int i = 0; i < int(nodes_.size()); ++i)
    junction_sites_.push_back(insert(nodes_[i].pos, i));
  // Protect a handful of continuous approaches before scattering local
  // junctions. They continue the founding main street and its collector.
  // Curves respond to grades; a river crossing needs a dry landing.
  std::vector<std::vector<int>> spines;
  for (int i = 0; i < int(nodes_.size()); ++i) {
    const auto &n = nodes_[i];
    if (n.edges.size() >= 4)
      continue;
    bool main_tip = std::abs(n.col) == 2 && n.row == 0;
    bool collector_tip = n.col == 0 && std::abs(n.row) == 2;
    if (!main_tip && !collector_tip)
      continue;
    RoadClass rank = main_tip ? RoadClass::Arterial : RoadClass::Collector;
    Point behind = street_point(main_tip ? n.col * .5 : n.col,
                                collector_tip ? n.row * .5 : n.row);
    Point at = n.pos;
    double bearing = std::atan2(at.z - behind.z, at.x - behind.x);
    int from = junction_sites_[i];
    auto &spine = spines.emplace_back(1, from);
    for (int leg = 0; leg < 7; ++leg) {
      double least = std::numeric_limits<double>::infinity(), heading = 0.;
      Point next{};
      for (double angle : {0., -.19, .19, -.39, .39, -.59, .59}) {
        double yaw = bearing + angle;
        for (double span : {53., 72., 91.}) {
          Point p{at.x + span * std::cos(yaw), at.z + span * std::sin(yaw)};
          if (std::abs(p.x) > half_width - 20 ||
              std::abs(p.z) > half_depth - 20 || site_.inland_water(p) ||
              site_.elevation(p) < 2.7)
            continue;
          double phase = std::sin(at.x * .012 + at.z * .009 + grid_phase_);
          double cost = std::abs(height(at) - height(p)) * .72 +
                        std::abs(angle - .21 * phase) * 6. +
                        (span - 53.) * .035;
          if (cost < least) {
            least = cost;
            heading = yaw;
            next = p;
          }
        }
      }
      if (!std::isfinite(least))
        break;
      if (std::any_of(survey_.begin(), survey_.end(),
                      [&](auto &s) { return distance(s.pos, next) < 30.; }))
        break;
      int to = insert(next, -1);
      feeders_[std::minmax(from, to)] = rank;
      spine.push_back(to);
      bearing = heading;
      at = next;
      from = to;
    }
  }
  // Side streets share the bends of the avenue they serve. Staggered
  // cross streets leave long blocks along the spine and shorter residential
  // blocks behind it. Each right of way still needs demand and clearance.
  for (const auto &spine : spines) {
    for (int side : {-1, 1}) {
      std::array<int, 2> previous{-1, -1};
      for (int k = 1; k < int(spine.size()); ++k) {
        Point at = survey_[spine[k]].pos, behind = survey_[spine[k - 1]].pos;
        Point ahead =
            survey_[spine[std::min(k + 1, int(spine.size()) - 1)]].pos;
        double angle = std::atan2(ahead.z - behind.z, ahead.x - behind.x);
        double phase = grid_phase_ + spine.front() * .65 + side * .9 + k * .49;
        int inner = spine[k];
        for (int row = 0; row < 2; ++row) {
          double depth = (row + 1) * (46. + 7. * std::sin(phase));
          double stagger = (row + 1) * 9. * std::cos(phase * .85);
          Point p{at.x - side * depth * std::sin(angle) +
                      stagger * std::cos(angle),
                  at.z + side * depth * std::cos(angle) +
                      stagger * std::sin(angle)};
          if (site_.inland_water(p) || site_.elevation(p) < 2.7 ||
              std::abs(height(p) - height(at)) > depth * .18 ||
              std::any_of(survey_.begin(), survey_.end(), [&](const auto &s) {
                return distance(p, s.pos) < 29.;
              })) {
            previous[row] = -1;
            inner = -1;
            continue;
          }
          int id = insert(p, -1);
          if (previous[row] >= 0 &&
              distance(survey_[previous[row]].pos, p) < 99.)
            feeders_[std::minmax(previous[row], id)] = RoadClass::Local;
          if (inner >= 0 && (row || (k + side + 1) % 3 != 1))
            feeders_[std::minmax(inner, id)] = RoadClass::Local;
          previous[row] = id;
          inner = id;
        }
      }
    }
  }
  std::mt19937 rng(seed_ ^ 0x854d986fu);
  auto unit = [&] { return double(rng() >> 8) / 16777216.; };
  for (int i = 0; i < 41000; ++i) {
    Point p{(2. * unit() - 1.) * (half_width - 19.),
            (2. * unit() - 1.) * (half_depth - 19.)};
    if (site_.inland_water(p) || site_.elevation(p) < 2.5)
      continue;
    // Larger spacing in the hinterland leaves room for longer district roads.
    double spacing =
        30. + 8. * std::min(1., distance(p, workshop_site_) / 510.);
    auto [x, z] = bin(p);
    bool clear = true;
    for (int u = x - 1; u <= x + 1 && clear; ++u)
      for (int v = z - 1; v <= z + 1 && clear; ++v) {
        auto it = survey_bins_.find({u, v});
        if (it == survey_bins_.end())
          continue;
        for (int id : it->second)
          if (square_distance(p, survey_[id].pos) < spacing * spacing) {
            clear = false;
            break;
          }
      }
    if (clear)
      insert(p, -1);
  }
}

void City::survey_neighbours(int origin) {
  auto &site = survey_[origin];
  if (site.surveyed)
    return;
  site.surveyed = true;
  auto [x, z] = bin(site.pos);
  std::vector<int> nearby;
  for (int u = x - 2; u <= x + 2; ++u)
    for (int v = z - 2; v <= z + 2; ++v) {
      auto it = survey_bins_.find({u, v});
      if (it != survey_bins_.end())
        nearby.insert(nearby.end(), it->second.begin(), it->second.end());
    }
  for (int id : nearby) {
    auto end = survey_[id].pos;
    double length = distance(site.pos, end);
    if (id == origin || length < 22. || length > 105.)
      continue;
    // Leave a shared clear corridor. More distant existing junctions across
    // water are still eligible when the intervening land cannot be settled.
    bool clear = true;
    for (int other : nearby) {
      if (other == id || other == origin)
        continue;
      auto p = survey_[other].pos;
      if (square_distance(site.pos, p) < length * length &&
          square_distance(end, p) < length * length &&
          segment_distance(p, site.pos, end) < std::min(length * .32, 22.)) {
        clear = false;
        break;
      }
    }
    if (clear || feeders_.count(std::minmax(origin, id)))
      site.neighbours.push_back(id);
  }
}

bool City::grow_surveyed(bool feeder_only) {
  if (survey_.empty())
    survey_land();
  travel_demand_.resize(nodes_.size());
  struct Proposal {
    double score;
    int from, site;
    RoadClass type;
  };
  std::vector<Proposal> proposals;
  auto [width, depth] = planning_extent();
  for (int i = 0; i < int(nodes_.size()); ++i) {
    const auto &n = nodes_[i];
    if (n.edges.size() >= 4 || !connected(i))
      continue;
    int origin = junction_sites_[i];
    survey_neighbours(origin);
    for (int site : survey_[origin].neighbours) {
      survey_neighbours(site);
      auto end = survey_[site].pos;
      int target = survey_[site].junction;
      if (std::abs(end.x) > width - 17. || std::abs(end.z) > depth - 17.)
        continue;
      if (target >= 0 && (target < i || nodes_[target].edges.size() >= 4))
        continue;
      double continuation = -1., closest = 1.,
             visits = travel_demand_[i].visits;
      RoadClass approach = RoadClass::Local;
      bool duplicate = false, triangle = false;
      for (int edge : n.edges) {
        const auto &r = roads_[edge];
        int j = r.a == i ? r.b : r.a;
        duplicate |= j == target;
        double dot = turn(r.path[r.a == i ? 1 : 7], n.pos, end);
        closest = std::min(closest, dot);
        if (dot > continuation) {
          continuation = dot;
          approach = r.type;
        }
        visits += travel_demand_[j].visits * .18;
        if (target >= 0)
          for (int link : nodes_[target].edges)
            triangle |= roads_[link].a == j || roads_[link].b == j;
      }
      if (duplicate || closest < -.78 || triangle)
        continue;
      if (target >= 0) {
        bool crowded = false;
        for (int e : nodes_[target].edges) {
          auto &r = roads_[e];
          if (turn(r.path[r.a == target ? 1 : 7], end, n.pos) < -.78)
            crowded = true;
        }
        if (crowded)
          continue;
      }
      auto feeder = feeders_.find(std::minmax(origin, site));
      if (feeder_only && (feeder == feeders_.end() ||
                          origin >= int(nodes_.size()) || n.edges.size() >= 4))
        continue;
      uint32_t key =
          lot_hash(seed_ ^ uint32_t(std::min(origin, site)) * 2654435761u ^
                   uint32_t(std::max(origin, site)) * 1597334677u);
      bool through = continuation > .75;
      RoadClass type = RoadClass::Local;
      if (through && approach == RoadClass::Arterial)
        type = RoadClass::Arterial;
      else if ((through && approach == RoadClass::Collector) ||
               (visits > 250 && (key % 7) == 0))
        type = RoadClass::Collector;
      if (feeder != feeders_.end())
        type = feeder->second;
      auto blocked = blocked_width_.find(std::minmax(origin, site));
      if (blocked != blocked_width_.end() && int(type) >= blocked->second)
        continue;
      double length = distance(n.pos, end);
      double grade = std::abs(height(end) - height(n.pos)) / length;
      double score = 2.7 * std::log1p(visits) + 2.4 * continuation -
                     40. * grade + double(key >> 8) / 16777216. * 3.2 -
                     .014 * length;
      if (type == RoadClass::Arterial)
        score += 1.7;
      if (feeder != feeders_.end())
        score += type == RoadClass::Local ? 5. : 5.5;
      // Prefer filling the space between occupied streets before extending
      // an isolated tip. Unoccupied survey points contribute no demand.
      int nearby = 0;
      for (int next : survey_[site].neighbours)
        if (survey_[next].junction >= 0)
          ++nearby;
      score += 1.8 * std::min(nearby, 4);
      if (n.edges.size() == 1)
        score += 2.8;
      if (target >= 0) {
        double existing = 0.;
        for (int e : road_route(i, target))
          existing += roads_[e].lengths.back();
        score += std::clamp(existing / length - 1., 0., 5.) * 1.5;
        if (nodes_[target].edges.size() == 1)
          score += 2.;
      }
      if (n.edges.size() == 3)
        score -= 3.;
      proposals.push_back({score, i, site, type});
    }
  }
  std::stable_sort(proposals.begin(), proposals.end(),
                   [](auto a, auto b) { return a.score > b.score; });
  for (auto proposal : proposals) {
    int a = proposal.from, site = proposal.site, b = survey_[site].junction;
    Point start = nodes_[a].pos, end = survey_[site].pos;
    double length = distance(start, end);
    Point normal{(start.z - end.z) / length, (end.x - start.x) / length};
    // Bow towards the gentler contour. Blend in the approach tangent for
    // through roads; snapped endpoints stay exact in both travel directions.
    Point mid{(start.x + end.x) * .5, (start.z + end.z) * .5};
    double bend =
        std::clamp((height({mid.x - normal.x * 7., mid.z - normal.z * 7.}) -
                    height({mid.x + normal.x * 7., mid.z + normal.z * 7.})) *
                       .9,
                   -5., 5.);
    bend += std::sin(mid.x * .017 + mid.z * .012 + grid_phase_) * length * .055;
    double entry = 0., best = .64;
    for (int e : nodes_[a].edges) {
      auto &r = roads_[e];
      Point prev = r.path[r.a == a ? 1 : 7];
      double align = turn(prev, start, end);
      if (align > best) {
        best = align;
        entry =
            ((start.x - prev.x) * normal.x + (start.z - prev.z) * normal.z) /
            distance(start, prev) * length * .68;
      }
    }
    Road road{};
    road.surveyed = true;
    road.a = a;
    road.type = proposal.type;
    bool dry = true, water = false, viable = true;
    for (int k = 0; k <= 8; ++k) {
      double t = k / 8.;
      double offset = t * (1. - t) * (4. * bend + entry * (1. - t));
      Point p{std::lerp(start.x, end.x, t) + offset * normal.x,
              std::lerp(start.z, end.z, t) + offset * normal.z};
      road.path[k] = p;
      double elevation = site_.elevation(p);
      dry &= !site_.inland_water(p) && elevation > 1.8;
      water |= site_.inland_water(p) || elevation <= 0.;
      if (k) {
        auto prev = road.path[k - 1];
        double span = distance(prev, p);
        road.lengths[k] = road.lengths[k - 1] + span;
        viable &= std::abs(height(prev) - height(p)) < span * .24;
      }
    }
    if (!dry) {
      if (!water || population_ < 3500 ||
          std::abs(height(start) - height(end)) > .12 * length)
        continue;
      if (std::any_of(roads_.begin(), roads_.end(), [&](auto &r) {
            return r.bridge && distance(r.path[4], mid) < 120.;
          }))
        continue;
      road.bridge = true;
      road.type = RoadClass::Arterial;
      viable = true;
    }
    double half = road_width(road.type) * .5;
    for (int k = 1; k <= 8 && viable; ++k) {
      Point p = road.path[k - 1], q = road.path[k];
      for (const auto &lot : buildings_)
        if (square_distance(mid, lot.pos) <
                (length * .6 + 25.) * (length * .6 + 25.) &&
            lot.clearance(p, q) < half + 4.3) {
          viable = false;
          break;
        }
      for (const auto &f : facilities_) {
        double space = (road.type == RoadClass::Arterial &&
                        f.kind == FacilityKind::Playground)
                           ? std::max(18., f.radius + 1.5)
                           : f.radius + 1.5;
        if (segment_distance(f.center, p, q) < half + space ||
            segment_distance(f.gate, p, q) < half + 1.4)
          viable = false;
      }
      for (const auto &r : roads_) {
        if (square_distance(mid, r.path[4]) >
            std::pow(length * .6 + r.lengths.back() * .6 + 16., 2))
          continue;
        bool shared = r.a == a || r.b == a || r.a == b || r.b == b;
        for (int j = 1; j <= 8; ++j) {
          Point u = r.path[j - 1], v = r.path[j];
          if (intersects(p, q, u, v) ||
              (!shared &&
               std::min({segment_distance(p, u, v), segment_distance(q, u, v),
                         segment_distance(u, p, q),
                         segment_distance(v, p, q)}) <
                   half + road_width(r.type) * .5 + 2.)) {
            viable = false;
            break;
          }
        }
        if (!viable)
          break;
      }
    }
    if (!viable) {
      auto key = std::minmax(junction_sites_[a], site);
      auto [it, inserted] = blocked_width_.emplace(key, int(road.type));
      if (!inserted)
        it->second = std::min(it->second, int(road.type));
      continue;
    }
    if (b < 0) {
      b = int(nodes_.size());
      survey_[site].junction = b;
      junction_sites_.push_back(site);
      nodes_.push_back(
          {int(std::round(end.x)), int(std::round(end.z)), end, {}});
    }
    road.b = b;
    commit_road(a, b, road);
    record(road.bridge                         ? "Bridge construction began"
           : road.type == RoadClass::Arterial  ? "Boulevard construction began"
           : road.type == RoadClass::Collector ? "Collector construction began"
                                               : "Street construction began");
    return true;
  }
  return false;
}
} // namespace city
