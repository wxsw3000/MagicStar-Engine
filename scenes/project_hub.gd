# scenes/project_hub.gd
# 案件工程管理器：自包含工程中心，管理多案件工程浏览、新建、导入、编辑与试玩
extends Control

# 节点引用
var projects_container: VBoxContainer
var lbl_hub_summary: Label
var new_project_modal: PanelContainer
var edit_proj_title: LineEdit
var edit_proj_folder: LineEdit
var edit_proj_author: LineEdit
var edit_proj_desc: TextEdit
var lbl_create_error: Label
var open_file_dialog: FileDialog
var import_ai_dialog: FileDialog
var export_json_dialog: FileDialog
var delete_confirm_dialog: ConfirmationDialog
var pending_export_proj_dir: String = ""
var pending_delete_proj_dir: String = ""
var modal_dimmer: ColorRect

func _ready() -> void:
	DisplayServer.window_set_title("MagicStar AVG Studio - 案件工程中心")
	setup_ui()
	refresh_project_list()

func setup_ui() -> void:
	var vbox_root = VBoxContainer.new()
	vbox_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox_root.add_theme_constant_override("separation", 0)
	add_child(vbox_root)

	# 1. 顶部全局导航栏
	var topbar = PanelContainer.new()
	topbar.custom_minimum_size = Vector2(0, 72)
	var tb_style = StyleBoxFlat.new()
	tb_style.bg_color = Color(0.06, 0.08, 0.12, 0.96)
	tb_style.border_width_bottom = 2
	tb_style.border_color = Color(1.0, 0.82, 0.35, 0.8)
	topbar.add_theme_stylebox_override("panel", tb_style)
	vbox_root.add_child(topbar)

	var tb_margin = MarginContainer.new()
	tb_margin.add_theme_constant_override("margin_left", 32)
	tb_margin.add_theme_constant_override("margin_right", 32)
	topbar.add_child(tb_margin)

	var tb_hbox = HBoxContainer.new()
	tb_hbox.add_theme_constant_override("separation", 18)
	tb_margin.add_child(tb_hbox)

	var title_vbox = VBoxContainer.new()
	title_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tb_hbox.add_child(title_vbox)

	var lbl_title = Label.new()
	lbl_title.text = "🌟 AVG Studio · 无代码工程中心"
	lbl_title.add_theme_font_size_override("font_size", 22)
	lbl_title.modulate = Color(1.0, 0.85, 0.35)
	title_vbox.add_child(lbl_title)

	var lbl_sub = Label.new()
	lbl_sub.text = "单文件夹自包含工程 — Master JSON 驱动剧情流转，AI 视听资产内敛沙盒"
	lbl_sub.add_theme_font_size_override("font_size", 13)
	lbl_sub.modulate = Color(0.65, 0.72, 0.82)
	title_vbox.add_child(lbl_sub)

	var sp1 = Control.new()
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb_hbox.add_child(sp1)

	var btn_new = Button.new()
	btn_new.text = "➕ 新建空白项目"
	btn_new.custom_minimum_size = Vector2(150, 44)
	btn_new.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_new.add_theme_font_size_override("font_size", 16)
	style_secondary_button(btn_new)
	btn_new.pressed.connect(show_new_project_dialog)
	tb_hbox.add_child(btn_new)

	var btn_import_ai = Button.new()
	btn_import_ai.text = "📥 导入主 JSON 创建项目"
	btn_import_ai.custom_minimum_size = Vector2(190, 44)
	btn_import_ai.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_import_ai.add_theme_font_size_override("font_size", 16)
	style_primary_button(btn_import_ai)
	btn_import_ai.pressed.connect(func(): import_ai_dialog.popup_centered(Vector2i(860, 540)))
	tb_hbox.add_child(btn_import_ai)

	var btn_open = Button.new()
	btn_open.text = "📂 载入外部工程目录"
	btn_open.custom_minimum_size = Vector2(150, 44)
	btn_open.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_open.add_theme_font_size_override("font_size", 16)
	style_secondary_button(btn_open)
	btn_open.pressed.connect(func(): open_file_dialog.popup_centered(Vector2i(860, 540)))
	tb_hbox.add_child(btn_open)

	# 2. 中间工程列表滚动区
	var content_margin = MarginContainer.new()
	content_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_margin.add_theme_constant_override("margin_left", 60)
	content_margin.add_theme_constant_override("margin_right", 60)
	content_margin.add_theme_constant_override("margin_top", 24)
	content_margin.add_theme_constant_override("margin_bottom", 24)
	vbox_root.add_child(content_margin)

	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 16)
	content_margin.add_child(content_vbox)

	var filter_row = HBoxContainer.new()
	content_vbox.add_child(filter_row)

	lbl_hub_summary = Label.new()
	lbl_hub_summary.text = "本地案件工程清单"
	lbl_hub_summary.add_theme_font_size_override("font_size", 18)
	lbl_hub_summary.modulate = Color(0.85, 0.9, 0.95)
	filter_row.add_child(lbl_hub_summary)

	var sp_f = Control.new()
	sp_f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_row.add_child(sp_f)

	var btn_refresh = Button.new()
	btn_refresh.text = "🔄 刷新列表"
	btn_refresh.custom_minimum_size = Vector2(100, 34)
	style_secondary_button(btn_refresh)
	btn_refresh.pressed.connect(refresh_project_list)
	filter_row.add_child(btn_refresh)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(scroll)

	projects_container = VBoxContainer.new()
	projects_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	projects_container.add_theme_constant_override("separation", 14)
	scroll.add_child(projects_container)

	# 3. 模态遮罩与新建弹窗
	setup_modals()

