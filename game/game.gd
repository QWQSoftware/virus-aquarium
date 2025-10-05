extends Node3D

@onready
var mission : MissionSystem = $Mission

@onready
var cloest_ui : Label = $MarginContainer2/VBoxContainer/ClosestCreatureUi

@onready
var sound_effects : SoundEffects = $SoundEffects

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
$Node3D/Medium01, $Node3D/Medium02, $Node3D/Medium03, $Node3D/Medium04, $Node3D/Medium05, $Node3D/Medium06, $Node3D/Medium07
]

@onready
var speed_label : Label = $SpeedLabel/HBoxContainer/SpeedLabel

@onready
var speed_label_control : Control = $SpeedLabel

@onready
var cloest_creature_ui : CloestCreatureUI = $MarginContainer2/VBoxContainer/ClosestCreatureUi

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
		
		# 首先检查是否被用户屏蔽
		if i < Creature.world_surface_point_is_blocked.size() and Creature.world_surface_point_is_blocked[i]:
			col = Color(0.0, 0.0, 1.0, 1.0) # blocked by user = blue
		elif i < attached.size() and attached[i]:
			# 如果不是被用户屏蔽，但 attached 为 true，则应该是被生物占用
			col = Color(1.0, 0.0, 0.0, 1.0) # occupied by creature = red
		if mm.has_method("set_instance_color"):
			mm.set_instance_color(i, col)
		# custom normal
		var enc = _encode_instance_normal_from_basis(b, n_world)
		mm.set_instance_custom_data(i, enc)

# creature properties




func _ready() -> void:
	# 示例：启动时填充 multimesh（每个实例使用统一缩放 0.1）
	#fill_multimesh_from_mediums(1.0, 0, 1.0)
	Creature.sound_effects = sound_effects
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
		Creature.world_surface_point_is_blocked.append(false)

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
	self.closest_ui = cloest_ui
	
	
	Creature.world_light_direction = -light.global_basis.z
	
	# 初始化速度标签
	if speed_label:
		speed_label.text = "SPD: X" + String.num(speed_radio)
	
	# 初始化任务系统
	if mission:
		print("[GAME] Mission system initialized")
		# 显示当前任务信息
		call_deferred("_show_initial_mission_info")
	
	return

var closest_ui = null

# Copied genome for paste functionality
var copied_genome: Array = []
var copied_genome_source_index: int = -1

# Game speed and pause control
var speed_radio : float = 1.0
var is_paused : bool = false
var origin_speed_radio : float = 0.0
var radio_text : String = "SPD: X1"

# debug visualization scale for surface points (meters)
# default increased so debug points are visible without Inspector tweaks
@export var debug_point_scale: float = 0.1

# How often (seconds) to rebuild the creatures octree when creatures move frequently
@export var creatures_octree_rebuild_interval: float = 0.5
var _creatures_octree_acc: float = 0.0

# How often (seconds) to validate and fix attachment states
var _attachment_validation_timer: float = 0.0

# Mission system integration variables
var max_creature_size_ever: float = 0.0
# 状态报告已移至Mission界面直接显示，无需定时器

