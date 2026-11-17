extends Node
## A real HTTP origin lets Google apply browser-key referrer restrictions.
## The page is served only on loopback, once, behind a per-opening random path.
const PORT:=43861
var server:=TCPServer.new()
var clients:Array[Dictionary]=[]
var page_path:=""
var html:=""
var view
var last_flight_frame:=-1
signal selected(lat:float,lon:float)
signal dismissed

func open_map(lat:float,lon:float,has_point:bool) -> bool:
	var key:=OS.get_environment("EMERGENCE_GOOGLE_MAPS_KEY")
	if key.is_empty() or not ClassDB.class_exists("GoogleMapView"): return false
	if server.listen(PORT,"127.0.0.1")!=OK: return false
	var center:=JSON.stringify({"lat":lat if has_point else 22.,"lng":lon if has_point else 13.})
	html=FileAccess.get_file_as_string("res://art/atlas/google_picker.html").replace("MAPS_BROWSER_KEY",key.uri_encode()).replace("INITIAL_CENTER",center).replace("INITIAL_ZOOM","10" if has_point else "2")
	page_path="/"+Crypto.new().generate_random_bytes(20).hex_encode()
	view=ClassDB.instantiate("GoogleMapView")
	var window:=DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,get_window().get_window_id())
	if not view.open_page(window,"http://127.0.0.1:%d%s"%[PORT,page_path]):
		close()
		return false
	return true

func _process(_delta:float) -> void:
	if not view: return
	if server.is_connection_available():
		clients.append({"peer":server.take_connection(),"bytes":PackedByteArray(),"start":Time.get_ticks_msec()})
	for client in clients.duplicate():
		var peer:StreamPeerTCP=client.peer
		peer.poll()
		var count:=peer.get_available_bytes()
		if count>0:
			var read:=peer.get_data(mini(count,8192))
			if read[0]==OK: client.bytes.append_array(read[1])
		var header:String=client.bytes.get_string_from_ascii()
		if header.contains("\r\n\r\n"):
			var ok:=header.begins_with("GET "+page_path+" HTTP/") and not html.is_empty()
			var body:=html.to_utf8_buffer() if ok else PackedByteArray()
			var reply:="HTTP/1.1 %s\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"%["200 OK" if ok else "404 Not Found",body.size()]
			peer.put_data(reply.to_ascii_buffer())
			peer.put_data(body)
			if ok: html=""
			peer.disconnect_from_host()
			clients.erase(client)
		elif header.length()>=8192 or Time.get_ticks_msec()-client.start>4000 or peer.get_status()!=StreamPeerTCP.STATUS_CONNECTED:
			peer.disconnect_from_host()
			clients.erase(client)
	var raw:String=view.next_event()
	if raw.is_empty(): return
	var data=JSON.parse_string(raw)
	if not data is Dictionary: return
	if data.get("action")=="selected" and data.get("lat") is float and data.get("lon") is float:
		selected.emit(data.lat,data.lon)
	elif data.get("action") in ["cancel","failed"]: dismissed.emit()

func tell(data:Dictionary) -> void:
	if view: view.notify_page(JSON.stringify(data))

func advance_flight(t:float) -> void:
	var frame:=floori(t*86.)
	if frame!=last_flight_frame:
		last_flight_frame=frame
		tell({"action":"progress","t":t})

func close() -> void:
	if view: view.dismiss()
	view=null
	server.stop()
	clients.clear()
	html=""

func _exit_tree() -> void:
	close()
