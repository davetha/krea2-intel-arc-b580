# Krea 2 on Intel Arc B580 (Battlemage) — working Docker setup

Run [Krea 2 Turbo](https://huggingface.co/krea) (12B DiT text-to-image) on a **$249 Intel Arc B580**
with **ComfyUI + PyTorch XPU**, entirely in Docker — including the fix for the Level-Zero
crash that makes `torch.xpu` abort on Battlemage with newer kernels.

**Results (1024×1024, 8 steps, warm):** ~150s → **~26–47s**. 512×512 in **~13s**. Verified end-to-end.

## TL;DR — the one fix that matters

If `torch.xpu` (or anything Level-Zero) **aborts/segfaults on first GPU kernel dispatch** on a
Battlemage card with the `xe` driver and a recent kernel (≥ 7.0), your userspace GPU driver
packages are built for the wrong distro generation. The classic mistake is installing the
`repositories.intel.com/gpu/ubuntu **noble** unified` packages (built for Ubuntu 24.04-era
kernels) on a newer host. The ABI doesn't match the new xe KMD and NEO aborts inside its
command encoder.

**Fix:** use the distro-matched [kobuk-team/intel-graphics PPA](https://launchpad.net/~kobuk-team/+archive/ubuntu/intel-graphics)
(Intel + Canonical's stack for Ubuntu 25.10+) inside your container:

```dockerfile
FROM ubuntu:25.10
RUN apt-get update && apt-get install -y software-properties-common gpg-agent \
 && add-apt-repository -y ppa:kobuk-team/intel-graphics \
 && apt-get update && apt-get install -y intel-opencl-icd libze-intel-gpu1 libze1 clinfo
RUN pip install torch --index-url https://download.pytorch.org/whl/xpu
```

With this stack the B580 hits **83 TFLOPS fp16 in a torch matmul — 72% of its XMX peak**.
The hardware was never the problem.

## Quickstart

Host requirements (nothing else touches the host — no kernel changes, no host driver installs):

- Battlemage GPU (tested: Arc B580), `xe` kernel driver loaded, `/dev/dri/renderD*` present
- Kernel ≥ 6.12 (tested on 7.0)
- Docker; note your `render` and `video` GIDs: `getent group render video`

```bash
git clone https://github.com/davetha/krea2-intel-arc-b580
cd krea2-intel-arc-b580/comfyui
docker build -t krea2-comfyui .

# one-time: download models (~15 GB) into ./models
docker run --rm -v "$PWD/models:/opt/ComfyUI/models" krea2-comfyui --download

# run (replace 991/44 with YOUR render/video GIDs)
docker run -d --name krea2-comfyui -p 8188:8188 \
  --device /dev/dri --group-add 991 --group-add 44 --ipc host \
  -v "$PWD/models:/opt/ComfyUI/models" -v "$PWD/output:/opt/ComfyUI/output" \
  --restart unless-stopped krea2-comfyui
# open http://<host>:8188
```

The entrypoint runs a fail-loud XPU self-check and refuses to start on CPU fallback.

## The model combo that fits 12 GB with no VRAM swapping

ComfyUI reloads any model that doesn't fit VRAM on *every* prompt (~25s/prompt overhead
with the bf16 text encoder). This combo keeps **everything resident** in the B580's 12 GB:

| Role | File | Source | Loader node |
|---|---|---|---|
| Diffusion (unet) | `krea2_turbo_bf16-Q4_0.gguf` (7.9 GB) | [molbal/krea2-gguf](https://huggingface.co/molbal/krea2-gguf) | `UnetLoaderGGUF` |
| Text encoder | `Qwen3-VL-4B-Instruct-Q4_K_M.gguf` (2.5 GB) | [unsloth/Qwen3-VL-4B-Instruct-GGUF](https://huggingface.co/unsloth/Qwen3-VL-4B-Instruct-GGUF) | `CLIPLoaderGGUF`, **type = `krea2`** |
| VAE | `qwen_image_vae.safetensors` (254 MB) | [Comfy-Org/Krea-2](https://huggingface.co/Comfy-Org/Krea-2) | `VAELoader` |

GGUF loading needs a ComfyUI-GGUF fork with Krea 2 arch support (baked into the Dockerfile;
stock `city96/ComfyUI-GGUF` doesn't load Krea 2 yet). Sampling: **8 steps, CFG 1.0, euler/simple**.

Alternative: `Q5_1` unet (9.9 GB) + `qwen3vl_4b_bf16.safetensors` gives slightly better
quality but forces per-prompt model swapping (total ≈ 45s at any size).

## Measured performance (Arc B580, kernel 7.0, xe)

Warm timings, 8 steps, euler/simple, CFG 1.0:

| Backend / config | 512² s/step | 512² total | 1024² s/step | 1024² total |
|---|---|---|---|---|
| sd.cpp Vulkan, Mesa 25.2 | 3.17 | ~32s | 16.7 | ~150s |
| sd.cpp Vulkan, Mesa 26.0 | 1.68 | ~20s | ~8.8 | ~85s |
| **ComfyUI torch-xpu (kobuk), all-resident Q4** | **1.27** | **~13s** | 3.6–5.0 | **~26–47s** |

Microbenchmark: fp16 4096×4096 matmul via torch-xpu = **83.1 TFLOPS** (B580 XMX peak ≈ 116).

### Vulkan findings (ggml / stable-diffusion.cpp fallback — see `sdcpp-vulkan/`)

- **Mesa ≥ 26.0 is ~1.7× faster** than 25.2 for ggml-Vulkan on Battlemage (26.1 ≈ 26.0 here).
- **KHR_coopmat is worth ~2.5×** and is auto-enabled when Mesa reports `minSubgroupSize == 16`
  (ggml detects the GPU as `INTEL_XE2`).
- **`--diffusion-fa` (flash attention) is ~10% SLOWER on Intel** — ggml forces a scalar FA
  path on Intel GPUs. Leave it off.
- Quantization level does **not** change speed (Q4 == Q5 per-step) — weights are dequantized
  to fp16 for the math. Quants only buy you VRAM.

## What does NOT work (so you don't burn the days we did)

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for the exact error signatures.

- ❌ `repositories.intel.com` "noble unified" NEO packages on a kernel-7.x host → abort in
  `command_encoder_xehp_and_later.inl` on first kernel dispatch (any NEO 25.x/26.x mix we tried).
- ❌ **SYCL / oneAPI** (sd.cpp `-DSD_SYCL=ON`, oneAPI 2025.3): crashes at runtime on both UR
  adapters — OpenCL (`UR_RESULT_ERROR_IN_EVENT_LIST_EXEC_STATUS`) and Level-Zero
  (`UR_RESULT_ERROR_DEVICE_LOST`). Untested against the kobuk runtime since; may improve.
- ❌ Forcing PyTorch onto OpenCL (`ONEAPI_DEVICE_SELECTOR=opencl:gpu`) — torch's XPU layer
  only accepts Level-Zero devices.
- ⚠️ Running two model servers on one box: a 12B pipeline holds 15–20 GB across VRAM+RAM;
  two backends co-resident on a 32 GB host = OOM-kill (exit 137).

## Repo layout

```
comfyui/        Working setup: ComfyUI + PyTorch XPU on the kobuk stack  ← use this
sdcpp-vulkan/   Fallback: stable-diffusion.cpp + Vulkan (works everywhere, slower)
sdcpp-sycl/     Reference: SYCL build that crashes on Battlemage+kernel 7 (documented dead end)
webui/          Wiring a lightweight web UI to either backend
docs/           Troubleshooting: every error signature we hit, and what it means
```

## Credits / provenance

Debugged interactively on real hardware (Arc B580, Ubuntu 26.04, kernel 7.0.0, xe driver,
July 2026) with [Claude Code](https://claude.com/claude-code). Key upstream references:
[intel/compute-runtime#872](https://github.com/intel/compute-runtime/issues/872),
[intel/compute-runtime#922](https://github.com/intel/compute-runtime/issues/922),
[llama.cpp Xe2 coopmat discussion](https://github.com/ggml-org/llama.cpp/discussions/13530),
[stable-diffusion.cpp Krea 2 docs](https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/krea2.md).

MIT licensed. Krea 2 model weights are under Krea's own community license — check it for
your use case.
