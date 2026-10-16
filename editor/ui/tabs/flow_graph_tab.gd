# editor/ui/tabs/flow_graph_tab.gd
# 流程节点图编辑器（基于 GraphEdit 打造的可视化连线创作画板）
class_name FlowGraphTab
extends Control

signal playtest_node_requested(node_id: String)
signal edit_dialogue_requested(dialogue_id: String)
signal edit_scene_requested(scene_id: String)

var graph_edit: GraphEdit
var node_map: Dictionary = {} # node_id -> GraphNode

func _ready() -> void:
	setup_ui()
	refresh_graph()

func setup_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)
	
	# 顶部操作工具栏
	var toolbar = HBoxContainer.new()
	toolbar.custom_minimum_size = Vector2(0, 42)
	vbox.add_child(toolbar)
	
	var btn_add_node = Button.new()
	btn_add_node.text = "➕ 添加故事节点"
	btn_add_node.pressed.connect(_on_add_node_pressed)
	toolbar.add_child(btn_add_node)
	
	var btn_refresh = Button.new()
	btn_refresh.text = "🔄 刷新流程图"
	btn_refresh.pressed.connect(refresh_graph)
	toolbar.add_child(btn_refresh)
	
	var btn_auto_layout = Button.new()
	btn_auto_layout.text = "📐 自动整齐排列"
	btn_auto_layout.pressed.connect(auto_arrange_nodes)
	toolbar.add_child(btn_auto_layout)
	
	var sep = VSeparator.new()
	toolbar.add_child(sep)
	
	var lbl_tips = Label.new()
	lbl_tips.text = "💡 提示: 拖动卡片右侧红/蓝圆点可连线到下一个节点；双击或点击按钮可直接跳转编辑对应场景或对话"
	lbl_tips.modulate = Color(0.7, 0.7, 0.7)
	toolbar.add_child(lbl_tips)
	
	# GraphEdit 画布
	graph_edit = GraphEdit.new()
	graph_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_edit.connection_request.connect(_on_connection_request)
	graph_edit.disconnection_request.connect(_on_disconnection_request)
	graph_edit.delete_nodes_request.connect(_on_delete_nodes_request)
	vbox.add_child(graph_edit)

func refresh_graph() -> void:
	if not graph_edit:
		return
		
	# 清空原有节点和连接
	graph_edit.clear_connections()
	for child in graph_edit.get_children():
		if child is GraphNode:
			child.queue_free()
	node_map.clear()
	
	var all_nodes = DataManager.nodes
	var start_node = DataManager.flow_config.get("start_node", "")
	
	var start_x = 100
	var start_y = 100
	var col = 0
	var row = 0
	
	for node_id in all_nodes:
		var data = all_nodes[node_id]
		var gnode = create_graph_node(node_id, data)
		graph_edit.add_child(gnode)
		node_map[node_id] = gnode
		
		# 恢复或计算初始位置
		if data.has("editor_pos") and data["editor_pos"] is Array and data["editor_pos"].size() >= 2:
			gnode.position_offset = Vector2(data["editor_pos"][0], data["editor_pos"][1])
		else:
			gnode.position_offset = Vector2(start_x + col * 360, start_y + row * 240)
			col += 1
			if col >= 3:
				col = 0
				row += 1
				
	# 建立连线
	for node_id in all_nodes:
		var data = all_nodes[node_id]
		var next_id = data.get("next", "")
		if not next_id.is_empty() and node_map.has(next_id):
			graph_edit.connect_node(StringName(node_id), 0, StringName(next_id), 0)
			
		# 处理分支选项中的连线
		if data.has("choices") and data["choices"] is Array:
			for choice in data["choices"]:
				var choice_next = choice.get("next_node", "")
				if not choice_next.is_empty() and node_map.has(choice_next):
					graph_edit.connect_node(StringName(node_id), 0, StringName(choice_next), 0)

