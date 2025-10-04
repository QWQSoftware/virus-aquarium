extends Node3D

@onready
var multiMeshInstance = $MultiMeshInstance3D

@onready
var mediums : Array = [
	$Medium01,
	$Medium02,
	$Medium03
]

# 生物实例列表（运行时创建）
var creatures : Array = []


const MeshSamplerScript = preload("res://utils/mesh_sampler.gd")
const CreatureScript = preload("res://game/creature.gd")


# MeshSampler is loaded on-demand below to avoid static preload issues in this environment.

# medium properties

func fill_multimesh_from_mediums(samples_per_unit: float = 1.0, total_samples: int = 0, _instance_scale = 0.1) -> void:
	# 遍历 mediums，采样每个 MeshInstance3D 的表面，并把位置写入 multiMeshInstance
	if not multiMeshInstance:
		return

	var all_samples := []
	for m in mediums:
		if m and m is MeshInstance3D:
			var samples = sample_mesh_surface(m, samples_per_unit, total_samples)
			# 合并样本（实例缩放由 instance_scale 参数控制，不跟随源节点）
			for s in samples:
				all_samples.append({"position": s["position"], "normal": s["normal"]})

	# 设置 MultiMesh 实例数量
	var mm = multiMeshInstance.multimesh
	if mm == null:
		return

	mm.instance_count = all_samples.size()

	# 填充每个实例的 transform（位置 + 使用法线构建朝向）
	for i in range(all_samples.size()):
		var entry = all_samples[i]
		var pos: Vector3 = entry["position"]
		var normal: Vector3 = entry["normal"]
		# 构建一个简单的 transform：使 z 轴对准法线（或 y 轴，取决于你的实例朝向需求）
		var up = Vector3.UP
		if abs(up.dot(normal)) > 0.999: # 避免共线
			up = Vector3.FORWARD
		var b = Basis()
		# 使用 Gram-Schmidt 创建正交基
		var z = normal.normalized()
		var x = up.cross(z).normalized()
		var y = z.cross(x).normalized()

		# 计算每实例缩放：支持 float（均匀缩放）、Vector3（非等比）或 Array（按索引/循环）
		var inst_scale_vec = Vector3.ONE

		# 应用非等比缩放到 basis
		b.x = x * inst_scale_vec.x
		b.y = y * inst_scale_vec.y
		b.z = z * inst_scale_vec.z

		var t = Transform3D(b, pos)
		mm.set_instance_transform(i, t)

		# 随机颜色：使用 RNG 生成 HSV，便于得到鲜艳的颜色
		var rng = RandomNumberGenerator.new()
		rng.randomize()
		var h = rng.randf()
		var s = rng.randf_range(0.6, 1.0)
		var v = rng.randf_range(0.6, 1.0)
		var col = Color.from_hsv(h, s, v)
		# 尝试用 set_instance_color（Godot 4），否则把颜色写入 custom_data（vec4）作为回退
		if mm.has_method("set_instance_color"):
			mm.set_instance_color(i, col)
		else:
			# custom_data 是一个 Vector4 - 存储 RGBA
			if mm.has_method("set_instance_custom_data"):
				mm.set_instance_custom_data(i, Vector4(col.r, col.g, col.b, col.a))
			# 否则不设置颜色

	# 如果需要其他实例化属性（颜色、尺度等），可以在这里设置


# Mesh sampling functions were migrated to res://utils/mesh_sampler.gd as MeshSampler
# Use MeshSampler.sample_mesh_surface(mesh_instance, samples_per_unit, total_samples, seed)

func sample_mesh_surface(mesh_instance: MeshInstance3D, samples_per_unit: float = 1.0, total_samples: int = 0) -> Array:
	# 兼容 wrapper：调用迁移到 MeshSampler
	return MeshSampler.sample_mesh_surface(mesh_instance, samples_per_unit, total_samples)

# creature properties




func _ready() -> void:
	# 示例：启动时填充 multimesh（每个实例使用统一缩放 0.1）
	fill_multimesh_from_mediums(1.0, 0, 1.0)
	# 创建一个示例 Creature 并加入 creatures 列表（用于运行时测试）
	var _gene = GenomeUtils.random_genome()
	var creature = CreatureScript.new(_gene, Vector3.ZERO)
	creatures.append(creature)

	return
