# editor/ui/tabs/ai_asset_tab.gd
# AVG Studio 专属 AI 资产工坊界面：管理清单、配置风格、调度 ComfyUI 生图与 Edge-TTS 批量/单项生成
class_name AIAssetTab
extends Control

const AIAssetMgr = preload("res://editor/core/ai_asset_manager.gd")

# 数据引用
var ai_settings: Dictionary = {}
var manifest_items: Array = []
var selected_item_id: String = ""

# 顶部配置栏控件
var opt_server_preset: OptionButton
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

# 资产清单列表控件
var opt_filter: OptionButton
var lbl_asset_summary: Label
var vbox_asset_list: VBoxContainer

# 右侧检视与生成台控件
var lbl_selected_title: Label
var lbl_selected_path: Label
var lbl_selected_status: Label
var img_preview: TextureRect
var audio_preview_box: HBoxContainer
var btn_audio_play: Button
var btn_audio_stop: Button
var lbl_audio_info: Label
var preview_audio_player: AudioStreamPlayer
var lbl_preview_placeholder: Label

var txt_item_prompt: TextEdit
var voice_meta_box: VBoxContainer
var txt_voice_text: LineEdit
var txt_voice_role: LineEdit
var lbl_combined_prompt: Label

var btn_generate_single: Button
var btn_pick_file: Button
var btn_mark_pending: Button
var lbl_gen_status: Label
var progress_bar: ProgressBar

