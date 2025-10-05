extends Control
class_name MissionSystem

var mission_label : RichTextLabel
var skip_button : Button

# 游戏节点引用（用于获取游戏状态）
var game_node: Node3D = null

# 任务类型枚举
enum MissionType {
	TOTAL_POPULATION,    # 总生物数量达到目标
	MAX_CREATURE_SIZE,   # 最大生物体型达到目标
	PLANT_POPULATION,    # 植物数量达到目标
	REPRODUCE_COUNT,     # 繁殖次数达到目标
	AVERAGE_SIZE         # 平均体型达到目标
}

# 任务数据结构
class Mission:
	var type: MissionType
	var target_value: float
	var current_value: float
	var description: String
	var reward_text: String
	var is_completed: bool = false
	
	func _init(mission_type: MissionType, target: float, desc: String, reward: String = ""):
		type = mission_type
		target_value = target
		current_value = 0.0
		description = desc
		reward_text = reward

# 任务系统状态
var current_mission: Mission = null
var mission_queue: Array[Mission] = []
var mission_index: int = 0
var skip_cooldown_timer: float = 0.0
var skip_cooldown_duration: float = 3.0  # 跳过冷却时间（秒）
var is_skipping_mission: bool = false  # 标记是否正在跳过任务

# 统计数据
var max_creature_size_ever: float = 0.0
var completed_missions_count: int = 0

# 预设任务模板
var mission_templates: Array[Dictionary] = [
	{
		"type": MissionType.TOTAL_POPULATION,
		"base_target": 10,
		"multiplier_range": [1.5, 3.0],
		"description_template": "Reach %d total creatures",
		"reward": "Population milestone achieved!"
	},
	{
		"type": MissionType.MAX_CREATURE_SIZE,
		"base_target": 1.0,
		"multiplier_range": [1.0, 1.7],
		"description_template": "Evolve creature to %.1fm size",
		"reward": "Evolution breakthrough!"
	},
	{
		"type": MissionType.PLANT_POPULATION,
		"base_target": 5,
		"multiplier_range": [1.5, 2.5],
		"description_template": "Cultivate %d plant organisms",
		"reward": "Ecosystem established!"
	},
	{
		"type": MissionType.AVERAGE_SIZE,
		"base_target": 1.0,
		"multiplier_range": [1.2, 2.0],
		"description_template": "Achieve %.2fm average creature size",
		"reward": "Population evolution success!"
	}
]

func _ready() -> void:
	"""初始化任务系统"""
	print("[MISSION] Initializing mission system...")
	
	# 手动获取节点引用
	mission_label = get_node("VBoxContainer2/VBoxContainer/MarginContainer2/RichTextLabel")
	skip_button = get_node("VBoxContainer2/MarginContainer3/Button")
	
	print("[MISSION] Mission label found: ", mission_label != null)
	print("[MISSION] Skip button found: ", skip_button != null)
	
	if skip_button:
		# 确保先断开旧连接（如果有的话）
		if skip_button.pressed.is_connected(_on_skip_button_pressed):
			skip_button.pressed.disconnect(_on_skip_button_pressed)
		
		skip_button.pressed.connect(_on_skip_button_pressed)
		skip_button.disabled = false
		print("[MISSION] Skip button connected and enabled")
		
		# 测试按钮是否可点击
		print("[MISSION] Skip button disabled state: ", skip_button.disabled)
		print("[MISSION] Skip button text: ", skip_button.text)
	else:
		print("[MISSION] ERROR: Skip button not found!")
	
	# 获取游戏节点引用
	game_node = get_parent()
	
	_initialize_missions()
	_start_next_mission()

func _process(delta: float) -> void:
	# 更新跳过按钮冷却
	if skip_button:
		if skip_cooldown_timer > 0.0:
			skip_cooldown_timer -= delta
			skip_button.text = "SKIP (%ds)" % int(skip_cooldown_timer + 1)
			skip_button.disabled = true
		else:
			skip_button.text = "SKIP"
			skip_button.disabled = false
			# 添加调试信息（每5秒打印一次状态）
			if int(Time.get_time_dict_from_system()["second"]) % 5 == 0:
				print("[MISSION DEBUG] Skip button enabled, cooldown: %.1f" % skip_cooldown_timer)
	
	# 更新当前任务进度
	if current_mission and not current_mission.is_completed and not is_skipping_mission:
		_update_mission_progress()
		_update_mission_display()
		
		# 检查任务完成
		if current_mission.current_value >= current_mission.target_value:
			_complete_current_mission()

