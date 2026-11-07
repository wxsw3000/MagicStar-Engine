# tools/test_vnccs_and_pose.gd
extends Control

const PoseMannequinClass = preload("res://editor/ui/pose_editor/pose_mannequin_3d.gd")
const PoseEditorDialogClass = preload("res://editor/ui/pose_editor/pose_editor_dialog.gd")
const AIAssetMgr = preload("res://editor/core/ai_asset_manager.gd")
const AIAssetTabClass = preload("res://editor/ui/tabs/ai_asset_tab.gd")

func _ready() -> void:
	print("--- 开始 VNCCS 角色一致性与 3D 姿态工坊集成全真测试 ---")
	call_deferred("run_tests")

func run_tests() -> void:
	await get_tree().create_timer(0.1).timeout
	
	print("[1] 测试 PoseMannequin3D 节点实例化与骨骼层级构造")
	var mannequin = PoseMannequinClass.new()
	add_child(mannequin)
	assert(mannequin.root_node != null, "Root 节点必须存在")
	assert(mannequin.hips_node != null, "Hips 节点必须存在")
	assert(mannequin.torso_node != null, "Torso 节点必须存在")
	assert(mannequin.head_node != null, "Head 节点必须存在")
	assert(mannequin.shoulder_l != null, "ShoulderL 节点必须存在")
	assert(mannequin.shoulder_r != null, "ShoulderR 节点必须存在")
	assert(mannequin.hip_l != null, "HipL 节点必须存在")
	assert(mannequin.hip_r != null, "HipR 节点必须存在")
	assert(mannequin.mesh_instances.size() >= 16, "应生成至少 16 个身体/关节网格组件")
	print("    ✅ 3D 人偶骨骼层级完整！组件网格数: %d" % mannequin.mesh_instances.size())

	print("[2] 测试 8 大常用立绘姿态预设库应用")
	var expected_presets = [
		"standing_calm", "crossed_arms", "chin_touch", "pointing_accuse",
		"hands_on_hips", "pocket_hands", "shrug_spread", "hold_clue"
	]
	for p_key in expected_presets:
		assert(PoseMannequinClass.PRESETS.has(p_key), "必须包含预设: " + p_key)
		mannequin.apply_preset(p_key)
		assert(mannequin.current_preset == p_key, "当前动作应更新为: " + p_key)
	print("    ✅ 8 套 AVG 常用立绘姿态预设切换全部成功！")

	print("[3] 测试 3D 灰模与 OpenPose 骨架着色渲染模式切换")
	mannequin.set_display_mode("openpose")
	assert(mannequin.display_mode == "openpose", "模式应为 openpose")
	var first_mat = mannequin.mesh_instances[0].material_override as StandardMaterial3D
	assert(first_mat != null and first_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "OpenPose 必须为无光照纯色以供 ControlNet 识别")
	
	mannequin.set_display_mode("dummy")
	assert(mannequin.display_mode == "dummy", "模式应为 dummy")
	print("    ✅ 灰模/OpenPose 材质模式实时切换验证通过！")
	mannequin.queue_free()

	print("[4] 测试 PoseEditorDialog 姿态工坊弹窗创建与视口构建")
	var dlg = PoseEditorDialogClass.new()
	add_child(dlg)
	assert(dlg.sub_viewport != null, "必须包含独立的 SubViewport 视口")
	assert(dlg.camera != null, "视口内必须包含 Camera3D 相机")
	assert(dlg.mannequin != null, "视口内必须嵌入 PoseMannequin3D 人偶")
	assert(dlg.vbox_presets.get_child_count() >= 8, "左侧预设列表至少包含 8 个快捷按钮")
	
	# 测试角色打开初始化
	var dummy_ent = {"name": "沈策", "base_prompt": "1boy, male detective"}
	dlg.open_for_character("char_shen_ce", dummy_ent)
	assert(dlg.character_id == "char_shen_ce", "角色 ID 绑定正确")
	assert(dlg.character_name == "沈策", "角色名称绑定正确")
	print("    ✅ 3D 姿态工坊弹窗与交互视口构建验证通过！")
	dlg.queue_free()

	print("[5] 测试 AIAssetTab 角色基准立绘标记 (Base Anchor)")
	var tab = AIAssetTabClass.new()
	add_child(tab)
	assert(tab.dlg_pose_editor != null, "AIAssetTab 应当挂载 dlg_pose_editor")
	
	# 备份当前真实的 manifest_items，确保测试不污染工程数据
	var original_manifest = tab.manifest_items.duplicate(true)
	
	# 模拟角色立绘素材并测试 set_character_base_sprite
	tab.manifest_items = [
		{
			"id": "char_mock_base",
			"entity_id": "char_mock",
			"character_id": "char_mock",
			"type": "character",
			"sub_type": "sprite",
			"name": "测试 基础立绘",
			"local_path": "res://projects/case_gallery_rain/assets/images/characters/char_mock.png",
			"is_base": true,
			"status": "ready"
		},
		{
			"id": "char_mock_diff_1",
			"entity_id": "char_mock",
			"character_id": "char_mock",
			"type": "character",
			"sub_type": "sprite",
			"name": "测试 差分: 冷笑",
			"local_path": "res://projects/case_gallery_rain/assets/images/characters/char_mock_diff_1.png",
			"is_base": false,
			"status": "pending"
		}
	]
	
	# 将 diff_1 改设为基准
	tab.set_character_base_sprite("char_mock", tab.manifest_items[1])
	assert(tab.manifest_items[1]["is_base"] == true, "diff_1 应被设为基准")
	assert(tab.manifest_items[0]["is_base"] == false, "原 base 应降级为差分")
	assert(tab.manifest_items[0]["base_sprite_path"] == "res://projects/case_gallery_rain/assets/images/characters/char_mock_diff_1.png", "原 base 应继承新 base 的路径")
	print("    ✅ 角色形象基准锚点切换与差分继承关系校验通过！")
	
	# 恢复原真数据并安全存盘
	if not original_manifest.is_empty():
		tab.manifest_items = original_manifest
		AIAssetMgr.save_manifest(tab.manifest_items)
	
	print("[6] 测试 3D 姿态提示词与中英双语解析")
	for p_key in expected_presets:
		var zh_p = PoseMannequinClass.get_preset_prompt(p_key, true)
		var en_p = PoseMannequinClass.get_preset_prompt(p_key, false)
		assert(not zh_p.is_empty(), "预设 %s 必须包含中文提示词" % p_key)
		assert(not en_p.is_empty(), "预设 %s 必须包含英文提示词" % p_key)
	print("    ✅ 8 大 3D 动作姿态中英文提示词映射全部就绪！")

	print("[7] 测试差分立绘卡片 3D 姿态下拉选择与联动构建")
	var test_card_item = {
		"id": "char_shen_ce_test",
		"entity_id": "char_shen_ce",
		"character_id": "char_shen_ce",
		"name": "沈策 差分: 冷笑嘲讽",
		"prompt": "眼神凌厉冰冷，嘴角微挑露出一抹戏谑微嘲的冷笑",
		"pose_preset": "crossed_arms",
		"is_base": false,
		"local_path": "res://projects/case_gallery_rain/assets/images/characters/char_shen_ce_vnccs_smile.png"
	}
	var card = tab.create_sprite_card(test_card_item)
	assert(card != null, "卡片应成功创建")
	# 检查卡片是否包含了动作姿态行与 OptionButton
	var found_pose_opt = false
	for ch in card.get_child(0).get_child(0).get_children():
		if ch is HBoxContainer:
			for sub_ch in ch.get_children():
				if sub_ch is OptionButton and sub_ch.item_count == 8:
					found_pose_opt = true
					assert(sub_ch.selected == 1, "crossed_arms 对应的索引应为 1")
					break
	assert(found_pose_opt, "立绘卡片内必须包含 8 项姿态选择下拉控件")
	print("    ✅ 差分卡片 3D 姿态预设下拉选择栏与联动构建验证通过！")
	card.queue_free()

	print("[8] 验证沈策差分相册三层架构 (Base DNA + 专属中文微表情 + 3D 动作姿态)")
	var shen_ce_ent = ProjectContext.active_project_data.get("characters", {}).get("char_shen_ce", {})
	assert(shen_ce_ent.has("base_prompt") and not str(shen_ce_ent["base_prompt"]).is_empty(), "角色必须拥有独立 Base DNA 形象提示词")
	print("    🌟 底层形象 DNA: ", shen_ce_ent["base_prompt"])

	var m_items = AIAssetMgr.load_manifest()
	var shen_ce_sprites = []
	for it in m_items:
		if it is Dictionary and it.get("character_id", "") == "char_shen_ce" and (it.get("sub_type", "") == "sprite" or it.get("type", "") == "character"):
			shen_ce_sprites.append(it)
	
	assert(shen_ce_sprites.size() == 11, "沈策立绘总数应为 11 项 (1 基础 + 10 差分)，当前为: %d" % shen_ce_sprites.size())
	
	var seen_prompts = {}
	for sp in shen_ce_sprites:
		var p_text = sp.get("prompt", "").strip_edges()
		assert(not p_text.is_empty(), "立绘差分提示词不能为空: " + sp.get("name", ""))
		assert(not seen_prompts.has(p_text), "发现重复提示词！立绘差分必须各具特色: %s 与 %s" % [sp.get("name", ""), seen_prompts.get(p_text, "")])
		seen_prompts[p_text] = sp.get("name", "")
		assert(sp.has("pose_preset") and not str(sp["pose_preset"]).is_empty(), "立绘差分必须绑定 3D 姿态预设: " + sp.get("name", ""))
		# 验证提示词为中文
		var has_chinese = false
		for i in range(p_text.length()):
			var c = p_text.unicode_at(i)
			if c >= 0x4E00 and c <= 0x9FA5:
				has_chinese = true
				break
		assert(has_chinese, "立绘提示词必须为中文: " + p_text)
	
	print("    ✅ 沈策相册全部 11 套立绘差分已 100% 具备专属中文微表情提示词与 3D 姿态预设！")
	for sp in shen_ce_sprites:
		print("       • [%s] %s | 动作: %s | 提示词: %s" % [
			"BASE" if sp.get("is_base", false) else "DIFF",
			sp.get("name", ""),
			sp.get("pose_preset", ""),
			sp.get("prompt", "")
		])

	print("[9] 测试生图双通道解耦架构 (微表情 Inpaint vs 3D 姿态全身生成)")
	# 测试新增差分弹窗的通道模式切换
	assert(tab.opt_add_sprite_mode != null, "新增差分弹窗必须包含生成通道下拉选择")
	tab.open_add_sprite_dialog("char_shen_ce", shen_ce_ent)
	assert(tab.opt_add_sprite_mode.selected == 0, "默认应选择模式 A: 纯微表情自然差分")
	assert(not tab.lbl_add_sprite_pose_title.visible, "微表情模式下姿态选择应隐匿")
	
	# 切换至模式 B: 3D 姿态全新立绘
	tab.opt_add_sprite_mode.selected = 1
	tab.opt_add_sprite_mode.item_selected.emit(1)
	assert(tab.lbl_add_sprite_pose_title.visible, "3D 姿态模式下应展现姿态预设选项")
	assert(tab.opt_add_sprite_pose.visible, "3D 姿态模式下应展现姿态预设下拉")
	tab.dlg_add_sprite.hide()
	print("    ✅ 新增差分弹窗双通道切换与交互响应验证通过！")

	print("[10] 测试 3D 姿态工坊全新立绘生成与外部参考图挂载")
	var test_pose_dlg = PoseEditorDialogClass.new()
	add_child(test_pose_dlg)
	test_pose_dlg.open_for_character("char_shen_ce", shen_ce_ent)
	
	# 监听生成的素材项 (使用引用容器接收 lambda 回调)
	var generated_box = []
	test_pose_dlg.pose_sprite_generated.connect(func(item):
		generated_box.append(item)
	)
	test_pose_dlg.txt_pose_name.text = "严谨深思"
	test_pose_dlg.mannequin.apply_preset("crossed_arms")
	test_pose_dlg._on_confirm_generate()
	
	assert(generated_box.size() > 0, "姿态工坊应成功派发立绘素材项")
	var generated_pose_item = generated_box[0]
	assert(generated_pose_item.get("generation_mode", "") == "pose", "素材项 generation_mode 必须为 pose")
	assert(generated_pose_item.has("pose_image") and not str(generated_pose_item["pose_image"]).is_empty(), "必须附带生成的 OpenPose 骨架底图")
	assert(generated_pose_item.get("prompt", "").contains("双手抱胸") or generated_pose_item.get("prompt", "").contains("arms crossed"), "提示词应包含姿态强化描述")
	print("    ✅ 3D 姿态工坊骨骼生成、Prompt 增强与 pose 模式标记验证通过！")
	test_pose_dlg.queue_free()

	tab.queue_free()

	print("\n🎉🎉🎉 全部 VNCCS 一致性、自然换脸无缝融合与 3D 姿态解耦全真测试 100% 通过！")
	get_tree().quit(0)
