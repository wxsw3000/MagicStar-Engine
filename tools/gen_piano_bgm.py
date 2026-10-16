import wave
import math
import struct
import os

SAMPLE_RATE = 44100
DURATION = 16.0 # 16秒无缝循环

def note_freq(name):
    # 音符音高映射
    freqs = {
        "D2": 73.42, "A2": 110.00, "Bb2": 116.54, "C3": 130.81, "C#3": 138.59,
        "D3": 146.83, "E3": 164.81, "F3": 174.61, "G3": 196.00, "A3": 220.00,
        "Bb3": 233.08, "C4": 261.63, "C#4": 277.18, "D4": 293.66, "E4": 329.63,
        "F4": 349.23, "G4": 392.00, "A4": 440.00
    }
    return freqs.get(name, 220.0)

def piano_note(t, freq, duration=3.0):
    if t < 0:
        return 0.0
    # 模拟真实钢琴击弦与谐波衰减 (基音 + 2次、3次、4次柔和泛音)
    amp = math.exp(-t * (2.2 + freq * 0.003))
    # 钢琴敲击瞬间微弱的木槌触键感
    hammer = math.sin(2 * math.pi * 80 * t) * math.exp(-t * 40.0) * 0.15
    
    h1 = math.sin(2 * math.pi * freq * t) * 1.0
    h2 = math.sin(2 * math.pi * freq * 2.0 * t) * 0.35 * math.exp(-t * 3.5)
    h3 = math.sin(2 * math.pi * freq * 3.0 * t) * 0.12 * math.exp(-t * 5.0)
    h4 = math.sin(2 * math.pi * freq * 4.0 * t) * 0.04 * math.exp(-t * 7.0)
    
    return (h1 + h2 + h3 + h4 + hammer) * amp * 0.25

def gen_mystery_piano_bgm():
    # 经典悬疑 D 小调慢速钢琴分解和弦 (Ace Attorney / 侦探物语风格)
    # 节奏: 60 BPM, 每小节 4 秒
    notes_timeline = [
        # 第 1 小节: Dm (沉重而专注的现场调查)
        (0.0, "D2"), (0.5, "A2"), (1.0, "D3"), (1.5, "F3"), (2.0, "A3"), (2.5, "D4"), (3.0, "F3"),
        # 第 2 小节: Bbmaj7 (暗流涌动的线索浮现)
        (4.0, "Bb2"), (4.5, "F3"), (5.0, "Bb3"), (5.5, "D4"), (6.0, "F4"), (6.5, "D4"), (7.0, "Bb3"),
        # 第 3 小节: Gm6 (疑点丛生的逻辑交织)
        (8.0, "G2"), (8.5, "D3"), (9.0, "G3"), (9.5, "Bb3"), (10.0, "D4"), (10.5, "E4"), (11.0, "Bb3"),
        # 第 4 小节: A7 (走向真相前的紧绷张力)
        (12.0, "A2"), (12.5, "E3"), (13.0, "A3"), (13.5, "C#4"), (14.0, "E4"), (14.5, "G4"), (15.0, "C#4")
    ]
    
    num_samples = int(SAMPLE_RATE * DURATION)
    buffer = [0.0] * num_samples
    
    # 叠加所有琴音
    for start_t, n_name in notes_timeline:
        f = note_freq(n_name)
        start_idx = int(start_t * SAMPLE_RATE)
        note_len = int(3.5 * SAMPLE_RATE)
        for i in range(note_len):
            idx = (start_idx + i) % num_samples
            t = i / SAMPLE_RATE
            buffer[idx] += piano_note(t, f)
            
    # 添加极其柔和的低频氛围垫底 (Soft warm cello pad，绝无沙沙白噪音)
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        # 低音大提琴温和长音
        drone_f = 73.42 # D2
        if t >= 4.0 and t < 8.0: drone_f = 58.27 # Bb1
        elif t >= 8.0 and t < 12.0: drone_f = 49.00 # G1
        elif t >= 12.0: drone_f = 55.00 # A1
        
        pad = math.sin(2 * math.pi * drone_f * t) * 0.08
        pad += math.sin(2 * math.pi * drone_f * 2 * t) * 0.03
        buffer[i] += pad

    # 输出为标准化 16-bit WAV
    max_val = max(max(abs(x) for x in buffer), 0.001)
    # 将电平限制在 -8dB，舒适且绝不爆音
    target_gain = 0.45 / max_val
    
    output_path = "E:/aigame/assets/audio/bgm/bgm_suspense_rain.wav"
    with wave.open(output_path, 'w') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        for val in buffer:
            sample = int(val * target_gain * 32767)
            wav.writeframes(struct.pack('<h', sample))
            
    print("Regenerated clean, warm, beautiful mystery piano BGM at:", output_path)

if __name__ == "__main__":
    gen_mystery_piano_bgm()
