#!/usr/bin/env bash
# Entrypoint for the Krea2/Arc ComfyUI container.
#   (no args)     -> verify XPU, then launch ComfyUI
#   --download    -> download the model set into the mounted volume, then exit
set -euo pipefail

MODELS_DIR="/opt/ComfyUI/models"

download_models() {
  echo ">> Downloading Krea 2 Turbo model set into ${MODELS_DIR} ..."
  pip install --quiet huggingface_hub
  mkdir -p "${MODELS_DIR}/unet" "${MODELS_DIR}/text_encoders" "${MODELS_DIR}/vae"

  # Recommended all-resident combo for 12 GB VRAM (no per-prompt model swapping):
  # 1) Diffusion model (unet) — Q4_0. Override with QUANT=Q5_1 for slightly better
  #    quality at the cost of per-prompt VRAM swapping (~25s/prompt overhead).
  local quant="${QUANT:-Q4_0}"
  hf download molbal/krea2-gguf "krea2_turbo_bf16-${quant}.gguf" \
      --local-dir "${MODELS_DIR}/unet"

  # 2) Text encoder — Qwen3-VL 4B GGUF (2.5 GB, loads via CLIPLoaderGGUF type=krea2).
  hf download unsloth/Qwen3-VL-4B-Instruct-GGUF "Qwen3-VL-4B-Instruct-Q4_K_M.gguf" \
      --local-dir "${MODELS_DIR}/text_encoders"
  #    bf16 alternative (8.9 GB, best quality, forces swapping):
  #    hf download Comfy-Org/Krea-2 text_encoders/qwen3vl_4b_bf16.safetensors --local-dir "${MODELS_DIR}"

  # 3) VAE
  hf download Comfy-Org/Krea-2 vae/qwen_image_vae.safetensors --local-dir "${MODELS_DIR}"

  echo ">> Done. Contents:"
  find "${MODELS_DIR}" -maxdepth 2 -type f ! -path '*/.cache/*' -printf '   %p  (%s bytes)\n'
}

verify_xpu() {
  echo ">> Verifying Intel XPU visibility inside container ..."
  python3 - <<'PY'
import sys, torch
ok = hasattr(torch, "xpu") and torch.xpu.is_available()
if not ok:
    sys.stderr.write(
        "\n!!! XPU NOT AVAILABLE inside the container.\n"
        "    Checklist: /dev/dri passed in, correct render/video GIDs in group_add,\n"
        "    xe driver loaded on host, and `clinfo -l` below should list the GPU.\n\n")
    import subprocess; subprocess.run(["clinfo", "-l"])
    sys.exit(1)
n = torch.xpu.device_count()
print(f"    XPU OK — {n} device(s): " + ", ".join(torch.xpu.get_device_name(i) for i in range(n)))
PY
}

if [[ "${1:-}" == "--download" ]]; then
  download_models
  exit 0
fi

verify_xpu
echo ">> Launching ComfyUI on 0.0.0.0:8188 ..."
exec python3 /opt/ComfyUI/main.py --listen 0.0.0.0 --port 8188
