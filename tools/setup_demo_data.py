import json
import os

BASE_DIR = "E:/aigame"

def write_json(rel_path, data):
    full_path = os.path.join(BASE_DIR, rel_path)
    os.makedirs(os.path.dirname(full_path), exist_ok=True)
    with open(full_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"Written: {rel_path}")

def setup_demo_data():
    # 1. game_config.json
    write_json("config/game_config.json", {
        "game_title": "暴风雨山庄：第十三钟声",
        "version": "1.0.0",
        "author": "Antigravity Detective Studio",
        "protagonist": "林侦探",
        "default_text_speed": 0.02
    })

    # 2. flow_config.json
    write_json("config/flow_config.json", {
        "start_node": "node_01_intro",
        "time_phases": ["雨夜抵达", "现场搜查", "破案辩论", "真相大白"]
    })

    # 3. data/nodes
    write_json("data/nodes/node_01_intro.json", {
        "id": "node_01_intro",
        "title": "序幕：暴雨夜的质询",
        "type": "story",
        "dialogue": "diag_01_intro",
        "next": "node_02_explore",
        "is_milestone": True,
        "time_phase": "雨夜抵达"
    })

    write_json("data/nodes/node_02_explore.json", {
        "id": "node_02_explore",
        "title": "搜查豪宅书房",
        "type": "explore",
        "scene": "scene_01_study",
        "is_milestone": True,
        "time_phase": "现场搜查"
    })

    write_json("data/nodes/node_03_inquiry.json", {
        "id": "node_03_inquiry",
        "title": "当面质询管家",
        "type": "story",
        "dialogue": "diag_02_inquiry",
        "time_phase": "破案辩论"
    })

    write_json("data/nodes/node_04_reasoning.json", {
        "id": "node_04_reasoning",
        "title": "击溃伪造的不在场证明",
        "type": "reasoning",
        "reasoning_id": "reason_01_clock",
        "is_milestone": True,
        "time_phase": "破案辩论"
    })

    write_json("data/nodes/node_05_ending.json", {
        "id": "node_05_ending",
        "title": "真相大白",
        "type": "ending",
        "ending_id": "ending_01_truth",
        "dialogue": "diag_03_ending",
        "time_phase": "真相大白"
    })

    # 4. data/scenes
    write_json("data/scenes/scene_01_study.json", {
        "id": "scene_01_study",
        "name": "古宅钟楼书房",
        "background": "res://assets/images/backgrounds/bg_study_storm.png",
        "bgm": "res://assets/audio/bgm/bgm_suspense_rain.wav",
        "explore_points": [
            {
                "id": "point_clock",
                "name": "🕰️ 停摆的落地钟",
                "rect": [0.08, 0.25, 0.16, 0.50],
                "type": "once",
                "trigger": {
                    "action": "clue",
                    "target": "clue_broken_clock"
                }
            },
            {
                "id": "point_teacup",
                "name": "🍵 壁炉旁的碎茶杯",
                "rect": [0.42, 0.52, 0.16, 0.24],
                "type": "once",
                "trigger": {
                    "action": "clue",
                    "target": "clue_sleeping_pills"
                }
            },
            {
                "id": "point_butler",
                "name": "👤 管家苏伯",
                "rect": [0.72, 0.28, 0.22, 0.58],
                "type": "repeatable",
                "trigger": {
                    "action": "jump_node",
                    "target": "node_03_inquiry"
                }
            }
        ]
    })

    # 5. data/clues
    write_json("data/clues/clue_broken_clock.json", {
        "id": "clue_broken_clock",
        "title": "卡死的古董落地钟",
        "type": "item",
        "source": "书房左侧落地钟",
        "description": "落地钟的指针停在【23点15分】。内部齿轮被一块铅块卡死，绝不可能在午夜12点发出钟声！"
    })

    write_json("data/clues/clue_sleeping_pills.json", {
        "id": "clue_sleeping_pills",
        "title": "残留药粉的碎茶杯",
        "type": "item",
        "source": "壁炉台红茶碎渣",
        "description": "伯爵红茶杯碎片底部残留未溶解的安眠药粉末，证明被害人早在23点前就已昏睡。"
    })

    # 6. data/dialogues
    write_json("data/dialogues/diag_01_intro.json", {
        "id": "diag_01_intro",
        "lines": [
            {
                "speaker": "旁白",
                "text": "暴风雨席卷了整座孤岛庄园，闪电刺破夜空。书房深处，案发时的回音犹在耳边。",
                "voice": "res://assets/audio/voice/voice_intro_1.mp3"
            },
            {
                "speaker": "林侦探",
                "character_image": "res://assets/images/characters/char_detective_normal.png",
                "text": "苏管家，你坚称自己在深夜十二点整，听到书房里传出老爷的争执声，随后古董钟敲了整整十二下？",
                "voice": "res://assets/audio/voice/voice_lin_question.mp3"
            },
            {
                "speaker": "苏管家",
                "character_image": "res://assets/images/characters/char_butler_nervous.png",
                "text": "是、是的，林侦探！老奴当时就在门外走廊擦拭银器，听得千真万确！",
                "voice": "res://assets/audio/voice/voice_butler_lie.mp3"
            },
            {
                "speaker": "林侦探",
                "character_image": "res://assets/images/characters/char_detective_normal.png",
                "text": "这里一定留有某种致命的破绽。我必须仔细调查这座书房！",
                "voice": "res://assets/audio/voice/voice_lin_investigate.mp3"
            }
        ]
    })

    write_json("data/dialogues/diag_02_inquiry.json", {
        "id": "diag_02_inquiry",
        "lines": [
            {
                "speaker": "林侦探",
                "character_image": "res://assets/images/characters/char_detective_normal.png",
                "text": "苏管家，关于你声称在午夜12点听到书房大钟报时作为不在场证明……我已经看穿了你的谎言！"
            }
        ],
        "choices": [
            {
                "text": "指出不在场证明中的致命矛盾（出示证物）",
                "next_node": "node_04_reasoning"
            },
            {
                "text": "继续搜查书房现场其他线索",
                "next_node": "node_02_explore"
            }
        ]
    })

    write_json("data/dialogues/diag_03_ending.json", {
        "id": "diag_03_ending",
        "lines": [
            {
                "speaker": "苏管家",
                "character_image": "res://assets/images/characters/char_butler_nervous.png",
                "text": "什……什么？！钟怎么会停在那个时候……难道老头子他早就……我、我认罪了！",
                "voice": "res://assets/audio/voice/voice_butler_breakdown.mp3"
            },
            {
                "speaker": "旁白",
                "text": "在确凿的物证面前，伪造的不在场证明瞬间崩塌。案情的真相，终于在暴雨中浮出水面。",
                "voice": "res://assets/audio/voice/voice_ending_victory.mp3"
            }
        ]
    })

    # 7. data/reasonings
    write_json("data/reasonings/reason_01_clock.json", {
        "id": "reason_01_clock",
        "title": "击穿午夜十二点的谎言",
        "question": "苏管家坚称【十二点整听到书房大钟敲响了十二下】作为不在场证明，哪个物证能证明他在撒谎？",
        "required_clues": ["clue_broken_clock"],
        "error_hints": {
            "clue_sleeping_pills": "红茶里的药粉确实说明老爷当时可能已昏迷，但这不能直接推翻管家宣称的【听到时钟敲响】！我们需要针对时钟本身的直接铁证！"
        },
        "next_node": "node_05_ending"
    })

    # 8. data/endings
    write_json("data/endings/ending_01_truth.json", {
        "id": "ending_01_truth",
        "title": "🎉 案情告破：第十三钟声的终结",
        "description": "林侦探利用卡死在23点15分的古董大钟，无情拆穿了管家精心编造的不在场证明！在如山的铁证面前，管家彻底崩溃伏法。\n\n暴风雨渐歇，晨曦穿透书房的窗棂，案件圆满侦破！"
    })

if __name__ == "__main__":
    setup_demo_data()
    print("Demo case data setup completed successfully!")
