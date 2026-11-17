#include "sim/weather.hpp"
#include "sim/life.hpp"
#include <algorithm>
#include <cmath>
#include <numbers>

namespace city {
namespace {
constexpr double tau = 2. * std::numbers::pi;
double smooth(double low, double high, double x) {
  double t = std::clamp((x - low) / (high - low), 0., 1.);
  return t * t * (3. - 2. * t);
}
// The atmosphere has its own random field. Querying the sky never consumes a
// city draw.
double noise(uint32_t seed, int front, uint32_t channel) {
  uint32_t h = seed + uint32_t(front) * 0x9e3779b9u + channel * 0x85ebca6bu;
  h ^= h >> 16;
  h *= 0x7feb352du;
  h ^= h >> 15;
  h *= 0x846ca68bu;
  h ^= h >> 16;
  return (h >> 8) / 16777216.;
}
double front_field(uint32_t seed, double minute, uint32_t channel) {
  const double phase = minute / 210.;
  const int k = int(std::floor(phase));
  return std::lerp(noise(seed, k, channel), noise(seed, k + 1, channel),
                   smooth(.12, .88, phase - k));
}
double cloud_cover(uint32_t seed, double minute) {
  return smooth(.09, .91,
                .83 * front_field(seed, minute, 1) +
                    .17 * front_field(seed, minute * 2.15, 2));
}
double rainfall(uint32_t seed, double minute) {
  return smooth(.55, .96, cloud_cover(seed, minute)) *
         (.4 + .6 * front_field(seed, minute * 2.6, 3)) *
         smooth(.10, .37, front_field(seed, minute * .70, 8));
}
} // namespace
Weather weather_at(uint32_t seed, double latitude, double tick) {
  const double minute = opening_minute + tick / ticks_per_minute;
  // Day one is the March equinox. The clock records local solar time.
  const double declination =
      .4091 * std::sin(tau * minute / (365.2422 * minutes_per_day));
  const double lat = latitude * tau / 360.;
  const double hour =
      tau * (std::fmod(minute, minutes_per_day) / minutes_per_day - .5);
  const double noon = std::cos(declination) * std::cos(hour);
  const double rain = rainfall(seed, minute);
  // Retained rain darkens paving after showers. The same time gives the same
  // surface even when a high-speed step skips the whole shower.
  double wetness = rain, retention = 1.;
  for (int age = 12; age <= 144; age += 12) {
    retention *= .79;
    wetness = std::max(wetness, retention * rainfall(seed, minute - age));
  }
  const double wind = .23 + .65 * front_field(seed, minute, 4) + rain * .18;
  const double bearing =
      tau * (noise(seed, 0, 5) + .32 * front_field(seed, minute, 6));
  return {-std::cos(declination) * std::sin(hour),
          std::sin(lat) * std::sin(declination) + std::cos(lat) * noon,
          std::sin(lat) * noon - std::cos(lat) * std::sin(declination),
          cloud_cover(seed, minute),
          rain,
          std::min(1., wetness * 1.65),
          wind * std::cos(bearing),
          wind * std::sin(bearing)};
}
} // namespace city
