extends RefCounted

class_name Creature

static var sound_effects : SoundEffects = null

# 决策枚举（基于 doc_creature_logic.md）
enum Decision {
	NONE,               # 无决策/空闲
	REPRODUCE,          # 繁殖（包含寻找配偶）
	PLANT_REPRODUCE,    # 植物专用繁殖（在附着点/附近产生后代）
	SELF_REPLICATE,     # 自我复制
	REST,               # 休息（寻找并附着到休息点）
	EAT,                # 觅食/攻击并进食
	FLEE,               # 逃跑（避开威胁）
	GROUP_FLEE,         # 群体避害（跟随/保持与群体移动）
	FOLLOW,             # 跟随（追随特定表面或个体）
	ATTACH,             # 附着到某个表面点
	IDLE                # 待机
}

# 1m的交互范围，例如攻击，进食，交配
const interact_range_m: float = 10.0

# 一些共享的世界参数，用来帮助生物读取世界环境信息
static var world_surface_points: Array[Vector3] = []
static var world_surface_normals: Array[Vector3] = []
static var world_surface_types: Array[int] = []
static var world_surface_light_levels: Array[int] = []
static var world_surface_point_is_attached: Array[bool] = []

# 全局光照输入向量（表示光线传播方向，不是指向光源）
# 默认设置：从东南方向45度角照射（模拟下午阳光）
static var world_light_direction: Vector3 = Vector3(0.5, -0.707, 0.5).normalized()

# 所有生物的世界坐标
static var creatures_world_positions: Array[Vector3] = []
# 所有生物的大小
static var creatures_sizes: Array[float] = []
# 所有生物的颜色（HSL）
static var creatures_colors: Array[Color] = []
static var creatures_is_plants: Array[bool] = []

static var creatures : Array = []
static var surface_octree = null
static var creatures_octree = null

# 植物数量控制
static var max_plant_population: int = 100  # 最大植物数量
static var current_plant_count: int = 0    # 当前植物数量

static func rebuild_surface_octree(max_points_per_node: int = 12, max_depth: int = 8) -> void:
	# Build/rebuild octree for world_surface_points
	var OctreeClass = preload("res://utils/octree.gd")
	if surface_octree == null:
		surface_octree = OctreeClass.new()
	if world_surface_points.size() == 0:
		surface_octree.root = null
		return
	surface_octree.build_from_points(world_surface_points, max_points_per_node, max_depth)

static func rebuild_creatures_octree(max_points_per_node: int = 12, max_depth: int = 8) -> void:
	# Build/rebuild octree that indexes creature positions (aligned with Creature.creatures array)
	var OctreeClass = preload("res://utils/octree.gd")
	if creatures_octree == null:
		creatures_octree = OctreeClass.new()
	var pos_arr: Array = []
	for c in creatures:
		if c == null:
			pos_arr.append(Vector3())
		else:
			pos_arr.append(c.position)
	if pos_arr.size() == 0:
		creatures_octree.root = null
		return
	creatures_octree.build_from_points(pos_arr, max_points_per_node, max_depth)

# Plant population control functions
static func set_max_plant_population(limit: int) -> void:
	max_plant_population = max(1, limit)

static func get_max_plant_population() -> int:
	return max_plant_population

static func get_current_plant_count() -> int:
	return current_plant_count

static func recalculate_plant_count() -> void:
	# 重新计算植物数量，防止数据不一致
	current_plant_count = 0
	for c in creatures:
		if c != null and c.is_plant:
			current_plant_count += 1

# Light direction control functions
static func set_world_light_direction(direction: Vector3) -> void:
	# 设置全局光照方向向量（会自动归一化）
	world_light_direction = direction.normalized()

static func get_world_light_direction() -> Vector3:
	# 获取当前全局光照方向向量
	return world_light_direction

static func set_world_light_from_angles(azimuth_deg: float, elevation_deg: float) -> void:
	# 通过方位角和仰角设置光照方向
	# azimuth_deg: 方位角（度）, 0度为北，90度为东
	# elevation_deg: 仰角（度），0度为水平，90度为垂直向上，-90度为垂直向下
	var azimuth_rad = deg_to_rad(azimuth_deg)
	var elevation_rad = deg_to_rad(elevation_deg)
	
	var x = cos(elevation_rad) * sin(azimuth_rad)
	var y = -sin(elevation_rad)  # Godot中Y轴向上为正，所以光照向下为负
	var z = cos(elevation_rad) * cos(azimuth_rad)
	
	world_light_direction = Vector3(x, y, z).normalized()

static func calculate_surface_light_intensity(surface_normal: Vector3) -> float:
	# 使用朗伯余弦定律计算表面接收到的光照强度
	# surface_normal: 表面法向量（应该已经归一化）
	# world_light_direction: 光照方向（指向光源的相反方向）
	# 返回值范围 [0.0, 1.0]，0为完全背光，1为完全正对光源
	
	# 确保向量归一化
	var normal = surface_normal.normalized()
	var light_dir = world_light_direction.normalized()
	
	# 计算法线与光照方向的点积（余弦值）
	# 负号是因为 world_light_direction 指向的是光线传播方向，而不是指向光源
	var cos_angle = -normal.dot(light_dir)
	
	# 只有面向光源的表面才能接收到光照（余弦值大于0）
	return max(0.0, cos_angle)

# 辅助函数：获取当前全局光照的有效强度
static func get_global_light_intensity() -> float:
	# 基于光照方向计算全局光照强度
	# 这可以用来模拟环境光照的强弱，但不影响具体表面的光照计算
	# 返回值范围 [0.0, 1.0]
	return world_light_direction.length()

# 预设光照条件的便利函数
static func set_sunlight_overhead() -> void:
	# 设置正午阳光（垂直向下）
	world_light_direction = Vector3(0.0, -1.0, 0.0)