func _ready() -> void:
	setup_ui()
	load_data()
	call_deferred("test_comfy_connection")

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
	row1.add_theme_constant_override("separation", 10)
	top_vbox.add_child(row1)

	var lbl_preset = Label.new()
	lbl_preset.text = "⚡ 环境:"
	row1.add_child(lbl_preset)

	opt_server_preset = OptionButton.new()
	opt_server_preset.add_item("💻 本地服务 (127.0.0.1:8188)", 0)
	opt_server_preset.add_item("🚀 远程 ComfyUI 服务", 1)
	opt_server_preset.add_item("⚙️ 自定义配置", 2)
	row1.add_child(opt_server_preset)

	var lbl_host = Label.new()
	lbl_host.text = "🔌 地址:"
	row1.add_child(lbl_host)

	txt_comfy_host = LineEdit.new()
	txt_comfy_host.custom_minimum_size = Vector2(260, 36)
	txt_comfy_host.placeholder_text = "https://..."
	row1.add_child(txt_comfy_host)

	var lbl_user = Label.new()
	lbl_user.text = "👤 账号:"
	row1.add_child(lbl_user)

	txt_comfy_user = LineEdit.new()
	txt_comfy_user.custom_minimum_size = Vector2(100, 36)
	txt_comfy_user.placeholder_text = "可选"
	row1.add_child(txt_comfy_user)

	var lbl_pass = Label.new()
	lbl_pass.text = "🔑 密码:"
	row1.add_child(lbl_pass)

	txt_comfy_pass = LineEdit.new()
	txt_comfy_pass.custom_minimum_size = Vector2(100, 36)
	txt_comfy_pass.secret = true
	txt_comfy_pass.placeholder_text = "可选"
	row1.add_child(txt_comfy_pass)

	btn_toggle_pass = Button.new()
	btn_toggle_pass.text = "👁️"
	btn_toggle_pass.tooltip_text = "显示/隐藏密码"
	btn_toggle_pass.custom_minimum_size = Vector2(36, 36)
	btn_toggle_pass.pressed.connect(func():
		txt_comfy_pass.secret = not txt_comfy_pass.secret
	)
	row1.add_child(btn_toggle_pass)

	btn_test_conn = Button.new()
	btn_test_conn.text = "测试连接"
	btn_test_conn.custom_minimum_size = Vector2(85, 36)
	btn_test_conn.pressed.connect(test_comfy_connection)
	row1.add_child(btn_test_conn)

	lbl_conn_status = Label.new()
	lbl_conn_status.text = "⚪ 未检测"
	lbl_conn_status.modulate = Color(0.7, 0.75, 0.8)
	row1.add_child(lbl_conn_status)

	var sp1 = Control.new()
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(sp1)

	var lbl_ckpt = Label.new()
	lbl_ckpt.text = "📦 底模:"
	row1.add_child(lbl_ckpt)

	opt_checkpoint = OptionButton.new()
	opt_checkpoint.custom_minimum_size = Vector2(210, 36)
	opt_checkpoint.item_selected.connect(func(idx):
		var ck = opt_checkpoint.get_item_metadata(idx)
		if ck:
			txt_checkpoint.text = ck
			ai_settings["checkpoint"] = ck
	)
	row1.add_child(opt_checkpoint)

	txt_checkpoint = LineEdit.new()
	txt_checkpoint.custom_minimum_size = Vector2(170, 36)
	txt_checkpoint.text = "sd_xl_turbo_1.0.safetensors"
	txt_checkpoint.tooltip_text = "当前选中的底模 Checkpoint 文件名"
	row1.add_child(txt_checkpoint)

	btn_save_config = Button.new()
	btn_save_config.text = "💾 保存 AI 配置"
	btn_save_config.custom_minimum_size = Vector2(115, 36)
	btn_save_config.pressed.connect(save_current_settings)
	row1.add_child(btn_save_config)

	opt_server_preset.item_selected.connect(func(idx):
		if idx == 0:
			txt_comfy_host.text = "http://127.0.0.1:8188"
			txt_comfy_user.text = ""
			txt_comfy_pass.text = ""
			save_current_settings()
			test_comfy_connection()
		elif idx == 1:
			if txt_comfy_host.text.is_empty() or txt_comfy_host.text.contains("127.0.0.1"):
				txt_comfy_host.text = "https://your-comfyui-server:8188"
			save_current_settings()
			test_comfy_connection()
	)

	# 第二行：全局风格基调、负向词与批量操作
	var row2 = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	top_vbox.add_child(row2)

	var lbl_style = Label.new()
	lbl_style.text = "🎨 风格模板:"
	row2.add_child(lbl_style)

	var opt_style_preset = OptionButton.new()
	opt_style_preset.custom_minimum_size = Vector2(190, 36)
	var p_keys = AIAssetMgr.get_style_preset_keys()
	for i in range(p_keys.size()):
		var p_key = p_keys[i]
		var preset = AIAssetMgr.get_style_preset(p_key)
		opt_style_preset.add_item(preset.get("name", p_key), i)
		opt_style_preset.set_item_metadata(i, p_key)
	row2.add_child(opt_style_preset)

	txt_global_style = LineEdit.new()
	txt_global_style.custom_minimum_size = Vector2(280, 36)
	row2.add_child(txt_global_style)

	var lbl_neg = Label.new()
	lbl_neg.text = "🚫 负向词:"
	row2.add_child(lbl_neg)

	txt_global_neg = LineEdit.new()
	txt_global_neg.custom_minimum_size = Vector2(220, 36)
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

	var sp2 = Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(sp2)

	btn_sync_manifest = Button.new()
	btn_sync_manifest.text = "🔄 扫描项目更新清单"
	btn_sync_manifest.custom_minimum_size = Vector2(160, 36)
	btn_sync_manifest.pressed.connect(sync_manifest)
	row2.add_child(btn_sync_manifest)

	btn_batch_generate = Button.new()
	btn_batch_generate.text = "⚡ 批量生成待处理素材"
	btn_batch_generate.custom_minimum_size = Vector2(180, 36)
	btn_batch_generate.modulate = Color(1.0, 0.85, 0.35)
	btn_batch_generate.pressed.connect(batch_generate_pending)
	row2.add_child(btn_batch_generate)

	# 2. 中间左右分栏工作区
	var body_split = HBoxContainer.new()
	body_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_split.add_theme_constant_override("separation", 14)
	vbox_root.add_child(body_split)

	# 左侧：素材清单列表 (420px)
	var left_panel = VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(430, 0)
	left_panel.add_theme_constant_override("separation", 8)
	body_split.add_child(left_panel)

	var filter_hbox = HBoxContainer.new()
	left_panel.add_child(filter_hbox)

	opt_filter = OptionButton.new()
	opt_filter.custom_minimum_size = Vector2(160, 34)
	opt_filter.add_item("全部素材", 0)
	opt_filter.add_item("🖼️ 场景背景", 1)
	opt_filter.add_item("👤 角色立绘", 2)
	opt_filter.add_item("🎙️ 配音音频", 3)
	opt_filter.add_item("🎵 BGM/音效", 4)
	opt_filter.add_item("⏳ 仅待生成", 5)
	opt_filter.add_item("🟢 仅已就绪", 6)
	opt_filter.item_selected.connect(func(_idx): refresh_list_view())
	filter_hbox.add_child(opt_filter)

	lbl_asset_summary = Label.new()
	lbl_asset_summary.text = "共 0 项素材"
	lbl_asset_summary.modulate = Color(0.7, 0.75, 0.85)
	filter_hbox.add_child(lbl_asset_summary)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(scroll)

	vbox_asset_list = VBoxContainer.new()
	vbox_asset_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_asset_list.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox_asset_list)

	# 右侧：单项资产实时预览与定制生成台
	var right_panel = PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r_style = StyleBoxFlat.new()
	r_style.bg_color = Color(0.08, 0.10, 0.14, 0.94)
	r_style.set_border_width_all(1)
	r_style.border_color = Color(0.3, 0.38, 0.5, 0.5)
	r_style.set_corner_radius_all(10)
	right_panel.add_theme_stylebox_override("panel", r_style)
	body_split.add_child(right_panel)

	var r_margin = MarginContainer.new()
	r_margin.add_theme_constant_override("margin_left", 20)
	r_margin.add_theme_constant_override("margin_top", 16)
	r_margin.add_theme_constant_override("margin_right", 20)
	r_margin.add_theme_constant_override("margin_bottom", 16)
	right_panel.add_child(r_margin)

	var r_vbox = VBoxContainer.new()
	r_vbox.add_theme_constant_override("separation", 12)
	r_margin.add_child(r_vbox)

	# 头部信息
	lbl_selected_title = Label.new()
	lbl_selected_title.text = "请在左侧选择素材项"
	lbl_selected_title.add_theme_font_size_override("font_size", 22)
	lbl_selected_title.modulate = Color(1.0, 0.85, 0.35)
	r_vbox.add_child(lbl_selected_title)

	var meta_row = HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 16)
	r_vbox.add_child(meta_row)

	lbl_selected_path = Label.new()
	lbl_selected_path.text = "路径: 未选择"
	lbl_selected_path.modulate = Color(0.65, 0.75, 0.85)
	meta_row.add_child(lbl_selected_path)

	lbl_selected_status = Label.new()
	lbl_selected_status.text = "状态: -"
	meta_row.add_child(lbl_selected_status)

	var sep = HSeparator.new()
	r_vbox.add_child(sep)

	# 视听预览区域
	var preview_frame = PanelContainer.new()
	preview_frame.custom_minimum_size = Vector2(0, 240)
	var pf_style = StyleBoxFlat.new()
	pf_style.bg_color = Color(0.05, 0.06, 0.09, 0.9)
	pf_style.set_border_width_all(1)
	pf_style.border_color = Color(0.25, 0.3, 0.4, 0.5)
	pf_style.set_corner_radius_all(8)
	preview_frame.add_theme_stylebox_override("panel", pf_style)
	r_vbox.add_child(preview_frame)

	var pf_center = CenterContainer.new()
	preview_frame.add_child(pf_center)

	img_preview = TextureRect.new()
	img_preview.custom_minimum_size = Vector2(400, 220)
	img_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pf_center.add_child(img_preview)

	lbl_preview_placeholder = Label.new()
	lbl_preview_placeholder.text = "🖼️ 暂无预览内容"
	lbl_preview_placeholder.modulate = Color(0.5, 0.6, 0.7)
	pf_center.add_child(lbl_preview_placeholder)

	# 音频控制器容器
	audio_preview_box = HBoxContainer.new()
	audio_preview_box.add_theme_constant_override("separation", 12)
	audio_preview_box.visible = false
	r_vbox.add_child(audio_preview_box)

	btn_audio_play = Button.new()
	btn_audio_play.text = "▶ 播放试听"
	btn_audio_play.custom_minimum_size = Vector2(110, 36)
	btn_audio_play.pressed.connect(play_audio_preview)
	audio_preview_box.add_child(btn_audio_play)

	btn_audio_stop = Button.new()
	btn_audio_stop.text = "⏹ 停止"
	btn_audio_stop.custom_minimum_size = Vector2(80, 36)
	btn_audio_stop.pressed.connect(stop_audio_preview)
	audio_preview_box.add_child(btn_audio_stop)

	lbl_audio_info = Label.new()
	lbl_audio_info.text = "准备试听"
	lbl_audio_info.modulate = Color(0.7, 0.8, 0.9)
	audio_preview_box.add_child(lbl_audio_info)

	preview_audio_player = AudioStreamPlayer.new()
	add_child(preview_audio_player)

	# 提示词与配音参数配置区
	var lbl_prompt_title = Label.new()
	lbl_prompt_title.text = "专有生成提示词 (Prompt):"
	r_vbox.add_child(lbl_prompt_title)

	txt_item_prompt = TextEdit.new()
	txt_item_prompt.custom_minimum_size = Vector2(0, 70)
	txt_item_prompt.text_changed.connect(update_combined_prompt_preview)
	r_vbox.add_child(txt_item_prompt)

	# 配音专属参数框
	voice_meta_box = VBoxContainer.new()
	voice_meta_box.visible = false
	r_vbox.add_child(voice_meta_box)

	var v_row = HBoxContainer.new()
	v_row.add_theme_constant_override("separation", 10)
	voice_meta_box.add_child(v_row)

	var lbl_vt = Label.new()
	lbl_vt.text = "台词文本:"
	v_row.add_child(lbl_vt)

	txt_voice_text = LineEdit.new()
	txt_voice_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v_row.add_child(txt_voice_text)

	var lbl_vr = Label.new()
	lbl_vr.text = "发音角色:"
	v_row.add_child(lbl_vr)

	txt_voice_role = LineEdit.new()
	txt_voice_role.custom_minimum_size = Vector2(180, 32)
	v_row.add_child(txt_voice_role)

	lbl_combined_prompt = Label.new()
	lbl_combined_prompt.text = "合成发送提示词: -"
	lbl_combined_prompt.modulate = Color(0.55, 0.65, 0.75)
	lbl_combined_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r_vbox.add_child(lbl_combined_prompt)

	# 底部操作栏
	var act_row = HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 14)
	r_vbox.add_child(act_row)

	btn_generate_single = Button.new()
	btn_generate_single.text = "🎨 单项生成 / 重新生成"
	btn_generate_single.custom_minimum_size = Vector2(200, 44)
	btn_generate_single.modulate = Color(1.0, 0.85, 0.35)
	btn_generate_single.pressed.connect(generate_current_item)
	act_row.add_child(btn_generate_single)

	btn_mark_pending = Button.new()
	btn_mark_pending.text = "🗑️ 设为待生成"
	btn_mark_pending.custom_minimum_size = Vector2(120, 44)
	btn_mark_pending.pressed.connect(mark_current_pending)
	act_row.add_child(btn_mark_pending)

	var sp_act = Control.new()
	sp_act.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act_row.add_child(sp_act)

	lbl_gen_status = Label.new()
	lbl_gen_status.text = "就绪"
	lbl_gen_status.modulate = Color(0.7, 0.8, 0.9)
	act_row.add_child(lbl_gen_status)

	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(160, 24)
	progress_bar.visible = false
	act_row.add_child(progress_bar)

