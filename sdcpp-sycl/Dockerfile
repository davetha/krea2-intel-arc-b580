# ⚠️ DOES NOT WORK on Battlemage + xe + kernel 7.x — kept as a documented dead end.
# Runtime crashes on both UR adapters (see docs/TROUBLESHOOTING.md). Retest after driver updates.
# Krea 2 Turbo on Intel Arc B580 via stable-diffusion.cpp — SYCL (oneAPI) backend.
# Experiment: is SYCL/oneMKL faster than the Mesa-Vulkan build on Battlemage?
#
# Runtime MUST force the OpenCL UR adapter (ONEAPI_DEVICE_SELECTOR=opencl:gpu) to
# dodge the Level-Zero command-encoder abort that breaks torch/L0 on this
# kernel-7.0 + xe host. ggml-SYCL (unlike PyTorch) honours that selector.

# 2025.3+ needed: sd.cpp's ggml-sycl references intel_gpu_bmg_g31/wcl arch enums
# absent from 2025.1 headers.
FROM intel/oneapi-basekit:latest

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        git cmake ninja-build ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone --recursive --depth 1 https://github.com/leejet/stable-diffusion.cpp

WORKDIR /opt/stable-diffusion.cpp
# The oneAPI env (icx/icpx, MKLROOT, LD_LIBRARY_PATH) is already baked into the
# base image — no setvars sourcing needed (and sourcing under /bin/sh returns
# non-zero, which breaks the RUN chain).
RUN cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DSD_SYCL=ON -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx && \
    cmake --build build --config Release -j4 && \
    test -x build/bin/sd-cli && echo "BUILD_OK: sd-cli (SYCL) present"

# Force the OpenCL UR adapter to dodge the Level-Zero abort on this xe/kernel-7.0 host.
ENV ONEAPI_DEVICE_SELECTOR=opencl:gpu
ENV PATH="/opt/stable-diffusion.cpp/build/bin:$PATH"
WORKDIR /work
ENTRYPOINT ["sd-cli"]