func setup_modals() -> void:
	modal_dimmer = ColorRect.new()
	modal_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_dimmer.color = Color(0.02, 0.03, 0.05, 0.75)
	modal_dimmer.visible = false
	add_child(modal_dimmer)

	# 新建工程弹窗
	new_project_modal = PanelContainer.new()
	new_project_modal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	new_project_modal.custom_minimum_size = Vector2(640, 480)
	new_project_modal.offset_left = -320
	new_project_modal.offset_top = -240
	new_project_modal.offset_right = 320
	new_project_modal.offset_bottom = 240
	new_project_modal.visible = false

	var m_style = StyleBoxFlat.new()
	m_style.bg_color = Color(0.08, 0.10, 0.15, 0.98)
	m_style.set_border_width_all(2)
	m_style.border_color = Color(1.0, 0.82, 0.35, 0.9)
	m_style.set_corner_radius_all(14)
	m_style.shadow_color = Color(0, 0, 0, 0.7)
	m_style.shadow_size = 24
	new_project_modal.add_theme_stylebox_override("panel", m_style)
	add_child(new_project_modal)

	var modal_margin = MarginContainer.new()
	modal_margin.add_theme_constant_override("margin_left", 28)
	modal_margin.add_theme_constant_override("margin_top", 22)
	modal_margin.add_theme_constant_override("margin_right", 28)
	modal_margin.add_theme_constant_override("margin_bottom", 22)
	new_project_modal.add_child(modal_margin)

	var m_vbox = VBoxContainer.new()
	m_vbox.add_theme_constant_override("separation", 14)
	modal_margin.add_child(m_vbox)

	var m_title = Label.new()
	m_title.text = "✨ 创建新的案件工程"
	m_title.add_theme_font_size_override("font_size", 22)
	m_title.modulate = Color(1.0, 0.85, 0.35)
	m_vbox.add_child(m_title)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	m_vbox.add_child(grid)

	var l1 = Label.new(); l1.text = "案件作品标题:"; grid.add_child(l1)
	edit_proj_title = LineEdit.new()
	edit_proj_title.placeholder_text = "例如: 东方快车雪夜谋杀案"
	edit_proj_title.custom_minimum_size = Vector2(380, 36)
	edit_proj_title.text_changed.connect(func(t):
		if edit_proj_folder.text.is_empty() or edit_proj_folder.text.begins_with("case_"):
			edit_proj_folder.text = "case_" + str(int(Time.get_unix_time_from_system()) % 10000)
	)
	grid.add_child(edit_proj_title)

	var l2 = Label.new(); l2.text = "工程文件夹名:"; grid.add_child(l2)
	edit_proj_folder = LineEdit.new()
	edit_proj_folder.placeholder_text = "例如: case_03_orient_express"
	edit_proj_folder.custom_minimum_size = Vector2(380, 36)
	grid.add_child(edit_proj_folder)

	var l3 = Label.new(); l3.text = "作者/制作组:"; grid.add_child(l3)
	edit_proj_author = LineEdit.new()
	edit_proj_author.text = "侦探作者"
	edit_proj_author.custom_minimum_size = Vector2(380, 36)
	grid.add_child(edit_proj_author)

	var l4 = Label.new(); l4.text = "案件故事简介:"; grid.add_child(l4)
	edit_proj_desc = TextEdit.new()
	edit_proj_desc.placeholder_text = "简述案件发生背景、核心谜题或侦探设定..."
	edit_proj_desc.custom_minimum_size = Vector2(380, 80)
	grid.add_child(edit_proj_desc)

	lbl_create_error = Label.new()
	lbl_create_error.text = ""
	lbl_create_error.modulate = Color(1.0, 0.4, 0.4)
	m_vbox.add_child(lbl_create_error)

	var m_btn_row = HBoxContainer.new()
	m_btn_row.alignment = BoxContainer.ALIGNMENT_END
	m_btn_row.add_theme_constant_override("separation", 14)
	m_vbox.add_child(m_btn_row)

	var btn_cancel = Button.new()
	btn_cancel.text = "✕ 取消"
	btn_cancel.custom_minimum_size = Vector2(100, 40)
	style_secondary_button(btn_cancel)
	btn_cancel.pressed.connect(hide_new_project_dialog)
	m_btn_row.add_child(btn_cancel)

	var btn_confirm = Button.new()
	btn_confirm.text = "🚀 创建并打开"
	btn_confirm.custom_minimum_size = Vector2(140, 40)
	style_primary_button(btn_confirm)
	btn_confirm.pressed.connect(_on_confirm_create_project)
	m_btn_row.add_child(btn_confirm)

	var user_profile = OS.get_environment("USERPROFILE")
	var default_dir = user_profile.path_join("Desktop") if not user_profile.is_empty() else ProjectSettings.globalize_path("res://")
	if not DirAccess.dir_exists_absolute(default_dir):
		default_dir = ProjectSettings.globalize_path("res://")

	# 外部文件导入弹窗
	open_file_dialog = FileDialog.new()
	open_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	open_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	open_file_dialog.title = "选择已有工程目录中的 project.json"
	open_file_dialog.filters = PackedStringArray(["*.json ; Project Master JSON (*.json)"])
	open_file_dialog.current_dir = ProjectSettings.globalize_path("res://projects/")
	open_file_dialog.file_selected.connect(_on_external_project_selected)
	add_child(open_file_dialog)

	# 主工程 JSON 一键创建项目弹窗 (默认从桌面/任意位置选择)
	import_ai_dialog = FileDialog.new()
	import_ai_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_ai_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_ai_dialog.title = "选择主工程 JSON 文件 (将自动在此创建独立工程文件夹)"
	import_ai_dialog.filters = PackedStringArray(["*.json ; Master Project JSON (*.json)"])
	import_ai_dialog.current_dir = default_dir
	import_ai_dialog.file_selected.connect(_on_import_ai_json_selected)
	add_child(import_ai_dialog)

	# 导出主工程 JSON 弹窗
	export_json_dialog = FileDialog.new()
	export_json_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_json_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_json_dialog.title = "导出全案主工程 JSON 文件"
	export_json_dialog.filters = PackedStringArray(["*.json ; Master Project JSON (*.json)"])
	export_json_dialog.current_dir = default_dir
	export_json_dialog.file_selected.connect(_on_export_file_selected)
	add_child(export_json_dialog)

	# 删除工程二次确认弹窗
	delete_confirm_dialog = ConfirmationDialog.new()
	delete_confirm_dialog.title = "⚠️ 确认删除工程"
	delete_confirm_dialog.ok_button_text = "彻底删除"
	delete_confirm_dialog.cancel_button_text = "取消"
	delete_confirm_dialog.confirmed.connect(_on_confirm_delete_project)
	add_child(delete_confirm_dialog)

