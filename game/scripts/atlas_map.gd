extends Control
const Geo=preload("res://scripts/geography.gd")
const BASE=preload("res://art/atlas/world.jpg")
const OVERVIEW=preload("res://art/atlas/world-relief.jpg")
const RELIEF=preload("res://scripts/relief.gdshader")
const COUNTRIES=preload("res://art/atlas/countries.json")
const PLACES=preload("res://art/atlas/places.json")
signal navigated
signal picked(lat:float,lon:float)
var geo
var center:=Vector2(.5,.446)
var pin:=Vector2.INF
var zoom:=0.
var interact:=true
var dragging:=false
var moved:=false
var down:=Vector2.ZERO
var map_origin:=Vector2.ZERO
var tile_nodes:Dictionary={}
var since_refresh:=0.
var prev_center:=Vector2.INF
var prev_pin:=Vector2.INF
var prev_zoom:=-1.
var prev_size:=Vector2.ZERO
var font:=SystemFont.new()
var annotations:Control
var borders:Array[PackedVector2Array]=[]
var place_points:=PackedVector2Array()
var place_cells:Dictionary={}
var major_places:Array[int]=[]
var border_bounds:Array[Rect2]=[]

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font.font_names=PackedStringArray(["Avenir Next","Apple SD Gothic Neo","Helvetica Neue"])
	for i in PLACES.data.size():
		var place:Array=PLACES.data[i]
		var uv:=Geo.mercator(place[2],place[1])
		place_points.append(uv)
		var cell:=Vector2i((uv*32.).floor())
		if not place_cells.has(cell): place_cells[cell]=[]
		place_cells[cell].append(i)
		if place[3]>=2200000: major_places.append(i)
	for country in COUNTRIES.data:
		for ring in country[4]:
			var points:=PackedVector2Array()
			for i in range(0,ring.size(),2):
				var uv:=Geo.mercator(ring[i+1],ring[i])
				if not points.is_empty() and absf(points[-1].x-uv.x)>.5:
					_store_border(points)
					points=PackedVector2Array()
				points.append(uv)
			_store_border(points)
	annotations=Control.new()
	annotations.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(annotations)
	annotations.draw.connect(_draw_labels)
	annotations.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_default_cursor_shape=Control.CURSOR_CROSS

func _store_border(points:PackedVector2Array) -> void:
	if points.size()<2: return
	var box:=Rect2(points[0],Vector2.ZERO)
	for p in points: box=box.expand(p)
	borders.append(points)
	border_bounds.append(box)

func span() -> float:
	return maxf(size.x,760.)*pow(2.,zoom)

func point(uv:Vector2) -> Vector2:
	return size*.5+Vector2(wrapf(uv.x-center.x,-.5,.5),uv.y-center.y)*span()

func at(pos:Vector2) -> Vector2:
	return center+(pos-size*.5)/span()

func set_zoom(next:float,anchor:Vector2) -> void:
	if not interact: return
	navigated.emit()
	var uv:=at(anchor)
	zoom=clampf(next,0.,14.)
	center=uv-(anchor-size*.5)/span()
	_bound()

func _bound() -> void:
	center.x=fposmod(center.x,1.)
	var half:=minf(.49,size.y/(2.*span()))
	center.y=clampf(center.y,half,1.-half)
	queue_redraw()

func _gui_input(e:InputEvent) -> void:
	if not interact: return
	if e is InputEventMouseButton:
		if e.button_index==MOUSE_BUTTON_WHEEL_UP or e.button_index==MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed: set_zoom(zoom+(.60 if e.button_index==MOUSE_BUTTON_WHEEL_UP else -.60),e.position)
		elif e.button_index==MOUSE_BUTTON_LEFT:
			if e.pressed:
				navigated.emit()
				dragging=true
				moved=false
				down=e.position
				map_origin=center
			elif dragging:
				dragging=false
				if not moved:
					var ll:=Geo.geographic(at(e.position))
					picked.emit(ll.x,ll.y)
	elif e is InputEventMouseMotion and dragging:
		if down.distance_to(e.position)>4.: moved=true
		if moved:
			center=map_origin+(down-e.position)/span()
			_bound()
	elif e is InputEventMagnifyGesture:
		set_zoom(zoom+log(e.factor)/log(2.),e.position)
	elif e is InputEventPanGesture:
		navigated.emit()
		center+=e.delta*28./span()
		_bound()

func _draw() -> void:
	var width:=span()
	var start:=size*.5-center*width
	var blend:=smoothstep(1.55,2.35,zoom)
	for i in range(-1,2):
		var rect:=Rect2(start+Vector2(i*width,0),Vector2.ONE*width)
		draw_texture_rect(BASE,rect,false)
		if blend>0: draw_texture_rect(OVERVIEW,rect,false,Color(1,1,1,blend))

func _visible_places() -> Array:
	if zoom<3.: return major_places
	var first:=Vector2i((at(Vector2.ZERO)*32.).floor())
	var last:=Vector2i((at(size)*32.).floor())
	var ids:Array=[]
	for y in range(maxi(0,first.y),mini(32,last.y+1)):
		for x in range(first.x,last.x+1):
			ids.append_array(place_cells.get(Vector2i(posmod(x,32),y),[]))
	return ids

