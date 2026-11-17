#include "sim/city.hpp"
#include <algorithm>
#include <cmath>

namespace city {
// Count the daily round trips in residents' schedules. Nearby junctions share
// frontage demand, while the bearing of each trip distinguishes travel axes.
void City::survey_trips() {
  std::vector<TravelDemand> lots(buildings_.size());
  travel_demand_.assign(nodes_.size(), {});
  auto trip = [&](int from, int to) {
    if (from < 0 || to < 0 || from == to)
      return;
    auto a = buildings_[from].pos, b = buildings_[to].pos;
    double dx = std::abs(a.x - b.x), dz = std::abs(a.z - b.z);
    double length = std::max(1., dx + dz);
    for (int id : {from, to}) {
      lots[id].visits += 2.;
      lots[id].east_west += 2. * dx / length;
      lots[id].north_south += 2. * dz / length;
    }
  };
  for (const auto &person : life_.people()) {
    trip(person.home, person.work);
    trip(person.work < 0 ? person.home : person.work, person.shop);
  }
  for (size_t i = 0; i < lots.size(); ++i) {
    const auto &road = roads_[buildings_[i].frontage];
    for (int end : {road.a, road.b}) {
      travel_demand_[end].visits += .5 * lots[i].visits;
      travel_demand_[end].east_west += .5 * lots[i].east_west;
      travel_demand_[end].north_south += .5 * lots[i].north_south;
    }
  }
}

double City::frontage_visits(int edge) const {
  const auto &road = roads_[edge];
  auto visits = [&](int node) {
    return node < int(travel_demand_.size()) ? travel_demand_[node].visits : 0.;
  };
  return .5 * (visits(road.a) + visits(road.b));
}

bool City::grow() {
  struct Candidate {
    double score;
    int origin, col, row;
    RoadClass type;
    bool bridge;
  };
  // A second project in this planning interval can start at a new junction.
  travel_demand_.resize(nodes_.size());
  const auto &demand = travel_demand_;
  std::vector<Candidate> candidates;
  auto dry = [&](Point p) {
    return !site_.inland_water(p) && site_.elevation(p) > 1.8;
  };
  for (int i = 0; i < int(nodes_.size()); ++i) {
    const auto &n = nodes_[i];
    if (!connected(i) || n.edges.size() == 4)
      continue;
    for (auto [dc, dr] : std::array<std::pair<int, int>, 4>{
             {{1, 0}, {0, 1}, {-1, 0}, {0, -1}}}) {
      bool taken = false;
      RoadClass approach = RoadClass::Local;
      double nearby = 0;
      for (int e : n.edges) {
        const auto &road = roads_[e];
        int j = road.a == i ? road.b : road.a;
        const auto &other = nodes_[j];
        int dot = (other.col - n.col) * dc + (other.row - n.row) * dr;
        taken |= dot > 0;
        if (dot < 0)
          approach = road.type;
        nearby += demand[j].visits * (road.bridge ? 4. : 1.);
      }
      if (taken)
        continue;
      int c = n.col + dc, r = n.row + dr;
      auto p = street_point(c, r);
      // Check the whole first span: a narrow stream can run between dry ends.
      bool bridge = false;
      for (int k = 1; k <= 8; ++k)
        bridge |= !dry(street_point(n.col + dc * k / 8., n.row + dr * k / 8.));
      if (bridge) {
        if (population_ < 3500)
          continue;
        int span = 1;
        while (!dry(p) && span < 4) {
          ++span;
          c += dc;
          r += dr;
          p = street_point(c, r);
        }
        if (!dry(p) ||
            std::abs(height(n.pos) - height(p)) > distance(n.pos, p) * .12)
          continue;
        // Keep new crossings apart and avoid treating a shallow dry slope as
        // water.
        bool water = false, crowded = false;
        for (int k = 1; k < 8; ++k) {
          Point sample = street_point(n.col + dc * span * k / 8.,
                                      n.row + dr * span * k / 8.);
          water |= site_.inland_water(sample) || site_.elevation(sample) <= 0.;
        }
        for (auto &existing : roads_)
          if (existing.bridge &&
              segment_distance(existing.path[4], n.pos, p) < 135.)
            crowded = true;
        if (!water || crowded)
          continue;
      }
      if (std::abs(p.x) > half_width - 18 || std::abs(p.z) > half_depth - 18)
        continue;
      int b = find_node(c, r);
      if (b >= 0 && b < i)
        continue;
      double visits = demand[i].visits + .22 * nearby;
      double aligned = dc ? demand[i].east_west : demand[i].north_south;
      auto type = RoadClass::Local;
      if (bridge || (approach == RoadClass::Arterial && visits > 100.) ||
          (approach == RoadClass::Collector && aligned > 210.))
        type = RoadClass::Arterial;
      else if (aligned > 125. ||
               (approach != RoadClass::Local && visits > 100.))
        type = RoadClass::Collector;
      double grade = std::abs(height(p) - height(n.pos)) / distance(p, n.pos);
      // A new link can open several dry blocks. This also credits the vacant
      // landing beyond a bridge before its first households have moved in.
      int open_blocks = 0;
      for (auto [x, y] : std::array<std::pair<int, int>, 4>{
               {{1, 0}, {0, 1}, {-1, 0}, {0, -1}}}) {
        auto next = street_point(c + x, r + y);
        if (find_node(c + x, r + y) < 0 && dry(next) &&
            std::abs(next.x) < half_width - 18 &&
            std::abs(next.z) < half_depth - 18)
          ++open_blocks;
      }
      double score = 2.4 * std::log1p(visits) + 1.3 * std::log1p(aligned) -
                     32. * grade + (b >= 0 ? 1.3 : 0.) + 1.3 * open_blocks -
                     (bridge ? 1.5 : 0.) + double(draw() >> 8) / 16777216. * 4.;
      candidates.push_back({score, i, c, r, type, bridge});
    }
  }
  std::stable_sort(candidates.begin(), candidates.end(),
                   [](auto a, auto b) { return a.score > b.score; });
  for (auto candidate : candidates) {
    const auto &n = nodes_[candidate.origin];
    auto type = candidate.type;
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
      viable = candidate.bridge ||
               (!site_.inland_water(p) && site_.elevation(p) > 1.8 &&
                site_.elevation(prev) > 1.8 &&
                std::abs(height(p) - height(prev)) / distance(prev, p) < .24);
      for (const auto &f : facilities_)
        if (segment_distance(f.center, prev, p) <
                road_width(type) * .5 +
                    (type == RoadClass::Arterial &&
                             f.kind == FacilityKind::Playground
                         ? 18.
                         : f.radius + 1.5) ||
            segment_distance(f.gate, prev, p) < road_width(type) * .5 + 1.4)
          viable = false;
      prev = p;
    }
    if (!viable)
      continue;
    int edge = add_road(candidate.origin, candidate.col, candidate.row, type,
                        candidate.bridge);
    record(roads_[edge].bridge            ? "Bridge construction began"
           : type == RoadClass::Arterial  ? "Boulevard construction began"
           : type == RoadClass::Collector ? "Collector construction began"
                                          : "Street construction began");
    return true;
  }
  return false;
}
} // namespace city
