# editor/ui/editor_main.gd
# AVG Studio 可视化游戏编辑器主界面（整合单行顶部工作流导航，杜绝多层标签堆叠）
extends Control

const FlowGraphTab = preload("res://editor/ui/tabs/flow_graph_tab.gd")
const ScenePainterTab = preload("res://editor/ui/tabs/scene_painter_tab.gd")
const DialogueTab = preload("res://editor/ui/tabs/dialogue_tab.gd")
const ClueTab = preload("res://editor/ui/tabs/clue_tab.gd")
const ReasoningTab = preload("res://editor/ui/tabs/reasoning_tab.gd")
const AIAssetTab = preload("res://editor/ui/tabs/ai_asset_tab.gd")
const ProjectSettingsTab = preload("res://editor/ui/tabs/project_settings_tab.gd")
const ExportManager = preload("res://editor/core/export_manager.gd")
const ExportDialog = preload("res://editor/ui/dialogs/export_dialog.gd")
const ProjectPackManager = preload("res://editor/core/project_pack_manager.gd")

var tab_container: TabContainer
var flow_graph_tab: Control
var scene_painter_tab: Control
var dialogue_tab: Control
var clue_tab: Control
var reasoning_tab: Control
var ai_asset_tab: Control
var project_settings_tab: Control

var nav_buttons: Array[Button] = []
var lbl_status: Label
var import_dialog: FileDialog
var export_pack_dialog: FileDialog

func _ready() -> void:
	DisplayServer.window_set_title("MagicStar AVG Studio - " + ProjectContext.get_active_project_title())
	setup_ui()
	setup_file_dialogs()
	switch_tab(0)

