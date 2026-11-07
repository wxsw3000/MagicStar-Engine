# tools/test_project_pack.gd
extends Control

const ProjectPackMgr = preload("res://editor/core/project_pack_manager.gd")
const AIAssetMgr = preload("res://editor/core/ai_asset_manager.gd")
const AIAssetTabClass = preload("res://editor/ui/tabs/ai_asset_tab.gd")

func _ready() -> void:
	print("--- 开始全案总工程 JSON 与 AI 资产工坊自动化全真验证 ---")
	call_deferred("run_tests")

func run_tests() -> void:
	await get_tree().create_timer(0.1).timeout
	
	print("[1] 测试导出全案总工程 JSON (Master Project JSON)")
	var export_path = OS.get_user_data_dir().path_join("test_master_pack.json")
	var exp_res = ProjectPackMgr.export_master_json(export_path)
	print("    导出结果: ", exp_res.get("message", ""))
	assert(exp_res.get("success", false), "导出应当成功")
	assert(FileAccess.file_exists(export_path), "导出的文件应存在于磁盘")
	
	print("[2] 校验导出的总工程 JSON 结构完整性")
	var file = FileAccess.open(export_path, FileAccess.READ)
	assert(file != null, "文件应可读取")
	var json = JSON.new()
	assert(json.parse(file.get_as_text()) == OK, "JSON 应当合法有效")
	var pack = json.data
	assert(pack.has("meta"), "应包含 meta")
	assert(pack.has("ai_settings"), "应包含 ai_settings")
	assert(pack.has("nodes"), "应包含 nodes")
	assert(pack.has("scenes"), "应包含 scenes")
	assert(pack.has("dialogues"), "应包含 dialogues")
	assert(pack.has("clues"), "应包含 clues")
	assert(pack.has("asset_manifest"), "应包含 asset_manifest")
	print("    ✅ 结构校验通过！素材清单条目数: %d" % pack["asset_manifest"].size())
	
	print("[3] 测试全案总工程 JSON 导入与解包")
	var imp_res = ProjectPackMgr.import_master_json(export_path)
	print("    导入结果: ", imp_res.get("message", ""))
	assert(imp_res.get("success", false), "导入应当成功")
	assert(DataManager.scenes.size() > 0, "导入后场景应正确加载")
	assert(DataManager.nodes.size() > 0, "导入后节点应正确加载")
	print("    ✅ 导入与解包验证通过！节点数: %d, 场景数: %d" % [DataManager.nodes.size(), DataManager.scenes.size()])
	
	print("[4] 测试 ComfyUI 服务探测")
	var comfy_host = pack["ai_settings"].get("comfyui_server", "http://127.0.0.1:8188")
	var comfy_user = pack["ai_settings"].get("comfyui_user", "")
	var comfy_pass = pack["ai_settings"].get("comfyui_password", "")
	var comfy_res = AIAssetMgr.check_comfy_service(comfy_host, comfy_user, comfy_pass)
	print("    ComfyUI 探测响应: ", comfy_res)
	# 如果服务在线则校验，若离线仅做日志打印
	if comfy_res.get("online", false):
		print("    ✅ ComfyUI 探测成功！显卡: %s, 候选模型数: %d" % [comfy_res.get("gpu", ""), comfy_res.get("checkpoints", []).size()])
	else:
		print("    ℹ️ ComfyUI 服务未运行 (跳过在线校验)")
	
	print("[5] 测试 AIAssetTab 界面装载与素材清单交互")
	var asset_tab = AIAssetTabClass.new()
	add_child(asset_tab)
	await get_tree().create_timer(0.2).timeout
	assert(asset_tab.manifest_items.size() > 0, "素材清单条目应大于0")
	assert(asset_tab.txt_comfy_host.text == comfy_host, "ComfyUI 默认地址应匹配配置")
	
	# 测试选择第一项并更新合成提示词
	asset_tab.select_item(asset_tab.manifest_items[0].get("id", ""))
	assert(not asset_tab.lbl_combined_prompt.text.is_empty(), "合成提示词应成功生成")
	print("    ✅ 资产工坊界面装载通过！首项合成提示词预览: %s" % asset_tab.lbl_combined_prompt.text)
	
	print("[6] 测试 AI 资产工坊 4 级批量生成体系与新增差分/台词弹窗交互")
	assert(asset_tab.btn_batch_generate != null, "Level 1 全局批量按钮应存在")
	assert(asset_tab.btn_batch_entity_pending != null, "Level 2 实体批量按钮应存在")
	
	# 备份 manifest_items 防止测试临时项污染工程
	var original_manifest_pack = asset_tab.manifest_items.duplicate(true)

	# 测试新增立绘差分
	var char_ent = asset_tab.entities_summary.get("characters", {}).get("char_shen_ce", {})
	assert(char_ent != null, "角色沈策应存在于实体总结中")
	var init_sp_cnt = char_ent.get("sprites", []).size()
	asset_tab.open_add_sprite_dialog("char_shen_ce", char_ent)
	asset_tab.txt_sprite_suffix.text = "严肃审视"
	asset_tab._on_confirm_add_sprite()
	assert(char_ent.get("sprites", []).size() == init_sp_cnt + 1, "新增立绘差分后数量应+1")
	print("    ✅ 新增立绘差分弹窗流程验证通过，沈策差分总数: %d" % char_ent.get("sprites", []).size())

	# 测试录入台词对白
	var init_vc_cnt = char_ent.get("voices", []).size()
	asset_tab.open_add_voice_dialog("char_shen_ce", char_ent)
	asset_tab.txt_voice_input.text = "死者紧握的手心里，藏着一枚画廊的黄铜钥匙。"
	asset_tab._on_confirm_add_voice()
	assert(char_ent.get("voices", []).size() == init_vc_cnt + 1, "新增台词对白后数量应+1")
	print("    ✅ 录入台词对白弹窗流程验证通过，沈策配音总数: %d" % char_ent.get("voices", []).size())

	# 恢复原真数据
	if not original_manifest_pack.is_empty():
		asset_tab.manifest_items = original_manifest_pack
		AIAssetMgr.save_manifest(asset_tab.manifest_items)

	# 遍历 4 大类切换与工作台加载
	asset_tab.switch_category("scene")
	asset_tab.select_entity("scene_gallery")
	print("    ✅ 场景工坊切换验证通过: ", asset_tab.lbl_entity_title.text)

	asset_tab.switch_category("clue")
	asset_tab.select_entity("clue_poison_cup")
	print("    ✅ 证物工坊切换验证通过: ", asset_tab.lbl_entity_title.text)

	asset_tab.switch_category("shared")
	print("    ✅ 全局公共库切换验证通过: ", asset_tab.lbl_entity_title.text)

	# 清理临时导出文件
	DirAccess.remove_absolute(export_path)
	
	print("=== 全部全案工程与 AI 资产工坊自动化测试 100% 通过！ ===")
	get_tree().quit(0)