# --- 数据装载与刷新 ---
func load_data() -> void:
	ai_settings = AIAssetMgr.load_ai_settings()
	txt_comfy_host.text = ai_settings.get("comfyui_server", "http://127.0.0.1:8188")
	txt_comfy_user.text = ai_settings.get("comfyui_user", "")
	txt_comfy_pass.text = ai_settings.get("comfyui_password", "")
	txt_checkpoint.text = ai_settings.get("checkpoint", "sd_xl_turbo_1.0.safetensors")
	txt_global_style.text = ai_settings.get("global_style_prompt", "")
	txt_global_neg.text = ai_settings.get("global_negative_prompt", "")

	if txt_comfy_host.text.contains("127.0.0.1") or txt_comfy_host.text.contains("localhost"):
		opt_server_preset.selected = 0
	elif not txt_comfy_host.text.is_empty():
		opt_server_preset.selected = 1
	else:
		opt_server_preset.selected = 2

	manifest_items = AIAssetMgr.load_manifest()
	if manifest_items.is_empty():
		manifest_items = AIAssetMgr.sync_manifest_with_project()
	refresh_list_view()

func save_current_settings() -> void:
	ai_settings["comfyui_server"] = txt_comfy_host.text.strip_edges()
	ai_settings["comfyui_user"] = txt_comfy_user.text.strip_edges()
	ai_settings["comfyui_password"] = txt_comfy_pass.text.strip_edges()
	ai_settings["checkpoint"] = txt_checkpoint.text.strip_edges()
	ai_settings["global_style_prompt"] = txt_global_style.text.strip_edges()
	ai_settings["global_negative_prompt"] = txt_global_neg.text.strip_edges()
	AIAssetMgr.save_ai_settings(ai_settings)
	lbl_gen_status.text = "AI 设置已保存！"

