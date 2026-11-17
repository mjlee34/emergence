extends "res://scripts/green_space.gd"

const LIMESTONE:=Color("#c8c0ae")
const GLASS:=Color("#526c75")
const Landmark=preload("res://scripts/landmark.gd")
const BRICK:=Color("#b17d63")
const BLUE:=Color("#526b84")

var monument_height:=0.
var visible_monument_height:=0.
var monument:MeshInstance3D
var clock_hands:Array[MeshInstance3D]=[]
var clock_minute:=-1

func setup(sim,land,site:Dictionary,canopy:Mesh) -> void:
	model=sim
	data=site
	position=data.pos
	rotation.y=data.yaw
	land.clear_street(PackedVector3Array([position,position+Vector3.RIGHT*.01]),data.radius+1.)
	land.clear_street(PackedVector3Array([data.curb,data.gate]),1.25)
	add_child(fittings)
	add_child(planting)
	var court=Forms.new(true)
	court.finish=Forms.Finish.WALK
	var r:float=data.radius
	var edge:=PackedVector2Array()
	if data.kind<=5:
		# A clipped rectangular parcel leaves planting pockets at the corners.
		for v in [Vector2(-.62,-.76),Vector2(.62,-.76),Vector2(.82,-.50),Vector2(.82,.48),Vector2(.62,.72),Vector2(-.62,.72),Vector2(-.82,.48),Vector2(-.82,-.50)]:
			edge.append(v*r)
	else:
		for i in 40:
			edge.append(Vector2(sin(TAU*i/40.),-cos(TAU*i/40.))*r)
	for i in edge.size():
		var a:=edge[i]
		var b:=edge[(i+1)%edge.size()]
		court.triangle(_p(0,0),_p(a.x,a.y),_p(b.x,b.y),LIMESTONE,Vector3.UP)
		court.quad(_p(a.x,a.y),_p(b.x,b.y),_p(b.x,b.y,-.38),_p(a.x,a.y,-.38),STONE,Vector3.UP)
	if data.kind>=6:
		for i in 80:
			var a:=TAU*i/80.
			var b:=TAU*(i+1)/80.
			for ring in [.87,.95]:
				var inner:float=ring*r
				court.quad(_arc(inner,a,.07),_arc(inner+.22,a,.07),_arc(inner+.22,b,.07),_arc(inner,b,.07),Color("#857969"),Vector3.UP)
	var curb:=to_local(data.curb)
	var half_width:=2.35 if data.kind in [3,4,5] else 1.2
	var entry:float=-r*.75 if data.kind<=5 else -r+.2
	court.quad(_p(-half_width,curb.z,.03),_p(half_width,curb.z,.03),_p(half_width,entry,.03),_p(-half_width,entry,.03),LIMESTONE,Vector3.UP)
	turf=court.attach(self)
	var g=Forms.new(true)
	match int(data.kind):
		2: _school(g)
		3: _hospital(g)
		4: _fire_station(g)
		5: _police_station(g)
		6,7: Landmark.build(g,data)
	if data.kind<=5:
		for side in [-1.,1.]:
			var x:float=side*(r*.64)
			g.box(Vector3(x,.18,-1.9),Vector3(.95,.36,3.1),LIMESTONE)
			for n in 5:
				g.taper(Vector3(x,.36,-3.+n*.56),.46,.33,.54+(n%2)*.12,8,Color("#597456"))
	var structure=g.attach(fittings)
	structure.position.y=_p(0,0).y
	if data.kind>=6:
		monument=structure
		if data.model=="lattice": structure.scale=Vector3(3.4,4.6,3.4)
		elif data.model=="liberty": structure.scale=Vector3.ONE*6.6
		structure.scale.y*=data.height_scale
	# Orient the waterfront facade toward the same open water used in the survey.
	if data.kind==7:
		var shore:=Vector2.ZERO
		for i in 12:
			var a:=i*TAU/12.
			var dir:=Vector2(sin(a),cos(a))
			var p:=Vector2(position.x,position.z)+dir*46.
			if model.inland_water(p.x,p.y) or model.height_at(p.x,p.y)<=model.sea_level():
				shore+=dir
		if shore.length()>.1: structure.rotation.y=atan2(-shore.x,-shore.y)-rotation.y
	if monument: _seat_monument()
	if data.get("model","")=="clock": _make_hands()
	if data.kind in [3,4,5]: _vehicle()
	if data.kind<=5:
		_tree(canopy,-r*.76,r*.39,.82)
		_sign(["COMMUNITY SCHOOL","HOSPITAL","FIRE STATION","POLICE"][data.kind-2],Vector3(0,2.67,-3.72))
	else:
		_plaza_gardens(canopy)
		for side in [-1,1]:
			_bench(side*r*.76,-1.,side*-PI*.5)

