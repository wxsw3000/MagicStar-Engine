# engine/core/condition_checker.gd
# 通用条件表达式求值器（纯数据驱动判定）
class_name ConditionChecker
extends RefCounted

static func evaluate(conditions: Array, game_state: Node) -> bool:
	if conditions.is_empty():
		return true
	
	for cond in conditions:
		if not evaluate_single(cond, game_state):
			return false
	return true

static func evaluate_single(cond: Dictionary, game_state: Node) -> bool:
	var cond_type = cond.get("type", "")
	match cond_type:
		"has_clue":
			var clue_id = cond.get("id", "")
			return game_state.has_clue(clue_id)
			
		"not_has_clue":
			var clue_id = cond.get("id", "")
			return not game_state.has_clue(clue_id)
			
		"has_flag":
			var flag_key = cond.get("key", "")
			var expected_val = cond.get("value", true)
			return game_state.get_flag(flag_key) == expected_val
			
		"not_has_flag":
			var flag_key = cond.get("key", "")
			return not game_state.get_flag(flag_key, false)
			
		"task_completed":
			var task_id = cond.get("id", "")
			return game_state.is_task_completed(task_id)
			
		"point_visited":
			var point_id = cond.get("id", "")
			return game_state.is_point_visited(point_id)
			
		"not_point_visited":
			var point_id = cond.get("id", "")
			return not game_state.is_point_visited(point_id)
			
		"time_phase":
			var phase_id = cond.get("id", "")
			return game_state.current_time_phase == phase_id
			
		"character_state":
			var char_id = cond.get("character", "")
			var state_key = cond.get("key", "")
			var expected = cond.get("value", null)
			return game_state.get_character_state(char_id, state_key) == expected
			
		_:
			# 未知条件默认通过，并输出调试警告
			push_warning("Unknown condition type: %s" % cond_type)
			return true
