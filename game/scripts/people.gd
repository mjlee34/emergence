extends Node3D
const BuildingWorks=preload("res://scripts/building_works.gd")
const Forms=preload("res://scripts/forms.gd")
const RESIDENTS = [
	preload("res://art/residents/Male_Adult_01.glb"), preload("res://art/residents/Female_Adult_03.glb"),
	preload("res://art/residents/Male_Adult_04.glb"), preload("res://art/residents/Female_Adult_02.glb"),
	preload("res://art/residents/Male_Adult_03.glb"), preload("res://art/residents/Female_Adult_01.glb"),
	preload("res://art/residents/Male_Adult_05.glb"), preload("res://art/residents/Female_Adult_04.glb")
]
var groups:Array[MultiMesh]=[]
var fabrics:Array[ShaderMaterial]=[]
var ids:=PackedInt32Array()
var poses:=PackedVector4Array()
var modes:=PackedInt32Array()
var umbrellas:Array[MultiMesh]=[]
var marker:=MeshInstance3D.new()
var parcels:=MultiMesh.new()
var bags:=MultiMesh.new()

func _ready() -> void:
	for scene:PackedScene in RESIDENTS:
		var paint:=ShaderMaterial.new()
		paint.shader=preload("res://scripts/walkers.gdshader")
		paint.set_shader_parameter("clothing", load(scene.resource_path.get_basename()+".png"))
		fabrics.append(paint)
		var batch:=MultiMesh.new()
		batch.transform_format=MultiMesh.TRANSFORM_3D
		batch.use_custom_data=true
		batch.mesh=Forms.imported_mesh(scene)
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
	for fabric in ["#355969","#aa6d41","#566d59","#804c53"]:
		var g=Forms.new()
		var tint:=Color(fabric)
		for j in 10:
			var a:=TAU*j/10.
			var b:=TAU*(j+1)/10.
			var da:=Vector3(cos(a),0,sin(a))
			var db:=Vector3(cos(b),0,sin(b))
			var peak:=Vector3(.08,2.21,0)
			var ring_a:=peak+da*.35-Vector3.UP*.07
			var ring_b:=peak+db*.35-Vector3.UP*.07
			var edge_a:=peak+da*.61-Vector3.UP*.23
			var edge_b:=peak+db*.61-Vector3.UP*.23
			var panel:=tint.lightened(.065) if j%2 else tint
			g.triangle(peak,ring_a,ring_b,panel,Vector3.UP)
			g.quad(ring_a,ring_b,edge_b,edge_a,panel,Vector3.UP)
		g.beam(Vector3(.08,1.30,0),Vector3(.08,2.22,0),.023,Color("#454b49"))
		var batch:=MultiMesh.new()
		batch.transform_format=MultiMesh.TRANSFORM_3D
		batch.mesh=g.mesh()
		var holder:=MultiMeshInstance3D.new()
		holder.multimesh=batch
		add_child(holder)
		umbrellas.append(batch)
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

func sync(model,orbit,state:Dictionary,fraction:float,selected:int,rain:float) -> void:
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
	var open_counts:=PackedInt32Array([0,0,0,0])
	if rain>.035:
		for i in ids.size():
			var id:=ids[i]
			if _has_umbrella(id,modes[i],rain): open_counts[id%4]+=1
	for k in umbrellas.size():
		if umbrellas[k].instance_count<open_counts[k]: umbrellas[k].instance_count=maxi(8,open_counts[k])
		umbrellas[k].visible_instance_count=open_counts[k]
	open_counts.fill(0)
	var bag_index:=0
	var load_index:=0
	for i in ids.size():
		var id:=ids[i]
		var k:=id%groups.size()
		var p:=poses[i]
		var scale_factor:=(1.0+.035*(id%5))*(.67 if data.children[i] else 1.)
		var transform3:=Transform3D(Basis(Vector3.UP,p.w).scaled(Vector3.ONE*scale_factor),Vector3(p.x,p.y+.055,p.z))
		groups[k].set_instance_transform(counts[k],transform3)
		groups[k].set_instance_custom_data(counts[k],Color((id%71)/71.,data.motion[i].x,data.motion[i].y,1))
		counts[k]+=1
		if _has_umbrella(id,modes[i],rain):
			umbrellas[id%4].set_instance_transform(open_counts[id%4],transform3)
			open_counts[id%4]+=1
		if bag_flags[i]:
			bags.set_instance_transform(bag_index,transform3.translated_local(Vector3(.34,.59,.045)))
			bag_index+=1
		if modes[i]==1:
			parcels.set_instance_transform(load_index,transform3.translated_local(Vector3(0,1.04,.29)))
			load_index+=1
	for fabric in fabrics: fabric.set_shader_parameter("simulation_tick",fmod(state.tick+fraction,TAU*100/1.75))
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
		marker.position=r.position+Vector3.UP*(3.45 if r.activity==5 else 1.96) if r.activity in [5,6] else b.pos+Vector3.UP*.49
		if r.activity==8: marker.position=r.position+Vector3.UP*.49
		marker.scale=Vector3(1.22,.65,1.22) if r.activity in [5,6] else Vector3(7.,1.,7.)
		marker.visible=true

func _has_umbrella(id:int,activity:int,rain:float) -> bool:
	return (activity==3 or activity==4) and rain>.035+float((id*31)%97)/135.

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