static func set_sunlight_angle(angle_from_vertical_deg: float, azimuth_deg: float = 0.0) -> void:
	# 设置指定角度的阳光
	# angle_from_vertical_deg: 与垂直方向的夹角（0度=垂直向下, 90度=水平）
	# azimuth_deg: 方位角（0度=北方, 90度=东方）
	set_world_light_from_angles(azimuth_deg, 90.0 - angle_from_vertical_deg)

static func set_no_light() -> void:
	# 关闭光照（夜晚状态）
	world_light_direction = Vector3.ZERO

# 验证并修复附着点状态不一致问题
static func validate_and_fix_attachment_state() -> void:
	# 重置所有附着点状态
	for i in range(world_surface_point_is_attached.size()):
		world_surface_point_is_attached[i] = false
	
	# 重新标记所有活着的生物占用的附着点
	for c in creatures:
		if c == null or not c.is_alive:
			continue
			
		# 标记当前附着点
		if c.now_attached_id >= 0 and c.now_attached_id < world_surface_point_is_attached.size():
			world_surface_point_is_attached[c.now_attached_id] = true
		
		# 标记附着列表中的点
		for pid in c.attachments:
			if typeof(pid) == TYPE_INT and pid >= 0 and pid < world_surface_point_is_attached.size():
				world_surface_point_is_attached[pid] = true
		
		# 标记繁殖预占的点（仅对正在繁殖的生物）
		if c.is_reproducing:
			for pid in c._plant_repro_found_points:
				if typeof(pid) == TYPE_INT and pid >= 0 and pid < world_surface_point_is_attached.size():
					world_surface_point_is_attached[pid] = true

# 清理无效的繁殖状态
static func cleanup_invalid_reproduction_states() -> void:
	for c in creatures:
		if c == null or not c.is_alive:
			continue
		
		# 检查繁殖状态的配偶是否仍然有效
		if c.is_reproducing and c._plant_repro_mode == 1:  # 配对繁殖模式
			var mate_valid = false
			if c._plant_repro_mate_idx >= 0 and c._plant_repro_mate_idx < creatures.size():
				var mate = creatures[c._plant_repro_mate_idx]
				if mate != null and mate.is_alive and mate.is_reproducing:
					mate_valid = true
			
			# 如果配偶无效，清理繁殖状态并释放预占点
			if not mate_valid:
				print("[CLEANUP] Invalid mate found for creature %d, cleaning reproduction state" % c.index)
				for pid in c._plant_repro_found_points:
					if typeof(pid) == TYPE_INT and pid >= 0 and pid < world_surface_point_is_attached.size():
						world_surface_point_is_attached[pid] = false
				c.is_reproducing = false
				c._plant_repro_mode = 0
				c._plant_repro_mate_idx = -1
				c._plant_repro_found_points.clear()
				c.progress = 0.0

# Debugging: print per-creature update details when enabled. Set DEBUG_FILTER_INDEX >=0 to only print that index.
static var DEBUG_PRINT_UPDATES: bool = false
static var DEBUG_FILTER_INDEX: int = -1

const REPRO_COLOR_MATING: Color = Color(1.0, 0.0, 0.0, 1.0) # red for mating
const REPRO_COLOR_SELFREPLICATE: Color = Color(0.0, 1.0, 0.0, 1.0) # green for self-replication


# --- 显式成员声明（避免在 RefCounted 上动态创建属性导致的错误）
var index: int = -1  # 在 creatures_world_positions 等静态数组中的索引

var now_attached_id : int = -1  # 当前附着点ID，-1表示未附着

var genome: Array = []
var phenotype: Dictionary = {}

# lifecycle / runtime
var age_s: float = 0.0
var is_alive: bool = true
var position: Vector3 = Vector3.ZERO
var global_transform: Transform3D = Transform3D()
var attachments: Array = []
# 保存实例化时的原始颜色，用于在繁殖结束后恢复
var _original_color: Color = Color(1.0, 1.0, 1.0, 1.0)

# current resources / state
var health_p: float = 0.0
var energy_p: float = 0.0
var stamina_p: float = 0.0

# --- phenotype-derived (硬编码字段，来自 GenomeUtils.decode_genome)
# lifespan / reproduction
var max_lifespan_s: float = 100.0
var adult_age_s: float = 0.0
var fertility_end_s: float = 1e9

# movement / activation
var general_move_speed_m_per_s: float = 0.2
var general_rot_speed_rad_s: float = 0.1
var active_move_speed_m_per_s: float = 1.0
var active_rot_speed_rad_s: float = 0.5
var activation_duration_s: float = 1.0
var activation_energy_cost_p: float = 0.0
var activation_cooldown_s: float = 0.0

# mating / reproduction
var mating_duration_s: float = 1.0
var mating_cooldown_s: float = 0.0
var mating_attachment_pref_type: int = 0
var mating_light_pref_unitless: float = 0.5
var mating_required_energy_p: float = 0.0
var mating_energy_cost_p: float = 0.0
var offspring_count: int = 0

# self-replication
var selfrep_cooldown_s: float = 0.0
var selfrep_required_energy_p: float = 0.0
var selfrep_energy_cost_p: float = 0.0
var selfrep_time_s: float = 0.1

# size / growth
var initial_size_m: float = 0.1
var size_k: float = 1.0

# predation / attack
var initial_attack_p: float = 0.0
var adult_attack_p: float = 1.0
var attack_k: float = 1.0
var attack_cd_s: float = 1.0

# energy
var max_energy_init_p: float = 10.0
var max_energy_adult_p: float = 100.0
var energy_k: float = 1.0

# consumption
var consumption_init_p_per_s: float = 0.1
var consumption_adult_p_per_s: float = 0.6
var consumption_k: float = 1.0

# photosynthesis / food
var photosynthesis_rate_p_per_s: float = 0.0
var as_food_energy_p: float = 10.0
var eating_time_s: float = 0.5
var eating_desire_k: float = 1.0

# health
var health_init_p: float = 10.0
var health_adult_p: float = 50.0
var health_k: float = 1.0
var health_recover_init_p_per_s: float = 0.5
var health_recover_adult_p_per_s: float = 2.0
var health_recover_k: float = 1.0

