# tools/ai_bridge.py
# AVG Studio 专属 AI 桥接器：统一调度 ComfyUI 生图与 Edge-TTS 语音合成
import sys
import os
import argparse
import json
import urllib.request
import urllib.error
import time
import asyncio
from PIL import Image

import ssl
import base64

def clean_base_url(host_str):
    h = host_str.strip()
    if not h.startswith("http://") and not h.startswith("https://"):
        if ":443" in h or "https" in h.lower():
            h = "https://" + h
        else:
            h = "http://" + h
    if h.endswith("/"):
        h = h[:-1]
    return h

def get_ssl_context():
    try:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        return ctx
    except Exception:
        return None

def get_auth_headers(user=None, password=None):
    headers = {"User-Agent": "AVGStudio/1.0"}
    if user and password:
        token = base64.b64encode(f"{user}:{password}".encode("utf-8")).decode("utf-8")
        headers["Authorization"] = f"Basic {token}"
    return headers

def cmd_check_comfy(args):
    base_url = clean_base_url(args.host)
    user = getattr(args, "user", None) or getattr(args, "auth_user", None)
    password = getattr(args, "password", None) or getattr(args, "auth_pass", None)
    
    headers = get_auth_headers(user, password)
    ctx = get_ssl_context()
    
    result = {"online": False, "gpu": "未知", "vram_free": 0, "checkpoints": []}
    try:
        url_stats = f"{base_url}/system_stats"
        req = urllib.request.Request(url_stats, headers=headers)
        with urllib.request.urlopen(req, context=ctx, timeout=8) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            result["online"] = True
            devices = data.get("devices", [])
            if devices:
                dev = devices[0]
                result["gpu"] = dev.get("name", "CUDA GPU")
                result["vram_free"] = dev.get("vram_free", 0)
                result["vram_total"] = dev.get("vram_total", 0)

        url_obj = f"{base_url}/object_info/CheckpointLoaderSimple"
        req_obj = urllib.request.Request(url_obj, headers=headers)
        with urllib.request.urlopen(req_obj, context=ctx, timeout=8) as resp:
            data_obj = json.loads(resp.read().decode("utf-8"))
            ckpts = data_obj.get("CheckpointLoaderSimple", {}).get("input", {}).get("required", {}).get("ckpt_name", [[]])[0]
            result["checkpoints"] = ckpts
    except Exception as e:
        result["error"] = str(e)

    print(json.dumps(result, ensure_ascii=False))

