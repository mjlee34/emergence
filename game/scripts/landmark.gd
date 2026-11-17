extends RefCounted
const Forms=preload("res://scripts/forms.gd")
const LIMESTONE:=Color("#c8c0ae")
const STEEL:=Color("#5b666b")
const CAP:=Color("#353d40")

static func lattice(g,metal:Color) -> void:
	var levels:=[Vector2(0.,5.15),Vector2(4.,4.05),Vector2(8.,2.65),Vector2(12.,1.9),Vector2(17.,1.25),Vector2(23.,.77),Vector2(29.,.38)]
	var corners:=[Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]
	for corner:Vector2 in corners:
		g.box(Vector3(corner.x*5.15,.34,corner.y*5.15),Vector3(2.05,.68,2.05),LIMESTONE)
	g.finish=Forms.Finish.METAL
	for i in levels.size()-1:
		var lo:Vector2=levels[i]
		var hi:Vector2=levels[i+1]
		for j in 4:
			var a:Vector2=corners[j]
			var b:Vector2=corners[(j+1)%4]
			var p:=Vector3(a.x*lo.y,lo.x+.6,a.y*lo.y)
			var q:=Vector3(b.x*lo.y,lo.x+.6,b.y*lo.y)
			var u:=Vector3(a.x*hi.y,hi.x+.6,a.y*hi.y)
			var v:=Vector3(b.x*hi.y,hi.x+.6,b.y*hi.y)
			g.beam(p,u,.64/(1.+i*.23),metal)
			g.beam(u,v,.23/(1.+i*.18),metal)
			if i>0:
				g.beam(p,v,.16/(1.+i*.13),metal)
				g.beam(q,u,.16/(1.+i*.13),metal)
			else:
				var prev:=p
				for seg in range(1,13):
					var t:=seg/12.
					var arch:=p.lerp(q,t)+Vector3.UP*5.25*sqrt(maxf(0.,1.-pow(2.*t-1.,2)))
					g.beam(prev,arch,.26,metal)
					prev=arch
	for deck in [Vector2(8.55,6.4),Vector2(17.5,3.65),Vector2(29.8,1.75)]:
		g.box(Vector3.UP*deck.x,Vector3(deck.y,.55,deck.y),metal)
		# A lit cornice reads as an observation deck across the river at dusk.
		g.finish=Forms.Finish.LAMP
		g.box(Vector3.UP*(deck.x+.18),Vector3(deck.y+.05,.075,deck.y+.05),LIMESTONE)
		g.finish=Forms.Finish.METAL
		for side in [-1.,1.]:
			g.box(Vector3(0,deck.x+.54,side*deck.y*.48),Vector3(deck.y,.10,.10),LIMESTONE)
			g.box(Vector3(side*deck.y*.48,deck.x+.54,0),Vector3(.10,.10,deck.y),LIMESTONE)
	g.taper(Vector3.UP*30.,.68,.14,2.2,12,metal)
	g.taper(Vector3.UP*32.2,.11,.03,2.2,8,metal)
	g.finish=Forms.Finish.LAMP
	g.taper(Vector3.UP*34.4,.11,.04,.24,8,LIMESTONE)

