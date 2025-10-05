class_name FreeLookCamera extends Camera3D

# 射线碰撞状态信号
signal ray_collision_detected(collision_point: Vector3, collider: Node3D)
signal ray_collision_simple()  # 无参数的碰撞信号
signal ray_collision_lost()
signal ray_collision_position_updated(collision_point: Vector3)  # 实时更新碰撞位置信号
signal ball_size_updated(radius: int)  # 球体大小更新信号

@onready
var RayCast : RayCast3D = $RayCast3D
@onready
var BallRangeMesh : MeshInstance3D = $RayCast3D/MeshInstance3D

# Ball radius control (1-4m range)
var BallRadius : float = 1.0
const MIN_BALL_RADIUS = 1.0
const MAX_BALL_RADIUS = 3.0

# Modifier keys' speed multiplier
const SHIFT_MULTIPLIER = 2.5
const ALT_MULTIPLIER = 1.0 / SHIFT_MULTIPLIER


@export_range(0.0, 1.0) var sensitivity: float = 0.25

# Mouse state
var _mouse_position = Vector2(0.0, 0.0)
var _total_pitch = 0.0

# Movement state
var _direction = Vector3(0.0, 0.0, 0.0)
var _velocity = Vector3(0.0, 0.0, 0.0)

# Collision state tracking
var _was_colliding: bool = false
var _acceleration = 30
var _deceleration = -10
var _vel_multiplier = 4

# Keyboard state
var _w = false
var _s = false
var _a = false
var _d = false
var _q = false
var _e = false
var _shift = false
var _alt = false

func _ready():
	# Initialize ball mesh scale to match the default radius
	_update_ball_mesh_scale()

func _input(event):
	# Receives mouse motion
	if event is InputEventMouseMotion:
		_mouse_position = event.relative
	
	# Receives mouse button input
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT: # Only allows rotation if right click down
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE)
			MOUSE_BUTTON_WHEEL_UP: # Increases ball radius
				if not event.pressed:  # Only trigger on release (just_released)
					var old_radius = BallRadius
					BallRadius = clamp(BallRadius + 1.0, MIN_BALL_RADIUS, MAX_BALL_RADIUS)
					if old_radius != BallRadius:  # 只在大小实际改变时发射信号
						ball_size_updated.emit(int(BallRadius))
					print("[CAMERA] Ball radius change: %.0fm -> %.0fm" % [old_radius, BallRadius])
					_update_ball_mesh_scale()
			MOUSE_BUTTON_WHEEL_DOWN: # Decreases ball radius
				if not event.is_pressed():  # Only trigger on release (just_released)
					var old_radius = BallRadius
					BallRadius = clamp(BallRadius - 1.0, MIN_BALL_RADIUS, MAX_BALL_RADIUS)
					if old_radius != BallRadius:  # 只在大小实际改变时发射信号
						ball_size_updated.emit(int(BallRadius))
					print("[CAMERA] Ball radius change: %.0fm -> %.0fm" % [old_radius, BallRadius])
					_update_ball_mesh_scale()

	# Receives key input
	if event is InputEventKey:
		match event.keycode:
			KEY_W:
				_w = event.pressed
			KEY_S:
				_s = event.pressed
			KEY_A:
				_a = event.pressed
			KEY_D:
				_d = event.pressed
			KEY_Q:
				_q = event.pressed
			KEY_E:
				_e = event.pressed
			KEY_SHIFT:
				_shift = event.pressed
			KEY_ALT:
				_alt = event.pressed

