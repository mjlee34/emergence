#pragma once
namespace city {
struct Point {
  double x, z;
};
double distance(Point a, Point b);
double segment_distance(Point p, Point a, Point b);
double ground(Point p);
double river_center(double z);
constexpr double half_width = 480, half_depth = 320;
} // namespace city
