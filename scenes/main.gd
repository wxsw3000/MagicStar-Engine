# scenes/main.gd
# 游戏主运行界面（挂载 UI 表现层，与底层系统完全通过 EventBus 解耦交互）
extends Control

# UI 节点引用
@onready var bg_rect: ColorRect = $Background
@onready var bg_texture: TextureRect = $BgTexture
@onready var char_portrait: TextureRect = $CharacterLayer/Portrait
@onready var bgm_player: AudioStreamPlayer = $BgmPlayer
@onready var voice_player: AudioStreamPlayer = $VoicePlayer
@onready var sfx_player: AudioStreamPlayer = $SfxPlayer

# 顶部栏
@onready var top_bar: PanelContainer = $TopBar
@onready var scene_title_label: Label = $TopBar/MarginContainer/HBoxContainer/SceneTitleLabel
@onready var phase_label: Label = $TopBar/MarginContainer/HBoxContainer/PhaseLabel
@onready var btn_notebook: Button = $TopBar/MarginContainer/HBoxContainer/BtnNotebook
@onready var btn_timeline: Button = $TopBar/MarginContainer/HBoxContainer/BtnTimeline
@onready var btn_save: Button = $TopBar/MarginContainer/HBoxContainer/BtnSave
@onready var btn_load: Button = $TopBar/MarginContainer/HBoxContainer/BtnLoad
@onready var btn_editor: Button = $TopBar/MarginContainer/HBoxContainer/BtnEditor
@onready var btn_hub: Button = $TopBar/MarginContainer/HBoxContainer/BtnHub

# 搜证热区容器
@onready var explore_container: Control = $ExploreContainer

# 对话层
@onready var dialogue_layer: Control = $DialogueLayer
@onready var dialogue_box: PanelContainer = $DialogueLayer/DialogueBox
@onready var speaker_label: Label = $DialogueLayer/DialogueBox/MarginContainer/VBoxContainer/SpeakerContainer/SpeakerLabel
@onready var content_label: Label = $DialogueLayer/DialogueBox/MarginContainer/VBoxContainer/ContentLabel
@onready var continue_indicator: Label = $DialogueLayer/DialogueBox/MarginContainer/VBoxContainer/IndicatorContainer/ContinueIndicator
@onready var choice_container: VBoxContainer = $DialogueLayer/ChoiceContainer

# 模态暗黑遮罩
@onready var modal_backdrop: ColorRect = $ModalBackdrop

# 线索笔记弹窗 (2栏查阅式)
@onready var notebook_modal: PanelContainer = $NotebookModal
@onready var notebook_clue_list: VBoxContainer = $NotebookModal/MarginContainer/VBoxContainer/BodySplit/LeftPanel/ScrollContainer/ClueList
@onready var notebook_detail_title: Label = $NotebookModal/MarginContainer/VBoxContainer/BodySplit/RightPanel/MarginContainer/DetailBox/DetailTitle
@onready var notebook_detail_tag: Label = $NotebookModal/MarginContainer/VBoxContainer/BodySplit/RightPanel/MarginContainer/DetailBox/MetaHBox/DetailTag
@onready var notebook_detail_source: Label = $NotebookModal/MarginContainer/VBoxContainer/BodySplit/RightPanel/MarginContainer/DetailBox/MetaHBox/DetailSource
@onready var notebook_detail_desc: Label = $NotebookModal/MarginContainer/VBoxContainer/BodySplit/RightPanel/MarginContainer/DetailBox/DetailDesc
@onready var btn_close_notebook: Button = $NotebookModal/MarginContainer/VBoxContainer/Header/BtnCloseNotebook

# 一体化举证推理台 (ReasoningArena - 破除弹窗重叠的核心)
@onready var reasoning_modal: PanelContainer = $ReasoningModal
@onready var reasoning_question_banner: PanelContainer = $ReasoningModal/MarginContainer/VBoxContainer/QuestionBanner
@onready var reasoning_question_label: Label = $ReasoningModal/MarginContainer/VBoxContainer/QuestionBanner/MarginContainer/QuestionLabel
@onready var reasoning_clue_list: VBoxContainer = $ReasoningModal/MarginContainer/VBoxContainer/BodySplit/LeftPanel/ScrollContainer/ReasoningClueList
@onready var reasoning_detail_title: Label = $ReasoningModal/MarginContainer/VBoxContainer/BodySplit/RightPanel/MarginContainer/DetailBox/ReasoningDetailTitle
@onready var reasoning_detail_tag: Label = $ReasoningModal/MarginContainer/VBoxContainer/BodySplit/RightPanel/MarginContainer/DetailBox/MetaHBox/ReasoningDetailTag
@onready var reasoning_detail_source: Label = $ReasoningModal/MarginContainer/VBoxContainer/BodySplit/RightPanel/MarginContainer/DetailBox/MetaHBox/ReasoningDetailSource
@onready var reasoning_detail_desc: Label = $ReasoningModal/MarginContainer/VBoxContainer/BodySplit/RightPanel/MarginContainer/DetailBox/ReasoningDetailDesc
@onready var reasoning_hint_label: Label = $ReasoningModal/MarginContainer/VBoxContainer/Footer/HintContainer/ReasoningHintLabel
@onready var selected_clue_summary_label: Label = $ReasoningModal/MarginContainer/VBoxContainer/Footer/HintContainer/SelectedSummaryLabel
@onready var btn_submit_reasoning: Button = $ReasoningModal/MarginContainer/VBoxContainer/Footer/BtnSubmitReasoning
@onready var btn_close_reasoning: Button = $ReasoningModal/MarginContainer/VBoxContainer/Header/BtnCloseReasoning

