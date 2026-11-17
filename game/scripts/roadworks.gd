extends Node3D
const Forms=preload("res://scripts/forms.gd")
const YELLOW=Color("#d6a041")
const STEEL=Color("#505952")
const RUBBER=Color("#353b38")

var data:Dictionary
var street:MeshInstance3D
var fixtures:Array
var stations:=PackedFloat32Array()
var plane:=Vector4()
var machine:MeshInstance3D
var closure:MeshInstance3D
var last_clear:=0
var progress:=0.

func setup(record:Dictionary,road:MeshInstance3D,props:Array) -> void:
	data=record
	street=road
	fixtures=props
	var path:PackedVector3Array=data.path
	var start:=Vector2(path[0].x,path[0].z)
	var axis:=Vector2(path[-1].x,path[-1].z)-start
	axis/=axis.length_squared()
	plane=Vector4(axis.x,axis.y,-axis.dot(start),0)
	for point in path: stations.append(axis.dot(Vector2(point.x,point.z)-start))
	machine=_roller() if not data.bridge else _deck_rig()
	var signs=Forms.new()
	for z in [-1,1]:
		signs.box(Vector3(.07,.10,z*.97),Vector3(.48,.18,.30),STEEL)
		signs.box(Vector3(0,.60,z*.97),Vector3(.11,1.12,.10),STEEL)
	for i in 8:
		signs.box(Vector3(0,.99,(i-3.5)*.31),Vector3(.12,.31,.31),Color("#d6d1b8") if i%2 else Color("#b65d3b"))
	closure=signs.attach(self)

func _roller() -> MeshInstance3D:
	var g=Forms.new()
	# The steel compaction drum spans the width between the two fork arms.
	for j in 16:
		var a:=TAU*j/16
		var b:=TAU*(j+1)/16
		var u:=Vector3(cos(a),sin(a),0)*.62
		var v:=Vector3(cos(b),sin(b),0)*.62
		var c:=Vector3(1.04,.62,0)
		g.quad(c+u+Vector3.BACK*.92,c+v+Vector3.BACK*.92,c+v-Vector3.BACK*.92,c+u-Vector3.BACK*.92,Color("#767b73"),u+v)
		for side in [-1,1]:
			var face:Vector3=c+Vector3.BACK*side*.92
			g.triangle(face,face+u,face+v,STEEL,Vector3.BACK*side)
	g.box(Vector3(-.65,.9,0),Vector3(2.15,.70,1.63),YELLOW)
	g.box(Vector3(-1.10,1.35,0),Vector3(1.12,.43,1.50),YELLOW.darkened(.12))
	g.box(Vector3(-.18,1.77,0),Vector3(.85,1.04,1.13),Color("#465a59"))
	g.box(Vector3(-.18,2.36,0),Vector3(1.25,.13,1.44),YELLOW)
	for z in [-1,1]:
		g.wheel(Vector3(-1.16,.52,z*.78),.52,z)
		g.beam(Vector3(-.15,.97,z*.99),Vector3(1.04,.62,z*.99),.16,YELLOW)
	return g.attach(self)

func _deck_rig() -> MeshInstance3D:
	var g=Forms.new()
	g.box(Vector3(0,.31,0),Vector3(3.5,.59,1.8),STEEL)
	g.box(Vector3(-.37,1.0,0),Vector3(2.27,.95,1.62),YELLOW)
	g.box(Vector3(-.60,1.87,0),Vector3(1.11,.91,1.22),Color("#435756"))
	g.beam(Vector3.ZERO,Vector3(2.7,5.2,0),.35,YELLOW)
	g.beam(Vector3(2.7,5.2,0),Vector3(2.7,2.3,0),.042,STEEL)
	g.box(Vector3(2.7,2.2,0),Vector3(.30,.27,2.8),STEEL)
	return g.attach(self)

func _at_front(node:Node3D,station:float,offset:float) -> void:
	station=clampf(station,0,1)
	var i:=clampi(stations.bsearch(station)-1,0,stations.size()-2)
	var path:PackedVector3Array=data.path
	var tangent:=(path[i+1]-path[i]).normalized()
	var t:=inverse_lerp(stations[i],stations[i+1],station)
	node.position=path[i].lerp(path[i+1],t)+Vector3(-tangent.z,0,tangent.x)*offset+Vector3.UP*.45
	node.rotation.y=-atan2(tangent.z,tangent.x)

func advance(time:float,land) -> bool:
	progress=clampf(inverse_lerp(data.started,data.opens,time),0,1)
	var leading:=smoothstep(0,1,progress)*1.28
	plane.w=leading
	street.set_instance_shader_parameter("workfront",plane)
	var path:PackedVector3Array=data.path
	while last_clear<path.size()-1 and stations[last_clear]<=leading:
		land.clear_street(path.slice(last_clear,last_clear+2),data.width*.5+2.8)
		last_clear+=1
	for fixture in fixtures:
		var t:=smoothstep(fixture.at+.19,fixture.at+.27,leading)
		fixture.node.visible=t>0
		if fixture.node is MeshInstance3D: fixture.node.scale=Vector3.ONE*maxf(t,.001)
	_at_front(machine,leading-.13,data.width*.14)
	_at_front(closure,leading-.24,-data.width*.21)
	var demobilize:=smoothstep(0.,.045,progress)*(1.-smoothstep(.94,1.,progress))
	machine.scale=Vector3.ONE*maxf(.001,demobilize)
	closure.scale=machine.scale
	return time>=data.opens
