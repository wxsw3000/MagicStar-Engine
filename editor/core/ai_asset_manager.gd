# editor/core/ai_asset_manager.gd
# AI 资产工坊核心管理器：管理配置、资产清单、ComfyUI生图与TTS调度
class_name AIAssetManager
extends RefCounted

const PoseMannequinClass = preload("res://editor/ui/pose_editor/pose_mannequin_3d.gd")
const AI_CONFIG_PATH = "res://config/ai_settings.json"
const MANIFEST_PATH = "res://data/assets/asset_manifest.json"

const STYLE_PRESETS = {
	"dark_mystery": {
		"id": "dark_mystery",
		"name": "🎬 本格悬疑黑金风 (默认)",
		"prompt": "本格悬疑推理日系动漫风格，精美二次元视觉小说立绘，剧场版光影，电影感，masterpiece, anime visual novel, dark mystery, cinematic lighting",
		"negative": "低质量，模糊，变形，多余肢体，文字，水印，worst quality, blurry, bad anatomy, deformed limbs"
	},
	"ghibli": {
		"id": "ghibli",
		"name": "🌿 宫崎骏 / 吉卜力手绘风",
		"prompt": "吉卜力动漫手绘水粉风格，宫崎骏美学，温暖治愈，高画质二次元插画，studio ghibli style, hand-painted anime illustration, soft warm lighting",
		"negative": "写实，3D塑料质感，现代CG，低质量，模糊，photorealistic, 3d render, worst quality"
	},
	"western_fantasy": {
		"id": "western_fantasy",
		"name": "🏰 欧美奇幻 / 写实风",
		"prompt": "欧美史诗奇幻写实插画，油画厚涂质感，伦勃朗戏剧性光影，cinematic realism, western fantasy concept art, oil painting texture",
		"negative": "二次元平涂，简笔卡通，多余肢体，低质量，flat anime, 2d cartoon, worst quality"
	},
	"japanese_wafuu": {
		"id": "japanese_wafuu",
		"name": "⛩️ 日式二次元 / 和风",
		"prompt": "精致和风日系动漫立绘，浮世绘古典优雅韵味，干净细腻线条，japanese anime visual novel, wafuu aesthetic, elegant traditional atmosphere",
		"negative": "美漫写实，3D模型，噪点，低质量，western comic, 3d, noisy, worst quality"
	},
	"chinese_guofeng": {
		"id": "chinese_guofeng",
		"name": "🏮 中式国风 / 仙侠水墨",
		"prompt": "典雅新中式国风插画，水墨意境晕染，朱砂与青黛配色，诗意唯美，chinese traditional aesthetics, elegant guofeng illustration, ink wash gradient",
		"negative": "西式魔幻，现代霓虹，杂乱涂鸦，低质量，western fantasy, neon, messy, worst quality"
	},
	"cute_chibi": {
		"id": "cute_chibi",
		"name": "🧸 卡通风 / Q版萌系",
		"prompt": "超可爱二次元Q版萌系插画，大眼萌化比例，清新马卡龙柔和色调，绘本风格，cute chibi style, kawaii 2D cartoon, rounded proportions",
		"negative": "写实恐怖，肌肉线条，阴暗怪诞，低质量，realistic, creepy, muscular, worst quality"
	},
	"dark_cthulhu": {
		"id": "dark_cthulhu",
		"name": "👁️ 暗黑 / 恐怖 / 克苏鲁",
		"prompt": "克苏鲁宇宙未知恐惧氛围，暗黑怪诞美学，冷色调迷雾与深渊阴影，lovecraftian cosmic horror, dark eerie atmosphere, eldritch shadows",
		"negative": "明亮温馨，可爱动漫，艳丽高饱和，低质量，bright, cheerful, cute, colorful, worst quality"
	},
	"pixel_retro": {
		"id": "pixel_retro",
		"name": "👾 像素 / 复古 16-bit",
		"prompt": "复古16位像素风视觉小说立绘，清晰像素边缘，点阵阴影质感，masterpiece pixel art, 16-bit retro visual novel, crisp pixel edges",
		"negative": "光滑渐变，平滑矢量，真实照片，低质量，smooth gradient, blurry, photograph, worst quality"
	},
	"watercolor_art": {
		"id": "watercolor_art",
		"name": "🎨 水彩 / 手绘 / 艺术画风",
		"prompt": "唯美梦幻水彩手绘，湿画法水痕肌理，纸质纹理与柔和色彩扩散，dreamy watercolor painting, delicate brush strokes, bleeding pigments",
		"negative": "数码塑料感，锐利生硬边缘，3D渲染，低质量，digital cgi, plastic 3d, sharp harsh lines, worst quality"
	}
}

static func get_style_preset_keys() -> Array:
	return STYLE_PRESETS.keys()

static func get_style_preset(preset_id: String) -> Dictionary:
	return STYLE_PRESETS.get(preset_id, STYLE_PRESETS["dark_mystery"])

static func get_python_executable() -> String:
	var candidates = [
		"C:/Users/63637/AppData/Local/Python/bin/python.exe",
		"python.exe",
		"python"
	]
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	return "python"

# --- 资产物理路径沙盒化：确保属于当前工程的素材 100% 写入工程专属 assets/ 目录 ---
static func get_sandboxed_asset_path(item: Dictionary) -> String:
	var pdir = ProjectContext.active_project_dir
	if pdir.is_empty():
		pdir = "res://projects/case_01_storm_villa/"
	if not pdir.ends_with("/"):
		pdir += "/"
		
	var item_type = item.get("type", "background")
	var item_id = item.get("id", "asset_" + str(int(Time.get_unix_time_from_system())))
	var ext = "png"
	var subfolder = "images/backgrounds"
	if item_type == "background":
		ext = "png"
		subfolder = "images/backgrounds"
	elif item_type == "character":
		ext = "png"
		subfolder = "images/characters"
	elif item_type == "bgm":
		ext = "wav"
		subfolder = "audio/bgm"
	elif item_type == "voice":
		ext = "mp3"
		subfolder = "audio/voice"
	elif item_type == "sfx":
		ext = "wav"
		subfolder = "audio/sfx"
		
	var raw_path = item.get("local_path", "")
	# 如果路径为空，或指向了全局遗留路径 res://assets/，或不包含本工程专属目录，强制定向到当前工程 assets 目录！
	if raw_path.is_empty() or raw_path.begins_with("res://assets/") or not raw_path.begins_with(pdir):
		var target_path = pdir + "assets/" + subfolder + "/" + item_id + "." + ext
		item["local_path"] = target_path
		return target_path
	return raw_path

