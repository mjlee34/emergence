extends SceneTree

var failures:=0

func _initialize() -> void:
	run.call_deferred()

func check(ok:bool,message:String) -> void:
	if not ok:
		failures+=1
		push_error(message)

func run() -> void:
	for scenario in [[156,156000,"orbit",140.],[29,329000,"liberty",94.],[481,145000,"lattice",154.],
			[31,203000,"lantern",90.],[171,145000,"arch",94.],[36,468000,"clock",104.]]:
		var world=load("res://main.tscn").instantiate()
		world.model=CityModel.new()
		world.model.reset(scenario[0])
		world.model.step(scenario[1])
		root.add_child(world)
		world.set_process(false)
		var found:=false
		for id in world.town.greens.size():
			var site=world.town.greens[id]
			if site.data.get("model","")!=scenario[2]: continue
			found=true
			var mesh:MeshInstance3D=site.monument
			var size_m:=mesh.get_aabb().size*mesh.scale
			check(size_m.y>=scenario[3],"Landmark height fell below skyline scale")
			check(Vector2(size_m.x,size_m.z).length()*.5<site.data.radius,"Footings exceed reserved grounds")
			var top:Vector3=site.position+Vector3.UP*site.monument_height
			site.advance(lerpf(site.data.started,site.data.opens,.55))
			check(site.visible_monument_height>0 and site.visible_monument_height<site.monument_height,"Construction lost its progressive silhouette")
			site.advance(site.data.opens)
			if site.data.model=="clock":
				site.set_clock(720)
				var noon:float=site.clock_hands[1].rotation.z
				site.set_clock(735)
				check(absf(angle_difference(noon,site.clock_hands[1].rotation.z)+PI*.5)<.002,"Clock hands failed to show city time")
			world._visit_green(id)
			check(world.orbit.is_position_in_frustum(top) and world.orbit.is_position_in_frustum(site.position),"Places view cropped the landmark")
			world._skyline()
			check(world.orbit.is_position_in_frustum(top) and world.orbit.is_position_in_frustum(site.position),"Skyline view cropped the landmark")
			world._fit_city()
			check(world.orbit.is_position_in_frustum(top),"City overview cropped the landmark")
		check(found,"Expected an organically built landmark")
		world.free()
	print("Landmark view checks completed with ",failures," failures.")
	quit(1 if failures else 0)
