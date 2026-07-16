#!/usr/bin/env bash
# Compose-free launcher for the sd.cpp Vulkan fallback.
#   ./run.sh build              # build builder + mesa26 runtime images
#   ./run.sh gen "prompt"       # generate -> ./out/  (STEPS/CFG/H/W/OUT env overrides)
#
# NOTE: do NOT pass --diffusion-fa on Intel — the scalar FA path is ~10% slower.
set -euo pipefail
cd "$(dirname "$0")"

IMAGE=krea2-sdcpp-vulkan:mesa26
MODELS="${MODELS:-$PWD/../comfyui/models}"
# Numeric host GIDs owning /dev/dri (names don't resolve in the image):
#   getent group render video
GID_RENDER="${GID_RENDER:-$(getent group render | cut -d: -f3)}"
GID_VIDEO="${GID_VIDEO:-$(getent group video | cut -d: -f3)}"
GPU=( --device /dev/dri --group-add "$GID_RENDER" --group-add "$GID_VIDEO" --ipc host )

case "${1:-gen}" in
  build)
    docker build -t krea2-sdcpp-vulkan:latest .
    docker build -f Dockerfile.mesa26 -t "$IMAGE" . ;;
  gen)
    prompt="${2:?usage: ./run.sh gen \"prompt\"}"
    mkdir -p out
    docker run --rm "${GPU[@]}" \
      -v "$MODELS:/models" -v "$PWD/out:/work" \
      "$IMAGE" \
      --diffusion-model /models/unet/krea2_turbo_bf16-Q5_1.gguf \
      --llm            /models/text_encoders/Qwen3-VL-4B-Instruct-Q4_K_M.gguf \
      --vae            /models/vae/wan_2.1_vae.safetensors \
      -p "$prompt" \
      --steps "${STEPS:-8}" --cfg-scale "${CFG:-1.0}" --sampling-method euler \
      -H "${H:-1024}" -W "${W:-1024}" \
      --offload-to-cpu -v -o "/work/${OUT:-out.png}"
    echo "-> ./out/${OUT:-out.png}" ;;
  *) echo "usage: $0 {build|gen \"prompt\"}"; exit 1 ;;
esac
