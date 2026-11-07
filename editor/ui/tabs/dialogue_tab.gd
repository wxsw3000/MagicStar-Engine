# editor/ui/tabs/dialogue_tab.gd
# 剧本台词与 NPC 盘问话题池编辑器：支持就地表情立绘差分选用、单句与本幕批量 TTS 配音生成与试听
class_name DialogueTab
extends Control

const AIAssetMgr = preload("res://editor/core/ai_asset_manager.gd")

var current_dialogue_id: String = ""
var current_dialogue_data: Dictionary = {}

var script_list: ItemList
var lines_container: VBoxContainer
var edit_diag_id: LineEdit
var opt_dialogue_type: OptionButton

var btn_add_line: Button
var btn_batch_voice: Button
var btn_save: Button
var lbl_batch_status: Label

var preview_audio_player: AudioStreamPlayer

# 常用预设表情差分列表
const STANDARD_EXPRESSIONS = [
	{"id": "normal", "label": "平常 / 默认 (normal)"},
	{"id": "confident", "label": "自信 / 坚定 (confident)"},
	{"id": "nervous", "label": "紧张 / 动摇 (nervous)"},
	{"id": "thinking", "label": "深思 / 沉吟 (thinking)"},
	{"id": "shocked", "label": "震惊 / 骇然 (shocked)"},
	{"id": "angry", "label": "愤怒 / 质问 (angry)"},
	{"id": "sad", "label": "悲伤 / 沮丧 (sad)"},
	{"id": "smiling", "label": "微笑 / 从容 (smiling)"}
]

func _ready() -> void:
	setup_audio_player()
	setup_ui()
	refresh_dialogue_list()

func setup_audio_player() -> void:
	preview_audio_player = AudioStreamPlayer.new()
	add_child(preview_audio_player)

# --- 实体按钮统一样式规范 (与 AI 资产工坊保持 100% 视觉质感一致) ---
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
	
	sb_normal.content_margin_left = 10
	sb_normal.content_margin_right = 10
	sb_normal.content_margin_top = 4
	sb_normal.content_margin_bottom = 4
	sb_hover.content_margin_left = 10
	sb_hover.content_margin_right = 10
	sb_hover.content_margin_top = 4
	sb_hover.content_margin_bottom = 4
	sb_pressed.content_margin_left = 10
	sb_pressed.content_margin_right = 10
	sb_pressed.content_margin_top = 4
	sb_pressed.content_margin_bottom = 4

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

