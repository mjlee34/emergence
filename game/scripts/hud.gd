extends Control
signal speed_selected(value: int)
signal home_requested
signal street_requested
signal meet_requested
signal district_requested(use:int)
var district_title:=""
var journey:=PackedVector2Array()
var last_leg:=Vector2i(-1,-1)
const IVORY=Color("#f6efdb")
const MUTED=Color("#bccac1")
const GOLD=Color("#f3c774")
const INK=Color("#203532")
const SIZES=[0,1,10,100,1000]
var sans:=SystemFont.new()
var serif:=SystemFont.new()
var speed:=1
var heading:=0.0
var scrim:=GradientTexture2D.new()
var state:Dictionary={}
var buttons:Array[Button]=[]
var dock:=PanelContainer.new()
var live:Label
var population:Label
var day:Label
var roads:Label
var entry:Label
var reset_button:=Button.new()
var map_button:=Button.new()
var map_open:=true
var street_button:=Button.new()
var meet_button:=Button.new()
var life_panel:=PanelContainer.new()
var occupancy:=Label.new()
var identity:=Label.new()
var routine_label:=Label.new()
var land_dots:=PackedVector2Array()
var land_uses:=PackedInt32Array()
const USE_COLORS=[Color("#acd49e"),Color("#f5c076"),Color("#b6a3d9")]
var map_paths:Array[PackedVector2Array]=[]
var map_ranks:=PackedInt32Array()
var river:=PackedVector2Array()
const ROUTE_COLORS=[Color("#a6b5a3"),Color("#7dd4c7"),Color("#f6b95d")]

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gradient:=Gradient.new()
	gradient.colors=PackedColorArray([Color("#152923ed"),Color("#15292300")])
	scrim.gradient=gradient
	scrim.fill=GradientTexture2D.FILL_RADIAL
	scrim.fill_from=Vector2(0.03,0.01)
	scrim.fill_to=Vector2(.76,.79)
	sans.font_names=PackedStringArray(["Avenir Next","Helvetica Neue","Arial"])
	serif.font_names=PackedStringArray(["Baskerville","Georgia","Times New Roman"])
	_label(self,"E M E R G E N C E",Vector2(82,30),18,IVORY)
	_label(self,"Alder Reach",Vector2(34,69),53,IVORY,serif)
	_label(self,"River valley   /   Fixture terrain",Vector2(37,140),16,MUTED)
	entry=_label(self,"",Vector2(37,171),14,GOLD)
	live=_label(self,"",Vector2.ZERO,14,IVORY)
	live.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	live.add_theme_stylebox_override("normal",_box(Color("#203532eb"),6,Color.TRANSPARENT,0))
	reset_button.text="Fit city"
	reset_button.tooltip_text="Follow the growing city (H)"
	_style_button(reset_button,false)
	add_child(reset_button)
	reset_button.pressed.connect(func(): home_requested.emit())
	map_button.text="Districts  ▴"
	_style_button(map_button,false)
	add_child(map_button)
	map_button.pressed.connect(func():
		map_open=not map_open
		map_button.text="Districts  ▴" if map_open else "Street plan  ▾"
		queue_redraw())
	street_button.text="Street view"
	street_button.tooltip_text="Observe the market streets (V)"
	_style_button(street_button,false)
	add_child(street_button)
	street_button.pressed.connect(func(): street_requested.emit())
	life_panel.add_theme_stylebox_override("panel",_box(Color("#182c29f5"),8,Color("#62756a"),1))
	add_child(life_panel)
	var info:=VBoxContainer.new()
	info.add_theme_constant_override("separation",5)
	life_panel.add_child(info)
	_font(occupancy,sans,14,MUTED)
	_font(identity,serif,26,IVORY)
	_font(routine_label,sans,15,IVORY)
	info.add_child(identity)
	info.add_child(routine_label)
	info.add_child(occupancy)
	var districts:=HBoxContainer.new()
	info.add_child(districts)
	for i in 3:
		var b:=Button.new()
		b.text=["Homes","Markets","Works"][i]
		_style_button(b,false)
		b.tooltip_text="Visit a "+["residential street","shopping street","workshop yard"][i]
		b.pressed.connect(func(): district_requested.emit(i))
		districts.add_child(b)
	meet_button.text="Meet a resident"
	_style_button(meet_button,false)
	info.add_child(meet_button)
	meet_button.pressed.connect(func(): meet_requested.emit())
	dock.add_theme_stylebox_override("panel",_box(INK.darkened(.16),10,Color("#587066"),1))
	add_child(dock)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",18)
	dock.add_child(row)
	var date_column:=_metric(row,"LOCAL TIME")
	day=date_column
	population=_metric(row,"RESIDENTS")
	roads=_metric(row,"STREETS")
	var line:=VSeparator.new()
	row.add_child(line)
	var speeds:=HBoxContainer.new()
	speeds.alignment=BoxContainer.ALIGNMENT_CENTER
	speeds.add_theme_constant_override("separation",3)
	row.add_child(speeds)
	for value in SIZES:
		var button:=Button.new()
		button.text="Ⅱ" if value==0 else str(value)+"×"
		button.tooltip_text="Pause or resume (Space)" if value==0 else str(value)+"× simulation speed"
		button.custom_minimum_size=Vector2(44 if value<100 else 65,38)
		_style_button(button,value==speed)
		button.size_flags_vertical=SIZE_SHRINK_CENTER
		speeds.add_child(button)
		button.pressed.connect(func(): speed_selected.emit(value))
		buttons.append(button)
	resized.connect(_layout)
	_layout.call_deferred()

