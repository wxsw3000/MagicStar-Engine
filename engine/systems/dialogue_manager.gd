# engine/systems/dialogue_manager.gd
# 对话系统管理器（支持线性对白、条件分支、以及侦探盘问话题池）
extends Node

const ConditionChecker = preload("res://engine/core/condition_checker.gd")

var current_dialogue_data: Dictionary = {}
var current_lines: Array = []
var current_line_index: int = 0
var is_active: bool = false

# 盘问模式状态
var is_topic_mode: bool = false
var topic_source_dialogue: Dictionary = {}

func _ready() -> void:
	EventBus.dialogue_choice_selected.connect(_on_choice_selected)
	EventBus.dialogue_topic_selected.connect(_on_topic_selected)

func start_dialogue(dialogue_id: String) -> void:
	var data = DataManager.get_dialogue_data(dialogue_id)
	if data.is_empty():
		push_error("[DialogueManager] 找不到对话: %s" % dialogue_id)
		return
	setup_dialogue(data)

func start_inline_dialogue(node_data: Dictionary) -> void:
	var lines = []
	var speaker = node_data.get("speaker", "")
	var raw_text = node_data.get("text", [])
	if raw_text is Array:
		for t in raw_text:
			lines.append({"speaker": speaker, "text": t})
	elif raw_text is String:
		lines.append({"speaker": speaker, "text": raw_text})
		
	var data = {
		"id": node_data.get("id", "inline"),
		"lines": lines,
		"next": node_data.get("next", "")
	}
	setup_dialogue(data)

func setup_dialogue(data: Dictionary) -> void:
	current_dialogue_data = data
	is_active = true
	
	# 如果是话题池结构（侦探盘问）
	if data.has("topics") and data["topics"] is Array:
		open_topic_menu(data)
		return
		
	is_topic_mode = false
	current_lines = data.get("lines", [])
	current_line_index = 0
	
	EventBus.dialogue_started.emit(data.get("id", ""), data)
	show_current_line()

func advance() -> void:
	if not is_active:
		return
		
	# 如果当前有选择分支，必须等待玩家做选择，不能直接点下一步
	var cur_line = get_current_line_data()
	var has_line_choices = cur_line.has("choices") and cur_line["choices"].size() > 0
	var has_root_choices = (current_line_index == current_lines.size() - 1) and current_dialogue_data.has("choices") and current_dialogue_data["choices"].size() > 0
	if has_line_choices or has_root_choices:
		return
		
	current_line_index += 1
	if current_line_index < current_lines.size():
		show_current_line()
	else:
		end_dialogue()

func get_current_line_data() -> Dictionary:
	if current_line_index < current_lines.size():
		return current_lines[current_line_index]
	return {}

func show_current_line() -> void:
	var line = get_current_line_data()
	if line.is_empty():
		end_dialogue()
		return
		
	# 处理行内自带的触发效果（如自动获得线索或修改角色状态）
	if line.has("obtain_clue"):
		GameState.obtain_clue(line["obtain_clue"])
	if line.has("set_flag"):
		var f = line["set_flag"]
		GameState.set_flag(f.get("key", ""), f.get("value", true))
		
	EventBus.dialogue_line_displayed.emit(line)
	
	# 如果当前行有选项分支，或者最后一行挂载了整段对话的选项分支
	var choices_to_show = []
	if line.has("choices") and line["choices"] is Array:
		choices_to_show = line["choices"]
	elif (current_line_index == current_lines.size() - 1) and current_dialogue_data.has("choices") and current_dialogue_data["choices"] is Array:
		choices_to_show = current_dialogue_data["choices"]
		
	if choices_to_show.size() > 0:
		var valid_choices = []
		for choice in choices_to_show:
			var conds = choice.get("conditions", [])
			if ConditionChecker.evaluate(conds, GameState):
				valid_choices.append(choice)
		EventBus.dialogue_choices_requested.emit(valid_choices)

func _on_choice_selected(index: int) -> void:
	var line = get_current_line_data()
	var choices = line.get("choices", [])
	if choices.is_empty() and current_dialogue_data.has("choices") and current_dialogue_data["choices"] is Array:
		choices = current_dialogue_data["choices"]
		
	if index >= 0 and index < choices.size():
		var choice = choices[index]
		# 执行选择分支的效果
		if choice.has("obtain_clue"):
			GameState.obtain_clue(choice["obtain_clue"])
		if choice.has("next_dialogue"):
			start_dialogue(choice["next_dialogue"])
			return
		elif choice.has("next_node"):
			end_dialogue(choice["next_node"])
			return
			
	# 默认前进到下一行
	current_line_index += 1
	if current_line_index < current_lines.size():
		show_current_line()
	else:
		end_dialogue()

# --- 盘问话题池模式 ---
func open_topic_menu(data: Dictionary) -> void:
	is_topic_mode = true
	topic_source_dialogue = data
	var valid_topics = []
	for topic in data.get("topics", []):
		var conds = topic.get("conditions", [])
		if ConditionChecker.evaluate(conds, GameState):
			# 检查是否重复触发
			var topic_id = topic.get("id", "")
			var is_asked = GameState.get_flag("topic_asked_" + topic_id, false)
			var topic_copy = topic.duplicate()
			topic_copy["is_asked"] = is_asked
			valid_topics.append(topic_copy)
			
	EventBus.dialogue_topics_requested.emit(valid_topics)

func _on_topic_selected(topic_id: String) -> void:
	if topic_id == "exit":
		end_dialogue()
		return
		
	GameState.set_flag("topic_asked_" + topic_id, true)
	
	# 查找对应话题配置
	for topic in topic_source_dialogue.get("topics", []):
		if topic.get("id", "") == topic_id:
			# 播放该话题的对话内容
			current_lines = topic.get("lines", [])
			current_line_index = 0
			is_active = true
			EventBus.dialogue_started.emit(topic_id, topic)
			show_current_line()
			return

func end_dialogue(override_next: String = "") -> void:
	is_active = false
	var next_target = override_next
	if next_target.is_empty():
		next_target = current_dialogue_data.get("next", "")
		
	# 如果处于盘问模式且还有话题未退出，回到话题菜单；否则彻底结束
	if is_topic_mode and override_next.is_empty():
		open_topic_menu(topic_source_dialogue)
		return
		
	is_topic_mode = false
	EventBus.dialogue_ended.emit(next_target)
