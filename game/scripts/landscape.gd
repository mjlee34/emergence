extends Node3D
const Forms = preload("res://scripts/forms.gd")
const X = 480
const Z = 320
const STEP = 5
var model
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
	var land=Forms.new(true)
	land.finish=Forms.Finish.MEADOW
	# Sample the playable valley finely and continue the horizon beyond it.
	var xs:=_axis(X)
	var zs:=_axis(Z)
	var grid:=PackedVector3Array()
	var rng:=RandomNumberGenerator.new()
	rng.seed=779
	for z in zs:
		for x in xs:
			grid.append(Vector3(x,model.height_at(x,z),z))
	for j in range(zs.size()-1):
		for i in range(xs.size()-1):
			var k:=j*xs.size()+i
			_facet(land,grid[k],grid[k+1],grid[k+xs.size()+1])
			_facet(land,grid[k],grid[k+xs.size()+1],grid[k+xs.size()])
	land.attach(self)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2((X+1200)*2,(Z+1200)*2)
	water.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/river.gdshader")
	water.material_override = mat
	add_child(water)
	_forest(rng)
	_rocks(rng)

func _facet(g,a: Vector3,b: Vector3,c: Vector3) -> void:
	var p := (a+b+c)/3
	var grass := Color("#a9b575").lerp(Color("#789660"),0.5+0.3*sin(p.x*.051)+0.18*cos(p.z*.115))
	grass = grass.lerp(Color("#667c65"),clampf((p.y-12)/30,0,0.92))
	var slope := 1.0-absf((b-a).cross(c-a).normalized().y)
	var rock := Color("#bab7a1").lerp(Color("#879386"),0.5+0.35*sin(p.y*.56))
	grass = grass.lerp(rock,clampf((slope-0.1)*3.3+maxf(p.y-33,0)*.046,0,1))
	if p.y<2.9: grass = Color("#d3c397").lerp(grass,smoothstep(.6,2.9,p.y))
	g.triangle(a,b,c,grass.lightened(.017*(1+sin(p.x*5+p.z))),Vector3.UP)

func _axis(edge:int) -> PackedInt32Array:
	var values:=PackedInt32Array()
	for x in range(-edge-1200,-edge,30): values.append(x)
	for x in range(-edge,edge,STEP): values.append(x)
	for x in range(edge,edge+1201,30): values.append(x)
	return values

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
			x=rng.randf_range(-X-580,X+580)
			z=rng.randf_range(-Z-580,Z+580)
			if absf(x)<X and absf(z)<Z: continue
		var h: float = model.height_at(x,z)
		var density := sin(x*.069+sin(z*.07))*.25+cos(z*.078-x*.057)*.2
		var woodland := absf(x+22)>97 or z < -76 or z>85
		if h<1.7 or h>36 or rng.randf()>(.55 if woodland else .085)+density: continue
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
