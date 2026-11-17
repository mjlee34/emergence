extends SceneTree
var failures:=0

func _initialize() -> void:
	run.call_deferred()

func check(ok:bool,message:String) -> void:
	if not ok:
		failures+=1
		push_error(message)

func run() -> void:
	var w=load("res://main.tscn").instantiate()
	root.add_child(w)
	w.set_process(false)
	check(w.weather_view.phase_name=="Day" and not w.town.street_lights.visible,"Opening morning failed")
	w.hud.weather_label.pressed.emit()
	check(not w.orbit.following and w.orbit.elevation<.2,"Skyline control did not frame the horizon")
	w._process(752.5)
	check(w.state.tick==3010 and w.weather_view.phase_name=="Night","Clock did not reach night")
	check(w.town.street_lights.visible and w.weather_view.headlamps[0].visible,"Night lighting did not reach the street")
	check(w.weather_view.drops.visible and w.weather_view.drops.multimesh.visible_instance_count>0,"Rain missing from the scene")
	var water=w.land.water_material
	var material=w.weather_view.rain_material
	var phase:float=material.get_shader_parameter("fall_phase")
	var wave:float=water.get_shader_parameter("wave_time")
	var sun:Basis=w.weather_view.sun.basis
	w._select_speed(0)
	w._process(5.)
	check(material.get_shader_parameter("fall_phase")==phase and water.get_shader_parameter("wave_time")==wave and w.weather_view.sun.basis==sun,"Paused atmosphere advanced")
	w._select_speed(1)
	w._process(.125)
	check(material.get_shader_parameter("fall_phase")!=phase and water.get_shader_parameter("wave_time")!=wave,"Rain did not interpolate between ticks")
	w._select_speed(1000)
	w._process(.75)
	check(w.weather==w.model.weather(w.remainder),"Fast-forward atmosphere fell out of sync")
	var fresh=CityModel.new()
	fresh.step(w.state.tick)
	check(w.weather==fresh.weather(w.remainder),"Fast-forward weather could not be reproduced")
	w._process((12360.-w.state.tick)/4000.)
	var count:=0
	for batch in w.people.umbrellas: count+=batch.visible_instance_count
	check(w.weather_view.phase_name=="Day" and w.weather.rain>.35 and count>0,"Daytime rain or pedestrians' umbrellas missing")
	print("Weather checks completed with ",failures," failures.")
	quit(1 if failures else 0)
