@tool
extends SkeletonModifier3D

@export var left_controller: XRController3D
@export var right_controller: XRController3D

@export_group("Smoothing")
@export_range(0.0, 1.0, 0.01) var smoothing: float = 0.0

@export_group("Left Grip")
@export var left_grip_bones: Array[FingerBoneConfig] = []
@export_group("Right Grip")
@export var right_grip_bones: Array[FingerBoneConfig] = []
@export_group("Left Trigger")
@export var left_trigger_bones: Array[FingerBoneConfig] = []
@export_group("Right Trigger")
@export var right_trigger_bones: Array[FingerBoneConfig] = []
@export_group("Left Face Buttons")
@export var left_face_bones: Array[FingerBoneConfig] = []
@export_group("Right Face Buttons")
@export var right_face_bones: Array[FingerBoneConfig] = []

var _smoothed := {}

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if not skeleton:
		return
	var delta := get_process_delta_time()

	_apply(left_grip_bones,     _smooth("lg", left_controller.get_float("grip")    if left_controller  else 0.0, delta), skeleton)
	_apply(right_grip_bones,    _smooth("rg", right_controller.get_float("grip")   if right_controller else 0.0, delta), skeleton)
	_apply(left_trigger_bones,  _smooth("lt", left_controller.get_float("trigger") if left_controller  else 0.0, delta), skeleton)
	_apply(right_trigger_bones, _smooth("rt", right_controller.get_float("trigger")if right_controller else 0.0, delta), skeleton)
	_apply(left_face_bones,     _smooth("lf", _face_value(left_controller),  delta), skeleton)
	_apply(right_face_bones,    _smooth("rf", _face_value(right_controller), delta), skeleton)

func _smooth(key: String, target: float, delta: float) -> float:
	if smoothing <= 0.0:
		_smoothed[key] = target
		return target
	var speed := 1.0 - smoothing
	var prev: float = _smoothed.get(key, target)
	var next := prev + (target - prev) * (1.0 - pow(speed, delta * 60.0))
	_smoothed[key] = next
	return next

func _apply(configs: Array[FingerBoneConfig], value: float, skeleton: Skeleton3D) -> void:
	for config in configs:
		if config.bone_name == "":
			continue
		var bone_idx := skeleton.find_bone(config.bone_name)
		if bone_idx == -1:
			continue
		var rest := skeleton.get_bone_rest(bone_idx).basis.get_rotation_quaternion()
		var curl := Quaternion(config.rotation_axis.normalized(), deg_to_rad(config.max_degrees * value))
		skeleton.set_bone_pose_rotation(bone_idx, rest * curl)

func _face_value(controller: XRController3D) -> float:
	if not controller:
		return 0.0
	return 1.0 if (controller.is_button_pressed("ax_button") or controller.is_button_pressed("by_button")) else 0.0