func setup_ui() -> void:
	var hsplit = HSplitContainer.new()
	hsplit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hsplit)
	
	# 左侧: 剧本列表
	var left_panel = VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(240, 0)
	hsplit.add_child(left_panel)
	
	var lbl_list = Label.new()
	lbl_list.text = "📜 剧情对话列表"
	lbl_list.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_panel.add_child(lbl_list)
	
	script_list = ItemList.new()
	script_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	script_list.item_selected.connect(_on_dialogue_selected)
	left_panel.add_child(script_list)
	
	var btn_add = Button.new()
	btn_add.text = "➕ 新增对白剧本"
	style_button(btn_add, "create")
	btn_add.pressed.connect(_on_add_dialogue_pressed)
	left_panel.add_child(btn_add)
	
	# 右侧: 台词流编辑器
	var right_panel = VBoxContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.add_theme_constant_override("separation", 8)
	hsplit.add_child(right_panel)
	
	# 顶部工具栏 (PanelContainer 装饰)
	var toolbar_panel = PanelContainer.new()
	var tb_style = StyleBoxFlat.new()
	tb_style.bg_color = Color(0.08, 0.10, 0.15, 0.95)
	tb_style.set_border_width_all(1)
	tb_style.border_color = Color(0.25, 0.32, 0.45, 0.6)
	tb_style.set_corner_radius_all(6)
	toolbar_panel.add_theme_stylebox_override("panel", tb_style)
	right_panel.add_child(toolbar_panel)

	var tb_margin = MarginContainer.new()
	tb_margin.add_theme_constant_override("margin_left", 10)
	tb_margin.add_theme_constant_override("margin_right", 10)
	tb_margin.add_theme_constant_override("margin_top", 6)
	tb_margin.add_theme_constant_override("margin_bottom", 6)
	toolbar_panel.add_child(tb_margin)

	var toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 10)
	tb_margin.add_child(toolbar)
	
	var lbl_id = Label.new()
	lbl_id.text = "剧本 ID: "
	toolbar.add_child(lbl_id)
	edit_diag_id = LineEdit.new()
	edit_diag_id.editable = false
	edit_diag_id.custom_minimum_size = Vector2(160, 32)
	toolbar.add_child(edit_diag_id)
	
	var sep1 = VSeparator.new()
	toolbar.add_child(sep1)
	
	btn_add_line = Button.new()
	btn_add_line.text = "➕ 添加一句对白"
	btn_add_line.custom_minimum_size = Vector2(130, 32)
	style_button(btn_add_line, "create")
	btn_add_line.pressed.connect(_on_add_line_pressed)
	toolbar.add_child(btn_add_line)
	
	btn_batch_voice = Button.new()
	btn_batch_voice.text = "⚡ 批量生成本幕全部配音"
	btn_batch_voice.custom_minimum_size = Vector2(190, 32)
	style_button(btn_batch_voice, "batch")
	btn_batch_voice.pressed.connect(_on_batch_generate_dialogue_voices)
	toolbar.add_child(btn_batch_voice)

	lbl_batch_status = Label.new()
	lbl_batch_status.text = ""
	lbl_batch_status.modulate = Color(0.7, 0.85, 1.0)
	toolbar.add_child(lbl_batch_status)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	btn_save = Button.new()
	btn_save.text = "💾 保存剧本配置"
	btn_save.custom_minimum_size = Vector2(120, 32)
	style_button(btn_save, "action")
	btn_save.pressed.connect(save_current_dialogue)
	toolbar.add_child(btn_save)
	
	# 台词卡片滚动列表
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(scroll)
	
	lines_container = VBoxContainer.new()
	lines_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines_container.add_theme_constant_override("separation", 10)
	scroll.add_child(lines_container)

func refresh_dialogue_list() -> void:
	script_list.clear()
	for d_id in DataManager.dialogues:
		script_list.add_item(d_id)
	if script_list.item_count > 0:
		script_list.select(0)
		_on_dialogue_selected(0)

func _on_dialogue_selected(index: int) -> void:
	var keys = DataManager.dialogues.keys()
	if index >= 0 and index < keys.size():
		load_dialogue(keys[index])

func load_dialogue(dialogue_id: String) -> void:
	current_dialogue_id = dialogue_id
	current_dialogue_data = DataManager.dialogues.get(dialogue_id, {}).duplicate(true)
	edit_diag_id.text = dialogue_id
	lbl_batch_status.text = ""
	render_lines()

func render_lines() -> void:
	for child in lines_container.get_children():
		child.queue_free()
		
	var lines = current_dialogue_data.get("lines", [])
	var ready_voice_cnt = 0
	for i in range(lines.size()):
		var line = lines[i]
		var vpath = get_resolved_voice_path(current_dialogue_id, i, line)
		if is_voice_ready(vpath):
			ready_voice_cnt += 1
		var card = create_line_card(i, line)
		lines_container.add_child(card)
		
	if lines.size() > 0:
		lbl_batch_status.text = "配音就绪状态: %d / %d 句" % [ready_voice_cnt, lines.size()]
	else:
		lbl_batch_status.text = "当前剧本暂无台词"

# --- 声音与立绘辅助方法 ---

func get_resolved_voice_path(d_id: String, index: int, line_data: Dictionary) -> String:
	var existing = line_data.get("voice", "")
	if not existing.is_empty():
		return existing
	var pdir = ProjectContext.active_project_dir
	if pdir.is_empty():
		pdir = "res://projects/case_gallery_rain/"
	if not pdir.ends_with("/"):
		pdir += "/"
	var vid = "voice_%s_%d" % [d_id, index + 1]
	return pdir + "assets/audio/voice/" + vid + ".mp3"

func is_voice_ready(vpath: String) -> bool:
	if vpath.is_empty():
		return false
	var abs_p = ProjectSettings.globalize_path(vpath)
	return FileAccess.file_exists(vpath) or FileAccess.file_exists(abs_p)

