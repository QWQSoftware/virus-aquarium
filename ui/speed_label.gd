extends Control

@onready
var speed_up_rect : Control = $HBoxContainer/HBoxContainer/TextureRect

@onready
var pause_rect : Control = $HBoxContainer/HBoxContainer/TextureRect3

@onready
var speed_down_rect : Control = $HBoxContainer/HBoxContainer/TextureRect2

# 跟踪各个操作是否已经触发过
var speed_up_triggered : bool = false
var speed_down_triggered : bool = false
var pause_triggered : bool = false

# 速度标签控制脚本

func _ready() -> void:
	# 初始设置为透明，等待信号触发渐入
	modulate.a = 0.0
	visible = true

# 渐入函数 - 通过信号连接调用
func fade_in() -> void:
	print("[SPEED_LABEL] Starting fade-in animation")
	
	# 创建渐入动画
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 1.0)  # 1秒渐入时间
	tween.tween_callback(func(): 
		print("[SPEED_LABEL] Fade-in complete")
	)

# 可选：渐出函数
func fade_out() -> void:
	print("[SPEED_LABEL] Starting fade-out animation")
	
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)  # 0.5秒渐出时间
	tween.tween_callback(func(): 
		print("[SPEED_LABEL] Fade-out complete")
	)

# 可选：立即显示/隐藏函数
func show_immediately() -> void:
	modulate.a = 1.0
	visible = true

func hide_immediately() -> void:
	modulate.a = 0.0
	visible = false

# 处理加速操作
func on_speed_up() -> void:
	if not speed_up_triggered:
		speed_up_triggered = true
		speed_up_rect.visible = false
		print("[SPEED_LABEL] Speed up triggered for first time - hiding speed up rect")

# 处理减速操作
func on_speed_down() -> void:
	if not speed_down_triggered:
		speed_down_triggered = true
		speed_down_rect.visible = false
		print("[SPEED_LABEL] Speed down triggered for first time - hiding speed down rect")

# 处理暂停操作
func on_pause() -> void:
	if not pause_triggered:
		pause_triggered = true
		pause_rect.visible = false
		print("[SPEED_LABEL] Pause triggered for first time - hiding pause rect")