# 时光机回溯弹窗
@onready var timeline_modal: PanelContainer = $TimelineModal
@onready var timeline_list_container: VBoxContainer = $TimelineModal/MarginContainer/VBoxContainer/ScrollContainer/TimelineList
@onready var btn_close_timeline: Button = $TimelineModal/MarginContainer/VBoxContainer/Header/BtnCloseTimeline

# 结局界面
@onready var ending_modal: PanelContainer = $EndingModal
@onready var ending_title_label: Label = $EndingModal/MarginContainer/VBoxContainer/EndingTitle
@onready var ending_desc_label: Label = $EndingModal/MarginContainer/VBoxContainer/EndingDesc
@onready var btn_restart_game: Button = $EndingModal/MarginContainer/VBoxContainer/BtnRestart

# 提示 Toast
@onready var toast_panel: PanelContainer = $ToastPanel
@onready var toast_label: Label = $ToastPanel/ToastLabel

# 状态变量
var selected_reasoning_clue: String = ""
var current_notebook_clue: String = ""
var typewriter_tween: Tween
var indicator_tween: Tween

# 样式常量规范 (黑金侦探风)
const PALETTE = {
	"bg_panel": Color(0.07, 0.09, 0.13, 0.96),
	"bg_card": Color(0.11, 0.14, 0.20, 0.90),
	"bg_card_selected": Color(0.18, 0.23, 0.33, 1.0),
	"border_gold": Color(1.0, 0.82, 0.35, 0.9),
	"border_normal": Color(0.28, 0.36, 0.48, 0.6),
	"border_subtle": Color(0.2, 0.25, 0.35, 0.4),
	"text_gold": Color(1.0, 0.85, 0.35, 1.0),
	"text_primary": Color(0.95, 0.96, 0.98, 1.0),
	"text_secondary": Color(0.7, 0.76, 0.84, 1.0),
	"text_cyan": Color(0.45, 0.85, 1.0, 1.0),
	"btn_primary": Color(0.85, 0.65, 0.15, 0.95),
	"btn_primary_hover": Color(1.0, 0.78, 0.25, 1.0)
}

func _ready() -> void:
	ProjectContext.ensure_active_project_loaded()
	apply_global_theme_styles()
	connect_signals()
	hide_modals()
	start_indicator_breathing()
	
	# 对话框点击即推进
	dialogue_box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	dialogue_box.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			trigger_dialogue_advance()
	)
	for child in dialogue_box.find_children("*", "Control", true, false):
		if child is Control and not (child is Button):
			child.mouse_filter = Control.MOUSE_FILTER_PASS
			
	explore_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 启动时确保氛围 BGM 播放
	var default_bgm = ProjectContext.get_default_bgm_path()
	if not default_bgm.is_empty() and ResourceLoader.exists(default_bgm):
		bgm_player.stream = load(default_bgm)
		bgm_player.play()
	
	# 初始化窗口标题
	var game_title = DataManager.game_config.get("game_title", ProjectContext.get_active_project_title())
	DisplayServer.window_set_title(game_title)
	
	# 启动剧情
	var custom_node = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--start-node="):
			custom_node = arg.substr("--start-node=".length())
		elif arg.begins_with("++start-node="):
			custom_node = arg.substr("++start-node=".length())
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--start-node="):
			custom_node = arg.substr("--start-node=".length())
		elif arg.begins_with("++start-node="):
			custom_node = arg.substr("++start-node=".length())
			
	NodeManager.start_game(custom_node)