func sync_manifest() -> void:
	manifest_items = AIAssetMgr.sync_manifest_with_project()
	refresh_list_view()
	lbl_gen_status.text = "已扫描并同步项目资产清单！"

func refresh_list_view() -> void:
	for child in vbox_asset_list.get_children():
		child.queue_free()

	var filter_idx = opt_filter.selected
	var ready_count = 0
	var pending_count = 0

	for item in manifest_items:
		var itype = item.get("type", "")
		var istatus = item.get("status", "pending")
		if istatus == "ready":
			ready_count += 1
		else:
			pending_count += 1

		# 过滤匹配
		var matched = true
		match filter_idx:
			1: matched = (itype == "background")
			2: matched = (itype == "character")
			3: matched = (itype == "voice")
			4: matched = (itype in ["bgm", "sfx"])
			5: matched = (istatus == "pending")
			6: matched = (istatus == "ready")
			_: matched = true

		if not matched:
			continue

		var iid = item.get("id", "")
		var iname = item.get("name", iid)
		var type_prefix = get_type_badge(itype)

		var btn = Button.new()
		var status_str = "🟢" if istatus == "ready" else "⏳"
		btn.text = " %s %s %s" % [status_str, type_prefix, iname]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 42)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		var is_sel = (iid == selected_item_id)
		style_item_button(btn, is_sel, istatus == "ready")

		btn.pressed.connect(func():
			select_item(iid)
		)
		vbox_asset_list.add_child(btn)

	lbl_asset_summary.text = "共 %d 项 (就绪: %d, 待生成: %d)" % [manifest_items.size(), ready_count, pending_count]
	
	if not selected_item_id.is_empty():
		select_item(selected_item_id)
	elif manifest_items.size() > 0:
		select_item(manifest_items[0].get("id", ""))