# surface / attachment
var surface_attachment_types_count: int = 0
var surface_attachment_count: int = 0
var surface_attachment_max_accum: int = 1

# stamina / rest
var stamina_max_p: float = 0.0
var rest_recover_speed_p_per_s: float = 1.0
var rest_pref_attachment_type: int = 0

# reconnaissance / appearance
var color_h_unitless: float = 0.0
var initial_insight_p: float = 1.0
var adult_insight_p: float = 1.0
var view_range_init_m: float = 20.0
var view_range_adult_m: float = 60.0
var view_range_k: float = 1.0

# decoration
var decor_scale_x: float = 0.5
var decor_scale_z: float = 0.5

# plant flag
var is_plant: bool = false

# decision weight exponents (来自 doc: k in [0,3])
var decision_k_reproduce: float = 1.0
var decision_k_rest: float = 1.0
var decision_k_eat: float = 1.0

# 数据驱动的 Creature 类（从 game.gd 抽离）
func _init(genome_in: Array, transform: Transform3D) -> void:
	# 设置index
	self.index = creatures_world_positions.size()

	self.now_attached_id = -1

	creatures_world_positions.append(transform.origin)


	# 把传入的基因数组复制到实例字段（避免外部修改影响）
	self.genome = genome_in.duplicate()
	# phenotype 是 decode 后的物理/行为参数字典
	self.phenotype = GenomeUtils.decode_genome(self.genome)
	# 硬编码把 phenotype 的关键字段设为实例属性（便于静态检查与可读性）
	self.max_lifespan_s = self.phenotype.get("max_lifespan_s", 100.0)
	self.adult_age_s = self.phenotype.get("adult_age_s", 0.0)
	self.fertility_end_s = self.phenotype.get("fertility_end_s", 1e9)

	# movement / activation
	self.general_move_speed_m_per_s = self.phenotype.get("general_move_speed_m_per_s", 0.2)
	self.general_rot_speed_rad_s = self.phenotype.get("general_rot_speed_rad_s", 0.1)
	self.active_move_speed_m_per_s = self.phenotype.get("active_move_speed_m_per_s", 1.0)
	self.active_rot_speed_rad_s = self.phenotype.get("active_rot_speed_rad_s", 0.5)
	self.activation_duration_s = self.phenotype.get("activation_duration_s", 1.0)
	self.activation_energy_cost_p = self.phenotype.get("activation_energy_cost_p", 0.0)
	self.activation_cooldown_s = self.phenotype.get("activation_cooldown_s", 0.0)

	# mating / reproduction
	self.mating_duration_s = self.phenotype.get("mating_duration_s", 1.0)
	self.mating_cooldown_s = self.phenotype.get("mating_cooldown_s", 0.0)
	self.mating_attachment_pref_type = self.phenotype.get("mating_attachment_pref_type", 0)
	self.mating_light_pref_unitless = self.phenotype.get("mating_light_pref_unitless", 0.5)
	# 能量值可以由 phenotype 提供两种形式：绝对值（*_p）或相对成年最大能量的比例（*_frac）
	# 优先使用 *_frac（若存在），否则回退到 *_p
	self.mating_required_energy_p = 0.0
	self.mating_energy_cost_p = 0.0
	var m_req_frac = self.phenotype.get("mating_required_energy_frac", null)
	var m_cost_frac = self.phenotype.get("mating_energy_cost_frac", null)
	if m_req_frac != null:
		self.mating_required_energy_p = float(m_req_frac) * self.phenotype.get("max_energy_adult_p", self.max_energy_adult_p)
	else:
		self.mating_required_energy_p = self.phenotype.get("mating_required_energy_p", 0.0)
	if m_cost_frac != null:
		self.mating_energy_cost_p = float(m_cost_frac) * self.phenotype.get("max_energy_adult_p", self.max_energy_adult_p)
	else:
		self.mating_energy_cost_p = self.phenotype.get("mating_energy_cost_p", 0.0)
	# 确保消耗不超过要求
	self.mating_energy_cost_p = min(max(0.0, self.mating_energy_cost_p), max(0.0, self.mating_required_energy_p))
	self.offspring_count = self.phenotype.get("offspring_count", 0)

	# self-replication
	self.selfrep_cooldown_s = self.phenotype.get("selfrep_cooldown_s", 0.0)
	# 同样处理自复制能量字段
	self.selfrep_required_energy_p = 0.0
	self.selfrep_energy_cost_p = 0.0
	var sr_req_frac = self.phenotype.get("selfrep_required_energy_frac", null)
	var sr_cost_frac = self.phenotype.get("selfrep_energy_cost_frac", null)
	if sr_req_frac != null:
		self.selfrep_required_energy_p = float(sr_req_frac) * self.phenotype.get("max_energy_adult_p", self.max_energy_adult_p)
	else:
		self.selfrep_required_energy_p = self.phenotype.get("selfrep_required_energy_p", 0.0)
	if sr_cost_frac != null:
		self.selfrep_energy_cost_p = float(sr_cost_frac) * self.phenotype.get("max_energy_adult_p", self.max_energy_adult_p)
	else:
		self.selfrep_energy_cost_p = self.phenotype.get("selfrep_energy_cost_p", 0.0)
	# 确保自复制消耗不超过所需能量
	self.selfrep_energy_cost_p = min(max(0.0, self.selfrep_energy_cost_p), max(0.0, self.selfrep_required_energy_p))
	self.selfrep_time_s = self.phenotype.get("selfrep_time_s", 0.1)

	# size / growth
	self.initial_size_m = self.phenotype.get("initial_size_m", 0.1)
	self.size_k = self.phenotype.get("size_k", 1.0)

	# predation / attack
	self.initial_attack_p = self.phenotype.get("initial_attack_p", 0.0)
	self.adult_attack_p = self.phenotype.get("adult_attack_p", 1.0)
	self.attack_k = self.phenotype.get("attack_k", 1.0)
	self.attack_cd_s = self.phenotype.get("attack_cd_s", 1.0)

	# energy
	self.max_energy_init_p = self.phenotype.get("max_energy_init_p", 10.0)
	self.max_energy_adult_p = self.phenotype.get("max_energy_adult_p", 100.0)
	self.energy_k = self.phenotype.get("energy_k", 1.0)

	# consumption
	self.consumption_init_p_per_s = self.phenotype.get("consumption_init_p_per_s", 0.1)
	self.consumption_adult_p_per_s = self.phenotype.get("consumption_adult_p_per_s", 0.6)
	self.consumption_k = self.phenotype.get("consumption_k", 1.0)

	# photosynthesis / food
	self.photosynthesis_rate_p_per_s = self.phenotype.get("photosynthesis_rate_p_per_s", 0.0)
	self.as_food_energy_p = self.phenotype.get("as_food_energy_p", 10.0)
	self.eating_time_s = self.phenotype.get("eating_time_s", 0.5)
	self.eating_desire_k = self.phenotype.get("eating_desire_k", 1.0)

	# health
	self.health_init_p = self.phenotype.get("health_init_p", 10.0)
	self.health_adult_p = self.phenotype.get("health_adult_p", 50.0)
	self.health_k = self.phenotype.get("health_k", 1.0)
	self.health_recover_init_p_per_s = self.phenotype.get("health_recover_init_p_per_s", 0.5)
	self.health_recover_adult_p_per_s = self.phenotype.get("health_recover_adult_p_per_s", 2.0)
	self.health_recover_k = self.phenotype.get("health_recover_k", 1.0)

	# surface / attachment
	self.surface_attachment_types_count = self.phenotype.get("surface_attachment_types_count", 0)
	self.surface_attachment_count = self.phenotype.get("surface_attachment_count", 0)
	self.surface_attachment_max_accum = self.phenotype.get("surface_attachment_max_accum", 1)

	# stamina / rest
	self.stamina_max_p = self.phenotype.get("stamina_max_p", 0.0)
	self.rest_recover_speed_p_per_s = self.phenotype.get("rest_recover_speed_p_per_s", 1.0)
	self.rest_pref_attachment_type = self.phenotype.get("rest_pref_attachment_type", 0)

	# reconnaissance / appearance
	self.color_h_unitless = self.phenotype.get("color_h_unitless", 0.0)
	self.initial_insight_p = self.phenotype.get("initial_insight_p", 1.0)
	self.adult_insight_p = self.phenotype.get("adult_insight_p", 1.0)
	self.view_range_init_m = self.phenotype.get("view_range_init_m", 20.0)
	self.view_range_adult_m = self.phenotype.get("view_range_adult_m", 60.0)
	self.view_range_k = self.phenotype.get("view_range_k", 1.0)

	# decoration
	self.decor_scale_x = self.phenotype.get("decor_scale_x", 0.5)
	self.decor_scale_z = self.phenotype.get("decor_scale_z", 0.5)
	# decision ks
	self.decision_k_reproduce = self.phenotype.get("decision_k_reproduce", 1.0)
	self.decision_k_rest = self.phenotype.get("decision_k_rest", 1.0)
	self.decision_k_eat = self.phenotype.get("decision_k_eat", 1.0)
	self.age_s = 0.0
	self.is_alive = true
	# 初始资源/状态（使用 phenotype 提供的范围作为参考）
	# 现在可以直接读取为实例属性（decode_genome 会填充默认值）
	self.health_p = self.health_init_p
	self.energy_p = self.max_energy_init_p
	self.stamina_p = self.stamina_max_p
	self.global_transform = transform
	# 计算是否为植物（无精力且有光合作用能力）
	self.is_plant = (self.stamina_p <= 0.0 and self.photosynthesis_rate_p_per_s > 0.0)
	creatures_is_plants.append(self.is_plant)
	
	# 更新植物计数
	if self.is_plant:
		current_plant_count += 1

	self.attachments = []


	creatures_sizes.append(initial_size_m)
	creatures_colors.append(Color.from_hsv(color_h_unitless, 1.0, 1.0))
	# cache original color so it can be restored after reproduction
	if self.index >= 0 and self.index < creatures_colors.size():
		self._original_color = creatures_colors[self.index]

	creatures.append(self)

	if DEBUG_PRINT_UPDATES:
		print("[CREATURE] created index=%d pos=%s is_plant=%s" % [self.index, str(self.position), str(self.is_plant)])

	sound_effects.play_random_sound()

