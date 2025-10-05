extends Control

@onready
var radius_label = $MarginContainer2/HBoxContainer/Label

func _ready() -> void:
	# 初始设置为透明但可见
	visible = true
	modulate.a = 0.0
	print("[PLAY_HINTS] Ready - initialized as transparent")

# 渐入函数 - 1秒内从透明变为不透明
func fade_in() -> void:
	print("[PLAY_HINTS] Starting fade-in animation")
	visible = true
	
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 1.0)
	tween.tween_callback(func(): 
		print("[PLAY_HINTS] Fade-in complete")
	)

# 渐出函数 - 1秒内从不透明变为透明并隐藏
func fade_out() -> void:
	print("[PLAY_HINTS] Starting fade-out animation")
	
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func(): 
		visible = false
		print("[PLAY_HINTS] Fade-out complete - now hidden")
	)

# 立即显示（无动画）
func show_immediately() -> void:
	visible = true
	modulate.a = 1.0
	print("[PLAY_HINTS] Shown immediately")

# 立即隐藏（无动画）
func hide_immediately() -> void:
	visible = false
	modulate.a = 0.0
	print("[PLAY_HINTS] Hidden immediately")

func update_radius(radius : int) -> void:
	radius_label.text = "X" + String.num_int64(radius)