# Updates the ball mesh scale to match the current BallRadius
func _update_ball_mesh_scale():
	if BallRangeMesh and BallRangeMesh.mesh:
		# Scale the mesh to match the ball radius
		# Assuming the original mesh has a radius of 1.0
		var new_scale = Vector3.ONE * BallRadius
		BallRangeMesh.scale = new_scale
		print("[CAMERA] Updating ball scale to: %s (radius: %.0fm)" % [str(new_scale), BallRadius])
		
		# Debug: Also check the actual mesh properties
		if BallRangeMesh.mesh is SphereMesh:
			var sphere_mesh = BallRangeMesh.mesh as SphereMesh
			print("[CAMERA] Original sphere radius: %.2fm, height: %.2fm" % [sphere_mesh.radius, sphere_mesh.height])
	else:
		print("[CAMERA] Warning: BallRangeMesh or mesh is null!")

# Updates mouselook and movement every frame
func _process(delta):
	_update_mouselook()
	_update_movement(delta)
	
	var is_currently_colliding = RayCast.is_colliding()
	
	if is_currently_colliding:
		# Only show ball when there's a collision
		BallRangeMesh.visible = true
		# Use global_position instead of global_transform.origin to preserve scale
		var collision_point = RayCast.get_collision_point()
		BallRangeMesh.global_position = collision_point
		
		# 实时发射碰撞位置更新信号（每帧都发射）
		ray_collision_position_updated.emit(collision_point)
		
		# 发射碰撞检测信号（仅在状态变化时）
		if not _was_colliding:
			var collider = RayCast.get_collider()
			ray_collision_detected.emit(collision_point, collider)
			ray_collision_simple.emit()  # 同时发射无参数信号
			ball_size_updated.emit(int(BallRadius))  # 发射球体大小更新信号
			print("[CAMERA] Ray collision detected at: ", collision_point, " with: ", collider.name if collider else "null")
			print("[CAMERA] Ball size updated: ", int(BallRadius))
	else:
		# Hide ball when no collision detected
		BallRangeMesh.visible = false
		
		# 发射碰撞丢失信号（仅在状态变化时）
		if _was_colliding:
			ray_collision_lost.emit()
			print("[CAMERA] Ray collision lost")
	
	# 更新碰撞状态
	_was_colliding = is_currently_colliding
	

# Updates camera movement
func _update_movement(delta):
	# Computes desired direction from key states
	_direction = Vector3(
		(_d as float) - (_a as float), 
		(_e as float) - (_q as float),
		(_s as float) - (_w as float)
	)
	
	# Computes the change in velocity due to desired direction and "drag"
	# The "drag" is a constant acceleration on the camera to bring it's velocity to 0
	var offset = _direction.normalized() * _acceleration * _vel_multiplier * delta \
		+ _velocity.normalized() * _deceleration * _vel_multiplier * delta
	
	# Compute modifiers' speed multiplier
	var speed_multi = 1
	if _shift: speed_multi *= SHIFT_MULTIPLIER
	if _alt: speed_multi *= ALT_MULTIPLIER
	
	# Checks if we should bother translating the camera
	if _direction == Vector3.ZERO and offset.length_squared() > _velocity.length_squared():
		# Sets the velocity to 0 to prevent jittering due to imperfect deceleration
		_velocity = Vector3.ZERO
	else:
		# Clamps speed to stay within maximum value (_vel_multiplier)
		_velocity.x = clamp(_velocity.x + offset.x, -_vel_multiplier, _vel_multiplier)
		_velocity.y = clamp(_velocity.y + offset.y, -_vel_multiplier, _vel_multiplier)
		_velocity.z = clamp(_velocity.z + offset.z, -_vel_multiplier, _vel_multiplier)
	
		translate(_velocity * delta * speed_multi)

# Updates mouse look 
func _update_mouselook():
	# Only rotates mouse if the mouse is captured
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_mouse_position *= sensitivity
		var yaw = _mouse_position.x
		var pitch = _mouse_position.y
		_mouse_position = Vector2(0, 0)
		
		# Prevents looking up/down too far
		pitch = clamp(pitch, -90 - _total_pitch, 90 - _total_pitch)
		_total_pitch += pitch
	
		rotate_y(deg_to_rad(-yaw))
		rotate_object_local(Vector3(1,0,0), deg_to_rad(-pitch))