func setup_ui() -> void:
	var vbox_root = VBoxContainer.new()
	vbox_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox_root.add_theme_constant_override("separation", 0)
	add_child(vbox_root)

	# =========================================================================
	# 整合式单行全局导航顶栏 (高度 54px，融合身份、工作流导航、快捷操作与菜单)
	# =========================================================================
	var topbar = PanelContainer.new()
	topbar.custom_minimum_size = Vector2(0, 54)
	var tb_style = StyleBoxFlat.new()
	tb_style.bg_color = Color(0.06, 0.08, 0.12, 0.98)
	tb_style.border_width_bottom = 2
	tb_style.border_color = Color(1.0, 0.82, 0.35, 0.6)
	topbar.add_theme_stylebox_override("panel", tb_style)
	vbox_root.add_child(topbar)

	var tb_margin = MarginContainer.new()
	tb_margin.add_theme_constant_override("margin_left", 16)
	tb_margin.add_theme_constant_override("margin_right", 16)
	topbar.add_child(tb_margin)

	var tb_hbox = HBoxContainer.new()
	tb_hbox.add_theme_constant_override("separation", 14)
	tb_margin.add_child(tb_hbox)

	# --- 左区：返回工程列表与工程身份 ---
	var btn_back_hub = Button.new()
	btn_back_hub.text = "🏠 工程中心"
	btn_back_hub.custom_minimum_size = Vector2(100, 36)
	btn_back_hub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	style_secondary_btn(btn_back_hub)
	btn_back_hub.pressed.connect(func():
		_on_save_all_pressed()
		get_tree().change_scene_to_file("res://scenes/project_hub.tscn")
	)
	tb_hbox.add_child(btn_back_hub)

	var sep_left = VSeparator.new()
	tb_hbox.add_child(sep_left)

	var proj_info_box = VBoxContainer.new()
	proj_info_box.alignment = BoxContainer.ALIGNMENT_CENTER
	proj_info_box.add_theme_constant_override("separation", 2)
	tb_hbox.add_child(proj_info_box)

	var lbl_proj_title = Label.new()
	lbl_proj_title.text = "《%s》" % ProjectContext.get_active_project_title()
	lbl_proj_title.add_theme_font_size_override("font_size", 17)
	lbl_proj_title.modulate = Color(1.0, 0.85, 0.35)
	proj_info_box.add_child(lbl_proj_title)

	lbl_status = Label.new()
	lbl_status.text = "🟢 就绪"
	lbl_status.add_theme_font_size_override("font_size", 12)
	lbl_status.modulate = Color(0.65, 0.8, 0.7)
	proj_info_box.add_child(lbl_status)

	var sp_left = Control.new()
	sp_left.custom_minimum_size = Vector2(12, 0)
	tb_hbox.add_child(sp_left)

	# --- 中区：统一工作流导航切换栏 (替代多层混乱的Tab栏) ---
	var nav_hbox = HBoxContainer.new()
	nav_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_hbox.add_theme_constant_override("separation", 6)
	tb_hbox.add_child(nav_hbox)

	var tab_names = [
		"🗺️ 故事流程",
		"🔍 搜证画板",
		"📜 剧本台词",
		"🧩 线索物证",
		"⚖️ 推理谜题",
		"🎨 AI 资产工坊",
		"⚙️ 项目配置"
	]

	nav_buttons.clear()
	for i in range(tab_names.size()):
		var t_btn = Button.new()
		t_btn.text = tab_names[i]
		t_btn.custom_minimum_size = Vector2(110, 38)
		t_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		t_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var tab_idx = i
		t_btn.pressed.connect(func(): switch_tab(tab_idx))
		nav_hbox.add_child(t_btn)
		nav_buttons.append(t_btn)

	# --- 右区：快捷操作与更多菜单 ---
	var actions_hbox = HBoxContainer.new()
	actions_hbox.add_theme_constant_override("separation", 10)
	actions_hbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tb_hbox.add_child(actions_hbox)

	var btn_save = Button.new()
	btn_save.text = "💾 保存 (Ctrl+S)"
	btn_save.custom_minimum_size = Vector2(120, 36)
	style_secondary_btn(btn_save)
	btn_save.pressed.connect(_on_save_all_pressed)
	actions_hbox.add_child(btn_save)

	var btn_playtest = Button.new()
	btn_playtest.text = "▶ 运行试玩 (F5)"
	btn_playtest.custom_minimum_size = Vector2(125, 36)
	style_primary_btn(btn_playtest)
	btn_playtest.pressed.connect(func(): run_playtest(""))
	actions_hbox.add_child(btn_playtest)

	# 更多下拉菜单 (收纳次要操作)
	var menu_more = MenuButton.new()
	menu_more.text = "更多操作 ▾"
	menu_more.custom_minimum_size = Vector2(95, 36)
	style_secondary_btn(menu_more)
	var popup = menu_more.get_popup()
	popup.add_item("📥 导入总工程 JSON...", 1)
	popup.add_item("📤 导出总工程 JSON...", 2)
	popup.add_separator()
	popup.add_item("📦 多平台打包发布...", 3)
	popup.add_item("🎮 全屏试玩模式", 4)
	popup.add_item("📁 打开工程文件夹", 5)
	popup.id_pressed.connect(_on_menu_more_item_pressed)
	actions_hbox.add_child(menu_more)

	# =========================================================================
	# 核心工作区画布 (隐藏原生Tab栏头，完全由顶栏控制)
	# =========================================================================
	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.tabs_visible = false # 彻底隐藏 Godot 原生第二层 Tab 栏！
	vbox_root.add_child(tab_container)

	# 0. 流程图
	flow_graph_tab = FlowGraphTab.new()
	flow_graph_tab.playtest_node_requested.connect(func(nid): run_playtest(nid))
	flow_graph_tab.edit_scene_requested.connect(_on_jump_to_scene)
	flow_graph_tab.edit_dialogue_requested.connect(_on_jump_to_dialogue)
	tab_container.add_child(flow_graph_tab)

	# 1. 搜证画板
	scene_painter_tab = ScenePainterTab.new()
	tab_container.add_child(scene_painter_tab)

	# 2. 剧本对白
	dialogue_tab = DialogueTab.new()
	tab_container.add_child(dialogue_tab)

	# 3. 线索档案
	clue_tab = ClueTab.new()
	tab_container.add_child(clue_tab)

	# 4. 推理矩阵
	reasoning_tab = ReasoningTab.new()
	tab_container.add_child(reasoning_tab)

	# 5. AI 资产工坊
	ai_asset_tab = AIAssetTab.new()
	tab_container.add_child(ai_asset_tab)

	# 6. 项目全局配置
	project_settings_tab = ProjectSettingsTab.new()
	tab_container.add_child(project_settings_tab)

# --- 标签页平滑切换与高亮反馈 ---
func switch_tab(idx: int) -> void:
	if idx < 0 or idx >= tab_container.get_child_count():
		return
	tab_container.current_tab = idx
	for i in range(nav_buttons.size()):
		var btn = nav_buttons[i]
		style_nav_btn(btn, i == idx)

func style_nav_btn(btn: Button, is_active: bool) -> void:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.22, 0.32, 1.0) if is_active else Color(0.08, 0.10, 0.14, 0.5)
	sb.border_width_bottom = 3 if is_active else 0
	sb.border_color = Color(1.0, 0.85, 0.35, 1.0)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4

	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(0.18, 0.25, 0.36, 0.9)
	hover.border_width_bottom = 3
	hover.border_color = Color(1.0, 0.9, 0.5, 0.8)
	hover.set_corner_radius_all(6)
	hover.content_margin_left = 12
	hover.content_margin_right = 12
	hover.content_margin_top = 4
	hover.content_margin_bottom = 4

	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6) if is_active else Color(0.75, 0.82, 0.9))

func style_primary_btn(btn: Button) -> void:
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var norm = StyleBoxFlat.new()
	norm.bg_color = Color(0.85, 0.65, 0.15, 0.95)
	norm.set_border_width_all(1)
	norm.border_color = Color(1.0, 0.95, 0.6, 1.0)
	norm.set_corner_radius_all(6)
	norm.content_margin_left = 12
	norm.content_margin_right = 12

	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(1.0, 0.78, 0.25, 1.0)
	hover.set_border_width_all(1)
	hover.border_color = Color(1.0, 1.0, 0.8, 1.0)
	hover.set_corner_radius_all(6)
	hover.content_margin_left = 12
	hover.content_margin_right = 12

	btn.add_theme_stylebox_override("normal", norm)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_color_override("font_color", Color(0.06, 0.07, 0.09, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0, 0, 0, 1.0))

