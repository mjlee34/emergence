#pragma once
#include "geo/site.hpp"
#include "sim/economy.hpp"
#include "sim/life.hpp"
#include <array>
#include <cstdint>
#include <deque>
#include <map>
#include <string>
#include <utility>
#include <vector>
namespace city {
constexpr int planning_interval = 60;
constexpr int construction_ticks = 24 * planning_interval;
struct Junction {
  int col, row;
  Point pos;
  std::vector<int> edges;
};
enum class RoadClass { Local, Collector, Arterial };
double road_width(RoadClass type);
double speed_factor(RoadClass type);
struct Road {
  int a, b;
  RoadClass type;
  bool bridge;
  int started = 0, opens = 0;
  unsigned available_lots = 15;
  std::array<Point, 9> path;
  std::array<double, 9> lengths;
};
double road_height(const Road &road, Point p);
enum class Use { Housing, Shops, Works };
struct Building {
  Point pos;
  double yaw;
  int style, capacity, started;
  Use use;
  int frontage, floors;
  int previous_floors = 0;
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
  explicit City(uint32_t seed = 147, Site site = {});
  const Site &site() const { return site_; }
  double height(Point p) const { return site_.height(p); }
  double street_height(const Road &road, Point p) const;
  void advance(int ticks);
  int tick() const { return tick_; }
  int population() const { return population_; }
  uint32_t seed() const { return seed_; }
  int capacity() const { return capacity_; }
  const Life &life() const { return life_; }
  const auto &nodes() const { return nodes_; }
  const auto &roads() const { return roads_; }
  const auto &buildings() const { return buildings_; }
  const auto &vehicles() const { return vehicles_; }
  const auto &renewals() const { return renewals_; }
  const auto &bounds() const { return bounds_; }
  const auto &events() const { return events_; }
  Point vehicle_position(const Vehicle &car, double &yaw,
                         double fraction = 0) const;
  std::vector<int> road_route(int start, int target) const;
  const Economy &economy() const { return economy_; }
  uint64_t digest() const;

private:
  Site site_;
  uint32_t seed_, random_;
  int tick_ = 0, population_ = 0, capacity_ = 0, vacant_ticks_ = 0;
  std::vector<Junction> nodes_;
  std::vector<Road> roads_;
  std::vector<Building> buildings_;
  std::vector<Vehicle> vehicles_;
  std::vector<Event> events_;
  std::map<std::pair<int, int>, int> node_index_;
  std::vector<int> renewals_;
  struct Completion {
    int tick, lot, beds;
  };
  std::deque<Completion> completions_;
  std::multimap<int, int> road_openings_;
  Life life_;
  Economy economy_;
  std::array<double, 4> bounds_{-30, 6, -30, 6};
  bool connected(int node) const;
  void spawn_vehicle();
  bool redevelop();
  int target_floors(const Building &b) const;
  uint32_t draw();
  int find_node(int c, int r) const;
  bool grow();
  int add_road(int a, int c, int r);
  bool develop(int edge, bool initial);
  void dispatch(Vehicle &car, int start);
  void record(std::string message);
};
} // namespace city