func _initialize_missions() -> void:
	"""初始化任务队列，自动生成目标参数"""
	mission_queue.clear()
	
	# 使用模板生成任务
	for template in mission_templates:
		var mission = _generate_mission_from_template(template)
		if mission:
			mission_queue.append(mission)
	
	# 打乱任务顺序增加变化性
	mission_queue.shuffle()
	
	print("[MISSION] Initialized %d missions" % mission_queue.size())

func _generate_next_endless_mission() -> void:
	"""生成下一个无穷尽任务"""
	# 随机选择一个任务模板
	var template = mission_templates[randi() % mission_templates.size()]
	var new_mission = _generate_mission_from_template(template)
	
	if new_mission:
		# 直接设置为当前任务，而不是添加到队列
		current_mission = new_mission
		current_mission.is_completed = false
		print("[MISSION] Generated endless mission: %s, Target: %s" % [new_mission.description, new_mission.target_value])
	else:
		print("[ERROR] Failed to generate endless mission")

func _generate_mission_from_template(template: Dictionary) -> Mission:
	"""从模板生成任务"""
	var mission_type: MissionType = template["type"]
	var base_target = template["base_target"]
	var multiplier_range = template["multiplier_range"]
	var desc_template = template["description_template"]
	var reward = template["reward"]
	
	var target = _generate_target_from_template(mission_type, base_target, multiplier_range)
	var description = ""
	
	match mission_type:
		MissionType.TOTAL_POPULATION, MissionType.PLANT_POPULATION:
			description = desc_template % int(target)
		MissionType.MAX_CREATURE_SIZE, MissionType.AVERAGE_SIZE:
			description = desc_template % target
		_:
			description = desc_template % target
	
	return Mission.new(mission_type, target, description, reward)

func _generate_target_from_template(type: MissionType, base_target: float, multiplier_range: Array) -> float:
	"""根据模板和当前状态生成目标值"""
	var current_value = _get_current_value_for_type(type)
	
	# 基于完成任务数增加难度
	var difficulty_factor = 1.0 + (completed_missions_count * 0.1)  # 每完成10个任务难度增加100%
	var adjusted_base = max(base_target, current_value * 1.2) * difficulty_factor
	
	var multiplier = randf_range(multiplier_range[0], multiplier_range[1])
	return adjusted_base * multiplier

func _get_current_value_for_type(type: MissionType) -> float:
	"""获取指定任务类型的当前值"""
	match type:
		MissionType.TOTAL_POPULATION:
			return float(Creature.creatures.size())
		MissionType.MAX_CREATURE_SIZE:
			return _get_current_max_creature_size()
		MissionType.PLANT_POPULATION:
			return float(Creature.get_current_plant_count())
		MissionType.AVERAGE_SIZE:
			return _get_current_average_creature_size()
		_:
			return 1.0

# 旧的目标生成函数已被模板系统替代

func _start_next_mission() -> void:
	"""开始下一个任务"""
	if mission_index >= mission_queue.size():
		# 动态生成新任务（无穷尽模式）
		_generate_next_endless_mission()
	else:
		# 使用预设任务队列
		current_mission = mission_queue[mission_index]
		current_mission.is_completed = false
		current_mission.current_value = 0.0
	
	# 清除skip冷却和跳过状态（新任务开始时允许立即跳过）
	skip_cooldown_timer = 0.0
	is_skipping_mission = false
	if skip_button:
		skip_button.disabled = false
		skip_button.text = "SKIP"
	
	print("[MISSION] Started mission %d: %s (Target: %.1f)" % [mission_index + 1, current_mission.description, current_mission.target_value])
	_update_mission_display()

