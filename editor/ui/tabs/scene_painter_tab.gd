# editor/ui/tabs/scene_painter_tab.gd
# 场景搜证画板（所见即所得的可视化热区标定与互动配置器）
class_name ScenePainterTab
extends Control

const HotspotBox = preload("res://editor/ui/components/hotspot_box.gd")

var current_scene_id: String = ""
var current_scene_data: Dictionary = {}
var selected_box: Control = null

# UI 引用
var scene_item_list: ItemList
var canvas_container: Control
var bg_texture_rect: TextureRect
var hotspot_layer: Control
var inspector_box: VBoxContainer

# 检查器字段
var edit_hotspot_id: LineEdit
var edit_hotspot_name: LineEdit
var edit_hotspot_rect: LineEdit
var opt_hotspot_type: OptionButton
var opt_trigger_action: OptionButton
var opt_target_item: OptionButton
var opt_condition_clue: OptionButton

# 画框新建模式
var is_drawing_mode: bool = false
var draw_start_pos: Vector2 = Vector2.ZERO
var draw_preview_rect: ColorRect

func _ready() -> void:
	setup_ui()
	refresh_scene_list()

func setup_ui() -> void:
	var hsplit = HSplitContainer.new()
	hsplit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hsplit)
	
	# 左侧: 场景列表与全局操作
	var left_panel = VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(240, 0)
	hsplit.add_child(left_panel)
	
	var lbl_scenes = Label.new()
	lbl_scenes.text = "🏛️ 场景列表"
	lbl_scenes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_panel.add_child(lbl_scenes)
	
	scene_item_list = ItemList.new()
	scene_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scene_item_list.item_selected.connect(_on_scene_selected)
	left_panel.add_child(scene_item_list)
	
	var btn_add_scene = Button.new()
	btn_add_scene.text = "➕ 新建设证场景"
	btn_add_scene.pressed.connect(_on_add_scene_pressed)
	left_panel.add_child(btn_add_scene)
	
	# 中间: 画板区域
	var center_box = VBoxContainer.new()
	center_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsplit.add_child(center_box)
	
	# 画板工具栏
	var canvas_toolbar = HBoxContainer.new()
	canvas_toolbar.custom_minimum_size = Vector2(0, 40)
	center_box.add_child(canvas_toolbar)
	
	var btn_mode_select = Button.new()
	btn_mode_select.text = "👆 选择/调整热区"
	btn_mode_select.pressed.connect(func(): set_drawing_mode(false))
	canvas_toolbar.add_child(btn_mode_select)
	
	var btn_mode_draw = Button.new()
	btn_mode_draw.text = "✏️ 鼠标画框新建热区"
	btn_mode_draw.pressed.connect(func(): set_drawing_mode(true))
	canvas_toolbar.add_child(btn_mode_draw)
	
	var sep1 = VSeparator.new()
	canvas_toolbar.add_child(sep1)
	
	var btn_save_scene = Button.new()
	btn_save_scene.text = "💾 保存当前场景配置"
	btn_save_scene.pressed.connect(save_current_scene)
	canvas_toolbar.add_child(btn_save_scene)
	
	# 画板视口
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_box.add_child(scroll)
	
	canvas_container = Control.new()
	canvas_container.custom_minimum_size = Vector2(1920, 1080)
	scroll.add_child(canvas_container)
	
	bg_texture_rect = TextureRect.new()
	bg_texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	canvas_container.add_child(bg_texture_rect)
	
	hotspot_layer = Control.new()
	hotspot_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas_container.add_child(hotspot_layer)
	
	# 画框预览
	draw_preview_rect = ColorRect.new()
	draw_preview_rect.color = Color(1.0, 0.8, 0.2, 0.4)
	draw_preview_rect.visible = false
	canvas_container.add_child(draw_preview_rect)
	
	# 监听画板上的点击画框事件
	canvas_container.gui_input.connect(_on_canvas_gui_input)
	
	# 右侧: 热区属性检查器
	var right_scroll = ScrollContainer.new()
	right_scroll.custom_minimum_size = Vector2(320, 0)
	hsplit.add_child(right_scroll)
	
	inspector_box = VBoxContainer.new()
	inspector_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(inspector_box)
	
	setup_inspector()

