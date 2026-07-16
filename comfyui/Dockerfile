# Krea 2 Turbo on Intel Arc B580 (Battlemage) — ComfyUI + PyTorch XPU
#
# Base: Ubuntu 24.04. We install the Intel GPU *user-space* compute runtime
# (the kernel-side i915/xe driver lives on the HOST and is passed in via
# /dev/dri — see docker-compose.yml). PyTorch XPU wheels replace the old,
# now-deprecated IPEX stack.
#
# NOTE (verify-on-box): the three Intel runtime package names below are the
# Battlemage-era set from repositories.intel.com. If the build fails on one of
# them, `apt-cache search level-zero` inside the base image shows the current
# name — this is the one spot most likely to drift.

# ubuntu:25.10 + kobuk PPA: the distro-matched Intel compute stack that actually
# works on Battlemage + xe + kernel >= 7.0. The old repositories.intel.com
# "noble unified" packages ABI-mismatch the new xe KMD and abort on first kernel
# dispatch (verified). kobuk NEO 26.22 hits ~83 TFLOPS fp16 via torch-xpu.
FROM ubuntu:25.10

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1

# --- base tooling -----------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-venv python3-pip \
        git wget curl ca-certificates gnupg software-properties-common gpg-agent \
        libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# --- Intel GPU compute runtime (kobuk PPA, matched to this distro/kernel) ----
RUN add-apt-repository -y ppa:kobuk-team/intel-graphics \
 && apt-get update && apt-get install -y --no-install-recommends \
        intel-opencl-icd \
        libze-intel-gpu1 \
        libze1 \
        clinfo \
    && rm -rf /var/lib/apt/lists/*

# --- python venv + PyTorch XPU ----------------------------------------------
# Upstream XPU wheels (IPEX no longer required). Pin torch minor as needed.
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --upgrade pip \
 && pip install torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/xpu

# --- ComfyUI ----------------------------------------------------------------
WORKDIR /opt
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git
WORKDIR /opt/ComfyUI
RUN pip install -r requirements.txt

# --- Krea 2 GGUF custom node (fork with Krea2 arch support) ------------------
# stock city96/ComfyUI-GGUF does NOT load Krea 2 files yet.
RUN git clone --depth 1 https://github.com/molbal/ComfyUI-GGUF.git \
        custom_nodes/ComfyUI-GGUF \
 && pip install --no-deps gguf sentencepiece protobuf

# Build-time smoke: import must succeed (XPU device is only testable at RUNTIME
# on real hardware — see entrypoint).
RUN python3 -c "import torch, torchvision; print('torch', torch.__version__)"

COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8188
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
