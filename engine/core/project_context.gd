# engine/core/project_context.gd
# 全局工程上下文管理器：管理多案件工程目录、project.json 读写与资产路径映射
extends Node

signal project_loaded(project_dir: String, project_data: Dictionary)
signal project_saved(project_dir: String)

const PROJECTS_ROOT = "res://projects/"
const DEFAULT_PROJECT_DIR = "res://projects/case_01_storm_villa/"

var active_project_dir: String = ""
var active_project_data: Dictionary = {}

# --- 统一资产注册表缓存 (Asset Registry Cache) ---
var _asset_index_by_id: Dictionary = {}
var _character_portraits: Dictionary = {}
var _scene_backgrounds: Dictionary = {}
var _audio_by_id: Dictionary = {}

func _ready() -> void:
	ensure_projects_root()
	ensure_active_project_loaded()

func ensure_active_project_loaded() -> void:
	if not active_project_dir.is_empty() and not DataManager.nodes.is_empty():
		return
		
	# 1. 检查命令行启动参数：--project=...
	var target_project = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--project="):
			target_project = arg.substr("--project=".length())
		elif arg.begins_with("++project="):
			target_project = arg.substr("++project=".length())
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--project="):
			target_project = arg.substr("--project=".length())
		elif arg.begins_with("++project="):
			target_project = arg.substr("++project=".length())
			
	if not target_project.is_empty() and FileAccess.file_exists(target_project.path_join("project.json")):
		load_project(target_project)
		return

	# 2. 检查本地上次选中的工程持久化记录 (开发与调试期便利)
	if FileAccess.file_exists("user://last_active_project.txt"):
		var f = FileAccess.open("user://last_active_project.txt", FileAccess.READ)
		if f:
			var saved_p = f.get_as_text().strip_edges()
			f.close()
			if not saved_p.is_empty() and FileAccess.file_exists(saved_p.path_join("project.json")):
				load_project(saved_p)
				return

	# 3. 扫描工程列表 (独立打包发行时自动加载包内包含的唯一案件工程)
	var list = get_projects_list()
	if not list.is_empty():
		load_project(list[0]["dir_path"])

func ensure_projects_root() -> void:
	var abs_path = ProjectSettings.globalize_path(PROJECTS_ROOT)
	if not DirAccess.dir_exists_absolute(abs_path):
		DirAccess.make_dir_recursive_absolute(abs_path)

# --- 获取所有案件工程列表 ---
func get_projects_list() -> Array:
	ensure_projects_root()
	var list: Array = []
	var dir = DirAccess.open(PROJECTS_ROOT)
	if not dir:
		return list
		
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if dir.current_is_dir() and not fname.begins_with("."):
			var sub_path = PROJECTS_ROOT + fname + "/"
			var pjson_path = sub_path + "project.json"
			if FileAccess.file_exists(pjson_path):
				var pdata = load_json_file(pjson_path)
				var meta = pdata.get("meta", {})
				var nodes = pdata.get("nodes", {})
				var assets = pdata.get("asset_manifest", [])
				
				# 封面推断 (优先寻找实际存在的文件：自包含沙盒 > 场景定义 > 素材清单)
				var cover = meta.get("cover_image", "")
				if cover.is_empty() or not FileAccess.file_exists(cover):
					var scs = pdata.get("scenes", {})
					if scs is Dictionary:
						for sc_id in scs:
							var sc_bg = scs[sc_id].get("background", "")
							if not sc_bg.is_empty():
								if FileAccess.file_exists(sc_bg):
									cover = sc_bg
									break
								elif FileAccess.file_exists(sub_path + sc_bg):
									cover = sub_path + sc_bg
									break
								elif sc_bg.begins_with("res://assets/") and FileAccess.file_exists(sub_path + sc_bg.substr("res://".length())):
									cover = sub_path + sc_bg.substr("res://".length())
									break
				if cover.is_empty() or not FileAccess.file_exists(cover):
					for it in assets:
						if it.get("type", "") == "background" and not it.get("local_path", "").is_empty():
							var lp = it.get("local_path", "")
							if FileAccess.file_exists(lp):
								cover = lp
								break
							elif FileAccess.file_exists(sub_path + lp):
								cover = sub_path + lp
								break
							elif lp.begins_with("res://assets/") and FileAccess.file_exists(sub_path + lp.substr("res://".length())):
								cover = sub_path + lp.substr("res://".length())
								break
							
				list.append({
					"dir_path": sub_path,
					"folder_name": fname,
					"title": meta.get("game_title", pdata.get("game_config", {}).get("game_title", fname)),
					"author": meta.get("author", "未知作者"),
					"description": meta.get("description", "案件工程"),
					"cover_image": cover,
					"updated_at": meta.get("updated_at", "近期修改"),
					"nodes_count": nodes.size(),
					"assets_count": assets.size(),
					"data": pdata
				})
		fname = dir.get_next()
	dir.list_dir_end()
	return list