# --- 全局 UI 风格化注入 ---
func apply_global_theme_styles() -> void:
	# 顶部导航栏样式
	var top_style = StyleBoxFlat.new()
	top_style.bg_color = Color(0.05, 0.06, 0.09, 0.92)
	top_style.border_width_bottom = 2
	top_style.border_color = Color(0.35, 0.45, 0.6, 0.4)
	top_bar.add_theme_stylebox_override("panel", top_style)
	
	# 对话框悬浮气垫样式
	var diag_style = StyleBoxFlat.new()
	diag_style.bg_color = Color(0.06, 0.08, 0.12, 0.94)
	diag_style.set_border_width_all(2)
	diag_style.border_color = Color(0.35, 0.45, 0.65, 0.75)
	diag_style.border_width_top = 3
	diag_style.set_corner_radius_all(14)
	diag_style.shadow_color = Color(0, 0, 0, 0.55)
	diag_style.shadow_size = 18
	dialogue_box.add_theme_stylebox_override("panel", diag_style)
	
	# 模态弹窗统一黑金高质感样式
	var modal_style = StyleBoxFlat.new()
	modal_style.bg_color = PALETTE["bg_panel"]
	modal_style.set_border_width_all(2)
	modal_style.border_color = PALETTE["border_gold"]
	modal_style.set_corner_radius_all(14)
	modal_style.shadow_color = Color(0, 0, 0, 0.7)
	modal_style.shadow_size = 24
	
	notebook_modal.add_theme_stylebox_override("panel", modal_style)
	reasoning_modal.add_theme_stylebox_override("panel", modal_style)
	timeline_modal.add_theme_stylebox_override("panel", modal_style)
	ending_modal.add_theme_stylebox_override("panel", modal_style)
	
	# 质询问题横幅样式
	var question_style = StyleBoxFlat.new()
	question_style.bg_color = Color(0.12, 0.15, 0.22, 0.95)
	question_style.set_border_width_all(2)
	question_style.border_color = Color(1.0, 0.82, 0.35, 0.6)
	question_style.set_corner_radius_all(8)
	reasoning_question_banner.add_theme_stylebox_override("panel", question_style)
	
	# 弹窗内右侧详情卡片样式
	var detail_card_style = StyleBoxFlat.new()
	detail_card_style.bg_color = Color(0.09, 0.11, 0.16, 0.88)
	detail_card_style.set_border_width_all(1)
	detail_card_style.border_color = Color(0.3, 0.38, 0.5, 0.5)
	detail_card_style.set_corner_radius_all(10)
	$NotebookModal/MarginContainer/VBoxContainer/BodySplit/RightPanel.add_theme_stylebox_override("panel", detail_card_style)
	$ReasoningModal/MarginContainer/VBoxContainer/BodySplit/RightPanel.add_theme_stylebox_override("panel", detail_card_style)
	
	# 按钮统一样式修饰
	style_button(btn_notebook, false)
	style_button(btn_timeline, false)
	style_button(btn_save, false)
	style_button(btn_load, false)
	style_button(btn_editor, false)
	style_button(btn_hub, false)
	style_button(btn_close_notebook, false)
	style_button(btn_close_reasoning, false)
	style_button(btn_close_timeline, false)
	
	# 举证反驳核心按钮 (醒目金色主操作)
	style_primary_button(btn_submit_reasoning)
	style_primary_button(btn_restart_game)
	
	# Toast 面板样式
	var toast_style = StyleBoxFlat.new()
	toast_style.bg_color = Color(0.08, 0.1, 0.14, 0.96)
	toast_style.set_border_width_all(2)
	toast_style.border_color = PALETTE["border_gold"]
	toast_style.set_corner_radius_all(20)
	toast_style.shadow_color = Color(0, 0, 0, 0.5)
	toast_style.shadow_size = 12
	toast_panel.add_theme_stylebox_override("panel", toast_style)

func style_button(btn: Button, is_highlight: bool = false) -> void:
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	var norm = StyleBoxFlat.new()
	norm.bg_color = Color(0.12, 0.15, 0.22, 0.85) if not is_highlight else Color(0.18, 0.23, 0.33, 1.0)
	norm.set_border_width_all(1 if not is_highlight else 2)
	norm.border_color = PALETTE["border_normal"] if not is_highlight else PALETTE["border_gold"]
	norm.set_corner_radius_all(8)
	norm.content_margin_left = 14
	norm.content_margin_right = 14
	norm.content_margin_top = 6
	norm.content_margin_bottom = 6
	
	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(0.18, 0.23, 0.33, 0.95)
	hover.set_border_width_all(2)
	hover.border_color = PALETTE["border_gold"]
	hover.set_corner_radius_all(8)
	hover.content_margin_left = 14
	hover.content_margin_right = 14
	hover.content_margin_top = 6
	hover.content_margin_bottom = 6
	
	btn.add_theme_stylebox_override("normal", norm)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", norm)

