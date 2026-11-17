extends Node3D
const Forms = preload("res://scripts/forms.gd")
const Roadworks=preload("res://scripts/roadworks.gd")
const BuildingWorks=preload("res://scripts/building_works.gd")
const WALLS = ["#c6bdaa","#bda991","#b88874","#abb1a7","#c2af95","#a9aca2"]
const ROOFS = ["#a17a66","#5b6770","#94705e","#777169","#ad8675","#52615f"]
var model
var land
var market_hall_built:=false
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
var construction:Dictionary={}
var roadworks:Dictionary={}
var court_works:Dictionary={}
var cars: Array[Node3D] = []
var junction_caps:Dictionary={}
var street_lights:=Node3D.new()
var last_light_tick:=-1

func create(sim, landscape) -> void:
	model=sim
	land=landscape
	add_child(street_lights)
	for i in range(6):
		var g=Forms.new()
		var tint:=Color(["#813e36","#a9aba7","#d4d0c6","#50616d","#343c43","#8b8d7c"][i])
		var hatch:=i%3==0
		# Cross-sections give the bonnet, windscreen and rear hatch different slopes.
		var stations:=[[ -2.10,.82,.82],[-1.90,.98,.89],[ -1.32,1.02,.90],[.88,1.01,.89],[1.88,.90,.84],[2.06,.73,.75]]
		for n in range(stations.size()-1):
			var a:Array=stations[n]
			var b:Array=stations[n+1]
			g.quad(Vector3(a[0],a[1],-a[2]),Vector3(a[0],a[1],a[2]),Vector3(b[0],b[1],b[2]),Vector3(b[0],b[1],-b[2]),tint,Vector3.UP)
			for z in [-1,1]:
				g.quad(Vector3(a[0],.38,z*a[2]*.93),Vector3(a[0],a[1],z*a[2]),Vector3(b[0],b[1],z*b[2]),Vector3(b[0],.38,z*b[2]*.93),tint,Vector3.BACK*z)
		for end in [stations[0],stations[-1]]:
			g.box(Vector3(end[0],(.36+end[1])*.5,0),Vector3(.06,end[1]-.36,end[2]*2.),tint)
		var tail:float=-1.74 if hatch else -1.38
		var roof_tail:float=-1.32 if hatch else -.85
		var glass:=Color("#455158")
		for z in [-1,1]:
			g.quad(Vector3(tail,1.01,z*.84),Vector3(roof_tail,1.52,z*.69),Vector3(.25,1.52,z*.67),Vector3(.94,1.02,z*.83),glass,Vector3.BACK*z)
			g.quad(Vector3(-.48,1.015,z*.845),Vector3(-.49,1.521,z*.695),Vector3(-.415,1.521,z*.695),Vector3(-.395,1.015,z*.845),Color("#30383a"),Vector3.BACK*z)
			for x in [-1.30,1.29]: g.wheel(Vector3(x,.37,z*.84),.34,z)
			g.box(Vector3(2.045,.739,z*.54),Vector3(.09,.13,.36),Color("#d9d9cd"))
			g.box(Vector3(-2.10,.742,z*.58),Vector3(.072,.14,.36),Color("#94463e"))
			g.box(Vector3(.60,1.102,z*.93),Vector3(.23,.12,.20),tint)
		for end in [[tail,roof_tail,-1.],[.94,.25,1.]]:
			g.quad(Vector3(end[0],1.01,-.836),Vector3(end[0],1.01,.836),Vector3(end[1],1.52,.69),Vector3(end[1],1.52,-.69),glass,Vector3(end[2],.6,0))
		g.box(Vector3((roof_tail+.25)*.5,1.532,0),Vector3(.25-roof_tail,.067,1.37),tint)
		g.box(Vector3(2.094,.53,0),Vector3(.026,.16,.60),Color("#515557"))
		car_meshes.append(g.mesh())

