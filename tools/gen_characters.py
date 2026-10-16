import urllib.request
import json
import time
from PIL import Image

COMFY_HOST = "192.168.1.57:8188"

def generate_character(prompt_text, save_path, seed=12345):
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
                "seed": seed,
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
                "height": 768,
                "width": 512
            }
        },
        "6": {
            "class_type": "CLIPTextEncode",
            "inputs": {
                "clip": ["4", 1],
                "text": prompt_text
            }
        },
        "7": {
            "class_type": "CLIPTextEncode",
            "inputs": {
                "clip": ["4", 1],
                "text": "worst quality, low quality, blurry, text, watermark, bad anatomy, deformed limbs, background details, complex background"
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
                "filename_prefix": "AVG_Char",
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
    print(f"Submitting char generation, prompt ID: {prompt_id}")

    start_time = time.time()
    while time.time() - start_time < 90:
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
                
                # Download raw
                urllib.request.urlretrieve(img_url, save_path)
                print(f"Downloaded character to {save_path}")
                
                # Make white background transparent
                img = Image.open(save_path).convert("RGBA")
                datas = img.getdata()
                new_data = []
                for item in datas:
                    # If pixel is close to pure white, make it transparent
                    if item[0] > 235 and item[1] > 235 and item[2] > 235:
                        new_data.append((255, 255, 255, 0))
                    else:
                        new_data.append(item)
                img.putdata(new_data)
                img.save(save_path, "PNG")
                print("Made transparent PNG successfully!")
                return True
    return False

if __name__ == "__main__":
    # Generate Lin Detective
    prompt_lin = "masterpiece, best quality, 1boy, handsome young detective, trench coat, necktie, dark hair, intelligent sharp eyes, serious expression, white background, simple background, half body portrait, anime mystery visual novel"
    generate_character(prompt_lin, "E:/aigame/assets/images/characters/char_detective_normal.png", seed=88721)

    # Generate Butler
    prompt_butler = "masterpiece, best quality, 1old man, elderly butler, black tuxedo vest, gray hair, mustache, nervous sweating expression, guilty eyes, white background, simple background, half body portrait, anime mystery visual novel"
    generate_character(prompt_butler, "E:/aigame/assets/images/characters/char_butler_nervous.png", seed=99312)
