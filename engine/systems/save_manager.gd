# engine/systems/save_manager.gd
# 存档与读档管理器（纯数据快照读写）
extends Node

const SAVE_PATH_TEMPLATE = "user://save_slot_%d.json"

func save_game(slot: int = 1) -> bool:
	var snapshot = GameState.create_snapshot()
	snapshot["save_time"] = Time.get_datetime_string_from_system()
	snapshot["slot"] = slot
	
	var file_path = SAVE_PATH_TEMPLATE % slot
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		push_error("[SaveManager] 无法写入存档: %s" % file_path)
		return false
		
	var json_string = JSON.stringify(snapshot, "\t")
	file.store_string(json_string)
	print("[SaveManager] 存档成功: %s" % file_path)
	EventBus.notification_requested.emit("游戏已存档至 栏位 %d" % slot, "system")
	return true

func load_game(slot: int = 1) -> bool:
	var file_path = SAVE_PATH_TEMPLATE % slot
	if not FileAccess.file_exists(file_path):
		EventBus.notification_requested.emit("该栏位无存档数据", "warning")
		return false
		
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return false
		
	var json_text = file.get_as_text()
	var json = JSON.new()
	if json.parse(json_text) != OK:
		push_error("[SaveManager] 存档损坏解析失败: %s" % file_path)
		return false
		
	var snapshot = json.data
	GameState.restore_from_snapshot(snapshot, false)
	print("[SaveManager] 读档成功: %s" % file_path)
	EventBus.notification_requested.emit("已加载 栏位 %d 存档" % slot, "system")
	return true

func has_save(slot: int = 1) -> bool:
	var file_path = SAVE_PATH_TEMPLATE % slot
	return FileAccess.file_exists(file_path)
