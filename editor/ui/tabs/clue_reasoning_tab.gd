# editor/ui/tabs/clue_reasoning_tab.gd
# 线索档案库与逻辑举证推理矩阵编辑器
class_name ClueReasoningTab
extends Control

# 子标签页
var tab_container: TabContainer

# --- 线索库变量 ---
var clue_list: ItemList
var current_clue_id: String = ""
var current_clue_data: Dictionary = {}
var edit_clue_id: LineEdit
var edit_clue_title: LineEdit
var opt_clue_type: OptionButton
var edit_clue_desc: TextEdit
var edit_clue_source: LineEdit

# --- 推理矩阵变量 ---
var reasoning_list: ItemList
var current_reasoning_id: String = ""
var current_reasoning_data: Dictionary = {}
var edit_res_id: LineEdit
var edit_res_title: LineEdit
var edit_res_question: TextEdit
var req_clues_container: VBoxContainer
var opt_res_next_node: OptionButton

func _ready() -> void:
	setup_ui()
	refresh_clues()
	refresh_reasonings()

func setup_ui() -> void:
	tab_container = TabContainer.new()
	tab_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(tab_container)
	
	# Tab 1: 线索档案库
	var clue_page = create_clue_page()
	clue_page.name = "🔍 线索与物证库"
	tab_container.add_child(clue_page)
	
	# Tab 2: 推理与破绽谜题
	var reasoning_page = create_reasoning_page()
	reasoning_page.name = "🧩 逻辑举证与推理谜题"
	tab_container.add_child(reasoning_page)

func create_clue_page() -> Control:
	var hsplit = HSplitContainer.new()
	
	# 左侧列表
	var left = VBoxContainer.new()
	left.custom_minimum_size = Vector2(260, 0)
	hsplit.add_child(left)
	
	var lbl = Label.new()
	lbl.text = "📑 已配置线索清单"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(lbl)
	
	clue_list = ItemList.new()
	clue_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	clue_list.item_selected.connect(_on_clue_selected)
	left.add_child(clue_list)
	
	var btn_add_clue = Button.new()
	btn_add_clue.text = "➕ 添加新线索"
	btn_add_clue.pressed.connect(_on_add_clue_pressed)
	left.add_child(btn_add_clue)
	
	# 右侧编辑表单
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_child(right)
	
	var grid = GridContainer.new()
	grid.columns = 2
	right.add_child(grid)
	
	var l1 = Label.new(); l1.text = "线索 ID: "; grid.add_child(l1)
	edit_clue_id = LineEdit.new(); edit_clue_id.editable = false; grid.add_child(edit_clue_id)
	
	var l2 = Label.new(); l2.text = "线索标题: "; grid.add_child(l2)
	edit_clue_title = LineEdit.new(); grid.add_child(edit_clue_title)
	
	var l3 = Label.new(); l3.text = "线索类别: "; grid.add_child(l3)
	opt_clue_type = OptionButton.new()
	opt_clue_type.add_item("物证 (item)", 0)
	opt_clue_type.add_item("证言 (testimony)", 1)
	opt_clue_type.add_item("现场 (scene)", 2)
	grid.add_child(opt_clue_type)
	
	var l4 = Label.new(); l4.text = "发现来源: "; grid.add_child(l4)
	edit_clue_source = LineEdit.new(); grid.add_child(edit_clue_source)
	
	var l5 = Label.new(); l5.text = "线索详述与推理价值: "
	right.add_child(l5)
	edit_clue_desc = TextEdit.new()
	edit_clue_desc.custom_minimum_size = Vector2(0, 140)
	right.add_child(edit_clue_desc)
	
	var btn_row = HBoxContainer.new()
	var btn_save = Button.new()
	btn_save.text = "💾 保存线索"
	btn_save.pressed.connect(save_current_clue)
	btn_row.add_child(btn_save)
	
	var btn_del = Button.new()
	btn_del.text = "🗑 删除线索"
	btn_del.modulate = Color(1.0, 0.4, 0.4)
	btn_del.pressed.connect(_on_delete_clue)
	btn_row.add_child(btn_del)
	right.add_child(btn_row)
	
	return hsplit

func refresh_clues() -> void:
	clue_list.clear()
	for cid in DataManager.clues:
		var c = DataManager.clues[cid]
		clue_list.add_item("%s (%s)" % [c.get("title", cid), cid])
	if clue_list.item_count > 0:
		clue_list.select(0)
		_on_clue_selected(0)

func _on_clue_selected(idx: int) -> void:
	var keys = DataManager.clues.keys()
	if idx >= 0 and idx < keys.size():
		current_clue_id = keys[idx]
		current_clue_data = DataManager.clues[current_clue_id].duplicate(true)
		edit_clue_id.text = current_clue_id
		edit_clue_title.text = current_clue_data.get("title", "")
		var c_type = current_clue_data.get("type", "item")
		match c_type:
			"item": opt_clue_type.selected = 0
			"testimony": opt_clue_type.selected = 1
			"scene": opt_clue_type.selected = 2
		edit_clue_source.text = current_clue_data.get("source", "")
		edit_clue_desc.text = current_clue_data.get("description", "")

func save_current_clue() -> void:
	if current_clue_id.is_empty():
		return
	current_clue_data["title"] = edit_clue_title.text.strip_edges()
	var t = "item"
	match opt_clue_type.selected:
		0: t = "item"
		1: t = "testimony"
		2: t = "scene"
	current_clue_data["type"] = t
	current_clue_data["source"] = edit_clue_source.text.strip_edges()
	current_clue_data["description"] = edit_clue_desc.text
	DataManager.save_item("clues", current_clue_id, current_clue_data)
	refresh_clues()