# --- 配置加载与存储 (支持多套 ComfyUI 环境地址与持久化隔离) ---
static func ensure_valid_environments(settings: Dictionary) -> void:
	var envs: Array = []
	if settings.has("comfyui_environments") and settings["comfyui_environments"] is Array:
		envs = settings["comfyui_environments"].duplicate(true)
	
	# 1. 保证基础本地环境存在
	var has_local = false
	for e in envs:
		if e is Dictionary and (str(e.get("server", "")).contains("127.0.0.1") or str(e.get("server", "")).contains("localhost")):
			has_local = true
			break
	if not has_local:
		envs.insert(0, {
			"id": "env_local",
			"name": "💻 本地默认 (127.0.0.1:8188)",
			"server": "http://127.0.0.1:8188",
			"user": "",
			"password": ""
		})
	
	# 2. 如果存在外部配置的真实远程地址（如公网穿透/私有云），自动导入作为独立环境
	var cur_server = str(settings.get("comfyui_server", "")).strip_edges()
	var cur_user = str(settings.get("comfyui_user", "")).strip_edges()
	var cur_pass = str(settings.get("comfyui_password", "")).strip_edges()
	
	# 如果当前 server 是占位符，尝试从全局配置文件中挽救历史配置
	if cur_server.is_empty() or cur_server.contains("your-comfyui-server"):
		if FileAccess.file_exists(AI_CONFIG_PATH):
			var gf = FileAccess.open(AI_CONFIG_PATH, FileAccess.READ)
			if gf:
				var g_json = JSON.new()
				if g_json.parse(gf.get_as_text()) == OK and g_json.data is Dictionary:
					var saved_s = str(g_json.data.get("comfyui_server", "")).strip_edges()
					if not saved_s.is_empty() and not saved_s.contains("your-comfyui-server") and not saved_s.contains("127.0.0.1"):
						cur_server = saved_s
						cur_user = str(g_json.data.get("comfyui_user", "")).strip_edges()
						cur_pass = str(g_json.data.get("comfyui_password", "")).strip_edges()
				gf.close()

	if not cur_server.is_empty() and not cur_server.contains("127.0.0.1") and not cur_server.contains("localhost") and not cur_server.contains("your-comfyui-server"):
		var found = false
		for e in envs:
			if e is Dictionary and e.get("server", "") == cur_server:
				found = true
				if not cur_user.is_empty() and str(e.get("user", "")).is_empty():
					e["user"] = cur_user
				if not cur_pass.is_empty() and str(e.get("password", "")).is_empty():
					e["password"] = cur_pass
				break
		if not found:
			var host_domain = cur_server.replace("https://", "").replace("http://", "").split("/")[0]
			envs.append({
				"id": "env_remote_" + str(Time.get_unix_time_from_system()),
				"name": "🚀 远程环境 (" + host_domain + ")",
				"server": cur_server,
				"user": cur_user,
				"password": cur_pass
			})

	settings["comfyui_environments"] = envs

	# 3. 校验并定位当前激活的环境 current_env_id
	var cur_id = str(settings.get("current_env_id", ""))
	var active_env: Dictionary = {}
	for e in envs:
		if e is Dictionary and e.get("id", "") == cur_id:
			active_env = e
			break
	if active_env.is_empty():
		for e in envs:
			if e is Dictionary and e.get("server", "") == cur_server and not cur_server.is_empty():
				active_env = e
				break
	if active_env.is_empty() and envs.size() > 0:
		# 优先选用非本地的远程环境，否则选第一个
		if envs.size() > 1 and not str(envs[envs.size() - 1].get("server", "")).contains("127.0.0.1"):
			active_env = envs[envs.size() - 1]
		else:
			active_env = envs[0]

	if not active_env.is_empty():
		settings["current_env_id"] = active_env.get("id", "")
		settings["comfyui_server"] = active_env.get("server", "http://127.0.0.1:8188")
		settings["comfyui_user"] = active_env.get("user", "")
		settings["comfyui_password"] = active_env.get("password", "")

static func load_ai_settings() -> Dictionary:
	var global_settings: Dictionary = {}
	if FileAccess.file_exists(AI_CONFIG_PATH):
		var file = FileAccess.open(AI_CONFIG_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
				global_settings = json.data
			file.close()

	var settings = get_default_ai_settings()
	for k in global_settings:
		settings[k] = global_settings[k]

	var proj_settings: Dictionary = {}
	if ProjectContext.active_project_data.has("ai_settings") and (ProjectContext.active_project_data["ai_settings"] is Dictionary):
		proj_settings = ProjectContext.active_project_data["ai_settings"]
	elif not ProjectContext.active_project_dir.is_empty():
		var pjson = ProjectContext.active_project_dir + "project.json"
		if FileAccess.file_exists(pjson):
			var pdata = ProjectContext.load_json_file(pjson)
			if pdata.has("ai_settings") and (pdata["ai_settings"] is Dictionary):
				proj_settings = pdata["ai_settings"]

	for k in proj_settings:
		if k == "comfyui_environments":
			if proj_settings[k] is Array and not proj_settings[k].is_empty():
				settings[k] = proj_settings[k]
		elif k in ["comfyui_server", "comfyui_user", "comfyui_password"]:
			var val = str(proj_settings[k])
			if (val.contains("your-comfyui-server") or val.is_empty()) and not str(settings.get(k, "")).is_empty() and not str(settings.get(k, "")).contains("your-comfyui-server"):
				continue
			settings[k] = proj_settings[k]
		else:
			settings[k] = proj_settings[k]

	ensure_valid_environments(settings)
	return settings

static func save_ai_settings(settings: Dictionary) -> bool:
	ensure_valid_environments(settings)
	
	# 1. 始终持久化至全局编辑器配置 (避免切换工程时环境列表丢失)
	var dir = AI_CONFIG_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file = FileAccess.open(AI_CONFIG_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings, "\t"))
		file.close()
	
	# 2. 如果当前有活动工程，同步更新工程内部的 ai_settings
	if not ProjectContext.active_project_dir.is_empty():
		ProjectContext.active_project_data["ai_settings"] = settings
		ProjectContext.save_active_project()
		
	return true

