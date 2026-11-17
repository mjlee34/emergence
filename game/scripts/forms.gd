extends RefCounted
## Procedural geometry with metre-scaled surface coordinates. Winding is selected from the requested outward direction.
var surface := SurfaceTool.new()
enum Finish { PLAIN, ROAD, WALK, BRICK, SLATE, MEADOW, GLASS, METAL, PLASTER, FELT, LAMP, LIMESTONE_FRONT, BRICK_FRONT, CURTAIN_WALL, BRONZE_FRONT, ENAMEL, WINDSCREEN, HEADLIGHT, TAIL_LIGHT }
var finish:=Finish.PLAIN
var construction_lag:=0.0
var facade_uv:=Vector3.ZERO
var detailed:bool
var material:Material
static var built_material:ShaderMaterial
static var plain_material:StandardMaterial3D

func _init(with_surfaces:=false) -> void:
	detailed=with_surfaces
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	if detailed:
		if not built_material:
			built_material=ShaderMaterial.new()
			built_material.shader=preload("res://scripts/surfaces.gdshader")
			for key in ["road","walk","brick","slate","meadow"]:
				built_material.set_shader_parameter(key,load("res://art/"+key+".jpg"))
				built_material.set_shader_parameter(key+"_surface",load("res://art/"+key+"_surface.png"))
			for key in ["limestone","brickfront","curtainwall","bronze"]:
				built_material.set_shader_parameter(key,load("res://art/"+key+".jpg"))
		material=built_material
	else:
		if not plain_material:
			plain_material=StandardMaterial3D.new()
			plain_material.vertex_color_use_as_albedo=true
			plain_material.roughness=.78
		material=plain_material

func triangle(a: Vector3, b: Vector3, c: Vector3, color: Color, outward: Vector3) -> void:
	var normal := (c-a).cross(b-a).normalized()
	if normal.dot(outward) < 0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	surface.set_normal(normal)
	surface.set_color(color.srgb_to_linear())
	if detailed:
		var n:=normal.abs()
		var top:=n.y>n.x and n.y>n.z
		var axis:=Vector3.RIGHT if top or n.z>=n.x else Vector3.BACK
		var tangent:Vector3=(axis-normal*normal.dot(axis)).normalized()
		var down:=Vector3.BACK if top else Vector3.DOWN
		var v:=normal.cross(tangent)
		var sign_v:float=signf(v.dot(down))
		surface.set_tangent(Plane(tangent,sign_v))
		surface.set_uv2(Vector2(finish,construction_lag))
		for p:Vector3 in [a,b,c]:
			if facade_uv!=Vector3.ZERO:
				surface.set_uv(Vector2(p.x*facade_uv.x+p.z*facade_uv.y+facade_uv.z,-p.y))
			else:
				surface.set_uv(Vector2(p.dot(axis),p.z if top else -p.y))
			surface.add_vertex(p)
	else:
		for p in [a,b,c]: surface.add_vertex(p)

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, outward: Vector3) -> void:
	triangle(a,b,c,color,outward)
	triangle(a,c,d,color,outward)

func box(center: Vector3, size: Vector3, color: Color) -> void:
	var h := size*0.5
	var p := []
	for j in range(8):
		p.append(center + Vector3(h.x if j&1 else -h.x, h.y if j&2 else -h.y, h.z if j&4 else -h.z))
	quad(p[2],p[3],p[7],p[6],color,Vector3.UP)
	quad(p[0],p[1],p[3],p[2],color,Vector3.FORWARD)
	quad(p[4],p[5],p[7],p[6],color,Vector3.BACK)
	quad(p[0],p[4],p[6],p[2],color,Vector3.LEFT)
	quad(p[1],p[5],p[7],p[3],color,Vector3.RIGHT)
	quad(p[0],p[1],p[5],p[4],color,Vector3.DOWN)

func taper(base: Vector3, low: float, high: float, height: float, sides: int, color: Color, phase := 0.0) -> void:
	var top := base + Vector3.UP*height
	for j in range(sides):
		var a := Vector3(cos(TAU*j/sides+phase),0,sin(TAU*j/sides+phase))
		var b := a.rotated(Vector3.UP,-TAU/sides)
		triangle(base+a*low,base+b*low,top+a*high,color,a+b)
		if high>0:
			triangle(base+b*low,top+b*high,top+a*high,color,a+b)
			triangle(top,top+b*high,top+a*high,color,Vector3.UP)

## Elliptical rings for clothing, bodies and other rounded small props.
func profile(center:Vector3,rings:Array,color:Color,sides:=10) -> void:
	for i in range(rings.size()-1):
		var lower:Vector3=rings[i]
		var upper:Vector3=rings[i+1]
		for j in sides:
			var a:=TAU*j/sides
			var b:=TAU*(j+1)/sides
			var u:=Vector3(cos(a),0,sin(a))
			var v:=Vector3(cos(b),0,sin(b))
			var low:=center+Vector3.UP*lower.y
			var high:=center+Vector3.UP*upper.y
			quad(low+u*Vector3(lower.x,0,lower.z),low+v*Vector3(lower.x,0,lower.z),
				high+v*Vector3(upper.x,0,upper.z),high+u*Vector3(upper.x,0,upper.z),color,u+v)
	var last:Vector3=rings[-1]
	var top:=center+Vector3.UP*last.y
	for j in sides:
		var a:=TAU*j/sides
		var b:=TAU*(j+1)/sides
		triangle(top,top+Vector3(last.x*cos(a),0,last.z*sin(a)),top+Vector3(last.x*cos(b),0,last.z*sin(b)),color,Vector3.UP)

func beam(a:Vector3,b:Vector3,width:float,color:Color) -> void:
	var axis:=(b-a).normalized()
	var right:=axis.cross(Vector3.UP if absf(axis.y)<.95 else Vector3.RIGHT).normalized()*width*.5
	var front:=axis.cross(right)
	var corners:=[right+front,-right+front,-right-front,right-front]
	for i in 4:
		var u:Vector3=corners[i]
		var v:Vector3=corners[(i+1)%4]
		quad(a+u,a+v,b+v,b+u,color,u+v)

func wheel(center:Vector3,radius:float,side:int) -> void:
	var axis:=Vector3.BACK*side
	for j in 12:
		var a:=TAU*j/12
		var b:=TAU*(j+1)/12
		var u:=Vector3(cos(a),sin(a),0)*radius
		var v:=Vector3(cos(b),sin(b),0)*radius
		quad(center+u-axis*.10,center+v-axis*.10,center+v+axis*.10,center+u+axis*.10,Color("#282b2a"),u+v)
		var face:=center+axis*.10
		quad(face+u,face+v,face+v*.55,face+u*.55,Color("#252828"),axis)
		triangle(face,face+u*.55,face+v*.55,Color("#888e8e") if j%2 else Color("#596268"),axis)

func mesh() -> ArrayMesh:
	surface.set_material(material)
	return surface.commit()

func attach(parent: Node3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh()
	parent.add_child(node)
	return node

## A shared mesh without keeping a glTF scene tree for each vehicle or resident.
static func imported_mesh(scene:PackedScene) -> Mesh:
	var root:=scene.instantiate()
	var body:MeshInstance3D=root if root is MeshInstance3D else root.find_children("*","MeshInstance3D",true,false)[0]
	var result:=body.mesh
	root.free()
	return result
