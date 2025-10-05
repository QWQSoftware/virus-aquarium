extends Resource

class_name Octree

# Lightweight octree for static point sets with radius query support.
# Not thread-safe. Designed to accelerate nearby-point queries for world_surface_points.

const MAX_CHILDREN := 8

class OctreeNode:
    var aabb_min: Vector3
    var aabb_max: Vector3
    var center: Vector3
    var points: Array = [] # stores point indices
    var children: Array = [] # length 8 or empty
    var depth: int = 0

    func _init(_min: Vector3, _max: Vector3, _depth: int) -> void:
        aabb_min = _min
        aabb_max = _max
        center = (_min + _max) * 0.5
        points = []
        children = []
        depth = _depth

func _init() -> void:
    root = null
    points_ref = null
    max_points = 8
    max_depth = 8

var root
var points_ref
var max_points
var max_depth

func build_from_points(points_array: Array, max_points_per_node: int = 8, max_depth_in: int = 8) -> void:
    # points_array: Array of Vector3
    points_ref = points_array
    max_points = max(1, int(max_points_per_node))
    max_depth = max(1, int(max_depth_in))
    var count = points_array.size()
    if count == 0:
        root = null
        return
    # compute bounds
    var minv = points_array[0]
    var maxv = points_array[0]
    for i in range(1, count):
        var p = points_array[i]
        minv.x = min(minv.x, p.x)
        minv.y = min(minv.y, p.y)
        minv.z = min(minv.z, p.z)
        maxv.x = max(maxv.x, p.x)
        maxv.y = max(maxv.y, p.y)
        maxv.z = max(maxv.z, p.z)

    # Expand bounds a little to avoid zero-size boxes
    var pad = 0.0001
    minv -= Vector3(pad, pad, pad)
    maxv += Vector3(pad, pad, pad)

    root = OctreeNode.new(minv, maxv, 0)
    # insert all indices
    for i in range(count):
        _insert_index(root, i)

func _subdivide(node: OctreeNode) -> void:
    if node.children.size() != 0:
        return
    var mn = node.aabb_min
    var mx = node.aabb_max
    var c = node.center
    # create 8 children boxes
    for xi in range(2):
        for yi in range(2):
            for zi in range(2):
                var child_min = Vector3( (mn.x if xi == 0 else c.x),
                                         (mn.y if yi == 0 else c.y),
                                         (mn.z if zi == 0 else c.z) )
                var child_max = Vector3( (c.x if xi == 0 else mx.x),
                                         (c.y if yi == 0 else mx.y),
                                         (c.z if zi == 0 else mx.z) )
                var child = OctreeNode.new(child_min, child_max, node.depth + 1)
                node.children.append(child)

func _insert_index(node: OctreeNode, idx: int) -> void:
    # if node has children, descend
    if node.children.size() != 0:
        var p = points_ref[idx]
        for child in node.children:
            if _point_in_aabb(p, child.aabb_min, child.aabb_max):
                _insert_index(child, idx)
                return
        # fallback
        node.points.append(idx)
        return

    # add to this node
    node.points.append(idx)
    # check split
    if node.points.size() > max_points and node.depth < max_depth:
        _subdivide(node)
        # redistribute
        var old = node.points.duplicate()
        node.points.clear()
        for id_old in old:
            var p2 = points_ref[id_old]
            var placed = false
            for child in node.children:
                if _point_in_aabb(p2, child.aabb_min, child.aabb_max):
                    _insert_index(child, id_old)
                    placed = true
                    break
            if not placed:
                node.points.append(id_old)

func _point_in_aabb(p: Vector3, mn: Vector3, mx: Vector3) -> bool:
    return p.x >= mn.x and p.x <= mx.x and p.y >= mn.y and p.y <= mx.y and p.z >= mn.z and p.z <= mx.z

func _aabb_sphere_intersect(mn: Vector3, mx: Vector3, center: Vector3, radius: float) -> bool:
    # clamp center to AABB and compute distance squared
    var cx = clamp(center.x, mn.x, mx.x)
    var cy = clamp(center.y, mn.y, mx.y)
    var cz = clamp(center.z, mn.z, mx.z)
    var dx = center.x - cx
    var dy = center.y - cy
    var dz = center.z - cz
    return (dx*dx + dy*dy + dz*dz) <= (radius * radius)

func query_radius(center: Vector3, radius: float, out_limit: int = 0) -> Array:
    var res: Array = []
    if root == null:
        return res
    _query_node(root, center, radius, res, out_limit)
    return res

func _query_node(node: OctreeNode, center: Vector3, radius: float, res: Array, out_limit: int) -> void:
    if not _aabb_sphere_intersect(node.aabb_min, node.aabb_max, center, radius):
        return
    # check points in node
    for idx in node.points:
        var p = points_ref[idx]
        if p.distance_to(center) <= radius:
            res.append(idx)
            if out_limit > 0 and res.size() >= out_limit:
                return
    # check children
    for child in node.children:
        _query_node(child, center, radius, res, out_limit)
        if out_limit > 0 and res.size() >= out_limit:
            return
