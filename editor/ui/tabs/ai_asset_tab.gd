# editor/ui/tabs/ai_asset_tab.gd
# AVG Studio 专属 AI 资产工坊界面：实体归属组织 (角色/场景/道具/公共)、非阻塞实时进度反馈与一键定位本地文件夹
class_name AIAssetTab
extends Control

const AIAssetMgr = preload("res://editor/core/ai_asset_manager.gd")
const PoseEditorDialogClass = preload("res://editor/ui/pose_editor/pose_editor_dialog.gd")
const PROGRESS_FILE_PATH = "user://temp_ai_progress.json"

# 数据引用
var ai_settings: Dictionary = {}
var manifest_items: Array = []
var entities_summary: Dictionary = {}

# 当前选中的分类与实体
# 分类: "character", "scene", "clue", "shared"
var current_category: String = "character"
var selected_entity_id: String = ""
var selected_item_id: String = ""
var char_workbench_subtab: String = "both"

# 顶部配置栏控件
var opt_server_preset: OptionButton
var btn_add_env: Button
var btn_manage_env: Button
var txt_comfy_host: LineEdit
var txt_comfy_user: LineEdit
var txt_comfy_pass: LineEdit
var btn_toggle_pass: Button
var btn_test_conn: Button
var lbl_conn_status: Label
var opt_checkpoint: OptionButton
var txt_checkpoint: LineEdit
var txt_global_style: LineEdit
var txt_global_neg: LineEdit
var btn_save_config: Button
var btn_sync_manifest: Button
var btn_batch_generate: Button

# 左侧实体导航栏控件
var btn_cat_characters: Button
var btn_cat_scenes: Button
var btn_cat_clues: Button
var btn_cat_shared: Button
var txt_search: LineEdit
var opt_filter_status: OptionButton
var vbox_entity_list: VBoxContainer
var lbl_nav_summary: Label

# 右侧实体专属工作台控件
var lbl_entity_title: Label
var lbl_entity_subtitle: Label
var btn_open_entity_folder: Button
var btn_batch_entity_pending: Button
var entity_content_scroll: ScrollContainer
var vbox_entity_content: VBoxContainer

# 兼容性字段 (供自动化测试与老逻辑访问)
var lbl_combined_prompt: Label
var preview_audio_player: AudioStreamPlayer

# 底部实时进度条与状态
var lbl_gen_status: Label
var progress_bar: ProgressBar
var progress_poll_timer: Timer

# 异步生成线程与状态
var gen_thread: Thread = null
var is_generating: bool = false
var gen_start_time: float = 0.0
var gen_start_time_ms: int = 0
var batch_start_time_ms: int = 0
var is_batch_running: bool = false
var batch_current_label: String = ""
var batch_current_index: int = 0
var batch_total_count: int = 0

# 交互弹窗 (新增差分与录入台词)
var dlg_add_sprite: ConfirmationDialog
var opt_add_sprite_mode: OptionButton
var lbl_add_sprite_pose_title: Label
var txt_sprite_suffix: LineEdit
var opt_add_sprite_pose: OptionButton
var txt_sprite_prompt: TextEdit
var pending_sprite_cid: String = ""
var pending_sprite_ent: Dictionary = {}

var dlg_add_voice: ConfirmationDialog
var txt_voice_input: TextEdit
var pending_voice_cid: String = ""
var pending_voice_ent: Dictionary = {}

# 多环境管理相关弹窗控件
var dlg_add_env: ConfirmationDialog
var txt_add_env_name: LineEdit
var txt_add_env_host: LineEdit
var txt_add_env_user: LineEdit
var txt_add_env_pass: LineEdit

var dlg_manage_env: AcceptDialog
var vbox_env_list: VBoxContainer

var dlg_edit_env: ConfirmationDialog
var editing_env_id: String = ""
var txt_edit_env_name: LineEdit
var txt_edit_env_host: LineEdit
var txt_edit_env_user: LineEdit
var txt_edit_env_pass: LineEdit

var dlg_import_file: FileDialog
var import_target_item: Dictionary = {}
var dlg_pose_editor: PoseEditorDialogClass

func _ready() -> void:
	setup_audio_player()
	setup_progress_timer()
	setup_dialogs()
	setup_ui()
	load_data()
	call_deferred("test_comfy_connection")

func _exit_tree() -> void:
	if progress_poll_timer and is_instance_valid(progress_poll_timer):
		progress_poll_timer.stop()
	if gen_thread and gen_thread.is_started():
		gen_thread.wait_to_finish()

func setup_audio_player() -> void:
	preview_audio_player = AudioStreamPlayer.new()
	add_child(preview_audio_player)

func setup_progress_timer() -> void:
	progress_poll_timer = Timer.new()
	progress_poll_timer.wait_time = 0.2
	progress_poll_timer.timeout.connect(_on_progress_timer_tick)
	add_child(progress_poll_timer)

func setup_dialogs() -> void:
	dlg_add_sprite = ConfirmationDialog.new()
	dlg_add_sprite.title = "新增表情/姿态立绘差分"
	dlg_add_sprite.min_size = Vector2(520, 330)
	var vbox_s = VBoxContainer.new()
	vbox_s.add_theme_constant_override("separation", 8)
	dlg_add_sprite.add_child(vbox_s)
	
	var lbl_s = Label.new()
	lbl_s.text = "差分简称 (如: 质询冷笑 / 震惊洞悉 / 严肃审视):"
	vbox_s.add_child(lbl_s)
	
	txt_sprite_suffix = LineEdit.new()
	txt_sprite_suffix.placeholder_text = "例如: 质询冷笑 / 震惊洞悉 / 严肃审视"
	txt_sprite_suffix.custom_minimum_size = Vector2(480, 34)
	txt_sprite_suffix.text_changed.connect(func(new_suf):
		var s_text = new_suf.strip_edges()
		if not s_text.is_empty():
			txt_sprite_prompt.text = "神色%s，目光凝注" % s_text
	)
	vbox_s.add_child(txt_sprite_suffix)

	var lbl_mode_s = Label.new()
	lbl_mode_s.text = "生成通道类型:"
	lbl_mode_s.modulate = Color(1.0, 0.85, 0.4)
	vbox_s.add_child(lbl_mode_s)

	opt_add_sprite_mode = OptionButton.new()
	opt_add_sprite_mode.custom_minimum_size = Vector2(480, 32)
	opt_add_sprite_mode.add_item("🎭 模式 A: 纯微表情自然差分 (100% 保持风衣身姿，潜空间平滑扩散微调表情)", 0)
	opt_add_sprite_mode.add_item("🧍‍♂️ 模式 B: 3D 姿态全新全身立绘 (解除身体锁定，依据 3D 骨架生成全新身姿)", 1)
	opt_add_sprite_mode.selected = 0
	opt_add_sprite_mode.item_selected.connect(func(idx):
		if lbl_add_sprite_pose_title:
			lbl_add_sprite_pose_title.visible = (idx == 1)
		if opt_add_sprite_pose:
			opt_add_sprite_pose.visible = (idx == 1)
	)
	vbox_s.add_child(opt_add_sprite_mode)

	lbl_add_sprite_pose_title = Label.new()
	lbl_add_sprite_pose_title.text = "绑定 3D 动作姿态预设:"
	lbl_add_sprite_pose_title.modulate = Color(0.65, 0.85, 0.75)
	lbl_add_sprite_pose_title.visible = false
	vbox_s.add_child(lbl_add_sprite_pose_title)

	opt_add_sprite_pose = OptionButton.new()
	opt_add_sprite_pose.custom_minimum_size = Vector2(480, 32)
	opt_add_sprite_pose.visible = false
	var p_keys = [
		"standing_calm", "crossed_arms", "chin_touch", "pointing_accuse",
		"hands_on_hips", "pocket_hands", "shrug_spread", "hold_clue"
	]
	var p_icons = ["🧍", "🙅", "🤔", "👉", "🥋", "🧥", "🤷", "🔍"]
	var p_labels = ["标准站姿·冷静从容", "双手抱胸·严谨深思", "手托下巴·推理破案", "一指指证·真凶就是你", "双手叉腰·自信傲然", "插兜侧立·冷酷风衣", "摊手无奈·无可奉告", "托举物证·细微观察"]
	for i in range(p_keys.size()):
		opt_add_sprite_pose.add_item("%s %s" % [p_icons[i], p_labels[i]], i)
		opt_add_sprite_pose.set_item_metadata(i, p_keys[i])
	vbox_s.add_child(opt_add_sprite_pose)

	var lbl_sp = Label.new()
	lbl_sp.text = "专属微表情神态中文提示词 (基础角色特征与动作姿态将智能组装):"
	lbl_sp.modulate = Color(1.0, 0.85, 0.4)
	vbox_s.add_child(lbl_sp)

	txt_sprite_prompt = TextEdit.new()
	txt_sprite_prompt.placeholder_text = "输入本差分的专属中文神态微表情（如：眼神凌厉冰冷，嘴角微嘲冷笑）..."
	txt_sprite_prompt.custom_minimum_size = Vector2(480, 68)
	txt_sprite_prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox_s.add_child(txt_sprite_prompt)
	
	dlg_add_sprite.confirmed.connect(_on_confirm_add_sprite)
	add_child(dlg_add_sprite)
	
	dlg_add_voice = ConfirmationDialog.new()
	dlg_add_voice.title = "录入新台词配音"
	dlg_add_voice.min_size = Vector2(500, 220)
	var vbox_v = VBoxContainer.new()
	vbox_v.add_theme_constant_override("separation", 8)
	dlg_add_voice.add_child(vbox_v)
	
	var lbl_v = Label.new()
	lbl_v.text = "请输入要合成的对白台词文本:"
	vbox_v.add_child(lbl_v)
	
	txt_voice_input = TextEdit.new()
	txt_voice_input.placeholder_text = "例如: 密室的锁，从来都不是在里面被锁上的……"
	txt_voice_input.custom_minimum_size = Vector2(460, 80)
	vbox_v.add_child(txt_voice_input)
	
	dlg_add_voice.confirmed.connect(_on_confirm_add_voice)
	add_child(dlg_add_voice)

	# --- 新增 ComfyUI 环境配置弹窗 ---
	dlg_add_env = ConfirmationDialog.new()
	dlg_add_env.title = "➕ 新增 ComfyUI 环境配置"
	dlg_add_env.min_size = Vector2(480, 290)
	var vbox_ae = VBoxContainer.new()
	vbox_ae.add_theme_constant_override("separation", 8)
	dlg_add_env.add_child(vbox_ae)
	
	var lbl_ae_name = Label.new()
	lbl_ae_name.text = "环境备注名称 (如: 办公室4090 / 阿里云GPU / 本地默认):"
	vbox_ae.add_child(lbl_ae_name)
	
	txt_add_env_name = LineEdit.new()
	txt_add_env_name.placeholder_text = "例如: 远程专属云端"
	txt_add_env_name.custom_minimum_size = Vector2(440, 36)
	vbox_ae.add_child(txt_add_env_name)
	
	var lbl_ae_host = Label.new()
	lbl_ae_host.text = "服务地址 Host (IP/域名及端口):"
	vbox_ae.add_child(lbl_ae_host)
	
	txt_add_env_host = LineEdit.new()
	txt_add_env_host.placeholder_text = "例如: https://domain.fun:8188 或 http://127.0.0.1:8188"
	txt_add_env_host.custom_minimum_size = Vector2(440, 36)
	vbox_ae.add_child(txt_add_env_host)
	
	var row_ae_auth = HBoxContainer.new()
	row_ae_auth.add_theme_constant_override("separation", 10)
	vbox_ae.add_child(row_ae_auth)
	
	var vbox_ae_u = VBoxContainer.new()
	vbox_ae_u.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_ae_user = Label.new()
	lbl_ae_user.text = "账号 (可选，无则留空):"
	vbox_ae_u.add_child(lbl_ae_user)
	txt_add_env_user = LineEdit.new()
	txt_add_env_user.placeholder_text = "可选"
	txt_add_env_user.custom_minimum_size = Vector2(200, 36)
	vbox_ae_u.add_child(txt_add_env_user)
	row_ae_auth.add_child(vbox_ae_u)
	
	var vbox_ae_p = VBoxContainer.new()
	vbox_ae_p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_ae_pass = Label.new()
	lbl_ae_pass.text = "密码 (可选，无则留空):"
	vbox_ae_p.add_child(lbl_ae_pass)
	
	var row_ae_p_box = HBoxContainer.new()
	txt_add_env_pass = LineEdit.new()
	txt_add_env_pass.secret = true
	txt_add_env_pass.placeholder_text = "可选"
	txt_add_env_pass.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt_add_env_pass.custom_minimum_size = Vector2(160, 36)
	row_ae_p_box.add_child(txt_add_env_pass)
	
	var btn_ae_eye = Button.new()
	btn_ae_eye.text = "👁️"
	btn_ae_eye.custom_minimum_size = Vector2(36, 36)
	btn_ae_eye.pressed.connect(func(): txt_add_env_pass.secret = not txt_add_env_pass.secret)
	row_ae_p_box.add_child(btn_ae_eye)
	vbox_ae_p.add_child(row_ae_p_box)
	row_ae_auth.add_child(vbox_ae_p)
	
	dlg_add_env.confirmed.connect(_on_confirm_add_env)
	add_child(dlg_add_env)
	
	# --- 管理所有 ComfyUI 环境弹窗 ---
	dlg_manage_env = AcceptDialog.new()
	dlg_manage_env.title = "⚙️ ComfyUI 环境配置管理"
	dlg_manage_env.min_size = Vector2(650, 420)
	var vbox_mg = VBoxContainer.new()
	vbox_mg.add_theme_constant_override("separation", 10)
	dlg_manage_env.add_child(vbox_mg)
	
	var lbl_mg_tip = Label.new()
	lbl_mg_tip.text = "当前已配置的 ComfyUI 环境列表（可随时切换、修改地址与账号密码、或删除多余环境）："
	lbl_mg_tip.modulate = Color(0.8, 0.85, 0.9)
	vbox_mg.add_child(lbl_mg_tip)
	
	var scroll_mg = ScrollContainer.new()
	scroll_mg.custom_minimum_size = Vector2(620, 260)
	scroll_mg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox_mg.add_child(scroll_mg)
	
	vbox_env_list = VBoxContainer.new()
	vbox_env_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_env_list.add_theme_constant_override("separation", 6)
	scroll_mg.add_child(vbox_env_list)
	
	var row_mg_btn = HBoxContainer.new()
	row_mg_btn.alignment = BoxContainer.ALIGNMENT_END
	var btn_mg_add = Button.new()
	btn_mg_add.text = "➕ 新增环境配置"
	btn_mg_add.custom_minimum_size = Vector2(130, 36)
	style_button(btn_mg_add, "primary")
	btn_mg_add.pressed.connect(func():
		dlg_manage_env.hide()
		open_add_env_dialog()
	)
	row_mg_btn.add_child(btn_mg_add)
	vbox_mg.add_child(row_mg_btn)
	add_child(dlg_manage_env)

	# --- 编辑已有环境配置弹窗 ---
	dlg_edit_env = ConfirmationDialog.new()
	dlg_edit_env.title = "✏️ 编辑 ComfyUI 环境配置"
	dlg_edit_env.min_size = Vector2(480, 290)
	var vbox_ed_env = VBoxContainer.new()
	vbox_ed_env.add_theme_constant_override("separation", 8)
	dlg_edit_env.add_child(vbox_ed_env)
	
	var lbl_ed_name = Label.new()
	lbl_ed_name.text = "环境备注名称:"
	vbox_ed_env.add_child(lbl_ed_name)
	txt_edit_env_name = LineEdit.new()
	txt_edit_env_name.custom_minimum_size = Vector2(440, 36)
	vbox_ed_env.add_child(txt_edit_env_name)
	
	var lbl_ed_host = Label.new()
	lbl_ed_host.text = "服务地址 Host (IP/域名及端口):"
	vbox_ed_env.add_child(lbl_ed_host)
	txt_edit_env_host = LineEdit.new()
	txt_edit_env_host.custom_minimum_size = Vector2(440, 36)
	vbox_ed_env.add_child(txt_edit_env_host)
	
	var row_ed_auth = HBoxContainer.new()
	row_ed_auth.add_theme_constant_override("separation", 10)
	vbox_ed_env.add_child(row_ed_auth)
	
	var vbox_ed_u = VBoxContainer.new()
	vbox_ed_u.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_ed_user = Label.new()
	lbl_ed_user.text = "账号 (可选):"
	vbox_ed_u.add_child(lbl_ed_user)
	txt_edit_env_user = LineEdit.new()
	txt_edit_env_user.custom_minimum_size = Vector2(200, 36)
	vbox_ed_u.add_child(txt_edit_env_user)
	row_ed_auth.add_child(vbox_ed_u)
	
	var vbox_ed_p = VBoxContainer.new()
	vbox_ed_p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl_ed_pass = Label.new()
	lbl_ed_pass.text = "密码 (可选):"
	vbox_ed_p.add_child(lbl_ed_pass)
	
	var row_ed_p_box = HBoxContainer.new()
	txt_edit_env_pass = LineEdit.new()
	txt_edit_env_pass.secret = true
	txt_edit_env_pass.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt_edit_env_pass.custom_minimum_size = Vector2(160, 36)
	row_ed_p_box.add_child(txt_edit_env_pass)
	
	var btn_ed_eye = Button.new()
	btn_ed_eye.text = "👁️"
	btn_ed_eye.custom_minimum_size = Vector2(36, 36)
	btn_ed_eye.pressed.connect(func(): txt_edit_env_pass.secret = not txt_edit_env_pass.secret)
	row_ed_p_box.add_child(btn_ed_eye)
	vbox_ed_p.add_child(row_ed_p_box)
	row_ed_auth.add_child(vbox_ed_p)
	
	dlg_edit_env.confirmed.connect(_on_confirm_edit_env)
	add_child(dlg_edit_env)

	# --- 外部资产一键导入/替换弹窗 (方案B外部管线支持) ---
	dlg_import_file = FileDialog.new()
	dlg_import_file.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg_import_file.access = FileDialog.ACCESS_FILESYSTEM
	dlg_import_file.title = "选择要导入并关联的外部资产文件"
	dlg_import_file.file_selected.connect(_on_external_file_selected)
	add_child(dlg_import_file)

	# --- 3D 姿态工坊弹窗 ---
	dlg_pose_editor = PoseEditorDialogClass.new()
	dlg_pose_editor.pose_sprite_generated.connect(_on_pose_sprite_generated)
	add_child(dlg_pose_editor)

