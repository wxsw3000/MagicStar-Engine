# editor/ui/pose_editor/pose_editor_dialog.gd
# AVG Studio 专属 3D 姿态工坊弹窗：实时 3D 视口、人体姿态预设库、多视角环绕与 OpenPose 骨架一键转绘
class_name PoseEditorDialog
extends ConfirmationDialog

signal pose_sprite_generated(new_sprite_item: Dictionary)

const PoseMannequinClass = preload("res://editor/ui/pose_editor/pose_mannequin_3d.gd")
const AIAssetMgr = preload("res://editor/core/ai_asset_manager.gd")

# 3D 视口组件
var sub_viewport_container: SubViewportContainer
var sub_viewport: SubViewport
var camera: Camera3D
var mannequin: PoseMannequinClass
var camera_pivot: Node3D

# 相机环绕参数
var camera_distance: float = 2.4
var camera_yaw: float = 0.0
var camera_pitch: float = 0.0
var camera_target_height: float = 1.15
var is_dragging: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO

# 角色数据
var character_id: String = ""
var character_name: String = ""
var character_ent: Dictionary = {}

# UI 控件
var vbox_presets: VBoxContainer
var txt_pose_name: LineEdit
var txt_extra_prompt: LineEdit
var opt_render_mode: OptionButton
var lbl_status: Label
var file_dlg_ref: FileDialog
var custom_pose_reference_path: String = ""

func _ready() -> void:
	title = "📐 AVG 3D 姿态工坊 (3D Pose Studio & OpenPose)"
	min_size = Vector2(980, 640)
	ok_button_text = "🎨 依此姿态生成角色全新立绘"
	cancel_button_text = "关闭"
	confirmed.connect(_on_confirm_generate)

	_build_ui()

