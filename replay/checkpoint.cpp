#include "replay/checkpoint.hpp"
#include <sstream>
namespace city {
std::string checkpoint(const City &c) {
  return "EMERGENCE-4 " + std::to_string(c.seed()) + " " +
         std::to_string(c.tick()) + " " + std::to_string(c.digest());
}
std::optional<City> restore(const std::string &record) {
  std::istringstream in(record);
  std::string version, trailing;
  uint32_t seed;
  int tick;
  uint64_t digest;
  if (!(in >> version >> seed >> tick >> digest) || version != "EMERGENCE-4" ||
      tick < 0 || (in >> trailing))
    return {};
  City c(seed);
  c.advance(tick);
  if (c.digest() != digest)
    return {};
  return c;
}
} // namespace city