func style_button(btn: Button, style_type: String = "primary") -> void:
	if btn == null:
		return
	var sb_normal = StyleBoxFlat.new()
	var sb_hover = StyleBoxFlat.new()
	var sb_pressed = StyleBoxFlat.new()
	
	sb_normal.set_corner_radius_all(6)
	sb_hover.set_corner_radius_all(6)
	sb_pressed.set_corner_radius_all(6)
	sb_normal.set_border_width_all(1)
	sb_hover.set_border_width_all(1)
	sb_pressed.set_border_width_all(1)
	
	sb_normal.content_margin_left = 12
	sb_normal.content_margin_right = 12
	sb_normal.content_margin_top = 6
	sb_normal.content_margin_bottom = 6
	sb_hover.content_margin_left = 12
	sb_hover.content_margin_right = 12
	sb_hover.content_margin_top = 6
	sb_hover.content_margin_bottom = 6
	sb_pressed.content_margin_left = 12
	sb_pressed.content_margin_right = 12
	sb_pressed.content_margin_top = 6
	sb_pressed.content_margin_bottom = 6

	match style_type:
		"batch":
			sb_normal.bg_color = Color(0.24, 0.16, 0.48, 0.95)
			sb_normal.border_color = Color(0.55, 0.38, 0.90, 0.85)
			sb_hover.bg_color = Color(0.32, 0.22, 0.62, 1.0)
			sb_hover.border_color = Color(0.70, 0.50, 1.0, 1.0)
			sb_pressed.bg_color = Color(0.18, 0.12, 0.38, 1.0)
			sb_pressed.border_color = Color(0.50, 0.35, 0.85, 1.0)
			btn.add_theme_color_override("font_color", Color(0.95, 0.90, 1.0))
			btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		"primary", "create":
			sb_normal.bg_color = Color(0.12, 0.38, 0.28, 0.95)
			sb_normal.border_color = Color(0.25, 0.75, 0.55, 0.85)
			sb_hover.bg_color = Color(0.16, 0.48, 0.35, 1.0)
			sb_hover.border_color = Color(0.35, 0.90, 0.65, 1.0)
			sb_pressed.bg_color = Color(0.08, 0.28, 0.20, 1.0)
			sb_pressed.border_color = Color(0.20, 0.65, 0.45, 1.0)
			btn.add_theme_color_override("font_color", Color(0.90, 1.0, 0.95))
			btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		"action":
			sb_normal.bg_color = Color(0.12, 0.26, 0.45, 0.95)
			sb_normal.border_color = Color(0.25, 0.55, 0.85, 0.85)
			sb_hover.bg_color = Color(0.16, 0.34, 0.58, 1.0)
			sb_hover.border_color = Color(0.35, 0.70, 1.0, 1.0)
			sb_pressed.bg_color = Color(0.08, 0.18, 0.32, 1.0)
			sb_pressed.border_color = Color(0.20, 0.45, 0.70, 1.0)
			btn.add_theme_color_override("font_color", Color(0.90, 0.95, 1.0))
			btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		"secondary":
			sb_normal.bg_color = Color(0.14, 0.17, 0.22, 0.95)
			sb_normal.border_color = Color(0.30, 0.38, 0.50, 0.6)
			sb_hover.bg_color = Color(0.20, 0.24, 0.30, 1.0)
			sb_hover.border_color = Color(0.42, 0.52, 0.68, 0.9)
			sb_pressed.bg_color = Color(0.10, 0.12, 0.16, 1.0)
			sb_pressed.border_color = Color(0.25, 0.32, 0.42, 0.8)
			btn.add_theme_color_override("font_color", Color(0.80, 0.88, 0.95))
			btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))

	btn.add_theme_stylebox_override("normal", sb_normal)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_pressed)
	btn.modulate = Color(1, 1, 1, 1)

# --- UI 搭建 ---
func setup_ui() -> void:
	var vbox_root = VBoxContainer.new()
	vbox_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox_root.add_theme_constant_override("separation", 10)
	add_child(vbox_root)

	# 1. 顶部配置与全局风格栏
	var top_panel = PanelContainer.new()
	var top_style = StyleBoxFlat.new()
	top_style.bg_color = Color(0.08, 0.10, 0.15, 0.95)
	top_style.set_border_width_all(1)
	top_style.border_color = Color(0.3, 0.4, 0.55, 0.6)
	top_style.set_corner_radius_all(8)
	top_panel.add_theme_stylebox_override("panel", top_style)
	vbox_root.add_child(top_panel)

	var top_margin = MarginContainer.new()
	top_margin.add_theme_constant_override("margin_left", 14)
	top_margin.add_theme_constant_override("margin_top", 10)
	top_margin.add_theme_constant_override("margin_right", 14)
	top_margin.add_theme_constant_override("margin_bottom", 10)
	top_panel.add_child(top_margin)

	var top_vbox = VBoxContainer.new()
	top_vbox.add_theme_constant_override("separation", 8)
	top_margin.add_child(top_vbox)

	# 第一行：ComfyUI 服务连接与 Checkpoint
	var row1 = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	top_vbox.add_child(row1)

	var lbl_preset = Label.new()
	lbl_preset.text = "⚡ 环境:"
	row1.add_child(lbl_preset)

	opt_server_preset = OptionButton.new()
	opt_server_preset.custom_minimum_size = Vector2(160, 34)
	row1.add_child(opt_server_preset)

	btn_add_env = Button.new()
	btn_add_env.text = "➕"
	btn_add_env.tooltip_text = "新增 ComfyUI 环境配置 (支持账号密码或无认证)"
	btn_add_env.custom_minimum_size = Vector2(34, 34)
	btn_add_env.pressed.connect(open_add_env_dialog)
	row1.add_child(btn_add_env)

	btn_manage_env = Button.new()
	btn_manage_env.text = "⚙️"
	btn_manage_env.tooltip_text = "管理所有 ComfyUI 环境配置 (切换/编辑/删除)"
	btn_manage_env.custom_minimum_size = Vector2(34, 34)
	btn_manage_env.pressed.connect(open_manage_env_dialog)
	row1.add_child(btn_manage_env)

	var lbl_host = Label.new()
	lbl_host.text = "🔌 地址:"
	row1.add_child(lbl_host)

	txt_comfy_host = LineEdit.new()
	txt_comfy_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt_comfy_host.custom_minimum_size = Vector2(140, 34)
	txt_comfy_host.placeholder_text = "http://..."
	row1.add_child(txt_comfy_host)

	# 保持节点存在以供内部读写与测试访问（隐藏以防单行宽度过大截断）
	txt_comfy_user = LineEdit.new()
	txt_comfy_user.visible = false
	row1.add_child(txt_comfy_user)

	txt_comfy_pass = LineEdit.new()
	txt_comfy_pass.visible = false
	row1.add_child(txt_comfy_pass)

	btn_toggle_pass = Button.new()
	btn_toggle_pass.visible = false
	row1.add_child(btn_toggle_pass)

	btn_test_conn = Button.new()
	btn_test_conn.text = "测试连接"
	btn_test_conn.custom_minimum_size = Vector2(80, 34)
	btn_test_conn.pressed.connect(test_comfy_connection)
	row1.add_child(btn_test_conn)

	lbl_conn_status = Label.new()
	lbl_conn_status.text = "⚪ 未检测"
	lbl_conn_status.modulate = Color(0.7, 0.75, 0.8)
	lbl_conn_status.clip_text = true
	lbl_conn_status.custom_minimum_size = Vector2(110, 30)
	row1.add_child(lbl_conn_status)

	var lbl_ckpt = Label.new()
	lbl_ckpt.text = "📦 底模:"
	row1.add_child(lbl_ckpt)

	opt_checkpoint = OptionButton.new()
	opt_checkpoint.custom_minimum_size = Vector2(170, 34)
	opt_checkpoint.item_selected.connect(func(idx):
		var ck = opt_checkpoint.get_item_metadata(idx)
		if ck:
			txt_checkpoint.text = ck
			ai_settings["checkpoint"] = ck
	)
	row1.add_child(opt_checkpoint)

	txt_checkpoint = LineEdit.new()
	txt_checkpoint.visible = false
	txt_checkpoint.text = "anima-turbo-v1.1.safetensors"
	row1.add_child(txt_checkpoint)

	btn_save_config = Button.new()
	btn_save_config.text = "💾 保存配置"
	btn_save_config.custom_minimum_size = Vector2(85, 34)
	style_button(btn_save_config, "secondary")
	btn_save_config.pressed.connect(save_current_settings)
	row1.add_child(btn_save_config)

	opt_server_preset.item_selected.connect(_on_server_preset_selected)

	# 第二行：风格模板与负向词 (自适应拉伸)
	var row2 = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	top_vbox.add_child(row2)

	var lbl_style = Label.new()
	lbl_style.text = "🎨 风格:"
	row2.add_child(lbl_style)

	var opt_style_preset = OptionButton.new()
	opt_style_preset.custom_minimum_size = Vector2(160, 34)
	var p_keys = AIAssetMgr.get_style_preset_keys()
	for i in range(p_keys.size()):
		var p_key = p_keys[i]
		var preset = AIAssetMgr.get_style_preset(p_key)
		opt_style_preset.add_item(preset.get("name", p_key), i)
		opt_style_preset.set_item_metadata(i, p_key)
	row2.add_child(opt_style_preset)

	txt_global_style = LineEdit.new()
	txt_global_style.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt_global_style.custom_minimum_size = Vector2(140, 34)
	row2.add_child(txt_global_style)

	var lbl_neg = Label.new()
	lbl_neg.text = "🚫 负向词:"
	row2.add_child(lbl_neg)

	txt_global_neg = LineEdit.new()
	txt_global_neg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt_global_neg.custom_minimum_size = Vector2(140, 34)
	row2.add_child(txt_global_neg)

	opt_style_preset.item_selected.connect(func(idx):
		var p_key = opt_style_preset.get_item_metadata(idx)
		var preset = AIAssetMgr.get_style_preset(p_key)
		txt_global_style.text = preset.get("prompt", "")
		txt_global_neg.text = preset.get("negative", "")
		ai_settings["global_style_preset"] = p_key
		ai_settings["global_style_prompt"] = txt_global_style.text
		ai_settings["global_negative_prompt"] = txt_global_neg.text
		AIAssetMgr.save_ai_settings(ai_settings)
	)

	# 第三行：全案一键批量生成与同步核心行动条 (居左顶格排列，绝不右溢截断！)
	var row3 = HBoxContainer.new()
	row3.add_theme_constant_override("separation", 12)
	top_vbox.add_child(row3)

	btn_batch_generate = Button.new()
	btn_batch_generate.text = "⚡ 批量生成全案所有待处理资产"
	btn_batch_generate.tooltip_text = "自动扫描全剧本中所有状态为待生成的背景、角色立绘差分、证物特写及配音并批量执行"
	btn_batch_generate.custom_minimum_size = Vector2(240, 36)
	style_button(btn_batch_generate, "batch")
	btn_batch_generate.pressed.connect(batch_generate_all_pending)
	row3.add_child(btn_batch_generate)

	btn_sync_manifest = Button.new()
	btn_sync_manifest.text = "🔄 扫描同步实体资产"
	btn_sync_manifest.tooltip_text = "从故事剧本和配置中刷新扫描所有人物、场景与物证资产清单"
	btn_sync_manifest.custom_minimum_size = Vector2(150, 36)
	style_button(btn_sync_manifest, "secondary")
	btn_sync_manifest.pressed.connect(sync_manifest)
	row3.add_child(btn_sync_manifest)

	var lbl_top_summary = Label.new()
	lbl_top_summary.text = "💡 提示：在左侧选择具体角色或场景，可针对单项或单个实体进行精准差分生成与视听调试。"
	lbl_top_summary.modulate = Color(0.65, 0.78, 0.9)
	lbl_top_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_top_summary.clip_text = true
	row3.add_child(lbl_top_summary)

	# 2. 中间分栏工作区
	var body_split = HBoxContainer.new()
	body_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_split.add_theme_constant_override("separation", 14)
	vbox_root.add_child(body_split)

	# --- 左侧：实体归属导航器 (紧凑 280px，留出更多画布空间) ---
	var left_panel = PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(280, 0)
	var lp_style = StyleBoxFlat.new()
	lp_style.bg_color = Color(0.07, 0.09, 0.13, 0.95)
	lp_style.set_border_width_all(1)
	lp_style.border_color = Color(0.25, 0.32, 0.45, 0.6)
	lp_style.set_corner_radius_all(8)
	left_panel.add_theme_stylebox_override("panel", lp_style)
	body_split.add_child(left_panel)

	var lp_margin = MarginContainer.new()
	lp_margin.add_theme_constant_override("margin_left", 10)
	lp_margin.add_theme_constant_override("margin_top", 10)
	lp_margin.add_theme_constant_override("margin_right", 10)
	lp_margin.add_theme_constant_override("margin_bottom", 10)
	left_panel.add_child(lp_margin)

	var lp_vbox = VBoxContainer.new()
	lp_vbox.add_theme_constant_override("separation", 8)
	lp_margin.add_child(lp_vbox)

	# 顶部分类切换按钮网格 (4大类)
	var cat_grid = GridContainer.new()
	cat_grid.columns = 2
	cat_grid.add_theme_constant_override("h_separation", 6)
	cat_grid.add_theme_constant_override("v_separation", 6)
	lp_vbox.add_child(cat_grid)

	btn_cat_characters = create_cat_button("👤 角色资产", "character")
	cat_grid.add_child(btn_cat_characters)

	btn_cat_scenes = create_cat_button("🔍 场景资产", "scene")
	cat_grid.add_child(btn_cat_scenes)

	btn_cat_clues = create_cat_button("🧩 道具证物", "clue")
	cat_grid.add_child(btn_cat_clues)

	btn_cat_shared = create_cat_button("🌐 全局公共", "shared")
	cat_grid.add_child(btn_cat_shared)

	# 检索过滤栏
	var search_row = HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 6)
	lp_vbox.add_child(search_row)

	txt_search = LineEdit.new()
	txt_search.placeholder_text = "🔍 搜索实体名称..."
	txt_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt_search.text_changed.connect(func(_t): refresh_entity_list())
	search_row.add_child(txt_search)

	opt_filter_status = OptionButton.new()
	opt_filter_status.custom_minimum_size = Vector2(95, 32)
	opt_filter_status.add_item("全部", 0)
	opt_filter_status.add_item("仅待生成", 1)
	opt_filter_status.add_item("仅已生成", 2)
	opt_filter_status.item_selected.connect(func(_idx): refresh_entity_list())
	search_row.add_child(opt_filter_status)

	lbl_nav_summary = Label.new()
	lbl_nav_summary.text = "共 0 个实体"
	lbl_nav_summary.modulate = Color(0.65, 0.72, 0.82)
	lbl_nav_summary.add_theme_font_size_override("font_size", 12)
	lp_vbox.add_child(lbl_nav_summary)

	var entity_scroll = ScrollContainer.new()
	entity_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lp_vbox.add_child(entity_scroll)

	vbox_entity_list = VBoxContainer.new()
	vbox_entity_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_entity_list.add_theme_constant_override("separation", 6)
	entity_scroll.add_child(vbox_entity_list)

	# --- 右侧：实体多维专属工坊 (Expanded) ---
	var right_panel = PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rp_style = StyleBoxFlat.new()
	rp_style.bg_color = Color(0.08, 0.10, 0.14, 0.95)
	rp_style.set_border_width_all(1)
	rp_style.border_color = Color(0.3, 0.38, 0.5, 0.6)
	rp_style.set_corner_radius_all(10)
	right_panel.add_theme_stylebox_override("panel", rp_style)
	body_split.add_child(right_panel)

	var rp_margin = MarginContainer.new()
	rp_margin.add_theme_constant_override("margin_left", 18)
	rp_margin.add_theme_constant_override("margin_top", 14)
	rp_margin.add_theme_constant_override("margin_right", 18)
	rp_margin.add_theme_constant_override("margin_bottom", 14)
	right_panel.add_child(rp_margin)

	var rp_vbox = VBoxContainer.new()
	rp_vbox.add_theme_constant_override("separation", 10)
	rp_margin.add_child(rp_vbox)

	# 右侧顶栏：实体标题、描述与一键操作
	var entity_header = HBoxContainer.new()
	entity_header.add_theme_constant_override("separation", 12)
	rp_vbox.add_child(entity_header)

	var title_box = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	entity_header.add_child(title_box)

	lbl_entity_title = Label.new()
	lbl_entity_title.text = "请在左侧选择实体"
	lbl_entity_title.add_theme_font_size_override("font_size", 18)
	lbl_entity_title.modulate = Color(1.0, 0.85, 0.35)
	lbl_entity_title.clip_text = true
	title_box.add_child(lbl_entity_title)

	lbl_entity_subtitle = Label.new()
	lbl_entity_subtitle.text = "选择一个角色、场景或道具，查看其名下的视听资产集合"
	lbl_entity_subtitle.modulate = Color(0.65, 0.75, 0.85)
	lbl_entity_subtitle.add_theme_font_size_override("font_size", 12)
	lbl_entity_subtitle.clip_text = true
	title_box.add_child(lbl_entity_subtitle)

	# 实体级批量生成按钮（显式突出展示，绝不截断）
	btn_batch_entity_pending = Button.new()
	btn_batch_entity_pending.text = "⚡ 批量生成本实体全部资产"
	btn_batch_entity_pending.tooltip_text = "批量生成当前选中的实体（角色/场景/道具）名下全部待处理的视听资产"
	btn_batch_entity_pending.custom_minimum_size = Vector2(185, 36)
	style_button(btn_batch_entity_pending, "batch")
	btn_batch_entity_pending.pressed.connect(_on_batch_current_entity_pending)
	entity_header.add_child(btn_batch_entity_pending)

	# 一键打开资源本地文件夹
	btn_open_entity_folder = Button.new()
	btn_open_entity_folder.text = "📂 资源目录"
	btn_open_entity_folder.tooltip_text = "在系统资源管理器中打开当前实体资产所在的本地目录"
	btn_open_entity_folder.custom_minimum_size = Vector2(100, 36)
	style_button(btn_open_entity_folder, "secondary")
	btn_open_entity_folder.pressed.connect(_on_open_current_entity_folder)
	entity_header.add_child(btn_open_entity_folder)

	var header_sep = HSeparator.new()
	rp_vbox.add_child(header_sep)

	# 右侧滚动工作台
	entity_content_scroll = ScrollContainer.new()
	entity_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rp_vbox.add_child(entity_content_scroll)

	vbox_entity_content = VBoxContainer.new()
	vbox_entity_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_entity_content.add_theme_constant_override("separation", 14)
	entity_content_scroll.add_child(vbox_entity_content)

	# 隐藏兼容提示词标签 (确保老自动化测试通过)
	lbl_combined_prompt = Label.new()
	lbl_combined_prompt.text = "合成提示词: -"
	lbl_combined_prompt.visible = false
	add_child(lbl_combined_prompt)

	# 3. 底部实时生成进度条与状态栏
	var bottom_panel = PanelContainer.new()
	var bot_style = StyleBoxFlat.new()
	bot_style.bg_color = Color(0.06, 0.08, 0.12, 0.95)
	bot_style.set_border_width_all(1)
	bot_style.border_color = Color(0.25, 0.35, 0.48, 0.5)
	bot_style.set_corner_radius_all(6)
	bottom_panel.add_theme_stylebox_override("panel", bot_style)
	vbox_root.add_child(bottom_panel)

	var bot_margin = MarginContainer.new()
	bot_margin.add_theme_constant_override("margin_left", 14)
	bot_margin.add_theme_constant_override("margin_top", 6)
	bot_margin.add_theme_constant_override("margin_right", 14)
	bot_margin.add_theme_constant_override("margin_bottom", 6)
	bottom_panel.add_child(bot_margin)

	var bot_hbox = HBoxContainer.new()
	bot_hbox.add_theme_constant_override("separation", 14)
	bot_margin.add_child(bot_hbox)

	lbl_gen_status = Label.new()
	lbl_gen_status.text = "⚪ 空闲"
	lbl_gen_status.modulate = Color(0.75, 0.85, 0.95)
	lbl_gen_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot_hbox.add_child(lbl_gen_status)

	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(240, 24)
	progress_bar.visible = false
	bot_hbox.add_child(progress_bar)

