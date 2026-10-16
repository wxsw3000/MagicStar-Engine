import asyncio
import edge_tts
import os

VOICE_DIR = "E:/aigame/assets/audio/voice"
os.makedirs(VOICE_DIR, exist_ok=True)

VOICE_MAP = {
    "narrator": "zh-CN-XiaoxiaoNeural",
    "lin": "zh-CN-YunxiNeural",
    "butler": "zh-CN-YunjianNeural"
}

LINES = [
    ("voice_intro_1.mp3", "narrator", "暴风雨席卷了整座孤岛庄园，闪电刺破夜空。书房深处，案发时的回音犹在耳边。"),
    ("voice_lin_question.mp3", "lin", "苏管家，你坚称自己在深夜十二点整，听到书房里传出老爷的争执声，随后古董钟敲了整整十二下？"),
    ("voice_butler_lie.mp3", "butler", "是、是的，林侦探！老奴当时就在门外走廊擦拭银器，听得千真万确！"),
    ("voice_lin_investigate.mp3", "lin", "这里一定留有某种致命的破绽。我必须仔细调查这座书房！"),
    ("voice_clock_inspect.mp3", "lin", "这座古董落地大钟……等等！指针竟然死死停在十一点十五分！齿轮内部有被硬物卡住的痕迹！"),
    ("voice_teacup_inspect.mp3", "lin", "壁炉台上的碎瓷片……残留的红茶底部，有未溶解的白色安眠药粉末！"),
    ("voice_lin_objection.mp3", "lin", "苏管家！你的不在场证明存在致命矛盾！请看这个时钟——它在十一点十五分就已经彻底卡死停摆，十二点绝不可能敲响！你在撒谎！"),
    ("voice_butler_breakdown.mp3", "butler", "什……什么？！钟怎么会停在那个时候……难道老头子他早就……我、我认罪了！"),
    ("voice_ending_victory.mp3", "narrator", "在确凿的物证面前，伪造的不在场证明瞬间崩塌。案情的真相，终于在暴雨中浮出水面。")
]

async def generate_all():
    print("Starting TTS generation...")
    for filename, role, text in LINES:
        voice = VOICE_MAP.get(role, "zh-CN-XiaoxiaoNeural")
        save_path = os.path.join(VOICE_DIR, filename)
        communicate = edge_tts.Communicate(text, voice)
        await communicate.save(save_path)
        print(f"Generated: {filename} ({role})")
    print("All voice files generated successfully!")

if __name__ == "__main__":
    asyncio.run(generate_all())
