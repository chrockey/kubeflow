# Minimal CUDA + PyTorch image for the Kubeflow MNIST example.
# Use a runtime (not devel) base since no extensions are built in-image.
FROM nvidia/cuda:12.8.0-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

# System + Python 3.12
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y --no-install-recommends \
        python3.12 \
        python3.12-venv \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 \
    && curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12 \
    && pip install -U pip setuptools wheel

# PyTorch + torchvision (for MNIST) + wandb
RUN pip install --no-cache-dir \
        torch==2.10.0 torchvision --index-url https://download.pytorch.org/whl/cu128 \
    && pip install --no-cache-dir wandb

WORKDIR /workspace
