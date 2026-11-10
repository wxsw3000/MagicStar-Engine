# editor/ui/dialogs/character_sheet_dialog.gd
# 角色属性表工坊弹窗：工业化「人设 → 立绘 → 差分 → 声线」四维属性选择表与一键拼装引擎
class_name CharacterSheetDialog
extends ConfirmationDialog

signal sheet_applied(character_id: String, assembled_data: Dictionary)

const CharacterSheetMgr = preload("res://editor/core/character_sheet_manager.gd")
const AIAssetMgr = preload("res://editor/core/ai_asset_manager.gd")

var character_id: String = ""
var character_ent: Dictionary = {}
var current_sheet: Dictionary = {}

# 控件引用字典，便于统一存取和枚举联动
var ui_controls: Dictionary = {}

# 预览与差分控件
var tab_container: TabContainer
var txt_preview_base_prompt: TextEdit
var txt_preview_negative_prompt: TextEdit
var txt_preview_voice_desc: TextEdit
var txt_preview_voice_role: LineEdit
var txt_preview_three_view_prompt: TextEdit
var item_list_expressions: ItemList
var lbl_assemble_stats: Label

func _ready() -> void:
	title = "📋 角色属性卡工坊 (Character Sheet & AI Prompt Assembler)"
	min_size = Vector2(1040, 720)
	ok_button_text = "✨ 一键装配应用至当前角色"
	cancel_button_text = "关闭"
	confirmed.connect(_on_confirm_apply)

	if tab_container == null:
		_rebuild_all_ui()
	if not current_sheet.is_empty():
		_load_sheet_to_ui(current_sheet)
		_refresh_preview()

func setup_character(cid: String, ent: Dictionary) -> void:
	character_id = cid
	character_ent = ent
	
	# 优先从 ent 或 DataManager 读取属性表，如无则读取沈策预设或创建标准默认表
	if ent.has("character_sheet") and ent["character_sheet"] is Dictionary and not ent["character_sheet"].is_empty():
		current_sheet = ent["character_sheet"].duplicate(true)
	elif cid.contains("shen_ce"):
		current_sheet = CharacterSheetMgr.get_shen_ce_preset()
	else:
		var cname = ent.get("name", cid)
		current_sheet = CharacterSheetMgr.create_default_sheet(cname, "男", 24)
	
	if tab_container == null:
		_rebuild_all_ui()
	_load_sheet_to_ui(current_sheet)
	_refresh_preview()

func _rebuild_all_ui() -> void:
	ui_controls.clear()
	for c in get_children():
		if c is MarginContainer:
			c.queue_free()

	var root_margin = MarginContainer.new()
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_margin.add_theme_constant_override("margin_left", 14)
	root_margin.add_theme_constant_override("margin_top", 12)
	root_margin.add_theme_constant_override("margin_right", 14)
	root_margin.add_theme_constant_override("margin_bottom", 14)
	add_child(root_margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 10)
	root_margin.add_child(main_vbox)

	# 顶部工具条
	var top_bar = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 10)
	main_vbox.add_child(top_bar)

	var lbl_hint = Label.new()
	lbl_hint.text = "🎯 工业化四维角色属性选择表：下拉选择枚举值，支持即选即改与一键拼装"
	lbl_hint.modulate = Color(0.75, 0.9, 1.0)
	top_bar.add_child(lbl_hint)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)

	var btn_preset_shen_ce = Button.new()
	btn_preset_shen_ce.text = "👤 载入沈策标准人设预设"
	btn_preset_shen_ce.pressed.connect(func():
		current_sheet = CharacterSheetMgr.get_shen_ce_preset()
		_load_sheet_to_ui(current_sheet)
		_refresh_preview()
	)
	top_bar.add_child(btn_preset_shen_ce)

	var btn_reset_default = Button.new()
	btn_reset_default.text = "🔄 重置默认空表"
	btn_reset_default.pressed.connect(func():
		var cname = character_ent.get("name", "新角色")
		current_sheet = CharacterSheetMgr.create_default_sheet(cname, "男", 24)
		_load_sheet_to_ui(current_sheet)
		_refresh_preview()
	)
	top_bar.add_child(btn_reset_default)

	# 选项卡容器
	tab_container = TabContainer.new()
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(tab_container)

	# Tab 1: 📇 身份卡 & 外貌规格
	var scroll_tab1 = ScrollContainer.new()
	scroll_tab1.name = "📇 身份与外貌 (Appearance)"
	scroll_tab1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_tab1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.add_child(scroll_tab1)
	var vbox_tab1 = VBoxContainer.new()
	vbox_tab1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_tab1.add_theme_constant_override("separation", 14)
	scroll_tab1.add_child(vbox_tab1)
	_build_identity_card(vbox_tab1)
	_build_appearance_card(vbox_tab1)

	# Tab 2: 🎭 气质风格 & 服装装备
	var scroll_tab2 = ScrollContainer.new()
	scroll_tab2.name = "🎭 气质与服装 (Vibe & Outfit)"
	scroll_tab2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_tab2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.add_child(scroll_tab2)
	var vbox_tab2 = VBoxContainer.new()
	vbox_tab2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_tab2.add_theme_constant_override("separation", 14)
	scroll_tab2.add_child(vbox_tab2)
	_build_vibe_card(vbox_tab2)
	_build_outfit_card(vbox_tab2)

	# Tab 3: 💡 性格叙事 & 声线配音
	var scroll_tab3 = ScrollContainer.new()
	scroll_tab3.name = "🎙️ 性格与声线 (Voice)"
	scroll_tab3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_tab3.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.add_child(scroll_tab3)
	var vbox_tab3 = VBoxContainer.new()
	vbox_tab3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_tab3.add_theme_constant_override("separation", 14)
	scroll_tab3.add_child(vbox_tab3)
	_build_personality_card(vbox_tab3)
	_build_voice_card(vbox_tab3)

	# Tab 4: 🎨 6+2 差分清单
	var scroll_tab4 = ScrollContainer.new()
	scroll_tab4.name = "🎨 6+2 差分清单 (Expressions)"
	scroll_tab4.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_tab4.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.add_child(scroll_tab4)
	var vbox_tab4 = VBoxContainer.new()
	vbox_tab4.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_tab4.add_theme_constant_override("separation", 14)
	scroll_tab4.add_child(vbox_tab4)
	_build_expression_card(vbox_tab4)

	# Tab 5: 🧩 一键拼装预览 & 三视图
	var scroll_tab5 = ScrollContainer.new()
	scroll_tab5.name = "🧩 一键拼装与三视图预览"
	scroll_tab5.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_tab5.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.add_child(scroll_tab5)
	var vbox_tab5 = VBoxContainer.new()
	vbox_tab5.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_tab5.add_theme_constant_override("separation", 14)
	scroll_tab5.add_child(vbox_tab5)
	_build_preview_card(vbox_tab5)

	tab_container.tab_changed.connect(func(_idx):
		_save_ui_to_sheet()
		_refresh_preview()
	)

