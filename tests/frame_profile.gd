extends SceneTree
## Measure the normal game loop with a reproducible city, camera and speed.

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	var tick:=int(args[0]) if args.size()>0 else 1181800
	var view:=args[1] if args.size()>1 else "overview"
	var speed:=int(args[2]) if args.size()>2 else 1
	if tick<0 or not view in ["overview","street"] or not speed in [1,10,100,1000]:
		printerr("Expected a nonnegative tick, overview or street, and a supported speed.")
		quit(1)
		return
	var world=load("res://main.tscn").instantiate()
	world.model=CityModel.new()
	world.model.reset(147)
	world.model.step(tick)
	root.add_child(world)
	world._select_speed(speed)
	world._fit_city()
	if view=="street": world._street_view()
	for frame in 15: await RenderingServer.frame_post_draw
	var frame_ms:Array[float]=[]
	var start_tick:int=world.state.tick
	var started:=Time.get_ticks_usec()
	var previous:=started
	for frame in 60:
		await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec()
		frame_ms.append((now-previous)/1000.)
		previous=now
	frame_ms.sort()
	var elapsed:float=(previous-started)/1000000.
	print("%s at %dx, %d residents, p50 %.1f ms, p95 %.1f ms, %.1f simulated minutes per real second" %
		[view,speed,world.state.population,frame_ms[29],frame_ms[56],(world.state.tick-start_tick)/(4.*elapsed)])
	quit()
