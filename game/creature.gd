extends RefCounted

class_name Creature

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

# 所有生物的世界坐标
static var creatures_world_positions: Array[Vector3] = []
# 所有生物的大小
static var creatures_sizes: Array[float] = []
# 所有生物的颜色（HSL）
static var creatures_colors: Array[Color] = []
static var creatures_is_plants: Array[bool] = []

static var creatures : Array[Creature] = []

# Debugging: print per-creature update details when enabled. Set DEBUG_FILTER_INDEX >=0 to only print that index.
static var DEBUG_PRINT_UPDATES: bool = true
static var DEBUG_FILTER_INDEX: int = -1


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
	creatures_sizes.append(initial_size_m)
	creatures_colors.append(Color.from_hsv(color_h_unitless, 1.0, 1.0))

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

	self.attachments = []

	creatures.append(self)

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
	# 释放任何被占用的世界表面点（包括当前附着点和 attachments 列表）
	if self.now_attached_id >= 0 and self.now_attached_id < world_surface_point_is_attached.size():
		world_surface_point_is_attached[self.now_attached_id] = false
	for pid in self.attachments:
		if typeof(pid) == TYPE_INT and pid >= 0 and pid < world_surface_point_is_attached.size():
			world_surface_point_is_attached[pid] = false
	self.genome.clear()
	self.phenotype.clear()
	self.attachments.clear()


static func cleanup_dead() -> void:
	# 倒序遍历 creatures 列表并释放已死亡的个体，倒序可以安全地在迭代中移除元素
	for i in range(creatures.size() - 1, -1, -1):
		var c = creatures[i]
		if c == null:
			continue
		if not c.is_alive:
			c.dispose()


func attach_to_surface_point(point_id: int) -> void:
	if point_id < 0 or point_id >= world_surface_points.size():
		return
	self.now_attached_id = point_id
	self.position = world_surface_points[point_id]
	self.global_transform.origin = self.position


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


# 是植物的话有10倍加成
func update_photosynthesis(_delta: float) -> void:
	if self.photosynthesis_rate_p_per_s <= 0.0:
		return
	if self.energy_p >= self.max_energy_adult_p:
		self.energy_p = self.max_energy_adult_p
	if self.is_plant:
		self.energy_p += self.photosynthesis_rate_p_per_s * 10.0 * _delta
	else:
		self.energy_p += self.photosynthesis_rate_p_per_s * _delta

	self.energy_p = min(self.energy_p, self.max_energy_adult_p)
	return

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
	if self.energy_p < min(self.mating_required_energy_p, self.selfrep_required_energy_p):
		return false
	return true

