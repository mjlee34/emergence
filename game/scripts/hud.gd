extends Control
signal map_world_requested
var world_button:=Button.new()
var place_name:="Alder Reach"
var place_subtitle:="River valley   /   Fixture terrain"
signal construction_requested
signal freight_requested
signal counter_requested
signal speed_selected(value: int)
signal home_requested
signal street_requested
signal bus_requested
var bus_button:=Button.new()
var bus_line:=PackedVector2Array()
var bus_dots:=PackedVector2Array()
var bus_point:=Vector2.ZERO
signal meet_requested
signal place_requested(id:int)
var parks_button:=MenuButton.new()
var green_dots:=PackedVector2Array()
var green_types:=PackedInt32Array()
signal district_requested(use:int)
var district_title:=""
var construction_note:=""
var journey:=PackedVector2Array()
var last_leg:=Vector3i(-1,-1,-1)
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
var ledger:=PanelContainer.new()
var business_name:=Label.new()
var trade_line:=Label.new()
var accounts:=Label.new()
var trading:=Label.new()
var freight_line:=PackedVector2Array()
var freight_id:=-1
var freight_point:=Vector2.ZERO
var follow_van:=Button.new()
var counter:=Button.new()
var live:Label
var population:Label
var day:Label
var roads:Label
signal skyline_requested
var weather_label:=Button.new()
var entry:Label
var reset_button:=Button.new()
var map_button:=Button.new()
var map_open:=true
var street_button:=Button.new()
var works_button:=Button.new()
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
var map_starts:=PackedInt32Array()
var map_opens:=PackedInt32Array()
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
	scrim.fill_to=Vector2(.68,.66)
	sans.font_names=PackedStringArray(["Avenir Next","Helvetica Neue","Arial"])
	serif.font_names=PackedStringArray(["Baskerville","Georgia","Times New Roman"])
	_label(self,"E M E R G E N C E",Vector2(82,30),18,IVORY)
	_label(self,place_name,Vector2(34,69),53,IVORY,serif)
	_label(self,place_subtitle,Vector2(37,140),16,MUTED)
	weather_label.position=Vector2(34,164)
	weather_label.tooltip_text="Watch the skyline (W)"
	_style_button(weather_label,false)
	add_child(weather_label)
	weather_label.pressed.connect(func(): skyline_requested.emit())
	entry=_label(self,"",Vector2(37,206),14,GOLD)
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
	world_button.text="World map"
	world_button.tooltip_text="Choose a settlement site (M)"
	_style_button(world_button,false)
	add_child(world_button)
	world_button.pressed.connect(func(): map_world_requested.emit())
	works_button.text="Construction"
	works_button.tooltip_text="Follow active road and building sites (G)"
	_style_button(works_button,false)
	add_child(works_button)
	works_button.pressed.connect(func(): construction_requested.emit())
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
	parks_button.text="Places"
	parks_button.tooltip_text="Explore parks, public services and landmarks (P)"
	_style_button(parks_button,false)
	districts.add_child(parks_button)
	parks_button.get_popup().id_pressed.connect(func(id:int): place_requested.emit(id))
	meet_button.text="Meet a resident"
	_style_button(meet_button,false)
	var observers:=HBoxContainer.new()
	info.add_child(observers)
	observers.add_child(meet_button)
	bus_button.text="Follow bus"
	bus_button.tooltip_text="Follow a Line 1 bus (B)"
	_style_button(bus_button,false)
	observers.add_child(bus_button)
	bus_button.pressed.connect(func(): bus_requested.emit())
	meet_button.pressed.connect(func(): meet_requested.emit())
	ledger.add_theme_stylebox_override("panel",_box(Color("#193b36f5"),8,Color("#64796a"),1))
	add_child(ledger)
	var sheet:=VBoxContainer.new()
	ledger.add_child(sheet)
	sheet.add_theme_constant_override("separation",5)
	_font(trading,sans,12,GOLD)
	trading.text="LOCAL TRADE"
	sheet.add_child(trading)
	_font(business_name,serif,25,IVORY)
	sheet.add_child(business_name)
	_font(trade_line,sans,16,IVORY)
	sheet.add_child(trade_line)
	_font(accounts,sans,14,MUTED)
	sheet.add_child(accounts)
	var actions:=HBoxContainer.new()
	sheet.add_child(actions)
	counter.text="View counter"
	_style_button(counter,false)
	actions.add_child(counter)
	counter.pressed.connect(func(): counter_requested.emit())
	follow_van.text="Follow delivery"
	_style_button(follow_van,false)
	actions.add_child(follow_van)
	follow_van.pressed.connect(func(): freight_requested.emit())
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
	works_button.position=Vector2(street_button.position.x-works_button.get_combined_minimum_size().x-7,66)
	world_button.position=Vector2(works_button.position.x-world_button.get_combined_minimum_size().x-7,66)
	life_panel.position=Vector2(34,size.y-32-life_panel.get_combined_minimum_size().y)
	ledger.position=Vector2(size.x-35-ledger.get_combined_minimum_size().x,332 if map_open else 112)
	queue_redraw()

