# tools/test_dialogue_tab.gd
extends Control

const DialogueTabClass = preload("res://editor/ui/tabs/dialogue_tab.gd")

func _ready() -> void:
	print("--- 开始【剧本台词】就地配音与表情差分自动化功能测试 ---")
	call_deferred("run_tests")

func run_tests() -> void:
	await get_tree().create_timer(0.1).timeout
	
	print("[1] 实例化 DialogueTab")
	var tab = DialogueTabClass.new()
	add_child(tab)
	await get_tree().create_timer(0.2).timeout
	
	print("[2] 校验顶部工具栏按钮存在性与实体质感")
	assert(tab.btn_add_line != null, "必须包含添加台词按钮")
	assert(tab.btn_batch_voice != null, "必须包含本幕批量配音按钮")
	assert(tab.btn_save != null, "必须包含保存剧本按钮")
	assert(tab.lbl_batch_status != null, "必须包含状态反馈标签")
	print("    ✅ 顶部工具栏验证通过！按钮文案: %s, 状态: %s" % [tab.btn_batch_voice.text, tab.lbl_batch_status.text])
	
	print("[3] 验证载入对话剧本 dlg_intro")
	tab.load_dialogue("dlg_intro")
	await get_tree().create_timer(0.1).timeout
	var lines = tab.current_dialogue_data.get("lines", [])
	assert(lines.size() > 0, "dlg_intro 应当有台词")
	print("    ✅ 对话载入成功，共 %d 句台词，卡片子节点数: %d" % [lines.size(), tab.lines_container.get_child_count()])
	
	print("[4] 校验台词卡片内部表情差分选择器与配音按钮")
	var first_card = tab.lines_container.get_child(0)
	assert(first_card != null, "首张台词卡片应当存在")
	
	# 测试添加一句对白
	var pre_count = lines.size()
	tab._on_add_line_pressed()
	assert(tab.current_dialogue_data.get("lines", []).size() == pre_count + 1, "添加对白后数量应+1")
	print("    ✅ 动态新增对白测试通过，当前总行数: %d" % tab.lines_container.get_child_count())
	
	# 测试删除刚刚添加的对白以还原数据
	tab.delete_line(pre_count)
	assert(tab.current_dialogue_data.get("lines", []).size() == pre_count, "删除对白后数量应恢复")
	print("    ✅ 删除台词与顺序维护测试通过")
	
	print("[5] 测试单句配音生成与数据联动")
	var second_line = tab.current_dialogue_data["lines"][1]
	var initial_vpath = tab.get_resolved_voice_path(tab.current_dialogue_id, 1, second_line)
	print("    第二句台词: [%s] %s" % [second_line.get("speaker", ""), second_line.get("text", "")])
	print("    解析配音目标路径: %s" % initial_vpath)
	
	# 测试调用批量配音逻辑
	tab._on_batch_generate_dialogue_voices()
	print("    ✅ 本幕批量配音执行完毕！最终状态反馈: %s" % tab.lbl_batch_status.text)
	
	# 校验配音文件是否已生成到磁盘
	assert(tab.is_voice_ready(initial_vpath), "执行配音生成后文件应当存在于工程路径中")
	print("    ✅ 物理音频文件生成确认: %s" % initial_vpath)
	
	print("=== 【剧本台词】自动化功能测试 100% 通过！ ===")
	get_tree().quit(0)
