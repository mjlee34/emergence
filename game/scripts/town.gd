extends Node3D
const Forms = preload("res://scripts/forms.gd")
const WALLS = ["#f3dfb9","#e2d1ae","#d9a783","#c7d0bd","#e6c78f","#b8c6ba"]
const ROOFS = ["#af6045","#596a70","#a7634d","#7b7065","#c27651","#586c65"]
var model
var land
var market_clock_built:=false
var roads := 0
var buildings := 0
var renewals:=0
var sites: Array[MeshInstance3D]=[]
var horizontal:Dictionary={}
var vertical:Dictionary={}
var enclosed:Dictionary={}
var paved:Dictionary={}
var last_paving_population:=0
var car_meshes: Array[Mesh]=[]
var construction := {}
var cars: Array[Node3D] = []

func create(sim, landscape) -> void:
	model=sim
	land=landscape
	for i in range(6):
		var g=Forms.new()
		var tint := Color(["#d75839","#eec66b","#eee1c5","#668991","#ad6351","#748e79"][i%6])
		g.box(Vector3(0,.64,0),Vector3(2.75,.67,1.28),tint)
		g.box(Vector3(-.13,1.12,0),Vector3(1.48,.46,1.1),Color("#4b6066"))
		g.box(Vector3(-.13,1.39,0),Vector3(1.52,.14,1.12),tint)
		for x in [-.88,.88]:
			for z in [-.59,.59]:
				g.box(Vector3(x,.34,z),Vector3(.49,.45,.19),Color("#424a47"))
		car_meshes.append(g.mesh())

func sync(state: Dictionary, fraction: float) -> void:
	var extended:bool=roads<state.roads
	while roads<state.roads:
		_street(model.street(roads))
		roads+=1
	if state.population>=3200 and (extended or state.population-last_paving_population>=150):
		_pave_blocks(state.population)
	var changed:Dictionary={}
	while renewals<state.renewals:
		var index:int=model.renewed_lot(renewals)
		if index<buildings: changed[index]=true
		renewals+=1
	for index in changed:
		var old:=sites[int(index)]
		construction.erase(old)
		old.queue_free()
		sites[index]=_build(model.lot(index))
	while buildings<state.buildings:
		sites.append(_build(model.lot(buildings)))
		buildings+=1
	for site in construction.keys():
		var t := clampf((state.tick+fraction-int(construction[site]))/24.,0.,1.)
		site.scale.y = maxf(.035,smoothstep(0,1,t))
		if t>=1: construction.erase(site)
	var positions: PackedVector4Array = model.traffic(fraction)
	while cars.size()<positions.size():
		var car:=MeshInstance3D.new()
		car.mesh=car_meshes[cars.size()%car_meshes.size()]
		add_child(car)
		cars.append(car)
	for i in cars.size():
		var p:=positions[i]
		cars[i].position=Vector3(p.x,p.y+.31,p.z)
		cars[i].rotation.y=p.w

func _ribbon(g,path: PackedVector3Array,width: float,lift: float,color: Color,offset:=0.,deck:=false) -> void:
	var left: Array[Vector3]=[]
	var right: Array[Vector3]=[]
	for i in path.size():
		var dir := (path[mini(i+1,path.size()-1)]-path[maxi(i-1,0)]).normalized()
		var lateral := Vector3(-dir.z,0,dir.x).normalized()
		for side in [-1,1]:
			var p:Vector3 = path[i]+lateral*(offset+side*width*.5)
			p.y=(path[i].y if deck else model.height_at(p.x,p.z))+lift
			if side<0: left.append(p)
			else: right.append(p)
	for i in range(path.size()-1):
		g.quad(left[i],right[i],right[i+1],left[i+1],color,Vector3.UP)

func _register_block_edges(data:Dictionary) -> void:
	if data.bridge: return
	var a:Vector2i=data.a
	var b:Vector2i=data.b
	var origin:=a.min(b)
	var path:PackedVector3Array=data.path
	if origin!=a:
		path=path.duplicate()
		path.reverse()
	var across:=a.y==b.y
	var edges:=horizontal if across else vertical
	edges[origin]=path
	for cell in [origin,origin-(Vector2i.DOWN if across else Vector2i.RIGHT)]:
		if paved.has(cell): continue
		if horizontal.has(cell) and horizontal.has(cell+Vector2i.DOWN) and vertical.has(cell) and vertical.has(cell+Vector2i.RIGHT):
			enclosed[cell]=true

