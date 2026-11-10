# editor/core/character_sheet_manager.gd
# 角色属性表核心管理器：工业化管理「人设 → AI立绘 → 表情差分 → 配音声线」四维属性，并提供一键拼装与声线映射
class_name CharacterSheetManager
extends RefCounted

const RIGID_ANTI_AGING_NEGATIVE = "衰老，褶皱，老年，苍老，成熟脸，法令纹，笑纹，眼袋，鱼尾纹，深纹，粗糙皮肤毛孔，下垂皮肤，丑陋，年迈，衰老松弛"
const GENERAL_NEGATIVE = "低质量，最差画质，模糊，粗糙，严重变形，多余肢体，多余手指，残缺肢体，画错的手脚，文字，水印，签名，作者名，字幕，对话框，标签"

# --- 标准枚举选项字典 (用于 UI 下拉框与结构化选择表) ---
const ENUM_OPTIONS = {
	"gender": ["男", "女", "中性", "非二元"],
	"species": ["人类", "精灵", "兽人", "机械体", "混血", "神裔", "恶魔"],
	"faction": ["正义秩序", "灰色中立", "混乱邪恶", "反叛阵营", "独立事务所"],
	"social_status": ["平民精英", "底层平民", "统治阶级", "边缘流浪者", "地下街暗网"],
	"height": ["182cm", "185cm", "180cm", "175cm", "170cm", "165cm", "160cm", "155cm"],
	"body_type": ["匀称偏清瘦", "瘦削", "健壮", "丰满", "肌肉型", "纸片型"],
	"skeleton": ["宽肩窄腰，长腿", "大骨架，宽肩", "小骨架，纤细", "长腿匀称", "窄肩匀称"],
	"head_body_ratio": ["7头身", "6头身 (少年感)", "5头身 (少女/幼态)", "2头身 (Q版萌系)", "8头身 (写实比例)"],
	"face_shape": ["削瘦英朗尖脸", "清秀瓜子脸", "鹅蛋脸", "圆脸", "方正硬朗脸", "长脸"],
	"eye_shape": ["狭长丹凤眼", "锐利下垂眼", "灵动杏眼", "上挑猫眼", "半垂死鱼眼", "深邃欧式眼"],
	"eye_color": ["冰灰深蓝", "深黑曜石", "琥珀金黄", "赤红血瞳", "翡翠冷绿", "紫罗兰", "异色双瞳"],
	"hair_style": ["偏分微凌乱碎短发，额前细碎刘海", "利落大背头", "及腰微卷长发", "高马尾", "双马尾", "短寸头", "遮眼碎刘海", "呆毛短发"],
	"hair_color": ["深黑", "银白", "金黄", "深邃墨蓝", "茶褐棕色", "赤红", "浅粉樱色"],
	"skin_tone": ["冷白无暇平滑肌肤", "健康暖白", "小麦健康色", "病态苍白透明感", "深色古铜"],
	"special_features": ["面颊平滑无胡茬，无皱纹，保持年轻美型", "异色双瞳", "眼角泪痣", "左臂机械义肢", "微小耳后旧伤", "兽耳特征", "无特殊体征"],
	"signature_item": ["深驼色大翻领经典双排扣风衣 + 暗红细领带", "黑色皮衣机车夹克", "战术眼罩", "破旧红围巾", "金丝半框眼镜", "修身西装马甲", "兜帽风衣"],
	"vibe_type": ["冷酷沉稳", "硬汉", "温柔治愈", "元气阳光", "慵懒随性", "腹黑", "病娇", "高贵冷艳", "痞气不羁", "呆萌可爱"],
	"age_presentation": ["成熟从容，但骨相与皮肤严格锁定青年美型感（杜绝老化）", "幼态萌系", "清爽少女感", "意气风发少年感", "沉稳成熟感", "饱经风霜沧桑感"],
	"style_preference": ["日系二次元商业AVG插画风格", "日系动漫画风", "半写实商业CG", "中式国风水墨", "美式卡通", "赛博朋克厚涂"],
	"default_emotion": ["从容冷静，专注洞察", "平静微冷", "自信微笑", "淡漠警惕", "通宵倦意"],
	"outfit_style": ["英伦侦探风正装与便服混搭", "现代日常便服", "学院制服", "华丽宴会礼服", "战术战斗机能服", "传统古风长袍"],
	"color_scheme": ["深驼色(60%)为主，藏青炭黑(30%)为辅，暗红细领带与白衬衫(10%)点缀", "纯黑(60%)+深灰(30%)+白(10%)", "藏青(60%)+浅灰(30%)+金(10%)", "米白(60%)+暖棕(30%)+红(10%)"],
	"material_texture": ["厚重毛呢与挺括棉质质感，丝质微反光", "机车皮革与金属光泽", "柔顺丝绸与轻纱", "复合战术织物材质"],
	"pitch_range": ["中低音", "低音", "中音", "中高音", "高音"],
	"timbre": ["磁性冷冽青年音", "清亮少年音", "沙哑低沉大叔音", "温润成熟青年音", "冷艳成熟御姐音", "软糯甜美少女音"],
	"speed": ["适中偏慢", "慢", "适中", "快"],
	"tone_baseline": ["沉稳冷静，掌控全场", "轻佻不羁", "温柔治愈", "强势压迫", "慵懒随性", "严谨理性"],
	"accent": ["标准普通话，咬字清晰，句尾微下沉", "地道方言", "文雅古风腔", "冷感机械音", "优雅贵族腔"],
	"emotional_expression": ["内敛平稳，质询时掷地有声", "外放热烈", "起伏跌宕大", "平淡波澜不惊"],
	"view_angle": ["3/4侧", "正面正视", "正侧面", "全景三视图"],
	"composition": ["半身立绘 (Waist-up)", "全身立绘 (Full body)", "胸像特写 (Bust)", "持械立姿"],
	"lighting": ["微冷调环境光 + 侧面轮廓光", "顶光微光", "戏剧性侧光", "电影感逆光", "均匀柔和室内光"],
	"aspect_ratio": ["2:3 (512x768)", "3:4 (768x1024)", "9:16 (720x1280)", "16:9 (1024x576)"]
}