# --- 新建案件工程 ---
func create_project(folder_name: String, title: String, author: String, desc: String) -> Dictionary:
	var safe_folder = folder_name.strip_edges().replace(" ", "_").replace("/", "").replace("\\", "")
	if safe_folder.is_empty():
		safe_folder = "case_" + str(Time.get_unix_time_from_system())
		
	var target_dir = PROJECTS_ROOT + safe_folder + "/"
	var abs_target = ProjectSettings.globalize_path(target_dir)
	if DirAccess.dir_exists_absolute(abs_target):
		return {"success": false, "message": "该工程文件夹已存在: " + safe_folder}
		
	DirAccess.make_dir_recursive_absolute(abs_target.path_join("assets/images/backgrounds"))
	DirAccess.make_dir_recursive_absolute(abs_target.path_join("assets/images/characters"))
	DirAccess.make_dir_recursive_absolute(abs_target.path_join("assets/audio/bgm"))
	DirAccess.make_dir_recursive_absolute(abs_target.path_join("assets/audio/voice"))
	DirAccess.make_dir_recursive_absolute(abs_target.path_join("assets/audio/sfx"))
	
	var template_data = {
		"$schema": "https://magicstar.avg/schema/v1/project_master.json",
		"version": "1.0.0",
		"meta": {
			"game_title": title,
			"author": author,
			"description": desc,
			"created_at": Time.get_datetime_string_from_system(),
			"updated_at": Time.get_datetime_string_from_system()
		},
		"ai_settings": {
			"comfyui_server": "http://127.0.0.1:8188",
			"comfyui_user": "",
			"comfyui_password": "",
			"checkpoint": "sd_xl_turbo_1.0.safetensors",
			"global_style_prompt": "masterpiece, best quality, anime visual novel, dark mystery, dramatic lighting",
			"global_negative_prompt": "worst quality, low quality, blurry, text, watermark, bad anatomy, deformed limbs",
			"character_base_prompt": "solo, waist-up portrait, standing pose, white background",
			"bg_base_prompt": "scenery, background, highly detailed, no humans",
			"tts_voice_default": "zh-CN-XiaoxiaoNeural"
		},
		"game_config": {
			"game_title": title,
			"author": author,
			"version": "0.1.0",
			"protagonist_name": "侦探"
		},
		"flow_config": {
			"start_node": "node_01_intro"
		},
		"nodes": {
			"node_01_intro": {
				"id": "node_01_intro",
				"title": "序幕开启",
				"type": "story",
				"dialogue": "diag_01_intro"
			}
		},
		"scenes": {
			"scene_01_crime_scene": {
				"id": "scene_01_crime_scene",
				"name": "案发现场",
				"background": target_dir + "assets/images/backgrounds/bg_scene_01.png",
				"interactive_points": []
			}
		},
		"characters": {
			"detective": {
				"id": "detective",
				"name": "侦探",
				"role": "侦探主角"
			}
		},
		"dialogues": {
			"diag_01_intro": {
				"id": "diag_01_intro",
				"lines": [
					{
						"speaker": "旁白",
						"text": "新的悬案拉开了序幕，真理等待着被揭示。"
					}
				]
			}
		},
		"clues": {},
		"reasonings": {},
		"endings": {},
		"tasks": {},
		"asset_manifest": [
			{
				"id": "bg_scene_01",
				"type": "background",
				"name": "案发现场背景",
				"prompt": "crime scene, dark interior room, dramatic cinematic lighting",
				"local_path": target_dir + "assets/images/backgrounds/bg_scene_01.png",
				"width": 1920,
				"height": 1080,
				"status": "pending"
			}
		]
	}
	
	var file = FileAccess.open(target_dir + "project.json", FileAccess.WRITE)
	if not file:
		return {"success": false, "message": "无法创建 project.json"}
	file.store_string(JSON.stringify(template_data, "\t"))
	file.close()
	
	load_project(target_dir)
	return {"success": true, "path": target_dir, "title": title}

