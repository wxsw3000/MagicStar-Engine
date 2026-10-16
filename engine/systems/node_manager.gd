# engine/systems/node_manager.gd
# 故事流与节点状态机管理器（统筹当前在剧情、探索、对话还是推理）
extends Node

var current_node_data: Dictionary = {}

func _ready() -> void:
	EventBus.dialogue_ended.connect(_on_dialogue_ended)
	EventBus.reasoning_succeeded.connect(_on_reasoning_succeeded)

func start_game(custom_node_id: String = "") -> void:
	var start_node_id = custom_node_id if not custom_node_id.is_empty() else DataManager.flow_config.get("start_node", "")
	if start_node_id.is_empty():
		push_error("[NodeManager] flow_config 中未配置 start_node！")
		return
	jump_to_node(start_node_id)

func jump_to_node(node_id: String) -> void:
	if node_id.is_empty():
		return
		
	var node_data = DataManager.get_node_data(node_id)
	if node_data.is_empty():
		push_error("[NodeManager] 找不到目标节点: %s" % node_id)
		return
		
	current_node_data = node_data
	GameState.current_node_id = node_id
	GameState.visited_nodes[node_id] = true
	
	# 如果该节点配置了 milestone（里程碑），自动记录时光机快照
	if node_data.get("is_milestone", false):
		GameState.record_milestone(node_data.get("title", "节点: " + node_id))
		
	# 如果该节点更新了时间阶段
	if node_data.has("time_phase"):
		GameState.set_time_phase(node_data["time_phase"])
		
	print("[NodeManager] 进入节点: %s (%s, 类型: %s)" % [node_id, node_data.get("title", ""), node_data.get("type", "")])
	EventBus.node_changed.emit(node_id, node_data)
	
	execute_node(node_data)

func execute_node(node_data: Dictionary) -> void:
	var node_type = node_data.get("type", "story")
	
	# 智能推导当前节点呈现的场景舞台 (确保剧情叙事、对白、举证质询均有对应的精美背景与氛围音效)
	var scene_id = node_data.get("scene", "")
	if scene_id.is_empty():
		var next_id = node_data.get("next", "")
		if not next_id.is_empty():
			var next_node = DataManager.get_node_data(next_id)
			scene_id = next_node.get("scene", "")
	if scene_id.is_empty() and not DataManager.scenes.is_empty():
		scene_id = DataManager.scenes.keys()[0]

	match node_type:
		"story", "dialogue":
			if not scene_id.is_empty():
				ExploreManager.enter_scene(scene_id, false)
			var diag_id = node_data.get("dialogue", "")
			if not diag_id.is_empty():
				DialogueManager.start_dialogue(diag_id)
			elif node_data.has("text"):
				# 直接由节点提供文本内容
				DialogueManager.start_inline_dialogue(node_data)
				
		"explore":
			var exp_scene = node_data.get("scene", scene_id)
			if not exp_scene.is_empty():
				ExploreManager.enter_scene(exp_scene, true)
				
		"reasoning":
			if not scene_id.is_empty():
				ExploreManager.enter_scene(scene_id, false)
			var reasoning_id = node_data.get("reasoning", node_data.get("reasoning_id", ""))
			if not reasoning_id.is_empty():
				ReasoningManager.start_reasoning(reasoning_id)
				
		"ending":
			if not scene_id.is_empty():
				ExploreManager.enter_scene(scene_id, false)
			var ending_id = node_data.get("ending", node_data.get("ending_id", ""))
			var ending_data = DataManager.get_ending_data(ending_id)
			EventBus.ending_triggered.emit(ending_id, ending_data)
			var diag_id = node_data.get("dialogue", "")
			if not diag_id.is_empty():
				DialogueManager.start_dialogue(diag_id)
			
		_:
			push_warning("[NodeManager] 未知节点类型: %s" % node_type)

func _on_dialogue_ended(next_target: String) -> void:
	var target = next_target
	if target.is_empty():
		target = current_node_data.get("next", "")
	if not target.is_empty():
		jump_to_node(target)

func _on_reasoning_succeeded(_reasoning_id: String, success_data: Dictionary) -> void:
	var next_node = success_data.get("next_node", "")
	if not next_node.is_empty():
		jump_to_node(next_node)