# --- 1. 创建标准空表 / 默认模板 ---
static func create_default_sheet(char_name: String = "新角色", gender: String = "男", age: int = 24) -> Dictionary:
	if char_name.contains("温寻") or char_name.contains("画家") or char_name.contains("学徒"):
		return {
			"identity": {
				"name": char_name,
				"title": "死者生前学徒",
				"age": age,
				"gender": gender,
				"species": "人类",
				"occupation": "青年画家 / 画廊学徒",
				"faction": "案发现场当事人",
				"social_status": "平民艺术生",
				"one_line_summary": "[看似内向怯懦]的[画廊学徒]，其实是[背负作品被盗执念的天才画家]",
				"three_core_words": "敏 · 执 · 郁"
			},
			"appearance": {
				"height": "155cm",
				"body_type": "娇小匀称偏清瘦",
				"skeleton": "娇小偏瘦骨架",
				"head_body_ratio": "6.5头身",
				"face_shape": "方正硬朗脸",
				"eye_shape": "微下垂杏眼，眼神微怯但藏有锐气",
				"eye_color": "琥珀浅褐",
				"features_brow_nose_lip": "微蹙平眉，秀挺鼻梁，略带局促的薄唇",
				"hair_style": "蓬松微乱的艺术家短卷发，散落额前额发",
				"hair_color": "深栗焦糖棕",
				"skin_tone": "健康白皙平滑肌肤",
				"special_features": "面颊极致平滑无胡茬（严禁老气），指节微有油彩干涸印记，少年感脸型",
				"signature_item": "沾有各色油彩的画师围裙，腕部缠绕棉质保护绷带"
			},
			"vibe": {
				"vibe_type": "神经质敏感",
				"age_presentation": "青涩少年的稚气与画家执念，平滑年轻脸型（严禁老化）",
				"style_preference": "日系二次元商业AVG插画风格",
				"default_emotion": "略带局促不安，眼神微闪躲"
			},
			"outfit": {
				"outfit_style": "画室艺术生复古常服",
				"color_scheme": "米白宽松亚麻衬衫(50%)，深墨绿针织开衫背心(30%)，深咖色工装宽松长裤，零星油彩痕迹(20%)",
				"material_texture": "柔软棉麻与粗针织羊毛质感，沾染微量干涸油彩",
				"accessories": "颈间松散系带棉质小围巾，铜质调色刀挂饰",
				"weapon_props": "便携木质画板与油画调色刀"
			},
			"personality": {
				"keywords": "神经质敏感，内向压抑，艺术偏执，心虚闪躲",
				"habitual_action": "神经质地轻搓沾有干涸颜料的手指，视线游移避开对视",
				"background_story": "多年心血画作被死者占为己有并署名拍卖，在雨夜潜入画室试图夺回画作，却卷入密室毒杀案件。",
				"contrast_setting": "面对质询时畏畏缩缩，一旦谈及色彩与绘画却眼神炽烈、近乎偏执。",
				"catchphrase": "画笔下的色彩从来不会说谎……说谎的只有窃夺者。"
			},
			"expression_sheet": get_default_expression_list(),
			"voice": {
				"pitch_range": "中音",
				"timbre": "少年感微沙青年音",
				"speed": "适中偏快",
				"tone_baseline": "略带局促不安，情绪激动时声音拔高微颤",
				"accent": "标准普通话，语尾略带急促",
				"emotional_expression": "压抑心虚，质询辩解时激烈反弹",
				"reference_desc": "24岁略带神经质与艺术执念的青年男声，情绪易波动，声线少年感清瘦。",
				"quotes_sample": "口说无凭！门是从里面插上的，就算毒发身亡，我又是怎么隔空把铁门插销锁死的？！",
				"recommended_tts_role": "zh-CN-YunxiNeural"
			},
			"spec": {
				"view_angle": "3/4侧",
				"composition": "半身立绘 (Waist-up)",
				"lighting": "微冷调环境光 + 侧面轮廓光",
				"aspect_ratio": "2:3 (512x768)",
				"negative_prompt": RIGID_ANTI_AGING_NEGATIVE + "，" + GENERAL_NEGATIVE + "，眼镜，镜片，镜框，墨镜"
			}
		}

	return {
		"identity": {
			"name": char_name,
			"title": "称号/代号",
			"age": age,
			"gender": gender,
			"species": "人类",
			"occupation": "调查员",
			"faction": "正义秩序",
			"social_status": "平民精英",
			"one_line_summary": "[外表冷峻]的[调查员]，其实[极度护短且内心温柔]",
			"three_core_words": "冷 · 锐 · 敏"
		},
		"appearance": {
			"height": "180cm",
			"body_type": "匀称偏清瘦",
			"skeleton": "宽肩窄腰，长腿",
			"head_body_ratio": "7头身",
			"face_shape": "削瘦英朗尖脸",
			"eye_shape": "狭长丹凤眼",
			"eye_color": "冰灰深蓝",
			"features_brow_nose_lip": "剑眉，高挺鼻梁，薄唇微抿",
			"hair_style": "偏分微凌乱碎短发，额前细碎刘海",
			"hair_color": "深黑",
			"skin_tone": "冷白无暇平滑肌肤",
			"special_features": "面颊平滑无胡茬，无皱纹，保持年轻美型",
			"signature_item": "深驼色大翻领双排扣风衣 + 暗红细领带"
		},
		"vibe": {
			"vibe_type": "冷酷沉稳",
			"age_presentation": "成熟从容，但骨相与皮肤严格锁定青年美型感（杜绝老化）",
			"style_preference": "日系二次元商业AVG插画风格",
			"default_emotion": "从容冷静，专注洞察"
		},
		"outfit": {
			"outfit_style": "英伦侦探风正装与便服混搭",
			"color_scheme": "深驼色(60%)为主，藏青炭黑(30%)为辅，暗红细领带与白衬衫(10%)点缀",
			"material_texture": "厚重毛呢与挺括棉质质感",
			"accessories": "暗银色袖口扣饰",
			"weapon_props": "侦探手册与便携放大镜"
		},
		"personality": {
			"keywords": "外冷内热，逻辑洁癖，敏锐毒舌",
			"habitual_action": "单手插风衣口袋，轻触下颌沉思",
			"background_story": "背负未解之谜重返案发现场，追求无可辩驳的物理铁证。",
			"contrast_setting": "外表是不苟言笑的冷面侦探，私下却极度嗜甜且畏寒。",
			"catchphrase": "真相从来不会因为谎言动听而改变形状。"
		},
		"expression_sheet": get_default_expression_list(),
		"voice": {
			"pitch_range": "中低音",
			"timbre": "磁性冷冽青年音",
			"speed": "适中偏慢",
			"tone_baseline": "沉稳冷静，掌控全场",
			"accent": "标准普通话，咬字清晰，句尾微下沉",
			"emotional_expression": "内敛平稳，质询时掷地有声",
			"reference_desc": "25岁清冷磁性的青年男声，低沉富有穿透力，条理分明不疾不徐。",
			"quotes_sample": "你的不在场证明，从一开始就存在致命的时间差。",
			"recommended_tts_role": "zh-CN-YunjianNeural"
		},
		"spec": {
			"view_angle": "3/4侧",
			"composition": "半身立绘 (Waist-up)",
			"lighting": "微冷调环境光 + 侧面轮廓光",
			"aspect_ratio": "2:3 (512x768)",
			"negative_prompt": RIGID_ANTI_AGING_NEGATIVE + ", " + GENERAL_NEGATIVE
		}
	}

