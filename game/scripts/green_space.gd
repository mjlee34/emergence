extends Node3D
const Forms=preload("res://scripts/forms.gd")
const WOOD:=Color("#a97748")
const FRAME:=Color("#344744")
const GRAVEL:=Color("#cebc96")
const STONE:=Color("#b4b1a2")
var data:Dictionary
var model
var turf:MeshInstance3D
var fittings:=Node3D.new()
var planting:=Node3D.new()
static var shrub_mesh:Mesh

func setup(sim,land,site:Dictionary,canopy:Mesh) -> void:
	model=sim
	data=site
	position=data.pos
	rotation.y=data.yaw
	land.clear_street(PackedVector3Array([position,position+Vector3.RIGHT*.01]),data.radius+1.)
	land.clear_street(PackedVector3Array([data.curb,data.gate]),1.1)
	add_child(fittings)
	add_child(planting)
	var g=Forms.new(true)
	var r:float=data.radius
	for i in 48:
		var a:=i*TAU/48
		var b:=(i+1)*TAU/48
		g.finish=Forms.Finish.MEADOW
		g.triangle(_p(0,0),_arc(r-.50,a),_arc(r-.50,b),Color("#82975f"),Vector3.UP)
		g.quad(_arc(r-.50,a),_arc(r-.50,b),_arc(r,b,-.27),_arc(r,a,-.27),Color("#7a875d"),Vector3.UP)
		g.finish=Forms.Finish.WALK
		g.quad(_arc(r*.62-.65,a,.04),_arc(r*.62+.65,a,.04),_arc(r*.62+.65,b,.04),_arc(r*.62-.65,b,.04),GRAVEL,Vector3.UP)
		g.finish=Forms.Finish.PLAIN
		for edge in [r*.62-.68,r*.62+.66]:
			g.quad(_arc(edge,a,.045),_arc(edge+.075,a,.045),_arc(edge+.075,b,.045),_arc(edge,b,.045),STONE,Vector3.UP)
	var curb:=to_local(data.curb)
	g.finish=Forms.Finish.WALK
	var far:float=curb.z
	for i in 8:
		var z0:=lerpf(far,-r*.62,i/8.)
		var z1:=lerpf(far,-r*.62,(i+1)/8.)
		g.quad(_p(-.76,z0,.055),_p(.76,z0,.055),_p(.76,z1,.055),_p(-.76,z1,.055),GRAVEL,Vector3.UP)
	turf=g.attach(self)
	if data.kind==0:
		_garden()
		_tree(canopy,-r*.71,r*.40,1.28)
		_tree(canopy,r*.75,r*.34,1.13)
		_tree(canopy,-r*.64,-r*.46,.88)
	else:
		_playground()
		_tree(canopy,-r*.66,r*.48,.95)
	_bench(-r*.80,-.6,PI*.5)
	_bench(r*.80,-.7,-PI*.5)
	if not shrub_mesh:
		shrub_mesh=preload("res://scripts/landscape.gd").crown_mesh(preload("res://art/deciduous.png"),1.08)
		shrub_mesh.material.set_shader_parameter("crown_fraction",.76)
	var shrubs:=MultiMesh.new()
	shrubs.transform_format=MultiMesh.TRANSFORM_3D
	shrubs.mesh=shrub_mesh
	shrubs.instance_count=30
	for i in shrubs.instance_count:
		var a:=(i%3)*TAU/3.+.72+sin(i*2.39996)*.42
		var r2:float=r*(.86+.07*sin(5.1*i))
		var root:=_arc(r2,a)
		var spread:=.77+.22*sin(4.2*i)
		shrubs.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*spread),root))
	var border:=MultiMeshInstance3D.new()
	border.multimesh=shrubs
	planting.add_child(border)
	var gate=Forms.new()
	var base:=_p(-1.36,-r+.35)
	gate.box(base+Vector3.UP*.66,Vector3(.1,1.32,.1),WOOD)
	gate.box(base+Vector3.UP*1.12,Vector3(.94,.53,.11),Color("#3e6859"))
	var label:=Label3D.new()
	label.text="GARDEN" if data.kind==0 else "PLAY"
	label.position=base+Vector3(0,1.12,-.066)
	label.rotation.y=PI
	label.pixel_size=.0043
	label.font_size=36
	label.outline_size=0
	fittings.add_child(label)
	gate.attach(fittings)

func _p(x:float,z:float,extra:=0.) -> Vector3:
	var p:=to_global(Vector3(x,0,z))
	return Vector3(x,model.height_at(p.x,p.z)-position.y+.285+extra,z)

func _arc(r:float,a:float,h:=0.) -> Vector3:
	return _p(r*sin(a),-r*cos(a),h)

func _tree(canopy:Mesh,x:float,z:float,s:float) -> void:
	var node:=MeshInstance3D.new()
	node.mesh=canopy
	node.position=_p(x,z)
	node.rotation.y=x+z
	node.scale=Vector3.ONE*s
	planting.add_child(node)