func _update_mission_progress() -> void:
	"""更新当前任务进度"""
	if not current_mission:
		return
		
	match current_mission.type:
		MissionType.TOTAL_POPULATION:
			current_mission.current_value = float(Creature.creatures.size())
		
		MissionType.MAX_CREATURE_SIZE:
			var max_size = _get_current_max_creature_size()
			current_mission.current_value = max_size
			max_creature_size_ever = max(max_creature_size_ever, max_size)
		
		MissionType.PLANT_POPULATION:
			current_mission.current_value = float(Creature.get_current_plant_count())
		
		MissionType.AVERAGE_SIZE:
			current_mission.current_value = _get_current_average_creature_size()
		
		MissionType.REPRODUCE_COUNT:
			# 这需要在生物系统中跟踪繁殖次数
			pass

func _get_current_max_creature_size() -> float:
	"""获取当前最大生物体型"""
	var max_size = 0.0
	for creature in Creature.creatures:
		if creature and creature.is_alive:
			max_size = max(max_size, creature.current_size_m)
	return max_size

func _get_current_average_creature_size() -> float:
	"""获取当前平均生物体型"""
	var total_size = 0.0
	var count = 0
	for creature in Creature.creatures:
		if creature and creature.is_alive:
			total_size += creature.current_size_m
			count += 1
	return total_size / max(1, count)

func _update_mission_display() -> void:
	"""更新任务显示文本"""
	if not current_mission:
		mission_label.text = "No active mission"
		return
	
	var progress_percent = (current_mission.current_value / current_mission.target_value) * 100.0
	var progress_bar = _create_progress_bar(progress_percent)
	
	var display_text = ""
	display_text += "MISSION %d | COMPLETED: %d\n" % [mission_index + 1, completed_missions_count]
	display_text += "%s\n\n" % current_mission.description
	display_text += "Progress: %.1f / %.1f\n" % [current_mission.current_value, current_mission.target_value]
	display_text += "%s\n" % progress_bar
	display_text += "%.1f%% Complete\n\n" % progress_percent
	
	# 添加分隔线
	display_text += "─────────────────────\n"
	
	# 添加游戏状态信息
	display_text += _get_game_status_text()
	
	mission_label.text = display_text

func _create_progress_bar(percent: float) -> String:
	"""创建ASCII进度条"""
	var bar_length = 20
	var filled_length = int((percent / 100.0) * bar_length)
	var bar = ""
	
	bar += "["
	for i in range(bar_length):
		if i < filled_length:
			bar += "■"
		else:
			bar += "□"
	bar += "]"
	
	return bar

func _get_game_status_text() -> String:
	"""获取游戏状态文本"""
	if not game_node:
		return "Game status unavailable"
	
	var status_text = "CURRENT STATUS\n"
	
	# 获取游戏状态数据
	var creature_count = 0
	var plant_count = 0
	var max_size = 0.0
	var avg_size = 0.0
	
	if game_node.has_method("get_current_creature_count"):
		creature_count = game_node.get_current_creature_count()
	
	if game_node.has_method("get_current_plant_count"):
		plant_count = game_node.get_current_plant_count()
	
	if game_node.has_method("get_current_max_creature_size"):
		max_size = game_node.get_current_max_creature_size()
	
	if game_node.has_method("get_current_average_creature_size"):
		avg_size = game_node.get_current_average_creature_size()
	
	status_text += "🦠 Creatures: %d\n" % creature_count
	status_text += "🌱 Plants: %d\n" % plant_count
	status_text += "📏 Max Size: %.2fm\n" % max_size
	status_text += "📊 Avg Size: %.2fm" % avg_size
	
	return status_text

func _complete_current_mission() -> void:
	"""完成当前任务"""
	if not current_mission:
		return
		
	current_mission.is_completed = true
	completed_missions_count += 1
	print("[MISSION] Mission completed: %s (Total: %d)" % [current_mission.description, completed_missions_count])
	
	# 显示完成信息
	var completion_text = ""
	completion_text += "MISSION COMPLETE!\n"
	completion_text += "%s\n" % current_mission.description
	completion_text += "%s" % current_mission.reward_text
	
	mission_label.text = completion_text
	
	# 2秒后开始下一个任务
	await get_tree().create_timer(2.0).timeout
	mission_index += 1
	_start_next_mission()

