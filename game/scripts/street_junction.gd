extends RefCounted
const Forms=preload("res://scripts/forms.gd")
const ASPHALT:=Color("#666968")
const CURB:=Color("#b3b3aa")
const PAINT:=Color("#c9c8bb")

var model
var center:Vector2

func _point(p:Vector2,lift:float) -> Vector3:
	var at:=center+p
	return Vector3(at.x,model.height_at(at.x,at.y)+lift,at.y)

func _stripe(g,dir:Vector2,side:Vector2,station:float,offset:float,length:float,width:float) -> void:
	var p:=dir*station+side*offset
	var x:=dir*length*.5
	var y:=side*width*.5
	g.quad(_point(p-x-y,.506),_point(p+x-y,.506),_point(p+x+y,.506),_point(p-x+y,.506),PAINT,Vector3.UP)

# Each open approach contributes its actual tangent and carriageway width.
# Fillets meet the two pavement edges at a tangent, including oblique Y joins.
func rebuild(parent:Node3D,sim,at:Vector3,arms:Array) -> MeshInstance3D:
	model=sim
	center=Vector2(at.x,at.z)
	var g=Forms.new(true)
	arms.sort_custom(func(a,b): return a.dir.angle()<b.dir.angle())
	for arm in arms: arm.cut=minf(arm.length*.27,arm.half+3.)
	if arms.size()==1:
		var arm:Dictionary=arms[0]
		var side:=Vector2(-arm.dir.y,arm.dir.x)
		for i in 12:
			var a:Vector2=side.rotated(PI*i/12.)*arm.half
			var b:Vector2=side.rotated(PI*(i+1)/12.)*arm.half
			g.finish=Forms.Finish.ROAD
			g.triangle(_point(Vector2.ZERO,.445),_point(a,.445),_point(b,.445),ASPHALT,Vector3.UP)
		return g.attach(parent)
	var corners:Array[PackedVector2Array]=[]
	for i in arms.size():
		var a:Dictionary=arms[i]
		var b:Dictionary=arms[(i+1)%arms.size()]
		var u:Vector2=a.dir
		var v:Vector2=b.dir
		var left:=Vector2(-u.y,u.x)*float(a.half)
		var right:=Vector2(v.y,-v.x)*float(b.half)
		var path:=PackedVector2Array()
		var cross:=u.cross(v)
		if cross>.12:
			var corner:=left+u*(right-left).cross(v)/cross
			var radius:=minf(2.4,minf(a.length,b.length)*.09)
			var start:=corner+u*radius
			var end:=corner+v*radius
			if start.dot(u)<a.length*.30 and end.dot(v)<b.length*.30:
				a.cut=maxf(a.cut,start.dot(u))
				b.cut=maxf(b.cut,end.dot(v))
				for j in 7:
					var t:=j/6.
					path.append(start.lerp(corner,t).lerp(corner.lerp(end,t),t))
		if path.is_empty():
			path.append(left)
			path.append(right)
		corners.append(path)
	for i in arms.size():
		var a:Dictionary=arms[i]
		var b:Dictionary=arms[(i+1)%arms.size()]
		var u:Vector2=a.dir
		var v:Vector2=b.dir
		var side:=Vector2(-u.y,u.x)
		var mouth:Vector2=u*a.cut
		var edge:Vector2=side*a.half
		g.finish=Forms.Finish.ROAD
		g.triangle(_point(Vector2.ZERO,.452),_point(mouth-edge,.452),_point(mouth+edge,.452),ASPHALT,Vector3.UP)
		var path:=PackedVector2Array([mouth+edge])
		path.append_array(corners[i])
		path.append(v*float(b.cut)+Vector2(v.y,-v.x)*float(b.half))
		for j in range(path.size()-1):
			var p:=path[j]
			var q:=path[j+1]
			if p.distance_squared_to(q)<.001: continue
			var outward:=Vector2(q.y-p.y,p.x-q.x).normalized()
			g.finish=Forms.Finish.ROAD
			g.triangle(_point(Vector2.ZERO,.452),_point(p,.452),_point(q,.452),ASPHALT,Vector3.UP)
			g.finish=Forms.Finish.WALK
			g.quad(_point(p,.49),_point(q,.49),_point(q+outward*.95,.49),_point(p+outward*.95,.49),CURB,Vector3.UP)
		if arms.size()>=3 and a.length*.48>a.cut+2. and (a.rank>0 or arms.any(func(other): return other.rank>0)):
			g.finish=Forms.Finish.PLAIN
			var crossing:float=a.cut+1.65
			var offset:float=-a.half+.45
			while offset<a.half-.25:
				if a.rank!=2 or absf(offset)>1.: _stripe(g,u,side,crossing,offset,1.85,.36)
				offset+=.85
			_stripe(g,u,side,crossing+1.72,-a.half*.52,.24,a.half*.83)
	return g.attach(parent)