func _input(event: InputEvent) -> void:
	# 处理暂停切换
	if(event.is_action_pressed("pause")):
		# 触发暂停操作的回调
		if speed_label_control:
			speed_label_control.on_pause()
		
		is_paused = !is_paused
		if(is_paused):
			origin_speed_radio = speed_radio
			speed_radio = 0
			if speed_label:
				speed_label.text = "||"
			print("[INPUT] Game paused (original speed: X%s)" % String.num(origin_speed_radio))
		else:
			speed_radio = origin_speed_radio
			radio_text = String.num(speed_radio)
			if speed_label:
				speed_label.text = "SPD: X" + radio_text
			print("[INPUT] Game unpaused (speed: X%s)" % radio_text)
		return  # 暂停切换后直接返回，避免其他逻辑干扰

	# 处理速度调整（在暂停状态下按加速/减速也会取消暂停）
	var speed_changed = false
	
	if(event.is_action_pressed("speed_up")):
		# 触发加速操作的回调
		if speed_label_control:
			speed_label_control.on_speed_up()
		
		# 如果当前是暂停状态，先取消暂停
		if is_paused:
			is_paused = false
			speed_radio = origin_speed_radio
			print("[INPUT] Game unpaused by speed_up (restored speed: X%s)" % String.num(speed_radio))
		
		speed_radio *= 2
		if speed_radio > 64:
			speed_radio = 64
		speed_changed = true
		
	if(event.is_action_pressed("speed_down")):
		# 触发减速操作的回调
		if speed_label_control:
			speed_label_control.on_speed_down()
		
		# 如果当前是暂停状态，先取消暂停
		if is_paused:
			is_paused = false
			speed_radio = origin_speed_radio
			print("[INPUT] Game unpaused by speed_down (restored speed: X%s)" % String.num(speed_radio))
		
		speed_radio /= 2
		if speed_radio < 0.25:
			speed_radio = 0.25
		speed_changed = true
	
	# 只有在速度发生变化时才更新标签
	if speed_changed:
		radio_text = String.num(speed_radio)
		if speed_label:
			speed_label.text = "SPD: X" + radio_text

	# 在范围内的所有空闲附着点放置新生物
	if(event.is_action_pressed("put_new_creatures")):
		var target_range = camera.BallRadius
		var pos = camera.BallRangeMesh.global_transform.origin
		var placed_count = 0
		
		for i in range(Creature.world_surface_points.size()):
			var p = Creature.world_surface_points[i]
			
			# 检查附着点是否已被占用
			if i >= Creature.world_surface_point_is_attached.size() or Creature.world_surface_point_is_attached[i]:
				continue
				
			# 检查是否在目标范围内
			if p.distance_to(pos) <= target_range:
				# 预先标记附着点为已占用，避免重复放置
				Creature.world_surface_point_is_attached[i] = true
				
				# 创建新生物并附着到该点
				var c = Creature.new(GenomeUtils.random_plant_genome(), Transform3D.IDENTITY)
				c.attach_to_surface_point(i)
				placed_count += 1
		
		if placed_count > 0:
			print("[INPUT] Placed %d new creatures in ball range" % placed_count)
			# 通知任务系统有新生物被放置
			_notify_mission_creature_placed(placed_count)

		
	if(event.is_action_pressed("copy")):
		var target_creature = cloest_creature_ui._current_target_creature
		if target_creature != null:
			copied_genome = GenomeUtils.get_creature_genome(target_creature)
			copied_genome_source_index = target_creature.index
			print("[INPUT] Copied genome from creature index: %d" % target_creature.index)
		else:
			print("[INPUT] No target creature selected for copying")
		return
	
	# 粘贴功能：使用复制的基因组在球体范围内放置生物
	if(event.is_action_pressed("paste")):
		if copied_genome.size() == 0:
			print("[INPUT] No genome copied. Use copy action first.")
			return
			
		var target_range = camera.BallRadius
		var pos = camera.BallRangeMesh.global_transform.origin
		var placed_count = 0
		
		for i in range(Creature.world_surface_points.size()):
			var p = Creature.world_surface_points[i]
			
			# 检查附着点是否已被占用
			if i >= Creature.world_surface_point_is_attached.size() or Creature.world_surface_point_is_attached[i]:
				continue
				
			# 检查是否在目标范围内
			if p.distance_to(pos) <= target_range:
				# 预先标记附着点为已占用，避免重复放置
				Creature.world_surface_point_is_attached[i] = true
				
				# 使用复制的基因组创建新生物
				var mutated_genome = GenomeUtils.mutate_genome(copied_genome)
				var c = Creature.new(mutated_genome, Transform3D.IDENTITY)
				c.attach_to_surface_point(i)
				placed_count += 1
		
		if placed_count > 0:
			print("[INPUT] Pasted %d creatures with copied genome (source index: %d)" % [placed_count, copied_genome_source_index])
			# 通知任务系统有新生物被粘贴
			_notify_mission_creature_placed(placed_count)
		else:
			print("[INPUT] No suitable attachment points found in ball range for pasting")
		return
	
	# 移除功能：删除球体范围内的所有生物
	if(event.is_action_pressed("remove")):
		var target_range = camera.BallRadius
		var pos = camera.BallRangeMesh.global_transform.origin
		var removed_count = 0
		var creatures_to_remove: Array = []
		
		# 先收集需要移除的生物，避免在迭代过程中修改数组
		for creature in Creature.creatures:
			if creature == null or not creature.is_alive:
				continue
				
			# 检查生物是否在目标范围内
			if creature.position.distance_to(pos) <= target_range:
				creatures_to_remove.append(creature)
		
		# 移除收集到的生物
		for creature in creatures_to_remove:
			creature.is_alive = false  # 标记为死亡，让cleanup_dead()处理
			removed_count += 1
		
		# 立即清理死亡的生物
		Creature.cleanup_dead()
		
		if removed_count > 0:
			print("[INPUT] Removed %d creatures in ball range" % removed_count)
			# 通知任务系统有生物被移除
			_notify_mission_creature_removed(removed_count)
		else:
			print("[INPUT] No creatures found in ball range to remove")
		return
	
	# 阻止功能：屏蔽球体范围内的附着点
	if(event.is_action_pressed("block")):
		var target_range = camera.BallRadius
		var pos = camera.BallRangeMesh.global_transform.origin
		var blocked_count = 0
		
		# 确保 blocked 数组大小与 surface_points 数组一致
		while Creature.world_surface_point_is_blocked.size() < Creature.world_surface_points.size():
			Creature.world_surface_point_is_blocked.append(false)
		
		for i in range(Creature.world_surface_points.size()):
			var p = Creature.world_surface_points[i]
			
			# 检查附着点是否在目标范围内
			if p.distance_to(pos) <= target_range:
				# 如果附着点未被屏蔽，则屏蔽它
				if not Creature.world_surface_point_is_blocked[i]:
					Creature.world_surface_point_is_blocked[i] = true
					# 同时设置 attached 状态以立即生效
					if i < Creature.world_surface_point_is_attached.size():
						Creature.world_surface_point_is_attached[i] = true
					else:
						# 扩展数组大小如果需要
						while Creature.world_surface_point_is_attached.size() <= i:
							Creature.world_surface_point_is_attached.append(false)
						Creature.world_surface_point_is_attached[i] = true
					blocked_count += 1
		
		if blocked_count > 0:
			print("[INPUT] Blocked %d attachment points in ball range" % blocked_count)
		else:
			print("[INPUT] No available attachment points found in ball range to block")
		return
	
	# 解除阻止功能：解除屏蔽球体范围内的附着点
	if(event.is_action_pressed("unblock")):
		var target_range = camera.BallRadius
		var pos = camera.BallRangeMesh.global_transform.origin
		var unblocked_count = 0
		
		# 确保 blocked 数组大小与 surface_points 数组一致
		while Creature.world_surface_point_is_blocked.size() < Creature.world_surface_points.size():
			Creature.world_surface_point_is_blocked.append(false)
		
		for i in range(Creature.world_surface_points.size()):
			var p = Creature.world_surface_points[i]
			
			# 检查附着点是否在目标范围内
			if p.distance_to(pos) <= target_range:
				# 如果附着点被用户屏蔽，则解除屏蔽
				if i < Creature.world_surface_point_is_blocked.size() and Creature.world_surface_point_is_blocked[i]:
					Creature.world_surface_point_is_blocked[i] = false
					
					# 检查该附着点是否真的被生物占用
					var is_occupied_by_creature = false
					for creature in Creature.creatures:
						if creature != null and creature.is_alive:
							# 检查多种占用情况
							if creature.now_attached_id == i or creature.attachments.has(i) or (creature.is_reproducing and creature._plant_repro_found_points.has(i)):
								is_occupied_by_creature = true
								break
					
					# 只有在没有生物占用时才解除 attached 状态
					if not is_occupied_by_creature and i < Creature.world_surface_point_is_attached.size():
						Creature.world_surface_point_is_attached[i] = false
					
					unblocked_count += 1
		
		if unblocked_count > 0:
			print("[INPUT] Unblocked %d attachment points in ball range" % unblocked_count)
		else:
			print("[INPUT] No blocked attachment points found in ball range to unblock")
		return
	
	# 任务系统相关输入处理
	if mission:
		# F1 - 显示当前任务信息（调试用）
		if event.is_action_pressed("ui_accept"):  # Enter键
			var mission_info = mission.get_current_mission_info()
			if mission_info.size() > 0:
				print("[MISSION DEBUG] Current: %s | Progress: %.1f%% (%s/%s)" % [
					mission_info["description"], 
					mission_info["progress"], 
					mission_info["current"], 
					mission_info["target"]
				])
			else:
				print("[MISSION DEBUG] No active mission")
		
		# ESC - 跳过当前任务；Shift+ESC 重置任务系统
		if event.is_action_pressed("ui_cancel"):  # Escape键
			if Input.is_key_pressed(KEY_SHIFT):
				mission.reset_mission_system()
				print("[MISSION DEBUG] Mission system reset")
			elif mission.can_skip_mission():
				mission.skip_current_mission()
				print("[MISSION DEBUG] Mission skipped via ESC")

