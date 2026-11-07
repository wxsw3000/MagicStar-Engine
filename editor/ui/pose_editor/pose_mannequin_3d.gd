# editor/ui/pose_editor/pose_mannequin_3d.gd
# AVG Studio 专属 3D 姿态人偶系统：支持解剖学骨骼层级、OpenPose 骨架着色与常用立绘动作预设
class_name PoseMannequin3D
extends Node3D

signal pose_changed(preset_name: String)

# 关节层级节点
var root_node: Node3D
var hips_node: Node3D
var torso_node: Node3D
var neck_node: Node3D
var head_node: Node3D

var shoulder_l: Node3D
var upper_arm_l: Node3D
var lower_arm_l: Node3D
var hand_l: Node3D

var shoulder_r: Node3D
var upper_arm_r: Node3D
var lower_arm_r: Node3D
var hand_r: Node3D

var hip_l: Node3D
var upper_leg_l: Node3D
var lower_leg_l: Node3D
var foot_l: Node3D

var hip_r: Node3D
var upper_leg_r: Node3D
var lower_leg_r: Node3D
var foot_r: Node3D

# 材质与模式
var display_mode: String = "dummy" # "dummy" or "openpose"
var mesh_instances: Array[MeshInstance3D] = []
var dummy_mat_body: StandardMaterial3D
var dummy_mat_joints: StandardMaterial3D
var dummy_mat_face: StandardMaterial3D

# 当前动作
var current_preset: String = "standing_calm"