func setup_inspector() -> void:
	var lbl_head = Label.new()
	lbl_head.text = "⚙️ 热区属性配置"
	lbl_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inspector_box.add_child(lbl_head)
	
	inspector_box.add_child(Label.new())
	(inspector_box.get_child(inspector_box.get_child_count() - 1) as Label).text = "热区标识 ID:"
	edit_hotspot_id = LineEdit.new()
	edit_hotspot_id.editable = false
	inspector_box.add_child(edit_hotspot_id)
	
	var lbl_name = Label.new()
	lbl_name.text = "线索/物体名称:"
	inspector_box.add_child(lbl_name)
	edit_hotspot_name = LineEdit.new()
	edit_hotspot_name.text_changed.connect(_on_inspector_data_changed)
	inspector_box.add_child(edit_hotspot_name)
	
	var lbl_rect = Label.new()
	lbl_rect.text = "归一化坐标 [X, Y, W, H]:"
	inspector_box.add_child(lbl_rect)
	edit_hotspot_rect = LineEdit.new()
	edit_hotspot_rect.editable = false
	inspector_box.add_child(edit_hotspot_rect)
	
	var lbl_type = Label.new()
	lbl_type.text = "可调查类型:"
	inspector_box.add_child(lbl_type)
	opt_hotspot_type = OptionButton.new()
	opt_hotspot_type.add_item("once (搜集一次后消失)", 0)
	opt_hotspot_type.add_item("repeatable (可反复点击对话)", 1)
	opt_hotspot_type.item_selected.connect(_on_inspector_data_changed)
	inspector_box.add_child(opt_hotspot_type)
	
	var lbl_act = Label.new()
	lbl_act.text = "点击触发动作 (Trigger):"
	inspector_box.add_child(lbl_act)
	opt_trigger_action = OptionButton.new()
	opt_trigger_action.add_item("clue (搜获线索)", 0)
	opt_trigger_action.add_item("dialogue (触发对白)", 1)
	opt_trigger_action.add_item("jump_node (跳转剧情节点)", 2)
	opt_trigger_action.item_selected.connect(_on_trigger_type_changed)
	inspector_box.add_child(opt_trigger_action)
	
	var lbl_tgt = Label.new()
	lbl_tgt.text = "目标数据项 ID:"
	inspector_box.add_child(lbl_tgt)
	opt_target_item = OptionButton.new()
	opt_target_item.item_selected.connect(_on_inspector_data_changed)
	inspector_box.add_child(opt_target_item)
	
	var lbl_cond = Label.new()
	lbl_cond.text = "前置出现条件 (需拥有线索):"
	inspector_box.add_child(lbl_cond)
	opt_condition_clue = OptionButton.new()
	opt_condition_clue.item_selected.connect(_on_inspector_data_changed)
	inspector_box.add_child(opt_condition_clue)
	
	var sep = HSeparator.new()
	inspector_box.add_child(sep)
	
	var btn_delete_hotspot = Button.new()
	btn_delete_hotspot.text = "🗑️ 删除选中热区"
	btn_delete_hotspot.modulate = Color(1.0, 0.4, 0.4)
	btn_delete_hotspot.pressed.connect(_on_delete_selected_hotspot)
	inspector_box.add_child(btn_delete_hotspot)

func refresh_scene_list() -> void:
	scene_item_list.clear()
	for sc_id in DataManager.scenes:
		var sc_data = DataManager.scenes[sc_id]
		var title = sc_data.get("name", sc_id)
		scene_item_list.add_item("%s (%s)" % [title, sc_id])
		
	if scene_item_list.item_count > 0:
		scene_item_list.select(0)
		_on_scene_selected(0)

func _on_scene_selected(index: int) -> void:
	var keys = DataManager.scenes.keys()
	if index >= 0 and index < keys.size():
		load_scene(keys[index])

func load_scene(scene_id: String) -> void:
	current_scene_id = scene_id
	current_scene_data = DataManager.scenes.get(scene_id, {}).duplicate(true)
	
	# 加载背景图
	var bg_path = current_scene_data.get("background", "")
	if not bg_path.is_empty() and ResourceLoader.exists(bg_path):
		bg_texture_rect.texture = load(bg_path)
	else:
		bg_texture_rect.texture = null
		
	# 清空现有热区
	for child in hotspot_layer.get_children():
		child.queue_free()
	selected_box = null
	
	# 实例化所有热区
	var points = current_scene_data.get("explore_points", [])
	for pt in points:
		var pt_id = pt.get("id", "pt_" + str(Time.get_ticks_msec()))
		var box = HotspotBox.new(pt_id, pt, canvas_container.custom_minimum_size)
		box.selected.connect(_on_hotspot_box_selected)
		box.rect_modified.connect(_on_hotspot_rect_modified)
		hotspot_layer.add_child(box)
		
	clear_inspector()