static func liberty(g,metal:Color) -> void:
	for layer in [Vector3(5.2,.6,0),Vector3(4.8,.6,.6),Vector3(4.25,.5,1.2),Vector3(3.7,3.2,1.7),Vector3(4.4,.48,4.9)]:
		g.box(Vector3.UP*(layer.z+layer.y*.5),Vector3(layer.x,layer.y,layer.x),LIMESTONE)
	g.finish=Forms.Finish.METAL
	for side in [-1.,1.]:
		for bay in [-1.2,-.6,0.,.6,1.2]:
			g.box(Vector3(bay,3.91,side*1.86),Vector3(.42,.85,.05),Color("#938974"))
			g.box(Vector3(side*1.86,3.91,bay),Vector3(.05,.85,.42),Color("#938974"))
	var base:=Vector3.UP*5.38
	g.profile(base,[Vector3(1.35,0,.94),Vector3(1.18,1.1,.84),Vector3(.75,3.45,.62),Vector3(.98,4.85,.64),Vector3(.40,5.25,.37)],metal,16)
	for i in 12:
		var a:=TAU*i/12.
		g.beam(base+Vector3(1.23*cos(a),.20,.88*sin(a)),base+Vector3(.78*cos(a+.63),4.6,.55*sin(a+.63)),.11,Color("#658e82"))
	g.profile(base+Vector3.UP*5.17,[Vector3(.27,0,.29),Vector3(.48,.25,.46),Vector3(.50,.82,.44),Vector3(.33,1.,.34)],metal,14)
	g.profile(base+Vector3(0,5.47,-.32),[Vector3(.25,0,.17),Vector3(.34,.30,.23),Vector3(.31,.51,.18)],Color("#86ab9b"),12)
	g.beam(base+Vector3(0,5.89,-.50),base+Vector3(0,5.67,-.62),.11,metal)
	g.taper(base+Vector3.UP*5.97,.56,.46,.20,12,metal)
	for i in 7:
		var a:=TAU*i/7.
		g.beam(base+Vector3(.4*cos(a),6.08,.4*sin(a)),base+Vector3(.95*cos(a),6.68,.95*sin(a)),.12,metal)
	g.beam(base+Vector3(-.82,4.76,0),base+Vector3(-1.17,5.88,-.12),.54,metal)
	g.beam(base+Vector3(-1.17,5.88,-.12),base+Vector3(-1.23,7.14,-.14),.34,metal)
	var hand:=base+Vector3(-1.23,7.08,-.14)
	g.taper(hand,.18,.22,.66,10,metal)
	g.taper(hand+Vector3.UP*.63,.20,.49,.31,10,metal)
	g.finish=Forms.Finish.LAMP
	g.taper(hand+Vector3.UP*.94,.32,.04,.87,9,Color("#d1ab64"))
	g.finish=Forms.Finish.METAL
	g.beam(base+Vector3(.83,4.82,0),base+Vector3(1.15,3.92,-.25),.48,metal)
	g.box(base+Vector3(.86,4.18,-.46),Vector3(.78,1.31,.27),Color("#68897d"))


static func build(g,site:Dictionary) -> void:
	var alloy:Color=[Color("#576269"),Color("#867058"),Color("#666c63"),Color("#717c83")][site.palette]
	match site.model:
		"lattice": lattice(g,alloy)
		"liberty": liberty(g,[Color("#78a693"),Color("#6b988a"),Color("#779b91"),Color("#65958b")][site.palette])
		"arch": _arch(g,alloy)
		"lantern": _lantern(g,alloy)
		"orbit": _orbit(g,alloy)
		"clock": _clock(g,alloy)

# The two legs taper and twist into one continuous triangular steel shell.
static func _arch(g,alloy:Color) -> void:
	var previous:=PackedVector3Array()
	for i in 57:
		var t:=PI*i/56.
		var p:=Vector3(-18.*cos(t),94.*sin(t),3.3*sin(2.*t))
		var tangent:=Vector3(18.*sin(t),94.*cos(t),6.6*cos(2.*t)).normalized()
		var side:=Vector3.BACK.cross(tangent).normalized()
		var depth:=tangent.cross(side)
		var span:=lerpf(2.9,1.34,sin(t))
		var ring:=PackedVector3Array([p+depth*span,p-depth*span*.82+side*span,p-depth*span*.82-side*span])
		if i>0:
			g.finish=Forms.Finish.METAL
			for j in 3:
				var k:=(j+1)%3
				g.quad(previous[j],previous[k],ring[k],ring[j],alloy.lightened(.21+j*.11),(ring[j]+ring[k])*.5-p)
			g.finish=Forms.Finish.LAMP
			g.beam(previous[0],ring[0],.12,LIMESTONE)
		previous=ring

static func _lantern(g,alloy:Color) -> void:
	g.taper(Vector3.ZERO,9.,8.,2.,24,LIMESTONE)
	for tier in 6:
		var y:=2.+tier*11.
		var r:=7.1-tier*.56
		g.finish=Forms.Finish.PLASTER
		g.taper(Vector3.UP*y,r,r-.56,11.,24,LIMESTONE if tier not in [2,4] else alloy)
		g.finish=Forms.Finish.PLAIN
		for face in 4:
			var v:=Vector3.BACK.rotated(Vector3.UP,face*PI*.5)
			g.beam(v*(r-.12)+Vector3.UP*(y+2.),v*(r-.35)+Vector3.UP*(y+5.),.85,CAP)
	g.finish=Forms.Finish.METAL
	g.taper(Vector3.UP*68.,4.1,6.4,2.5,24,alloy)
	g.taper(Vector3.UP*70.5,6.4,6.4,.65,24,STEEL)
	for i in 16:
		var a:=Vector3.BACK.rotated(Vector3.UP,TAU*i/16.)
		var b:=a.rotated(Vector3.UP,TAU/16.)
		g.beam(a*6.+Vector3.UP*71.,a*6.+Vector3.UP*72.7,.14,STEEL)
		g.beam(a*6.+Vector3.UP*72.7,b*6.+Vector3.UP*72.7,.14,STEEL)
		g.beam(a*4.6+Vector3.UP*71.,a*4.6+Vector3.UP*80.,.26,alloy)
	g.finish=Forms.Finish.LAMP
	for i in 7: g.taper(Vector3.UP*(72.7+i*.88),2.7,2.1,.78,24,Color("#dfbf87"))
	g.finish=Forms.Finish.METAL
	g.taper(Vector3.UP*80.,5.7,1.,5.4,20,alloy)
	g.taper(Vector3.UP*85.4,.64,.09,3.6,12,alloy)

