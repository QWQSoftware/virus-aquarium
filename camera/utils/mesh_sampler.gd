class_name MeshSampler

# Mesh surface sampling utilities
# Usage:
#   var samples = MeshSampler.sample_mesh_surface(mesh_instance, samples_per_unit, total_samples, seed)

static func sample_mesh_surface(mesh_instance: MeshInstance3D, samples_per_unit: float = 1.0, total_samples: int = 0, rng_seed: int = -1) -> Array:
	# 参数说明：samples_per_unit = 每单位面积的采样数；total_samples > 0 则覆盖 samples_per_unit
	var mesh = mesh_instance.mesh
	if mesh == null:
		return []

	var triangles = _extract_triangles_with_normals(mesh)
	if triangles.is_empty():
		return []

	# 计算每个三角形面积与总体面积（使用世界空间坐标，考虑 MeshInstance3D 的 transform/scale）
	var areas := []
	var total_area := 0.0
	for tri in triangles:
		var a_local: Vector3 = tri.a
		var b_local: Vector3 = tri.b
		var c_local: Vector3 = tri.c
		var a_w: Vector3 = mesh_instance.to_global(a_local)
		var b_w: Vector3 = mesh_instance.to_global(b_local)
		var c_w: Vector3 = mesh_instance.to_global(c_local)
		var area = ((b_w - a_w).cross(c_w - a_w)).length() * 0.5
		areas.append(area)
		total_area += area

	if total_area <= 0.0:
		return []

	# 决定需要采样的总点数
	var N := 0
	if total_samples > 0:
		N = total_samples
	else:
		N = int(max(1, round(total_area * samples_per_unit)))

	# 构建面积累计数组，便于按面积比例采样三角形
	var cum_areas := []
	var s := 0.0
	for area in areas:
		s += area
		cum_areas.append(s)

	var rng := RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()

	# 把三角形转换到世界空间（顶点与顶点法线），后续采样全部在世界空间进行
	var world_tris := []
	for tri in triangles:
		var a_w: Vector3 = mesh_instance.to_global(tri.a)
		var b_w: Vector3 = mesh_instance.to_global(tri.b)
		var c_w: Vector3 = mesh_instance.to_global(tri.c)
		var na_w = null
		var nb_w = null
		var nc_w = null
		if tri.has("na") and tri.na != null:
			var normal_mat = mesh_instance.global_transform.basis.inverse().transposed()
			na_w = (normal_mat * tri.na).normalized()
		if tri.has("nb") and tri.nb != null:
			var normal_mat = mesh_instance.global_transform.basis.inverse().transposed()
			nb_w = (normal_mat * tri.nb).normalized()
		if tri.has("nc") and tri.nc != null:
			var normal_mat = mesh_instance.global_transform.basis.inverse().transposed()
			nc_w = (normal_mat * tri.nc).normalized()
		world_tris.append({"a": a_w, "b": b_w, "c": c_w, "na": na_w, "nb": nb_w, "nc": nc_w})

	var results := []
	for i in range(N):
		var r = rng.randf() * total_area
		# 二分查找或线性查找所选三角形（这里用简单线性查找，若三角形很多可改为二分）
		var idx := 0
		while idx < cum_areas.size() and r > cum_areas[idx]:
			idx += 1
		if idx >= world_tris.size():
			idx = world_tris.size() - 1

		var tri_w = world_tris[idx]
		var sampled = _sample_point_and_normal_in_triangle(tri_w, rng)
		var sample_point_world: Vector3 = sampled[0]
		var sample_normal_world: Vector3 = sampled[1]

		results.append({"position": sample_point_world, "normal": sample_normal_world})

	return results


static func _extract_triangles_with_normals(mesh: Mesh) -> Array:
	var tris := []
	if not mesh or not mesh.has_method("get_surface_count"):
		return tris

	var surface_count := mesh.get_surface_count()
	for si in range(surface_count):
		var arrays = mesh.surface_get_arrays(si)
		var verts = arrays[Mesh.ARRAY_VERTEX]
		if not verts or verts.size() == 0:
			continue

		var normals = null
		if Mesh.ARRAY_NORMAL < arrays.size():
			normals = arrays[Mesh.ARRAY_NORMAL]

		var indices = null
		if Mesh.ARRAY_INDEX < arrays.size():
			indices = arrays[Mesh.ARRAY_INDEX]

		if indices and indices.size() > 0:
			for i in range(0, indices.size(), 3):
				if i + 2 >= indices.size():
					break
				var ia = int(indices[i])
				var ib = int(indices[i + 1])
				var ic = int(indices[i + 2])
				var A = verts[ia]
				var B = verts[ib]
				var C = verts[ic]
				var NA = null
				var NB = null
				var NC = null
				if normals and normals.size() > 0:
					NA = normals[ia]
					NB = normals[ib]
					NC = normals[ic]
				tris.append({"a": A, "b": B, "c": C, "na": NA, "nb": NB, "nc": NC})
		else:
			for i in range(0, verts.size(), 3):
				if i + 2 >= verts.size():
					break
				var A2 = verts[i]
				var B2 = verts[i + 1]
				var C2 = verts[i + 2]
				var NA2 = null
				var NB2 = null
				var NC2 = null
				if normals and normals.size() >= i + 3:
					NA2 = normals[i]
					NB2 = normals[i + 1]
					NC2 = normals[i + 2]
				tris.append({"a": A2, "b": B2, "c": C2, "na": NA2, "nb": NB2, "nc": NC2})

	return tris


static func _sample_point_and_normal_in_triangle(tri: Dictionary, rng: RandomNumberGenerator) -> Array:
	var A: Vector3 = tri.a
	var B: Vector3 = tri.b
	var C: Vector3 = tri.c

	var r1 = rng.randf()
	var r2 = rng.randf()
	var sqrt_r1 = sqrt(r1)
	var u = 1.0 - sqrt_r1
	var v = sqrt_r1 * (1.0 - r2)
	var w = sqrt_r1 * r2

	var p = A * u + B * v + C * w

	var n: Vector3
	if tri.has("na") and tri.na != null and tri.nb != null and tri.nc != null:
		n = tri.na * u + tri.nb * v + tri.nc * w
		if n.length() == 0:
			n = ((B - A).cross(C - A)).normalized()
		else:
			n = n.normalized()
	else:
		n = ((B - A).cross(C - A)).normalized()

	return [p, n]
