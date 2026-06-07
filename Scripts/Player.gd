extends Node

@export var max_jump_speed:float = 7
@export var drag:float = 10
@export var jump_multiplier:float = 1
@export var velocity_limit:float = 0.4
@export var velocity_history_size:int = 8
@export var hand_clip_distance: float = 0.5
@export var hand_slide_friction: float = 0.05
@export var hand_vibration_duration: float = 0.08
@export var hand_vibration_amplitude: float = 0.2
@export var tap_sound: AudioStream

enum TurnMode { NONE, SMOOTH, SNAP }
enum TurnController { LEFT, RIGHT }

@export_group("Turning")
@export var turn_mode: TurnMode = TurnMode.SNAP
@export var turn_controller: TurnController = TurnController.RIGHT
@export_range(0, 9, 1) var turn_speed_level: int = 5
@export var snap_turn_deadzone: float = 0.5
@export var turn_joystick_deadzone: float = 0.2

@onready var player:CharacterBody3D = $Player
@onready var player_collision:CollisionShape3D = $Player/Collision
@onready var head:Node3D = $Player/XROrigin3D/Head
@onready var xr_origin:XROrigin3D = $Player/XROrigin3D
@onready var left_hand:Node3D = $Player/XROrigin3D/LeftHand/Follow
@onready var right_hand:Node3D = $Player/XROrigin3D/RightHand/Follow
@onready var left_hand_follower:CharacterBody3D = $LeftHandFollower
@onready var right_hand_follower:CharacterBody3D = $RightHandFollower
@onready var left_controller: XRController3D = $Player/XROrigin3D/LeftHand
@onready var right_controller: XRController3D = $Player/XROrigin3D/RightHand
@onready var left_hand_audio: AudioStreamPlayer3D = $LeftHandFollower/Audio
@onready var right_hand_audio: AudioStreamPlayer3D = $RightHandFollower/Audio

var velocity_history:Array[Vector3] = []
var previous_position:Vector3
var velocity_average:Vector3
var velocity_index:int

var is_moving:bool
var is_left_hand_colliding:bool
var is_right_hand_colliding:bool

var snap_turn_ready: bool = true

const TURN_DEGREES: Array[float] = [20.0, 40.0, 60.0, 80.0, 100.0, 130.0, 170.0, 220.0, 290.0, 360.0]

func _ready() -> void:
	init()

func _process(delta:float) -> void:
	player_collision.global_position = head.global_position - Vector3(0, 0.25, 0)
	
	if not player.is_on_floor():
		player.velocity += Vector3.DOWN * delta * 9.8
	else:
		player.velocity *= 1 - (drag * delta * cos(player.get_floor_angle()))
	move_followers(true, delta)

	var left_hand_velocity = left_hand_follower.global_position - left_hand.global_position
	var right_hand_velocity = right_hand_follower.global_position - right_hand.global_position
	var movement = Vector3.ZERO
	
	if is_left_hand_colliding and is_right_hand_colliding:
		movement = (left_hand_velocity + right_hand_velocity) / 2
	else:
		movement = (left_hand_velocity if is_left_hand_colliding else Vector3.ZERO) + (right_hand_velocity if is_right_hand_colliding else Vector3.ZERO) 
	
	if is_left_hand_colliding or is_right_hand_colliding:
		player.velocity = movement / delta
		is_moving = true
	elif is_moving:
		if velocity_average.length() > velocity_limit:
			if velocity_average.length() * jump_multiplier > max_jump_speed:
				player.velocity = velocity_average.normalized() * max_jump_speed
			else:
				player.velocity = jump_multiplier * velocity_average
		else:
			player.velocity = Vector3.ZERO
		is_moving = false
	
	player.move_and_slide()
	
	handle_turning(delta)
	
	move_followers(false, delta)
	
	store_velocities(delta)

func _get_turn_degrees() -> float:
	return TURN_DEGREES[clamp(turn_speed_level, 0, 9)]

func handle_turning(delta: float) -> void:
	if turn_mode == TurnMode.NONE:
		return
	
	var controller: XRController3D = right_controller if turn_controller == TurnController.RIGHT else left_controller
	var joystick_x: float = controller.get_vector2("primary").x
	
	if abs(joystick_x) < turn_joystick_deadzone:
		if turn_mode == TurnMode.SNAP:
			snap_turn_ready = true
		return
	
	match turn_mode:
		TurnMode.SMOOTH:
			_apply_smooth_turn(joystick_x, delta)
		TurnMode.SNAP:
			_apply_snap_turn(joystick_x)

