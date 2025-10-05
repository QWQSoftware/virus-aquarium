class_name CloestCreatureUI extends Label

# 显示与给定位置距离最近生物的实时信息（年龄、能量、血量等），并可选地在屏幕上显示目标指示器
# 使用方法：在场景中添加一个 Label 节点并把此脚本附加到它，然后通过 set_reference_position() 函数设置参考位置。
# 可选：将一个 Control 节点分配给 target_indicator 属性来显示目标生物的屏幕位置指示器。
# 要求：项目中存在全局可访问的 `Creature` 类（带有静态数组 `Creature.creatures`）

@export var max_distance: float = 50.0 # 搜索最近生物的最大距离
@export var target_indicator: Control # 用于显示目标生物位置的UI控件（可选）

@export var debug_mesh_3d :MeshInstance3D

var _reference_position: Vector3 = Vector3.ZERO # 用于计算距离的参考位置
var _current_target_creature: Creature = null # 当前目标生物

# 设置参考位置的函数，用于信号连接
func set_reference_position(pos: Vector3) -> void:
	_reference_position = pos

# 获取生物的实际世界位置（优先使用世界位置数组）
func _get_creature_world_position(creature: Creature) -> Vector3:
	if not creature:
		if OS.is_debug_build():
			print("[DEBUG] _get_creature_world_position: creature is null")
		return Vector3.ZERO
	
	# 首先尝试从Node3D获取实时位置（如果Creature继承自Node3D）
	if creature.has_method("get_global_position") or "global_position" in creature:
		var node_pos = creature.global_position
		if OS.is_debug_build():
			print("[DEBUG] Using global_position for creature %d: %s" % [creature.index, str(node_pos)])
		return node_pos
	
	# 优先使用静态位置数组（若存在且索引有效）
	if creature.index >= 0 and creature.index < Creature.creatures_world_positions.size():
		var world_pos = Creature.creatures_world_positions[creature.index]
		if OS.is_debug_build():
			print("[DEBUG] Using world_positions array for creature %d: %s" % [creature.index, str(world_pos)])
		return world_pos
	
	# 回退到实例的位置字段
	var instance_pos = creature.position
	if OS.is_debug_build():
		print("[DEBUG] Using creature.position for creature %d: %s (world_positions size: %d)" % [creature.index, str(instance_pos), Creature.creatures_world_positions.size()])
	return instance_pos

func _ready() -> void:
	# 现在这个脚本直接继承自Label，所以不需要创建子Label
	# 所有的大小、位置、字体等属性都可以在场景编辑器中直接设置
	self.text = ""
	self.visible = true

func _process(_delta: float) -> void:
	_update_closest_creature()