# --- 刷新工程卡片列表 ---
func refresh_project_list() -> void:
	for c in projects_container.get_children():
		c.queue_free()

	var list = ProjectContext.get_projects_list()
	lbl_hub_summary.text = "本地案件工程清单 (共 %d 个案件)" % list.size()

	if list.is_empty():
		var empty_label = Label.new()
		empty_label.text = "暂无案件工程，点击右上角【📥 导入主 JSON 创建项目】或【➕ 新建空白项目】开始创作！"
		empty_label.modulate = Color(0.7, 0.75, 0.85)
		projects_container.add_child(empty_label)
		return

	for p in list:
		var card = create_project_card(p)
		projects_container.add_child(card)

func create_project_card(pdata: Dictionary) -> PanelContainer:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 136)

	var c_style = StyleBoxFlat.new()
	c_style.bg_color = Color(0.08, 0.10, 0.15, 0.94)
	c_style.set_border_width_all(1)
	c_style.border_color = Color(0.28, 0.38, 0.52, 0.6)
	c_style.set_corner_radius_all(12)
	c_style.shadow_color = Color(0, 0, 0, 0.4)
	c_style.shadow_size = 8
	card.add_theme_stylebox_override("panel", c_style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	card.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	margin.add_child(hbox)

	# 封面缩略图
	var thumb_frame = PanelContainer.new()
	thumb_frame.custom_minimum_size = Vector2(170, 104)
	var tf_style = StyleBoxFlat.new()
	tf_style.bg_color = Color(0.04, 0.05, 0.08, 1.0)
	tf_style.set_border_width_all(1)
	tf_style.border_color = Color(0.35, 0.45, 0.6, 0.4)
	tf_style.set_corner_radius_all(8)
	thumb_frame.add_theme_stylebox_override("panel", tf_style)
	hbox.add_child(thumb_frame)

	var tex_rect = TextureRect.new()
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb_frame.add_child(tex_rect)

	var cover_path = pdata.get("cover_image", "")
	if not cover_path.is_empty():
		var abs_cover = ProjectSettings.globalize_path(cover_path)
		if FileAccess.file_exists(abs_cover):
			var img = Image.new()
			if img.load(abs_cover) == OK:
				tex_rect.texture = ImageTexture.create_from_image(img)

	if tex_rect.texture == null:
		var ph_lbl = Label.new()
		ph_lbl.text = "🖼️\n待生成封面"
		ph_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ph_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ph_lbl.modulate = Color(0.4, 0.5, 0.6, 0.7)
		thumb_frame.add_child(ph_lbl)

	# 中间详情信息
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	info_vbox.add_theme_constant_override("separation", 6)
	hbox.add_child(info_vbox)

	var title_lbl = Label.new()
	title_lbl.text = "《%s》" % pdata.get("title", "未命名案件")
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.modulate = Color(1.0, 0.85, 0.35)
	info_vbox.add_child(title_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = pdata.get("description", "案件工程")
	desc_lbl.add_theme_font_size_override("font_size", 15)
	desc_lbl.modulate = Color(0.72, 0.78, 0.88)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.max_lines_visible = 2
	info_vbox.add_child(desc_lbl)

	var meta_lbl = Label.new()
	meta_lbl.text = "📁 %s  |  作者: %s  |  📜 %d 节点  |  🎨 %d 素材  |  🕒 %s" % [
		pdata.get("dir_path", ""),
		pdata.get("author", "未知"),
		pdata.get("nodes_count", 0),
		pdata.get("assets_count", 0),
		pdata.get("updated_at", "")
	]
	meta_lbl.add_theme_font_size_override("font_size", 13)
	meta_lbl.modulate = Color(0.55, 0.65, 0.75)
	info_vbox.add_child(meta_lbl)

	# 右侧操作按钮组
	var btn_vbox = VBoxContainer.new()
	btn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_vbox.add_theme_constant_override("separation", 8)
	hbox.add_child(btn_vbox)

	var dir_path = pdata.get("dir_path", "")

	var btn_edit = Button.new()
	btn_edit.text = "🛠️ 进入编辑器"
	btn_edit.custom_minimum_size = Vector2(130, 42)
	style_primary_button(btn_edit)
	btn_edit.pressed.connect(func(): open_project_in_editor(dir_path))
	btn_vbox.add_child(btn_edit)

	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_vbox.add_child(btn_row)

	var btn_play = Button.new()
	btn_play.text = "▶ 试玩"
	btn_play.custom_minimum_size = Vector2(62, 34)
	style_secondary_button(btn_play)
	btn_play.pressed.connect(func(): playtest_project(dir_path))
	btn_row.add_child(btn_play)

	var btn_export = Button.new()
	btn_export.text = "📤 导出"
	btn_export.custom_minimum_size = Vector2(62, 34)
	style_secondary_button(btn_export)
	btn_export.pressed.connect(func():
		pending_export_proj_dir = dir_path
		export_json_dialog.current_file = pdata.get("folder_name", "project") + "_master.json"
		export_json_dialog.popup_centered(Vector2i(860, 540))
	)
	btn_row.add_child(btn_export)

	var btn_folder = Button.new()
	btn_folder.text = "📁 目录"
	btn_folder.custom_minimum_size = Vector2(62, 34)
	style_secondary_button(btn_folder)
	btn_folder.pressed.connect(func():
		var abs_dir = ProjectSettings.globalize_path(dir_path)
		OS.shell_open(abs_dir)
	)
	btn_row.add_child(btn_folder)

	var btn_delete = Button.new()
	btn_delete.text = "🗑️ 删除"
	btn_delete.custom_minimum_size = Vector2(62, 34)
	style_danger_button(btn_delete)
	btn_delete.pressed.connect(func():
		pending_delete_proj_dir = dir_path
		delete_confirm_dialog.dialog_text = "确定要彻底删除案件工程《%s》吗？\n文件夹: %s\n此操作将永久移除该工程与其内部的所有美术音频资源！" % [pdata.get("title", ""), dir_path]
		delete_confirm_dialog.popup_centered(Vector2i(540, 200))
	)
	btn_row.add_child(btn_delete)

	return card

# --- 按钮风格美化 ---
func style_primary_button(btn: Button) -> void:
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var norm = StyleBoxFlat.new()
	norm.bg_color = Color(0.85, 0.65, 0.15, 0.95)
	norm.set_border_width_all(1)
	norm.border_color = Color(1.0, 0.95, 0.6, 1.0)
	norm.set_corner_radius_all(8)
	norm.content_margin_left = 14
	norm.content_margin_right = 14
	
	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(1.0, 0.78, 0.25, 1.0)
	hover.set_border_width_all(2)
	hover.border_color = Color(1.0, 1.0, 0.8, 1.0)
	hover.set_corner_radius_all(8)
	hover.content_margin_left = 14
	hover.content_margin_right = 14

	btn.add_theme_stylebox_override("normal", norm)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_color_override("font_color", Color(0.06, 0.07, 0.09, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0, 0, 0, 1.0))

func style_secondary_button(btn: Button) -> void:
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var norm = StyleBoxFlat.new()
	norm.bg_color = Color(0.12, 0.16, 0.23, 0.85)
	norm.set_border_width_all(1)
	norm.border_color = Color(0.3, 0.4, 0.55, 0.6)
	norm.set_corner_radius_all(8)
	norm.content_margin_left = 12
	norm.content_margin_right = 12
	
	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(0.18, 0.24, 0.35, 0.95)
	hover.set_border_width_all(1)
	hover.border_color = Color(1.0, 0.82, 0.35, 0.9)
	hover.set_corner_radius_all(8)
	hover.content_margin_left = 12
	hover.content_margin_right = 12

	btn.add_theme_stylebox_override("normal", norm)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)

func style_danger_button(btn: Button) -> void:
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var norm = StyleBoxFlat.new()
	norm.bg_color = Color(0.35, 0.12, 0.15, 0.85)
	norm.set_border_width_all(1)
	norm.border_color = Color(0.65, 0.25, 0.3, 0.7)
	norm.set_corner_radius_all(8)
	norm.content_margin_left = 12
	norm.content_margin_right = 12
	
	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(0.55, 0.15, 0.2, 0.95)
	hover.set_border_width_all(1)
	hover.border_color = Color(1.0, 0.4, 0.45, 0.9)
	hover.set_corner_radius_all(8)
	hover.content_margin_left = 12
	hover.content_margin_right = 12

	btn.add_theme_stylebox_override("normal", norm)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.85, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))