static func get_default_ai_settings() -> Dictionary:
	return {
		"comfyui_server": "http://127.0.0.1:8188",
		"comfyui_user": "",
		"comfyui_password": "",
		"comfyui_environments": [
			{
				"id": "env_local",
				"name": "💻 本地默认 (127.0.0.1:8188)",
				"server": "http://127.0.0.1:8188",
				"user": "",
				"password": ""
			}
		],
		"current_env_id": "env_local",
		"checkpoint": "sd_xl_turbo_1.0.safetensors",
		"global_style_preset": "dark_mystery",
		"global_style_prompt": "masterpiece, best quality, anime visual novel, victorian dark mystery, cinematic lighting",
		"global_negative_prompt": "worst quality, low quality, blurry, bad anatomy, deformed limbs, (text:1.5), (watermark:1.5), (signature:1.5), (artist name:1.5), (username:1.4), (subtitles:1.5), (dialogue box:1.4), (words:1.4), (letters:1.4), (font:1.4), (caption:1.4), (ui:1.4), (speech bubble:1.4), (label:1.4), (gibberish:1.3), noisy",
		"character_base_prompt": "solo, waist-up portrait, standing pose, white background, simple background",
		"bg_base_prompt": "scenery, background, interior or exterior, highly detailed, no humans",
		"tts_voice_default": "zh-CN-XiaoxiaoNeural",
		"bg_width": 1024,
		"bg_height": 576,
		"char_width": 512,
		"char_height": 768
	}

# --- 资产清单加载与存储 (100% 绑定当前活动工程) ---
static func load_manifest() -> Array:
	var items: Array = []
	if ProjectContext.active_project_data.has("asset_manifest") and (ProjectContext.active_project_data["asset_manifest"] is Array):
		items = ProjectContext.active_project_data["asset_manifest"]
	elif not ProjectContext.active_project_dir.is_empty():
		var pjson = ProjectContext.active_project_dir + "project.json"
		if FileAccess.file_exists(pjson):
			var pdata = ProjectContext.load_json_file(pjson)
			items = pdata.get("asset_manifest", [])
	elif FileAccess.file_exists(MANIFEST_PATH):
		var file = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
				items = json.data.get("items", [])
				
	for it in items:
		if it is Dictionary:
			get_sandboxed_asset_path(it)
	refresh_manifest_status(items)
	return items

static func save_manifest(items: Array) -> bool:
	for it in items:
		if it is Dictionary:
			get_sandboxed_asset_path(it)
	if not ProjectContext.active_project_dir.is_empty():
		ProjectContext.active_project_data["asset_manifest"] = items
		ProjectContext.save_active_project()
		return true
	var dir = MANIFEST_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file = FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	if not file:
		return false
	var data = {"items": items}
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true

static func refresh_manifest_status(items: Array) -> void:
	for item in items:
		var path = item.get("local_path", "")
		var file_exists = not path.is_empty() and (FileAccess.file_exists(path) or FileAccess.file_exists(ProjectSettings.globalize_path(path)))
		# 尊重用户手动设定的状态：
		# 1. 若用户此前已显式设定 status 为 "pending" 或 "ready"，绝对保持原样，绝不被底层扫描静默覆盖；
		# 2. 只有在此前未设定 status（或 status 为空）时，才根据文件是否存在智能初始化。
		if not item.has("status") or (item["status"] != "pending" and item["status"] != "ready"):
			item["status"] = "ready" if file_exists else "pending"