func style_secondary_btn(btn: Button) -> void:
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var norm = StyleBoxFlat.new()
	norm.bg_color = Color(0.12, 0.16, 0.23, 0.85)
	norm.set_border_width_all(1)
	norm.border_color = Color(0.3, 0.4, 0.55, 0.6)
	norm.set_corner_radius_all(6)
	norm.content_margin_left = 10
	norm.content_margin_right = 10

	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(0.18, 0.24, 0.35, 0.95)
	hover.set_border_width_all(1)
	hover.border_color = Color(1.0, 0.82, 0.35, 0.9)
	hover.set_corner_radius_all(6)
	hover.content_margin_left = 10
	hover.content_margin_right = 10

	btn.add_theme_stylebox_override("normal", norm)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)

# --- 弹窗与更多操作处理 ---
func setup_file_dialogs() -> void:
	import_dialog = FileDialog.new()
	import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_dialog.title = "选择要导入的全案总工程 JSON 文件"
	import_dialog.filters = PackedStringArray(["*.json ; Project Master JSON (*.json)"])
	import_dialog.current_dir = ProjectSettings.globalize_path("res://projects/")
	import_dialog.file_selected.connect(_on_import_confirmed)
	add_child(import_dialog)

	export_pack_dialog = FileDialog.new()
	export_pack_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_pack_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_pack_dialog.title = "导出全案总工程 JSON 文件"
	export_pack_dialog.filters = PackedStringArray(["*.json ; Project Master JSON (*.json)"])
	export_pack_dialog.current_dir = ProjectSettings.globalize_path("res://projects/")
	export_pack_dialog.current_file = "project_master_export.json"
	export_pack_dialog.file_selected.connect(_on_export_pack_confirmed)
	add_child(export_pack_dialog)

func _on_menu_more_item_pressed(id: int) -> void:
	match id:
		1: import_dialog.popup_centered(Vector2i(820, 520))
		2: export_pack_dialog.popup_centered(Vector2i(820, 520))
		3: _on_export_pressed()
		4: get_tree().change_scene_to_file("res://scenes/main.tscn")
		5:
			var abs_dir = ProjectSettings.globalize_path(ProjectContext.active_project_dir)
			OS.shell_open(abs_dir)

func _on_import_confirmed(file_path: String) -> void:
	var res = ProjectPackManager.import_master_json(file_path)
	if res.get("success", false):
		lbl_status.text = "🟢 导入成功"
		flow_graph_tab.refresh_graph()
		scene_painter_tab.refresh_scene_list()
		dialogue_tab.refresh_dialogue_list()
		clue_tab.refresh_clues()
		reasoning_tab.refresh_reasonings()
		project_settings_tab.load_data()
		ai_asset_tab.load_data()
	else:
		lbl_status.text = "❌ 导入失败: " + res.get("message", "未知错误")

func _on_export_pack_confirmed(file_path: String) -> void:
	_on_save_all_pressed()
	var res = ProjectPackManager.export_master_json(file_path)
	if res.get("success", false):
		lbl_status.text = "🟢 导出成功"
	else:
		lbl_status.text = "❌ 导出失败: " + res.get("message", "未知错误")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_F5:
			run_playtest("")
		elif event.keycode == KEY_S and event.ctrl_pressed:
			_on_save_all_pressed()

func run_playtest(node_id: String = "") -> void:
	var godot_exe = ExportManager.get_godot_executable()
	var proj_path = ProjectSettings.globalize_path("res://")
	var args = ["--path", proj_path, "res://scenes/main.tscn"]
	if not ProjectContext.active_project_dir.is_empty():
		args.append("++project=" + ProjectContext.active_project_dir)
	if not node_id.is_empty():
		args.append("++start-node=" + node_id)

	print("[AVG Studio] 正在启动试玩进程: ", args)
	OS.create_process(godot_exe, args)

func _on_save_all_pressed() -> void:
	scene_painter_tab.save_current_scene()
	dialogue_tab.save_current_dialogue()
	clue_tab.save_current_clue()
	reasoning_tab.save_current_reasoning()
	project_settings_tab.save_settings()
	flow_graph_tab.refresh_graph()
	ai_asset_tab.save_current_settings()
	ProjectContext.save_active_project()
	lbl_status.text = "🟢 已存盘 (" + Time.get_time_string_from_system() + ")"

func _on_export_pressed() -> void:
	var dlg = ExportDialog.new()
	add_child(dlg)
	dlg.popup_centered()

func _on_jump_to_scene(scene_id: String) -> void:
	switch_tab(1)
	scene_painter_tab.load_scene(scene_id)

func _on_jump_to_dialogue(dialogue_id: String) -> void:
	switch_tab(2)
	dialogue_tab.load_dialogue(dialogue_id)
