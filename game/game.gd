extends Node3D

@onready
var light : DirectionalLight3D = $DirectionalLight3D

@onready
var multiMeshInstance = $MultiMeshInstance3D

@onready
var debugMultiMeshInstance = $DebugMultiMeshInstance3D

@onready
var camera : FreeLookCamera = $Camera

@onready
var mediums : Array = [
	$Medium01,
	$Medium02,
	$Medium03,
	$Medium04,
	$Medium05, 
	$Medium06, 
	$Medium07
]


# Debug options for visualizing samples
const DEBUG_SHOW_SAMPLES: bool = true
const DEBUG_MAX_SAMPLES: int = 8


# MeshSampler is loaded on-demand below to avoid static preload issues in this environment.

# medium properties


func fill_multimesh_from_mediums(mm_instance: MultiMeshInstance3D, samples = null, samples_per_unit: float = 1.0, total_samples: int = 0) -> void:
	# 填充 MultiMeshInstance：如果传入 samples（位置/法线数组），优先使用它；否则从 mediums 采样
	if not mm_instance:
		return

	var all_samples: Array = []
	if samples != null:
		all_samples = samples.duplicate()
	else:
		for m in mediums:
			if m and m is MeshInstance3D:
				var samp = sample_mesh_surface(m, samples_per_unit, total_samples)
				# 合并样本（实例缩放由 instance_scale 参数控制，不跟随源节点）
				for s in samp:
					all_samples.append({"position": s["position"], "normal": s["normal"], "source": m})

	# 设置 MultiMesh 实例数量
	var mm = mm_instance.multimesh
	if mm == null:
		return

	# Delegate to helper that fills multimesh from sample list
	update_multimesh_from_samples(mm, all_samples)

	# 如果需要其他实例化属性（颜色、尺度等），可以在这里设置


# Mesh sampling functions were migrated to res://utils/mesh_sampler.gd as MeshSampler
# Use MeshSampler.sample_mesh_surface(mesh_instance, samples_per_unit, total_samples, seed)

func sample_mesh_surface(mesh_instance: MeshInstance3D, samples_per_unit: float = 1.0, total_samples: int = 0) -> Array:
	# 兼容 wrapper：调用迁移到 MeshSampler
	return MeshSampler.sample_mesh_surface(mesh_instance, samples_per_unit, total_samples)


### Helpers for MultiMesh updates
func _build_basis_from_normal(normal: Vector3, inst_scale_vec := Vector3.ONE) -> Basis:
	var up = Vector3.UP
	if abs(up.dot(normal)) > 0.999:
		up = Vector3.FORWARD
	var z = normal.normalized()
	var x = up.cross(z).normalized()
	var y = z.cross(x).normalized()
	var b = Basis()
	b.x = x * inst_scale_vec.x
	b.y = y * inst_scale_vec.y
	b.z = z * inst_scale_vec.z
	return b

func _encode_instance_normal_from_basis(b: Basis, n_world: Vector3) -> Color:
	var n_local = (b.transposed() * n_world).normalized()
	return Color(n_local.x * 0.5 + 0.5, n_local.y * 0.5 + 0.5, n_local.z * 0.5 + 0.5, 1.0)


func update_multimesh_from_samples(mm: MultiMesh, samples: Array) -> void:
	if mm == null:
		return
	mm.instance_count = samples.size()
	for i in range(samples.size()):
		var entry = samples[i]
		var pos: Vector3 = entry["position"]
		var normal: Vector3 = entry["normal"].normalized()
		var b = _build_basis_from_normal(normal)
		var t = Transform3D(b, pos)
		mm.set_instance_transform(i, t)
		# color
		var rng = RandomNumberGenerator.new()
		rng.randomize()
		var h = rng.randf_range(0.48, 0.52)
		var s = rng.randf_range(0.0, 0.0)
		var v = 1.0
		var col = Color.from_hsv(h, s, v)
		if mm.has_method("set_instance_color"):
			mm.set_instance_color(i, col)
		# custom normal (instance-local)
		var enc = _encode_instance_normal_from_basis(b, normal)
		mm.set_instance_custom_data(i, enc)

