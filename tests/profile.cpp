#include "sim/city.hpp"
#include <chrono>
#include <iostream>
int main() {
  city::City city(147);
  auto start = std::chrono::steady_clock::now();
  city.advance(40000);
  double seconds =
      std::chrono::duration<double>(std::chrono::steady_clock::now() - start)
          .count();
  std::cout << city.tick() << " ticks in " << seconds << " s ("
            << int(city.tick() / seconds) << " ticks/s), " << city.population()
            << " residents, " << city.roads().size() << " roads, "
            << city.buildings().size() << " buildings.\n";
}