# 销毁时从静态数组中移除自己
func dispose() -> void:
	if self.index >= 0 and self.index < creatures_world_positions.size():
		creatures_world_positions.remove_at(self.index)
		creatures_sizes.remove_at(self.index)
		creatures_colors.remove_at(self.index)
		for i in range(self.index, creatures.size()):
			var c = creatures[i]
			if c and c.index > self.index:
				c.index -= 1
		self.index = -1
	if self in creatures:
		creatures.erase(self)
	# 更新植物计数
	if self.is_plant:
		current_plant_count = max(0, current_plant_count - 1)
	# 释放任何被占用的世界表面点
	var released_points: Array = []
	
	# 释放当前附着点
	if self.now_attached_id >= 0 and self.now_attached_id < world_surface_point_is_attached.size():
		world_surface_point_is_attached[self.now_attached_id] = false
		released_points.append(self.now_attached_id)
	
	# 释放 attachments 列表中的点（避免与当前附着点重复）
	for pid in self.attachments:
		if typeof(pid) == TYPE_INT and pid >= 0 and pid < world_surface_point_is_attached.size():
			if pid != self.now_attached_id:  # 避免重复释放
				world_surface_point_is_attached[pid] = false
				released_points.append(pid)
	
	# 释放繁殖过程中预占的附着点（避免与已释放的点重复）
	for pid in self._plant_repro_found_points:
		if typeof(pid) == TYPE_INT and pid >= 0 and pid < world_surface_point_is_attached.size():
			if not released_points.has(pid):  # 避免重复释放
				world_surface_point_is_attached[pid] = false
				released_points.append(pid)
	
	if released_points.size() > 0:
		print("[DISPOSE] Creature %d released %d attachment points: %s" % [index, released_points.size(), str(released_points)])
	self.genome.clear()
	self.phenotype.clear()
	self.attachments.clear()
	self._plant_repro_found_points.clear()


