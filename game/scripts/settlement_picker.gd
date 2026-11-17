extends Control
const AtlasMap=preload("res://scripts/atlas_map.gd")
const Geo=preload("res://scripts/geography.gd")
const SITES=[
	["김제 평야",35.798,126.825],["루아르 계곡",47.342,.465],["새크라멘토 계곡",38.548,-121.685]]
const INK:=Color("#f3efdf")
const MUTED:=Color("#b6c6bc")
signal founded(model,lat:float,lon:float,place:String)
signal resume_requested
var google=preload("res://scripts/google_picker.gd").new()
var geo=Geo.new()
var atlas=AtlasMap.new()
var card:=PanelContainer.new()
var title:Label
var location:=LineEdit.new()
var seed_entry:=LineEdit.new()
var coordinates:Label
var status:Label
var begin:Button
var controls:=Control.new()
var map_credit:Button
var back:Button
var lat:=0.
var lon:=0.
var place:=""
var chosen:=false
var busy:=false
var returnable:=false
var focus_tween:Tween
var notice:=AcceptDialog.new()
var label_font:=SystemFont.new()

func _style(color:Color,radius:=8) -> StyleBoxFlat:
	var s:=StyleBoxFlat.new()
	s.bg_color=color
	s.set_corner_radius_all(radius)
	for side in [SIDE_LEFT,SIDE_RIGHT]: s.set_content_margin(side,12)
	for side in [SIDE_TOP,SIDE_BOTTOM]: s.set_content_margin(side,8)
	return s

func _button(parent:Control,text:String,action:Callable,primary:=false) -> Button:
	var btn:=Button.new()
	parent.add_child(btn)
	btn.text=text
	btn.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	btn.focus_mode=Control.FOCUS_NONE
	btn.add_theme_stylebox_override("normal",_style(Color("#cde4b4") if primary else Color("#374b43")))
	btn.add_theme_stylebox_override("hover",_style(Color("#e8f1d2") if primary else Color("#4c6357")))
	btn.add_theme_stylebox_override("pressed",_style(Color("#9ab693") if primary else Color("#263f34")))
	btn.add_theme_stylebox_override("disabled",_style(Color("#36453d")))
	btn.add_theme_color_override("font_color",Color("#20342b") if primary else INK)
	btn.add_theme_color_override("font_hover_color",Color("#20342b") if primary else Color.WHITE)
	btn.add_theme_font_size_override("font_size",15)
	btn.pressed.connect(action)
	return btn

