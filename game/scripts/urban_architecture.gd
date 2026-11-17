extends RefCounted
const Forms=preload("res://scripts/forms.gd")
const ROOF:=Color("#45494b")
const FLASHING:=Color("#777b7a")
const STONE:=Color("#aba69c")

static func masonry_house(lot:Dictionary) -> bool:
	return lot.floors in [2,3] and (lot.use==1 or lot.style%4!=0)

static func house_shell(g,lot:Dictionary,w:float,d:float,h:float) -> void:
	g.finish=Forms.Finish.BRICK_FRONT if (lot.style/5)%3==0 else Forms.Finish.LIMESTONE_FRONT
	g.box(Vector3.UP*h*.5,Vector3(w,h,d),Color("#e4e1dc"))
	g.finish=Forms.Finish.PLAIN
	var front:float=lot.front_sign*(d*.5+.04)
	g.box(Vector3(0,1.12,front),Vector3(1.22,2.25,.14),Color("#41464a"))
	g.box(Vector3(0,2.29,front),Vector3(1.42,.12,.21),STONE)

# Match the floor spacing in the four-storey facade maps.
static func finish(lot:Dictionary) -> int:
	var choice:int=lot.style%7
	if lot.use==0:
		return Forms.Finish.BRICK_FRONT if choice in [0,1,2] else Forms.Finish.LIMESTONE_FRONT
	if lot.floors<9 and choice<3: return Forms.Finish.LIMESTONE_FRONT
	return Forms.Finish.BRONZE_FRONT if choice in [1,4,5] else Forms.Finish.CURTAIN_WALL

static func storey(lot:Dictionary) -> float:
	return 3.55 if finish(lot)>=Forms.Finish.CURTAIN_WALL else 3.05