func get_type_badge(itype: String) -> String:
	match itype:
		"background": return "[背景]"
		"character": return "[立绘]"
		"voice": return "[配音]"
		"bgm": return "[BGM]"
		"sfx": return "[音效]"
		_: return "[素材]"

func style_item_button(btn: Button, is_selected: bool, is_ready: bool) -> void:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.23, 0.33, 0.95) if is_selected else Color(0.10, 0.13, 0.18, 0.85)
	sb.set_border_width_all(2 if is_selected else 1)
	sb.border_color = Color(1.0, 0.85, 0.35, 1.0) if is_selected else (Color(0.3, 0.75, 0.45, 0.5) if is_ready else Color(0.8, 0.55, 0.25, 0.5))
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	btn.add_theme_stylebox_override("normal", sb)

func select_item(item_id: String) -> void:
	selected_item_id = item_id
	var item = get_item_by_id(item_id)
	if item.is_empty():
		return

	var itype = item.get("type", "")
	var istatus = item.get("status", "pending")
	var lpath = item.get("local_path", "")

	lbl_selected_title.text = "%s %s" % [get_type_badge(itype), item.get("name", item_id)]
	lbl_selected_path.text = "目标文件: " + lpath
	lbl_selected_status.text = "状态: " + ("🟢 已就绪" if istatus == "ready" else "⏳ 待生成")
	lbl_selected_status.modulate = Color(0.4, 0.9, 0.5) if istatus == "ready" else Color(1.0, 0.6, 0.3)

	txt_item_prompt.text = item.get("prompt", "")
	update_combined_prompt_preview()

	# 区分图像与音频预览
	stop_audio_preview()
	if itype in ["background", "character"]:
		audio_preview_box.visible = false
		voice_meta_box.visible = false
		load_image_preview(lpath)
	elif itype in ["voice", "bgm", "sfx"]:
		img_preview.texture = null
		img_preview.visible = false
		lbl_preview_placeholder.visible = false
		audio_preview_box.visible = true
		voice_meta_box.visible = (itype == "voice")
		if itype == "voice":
			txt_voice_text.text = item.get("text", "")
			txt_voice_role.text = item.get("voice_role", "zh-CN-XiaoxiaoNeural")
		lbl_audio_info.text = "准备试听: " + lpath.get_file()

func get_item_by_id(item_id: String) -> Dictionary:
	for it in manifest_items:
		if it.get("id", "") == item_id:
			return it
	return {}

func update_combined_prompt_preview() -> void:
	var global_style = txt_global_style.text.strip_edges()
	var item_prompt = txt_item_prompt.text.strip_edges()
	lbl_combined_prompt.text = "合成发送提示词: " + global_style + ", " + item_prompt

