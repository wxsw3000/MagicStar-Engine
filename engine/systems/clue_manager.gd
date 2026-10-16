# engine/systems/clue_manager.gd
# 搜证与线索笔记本管理器
extends Node

func _ready() -> void:
	pass

# 获取当前玩家已解锁的所有线索详情列表
func get_obtained_clues_data(category_filter: String = "") -> Array:
	var result = []
	for clue_id in GameState.obtained_clues:
		var data = DataManager.get_clue_data(clue_id)
		if not data.is_empty():
			if category_filter.is_empty() or data.get("type", "") == category_filter:
				result.append(data)
	return result

# 检查一组线索中是否包含指定线索
func has_clue(clue_id: String) -> bool:
	return GameState.has_clue(clue_id)

# 获取某条线索的关联线索列表（若已解锁）
func get_unlocked_related_clues(clue_id: String) -> Array:
	var data = DataManager.get_clue_data(clue_id)
	var related_ids = data.get("related_clues", [])
	var unlocked = []
	for r_id in related_ids:
		if GameState.has_clue(r_id):
			unlocked.append(DataManager.get_clue_data(r_id))
	return unlocked
