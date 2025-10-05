# Growth utilities for the virus-aquarium project.
# 提供 x^k 的计算工具，常用于大小/能量/视野等随年龄的幂律生长曲线。
# 主要目标：方便在 k 属于 [0,3] 的范围内快速计算并保持数值/类型稳定性。

class_name GrowthUtils

static func pow_k(x: float, k: float) -> float:
	"""
	计算 x^k，并把 k 限制到 [0,3] 范围内以避免不期望的大指数或负数。
	参数:
		x: 基值（通常在 0..1 或正数范围）
		k: 指数，可以是浮点数，会被 clamp 到 [0.0, 3.0]
	返回:
		x 的 k 次幂（float）
	示例:
		GrowthUtils.pow_k(0.5, 2.0)  # 0.25
	"""
	k = clamp(float(k), 0.0, 3.0)
	# 对常见整数指数做快速路径
	if is_equal_approx(k, 0.0):
		return 1.0
	if is_equal_approx(k, 1.0):
		return x
	if is_equal_approx(k, 2.0):
		return x * x
	if is_equal_approx(k, 3.0):
		return x * x * x
	# 浮点幂（fallback）
	return pow(x, k)

static func pow_k_int(x: float, k: int) -> float:
	"""
	对整数指数 k 的快速计算，期望 k 在 0..3（但对其他整数也有退化处理）。
	"""
	if k <= 0:
		return 1.0
	elif k == 1:
		return x
	elif k == 2:
		return x * x
	elif k == 3:
		return x * x * x
	else:
		return pow(x, float(k))

static func series(x: float, k_min: int = 0, k_max: int = 3) -> Array:
	"""
	返回一个 Array，包含从 k_min 到 k_max（包含）的 x^k 值（按 k 升序排列）。
	会自动裁剪 k_min/k_max 到 [0,3] 的范围并保证整数步进。
	示例:
		GrowthUtils.series(0.5) -> [1.0, 0.5, 0.25, 0.125]
	"""
	k_min = max(0, int(k_min))
	k_max = min(3, int(k_max))
	var out := []
	for kk in range(k_min, k_max + 1):
		out.append(pow_k(x, float(kk)))
	return out

static func evaluate_list(x: float, ks: Array) -> Dictionary:
	"""
	对一组指数 ks（可以是整数或浮点）计算 x^k，并返回一个字典 mapping k->value。
	输入 ks 中的每一项会被 clamp 到 [0,3]（如为 float）或按整数处理（如为 int）。
	"""
	var out := {}
	for k in ks:
		if typeof(k) == TYPE_INT:
			out[str(k)] = pow_k_int(x, int(k))
		else:
			out[str(float(k))] = pow_k(x, float(k))
	return out
