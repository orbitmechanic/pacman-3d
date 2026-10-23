class_name LivesDisplay
extends Control

## Arcade-style remaining-lives pucks, drawn procedurally (no textures).
## Each puck is a Pac-Man silhouette with the mouth opening to the right.

const PUCK_RADIUS := 9.0
const PUCK_SPACING := 30.0
const MOUTH_HALF_ANGLE := 0.62

var lives := 3

func set_lives(count: int) -> void:
	lives = count
	queue_redraw()

func _draw() -> void:
	var color := Color(1.0, 0.85, 0.12)
	var center_y := size.y * 0.5
	for i in lives:
		var c := Vector2(12.0 + i * PUCK_SPACING, center_y)
		var pts := PackedVector2Array([c])
		var segments := 22
		for k in segments + 1:
			var a := lerpf(MOUTH_HALF_ANGLE, TAU - MOUTH_HALF_ANGLE, float(k) / segments)
			pts.append(c + Vector2(cos(a), sin(a)) * PUCK_RADIUS)
		draw_colored_polygon(pts, color)
