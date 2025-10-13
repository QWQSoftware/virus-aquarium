extends Control
class_name MissionSystem

# UI元素引用
var mission_label : RichTextLabel

# 游戏节点引用（用于获取游戏状态）
var game_node: Node3D = null

# 任务类型枚举
enum MissionType {
	TOTAL_POPULATION,    # 总生物数量达到目标
	MAX_CREATURE_SIZE,   # 最大生物体型达到目标
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
	
	print("[MISSION] Mission label found: ", mission_label != null)
	
	# 获取游戏节点引用
	game_node = get_parent()
	
	_initialize_missions()
	_start_next_mission()

# ========== UI 动画：缓入与缓出（参考 ui/init_hints.gd） ==========
# 说明：这些方法不改变现有任务流程，仅提供可复用的渐入/渐出动画接口。

func _start_fade_in_delayed(delay: float = 0.0, duration: float = 1.0) -> void:
	"""在 delay 秒后开始淡入（对整个 MissionSystem 控件生效）"""
	if delay > 0.0:
		var delay_timer = get_tree().create_timer(delay)
		delay_timer.timeout.connect(func(): _fade_in(duration))
	else:
		_fade_in(duration)

func _fade_in(duration: float = 1.0) -> void:
	"""淡入 Mission 面板（将 alpha 从 0 -> 1）"""
	print("[MISSION_UI] Starting fade-in animation (duration=", duration, ")")
	visible = true
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, duration)
	tween.tween_callback(func():
		print("[MISSION_UI] Fade-in complete")
	)

func _fade_out(duration: float = 0.5, hide_on_complete: bool = false) -> void:
	"""淡出 Mission 面板（将 alpha 从 1 -> 0）。hide_on_complete 为 true 时结束后隐藏。"""
	print("[MISSION_UI] Starting fade-out animation (duration=", duration, ", hide=", hide_on_complete, ")")
	modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, duration)
	tween.tween_callback(func():
		if hide_on_complete:
			visible = false
		print("[MISSION_UI] Fade-out complete")
	)

# ========== 声音播放辅助 ==========
# 说明：按给定节点名列表优先顺序，找到第一个存在且支持 play() 的节点并播放
func _play_first_available_sound(node_names: Array) -> void:
	for n in node_names:
		var node = get_node_or_null(n)
		if node and node.has_method("play"):
			node.play()
			return

func _process(delta: float) -> void:
	# 更新跳过按钮冷却
	if skip_cooldown_timer > 0.0:
		skip_cooldown_timer -= delta
	
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
		MissionType.TOTAL_POPULATION:
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
	var target = adjusted_base * multiplier
	
	# 限制“总生物数量”类任务的目标小于100
	if type == MissionType.TOTAL_POPULATION:
		target = min(target, 99.0)
	return target

func _get_current_value_for_type(type: MissionType) -> float:
	"""获取指定任务类型的当前值"""
	match type:
		MissionType.TOTAL_POPULATION:
			return float(Creature.creatures.size())
		MissionType.MAX_CREATURE_SIZE:
			return _get_current_max_creature_size()
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
	display_text += "MISSION %d | FINISHED: %d\n" % [mission_index + 1, completed_missions_count]
	display_text += "%s\n\n" % current_mission.description
	display_text += "Progress: %.1f / %.1f\n" % [current_mission.current_value, current_mission.target_value]
	display_text += "%s\n" % progress_bar
	display_text += "%.1f%% Complete\n\n" % progress_percent
	
	# 添加分隔线（ASCII）
	display_text += "---------------------\n"
	
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
			bar += "#"  # ASCII filled
		else:
			bar += "-"  # ASCII empty
	bar += "]"
	
	return bar

func _get_game_status_text() -> String:
	"""获取游戏状态文本"""
	if not game_node:
		return "Game status unavailable"
	
	var status_text = "CURRENT STATUS\n"
	
	# 获取游戏状态数据
	var creature_count = 0
	var _plant_count = 0
	var max_size = 0.0
	var avg_size = 0.0
	
	if game_node.has_method("get_current_creature_count"):
		creature_count = game_node.get_current_creature_count()
	
	if game_node.has_method("get_current_plant_count"):
		_plant_count = game_node.get_current_plant_count()
	
	if game_node.has_method("get_current_max_creature_size"):
		max_size = game_node.get_current_max_creature_size()
	
	if game_node.has_method("get_current_average_creature_size"):
		avg_size = game_node.get_current_average_creature_size()
	
	status_text += "Creatures: %d\n" % creature_count
	# status_text += "Viruses: %d\n" % plant_count
	status_text += "Max Size: %.2fm\n" % max_size
	status_text += "Avg Size: %.2fm" % avg_size
	
	return status_text

func _complete_current_mission() -> void:
	"""完成当前任务"""
	if not current_mission:
		return
		
	current_mission.is_completed = true
	completed_missions_count += 1
	print("[MISSION] Mission completed: %s (Total: %d)" % [current_mission.description, completed_missions_count])

	# 播放完成音效（若存在专用 CompleteAudioStreamPlayer 则优先，否则回退）
	_play_first_available_sound(["CompleteAudioStreamPlayer", "AudioStreamPlayer"])

	# 显示完成信息
	var completion_text = ""
	completion_text += "MISSION COMPLETE!\n\n"
	completion_text += "Accomplished: %s\n\n" % current_mission.description
	completion_text += "Reward: %s" % current_mission.reward_text

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
	skip_text += "MISSION SKIPPED\n\n"
	skip_text += "Skipped: %s\n" % current_mission.description
	skip_text += "Reason: User pressed ESC\n\n"
	skip_text += "Loading next mission..."
	
	mission_label.text = skip_text
	
	# 1.5秒后开始下一个任务，给用户足够时间看到跳过信息
	await get_tree().create_timer(1.5).timeout
	mission_index += 1
	is_skipping_mission = false
	_start_next_mission()

func _handle_skip_input() -> void:
	"""处理Ctrl键跳过任务"""
	print("[MISSION] ESC key pressed for skip!")
	print("[MISSION] Current cooldown timer: %.1f" % skip_cooldown_timer)
	print("[MISSION] Current mission exists: ", current_mission != null)
	if current_mission:
		print("[MISSION] Current mission: %s" % current_mission.description)
		print("[MISSION] Mission completed: %s" % current_mission.is_completed)
	print("[MISSION] Is skipping mission: %s" % is_skipping_mission)
	
	if skip_cooldown_timer > 0.0:
		print("[MISSION] Skip is on cooldown: %.1fs remaining" % skip_cooldown_timer)
		return  # 还在冷却中
	
	if not current_mission or current_mission.is_completed:
		print("[MISSION] No current mission to skip or mission already completed")
		return
	
	if is_skipping_mission:
		print("[MISSION] Already skipping a mission")
		return
	
	print("[MISSION] Proceeding with mission skip...")
	
	# 播放音效
	_play_first_available_sound(["SkipAudioStreamPlayer", "AudioStreamPlayer"])
	
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

# 公共接口：请求跳过当前任务（供外部如 game.gd 调用）
func skip_current_mission() -> void:
	"""触发与 ESC 相同的跳过逻辑，带冷却与并发保护"""
	_handle_skip_input()
