#include "replay/checkpoint.hpp"
#include <sstream>
#include <iomanip>
#include <limits>
namespace city {
std::string checkpoint(const City &c) {
  if (c.site().geographic()) {
    std::ostringstream out;
    out << "EMERGENCE-GEO-4 " << c.seed() << ' ' << c.tick() << ' ' << c.digest()
        << ' ' << std::setprecision(std::numeric_limits<double>::max_digits10)
        << c.site().latitude << ' ' << c.site().longitude;
    for (auto y : c.site().elevations) out << ' ' << y;
    out << ' ' << c.site().lake.size();
    for (auto wet : c.site().lake) out << ' ' << int(wet);
    return out.str();
  }
  return "EMERGENCE-8 " + std::to_string(c.seed()) + " " +
         std::to_string(c.tick()) + " " + std::to_string(c.digest());
}
std::optional<City> restore(const std::string &record) {
  std::istringstream in(record);
  std::string version, trailing;
  uint32_t seed;
  int tick;
  uint64_t digest;
  if (!(in >> version >> seed >> tick >> digest) || tick < 0)
    return {};
  Site site;
  if (version == "EMERGENCE-GEO-4") {
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
  } else if (version != "EMERGENCE-8") return {};
  if (in >> trailing)
    return {};
  City c(seed, std::move(site));
  c.advance(tick);
  if (c.digest() != digest)
    return {};
  return c;
}
} // namespace city
