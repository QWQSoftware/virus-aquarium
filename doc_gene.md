# 位移速度
## 参数概述（新的实现）

大小由三项基因/表型控制（对应代码中的 phenotype 字段与基因槽）：

	- `initial_size_m`（基因槽 21）: 生物出生时的基础大小，单位米，映射区间 0.1 - 0.3 m。
	- `size_growth_scale`（基因槽 22）: 对数增长的尺度（单位米），控制年龄对大小的放大倍率，映射区间建议 0.05 - 1.0 m。
	- `size_k`（基因槽 23）: 对数曲线的底 k，映射到实数范围 2 - 100（越大表示随年龄增长越平缓）。

## 计算公式

运行时使用以下公式计算当前尺寸（代码中为 `current_size_m`）：

current_size_m = initial_size_m + log_k(age + 1) * size_growth_scale

其中 log_k(x) 表示以 k 为底的对数：

log_k(x) = ln(x) / ln(k)

说明：使用 age + 1 避免对数在 age=0 时的奇异性，且当 age=0 时 log_k(1)=0，从而保证初始大小等于 `initial_size_m`。

## 设计意图与行为

	- k 范围为 2..100：k 越大，ln(k) 越大，log_k(age+1) 越小，因此尺寸随年龄增长更平缓；k 越小，增长更陡峭。
	- `size_growth_scale` 控制对数增长的绝对贡献（以米为单位），方便把年龄增量映射为可感知的几厘米/分米等尺度。
	- 这种实现相比原来的 x^k（age^k）在年龄很大时增长更受控、曲线更平滑，且更容易通过调节 k 与 scale 达到想要的生长速度与饱和感。

## 示例（便于理解）

	- 初始参数：`initial_size_m = 0.12`, `size_k = 2`, `size_growth_scale = 0.1`。当 age=9s 时：
		- log_2(10) ≈ 3.32 → 增量 ≈ 0.332 m → current_size_m ≈ 0.452 m。
	- 初始参数：`initial_size_m = 0.12`, `size_k = 50`, `size_growth_scale = 0.1`。当 age=9s 时：
		- log_50(10) = ln(10)/ln(50) ≈ 0.430 → 增量 ≈ 0.043 m → current_size_m ≈ 0.163 m。

## 代码对应

	- `utils/genome.gd`：将基因槽 21 映射为 `initial_size_m`，22 映射为 `size_growth_scale`，23 映射为 `size_k`（2..100）。
	- `game/creature.gd`：使用公式 current_size_m = initial_size_m + (ln(age+1)/ln(k)) * size_growth_scale 计算并赋值给 `current_size_m`。

---

说明：交配与自我复制的能量参数支持两种表示方式：
- 绝对值（单位：能量点 p），字段名例如 `mating_required_energy_p`、`mating_energy_cost_p`、`selfrep_required_energy_p`、`selfrep_energy_cost_p`。
- 相对值（0.0 - 1.0），相对于成年最大能量 `max_energy_adult_p`，使用后缀 `_frac`，例如 `mating_required_energy_frac`、`mating_energy_cost_frac`、`selfrep_required_energy_frac`、`selfrep_energy_cost_frac`。

优先级：如果 phenotype 中同时存在 `_frac` 字段，运行时会使用 `_frac * max_energy_adult_p` 计算出实际的能量阈值/消耗；否则使用绝对 `_p` 字段。


## 自我复制时间 0.1-5.0s（更短可实现快速自复制）

## 自我复制冷却时间 0-30s（推荐目标：尽量短以支持快速重复）

## 自我复制所需能量值 p

## 自我复制所消耗的能量值 p

---

# 大小

使用球体scale进行计算

## 初始大小 0.1m - 0.3m

## 参数概述（新的实现）

大小由三项基因/表型控制（对应代码中的 phenotype 字段与基因槽）：

- `initial_size_m`（基因槽 21）: 生物出生时的基础大小，单位米，映射区间 0.1 - 0.3 m。
- `size_growth_scale`（基因槽 22）: 对数增长的尺度（单位米），控制年龄对大小的放大倍率，映射区间建议 0.05 - 1.0 m。
- `size_k`（基因槽 23）: 对数曲线的底 k，映射到实数范围 2 - 100（越大表示随年龄增长越平缓）。

## 计算公式

运行时使用以下公式计算当前尺寸（代码中为 `current_size_m`）：

current_size_m = initial_size_m + log_k(age + 1) * size_growth_scale

其中 log_k(x) 表示以 k 为底的对数：

