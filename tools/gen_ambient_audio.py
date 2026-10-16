import wave
import math
import random
import struct
import os

SAMPLE_RATE = 44100

def create_wave(filename, duration, sample_generator):
    os.makedirs(os.path.dirname(filename), exist_ok=True)
    num_samples = int(SAMPLE_RATE * duration)
    with wave.open(filename, 'w') as wav:
        wav.setnchannels(1)  # mono
        wav.setsampwidth(2)  # 16-bit
        wav.setframerate(SAMPLE_RATE)
        for i in range(num_samples):
            t = i / SAMPLE_RATE
            val = sample_generator(t, i, num_samples)
            val = max(-1.0, min(1.0, val))
            sample = int(val * 32767)
            wav.writeframes(struct.pack('<h', sample))

# 1. 雨夜悬疑氛围 BGM (雨声底噪 + 低音氛围和弦)
def gen_bgm():
    random.seed(42)
    def bgm_gen(t, i, total):
        # 雨声粉红噪声模拟
        rain = (random.random() * 2 - 1) * 0.12
        # 低沉悬疑低音弦律 (D小调: D2=73.4Hz, F2=87.3Hz, A2=110Hz)
        chord_freq = 73.416
        if (t % 16) > 8:
            chord_freq = 65.406 # C2
        drone = math.sin(2 * math.pi * chord_freq * t) * 0.18
        drone += math.sin(2 * math.pi * (chord_freq * 1.5) * t) * 0.08
        # 慢速低频脉动 (LFO)
        lfo = 0.8 + 0.2 * math.sin(2 * math.pi * 0.25 * t)
        # 偶尔的水滴声
        drip = 0.0
        if random.random() < 0.0002:
            drip = math.sin(2 * math.pi * 1200 * t) * 0.15
        return (rain + drone * lfo + drip) * 0.7

    create_wave("E:/aigame/assets/audio/bgm/bgm_suspense_rain.wav", 16.0, bgm_gen)
    print("Generated bgm_suspense_rain.wav")

# 2. 发现线索提示音 (清脆双音和弦)
def gen_sfx_clue():
    def clue_gen(t, i, total):
        env = math.exp(-t * 5.0)
        # E6 (1318.5Hz) -> G#6 (1661.2Hz) -> B6 (1975.5Hz)
        s1 = math.sin(2 * math.pi * 1318.5 * t)
        s2 = math.sin(2 * math.pi * 1975.5 * t)
        return (s1 * 0.5 + s2 * 0.5) * env * 0.8
    create_wave("E:/aigame/assets/audio/sfx/sfx_clue_found.wav", 1.2, clue_gen)
    print("Generated sfx_clue_found.wav")

# 3. 击溃谎言/异议重击音效 (低音撞击震撼音)
def gen_sfx_objection():
    random.seed(99)
    def obj_gen(t, i, total):
        env = math.exp(-t * 4.0)
        # 下降滑音从 180Hz 骤降至 45Hz
        freq = 180.0 * math.exp(-t * 6.0) + 45.0
        hit = math.sin(2 * math.pi * freq * t) * 0.8
        # 爆音瞬态
        noise = (random.random() * 2 - 1) * math.exp(-t * 20.0) * 0.4
        return (hit + noise) * env
    create_wave("E:/aigame/assets/audio/sfx/sfx_objection.wav", 1.5, obj_gen)
    print("Generated sfx_objection.wav")

if __name__ == "__main__":
    gen_bgm()
    gen_sfx_clue()
    gen_sfx_objection()
