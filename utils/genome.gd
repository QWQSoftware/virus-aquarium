class_name GenomeUtils

# Genome utility functions for the virus-aquarium project.
# Genome is represented as Array of float in [0,1].
# The mapping follows `doc_gene.md`. The decoder is defensive: if the provided
# genome is shorter than expected we fall back to safe defaults.

const DEFAULT_GENOME_LENGTH := 54

static func _lerp(a: float, b: float, t: float) -> float:
	return a + (b - a) * t

static func _gval(g: Array, idx: int, default: float = 0.5) -> float:
	# safe access and clamp to [0,1]
	if idx >= 0 and idx < g.size():
		return clamp(float(g[idx]), 0.0, 1.0)
	return clamp(float(default), 0.0, 1.0)

static func decode_genome(genome: Array) -> Dictionary:
	var g := []
	for v in genome:
		g.append(clamp(float(v), 0.0, 1.0))
	# If genome is shorter, _gval will provide defaults.
	var out := {}

	# Movement / activation
	# units and typical ranges:
	# - general_move_speed_m_per_s: m/s (0.0 - 1.0 typical)
	# - general_rot_speed_rad_s: rad/s (0.0 - 0.3 typical)
	# - active_move_speed_m_per_s: m/s (1.0 - 10.0 typical)
	# - active_rot_speed_rad_s: rad/s (0.4 - 0.7 typical)
	# - activation_duration_s: seconds (1.0 - 10.0)
	# - activation_energy_cost_p: energy points (0 - 10)
	# - activation_cooldown_s: seconds (0 - 60)
	#
	# 中文：移动 / 激活
	# - general_move_speed_m_per_s: 米/秒（典型范围 0.0 - 1.0）
	# - general_rot_speed_rad_s: 弧度/秒（典型范围 0.0 - 0.3）
	# - active_move_speed_m_per_s: 激活时移动速度，米/秒（1.0 - 10.0）
	# - active_rot_speed_rad_s: 激活时旋转速度，弧度/秒（0.4 - 0.7）
	# - activation_duration_s: 激活持续时间，秒（1 - 10）
	# - activation_energy_cost_p: 激活消耗的能量点（0 - 10）
	# - activation_cooldown_s: 激活后的冷却时间，秒（0 - 60）
	out.general_move_speed_m_per_s = _lerp(0.0, 1.0, _gval(g, 0, 0.2))
	out.general_rot_speed_rad_s  = _lerp(0.0, 0.3, _gval(g, 1, 0.1))
	out.active_move_speed_m_per_s  = _lerp(1.0, 10.0, _gval(g, 2, 0.5))
	out.active_rot_speed_rad_s   = _lerp(0.4, 0.7, _gval(g, 3, 0.5))
	out.activation_duration_s = _lerp(1.0, 10.0, _gval(g, 4, 0.2))
	out.activation_energy_cost_p = _lerp(0.0, 10.0, _gval(g, 5, 0.0))
	out.activation_cooldown_s = _lerp(0.0, 60.0, _gval(g, 6, 0.0))

	# Lifespan / reproduction
	# units and typical ranges:
	# - max_lifespan_s: seconds (10 - 300)
	# - adult_age_s: seconds (fraction of max_lifespan)
	# - fertility_end_s: seconds (fraction of max_lifespan)
	# - mating_duration_s: seconds (0.5 - 10.0)
	# - mating_cooldown_s: seconds (0 - 60)
	# - mating_attachment_pref_type: integer (attachment type id, 0-9)
	# - mating_light_pref_unitless: unitless [0-1] (preferred light intensity)
	# - mating_min_energy_p: energy points (0 - 200)
	# - mating_energy_cost_p: energy points (0 - 100)
	# - offspring_count: integer (0 - 6)
	#
	# 中文：寿命 / 繁殖
	# - max_lifespan_s: 最大寿命，秒（10 - 300）
	# - adult_age_s: 成年年龄，秒（为最大寿命的某一比例）
	# - fertility_end_s: 终止生育年龄，秒（为最大寿命的某一比例）
	# - mating_duration_s: 交配时长，秒（0.5 - 10）
	# - mating_cooldown_s: 交配冷却，秒（0 - 60）
	# - mating_attachment_pref_type: 偏好附着点类型（整数 id，0-9）
	# - mating_light_pref_unitless: 偏好光照强度（0-1）
	# - mating_min_energy_p: 交配所需最低能量点（0 - 200）
	# - mating_energy_cost_p: 交配消耗的能量点（0 - 100）
	# - offspring_count: 后代数量（整数，0 - 6）
	out.max_lifespan_s = _lerp(10.0, 300.0, _gval(g, 7, 0.5))
	out.adult_age_s = out.max_lifespan_s * _lerp(0.05, 0.95, _gval(g, 8, 0.2))
	out.fertility_end_s = out.max_lifespan_s * _lerp(0.2, 1.0, _gval(g, 9, 0.9))

	out.mating_duration_s = _lerp(0.5, 10.0, _gval(g, 10, 0.3))
	out.mating_cooldown_s = _lerp(0.0, 60.0, _gval(g, 11, 0.0))
	out.mating_attachment_pref_type = int(floor(_gval(g, 12, 0.0) * 10.0))
	out.mating_light_pref_unitless = _lerp(0.0, 1.0, _gval(g, 13, 0.5))
	out.mating_min_energy_p = _lerp(0.0, 200.0, _gval(g, 14, 0.1))
	out.mating_energy_cost_p = _lerp(0.0, 100.0, _gval(g, 15, 0.0))
	out.offspring_count = int(floor(_gval(g, 16, 0.0) * 6.0))

	# Self-replication
	# units and typical ranges:
	# - selfrep_cooldown_s: seconds (0 - 300)
	# - selfrep_required_energy_p: energy points required to start (0 - 500)
	# - selfrep_energy_cost_p: energy points consumed during replication (0 - 300)
	# - selfrep_time_s: seconds (0.1 - 60)
	#
	# 中文：自我复制
	# - selfrep_cooldown_s: 自我复制冷却时间，秒（0 - 300）
	# - selfrep_required_energy_p: 开始自我复制所需的能量点（0 - 500）
	# - selfrep_energy_cost_p: 自我复制过程中消耗的能量点（0 - 300）
	# - selfrep_time_s: 自我复制所需时间，秒（0.1 - 60）
	out.selfrep_cooldown_s = _lerp(0.0, 300.0, _gval(g, 17, 0.0))
	out.selfrep_required_energy_p = _lerp(0.0, 500.0, _gval(g, 18, 0.0))
	out.selfrep_energy_cost_p = _lerp(0.0, 300.0, _gval(g, 19, 0.0))
	out.selfrep_time_s = _lerp(0.1, 60.0, _gval(g, 20, 0.1))

	# Size / growth
	# units and typical ranges:
	# - initial_size_m: meters (0.1 - 0.3)
	# - adult_size_m: meters (0.5 - 3.0)
	# - size_k: unitless exponent for growth curve x^k
	#
	# 中文：大小 / 生长
	# - initial_size_m: 初始大小，米（0.1 - 0.3）
	# - adult_size_m: 成年大小，米（0.5 - 3.0）
	# - size_k: 生长曲线指数 k（无单位）
	out.initial_size_m = _lerp(0.1, 0.3, _gval(g, 21, 0.1))
	out.adult_size_m = _lerp(0.5, 3.0, _gval(g, 22, 0.5))
	out.size_k = _lerp(0.1, 4.0, _gval(g, 23, 1.0))

	# Energy
	# units and typical ranges:
	# - max_energy_init_p: energy points (0 - 20)
	# - max_energy_adult_p: energy points (50 - 150)
	# - energy_k: unitless exponent for energy growth curve x^k
	#
	# 中文：能量
	# - max_energy_init_p: 初始最大能量，能量点（0 - 20）
	# - max_energy_adult_p: 成年最大能量，能量点（50 - 150）
	# - energy_k: 能量槽成长曲线指数 k（无单位）
	out.max_energy_init_p = _lerp(0.0, 20.0, _gval(g, 24, 0.0))
	out.max_energy_adult_p = _lerp(50.0, 150.0, _gval(g, 25, 0.5))
	out.energy_k = _lerp(0.1, 4.0, _gval(g, 26, 1.0))

	# Consumption
	# units and typical ranges:
	# - consumption_init_p_per_s: energy consumption rate at start (p/s) (0.1-0.5)
	# - consumption_adult_p_per_s: energy consumption rate at adult (p/s) (0.6-1.0)
	# - consumption_k: unitless exponent for consumption growth curve x^k
	#
	# 中文：消耗
	# - consumption_init_p_per_s: 初始能量消耗速率（点/秒）（0.1 - 0.5）
	# - consumption_adult_p_per_s: 成年能量消耗速率（点/秒）（0.6 - 1.0）
	# - consumption_k: 能量消耗速率增长曲线指数 k（无单位）
	out.consumption_init_p_per_s = _lerp(0.1, 0.5, _gval(g, 27, 0.1))
	out.consumption_adult_p_per_s = _lerp(0.6, 1.0, _gval(g, 28, 0.6))
	out.consumption_k = _lerp(0.1, 4.0, _gval(g, 29, 1.0))

	# Photosynthesis / food
	# units and typical ranges:
	# - photosynthesis_rate_p_per_s: energy gained in light per second (p/s) (0 - 5)
	# - as_food_energy_p: energy provided if eaten (p) (10 - 150)
	# - eating_time_s: seconds to eat (0.5 - 1.0)
	# - eating_desire_k: unitless exponent controlling desire curve
	#
	# 中文：光合作用 / 食物
	# - photosynthesis_rate_p_per_s: 在光照下每秒产生的能量点（点/秒）（0 - 5）
	# - as_food_energy_p: 被当作食物时提供的能量点（10 - 150）
	# - eating_time_s: 进食所需时间，秒（0.5 - 1.0）
	# - eating_desire_k: 进食欲望曲线指数 k（无单位）
	out.photosynthesis_rate_p_per_s = _lerp(0.0, 5.0, _gval(g, 30, 0.0))
	out.as_food_energy_p = _lerp(10.0, 150.0, _gval(g, 31, 0.1))
	out.eating_time_s = _lerp(0.5, 1.0, _gval(g, 32, 0.5))
	out.eating_desire_k = _lerp(0.1, 4.0, _gval(g, 33, 1.0))

	# Health
	# units and typical ranges:
	# - health_init_p: hit points at spawn (p) (1 - 20)
	# - health_adult_p: hit points at adult (p) (25 - 100)
	# - health_k: unitless exponent for HP growth curve
	# - health_recover_init_p_per_s: HP recovered per second at spawn (p/s) (0.5 - 1)
	# - health_recover_adult_p_per_s: HP recovered per second at adult (p/s) (2 - 5)
	# - health_recover_k: unitless exponent for recovery curve
	#
	# 中文：血量 / 恢复
	# - health_init_p: 初始最大血量（血点）（1 - 20）
	# - health_adult_p: 成年最大血量（25 - 100）
	# - health_k: 血量成长曲线指数 k（无单位）
	# - health_recover_init_p_per_s: 初始血量回复速度，点/秒（0.5 - 1）
	# - health_recover_adult_p_per_s: 成年血量回复速度，点/秒（2 - 5）
	# - health_recover_k: 血量回复曲线指数 k（无单位）
	out.health_init_p = _lerp(1.0, 20.0, _gval(g, 34, 0.5))
	out.health_adult_p = _lerp(25.0, 100.0, _gval(g, 35, 0.5))
	out.health_k = _lerp(0.1, 4.0, _gval(g, 36, 1.0))
	out.health_recover_init_p_per_s = _lerp(0.5, 1.0, _gval(g, 37, 0.5))
	out.health_recover_adult_p_per_s = _lerp(2.0, 5.0, _gval(g, 38, 0.5))
	out.health_recover_k = _lerp(0.1, 4.0, _gval(g, 39, 1.0))

	# Surface / attachment
	# meanings and ranges:
	# - surface_attachment_types_count: number of different attachment type IDs provided (0-10)
	# - surface_attachment_count: number of attachment points available (0-3)
	# - surface_attachment_max_accum: maximum accumulated chain depth (1-10)
	#
	# 中文：表面 / 附着
	# - surface_attachment_types_count: 提供的附着点类型数量（0-10）
	# - surface_attachment_count: 提供的附着点数量（0-3）
	# - surface_attachment_max_accum: 最大附着点累计值/链深度（1-10）
	out.surface_attachment_types_count = int(floor(_gval(g, 40, 0.0) * 10.0))
	out.surface_attachment_count = int(floor(_gval(g, 41, 0.0) * 3.0))
	out.surface_attachment_max_accum = int(1 + floor(_gval(g, 42, 0.0) * 9.0))

	# Stamina / rest
	# units and typical ranges:
	# - stamina_max_p: stamina points (0 - 100)
	# - rest_recover_speed_p_per_s: stamina recovered per second while resting (p/s) (1 - 25)
	# - rest_pref_attachment_type: preferred attachment type id for resting (0-9)
	#
	# 中文：精力 / 休息
	# - stamina_max_p: 精力值（0 为植物）（0 - 100）
	# - rest_recover_speed_p_per_s: 休息时每秒恢复的精力点（1 - 25）
	# - rest_pref_attachment_type: 偏好的休息附着点类型 id（0-9）
	out.stamina_max_p = _lerp(0.0, 100.0, _gval(g, 43, 0.0))
	out.rest_recover_speed_p_per_s = _lerp(1.0, 25.0, _gval(g, 44, 0.5))
	out.rest_pref_attachment_type = int(floor(_gval(g, 45, 0.0) * 10.0))

	# Reconnaissance / senses / appearance
	# units and typical ranges:
	# - color_h_unitless: hue component H in HSV color (0.0 - 1.0)
	# - initial_insight_p: numeric insight value at spawn (1 - 4)
	# - adult_insight_p: numeric insight at adult (1 - 30)
	# - view_range_init_m: view range at spawn in meters (20 - 50)
	# - view_range_adult_m: view range at adult in meters (60 - 500)
	# - view_range_k: unitless exponent for view range growth curve
	#
	# 中文：侦察与反侦察 / 视觉 / 外观
	# - color_h_unitless: 颜色 H 分量（0.0 - 1.0）
	# - initial_insight_p: 初始洞察力（数值，1 - 4）
	# - adult_insight_p: 成年洞察力（数值，1 - 30）
	# - view_range_init_m: 初始视野范围，米（20 - 50）
	# - view_range_adult_m: 成年视野范围，米（60 - 500）
	# - view_range_k: 视野范围增长曲线指数 k（无单位）
	out.color_h_unitless = _gval(g, 46, 0.0)
	out.initial_insight_p = _lerp(1.0, 4.0, _gval(g, 47, 0.5))
	out.adult_insight_p = _lerp(1.0, 30.0, _gval(g, 48, 0.5))
	out.view_range_init_m = _lerp(20.0, 50.0, _gval(g, 49, 0.2))
	out.view_range_adult_m = _lerp(60.0, 500.0, _gval(g, 50, 0.5))
	out.view_range_k = _lerp(0.1, 4.0, _gval(g, 51, 1.0))

	# Decoration
	# - decor_scale_x: unitless scale applied to decoration along x (0.2 - 1.0)
	# - decor_scale_z: unitless scale applied to decoration along z (0.2 - 1.0)
	#
	# 中文：装饰
	# - decor_scale_x: 装饰物在 x 轴的缩放（0.2 - 1.0）
	# - decor_scale_z: 装饰物在 z 轴的缩放（0.2 - 1.0）
	out.decor_scale_x = _lerp(0.2, 1.0, _gval(g, 52, 0.5))
	out.decor_scale_z = _lerp(0.2, 1.0, _gval(g, 53, 0.5))

	return out

static func random_genome(length: int = DEFAULT_GENOME_LENGTH, rng_seed: int = -1) -> Array:
	var rng = RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = int(rng_seed)
	else:
		rng.randomize()
	var g := []
	for i in range(length):
		g.append(rng.randf())
	return g

static func mutate_genome(genome: Array, p_mut: float = 0.02, sigma: float = 0.05, rng_seed: int = -1) -> Array:
	var rng = RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = int(rng_seed)
	else:
		rng.randomize()
	var out := []
	for v in genome:
		var val = float(v)
		if rng.randf() < p_mut:
			val += rng.randf_range(-sigma, sigma)
		out.append(clamp(val, 0.0, 1.0))
	return out

static func crossover_single_point(a: Array, b: Array, rng_seed: int = -1) -> Array:
	var rng = RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = int(rng_seed)
	else:
		rng.randomize()
	var n = min(a.size(), b.size())
	if n <= 1:
		return a.duplicate()
	var point = rng.randi_range(1, n - 1)
	var out := []
	for i in range(n):
		out.append(a[i] if i < point else b[i])
	return out
