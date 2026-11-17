extends Node3D
const Forms=preload("res://scripts/forms.gd")
const TEAL:=Color("#397d79")
const CREAM:=Color("#e7e2ce")
const GLASS:=Color("#43595e")
const DARK:=Color("#303f42")
const LED:=Color("#ffca65")
var network:Dictionary
var service:Dictionary
var buses:Array[Node3D]=[]
var doors:Array[MeshInstance3D]=[]
var cars:Dictionary={}

func _sign(parent:Node3D,caption:String,p:Vector3,yaw:float,pixel:float,colour:Color) -> void:
	var text:=Label3D.new()
	text.text=caption
	text.font_size=40
	text.pixel_size=pixel
	text.modulate=colour
	text.outline_size=0
	text.position=p
	text.rotation.y=yaw
	text.double_sided=false
	parent.add_child(text)

func create(model) -> void:
	network=model.bus_network()
	var shell=Forms.new()
	shell.box(Vector3(0,.85,0),Vector3(7.46,.82,2.22),TEAL)
	shell.box(Vector3(0,1.73,0),Vector3(7.36,1.03,2.19),GLASS)
	shell.box(Vector3(0,2.49,0),Vector3(7.43,.53,2.25),CREAM)
	shell.box(Vector3(-.71,2.85,0),Vector3(2.33,.25,1.44),Color("#aaa99b"))
	for side in [-1,1]:
		for x in [-3.56,-2.61,-1.66,-.71,.24,1.19,2.14,3.56]:
			shell.box(Vector3(x,1.78,side*1.101),Vector3(.085,1.01,.032),DARK)
		shell.box(Vector3(0,1.31,side*1.113),Vector3(7.36,.10,.036),CREAM)
		shell.box(Vector3(0,.68,side*1.114),Vector3(7.39,.10,.035),Color("#a9c7ad"))
		for x in [-2.35,2.27]: shell.wheel(Vector3(x,.48,side*1.04),.47,side)
		shell.box(Vector3(3.735,.83,side*.79),Vector3(.04,.18,.41),Color("#fff2c9"))
		shell.box(Vector3(-3.735,.89,side*.94),Vector3(.04,.28,.12),Color("#b75744"))
	shell.box(Vector3(3.722,2.45,0),Vector3(.045,.38,1.96),DARK)
	shell.box(Vector3(-1.73,2.48,1.135),Vector3(2.79,.36,.045),DARK)
	shell.box(Vector3(2.64,1.50,1.135),Vector3(1.23,1.93,.04),DARK)
	var mesh=shell.mesh()
	var leaf=Forms.new()
	leaf.box(Vector3.ZERO,Vector3(.60,1.88,.052),TEAL)
	leaf.box(Vector3(0,.25,.031),Vector3(.49,1.15,.025),GLASS)
	var door_mesh=leaf.mesh()
	for id in network.fleet:
		var bus:=Node3D.new()
		bus.scale.z=.93
		var body:=MeshInstance3D.new()
		body.mesh=mesh
		bus.add_child(body)
		for j in 2:
			var door:=MeshInstance3D.new()
			door.mesh=door_mesh
			bus.add_child(door)
			doors.append(door)
		_sign(bus,"1  TOWN LOOP",Vector3(3.76,2.45,0),PI*.5,.0061,LED)
		_sign(bus,"1   TOWN LOOP",Vector3(-1.73,2.48,1.168),0,.0070,LED)
		add_child(bus)
		buses.append(bus)
	for i in network.stops.size(): _shelter(network.stops[i],i)

func _shelter(stop:Dictionary,index:int) -> void:
	var node:=Node3D.new()
	add_child(node)
	node.position=stop.position
	node.rotation.y=stop.yaw
	var g=Forms.new()
	for x in [-1.7,1.7]:
		g.box(Vector3(x,1.16,1.14),Vector3(.095,2.32,.10),DARK)
	g.box(Vector3(0,2.35,.77),Vector3(3.89,.15,1.48),TEAL)
	g.box(Vector3(-.22,.59,.98),Vector3(2.48,.14,.43),CREAM)
	for x in [-1.13,.69]: g.box(Vector3(x,.31,.99),Vector3(.09,.62,.25),DARK)
	g.box(Vector3(2.16,1.32,.42),Vector3(.07,2.65,.07),DARK)
	g.box(Vector3(2.16,2.36,.42),Vector3(.66,.80,.09),TEAL)
	g.box(Vector3(2.16,1.57,.42),Vector3(.39,.51,.10),CREAM)
	g.attach(node)
	_sign(node,"1",Vector3(2.16,2.37,.48),0,.016,Color.WHITE)
	_sign(node,"1",Vector3(2.16,2.37,.36),PI,.016,Color.WHITE)
	var caption:="%02d   %s"%[index+1,stop.name.to_upper()]
	_sign(node,caption,Vector3(0,2.34,.015),PI,.0036,Color.WHITE)

func sync(model,town,fraction:float) -> void:
	service=model.mobility(fraction)
	for i in service.buses.size():
		var row:Dictionary=service.buses[i]
		var p:Vector4=row.pose
		buses[i].position=Vector3(p.x,p.y+.4,p.z)
		buses[i].rotation.y=p.w
		for j in 2:
			var side:=2*j-1
			doors[i*2+j].position=Vector3(2.64+side*(.31+.55*row.door_open),1.5,1.17)
	var current:Dictionary={}
	for i in service.drivers.size():
		var id:int=service.drivers[i]
		current[id]=true
		if not cars.has(id):
			var car:=MeshInstance3D.new()
			car.mesh=town.car_meshes[id%town.car_meshes.size()]
			add_child(car)
			cars[id]=car
		var p:Vector4=service.cars[i]
		cars[id].position=Vector3(p.x,p.y+.32,p.z)
		cars[id].rotation.y=p.w
	for id in cars.keys():
		if not current.has(id):
			cars[id].queue_free()
			cars.erase(id)

func pick(camera:Camera3D,screen:Vector2,people,sites:Array[MeshInstance3D]) -> Vector2i:
	var closest:=INF
	var choice:=Vector2i(-1,-1)
	for kind in 2:
		var keys:Array=cars.keys() if kind==0 else range(buses.size())
		for id in keys:
			var target:Node3D=cars[id] if kind==0 else buses[id]
			var pos:=target.position+Vector3.UP*(1.2 if kind==0 else 2.0)
			if camera.is_position_behind(pos): continue
			var separation:=screen.distance_to(camera.unproject_position(pos))
			if separation>clampf((1150. if kind==0 else 2000.)/camera.size,6.,28.) or separation>=closest: continue
			if not people._in_sight(camera,pos,sites): continue
			closest=separation
			choice=Vector2i(kind,id)
	return choice