func style_primary_button(btn: Button) -> void:
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	var norm = StyleBoxFlat.new()
	norm.bg_color = PALETTE["btn_primary"]
	norm.set_border_width_all(2)
	norm.border_color = Color(1.0, 0.95, 0.6, 1.0)
	norm.set_corner_radius_all(10)
	norm.content_margin_left = 20
	norm.content_margin_right = 20
	norm.shadow_color = Color(1.0, 0.7, 0.1, 0.4)
	norm.shadow_size = 10
	
	var hover = StyleBoxFlat.new()
	hover.bg_color = PALETTE["btn_primary_hover"]
	hover.set_border_width_all(2)
	hover.border_color = Color(1.0, 1.0, 0.8, 1.0)
	hover.set_corner_radius_all(10)
	hover.content_margin_left = 20
	hover.content_margin_right = 20
	hover.shadow_color = Color(1.0, 0.75, 0.15, 0.6)
	hover.shadow_size = 16
	
	btn.add_theme_stylebox_override("normal", norm)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", norm)
	btn.add_theme_color_override("font_color", Color(0.06, 0.07, 0.09, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0.0, 0.0, 0.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.0, 0.0, 0.0, 1.0))

func start_indicator_breathing() -> void:
	if indicator_tween and indicator_tween.is_valid():
		indicator_tween.kill()
	indicator_tween = create_tween().set_loops()
	indicator_tween.tween_property(continue_indicator, "modulate:a", 0.3, 0.6)
	indicator_tween.tween_property(continue_indicator, "modulate:a", 1.0, 0.6)

func update_clue_counter() -> void:
	var count = ClueManager.get_obtained_clues_data().size()
	btn_notebook.text = "📂 随身笔记 (%d)" % count

# --- 信号连接 ---
func connect_signals() -> void:
	EventBus.dialogue_line_displayed.connect(_on_dialogue_line_displayed)
	EventBus.dialogue_choices_requested.connect(_on_dialogue_choices_requested)
	EventBus.dialogue_topics_requested.connect(_on_dialogue_topics_requested)
	EventBus.dialogue_started.connect(func(_id, _data):
		dialogue_box.visible = true
	)
	EventBus.dialogue_ended.connect(func(_next):
		dialogue_box.visible = false
		char_portrait.visible = false
		clear_choices()
	)
	
	EventBus.scene_changed.connect(_on_scene_changed)
	EventBus.explore_mode_changed.connect(_on_explore_mode_changed)
	EventBus.time_phase_changed.connect(_on_time_phase_changed)
	
	EventBus.reasoning_requested.connect(_on_reasoning_requested)
	EventBus.reasoning_succeeded.connect(_on_reasoning_succeeded)
	EventBus.reasoning_failed.connect(_on_reasoning_failed)
	
	EventBus.ending_triggered.connect(_on_ending_triggered)
	EventBus.notification_requested.connect(show_toast)
	EventBus.clue_obtained.connect(func(_cid, _data):
		update_clue_counter()
		var clue_sfx = ProjectContext.get_sfx("sfx_clue_found")
		if not clue_sfx.is_empty() and ResourceLoader.exists(clue_sfx):
			sfx_player.stream = load(clue_sfx)
			sfx_player.play()
	)
	update_clue_counter()
	
	# 顶部栏按钮事件
	btn_notebook.pressed.connect(toggle_notebook)
	btn_timeline.pressed.connect(open_timeline_modal)
	btn_save.pressed.connect(func(): SaveManager.save_game(1))
	btn_editor.pressed.connect(func(): get_tree().change_scene_to_file("res://editor/ui/editor_main.tscn"))
	btn_hub.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/project_hub.tscn"))
	if OS.has_feature("mobile") or not OS.has_feature("editor"):
		btn_editor.visible = false
		btn_hub.visible = false
	
	# 模态弹窗关闭与提交事件
	btn_close_notebook.pressed.connect(close_notebook)
	btn_close_timeline.pressed.connect(close_timeline)
	btn_close_reasoning.pressed.connect(close_reasoning)
	btn_submit_reasoning.pressed.connect(_on_submit_reasoning_pressed)
	
	btn_restart_game.pressed.connect(func():
		hide_modals()
		GameState.reset_state()
		NodeManager.start_game()
	)

# --- 输入监听与推进 ---
func _input(event: InputEvent) -> void:
	# ESC 键快捷关闭非锁定模态窗口
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if notebook_modal.visible:
			close_notebook()
			return
		elif timeline_modal.visible:
			close_timeline()
			return
		elif reasoning_modal.visible:
			close_reasoning()
			return

	# 对话推进逻辑
	if not dialogue_box.visible or choice_container.visible or modal_backdrop.visible:
		return
		
	var is_advance = false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var topbar_rect = top_bar.get_global_rect()
		if not topbar_rect.has_point(event.position):
			is_advance = true
	elif event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E]:
			is_advance = true
			
	if is_advance:
		trigger_dialogue_advance()

func trigger_dialogue_advance() -> void:
	if not dialogue_box.visible or choice_container.visible or modal_backdrop.visible:
		return
	if typewriter_tween and typewriter_tween.is_valid():
		typewriter_tween.kill()
	content_label.visible_ratio = 1.0
	DialogueManager.advance()

