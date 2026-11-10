# editor/core/ai_asset_manager.gd
# AI 资产工坊核心管理器：管理配置、资产清单、ComfyUI生图与TTS调度
extends RefCounted

const PoseMannequinClass = preload("res://editor/ui/pose_editor/pose_mannequin_3d.gd")
const CharacterSheetMgr = preload("res://editor/core/character_sheet_manager.gd")
const AI_CONFIG_PATH = "res://config/ai_settings.json"
const MANIFEST_PATH = "res://data/assets/asset_manifest.json"

const STYLE_PRESETS = {
	"dark_mystery": {
		"id": "dark_mystery",
		"name": "🎬 本格悬疑黑金风 (默认)",
		"prompt": "本格悬疑推理日系动漫风格，精美二次元视觉小说立绘，剧场版光影，电影感，杰作，极高画质",
		"negative": "低质量，最差画质，模糊，粗糙，严重变形，多余肢体，衰老褶皱，法令纹，眼袋，粗糙毛孔，文字，水印"
	},
	"ghibli": {
		"id": "ghibli",
		"name": "🌿 宫崎骏 / 吉卜力手绘风",
		"prompt": "吉卜力动漫手绘水粉风格，宫崎骏美学，温暖治愈，高画质二次元插画，柔和暖光，杰作",
		"negative": "写实，3D塑料质感，现代CG，低质量，模糊，粗糙，严重变形"
	},
	"western_fantasy": {
		"id": "western_fantasy",
		"name": "🏰 欧美奇幻 / 写实风",
		"prompt": "欧美史诗奇幻写实插画，油画厚涂质感，伦勃朗戏剧性光影，概念艺术，电影级质感",
		"negative": "二次元平涂，简笔卡通，多余肢体，低质量，模糊，变形"
	},
	"japanese_wafuu": {
		"id": "japanese_wafuu",
		"name": "⛩️ 日式二次元 / 和风",
		"prompt": "精致和风日系动漫立绘，浮世绘古典优雅韵味，干净细腻线条，高画质二次元视觉小说",
		"negative": "美漫写实，3D模型，噪点，低质量，模糊，变形"
	},
	"chinese_guofeng": {
		"id": "chinese_guofeng",
		"name": "🏮 中式国风 / 仙侠水墨",
		"prompt": "典雅新中式国风插画，水墨意境晕染，朱砂与青黛配色，诗意唯美，高画质国风立绘",
		"negative": "西式魔幻，现代霓虹，杂乱涂鸦，低质量，模糊，变形"
	},
	"cute_chibi": {
		"id": "cute_chibi",
		"name": "🧸 卡通风 / Q版萌系",
		"prompt": "超可爱二次元Q版萌系插画，大眼萌化比例，清新马卡龙柔和色调，绘本风格",
		"negative": "写实恐怖，肌肉线条，阴暗怪诞，低质量，模糊，变形"
	},
	"dark_cthulhu": {
		"id": "dark_cthulhu",
		"name": "👁️ 暗黑 / 恐怖 / 克苏鲁",
		"prompt": "克苏鲁宇宙未知恐惧氛围，暗黑怪诞美学，冷色调迷雾与深渊阴影，不可名状之物",
		"negative": "明亮温馨，可爱动漫，艳丽高饱和，低质量，模糊，变形"
	},
	"pixel_retro": {
		"id": "pixel_retro",
		"name": "👾 像素 / 复古 16-bit",
		"prompt": "复古16位像素风视觉小说立绘，清晰像素边缘，点阵阴影质感，怀旧街机质感",
		"negative": "光滑渐变，平滑矢量，真实照片，低质量，模糊"
	},
	"watercolor_art": {
		"id": "watercolor_art",
		"name": "🎨 水彩 / 手绘 / 艺术画风",
		"prompt": "唯美梦幻水彩手绘，湿画法水痕肌理，纸质纹理与柔和色彩扩散，艺术级插画",
		"negative": "数码塑料感，锐利生硬边缘，3D渲染，低质量，模糊"
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

static func _get_data_manager():
	var ml = Engine.get_main_loop()
	if ml and ml is SceneTree and ml.root:
		return ml.root.get_node_or_null("DataManager")
	return null

static func _get_project_context():
	var ml = Engine.get_main_loop()
	if ml and ml is SceneTree and ml.root:
		return ml.root.get_node_or_null("ProjectContext")
	return null

# --- 资产物理路径沙盒化：确保属于当前工程的素材 100% 写入工程专属 assets/ 目录 ---
static func _get_project_dir() -> String:
	var pctx = _get_project_context()
	if pctx and "active_project_dir" in pctx and not str(pctx.active_project_dir).is_empty():
		var p = str(pctx.active_project_dir)
		return p if p.ends_with("/") else p + "/"
	return "res://projects/case_gallery_rain/"

static func get_sandboxed_asset_path(item: Dictionary) -> String:
	var pdir = _get_project_dir()
		
	var item_type = item.get("type", "background")
	var item_id = item.get("id", "asset_" + str(int(Time.get_unix_time_from_system())))
	var ext = "png"
	var subfolder = "images/backgrounds"
	if item_type == "background":
		ext = "png"
		subfolder = "images/backgrounds"
	elif item_type == "character" or item_type == "turnaround":
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
	var pctx = _get_project_context()
	if pctx and pctx.active_project_data.has("ai_settings") and (pctx.active_project_data["ai_settings"] is Dictionary):
		proj_settings = pctx.active_project_data["ai_settings"]
	elif pctx and not str(pctx.active_project_dir).is_empty():
		var pjson = str(pctx.active_project_dir) + "project.json"
		if FileAccess.file_exists(pjson):
			var pdata = pctx.load_json_file(pjson)
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
	var pctx = _get_project_context()
	if pctx and not str(pctx.active_project_dir).is_empty():
		pctx.active_project_data["ai_settings"] = settings
		pctx.save_active_project()
		
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
		"global_style_prompt": "本格悬疑推理日系动漫风格，精美二次元视觉小说立绘，剧场版光影，电影感，杰作，极高画质",
		"global_negative_prompt": "低质量，最差画质，模糊，粗糙，严重变形，畸形肢体，残缺肢体，画错的手脚，衰老褶皱，法令纹，眼袋，粗糙皮肤毛孔，皮肤下垂，丑陋，文字，水印，签名，作者名，字幕，对话框，字体，杂乱涂鸦，噪点",
		"character_base_prompt": "单人，半身立绘，站立姿态，纯白背景，干净背景",
		"bg_base_prompt": "场景插画，室内或室外背景，极高细节度，无人空镜头",
		"tts_voice_default": "zh-CN-YunxiNeural",
		"bg_width": 1024,
		"bg_height": 576,
		"char_width": 512,
		"char_height": 768,
		"prompt_templates": {
			"base_char_template": "{画质}, {画风}, {头身比}, {性别}{年龄}岁青年角色, {身高}{体型}, {脸型眼神}, {发型发色}, {肤色}, 穿着{服装风格}, {服装配色}, {服装材质}, {气质}气质, {表情}默认神情, {构图机位}, {光影氛围}, {尺寸定标}, 独立单人立绘, (单人:1.4), 纯白背景",
			"diff_template": "将图1中角色的面部表情修改为：{expression}。重点调整眉毛、眼神与嘴角微表情，神态自然生动；严格保持{name}原本的年轻动漫脸型与细腻平滑肌肤，绝对禁止衰老褶皱、法令纹与眼袋；保持镜头机位、半身构图、动作姿态与发型服装完全一致，{accessory_rule}。",
			"scale_anchor_enabled": true,
			"scale_rule_medium": "(标准匀称身形:1.1), (人物脚底紧贴画面底边基准线:1.3), (头顶适度留白15%:1.1), 170厘米标准身形画框比例",
			"scale_rule_petite": "(娇小低矮身形:1.3), (人物脚底紧贴画面底边基准线:1.3), (头顶保留24%大面积空旷留白:1.3), 160厘米娇小身形画框比例",
			"scale_rule_tall": "(高大挺拔身形:1.25), (人物脚底紧贴画面底边基准线:1.3), (头顶逼近画面上方, 顶部仅留8%微小留白:1.2), 180厘米以上身形画框比例"
		}
	}

# --- 资产清单加载与存储 (100% 绑定当前活动工程) ---
static func load_manifest() -> Array:
	var items: Array = []
	var pctx = _get_project_context()
	if pctx and pctx.active_project_data.has("asset_manifest") and (pctx.active_project_data["asset_manifest"] is Array):
		items = pctx.active_project_data["asset_manifest"]
	elif pctx and not str(pctx.active_project_dir).is_empty():
		var pjson = str(pctx.active_project_dir) + "project.json"
		if FileAccess.file_exists(pjson):
			var pdata = pctx.load_json_file(pjson)
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
	var pctx = _get_project_context()
	if pctx and not str(pctx.active_project_dir).is_empty():
		pctx.active_project_data["asset_manifest"] = items
		pctx.save_active_project()
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

	var pdir = _get_project_dir()
	var dm = _get_data_manager()
	if not dm:
		return items

	# 1. 扫描场景背景与BGM
	for sc_id in (dm.scenes if dm else {}):
		var sc = dm.scenes[sc_id]
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
	for d_id in (dm.dialogues if dm else {}):
		var diag = dm.dialogues[d_id]
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
	for clue_id in (dm.clues if dm else {}):
		var clue = dm.clues[clue_id]
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
						for cid in (dm.characters if dm else {}):
							var c = dm.characters[cid]
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
	var dm = _get_data_manager()
	for cid in (dm.characters if dm else {}):
		var c = dm.characters[cid]
		if c.get("name", "") == speaker or cid == speaker:
			return cid
	if speaker == "旁白" or "独白" in speaker or "内心" in speaker or speaker.is_empty():
		return "char_narrator"
	return "char_" + speaker.replace(" ", "_").to_lower()

# --- 实体资产结构化聚合 (Domain Entity Aggregator) ---
static func get_entities_summary(items: Array) -> Dictionary:
	var dm = _get_data_manager()
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
	for cid in (dm.characters if dm else {}):
		var c = dm.characters[cid]
		result["characters"][cid] = {
			"id": cid,
			"name": c.get("name", cid),
			"identity": c.get("identity", "登场人物"),
			"voice_role": c.get("voice", deduce_voice_role(c.get("name", cid))),
			"base_prompt": c.get("base_prompt", c.get("prompt", c.get("name", cid) + ", upper body portrait")),
			"negative_prompt": c.get("negative_prompt", ""),
			"character_sheet": c.get("character_sheet", {}),
			"turnaround": null,
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
			"turnaround": null,
			"sprites": [],
			"voices": [],
			"ready_count": 0,
			"total_count": 0
		}

	# 预先从 DataManager 载入已知场景
	for sc_id in (dm.scenes if dm else {}):
		var sc = dm.scenes[sc_id]
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
	for clue_id in (dm.clues if dm else {}):
		var clue = dm.clues[clue_id]
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
					for cid in (dm.characters if dm else {}):
						var c = dm.characters[cid]
						if c.get("name", "") in iname or cid in iid:
							r = c.get("name", "")
							break
				eid = deduce_character_entity_id(r)
				it["entity_type"] = etype
				it["entity_id"] = eid
				it["sub_type"] = "voice"
			elif itype == "background":
				etype = "scene"
				for sid in (dm.scenes if dm else {}):
					var s = dm.scenes[sid]
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
					"turnaround": null,
					"sprites": [],
					"voices": [],
					"ready_count": 0,
					"total_count": 0
				}
			var c_obj = result["characters"][eid]
			c_obj["total_count"] += 1
			if is_ready:
				c_obj["ready_count"] += 1

			if it.get("sub_type", "") == "turnaround" or it.get("type", "") == "turnaround":
				c_obj["turnaround"] = it
			elif it.get("sub_type", "") == "sprite" or it.get("type", "") == "character":
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

	# 检查并自动匹配角色的三视图概念文件 (Turnaround Sheet)
	var pdir = _get_project_dir()
	
	for cid in result["characters"]:
		if cid == "char_narrator":
			continue
		var c_obj = result["characters"][cid]
		if c_obj.get("turnaround") == null:
			var expected_rel = pdir + "assets/images/characters/char_%s_turnaround.png" % cid
			var expected_abs = ProjectSettings.globalize_path(expected_rel)
			var has_file = FileAccess.file_exists(expected_abs)
			var sheet = c_obj.get("character_sheet", {})
			var t_prompt = CharacterSheetMgr.assemble_three_view_prompt(sheet) if not sheet.is_empty() else "%s 全身三视图" % c_obj.get("name", cid)
			var t_neg = CharacterSheetMgr.get_three_view_negative_prompt(sheet) if not sheet.is_empty() else CharacterSheetMgr.TURNAROUND_NEGATIVE
			
			c_obj["turnaround"] = {
				"id": "char_%s_turnaround" % cid,
				"name": "%s 全身三视图 (Turnaround)" % c_obj.get("name", cid),
				"type": "turnaround",
				"entity_type": "character",
				"entity_id": cid,
				"character_id": cid,
				"sub_type": "turnaround",
				"prompt": t_prompt,
				"negative_prompt": t_neg,
				"local_path": expected_rel,
				"width": 1024,
				"height": 576,
				"status": "ready" if has_file else "pending"
			}

	return result

