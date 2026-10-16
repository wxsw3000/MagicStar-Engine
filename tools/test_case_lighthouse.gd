# tools/test_case_lighthouse.gd
extends Control

func _ready() -> void:
	print("--- 开始调试 case_snowbound_lighthouse 运行时状态 ---")
	call_deferred("run_debug")

func run_debug() -> void:
	await get_tree().create_timer(0.1).timeout
	
	# 1. 载入工程
	var proj_path = "res://projects/case_snowbound_lighthouse/"
	var ok = ProjectContext.load_project(proj_path)
	print("[1] 载入工程: ", ok, " 标题: ", ProjectContext.get_active_project_title())
	assert(ok, "工程载入必须成功")
	
	# 2. 检查 flow_config 与起始节点
	print("[2] flow_config: ", DataManager.flow_config)
	var start_node = DataManager.flow_config.get("start_node", "")
	assert(start_node == "node_01_intro", "起始节点必须为 node_01_intro")
	
	# 3. 实例化 main.tscn
	var main_scene = load("res://scenes/main.tscn").instantiate()
	add_child(main_scene)
	await get_tree().create_timer(0.2).timeout
	
	print("[3] main 场景初始化完成:")
	print("    bg_texture.texture: ", main_scene.bg_texture.texture)
	assert(main_scene.bg_texture.texture != null, "初始剧情必须有背景图呈现，严禁黑屏！")
	print("    bgm_player.playing: ", main_scene.bgm_player.playing)
	assert(main_scene.bgm_player.playing, "氛围 BGM 必须开始播放，严禁静音！")
	print("    dialogue_box.visible: ", main_scene.dialogue_box.visible)
	assert(main_scene.dialogue_box.visible, "序幕对白框必须可见")
	print("    speaker_label: ", main_scene.speaker_label.text)
	print("    content_label: ", main_scene.content_label.text)
	print("    char_portrait.visible (旁白时): ", main_scene.char_portrait.visible)
	assert(not main_scene.char_portrait.visible, "旁白时不应显示立绘")
	
	# 4. 模拟点击推进对话至第2句 (水岛悠斗发言)
	print("[4] 模拟触发点击推进对话 (InputEventMouseButton)")
	var click_evt = InputEventMouseButton.new()
	click_evt.button_index = MOUSE_BUTTON_LEFT
	click_evt.pressed = true
	click_evt.position = Vector2(500, 500)
	main_scene._input(click_evt)
	await get_tree().create_timer(0.1).timeout
	
	print("    第2句说话人: ", main_scene.speaker_label.text)
	assert(main_scene.speaker_label.text == "水岛悠斗", "第2句应为水岛悠斗")
	print("    char_portrait.visible (水岛悠斗): ", main_scene.char_portrait.visible)
	print("    char_portrait.texture: ", main_scene.char_portrait.texture)
	assert(main_scene.char_portrait.visible, "角色发言时立绘必须自动匹配并显示！")
	assert(main_scene.char_portrait.texture != null, "角色立绘贴图不可为空！")
	
	# 5. 模拟继续点击至第3句 (相马千鹤发言)
	main_scene._input(click_evt)
	await get_tree().create_timer(0.1).timeout
	print("    第3句说话人: ", main_scene.speaker_label.text)
	assert(main_scene.speaker_label.text == "相马千鹤", "第3句应为相马千鹤")
	assert(main_scene.char_portrait.visible, "相马千鹤立绘必须自动显示！")
	
	# 6. 点击推进完毕整个 intro
	while DialogueManager.is_active:
		main_scene._input(click_evt)
		await get_tree().create_timer(0.05).timeout
		
	await get_tree().create_timer(0.2).timeout
	print("[5] 对话推进完毕后节点状态:")
	print("    当前节点 ID: ", GameState.current_node_id)
	assert(GameState.current_node_id == "node_02_explore_top", "应顺利推进至搜证节点 node_02_explore_top")
	print("    当前场景 ID: ", GameState.current_scene_id)
	assert(GameState.current_scene_id == "scene_lighthouse_top", "场景应切换至灯室 scene_lighthouse_top")
	print("    is_exploring: ", ExploreManager.is_exploring)
	assert(ExploreManager.is_exploring, "应处于搜证模式")
	print("    搜查热区控件数: ", main_scene.explore_container.get_child_count())
	assert(main_scene.explore_container.get_child_count() > 0, "搜查模式应有搜查点及导航推进按钮")
	
	print("=== case_snowbound_lighthouse 运行时验证 100% 通过！ ===")
	get_tree().quit(0)
