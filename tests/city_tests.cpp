#include "replay/checkpoint.hpp"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <iostream>
#include <stdexcept>
#define CHECK(expr)                                                            \
  do {                                                                         \
    if (!(expr))                                                               \
      throw std::runtime_error(#expr);                                         \
  } while (false)
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
  CHECK(inland.height({40, 80}) != fixture.height({40, 80}));
  for (const auto &r : inland.roads())
    for (auto p : r.path)
      CHECK(inland.street_height(r, p) == site.height(p));
  inland.advance(1501);
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

int main() {
  using namespace city;
  check_geographic_terrain();
  check_market();
  check_construction();
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
      CHECK(road_height(path, p) > 0 &&
            (car.from == path.a || car.from == path.b));
    }
    std::cout << "Seed " << seed << " at 0 / 640 ticks: residents " << people
              << " / " << a.population() << ", roads " << roads << " / "
              << a.roads().size() << ", buildings " << lots << " / "
              << a.buildings().size() << "\n";
  }
  City regional(147u);
  double initial_span = regional.bounds()[2] - regional.bounds()[0];
  regional.advance(7200 * planning_interval);
  CHECK(regional.bounds()[2] - regional.bounds()[0] > 3. * initial_span);
  CHECK(regional.renewals().size() > 0);
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
  CHECK(bridges == 2);
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
    if (p.work >= 0 && p.errand >= 0) {
      observed = id;
      break;
    }
  }
  CHECK(observed >= 0);
  const auto &record = opening.life().people()[observed];
  std::array<int, 4> observed_states{};
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
  for (int duration : observed_states)
    CHECK(duration > 0);
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
