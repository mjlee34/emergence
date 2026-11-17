#include "replay/checkpoint.hpp"
#include <sstream>
#include <iomanip>
#include <limits>
namespace city {
std::string checkpoint(const City &c) {
  if (c.site().geographic()) {
    std::ostringstream out;
    out << "EMERGENCE-GEO-7 " << c.seed() << ' ' << c.tick() << ' ' << c.digest()
        << ' ' << c.township_through_tick() << ' ' << std::setprecision(std::numeric_limits<double>::max_digits10)
        << c.site().latitude << ' ' << c.site().longitude;
    for (auto y : c.site().elevations) out << ' ' << y;
    out << ' ' << c.site().lake.size();
    for (auto wet : c.site().lake) out << ' ' << int(wet);
    return out.str();
  }
  return "EMERGENCE-11 " + std::to_string(c.seed()) + " " +
         std::to_string(c.tick()) + " " + std::to_string(c.digest()) + " " +
         std::to_string(c.township_through_tick());
}
std::optional<City> restore(const std::string &record) {
  std::istringstream in(record);
  std::string version, trailing;
  uint32_t seed;
  int tick;
  uint64_t digest;
  if (!(in >> version >> seed >> tick >> digest) || tick < 0)
    return {};
  // Replay an older city's history inside its original boundary, then allow
  // regional growth. Save the transition tick for later replays of this city.
  int township_through = tick;
  if (version == "EMERGENCE-11" || version == "EMERGENCE-GEO-7") {
    if (!(in >> township_through) || township_through < 0 || township_through > tick)
      return {};
  }
  Site site;
  if (version == "EMERGENCE-GEO-7" || version == "EMERGENCE-GEO-6" || version == "EMERGENCE-GEO-5") {
    if (!(in >> site.latitude >> site.longitude)) return {};
    site.elevations.resize(Site::side * Site::side);
    for (auto &y : site.elevations)
      if (!(in >> y)) return {};
    size_t count;
    if (!(in >> count) || (count && count != site.elevations.size())) return {};
    site.lake.resize(count);
    for (auto &wet : site.lake) {
      int value;
      if (!(in >> value) || (value != 0 && value != 1)) return {};
      wet = value;
    }
    if (!site.suitable()) return {};
  } else if (version != "EMERGENCE-11" && version != "EMERGENCE-10" && version != "EMERGENCE-9") return {};
  if (in >> trailing)
    return {};
  City c(seed, std::move(site), township_through);
  c.advance(tick);
  if (c.digest() != digest)
    return {};
  return c;
}
} // namespace city