func sync(state: Dictionary, fraction: float) -> void:
	var time:float=state.tick+fraction
	var initial:=roads==0
	var opened:=false
	while roads<state.roads:
		var data:Dictionary=model.street(roads)
		var pending:bool=time<data.opens
		_street(data,pending,roads)
		opened=opened or not pending
		roads+=1
	for id in roadworks.keys():
		var work=roadworks[id]
		if work.advance(time,land):
			work.street.set_instance_shader_parameter("workfront",Vector4(0,0,0,2))
			_open_road(work.data)
			work.queue_free()
			roadworks.erase(id)
			opened=true
	if state.population>=3200 and (opened or state.population-last_paving_population>=150):
		_pave_blocks(state.population,time,initial)
	for court in court_works.keys():
		var c:Dictionary=court_works[court]
		var p:=clampf((time-c.start)/360.,0,1)
		var plane:Vector4=c.plane
		plane.w=lerpf(-.12,1.15,smoothstep(0.,1.,p))
		court.set_instance_shader_parameter("workfront",plane if p<1 else Vector4(0,0,0,2))
		if p>=1: court_works.erase(court)
	var changed:Dictionary={}
	while renewals<state.renewals:
		var index:int=model.renewed_lot(renewals)
		if index<buildings: changed[index]=true
		renewals+=1
	for index in changed: _present_lot(index,state,time,true)
	while buildings<state.buildings:
		_present_lot(buildings,state,time,false)
		buildings+=1
	for id in construction.keys():
		var work=construction[id]
		if work.advance(time,state.construction_ticks):
			work.queue_free()
			construction.erase(id)
	street_lights.visible=state.minute>=1080 or state.minute<390
	if street_lights.visible and state.tick!=last_light_tick:
		last_light_tick=state.tick
		for i in buildings:
			sites[i].set_instance_shader_parameter("occupancy",float(state.occupants[i]))
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

func _present_lot(id:int,state:Dictionary,time:float,replace:bool) -> void:
	var lot:Dictionary=model.lot(id)
	var active:bool=time<lot.started+state.construction_ticks
	var previous:MeshInstance3D
	if replace:
		previous=sites[id]
		# A single fast step can cross more than one project on this parcel.
		if construction.has(id):
			var former=construction[id]
			if is_instance_valid(former.old): former.old.queue_free()
			former.queue_free()
			construction.erase(id)
		if not active or previous.get_meta("floors")!=lot.previous_floors:
			previous.queue_free()
			previous=null
	if active and lot.previous_floors>0 and not previous:
		var prior:=lot.duplicate()
		prior.floors=lot.previous_floors
		previous=_build(prior)
	var finished:=_build(lot)
	finished.set_meta("floors",lot.floors)
	if replace: sites[id]=finished
	else: sites.append(finished)
	if active:
		var work=BuildingWorks.new()
		add_child(work)
		work.setup(lot,finished,previous)
		construction[id]=work

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

func _pave_blocks(population:int,time:float,initial:bool) -> void:
	# Closed central blocks acquire a continuous mineral surface and planted courts.
	# The same sampled edges define the four sides, so sidewalks follow road bends.
	last_paving_population=population
	var built=[]
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
		var g=Forms.new(true)
		var brick:=Color("#b7ac95") if (cell.x+cell.y)%3==0 else Color("#a8a797")
		if industrial: brick=Color("#969c92")
		for j in 8:
			for i in 8:
				var k:=j*9+i
				var planted:=not industrial and (radius>45. or (i in range(2,6) and j in range(2,6)))
				g.finish=Forms.Finish.MEADOW if planted else Forms.Finish.WALK
				var tint:=Color("#899a70") if planted else brick
				g.quad(grid[k],grid[k+1],grid[k+10],grid[k+9],tint,Vector3.UP)
		var court_mesh=g.attach(self)
		if not initial:
			var axis:=Vector2(bottom[4].x-top[4].x,bottom[4].z-top[4].z)
			axis/=axis.length_squared()
			court_works[court_mesh]={"start":time,"plane":Vector4(axis.x,axis.y,-axis.dot(Vector2(top[4].x,top[4].z)),0)}
		built.append(cell)
	for cell in built:
		paved[cell]=true
		enclosed.erase(cell)

