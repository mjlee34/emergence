#pragma once
#include <cstdint>

namespace city {
struct Weather {
  // Unit vector pointing at the sun in local east, up, south axes.
  double sun_east, sun_up, sun_south;
  double clouds, rain, wetness, wind_east, wind_south;
};
Weather weather_at(uint32_t seed, double latitude, double tick);
} // namespace city
