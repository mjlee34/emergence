#include "sim/city.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
using namespace godot;

class CityModel : public RefCounted {
  GDCLASS(CityModel, RefCounted)
  city::City state;
  static Vector3 surface(city::Point p) {
    return Vector3(p.x, city::ground(p), p.z);
  }

protected:
  static void _bind_methods() {
    ClassDB::bind_method(D_METHOD("reset", "seed"), &CityModel::reset);
    ClassDB::bind_method(D_METHOD("step", "ticks"), &CityModel::step);
    ClassDB::bind_method(D_METHOD("height_at", "x", "z"),
                         &CityModel::height_at);
    ClassDB::bind_method(D_METHOD("river_x", "z"), &CityModel::river_x);
    ClassDB::bind_method(D_METHOD("summary"), &CityModel::summary);
    ClassDB::bind_method(D_METHOD("renewed_lot", "index"),
                         &CityModel::renewed_lot);
    ClassDB::bind_method(D_METHOD("street", "index"), &CityModel::street);
    ClassDB::bind_method(D_METHOD("lot", "index"), &CityModel::lot);
    ClassDB::bind_method(D_METHOD("traffic", "fraction"), &CityModel::traffic);
  }

public:
  void reset(int seed) { state = city::City(seed); }
  void step(int ticks) { state.advance(ticks); }
  double height_at(double x, double z) const { return city::ground({x, z}); }
  double river_x(double z) const { return city::river_center(z); }
  Dictionary summary() const {
    Dictionary d;
    d["tick"] = state.tick();
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
      path.push_back(Vector3(p.x, city::road_height(r, p), p.z));
    const auto &a = state.nodes()[r.a], &b = state.nodes()[r.b];
    d["a"] = Vector2i(a.col, a.row);
    d["b"] = Vector2i(b.col, b.row);
    d["path"] = path;
    d["class"] = int(r.type);
    d["width"] = city::road_width(r.type);
    d["bridge"] = r.bridge;
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
    d["floors"] = b.floors;
    d["started"] = b.started;
    return d;
  }
  PackedVector4Array traffic(double fraction) const {
    PackedVector4Array out;
    for (auto &v : state.vehicles()) {
      double yaw;
      auto p = state.vehicle_position(v, yaw, fraction);
      out.push_back(
          Vector4(p.x, city::road_height(state.roads()[v.edge], p), p.z, yaw));
    }
    return out;
  }
};
void init_city(ModuleInitializationLevel level) {
  if (level == MODULE_INITIALIZATION_LEVEL_SCENE)
    GDREGISTER_CLASS(CityModel);
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