func create_cat_button(title: String, cat_id: String) -> Button:
	var btn = Button.new()
	btn.text = title
	btn.custom_minimum_size = Vector2(0, 36)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(func():
		switch_category(cat_id)
	)
	return btn

# --- 分类切换与实体选择 ---
func switch_category(cat_id: String) -> void:
	current_category = cat_id
	update_cat_buttons_style()
	refresh_entity_list()

func update_cat_buttons_style() -> void:
	var buttons = [
		{"btn": btn_cat_characters, "id": "character"},
		{"btn": btn_cat_scenes, "id": "scene"},
		{"btn": btn_cat_clues, "id": "clue"},
		{"btn": btn_cat_shared, "id": "shared"}
	]
	for b in buttons:
		var is_active = (b["id"] == current_category)
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.18, 0.26, 0.38, 0.95) if is_active else Color(0.10, 0.13, 0.18, 0.8)
		sb.set_border_width_all(2 if is_active else 1)
		sb.border_color = Color(1.0, 0.85, 0.35) if is_active else Color(0.3, 0.4, 0.5, 0.5)
		sb.set_corner_radius_all(6)
		b["btn"].add_theme_stylebox_override("normal", sb)

func load_data() -> void:
	ai_settings = AIAssetMgr.load_ai_settings()
	txt_comfy_host.text = ai_settings.get("comfyui_server", "http://127.0.0.1:8188")
	txt_comfy_user.text = ai_settings.get("comfyui_user", "")
	txt_comfy_pass.text = ai_settings.get("comfyui_password", "")
	txt_checkpoint.text = ai_settings.get("checkpoint", "sd_xl_turbo_1.0.safetensors")
	txt_global_style.text = ai_settings.get("global_style_prompt", "")
	txt_global_neg.text = ai_settings.get("global_negative_prompt", "")

	_refresh_env_dropdown()

	manifest_items = AIAssetMgr.load_manifest()
	if manifest_items.is_empty():
		manifest_items = AIAssetMgr.sync_manifest_with_project()
	
	entities_summary = AIAssetMgr.get_entities_summary(manifest_items)
	switch_category("character")

func sync_manifest() -> void:
	manifest_items = AIAssetMgr.sync_manifest_with_project()
	entities_summary = AIAssetMgr.get_entities_summary(manifest_items)
	refresh_entity_list()
	lbl_gen_status.text = "✅ 已扫描并按实体（角色/场景/道具/公共）同步全案资产！"

func refresh_entity_list() -> void:
	for child in vbox_entity_list.get_children():
		child.queue_free()

	entities_summary = AIAssetMgr.get_entities_summary(manifest_items)
	var search_text = txt_search.text.strip_edges().to_lower()
	var filter_status_idx = opt_filter_status.selected
	var entity_dict = {}

	match current_category:
		"character": entity_dict = entities_summary.get("characters", {})
		"scene": entity_dict = entities_summary.get("scenes", {})
		"clue": entity_dict = entities_summary.get("clues", {})
		"shared":
			var sh = entities_summary.get("shared", {})
			entity_dict = {"shared": sh}

	var visible_count = 0
	var first_matching_id = ""

	for eid in entity_dict:
		var ent = entity_dict[eid]
		var ename = ent.get("name", eid)
		var total = ent.get("total_count", 0)
		var ready_c = ent.get("ready_count", 0)

		# 过滤匹配
		if not search_text.is_empty():
			if not ename.to_lower().contains(search_text) and not eid.to_lower().contains(search_text):
				continue

		if filter_status_idx == 1 and ready_c == total and total > 0:
			continue # 仅待生成，排除全部生成的
		elif filter_status_idx == 2 and ready_c == 0 and total > 0:
			continue # 仅已生成，排除零生成的

		visible_count += 1
		if first_matching_id.is_empty():
			first_matching_id = eid

		var btn = create_entity_list_button(eid, ent)
		vbox_entity_list.add_child(btn)

	lbl_nav_summary.text = "共 %d 个实体 (当前分类)" % visible_count

	# 默认选中逻辑
	if not selected_entity_id.is_empty() and entity_dict.has(selected_entity_id):
		select_entity(selected_entity_id)
	elif not first_matching_id.is_empty():
		select_entity(first_matching_id)
	else:
		clear_entity_workbench()

func create_entity_list_button(eid: String, ent: Dictionary) -> Button:
	var btn = Button.new()
	var ename = ent.get("name", eid)
	var total = ent.get("total_count", 0)
	var ready_c = ent.get("ready_count", 0)
	var is_sel = (eid == selected_entity_id)

	var icon_badge = "👤 "
	var meta_info = ""
	if current_category == "character":
		icon_badge = "👤 "
		var sp_cnt = ent.get("sprites", []).size()
		var vc_cnt = ent.get("voices", []).size()
		meta_info = "立绘: %d | 配音: %d" % [sp_cnt, vc_cnt]
	elif current_category == "scene":
		icon_badge = "🔍 "
		var has_bg = "🟢" if ent.get("background") != null and ent["background"].get("status") == "ready" else "⏳"
		var has_bgm = "🟢" if ent.get("bgm") != null and ent["bgm"].get("status") == "ready" else "⏳"
		meta_info = "背景: %s | BGM: %s" % [has_bg, has_bgm]
	elif current_category == "clue":
		icon_badge = "🧩 "
		var has_img = "🟢" if ent.get("image") != null and ent["image"].get("status") == "ready" else "⏳"
		meta_info = "特写: %s" % has_img
	else:
		icon_badge = "🌐 "
		meta_info = "公共素材: %d/%d" % [ready_c, total]

	var status_tag = "🟢" if ready_c >= total and total > 0 else "⏳"
	btn.text = "%s %s %s\n  └ %s (%d/%d 已生成)" % [status_tag, icon_badge, ename, meta_info, ready_c, total]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 52)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.24, 0.35, 0.95) if is_sel else Color(0.10, 0.13, 0.18, 0.85)
	sb.set_border_width_all(2 if is_sel else 1)
	sb.border_color = Color(1.0, 0.85, 0.35) if is_sel else (Color(0.3, 0.7, 0.4, 0.4) if ready_c >= total and total > 0 else Color(0.7, 0.5, 0.2, 0.4))
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	btn.add_theme_stylebox_override("normal", sb)

	btn.pressed.connect(func():
		select_entity(eid)
	)
	return btn

# --- 选中实体并渲染专属工作台 ---
func select_entity(eid: String) -> void:
	selected_entity_id = eid
	update_entity_list_highlight()

	match current_category:
		"character":
			var ent = entities_summary.get("characters", {}).get(eid, {})
			render_character_workbench(eid, ent)
		"scene":
			var ent = entities_summary.get("scenes", {}).get(eid, {})
			render_scene_workbench(eid, ent)
		"clue":
			var ent = entities_summary.get("clues", {}).get(eid, {})
			render_clue_workbench(eid, ent)
		"shared":
			var ent = entities_summary.get("shared", {})
			render_shared_workbench(ent)

func update_entity_list_highlight() -> void:
	var children = vbox_entity_list.get_children()
	for child in children:
		if child is Button:
			# 根据是否为选中的按钮更新边框与高亮
			var btn = child as Button
			var is_sel = btn.text.contains(selected_entity_id) or (selected_entity_id == "shared" and btn.text.contains("全局公共"))
			# 简单刷新列表外观
			var sb = btn.get_theme_stylebox("normal") as StyleBoxFlat
			if sb:
				sb.border_color = Color(1.0, 0.85, 0.35) if is_sel else Color(0.3, 0.4, 0.5, 0.4)
				sb.set_border_width_all(2 if is_sel else 1)

func clear_entity_workbench() -> void:
	lbl_entity_title.text = "暂无匹配实体"
	lbl_entity_subtitle.text = "请清除搜索关键字或切换其他分类"
	for child in vbox_entity_content.get_children():
		child.queue_free()