# Break up the stone forecourt without closing the promenade used by visitors.
func _plaza_gardens(canopy:Mesh) -> void:
	var garden=Forms.new(true)
	var r:float=data.radius
	var sectors:=6 if data.model in ["orbit","lantern"] else 4
	for i in sectors:
		var middle:=TAU*(i+.5)/sectors
		var span:=TAU/sectors*.31
		for j in 10:
			var a:=middle-span+2.*span*j/10.
			var b:=middle-span+2.*span*(j+1)/10.
			garden.finish=Forms.Finish.MEADOW
			garden.quad(_arc(r*.83,a,.11),_arc(r*.83,b,.11),_arc(r*.88,b,.11),_arc(r*.88,a,.11),Color("#74846a"),Vector3.UP)
			garden.finish=Forms.Finish.PLAIN
			garden.beam(_arc(r*.83,a,.12),_arc(r*.83,b,.12),.16,LIMESTONE.darkened(.22))
		if data.model not in ["liberty","lattice"]:
			_tree(canopy,sin(middle)*r*.854,-cos(middle)*r*.854,.80)
	garden.attach(planting)

func advance(time:float) -> void:
	super.advance(time)
	if not monument: return
	var p:=smoothstep(data.started,data.opens,time)
	var built:=smoothstep(.28,.97,p)
	fittings.scale.y=1.
	fittings.visible=p>.20
	var local_height:=monument.get_aabb().end.y*built
	monument.set_instance_shader_parameter("built_height",local_height+.001)
	visible_monument_height=monument.position.y+local_height*monument.scale.y
	for hand in clock_hands: hand.visible=local_height>=76.

func _seat_monument() -> void:
	var feet:Array[Vector2]=[Vector2.ZERO]
	var width:float={"clock":17.5,"orbit":20.,"lantern":18.,"arch":6.0}.get(data.model,5.2*monument.scale.x)
	if data.model=="arch": feet.assign([Vector2(-18.,0),Vector2(18.,0)])
	if data.model=="lattice":
		width=2.05*monument.scale.x
		feet.clear()
		for x in [-5.15,5.15]:
			for z in [-5.15,5.15]:
				feet.append(Vector2(x,z)*monument.scale.x)
	var floors:Array[float]=[]
	var top:=monument.position.y
	for foot in feet:
		var floor_y:=top
		for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1),Vector2.ZERO]:
			var q:Vector2=(foot+corner*width*.5).rotated(-monument.rotation.y)
			var ground:=_p(q.x,q.y).y
			floor_y=minf(floor_y,ground)
			top=maxf(top,ground)
		floors.append(floor_y-.8)
	var foundation=Forms.new(true)
	for i in feet.size():
		var depth:=top-floors[i]
		foundation.box(Vector3(feet[i].x,top-depth*.5,feet[i].y),Vector3(width,depth,width),LIMESTONE)
	foundation.attach(fittings).rotation.y=monument.rotation.y
	monument.position.y=top
	monument_height=top+monument.get_aabb().end.y*monument.scale.y

func _make_hands() -> void:
	for dial in 4:
		var face:=Node3D.new()
		monument.add_child(face)
		face.rotation.y=dial*PI*.5
		face.position=Vector3.UP*72.2+Vector3.BACK.rotated(Vector3.UP,face.rotation.y)*7.79
		for length:float in [1.85,2.95]:
			var g=Forms.new(true)
			g.box(Vector3.UP*(length*.43),Vector3(.21,length,.10),Color("#323535"))
			clock_hands.append(g.attach(face))
	set_clock(0)

