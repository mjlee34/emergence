#include "sim/city.hpp"
#include <algorithm>
#include <cmath>
#include <functional>
#include <limits>

namespace city {
PersonPose follow_path(const Footpath &path, double progress, bool forward,
                       double offset) {
  double d = std::clamp(forward ? progress : 1. - progress, 0., 1.) *
             path.lengths.back();
  auto it = std::lower_bound(path.lengths.begin() + 1, path.lengths.end(), d);
  size_t k =
      std::min(size_t(it - path.lengths.begin()), path.points.size() - 1);
  auto a = path.points[k - 1], b = path.points[k];
  double len = path.lengths[k] - path.lengths[k - 1];
  double t = (d - path.lengths[k - 1]) / len;
  double dx = b.pos.x - a.pos.x, dz = b.pos.z - a.pos.z;
  // Interpolate the lane tangent across neighbouring samples as a vehicle
  // turns.
  double tx = dx / len, tz = dz / len;
  size_t neighbour = t < .5 ? (k >= 2 ? k - 2 : k - 1)
                            : std::min(k + 1, path.points.size() - 1);
  auto p = path.points[neighbour].pos;
  Point turn = t < .5 ? Point{a.pos.x - p.x, a.pos.z - p.z}
                      : Point{p.x - b.pos.x, p.z - b.pos.z};
  double span = std::hypot(turn.x, turn.z);
  if (span > .001) {
    double weight = std::abs(t - .5);
    tx = std::lerp(tx, turn.x / span, weight);
    tz = std::lerp(tz, turn.z / span, weight);
  }
  return {{std::lerp(a.pos.x, b.pos.x, t) - dz * offset / len,
           std::lerp(a.pos.z, b.pos.z, t) + dx * offset / len},
          std::lerp(a.height, b.height, t),
          std::atan2(forward ? tx : -tx, forward ? tz : -tz)};
}
namespace {
// Pick a closed circuit through the founding market junction. Reward coverage
// and arterial/collector frontage so the service reaches several
// neighbourhoods.
std::vector<int> town_circuit(const City &c) {
  std::vector<int> path{0}, best;
  double highest = -1;
  std::function<void(int, double)> visit = [&](int node, double score) {
    for (int edge : c.nodes()[node].edges) {
      const auto &r = c.roads()[edge];
      int next = node == r.a ? r.b : r.a;
      double weight = distance(c.nodes()[node].pos, c.nodes()[next].pos) *
                      (r.type == RoadClass::Local ? .76 : 1.);
      if (next == 0 && path.size() >= 5 && score + weight > highest) {
        highest = score + weight;
        best = path;
      } else if (path.size() < 8 &&
                 std::find(path.begin(), path.end(), next) == path.end()) {
        path.push_back(next);
        visit(next, score + weight);
        path.pop_back();
      }
    }
  };
  visit(0, 0.);
  return best;
}
void add_point(Footpath &track, WalkPoint p) {
  double d =
      track.points.empty() ? 0. : distance(track.points.back().pos, p.pos);
  if (!track.points.empty() && d < .001)
    return;
  track.points.push_back(p);
  track.lengths.push_back(track.lengths.empty() ? 0.
                                                : track.lengths.back() + d);
}
} // namespace
void Transit::establish(const City &c) {
  auto nodes = town_circuit(c);
  if (nodes.empty())
    return;
  int n = nodes.size();
  std::vector<int> edges;
  for (int i = 0; i < n; ++i) {
    int a = nodes[i], b = nodes[(i + 1) % n];
    auto &connected = c.nodes()[a].edges;
    edges.push_back(
        *std::find_if(connected.begin(), connected.end(), [&](int e) {
          auto &r = c.roads()[e];
          return r.a == b || r.b == b;
        }));
  }
  for (int direction : {0, 1}) {
    int base = stops_.size();
    std::vector<WalkPoint> lane;
    std::vector<int> indices;
    for (int k = 0; k < n; ++k) {
      int i = direction ? n - 1 - k : k;
      int edge = edges[i];
      auto &r = c.roads()[edge];
      int origin = nodes[direction ? (i + 1) % n : i];
      int side = origin == r.a ? 1 : -1;
      // Join adjacent lane tangents across each intersection.
      for (int j = 1; j <= 7; ++j) {
        int sample = side > 0 ? j : 8 - j;
        double d =
            side > 0 ? r.lengths[sample] : r.lengths.back() - r.lengths[sample];
        Vehicle vehicle{edge, origin, 0, d, .9, {}};
        double yaw;
        Point p = c.vehicle_position(vehicle, yaw);
        if (r.type == RoadClass::Local) {
          double curb = road_width(r.type) * .037;
          p.x += std::sin(yaw) * curb;
          p.z += std::cos(yaw) * curb;
        }
        lane.push_back({p, c.street_height(r, p)});
        if (i % 2 == 0 && j == 4) {
          auto center = r.path[4];
          double width = road_width(r.type) * .5 + .8;
          Point platform{center.x + std::sin(yaw) * width,
                         center.z + std::cos(yaw) * width};
          indices.push_back(int(lane.size() - 1));
          stops_.push_back({edge,
                            side,
                            0,
                            direction,
                            {platform, c.height(platform) + .38},
                            yaw,
                            0,
                            0,
                            {}});
        }
      }
    }
    double total = 0;
    int count = indices.size();
    for (int i = 0; i < count; ++i) {
      auto &stop = stops_[base + i];
      stop.next = base + (i + 1) % count;
      int k = indices[i];
      add_point(stop.track, lane[k]);
      do {
        k = (k + 1) % lane.size();
        add_point(stop.track, lane[k]);
      } while (k != indices[(i + 1) % count]);
      total += stop.track.lengths.back();
    }
    double t = 0;
    for (int i = base; i < int(stops_.size()); ++i) {
      auto &s = stops_[i];
      s.arrival = t;
      s.departure = t + 2.;
      t = s.departure + (cycle - 2. * count) * s.track.lengths.back() / total;
    }
  }
}
BusPosition Transit::bus(int id, double minute) const {
  double phase = std::fmod(minute - (id % 2) * headway + cycle, cycle);
  int count = stops_.size() / 2, first = id / 2 * count, at = first;
  while (at + 1 < first + count && stops_[at + 1].arrival <= phase)
    ++at;
  auto &s = stops_[at];
  double end = s.next == first ? cycle : stops_[s.next].arrival;
  double p = std::clamp((phase - s.departure) / (end - s.departure), 0., 1.);
  // Ease into and out of the platform without changing the timetable.
  p = p * p * (3. - 2. * p);
  return {follow_path(s.track, p, true), at, s.next, phase < s.departure};
}
int Transit::vehicle(const BusTrip &t) const {
  return stops_[t.from].direction * 2 + t.run % 2;
}
std::vector<std::pair<int, int>> Transit::sections(int from, int to,
                                                   int run) const {
  std::vector<std::pair<int, int>> result;
  for (int at = from; at != to;) {
    result.emplace_back(at, (run + minutes_per_day / headway) %
                                (minutes_per_day / headway));
    int next = stops_[at].next;
    if (next < at)
      run += 2;
    at = next;
  }
  return result;
}
BusTrip Transit::departure(int from, int to, double reach) const {
  if (from < 0 || to < 0 || from == to || from >= int(stops_.size()) ||
      to >= int(stops_.size()) ||
      stops_[from].direction != stops_[to].direction)
    return {};
  const auto &a = stops_[from], &b = stops_[to];
  int run = int(std::ceil((reach + .15 - a.departure) / headway));
  for (int attempt = 0; attempt < 2; ++attempt, ++run) {
    auto legs = sections(from, to, run);
    bool free = std::all_of(legs.begin(), legs.end(), [&](auto key) {
      auto it = booked_.find(key);
      return it == booked_.end() || it->second < capacity;
    });
    if (!free)
      continue;
    BusTrip trip;
    trip.from = from;
    trip.to = to;
    trip.run = run;
    trip.reach = reach;
    trip.board = std::max(reach, run * headway + a.arrival + .45);
    trip.alight =
        run * headway + b.arrival + (b.arrival <= a.arrival ? cycle : 0);
    return trip;
  }
  return {};
}
void Transit::release(const BusTrip &trip) {
  for (auto key : sections(trip.from, trip.to, trip.run)) {
    auto it = booked_.find(key);
    if (--it->second == 0)
      booked_.erase(it);
  }
}
void Transit::reserve(const BusTrip &trip) {
  for (auto key : sections(trip.from, trip.to, trip.run))
    ++booked_[key];
}
} // namespace city
