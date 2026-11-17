extends Node3D
const Forms = preload("res://scripts/forms.gd")
const X = 480
const Z = 320
const STEP = 5
const TILE = 160
const COARSE_STEP = 20
var region:Vector2i
var coarse_tiles:Dictionary={}
var fine_tiles:Dictionary={}
var target_tile:=Vector2i(9999,9999)
var queued_tiles:Array[Vector2i]=[]
var model
var water_material:=ShaderMaterial.new()
var lakes
var has_lakes:=false
var sea:=0.
var groves: Array[MultiMesh]=[]
var species:=PackedByteArray()
var instance_ids:=PackedInt32Array()
var tree_sites := PackedVector3Array()
var active := PackedByteArray()
var tree_cells: Dictionary = {}

func _cell(p:Vector3) -> Vector2i:
	return Vector2i(floori(p.x/32.),floori(p.z/32.))

func create(sim) -> void:
	model = sim
	sea=model.sea_level()
	region=Vector2i(model.region_half_size())
	var rng:=RandomNumberGenerator.new()
	rng.seed=779
	# The original valley stays detailed. The outer districts start with the
	# same 20 m spacing as the geographic survey.
	_patch(Rect2i(-X,-Z,2*X,2*Z),STEP,true)
	for z in range(-region.y,region.y,TILE):
		for x in range(-region.x,region.x,TILE):
			if x>=-X and x<X and z>=-Z and z<Z: continue
			var key:=Vector2i(x/TILE,z/TILE)
			coarse_tiles[key]=_patch(Rect2i(x,z,TILE,TILE),COARSE_STEP)
	var horizon:=1920
	for sign_dir in [-1,1]:
		var z_edge:int=region.y if sign_dir==1 else -region.y-horizon
		var x_edge:int=region.x if sign_dir==1 else -region.x-horizon
		_patch(Rect2i(-region.x-horizon,z_edge,2*(region.x+horizon),horizon),40)
		_patch(Rect2i(x_edge,-region.y,horizon,2*region.y),40)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(region+Vector2i(horizon,horizon))*2.
	water.mesh = plane
	water_material.shader = preload("res://scripts/river.gdshader")
	water.material_override = water_material
	water.position.y=sea+.025 if model.is_geographic() else 0.
	add_child(water)
	_forest(rng)
	if not model.is_geographic(): _rocks(rng)

func _terrain_colour(p:Vector3,normal:Vector3) -> Color:
	var grass:=Color("#a1ad7d").lerp(Color("#7c9069"),.5+.28*sin(p.x*.019)+.19*cos(p.z*.027))
	grass=grass.lerp(Color("#657765"),smoothstep(12.,45.,p.y-sea)*.88)
	var rock:=Color("#a9a796").lerp(Color("#828982"),.5+.30*sin(p.y*.09+p.x*.012))
	grass=grass.lerp(rock,clampf((1.-normal.y-.10)*3.3+maxf(p.y-sea-33.,0.)*.038,0.,1.))
	return Color("#c3b694").lerp(grass,smoothstep(.6,2.9,p.y-sea)).srgb_to_linear()

func _water_facet(a:Vector3,b:Vector3,c:Vector3) -> void:
	var center:=(a+b+c)/3.
	if model.inland_water(center.x,center.z):
		has_lakes=true
		var lift:=Vector3.UP*.16
		lakes.triangle(a+lift,b+lift,c+lift,Color.WHITE,Vector3.UP)