static func _orbit(g,alloy:Color) -> void:
	g.taper(Vector3.ZERO,10.,8.,1.8,24,LIMESTONE)
	g.finish=Forms.Finish.METAL
	for i in 3:
		var foot:=Vector3.RIGHT.rotated(Vector3.UP,TAU*i/3.)
		var a:=foot*7.6+Vector3.UP*1.8
		for k in range(1,15):
			var t:=k/14.
			var b:=foot.rotated(Vector3.UP,t*.92)*(2.+5.6*pow(1.-t,2.))+Vector3.UP*(1.8+88.*t)
			g.beam(a,b,2.8-t*.95,alloy.lightened(.19))
			a=b
	g.taper(Vector3.UP*88.,3.8,10.2,4.5,32,alloy)
	g.finish=Forms.Finish.GLASS
	g.taper(Vector3.UP*92.5,10.2,10.2,3.4,32,Color("#56727d"))
	g.finish=Forms.Finish.METAL
	g.taper(Vector3.UP*95.9,10.7,4.3,3.1,32,alloy)
	var center:=Vector3.UP*103.
	for slope in [-.77,.77]:
		var previous:=center+Vector3.RIGHT*12.8
		for i in range(1,49):
			var a:=TAU*i/48.
			var point:=center+Vector3(12.8*cos(a),12.8*sin(a)*sin(slope),12.8*sin(a)*cos(slope))
			g.beam(previous,point,.60,alloy.lightened(.38))
			previous=point
	g.taper(Vector3.UP*98.,1.5,.56,21.,16,alloy)
	g.taper(Vector3.UP*119.,.56,.05,10.,12,STEEL)

static func _clock(g,alloy:Color) -> void:
	g.finish=Forms.Finish.PLASTER
	g.box(Vector3.UP*2.,Vector3(17.5,4.,17.5),LIMESTONE)
	g.box(Vector3.UP*36.,Vector3(13.,64.,13.),LIMESTONE.darkened(.16))
	for side in [-1.,1.]:
		for n in [-1.,0.,1.]:
			g.box(Vector3(n*4.8,37.,side*6.6),Vector3(.82,62.,.94),LIMESTONE)
			g.box(Vector3(side*6.6,37.,n*4.8),Vector3(.94,62.,.82),LIMESTONE)
	g.box(Vector3.UP*72.2,Vector3(15.,8.4,15.),LIMESTONE)
	for i in 4:
		var forward:=Vector3.BACK.rotated(Vector3.UP,i*PI*.5)
		var right:=forward.cross(Vector3.UP)
		var center:=forward*7.54+Vector3.UP*72.2
		for j in 36:
			var a:=TAU*j/36.
			var b:=TAU*(j+1)/36.
			var u:=(right*sin(a)+Vector3.UP*cos(a))*3.64
			var v:=(right*sin(b)+Vector3.UP*cos(b))*3.64
			g.finish=Forms.Finish.LAMP
			g.triangle(center,center+u,center+v,Color("#dfd9bf"),forward)
			g.finish=Forms.Finish.METAL
			g.beam(center+u,center+v,.21,alloy)
			if j%3==0: g.beam(center+u*.78+forward*.15,center+u*.93+forward*.15,.13,CAP)
	g.finish=Forms.Finish.METAL
	for tier in 3:
		var size:=13.8-tier*2.2
		g.box(Vector3.UP*(77.5+tier*2.1),Vector3(size,2.2,size),alloy)
	g.taper(Vector3.UP*82.8,6.8,1.2,16.,4,alloy,PI*.25)
	g.taper(Vector3.UP*98.8,.92,.05,7.6,12,alloy)