# --- 从全身三视图智能裁切提取正视半身立绘作为形象基准 (Plan A 黄金工作流) ---
static func extract_front_view_base_from_turnaround(turnaround_path: String, output_path: String) -> Dictionary:
	var abs_t_path = ProjectSettings.globalize_path(turnaround_path)
	if not FileAccess.file_exists(abs_t_path):
		return {"success": false, "error": "三视图文件不存在: " + turnaround_path}
	
	var img = Image.load_from_file(abs_t_path)
	if img == null or img.is_empty():
		return {"success": false, "error": "无法载入三视图图像: " + turnaround_path}
	
	var w = img.get_width()
	var h = img.get_height()
	
	# 正视图位于画布左侧约 42% 区域，扫描非白底/非透明的前景像素
	var max_scan_x = int(w * 0.42)
	var min_x = max_scan_x
	var max_x = 0
	var min_y = h
	var max_y = 0
	var fg_count = 0
	
	for y in range(h):
		for x in range(max_scan_x):
			var c = img.get_pixel(x, y)
			var is_white = (c.r > 0.94 and c.g > 0.94 and c.b > 0.94)
			if c.a > 0.1 and not is_white:
				fg_count += 1
				if x < min_x: min_x = x
				if x > max_x: max_x = x
				if y < min_y: min_y = y
				if y > max_y: max_y = y
	
	if fg_count < 100:
		# 兜底保底构图：以画布左侧 1/3 为黄金裁切区
		min_x = int(w * 0.08)
		max_x = int(w * 0.32)
		min_y = int(h * 0.06)
		max_y = int(h * 0.94)
	
	var center_x = int((min_x + max_x) / 2.0)
	var total_char_h = max_y - min_y
	
	# 半身立绘（Waist-up）：从头顶至腰跨，约占全身高度的 62%
	var crop_h = int(total_char_h * 0.62)
	var headroom = int(total_char_h * 0.06)
	var crop_top = max(0, min_y - headroom)
	if crop_top + crop_h > h:
		crop_h = h - crop_top
	
	# 严格 2:3 纵横比 (512x768)
	var crop_w = int(crop_h * (2.0 / 3.0))
	var crop_left = center_x - int(crop_w / 2.0)
	if crop_left < 0:
		crop_left = 0
	if crop_left + crop_w > w:
		crop_left = w - crop_w
	
	var crop_rect = Rect2i(crop_left, crop_top, crop_w, crop_h)
	var cropped_img = img.get_region(crop_rect)
	cropped_img.resize(512, 768, Image.INTERPOLATE_LANCZOS)
	
	var abs_out = ProjectSettings.globalize_path(output_path)
	var err = cropped_img.save_png(abs_out)
	if err != OK:
		return {"success": false, "error": "保存裁切半身立绘失败: %d" % err}
	
	# 自动执行 u2net 深度透明去背，使提取出的半身基准具备透明通道
	remove_image_background(abs_out)
	
	return {
		"success": true,
		"crop_rect": crop_rect,
		"output_path": output_path,
		"abs_output_path": abs_out
	}

