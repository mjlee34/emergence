#include "sim/economy.hpp"
#include "sim/city.hpp"
#include <algorithm>
#include <bit>
#include <cmath>
#include <limits>
namespace city {
namespace {
constexpr int loading = 20, unloading = 28, cadence = 40;
constexpr double van_speed = .84;
Shipment manifest(const City &c, int id, int supplier, int shop, int units) {
  Shipment s{
      id,       supplier, shop, units,
      c.tick(), 0,        0,    drive_route(c, supplier, shop, van_speed)};
  s.arrival = s.ordered + loading + int(std::ceil(s.route.back().end_time));
  s.completed = s.arrival + unloading;
  return s;
}
} // namespace
VanPose Economy::van(const City &c, const Shipment &s, double tick) const {
  return drive_pose(c, s.route, std::max(0., tick - s.ordered - loading),
                    van_speed);
}
void Economy::open(const City &c, int id) {
  if (id >= int(places_.size()))
    places_.resize(id + 1);
  auto &b = places_[id];
  auto &lot = c.buildings()[id];
  if (b.open || lot.use == Use::Housing)
    return;
  b.open = true;
  b.goods = lot.style % 4 == 3 ? Goods::Garments : Goods::Provisions;
  b.cash = 800 + 8 * c.life().occupancies()[id].jobs;
  if (lot.use == Use::Works) {
    works_.push_back(id);
    b.stock = 64;
  } else {
    shops_.push_back(id);
    b.stock = 12 + lot.style % 24;
  }
}
void Economy::update(const City &c) {
  while (int(wallets_.size()) < c.population()) {
    auto v = c.life().people()[wallets_.size()].variation;
    Wallet w;
    w.cash = 48 + int(v % 36);
    wallets_.push_back(w);
  }
  // Freight arrives even between the ten-minute market clearings.
  for (auto it = active_.begin(); it != active_.end();) {
    if (it->completed > c.tick()) {
      ++it;
      continue;
    }
    auto &shop = places_[it->shop];
    shop.stock += it->units;
    shop.pending -= it->units;
    shop.received += it->units;
    shop.last_delivery = c.tick();
    ++delivered_;
    it = active_.erase(it);
  }
  if (c.tick() % cadence == 0) {
    trade(c);
    order(c);
  }
}
void Economy::index_schedules(const City &c) {
  const auto &life = c.life();
  if (indexed_jobs_ != life.job_revision()) {
    // Previously waiting residents can receive a new schedule overnight.
    for (auto &hour : hourly_roster_) hour.clear();
    indexed_people_ = 0;
    indexed_jobs_ = life.job_revision();
  }
  for (; indexed_people_ < c.population(); ++indexed_people_) {
    const auto &r = life.people()[indexed_people_];
    double first, last;
    if (r.work >= 0) {
      first = r.leave_home;
      last = r.finish;
    } else if (r.shop >= 0) {
      first = 405 + r.variation % 545 + r.trips[0].duration;
      last = r.outing_return;
    } else {
      continue;
    }
    for (int h = int(first) / 60; h <= std::min(23, int(last) / 60); ++h)
      hourly_roster_[h].push_back(indexed_people_);
  }
}

void Economy::trade(const City &c) {
  index_schedules(c);
  for (auto &b : places_) b.staff = 0;
  const int absolute = opening_minute + c.tick() / ticks_per_minute;
  const int day = absolute / minutes_per_day;
  clearing_.clear();
  for (int id : hourly_roster_[(absolute % minutes_per_day) / 60]) {
    const auto phase = c.life().routine(id, c.tick());
    if (phase.activity == Activity::Work) {
      ++places_[phase.to].staff;
      if ((c.tick() / cadence + id) % 6 == 0)
        clearing_.push_back({id, phase.to, true});
    } else if (phase.activity == Activity::Shopping && wallets_[id].purchase_day != day) {
      clearing_.push_back({id, phase.to, false});
    }
  }
  // Staff counts must be complete before the first shopper can be served.
  for (const auto &order : clearing_) {
    auto &w = wallets_[order.resident];
    if (order.wage) {
      auto &firm = places_[order.place];
      // Stagger hourly wage payments across staff members.
      if (firm.cash >= 2) {
        firm.cash -= 2;
        firm.wages += 2;
        w.cash += 2;
        w.wages += 2;
      }
    } else {
      auto &shop = places_[order.place];
      if (!shop.staff)
        continue;
      if (shop.stock == 0 || w.cash < retail_price) {
        ++shop.missed;
        w.purchase_day = day;
        continue;
      }
      --shop.stock;
      ++shop.sold;
      ++sales_;
      shop.cash += retail_price;
      w.cash -= retail_price;
      w.spent += retail_price;
      w.purchase_day = day;
      w.receipt = c.tick();
      w.shop = order.place;
      shop.last_sale = c.tick();
    }
  }
  for (int id : works_) {
    auto &b = places_[id];
    if (b.stock >= 128)
      continue;
    b.labor += b.staff;
    int made = std::min(128 - b.stock, b.labor / 6);
    b.labor %= 6;
    if (made) {
      b.stock += made;
      b.produced += made;
      production_ += made;
      b.last_batch = c.tick();
    }
  }
}
void Economy::order(const City &c) {
  int minute = (opening_minute + c.tick() / ticks_per_minute) % minutes_per_day;
  if (minute < 360 || minute > 1200 || shops_.empty())
    return;
  // Round-robin prevents the first shop from monopolising a supplier's van.
  int begin = next_shop_;
  for (int i = 0; i < int(shops_.size()); ++i) {
    int ix = (begin + i) % shops_.size(), id = shops_[ix];
    auto &b = places_[id];
    if (b.pending || b.stock > 26 || b.cash < 8 * wholesale_price)
      continue;
    int chosen = -1;
    double best = std::numeric_limits<double>::infinity();
    for (int src : works_) {
      const auto &factory = places_[src];
      if (factory.goods != b.goods || factory.stock < 8 || !factory.staff)
        continue;
      if (std::any_of(active_.begin(), active_.end(),
                      [&](const Shipment &s) { return s.supplier == src; }))
        continue;
      double dist = distance(c.buildings()[id].pos, c.buildings()[src].pos);
      if (dist < best) {
        chosen = src;
        best = dist;
      }
    }
    if (chosen < 0)
      continue;
    auto &factory = places_[chosen];
    int units = std::min({48, factory.stock, b.cash / wholesale_price});
    factory.stock -= units;
    b.pending += units;
    b.cash -= units * wholesale_price;
    factory.cash += units * wholesale_price;
    active_.push_back(manifest(c, next_id_++, chosen, id, units));
    next_shop_ = (ix + 1) % shops_.size();
  }
}
uint64_t Economy::digest() const {
  uint64_t h = 14695981039346656037ULL;
  auto mix = [&](uint64_t v) {
    h ^= v;
    h *= 1099511628211ULL;
  };
  for (auto v : {next_id_, next_shop_, sales_, delivered_, production_})
    mix(v);
  for (auto &b : places_) {
    for (auto v : {int(b.goods), int(b.open), b.stock, b.cash, b.pending,
                   b.produced, b.sold, b.received, b.wages, b.labor, b.staff,
                   b.last_sale, b.last_batch, b.last_delivery, b.missed})
      mix(v);
  }
  for (auto &w : wallets_) {
    for (auto v : {w.cash, w.wages, w.spent, w.purchase_day, w.receipt, w.shop})
      mix(v);
  }
  for (auto &s : active_) {
    for (auto v :
         {s.id, s.supplier, s.shop, s.units, s.ordered, s.arrival, s.completed})
      mix(v);
    for (auto &leg : s.route) {
      mix(leg.edge);
      mix(std::bit_cast<uint64_t>(leg.from));
      mix(std::bit_cast<uint64_t>(leg.to));
      mix(std::bit_cast<uint64_t>(leg.end_time));
    }
  }
  return h;
}
} // namespace city