func _bench(x:float,z:float,yaw:float) -> void:
	var g=Forms.new()
	for end in [-.68,.68]:
		g.box(Vector3(end,.23,0),Vector3(.08,.46,.45),FRAME)
		g.beam(Vector3(end,.40,-.21),Vector3(end,.89,-.32),.07,FRAME)
	for row in 4:
		g.box(Vector3(0,.46,-.23+.14*row),Vector3(1.85,.08,.11),WOOD)
	for row in 2: g.box(Vector3(0,.70+.16*row,-.30),Vector3(1.85,.12,.065),WOOD)
	var seat=g.attach(fittings)
	seat.position=_p(x,z)
	seat.rotation.y=yaw

func _garden() -> void:
	var g=Forms.new()
	# Low stone rim, water and a tiered fountain leave sightlines across the garden.
	g.taper(Vector3.ZERO,1.30,1.28,.29,32,STONE)
	g.taper(Vector3.UP*.29,1.12,1.12,.035,32,Color("#699da0"))
	g.taper(Vector3.UP*.32,.21,.13,.49,16,STONE)
	g.taper(Vector3.UP*.80,.18,.60,.18,24,STONE)
	g.taper(Vector3.UP*.98,.49,.49,.025,24,Color("#82b1ad"))
	g.taper(Vector3.UP*1.01,.09,.025,.26,12,Color("#cedfe0"))
	g.attach(fittings).position=_p(0,0)
	var beds=Forms.new()
	for side in [-1,1]:
		var x:float=side*2.65
		beds.taper(_p(x,0),1.08,1.08,.17,16,Color("#806e53"))
		for i in 30:
			var a:=i*2.4
			var d:=.92*sqrt(i/30.)
			var base:=_p(x+d*cos(a),d*sin(a),.14)
			beds.taper(base,.19,.12,.24+.05*sin(a),7,Color("#536d46"))
			beds.taper(base+Vector3.UP*.23,.105,.075,.10,7,Color(["#d2a597","#d6bd78","#a094ba"][i%3]))
	beds.attach(planting)

func _playground() -> void:
	var g=Forms.new()
	# A low timber climbing tower, metal chute and rope swing share the safety surface.
	for i in 40:
		var a:=TAU*i/40
		var b:=TAU*(i+1)/40
		g.triangle(_p(0,0,.045),_arc(3.32,a,.045),_arc(3.32,b,.045),Color("#bd966e"),Vector3.UP)
	var deck:=_p(-1.15,-.48,.08)
	for x in [-.68,.68]:
		for z in [-.66,.66]:
			g.box(deck+Vector3(x,1.25,z),Vector3(.13,2.5,.13),WOOD)
	g.box(deck+Vector3.UP*1.1,Vector3(1.54,.12,1.48),WOOD)
	for x in [-.68,.68]:
		g.box(deck+Vector3(x,1.63,0),Vector3(.09,.10,1.38),FRAME)
		for z in [-.42,0.,.42]:
			g.box(deck+Vector3(x,1.41,z),Vector3(.055,.45,.055),WOOD)
	var eave:=deck+Vector3.UP*2.38
	var tip:=eave+Vector3.UP*.65
	for i in 4:
		var a:=Vector3(-.94 if i in [0,3] else .94,0,-.94 if i<2 else .94)
		var b:=a.rotated(Vector3.UP,-PI*.5)
		g.triangle(eave+a,eave+b,tip,Color("#ad654b"),Vector3.UP)
	for x in [-.53,.53]:
		g.beam(deck+Vector3(x,.04,1.64),deck+Vector3(x,1.18,.68),.09,FRAME)
	for i in 5:
		var t:float=i/5.
		g.box(deck+Vector3(0,.13+t*1.10,1.60-t*.96),Vector3(1.02,.09,.15),WOOD)
	var end:=deck+Vector3(0,1.15,-.64)
	for i in 9:
		var t:float=(i+1)/9.
		var next:=deck+Vector3(0,1.15-.98*smoothstep(0.,.93,t),-.64-t*1.92)
		g.quad(end+Vector3.LEFT*.40,end+Vector3.RIGHT*.40,next+Vector3.RIGHT*.40,next+Vector3.LEFT*.40,Color("#a6bcbd"),Vector3.UP)
		for side in [-1.,1.]:
			g.beam(end+Vector3(side*.40,.07,0),next+Vector3(side*.40,.07,0),.105,Color("#467a76"))
		end=next
	var swing:=_p(1.33,.62,.06)
	for end_x in [-.95,.95]:
		for z in [-.83,.83]:
			g.beam(swing+Vector3(end_x,0,z),swing+Vector3(end_x,2.42,0),.12,WOOD)
	g.beam(swing+Vector3(-1.11,2.42,0),swing+Vector3(1.11,2.42,0),.16,FRAME)
	for x in [-.31,.31]:
		g.beam(swing+Vector3(x,2.38,0),swing+Vector3(x,.55,0),.029,FRAME)
	g.box(swing+Vector3.UP*.51,Vector3(.73,.08,.32),Color("#42565d"))
	g.attach(fittings)

func advance(time:float) -> void:
	var p:=clampf((time-data.started)/(data.opens-data.started),0.,1.)
	turf.set_instance_shader_parameter("workfront",Vector4(0.,1.,0.,lerpf(-data.radius-18.,data.radius+.2,smoothstep(0.,.68,p))) if p<1. else Vector4(0,0,0,2))
	fittings.scale.y=maxf(.001,smoothstep(.42,.86,p))
	planting.scale.y=maxf(.001,smoothstep(.62,1.,p))
	fittings.visible=p>.42
	planting.visible=p>.62