# --- 从外部 JSON 文件一键导入并自动创建独立案件工程 ---
func import_project_from_json(json_file_path: String, custom_folder_name: String = "") -> Dictionary:
	if not FileAccess.file_exists(json_file_path):
		return {"success": false, "message": "指定的 JSON 文件不存在: " + json_file_path}
		
	var file = FileAccess.open(json_file_path, FileAccess.READ)
	if not file:
		return {"success": false, "message": "无法读取文件: " + json_file_path}
		
	var raw_text = file.get_as_text().strip_edges()
	file.close()
	
	# 智能容错：自动剔除 Markdown 代码块 (```json ... ```) 与前后多余非 JSON 文本
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
		return {"success": false, "message": "JSON 格式非法: 行 %d - %s" % [json.get_error_line(), json.get_error_message()]}
		
	var data: Dictionary = json.data
	
	# 读取元数据
	var meta = data.get("meta", {})
	var gconf = data.get("game_config", {})
	var title = meta.get("game_title", gconf.get("game_title", "未命名案件"))
	var author = meta.get("author", gconf.get("author", "侦探作者"))
	var desc = meta.get("description", gconf.get("description", "AVG 推理案情工程"))
	
	# 自动推导工程文件夹名称
	var folder_name = custom_folder_name.strip_edges()
	if folder_name.is_empty():
		if meta.has("project_id") and not str(meta["project_id"]).is_empty():
			folder_name = str(meta["project_id"]).strip_edges().replace(" ", "_").replace("/", "").replace("\\", "")
		else:
			folder_name = "case_" + str(int(Time.get_unix_time_from_system()))
			
	var target_dir = PROJECTS_ROOT + folder_name + "/"
	var abs_target = ProjectSettings.globalize_path(target_dir)
	# 如果已存在同名工程，自动附加时间戳避免覆盖
	if DirAccess.dir_exists_absolute(abs_target):
		folder_name += "_" + str(int(Time.get_unix_time_from_system()) % 10000)
		target_dir = PROJECTS_ROOT + folder_name + "/"
		abs_target = ProjectSettings.globalize_path(target_dir)
		
	# 创建自包含工程目录结构
	DirAccess.make_dir_recursive_absolute(abs_target.path_join("assets/images/backgrounds"))
	DirAccess.make_dir_recursive_absolute(abs_target.path_join("assets/images/characters"))
	DirAccess.make_dir_recursive_absolute(abs_target.path_join("assets/audio/bgm"))
	DirAccess.make_dir_recursive_absolute(abs_target.path_join("assets/audio/voice"))
	DirAccess.make_dir_recursive_absolute(abs_target.path_join("assets/audio/sfx"))
	
	# 规范化 meta 与 ai_settings
	if not data.has("meta") or not (data["meta"] is Dictionary):
		data["meta"] = {}
	data["meta"]["game_title"] = title
	data["meta"]["author"] = author
	data["meta"]["description"] = desc
	data["meta"]["created_at"] = Time.get_datetime_string_from_system()
	data["meta"]["updated_at"] = Time.get_datetime_string_from_system()
	
	if not data.has("game_config") or not (data["game_config"] is Dictionary):
		data["game_config"] = {}
	data["game_config"]["game_title"] = title
	data["game_config"]["author"] = author
	data["game_config"]["version"] = data["game_config"].get("version", "1.0.0")
	data["game_config"]["protagonist_name"] = data["game_config"].get("protagonist_name", "侦探")
	
	# 确保 flow_config 完整存在且有 start_node
	if not data.has("flow_config") or not (data["flow_config"] is Dictionary):
		data["flow_config"] = {}
	if not data["flow_config"].has("start_node") or str(data["flow_config"]["start_node"]).is_empty():
		var n_dict = normalize_dict(data.get("nodes", {}))
		if n_dict.has("node_01_intro"):
			data["flow_config"]["start_node"] = "node_01_intro"
		elif n_dict.has("node_01"):
			data["flow_config"]["start_node"] = "node_01"
		elif not n_dict.is_empty():
			data["flow_config"]["start_node"] = n_dict.keys()[0]
	
	if not data.has("ai_settings") or not (data["ai_settings"] is Dictionary):
		data["ai_settings"] = {
			"comfyui_server": "http://127.0.0.1:8188",
			"comfyui_user": "",
			"comfyui_password": "",
			"checkpoint": "sd_xl_turbo_1.0.safetensors",
			"global_style_prompt": "masterpiece, best quality, anime visual novel, dark mystery, dramatic lighting",
			"global_negative_prompt": "worst quality, low quality, blurry, text, watermark, bad anatomy, deformed limbs",
			"character_base_prompt": "solo, waist-up portrait, standing pose, white background",
			"bg_base_prompt": "scenery, background, highly detailed, no humans",
			"tts_voice_default": "zh-CN-XiaoxiaoNeural"
		}
		
	# 资产清单 (asset_manifest) 自动补齐与相对路径校正
	var manifest = data.get("asset_manifest", [])
	if manifest.is_empty():
		manifest = []
		var scenes_dict = normalize_dict(data.get("scenes", {}))
		for sc_id in scenes_dict:
			var sc = scenes_dict[sc_id]
			manifest.append({
				"id": "bg_" + sc_id,
				"name": sc.get("name", sc_id) + " 场景背景",
				"type": "background",
				"prompt": sc.get("prompt", sc.get("name", "mystery interior room")),
				"negative_prompt": "",
				"local_path": target_dir + "assets/images/backgrounds/bg_" + sc_id + ".png",
				"width": 1920,
				"height": 1080,
				"status": "pending"
			})
			sc["background"] = target_dir + "assets/images/backgrounds/bg_" + sc_id + ".png"
			
		var char_dict = normalize_dict(data.get("characters", {}))
		for ch_id in char_dict:
			var ch = char_dict[ch_id]
			manifest.append({
				"id": "char_" + ch_id,
				"name": ch.get("name", ch_id) + " 半身立绘",
				"type": "character",
				"prompt": ch.get("prompt", ch.get("name", "anime detective character")),
				"negative_prompt": "",
				"local_path": target_dir + "assets/images/characters/char_" + ch_id + ".png",
				"width": 1024,
				"height": 1440,
				"status": "pending"
			})
			
		var diag_dict = normalize_dict(data.get("dialogues", {}))
		for d_id in diag_dict:
			var diag = diag_dict[d_id]
			var lines = diag.get("lines", [])
			for line_idx in range(lines.size()):
				var line = lines[line_idx]
				if not (line is Dictionary):
					continue
				var text = line.get("text", "")
				if text.is_empty():
					continue
				var v_id = "voice_%s_%d" % [d_id, line_idx + 1]
				var raw_v = line.get("voice", "")
				if not raw_v.is_empty():
					v_id = raw_v.get_file().get_basename()
				else:
					line["voice"] = target_dir + "assets/audio/voice/" + v_id + ".mp3"
					
				var speaker = line.get("speaker", "旁白")
				var voice_role = "zh-CN-YunxiNeural"
				if speaker == "旁白":
					voice_role = "zh-CN-YunyangNeural"
				elif "女" in speaker or "千鹤" in speaker or "真理子" in speaker or "妻" in speaker or "小姐" in speaker:
					voice_role = "zh-CN-XiaoxiaoNeural"
				elif "源治" in speaker or "老" in speaker or "守护人" in speaker or "医生" in speaker:
					voice_role = "zh-CN-YunjianNeural"
				elif char_dict.has(speaker) and char_dict[speaker].has("voice"):
					voice_role = char_dict[speaker]["voice"]

				manifest.append({
					"id": v_id,
					"name": "%s 配音 (%s)" % [speaker, text.left(8) + ("..." if text.length() > 8 else "")],
					"type": "voice",
					"role": speaker,
					"text": text,
					"voice_role": voice_role,
					"local_path": target_dir + "assets/audio/voice/" + v_id + ".mp3",
					"status": "pending"
				})

		data["asset_manifest"] = manifest
	else:
		for it in manifest:
			if it is Dictionary:
				var m_type = it.get("type", "background")
				var it_id = it.get("id", "asset_" + str(int(Time.get_unix_time_from_system())))
				if m_type == "background":
					it["local_path"] = target_dir + "assets/images/backgrounds/" + it_id + ".png"
				elif m_type == "character":
					it["local_path"] = target_dir + "assets/images/characters/" + it_id + ".png"
				elif m_type == "bgm":
					it["local_path"] = target_dir + "assets/audio/bgm/" + it_id + ".mp3"
				elif m_type == "voice":
					it["local_path"] = target_dir + "assets/audio/voice/" + it_id + ".mp3"
				elif m_type == "sfx":
					it["local_path"] = target_dir + "assets/audio/sfx/" + it_id + ".wav"
					
	# 写入 project.json
	var out_file = FileAccess.open(target_dir + "project.json", FileAccess.WRITE)
	if not out_file:
		return {"success": false, "message": "无法写入目标工程 project.json"}
	out_file.store_string(JSON.stringify(data, "\t"))
	out_file.close()
	
	# 立即载入新工程
	load_project(target_dir)
	
	var n_count = data.get("nodes", {}).size() if data.get("nodes") is Dictionary else data.get("nodes", []).size()
	var sc_count = data.get("scenes", {}).size() if data.get("scenes") is Dictionary else data.get("scenes", []).size()
	var cl_count = data.get("clues", {}).size() if data.get("clues") is Dictionary else data.get("clues", []).size()
	
	return {
		"success": true,
		"path": target_dir,
		"title": title,
		"folder_name": folder_name,
		"nodes_count": n_count,
		"scenes_count": sc_count,
		"clues_count": cl_count,
		"assets_count": manifest.size()
	}

