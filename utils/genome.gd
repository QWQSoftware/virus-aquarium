class_name GenomeUtils

# 基因（genome）工具集
# - 基因以 Array[float] 表示，每个值应在 [0,1] 范围内。
# - 本文件负责将基因数组 decode 成 phenotype 字典（物理/行为参数），
#   映射表依据项目根目录下的 `doc_gene.md`。
# - decode 是防御式实现：如果传入的 genome 长度不足，使用安全默认值。

const DEFAULT_GENOME_LENGTH := 61
# 默认基因长度：用于生成随机基因或预期的基因槽数。
# 如果你扩展/重排基因索引，请同步修改此常量。

static func _lerp(a: float, b: float, t: float) -> float:
	# 线性插值（Lerp）
	# 参数:
	#  - a: 起始值（float）
	#  - b: 结束值（float）
	#  - t: 插值因子（通常在 0..1 范围内）
	# 返回:
	#  - 在 a 和 b 之间按比例 t 插值的值（float）
	# 说明/边界:
	#  - 如果 t 在 [0,1] 之外，则会按比例外推；调用方通常保证 t 已被 clamp 到 [0,1]
	#  - 用于将基因槽（0..1）映射到有单位的物理参数区间
	return a + (b - a) * t

static func _gval(g: Array, idx: int, default: float = 0.5) -> float:
	# 读取基因数组的安全包装器
	# 参数:
	#  - g: 基因数组（Array），每个元素预期为可转换为 float 的数值（通常在 0..1）
	#  - idx: 要读取的基因槽索引（int）
	#  - default: 当索引越界或缺失时使用的默认值（float，默认 0.5）
	# 返回:
	#  - 索引处的基因值，已转换为 float 并 clamp 到 [0.0, 1.0]
	# 说明/边界:
	#  - 如果 idx 越界（负值或大于等于 g.size()），返回 clamp(default, 0,1)
	#  - 可保证上层调用无需再对基因值做越界检查
	if idx >= 0 and idx < g.size():
		return clamp(float(g[idx]), 0.0, 1.0)
	return clamp(float(default), 0.0, 1.0)

