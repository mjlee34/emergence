extends Node3D
const Landscape=preload("res://scripts/landscape.gd")
const Town=preload("res://scripts/town.gd")
const Orbit=preload("res://scripts/orbit.gd")
const Hud=preload("res://scripts/hud.gd")
const TICKS_PER_SECOND=4.
var model:=CityModel.new()
var orbit:=Orbit.new()
var land:=Landscape.new()
var town:=Town.new()
var hud:=Hud.new()
var speed:=10
var last_speed:=10
var remainder:=0.
var state:Dictionary
var capture_path:=""
var capture_tick:=0
var capture_detail:=false
var atlas:=false

func _ready() -> void:
	var seed_value:=147
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value=int(arg.trim_prefix("--seed="))
		if arg.begins_with("--capture="): capture_path=arg.trim_prefix("--capture=")
		if arg.begins_with("--at="): capture_tick=maxi(0,int(arg.trim_prefix("--at=")))
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
	hud.home_requested.connect(orbit.home)
	if capture_path!="":
		model.step(capture_tick)
		speed=0
	state=model.summary()
	orbit.frame_city(state.bounds,1.)
	_sync()
	if capture_path!="": _capture.call_deferred()

func _lighting() -> void:
	var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("#294240")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("#c9d9df")
	env.ambient_light_energy=.34
	env.reflected_light_source=Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode=Environment.TONE_MAPPER_ACES
	env.ssao_enabled=true
	env.ssao_radius=2.2
	env.ssao_intensity=1.6
	var environment:=WorldEnvironment.new()
	environment.environment=env
	add_child(environment)
	var sun:=DirectionalLight3D.new()
	sun.light_color=Color("#fff0d5")
	sun.light_energy=1.15
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=900
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.rotation_degrees=Vector3(-37,-133,0)
	add_child(sun)
	var floor_node:=MeshInstance3D.new()
	var floor_mesh:=PlaneMesh.new()
	floor_mesh.size=Vector2(4000,4000)
	floor_node.mesh=floor_mesh
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=Color("#192c2d")
	mat.roughness=1.
	floor_node.material_override=mat
	floor_node.position.y=-10.76
	add_child(floor_node)

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
	town.sync(state,remainder)
	hud.display(state,speed,orbit.azimuth)
	hud.sync_map(model,state.roads)

func _select_speed(value:int) -> void:
	if value==0 and speed==0: value=last_speed
	if value>0: last_speed=value
	speed=value
	hud.display(state,speed,orbit.azimuth)
	hud.sync_map(model,state.roads)

func _input(event:InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
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
