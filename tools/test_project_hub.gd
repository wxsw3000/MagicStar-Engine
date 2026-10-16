# tools/test_project_hub.gd
extends Control

func _ready() -> void:
	print("--- 开始 Project Hub 案件工程管理器全真自动化测试 ---")
	call_deferred("run_hub_test")

func run_hub_test() -> void:
	await get_tree().create_timer(0.1).timeout
	
	print("[1] 测试工程目录扫描与列表获取")
	var p_list = ProjectContext.get_projects_list()
	print("    扫描到工程数: %d" % p_list.size())
	assert(p_list.size() >= 1, "应扫描到至少 1 个案件工程")
	for p in p_list:
		assert(not p["folder_name"].is_empty(), "工程文件夹名不可为空")
		assert(p["nodes_count"] > 0, "工程应包含节点数据")
	print("    ✅ 初始工程列表扫描验证通过")
	
	print("[2] 测试创建新案件工程")
	var test_case_id = "case_test_" + str(int(Time.get_unix_time_from_system()))
	var new_res = ProjectContext.create_project(test_case_id, "密室夜行杀人事件", "测试探长", "暴风雨雪夜密室...")
	if not new_res.get("success", false):
		print("新建工程返回错误: ", new_res)
	assert(new_res.get("success", false), "新建工程应当成功")
	var new_path = new_res.get("path", "")
	assert(FileAccess.file_exists(new_path + "project.json"), "新工程 project.json 应存在")
	print("    ✅ 新建案件工程验证通过: %s" % new_path)
	
	print("[3] 测试工程上下文动态切换")
	# 切换至新建工程
	var ok_load_new = ProjectContext.load_project(new_path)
	assert(ok_load_new, "应成功载入新工程")
	assert("密室夜行" in ProjectContext.get_active_project_title(), "当前工程标题应切换为新工程")
	
	# 切换回初始工程
	var orig_proj_path = p_list[0]["dir_path"]
	var ok_load_orig = ProjectContext.load_project(orig_proj_path)
	assert(ok_load_orig, "应成功切回初始工程")
	print("    ✅ 多工程动态切换验证通过")
	
	print("[4] 测试 ProjectHub 界面控件渲染")
	var hub_packed = load("res://scenes/project_hub.tscn")
	var hub_scene = hub_packed.instantiate()
	add_child(hub_scene)
	assert(hub_scene.projects_container.get_child_count() >= p_list.size() + 1, "界面中卡片数量应随之增加渲染")
	print("    ✅ ProjectHub 界面卡片渲染验证通过，当前卡片数: %d" % hub_scene.projects_container.get_child_count())
	
	print("[5] 测试工程 Master JSON 独立导出")
	var temp_export_path = "res://tools/temp_exported_master.json"
	var exp_res = ProjectContext.export_project_json(new_path, temp_export_path)
	assert(exp_res.get("success", false), "导出工程 JSON 应当成功")
	assert(FileAccess.file_exists(temp_export_path), "导出的 JSON 文件应存在")
	var exported_json = ProjectContext.load_json_file(temp_export_path)
	assert(exported_json.get("meta", {}).get("game_title", "") == "密室夜行杀人事件", "导出的 JSON 内容元数据应完全匹配")
	DirAccess.remove_absolute(temp_export_path)
	print("    ✅ 工程 Master JSON 独立导出验证通过")

	print("[6] 测试自包含工程彻底删除")
	var del_res = ProjectContext.delete_project(new_path)
	assert(del_res.get("success", false), "删除工程应当成功")
	assert(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(new_path)), "工程文件夹应被彻底物理移除")
	print("    ✅ 自包含工程物理删除验证通过")
	
	print("=== Project Hub 案件工程管理器全真自动化测试 100% 通过！ ===")
	get_tree().quit(0)
