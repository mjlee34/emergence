extends Node3D
signal map_requested
const BuildingWorks=preload("res://scripts/building_works.gd")
const Landscape=preload("res://scripts/landscape.gd")
const Town=preload("res://scripts/town.gd")
const Orbit=preload("res://scripts/orbit.gd")
const People=preload("res://scripts/people.gd")
const Trade=preload("res://scripts/trade.gd")
const Hud=preload("res://scripts/hud.gd")
const TICKS_PER_SECOND=4.
var model:CityModel
var orbit:=Orbit.new()
var land:=Landscape.new()
var town:=Town.new()
var trade:=Trade.new()
var transit:=preload("res://scripts/transit.gd").new()
var green_id:=-1
var capture_green:=-1
var following_bus:=-1
var observer_angle:=0.
var angle_origin:=Vector3.INF
var last_bus_stop:=-1
var capture_bus:=-1
var business_id:=-1
var following_van:=-1
var manifests:Array=[]
var capture_freight:=false
var capture_counter:=-1
var hud:=Hud.new()
var speed:=1
var last_speed:=1
var people:=People.new()
var selected:=-1
var watching:=false
var click_start:=Vector2.ZERO
var weather_view:=preload("res://scripts/weather_view.gd").new()
var weather:Dictionary={}
var remainder:=0.
var state:Dictionary
var capture_path:=""
var watching_construction:=false
var construction_target:=Vector2i(-1,-1) # x=0 for streets, x=1 for lots
var fixed_site:=Vector2i(-1,-1)
var capture_tick:=0
var capture_detail:=false
var capture_skyline:=false
var watching_skyline:=false
var skyline_revision:=Vector3i(-1,-1,-1)
var skyline_target:=Vector3.ZERO
var skyline_size:=0.
var skyline_monument_opens:=-1
var atlas:=false
var street_capture:=false
var meet_capture:=false
var capture_resident:=-1
var capture_district:=1

func _ready() -> void:
	var seed_value:=147
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value=int(arg.trim_prefix("--seed="))
		if arg.begins_with("--capture="): capture_path=arg.trim_prefix("--capture=")
		if arg.begins_with("--at="): capture_tick=maxi(0,int(arg.trim_prefix("--at=")))
		if arg.begins_with("--site-road="): fixed_site=Vector2i(0,int(arg.trim_prefix("--site-road=")))
		if arg.begins_with("--site-lot="): fixed_site=Vector2i(1,int(arg.trim_prefix("--site-lot=")))
		if arg=="--no-hud": hud.visible=false
		if arg.begins_with("--bus="): capture_bus=clampi(int(arg.trim_prefix("--bus=")),0,3)
		if arg.begins_with("--park="): capture_green=int(arg.trim_prefix("--park="))
		if arg=="--freight": capture_freight=true
		if arg.begins_with("--counter="): capture_counter=int(arg.trim_prefix("--counter="))
		if arg=="--street": street_capture=true
		if arg=="--meet": meet_capture=true
		if arg.begins_with("--resident="): capture_resident=int(arg.trim_prefix("--resident="))
		if arg.begins_with("--district="):
			capture_district=clampi(int(arg.trim_prefix("--district=")),0,2)
			street_capture=true
		if arg=="--skyline": capture_skyline=true
		if arg=="--atlas": atlas=true
		if arg=="--detail": capture_detail=true
		if arg.begins_with("--speed="):
			var requested:=int(arg.trim_prefix("--speed="))
			if requested in [1,10,100,1000]:
				speed=requested
				last_speed=requested
	if not model:
		model=CityModel.new()
		if seed_value!=147: model.reset(seed_value)
	add_child(weather_view)
	add_child(land)
	land.create(model)
	add_child(town)
	town.create(model,land)
	add_child(trade)
	add_child(transit)
	transit.create(model)
	add_child(people)
	orbit.region_half_size=model.region_half_size()
	add_child(orbit)
	if atlas:
		orbit.following=false
		orbit.azimuth=-.30
		orbit.elevation=.74
		orbit.extent=560
		orbit.pivot=Vector3(0,7,0)
		orbit.update_view()
	if capture_detail:
		orbit.following=false
		orbit.extent=100
		orbit.pivot=Vector3(-25,4,8)
		orbit.update_view()
	var canvas:=CanvasLayer.new()
	add_child(canvas)
	canvas.add_child(hud)
	hud.map_world_requested.connect(func(): map_requested.emit())
	hud.speed_selected.connect(_select_speed)
	hud.home_requested.connect(_fit_city)
	hud.street_requested.connect(_street_view)
	hud.skyline_requested.connect(_skyline)
	hud.place_requested.connect(_visit_green)
	hud.bus_requested.connect(_watch_bus)
	hud.meet_requested.connect(_meet)
	hud.construction_requested.connect(_toggle_construction)
	hud.freight_requested.connect(_follow_delivery)
	hud.counter_requested.connect(_view_business)
	hud.district_requested.connect(_district_view)
	if capture_tick>0: model.step(capture_tick)
	if capture_path!="": speed=0
	state=model.summary()
	orbit.frame_city(state.bounds,1.)
	_sync()
	if street_capture or (not atlas and not capture_detail and capture_path==""): _district_view(capture_district)
	if capture_counter>=0 and not model.business(capture_counter).is_empty():
		business_id=capture_counter
		_view_business()
	if capture_skyline: _skyline()
	if capture_green>=0 and capture_green<state.facilities: _visit_green(capture_green)
	if capture_bus>=0: _watch_bus(capture_bus)
	if capture_freight: _follow_delivery()
	if meet_capture: _meet()
	if capture_resident>=0 and capture_resident<state.population: _watch(capture_resident)
	_sync()
	if fixed_site.y>=0 and ((fixed_site.x==0 and fixed_site.y<state.roads) or (fixed_site.x==1 and fixed_site.y<state.buildings)):
		_frame_work(fixed_site,1.)
	if capture_path!="": _capture.call_deferred()

