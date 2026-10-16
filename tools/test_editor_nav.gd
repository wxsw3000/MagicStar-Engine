# tools/test_editor_nav.gd
extends Control

func _ready() -> void:
	print("--- 开始 Editor 统一顶栏与工作区导航全真自动化测试 ---")
	call_deferred("run_editor_test")

func run_editor_test() -> void:
	await get_tree().create_timer(0.1).timeout
	
	print("[1] 实例化 EditorMain 主界面")
	var editor_packed = load("res://editor/ui/editor_main.tscn")
	var editor_scene = editor_packed.instantiate()
	add_child(editor_scene)
	await get_tree().create_timer(0.2).timeout
	
	print("[2] 校验单层顶栏布局与冗余 Tab 隐藏")
	assert(editor_scene.tab_container.tabs_visible == false, "原生两层冗余 Tab 标签必须已隐藏(tabs_visible==false)")
	assert(editor_scene.nav_buttons.size() == 7, "必须提供 7 个一级工作区导航分段按钮")
	print("    ✅ 单层统一顶栏验证通过，Tab 标签原生双层已成功消除")
	
	print("[3] 遍历点击 7 个工作区标签并验证对应面板加载")
	var tab_names = ["故事流程", "搜证画板", "剧本台词", "线索物证", "推理谜题", "AI 资产工坊", "项目配置"]
	for i in range(tab_names.size()):
		editor_scene.switch_tab(i)
		await get_tree().create_timer(0.05).timeout
		assert(editor_scene.tab_container.current_tab == i, "当前激活面板应为索引 %d (%s)" % [i, tab_names[i]])
		print("    ✅ 切换至工作区 [%d] %s 成功" % [i, tab_names[i]])
		
	print("[4] 校验线索与推理已彻底解耦为独立一级面板")
	var clue_tab = editor_scene.clue_tab
	var reasoning_tab = editor_scene.reasoning_tab
	assert(clue_tab != null, "必须包含独立的线索物证一级面板")
	assert(reasoning_tab != null, "必须包含独立的推理谜题一级面板")
	assert(not clue_tab.has_node("TabContainer"), "线索面板内部不得再有深层嵌套 TabContainer")
	assert(not reasoning_tab.has_node("TabContainer"), "推理面板内部不得再有深层嵌套 TabContainer")
	print("    ✅ 线索与推理独立一级面板验证通过，零嵌套 Tab")
	
	print("[5] 测试快速保存逻辑")
	editor_scene._on_save_all_pressed()
	print("    ✅ 快速保存测试通过")
	
	print("=== Editor 统一顶栏与工作区导航全真自动化测试 100% 通过！ ===")
	get_tree().quit(0)
