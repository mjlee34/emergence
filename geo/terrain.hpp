#pragma once
namespace city {
struct Point {
  double x, z;
};
double distance(Point a, Point b);
double segment_distance(Point p, Point a, Point b);
double segment_clearance(Point a, Point b, Point c, Point d);
double ground(Point p);
double river_center(double z);
constexpr double township_half_width = 480, township_half_depth = 320;
constexpr double half_width = 3 * township_half_width, half_depth = 3 * township_half_depth;
} // namespace city
