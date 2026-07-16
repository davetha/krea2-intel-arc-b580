# Troubleshooting — every failure we hit, and what it actually means

All of these were reproduced on an Arc B580 (Battlemage G21), Ubuntu 26.04 host,
kernel 7.0, `xe` driver, everything in Docker. Error strings are verbatim so this
page is googleable.

## PyTorch XPU / Level-Zero crashes

### `Abort was called at 655 line in file: ./shared/source/command_container/command_encoder_xehp_and_later.inl`
NEO compute-runtime (userspace) is built for an older kernel generation than your `xe`
KMD. Happens the instant *any* GPU kernel is dispatched — device enumeration still works,
which makes it look like your app's fault. It isn't.
**Fix:** use driver packages built for your distro generation. On Ubuntu 25.10+:
`add-apt-repository ppa:kobuk-team/intel-graphics` inside the container, then install
`intel-opencl-icd libze-intel-gpu1 libze1`. Do **not** use the
`repositories.intel.com/gpu/ubuntu noble unified` line on a kernel-7.x host.

### `Abort was called at 15 line in file: ../../neo/shared/source/gmm_helper/resource_info.cpp`
You upgraded NEO but left the old gmmlib (`libigdgmm12`) / IGC behind. The NEO + gmmlib +
IGC set must be coherent (see upstream [compute-runtime#922](https://github.com/intel/compute-runtime/issues/922)).
The kobuk PPA handles this for you.

### `torch.xpu` segfaults in `_lazy_init` with no message
Same root cause as above — wrong-generation coherent set. Even a "correct" manually
assembled NEO+gmmlib+IGC set from GitHub releases segfaulted for us on kernel 7.0;
only the distro-matched PPA packages worked.

### `RuntimeError: No XPU devices are available` with `ONEAPI_DEVICE_SELECTOR=opencl:gpu`
PyTorch's XPU layer only accepts Level-Zero devices. You cannot route torch through the
OpenCL UR adapter, even though the wheel bundles `libur_adapter_opencl.so`. Fix Level-Zero
instead (above).

## SYCL (stable-diffusion.cpp `-DSD_SYCL=ON`)

- OpenCL adapter: `opencl backend failed with error: 68 (UR_RESULT_ERROR_IN_EVENT_LIST_EXEC_STATUS)`
  in `ggml_backend_sycl_buffer_set_tensor` → crash (exit 139).
- Level-Zero adapter: `level_zero backend failed with error: 20 (UR_RESULT_ERROR_DEVICE_LOST)`.
- Build error `no member named 'intel_gpu_bmg_g31' in 'sycl::...::architecture'`: your oneAPI
  is too old for current ggml-sycl — use oneAPI ≥ 2025.3.
- `icpx: error: unable to execute command: Killed`: compiler OOM — lower `-j`.

We did not get SYCL working on this hardware/kernel combo (tested against oneAPI 2025.3 +
NEO 25.18/26.05/26.22). It may work with the kobuk runtime — untested. The Vulkan and
torch-xpu paths made it moot.

## ComfyUI

- **`CLIPLoader` has no `krea2` type / Krea 2 GGUF won't load:** you need a
  ComfyUI-GGUF fork with Krea 2 arch support (stock `city96/ComfyUI-GGUF` doesn't have it
  yet) and a recent ComfyUI (≥ 0.26).
- **Container exits with code 137 mid-generation:** host **RAM** OOM, not VRAM. A 12B
  pipeline holds 15–20 GB across VRAM+RAM; don't run a second model server (e.g. an
  sd-server or a big llama.cpp) on the same 32 GB box simultaneously.
- **~25s of "Requested to load ..." before every sampling run:** your model combo doesn't
  fit VRAM, so ComfyUI swaps text encoder ↔ unet per prompt. Use the all-resident Q4 combo
  (README) to eliminate it.
- **First generation is much slower:** one-time kernel warm-up; per-step time drops over
  the first few steps (we saw 5.7 → 2.0 s/step within one run).

## stable-diffusion.cpp (Vulkan fallback)

- `Conditioner model tensor 'text_encoders.llm.visual...' not in model metadata`:
  ComfyUI's `qwen3vl_4b_*.safetensors` text encoders are **vision-stripped** and fail
  sd.cpp validation. Use the **full** `Qwen3-VL-4B-Instruct-Q4_K_M.gguf` (unsloth) for `--llm`.
- sd.cpp wants the **Wan2.1 VAE** (`wan_2.1_vae.safetensors`), *not* `qwen_image_vae`.
- `Could not find ... "SPIRV-Headers"` at build: `apt install spirv-headers` (not just
  `spirv-tools`).
- The CLI binary is `sd-cli` (upstream renamed it from `sd`).
- `Device memory allocation ... failed` at 1024²: add `--vae-tiling`, and/or keep
  text-encoder weights in RAM: `--params-backend te=cpu,vae=cpu` (weights in RAM, compute
  still on GPU — this is *not* the slow `--backend te=cpu`).

## Docker

- `unable to find group render: no matching entries in group file`: use **numeric GIDs**
  in `--group-add` (from `getent group render video` on the host) — names don't resolve
  inside most images.
- Slow/failing build with `checking context`: your build context contains the models
  directory; add a `.dockerignore`.

## Source-built Mesa (testing release candidates)

- **Everything suddenly ~25× slower after swapping in a self-built ANV:** the Vulkan
  loader silently ignored your ICD and ggml fell back to CPU. Run
  `VK_LOADER_DEBUG=error,warn vulkaninfo --summary` — we hit
  `libdisplay-info.so.3: cannot open shared object file` (install `libdisplay-info3`).
  Always `ldd libvulkan_intel.so | grep "not found"` after grafting a self-built driver.
- **`meson ... ERROR: Feature llvm cannot be disabled: CLC requires LLVM`:** ANV needs
  intel-clc; leave LLVM enabled even for a Vulkan-only build.
- **Mesa 26.2.0-rc1 regression:** 1024² generation OOMs
  (`ggml_gallocr_reserve_n_impl: failed to allocate Vulkan0 buffer of size 3852311564`)
  because rc1 exposes only 2 memory heaps vs 3 on 26.0 (the 30.67 GiB host-visible heap
  is missing). 512² is unaffected (parity with 26.0). Re-test at 26.2 final.

## Monitoring GPU usage (xe driver)

- `intel_gpu_top` (igt ≤ 2.3) does **not** support the xe PMU — prints
  `Failed to detect engines!`. Not fixable with flags.
- `nvtop` works (device, clock, temp, fan; utilization column is blank on xe for now).
- Best signal is sysfs, no tools needed — see [`tools/arcwatch`](../tools/arcwatch):
  `act_freq` is ~0 when idle (clock-gated) and pegs near max under load; power comes from
  the hwmon energy counter delta. A pegged B580 reads ~2850 MHz / ~190 W.
