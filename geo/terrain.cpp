#include "geo/terrain.hpp"
#include <algorithm>
#include <cmath>
namespace city {
double distance(Point a, Point b) { return std::hypot(a.x - b.x, a.z - b.z); }
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
  double ridges = hill(p, -151, -112, 60, 42, 46) +
                  hill(p, -207, -49, 33, 54, 32) +
                  hill(p, -84, -151, 46, 38, 30) +
                  hill(p, 197, -90, 39, 62, 35) + hill(p, 195, 108, 53, 57, 22);
  double detail = 1 + .12 * std::sin(p.x * .13) * std::cos(p.z * .14) +
                  .08 * std::sin(.27 * p.x + .05 * p.z);
  double t = std::clamp((bank - 12.0) / 17.0, 0.0, 1.0);
  return -3.8 + (meadow + ridges * detail + 3.8) * t * t * (3 - 2 * t);
}
Point street_point(double col, double row) {
  return {-30 + col * 32 + 10 * std::sin(row * .91 + col * .52) +
              3 * std::sin(col * 1.3 + row * .8),
          6 + row * 28 + 13 * std::sin(col * .94 - row * .37) +
              4 * std::cos(row * 1.08 + col * .46)};
}
} // namespace city
