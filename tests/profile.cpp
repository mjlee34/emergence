#include "sim/city.hpp"
#include <algorithm>
#include <charconv>
#include <chrono>
#include <iostream>
#include <string_view>

int main(int argc, char **argv) {
  city::City city(147);
  for (int i = 1; i < std::max(2, argc); ++i) {
    int target = 40000;
    if (argc > 1) {
      std::string_view arg(argv[i]);
      auto [end, error] = std::from_chars(arg.begin(), arg.end(), target);
      if (error != std::errc{} || end != arg.end() || target <= city.tick()) {
        std::cerr << "Supply increasing positive target ticks.\n";
        return 1;
      }
    }
    int interval = target - city.tick();
    auto start = std::chrono::steady_clock::now();
    city.advance(interval);
    double seconds = std::chrono::duration<double>(
        std::chrono::steady_clock::now() - start).count();
    auto bounds = city.bounds();
    std::cout << "Tick " << target << ", " << interval << " ticks in "
              << seconds << " s, " << city.population() << " residents, "
              << city.roads().size() << " roads, " << city.buildings().size()
              << " buildings, " << int(bounds[2] - bounds[0]) << " x "
              << int(bounds[3] - bounds[1]) << " m, checksum "
              << city.digest() << '\n';
  }
}
