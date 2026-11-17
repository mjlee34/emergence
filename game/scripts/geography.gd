extends Node
## Tilezen Terrarium pixels contain absolute elevations, not display colours.
const EARTH:=40075016.68557849
const SIDE:=169
const STEP:=20.
const CACHE:="user://terrain-v1"
const SOURCE:="https://s3.amazonaws.com/elevation-tiles-prod/terrarium"
const LAKES=preload("res://art/atlas/lakes.json")
var tiles:Dictionary={}
var textures:Dictionary={}
var pending:Dictionary={}
var failed:Dictionary={}
var last_used:Dictionary={}
var queue:Array[Vector3i]=[]
var local_queue:Array[Vector3i]=[]
var held:Dictionary={}
var active:=0

static func mercator(lat:float,lon:float) -> Vector2:
	return Vector2((lon+180.)/360.,.5-asinh(tan(deg_to_rad(clampf(lat,-85.05,85.05))))/TAU)

static func geographic(uv:Vector2) -> Vector2:
	return Vector2(rad_to_deg(atan(sinh(PI*(1.-2.*uv.y)))),fposmod(uv.x,1.)*360.-180.)

static func dem_zoom(lat:float) -> int:
	return clampi(roundi(log(156543.0339*cos(deg_to_rad(lat))/STEP)/log(2.)),8,13)

static func key_at(uv:Vector2,z:int) -> Vector3i:
	var n:=1<<z
	return Vector3i(posmod(floori(uv.x*n),n),clampi(floori(uv.y*n),0,n-1),z)

static func filename(key:Vector3i) -> String:
	return "%d_%d_%d.terr"%[key.z,key.x,key.y]

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE))

func _decode(bytes:PackedByteArray,key:Vector3i) -> bool:
	var im:=Image.new()
	if im.load_png_from_buffer(bytes)!=OK or im.get_size()!=Vector2i(256,256): return false
	im.convert(Image.FORMAT_RGB8)
	tiles[key]=im.get_data()
	textures[key]=ImageTexture.create_from_image(im)
	last_used[key]=Time.get_ticks_msec()
	return true

func want(key:Vector3i,priority:=false) -> void:
	last_used[key]=Time.get_ticks_msec()
	if tiles.has(key): return
	if pending.has(key):
		if priority and queue.has(key):
			queue.erase(key)
			queue.push_front(key)
		return
	if failed.has(key) and Time.get_ticks_msec()-int(failed[key])<8000: return
	failed.erase(key)
	pending[key]=true
	var name:=filename(key)
	if FileAccess.file_exists("res://art/atlas/tiles/"+name) or FileAccess.file_exists(CACHE+"/"+name):
		if priority: local_queue.push_front(key)
		else: local_queue.append(key)
	elif priority: queue.push_front(key)
	else: queue.append(key)

func _process(_delta:float) -> void:
	for _i in 2:
		if local_queue.is_empty(): break
		_fetch(local_queue.pop_front())
	if active>=5 or queue.is_empty(): return
	var key:Vector3i=queue.pop_front()
	_fetch(key)

func _fetch(key:Vector3i) -> void:
	active+=1
	var name:=filename(key)
	var disk:=CACHE+"/"+name
	var ok:=false
	for path in ["res://art/atlas/tiles/"+name,disk]:
		if FileAccess.file_exists(path) and _decode(FileAccess.get_file_as_bytes(path),key):
			ok=true
			break
	if not ok:
		var request:=HTTPRequest.new()
		request.timeout=12.
		request.body_size_limit=512*1024
		add_child(request)
		if request.request("%s/%d/%d/%d.png"%[SOURCE,key.z,key.x,key.y])==OK:
			var response:Array=await request.request_completed
			ok=response[0]==HTTPRequest.RESULT_SUCCESS and response[1]==200 and _decode(response[3],key)
			if ok:
				var partial:=disk+".%d.part"%OS.get_process_id()
				var file:=FileAccess.open(partial,FileAccess.WRITE)
				if file:
					file.store_buffer(response[3])
					file.close()
					DirAccess.rename_absolute(ProjectSettings.globalize_path(partial),ProjectSettings.globalize_path(disk))
		request.queue_free()
	if not ok: failed[key]=Time.get_ticks_msec()
	pending.erase(key)
	active-=1
	if tiles.size()>112:
		var oldest:Vector3i=key
		for k in tiles:
			if not held.has(k) and (held.has(oldest) or last_used[k]<last_used[oldest]): oldest=k
		tiles.erase(oldest)
		textures.erase(oldest)
		last_used.erase(oldest)