# --- 辅助方法：创建带枚举下拉与自定义文本的统一选择行 ---
func _create_select_row(parent: GridContainer, label_text: String, enum_key: String, field_key: String) -> void:
	var lbl = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(170, 0)
	lbl.modulate = Color(0.85, 0.9, 0.95)
	parent.add_child(lbl)

	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 6)
	parent.add_child(hbox)

	var opt = OptionButton.new()
	opt.custom_minimum_size = Vector2(190, 32)
	var options: Array = CharacterSheetMgr.ENUM_OPTIONS.get(enum_key, [])
	for i in range(options.size()):
		opt.add_item(options[i], i)
	hbox.add_child(opt)

	var txt = LineEdit.new()
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.placeholder_text = "自定义详细描述 / 补充说明"
	hbox.add_child(txt)

	ui_controls[field_key + "_opt"] = opt
	ui_controls[field_key + "_txt"] = txt

	# 下拉切换时自动填充文本并触发联动预览
	opt.item_selected.connect(func(idx: int):
		if idx >= 0 and idx < options.size():
			txt.text = options[idx]
		_save_ui_to_sheet()
		_refresh_preview()
	)

	txt.text_changed.connect(func(_new_t):
		_save_ui_to_sheet()
		_refresh_preview()
	)

func _build_identity_card(parent: VBoxContainer) -> void:
	var group = _create_section_panel(parent, "一、身份卡（Identity）[人设·叙事]")
	var grid = _create_grid(group, 2)

	# 姓名/称号
	var lbl1 = Label.new(); lbl1.text = "姓名 / 称号:"; lbl1.modulate = Color(0.85, 0.9, 0.95); grid.add_child(lbl1)
	var name_box = HBoxContainer.new()
	var txt_name = LineEdit.new(); txt_name.placeholder_text = "本名"; txt_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_child(txt_name); ui_controls["ident_name"] = txt_name
	var txt_title = LineEdit.new(); txt_title.placeholder_text = "称号/代号"; txt_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_child(txt_title); ui_controls["ident_title"] = txt_title
	grid.add_child(name_box)

	# 年龄
	var lbl2 = Label.new(); lbl2.text = "年龄 [★影响头身与声线]:"; lbl2.modulate = Color(0.85, 0.9, 0.95); grid.add_child(lbl2)
	var spin_age = SpinBox.new(); spin_age.min_value = 1; spin_age.max_value = 150; spin_age.value = 24
	grid.add_child(spin_age); ui_controls["ident_age"] = spin_age

	# 性别
	_create_select_row(grid, "性别 [★影响骨架音域]:", "gender", "ident_gender")

	# 种族
	_create_select_row(grid, "种族 / 物种:", "species", "ident_species")

	# 职业
	var lbl3 = Label.new(); lbl3.text = "职业 / 身份:"; lbl3.modulate = Color(0.85, 0.9, 0.95); grid.add_child(lbl3)
	var txt_occ = LineEdit.new(); txt_occ.placeholder_text = "如：私家侦探 / 青年画家"; txt_occ.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(txt_occ); ui_controls["ident_occupation"] = txt_occ

	# 阵营
	_create_select_row(grid, "阵营 / 势力:", "faction", "ident_faction")

	# 社会地位
	_create_select_row(grid, "社会地位:", "social_status", "ident_social_status")

	# 一句话人设与三词核心
	var lbl4 = Label.new(); lbl4.text = "三词核心 [人设收敛]:"; lbl4.modulate = Color(0.85, 0.9, 0.95); grid.add_child(lbl4)
	var txt_three = LineEdit.new(); txt_three.placeholder_text = "如：冷 · 锐 · 敏"; grid.add_child(txt_three)
	ui_controls["ident_three_words"] = txt_three

	var lbl5 = Label.new(); lbl5.text = "一句话人设 [外表+身份+反差]:"; lbl5.modulate = Color(0.85, 0.9, 0.95); grid.add_child(lbl5)
	var txt_one = TextEdit.new(); txt_one.custom_minimum_size = Vector2(0, 50); grid.add_child(txt_one)
	ui_controls["ident_one_line"] = txt_one