# --- 渲染 1：角色资产专属工坊 ---
func render_character_workbench(cid: String, ent: Dictionary) -> void:
	for child in vbox_entity_content.get_children():
		child.queue_free()

	var cname = ent.get("name", cid)
	lbl_entity_title.text = "👤 角色资产工坊: " + cname
	lbl_entity_subtitle.text = "身份: %s | 配音声线: %s | 共 %d 个差分立绘，%d 条配音对白" % [
		ent.get("identity", "登场人物"),
		ent.get("voice_role", "未指定"),
		ent.get("sprites", []).size(),
		ent.get("voices", []).size()
	]
	btn_batch_entity_pending.text = "⚡ 批量生成「%s」全部资产" % cname
	btn_batch_entity_pending.visible = true

	# 1. 角色基础形象与声线设定卡片
	var base_panel = create_section_card("🎭 基础设定与声线配置 (底模继承)")
	vbox_entity_content.add_child(base_panel)
	var base_vbox = get_card_vbox(base_panel)

	var prompt_row = HBoxContainer.new()
	prompt_row.add_theme_constant_override("separation", 10)
	base_vbox.add_child(prompt_row)

	var lbl_p = Label.new()
	lbl_p.text = "基础外貌 Prompt:"
	lbl_p.custom_minimum_size = Vector2(120, 0)
	prompt_row.add_child(lbl_p)

	var txt_base_prompt = LineEdit.new()
	txt_base_prompt.text = ent.get("base_prompt", "")
	txt_base_prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt_base_prompt.text_changed.connect(func(new_text):
		ent["base_prompt"] = new_text.strip_edges()
	)
	prompt_row.add_child(txt_base_prompt)

	var voice_row = HBoxContainer.new()
	voice_row.add_theme_constant_override("separation", 10)
	base_vbox.add_child(voice_row)

	var lbl_v = Label.new()
	lbl_v.text = "配音声线 (TTS Role):"
	lbl_v.custom_minimum_size = Vector2(120, 0)
	voice_row.add_child(lbl_v)

	var txt_voice_role = LineEdit.new()
	txt_voice_role.text = ent.get("voice_role", "zh-CN-YunxiNeural")
	txt_voice_role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt_voice_role.text_changed.connect(func(new_role):
		ent["voice_role"] = new_role.strip_edges()
		for vc in ent.get("voices", []):
			vc["voice_role"] = new_role.strip_edges()
	)
	voice_row.add_child(txt_voice_role)

	var btn_test_voice = Button.new()
	btn_test_voice.text = "▶ 试听声线"
	btn_test_voice.custom_minimum_size = Vector2(100, 34)
	style_button(btn_test_voice, "action")
	btn_test_voice.pressed.connect(func():
		test_character_voice(ent)
	)
	voice_row.add_child(btn_test_voice)

	# 角色资产工坊内部防遮挡子视图切换器 (立绘相册 vs 台词配音池)
	var subtab_nav = HBoxContainer.new()
	subtab_nav.add_theme_constant_override("separation", 10)
	vbox_entity_content.add_child(subtab_nav)

	var btn_sub_sprites = Button.new()
	btn_sub_sprites.text = "🎨 表情立绘差分相册 (%d 项)" % ent.get("sprites", []).size()
	btn_sub_sprites.custom_minimum_size = Vector2(210, 36)
	subtab_nav.add_child(btn_sub_sprites)

	var btn_sub_voices = Button.new()
	btn_sub_voices.text = "🎙️ 角色台词配音池 (%d 句对白)" % ent.get("voices", []).size()
	btn_sub_voices.custom_minimum_size = Vector2(210, 36)
	subtab_nav.add_child(btn_sub_voices)

	var btn_sub_both = Button.new()
	btn_sub_both.text = "📑 全部展开平铺"
	btn_sub_both.custom_minimum_size = Vector2(130, 36)
	subtab_nav.add_child(btn_sub_both)

	# 2. 表情立绘差分相册
	var btn_pose_editor = Button.new()
	btn_pose_editor.text = "📐 3D 姿态工坊"
	btn_pose_editor.custom_minimum_size = Vector2(130, 32)
	btn_pose_editor.tooltip_text = "打开 3D 人体骨骼姿态工坊，基于全新 3D 肢体动作创建立绘"
	style_button(btn_pose_editor, "action")
	btn_pose_editor.pressed.connect(func():
		open_pose_editor_dialog(cid, ent)
	)

	var btn_add_sprite = Button.new()
	btn_add_sprite.text = "➕ 新增立绘差分"
	btn_add_sprite.custom_minimum_size = Vector2(130, 32)
	style_button(btn_add_sprite, "create")
	btn_add_sprite.pressed.connect(func():
		open_add_sprite_dialog(cid, ent)
	)

	var btn_batch_sprites = Button.new()
	btn_batch_sprites.text = "⚡ 批量生成本角色全部立绘"
	btn_batch_sprites.custom_minimum_size = Vector2(185, 32)
	style_button(btn_batch_sprites, "batch")
	btn_batch_sprites.pressed.connect(func():
		_on_batch_character_sprites_pending(cid, ent)
	)

	var sprites_panel = create_section_card(
		"🎨 表情立绘差分相册 (%d 项)" % ent.get("sprites", []).size(),
		[btn_pose_editor, btn_add_sprite, btn_batch_sprites]
	)
	vbox_entity_content.add_child(sprites_panel)
	var sprites_vbox = get_card_vbox(sprites_panel)

	var sprites = ent.get("sprites", [])
	if sprites.is_empty():
		var empty_box = VBoxContainer.new()
		empty_box.add_theme_constant_override("separation", 10)
		sprites_vbox.add_child(empty_box)

		var lbl_empty = Label.new()
		lbl_empty.text = "暂无立绘差分配置。您可以点击右上角【➕ 新增立绘差分】自定义表情，或点击下方按钮直接由 AI 绘制首张立绘！"
		lbl_empty.modulate = Color(0.65, 0.78, 0.9)
		empty_box.add_child(lbl_empty)

		var btn_quick_first = Button.new()
		btn_quick_first.text = "🎨 依据基础外貌 Prompt 快速生成首张立绘"
		btn_quick_first.custom_minimum_size = Vector2(280, 36)
		style_button(btn_quick_first, "action")
		btn_quick_first.pressed.connect(func():
			proactive_generate_character_sprite(cid, ent)
		)
		empty_box.add_child(btn_quick_first)
	else:
		var sprites_grid = HFlowContainer.new()
		sprites_grid.add_theme_constant_override("h_separation", 14)
		sprites_grid.add_theme_constant_override("v_separation", 14)
		sprites_vbox.add_child(sprites_grid)
		for sp in sprites:
			var card = create_sprite_card(sp)
			sprites_grid.add_child(card)

	# 3. 角色台词配音池
	var btn_add_voice = Button.new()
	btn_add_voice.text = "➕ 录入台词配音"
	btn_add_voice.custom_minimum_size = Vector2(130, 32)
	style_button(btn_add_voice, "create")
	btn_add_voice.pressed.connect(func():
		open_add_voice_dialog(cid, ent)
	)

	var btn_batch_voices = Button.new()
	btn_batch_voices.text = "⚡ 批量生成本角色全部配音"
	btn_batch_voices.custom_minimum_size = Vector2(185, 32)
	style_button(btn_batch_voices, "batch")
	btn_batch_voices.pressed.connect(func():
		_on_batch_character_voices_pending(cid, ent)
	)

	var voices_panel = create_section_card(
		"🎙️ 角色台词配音池 (%d 句对白)" % ent.get("voices", []).size(),
		[btn_add_voice, btn_batch_voices]
	)
	vbox_entity_content.add_child(voices_panel)
	var voices_vbox = get_card_vbox(voices_panel)

	var voices = ent.get("voices", [])
	if voices.is_empty():
		var empty_v_box = VBoxContainer.new()
		empty_v_box.add_theme_constant_override("separation", 10)
		voices_vbox.add_child(empty_v_box)

		var lbl_no_v = Label.new()
		lbl_no_v.text = "暂无该角色的台词记录。您可以点击右上角【➕ 录入台词配音】或下方按钮添加对白！"
		lbl_no_v.modulate = Color(0.6, 0.7, 0.8)
		empty_v_box.add_child(lbl_no_v)

		var btn_quick_v = Button.new()
		btn_quick_v.text = "🎙️ 立即录入第一句对白台词"
		btn_quick_v.custom_minimum_size = Vector2(240, 36)
		style_button(btn_quick_v, "create")
		btn_quick_v.pressed.connect(func():
			open_add_voice_dialog(cid, ent)
		)
		empty_v_box.add_child(btn_quick_v)
	else:
		for vc in voices:
			var row = create_voice_line_row(vc)
			voices_vbox.add_child(row)

	var update_char_subtab = func():
		if char_workbench_subtab == "voices":
			sprites_panel.visible = false
			voices_panel.visible = true
			style_button(btn_sub_sprites, "secondary")
			style_button(btn_sub_voices, "action")
			style_button(btn_sub_both, "secondary")
		elif char_workbench_subtab == "both":
			sprites_panel.visible = true
			voices_panel.visible = true
			style_button(btn_sub_sprites, "secondary")
			style_button(btn_sub_voices, "secondary")
			style_button(btn_sub_both, "action")
		else: # "sprites"
			sprites_panel.visible = true
			voices_panel.visible = false
			style_button(btn_sub_sprites, "action")
			style_button(btn_sub_voices, "secondary")
			style_button(btn_sub_both, "secondary")

	btn_sub_sprites.pressed.connect(func():
		char_workbench_subtab = "sprites"
		update_char_subtab.call()
	)
	btn_sub_voices.pressed.connect(func():
		char_workbench_subtab = "voices"
		update_char_subtab.call()
	)
	btn_sub_both.pressed.connect(func():
		char_workbench_subtab = "both"
		update_char_subtab.call()
	)

	update_char_subtab.call()

# --- 渲染 2：场景资产专属工坊 ---
func render_scene_workbench(sc_id: String, ent: Dictionary) -> void:
	for child in vbox_entity_content.get_children():
		child.queue_free()

	var sc_name = ent.get("name", sc_id)
	lbl_entity_title.text = "🔍 场景资产工坊: " + sc_name
	lbl_entity_subtitle.text = "场景标识: %s | 包含背景大图与专属氛围配乐" % sc_id
	btn_batch_entity_pending.text = "⚡ 批量生成「%s」全部素材" % sc_name
	btn_batch_entity_pending.visible = true

	# 1. 场景背景大图卡片
	var btn_batch_scene = Button.new()
	btn_batch_scene.text = "⚡ 批量生成本场景素材"
	btn_batch_scene.custom_minimum_size = Vector2(175, 32)
	style_button(btn_batch_scene, "batch")
	btn_batch_scene.pressed.connect(func():
		_on_batch_scene_pending(sc_id, ent)
	)

	var bg_panel = create_section_card("🖼️ 场景背景大图 (960x540 原生宽屏)", [btn_batch_scene])
	vbox_entity_content.add_child(bg_panel)
	var bg_vbox = get_card_vbox(bg_panel)

	var bg_item = ent.get("background")
	if bg_item != null:
		var preview_box = HBoxContainer.new()
		preview_box.add_theme_constant_override("separation", 16)
		bg_vbox.add_child(preview_box)

		# 大预览框
		var frame = PanelContainer.new()
		frame.custom_minimum_size = Vector2(400, 225)
		var f_style = StyleBoxFlat.new()
		f_style.bg_color = Color(0.04, 0.05, 0.08, 0.95)
		f_style.set_border_width_all(1)
		f_style.border_color = Color(0.3, 0.4, 0.55, 0.6)
		f_style.set_corner_radius_all(6)
		frame.add_theme_stylebox_override("panel", f_style)
		preview_box.add_child(frame)

		var img_rect = TextureRect.new()
		img_rect.custom_minimum_size = Vector2(400, 225)
		img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.add_child(img_rect)
		load_texture_to_rect(img_rect, bg_item.get("local_path", ""))

		# 右侧提示词与操作
		var info_vbox = VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vbox.add_theme_constant_override("separation", 8)
		preview_box.add_child(info_vbox)

		var path_lbl = Label.new()
		path_lbl.text = "路径: " + bg_item.get("local_path", "")
		path_lbl.modulate = Color(0.65, 0.75, 0.85)
		info_vbox.add_child(path_lbl)

		var is_ready = (bg_item.get("status", "pending") == "ready")
		var st_hbox = HBoxContainer.new()
		st_hbox.add_theme_constant_override("separation", 8)
		info_vbox.add_child(st_hbox)

		var lbl_st = Label.new()
		lbl_st.text = "资产状态:"
		lbl_st.modulate = Color(0.7, 0.8, 0.9)
		st_hbox.add_child(lbl_st)

		var opt_bg_st = OptionButton.new()
		opt_bg_st.add_item("🟢 已生成", 0)
		opt_bg_st.add_item("⏳ 待生成", 1)
		opt_bg_st.selected = 0 if is_ready else 1
		opt_bg_st.custom_minimum_size = Vector2(115, 28)
		opt_bg_st.tooltip_text = "手动修改场景背景状态（已生成 / 待生成）"
		opt_bg_st.item_selected.connect(func(idx: int):
			var new_st = "ready" if idx == 0 else "pending"
			change_item_status(bg_item, new_st)
		)
		st_hbox.add_child(opt_bg_st)

		var lbl_pr = Label.new()
		lbl_pr.text = "场景描述 Prompt:"
		info_vbox.add_child(lbl_pr)

		var txt_bg_prompt = TextEdit.new()
		txt_bg_prompt.text = bg_item.get("prompt", "")
		txt_bg_prompt.custom_minimum_size = Vector2(0, 70)
		txt_bg_prompt.text_changed.connect(func():
			bg_item["prompt"] = txt_bg_prompt.text.strip_edges()
			AIAssetMgr.save_manifest(manifest_items)
		)
		info_vbox.add_child(txt_bg_prompt)

		var act_hbox = HBoxContainer.new()
		act_hbox.add_theme_constant_override("separation", 10)
		info_vbox.add_child(act_hbox)

		var btn_gen_bg = Button.new()
		btn_gen_bg.text = "🎨 生成 / 重新生成背景"
		btn_gen_bg.custom_minimum_size = Vector2(180, 36)
		style_button(btn_gen_bg, "action")
		btn_gen_bg.pressed.connect(func():
			start_single_generation(bg_item)
		)
		act_hbox.add_child(btn_gen_bg)

		var btn_import_bg = Button.new()
		btn_import_bg.text = "📥 导入外部背景"
		btn_import_bg.custom_minimum_size = Vector2(130, 36)
		style_button(btn_import_bg, "secondary")
		btn_import_bg.pressed.connect(func():
			import_external_asset_for_item(bg_item)
		)
		act_hbox.add_child(btn_import_bg)

		var btn_loc_bg = Button.new()
		btn_loc_bg.text = "📂 定位文件"
		btn_loc_bg.custom_minimum_size = Vector2(100, 36)
		style_button(btn_loc_bg, "secondary")
		btn_loc_bg.pressed.connect(func():
			open_file_in_explorer(bg_item.get("local_path", ""))
		)
		act_hbox.add_child(btn_loc_bg)
	else:
		var no_bg_box = VBoxContainer.new()
		no_bg_box.add_theme_constant_override("separation", 10)
		bg_vbox.add_child(no_bg_box)

		var lbl_no_bg = Label.new()
		lbl_no_bg.text = "当前场景尚未配置背景图。您可以点击下方按钮，由 AI 立即为该场景绘制 16:9 高清背景！"
		lbl_no_bg.modulate = Color(0.65, 0.78, 0.9)
		no_bg_box.add_child(lbl_no_bg)

		var btn_add_bg = Button.new()
		btn_add_bg.text = "🎨 依据场景名称生成 16:9 场景背景大图"
		btn_add_bg.custom_minimum_size = Vector2(280, 36)
		style_button(btn_add_bg, "create")
		btn_add_bg.pressed.connect(func():
			proactive_generate_scene_background(sc_id, ent)
		)
		no_bg_box.add_child(btn_add_bg)

	# 2. 场景配乐与环境氛围音
	var audio_panel = create_section_card("🎵 专属环境氛围音 & 场景 BGM")
	vbox_entity_content.add_child(audio_panel)
	var audio_vbox = get_card_vbox(audio_panel)

	var bgm_item = ent.get("bgm")
	if bgm_item != null:
		var bgm_row = create_audio_line_row("场景 BGM", bgm_item)
		audio_vbox.add_child(bgm_row)
	else:
		var lbl_no_bgm = Label.new()
		lbl_no_bgm.text = "当前场景未指定独立 BGM，将使用默认背景音乐。"
		lbl_no_bgm.modulate = Color(0.6, 0.7, 0.8)
		audio_vbox.add_child(lbl_no_bgm)

# --- 渲染 3：道具证物专属工坊 ---
func render_clue_workbench(clue_id: String, ent: Dictionary) -> void:
	for child in vbox_entity_content.get_children():
		child.queue_free()

	var clue_name = ent.get("name", clue_id)
	lbl_entity_title.text = "🧩 道具证物工坊: " + clue_name
	lbl_entity_subtitle.text = "证物 ID: %s | 包含高清特写图与调查音效" % clue_id
	btn_batch_entity_pending.text = "⚡ 批量生成「%s」特写" % clue_name
	btn_batch_entity_pending.visible = true

	var btn_batch_clue = Button.new()
	btn_batch_clue.text = "⚡ 批量生成本证物素材"
	btn_batch_clue.custom_minimum_size = Vector2(175, 32)
	style_button(btn_batch_clue, "batch")
	btn_batch_clue.pressed.connect(func():
		_on_batch_clue_pending(clue_id, ent)
	)

	var item_card = create_section_card("🖼️ 证物特写图像 (512x512 纯背景透明特写)", [btn_batch_clue])
	vbox_entity_content.add_child(item_card)
	var card_vbox = get_card_vbox(item_card)

	var clue_img_item = ent.get("image")
	if clue_img_item != null:
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 16)
		card_vbox.add_child(hbox)

		var frame = PanelContainer.new()
		frame.custom_minimum_size = Vector2(200, 200)
		var f_style = StyleBoxFlat.new()
		f_style.bg_color = Color(0.04, 0.05, 0.08, 0.95)
		f_style.set_border_width_all(1)
		f_style.border_color = Color(0.3, 0.4, 0.55, 0.6)
		f_style.set_corner_radius_all(6)
		frame.add_theme_stylebox_override("panel", f_style)
		hbox.add_child(frame)

		var img_rect = TextureRect.new()
		img_rect.custom_minimum_size = Vector2(200, 200)
		img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.add_child(img_rect)
		load_texture_to_rect(img_rect, clue_img_item.get("local_path", ""))

		var info_vbox = VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vbox.add_theme_constant_override("separation", 8)
		hbox.add_child(info_vbox)

		var p_lbl = Label.new()
		p_lbl.text = "路径: " + clue_img_item.get("local_path", "")
		p_lbl.modulate = Color(0.65, 0.75, 0.85)
		info_vbox.add_child(p_lbl)

		var is_ready = (clue_img_item.get("status", "pending") == "ready")
		var st_hbox = HBoxContainer.new()
		st_hbox.add_theme_constant_override("separation", 8)
		info_vbox.add_child(st_hbox)

		var lbl_st = Label.new()
		lbl_st.text = "资产状态:"
		lbl_st.modulate = Color(0.7, 0.8, 0.9)
		st_hbox.add_child(lbl_st)

		var opt_clue_st = OptionButton.new()
		opt_clue_st.add_item("🟢 已生成", 0)
		opt_clue_st.add_item("⏳ 待生成", 1)
		opt_clue_st.selected = 0 if is_ready else 1
		opt_clue_st.custom_minimum_size = Vector2(115, 28)
		opt_clue_st.tooltip_text = "手动修改物证特写状态（已生成 / 待生成）"
		opt_clue_st.item_selected.connect(func(idx: int):
			var new_st = "ready" if idx == 0 else "pending"
			change_item_status(clue_img_item, new_st)
		)
		st_hbox.add_child(opt_clue_st)

		var txt_prompt = TextEdit.new()
		txt_prompt.text = clue_img_item.get("prompt", "")
		txt_prompt.custom_minimum_size = Vector2(0, 60)
		txt_prompt.text_changed.connect(func():
			clue_img_item["prompt"] = txt_prompt.text.strip_edges()
			AIAssetMgr.save_manifest(manifest_items)
		)
		info_vbox.add_child(txt_prompt)

		var act_hbox = HBoxContainer.new()
		act_hbox.add_theme_constant_override("separation", 10)
		info_vbox.add_child(act_hbox)

		var btn_gen = Button.new()
		btn_gen.text = "🎨 生成特写"
		btn_gen.custom_minimum_size = Vector2(130, 36)
		style_button(btn_gen, "action")
		btn_gen.pressed.connect(func():
			start_single_generation(clue_img_item)
		)
		act_hbox.add_child(btn_gen)

		var btn_import_clue = Button.new()
		btn_import_clue.text = "📥 导入外部特写"
		btn_import_clue.custom_minimum_size = Vector2(130, 36)
		style_button(btn_import_clue, "secondary")
		btn_import_clue.pressed.connect(func():
			import_external_asset_for_item(clue_img_item)
		)
		act_hbox.add_child(btn_import_clue)

		var btn_loc = Button.new()
		btn_loc.text = "📂 定位文件"
		btn_loc.custom_minimum_size = Vector2(100, 36)
		style_button(btn_loc, "secondary")
		btn_loc.pressed.connect(func():
			open_file_in_explorer(clue_img_item.get("local_path", ""))
		)
		act_hbox.add_child(btn_loc)
	else:
		var no_clue_box = VBoxContainer.new()
		no_clue_box.add_theme_constant_override("separation", 10)
		card_vbox.add_child(no_clue_box)

		var lbl_no_clue = Label.new()
		lbl_no_clue.text = "当前证物尚未配置特写图像。您可以点击下方按钮，由 AI 立即生成 512x512 纯背景特写！"
		lbl_no_clue.modulate = Color(0.65, 0.78, 0.9)
		no_clue_box.add_child(lbl_no_clue)

		var btn_add_clue = Button.new()
		btn_add_clue.text = "🎨 依据证物名称生成 512x512 特写图"
		btn_add_clue.custom_minimum_size = Vector2(260, 36)
		style_button(btn_add_clue, "create")
		btn_add_clue.pressed.connect(func():
			proactive_generate_clue_image(clue_id, ent)
		)
		no_clue_box.add_child(btn_add_clue)

