extends RefCounted
## Flat-shaded miniature geometry. Winding is selected from the requested outward direction.
var surface := SurfaceTool.new()
var material := StandardMaterial3D.new()

func _init() -> void:
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = false
	material.roughness = 0.91

func triangle(a: Vector3, b: Vector3, c: Vector3, color: Color, outward: Vector3) -> void:
	var normal := (c-a).cross(b-a).normalized()
	if normal.dot(outward) < 0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	surface.set_normal(normal)
	surface.set_color(color.srgb_to_linear())
	for p in [a,b,c]:
		surface.add_vertex(p)

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

func mesh() -> ArrayMesh:
	surface.set_material(material)
	return surface.commit()

func attach(parent: Node3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh()
	parent.add_child(node)
	return node