func load_image_preview(lpath: String) -> void:
	img_preview.visible = true
	var abs_path = ProjectSettings.globalize_path(lpath)
	if FileAccess.file_exists(abs_path):
		var img = Image.new()
		var err = img.load(abs_path)
		if err == OK:
			img_preview.texture = ImageTexture.create_from_image(img)
			lbl_preview_placeholder.visible = false
			return

	img_preview.texture = null
	lbl_preview_placeholder.text = "🖼️ 暂无图片预览 (文件尚未生成)"
	lbl_preview_placeholder.visible = true

func play_audio_preview() -> void:
	var item = get_item_by_id(selected_item_id)
	if item.is_empty():
		return
	var lpath = item.get("local_path", "")
	var abs_path = ProjectSettings.globalize_path(lpath)
	if not FileAccess.file_exists(abs_path):
		lbl_audio_info.text = "⚠️ 文件不存在，尚未生成！"
		return

	if lpath.ends_with(".mp3"):
		var mp3 = AudioStreamMP3.new()
		var f = FileAccess.open(abs_path, FileAccess.READ)
		if f:
			mp3.data = f.get_buffer(f.get_length())
			preview_audio_player.stream = mp3
			preview_audio_player.play()
			lbl_audio_info.text = "正在播放: " + lpath.get_file()
	elif lpath.ends_with(".wav"):
		var wav = AudioStreamWAV.new()
		var f = FileAccess.open(abs_path, FileAccess.READ)
		if f:
			wav.data = f.get_buffer(f.get_length())
			preview_audio_player.stream = wav
			preview_audio_player.play()
			lbl_audio_info.text = "正在播放: " + lpath.get_file()

func stop_audio_preview() -> void:
	if preview_audio_player.playing:
		preview_audio_player.stop()
		lbl_audio_info.text = "已停止播放"

# --- ComfyUI 服务探测 ---
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
		lbl_conn_status.text = "🟢 已连接 (%s, 空闲: %d MB)" % [gpu, vram_free_mb]
		lbl_conn_status.modulate = Color(0.3, 0.9, 0.4)
		
		# 自动填充可用的底模列表
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

# --- 单项生成与批量生成 ---
func generate_current_item() -> void:
	var item = get_item_by_id(selected_item_id)
	if item.is_empty():
		return

	# 保存针对该项修改的 prompt
	item["prompt"] = txt_item_prompt.text.strip_edges()
	if item.get("type", "") == "voice":
		item["text"] = txt_voice_text.text.strip_edges()
		item["voice_role"] = txt_voice_role.text.strip_edges()
	AIAssetMgr.save_manifest(manifest_items)

	lbl_gen_status.text = "正在生成: " + item.get("name", "") + "..."
	btn_generate_single.disabled = true

	# 保存设置并执行
	save_current_settings()
	var res = AIAssetMgr.generate_asset_item(item, ai_settings)

	btn_generate_single.disabled = false
	if res.get("success", false):
		item["status"] = "ready"
		AIAssetMgr.save_manifest(manifest_items)
		lbl_gen_status.text = "✅ 生成成功: " + item.get("name", "")
		select_item(selected_item_id)
		refresh_list_view()
	else:
		lbl_gen_status.text = "❌ 生成失败: " + res.get("error", "未知错误")

func mark_current_pending() -> void:
	var item = get_item_by_id(selected_item_id)
	if item.is_empty():
		return
	item["status"] = "pending"
	AIAssetMgr.save_manifest(manifest_items)
	select_item(selected_item_id)
	refresh_list_view()

func batch_generate_pending() -> void:
	save_current_settings()
	var pending_list = []
	for it in manifest_items:
		if it.get("status", "pending") == "pending":
			pending_list.append(it)

	if pending_list.is_empty():
		lbl_gen_status.text = "所有素材已全部生成完毕，无需批量生成！"
		return

	btn_batch_generate.disabled = true
	progress_bar.visible = true
	progress_bar.max_value = pending_list.size()
	progress_bar.value = 0

	var idx = 0
	for it in pending_list:
		idx += 1
		lbl_gen_status.text = "批量生成中 [%d/%d]: %s" % [idx, pending_list.size(), it.get("name", "")]
		progress_bar.value = idx - 1
		
		var res = AIAssetMgr.generate_asset_item(it, ai_settings)
		if res.get("success", false):
			it["status"] = "ready"
		progress_bar.value = idx

	AIAssetMgr.save_manifest(manifest_items)
	btn_batch_generate.disabled = false
	progress_bar.visible = false
	lbl_gen_status.text = "✅ 批量生成完成！共处理 %d 项素材。" % pending_list.size()
	refresh_list_view()