# --- 自动同步与搜集全案资产 (支持实体归属与沙盒化) ---
static func sync_manifest_with_project() -> Array:
	var items = load_manifest()
	var item_map = {}
	for it in items:
		item_map[it.get("id", "")] = it

	var pdir = ProjectContext.active_project_dir
	if pdir.is_empty():
		pdir = "res://projects/case_01/"
	if not pdir.ends_with("/"):
		pdir += "/"

	# 1. 扫描场景背景与BGM
	for sc_id in DataManager.scenes:
		var sc = DataManager.scenes[sc_id]
		var sc_name = sc.get("name", sc_id)
		var bg_path = sc.get("background", "")
		if not bg_path.is_empty():
			var bg_id = bg_path.get_file().get_basename()
			if not item_map.has(bg_id):
				var new_item = {
					"id": bg_id,
					"type": "background",
					"entity_type": "scene",
					"entity_id": sc_id,
					"entity_name": sc_name,
					"sub_type": "background",
					"name": sc_name + " 背景",
					"prompt": sc_name + ", victorian mystery scene, interior architecture",
					"local_path": bg_path,
					"width": 1920,
					"height": 1080,
					"status": "ready" if FileAccess.file_exists(bg_path) else "pending"
				}
				items.append(new_item)
				item_map[bg_id] = new_item
			else:
				var it = item_map[bg_id]
				it["entity_type"] = "scene"
				it["entity_id"] = sc_id
				it["entity_name"] = sc_name
				it["sub_type"] = "background"
				
		var bgm_path = sc.get("bgm", "")
		if not bgm_path.is_empty():
			var bgm_id = bgm_path.get_file().get_basename()
			if not item_map.has(bgm_id):
				var new_item = {
					"id": bgm_id,
					"type": "bgm",
					"entity_type": "scene",
					"entity_id": sc_id,
					"entity_name": sc_name,
					"sub_type": "bgm",
					"name": sc_name + " BGM",
					"prompt": "Solo acoustic piano in D-minor, dark mystery, melancholic",
					"local_path": bgm_path,
					"status": "ready" if FileAccess.file_exists(bgm_path) else "pending"
				}
				items.append(new_item)
				item_map[bgm_id] = new_item
			else:
				var it = item_map[bgm_id]
				it["entity_type"] = "scene"
				it["entity_id"] = sc_id
				it["entity_name"] = sc_name
				it["sub_type"] = "bgm"

	# 2. 扫描对话中的角色立绘与配音
	for d_id in DataManager.dialogues:
		var diag = DataManager.dialogues[d_id]
		var lines = diag.get("lines", [])
		for idx in range(lines.size()):
			var line = lines[idx]
			if not (line is Dictionary):
				continue
				
			var speaker = line.get("speaker", "旁白").strip_edges()
			if speaker.is_empty():
				speaker = "旁白"
			var char_entity_id = deduce_character_entity_id(speaker)
			
			var char_img = line.get("character_image", "")
			if not char_img.is_empty():
				var cid = char_img.get_file().get_basename()
				if not item_map.has(cid):
					var new_item = {
						"id": cid,
						"type": "character",
						"entity_type": "character",
						"entity_id": char_entity_id,
						"entity_name": speaker,
						"sub_type": "sprite",
						"name": speaker + " 立绘 (" + cid.get_file() + ")",
						"character_id": char_entity_id,
						"prompt": speaker + ", upper body portrait, simple background",
						"local_path": char_img,
						"width": 512,
						"height": 768,
						"status": "ready" if (FileAccess.file_exists(char_img) or FileAccess.file_exists(ProjectSettings.globalize_path(char_img))) else "pending"
					}
					items.append(new_item)
					item_map[cid] = new_item
				else:
					var it = item_map[cid]
					it["entity_type"] = "character"
					it["entity_id"] = char_entity_id
					it["entity_name"] = speaker
					it["sub_type"] = "sprite"
					
			var text = line.get("text", "")
			if not text.is_empty():
				var voice = line.get("voice", "")
				var vid = ""
				if not voice.is_empty():
					vid = voice.get_file().get_basename()
				else:
					vid = "voice_%s_%d" % [d_id, idx + 1]
					voice = pdir + "assets/audio/voice/" + vid + ".mp3"
					line["voice"] = voice
					
				if not item_map.has(vid):
					var voice_role = deduce_voice_role(speaker)
					var new_item = {
						"id": vid,
						"type": "voice",
						"entity_type": "character",
						"entity_id": char_entity_id,
						"entity_name": speaker,
						"sub_type": "voice",
						"name": speaker + " 配音: " + text.left(10) + ("..." if text.length() > 10 else ""),
						"role": speaker,
						"text": text,
						"voice_role": voice_role,
						"local_path": voice,
						"status": "ready" if (FileAccess.file_exists(voice) or FileAccess.file_exists(ProjectSettings.globalize_path(voice))) else "pending"
					}
					items.append(new_item)
					item_map[vid] = new_item
				else:
					var it = item_map[vid]
					it["entity_type"] = "character"
					it["entity_id"] = char_entity_id
					it["entity_name"] = speaker
					it["sub_type"] = "voice"

	# 3. 扫描线索物证 (Clues)
	for clue_id in DataManager.clues:
		var clue = DataManager.clues[clue_id]
		var cname = clue.get("name", clue.get("title", clue_id))
		var clue_img = clue.get("image", clue.get("icon", ""))
		if clue_img.is_empty():
			clue_img = pdir + "assets/images/characters/clue_" + clue_id + ".png"
			clue["image"] = clue_img
		var cid = clue_img.get_file().get_basename()
		if not item_map.has(cid):
			var new_item = {
				"id": cid,
				"type": "clue",
				"entity_type": "clue",
				"entity_id": clue_id,
				"entity_name": cname,
				"sub_type": "image",
				"name": cname + " 特写",
				"prompt": cname + ", investigation item closeup, white background, detailed, isolated",
				"local_path": clue_img,
				"width": 512,
				"height": 512,
				"status": "ready" if (FileAccess.file_exists(clue_img) or FileAccess.file_exists(ProjectSettings.globalize_path(clue_img))) else "pending"
			}
			items.append(new_item)
			item_map[cid] = new_item
		else:
			var it = item_map[cid]
			it["entity_type"] = "clue"
			it["entity_id"] = clue_id
			it["entity_name"] = cname
			it["sub_type"] = "image"

	# 3.5 自动扫描角色素材目录中的多表情差分与外部立绘 (支持方案B外部导入与自动装配)
	var char_img_dir = pdir + "assets/images/characters/"
	var abs_char_img_dir = ProjectSettings.globalize_path(char_img_dir)
	if DirAccess.dir_exists_absolute(abs_char_img_dir):
		var cdir = DirAccess.open(char_img_dir)
		if cdir:
			cdir.list_dir_begin()
			var fn = cdir.get_next()
			while fn != "":
				var ext = fn.get_extension().to_lower()
				if not cdir.current_is_dir() and ext in ["png", "jpg", "jpeg", "webp"]:
					var base_id = fn.get_basename()
					# 忽略线索道具特写
					if not base_id.begins_with("clue_"):
						var matched_cid = ""
						var matched_cname = ""
						for cid in DataManager.characters:
							var c = DataManager.characters[cid]
							var cname = c.get("name", cid)
							if base_id == cid or base_id.begins_with(cid + "_") or base_id.begins_with("char_" + cid + "_"):
								matched_cid = cid
								matched_cname = cname
								break
							elif not cname.is_empty() and (base_id == cname or base_id.begins_with(cname + "_")):
								matched_cid = cid
								matched_cname = cname
								break
						
						if not matched_cid.is_empty():
							if not item_map.has(base_id):
								var expr_name = "立绘"
								if base_id != matched_cid:
									var suffix = base_id.substr(matched_cid.length()).trim_prefix("_")
									if suffix.is_empty():
										suffix = "差分"
									expr_name = "差分: " + suffix
								var new_item = {
									"id": base_id,
									"type": "character",
									"entity_type": "character",
									"entity_id": matched_cid,
									"entity_name": matched_cname,
									"sub_type": "sprite",
									"name": "%s %s" % [matched_cname, expr_name],
									"character_id": matched_cid,
									"prompt": matched_cname + ", upper body portrait, simple background",
									"local_path": char_img_dir + fn,
									"width": 512,
									"height": 768,
									"status": "ready"
								}
								items.append(new_item)
								item_map[base_id] = new_item
				fn = cdir.get_next()
			cdir.list_dir_end()

	# 4. 历史遗留资产智能补齐归属
	for it in items:
		if not it.has("entity_type") or it["entity_type"].is_empty():
			var itype = it.get("type", "")
			if itype == "character":
				it["entity_type"] = "character"
				it["entity_id"] = deduce_character_entity_id(it.get("character_id", it.get("name", "")))
				it["entity_name"] = it.get("character_id", it.get("name", "角色"))
				it["sub_type"] = "sprite"
			elif itype == "voice":
				it["entity_type"] = "character"
				var r = it.get("role", "旁白")
				it["entity_id"] = deduce_character_entity_id(r)
				it["entity_name"] = r
				it["sub_type"] = "voice"
			elif itype == "background":
				it["entity_type"] = "scene"
				it["entity_id"] = it.get("id", "scene_general")
				it["entity_name"] = it.get("name", "场景")
				it["sub_type"] = "background"
			elif itype in ["bgm", "sfx"]:
				it["entity_type"] = "shared"
				it["entity_id"] = "shared"
				it["entity_name"] = "公共音频"
				it["sub_type"] = itype

	refresh_manifest_status(items)
	save_manifest(items)
	return items