# --- 2. 默认 6+2 差分清单生成 ---
static func get_default_expression_list() -> Array:
	return [
		{
			"id": "default",
			"name": "平静（基准）",
			"expression": "default",
			"changes": "眼神清澈深邃，剑眉平舒，薄唇微抿",
			"details": "干净侧脸，平滑无暇二次元肤质，从容冷峻",
			"is_custom": false
		},
		{
			"id": "smile",
			"name": "从容浅笑",
			"expression": "smile",
			"changes": "眉眼微舒，嘴角轻微扬起极淡笑意",
			"details": "眼神带着破获真相的笃定从容，气场放松温和",
			"is_custom": false
		},
		{
			"id": "serious",
			"name": "严厉质询",
			"expression": "serious",
			"changes": "剑眉微压，眼神如刀刃般锐利直视前方，双唇平直紧闭",
			"details": "★ 刚性防老约束：绝对禁止法令纹、抬头纹与眼袋，保持 20 岁光滑少年感脸型！",
			"is_custom": false
		},
		{
			"id": "ponder",
			"name": "闭目深思",
			"expression": "ponder",
			"changes": "双眼自然轻阖，睫毛微垂，眉心极微蹙起",
			"details": "手指轻触下颌，沉浸在逻辑推演中，宁静深沉",
			"is_custom": false
		},
		{
			"id": "shocked",
			"name": "震惊错愕",
			"expression": "shocked",
			"changes": "双眸睁大，瞳孔微收，嘴唇微张",
			"details": "意外洞悉关键破绽，神色错愕，额角微渗冷汗",
			"is_custom": false
		},
		{
			"id": "smirk",
			"name": "冷笑嘲讽",
			"expression": "smirk",
			"changes": "眼神微敛带戏谑冷光，单侧嘴角轻扬",
			"details": "看穿凶手拙劣谎言时的压迫气场，胜券在握",
			"is_custom": false
		},
		{
			"id": "tired",
			"name": "疲惫倦意（专属）",
			"expression": "tired",
			"changes": "眼皮半垂，视线微向下，神色淡漠微显疲惫",
			"details": "通宵推理后的专注倦意，眼底微阴影但面颊饱满不凹陷",
			"is_custom": true
		},
		{
			"id": "accuse",
			"name": "指证破谎（专属）",
			"expression": "accuse",
			"changes": "目光凌厉决绝，剑眉英挺怒张，薄唇果断张开指证",
			"details": "戏剧性正义光感，气势压制全场，直指凶手破绽",
			"is_custom": true
		}
	]