func _build_ui() -> void:
	var root_margin = MarginContainer.new()
	root_margin.add_theme_constant_override("margin_left", 12)
	root_margin.add_theme_constant_override("margin_top", 10)
	root_margin.add_theme_constant_override("margin_right", 12)
	root_margin.add_theme_constant_override("margin_bottom", 10)
	add_child(root_margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	root_margin.add_child(hbox)

	# --- 左侧栏：动作预设库与模式选择 (250px) ---
	var left_panel = PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(250, 0)
	var lp_style = StyleBoxFlat.new()
	lp_style.bg_color = Color(0.08, 0.10, 0.14, 0.95)
	lp_style.set_corner_radius_all(6)
	lp_style.set_border_width_all(1)
	lp_style.border_color = Color(0.25, 0.32, 0.45, 0.6)
	left_panel.add_theme_stylebox_override("panel", lp_style)
	hbox.add_child(left_panel)

	var left_vbox = VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 8)
	var left_margin = MarginContainer.new()
	left_margin.add_theme_constant_override("margin_left", 10)
	left_margin.add_theme_constant_override("margin_top", 10)
	left_margin.add_theme_constant_override("margin_right", 10)
	left_margin.add_theme_constant_override("margin_bottom", 10)
	left_panel.add_child(left_margin)
	left_margin.add_child(left_vbox)

	var lbl_p_title = Label.new()
	lbl_p_title.text = "🎭 常用立绘姿态预设"
	lbl_p_title.add_theme_font_size_override("font_size", 14)
	lbl_p_title.modulate = Color(1.0, 0.85, 0.4)
	left_vbox.add_child(lbl_p_title)

	var scroll_presets = ScrollContainer.new()
	scroll_presets.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(scroll_presets)

	vbox_presets = VBoxContainer.new()
	vbox_presets.add_theme_constant_override("separation", 6)
	vbox_presets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_presets.add_child(vbox_presets)

	_populate_preset_buttons()

	var lbl_mode = Label.new()
	lbl_mode.text = "🎨 视口渲染着色模式:"
	lbl_mode.add_theme_font_size_override("font_size", 12)
	lbl_mode.modulate = Color(0.75, 0.85, 0.95)
	left_vbox.add_child(lbl_mode)

	opt_render_mode = OptionButton.new()
	opt_render_mode.add_item("🔘 3D 现代灰模 (美学预览)", 0)
	opt_render_mode.add_item("🌈 OpenPose 骨骼骨架 (线控底图)", 1)
	opt_render_mode.selected = 0
	opt_render_mode.custom_minimum_size = Vector2(0, 30)
	opt_render_mode.item_selected.connect(func(idx):
		var mode = "dummy" if idx == 0 else "openpose"
		if mannequin:
			mannequin.set_display_mode(mode)
	)
	left_vbox.add_child(opt_render_mode)

	var btn_upload_ref = Button.new()
	btn_upload_ref.text = "📥 上传外部姿态参考图"
	btn_upload_ref.custom_minimum_size = Vector2(0, 32)
	btn_upload_ref.tooltip_text = "从本地导入名场面、摄影或动漫截图作为 ControlNet 姿态控制底图"
	btn_upload_ref.pressed.connect(_on_import_ref_pressed)
	left_vbox.add_child(btn_upload_ref)

	# --- 中间栏：3D 交互视口 (512x768 标准立绘比例) ---
	var center_vbox = VBoxContainer.new()
	center_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_vbox.add_theme_constant_override("separation", 8)
	hbox.add_child(center_vbox)

	var viewport_frame = PanelContainer.new()
	viewport_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vf_style = StyleBoxFlat.new()
	vf_style.bg_color = Color(0.02, 0.03, 0.05, 1.0)
	vf_style.set_corner_radius_all(6)
	vf_style.set_border_width_all(1)
	vf_style.border_color = Color(0.3, 0.45, 0.65, 0.8)
	viewport_frame.add_theme_stylebox_override("panel", vf_style)
	center_vbox.add_child(viewport_frame)

	sub_viewport_container = SubViewportContainer.new()
	sub_viewport_container.stretch = true
	sub_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sub_viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
	sub_viewport_container.gui_input.connect(_on_viewport_gui_input)
	viewport_frame.add_child(sub_viewport_container)

	sub_viewport = SubViewport.new()
	sub_viewport.size = Vector2i(512, 768)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_viewport_container.add_child(sub_viewport)

	_setup_3d_scene()

	# 视口快捷视角控制条
	var view_bar = HBoxContainer.new()
	view_bar.add_theme_constant_override("separation", 8)
	center_vbox.add_child(view_bar)

	var lbl_v_hint = Label.new()
	lbl_v_hint.text = "视角快捷:"
	lbl_v_hint.modulate = Color(0.7, 0.8, 0.9)
	view_bar.add_child(lbl_v_hint)

	var btn_view_front = Button.new()
	btn_view_front.text = "正视"
	btn_view_front.pressed.connect(func(): _set_camera_angle(0.0, 0.0))
	view_bar.add_child(btn_view_front)

	var btn_view_15 = Button.new()
	btn_view_15.text = "微侧 15°"
	btn_view_15.pressed.connect(func(): _set_camera_angle(15.0, 0.0))
	view_bar.add_child(btn_view_15)

	var btn_view_45 = Button.new()
	btn_view_45.text = "动态 45°"
	btn_view_45.pressed.connect(func(): _set_camera_angle(45.0, 0.0))
	view_bar.add_child(btn_view_45)

	var btn_view_up = Button.new()
	btn_view_up.text = "微仰角"
	btn_view_up.pressed.connect(func(): _set_camera_angle(camera_yaw, -8.0))
	view_bar.add_child(btn_view_up)

	var btn_view_reset = Button.new()
	btn_view_reset.text = "🔄 重置视角"
	btn_view_reset.pressed.connect(_reset_camera)
	view_bar.add_child(btn_view_reset)

	# --- 右侧栏：角色属性与生成参数 (260px) ---
	var right_panel = PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(260, 0)
	var rp_style = StyleBoxFlat.new()
	rp_style.bg_color = Color(0.08, 0.10, 0.14, 0.95)
	rp_style.set_corner_radius_all(6)
	rp_style.set_border_width_all(1)
	rp_style.border_color = Color(0.25, 0.32, 0.45, 0.6)
	right_panel.add_theme_stylebox_override("panel", rp_style)
	hbox.add_child(right_panel)

	var right_vbox = VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 10)
	var right_margin = MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 12)
	right_margin.add_theme_constant_override("margin_top", 12)
	right_margin.add_theme_constant_override("margin_right", 12)
	right_margin.add_theme_constant_override("margin_bottom", 12)
	right_panel.add_child(right_margin)
	right_margin.add_child(right_vbox)

	var lbl_r_title = Label.new()
	lbl_r_title.text = "⚙️ 新姿态立绘生成参数"
	lbl_r_title.add_theme_font_size_override("font_size", 14)
	lbl_r_title.modulate = Color(1.0, 0.85, 0.4)
	right_vbox.add_child(lbl_r_title)

	var lbl_name_hint = Label.new()
	lbl_name_hint.text = "立绘差分后缀名:"
	lbl_name_hint.modulate = Color(0.7, 0.8, 0.9)
	right_vbox.add_child(lbl_name_hint)

	txt_pose_name = LineEdit.new()
	txt_pose_name.text = "双手抱胸·严谨深思"
	right_vbox.add_child(txt_pose_name)

	var lbl_prompt_hint = Label.new()
	lbl_prompt_hint.text = "姿态专属描述词 (Prompt):"
	lbl_prompt_hint.modulate = Color(0.7, 0.8, 0.9)
	right_vbox.add_child(lbl_prompt_hint)

	txt_extra_prompt = LineEdit.new()
	txt_extra_prompt.text = "arms crossed against chest, looking stern, confident standing pose"
	right_vbox.add_child(txt_extra_prompt)

	var btn_snapshot = Button.new()
	btn_snapshot.text = "📸 导出当前姿态快照 (PNG)"
	btn_snapshot.custom_minimum_size = Vector2(0, 36)
	btn_snapshot.pressed.connect(_on_export_snapshot)
	right_vbox.add_child(btn_snapshot)

	lbl_status = Label.new()
	lbl_status.text = "💡 提示: 鼠标左键拖拽旋转视角，滚轮缩放，选择左侧预设即可实时摆姿势。"
	lbl_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_status.modulate = Color(0.65, 0.75, 0.85)
	lbl_status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(lbl_status)