func _update_closest_creature() -> void:
	# 使用给定的参考位置而不是相机位置
	var reference_pos: Vector3 = _reference_position
	
	# 如果没有设置参考位置，使用相机位置作为参考
	if reference_pos == Vector3.ZERO:
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam:
			reference_pos = cam.global_position
		else:
			if OS.is_debug_build():
				print("[DEBUG] No reference position and no camera found")
			return

	var best_creature: Creature = null
	var best_dist: float = 1e20
	var total_creatures: int = 0
	var alive_creatures: int = 0
	var creatures_in_range: int = 0

	# 遍历全局生物列表，寻找距离最近且存活的生物
	for i in range(Creature.creatures.size()):
		var c = Creature.creatures[i]
		total_creatures += 1
		
		if not c:
			# 调试：记录空指针
			continue
			
		if not c.is_alive:
			# 调试：记录非存活生物
			continue
			
		alive_creatures += 1
		
		# 获取生物的实际世界位置
		var pos: Vector3 = _get_creature_world_position(c)
		var d = reference_pos.distance_to(pos)
		
		# 调试：检查距离是否在范围内
		if d <= max_distance:
			creatures_in_range += 1
		
		if d < best_dist and d <= max_distance:
			best_dist = d
			best_creature = c

	# 添加调试信息
	if OS.is_debug_build():
		print("[DEBUG] Reference pos: %s, Max distance: %.1f" % [str(reference_pos), max_distance])
		print("[DEBUG] Total creatures: %d, Alive: %d, In range: %d" % [total_creatures, alive_creatures, creatures_in_range])
		if best_creature:
			var best_pos = _get_creature_world_position(best_creature)
			print("[DEBUG] Best creature %d found at distance: %.2fm, position: %s" % [best_creature.index, best_dist, str(best_pos)])
		else:
			print("[DEBUG] No creature found within range")

	# 如果没有找到合适的生物，清空显示
	if not best_creature:
		_current_target_creature = null
		call_deferred("set_text", "")
		_update_target_indicator()
		return

	# 从生物中提取信息并格式化显示
	var info_lines: Array = []
	info_lines.append("Index: %d" % best_creature.index)
	info_lines.append("Dist: %.2f m" % best_dist)
	info_lines.append("Age: %.1f s" % best_creature.age_s)
	# 寿命 / 繁殖信息：最大寿命、成年年龄、终止生育年龄、剩余寿命及进度
	var max_lifespan: float = 0.0
	var adult_age: float = 0.0
	var fertility_end: float = 1e9
	# 直接从 Creature 实例字段读取（这些字段在 Creature 类中有默认声明）
	max_lifespan = float(best_creature.max_lifespan_s)
	adult_age = float(best_creature.adult_age_s)
	fertility_end = float(best_creature.fertility_end_s)

	info_lines.append("Max life: %.1f s" % max_lifespan)
	info_lines.append("Adult age: %.1f s" % adult_age)
	info_lines.append("Fertility end: %.1f s" % fertility_end)

	var life_remaining: float = max(0.0, max_lifespan - best_creature.age_s) if max_lifespan > 0.0 else 0.0
	info_lines.append("Life remaining: %.1f s" % life_remaining)
	var life_pct: float = (best_creature.age_s / max_lifespan) * 100.0 if max_lifespan > 0.0 else 0.0
	info_lines.append("Life progress: %.1f%%" % life_pct)

	var is_fertile: bool = (best_creature.age_s >= adult_age and best_creature.age_s <= fertility_end)
	info_lines.append("Fertile: %s" % ("Yes" if is_fertile else "No"))
	if is_fertile:
		info_lines.append("Fertile remaining: %.1f s" % max(0.0, fertility_end - best_creature.age_s))

	# 植物专用：显示植物繁殖状态与进度（如果适用）
	if best_creature.is_plant:
		info_lines.append("Plant: Yes")
		info_lines.append("Plant reproducing: %s" % ("Yes" if best_creature.is_reproducing else "No"))
		if best_creature.is_reproducing:
			var mode_str: String = "None"
			if best_creature._plant_repro_mode == 1:
				mode_str = "Pair"
			elif best_creature._plant_repro_mode == 2:
				mode_str = "Self"
			info_lines.append("Plant repro mode: %s" % mode_str)
			info_lines.append("Repro progress: %.0f%%" % clamp(best_creature.progress * 100.0, 0.0, 100.0))

	# 能量/血量/精力 直接从 Creature 实例读取（已在 Creature 中声明）
	var energy: float = 0.0
	var health: float = 0.0
	var stamina: float = 0.0

	# 直接读取并转为 float，防止显示为 Variant
	if typeof(best_creature.energy_p) != TYPE_NIL:
		energy = float(best_creature.energy_p)
	if typeof(best_creature.health_p) != TYPE_NIL:
		health = float(best_creature.health_p)
	if typeof(best_creature.stamina_p) != TYPE_NIL:
		stamina = float(best_creature.stamina_p)
	info_lines.append("Energy: %.1f" % energy)
	info_lines.append("Health: %.1f" % health)
	info_lines.append("Stamina: %.1f" % stamina)

	# 额外展示：最大能量 / 当前能量百分比
	var max_energy_init: float = best_creature.max_energy_init_p if typeof(best_creature.max_energy_init_p) != TYPE_NIL else 0.0
	var max_energy_adult: float = best_creature.max_energy_adult_p if typeof(best_creature.max_energy_adult_p) != TYPE_NIL else max_energy_init
	var energy_pct: float = (energy / max(1.0, max_energy_adult)) * 100.0
	info_lines.append("Max energy (init/adult): %.1f / %.1f" % [max_energy_init, max_energy_adult])
	info_lines.append("Energy %%: %.1f%%" % energy_pct)

	# 血量相关（显示当前 / 成年上限 / 百分比）
	var hp_init: float = best_creature.health_init_p if typeof(best_creature.health_init_p) != TYPE_NIL else 0.0
	var hp_adult: float = best_creature.health_adult_p if typeof(best_creature.health_adult_p) != TYPE_NIL else max(1.0, hp_init)
	var hp_pct: float = (health / max(1.0, hp_adult)) * 100.0
	info_lines.append("Health (init/adult): %.1f / %.1f" % [hp_init, hp_adult])
	info_lines.append("Health %%: %.1f%%" % hp_pct)

	# 精力（stamina）上限与百分比
	var stam_max: float = best_creature.stamina_max_p if typeof(best_creature.stamina_max_p) != TYPE_NIL else 0.0
	var stam_pct: float = (stamina / max(1.0, stam_max)) * 100.0 if stam_max > 0.0 else 0.0
	info_lines.append("Stamina max: %.1f" % stam_max)
	info_lines.append("Stamina %%: %.1f%%" % stam_pct)

	# 繁殖 / 自复制能量阈值与消耗（直接显示实例字段）
	var mating_req = best_creature.mating_required_energy_p if typeof(best_creature.mating_required_energy_p) != TYPE_NIL else 0.0
	var mating_cost = best_creature.mating_energy_cost_p if typeof(best_creature.mating_energy_cost_p) != TYPE_NIL else 0.0
	var selfrep_req = best_creature.selfrep_required_energy_p if typeof(best_creature.selfrep_required_energy_p) != TYPE_NIL else 0.0
	var selfrep_cost = best_creature.selfrep_energy_cost_p if typeof(best_creature.selfrep_energy_cost_p) != TYPE_NIL else 0.0
	info_lines.append("Mating req/cost: %.1f / %.1f" % [mating_req, mating_cost])
	info_lines.append("Selfrep req/cost: %.1f / %.1f" % [selfrep_req, selfrep_cost])

	# 冷却与繁殖状态
	var cooldown_timer: float = best_creature.cooldown_timer if typeof(best_creature.cooldown_timer) != TYPE_NIL else 0.0
	var mating_cooldown: float = best_creature.mating_cooldown_s if typeof(best_creature.mating_cooldown_s) != TYPE_NIL else 0.0
	var selfrep_cooldown: float = best_creature.selfrep_cooldown_s if typeof(best_creature.selfrep_cooldown_s) != TYPE_NIL else 0.0
	info_lines.append("Cooldown timer: %.1f s (mating cooldown: %.1f s, selfrep cooldown: %.1f s)" % [cooldown_timer, mating_cooldown, selfrep_cooldown])
	info_lines.append("Is reproducing: %s" % ("Yes" if best_creature.is_reproducing else "No"))
	
	var info_text = "\n".join(info_lines)
	call_deferred("set_text", info_text)
	
	# 更新目标指示器位置
	_current_target_creature = best_creature
	_update_target_indicator()