func _process(delta:float) -> void:
	remainder+=delta*TICKS_PER_SECOND*speed
	var ticks:=int(remainder)
	if ticks>0:
		model.step(ticks)
		remainder-=ticks
		state=model.summary()
	orbit.frame_city(state.bounds,1.-exp(-delta*1.8))
	_sync()
	if following_bus>=0 or watching:
		orbit.azimuth=lerp_angle(orbit.azimuth,observer_angle,1.-exp(-delta*3.))
		orbit.update_view()
	if watching_construction: _follow_works(1.-exp(-delta*3.))
	if watching_skyline:
		if skyline_revision!=_skyline_revision():
			var current:=orbit.pivot
			var size_before:=orbit.extent
			_compose_skyline(false)
			orbit.pivot=current
			orbit.extent=size_before
		var blend:=1.-exp(-delta*1.65)
		orbit.pivot=orbit.pivot.lerp(skyline_target,blend)
		orbit.extent=lerpf(orbit.extent,skyline_size,blend)
		orbit.update_view()

func _sync() -> void:
	var info:Dictionary={}
	manifests=model.freight(remainder)
	var run:Dictionary={}
	if following_van>=0:
		for order in manifests:
			if order.id==following_van: run=order; break
		if run.is_empty(): _view_business()
		else:
			var progress:=smoothstep(run.start+20.,run.arrival,state.tick+remainder)
			orbit.azimuth=lerp_angle(_front_angle(run.source),_front_angle(run.shop),progress)
			orbit.elevation=.65
			orbit.pivot=run.position+Vector3.UP*1.0
			orbit.update_view()
	if selected>=0:
		info=model.resident(selected,remainder)
		if watching:
			orbit.pivot=info.position+Vector3.UP*1.0
			if info.activity>=3 and angle_origin.distance_squared_to(orbit.pivot)>12.:
				angle_origin=orbit.pivot
				observer_angle=_clear_angle(orbit.pivot,observer_angle,Vector3.ZERO)
			orbit.update_view()
	weather=model.weather(remainder)
	weather_view.sync(weather,state.tick+remainder,orbit)
	land.detail_near(orbit.pivot,orbit.extent)
	town.sync(state,remainder,weather_view.lamps)
	town.update_detail(orbit.global_position)
	var calls:Dictionary={}
	for call in model.responders(remainder): calls[call.station]=call
	for id in town.greens.size():
		var site=town.greens[id]
		if site.data.kind>=6: skyline_monument_opens=site.data.opens
		if site.data.kind>=6 and site.fittings.visible:
			if site.data.model=="clock": site.set_clock(state.minute)
			orbit.landmark_peak=site.position+Vector3.UP*site.visible_monument_height
		if site.data.kind in [3,4,5] and (site.on_call or calls.has(id)):
			site.move_responder(calls.get(id,{}),state.tick+remainder)
	transit.sync(model,town,remainder,orbit,selected)
	if following_bus>=0:
		var at:int=transit.service.buses[following_bus].stop
		var bus:Node3D=transit.buses[following_bus]
		if at!=last_bus_stop or angle_origin.distance_squared_to(bus.position)>16.:
			last_bus_stop=at
			angle_origin=bus.position
			observer_angle=_clear_angle(bus.position+Vector3.UP*1.45,observer_angle,bus.global_basis.x*2.4)
		orbit.pivot=transit.buses[following_bus].position+Vector3.UP*1.45
		orbit.update_view()
	people.sync(model,orbit,state,remainder,selected,weather.rain)
	hud.show_weather(weather_view.phase_name,weather_view.condition)
	hud.display(state,speed,orbit.azimuth)
	hud.sync_map(model,state.roads,state.buildings)
	if green_id>=0:
		var green:Dictionary=town.greens[green_id].data
		var visitors:int=state.visitors[green_id]
		hud.district_title=green.name
		hud.construction_note=("%d visiting now  ·  Open to the neighbourhood"%visitors) if state.tick>=green.opens else "Construction in progress"
		if green.kind in [2,3,4,5] and state.tick>=green.opens:
			var reach:int=model.facility(green_id).catchment
			hud.construction_note=("%d pupils within reach  ·  %d in class"%[reach,visitors]) if green.kind==2 else ("%d residents within reach"%reach if green.kind==3 else "%d residents and jobs within reach"%reach)
			if green.kind!=2:
				var phase:="Available"
				if calls.has(green_id): phase="On scene" if calls[green_id].on_scene else "Unit on the road"
				hud.construction_note+="\n%s  ·  %d calls completed"%[phase,model.facility(green_id).responses]
	hud.show_life(state,info,model,following_bus>=0)
	hud.show_transit(transit.network,transit.service,following_bus,info)
	if business_id<0 and not manifests.is_empty(): business_id=manifests[0].shop
	trade.sync(model,state,manifests,remainder,following_van,business_id)
	weather_view.light_traffic(orbit,transit,trade)
	hud.show_trade(model,model.business(business_id),run,manifests.size(),state.tick)
	var elapsed_minutes:float=(state.tick+remainder)/4.
	var surfaces:ShaderMaterial=town.Forms.built_material
	if surfaces:
		surfaces.set_shader_parameter("night",weather_view.lamps)
		surfaces.set_shader_parameter("wetness",weather.wetness)
		surfaces.set_shader_parameter("rain",weather.rain)
		surfaces.set_shader_parameter("clouds",weather.clouds)
		surfaces.set_shader_parameter("cloud_scroll",weather_view.CLOUD_DRIFT*elapsed_minutes)
		surfaces.set_shader_parameter("wave_time",fposmod(elapsed_minutes,1000.))
	land.water_material.set_shader_parameter("wave_time",fposmod(elapsed_minutes,TAU*100.))
	land.water_material.set_shader_parameter("rain",weather.rain)
	land.water_material.set_shader_parameter("wind",weather.wind)