func _street(data:Dictionary,pending:bool,id:int) -> void:
	var fixtures:Array=[]
	var g=Forms.new(true)
	var path:PackedVector3Array=data.path
	var width:float=data.width
	var rank:int=data["class"]
	var deck:bool=data.bridge
	var asphalt:=Color(["#888c7f","#606d6c","#414f53"][rank])
	if pending:
		# Compacted aggregate stays just ahead of the paving front.
		_ribbon(g,path,width+1.,.31,Color("#927c61") if not deck else Color("#767b77"),0,deck)
	else:
		for k in range(path.size()-1): land.clear_street(path.slice(k,k+2),width*.5+2.8)
	g.construction_lag=.09
	g.finish=Forms.Finish.WALK
	_ribbon(g,path,width+1.6+rank*.7,.385,Color("#c4bba4"),0,deck)
	g.construction_lag=.17
	g.finish=Forms.Finish.ROAD
	_ribbon(g,path,width,.405,asphalt,0,deck)
	g.construction_lag=.24
	g.finish=Forms.Finish.PLAIN
	var interior:=path.slice(1,8)
	if rank>0 and not deck:
		# Mark the pedestrian crossing on each approach, outside the junction cap.
		for k in [1,6]:
			var fraction:=.67 if k==1 else .12
			var stripe:=PackedVector3Array([path[k].lerp(path[k+1],fraction),path[k].lerp(path[k+1],fraction+.19)])
			var offset:float=-width*.5+.6
			while offset<width*.5-.35:
				if rank!=2 or absf(offset)>1.1:
					_ribbon(g,stripe,.36,.46,Color("#b7b6a8"),offset)
				offset+=.92
	if rank==2:
		_ribbon(g,interior,1.85,.45,Color("#c7bea3"),0,deck)
		g.finish=Forms.Finish.MEADOW
		_ribbon(g,interior,1.35,.48,Color("#76915e"),0,deck)
		g.finish=Forms.Finish.PLAIN
		if not deck:
			for i in [2,6]:
				fixtures.append({"at":i/8.,"node":_street_tree(path[i]+Vector3.UP*.42)})
	if rank>0:
		for i in range(1,7,2):
			var dash:=PackedVector3Array([path[i],path[i].lerp(path[i+1],.75)])
			for stripe in ([-3.9,3.9] if rank==2 else [0.]):
				_ribbon(g,dash,.15,.45,Color("#c7b58d") if rank==1 else Color("#c6c6ba"),stripe,deck)
		var tangent:=(path[5]-path[3]).normalized()
		var lateral:=Vector3(-tangent.z,0,tangent.x).normalized()
		var p:=path[4]+lateral*(width*.5+.55)
		var mast:=Color("#727976")
		g.taper(p,.092,.061,5.5,9,mast)
		var lamp:=p+Vector3.UP*5.52-lateral*1.05
		for side in [-1,1]:
			var start:Vector3=p+Vector3.UP*5.36+tangent*.042*side
			var end:Vector3=lamp+tangent*.042*side
			g.quad(start,end,end+Vector3.UP*.08,start+Vector3.UP*.08,mast,tangent*side)
		g.box(lamp,Vector3(.55,.115,.31),Color("#59605e"))
		g.finish=Forms.Finish.LAMP
		g.box(lamp-Vector3.UP*.067,Vector3(.48,.045,.26),Color("#cccabe"))
		g.finish=Forms.Finish.PLAIN
		var bulb:=OmniLight3D.new()
		bulb.position=lamp-Vector3.UP*.24
		bulb.light_color=Color("#ffd4a0")
		bulb.light_energy=2.7
		bulb.omni_range=13.
		bulb.omni_attenuation=1.35
		bulb.distance_fade_enabled=true
		bulb.distance_fade_begin=130
		bulb.distance_fade_length=65
		street_lights.add_child(bulb)
		fixtures.append({"at":.5,"node":bulb})
	if deck:
		for side in [-1,1]:
			_ribbon(g,path,.55,1.28,Color("#c8c2a9"),side*(width*.5+.65),true)
			for i in path.size():
				var dir:Vector3=(path[mini(i+1,8)]-path[maxi(i-1,0)]).normalized()
				var p:Vector3=path[i]+Vector3(-dir.z,0,dir.x)*side*(width*.5+.65)
				g.box(p+Vector3.UP*.83,Vector3(.5,1,.5),Color("#948f79"))
		g.construction_lag=0.
		# Longitudinal steel and concrete fascia give the advancing deck a section.
		for side in [-1,1]:
			for i in range(path.size()-1):
				var dir:Vector3=(path[i+1]-path[i]).normalized()
				var sideward:Vector3=Vector3(-dir.z,0,dir.x)*side
				var edge:Vector3=sideward*(width*.5+.55)+Vector3.UP*.05
				g.beam(path[i]+edge,path[i+1]+edge,.57,Color("#a49d91"))
				var girder:Vector3=sideward*width*.33-Vector3.UP*.40
				g.beam(path[i]+girder,path[i+1]+girder,.65,Color("#575f5b"))
		for i in [2,4,6]:
			var p:=path[i]
			var h:float=p.y-model.height_at(p.x,p.z)
			for side in [-1,1]:
				g.taper(p+Vector3(0,-h-.6,side*4),.85,.68,h+.7,8,Color("#a59a83"))
	var street=g.attach(self)
	if pending:
		var work=Roadworks.new()
		add_child(work)
		work.setup(data,street,fixtures)
		roadworks[id]=work
	else: _open_road(data)