func play_audio_file(vpath: String) -> void:
	var abs_path = ProjectSettings.globalize_path(vpath)
	if not FileAccess.file_exists(abs_path) and not FileAccess.file_exists(vpath):
		lbl_batch_status.text = "⚠️ 该配音文件尚未生成，无法播放！"
		return
		
	if preview_audio_player.playing:
		preview_audio_player.stop()

	if vpath.ends_with(".mp3"):
		var mp3 = AudioStreamMP3.new()
		var f = FileAccess.open(abs_path, FileAccess.READ)
		if f:
			mp3.data = f.get_buffer(f.get_length())
			preview_audio_player.stream = mp3
			preview_audio_player.play()
			lbl_batch_status.text = "正在试听: " + vpath.get_file()
	elif vpath.ends_with(".wav"):
		var wav = AudioStreamWAV.new()
		var f = FileAccess.open(abs_path, FileAccess.READ)
		if f:
			wav.data = f.get_buffer(f.get_length())
			preview_audio_player.stream = wav
			preview_audio_player.play()
			lbl_batch_status.text = "正在试听: " + vpath.get_file()

func get_all_speaker_names() -> Array:
	var list = ["旁白"]
	for cid in DataManager.characters:
		var c = DataManager.characters[cid]
		var cname = c.get("name", cid)
		if not list.has(cname):
			list.append(cname)
	return list

# --- 台词卡片渲染 ---

