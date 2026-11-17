extends SceneTree
const Geo=preload("res://scripts/geography.gd")
const Picker=preload("res://scripts/settlement_picker.gd")
var failures:=0

func _initialize(): run.call_deferred()

func check(ok:bool,description:String) -> void:
	if not ok:
		push_error(description)
		failures+=1

func run() -> void:
	var app=load("res://launch.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var picker=app.picker
	check(is_instance_valid(picker) and app.world==null,"Default launch skipped the world map")
	for coord in [Vector2(35.798,126.825),Vector2(-34.52,-58.38),Vector2(64.1,179.9)]:
		check(coord.distance_to(Geo.geographic(Geo.mercator(coord.x,coord.y)))<.0001,"Projection failed to round trip")
	check(Picker.parse_point("https://www.google.com/maps/place/X/@1,2,10z/data=!3d47.342!4d0.465")==[47.342,.465],"Place pin lost to viewport centre")
	check(Picker.parse_point("35.798, 126.825")==[35.798,126.825],"Coordinate entry failed")
	picker.location.text="서울"
	picker._locate()
	check(picker.chosen and absf(picker.lat-37.56)<.15,"City search failed")
	picker.select_point(89.,0.,"")
	check(picker.status.text.contains("85"),"Polar limit missing")
	var wet=picker.geo._lake_mask(47.60,-87.48)
	check(wet[Geo.SIDE*Geo.SIDE/2]==1,"Lake Superior missing from water mask")
	var atlas=picker.atlas
	picker._stop_focus()
	var clicks:=Vector2(850,365)
	var expected:=Geo.geographic(atlas.at(clicks))
	var button:=InputEventMouseButton.new()
	button.button_index=MOUSE_BUTTON_LEFT
	button.position=clicks
	button.pressed=true
	atlas._gui_input(button)
	button.pressed=false
	atlas._gui_input(button)
	check(Vector2(picker.lat,picker.lon).distance_to(expected)<.001,"Map click selected a different coordinate")
	var before:Vector2=atlas.at(clicks)
	atlas.set_zoom(atlas.zoom+1.,clicks)
	check(atlas.at(clicks).distance_to(before)<.00001,"Zoom lost its geographic anchor")
	var centres:Array[float]=[]
	for region in Picker.SITES:
		var data:Dictionary=await picker.geo.survey(region[1],region[2])
		check(not data.is_empty(),"Offline survey missing for "+region[0])
		if data.is_empty(): continue
		var model:=CityModel.new()
		check(model.settle_at(147,region[1],region[2],data.heights,data.lakes),"Sample site rejected: "+region[0])
		centres.append(model.height_at(0,0)-model.sea_level())
	check(centres.size()==3 and absf(centres[0]-centres[1])>10,"Sites share the same elevation")
	picker.select_point(Picker.SITES[0][1],Picker.SITES[0][2],Picker.SITES[0][0])
	picker.begin.pressed.emit()
	for _i in 300:
		await process_frame
		if app.world!=null and not app.flying: break
	check(app.world!=null and not app.flying,"Map to 3D handoff failed")
	if app.world!=null and not app.flying:
		check(app.world.model.is_geographic() and app.world.state.population>0 and app.world.hud.visible,"Imported world did not start")
		var previous=app.world
		app.world.hud.world_button.pressed.emit()
		check(is_instance_valid(app.picker) and previous.process_mode==Node.PROCESS_MODE_DISABLED,"Return to map failed")
		app.picker.back.pressed.emit()
		check(app.world==previous and app.picker==null and app.world.hud.visible,"Resume lost the current settlement")
	print("Settlement checks completed with ",failures," failures.")
	app.queue_free()
	await process_frame
	quit(1 if failures else 0)
