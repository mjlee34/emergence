extends Node3D
const Forms=preload("res://scripts/forms.gd")
const TEAL=Color("#197f75")
const CREAM=Color("#f1ddac")
var truck_mesh:Mesh
var porter_mesh:Mesh
var trucks:Dictionary={}
var anchors:Dictionary={}
var stacks:Array[MultiMesh]=[]
var tag:=Label3D.new()
var stock_revision:=-1

func _ready() -> void:
	var g=Forms.new()
	g.box(Vector3(0,.53,0),Vector3(4.35,.38,1.68),Color("#39494a"))
	g.box(Vector3(-.66,1.43,0),Vector3(3.06,1.72,1.81),CREAM)
	g.box(Vector3(-.66,1.19,0),Vector3(3.1,.52,1.84),TEAL)
	g.box(Vector3(-.66,2.34,0),Vector3(3.14,.16,1.93),TEAL)
	g.box(Vector3(1.53,.96,0),Vector3(1.44,.83,1.70),TEAL)
	g.box(Vector3(1.39,1.61,0),Vector3(1.04,.60,1.56),Color("#49686b"))
	g.box(Vector3(1.37,1.95,0),Vector3(1.16,.12,1.69),CREAM)
	for side in [-1,1]:
		g.box(Vector3(2.26,1.06,side*.53),Vector3(.08,.23,.35),Color("#fff1c4"))
		g.box(Vector3(-2.22,.89,side*.7),Vector3(.08,.20,.17),Color("#ce6048"))
		for x in [-1.34,1.47]:
			g.wheel(Vector3(x,.43,side*.80),.38,side)
	truck_mesh=g.mesh()
	var porter=Forms.new()
	porter.box(Vector3(-.16,.39,.14),Vector3(.22,.62,.22),Color("#3c4f59"))
	porter.box(Vector3(.10,.39,-.13),Vector3(.22,.62,.22),Color("#3c4f59"))
	porter.box(Vector3(0,1.02,0),Vector3(.49,.70,.32),TEAL)
	porter.taper(Vector3(0,1.38,0),.19,.19,.34,8,Color("#bc8c68"))
	porter.box(Vector3(0,1.76,.04),Vector3(.47,.12,.44),CREAM)
	for side in [-1,1]:
		porter.box(Vector3(side*.26,1.08,.18),Vector3(.14,.18,.45),TEAL)
	porter.box(Vector3(0,1.02,.4),Vector3(.63,.49,.47),Color("#c58c53"))
	porter.box(Vector3(0,1.04,.4),Vector3(.12,.51,.49),CREAM)
	porter_mesh=porter.mesh()
	for kind in 3:
		var box=Forms.new()
		if kind==2:
			box.box(Vector3(0,.4,0),Vector3(.97,.77,.8),Color("#bb8d5f"))
			box.box(Vector3(0,.4,0),Vector3(.16,.80,.82),CREAM)
		else:
			box.box(Vector3(0,.26,0),Vector3(.97,.5,.74),Color("#a0744d"))
			for side in [-1,1]:
				box.box(Vector3(0,.47,side*.36),Vector3(1.03,.10,.08),CREAM)
			for n in 6:
				var fruit:=Color(["#cd714c","#d4ad54","#92a953"][n%3])
				var spot:=Vector3((n%3-1)*.29,.47,(n/3-.5)*.29)
				if kind==0:
					box.taper(spot,.16,.13,.19,6,fruit)
				else:
					box.box(spot+Vector3.UP*.10,Vector3(.26,.22,.27),Color("#6f999f") if n%2 else Color("#cf976f"))
		var mm:=MultiMesh.new()
		mm.transform_format=MultiMesh.TRANSFORM_3D
		mm.mesh=box.mesh()
		var node:=MultiMeshInstance3D.new()
		node.multimesh=mm
		add_child(node)
		stacks.append(mm)
	tag.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size=34
	tag.pixel_size=.015
	tag.outline_size=8
	tag.modulate=Color("#fff2bf")
	tag.outline_modulate=Color("#194743")
	tag.no_depth_test=true
	add_child(tag)

