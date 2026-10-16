# editor/core/ai_asset_manager.gd
# AI 资产工坊核心管理器：管理配置、资产清单、ComfyUI生图与TTS调度
class_name AIAssetManager
extends RefCounted

const AI_CONFIG_PATH = "res://config/ai_settings.json"
const MANIFEST_PATH = "res://data/assets/asset_manifest.json"

const STYLE_PRESETS = {
	"dark_mystery": {
		"id": "dark_mystery",
		"name": "🎬 本格悬疑黑金风 (默认)",
		"prompt": "masterpiece, best quality, anime visual novel, dark mystery, cinematic dramatic lighting, sharp shadows",
		"negative": "worst quality, low quality, blurry, text, watermark, bad anatomy, deformed limbs, oversaturated"
	},
	"ghibli": {
		"id": "ghibli",
		"name": "🌿 宫崎骏 / 吉卜力手绘风",
		"prompt": "studio ghibli style, hayao miyazaki aesthetic, hand-painted gouache illustration, lush vibrant colors, nostalgic anime masterpiece, soft warm sunlight, emotional warmth",
		"negative": "photorealistic, 3d render, plastic skin, harsh cgi, dark gloomy, neon, modern digital, worst quality"
	},
	"western_fantasy": {
		"id": "western_fantasy",
		"name": "🏰 欧美奇幻 / 写实风",
		"prompt": "cinematic realism, western fantasy concept art, oil painting texture, rembrandt lighting, dramatic atmospheric depth, intricate textures, 8k cinematic",
		"negative": "anime, manga, 2d cartoon, flat shading, oversaturated, deformed, bad anatomy, worst quality"
	},
	"japanese_wafuu": {
		"id": "japanese_wafuu",
		"name": "⛩️ 日式二次元 / 和风",
		"prompt": "japanese anime visual novel, wafuu aesthetic, ukiyo-e undertone, clean fine lineart, elegant traditional japanese atmosphere, dramatic anime lighting, masterpiece",
		"negative": "western comic, 3d, realistic photograph, gritty, noisy, monochrome, worst quality"
	},
	"chinese_guofeng": {
		"id": "chinese_guofeng",
		"name": "🏮 中式国风 / 仙侠水墨",
		"prompt": "chinese traditional aesthetics, elegant guofeng illustration, subtle ink wash gradient, soft jade and cinnabar color palette, ethereal poetic atmosphere, masterpiece",
		"negative": "western fantasy, anime eyes, harsh cgi, neon, modern elements, messy, worst quality"
	},
	"cute_chibi": {
		"id": "cute_chibi",
		"name": "🧸 卡通风 / Q版萌系",
		"prompt": "cute chibi style, kawaii 2D cartoon, big expressive eyes, rounded proportions, soft pastel palette, clean outline, storybook illustration, adorable character design",
		"negative": "realistic, grim, dark, creepy, hyper-detailed muscles, scary, blood, ugly, worst quality"
	},
	"dark_cthulhu": {
		"id": "dark_cthulhu",
		"name": "👁️ 暗黑 / 恐怖 / 克苏鲁",
		"prompt": "lovecraftian cosmic horror, dark eerie atmosphere, beksinski influence, eldritch shadows, sickly cold desaturated palette, unsettling mist, psychological horror",
		"negative": "bright, cheerful, cute, anime idol, colorful, happy, sunny, oversaturated, worst quality"
	},
	"pixel_retro": {
		"id": "pixel_retro",
		"name": "👾 像素 / 复古 16-bit",
		"prompt": "masterpiece pixel art, 16-bit retro visual novel aesthetic, crisp pixel edges, nostalgic point-and-click game style, dithered shading, pc-98 aesthetic",
		"negative": "smooth gradient, blurry, photorealistic, vector art, 3d render, modern cgi, worst quality"
	},
	"watercolor_art": {
		"id": "watercolor_art",
		"name": "🎨 水彩 / 手绘 / 艺术画风",
		"prompt": "dreamy watercolor painting, wet-on-wet technique, delicate brush strokes, bleeding pigments on textured cotton paper, artistic splatters, fine art storybook",
		"negative": "digital cgi, plastic 3d, sharp harsh lines, photograph, flat fill, neon, worst quality"
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

# --- 配置加载与存储 (100% 绑定当前活动工程) ---
static func load_ai_settings() -> Dictionary:
	if ProjectContext.active_project_data.has("ai_settings") and (ProjectContext.active_project_data["ai_settings"] is Dictionary):
		return ProjectContext.active_project_data["ai_settings"]
	elif not ProjectContext.active_project_dir.is_empty():
		var pjson = ProjectContext.active_project_dir + "project.json"
		if FileAccess.file_exists(pjson):
			var pdata = ProjectContext.load_json_file(pjson)
			if pdata.has("ai_settings"):
				return pdata["ai_settings"]
	if FileAccess.file_exists(AI_CONFIG_PATH):
		var file = FileAccess.open(AI_CONFIG_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
				return json.data
	return get_default_ai_settings()

static func save_ai_settings(settings: Dictionary) -> bool:
	if not ProjectContext.active_project_dir.is_empty():
		ProjectContext.active_project_data["ai_settings"] = settings
		ProjectContext.save_active_project()
		return true
	var dir = AI_CONFIG_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file = FileAccess.open(AI_CONFIG_PATH, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify(settings, "\t"))
	file.close()
	return true

static func get_default_ai_settings() -> Dictionary:
	return {
		"comfyui_server": "http://127.0.0.1:8188",
		"comfyui_user": "",
		"comfyui_password": "",
		"checkpoint": "sd_xl_turbo_1.0.safetensors",
		"global_style_prompt": "masterpiece, best quality, anime visual novel, victorian dark mystery, cinematic lighting",
		"global_negative_prompt": "worst quality, low quality, blurry, text, watermark, bad anatomy, deformed limbs, noisy",
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
		if not path.is_empty() and (FileAccess.file_exists(path) or FileAccess.file_exists(ProjectSettings.globalize_path(path))):
			item["status"] = "ready"
		else:
			item["status"] = "pending"

# --- 自动同步与搜集全案资产 ---
static func sync_manifest_with_project() -> Array:
	var items = load_manifest()
	var item_map = {}
	for it in items:
		item_map[it.get("id", "")] = it

	# 1. 扫描场景背景与BGM
	for sc_id in DataManager.scenes:
		var sc = DataManager.scenes[sc_id]
		var bg_path = sc.get("background", "")
		if not bg_path.is_empty():
			var bg_id = bg_path.get_file().get_basename()
			if not item_map.has(bg_id):
				var new_item = {
					"id": bg_id,
					"type": "background",
					"name": sc.get("name", bg_id),
					"prompt": sc.get("name", "") + ", victorian mystery scene, interior architecture",
					"local_path": bg_path,
					"width": 1920,
					"height": 1080,
					"status": "ready" if FileAccess.file_exists(bg_path) else "pending"
				}
				items.append(new_item)
				item_map[bg_id] = new_item
				
		var bgm_path = sc.get("bgm", "")
		if not bgm_path.is_empty():
			var bgm_id = bgm_path.get_file().get_basename()
			if not item_map.has(bgm_id):
				var new_item = {
					"id": bgm_id,
					"type": "bgm",
					"name": "场景BGM - " + sc.get("name", bgm_id),
					"prompt": "Solo acoustic piano in D-minor, dark mystery, melancholic",
					"local_path": bgm_path,
					"status": "ready" if FileAccess.file_exists(bgm_path) else "pending"
				}
				items.append(new_item)
				item_map[bgm_id] = new_item

	# 2. 扫描对话中的角色立绘与配音
	var pdir = ProjectContext.active_project_dir
	if pdir.is_empty():
		pdir = "res://projects/case_01/"
	if not pdir.ends_with("/"):
		pdir += "/"

	for d_id in DataManager.dialogues:
		var diag = DataManager.dialogues[d_id]
		var lines = diag.get("lines", [])
		for idx in range(lines.size()):
			var line = lines[idx]
			if not (line is Dictionary):
				continue
				
			var char_img = line.get("character_image", "")
			if not char_img.is_empty():
				var cid = char_img.get_file().get_basename()
				if not item_map.has(cid):
					var new_item = {
						"id": cid,
						"type": "character",
						"name": line.get("speaker", "角色") + " 立绘",
						"character_id": line.get("speaker", ""),
						"prompt": line.get("speaker", "") + ", upper body portrait, simple background",
						"local_path": char_img,
						"width": 512,
						"height": 768,
						"status": "ready" if (FileAccess.file_exists(char_img) or FileAccess.file_exists(ProjectSettings.globalize_path(char_img))) else "pending"
					}
					items.append(new_item)
					item_map[cid] = new_item
					
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
					var speaker = line.get("speaker", "旁白")
					var voice_role = deduce_voice_role(speaker)
					var new_item = {
						"id": vid,
						"type": "voice",
						"name": speaker + " 配音: " + text.left(10) + ("..." if text.length() > 10 else ""),
						"role": speaker,
						"text": text,
						"voice_role": voice_role,
						"local_path": voice,
						"status": "ready" if (FileAccess.file_exists(voice) or FileAccess.file_exists(ProjectSettings.globalize_path(voice))) else "pending"
					}
					items.append(new_item)
					item_map[vid] = new_item

	refresh_manifest_status(items)
	save_manifest(items)
	return items

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
static func generate_asset_item(item: Dictionary, settings: Dictionary) -> Dictionary:
	var item_type = item.get("type", "")
	var local_path = get_sandboxed_asset_path(item)
	var abs_save_path = ProjectSettings.globalize_path(local_path)
	DirAccess.make_dir_recursive_absolute(abs_save_path.get_base_dir())
	var bridge_script = ProjectSettings.globalize_path("res://tools/ai_bridge.py")
	
	if item_type in ["background", "character"]:
		var host = settings.get("comfyui_server", "http://127.0.0.1:8188")
		var user = settings.get("comfyui_user", "")
		var password = settings.get("comfyui_password", "")
		var ckpt = settings.get("checkpoint", "sd_xl_turbo_1.0.safetensors")
		var global_style = settings.get("global_style_prompt", "")
		var global_neg = settings.get("global_negative_prompt", "")
		var item_prompt = item.get("prompt", "")
		var final_prompt = ""
		var final_neg = global_neg
		var w = 512
		var h = 768
		var is_trans = 0
		
		if item_type == "background":
			# 场景背景模式：绝对封杀人物，注入广角空间透视与空镜氛围
			var bg_prefix = "(scenery:1.4), (empty room:1.3), (no humans:1.5), wide angle interior architecture, environment concept, "
			final_prompt = bg_prefix + global_style + ", " + item_prompt
			final_neg = "(humans:1.6), (1girl:1.6), (1boy:1.6), (people:1.6), (character:1.5), crowd, face, " + global_neg
			w = 960
			h = 540
			is_trans = 0
		elif item_type == "character":
			# 角色立绘模式：强制纯白底与半身独立站姿，确保 AI 100% 干净抠图
			var char_prefix = "(solo:1.4), (waist-up portrait:1.3), (standing pose:1.2), (pure white background:1.5), (simple background:1.4), isolated, studio portrait, "
			final_prompt = char_prefix + global_style + ", " + item_prompt
			final_neg = "complex background, scenery, outdoors, indoors, furniture, room, wallpaper, extra fingers, bad anatomy, " + global_neg
			w = 512
			h = 768
			is_trans = 1
		else:
			final_prompt = global_style + ", " + item_prompt
		
		var args = [
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
		if not user.is_empty():
			args.append_array(["--user", user])
		if not password.is_empty():
			args.append_array(["--password", password])
		
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