func show_life(data:Dictionary,resident:Dictionary,model,bus_view:=false) -> void:
	occupancy.text="%s walking  ·  %s driving  ·  %s waiting  ·  %s aboard\n%s working  ·  %s shopping" % [grouped(data.walking),grouped(data.driving),grouped(data.waiting),grouped(data.riding),grouped(data.at_work),grouped(data.shopping)]
	if bus_view:
		journey.clear()
		last_leg=Vector3i(-1,-1,-1)
		return
	if resident.is_empty():
		identity.text="Street life" if district_title=="" else district_title
		routine_label.text="Click a person to follow their day.\n%s employed  ·  %s jobs open" % [grouped(data.employed),grouped(data.jobs-data.employed)]
		if construction_note!="": routine_label.text=construction_note
		journey.clear()
		last_leg=Vector3i(-1,-1,-1)
	else:
		var v:int=resident.variation
		var given:=["Mina","Theo","Iris","Leon","Ari","Ella","Milo","Ren","Nora","Emil","Sam","Lina","Alex","Noa","Rae","Kai"]
		var family:=["Park","Reed","Chen","Hill","Baek","Ford","Kim","Bell","Tan","Cole","Shaw","Ito","Yu","Moon","West","Gray"]
		identity.text="%s %s  ·  #%d"%[given[v%16],family[(v>>8)%16],resident.id+1]
		var activity:String=["At home  ·","On shift  ·","Shopping  ·","Walking to","Waiting for Line 1 to","On Line 1 to","Driving to","Visiting","In class at"][resident.activity]
		var workplace:="Seeking work" if resident.seeking else "Outside workforce"
		if resident.child: workplace="Child"
		if resident.work>=0:
			workplace="%s  (%s–%s)"%[_address(model,resident.work),_time(resident.shift),_time(resident.finish)]
		var destination:=_address(model,resident.target)
		if resident.facility>=0 and not resident.returning:
			destination=model.facility(resident.facility).name
		routine_label.text="%s %s\nHome   %s\nWork    %s"%[activity,destination,_address(model,resident.home),workplace]
		if resident.work>=0 or resident.shop>=0:
			routine_label.text+=("\nCommute   " if resident.work>=0 else "\nShopping trips   ")+["On foot","Private car","Line 1 bus"][resident.mode]
		if resident.bus>=0:
			var phase:="Walk from" if resident.last_mile else "Walk to"
			if resident.activity==4: phase="Waiting at"
			if resident.activity==5: phase="Aboard · exit at"
			routine_label.text+="  ·  %s stop %02d"%[phase,(resident.alight_at if resident.activity==5 else resident.stop)+1]
		routine_label.text+="\nWallet   $%s   ·   $%s earned"%[grouped(resident.wallet),grouped(resident.wages)]
		if resident.receipt>=0:
			routine_label.text+="\nLast purchase   $12 at %s"%_address(model,resident.store)
		var leg:=Vector3i(resident.id,resident.target,resident.activity)
		if last_leg!=leg:
			last_leg=leg
			journey=model.walking_plan(resident.id,0.)
			queue_redraw()
	life_panel.reset_size()
	life_panel.position.y=size.y-32-life_panel.size.y

