# editor/ui/tabs/reasoning_tab.gd
# 逻辑举证与推理谜题矩阵编辑器
class_name ReasoningTab
extends Control

var reasoning_list: ItemList
var current_reasoning_id: String = ""
var current_reasoning_data: Dictionary = {}

var edit_res_id: LineEdit
var edit_res_title: LineEdit
var opt_res_next_node: OptionButton
var edit_res_question: TextEdit
var req_clues_container: VBoxContainer

func _ready() -> void:
	setup_ui()
	refresh_reasonings()

func setup_ui() -> void:
	var hsplit = HSplitContainer.new()
	hsplit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hsplit)
	
	# 左侧列表
	var left = VBoxContainer.new()
	left.custom_minimum_size = Vector2(260, 0)
	hsplit.add_child(left)
	
	var lbl = Label.new()
	lbl.text = "🧩 破绽与推理谜题清单"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(lbl)
	
	reasoning_list = ItemList.new()
	reasoning_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reasoning_list.item_selected.connect(_on_reasoning_selected)
	left.add_child(reasoning_list)
	
	var btn_add_res = Button.new()
	btn_add_res.text = "➕ 添加推理谜题"
	btn_add_res.pressed.connect(_on_add_reasoning_pressed)
	left.add_child(btn_add_res)
	
	# 右侧表单
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	hsplit.add_child(right)
	
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	right.add_child(grid)
	
	var l1 = Label.new(); l1.text = "推理 ID: "; grid.add_child(l1)
	edit_res_id = LineEdit.new(); edit_res_id.editable = false; grid.add_child(edit_res_id)
	
	var l2 = Label.new(); l2.text = "谜题标题: "; grid.add_child(l2)
	edit_res_title = LineEdit.new(); grid.add_child(edit_res_title)
	
	var l_node = Label.new(); l_node.text = "论证成功跳转节点: "; grid.add_child(l_node)
	opt_res_next_node = OptionButton.new(); grid.add_child(opt_res_next_node)
	
	var l3 = Label.new(); l3.text = "核心矛盾/质询疑问 (Question): "
	right.add_child(l3)
	edit_res_question = TextEdit.new()
	edit_res_question.custom_minimum_size = Vector2(0, 90)
	right.add_child(edit_res_question)
	
	var l4 = Label.new(); l4.text = "勾选正确论证必须出示的铁证 (Required Clues): "
	right.add_child(l4)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 160)
	right.add_child(scroll)
	
	req_clues_container = VBoxContainer.new()
	req_clues_container.add_theme_constant_override("separation", 6)
	scroll.add_child(req_clues_container)
	
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	var btn_save = Button.new()
	btn_save.text = "💾 保存此推理谜题"
	btn_save.pressed.connect(save_current_reasoning)
	btn_row.add_child(btn_save)
	
	var btn_del = Button.new()
	btn_del.text = "🗑 删除谜题"
	btn_del.modulate = Color(1.0, 0.4, 0.4)
	btn_del.pressed.connect(_on_delete_reasoning)
	btn_row.add_child(btn_del)
	right.add_child(btn_row)

func refresh_reasonings() -> void:
	reasoning_list.clear()
	for rid in DataManager.reasonings:
		var r = DataManager.reasonings[rid]
		reasoning_list.add_item("%s (%s)" % [r.get("title", rid), rid])
	if reasoning_list.item_count > 0:
		reasoning_list.select(0)
		_on_reasoning_selected(0)

func _on_reasoning_selected(idx: int) -> void:
	var keys = DataManager.reasonings.keys()
	if idx < 0 or idx >= keys.size():
		return
	current_reasoning_id = keys[idx]
	current_reasoning_data = DataManager.reasonings[current_reasoning_id]
	
	edit_res_id.text = current_reasoning_id
	edit_res_title.text = current_reasoning_data.get("title", "")
	edit_res_question.text = current_reasoning_data.get("question", "")
	
	# 刷新可选故事节点列表
	opt_res_next_node.clear()
	var n_keys = DataManager.nodes.keys()
	var cur_next = current_reasoning_data.get("next_node", "")
	var sel_n_idx = 0
	for i in range(n_keys.size()):
		var nid = n_keys[i]
		var ndata = DataManager.nodes[nid]
		opt_res_next_node.add_item("%s (%s)" % [ndata.get("title", nid), nid], i)
		if nid == cur_next:
			sel_n_idx = i
	if opt_res_next_node.item_count > 0:
		opt_res_next_node.selected = sel_n_idx
		
	# 刷新必需线索勾选框
	for c in req_clues_container.get_children():
		c.queue_free()
		
	var req_list: Array = current_reasoning_data.get("required_clues", [])
	for cid in DataManager.clues:
		var cdata = DataManager.clues[cid]
		var chk = CheckBox.new()
		chk.text = "  [%s] %s (%s)" % [cdata.get("type", "物证"), cdata.get("title", cid), cid]
		chk.button_pressed = (cid in req_list)
		chk.set_meta("clue_id", cid)
		req_clues_container.add_child(chk)

func _on_add_reasoning_pressed() -> void:
	var new_id = "reason_" + str(Time.get_unix_time_from_system()).substr(5, 5)
	var new_data = {
		"id": new_id,
		"title": "破除谎言的推理",
		"question": "对方的关键陈述中隐藏着什么物理或时间矛盾？哪项铁证能推翻它？",
		"required_clues": [],
		"next_node": ""
	}
	DataManager.save_item("reasonings", new_id, new_data)
	refresh_reasonings()

func save_current_reasoning() -> void:
	if current_reasoning_id.is_empty():
		return
	current_reasoning_data["title"] = edit_res_title.text
	current_reasoning_data["question"] = edit_res_question.text
	
	var n_keys = DataManager.nodes.keys()
	if opt_res_next_node.selected >= 0 and opt_res_next_node.selected < n_keys.size():
		current_reasoning_data["next_node"] = n_keys[opt_res_next_node.selected]
		
	var req_clues: Array = []
	for c in req_clues_container.get_children():
		if c is CheckBox and c.button_pressed:
			req_clues.append(c.get_meta("clue_id"))
	current_reasoning_data["required_clues"] = req_clues
	
	DataManager.save_item("reasonings", current_reasoning_id, current_reasoning_data)
	var sel_idx = reasoning_list.get_selected_items()
	if sel_idx.size() > 0:
		reasoning_list.set_item_text(sel_idx[0], "%s (%s)" % [current_reasoning_data["title"], current_reasoning_id])

func _on_delete_reasoning() -> void:
	if current_reasoning_id.is_empty():
		return
	DataManager.delete_item("reasonings", current_reasoning_id)
	current_reasoning_id = ""
	refresh_reasonings()
