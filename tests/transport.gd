extends SceneTree
## Follow a commuter from the platform into the bus and through the workplace door.
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var world = load("res://main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	var driver := -1
	for id in world.transit.cars:
		if world.model.resident(id,0.).activity == 6:
			driver = id
			break
	check(driver >= 0, "Opening traffic has no resident at the wheel")
	if driver >= 0:
		var full:Dictionary=world.model.mobility(0.)
		var remote:Dictionary=world.model.mobility_near(0.,Vector2(1400,950),1.,driver)
		check(remote.drivers.size()==1 and remote.drivers[0]==driver,"Camera culling lost the tracked driver")
		check(remote.waiting==full.waiting and remote.buses==full.buses,"Camera culling changed transit passenger totals")
		var index:int=full.drivers.find(driver)
		check(remote.stance.size()==1 and remote.stance[0].is_equal_approx(full.stance[index]),"Visible wheel travel depends on the camera")
		var later:Dictionary=world.model.mobility_near(.25,Vector2(1400,950),1.,driver)
		check(later.stance.size()==1 and later.stance[0].z>remote.stance[0].z,"Driving wheels did not advance with the trip")
		var car:MeshInstance3D=world.transit.cars[driver]
		check(car.mesh.get_surface_count()==1 and car.basis.is_conformal(),"Passenger car mesh or road alignment is invalid")
		world._watch(driver)
		world._process(0.)
		var r: Dictionary = world.model.resident(driver,0.)
		check(world.hud.routine_label.text.contains("Driving to"), "Driver has no displayed destination")
		check(r.position.distance_to(world.transit.cars[driver].position) < 1., "Driver and car disagree")
	world.hud.bus_button.pressed.emit()
	world._process(0.)
	check(world.following_bus >= 0 and world.hud.bus_line.size() > 2, "Follow bus did not show the line")
	var id := -1
	for waiter in world.state.population:
		var candidate: Dictionary = world.model.resident(waiter,0.)
		if candidate.activity == 4 and candidate.work >= 0:
			id = waiter
			break
	check(id >= 0, "No commuter waiting at the opening stop")
	if id >= 0:
		world._watch(id)
		world._process(0.)
		var r: Dictionary = world.model.resident(id,0.)
		var bus: int = r.bus
		check(world.hud.routine_label.text.contains("Waiting at") and world.people.ids.has(id), "Waiting passenger missing")
		world._select_speed(0)
		var before: Transform3D = world.transit.buses[bus].transform
		world._process(5.)
		check(world.transit.buses[bus].transform == before and world.model.resident(id,0.).activity == 4, "Pause advanced bus or queue")
		world._select_speed(1)
		var rode := false
		var got_off := false
		var arrived := false
		for step in 240:
			world._process(.25)
			r = world.model.resident(id,0.)
			if r.activity == 5 and not rode:
				rode = true
				check(not world.people.ids.has(id), "Passenger still standing on the pavement")
				check(r.position.distance_to(world.transit.buses[bus].position) < 1., "Passenger missed their bus")
				world._watch_bus(bus)
				world._process(0.)
				check(world.transit.service.buses[bus].load >= 1 and not world.hud.meet_button.disabled, "Bus has no passenger to meet")
				world.hud.meet_button.pressed.emit()
				check(world.model.resident(world.selected,0.).bus == bus, "Meet a rider lost the tracked bus")
				world._watch(id)
			elif rode and r.activity == 3:
				got_off = r.last_mile and world.people.ids.has(id)
			elif got_off and r.activity == 1:
				arrived = r.target == r.work
				break
		check(rode and got_off and arrived, "Commuter did not finish their multimodal trip")
	print("Transport checks completed with ",failures," failures.")
	quit(1 if failures else 0)