static func cleanup_dead() -> void:
	# 倒序遍历 creatures 列表并释放已死亡的个体，倒序可以安全地在迭代中移除元素
	for i in range(creatures.size() - 1, -1, -1):
		var c = creatures[i]
		if c == null:
			continue
		if not c.is_alive:
			c.dispose()


func attach_to_surface_point(point_id: int) -> void:
	# Validate point id
	if point_id < 0 or point_id >= world_surface_points.size():
		print("[ATTACH] Invalid point_id %d (world_surface_points.size=%d)" % [point_id, world_surface_points.size()])
		return

	# Check if point is already occupied by another creature
	if point_id < world_surface_point_is_attached.size() and world_surface_point_is_attached[point_id]:
		print("[ATTACH] Point %d already occupied, forcing attachment anyway" % point_id)
		# 在调试模式下，我们仍然继续，但记录这个问题
	
	# Detach from previous point if any
	if self.now_attached_id >= 0 and self.now_attached_id < world_surface_point_is_attached.size():
		world_surface_point_is_attached[self.now_attached_id] = false

	# Attach: set position and mark point as attached
	self.now_attached_id = point_id
	self.position = world_surface_points[point_id]
	self.global_transform.origin = self.position
	if point_id < world_surface_point_is_attached.size():
		world_surface_point_is_attached[point_id] = true
	
	# Note: attachments 列表用于记录生物可以附着到的其他生物，
	# 不应该包含当前附着的表面点，避免在 dispose() 时重复释放
	if not self.attachments:
		self.attachments = []


# 年龄上下文
# 处理生物的年龄增长和寿命终结并计算当前大小

var current_size_m : float = 0.0

func update_age(delta: float) -> void:
	self.age_s += delta
	if self.age_s >= self.max_lifespan_s:
		self.is_alive = false

	# 使用 log_k(age+1) 的曲线来生成大小增长，其中 k 范围由基因映射至 2..100
	# current_size_m = initial_size_m + log_k(age+1) * size_growth_scale
	var k: float = max(2.0, float(self.size_k))
	var scale: float = self.phenotype.get("size_growth_scale", 0.1)
	# age + 1 避免对数 singularity，在 age_s 很小时 log_k(1) = 0，保证初始大小为 initial_size_m
	var age_term: float = max(0.0, float(self.age_s))
	# 对数换底： log_k(x) = ln(x) / ln(k)
	var logk: float = 0.0
	if age_term > 0.0:
		logk = log(age_term + 1.0) / max(0.0001, log(k))
	self.current_size_m = self.initial_size_m + logk * scale


# 光合作用基于实际光照强度计算
func update_photosynthesis(_delta: float) -> void:
	if self.photosynthesis_rate_p_per_s <= 0.0:
		return
	if self.energy_p >= self.max_energy_adult_p:
		self.energy_p = self.max_energy_adult_p
		return
		
	# 获取当前位置的实际光照强度（基于表面法线与光照方向的几何关系）
	var light_intensity = get_current_light_intensity()
	
	# 计算基础光合作用能量产出
	var base_photosynthesis = self.photosynthesis_rate_p_per_s * _delta
	
	# 应用光照影响和植物加成
	var energy_gain: float
	if self.is_plant:
		# 植物光合作用：基础速率 * 植物加成(10倍) * 光照强度
		energy_gain = base_photosynthesis * 10.0 * light_intensity
	else:
		# 非植物的光合作用（如蓝藻细菌）：基础速率 * 光照强度
		energy_gain = base_photosynthesis * light_intensity
	
	# 应用能量增益
	var old_energy = self.energy_p
	self.energy_p += energy_gain
	self.energy_p = min(self.energy_p, self.max_energy_adult_p)
	
	# 调试输出光合作用详情
	if DEBUG_PRINT_UPDATES and (DEBUG_FILTER_INDEX < 0 or DEBUG_FILTER_INDEX == self.index):
		if energy_gain > 0.001:  # 只显示有意义的能量增益
			print("[PHOTOSYNTHESIS] Creature %d: light=%.3f, base_rate=%.3f, gain=%.3f, energy: %.3f->%.3f" % [
				self.index, 
				light_intensity, 
				self.photosynthesis_rate_p_per_s,
				energy_gain, 
				old_energy, 
				self.energy_p
			])
	return

# 获取当前生物位置的光照强度
func get_current_light_intensity() -> float:
	var surface_normal: Vector3
	
	# 如果生物附着在表面点上，使用该点的法线计算光照强度
	if self.now_attached_id >= 0 and self.now_attached_id < world_surface_normals.size():
		surface_normal = world_surface_normals[self.now_attached_id]
		
		# 验证法线向量的有效性
		if surface_normal.length_squared() < 0.1:
			# 法线向量无效，使用默认向上方向
			surface_normal = Vector3.UP
			if DEBUG_PRINT_UPDATES and (DEBUG_FILTER_INDEX < 0 or DEBUG_FILTER_INDEX == self.index):
				print("[LIGHT] Invalid surface normal at point %d, using default UP" % self.now_attached_id)
	else:
		# 如果没有附着，假设表面向上（默认情况）
		surface_normal = Vector3.UP
		if DEBUG_PRINT_UPDATES and (DEBUG_FILTER_INDEX < 0 or DEBUG_FILTER_INDEX == self.index):
			print("[LIGHT] Creature %d not attached, using default UP normal" % self.index)
	
	var light_intensity = calculate_surface_light_intensity(surface_normal)
	
	# 调试输出光照计算详情
	if DEBUG_PRINT_UPDATES and (DEBUG_FILTER_INDEX < 0 or DEBUG_FILTER_INDEX == self.index):
		print("[LIGHT] Creature %d: normal=%s, light_dir=%s, intensity=%.3f" % [
			self.index, 
			str(surface_normal), 
			str(world_light_direction), 
			light_intensity
		])
	
	return light_intensity

