extends SceneTree
var google
var selected:=false
var timeout:=Timer.new()
func _initialize(): run.call_deferred()
func run():
	google=load("res://scripts/google_picker.gd").new()
	root.add_child(google)
	OS.set_environment("EMERGENCE_GOOGLE_MAPS_KEY","local-transport-test")
	if not google.open_map(0,0,false):
		quit(1)
		return
	# Run the shipped page in WebKit. Replace only the external SDK with a
	# local map double so the test consumes no Google API requests.
	google.html=google.html.left(google.html.find('<script async src='))+'''<script>
	const testPoint={lat:()=>35.798,lng:()=>126.825};
	window.google={maps:{RenderingType:{VECTOR:"VECTOR"},SymbolPath:{CIRCLE:1},
	  Marker:class{setPosition(){}},Map:class{
	    addListener(action,fn){if(action==="click")setTimeout(()=>{fn({latLng:testPoint});document.querySelector("#found").click()},20)}
	    getCenter(){return {lat:()=>22,lng:()=>13}} getZoom(){return 2}
	    moveCamera(args){if(args.zoom>10)window.webkit.messageHandlers.settlement.postMessage(JSON.stringify({action:"cancel"}))}
	  }}};
	initMap();
	</script></html>'''
	google.selected.connect(func(a,b):
		selected=absf(a-35.798)<.0001 and absf(b-126.825)<.0001
		print("Native HTML click through WebKit: ",selected)
		google.tell({"action":"fly"})
		google.advance_flight(.75))
	google.dismissed.connect(finished)
	root.add_child(timeout)
	timeout.one_shot=true
	timeout.timeout.connect(func(): finished(true))
	timeout.start(12.)
func finished(expired:=false):
	print("Embedded camera callback: ",not expired and selected)
	timeout.stop()
	timeout.queue_free()
	google.close()
	google.queue_free()
	google=null
	await process_frame
	quit(1 if expired or not selected else 0)
