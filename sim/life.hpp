#pragma once
#include "geo/terrain.hpp"
#include <array>
#include <cstdint>
#include <map>
#include <vector>
namespace city {
class City;
constexpr int minutes_per_day = 1440, ticks_per_minute = 4,
              opening_minute = 465;
enum class Activity { Home, Work, Shopping, Walking };
struct WalkPoint {
  Point pos;
  double height;
};
struct Footpath {
  std::vector<WalkPoint> points;
  std::vector<double> lengths;
};
struct Resident {
  int home, work = -1, shop = -1, commute = -1, errand = -1, first_day = 0;
  uint32_t variation;
  bool seeks_work;
  int leave_home, lunch, finish;
  double commute_minutes = 0;
};
struct DailyState {
  Activity activity;
  int from, to, route = -1;
  double progress = 0;
};
struct PersonPose {
  Point pos;
  double height, yaw;
};
struct Occupancy {
  int beds = 0, housed = 0, jobs = 0, hired = 0;
};
class Life {
public:
  void open(const City &city, int lot, int beds);
  void settle(const City &city);
  void hire_waiting(const City &city);
  DailyState routine(int id, double tick) const;
  PersonPose pose(const City &city, int id, const DailyState &state,
                  double tick = 0) const;
  const auto &people() const { return residents_; }
  const auto &occupancies() const { return places_; }
  const auto &paths() const { return paths_; }
  int employed() const { return employed_; }
  int workforce() const {
    return employed_ + static_cast<int>(waiting_.size());
  }
  int jobs() const { return jobs_; }
  uint64_t digest() const;

private:
  std::vector<Resident> residents_;
  std::vector<Occupancy> places_;
  std::vector<int> housing_, employers_, markets_, waiting_;
  std::map<std::pair<int, int>, int> route_index_;
  std::vector<Footpath> paths_;
  int jobs_ = 0, employed_ = 0;
  void assign_work(const City &city, Resident &resident);
  void assign_shop(const City &city, Resident &resident);
  int path(const City &city, int a, int b);
};
} // namespace city
