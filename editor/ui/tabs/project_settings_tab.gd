# editor/ui/tabs/project_settings_tab.gd
# 游戏项目全局设置与全量数据一致性体检
class_name ProjectSettingsTab
extends Control

var edit_game_title: LineEdit
var edit_game_version: LineEdit
var edit_game_author: LineEdit
var edit_protagonist: LineEdit
var opt_start_node: OptionButton
var check_result_label: RichTextLabel

func _ready() -> void:
	setup_ui()
	load_data()

func setup_ui() -> void:
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	
	var lbl_title = Label.new()
	lbl_title.text = "⚙️ 游戏项目全局属性"
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl_title)
	
	var grid = GridContainer.new()
	grid.columns = 2
	vbox.add_child(grid)
	
	var l1 = Label.new(); l1.text = "游戏标题 (Game Title): "; grid.add_child(l1)
	edit_game_title = LineEdit.new(); grid.add_child(edit_game_title)
	
	var l2 = Label.new(); l2.text = "发布版本 (Version): "; grid.add_child(l2)
	edit_game_version = LineEdit.new(); grid.add_child(edit_game_version)
	
	var l3 = Label.new(); l3.text = "制作组/作者: "; grid.add_child(l3)
	edit_game_author = LineEdit.new(); grid.add_child(edit_game_author)
	
	var l4 = Label.new(); l4.text = "侦探主人公姓名: "; grid.add_child(l4)
	edit_protagonist = LineEdit.new(); grid.add_child(edit_protagonist)
	
	var l5 = Label.new(); l5.text = "流程起始故事节点 (Start Node): "; grid.add_child(l5)
	opt_start_node = OptionButton.new(); grid.add_child(opt_start_node)
	
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	var btn_row = HBoxContainer.new()
	var btn_save = Button.new()
	btn_save.text = "💾 保存项目设置"
	btn_save.pressed.connect(save_settings)
	btn_row.add_child(btn_save)
	
	var btn_validate = Button.new()
	btn_validate.text = "🩺 执行全量死链体检"
	btn_validate.pressed.connect(run_integrity_check)
	btn_row.add_child(btn_validate)
	vbox.add_child(btn_row)
	
	var l_log = Label.new()
	l_log.text = "📋 数据一致性报告:"
	vbox.add_child(l_log)
	
	check_result_label = RichTextLabel.new()
	check_result_label.bbcode_enabled = true
	check_result_label.custom_minimum_size = Vector2(0, 200)
	vbox.add_child(check_result_label)

func load_data() -> void:
	var g_cfg = DataManager.game_config
	var f_cfg = DataManager.flow_config
	
	edit_game_title.text = g_cfg.get("game_title", "神星悬疑推理引擎")
	edit_game_version.text = str(g_cfg.get("version", g_cfg.get("engine_version", "1.0.0")))
	edit_game_author.text = str(g_cfg.get("author", "Detective Studio"))
	
	var prot = g_cfg.get("protagonist", "林侦探")
	if prot is Dictionary:
		edit_protagonist.text = prot.get("name", "侦探")
	else:
		edit_protagonist.text = str(prot)
	
	# 起始节点下拉
	opt_start_node.clear()
	var nodes = DataManager.nodes.keys()
	var cur_start = f_cfg.get("start_node", "")
	var sel_idx = 0
	for i in range(nodes.size()):
		var nid = nodes[i]
		opt_start_node.add_item(nid, i)
		if nid == cur_start:
			sel_idx = i
	if nodes.size() > 0:
		opt_start_node.selected = sel_idx

func save_settings() -> void:
	var g_cfg = DataManager.game_config
	g_cfg["game_title"] = edit_game_title.text.strip_edges()
	g_cfg["version"] = edit_game_version.text.strip_edges()
	g_cfg["author"] = edit_game_author.text.strip_edges()
	g_cfg["protagonist"] = edit_protagonist.text.strip_edges()
	
	DataManager.save_game_config(g_cfg)
	
	var f_cfg = DataManager.flow_config
	if opt_start_node.item_count > 0:
		f_cfg["start_node"] = opt_start_node.get_item_text(opt_start_node.selected)
	DataManager.save_flow_config(f_cfg)
	
	run_integrity_check()

func run_integrity_check() -> void:
	check_result_label.clear()
	var report = []
	var issues = 0
	
	# 1. 检查起点
	var start_node = DataManager.flow_config.get("start_node", "")
	if not DataManager.nodes.has(start_node):
		report.append("[color=red]❌ 致命错误: 起始节点 '%s' 在节点库中不存在！[/color]" % start_node)
		issues += 1
	else:
		report.append("[color=green]✅ 起始节点有效: %s[/color]" % start_node)
		
	# 2. 检查节点跳转死链
	for nid in DataManager.nodes:
		var ndata = DataManager.nodes[nid]
		var next_id = ndata.get("next", "")
		if not next_id.is_empty() and not DataManager.nodes.has(next_id):
			report.append("[color=yellow]⚠️ 节点 [%s] 的 next 属性指向了不存在的节点: %s[/color]" % [nid, next_id])
			issues += 1
			
		var scene_id = ndata.get("scene", "")
		if not scene_id.is_empty() and not DataManager.scenes.has(scene_id):
			report.append("[color=yellow]⚠️ 节点 [%s] 引用的场景不存在: %s[/color]" % [nid, scene_id])
			issues += 1
			
		var diag_id = ndata.get("dialogue", "")
		if not diag_id.is_empty() and not DataManager.dialogues.has(diag_id):
			report.append("[color=yellow]⚠️ 节点 [%s] 引用的剧本不存在: %s[/color]" % [nid, diag_id])
			issues += 1
			
	# 3. 检查推理谜题线索依赖
	for rid in DataManager.reasonings:
		var rdata = DataManager.reasonings[rid]
		for cid in rdata.get("required_clues", []):
			if not DataManager.clues.has(cid):
				report.append("[color=red]❌ 推理谜题 [%s] 依赖的线索不存在: %s[/color]" % [rid, cid])
				issues += 1
				
	if issues == 0:
		report.append("\n[b][color=green]🎉 恭喜！全工程数据体检完成，0 处死链与逻辑冲突，可放心打包发布！[/color][/b]")
	else:
		report.append("\n[b][color=orange]共发现 %d 处配置警报，建议在发布前修正。[/color][/b]" % issues)
		
	check_result_label.append_text("\n".join(report))
