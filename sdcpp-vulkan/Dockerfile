# Krea 2 Turbo on Intel Arc B580 via stable-diffusion.cpp — VULKAN backend.
#
# Why Vulkan: torch.xpu's Level-Zero compute backend aborts on Battlemage + xe +
# kernel >= 7.0 (intel/compute-runtime #872/#922). Vulkan uses Mesa ANV — a
# totally separate driver stack that drives the B580 fine (vulkaninfo sees it as
# a discrete GPU). ggml/stable-diffusion.cpp added Krea 2 support 2026-06-25.
#
# Base ubuntu:25.10 for Mesa >= 25.2 (Battlemage ANV support).

FROM ubuntu:25.10

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        git cmake build-essential ninja-build \
        libvulkan-dev vulkan-tools mesa-vulkan-drivers \
        glslc glslang-tools spirv-tools spirv-headers \
        libgomp1 ca-certificates curl python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone --recursive --depth 1 https://github.com/leejet/stable-diffusion.cpp

WORKDIR /opt/stable-diffusion.cpp
RUN cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DSD_VULKAN=ON \
 && cmake --build build --config Release -j"$(nproc)" \
 && test -x build/bin/sd-cli && echo "BUILD_OK: sd-cli binary present"

ENV PATH="/opt/stable-diffusion.cpp/build/bin:$PATH"
WORKDIR /work
ENTRYPOINT ["sd-cli"]
