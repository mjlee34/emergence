extends SceneTree
## Exercise the same presentation, extension, and controls as an interactive launch.
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event)
	event.pressed = false
	root.push_input(event)

func run() -> void:
	var world = load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	world.set_process(false)
	var initial: Dictionary = world.model.summary()
	check(world.town.buildings==initial.buildings,"Initial buildings were not presented")
	key(KEY_SPACE)
	world._process(2.0)
	check(world.state.tick==initial.tick and world.speed==0,"Pause changed simulation time")
	for i in range(1,5):
		world.hud.buttons[i].pressed.emit()
		var before:int=world.state.tick
		world._process(.25)
		check(world.state.tick-before==[1,10,100,1000][i-1],"Speed control advanced the wrong number of ticks")
	check(world.town.roads>initial.roads and world.town.buildings>initial.buildings,"Growth did not reach the scene")
	key(KEY_1)
	var first:Vector3=world.town.cars[0].position
	world._process(.5)
	check(first.distance_to(world.town.cars[0].position)>.1,"Road traffic did not move")
	var wheel:=InputEventMouseButton.new()
	wheel.position=Vector2(480,280)
	wheel.button_index=MOUSE_BUTTON_WHEEL_UP
	wheel.pressed=true
	var before_zoom:float=world.orbit.size
	root.push_input(wheel)
	check(world.orbit.size<before_zoom,"Scroll did not zoom")
	var down:=InputEventMouseButton.new()
	down.position=wheel.position
	down.button_index=MOUSE_BUTTON_LEFT
	down.pressed=true
	root.push_input(down)
	var drag:=InputEventMouseMotion.new()
	drag.button_mask=MOUSE_BUTTON_MASK_LEFT
	drag.position=wheel.position
	drag.relative=Vector2(24,15)
	var before_angle:float=world.orbit.azimuth
	root.push_input(drag)
	check(world.orbit.azimuth!=before_angle,"Drag did not orbit")
	down.shift_pressed=true
	root.push_input(down)
	var before_pan:Vector3=world.orbit.pivot
	root.push_input(drag)
	check(world.orbit.pivot!=before_pan,"Shift-drag did not pan")
	world.hud.reset_button.pressed.emit()
	check(is_equal_approx(world.orbit.size,before_zoom),"Reset did not restore the opening camera")
	print("Playable checks completed with ",failures," failures.")
	quit(1 if failures else 0)