func update_multimesh_from_creatures(mm: MultiMesh, creatures_list: Array) -> void:
	if mm == null:
		return
	mm.instance_count = creatures_list.size()
	for i in range(creatures_list.size()):
		var c = creatures_list[i]
		var pos: Vector3 = c.position
		# 基于生物当前大小（以 1m 为基准）计算实例缩放
		var size_scale: float = max(0.001, float(c.current_size_m))
		var inst_scale_vec: Vector3 = Vector3.ONE * size_scale
		# Use the surface normal at the creature's attached point if available.
		var n_world: Vector3 = Vector3.UP
		if c.now_attached_id >= 0 and c.now_attached_id < Creature.world_surface_normals.size():
			n_world = Creature.world_surface_normals[c.now_attached_id]
		# 构建带缩放的 basis，使实例朝向与法线一致并按 size_scale 缩放
		var b = _build_basis_from_normal(n_world, inst_scale_vec)
		var t = Transform3D(b, pos)
		mm.set_instance_transform(i, t)
		# 更新静态大小数组，供其它系统使用
		if c.index >= 0 and c.index < Creature.creatures_sizes.size():
			Creature.creatures_sizes[c.index] = size_scale * 0.05;
		var enc = _encode_instance_normal_from_basis(b, n_world)
		mm.set_instance_custom_data(i, enc)
		var col = Creature.creatures_colors[i]
		
		#print(Creature.creatures_colors)
		
		if mm.has_method("set_instance_color"):
			mm.set_instance_color(i, col)


### Debug: update a MultiMesh from world surface points and color by attachment state
func update_debug_multimesh_from_surface_points(mm: MultiMesh) -> void:
	if mm == null:
		return
	# ensure the MultiMesh has a mesh assigned on the MultiMeshInstance
	# the mesh defines the visible geometry for each instance; if missing nothing will be drawn
	if debugMultiMeshInstance == null or debugMultiMeshInstance.multimesh == null:
		print("[DEBUG] debugMultiMeshInstance has no mesh assigned - attach a small sphere/circle mesh to see surface points")
		return
	var points = Creature.world_surface_points
	var normals = Creature.world_surface_normals
	var attached = Creature.world_surface_point_is_attached
	mm.instance_count = points.size()
	for i in range(points.size()):
		var pos: Vector3 = points[i]
		var n_world: Vector3 = Vector3.UP
		if i < normals.size():
			n_world = normals[i]
		var inst_scale_vec = Vector3.ONE * max(0.0001, debug_point_scale)
		var b = _build_basis_from_normal(n_world, inst_scale_vec)
		var t = Transform3D(b, pos)
		mm.set_instance_transform(i, t)
		# color by attached state
		var col: Color = Color(0.6, 0.6, 0.6, 1.0) # free = grey
		if i < attached.size() and attached[i]:
			col = Color(1.0, 0.0, 0.0, 1.0) # occupied = red
		if mm.has_method("set_instance_color"):
			mm.set_instance_color(i, col)
		# custom normal
		var enc = _encode_instance_normal_from_basis(b, n_world)
		mm.set_instance_custom_data(i, enc)

# creature properties




func _ready() -> void:
	# 示例：启动时填充 multimesh（每个实例使用统一缩放 0.1）
	#fill_multimesh_from_mediums(1.0, 0, 1.0)

	## 创建一个示例 Creature 并加入 creatures 列表（用于运行时测试）

	
	
	var all_samples := []
	for m in mediums:
		if m and m is MeshInstance3D:
			var samples = sample_mesh_surface(m, 0.2, 0)
			# 合并样本（实例缩放由 instance_scale 参数控制，不跟随源节点）
			for s in samples:
				# store source mesh so we can convert normals back to mesh-local space later
				all_samples.append({"position": s["position"], "normal": s["normal"], "source": m})

	fill_multimesh_from_mediums(debugMultiMeshInstance, all_samples, 0.2, 0)

	for s in all_samples:
		Creature.world_surface_points.append(s["position"])
		Creature.world_surface_normals.append(s["normal"])
		Creature.world_surface_point_is_attached.append(false)

	# Build spatial indexes initially
	Creature.rebuild_surface_octree()
	Creature.rebuild_creatures_octree()

	# Ensure debug MultiMeshInstance has a mesh so debug points are visible
	if debugMultiMeshInstance and debugMultiMeshInstance.multimesh == null:
		var sphere = SphereMesh.new()
		# Make the sphere unit radius; instance scale will control final size
		sphere.radius = 1.0
		sphere.height = 0.5
		debugMultiMeshInstance.mesh = sphere

	# var newCreature = Creature.new(GenomeUtils.random_plant_genome(), Transform3D.IDENTITY)
	# newCreature.attach_to_surface_point(0)

	# Instance the UI that shows closest creature and count
	var ui_scene = preload("res://ui/closest_creature_ui.tscn")
	var ui_inst = ui_scene.instantiate()
	add_child(ui_inst)
	self.closest_ui = ui_inst
	
	
	Creature.world_light_direction = -light.global_basis.z
	
	return