static func decode_genome(genome: Array) -> Dictionary:
	# 将基因数组解码为 phenotype 字典（物理与行为参数）
	# 参数:
	#  - genome: Array，基因槽数组，元素预期在 [0,1]（若越界会被 clamp）
	# 返回:
	#  - Dictionary，包含被映射为带单位的参数（例如速度、寿命、繁殖参数等）
	# 行为说明:
	#  - decode 会对传入 genome 做防御性处理：把值 clamp 到 [0,1]，若数组太短，
	#    内部调用 _gval 会使用内置默认值保证输出字典字段都有合理数值。
	#  - 映射区间与默认值在文件顶部注释和 doc_gene.md 中定义，便于保持一致性。
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
	out.adult_age_s = out.max_lifespan_s * _lerp(0.05, 0.10, _gval(g, 8, 0.2))
	out.fertility_end_s = out.max_lifespan_s * _lerp(0.2, 1.0, _gval(g, 9, 0.9))

	# 为了支持更快的繁殖周期（例如每 ~5s 可完成一次繁殖），
	# 将交配时长与冷却的映射区间缩小到更小的上限。
	out.mating_duration_s = _lerp(0.1, 1.0, _gval(g, 10, 0.3))
	out.mating_cooldown_s = _lerp(0.0, 10.0, _gval(g, 11, 0.0))
	out.mating_attachment_pref_type = int(floor(_gval(g, 12, 0.0) * 10.0))
	out.mating_light_pref_unitless = _lerp(0.0, 1.0, _gval(g, 13, 0.5))
	out.mating_min_energy_p = _lerp(0.0, 200.0, _gval(g, 14, 0.1))
	out.mating_energy_cost_p = _lerp(0.0, 100.0, _gval(g, 15, 0.0))

	# 新：将交配/自复制能量参数也以相对比率输出（相对于成年最大能量 max_energy_adult_p）
	# 这些 *_frac 字段在 Creature 初始化时会被优先识别并乘以 max_energy_adult_p
	out.mating_required_energy_frac = _lerp(0.0, 1.0, _gval(g, 14, 0.1))
	out.mating_energy_cost_frac = _lerp(0.0, 1.0, _gval(g, 15, 0.0))
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
	# 同样缩短自我复制的冷却与执行时间上限，便于快速重复自复制
	out.selfrep_cooldown_s = _lerp(0.0, 30.0, _gval(g, 17, 0.0))
	out.selfrep_required_energy_p = _lerp(0.0, 500.0, _gval(g, 18, 0.0))
	out.selfrep_energy_cost_p = _lerp(0.0, 300.0, _gval(g, 19, 0.0))

	# 相对比率字段（0.0 - 1.0），表示相对于成年最大能量的比例
	out.selfrep_required_energy_frac = _lerp(0.0, 1.0, _gval(g, 18, 0.0))
	out.selfrep_energy_cost_frac = _lerp(0.0, 1.0, _gval(g, 19, 0.0))
	out.selfrep_time_s = _lerp(0.1, 5.0, _gval(g, 20, 0.1))

	# Size / growth
	# units and typical ranges:
	# - initial_size_m: meters (0.1 - 0.3)
	# - size_k: parameter controlling the growth curve; interpreted as the base k for log_k(x)
	# - size_growth_scale: meters multiplier controlling how much log_k(age) contributes to size
	#
	# 中文：大小 / 生长
	# - initial_size_m: 初始大小，米（0.1 - 0.3）
	# - size_k: 生长曲线参数 k（作为对数底），范围 2 - 100；增长使用 log_k(age+1)
	# - size_growth_scale: 生长缩放因子（米），控制 log_k(age+1) 的放大倍数
	out.initial_size_m = _lerp(0.1, 0.3, _gval(g, 21, 0.1))
	# 新：使用以 k 为底的对数曲线 log_k(age+1) 作为年龄到尺寸的映射，k 映射到 2..100
	out.size_k = _lerp(2.0, 100.0, _gval(g, 23, 0.5))
	# 使用原本被占位的基因槽（22）来控制对数曲线的尺度（以米为单位），默认 0.1m
	out.size_growth_scale = _lerp(0.05, 1.0, _gval(g, 22, 0.1))

	# Predation / attack (捕食 / 攻击)
	# units and typical ranges:
	# - initial_attack_p: attack power at spawn (points) (0 - 5)
	# - adult_attack_p: attack power at adult (points) (1 - 15)
	# - attack_k: unitless exponent for attack growth curve x^k
	# - attack_cd_s: attack cooldown seconds (1 - 10)
	#
	# 中文：捕食 / 攻击
	# - initial_attack_p: 初始攻击力（0 - 5）
	# - adult_attack_p: 成年攻击力（1 - 15）
	# - attack_k: 攻击成长曲线指数 k（无单位）
	# - attack_cd_s: 攻击冷却（秒）（1 - 10）
	out.initial_attack_p = _lerp(0.0, 5.0, _gval(g, 24, 0.0))
	out.adult_attack_p = _lerp(1.0, 15.0, _gval(g, 25, 0.1))
	# 攻击成长曲线 k 值可在 0-3 范围
	out.attack_k = _lerp(0.0, 3.0, _gval(g, 26, 1.0))
	out.attack_cd_s = _lerp(1.0, 10.0, _gval(g, 27, 1.0))

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
	out.max_energy_init_p = _lerp(0.0, 20.0, _gval(g, 28, 0.0))
	out.max_energy_adult_p = _lerp(50.0, 150.0, _gval(g, 29, 0.5))
	# energy_k 使用 0-3 幅度以匹配文档中的 k 值假设
	out.energy_k = _lerp(0.0, 3.0, _gval(g, 30, 1.0))

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
	out.consumption_init_p_per_s = _lerp(0.1, 0.5, _gval(g, 31, 0.1))
	out.consumption_adult_p_per_s = _lerp(0.6, 1.0, _gval(g, 32, 0.6))
	out.consumption_k = _lerp(0.0, 3.0, _gval(g, 33, 1.0))

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
	out.photosynthesis_rate_p_per_s = _lerp(0.0, 5.0, _gval(g, 34, 0.0))
	out.as_food_energy_p = _lerp(10.0, 150.0, _gval(g, 35, 0.1))
	out.eating_time_s = _lerp(0.5, 1.0, _gval(g, 36, 0.5))
	out.eating_desire_k = _lerp(0.0, 3.0, _gval(g, 37, 1.0))

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
	out.health_init_p = _lerp(1.0, 20.0, _gval(g, 38, 0.5))
	out.health_adult_p = _lerp(25.0, 100.0, _gval(g, 39, 0.5))
	out.health_k = _lerp(0.0, 3.0, _gval(g, 40, 1.0))
	out.health_recover_init_p_per_s = _lerp(0.5, 1.0, _gval(g, 41, 0.5))
	out.health_recover_adult_p_per_s = _lerp(2.0, 5.0, _gval(g, 42, 0.5))
	out.health_recover_k = _lerp(0.1, 4.0, _gval(g, 43, 1.0))

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
	out.surface_attachment_types_count = int(floor(_gval(g, 44, 0.0) * 10.0))
	out.surface_attachment_count = int(floor(_gval(g, 45, 0.0) * 3.0))
	out.surface_attachment_max_accum = int(1 + floor(_gval(g, 46, 0.0) * 9.0))

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
	out.stamina_max_p = _lerp(0.0, 100.0, _gval(g, 47, 0.0))
	out.rest_recover_speed_p_per_s = _lerp(1.0, 25.0, _gval(g, 48, 0.5))
	out.rest_pref_attachment_type = int(floor(_gval(g, 49, 0.0) * 10.0))

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
	out.color_h_unitless = _gval(g, 50, 0.0)
	out.initial_insight_p = _lerp(1.0, 4.0, _gval(g, 51, 0.5))
	out.adult_insight_p = _lerp(1.0, 30.0, _gval(g, 52, 0.5))
	out.view_range_init_m = _lerp(20.0, 50.0, _gval(g, 53, 0.2))
	out.view_range_adult_m = _lerp(60.0, 500.0, _gval(g, 54, 0.5))
	out.view_range_k = _lerp(0.0, 3.0, _gval(g, 55, 1.0))

	# Decoration
	# - decor_scale_x: unitless scale applied to decoration along x (0.2 - 1.0)
	# - decor_scale_z: unitless scale applied to decoration along z (0.2 - 1.0)
	#
	# 中文：装饰
	# - decor_scale_x: 装饰物在 x 轴的缩放（0.2 - 1.0）
	# - decor_scale_z: 装饰物在 z 轴的缩放（0.2 - 1.0）
	out.decor_scale_x = _lerp(0.2, 1.0, _gval(g, 56, 0.5))
	out.decor_scale_z = _lerp(0.2, 1.0, _gval(g, 57, 0.5))

	# 决策权重曲线 k 值（用于 compute_*_desire 的幂指数）
	# 注：k 越大，函数 x^k 对小 x 更不敏感，对接近 1 的 x 更敏感，常用于调节欲望响应曲线。
	# decision_k_reproduce: 繁殖欲望的幂指数，范围 0.0 - 3.0
	# decision_k_rest: 休息欲望的幂指数，范围 0.0 - 3.0
	# decision_k_eat: 进食欲望的幂指数，范围 0.0 - 3.0
	out.decision_k_reproduce = _lerp(0.0, 3.0, _gval(g, 58, 1.0))
	out.decision_k_rest = _lerp(0.0, 3.0, _gval(g, 59, 1.0))
	out.decision_k_eat = _lerp(0.0, 3.0, _gval(g, 60, 1.0))

	return out

