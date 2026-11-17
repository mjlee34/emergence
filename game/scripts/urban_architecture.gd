extends RefCounted
const Forms=preload("res://scripts/forms.gd")
const ROOF:=Color("#45494b")
const FLASHING:=Color("#777b7a")
const STONE:=Color("#aba69c")

static func row_house(lot:Dictionary) -> bool:
	return lot.use==0 and lot.floors<=3 and lot.wing>=4.5 and lot.style%4!=0

static func masonry_house(lot:Dictionary) -> bool:
	return lot.floors in [2,3] and (lot.use==1 or lot.style%4!=0)

static func entrance(g,x:float,z:float,side:int,style:int) -> void:
	var trim:=Color("#4d514e")
	var leaf:Color=[Color("#515854"),Color("#635147"),Color("#484d51")][style%3]
	g.finish=Forms.Finish.PLAIN
	g.box(Vector3(x,1.12,z),Vector3(1.05,2.25,.18),trim)
	var face:=z+side*.101
	g.box(Vector3(x,1.10,face),Vector3(.89,2.10,.035),leaf)
	g.finish=Forms.Finish.WINDSCREEN
	g.box(Vector3(x,1.58,face+side*.025),Vector3(.65,.79,.019),Color("#45504f"))
	g.finish=Forms.Finish.PLAIN
	g.box(Vector3(x,.64,face+side*.03),Vector3(.67,.72,.03),leaf.lightened(.07))
	g.box(Vector3(x,1.57,face+side*.04),Vector3(.033,.79,.026),trim)
	g.box(Vector3(x+.32,1.04,face+side*.07),Vector3(.13,.036,.087),Color("#bbb6a8"))

static func house_shell(g,lot:Dictionary,w:float,d:float,h:float) -> void:
	g.finish=Forms.Finish.BRICK_FRONT if (lot.style/5)%3==0 else Forms.Finish.LIMESTONE_FRONT
	g.box(Vector3.UP*h*.5,Vector3(w,h,d),Color("#e4e1dc"))
	g.finish=Forms.Finish.PLAIN
	var front:float=lot.front_sign*(d*.5+.04)
	entrance(g,0.,front,lot.front_sign,lot.style)
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

# A raised band of windows brings light into the founding market hall.
static func market_lantern(g,w:float,d:float,h:float) -> void:
	var timber:=Color("#554f47")
	var copper:=Color("#647970")
	var rim:=Vector3(0,h+.44,0)
	g.finish=Forms.Finish.PLAIN
	g.box(rim,Vector3(w*.80,.26,d*.58),timber)
	g.finish=Forms.Finish.GLASS
	g.box(rim+Vector3.UP*.90,Vector3(w*.73,1.58,d*.48),Color("#aab5a7"))
	g.finish=Forms.Finish.PLAIN
	for side in [-1.,1.]:
		for i in 6:
			g.box(rim+Vector3((i/5.-.5)*w*.74,.88,side*d*.25),Vector3(.10,1.6,.12),timber)
	var eave:=h+2.13
	for side in [-1.,1.]:
		g.quad(Vector3(-w*.41,eave,side*d*.31),Vector3(w*.41,eave,side*d*.31),Vector3(w*.33,eave+1.2,0),Vector3(-w*.33,eave+1.2,0),copper,Vector3.UP)
		g.triangle(Vector3(side*w*.41,eave,-d*.31),Vector3(side*w*.41,eave,d*.31),Vector3(side*w*.33,eave+1.2,0),copper,Vector3.RIGHT*side)

# The top dwelling sits inside the roof. Projecting dormers and the change
# in pitch remain readable when the street-level meshes switch out.
static func mansion_block(g,lot:Dictionary,w:float,d:float) -> void:
	var h:float=lot.floors*3.05
	var eave:=h-3.05
	var stone:=Color("#c9c3b6")
	var slate:Color=[Color("#545e63"),Color("#65625d"),Color("#536566")][(lot.style/3)%3]
	var facade:=Forms.Finish.BRICK_FRONT if lot.style%3 else Forms.Finish.LIMESTONE_FRONT
	_section(g,Vector2.ZERO,w,d,0.,eave,.18,facade,Color("#e6dfd2"),stone)
	g.finish=Forms.Finish.PLAIN
	g.box(Vector3.UP*eave,Vector3(w+.38,.30,d+.38),stone)
	var lower:=Vector2(w*.5+.15,d*.5+.15)
	var upper:=Vector2(w*.5-.85,d*.5-.80)
	g.finish=Forms.Finish.SLATE
	for side in [-1.,1.]:
		g.quad(Vector3(-lower.x,eave,side*lower.y),Vector3(lower.x,eave,side*lower.y),Vector3(upper.x,h,side*upper.y),Vector3(-upper.x,h,side*upper.y),slate,Vector3.UP)
		g.quad(Vector3(side*lower.x,eave,-lower.y),Vector3(side*lower.x,eave,lower.y),Vector3(side*upper.x,h,upper.y),Vector3(side*upper.x,h,-upper.y),slate,Vector3.UP)
	g.finish=Forms.Finish.FELT
	g.box(Vector3(0,h,0),Vector3(2.*upper.x,.14,2.*upper.y),ROOF)
	var bays:=maxi(2,floori(w/3.6))
	for side in [-1.,1.]:
		for i in bays:
			var x:float=((i+.5)/bays-.5)*w
			var window:=Vector3(x,eave+1.23,side*(d*.5-.18))
			g.finish=Forms.Finish.PLAIN
			g.box(window,Vector3(1.38,1.8,.74),stone)
			g.finish=Forms.Finish.GLASS
			g.box(window+Vector3(0,.02,side*.37),Vector3(1.02,1.43,.06),Color("#576766"))
			g.finish=Forms.Finish.PLAIN
			g.box(window+Vector3.UP*.94,Vector3(1.55,.19,.88),slate)
	g.finish=Forms.Finish.BRICK
	g.box(Vector3(w*.29,h+.53,-d*.23),Vector3(.79,1.15,.64),Color("#a18e80"))