func _toggle_construction() -> void:
	watching_skyline=false
	_leave_green()
	following_bus=-1
	watching_construction=not watching_construction
	construction_target=Vector2i(-1,-1)
	hud.works_button.text="Leave site" if watching_construction else "Construction"
	if watching_construction:
		following_van=-1
		selected=-1
		watching=false
		orbit.following=false
		_follow_works(0.)
	else:
		hud.district_title=""
		hud.construction_note=""

func _leave_green() -> void:
	if green_id>=0:
		green_id=-1
		hud.district_title=""
		hud.construction_note=""

func _leave_site() -> void:
	if watching_skyline: hud.district_title=""
	watching_skyline=false
	_leave_green()
	following_bus=-1
	if watching_construction: _toggle_construction()

func _follow_works(weight:float) -> void:
	var active:Dictionary=town.roadworks if construction_target.x==0 else town.construction
	if not active.has(construction_target.y):
		var best:=INF
		construction_target=Vector2i(-1,-1)
		for kind in 2:
			var projects:Dictionary=town.roadworks if kind==0 else town.construction
			for id in projects:
				var pos:Vector3=projects[id].data.path[4] if kind==0 else projects[id].position
				var d:=pos.distance_squared_to(orbit.pivot)
				if d<best:
					best=d
					construction_target=Vector2i(kind,id)
	if construction_target.y<0:
		hud.district_title="Waiting for construction"
		hud.construction_note="Watching for the next project.\nUse 10× or 100× to advance time."
		return
	_frame_work(construction_target,weight)
	var id:=construction_target.y
	var stage:String
	var ends:int
	if construction_target.x==0:
		var site=town.roadworks[id]
		ends=site.data.opens
		stage="Setting out" if site.progress<.12 else ("Extending bridge deck" if site.data.bridge else "Laying pavement")
		if site.progress>.84: stage="Finishing approaches"
	else:
		var site=town.construction[id]
		ends=site.started+state.construction_ticks
		stage="Preparing foundations"
		if is_instance_valid(site.old) and site.progress<.23: stage="Dismantling old building"
		elif site.progress>.88: stage="Finishing the site"
		elif site.progress>.57: stage="Closing the facade"
		elif site.progress>.23: stage="Raising the frame"
	var remaining:=ceili((ends-state.tick-remainder)/4.)
	hud.construction_note="%s\n%d city minutes to completion" % [stage,remaining]

