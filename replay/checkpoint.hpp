#pragma once
#include "sim/city.hpp"
#include <optional>
namespace city {
std::string checkpoint(const City& city);
std::optional<City> restore(const std::string& record);
}