# 更新目标指示器在屏幕上的位置
func _update_target_indicator() -> void:
	if not target_indicator:
		return
		
	if not _current_target_creature:
		# 没有目标时隐藏指示器
		target_indicator.visible = false
		return
	
	# 获取当前活动的3D摄像机
	var cam: Camera3D = get_viewport().get_camera_3d()
	if not cam:
		target_indicator.visible = false
		return
	
	# 获取目标生物的3D位置
	var target_pos_3d: Vector3 = _get_creature_world_position(_current_target_creature)
	
	# 检查目标是否在相机前方
	var cam_transform = cam.get_camera_transform()
	var to_target = target_pos_3d - cam_transform.origin
	if cam_transform.basis.z.dot(to_target) > 0:
		# 目标在相机后方，隐藏指示器
		target_indicator.visible = false
		return
	
	# 将3D位置投影到屏幕2D坐标
	var screen_pos: Vector2 = cam.unproject_position(target_pos_3d)
	
	# 调试信息
	if OS.is_debug_build():
		print("[DEBUG] Target 3D pos: %s, Screen pos: %s" % [str(target_pos_3d), str(screen_pos)])
		print("[DEBUG] Camera pos: %s, Camera forward: %s" % [str(cam_transform.origin), str(-cam_transform.basis.z)])
	
	# 检查目标是否在相机视野内
	var viewport_size = get_viewport().get_visible_rect().size
	if screen_pos.x >= 0 and screen_pos.x <= viewport_size.x and screen_pos.y >= 0 and screen_pos.y <= viewport_size.y:
		# 目标在屏幕内，显示指示器
		target_indicator.visible = true
		target_indicator.position = screen_pos - target_indicator.size * 0.5  # 居中对齐
		
		if OS.is_debug_build():
			print("[DEBUG] Indicator positioned at: %s (size: %s)" % [str(target_indicator.position), str(target_indicator.size)])
	else:
		# 目标在屏幕外，可以选择隐藏或显示在屏幕边缘
		target_indicator.visible = false
		
		if OS.is_debug_build():
			print("[DEBUG] Target out of screen bounds. Viewport size: %s" % str(viewport_size))
