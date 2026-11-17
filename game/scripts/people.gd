extends Node3D
const Forms=preload("res://scripts/forms.gd")
const COATS=["#d86a47","#558caf","#d7b54d","#70885b","#e4d4b8","#995b70","#61a8a1","#cb915b"]
var groups:Array[MultiMesh]=[]
var paint:=ShaderMaterial.new()
var ids:=PackedInt32Array()
var poses:=PackedVector4Array()
var modes:=PackedInt32Array()
var marker:=MeshInstance3D.new()
var parcels:=MultiMesh.new()

func _ready() -> void:
	paint.shader=preload("res://scripts/walkers.gdshader")
	for i in COATS.size():
		var g=Forms.new()
		var coat:=Color(COATS[i])
		var skin:=Color(["#e3b892","#b88564","#805b49","#c99770"][i%4])
		var trousers:=Color(["#394d59","#514d49","#485775"][i%3])
		for side in [-1,1]:
			g.box(Vector3(side*.12,.45,0),Vector3(.18,.70,.22),trousers)
			g.box(Vector3(side*.12,.12,.055),Vector3(.2,.19,.33),Color("#594f45"))
			g.box(Vector3(side*.29,1.18,0),Vector3(.14,.42,.17),coat)
			g.box(Vector3(side*.29,.91,0),Vector3(.13,.18,.15),skin)
		g.box(Vector3(0,1.12,0),Vector3(.47,.71,.3),coat)
		g.taper(Vector3(0,1.48,0),.19,.205,.33,8,skin)
		g.taper(Vector3(0,1.76,-.02),.217,.17,.13,8,Color("#675547") if i%3 else Color("#493e38"))
		if i%3==1:
			g.box(Vector3(0,1.80,.08),Vector3(.44,.11,.48),coat)
		if i%2==0:
			g.box(Vector3(0,1.17,-.225),Vector3(.29,.4,.14),Color("#746449"))
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
		var hit=site.get_aabb().intersects_ray(inverse*start,inverse.basis*dir)
		if hit!=null and start.distance_to(site.global_transform*hit)<depth-.5:
			return false
	return true
