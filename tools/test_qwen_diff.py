import urllib.request
import urllib.parse
import json
import time
import os
import sys
import argparse
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ai_bridge import create_adaptive_face_mask, harmonize_and_blend

def upload_image(base_url, image_path, filename):
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

    req = urllib.request.Request(
        f"{base_url}/upload/image",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"}
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode("utf-8"))

def build_nunchaku_edit_workflow(uploaded_ref_filename, prompt_text, neg_prompt_text, seed=777, steps=20, cfg=3.5):
    """
    4060 8G 实测跑通的官方 Nunchaku SVDQuant INT4 工作流
    """
    return {
        "dit": {
            "class_type": "NunchakuQwenImageDiTLoader",
            "inputs": {
                "model_name": "nunchaku_qwen_image_2511_balance_int4.safetensors",
                "cpu_offload": "auto"
            }
        },
        "clip": {
            "class_type": "CLIPLoader",
            "inputs": {
                "clip_name": "qwen_2.5_vl_7b_fp8_scaled.safetensors",
                "type": "qwen_image"
            }
        },
        "vae": {
            "class_type": "VAELoader",
            "inputs": {
                "vae_name": "qwen_image_vae.safetensors"
            }
        },
        "ref_img": {
            "class_type": "LoadImage",
            "inputs": {
                "image": uploaded_ref_filename
            }
        },
        "pos": {
            "class_type": "TextEncodeQwenImageEdit",
            "inputs": {
                "clip": ["clip", 0],
                "prompt": prompt_text,
                "vae": ["vae", 0],
                "image": ["ref_img", 0]
            }
        },
        "neg": {
            "class_type": "CLIPTextEncode",
            "inputs": {
                "clip": ["clip", 0],
                "text": neg_prompt_text
            }
        },
        "latent": {
            "class_type": "EmptyLatentImage",
            "inputs": {
                "width": 512,
                "height": 768,
                "batch_size": 1
            }
        },
        "sampler": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["dit", 0],
                "seed": seed,
                "steps": steps,
                "cfg": cfg,
                "sampler_name": "euler",
                "scheduler": "simple",
                "positive": ["pos", 0],
                "negative": ["neg", 0],
                "latent_image": ["latent", 0],
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
                "filename_prefix": "qwen_4060_shen_ce_diff"
            }
        }
    }

