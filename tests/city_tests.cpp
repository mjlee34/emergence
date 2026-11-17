#include "replay/checkpoint.hpp"
#include <chrono>
#include <cmath>
#include <iostream>
#include <stdexcept>
#define CHECK(expr)                                                            \
  do {                                                                         \
    if (!(expr))                                                               \
      throw std::runtime_error(#expr);                                         \
  } while (false)
int main() {
  using namespace city;
  auto start = std::chrono::steady_clock::now();
  for (auto seed : {147u, 42u, 2026u}) {
    City a(seed), b(seed);
    auto roads = a.roads().size(), lots = a.buildings().size();
    int people = a.population();
    CHECK(people >= 1000 && people <= 5000);
    auto initial = a.digest();
    a.advance(0);
    CHECK(initial == a.digest());
    a.advance(640);
    for (int i = 0; i < 64; ++i)
      b.advance(10);
    CHECK(a.digest() == b.digest());
    CHECK(a.roads().size() > roads);
    CHECK(a.buildings().size() > lots);
    CHECK(a.population() > people && a.population() <= a.capacity());
    auto restored = restore(checkpoint(a));
    CHECK(restored);
    restored->advance(11);
    b.advance(11);
    CHECK(restored->digest() == b.digest());
    CHECK(!restore(checkpoint(a) + " damaged"));
    for (auto &r : a.roads())
      for (auto p : r.path)
        CHECK(ground(p) > 1.);
    for (auto &car : a.vehicles()) {
      const auto &path = a.roads().at(car.edge);
      double yaw;
      auto p = a.vehicle_position(car, yaw);
      CHECK(car.along >= 0 && car.along < path.lengths.back());
      CHECK(std::isfinite(yaw));
      CHECK(ground(p) > 0 && (car.from == path.a || car.from == path.b));
    }
    std::cout << "Seed " << seed << " at 0 / 640 ticks: residents " << people
              << " / " << a.population() << ", roads " << roads << " / "
              << a.roads().size() << ", buildings " << lots << " / "
              << a.buildings().size() << "\n";
  }
  std::cout << "Test time "
            << std::chrono::duration<double>(std::chrono::steady_clock::now() -
                                             start)
                   .count()
            << " s\n";
}
