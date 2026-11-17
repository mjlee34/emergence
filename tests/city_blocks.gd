extends SceneTree
const Blocks=preload("res://scripts/city_blocks.gd")
var failed:=false

func _initialize() -> void: run.call_deferred()

func check(ok:bool,message:String) -> void:
	if not ok:
		push_error(message)
		failed=true

func run() -> void:
	var blocks=Blocks.new()
	var parent:=Node3D.new()
	root.add_child(parent)
	var model:=CityModel.new()
	var points:=[Vector2(0,0),Vector2(40,0),Vector2(80,0),Vector2(0,40),Vector2(40,40),Vector2(80,40)]
	var streets:=[[0,1],[1,2],[2,5],[5,4],[4,3],[3,0],[1,4]]
	var lots:Array[Dictionary]=[]
	for i in streets.size():
		var ends:Array=streets[i]
		var path:=PackedVector3Array()
		for sample in 9:
			var p:Vector2=points[ends[0]].lerp(points[ends[1]],sample/8.)
			path.append(Vector3(p.x,0.,p.y))
		blocks.opened(i,{"from_id":ends[0],"to_id":ends[1],"path":path,"bridge":false,"surveyed":true})
		if i==5:
			blocks.sync(parent,model,lots)
			check(blocks.faces.size()==1 and blocks.surfaces.is_empty(),"Unoccupied perimeter should enclose one unpaved block")
	# Both districts face opposite sides of the shared street. Each supplies
	# enough occupied frontage to qualify its own courtyard.
	for i in 5:
		lots.append({"frontage":6,"front_sign":-1,"use":2})
		lots.append({"frontage":6,"front_sign":1,"use":0})
	blocks.sync(parent,model,lots)
	check(blocks.faces.size()==2 and blocks.surfaces.size()==2,"Cross street failed to divide the block")
	for key in blocks.surfaces:
		var face:Dictionary=blocks.faces[key]
		var surface:Dictionary=blocks.surfaces[key]
		check(surface.kind==(2 if face.edges.has(0) else 0),"Opposite frontage changed the block's land use")
		check(surface.mesh.get_aabb().size.x<=40.1,"New courtyard crossed the dividing street")
	parent.free()
	print("City block checks completed with ",int(failed)," failures.")
	quit(int(failed))
