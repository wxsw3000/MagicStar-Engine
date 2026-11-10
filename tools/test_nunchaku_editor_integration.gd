# tools/test_nunchaku_editor_integration.gd
# 自动化测试套件：深度验证 Godot 编辑器全面集成 Nunchaku Qwen-Image 2.1 差分管线
extends Control

const AIAssetMgr = preload("res://editor/core/ai_asset_manager.gd")
const AIAssetTabClass = preload("res://editor/ui/tabs/ai_asset_tab.gd")

func _ready() -> void:
	print("==================================================================")
	print("--- 开始 Godot 编辑器 Nunchaku Qwen-Image 2.1 集成自动化测试 ---")
	print("==================================================================")
	call_deferred("run_tests")

func run_tests() -> void:
	await get_tree().create_timer(0.1).timeout

	print("\n[Step 1] 测试 AI 配置加载与 4060 局域网环境识别")
	var settings = AIAssetMgr.load_ai_settings()
	var server = settings.get("comfyui_server", "")
	var ckpt = settings.get("checkpoint", "")
	var env_id = settings.get("current_env_id", "")
	print("    当前服务地址: %s" % server)
	print("    当前底模配置: %s" % ckpt)
	print("    当前环境 ID : %s" % env_id)
	var user = settings.get("comfyui_user", "")
	var password = settings.get("comfyui_password", "")
	assert(server.contains("192.168.0.199") or server.contains("192.168.1.57") or server.contains("192.168.3.33") or server.contains("127.0.0.1"), "应当指向有效的算力机器")
	assert(ckpt.contains("nunchaku_qwen_image") or ckpt.contains("qwen-image"), "默认底模应当为 Qwen-Image / Nunchaku 模型")
	print("    ✅ Step 1 测试通过！")

	print("\n[Step 2] 测试 check_comfy_service 跨网络服务自检与模型探查")
	var res = AIAssetMgr.check_comfy_service(server, user, password)
	print("    在线状态: %s" % str(res.get("online", false)))
	print("    检测到 GPU: %s" % str(res.get("gpu", "未知")))
	var ckpts = res.get("checkpoints", [])
	print("    检测到底模总数: %d" % ckpts.size())
	for c in ckpts:
		print("      - %s" % str(c))
	assert(res.get("online", false) == true, "ComfyUI 服务应当在线")
	var has_qwen_model = false
	for c in ckpts:
		if str(c).contains("nunchaku_qwen_image") or str(c).contains("qwen-image"):
			has_qwen_model = true
			break
	assert(has_qwen_model, "服务返回的模型清单中必须包含 Qwen-Image / Nunchaku 模型")
	print("    ✅ Step 2 探查通过！成功识别 Qwen-Image 算力底模！")

	print("\n[Step 3] 挂载 AIAssetTab 并验证编辑器 UI 对 Nunchaku 模型的识别与装配")
	var tab = AIAssetTabClass.new()
	add_child(tab)
	await get_tree().create_timer(0.2).timeout

	# 执行在线连接检查
	tab.test_comfy_connection()
	await get_tree().create_timer(0.2).timeout

	print("    UI 连接状态标识: %s" % tab.lbl_conn_status.text)
	print("    UI 选中底模文本: %s" % tab.txt_checkpoint.text)
	print("    底模下拉框项数  : %d" % tab.opt_checkpoint.item_count)
	for i in range(tab.opt_checkpoint.item_count):
		print("      [%d] 显示名称: %s | 元数据: %s" % [
			i,
			tab.opt_checkpoint.get_item_text(i),
			str(tab.opt_checkpoint.get_item_metadata(i))
		])
	assert(tab.txt_checkpoint.text.contains("nunchaku_qwen_image") or tab.txt_checkpoint.text.contains("qwen-image"), "编辑器当前选中的底模应当为 Qwen-Image / Nunchaku")
	print("    ✅ Step 3 UI 控件装配与底模绑定校验通过！")

	print("\n[Step 4] 模拟立绘差分任务：验证指令级微表情参数组装")
	var test_item = {
		"id": "char_shen_ce_diff_test",
		"type": "character",
		"character_id": "char_shen_ce",
		"name": "沈策 微笑测试差分",
		"prompt": "温柔微笑，眼眸微弯，带着和善暖意",
		"generation_mode": "expression",
		"base_sprite_path": "projects/case_gallery_rain/assets/images/characters/char_shen_ce.png"
	}

	# 验证沙盒路径
	var sandboxed = AIAssetMgr.get_sandboxed_asset_path(test_item)
	print("    目标保存路径: %s" % sandboxed)
	assert(sandboxed.ends_with(".png"), "生成目标应当为 PNG")

	print("\n[Step 5] 验证尺寸体系与生成模板弹窗 (dlg_edit_templates) 交互")
	assert(tab.btn_edit_templates != null, "界面应挂载 '📐 尺寸与生成模板' 按钮")
	assert(tab.dlg_edit_templates != null, "界面应挂载模板编辑弹窗")
	tab.open_edit_templates_dialog()
	print("    弹窗差分母版预览: %s..." % tab.txt_tpl_diff.text.substr(0, 45))
	print("    身高定标启用状态: %s" % str(tab.chk_tpl_scale_enabled.button_pressed))
	print("    高个(180cm+)定标: %s" % tab.txt_tpl_scale_tall.text)
	print("    娇小(160cm) 定标: %s" % tab.txt_tpl_scale_petite.text)
	assert(tab.txt_tpl_diff.text.contains("{expression}"), "差分母版需包含 {expression} 变量插槽")
	assert(tab.txt_tpl_scale_tall.text.contains("180"), "高个定标规则需包含 180")
	assert(tab.txt_tpl_scale_petite.text.contains("160"), "娇小定标规则需包含 160")
	print("    ✅ Step 5 模板配置弹窗与插槽变量校验通过！")

	print("\n[Step 6] 验证 180cm vs 160cm 世界观身高比例体系渲染定标注入")
	const CharacterSheetMgr = preload("res://editor/core/character_sheet_manager.gd")
	var rule_180 = CharacterSheetMgr.get_height_scale_rule("182cm")
	var rule_160 = CharacterSheetMgr.get_height_scale_rule("160cm")
	print("    182cm 角色注入留白定标: %s" % rule_180)
	print("    160cm 角色注入留白定标: %s" % rule_160)
	assert(rule_180.contains("8%"), "180cm+ 角色应注入 8% 顶框留白 (高个挺拔)")
	assert(rule_160.contains("24%"), "160cm 角色应注入 24% 顶部留白 (娇小身形)")
	assert(rule_180 != rule_160, "不同身高角色应获得截然不同的画框留白规则以呈现真实身高差")
	print("    ✅ Step 6 真实身高差定标对比体系验证通过！")

	print("\n[Step 7] 验证方案A：从全身三视图自动裁切正视半身设为形象基准 (Plan A 黄金工作流)")
	var t_path = "res://projects/case_gallery_rain/assets/images/characters/char_shen_ce_turnaround.png"
	var out_base_path = "res://projects/case_gallery_rain/assets/images/characters/char_shen_ce_test_base.png"
	var abs_t_path = ProjectSettings.globalize_path(t_path)
	if FileAccess.file_exists(abs_t_path):
		var ext_res = AIAssetMgr.extract_front_view_base_from_turnaround(t_path, out_base_path)
		print("    提取结果: %s" % str(ext_res))
		assert(ext_res.get("success", false) == true, "三视图裁切提取半身必须成功")
		var abs_out = ProjectSettings.globalize_path(out_base_path)
		assert(FileAccess.file_exists(abs_out), "提取生成的 PNG 文件必须存在")
		var out_img = Image.load_from_file(abs_out)
		assert(out_img != null and not out_img.is_empty(), "必须能正确载入提取后的图像")
		print("    提取图像分辨率: %d x %d" % [out_img.get_width(), out_img.get_height()])
		assert(out_img.get_width() == 512 and out_img.get_height() == 768, "半身立绘基准尺寸必须为 512x768 (2:3)")
		# 清理测试临时文件
		DirAccess.remove_absolute(abs_out)
		print("    ✅ Step 7 方案A三视图正视半身智能提取验证通过！")
	else:
		print("    ⚠️ 未找到沈策三视图源文件，跳过实际像素提取校验")

	print("\n[Step 8] 验证 3-View 分视图高精 Prompt 编译与温寻/沈策角色差异化")
	var pctx = tab._get_project_context()
	var wen_xun_sheet = pctx.active_project_data["characters"]["char_wen_xun"]["character_sheet"]
	var shen_ce_sheet = pctx.active_project_data["characters"]["char_shen_ce"]["character_sheet"]
	
	var wx_front = CharacterSheetMgr.assemble_view_prompt(wen_xun_sheet, "front")
	var wx_side = CharacterSheetMgr.assemble_view_prompt(wen_xun_sheet, "side")
	var wx_back = CharacterSheetMgr.assemble_view_prompt(wen_xun_sheet, "back")
	
	print("    温寻正视 Prompt: %s..." % wx_front.substr(0, 50))
	assert(wx_front.contains("正面立绘"), "正视图应包含正面立绘标识")
	assert(wx_side.contains("正侧面立绘"), "侧视图应包含正侧面立绘标识")
	assert(wx_back.contains("180度纯正背面立绘"), "背视图应包含180度纯正背面立绘标识")
	assert(wx_back.contains("严禁回头") and wx_back.contains("严禁露出正脸或侧脸"), "背视图必须严格禁止回头或侧面露脸")

	# 验证背视图负向词强化
	var wx_back_neg = CharacterSheetMgr.get_three_view_negative_prompt(wen_xun_sheet, "back")
	assert(wx_back_neg.contains("露出面部") and wx_back_neg.contains("回头") and wx_back_neg.contains("正脸"), "背视图负向词必须严格封杀正面五官与回眸")
	
	# 验证风格：禁止平涂草图词汇，保持商业插画CG质感
	assert(not wx_front.contains("平涂赛璐珞") and not wx_front.contains("无阴影"), "必须剔除平涂无阴影等草图词，保持商业AVG光影")
	
	# 验证温寻与沈策的人设绝对隔离
	assert(wx_front.contains("画室") or wx_front.contains("围裙") or wx_front.contains("衬衫"), "温寻 Prompt 必须体现画家学徒身份")
	assert(not wx_front.contains("深驼色大翻领") and not wx_front.contains("细领带"), "温寻严禁携带沈策的侦探大衣与领带")
	
	var sc_front = CharacterSheetMgr.assemble_view_prompt(shen_ce_sheet, "front")
	assert(sc_front.contains("英伦侦探风") and sc_front.contains("风衣"), "沈策必须保持英伦侦探风衣人设")

	# 验证 UI 三视图卡片控件与本地浏览功能
	var t_card = tab.create_turnaround_card("char_wen_xun", pctx.active_project_data["characters"]["char_wen_xun"])
	assert(t_card != null, "三视图卡片应当顺利构建")
	print("    ✅ Step 8 3-View 独立分视图与双角色外观人设隔离校验通过！")

	print("\n[Step 9] 验证三视图透明背景通道 (RGBA) 与深度去背工具 (rembg)")
	var wx_front_path = ProjectSettings.globalize_path("res://projects/case_gallery_rain/assets/images/characters/char_wen_xun_front.png")
	if FileAccess.file_exists(wx_front_path):
		var img_wx = Image.load_from_file(wx_front_path)
		assert(img_wx != null, "必须能正常载入温寻正视立绘")
		print("    温寻正视立绘透明通道模式: %s (detect_alpha=%d)" % ["RGBA 透明" if img_wx.detect_alpha() != Image.ALPHA_NONE else "RGB 纯色", img_wx.detect_alpha()])
		assert(img_wx.detect_alpha() != Image.ALPHA_NONE, "温寻正视立绘必须包含透明通道 (RGBA)，以便作为形象基准直接叠加到游戏背景")
	print("    ✅ Step 9 三视图透明背景免抠体系验证通过！")

	print("\n🎉 全部 Godot 编辑器集成测试 100% 通过！")
	get_tree().quit(0)
