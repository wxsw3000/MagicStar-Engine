# engine/core/game_state.gd
# 运行时游戏状态管理与快照时光机（纯数据状态，可随时完整存读档）
extends Node

var current_node_id: String = ""
var current_scene_id: String = ""
var current_time_phase: String = "init"

# 运行时数据集合
var obtained_clues: Array = []
var active_tasks: Array = []
var completed_tasks: Array = []
var visited_points: Dictionary = {}
var visited_nodes: Dictionary = {}
var character_states: Dictionary = {}
var flags: Dictionary = {}

# 里程碑快照列表（用于时间线剧情回溯）
var milestones: Array = []

func _ready() -> void:
	EventBus.request_rewind_to_milestone.connect(restore_from_snapshot)

func reset_state() -> void:
	current_node_id = ""
	current_scene_id = ""
	current_time_phase = "init"
	obtained_clues.clear()
	active_tasks.clear()
	completed_tasks.clear()
	visited_points.clear()
	visited_nodes.clear()
	character_states.clear()
	flags.clear()
	milestones.clear()

# --- 线索管理 ---
func obtain_clue(clue_id: String) -> bool:
	if clue_id.is_empty():
		return false
	if clue_id in obtained_clues:
		return false
	obtained_clues.append(clue_id)
	var clue_data = DataManager.get_clue_data(clue_id)
	EventBus.clue_obtained.emit(clue_id, clue_data)
	EventBus.notification_requested.emit("获得线索: %s" % clue_data.get("name", clue_id), "clue")
	return true

func has_clue(clue_id: String) -> bool:
	return clue_id in obtained_clues

# --- 标记 Flags 管理 ---
func set_flag(key: String, value: Variant = true) -> void:
	flags[key] = value

func get_flag(key: String, default_val: Variant = false) -> Variant:
	return flags.get(key, default_val)

# --- 探索点管理 ---
func mark_point_visited(point_id: String) -> void:
	visited_points[point_id] = true

func is_point_visited(point_id: String) -> bool:
	return visited_points.get(point_id, false)

# --- 任务管理 ---
func start_task(task_id: String) -> void:
	if not task_id in active_tasks and not task_id in completed_tasks:
		active_tasks.append(task_id)
		var task_data = DataManager.get_task_data(task_id)
		EventBus.task_started.emit(task_id, task_data)
		EventBus.notification_requested.emit("新目标: %s" % task_data.get("name", task_id), "task")

func complete_task(task_id: String) -> void:
	if task_id in active_tasks:
		active_tasks.erase(task_id)
	if not task_id in completed_tasks:
		completed_tasks.append(task_id)
		var task_data = DataManager.get_task_data(task_id)
		EventBus.task_completed.emit(task_id, task_data)
		EventBus.notification_requested.emit("完成调查: %s" % task_data.get("name", task_id), "success")
		# 自动发放奖励
		var reward = task_data.get("reward", {})
		for c in reward.get("clues", []):
			obtain_clue(c)

func is_task_completed(task_id: String) -> bool:
	return task_id in completed_tasks

# --- 角色状态 ---
func set_character_state(char_id: String, state_key: String, state_val: Variant) -> void:
	if not character_states.has(char_id):
		character_states[char_id] = {}
	character_states[char_id][state_key] = state_val
	EventBus.character_state_changed.emit(char_id, state_key, state_val)

func get_character_state(char_id: String, state_key: String, default_val: Variant = null) -> Variant:
	if character_states.has(char_id):
		return character_states[char_id].get(state_key, default_val)
	return default_val

# --- 时间阶段 ---
func set_time_phase(phase_id: String) -> void:
	current_time_phase = phase_id
	var phase_info = DataManager.flow_config.get("phases", {}).get(phase_id, {})
	EventBus.time_phase_changed.emit(phase_id, phase_info)

# --- 快照与时光机回溯 ---
func record_milestone(title: String) -> void:
	var snapshot = create_snapshot()
	snapshot["milestone_id"] = "ms_%d" % (milestones.size() + 1)
	snapshot["title"] = title
	snapshot["timestamp"] = Time.get_datetime_string_from_system()
	milestones.append(snapshot)
	EventBus.milestone_created.emit(snapshot["milestone_id"], title)

func create_snapshot() -> Dictionary:
	return {
		"current_node_id": current_node_id,
		"current_scene_id": current_scene_id,
		"current_time_phase": current_time_phase,
		"obtained_clues": obtained_clues.duplicate(),
		"active_tasks": active_tasks.duplicate(),
		"completed_tasks": completed_tasks.duplicate(),
		"visited_points": visited_points.duplicate(),
		"visited_nodes": visited_nodes.duplicate(),
		"character_states": character_states.duplicate(true),
		"flags": flags.duplicate()
	}

func restore_from_snapshot(snapshot: Dictionary, keep_clues: bool = true) -> void:
	var saved_clues = obtained_clues.duplicate()
	
	current_node_id = snapshot.get("current_node_id", "")
	current_scene_id = snapshot.get("current_scene_id", "")
	current_time_phase = snapshot.get("current_time_phase", "init")
	active_tasks = snapshot.get("active_tasks", []).duplicate()
	completed_tasks = snapshot.get("completed_tasks", []).duplicate()
	visited_points = snapshot.get("visited_points", {}).duplicate()
	visited_nodes = snapshot.get("visited_nodes", {}).duplicate()
	character_states = snapshot.get("character_states", {}).duplicate(true)
	flags = snapshot.get("flags", {}).duplicate()
	
	if keep_clues:
		# 智能回溯：保留已发现的线索，免去玩家重复搜证的枯燥
		for c in snapshot.get("obtained_clues", []):
			if not c in saved_clues:
				saved_clues.append(c)
		obtained_clues = saved_clues
	else:
		obtained_clues = snapshot.get("obtained_clues", []).duplicate()
		
	EventBus.notification_requested.emit("已回溯至节点: " + snapshot.get("title", current_node_id), "system")
	
	# 通知节点管理器重新跳转至该节点
	if not current_node_id.is_empty():
		NodeManager.jump_to_node(current_node_id)