func _frame_work(target:Vector2i,weight:float) -> void:
	var pos:Vector3
	var angle:float
	var span:float
	if target.x==0:
		var road:Dictionary=model.street(target.y)
		var path:PackedVector3Array=road.path
		pos=path[4]+Vector3.UP*1.6
		var axis:=path[-1]-path[0]
		angle=atan2(axis.x,axis.z)+1.24
		span=clampf(axis.length()*.72,30.,90.)
		hud.district_title="Bridge works" if road.bridge else "Road works"
	else:
		var lot:Dictionary=model.lot(target.y)
		var height:float=town.sites[target.y].get_aabb().end.y
		pos=lot.pos+Vector3.UP*(height*.40+1.)
		angle=_front_angle(target.y)
		span=clampf(height*1.40+14.,25.,92.)
		hud.district_title="Redevelopment" if lot.previous_floors else "Building site"
	orbit.following=false
	orbit.pivot=orbit.pivot.lerp(pos,weight)
	orbit.azimuth=lerp_angle(orbit.azimuth,angle,weight)
	orbit.elevation=lerpf(orbit.elevation,.61,weight)
	orbit.extent=lerpf(orbit.extent,span,weight)
	orbit.update_view()

func _follow_delivery() -> void:
	_leave_site()
	if manifests.is_empty(): return
	var chosen:Dictionary=manifests[0]
	for order in manifests:
		if order.shop==business_id and following_van!=order.id:
			chosen=order
			break
	if following_van>=0:
		for i in manifests.size():
			if manifests[i].id==following_van:
				chosen=manifests[(i+1)%manifests.size()]
				break
	business_id=chosen.shop
	following_van=chosen.id
	selected=-1
	watching=false
	orbit.following=false
	orbit.extent=23.
	orbit.pivot=chosen.position+Vector3.UP*1.0
	orbit.update_view()

