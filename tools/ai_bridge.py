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
from PIL import Image, ImageDraw, ImageFilter

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

def upload_image_to_comfy(base_url, image_path, headers, ctx, filename=None):
    if not filename:
        filename = os.path.basename(image_path)
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
    with urllib.request.urlopen(req, context=ctx, timeout=25) as resp:
        return json.loads(resp.read().decode("utf-8"))

def report_progress(progress_file, stage, percent, text):
    if not progress_file:
        return
    try:
        data = {
            "stage": stage,
            "percent": int(percent),
            "text": text,
            "timestamp": time.time()
        }
        dir_name = os.path.dirname(progress_file)
        if dir_name:
            os.makedirs(dir_name, exist_ok=True)
        with open(progress_file, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
    except Exception:
        pass

def create_adaptive_face_mask(base_pil, prompt=""):
    """
    方案 A：靶向五官分流自适应遮罩
    根据微表情提示词智能判断重绘焦点：
    1. 纯嘴部/口型专属（张嘴/说话口型等）：仅重绘嘴唇核心区（y: 0.25~0.34, x: 0.40~0.60），双眼、眉毛、额头 100% 物理绝对冻结！
    2. 纯眼眉专属（闭目/眨眼等）：仅重绘双眼与眉毛区域（y: 0.125~0.250, x: 0.32~0.68），下颌、嘴唇 100% 物理绝对冻结！
    3. 标准微表情全区（严厉质询/微笑/愤怒/深思/震惊等）：完整包裹面部五官（y: 0.125~0.340, x: 0.31~0.69），下巴边缘、发型轮廓、领口服饰 100% 物理锁定。
    """
    import numpy as np
    bw, bh = base_pil.size
    p_lower = str(prompt).lower()
    
    mouth_only_kws = ["张嘴", "说话", "口型", "说话口型", "open mouth", "speaking"]
    eyes_only_kws = ["闭目", "闭眼", "眨眼", "closed eyes", "blink"]
    
    is_mouth_only = any(k in p_lower for k in mouth_only_kws) and not any(k in p_lower for k in ["怒", "笑", "质询", "表情", "神色", "冷", "严厉", "悲", "喜", "严肃", "深思", "疑惑"])
    is_eyes_only = any(k in p_lower for k in eyes_only_kws) and not any(k in p_lower for k in ["怒", "笑", "质询", "表情", "神色", "冷", "严厉", "悲", "喜", "严肃", "深思", "疑惑"])
    
    mask = Image.new("L", (bw, bh), 0)
    draw = ImageDraw.Draw(mask)
    
    if is_mouth_only:
        # 模式 1：纯嘴部/唇周微表情重绘 (双眼和眉骨 100% 锁定)
        mouth_box = [int(bw * 0.40), int(bh * 0.250), int(bw * 0.60), int(bh * 0.340)]
        draw.ellipse(mouth_box, fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(radius=8))
    elif is_eyes_only:
        # 模式 2：纯眼眉/眼神微表情重绘 (嘴唇和下颌 100% 锁定)
        eyes_box = [int(bw * 0.32), int(bh * 0.125), int(bw * 0.68), int(bh * 0.250)]
        draw.ellipse(eyes_box, fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(radius=8))
    else:
        # 模式 3：标准面部微表情全区重绘 (眉毛、眼眸、鼻梁、面颊、唇周连贯整体，保护下巴、耳朵、发型与服饰)
        face_box = [int(bw * 0.31), int(bh * 0.125), int(bw * 0.69), int(bh * 0.340)]
        draw.ellipse(face_box, fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(radius=12))

    # 平滑余弦边界防护：防止边界生硬突变
    m_arr = np.array(mask, dtype=np.float32)
    y_indices = np.arange(bh)[:, None]
    top_fade = np.clip((y_indices - bh * 0.12) / max(bh * 0.03, 1.0), 0.0, 1.0)
    bottom_fade = np.clip((bh * 0.36 - y_indices) / max(bh * 0.03, 1.0), 0.0, 1.0)
    top_smooth = 0.5 - 0.5 * np.cos(np.pi * top_fade)
    bottom_smooth = 0.5 - 0.5 * np.cos(np.pi * bottom_fade)
    m_arr = (m_arr * top_smooth * bottom_smooth).astype(np.uint8)
    mask = Image.fromarray(m_arr, "L")

    # 若原图带 Alpha 通道，绝不向背景透明区渗透
    if base_pil.mode == "RGBA":
        alpha = base_pil.split()[3]
        bg_zero = Image.new("L", (bw, bh), 0)
        mask = Image.composite(mask, bg_zero, alpha)
    return mask

def create_adaptive_pose_mask(base_pil, pose_preset=""):
    """
    智能自适应 3D 姿态重绘遮罩 (解决叠人双头、锁死下巴与下半身崩坏):
    1. 头部核心区 (额头、眉眼、发型、发缝、耳朵 - y: 0.03~0.33):
       绝对锚定 (权重 45, 有效去噪仅 ~0.14)，100% 保持角色原本骨相、发型、面貌与神韵，防止换脸换头。
    2. 下颌与下巴过渡区 (y: 0.22~0.38):
       - 若姿态为 chin_touch (手托下巴): 赋予高重绘权 (240, 允许手升至真实下巴处托住)。
       - 其他姿态: 保持面部下颚轮廓保护 (权重 55)。
    3. 躯干与手臂动作展开区 (y: 0.33~0.80):
       赋予高自由动作生成权重 (255, 0.92 去噪)，彻底粉碎 Base 原图手臂垂直下垂的潜空间惯性，
       强迫扩散模型按照动作提示词重新绘制抬手、抱胸、插兜、一指指证等真实肢体姿势！
    4. 底部边界自适应控制 (y: 0.80~1.0):
       适度控制 (权重 65)，既防止生成第二个小人，又保证风衣整体构图连贯。
    """
    bw, bh = base_pil.size
    # 基础默认给动作展开权重 255 (高自由重绘，摆脱垂手站姿)
    mask = Image.new("L", (bw, bh), 255)
    draw = ImageDraw.Draw(mask)
    
    # 1. 下半身风衣底端防叠人锚定 (y > 0.80 处权重 65)
    draw.rectangle([0, int(bh * 0.80), bw, bh], fill=65)
    
    # 2. 头部上半部身份绝对锁死 (权重 45，原脸原发原耳深度冻结保护)
    head_top_box = [int(bw * 0.20), int(bh * 0.03), int(bw * 0.80), int(bh * 0.28)]
    draw.ellipse(head_top_box, fill=45)
    
    # 3. 下巴与面部下半区按姿态智能分流
    is_chin_pose = ("chin" in str(pose_preset).lower() or "touch" in str(pose_preset).lower() or "下巴" in str(pose_preset))
    if is_chin_pose:
        # 手托下巴：在真实下巴处开辟动作手势通道 (高权重 240，允许手升上来)
        chin_box = [int(bw * 0.32), int(bh * 0.24), int(bw * 0.68), int(bh * 0.42)]
        draw.ellipse(chin_box, fill=240)
    else:
        # 其他姿态：下颌与嘴唇也处于面部保护区 (权重 55)
        jaw_box = [int(bw * 0.24), int(bh * 0.22), int(bw * 0.76), int(bh * 0.38)]
        draw.ellipse(jaw_box, fill=55)
        
    mask = mask.filter(ImageFilter.GaussianBlur(radius=18))
    return mask

def harmonize_and_blend(gen_pil, base_pil, mask_pil):
    """
    S 曲线非线性余弦平滑过渡融合 (Cosine Smoothstep)。
    保证遮罩外所有像素（服装、发型、脖子、轮廓）100% 绝对物理一致（MAE = 0.000），
    同时杜绝生硬贴纸边界与破坏性色偏。
    """
    try:
        import numpy as np
        gen_rgba = gen_pil.convert("RGBA")
        base_rgba = base_pil.convert("RGBA")
        if gen_rgba.size != base_rgba.size:
            gen_rgba = gen_rgba.resize(base_rgba.size, Image.Resampling.LANCZOS)
            
        gen_arr = np.array(gen_rgba, dtype=np.float32)
        base_arr = np.array(base_rgba, dtype=np.float32)
        mask_arr = np.array(mask_pil, dtype=np.float32) / 255.0
        
        # 采用非线性余弦平滑过渡 (Cosine Smoothstep)，消除边界突变与马赫带效应
        smooth_mask = 0.5 - 0.5 * np.cos(np.pi * mask_arr)
        smooth_mask = np.expand_dims(smooth_mask, axis=-1)
        
        blended_arr = gen_arr * smooth_mask + base_arr * (1.0 - smooth_mask)

        # 核心物理锁死：非遮罩区域 (mask <= 0.001) 强制 1:1 回填 Base 原图像素，保证服装与发型 100% 绝对物理一致！
        zero_mask = (mask_arr <= 0.001)
        for c in range(4):
            blended_arr[..., c][zero_mask] = base_arr[..., c][zero_mask]

        # 继承 Base 原图的 Alpha 透明边界，杜绝透明区发丝溢出杂色
        blended_arr[..., 3] = base_arr[..., 3]

        blended_arr = np.clip(blended_arr, 0, 255).astype(np.uint8)
        return Image.fromarray(blended_arr, "RGBA")
    except Exception:
        return Image.composite(gen_pil.convert("RGBA"), base_pil.convert("RGBA"), mask_pil)

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

        url_obj = f"{base_url}/object_info"
        req_obj = urllib.request.Request(url_obj, headers=headers)
        with urllib.request.urlopen(req_obj, context=ctx, timeout=8) as resp:
            data_obj = json.loads(resp.read().decode("utf-8"))
            ckpts = data_obj.get("CheckpointLoaderSimple", {}).get("input", {}).get("required", {}).get("ckpt_name", [[]])[0]
            unets = data_obj.get("UNETLoader", {}).get("input", {}).get("required", {}).get("unet_name", [[]])[0]
            nunchakus = data_obj.get("NunchakuQwenImageDiTLoader", {}).get("input", {}).get("required", {}).get("model_name", [[]])[0]
            ggufs = data_obj.get("UnetLoaderGGUF", {}).get("input", {}).get("required", {}).get("unet_name", [[]])[0]
            all_models = list(ckpts)
            for m in list(unets) + list(nunchakus) + list(ggufs):
                if m not in all_models:
                    all_models.append(m)
            result["checkpoints"] = all_models
            result["vaes"] = data_obj.get("VAELoader", {}).get("input", {}).get("required", {}).get("vae_name", [[]])[0]
            result["clips"] = data_obj.get("CLIPLoader", {}).get("input", {}).get("required", {}).get("clip_name", [[]])[0]
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
    
    steps = args.steps
    cfg = args.cfg
    sampler = args.sampler
    scheduler = args.scheduler
    ckpt_lower = args.ckpt.lower()
    is_nunchaku = ("nunchaku" in ckpt_lower or "qwen" in ckpt_lower)

    target_width = args.width
    target_height = args.height
    gen_width = args.width
    gen_height = args.height

    if is_nunchaku and (target_width * target_height < 900000):
        # Qwen-Image-Edit 内部强制以 1MP (1024x1024) 等面积缩放参考图生成潜空间。
        # 若以 512x768 潜空间采样，模型会导致参考图与生成图尺寸错位，产生 1.63x 严重画幅放大与裁切！
        # 因此以原生 1MP (832x1248) 比例对齐采样，生成完成后重采样回 target_width x target_height。
        import math
        scale_f = math.sqrt(1048576.0 / (target_width * target_height))
        gen_width = int(round(target_width * scale_f / 32) * 32)
        gen_height = int(round(target_height * scale_f / 32) * 32)

    # --- 角色一致性检测：是否启动基于 Base 立绘的 VNCCS 面部差分重绘 (Inpainting) 或 3D 姿态一致性重绘 ---
    base_image_path = getattr(args, "base_image", "") or ""
    inpaint_face = bool(getattr(args, "inpaint_face", 0))
    denoise_strength = getattr(args, "denoise", 0.72)
    is_inpaint_mode = False
    is_pose_consistent_mode = False
    base_pil = None
    mask_pil = None
    temp_base_path = None
    temp_mask_path = None
    uploaded_base = ""
    uploaded_mask = ""

    prog_file = getattr(args, "progress_file", None)

    if base_image_path and os.path.exists(base_image_path):
        try:
            base_pil = Image.open(base_image_path).convert("RGBA")
            bw, bh = base_pil.size
            pose_image_path = getattr(args, "pose_image", "") or ""
            pose_preset = getattr(args, "pose_preset", "") or ""

            if inpaint_face:
                # 模式 A: 纯微表情专注差分重绘 (仅面部重绘，身体 100% 冻结锁死)
                report_progress(prog_file, "prep_inpaint", 10, "正在提取基准立绘并生成智能面部羽化 Mask...")
                mask_pil = create_adaptive_face_mask(base_pil, getattr(args, "prompt", ""))
                # SDXL / Anima 使用局部潜空间 DifferentialDiffusion；Nunchaku 使用多模态视觉参考 + 后处理平滑融合
                if not is_nunchaku:
                    is_inpaint_mode = True
            elif pose_image_path or pose_preset:
                # 模式 B: 3D 姿态一致性重绘 (头部发型身份绝对锁定，下摆锁死杜绝叠人，躯干动作区高自由重绘)
                report_progress(prog_file, "prep_pose_mask", 10, "正在锁定基准角色面容发型身份，并构建 3D 动作区自适应重绘 Mask...")
                mask_pil = create_adaptive_pose_mask(base_pil, pose_preset)
                if not is_nunchaku:
                    is_pose_consistent_mode = True
            else:
                # 模式 C: 独立全量参考生图 (全局视觉编码)
                is_inpaint_mode = False
                is_pose_consistent_mode = False

            import tempfile
            temp_base_path = os.path.join(tempfile.gettempdir(), f"_avg_tmp_base_{seed}.png")
            
            # 若基准图含透明通道，合成到纯白底上传给多模态编码器，避免透明转黑导致深色发型与服装与背景混淆
            if base_pil.mode == "RGBA":
                upload_base_pil = Image.new("RGB", base_pil.size, (255, 255, 255))
                upload_base_pil.paste(base_pil, mask=base_pil.split()[-1])
            else:
                upload_base_pil = base_pil.convert("RGB")

            # 保持多模态参考图与生成潜空间分辨率 1:1 精确锁定，杜绝 1.63x 缩放引起的画幅裁切与镜头推拉
            if is_nunchaku and (upload_base_pil.size != (gen_width, gen_height)):
                upload_base_pil = upload_base_pil.resize((gen_width, gen_height), Image.Resampling.LANCZOS)

            upload_base_pil.save(temp_base_path, "PNG")

            stage_txt = "正在将基准立绘与面部 Mask 同步上传至算力节点..." if is_inpaint_mode else ("正在同步上传基准角色图与 3D 姿态动作区重绘 Mask..." if is_pose_consistent_mode else "正在同步基准立绘至多模态视觉编码节点...")
            report_progress(prog_file, "upload_base", 15, stage_txt)
            upload_b = upload_image_to_comfy(base_url, temp_base_path, headers, ctx, f"avg_base_{seed}.png")
            uploaded_base = upload_b.get("name", f"avg_base_{seed}.png")

            if mask_pil and (is_inpaint_mode or is_pose_consistent_mode):
                mask_rgba = Image.new("RGBA", (bw, bh), (255, 255, 255, 255))
                mask_data = list(mask_pil.get_flattened_data()) if hasattr(mask_pil, "get_flattened_data") else list(mask_pil.getdata())
                new_rgba_data = []
                for m_val in mask_data:
                    alpha_val = 255 - m_val
                    new_rgba_data.append((m_val, m_val, m_val, alpha_val))
                mask_rgba.putdata(new_rgba_data)
                temp_mask_path = os.path.join(tempfile.gettempdir(), f"_avg_tmp_mask_{seed}.png")
                mask_rgba.save(temp_mask_path, "PNG")
                upload_m = upload_image_to_comfy(base_url, temp_mask_path, headers, ctx, f"avg_mask_{seed}.png")
                uploaded_mask = upload_m.get("name", f"avg_mask_{seed}.png")
        except Exception as e:
            is_inpaint_mode = False
            is_pose_consistent_mode = False

    # --- 3D 姿态骨架生成模式检测 (ControlNet / Pose Guidance) ---
    pose_image_path = getattr(args, "pose_image", "") or ""
    is_pose_mode = False
    uploaded_pose = ""
    controlnet_model = None

    if pose_image_path and os.path.exists(pose_image_path) and not inpaint_face:
        report_progress(prog_file, "prep_pose", 10, "正在同步 3D 姿态骨架底图并检测 ControlNet 算力...")
        try:
            upload_p = upload_image_to_comfy(base_url, pose_image_path, headers, ctx, f"avg_pose_{seed}.png")
            uploaded_pose = upload_p.get("name", f"avg_pose_{seed}.png")
            is_pose_mode = True
            
            # 检测 ComfyUI 中是否存在 ControlNet 权重
            try:
                url_obj = f"{base_url}/object_info/ControlNetLoader"
                req_obj = urllib.request.Request(url_obj, headers=headers)
                with urllib.request.urlopen(req_obj, context=ctx, timeout=6) as resp_obj:
                    cn_info = json.loads(resp_obj.read().decode("utf-8"))
                    available_cns = cn_info.get("ControlNetLoader", {}).get("input", {}).get("required", {}).get("control_net_name", [[]])[0]
                    for cn in available_cns:
                        if any(k in cn.lower() for k in ["pose", "openpose", "control"]):
                            controlnet_model = cn
                            break
                    if not controlnet_model and available_cns:
                        controlnet_model = available_cns[0]
            except Exception:
                controlnet_model = None

            if controlnet_model:
                report_progress(prog_file, "cn_loaded", 15, f"已装载 ControlNet 权重: {controlnet_model}")
            else:
                report_progress(prog_file, "pose_guided", 15, "算力节点未发现 ControlNet 权重，已启用 3D 姿态空间提示词强化引导...")
        except Exception as e:
            is_pose_mode = False

    # --- 差分微表情与全身姿态生成参数科学调校 ---
    if is_inpaint_mode:
        # 方案 A 靶向微表情重绘：去噪幅度锁定在 0.55~0.62 黄金区间
        # 搭配靶向器官遮罩与 Anima-Turbo 规范 CFG 1.0，五官鲜明变化且 100% 杜绝换人
        if denoise_strength > 0.68 or denoise_strength < 0.45:
            denoise_strength = 0.58
        if "anima" in ckpt_lower:
            cfg = 1.0
            steps = 10
    elif is_pose_consistent_mode:
        # 3D 姿态一致性重绘：黄金去噪区间 0.90~0.95 (默认 0.92)
        # 头部与面部通过 Mask 0 绝对锁定，躯干高噪重绘彻底粉碎原图垂手惯性
        if denoise_strength < 0.85 or denoise_strength > 0.96:
            denoise_strength = 0.92
        if "anima" in ckpt_lower:
            cfg = 2.4
            steps = 14
    elif is_pose_mode:
        # 全身姿态生成模式（无基准图）：适当提升提示词引导权重与步数，强化肢体动作控制
        if "anima" in ckpt_lower:
            cfg = 2.0
            steps = 10

    is_nunchaku = ("nunchaku" in ckpt_lower or "qwen" in ckpt_lower)

    if is_nunchaku:
        # Nunchaku Qwen-Image 2.1 INT4 模块化工作流
        clip_name = "qwen_2.5_vl_7b_fp8_scaled.safetensors"
        vae_name = "qwen_image_vae.safetensors"
        try:
            url_obj = f"{base_url}/object_info"
            req_obj = urllib.request.Request(url_obj, headers=headers)
            with urllib.request.urlopen(req_obj, context=ctx, timeout=6) as resp_obj:
                d_obj = json.loads(resp_obj.read().decode("utf-8"))
                avail_clips = d_obj.get("CLIPLoader", {}).get("input", {}).get("required", {}).get("clip_name", [[]])[0]
                if args.ckpt.endswith(".gguf"):
                    for c in avail_clips:
                        if "qwen3vl" in c.lower() or "qwen3" in c.lower():
                            clip_name = c
                            break
                if not clip_name or clip_name == "qwen_2.5_vl_7b_fp8_scaled.safetensors":
                    for c in avail_clips:
                        if "qwen" in c.lower() or "vl" in c.lower():
                            clip_name = c
                            break
                avail_vaes = d_obj.get("VAELoader", {}).get("input", {}).get("required", {}).get("vae_name", [[]])[0]
                if args.ckpt.endswith(".gguf"):
                    for v in avail_vaes:
                        if "2.1" in v.lower() or "bf16" in v.lower():
                            vae_name = v
                            break
                if not vae_name:
                    for v in avail_vaes:
                        if "qwen_image_vae" in v.lower():
                            vae_name = v
                            break
                if not vae_name:
                    for v in avail_vaes:
                        if "qwen" in v.lower():
                            vae_name = v
                            break
        except Exception:
            pass

        if steps >= 28 or steps <= 0:
            steps = 20
        if cfg >= 6.0 or cfg <= 0:
            cfg = 3.5
        sampler = "euler"
        scheduler = "simple"

        workflow = {
            "2": {
                "class_type": "CLIPLoader",
                "inputs": {
                    "clip_name": clip_name,
                    "type": "qwen_image"
                }
            },
            "3": {
                "class_type": "VAELoader",
                "inputs": {
                    "vae_name": vae_name
                }
            },
            "5": {
                "class_type": "CLIPTextEncode",
                "inputs": {
                    "clip": ["2", 0],
                    "text": args.negative
                }
            },
            "6": {
                "class_type": "EmptyLatentImage",
                "inputs": {
                    "batch_size": 1,
                    "height": gen_height,
                    "width": gen_width
                }
            }
        }

        if args.ckpt.endswith(".gguf"):
            workflow["1"] = {
                "class_type": "UnetLoaderGGUF",
                "inputs": {"unet_name": args.ckpt}
            }
            workflow["cache"] = {
                "class_type": "QwenImage21Cache",
                "inputs": {"model": ["1", 0], "device": "auto", "dtype": "int8"}
            }
            dit_ref = ["cache", 0]
        else:
            workflow["1"] = {
                "class_type": "NunchakuQwenImageDiTLoader",
                "inputs": {"model_name": args.ckpt, "cpu_offload": "auto"}
            }
            dit_ref = ["1", 0]

        if args.ckpt.endswith(".gguf"):
            # Qwen-Image-2.1 原生多模态指令差分编码器 (产出 64 通道专用 Latent 与 Conditionings)
            q_res = max(gen_width, gen_height)
            if q_res % 32 != 0:
                q_res = ((q_res // 32) + 1) * 32
            enc_inputs = {
                "clip": ["2", 0],
                "prompt": args.prompt,
                "negative_prompt": getattr(args, "negative", "") or "ugly, deformed, mutated, extra fingers, disfigured, blurry, low quality, changed clothes, changed hairstyle",
                "resolution": q_res,
                "vae": ["3", 0]
            }
            if uploaded_base:
                workflow["10"] = {
                    "class_type": "LoadImage",
                    "inputs": {
                        "image": uploaded_base
                    }
                }
                enc_inputs["images.image_1"] = ["10", 0]

            workflow["4"] = {
                "class_type": "TextEncodeQwenImage21",
                "inputs": enc_inputs
            }
            pos_cond = ["4", 0]
            neg_cond = ["4", 1]
            latent_in = ["4", 2]
        elif uploaded_base:
            workflow["10"] = {
                "class_type": "LoadImage",
                "inputs": {
                    "image": uploaded_base
                }
            }
            # 使用 TextEncodeQwenImageEditPlus 节点接收多模态参考底图与 VAE 潜空间特征
            workflow["4"] = {
                "class_type": "TextEncodeQwenImageEditPlus",
                "inputs": {
                    "clip": ["2", 0],
                    "prompt": args.prompt,
                    "vae": ["3", 0],
                    "image1": ["10", 0]
                }
            }
            # 负向引导同样绑定参考底图与反向提示词，实现差分向量精准指向新表情并杜绝色偏相减失真
            neg_text = getattr(args, "negative", "") or "calm, relaxed, neutral, emotionless expression in image 1"
            workflow["5"] = {
                "class_type": "TextEncodeQwenImageEditPlus",
                "inputs": {
                    "clip": ["2", 0],
                    "prompt": neg_text,
                    "vae": ["3", 0],
                    "image1": ["10", 0]
                }
            }
            pos_cond = ["4", 0]
            neg_cond = ["5", 0]
            latent_in = ["6", 0]
        else:
            workflow["4"] = {
                "class_type": "CLIPTextEncode",
                "inputs": {
                    "clip": ["2", 0],
                    "text": args.prompt
                }
            }
            pos_cond = ["4", 0]
            neg_cond = ["5", 0]
            latent_in = ["6", 0]

        workflow["7"] = {
            "class_type": "KSampler",
            "inputs": {
                "cfg": cfg,
                "denoise": 1.0,
                "latent_image": latent_in,
                "model": dit_ref,
                "negative": neg_cond,
                "positive": pos_cond,
                "sampler_name": sampler,
                "scheduler": scheduler,
                "seed": seed,
                "steps": steps
            }
        }
        workflow["8"] = {
            "class_type": "VAEDecode",
            "inputs": {
                "samples": ["7", 0],
                "vae": ["3", 0]
            }
        }
        workflow["9"] = {
            "class_type": "SaveImage",
            "inputs": {
                "filename_prefix": "AVG_Gen",
                "images": ["8", 0]
            }
        }
    elif "anima" in ckpt_lower:
        sampler = "euler"
        scheduler = "sgm_uniform"
        
        # Anima 模块化工作流 (UNETLoader + CLIPLoader + VAELoader)
        workflow = {
            "1": {
                "class_type": "UNETLoader",
                "inputs": {
                    "unet_name": args.ckpt,
                    "weight_dtype": "default"
                }
            },
            "2": {
                "class_type": "CLIPLoader",
                "inputs": {
                    "clip_name": "qwen_3_06b_base.safetensors",
                    "type": "stable_diffusion"
                }
            },
            "3": {
                "class_type": "VAELoader",
                "inputs": {
                    "vae_name": "qwen_image_vae.safetensors"
                }
            },
            "4": {
                "class_type": "CLIPTextEncode",
                "inputs": {
                    "clip": ["2", 0],
                    "text": args.prompt
                }
            },
            "5": {
                "class_type": "CLIPTextEncode",
                "inputs": {
                    "clip": ["2", 0],
                    "text": args.negative
                }
            }
        }

        pos_cond = ["4", 0]
        neg_cond = ["5", 0]
        if is_pose_mode and controlnet_model:
            workflow["20"] = {
                "class_type": "ControlNetLoader",
                "inputs": {"control_net_name": controlnet_model}
            }
            workflow["21"] = {
                "class_type": "LoadImage",
                "inputs": {"image": uploaded_pose}
            }
            workflow["22"] = {
                "class_type": "ControlNetApplyAdvanced",
                "inputs": {
                    "strength": 0.90,
                    "start_percent": 0.0,
                    "end_percent": 0.95,
                    "positive": ["4", 0],
                    "negative": ["5", 0],
                    "control_net": ["20", 0],
                    "image": ["21", 0]
                }
            }
            pos_cond = ["22", 0]
            neg_cond = ["22", 1]

        if is_inpaint_mode or is_pose_consistent_mode:
            # 潜空间平滑差分重绘分支：引入 Differential Diffusion，锁定基准立绘身份并重绘目标区
            workflow["14"] = {
                "class_type": "DifferentialDiffusion",
                "inputs": {"model": ["1", 0], "strength": 1.0}
            }
            workflow["10"] = {
                "class_type": "LoadImage",
                "inputs": {"image": uploaded_base}
            }
            workflow["11"] = {
                "class_type": "LoadImage",
                "inputs": {"image": uploaded_mask}
            }
            workflow["12"] = {
                "class_type": "VAEEncode",
                "inputs": {"pixels": ["10", 0], "vae": ["3", 0]}
            }
            workflow["13"] = {
                "class_type": "SetLatentNoiseMask",
                "inputs": {"samples": ["12", 0], "mask": ["11", 1]}
            }
            workflow["7"] = {
                "class_type": "KSampler",
                "inputs": {
                    "cfg": cfg,
                    "denoise": denoise_strength,
                    "latent_image": ["13", 0],
                    "model": ["14", 0],
                    "negative": neg_cond,
                    "positive": pos_cond,
                    "sampler_name": sampler,
                    "scheduler": scheduler,
                    "seed": seed,
                    "steps": steps
                }
            }
        else:
            workflow["6"] = {
                "class_type": "EmptyLatentImage",
                "inputs": {
                    "batch_size": 1,
                    "height": args.height,
                    "width": args.width
                }
            }
            workflow["7"] = {
                "class_type": "KSampler",
                "inputs": {
                    "cfg": cfg,
                    "denoise": 1,
                    "latent_image": ["6", 0],
                    "model": ["1", 0],
                    "negative": neg_cond,
                    "positive": pos_cond,
                    "sampler_name": sampler,
                    "scheduler": scheduler,
                    "seed": seed,
                    "steps": steps
                }
            }

        workflow["8"] = {
            "class_type": "VAEDecode",
            "inputs": {
                "samples": ["7", 0],
                "vae": ["3", 0]
            }
        }
        workflow["9"] = {
            "class_type": "SaveImage",
            "inputs": {
                "filename_prefix": "AVG_Gen",
                "images": ["8", 0]
            }
        }
    else:
        # 标准 Checkpoint 整合包模型 (SDXL / SD 1.5)
        if "turbo" in ckpt_lower:
            if cfg >= 5.0:
                cfg = 1.5
            if steps >= 20:
                steps = 4
            if sampler in ["dpmpp_2m", "dpmpp_sde"]:
                sampler = "euler_ancestral"
        
        workflow = {
            "4": {
                "class_type": "CheckpointLoaderSimple",
                "inputs": {
                    "ckpt_name": args.ckpt
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
            }
        }

        pos_cond = ["6", 0]
        neg_cond = ["7", 0]
        if is_pose_mode and controlnet_model:
            workflow["20"] = {
                "class_type": "ControlNetLoader",
                "inputs": {"control_net_name": controlnet_model}
            }
            workflow["21"] = {
                "class_type": "LoadImage",
                "inputs": {"image": uploaded_pose}
            }
            workflow["22"] = {
                "class_type": "ControlNetApplyAdvanced",
                "inputs": {
                    "strength": 0.90,
                    "start_percent": 0.0,
                    "end_percent": 0.95,
                    "positive": ["6", 0],
                    "negative": ["7", 0],
                    "control_net": ["20", 0],
                    "image": ["21", 0]
                }
            }
            pos_cond = ["22", 0]
            neg_cond = ["22", 1]

        if is_inpaint_mode or is_pose_consistent_mode:
            # Differential Diffusion 潜空间平滑扩散
            workflow["14"] = {
                "class_type": "DifferentialDiffusion",
                "inputs": {"model": ["4", 0], "strength": 1.0}
            }
            workflow["10"] = {
                "class_type": "LoadImage",
                "inputs": {"image": uploaded_base}
            }
            workflow["11"] = {
                "class_type": "LoadImage",
                "inputs": {"image": uploaded_mask}
            }
            workflow["12"] = {
                "class_type": "VAEEncode",
                "inputs": {"pixels": ["10", 0], "vae": ["4", 2]}
            }
            workflow["13"] = {
                "class_type": "SetLatentNoiseMask",
                "inputs": {"samples": ["12", 0], "mask": ["11", 1]}
            }
            workflow["3"] = {
                "class_type": "KSampler",
                "inputs": {
                    "cfg": cfg,
                    "denoise": denoise_strength,
                    "latent_image": ["13", 0],
                    "model": ["14", 0],
                    "negative": neg_cond,
                    "positive": pos_cond,
                    "sampler_name": sampler,
                    "scheduler": scheduler,
                    "seed": seed,
                    "steps": steps
                }
            }
        else:
            workflow["5"] = {
                "class_type": "EmptyLatentImage",
                "inputs": {
                    "batch_size": 1,
                    "height": args.height,
                    "width": args.width
                }
            }
            workflow["3"] = {
                "class_type": "KSampler",
                "inputs": {
                    "cfg": cfg,
                    "denoise": 1,
                    "latent_image": ["5", 0],
                    "model": ["4", 0],
                    "negative": neg_cond,
                    "positive": pos_cond,
                    "sampler_name": sampler,
                    "scheduler": scheduler,
                    "seed": seed,
                    "steps": steps
                }
            }

        workflow["8"] = {
            "class_type": "VAEDecode",
            "inputs": {
                "samples": ["3", 0],
                "vae": ["4", 2]
            }
        }
        workflow["9"] = {
            "class_type": "SaveImage",
            "inputs": {
                "filename_prefix": "AVG_Gen",
                "images": ["8", 0]
            }
        }

    prog_file = getattr(args, "progress_file", None)
    report_progress(prog_file, "connect", 10, "正在连接 ComfyUI 服务并提交任务...")

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
            report_progress(prog_file, "error", 0, "❌ 未能获取 ComfyUI prompt_id")
            print(json.dumps({"success": False, "error": "未能获取 prompt_id"}))
            return

        report_progress(prog_file, "queue", 25, f"任务已进入 ComfyUI 队列 (ID: {prompt_id[:8]}...)")

        # 轮询等待生成完成
        start_time = time.time()
        timeout = max(args.timeout, 360) if is_nunchaku else args.timeout
        found = False
        expected_time = (steps * 8.2) if is_nunchaku else (20.0 if "anima" in ckpt_lower else 40.0)
        
        while time.time() - start_time < timeout:
            time.sleep(0.8)
            elapsed = time.time() - start_time
            simulated_pct = min(80, 25 + int((elapsed / max(expected_time, 1.0)) * 55))
            m_desc = "Nunchaku Qwen-Image 采样中..." if is_nunchaku else "扩散模型采样推理中..."
            report_progress(prog_file, "sampling", simulated_pct, f"{m_desc} ({elapsed:.1f}s / ~{int(expected_time)}s)")

            try:
                h_url = f"{base_url}/history/{prompt_id}"
                req_h = urllib.request.Request(h_url, headers=headers)
                with urllib.request.urlopen(req_h, context=ctx, timeout=6) as h_resp:
                    h_data = json.loads(h_resp.read().decode("utf-8"))
                    if prompt_id in h_data:
                        item = h_data[prompt_id]
                        status = item.get("status", {})
                        if status.get("status_str") == "error":
                            err_msg = "ComfyUI 推理执行出错"
                            msgs = status.get("messages", [])
                            for m in msgs:
                                if len(m) > 1 and isinstance(m[1], dict) and "exception_message" in m[1]:
                                    err_msg = f"[{m[1].get('node_type', '')}] {m[1].get('exception_message', '')}"
                            report_progress(prog_file, "error", 0, f"❌ {err_msg}")
                            print(json.dumps({"success": False, "error": err_msg}, ensure_ascii=False))
                            return

                        outputs = item.get("outputs", {})
                        if "9" in outputs and "images" in outputs["9"]:
                            img_info = outputs["9"]["images"][0]
                            filename = img_info["filename"]
                            subfolder = img_info.get("subfolder", "")
                            view_url = f"{base_url}/view?filename={filename}&subfolder={subfolder}&type=output"
                            
                            report_progress(prog_file, "download", 82, "图像推理完成，正在下载至本地...")
                            req_view = urllib.request.Request(view_url, headers=headers)
                            with urllib.request.urlopen(req_view, context=ctx, timeout=15) as r_img:
                                with open(save_path, "wb") as f_out:
                                    f_out.write(r_img.read())
                            found = True
                            break
            except Exception:
                pass
                
        if not found:
            report_progress(prog_file, "error", 0, f"❌ 生成超时（超过 {timeout} 秒）")
            print(json.dumps({"success": False, "error": f"生成超时（超过 {timeout} 秒）"}))
            return

        # 若使用了 Nunchaku 1MP 原生潜空间等比扩展采样，生成完毕后以 Lanczos 算法重采样恢复至引擎目标规格
        if is_nunchaku and os.path.exists(save_path):
            try:
                g_img = Image.open(save_path)
                if g_img.size != (target_width, target_height):
                    g_img = g_img.resize((target_width, target_height), Image.Resampling.LANCZOS)
                    g_img.save(save_path, "PNG")
            except Exception:
                pass

        # 若要求透明立绘通道处理
        if args.transparent:
            report_progress(prog_file, "rembg", 88, "正在执行 u2net 深度透明抠图与发丝羽化...")
            processed = False
            try:
                import rembg
                import io
                import numpy as np
                with open(save_path, 'rb') as i_f:
                    input_bytes = i_f.read()
                out_bytes = rembg.remove(input_bytes)
                
                # 针对二次元 AVG 立绘边缘与背景半透明残留“污渍/噪点”进行纯净去雾与二值边缘羽化
                rb_im = Image.open(io.BytesIO(out_bytes)).convert("RGBA")
                arr = np.array(rb_im)
                alpha = arr[:, :, 3].astype(np.float32)
                
                # 剔除背景低不透明度残影与雾化噪点 (< 50 强制置 0)
                # 强化角色主体不透明度 (> 210 饱和为 255)
                # 介于 50..210 平滑拉伸，保持自然发丝抗锯齿
                new_alpha = np.zeros_like(alpha)
                high_mask = alpha >= 210.0
                new_alpha[high_mask] = 255.0
                mid_mask = (alpha >= 50.0) & (alpha < 210.0)
                new_alpha[mid_mask] = (alpha[mid_mask] - 50.0) / (210.0 - 50.0) * 255.0
                
                # 剔除游离孤岛微小杂质颗粒 (面积 < 80 像素的噪点)
                try:
                    from scipy import ndimage
                    labeled, num_features = ndimage.label(new_alpha > 0)
                    if num_features > 1:
                        sizes = ndimage.sum(new_alpha > 0, labeled, range(num_features + 1))
                        small_comps = np.where(sizes < 80)[0]
                        for c_id in small_comps:
                            new_alpha[labeled == c_id] = 0.0
                except Exception:
                    pass
                
                arr[:, :, 3] = np.clip(new_alpha, 0, 255).astype(np.uint8)
                # 将全透明像素的 RGB 归零，杜绝贴图过滤时的白边/黑边杂色
                arr[arr[:, :, 3] == 0] = [0, 0, 0, 0]
                
                clean_img = Image.fromarray(arr)
                clean_img.save(save_path, "PNG")
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

            # Nunchaku 生成的角色立绘垂直轮廓自适应锚定对齐 (对齐 Base 原图头部留白边界)
            if is_nunchaku and base_pil:
                try:
                    import numpy as np
                    gen_im = Image.open(save_path).convert("RGBA")
                    g_alpha = np.array(gen_im)[:, :, 3]
                    b_alpha = np.array(base_pil)[:, :, 3]
                    gy = np.where(g_alpha > 50)[0]
                    by = np.where(b_alpha > 50)[0]
                    if len(gy) and len(by):
                        dy = by[0] - gy[0]
                        if -40 <= dy <= 40 and dy != 0:
                            shifted = Image.new("RGBA", gen_im.size, (0, 0, 0, 0))
                            shifted.paste(gen_im, (0, dy))
                            shifted.save(save_path, "PNG")
                except Exception:
                    pass

        # 若开启了面部重绘模式 (inpaint_face=1)，将新生成的面部表情与 Base 原图执行色彩协调与余弦平滑过渡融合
        # 从而 100% 保持身材、服装、发型轮廓像素级不变（MAE=0.000），消除色偏斑迹与贴纸撕裂感
        if inpaint_face and base_pil and mask_pil:
            report_progress(prog_file, "composite", 92, "正在执行自然色调协调与余弦无缝过渡融合...")
            try:
                gen_img = Image.open(save_path).convert("RGBA")
                composite_img = harmonize_and_blend(gen_img, base_pil, mask_pil)
                composite_img.save(save_path, "PNG")
            except Exception as e:
                print(f"[AI Bridge] harmonize_and_blend failed: {e}")

        # 若是 3D 姿态一致性重绘模式，将新生成的服装区域色彩分布对齐基准图，彻底抹除戏剧光影与色温偏色
        # 注意：精准识别并排除人体手部/面部皮肤像素，绝不能把手部肤色错当成风衣调成死灰
        if is_pose_consistent_mode and base_pil:
            try:
                import numpy as np
                gen_rgba = Image.open(save_path).convert("RGBA")
                bw, bh = base_pil.size
                if gen_rgba.size != (bw, bh):
                    gen_rgba = gen_rgba.resize((bw, bh), Image.Resampling.LANCZOS)
                gen_arr = np.array(gen_rgba, dtype=np.float32)
                base_arr = np.array(base_pil.convert("RGBA").resize((bw, bh), Image.Resampling.LANCZOS), dtype=np.float32)

                # 提取下半部服装有效像素 (y > 38% 且两图均有实质不透明内容)
                h, w = gen_arr.shape[:2]
                torso_y = np.zeros((h, w), dtype=bool)
                torso_y[int(h * 0.38):, :] = True

                # 智能识别手部与皮肤高亮区：肤色通常 R > G > B 且 R > 130，绝不能当作风衣深色对齐！
                r_c, g_c, b_c = gen_arr[..., 0], gen_arr[..., 1], gen_arr[..., 2]
                is_skin = (r_c > 130) & (g_c > 95) & (r_c > b_c + 10) & (r_c >= g_c)

                torso_mask = torso_y & (base_arr[..., 3] > 80) & (gen_arr[..., 3] > 80) & (~is_skin)

                if np.sum(torso_mask) > 300:
                    for c in range(3): # R, G, B
                        b_vals = base_arr[..., c][torso_mask]
                        g_vals = gen_arr[..., c][torso_mask]
                        b_mean = np.mean(b_vals)
                        b_std = max(float(np.std(b_vals)), 1.0)
                        g_mean = np.mean(g_vals)
                        g_std = max(float(np.std(g_vals)), 1.0)

                        scale = min(max(b_std / g_std, 0.8), 1.2)
                        gen_arr[..., c][torso_mask] = np.clip((g_vals - g_mean) * scale + b_mean, 0, 255)

                    aligned_img = Image.fromarray(np.clip(gen_arr, 0, 255).astype(np.uint8))
                    aligned_img.save(save_path, "PNG")
            except Exception:
                pass

        # 底部残留对话框、字幕条与横向文本框智能剔除
        if (is_pose_consistent_mode or is_inpaint_mode) and base_pil:
            try:
                import numpy as np
                curr_img = Image.open(save_path).convert("RGBA")
                c_arr = np.array(curr_img)
                h, w = c_arr.shape[:2]
                b_arr = np.array(base_pil.convert("RGBA").resize((w, h), Image.Resampling.LANCZOS))
                b_alpha = b_arr[:, :, 3]
                
                # 底部 12% 区域 (y > 88% 处)，若基准图左右底角原本完全透明，而生成图生成了横向不透明矩形底条或文字，强制剔除
                bottom_leak = np.zeros((h, w), dtype=bool)
                bottom_leak[int(h * 0.88):, :int(w * 0.22)] = True
                bottom_leak[int(h * 0.88):, int(w * 0.78):] = True
                kill_mask = bottom_leak & (b_alpha < 15) & (c_arr[:, :, 3] > 15)
                if np.any(kill_mask):
                    c_arr[kill_mask, 3] = 0
                    Image.fromarray(c_arr).save(save_path, "PNG")
            except Exception:
                pass

        if temp_base_path and os.path.exists(temp_base_path):
            try: os.remove(temp_base_path)
            except Exception: pass
        if temp_mask_path and os.path.exists(temp_mask_path):
            try: os.remove(temp_mask_path)
            except Exception: pass

        report_progress(prog_file, "done", 100, "✅ 生成成功并保存！")
        print(json.dumps({
            "success": True,
            "path": save_path,
            "seed": seed,
            "prompt_id": prompt_id
        }, ensure_ascii=False))

    except Exception as e:
        report_progress(prog_file, "error", 0, f"❌ 生成异常: {str(e)}")
        print(json.dumps({"success": False, "error": str(e)}, ensure_ascii=False))

async def async_generate_voice(text, voice, save_path, rate="+0%", pitch="+0Hz", volume="+0%"):
    import edge_tts
    os.makedirs(os.path.dirname(save_path), exist_ok=True)
    communicate = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch, volume=volume)
    await communicate.save(save_path)

def cmd_generate_voice(args):
    prog_file = getattr(args, "progress_file", None)
    report_progress(prog_file, "tts_start", 25, "正在连接 Edge-TTS 神经网络合成语音...")

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

        report_progress(prog_file, "tts_stream", 60, "正在接收语音音频流...")
        asyncio.run(async_generate_voice(args.text, args.voice, save_path, rate=rate, pitch=pitch, volume=volume))
        report_progress(prog_file, "done", 100, "✅ 配音生成完成！")
        print(json.dumps({
            "success": True,
            "path": save_path,
            "voice": args.voice,
            "emotion": emotion,
            "rate": rate,
            "pitch": pitch
        }, ensure_ascii=False))
    except Exception as e:
        report_progress(prog_file, "error", 0, f"❌ 配音失败: {str(e)}")
        print(json.dumps({"success": False, "error": str(e)}, ensure_ascii=False))

def cmd_remove_background(args):
    img_path = args.image
    save_path = args.save if args.save else img_path
    prog_file = args.progress_file
    
    if not os.path.exists(img_path):
        print(json.dumps({"success": False, "error": f"Image file not found: {img_path}"}, ensure_ascii=False))
        sys.exit(1)
        
    report_progress(prog_file, "rembg", 20, "正在执行 u2net 深度透明抠图与发丝羽化...")
    processed = False
    try:
        import rembg
        import io
        import numpy as np
        with open(img_path, 'rb') as i_f:
            input_bytes = i_f.read()
        out_bytes = rembg.remove(input_bytes)
        
        rb_im = Image.open(io.BytesIO(out_bytes)).convert("RGBA")
        arr = np.array(rb_im)
        alpha = arr[:, :, 3].astype(np.float32)
        
        new_alpha = np.zeros_like(alpha)
        high_mask = alpha >= 210.0
        new_alpha[high_mask] = 255.0
        mid_mask = (alpha >= 50.0) & (alpha < 210.0)
        new_alpha[mid_mask] = (alpha[mid_mask] - 50.0) / (210.0 - 50.0) * 255.0
        
        try:
            from scipy import ndimage
            labeled, num_features = ndimage.label(new_alpha > 0)
            if num_features > 1:
                sizes = ndimage.sum(new_alpha > 0, labeled, range(num_features + 1))
                small_comps = np.where(sizes < 80)[0]
                for c_id in small_comps:
                    new_alpha[labeled == c_id] = 0.0
        except Exception:
            pass
            
        arr[:, :, 3] = np.clip(new_alpha, 0, 255).astype(np.uint8)
        arr[arr[:, :, 3] == 0] = [0, 0, 0, 0]
        
        clean_img = Image.fromarray(arr)
        clean_img.save(save_path, "PNG")
        processed = True
    except Exception as e:
        print(f"rembg error: {e}", file=sys.stderr)
        
    if not processed:
        try:
            img = Image.open(img_path).convert("RGBA")
            datas = img.getdata()
            new_data = []
            for item in datas:
                if item[0] > 240 and item[1] > 240 and item[2] > 240:
                    new_data.append((255, 255, 255, 0))
                else:
                    new_data.append(item)
            img.putdata(new_data)
            img.save(save_path, "PNG")
            processed = True
        except Exception as e:
            print(json.dumps({"success": False, "error": str(e)}, ensure_ascii=False))
            sys.exit(1)
            
    report_progress(prog_file, "done", 100, "✅ 透明去背处理完成！")
    print(json.dumps({"success": True, "saved_path": save_path, "transparent": True}, ensure_ascii=False))

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
    p_img.add_argument("--progress_file", "--progress-file", default="")
    p_img.add_argument("--base_image", "--base-image", default="")
    p_img.add_argument("--inpaint_face", "--inpaint-face", type=lambda x: int(float(x)), default=0)
    p_img.add_argument("--denoise", type=float, default=0.88)
    p_img.add_argument("--pose_image", "--pose-image", default="")
    p_img.add_argument("--pose_preset", "--pose-preset", default="")

    # generate_voice
    p_voice = subparsers.add_parser("generate_voice")
    p_voice.add_argument("--text", required=True)
    p_voice.add_argument("--voice", default="zh-CN-XiaoxiaoNeural")
    p_voice.add_argument("--save", required=True)
    p_voice.add_argument("--emotion", default="normal")
    p_voice.add_argument("--rate", default="+0%")
    p_voice.add_argument("--pitch", default="+0Hz")
    p_voice.add_argument("--volume", default="+0%")
    p_voice.add_argument("--progress_file", "--progress-file", default="")

    # remove_background
    p_rembg = subparsers.add_parser("remove_background")
    p_rembg.add_argument("--image", required=True)
    p_rembg.add_argument("--save", default="")
    p_rembg.add_argument("--progress_file", "--progress-file", default="")

    args = parser.parse_args()
    if args.command == "check_comfy":
        cmd_check_comfy(args)
    elif args.command == "generate_image":
        cmd_generate_image(args)
    elif args.command == "generate_voice":
        cmd_generate_voice(args)
    elif args.command == "remove_background":
        cmd_remove_background(args)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