# 获取相对于当前光照的光照因子（用于光合作用等计算）
func get_light_factor() -> float:
	# 直接返回基于几何关系计算的光照强度
	# 这个值基于表面法线与光照方向的余弦值，符合朗伯余弦定律
	return get_current_light_intensity()

func update_hp(_delta: float) -> void:
	return

func update_stamina(_delta: float) -> void:
	if self.is_plant:
		return
	return

func update_energy(_delta: float) -> void:
	return



func update(delta: float) -> void:
	if not self.is_alive:
		return

	# global cooldown update (ensure cooldown always counts down)
	if cooldown_timer > 0.0:
		cooldown_timer = max(0.0, cooldown_timer - delta)
	
	self.update_age(delta)
	self.update_hp(delta)
	self.update_stamina(delta)
	self.update_energy(delta)
	self.update_photosynthesis(delta)
	self.decide_and_act(delta)

	# Debug printing of detailed state for inspection
	if DEBUG_PRINT_UPDATES and (DEBUG_FILTER_INDEX < 0 or DEBUG_FILTER_INDEX == self.index):
		var info := []
		info.append("Creature index=" + str(self.index))
		info.append("alive=" + str(self.is_alive))
		info.append("age=" + ("%.3f" % self.age_s))
		info.append("pos=" + str(self.position))
		info.append("size_m=" + ("%.4f" % self.current_size_m))
		info.append("energy=" + ("%.3f" % self.energy_p) + "/" + ("%.2f" % self.max_energy_adult_p))
		info.append("health=" + ("%.3f" % self.health_p) + "/" + ("%.2f" % self.health_adult_p))
		info.append("stamina=" + ("%.3f" % self.stamina_p) + "/" + ("%.2f" % self.stamina_max_p))
		info.append("is_plant=" + str(self.is_plant))
		info.append("repro_mode=" + str(self._plant_repro_mode) + ", is_reproducing=" + str(self.is_reproducing))
		info.append("progress=" + ("%.3f" % self.progress) + ", cooldown=" + ("%.3f" % self.cooldown_timer))
		info.append("m_req=" + ("%.3f" % self.mating_required_energy_p) + ", m_cost=" + ("%.3f" % self.mating_energy_cost_p))
		info.append("s_req=" + ("%.3f" % self.selfrep_required_energy_p) + ", s_cost=" + ("%.3f" % self.selfrep_energy_cost_p))
		info.append("offspring_count=" + str(self.offspring_count))
		info.append("light=" + ("%.3f" % get_current_light_intensity()))
		if self.is_plant:
			info.append("plant_pop=" + str(current_plant_count) + "/" + str(max_plant_population))
		print("[CREATURE-UPDATE] " + String(" | ").join(info))

func decide_and_act(delta: float) -> void:
	if not self.is_alive:
		return
	if self.is_plant:
		self.do_plant_reproduce(delta)
		return

	if self.is_reproducing:
		self.do_reproduce(delta)
		return

	var w_reproduce = self.compute_reproduce_desire()
	var w_rest = self.compute_rest_desire()
	var w_eat = self.compute_eat_desire()
	# var w_flee = self.compute_flee_desire()

	var max_w = max(w_reproduce, w_rest) #, max(w_eat, w_flee))
	if max_w == w_reproduce:
		self.do_reproduce(delta)
	elif max_w == w_rest:
		self.do_rest(delta)
	elif max_w == w_eat:
		self.do_eat(delta)
	# elif max_w == w_flee:
	# 	self.do_flee()

func compute_reproduce_desire() -> float:
	var adult_age = self.phenotype.get("adult_age_s", 0.0)
	var fertility_end = self.phenotype.get("fertility_end_s", 1e9)
	if self.age_s < adult_age or self.age_s > fertility_end:
		return 0.0
	# 检查植物总数上限（仅对植物有效）
	if self.is_plant and current_plant_count >= max_plant_population:
		return 0.0
	# 使用初始化时计算好的实例字段（可能来自绝对值或 frac 转换）
	var min_energy = self.mating_required_energy_p
	var e = self.energy_p
	if e < min_energy:
		return 0.0
	var max_e = max(1.0, self.max_energy_adult_p)
	return clamp((e - min_energy) / max(0.0001, (max_e - min_energy)), 0.0, 1.0)

func compute_rest_desire() -> float:
	var max_stam = max(1.0, self.phenotype.get("stamina_max_p", 100.0))
	return clamp(1.0 - (self.stamina_p / max_stam), 0.0, 1.0)

func compute_eat_desire() -> float:
	var max_e = max(1.0, self.phenotype.get("max_energy_adult_p", 100.0))
	return clamp(1.0 - (self.energy_p / max_e), 0.0, 1.0)

func compute_flee_desire() -> float:
	var max_hp = max(1.0, self.phenotype.get("health_adult_p", 100.0))
	return clamp(1.0 - (self.health_p / max_hp), 0.0, 1.0)


# 繁殖上下文

func can_reproduce() -> bool:
	if self.age_s < self.adult_age_s or self.age_s > self.fertility_end_s:
		return false
	# 检查植物总数上限（仅对植物有效）
	if self.is_plant and current_plant_count >= max_plant_population:
		return false
	if self.energy_p < min(self.mating_required_energy_p, self.selfrep_required_energy_p):
		return false
	return true

func reproduce_with(mate: Creature) -> void:
	if not self.can_reproduce() or not mate.can_reproduce():
		return

	# 进行交配
	self.is_reproducing = true
	mate.is_reproducing = true
	# set reproduce color for both participants (mode 1 = mating)
	self._set_repro_color(true, 1)
	if mate != null:
		mate._set_repro_color(true, 1)

