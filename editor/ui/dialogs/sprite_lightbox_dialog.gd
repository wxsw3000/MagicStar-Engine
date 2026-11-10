# editor/ui/dialogs/sprite_lightbox_dialog.gd
# 高清立绘相册画廊查看器：支持大图放大检视、键盘左右键流畅连续轮播浏览、微表情提示词即时查阅
class_name SpriteLightboxDialog
extends Window

const AIAssetMgr = preload("res://editor/core/ai_asset_manager.gd")

var sprites_list: Array = []
var current_index: int = 0
var character_name: String = ""

# 控件引用
var lbl_title: Label
var lbl_counter: Label
var lbl_resolution: Label
var img_viewport_rect: TextureRect
var txt_prompt_info: TextEdit
var btn_prev: Button
var btn_next: Button
var btn_open_folder: Button
var btn_fit_toggle: Button
var is_fit_mode: bool = true

func _init() -> void:
	title = "🖼️ 高清立绘画廊检视器 (Image Lightbox & Continuous Viewer)"
	size = Vector2(960, 780)
	exclusive = true
	unresizable = false

func _ready() -> void:
	close_requested.connect(queue_free)
	_build_ui()
	_update_view()

func setup_gallery(cname: String, list: Array, start_index: int = 0) -> void:
	character_name = cname
	sprites_list = list
	if start_index >= 0 and start_index < sprites_list.size():
		current_index = start_index
	else:
		current_index = 0
	if is_inside_tree():
		_update_view()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_LEFT or event.keycode == KEY_A:
			_navigate(-1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_RIGHT or event.keycode == KEY_D:
			_navigate(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			queue_free()
			get_viewport().set_input_as_handled()

func _build_ui() -> void:
	var root = MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 14)
	root.add_theme_constant_override("margin_top", 12)
	root.add_theme_constant_override("margin_right", 14)
	root.add_theme_constant_override("margin_bottom", 14)
	add_child(root)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	root.add_child(main_vbox)

	# --- 1. 顶部状态栏 ---
	var top_bar = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 10)
	main_vbox.add_child(top_bar)

	lbl_title = Label.new()
	lbl_title.text = "立绘浏览"
	lbl_title.add_theme_font_size_override("font_size", 16)
	lbl_title.modulate = Color(1.0, 0.85, 0.4)
	top_bar.add_child(lbl_title)

	lbl_counter = Label.new()
	lbl_counter.text = "[0 / 0]"
	lbl_counter.modulate = Color(0.7, 0.9, 1.0)
	top_bar.add_child(lbl_counter)

	lbl_resolution = Label.new()
	lbl_resolution.text = "分辨率: -"
	lbl_resolution.modulate = Color(0.6, 0.7, 0.8)
	top_bar.add_child(lbl_resolution)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)

	var lbl_keys_hint = Label.new()
	lbl_keys_hint.text = "⌨️ 快捷键: 键盘 ← / → (或 A / D) 连续翻页浏览 | ESC 退出"
	lbl_keys_hint.modulate = Color(0.65, 0.75, 0.85)
	top_bar.add_child(lbl_keys_hint)

	# --- 2. 中间大图视口 ---
	var center_panel = PanelContainer.new()
	center_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cp_style = StyleBoxFlat.new()
	cp_style.bg_color = Color(0.04, 0.05, 0.07, 1.0)
	cp_style.set_corner_radius_all(6)
	cp_style.border_width_left = 1; cp_style.border_width_right = 1
	cp_style.border_width_top = 1; cp_style.border_width_bottom = 1
	cp_style.border_color = Color(0.2, 0.25, 0.32)
	center_panel.add_theme_stylebox_override("panel", cp_style)
	main_vbox.add_child(center_panel)

	var view_container = Control.new()
	view_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_panel.add_child(view_container)

	img_viewport_rect = TextureRect.new()
	img_viewport_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	img_viewport_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img_viewport_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view_container.add_child(img_viewport_rect)

	# 左右浮动翻页大箭头
	var arrow_prev = Button.new()
	arrow_prev.text = "◀"
	arrow_prev.custom_minimum_size = Vector2(48, 80)
	arrow_prev.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	arrow_prev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow_prev.pressed.connect(func(): _navigate(-1))
	view_container.add_child(arrow_prev)

	var arrow_next = Button.new()
	arrow_next.text = "▶"
	arrow_next.custom_minimum_size = Vector2(48, 80)
	arrow_next.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	arrow_next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow_next.pressed.connect(func(): _navigate(1))
	view_container.add_child(arrow_next)

	# --- 3. 底部详细信息与导航栏 ---
	var bottom_vbox = VBoxContainer.new()
	bottom_vbox.add_theme_constant_override("separation", 6)
	main_vbox.add_child(bottom_vbox)

	txt_prompt_info = TextEdit.new()
	txt_prompt_info.custom_minimum_size = Vector2(0, 75)
	txt_prompt_info.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	txt_prompt_info.editable = false
	bottom_vbox.add_child(txt_prompt_info)

	var nav_bar = HBoxContainer.new()
	nav_bar.add_theme_constant_override("separation", 10)
	bottom_vbox.add_child(nav_bar)

	btn_prev = Button.new()
	btn_prev.text = "⬅️ 上一张 (Left Arrow)"
	btn_prev.custom_minimum_size = Vector2(170, 36)
	btn_prev.pressed.connect(func(): _navigate(-1))
	nav_bar.add_child(btn_prev)

	btn_next = Button.new()
	btn_next.text = "下一张 ➡️ (Right Arrow)"
	btn_next.custom_minimum_size = Vector2(170, 36)
	btn_next.pressed.connect(func(): _navigate(1))
	nav_bar.add_child(btn_next)

	var bot_spacer = Control.new()
	bot_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_bar.add_child(bot_spacer)

	var btn_rembg = Button.new()
	btn_rembg.text = "✂️ 一键透明去背"
	btn_rembg.tooltip_text = "对当前浏览立绘执行 u2net 深度发丝抠图，生成透明背景 RGBA PNG"
	btn_rembg.custom_minimum_size = Vector2(130, 36)
	btn_rembg.pressed.connect(func():
		if sprites_list.is_empty():
			return
		var item = sprites_list[current_index]
		var path = item.get("local_path", item.get("path", ""))
		if path.is_empty():
			return
		var py = AIAssetMgr.get_python_executable()
		var abs_p = ProjectSettings.globalize_path(path)
		var bridge_script = ProjectSettings.globalize_path("res://tools/ai_bridge.py")
		var output = []
		OS.execute(py, [bridge_script, "remove_background", "--image", abs_p, "--save", abs_p], output, true)
		_update_view()
	)
	nav_bar.add_child(btn_rembg)

	btn_open_folder = Button.new()
	btn_open_folder.text = "📂 打开所在目录"
	btn_open_folder.custom_minimum_size = Vector2(130, 36)
	btn_open_folder.pressed.connect(_open_current_in_explorer)
	nav_bar.add_child(btn_open_folder)

	var btn_close = Button.new()
	btn_close.text = "关闭检视"
	btn_close.custom_minimum_size = Vector2(100, 36)
	btn_close.pressed.connect(queue_free)
	nav_bar.add_child(btn_close)