func create_graph_node(node_id: String, data: Dictionary) -> GraphNode:
	var gnode = GraphNode.new()
	gnode.name = node_id
	var node_type = data.get("type", "story")
	var title = data.get("title", node_id)
	var is_milestone = data.get("is_milestone", false)
	var is_start = (node_id == DataManager.flow_config.get("start_node", ""))
	
	var prefix = "🚩 [起点] " if is_start else ""
	var milestone_icon = " ⏳" if is_milestone else ""
	gnode.title = "%s%s (%s)%s" % [prefix, title, node_type, milestone_icon]
	gnode.resizable = true
	gnode.custom_minimum_size = Vector2(280, 160)
	
	# 设置槽位连接点 (Slot 0)
	# 左侧输入: 允许接入
	# 右侧输出: 允许连出 (根据类型设置颜色)
	var slot_color = Color(0.3, 0.7, 1.0) # story
	match node_type:
		"explore": slot_color = Color(1.0, 0.6, 0.2)
		"reasoning": slot_color = Color(0.8, 0.4, 1.0)
		"ending": slot_color = Color(0.9, 0.3, 0.3)
		
	gnode.set_slot(0, true, 0, Color(0.5, 0.8, 0.5), true, 0, slot_color)
	
	# 卡片内容
	var content_box = VBoxContainer.new()
	
	var lbl_id = Label.new()
	lbl_id.text = "ID: " + node_id
	lbl_id.modulate = Color(0.6, 0.8, 1.0)
	content_box.add_child(lbl_id)
	
	if data.has("scene"):
		var btn_scene = Button.new()
		btn_scene.text = "🔍 关联场景: " + str(data.get("scene", ""))
		btn_scene.flat = true
		btn_scene.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn_scene.pressed.connect(func(): edit_scene_requested.emit(str(data.get("scene", ""))))
		content_box.add_child(btn_scene)
		
	if data.has("dialogue"):
		var btn_diag = Button.new()
		btn_diag.text = "💬 关联剧本: " + str(data.get("dialogue", ""))
		btn_diag.flat = true
		btn_diag.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn_diag.pressed.connect(func(): edit_dialogue_requested.emit(str(data.get("dialogue", ""))))
		content_box.add_child(btn_diag)
		
	if data.has("text"):
		var lbl_txt = Label.new()
		lbl_txt.text = "内容: " + str(data.get("text", "")).substr(0, 25) + "..."
		lbl_txt.modulate = Color(0.8, 0.8, 0.8)
		content_box.add_child(lbl_txt)
		
	# 试玩与快捷操作
	var btn_row = HBoxContainer.new()
	
	var btn_play = Button.new()
	btn_play.text = "▶ 试玩该节点"
	btn_play.pressed.connect(func(): playtest_node_requested.emit(node_id))
	btn_row.add_child(btn_play)
	
	var btn_set_start = Button.new()
	btn_set_start.text = "设为起点"
	btn_set_start.pressed.connect(func():
		DataManager.flow_config["start_node"] = node_id
		DataManager.save_flow_config(DataManager.flow_config)
		refresh_graph()
	)
	btn_row.add_child(btn_set_start)
	
	content_box.add_child(btn_row)
	gnode.add_child(content_box)
	
	# 位置改变时更新数据
	gnode.position_offset_changed.connect(func():
		data["editor_pos"] = [gnode.position_offset.x, gnode.position_offset.y]
		DataManager.save_item("nodes", node_id, data)
	)
	
	return gnode

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var from_id = String(from_node)
	var to_id = String(to_node)
	
	if DataManager.nodes.has(from_id):
		var node_data = DataManager.nodes[from_id]
		node_data["next"] = to_id
		DataManager.save_item("nodes", from_id, node_data)
		graph_edit.connect_node(from_node, from_port, to_node, to_port)

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var from_id = String(from_node)
	if DataManager.nodes.has(from_id):
		var node_data = DataManager.nodes[from_id]
		if node_data.get("next", "") == String(to_node):
			node_data.erase("next")
			DataManager.save_item("nodes", from_id, node_data)
		graph_edit.disconnect_node(from_node, from_port, to_node, to_port)

func _on_delete_nodes_request(nodes: Array[StringName]) -> void:
	for node_name in nodes:
		var node_id = String(node_name)
		DataManager.delete_item("nodes", node_id)
	refresh_graph()

func auto_arrange_nodes() -> void:
	var start_node = DataManager.flow_config.get("start_node", "")
	var visited = {}
	var current = start_node
	var x = 80
	var y = 150
	
	while not current.is_empty() and not visited.has(current):
		visited[current] = true
		if node_map.has(current):
			var gnode = node_map[current]
			gnode.position_offset = Vector2(x, y)
			var node_data = DataManager.nodes[current]
			node_data["editor_pos"] = [x, y]
			DataManager.save_item("nodes", current, node_data)
			x += 350
			current = node_data.get("next", "")
		else:
			break
			
	# 排列未连入主链的节点
	var rest_y = 450
	var rest_x = 80
	for node_id in DataManager.nodes:
		if not visited.has(node_id) and node_map.has(node_id):
			var gnode = node_map[node_id]
			gnode.position_offset = Vector2(rest_x, rest_y)
			var data = DataManager.nodes[node_id]
			data["editor_pos"] = [rest_x, rest_y]
			DataManager.save_item("nodes", node_id, data)
			rest_x += 350
			if rest_x > 1200:
				rest_x = 80
				rest_y += 240

func _on_add_node_pressed() -> void:
	var dialog = ConfirmationDialog.new()
	dialog.title = "新建故事流程节点"
	dialog.size = Vector2(400, 260)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(vbox)
	
	vbox.add_child(Label.new())
	var lbl1 = vbox.get_child(0) as Label
	lbl1.text = "节点 ID (唯一英文标识，如 node_search_hall):"
	var edit_id = LineEdit.new()
	edit_id.text = "node_" + str(Time.get_ticks_msec()).substr(0, 4)
	vbox.add_child(edit_id)
	
	var lbl2 = Label.new()
	lbl2.text = "节点标题 (如 调查走廊):"
	vbox.add_child(lbl2)
	var edit_title = LineEdit.new()
	edit_title.text = "新剧情节点"
	vbox.add_child(edit_title)
	
	var lbl3 = Label.new()
	lbl3.text = "节点类型:"
	vbox.add_child(lbl3)
	var opt_type = OptionButton.new()
	opt_type.add_item("story (剧情对话)", 0)
	opt_type.add_item("explore (场景搜证)", 1)
	opt_type.add_item("reasoning (举证推理)", 2)
	opt_type.add_item("ending (案情结局)", 3)
	vbox.add_child(opt_type)
	
	dialog.confirmed.connect(func():
		var new_id = edit_id.text.strip_edges()
		if new_id.is_empty():
			return
		var type_str = "story"
		match opt_type.selected:
			0: type_str = "story"
			1: type_str = "explore"
			2: type_str = "reasoning"
			3: type_str = "ending"
			
		var new_data = {
			"id": new_id,
			"title": edit_title.text.strip_edges(),
			"type": type_str,
			"editor_pos": [200, 200]
		}
		if type_str == "explore":
			new_data["scene"] = "scene_001_livingroom"
		elif type_str == "story":
			new_data["text"] = "这里是新剧情的内容..."
		elif type_str == "reasoning":
			new_data["reasoning_id"] = "reason_001_timeline"
			
		DataManager.save_item("nodes", new_id, new_data)
		refresh_graph()
		dialog.queue_free()
	)
	
	add_child(dialog)
	dialog.popup_centered()