func hide_modals() -> void:
	modal_backdrop.visible = false
	notebook_modal.visible = false
	reasoning_modal.visible = false
	timeline_modal.visible = false
	ending_modal.visible = false
	choice_container.visible = false

# --- 对话与分支选择处理 ---
func _on_dialogue_line_displayed(line_data: Dictionary) -> void:
	dialogue_box.visible = true
	clear_choices()
	
	var speaker = line_data.get("speaker", "")
	speaker_label.text = speaker if not speaker.is_empty() else " "
	
	var text = line_data.get("text", "")
	content_label.text = text
	
	# 打字机平滑渐现
	content_label.visible_ratio = 0.0
	if typewriter_tween and typewriter_tween.is_valid():
		typewriter_tween.kill()
	typewriter_tween = create_tween()
	var duration = max(0.2, text.length() * 0.02)
	typewriter_tween.tween_property(content_label, "visible_ratio", 1.0, duration)
	
	# 播放语音 (基于统一资产系统)
	var raw_voice = line_data.get("voice", "")
	var voice_file = ProjectContext.get_voice(raw_voice)
	if not voice_file.is_empty() and ProjectContext.is_valid_file(voice_file):
		voice_player.stream = load(voice_file)
		voice_player.play()
	else:
		voice_player.stop()
		
	# 伴随音效 (基于统一资产系统)
	var raw_sfx = line_data.get("sfx", "")
	var line_sfx = ProjectContext.get_sfx(raw_sfx)
	if not line_sfx.is_empty() and ProjectContext.is_valid_file(line_sfx):
		sfx_player.stream = load(line_sfx)
		sfx_player.play()
		
	# 立绘渲染 (基于统一资产系统：支持角色名、角色ID、立绘文件名、直接路径，并支持表情差分)
	var raw_char = line_data.get("character_image", "")
	if raw_char.is_empty():
		raw_char = speaker
	var expression = line_data.get("expression", line_data.get("emotion", "normal"))
	var char_img = ProjectContext.get_character_portrait(raw_char, expression)
		
	var tex = ProjectContext.load_texture(char_img)
	if tex:
		char_portrait.texture = tex
		char_portrait.visible = true
	else:
		char_portrait.visible = false

func find_character_portrait_for_speaker(speaker_name: String, expression: String = "") -> String:
	return ProjectContext.get_character_portrait(speaker_name, expression)

func is_image_file_valid(path: String) -> bool:
	return ProjectContext.is_valid_file(path)

func _on_dialogue_choices_requested(choices: Array) -> void:
	clear_choices()
	if choices.is_empty():
		return
		
	choice_container.visible = true
	for i in range(choices.size()):
		var choice = choices[i]
		var btn = Button.new()
		btn.text = "   ▶  " + choice.get("text", "")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 56)
		btn.add_theme_font_size_override("font_size", 20)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		
		var n_style = StyleBoxFlat.new()
		n_style.bg_color = Color(0.08, 0.1, 0.15, 0.94)
		n_style.set_border_width_all(2)
		n_style.border_color = Color(0.35, 0.45, 0.6, 0.8)
		n_style.set_corner_radius_all(10)
		n_style.content_margin_left = 24
		n_style.content_margin_right = 24
		
		var h_style = StyleBoxFlat.new()
		h_style.bg_color = Color(0.15, 0.2, 0.28, 0.98)
		h_style.set_border_width_all(2)
		h_style.border_color = PALETTE["border_gold"]
		h_style.set_corner_radius_all(10)
		h_style.content_margin_left = 32
		h_style.content_margin_right = 24
		
		btn.add_theme_stylebox_override("normal", n_style)
		btn.add_theme_stylebox_override("hover", h_style)
		btn.add_theme_stylebox_override("pressed", h_style)
		btn.add_theme_stylebox_override("focus", h_style)
		
		btn.pressed.connect(func():
			EventBus.dialogue_choice_selected.emit(i)
		)
		choice_container.add_child(btn)

func _on_dialogue_topics_requested(topics: Array) -> void:
	clear_choices()
	choice_container.visible = true
	dialogue_box.visible = true
	speaker_label.text = "质询话题"
	content_label.text = "请选择你想询问的重点话题，或推进后续搜查："
	
	for topic in topics:
		var btn = Button.new()
		var title = topic.get("title", "")
		var is_asked = topic.get("is_asked", false)
		btn.text = ("   ✓ " if is_asked else "   ▶ ") + title
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 52)
		btn.add_theme_font_size_override("font_size", 19)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		
		var n_style = StyleBoxFlat.new()
		n_style.bg_color = Color(0.08, 0.1, 0.15, 0.92) if not is_asked else Color(0.06, 0.07, 0.10, 0.85)
		n_style.set_border_width_all(1)
		n_style.border_color = Color(0.35, 0.45, 0.6, 0.7) if not is_asked else Color(0.2, 0.25, 0.35, 0.4)
		n_style.set_corner_radius_all(8)
		n_style.content_margin_left = 20
		
		var h_style = StyleBoxFlat.new()
		h_style.bg_color = Color(0.14, 0.18, 0.26, 0.98)
		h_style.set_border_width_all(2)
		h_style.border_color = PALETTE["border_gold"]
		h_style.set_corner_radius_all(8)
		h_style.content_margin_left = 26
		
		btn.add_theme_stylebox_override("normal", n_style)
		btn.add_theme_stylebox_override("hover", h_style)
		btn.add_theme_stylebox_override("pressed", h_style)
		btn.add_theme_stylebox_override("focus", n_style)
		
		if is_asked:
			btn.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78, 0.85))
			
		var topic_id = topic.get("id", "")
		btn.pressed.connect(func():
			EventBus.dialogue_topic_selected.emit(topic_id)
		)
		choice_container.add_child(btn)