func _text(parent:Control,value:String,points:int,color:Color=INK) -> Label:
	var label:=Label.new()
	label.text=value
	label.add_theme_font_size_override("font_size",points)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label_font.font_names=PackedStringArray(["Avenir Next","Apple SD Gothic Neo","Helvetica Neue"])
	var theme_local:=Theme.new()
	theme_local.default_font=label_font
	theme=theme_local
	add_child(geo)
	add_child(google)
	google.selected.connect(_google_selected)
	google.dismissed.connect(google.close)
	atlas.geo=geo
	add_child(atlas)
	atlas.navigated.connect(_stop_focus)
	atlas.picked.connect(func(a,b): select_point(a,b,""))
	add_child(controls)
	controls.z_index=30
	controls.mouse_filter=Control.MOUSE_FILTER_IGNORE
	controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	controls.add_child(card)
	var box:=_style(Color("#1e322cf5"),12)
	for side in [SIDE_LEFT,SIDE_RIGHT]: box.set_content_margin(side,22)
	for side in [SIDE_TOP,SIDE_BOTTOM]: box.set_content_margin(side,17)
	card.add_theme_stylebox_override("panel",box)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",7)
	card.add_child(column)
	_text(column,"E M E R G E N C E",13,Color("#bdd8aa"))
	title=_text(column,"정착지 선택",32)
	coordinates=_text(column,"세계지도에서 정착할 곳을 클릭하세요.",16)
	location.placeholder_text="도시 · 위도, 경도 · Google 지도 링크"
	location.clear_button_enabled=true
	location.custom_minimum_size.y=35
	location.add_theme_font_size_override("font_size",15)
	var search:=HBoxContainer.new()
	column.add_child(search)
	search.add_child(location)
	location.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	location.text_submitted.connect(func(_s): _locate())
	_button(search,"찾기",_locate)
	var spots:=HBoxContainer.new()
	column.add_child(spots)
	for data in SITES:
		_button(spots,data[0],func(): select_point(data[1],data[2],data[0],true))
	seed_entry.placeholder_text="도시 시드 · 비워 두면 매번 새 도시"
	seed_entry.max_length=10
	seed_entry.tooltip_text="같은 좌표와 시드를 입력하면 같은 도시가 자랍니다."
	column.add_child(seed_entry)
	var actions:=HBoxContainer.new()
	column.add_child(actions)
	begin=_button(actions,"새 도시 시작" if returnable else "이곳에 정착",_begin,true)
	begin.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	begin.disabled=true
	_button(actions,"Google 지도 ↗" if OS.get_environment("EMERGENCE_GOOGLE_MAPS_KEY").is_empty() else "Google 지도",_google)
	status=_text(column,"드래그로 이동 · 스크롤로 확대",14,MUTED)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var zoom_buttons:=VBoxContainer.new()
	controls.add_child(zoom_buttons)
	zoom_buttons.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	zoom_buttons.offset_left=-70
	zoom_buttons.offset_right=-20
	_button(zoom_buttons,"+",func(): atlas.set_zoom(atlas.zoom+1.,atlas.size*.5))
	_button(zoom_buttons,"−",func(): atlas.set_zoom(atlas.zoom-1.,atlas.size*.5))
	map_credit=_button(controls,"Natural Earth  ·  Mapzen  ⓘ",func(): notice.popup_centered(Vector2i(650,530)))
	map_credit.add_theme_font_size_override("font_size",12)
	back=_button(controls,"도시로 돌아가기",func(): resume_requested.emit())
	back.visible=returnable
	add_child(notice)
	notice.title="지도와 지형 데이터"
	notice.dialog_text=FileAccess.get_file_as_string("res://art/atlas/credits.txt")
	resized.connect(_layout)
	_layout()
	if not returnable and not OS.get_environment("EMERGENCE_GOOGLE_MAPS_KEY").is_empty():
		_google.call_deferred()

func _layout() -> void:
	card.size=Vector2(minf(420.,size.x-40),0)
	card.position=Vector2(27,size.y-card.size.y-28)
	map_credit.position=Vector2(size.x-map_credit.size.x-13,size.y-map_credit.size.y-12)
	back.position=Vector2(26,23)

func select_point(a:float,b:float,name:String,focus:=false) -> void:
	if busy: return
	if not is_finite(a) or not is_finite(b) or absf(a)>85. or absf(b)>180.:
		status.text="위도 ±85°와 경도 ±180° 안에서 선택하세요."
		return
	lat=a
	lon=b
	place=name
	chosen=true
	atlas.pin=Geo.mercator(a,b)
	title.text=name if name!="" else "선택한 정착지"
	coordinates.text="%.5f° %s    %.5f° %s"%[absf(a),"N" if a>=0 else "S",absf(b),"E" if b>=0 else "W"]
	status.text="새 도시를 시작하면 현재 정착지가 종료됩니다." if returnable else "이 지점 주변의 실제 지형으로 시작합니다."
	begin.disabled=false
	_stop_focus()
	if focus:
		var start:Vector2=atlas.center
		var offset:=Vector2(wrapf(atlas.pin.x-start.x,-.5,.5),atlas.pin.y-start.y)
		var zoom_from:float=atlas.zoom
		focus_tween=create_tween()
		focus_tween.tween_method(func(t:float):
			var p:=smoothstep(0.,1.,t)
			atlas.center=start+offset*p
			atlas.zoom=lerpf(zoom_from,3.5,p)
			atlas._bound()
		,0.,1.,.9)

func _stop_focus() -> void:
	if focus_tween: focus_tween.kill()
	focus_tween=null

static func parse_point(raw:String) -> Array:
	var value:=raw.strip_edges().uri_decode()
	for pattern in ["!3d(-?[0-9.]+)!4d(-?[0-9.]+)","@(-?[0-9.]+),\\s*(-?[0-9.]+)","(?:[?&](?:query|q|ll)=|^\\s*)([+-]?[0-9]+(?:\\.[0-9]+)?)[,，]\\s*([+-]?[0-9]+(?:\\.[0-9]+)?)(?:$|[&/ ])"]:
		var regex:=RegEx.new()
		regex.compile(pattern)
		var m:=regex.search(value)
		if m and m.get_string(1).is_valid_float() and m.get_string(2).is_valid_float():
			return [float(m.get_string(1)),float(m.get_string(2))]
	return []