# --- 3. 沈策专属标准预设 ---
static func get_shen_ce_preset() -> Dictionary:
	var sheet = create_default_sheet("沈策", "男", 28)
	sheet["identity"]["title"] = "灰烬侦探"
	sheet["identity"]["occupation"] = "私家侦探 / 前刑侦顾问"
	sheet["identity"]["social_status"] = "平民精英"
	sheet["identity"]["one_line_summary"] = "表面冷峻毒舌、不近人情的私家侦探，其实内心极度护短且背负着未破冤案的执念。"
	sheet["identity"]["three_core_words"] = "冷 · 锐 · 敏"
	sheet["appearance"]["height"] = "182cm"
	sheet["appearance"]["body_type"] = "匀称偏清瘦"
	sheet["appearance"]["head_body_ratio"] = "7头身"
	sheet["appearance"]["features_brow_nose_lip"] = "剑眉利落，鼻梁高挺，薄唇微抿"
	sheet["appearance"]["hair_style"] = "黑色偏分微凌乱碎短发，额前有两缕垂落细碎发"
	sheet["appearance"]["signature_item"] = "深驼色大翻领经典双排扣风衣 + 暗红斜纹细领带"
	sheet["appearance"]["special_features"] = "面颊极致平滑无胡茬（严禁老气），右侧耳后有一枚极细小的陈旧划痕"
	sheet["vibe"]["vibe_type"] = "冷酷，沉稳，腹黑"
	sheet["vibe"]["age_presentation"] = "成熟从容气场，但面部骨相与皮肤严格锁定 22 岁美青年感（杜绝老化皱纹）"
	sheet["outfit"]["outfit_style"] = "英伦侦探风正装与便服混搭"
	sheet["outfit"]["color_scheme"] = "深驼色(60%)风衣，藏青炭黑(30%)西装马甲，纯白与暗红(10%)领口点缀"
	sheet["outfit"]["material_texture"] = "厚重毛呢大衣质感，挺括棉质白衬衫，丝质领带微反光"
	sheet["outfit"]["accessories"] = "袖口暗银色金属指南针扣饰"
	sheet["outfit"]["weapon_props"] = "便携式牛皮封套侦探手册与黄铜放大镜"
	sheet["personality"]["contrast_setting"] = "外表是智商碾压全场的冷面名探，私下却极度嗜甜且极度畏寒。"
	sheet["personality"]["catchphrase"] = "谎言的修饰再华丽，在物理规律面前也薄如蝉翼。"
	sheet["voice"]["recommended_tts_role"] = "zh-CN-YunjianNeural"
	sheet["voice"]["reference_desc"] = "25岁清冷磁性的青年男声，低沉富有穿透力，条理清晰，句尾微下沉。"
	return sheet

