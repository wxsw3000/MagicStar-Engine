import ssl
import urllib.request
import urllib.parse
import json
import time
import os
import sys
import base64
from PIL import Image

# 引入 ai_bridge 现成的像素级面部遮罩与余弦融合函数
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ai_bridge import create_adaptive_face_mask, harmonize_and_blend

def get_ssl_context():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx

def upload_image(base_url, headers, ctx, image_path, filename):
    boundary = "----WebKitFormBoundary" + str(int(time.time() * 1000))
    with open(image_path, "rb") as f:
        file_bytes = f.read()

    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="image"; filename="{filename}"\r\n'
        f"Content-Type: image/png\r\n\r\n"
    ).encode("utf-8") + file_bytes + (
        f"\r\n--{boundary}\r\n"
        f'Content-Disposition: form-data; name="overwrite"\r\n\r\n'
        f"true\r\n"
        f"--{boundary}--\r\n"
    ).encode("utf-8")

    req_headers = dict(headers)
    req_headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
    req = urllib.request.Request(f"{base_url}/upload/image", data=body, headers=req_headers)
    with urllib.request.urlopen(req, context=ctx, timeout=15) as resp:
        return json.loads(resp.read().decode("utf-8"))

def build_qwen_diff_workflow(uploaded_ref_filename, prompt_text, neg_prompt_text, seed=42, steps=20, cfg=3.5, resolution=768, clip_name="qwen3vl_8b_w4a8.safetensors"):
    """
    Qwen-Image-2.1 GGUF 高精度指令差分工作流 (经过 4060 验证并移植到 199 RTX PRO 6000)
    """
    return {
        "unet": {
            "class_type": "UnetLoaderGGUF",
            "inputs": {
                "unet_name": "qwen-image-2.1-Q4_K_M.gguf"
            }
        },
        "cache": {
            "class_type": "QwenImage21Cache",
            "inputs": {
                "model": ["unet", 0],
                "device": "auto",
                "dtype": "int8"
            }
        },
        "clip": {
            "class_type": "CLIPLoader",
            "inputs": {
                "clip_name": clip_name,
                "type": "qwen_image"
            }
        },
        "vae": {
            "class_type": "VAELoader",
            "inputs": {
                "vae_name": "qwen_image_2.1_vae_bf16.safetensors"
            }
        },
        "ref_img": {
            "class_type": "LoadImage",
            "inputs": {
                "image": uploaded_ref_filename
            }
        },
        "qwen_enc": {
            "class_type": "TextEncodeQwenImage21",
            "inputs": {
                "clip": ["clip", 0],
                "prompt": prompt_text,
                "negative_prompt": neg_prompt_text,
                "resolution": resolution,
                "vae": ["vae", 0],
                "images.image_1": ["ref_img", 0]
            }
        },
        "sampler": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["cache", 0],
                "seed": seed,
                "steps": steps,
                "cfg": cfg,
                "sampler_name": "euler",
                "scheduler": "simple",
                "positive": ["qwen_enc", 0],
                "negative": ["qwen_enc", 1],
                "latent_image": ["qwen_enc", 2],
                "denoise": 1.0
            }
        },
        "decode": {
            "class_type": "VAEDecode",
            "inputs": {
                "samples": ["sampler", 0],
                "vae": ["vae", 0]
            }
        },
        "save": {
            "class_type": "SaveImage",
            "inputs": {
                "images": ["decode", 0],
                "filename_prefix": "qwen21_199_shen_ce_smile"
            }
        }
    }

import argparse

EXPRESSION_PROMPTS = {
    "smile": (
        "In Picture 1, keep the man's identity, facial structure, eyes, hairstyle, black hair, "
        "and black modern detective clothing strictly identical. "
        "Change only his expression to a gentle, warm smile: mouth curved upwards with a soft smile, "
        "friendly eyes, relaxed warm atmosphere."
    ),
    "shocked": (
        "In Picture 1, keep the man's identity, facial structure, eyes, hairstyle, black hair, "
        "and black modern detective clothing strictly identical. "
        "Change only his expression to a shocked, surprised look: eyes wide open, eyebrows slightly raised, "
        "mouth slightly parted in disbelief."
    ),
    "ponder": (
        "In Picture 1, keep the man's identity, facial structure, eyes, hairstyle, black hair, "
        "and black modern detective clothing strictly identical. "
        "Change only his expression to a deep pondering thoughtful expression: eyes narrowed in contemplation, "
        "lips firmly set, analytical deductive expression."
    ),
    "serious": (
        "In Picture 1, keep the man's identity, facial structure, eyes, hairstyle, black hair, "
        "and black modern detective clothing strictly identical. "
        "Change only his expression to a stern, serious, sharp detective expression: intense focused gaze, "
        "straight firm mouth, solemn calm demeanor."
    )
}

