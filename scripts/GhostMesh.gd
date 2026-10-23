class_name GhostMesh
extends RefCounted

## Procedural ghost body: a hemisphere dome, straight sides and the classic
## scalloped skirt. Built as one ArrayMesh so a ghost is a single draw call and
## the whole cast shares zero binary assets.
##
## Local frame: origin at the equator centre, +X is "front" (eyes look this
## way), the dome tops out at +radius and the scalloped skirt hangs about
## radius + 0.15 below it.

const RIM_WAVES := 4

static func build(radius := 0.42, segments := 28, dome_rings := 8) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	# Ring definitions: radius, y, and whether normals are spherical (dome) or
	# horizontal (sides/skirt).
	var rings: Array[Dictionary] = []
	for i in dome_rings + 1:
		var theta := (PI / 2.0) * float(i) / float(dome_rings)
		rings.append({
			"r": radius * sin(theta),
			"y": radius * cos(theta),
			"dome": theta,
		})
	rings.append({"r": radius, "y": -0.22, "dome": -1.0})
	rings.append({"r": radius, "y": -0.44, "dome": -1.0})
	rings.append({"r": radius, "y": NAN, "dome": -1.0})

	var cols := segments + 1
	for ring in rings:
		for j in cols:
			var phi := TAU * float(j) / float(segments)
			var y: float = ring["y"]
			if is_nan(y):
				# Scalloped hem: couples to phi so the zigzag closes seamlessly.
				y = -0.56 + 0.09 * cos(RIM_WAVES * phi)
			var r: float = ring["r"]
			verts.append(Vector3(r * cos(phi), y, r * sin(phi)))
			var theta: float = ring["dome"]
			if theta >= 0.0:
				normals.append(Vector3(
					sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi)
				))
			else:
				normals.append(Vector3(cos(phi), 0.0, sin(phi)))

	var indices := PackedInt32Array()
	for i in rings.size() - 1:
		for j in segments:
			var a := i * cols + j
			var b := a + 1
			var c := a + cols
			var d := c + 1
			indices.append_array([a, c, b, b, c, d])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