func clear_choices() -> void:
	choice_container.visible = false
	for child in choice_container.get_children():
		child.queue_free()

# --- 场景与搜查热区 ---
func _on_scene_changed(scene_id: String, scene_data: Dictionary) -> void:
	scene_title_label.text = "📍 " + scene_data.get("name", scene_id)
	
	var raw_bg_path = scene_data.get("background", scene_id)
	var bg_path = ProjectContext.get_scene_background(raw_bg_path)
	var tex = ProjectContext.load_texture(bg_path)
	if tex:
		bg_texture.texture = tex
		bg_texture.visible = true
	else:
		bg_texture.visible = false
		
	var raw_bgm_path = scene_data.get("bgm", scene_id)
	var bgm_path = ProjectContext.get_bgm(raw_bgm_path)
		
	if not bgm_path.is_empty() and ResourceLoader.exists(bgm_path):
		var s = load(bgm_path)
		if bgm_player.stream != s:
			bgm_player.stream = s
			bgm_player.play()
			
	refresh_explore_points()

func _on_explore_mode_changed(is_exploring: bool) -> void:
	explore_container.visible = is_exploring
	if is_exploring:
		char_portrait.visible = false
		refresh_explore_points()
		show_toast("🔍 现场搜查：点击画面中的可疑区域展开调查")

func refresh_explore_points() -> void:
	for child in explore_container.get_children():
		child.queue_free()
		
	var points = ExploreManager.get_active_explore_points()
	var vp_size = get_viewport_rect().size
	
	for pt in points:
		var rect_data = pt.get("rect", [0.1, 0.1, 0.1, 0.1])
		var btn = Button.new()
		btn.size = Vector2(rect_data[2] * vp_size.x, rect_data[3] * vp_size.y)
		btn.position = Vector2(rect_data[0] * vp_size.x, rect_data[1] * vp_size.y)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		
		# 精致搜查热区样式：平时微光黄框，悬停浮现聚光灯高亮
		var normal_style = StyleBoxFlat.new()
		normal_style.bg_color = Color(0, 0, 0, 0)
		normal_style.set_border_width_all(1)
		normal_style.border_color = Color(1.0, 0.85, 0.35, 0.25)
		normal_style.set_corner_radius_all(8)
		
		var hover_style = StyleBoxFlat.new()
		hover_style.bg_color = Color(1.0, 0.85, 0.35, 0.12)
		hover_style.set_border_width_all(2)
		hover_style.border_color = Color(1.0, 0.9, 0.35, 0.95)
		hover_style.set_corner_radius_all(8)
		
		btn.add_theme_stylebox_override("normal", normal_style)
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.add_theme_stylebox_override("pressed", hover_style)
		btn.add_theme_stylebox_override("focus", normal_style)
		
		# 底部悬浮指示胶囊
		var badge = Label.new()
		badge.text = pt.get("name", "调查")
		badge.add_theme_font_size_override("font_size", 16)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		badge.offset_top = -34
		badge.offset_bottom = -6
		badge.offset_left = 6
		badge.offset_right = -6
		
		var badge_style = StyleBoxFlat.new()
		badge_style.bg_color = Color(0.06, 0.08, 0.12, 0.88)
		badge_style.set_border_width_all(1)
		badge_style.border_color = Color(1.0, 0.85, 0.35, 0.6)
		badge_style.set_corner_radius_all(6)
		badge.add_theme_stylebox_override("normal", badge_style)
		
		btn.add_child(badge)
		
		var pt_id = pt.get("id", "")
		btn.pressed.connect(func():
			EventBus.explore_point_clicked.emit(pt_id, pt)
			call_deferred("refresh_explore_points")
		)
		explore_container.add_child(btn)

	# 导航辅助：如果本场景的所有调查点已经搜查完毕，提供醒目的前进推进按钮
	var cur_node_data = NodeManager.current_node_data
	var next_node_id = cur_node_data.get("next", "")
	if not next_node_id.is_empty():
		var btn_advance = Button.new()
		if points.is_empty():
			btn_advance.text = "✨ 调查完毕：前往下一区域 ▶"
			style_primary_button(btn_advance)
		else:
			btn_advance.text = "前往下一区域 ▶"
			style_button(btn_advance, false)
			
		btn_advance.custom_minimum_size = Vector2(240, 46)
		btn_advance.position = Vector2(vp_size.x - 280, vp_size.y - 120)
		btn_advance.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn_advance.pressed.connect(func():
			ExploreManager.is_exploring = false
			EventBus.explore_mode_changed.emit(false)
			NodeManager.jump_to_node(next_node_id)
		)
		explore_container.add_child(btn_advance)