func _build_appearance_card(parent: VBoxContainer) -> void:
	var group = _create_section_panel(parent, "二、外貌规格（Appearance）★ 立绘核心 (全选项可下拉选择)")
	var grid = _create_grid(group, 2)

	_create_select_row(grid, "身高 [★与体型定头身]:", "height", "app_height")
	_create_select_row(grid, "体型 [★骨相基础]:", "body_type", "app_body_type")
	_create_select_row(grid, "骨架比例:", "skeleton", "app_skeleton")
	_create_select_row(grid, "头身比 [★2Q版/6少年/7美型]:", "head_body_ratio", "app_ratio")
	_create_select_row(grid, "脸型 [★二次元轮廓]:", "face_shape", "app_face")
	_create_select_row(grid, "眼型 [丹凤眼/杏眼等]:", "eye_shape", "app_eye_shape")
	_create_select_row(grid, "瞳色 [冰蓝/深黑/金黄等]:", "eye_color", "app_eye_color")
	_create_select_row(grid, "发型 [★剪影识别点]:", "hair_style", "app_hair_style")
	_create_select_row(grid, "发色 [黑色/银白/金黄等]:", "hair_color", "app_hair_color")
	_create_select_row(grid, "肤色 [冷白/暖白/小麦色]:", "skin_tone", "app_skin_tone")
	_create_select_row(grid, "标志性单品 [一眼记住]:", "signature_item", "app_signature")
	_create_select_row(grid, "特殊体征 [★刚性防老约束]:", "special_features", "app_special")

func _build_vibe_card(parent: VBoxContainer) -> void:
	var group = _create_section_panel(parent, "三、气质风格（Vibe）★ 立绘+声线桥梁")
	var grid = _create_grid(group, 2)

	_create_select_row(grid, "气质类型 [冷酷/腹黑/温柔等]:", "vibe_type", "vibe_type")
	_create_select_row(grid, "年龄感呈现 [★防衰老锁龄]:", "age_presentation", "vibe_age_pres")
	_create_select_row(grid, "风格倾向 [日系二次元/国风等]:", "style_preference", "vibe_style")
	_create_select_row(grid, "默认情绪 [差分基准状态]:", "default_emotion", "vibe_default_emo")

func _build_outfit_card(parent: VBoxContainer) -> void:
	var group = _create_section_panel(parent, "四、服装装备（Outfit）[立绘穿搭]")
	var grid = _create_grid(group, 2)

	_create_select_row(grid, "服装风格 [制服/礼服/便服]:", "outfit_style", "outfit_style")
	_create_select_row(grid, "配色方案 [60-30-10 比例]:", "color_scheme", "outfit_colors")
	_create_select_row(grid, "材质质感 [毛呢/皮革/丝绸]:", "material_texture", "outfit_material")

	var lbl1 = Label.new(); lbl1.text = "饰品 / 徽章:"; lbl1.modulate = Color(0.85, 0.9, 0.95); grid.add_child(lbl1)
	var txt_acc = LineEdit.new(); txt_acc.placeholder_text = "如：暗银色指南针袖扣"; grid.add_child(txt_acc)
	ui_controls["outfit_accessories"] = txt_acc

	var lbl2 = Label.new(); lbl2.text = "武器 / 随身道具:"; lbl2.modulate = Color(0.85, 0.9, 0.95); grid.add_child(lbl2)
	var txt_props = LineEdit.new(); txt_props.placeholder_text = "如：侦探手册与黄铜放大镜"; grid.add_child(txt_props)
	ui_controls["outfit_props"] = txt_props