# --- 4. 一键拼装引擎 (Prompt & Pipeline Assembler) ---
static func get_height_scale_rule(height_str: String) -> String:
	var regex = RegEx.new()
	regex.compile("(\\d{3})\\s*cm")
	var m = regex.search(height_str)
	var h_num = 175
	if m:
		h_num = int(m.get_string(1))
	
	if h_num >= 180:
		return "(高大挺拔身形:1.25), (人物脚底紧贴画面底边基准线:1.3), (头顶逼近画面上方, 顶部仅留8%微小留白:1.2), 180厘米以上身形画框比例"
	elif h_num <= 165:
		return "(娇小低矮身形:1.3), (人物脚底紧贴画面底边基准线:1.3), (头顶保留24%大面积空旷留白:1.3), 160厘米娇小身形画框比例"
	else:
		return "(标准匀称身形:1.1), (人物脚底紧贴画面底边基准线:1.3), (头顶适度留白15%:1.1), 170厘米标准身形画框比例"

static func assemble_prompts(sheet: Dictionary) -> Dictionary:
	var ident = sheet.get("identity", {})
	var app = sheet.get("appearance", {})
	var vibe = sheet.get("vibe", {})
	var outfit = sheet.get("outfit", {})
	var voice = sheet.get("voice", {})
	var spec = sheet.get("spec", {})
	var expr_list = sheet.get("expression_sheet", [])
	
	var c_name = ident.get("name", "角色")
	var gender = ident.get("gender", "男")
	var age = ident.get("age", 24)
	
	# 提取核心参数
	var style = vibe.get("style_preference", "日系二次元商业AVG插画风格")
	var ratio = app.get("head_body_ratio", "7头身")
	var height = app.get("height", "180cm")
	var body_type = app.get("body_type", "匀称")
	var face = app.get("face_shape", "削瘦英朗尖脸")
	var eye = app.get("eye_shape", "狭长丹凤眼")
	var eye_c = app.get("eye_color", "深灰冷瞳")
	var hair = app.get("hair_style", "偏分短发")
	var hair_c = app.get("hair_color", "黑色")
	var skin = app.get("skin_tone", "冷白无暇平滑肌肤")
	var out_style = outfit.get("outfit_style", "便服")
	var c_scheme = outfit.get("color_scheme", "经典配色")
	var texture = outfit.get("material_texture", "挺括质感")
	var sig_item = app.get("signature_item", "")
	var special = app.get("special_features", "")
	var v_type = vibe.get("vibe_type", "冷酷沉稳")
	var def_emo = vibe.get("default_emotion", "从容冷静")
	var v_angle = spec.get("view_angle", "3/4侧")
	var comp = spec.get("composition", "半身立绘")
	var light = spec.get("lighting", "侧逆光")
	var aspect = spec.get("aspect_ratio", "2:3")
	
	# --- 模板拼装 A：生图基准 Prompt (全中文原生支持，世界观身高比例定标) ---
	var scale_rule = get_height_scale_rule(height)
	var p_parts: Array = [
		"(杰作，极高画质:1.2)",
		style,
		ratio,
		"%s%d岁青年角色" % [gender, age],
		"%s%s" % [height, body_type],
		"%s，%s%s" % [face, eye, eye_c],
		"%s%s" % [hair_c, hair],
		skin,
		"穿着%s" % out_style,
		c_scheme,
		texture
	]
	if not sig_item.is_empty():
		p_parts.append("佩戴%s" % sig_item)
	if not special.is_empty():
		p_parts.append(special)
	p_parts.append("%s气质" % v_type)
	p_parts.append("%s默认神情" % def_emo)
	p_parts.append("%s%s" % [v_angle, comp])
	p_parts.append(light)
	p_parts.append("%s比例" % aspect)
	if not scale_rule.is_empty():
		p_parts.append(scale_rule)
	p_parts.append("(单人:1.4), (平滑细腻年轻动漫脸:1.3), 纯白背景")
	
	var base_prompt = ", ".join(p_parts)
	
	# --- 模板拼装 B：刚性逆龄通用负向词 (全中文) ---
	var negative_prompt = RIGID_ANTI_AGING_NEGATIVE + "，" + GENERAL_NEGATIVE
	if gender == "男":
		negative_prompt += "，女性，少女，女人"
	elif gender == "女":
		negative_prompt += "，男性，少年，男人，胡子，胡茬"
	
	# --- 模板拼装 C：配音描述与推荐 TTS ---
	var voice_role = voice.get("recommended_tts_role", "")
	if voice_role.is_empty():
		voice_role = resolve_tts_voice(sheet)
	
	var v_desc = "%s%s，语速%s，语气%s，%s，情绪表达%s。参考：%s" % [
		voice.get("pitch_range", "中低音"),
		voice.get("timbre", "磁性青年音"),
		voice.get("speed", "适中"),
		voice.get("tone_baseline", "沉稳"),
		voice.get("accent", "标准普通话"),
		voice.get("emotional_expression", "内敛平稳"),
		voice.get("reference_desc", "清冷沉稳青年男声")
	]
	
	# --- 模板拼装 D：6+2 差分任务项与指令微表情 Prompt (全中文原生指令) ---
	var has_glasses = sig_item.contains("眼镜") or special.contains("眼镜") or str(ident.get("id", "")).contains("shen_ce") or str(ident.get("name", "")).contains("沈策")
	var accessory_rule = "严格保持原图眼镜、服装与发型一致" if has_glasses else "严格保持原图服装与发型完全一致，脸上绝对不戴眼镜，无眼镜，无镜片，无镜框"

	var assembled_sprites: Array = []
	for expr in expr_list:
		var eid = expr.get("id", "sprite")
		var ename = expr.get("name", "差分")
		var changes = expr.get("changes", "")
		var details = expr.get("details", "")
		
		# 指令级微表情 Prompt (Qwen-Image / Nunchaku 专用：全中文自然语言，动态角色名与饰品隔离)
		var qwen_cmd = "将图1中角色的面部表情修改为：%s。%s。重点调整眉毛、眼神与嘴角微表情，神态自然生动；严格保持%s原本的年轻动漫脸型与细腻平滑肌肤，绝对禁止衰老褶皱、法令纹与眼袋；保持机位镜头、半身构图、动作姿态与发型服装完全一致，%s。" % [
			changes, details, c_name, accessory_rule
		]
		
		var sprite_neg = RIGID_ANTI_AGING_NEGATIVE + "，" + GENERAL_NEGATIVE
		if not has_glasses:
			sprite_neg += "，眼镜，镜片，镜框，墨镜，太阳镜，单片镜，圆眼镜"
		
		assembled_sprites.append({
			"id": "char_%s_%s" % [ident.get("name", "char"), eid],
			"expression": eid,
			"name": "%s·%s" % [c_name, ename],
			"prompt": "%s，%s" % [changes, details],
			"qwen_diff_prompt": qwen_cmd,
			"negative_prompt": sprite_neg,
			"is_custom": expr.get("is_custom", false)
		})
	
	return {
		"base_prompt": base_prompt,
		"negative_prompt": negative_prompt,
		"voice_description": v_desc,
		"recommended_tts_role": voice_role,
		"tts_options": {
			"pitch": "-2Hz" if voice.get("pitch_range", "").contains("低") else "0Hz",
			"rate": "-5%" if voice.get("speed", "").contains("慢") else "0%"
		},
		"sprites": assembled_sprites
	}