func _open_road(data:Dictionary) -> void:
	_register_block_edges(data)
	var path:PackedVector3Array=data.path
	var width:float=data.width
	var rank:int=data["class"]
	var asphalt:=Color(["#888c7f","#606d6c","#414f53"][rank])
	for end_index in [0,1]:
		var key:Vector2i=data.a if end_index==0 else data.b
		var center:Vector3=path[0] if end_index==0 else path[-1]
		if not junction_caps.has(key) or junction_caps[key].rank<rank:
			if junction_caps.has(key): junction_caps[key].node.queue_free()
			var cap=Forms.new(true)
			cap.finish=Forms.Finish.ROAD
			var radius:=width*.54+.24
			center.y=model.height_at(center.x,center.z)+.437
			for i in range(20):
				var a:=center+Vector3(cos(TAU*i/20.),0,sin(TAU*i/20.))*radius
				var b:=center+Vector3(cos(TAU*(i+1)/20.),0,sin(TAU*(i+1)/20.))*radius
				a.y=model.height_at(a.x,a.z)+.437
				b.y=model.height_at(b.x,b.z)+.437
				cap.triangle(center,a,b,asphalt,Vector3.UP)
			junction_caps[key]={"rank":rank,"node":cap.attach(self)}

var street_crown:Mesh
func _street_tree(at:Vector3) -> MeshInstance3D:
	if not street_crown:
		street_crown=preload("res://scripts/landscape.gd").crown_mesh(preload("res://art/deciduous.png"),4.4)
	var tree:=MeshInstance3D.new()
	tree.mesh=street_crown
	tree.position=at
	add_child(tree)
	return tree

