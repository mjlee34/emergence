#include "replay/checkpoint.hpp"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>
#define CHECK(expr)                                                            \
  do {                                                                         \
    if (!(expr))                                                               \
      throw std::runtime_error(#expr);                                         \
  } while (false)
void check_weather() {
  using namespace city;
  auto at = [](int seed, double lat, double minute) {
    return weather_at(seed, lat, (minute - opening_minute) * ticks_per_minute);
  };
  auto morning = at(147, 45., 420), evening = at(147, 45., 1020);
  CHECK(morning.sun_east > .8 && evening.sun_east < -.8);
  CHECK(at(147, 45., 720).sun_up > .65 && at(147, 45., 1440).sun_up < -.65);
  CHECK(at(147, 45., 720).sun_south > 0 && at(147, -45., 720).sun_south < 0);
  CHECK(at(147, 80., 91 * 1440.).sun_up > 0 &&
        at(147, -80., 91 * 1440. + 720.).sun_up < 0);
  bool clear = false, overcast = false, storm = false, drying = false;
  for (int minute = 0; minute < 8 * 1440; minute += 5) {
    const auto w = at(147, 45., minute);
    CHECK(std::abs(w.sun_east * w.sun_east + w.sun_up * w.sun_up +
                   w.sun_south * w.sun_south - 1.) < 1e-10);
    CHECK(w.rain >= 0 && w.rain <= 1 && w.wetness >= w.rain && w.wetness <= 1.);
    clear |= w.clouds < .15;
    overcast |= w.clouds > .63 && w.rain < .045;
    storm |= w.rain > .5;
    drying |= w.wetness > .08 && w.rain < .01;
    const auto next = at(147, 45., minute + .01);
    CHECK(std::abs(next.rain - w.rain) < .002 &&
          std::abs(next.wetness - w.wetness) < .002);
  }
  CHECK(clear && overcast && storm && drying);
  City c;
  c.advance(3010);
  const auto digest = c.digest();
  const auto w = c.weather(.45);
  CHECK(c.digest() == digest && w.rain == weather_at(147, 45., 3010.45).rain);
  CHECK(w.clouds != weather_at(148, 45., 3010.45).clouds);
  const auto saved = restore(checkpoint(c));
  CHECK(saved && saved->weather(.45).wetness == w.wetness);
}
void check_facilities() {
  using namespace city;
  City c;
  CHECK(c.facilities().size() == 2);
  int visitors[2] = {}, play = 0;
  std::set<std::array<int, 3>> slots;
  for (int i = 0; i < c.population(); ++i) {
    const auto &r = c.life().people()[i];
    if (r.facility < 0)
      continue;
    const auto &f = c.facilities()[r.facility];
    int day = int(r.variation >> 28) % 2;
    auto tick = [&](double min) {
      return (day * minutes_per_day + min - opening_minute) * ticks_per_minute;
    };
    double arrived = r.visit_start + r.visit_walk;
    auto walk = c.life().routine(i, tick(r.visit_start + r.visit_walk * .5));
    auto visit = c.life().routine(i, tick(arrived + 1.));
    auto back =
        c.life().routine(i, tick(arrived + r.visit_stay + r.visit_walk * .5));
    CHECK(walk.activity == Activity::Walking && walk.facility == r.facility &&
          !walk.reverse);
    CHECK(visit.activity == Activity::Leisure && visit.facility == r.facility);
    CHECK(back.activity == Activity::Walking && back.reverse);
    CHECK(c.life()
              .routine(i, tick(arrived + r.visit_stay + r.visit_walk + .1))
              .activity == Activity::Home);
    CHECK(distance(c.life().paths()[walk.route].points.back().pos, f.gate) <
          .01);
    ++visitors[int(f.kind)];
    if (r.slide_slot >= 0) {
      CHECK(r.child && !r.car_owner && f.kind == FacilityKind::Playground);
      CHECK(slots.insert({r.facility, day, r.slide_slot}).second);
      auto t = tick(r.slide_slot * 4. + 1.75);
      auto pose = c.life().pose(c, i, c.life().routine(i, t), t);
      CHECK(pose.height - c.height(pose.pos) > 1.2);
      ++play;
    }
  }
  CHECK(visitors[0] > 0 && visitors[1] > 0 && play > 0);
  c.advance(23040);
  CHECK(c.facilities().size() > 2);
  for (const auto &f : c.facilities()) {
    CHECK(c.roads()[f.frontage].opens <= std::max(f.started, 0));
    CHECK(!c.roads()[f.frontage].bridge &&
          c.roads()[f.frontage].type != RoadClass::Arterial);
    for (int a = 0; a < 8; ++a) {
      Point p{f.center.x + f.radius * std::cos(a * .785398),
              f.center.z + f.radius * std::sin(a * .785398)};
      CHECK(!c.site().inland_water(p) && c.site().elevation(p) > 1.);
    }
    for (const auto &b : c.buildings()) {
      CHECK(distance(f.center, b.pos) >= f.radius + 6.4);
      if (b.use == Use::Works)
        CHECK(distance(f.center, b.pos) >= 25.);
    }
  }
}
void check_commuting() {
  using namespace city;
  City c(147);
  auto &life = c.life();
  auto &service = life.transit();
  CHECK(service.stops().size() >= 4);
  int modes[3] = {}, waits = 0;
  auto state_at = [&](int id, double minute) {
    return life.routine(id, (minute - opening_minute) * ticks_per_minute);
  };
  for (int id = 0; id < c.population(); ++id) {
    auto &r = life.people()[id];
    if (r.work < 0) {
      if (r.shop >= 0) {
        const double depart = 405 + r.variation % 545;
        CHECK(state_at(id, depart + r.trips[0].duration + 1).activity ==
              Activity::Shopping);
        CHECK(
            state_at(id, r.outing_return + r.trips[1].duration + 1).activity ==
            Activity::Home);
      }
      continue;
    }
    ++modes[int(r.mode)];
    for (int d = 0; d < 2; ++d) {
      double depart = d ? r.finish : r.leave_home;
      auto &leg = r.trips[d];
      CHECK(state_at(id, depart + leg.duration + .01).activity ==
            (d ? Activity::Home : Activity::Work));
      if (r.mode == Mode::Bus) {
        auto &t = leg.bus;
        int bus = service.vehicle(t);
        auto board = service.bus(bus, t.board),
             alight = service.bus(bus, t.alight + .001);
        CHECK(board.dwelling && board.stop == t.from && alight.dwelling &&
              alight.stop == t.to);
        if (t.board > t.reach + .001) {
          CHECK(state_at(id, (t.board + t.reach) * .5).activity ==
                Activity::Waiting);
          ++waits;
        }
        double minute = (t.board + t.alight) * .5,
               tick = (minute - opening_minute) * ticks_per_minute;
        auto trip = life.routine(id, tick);
        CHECK(trip.activity == Activity::Riding && trip.bus == bus);
        CHECK(distance(life.pose(c, id, trip, tick).pos,
                       service.bus(bus, minute).pose.pos) < .001);
        CHECK(state_at(id, (t.finish + t.alight) * .5).activity ==
              Activity::Walking);
      } else if (r.mode == Mode::Car) {
        CHECK(r.car_owner && leg.drive >= 0);
        auto trip = state_at(id, depart + leg.access + leg.driving * .5);
        CHECK(trip.activity == Activity::Driving && trip.drive == leg.drive);
        auto &route = life.drive_paths()[leg.drive];
        CHECK(distance(life.pose(c, id, trip).pos,
                       drive_pose(c, route, route.back().end_time * .5, .98)
                           .position) < .001);
        for (auto &edge : route)
          CHECK(c.roads()[edge.edge].opens <= c.tick());
      }
    }
  }
  CHECK(modes[0] > 0 && modes[1] > 0 && modes[2] > 0 && waits > 0);
  for (int t = 0; t < minutes_per_day * 4; t += 2) {
    std::array<int, Transit::fleet> aboard{};
    for (int id = 0; id < c.population(); ++id) {
      auto s = life.routine(id, t);
      if (s.activity == Activity::Riding)
        ++aboard.at(s.bus);
    }
    for (int count : aboard)
      CHECK(count <= Transit::capacity);
  }
  // Saturate a section. Later riders take the following service or another
  // mode.
  Transit busy = service;
  auto first = busy.departure(0, 1, 60.);
  CHECK(first.from == 0);
  for (int i = 0; i < Transit::capacity; ++i)
    busy.reserve(first);
  auto later = busy.departure(0, 1, 60.);
  CHECK(later.run == first.run + 1);
}
void check_geographic_terrain() {
  using namespace city;
  Site site;
  site.latitude = 47.342;
  site.longitude = .465;
  site.elevations.resize(Site::side * Site::side);
  for (int z = 0; z < Site::side; ++z)
    for (int x = 0; x < Site::side; ++x)
      site.elevations[z * Site::side + x] = 400 + x + 2*z;
  site.lake.resize(site.elevations.size());
  CHECK(site.suitable());
  CHECK(std::abs(site.height({10, 10}) - 8.15) < 1e-8);
  City inland(31, site), fixture(31);
  CHECK(inland.weather().sun_up == weather_at(31, site.latitude, 0).sun_up);
  CHECK(inland.height({40, 80}) != fixture.height({40, 80}));
  for (const auto &r : inland.roads())
    for (auto p : r.path)
      CHECK(inland.street_height(r, p) == site.height(p));
  CHECK(inland.facilities().size() == 2);
  // Hold geography constant and compare growth in logical block coordinates.
  // This detects layouts that merely rotate or redraw the same connections.
  City other(42, site);
  auto start = inland.roads().size(), other_start = other.roads().size();
  auto expansion = [](const City &city, size_t start) {
    std::set<std::array<int, 4>> links;
    for (size_t i = start; i < city.roads().size(); ++i) {
      const auto &road = city.roads()[i];
      const auto &a = city.nodes()[road.a], &b = city.nodes()[road.b];
      auto ends = std::minmax({std::pair{a.col, a.row}, std::pair{b.col, b.row}});
      links.insert({ends.first.first, ends.first.second,
                    ends.second.first, ends.second.second});
    }
    return links;
  };
  inland.advance(38400);
  other.advance(38400);
  auto growth = expansion(inland, start), alternate = expansion(other, other_start);
  CHECK(growth.size() >= 8 && alternate.size() >= 8);
  CHECK(growth != alternate);
  auto recovered = restore(checkpoint(inland));
  CHECK(recovered && recovered->digest() == inland.digest());
  CHECK(recovered->site().longitude == site.longitude);
  auto middle = site.elevations.size()/2;
  site.lake[middle] = 1;
  CHECK(!site.suitable());
  site.lake[middle] = 0;
  site.elevations[middle] += 1600;
  CHECK(!site.suitable());
  std::fill(site.elevations.begin(), site.elevations.end(), -25);
  CHECK(!site.suitable());
}
void check_market() {
  using namespace city;
  City c(147);
  const auto &e = c.economy();
  auto cash = [&]() {
    long long balance = 0;
    for (auto &b : e.places())
      balance += b.cash;
    for (auto &w : e.wallets())
      balance += w.cash;
    return balance;
  };
  auto goods = [&]() {
    int count = 0;
    for (auto &b : e.places())
      count += b.stock + b.pending;
    return count;
  };
  auto opening_cash = cash();
  int opening_goods = goods(), opening_sales = e.sales(),
      opening_output = e.production(), people = c.population();
  CHECK(!e.shipments().empty());
  auto s = e.shipments().front();
  CHECK(e.places()[s.shop].pending == s.units &&
        e.places()[s.shop].goods == e.places()[s.supplier].goods);
  CHECK(e.places()[s.supplier].staff > 0);
  auto yard = e.van(c, s, s.ordered), dock = e.van(c, s, s.arrival);
  CHECK(distance(yard.position, c.buildings()[s.supplier].pos) < 16);
  CHECK(distance(dock.position, c.buildings()[s.shop].pos) < 16);
  CHECK(distance(yard.position, dock.position) > 3);
  c.advance(s.completed - 1);
  auto before = e.places()[s.shop];
  CHECK(before.pending == s.units && before.received == 0);
  c.advance(1);
  const auto &after = e.places()[s.shop];
  CHECK(after.received == s.units && after.pending == 0 &&
        after.stock == before.stock + s.units);
  c.advance(1500 - c.tick());
  CHECK(e.sales() > opening_sales && e.deliveries() > 0 &&
        e.production() > opening_output);
  for (int i = people; i < c.population(); ++i)
    opening_cash += 48 + c.life().people()[i].variation % 36;
  CHECK(cash() == opening_cash);
  CHECK(goods() == opening_goods + (e.production() - opening_output) -
                       (e.sales() - opening_sales));
  int spending = 0, wages = 0, payroll = 0;
  for (auto &w : e.wallets()) {
    CHECK(w.cash >= 0);
    if (w.spent)
      CHECK(w.receipt >= 0 && c.buildings().at(w.shop).use == Use::Shops);
    spending += w.spent;
    wages += w.wages;
  }
  for (auto &b : e.places()) {
    CHECK(b.cash >= 0 && b.stock >= 0 && b.pending >= 0);
    payroll += b.wages;
  }
  CHECK(spending == retail_price * e.sales() && wages == payroll && wages > 0);
}
void check_construction() {
  city::City city(147);
  for (const auto &street : city.roads())
    CHECK(street.opens == 0);
  const int id = city.roads().size();
  while (int(city.roads().size()) == id && city.tick() < 10000)
    city.advance(1);
  auto street = city.roads().at(id);
  CHECK(street.started == city.tick() && street.opens > street.started);
  while (city.tick() < street.opens) {
    auto route = city.road_route(street.a, street.b);
    CHECK(std::find(route.begin(), route.end(), id) == route.end());
    for (const auto &car : city.vehicles()) {
      CHECK(city.roads()[car.edge].opens <= city.tick());
      for (int edge : car.route)
        CHECK(city.roads()[edge].opens <= city.tick());
    }
    for (const auto &shipment : city.economy().shipments())
      for (const auto &leg : shipment.route)
        CHECK(city.roads()[leg.edge].opens <= shipment.ordered);
    city.advance(1);
  }
  CHECK(city.road_route(street.a, street.b) == std::vector<int>{id});
  CHECK(city.events().back().tick == street.opens);
  CHECK(city.events().back().text == "Street opened to traffic");
}

void check_public_places() {
  using namespace city;
  City c(0);
  c.advance(60000);
  std::set<FacilityKind> services;
  for (auto &f:c.facilities()) {
    if (!is_service(f.kind)) continue;
    services.insert(f.kind);
    CHECK(f.catchment>0 && f.opens<=c.tick());
  }
  CHECK(services.size()==4);
  bool in_class=false;
  for (int id=0;id<c.population();++id) {
    const auto &p=c.life().people()[id];
    if(p.school<0) continue;
    CHECK(p.child && c.facilities()[p.school].kind==FacilityKind::School);
    int day=std::max(p.first_day,p.school_day);
    while(day%7>=5) ++day;
    auto at=[&](double minute){ return c.life().routine(id,
      (day*minutes_per_day+minute-opening_minute)*ticks_per_minute); };
    auto walk=at(p.class_start-p.school_walk*.5), back=at(p.class_start+120.+p.school_walk*.5);
    CHECK(walk.activity==Activity::Walking && walk.facility==p.school && !walk.reverse);
    CHECK(at(p.class_start+30.).activity==Activity::School);
    CHECK(back.activity==Activity::Walking && back.reverse);
    CHECK(distance(c.life().paths()[walk.route].points.back().pos,c.facilities()[p.school].gate)<.01);
    in_class=true;
  }
  CHECK(in_class);
  std::set<FacilityKind> responding;
  for(int i=0;i<120;++i) {
    c.advance(60);
    std::set<int> busy;
    for(const auto &call:c.responses()) {
      const auto &station=c.facilities()[call.station];
      CHECK(busy.insert(call.station).second && station.opens<=call.start);
      CHECK(call.outward.front().edge==station.frontage && call.returning.back().edge==station.frontage);
      CHECK(call.outward.back().edge==c.buildings()[call.lot].frontage);
      for(const auto &leg:call.outward) CHECK(c.roads()[leg.edge].opens<=call.start);
      CHECK(call.start<=call.arrival && call.arrival<call.leaving && call.leaving<=call.end);
      responding.insert(station.kind);
    }
  }
  CHECK(responding.size()==3);
  auto inspect=[](const City &city, FacilityKind expected) {
    int total=0;
    for(const auto &f:city.facilities()) if(is_landmark(f.kind)) {
      ++total;
      CHECK(f.radius >= (expected==FacilityKind::BoulevardMonument ? 34. : 29.));
      CHECK(f.kind==expected && f.started>=24*minutes_per_day*ticks_per_minute);
      CHECK(city.site().elevation(f.center)>1.4 && !city.site().inland_water(f.center));
      for (const auto &lot : city.buildings())
        CHECK(distance(f.center,lot.pos) >= f.radius + 6.4);
      for (const auto &nearby : city.facilities())
        if (&nearby != &f) CHECK(distance(f.center, nearby.center) >= f.radius + nearby.radius + 2.);
      if (expected==FacilityKind::WaterfrontMonument) {
        int water_views=0;
        for (int ray=0; ray<12; ++ray) {
          double a=ray*3.141592653589793/6.;
          Point shore{f.center.x+46.*std::sin(a),f.center.z+46.*std::cos(a)};
          Point water{f.center.x+59.*std::sin(a),f.center.z+59.*std::cos(a)};
          water_views += city.site().elevation(shore)<=0 && city.site().elevation(water)<=0;
        }
        CHECK(water_views>=2);
      }
      if(expected==FacilityKind::BoulevardMonument)
        CHECK(std::any_of(city.roads().begin(),city.roads().end(),[&](auto &r){
          return r.type==RoadClass::Arterial && distance(r.path[4],f.center)<100.; }));
    }
    CHECK(total==1);
  };
  City shore(33);
  shore.advance(330000);
  inspect(shore, FacilityKind::WaterfrontMonument);
  City other(481);
  other.advance(145000);
  inspect(other,FacilityKind::BoulevardMonument);
  // Sample design draws independently of how often a particular fixture
  // supplies the necessary waterfront or boulevard site.
  std::set<std::string> designs;
  Facility parcel{};
  parcel.frontage = 19;
  for (auto kind : {FacilityKind::BoulevardMonument, FacilityKind::WaterfrontMonument}) {
    parcel.kind = kind;
    for (int seed = 0; seed < 100; ++seed) {
      const auto design = landmark_design(seed, parcel);
      CHECK(design.height_scale >= .98 && design.height_scale <= 1.17);
      CHECK(design.palette >= 0 && design.palette < 4);
      CHECK(std::string(design.name) == facility_name(seed, parcel));
      designs.insert(design.model);
    }
  }
  CHECK(designs.size() == 6);
}

void check_grown_districts(const city::City &c) {
  using namespace city;
  // Traverse the open graph from the founding intersection. Every usable
  // road must be reachable and share its exact endpoints with the routing
  // graph.
  std::vector<int> pending{0};
  std::vector<bool> reached(c.nodes().size());
  reached[0] = true;
  while (!pending.empty()) {
    int n = pending.back();
    pending.pop_back();
    for (int edge : c.nodes()[n].edges) {
      const auto &road = c.roads()[edge];
      if (road.opens > c.tick())
        continue;
      int next = road.a == n ? road.b : road.a;
      if (reached[next])
        continue;
      reached[next] = true;
      pending.push_back(next);
    }
  }
  int tips = 0, open = 0;
  for (const auto &node : c.nodes())
    tips += node.edges.size() == 1;
  CHECK(tips * 3 < int(c.nodes().size()));
  for (size_t i = 0; i < c.roads().size(); ++i) {
    const auto &r = c.roads()[i];
    if (r.opens <= c.tick()) {
      CHECK(reached[r.a] && reached[r.b]);
      ++open;
    }
    CHECK(distance(r.path.front(), c.nodes()[r.a].pos) < 1e-7);
    CHECK(distance(r.path.back(), c.nodes()[r.b].pos) < 1e-7);
    if (!r.surveyed)
      continue;
    for (size_t j = 0; j < i; ++j) {
      const auto &s = c.roads()[j];
      if (r.a == s.a || r.a == s.b || r.b == s.a || r.b == s.b)
        continue;
      if (distance(r.path[4], s.path[4]) > r.lengths.back() + s.lengths.back())
        continue;
      for (int u = 1; u <= 8; ++u)
        for (int v = 1; v <= 8; ++v)
          CHECK(segment_clearance(r.path[u - 1], r.path[u], s.path[v - 1],
                                  s.path[v]) > 0.01);
    }
  }
  CHECK(open > int(c.nodes().size()) + 12);
  int peak = 0, deep = 0, inner = 0, outer = 0, inner_floors = 0,
      outer_floors = 0;
  for (const auto &lot : c.buildings()) {
    peak = std::max(peak, lot.floors);
    deep += lot.rear != 0.;
    double d = std::numeric_limits<double>::infinity();
    for (auto centre : c.district_centres())
      d = std::min(d, distance(lot.pos, centre));
    if (d < 110.) {
      ++inner;
      inner_floors += lot.floors;
    }
    if (d > 270.) {
      ++outer;
      outer_floors += lot.floors;
    }
  }
  CHECK(peak >= 18 && deep > 0 && inner > 0 && outer > 0);
  CHECK(double(inner_floors) / inner > double(outer_floors) / outer + 2.);
}

int main() {
  using namespace city;
  check_weather();
  check_facilities();
  check_commuting();
  check_geographic_terrain();
  check_market();
  check_construction();
  // Prior surveyed-street games replay to their original checksum. Their
  // first new planning survey can then choose a commercial corner.
  auto prior = restore("EMERGENCE-12 147 14400 12410467977675168576 0 -1");
  CHECK(prior && prior->main_street_corner() < 0);
  prior->advance(7200);
  CHECK(prior->main_street_corner() >= 0 && restore(checkpoint(*prior)));
  for (unsigned seed : {147u, 42u, 2026u}) {
    City small(seed);
    while (small.population() < 2700 && small.tick() < 80000)
      small.advance(720);
    int corner = small.main_street_corner();
    CHECK(corner >= 0 && small.buildings()[corner].use == Use::Shops);
    CHECK(small.life().occupancies()[corner].hired > 0 &&
          small.buildings()[corner].floors >= 4);
    int early = small.buildings()[corner].floors;
    while (small.population() < 9000 && small.tick() < 180000)
      small.advance(720);
    CHECK(small.main_street_corner() == corner &&
          small.buildings()[corner].floors > early);
    auto &b = small.buildings()[corner];
    CHECK(std::count_if(small.buildings().begin(), small.buildings().end(),
                        [&](const auto &nearby) {
                          return &nearby != &b && nearby.floors >= 4 &&
                                 distance(nearby.pos, b.pos) < 90.;
                        }) >= 2);
  }
  check_public_places();
  auto start = std::chrono::steady_clock::now();
  for (auto seed : {147u, 42u, 2026u}) {
    City a(seed), b(seed);
    auto roads = a.roads().size(), lots = a.buildings().size();
    int people = a.population();
    CHECK(people >= 1000 && people <= 5000);
    auto initial = a.digest();
    a.advance(0);
    CHECK(initial == a.digest());
    a.advance(640 * planning_interval);
    for (int i = 0; i < 64; ++i)
      b.advance(10 * planning_interval);
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
        CHECK(r.bridge || ground(p) > 1.);
    for (auto &car : a.vehicles()) {
      const auto &path = a.roads().at(car.edge);
      double yaw;
      auto p = a.vehicle_position(car, yaw);
      CHECK(car.along >= 0 && car.along < path.lengths.back());
      CHECK(std::isfinite(yaw));
      CHECK(a.street_height(path, p) > 0 &&
            (car.from == path.a || car.from == path.b));
    }
    std::cout << "Seed " << seed << " at 0 / 640 ticks: residents " << people
              << " / " << a.population() << ", roads " << roads << " / "
              << a.roads().size() << ", buildings " << lots << " / "
              << a.buildings().size() << "\n";
  }
  // A checksum produced by the preceding release after reaching the old boundary.
  auto migrated = restore("EMERGENCE-10 147 600000 242605203417491144");
  CHECK(migrated && migrated->population() == 51667);
  if (migrated) {
    migrated->advance(planning_interval);
    CHECK(migrated->planning_extent().x > township_half_width);
    auto reopened = restore(checkpoint(*migrated));
    CHECK(reopened && reopened->digest() == migrated->digest());
  }
  City regional(147u);
  double initial_span = regional.bounds()[2] - regional.bounds()[0];
  regional.advance(9600 * planning_interval);
  CHECK(regional.bounds()[2] - regional.bounds()[0] > 3. * initial_span);
  check_grown_districts(regional);
  auto bounds = regional.bounds();
  CHECK(bounds[0] < -township_half_width || bounds[1] < -township_half_depth ||
        bounds[2] > township_half_width || bounds[3] > township_half_depth);
  CHECK(regional.renewals().size() > 0);
  CHECK(std::none_of(regional.facilities().begin(), regional.facilities().end(),
                     [](const auto &f) { return is_landmark(f.kind); }));
  bool tall = false, industrial = false;
  int banks[2] = {};
  for (const auto &b : regional.buildings()) {
    ++banks[b.pos.x > river_center(b.pos.z)];
    tall |= b.floors >= 9;
    industrial |= b.use == Use::Works;
    CHECK(ground(b.pos) > 2.5);
  }
  CHECK(tall && industrial && banks[0] > 100 && banks[1] > 100);
  int bridges = 0;
  for (const auto &road : regional.roads()) {
    if (!road.bridge)
      continue;
    ++bridges;
    bool water = false;
    CHECK(ground(road.path.front()) > 1.8 && ground(road.path.back()) > 1.8);
    for (const auto &p : road.path) {
      water |= ground(p) < 0.;
      CHECK(road_height(road, p) > 1.8);
    }
    CHECK(water);
  }
  CHECK(bridges >= 1);
  CHECK(road_width(RoadClass::Arterial) > 2 * road_width(RoadClass::Local));
  CHECK(speed_factor(RoadClass::Arterial) > speed_factor(RoadClass::Collector));
  const auto &life = regional.life();
  CHECK(int(life.people().size()) == regional.population());
  std::vector<int> beds(regional.buildings().size()), jobs(beds.size());
  int employed = 0;
  for (const auto &person : life.people()) {
    ++beds.at(person.home);
    CHECK(regional.buildings()[person.home].use == Use::Housing);
    if (person.work >= 0) {
      ++jobs.at(person.work);
      ++employed;
      CHECK(regional.buildings()[person.work].use != Use::Housing);
    }
    if (person.shop >= 0)
      CHECK(regional.buildings()[person.shop].use == Use::Shops);
  }
  for (size_t i = 0; i < life.occupancies().size(); ++i) {
    const auto &place = life.occupancies()[i];
    CHECK(beds[i] == place.housed && beds[i] <= place.beds);
    CHECK(jobs[i] == place.hired && jobs[i] <= place.jobs);
  }
  CHECK(employed == life.employed() && employed <= life.jobs());
  City opening;
  int observed = -1;
  for (int id = 0; id < opening.population(); ++id) {
    auto &p = opening.life().people()[id];
    if (p.work >= 0 && p.errand >= 0 && p.mode == Mode::Walk) {
      observed = id;
      break;
    }
  }
  CHECK(observed >= 0);
  const auto &record = opening.life().people()[observed];
  std::array<int, 8> observed_states{};
  bool commute = false, lunch = false, returned = false;
  for (int minute = 0; minute < minutes_per_day; ++minute) {
    auto s = opening.life().routine(
        observed,
        (minutes_per_day + minute - opening_minute) * ticks_per_minute);
    ++observed_states[int(s.activity)];
    if (s.activity == Activity::Walking) {
      auto pose = opening.life().pose(opening, observed, s);
      CHECK(std::isfinite(pose.height));
      commute |= s.from == record.home && s.to == record.work;
      lunch |= s.from == record.work && s.to == record.shop;
      returned |= s.from == record.work && s.to == record.home;
    }
    if (minute == 23 * 60)
      CHECK(s.activity == Activity::Home && s.to == record.home);
  }
  CHECK(commute && lunch && returned);
  for (int i = 0; i <= int(Activity::Walking); ++i)
    CHECK(observed_states[i] > 0);
  const auto renewed = restore(checkpoint(regional));
  CHECK(renewed && renewed->digest() == regional.digest());
  std::cout << "Regional replay: " << regional.population() << " residents, "
            << regional.buildings().size() << " buildings and " << bridges
            << " crossings.\n";
  std::cout << "Test time "
            << std::chrono::duration<double>(std::chrono::steady_clock::now() -
                                             start)
                   .count()
            << " s\n";
}