def main():
    parser = argparse.ArgumentParser(description="199 Server Qwen Diff Generator")
    parser.add_argument("--expression", type=str, default="smile", choices=list(EXPRESSION_PROMPTS.keys()), help="Preset expression")
    parser.add_argument("--custom_prompt", type=str, default=None, help="Custom prompt override")
    parser.add_argument("--seed", type=int, default=42, help="Sampling seed")
    parser.add_argument("--steps", type=int, default=20, help="Sampling steps")
    args = parser.parse_args()

    base_url = "https://192.168.0.199:8188"
    auth_str = base64.b64encode(b"dkzl_ubuntu:Jyzn2331").decode("utf-8")
    headers = {
        "Authorization": f"Basic {auth_str}",
        "User-Agent": "AVGStudio/1.0"
    }
    ctx = get_ssl_context()

    expr_name = args.expression
    prompt = args.custom_prompt if args.custom_prompt else EXPRESSION_PROMPTS.get(expr_name, EXPRESSION_PROMPTS["smile"])
    neg_prompt = "ugly, deformed, mutated, extra fingers, disfigured, blurry, low quality, changed clothes, changed hairstyle"

    print(f"[1/6] 连接 199 ComfyUI: {base_url} ...")
    try:
        req = urllib.request.Request(f"{base_url}/system_stats", headers=headers)
        with urllib.request.urlopen(req, context=ctx, timeout=5) as res:
            stats = json.loads(res.read().decode("utf-8"))
            dev = stats.get("devices", [{}])[0]
            print(f"      GPU: {dev.get('name')}")
            print(f"      空闲显存: {dev.get('vram_free', 0) / (1024*1024):.1f} MB")
    except Exception as e:
        print(f"❌ 无法连接到 199 ComfyUI: {e}")
        return False

    # 检查 UnetLoaderGGUF 是否就绪
    req_obj = urllib.request.Request(f"{base_url}/object_info", headers=headers)
    chosen_clip = "qwen_2.5_vl_7b_fp8_scaled.safetensors"
    with urllib.request.urlopen(req_obj, context=ctx, timeout=6) as robj:
        d_obj = json.loads(robj.read().decode("utf-8"))
        if "UnetLoaderGGUF" not in d_obj:
            print("❌ 远端 199 ComfyUI 尚未加载 UnetLoaderGGUF 节点！")
            return False
        avail_clips = d_obj.get("CLIPLoader", {}).get("input", {}).get("required", {}).get("clip_name", [[]])[0]
        for c in avail_clips:
            if "qwen3vl" in c.lower() or "qwen3" in c.lower():
                chosen_clip = c
                break
        print(f"      ✅ 远端 UnetLoaderGGUF 节点已就绪，选用文本编码器: {chosen_clip}")

    ref_path = "E:/MagicStar-Engine/projects/case_gallery_rain/assets/images/characters/char_shen_ce.png"
    ref_name = "qwen_ref_shen_ce.png"
    print(f"[2/6] 上传参考立绘: {ref_path} ...")
    up_res = upload_image(base_url, headers, ctx, ref_path, ref_name)
    print(f"      上传成功: {up_res.get('name', ref_name)}")

    print(f"[3/6] 构建 Qwen-Image-2.1 GGUF 指令微表情差分工作流 ({expr_name}) 并提交 ...")
    wf = build_qwen_diff_workflow(ref_name, prompt, neg_prompt, seed=args.seed, steps=args.steps, cfg=3.5, resolution=768, clip_name=chosen_clip)

    prompt_data = json.dumps({"prompt": wf}).encode("utf-8")
    p_headers = dict(headers)
    p_headers["Content-Type"] = "application/json"
    p_req = urllib.request.Request(f"{base_url}/prompt", data=prompt_data, headers=p_headers)

    try:
        with urllib.request.urlopen(p_req, context=ctx, timeout=10) as res:
            res_json = json.loads(res.read().decode("utf-8"))
            prompt_id = res_json.get("prompt_id")
            print(f"      任务已提交, Prompt ID: {prompt_id}")
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8")
        print(f"❌ 任务验证/提交失败 (HTTP {e.code}):\n{err_body}")
        return False
    except Exception as e:
        print(f"❌ 提交请求异常: {e}")
        return False

    print(f"[4/6] 轮询任务执行状态并监控生成 ...")
    start_time = time.time()
    last_print = 0

    while True:
        elapsed = time.time() - start_time
        try:
            h_req = urllib.request.Request(f"{base_url}/history/{prompt_id}", headers=headers)
            with urllib.request.urlopen(h_req, context=ctx, timeout=5) as res:
                hist_data = json.loads(res.read().decode("utf-8"))
        except Exception:
            time.sleep(2)
            continue

        if prompt_id in hist_data:
            item = hist_data[prompt_id]
            status = item.get("status", {})
            status_str = status.get("status_str")
            if status_str == "error":
                print(f"\n❌ 推理执行出错! 错误信息:")
                msgs = status.get("messages", [])
                for m in msgs:
                    if len(m) > 1 and isinstance(m[1], dict) and "exception_message" in m[1]:
                        print(f"   Node: {m[1].get('node_type')} ({m[1].get('node_id')})")
                        print(f"   Error: {m[1].get('exception_message')}")
                        for tb in m[1].get("traceback", []):
                            print(f"   {tb.strip()}")
                return False

            if status.get("completed", False) or item.get("outputs"):
                print(f"\n✅ 渲染完成! 总耗时: {elapsed:.2f} 秒")
                outputs = item.get("outputs", {})
                save_out = outputs.get("save", {}).get("images", [])
                if not save_out:
                    print("⚠️ 未找到输出图片列表!")
                    return False
                img_info = save_out[0]
                img_fn = img_info.get("filename")
                img_sub = img_info.get("subfolder", "")
                img_type = img_info.get("type", "output")

                raw_download_path = "E:/MagicStar-Engine/samples/qwen21_199_raw_gen.png"
                print(f"[5/6] 下载生成的差分图像: {img_fn} ...")
                query = urllib.parse.urlencode({"filename": img_fn, "subfolder": img_sub, "type": img_type})
                view_url = f"{base_url}/view?{query}"
                v_req = urllib.request.Request(view_url, headers=headers)
                with urllib.request.urlopen(v_req, context=ctx, timeout=20) as img_res:
                    raw_data = img_res.read()
                    with open(raw_download_path, "wb") as f:
                        f.write(raw_data)
                print(f"      原始差分已保存至: {raw_download_path} ({len(raw_data)} 字节)")

                # [6/6] 执行像素级羽化贴合融合
                final_out_path = f"E:/MagicStar-Engine/projects/case_gallery_rain/assets/images/characters/char_shen_ce_{expr_name}.png"
                print(f"[6/6] 执行余弦非线性羽化与服装发型绝对锁死融合 ...")
                base_pil = Image.open(ref_path).convert("RGBA")
                raw_gen_pil = Image.open(raw_download_path).convert("RGBA")
                
                # 提取面部自适应遮罩
                mask_pil = create_adaptive_face_mask(base_pil, prompt)
                # S曲线余弦过渡平滑融合
                final_blended = harmonize_and_blend(raw_gen_pil, base_pil, mask_pil)
                os.makedirs(os.path.dirname(final_out_path), exist_ok=True)
                final_blended.save(final_out_path, "PNG")
                print(f"      🎉 沈策【{expr_name}】差分立绘成功交付: {final_out_path} ({os.path.getsize(final_out_path)} 字节)")
                return True

        if elapsed - last_print >= 5:
            last_print = elapsed
            try:
                s_req = urllib.request.Request(f"{base_url}/system_stats", headers=headers)
                with urllib.request.urlopen(s_req, context=ctx, timeout=3) as sres:
                    s_data = json.loads(sres.read().decode("utf-8"))
                    v_free = s_data.get("devices", [{}])[0].get("vram_free", 0) / (1024 * 1024)
                    print(f"      [推理中... 已用时 {elapsed:.1f}s] 当前空闲显存: {v_free:.1f} MB")
            except Exception:
                print(f"      [推理中... 已用时 {elapsed:.1f}s]")

        time.sleep(2)

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