static func remove_image_background(image_path: String) -> Dictionary:
	var abs_path = ProjectSettings.globalize_path(image_path)
	if not FileAccess.file_exists(abs_path):
		return {"success": false, "error": "文件不存在: " + abs_path}
	
	var py = get_python_executable()
	var bridge_script = ProjectSettings.globalize_path("res://tools/ai_bridge.py")
	var args = [
		bridge_script, "remove_background",
		"--image", abs_path,
		"--save", abs_path
	]
	var output = []
	var exit_code = OS.execute(py, args, output, true)
	if exit_code != OK:
		return {"success": false, "error": "透明抠图失败: %s" % "\n".join(output)}
	return {"success": true, "path": abs_path}

static func deduce_voice_role(speaker: String) -> String:
	var dm = _get_data_manager()
	if dm and dm.characters.has(speaker) and dm.characters[speaker].has("voice"):
		return dm.characters[speaker]["voice"]
	for cid in (dm.characters if dm else {}):
		var c = dm.characters[cid]
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
	
	if item_type in ["background", "character", "clue", "turnaround"] or item.get("sub_type", "") == "turnaround":
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
		var is_nunchaku = ckpt.to_lower().contains("nunchaku") or ckpt.to_lower().contains("qwen")
		
		if item_type == "background":
			# 场景背景模式：绝对封杀人物，注入广角空间透视与空镜氛围
			if is_nunchaku or is_anima:
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
			var pctx = _get_project_context()
			var dm = _get_data_manager()
			if dm and dm.characters.has(cid):
				char_data = dm.characters[cid]
			elif pctx and pctx.active_project_data.has("characters") and pctx.active_project_data["characters"].has(cid):
				char_data = pctx.active_project_data["characters"][cid]
			
			var char_base_dna = char_data.get("base_prompt", "")
			if char_base_dna.is_empty():
				char_base_dna = char_data.get("prompt", "")

			var is_male = item_prompt.contains("男") or item_prompt.contains("boy") or item_prompt.contains("he") or item.get("name", "").contains("沈策") or item.get("name", "").contains("温寻") or cid.contains("shen_ce") or cid.contains("wen_xun")
			var gender_prefix = "单人男性，" if is_male else "单人女性，"
			var gender_neg = "女性，少女，女人，" if is_male else "男性，少年，男人，胡子，胡茬，"
			var ui_neg = "对话框，台词框，气泡框，对话气泡，文字，字幕，台词，下方字幕，文本，英文字母，日文字符，中文字，水印，logo，边框，黑边，分镜框，乱码，"
			var anti_light_neg = "剧场暗调光影，强烈阴影，深重投影，彩色轮廓光，刺眼高光，严重偏色，高对比度，"
			var anti_dup_neg = "多重视图，多张重叠，两人同框，双人，两个角色，多余脑袋，双头，分屏，连环画分镜，多余手臂，多余躯体，小人，"

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
			
			var is_base_item = item.get("is_base", false) or item.get("id", "") == cid or item.get("id", "") == "char_" + cid or item.get("generation_mode", "") == "base"
			if base_sprite_path.is_empty() and not is_base_item:
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
			var has_glasses = char_base_dna.contains("眼镜") or char_base_dna.to_lower().contains("glasses") or item_prompt.contains("眼镜") or cid.contains("shen_ce")

			if is_nunchaku:
				if not base_sprite_path.is_empty() and not is_pose_mode:
					# --- 【Qwen-Image / Nunchaku 多模态指令级微表情差分 (全中文纯净指令)】 ---
					var expr_clean = item_prompt.strip_edges()
					var gender_word = "他" if is_male else "她"
					var gender_en = "his" if is_male else "her"
					var char_name = char_data.get("name", cid)
					var accessory_rule = "严格保持原图眼镜、服装与发型一致" if has_glasses else "严格保持原图服装与发型完全一致，脸上绝对不戴眼镜，无眼镜，无镜片，无镜框"
					
					var tpls = settings.get("prompt_templates", {})
					var diff_tpl = str(tpls.get("diff_template", ""))
					if diff_tpl.is_empty():
						diff_tpl = "将图1中角色的面部表情修改为：{expression}。重点调整眉毛、眼神与嘴角微表情，神态自然生动；严格保持{name}原本的年轻动漫脸型与细腻平滑肌肤，绝对禁止衰老褶皱、法令纹与眼袋；保持镜头机位、半身构图、动作姿态与发型服装完全一致，{accessory_rule}。"
					
					if item.has("qwen_diff_prompt") and not str(item.get("qwen_diff_prompt", "")).is_empty():
						final_prompt = str(item.get("qwen_diff_prompt"))
					else:
						# 角色属性自适应指令母版：支持用户在 UI 自定义模板并自动替换变量插槽
						final_prompt = diff_tpl.replace("{expression}", expr_clean)\
							.replace("{name}", char_name)\
							.replace("{gender_word}", gender_word)\
							.replace("{gender_en}", gender_en)\
							.replace("{accessory_rule}", accessory_rule)
					
					final_neg = "表情毫无变化，平静无神，面无表情，原样不变，与图1完全相同的表情，低质量，最差画质，模糊，粗糙，衰老，褶皱，老年，苍老，成熟脸，法令纹，笑纹，眼袋，鱼尾纹，深纹，粗糙皮肤毛孔，皮肤下垂，丑陋，衰朽"
					if not has_glasses:
						final_neg += "，眼镜，镜片，镜框，墨镜，太阳镜，单片镜，圆眼镜"
					if expr_clean.find("严厉") != -1 or expr_clean.find("质询") != -1 or expr_clean.find("愤怒") != -1 or expr_clean.find("严肃") != -1 or expr_clean.find("冷") != -1:
						final_neg += "，微笑，欢快，温和，高兴"
					elif expr_clean.find("笑") != -1 or expr_clean.find("开心") != -1 or expr_clean.find("喜") != -1:
						final_neg += "，愤怒，皱眉，严厉，哭泣，悲伤"
					args = [
						bridge_script, "generate_image",
						"--host", host,
						"--ckpt", ckpt,
						"--prompt", final_prompt,
						"--negative", final_neg,
						"--width", str(w),
						"--height", str(h),
						"--steps", "20",
						"--cfg", "2.5",
						"--timeout", "300",
						"--transparent", str(is_trans),
						"--save", abs_save_path,
						"--base_image", base_sprite_path,
						"--inpaint_face", "1"
					]
					print("[AIAssetMgr] 启动 Nunchaku Qwen-Image 指令级表情差分: %s (基准图: %s)" % [expr_clean, base_sprite_path])
				else:
					# 独立单人立绘生成 (基准立绘创建或姿态模式)
					# --- 统一世界观身高比例定标计算 (确保180cm与160cm在同画布保持真实身高差) ---
					var tpls = settings.get("prompt_templates", {})
					var scale_enabled = tpls.get("scale_anchor_enabled", true)
					var scale_phrase = ""
					if scale_enabled:
						var char_h_num = 175
						var h_raw = str(char_data.get("height", "")).to_lower()
						if h_raw.is_empty():
							h_raw = str(char_base_dna).to_lower()
						var regex = RegEx.new()
						regex.compile("(\\d{3})\\s*cm")
						var m = regex.search(h_raw)
						if m:
							char_h_num = int(m.get_string(1))
						
						if char_h_num >= 180:
							scale_phrase = str(tpls.get("scale_rule_tall", "(高大挺拔身形:1.25), (人物脚底紧贴画面底边基准线:1.3), (头顶逼近画面上方, 顶部仅留8%微小留白:1.2), 180厘米以上身形画框比例"))
						elif char_h_num <= 165:
							scale_phrase = str(tpls.get("scale_rule_petite", "(娇小低矮身形:1.3), (人物脚底紧贴画面底边基准线:1.3), (头顶保留24%大面积空旷留白:1.3), 160厘米娇小身形画框比例"))
						else:
							scale_phrase = str(tpls.get("scale_rule_medium", "(标准匀称身形:1.1), (人物脚底紧贴画面底边基准线:1.3), (头顶适度留白15%:1.1), 170厘米标准身形画框比例"))
					
					final_prompt = "(单人:1.5), 独立单人二次元立绘，纯白背景，" + item_prompt + "，" + char_base_dna + "，" + clean_char_style
					if not scale_phrase.is_empty():
						final_prompt += "，" + scale_phrase
					final_neg = anti_dup_neg + anti_light_neg + gender_neg + ui_neg + "衰老，褶皱，老年，苍老，成熟脸，法令纹，眼袋，鱼尾纹，粗糙毛孔，皮肤下垂，丑陋，复杂背景，多余肢体，低质量，模糊"
					if not has_glasses:
						final_neg += "，眼镜，镜片，镜框，墨镜"
					args = [
						bridge_script, "generate_image",
						"--host", host,
						"--ckpt", ckpt,
						"--prompt", final_prompt,
						"--negative", final_neg,
						"--width", str(w),
						"--height", str(h),
						"--steps", "20",
						"--cfg", "3.5",
						"--timeout", "300",
						"--transparent", str(is_trans),
						"--save", abs_save_path
					]
					if not base_sprite_path.is_empty():
						args.append_array(["--base_image", base_sprite_path])
					print("[AIAssetMgr] 启动 Nunchaku Qwen-Image 角色立绘生成: %s" % item.get("name", ""))
			elif is_pose_mode:
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
			if is_nunchaku or is_anima:
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
		elif item_type == "turnaround" or item.get("sub_type", "") == "turnaround":
			# 角色形象三视图 (支持 512x768 独立单视图 front/side/back 与 1024x576 全景概念母本)
			var cid = item.get("character_id", item.get("entity_id", ""))
			var char_data = {}
			var pctx = _get_project_context()
			var dm = _get_data_manager()
			if dm and dm.characters.has(cid):
				char_data = dm.characters[cid]
			elif pctx and pctx.active_project_data.has("characters") and pctx.active_project_data["characters"].has(cid):
				char_data = pctx.active_project_data["characters"][cid]
			
			var c_sheet = char_data.get("character_sheet", {})
			if c_sheet.is_empty():
				c_sheet = CharacterSheetMgr.create_default_sheet(char_data.get("name", cid), "男", 24)
			
			var view_type = item.get("view_type", "")
			if not view_type.is_empty() and view_type in ["front", "side", "back"]:
				# 独立高精单视图 (正面/侧面/背面，512x768 原生商业AVG插画)
				w = 512
				h = 768
				final_prompt = item_prompt
				if final_prompt.is_empty():
					final_prompt = CharacterSheetMgr.assemble_view_prompt(c_sheet, view_type)
				if not global_style.is_empty():
					final_prompt += "，" + global_style
				final_neg = item_neg
				if final_neg.is_empty():
					final_neg = CharacterSheetMgr.get_three_view_negative_prompt(c_sheet, view_type)
				elif view_type == "back" and not final_neg.contains("露出面部"):
					final_neg += "，(正面:1.7)，(半侧面:1.6)，(侧面:1.6)，(回头:1.7)，(回眸:1.7)，(扭头:1.6)，(露出面部:1.7)，(正脸:1.7)，(侧脸:1.6)，眼睛，瞳孔，眉毛，鼻子，嘴巴，嘴唇，前襟领带，胸口，胸部，正面视角，侧视，facing camera, looking back, looking at viewer, profile, side view, 3/4 view, turn around, looking over shoulder, face visible"
			else:
				# 1024x576 全景三视图概念母本
				w = 1024
				h = 576
				final_prompt = item_prompt
				if final_prompt.is_empty():
					final_prompt = CharacterSheetMgr.assemble_three_view_prompt(c_sheet)
				if not global_style.is_empty():
					final_prompt += "，" + global_style
				final_neg = item_neg
				if final_neg.is_empty():
					final_neg = CharacterSheetMgr.get_three_view_negative_prompt(c_sheet, view_type)
				elif view_type == "back" and not final_neg.contains("露出面部"):
					final_neg += "，(正面:1.7)，(半侧面:1.6)，(侧面:1.6)，(回头:1.7)，(回眸:1.7)，(扭头:1.6)，(露出面部:1.7)，(正脸:1.7)，(侧脸:1.6)，眼睛，瞳孔，眉毛，鼻子，嘴巴，嘴唇，前襟领带，胸口，胸部，正面视角，侧视，facing camera, looking back, looking at viewer, profile, side view, 3/4 view, turn around, looking over shoulder, face visible"
			
			if not view_type.is_empty() and view_type in ["front", "side", "back"]:
				is_trans = 1 # 独立三视图立绘自动生成透明通道，方便直接作为舞台立绘与形象基准
			else:
				is_trans = 0 # 16:9 全景概念母本保留白底设计图
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
			print("[AIAssetMgr] 启动角色形象三视图生成: %s (%s) -> %s" % [item.get("name", ""), ("全景16:9" if view_type.is_empty() else view_type), abs_save_path])
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

		if is_nunchaku and (item_type != "character" or item.get("sub_type", "") == "turnaround"):
			args.append_array(["--steps", "20", "--cfg", "3.5", "--timeout", "300"])

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
