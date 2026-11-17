extends Node
const Picker=preload("res://scripts/settlement_picker.gd")
const World=preload("res://main.tscn")
var world
var picker
var layer:=CanvasLayer.new()
var flying:=false

func _ready() -> void:
	layer.layer=8
	add_child(layer)
	# Historical fixture captures and benchmarks keep their explicit entry point.
	for arg in OS.get_cmdline_user_args():
		if arg in ["--fixture","--atlas","--detail","--street","--freight","--meet","--no-hud"] or arg.begins_with("--at=") or arg.begins_with("--capture=") or arg.begins_with("--seed=") or arg.begins_with("--bus=") or arg.begins_with("--site-") or arg.begins_with("--speed=") or arg.begins_with("--district=") or arg.begins_with("--resident=") or arg.begins_with("--counter="):
			_attach(World.instantiate())
			return
	_show_picker()

func _attach(scene) -> void:
	world=scene
	world.map_requested.connect(_show_picker)
	add_child(world)

func _show_picker() -> void:
	if is_instance_valid(picker) or flying: return
	if is_instance_valid(world):
		world.process_mode=Node.PROCESS_MODE_DISABLED
		world.hud.visible=false
	picker=Picker.new()
	picker.returnable=is_instance_valid(world)
	layer.add_child(picker)
	picker.founded.connect(_arrive)
	picker.resume_requested.connect(_resume)

func _resume() -> void:
	if flying or not is_instance_valid(world) or picker.busy: return
	picker.queue_free()
	picker=null
	world.process_mode=Node.PROCESS_MODE_INHERIT
	world.hud.visible=true

func _input(e:InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode==KEY_ESCAPE and is_instance_valid(picker):
		_resume()

func _arrive(model,lat:float,lon:float,name_on_map:String) -> void:
	flying=true
	if is_instance_valid(world):
		remove_child(world)
		world.free()
	var scene=World.instantiate()
	scene.model=model
	scene.hud.place_name=name_on_map if name_on_map!="" else "새 정착지"
	scene.hud.place_subtitle="%.5f°, %.5f°   /   실제 지형"%[lat,lon]
	_attach(scene)
	world.process_mode=Node.PROCESS_MODE_DISABLED
	world.hud.hide()
	world.hide()
	var camera=world.orbit
	var landing:Vector3=camera.pivot
	var height:float=model.height_at(0,0)
	var map=picker.atlas
	var start:Vector2=map.center
	var end:Vector2=map.pin
	var delta:=Vector2(wrapf(end.x-start.x,-.5,.5),end.y-start.y)
	var initial:float=map.zoom
	# Match the final overhead map scale to the north-up camera footprint in metres.
	var final_zoom:=log(40075016.686*cos(deg_to_rad(lat))*map.size.y/(map.size.x*990.))/log(2.)
	var google=picker.google
	if google.view:
		picker.hide()
		map.set_process(false)
		google.tell({"action":"fly"})
	var shot:=create_tween()
	shot.tween_method(func(t:float):
		if google.view: google.advance_flight(t)
		var travel:=smoothstep(0.,.48,t)
		map.center=Vector2(fposmod(start.x+delta.x*travel,1.),start.y+delta.y*travel)
		map.zoom=lerpf(initial,final_zoom,smoothstep(.08,1.,t))
		picker.controls.modulate.a=1.-smoothstep(0.,.19,t)
	,0.,1.,2.85)
	camera.following=false
	camera.azimuth=0.
	camera.elevation=1.569
	camera.extent=990.
	camera.pivot=Vector3(0,height,0)
	camera.update_view()
	shot.tween_method(func(t:float):
		var eased:=smoothstep(0.,1.,t)
		world.show()
		if t>=.46:
			picker.hide()
			map.set_process(false)
		picker.modulate.a=1.-smoothstep(0.,.46,t)
		if google.view: google.view.set_opacity(picker.modulate.a)
		camera.extent=exp(lerpf(log(990.),log(65.),eased))
		map.zoom=final_zoom+log(990./camera.extent)/log(2.)
		camera.elevation=lerpf(1.569,.64,eased)
		camera.azimuth=lerpf(0.,-.37,eased)
		camera.pivot=Vector3(0,height,0).lerp(landing,eased)
		camera.update_view()
	,0.,1.,2.45)
	await shot.finished
	picker.queue_free()
	picker=null
	world.process_mode=Node.PROCESS_MODE_INHERIT
	world.hud.modulate.a=0.
	world.hud.show()
	create_tween().tween_property(world.hud,"modulate:a",1.,.4)
	flying=false