func _build_personality_card(parent: VBoxContainer) -> void:
	var group = _create_section_panel(parent, "五、性格叙事（Personality）[配音与剧情]")
	var grid = _create_grid(group, 2)

	var lbl1 = Label.new(); lbl1.text = "性格关键词 (3-5词):"; lbl1.modulate = Color(0.85, 0.9, 0.95); grid.add_child(lbl1)
	var txt_kw = LineEdit.new(); txt_kw.placeholder_text = "如：外冷内热，逻辑洁癖，敏锐毒舌"; grid.add_child(txt_kw)
	ui_controls["pers_keywords"] = txt_kw

	var lbl2 = Label.new(); lbl2.text = "习惯动作 [★可做姿态差分]:"; lbl2.modulate = Color(0.85, 0.9, 0.95); grid.add_child(lbl2)
	var txt_habit = LineEdit.new(); txt_habit.placeholder_text = "如：单手插风衣口袋，轻触下颌沉思"; grid.add_child(txt_habit)
	ui_controls["pers_habit"] = txt_habit

	var lbl3 = Label.new(); lbl3.text = "反差设定 (趣味埋点):"; lbl3.modulate = Color(0.85, 0.9, 0.95); grid.add_child(lbl3)
	var txt_con = TextEdit.new(); txt_con.custom_minimum_size = Vector2(0, 45); grid.add_child(txt_con)
	ui_controls["pers_contrast"] = txt_con

	var lbl4 = Label.new(); lbl4.text = "标志口头禅:"; lbl4.modulate = Color(0.85, 0.9, 0.95); grid.add_child(lbl4)
	var txt_cp = LineEdit.new(); txt_cp.placeholder_text = "如：真相从来不会因为谎言动听而改变形状。"; grid.add_child(txt_cp)
	ui_controls["pers_catchphrase"] = txt_cp

func _build_voice_card(parent: VBoxContainer) -> void:
	var group = _create_section_panel(parent, "七、声线风格（Voice）★ 配音核心与智能映射")
	var grid = _create_grid(group, 2)

	_create_select_row(grid, "音域 [低音/中音/高音]:", "pitch_range", "voice_pitch")
	_create_select_row(grid, "音色 [磁性/清亮/沙哑/御姐]:", "timbre", "voice_timbre")
	_create_select_row(grid, "语速 [慢/适中/快]:", "speed", "voice_speed")
	_create_select_row(grid, "语气基调 [沉稳/轻佻/强势]:", "tone_baseline", "voice_tone")
	_create_select_row(grid, "口音/腔调 [普通话/古风/机械]:", "accent", "voice_accent")
	_create_select_row(grid, "情绪特征 [内敛/外放/起伏大]:", "emotional_expression", "voice_emotion")

	var lbl1 = Label.new(); lbl1.text = "参考声线描述 (给AI/配音员):"; lbl1.modulate = Color(0.85, 0.9, 0.95); grid.add_child(lbl1)
	var txt_ref = TextEdit.new(); txt_ref.custom_minimum_size = Vector2(0, 45); grid.add_child(txt_ref)
	ui_controls["voice_ref_desc"] = txt_ref

	var lbl2 = Label.new(); lbl2.text = "推荐 TTS Role (在线发音角色):"; lbl2.modulate = Color(0.85, 0.9, 0.95); grid.add_child(lbl2)
	var opt_tts = OptionButton.new()
	opt_tts.add_item("zh-CN-YunjianNeural (沉稳/磁性青年男声)", 0); opt_tts.set_item_metadata(0, "zh-CN-YunjianNeural")
	opt_tts.add_item("zh-CN-YunxiNeural (阳光/清朗青年男声)", 1); opt_tts.set_item_metadata(1, "zh-CN-YunxiNeural")
	opt_tts.add_item("zh-CN-YunyangNeural (严谨成熟男声)", 2); opt_tts.set_item_metadata(2, "zh-CN-YunyangNeural")
	opt_tts.add_item("zh-CN-XiaohanNeural (冷冽/御姐女声)", 3); opt_tts.set_item_metadata(3, "zh-CN-XiaohanNeural")
	opt_tts.add_item("zh-CN-XiaoxiaoNeural (标准温暖女主声)", 4); opt_tts.set_item_metadata(4, "zh-CN-XiaoxiaoNeural")
	opt_tts.add_item("zh-CN-XiaoyiNeural (甜美少女声)", 5); opt_tts.set_item_metadata(5, "zh-CN-XiaoyiNeural")
	grid.add_child(opt_tts); ui_controls["voice_tts_role"] = opt_tts