# 进度 0-1
var progress : float = 0.0
# 冷却时间计算
var cooldown_timer : float = 0.0
# 是否正在繁殖
var is_reproducing : bool = false
# 植物繁殖私有状态：0=none,1=mating,2=selfrep
var _plant_repro_mode : int = 0
# 繁殖时的配偶索引（creatures 数组索引），-1 表示无
var _plant_repro_mate_idx : int = -1
# 自我复制时预占用的附着点列表（整数 id）
var _plant_repro_found_points : Array = []

func do_plant_reproduce(_delta: float) -> void:
	# 植物专用繁殖逻辑（优化版）
	# 只在成年尝试繁殖
	if age_s < adult_age_s or age_s > fertility_end_s:
		return

	# 检查植物总数上限
	if current_plant_count >= max_plant_population:
		return

	# 能量不足无法繁殖
	if energy_p < min(mating_required_energy_p, selfrep_required_energy_p):
		return

	# 检查繁殖冷却（使用 update() 全局递减，仅在冷却中直接返回）
	if cooldown_timer > 0.0:
		return

	# 本地缓存以减少全局数组访问开销
	var wsp: Array = world_surface_points
	var wsp_att: Array = world_surface_point_is_attached
	var creatures_arr: Array = creatures
	var ws_count: int = wsp.size()
	var ws_att_count: int = wsp_att.size()
	var pos_self: Vector3 = self.position
	var off_count: int = int(offspring_count)
	# cache squared radii to avoid sqrt in distance_to
	var interact_range_sq: float = interact_range_m * interact_range_m
	var selfrep_radius: float = 2.0
	var selfrep_radius_sq: float = selfrep_radius * selfrep_radius

	# 如果已经处于繁殖状态，根据当前模式推进进度并在完成时生成后代
	if is_reproducing:
		if _plant_repro_mode == 2:
			progress += _delta / max(0.0001, selfrep_time_s)
		elif _plant_repro_mode == 1:
			progress += _delta / max(0.0001, mating_duration_s)
		else:
			# 非法模式：重置并释放预占的附着点
			print("[REPRO] Invalid reproduction mode %d for creature %d, cleaning up" % [_plant_repro_mode, index])
			_cleanup_reproduction_state(wsp_att, ws_att_count)
			return

		if progress >= 1.0:
			progress = 0.0
			is_reproducing = false

			if _plant_repro_mode == 2:
				# 自我复制：在预占的附着点上生成后代
				for pid in _plant_repro_found_points:
					if typeof(pid) != TYPE_INT:
						continue
					if pid < 0 or pid >= ws_count:
						continue
					# 仅在预占标记仍然为 true 时生成
					if pid < ws_att_count and wsp_att[pid]:
						var child_genome = self.genome.duplicate()
						child_genome = GenomeUtils.mutate_genome(child_genome)
						child_genome = GenomeUtils.enforce_plant_genome(child_genome)
						var new_creature = Creature.new(child_genome, Transform3D(Basis(), wsp[pid]))
						new_creature.attach_to_surface_point(pid)

				energy_p = max(0.0, energy_p - selfrep_energy_cost_p)
				cooldown_timer = selfrep_cooldown_s
				# restore color after self-replication finished (mode 2)
				self._set_repro_color(false, 2)

			elif _plant_repro_mode == 1:
				# 配对繁殖：使用预占的附着点生成后代
				var mate: Creature = null
				if _plant_repro_mate_idx >= 0 and _plant_repro_mate_idx < creatures_arr.size():
					mate = creatures_arr[_plant_repro_mate_idx]

				# 生成后代并标记附着点为已占用
				for pid in _plant_repro_found_points:
					if typeof(pid) != TYPE_INT:
						continue
					if pid < 0 or pid >= ws_count:
						continue
					# 仅在预占标记仍然为 true 时生成
					if pid < ws_att_count and wsp_att[pid]:
						var child_genome: Array = []
						if mate != null:
							child_genome = GenomeUtils.crossover_single_point(self.genome, mate.genome)
						else:
							child_genome = self.genome.duplicate()
						child_genome = GenomeUtils.mutate_genome(child_genome)
						if self.is_plant:
							child_genome = GenomeUtils.enforce_plant_genome(child_genome)
						var new_creature2 = Creature.new(child_genome, Transform3D(Basis(), wsp[pid]))
						new_creature2.attach_to_surface_point(pid)

				energy_p = max(0.0, energy_p - mating_energy_cost_p)
				cooldown_timer = mating_cooldown_s
				if mate:
					mate.energy_p = max(0.0, mate.energy_p - mating_energy_cost_p)
					mate.cooldown_timer = mate.mating_cooldown_s
				# restore colors after mating finished (mode 1)
				self._set_repro_color(false, 1)
				if mate:
					mate._set_repro_color(false, 1)

			# 清理临时状态
			_plant_repro_mode = 0
			_plant_repro_mate_idx = -1
			_plant_repro_found_points.clear()
		return

	# 尚未繁殖：优先使用空间索引（octree）做半径查询以避免线性扫描
	var found_points: Array = []
	var mate_idx: int = -1
	var pos_self_local: Vector3 = pos_self

	# 先尝试使用 surface_octree 查找附近空闲附着点
	if surface_octree != null:
		if off_count > 0:
			# query all nearby points within interact_range and pick nearest available ones
			var nearby_pts: Array = surface_octree.query_radius(pos_self_local, interact_range_m, 0)
			var candidates2: Array = []
			var mate_pos_local: Vector3 = Vector3()
			var has_mate_pos: bool = false
			if _plant_repro_mate_idx >= 0 and _plant_repro_mate_idx < creatures_arr.size():
				mate_pos_local = creatures_arr[_plant_repro_mate_idx].position
				has_mate_pos = true
			for pid in nearby_pts:
				if pid >= 0 and pid < ws_att_count and not wsp_att[pid]:
					var pt2 = wsp[pid]
					var d2 = pt2.distance_squared_to(pos_self_local)
					if has_mate_pos:
						d2 = min(d2, pt2.distance_squared_to(mate_pos_local))
					candidates2.append({"pid": pid, "d": d2})
			# choose nearest up to off_count
			while candidates2.size() > 0 and found_points.size() < off_count:
				var best_idx2: int = 0
				var best_d2: float = candidates2[0]["d"]
				for j in range(1, candidates2.size()):
					if candidates2[j]["d"] < best_d2:
						best_d2 = candidates2[j]["d"]
						best_idx2 = j
				found_points.append(candidates2[best_idx2]["pid"])
				candidates2.remove_at(best_idx2)

		# 使用 creatures_octree 查找配偶（若可用），否则回退到线性扫描
		if creatures_octree != null:
			var c_near: Array = creatures_octree.query_radius(pos_self_local, interact_range_m)
			for ci_idx in c_near:
				if ci_idx >= 0 and ci_idx < creatures_arr.size():
					var ci_other = creatures_arr[ci_idx]
					if ci_other == self:
						continue
					if not ci_other.is_alive or not ci_other.is_plant:
						continue
					if not ci_other.can_reproduce():
						continue
					mate_idx = ci_idx
					break
		else:
			for ci in range(creatures_arr.size()):
				var other_ci = creatures_arr[ci]
				if other_ci == self:
					continue
				if not other_ci.is_alive or not other_ci.is_plant:
					continue
				if not other_ci.can_reproduce():
					continue
				if pos_self_local.distance_squared_to(other_ci.position) <= interact_range_sq:
					mate_idx = ci
					break
	else:
		# 没有 surface_octree：回退到线性扫描（同时寻找附着点与配偶）
		var need_found = off_count > 0
		if need_found:
			var candidates3: Array = []
			for i in range(ws_count):
				if i >= ws_att_count:
					continue
				if wsp_att[i]:
					continue
				var pt_i = wsp[i]
				if pt_i.distance_squared_to(pos_self_local) <= interact_range_sq:
					var d3: float = pt_i.distance_squared_to(pos_self_local)
					if mate_idx != -1 and mate_idx < creatures_arr.size():
						var mate_pt = creatures_arr[mate_idx].position
						d3 = min(d3, pt_i.distance_squared_to(mate_pt))
					candidates3.append({"pid": i, "d": d3})
			# pick nearest
			while candidates3.size() > 0 and found_points.size() < off_count:
				var best_idx3: int = 0
				var best_d3: float = candidates3[0]["d"]
				for j in range(1, candidates3.size()):
					if candidates3[j]["d"] < best_d3:
						best_d3 = candidates3[j]["d"]
						best_idx3 = j
				found_points.append(candidates3[best_idx3]["pid"])
				candidates3.remove_at(best_idx3)
		for ci in range(creatures_arr.size()):
			var other_ci = creatures_arr[ci]
			if other_ci == self:
				continue
			if not other_ci.is_alive or not other_ci.is_plant:
				continue
			if not other_ci.can_reproduce():
				continue
			if pos_self_local.distance_squared_to(other_ci.position) <= interact_range_sq:
				mate_idx = ci
				break


	# 如果找到配偶则开始配对繁殖（设置双方状态并预占附着点）
	if mate_idx != -1:
		var mate_ref = creatures_arr[mate_idx]
		if energy_p < mating_required_energy_p or mate_ref.energy_p < mate_ref.mating_required_energy_p:
			return
		# 只有找到足够的附着点才开始交配
		if found_points.size() > 0:
			is_reproducing = true
			progress = 0.0
			_plant_repro_mode = 1
			_plant_repro_mate_idx = mate_idx
			_plant_repro_found_points = found_points.duplicate()
			# 预占附着点
			for pid in _plant_repro_found_points:
				if typeof(pid) != TYPE_INT:
					continue
				if pid >= 0 and pid < ws_att_count:
					wsp_att[pid] = true
			mate_ref.is_reproducing = true
			mate_ref._plant_repro_mode = 1
			mate_ref._plant_repro_mate_idx = self.index
			mate_ref._plant_repro_found_points = _plant_repro_found_points.duplicate()
			# change colors to indicate reproduction (mating mode)
			self._set_repro_color(true, 1)
			if mate_ref:
				mate_ref._set_repro_color(true, 1)
		return

	# 尝试自我复制：若找到至少一个点则开始自我复制并预占点
	if found_points.size() > 0:
		is_reproducing = true
		progress = 0.0
		_plant_repro_mode = 2
		_plant_repro_found_points = found_points.duplicate()
		for pid in _plant_repro_found_points:
			if typeof(pid) != TYPE_INT:
				continue
			if pid >= 0 and pid < ws_att_count:
				wsp_att[pid] = true
		# set reproduction color for self when self-replicating (mode 2)
		self._set_repro_color(true, 2)
		return