# --- 随身笔记系统 (独立查阅抽屉) ---
func toggle_notebook() -> void:
	if notebook_modal.visible:
		close_notebook()
	else:
		open_notebook()

func open_notebook() -> void:
	hide_modals()
	notebook_modal.visible = true
	modal_backdrop.visible = true
	refresh_notebook()

func close_notebook() -> void:
	notebook_modal.visible = false
	modal_backdrop.visible = false

func refresh_notebook() -> void:
	for child in notebook_clue_list.get_children():
		child.queue_free()
		
	var clues = ClueManager.get_obtained_clues_data()
	if clues.is_empty():
		notebook_detail_title.text = "线索库暂空"
		notebook_detail_tag.text = "类型: 暂无"
		notebook_detail_source.text = "出处: 现场"
		notebook_detail_desc.text = "尚未获得任何证据。请在书房各处仔细搜查，或询问相关人员。"
		return
		
	for clue in clues:
		var cid = clue.get("id", "")
		var ctitle = clue.get("title", clue.get("name", cid))
		var ctype = clue.get("type", "物证")
		
		var btn = Button.new()
		btn.text = "  🔍 [%s] %s" % [ctype, ctitle]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 48)
		btn.add_theme_font_size_override("font_size", 18)
		style_button(btn, cid == current_notebook_clue)
		
		btn.pressed.connect(func():
			select_notebook_clue(cid)
		)
		notebook_clue_list.add_child(btn)
		
	select_notebook_clue(clues[0].get("id", ""))

func select_notebook_clue(clue_id: String) -> void:
	current_notebook_clue = clue_id
	var clue = DataManager.get_clue_data(clue_id)
	notebook_detail_title.text = clue.get("title", clue.get("name", clue_id))
	notebook_detail_tag.text = "类型: " + clue.get("type", "普通物证")
	notebook_detail_source.text = "出处: " + clue.get("source", "现场勘验")
	notebook_detail_desc.text = clue.get("description", "")
	
	# 刷新列表卡片选中态高亮
	var idx = 0
	var clues = ClueManager.get_obtained_clues_data()
	for child in notebook_clue_list.get_children():
		if child is Button and idx < clues.size():
			style_button(child, clues[idx].get("id", "") == clue_id)
		idx += 1

# --- 一体化举证推理台 (ReasoningArena) ---
func _on_reasoning_requested(_reasoning_id: String, reasoning_data: Dictionary) -> void:
	hide_modals()
	dialogue_box.visible = false
	explore_container.visible = false
	char_portrait.visible = false
	
	reasoning_modal.visible = true
	modal_backdrop.visible = true
	
	selected_reasoning_clue = ""
	reasoning_question_label.text = "❓ 质询核心: " + reasoning_data.get("question", "请找出对方言论中的破绽，并出示直接铁证！")
	reasoning_hint_label.text = ""
	selected_clue_summary_label.text = "准备出示: 【请在左侧列表中点击选择证据】"
	
	refresh_reasoning_clues()

func refresh_reasoning_clues() -> void:
	for child in reasoning_clue_list.get_children():
		child.queue_free()
		
	var clues = ClueManager.get_obtained_clues_data()
	if clues.is_empty():
		reasoning_detail_title.text = "暂无线索可用"
		reasoning_detail_tag.text = ""
		reasoning_detail_source.text = ""
		reasoning_detail_desc.text = "随身证物清单为空，请先返回现场进行搜查！"
		btn_submit_reasoning.disabled = true
		return
		
	btn_submit_reasoning.disabled = false
	for clue in clues:
		var cid = clue.get("id", "")
		var ctitle = clue.get("title", clue.get("name", cid))
		var ctype = clue.get("type", "物证")
		
		var btn = Button.new()
		btn.text = "  📦 [%s] %s" % [ctype, ctitle]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 52)
		btn.add_theme_font_size_override("font_size", 18)
		style_button(btn, false)
		
		btn.pressed.connect(func():
			select_reasoning_clue(cid)
		)
		reasoning_clue_list.add_child(btn)
		
	# 默认直接选定第一个证物，方便玩家立即查看细节与出示
	select_reasoning_clue(clues[0].get("id", ""))