# The existing corner business occupies all of these floors. Its upper
# storeys pull back towards the street corner as the parcel is redeveloped.
static func corner_building(g,lot:Dictionary,w:float,d:float) -> void:
	var floors:int=lot.floors
	var storey_h:=storey(lot)
	var h:=floors*storey_h
	var tall:=floors>=10
	var stone:=Color("#ded7c7")
	var trim:=Color("#aaaba1")
	var metal:Color=[Color("#697d74"),Color("#717b85"),Color("#83786a")][lot.style%3]
	var setback:=storey_h*clampi(floori(floors*.52),2,7)
	_section(g,Vector2.ZERO,w,d,0.,setback,.26,Forms.Finish.LIMESTONE_FRONT,stone,trim)
	var center:=Vector2(w*.10*(1. if lot.style%2 else -1.),d*.065*float(lot.front_sign))
	var width:=w*.70
	var depth:=d*.76
	var shoulder:=h-storey_h if floors>=6 else h
	var skin:=Forms.Finish.BRONZE_FRONT if tall else Forms.Finish.LIMESTONE_FRONT
	_section(g,center,width,depth,setback,shoulder,minf(width,depth)*.11,skin,Color("#e5ded2"),trim)
	if shoulder<h:
		width*=.82
		depth*=.85
		_section(g,center,width,depth,shoulder,h,.4,skin,stone,trim)
	g.finish=Forms.Finish.PLAIN
	for side in [-1.,1.]:
		for column in [-.31,.31]:
			g.box(Vector3(center.x+width*column,(setback+shoulder)*.5,center.y+side*(depth*.5+.035)),Vector3(.18,shoulder-setback,.17),trim)
	var base:=Vector3(center.x,h,center.y)
	var radius:=minf(width,depth)*.43
	g.taper(base,radius*1.1,radius*1.1,.36,8,trim,PI/8.)
	g.finish=Forms.Finish.GLASS
	g.taper(base+Vector3.UP*.36,radius,radius,1.55,8,Color("#829996"),PI/8.)
	g.finish=Forms.Finish.PLAIN
	var eave:=base+Vector3.UP*1.91
	var crown:=radius*(1.15 if tall else .87)
	g.taper(eave,radius*1.12,radius*.30,crown,8,metal,PI/8.)
	g.taper(eave+Vector3.UP*crown,radius*.30,.07,1.10,8,metal,PI/8.)

static func add(g,lot:Dictionary,w:float,d:float,nearby:bool) -> void:
	if lot.main_street_corner:
		corner_building(g,lot,w+1.15,d+.58)
		return
	if lot.use==0 and lot.floors<=8 and lot.style%5 in [0,1,2]:
		mansion_block(g,lot,w,d)
		return
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
	var podium:=floor_height
	var tower_lot:bool=floors>=11 and lot.wing>=2.
	if tower_lot: podium=floor_height*(3 if floors>=18 else 2)
	var podium_skin:=Forms.Finish.LIMESTONE_FRONT if tower_lot and lot.use==1 else facade
	_section(g,Vector2.ZERO,width,depth,0.,podium,.38,podium_skin,tint,trim)
	if tower_lot:
		width*=.83
		depth*=.92
	var center:=Vector2.ZERO
	var start:=podium
	var chamfer:=.22
	var form:int=(s/9)%4
	if form==1: chamfer=minf(width,depth)*.23
	if form==2: chamfer=minf(width,depth)*.12
	var tall:=floors>=9
	if tower_lot and lot.use==0 and s%3==0: facade=Forms.Finish.CURTAIN_WALL
	if facade==Forms.Finish.CURTAIN_WALL:
		tint=[Color("#bfd3d4"),Color("#c5cbcf"),Color("#cadbd4")][(s/11)%3]
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
	if floors>=6 and form==1 and lot.use==0:
		# Recessed balcony bands wrap two street-facing corners.
		g.finish=Forms.Finish.PLAIN
		for floor_id in range(2,floors,2):
			var y:=floor_id*floor_height
			for sign_x in [-1.,1.]:
				g.box(Vector3(sign_x*width*.29,y,lot.front_sign*(depth*.5+.28)),Vector3(width*.30,.19,.68),STONE)
				g.box(Vector3(sign_x*width*.29,y+.59,lot.front_sign*(depth*.5+.57)),Vector3(width*.30,1.0,.09),Color("#8c9999"))
	# Enclosed mechanical floors follow the roof outline of each family.
	var top:=Vector3(center.x,height,center.y)
	var plant:=Vector2(width*.47,depth*.39)
	var crown:=floor_height*.38
	g.finish=Forms.Finish.METAL
	if tall and form==1:
		# A folded zinc crown continues the chamfered glass shaft to a ridge.
		var rise:=clampf(height*.075,2.6,7.4)
		var ridge:=top+Vector3(width*.14,rise,0.)
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