func _apply_smooth_turn(joystick_x: float, delta: float) -> void:
	var deg_per_second = _get_turn_degrees()
	var degrees = joystick_x * deg_per_second * delta
	_rotate_player_yaw(degrees)

func _apply_snap_turn(joystick_x: float) -> void:
	if not snap_turn_ready:
		return
	if abs(joystick_x) >= snap_turn_deadzone:
		_rotate_player_yaw((_get_turn_degrees() / 4.0) * sign(joystick_x))
		snap_turn_ready = false

func _rotate_player_yaw(degrees: float) -> void:
	var rad = deg_to_rad(-degrees)
	
	var pivot: Vector3
	if is_left_hand_colliding and is_right_hand_colliding:
		pivot = (left_hand.global_position + right_hand.global_position) / 2.0
	elif is_left_hand_colliding:
		pivot = left_hand.global_position
	elif is_right_hand_colliding:
		pivot = right_hand.global_position
	else:
		pivot = head.global_position
	
	player.global_position = pivot + (player.global_position - pivot).rotated(Vector3.UP, rad)
	player.rotation.y += rad
	
	xr_origin.global_position = pivot + (xr_origin.global_position - pivot).rotated(Vector3.UP, rad)
	xr_origin.rotation.y += rad

func move_followers(include_velocity: bool, delta: float) -> void:
	delta = clampf(delta, 0.0005, 1)
	var additional_force = Vector3.DOWN * 2 * 9.8 * delta * delta if include_velocity else Vector3.ZERO

	if left_hand_follower.global_position.distance_to(left_hand.global_position) > hand_clip_distance:
		left_hand_follower.global_position = left_hand.global_position

	if right_hand_follower.global_position.distance_to(right_hand.global_position) > hand_clip_distance:
		right_hand_follower.global_position = right_hand.global_position

	left_hand_follower.velocity = (left_hand.global_position - left_hand_follower.global_position) + additional_force
	right_hand_follower.velocity = (right_hand.global_position - right_hand_follower.global_position) + additional_force
	
	left_hand_follower.global_rotation = left_hand.global_rotation
	right_hand_follower.global_rotation = right_hand.global_rotation

	var left_collision = left_hand_follower.move_and_collide(left_hand_follower.velocity, false, 0.0000001, false)
	var right_collision = right_hand_follower.move_and_collide(right_hand_follower.velocity, false, 0.0000001, false)

	if include_velocity:
		var newly_left = left_collision != null and not is_left_hand_colliding
		var newly_right = right_collision != null and not is_right_hand_colliding

		is_left_hand_colliding = left_collision != null
		is_right_hand_colliding = right_collision != null

		if newly_left:
			trigger_haptic(left_controller, hand_vibration_amplitude, hand_vibration_duration)
			play_tap_sound(left_hand_audio, left_collision)
		if newly_right:
			trigger_haptic(right_controller, hand_vibration_amplitude, hand_vibration_duration)
			play_tap_sound(right_hand_audio, right_collision)

func trigger_haptic(controller: XRController3D, amplitude: float, duration: float) -> void:
	controller.trigger_haptic_pulse("haptic", amplitude, 50.0, duration, 0.0)
	
func play_tap_sound(audio: AudioStreamPlayer3D, collision: KinematicCollision3D) -> void:
	if tap_sound == null:
		return
	audio.stream = tap_sound
	audio.pitch_scale = randf_range(0.9, 1.1)
	audio.play()

func init() -> void:
	for i in range(velocity_history_size):
		velocity_history.append(Vector3.ZERO)
	previous_position = player.global_position

func store_velocities(delta:float) -> void:
	velocity_index = (velocity_index + 1) % velocity_history_size
	var oldest_velocity := velocity_history[velocity_index]
	var current_velocity := (player.global_position - previous_position) / delta
	velocity_average += (current_velocity - oldest_velocity) / float(velocity_history_size);
	velocity_history[velocity_index] = current_velocity
	previous_position = player.global_position
