extends Control

# 初始提示界面 - 当用户执行移动+视角操作时自动隐藏

# 信号：当提示已经隐藏时发射
signal hints_hidden

# 状态跟踪变量
var _w_pressed: bool = false
var _right_mouse_pressed: bool = false
var _mouse_moved: bool = false
var _shift_pressed: bool = false

# 是否已经隐藏过（避免重复隐藏）
var _has_been_hidden: bool = false

func _ready() -> void:
	# 初始设置为透明但可见
	visible = true
	modulate.a = 0.0
	print("[INIT_HINTS] Starting fade-in sequence...")
	
	# 4秒后开始渐入动画
	_start_fade_in_delayed()

func _start_fade_in_delayed() -> void:
	# 等待4秒后开始渐入
	var delay_timer = get_tree().create_timer(4.0)
	delay_timer.timeout.connect(_fade_in)

func _fade_in() -> void:
	print("[INIT_HINTS] Starting fade-in animation")
	
	# 创建渐入动画
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 1.0)  # 1秒渐入时间
	tween.tween_callback(func(): 
		print("[INIT_HINTS] Fade-in complete - press W + right mouse + move mouse + shift to hide")
	)

func _input(event: InputEvent) -> void:
	# 如果已经隐藏过就不再处理事件
	if _has_been_hidden:
		return
	
	# 处理键盘事件
	if event is InputEventKey:
		if event.keycode == KEY_W:
			_w_pressed = event.pressed
			_check_hide_condition()
		elif event.keycode == KEY_SHIFT:
			_shift_pressed = event.pressed
			_check_hide_condition()
	
	# 处理鼠标按键事件
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_right_mouse_pressed = event.pressed
			_check_hide_condition()
	
	# 处理鼠标移动事件
	elif event is InputEventMouseMotion:
		if _right_mouse_pressed:  # 只有在右键按下时才算作有效的鼠标移动
			_mouse_moved = true
			_check_hide_condition()

func _check_hide_condition() -> void:
	# 检查是否四个条件都满足
	if _w_pressed and _right_mouse_pressed and _mouse_moved and _shift_pressed:
		_hide_hints()

func _hide_hints() -> void:
	if not _has_been_hidden:
		_has_been_hidden = true
		print("[INIT_HINTS] All conditions met (W + Right Mouse + Mouse Move + Shift) - hiding hints")
		
		# 添加淡出动画
		var tween = create_tween()
		modulate.a = 1.0
		tween.tween_property(self, "modulate:a", 0.0, 0.5)
		tween.tween_callback(func(): 
			visible = false
			# 在动画完成后发射信号
			hints_hidden.emit()
			print("[INIT_HINTS] Signal 'hints_hidden' emitted")
		)

# 可选：提供重新显示提示的公共方法
func show_hints() -> void:
	visible = true
	_has_been_hidden = false
	_w_pressed = false
	_right_mouse_pressed = false
	_mouse_moved = false
	modulate.a = 0.0  # 重新开始时也是透明的
	print("[INIT_HINTS] Hints reset - starting fade-in sequence...")
	_start_fade_in_delayed()
