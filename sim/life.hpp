#pragma once
#include "sim/transit.hpp"
#include <array>
#include <cstdint>
#include <map>
#include <set>
#include <vector>
namespace city {
class City;
constexpr int minutes_per_day = 1440, ticks_per_minute = 4,
              opening_minute = 465;
enum class Activity {
  Home,
  Work,
  Shopping,
  Walking,
  Waiting,
  Riding,
  Driving,
  Leisure
};
enum class Mode { Walk, Car, Bus };
struct CommuteLeg {
  int drive = -1;
  double access = 0, driving = 0, duration = 0;
  BusTrip bus;
};
struct Resident {
  int home, work = -1, shop = -1, commute = -1, errand = -1, first_day = 0;
  uint32_t variation;
  bool seeks_work;
  int leave_home, lunch, finish;
  double commute_minutes = 0;
  double outing_return = 0;
  int facility = -1, leisure_path = -1, visit_day = 0;
  double visit_start = 0, visit_walk = 0, visit_stay = 0;
  Mode mode = Mode::Walk;
  bool car_owner = false, child = false;
  int slide_slot = -1;
  std::array<CommuteLeg, 2> trips;
};
struct DailyState {
  Activity activity;
  int from, to, route = -1;
  double progress = 0;
  bool reverse = false;
  int stop = -1, bus = -1, drive = -1;
  bool last_mile = false;
  int facility = -1;
};
struct Occupancy {
  int beds = 0, housed = 0, jobs = 0, hired = 0;
};
class Life {
public:
  void start_service(const City &city) { transit_.establish(city); }
  const Transit &transit() const { return transit_; }
  const auto &drive_paths() const { return drives_; }
  void open(const City &city, int lot, int beds);
  void settle(const City &city);
  void open_facility(const City &city, int id);
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
  Transit transit_;
  std::vector<std::vector<DriveLeg>> drives_;
  std::map<std::pair<int, int>, int> drive_cache_, access_cache_;
  std::vector<Resident> residents_;
  std::map<std::pair<int, int>, int> green_paths_;
  std::set<std::array<int, 3>> slide_slots_;
  void plan_visit(const City &city, Resident &resident);
  void plan_travel(const City &city, Resident &r, double walking);
  BusTrip bus_option(const City &city, int a, int b, double start, double pace);
  int access_path(const City &city, int lot, int stop);
  CommuteLeg drive_option(const City &city, int from, int to, double pace);
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
