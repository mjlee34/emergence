extends "res://scripts/green_space.gd"

const LIMESTONE:=Color("#c8c0ae")
const GLASS:=Color("#526c75")
const IRON:=Color("#605750")
const COPPER:=Color("#79a398")
const BRICK:=Color("#b17d63")
const BLUE:=Color("#526b84")

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
		6: _tower(g)
		7: _statue(g)
	if data.kind<=5:
		for side in [-1.,1.]:
			var x:float=side*(r*.64)
			g.box(Vector3(x,.18,-1.9),Vector3(.95,.36,3.1),LIMESTONE)
			for n in 5:
				g.taper(Vector3(x,.36,-3.+n*.56),.46,.33,.54+(n%2)*.12,8,Color("#597456"))
	var structure=g.attach(fittings)
	structure.position.y=_p(0,0).y
	# Face the torch towards water where the terrain survey found it.
	if data.kind==7:
		var shore:=Vector2.ZERO
		for i in 12:
			var a:=i*TAU/12.
			var dir:=Vector2(sin(a),cos(a))
			var p:=Vector2(position.x,position.z)+dir*32.
			if model.inland_water(p.x,p.y) or model.height_at(p.x,p.y)<=model.sea_level():
				shore+=dir
		if shore.length()>.1: structure.rotation.y=atan2(-shore.x,-shore.y)-rotation.y
	if data.kind in [3,4,5]: _vehicle()
	if data.kind<=5:
		_tree(canopy,-r*.76,r*.39,.82)
		_sign(["COMMUNITY SCHOOL","HOSPITAL","FIRE STATION","POLICE"][data.kind-2],Vector3(0,2.67,-3.72))
	else:
		for side in [-1,1]:
			_bench(side*r*.76,-1.,side*-PI*.5)

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

func _tower(g) -> void:
	var levels:=[Vector2(0.,5.15),Vector2(4.,4.05),Vector2(8.,2.65),Vector2(12.,1.9),Vector2(17.,1.25),Vector2(23.,.77),Vector2(29.,.38)]
	var corners:=[Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]
	for corner:Vector2 in corners:
		g.box(Vector3(corner.x*5.15,.34,corner.y*5.15),Vector3(2.05,.68,2.05),LIMESTONE)
	g.finish=Forms.Finish.METAL
	for i in levels.size()-1:
		var lo:Vector2=levels[i]
		var hi:Vector2=levels[i+1]
		for j in 4:
			var a:Vector2=corners[j]
			var b:Vector2=corners[(j+1)%4]
			var p:=Vector3(a.x*lo.y,lo.x+.6,a.y*lo.y)
			var q:=Vector3(b.x*lo.y,lo.x+.6,b.y*lo.y)
			var u:=Vector3(a.x*hi.y,hi.x+.6,a.y*hi.y)
			var v:=Vector3(b.x*hi.y,hi.x+.6,b.y*hi.y)
			g.beam(p,u,.64/(1.+i*.23),IRON)
			g.beam(u,v,.23/(1.+i*.18),IRON)
			if i>0:
				g.beam(p,v,.16/(1.+i*.13),IRON)
				g.beam(q,u,.16/(1.+i*.13),IRON)
			else:
				var prev:=p
				for seg in range(1,13):
					var t:=seg/12.
					var arch:=p.lerp(q,t)+Vector3.UP*5.25*sqrt(maxf(0.,1.-pow(2.*t-1.,2)))
					g.beam(prev,arch,.26,IRON)
					prev=arch
	for deck in [Vector2(8.55,6.4),Vector2(17.5,3.65),Vector2(29.8,1.75)]:
		g.box(Vector3.UP*deck.x,Vector3(deck.y,.55,deck.y),IRON)
		for side in [-1.,1.]:
			g.box(Vector3(0,deck.x+.54,side*deck.y*.48),Vector3(deck.y,.10,.10),LIMESTONE)
			g.box(Vector3(side*deck.y*.48,deck.x+.54,0),Vector3(.10,.10,deck.y),LIMESTONE)
	g.taper(Vector3.UP*30.,.68,.14,2.2,12,IRON)
	g.taper(Vector3.UP*32.2,.11,.03,2.2,8,IRON)
	g.finish=Forms.Finish.LAMP
	g.taper(Vector3.UP*34.4,.11,.04,.24,8,LIMESTONE)

func _statue(g) -> void:
	for layer in [Vector3(6.8,.6,0),Vector3(5.8,.6,.6),Vector3(4.6,.5,1.2),Vector3(3.7,3.2,1.7),Vector3(4.4,.48,4.9)]:
		g.box(Vector3.UP*(layer.z+layer.y*.5),Vector3(layer.x,layer.y,layer.x),LIMESTONE)
	g.finish=Forms.Finish.METAL
	var base:=Vector3.UP*5.38
	g.profile(base,[Vector3(1.35,0,.94),Vector3(1.18,1.1,.84),Vector3(.75,3.45,.62),Vector3(.98,4.85,.64),Vector3(.40,5.25,.37)],COPPER,16)
	for i in 12:
		var a:=TAU*i/12.
		g.beam(base+Vector3(1.23*cos(a),.20,.88*sin(a)),base+Vector3(.78*cos(a+.63),4.6,.55*sin(a+.63)),.11,Color("#658e82"))
	g.profile(base+Vector3.UP*5.17,[Vector3(.27,0,.29),Vector3(.48,.25,.46),Vector3(.50,.82,.44),Vector3(.33,1.,.34)],COPPER,14)
	g.taper(base+Vector3.UP*5.97,.56,.46,.20,12,COPPER)
	for i in 7:
		var a:=TAU*i/7.
		g.beam(base+Vector3(.4*cos(a),6.08,.4*sin(a)),base+Vector3(.95*cos(a),6.68,.95*sin(a)),.12,COPPER)
	g.beam(base+Vector3(-.82,4.76,0),base+Vector3(-1.17,5.88,-.12),.54,COPPER)
	g.beam(base+Vector3(-1.17,5.88,-.12),base+Vector3(-1.23,7.14,-.14),.34,COPPER)
	var hand:=base+Vector3(-1.23,7.08,-.14)
	g.taper(hand,.18,.22,.66,10,IRON)
	g.taper(hand+Vector3.UP*.63,.20,.49,.31,10,COPPER)
	g.finish=Forms.Finish.LAMP
	g.taper(hand+Vector3.UP*.94,.32,.04,.87,9,Color("#d1ab64"))
	g.finish=Forms.Finish.METAL
	g.beam(base+Vector3(.83,4.82,0),base+Vector3(1.15,3.92,-.25),.48,COPPER)
	g.box(base+Vector3(.86,4.18,-.46),Vector3(.78,1.31,.27),Color("#68897d"))

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
