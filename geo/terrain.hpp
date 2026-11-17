#pragma once
namespace city {
struct Point {
  double x, z;
};
double distance(Point a, Point b);
double ground(Point p);
double river_center(double z);
Point street_point(double col, double row);
constexpr double half_width = 216, half_depth = 164;
} // namespace city