func _metric(parent:Control,title:String) -> Label:
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",-2)
	column.custom_minimum_size.x=93 if title!="STREETS" else 60
	parent.add_child(column)
	var name_label:=Label.new()
	name_label.text=title
	_font(name_label,sans,10,MUTED)
	column.add_child(name_label)
	var value:=Label.new()
	_font(value,sans,23,IVORY)
	column.add_child(value)
	return value

func _label(parent:Control,words:String,pos:Vector2,px:int,color:Color,font:Font=null) -> Label:
	var label:=Label.new()
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.text=words
	_font(label,sans if font==null else font,px,color)
	label.position=pos
	parent.add_child(label)
	return label

func _font(control:Control,font:Font,px:int,color:Color) -> void:
	control.add_theme_font_override("font",font)
	control.add_theme_font_size_override("font_size",px)
	control.add_theme_color_override("font_color",color)

func _box(fill:Color,radius:int,border:Color,width:int) -> StyleBoxFlat:
	var s:=StyleBoxFlat.new()
	s.bg_color=fill
	s.set_corner_radius_all(radius)
	s.set_border_width_all(width)
	s.border_color=border
	for side in [SIDE_LEFT,SIDE_RIGHT]: s.set_content_margin(side,14)
	for side in [SIDE_TOP,SIDE_BOTTOM]: s.set_content_margin(side,8)
	return s

func _style_button(b:Button,selected:bool) -> void:
	_font(b,sans,15,INK if selected else IVORY)
	b.add_theme_color_override("font_hover_color",INK)
	b.add_theme_color_override("font_pressed_color",INK)
	b.add_theme_stylebox_override("normal",_box(GOLD if selected else INK,6,Color.TRANSPARENT,0))
	b.add_theme_stylebox_override("hover",_box(Color("#d8dfbd"),6,Color.TRANSPARENT,0))
	b.add_theme_stylebox_override("pressed",_box(GOLD,6,Color.TRANSPARENT,0))

