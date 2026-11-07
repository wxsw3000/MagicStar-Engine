import urllib.request
import urllib.parse
import json
import time
import os
import sys

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

def build_qwen_edit_workflow(uploaded_ref_filename, prompt_text, neg_prompt_text, seed=123456, steps=20, cfg=3.5, resolution=768):
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
                "clip_name": "qwen_2.5_vl_7b_fp8_scaled.safetensors",
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
                "image_1": ["ref_img", 0]
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
                "filename_prefix": "qwen21_diff_test"
            }
        }
    }

def run_test():
    base_url = "http://192.168.3.33:8188"
    ref_image_path = "projects/case_gallery_rain/assets/images/characters/char_shen_ce.png"
    out_dir = "samples"
    os.makedirs(out_dir, exist_ok=True)
    out_file = os.path.join(out_dir, "qwen_diff_test_smile.png")

    print(f"[1/5] 检查 ComfyUI 连接: {base_url} ...")
    try:
        with urllib.request.urlopen(f"{base_url}/system_stats", timeout=5) as res:
            stats = json.loads(res.read().decode("utf-8"))
            gpu_name = stats.get("devices", [{}])[0].get("name", "Unknown GPU")
            vram_free_mb = stats.get("devices", [{}])[0].get("vram_free", 0) / (1024 * 1024)
            print(f"      GPU: {gpu_name}")
            print(f"      当前空闲显存: {vram_free_mb:.1f} MB")
    except Exception as e:
        print(f"❌ 无法连接到 ComfyUI: {e}")
        return False

    print(f"[2/5] 上传参考立绘: {ref_image_path} ...")
    ref_remote_name = "qwen_ref_shen_ce.png"
    try:
        up_res = upload_image(base_url, ref_image_path, ref_remote_name)
        print(f"      上传成功: {up_res.get('name', ref_remote_name)}")
    except Exception as e:
        print(f"❌ 上传参考图失败: {e}")
        return False

    prompt = (
        "Keep the character's facial identity, facial structure, eye shape, hairstyle, "
        "hair color, and clothing strictly identical to the reference image. "
        "Modify only the facial expression: a gentle smiling happy expression, mouth slightly open, "
        "subtle blush on cheeks, eyes curved with gentle warmth."
    )
    neg_prompt = "ugly, deformed, mutated, extra fingers, disfigured, blurry, low quality, changed clothes, changed hairstyle"

    print(f"[3/5] 构建 Qwen-Image-2.1 指令差分工作流并提交 ...")
    wf = build_qwen_edit_workflow(
        uploaded_ref_filename=ref_remote_name,
        prompt_text=prompt,
        neg_prompt_text=neg_prompt,
        seed=42,
        steps=20,
        cfg=3.5,
        resolution=768
    )

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
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8")
        print(f"❌ 任务验证/提交失败 (HTTP {e.code}): {err_body}")
        return False
    except Exception as e:
        print(f"❌ 提交请求异常: {e}")
        return False

    print(f"[4/5] 轮询任务执行状态并监控耗时与显存 (预计需要 40~90 秒) ...")
    start_time = time.time()
    last_print = 0

    while True:
        elapsed = time.time() - start_time
        try:
            with urllib.request.urlopen(f"{base_url}/history/{prompt_id}", timeout=5) as res:
                hist_data = json.loads(res.read().decode("utf-8"))
        except Exception as e:
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

                print(f"[5/5] 下载生成的差分图像: {img_fn} ...")
                query = urllib.parse.urlencode({"filename": img_fn, "subfolder": img_sub, "type": img_type})
                view_url = f"{base_url}/view?{query}"
                with urllib.request.urlopen(view_url, timeout=20) as img_res:
                    img_data = img_res.read()
                    with open(out_file, "wb") as f:
                        f.write(img_data)
                print(f"      已保存至本地: {out_file} (文件大小: {len(img_data)} 字节)")
                return True

        if elapsed - last_print >= 5:
            last_print = elapsed
            # 尝试获取实时显存
            try:
                with urllib.request.urlopen(f"{base_url}/system_stats", timeout=3) as sres:
                    s_data = json.loads(sres.read().decode("utf-8"))
                    v_free = s_data.get("devices", [{}])[0].get("vram_free", 0) / (1024 * 1024)
                    print(f"      [运行中... 已用时 {elapsed:.1f}s] 当前空闲显存: {v_free:.1f} MB")
            except Exception:
                print(f"      [运行中... 已用时 {elapsed:.1f}s]")

        time.sleep(2)

if __name__ == "__main__":
    success = run_test()
    sys.exit(0 if success else 1)