func _pave_blocks(population:int) -> void:
	# Closed central blocks acquire a continuous mineral surface and planted courts.
	# The same sampled edges define the four sides, so sidewalks follow road bends.
	last_paving_population=population
	var built=[]
	var g=Forms.new()
	for cell in enclosed:
		var top:PackedVector3Array=horizontal[cell]
		var bottom:PackedVector3Array=horizontal[cell+Vector2i.DOWN]
		var center:=top[4].lerp(bottom[4],.5)
		var radius:=Vector2(center.x+30,center.z-6).length()
		var industrial:bool=center.x>model.river_x(center.z)+24 and center.z>0
		if not industrial and radius>minf(210.,population*.026): continue
		var left:PackedVector3Array=vertical[cell]
		var right:PackedVector3Array=vertical[cell+Vector2i.RIGHT]
		var grid:=PackedVector3Array()
		for j in 9:
			for i in 9:
				var u:=i/8.
				var v:=j/8.
				var p:=top[i].lerp(bottom[i],v)
				p+=(left[j]-top[0].lerp(bottom[0],v))*(1.-u)+(right[j]-top[8].lerp(bottom[8],v))*u
				p.y=model.height_at(p.x,p.z)+.14
				grid.append(p)
		var brick:=Color("#b7ac95") if (cell.x+cell.y)%3==0 else Color("#a8a797")
		if industrial: brick=Color("#969c92")
		for j in 8:
			for i in 8:
				var k:=j*9+i
				var court:=i>=3 and i<=4 and j>=3 and j<=4 and not industrial
				var tint:=Color("#899a70") if court else brick
				g.quad(grid[k],grid[k+1],grid[k+10],grid[k+9],tint,Vector3.UP)
		built.append(cell)
	if not built.is_empty(): g.attach(self)
	for cell in built:
		paved[cell]=true
		enclosed.erase(cell)

func _street(data: Dictionary) -> void:
	_register_block_edges(data)
	var g=Forms.new()
	var path:PackedVector3Array=data.path
	var width:float=data.width
	var rank:int=data["class"]
	var deck:bool=data.bridge
	var asphalt:=Color(["#888c7f","#606d6c","#414f53"][rank])
	land.clear_street(path,width*.5+2.8)
	_ribbon(g,path,width+1.6+rank*.7,.24,Color("#c4bba4"),0,deck)
	_ribbon(g,path,width,.36,asphalt,0,deck)
	for p in [path[0],path[-1]]:
		g.taper(p+Vector3.UP*.27,width*.5,width*.5,.11,16,asphalt)
	var interior:=path.slice(1,8)
	if rank==2:
		_ribbon(g,interior,1.85,.45,Color("#c7bea3"),0,deck)
		_ribbon(g,interior,1.35,.48,Color("#76915e"),0,deck)
		for i in [2,4,6]:
			var p:=path[i]+Vector3.UP*.45
			if not deck:
				g.taper(p,.17,.12,1.45,6,Color("#76674d"))
				g.taper(p+Vector3.UP*1.3,.72,1.1,1.0,8,Color("#739259"))
				g.taper(p+Vector3.UP*2.3,1.1,.28,1.16,8,Color("#90a564"))
	if rank>0:
		for i in range(1,7,2):
			var dash:=PackedVector3Array([path[i],path[i].lerp(path[i+1],.75)])
			for stripe in ([-3.9,3.9] if rank==2 else [0.]):
				_ribbon(g,dash,.23,.42,Color("#eddfac") if rank==1 else Color("#e6e3cd"),stripe,deck)
		var tangent:=(path[5]-path[3]).normalized()
		var lateral:=Vector3(-tangent.z,0,tangent.x).normalized()
		var p:=path[4]+lateral*(width*.5+.55)
		g.taper(p,.15,.10,4.3,6,Color("#475553"))
		g.box(p+Vector3.UP*4.3,Vector3(.62,.22,.62),Color("#eedcab"))
	if deck:
		for side in [-1,1]:
			_ribbon(g,path,.55,1.28,Color("#c8c2a9"),side*(width*.5+.65),true)
			for i in path.size():
				var dir:Vector3=(path[mini(i+1,8)]-path[maxi(i-1,0)]).normalized()
				var p:Vector3=path[i]+Vector3(-dir.z,0,dir.x)*side*(width*.5+.65)
				g.box(p+Vector3.UP*.83,Vector3(.5,1,.5),Color("#948f79"))
		for i in [2,4,6]:
			var p:=path[i]
			var h:float=p.y-model.height_at(p.x,p.z)
			for side in [-1,1]:
				g.taper(p+Vector3(0,-h-.6,side*4),.85,.68,h+.7,8,Color("#a59a83"))
	g.attach(self)

func _build(lot: Dictionary) -> MeshInstance3D:
	var s:int=lot.style
	var use:int=lot.use
	var w:=7.2+(s%4)*.62
	var d:=5.8+(s%5)*.47
	var floors:int=lot.floors
	if floors>=4 or use==2:
		return _urban_block(lot,w,d)
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
	return site