func _build_expression_card(parent: VBoxContainer) -> void:
	var group = _create_section_panel(parent, "六、表情差分清单（Expression Sheet）★ 6基础 + 2专属")

	var lbl_exp_info = Label.new()
	lbl_exp_info.text = "以下 8 大表情均自动注入【刚性逆龄防老 (NO wrinkles, NO aging)】指令，保证角色五官生动的同时面颊绝对光滑平整："
	lbl_exp_info.modulate = Color(0.7, 0.85, 1.0)
	group.add_child(lbl_exp_info)

	item_list_expressions = ItemList.new()
	item_list_expressions.custom_minimum_size = Vector2(0, 320)
	item_list_expressions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(item_list_expressions)

func _build_preview_card(parent: VBoxContainer) -> void:
	var group = _create_section_panel(parent, "九、一键拼装成果与全身三视图 Prompt")

	lbl_assemble_stats = Label.new()
	lbl_assemble_stats.modulate = Color(0.4, 1.0, 0.6)
	group.add_child(lbl_assemble_stats)

	var lbl1 = Label.new(); lbl1.text = "🎨 演播立绘 Base Prompt (用于生成 3/4 侧身带戏剧光影的演播主图):"
	group.add_child(lbl1)
	txt_preview_base_prompt = TextEdit.new()
	txt_preview_base_prompt.custom_minimum_size = Vector2(0, 80)
	txt_preview_base_prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	group.add_child(txt_preview_base_prompt)

	var lbl2 = Label.new(); lbl2.text = "📐 全身三视图 Turnaround Prompt (用于生成正面/正侧/背面三视图概念档案):"
	lbl2.modulate = Color(0.8, 0.9, 1.0)
	group.add_child(lbl2)
	txt_preview_three_view_prompt = TextEdit.new()
	txt_preview_three_view_prompt.custom_minimum_size = Vector2(0, 75)
	txt_preview_three_view_prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	group.add_child(txt_preview_three_view_prompt)

	var lbl3 = Label.new(); lbl3.text = "🛡️ 刚性逆龄防老 Negative Prompt (100% 杜绝法令纹/眼袋/老态皱纹):"
	group.add_child(lbl3)
	txt_preview_negative_prompt = TextEdit.new()
	txt_preview_negative_prompt.custom_minimum_size = Vector2(0, 50)
	txt_preview_negative_prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	group.add_child(txt_preview_negative_prompt)

	var lbl4 = Label.new(); lbl4.text = "🎙️ 配音声线描述与推荐 TTS Role:"
	group.add_child(lbl4)
	var v_row = HBoxContainer.new()
	txt_preview_voice_desc = TextEdit.new(); txt_preview_voice_desc.custom_minimum_size = Vector2(0, 45); txt_preview_voice_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v_row.add_child(txt_preview_voice_desc)
	txt_preview_voice_role = LineEdit.new(); txt_preview_voice_role.custom_minimum_size = Vector2(240, 0); txt_preview_voice_role.editable = false
	v_row.add_child(txt_preview_voice_role)
	group.add_child(v_row)

func _create_section_panel(parent: Control, title_text: String) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.18, 0.95)
	style.set_corner_radius_all(6)
	style.border_width_left = 1; style.border_width_right = 1
	style.border_width_top = 1; style.border_width_bottom = 1
	style.border_color = Color(0.24, 0.28, 0.36)
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var lbl = Label.new()
	lbl.text = title_text
	lbl.modulate = Color(1.0, 0.85, 0.4)
	lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(lbl)

	parent.add_child(panel)
	return vbox

func _create_grid(parent: VBoxContainer, cols: int = 2) -> GridContainer:
	var grid = GridContainer.new()
	grid.columns = cols
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	return grid