# --- 渲染 4：全局公共资产工坊 ---
func render_shared_workbench(ent: Dictionary) -> void:
	for child in vbox_entity_content.get_children():
		child.queue_free()

	lbl_entity_title.text = "🌐 全局公共资产库"
	lbl_entity_subtitle.text = "跨场景复用的通用 BGM、环境音效与系统交互音频"
	btn_batch_entity_pending.text = "⚡ 批量生成待处理公共音频"
	btn_batch_entity_pending.visible = true

	var btn_batch_shared = Button.new()
	btn_batch_shared.text = "⚡ 批量生成待处理公共音频"
	btn_batch_shared.custom_minimum_size = Vector2(185, 32)
	style_button(btn_batch_shared, "batch")
	btn_batch_shared.pressed.connect(func():
		var pending = []
		for it in ent.get("items", []):
			if it.get("status", "pending") != "ready":
				pending.append(it)
		if pending.is_empty():
			lbl_gen_status.text = "公共资产库内所有音频均已生成！"
			return
		execute_batch_generation(pending, "公共音频")
	)

	var card = create_section_card("🎵 公共配乐与系统音效", [btn_batch_shared])
	vbox_entity_content.add_child(card)
	var card_vbox = get_card_vbox(card)

	var items = ent.get("items", [])
	if items.is_empty():
		var lbl_empty = Label.new()
		lbl_empty.text = "暂无未分类的公共音频。"
		lbl_empty.modulate = Color(0.6, 0.7, 0.8)
		card_vbox.add_child(lbl_empty)
	else:
		for it in items:
			var row = create_audio_line_row(it.get("name", it.get("id")), it)
			card_vbox.add_child(row)

# --- 通用组件构造器 ---
func create_section_card(title: String, right_controls: Array = []) -> PanelContainer:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.11, 0.9)
	style.set_border_width_all(1)
	style.border_color = Color(0.2, 0.28, 0.4, 0.5)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	panel.set_meta("vbox", vbox)

	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(header_hbox)

	var lbl = Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.modulate = Color(0.95, 0.85, 0.45)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.clip_text = true
	header_hbox.add_child(lbl)

	for ctrl in right_controls:
		if ctrl is Control:
			header_hbox.add_child(ctrl)

	return panel

func get_card_vbox(panel: PanelContainer) -> VBoxContainer:
	if panel and panel.has_meta("vbox"):
		return panel.get_meta("vbox")
	return null

func create_sprite_card(item: Dictionary) -> PanelContainer:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(210, 395)
	var c_style = StyleBoxFlat.new()
	c_style.bg_color = Color(0.05, 0.06, 0.09, 0.95)
	c_style.set_border_width_all(1)
	c_style.border_color = Color(0.3, 0.4, 0.5, 0.5)
	c_style.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", c_style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# 缩略图
	var thumb_frame = PanelContainer.new()
	thumb_frame.custom_minimum_size = Vector2(190, 150)
	var tf_style = StyleBoxFlat.new()
	tf_style.bg_color = Color(0.02, 0.03, 0.05, 1.0)
	tf_style.set_corner_radius_all(4)
	thumb_frame.add_theme_stylebox_override("panel", tf_style)
	vbox.add_child(thumb_frame)

	var img_rect = TextureRect.new()
	img_rect.custom_minimum_size = Vector2(190, 150)
	img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	thumb_frame.add_child(img_rect)
	load_texture_to_rect(img_rect, item.get("local_path", ""))

	var name_lbl = Label.new()
	name_lbl.text = item.get("name", item.get("id"))
	name_lbl.clip_text = true
	name_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(name_lbl)

	# 角色形象基准与差分继承状态栏
	var cid = item.get("character_id", item.get("entity_id", ""))
	var is_base = item.get("is_base", false)
	if not item.has("is_base"):
		if item.get("id", "") == "char_" + cid or item.get("name", "").contains("基础"):
			is_base = true

	var base_row = HBoxContainer.new()
	base_row.add_theme_constant_override("separation", 4)
	vbox.add_child(base_row)

	# 动作姿态绑定栏 (8套 3D 姿态预设快速切换，联动 3D 姿态工坊)
	var pose_row = HBoxContainer.new()
	pose_row.add_theme_constant_override("separation", 4)
	pose_row.visible = (item.get("generation_mode", "") == "pose")

	if is_base:
		var lbl_base_tag = Label.new()
		lbl_base_tag.text = "🌟 形象基准 (Base)"
		lbl_base_tag.add_theme_font_size_override("font_size", 11)
		lbl_base_tag.modulate = Color(1.0, 0.85, 0.35)
		lbl_base_tag.tooltip_text = "本立绘为形象基准锚点，其他差分将以此为底图进行面部差分重绘"
		lbl_base_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		base_row.add_child(lbl_base_tag)
		c_style.border_color = Color(0.85, 0.70, 0.30, 0.8)
		c_style.set_border_width_all(2)
	else:
		var is_pose_item = (item.get("generation_mode", "") == "pose")
		var opt_mode_tag = OptionButton.new()
		opt_mode_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opt_mode_tag.custom_minimum_size = Vector2(0, 22)
		opt_mode_tag.add_theme_font_size_override("font_size", 10)
		opt_mode_tag.add_item("🎭 微表情自然差分", 0)
		opt_mode_tag.add_item("🧍‍♂️ 3D姿态新立绘", 1)
		opt_mode_tag.selected = 1 if is_pose_item else 0
		opt_mode_tag.tooltip_text = "切换生成模式：微表情差分（100% 保持身材衣服）或 3D 姿态新立绘"
		opt_mode_tag.item_selected.connect(func(idx: int):
			var now_pose = (idx == 1)
			item["generation_mode"] = "pose" if now_pose else "expression"
			pose_row.visible = now_pose
			AIAssetMgr.save_manifest(manifest_items)
		)
		base_row.add_child(opt_mode_tag)

		var btn_set_base = Button.new()
		btn_set_base.text = "设为基准"
		btn_set_base.custom_minimum_size = Vector2(58, 20)
		btn_set_base.add_theme_font_size_override("font_size", 10)
		btn_set_base.tooltip_text = "将此立绘设为本角色后续表情差分的基准原画"
		style_button(btn_set_base, "secondary")
		btn_set_base.pressed.connect(func():
			set_character_base_sprite(cid, item)
		)
		base_row.add_child(btn_set_base)

	vbox.add_child(pose_row)

	var lbl_pose_tag = Label.new()
	lbl_pose_tag.text = "📐 动作:"
	lbl_pose_tag.add_theme_font_size_override("font_size", 10)
	lbl_pose_tag.modulate = Color(0.65, 0.85, 0.75)
	pose_row.add_child(lbl_pose_tag)

	var opt_card_pose = OptionButton.new()
	opt_card_pose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt_card_pose.custom_minimum_size = Vector2(0, 24)
	opt_card_pose.add_theme_font_size_override("font_size", 10)
	opt_card_pose.tooltip_text = "选择本差分绑定的 3D 动作姿态"

	var p_keys = [
		"standing_calm", "crossed_arms", "chin_touch", "pointing_accuse",
		"hands_on_hips", "pocket_hands", "shrug_spread", "hold_clue"
	]
	var p_icons = ["🧍", "🙅", "🤔", "👉", "🥋", "🧥", "🤷", "🔍"]
	var p_labels = ["标准站姿", "双手抱胸", "手托下巴", "一指指证", "双手叉腰", "插兜侧立", "摊手无奈", "托举物证"]
	var cur_pose = item.get("pose_preset", "standing_calm")
	var sel_p_idx = 0
	for p_i in range(p_keys.size()):
		var pk = p_keys[p_i]
		opt_card_pose.add_item("%s %s" % [p_icons[p_i], p_labels[p_i]], p_i)
		opt_card_pose.set_item_metadata(p_i, pk)
		if pk == cur_pose:
			sel_p_idx = p_i
	opt_card_pose.selected = sel_p_idx
	opt_card_pose.item_selected.connect(func(idx: int):
		var chosen_k = opt_card_pose.get_item_metadata(idx)
		item["pose_preset"] = chosen_k
		item["generation_mode"] = "pose"
		AIAssetMgr.save_manifest(manifest_items)
	)
	pose_row.add_child(opt_card_pose)

	var btn_pose_tweak = Button.new()
	btn_pose_tweak.text = "3D"
	btn_pose_tweak.custom_minimum_size = Vector2(28, 22)
	btn_pose_tweak.add_theme_font_size_override("font_size", 10)
	btn_pose_tweak.tooltip_text = "打开 3D 姿态工坊预览与微调此动作"
	style_button(btn_pose_tweak, "secondary")
	btn_pose_tweak.pressed.connect(func():
		if dlg_pose_editor:
			var cid_inner = item.get("character_id", item.get("entity_id", ""))
			var ent_inner = entities_summary.get("characters", {}).get(cid_inner, {})
			dlg_pose_editor.open_for_character(cid_inner, ent_inner)
			dlg_pose_editor.select_preset(item.get("pose_preset", "standing_calm"))
	)
	pose_row.add_child(btn_pose_tweak)

	# 提示词展示与实时编辑框 (专注微表情神态，基础特征与动作自动组装)
	var lbl_prompt_tag = Label.new()
	lbl_prompt_tag.text = "🎭 专属微表情神态 (中文):"
	lbl_prompt_tag.add_theme_font_size_override("font_size", 10)
	lbl_prompt_tag.modulate = Color(0.75, 0.85, 0.95)
	vbox.add_child(lbl_prompt_tag)

	var txt_card_prompt = TextEdit.new()
	txt_card_prompt.text = item.get("prompt", "")
	txt_card_prompt.custom_minimum_size = Vector2(0, 52)
	txt_card_prompt.placeholder_text = "输入本立绘差分的中文神态微表情..."
	txt_card_prompt.tooltip_text = "只填写本差分的微表情（如：冷笑嘲讽）。底层人物外貌服饰与所选动作将在生图时自动组装！"
	txt_card_prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	txt_card_prompt.add_theme_font_size_override("font_size", 11)
	txt_card_prompt.text_changed.connect(func():
		item["prompt"] = txt_card_prompt.text.strip_edges()
		AIAssetMgr.save_manifest(manifest_items)
	)
	vbox.add_child(txt_card_prompt)

	var is_ready = (item.get("status", "pending") == "ready")
	var opt_status = OptionButton.new()
	opt_status.add_item("🟢 已生成", 0)
	opt_status.add_item("⏳ 待生成", 1)
	opt_status.selected = 0 if is_ready else 1
	opt_status.custom_minimum_size = Vector2(0, 26)
	opt_status.add_theme_font_size_override("font_size", 11)
	opt_status.tooltip_text = "手动修改此立绘状态（已生成 / 待生成）"
	opt_status.item_selected.connect(func(idx: int):
		var new_st = "ready" if idx == 0 else "pending"
		change_item_status(item, new_st)
	)
	vbox.add_child(opt_status)

	var act_row = HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 6)
	vbox.add_child(act_row)

	var btn_gen = Button.new()
	btn_gen.text = "🎨 生成"
	btn_gen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style_button(btn_gen, "action")
	btn_gen.pressed.connect(func():
		start_single_generation(item)
	)
	act_row.add_child(btn_gen)

	var btn_import = Button.new()
	btn_import.text = "📥"
	btn_import.tooltip_text = "从外部导入/替换图片文件 (PNG/JPG/WEBP)"
	btn_import.custom_minimum_size = Vector2(34, 30)
	style_button(btn_import, "secondary")
	btn_import.pressed.connect(func():
		import_external_asset_for_item(item)
	)
	act_row.add_child(btn_import)

	var btn_loc = Button.new()
	btn_loc.text = "📂"
	btn_loc.tooltip_text = "定位到本地文件夹"
	btn_loc.custom_minimum_size = Vector2(34, 30)
	style_button(btn_loc, "secondary")
	btn_loc.pressed.connect(func():
		open_file_in_explorer(item.get("local_path", ""))
	)
	act_row.add_child(btn_loc)

	return card

func create_voice_line_row(item: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.04, 0.05, 0.08, 0.9)
	p_style.set_border_width_all(1)
	p_style.border_color = Color(0.2, 0.25, 0.35, 0.4)
	p_style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", p_style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	margin.add_child(hbox)

	var is_ready = (item.get("status", "pending") == "ready")
	var opt_status = OptionButton.new()
	opt_status.add_item("🟢 已生成", 0)
	opt_status.add_item("⚪ 待生成", 1)
	opt_status.selected = 0 if is_ready else 1
	opt_status.custom_minimum_size = Vector2(105, 28)
	opt_status.tooltip_text = "手动修改配音状态（已生成 / 待生成）"
	opt_status.item_selected.connect(func(idx: int):
		var new_st = "ready" if idx == 0 else "pending"
		change_item_status(item, new_st)
	)
	hbox.add_child(opt_status)

	var has_file = false
	var local_path = item.get("local_path", "")
	if not local_path.is_empty():
		var abs_p = ProjectSettings.globalize_path(local_path)
		has_file = FileAccess.file_exists(abs_p) or FileAccess.file_exists(local_path)

	var btn_play = Button.new()
	btn_play.text = "▶ 试听"
	btn_play.custom_minimum_size = Vector2(75, 30)
	style_button(btn_play, "action")
	btn_play.disabled = not has_file
	btn_play.pressed.connect(func():
		play_audio_file(item.get("local_path", ""))
	)
	hbox.add_child(btn_play)

	var btn_gen = Button.new()
	btn_gen.text = "🎙️ 生成配音"
	btn_gen.custom_minimum_size = Vector2(95, 30)
	style_button(btn_gen, "create")
	btn_gen.pressed.connect(func():
		start_single_generation(item)
	)
	hbox.add_child(btn_gen)

	var btn_loc = Button.new()
	btn_loc.text = "📂"
	btn_loc.tooltip_text = "定位到本地文件夹"
	btn_loc.custom_minimum_size = Vector2(34, 30)
	style_button(btn_loc, "secondary")
	btn_loc.pressed.connect(func():
		open_file_in_explorer(item.get("local_path", ""))
	)
	hbox.add_child(btn_loc)

	var btn_import = Button.new()
	btn_import.text = "📥"
	btn_import.tooltip_text = "从外部导入音频文件 (MP3/WAV/OGG)"
	btn_import.custom_minimum_size = Vector2(34, 30)
	style_button(btn_import, "secondary")
	btn_import.pressed.connect(func():
		import_external_asset_for_item(item)
	)
	hbox.add_child(btn_import)

	var sep = VSeparator.new()
	hbox.add_child(sep)

	var text_lbl = Label.new()
	text_lbl.text = item.get("text", "")
	text_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_lbl.clip_text = true
	hbox.add_child(text_lbl)

	return panel

