# engine/core/data_manager.gd
# 数据层核心加载器与校验器（完全与剧情内容解耦）
extends Node

const DATA_ROOT = "res://data/"
const CONFIG_ROOT = "res://config/"

var game_config: Dictionary = {}
var flow_config: Dictionary = {}

var nodes: Dictionary = {}
var scenes: Dictionary = {}
var dialogues: Dictionary = {}
var clues: Dictionary = {}
var tasks: Dictionary = {}
var characters: Dictionary = {}
var reasonings: Dictionary = {}
var endings: Dictionary = {}

func _ready() -> void:
	# 数据层已全面升级为自包含工程模式，完全由 ProjectContext 统一按项目动态注入
	# 不再在启动时加载废弃残留的 res://data/ 目录，避免冲掉当前工程数据
	pass

func load_all_data() -> void:
	print("[DataManager] 开始加载数据配置...")
	load_configs()
	
	nodes = load_directory_json(DATA_ROOT + "nodes")
	scenes = load_directory_json(DATA_ROOT + "scenes")
	dialogues = load_directory_json(DATA_ROOT + "dialogues")
	clues = load_directory_json(DATA_ROOT + "clues")
	tasks = load_directory_json(DATA_ROOT + "tasks")
	characters = load_directory_json(DATA_ROOT + "characters")
	reasonings = load_directory_json(DATA_ROOT + "reasonings")
	endings = load_directory_json(DATA_ROOT + "endings")
	
	print("[DataManager] 数据加载完成:")
	print(" - 节点: %d, 场景: %d, 对话: %d" % [nodes.size(), scenes.size(), dialogues.size()])
	print(" - 线索: %d, 任务: %d, 角色: %d" % [clues.size(), tasks.size(), characters.size()])
	print(" - 推理: %d, 结局: %d" % [reasonings.size(), endings.size()])
	
	validate_data()

func load_configs() -> void:
	game_config = load_json_file(CONFIG_ROOT + "game_config.json")
	flow_config = load_json_file(CONFIG_ROOT + "flow_config.json")

func load_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("[DataManager] 配置文件不存在: %s" % path)
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[DataManager] 无法读取文件: %s" % path)
		return {}
	var json_text = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("[DataManager] JSON解析错误 (%s): 行 %d, %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	var result = json.data
	if result is Dictionary:
		return result
	return {}

func save_json_file(path: String, data: Variant) -> bool:
	var dir_path = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("[DataManager] 无法写入文件: %s" % path)
		return false
	var json_string = JSON.stringify(data, "\t")
	file.store_string(json_string)
	file.close()
	return true

func save_item(category: String, id: String, data: Dictionary) -> bool:
	var dir_path = DATA_ROOT + category
	var file_path = dir_path + "/" + id + ".json"
	var success = save_json_file(file_path, data)
	if success:
		match category:
			"nodes": nodes[id] = data
			"scenes": scenes[id] = data
			"dialogues": dialogues[id] = data
			"clues": clues[id] = data
			"tasks": tasks[id] = data
			"characters": characters[id] = data
			"reasonings": reasonings[id] = data
			"endings": endings[id] = data
		validate_data()
	return success

func delete_item(category: String, id: String) -> bool:
	var file_path = DATA_ROOT + category + "/" + id + ".json"
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
	match category:
		"nodes": nodes.erase(id)
		"scenes": scenes.erase(id)
		"dialogues": dialogues.erase(id)
		"clues": clues.erase(id)
		"tasks": tasks.erase(id)
		"characters": characters.erase(id)
		"reasonings": reasonings.erase(id)
		"endings": endings.erase(id)
	validate_data()
	return true

func save_game_config(data: Dictionary) -> bool:
	game_config = data
	return save_json_file(CONFIG_ROOT + "game_config.json", data)

func save_flow_config(data: Dictionary) -> bool:
	flow_config = data
	return save_json_file(CONFIG_ROOT + "flow_config.json", data)

func load_directory_json(dir_path: String) -> Dictionary:
	var result: Dictionary = {}
	if not DirAccess.dir_exists_absolute(dir_path):
		return result
		
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				var full_path = dir_path + "/" + file_name
				var data = load_json_file(full_path)
				# 支持单文件包含单个对象 (带 id) 或 包含多个对象的数组
				if data.has("id"):
					result[data["id"]] = data
				elif data.has("items") and data["items"] is Array:
					for item in data["items"]:
						if item is Dictionary and item.has("id"):
							result[item["id"]] = item
			file_name = dir.get_next()
		dir.list_dir_end()
	return result

# 安全数据获取器
func get_node_data(id: String) -> Dictionary:
	return nodes.get(id, {})

func get_scene_data(id: String) -> Dictionary:
	return scenes.get(id, {})

func get_dialogue_data(id: String) -> Dictionary:
	return dialogues.get(id, {})

func get_clue_data(id: String) -> Dictionary:
	return clues.get(id, {})

func get_task_data(id: String) -> Dictionary:
	return tasks.get(id, {})

func get_character_data(id: String) -> Dictionary:
	return characters.get(id, {})

func get_reasoning_data(id: String) -> Dictionary:
	return reasonings.get(id, {})

func get_ending_data(id: String) -> Dictionary:
	return endings.get(id, {})

# 数据一致性静态校验（防止配置错误导致游戏崩溃）
func validate_data() -> void:
	var warnings_count = 0
	# 检查任务引用的线索
	for task_id in tasks:
		var task = tasks[task_id]
		for req_clue in task.get("required_clues", []):
			if not clues.has(req_clue):
				push_warning("[校验警告] 任务 '%s' 依赖的线索 '%s' 未在线索表中找到！" % [task_id, req_clue])
				warnings_count += 1
				
	# 检查推理引用的线索
	for res_id in reasonings:
		var reasoning = reasonings[res_id]
		for req_clue in reasoning.get("required_clues", []):
			if not clues.has(req_clue):
				push_warning("[校验警告] 推理 '%s' 依赖的线索 '%s' 未在线索表中找到！" % [res_id, req_clue])
				warnings_count += 1
				
	if warnings_count == 0:
		print("[DataManager] ✅ 所有数据配置校验通过，无死链。")
	else:
		push_warning("[DataManager] ⚠️ 数据校验发现 %d 处潜在问题，请检查 JSON 配置！" % warnings_count)
