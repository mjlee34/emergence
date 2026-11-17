#pragma once
#include "geo/site.hpp"
#include "sim/economy.hpp"
#include "sim/life.hpp"
#include "sim/weather.hpp"
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
  bool bridge = false, surveyed = false;
  int started = 0, opens = 0;
  unsigned available_lots = 15;
  std::array<Point, 9> path;
  std::array<double, 9> lengths;
};
double road_height(const Road &road, Point p, const Site &site = {});
enum class Use { Housing, Shops, Works };
struct Building {
  Point pos;
  double yaw;
  int style, capacity, started;
  Use use;
  int frontage, floors;
  int previous_floors = 0, sample = 2;
  double wing = 0., previous_wing = 0., rear = 0., previous_rear = 0.;
  Point centre(double depth) const;
  double clearance(Point a, Point b) const;
};
enum class FacilityKind { Park, Playground, School, Hospital, Fire, Police, BoulevardMonument, WaterfrontMonument };
inline bool is_service(FacilityKind k) {
  return k >= FacilityKind::School && k <= FacilityKind::Police;
}
inline bool is_landmark(FacilityKind k) { return k >= FacilityKind::BoulevardMonument; }
struct Facility {
  FacilityKind kind;
  Point center, gate;
  double yaw, radius;
  int frontage, sample, side, started, opens;
  int catchment = 0, responses = 0;
};
struct LandmarkDesign {
  const char *model, *name;
  double height_scale;
  int palette;
};
LandmarkDesign landmark_design(uint32_t seed, const Facility &site);
const char *facility_name(uint32_t seed, const Facility &site);

struct Response {
  int station, lot, start, arrival, leaving, end;
  std::vector<DriveLeg> outward, returning;
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
  explicit City(uint32_t seed = 147, Site site = {},
                int township_through_tick = 0, int old_roads_through_tick = -1,
                int old_skyline_through_tick = -1);
  const Site &site() const { return site_; }
  double height(Point p) const { return site_.height(p); }
  Point planning_extent() const;
  int township_through_tick() const { return township_through_tick_; }
  int old_roads_through_tick() const { return old_roads_through_tick_; }
  double street_height(const Road &road, Point p) const;
  void advance(int ticks);
  Weather weather(double fraction = 0.) const {
    return weather_at(seed_, site_.geographic() ? site_.latitude : 45.,
                      tick_ + fraction);
  }
  int tick() const { return tick_; }
  int population() const { return population_; }
  uint32_t seed() const { return seed_; }
  int capacity() const { return capacity_; }
  const Life &life() const { return life_; }
  const auto &facilities() const { return facilities_; }
  const auto &nodes() const { return nodes_; }
  const auto &roads() const { return roads_; }
  const auto &buildings() const { return buildings_; }
  std::vector<Vehicle> vehicles() const;
  const auto &renewals() const { return renewals_; }
  const auto &bounds() const { return bounds_; }
  int main_street_corner() const { return main_street_corner_; }
  int old_skyline_through_tick() const { return old_skyline_through_tick_; }
  const auto &district_centres() const { return centres_; }
  const auto &responses() const { return responses_; }
  const auto &events() const { return events_; }
  Point vehicle_position(const Vehicle &car, double &yaw,
                         double fraction = 0) const;
  std::vector<int> road_route(int start, int target) const;
  const Economy &economy() const { return economy_; }
  uint64_t digest() const;

private:
  Site site_;
  uint32_t seed_, random_;
  int township_through_tick_, old_roads_through_tick_;
  int old_skyline_through_tick_, main_street_corner_ = -1;
  void choose_main_street_corner();
  double grid_angle_, grid_phase_, block_width_;
  Point workshop_site_;
  Point street_point(double column, double row) const;
  int tick_ = 0, population_ = 0, capacity_ = 0, vacant_ticks_ = 0;
  std::vector<Junction> nodes_;
  std::vector<Road> roads_;
  std::vector<Building> buildings_;
  std::vector<Facility> facilities_;
  std::vector<Event> events_;
  bool access_changed_ = false;
  int surveyed_population_ = 0;
  void plan_facilities();
  void plan_public_sites(bool allow_building = true);
  std::vector<Response> responses_;
  void dispatch_services();
  struct TravelDemand {
    double visits = 0, east_west = 0, north_south = 0;
  };
  std::vector<TravelDemand> travel_demand_;
  void survey_trips();
  double frontage_visits(int edge) const;
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
  bool redevelop();
  std::vector<Point> centres_;
  void locate_centres();
  void reserve_frontage(Building &b) const;
  int target_floors(const Building &b) const;
  uint32_t draw();
  int find_node(int c, int r) const;
  bool grow();
  bool grow_surveyed(bool feeder_only = false);
  struct SurveyPoint {
    Point pos;
    int junction = -1;
    std::vector<int> neighbours;
    bool surveyed = false;
  };
  std::vector<SurveyPoint> survey_;
  std::vector<int> junction_sites_;
  std::map<std::pair<int, int>, std::vector<int>> survey_bins_;
  std::map<std::pair<int, int>, int> blocked_width_;
  std::map<std::pair<int, int>, RoadClass> feeders_;
  void survey_land();
  void survey_neighbours(int origin);
  int commit_road(int a, int b, Road road);

  int add_road(int a, int c, int r, RoadClass type, bool bridge = false);
  bool develop(int edge, bool initial);
  void record(std::string message);
};
} // namespace city