# 清理繁殖状态的辅助函数
func _cleanup_reproduction_state(wsp_att: Array, ws_att_count: int) -> void:
	for pid in _plant_repro_found_points:
		if typeof(pid) == TYPE_INT and pid >= 0 and pid < ws_att_count:
			wsp_att[pid] = false
	is_reproducing = false
	_plant_repro_mode = 0
	_plant_repro_mate_idx = -1
	_plant_repro_found_points.clear()
	progress = 0.0
	# 恢复颜色
	self._set_repro_color(false, _plant_repro_mode)

# 繁殖上下文
func do_reproduce(_delta: float) -> void:
	# TODO: implement mating/replication logic
	pass

# 休息上下文
func do_rest(_delta: float) -> void:
	# TODO: implement rest logic
	pass

# 进食上下文
func do_eat(_delta: float) -> void:
	# TODO: implement eating logic
	pass


# Helper: set or restore reproduction color for this creature instance
func _set_repro_color(enable: bool, mode: int = 1) -> void:
	# Ensure index is valid
	if self.index < 0 or self.index >= creatures_colors.size():
		return
	if enable:
		# cache original color if not already cached
		self._original_color = creatures_colors[self.index]
		if mode == 2:
			creatures_colors[self.index] = REPRO_COLOR_SELFREPLICATE
		else:
			creatures_colors[self.index] = REPRO_COLOR_MATING
	else:
		# restore cached original color
		creatures_colors[self.index] = self._original_color