func create_audio_line_row(label_text: String, item: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.04, 0.05, 0.08, 0.9)
	p_style.set_border_width_all(1)
	p_style.border_color = Color(0.2, 0.25, 0.35, 0.4)
	p_style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", p_style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	margin.add_child(hbox)

	var is_ready = (item.get("status", "pending") == "ready")
	var opt_status = OptionButton.new()
	opt_status.add_item("🟢 已生成", 0)
	opt_status.add_item("⚪ 待生成", 1)
	opt_status.selected = 0 if is_ready else 1
	opt_status.custom_minimum_size = Vector2(105, 28)
	opt_status.tooltip_text = "手动修改音频状态（已生成 / 待生成）"
	opt_status.item_selected.connect(func(idx: int):
		var new_st = "ready" if idx == 0 else "pending"
		change_item_status(item, new_st)
	)
	hbox.add_child(opt_status)

	var has_file = false
	var local_path = item.get("local_path", "")
	if not local_path.is_empty():
		var abs_p = ProjectSettings.globalize_path(local_path)
		has_file = FileAccess.file_exists(abs_p) or FileAccess.file_exists(local_path)

	var btn_play = Button.new()
	btn_play.text = "▶ 试听"
	btn_play.custom_minimum_size = Vector2(75, 30)
	style_button(btn_play, "action")
	btn_play.disabled = not has_file
	btn_play.pressed.connect(func():
		play_audio_file(item.get("local_path", ""))
	)
	hbox.add_child(btn_play)

	var btn_loc = Button.new()
	btn_loc.text = "📂"
	btn_loc.tooltip_text = "定位到本地文件夹"
	btn_loc.custom_minimum_size = Vector2(34, 30)
	style_button(btn_loc, "secondary")
	btn_loc.pressed.connect(func():
		open_file_in_explorer(item.get("local_path", ""))
	)
	hbox.add_child(btn_loc)

	var btn_import = Button.new()
	btn_import.text = "📥"
	btn_import.tooltip_text = "从外部导入音频文件 (MP3/WAV/OGG)"
	btn_import.custom_minimum_size = Vector2(34, 30)
	style_button(btn_import, "secondary")
	btn_import.pressed.connect(func():
		import_external_asset_for_item(item)
	)
	hbox.add_child(btn_import)

	var sep = VSeparator.new()
	hbox.add_child(sep)

	var title_lbl = Label.new()
	title_lbl.text = label_text + ": " + item.get("local_path", "").get_file()
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.clip_text = true
	hbox.add_child(title_lbl)

	return panel

# --- 资源加载与音频播放 ---
func load_texture_to_rect(rect: TextureRect, local_path: String) -> void:
	if rect == null or local_path.is_empty():
		return
	var abs_path = ProjectSettings.globalize_path(local_path)
	if FileAccess.file_exists(abs_path):
		var img = Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			rect.texture = ImageTexture.create_from_image(img)
			return
		var fallback_img = Image.new()
		if fallback_img.load(abs_path) == OK:
			rect.texture = ImageTexture.create_from_image(fallback_img)
			return
	rect.texture = null

func play_audio_file(local_path: String) -> void:
	if local_path.is_empty():
		return
	var abs_path = ProjectSettings.globalize_path(local_path)
	if not FileAccess.file_exists(abs_path):
		lbl_gen_status.text = "⚠️ 提示: 该音频文件尚未生成，无法播放！"
		return

	if preview_audio_player.playing:
		preview_audio_player.stop()

	if local_path.ends_with(".mp3"):
		var mp3 = AudioStreamMP3.new()
		var f = FileAccess.open(abs_path, FileAccess.READ)
		if f:
			mp3.data = f.get_buffer(f.get_length())
			preview_audio_player.stream = mp3
			preview_audio_player.play()
			lbl_gen_status.text = "正在播放: " + local_path.get_file()
	elif local_path.ends_with(".wav"):
		var wav = AudioStreamWAV.new()
		var f = FileAccess.open(abs_path, FileAccess.READ)
		if f:
			wav.data = f.get_buffer(f.get_length())
			preview_audio_player.stream = wav
			preview_audio_player.play()
			lbl_gen_status.text = "正在播放: " + local_path.get_file()

# --- 手动修改资源状态 (已生成 <-> 待生成) ---
func change_item_status(item: Dictionary, new_status: String) -> void:
	item["status"] = new_status
	
	# 同步更新 manifest_items 中对应 id 的项
	var item_id = item.get("id", "")
	for it in manifest_items:
		if it is Dictionary and it.get("id", "") == item_id:
			it["status"] = new_status
			break
			
	# 立即存盘写入项目配置
	AIAssetMgr.save_manifest(manifest_items)
	
	var st_display = "🟢 已生成" if new_status == "ready" else "⏳ 待生成"
	lbl_gen_status.text = "✏️ 已将「%s」状态更改为: %s" % [item.get("name", item_id), st_display]
	
	# 刷新实体汇总数据、左侧导航列表与当前工作台
	refresh_entity_list()

# --- 一键在操作系统中打开并定位文件夹 ---
func open_file_in_explorer(file_or_dir_path: String) -> void:
	var path_str = file_or_dir_path.strip_edges()
	
	# 如果路径为空，智能推导当前分类的默认资源存放路径
	if path_str.is_empty():
		var pdir = ProjectContext.active_project_dir
		if pdir.is_empty():
			pdir = "res://projects/case_gallery_rain/"
		if not pdir.ends_with("/"):
			pdir += "/"
		match current_category:
			"character":
				path_str = pdir + "assets/images/characters/"
			"scene":
				path_str = pdir + "assets/images/backgrounds/"
			"clue":
				path_str = pdir + "assets/images/clues/"
			"shared":
				path_str = pdir + "assets/audio/bgm/"
			_:
				path_str = pdir + "assets/"

	# 规范化相对路径
	if not path_str.begins_with("res://") and not path_str.begins_with("user://") and not path_str.is_absolute_path():
		var pdir = ProjectContext.active_project_dir
		if pdir.is_empty():
			pdir = "res://projects/case_gallery_rain/"
		if not pdir.ends_with("/"):
			pdir += "/"
		if path_str.begins_with("projects/"):
			path_str = "res://" + path_str
		elif path_str.begins_with("assets/"):
			path_str = pdir + path_str
		else:
			path_str = pdir.path_join(path_str)

	var abs_path = ProjectSettings.globalize_path(path_str)
	
	# 1. 目标是一个已经存在的文件：使用 Godot 4 原生 Shell API 在操作系统文件管理器中高亮选中
	if FileAccess.file_exists(abs_path):
		var err = OS.shell_show_in_file_manager(abs_path, true)
		if err == OK:
			lbl_gen_status.text = "📂 已在资源管理器中定位并选中: " + abs_path.get_file()
			return
		else:
			# 原生选中失败时的备用降级：直接打开该文件所在文件夹
			var parent_dir = abs_path.get_base_dir()
			OS.shell_open(parent_dir)
			lbl_gen_status.text = "📂 已打开资源所在目录: " + parent_dir
			return

	# 2. 目标是一个目录路径（或尚未生成的文件，需要打开其目标所在目录）
	var target_dir = abs_path
	if not DirAccess.dir_exists_absolute(target_dir):
		target_dir = abs_path.get_base_dir()
	
	# 确保目标目录在磁盘上真实存在，若不存在则递归创建
	if not DirAccess.dir_exists_absolute(target_dir):
		DirAccess.make_dir_recursive_absolute(target_dir)
		
	if DirAccess.dir_exists_absolute(target_dir):
		OS.shell_open(target_dir)
		lbl_gen_status.text = "📂 已打开资源存放目录: " + target_dir
		return
		
	# 3. 兜底保护：打开当前活动工程的 assets 目录
	var cur_pdir = ProjectContext.active_project_dir
	if not cur_pdir.is_empty():
		var p_assets = ProjectSettings.globalize_path(cur_pdir.path_join("assets"))
		if not DirAccess.dir_exists_absolute(p_assets):
			DirAccess.make_dir_recursive_absolute(p_assets)
		OS.shell_open(p_assets)
		lbl_gen_status.text = "📂 已打开当前工程资产目录: " + p_assets

# --- 一键从外部导入/替换资源文件 (支持方案B与外部管线协同) ---
func import_external_asset_for_item(item: Dictionary) -> void:
	import_target_item = item
	var itype = item.get("type", "")
	if itype in ["voice", "bgm", "sfx", "audio"]:
		dlg_import_file.title = "选择要导入的音频文件 (MP3 / WAV / OGG)"
		dlg_import_file.filters = PackedStringArray(["*.mp3, *.wav, *.ogg ; 音频文件 (*.mp3, *.wav, *.ogg)"])
	else:
		dlg_import_file.title = "选择要导入的图像立绘/背景/特写 (PNG / JPG / WEBP)"
		dlg_import_file.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; 图像文件 (*.png, *.jpg, *.webp)"])
	
	# 如果已有路径，默认尝试定位到所在目录
	var cur_p = item.get("local_path", "")
	if not cur_p.is_empty():
		var abs_base = ProjectSettings.globalize_path(cur_p).get_base_dir()
		if DirAccess.dir_exists_absolute(abs_base):
			dlg_import_file.current_dir = abs_base
	dlg_import_file.popup_centered(Vector2i(850, 540))

func _on_external_file_selected(source_path: String) -> void:
	if import_target_item.is_empty():
		return
	
	var item = import_target_item
	var target_rel_path = item.get("local_path", "")
	
	# 如果原本没有指定目标路径，根据类型与工程目录推导标准路径
	if target_rel_path.is_empty():
		var pdir = ProjectContext.active_project_dir
		if pdir.is_empty():
			pdir = "res://projects/case_gallery_rain/"
		if not pdir.ends_with("/"):
			pdir += "/"
		var ext = source_path.get_extension().to_lower()
		var item_id = item.get("id", "asset_" + str(Time.get_unix_time_from_system()))
		match item.get("type", ""):
			"character":
				target_rel_path = pdir + "assets/images/characters/" + item_id + "." + ext
			"scene", "background":
				target_rel_path = pdir + "assets/images/backgrounds/" + item_id + "." + ext
			"clue":
				target_rel_path = pdir + "assets/images/characters/" + item_id + "." + ext
			"voice":
				target_rel_path = pdir + "assets/audio/voice/" + item_id + "." + ext
			"bgm":
				target_rel_path = pdir + "assets/audio/bgm/" + item_id + "." + ext
			_:
				target_rel_path = pdir + "assets/" + item_id + "." + ext
		item["local_path"] = target_rel_path

	var abs_dest = ProjectSettings.globalize_path(target_rel_path)
	var dest_dir = abs_dest.get_base_dir()
	if not DirAccess.dir_exists_absolute(dest_dir):
		DirAccess.make_dir_recursive_absolute(dest_dir)

	var err = DirAccess.copy_absolute(source_path, abs_dest)
	if err != OK:
		lbl_gen_status.text = "❌ 复制文件失败，错误码: %d" % err
		return

	# 标记为已生成，并持久化写入工程配置
	item["status"] = "ready"
	var item_id = item.get("id", "")
	for it in manifest_items:
		if it is Dictionary and it.get("id", "") == item_id:
			it["status"] = "ready"
			it["local_path"] = target_rel_path
			break

	AIAssetMgr.save_manifest(manifest_items)
	ProjectContext.rebuild_asset_index()
	lbl_gen_status.text = "✅ 成功导入并绑定外部资产: " + source_path.get_file()
	refresh_entity_list()

func _on_open_current_entity_folder() -> void:
	var pdir = ProjectContext.active_project_dir
	if pdir.is_empty():
		pdir = "res://projects/case_gallery_rain/"
	if not pdir.ends_with("/"):
		pdir += "/"
	
	match current_category:
		"character":
			open_file_in_explorer(pdir + "assets/images/characters/")
		"scene":
			open_file_in_explorer(pdir + "assets/images/backgrounds/")
		"clue":
			open_file_in_explorer(pdir + "assets/images/clues/")
		"shared":
			open_file_in_explorer(pdir + "assets/audio/bgm/")

# --- 生成进度与非阻塞异步执行 ---
func _on_progress_timer_tick() -> void:
	if not is_generating:
		return
	var abs_prog = ProjectSettings.globalize_path(PROGRESS_FILE_PATH)
	var now_ms = Time.get_ticks_msec()
	if gen_start_time_ms <= 0 or gen_start_time_ms > now_ms:
		gen_start_time_ms = now_ms
	var elapsed = maxf(0.0, float(now_ms - gen_start_time_ms) / 1000.0)

	if FileAccess.file_exists(abs_prog):
		var f = FileAccess.open(abs_prog, FileAccess.READ)
		if f:
			var txt = f.get_as_text()
			f.close()
			var json = JSON.new()
			if json.parse(txt) == OK and json.data is Dictionary:
				var d = json.data
				var pct = d.get("percent", 0)
				var msg = d.get("text", "生成中...")
				if is_batch_running and batch_total_count > 0:
					progress_bar.max_value = batch_total_count * 100
					progress_bar.value = clampf((batch_current_index - 1) * 100 + pct, 0, batch_total_count * 100)
					lbl_gen_status.text = "⚡ %s [%d/%d] %s (%d%%, 已耗时 %.1fs)" % [
						batch_current_label, batch_current_index, batch_total_count, msg, pct, elapsed
					]
				else:
					progress_bar.max_value = 100
					progress_bar.value = pct
					lbl_gen_status.text = "⏳ %s (%d%%, 已耗时 %.1fs)" % [msg, pct, elapsed]
				return

	# 若进度文件尚未写入或正在等待 ComfyUI 排队，保持计时器活跃
	if is_batch_running and batch_total_count > 0:
		lbl_gen_status.text = "⚡ %s [%d/%d] 排队准备中... (已耗时 %.1fs)" % [
			batch_current_label, batch_current_index, batch_total_count, elapsed
		]
	else:
		lbl_gen_status.text = "⏳ 排队准备中... (已耗时 %.1fs)" % elapsed

func start_single_generation(item: Dictionary) -> void:
	if is_generating:
		lbl_gen_status.text = "⚠️ 当前已有生成任务正在进行中，请稍候！"
		return

	save_current_settings()
	is_generating = true
	is_batch_running = false
	batch_total_count = 0
	batch_current_index = 0
	var now_ms = Time.get_ticks_msec()
	gen_start_time_ms = now_ms
	gen_start_time = Time.get_unix_time_from_system()
	progress_bar.visible = true
	progress_bar.max_value = 100
	progress_bar.value = 5
	lbl_gen_status.text = "⏳ 准备生成: %s (已耗时 0.0s)..." % item.get("name", "")
	progress_poll_timer.start()

	# 初始化清理进度文件
	var abs_prog = ProjectSettings.globalize_path(PROGRESS_FILE_PATH)
	if FileAccess.file_exists(abs_prog):
		DirAccess.remove_absolute(abs_prog)

	if gen_thread and gen_thread.is_started():
		gen_thread.wait_to_finish()

	gen_thread = Thread.new()
	gen_thread.start(func():
		var res = AIAssetMgr.generate_asset_item(item, ai_settings, PROGRESS_FILE_PATH)
		call_deferred("_on_single_gen_finished", item, res)
	)

func _on_single_gen_finished(item: Dictionary, res: Dictionary) -> void:
	is_generating = false
	is_batch_running = false
	progress_poll_timer.stop()
	progress_bar.visible = false
	if gen_thread and gen_thread.is_started():
		gen_thread.wait_to_finish()

	var now_ms = Time.get_ticks_msec()
	var elapsed = maxf(0.0, float(now_ms - gen_start_time_ms) / 1000.0) if gen_start_time_ms > 0 else 0.0
	gen_start_time_ms = 0
	gen_start_time = 0.0
	if res.get("success", false):
		item["status"] = "ready"
		AIAssetMgr.save_manifest(manifest_items)
		lbl_gen_status.text = "✅ 生成成功: %s (耗时 %.1fs)" % [item.get("name", ""), elapsed]
		refresh_entity_list()
		select_entity(selected_entity_id)
	else:
		lbl_gen_status.text = "❌ 生成失败 (耗时 %.1fs): %s" % [elapsed, res.get("error", "未知错误")]

func _on_batch_current_entity_pending() -> void:
	var pending_items: Array = []
	match current_category:
		"character":
			var ent = entities_summary.get("characters", {}).get(selected_entity_id, {})
			for it in ent.get("sprites", []):
				if it.get("status") != "ready": pending_items.append(it)
			for it in ent.get("voices", []):
				if it.get("status") != "ready": pending_items.append(it)
		"scene":
			var ent = entities_summary.get("scenes", {}).get(selected_entity_id, {})
			var bg = ent.get("background")
			if bg != null and bg.get("status") != "ready": pending_items.append(bg)
			var bgm = ent.get("bgm")
			if bgm != null and bgm.get("status") != "ready": pending_items.append(bgm)
			for it in ent.get("items", []):
				if it.get("status") != "ready" and not pending_items.has(it): pending_items.append(it)
		"clue":
			var ent = entities_summary.get("clues", {}).get(selected_entity_id, {})
			var img = ent.get("image")
			if img != null and img.get("status") != "ready": pending_items.append(img)
			var sfx = ent.get("sfx")
			if sfx != null and sfx.get("status") != "ready": pending_items.append(sfx)
			for it in ent.get("items", []):
				if it.get("status") != "ready" and not pending_items.has(it): pending_items.append(it)
		"shared":
			var ent = entities_summary.get("shared", {})
			for it in ent.get("items", []):
				if it.get("status") != "ready": pending_items.append(it)

	if pending_items.is_empty():
		lbl_gen_status.text = "当前实体名下所有素材均已生成，无需重新生成！"
		return

	execute_batch_generation(pending_items, "本实体")

