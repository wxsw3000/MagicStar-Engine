# tools/test_main_direct_boot.gd
extends Control

func _ready() -> void:
	print("--- 验证 main.tscn 直接启动状态 ---")
	var root_node = load("res://scenes/main.tscn").instantiate()
	add_child(root_node)
	
	await get_tree().create_timer(0.3).timeout
	print("当前活动工程: ", ProjectContext.get_active_project_title())
	print("当前节点: ", GameState.current_node_id)
	print("当前场景: ", GameState.current_scene_id)
	print("背景贴图: ", root_node.bg_texture.texture)
	print("说话人: ", root_node.speaker_label.text)
	print("对白内容: ", root_node.content_label.text)
	print("对话系统激活状态: ", DialogueManager.is_active)
	
	assert(root_node.bg_texture.texture != null, "直接启动时背景贴图绝不可为空！")
	assert(DialogueManager.is_active, "直接启动时对白系统必须处于激活状态！")
	assert(not root_node.content_label.text.is_empty(), "对白内容绝不可为空！")
	
	# 触发点击推进对话
	var click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(500, 500)
	root_node._input(click)
	
	await get_tree().create_timer(0.2).timeout
	print("点击推进后说话人: ", root_node.speaker_label.text)
	print("点击推进后立绘可见性: ", root_node.char_portrait.visible)
	print("点击推进后立绘贴图: ", root_node.char_portrait.texture)
	assert(root_node.speaker_label.text == "水岛悠斗", "推进后应为水岛悠斗")
	assert(root_node.char_portrait.visible, "立绘必须可见")
	assert(root_node.char_portrait.texture != null, "立绘贴图必须有效")
	print("=== main.tscn 原生直接启动与点击推进 100% 验证成功！ ===")
	get_tree().quit(0)