# --- 5. 智能配音声线匹配器 ---
static func resolve_tts_voice(sheet: Dictionary) -> String:
	var ident = sheet.get("identity", {})
	var voice = sheet.get("voice", {})
	var gender = ident.get("gender", "男")
	var pitch = voice.get("pitch_range", "中音")
	var timbre = voice.get("timbre", "清亮")
	
	if gender == "男":
		if pitch.contains("低") or timbre.contains("磁性") or timbre.contains("冷冽"):
			return "zh-CN-YunjianNeural" # 沉稳、冷峻、磁性男声
		elif timbre.contains("少年") or timbre.contains("清亮"):
			return "zh-CN-YunxiNeural" # 阳光、清澈少年男声
		else:
			return "zh-CN-YunyangNeural" # 严谨播音/成熟男声
	else:
		if timbre.contains("御姐") or timbre.contains("冷") or pitch.contains("低"):
			return "zh-CN-XiaohanNeural" # 冷冽御姐音
		elif timbre.contains("软糯") or timbre.contains("萝莉") or pitch.contains("高"):
			return "zh-CN-XiaoyiNeural" # 软萌甜美
		else:
			return "zh-CN-XiaoxiaoNeural" # 温暖亲切、标准女主音

# --- 6. 全身三视图 Prompt 拼装器 (Character Turnaround Sheet) ---
const TURNAROUND_NEGATIVE = "透视角度冲突，头部身体朝向不一，多余手臂，多余腿，多余躯体，低质量，最差画质，模糊，衰老褶皱，法令纹，眼袋，粗糙毛孔，复杂背景，文字，水印，对话框"