func _on_batch_character_sprites_pending(cid: String, ent: Dictionary) -> void:
	var pending: Array = []
	for sp in ent.get("sprites", []):
		if sp.get("status", "pending") != "ready":
			pending.append(sp)
	if pending.is_empty():
		lbl_gen_status.text = "本角色所有立绘均已生成，无需批量生成！"
		return
	execute_batch_generation(pending, ent.get("name", cid) + " 全部立绘")

func _on_batch_character_voices_pending(cid: String, ent: Dictionary) -> void:
	var pending: Array = []
	for vc in ent.get("voices", []):
		if vc.get("status", "pending") != "ready":
			pending.append(vc)
	if pending.is_empty():
		lbl_gen_status.text = "本角色所有配音均已生成，无需批量生成！"
		return
	execute_batch_generation(pending, ent.get("name", cid) + " 全部配音")

func _on_batch_scene_pending(sc_id: String, ent: Dictionary) -> void:
	var pending: Array = []
	var bg = ent.get("background")
	if bg != null and bg.get("status", "pending") != "ready":
		pending.append(bg)
	var bgm = ent.get("bgm")
	if bgm != null and bgm.get("status", "pending") != "ready":
		pending.append(bgm)
	for it in ent.get("items", []):
		if it.get("status", "pending") != "ready" and not pending.has(it):
			pending.append(it)
	if pending.is_empty():
		lbl_gen_status.text = "本场景所有视听素材均已生成！"
		return
	execute_batch_generation(pending, ent.get("name", sc_id) + " 场景素材")

func _on_batch_clue_pending(clue_id: String, ent: Dictionary) -> void:
	var pending: Array = []
	var img = ent.get("image")
	if img != null and img.get("status", "pending") != "ready":
		pending.append(img)
	var sfx = ent.get("sfx")
	if sfx != null and sfx.get("status", "pending") != "ready":
		pending.append(sfx)
	for it in ent.get("items", []):
		if it.get("status", "pending") != "ready" and not pending.has(it):
			pending.append(it)
	if pending.is_empty():
		lbl_gen_status.text = "本证物所有视听素材均已生成！"
		return
	execute_batch_generation(pending, ent.get("name", clue_id) + " 证物素材")

func batch_generate_all_pending() -> void:
	var pending_items = []
	for it in manifest_items:
		if it.get("status", "pending") == "pending":
			pending_items.append(it)

	if pending_items.is_empty():
		lbl_gen_status.text = "所有素材已全部生成完毕，无需批量生成！"
		return

	execute_batch_generation(pending_items, "全案")

func execute_batch_generation(items_to_gen: Array, batch_label: String) -> void:
	if is_generating:
		lbl_gen_status.text = "⚠️ 当前已有生成任务正在进行中！"
		return

	save_current_settings()
	is_generating = true
	is_batch_running = true
	batch_current_label = batch_label
	batch_total_count = items_to_gen.size()
	batch_current_index = 0
	var now_ms = Time.get_ticks_msec()
	batch_start_time_ms = now_ms
	gen_start_time_ms = now_ms
	gen_start_time = Time.get_unix_time_from_system()

	progress_bar.visible = true
	progress_bar.max_value = items_to_gen.size() * 100
	progress_bar.value = 0
	lbl_gen_status.text = "⚡ %s批量生成准备中 (共 %d 项)..." % [batch_label, items_to_gen.size()]
	progress_poll_timer.start()

	# 初始化清理进度文件
	var abs_prog = ProjectSettings.globalize_path(PROGRESS_FILE_PATH)
	if FileAccess.file_exists(abs_prog):
		DirAccess.remove_absolute(abs_prog)

	if gen_thread and gen_thread.is_started():
		gen_thread.wait_to_finish()

	gen_thread = Thread.new()
	gen_thread.start(func():
		var total = items_to_gen.size()
		var count = 0
		for it in items_to_gen:
			count += 1
			call_deferred("_update_batch_step", batch_label, count, total, it.get("name", ""))
			var res = AIAssetMgr.generate_asset_item(it, ai_settings, PROGRESS_FILE_PATH)
			if res.get("success", false):
				it["status"] = "ready"
		call_deferred("_on_batch_all_finished", total)
	)

func _update_batch_step(batch_label: String, cur: int, total: int, item_name: String) -> void:
	batch_current_label = batch_label
	batch_current_index = cur
	batch_total_count = total
	var now_ms = Time.get_ticks_msec()
	gen_start_time_ms = now_ms
	gen_start_time = Time.get_unix_time_from_system()
	progress_bar.max_value = total * 100
	progress_bar.value = (cur - 1) * 100
	lbl_gen_status.text = "⚡ %s批量生成中 [%d/%d]: %s (已耗时 0.0s)" % [batch_label, cur, total, item_name]

func _on_batch_all_finished(total: int) -> void:
	is_generating = false
	is_batch_running = false
	progress_poll_timer.stop()
	progress_bar.visible = false
	if gen_thread and gen_thread.is_started():
		gen_thread.wait_to_finish()

	var now_ms = Time.get_ticks_msec()
	var total_elapsed = maxf(0.0, float(now_ms - batch_start_time_ms) / 1000.0) if batch_start_time_ms > 0 else 0.0
	gen_start_time_ms = 0
	batch_start_time_ms = 0
	gen_start_time = 0.0
	batch_total_count = 0
	batch_current_index = 0

	AIAssetMgr.save_manifest(manifest_items)
	lbl_gen_status.text = "✅ 批量生成完成！共处理 %d 项素材 (总耗时 %.1fs)。" % [total, total_elapsed]
	refresh_entity_list()
	select_entity(selected_entity_id)

# --- 兼容性方法 (供自动化测试与老逻辑访问) ---
func select_item(item_id: String) -> void:
	selected_item_id = item_id
	var item = get_item_by_id(item_id)
	if not item.is_empty():
		var style = txt_global_style.text.strip_edges()
		var p = item.get("prompt", "")
		lbl_combined_prompt.text = "合成发送提示词: " + style + ", " + p
		# 自动联动切换分类并选中对应实体
		var etype = item.get("entity_type", "character")
		var eid = item.get("entity_id", "")
		if etype != current_category:
			switch_category(etype)
		if not eid.is_empty():
			select_entity(eid)

func get_item_by_id(item_id: String) -> Dictionary:
	for it in manifest_items:
		if it.get("id", "") == item_id:
			return it
	return {}

func save_current_settings() -> void:
	var cur_host = txt_comfy_host.text.strip_edges()
	var cur_user = txt_comfy_user.text.strip_edges()
	var cur_pass = txt_comfy_pass.text.strip_edges()

	ai_settings["comfyui_server"] = cur_host
	ai_settings["comfyui_user"] = cur_user
	ai_settings["comfyui_password"] = cur_pass
	ai_settings["checkpoint"] = txt_checkpoint.text.strip_edges()
	ai_settings["global_style_prompt"] = txt_global_style.text.strip_edges()
	ai_settings["global_negative_prompt"] = txt_global_neg.text.strip_edges()

	# 同步写回当前选中的环境配置
	var cur_env_id = str(ai_settings.get("current_env_id", ""))
	var envs = ai_settings.get("comfyui_environments", [])
	var env_found = false
	var saved_env_name = ""
	for e in envs:
		if e is Dictionary and str(e.get("id", "")) == cur_env_id:
			e["server"] = cur_host
			e["user"] = cur_user
			e["password"] = cur_pass
			saved_env_name = str(e.get("name", ""))
			env_found = true
			break
	if not env_found and envs.size() > 0:
		envs[0]["server"] = cur_host
		envs[0]["user"] = cur_user
		envs[0]["password"] = cur_pass
		saved_env_name = str(envs[0].get("name", ""))

	ai_settings["comfyui_environments"] = envs
	AIAssetMgr.save_ai_settings(ai_settings)
	_refresh_env_dropdown()
	lbl_gen_status.text = "✅ AI 设置与环境 [%s] 已保存！" % saved_env_name

func test_comfy_connection() -> void:
	var host = txt_comfy_host.text.strip_edges()
	var user = txt_comfy_user.text.strip_edges()
	var password = txt_comfy_pass.text.strip_edges()
	lbl_conn_status.text = "⏳ 检测中..."
	lbl_conn_status.modulate = Color(0.9, 0.8, 0.4)

	var res = AIAssetMgr.check_comfy_service(host, user, password)
	if res.get("online", false):
		var gpu = res.get("gpu", "GPU")
		var vram_free_mb = int(res.get("vram_free", 0) / 1024 / 1024)
		var short_gpu = "在线"
		if "RTX" in gpu:
			short_gpu = "RTX " + gpu.split("RTX")[1].split(":")[0].strip_edges()
		elif "NVIDIA" in gpu:
			short_gpu = gpu.split("NVIDIA")[1].split(":")[0].strip_edges()
		lbl_conn_status.text = "🟢 已连接 (%s, %dG)" % [short_gpu, int(vram_free_mb / 1024)]
		lbl_conn_status.tooltip_text = "显卡完整信息: %s\n空闲显存: %d MB" % [gpu, vram_free_mb]
		lbl_conn_status.modulate = Color(0.3, 0.9, 0.4)
		
		var ckpts = res.get("checkpoints", [])
		if ckpts.size() > 0:
			opt_checkpoint.clear()
			for i in range(ckpts.size()):
				var ck = ckpts[i]
				opt_checkpoint.add_item(ck, i)
				opt_checkpoint.set_item_metadata(i, ck)
				if ck == txt_checkpoint.text:
					opt_checkpoint.selected = i
			if opt_checkpoint.selected == -1:
				opt_checkpoint.selected = 0
				txt_checkpoint.text = ckpts[0]
				ai_settings["checkpoint"] = ckpts[0]
	else:
		lbl_conn_status.text = "🔴 未连接 (%s)" % res.get("error", "超时")
		lbl_conn_status.modulate = Color(1.0, 0.4, 0.4)

# --- 主动自主创作接口 (Proactive Creation) ---
func proactive_generate_character_sprite(cid: String, ent: Dictionary) -> void:
	var pdir = ProjectContext.active_project_dir
	if pdir.is_empty():
		pdir = "res://projects/case_gallery_rain/"
	if not pdir.ends_with("/"):
		pdir += "/"
	
	var cname = ent.get("name", cid)
	var base_p = ent.get("base_prompt", "")
	if base_p.is_empty():
		base_p = "%s，半身立绘，正面站姿，纯白背景" % cname
		ent["base_prompt"] = base_p
	
	var sprite_idx = ent.get("sprites", []).size() + 1
	var item_id = "char_" + cid + "_sprite_" + str(sprite_idx)
	var rel_path = pdir + "assets/images/characters/" + item_id + ".png"
	
	var new_item = {
		"id": item_id,
		"type": "character",
		"entity_type": "character",
		"entity_id": cid,
		"entity_name": cname,
		"character_id": cid,
		"sub_type": "sprite",
		"name": cname + " 立绘 " + str(sprite_idx),
		"prompt": base_p,
		"negative_prompt": "复杂背景，室内室外环境，多余手指，肢体畸变，低质量，模糊",
		"local_path": rel_path,
		"width": 512,
		"height": 768,
		"status": "pending"
	}
	
	manifest_items.append(new_item)
	ent["sprites"].append(new_item)
	AIAssetMgr.save_manifest(manifest_items)
	
	render_character_workbench(cid, ent)
	start_single_generation(new_item)

func test_character_voice(ent: Dictionary) -> void:
	var cname = ent.get("name", "角色")
	var role = ent.get("voice_role", "zh-CN-YunxiNeural")
	var test_text = "你好，我是%s。这是我的配音声线试听。" % cname
	var temp_path = "user://temp_voice_preview.mp3"
	var abs_path = ProjectSettings.globalize_path(temp_path)
	
	lbl_gen_status.text = "🎙️ 正在实时合成 [%s] 试听语音..." % role
	
	var script_path = ProjectSettings.globalize_path("res://tools/ai_bridge.py")
	var args = [
		script_path,
		"generate_voice",
		"--text", test_text,
		"--voice", role,
		"--save", abs_path
	]
	
	var output = []
	var exit_code = OS.execute("python", args, output, true)
	if exit_code == 0 and FileAccess.file_exists(abs_path):
		play_audio_file(temp_path)
		lbl_gen_status.text = "✅ [%s] 声线试听合成完成并开始播放！" % cname
	else:
		lbl_gen_status.text = "❌ 试听语音合成失败，请检查 Python / Edge-TTS 环境。"

func proactive_generate_scene_background(sc_id: String, ent: Dictionary) -> void:
	var pdir = ProjectContext.active_project_dir
	if pdir.is_empty():
		pdir = "res://projects/case_gallery_rain/"
	if not pdir.ends_with("/"):
		pdir += "/"
	
	var sc_name = ent.get("name", sc_id)
	var item_id = "bg_" + sc_id
	var rel_path = pdir + "assets/images/backgrounds/" + item_id + ".png"
	var prompt = sc_name + ", watercolor anime style, highly detailed interior scenery, dramatic lighting, no humans"
	
	var new_item = {
		"id": item_id,
		"type": "background",
		"entity_type": "scene",
		"entity_id": sc_id,
		"entity_name": sc_name,
		"sub_type": "background",
		"name": sc_name + " 背景大图",
		"prompt": prompt,
		"negative_prompt": "(humans, people, character:1.4), text, watermark, blurry",
		"local_path": rel_path,
		"width": 1024,
		"height": 576,
		"status": "pending"
	}
	
	manifest_items.append(new_item)
	ent["background"] = new_item
	AIAssetMgr.save_manifest(manifest_items)
	
	render_scene_workbench(sc_id, ent)
	start_single_generation(new_item)

func proactive_generate_clue_image(clue_id: String, ent: Dictionary) -> void:
	var pdir = ProjectContext.active_project_dir
	if pdir.is_empty():
		pdir = "res://projects/case_gallery_rain/"
	if not pdir.ends_with("/"):
		pdir += "/"
	
	var cname = ent.get("name", clue_id)
	var item_id = "clue_" + clue_id
	var rel_path = pdir + "assets/images/clues/" + item_id + ".png"
	var prompt = cname + ", macro close-up shot, dramatic lighting, isolated, single object"
	
	var new_item = {
		"id": item_id,
		"type": "clue",
		"entity_type": "clue",
		"entity_id": clue_id,
		"entity_name": cname,
		"sub_type": "image",
		"name": cname + " 特写",
		"prompt": prompt,
		"negative_prompt": "humans, hands, cluttered, text",
		"local_path": rel_path,
		"width": 512,
		"height": 512,
		"status": "pending"
	}
	
	manifest_items.append(new_item)
	ent["image"] = new_item
	AIAssetMgr.save_manifest(manifest_items)
	
	render_clue_workbench(clue_id, ent)
	start_single_generation(new_item)

func open_add_sprite_dialog(cid: String, ent: Dictionary) -> void:
	char_workbench_subtab = "sprites"
	pending_sprite_cid = cid
	pending_sprite_ent = ent
	txt_sprite_suffix.text = "质询冷笑"
	var cname = ent.get("name", cid)
	if txt_sprite_prompt:
		txt_sprite_prompt.text = "眼神凌厉冰冷，嘴角微嘲冷笑"
	if opt_add_sprite_mode:
		opt_add_sprite_mode.selected = 0
	if lbl_add_sprite_pose_title:
		lbl_add_sprite_pose_title.visible = false
	if opt_add_sprite_pose:
		opt_add_sprite_pose.visible = false
		opt_add_sprite_pose.selected = 0
	dlg_add_sprite.popup_centered()