func _on_hotspot_box_selected(box: HotspotBox) -> void:
	for child in hotspot_layer.get_children():
		if child is HotspotBox:
			child.set_selected(child == box)
	selected_box = box
	load_box_into_inspector(box)

func _on_hotspot_rect_modified(box: HotspotBox, norm_rect: Array) -> void:
	if box == selected_box:
		edit_hotspot_rect.text = str(norm_rect)

func load_box_into_inspector(box: HotspotBox) -> void:
	var data = box.hotspot_data
	edit_hotspot_id.text = box.hotspot_id
	edit_hotspot_name.text = data.get("name", "")
	edit_hotspot_rect.text = str(box.get_normalized_rect())
	
	var is_repeatable = (data.get("type", "once") == "repeatable")
	opt_hotspot_type.selected = 1 if is_repeatable else 0
	
	var trig = data.get("trigger", {})
	var act = trig.get("action", "clue")
	match act:
		"clue": opt_trigger_action.selected = 0
		"dialogue": opt_trigger_action.selected = 1
		"jump_node": opt_trigger_action.selected = 2
		
	refresh_target_dropdown(act, trig.get("target", ""))
	refresh_condition_dropdown(data.get("conditions", []))

func refresh_target_dropdown(action_type: String, current_target: String) -> void:
	opt_target_item.clear()
	var items = []
	match action_type:
		"clue": items = DataManager.clues.keys()
		"dialogue": items = DataManager.dialogues.keys()
		"jump_node": items = DataManager.nodes.keys()
		
	var sel_idx = 0
	for i in range(items.size()):
		var it = items[i]
		opt_target_item.add_item(it, i)
		if it == current_target:
			sel_idx = i
	if items.size() > 0:
		opt_target_item.selected = sel_idx

func refresh_condition_dropdown(conditions: Array) -> void:
	opt_condition_clue.clear()
	opt_condition_clue.add_item("无前置条件", 0)
	
	var current_req = ""
	for cond in conditions:
		if cond.get("type", "") == "has_clue":
			current_req = cond.get("clue_id", "")
			
	var idx = 1
	var sel_idx = 0
	for clue_id in DataManager.clues:
		var clue_data = DataManager.clues[clue_id]
		opt_condition_clue.add_item("%s (%s)" % [clue_data.get("title", clue_id), clue_id], idx)
		if clue_id == current_req:
			sel_idx = idx
		idx += 1
	opt_condition_clue.selected = sel_idx

func _on_trigger_type_changed(index: int) -> void:
	var act = "clue"
	match index:
		0: act = "clue"
		1: act = "dialogue"
		2: act = "jump_node"
	refresh_target_dropdown(act, "")
	_on_inspector_data_changed()

func _on_inspector_data_changed(_v = null) -> void:
	if not selected_box:
		return
		
	selected_box.hotspot_data["name"] = edit_hotspot_name.text.strip_edges()
	selected_box.hotspot_data["type"] = "repeatable" if opt_hotspot_type.selected == 1 else "once"
	
	var act = "clue"
	match opt_trigger_action.selected:
		0: act = "clue"
		1: act = "dialogue"
		2: act = "jump_node"
		
	var target_str = opt_target_item.get_item_text(opt_target_item.selected) if opt_target_item.item_count > 0 else ""
	selected_box.hotspot_data["trigger"] = {
		"action": act,
		"target": target_str
	}
	
	if opt_condition_clue.selected > 0:
		var text = opt_condition_clue.get_item_text(opt_condition_clue.selected)
		var cid = text.split(" (")[-1].replace(")", "")
		selected_box.hotspot_data["conditions"] = [{"type": "has_clue", "clue_id": cid}]
	else:
		selected_box.hotspot_data.erase("conditions")
		
	selected_box.queue_redraw()

