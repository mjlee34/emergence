#include "geo/terrain.hpp"
#include <algorithm>
#include <cmath>
namespace city {
double distance(Point a, Point b) { return std::hypot(a.x - b.x, a.z - b.z); }
double segment_distance(Point p, Point a, Point b) {
  double x = b.x - a.x, z = b.z - a.z;
  double t =
      std::clamp(((p.x - a.x) * x + (p.z - a.z) * z) / (x * x + z * z), 0., 1.);
  return distance(p, {a.x + x * t, a.z + z * t});
}
double river_center(double z) {
  return 94 + 29 * std::sin(z * .021 + .4) - .18 * z;
}
static double hill(Point p, double x, double z, double sx, double sz,
                   double h) {
  return h *
         std::exp(-std::pow((p.x - x) / sx, 2) - std::pow((p.z - z) / sz, 2));
}
double ground(Point p) {
  double bank = std::abs(p.x - river_center(p.z));
  double meadow =
      4.6 + 1.5 * std::sin(p.x * .027 + p.z * .011) + .9 * std::cos(p.z * .046);
  double ridges =
      hill(p, -235, -234, 120, 66, 71) + hill(p, -429, -75, 60, 89, 64) +
      hill(p, -104, -298, 89, 58, 49) + hill(p, 356, -168, 71, 103, 59) +
      hill(p, 398, 249, 86, 89, 55);
  double detail = 1 + .12 * std::sin(p.x * .13) * std::cos(p.z * .14) +
                  .08 * std::sin(.27 * p.x + .05 * p.z);
  double t = std::clamp((bank - 12.0) / 17.0, 0.0, 1.0);
  return -3.8 + (meadow + ridges * detail + 3.8) * t * t * (3 - 2 * t);
}
} // namespace city
