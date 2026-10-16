# editor/ui/tabs/clue_tab.gd
# 线索与物证档案库编辑器
class_name ClueTab
extends Control

var clue_list: ItemList
var current_clue_id: String = ""
var current_clue_data: Dictionary = {}

var edit_clue_id: LineEdit
var edit_clue_title: LineEdit
var opt_clue_type: OptionButton
var edit_clue_desc: TextEdit
var edit_clue_source: LineEdit

func _ready() -> void:
	setup_ui()
	refresh_clues()

func setup_ui() -> void:
	var hsplit = HSplitContainer.new()
	hsplit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hsplit)
	
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
	right.add_theme_constant_override("separation", 10)
	hsplit.add_child(right)
	
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
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
	edit_clue_desc.custom_minimum_size = Vector2(0, 160)
	right.add_child(edit_clue_desc)
	
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	var btn_save = Button.new()
	btn_save.text = "💾 保存此线索"
	btn_save.pressed.connect(save_current_clue)
	btn_row.add_child(btn_save)
	
	var btn_del = Button.new()
	btn_del.text = "🗑 删除线索"
	btn_del.modulate = Color(1.0, 0.4, 0.4)
	btn_del.pressed.connect(_on_delete_clue)
	btn_row.add_child(btn_del)
	right.add_child(btn_row)

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
	if idx < 0 or idx >= keys.size():
		return
	current_clue_id = keys[idx]
	current_clue_data = DataManager.clues[current_clue_id]
	
	edit_clue_id.text = current_clue_id
	edit_clue_title.text = current_clue_data.get("title", "")
	edit_clue_source.text = current_clue_data.get("source", "")
	edit_clue_desc.text = current_clue_data.get("description", "")
	
	match current_clue_data.get("type", "item"):
		"item": opt_clue_type.selected = 0
		"testimony": opt_clue_type.selected = 1
		"scene": opt_clue_type.selected = 2

func _on_add_clue_pressed() -> void:
	var new_id = "clue_" + str(Time.get_unix_time_from_system()).substr(5, 5)
	var new_data = {
		"id": new_id,
		"title": "新发现线索",
		"type": "item",
		"source": "现场勘验",
		"description": "请在此输入该线索的具体特征或用于驳斥谎言的破绽点。"
	}
	DataManager.save_item("clues", new_id, new_data)
	refresh_clues()

func save_current_clue() -> void:
	if current_clue_id.is_empty():
		return
	current_clue_data["title"] = edit_clue_title.text
	current_clue_data["source"] = edit_clue_source.text
	current_clue_data["description"] = edit_clue_desc.text
	
	match opt_clue_type.selected:
		0: current_clue_data["type"] = "item"
		1: current_clue_data["type"] = "testimony"
		2: current_clue_data["type"] = "scene"
		
	DataManager.save_item("clues", current_clue_id, current_clue_data)
	var sel_idx = clue_list.get_selected_items()
	if sel_idx.size() > 0:
		clue_list.set_item_text(sel_idx[0], "%s (%s)" % [current_clue_data["title"], current_clue_id])

func _on_delete_clue() -> void:
	if current_clue_id.is_empty():
		return
	DataManager.delete_item("clues", current_clue_id)
	current_clue_id = ""
	refresh_clues()