func clear_inspector() -> void:
	edit_hotspot_id.text = ""
	edit_hotspot_name.text = ""
	edit_hotspot_rect.text = ""
	opt_target_item.clear()
	opt_condition_clue.clear()

func set_drawing_mode(enabled: bool) -> void:
	is_drawing_mode = enabled
	draw_preview_rect.visible = false

func _on_canvas_gui_input(event: InputEvent) -> void:
	if not is_drawing_mode:
		return
		
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			draw_start_pos = event.position
			draw_preview_rect.position = draw_start_pos
			draw_preview_rect.size = Vector2.ZERO
			draw_preview_rect.visible = true
		else:
			if draw_preview_rect.visible:
				draw_preview_rect.visible = false
				var end_pos = event.position
				var rx = min(draw_start_pos.x, end_pos.x)
				var ry = min(draw_start_pos.y, end_pos.y)
				var rw = abs(end_pos.x - draw_start_pos.x)
				var rh = abs(end_pos.y - draw_start_pos.y)
				
				if rw > 20 and rh > 20:
					create_new_hotspot_at(rx, ry, rw, rh)
					set_drawing_mode(false)
					
	elif event is InputEventMouseMotion and draw_preview_rect.visible:
		var cur_pos = event.position
		var rx = min(draw_start_pos.x, cur_pos.x)
		var ry = min(draw_start_pos.y, cur_pos.y)
		var rw = abs(cur_pos.x - draw_start_pos.x)
		var rh = abs(cur_pos.y - draw_start_pos.y)
		draw_preview_rect.position = Vector2(rx, ry)
		draw_preview_rect.size = Vector2(rw, rh)

func create_new_hotspot_at(px: float, py: float, pw: float, ph: float) -> void:
	var c_size = canvas_container.custom_minimum_size
	var nx = snapped(px / c_size.x, 0.001)
	var ny = snapped(py / c_size.y, 0.001)
	var nw = snapped(pw / c_size.x, 0.001)
	var nh = snapped(ph / c_size.y, 0.001)
	
	var new_id = "point_" + str(Time.get_ticks_msec()).substr(0, 5)
	var new_pt_data = {
		"id": new_id,
		"name": "新线索热区",
		"rect": [nx, ny, nw, nh],
		"type": "once",
		"trigger": {"action": "clue", "target": ""}
	}
	
	var box = HotspotBox.new(new_id, new_pt_data, c_size)
	box.selected.connect(_on_hotspot_box_selected)
	box.rect_modified.connect(_on_hotspot_rect_modified)
	hotspot_layer.add_child(box)
	_on_hotspot_box_selected(box)

func _on_delete_selected_hotspot() -> void:
	if selected_box:
		selected_box.queue_free()
		selected_box = null
		clear_inspector()

func save_current_scene() -> void:
	if current_scene_id.is_empty():
		return
		
	var updated_points = []
	for child in hotspot_layer.get_children():
		if child is HotspotBox and is_instance_valid(child):
			child.hotspot_data["rect"] = child.get_normalized_rect()
			updated_points.append(child.hotspot_data)
			
	current_scene_data["explore_points"] = updated_points
	DataManager.save_item("scenes", current_scene_id, current_scene_data)

func _on_add_scene_pressed() -> void:
	var dialog = ConfirmationDialog.new()
	dialog.title = "新建场景"
	dialog.size = Vector2(360, 200)
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	vbox.add_child(Label.new())
	(vbox.get_child(0) as Label).text = "场景 ID (如 scene_002_garden):"
	var e_id = LineEdit.new()
	e_id.text = "scene_" + str(Time.get_ticks_msec()).substr(0, 4)
	vbox.add_child(e_id)
	
	var l_name = Label.new()
	l_name.text = "场景名称 (如 宅邸后花园):"
	vbox.add_child(l_name)
	var e_name = LineEdit.new()
	e_name.text = "新搜证现场"
	vbox.add_child(e_name)
	
	dialog.confirmed.connect(func():
		var sid = e_id.text.strip_edges()
		if not sid.is_empty():
			var sc_data = {
				"id": sid,
				"name": e_name.text.strip_edges(),
				"background": "res://assets/images/backgrounds/bg_hall.svg",
				"explore_points": []
			}
			DataManager.save_item("scenes", sid, sc_data)
			refresh_scene_list()
	)
	add_child(dialog)
	dialog.popup_centered()
