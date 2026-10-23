class_name PacMesh
extends RefCounted

## UV sphere with a wedge removed for the mouth. The gap is centered on +X
## (local), so the node can simply yaw to face its travel direction.

static func build(radius: float, gap_degrees: float, segments := 32, rings := 16) -> ArrayMesh:
	var gap := deg_to_rad(clampf(gap_degrees, 0.0, 170.0))
	var phi_start := gap / 2.0
	var phi_end := TAU - gap / 2.0
	var cols := segments + 1

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	for i in rings + 1:
		var theta := PI * float(i) / rings
		for j in cols:
			var phi := phi_start + (phi_end - phi_start) * float(j) / segments
			var n := Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
			verts.append(n * radius)
			normals.append(n)

	for i in rings:
		for j in segments:
			var a := i * cols + j
			var b := a + cols
			indices.append(a)
			indices.append(b)
			indices.append(a + 1)
			indices.append(a + 1)
			indices.append(b)
			indices.append(b + 1)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