var closest_ui = null

var speed_radio : int = 1

# debug visualization scale for surface points (meters)
# default increased so debug points are visible without Inspector tweaks
@export var debug_point_scale: float = 0.1

# How often (seconds) to rebuild the creatures octree when creatures move frequently
@export var creatures_octree_rebuild_interval: float = 0.5
var _creatures_octree_acc: float = 0.0

# How often (seconds) to validate and fix attachment states
var _attachment_validation_timer: float = 0.0

func _input(event: InputEvent) -> void:
	if(event.is_action("speed_up")):
		speed_radio *= 2
	if(event.is_action("speed_down")):
		speed_radio /= 2
		if speed_radio < 1:
			speed_radio = 1

	# 在范围内的所有空闲附着点放置新生物
	if(event.is_action("put_new_creatures")):
		var target_range = camera.BallRadius
		var pos = camera.BallRangeMesh.global_transform.origin
		for i in range(Creature.world_surface_points.size()):
			var p = Creature.world_surface_points[i]
			if Creature.world_surface_point_is_attached[i]:
				continue
			if p.distance_to(pos) <= target_range:
				# pre-mark the point as attached to avoid double-placement races
				if i < Creature.world_surface_point_is_attached.size():
					if Creature.world_surface_point_is_attached[i]:
						continue
					Creature.world_surface_point_is_attached[i] = true
				var c = Creature.new(GenomeUtils.random_plant_genome(), Transform3D.IDENTITY)
				c.attach_to_surface_point(i)

		
	
	# 按 'c' 键计数 camera.BallRangeMesh 范围内的生物并打印
	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == Key.KEY_C:
			var target_range = camera.BallRadius
			var pos = camera.BallRangeMesh.global_transform.origin
			var cnt = 0
			for cc in Creature.creatures:
				if cc and cc.position.distance_to(pos) <= target_range:
					cnt += 1

			print("[INPUT] Creatures in ball range:", cnt)


func _physics_process(delta: float) -> void:
	# First update creature simulation/state
	for c in Creature.creatures:
		c.update(delta * speed_radio)

	# Remove dead creatures after update so subsequent rendering/instancing matches live set
	Creature.cleanup_dead()
	
	# Periodically validate and fix attachment states (every 5 seconds)
	_attachment_validation_timer += delta
	if _attachment_validation_timer >= 5.0:
		_attachment_validation_timer = 0.0
		Creature.cleanup_invalid_reproduction_states()
		Creature.validate_and_fix_attachment_state()

	# Then reflect creatures into the MultiMesh each frame
	var mm = null
	if multiMeshInstance:
		mm = multiMeshInstance.multimesh
	if mm == null:
		return

	# update debug multimesh (shows attachment occupancy)
	if debugMultiMeshInstance and debugMultiMeshInstance.multimesh:
		update_debug_multimesh_from_surface_points(debugMultiMeshInstance.multimesh)

	# Ensure instance count matches creatures
	update_multimesh_from_creatures(mm, Creature.creatures)

	if DEBUG_SHOW_SAMPLES:
		print("[PHYSICS] creatures_count=", Creature.creatures.size(), " multimesh_count=", mm.instance_count)

	# Trigger periodic rebuild of the creatures octree using accumulator
	_creatures_octree_acc += delta
	if _creatures_octree_acc >= creatures_octree_rebuild_interval:
		_creatures_octree_acc = 0.0
		Creature.rebuild_creatures_octree()
	pass
