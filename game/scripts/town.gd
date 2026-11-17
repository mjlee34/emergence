extends Node3D
const Forms = preload("res://scripts/forms.gd")
const WALLS = ["#f3dfb9","#e2d1ae","#d9a783","#c7d0bd","#e6c78f","#b8c6ba"]
const ROOFS = ["#af6045","#596a70","#a7634d","#7b7065","#c27651","#586c65"]
var model
var land
var market_clock_built:=false
var roads := 0
var buildings := 0
var construction := {}
var cars: Array[Node3D] = []

func create(sim, landscape) -> void:
	model=sim
	land=landscape
	var traffic: PackedVector4Array=model.traffic(0)
	for i in traffic.size():
		var g=Forms.new()
		var tint := Color(["#d75839","#eec66b","#eee1c5","#668991","#ad6351","#748e79"][i%6])
		g.box(Vector3(0,.64,0),Vector3(2.75,.67,1.28),tint)
		g.box(Vector3(-.13,1.12,0),Vector3(1.48,.46,1.1),Color("#4b6066"))
		g.box(Vector3(-.13,1.39,0),Vector3(1.52,.14,1.12),tint)
		for x in [-.88,.88]:
			for z in [-.59,.59]:
				g.box(Vector3(x,.34,z),Vector3(.49,.45,.19),Color("#424a47"))
		cars.append(g.attach(self))
	_water_tower()

func sync(state: Dictionary, fraction: float) -> void:
	while roads<state.roads:
		_street(model.street(roads))
		roads+=1
	while buildings<state.buildings:
		_build(model.lot(buildings))
		buildings+=1
	for site in construction.keys():
		var t := clampf((state.tick+fraction-int(construction[site]))/24.,0.,1.)
		site.scale.y = maxf(.035,smoothstep(0,1,t))
		if t>=1: construction.erase(site)
	var positions: PackedVector4Array = model.traffic(fraction)
	for i in cars.size():
		var p:=positions[i]
		cars[i].position=Vector3(p.x,p.y+.31,p.z)
		cars[i].rotation.y=p.w

func _ribbon(g,path: PackedVector3Array,width: float,lift: float,color: Color) -> void:
	var left: Array[Vector3]=[]
	var right: Array[Vector3]=[]
	for i in path.size():
		var dir := (path[mini(i+1,path.size()-1)]-path[maxi(i-1,0)]).normalized()
		var lateral := Vector3(-dir.z,0,dir.x).normalized()*width*.5
		for sign_value in [-1,1]:
			var p:Vector3 = path[i]+sign_value*lateral
			p.y=model.height_at(p.x,p.z)+lift
			if sign_value<0: left.append(p)
			else: right.append(p)
	for i in range(path.size()-1):
		g.quad(left[i],right[i],right[i+1],left[i+1],color,Vector3.UP)

func _street(data: Dictionary) -> void:
	var g=Forms.new()
	var path:PackedVector3Array=data.path
	var width:=5.8 if data.avenue else 4.15
	land.clear_street(path,width*.5+2.15)
	_ribbon(g,path,width+1.85,.22,Color("#c7bd9e"))
	_ribbon(g,path,width,.32,Color("#6c7470"))
	for p in [path[0],path[-1]]:
		g.taper(p+Vector3.UP*.23,width*.50,width*.50,.11,12,Color("#6c7470"))
	if data.avenue:
		for i in range(1,7,2):
			_ribbon(g,PackedVector3Array([path[i].lerp(path[i+1],.20),path[i].lerp(path[i+1],.82)]),.15,.37,Color("#e8d7a0"))
		# A streetlamp on the sidewalk of each collector block.
		var p := path[4]
		p.z+=width*.5+.5
		p.y=model.height_at(p.x,p.z)
		g.taper(p,.12,.1,3.85,6,Color("#485754"))
		g.box(p+Vector3(0,3.87,-.38),Vector3(.15,.18,.9),Color("#485754"))
		g.box(p+Vector3(0,3.81,-.78),Vector3(.36,.15,.53),Color("#ffe6a6"))
	g.attach(self)