static func deduce_character_entity_id(speaker: String) -> String:
	for cid in DataManager.characters:
		var c = DataManager.characters[cid]
		if c.get("name", "") == speaker or cid == speaker:
			return cid
	if speaker == "旁白" or "独白" in speaker or "内心" in speaker or speaker.is_empty():
		return "char_narrator"
	return "char_" + speaker.replace(" ", "_").to_lower()

# --- 实体资产结构化聚合 (Domain Entity Aggregator) ---
static func get_entities_summary(items: Array) -> Dictionary:
	var result = {
		"characters": {},
		"scenes": {},
		"clues": {},
		"shared": {
			"id": "shared",
			"name": "全局公共库",
			"items": [],
			"ready_count": 0,
			"total_count": 0
		}
	}

	# 预先从 DataManager 载入已知角色
	for cid in DataManager.characters:
		var c = DataManager.characters[cid]
		result["characters"][cid] = {
			"id": cid,
			"name": c.get("name", cid),
			"identity": c.get("identity", "登场人物"),
			"voice_role": c.get("voice", deduce_voice_role(c.get("name", cid))),
			"base_prompt": c.get("prompt", c.get("name", cid) + ", upper body portrait"),
			"sprites": [],
			"voices": [],
			"ready_count": 0,
			"total_count": 0
		}

	# 确保虚拟角色【旁白与心声】存在
	if not result["characters"].has("char_narrator"):
		result["characters"]["char_narrator"] = {
			"id": "char_narrator",
			"name": "旁白与心声",
			"identity": "系统独白 / 叙事旁白",
			"voice_role": "zh-CN-YunyangNeural",
			"base_prompt": "narrator voice over",
			"sprites": [],
			"voices": [],
			"ready_count": 0,
			"total_count": 0
		}

	# 预先从 DataManager 载入已知场景
	for sc_id in DataManager.scenes:
		var sc = DataManager.scenes[sc_id]
		result["scenes"][sc_id] = {
			"id": sc_id,
			"name": sc.get("name", sc_id),
			"background": null,
			"bgm": null,
			"ambient": null,
			"items": [],
			"ready_count": 0,
			"total_count": 0
		}

	# 预先从 DataManager 载入已知线索
	for clue_id in DataManager.clues:
		var clue = DataManager.clues[clue_id]
		result["clues"][clue_id] = {
			"id": clue_id,
			"name": clue.get("name", clue.get("title", clue_id)),
			"image": null,
			"sfx": null,
			"items": [],
			"ready_count": 0,
			"total_count": 0
		}

	# 遍历资产清单，按实体归纳归类
	for it in items:
		var etype = it.get("entity_type", "")
		var eid = it.get("entity_id", "")

		# 动态智能推断（向前兼容旧版未打标清单）
		if etype.is_empty() or eid.is_empty():
			var itype = it.get("type", "")
			var iid = it.get("id", "")
			var iname = it.get("name", "")
			if itype == "character":
				etype = "character"
				eid = deduce_character_entity_id(it.get("character_id", iname))
				it["entity_type"] = etype
				it["entity_id"] = eid
				it["sub_type"] = "sprite"
			elif itype == "voice":
				etype = "character"
				var r = it.get("role", "")
				if r.is_empty():
					for cid in DataManager.characters:
						var c = DataManager.characters[cid]
						if c.get("name", "") in iname or cid in iid:
							r = c.get("name", "")
							break
				eid = deduce_character_entity_id(r)
				it["entity_type"] = etype
				it["entity_id"] = eid
				it["sub_type"] = "voice"
			elif itype == "background":
				etype = "scene"
				for sid in DataManager.scenes:
					var s = DataManager.scenes[sid]
					if s.get("name", "") in iname or sid in iid:
						eid = sid
						break
				if eid.is_empty():
					eid = iid
				it["entity_type"] = etype
				it["entity_id"] = eid
				it["sub_type"] = "background"
			elif itype == "clue":
				etype = "clue"
				eid = iid
				it["entity_type"] = etype
				it["entity_id"] = eid
				it["sub_type"] = "image"
			else:
				etype = "shared"
				eid = "shared"
				it["entity_type"] = etype
				it["entity_id"] = eid

		var is_ready = (it.get("status", "pending") == "ready")

		if etype == "character":
			if not result["characters"].has(eid):
				result["characters"][eid] = {
					"id": eid,
					"name": it.get("entity_name", eid),
					"identity": "角色",
					"voice_role": it.get("voice_role", "zh-CN-XiaoxiaoNeural"),
					"base_prompt": it.get("prompt", ""),
					"sprites": [],
					"voices": [],
					"ready_count": 0,
					"total_count": 0
				}
			var c_obj = result["characters"][eid]
			c_obj["total_count"] += 1
			if is_ready:
				c_obj["ready_count"] += 1

			if it.get("sub_type", "") == "sprite" or it.get("type", "") == "character":
				c_obj["sprites"].append(it)
			else:
				c_obj["voices"].append(it)

		elif etype == "scene":
			if not result["scenes"].has(eid):
				result["scenes"][eid] = {
					"id": eid,
					"name": it.get("entity_name", eid),
					"background": null,
					"bgm": null,
					"ambient": null,
					"items": [],
					"ready_count": 0,
					"total_count": 0
				}
			var sc_obj = result["scenes"][eid]
			sc_obj["total_count"] += 1
			if is_ready:
				sc_obj["ready_count"] += 1
			sc_obj["items"].append(it)
			if it.get("sub_type", "") == "background" or it.get("type", "") == "background":
				sc_obj["background"] = it
			elif it.get("sub_type", "") == "bgm" or it.get("type", "") == "bgm":
				sc_obj["bgm"] = it
			elif it.get("sub_type", "") == "ambient":
				sc_obj["ambient"] = it

		elif etype == "clue":
			if not result["clues"].has(eid):
				result["clues"][eid] = {
					"id": eid,
					"name": it.get("entity_name", eid),
					"image": null,
					"sfx": null,
					"items": [],
					"ready_count": 0,
					"total_count": 0
				}
			var cl_obj = result["clues"][eid]
			cl_obj["total_count"] += 1
			if is_ready:
				cl_obj["ready_count"] += 1
			cl_obj["items"].append(it)
			if it.get("sub_type", "") == "image" or it.get("type", "") == "clue":
				cl_obj["image"] = it
			elif it.get("sub_type", "") == "sfx":
				cl_obj["sfx"] = it

		else:
			var sh_obj = result["shared"]
			sh_obj["total_count"] += 1
			if is_ready:
				sh_obj["ready_count"] += 1
			sh_obj["items"].append(it)

	return result