func _setup_3d_scene() -> void:
	# 环境打光
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.07, 1.0)
	env.ambient_light_color = Color(0.7, 0.75, 0.85)
	env.ambient_light_energy = 0.8

	var world_env = WorldEnvironment.new()
	world_env.environment = env
	sub_viewport.add_child(world_env)

	# 主光源 (Key Light)
	var light = DirectionalLight3D.new()
	light.position = Vector3(1.5, 3.0, 2.0)
	light.rotation_degrees = Vector3(-35, 30, 0)
	light.light_color = Color(1.0, 0.96, 0.90)
	light.light_energy = 1.2
	sub_viewport.add_child(light)

	# 补光 (Fill Light)
	var fill_light = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-20, -60, 0)
	fill_light.light_color = Color(0.6, 0.75, 0.95)
	fill_light.light_energy = 0.5
	sub_viewport.add_child(fill_light)

	# 人偶主体
	mannequin = PoseMannequinClass.new()
	mannequin.name = "Mannequin"
	sub_viewport.add_child(mannequin)

	# 相机与枢轴
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position = Vector3(0, camera_target_height, 0)
	sub_viewport.add_child(camera_pivot)

	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0, 0, camera_distance)
	camera.current = true
	camera.fov = 42.0
	camera_pivot.add_child(camera)

func _populate_preset_buttons() -> void:
	for key in PoseMannequinClass.PRESETS:
		var p_info = PoseMannequinClass.PRESETS[key]
		var btn = Button.new()
		btn.text = p_info.get("name", key)
		btn.custom_minimum_size = Vector2(0, 32)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(func():
			if mannequin:
				mannequin.apply_preset(key)
				txt_pose_name.text = p_info.get("name", key)
				lbl_status.text = "✅ 已应用姿态: " + p_info.get("name", key)
		)
		vbox_presets.add_child(btn)