func _draw_labels() -> void:
	var a=annotations
	if zoom<4.:
		var gap:=30 if zoom<1.2 else 10
		for lon in range(-180,180,gap):
			var p:=point(Geo.mercator(0,lon))
			a.draw_line(Vector2(p.x,0),Vector2(p.x,size.y),Color("#38494c28"),1.)
		for lat in range(-80,81,10):
			if lat%gap!=0: continue
			var p:=point(Geo.mercator(lat,0))
			a.draw_line(Vector2(0,p.y),Vector2(size.x,p.y),Color("#38494c28"),1.)
	var occupied:Array[Rect2]=[]
	if zoom<5.:
		var width:=span()
		for wrap in [-1,0,1]:
			var origin:=size*.5-center*width+Vector2(wrap*width,0)
			var viewport:=Rect2(-origin/width,size/width)
			a.draw_set_transform(origin,0.,Vector2.ONE*width)
			for i in borders.size():
				if viewport.intersects(border_bounds[i],true):
					a.draw_polyline(borders[i],Color("#585c547b"),1./width,true)
		a.draw_set_transform(Vector2.ZERO)
		for country in COUNTRIES.data:
			if country[3]>clampf(2.+zoom,2.,6.): continue
			var pos:=point(Geo.mercator(country[2],country[1]))
			if not Rect2(Vector2.ZERO,size).has_point(pos): continue
			var name:String=country[0]
			var w:=font.get_string_size(name,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x
			var origin:=pos+Vector2(-w*.5,0)
			var bounds:=Rect2(origin-Vector2(3,15),Vector2(w+9,22))
			var overlaps:=false
			for other in occupied:
				if other.intersects(bounds): overlaps=true; break
			if overlaps: continue
			occupied.append(bounds)
			a.draw_string_outline(font,origin,name,HORIZONTAL_ALIGNMENT_LEFT,-1,17,4,Color("#eeebd5"))
			a.draw_string(font,origin,name,HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("#414b41"))
	for id in _visible_places():
		var place:Array=PLACES.data[id]
		if place[3]<(8000000 if zoom<1. else (2200000 if zoom<3. else (180000 if zoom<6. else 0))): continue
		var p:=point(place_points[id])
		if not Rect2(Vector2.ZERO,size).has_point(p): continue
		var name:String=place[4] if place[4]!="" else place[0]
		var box:=Rect2(p+Vector2(5,-14),Vector2(font.get_string_size(name,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x+8,18))
		var overlap:=false
		for other in occupied:
			if other.intersects(box): overlap=true; break
		if overlap: continue
		occupied.append(box)
		a.draw_circle(p,2.1,Color("#333d35"))
		a.draw_string_outline(font,p+Vector2(7,4),name,HORIZONTAL_ALIGNMENT_LEFT,-1,13,4,Color("#e9e9d5e8"))
		a.draw_string(font,p+Vector2(7,4),name,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("#303b36"))
	if pin!=Vector2.INF:
		var p:=point(pin)
		a.draw_arc(p,13,0,TAU,48,Color("#153f37"),3,true)
		a.draw_arc(p,16,0,TAU,48,Color("#fff5d9"),2,true)
		a.draw_circle(p,4,Color("#173e34"))
		for dir in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
			a.draw_line(p+dir*19,p+dir*26,Color("#173e34"),2,true)

func _process(delta:float) -> void:
	if prev_center!=center or prev_zoom!=zoom or prev_pin!=pin or prev_size!=size:
		queue_redraw()
		annotations.queue_redraw()
		prev_center=center
		prev_zoom=zoom
		prev_pin=pin
		prev_size=size
	since_refresh+=delta
	if since_refresh<.12: return
	since_refresh=0.
	var shown:Dictionary={}
	if zoom>2.35:
		var desired:=clampi(floori(log(span()/256.)/log(2.)),3,14)
		var first:=Vector2i((at(Vector2.ZERO)*(1<<desired)).floor())
		var last:=Vector2i((at(size)*(1<<desired)).floor())
		for y in range(maxi(0,first.y),mini(1<<desired,last.y+1)):
			for x in range(first.x,last.x+1):
				var key:=Vector3i(posmod(x,1<<desired),y,desired)
				if interact and not dragging: geo.want(key)
				while key.z>=3:
					if geo.textures.has(key):
						shown[key]=true
						break
					key=Vector3i(key.x>>1,key.y>>1,key.z-1)
	for key in tile_nodes.keys():
		if not shown.has(key):
			tile_nodes[key].queue_free()
			tile_nodes.erase(key)
	for key in shown:
		if not tile_nodes.has(key):
			var tile:=TextureRect.new()
			tile.mouse_filter=Control.MOUSE_FILTER_IGNORE
			tile.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			tile.texture=geo.textures[key]
			tile.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
			var mat:=ShaderMaterial.new()
			mat.shader=RELIEF
			var ll:=Geo.geographic(Vector2(key.x+.5,key.y+.5)/(1<<key.z))
			mat.set_shader_parameter("metres_per_pixel",156543.*cos(deg_to_rad(ll.x))/(1<<key.z))
			tile.material=mat
			add_child(tile)
			tile.z_index=key.z
			tile_nodes[key]=tile
	annotations.z_index=20
	_place_tiles()

func _place_tiles() -> void:
	for key in tile_nodes:
		var n:float=1<<key.z
		var tile:TextureRect=tile_nodes[key]
		tile.position=point(Vector2(key.x+.5,key.y+.5)/n)-Vector2.ONE*(span()*.5/n)
		tile.size=Vector2.ONE*(span()/n+.35)
		tile.material.set_shader_parameter("opacity",smoothstep(1.55,2.35,zoom))

func _notification(what:int) -> void:
	if what==NOTIFICATION_DRAW and is_node_ready(): _place_tiles()
