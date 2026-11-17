#include "sim/city.hpp"
#include <algorithm>
#include <cmath>
namespace city {
RoadCurb building_curb(const City &c, int lot) {
  auto &b = c.buildings()[lot];
  return {b.frontage, b.sample, b.pos};
}
std::vector<DriveLeg> drive_route(const City &c, int origin, int target,
                                  double speed) {
  return drive_route(c, building_curb(c, origin), building_curb(c, target),
                     speed);
}
std::vector<DriveLeg> drive_route(const City &c, RoadCurb origin,
                                  RoadCurb target, double speed) {
  std::vector<DriveLeg> legs;
  int first = origin.edge, last = target.edge;
  const auto &a = c.roads()[first], &b = c.roads()[last];
  double start = a.lengths[origin.sample], end = b.lengths[target.sample];
  double time = 0;
  auto leg = [&](int edge, double from, double to) {
    if (std::abs(to - from) < .001)
      return;
    time += std::abs(to - from) / (speed * speed_factor(c.roads()[edge].type));
    legs.push_back({edge, from, to, time});
  };
  auto curb_forward = [&](const Road &r, RoadCurb curb) {
    int k = curb.sample;
    auto p = r.path[k], q = r.path[k + 1], door = curb.door;
    return (q.x - p.x) * (door.z - p.z) - (q.z - p.z) * (door.x - p.x) > 0;
  };
  bool depart_forward = curb_forward(a, origin),
       arrive_forward = curb_forward(b, target);
  if (first == last && depart_forward == arrive_forward &&
      (depart_forward ? start <= end : start >= end))
    leg(first, start, end);
  else {
    // Approach each building on its own curb, crossing medians only at
    // junctions.
    int start_node = depart_forward ? a.b : a.a;
    int end_node = arrive_forward ? b.a : b.b;
    leg(first, start, start_node == a.a ? 0 : a.lengths.back());
    auto route = c.road_route(start_node, end_node);
    int node = start_node;
    for (auto it = route.rbegin(); it != route.rend(); ++it) {
      auto &r = c.roads()[*it];
      bool forward = node == r.a;
      leg(*it, forward ? 0 : r.lengths.back(), forward ? r.lengths.back() : 0);
      node = forward ? r.b : r.a;
    }
    leg(last, end_node == b.a ? 0 : b.lengths.back(), end);
  }
  // Building entrances can occupy the same point along a street.
  if (legs.empty())
    legs.push_back({first, start, start, 0});
  return legs;
}
Vehicle drive_vehicle(const City &c, const std::vector<DriveLeg> &legs,
                      double elapsed, double speed, bool include_route) {
  auto it = std::lower_bound(
      legs.begin(), legs.end(), elapsed,
      [](const DriveLeg &leg, double t) { return leg.end_time < t; });
  if (it == legs.end())
    --it;
  const auto &r = c.roads()[it->edge];
  bool forward = it->to >= it->from;
  double before = it == legs.begin() ? 0 : (it - 1)->end_time;
  double progress =
      it->end_time > before
          ? std::clamp((elapsed - before) / (it->end_time - before), 0., 1.)
          : 0.;
  double at = std::lerp(it->from, it->to, progress);
  Vehicle vehicle{it->edge, forward ? r.a : r.b,
                  0,        forward ? at : r.lengths.back() - at,
                  speed,    {}};
  const auto &last = legs.back();
  const auto &end = c.roads()[last.edge];
  vehicle.destination = last.to >= last.from ? end.b : end.a;
  if (include_route)
    for (auto next = legs.end(); next != it + 1;)
      vehicle.route.push_back((--next)->edge);
  return vehicle;
}
VanPose drive_pose(const City &c, const std::vector<DriveLeg> &legs,
                   double elapsed, double speed) {
  auto vehicle = drive_vehicle(c, legs, elapsed, speed);
  const auto &r = c.roads()[vehicle.edge];
  double yaw;
  auto pos = c.vehicle_position(vehicle, yaw);
  double berth = std::clamp(
      1. - std::min(elapsed, legs.back().end_time - elapsed) / 5., 0., 1.);
  double lane = r.type == RoadClass::Arterial ? 5.35 : road_width(r.type) * .22;
  double shift = berth * (road_width(r.type) * .5 - .97 - lane);
  pos.x += std::sin(yaw) * shift;
  pos.z += std::cos(yaw) * shift;
  return {pos, c.street_height(r, pos), yaw};
}
} // namespace city