static func random_genome(length: int = DEFAULT_GENOME_LENGTH, rng_seed: int = -1) -> Array:
	# 生成随机基因数组（元素为 0..1 的随机 float）
	# 参数:
	#  - length: 期望的基因槽数量（默认为 DEFAULT_GENOME_LENGTH）
	#  - rng_seed: 可选的随机种子（int），若 >=0 则使用确定性种子，便于可重复测试
	# 返回:
	#  - Array，长度为 length，包含随机 float 值（0..1）
	# 说明/边界:
	#  - 当 rng_seed 提供时，生成器使用固定 seed，从而生成可重复的基因序列；
	#    否则使用随机化的种子。
	var rng = RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = int(rng_seed)
	else:
		rng.randomize()
	var g := []
	for i in range(length):
		g.append(rng.randf())
	return g

static func random_plant_genome(rng_seed: int = -1) -> Array:
	# 生成随机植物基因数组（元素为 0..1 的随机 float，且精力值为 0）
	# 参数:
	#  - rng_seed: 可选的随机种子（int），若 >=0 则使用确定性种子，便于可重复测试
	# 返回:
	#  - Array，长度为 DEFAULT_GENOME_LENGTH，包含随机 float 值（0..1），
	#    且精力值槽（47号）被强制设为 0。
	# 说明/边界:
	#  - 当 rng_seed 提供时，生成器使用固定 seed，从而生成可重复的基因序列；
	#    否则使用随机化的种子。
	var g = random_genome(DEFAULT_GENOME_LENGTH, rng_seed)
	g[47] = 0.0 # force stamina to zero for plants

	var rng = RandomNumberGenerator.new()
	
	#植物的繁殖时间尽可能早
	g[8] = rng.randf_range(0.1,0.3) # adult age
	#植物的寿命尽量短
	# 将最大寿命映射为基因槽的 0..1 值，使 phenotype.decode 时得到大约 30..60s
	var lifespan_min_t = (30.0 - 10.0) / (300.0 - 10.0)
	var lifespan_max_t = (60.0 - 10.0) / (300.0 - 10.0)
	g[7] = rng.randf_range(lifespan_min_t, lifespan_max_t)
	return g

