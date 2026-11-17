extends Camera3D
var pivot:=Vector3(-24,5,1)
var azimuth:=-.58
var elevation:=.59
var extent:=158.
var following:=true
var landmark_peak:=Vector3.ZERO
var city_bounds:=Vector4(-115,-70,65,70)
var orbiting:=false
var panning:=false

func _ready() -> void:
	projection=Camera3D.PROJECTION_PERSPECTIVE
	fov=38.
	near=.20
	far=4200
	update_view()

func update_view() -> void:
	size=extent
	position=pivot+Vector3(sin(azimuth)*cos(elevation),sin(elevation),cos(azimuth)*cos(elevation))*(extent*.5/tan(deg_to_rad(fov)*.5))
	look_at(pivot,Vector3.UP)

# In a perspective view, a tower on the near bank needs more room than
# one on the horizon. Project the city's ground corners and the spire.
func skyline_extent(center:Vector3,peak:Vector3,bounds:Vector4) -> float:
	var back:=Vector3(sin(azimuth)*cos(elevation),sin(elevation),cos(azimuth)*cos(elevation))
	var right:=Vector3(cos(azimuth),0,-sin(azimuth))
	var up:=back.cross(right)
	var viewport_size:=get_viewport().get_visible_rect().size
	var aspect:=viewport_size.x/viewport_size.y
	var lens:=tan(deg_to_rad(fov)*.5)
	var needed:=0.
	for point:Vector3 in [peak,Vector3(bounds.x,0,bounds.y),Vector3(bounds.z,0,bounds.y),Vector3(bounds.x,0,bounds.w),Vector3(bounds.z,0,bounds.w)]:
		var offset:=point-center
		var half_screen:=maxf(absf(offset.dot(right))/aspect,absf(offset.dot(up)))
		needed=maxf(needed,2.*(half_screen*1.10+lens*offset.dot(back)))
	return needed

func frame_city(bounds:Vector4,weight:float) -> void:
	city_bounds=bounds
	if not following: return
	var dx:=bounds.z-bounds.x
	var dz:=bounds.w-bounds.y
	var right:=absf(cos(azimuth))
	var depth:=absf(sin(azimuth))
	var viewport_size:=get_viewport().get_visible_rect().size
	var horizontal:=(dx*right+dz*depth)*viewport_size.y/viewport_size.x
	var vertical:=(dz*right+dx*depth)*sin(elevation)
	var goal:=clampf(maxf(horizontal,vertical)*1.05+31.,160.,1000.)
	var center:=Vector3((bounds.x+bounds.z)*.5,8,(bounds.y+bounds.w)*.5)
	if landmark_peak!=Vector3.ZERO:
		center.y=maxf(center.y,landmark_peak.y*.35)
		goal=maxf(goal,skyline_extent(center,landmark_peak,bounds))
	extent=lerpf(extent,goal,weight)
	pivot=pivot.lerp(center,weight)
	update_view()

func home() -> void:
	following=true
	azimuth=-.58
	elevation=.59
	frame_city(city_bounds,1.)

func zoom_by(factor: float) -> void:
	following=false
	extent=clampf(extent*factor,16,1050)
	update_view()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT or event.button_index==MOUSE_BUTTON_RIGHT:
			orbiting=event.pressed and not event.shift_pressed
			panning=event.pressed and event.shift_pressed
		if event.button_index==MOUSE_BUTTON_MIDDLE: panning=event.pressed
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_UP: zoom_by(pow(.91,maxf(1,event.factor)))
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN: zoom_by(pow(1/.91,maxf(1,event.factor)))
	elif event is InputEventMouseMotion:
		if not event.button_mask:
			orbiting=false
			panning=false
		if orbiting:
			following=false
			azimuth-=event.relative.x*.006
			elevation=clampf(elevation+event.relative.y*.005,.24,1.35)
		if panning: _pan(event.relative)
	elif event is InputEventMagnifyGesture:
		zoom_by(1/event.factor)
	elif event is InputEventPanGesture:
		_pan(event.delta*8)
	elif event is InputEventKey and event.pressed and event.keycode==KEY_H:
		home()
	update_view()

func _pan(delta:Vector2) -> void:
	following=false
	var forward:=Vector3(sin(azimuth),0,cos(azimuth))
	pivot+=(forward*(-delta.y)/sin(elevation)-global_basis.x*delta.x)*extent/get_viewport().get_visible_rect().size.y
	pivot.x=clampf(pivot.x,-480,480)
	pivot.z=clampf(pivot.z,-320,320)
