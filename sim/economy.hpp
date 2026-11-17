#pragma once
#include "geo/terrain.hpp"
#include <cstdint>
#include <vector>

namespace city {
class City;
enum class Goods { Provisions, Garments };
constexpr int wholesale_price = 6, retail_price = 12;
struct Business {
  int stock = 0, cash = 0, pending = 0, produced = 0, sold = 0, received = 0,
      wages = 0;
  int last_sale = -1, last_delivery = -1, last_batch = -1, staff = 0, labor = 0,
      missed = 0;
  bool open = false;
  Goods goods = Goods::Provisions;
};
struct Wallet {
  int cash = 0, wages = 0, spent = 0, purchase_day = -1, receipt = -1,
      shop = -1;
};
struct DriveLeg {
  int edge;
  double from, to, end_time;
};
struct Shipment {
  int id, supplier, shop, units, ordered, arrival, completed;
  std::vector<DriveLeg> route;
};
struct VanPose {
  Point position;
  double height, yaw;
};
class Economy {
public:
  void open(const City &city, int lot);
  void update(const City &city);
  const auto &places() const { return places_; }
  const auto &wallets() const { return wallets_; }
  const auto &shipments() const { return active_; }
  VanPose van(const City &city, const Shipment &s, double tick) const;
  int stock_revision() const {
    return next_id_ + delivered_ + sales_ + production_ +
           int(shops_.size() + works_.size());
  }
  int deliveries() const { return delivered_; }
  int sales() const { return sales_; }
  int production() const { return production_; }
  uint64_t digest() const;

private:
  std::vector<Business> places_;
  std::vector<Wallet> wallets_;
  std::vector<int> shops_, works_;
  std::vector<Shipment> active_;
  int next_id_ = 1, delivered_ = 0, sales_ = 0, production_ = 0, next_shop_ = 0;
  void trade(const City &city);
  void order(const City &city);
};
} // namespace city
