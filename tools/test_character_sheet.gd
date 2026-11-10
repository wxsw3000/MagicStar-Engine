# tools/test_character_sheet.gd
extends SceneTree

const CharacterSheetMgr = preload("res://editor/core/character_sheet_manager.gd")
const CharacterSheetDialogClass = preload("res://editor/ui/dialogs/character_sheet_dialog.gd")

func _init() -> void:
	print("=========================================================")
	print("--- 开始测试 CharacterSheetManager 与 装配引擎 ---")
	print("=========================================================")
	
	# 1. 测试标准空表创建
	var default_sheet = CharacterSheetMgr.create_default_sheet("测试角色", "男", 24)
	assert(default_sheet.has("identity"), "必须包含 identity")
	assert(default_sheet.has("appearance"), "必须包含 appearance")
	assert(default_sheet.has("vibe"), "必须包含 vibe")
	assert(default_sheet.has("outfit"), "必须包含 outfit")
	assert(default_sheet.has("expression_sheet"), "必须包含 expression_sheet")
	assert(default_sheet.has("voice"), "必须包含 voice")
	assert(default_sheet.has("spec"), "必须包含 spec")
	print("✅ Step 1: 标准空表与默认预设结构验证通过！")
	
	# 2. 测试沈策预设
	var shen_ce_sheet = CharacterSheetMgr.get_shen_ce_preset()
	assert(shen_ce_sheet["identity"]["name"] == "沈策", "角色名应为沈策")
	print("✅ Step 2: 沈策专属角色属性表加载成功！")
	
	# 3. 测试一键拼装引擎
	var assembled = CharacterSheetMgr.assemble_prompts(shen_ce_sheet)
	print("\n--- 拼装成果预览 ---")
	print("Base Prompt:")
	print("  " + assembled.get("base_prompt", ""))
	print("Negative Prompt (防老逆龄):")
	print("  " + assembled.get("negative_prompt", ""))
	print("Recommended TTS Voice:")
	print("  " + assembled.get("recommended_tts_role", ""))
	print("Assembled Sprites Count: %d" % assembled.get("sprites", []).size())
	
	assert(assembled.get("base_prompt", "").contains("沈策") or assembled.get("base_prompt", "").contains("角色"), "Prompt 需包含角色描述")
	assert(assembled.get("negative_prompt", "").contains("衰老") or assembled.get("negative_prompt", "").contains("褶皱"), "Negative prompt 必须含有衰老/褶皱防老约束")
	assert(assembled.get("negative_prompt", "").contains("法令纹"), "Negative prompt 必须含有法令纹约束")
	assert(assembled.get("sprites", []).size() >= 8, "必须生成 6+2 共 8 个表情差分项")
	
	var serious_found = false
	for sp in assembled.get("sprites", []):
		if sp.get("expression") == "serious":
			serious_found = true
			var qwen_cmd = sp.get("qwen_diff_prompt", "")
			print("Serious Diff Qwen Prompt: " + qwen_cmd)
			assert(qwen_cmd.contains("绝对禁止衰老褶皱"), "严厉质询微表情必须显式约束绝对禁止衰老褶皱")
	assert(serious_found, "差分清单必须包含 serious 严厉质询")
	print("✅ Step 3: 一键拼装与 6+2 微表情生成引擎测试全部通过！")
	
	# 4. 实例化测试 CharacterSheetDialog 避免 UI 脚本语法或类型错误
	var dlg = CharacterSheetDialogClass.new()
	assert(dlg != null, "CharacterSheetDialog 实例化成功")
	dlg.queue_free()
	print("✅ Step 4: CharacterSheetDialog 实例化与脚本绑定完全正常！")

	# 5. 实例化测试 SpriteLightboxDialog
	var LightboxClass = load("res://editor/ui/dialogs/sprite_lightbox_dialog.gd")
	var lb = LightboxClass.new()
	assert(lb != null, "SpriteLightboxDialog 实例化成功")
	lb.queue_free()
	print("✅ Step 5: SpriteLightboxDialog 高清画廊弹窗测试通过！")
	
	print("\n🎉 全部 CharacterSheet & Lightbox 自动化测试通过！")
	quit(0)
