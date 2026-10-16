# tools/test_import_ai_project.gd
extends Control

func _ready() -> void:
	print("--- 开始第三方 AI 故事 JSON 自动创建项目全流程自动化测试 ---")
	call_deferred("run_test")

func run_test() -> void:
	await get_tree().create_timer(0.1).timeout
	
	# 1. 模拟第三方 AI 输出的完整故事大 JSON
	var mock_ai_json = {
		"$schema": "https://magicstar.avg/schema/v1/project_master.json",
		"meta": {
			"project_id": "case_orient_phantom_" + str(int(Time.get_unix_time_from_system())),
			"game_title": "东方快车幽灵案",
			"author": "第三方AI创作者",
			"description": "列车在大雪中脱轨停滞，车厢内发生神秘失踪案..."
		},
		"ai_settings": {
			"comfyui_server": "http://127.0.0.1:8188",
			"comfyui_user": "",
			"comfyui_password": "",
			"checkpoint": "sd_xl_turbo_1.0.safetensors",
			"global_style_prompt": "masterpiece, anime visual novel, snow express train mystery, dramatic cold lighting",
			"global_negative_prompt": "worst quality, low quality, bad anatomy"
		},
		"nodes": {
			"node_train_01": {
				"id": "node_train_01",
				"title": "幽灵号停车",
				"type": "story",
				"dialogue": "diag_train_intro",
				"next": "node_train_explore"
			},
			"node_train_explore": {
				"id": "node_train_explore",
				"title": "头等车厢搜证",
				"type": "explore",
				"scene": "scene_first_class"
			},
			"node_train_reason": {
				"id": "node_train_reason",
				"title": "戳破车长的谎言",
				"type": "reasoning",
				"reasoning_id": "reason_conductor_ticket"
			},
			"node_train_ending": {
				"id": "node_train_ending",
				"title": "风雪破晓",
				"type": "ending",
				"ending_id": "ending_train_clear"
			}
		},
		"scenes": {
			"scene_first_class": {
				"id": "scene_first_class",
				"name": "豪华头等车厢",
				"prompt": "interior of luxurious vintage express train cabin, snowy blizzard outside window, wooden paneling, art deco lamps",
				"explore_points": [
					{
						"id": "point_ticket",
						"name": "撕碎的车票",
						"rect": [0.3, 0.4, 0.1, 0.1],
						"type": "once",
						"trigger": {"action": "clue", "target": "clue_ripped_ticket"}
					}
				]
			}
		},
		"dialogues": {
			"diag_train_intro": {
				"id": "diag_train_intro",
				"lines": [
					{
						"speaker": "列车长",
						"text": "大雪封山了，各位乘客请待在自己的包厢内，不要随意走动。"
					}
				]
			}
		},
		"clues": {
			"clue_ripped_ticket": {
				"id": "clue_ripped_ticket",
				"title": "撕碎的特等车票",
				"description": "车票上的座位号是7号，但旅客名单上7号座位显示无人预订！",
				"type": "item"
			}
		},
		"characters": {
			"conductor": {
				"id": "conductor",
				"name": "严厉的车长",
				"prompt": "1man, middle-aged european train conductor, navy blue uniform, brass buttons, stern expression, mustache, waist-up portrait"
			}
		},
		"reasonings": {
			"reason_conductor_ticket": {
				"id": "reason_conductor_ticket",
				"title": "推翻车长的无人论",
				"question": "车长声称7号包厢从未有人入住，哪个证物能证明他在撒谎？",
				"required_clues": ["clue_ripped_ticket"],
				"next_node": "node_train_ending"
			}
		},
		"endings": {
			"ending_train_clear": {
				"id": "ending_train_clear",
				"title": "破晓终局：幽灵现形",
				"description": "随着被隐匿的车票被搜出，神秘乘客的身份终于水落石出！"
			}
		}
	}
	
	# 2. 将模拟 JSON 存为外部临时文件
	var temp_json_path = "res://tools/temp_mock_ai_story.json"
	var f = FileAccess.open(temp_json_path, FileAccess.WRITE)
	assert(f != null, "临时测试 JSON 必须能写入")
	f.store_string(JSON.stringify(mock_ai_json, "\t"))
	f.close()
	print("    ✅ 模拟第三方 AI 故事 JSON 创建完成: %s" % temp_json_path)
	
	# 3. 执行 ProjectContext.import_project_from_json 自动创建项目
	print("[2] 执行从 AI 故事 JSON 自动创建项目")
	var res = ProjectContext.import_project_from_json(temp_json_path)
	print("    导入返回结果: ", res)
	assert(res.get("success", false), "AI 故事 JSON 自动导入创建工程必须成功")
	var proj_path = res.get("path", "")
	assert(DirAccess.dir_exists_absolute(proj_path), "新建项目目录必须存在")
	assert(FileAccess.file_exists(proj_path + "project.json"), "新建项目 project.json 必须存在")
	print("    ✅ 成功自动创建独立工程: %s" % proj_path)
	
	# 4. 验证 DataManager 与资产清单已同步
	print("[3] 验证 DataManager 核心数据状态")
	assert(DataManager.nodes.has("node_train_01"), "节点流中必须包含 node_train_01")
	assert(DataManager.scenes.has("scene_first_class"), "场景中必须包含 scene_first_class")
	assert(DataManager.clues.has("clue_ripped_ticket"), "线索库中必须包含 clue_ripped_ticket")
	assert(DataManager.reasonings.has("reason_conductor_ticket"), "推理库中必须包含 reason_conductor_ticket")
	print("    ✅ DataManager 校验 100% 吻合！")
	
	# 5. 验证资产工坊 manifest 自动推导补齐
	print("[4] 验证 AI 资产工坊清单自动生成")
	var AIAssetMgr = load("res://editor/core/ai_asset_manager.gd")
	var manifest = AIAssetMgr.load_manifest()
	assert(manifest.size() >= 2, "应自动从场景与角色推导出至少2项待生成素材清单")
	var has_bg = false
	var has_char = false
	var has_voice = false
	for it in manifest:
		if it.get("type") == "background":
			has_bg = true
			assert("luxurious vintage express train" in it.get("prompt"), "背景提示词必须正确捕获")
		elif it.get("type") == "character":
			has_char = true
			assert("train conductor" in it.get("prompt"), "角色提示词必须正确捕获")
		elif it.get("type") == "voice":
			has_voice = true
	assert(has_bg, "必须包含自动推导的场景背景素材待生成项")
	assert(has_char, "必须包含自动推导的角色立绘素材待生成项")
	assert(has_voice, "必须包含自动推导的对白配音素材待生成项")
	print("    ✅ AI 资产清单推导验证通过，待生成的素材总条数(含背景、立绘与配音): %d" % manifest.size())
	
	# 6. 清理临时测试文件与测试工程
	DirAccess.remove_absolute(temp_json_path)
	var abs_proj = ProjectSettings.globalize_path(proj_path)
	OS.execute("cmd.exe", ["/c", "rmdir", "/s", "/q", abs_proj])
	
	# 切回当前活动工程
	var p_list = ProjectContext.get_projects_list()
	if not p_list.is_empty():
		ProjectContext.load_project(p_list[0]["dir_path"])
	
	print("=== 第三方 AI 故事 JSON 自动创建项目全流程自动化测试 100% 通过！ ===")
	get_tree().quit(0)