func _on_viewport_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = mb.pressed
			last_mouse_pos = mb.position
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = clamp(camera_distance - 0.15, 1.2, 4.0)
			_update_camera_transform()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = clamp(camera_distance + 0.15, 1.2, 4.0)
			_update_camera_transform()
	elif event is InputEventMouseMotion and is_dragging:
		var mm = event as InputEventMouseMotion
		var delta = mm.position - last_mouse_pos
		last_mouse_pos = mm.position
		camera_yaw -= delta.x * 0.45
		camera_pitch = clamp(camera_pitch - delta.y * 0.45, -45.0, 45.0)
		_update_camera_transform()

func _set_camera_angle(yaw: float, pitch: float) -> void:
	camera_yaw = yaw
	camera_pitch = pitch
	_update_camera_transform()

func _reset_camera() -> void:
	camera_distance = 2.4
	camera_yaw = 0.0
	camera_pitch = 0.0
	_update_camera_transform()

func _update_camera_transform() -> void:
	if camera_pivot:
		camera_pivot.rotation_degrees = Vector3(camera_pitch, camera_yaw, 0)
	if camera:
		camera.position = Vector3(0, 0, camera_distance)

# --- 弹出配置初始化 ---
func open_for_character(cid: String, ent: Dictionary) -> void:
	character_id = cid
	character_name = ent.get("name", cid)
	character_ent = ent
	title = "📐 3D 姿态工坊: %s (OpenPose)" % character_name
	txt_pose_name.text = "双手抱胸·严谨深思"
	_reset_camera()
	popup_centered()

func select_preset(key: String) -> void:
	if mannequin and PoseMannequinClass.PRESETS.has(key):
		mannequin.apply_preset(key)
		var p_info = PoseMannequinClass.PRESETS[key]
		if txt_pose_name:
			txt_pose_name.text = p_info.get("name", key)
		if lbl_status:
			lbl_status.text = "✅ 已应用姿态: " + p_info.get("name", key)

# --- 截图并导出快照 ---
func capture_viewport_image() -> Image:
	if not sub_viewport:
		return null
	# 在无 GPU 硬件管线模式（如 Headless 自动化测试环境）直接创建保底图像，避免 dummy renderer 空纹理异常
	if DisplayServer.get_name() == "headless":
		var img = Image.create(512, 768, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.02, 0.03, 0.05, 1.0))
		return img

	var tex = sub_viewport.get_texture()
	var img: Image = null
	if tex:
		img = tex.get_image()
	if not img:
		img = Image.create(512, 768, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.02, 0.03, 0.05, 1.0))
	return img

func _on_export_snapshot() -> void:
	var img = capture_viewport_image()
	if not img:
		lbl_status.text = "❌ 获取视口画面失败"
		return
	
	var pdir = ProjectContext.active_project_dir
	if pdir.is_empty():
		pdir = "res://projects/case_gallery_rain/"
	if not pdir.ends_with("/"):
		pdir += "/"
	
	var fname = "pose_%s_%d.png" % [character_id, int(Time.get_unix_time_from_system())]
	var save_path = pdir + "assets/images/characters/" + fname
	var abs_p = ProjectSettings.globalize_path(save_path)
	DirAccess.make_dir_recursive_absolute(abs_p.get_base_dir())
	img.save_png(abs_p)
	lbl_status.text = "✅ 姿态快照已保存至: " + fname

# --- 外部姿态参考图导入 ---
func _on_import_ref_pressed() -> void:
	if not file_dlg_ref:
		file_dlg_ref = FileDialog.new()
		file_dlg_ref.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		file_dlg_ref.access = FileDialog.ACCESS_FILESYSTEM
		file_dlg_ref.filters = ["*.png, *.jpg, *.jpeg, *.webp ; 姿态参考图像"]
		file_dlg_ref.title = "选择外部姿态参考图 (Pose Reference)"
		file_dlg_ref.min_size = Vector2(700, 480)
		file_dlg_ref.file_selected.connect(_on_ref_file_selected)
		add_child(file_dlg_ref)
	file_dlg_ref.popup_centered()

