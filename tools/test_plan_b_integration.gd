# tools/test_plan_b_integration.gd
extends Node

const AIAssetMgr = preload("res://editor/core/ai_asset_manager.gd")

func _ready() -> void:
	print("--- 开始方案 B 外部资产导入与状态持久化深度全真测试 ---")
	
	# 1. 确保加载活动工程
	ProjectContext.load_project("res://projects/case_gallery_rain/")
	
	# 2. 测试「待生成」能够成功修改为「已生成」并持久化（即使本地文件不存在）
	print("[1] 测试手动将无文件的素材标记为 ready 并防止被静默重置")
	var dummy_non_existent = {
		"id": "char_test_dummy_ghost",
		"name": "虚构待导入角色立绘",
		"type": "character",
		"entity_type": "character",
		"entity_id": "char_shen_ce",
		"local_path": "res://projects/case_gallery_rain/assets/images/characters/char_test_dummy_ghost.png",
		"status": "pending"
	}
	assert(not FileAccess.file_exists(dummy_non_existent["local_path"]), "前置条件：文件应不存在")
	
	# 手动改为 ready
	dummy_non_existent["status"] = "ready"
	var test_items = [dummy_non_existent]
	AIAssetMgr.refresh_manifest_status(test_items)
	assert(test_items[0]["status"] == "ready", "断言失败：用户标记的 ready 应该被保留，不应被强制设回 pending！")
	print("    ✅ 校验通过：用户手动标记的 ready 成功保留（即使文件不存在）！")
	
	# 3. 测试手动将有文件的素材标记为 pending（重绘需求）
	print("[2] 测试手动将有文件的素材标记为 pending 并防止被覆盖为 ready")
	var existing_item = {
		"id": "char_shen_ce",
		"name": "沈策",
		"type": "character",
		"local_path": "res://projects/case_gallery_rain/assets/images/characters/char_shen_ce.png",
		"status": "ready"
	}
	existing_item["status"] = "pending"
	var test_items2 = [existing_item]
	AIAssetMgr.refresh_manifest_status(test_items2)
	assert(test_items2[0]["status"] == "pending", "断言失败：用户标记的 pending 应该被保留！")
	print("    ✅ 校验通过：用户手动标记的 pending 成功保留！")
	
	# 4. 测试外部立绘文件自动扫描与装配 (Auto-discovery)
	print("[3] 测试目录扫描自动装配外部差分立绘 (如 char_shen_ce_vnccs_smile.png)")
	var dummy_sprite_path = "res://projects/case_gallery_rain/assets/images/characters/char_shen_ce_vnccs_smile.png"
	var abs_dummy_path = ProjectSettings.globalize_path(dummy_sprite_path)
	var f = FileAccess.open(abs_dummy_path, FileAccess.WRITE)
	assert(f != null, "创建虚拟外部立绘失败")
	f.store_string("DUMMY_IMAGE_DATA")
	f.close()
	
	var synced = AIAssetMgr.sync_manifest_with_project()
	var found_vnccs = false
	for it in synced:
		if it.get("id") == "char_shen_ce_vnccs_smile":
			found_vnccs = true
			assert(it.get("entity_id") == "char_shen_ce", "应该归属到沈策")
			assert(it.get("status") == "ready", "外部已存在的文件应为 ready")
			break
	
	assert(found_vnccs, "断言失败：未自动扫描识别外部差分立绘！")
	print("    ✅ 校验通过：成功自动发现外部新立绘并绑定至角色实体！")
	
	# 清理临时立绘
	DirAccess.remove_absolute(abs_dummy_path)
	
	# 5. 测试 ProjectContext 索引差分检索
	print("[4] 测试 ProjectContext 表情别名解析")
	ProjectContext.rebuild_asset_index()
	var p_portrait = ProjectContext.get_character_portrait("char_shen_ce")
	assert(not p_portrait.is_empty(), "基础立绘解析不应为空")
	print("    ✅ 校验通过：ProjectContext 立绘索引成功，基础立绘: %s" % p_portrait)
	
	# 6. 测试负向提示词配置
	print("[5] 测试防乱码与文字抑制负向提示词注入")
	var settings = AIAssetMgr.load_ai_settings()
	var neg = settings.get("global_negative_prompt", "")
	assert("text" in neg and "watermark" in neg and "signature" in neg, "负向词必须包含文字/水印/签名抑制")
	print("    ✅ 校验通过：当前全局负向提示词已注入强力文字抑制: %s" % neg.left(50))
	
	print("=== 方案 B 全部集成与修复测试 100% 通过！ ===")
	get_tree().quit(0)