static func get_three_view_negative_prompt(sheet: Dictionary = {}, view_type: String = "") -> String:
	var gender = sheet.get("identity", {}).get("gender", "男")
	var neg = RIGID_ANTI_AGING_NEGATIVE + "，" + GENERAL_NEGATIVE + "，" + TURNAROUND_NEGATIVE
	if gender == "男":
		neg += "，女性，少女，女人"
	elif gender == "女":
		neg += "，男性，少年，男人，胡子，胡茬"
	
	if view_type == "back":
		neg += "，(正面:1.7)，(半侧面:1.6)，(侧面:1.6)，(回头:1.7)，(回眸:1.7)，(扭头:1.6)，(露出面部:1.7)，(正脸:1.7)，(侧脸:1.6)，眼睛，瞳孔，眉毛，鼻子，嘴巴，嘴唇，前襟领带，胸口，胸部，正面视角，侧视，facing camera, looking back, looking at viewer, profile, side view, 3/4 view, turn around, looking over shoulder, face visible, visible face"
	elif view_type == "side":
		neg += "，(正脸直视:1.5)，(完全正视:1.4)，(完全背面:1.4)，front view, facing camera, back view"
	return neg

static func assemble_three_view_prompt(sheet: Dictionary) -> String:
	var ident = sheet.get("identity", {})
	var app = sheet.get("appearance", {})
	var outfit = sheet.get("outfit", {})
	var vibe = sheet.get("vibe", {})
	
	var gender = ident.get("gender", "男")
	var gender_zh = "单人青年男性" if gender == "男" else "单人青年女性"
	var height = app.get("height", "180cm")
	var scale_rule = get_height_scale_rule(height)
	
	var parts: Array = [
		"(杰作，极高画质:1.3)",
		vibe.get("style_preference", "日系二次元商业AVG插画风格"),
		"全景角色三视图概念母本，(正面视图，90度正侧面视图，正背面视图)",
		"全身立绘，笔直站立姿态，从容安定构图",
		gender_zh,
		"%s%d岁青年角色" % [gender, ident.get("age", 24)],
		"%s，%s，%s" % [app.get("head_body_ratio", "7头身"), height, app.get("body_type", "匀称偏清瘦")],
		"%s%s，%s" % [app.get("hair_color", "深黑"), app.get("hair_style", "短发"), app.get("face_shape", "尖脸")],
		"穿着%s" % outfit.get("outfit_style", "便服"),
		outfit.get("color_scheme", ""),
		app.get("signature_item", ""),
		"(平滑细腻年轻动漫脸:1.3)，无瑕动漫平滑肌肤",
		scale_rule,
		"精致细腻二次元CG，通透光影与立体轮廓，纯白背景"
	]
	var clean_parts: Array = []
	for p in parts:
		if not str(p).is_empty():
			clean_parts.append(str(p).strip_edges())
	return "，".join(clean_parts)

