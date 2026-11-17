#pragma once
#include "geo/terrain.hpp"
#include <vector>
namespace city {
class City;
struct DriveLeg {
  int edge;
  double from, to, end_time;
};
struct Vehicle;
Vehicle drive_vehicle(const City &city, const std::vector<DriveLeg> &route,
                      double elapsed, double speed, bool include_route = false);
struct VanPose {
  Point position;
  double height, yaw;
};
std::vector<DriveLeg> drive_route(const City &city, int origin, int target,
                                  double speed);
VanPose drive_pose(const City &city, const std::vector<DriveLeg> &route,
                   double elapsed, double speed);
} // namespace city