func _patch(rect:Rect2i,step:int,stitch:=false) -> Node3D:
	var tile:=Node3D.new()
	add_child(tile)
	var land=Forms.new(true)
	land.finish=Forms.Finish.MEADOW
	lakes=Forms.new() if model.is_geographic() else null
	has_lakes=false
	var grid:=PackedVector3Array()
	var cols:=rect.size.x/step+1
	for z in range(rect.position.y,rect.end.y+1,step):
		for x in range(rect.position.x,rect.end.x+1,step):
			var h:float=model.height_at(x,z)
			# Match the edges of a fine patch to the coarser neighbour.
			if stitch and (z==rect.position.y or z==rect.end.y) and posmod(x,COARSE_STEP)!=0:
				var dx:=posmod(x,COARSE_STEP)
				h=lerpf(model.height_at(x-dx,z),model.height_at(x-dx+COARSE_STEP,z),dx/float(COARSE_STEP))
			elif stitch and (x==rect.position.x or x==rect.end.x) and posmod(z,COARSE_STEP)!=0:
				var dz:=posmod(z,COARSE_STEP)
				h=lerpf(model.height_at(x,z-dz),model.height_at(x,z-dz+COARSE_STEP),dz/float(COARSE_STEP))
			var p:=Vector3(x,h,z)
			grid.append(p)
			# Use the same metre-scale slope on both sides of every LOD boundary.
			var normal:=Vector3(model.height_at(x-5,z)-model.height_at(x+5,z),10.,
				model.height_at(x,z-5)-model.height_at(x,z+5)).normalized()
			var tangent:=(Vector3.RIGHT-normal*normal.x).normalized()
			land.surface.set_normal(normal)
			land.surface.set_tangent(Plane(tangent,-1.))
			land.surface.set_color(_terrain_colour(p,normal))
			land.surface.set_uv(Vector2(x,z))
			land.surface.set_uv2(Vector2(Forms.Finish.MEADOW,0))
			land.surface.add_vertex(p)
	for j in rect.size.y/step:
		for i in cols-1:
			var k:=j*cols+i
			for vertex in [k,k+1,k+cols+1,k,k+cols+1,k+cols]:
				land.surface.add_index(vertex)
			if lakes:
				_water_facet(grid[k],grid[k+1],grid[k+cols+1])
				_water_facet(grid[k],grid[k+cols+1],grid[k+cols])
	land.attach(tile)
	if has_lakes:
		var surface=lakes.attach(tile)
		surface.material_override=water_material
	lakes=null
	return tile

func detail_near(focus:Vector3,extent:float) -> void:
	var key:=Vector2i(floori(focus.x/TILE),floori(focus.z/TILE)) if extent<190. else Vector2i(9999,9999)
	if key!=target_tile:
		target_tile=key
		queued_tiles.clear()
		var wanted:Dictionary={}
		for y in range(-1,2):
			for x in range(-1,2):
				var tile:=key+Vector2i(x,y)
				if not coarse_tiles.has(tile): continue
				wanted[tile]=true
				if not fine_tiles.has(tile): queued_tiles.append(tile)
		for tile in fine_tiles.keys():
			if wanted.has(tile): continue
			fine_tiles[tile].queue_free()
			fine_tiles.erase(tile)
			coarse_tiles[tile].show()
		queued_tiles.sort_custom(func(a:Vector2i,b:Vector2i): return a.distance_squared_to(key)>b.distance_squared_to(key))
	if not queued_tiles.is_empty():
		var tile:Vector2i=queued_tiles.pop_back()
		fine_tiles[tile]=_patch(Rect2i(tile*TILE,Vector2i(TILE,TILE)),STEP,true)
		coarse_tiles[tile].hide()

static func crown_mesh(image:Texture2D,height:float) -> QuadMesh:
	var sheet:=QuadMesh.new()
	sheet.size=Vector2.ONE*height*1.18
	sheet.custom_aabb=AABB(Vector3(-height*.65,-.18*height,-height*.65),Vector3(height*1.3,height*1.36,height*1.3))
	var bark:=ShaderMaterial.new()
	bark.shader=preload("res://scripts/canopy.gdshader")
	bark.set_shader_parameter("crown",image)
	bark.set_shader_parameter("height",height)
	sheet.material=bark
	return sheet