func _front_angle(id:int) -> float:
	var b:Dictionary=model.lot(id)
	return b.yaw+(.0 if b.front_sign>0 else PI)+.55

func _view_business() -> void:
	_leave_site()
	following_van=-1
	if business_id<0: return
	var b:Dictionary=model.lot(business_id)
	var front:Vector3=Basis(Vector3.UP,b.yaw)*Vector3(0,0,b.front_sign)
	selected=-1
	watching=false
	orbit.following=false
	orbit.azimuth=atan2(front.x,front.z)+.48
	orbit.elevation=.53
	orbit.extent=26.
	orbit.pivot=b.pos+front*3.7+Vector3.UP*1.45
	orbit.update_view()
	hud.district_title="Market district" if b.use==1 else "Workshop district"

func _fit_city() -> void:
	_leave_site()
	hud.district_title="City overview"
	following_van=-1
	watching=false
	selected=-1
	orbit.home()

func _visit_green(id:=-1) -> void:
	if town.greens.is_empty(): return
	if id<0: id=(green_id+1)%town.greens.size()
	_leave_site()
	following_van=-1
	watching=false
	selected=-1
	green_id=id
	var green:Dictionary=town.greens[id].data
	orbit.following=false
	orbit.extent=green.radius*2.9
	orbit.elevation=.16 if green.kind>=6 else .60
	if green.kind>=6:
		var height:float=town.greens[id].monument_height
		orbit.extent=maxf(orbit.extent,height*1.34)
		orbit.pivot=green.pos+Vector3.UP*height*.48
	else:
		orbit.pivot=green.pos+Vector3.UP*([.85,.85,2.8,4.3,2.9,3.][green.kind] as float)
	var bearing:float=green.yaw+PI+.38
	if green.kind>=6:
		var center:=Vector2((state.bounds.x+state.bounds.z)*.5,(state.bounds.y+state.bounds.w)*.5)
		var outward:=Vector2(green.pos.x,green.pos.z)-center
		bearing=atan2(outward.x,outward.y)
		if green.model in ["liberty","arch"]:
			bearing=green.yaw+town.greens[id].monument.rotation.y+PI+.24
	orbit.azimuth=_clear_angle(orbit.pivot,bearing,Vector3.RIGHT*3.)
	orbit.update_view()

func _pick_green(screen:Vector2) -> int:
	var origin:=orbit.project_ray_origin(screen)
	var ray:=orbit.project_ray_normal(screen)
	for id in town.greens.size():
		var green:Dictionary=town.greens[id].data
		var hit=Plane(Vector3.UP,green.pos.y+.32).intersects_ray(origin,ray)
		if hit!=null and hit.distance_to(green.pos)<green.radius and people._in_sight(orbit,hit+Vector3.UP*.35,town.sites): return id
	return -1

func _skyline() -> void:
	_leave_site()
	following_van=-1
	watching=false
	selected=-1
	hud.district_title="City skyline"
	watching_skyline=true
	_compose_skyline(true)

func _skyline_revision() -> Vector3i:
	# A completed monument can change the composition between two lot starts.
	return Vector3i(state.buildings,state.renewals,int(skyline_monument_opens>=0 and state.tick>=skyline_monument_opens))