func _on_confirm_add_sprite() -> void:
	if pending_sprite_cid.is_empty() or pending_sprite_ent.is_empty():
		return
	var suffix = txt_sprite_suffix.text.strip_edges()
	if suffix.is_empty():
		suffix = "表情差分"
	
	var pdir = ProjectContext.active_project_dir
	if pdir.is_empty():
		pdir = "res://projects/case_gallery_rain/"
	if not pdir.ends_with("/"):
		pdir += "/"
	
	var cname = pending_sprite_ent.get("name", pending_sprite_cid)
	var base_p = pending_sprite_ent.get("base_prompt", "")
	if base_p.is_empty():
		base_p = "%s，半身立绘，正面站姿，纯白背景" % cname
		pending_sprite_ent["base_prompt"] = base_p
	
	var sprite_idx = pending_sprite_ent.get("sprites", []).size() + 1
	var item_id = "char_" + pending_sprite_cid + "_sprite_" + str(sprite_idx)
	var rel_path = pdir + "assets/images/characters/" + item_id + ".png"
	var combined_prompt = ""
	if txt_sprite_prompt and not txt_sprite_prompt.text.strip_edges().is_empty():
		combined_prompt = txt_sprite_prompt.text.strip_edges()
	else:
		combined_prompt = "神色" + suffix + "，目光凝注"
	
	var is_pose_mode = (opt_add_sprite_mode and opt_add_sprite_mode.selected == 1)
	var gen_mode = "pose" if is_pose_mode else "expression"

	var chosen_pose = "standing_calm"
	if is_pose_mode and opt_add_sprite_pose:
		var sel = opt_add_sprite_pose.selected
		chosen_pose = opt_add_sprite_pose.get_item_metadata(sel)

	var base_seed = 0
	var existing_sprites = pending_sprite_ent.get("sprites", [])
	if not existing_sprites.is_empty() and existing_sprites[0].get("seed", 0) > 0:
		base_seed = existing_sprites[0].get("seed")
	
	var base_path = ""
	for sp in existing_sprites:
		if sp.get("is_base", false):
			base_path = sp.get("local_path", "")
			break
	if base_path.is_empty() and existing_sprites.size() > 0:
		base_path = existing_sprites[0].get("local_path", "")

	var is_male = cname.contains("沈策") or cname.contains("温寻") or pending_sprite_cid.contains("shen_ce") or pending_sprite_cid.contains("wen_xun")
	var gender_neg = "女性，少女，女，(female:1.6), (1girl:1.6), (woman:1.6), " if is_male else ""
	var neg_prompt = gender_neg + "日文，对话框，台词框，字幕，气泡，漫画框，复杂背景，室内室外环境，多余手指，肢体畸变，低质量，模糊，text, watermark, speech bubble, dialogue box"

	var item_title = "%s %s: %s" % [cname, "3D姿态" if is_pose_mode else "微表情", suffix]
	var new_item = {
		"id": item_id,
		"type": "character",
		"entity_type": "character",
		"entity_id": pending_sprite_cid,
		"entity_name": cname,
		"character_id": pending_sprite_cid,
		"sub_type": "sprite",
		"name": item_title,
		"prompt": combined_prompt,
		"negative_prompt": neg_prompt,
		"pose_preset": chosen_pose,
		"generation_mode": gen_mode,
		"local_path": rel_path,
		"width": 512,
		"height": 768,
		"seed": base_seed,
		"base_sprite_path": base_path,
		"is_base": false,
		"status": "pending"
	}
	
	manifest_items.append(new_item)
	pending_sprite_ent["sprites"].append(new_item)
	AIAssetMgr.save_manifest(manifest_items)
	dlg_add_sprite.hide()
	
	char_workbench_subtab = "sprites"
	refresh_entity_list()
	select_entity(pending_sprite_cid)
	lbl_gen_status.text = "✅ 已新增立绘差分项 [%s]，可单独点击【🎨 生成】或右上角【⚡ 批量生成】！" % new_item.get("name", "")

# --- 角色基准立绘切换 ---
func set_character_base_sprite(cid: String, base_item: Dictionary) -> void:
	var base_id = base_item.get("id", "")
	for it in manifest_items:
		if it is Dictionary and (it.get("character_id", "") == cid or it.get("entity_id", "") == cid):
			if it.get("sub_type", "") == "sprite" or it.get("type", "") == "character":
				it["is_base"] = (it.get("id", "") == base_id)
				if it.get("id", "") == base_id:
					it["base_sprite_path"] = ""
				else:
					it["base_sprite_path"] = base_item.get("local_path", "")
	AIAssetMgr.save_manifest(manifest_items)
	refresh_entity_list()
	select_entity(cid)
	lbl_gen_status.text = "🌟 已将「%s」设为角色 [%s] 的形象基准锚点！" % [base_item.get("name", base_id), cid]

# --- 3D 姿态工坊交互 ---
func open_pose_editor_dialog(cid: String, ent: Dictionary) -> void:
	if dlg_pose_editor:
		dlg_pose_editor.open_for_character(cid, ent)

func _on_pose_sprite_generated(new_item: Dictionary) -> void:
	manifest_items.append(new_item)
	var cid = new_item.get("character_id", "")
	var ent = entities_summary.get("characters", {}).get(cid, {})
	if not ent.is_empty():
		ent["sprites"].append(new_item)
	AIAssetMgr.save_manifest(manifest_items)
	refresh_entity_list()
	select_entity(cid)
	lbl_gen_status.text = "✅ 已由 3D 姿态工坊创建新立绘项 [%s]，正在启动生成..." % new_item.get("name", "")
	start_single_generation(new_item)

func open_add_voice_dialog(cid: String, ent: Dictionary) -> void:
	char_workbench_subtab = "voices"
	pending_voice_cid = cid
	pending_voice_ent = ent
	txt_voice_input.text = ""
	dlg_add_voice.popup_centered()

func _on_confirm_add_voice() -> void:
	if pending_voice_cid.is_empty() or pending_voice_ent.is_empty():
		return
	var text_content = txt_voice_input.text.strip_edges()
	if text_content.is_empty():
		lbl_gen_status.text = "⚠️ 台词文本不能为空！"
		return
	
	var pdir = ProjectContext.active_project_dir
	if pdir.is_empty():
		pdir = "res://projects/case_gallery_rain/"
	if not pdir.ends_with("/"):
		pdir += "/"
	
	var cname = pending_voice_ent.get("name", pending_voice_cid)
	var voice_role = pending_voice_ent.get("voice_role", "zh-CN-YunxiNeural")
	var voice_idx = pending_voice_ent.get("voices", []).size() + 1
	var item_id = "voice_" + pending_voice_cid + "_" + str(voice_idx)
	var rel_path = pdir + "assets/audio/voice/" + item_id + ".mp3"
	
	var new_item = {
		"id": item_id,
		"type": "voice",
		"entity_type": "character",
		"entity_id": pending_voice_cid,
		"entity_name": cname,
		"character_id": pending_voice_cid,
		"sub_type": "voice",
		"name": "%s 配音: %s" % [cname, text_content.substr(0, 15)],
		"text": text_content,
		"voice_role": voice_role,
		"local_path": rel_path,
		"status": "pending"
	}
	
	manifest_items.append(new_item)
	pending_voice_ent["voices"].append(new_item)
	AIAssetMgr.save_manifest(manifest_items)
	dlg_add_voice.hide()
	
	char_workbench_subtab = "voices"
	refresh_entity_list()
	select_entity(pending_voice_cid)
	lbl_gen_status.text = "✅ 已录入台词对白 [%s]，可单独点击【🎙️ 生成】或右上角【⚡ 批量生成】！" % new_item.get("name", "")

# --- ComfyUI 多环境配置管理与切换逻辑 ---
func _refresh_env_dropdown() -> void:
	opt_server_preset.clear()
	var envs = ai_settings.get("comfyui_environments", [])
	var cur_id = str(ai_settings.get("current_env_id", ""))
	var selected_idx = 0
	
	for i in range(envs.size()):
		var env = envs[i]
		var env_name = str(env.get("name", "环境 " + str(i + 1)))
		var host = str(env.get("server", ""))
		var user = str(env.get("user", ""))
		
		var icon_prefix = "💻 " if (host.contains("127.0.0.1") or host.contains("localhost")) else "🚀 "
		var auth_tag = " [🔑鉴权]" if not user.is_empty() else ""
		var display_text = "%s%s%s" % [icon_prefix, env_name, auth_tag]
		
		opt_server_preset.add_item(display_text, i)
		opt_server_preset.set_item_metadata(i, env.get("id", ""))
		
		if str(env.get("id", "")) == cur_id:
			selected_idx = i
			
	var add_idx = envs.size()
	opt_server_preset.add_item("➕ 新增环境配置...", add_idx)
	opt_server_preset.set_item_metadata(add_idx, "__add_new__")
	
	if selected_idx < envs.size():
		opt_server_preset.selected = selected_idx

func _on_server_preset_selected(idx: int) -> void:
	var meta = opt_server_preset.get_item_metadata(idx)
	if str(meta) == "__add_new__":
		_restore_env_dropdown_selection()
		open_add_env_dialog()
		return

	var envs = ai_settings.get("comfyui_environments", [])
	if idx >= 0 and idx < envs.size():
		var env = envs[idx]
		var env_id = str(env.get("id", ""))
		ai_settings["current_env_id"] = env_id
		
		# 将选中环境的地址、账号、密码载入输入框中，绝不丢失历史
		txt_comfy_host.text = env.get("server", "http://127.0.0.1:8188")
		txt_comfy_user.text = env.get("user", "")
		txt_comfy_pass.text = env.get("password", "")
		
		ai_settings["comfyui_server"] = txt_comfy_host.text
		ai_settings["comfyui_user"] = txt_comfy_user.text
		ai_settings["comfyui_password"] = txt_comfy_pass.text
		AIAssetMgr.save_ai_settings(ai_settings)
		
		lbl_gen_status.text = "已切换至环境: " + str(env.get("name", ""))
		test_comfy_connection()

func _restore_env_dropdown_selection() -> void:
	var cur_id = str(ai_settings.get("current_env_id", ""))
	for i in range(opt_server_preset.item_count):
		if str(opt_server_preset.get_item_metadata(i)) == cur_id:
			opt_server_preset.selected = i
			break

func open_add_env_dialog() -> void:
	txt_add_env_name.text = ""
	txt_add_env_host.text = ""
	txt_add_env_user.text = ""
	txt_add_env_pass.text = ""
	dlg_add_env.popup_centered()

func _on_confirm_add_env() -> void:
	var h = txt_add_env_host.text.strip_edges()
	if h.is_empty():
		h = "http://127.0.0.1:8188"
	var u = txt_add_env_user.text.strip_edges()
	var p = txt_add_env_pass.text.strip_edges()
	var n = txt_add_env_name.text.strip_edges()
	if n.is_empty():
		if h.contains("127.0.0.1") or h.contains("localhost"):
			n = "本地默认 (" + h + ")"
		else:
			n = "远程环境 (" + h.replace("https://", "").replace("http://", "").split("/")[0] + ")"
	
	var new_env = {
		"id": "env_" + str(Time.get_unix_time_from_system()) + "_" + str(randi() % 1000),
		"name": n,
		"server": h,
		"user": u,
		"password": p
	}
	
	var envs = ai_settings.get("comfyui_environments", [])
	envs.append(new_env)
	ai_settings["comfyui_environments"] = envs
	ai_settings["current_env_id"] = new_env["id"]
	
	txt_comfy_host.text = h
	txt_comfy_user.text = u
	txt_comfy_pass.text = p
	ai_settings["comfyui_server"] = h
	ai_settings["comfyui_user"] = u
	ai_settings["comfyui_password"] = p
	
	AIAssetMgr.save_ai_settings(ai_settings)
	_refresh_env_dropdown()
	dlg_add_env.hide()
	lbl_gen_status.text = "✅ 成功添加新环境并已切换: " + n
	test_comfy_connection()

func open_manage_env_dialog() -> void:
	_render_env_manager_list()
	dlg_manage_env.popup_centered()

func _render_env_manager_list() -> void:
	for c in vbox_env_list.get_children():
		c.queue_free()
		
	var envs = ai_settings.get("comfyui_environments", [])
	var cur_id = str(ai_settings.get("current_env_id", ""))
	
	for i in range(envs.size()):
		var env = envs[i]
		var eid = str(env.get("id", ""))
		var is_cur = (eid == cur_id)
		
		var panel = PanelContainer.new()
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.14, 0.20, 0.28, 0.95) if is_cur else Color(0.08, 0.11, 0.15, 0.85)
		sb.set_border_width_all(2 if is_cur else 1)
		sb.border_color = Color(0.4, 0.8, 1.0) if is_cur else Color(0.2, 0.28, 0.38, 0.6)
		sb.set_corner_radius_all(6)
		panel.add_theme_stylebox_override("panel", sb)
		
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_top", 8)
		margin.add_theme_constant_override("margin_bottom", 8)
		panel.add_child(margin)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		margin.add_child(hbox)
		
		var vbox_info = VBoxContainer.new()
		vbox_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox_info.add_theme_constant_override("separation", 4)
		
		var lbl_title = Label.new()
		var tag = " [🟢 当前正在使用]" if is_cur else ""
		lbl_title.text = str(env.get("name", "未命名环境")) + tag
		lbl_title.modulate = Color(1.0, 0.9, 0.4) if is_cur else Color(1, 1, 1)
		vbox_info.add_child(lbl_title)
		
		var lbl_detail = Label.new()
		var u_text = "账号: " + str(env.get("user", "")) if not str(env.get("user", "")).is_empty() else "无账号鉴权"
		var p_text = "已配置密码" if not str(env.get("password", "")).is_empty() else "无密码"
		lbl_detail.text = "地址: %s | %s | %s" % [env.get("server", ""), u_text, p_text]
		lbl_detail.modulate = Color(0.65, 0.72, 0.8)
		vbox_info.add_child(lbl_detail)
		hbox.add_child(vbox_info)
		
		if not is_cur:
			var btn_switch = Button.new()
			btn_switch.text = "切换使用"
			btn_switch.custom_minimum_size = Vector2(85, 32)
			style_button(btn_switch, "secondary")
			btn_switch.pressed.connect(func():
				_switch_to_env_by_id(eid)
				_render_env_manager_list()
			)
			hbox.add_child(btn_switch)
			
		var btn_edit = Button.new()
		btn_edit.text = "✏️ 编辑"
		btn_edit.custom_minimum_size = Vector2(75, 32)
		btn_edit.pressed.connect(func():
			open_edit_env_dialog(env)
		)
		hbox.add_child(btn_edit)
		
		var btn_del = Button.new()
		btn_del.text = "🗑️"
		btn_del.tooltip_text = "删除此环境配置"
		btn_del.custom_minimum_size = Vector2(36, 32)
		btn_del.disabled = (envs.size() <= 1)
		btn_del.pressed.connect(func():
			_delete_env_by_id(eid)
		)
		hbox.add_child(btn_del)
		
		vbox_env_list.add_child(panel)

func _switch_to_env_by_id(eid: String) -> void:
	var envs = ai_settings.get("comfyui_environments", [])
	for i in range(envs.size()):
		var env = envs[i]
		if str(env.get("id", "")) == eid:
			ai_settings["current_env_id"] = eid
			txt_comfy_host.text = env.get("server", "http://127.0.0.1:8188")
			txt_comfy_user.text = env.get("user", "")
			txt_comfy_pass.text = env.get("password", "")
			ai_settings["comfyui_server"] = txt_comfy_host.text
			ai_settings["comfyui_user"] = txt_comfy_user.text
			ai_settings["comfyui_password"] = txt_comfy_pass.text
			AIAssetMgr.save_ai_settings(ai_settings)
			_refresh_env_dropdown()
			lbl_gen_status.text = "已切换至环境: " + str(env.get("name", ""))
			test_comfy_connection()
			break

func _delete_env_by_id(eid: String) -> void:
	var envs = ai_settings.get("comfyui_environments", [])
	if envs.size() <= 1:
		return
	var new_envs = []
	for e in envs:
		if str(e.get("id", "")) != eid:
			new_envs.append(e)
	ai_settings["comfyui_environments"] = new_envs
	if str(ai_settings.get("current_env_id", "")) == eid:
		var next_env = new_envs[0]
		_switch_to_env_by_id(str(next_env.get("id", "")))
	else:
		AIAssetMgr.save_ai_settings(ai_settings)
		_refresh_env_dropdown()
	_render_env_manager_list()

func open_edit_env_dialog(env: Dictionary) -> void:
	editing_env_id = str(env.get("id", ""))
	txt_edit_env_name.text = str(env.get("name", ""))
	txt_edit_env_host.text = str(env.get("server", ""))
	txt_edit_env_user.text = str(env.get("user", ""))
	txt_edit_env_pass.text = str(env.get("password", ""))
	dlg_edit_env.popup_centered()

func _on_confirm_edit_env() -> void:
	var envs = ai_settings.get("comfyui_environments", [])
	for e in envs:
		if str(e.get("id", "")) == editing_env_id:
			var n = txt_edit_env_name.text.strip_edges()
			var h = txt_edit_env_host.text.strip_edges()
			if h.is_empty():
				h = "http://127.0.0.1:8188"
			if n.is_empty():
				n = "环境 (" + h + ")"
			e["name"] = n
			e["server"] = h
			e["user"] = txt_edit_env_user.text.strip_edges()
			e["password"] = txt_edit_env_pass.text.strip_edges()
			
			if str(ai_settings.get("current_env_id", "")) == editing_env_id:
				txt_comfy_host.text = e["server"]
				txt_comfy_user.text = e["user"]
				txt_comfy_pass.text = e["password"]
				ai_settings["comfyui_server"] = e["server"]
				ai_settings["comfyui_user"] = e["user"]
				ai_settings["comfyui_password"] = e["password"]
				test_comfy_connection()
			break
			
	AIAssetMgr.save_ai_settings(ai_settings)
	_refresh_env_dropdown()
	dlg_edit_env.hide()
	if dlg_manage_env.visible:
		_render_env_manager_list()
	lbl_gen_status.text = "✅ 环境配置已更新！"