def cmd_generate_image(args):
    base_url = clean_base_url(args.host)
    user = getattr(args, "user", None) or getattr(args, "auth_user", None)
    password = getattr(args, "password", None) or getattr(args, "auth_pass", None)
    
    headers = get_auth_headers(user, password)
    ctx = get_ssl_context()
    
    save_path = os.path.abspath(args.save)
    os.makedirs(os.path.dirname(save_path), exist_ok=True)
    
    seed = args.seed if args.seed > 0 else int(time.time() * 1000) % 10000000
    
    # 智能适配 Turbo 模型：Turbo 系列步数通常需 4 步、cfg 1.0~2.0、euler_ancestral
    steps = args.steps
    cfg = args.cfg
    sampler = args.sampler
    scheduler = args.scheduler
    ckpt_lower = args.ckpt.lower()
    
    if "turbo" in ckpt_lower:
        if cfg >= 5.0:
            cfg = 1.5
        if steps >= 20:
            steps = 4
        if sampler in ["dpmpp_2m", "dpmpp_sde"]:
            sampler = "euler_ancestral"
    
    workflow = {
        "3": {
            "class_type": "KSampler",
            "inputs": {
                "cfg": cfg,
                "denoise": 1,
                "latent_image": ["5", 0],
                "model": ["4", 0],
                "negative": ["7", 0],
                "positive": ["6", 0],
                "sampler_name": sampler,
                "scheduler": scheduler,
                "seed": seed,
                "steps": steps
            }
        },
        "4": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {
                "ckpt_name": args.ckpt
            }
        },
        "5": {
            "class_type": "EmptyLatentImage",
            "inputs": {
                "batch_size": 1,
                "height": args.height,
                "width": args.width
            }
        },
        "6": {
            "class_type": "CLIPTextEncode",
            "inputs": {
                "clip": ["4", 1],
                "text": args.prompt
            }
        },
        "7": {
            "class_type": "CLIPTextEncode",
            "inputs": {
                "clip": ["4", 1],
                "text": args.negative
            }
        },
        "8": {
            "class_type": "VAEDecode",
            "inputs": {
                "samples": ["3", 0],
                "vae": ["4", 2]
            }
        },
        "9": {
            "class_type": "SaveImage",
            "inputs": {
                "filename_prefix": "AVG_Gen",
                "images": ["8", 0]
            }
        }
    }

    try:
        post_headers = dict(headers)
        post_headers["Content-Type"] = "application/json"
        
        prompt_req = urllib.request.Request(
            f"{base_url}/prompt",
            data=json.dumps({"prompt": workflow}).encode("utf-8"),
            headers=post_headers
        )
        with urllib.request.urlopen(prompt_req, context=ctx, timeout=12) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            prompt_id = data.get("prompt_id")
            
        if not prompt_id:
            print(json.dumps({"success": False, "error": "未能获取 prompt_id"}))
            return

        # 轮询等待生成完成
        start_time = time.time()
        timeout = args.timeout
        found = False
        
        while time.time() - start_time < timeout:
            time.sleep(1.0)
            try:
                h_url = f"{base_url}/history/{prompt_id}"
                req_h = urllib.request.Request(h_url, headers=headers)
                with urllib.request.urlopen(req_h, context=ctx, timeout=6) as h_resp:
                    h_data = json.loads(h_resp.read().decode("utf-8"))
                    if prompt_id in h_data:
                        outputs = h_data[prompt_id].get("outputs", {})
                        if "9" in outputs and "images" in outputs["9"]:
                            img_info = outputs["9"]["images"][0]
                            filename = img_info["filename"]
                            subfolder = img_info.get("subfolder", "")
                            view_url = f"{base_url}/view?filename={filename}&subfolder={subfolder}&type=output"
                            
                            req_view = urllib.request.Request(view_url, headers=headers)
                            with urllib.request.urlopen(req_view, context=ctx, timeout=15) as r_img:
                                with open(save_path, "wb") as f_out:
                                    f_out.write(r_img.read())
                            found = True
                            break
            except Exception:
                pass
                
        if not found:
            print(json.dumps({"success": False, "error": f"生成超时（超过 {timeout} 秒）"}))
            return

        # 若要求透明立绘通道处理
        if args.transparent:
            processed = False
            try:
                import rembg
                with open(save_path, 'rb') as i_f:
                    input_bytes = i_f.read()
                out_bytes = rembg.remove(input_bytes)
                with open(save_path, 'wb') as o_f:
                    o_f.write(out_bytes)
                processed = True
            except Exception:
                pass
                
            if not processed:
                try:
                    img = Image.open(save_path).convert("RGBA")
                    datas = img.getdata()
                    new_data = []
                    for item in datas:
                        brightness = (item[0] + item[1] + item[2]) / 3.0
                        if item[0] > 230 and item[1] > 230 and item[2] > 230:
                            new_data.append((255, 255, 255, 0))
                        elif item[0] > 205 and item[1] > 205 and item[2] > 205:
                            alpha = int(255 * (1.0 - (brightness - 205) / 25.0))
                            new_data.append((item[0], item[1], item[2], max(0, min(255, alpha))))
                        else:
                            new_data.append(item)
                    img.putdata(new_data)
                    img.save(save_path, "PNG")
                except Exception:
                    pass

        print(json.dumps({
            "success": True,
            "path": save_path,
            "seed": seed,
            "prompt_id": prompt_id
        }, ensure_ascii=False))

    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}, ensure_ascii=False))