func _compose_skyline(enter:bool) -> void:
	var bounds:Vector4=state.bounds
	var x:=lerpf(bounds.x,bounds.z,.50)
	var z:=lerpf(bounds.y,bounds.w,.46)
	orbit.following=false
	orbit.pivot=Vector3(x,model.height_at(x,z)+6.,z)
	if enter: orbit.elevation=.075
	orbit.extent=clampf((bounds.z-bounds.x)*.52,96.,225.)
	var solar:Vector3=weather.sun
	if enter: orbit.azimuth=atan2(solar.x,solar.z)+.86
	var districts:Dictionary={}
	for lot:Dictionary in town.lots:
		if lot.floors<4: continue
		var key:=Vector2i(floori(lot.pos.x/96.),floori(lot.pos.z/96.))
		var mass:Vector4=districts.get(key,Vector4.ZERO)
		var weight:float=lot.floors
		districts[key]=mass+Vector4(lot.pos.x,lot.pos.y+lot.floors*1.35,lot.pos.z,1.)*weight
	var densest:=0.
	var founding:Vector3=town.lots[0].pos if not town.lots.is_empty() else Vector3.ZERO
	for cell:Vector2i in districts:
		var mass:Vector4=districts[cell]
		var focus:=Vector3(mass.x,mass.y,mass.z)/mass.w
		var weight:=mass.w
		for neighbour:Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var surround:Vector4=districts.get(cell+neighbour,Vector4.ZERO)
			weight+=surround.w*.35
		weight/=1.+focus.distance_to(founding)/260.
		if weight>densest:
			densest=weight
			orbit.pivot=focus
	var town_scale:=smoothstep(2500.,10500.,state.population)
	if densest>0.:
		orbit.extent=clampf(orbit.extent,lerpf(68.,100.,town_scale),lerpf(76.,164.,town_scale))
	# Keep the first commercial corner in the composition while the town is small.
	if state.population<12000:
		for lot in town.lots:
			if lot.main_street_corner:
				var influence:=1.-smoothstep(6000.,12000.,state.population)
				orbit.pivot=orbit.pivot.lerp(lot.pos+Vector3.UP*lot.floors*1.65,.72*influence)
				break
	var framed_monument:=false
	for site in town.greens:
		if site.data.kind<6 or state.tick<site.data.opens: continue
		framed_monument=true
		# Frame the monument with the urban area on either side of it.
		var middle:=Vector3(x,0.,z)
		var base:Vector3=site.position
		var blend:Vector3=middle.lerp(base,.45)
		var height:float=site.monument_height
		orbit.pivot=Vector3(blend.x,base.y+height*.41,blend.z)
		orbit.extent=maxf(height*1.34,orbit.skyline_extent(orbit.pivot,base+Vector3.UP*height,bounds))
		break
	if enter: orbit.azimuth=_skyline_azimuth(orbit.azimuth)
	if not framed_monument and densest>0.:
		# Reserve headroom for every occupied tower in the central neighbourhood.
		var sight:=Vector3(sin(orbit.azimuth)*cos(orbit.elevation),sin(orbit.elevation),cos(orbit.azimuth)*cos(orbit.elevation))
		var up:=sight.cross(Vector3(cos(orbit.azimuth),0,-sin(orbit.azimuth)))
		var half_lens:=tan(deg_to_rad(orbit.fov)*.5)
		for site in town.sites:
			var offset:Vector3=site.position-orbit.pivot
			if Vector2(offset.x,offset.z).length()>125.: continue
			var top:=offset+Vector3.UP*site.get_aabb().end.y
			orbit.extent=maxf(orbit.extent,2.*(top.dot(up)*1.15+half_lens*top.dot(sight)))
	orbit.update_view()
	var lift:float=model.height_at(orbit.position.x,orbit.position.z)+4.-orbit.position.y
	if lift>0.:
		orbit.pivot.y+=lift
		orbit.update_view()

	skyline_revision=_skyline_revision()
	skyline_target=orbit.pivot
	skyline_size=orbit.extent