func _locate() -> void:
	if busy: return
	var query:=location.text.strip_edges()
	var result:=parse_point(query)
	if result.is_empty() and query.begins_with("https://maps.app.goo.gl/"):
		busy=true
		begin.disabled=true
		status.text="Google 지도 링크를 확인하고 있습니다…"
		var req:=HTTPRequest.new()
		req.timeout=8
		req.max_redirects=0
		add_child(req)
		if req.request(query)==OK:
			var response:Array=await req.request_completed
			for header in response[2]:
				if header.to_lower().begins_with("location:"): result=parse_point(header.substr(9))
		req.queue_free()
		busy=false
		begin.disabled=not chosen
	if result.is_empty() and query!="":
		for city in AtlasMap.PLACES.data:
			if query.to_lower()==String(city[0]).to_lower() or query==city[4] or (query.length()>=2 and String(city[4]).begins_with(query)):
				select_point(city[2],city[1],city[4] if city[4]!="" else city[0],true)
				location.release_focus()
				return
	if result.is_empty():
		status.text="좌표를 확인할 수 없습니다. Google 지도에서 위도와 경도를 복사해 주세요."
		return
	select_point(result[0],result[1],"",true)
	location.release_focus()

func _google_selected(a:float,b:float) -> void:
	if absf(a)>85. or absf(b)>180.:
		google.tell({"action":"retry","message":"위도 ±85° 안에서 정착할 곳을 선택하세요."})
		return
	select_point(a,b,"")
	_begin()

func _google() -> void:
	if busy or google.view: return
	if not OS.get_environment("EMERGENCE_GOOGLE_MAPS_KEY").is_empty():
		if not google.open_map(lat,lon,chosen): status.text="앱 안의 Google 지도를 열 수 없습니다. 기본 세계지도에서 선택하세요."
		return
	status.text="Google 지도에서 좌표를 복사한 뒤 이곳에 붙여넣으세요."
	var url:="https://www.google.com/maps"
	if chosen: url+="?q=%.6f,%.6f"%[lat,lon]
	OS.shell_open(url)

func _begin() -> void:
	if busy or not chosen: return
	var value:=seed_entry.text.strip_edges()
	if value!="" and (not value.is_valid_int() or int(value)<0 or int(value)>2147483647):
		status.text="시드는 0부터 2147483647 사이의 정수로 입력하세요."
		google.tell({"action":"retry","message":status.text})
		return
	var city_seed:=int(value) if value!="" else Crypto.new().generate_random_bytes(4).decode_u32(0) & 0x7fffffff
	_stop_focus()
	busy=true
	begin.disabled=true
	atlas.interact=false
	location.release_focus()
	status.text="정착지 주변의 표고와 호수를 확인하고 있습니다…"
	var data:Dictionary=await geo.survey(lat,lon)
	var model:=CityModel.new()
	if data.is_empty() or not model.settle_at(city_seed,lat,lon,data.heights,data.lakes):
		status.text="지형을 불러오지 못했습니다. 연결을 확인하고 다시 시도하세요." if data.is_empty() else "물이나 급경사가 초기 정착지와 겹칩니다. 가까운 평지를 선택하세요."
		google.tell({"action":"retry","message":status.text})
		busy=false
		atlas.interact=true
		begin.disabled=false
		_layout()
		return
	# Prime progressively finer relief while the 3D scene is being prepared.
	for z in [4,6,8,10,12]:
		var k:=Geo.key_at(atlas.pin,z)
		for dy in range(-1,2):
			for dx in range(-1,2):
				var neighbour:=Vector3i(posmod(k.x+dx,1<<z),clampi(k.y+dy,0,(1<<z)-1),z)
				if FileAccess.file_exists("res://art/atlas/tiles/"+Geo.filename(neighbour)): geo.want(neighbour,true)
		geo.want(k,true)
	status.text="선택한 지형에 정착지를 준비하고 있습니다…"
	await get_tree().process_frame
	founded.emit(model,lat,lon,place)