func _build(lot: Dictionary) -> void:
	var s:int=lot.style
	var use:int=lot.use
	var w:=5.2+(s%4)*.63
	var d:=4.2+(s%5)*.47
	var floors:=1+(s%3)
	if use==1: floors=2+(s%3)
	if use==2: floors=1
	var h:=floors*2.25+.48
	var g=Forms.new()
	var yard_color:=Color("#98a46c") if use==0 else Color("#b4a88f")
	g.box(Vector3(0,-.24,0),Vector3(w+1.85,.52,d+1.95),yard_color)
	var wall:=Color(WALLS[s%WALLS.size()])
	var roof:=Color(ROOFS[(s/7)%ROOFS.size()])
	g.box(Vector3(0,-.22,0),Vector3(w+1.1,.94,d+1),Color("#a59b85"))
	g.box(Vector3(0,h*.5,0),Vector3(w,h,d),wall)
	for floor_index in floors:
		var y:=floor_index*2.25+1.55
		for side in [-1,1]:
			for k in range(3):
				var x:float=(k-1)*w*.30
				if floor_index==0 and k==1:
					g.box(Vector3(x,.99,side*(d*.5+.055)),Vector3(.92,1.87,.12),Color("#65716b"))
				else:
					g.box(Vector3(x,y,side*(d*.5+.055)),Vector3(1.03,1.12,.13),Color("#567078"))
					g.box(Vector3(x,y-.60,side*(d*.5+.1)),Vector3(1.24,.15,.24),Color("#eee1bd"))
			for k in [-1,1]:
				g.box(Vector3(side*(w*.5+.04),y,k*d*.22),Vector3(.12,1.06,.88),Color("#627b7b"))
	if use==0:
		if s%4==0:
			g.box(Vector3(w*.28,h*.32,d*.46),Vector3(w*.42,h*.64,d*.42),wall)
			g.box(Vector3(w*.28,h*.65,d*.46),Vector3(w*.49,.26,d*.47),roof)
		_gable(g,w,d,h,roof,wall)
		g.box(Vector3(w*.25,h+1.36,-d*.2),Vector3(.77,2.1,.74),Color("#a56b53"))
	elif use==1:
		g.box(Vector3(0,h+.10,0),Vector3(w+.5,.4,d+.5),Color("#eee1c1"))
		g.box(Vector3(0,h+.33,0),Vector3(w-.32,.25,d-.32),Color("#707972"))
		g.box(Vector3(-w*.24,h+.73,d*.18),Vector3(1.3,.62,1.2),Color("#afb3a4"))
		for k in range(7):
			g.box(Vector3((k-3)*w/7,2.40,-d*.5-.46),Vector3(w/7,.23,1.14),Color("#d48765") if k%2 else Color("#f3dfb7"))
	else:
		_gable(g,w,d,h,Color("#698181"),wall)
		g.taper(Vector3(w*.34,h-.5,0),.46,.33,3.0,8,Color("#a9775e"))
	if use==1 and not market_clock_built:
		market_clock_built=true
		var top:=h+.4
		g.box(Vector3(0,top+1.9,0),Vector3(2.85,3.8,2.85),Color("#efdfb9"))
		for sign_z in [-1,1]:
			g.box(Vector3(0,top+2,sign_z*1.45),Vector3(1.68,1.68,.12),Color("#505f5b"))
			g.box(Vector3(-.2,top+2.03,sign_z*1.55),Vector3(.48,.12,.1),Color("#f6dfac"))
			g.box(Vector3(0,top+2.33,sign_z*1.55),Vector3(.12,.69,.1),Color("#f6dfac"))
		g.taper(Vector3(0,top+3.8,0),2.36,.12,3.8,4,Color("#60807b"),PI*.25)
		g.taper(Vector3(0,top+7.6,0),.15,.02,1.,6,Color("#ccaf65"))
	if use==0:
		# Low garden walls and planting frame each cottage's backyard.
		g.box(Vector3(0,.25,d*.5+.65),Vector3(w*.92,.65,.35),Color("#788a57"))
		for side in [-1,1]:
			g.box(Vector3(side*(w*.5+.35),.23,d*.22),Vector3(.3,.58,d*.55),Color("#8a9866"))
	var site=g.attach(self)
	site.position=lot.pos
	site.rotation.y=lot.yaw
	land.clear_lot(lot.pos)
	if lot.started>=0: construction[site]=lot.started

func _gable(g,w:float,d:float,h:float,roof:Color,wall:Color) -> void:
	var ridge:=h+1.65
	for sign_x in [-1,1]:
		var x:float=sign_x*w*.5
		g.triangle(Vector3(x,h,-d*.5),Vector3(x,ridge,0),Vector3(x,h,d*.5),wall,Vector3.RIGHT*sign_x)
	for sign_z in [-1,1]:
		var z:float=sign_z*(d*.5+.42)
		var x:=w*.5+.37
		g.quad(Vector3(-x,h-.14,z),Vector3(x,h-.14,z),Vector3(x,ridge,0),Vector3(-x,ridge,0),roof,Vector3.UP)

func _water_tower() -> void:
	# A small municipal landmark set outside the developable street lattice.
	var p:=Vector3(144,model.height_at(144,34),34)
	var g=Forms.new()
	for x in [-1.8,1.8]:
		for z in [-1.8,1.8]:
			g.box(Vector3(x,5,z),Vector3(.47,10,.47),Color("#806e53"))
	for y in [3.0,7.0,9.6]:
		g.box(Vector3(0,y,0),Vector3(4.3,.38,4.3),Color("#776950"))
	g.taper(Vector3(0,9.6,0),2.2,3.1,1.1,12,Color("#adc1b1"))
	g.taper(Vector3(0,10.7,0),3.1,3.1,4.4,12,Color("#e0c8a0"))
	for y in [11.2,13.5,14.8]:
		g.taper(Vector3(0,y,0),3.16,3.16,.19,12,Color("#847f6a"))
	g.taper(Vector3(0,15.1,0),3.45,0,1.8,12,Color("#9e5d47"))
	var tower=g.attach(self)
	tower.position=p
	land.clear_lot(p)
