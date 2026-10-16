# tools/test_ui_reasoning.gd
extends Control

func _ready() -> void:
	print("--- 开始自动化 UI 推理与弹窗流程全真验证 ---")
	call_deferred("test_flow")

func test_flow() -> void:
	var main_packed = load("res://scenes/main.tscn")
	var main_scene = main_packed.instantiate()
	add_child(main_scene)
	await get_tree().create_timer(0.2).timeout
	
	print("[1] 初始状态验证")
	assert(not main_scene.notebook_modal.visible, "NotebookModal 初始应为隐藏")
	assert(not main_scene.reasoning_modal.visible, "ReasoningModal 初始应为隐藏")
	assert(not main_scene.modal_backdrop.visible, "ModalBackdrop 初始应为隐藏")
	print("    ✅ 初始模态窗口状态正常")
	
	print("[2] 添加证据线索并测试独立随身笔记本")
	GameState.obtain_clue("clue_broken_clock")
	GameState.obtain_clue("clue_sleeping_pills")
	
	main_scene.open_notebook()
	await get_tree().create_timer(0.1).timeout
	assert(main_scene.notebook_modal.visible, "NotebookModal 应为打开状态")
	assert(main_scene.modal_backdrop.visible, "ModalBackdrop 应为打开状态")
	assert(not main_scene.reasoning_modal.visible, "ReasoningModal 不应打开")
	assert(main_scene.notebook_clue_list.get_child_count() == 2, "笔记本应收录2条线索")
	print("    ✅ 随身笔记本独立打开测试通过，收录线索数: %d" % main_scene.notebook_clue_list.get_child_count())
	
	main_scene.close_notebook()
	assert(not main_scene.notebook_modal.visible, "NotebookModal 应关闭")
	assert(not main_scene.modal_backdrop.visible, "ModalBackdrop 应关闭")
	print("    ✅ 随身笔记本独立关闭测试通过")
	
	print("[3] 启动一体化举证台 (ReasoningArena)")
	ReasoningManager.start_reasoning("reason_01_clock")
	await get_tree().create_timer(0.2).timeout
	
	assert(main_scene.reasoning_modal.visible, "ReasoningModal 应为可见")
	assert(main_scene.modal_backdrop.visible, "ModalBackdrop 应为可见")
	assert(not main_scene.notebook_modal.visible, "【重要】NotebookModal 绝对不能与 ReasoningModal 同时可见！")
	print("    ✅ 关键验证成功：一体化举证台独立呈现，完全无弹窗叠放！")
	
	assert(main_scene.reasoning_clue_list.get_child_count() == 2, "举证台左侧应直接列出所有已获证据")
	print("    ✅ 举证台证据卡片数量正常: %d" % main_scene.reasoning_clue_list.get_child_count())
	
	print("[4] 测试选择错误证据出示（残留药粉）")
	main_scene.select_reasoning_clue("clue_sleeping_pills")
	assert(main_scene.selected_reasoning_clue == "clue_sleeping_pills", "选定证据应更新")
	assert("残留药粉" in main_scene.reasoning_detail_title.text, "右侧详情卡片标题应显示选中线索")
	
	main_scene._on_submit_reasoning_pressed()
	await get_tree().create_timer(0.2).timeout
	
	assert(main_scene.reasoning_modal.visible, "出示错误证据后，举证台应保持打开，不让玩家被迫重新点开！")
	assert("💡 破绽驳回" in main_scene.reasoning_hint_label.text, "举证台底部应即时提示错误破绽分析: " + main_scene.reasoning_hint_label.text)
	print("    ✅ 错误证据提交与原位即时反馈验证通过: %s" % main_scene.reasoning_hint_label.text)
	
	print("[5] 测试切换并出示正确证据（卡死的落地钟）")
	main_scene.select_reasoning_clue("clue_broken_clock")
	assert(main_scene.selected_reasoning_clue == "clue_broken_clock", "选定证据应更新为落地钟")
	assert("落地钟" in main_scene.reasoning_detail_title.text, "右侧详情卡片标题应显示落地钟")
	
	main_scene._on_submit_reasoning_pressed()
	await get_tree().create_timer(0.3).timeout
	
	assert(not main_scene.reasoning_modal.visible, "推理成功后，举证台应优雅关闭")
	assert(not main_scene.modal_backdrop.visible, "遮罩应一并关闭")
	print("    ✅ 正确举证成功！一体化举证台流程完美闭环！")
	
	print("=== 自动化 UI 流程全部通过验证！无任何重叠与死锁！ ===")
	get_tree().quit(0)
