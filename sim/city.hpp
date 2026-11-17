#pragma once
#include "geo/terrain.hpp"
#include <array>
#include <cstdint>
#include <string>
#include <vector>
namespace city {
struct Junction {
  int col, row;
  Point pos;
  std::vector<int> edges;
};
struct Road {
  int a, b;
  bool avenue;
  std::array<Point, 9> path;
  std::array<double, 9> lengths;
};
enum class Use { Housing, Shops, Works };
struct Building {
  Point pos;
  double yaw;
  int style, capacity, started;
  Use use;
};
struct Vehicle {
  int edge, from, destination;
  double along, speed;
  std::vector<int> route;
};
struct Event {
  int tick;
  std::string text;
};
class City {
public:
  explicit City(uint32_t seed = 147);
  void advance(int ticks);
  int tick() const { return tick_; }
  int population() const { return population_; }
  uint32_t seed() const { return seed_; }
  int capacity() const { return capacity_; }
  const auto &nodes() const { return nodes_; }
  const auto &roads() const { return roads_; }
  const auto &buildings() const { return buildings_; }
  const auto &vehicles() const { return vehicles_; }
  const auto &events() const { return events_; }
  Point vehicle_position(const Vehicle &car, double &yaw,
                         double fraction = 0) const;
  uint64_t digest() const;

private:
  uint32_t seed_, random_;
  int tick_ = 0, population_ = 0, capacity_ = 0, vacant_ticks_ = 0;
  std::vector<Junction> nodes_;
  std::vector<Road> roads_;
  std::vector<Building> buildings_;
  std::vector<Vehicle> vehicles_;
  std::vector<Event> events_;
  uint32_t draw();
  int find_node(int c, int r) const;
  bool grow();
  int add_road(int a, int c, int r);
  bool develop(int edge, bool initial);
  void dispatch(Vehicle &car, int start);
  void record(std::string message);
};
} // namespace city