func _load_sheet_to_ui(sheet: Dictionary) -> void:
	var ident = sheet.get("identity", {})
	var app = sheet.get("appearance", {})
	var vibe = sheet.get("vibe", {})
	var outfit = sheet.get("outfit", {})
	var pers = sheet.get("personality", {})
	var voice = sheet.get("voice", {})

	# 身份卡
	if ui_controls.has("ident_name"): ui_controls["ident_name"].text = ident.get("name", "")
	if ui_controls.has("ident_title"): ui_controls["ident_title"].text = ident.get("title", "")
	if ui_controls.has("ident_age"): ui_controls["ident_age"].value = float(ident.get("age", 24))
	_set_select_value("ident_gender", ident.get("gender", "男"))
	_set_select_value("ident_species", ident.get("species", "人类"))
	if ui_controls.has("ident_occupation"): ui_controls["ident_occupation"].text = ident.get("occupation", "")
	_set_select_value("ident_faction", ident.get("faction", "正义秩序"))
	_set_select_value("ident_social_status", ident.get("social_status", "平民精英"))
	if ui_controls.has("ident_three_words"): ui_controls["ident_three_words"].text = ident.get("three_core_words", "")
	if ui_controls.has("ident_one_line"): ui_controls["ident_one_line"].text = ident.get("one_line_summary", "")

	# 外貌规格
	_set_select_value("app_height", app.get("height", "182cm"))
	_set_select_value("app_body_type", app.get("body_type", "匀称偏清瘦"))
	_set_select_value("app_skeleton", app.get("skeleton", "宽肩窄腰，长腿"))
	_set_select_value("app_ratio", app.get("head_body_ratio", "7头身"))
	_set_select_value("app_face", app.get("face_shape", "削瘦英朗尖脸"))
	_set_select_value("app_eye_shape", app.get("eye_shape", "狭长丹凤眼"))
	_set_select_value("app_eye_color", app.get("eye_color", "冰灰深蓝"))
	_set_select_value("app_hair_style", app.get("hair_style", "偏分微凌乱碎短发，额前细碎刘海"))
	_set_select_value("app_hair_color", app.get("hair_color", "深黑"))
	_set_select_value("app_skin_tone", app.get("skin_tone", "冷白无暇平滑肌肤"))
	_set_select_value("app_signature", app.get("signature_item", "深驼色大翻领经典双排扣风衣 + 暗红细领带"))
	_set_select_value("app_special", app.get("special_features", "面颊平滑无胡茬，无皱纹，保持年轻美型"))

	# 气质与服装
	_set_select_value("vibe_type", vibe.get("vibe_type", "冷酷沉稳"))
	_set_select_value("vibe_age_pres", vibe.get("age_presentation", "成熟从容，但骨相与皮肤严格锁定青年美型感（杜绝老化）"))
	_set_select_value("vibe_style", vibe.get("style_preference", "日系二次元商业AVG插画风格"))
	_set_select_value("vibe_default_emo", vibe.get("default_emotion", "从容冷静，专注洞察"))

	_set_select_value("outfit_style", outfit.get("outfit_style", "英伦侦探风正装与便服混搭"))
	_set_select_value("outfit_colors", outfit.get("color_scheme", "深驼色(60%)为主，藏青炭黑(30%)为辅，暗红细领带与白衬衫(10%)点缀"))
	_set_select_value("outfit_material", outfit.get("material_texture", "厚重毛呢与挺括棉质质感，丝质微反光"))
	if ui_controls.has("outfit_accessories"): ui_controls["outfit_accessories"].text = outfit.get("accessories", "")
	if ui_controls.has("outfit_props"): ui_controls["outfit_props"].text = outfit.get("weapon_props", "")

	# 性格与声线
	if ui_controls.has("pers_keywords"): ui_controls["pers_keywords"].text = pers.get("keywords", "")
	if ui_controls.has("pers_habit"): ui_controls["pers_habit"].text = pers.get("habitual_action", "")
	if ui_controls.has("pers_contrast"): ui_controls["pers_contrast"].text = pers.get("contrast_setting", "")
	if ui_controls.has("pers_catchphrase"): ui_controls["pers_catchphrase"].text = pers.get("catchphrase", "")

	_set_select_value("voice_pitch", voice.get("pitch_range", "中低音"))
	_set_select_value("voice_timbre", voice.get("timbre", "磁性冷冽青年音"))
	_set_select_value("voice_speed", voice.get("speed", "适中偏慢"))
	_set_select_value("voice_tone", voice.get("tone_baseline", "沉稳冷静，掌控全场"))
	_set_select_value("voice_accent", voice.get("accent", "标准普通话，咬字清晰，句尾微下沉"))
	_set_select_value("voice_emotion", voice.get("emotional_expression", "内敛平稳，质询时掷地有声"))
	if ui_controls.has("voice_ref_desc"): ui_controls["voice_ref_desc"].text = voice.get("reference_desc", "")

	var tts_role = voice.get("recommended_tts_role", "zh-CN-YunjianNeural")
	if ui_controls.has("voice_tts_role"):
		var opt_tts = ui_controls["voice_tts_role"] as OptionButton
		for i in range(opt_tts.item_count):
			if opt_tts.get_item_metadata(i) == tts_role:
				opt_tts.selected = i
				break

	if item_list_expressions:
		item_list_expressions.clear()
		for expr in sheet.get("expression_sheet", CharacterSheetMgr.get_default_expression_list()):
			var tag = "[专属]" if expr.get("is_custom", false) else "[基础]"
			item_list_expressions.add_item("%s %s | 眉眼嘴变化: %s | 约束: %s" % [tag, expr.get("name", ""), expr.get("changes", ""), expr.get("details", "")])

func _set_select_value(field_key: String, val: String) -> void:
	if ui_controls.has(field_key + "_txt"):
		ui_controls[field_key + "_txt"].text = val
	if ui_controls.has(field_key + "_opt"):
		var opt = ui_controls[field_key + "_opt"] as OptionButton
		for i in range(opt.item_count):
			var it = opt.get_item_text(i)
			if it == val or val.begins_with(it) or it.begins_with(val):
				opt.selected = i
				break