func _on_ref_file_selected(path: String) -> void:
	custom_pose_reference_path = path
	if lbl_status:
		lbl_status.text = "✅ 已挂载外部姿态参考图: %s\n点击确认将直接作为姿态控制底图生成！" % path.get_file()

# --- 确认依此姿态生成全新立绘 ---
func _on_confirm_generate() -> void:
	var pdir = ProjectContext.active_project_dir
	if pdir.is_empty():
		pdir = "res://projects/case_gallery_rain/"
	if not pdir.ends_with("/"):
		pdir += "/"
	
	var suffix = txt_pose_name.text.strip_edges()
	if suffix.is_empty():
		suffix = "3D姿态立绘"
	
	var pose_rel_path = ""
	if not custom_pose_reference_path.is_empty() and FileAccess.file_exists(custom_pose_reference_path):
		var pose_fname = "pose_ref_%s_%d.png" % [character_id, int(Time.get_unix_time_from_system())]
		pose_rel_path = pdir + "assets/images/characters/" + pose_fname
		var pose_abs_path = ProjectSettings.globalize_path(pose_rel_path)
		DirAccess.make_dir_recursive_absolute(pose_abs_path.get_base_dir())
		DirAccess.copy_absolute(custom_pose_reference_path, pose_abs_path)
	else:
		# 自动将视口临时切换至 OpenPose 骨架着色进行标准化纯骨骼采样
		var old_mode = mannequin.display_mode if mannequin else "dummy"
		if mannequin:
			mannequin.set_display_mode("openpose")
		var img = capture_viewport_image()
		if mannequin:
			mannequin.set_display_mode(old_mode)
		if not img:
			return
		
		var pose_fname = "pose_control_%s_%d.png" % [character_id, int(Time.get_unix_time_from_system())]
		pose_rel_path = pdir + "assets/images/characters/" + pose_fname
		var pose_abs_path = ProjectSettings.globalize_path(pose_rel_path)
		DirAccess.make_dir_recursive_absolute(pose_abs_path.get_base_dir())
		img.save_png(pose_abs_path)

	# 构造全新立绘素材项
	var sprite_idx = character_ent.get("sprites", []).size() + 1
	var item_id = "char_" + character_id + "_sprite_" + str(sprite_idx)
	var rel_path = pdir + "assets/images/characters/" + item_id + ".png"
	var base_p = character_ent.get("base_prompt", "")
	var extra_p = txt_extra_prompt.text.strip_edges()
	
	var pose_prompt_zh = ""
	var pose_prompt_en = ""
	if mannequin and mannequin.PRESETS.has(mannequin.current_preset):
		var p_info = mannequin.PRESETS[mannequin.current_preset]
		pose_prompt_zh = p_info.get("prompt_zh", "")
		pose_prompt_en = p_info.get("prompt_en", "")

	var final_p = base_p + "，" + suffix
	if not pose_prompt_zh.is_empty():
		final_p += "，" + pose_prompt_zh
	if not extra_p.is_empty():
		final_p += "，" + extra_p
	if not pose_prompt_en.is_empty():
		final_p += "，" + pose_prompt_en

	var new_item = {
		"id": item_id,
		"type": "character",
		"entity_type": "character",
		"entity_id": character_id,
		"entity_name": character_name,
		"character_id": character_id,
		"sub_type": "sprite",
		"name": "%s 3D姿态: %s" % [character_name, suffix],
		"prompt": final_p,
		"negative_prompt": "复杂背景，室内室外环境，多余手指，肢体畸变，低质量，模糊",
		"local_path": rel_path,
		"width": 512,
		"height": 768,
		"pose_preset": mannequin.current_preset if mannequin else "standing_calm",
		"pose_image": pose_rel_path,
		"generation_mode": "pose",
		"status": "pending"
	}

	custom_pose_reference_path = ""
	pose_sprite_generated.emit(new_item)
	hide()
