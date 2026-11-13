class_name EffectGlyph
extends RefCounted

## Geometry stays legible in monochrome and never depends on an emoji font.
static func paint(canvas: CanvasItem, kind: String, center: Vector2, radius: float, ink: Color) -> void:
	var shape: Array = []
	match kind:
		"relax":
			shape = [[-.78,-.64],[0,-.95],[.78,-.64],[.64,.35],[0,.95],[-.64,.35],[-.78,-.64]]
			line(canvas, center, radius, [[0,-.86],[0,.68]], Color(ink, .5))
		"work", "next":
			shape = [[-.65,-.85],[.38,-.85],[.72,-.5],[.72,.85],[-.65,.85],[-.65,-.85]]
			line(canvas, center, radius, [[-.4,.1],[-.1,.4],[.47,-.25]], ink)
			if kind == "next":
				line(canvas, center, radius, [[.3,-.9],[.9,-.9],[.9,-.35]], ink)
		"draw", "discard", "exhaust", "retrieve", "search":
			shape = [[-.8,.5],[-.8,-.82],[.33,-.82],[.33,.5],[-.8,.5]]
			line(canvas, center, radius, [[-.5,.76],[.65,.76],[.65,-.5]], ink)
			if kind == "draw":
				line(canvas, center, radius, [[-.1,.1],[-.1,-.55],[-.4,-.2],[-.1,-.55],[.22,-.2]], ink)
			elif kind == "exhaust":
				line(canvas, center, radius, [[-.5,-.4],[.1,.2],[-.5,.2],[.1,-.4]], ink)
			else:
				line(canvas, center, radius, [[-.5,-.2],[.1,.4],[.1,-.1]], ink)
		"focus":
			shape = [[-.65,.8],[-.35,-.3],[.65,-.9],[.5,.35],[-.65,.8]]
			line(canvas, center, radius, [[-.55,.66],[.25,-.15]], ink)
		"heart":
			shape = [[0,.8],[-.82,-.05],[-.82,-.5],[-.42,-.8],[0,-.45],[.42,-.8],[.82,-.5],[.82,-.05],[0,.8]]
		"book", "bookmark":
			shape = [[0,-.6],[-.85,-.85],[-.85,.65],[0,.9],[.85,.65],[.85,-.85],[0,-.6],[0,.9]]
		"link", "partner":
			canvas.draw_arc(center + Vector2(-radius*.3,0), radius*.6, -.7, 4.5, 22, ink, 1.8, true)
			canvas.draw_arc(center + Vector2(radius*.3,0), radius*.6, 2.4, 7.6, 22, ink, 1.8, true)
			if kind == "partner":
				canvas.draw_circle(center + Vector2(-radius*.45,-radius*.62),radius*.24,ink,false,1.6,true)
				canvas.draw_circle(center + Vector2(radius*.45,-radius*.62),radius*.24,ink,false,1.6,true)
		"clock":
			canvas.draw_circle(center, radius*.82, ink, false, 1.8, true)
			shape = [[0,-.58],[0,.04],[.46,.28]]
		"scene":
			shape = [[-.8,-.8],[.8,-.8],[.8,.8],[-.8,.8],[-.8,-.8],[0,-.8],[0,.8]]
			line(canvas, center, radius, [[-.8,0],[.8,0]], ink)
		"break", "erosion":
			shape = [[-.8,-.7],[-.1,-.7],[-.32,-.05],[.3,-.12],[.06,.78],[.8,.78]]
			line(canvas, center, radius, [[-.8,.7],[-.5,.2],[.7,-.8]], Color(ink,.5))
		"citation":
			for x in [-.45,.4]:
				canvas.draw_circle(center+Vector2(x*radius,-.2*radius), radius*.25,ink,true,-1,true)
				line(canvas,center,radius,[[x+.2,-.1],[x,.55],[x-.2,.55]],ink)
		"induced", "status":
			shape = [[-.8,-.7],[-.8,.7],[-.4,.7]]
			line(canvas,center,radius,[[.8,-.7],[.8,.7],[.4,.7]],ink)
			canvas.draw_circle(center,radius*.28,ink,true,-1,true)
		"stamp":
			shape = [[-.8,.25],[.8,.25],[.8,.75],[-.8,.75],[-.8,.25],[-.3,.25],[-.3,-.6],[.3,-.6],[.3,.25]]
		_:
			canvas.draw_circle(center,radius*.6,ink,false,1.8,true)
	if not shape.is_empty():
		line(canvas,center,radius,shape,ink)

static func line(canvas: CanvasItem, center: Vector2, radius: float, values: Array, ink: Color) -> void:
	var points := PackedVector2Array()
	for pair in values:
		points.append(center + Vector2(pair[0],pair[1]) * radius)
	canvas.draw_polyline(points, ink, maxf(1.3, radius*.13), true)
