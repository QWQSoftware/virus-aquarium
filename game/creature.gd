extends RefCounted

class_name Creature

# 1m的交互范围，例如攻击，进食，交配
const interact_range_m: float = 1.0

# 一些共享的世界参数，用来帮助生物读取世界环境信息
static var world_surface_points: Array[Vector3] = []
static var world_surface_normals: Array[Vector3] = []
static var world_surface_point_is_attached: Array[bool] = []

# 所有生物的世界坐标
static var creatures_world_positions: Array[Vector3] = []
# 所有生物的大小
static var creatures_sizes: Array[float] = []
# 所有生物的颜色（HSL）
static var creatures_colors: Array[Color] = []


# --- 显式成员声明（避免在 RefCounted 上动态创建属性导致的错误）
var index: int = -1  # 在 creatures_world_positions 等静态数组中的索引

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
var mating_min_energy_p: float = 0.0
var mating_energy_cost_p: float = 0.0
var offspring_count: int = 0

# self-replication
var selfrep_cooldown_s: float = 0.0
var selfrep_required_energy_p: float = 0.0
var selfrep_energy_cost_p: float = 0.0
var selfrep_time_s: float = 0.1

# size / growth
var initial_size_m: float = 0.1
var adult_size_m: float = 0.5
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

# 数据驱动的 Creature 类（从 game.gd 抽离）
func _init(genome_in: Array, transform: Transform3D) -> void:
	# 设置index
	self.index = creatures_world_positions.size()
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
	self.mating_min_energy_p = self.phenotype.get("mating_min_energy_p", 0.0)
	self.mating_energy_cost_p = self.phenotype.get("mating_energy_cost_p", 0.0)
	self.offspring_count = self.phenotype.get("offspring_count", 0)

	# self-replication
	self.selfrep_cooldown_s = self.phenotype.get("selfrep_cooldown_s", 0.0)
	self.selfrep_required_energy_p = self.phenotype.get("selfrep_required_energy_p", 0.0)
	self.selfrep_energy_cost_p = self.phenotype.get("selfrep_energy_cost_p", 0.0)
	self.selfrep_time_s = self.phenotype.get("selfrep_time_s", 0.1)

	# size / growth
	self.initial_size_m = self.phenotype.get("initial_size_m", 0.1)
	self.adult_size_m = self.phenotype.get("adult_size_m", 0.5)
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
	self.age_s = 0.0
	self.is_alive = true
	# 初始资源/状态（使用 phenotype 提供的范围作为参考）
	# 现在可以直接读取为实例属性（decode_genome 会填充默认值）
	self.health_p = self.health_init_p
	self.energy_p = self.max_energy_init_p
	self.stamina_p = self.stamina_max_p
	self.global_transform = transform
	self.is_plant = (self.energy_p <= 0.0 and self.photosynthesis_rate_p_per_s > 0.0)
	self.attachments = []



func update_age(delta: float) -> void:
	self.age_s += delta
	if self.age_s >= self.max_lifespan_s:
		self.is_alive = false

func update_photosynthesis(delta: float) -> void:
	return

func update_hp(delta: float) -> void:
	return

func update_stamina(delta: float) -> void:
	return

func update_energy(delta: float) -> void:
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

func decide_and_act(delta: float) -> void:
	if not self.is_alive:
		return
	if self.is_plant:
		var repro_w = self.compute_reproduce_desire()
		if repro_w > 0.5:
			self.do_reproduce()
		return

	var w_reproduce = self.compute_reproduce_desire()
	var w_rest = self.compute_rest_desire()
	var w_eat = self.compute_eat_desire()
	var w_flee = self.compute_flee_desire()

	var max_w = max(max(w_reproduce, w_rest), max(w_eat, w_flee))
	if max_w == w_reproduce:
		self.do_reproduce()
	elif max_w == w_rest:
		self.do_rest(delta)
	elif max_w == w_eat:
		self.do_eat()
	elif max_w == w_flee:
		self.do_flee()

func compute_reproduce_desire() -> float:
	var adult_age = self.phenotype.get("adult_age_s", 0.0)
	var fertility_end = self.phenotype.get("fertility_end_s", 1e9)
	if self.age_s < adult_age or self.age_s > fertility_end:
		return 0.0
	var min_energy = self.phenotype.get("mating_min_energy_p", 0.0)
	var e = self.energy_p
	if e < min_energy:
		return 0.0
	var max_e = self.phenotype.get("max_energy_adult_p", max(min_energy, e))
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

func do_reproduce() -> void:
	# TODO: implement mating/replication logic
	pass

func do_rest(_delta: float) -> void:
	# TODO: implement rest logic
	pass

func do_eat() -> void:
	# TODO: implement eating logic
	pass

func do_flee() -> void:
	# TODO: implement flee logic
	pass

func do_attach(_target, _attach_point_id: int) -> void:
	# TODO: implement attach logic
	pass
