import os
import sys
import json

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

PROJECT_DIR = os.path.join(os.path.dirname(__file__), "..", "projects", "case_gallery_rain")
ASSETS_DIR = os.path.join(PROJECT_DIR, "assets")
IMG_BG_DIR = os.path.join(ASSETS_DIR, "images", "backgrounds")
IMG_CHAR_DIR = os.path.join(ASSETS_DIR, "images", "characters")
IMG_CLUE_DIR = os.path.join(ASSETS_DIR, "images", "clues")
AUDIO_VOICE_DIR = os.path.join(ASSETS_DIR, "audio", "voice")
AUDIO_BGM_DIR = os.path.join(ASSETS_DIR, "audio", "bgm")

for d in [IMG_BG_DIR, IMG_CHAR_DIR, IMG_CLUE_DIR, AUDIO_VOICE_DIR, AUDIO_BGM_DIR]:
    os.makedirs(d, exist_ok=True)

project_data = {
    "meta": {
        "project_id": "case_gallery_rain",
        "game_title": "雨夜画廊的最后调色",
        "author": "MagicStar Studio",
        "version": "1.0.0",
        "description": "暴雨深夜，封闭的私人画室中知名收藏家离奇暴毙。面对无足迹的画廊与反锁的铁栓，侦探沈策如何击碎嫌疑人温寻的完美不在场证明？",
        "style_preset": "anime visual novel",
        "cover_image": "res://projects/case_gallery_rain/assets/images/backgrounds/bg_scene_studio_crime.png"
    },
    "flow_config": {
        "start_node": "node_01_intro",
        "phases": {
            "phase_1": {
                "name": "案发现场搜证",
                "nodes": ["node_01_intro", "node_02_explore"]
            },
            "phase_2": {
                "name": "质询破谎与结案",
                "nodes": ["node_03_confrontation", "node_04_ending_truth", "node_05_ending_false"]
            }
        }
    },
    "game_config": {
        "game_title": "雨夜画廊的最后调色",
        "protagonist_name": "沈策",
        "version": "1.0.0"
    },
    "ai_settings": {
        "comfyui_server": "https://63zf182nv122.vicp.fun:8188",
        "comfyui_user": "dkzl_ubuntu",
        "comfyui_password": "Jyzn2331",
        "checkpoint": "sd_xl_turbo_1.0.safetensors",
        "global_style_prompt": "masterpiece, best quality, anime visual novel, dark mystery, rainy night, dramatic lighting",
        "global_negative_prompt": "worst quality, low quality, blurry, text, watermark, bad anatomy, deformed limbs",
        "character_base_prompt": "solo, waist-up portrait, standing pose, white background",
        "bg_base_prompt": "scenery, background, interior architecture, highly detailed, no humans",
        "tts_voice_default": "zh-CN-YunxiNeural"
    },
    "characters": {
        "char_shen_ce": {
            "id": "char_shen_ce",
            "name": "沈策",
            "identity": "资深私家侦探",
            "age": 36,
            "voice": "zh-CN-YunjianNeural",
            "prompt": "Chinese detective Shen Ce, 36 years old, dark trench coat, deep sharp eyes, slight stubble, holding a pipe, calm analytical expression, waist-up portrait, standing pose, white background",
            "negative_prompt": "(background:1.3), complex background, extra limbs, bad hands",
            "size": [512, 768]
        },
        "char_wen_xun": {
            "id": "char_wen_xun",
            "name": "温寻",
            "identity": "青年天才画家 / 死者学徒",
            "age": 24,
            "voice": "zh-CN-YunxiNeural",
            "prompt": "Chinese young male painter Wen Xun, 24 years old, short messy dark hair, paint-stained beige artist apron, nervously gripping paintbrush, anxious and defensive expression, waist-up portrait, standing pose, white background",
            "negative_prompt": "(background:1.3), complex background, extra limbs, bad hands",
            "size": [512, 768]
        }
    },
    "scenes": {
        "scene_studio_crime": {
            "id": "scene_studio_crime",
            "name": "案发画室密室",
            "description": "二楼私人密闭画室，大雨敲击着玻璃窗，厚重木门由铁栓从内反锁。",
            "background": "res://projects/case_gallery_rain/assets/images/backgrounds/bg_scene_studio_crime.png",
            "bgm": "res://projects/case_gallery_rain/assets/audio/bgm/bgm_investigation.mp3",
            "explore_points": [
                {
                    "id": "exp_desk_wine",
                    "name": "书桌与毒红酒",
                    "rect": [0.15, 0.45, 0.22, 0.35],
                    "hint": "桌上放着半杯散发苦杏仁味的热红酒与一块未融化的特殊残渣。",
                    "trigger": {
                        "action": "clue",
                        "target": "clue_sugar_sculpture"
                    }
                },
                {
                    "id": "exp_easel_cord",
                    "name": "中央画架与钓线",
                    "rect": [0.42, 0.30, 0.22, 0.45],
                    "hint": "画架顶部绷着坚韧的透明细线，线头残留着未干的群青油彩。",
                    "trigger": {
                        "action": "clue",
                        "target": "clue_ultramarine_thread"
                    }
                },
                {
                    "id": "exp_door_bolt",
                    "name": "反锁的门栓铁轨",
                    "rect": [0.72, 0.35, 0.20, 0.45],
                    "hint": "沉重铁栓卡在锁扣里，滑轨缝隙处凝固着一枚红色的计时火漆印章。",
                    "trigger": {
                        "action": "clue",
                        "target": "clue_wax_seal"
                    }
                }
            ]
        },
        "scene_gallery_hall": {
            "id": "scene_gallery_hall",
            "name": "美术馆二楼回廊",
            "description": "幽静幽暗的美术馆长廊，两壁挂满古典油画，窗外电闪雷鸣。",
            "background": "res://projects/case_gallery_rain/assets/images/backgrounds/bg_scene_gallery_hall.png",
            "bgm": "res://projects/case_gallery_rain/assets/audio/bgm/bgm_tension.mp3",
            "explore_points": []
        }
    },
    "clues": {
        "clue_sugar_sculpture": {
            "id": "clue_sugar_sculpture",
            "name": "半融的画糖雕塑",
            "type": "item",
            "description": "在热红酒杯底提取的糖制残渣。原本用于包裹毒物胶囊，温水溶解需恰好30分钟。",
            "image": "res://projects/case_gallery_rain/assets/images/clues/clue_sugar_sculpture.png",
            "prompt": "half melted sugar candy sculpture on vintage porcelain plate, faint golden glow, macro close-up shot, dramatic lighting, isolated, single object",
            "obtained_at": "scene_studio_crime"
        },
        "clue_ultramarine_thread": {
            "id": "clue_ultramarine_thread",
            "name": "沾染群青油彩的细线",
            "type": "item",
            "description": "高强度透明尼龙细线，末端沾有温寻调色盘独有的自制群青油彩，有穿过门下缝隙的摩擦压痕。",
            "image": "res://projects/case_gallery_rain/assets/images/clues/clue_ultramarine_thread.png",
            "prompt": "thin nylon fishing thread stained with ultramarine blue oil paint, coiled on dark velvet cloth, macro close-up shot, dramatic lighting, isolated",
            "obtained_at": "scene_studio_crime"
        },
        "clue_wax_seal": {
            "id": "clue_wax_seal",
            "name": "倒计时火漆印",
            "type": "item",
            "description": "门栓导轨下熔铸的红色火漆块。冷却前利用重锤与引线将插销落下，造成从内反锁的假象。",
            "image": "res://projects/case_gallery_rain/assets/images/clues/clue_wax_seal.png",
            "prompt": "red wax seal stamp on metallic iron bolt rail, dripping wax texture, macro close-up shot, dramatic lighting, isolated, single object",
            "obtained_at": "scene_studio_crime"
        }
    },
    "nodes": {
        "node_01_intro": {
            "id": "node_01_intro",
            "type": "story",
            "title": "画室惨剧",
            "scene": "scene_studio_crime",
            "dialogue": "dlg_intro",
            "next": "node_02_explore"
        },
        "node_02_explore": {
            "id": "node_02_explore",
            "type": "explore",
            "title": "现场搜查",
            "scene": "scene_studio_crime",
            "next": "node_03_confrontation"
        },
        "node_03_confrontation": {
            "id": "node_03_confrontation",
            "type": "reasoning",
            "title": "破谎质询",
            "scene": "scene_gallery_hall",
            "reasoning": "reason_murder_trick",
            "next_on_success": "node_04_ending_truth",
            "next_on_fail": "node_05_ending_false"
        },
        "node_04_ending_truth": {
            "id": "node_04_ending_truth",
            "type": "ending",
            "title": "真结局：雨过天晴",
            "scene": "scene_gallery_hall",
            "dialogue": "dlg_ending_truth",
            "ending": "ending_truth"
        },
        "node_05_ending_false": {
            "id": "node_05_ending_false",
            "type": "ending",
            "title": "假结局：迷雾迷局",
            "scene": "scene_gallery_hall",
            "dialogue": "dlg_ending_false",
            "ending": "ending_false"
        }
    },
    "dialogues": {
        "dlg_intro": {
            "id": "dlg_intro",
            "lines": [
                {
                    "speaker": "旁白",
                    "text": "暴雨倾盆的午夜，美术馆顶层的铁门被强行破开，收藏家陆伯言倒在画架旁，瞳孔已经扩散。",
                    "expression": "normal"
                },
                {
                    "speaker": "沈策",
                    "text": "门窗皆反锁，窗外毫无攀爬脚印。温寻，身为今晚唯一的陪同者，你有什么想说的？",
                    "character_image": "res://projects/case_gallery_rain/assets/images/characters/char_shen_ce.png",
                    "expression": "confident"
                },
                {
                    "speaker": "温寻",
                    "text": "沈侦探！我八点就离开画室下楼煮夜宵了，离开时老师亲手把门反锁，我绝不可能下毒！",
                    "character_image": "res://projects/case_gallery_rain/assets/images/characters/char_wen_xun.png",
                    "expression": "nervous"
                },
                {
                    "speaker": "沈策",
                    "text": "是不是谎言，画室里的物证会告诉我答案。仔细搜查每一个角落吧。",
                    "character_image": "res://projects/case_gallery_rain/assets/images/characters/char_shen_ce.png",
                    "expression": "normal"
                }
            ]
        },
        "dlg_confrontation": {
            "id": "dlg_confrontation",
            "lines": [
                {
                    "speaker": "沈策",
                    "text": "温寻，你的‘下楼不在场证明’从一开始就是用这间画室为你布置的障眼法！",
                    "character_image": "res://projects/case_gallery_rain/assets/images/characters/char_shen_ce.png",
                    "expression": "confident"
                },
                {
                    "speaker": "温寻",
                    "text": "口说无凭！门是从里面插上的，就算毒发身亡，我又是怎么隔空把铁门插销锁死的？！",
                    "character_image": "res://projects/case_gallery_rain/assets/images/characters/char_wen_xun.png",
                    "expression": "angry"
                }
            ]
        },
        "dlg_ending_truth": {
            "id": "dlg_ending_truth",
            "lines": [
                {
                    "speaker": "沈策",
                    "text": "沾着群青油彩的细线穿过门缝，火漆冷却后重锤落下——你以为带走了细线，但门轴上的蜡印早就出卖了一切。",
                    "character_image": "res://projects/case_gallery_rain/assets/images/characters/char_shen_ce.png",
                    "expression": "confident"
                },
                {
                    "speaker": "温寻",
                    "text": "……他夺走了我所有的画，甚至要在明天的拍卖会上署上他的名字……我只是拿回属于我自己的东西！",
                    "character_image": "res://projects/case_gallery_rain/assets/images/characters/char_wen_xun.png",
                    "expression": "sad"
                },
                {
                    "speaker": "旁白",
                    "text": "警笛在雨夜中划破长空，晨光透过彩绘玻璃射入走廊，画廊的最后调色落下了帷幕。",
                    "expression": "normal"
                }
            ]
        },
        "dlg_ending_false": {
            "id": "dlg_ending_false",
            "lines": [
                {
                    "speaker": "沈策",
                    "text": "或许……真的是死者突发急性疾病自杀封门。证据链不足以立案，暴雨冲淡了所有痕迹。",
                    "character_image": "res://projects/case_gallery_rain/assets/images/characters/char_shen_ce.png",
                    "expression": "sad"
                },
                {
                    "speaker": "温寻",
                    "text": "我就说了我什么都不知道……请容许我先为老师操办后事吧。",
                    "character_image": "res://projects/case_gallery_rain/assets/images/characters/char_wen_xun.png",
                    "expression": "normal"
                },
                {
                    "speaker": "旁白",
                    "text": "暴雨下了一整夜，真正的诡计被尘封在油彩之下，画室的冤魂将永远无声沉睡。",
                    "expression": "normal"
                }
            ]
        }
    },
    "reasonings": {
        "reason_murder_trick": {
            "id": "reason_murder_trick",
            "title": "破解画室反锁密室的手法",
            "question": "凶手究竟利用了哪两样物证，在离开画室后从容将门闩从内反锁并实现延时毒杀？",
            "required_clues": ["clue_ultramarine_thread", "clue_wax_seal"],
            "conclusion": "利用火漆与群青细线组成的重力滑轮机关，在门外关门后抽拉引线令门栓落下，并利用糖雕延时释放毒药！"
        }
    },
    "endings": {
        "ending_truth": {
            "id": "ending_truth",
            "title": "真结局：雨过天晴",
            "type": "true",
            "description": "沈策识破了温寻巧妙的延时密室诡计，群青油彩与火漆印成为无法抵赖的铁证。温寻认罪伏法，天才的贪欲与怨恨最终被晨曦洗净。"
        },
        "ending_false": {
            "id": "ending_false",
            "title": "假结局：迷雾沉沦",
            "type": "false",
            "description": "关键密室手法未能解开，温寻借不在场证明摆脱嫌疑并继承了大量名画。真相被暴雨永久掩埋。"
        }
    },
    "asset_manifest": [
        {
            "id": "bg_scene_studio_crime",
            "type": "background",
            "entity_type": "scene",
            "entity_id": "scene_studio_crime",
            "entity_name": "案发画室密室",
            "sub_type": "background",
            "name": "案发画室密室 背景大图",
            "prompt": "Left zone: wooden mahogany desk with antique poison red wine glass and candle. Center zone: large wooden painter easel, canvas on it, messy palette. Right zone: heavy wooden door with iron bolt rail, circular arched window with heavy storm rain outside. Watercolor anime style, dark mystery, amber warm light and cold blue rain, highly detailed, scenery, no humans",
            "negative_prompt": "(humans, people, character:1.4), text, watermark, blurry",
            "local_path": "res://projects/case_gallery_rain/assets/images/backgrounds/bg_scene_studio_crime.png",
            "width": 1024,
            "height": 576,
            "status": "pending"
        },
        {
            "id": "bg_scene_gallery_hall",
            "type": "background",
            "entity_type": "scene",
            "entity_id": "scene_gallery_hall",
            "entity_name": "美术馆二楼回廊",
            "sub_type": "background",
            "name": "美术馆二楼回廊 背景大图",
            "prompt": "Left zone: rows of classical oil paintings on dark velvet wall. Center zone: long polished marble corridor reflecting dim chandeliers. Right zone: tall stained glass arch windows, lightning storm outside. Watercolor anime style, dark mystery, dramatic lighting, scenery, no humans",
            "negative_prompt": "(humans, people, character:1.4), text, watermark, blurry",
            "local_path": "res://projects/case_gallery_rain/assets/images/backgrounds/bg_scene_gallery_hall.png",
            "width": 1024,
            "height": 576,
            "status": "pending"
        },
        {
            "id": "char_shen_ce",
            "type": "character",
            "entity_type": "character",
            "entity_id": "char_shen_ce",
            "entity_name": "沈策",
            "character_id": "char_shen_ce",
            "sub_type": "sprite",
            "name": "沈策 半身立绘",
            "prompt": "Chinese detective Shen Ce, 36 years old, dark trench coat, deep sharp eyes, slight stubble, holding a pipe, calm analytical expression, waist-up portrait, standing pose, white background",
            "negative_prompt": "(background:1.3), complex background, extra limbs, bad hands",
            "local_path": "res://projects/case_gallery_rain/assets/images/characters/char_shen_ce.png",
            "width": 512,
            "height": 768,
            "status": "pending"
        },
        {
            "id": "char_wen_xun",
            "type": "character",
            "entity_type": "character",
            "entity_id": "char_wen_xun",
            "entity_name": "温寻",
            "character_id": "char_wen_xun",
            "sub_type": "sprite",
            "name": "温寻 半身立绘",
            "prompt": "Chinese young male painter Wen Xun, 24 years old, short messy dark hair, paint-stained beige artist apron, nervously gripping paintbrush, anxious and defensive expression, waist-up portrait, standing pose, white background",
            "negative_prompt": "(background:1.3), complex background, extra limbs, bad hands",
            "local_path": "res://projects/case_gallery_rain/assets/images/characters/char_wen_xun.png",
            "width": 512,
            "height": 768,
            "status": "pending"
        },
        {
            "id": "clue_sugar_sculpture",
            "type": "clue",
            "entity_type": "clue",
            "entity_id": "clue_sugar_sculpture",
            "entity_name": "半融的画糖雕塑",
            "sub_type": "image",
            "name": "半融的画糖雕塑 特写",
            "prompt": "half melted sugar candy sculpture on vintage porcelain plate, faint golden glow, macro close-up shot, dramatic lighting, isolated, single object",
            "negative_prompt": "humans, hands, cluttered, text",
            "local_path": "res://projects/case_gallery_rain/assets/images/clues/clue_sugar_sculpture.png",
            "width": 512,
            "height": 512,
            "status": "pending"
        },
        {
            "id": "clue_ultramarine_thread",
            "type": "clue",
            "entity_type": "clue",
            "entity_id": "clue_ultramarine_thread",
            "entity_name": "沾染群青油彩的细线",
            "sub_type": "image",
            "name": "沾染群青油彩的细线 特写",
            "prompt": "thin nylon fishing thread stained with ultramarine blue oil paint, coiled on dark velvet cloth, macro close-up shot, dramatic lighting, isolated",
            "negative_prompt": "humans, hands, cluttered, text",
            "local_path": "res://projects/case_gallery_rain/assets/images/clues/clue_ultramarine_thread.png",
            "width": 512,
            "height": 512,
            "status": "pending"
        },
        {
            "id": "clue_wax_seal",
            "type": "clue",
            "entity_type": "clue",
            "entity_id": "clue_wax_seal",
            "entity_name": "倒计时火漆印",
            "sub_type": "image",
            "name": "倒计时火漆印 特写",
            "prompt": "red wax seal stamp on metallic iron bolt rail, dripping wax texture, macro close-up shot, dramatic lighting, isolated, single object",
            "negative_prompt": "humans, hands, cluttered, text",
            "local_path": "res://projects/case_gallery_rain/assets/images/clues/clue_wax_seal.png",
            "width": 512,
            "height": 512,
            "status": "pending"
        },
        {
            "id": "voice_dlg_intro_1",
            "type": "voice",
            "entity_type": "character",
            "entity_id": "char_narrator",
            "entity_name": "旁白",
            "role": "旁白",
            "sub_type": "voice",
            "name": "旁白 配音: 暴雨倾盆的午夜...",
            "text": "暴雨倾盆的午夜，美术馆顶层的铁门被强行破开，收藏家陆伯言倒在画架旁，瞳孔已经扩散。",
            "voice_role": "zh-CN-YunyangNeural",
            "local_path": "res://projects/case_gallery_rain/assets/audio/voice/voice_dlg_intro_1.mp3",
            "status": "pending"
        },
        {
            "id": "voice_dlg_intro_2",
            "type": "voice",
            "entity_type": "character",
            "entity_id": "char_shen_ce",
            "entity_name": "沈策",
            "role": "沈策",
            "sub_type": "voice",
            "name": "沈策 配音: 门窗皆反锁，窗外...",
            "text": "门窗皆反锁，窗外毫无攀爬脚印。温寻，身为今晚唯一的陪同者，你有什么想说的？",
            "voice_role": "zh-CN-YunjianNeural",
            "local_path": "res://projects/case_gallery_rain/assets/audio/voice/voice_dlg_intro_2.mp3",
            "status": "pending"
        },
        {
            "id": "voice_dlg_intro_3",
            "type": "voice",
            "entity_type": "character",
            "entity_id": "char_wen_xun",
            "entity_name": "温寻",
            "role": "温寻",
            "sub_type": "voice",
            "name": "温寻 配音: 沈侦探！我八点就...",
            "text": "沈侦探！我八点就离开画室下楼煮夜宵了，离开时老师亲手把门反锁，我绝不可能下毒！",
            "voice_role": "zh-CN-YunxiNeural",
            "local_path": "res://projects/case_gallery_rain/assets/audio/voice/voice_dlg_intro_3.mp3",
            "status": "pending"
        },
        {
            "id": "voice_dlg_intro_4",
            "type": "voice",
            "entity_type": "character",
            "entity_id": "char_shen_ce",
            "entity_name": "沈策",
            "role": "沈策",
            "sub_type": "voice",
            "name": "沈策 配音: 是不是谎言，画室...",
            "text": "是不是谎言，画室里的物证会告诉我答案。仔细搜查每一个角落吧。",
            "voice_role": "zh-CN-YunjianNeural",
            "local_path": "res://projects/case_gallery_rain/assets/audio/voice/voice_dlg_intro_4.mp3",
            "status": "pending"
        },
        {
            "id": "voice_dlg_confrontation_1",
            "type": "voice",
            "entity_type": "character",
            "entity_id": "char_shen_ce",
            "entity_name": "沈策",
            "role": "沈策",
            "sub_type": "voice",
            "name": "沈策 配音: 温寻，你的不在场证明...",
            "text": "温寻，你的‘下楼不在场证明’从一开始就是用这间画室为你布置的障眼法！",
            "voice_role": "zh-CN-YunjianNeural",
            "local_path": "res://projects/case_gallery_rain/assets/audio/voice/voice_dlg_confrontation_1.mp3",
            "status": "pending"
        },
        {
            "id": "voice_dlg_confrontation_2",
            "type": "voice",
            "entity_type": "character",
            "entity_id": "char_wen_xun",
            "entity_name": "温寻",
            "role": "温寻",
            "sub_type": "voice",
            "name": "温寻 配音: 口说无凭！门是从里面...",
            "text": "口说无凭！门是从里面插上的，就算毒发身亡，我又是怎么隔空把铁门插销锁死的？！",
            "voice_role": "zh-CN-YunxiNeural",
            "local_path": "res://projects/case_gallery_rain/assets/audio/voice/voice_dlg_confrontation_2.mp3",
            "status": "pending"
        },
        {
            "id": "voice_dlg_ending_truth_1",
            "type": "voice",
            "entity_type": "character",
            "entity_id": "char_shen_ce",
            "entity_name": "沈策",
            "role": "沈策",
            "sub_type": "voice",
            "name": "沈策 配音: 沾着群青油彩的细线...",
            "text": "沾着群青油彩的细线穿过门缝，火漆冷却后重锤落下——你以为带走了细线，但门轴上的蜡印早就出卖了一切。",
            "voice_role": "zh-CN-YunjianNeural",
            "local_path": "res://projects/case_gallery_rain/assets/audio/voice/voice_dlg_ending_truth_1.mp3",
            "status": "pending"
        },
        {
            "id": "voice_dlg_ending_truth_2",
            "type": "voice",
            "entity_type": "character",
            "entity_id": "char_wen_xun",
            "entity_name": "温寻",
            "role": "温寻",
            "sub_type": "voice",
            "name": "温寻 配音: 他夺走了我所有的画...",
            "text": "……他夺走了我所有的画，甚至要在明天的拍卖会上署上他的名字……我只是拿回属于我自己的东西！",
            "voice_role": "zh-CN-YunxiNeural",
            "local_path": "res://projects/case_gallery_rain/assets/audio/voice/voice_dlg_ending_truth_2.mp3",
            "status": "pending"
        },
        {
            "id": "voice_dlg_ending_truth_3",
            "type": "voice",
            "entity_type": "character",
            "entity_id": "char_narrator",
            "entity_name": "旁白",
            "role": "旁白",
            "sub_type": "voice",
            "name": "旁白 配音: 警笛在雨夜中划破长空...",
            "text": "警笛在雨夜中划破长空，晨光透过彩绘玻璃射入走廊，画廊的最后调色落下了帷幕。",
            "voice_role": "zh-CN-YunyangNeural",
            "local_path": "res://projects/case_gallery_rain/assets/audio/voice/voice_dlg_ending_truth_3.mp3",
            "status": "pending"
        },
        {
            "id": "voice_dlg_ending_false_1",
            "type": "voice",
            "entity_type": "character",
            "entity_id": "char_shen_ce",
            "entity_name": "沈策",
            "role": "沈策",
            "sub_type": "voice",
            "name": "沈策 配音: 或许死者突发急性疾病...",
            "text": "或许……真的是死者突发急性疾病自杀封门。证据链不足以立案，暴雨冲淡了所有痕迹。",
            "voice_role": "zh-CN-YunjianNeural",
            "local_path": "res://projects/case_gallery_rain/assets/audio/voice/voice_dlg_ending_false_1.mp3",
            "status": "pending"
        },
        {
            "id": "voice_dlg_ending_false_2",
            "type": "voice",
            "entity_type": "character",
            "entity_id": "char_wen_xun",
            "entity_name": "温寻",
            "role": "温寻",
            "sub_type": "voice",
            "name": "温寻 配音: 我就说了我什么都不知道...",
            "text": "我就说了我什么都不知道……请容许我先为老师操办后事吧。",
            "voice_role": "zh-CN-YunxiNeural",
            "local_path": "res://projects/case_gallery_rain/assets/audio/voice/voice_dlg_ending_false_2.mp3",
            "status": "pending"
        },
        {
            "id": "voice_dlg_ending_false_3",
            "type": "voice",
            "entity_type": "character",
            "entity_id": "char_narrator",
            "entity_name": "旁白",
            "role": "旁白",
            "sub_type": "voice",
            "name": "旁白 配音: 暴雨下了一整夜...",
            "text": "暴雨下了一整夜，真正的诡计被尘封在油彩之下，画室的冤魂将永远无声沉睡。",
            "voice_role": "zh-CN-YunyangNeural",
            "local_path": "res://projects/case_gallery_rain/assets/audio/voice/voice_dlg_ending_false_3.mp3",
            "status": "pending"
        }
    ]
}

pjson_path = os.path.join(PROJECT_DIR, "project.json")
with open(pjson_path, "w", encoding="utf-8") as f:
    json.dump(project_data, f, ensure_ascii=False, indent="\t")

print(f"✅ 成功创建纯净短篇工程: {pjson_path}")
print(f"包含角色: {list(project_data['characters'].keys())}")
print(f"包含场景: {list(project_data['scenes'].keys())}")
print(f"包含线索: {list(project_data['clues'].keys())}")
print(f"清单素材项: {len(project_data['asset_manifest'])} 项")