func _physics_process(delta: float) -> void:
	# 获取实际的时间步长（考虑速度倍率和暂停状态）
	var effective_delta = delta * speed_radio
	
	# 只有在非暂停状态下才更新生物逻辑
	if not is_paused and speed_radio > 0:
		# Update creature simulation/state
		for c in Creature.creatures:
			c.update(effective_delta)

		# Remove dead creatures after update so subsequent rendering/instancing matches live set
		Creature.cleanup_dead()
		
		# 更新任务系统（任务系统有自己的更新逻辑，但我们可以在这里触发特殊事件）
		if mission:
			_update_mission_events()
			# 状态报告现在直接在Mission界面显示，无需定期触发
		
		# Periodically validate and fix attachment states (every 5 seconds of real time)
		_attachment_validation_timer += delta  # 使用真实时间，不受速度影响
		if _attachment_validation_timer >= 5.0:
			_attachment_validation_timer = 0.0
			Creature.cleanup_invalid_reproduction_states()
			Creature.validate_and_fix_attachment_state()

		# Trigger periodic rebuild of the creatures octree using accumulator
		_creatures_octree_acc += effective_delta  # 使用游戏时间
		if _creatures_octree_acc >= creatures_octree_rebuild_interval:
			_creatures_octree_acc = 0.0
			Creature.rebuild_creatures_octree()

	# 渲染更新始终执行（即使暂停也要显示当前状态）
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

	if DEBUG_SHOW_SAMPLES and not is_paused:
		print("[PHYSICS] creatures_count=", Creature.creatures.size(), " multimesh_count=", mm.instance_count)

