#include "sim/city.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
using namespace godot;

class CityModel : public RefCounted {
  GDCLASS(CityModel, RefCounted)
  city::City state;
  Vector3 surface(city::Point p) const {
    return Vector3(p.x, state.height(p), p.z);
  }

protected:
  static void _bind_methods() {
    ClassDB::bind_method(D_METHOD("settle_at", "seed", "latitude", "longitude", "elevations", "lakes"), &CityModel::settle_at);
    ClassDB::bind_method(D_METHOD("is_geographic"), &CityModel::is_geographic);
    ClassDB::bind_method(D_METHOD("inland_water", "x", "z"), &CityModel::inland_water);
    ClassDB::bind_method(D_METHOD("sea_level"), &CityModel::sea_level);
    ClassDB::bind_method(D_METHOD("reset", "seed"), &CityModel::reset);
    ClassDB::bind_method(D_METHOD("step", "ticks"), &CityModel::step);
    ClassDB::bind_method(D_METHOD("height_at", "x", "z"),
                         &CityModel::height_at);
    ClassDB::bind_method(D_METHOD("river_x", "z"), &CityModel::river_x);
    ClassDB::bind_method(
        D_METHOD("street_people", "fraction", "focus", "radius", "selected"),
        &CityModel::street_people);
    ClassDB::bind_method(D_METHOD("resident", "id", "fraction"),
                         &CityModel::resident);
    ClassDB::bind_method(D_METHOD("walking_plan", "id", "fraction"),
                         &CityModel::walking_plan);
    ClassDB::bind_method(D_METHOD("business", "id"), &CityModel::business);
    ClassDB::bind_method(D_METHOD("delivery_route", "id"),
                         &CityModel::delivery_route);
    ClassDB::bind_method(D_METHOD("freight", "fraction"), &CityModel::freight);
    ClassDB::bind_method(D_METHOD("summary"), &CityModel::summary);
    ClassDB::bind_method(D_METHOD("renewed_lot", "index"),
                         &CityModel::renewed_lot);
    ClassDB::bind_method(D_METHOD("street", "index"), &CityModel::street);
    ClassDB::bind_method(D_METHOD("lot", "index"), &CityModel::lot);
    ClassDB::bind_method(D_METHOD("traffic", "fraction"), &CityModel::traffic);
  }

public:
  bool settle_at(int seed, double latitude, double longitude, const PackedInt32Array &samples, const PackedByteArray &lakes) {
    if (samples.size() != city::Site::side * city::Site::side || lakes.size() != samples.size())
      return false;
    city::Site site{latitude, longitude, {samples.ptr(), samples.ptr() + samples.size()}, {lakes.ptr(), lakes.ptr() + lakes.size()}};
    if (!site.suitable())
      return false;
    state = city::City(seed, std::move(site));
    return true;
  }
  bool is_geographic() const { return state.site().geographic(); }
  bool inland_water(double x, double z) const { return state.site().inland_water({x, z}); }
  double sea_level() const { return -state.site().datum(); }
  void reset(int seed) { state = city::City(seed); }
  void step(int ticks) { state.advance(ticks); }
  double height_at(double x, double z) const { return state.height({x, z}); }
  double river_x(double z) const { return city::river_center(z); }
  Dictionary summary() const {
    Dictionary d;
    const auto &economy = state.economy();
    d["stock_revision"] = economy.stock_revision();
    d["sales"] = economy.sales();
    d["delivered"] = economy.deliveries();
    d["produced"] = economy.production();
    PackedInt32Array stocks;
    for (auto &b : economy.places())
      stocks.push_back(b.open ? b.stock : -1);
    d["stocks"] = stocks;
    d["tick"] = state.tick();
    int absolute = state.tick() / city::ticks_per_minute + city::opening_minute;
    d["minute"] = absolute % city::minutes_per_day;
    d["day"] = 1 + absolute / city::minutes_per_day;
    d["construction_ticks"] = city::construction_ticks;
    std::array<int, 4> totals{};
    PackedInt32Array occupants;
    occupants.resize(state.buildings().size());
    const auto &life = state.life();
    for (int id = 0; id < state.population(); ++id) {
      auto action = life.routine(id, state.tick());
      ++totals[int(action.activity)];
      if (action.activity != city::Activity::Walking)
        ++occupants.ptrw()[action.to];
    }
    d["occupants"] = occupants;
    d["home"] = totals[0];
    d["at_work"] = totals[1];
    d["shopping"] = totals[2];
    d["walking"] = totals[3];
    d["employed"] = life.employed();
    d["workforce"] = life.workforce();
    d["jobs"] = life.jobs();
    d["population"] = state.population();
    d["roads"] = int(state.roads().size());
    d["buildings"] = int(state.buildings().size());
    auto bounds = state.bounds();
    d["bounds"] = Vector4(bounds[0], bounds[1], bounds[2], bounds[3]);
    d["renewals"] = int(state.renewals().size());
    d["event"] = String(state.events().back().text.c_str());
    d["event_tick"] = state.events().back().tick;
    return d;
  }
  Dictionary resident(int id, double fraction) const {
    Dictionary d;
    ERR_FAIL_INDEX_V(id, state.population(), d);
    const auto &life = state.life();
    const auto &r = life.people()[id];
    auto activity = life.routine(id, state.tick() + fraction);
    auto pose = life.pose(state, id, activity, state.tick() + fraction);
    d["id"] = id;
    const auto &wallet = state.economy().wallets()[id];
    d["wallet"] = wallet.cash;
    d["wages"] = wallet.wages;
    d["receipt"] = wallet.receipt;
    d["store"] = wallet.shop;
    d["variation"] = int64_t(r.variation);
    d["home"] = r.home;
    d["work"] = r.work;
    d["shop"] = r.shop;
    d["seeking"] = r.seeks_work;
    d["activity"] = int(activity.activity);
    d["target"] = activity.to;
    d["shift"] = r.leave_home + int(std::ceil(r.commute_minutes));
    d["finish"] = r.finish;
    d["position"] = Vector3(pose.pos.x, pose.height, pose.pos.z);
    return d;
  }
  PackedVector2Array walking_plan(int id, double fraction) const {
    PackedVector2Array line;
    ERR_FAIL_INDEX_V(id, state.population(), line);
    const auto &life = state.life();
    auto phase = life.routine(id, state.tick() + fraction);
    const auto &person = life.people()[id];
    int route = phase.route >= 0 ? phase.route : person.commute;
    if (route < 0)
      route = person.errand;
    if (route >= 0)
      for (const auto &wp : life.paths()[route].points)
        line.push_back(Vector2(wp.pos.x, wp.pos.z));
    return line;
  }
  Dictionary street_people(double fraction, Vector2 focus, double radius,
                           int selected) const {
    const auto &life = state.life();
    PackedVector4Array poses;
    PackedInt32Array ids, modes, bags;
    std::vector<int> outdoor(state.buildings().size(), 0);
    // Residents indoors remain in occupancy totals. Sample the visible street
    // crowd at city scale.
    int stride = radius > 155 ? std::max(1, state.population() / 1300)
                              : std::max(1, state.population() / 9000);
    auto emit_person = [&](int id) {
      auto s = life.routine(id, state.tick() + fraction);
      const auto &b = state.buildings()[s.to];
      bool walking = s.activity == city::Activity::Walking;
      if (!walking) {
        if (s.activity == city::Activity::Home ||
            (s.activity == city::Activity::Work && b.use == city::Use::Shops))
          return;
        if (outdoor[s.to] >= 3 || (life.people()[id].variation % 5) != 0)
          return;
      }
      auto p = life.pose(state, id, s, state.tick() + fraction);
      if (std::abs(p.pos.x - focus.x) > radius ||
          std::abs(p.pos.z - focus.y) > radius)
        return;
      if (!walking) {
        int slot = outdoor[s.to]++;
        p.pos.x += slot * .86 * std::cos(b.yaw);
        p.pos.z -= slot * .86 * std::sin(b.yaw);
        if (s.activity == city::Activity::Shopping)
          p.yaw = b.yaw + slot * 1.8;
      }
      poses.push_back(Vector4(p.pos.x, p.height, p.pos.z, p.yaw));
      ids.push_back(id);
      modes.push_back(int(s.activity));
      const auto &w = state.economy().wallets()[id];
      bags.push_back(w.receipt >= 0 && w.shop >= 0 &&
                     (s.activity == city::Activity::Shopping ||
                      (walking && s.from == w.shop)) &&
                     (state.tick() + city::opening_minute * 4) / 5760 ==
                         (w.receipt + city::opening_minute * 4) / 5760);
    };
    if (selected >= 0 && selected < state.population())
      emit_person(selected);
    for (int id = 0; id < state.population() && ids.size() < 1200; id += stride)
      if (id != selected)
        emit_person(id);
    Dictionary d;
    d["poses"] = poses;
    d["ids"] = ids;
    d["modes"] = modes;
    d["bags"] = bags;
    return d;
  }
  Dictionary business(int id) const {
    Dictionary d;
    const auto &places = state.economy().places();
    if (id < 0 || id >= int(places.size()) || !places[id].open)
      return d;
    const auto &b = places[id];
    d["id"] = id;
    d["goods"] = int(b.goods);
    d["stock"] = b.stock;
    d["cash"] = b.cash;
    d["sold"] = b.sold;
    d["received"] = b.received;
    d["pending"] = b.pending;
    d["made"] = b.produced;
    d["staff"] = b.staff;
    d["wages"] = b.wages;
    d["missed"] = b.missed;
    d["last_sale"] = b.last_sale;
    d["last_delivery"] = b.last_delivery;
    d["last_batch"] = b.last_batch;
    return d;
  }
  PackedVector2Array delivery_route(int id) const {
    PackedVector2Array path;
    for (const auto &s : state.economy().shipments()) {
      if (s.id != id)
        continue;
      double time = s.ordered + 20;
      for (auto &leg : s.route) {
        double end = s.ordered + 20 + leg.end_time;
        for (double t = time; t < end; t += 3.) {
          auto p = state.economy().van(state, s, t).position;
          path.push_back(Vector2(p.x, p.z));
        }
        time = end;
      }
      auto p = state.economy().van(state, s, s.arrival).position;
      path.push_back(Vector2(p.x, p.z));
      break;
    }
    return path;
  }
  Array freight(double fraction) const {
    Array rows;
    for (auto &s : state.economy().shipments()) {
      Dictionary d;
      auto p = state.economy().van(state, s, state.tick() + fraction);
      d["id"] = s.id;
      d["source"] = s.supplier;
      d["shop"] = s.shop;
      d["units"] = s.units;
      d["start"] = s.ordered;
      d["arrival"] = s.arrival;
      d["end"] = s.completed;
      d["position"] = Vector3(p.position.x, p.height + .36, p.position.z);
      d["yaw"] = p.yaw;
      rows.push_back(d);
    }
    return rows;
  }
  int renewed_lot(int index) const {
    ERR_FAIL_INDEX_V(index, int(state.renewals().size()), -1);
    return state.renewals()[index];
  }
  Dictionary street(int index) const {
    Dictionary d;
    ERR_FAIL_INDEX_V(index, int(state.roads().size()), d);
    const auto &r = state.roads()[index];
    PackedVector3Array path;
    for (auto p : r.path)
      path.push_back(Vector3(p.x, state.street_height(r, p), p.z));
    const auto &a = state.nodes()[r.a], &b = state.nodes()[r.b];
    d["a"] = Vector2i(a.col, a.row);
    d["b"] = Vector2i(b.col, b.row);
    d["path"] = path;
    d["class"] = int(r.type);
    d["width"] = city::road_width(r.type);
    d["bridge"] = r.bridge;
    d["started"] = r.started;
    d["opens"] = r.opens;
    return d;
  }
  Dictionary lot(int index) const {
    Dictionary d;
    ERR_FAIL_INDEX_V(index, int(state.buildings().size()), d);
    const auto &b = state.buildings()[index];
    d["pos"] = surface(b.pos);
    d["yaw"] = b.yaw;
    d["style"] = b.style;
    d["use"] = int(b.use);
    d["frontage"] = b.frontage;
    const auto &r = state.roads()[b.frontage];
    int k = city::distance(b.pos, r.path[2]) < city::distance(b.pos, r.path[6])
                ? 2
                : 6;
    auto at = r.path[k], next = r.path[k + 1];
    d["front_sign"] = ((next.x - at.x) * (b.pos.z - at.z) -
                           (next.z - at.z) * (b.pos.x - at.x) >
                       0)
                          ? -1
                          : 1;
    const auto &places = state.life().occupancies();
    if (index < int(places.size())) {
      d["jobs"] = places[index].jobs;
      d["hired"] = places[index].hired;
      d["housed"] = places[index].housed;
    }
    d["floors"] = b.floors;
    d["started"] = b.started;
    d["previous_floors"] = b.previous_floors;
    return d;
  }
  PackedVector4Array traffic(double fraction) const {
    PackedVector4Array out;
    for (auto &v : state.vehicles()) {
      double yaw;
      auto p = state.vehicle_position(v, yaw, fraction);
      out.push_back(
          Vector4(p.x, state.street_height(state.roads()[v.edge], p), p.z, yaw));
    }
    return out;
  }
};
#ifdef __APPLE__
void register_map_view();
#endif
void init_city(ModuleInitializationLevel level) {
  if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
    GDREGISTER_CLASS(CityModel);
#ifdef __APPLE__
    register_map_view();
#endif
  }
}
void stop_city(ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT emergence_init(
    GDExtensionInterfaceGetProcAddress get, GDExtensionClassLibraryPtr lib,
    GDExtensionInitialization *init) {
  GDExtensionBinding::InitObject obj(get, lib, init);
  obj.register_initializer(init_city);
  obj.register_terminator(stop_city);
  obj.set_minimum_library_initialization_level(
      MODULE_INITIALIZATION_LEVEL_SCENE);
  return obj.init();
}
