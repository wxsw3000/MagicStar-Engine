# tools/test_ai_environments.gd
# 自动化测试套件：深度验证 ComfyUI 多环境配置管理、账号密码隔离与无损切换
extends Control

const AIAssetMgr = preload("res://editor/core/ai_asset_manager.gd")
const AIAssetTabClass = preload("res://editor/ui/tabs/ai_asset_tab.gd")

func _ready() -> void:
	print("--- 开始 ComfyUI 多环境配置与账号密码管理全真自动化测试 ---")
	call_deferred("run_tests")

func run_tests() -> void:
	await get_tree().create_timer(0.1).timeout
	
	print("[1] 测试多环境配置数据初始化与环境识别")
	var settings = AIAssetMgr.load_ai_settings()
	var envs = settings.get("comfyui_environments", [])
	assert(envs is Array, "环境列表应当是 Array")
	assert(envs.size() >= 2, "应当包含至少 2 个环境（本地与远程）")
	print("    当前环境数量: %d" % envs.size())
	for i in range(envs.size()):
		var e = envs[i]
		print("    - 环境 [%d]: %s (Host: %s, User: %s)" % [i, e.get("name", ""), e.get("server", ""), e.get("user", "")])

	print("[2] 挂载 AIAssetTab 界面并验证控件装配")
	var tab = AIAssetTabClass.new()
	add_child(tab)
	await get_tree().create_timer(0.2).timeout
	
	assert(tab.opt_server_preset != null, "环境下拉框应存在")
	assert(tab.btn_add_env != null, "➕ 新增按钮应存在")
	assert(tab.btn_manage_env != null, "⚙️ 管理按钮应存在")
	assert(tab.dlg_add_env != null, "新增弹窗应就绪")
	assert(tab.dlg_manage_env != null, "管理弹窗应就绪")
	assert(tab.dlg_edit_env != null, "编辑弹窗应就绪")
	print("    ✅ 界面与弹窗装配校验通过！下拉项数量: %d" % tab.opt_server_preset.item_count)

	print("[3] 测试环境切换防丢失机制：从远程鉴权环境切换到本地")
	var remote_idx = 1
	var vicp_host = ""
	var vicp_user = ""
	var vicp_pass = ""
	for i in range(tab.ai_settings["comfyui_environments"].size()):
		var e = tab.ai_settings["comfyui_environments"][i]
		if str(e.get("server", "")).contains("vicp.fun"):
			remote_idx = i
			vicp_host = str(e.get("server", ""))
			vicp_user = str(e.get("user", ""))
			vicp_pass = str(e.get("password", ""))
			break
			
	tab._on_server_preset_selected(remote_idx)
	assert(tab.txt_comfy_host.text == vicp_host, "应选入远程鉴权环境")
	assert(tab.txt_comfy_user.text == vicp_user, "远程鉴权环境账号应匹配")

	# 切换到本地环境 (索引 0)
	tab._on_server_preset_selected(0)
	assert(tab.txt_comfy_host.text.contains("127.0.0.1"), "切换至本地后地址应为 127.0.0.1")
	assert(tab.txt_comfy_user.text == "", "本地环境账号应为空")
	assert(tab.txt_comfy_pass.text == "", "本地环境密码应为空")
	print("    ✅ 成功切换至本地环境: %s" % tab.txt_comfy_host.text)

	print("[4] 测试环境无损切换回远程：凭据与地址完整恢复")
	tab._on_server_preset_selected(remote_idx)
	assert(tab.txt_comfy_host.text == vicp_host, "切回远程后 Host 应完整恢复")
	assert(tab.txt_comfy_user.text == vicp_user, "切回远程后 User 应完整恢复")
	assert(tab.txt_comfy_pass.text == vicp_pass, "切回远程后 Password 应完整恢复")
	print("    ✅ 成功切回远程环境，凭据完整未丢失！User: %s" % tab.txt_comfy_user.text)

	print("[5] 测试弹窗新增第三方环境 (包含账号密码)")
	tab.open_add_env_dialog()
	tab.txt_add_env_name.text = "测试私有云RTX4090"
	tab.txt_add_env_host.text = "http://192.168.1.188:8188"
	tab.txt_add_env_user.text = "studio_admin"
	tab.txt_add_env_pass.text = "secret_pass_123"
	tab._on_confirm_add_env()

	assert(tab.txt_comfy_host.text == "http://192.168.1.188:8188", "新增环境后应自动切换并填入地址")
	assert(tab.txt_comfy_user.text == "studio_admin", "新增环境后应自动填入账号")
	assert(tab.txt_comfy_pass.text == "secret_pass_123", "新增环境后应自动填入密码")
	print("    ✅ 新增环境成功并已自动激活！")

	print("[6] 测试环境管理弹窗渲染与环境编辑")
	tab.open_manage_env_dialog()
	assert(tab.vbox_env_list.get_child_count() >= 3, "管理列表中应至少呈现 3 个环境卡片")
	
	# 编辑刚才新增的环境
	var test_env = null
	for e in tab.ai_settings["comfyui_environments"]:
		if e.get("server", "") == "http://192.168.1.188:8188":
			test_env = e
			break
	assert(test_env != null, "应在配置中找到测试环境")

	tab.dlg_manage_env.hide()
	tab.open_edit_env_dialog(test_env)
	tab.txt_edit_env_name.text = "更新后的办公室4090"
	tab.txt_edit_env_host.text = "http://192.168.1.199:8188"
	tab._on_confirm_edit_env()

	assert(tab.txt_comfy_host.text == "http://192.168.1.199:8188", "编辑后地址应同步更新至输入框")
	print("    ✅ 环境编辑与同步生效通过！")

	print("[7] 测试环境删除与安全兜底保护")
	var prev_cnt = tab.ai_settings["comfyui_environments"].size()
	tab._delete_env_by_id(test_env["id"])
	var after_cnt = tab.ai_settings["comfyui_environments"].size()
	assert(after_cnt == prev_cnt - 1, "删除后数量应减少 1")
	# 确认删除了临时测试环境后，切回远程主环境
	tab._on_server_preset_selected(1)
	print("    ✅ 环境删除与安全回退通过！")

	print("=== ComfyUI 多环境配置管理全套自动化测试 100% 验证通过！ ===")
	get_tree().quit(0)