# 预设动作字典 (角度单位: 度)
const PRESETS = {
	"standing_calm": {
		"name": "标准站姿·冷静从容",
		"prompt_zh": "自然端正站姿，双手自然下垂，神色从容冷静",
		"prompt_en": "standing calmly, upright posture, confident steady stance",
		"torso": Vector3(0, 0, 0),
		"head": Vector3(0, 0, 0),
		"shoulder_l": Vector3(0, 0, -8),
		"lower_arm_l": Vector3(-5, 0, 0),
		"shoulder_r": Vector3(0, 0, 8),
		"lower_arm_r": Vector3(-5, 0, 0),
		"hip_l": Vector3(0, 0, -3),
		"lower_leg_l": Vector3(0, 0, 0),
		"hip_r": Vector3(0, 0, 3),
		"lower_leg_r": Vector3(0, 0, 0)
	},
	"crossed_arms": {
		"name": "双手抱胸·严谨深思",
		"prompt_zh": "双手抱胸交叉于胸前，身姿严谨沉稳，带有审视气场",
		"prompt_en": "arms crossed over chest, folding arms across chest, serious analytical posture",
		"torso": Vector3(2, 0, 0),
		"head": Vector3(4, -6, -2),
		"shoulder_l": Vector3(-35, 42, -28),
		"lower_arm_l": Vector3(-65, 45, 0),
		"shoulder_r": Vector3(-35, -42, 28),
		"lower_arm_r": Vector3(-65, -45, 0),
		"hip_l": Vector3(0, 0, -4),
		"lower_leg_l": Vector3(0, 0, 0),
		"hip_r": Vector3(0, 0, 4),
		"lower_leg_r": Vector3(0, 0, 0)
	},
	"chin_touch": {
		"name": "手托下巴·推理破案",
		"prompt_zh": "单手托住下巴，作低头沉思推演姿态",
		"prompt_en": "hand on chin, touching chin, thoughtful deductive posture",
		"torso": Vector3(3, -4, 0),
		"head": Vector3(-4, 12, -4),
		"shoulder_l": Vector3(-20, 26, -14),
		"lower_arm_l": Vector3(-50, 18, 0),
		"shoulder_r": Vector3(-60, -22, 34),
		"lower_arm_r": Vector3(-102, -26, 0),
		"hip_l": Vector3(0, 0, -3),
		"lower_leg_l": Vector3(0, 0, 0),
		"hip_r": Vector3(0, 0, 3),
		"lower_leg_r": Vector3(0, 0, 0)
	},
	"pointing_accuse": {
		"name": "一指指证·真凶就是你",
		"prompt_zh": "单手抬起伸出食指直指前方，手臂前伸指证真凶的破案魄力姿态",
		"prompt_en": "pointing finger forward accusatorially, one arm outstretched pointing directly forward at viewer, dramatic deductive confrontation",
		"torso": Vector3(-3, 6, 0),
		"head": Vector3(2, -6, 0),
		"shoulder_l": Vector3(12, 16, -24),
		"lower_arm_l": Vector3(-25, 0, 0),
		"shoulder_r": Vector3(-88, 4, 2),
		"lower_arm_r": Vector3(0, 0, 0),
		"hip_l": Vector3(-4, 0, -4),
		"lower_leg_l": Vector3(4, 0, 0),
		"hip_r": Vector3(4, 0, 4),
		"lower_leg_r": Vector3(-4, 0, 0)
	},
	"hands_on_hips": {
		"name": "双手叉腰·自信傲然",
		"prompt_zh": "双手叉腰，身姿挺拔自信傲然",
		"prompt_en": "hands on hips, confident stance",
		"torso": Vector3(0, 0, 0),
		"head": Vector3(-2, 0, 0),
		"shoulder_l": Vector3(14, 22, -38),
		"lower_arm_l": Vector3(-76, 0, 0),
		"shoulder_r": Vector3(14, -22, 38),
		"lower_arm_r": Vector3(-76, 0, 0),
		"hip_l": Vector3(0, 0, -5),
		"lower_leg_l": Vector3(0, 0, 0),
		"hip_r": Vector3(0, 0, 5),
		"lower_leg_r": Vector3(0, 0, 0)
	},
	"pocket_hands": {
		"name": "插兜侧立·冷酷风衣",
		"prompt_zh": "双手插兜微侧身站立，潇洒冷峻",
		"prompt_en": "hands in pockets, standing slightly sideways, cool detective posture",
		"torso": Vector3(0, 18, 0),
		"head": Vector3(0, -14, 0),
		"shoulder_l": Vector3(6, 14, -18),
		"lower_arm_l": Vector3(-48, 6, 0),
		"shoulder_r": Vector3(6, -14, 18),
		"lower_arm_r": Vector3(-48, -6, 0),
		"hip_l": Vector3(0, 0, -3),
		"lower_leg_l": Vector3(0, 0, 0),
		"hip_r": Vector3(0, 0, 3),
		"lower_leg_r": Vector3(0, 0, 0)
	},
	"shrug_spread": {
		"name": "摊手无奈·无可奉告",
		"prompt_zh": "摊开双手耸肩，无可奉告的无奈姿态",
		"prompt_en": "shrugging, spreading hands, helpless gesture",
		"torso": Vector3(2, 0, 0),
		"head": Vector3(4, 6, 8),
		"shoulder_l": Vector3(-26, 22, -44),
		"lower_arm_l": Vector3(-58, 36, 0),
		"shoulder_r": Vector3(-26, -22, 44),
		"lower_arm_r": Vector3(-58, -36, 0),
		"hip_l": Vector3(0, 0, -3),
		"lower_leg_l": Vector3(0, 0, 0),
		"hip_r": Vector3(0, 0, 3),
		"lower_leg_r": Vector3(0, 0, 0)
	},
	"hold_clue": {
		"name": "托举物证·细微观察",
		"prompt_zh": "单手托举关键物证于胸前，目光锐利凝视观察",
		"prompt_en": "holding up a small clue or evidence in hand, examining closely",
		"torso": Vector3(0, -8, 0),
		"head": Vector3(14, -18, 2),
		"shoulder_l": Vector3(-64, 24, -18),
		"lower_arm_l": Vector3(-52, 16, 0),
		"shoulder_r": Vector3(8, -12, 14),
		"lower_arm_r": Vector3(-24, 0, 0),
		"hip_l": Vector3(0, 0, -3),
		"lower_leg_l": Vector3(0, 0, 0),
		"hip_r": Vector3(0, 0, 3),
		"lower_leg_r": Vector3(0, 0, 0)
	}
}

static func get_preset_prompt(preset_key: String, is_zh: bool = true) -> String:
	if PRESETS.has(preset_key):
		return PRESETS[preset_key].get("prompt_zh" if is_zh else "prompt_en", "")
	return ""

func _ready() -> void:
	_init_materials()
	_build_skeleton_hierarchy()
	apply_preset("standing_calm")