func create_line_card(index: int, line_data: Dictionary) -> PanelContainer:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var c_style = StyleBoxFlat.new()
	c_style.bg_color = Color(0.08, 0.10, 0.15, 0.95)
	c_style.set_border_width_all(1)
	c_style.border_color = Color(0.20, 0.27, 0.38, 0.7)
	c_style.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", c_style)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	
	# 卡片顶栏: 序号 + 说话人 + 立绘表情差分选择 + 配音操作 + 顺序/删除
	var top_row = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	vbox.add_child(top_row)
	
	var lbl_idx = Label.new()
	lbl_idx.text = "#%d" % (index + 1)
	lbl_idx.modulate = Color(0.65, 0.75, 0.85)
	top_row.add_child(lbl_idx)
	
	var lbl_spk = Label.new()
	lbl_spk.text = "说话人:"
	top_row.add_child(lbl_spk)
	
	var opt_speaker = OptionButton.new()
	opt_speaker.custom_minimum_size = Vector2(110, 30)
	var speakers = get_all_speaker_names()
	var current_spk = line_data.get("speaker", "旁白")
	var spk_found = false
	for s_i in range(speakers.size()):
		opt_speaker.add_item(speakers[s_i], s_i)
		if speakers[s_i] == current_spk:
			opt_speaker.select(s_i)
			spk_found = true
	if not spk_found:
		opt_speaker.add_item(current_spk, speakers.size())
		opt_speaker.select(speakers.size())
	top_row.add_child(opt_speaker)
	
	var edit_spk = LineEdit.new()
	edit_spk.text = current_spk
	edit_spk.custom_minimum_size = Vector2(90, 30)
	top_row.add_child(edit_spk)

	# 2. 立绘表情差分选用下拉框 (Task 3 核心支持)
	var lbl_expr = Label.new()
	lbl_expr.text = "🎨 立绘表情:"
	top_row.add_child(lbl_expr)

	var opt_expr = OptionButton.new()
	opt_expr.custom_minimum_size = Vector2(170, 30)
	top_row.add_child(opt_expr)

	var cur_expr = line_data.get("expression", "normal")
	for e_i in range(STANDARD_EXPRESSIONS.size()):
		var expr_def = STANDARD_EXPRESSIONS[e_i]
		opt_expr.add_item(expr_def["label"], e_i)
		opt_expr.set_item_metadata(e_i, expr_def["id"])
		if expr_def["id"] == cur_expr:
			opt_expr.select(e_i)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)
	
	var btn_up = Button.new()
	btn_up.text = "⬆"
	btn_up.custom_minimum_size = Vector2(32, 30)
	style_button(btn_up, "secondary")
	btn_up.disabled = (index == 0)
	btn_up.pressed.connect(func(): move_line(index, -1))
	top_row.add_child(btn_up)
	
	var btn_down = Button.new()
	btn_down.text = "⬇"
	btn_down.custom_minimum_size = Vector2(32, 30)
	style_button(btn_down, "secondary")
	btn_down.disabled = (index == current_dialogue_data.get("lines", []).size() - 1)
	btn_down.pressed.connect(func(): move_line(index, 1))
	top_row.add_child(btn_down)
	
	var btn_del = Button.new()
	btn_del.text = "✕"
	btn_del.custom_minimum_size = Vector2(32, 30)
	style_button(btn_del, "secondary")
	btn_del.modulate = Color(1.0, 0.5, 0.5)
	btn_del.pressed.connect(func(): delete_line(index))
	top_row.add_child(btn_del)

	# 2. 独立配音与试听专属功能栏 (极醒目、绝对防截断，支持就地即时配音与音频播放)
	var vpath = get_resolved_voice_path(current_dialogue_id, index, line_data)
	var ready = is_voice_ready(vpath)

	var voice_panel = PanelContainer.new()
	var vp_style = StyleBoxFlat.new()
	vp_style.bg_color = Color(0.06, 0.08, 0.12, 0.95)
	vp_style.set_border_width_all(1)
	vp_style.border_color = Color(0.25, 0.35, 0.5, 0.6)
	vp_style.set_corner_radius_all(6)
	voice_panel.add_theme_stylebox_override("panel", vp_style)
	vbox.add_child(voice_panel)

	var vp_margin = MarginContainer.new()
	vp_margin.add_theme_constant_override("margin_left", 10)
	vp_margin.add_theme_constant_override("margin_right", 10)
	vp_margin.add_theme_constant_override("margin_top", 4)
	vp_margin.add_theme_constant_override("margin_bottom", 4)
	voice_panel.add_child(vp_margin)

	var voice_row = HBoxContainer.new()
	voice_row.add_theme_constant_override("separation", 10)
	vp_margin.add_child(voice_row)

	var lbl_v_head = Label.new()
	lbl_v_head.text = "🎙️ 角色配音:"
	lbl_v_head.modulate = Color(1.0, 0.85, 0.45)
	voice_row.add_child(lbl_v_head)

	var lbl_v_status = Label.new()
	lbl_v_status.text = "🟢 [配音已就绪]" if ready else "⚪ [尚未生成配音]"
	lbl_v_status.modulate = Color(0.4, 0.95, 0.6) if ready else Color(0.7, 0.75, 0.8)
	voice_row.add_child(lbl_v_status)

	var btn_play = Button.new()
	btn_play.text = "▶ 试听配音"
	btn_play.custom_minimum_size = Vector2(90, 30)
	style_button(btn_play, "action")
	btn_play.disabled = not ready
	btn_play.pressed.connect(func():
		var cur_path = get_resolved_voice_path(current_dialogue_id, index, line_data)
		play_audio_file(cur_path)
	)
	voice_row.add_child(btn_play)

	var btn_gen = Button.new()
	btn_gen.text = "🎙️ 生成本句配音"
	btn_gen.custom_minimum_size = Vector2(120, 30)
	style_button(btn_gen, "create")
	voice_row.add_child(btn_gen)

	var v_sp = Control.new()
	v_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voice_row.add_child(v_sp)

	var lbl_file_hint = Label.new()
	var role_name = AIAssetMgr.deduce_voice_role(current_spk)
	lbl_file_hint.text = "文件: %s | 声线: %s" % [vpath.get_file(), role_name]
	lbl_file_hint.modulate = Color(0.5, 0.62, 0.75)
	lbl_file_hint.add_theme_font_size_override("font_size", 12)
	voice_row.add_child(lbl_file_hint)
	
	# 台词文本
	var edit_content = TextEdit.new()
	edit_content.text = line_data.get("text", "")
	edit_content.custom_minimum_size = Vector2(0, 60)
	edit_content.text_changed.connect(func():
		line_data["text"] = edit_content.text
	)
	vbox.add_child(edit_content)

	# 底部资产绑定详情信息行
	var info_row = HBoxContainer.new()
	vbox.add_child(info_row)

	var lbl_detail = Label.new()
	var char_img_show = line_data.get("character_image", "无/旁白")
	if char_img_show.is_empty() and edit_spk.text != "旁白":
		char_img_show = "(待匹配立绘)"
	lbl_detail.text = "📁 立绘路径: %s  |  🎙️ 配音文件: %s" % [char_img_show.get_file() if char_img_show.contains("/") else char_img_show, vpath.get_file()]
	lbl_detail.modulate = Color(0.5, 0.62, 0.75)
	info_row.add_child(lbl_detail)

	# 说话人选择与手填同步
	opt_speaker.item_selected.connect(func(s_idx):
		var spk_text = opt_speaker.get_item_text(s_idx)
		edit_spk.text = spk_text
		line_data["speaker"] = spk_text
		update_line_character_and_voice(line_data, index, lbl_detail, btn_play, lbl_v_status)
	)

	edit_spk.text_changed.connect(func(new_text):
		line_data["speaker"] = new_text
		update_line_character_and_voice(line_data, index, lbl_detail, btn_play, lbl_v_status)
	)

	# 立绘表情差分选择响应
	opt_expr.item_selected.connect(func(e_idx):
		var expr_id = opt_expr.get_item_metadata(e_idx)
		if expr_id:
			line_data["expression"] = expr_id
			update_line_character_and_voice(line_data, index, lbl_detail, btn_play, lbl_v_status)
	)

	# 单句配音生成按钮响应
	btn_gen.pressed.connect(func():
		generate_single_voice_for_line(index, line_data, btn_gen, btn_play, lbl_v_status, lbl_detail)
	)
	
	return card

