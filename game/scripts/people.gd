extends Node3D
const BuildingWorks=preload("res://scripts/building_works.gd")
const Forms=preload("res://scripts/forms.gd")
const COATS=["#935d50","#546877","#ac9361","#596c59","#b6afa0","#6b535e","#597478","#886c57"]
var groups:Array[MultiMesh]=[]
var paint:=ShaderMaterial.new()
var ids:=PackedInt32Array()
var poses:=PackedVector4Array()
var modes:=PackedInt32Array()
var marker:=MeshInstance3D.new()
var parcels:=MultiMesh.new()
var bags:=MultiMesh.new()

func _ready() -> void:
	paint.shader=preload("res://scripts/walkers.gdshader")
	for i in COATS.size():
		var g=Forms.new()
		var coat:=Color(COATS[i])
		var skin:=Color(["#e3b892","#b88564","#805b49","#c99770"][i%4])
		var trousers:=Color(["#394d59","#514d49","#485775"][i%3])
		for side in [-1,1]:
			var leg:=Vector3(side*.105,0,0)
			g.profile(leg,[Vector3(.068,.10,.08),Vector3(.077,.44,.083),Vector3(.11,.80,.12),Vector3(.11,.91,.13)],trousers,8)
			g.profile(leg+Vector3(0,0,.046),[Vector3(.083,.025,.145),Vector3(.087,.088,.15),Vector3(.065,.16,.093)],Color("#46413c"),8)
			var arm:=Vector3(side*.235,0,0)
			g.profile(arm,[Vector3(.048,.87,.064),Vector3(.068,1.09,.078),Vector3(.086,1.36,.093),Vector3(.043,1.43,.07)],coat,8)
			g.profile(arm,[Vector3(.036,.77,.04),Vector3(.053,.815,.056),Vector3(.047,.89,.05)],skin,8)
		g.profile(Vector3.ZERO,[Vector3(.190,.78,.136),Vector3(.204,.91,.146),Vector3(.164,1.06,.127),Vector3(.22,1.31,.15),Vector3(.196,1.41,.113),Vector3(.074,1.46,.085)],coat)
		g.profile(Vector3.ZERO,[Vector3(.06,1.41,.065),Vector3(.06,1.50,.066),Vector3(.086,1.515,.087),Vector3(.112,1.61,.103),Vector3(.118,1.71,.11),Vector3(.081,1.765,.085)],skin)
		g.profile(Vector3(0,0,-.012),[Vector3(.117,1.65,.106),Vector3(.12,1.71,.11),Vector3(.096,1.757,.093),Vector3(.047,1.779,.05)],Color("#53453a") if i%3 else Color("#37322d"))
		if i%3==1:
			g.profile(Vector3.ZERO,[Vector3(.132,1.71,.14),Vector3(.113,1.742,.115),Vector3(.073,1.785,.083)],coat)
		if i%3==0: g.profile(Vector3(0,0,-.145),[Vector3(.104,.97,.072),Vector3(.14,1.05,.089),Vector3(.13,1.30,.08),Vector3(.088,1.34,.06)],Color("#695c4a"))
		var batch:=MultiMesh.new()
		batch.transform_format=MultiMesh.TRANSFORM_3D
		batch.use_custom_data=true
		batch.mesh=g.mesh()
		var node:=MultiMeshInstance3D.new()
		node.multimesh=batch
		node.material_override=paint
		add_child(node)
		groups.append(batch)
	var carton:=BoxMesh.new()
	carton.size=Vector3(.47,.31,.38)
	var kraft:=StandardMaterial3D.new()
	kraft.albedo_color=Color("#be945f")
	carton.material=kraft
	parcels.transform_format=MultiMesh.TRANSFORM_3D
	parcels.mesh=carton
	var loads:=MultiMeshInstance3D.new()
	loads.multimesh=parcels
	add_child(loads)
	var bag=Forms.new()
	bag.box(Vector3.ZERO,Vector3(.30,.37,.23),Color("#d99249"))
	for x in [-.095,.095]:
		bag.box(Vector3(x,.23,0),Vector3(.033,.14,.04),Color("#65553d"))
	bag.box(Vector3(0,.3,0),Vector3(.20,.04,.04),Color("#65553d"))
	bags.transform_format=MultiMesh.TRANSFORM_3D
	bags.mesh=bag.mesh()
	var bag_batch:=MultiMeshInstance3D.new()
	bag_batch.multimesh=bags
	add_child(bag_batch)
	var ring:=TorusMesh.new()
	ring.inner_radius=.68
	ring.outer_radius=.83
	ring.rings=24
	ring.ring_segments=6
	marker.mesh=ring
	var mat:=StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color=Color("#ffd174")
	marker.material_override=mat
	marker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible=false
	add_child(marker)

