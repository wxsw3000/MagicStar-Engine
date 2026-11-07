# tools/test_inpaint_pipeline.py
# 自动化测试：VNCCS 面部差分重绘管线、Mask 生成与像素级无缝贴合校验
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')
from PIL import Image, ImageDraw, ImageFilter

def test_pipeline():
    print("--- [1] 测试 PIL 智能面部羽化 Mask 构造 ---")
    bw, bh = 512, 768
    mask_pil = Image.new("L", (bw, bh), 0)
    draw = ImageDraw.Draw(mask_pil)
    face_box = [int(bw * 0.28), int(bh * 0.12), int(bw * 0.72), int(bh * 0.42)]
    draw.ellipse(face_box, fill=255)
    mask_pil = mask_pil.filter(ImageFilter.GaussianBlur(radius=16))
    
    assert mask_pil.size == (bw, bh), "Mask 尺寸应与原图一致"
    # 面部中心点权重应当为 255
    center_val = mask_pil.getpixel((int(bw * 0.5), int(bh * 0.27)))
    assert center_val > 240, f"面部中心权重应当接近 255, 实际: {center_val}"
    # 底部和边缘应当为 0 (完全不改变身材、衣服)
    bottom_val = mask_pil.getpixel((int(bw * 0.5), int(bh * 0.85)))
    assert bottom_val == 0, f"服装身体区域权重必须为 0, 实际: {bottom_val}"
    print(f"    ✅ Mask 结构有效！面部中心权重: {center_val}, 身体服装区域权重: {bottom_val}")

    print("--- [2] 测试像素级羽化贴合 (Composite) 纯保真度 ---")
    # 模拟 Base 立绘 (带有衣服细节、背景与发型)
    base_img = Image.new("RGBA", (bw, bh), (30, 45, 80, 255))
    base_draw = ImageDraw.Draw(base_img)
    # 画一个特殊的西装领带 (在身体区域)
    base_draw.rectangle([200, 400, 312, 600], fill=(200, 40, 40, 255))
    # 记录领带处一个特定像素的值
    original_tie_pixel = base_img.getpixel((256, 500))

    # 模拟 AI 生成出的表情差分新图 (可能整体背景或其它地方有些微变化)
    diff_gen_img = Image.new("RGBA", (bw, bh), (180, 180, 180, 255))
    diff_draw = ImageDraw.Draw(diff_gen_img)
    # 新图的面部区域 (黄色微笑表情)
    diff_draw.ellipse(face_box, fill=(255, 230, 120, 255))

    # 执行羽化复合贴合
    composite_img = Image.composite(diff_gen_img, base_img, mask_pil)
    
    # 校验：非面部区域 (如西装领带) 是否 100% 字节无损保留原 Base 图像素
    after_tie_pixel = composite_img.getpixel((256, 500))
    assert after_tie_pixel == original_tie_pixel, f"服装身体像素必须 100% 保持不变！原: {original_tie_pixel}, 复合后: {after_tie_pixel}"
    
    # 校验：面部区域是否成功融合为新表情
    face_pixel = composite_img.getpixel((int(bw * 0.5), int(bh * 0.27)))
    assert face_pixel[0] > 200, "面部区域已成功融合新表情颜色"
    print(f"    ✅ 像素级贴合校验通过！身体领带像素完全一致: {after_tie_pixel}")

    print("--- [3] 校验 ai_bridge.py 命令行参数支持 ---")
    import subprocess
    cmd = [sys.executable, "tools/ai_bridge.py", "generate_image", "--help"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    assert res.returncode == 0, "ai_bridge.py help 应当成功执行"
    assert "--base_image" in res.stdout, "必须包含 --base_image 参数"
    assert "--inpaint_face" in res.stdout, "必须包含 --inpaint_face 参数"
    assert "--denoise" in res.stdout, "必须包含 --denoise 参数"
    assert "--pose_image" in res.stdout, "必须包含 --pose_image 参数"
    assert "--pose_preset" in res.stdout, "必须包含 --pose_preset 参数"
    print("    ✅ 命令行参数解析检验通过！支持 --base_image, --inpaint_face, --denoise, --pose_image, --pose_preset")

    print("--- [4] 测试 ComfyUI LoadImage 双兼容 RGBA 遮罩映射 ---")
    mask_rgba = Image.new("RGBA", (bw, bh), (255, 255, 255, 255))
    mask_data = mask_pil.getdata()
    new_rgba_data = []
    for m_val in mask_data:
        alpha_val = 255 - m_val
        new_rgba_data.append((m_val, m_val, m_val, alpha_val))
    mask_rgba.putdata(new_rgba_data)
    
    # 模拟 ComfyUI LoadImage 节点官方公式: mask = 1.0 - (alpha / 255.0)
    face_rgba = mask_rgba.getpixel((int(bw * 0.5), int(bh * 0.27)))
    comfy_face_mask = 1.0 - (face_rgba[3] / 255.0)
    assert comfy_face_mask > 0.94, f"ComfyUI 在面部区域解析的重绘遮罩权重应接近 1.0, 实际: {comfy_face_mask}"
    
    body_rgba = mask_rgba.getpixel((int(bw * 0.5), int(bh * 0.85)))
    comfy_body_mask = 1.0 - (body_rgba[3] / 255.0)
    assert comfy_body_mask == 0.0, f"ComfyUI 在身体区域解析的重绘遮罩权重必须为 0.0, 实际: {comfy_body_mask}"
    print(f"    ✅ ComfyUI LoadImage 遮罩解析完美匹配！面部去噪权重: {comfy_face_mask:.2f}, 身体锁定权重: {comfy_body_mask:.2f}")

    print("--- [5] 测试 3D 姿态自适应动作区与面部身份锁遮罩 (Pose Mask) ---")
    from ai_bridge import create_adaptive_pose_mask
    pose_base = Image.new("RGBA", (bw, bh), (100, 100, 100, 255))
    pose_mask = create_adaptive_pose_mask(pose_base, "standing_calm")
    assert pose_mask.size == (bw, bh), "Pose Mask 尺寸应与原图一致"
    
    # 头部上半部身份绝对锁死 (45~75之间)
    head_pose_val = pose_mask.getpixel((int(bw * 0.5), int(bh * 0.15)))
    assert 40 <= head_pose_val <= 80, f"头部区域去噪权重应受控在 40~80 之间, 实际: {head_pose_val}"
    
    # 躯干动作区 (手臂、胸前) 权重应在 180~255 之间
    action_val = pose_mask.getpixel((int(bw * 0.5), int(bh * 0.55)))
    assert 180 <= action_val <= 255, f"动作区重绘权重应在 180~255 之间, 实际: {action_val}"
    
    # 风衣底摆必须锚定锁死 (40~85)，彻底杜绝下半身叠画小人
    hem_val = pose_mask.getpixel((int(bw * 0.5), int(bh * 0.85)))
    assert 40 <= hem_val <= 90, f"下摆锁死权重必须在 40~90 之间, 实际: {hem_val}"
    
    # 测试 chin_touch 姿态下的下巴微通道
    chin_mask = create_adaptive_pose_mask(pose_base, "chin_touch")
    chin_val = chin_mask.getpixel((int(bw * 0.5), int(bh * 0.32)))
    assert chin_val > 150, f"chin_touch 下巴区域必须开放手势通道, 实际: {chin_val}"
    
    print(f"    ✅ 3D 姿态防叠人自适应遮罩校验通过！头部锁: {head_pose_val}, 动作区: {action_val}, 下摆锁: {hem_val}, 下巴手势通道: {chin_val}")

    print("\n🎉 VNCCS 面部差分重绘与 3D 姿态一致性自适应遮罩自动化验证全部通过！")

if __name__ == "__main__":
    test_pipeline()