func _van(id:int) -> Dictionary:
	if trucks.has(id): return trucks[id]
	var body:=MeshInstance3D.new()
	body.mesh=truck_mesh
	add_child(body)
	for side in [-1,1]:
		var lettering:=Label3D.new()
		lettering.text="ALDER  FREIGHT"
		lettering.font_size=34
		lettering.pixel_size=.0061
		lettering.modulate=Color("#214c49")
		lettering.outline_size=0
		lettering.position=Vector3(-.66,1.78,side*.916)
		if side<0: lettering.rotation.y=PI
		body.add_child(lettering)
	var porter:=MeshInstance3D.new()
	porter.mesh=porter_mesh
	add_child(porter)
	trucks[id]={"body":body,"porter":porter}
	return trucks[id]

func _anchor(model,id:int) -> Dictionary:
	if anchors.has(id): return anchors[id]
	var b:Dictionary=model.lot(id)
	var basis:=Basis(Vector3.UP,b.yaw)
	var depth:=5.8+(int(b.style)%5)*.47
	var front:Vector3=b.pos+basis*Vector3(0,0,(depth*.5+1.15)*int(b.front_sign))
	anchors[id]={"front":front,"basis":basis,"side":b.front_sign,"use":b.use,"kind":2 if b.use==2 else int(int(b.style)%4==3)}
	return anchors[id]

func _inventory(model,state:Dictionary) -> void:
	if stock_revision==state.stock_revision: return
	stock_revision=state.stock_revision
	var poses:=[[],[],[]]
	for id in state.stocks.size():
		var stock:int=state.stocks[id]
		if stock<=0: continue
		var a:=_anchor(model,id)
		var n:=mini(9,ceili(stock/(12. if a.use==2 else 8.)))
		for slot in n:
			var offset:=Vector3(-3.2+slot%3*1.01,(slot/3)*(.79 if a.use==2 else .62)+.34,0)
			var pos:Vector3=a.front+a.basis*offset
			poses[a.kind].append(Transform3D(a.basis,pos))
	for kind in 3:
		var m:=stacks[kind]
		if m.instance_count<poses[kind].size(): m.instance_count=poses[kind].size()
		m.visible_instance_count=poses[kind].size()
		for i in poses[kind].size(): m.set_instance_transform(i,poses[kind][i])

func sync(model,state:Dictionary,freight:Array,fraction:float,follow:int,site:int) -> void:
	_inventory(model,state)
	var live:Dictionary={}
	var time:float=state.tick+fraction
	tag.visible=false
	for row in freight:
		var d:Dictionary=row
		var node:=_van(d.id)
		live[d.id]=true
		node.body.position=d.position
		node.body.rotation.y=d.yaw
		var loading:bool=time<d.start+20
		var unloading:bool=time>=d.arrival
		node.porter.visible=loading or unloading
		if node.porter.visible:
			var door:Vector3=_anchor(model,d.source if loading else d.shop).front
			var back:Vector3=node.body.to_global(Vector3(-2.55,0,0))
			var phase:float=(time-d.start)/20. if loading else (time-d.arrival)/float(d.end-d.arrival)
			var f:=.5-.5*cos(TAU*phase*2)
			var p:Vector3=back.lerp(door,f)
			p.y=model.height_at(p.x,p.z)+.31
			node.porter.position=p
			var dir:Vector3=door-back
			node.porter.rotation.y=atan2(dir.x,dir.z)+(PI if sin(TAU*phase*2)<0 else 0.)
		if d.id==follow:
			tag.text="Loading %d units"%d.units if loading else ("Unloading %d units"%d.units if unloading else "Delivery %03d"%d.id)
			tag.position=d.position+Vector3.UP*3.25
			tag.visible=true
	for id in trucks.keys():
		if live.has(id): continue
		trucks[id].body.queue_free()
		trucks[id].porter.queue_free()
		trucks.erase(id)
	if follow<0 and site>=0:
		var b:Dictionary=model.business(site)
		if b.is_empty(): return
		var sale:bool=b.last_sale>=0 and b.last_sale>=b.last_delivery and time-b.last_sale<28
		var delivery:bool=b.last_delivery>=0 and time-b.last_delivery<32
		var produced:bool=b.last_batch>=0 and time-b.last_batch<24
		if sale or delivery or produced:
			tag.text="SALE   +$12" if sale else ("DELIVERY RECEIVED" if delivery else "BATCH PACKED")
			tag.position=_anchor(model,site).front+Vector3.UP*3.8
			tag.visible=true
