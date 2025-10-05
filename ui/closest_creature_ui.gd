extends Label

# 显示与当前摄像机距离最近生物的实时信息（年龄、能量、血量等）
# 使用方法：在场景中添加一个 Label 节点并把此脚本附加到它。
# 要求：项目中存在全局可访问的 `Creature` 类（带有静态数组 `Creature.creatures`）

@export var update_rate: float = 0.01 # 信息刷新间隔（秒）
@export var max_distance: float = 10.0 # 搜索最近生物的最大距离

var _acc: float = 0.0

func _ready() -> void:
	# 现在这个脚本直接继承自Label，所以不需要创建子Label
	# 所有的大小、位置、字体等属性都可以在场景编辑器中直接设置
	self.text = ""
	self.visible = true

func _process(delta: float) -> void:
	_acc += delta
	if _acc >= update_rate:
		_acc = 0.0
		_update_closest_creature()

func _update_closest_creature() -> void:
	# 获取当前活动的 3D 摄像机
	var cam: Camera3D = get_viewport().get_camera_3d()
	if not cam:
		# 没有摄像机时隐藏信息
		self.text = ""
		return
	var cam_pos: Vector3 = cam.global_transform.origin

	var best_creature: Creature = null
	var best_dist: float = 1e20

	# 遍历全局生物列表，寻找距离最近且存活的生物
	for i in range(Creature.creatures.size()):
		var c = Creature.creatures[i]
		if not c:
			continue
		if not c.is_alive:
			continue
		# 优先使用静态位置数组（若存在），否则使用实例的位置字段
		var pos: Vector3 = c.position
		if c.index >= 0 and c.index < Creature.creatures_world_positions.size():
			pos = Creature.creatures_world_positions[c.index]
		var d = cam_pos.distance_to(pos)
		if d < best_dist and d <= max_distance:
			best_dist = d
			best_creature = c

	# 如果没有找到合适的生物，清空显示
	if not best_creature:
		call_deferred("set_text", "")
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