func _on_delete_clue() -> void:
	if not current_clue_id.is_empty():
		DataManager.delete_item("clues", current_clue_id)
		refresh_clues()

func _on_add_clue_pressed() -> void:
	var cid = "clue_" + str(Time.get_ticks_msec()).substr(0, 4)
	var new_clue = {
		"id": cid,
		"title": "新发现线索",
		"type": "item",
		"source": "现场调查",
		"description": "详细描述此物证的来历和破案价值..."
	}
	DataManager.save_item("clues", cid, new_clue)
	refresh_clues()

# --- 推理矩阵部分 ---
func create_reasoning_page() -> Control:
	var hsplit = HSplitContainer.new()
	
	var left = VBoxContainer.new()
	left.custom_minimum_size = Vector2(260, 0)
	hsplit.add_child(left)
	
	var lbl = Label.new()
	lbl.text = "🧩 推理关卡清单"
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
	hsplit.add_child(right)
	
	var grid = GridContainer.new()
	grid.columns = 2
	right.add_child(grid)
	
	var l1 = Label.new(); l1.text = "推理 ID: "; grid.add_child(l1)
	edit_res_id = LineEdit.new(); edit_res_id.editable = false; grid.add_child(edit_res_id)
	
	var l2 = Label.new(); l2.text = "谜题标题: "; grid.add_child(l2)
	edit_res_title = LineEdit.new(); grid.add_child(edit_res_title)
	
	var l_node = Label.new(); l_node.text = "推导成功跳转故事节点: "; grid.add_child(l_node)
	opt_res_next_node = OptionButton.new(); grid.add_child(opt_res_next_node)
	
	var l3 = Label.new(); l3.text = "核心矛盾/破绽疑问 (Question): "
	right.add_child(l3)
	edit_res_question = TextEdit.new()
	edit_res_question.custom_minimum_size = Vector2(0, 80)
	right.add_child(edit_res_question)
	
	var l4 = Label.new(); l4.text = "勾选正确论证必须出示的线索 (Required Clues): "
	right.add_child(l4)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 150)
	right.add_child(scroll)
	
	req_clues_container = VBoxContainer.new()
	scroll.add_child(req_clues_container)
	
	var btn_row = HBoxContainer.new()
	var btn_save = Button.new()
	btn_save.text = "💾 保存推理谜题"
	btn_save.pressed.connect(save_current_reasoning)
	btn_row.add_child(btn_save)
	
	var btn_del = Button.new()
	btn_del.text = "🗑 删除谜题"
	btn_del.modulate = Color(1.0, 0.4, 0.4)
	btn_del.pressed.connect(_on_delete_reasoning)
	btn_row.add_child(btn_del)
	right.add_child(btn_row)
	
	return hsplit

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
	if idx >= 0 and idx < keys.size():
		current_reasoning_id = keys[idx]
		current_reasoning_data = DataManager.reasonings[current_reasoning_id].duplicate(true)
		edit_res_id.text = current_reasoning_id
		edit_res_title.text = current_reasoning_data.get("title", "")
		edit_res_question.text = current_reasoning_data.get("question", "")
		
		# 刷新目标节点下拉
		opt_res_next_node.clear()
		var n_keys = DataManager.nodes.keys()
		var sel_n = 0
		var target_next = current_reasoning_data.get("next_node", "")
		for i in range(n_keys.size()):
			var nid = n_keys[i]
			opt_res_next_node.add_item(nid, i)
			if nid == target_next:
				sel_n = i
		if n_keys.size() > 0:
			opt_res_next_node.selected = sel_n
			
		# 渲染线索复选框
		for c in req_clues_container.get_children():
			c.queue_free()
		var req_arr = current_reasoning_data.get("required_clues", [])
		for cid in DataManager.clues:
			var cdata = DataManager.clues[cid]
			var cb = CheckBox.new()
			cb.text = "%s (%s)" % [cdata.get("title", cid), cid]
			cb.set_meta("clue_id", cid)
			cb.button_pressed = (cid in req_arr)
			req_clues_container.add_child(cb)

func save_current_reasoning() -> void:
	if current_reasoning_id.is_empty():
		return
	current_reasoning_data["title"] = edit_res_title.text.strip_edges()
	current_reasoning_data["question"] = edit_res_question.text
	if opt_res_next_node.item_count > 0:
		current_reasoning_data["next_node"] = opt_res_next_node.get_item_text(opt_res_next_node.selected)
		
	var updated_req = []
	for child in req_clues_container.get_children():
		if child is CheckBox and child.button_pressed:
			updated_req.append(child.get_meta("clue_id"))
	current_reasoning_data["required_clues"] = updated_req
	DataManager.save_item("reasonings", current_reasoning_id, current_reasoning_data)
	refresh_reasonings()

func _on_delete_reasoning() -> void:
	if not current_reasoning_id.is_empty():
		DataManager.delete_item("reasonings", current_reasoning_id)
		refresh_reasonings()

func _on_add_reasoning_pressed() -> void:
	var rid = "reason_" + str(Time.get_ticks_msec()).substr(0, 4)
	var new_res = {
		"id": rid,
		"title": "新案件矛盾点",
		"question": "凶手的辩解中存在怎样的致命矛盾？",
		"required_clues": [],
		"error_hints": {},
		"next_node": ""
	}
	DataManager.save_item("reasonings", rid, new_res)
	refresh_reasonings()