func _init_materials() -> void:
	# 3D 现代灰模材质
	dummy_mat_body = StandardMaterial3D.new()
	dummy_mat_body.albedo_color = Color(0.24, 0.28, 0.35)
	dummy_mat_body.roughness = 0.4
	dummy_mat_body.metallic = 0.15

	dummy_mat_joints = StandardMaterial3D.new()
	dummy_mat_joints.albedo_color = Color(0.85, 0.70, 0.35)
	dummy_mat_joints.roughness = 0.3
	dummy_mat_joints.metallic = 0.6

	dummy_mat_face = StandardMaterial3D.new()
	dummy_mat_face.albedo_color = Color(0.35, 0.42, 0.52)
	dummy_mat_face.roughness = 0.5

func _build_skeleton_hierarchy() -> void:
	root_node = Node3D.new()
	root_node.name = "Root"
	add_child(root_node)

	# 骨盆 Hips
	hips_node = Node3D.new()
	hips_node.name = "Hips"
	hips_node.position = Vector3(0, 0.95, 0)
	root_node.add_child(hips_node)
	_create_capsule_mesh(hips_node, Vector3(0.22, 0.16, 0.15), Vector3(0, 0, 0), "hips", Color(0.2, 0.7, 0.4))

	# 躯干 Torso / 胸腔
	torso_node = Node3D.new()
	torso_node.name = "Torso"
	torso_node.position = Vector3(0, 0.14, 0)
	hips_node.add_child(torso_node)
	_create_capsule_mesh(torso_node, Vector3(0.26, 0.38, 0.18), Vector3(0, 0.20, 0), "torso", Color(0.2, 0.9, 0.3))

	# 颈部 Neck
	neck_node = Node3D.new()
	neck_node.name = "Neck"
	neck_node.position = Vector3(0, 0.42, 0)
	torso_node.add_child(neck_node)
	_create_cylinder_mesh(neck_node, 0.05, 0.10, Vector3(0, 0.05, 0), "neck", Color(1.0, 0.0, 0.0))

	# 头部 Head
	head_node = Node3D.new()
	head_node.name = "Head"
	head_node.position = Vector3(0, 0.11, 0)
	neck_node.add_child(head_node)
	_create_sphere_mesh(head_node, 0.14, Vector3(0, 0.12, 0), "head", Color(1.0, 0.0, 0.5))
	# 面部朝向鼻锥标志
	_create_cylinder_mesh(head_node, 0.02, 0.08, Vector3(0, 0.12, 0.14), "nose", Color(1.0, 0.2, 0.6), Vector3(90, 0, 0))

	# --- 左臂 (Left Arm) ---
	shoulder_l = Node3D.new()
	shoulder_l.name = "ShoulderL"
	shoulder_l.position = Vector3(0.22, 0.34, 0)
	torso_node.add_child(shoulder_l)
	_create_joint_sphere(shoulder_l, 0.055, "joint_shoulder_l", Color(0.0, 0.8, 1.0))

	upper_arm_l = Node3D.new()
	upper_arm_l.name = "UpperArmL"
	shoulder_l.add_child(upper_arm_l)
	_create_capsule_mesh(upper_arm_l, Vector3(0.08, 0.26, 0.08), Vector3(0, -0.14, 0), "arm_l", Color(0.0, 0.85, 1.0))

	lower_arm_l = Node3D.new()
	lower_arm_l.name = "LowerArmL"
	lower_arm_l.position = Vector3(0, -0.28, 0)
	upper_arm_l.add_child(lower_arm_l)
	_create_joint_sphere(lower_arm_l, 0.045, "joint_elbow_l", Color(0.0, 0.6, 1.0))
	_create_capsule_mesh(lower_arm_l, Vector3(0.07, 0.24, 0.07), Vector3(0, -0.13, 0), "forearm_l", Color(0.0, 0.5, 1.0))

	hand_l = Node3D.new()
	hand_l.name = "HandL"
	hand_l.position = Vector3(0, -0.26, 0)
	lower_arm_l.add_child(hand_l)
	_create_sphere_mesh(hand_l, 0.05, Vector3(0, -0.03, 0), "hand_l", Color(0.0, 0.3, 1.0))

	# --- 右臂 (Right Arm) ---
	shoulder_r = Node3D.new()
	shoulder_r.name = "ShoulderR"
	shoulder_r.position = Vector3(-0.22, 0.34, 0)
	torso_node.add_child(shoulder_r)
	_create_joint_sphere(shoulder_r, 0.055, "joint_shoulder_r", Color(1.0, 0.5, 0.0))

	upper_arm_r = Node3D.new()
	upper_arm_r.name = "UpperArmR"
	shoulder_r.add_child(upper_arm_r)
	_create_capsule_mesh(upper_arm_r, Vector3(0.08, 0.26, 0.08), Vector3(0, -0.14, 0), "arm_r", Color(1.0, 0.6, 0.0))

	lower_arm_r = Node3D.new()
	lower_arm_r.name = "LowerArmR"
	lower_arm_r.position = Vector3(0, -0.28, 0)
	upper_arm_r.add_child(lower_arm_r)
	_create_joint_sphere(lower_arm_r, 0.045, "joint_elbow_r", Color(1.0, 0.8, 0.0))
	_create_capsule_mesh(lower_arm_r, Vector3(0.07, 0.24, 0.07), Vector3(0, -0.13, 0), "forearm_r", Color(1.0, 0.85, 0.0))

	hand_r = Node3D.new()
	hand_r.name = "HandR"
	hand_r.position = Vector3(0, -0.26, 0)
	lower_arm_r.add_child(hand_r)
	_create_sphere_mesh(hand_r, 0.05, Vector3(0, -0.03, 0), "hand_r", Color(0.85, 1.0, 0.0))

	# --- 下肢 (Legs) ---
	hip_l = Node3D.new()
	hip_l.name = "HipL"
	hip_l.position = Vector3(0.12, -0.08, 0)
	hips_node.add_child(hip_l)
	_create_joint_sphere(hip_l, 0.05, "joint_hip_l", Color(0.0, 0.5, 1.0))

	upper_leg_l = Node3D.new()
	upper_leg_l.name = "UpperLegL"
	hip_l.add_child(upper_leg_l)
	_create_capsule_mesh(upper_leg_l, Vector3(0.10, 0.42, 0.10), Vector3(0, -0.22, 0), "leg_l", Color(0.0, 0.4, 0.9))

	lower_leg_l = Node3D.new()
	lower_leg_l.name = "LowerLegL"
	lower_leg_l.position = Vector3(0, -0.44, 0)
	upper_leg_l.add_child(lower_leg_l)
	_create_joint_sphere(lower_leg_l, 0.045, "joint_knee_l", Color(0.0, 0.2, 1.0))
	_create_capsule_mesh(lower_leg_l, Vector3(0.09, 0.40, 0.09), Vector3(0, -0.20, 0), "calf_l", Color(0.1, 0.15, 0.9))

	foot_l = Node3D.new()
	foot_l.name = "FootL"
	foot_l.position = Vector3(0, -0.42, 0)
	lower_leg_l.add_child(foot_l)
	_create_box_mesh(foot_l, Vector3(0.09, 0.06, 0.18), Vector3(0, -0.03, 0.05), "foot_l", Color(0.2, 0.0, 0.8))

	hip_r = Node3D.new()
	hip_r.name = "HipR"
	hip_r.position = Vector3(-0.12, -0.08, 0)
	hips_node.add_child(hip_r)
	_create_joint_sphere(hip_r, 0.05, "joint_hip_r", Color(0.6, 0.0, 1.0))

	upper_leg_r = Node3D.new()
	upper_leg_r.name = "UpperLegR"
	hip_r.add_child(upper_leg_r)
	_create_capsule_mesh(upper_leg_r, Vector3(0.10, 0.42, 0.10), Vector3(0, -0.22, 0), "leg_r", Color(0.7, 0.0, 1.0))

	lower_leg_r = Node3D.new()
	lower_leg_r.name = "LowerLegR"
	lower_leg_r.position = Vector3(0, -0.44, 0)
	upper_leg_r.add_child(lower_leg_r)
	_create_joint_sphere(lower_leg_r, 0.045, "joint_knee_r", Color(0.85, 0.0, 0.9))
	_create_capsule_mesh(lower_leg_r, Vector3(0.09, 0.40, 0.09), Vector3(0, -0.20, 0), "calf_r", Color(0.9, 0.0, 0.8))

	foot_r = Node3D.new()
	foot_r.name = "FootR"
	foot_r.position = Vector3(0, -0.42, 0)
	lower_leg_r.add_child(foot_r)
	_create_box_mesh(foot_r, Vector3(0.09, 0.06, 0.18), Vector3(0, -0.03, 0.05), "foot_r", Color(1.0, 0.0, 0.8))

