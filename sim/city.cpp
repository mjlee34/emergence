#include "sim/city.hpp"
#include <algorithm>
#include <bit>
#include <cmath>
#include <limits>
#include <queue>

namespace city {
namespace {
constexpr int build_time=24;
double segment_distance(Point p, Point a, Point b) {
    double x=b.x-a.x,z=b.z-a.z;
    double t=std::clamp(((p.x-a.x)*x+(p.z-a.z)*z)/(x*x+z*z),0.,1.);
    return distance(p,{a.x+x*t,a.z+z*t});
}
}
uint32_t City::draw() { random_=random_*1664525u+1013904223u; return random_; }
City::City(uint32_t seed):seed_(seed),random_(seed) {
    nodes_.push_back({0,0,street_point(0,0),{}});
    // A small market street and incomplete side streets provide the starting frontier.
    for(int dir : {-1,1}) for(int i=1;i<=2;++i)
        add_road(find_node(dir*(i-1),0),dir*i,0);
    for(int c=-2;c<=2;++c) for(int r : {-1,1})
        if(!(c==2 && r==-1)) add_road(find_node(c,0),c,r);
    for(int r : {-1,1}) for(int c=-2;c<2;++c)
        if(find_node(c+1,r)>=0 && (c+r)%3!=0) add_road(find_node(c,r),c+1,r);
    for(int pass=0;pass<4;++pass)
        for(int e=0;e<int(roads_.size());++e) develop(e,true);
    population_=capacity_*95/100;
    for(int i=0;i<22;++i) {
        Vehicle v{}; v.speed=.75+(draw()%60)*.01;
        dispatch(v,draw()%nodes_.size());
        v.along=roads_[v.edge].lengths.back()*(draw()%98)/100.;
        vehicles_.push_back(std::move(v));
    }
    record("Settlement established");
}
int City::find_node(int c,int r) const {
    for(int i=0;i<int(nodes_.size());++i)
        if(nodes_[i].col==c && nodes_[i].row==r) return i;
    return -1;
}
int City::add_road(int a,int c,int r) {
    int b=find_node(c,r);
    if(b<0) { b=nodes_.size(); nodes_.push_back({c,r,street_point(c,r),{}}); }
    Road road{}; road.a=a; road.b=b; road.avenue=(nodes_[a].row==0 && r==0);
    for(int i=0;i<=8;++i) {
        double t=i/8.;
        road.path[i]=street_point(std::lerp(double(nodes_[a].col),double(c),t),
                                  std::lerp(double(nodes_[a].row),double(r),t));
        if(i) road.lengths[i]=road.lengths[i-1]+distance(road.path[i],road.path[i-1]);
    }
    int e=roads_.size(); roads_.push_back(road);
    nodes_[a].edges.push_back(e); nodes_[b].edges.push_back(e);
    return e;
}
bool City::grow() {
    double best=-1e9; int origin=-1, col=0,row=0;
    for(int i=0;i<int(nodes_.size());++i) {
        const auto& n=nodes_[i];
        for(auto [dc,dr] : std::array<std::pair<int,int>,4>{{{1,0},{-1,0},{0,1},{0,-1}}}) {
            int c=n.col+dc,r=n.row+dr,b=find_node(c,r);
            if(b>=0 && (i>b || std::any_of(n.edges.begin(),n.edges.end(),[&](int e){
                return roads_[e].a==b || roads_[e].b==b;
            }))) continue;
            Point end=street_point(c,r);
            if(std::abs(end.x)>half_width-15 || std::abs(end.z)>half_depth-15) continue;
            double grade=0; Point prev=n.pos; bool viable=true;
            for(int s=1;s<=8 && viable;++s) {
                Point p=street_point(n.col+dc*s/8.,n.row+dr*s/8.);
                double h=ground(p);
                grade=std::max(grade,std::abs(h-ground(prev))/distance(prev,p));
                viable=h>1.6 && grade<.21;
                for(auto& lot:buildings_) if(segment_distance(lot.pos,prev,p)<6.8) {viable=false;break;}
                prev=p;
            }
            if(!viable) continue;
            double score=double(draw()%1000)/140. - .055*distance(end,street_point(0,0))
                         - grade*25 + (b>=0?1.5:0) + (r==0?1.:0);
            if(score>best) {best=score;origin=i;col=c;row=r;}
        }
    }
    if(origin<0) return false;
    add_road(origin,col,row);
    record("Street extension opened");
    return true;
}
bool City::develop(int e,bool initial) {
    const Road& road=roads_[e]; int start=draw()%4;
    for(int j=0;j<4;++j) {
        int slot=(j+start)%4, k=slot<2?2:6;
        Point p=road.path[k],next=road.path[k+1];
        double dx=next.x-p.x,dz=next.z-p.z, length=std::hypot(dx,dz);
        double offset=(slot%2?1:-1)*(road.avenue?8.9:8.1);
        p.x-=dz*offset/length; p.z+=dx*offset/length;
        if(ground(p)<2.5 || std::any_of(buildings_.begin(),buildings_.end(),[&](const auto& lot){return distance(p,lot.pos)<9.2;})) continue;
        bool clear=true;
        for(const auto& other:roads_)
            for(size_t k2=1;k2<other.path.size();++k2)
                if(segment_distance(p,other.path[k2-1],other.path[k2])<6.7) clear=false;
        if(!clear) continue;
        int style=int(draw()>>8)%997;
        Use use=road.avenue && style%3!=0 ? Use::Shops : (style%13==0?Use::Works:Use::Housing);
        int beds=use==Use::Housing?34+style%24:0;
        buildings_.push_back({p,-std::atan2(dz,dx),style,beds,initial?-build_time:tick_,use});
        if(initial) capacity_+=beds;
        else record(use==Use::Housing?"Housing construction began":use==Use::Shops?"Market construction began":"Workshop construction began");
        return true;
    }
    return false;
}
void City::dispatch(Vehicle& v,int start) {
    // Breadth-first routing minimizes intersections traversed in this short-block network.
    int target=(start+1+draw()%(nodes_.size()-1))%nodes_.size();
    std::vector<int> via(nodes_.size(),-1);
    std::queue<int> queue;queue.push(start);via[start]=-2;
    while(via[target]<0) {
        int n=queue.front();queue.pop();
        for(int e:nodes_[n].edges) {
            int next=roads_[e].a==n?roads_[e].b:roads_[e].a;
            if(via[next]!=-1) continue;
            via[next]=e;queue.push(next);
        }
    }
    v.route.clear(); v.destination=target;
    for(int n=target;n!=start;) {
        int e=via[n];v.route.push_back(e);n=roads_[e].a==n?roads_[e].b:roads_[e].a;
    }
    v.edge=v.route.back();v.route.pop_back();v.from=start;v.along=0;
}
Point City::vehicle_position(const Vehicle& v,double& yaw,double fraction) const {
    const auto& road=roads_[v.edge]; bool forward=v.from==road.a;
    double d=std::clamp(v.along+fraction*v.speed,0.,road.lengths.back());
    if(!forward) d=road.lengths.back()-d;
    int i=1;while(i<8 && road.lengths[i]<d) ++i;
    Point a=road.path[i-1],b=road.path[i]; double len=road.lengths[i]-road.lengths[i-1];
    double f=(d-road.lengths[i-1])/len, sign=forward?1:-1;
    double dx=(b.x-a.x)*sign/len,dz=(b.z-a.z)*sign/len;
    yaw=-std::atan2(dz,dx);
    return {std::lerp(a.x,b.x,f)-dz*.82,std::lerp(a.z,b.z,f)+dx*.82};
}
void City::advance(int ticks) {
    for(int i=0;i<ticks;++i) {
        ++tick_;
        // Construction is append-only; only recent starts can complete on this tick.
        for(auto it=buildings_.rbegin();it!=buildings_.rend() && it->started>=tick_-build_time;++it)
            if(it->started==tick_-build_time) capacity_+=it->capacity;
        if(tick_%4==0 && population_<capacity_) population_+=std::min(capacity_-population_,int(2+draw()%5));
        if(tick_%16==0 && population_*100>=capacity_*86 && tick_>=vacant_ticks_) {
            bool built=false;
            if(tick_%64==16 && grow()) built=develop(roads_.size()-1,false);
            if(!built) {
                int start=draw()%roads_.size();
                for(int j=0;j<int(roads_.size()) && !built;++j) built=develop((start+j)%roads_.size(),false);
            }
            if(!built && !grow()) vacant_ticks_=tick_+2048;
        }
        for(auto& v:vehicles_) {
            const auto& road=roads_[v.edge];v.along+=v.speed;
            if(v.along>=road.lengths.back()) {
                double carry=v.along-road.lengths.back();
                int end=road.a==v.from?road.b:road.a;
                if(v.route.empty()) dispatch(v,end);
                else {v.edge=v.route.back();v.route.pop_back();v.from=end;}
                v.along=carry;
            }
        }
    }
}
void City::record(std::string text) { events_.push_back({tick_,std::move(text)}); }
uint64_t City::digest() const {
    uint64_t h=14695981039346656037ULL;
    auto mix=[&](uint64_t value){h^=value;h*=1099511628211ULL;};
    mix(seed_);mix(random_);mix(tick_);mix(capacity_);mix(population_);mix(vacant_ticks_);
    for(const auto& n:nodes_){mix(n.col);mix(n.row);}
    for(const auto& r:roads_){mix(r.a);mix(r.b);}
    for(const auto& b:buildings_){mix(std::bit_cast<uint64_t>(b.pos.x));mix(std::bit_cast<uint64_t>(b.pos.z));mix(b.style);mix(b.started);}
    for(const auto& v:vehicles_){mix(v.edge);mix(v.from);mix(v.destination);mix(std::bit_cast<uint64_t>(v.along));for(auto e:v.route) mix(e);}
    return h;
}
}

