extends RefCounted

class_name Creature

# 数据驱动的 Creature 类（从 game.gd 抽离）
func _init(genome: Array, pos: Vector3 = Vector3.ZERO) -> void:
    self.genome = genome.duplicate()
    # phenotype 是 decode 后的物理/行为参数字典
    self.phenotype = GenomeUtils.decode_genome(self.genome)
    self.age_s = 0.0
    self.is_alive = true
    # 初始资源/状态（使用 phenotype 提供的范围作为参考）
    self.health_p = self.phenotype.get("health_init_p", 10.0)
    self.energy_p = self.phenotype.get("max_energy_init_p", 10.0)
    self.stamina_p = self.phenotype.get("stamina_max_p", 10.0)
    self.position = pos
    self.global_transform = Transform3D(Basis(), pos)
    self.is_plant = (self.energy_p <= 0.0 and self.phenotype.get("photosynthesis_rate_p_per_s", 0.0) > 0.0)
    self.attachments = []

func update(delta: float) -> void:
    if not self.is_alive:
        return
    self.age_s += delta
    var photos = self.phenotype.get("photosynthesis_rate_p_per_s", 0.0)
    if photos > 0.0:
        self.energy_p = min(self.energy_p + photos * delta, self.phenotype.get("max_energy_adult_p", 100.0))
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
