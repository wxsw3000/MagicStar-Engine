# editor/core/project_pack_manager.gd
# 全案总工程包导入/导出管理器：实现单文件大JSON与各模块文件间的无缝互转
class_name ProjectPackManager
extends RefCounted

const AIAssetMgr = preload("res://editor/core/ai_asset_manager.gd")

# 导出为全案一体化总工程包 (Master Project JSON)
static func export_master_json(file_path: String) -> Dictionary:
	var result = {"success": false, "message": "", "file_path": file_path}
	
	# 收集全部数据结构
	var master_data = {
		"$schema": "https://magicstar.avg/schema/v1/project_master.json",
		"version": "1.0.0",
		"exported_at": Time.get_datetime_string_from_system(),
		"meta": {
			"game_title": DataManager.game_config.get("game_title", "未命名案件"),
			"author": DataManager.game_config.get("author", "侦探作者"),
			"description": DataManager.game_config.get("description", "AVG 推理案情工程")
		},
		"ai_settings": AIAssetMgr.load_ai_settings(),
		"game_config": DataManager.game_config,
		"flow_config": DataManager.flow_config,
		"nodes": DataManager.nodes,
		"scenes": DataManager.scenes,
		"dialogues": DataManager.dialogues,
		"clues": DataManager.clues,
		"tasks": DataManager.tasks,
		"characters": DataManager.characters,
		"reasonings": DataManager.reasonings,
		"endings": DataManager.endings,
		"asset_manifest": AIAssetMgr.load_manifest()
	}
	
	var dir = file_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
		
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		result.message = "无法创建目标文件: " + file_path
		return result
		
	var json_str = JSON.stringify(master_data, "\t")
	file.store_string(json_str)
	file.close()
	
	result.success = true
	result.message = "全案总工程已成功导出！包含节点 %d 个，场景 %d 个，线索 %d 个，素材 %d 项。" % [
		DataManager.nodes.size(),
		DataManager.scenes.size(),
		DataManager.clues.size(),
		master_data["asset_manifest"].size()
	]
	return result

# 导入全案一体化总工程包并解包同步到各数据系统
static func import_master_json(file_path: String) -> Dictionary:
	var result = {"success": false, "message": "", "stats": {}}
	if not FileAccess.file_exists(file_path):
		result.message = "指定的总工程 JSON 文件不存在: " + file_path
		return result
		
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		result.message = "无法读取工程文件: " + file_path
		return result
		
	var raw_text = file.get_as_text().strip_edges()
	file.close()
	
	var clean_text = raw_text
	var first_brace = clean_text.find("{")
	var last_brace = clean_text.rfind("}")
	if first_brace != -1 and last_brace != -1 and last_brace > first_brace:
		clean_text = clean_text.substr(first_brace, last_brace - first_brace + 1)
	elif clean_text.begins_with("```"):
		var first_newline = clean_text.find("\n")
		if first_newline != -1:
			clean_text = clean_text.substr(first_newline + 1)
		if clean_text.ends_with("```"):
			clean_text = clean_text.substr(0, clean_text.length() - 3).strip_edges()
			
	var json = JSON.new()
	var err = json.parse(clean_text)
	if err != OK or not (json.data is Dictionary):
		result.message = "JSON 解析失败: 行 %d - %s" % [json.get_error_line(), json.get_error_message()]
		return result
		
	var data: Dictionary = json.data
	var stats = {}
	
	# 1. 解包配置
	if data.has("game_config") and data["game_config"] is Dictionary:
		DataManager.save_game_config(data["game_config"])
		stats["game_config"] = true
	if data.has("flow_config") and data["flow_config"] is Dictionary:
		DataManager.save_flow_config(data["flow_config"])
		stats["flow_config"] = true
	if data.has("ai_settings") and data["ai_settings"] is Dictionary:
		AIAssetMgr.save_ai_settings(data["ai_settings"])
		stats["ai_settings"] = true
		
	# 2. 解包核心剧情数据各目录
	stats["nodes"] = unpack_category("nodes", data.get("nodes", {}))
	stats["scenes"] = unpack_category("scenes", data.get("scenes", {}))
	stats["dialogues"] = unpack_category("dialogues", data.get("dialogues", {}))
	stats["clues"] = unpack_category("clues", data.get("clues", {}))
	stats["tasks"] = unpack_category("tasks", data.get("tasks", {}))
	stats["characters"] = unpack_category("characters", data.get("characters", {}))
	stats["reasonings"] = unpack_category("reasonings", data.get("reasonings", {}))
	stats["endings"] = unpack_category("endings", data.get("endings", {}))
	
	# 3. 解包资产清单
	if data.has("asset_manifest") and data["asset_manifest"] is Array:
		AIAssetMgr.save_manifest(data["asset_manifest"])
		stats["asset_manifest"] = data["asset_manifest"].size()
		
	# 重新加载底层数据系统并同步至工程主文件
	DataManager.load_all_data()
	ProjectContext.save_active_project()
	
	result.success = true
	result.stats = stats
	result.message = "工程导入解包完成！已同步节点 %d 个，场景 %d 个，素材清单 %d 项。" % [
		stats.get("nodes", 0),
		stats.get("scenes", 0),
		stats.get("asset_manifest", 0)
	]
	return result

static func unpack_category(category: String, dict_or_arr: Variant) -> int:
	var count = 0
	var items = {}
	if dict_or_arr is Dictionary:
		items = dict_or_arr
	elif dict_or_arr is Array:
		for item in dict_or_arr:
			if item is Dictionary and item.has("id"):
				items[item["id"]] = item
				
	for id in items:
		var item_data = items[id]
		if item_data is Dictionary:
			DataManager.save_item(category, str(id), item_data)
			count += 1
	return count