func show_transit(net:Dictionary,service:Dictionary,id:int,resident:Dictionary) -> void:
	meet_button.text="Meet a resident"
	meet_button.disabled=false
	bus_button.text="Next bus" if id>=0 else "Follow bus"
	bus_line=PackedVector2Array()
	bus_dots=PackedVector2Array()
	var selected_bus:int=id if id>=0 else resident.get("bus",-1)
	if selected_bus<0: return
	var row:Dictionary=service.buses[selected_bus]
	bus_line=net.line
	for stop in net.stops: bus_dots.append(Vector2(stop.position.x,stop.position.z))
	bus_point=Vector2(row.pose.x,row.pose.z)
	if id>=0:
		var stop:int=row.stop if row.dwell else row.next
		identity.text="Line 1   ·   Town loop"
		routine_label.text="Bus %02d   ·   %s %02d · %s\n%d / %d aboard   ·   %d waiting at stop\nEvery %d city minutes in each direction" % [id+1,"At" if row.dwell else "Next",stop+1,net.stops[stop].name,row.load,net.capacity,service.waiting[stop],net.headway]
		meet_button.text="Meet a rider"
		meet_button.disabled=row.rider<0 and service.first_waiter[stop]<0
		life_panel.reset_size()
	life_panel.position.y=size.y-32-life_panel.size.y
	queue_redraw()

func show_trade(model,b:Dictionary,order:Dictionary,total:int,tick:int) -> void:
	if b.is_empty(): return
	var name_of_goods:String=["Provisions","Garments"][b.goods]
	business_name.text=_address(model,b.id)
	counter.text="View counter" if int(model.lot(b.id).use)==1 else "View yard"
	follow_van.disabled=total==0
	if order.is_empty():
		if freight_id>=0:
			freight_id=-1
			freight_line.clear()
			queue_redraw()
		trading.text="LOCAL TRADE"
		var working:bool=int(model.lot(b.id).use)==2
		var status:String
		if working: status="%s packed"%grouped(b.made)
		elif b.stock==0: status="Sold out"
		else: status="%s sold"%grouped(b.sold)
		trade_line.text="%s  ·  %s"%[name_of_goods,status]
		accounts.text="%s on hand   ·   %s on shift\nTill  $%s    Payroll  $%s"%[grouped(b.stock),b.staff,grouped(b.cash),grouped(b.wages)]
		if b.pending: accounts.text+="\nIncoming order   %d units"%b.pending
		elif b.last_sale>=0: accounts.text+="\nLast sale   $12 at %s"%_time((465+b.last_sale/4)%1440)
		if b.missed: accounts.text+="\n%s purchases unfilled"%grouped(b.missed)
	else:
		if freight_id!=order.id:
			freight_id=order.id
			freight_line=model.delivery_route(order.id)
		freight_point=Vector2(order.position.x,order.position.z)
		queue_redraw()
		var phase:String="Loading" if tick<order.start+20 else ("Unloading" if tick>=order.arrival else "In transit")
		trading.text="DELIVERY %03d   ·   %s"%[order.id,phase.to_upper()]
		trade_line.text="%s  →  %s"%[_address(model,order.source),_address(model,order.shop)]
		accounts.text="%d %s   ·   $%d wholesale\nShop stock   %d now  +  %d on order"%[order.units,name_of_goods.to_lower(),order.units*6,b.stock,b.pending]
	ledger.reset_size()
	ledger.position=Vector2(size.x-35-ledger.size.x,332 if map_open else 112)

func _address(model,id:int) -> String:
	var b:Dictionary=model.lot(id)
	var title: String
	match int(b.use):
		0: title="Residence"
		1: title=["Bakery","Corner café","Grocer","Outfitter"][b.style%4]
		_: title=["Flour mill","Food co-op","Creamery","Textile mill"][b.style%4]
	return "%s %02d"%[title,id+1]

func _time(minute:int) -> String:
	return "%02d:%02d"%[int(minute/60),minute%60]