func select_reasoning_clue(clue_id: String) -> void:
	selected_reasoning_clue = clue_id
	var clue = DataManager.get_clue_data(clue_id)
	var ctitle = clue.get("title", clue.get("name", clue_id))
	
	reasoning_detail_title.text = ctitle
	reasoning_detail_tag.text = "分类: " + clue.get("type", "现场物证")
	reasoning_detail_source.text = "出处: " + clue.get("source", "现场搜查")
	reasoning_detail_desc.text = clue.get("description", "")
	
	selected_clue_summary_label.text = "准备出示: 【%s】" % ctitle
	
	# 刷新证据卡片视觉高亮
	var idx = 0
	var clues = ClueManager.get_obtained_clues_data()
	for child in reasoning_clue_list.get_children():
		if child is Button and idx < clues.size():
			var is_sel = (clues[idx].get("id", "") == clue_id)
			style_button(child, is_sel)
			if is_sel:
				child.text = "  ✓ [%s] %s" % [clues[idx].get("type", "物证"), clues[idx].get("title", "")]
			else:
				child.text = "  📦 [%s] %s" % [clues[idx].get("type", "物证"), clues[idx].get("title", "")]
		idx += 1

func _on_submit_reasoning_pressed() -> void:
	if selected_reasoning_clue.is_empty():
		show_toast("请先在左侧选择要出示的证据！", "warning")
		return
		
	EventBus.reasoning_submitted.emit([selected_reasoning_clue])

func _on_reasoning_succeeded(_reasoning_id: String, _data: Dictionary) -> void:
	reasoning_modal.visible = false
	modal_backdrop.visible = false
	var obj_sfx = ProjectContext.get_sfx("sfx_objection")
	if not obj_sfx.is_empty() and ResourceLoader.exists(obj_sfx):
		sfx_player.stream = load(obj_sfx)
		sfx_player.play()

func _on_reasoning_failed(_reasoning_id: String, hint: String) -> void:
	reasoning_hint_label.text = "💡 破绽驳回: " + hint
	
	# 提示文字微动警示动画
	var tw = create_tween()
	reasoning_hint_label.modulate = Color(1.0, 0.3, 0.3, 1.0)
	tw.tween_property(reasoning_hint_label, "modulate", Color(1.0, 0.7, 0.7, 1.0), 0.5)

func close_reasoning() -> void:
	reasoning_modal.visible = false
	modal_backdrop.visible = false
	# 恢复此前的搜查状态
	explore_container.visible = true

# --- 时光机与回溯 ---
func open_timeline_modal() -> void:
	hide_modals()
	timeline_modal.visible = true
	modal_backdrop.visible = true
	
	for child in timeline_list_container.get_children():
		child.queue_free()
		
	var snapshots = GameState.milestones
	if snapshots.is_empty():
		var lbl = Label.new()
		lbl.text = "暂无历史里程碑记录。"
		lbl.add_theme_color_override("font_color", PALETTE["text_secondary"])
		timeline_list_container.add_child(lbl)
		return
		
	for snapshot in snapshots:
		var btn = Button.new()
		btn.text = "  ⏪ %s [%s]" % [snapshot.get("title", ""), snapshot.get("timestamp", "")]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 48)
		btn.add_theme_font_size_override("font_size", 18)
		style_button(btn, false)
		
		btn.pressed.connect(func():
			close_timeline()
			GameState.restore_from_snapshot(snapshot, true)
		)
		timeline_list_container.add_child(btn)

func close_timeline() -> void:
	timeline_modal.visible = false
	modal_backdrop.visible = false

func _on_time_phase_changed(phase_id: String, phase_data: Dictionary) -> void:
	phase_label.text = "⌛ 阶段: " + phase_data.get("name", phase_id)

func _on_ending_triggered(_ending_id: String, ending_data: Dictionary) -> void:
	hide_modals()
	dialogue_box.visible = false
	explore_container.visible = false
	char_portrait.visible = false
	
	ending_modal.visible = true
	modal_backdrop.visible = true
	ending_title_label.text = ending_data.get("title", "案件完结")
	ending_desc_label.text = ending_data.get("description", "")

# --- Toast 浮动通知 ---
func show_toast(msg: String, type: String = "info") -> void:
	toast_label.text = msg
	match type:
		"clue": toast_panel.modulate = Color(0.6, 0.9, 1.0)
		"success": toast_panel.modulate = Color(0.6, 1.0, 0.6)
		"warning": toast_panel.modulate = Color(1.0, 0.8, 0.5)
		_: toast_panel.modulate = Color(1.0, 1.0, 1.0)
		
	toast_panel.visible = true
	var tw = create_tween()
	toast_panel.modulate.a = 0.0
	tw.tween_property(toast_panel, "modulate:a", 1.0, 0.2)
	tw.tween_interval(2.2)
	tw.tween_property(toast_panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): toast_panel.visible = false)