# --- 删除指定案件工程 ---
func delete_project(project_dir: String) -> Dictionary:
	var pdir = project_dir
	if not pdir.ends_with("/"):
		pdir += "/"
	var abs_dir = ProjectSettings.globalize_path(pdir)
	if not DirAccess.dir_exists_absolute(abs_dir):
		return {"success": false, "message": "工程目录不存在: " + abs_dir}
		
	# 如果当前活动的是要删除的工程，安全解除活动绑定
	if active_project_dir == pdir:
		active_project_dir = ""
		active_project_data = {}
		
	var err = OS.move_to_trash(abs_dir)
	if err != OK or DirAccess.dir_exists_absolute(abs_dir):
		err = _remove_dir_recursive(abs_dir)
		
	if err == OK or not DirAccess.dir_exists_absolute(abs_dir):
		return {"success": true, "message": "工程文件夹已成功删除"}
	return {"success": false, "message": "删除工程文件夹失败，错误码: %d" % err}

func _remove_dir_recursive(path: String) -> Error:
	var dir = DirAccess.open(path)
	if not dir:
		return FAILED
	dir.list_dir_begin()
	var item = dir.get_next()
	while item != "":
		if item != "." and item != "..":
			var sub_path = path.path_join(item)
			if dir.current_is_dir():
				var err = _remove_dir_recursive(sub_path)
				if err != OK:
					return err
			else:
				var err = DirAccess.remove_absolute(sub_path)
				if err != OK:
					return err
		item = dir.get_next()
	dir.list_dir_end()
	return DirAccess.remove_absolute(path)

