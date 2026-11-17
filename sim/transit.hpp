#pragma once
#include "sim/road_trip.hpp"
#include <array>
#include <map>
#include <utility>

namespace city {
class City;
struct WalkPoint {
  Point pos;
  double height;
};
struct Footpath {
  std::vector<WalkPoint> points;
  std::vector<double> lengths;
};
struct PersonPose {
  Point pos;
  double height, yaw;
};
PersonPose follow_path(const Footpath &path, double progress, bool forward,
                       double offset = 0);
struct Stop {
  int edge, side, next, direction;
  WalkPoint platform;
  double yaw, arrival, departure;
  Footpath track;
};
struct BusTrip {
  int from = -1, to = -1, run = -1, access = -1, egress = -1;
  double reach = 0, board = 0, alight = 0, finish = 0;
};
struct BusPosition {
  PersonPose pose;
  int stop, next;
  bool dwelling;
};
class Transit {
public:
  static constexpr int headway = 18, cycle = 36, capacity = 32, fleet = 4;
  void establish(const City &city);
  const auto &stops() const { return stops_; }
  BusPosition bus(int id, double minute) const;
  int vehicle(const BusTrip &trip) const;
  BusTrip departure(int from, int to, double reach) const;
  void reserve(const BusTrip &trip);
  void release(const BusTrip &trip);

private:
  std::vector<Stop> stops_;
  std::map<std::pair<int, int>, int> booked_;
  std::vector<std::pair<int, int>> sections(int from, int to, int run) const;
};
} // namespace city
