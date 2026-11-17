extends Node3D

var sun:=DirectionalLight3D.new()
var moon:=DirectionalLight3D.new()
var atmosphere:=Environment.new()
var sky_material:=ShaderMaterial.new()
var drops:=MultiMeshInstance3D.new()
var rain_material:=ShaderMaterial.new()
var headlamps:Array[SpotLight3D]=[]
var lamps:=0.
var phase_name:=""
var condition:=""
var last_sky_tick:=-1
const DROP_COUNT=3000
const CLOUD_DRIFT:=Vector2(.0023,-.0014)

func _ready() -> void:
	var sky:=Sky.new()
	sky.process_mode=Sky.PROCESS_MODE_REALTIME
	sky.radiance_size=Sky.RADIANCE_SIZE_256
	sky_material.shader=preload("res://scripts/weather_sky.gdshader")
	sky.sky_material=sky_material
	atmosphere.sky=sky
	atmosphere.background_mode=Environment.BG_SKY
	atmosphere.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	atmosphere.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	atmosphere.tonemap_mode=Environment.TONE_MAPPER_ACES
	atmosphere.fog_enabled=true
	atmosphere.fog_sky_affect=.24
	atmosphere.ssao_enabled=true
	atmosphere.ssao_radius=1.6
	atmosphere.ssao_intensity=1.6
	atmosphere.glow_enabled=true
	atmosphere.glow_intensity=.38
	var environment:=WorldEnvironment.new()
	environment.environment=atmosphere
	add_child(environment)
	sun.shadow_enabled=true
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits=true
	sun.shadow_bias=.035
	sun.shadow_normal_bias=.85
	sun.light_angular_distance=.35
	add_child(sun)
	moon.light_color=Color("#a5bdea")
	add_child(moon)
	for i in 10:
		var beam:=SpotLight3D.new()
		beam.light_color=Color("#fff1cd")
		beam.spot_range=20.
		beam.spot_angle=27.
		beam.spot_angle_attenuation=.62
		beam.spot_attenuation=1.0
		beam.visible=false
		add_child(beam)
		headlamps.append(beam)
	_make_rain()

func _make_rain() -> void:
	var batch:=MultiMesh.new()
	batch.transform_format=MultiMesh.TRANSFORM_3D
	batch.use_custom_data=true
	batch.mesh=QuadMesh.new()
	batch.instance_count=DROP_COUNT
	var rng:=RandomNumberGenerator.new()
	rng.seed=38911
	for i in DROP_COUNT:
		batch.set_instance_transform(i,Transform3D.IDENTITY)
		batch.set_instance_custom_data(i,Color(rng.randf(),rng.randf(),rng.randf(),rng.randf()))
	drops.multimesh=batch
	rain_material.shader=preload("res://scripts/rain.gdshader")
	drops.material_override=rain_material
	drops.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(drops)

func sync(w:Dictionary,tick:float,orbit:Camera3D) -> void:
	var direction:Vector3=w.sun
	var daylight:=smoothstep(-.14,.14,direction.y)
	var twilight:=(1.-smoothstep(.02,.29,absf(direction.y)))*smoothstep(-.20,-.04,direction.y)
	var cover:float=w.clouds
	var rain:float=w.rain
	lamps=1.-smoothstep(-.075,.105,direction.y-cover*.035)
	var rising:=direction.x>=0.
	if direction.y<-.115: phase_name="Night"
	elif direction.y<.14: phase_name="Dawn" if rising else "Dusk"
	else: phase_name="Day"
	if rain>=.34: condition="Rain"
	elif rain>=.045: condition="Light rain"
	elif cover>.63: condition="Overcast"
	elif cover>.27: condition="Partly cloudy"
	else: condition="Clear skies"
	sun.rotation=Vector3(-asin(clampf(direction.y,-1.,1.)),atan2(direction.x,direction.z),0.)
	moon.rotation=Vector3(asin(clampf(direction.y,-1.,1.)),atan2(-direction.x,-direction.z),0.)
	sun.light_energy=smoothstep(-.035,.18,direction.y)*(1.10-.88*cover)
	sun.light_color=Color("#ffad78").lerp(Color("#fff2dc"),smoothstep(.025,.34,direction.y))
	sun.directional_shadow_max_distance=clampf(orbit.size*2.8,95.,1700.)
	sun.shadow_opacity=1.-cover*.62
	moon.light_energy=.32*(1.-daylight)*(1.-cover*.64)
	atmosphere.ambient_light_color=Color("#a2b4cf").lerp(Color("#dae4ed").lerp(Color("#acbdca"),cover),daylight)
	atmosphere.ambient_light_energy=lerpf(.40,.55+cover*.06,daylight)
	atmosphere.background_energy_multiplier=lerpf(.43,1.,daylight)
	var mist:=Color("#a1b5c5").lerp(Color("#99a7b3"),cover)
	mist=mist.lerp(Color("#efbd9d"),twilight*.78*(1.-cover))
	atmosphere.fog_light_color=Color("#526783").lerp(mist,daylight)
	atmosphere.fog_light_energy=lerpf(.18,.92,daylight)
	atmosphere.fog_density=.00012+cover*.00036+rain*.0023
	# The reflected sky changes slowly. Refresh once per simulated minute.
	var sky_tick:=floori(tick/4.)
	if sky_tick!=last_sky_tick:
		last_sky_tick=sky_tick
		sky_material.set_shader_parameter("sun_direction",direction)
		sky_material.set_shader_parameter("daylight",daylight)
		sky_material.set_shader_parameter("twilight",twilight)
		sky_material.set_shader_parameter("cover",cover)
		sky_material.set_shader_parameter("cloud_scroll",CLOUD_DRIFT*sky_tick)
	drops.visible=rain>.009
	if drops.visible:
		# Denser nearby sheets retain individual streaks. Distant rain is expressed by haze.
		var width:=clampf(orbit.size*2.15,43.,340.)
		var height:=clampf(orbit.size*.94,28.,132.)
		var focus:Vector3=orbit.pivot.lerp(orbit.position,.27)
		var span:=Vector3(width,height,width)
		drops.custom_aabb=AABB(focus-span*.5,span).grow(3.)
		drops.multimesh.visible_instance_count=ceili(DROP_COUNT*rain)
		rain_material.set_shader_parameter("center",focus)
		rain_material.set_shader_parameter("span",Vector2(width,height))
		rain_material.set_shader_parameter("intensity",rain)
		rain_material.set_shader_parameter("wind",w.wind)
		rain_material.set_shader_parameter("fall_phase",fposmod(tick/12.,1.))

func light_traffic(camera:Camera3D,transit,trade) -> void:
	var vehicles:Array[Node3D]=[]
	if lamps>.035:
		vehicles.append_array(transit.buses)
		vehicles.append_array(transit.cars.values())
		for truck in trade.trucks.values(): vehicles.append(truck.body)
		vehicles.sort_custom(func(a:Node3D,b:Node3D): return camera.pivot.distance_squared_to(a.position)<camera.pivot.distance_squared_to(b.position))
	for i in headlamps.size():
		var beam:=headlamps[i]
		beam.visible=i<vehicles.size()
		if beam.visible:
			var vehicle:=vehicles[i]
			var front:=vehicle.global_basis.x.normalized()
			var length:=3.74 if vehicle in transit.buses else 2.12
			beam.position=vehicle.position+front*length+Vector3.UP*.73
			beam.look_at(beam.position+front-Vector3.UP*.16)
			beam.light_energy=5.4*lamps