# --- 导出指定案件工程主文件 ---
func export_project_json(project_dir: String, dest_file_path: String) -> Dictionary:
	var pdir = project_dir
	if not pdir.ends_with("/"):
		pdir += "/"
	var pjson = pdir + "project.json"
	if not FileAccess.file_exists(pjson):
		return {"success": false, "message": "工程主文件不存在: " + pjson}
		
	var file = FileAccess.open(pjson, FileAccess.READ)
	if not file:
		return {"success": false, "message": "无法读取源工程文件: " + pjson}
	var content = file.get_as_text()
	file.close()
	
	var dest_dir = dest_file_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dest_dir):
		DirAccess.make_dir_recursive_absolute(dest_dir)
		
	var out_file = FileAccess.open(dest_file_path, FileAccess.WRITE)
	if not out_file:
		return {"success": false, "message": "无法创建导出目标文件: " + dest_file_path}
	out_file.store_string(content)
	out_file.close()
	
	return {"success": true, "message": "已成功导出项目主 JSON！", "path": dest_file_path}

# --- 载入指定工程 ---
func load_project(project_dir: String) -> bool:
	var pdir = project_dir
	if not pdir.ends_with("/"):
		pdir += "/"
	var pjson_path = pdir + "project.json"
	if not FileAccess.file_exists(pjson_path):
		push_error("[ProjectContext] 未找到工程定义: " + pjson_path)
		return false
		
	var data = load_json_file(pjson_path)
	if data.is_empty():
		return false
		
	active_project_dir = pdir
	active_project_data = data
	
	# 同步至底层 DataManager (确保项目间完全隔离，不残留旧工程数据)
	DataManager.game_config = data.get("game_config", {}) if (data.get("game_config") is Dictionary) else {}
	DataManager.flow_config = data.get("flow_config", {}) if (data.get("flow_config") is Dictionary) else {}
	DataManager.nodes = normalize_dict(data.get("nodes", {}))
	DataManager.scenes = normalize_dict(data.get("scenes", {}))
	DataManager.dialogues = normalize_dict(data.get("dialogues", {}))
	DataManager.clues = normalize_dict(data.get("clues", {}))
	DataManager.reasonings = normalize_dict(data.get("reasonings", {}))
	DataManager.endings = normalize_dict(data.get("endings", {}))
	DataManager.characters = normalize_dict(data.get("characters", {}))
	DataManager.tasks = normalize_dict(data.get("tasks", {}))
		
	# 校验与广播
	DataManager.validate_data()
	
	# 运行时与编辑器解耦：仅当处于编辑器环境时才同步 AI 配置与清单
	if ResourceLoader.exists("res://editor/core/ai_asset_manager.gd"):
		var AIAssetMgr = load("res://editor/core/ai_asset_manager.gd")
		if AIAssetMgr:
			if data.has("ai_settings") and data["ai_settings"] is Dictionary:
				AIAssetMgr.save_ai_settings(data["ai_settings"])
			if data.has("asset_manifest") and data["asset_manifest"] is Array:
				AIAssetMgr.save_manifest(data["asset_manifest"])
		
	rebuild_asset_registry()
	
	var pref_file = FileAccess.open("user://last_active_project.txt", FileAccess.WRITE)
	if pref_file:
		pref_file.store_string(active_project_dir)
		pref_file.close()

	print("[ProjectContext] ✅ 成功载入工程: %s (%s)" % [get_active_project_title(), active_project_dir])
	project_loaded.emit(active_project_dir, active_project_data)
	return true

