#include "geo/site.hpp"
#include <algorithm>
#include <cmath>

namespace city {
double Site::elevation(Point p) const {
  if (!geographic())
    return ground(p);
  double x = std::clamp(p.x / spacing + side / 2, 0., double(side - 1));
  double z = std::clamp(p.z / spacing + side / 2, 0., double(side - 1));
  int i = std::min(int(x), side - 2), j = std::min(int(z), side - 2);
  auto row = [&](int r) {
    return std::lerp(double(elevations[r * side + i]),
                     double(elevations[r * side + i + 1]), x - i);
  };
  return std::lerp(row(j), row(j + 1), z - j) * .1;
}

bool Site::inland_water(Point p) const {
  if (lake.empty())
    return false;
  const int x = std::clamp(int(std::round(p.x / spacing)) + side / 2, 0, side - 1);
  const int z = std::clamp(int(std::round(p.z / spacing)) + side / 2, 0, side - 1);
  return lake[z * side + x] != 0;
}

bool Site::suitable() const {
  if (elevations.size() != side * side || (!lake.empty() && lake.size() != elevations.size()) || !std::isfinite(latitude) ||
      !std::isfinite(longitude) || std::abs(latitude) > 85. ||
      std::abs(longitude) > 180.)
    return false;
  // The founding settlement occupies this footprint. Later roads evaluate
  // their own grades as the network expands.
  for (int z = -100; z <= 100; z += 10)
    for (int x = -142; x <= 78; x += 10) {
      const double y = elevation({double(x), double(z)});
      if (inland_water({double(x), double(z)}) || y <= 1. || std::abs(y - elevation({x + 10., double(z)})) > 2.2 ||
          std::abs(y - elevation({double(x), z + 10.})) > 2.2)
        return false;
    }
  return true;
}
}