func _navigate(dir: int) -> void:
	if sprites_list.is_empty():
		return
	current_index = (current_index + dir) % sprites_list.size()
	if current_index < 0:
		current_index = sprites_list.size() - 1
	_update_view()

func _update_view() -> void:
	if sprites_list.is_empty() or current_index < 0 or current_index >= sprites_list.size():
		lbl_title.text = "暂无立绘数据"
		lbl_counter.text = "[0 / 0]"
		txt_prompt_info.text = ""
		img_viewport_rect.texture = null
		return

	var item = sprites_list[current_index]
	var iname = item.get("name", item.get("id", "立绘"))
	var path = item.get("local_path", item.get("path", ""))
	var prompt = item.get("prompt", "")
	var qwen_cmd = item.get("qwen_diff_prompt", "")
	var is_base = item.get("is_base", false)
	var is_turnaround = (item.get("sub_type", "") == "turnaround" or item.get("type", "") == "turnaround")

	var tag = ""
	if is_turnaround:
		tag = " (📐 全身三视图概念母本)"
	elif is_base:
		tag = " (🌟 舞台形象基准锚点)"

	lbl_title.text = "👤 %s · %s%s" % [character_name, iname, tag]
	lbl_counter.text = "[%d / %d]" % [current_index + 1, sprites_list.size()]

	var tex = _load_texture(path)
	if tex:
		img_viewport_rect.texture = tex
		var abs_path = ProjectSettings.globalize_path(path)
		var is_alpha = false
		if FileAccess.file_exists(abs_path):
			var im = Image.load_from_file(abs_path)
			if im:
				is_alpha = (im.detect_alpha() != Image.ALPHA_NONE)
		var alpha_tag = " | 🟢 透明通道 (RGBA)" if is_alpha else " | ⚪ 纯色背景 (RGB)"
		lbl_resolution.text = "分辨率: %d × %d | 格式: %s%s | 路径: %s" % [tex.get_width(), tex.get_height(), "16:9 概念三视图" if is_turnaround else "2:3 舞台立绘", alpha_tag, path.get_file()]
	else:
		img_viewport_rect.texture = null
		lbl_resolution.text = "⚠️ 图片未生成或文件不存在: %s" % path

	var info_text = ""
	if is_turnaround:
		info_text = "【全身三视图概念母本 Prompt (Turnaround DNA)】:\n%s" % prompt
	else:
		info_text = "【当前表情描述 Prompt】:\n%s" % prompt
		if not qwen_cmd.is_empty():
			info_text += "\n\n【Qwen-Image / Nunchaku 指令级微表情 Prompt】:\n%s" % qwen_cmd
	txt_prompt_info.text = info_text

func _load_texture(path: String) -> ImageTexture:
	if path.is_empty():
		return null
	var abs_path = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return null
	var img = Image.load_from_file(abs_path)
	if img:
		return ImageTexture.create_from_image(img)
	return null

func _open_current_in_explorer() -> void:
	if sprites_list.is_empty():
		return
	var item = sprites_list[current_index]
	var path = item.get("local_path", item.get("path", ""))
	if path.is_empty():
		return
	var abs_path = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		var err = OS.shell_show_in_file_manager(abs_path, true)
		if err == OK:
			return
	var dir = abs_path.get_base_dir()
	OS.shell_open(dir)
