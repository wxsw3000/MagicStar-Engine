# editor/core/export_manager.gd
# 多平台打包与发布管理器
class_name ExportManager
extends RefCounted

signal export_log(message: String)
signal export_progress(percent: float, status: String)
signal export_finished(success: bool, output_dir: String)

static func get_godot_executable() -> String:
	var exe = OS.get_executable_path()
	if exe.ends_with(".exe") or not exe.is_empty():
		return exe
	return "godot"

# 打包为 Windows 独立绿色运行包 (Exe + PCK / 独立目录)
static func export_windows(output_dir: String, game_title: String = "") -> Dictionary:
	var result = {"success": false, "message": "", "output_path": ""}
	var title = game_title if not game_title.is_empty() else "MysteryAVG"
	# 清理非法字符
	var safe_title = title.replace(" ", "_").replace(":", "").replace("/", "").replace("\\", "")
	var target_folder = output_dir.path_join(safe_title + "_Windows")
	
	if not DirAccess.dir_exists_absolute(target_folder):
		DirAccess.make_dir_recursive_absolute(target_folder)
		
	var godot_exe = get_godot_executable()
	if not FileAccess.file_exists(godot_exe):
		result.message = "未找到 Godot 引擎可执行程序: " + godot_exe
		return result
		
	# 1. 复制或链接可执行文件
	var target_exe = target_folder.path_join(safe_title + ".exe")
	var copy_err = DirAccess.copy_absolute(godot_exe, target_exe)
	if copy_err != OK:
		result.message = "复制引擎可执行文件失败，错误码: %d" % copy_err
		return result
		
	# 2. 导出或复制项目数据包
	# 使用 Godot CLI 编译独立 PCK 数据包
	var target_pck = target_folder.path_join(safe_title + ".pck")
	var project_path = ProjectSettings.globalize_path("res://")
	
	# 如果当前有导出预设则通过 CLI 导出，否则打包关键数据目录
	var args = [
		"--headless",
		"--path", project_path,
		"--export-pack", "Windows Desktop", target_pck
	]
	
	var output = []
	var exit_code = OS.execute(godot_exe, args, output, true)
	
	# 如果由于没有预设导致 export-pack 失败，采用绿色便携包模式 (复制项目结构 + 运行启动脚本)
	if exit_code != OK or not FileAccess.file_exists(target_pck):
		var portable_res = create_portable_package(target_folder, safe_title)
		if portable_res.success:
			result.success = true
			result.output_path = target_folder
			result.message = "Windows 绿色版打包成功（便携资源模式）！"
			return result
		else:
			result.message = "打包失败: " + portable_res.message
			return result
			
	result.success = true
	result.output_path = target_folder
	result.message = "Windows 独立端打包成功: " + target_exe
	return result

# 创建免模板的便携式独立发布包 (包含引擎、运行脚本、数据与资源)
static func create_portable_package(target_folder: String, game_title: String) -> Dictionary:
	var res_dir = target_folder.path_join("game_data")
	if not DirAccess.dir_exists_absolute(res_dir):
		DirAccess.make_dir_recursive_absolute(res_dir)
		
	# 递归复制 engine, data, config, scenes, assets, project.godot
	var project_root = ProjectSettings.globalize_path("res://")
	var folders_to_copy = ["config", "data", "engine", "scenes", "assets"]
	
	for folder in folders_to_copy:
		var src = project_root.path_join(folder)
		var dst = res_dir.path_join(folder)
		copy_directory_recursive(src, dst)
		
	# 复制 project.godot
	var src_proj = project_root.path_join("project.godot")
	var dst_proj = res_dir.path_join("project.godot")
	DirAccess.copy_absolute(src_proj, dst_proj)
	
	# 创建 Windows 启动批处理与可执行包装
	var bat_content = "@echo off\r\nstart \"\" \"%~dp0" + game_title + ".exe\" --path \"%~dp0game_data\"\r\n"
	var bat_path = target_folder.path_join("启动游戏.bat")
	var f = FileAccess.open(bat_path, FileAccess.WRITE)
	if f:
		f.store_string(bat_content)
		f.close()
		
	return {"success": true, "message": "便携工程打包完成"}

# 递归复制目录
static func copy_directory_recursive(src_dir: String, dst_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(src_dir):
		return
	if not DirAccess.dir_exists_absolute(dst_dir):
		DirAccess.make_dir_recursive_absolute(dst_dir)
		
	var dir = DirAccess.open(src_dir)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				var src_path = src_dir.path_join(file_name)
				var dst_path = dst_dir.path_join(file_name)
				if dir.current_is_dir():
					copy_directory_recursive(src_path, dst_path)
				else:
					DirAccess.copy_absolute(src_path, dst_path)
			file_name = dir.get_next()
		dir.list_dir_end()

# 打包纯游戏数据工程包 (方便创作者分享剧本或在线热更)
static func export_game_data_package(output_dir: String, package_name: String = "mystery_game.avgpkg") -> Dictionary:
	var result = {"success": false, "message": "", "output_path": ""}
	var target_folder = output_dir.path_join("Data_Packages")
	if not DirAccess.dir_exists_absolute(target_folder):
		DirAccess.make_dir_recursive_absolute(target_folder)
		
	var target_zip = target_folder.path_join(package_name)
	# 准备打包 data 与 config
	var writer = ZIPPacker.new()
	var err = writer.open(target_zip)
	if err != OK:
		result.message = "无法创建数据包 ZIP: %d" % err
		return result
		
	var project_root = ProjectSettings.globalize_path("res://")
	pack_folder_to_zip(writer, project_root.path_join("config"), "config")
	pack_folder_to_zip(writer, project_root.path_join("data"), "data")
	writer.close()
	
	result.success = true
	result.output_path = target_zip
	result.message = "纯数据剧情包生成完毕: " + target_zip
	return result

static func pack_folder_to_zip(writer: ZIPPacker, folder_path: String, zip_prefix: String) -> void:
	if not DirAccess.dir_exists_absolute(folder_path):
		return
	var dir = DirAccess.open(folder_path)
	if dir:
		dir.list_dir_begin()
		var item = dir.get_next()
		while item != "":
			if item != "." and item != "..":
				var full_item_path = folder_path.path_join(item)
				var zip_item_path = zip_prefix + "/" + item
				if dir.current_is_dir():
					pack_folder_to_zip(writer, full_item_path, zip_item_path)
				else:
					var f = FileAccess.open(full_item_path, FileAccess.READ)
					if f:
						var buffer = f.get_buffer(f.get_length())
						writer.start_file(zip_item_path)
						writer.write_file(buffer)
						writer.close_file()
						f.close()
			item = dir.get_next()
		dir.list_dir_end()