# --- 操作回调 ---
func show_new_project_dialog() -> void:
	edit_proj_title.text = ""
	edit_proj_folder.text = "case_" + str(int(Time.get_unix_time_from_system()) % 100000)
	edit_proj_author.text = "侦探作者"
	edit_proj_desc.text = ""
	lbl_create_error.text = ""
	modal_dimmer.visible = true
	new_project_modal.visible = true

func hide_new_project_dialog() -> void:
	modal_dimmer.visible = false
	new_project_modal.visible = false

func _on_confirm_create_project() -> void:
	var title = edit_proj_title.text.strip_edges()
	var folder = edit_proj_folder.text.strip_edges()
	var author = edit_proj_author.text.strip_edges()
	var desc = edit_proj_desc.text.strip_edges()

	if title.is_empty():
		lbl_create_error.text = "请输入案件作品标题！"
		return
	if folder.is_empty():
		lbl_create_error.text = "请输入有效的文件夹名！"
		return

	var res = ProjectContext.create_project(folder, title, author, desc)
	if res.get("success", false):
		hide_new_project_dialog()
		open_project_in_editor(res.get("path", ""))
	else:
		lbl_create_error.text = res.get("message", "创建工程失败")

func _on_import_ai_json_selected(file_path: String) -> void:
	var res = ProjectContext.import_project_from_json(file_path)
	if res.get("success", false):
		print("[ProjectHub] ✅ 成功从 AI 故事 JSON 自动创建案件工程: %s (%s)" % [res.get("title", ""), res.get("path", "")])
		refresh_project_list()
		open_project_in_editor(res.get("path", ""))
	else:
		OS.alert("导入 AI 故事 JSON 失败:\n" + res.get("message", "未知错误"), "导入失败")