static func deduce_voice_role(speaker: String) -> String:
	if DataManager.characters.has(speaker) and DataManager.characters[speaker].has("voice"):
		return DataManager.characters[speaker]["voice"]
	for cid in DataManager.characters:
		var c = DataManager.characters[cid]
		if c.get("name", "") == speaker and c.has("voice"):
			return c["voice"]
	if speaker == "旁白":
		return "zh-CN-YunyangNeural"
	if "千鹤" in speaker or "真理子" in speaker or "女" in speaker or "妻" in speaker or "夫人" in speaker or "小姐" in speaker:
		return "zh-CN-XiaoxiaoNeural"
	if "悠斗" in speaker or "学徒" in speaker or "青年" in speaker or "少年" in speaker:
		return "zh-CN-YunxiNeural"
	if "源治" in speaker or "老" in speaker or "守护人" in speaker or "医生" in speaker:
		return "zh-CN-YunjianNeural"
	return "zh-CN-YunxiNeural"

# --- 检查 ComfyUI 服务状态 ---
static func check_comfy_service(host: String, user: String = "", password: String = "") -> Dictionary:
	var bridge_script = ProjectSettings.globalize_path("res://tools/ai_bridge.py")
	var args = [bridge_script, "check_comfy", "--host", host]
	if not user.is_empty():
		args.append_array(["--user", user])
	if not password.is_empty():
		args.append_array(["--password", password])
	var output = []
	var exit_code = OS.execute(get_python_executable(), args, output, true)
	if exit_code == OK and output.size() > 0:
		var json = JSON.new()
		if json.parse(output[0].strip_edges()) == OK and json.data is Dictionary:
			return json.data
	return {"online": false, "error": "执行桥接脚本失败或服务未启动"}