func _build(lot: Dictionary) -> MeshInstance3D:
	var s:int=lot.style
	var use:int=lot.use
	var w:=7.2+(s%4)*.62
	var d:=5.8+(s%5)*.47
	var floors:int=lot.floors
	if floors>=4 or use==2:
		return _urban_block(lot,w,d)
	var h:=floors*2.65+.48
	var g=Forms.new(true)
	var yard_color:=Color("#98a46c") if use==0 else Color("#b4a88f")
	g.finish=Forms.Finish.MEADOW if use==0 else Forms.Finish.WALK
	g.box(Vector3(0,-.24,0),Vector3(w+1.85,.52,d+1.95),yard_color)
	var wall:=Color(WALLS[s%WALLS.size()])
	var roof:=Color(ROOFS[(s/7)%ROOFS.size()])
	g.box(Vector3(0,-.22,0),Vector3(w+1.1,.94,d+1),Color("#a59b85"))
	g.finish=Forms.Finish.BRICK if use==1 or s%3==0 else Forms.Finish.PLASTER
	g.box(Vector3(0,h*.5,0),Vector3(w,h,d),wall)
	g.finish=Forms.Finish.PLAIN
	for floor_index in floors:
		var y:=floor_index*2.65+1.55
		for side in [-1,1]:
			for k in range(3):
				var x:float=(k-1)*w*.30
				if floor_index==0 and use==1 and side==lot.front_sign: continue
				if floor_index==0 and k==1:
					g.box(Vector3(x,.99,side*(d*.5+.055)),Vector3(.92,1.87,.12),Color("#65716b"))
				else:
					g.finish=Forms.Finish.GLASS
					g.box(Vector3(x,y,side*(d*.5+.055)),Vector3(1.03,1.12,.13),Color("#567078"))
					g.finish=Forms.Finish.PLAIN
					g.box(Vector3(x,y-.60,side*(d*.5+.1)),Vector3(1.24,.10,.23),Color("#ada99f"))
					g.box(Vector3(x,y,side*(d*.5+.135)),Vector3(.046,1.17,.04),Color("#a6a49c"))
					g.box(Vector3(x,y+.18,side*(d*.5+.135)),Vector3(1.10,.055,.04),Color("#a6a49c"))
			for k in [-1,1]:
				g.finish=Forms.Finish.GLASS
				g.box(Vector3(side*(w*.5+.04),y,k*d*.22),Vector3(.12,1.12,.94),Color("#627b7b"))
				g.finish=Forms.Finish.PLAIN
				g.box(Vector3(side*(w*.5+.11),y+.13,k*d*.22),Vector3(.05,.047,1.0),Color("#9d9c94"))
				g.box(Vector3(side*(w*.5+.10),y-.60,k*d*.22),Vector3(.19,.11,1.10),Color("#a19e92"))
	if use==0:
		if s%4==0:
			g.box(Vector3(w*.28,h*.32,d*.46),Vector3(w*.42,h*.64,d*.42),wall)
			g.box(Vector3(w*.28,h*.65,d*.46),Vector3(w*.49,.26,d*.47),roof)
		if s%3==1:
			_hip_roof(g,w,d,h,roof)
		else:
			_gable(g,w,d,h,roof,wall)
		g.finish=Forms.Finish.BRICK
		g.box(Vector3(w*.25,h+1.20,-d*.2),Vector3(.58,1.95,.62),Color("#a08777"))
		g.finish=Forms.Finish.PLAIN
		g.box(Vector3(w*.25,h+2.19,-d*.2),Vector3(.72,.13,.76),Color("#8c8a7e"))
		for eave in [-1,1]:
			g.box(Vector3(0,h-.09,eave*(d*.5+.40)),Vector3(w+.86,.15,.16),Color("#676b68"))
			g.box(Vector3(w*.46,h*.5,eave*(d*.5+.10)),Vector3(.10,h,.12),Color("#777b75"))
	elif use==1:
		g.finish=Forms.Finish.FELT
		g.box(Vector3(0,h+.12,0),Vector3(w+.18,.25,d+.18),Color("#686b68"))
		g.finish=Forms.Finish.PLAIN
		for sign_z in [-1,1]:
			g.box(Vector3(0,h+.37,sign_z*d*.5),Vector3(w+.26,.47,.18),Color("#898980"))
			g.box(Vector3(0,h+.64,sign_z*d*.5),Vector3(w+.4,.09,.30),Color("#afa99c"))
		for sign_x in [-1,1]:
			g.box(Vector3(sign_x*w*.5,h+.37,0),Vector3(.17,.47,d+.18),Color("#898980"))
			g.box(Vector3(sign_x*w*.5,h+.64,0),Vector3(.28,.09,d+.21),Color("#afa99c"))
		g.finish=Forms.Finish.FELT
		g.box(Vector3(0,h+.24,0),Vector3(w-.32,.08,d-.32),Color("#666961"))
		g.finish=Forms.Finish.PLAIN
		g.box(Vector3(-w*.24,h+.64,d*.18),Vector3(1.38,.67,.99),Color("#919892"))
		for k in 8:
			g.box(Vector3(-w*.24-.51+k*.14,h+.65,d*.18+.50),Vector3(.056,.46,.028),Color("#4f5856"))
		g.taper(Vector3(-w*.24,h+.98,d*.18),.32,.32,.047,14,Color("#535c58"))
		g.taper(Vector3(w*.30,h+.27,-d*.21),.095,.095,.82,10,Color("#757b75"))
		g.taper(Vector3(w*.30,h+1.09,-d*.21),.17,.095,.12,10,Color("#a1a59c"))

	else:
		_gable(g,w,d,h,Color("#698181"),wall)
		g.taper(Vector3(w*.34,h-.5,0),.46,.33,3.0,8,Color("#a9775e"))
	if use==1 and not market_hall_built:
		market_hall_built=true
		# Stepped masonry parapet on the oldest shop on the high street.
		var face:float=int(lot.front_sign)*(d*.5-.07)
		g.finish=Forms.Finish.BRICK
		for k in 3:
			g.box(Vector3(0,h+.31+k*.25,face),Vector3(w*(.91-k*.22),.32,.28),wall)
			g.box(Vector3(0,h+.49+k*.25,face),Vector3(w*(.91-k*.22)+.10,.065,.36),Color("#a49e91"))
		g.finish=Forms.Finish.PLAIN
	if use==0:
		_home_front(g,lot,w,d)
	_street_furniture(g,lot,w,d)
	var site=g.attach(self)
	site.position=lot.pos
	site.rotation.y=lot.yaw
	_add_shop_sign(site,lot,d)
	if use==0:
		if lot.style%4!=0:
			var sapling:=MeshInstance3D.new()
			if not street_crown: street_crown=preload("res://scripts/landscape.gd").crown_mesh(preload("res://art/deciduous.png"),4.4)
			sapling.mesh=street_crown
			sapling.position=Vector3(-w*.40,.13,-lot.front_sign*(d*.5+.32))
			sapling.scale=Vector3.ONE*(.71+.12*(lot.style%5))
			site.add_child(sapling)
		if lot.style%3==0:
			var parked:=MeshInstance3D.new()
			parked.mesh=car_meshes[lot.style%car_meshes.size()]
			parked.position=Vector3(w*.5+1.05,.24,0)
			parked.rotation.y=PI*.5
			site.add_child(parked)
	land.clear_lot(lot.pos)
	return site