# --- 保存当前工程 ---
func save_active_project() -> bool:
	if active_project_dir.is_empty():
		return false
	var pjson_path = active_project_dir + "project.json"
	
	# 刷新元信息
	var meta = active_project_data.get("meta", {})
	meta["updated_at"] = Time.get_datetime_string_from_system()
	active_project_data["meta"] = meta
	
	active_project_data["game_config"] = DataManager.game_config
	active_project_data["flow_config"] = DataManager.flow_config
	active_project_data["nodes"] = DataManager.nodes
	active_project_data["scenes"] = DataManager.scenes
	active_project_data["dialogues"] = DataManager.dialogues
	active_project_data["clues"] = DataManager.clues
	active_project_data["tasks"] = DataManager.tasks
	active_project_data["characters"] = DataManager.characters
	active_project_data["reasonings"] = DataManager.reasonings
	active_project_data["endings"] = DataManager.endings
	
	if ResourceLoader.exists("res://editor/core/ai_asset_manager.gd"):
		var AIAssetMgr = load("res://editor/core/ai_asset_manager.gd")
		if AIAssetMgr:
			active_project_data["ai_settings"] = AIAssetMgr.load_ai_settings()
			active_project_data["asset_manifest"] = AIAssetMgr.load_manifest()
	
	var file = FileAccess.open(pjson_path, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify(active_project_data, "\t"))
	file.close()
	
	rebuild_asset_registry()
	print("[ProjectContext] 💾 已将当前修改存盘回: " + pjson_path)
	project_saved.emit(active_project_dir)
	return true

func get_active_project_title() -> String:
	return active_project_data.get("meta", {}).get("game_title", DataManager.game_config.get("game_title", "未命名工程"))

# ========================================================
# --- 统一资产注册表中心 (Unified Asset Registry & Resolver) ---
# ========================================================

func rebuild_asset_registry() -> void:
	_asset_index_by_id.clear()
	_character_portraits.clear()
	_scene_backgrounds.clear()
	_audio_by_id.clear()

	if active_project_dir.is_empty() and active_project_data.is_empty():
		return

	# 1. 索引 asset_manifest 中的全部已登记资产项 (最高优先级)
	var manifest = active_project_data.get("asset_manifest", [])
	if manifest is Array:
		for item in manifest:
			if not (item is Dictionary):
				continue
			var aid = item.get("id", "")
			var lp = item.get("local_path", "")
			var atype = item.get("type", "")
			var aname = item.get("name", "")
			var resolved_p = resolve_asset_path(lp)

			if not aid.is_empty():
				_asset_index_by_id[aid] = resolved_p

			if atype == "character":
				var cid = item.get("character_id", "")
				if not cid.is_empty():
					_character_portraits[cid] = resolved_p
				if not aname.is_empty():
					_character_portraits[aname] = resolved_p
				if not aid.is_empty():
					_character_portraits[aid] = resolved_p
			elif atype == "background":
				if not aid.is_empty():
					_scene_backgrounds[aid] = resolved_p
					if aid.begins_with("bg_"):
						_scene_backgrounds[aid.substr(3)] = resolved_p
				if not aname.is_empty():
					_scene_backgrounds[aname] = resolved_p
			elif atype in ["bgm", "sfx", "voice"]:
				if not aid.is_empty():
					_audio_by_id[aid] = resolved_p

	# 2. 索引 characters 字典
	var chars = active_project_data.get("characters", {})
	if chars is Dictionary:
		for cid in chars:
			var c = chars[cid]
			var cname = c.get("name", "")
			var portrait = c.get("portrait", "")
			if not portrait.is_empty():
				var resolved = resolve_asset_path(portrait)
				if is_valid_file(resolved):
					_character_portraits[cid] = resolved
					if not cname.is_empty():
						_character_portraits[cname] = resolved

	# 3. 索引 scenes 字典
	var scs = active_project_data.get("scenes", {})
	if scs is Dictionary:
		for sid in scs:
			var sc = scs[sid]
			var sname = sc.get("name", "")
			var bg = sc.get("background", "")
			if not bg.is_empty():
				var resolved = resolve_asset_path(bg)
				if is_valid_file(resolved):
					_scene_backgrounds[sid] = resolved
					if not sname.is_empty():
						_scene_backgrounds[sname] = resolved
			var sbgm = sc.get("bgm", "")
			if not sbgm.is_empty():
				var resolved_bgm = resolve_asset_path(sbgm)
				if is_valid_file(resolved_bgm):
					_audio_by_id[sid + "_bgm"] = resolved_bgm
					_audio_by_id[sid] = resolved_bgm

	# 4. 扫描沙盒物理目录，动态补齐 ComfyUI / TTS 最新生成的文件
	_scan_sandbox_media_files()