# --- 执行单项素材生成 ---
static func generate_asset_item(item: Dictionary, settings: Dictionary, progress_file: String = "") -> Dictionary:
	var item_type = item.get("type", "")
	var local_path = get_sandboxed_asset_path(item)
	var abs_save_path = ProjectSettings.globalize_path(local_path)
	DirAccess.make_dir_recursive_absolute(abs_save_path.get_base_dir())
	var bridge_script = ProjectSettings.globalize_path("res://tools/ai_bridge.py")
	
	if item_type in ["background", "character", "clue"]:
		var host = settings.get("comfyui_server", "http://127.0.0.1:8188")
		var user = settings.get("comfyui_user", "")
		var password = settings.get("comfyui_password", "")
		var ckpt = settings.get("checkpoint", "sd_xl_turbo_1.0.safetensors")
		var global_style = settings.get("global_style_prompt", "")
		var global_neg = settings.get("global_negative_prompt", "")
		var item_prompt = item.get("prompt", "")
		var item_neg = item.get("negative_prompt", "")
		var final_prompt = ""
		var final_neg = global_neg
		if not item_neg.is_empty():
			final_neg = item_neg + "，" + final_neg
		var w = 512
		var h = 768
		var is_trans = 0
		var args: Array = []
		
		var is_anima = ckpt.to_lower().contains("anima")
		
		if item_type == "background":
			# 场景背景模式：绝对封杀人物，注入广角空间透视与空镜氛围
			if is_anima:
				var bg_prefix = "高质量场景概念设计插画，大广角室内建筑透视，空镜，无人物，"
				final_prompt = bg_prefix + item_prompt + "，" + global_style
				final_neg = "人物，单人，少女，少年，面部，低质量，模糊，" + final_neg
			else:
				var bg_prefix = "(scenery:1.4), (empty room:1.3), (no humans:1.5), wide angle interior architecture, environment concept, "
				final_prompt = bg_prefix + global_style + ", " + item_prompt
				final_neg = "(humans:1.6), (1girl:1.6), (1boy:1.6), (people:1.6), (character:1.5), crowd, face, " + final_neg
			w = 960
			h = 540
			is_trans = 0
			args = [
				bridge_script, "generate_image",
				"--host", host,
				"--ckpt", ckpt,
				"--prompt", final_prompt,
				"--negative", final_neg,
				"--width", str(w),
				"--height", str(h),
				"--transparent", str(is_trans),
				"--save", abs_save_path
			]
		elif item_type == "character":
			# 角色立绘双通道架构：【模式 A：纯微表情差分 (面部专注+骨相锁定)】 vs 【模式 B：3D 姿态全身生成 (姿态前置+解除身体锁定)】
			var cid = item.get("character_id", item.get("entity_id", ""))
			var char_data = {}
			if DataManager.characters.has(cid):
				char_data = DataManager.characters[cid]
			elif ProjectContext.active_project_data.has("characters") and ProjectContext.active_project_data["characters"].has(cid):
				char_data = ProjectContext.active_project_data["characters"][cid]
			
			var char_base_dna = char_data.get("base_prompt", "")
			if char_base_dna.is_empty():
				char_base_dna = char_data.get("prompt", "")

			var is_male = item_prompt.contains("男") or item_prompt.contains("boy") or item_prompt.contains("he") or item.get("name", "").contains("沈策") or item.get("name", "").contains("温寻") or cid.contains("shen_ce") or cid.contains("wen_xun")
			var gender_prefix = "单人男性，1boy, " if is_male else ""
			var gender_neg = "女性，少女，女，(female:1.6), (1girl:1.6), (woman:1.6), " if is_male else ""
			var ui_neg = "对话框，台词框，气泡框，对话气泡，文字，字幕，台词，下方字幕，文本，英文字母，日文字符，中文字，水印，logo，边框，黑边，分镜框，乱码，(dialogue box:2.0), (speech bubble:2.0), (text:2.0), (subtitles:2.0), (caption:2.0), (textbox:2.0), (message box:2.0), (watermark:2.0), (letters:1.9), (chinese text:1.9), (japanese text:1.9), (bottom text:1.9), (movie bar:1.9), (black bar:1.9), (comic frame:1.8), (border:1.8), "
			var anti_light_neg = "(cinematic lighting:1.8), (dramatic lighting:1.8), (harsh shadows:1.8), (strong drop shadows:1.8), (colored rim light:1.7), (glow:1.6), (ambient color cast:1.7), (purple lighting:1.7), (blue lighting:1.7), (high contrast:1.6), "
			var anti_dup_neg = "(duplicate:2.0), (multiple views:2.0), (stacked bodies:2.0), (two people:2.0), (two characters:2.0), (extra head:2.0), (two heads:2.0), (second head:2.0), (split screen:2.0), (comic panel:1.9), (clones:1.9), (extra arms:1.8), (extra body:1.9), (mini character:1.9), "

			# 剔除角色立绘中造成色温偏色与字幕残留的光影关键词，采用平涂赛璐珞与服装原色保真
			var clean_char_style = global_style
			clean_char_style = clean_char_style.replace("剧场版光影", "均匀漫射自然柔光")
			clean_char_style = clean_char_style.replace("电影感", "二次元平涂色彩")
			clean_char_style = clean_char_style.replace("cinematic dramatic lighting", "soft studio lighting, authentic costume colors")
			clean_char_style = clean_char_style.replace("cinematic lighting", "clean anime cel shading, soft studio lighting")
			clean_char_style = clean_char_style.replace("sharp shadows", "no harsh shadows")
			clean_char_style = clean_char_style.replace("visual novel", "character sprite")
			clean_char_style = clean_char_style.replace("视觉小说", "二次元立绘")

			# 寻找形象基准 Base 锚点
			var base_sprite_path = ""
			var explicit_base = item.get("base_sprite_path", "")
			if not explicit_base.is_empty():
				var abs_p = ProjectSettings.globalize_path(explicit_base)
				if FileAccess.file_exists(abs_p):
					base_sprite_path = abs_p
			
			if base_sprite_path.is_empty() and not item.get("is_base", false):
				var cid_find = cid
				var m_items = load_manifest()
				var candidate_base = ""
				for it in m_items:
					if it is Dictionary and (it.get("character_id", "") == cid_find or it.get("entity_id", "") == cid_find):
						if it.get("sub_type", "") == "sprite" or it.get("type", "") == "character":
							if it.get("id", "") == item.get("id", ""):
								continue
							var it_path = it.get("local_path", "")
							var it_abs = ProjectSettings.globalize_path(it_path)
							if FileAccess.file_exists(it_abs):
								if it.get("is_base", false):
									candidate_base = it_abs
									break
								elif candidate_base.is_empty():
									candidate_base = it_abs
				base_sprite_path = candidate_base

			# 动作姿态预设与模式智能判定
			var pose_preset_key = item.get("pose_preset", "standing_calm")
			var has_distinct_pose = (pose_preset_key != "standing_calm" and not pose_preset_key.is_empty())
			var has_pose_img = item.has("pose_image") and not str(item.get("pose_image", "")).is_empty()
			var gen_mode = item.get("generation_mode", "")

			var is_pose_mode = false
			if gen_mode == "pose":
				is_pose_mode = true
			elif gen_mode == "expression":
				is_pose_mode = false
			else:
				# 兼容历史数据与卡片姿态选择：指定非标准站姿或拥有姿态骨架图时，必须归入姿态模式，绝不能锁死身体！
				is_pose_mode = has_pose_img or has_distinct_pose

			w = 512
			h = 768
			is_trans = 1

			if is_pose_mode:
				# --- 【模式 B：3D 姿态全新全身立绘生成】 ---
				var pose_prompt_zh = ""
				var pose_prompt_en = ""
				if PoseMannequinClass.PRESETS.has(pose_preset_key):
					var p_info = PoseMannequinClass.PRESETS[pose_preset_key]
					pose_prompt_zh = p_info.get("prompt_zh", "")
					pose_prompt_en = p_info.get("prompt_en", "")

				# 核心：将肢体动作姿态置于提示词最前列（Highest Token Priority），并强化权重至 1.6
				var pose_front = ""
				if not pose_prompt_en.is_empty():
					pose_front += "((%s):1.6), " % pose_prompt_en
				if not pose_prompt_zh.is_empty():
					pose_front += "((%s):1.5), " % pose_prompt_zh

				var char_prefix = "(solo:1.6), (single person:1.6), (single upper body:1.5), 独立单人立绘，纯白背景，干净轮廓，无杂物，" + gender_prefix if is_anima else "(solo:1.6), (single person:1.6), (pure white background:1.5), isolated, " + gender_prefix
				final_prompt = pose_front + char_prefix + item_prompt + "，" + char_base_dna + "，" + clean_char_style
				
				# 负面词高强度严厉封杀站立垂手、垂臂、无动作等冲突姿态，强迫扩散模型摆出目标动作
				var pose_neg = "(arms at sides:2.0), (hands down:2.0), (hands at sides:2.0), (arms down:1.9), (hanging arms:1.9), (standing calmly:1.8), (neutral arms:1.8), "
				final_neg = anti_dup_neg + pose_neg + anti_light_neg + gender_neg + ui_neg + "复杂背景，室内室外环境，多余手指，肢体畸变，低质量，模糊"

				args = [
					bridge_script, "generate_image",
					"--host", host,
					"--ckpt", ckpt,
					"--prompt", final_prompt,
					"--negative", final_neg,
					"--width", str(w),
					"--height", str(h),
					"--transparent", str(is_trans),
					"--save", abs_save_path,
					"--inpaint_face", "0",
					"--denoise", "0.92",
					"--pose_preset", pose_preset_key
				]
				if has_pose_img:
					var p_abs = ProjectSettings.globalize_path(item.get("pose_image"))
					if FileAccess.file_exists(p_abs):
						args.append_array(["--pose_image", p_abs])
				if not base_sprite_path.is_empty():
					args.append_array(["--base_image", base_sprite_path])
				print("[AIAssetMgr] 启动 3D 姿态自适应差分一致性管线: %s (面部 100%% 锁定，躯干高自由去噪 0.92)" % pose_preset_key)

			else:
				# --- 【方案 A：靶向五官微表情差分 (Prompt 锚点锁定 + 极小局部重绘)】 ---
				var expr_text = item_prompt.strip_edges()
				
				# 关键核心：100% 完整继承角色的基础外观 Prompt 锚点！杜绝扩散模型因缺失容貌描述而换脸
				var prompt_anchor = char_base_dna
				if prompt_anchor.is_empty():
					prompt_anchor = "单人二次元男性立绘，利落黑色偏分短发，深灰锐利眼眸，下颌青色胡茬，清瘦五官" if is_male else "单人二次元女性立绘，精致清秀五官，细腻肤质，柔美眼眸"
				
				# 提示词结构：基础容貌锚点 + 强权重微表情增量 + 风格统一
				final_prompt = "%s，((%s):1.6)，%s" % [prompt_anchor, expr_text, clean_char_style]
				final_neg = anti_dup_neg + anti_light_neg + gender_neg + ui_neg + "变形，多余肢体，低质量，模糊"

				args = [
					bridge_script, "generate_image",
					"--host", host,
					"--ckpt", ckpt,
					"--prompt", final_prompt,
					"--negative", final_neg,
					"--width", str(w),
					"--height", str(h),
					"--transparent", str(is_trans),
					"--save", abs_save_path
				]
				if not base_sprite_path.is_empty():
					# 方案 A 最佳去噪 0.58，搭配 Anima-Turbo 规范 CFG 1.0 与靶向器官分流遮罩
					args.append_array(["--base_image", base_sprite_path, "--inpaint_face", "1", "--denoise", "0.58"])
					print("[AIAssetMgr] 启动方案 A 靶向微表情融合: %s (锁定角色外观锚点, 去噪 0.58)" % base_sprite_path)
				else:
					args.append_array(["--inpaint_face", "0"])

		elif item_type == "clue":
			# 物证特写模式：孤立微距实物特写与透明抠图
			if is_anima:
				var clue_prefix = "纯白背景，单个物品特写，静物微距，"
				final_prompt = clue_prefix + item_prompt + "，" + global_style
				final_neg = "人物，复杂背景，多余杂物，低质量，" + global_neg
			else:
				var clue_prefix = "(isolated object:1.4), (pure white background:1.4), (still life:1.3), macro detail, item closeup, "
				final_prompt = clue_prefix + global_style + ", " + item_prompt
				final_neg = "(humans:1.6), (face:1.5), (character:1.5), room, complex background, " + global_neg
			w = 512
			h = 512
			is_trans = 1
			args = [
				bridge_script, "generate_image",
				"--host", host,
				"--ckpt", ckpt,
				"--prompt", final_prompt,
				"--negative", final_neg,
				"--width", str(w),
				"--height", str(h),
				"--transparent", str(is_trans),
				"--save", abs_save_path
			]
		else:
			final_prompt = (item_prompt + "，" + global_style) if is_anima else (global_style + ", " + item_prompt)
			args = [
				bridge_script, "generate_image",
				"--host", host,
				"--ckpt", ckpt,
				"--prompt", final_prompt,
				"--negative", final_neg,
				"--width", str(w),
				"--height", str(h),
				"--transparent", str(is_trans),
				"--save", abs_save_path
			]

		if item.get("seed", 0) > 0:
			args.append_array(["--seed", str(item.get("seed"))])
		if not user.is_empty():
			args.append_array(["--user", user])
		if not password.is_empty():
			args.append_array(["--password", password])
		if not progress_file.is_empty():
			args.append_array(["--progress_file", ProjectSettings.globalize_path(progress_file)])
		
		var output = []
		var py = get_python_executable()
		print("[AIAssetMgr] 执行生图: ", py, " args=", args)
		var exit_code = OS.execute(py, args, output, true)
		print("[AIAssetMgr] 退出代码: ", exit_code, " 输出条数: ", output.size())
		if output.size() > 0:
			print("[AIAssetMgr] 输出内容: ", output[0])
		if exit_code == OK and output.size() > 0:
			var json = JSON.new()
			if json.parse(output[0].strip_edges()) == OK and json.data is Dictionary:
				var res = json.data
				if res.get("success", false):
					item["status"] = "ready"
					if res.has("seed"):
						item["seed"] = res["seed"]
				return res
			else:
				print("[AIAssetMgr] JSON 解析失败: ", output[0])
		var err_msg = "ComfyUI 生图执行失败"
		if output.size() > 0 and not output[0].strip_edges().is_empty():
			err_msg += ": " + output[0].strip_edges()
		return {"success": false, "error": err_msg}
		
	elif item_type == "voice":
		var text = item.get("text", "")
		var voice = item.get("voice_role", settings.get("tts_voice_default", "zh-CN-XiaoxiaoNeural"))
		var emotion = item.get("emotion", item.get("expression", "normal"))
		var args = [
			bridge_script, "generate_voice",
			"--text", text,
			"--voice", voice,
			"--emotion", emotion,
			"--save", abs_save_path
		]
		if not progress_file.is_empty():
			args.append_array(["--progress_file", ProjectSettings.globalize_path(progress_file)])
		var output = []
		var exit_code = OS.execute(get_python_executable(), args, output, true)
		if exit_code == OK and output.size() > 0:
			var json = JSON.new()
			if json.parse(output[0].strip_edges()) == OK and json.data is Dictionary:
				var res = json.data
				if res.get("success", false):
					item["status"] = "ready"
				return res
		return {"success": false, "error": "Edge-TTS 配音执行失败"}
	return {"success": false, "error": "不支持自动生成的素材类型: " + item_type}