func _home_front(g,lot:Dictionary,w:float,d:float) -> void:
	var side:int=lot.front_sign
	var z:float=side*(d*.5+1.)
	g.finish=Forms.Finish.WALK
	g.box(Vector3(0,.21,side*(d*.5+1.44)),Vector3(1.2,.24,2.88),Color("#aba599"))
	g.box(Vector3(0,.42,z-side*.35),Vector3(2.24,.44,1.58),Color("#a39c8c"))
	g.finish=Forms.Finish.PLAIN
	for post in [-.94,.94]:
		g.box(Vector3(post,1.40,z+side*.36),Vector3(.11,1.97,.11),Color("#aaa99f"))
	g.box(Vector3(0,2.42,z),Vector3(2.42,.17,1.83),Color("#656966"))
	var back:float=-side*(d*.5+.83)
	var wood:=Color("#8b8372")
	for slat in 19:
		var x:float=(slat-9)*w/20.
		g.box(Vector3(x,.50,back),Vector3(w/24.,.94,.085),wood)
	for rail in [.31,.74]:
		g.box(Vector3(0,rail,back-side*.07),Vector3(w*.96,.10,.072),Color("#786f5e"))
	var wing:float=-w*.5-.53
	for rail in [.4,.75]: g.box(Vector3(wing,rail,0),Vector3(.065,.065,d+1.6),Color("#787e74"))
	for post in [-1,0,1]: g.box(Vector3(wing,.43,post*(d*.5+.8)),Vector3(.093,.86,.093),Color("#73796e"))
	if lot.floors>=2 and lot.style%3!=0:
		var bx:float=w*.27
		g.box(Vector3(bx,3.04,z-side*.46),Vector3(2.14,.17,1.17),Color("#9b988d"))
		g.box(Vector3(bx,3.99,z+side*.08),Vector3(2.09,.073,.06),Color("#484e4e"))
		for bar in 8:
			g.box(Vector3(bx-.98+bar*.28,3.53,z+side*.08),Vector3(.038,.92,.04),Color("#525b59"))

func _hip_roof(g,w:float,d:float,h:float,roof:Color) -> void:
	var x:=w*.5+.35
	var z:=d*.5+.39
	var left:=Vector3(-w*.23,h+1.94,0)
	var right:=Vector3(w*.23,h+1.94,0)
	g.finish=Forms.Finish.SLATE
	for side in [-1,1]:
		g.quad(Vector3(-x,h,side*z),Vector3(x,h,side*z),right,left,roof,Vector3.UP)
		g.triangle(Vector3(side*x,h,z),Vector3(side*x,h,-z),left if side<0 else right,roof,Vector3.UP)
	g.finish=Forms.Finish.PLAIN

func _gable(g,w:float,d:float,h:float,roof:Color,wall:Color,industrial:=false) -> void:
	var ridge:=h+1.65
	for sign_x in [-1,1]:
		var x:float=sign_x*w*.5
		g.triangle(Vector3(x,h,-d*.5),Vector3(x,ridge,0),Vector3(x,h,d*.5),wall,Vector3.RIGHT*sign_x)
	g.finish=Forms.Finish.METAL if industrial else Forms.Finish.SLATE
	for sign_z in [-1,1]:
		var z:float=sign_z*(d*.5+.42)
		var x:=w*.5+.37
		g.quad(Vector3(-x,h-.14,z),Vector3(x,h-.14,z),Vector3(x,ridge,0),Vector3(-x,ridge,0),roof,Vector3.UP)

	g.finish=Forms.Finish.PLAIN

