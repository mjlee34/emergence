extends Node3D
const Forms = preload("res://scripts/forms.gd")
const X = 216
const Z = 164
const STEP = 4
var model
var groves: Array[MultiMesh]=[]
var species:=PackedByteArray()
var instance_ids:=PackedInt32Array()
var tree_sites := PackedVector3Array()
var active := PackedByteArray()

func create(sim) -> void:
	model = sim
	var land = Forms.new()
	var step_count := int(2*X/STEP)+1
	var grid := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 779
	for j in range(int(2*Z/STEP)+1):
		for i in range(step_count):
			var x := float(-X+i*STEP)
			var z := float(-Z+j*STEP)
			if absf(x)<X: x += rng.randf_range(-0.68,0.68)
			if absf(z)<Z: z += rng.randf_range(-0.68,0.68)
			grid.append(Vector3(x,model.height_at(x,z),z))
	for j in range(int(2*Z/STEP)):
		for i in range(step_count-1):
			var k := j*step_count+i
			var a := grid[k]
			var b := grid[k+1]
			var c := grid[k+step_count+1]
			var d := grid[k+step_count]
			_facet(land,a,b,c)
			_facet(land,a,c,d)
			if j==0: _cut(land,a,b,Vector3.FORWARD)
			if i==0: _cut(land,a,d,Vector3.LEFT)
			if j==int(2*Z/STEP)-1: _cut(land,d,c,Vector3.BACK)
			if i==step_count-2: _cut(land,b,c,Vector3.RIGHT)
	land.attach(self)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(X*2,Z*2)
	water.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/river.gdshader")
	water.material_override = mat
	add_child(water)
	var base = Forms.new()
	base.box(Vector3(0,-10,0),Vector3(X*2+0.1,1.4,Z*2+0.1),Color("#47504b"))
	base.attach(self)
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

func _cut(g,a: Vector3,b: Vector3,n: Vector3) -> void:
	var upper_a := a
	var upper_b := b
	for band in [[-1.4,"#927d5b"],[-4.7,"#ac956f"],[-5.5,"#c0ae8d"],[-9.5,"#85775f"]]:
		var low_a := Vector3(a.x,minf(upper_a.y,band[0]),a.z)
		var low_b := Vector3(b.x,minf(upper_b.y,band[0]),b.z)
		if upper_a.y>low_a.y or upper_b.y>low_b.y:
			g.quad(upper_a,upper_b,low_b,low_a,Color(band[1]),n)
		upper_a=low_a
		upper_b=low_b

func _forest(rng: RandomNumberGenerator) -> void:
	var tree = Forms.new()
	tree.taper(Vector3.ZERO,.36,.27,3.1,6,Color("#795a43"))
	tree.taper(Vector3(0,1.4,0),2.5,.18,4.0,7,Color("#386554"),.24)
	tree.taper(Vector3(0,3.25,0),2.12,.1,3.8,7,Color("#47745a"),.55)
	tree.taper(Vector3(0,5,0),1.45,0,3.4,7,Color("#598367"),.28)
	var alder=Forms.new()
	alder.taper(Vector3.ZERO,.39,.26,4.5,7,Color("#80694e"))
	for crown in [Vector4(-1.15,3.1,-.15,2.05),Vector4(1.22,3.7,.35,1.9),Vector4(0,4.5,0,2.45)]:
		var pos:=Vector3(crown.x,crown.y,crown.z)
		alder.taper(pos,.65,crown.w,1.55,7,Color("#b9a754"),crown.x)
		alder.taper(pos+Vector3.UP*1.55,crown.w,crown.w*.59,1.7,7,Color("#d4bd62"),crown.x)
		alder.taper(pos+Vector3.UP*3.25,crown.w*.59,.18,.78,7,Color("#e6c968"),crown.x)
	var poses: Array=[[],[]]
	var shades: Array=[[],[]]
	for mesh in [tree.mesh(),alder.mesh()]:
		var instances:=MultiMesh.new()
		instances.transform_format=MultiMesh.TRANSFORM_3D
		instances.use_colors=true
		instances.mesh=mesh
		groves.append(instances)
	for i in range(4700):
		var x := rng.randf_range(-X+3,X-3)
		var z := rng.randf_range(-Z+3,Z-3)
		var h: float = model.height_at(x,z)
		var density := sin(x*.069+sin(z*.07))*.25+cos(z*.078-x*.057)*.2
		var woodland := absf(x+22)>97 or z < -76 or z>85
		if h<1.7 or h>36 or rng.randf()>(.55 if woodland else .085)+density: continue
		var size := rng.randf_range(.58,1.65)
		var pos := Vector3(x,h-.32,z)
		var kind:=1 if rng.randf()<(.29 if h<12 else .08)+.11*sin(z*.08+x*.04) else 0
		species.append(kind)
		instance_ids.append(poses[kind].size())
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
		var grove:=MultiMeshInstance3D.new()
		grove.multimesh=instances
		add_child(grove)

func clear_street(path: PackedVector3Array, clearance: float) -> void:
	var a := Vector2(path[0].x,path[0].z)
	var b := Vector2(path[-1].x,path[-1].z)
	for i in tree_sites.size():
		if not active[i]: continue
		var p := Vector2(tree_sites[i].x,tree_sites[i].z)
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
