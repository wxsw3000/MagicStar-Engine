# editor/ui/tabs/dialogue_tab.gd
# 剧本台词与 NPC 盘问话题池编辑器
class_name DialogueTab
extends Control

var current_dialogue_id: String = ""
var current_dialogue_data: Dictionary = {}

var script_list: ItemList
var lines_container: VBoxContainer
var edit_diag_id: LineEdit
var opt_dialogue_type: OptionButton

func _ready() -> void:
	setup_ui()
	refresh_dialogue_list()

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
	btn_add.pressed.connect(_on_add_dialogue_pressed)
	left_panel.add_child(btn_add)
	
	# 右侧: 台词流编辑器
	var right_panel = VBoxContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_child(right_panel)
	
	# 顶部工具栏
	var toolbar = HBoxContainer.new()
	toolbar.custom_minimum_size = Vector2(0, 40)
	right_panel.add_child(toolbar)
	
	var lbl_id = Label.new()
	lbl_id.text = "剧本 ID: "
	toolbar.add_child(lbl_id)
	edit_diag_id = LineEdit.new()
	edit_diag_id.editable = false
	edit_diag_id.custom_minimum_size = Vector2(180, 0)
	toolbar.add_child(edit_diag_id)
	
	var sep1 = VSeparator.new()
	toolbar.add_child(sep1)
	
	var btn_add_line = Button.new()
	btn_add_line.text = "➕ 添加一句对白"
	btn_add_line.pressed.connect(_on_add_line_pressed)
	toolbar.add_child(btn_add_line)
	
	var btn_save = Button.new()
	btn_save.text = "💾 保存剧本配置"
	btn_save.pressed.connect(save_current_dialogue)
	toolbar.add_child(btn_save)
	
	# 台词卡片滚动列表
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(scroll)
	
	lines_container = VBoxContainer.new()
	lines_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	render_lines()

func render_lines() -> void:
	for child in lines_container.get_children():
		child.queue_free()
		
	var lines = current_dialogue_data.get("lines", [])
	for i in range(lines.size()):
		var line = lines[i]
		var card = create_line_card(i, line)
		lines_container.add_child(card)

func create_line_card(index: int, line_data: Dictionary) -> PanelContainer:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)
	
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	# 卡片顶栏: 序号 + 说话人 + 顺序调整
	var top_row = HBoxContainer.new()
	vbox.add_child(top_row)
	
	var lbl_idx = Label.new()
	lbl_idx.text = "#%d" % (index + 1)
	lbl_idx.modulate = Color(0.7, 0.7, 0.7)
	top_row.add_child(lbl_idx)
	
	var lbl_spk = Label.new()
	lbl_spk.text = "说话人:"
	top_row.add_child(lbl_spk)
	var edit_spk = LineEdit.new()
	edit_spk.text = line_data.get("speaker", "旁白")
	edit_spk.text_changed.connect(func(new_text): line_data["speaker"] = new_text)
	top_row.add_child(edit_spk)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)
	
	var btn_up = Button.new()
	btn_up.text = "⬆"
	btn_up.disabled = (index == 0)
	btn_up.pressed.connect(func(): move_line(index, -1))
	top_row.add_child(btn_up)
	
	var btn_down = Button.new()
	btn_down.text = "⬇"
	btn_down.disabled = (index == current_dialogue_data.get("lines", []).size() - 1)
	btn_down.pressed.connect(func(): move_line(index, 1))
	top_row.add_child(btn_down)
	
	var btn_del = Button.new()
	btn_del.text = "✕"
	btn_del.modulate = Color(1.0, 0.4, 0.4)
	btn_del.pressed.connect(func(): delete_line(index))
	top_row.add_child(btn_del)
	
	# 台词文本
	var edit_content = TextEdit.new()
	edit_content.text = line_data.get("text", "")
	edit_content.custom_minimum_size = Vector2(0, 60)
	edit_content.text_changed.connect(func(): line_data["text"] = edit_content.text)
	vbox.add_child(edit_content)
	
	return card

func _on_add_line_pressed() -> void:
	if current_dialogue_id.is_empty():
		return
	if not current_dialogue_data.has("lines"):
		current_dialogue_data["lines"] = []
	var new_line = {
		"speaker": "主人公",
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
					{"speaker": "旁白", "text": "开始新的对话..."}
				]
			}
			DataManager.save_item("dialogues", did, d_data)
			refresh_dialogue_list()
			load_dialogue(did)
	)
	add_child(dialog)
	dialog.popup_centered()
