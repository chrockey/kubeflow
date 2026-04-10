# Base image with CUDA 12.8 and cuDNN (devel for nvcc)
FROM nvidia/cuda:12.8.0-cudnn-devel-ubuntu22.04

# CUDA architecture for B200 (100) - Blackwell
ENV TORCH_CUDA_ARCH_LIST="10.0"
ENV FLASH_ATTN_CUDA_ARCHS="100"
ENV CUDA_HOME="/usr/local/cuda"

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Seoul

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    curl \
    git \
    git-lfs \
    ninja-build \
    libatlas-base-dev \
    libhdf5-dev \
    libcgal-dev \
    libeigen3-dev \
    libfreeimage-dev \
    libgflags-dev \
    libegl1 \
    libgl1 \
    libgomp1 \
    libopenblas-dev \
    libx11-6 \
    libxrender1 \
    protobuf-compiler \
    software-properties-common \
    wget \
    && rm -rf /var/lib/apt/lists/* \
    && git lfs install

# Install Python 3.12
RUN add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y python3.12 python3.12-dev python3.12-venv \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1

# Install pip for Python 3.12
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12 \
    && pip3 install -U pip setuptools wheel

# Install PyTorch 2.10.0 with CUDA 12.8 (Blackwell support)
RUN pip3 install torch==2.10.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

# Install Python dependencies (training-only, minimal)
COPY requirements-b200-train.txt /tmp/requirements.txt
RUN pip3 install --ignore-installed blinker -r /tmp/requirements.txt

# Install flash-attn
RUN pip3 install flash-attn --no-build-isolation

# Install spconv (sparse convolution) for B200
# Build from source following https://github.com/RayYoh/spconv-12.8
ENV CUMM_CUDA_VERSION="12.8"
ENV CUMM_CUDA_ARCH_LIST="10.0"
ENV CUMM_DISABLE_JIT="1"
ENV SPCONV_DISABLE_JIT="1"
ENV MAX_JOBS=4

# Build and install cumm
RUN pip3 install pccm \
    && git clone https://github.com/RayYoh/cumm.git /tmp/cumm \
    && cd /tmp/cumm \
    && python3 setup.py bdist_wheel \
    && pip3 install dist/*.whl \
    && rm -rf /tmp/cumm

# Build and install spconv
RUN git clone https://github.com/kenomo/spconv.git /tmp/spconv \
    && cd /tmp/spconv \
    && python3 setup.py bdist_wheel \
    && pip3 install dist/*.whl \
    && rm -rf /tmp/spconv

# Install CUDA extensions from source
WORKDIR /tmp/extensions

# nvdiffrast (differentiable rendering)
RUN git clone https://github.com/NVlabs/nvdiffrast.git \
    && pip3 install ./nvdiffrast --no-build-isolation

# diffoctreerast (octree-based rendering)
RUN git clone --recurse-submodules https://github.com/JeffreyXiang/diffoctreerast.git \
    && pip3 install ./diffoctreerast --no-build-isolation

# mip-splatting (Gaussian splatting)
RUN git clone https://github.com/autonomousvision/mip-splatting.git \
    && pip3 install ./mip-splatting/submodules/diff-gaussian-rasterization/ --no-build-isolation

# Clean up
RUN rm -rf /tmp/extensions

# Set working directory
WORKDIR /workspace