# A tower across the river makes a skyline. A tower against the lens hides it.
# Test only the foreground of each possible view when the observer presses W.
func _skyline_azimuth(preferred:float) -> float:
	var reach:float=orbit.extent*.5/tan(deg_to_rad(orbit.fov)*.5)
	var best:=INF
	var chosen:=preferred
	for offset:float in [0.,.44,-.44,.92,-.92,1.5,-1.5,2.2,-2.2,PI]:
		var bearing:=preferred+offset
		var direction:=Vector2(sin(bearing),cos(bearing))
		var eye:=Vector2(orbit.pivot.x,orbit.pivot.z)+direction*reach*cos(orbit.elevation)
		var score:=absf(offset)*.35
		var eye_y:float=orbit.pivot.y+reach*sin(orbit.elevation)
		for site in town.sites:
			var delta:=eye-Vector2(site.position.x,site.position.z)
			var depth:=delta.dot(direction)
			if depth< -6. or depth>reach*.55: continue
			if absf(delta.cross(direction))>7.+maxf(0.,depth)*.42: continue
			var obstruction:=site.position.y+site.get_aabb().end.y-(eye_y-depth*tan(orbit.elevation))
			score+=clampf((obstruction+10.)/16.,0.,2.)*(1.-maxf(0.,depth)/reach)
		if score<best:
			best=score
			chosen=bearing
	return chosen

func _street_view() -> void:
	_district_view(1)

func _district_view(use:int) -> void:
	_leave_site()
	following_van=-1
	hud.district_title=["Residential streets","Market district","Workshop district"][use]
	watching=false
	selected=-1
	var nearest:=INF
	for i in state.buildings:
		var lot:Dictionary=model.lot(i)
		if lot.use!=use or state.tick-lot.started<state.construction_ticks: continue
		var path:PackedVector3Array=model.street(lot.frontage).path
		var stop:Vector3=lot.pos.lerp(path[4],.58)
		var d:=stop.distance_squared_to(Vector3(-30,4,6))
		if d<nearest:
			nearest=d
			if use!=0: business_id=i
			orbit.pivot=stop+Vector3.UP*1.4
	orbit.following=false
	orbit.extent=36
	orbit.elevation=.54
	orbit.azimuth=_clear_angle(orbit.pivot,-.37,Vector3.RIGHT*2.) if not town.sites.is_empty() else -.37
	orbit.update_view()

func _clear_angle(pivot:Vector3,preferred:float,half_length:Vector3) -> float:
	var distance:float=orbit.extent*.5/tan(deg_to_rad(orbit.fov)*.5)
	var best:=INF
	var chosen:=preferred
	for offset in [0.,.55,-.55,1.35,-1.35,2.25,-2.25,PI]:
		var angle:float=preferred+offset
		var dir:=Vector3(sin(angle)*cos(orbit.elevation),sin(orbit.elevation),cos(angle)*cos(orbit.elevation))
		var score:float=absf(offset)*.012
		for site in town.sites:
			if site.position.distance_squared_to(pivot)>pow(distance+14.,2): continue
			var inv:=site.global_transform.affine_inverse()
			for along in [-1.,0.,1.]:
				var from:Vector3=pivot+half_length*along
				var hit=BuildingWorks.visible_bounds(site).intersects_ray(inv*from,inv.basis*dir)
				if hit!=null and (site.global_transform*hit).distance_to(from)<distance: score+=1.
		if score<best:
			best=score
			chosen=angle
		if score==0.: break
	return chosen

func _watch_bus(id:=-1) -> void:
	if transit.service.buses.is_empty(): return
	if id<0:
		id=(following_bus+1)%transit.service.buses.size()
		if following_bus<0:
			var best:=-1
			for i in transit.service.buses.size():
				var bus:Dictionary=transit.service.buses[i]
				var score:int=bus.load+transit.service.waiting[bus.next]*4
				if score>best: id=i; best=score
	_leave_site()
	following_van=-1
	selected=-1
	watching=false
	following_bus=id
	orbit.following=false
	orbit.extent=24.
	orbit.elevation=.67
	last_bus_stop=transit.service.buses[id].stop
	var bus:Node3D=transit.buses[id]
	angle_origin=bus.position
	observer_angle=_clear_angle(bus.position+Vector3.UP*1.45,bus.rotation.y+.84,bus.global_basis.x*2.4)
	orbit.azimuth=observer_angle
	orbit.pivot=transit.buses[id].position+Vector3.UP*1.45
	orbit.update_view()