# --- 7. 单张高精分视图 Prompt 拼装器 (正面/侧面/背面 单张 512x768 原生商业AVG插画) ---
static func assemble_view_prompt(sheet: Dictionary, view_type: String = "front") -> String:
	var ident = sheet.get("identity", {})
	var app = sheet.get("appearance", {})
	var outfit = sheet.get("outfit", {})
	var vibe = sheet.get("vibe", {})
	
	var gender = ident.get("gender", "男")
	var gender_zh = "单人青年男性" if gender == "男" else "单人青年女性"
	var height = app.get("height", "180cm")
	var scale_rule = get_height_scale_rule(height)
	var c_style = vibe.get("style_preference", "日系二次元商业AVG插画风格")
	
	var view_desc = "((单人正面立绘:1.6)), (完全正面直视视角:1.5), 笔直站姿，从容直视前方，正面五官与服饰细节完整展现"
	var view_focus = "正面五官神态与服饰前襟细节"
	if view_type == "side":
		view_desc = "((90度纯正侧面立绘:1.6)), (严格正侧视90度视角:1.5), (纯侧身站立姿态:1.4), 清秀侧颜线条，从容平视视线，严禁斜视或面向镜头"
		view_focus = "侧脸骨骼鼻梁线条与服装侧面层次"
	elif view_type == "back":
		view_desc = "((180度纯正背面立绘:1.6)), (完全正后方观察视角:1.5), (背对镜头笔直站立姿态:1.5), 严格保持180度正背面站立, 严禁回头, 严禁侧身, 严禁扭头, 严禁露出正脸或侧脸, 严禁露出五官, 只能看到后脑勺发流、颈后与后背服饰全貌, ((from behind:1.6)), ((back view:1.6)), ((facing away:1.5)), strict rear view, head facing away, back of head"
		view_focus = "后背服饰完整层次与后摆全貌，背部脊线轮廓，后发完整层次"
	
	var parts: Array = [
		"(杰作，极高画质:1.3)",
		c_style,
		view_desc,
		gender_zh,
		"%s%d岁青年角色" % [gender, ident.get("age", 24)],
		"%s，%s，%s" % [app.get("head_body_ratio", "7头身"), height, app.get("body_type", "匀称偏清瘦")],
		"%s%s" % [app.get("hair_color", "深黑"), app.get("hair_style", "短发")],
		app.get("face_shape", "尖脸") if view_type != "back" else "后发完整轮廓",
		"穿着%s" % outfit.get("outfit_style", "便服"),
		outfit.get("color_scheme", ""),
		app.get("signature_item", ""),
		view_focus,
		"(平滑细腻年轻动漫脸:1.3)，无瑕动漫平滑肌肤" if view_type != "back" else "平滑颈项线条",
		scale_rule,
		"精致细腻二次元CG，通透光影与立体轮廓，纯白背景"
	]
	var clean_parts: Array = []
	for p in parts:
		if not str(p).is_empty():
			clean_parts.append(str(p).strip_edges())
	return "，".join(clean_parts)
