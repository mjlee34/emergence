extends RefCounted
const Forms=preload("res://scripts/forms.gd")

var paths:Dictionary={}
var arms:Dictionary={}
var faces:Dictionary={}
var surfaces:Dictionary={}
var changed:=false

func opened(id:int,street:Dictionary) -> void:
	paths[id]=street
	for reverse in 2:
		var start:int=street.to_id if reverse else street.from_id
		var path:PackedVector3Array=street.path
		var delta:Vector3=path[-2]-path[-1] if reverse else path[1]-path[0]
		if not arms.has(start): arms[start]=[]
		arms[start].append([atan2(delta.z,delta.x),2*id+reverse])
		arms[start].sort_custom(func(a,b): return a[0]<b[0])
	changed=true

# Walk each side of every open street, taking the next turn around its block.
# The outside face winds backwards. A bridge leading to a dead end has both
# sides on the same face and cannot delimit a developed parcel.
func _trace() -> void:
	faces.clear()
	var visited:Dictionary={}
	for id:int in paths:
		for direction in 2:
			var first:int=2*id+direction
			if visited.has(first): continue
			var half_edge:=first
			var outline:=PackedVector2Array()
			var edges:=PackedInt32Array()
			var sides:=PackedInt32Array()
			var surveyed:=false
			var valid:=true
			while not visited.has(half_edge):
				visited[half_edge]=true
				var edge:=half_edge>>1
				var reverse:=half_edge%2
				var street:Dictionary=paths[edge]
				valid=valid and not street.bridge and not edges.has(edge)
				surveyed=surveyed or street.surveyed
				edges.append(edge)
				sides.append(half_edge)
				for k in range(0,8,2):
					var p:Vector3=street.path[8-k if reverse else k]
					outline.append(Vector2(p.x,p.z))
				var end:int=street.from_id if reverse else street.to_id
				var turns:Array=arms[end]
				for i in turns.size():
					if turns[i][1]==(half_edge^1):
						half_edge=turns[posmod(i-1,turns.size())][1]
						break
			if not valid or not surveyed or edges.size()>20 or edges.size()<3: continue
			var area:=0.
			for i in outline.size(): area+=outline[i].cross(outline[(i+1)%outline.size()])*.5
			if area<320. or area>15000.: continue
			faces[first]={"edges":edges,"sides":sides,"outline":outline}
	changed=false

func sync(parent:Node3D,model,lots:Array[Dictionary]) -> void:
	if changed: _trace()
	var uses:Dictionary={}
	for lot in lots:
		var side:int=2*lot.frontage+int(lot.front_sign>0)
		var counts:Vector3i=uses.get(side,Vector3i.ZERO)
		counts[lot.use]+=1
		uses[side]=counts
	for key in surfaces.keys():
		if not faces.has(key) or surfaces[key].edges!=faces[key].edges:
			surfaces[key].mesh.queue_free()
			surfaces.erase(key)
	for key in faces:
		var face:Dictionary=faces[key]
		var counts:=Vector3i.ZERO
		for side in face.sides: counts+=Vector3i(uses.get(side,Vector3i.ZERO))
		if counts.x+counts.y+counts.z<face.edges.size(): continue
		var kind:=2 if counts.z>counts.x and counts.z>=counts.y else (1 if counts.y>counts.x else 0)
		if surfaces.has(key):
			if surfaces[key].kind==kind: continue
			surfaces[key].mesh.queue_free()
			surfaces.erase(key)
		var outline:PackedVector2Array=face.outline
		var indices:=Geometry2D.triangulate_polygon(outline)
		if indices.is_empty(): continue
		var mesh=Forms.new(true)
		for i in range(0,indices.size(),3):
			_ground(mesh,model,outline,outline[indices[i]],outline[indices[i+1]],outline[indices[i+2]],kind)
		surfaces[key]={"edges":face.edges,"kind":kind,"mesh":mesh.attach(parent)}

func _ground(g,model,outline:PackedVector2Array,a:Vector2,b:Vector2,c:Vector2,kind:int) -> void:
	var longest:=maxf(a.distance_squared_to(b),maxf(b.distance_squared_to(c),c.distance_squared_to(a)))
	if longest>16.*16.:
		# Bisect the longest side to drape the ground surface over local relief.
		if b.distance_squared_to(c)==longest:
			_ground(g,model,outline,b,(b+c)*.5,a,kind)
			_ground(g,model,outline,(b+c)*.5,c,a,kind)
		elif a.distance_squared_to(c)==longest:
			_ground(g,model,outline,c,(c+a)*.5,b,kind)
			_ground(g,model,outline,(c+a)*.5,a,b,kind)
		else:
			_ground(g,model,outline,a,(a+b)*.5,c,kind)
			_ground(g,model,outline,(a+b)*.5,b,c,kind)
		return
	var at:=(a+b+c)/3.
	var border:=INF
	for i in outline.size():
		border=minf(border,at.distance_squared_to(Geometry2D.get_closest_point_to_segment(at,outline[i],outline[(i+1)%outline.size()])))
	var yard:=kind==0 or (kind==1 and border>22.*22.)
	g.finish=Forms.Finish.MEADOW if yard else Forms.Finish.WALK
	var tint:=Color("#87916e") if yard else (Color("#999893") if kind==2 else Color("#b0a89a"))
	g.triangle(Vector3(a.x,model.height_at(a.x,a.y)+.10,a.y),Vector3(b.x,model.height_at(b.x,b.y)+.10,b.y),Vector3(c.x,model.height_at(c.x,c.y)+.10,c.y),tint,Vector3.UP)