static func enforce_plant_genome(genome: Array, rng_seed: int = -1) -> Array:
	# 确保给定的 genome 满足植物的约束：
	# - 精力槽（47）为 0（植物无精力）
	# - 成年年龄槽（8）在 [0.1, 0.3]
	# - 最大寿命槽（7）映射到 phenotype 上大约 30..60s（对应基因槽 0..1 的子区间）
	var rng = RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = int(rng_seed)
	else:
		rng.randomize()
	var g := []
	for v in genome:
		g.append(clamp(float(v), 0.0, 1.0))
	# force stamina slot to zero
	if 47 >= g.size():
		# extend if needed
		for i in range(g.size(), 48):
			g.append(0.0)
	g[47] = 0.0
	# clamp/set adult age slot (8) to [0.1, 0.3]
	if 8 >= g.size():
		for i in range(g.size(), 9):
			g.append(0.1)
	g[8] = clamp(g[8], 0.1, 0.3)
	# lifespan slot (7): map target lifespan 30..60s into gene t range
	var lifespan_min_t = (30.0 - 10.0) / (300.0 - 10.0)
	var lifespan_max_t = (60.0 - 10.0) / (300.0 - 10.0)
	if 7 >= g.size():
		for i in range(g.size(), 8):
			g.append(lifespan_min_t)
	# if mutated value is outside desired range, randomize inside the range
	if g[7] < lifespan_min_t or g[7] > lifespan_max_t:
		g[7] = rng.randf_range(lifespan_min_t, lifespan_max_t)
	# ensure length and clamp
	for i in range(g.size()):
		g[i] = clamp(float(g[i]), 0.0, 1.0)
	return g

static func mutate_genome(genome: Array, p_mut: float = 0.02, sigma: float = 0.05, rng_seed: int = -1) -> Array:
	# 随机变异基因数组
	# 参数:
	#  - genome: 输入基因 Array
	#  - p_mut: 每个基因发生变异的概率（默认 0.02 即 2%）
	#  - sigma: 发生变异时添加的高斯/均匀噪声幅度（本实现使用均匀区间 [-sigma, sigma]）
	#  - rng_seed: 可选随机种子（>=0 则确定性）
	# 返回:
	#  - Array，新基因数组，元素已 clamp 到 [0,1]
	# 说明/边界:
	#  - 该实现对每个基因使用独立的伯努利试验决定是否变异；变异量为均匀随机
	#    而非正态分布；如需正态噪声可替换为 rng.randfnormal()
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
	# 单点交叉（Crossover）
	# 参数:
	#  - a: 父代基因数组 A
	#  - b: 父代基因数组 B
	#  - rng_seed: 可选随机种子（>=0 则确定性）
	# 返回:
	#  - Array，交叉后的子代基因数组（长度为 min(a.size(), b.size())）
	# 行为/边界:
	#  - 若两个输入数组长度小于等于 1，则直接返回 a 的拷贝（无法交叉）
	#  - 在 [1, n-1] 范围内随机选择一个切点，子代取 a[0:point] + b[point:n]
	#  - 可通过 rng_seed 获得确定性结果，便于测试
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