log_k(x) = ln(x) / ln(k)

说明：使用 age + 1 避免对数在 age=0 时的奇异性，且当 age=0 时 log_k(1)=0，从而保证初始大小等于 `initial_size_m`。

## 设计意图与行为

- k 范围为 2..100：k 越大，ln(k) 越大，log_k(age+1) 越小，因此尺寸随年龄增长更平缓；k 越小，增长更陡峭。
- `size_growth_scale` 控制对数增长的绝对贡献（以米为单位），方便把年龄增量映射为可感知的几厘米/分米等尺度。
- 这种实现相比原来的 x^k（age^k）在年龄很大时增长更受控、曲线更平滑，且更容易通过调节 k 与 scale 达到想要的生长速度与饱和感。

## 示例（便于理解）

- 初始参数：`initial_size_m = 0.12`, `size_k = 2`, `size_growth_scale = 0.1`。当 age=9s 时：
	- log_2(10) ≈ 3.32 → 增量 ≈ 0.332 m → current_size_m ≈ 0.452 m。
- 初始参数：`initial_size_m = 0.12`, `size_k = 50`, `size_growth_scale = 0.1`。当 age=9s 时：
	- log_50(10) = ln(10)/ln(50) ≈ 0.430 → 增量 ≈ 0.043 m → current_size_m ≈ 0.163 m。

## 代码对应

- `utils/genome.gd`：将基因槽 21 映射为 `initial_size_m`，22 映射为 `size_growth_scale`，23 映射为 `size_k`（2..100）。
- `game/creature.gd`：使用公式 current_size_m = initial_size_m + (ln(age+1)/ln(k)) * size_growth_scale 计算并赋值给 `current_size_m`。

---

---

# 捕食

## 初始攻击力 0-5p

## 成年攻击力 1-15p

## 攻击力成长曲线的k参数 x^k

## 攻击CD 1-10s

---

# 能量

## 初始最大能量大小 0-20 p

## 成年最大能量大小 50-150 p

## k能量槽曲线 x^k x为年龄


## 初始能量消耗速率 0.1-0.5 p/s

## 成年能量消耗速率 0.6-1 p/s

## 能量消耗速率增长曲线 x^k x为年龄


## 自身能量产生速率（在光照下） 0-5 p/s

## 作为食物时提供的最低能量 10-150 p/s

## 进食时间 0.5-1.0s

## 进食欲望曲线 x^k

---

# 血量

## 初始最大血量 1-20 p

## 成年最大血量 25-100 p

## 血量槽成长曲线 x^k


## 初始血量回复速度 0.5-1 p/s

## 成年血量回复速度 2-5 p/s

## 血量回复曲线 x^k

---

# 表面

## 所提供的表面附着点类型 （1,2,3..9）

## 所提供的附着点数量 (0-3)

## 最大附着点积累值 (1-10)

基于附着点连成一串的生物的的累计数量值

例如 1->2->3
1号生物该值为0
2号生物附着在1上为1
3号生物附着在2上，积累下来为2

当 1->2 1->3 1->4
时，若1=0,则2,3,4的该值为1

---

# 精力

## 精力值 （0为植物） 0-100 p

## 休息时回复精力速度 1-25 p/s

## 休息偏好附着点类型 （0,1,2,3...9） 0为附着基础表面



---

# 侦察与反侦察

## 颜色 HSV  H: 0-1

隐蔽方式计算，目标生物周围50m内 H差值为0.1的生物数量，洞察力大于该生物数量值时认为可以看到该生物

## 初始洞察力 1-4 p

## 成年洞察力 1-30 p

## 洞察力增长曲线 x^k


## 初始视野范围 20-50m

## 成年视野范围 60-500m

## 视野范围增长曲线 x^k

---

# 单纯装饰

## x方向scale 0.2-1.0

## z方向scale 0.2-1.0

---

# 决策权重曲线

决策均基于 x^k曲线（A）和 -x^k + 1曲线（B）

k值为 0-3 （可能）

繁殖决策权重 k 基于能量值进行计算 A曲线

休息决策权重 k 基于精力值进行计算 B曲线

觅食决策权重 k 基于能量值进行计算 B曲线

---

# 运行时计算

## 当前年龄

## 当前全局变换

## 目标方向

## 当前血量

## 当前能量

## 当前精力值



## 休息欲望

## 觅食欲望

## 繁殖欲望



## 附着点1

## 附着点2

## 附着点3

## 附着点4

## 附着点5

## 当前附着位置 目标实体+附着点ID