func _skip_current_mission() -> void:
	"""跳过当前任务"""
	if not current_mission:
		return
	
	is_skipping_mission = true
	print("[MISSION] Mission skipped: %s" % current_mission.description)
	
	# 显示跳过信息
	var skip_text = ""
	skip_text += "MISSION SKIPPED!\n"
	skip_text += "%s\n" % current_mission.description
	skip_text += "Moving to next mission..."
	
	mission_label.text = skip_text
	
	# 1秒后开始下一个任务（比完成更快）
	await get_tree().create_timer(1.0).timeout
	mission_index += 1
	is_skipping_mission = false
	_start_next_mission()

func _on_skip_button_pressed() -> void:
	"""处理跳过按钮点击"""
	print("[MISSION] Skip button pressed!")
	print("[MISSION] Current cooldown timer: %.1f" % skip_cooldown_timer)
	print("[MISSION] Current mission exists: ", current_mission != null)
	
	if skip_cooldown_timer > 0.0:
		print("[MISSION] Skip button is on cooldown: %.1fs remaining" % skip_cooldown_timer)
		return  # 还在冷却中
	
	if not current_mission or current_mission.is_completed:
		print("[MISSION] No current mission to skip or mission already completed")
		return
	
	if is_skipping_mission:
		print("[MISSION] Already skipping a mission")
		return
	
	# 播放音效
	if has_node("AudioStreamPlayer"):
		$AudioStreamPlayer.play()
	
	# 开始冷却
	skip_cooldown_timer = skip_cooldown_duration
	
	# 使用专门的跳过逻辑
	_skip_current_mission()

# 公共接口：添加自定义任务
func add_custom_mission(type: MissionType, target: float, description: String, reward: String = "") -> void:
	"""添加自定义任务到队列"""
	var new_mission = Mission.new(type, target, description, reward)
	mission_queue.append(new_mission)
	print("[MISSION] Added custom mission: %s" % description)

# 公共接口：获取当前任务信息
func get_current_mission_info() -> Dictionary:
	"""获取当前任务信息"""
	if not current_mission:
		return {}
	
	return {
		"type": current_mission.type,
		"description": current_mission.description,
		"current": current_mission.current_value,
		"target": current_mission.target_value,
		"progress": (current_mission.current_value / current_mission.target_value) * 100.0,
		"completed": current_mission.is_completed,
		"mission_index": mission_index + 1,
		"total_missions": mission_queue.size()
	}

# 公共接口：获取所有任务信息
func get_all_missions_info() -> Array:
	"""获取所有任务信息"""
	var missions_info = []
	for i in range(mission_queue.size()):
		var mission = mission_queue[i]
		missions_info.append({
			"index": i + 1,
			"type": mission.type,
			"description": mission.description,
			"target": mission.target_value,
			"completed": mission.is_completed,
			"is_current": (i == mission_index)
		})
	return missions_info

# 公共接口：强制完成当前任务（调试用）
func force_complete_current_mission() -> void:
	"""强制完成当前任务（仅用于调试和测试）"""
	if current_mission and not current_mission.is_completed:
		current_mission.current_value = current_mission.target_value
		_complete_current_mission()

# 公共接口：重置任务系统
func reset_mission_system() -> void:
	"""重置任务系统到初始状态"""
	mission_index = 0
	current_mission = null
	mission_queue.clear()
	skip_cooldown_timer = 0.0
	is_skipping_mission = false
	max_creature_size_ever = 0.0
	completed_missions_count = 0
	_initialize_missions()
	_start_next_mission()
	print("[MISSION] Mission system reset")

# 公共接口：设置跳过冷却时间
func set_skip_cooldown_duration(duration: float) -> void:
	"""设置跳过按钮的冷却时间"""
	skip_cooldown_duration = max(0.0, duration)

# 公共接口：检查是否可以跳过
func can_skip_mission() -> bool:
	"""检查当前是否可以跳过任务"""
	return skip_cooldown_timer <= 0.0 and current_mission != null

# 公共接口：获取跳过冷却剩余时间
func get_skip_cooldown_remaining() -> float:
	"""获取跳过冷却剩余时间"""
	return max(0.0, skip_cooldown_timer)

# 公共接口：获取完成任务总数
func get_completed_missions_count() -> int:
	"""获取已完成的任务总数"""
	return completed_missions_count
