import urllib.request
import json
import time

COMFY_HOST = "192.168.1.57:8188"

def test_generate_bg():
    prompt_workflow = {
        "3": {
            "class_type": "KSampler",
            "inputs": {
                "cfg": 7,
                "denoise": 1,
                "latent_image": ["5", 0],
                "model": ["4", 0],
                "negative": ["7", 0],
                "positive": ["6", 0],
                "sampler_name": "euler_ancestral",
                "scheduler": "karras",
                "seed": 42881,
                "steps": 20
            }
        },
        "4": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {
                "ckpt_name": "toonyou_beta6.safetensors"
            }
        },
        "5": {
            "class_type": "EmptyLatentImage",
            "inputs": {
                "batch_size": 1,
                "height": 576,
                "width": 1024
            }
        },
        "6": {
            "class_type": "CLIPTextEncode",
            "inputs": {
                "clip": ["4", 1],
                "text": "masterpiece, best quality, dark antique study library, tall grandfather clock, rainy window, lightning flash, fireplace glowing, suspense anime style, interior, detective visual novel background, detailed"
            }
        },
        "7": {
            "class_type": "CLIPTextEncode",
            "inputs": {
                "clip": ["4", 1],
                "text": "worst quality, low quality, blurry, text, watermark, people, character, human"
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
                "filename_prefix": "AVG_Study_BG",
                "images": ["8", 0]
            }
        }
    }

    req = urllib.request.Request(
        f"http://{COMFY_HOST}/prompt",
        data=json.dumps({"prompt": prompt_workflow}).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )
    resp = urllib.request.urlopen(req)
    data = json.loads(resp.read())
    prompt_id = data.get("prompt_id")
    print("Submitted prompt ID:", prompt_id)

    # Poll history
    start_time = time.time()
    while time.time() - start_time < 60:
        time.sleep(1)
        h_req = urllib.request.Request(f"http://{COMFY_HOST}/history/{prompt_id}")
        h_resp = urllib.request.urlopen(h_req)
        h_data = json.loads(h_resp.read())
        if prompt_id in h_data:
            outputs = h_data[prompt_id].get("outputs", {})
            if "9" in outputs and "images" in outputs["9"]:
                img_info = outputs["9"]["images"][0]
                filename = img_info["filename"]
                subfolder = img_info.get("subfolder", "")
                img_url = f"http://{COMFY_HOST}/view?filename={filename}&subfolder={subfolder}&type=output"
                print("Image generated successfully:", img_url)
                
                # Download to destination
                save_dest = "E:/aigame/assets/images/backgrounds/bg_study_storm.png"
                urllib.request.urlretrieve(img_url, save_dest)
                print("Saved image to:", save_dest)
                return True
    print("Timeout waiting for generation")
    return False

if __name__ == "__main__":
    test_generate_bg()