# 任务系统事件处理
func _update_mission_events() -> void:
	"""处理任务系统相关的游戏事件"""
	if not mission:
		return
		
	var current_mission_info = mission.get_current_mission_info()
	if current_mission_info.size() == 0:
		return
	
	# 检查是否有重要的游戏事件需要通知任务系统
	# 例如：新生物诞生、重大进化、生态系统变化等
	
	# 检查是否有重大进化事件（生物大小显著增长）
	var current_max_size = 0.0
	
	for creature in Creature.creatures:
		if creature and creature.is_alive:
			current_max_size = max(current_max_size, creature.current_size_m)
	
	# 检查是否有重大进化突破
	if current_max_size > max_creature_size_ever * 1.5:
		max_creature_size_ever = current_max_size
		_notify_mission_major_evolution()
	
	# 可以在这里添加特殊的任务完成庆祝效果
	# 或者根据游戏状态动态调整任务难度等

# 任务系统通知函数
func _notify_mission_creature_placed(count: int) -> void:
	"""通知任务系统有新生物被放置"""
	if not mission:
		return
	
	# 可以在这里添加特殊效果或者任务进度加速
	print("[MISSION] Notified: %d creatures placed" % count)

func _notify_mission_creature_removed(count: int) -> void:
	"""通知任务系统有生物被移除"""
	if not mission:
		return
	
	print("[MISSION] Notified: %d creatures removed" % count)

func _notify_mission_major_evolution() -> void:
	"""通知任务系统发生了重大进化事件"""
	if not mission:
		return
	
	print("[MISSION] Notified: Major evolution detected")

# 获取任务系统状态的辅助函数
func get_mission_progress() -> Dictionary:
	"""获取当前任务进度信息"""
	if not mission:
		return {}
	return mission.get_current_mission_info()

func is_mission_system_active() -> bool:
	"""检查任务系统是否激活"""
	return mission != null

func complete_current_mission_debug() -> void:
	"""调试用：完成当前任务"""
	if mission:
		mission.force_complete_current_mission()

func reset_mission_system_debug() -> void:
	"""调试用：重置任务系统"""
	if mission:
		mission.reset_mission_system()

func _show_initial_mission_info() -> void:
	"""显示初始任务信息"""
	if not mission:
		return
		
	var mission_info = mission.get_current_mission_info()
	if mission_info.size() > 0:
		print("=== MISSION SYSTEM STARTED ===")
		print("Current Mission: %s" % mission_info["description"])
		print("Target: %s" % mission_info["target"])
		print("Progress: %.1f%%" % mission_info["progress"])
		print("Mission %d of %d" % [mission_info["mission_index"], mission_info["total_missions"]])
		print("==============================")

# 添加一些游戏状态查询函数供任务系统使用
func get_current_creature_count() -> int:
	"""获取当前生物数量（供任务系统使用）"""
	return Creature.creatures.size()

func get_current_plant_count() -> int:
	"""获取当前植物数量（供任务系统使用）"""
	return Creature.get_current_plant_count()

func get_current_max_creature_size() -> float:
	"""获取当前最大生物体型（供任务系统使用）"""
	var max_size = 0.0
	for creature in Creature.creatures:
		if creature and creature.is_alive:
			max_size = max(max_size, creature.current_size_m)
	return max_size

func get_current_average_creature_size() -> float:
	"""获取当前平均生物体型（供任务系统使用）"""
	var total_size = 0.0
	var count = 0
	for creature in Creature.creatures:
		if creature and creature.is_alive:
			total_size += creature.current_size_m
			count += 1
	return total_size / max(1, count)

# 注释：状态报告功能已移至Mission界面直接显示
# func _show_mission_status_report() -> void:
# 	"""定期显示任务状态报告 - 已废弃，状态现在直接在Mission界面显示"""