func _layout() -> void:
	var w:=dock.get_combined_minimum_size()
	dock.size=w
	dock.position=Vector2((size.x-w.x)*.5,size.y-w.y-32)
	live.position=Vector2(size.x-169,22)
	live.size.x=134
	reset_button.position=Vector2(size.x-reset_button.get_combined_minimum_size().x-35,66)
	map_button.position=Vector2(reset_button.position.x-map_button.get_combined_minimum_size().x-7,66)
	street_button.position=Vector2(map_button.position.x-street_button.get_combined_minimum_size().x-7,66)
	life_panel.position=Vector2(34,size.y-345)
	queue_redraw()

func show_life(data:Dictionary,resident:Dictionary,model) -> void:
	occupancy.text="%s working    %s shopping    %s walking" % [grouped(data.at_work),grouped(data.shopping),grouped(data.walking)]
	if resident.is_empty():
		identity.text="Street life" if district_title=="" else district_title
		routine_label.text="Click a person to follow their day.\n%s employed  ·  %s jobs open" % [grouped(data.employed),grouped(data.jobs-data.employed)]
		journey.clear()
		last_leg=Vector2i(-1,-1)
	else:
		var v:int=resident.variation
		var given:=["Mina","Theo","Iris","Leon","Ari","Ella","Milo","Ren","Nora","Emil","Sam","Lina","Alex","Noa","Rae","Kai"]
		var family:=["Park","Reed","Chen","Hill","Baek","Ford","Kim","Bell","Tan","Cole","Shaw","Ito","Yu","Moon","West","Gray"]
		identity.text="%s %s  ·  #%d"%[given[v%16],family[(v>>8)%16],resident.id+1]
		var activity:String=["At home  ·","On shift  ·","Shopping  ·","Walking to"][resident.activity]
		var workplace:="Seeking work" if resident.seeking else "Outside workforce"
		if resident.work>=0:
			workplace="%s  (%s–%s)"%[_address(model,resident.work),_time(resident.shift),_time(resident.finish)]
		routine_label.text="%s %s\nHome   %s\nWork    %s"%[activity,_address(model,resident.target),_address(model,resident.home),workplace]
		var leg:=Vector2i(resident.id,resident.target)
		if last_leg!=leg:
			last_leg=leg
			journey=model.walking_plan(resident.id,0.)
			queue_redraw()
	life_panel.reset_size()

func _address(model,id:int) -> String:
	var b:Dictionary=model.lot(id)
	var title: String
	match int(b.use):
		0: title="Residence"
		1: title=["Bakery","Corner café","Grocer","Bookshop"][b.style%4]
		_: title=["Foundry","Joinery","Printworks","Textile mill"][b.style%4]
	return "%s %02d"%[title,id+1]

func _time(minute:int) -> String:
	return "%02d:%02d"%[int(minute/60),minute%60]

func display(data:Dictionary,multiplier:int,angle:float) -> void:
	if state!=data:
		day.text="%02d:%02d" % [int(data.minute/60),data.minute%60]
		population.text=grouped(data.population)
		roads.text=str(data.roads)
		entry.text="Day %d   ·   %s"%[data.day,data.event]
		state=data
	if speed!=multiplier or live.text=="":
		speed=multiplier
		live.text="●   OBSERVING" if speed>0 else "Ⅱ   PAUSED"
		for i in buttons.size(): _style_button(buttons[i],SIZES[i]==speed)
	if absf(heading-angle)>.001:
		heading=angle
		queue_redraw()

func grouped(value:int) -> String:
	var s:=str(value)
	var i:=s.length()-3
	while i>0:
		s=s.insert(i,",")
		i-=3
	return s