func _get_select_value(field_key: String, default_val: String = "") -> String:
	if ui_controls.has(field_key + "_txt"):
		var t = ui_controls[field_key + "_txt"].text.strip_edges()
		if not t.is_empty():
			return t
	if ui_controls.has(field_key + "_opt"):
		var opt = ui_controls[field_key + "_opt"] as OptionButton
		if opt.selected >= 0:
			return opt.get_item_text(opt.selected)
	return default_val

func _save_ui_to_sheet() -> void:
	if not current_sheet.has("identity"): current_sheet["identity"] = {}
	if not current_sheet.has("appearance"): current_sheet["appearance"] = {}
	if not current_sheet.has("vibe"): current_sheet["vibe"] = {}
	if not current_sheet.has("outfit"): current_sheet["outfit"] = {}
	if not current_sheet.has("personality"): current_sheet["personality"] = {}
	if not current_sheet.has("voice"): current_sheet["voice"] = {}

	var ident = current_sheet["identity"]
	if ui_controls.has("ident_name"): ident["name"] = ui_controls["ident_name"].text.strip_edges()
	if ui_controls.has("ident_title"): ident["title"] = ui_controls["ident_title"].text.strip_edges()
	if ui_controls.has("ident_age"): ident["age"] = int(ui_controls["ident_age"].value)
	ident["gender"] = _get_select_value("ident_gender", "男")
	ident["species"] = _get_select_value("ident_species", "人类")
	if ui_controls.has("ident_occupation"): ident["occupation"] = ui_controls["ident_occupation"].text.strip_edges()
	ident["faction"] = _get_select_value("ident_faction", "正义秩序")
	ident["social_status"] = _get_select_value("ident_social_status", "平民精英")
	if ui_controls.has("ident_three_words"): ident["three_core_words"] = ui_controls["ident_three_words"].text.strip_edges()
	if ui_controls.has("ident_one_line"): ident["one_line_summary"] = ui_controls["ident_one_line"].text.strip_edges()

	var app = current_sheet["appearance"]
	app["height"] = _get_select_value("app_height", "182cm")
	app["body_type"] = _get_select_value("app_body_type", "匀称偏清瘦")
	app["skeleton"] = _get_select_value("app_skeleton", "宽肩窄腰，长腿")
	app["head_body_ratio"] = _get_select_value("app_ratio", "7头身")
	app["face_shape"] = _get_select_value("app_face", "削瘦英朗尖脸")
	app["eye_shape"] = _get_select_value("app_eye_shape", "狭长丹凤眼")
	app["eye_color"] = _get_select_value("app_eye_color", "冰灰深蓝")
	app["hair_style"] = _get_select_value("app_hair_style", "偏分微凌乱碎短发，额前细碎刘海")
	app["hair_color"] = _get_select_value("app_hair_color", "深黑")
	app["skin_tone"] = _get_select_value("app_skin_tone", "冷白无暇平滑肌肤")
	app["signature_item"] = _get_select_value("app_signature", "深驼色大翻领经典双排扣风衣 + 暗红细领带")
	app["special_features"] = _get_select_value("app_special", "面颊平滑无胡茬，无皱纹，保持年轻美型")

	var vibe = current_sheet["vibe"]
	vibe["vibe_type"] = _get_select_value("vibe_type", "冷酷沉稳")
	vibe["age_presentation"] = _get_select_value("vibe_age_pres", "成熟从容，但骨相与皮肤严格锁定青年美型感（杜绝老化）")
	vibe["style_preference"] = _get_select_value("vibe_style", "日系二次元商业AVG插画风格")
	vibe["default_emotion"] = _get_select_value("vibe_default_emo", "从容冷静，专注洞察")

	var outfit = current_sheet["outfit"]
	outfit["outfit_style"] = _get_select_value("outfit_style", "英伦侦探风正装与便服混搭")
	outfit["color_scheme"] = _get_select_value("outfit_colors", "深驼色(60%)为主，藏青炭黑(30%)为辅，暗红细领带与白衬衫(10%)点缀")
	outfit["material_texture"] = _get_select_value("outfit_material", "厚重毛呢与挺括棉质质感，丝质微反光")
	if ui_controls.has("outfit_accessories"): outfit["accessories"] = ui_controls["outfit_accessories"].text.strip_edges()
	if ui_controls.has("outfit_props"): outfit["weapon_props"] = ui_controls["outfit_props"].text.strip_edges()

	var pers = current_sheet["personality"]
	if ui_controls.has("pers_keywords"): pers["keywords"] = ui_controls["pers_keywords"].text.strip_edges()
	if ui_controls.has("pers_habit"): pers["habitual_action"] = ui_controls["pers_habit"].text.strip_edges()
	if ui_controls.has("pers_contrast"): pers["contrast_setting"] = ui_controls["pers_contrast"].text.strip_edges()
	if ui_controls.has("pers_catchphrase"): pers["catchphrase"] = ui_controls["pers_catchphrase"].text.strip_edges()

	var voice = current_sheet["voice"]
	voice["pitch_range"] = _get_select_value("voice_pitch", "中低音")
	voice["timbre"] = _get_select_value("voice_timbre", "磁性冷冽青年音")
	voice["speed"] = _get_select_value("voice_speed", "适中偏慢")
	voice["tone_baseline"] = _get_select_value("voice_tone", "沉稳冷静，掌控全场")
	voice["accent"] = _get_select_value("voice_accent", "标准普通话，咬字清晰，句尾微下沉")
	voice["emotional_expression"] = _get_select_value("voice_emotion", "内敛平稳，质询时掷地有声")
	if ui_controls.has("voice_ref_desc"): voice["reference_desc"] = ui_controls["voice_ref_desc"].text.strip_edges()
	if ui_controls.has("voice_tts_role"):
		var opt_tts = ui_controls["voice_tts_role"] as OptionButton
		var sel_meta = opt_tts.get_item_metadata(opt_tts.selected)
		voice["recommended_tts_role"] = sel_meta if sel_meta else "zh-CN-YunjianNeural"