func _scan_sandbox_media_files() -> void:
	if active_project_dir.is_empty():
		return
		
	# 扫描人物立绘
	var char_dir = active_project_dir + "assets/images/characters/"
	var abs_char_dir = ProjectSettings.globalize_path(char_dir)
	if DirAccess.dir_exists_absolute(abs_char_dir):
		var dir = DirAccess.open(char_dir)
		if dir:
			dir.list_dir_begin()
			var fn = dir.get_next()
			while fn != "":
				if not dir.current_is_dir() and fn.ends_with(".png"):
					var base_no_ext = fn.get_basename()
					var full_p = char_dir + fn
					_asset_index_by_id[base_no_ext] = full_p
					_character_portraits[base_no_ext] = full_p
					# 模糊别名匹配：例如 char_char_assistant 匹配 char_assistant 与 水岛悠斗
					var chars = active_project_data.get("characters", {})
					if chars is Dictionary:
						for cid in chars:
							if cid in base_no_ext:
								_character_portraits[cid] = full_p
								var cname = chars[cid].get("name", "")
								if not cname.is_empty():
									_character_portraits[cname] = full_p
				fn = dir.get_next()
			dir.list_dir_end()

	# 扫描场景背景
	var bg_dir = active_project_dir + "assets/images/backgrounds/"
	var abs_bg_dir = ProjectSettings.globalize_path(bg_dir)
	if DirAccess.dir_exists_absolute(abs_bg_dir):
		var dir = DirAccess.open(bg_dir)
		if dir:
			dir.list_dir_begin()
			var fn = dir.get_next()
			while fn != "":
				if not dir.current_is_dir() and fn.ends_with(".png"):
					var base_no_ext = fn.get_basename()
					var full_p = bg_dir + fn
					_asset_index_by_id[base_no_ext] = full_p
					_scene_backgrounds[base_no_ext] = full_p
					var scs = active_project_data.get("scenes", {})
					if scs is Dictionary:
						for sid in scs:
							if sid in base_no_ext:
								_scene_backgrounds[sid] = full_p
								var sname = scs[sid].get("name", "")
								if not sname.is_empty():
									_scene_backgrounds[sname] = full_p
				fn = dir.get_next()
			dir.list_dir_end()

	# 扫描音频
	for sub in ["bgm", "sfx", "voice"]:
		var aud_dir = active_project_dir + "assets/audio/" + sub + "/"
		var abs_aud_dir = ProjectSettings.globalize_path(aud_dir)
		if DirAccess.dir_exists_absolute(abs_aud_dir):
			var dir = DirAccess.open(aud_dir)
			if dir:
				dir.list_dir_begin()
				var fn = dir.get_next()
				while fn != "":
					if not dir.current_is_dir() and (fn.ends_with(".wav") or fn.ends_with(".mp3") or fn.ends_with(".ogg")):
						var base_no_ext = fn.get_basename()
						var full_p = aud_dir + fn
						_asset_index_by_id[base_no_ext] = full_p
						_audio_by_id[base_no_ext] = full_p
					fn = dir.get_next()
				dir.list_dir_end()

# --- 业务层唯一 ID 解析入口 ---

func get_character_portrait(identifier: String, expression: String = "") -> String:
	if identifier.is_empty() or identifier == "旁白":
		return ""
		
	# 1. 优先尝试特定表情差分，例如 "char_assistant_nervous" 或 "水岛悠斗_nervous"
	if not expression.is_empty() and expression != "normal":
		var expr_key = identifier + "_" + expression
		if _character_portraits.has(expr_key) and is_valid_file(_character_portraits[expr_key]):
			return _character_portraits[expr_key]
		for k in _character_portraits:
			if (identifier in k) and (expression in k) and is_valid_file(_character_portraits[k]):
				return _character_portraits[k]
		if _asset_index_by_id.has(expr_key) and is_valid_file(_asset_index_by_id[expr_key]):
			return _asset_index_by_id[expr_key]

	# 2. 回退到标准基础立绘匹配
	if _character_portraits.has(identifier):
		var p = _character_portraits[identifier]
		if is_valid_file(p):
			return p
	for k in _character_portraits:
		if identifier in k or k in identifier:
			var p = _character_portraits[k]
			if is_valid_file(p):
				return p
	if _asset_index_by_id.has(identifier):
		var p = _asset_index_by_id[identifier]
		if is_valid_file(p):
			return p
	var direct = resolve_asset_path(identifier)
	return direct if is_valid_file(direct) else ""

func get_scene_background(identifier: String) -> String:
	if identifier.is_empty():
		return get_default_background()
	if _scene_backgrounds.has(identifier):
		var p = _scene_backgrounds[identifier]
		if is_valid_file(p):
			return p
	for k in _scene_backgrounds:
		if identifier in k or k in identifier:
			var p = _scene_backgrounds[k]
			if is_valid_file(p):
				return p
	if _asset_index_by_id.has(identifier):
		var p = _asset_index_by_id[identifier]
		if is_valid_file(p):
			return p
	var direct = resolve_asset_path(identifier)
	if is_valid_file(direct):
		return direct
	return get_default_background()

func get_default_background() -> String:
	for k in _scene_backgrounds:
		var p = _scene_backgrounds[k]
		if is_valid_file(p):
			return p
	return ""

func get_bgm(identifier: String) -> String:
	if not identifier.is_empty():
		if _audio_by_id.has(identifier):
			var p = _audio_by_id[identifier]
			if is_valid_file(p):
				return p
		if _asset_index_by_id.has(identifier):
			var p = _asset_index_by_id[identifier]
			if is_valid_file(p):
				return p
		var direct = resolve_asset_path(identifier)
		if is_valid_file(direct):
			return direct
	return get_default_bgm_path()

