# Wiring a web UI to the backends

We drive [davetha/krea2-web-ui](https://github.com/davetha/krea2-web-ui) — a single-file,
phone-friendly UI that talks to **ComfyUI's API** (`/prompt`, `/history`, `/upload/image`).
Any ComfyUI front-end works the same way.

## Option A (recommended): ComfyUI backend

Run the `comfyui/` image from this repo, then point the UI at it (`COMFY_URL=http://localhost:8188`).
Patch the UI's workflow nodes to the GGUF loaders (all-resident combo):

```diff
-  "10": {"class_type": "UNETLoader", "inputs": {"unet_name": "krea2_turbo_fp8_scaled.safetensors", "weight_dtype": "default"}},
-  "11": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen3vl_4b_fp8_scaled.safetensors", "type": "krea2", "device": "default"}},
+  "10": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": "krea2_turbo_bf16-Q4_0.gguf"}},
+  "11": {"class_type": "CLIPLoaderGGUF", "inputs": {"clip_name": "Qwen3-VL-4B-Instruct-Q4_K_M.gguf", "type": "krea2", "device": "default"}},
```

Everything else (txt2img *and* img2img/transform) works unchanged. Measured through the UI
on a B580: 512²/8 ≈ **13–15s**, 1024²/8 ≈ **26–47s**, img2img ≈ 28s.

```bash
docker run -d --name krea-web --restart unless-stopped --network host \
  -v "$PWD/krea-web.py:/krea-web.py:ro" \
  python:3.12-slim python3 /krea-web.py
# UI on :7860 -> ComfyUI on :8188
```

## Option B: sd.cpp `sd-server` backend (Vulkan fallback)

`sd-server` (from `sdcpp-vulkan/`) exposes an **A1111-compatible API**
(`POST /sdapi/v1/txt2img`, `/sdapi/v1/img2img`, base64 images in `{"images":[...]}`) and
keeps models warm between requests. Swap the UI's backend functions to POST there instead —
about 30 lines. Slower than Option A but has no PyTorch dependency at all.

## Don't run both backends at once

Each holds 15–20 GB across VRAM+RAM. On a 32 GB host, running ComfyUI and sd-server
simultaneously gets one of them OOM-killed (exit 137).

## Accurate photo → coloring page (the img2img trap)

Plain img2img cannot make a faithful coloring page from a photo with this model: at the
denoise strength needed to whiten the background (~0.75), the model discards your subject
entirely; at strengths that preserve the subject (~0.6), the background stays a photo.
There is no working middle value.

What works (deployed in our UI, ~45s total):
1. **img2img pass 1** @ strength 0.60 — converts the *subject* to clean line art
2. **img2img pass 2** @ 0.60 on the pass-1 output — refines lines, background still photo
3. **Pixel-space binarization** — photo remnants live in *colorful neighborhoods*
   (box-blurred saturation > threshold → force white); dark pixels in unsaturated
   regions are line strokes (→ black). ~15 lines of PIL/numpy.

Don't bother with: DoG/edge-map init images (the model hallucinates from the noise) or
aggressive despeckling (fur strokes are small components and get eaten).