func reproduce_with(mate: Creature) -> void:
	if not self.can_reproduce() or not mate.can_reproduce():
		return

	# 进行交配
	self.is_reproducing = true
	mate.is_reproducing = true

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
	# 植物专用繁殖逻辑（支持配对繁殖和自我复制）
	# 只在成年尝试繁殖
	if age_s < adult_age_s or age_s > fertility_end_s:
		return

	# 能量不足无法繁殖
	if energy_p < min(mating_required_energy_p, selfrep_required_energy_p):
		return

	# 检查繁殖冷却
	if cooldown_timer > 0.0:
		cooldown_timer = max(0.0, cooldown_timer - _delta)
		return

	# 如果已经处于繁殖状态，根据当前模式推进进度并在完成时生成后代
	if is_reproducing:
		if _plant_repro_mode == 2:
			# 自我复制使用 selfrep_time_s
			progress += _delta / max(0.0001, selfrep_time_s)
		elif _plant_repro_mode == 1:
			# 与配偶交配使用 mating_duration_s
			progress += _delta / max(0.0001, mating_duration_s)
		else:
			# 兼容：如果没有模式则直接取消繁殖
			is_reproducing = false
			_plant_repro_mode = 0
			_plant_repro_mate_idx = -1
			_plant_repro_found_points.clear()
			progress = 0.0
			return

		if progress >= 1.0:
			# 繁殖完成：根据模式生成后代并结算能量/冷却
			progress = 0.0
			is_reproducing = false

			if _plant_repro_mode == 2:
				# 自我复制：在预占的附着点上生成后代
				for pid in _plant_repro_found_points:
					if pid < 0 or pid >= world_surface_points.size():
						continue
					# 位置再次检查（已被预占则直接跳过）
					if world_surface_point_is_attached.size() > pid and world_surface_point_is_attached[pid]:
						# 已预占/标记为占用，生成后代并附着
						# 复制并对基因进行变异以引入突变
						var child_genome = self.genome.duplicate()
						child_genome = GenomeUtils.mutate_genome(child_genome)
						# 确保子代仍符合植物标准（如 stamina=0, 合理的成年年龄/寿命）
						child_genome = GenomeUtils.enforce_plant_genome(child_genome)
						var new_creature = Creature.new(child_genome, Transform3D(Basis(), world_surface_points[pid]))
						new_creature.attach_to_surface_point(pid)
				# 扣除能量并设置冷却
				energy_p = max(0.0, energy_p - selfrep_energy_cost_p)
				cooldown_timer = selfrep_cooldown_s

			elif _plant_repro_mode == 1:
				# 配对繁殖：尝试在自己周围或配偶周围寻找空闲点并生成后代
				var mate: Creature = null
				if _plant_repro_mate_idx >= 0 and _plant_repro_mate_idx < creatures.size():
					mate = creatures[_plant_repro_mate_idx]

				# 收集可用点（优先自身附近，然后配偶附近）
				var spawn_points: Array[int] = []
				# 优先从自身附近收集
				for i in range(world_surface_points.size()):
					if spawn_points.size() >= offspring_count:
						break
					if i >= world_surface_point_is_attached.size():
						continue
					if world_surface_point_is_attached[i]:
						continue
					var pt = world_surface_points[i]
					if pt.distance_to(self.position) <= 2.0:
						spawn_points.append(i)

				# 如需更多，则从配偶附近继续收集（避免重复）
				if mate:
					for i in range(world_surface_points.size()):
						if spawn_points.size() >= offspring_count:
							break
						if i >= world_surface_point_is_attached.size():
							continue
						if world_surface_point_is_attached[i]:
							continue
						if spawn_points.has(i):
							continue
						var pt2 = world_surface_points[i]
						if pt2.distance_to(mate.position) <= 2.0:
							spawn_points.append(i)

				# 生成后代（基因简单采用父本基因拷贝作为占位实现）
				for pid in spawn_points:
					if pid < 0 or pid >= world_surface_points.size():
						continue
					world_surface_point_is_attached[pid] = true
					# 交配子代：若存在配偶则做单点交叉，否则复制父本基因，再对结果进行突变
					var child_genome: Array = []
					if mate != null:
						child_genome = GenomeUtils.crossover_single_point(self.genome, mate.genome)
					else:
						child_genome = self.genome.duplicate()
					# 对子代基因进行变异
					child_genome = GenomeUtils.mutate_genome(child_genome)
					# 若父本为植物，也需要确保子代满足植物约束
					if self.is_plant:
						child_genome = GenomeUtils.enforce_plant_genome(child_genome)
					var new_creature2 = Creature.new(child_genome, Transform3D(Basis(), world_surface_points[pid]))
					new_creature2.attach_to_surface_point(pid)

				# 扣除双方能量并设置双方冷却
				energy_p = max(0.0, energy_p - mating_energy_cost_p)
				cooldown_timer = mating_cooldown_s
				if mate:
					mate.energy_p = max(0.0, mate.energy_p - mating_energy_cost_p)
					mate.cooldown_timer = mate.mating_cooldown_s

			# 清理临时状态
			_plant_repro_mode = 0
			_plant_repro_mate_idx = -1
			_plant_repro_found_points.clear()
		return


	# 尚未繁殖：尝试寻找附近可用的附着点（用于自我复制）
	var found_points: Array[int] = []
	if offspring_count > 0:
		for i in range(world_surface_points.size()):
			if world_surface_point_is_attached[i]:
				continue
			var pt = world_surface_points[i]
			# 搜索附近 interact_range_m 范围内的点
			if pt.distance_to(self.position) > interact_range_m:
				continue
			found_points.append(i)
			if found_points.size() >= self.offspring_count:
				break

	# 配对尝试：优先与其他植物交配
	var mate_idx: int = -1
	for i in range(creatures.size()):
		var other = creatures[i]
		if other == self:
			continue
		if not other.is_alive or not other.is_plant:
			continue
		if not other.can_reproduce():
			continue
		var dist = self.position.distance_to(other.position)
		if dist > interact_range_m:
			continue
		mate_idx = i
		break

	if mate_idx != -1:
		# 开始配对繁殖：设置双方为繁殖状态并记录配偶
		var mate = creatures[mate_idx]
		# 若任一方能量不足或处于冷却，则取消
		if energy_p < mating_required_energy_p or mate.energy_p < mate.mating_required_energy_p:
			return
		is_reproducing = true
		progress = 0.0
		_plant_repro_mode = 1
		_plant_repro_mate_idx = mate_idx
		# 将配偶也标记为繁殖中（但配偶的进度将在其自己的 do_plant_reproduce 中推进）
		mate.is_reproducing = true
		mate._plant_repro_mode = 1
		mate._plant_repro_mate_idx = self.index
		return

	# 自我复制尝试：如果找到至少一个点则开始自我复制并预占点
	if found_points.size() > 0:
		is_reproducing = true
		progress = 0.0
		_plant_repro_mode = 2
		_plant_repro_found_points = found_points.duplicate()
		# 预占这些附着点，防止被其他生物占用
		for pid in _plant_repro_found_points:
			if pid >= 0 and pid < world_surface_point_is_attached.size():
				world_surface_point_is_attached[pid] = true
		return

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
