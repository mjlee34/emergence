#pragma once
#include "geo/terrain.hpp"
#include <cstdint>
#include <vector>

namespace city {
// East is +x, south is +z. Samples are absolute elevations in decimetres.
struct Site {
  static constexpr int side = 169;
  static constexpr int spacing = 20;
  double latitude = 0, longitude = 0;
  std::vector<int32_t> elevations;
  std::vector<uint8_t> lake;
  bool inland_water(Point p) const;
  bool geographic() const { return !elevations.empty(); }
  double elevation(Point p) const;
  double datum() const { return geographic() ? elevations[side * side / 2] * .1 - 8. : 0.; }
  double height(Point p) const { return elevation(p) - datum(); }
  bool suitable() const;
};
}