func _gable(g,w:float,d:float,h:float,roof:Color,wall:Color) -> void:
	var ridge:=h+1.65
	for sign_x in [-1,1]:
		var x:float=sign_x*w*.5
		g.triangle(Vector3(x,h,-d*.5),Vector3(x,ridge,0),Vector3(x,h,d*.5),wall,Vector3.RIGHT*sign_x)
	for sign_z in [-1,1]:
		var z:float=sign_z*(d*.5+.42)
		var x:=w*.5+.37
		g.quad(Vector3(-x,h-.14,z),Vector3(x,h-.14,z),Vector3(x,ridge,0),Vector3(-x,ridge,0),roof,Vector3.UP)

func _urban_block(lot:Dictionary,w:float,d:float) -> MeshInstance3D:
	var g=Forms.new()
	var s:int=lot.style
	var floors:int=lot.floors
	var height:=floors*2.8
	var facade:=Color(["#c5b39a","#d0c6af","#b49377","#c8cfc2"][s%4])
	g.box(Vector3(0,-.13,0),Vector3(w+2.3,.8,d+2.0),Color("#aba594"))
	if lot.use==2:
		# Riverside sheds have wide loading doors, roof monitors and exhaust stacks.
		g.box(Vector3(0,2.15,0),Vector3(w+1.2,4.3,d+.8),Color("#a5aa98"))
		_gable(g,w+1.2,d+.8,4.3,Color("#778c8b"),facade)
		for x in [-1,1]:
			g.box(Vector3(x*w*.23,1.4,d*.5+.42),Vector3(2.34,2.8,.13),Color("#5f716e"))
		g.box(Vector3(0,5.76,0),Vector3(w*.68,.84,1.4),Color("#bcc6b9"))
		g.taper(Vector3(-w*.33,3.8,-d*.22),.58,.42,3.4+s%4,8,Color("#a1775d"))
		if s%5==0:
			for x in [-1,1]:
				var silo:=Vector3(x*1.12,3.8,-d*.34)
				g.taper(silo,1.05,1.05,4.1,12,Color("#cad0be"))
				g.taper(silo+Vector3.UP*4.1,1.1,0,.8,12,Color("#839795"))
	else:
		var glass:=Color(["#58777b","#627b79","#54727c","#728683"][s%4])
		var tower:=floors>=9
		g.box(Vector3(0,2,0),Vector3(w+1.2,4,d+1),facade)
		for side in [-1,1]:
			g.box(Vector3(0,1.7,side*(d*.5+.55)),Vector3(w*.84,2.3,.14),glass)
		var body_w:=w*(.90 if tower else 1.)
		var body_d:=d*(.88 if tower else 1.)
		g.box(Vector3(0,(height+4)*.5,0),Vector3(body_w,height-4,body_d),glass if tower else facade)
		for level in range(2,floors):
			var y:=level*2.8+.35
			if tower:
				g.box(Vector3(0,y,0),Vector3(body_w+.04,.36,body_d+.04),facade)
			else:
				for side in [-1,1]:
					g.box(Vector3(0,y,side*(body_d*.5+.04)),Vector3(body_w*.88,1.28,.14),glass)
					g.box(Vector3(side*(body_w*.5+.04),y,0),Vector3(.14,1.28,body_d*.74),glass)
		if not tower:
			for side in [-1,1]:
				for bay in [-.25,0.,.25]:
					g.box(Vector3(bay*body_w,(height+4)*.5,side*(body_d*.5+.14)),Vector3(.21,height-4,.16),facade)
		if tower:
			for side in [-1,1]:
				g.box(Vector3(side*body_w*.5,(height+4)*.5,-body_d*.28),Vector3(.3,height-4,.57),facade)
			if s%2==0:
				var crown_h:=3.+s%4
				g.box(Vector3(0,height+crown_h*.5,0),Vector3(body_w*.72,crown_h,body_d*.72),glass)
				g.box(Vector3(0,height+crown_h+.12,0),Vector3(body_w*.74,.32,body_d*.74),facade)
		g.box(Vector3(0,height+.18,0),Vector3(body_w+.35,.44,body_d+.35),facade)
		g.box(Vector3(-.52,height+.91,0),Vector3(body_w*.52,1.4,body_d*.48),Color("#929c95"))
		for unit in range(2):
			g.box(Vector3(body_w*.27,height+.56,(unit-.5)*body_d*.46),Vector3(.91,.76,1.27),Color("#87948e"))
		if tower and s%3==0:
			g.taper(Vector3(-.5,height+1.6,0),.18,.04,3.2,6,facade)
	var site=g.attach(self)
	site.position=lot.pos
	site.rotation.y=lot.yaw
	land.clear_lot(lot.pos)
	if lot.started>=0: construction[site]=lot.started
	return site