func _on_external_project_selected(file_path: String) -> void:
	var proj_dir = file_path.get_base_dir() + "/"
	if FileAccess.file_exists(proj_dir + "project.json") and ProjectContext.load_project(proj_dir):
		refresh_project_list()
		open_project_in_editor(proj_dir)
	else:
		_on_import_ai_json_selected(file_path)

func open_project_in_editor(dir_path: String) -> void:
	ProjectContext.load_project(dir_path)
	get_tree().change_scene_to_file("res://editor/ui/editor_main.tscn")

func playtest_project(dir_path: String) -> void:
	ProjectContext.load_project(dir_path)
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_export_file_selected(dest_path: String) -> void:
	if pending_export_proj_dir.is_empty():
		return
	var res = ProjectContext.export_project_json(pending_export_proj_dir, dest_path)
	if res.get("success", false):
		print("[ProjectHub] ✅ 导出全案 JSON 成功: %s" % dest_path)
	else:
		OS.alert("导出工程 JSON 失败:\n" + res.get("message", "未知错误"), "导出失败")
	pending_export_proj_dir = ""

func _on_confirm_delete_project() -> void:
	if pending_delete_proj_dir.is_empty():
		return
	var res = ProjectContext.delete_project(pending_delete_proj_dir)
	if res.get("success", false):
		print("[ProjectHub] 🗑️ 删除工程成功: %s" % pending_delete_proj_dir)
		refresh_project_list()
	else:
		OS.alert("删除工程失败:\n" + res.get("message", "未知错误"), "删除失败")
	pending_delete_proj_dir = ""