# --- 辅助网格创建器 ---
func _create_capsule_mesh(parent: Node3D, size: Vector3, pos: Vector3, tag: String, op_color: Color) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var cap = CapsuleMesh.new()
	cap.radius = size.x * 0.5
	cap.height = size.y
	mi.mesh = cap
	mi.position = pos
	mi.material_override = dummy_mat_body
	mi.set_meta("tag", tag)
	mi.set_meta("op_color", op_color)
	parent.add_child(mi)
	mesh_instances.append(mi)
	return mi

func _create_sphere_mesh(parent: Node3D, radius: float, pos: Vector3, tag: String, op_color: Color) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var sph = SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	mi.mesh = sph
	mi.position = pos
	mi.material_override = dummy_mat_face if tag == "head" else dummy_mat_body
	mi.set_meta("tag", tag)
	mi.set_meta("op_color", op_color)
	parent.add_child(mi)
	mesh_instances.append(mi)
	return mi

func _create_cylinder_mesh(parent: Node3D, radius: float, height: float, pos: Vector3, tag: String, op_color: Color, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	mi.mesh = cyl
	mi.position = pos
	if rot_deg != Vector3.ZERO:
		mi.rotation_degrees = rot_deg
	mi.material_override = dummy_mat_body
	mi.set_meta("tag", tag)
	mi.set_meta("op_color", op_color)
	parent.add_child(mi)
	mesh_instances.append(mi)
	return mi

func _create_joint_sphere(parent: Node3D, radius: float, tag: String, op_color: Color) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var sph = SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	mi.mesh = sph
	mi.material_override = dummy_mat_joints
	mi.set_meta("tag", tag)
	mi.set_meta("op_color", op_color)
	parent.add_child(mi)
	mesh_instances.append(mi)
	return mi

func _create_box_mesh(parent: Node3D, size: Vector3, pos: Vector3, tag: String, op_color: Color) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.material_override = dummy_mat_body
	mi.set_meta("tag", tag)
	mi.set_meta("op_color", op_color)
	parent.add_child(mi)
	mesh_instances.append(mi)
	return mi

# --- 应用预设动作 ---
func apply_preset(preset_key: String) -> void:
	if not PRESETS.has(preset_key):
		return
	current_preset = preset_key
	var p = PRESETS[preset_key]
	
	if p.has("torso") and torso_node:
		torso_node.rotation_degrees = p["torso"]
	if p.has("head") and head_node:
		head_node.rotation_degrees = p["head"]
	if p.has("shoulder_l") and shoulder_l:
		shoulder_l.rotation_degrees = p["shoulder_l"]
	if p.has("lower_arm_l") and lower_arm_l:
		lower_arm_l.rotation_degrees = p["lower_arm_l"]
	if p.has("shoulder_r") and shoulder_r:
		shoulder_r.rotation_degrees = p["shoulder_r"]
	if p.has("lower_arm_r") and lower_arm_r:
		lower_arm_r.rotation_degrees = p["lower_arm_r"]
	if p.has("hip_l") and hip_l:
		hip_l.rotation_degrees = p["hip_l"]
	if p.has("lower_leg_l") and lower_leg_l:
		lower_leg_l.rotation_degrees = p["lower_leg_l"]
	if p.has("hip_r") and hip_r:
		hip_r.rotation_degrees = p["hip_r"]
	if p.has("lower_leg_r") and lower_leg_r:
		lower_leg_r.rotation_degrees = p["lower_leg_r"]

	pose_changed.emit(preset_key)

# --- 切换着色渲染模式 ---
func set_display_mode(mode: String) -> void:
	display_mode = mode
	for mi in mesh_instances:
		if not is_instance_valid(mi):
			continue
		if display_mode == "openpose":
			# OpenPose 纯色骨架模式：无光照不发散，纯度 100% 对应关节点
			var mat = StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = mi.get_meta("op_color", Color.WHITE)
			mi.material_override = mat
		else:
			# 3D 现代灰模模式：高质量工作室打光
			var tag = mi.get_meta("tag", "")
			if "joint" in tag:
				mi.material_override = dummy_mat_joints
			elif tag == "head":
				mi.material_override = dummy_mat_face
			else:
				mi.material_override = dummy_mat_body
