extends Node3D
const Landscape=preload("res://scripts/landscape.gd")
const Town=preload("res://scripts/town.gd")
const Orbit=preload("res://scripts/orbit.gd")
const People=preload("res://scripts/people.gd")
const Trade=preload("res://scripts/trade.gd")
const Hud=preload("res://scripts/hud.gd")
const TICKS_PER_SECOND=4.
var model:=CityModel.new()
var orbit:=Orbit.new()
var land:=Landscape.new()
var town:=Town.new()
var trade:=Trade.new()
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
var light:=DirectionalLight3D.new()
var atmosphere:=Environment.new()
var remainder:=0.
var state:Dictionary
var capture_path:=""
var capture_tick:=0
var capture_detail:=false
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
		if arg=="--no-hud": hud.visible=false
		if arg=="--freight": capture_freight=true
		if arg.begins_with("--counter="): capture_counter=int(arg.trim_prefix("--counter="))
		if arg=="--street": street_capture=true
		if arg=="--meet": meet_capture=true
		if arg.begins_with("--resident="): capture_resident=int(arg.trim_prefix("--resident="))
		if arg.begins_with("--district="):
			capture_district=clampi(int(arg.trim_prefix("--district=")),0,2)
			street_capture=true
		if arg=="--atlas": atlas=true
		if arg=="--detail": capture_detail=true
		if arg.begins_with("--speed="):
			var requested:=int(arg.trim_prefix("--speed="))
			if requested in [1,10,100,1000]:
				speed=requested
				last_speed=requested
	model.reset(seed_value)
	_lighting()
	add_child(land)
	land.create(model)
	add_child(town)
	town.create(model,land)
	add_child(trade)
	add_child(people)
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
	hud.speed_selected.connect(_select_speed)
	hud.home_requested.connect(_fit_city)
	hud.street_requested.connect(_street_view)
	hud.meet_requested.connect(_meet)
	hud.freight_requested.connect(_follow_delivery)
	hud.counter_requested.connect(_view_business)
	hud.district_requested.connect(_district_view)
	if capture_tick>0: model.step(capture_tick)
	if capture_path!="": speed=0
	state=model.summary()
	orbit.frame_city(state.bounds,1.)
	if street_capture or (not atlas and not capture_detail and capture_path==""): _district_view(capture_district)
	_sync()
	if capture_counter>=0 and not model.business(capture_counter).is_empty():
		business_id=capture_counter
		_view_business()
	if capture_freight: _follow_delivery()
	if meet_capture: _meet()
	if capture_resident>=0 and capture_resident<state.population: _watch(capture_resident)
	_sync()
	if capture_path!="": _capture.call_deferred()

func _lighting() -> void:
	var env:=atmosphere
	env.background_mode=Environment.BG_SKY
	var sky_model:=ProceduralSkyMaterial.new()
	sky_model.sky_top_color=Color("#688aaa")
	sky_model.sky_horizon_color=Color("#c2cbd0")
	sky_model.ground_horizon_color=Color("#b6bfbd")
	sky_model.ground_bottom_color=Color("#697369")
	sky_model.sun_angle_max=9.
	env.sky=Sky.new()
	env.sky.sky_material=sky_model
	env.fog_enabled=true
	env.fog_density=.000105
	env.fog_light_color=Color("#bec9cb")
	env.fog_sky_affect=.32
	env.background_color=Color("#294240")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("#c9d9df")
	env.ambient_light_energy=.34
	env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode=Environment.TONE_MAPPER_ACES
	env.ssao_enabled=true
	env.ssao_radius=1.6
	env.ssao_intensity=1.6
	var environment:=WorldEnvironment.new()
	environment.environment=env
	add_child(environment)
	var sun:=light
	sun.light_color=Color("#fff3e3")
	sun.light_energy=1.15
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=900
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits=true
	sun.shadow_bias=.035
	sun.shadow_normal_bias=.85
	sun.rotation_degrees=Vector3(-37,-133,0)
	sun.light_angular_distance=.35
	add_child(sun)
func _process(delta:float) -> void:
	remainder+=delta*TICKS_PER_SECOND*speed
	var ticks:=int(remainder)
	if ticks>0:
		model.step(ticks)
		remainder-=ticks
		state=model.summary()
	orbit.frame_city(state.bounds,1.-exp(-delta*1.8))
	_sync()

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
			orbit.update_view()
	town.sync(state,remainder)
	people.sync(model,orbit,state,remainder,selected)
	hud.display(state,speed,orbit.azimuth)
	hud.sync_map(model,state.roads,state.buildings)
	hud.show_life(state,info,model)
	if business_id<0 and not manifests.is_empty(): business_id=manifests[0].shop
	trade.sync(model,state,manifests,remainder,following_van,business_id)
	hud.show_trade(model,model.business(business_id),run,manifests.size(),state.tick)
	var sun_height:=sin((state.minute-360.)/1440.*TAU)
	var daylight:=smoothstep(-.08,.38,sun_height)
	light.light_energy=lerpf(.12,1.02,daylight)
	light.rotation_degrees=Vector3(-lerpf(16.,57.,maxf(0.,sun_height)),-118.+(state.minute-465)*.135,0)
	light.directional_shadow_max_distance=clampf(orbit.extent*2.8,95.,1700.)
	atmosphere.fog_light_energy=lerpf(.06,.80,daylight)
	atmosphere.background_energy_multiplier=lerpf(.08,.80,daylight)
	if town.Forms.built_material: town.Forms.built_material.set_shader_parameter("night",1.-daylight)
	light.light_color=Color("#a5c2df").lerp(Color("#fff3e3"),daylight)
	atmosphere.ambient_light_color=Color("#cbd5df")
	atmosphere.ambient_light_energy=lerpf(.20,.58,daylight)

func _follow_delivery() -> void:
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
	following_van=-1
	watching=false
	selected=-1
	orbit.home()

func _street_view() -> void:
	_district_view(1)

func _district_view(use:int) -> void:
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
	orbit.azimuth=-.37
	orbit.elevation=.64
	orbit.update_view()

func _meet() -> void:
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
	following_van=-1
	selected=id
	watching=true
	orbit.following=false
	orbit.extent=28
	var r:Dictionary=model.resident(id,remainder)
	orbit.pivot=r.position+Vector3.UP
	orbit.update_view()

func _unhandled_input(event:InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed: click_start=event.position
		elif click_start.distance_to(event.position)<4. and not event.shift_pressed:
			var id:=people.pick(orbit,event.position,town.sites)
			if id>=0: _watch(id)
			else:
				var at:=_pick_business(event.position)
				if at>=0:
					business_id=at
					_view_business()
	if event is InputEventMouseMotion and event.button_mask and event.position.distance_to(click_start)>4:
		watching=false
		following_van=-1
	if event is InputEventPanGesture:
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
		var hit=site.get_aabb().intersects_ray(inv*start,inv.basis*dir)
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
