extends SceneTree
var failures:=0

func _initialize() -> void:
	run.call_deferred()

func check(ok:bool,message:String) -> void:
	if not ok:
		failures+=1
		push_error(message)

func run() -> void:
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	check(world.town.greens.size()==2,"Founding facilities missing")
	world.hud.parks_button.pressed.emit()
	world._process(0.)
	check(world.green_id==0 and world.hud.identity.text.contains("park"),"Parks button did not visit the garden")
	world.hud.parks_button.pressed.emit()
	world._process(0.)
	check(world.green_id==1 and world.hud.identity.text.contains("playground"),"Could not cycle to playground")
	check(world.hud.green_dots.size()==2 and world.state.visitors[1]>0,"Playground visitors or map pins missing")
	world.hud.reset_button.pressed.emit()
	check(world.green_id<0,"Camera did not leave playground")
	var initial:int=world.town.greens.size()
	for step in 20:
		world._process(720.)
		if world.town.greens.size()>initial: break
	check(world.town.greens.size()>initial,"New neighbourhood did not receive a facility")
	if world.town.greens.size()>initial:
		var green=world.town.greens.back()
		var id:int=world.town.greens.size()-1
		check(world.state.tick==green.data.started and not green.fittings.visible and world.state.visitors[id]==0,"New facility opened before landscaping")
		world._process(135.)
		check(green.fittings.visible and green.fittings.scale.y<1. and world.state.visitors[id]==0,"Missing landscaping stage")
		var size_before:float=green.fittings.scale.y
		world._select_speed(0)
		world._process(.8)
		check(green.fittings.scale.y==size_before,"Paused works continued")
		world._select_speed(1)
		world._process(45.)
		check(green.fittings.scale.y==1. and not world.town.landscaping.has(green),"Completed facility still under construction")
	print("Green space checks completed with ",failures," failures.")
	quit(1 if failures else 0)