func show_weather(phase:String,condition:String) -> void:
	weather_label.text=phase+"   ·   "+condition+"   ↗"

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
	while green_dots.size()<state.get("facilities",0):
		var green:Dictionary=sim.facility(green_dots.size())
		green_dots.append(Vector2(green.pos.x,green.pos.z))
		green_types.append(green.kind)
		var popup:=parks_button.get_popup()
		var caption:="%s  ·  %d"%[green.name,green_types.count(green.kind)]
		popup.add_item(caption,green_types.size()-1)
		if green.kind>=6: popup.set_item_text(popup.item_count-1,"★  "+green.name)
		queue_redraw()
	parks_button.disabled=green_dots.is_empty()
	if map_paths.size()==count and land_dots.size()==buildings: return
	while land_dots.size()<buildings:
		var b:Dictionary=sim.lot(land_dots.size())
		land_dots.append(Vector2(b.pos.x,b.pos.z))
		land_uses.append(b.use)
	if river.is_empty() and not sim.is_geographic():
		var extent:=int(sim.region_half_size().y)
		for z in range(-extent,extent+1,8):
			river.append(Vector2(sim.river_x(z),z))
	while map_paths.size()<count:
		var data:Dictionary=sim.street(map_paths.size())
		var line:=PackedVector2Array()
		for p in data.path: line.append(Vector2(p.x,p.z))
		map_paths.append(line)
		map_ranks.append(data["class"])
		map_starts.append(data.started)
		map_opens.append(data.opens)
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
			if map_ranks[i]!=rank: continue
			var path:=map_paths[i]
			if state.tick<map_opens[i]:
				var front:=smoothstep(map_starts[i],map_opens[i],state.tick)*(path.size()-1)
				var k:=mini(int(front),path.size()-2)
				var line:=path.slice(0,k+1)
				line.append(path[k].lerp(path[k+1],front-k))
				draw_polyline(line,GOLD,1.6/scale_factor,true)
				draw_circle(line[-1],2.8/scale_factor,GOLD)
			else: draw_polyline(path,ROUTE_COLORS[rank],[.75,1.15,2.0][rank]/scale_factor,true)
	for i in land_dots.size():
		draw_circle(land_dots[i],clampf(3.5*scale_factor,1.1,2.7)/scale_factor,USE_COLORS[land_uses[i]])
	for i in green_dots.size():
		var dot:=green_dots[i]
		var r:=4./scale_factor
		draw_circle(dot,r,INK)
		var colors:=[Color("#a3cd66"),Color("#f39a75"),Color("#f8cb67"),Color("#79d9cb"),Color("#ee705b"),Color("#86b6f0"),Color("#ffe9a7"),Color("#ffe9a7")]
		draw_circle(dot,r*.76,colors[green_types[i]])
		if green_types[i]>=6: draw_arc(dot,r*1.4,0,TAU,16,colors[green_types[i]],1.2/scale_factor,true)
	if bus_line.size()>1:
		draw_polyline(bus_line,Color("#77dfe1"),2.7/scale_factor,true)
		for p in bus_dots: draw_circle(p,2.5/scale_factor,IVORY)
		draw_circle(bus_point,4.2/scale_factor,Color("#36c6da"))
	if journey.size()>1:
		draw_polyline(journey,Color("#fff0bc"),2.2/scale_factor,true)
		draw_circle(journey[0],3.5/scale_factor,IVORY)
		draw_circle(journey[-1],3.5/scale_factor,GOLD)
	if freight_line.size()>1:
		draw_polyline(freight_line,Color("#faad67"),2.5/scale_factor,true)
		draw_circle(freight_point,4.2/scale_factor,IVORY)
	draw_set_transform(Vector2.ZERO)
	var y:=panel.end.y-45
	var x:=panel.position.x+12
	for rank in [2,1,0]:
		draw_line(Vector2(x,y-4),Vector2(x+12,y-4),ROUTE_COLORS[rank],rank+1.5,true)
		draw_string(sans,Vector2(x+16,y),["Local","Collector","Arterial"][rank],HORIZONTAL_ALIGNMENT_LEFT,-1,13,IVORY)
		x+=85
	for rank in 3:
		var dot:=panel.position+Vector2(13+rank*87,panel.size.y-28)
		draw_circle(dot,3.3,USE_COLORS[rank])
		draw_string(sans,dot+Vector2(7,4),["Housing","Commerce","Industry"][rank],HORIZONTAL_ALIGNMENT_LEFT,-1,12,IVORY)
	for i in 2:
		var dot:=panel.position+Vector2(13+i*87,panel.size.y-11)
		draw_circle(dot,3.3,Color("#a3cd66") if i==0 else Color("#f39a75"))
		draw_string(sans,dot+Vector2(7,4),["Park","Playground"][i],HORIZONTAL_ALIGNMENT_LEFT,-1,12,IVORY)