func get_default_bgm_path() -> String:
	if is_valid_file("res://engine/assets/audio/bgm/bgm_suspense_rain.wav"):
		return "res://engine/assets/audio/bgm/bgm_suspense_rain.wav"
	if is_valid_file("res://assets/audio/bgm/bgm_suspense_rain.wav"):
		return "res://assets/audio/bgm/bgm_suspense_rain.wav"
	return ""

func get_default_sfx_path(identifier: String) -> String:
	var engine_preset = "res://engine/assets/audio/sfx/" + identifier + ".wav"
	if is_valid_file(engine_preset):
		return engine_preset
	var preset = "res://assets/audio/sfx/" + identifier + ".wav"
	if is_valid_file(preset):
		return preset
	return ""

func get_voice(identifier: String) -> String:
	if identifier.is_empty():
		return ""
	if _audio_by_id.has(identifier):
		var p = _audio_by_id[identifier]
		if is_valid_file(p):
			return p
	if _asset_index_by_id.has(identifier):
		var p = _asset_index_by_id[identifier]
		if is_valid_file(p):
			return p
	var direct = resolve_asset_path(identifier)
	return direct if is_valid_file(direct) else ""

func get_sfx(identifier: String) -> String:
	if identifier.is_empty():
		return ""
	if _audio_by_id.has(identifier):
		var p = _audio_by_id[identifier]
		if is_valid_file(p):
			return p
	if _asset_index_by_id.has(identifier):
		var p = _asset_index_by_id[identifier]
		if is_valid_file(p):
			return p
	var default_sfx = get_default_sfx_path(identifier)
	if not default_sfx.is_empty():
		return default_sfx
	var direct = resolve_asset_path(identifier)
	return direct if is_valid_file(direct) else ""

func resolve_asset(identifier: String, type_hint: String = "") -> String:
	if identifier.is_empty():
		return ""
	match type_hint:
		"character":
			return get_character_portrait(identifier)
		"scene", "background":
			return get_scene_background(identifier)
		"bgm":
			return get_bgm(identifier)
		"voice":
			return get_voice(identifier)
		"sfx":
			return get_sfx(identifier)
			
	if _asset_index_by_id.has(identifier):
		return _asset_index_by_id[identifier]
	if _character_portraits.has(identifier):
		return _character_portraits[identifier]
	if _scene_backgrounds.has(identifier):
		return _scene_backgrounds[identifier]
	if _audio_by_id.has(identifier):
		return _audio_by_id[identifier]
		
	return resolve_asset_path(identifier)

func is_valid_file(path: String) -> bool:
	if path.is_empty():
		return false
	if ResourceLoader.exists(path):
		return true
	if FileAccess.file_exists(path):
		return true
	var abs_p = ProjectSettings.globalize_path(path)
	return FileAccess.file_exists(abs_p)

# --- 资产物理路径安全解析 (底层沙盒相对路径映射) ---
func resolve_asset_path(raw_path: String) -> String:
	if raw_path.is_empty():
		return ""
		
	# 1. 优先在当前工程中寻找文件
	if not active_project_dir.is_empty():
		var in_proj = active_project_dir + raw_path
		if is_valid_file(in_proj):
			return in_proj
			
		if raw_path.begins_with(active_project_dir) and is_valid_file(raw_path):
			return raw_path
			
		if raw_path.begins_with("res://assets/"):
			var sub_path = raw_path.substr("res://".length())
			var mapped_proj = active_project_dir + sub_path
			if is_valid_file(mapped_proj):
				return mapped_proj
				
	# 2. 次选全局存在的文件
	if is_valid_file(raw_path):
		return raw_path
		
	return raw_path

# --- 通用纹理加载器 (支持导入资源、PCK/APK打包资源与独立外部图像) ---
func load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			return res
	if FileAccess.file_exists(path):
		var buffer = FileAccess.get_file_as_bytes(path)
		if not buffer.is_empty():
			var img = Image.new()
			var err = img.load_png_from_buffer(buffer)
			if err != OK:
				err = img.load_jpg_from_buffer(buffer)
			if err != OK:
				err = img.load_webp_from_buffer(buffer)
			if err == OK:
				return ImageTexture.create_from_image(img)
	var abs_p = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_p):
		var img = Image.new()
		if img.load(abs_p) == OK:
			return ImageTexture.create_from_image(img)
	return null

# --- 工具函数 ---
func load_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		return json.data
	return {}

func normalize_dict(val: Variant) -> Dictionary:
	var result = {}
	if val is Dictionary:
		return val
	elif val is Array:
		for item in val:
			if item is Dictionary and item.has("id"):
				result[item["id"]] = item
	return result