func sync(model,orbit,state:Dictionary,fraction:float,selected:int) -> void:
	var data:Dictionary=model.street_people(fraction,Vector2(orbit.pivot.x,orbit.pivot.z),orbit.extent*1.7+15,selected)
	ids=data.ids
	poses=data.poses
	modes=data.modes
	var counts:=PackedInt32Array()
	counts.resize(groups.size())
	for id in ids: counts[id%groups.size()]+=1
	for k in groups.size():
		if counts[k]>groups[k].instance_count: groups[k].instance_count=maxi(16,ceili(counts[k]/16.)*16)
		groups[k].visible_instance_count=counts[k]
	counts.fill(0)
	var carrying:=modes.count(1)
	if parcels.instance_count<carrying: parcels.instance_count=carrying
	parcels.visible_instance_count=carrying
	var bag_flags:PackedInt32Array=data.bags
	var bag_count:=bag_flags.count(1)
	if bags.instance_count<bag_count: bags.instance_count=bag_count
	bags.visible_instance_count=bag_count
	var bag_index:=0
	var load_index:=0
	for i in ids.size():
		var id:=ids[i]
		var k:=id%groups.size()
		var p:=poses[i]
		var scale_factor:=1.0+.035*(id%5)
		var transform3:=Transform3D(Basis(Vector3.UP,p.w).scaled(Vector3.ONE*scale_factor),Vector3(p.x,p.y+.055,p.z))
		groups[k].set_instance_transform(counts[k],transform3)
		groups[k].set_instance_custom_data(counts[k],Color((id%71)/71.,1 if modes[i]==3 else (.35 if modes[i]==1 else 0),0,1))
		counts[k]+=1
		if bag_flags[i]:
			bags.set_instance_transform(bag_index,transform3.translated_local(Vector3(.34,.59,.045)))
			bag_index+=1
		if modes[i]==1:
			parcels.set_instance_transform(load_index,transform3.translated_local(Vector3(0,1.04,.29)))
			load_index+=1
	paint.set_shader_parameter("simulation_tick",fmod(state.tick+fraction,TAU*100/1.75))
	marker.visible=false
	marker.scale=Vector3.ONE
	var index:=ids.find(selected)
	if index>=0:
		var p:=poses[index]
		marker.position=Vector3(p.x,p.y+.09,p.z)
		marker.visible=true
	elif selected>=0:
		var r:Dictionary=model.resident(selected,fraction)
		var b:Dictionary=model.lot(r.target)
		marker.position=b.pos+Vector3.UP*.49
		marker.scale=Vector3(7.,1.,7.)
		marker.visible=true

func pick(camera:Camera3D,screen:Vector2,sites:Array[MeshInstance3D]) -> int:
	var best:=-1
	var threshold:=clampf(620./camera.size,7,20)
	for i in ids.size():
		var p:=poses[i]
		var center:=camera.unproject_position(Vector3(p.x,p.y+1.05,p.z))
		var distance:=center.distance_to(screen)
		if distance<threshold and _in_sight(camera,Vector3(p.x,p.y+1.05,p.z),sites):
			best=ids[i]
			threshold=distance
	return best

func _in_sight(camera:Camera3D,target:Vector3,sites:Array[MeshInstance3D]) -> bool:
	var start:=camera.project_ray_origin(camera.unproject_position(target))
	var dir:=camera.project_ray_normal(camera.unproject_position(target))
	var depth:=start.distance_to(target)
	for site in sites:
		var inverse:=site.global_transform.affine_inverse()
		var hit=BuildingWorks.visible_bounds(site).intersects_ray(inverse*start,inverse.basis*dir)
		if hit!=null and start.distance_to(site.global_transform*hit)<depth-.5:
			return false
	return true