static func add(g,lot:Dictionary,w:float,d:float,nearby:bool) -> void:
	var s:int=lot.style
	var floors:int=lot.floors
	var facade:=finish(lot)
	var floor_height:=storey(lot)
	var height:=floor_height*floors
	var tint:Color=[Color("#e7e8e6"),Color("#dadcdd"),Color("#eeeae4"),Color("#d5d7d4")][(s/7)%4]
	var trim:=FLASHING if facade>=Forms.Finish.CURTAIN_WALL else STONE
	var width:=w+1.15
	var depth:=d+.58
	# Podium and tower share the same footprint at every level of detail.
	# Each subsequent mass sits on the previous volume's roof terrace.
	_section(g,Vector2.ZERO,width,depth,0.,floor_height,.38,facade,tint,trim)
	var center:=Vector2.ZERO
	var start:=floor_height
	var chamfer:=.22
	var form:int=(s/9)%4
	if form==1: chamfer=minf(width,depth)*.23
	if form==2: chamfer=minf(width,depth)*.12
	var tall:=floors>=9
	if form==0 or form==2 or (form==3 and tall):
		var split:=maxi(2,roundi(floors*(.61 if form==0 else .75)))*floor_height
		_section(g,center,width,depth,start,split,chamfer,facade,tint,trim)
		start=split
		var setback:=width*(.27 if form==0 else .17)
		width-=setback
		if form==0: center.x+=setback*.46*(1. if s%2 else -1.)
		else: depth*=.83
		if nearby and form==0:
			var terrace_x:=center.x-signf(center.x)*(width*.5+setback*.50)
			g.finish=Forms.Finish.PLAIN
			for end in [-1.,1.]:
				g.box(Vector3(terrace_x,split+.36,end*depth*.31),Vector3(setback*.52,.65,depth*.24),Color("#797c75"))
				g.box(Vector3(terrace_x,split+.88,end*depth*.31),Vector3(setback*.47,.48,depth*.23),Color("#52604c"))
	_section(g,center,width,depth,start,height,chamfer,facade,tint,trim)
	# Enclosed mechanical floors follow the roof outline of each family.
	var top:=Vector3(center.x,height,center.y)
	var plant:=Vector2(width*.47,depth*.39)
	var crown:=floor_height*.38
	g.finish=Forms.Finish.METAL
	if tall and form==1:
		# A folded zinc crown continues the chamfered glass shaft to a ridge.
		var ridge:=top+Vector3(width*.14,3.3,0.)
		for side in [-1.,1.]:
			var left:=top+Vector3(-width*.43,.10,side*depth*.40)
			var right:=top+Vector3(width*.43,.10,side*depth*.40)
			g.quad(left,right,ridge+Vector3(width*.21,0,0),ridge-Vector3(width*.21,0,0),trim,Vector3.UP)
			g.triangle(top+Vector3(side*width*.43,.10,-depth*.40),top+Vector3(side*width*.43,.10,depth*.40),ridge+Vector3(side*width*.21,0,0),trim,Vector3.RIGHT*side)
	elif tall and form==2:
		_section(g,center,width*.72,depth*.72,height,height+floor_height*.7,chamfer*.67,facade,tint,trim)
		g.finish=Forms.Finish.METAL
		g.taper(top+Vector3.UP*floor_height*.7,.19,.035,4.5,8,FLASHING)
	else:
		top+=Vector3(width*.14,0.,-depth*.12)
		g.box(top+Vector3.UP*(crown*.5+.12),Vector3(plant.x,crown,plant.y),Color("#636b6b"))
		if nearby:
			g.finish=Forms.Finish.PLAIN
			for row in 4:
				g.box(top+Vector3(0,.25+row*crown*.18,plant.y*.5+.01),Vector3(plant.x*.79,.065,.045),ROOF)
	if nearby and lot.use==1 and form in [0,3]:
		g.finish=Forms.Finish.METAL
		for side in [-1.,1.]:
			for bay in [-.29,0.,.29]:
				g.box(Vector3(center.x+width*bay,(height+start)*.5,center.y+side*(depth*.5+.09)),Vector3(.10,height-start,.22),trim)
	if nearby and lot.use==0 and form==3:
		g.finish=Forms.Finish.PLAIN
		var sign_z:float=lot.front_sign
		for level in range(1,floors-1):
			var y:=level*floor_height+.15
			var bz:=sign_z*(depth*.5+.34)
			var bx:=center.x+width*.17
			g.box(Vector3(bx,y,bz),Vector3(width*.45,.17,.83),trim)
			g.box(Vector3(bx,y+.61,bz+.38*sign_z),Vector3(width*.43,.84,.07),Color("#778584"))
			g.box(Vector3(bx,y+1.05,bz+.38*sign_z),Vector3(width*.46,.07,.10),ROOF)

static func _section(g,center:Vector2,w:float,d:float,bottom:float,top:float,cut:float,facade:int,tint:Color,trim:Color) -> void:
	var x:=w*.5
	var z:=d*.5
	var edge:=PackedVector2Array([Vector2(-x+cut,-z),Vector2(x-cut,-z),Vector2(x,-z+cut),Vector2(x,z-cut),
		Vector2(x-cut,z),Vector2(-x+cut,z),Vector2(-x,z-cut),Vector2(-x,-z+cut)])
	for i in edge.size():
		var a:=edge[i]+center
		var b:=edge[(i+1)%edge.size()]+center
		var outward:=Vector3(b.y-a.y,0.,a.x-b.x)
		var hi:=Vector3(a.x,top,a.y)
		var end:=Vector3(b.x,top,b.y)
		# End on a mullion at both corners, including the beveled faces.
		var span:=b-a
		var bay:=2.4 if facade>=Forms.Finish.CURTAIN_WALL else 2.2
		var axis:=span*(maxi(1,roundi(span.length()/bay))*bay/span.length_squared())
		g.facade_uv=Vector3(axis.x,axis.y,-a.dot(axis))
		g.finish=facade
		g.quad(Vector3(a.x,bottom,a.y),Vector3(b.x,bottom,b.y),end,hi,tint,outward)
		g.facade_uv=Vector3.ZERO
		g.finish=Forms.Finish.FELT
		g.triangle(Vector3(center.x,top,center.y),hi,end,ROOF,Vector3.UP)
		g.finish=Forms.Finish.PLAIN
		g.quad(hi,end,end+Vector3.UP*.16,hi+Vector3.UP*.16,trim,outward)