def main():
    parser = argparse.ArgumentParser(description="RTX 4060 Qwen Diff Runner")
    parser.add_argument("--url", type=str, default="http://192.168.1.57:8188", help="4060 ComfyUI base URL")
    parser.add_argument("--expression", type=str, default="serious", choices=["serious", "smile", "shocked", "ponder", "smirk"], help="Expression key")
    parser.add_argument("--seed", type=int, default=777, help="Seed")
    parser.add_argument("--steps", type=int, default=20, help="Steps")
    args = parser.parse_args()

    base_url = args.url.rstrip("/")
    ref_image_path = "E:/MagicStar-Engine/projects/case_gallery_rain/assets/images/characters/char_shen_ce.png"
    out_dir = "E:/MagicStar-Engine/samples"
    os.makedirs(out_dir, exist_ok=True)
    raw_gen_path = os.path.join(out_dir, f"qwen_4060_raw_{args.expression}.png")
    final_out_path = f"E:/MagicStar-Engine/projects/case_gallery_rain/assets/images/characters/char_shen_ce_{args.expression}.png"

    print(f"[1/5] 连接 4060 ComfyUI: {base_url} ...")
    try:
        with urllib.request.urlopen(f"{base_url}/system_stats", timeout=5) as res:
            stats = json.loads(res.read().decode("utf-8"))
            gpu_name = stats.get("devices", [{}])[0].get("name", "Unknown GPU")
            vram_free_mb = stats.get("devices", [{}])[0].get("vram_free", 0) / (1024 * 1024)
            print(f"      GPU: {gpu_name}")
            print(f"      当前空闲显存: {vram_free_mb:.1f} MB")
    except Exception as e:
        print(f"❌ 无法连接到 4060 ComfyUI ({base_url}): {e}")
        return False

    print(f"[2/5] 上传参考立绘: {ref_image_path} ...")
    ref_remote_name = "qwen_ref_shen_ce.png"
    try:
        up_res = upload_image(base_url, ref_image_path, ref_remote_name)
        print(f"      上传成功: {up_res.get('name', ref_remote_name)}")
    except Exception as e:
        print(f"❌ 上传参考图失败: {e}")
        return False

    if args.expression == "serious":
        prompt = (
            "Change the character's facial expression in image 1 to: stern sharp detective inquiry, "
            "intense piercing gaze, sharply angled eyebrows, firm straight set mouth, confident and intimidating. "
            "Strictly maintain the handsome youthful anime aesthetic, smooth flawless anime skin, "
            "identical 20-year-old facial structure and hairstyle as image 1, absolutely NO wrinkles, NO aging, NO nasolabial folds."
        )
        neg_prompt = (
            "wrinkles, old, aged, elderly, mature face, nasolabial folds, laugh lines, eye bags, crows feet, deep lines, "
            "sagging skin, realistic skin pores, ugly, decrepit, deformed, bad anatomy, bad hands, blurry, changed clothes, changed hairstyle"
        )
    else:
        prompt = (
            "Change the character's facial expression in image 1 to: gentle confident subtle smile, "
            "warm relaxed eyes, lips curved slightly upwards, calm atmosphere. "
            "Strictly maintain the handsome youthful anime aesthetic, smooth flawless anime skin, "
            "identical 20-year-old facial structure and hairstyle as image 1, absolutely NO wrinkles, NO aging, NO nasolabial folds."
        )
        neg_prompt = (
            "wrinkles, old, aged, elderly, mature face, nasolabial folds, laugh lines, eye bags, crows feet, deep lines, "
            "sagging skin, realistic skin pores, ugly, decrepit, deformed, bad anatomy, blurry, changed clothes, changed hairstyle"
        )

    print(f"[3/5] 构建 4060 原生 Nunchaku 差分工作流并提交 (表情: {args.expression}) ...")
    wf = build_nunchaku_edit_workflow(ref_remote_name, prompt, neg_prompt, seed=args.seed, steps=args.steps, cfg=3.5)

    req = urllib.request.Request(
        f"{base_url}/prompt",
        data=json.dumps({"prompt": wf}).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as res:
            p_res = json.loads(res.read().decode("utf-8"))
            prompt_id = p_res.get("prompt_id")
            print(f"      任务已提交, Prompt ID: {prompt_id}")
    except Exception as e:
        print(f"❌ 提交任务失败: {e}")
        return False

    print(f"[4/5] 轮询任务执行状态并监控生成 (预计耗时 ~2 分半) ...")
    start_time = time.time()
    last_print = 0

    while True:
        elapsed = time.time() - start_time
        try:
            with urllib.request.urlopen(f"{base_url}/history/{prompt_id}", timeout=5) as res:
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
                return False

            if status.get("completed", False) or item.get("outputs"):
                print(f"\n✅ 4060 渲染完成! 总耗时: {elapsed:.2f} 秒")
                outputs = item.get("outputs", {})
                save_out = outputs.get("save", {}).get("images", [])
                if not save_out:
                    print("⚠️ 未找到输出图片列表!")
                    return False
                img_info = save_out[0]
                img_fn = img_info.get("filename")
                img_sub = img_info.get("subfolder", "")
                img_type = img_info.get("type", "output")

                print(f"[5/5] 下载 4060 生成的差分原始图像: {img_fn} ...")
                query = urllib.parse.urlencode({"filename": img_fn, "subfolder": img_sub, "type": img_type})
                view_url = f"{base_url}/view?{query}"
                with urllib.request.urlopen(view_url, timeout=20) as img_res:
                    img_data = img_res.read()
                    with open(raw_gen_path, "wb") as f:
                        f.write(img_data)
                print(f"      原始图已保存至: {raw_gen_path} ({len(img_data)} 字节)")

                # 执行像素级余弦羽化与服装发型绝对锁死融合
                print(f"      执行余弦非线性羽化与发型服装绝对锁死融合 ...")
                base_pil = Image.open(ref_image_path).convert("RGBA")
                raw_gen_pil = Image.open(raw_gen_path).convert("RGBA")
                mask_pil = create_adaptive_face_mask(base_pil, prompt)
                final_blended = harmonize_and_blend(raw_gen_pil, base_pil, mask_pil)
                os.makedirs(os.path.dirname(final_out_path), exist_ok=True)
                final_blended.save(final_out_path, "PNG")
                print(f"      🎉 沈策【微笑】差分立绘成功交付: {final_out_path} ({os.path.getsize(final_out_path)} 字节)")
                return True

        if elapsed - last_print >= 5:
            last_print = elapsed
            print(f"      [4060 渲染中... 已用时 {elapsed:.1f}s]")

        time.sleep(2)

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