func _refresh_preview() -> void:
	var assembled = CharacterSheetMgr.assemble_prompts(current_sheet)
	var three_view = CharacterSheetMgr.assemble_three_view_prompt(current_sheet)
	if txt_preview_base_prompt:
		txt_preview_base_prompt.text = assembled.get("base_prompt", "")
	if txt_preview_three_view_prompt:
		txt_preview_three_view_prompt.text = three_view
	if txt_preview_negative_prompt:
		txt_preview_negative_prompt.text = assembled.get("negative_prompt", "")
	if txt_preview_voice_desc:
		txt_preview_voice_desc.text = assembled.get("voice_description", "")
	if txt_preview_voice_role:
		txt_preview_voice_role.text = assembled.get("recommended_tts_role", "")
	if lbl_assemble_stats:
		lbl_assemble_stats.text = "✅ 属性表已就绪：包含演播立绘 Prompt、全身三视图 Prompt、刚性逆龄防老负向约束与 %d 项差分！" % assembled.get("sprites", []).size()

func _on_confirm_apply() -> void:
	_save_ui_to_sheet()
	var assembled = CharacterSheetMgr.assemble_prompts(current_sheet)

	character_ent["character_sheet"] = current_sheet.duplicate(true)
	character_ent["base_prompt"] = assembled.get("base_prompt", "")
	character_ent["prompt"] = assembled.get("base_prompt", "")
	character_ent["negative_prompt"] = assembled.get("negative_prompt", "")
	character_ent["voice_role"] = assembled.get("recommended_tts_role", "")
	character_ent["voice"] = assembled.get("recommended_tts_role", "")

	var three_view_p = CharacterSheetMgr.assemble_three_view_prompt(current_sheet)
	var three_view_neg = CharacterSheetMgr.get_three_view_negative_prompt(current_sheet)
	if character_ent.get("turnaround") is Dictionary:
		character_ent["turnaround"]["prompt"] = three_view_p
		character_ent["turnaround"]["negative_prompt"] = three_view_neg

	var existing_sprites: Array = character_ent.get("sprites", [])
	var existing_map: Dictionary = {}
	for sp in existing_sprites:
		existing_map[sp.get("expression", "")] = sp

	var updated_sprites: Array = []
	var pdir = "res://"
	var pctx = get_node_or_null("/root/ProjectContext")
	if pctx and "active_project_dir" in pctx and not str(pctx.active_project_dir).is_empty():
		pdir = pctx.active_project_dir

	for new_sp in assembled.get("sprites", []):
		var expr_id = new_sp.get("expression", "")
		if existing_map.has(expr_id):
			var merged = existing_map[expr_id].duplicate(true)
			merged["prompt"] = new_sp.get("prompt", "")
			merged["negative_prompt"] = new_sp.get("negative_prompt", "")
			merged["qwen_diff_prompt"] = new_sp.get("qwen_diff_prompt", "")
			updated_sprites.append(merged)
		else:
			var target_path = pdir + "assets/images/characters/%s_%s.png" % [character_id, expr_id]
			new_sp["path"] = target_path
			new_sp["local_path"] = target_path
			updated_sprites.append(new_sp)

	character_ent["sprites"] = updated_sprites

	var dm = get_node_or_null("/root/DataManager")
	if dm and "characters" in dm and dm.characters.has(character_id):
		dm.characters[character_id] = character_ent
	if pctx and "active_project_data" in pctx and pctx.active_project_data.has("characters"):
		pctx.active_project_data["characters"][character_id] = character_ent

	sheet_applied.emit(character_id, assembled)
	print("[CharacterSheetDialog] ✅ 角色属性表选择装配完成！")
