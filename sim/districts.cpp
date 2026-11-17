#include "sim/city.hpp"
#include <algorithm>
#include <cmath>

namespace city {
Point Building::centre(double depth) const {
  return {pos.x + std::sin(yaw) * depth * .5,
          pos.z + std::cos(yaw) * depth * .5};
}

double Building::clearance(Point a, Point b) const {
  if (wing == 0.)
    return segment_distance(pos, a, b);
  double dx = std::cos(yaw) * wing, dz = -std::sin(yaw) * wing;
  Point left{pos.x - dx, pos.z - dz}, right{pos.x + dx, pos.z + dz};
  if (rear == 0.)
    return segment_clearance(a, b, left, right);
  auto inside = [&](Point p) {
    double x = p.x - pos.x, z = p.z - pos.z;
    double back = (x * std::sin(yaw) + z * std::cos(yaw)) / rear;
    return std::abs(x * std::cos(yaw) - z * std::sin(yaw)) <= wing &&
           back >= 0. && back <= 1.;
  };
  if (inside(a) || inside(b))
    return 0.;
  Point l{left.x + std::sin(yaw) * rear, left.z + std::cos(yaw) * rear};
  Point r{right.x + std::sin(yaw) * rear, right.z + std::cos(yaw) * rear};
  return std::min(
      {segment_clearance(a, b, left, right), segment_clearance(a, b, l, r),
       segment_clearance(a, b, l, left), segment_clearance(a, b, r, right)});
}

void City::reserve_frontage(Building &b) const {
  if (b.rear != 0.)
    return;
  // Keep the front door fixed during a redevelopment. Try wider frontage,
  // then let taller buildings occupy a deeper floor plate towards the yard.
  for (double wing : {7., 4.5, 2.5}) {
    if (wing <= b.wing)
      break;
    double dx = std::cos(b.yaw) * wing, dz = -std::sin(b.yaw) * wing;
    Point a{b.pos.x - dx, b.pos.z - dz}, z{b.pos.x + dx, b.pos.z + dz};
    if (site_.inland_water(a) || site_.inland_water(z) ||
        site_.elevation(a) < 2.5 || site_.elevation(z) < 2.5 ||
        std::abs(height(a) - height(z)) > wing * .21)
      continue;
    bool clear = true;
    for (const auto &other : buildings_)
      if (&other != &b && distance(other.pos, b.pos) < 36. &&
          other.clearance(a, z) < 11.6) {
        clear = false;
        break;
      }
    for (const auto &road : roads_) {
      if (!clear)
        break;
      if (distance(road.path[4], b.pos) > road.lengths.back() * .58 + 25.)
        continue;
      for (int k = 1; k <= 8; ++k)
        if (segment_clearance(a, z, road.path[k - 1], road.path[k]) <
            road_width(road.type) * .5 + 4.3) {
          clear = false;
          break;
        }
    }
    for (const auto &f : facilities_)
      if (segment_distance(f.center, a, z) < f.radius + 6.4 ||
          segment_clearance(a, z, f.gate, roads_[f.frontage].path[f.sample]) <
              6.4)
        clear = false;
    for (const auto &[ends, rank] : feeders_)
      if (segment_clearance(a, z, survey_[ends.first].pos,
                            survey_[ends.second].pos) <
          road_width(rank) * .5 + 4.3)
        clear = false;
    if (clear) {
      b.wing = wing;
      break;
    }
  }
  if (b.wing == 0. || target_floors(b) < 10)
    return;
  const auto curb = roads_[b.frontage].path[b.sample];
  const double side = (b.pos.x - curb.x) * std::sin(b.yaw) +
                                  (b.pos.z - curb.z) * std::cos(b.yaw) >
                              0.
                          ? 1.
                          : -1.;
  for (double depth : {8., 4.}) {
    Building parcel = b;
    parcel.rear = side * depth;
    Point center = parcel.centre(2. * parcel.rear);
    double dx = std::cos(b.yaw) * b.wing, dz = -std::sin(b.yaw) * b.wing;
    Point l{center.x - dx, center.z - dz}, r{center.x + dx, center.z + dz};
    bool clear = true;
    for (auto p : {l, r, center}) {
      if (site_.inland_water(p) || site_.elevation(p) < 2.5 ||
          std::abs(height(p) - height(b.pos)) > 1.3)
        clear = false;
    }
    for (const auto &other : buildings_) {
      if (&other == &b || distance(other.pos, b.pos) > 46.)
        continue;
      Point front = other.pos, back = other.centre(2. * other.rear);
      double ox = std::cos(other.yaw) * other.wing,
             oz = -std::sin(other.yaw) * other.wing;
      Point a{front.x - ox, front.z - oz}, z{front.x + ox, front.z + oz};
      Point c{back.x - ox, back.z - oz}, d{back.x + ox, back.z + oz};
      if (std::min({parcel.clearance(a, z), parcel.clearance(c, d),
                    parcel.clearance(a, c), parcel.clearance(z, d),
                    other.clearance(l, r)}) < 11.6)
        clear = false;
    }
    for (const auto &road : roads_) {
      if (!clear)
        break;
      if (distance(road.path[4], b.pos) > road.lengths.back() * .6 + 36.)
        continue;
      for (int k = 1; k <= 8; ++k)
        if (parcel.clearance(road.path[k - 1], road.path[k]) <
            road_width(road.type) * .5 + 4.3) {
          clear = false;
          break;
        }
    }
    for (const auto &f : facilities_)
      if (parcel.clearance(f.center, f.center) < f.radius + 6.4 ||
          parcel.clearance(f.gate, roads_[f.frontage].path[f.sample]) < 6.4)
        clear = false;
    for (const auto &[ends, rank] : feeders_)
      if (parcel.clearance(survey_[ends.first].pos, survey_[ends.second].pos) <
          road_width(rank) * .5 + 4.3)
        clear = false;
    if (clear) {
      b.rear = parcel.rear;
      break;
    }
  }
}

void City::choose_main_street_corner() {
  const auto &occupied = life_.occupancies();
  double best = 0.;
  for (int i = 0; i < int(occupied.size()); ++i) {
    const auto &lot = buildings_[i];
    if (lot.use != Use::Shops || occupied[i].hired == 0)
      continue;
    const auto &r = roads_[lot.frontage];
    if (r.type == RoadClass::Local || r.opens > tick_)
      continue;
    auto degree = std::max(nodes_[r.a].edges.size(), nodes_[r.b].edges.size());
    double visits = frontage_visits(lot.frontage);
    if (degree < 3 || visits < 95.)
      continue;
    double access = 1.;
    for (const auto &stop : life_.transit().stops())
      if (distance(stop.platform.pos, lot.pos) < 55.) {
        access = 1.25;
        break;
      }
    double score = access * std::sqrt(visits) * occupied[i].hired;
    if (score > best) {
      best = score;
      main_street_corner_ = i;
    }
  }
}

void City::locate_centres() {
  // A cluster needs established jobs and accessible streets. Once established
  // its centre persists, so adjacent parcels can redevelop over many years.
  if (population_ < 3100 || centres_.size() >= 2 ||
      (!centres_.empty() && population_ < 30000))
    return;
  struct District {
    double jobs = 0.;
    Point sum{};
  };
  std::map<std::pair<int, int>, District> districts;
  const auto &places = life_.occupancies();
  for (size_t i = 0; i < places.size(); ++i) {
    const auto &b = buildings_[i];
    if (b.use != Use::Shops || places[i].hired == 0)
      continue;
    auto &d = districts[{int(std::floor(b.pos.x / 95.)),
                         int(std::floor(b.pos.z / 95.))}];
    double weight = places[i].hired *
                    (roads_[b.frontage].type == RoadClass::Local ? .65 : 1.);
    d.sum.x += b.pos.x * weight;
    d.sum.z += b.pos.z * weight;
    d.jobs += weight;
  }
  Point best{};
  double highest = centres_.empty() ? 30. : 180.;
  for (auto &[cell, d] : districts) {
    Point at{d.sum.x / d.jobs, d.sum.z / d.jobs};
    if (!centres_.empty() && distance(at, centres_.front()) < 255.)
      continue;
    double score = d.jobs;
    for (const auto &stop : life_.transit().stops())
      if (distance(stop.platform.pos, at) < 75.) {
        score *= 1.35;
        break;
      }
    if (score > highest) {
      highest = score;
      best = at;
    }
  }
  if (highest > (centres_.empty() ? 30. : 180.))
    centres_.push_back(best);
}
} // namespace city