func _sample(x:int,y:int,z:int) -> float:
	var n:=1<<z
	var key:=Vector3i(posmod(x>>8,n),clampi(y>>8,0,n-1),z)
	var bytes:PackedByteArray=tiles[key]
	var i:=(posmod(y,256)*256+posmod(x,256))*3
	return bytes[i]*256.+bytes[i+1]+bytes[i+2]/256.-32768.

func _lake_mask(lat:float,lon:float) -> PackedByteArray:
	var mask:=PackedByteArray()
	mask.resize(SIDE*SIDE)
	var lat_step:=STEP*360./EARTH
	var lon_step:=lat_step/cos(deg_to_rad(lat))
	for polygon in LAKES.data:
		var b:Array=polygon[0]
		if lon+84*lon_step<b[0] or lon-84*lon_step>b[2] or lat+84*lat_step<b[1] or lat-84*lat_step>b[3]: continue
		for row in SIDE:
			var latitude:=lat-(row-84)*lat_step
			var hits:Array[float]=[]
			for ring in polygon[1]:
				for k in range(2,ring.size(),2):
					var y0:float=ring[k-1]
					var y1:float=ring[k+1]
					if (y0>latitude)==(y1>latitude): continue
					hits.append(lerpf(ring[k-2],ring[k],(latitude-y0)/(y1-y0)))
			hits.sort()
			for k in range(1,hits.size(),2):
				for col in range(maxi(0,ceili((hits[k-1]-lon)/lon_step)+84),mini(SIDE,floori((hits[k]-lon)/lon_step)+85)):
					mask[row*SIDE+col]=1
	return mask

func survey(lat:float,lon:float) -> Dictionary:
	var z:=dem_zoom(lat)
	var pixels:=float(256<<z)
	# Keep the source pixel origin in doubles, including at the date line.
	var cx:=(lon+180.)/360.*pixels-.5
	var cy:=(.5-asinh(tan(deg_to_rad(lat)))/TAU)*pixels-.5
	var stride:=STEP*pixels/(EARTH*cos(deg_to_rad(lat)))
	var reach:=stride*(SIDE/2)
	var needed:Array[Vector3i]=[]
	for y in range(floori(cy-reach)>>8,((floori(cy+reach)+1)>>8)+1):
		for x in range(floori(cx-reach)>>8,((floori(cx+reach)+1)>>8)+1):
			var key:=Vector3i(posmod(x,1<<z),clampi(y,0,(1<<z)-1),z)
			held[key]=true
			want(key,true)
			needed.append(key)
	while true:
		var ready:=true
		for key in needed:
			if failed.has(key) and not pending.has(key):
				held.clear()
				return {}
			if not tiles.has(key): ready=false
		if ready: break
		await get_tree().process_frame
	var samples:=PackedInt32Array()
	samples.resize(SIDE*SIDE)
	for row in SIDE:
		var y:=cy+(row-SIDE/2)*stride
		var iy:=floori(y)
		for col in SIDE:
			var x:=cx+(col-SIDE/2)*stride
			var ix:=floori(x)
			var top:=lerpf(_sample(ix,iy,z),_sample(ix+1,iy,z),x-ix)
			var bottom:=lerpf(_sample(ix,iy+1,z),_sample(ix+1,iy+1,z),x-ix)
			samples[row*SIDE+col]=roundi(10.*lerpf(top,bottom,y-iy))
	held.clear()
	return {"heights":samples,"lakes":_lake_mask(lat,lon)}