func update_line_character_and_voice(line_data: Dictionary, index: int, lbl_detail: Label, btn_play: Button, lbl_v_status: Label) -> void:
	var speaker = line_data.get("speaker", "旁白").strip_edges()
	var expr = line_data.get("expression", "normal")
	if speaker == "旁白" or speaker.is_empty():
		line_data["character_image"] = ""
	else:
		var char_ent_id = AIAssetMgr.deduce_character_entity_id(speaker)
		var portrait = ProjectContext.get_character_portrait(char_ent_id, expr)
		if portrait.is_empty():
			portrait = ProjectContext.get_character_portrait(speaker, expr)
		line_data["character_image"] = portrait

	var cur_vpath = get_resolved_voice_path(current_dialogue_id, index, line_data)
	line_data["voice"] = cur_vpath
	var ready = is_voice_ready(cur_vpath)
	btn_play.disabled = not ready
	lbl_v_status.text = "🟢 [配音已就绪]" if ready else "⚪ [尚未生成配音]"
	lbl_v_status.modulate = Color(0.4, 0.95, 0.6) if ready else Color(0.7, 0.75, 0.8)
	
	var char_show = line_data.get("character_image", "无/旁白")
	lbl_detail.text = "📁 立绘路径: %s  |  🎙️ 配音文件: %s" % [char_show.get_file() if char_show.contains("/") else char_show, cur_vpath.get_file()]

# --- 单句生成与批量生成实现 ---

func generate_single_voice_for_line(index: int, line_data: Dictionary, btn_gen: Button, btn_play: Button, lbl_v_status: Label, lbl_detail: Label) -> void:
	var text = line_data.get("text", "").strip_edges()
	if text.is_empty():
		lbl_batch_status.text = "⚠️ 台词文本为空，无法生成配音！"
		return

	var vpath = get_resolved_voice_path(current_dialogue_id, index, line_data)
	line_data["voice"] = vpath
	var speaker = line_data.get("speaker", "旁白")
	var voice_role = AIAssetMgr.deduce_voice_role(speaker)
	var emotion = line_data.get("expression", "normal")
	
	var item = {
		"id": vpath.get_file().get_basename(),
		"type": "voice",
		"text": text,
		"voice_role": voice_role,
		"emotion": emotion,
		"local_path": vpath
	}

	btn_gen.disabled = true
	lbl_v_status.text = "⏳ 生成中..."
	lbl_v_status.modulate = Color(1.0, 0.85, 0.3)
	lbl_batch_status.text = "🎙️ 正在为第 %d 句台词生成配音..." % (index + 1)

	var settings = AIAssetMgr.load_ai_settings()
	var res = AIAssetMgr.generate_asset_item(item, settings)

	btn_gen.disabled = false
	if res.get("success", false):
		lbl_v_status.text = "🟢 [配音已就绪]"
		lbl_v_status.modulate = Color(0.4, 0.95, 0.6)
		btn_play.disabled = false
		lbl_batch_status.text = "✅ 第 %d 句台词配音生成成功！" % (index + 1)
		save_current_dialogue()
		AIAssetMgr.sync_manifest_with_project()
		update_line_character_and_voice(line_data, index, lbl_detail, btn_play, lbl_v_status)
	else:
		lbl_v_status.text = "❌ 失败"
		lbl_v_status.modulate = Color(1.0, 0.4, 0.4)
		lbl_batch_status.text = "❌ 生成失败: " + res.get("error", "未知错误")