func _urban_block(lot:Dictionary,w:float,d:float) -> MeshInstance3D:
	var g=Forms.new(true)
	var s:int=lot.style
	var floors:int=lot.floors
	var height:=floors*2.8
	var facade:=Color(["#c5b39a","#d0c6af","#b49377","#c8cfc2"][s%4])
	g.box(Vector3(0,-.13,0),Vector3(w+2.3,.8,d+2.0),Color("#aba594"))
	if lot.use==2:
		# Riverside sheds have wide loading doors, roof monitors and exhaust stacks.
		g.finish=Forms.Finish.METAL
		g.box(Vector3(0,2.15,0),Vector3(w+1.2,4.3,d+.8),Color("#a5aa98"))
		_gable(g,w+1.2,d+.8,4.3,Color("#77807f"),facade,true)
		var front:float=lot.front_sign*(d*.5+.44)
		for x in [-1,1]:
			g.box(Vector3(x*w*.23,1.49,front),Vector3(2.66,2.98,.13),Color("#4b5552"))
			for slat in 13:
				g.box(Vector3(x*w*.23,.24+slat*.20,front+lot.front_sign*.085),Vector3(2.43,.16,.045),Color("#737c77"))
			g.finish=Forms.Finish.GLASS
			g.box(Vector3(x*w*.23,2.35,front+lot.front_sign*.11),Vector3(1.76,.27,.04),Color("#485e63"))
		g.finish=Forms.Finish.PLAIN
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
		g.finish=Forms.Finish.BRICK
		g.box(Vector3(0,2,0),Vector3(w+1.2,4,d+1),facade)
		for side in [-1,1]:
			g.finish=Forms.Finish.GLASS
			g.box(Vector3(0,1.7,side*(d*.5+.55)),Vector3(w*.84,2.3,.14),glass)
		var body_w:=w*(.90 if tower else 1.)
		var body_d:=d*(.88 if tower else 1.)
		g.finish=Forms.Finish.GLASS if tower else Forms.Finish.PLASTER
		g.box(Vector3(0,(height+4)*.5,0),Vector3(body_w,height-4,body_d),glass if tower else facade)
		g.finish=Forms.Finish.PLAIN
		for level in range(2,floors):
			var y:=level*2.8+.35
			if tower:
				var band_height:float=.13 if s%3==0 else (.26 if s%3==1 else .17)
				var band_color:Color=facade if s%3!=0 else Color("#717c7f")
				g.box(Vector3(0,y,0),Vector3(body_w+.13,band_height,body_d+.13),band_color)
				if lot.use==0 and level%2==0:
					var bx:float=body_w*.14*(1 if level%4 else -1)
					var bz:float=lot.front_sign*(body_d*.5+.41)
					g.box(Vector3(bx,y+.03,bz),Vector3(body_w*.48,.16,1.02),Color("#b3aea2"))
					g.box(Vector3(bx,y+.57,bz+lot.front_sign*.44),Vector3(body_w*.47,.78,.075),Color("#84918d"))
					g.box(Vector3(bx,y+.99,bz+lot.front_sign*.44),Vector3(body_w*.48,.052,.095),Color("#565e60"))
			else:
				for side in [-1,1]:
					g.finish=Forms.Finish.GLASS
					g.box(Vector3(0,y,side*(body_d*.5+.04)),Vector3(body_w*.88,1.28,.14),glass)
					g.box(Vector3(side*(body_w*.5+.04),y,0),Vector3(.14,1.28,body_d*.74),glass)
		g.finish=Forms.Finish.PLAIN
		if not tower:
			for side in [-1,1]:
				for bay in [-.25,0.,.25]:
					g.box(Vector3(bay*body_w,(height+4)*.5,side*(body_d*.5+.14)),Vector3(.21,height-4,.16),facade)
		if tower:
			for side in [-1,1]:
				g.box(Vector3(side*body_w*.5,(height+4)*.5,-body_d*.28),Vector3(.3,height-4,.57),facade)
			if s%3==1:
				for k in range(-2,3):
					for side in [-1,1]:
						g.box(Vector3(k*body_w*.18,(height+4)*.5,side*(body_d*.5+.11)),Vector3(.075,height-4,.17),Color("#89908f"))
			if s%2==0:
				var crown_h:=1.6+(s%4)*.5
				g.finish=Forms.Finish.METAL
				g.box(Vector3(0,height+crown_h*.5,0),Vector3(body_w*.72,crown_h,body_d*.72),glass)
				g.finish=Forms.Finish.PLAIN
				for k in range(5):
					g.box(Vector3(0,height+.40+.19*k,body_d*.36+.04),Vector3(body_w*.50,.09,.11),Color("#414b4c"))
				g.box(Vector3(0,height+crown_h+.12,0),Vector3(body_w*.74,.32,body_d*.74),facade)
		g.box(Vector3(0,height+.18,0),Vector3(body_w+.35,.44,body_d+.35),facade)
		g.box(Vector3(-.52,height+.91,0),Vector3(body_w*.52,1.4,body_d*.48),Color("#929c95"))
		for unit in range(2):
			g.box(Vector3(body_w*.27,height+.56,(unit-.5)*body_d*.46),Vector3(.91,.76,1.27),Color("#87948e"))
		if tower and s%3==0:
			g.taper(Vector3(-.5,height+1.6,0),.18,.04,3.2,6,facade)
	_street_furniture(g,lot,w,d)
	var site=g.attach(self)
	site.position=lot.pos
	site.rotation.y=lot.yaw
	_add_shop_sign(site,lot,d)
	land.clear_lot(lot.pos)
	return site