func _forest(rng: RandomNumberGenerator) -> void:
	var poses: Array=[[],[]]
	var shades: Array=[[],[]]
	for mesh in [crown_mesh(preload("res://art/fir.png"),10.),crown_mesh(preload("res://art/deciduous.png"),7.8)]:
		var instances:=MultiMesh.new()
		instances.transform_format=MultiMesh.TRANSFORM_3D
		instances.use_colors=true
		instances.use_custom_data=true
		instances.mesh=mesh
		groves.append(instances)
	for i in range(21800):
		var x := rng.randf_range(-X+3,X-3)
		var z := rng.randf_range(-Z+3,Z-3)
		if i>=11500:
			x=rng.randf_range(-region.x-160,region.x+160)
			z=rng.randf_range(-region.y-160,region.y+160)
			if absf(x)<X and absf(z)<Z: continue
		var h: float = model.height_at(x,z)
		var density := sin(x*.069+sin(z*.07))*.25+cos(z*.078-x*.057)*.2
		var woodland := absf(x+22)>97 or z < -76 or z>85
		if h-sea<1.7 or model.inland_water(x,z) or h>(48. if model.is_geographic() else 36.) or rng.randf()>(.55 if woodland else .085)+density: continue
		var size := rng.randf_range(.58,1.65)
		var pos := Vector3(x,h-.32,z)
		var kind:=1 if rng.randf()<(.64 if h<12 else .24)+.11*sin(z*.08+x*.04) else 0
		species.append(kind)
		instance_ids.append(poses[kind].size())
		var cell:=_cell(pos)
		if not tree_cells.has(cell): tree_cells[cell]=[]
		tree_cells[cell].append(tree_sites.size())
		tree_sites.append(pos)
		active.append(1)
		poses[kind].append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*size),pos))
		shades[kind].append(Color.WHITE.lerp(Color("#d0bd91"),rng.randf()*.64))
	for kind in groves.size():
		var instances:=groves[kind]
		instances.instance_count=poses[kind].size()
		for i in poses[kind].size():
			instances.set_instance_transform(i,poses[kind][i])
			instances.set_instance_color(i,shades[kind][i])
			instances.set_instance_custom_data(i,Color(float(i%2),0,0,0))
		var grove:=MultiMeshInstance3D.new()
		grove.multimesh=instances
		add_child(grove)

func clear_street(path: PackedVector3Array, clearance: float) -> void:
	var a := Vector2(path[0].x,path[0].z)
	var b := Vector2(path[-1].x,path[-1].z)
	var margin:=Vector3(clearance+3,0,clearance+3)
	var first:=_cell(path[0].min(path[-1])-margin)
	var last:=_cell(path[0].max(path[-1])+margin)
	for x in range(first.x,last.x+1):
		for z in range(first.y,last.y+1):
			for i in tree_cells.get(Vector2i(x,z),[]):
				if not active[i]: continue
				var p:=Vector2(tree_sites[i].x,tree_sites[i].z)
				if Geometry2D.get_closest_point_to_segment(p,a,b).distance_squared_to(p)<clearance*clearance:
					active[i]=0
					groves[species[i]].set_instance_transform(instance_ids[i],Transform3D(Basis.IDENTITY,Vector3(0,-200,0)))

func clear_lot(pos: Vector3) -> void:
	clear_street(PackedVector3Array([pos, pos+Vector3(.01,0,0)]),6.8)

func _rocks(rng: RandomNumberGenerator) -> void:
	var rocks = Forms.new()
	for i in range(430):
		var z:=rng.randf_range(-Z+2,Z-2)
		var x:float=model.river_x(z)+rng.randf_range(13,22)*(-1 if i%2 else 1)
		var h:float=model.height_at(x,z)
		if h < -1.1 or h>2.2: continue
		var r:=rng.randf_range(.45,1.9)
		var p:=Vector3(x,h-.25,z)
		rocks.taper(p,r,r*.64,r*.75,5,Color("#a3aaa0"),i*.31)
	rocks.attach(self)
