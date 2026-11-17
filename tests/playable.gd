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

func check_pedestrian_click(world) -> void:
	var view: Rect2 = root.get_visible_rect()
	var clear_area := Rect2(view.size * Vector2(.35,.22), view.size * Vector2(.40,.50))
	for i in world.people.ids.size():
		if world.people.modes[i] != 3: continue
		var pose: Vector4 = world.people.poses[i]
		var screen: Vector2 = world.orbit.unproject_position(Vector3(pose.x, pose.y+1.05, pose.z))
		if not clear_area.has_point(screen): continue
		var id: int = world.people.ids[i]
		if world.people.pick(world.orbit, screen, world.town.sites) != id: continue
		var click := InputEventMouseButton.new()
		click.position = screen
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		root.push_input(click, true)
		click.pressed = false
		root.push_input(click, true)
		check(world.watching and world.selected == id, "Click did not follow the visible pedestrian")
		world._street_view()
		return
	check(false, "No visible commuter in the opening market street")

func check_construction(world, initial: Dictionary) -> void:
	var street_id:int=initial.roads
	var lot_id:int=initial.buildings
	check(world.town.roadworks.has(street_id) and world.town.construction.has(lot_id),"First construction site missing")
	if not world.town.roadworks.has(street_id) or not world.town.construction.has(lot_id): return
	var street=world.town.roadworks[street_id]
	var building=world.town.construction[lot_id]
	check(building.frame.visible and building.building.scale==Vector3.ONE,"Building frame or finished proportions incorrect")
	key(KEY_SPACE)
	var pos:Vector3=street.machine.position
	var angle:float=building.jib.rotation.y
	world._process(.5)
	check(street.machine.position==pos and building.jib.rotation.y==angle,"Paused construction kept moving")
	key(KEY_1)
	world._process(.125)
	check(street.progress>0 and building.jib.rotation.y!=angle,"Crane did not interpolate between ticks")
	world.hud.works_button.pressed.emit()
	world._process(.1)
	check(world.watching_construction and world.construction_target.y>=0,"Construction camera failed to find a site")
	world.hud.works_button.pressed.emit()
	check(not world.watching_construction,"Construction camera did not release")
	world._street_view()

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
	check_pedestrian_click(world)
	check(world.state.sales>0 and world.manifests.size()>0,"Market failed to open")
	world.hud.follow_van.pressed.emit()
	world._process(0)
	var shipment_id:int=world.following_van
	check(shipment_id>=0 and world.trade.trucks.has(shipment_id),"Delivery van missing")
	check(world.hud.trading.text.contains("DELIVERY") and world.hud.freight_line.size()>1,"Freight manifest or map route missing")
	var pos:Vector3=world.orbit.pivot
	world._process(1)
	check(pos==world.orbit.pivot,"Paused van moved")
	world.hud.counter.pressed.emit()
	check(world.following_van<0 and world.business_id>=0,"Counter view failed")
	world._street_view()
	for i in range(1,5):
		world.hud.buttons[i].pressed.emit()
		var before:int=world.state.tick
		world._process(.25)
		check(world.state.tick-before==[1,10,100,1000][i-1],"Speed control advanced the wrong number of ticks")
	check(world.town.roads>initial.roads and world.town.buildings>initial.buildings,"Growth did not reach the scene")
	check_construction(world,initial)
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
	check(world.orbit.following,"Fit city did not restore automatic framing")
	check(world.hud.map_paths.size()==world.state.roads,"Street plan missed a road")
	var was_open:bool=world.hud.map_open
	world.hud.map_button.pressed.emit()
	check(was_open!=world.hud.map_open,"Street plan toggle failed")
	var small_extent:float=world.orbit.size
	key(KEY_4)
	world._process(60.)
	world.orbit.home()
	check(not world.town.roadworks.has(initial.roads) and not world.town.construction.has(initial.buildings),"Completed site retained its construction rig")
	check(world.orbit.size>small_extent,"Camera did not expand with the city")
	check(world.town.sites.size()==world.state.buildings,"Redevelopment duplicated a parcel")
	check(world.town.renewals==world.state.renewals,"Redevelopment did not reach the scene")
	check(world.town.cars.size()==world.model.traffic(0).size(),"Traffic population did not reach the scene")
	world.hud.district_requested.emit(2)
	check(world.hud.district_title=="Workshop district" and not world.orbit.following,"Workshop district focus failed")
	world.hud.district_requested.emit(1)
	world._sync()
	world.hud.meet_button.pressed.emit()
	world._sync()
	check(world.selected>=0 and world.watching,"Resident inspection failed")
	var person:Dictionary=world.model.resident(world.selected,0)
	check(person.home>=0 and world.hud.identity.text.contains("#"),"Resident address or identity missing")
	world.hud.reset_button.pressed.emit()
	check(not world.watching and world.orbit.following,"Fit city did not leave resident view")
	print("Playable checks completed with ",failures," failures.")
	quit(1 if failures else 0)
