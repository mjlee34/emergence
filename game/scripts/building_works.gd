extends Node3D
const Architecture=preload("res://scripts/urban_architecture.gd")
const Forms=preload("res://scripts/forms.gd")
const STEEL=Color("#747b77")
const CONCRETE=Color("#aaa998")
const CRANE=Color("#d3a54f")
var building:MeshInstance3D
var old:MeshInstance3D
var frame:MeshInstance3D
var yard:MeshInstance3D
var mast:Node3D
var jib:MeshInstance3D
var trolley:Node3D
var cable:MeshInstance3D
var load_hook:MeshInstance3D
var started:int
var height:float
var deck_height:float
var progress:=0.
var phase_offset:float

func setup(lot:Dictionary,finished:MeshInstance3D,previous:MeshInstance3D) -> void:
	building=finished
	old=previous
	started=lot.started
	phase_offset=lot.style*.71
	position=lot.pos
	rotation.y=lot.yaw
	height=building.get_aabb().end.y
	var w:=7.2+int(lot.style%4)*.62+2.*float(lot.wing)
	var d:=5.8+int(lot.style%5)*.47+float(lot.depth_extension)
	var floors:int=lot.floors if lot.use!=2 else 1
	var floor_height:=2.65
	if floors>=4: floor_height=Architecture.storey(lot)
	elif Architecture.masonry_house(lot) or Architecture.row_house(lot): floor_height=3.05
	deck_height=4.3 if lot.use==2 else floors*floor_height
	var frame_forms=Forms.new(true)
	frame_forms.box(Vector3(0,.17,0),Vector3(w+.30,.29,d+.30),CONCRETE)
	for floor_id in floors:
		var y:float=(floor_id+1)*deck_height/floors
		frame_forms.box(Vector3(0,y-.10,0),Vector3(w-.10,.20,d-.10),CONCRETE)
	for x in [-.47,0,.47]:
		for z in [-.46,.46]:
			frame_forms.box(Vector3(x*w,deck_height*.5,z*d),Vector3(.23,deck_height,.23),STEEL)
	frame=frame_forms.attach(self)
	var pad=Forms.new(true)
	pad.box(Vector3(0,.09,0),Vector3(w+1.45,.20,d+1.52),Color("#927b5c"))
	for side in [-1,1]:
		for k in 4:
			var x:float=(k-1.5)*(w+.72)*.25
			var z:float=side*(d*.5+.70)
			pad.box(Vector3(x,.60,z),Vector3(w*.24,.15,.12),CRANE)
			pad.box(Vector3(x-w*.113,.46,z),Vector3(.07,.91,.08),STEEL)
	yard=pad.attach(self)
	_make_crane(w,d,maxf(7.3,deck_height+3.4))

func _make_crane(w:float,d:float,top:float) -> void:
	mast=Node3D.new()
	add_child(mast)
	mast.position=Vector3(-w*.50-.50,.2,-d*.26)
	var g=Forms.new()
	g.box(Vector3(0,.29,0),Vector3(1.53,.55,1.49),CONCRETE)
	for x in [-.32,.32]:
		for z in [-.32,.32]:
			g.box(Vector3(x,top*.5,z),Vector3(.10,top,.10),CRANE)
	var bays:=ceili(top/1.28)
	for i in bays:
		var y:=top*i/bays
		var end:=top*(i+1)/bays
		for side in [-1,1]:
			var x:float=.32 if i%2 else -.32
			g.beam(Vector3(x,y,side*.32),Vector3(-x,end,side*.32),.063,CRANE)
			g.beam(Vector3(side*.32,y,x),Vector3(side*.32,end,-x),.063,CRANE)
	g.attach(mast)
	var boom=Forms.new()
	boom.box(Vector3(0,.32,0),Vector3(1.0,.63,.95),STEEL)
	boom.box(Vector3(.48,.80,.34),Vector3(1.03,1.08,.79),Color("#4b6162"))
	for z in [-.27,.27]:
		boom.beam(Vector3(-2.6,.86,z),Vector3(w+.4,.86,z),.12,CRANE)
	boom.beam(Vector3(-2.60,1.42,0),Vector3(w+.4,1.42,0),.11,CRANE)
	for i in range(-2,ceili(w)):
		for side in [-1,1]:
			boom.beam(Vector3(i,.86,side*.27),Vector3(i+.51,1.42,0),.065,CRANE)
			boom.beam(Vector3(i+.51,1.42,0),Vector3(i+1,.86,side*.27),.065,CRANE)
	boom.box(Vector3(-2.12,.76,0),Vector3(1.14,1.20,.88),CONCRETE)
	jib=boom.attach(mast)
	jib.position.y=top
	trolley=Node3D.new()
	jib.add_child(trolley)
	var line=Forms.new()
	line.box(Vector3(0,-.5,0),Vector3(.035,1.,.035),STEEL.darkened(.5))
	cable=line.attach(trolley)
	var hook=Forms.new()
	hook.box(Vector3.ZERO,Vector3(.22,.28,.20),CRANE)
	for side in [-1,1]:
		hook.beam(Vector3.ZERO,Vector3(side*.72,-.43,0),.036,STEEL)
	hook.box(Vector3(0,-.53,0),Vector3(1.75,.20,.53),Color("#9d8565"))
	load_hook=hook.attach(trolley)

static func visible_bounds(site:MeshInstance3D) -> AABB:
	var bounds:=site.get_aabb()
	if site.has_meta("visible_height"):
		bounds.size.y=maxf(0.,float(site.get_meta("visible_height"))-bounds.position.y)
	return bounds

func advance(time:float,duration:int) -> bool:
	progress=clampf((time-started)/duration,0,1)
	var p:=progress
	if is_instance_valid(old):
		var remaining:=1.-smoothstep(.0,.23,p)
		old.set_instance_shader_parameter("built_height",lerpf(-.4,old.get_aabb().end.y+.1,remaining))
		for child in old.get_children(): child.visible=p<.055
		old.visible=p<.23
	var prep:=.18 if is_instance_valid(old) else .025
	var structure:=smoothstep(prep,.83,p)
	var shell:=smoothstep(prep+.13,.97,p)
	var limit:=lerpf(-.6,height+.08,shell)
	building.set_instance_shader_parameter("built_height",limit)
	var visible_height:=maxf(limit,deck_height*structure)
	if is_instance_valid(old) and old.visible:
		visible_height=maxf(visible_height,float(old.get_instance_shader_parameter("built_height")))
	building.set_meta("visible_height",visible_height)
	for child in building.get_children():
		child.visible=p>.93
	frame.set_instance_shader_parameter("built_height",lerpf(-.05,deck_height+.05,structure))
	frame.visible=p>=prep and p<.97
	yard.visible=p<.97
	yard.scale=Vector3.ONE*maxf(.01,smoothstep(0,.05,p))
	var lift:=smoothstep(.0,.14,p)*(1.-smoothstep(.88,1.,p))
	mast.scale.y=maxf(.001,lift)
	jib.rotation.y=.28+.98*sin(phase_offset+p*TAU*1.6)
	trolley.position=Vector3(3.4+2.3*sin(phase_offset+p*TAU*3.),.8,0)
	var drop:=lerpf(1.0,maxf(1.4,jib.position.y-deck_height*structure-.85),.5+.45*cos(p*TAU*5.))
	cable.scale.y=drop
	load_hook.position.y=-drop
	if p<1: return false
	building.set_instance_shader_parameter("built_height",10000.)
	building.remove_meta("visible_height")
	if is_instance_valid(old): old.queue_free()
	return true