func _meet() -> void:
	if following_bus>=0:
		var bus:Dictionary=transit.service.buses[following_bus]
		var rider:int=bus.rider
		if rider<0: rider=transit.service.first_waiter[bus.stop if bus.dwell else bus.next]
		if rider>=0: _watch(rider)
		return
	if people.ids.is_empty():
		selected=0 if selected<0 else (selected+1)%state.population
	else:
		var nearest:=INF
		var next_id:=-1
		for i in people.ids.size():
			if people.ids[i]==selected: continue
			var p:=people.poses[i]
			var dist:=Vector2(p.x-orbit.pivot.x,p.z-orbit.pivot.z).length_squared()
			if people.modes[i]!=3: dist+=900
			if dist<nearest:
				nearest=dist
				next_id=people.ids[i]
		if next_id>=0: selected=next_id
	if selected>=0: _watch(selected)

func _watch(id:int) -> void:
	_leave_site()
	following_van=-1
	selected=id
	watching=true
	orbit.following=false
	orbit.extent=28
	var r:Dictionary=model.resident(id,remainder)
	orbit.pivot=r.position+Vector3.UP
	angle_origin=orbit.pivot
	observer_angle=_clear_angle(orbit.pivot,orbit.azimuth,Vector3.ZERO) if r.activity>=3 else orbit.azimuth
	orbit.azimuth=observer_angle
	orbit.update_view()

func _unhandled_input(event:InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed: click_start=event.position
		elif click_start.distance_to(event.position)<4. and not event.shift_pressed:
			var vehicle:=transit.pick(orbit,event.position,people,town.sites)
			var id:=people.pick(orbit,event.position,town.sites)
			if id>=0: _watch(id)
			elif vehicle.x==0: _watch(vehicle.y)
			elif vehicle.x==1: _watch_bus(vehicle.y)
			else:
				var park:=_pick_green(event.position)
				if park>=0:
					_visit_green(park)
					return
				var at:=_pick_business(event.position)
				if at>=0:
					business_id=at
					_view_business()
	if event is InputEventMouseMotion and event.button_mask and event.position.distance_to(click_start)>4:
		_leave_site()
		watching=false
		following_van=-1
	if event is InputEventPanGesture or event is InputEventMagnifyGesture or (event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]):
		_leave_site()
		watching=false
		following_van=-1

func _pick_business(screen:Vector2) -> int:
	var start:=orbit.project_ray_origin(screen)
	var dir:=orbit.project_ray_normal(screen)
	var best:=INF
	var chosen:=-1
	for i in town.sites.size():
		var site:MeshInstance3D=town.sites[i]
		var inv:=site.global_transform.affine_inverse()
		var hit=BuildingWorks.visible_bounds(site).intersects_ray(inv*start,inv.basis*dir)
		if hit==null: continue
		var dist:=start.distance_squared_to(site.global_transform*hit)
		if dist<best:
			best=dist
			chosen=i
	return chosen if not model.business(chosen).is_empty() else -1


func _select_speed(value:int) -> void:
	if value==0 and speed==0: value=last_speed
	if value>0: last_speed=value
	speed=value
	hud.display(state,speed,orbit.azimuth)
	hud.sync_map(model,state.roads,state.buildings)

func _input(event:InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_M: map_requested.emit()
			KEY_W: _skyline()
			KEY_B: _watch_bus()
			KEY_P: _visit_green()
			KEY_G: _toggle_construction()
			KEY_H: _fit_city()
			KEY_V: _street_view()
			KEY_SPACE: _select_speed(0)
			KEY_1: _select_speed(1)
			KEY_2: _select_speed(10)
			KEY_3: _select_speed(100)
			KEY_4: _select_speed(1000)
			_: return
		get_viewport().set_input_as_handled()

func _capture() -> void:
	for i in range(8): await RenderingServer.frame_post_draw
	var capture:=get_viewport().get_texture().get_image()
	var result:=capture.save_png(capture_path)
	print("Captured ",capture.get_size()," at tick ",state.tick," to ",capture_path," (",result,")")
	get_tree().quit(0 if result==OK else 1)