func set_clock(minute:int) -> void:
	if clock_minute==minute: return
	clock_minute=minute
	for i in clock_hands.size():
		var period:=720. if i%2==0 else 60.
		clock_hands[i].rotation.z=-TAU*minute/period

func _sign(caption:String,at:Vector3) -> void:
	var label:=Label3D.new()
	label.text=caption
	label.pixel_size=.005
	label.font_size=56
	label.outline_size=0
	label.modulate=Color("#f5efdb")
	label.position=at+Vector3.UP*_p(0,0).y
	label.rotation.y=PI
	fittings.add_child(label)

func _block(g,center:Vector3,size:Vector3,shade:Color,finish:int) -> void:
	g.finish=finish
	g.box(center,size,shade)

func _windows(g,width:float,z:float,rows:int) -> void:
	for level in rows:
		for bay in 6:
			var x:float=width*((bay+.5)/6.-.5)
			_block(g,Vector3(x,1.55+2.65*level,z),Vector3(width/6.-.32,1.44,.10),GLASS,Forms.Finish.GLASS)
			_block(g,Vector3(x,1.55+2.65*level,z-.06),Vector3(.07,1.5,.09),LIMESTONE,Forms.Finish.PLAIN)

func _entrance(g,accent:Color) -> void:
	_block(g,Vector3(0,1.18,-3.25),Vector3(2.6,2.36,.65),GLASS,Forms.Finish.GLASS)
	_block(g,Vector3(0,2.66,-3.31),Vector3(4.8,.60,.76),accent,Forms.Finish.PLAIN)
	for x in [-2.12,2.12]:
		g.box(Vector3(x,1.16,-3.50),Vector3(.14,2.34,.14),LIMESTONE)

func _school(g) -> void:
	_block(g,Vector3(0,2.75,.15),Vector3(10.1,5.5,6.2),BRICK,Forms.Finish.BRICK)
	_windows(g,9.9,-3.0,2)
	_block(g,Vector3(0,5.52,.15),Vector3(10.6,.24,6.7),LIMESTONE,Forms.Finish.PLAIN)
	for side in [-1.,1.]:
		var z:float=.15+side*3.32
		g.quad(Vector3(-5.27,5.64,z),Vector3(5.27,5.64,z),Vector3(5.27,7.,.15),Vector3(-5.27,7.,.15),Color("#677575"),Vector3.UP)
	_entrance(g,Color("#5e7166"))
	# Painted hopscotch lanes in the forecourt.
	for i in 6:
		var x:float=-3.6+(i%2)*.49
		g.box(Vector3(x,.09,-3.75-floori(i/2.)*.58),Vector3(.44,.03,.48),Color("#d4ab78") if i%2 else Color("#a9c4b7"))

func _hospital(g) -> void:
	_block(g,Vector3(0,4.20,.55),Vector3(10.2,8.4,7.0),Color("#d9d5c6"),Forms.Finish.PLASTER)
	_windows(g,10.,-3.,3)
	for level in 3:
		g.box(Vector3(0,2.49+2.65*level,.55),Vector3(10.45,.22,7.25),LIMESTONE)
	_block(g,Vector3(0,8.55,.55),Vector3(10.65,.30,7.45),Color("#859497"),Forms.Finish.METAL)
	g.box(Vector3(2.5,9.02,1.9),Vector3(2.2,.8,1.7),STONE)
	_entrance(g,Color("#367b79"))
	for dims in [Vector3(1.45,.44,.15),Vector3(.44,1.45,.16)]:
		_block(g,Vector3(0,7.9,-3.02),dims,Color("#5caaa1"),Forms.Finish.PLAIN)