func _on_batch_generate_dialogue_voices() -> void:
	if current_dialogue_id.is_empty():
		return
	var lines = current_dialogue_data.get("lines", [])
	if lines.is_empty():
		lbl_batch_status.text = "⚠️ 当前剧本没有任何台词！"
		return

	btn_batch_voice.disabled = true
	var settings = AIAssetMgr.load_ai_settings()
	var total = lines.size()
	var success_cnt = 0
	
	for i in range(total):
		var line = lines[i]
		var text = line.get("text", "").strip_edges()
		if text.is_empty():
			continue
		var vpath = get_resolved_voice_path(current_dialogue_id, i, line)
		line["voice"] = vpath
		var speaker = line.get("speaker", "旁白")
		var voice_role = AIAssetMgr.deduce_voice_role(speaker)
		var emotion = line.get("expression", "normal")
		
		lbl_batch_status.text = "⚡ 正在批量生成本幕配音 (%d/%d)..." % [i + 1, total]
		
		var item = {
			"id": vpath.get_file().get_basename(),
			"type": "voice",
			"text": text,
			"voice_role": voice_role,
			"emotion": emotion,
			"local_path": vpath
		}
		var res = AIAssetMgr.generate_asset_item(item, settings)
		if res.get("success", false):
			success_cnt += 1

	btn_batch_voice.disabled = false
	save_current_dialogue()
	AIAssetMgr.sync_manifest_with_project()
	render_lines()
	lbl_batch_status.text = "🎉 本幕批量配音完成！成功生成 %d / %d 句" % [success_cnt, total]

# --- 增删移动与基础存储 ---

func _on_add_line_pressed() -> void:
	if current_dialogue_id.is_empty():
		return
	if not current_dialogue_data.has("lines"):
		current_dialogue_data["lines"] = []
	var new_line = {
		"speaker": "沈策",
		"expression": "normal",
		"text": "请输入台词内容..."
	}
	current_dialogue_data["lines"].append(new_line)
	render_lines()

func move_line(index: int, dir: int) -> void:
	var lines = current_dialogue_data.get("lines", [])
	var target = index + dir
	if target >= 0 and target < lines.size():
		var temp = lines[index]
		lines[index] = lines[target]
		lines[target] = temp
		render_lines()

func delete_line(index: int) -> void:
	var lines = current_dialogue_data.get("lines", [])
	if index >= 0 and index < lines.size():
		lines.remove_at(index)
		render_lines()

func save_current_dialogue() -> void:
	if current_dialogue_id.is_empty():
		return
	DataManager.save_item("dialogues", current_dialogue_id, current_dialogue_data)
	lbl_batch_status.text = "💾 剧本数据已成功保存"

func _on_add_dialogue_pressed() -> void:
	var dialog = ConfirmationDialog.new()
	dialog.title = "新建剧本"
	dialog.size = Vector2(320, 160)
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	vbox.add_child(Label.new())
	(vbox.get_child(0) as Label).text = "剧本 ID (如 diag_hall_investigate):"
	var e_id = LineEdit.new()
	e_id.text = "diag_" + str(Time.get_ticks_msec()).substr(0, 4)
	vbox.add_child(e_id)
	
	dialog.confirmed.connect(func():
		var did = e_id.text.strip_edges()
		if not did.is_empty():
			var d_data = {
				"id": did,
				"lines": [
					{"speaker": "旁白", "expression": "normal", "text": "开始新的对话..."}
				]
			}
			DataManager.save_item("dialogues", did, d_data)
			refresh_dialogue_list()
			load_dialogue(did)
	)
	add_child(dialog)
	dialog.popup_centered()