async def async_generate_voice(text, voice, save_path, rate="+0%", pitch="+0Hz", volume="+0%"):
    import edge_tts
    os.makedirs(os.path.dirname(save_path), exist_ok=True)
    communicate = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch, volume=volume)
    await communicate.save(save_path)

def cmd_generate_voice(args):
    try:
        save_path = os.path.abspath(args.save)
        rate = args.rate
        pitch = args.pitch
        volume = args.volume
        
        # 依据情绪标签智能映射语气与语速
        emotion = getattr(args, "emotion", "normal").lower()
        if emotion in ["nervous", "anxious", "panic", "慌张", "紧张"]:
            rate = "+16%"
            pitch = "+6Hz"
        elif emotion in ["angry", "rage", "furious", "愤怒", "质问"]:
            rate = "+10%"
            pitch = "+3Hz"
            volume = "+25%"
        elif emotion in ["shocked", "surprise", "震惊", "意外"]:
            rate = "+12%"
            pitch = "+8Hz"
            volume = "+15%"
        elif emotion in ["sad", "sorrow", "grief", "悲伤", "沮丧", "哭泣"]:
            rate = "-15%"
            pitch = "-8Hz"
            volume = "-10%"
        elif emotion in ["confident", "serious", "calm", "自信", "破案", "严肃"]:
            rate = "-5%"
            pitch = "-2Hz"

        asyncio.run(async_generate_voice(args.text, args.voice, save_path, rate=rate, pitch=pitch, volume=volume))
        print(json.dumps({
            "success": True,
            "path": save_path,
            "voice": args.voice,
            "emotion": emotion,
            "rate": rate,
            "pitch": pitch
        }, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}, ensure_ascii=False))

def main():
    parser = argparse.ArgumentParser(description="AVG Studio AI Bridge")
    subparsers = parser.add_subparsers(dest="command")

    # check_comfy
    p_check = subparsers.add_parser("check_comfy")
    p_check.add_argument("--host", default="http://127.0.0.1:8188")
    p_check.add_argument("--user", default="")
    p_check.add_argument("--password", default="")

    # generate_image
    p_img = subparsers.add_parser("generate_image")
    p_img.add_argument("--host", default="http://127.0.0.1:8188")
    p_img.add_argument("--user", default="")
    p_img.add_argument("--password", default="")
    p_img.add_argument("--prompt", required=True)
    p_img.add_argument("--negative", default="worst quality, low quality, blurry")
    p_img.add_argument("--ckpt", default="sd_xl_turbo_1.0.safetensors")
    p_img.add_argument("--width", type=lambda x: int(float(x)), default=512)
    p_img.add_argument("--height", type=lambda x: int(float(x)), default=768)
    p_img.add_argument("--steps", type=lambda x: int(float(x)), default=28)
    p_img.add_argument("--sampler", default="dpmpp_2m")
    p_img.add_argument("--scheduler", default="karras")
    p_img.add_argument("--cfg", type=float, default=7.0)
    p_img.add_argument("--seed", type=lambda x: int(float(x)), default=-1)
    p_img.add_argument("--transparent", type=lambda x: int(float(x)), default=0)
    p_img.add_argument("--save", required=True)
    p_img.add_argument("--timeout", type=lambda x: int(float(x)), default=180)

    # generate_voice
    p_voice = subparsers.add_parser("generate_voice")
    p_voice.add_argument("--text", required=True)
    p_voice.add_argument("--voice", default="zh-CN-XiaoxiaoNeural")
    p_voice.add_argument("--save", required=True)
    p_voice.add_argument("--emotion", default="normal")
    p_voice.add_argument("--rate", default="+0%")
    p_voice.add_argument("--pitch", default="+0Hz")
    p_voice.add_argument("--volume", default="+0%")

    args = parser.parse_args()
    if args.command == "check_comfy":
        cmd_check_comfy(args)
    elif args.command == "generate_image":
        cmd_generate_image(args)
    elif args.command == "generate_voice":
        cmd_generate_voice(args)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