func _fire_station(g) -> void:
	_block(g,Vector3(0,2.1,.1),Vector3(9.3,4.2,6.1),Color("#ae6c52"),Forms.Finish.BRICK)
	_block(g,Vector3(0,4.25,.1),Vector3(9.55,.20,6.36),Color("#7d8583"),Forms.Finish.FELT)
	for x in [-2.28,2.28]:
		_block(g,Vector3(x,1.4,-3.02),Vector3(3.3,2.8,.13),Color("#834b40"),Forms.Finish.METAL)
		for strip in 6:
			g.box(Vector3(x,.25+strip*.43,-3.105),Vector3(3.15,.07,.06),STONE)
		g.box(Vector3(x,2.05,-3.13),Vector3(2.95,.46,.07),GLASS)
	_block(g,Vector3(0,2.67,-3.46),Vector3(4.4,.58,.45),Color("#854738"),Forms.Finish.PLAIN)
	_block(g,Vector3(3.23,4.7,1.65),Vector3(2.65,9.4,2.65),BRICK,Forms.Finish.BRICK)
	for i in 4:
		_block(g,Vector3(3.23,5.28+i*.90,.28),Vector3(1.6,.38,.10),FRAME,Forms.Finish.PLAIN)
	g.box(Vector3(3.23,9.48,1.65),Vector3(2.98,.24,2.98),LIMESTONE)

func _police_station(g) -> void:
	_block(g,Vector3(0,2.9,.15),Vector3(8.7,5.8,6.2),Color("#b8bbba"),Forms.Finish.PLASTER)
	_windows(g,8.55,-3.0,2)
	_entrance(g,BLUE)
	_block(g,Vector3(0,5.98,.15),Vector3(9.2,.43,6.65),BLUE,Forms.Finish.METAL)
	g.beam(Vector3(2.7,6.0,1.6),Vector3(2.7,9.4,1.6),.10,FRAME)
	g.beam(Vector3(2.15,8.7,1.6),Vector3(3.25,8.7,1.6),.07,FRAME)

var vehicle:MeshInstance3D
var beacons:Node3D
var on_call:=false

func _vehicle() -> void:
	var g=Forms.new(true)
	var shade:Color={3:Color("#ede7d8"),4:Color("#b94432"),5:Color("#ecede6")}[data.kind]
	var stripe:Color={3:Color("#468c84"),4:Color("#dbc388"),5:BLUE}[data.kind]
	var length:=4.8 if data.kind==4 else 4.1
	g.box(Vector3(0,.60,0),Vector3(length,.57,1.57),FRAME)
	g.box(Vector3(0,1.02,0),Vector3(length, .75,1.75),shade)
	for side in [-1,1]:
		g.box(Vector3(0,1.09,side*.89),Vector3(length-.07,.24,.08),stripe)
		for x in [-length*.31,length*.30]: g.wheel(Vector3(x,.41,side*.82),.37,side)
	var cab:=Vector3(.73,1.63,0)
	g.box(cab,Vector3(1.52,.59,1.56),GLASS)
	g.box(cab+Vector3.UP*.33,Vector3(1.55,.11,1.67),shade)
	if data.kind!=5:
		g.box(Vector3(-.85,1.70,0),Vector3(2.24,.96,1.74),shade)
	if data.kind==4:
		for side in [-1.,1.]: g.box(Vector3(-.70,2.32,.43*side),Vector3(2.69,.09,.08),LIMESTONE)
		for i in 8: g.box(Vector3(-1.96+i*.35,2.32,0),Vector3(.07,.09,.89),LIMESTONE)
	for side in [-1.,1.]:
		g.box(Vector3(length*.50,1.12,.57*side),Vector3(.06,.19,.31),Color("#ffefc5"))
	vehicle=g.attach(fittings)
	var lights=Forms.new(true)
	lights.finish=Forms.Finish.LAMP
	for side in [-1.,1.]:
		lights.box(Vector3(.78,2.08,.38*side),Vector3(.32,.16,.40),Color("#78accd") if side>0 else Color("#b94f46"))
	beacons=lights.attach(vehicle)
	move_responder({},0.)

func move_responder(call:Dictionary,time:float) -> void:
	on_call=not call.is_empty()
	if on_call:
		vehicle.global_position=call.position
		vehicle.global_rotation=Vector3(0,call.yaw,0)
	else:
		vehicle.position=_p(1.85,-5.12,.06)
		vehicle.rotation=Vector3.ZERO
	beacons.visible=on_call and fmod(time,4.)<2.