func _street_furniture(g,lot:Dictionary,w:float,d:float) -> void:
	var side:int=lot.front_sign
	var front:=side*(d*.5+.75)
	if lot.use==1:
		# Shopfronts face the same sidewalk that customers and staff use.
		var fabric:=Color(["#935d51","#506e67","#947e51"][lot.style%3])
		var frame:=Color("#49504d")
		var plane:float=side*(d*.5+.21)
		g.finish=Forms.Finish.PLAIN
		g.box(Vector3(0,1.44,plane),Vector3(w*.94,2.65,.26),frame)
		for bay in 5:
			var x:float=(bay-2)*w*.177
			var is_door:=bay==2
			var y:=1.23 if is_door else 1.39
			var opening:=2.04 if is_door else 1.52
			g.finish=Forms.Finish.GLASS
			g.box(Vector3(x,y,plane+side*.14),Vector3(w*.165,opening,.045),Color("#59716f"))
			g.finish=Forms.Finish.PLAIN
			g.box(Vector3(x,2.22,plane+side*.18),Vector3(w*.169,.045,.08),Color("#8b8a79"))
			g.box(Vector3(x,2.39,plane+side*.15),Vector3(w*.162,.26,.07),Color("#9fa9a0"))
			if is_door:
				g.box(Vector3(x+w*.060,1.22,plane+side*.22),Vector3(.035,.38,.07),Color("#c7c4b5"))
			else:
				g.box(Vector3(x,.46,plane+side*.18),Vector3(w*.169,.23,.12),Color("#636862"))
		g.box(Vector3(0,2.89,plane),Vector3(w*.99,.51,.33),Color("#394842"))
		g.box(Vector3(0,3.18,plane),Vector3(w*1.01,.085,.40),Color("#aea492"))
		for i in 10:
			var x0:float=-w*.49+w*.098*i
			var x1:float=x0+w*.098
			var inner:=plane+side*.20
			var outer:=front+side*.58
			var cloth:=fabric if i%2==0 else fabric.lightened(.36)
			g.quad(Vector3(x0,2.66,inner),Vector3(x1,2.66,inner),Vector3(x1,2.32,outer),Vector3(x0,2.32,outer),cloth,Vector3.UP)
			g.box(Vector3((x0+x1)*.5,2.25,outer),Vector3(x1-x0,.15,.04),cloth.darkened(.10))
		for x in [-1,1]:
			var table:=Vector3(x*w*.29,0,front+side*1.05)
			g.taper(table,.10,.10,.76,6,Color("#645b49"))
			g.taper(table+Vector3.UP*.76,.53,.53,.12,10,Color("#b99160"))
			for chair in [-1,1]:
				g.box(table+Vector3(chair*.77,.42,0),Vector3(.4,.16,.43),fabric)
				g.box(table+Vector3(chair*.77,.22,0),Vector3(.15,.42,.15),Color("#645b49"))
	elif lot.use==0:
		g.box(Vector3(w*.36,.62,front),Vector3(.16,1.2,.16),Color("#876e55"))
		g.box(Vector3(w*.36,1.22,front),Vector3(.44,.34,.44),Color("#7d8a79"))

func _add_shop_sign(site:MeshInstance3D,lot:Dictionary,d:float) -> void:
	if lot.use==0: return
	var sign:=Label3D.new()
	var names:=["BAKERY","CAFÉ","GROCER","OUTFITTER"] if lot.use==1 else ["FLOUR MILL","FOOD CO-OP","CREAMERY","TEXTILE MILL"]
	sign.text=names[lot.style%4]
	sign.font_size=44
	sign.pixel_size=.012
	sign.outline_size=1
	sign.modulate=Color("#fff1ce")
	sign.outline_modulate=Color("#35483d")
	sign.double_sided=false
	sign.position=Vector3(0,2.90 if lot.use==1 else 3.40,int(lot.front_sign)*(d*.5+(.40 if lot.use==1 else .75)))
	if lot.front_sign<0: sign.rotation.y=PI
	site.add_child(sign)