func _draw() -> void:
	# Custom contour mark and a compass registered to the camera.
	draw_texture_rect(scrim,Rect2(Vector2.ZERO,Vector2(670,365)),false)
	for i in range(3):
		var points:=PackedVector2Array()
		for k in range(5):
			points.append(Vector2(36+k*7,46+i*4+[-2,-7,-1,-9,-4][k]))
		draw_polyline(points,GOLD,1.75,true)
	if map_open: _draw_plan()
	var center:=Vector2(59,size.y-66)
	draw_arc(center,22,0,TAU,48,Color("#bdcbb695"),1,true)
	var n:=Vector2(sin(heading),-cos(heading))
	draw_colored_polygon(PackedVector2Array([center+n*16,center+n.orthogonal()*3.5,center-n.orthogonal()*3.5]),GOLD)
	draw_line(center,center-n*12,MUTED,1.5,true)
	draw_string(sans,center+Vector2(-4,-30),"N",HORIZONTAL_ALIGNMENT_LEFT,-1,11,IVORY)
	draw_string(sans,Vector2(size.x-297,size.y-23),"Drag to orbit   ·   Shift-drag to pan   ·   Scroll to zoom",HORIZONTAL_ALIGNMENT_LEFT,-1,11,MUTED)


func sync_map(sim,count:int,buildings:int) -> void:
	if map_paths.size()==count and land_dots.size()==buildings: return
	while land_dots.size()<buildings:
		var b:Dictionary=sim.lot(land_dots.size())
		land_dots.append(Vector2(b.pos.x,b.pos.z))
		land_uses.append(b.use)
	if river.is_empty():
		for z in range(-320,321,8):
			river.append(Vector2(sim.river_x(z),z))
	while map_paths.size()<count:
		var data:Dictionary=sim.street(map_paths.size())
		var line:=PackedVector2Array()
		for p in data.path: line.append(Vector2(p.x,p.z))
		map_paths.append(line)
		map_ranks.append(data["class"])
	queue_redraw()

func _draw_plan() -> void:
	var panel:=Rect2(size.x-301,111,266,204)
	draw_rect(panel,Color("#182b29ef"))
	if state.is_empty(): return
	var bounds:Vector4=state.bounds
	var focus:=Vector2((bounds.x+bounds.z)*.5,(bounds.y+bounds.w)*.5)
	var scale_factor:=minf(235./maxf(100,bounds.z-bounds.x+28),144./maxf(70,bounds.w-bounds.y+28))
	var origin:=panel.position+Vector2(133,83)-focus*scale_factor
	var plot:=Rect2(panel.position+Vector2(5,5),Vector2(256,155))
	for i in range(1,river.size()):
		var a:=origin+river[i-1]*scale_factor
		var b:=origin+river[i]*scale_factor
		if plot.has_point(a) and plot.has_point(b): draw_line(a,b,Color("#426b70"),maxf(2,16*scale_factor),true)
	draw_set_transform(origin,0,Vector2.ONE*scale_factor)
	for rank in 3:
		for i in map_paths.size():
			if map_ranks[i]==rank:
				draw_polyline(map_paths[i],ROUTE_COLORS[rank],[.75,1.15,2.0][rank]/scale_factor,true)
	for i in land_dots.size():
		draw_circle(land_dots[i],clampf(3.5*scale_factor,1.1,2.7)/scale_factor,USE_COLORS[land_uses[i]])
	if journey.size()>1:
		draw_polyline(journey,Color("#fff0bc"),2.2/scale_factor,true)
		draw_circle(journey[0],3.5/scale_factor,IVORY)
		draw_circle(journey[-1],3.5/scale_factor,GOLD)
	draw_set_transform(Vector2.ZERO)
	var y:=panel.end.y-28
	var x:=panel.position.x+12
	for rank in [2,1,0]:
		draw_line(Vector2(x,y-4),Vector2(x+12,y-4),ROUTE_COLORS[rank],rank+1.5,true)
		draw_string(sans,Vector2(x+16,y),["Local","Collector","Arterial"][rank],HORIZONTAL_ALIGNMENT_LEFT,-1,13,IVORY)
		x+=85
	for rank in 3:
		var dot:=panel.position+Vector2(13+rank*87,panel.size.y-11)
		draw_circle(dot,3.3,USE_COLORS[rank])
		draw_string(sans,dot+Vector2(7,4),["Housing","Commerce","Industry"][rank],HORIZONTAL_ALIGNMENT_LEFT,-1,12,IVORY)
