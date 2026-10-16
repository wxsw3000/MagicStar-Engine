# engine/systems/explore_manager.gd
# 2D 点击式场景搜证与探索管理器
extends Node

const ConditionChecker = preload("res://engine/core/condition_checker.gd")

var current_scene_data: Dictionary = {}
var is_exploring: bool = false

func _ready() -> void:
	EventBus.explore_point_clicked.connect(interact_point)

func enter_scene(scene_id: String, enable_explore: bool = true) -> void:
	var data = DataManager.get_scene_data(scene_id)
	if data.is_empty():
		push_error("[ExploreManager] 场景不存在: %s" % scene_id)
		return
		
	current_scene_data = data
	GameState.current_scene_id = scene_id
	is_exploring = enable_explore
	
	print("[ExploreManager] 进入场景: %s (%s, 探索模式: %s)" % [scene_id, data.get("name", ""), enable_explore])
	EventBus.scene_changed.emit(scene_id, data)
	EventBus.explore_mode_changed.emit(enable_explore)

func get_active_explore_points() -> Array:
	var result = []
	for pt in current_scene_data.get("explore_points", []):
		var point_id = pt.get("id", "")
		# 检查开放条件
		var conds = pt.get("conditions", [])
		if not ConditionChecker.evaluate(conds, GameState):
			continue
			
		# 检查一次性调查点是否已被调查
		var is_once = pt.get("type", "repeatable") == "once"
		var visited = GameState.is_point_visited(point_id)
		if is_once and visited:
			continue
			
		var pt_copy = pt.duplicate()
		pt_copy["visited"] = visited
		result.append(pt_copy)
	return result

func interact_point(point_id: String, _point_data: Dictionary = {}) -> void:
	var target_pt: Dictionary = {}
	for pt in current_scene_data.get("explore_points", []):
		if pt.get("id", "") == point_id:
			target_pt = pt
			break
			
	if target_pt.is_empty():
		return
		
	GameState.mark_point_visited(point_id)
	
	# 执行触发结果
	var trigger = target_pt.get("trigger", {})
	var action_type = trigger.get("action", "")
	var target_val = trigger.get("target", "")
	
	if trigger.has("set_flag"):
		var f = trigger["set_flag"]
		GameState.set_flag(f.get("key", ""), f.get("value", true))
		
	# 1. 获得线索触发
	if action_type == "clue" or trigger.has("obtain_clue"):
		var clue_id = target_val if action_type == "clue" else trigger["obtain_clue"]
		if not clue_id.is_empty():
			GameState.obtain_clue(clue_id)
			var cdata = DataManager.get_clue_data(clue_id)
			var ctitle = cdata.get("title", clue_id)
			var cdesc = cdata.get("description", "")
			var protag = DataManager.game_config.get("protagonist_name", DataManager.game_config.get("protagonist", "侦探"))
			DialogueManager.start_inline_dialogue({
				"speaker": protag,
				"text": "【%s】\n%s" % [ctitle, cdesc]
			})
			return

	# 2. 跳转剧情节点触发
	if action_type == "jump_node" or trigger.has("next_node"):
		var target_node = target_val if action_type == "jump_node" else trigger["next_node"]
		if not target_node.is_empty():
			is_exploring = false
			EventBus.explore_mode_changed.emit(false)
			NodeManager.jump_to_node(target_node)
			return

	# 3. 触发对话
	if action_type == "dialogue" or trigger.has("dialogue"):
		var diag_id = target_val if action_type == "dialogue" else trigger["dialogue"]
		if not diag_id.is_empty():
			DialogueManager.start_dialogue(diag_id)
			return
			
	if trigger.has("inspection_text"):
		DialogueManager.start_inline_dialogue({
			"speaker": "旁白",
			"text": trigger["inspection_text"]
		})
