# editor/ui/dialogs/export_dialog.gd
# 多平台一键打包与发布对话框
class_name ExportDialog
extends Window

const ExportManager = preload("res://editor/core/export_manager.gd")

var opt_platform: OptionButton
var edit_out_dir: LineEdit
var log_label: RichTextLabel
var btn_start_export: Button
var btn_open_folder: Button
var last_output_folder: String = ""

func _init() -> void:
	title = "📦 多平台游戏一键打包发布中心"
	size = Vector2(650, 480)
	exclusive = true
	unresizable = false

func _ready() -> void:
	setup_ui()
	close_requested.connect(queue_free)

func setup_ui() -> void:
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	var lbl_desc = Label.new()
	lbl_desc.text = "选择发布平台与输出目标，AVG Studio 将自动化打包全量引擎与游戏工程资源："
	vbox.add_child(lbl_desc)
	
	var grid = GridContainer.new()
	grid.columns = 2
	vbox.add_child(grid)
	
	var l1 = Label.new(); l1.text = "目标发布平台: "; grid.add_child(l1)
	opt_platform = OptionButton.new()
	opt_platform.add_item("💻 Windows 独立桌面绿色发行包 (.exe + 资源包)", 0)
	opt_platform.add_item("📦 AVG 纯数据工程发布包 (.avgpkg / 剧情包)", 1)
	grid.add_child(opt_platform)
	
	var l2 = Label.new(); l2.text = "发布输出路径: "; grid.add_child(l2)
	var dir_row = HBoxContainer.new()
	edit_out_dir = LineEdit.new()
	var default_dir = ProjectSettings.globalize_path("res://builds")
	edit_out_dir.text = default_dir
	edit_out_dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dir_row.add_child(edit_out_dir)
	grid.add_child(dir_row)
	
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	var btn_row = HBoxContainer.new()
	btn_start_export = Button.new()
	btn_start_export.text = "🚀 开始执行构建与打包"
	btn_start_export.pressed.connect(_on_start_export_pressed)
	btn_row.add_child(btn_start_export)
	
	btn_open_folder = Button.new()
	btn_open_folder.text = "📂 打开生成目录"
	btn_open_folder.disabled = true
	btn_open_folder.pressed.connect(_on_open_folder_pressed)
	btn_row.add_child(btn_open_folder)
	vbox.add_child(btn_row)
	
	var l_log = Label.new()
	l_log.text = "构建输出日志:"
	vbox.add_child(l_log)
	
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.text = "[color=gray]等待开始打包...[/color]"
	vbox.add_child(log_label)

func _on_start_export_pressed() -> void:
	var out_dir = edit_out_dir.text.strip_edges()
	if out_dir.is_empty():
		return
		
	btn_start_export.disabled = true
	log_label.text = "[color=cyan]🚀 开始打包流程，正在分析项目资源...[/color]\n"
	
	var selected_plat = opt_platform.selected
	var title = DataManager.game_config.get("game_title", "MysteryAVG")
	
	# 异步延迟以展示 UI 响应
	get_tree().create_timer(0.1).timeout.connect(func():
		var res: Dictionary = {}
		match selected_plat:
			0:
				log_label.append_text("[color=yellow]正在生成 Windows 独立可执行环境与便携工程包...[/color]\n")
				res = ExportManager.export_windows(out_dir, title)
			1:
				log_label.append_text("[color=yellow]正在打包 JSON 数据与配置为 .avgpkg 归档...[/color]\n")
				res = ExportManager.export_game_data_package(out_dir, "mystery_case_pack.avgpkg")
				
		if res.get("success", false):
			last_output_folder = res.get("output_path", out_dir)
			btn_open_folder.disabled = false
			log_label.append_text("[color=green]✅ 构建成功！[/color]\n")
			log_label.append_text("[color=white]%s[/color]\n" % res.get("message", ""))
			log_label.append_text("[color=green]输出位置: %s[/color]\n" % last_output_folder)
		else:
			log_label.append_text("[color=red]❌ 构建失败！[/color]\n")
			log_label.append_text("[color=red]%s[/color]\n" % res.get("message", "未知错误"))
			
		btn_start_export.disabled = false
	)

func _on_open_folder_pressed() -> void:
	if not last_output_folder.is_empty():
		OS.shell_open(last_output_folder)
