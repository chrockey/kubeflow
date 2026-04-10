# Kakao Cloud + Kubeflow training template

A minimal template for running distributed PyTorch training on
[Kakao Cloud](https://www.kakaocloud.com/) with
[Kubeflow Trainer](https://www.kubeflow.org/docs/components/trainer/):
build a CUDA image, push it to the Kakao Container Registry (KCR), and
submit a `TrainJob`.

## Prerequisites

- A Kakao Cloud Kubernetes namespace with the Kubeflow Trainer CRDs installed
- `kubectl` configured for that namespace
- `docker` with push access to KCR

## Workflow

### 1. Create `.env` at the repo root

```bash
REGISTRY_USERNAME=your-kcr-username
REGISTRY_PASSWORD=your-kcr-password
WANDB_API_KEY=your-wandb-key   # https://wandb.ai/authorize
```

`.env` is gitignored. It is the single source of truth: `docker_build.sh`
reads it for image push, and the next step loads it into a Kubernetes Secret
for the TrainJob.

### 2. Build and push the image

```bash
./docker/docker_build.sh latest --push
```

Edit `REGISTRY` and `IMAGE_NAME` in `docker/docker_build.sh` to match your KCR
namespace.

### 3. Load `.env` into a Kubernetes Secret (one-time)

```bash
kubectl create secret generic train-env \
  --from-env-file=.env \
  -n kbm-g-np-postech-a
```

The TrainJob references `train-env` via `secretKeyRef`, so `WANDB_API_KEY`
(and any other variable in `.env`) is injected into the pod with no per-job
edits.

### 4. Apply the TrainingRuntime

```bash
kubectl apply -f kubeflow/training-runtime.yaml
```

Edit the `image:` field to point at the tag you pushed in step 2.

### 5. Submit the TrainJob

```bash
kubectl apply -f kubeflow/example-training.yaml
kubectl logs -f -n kbm-g-np-postech-a -l trainer.kubeflow.org/trainjob-name=example-training
```

`example-training.yaml` is a self-contained 2-GPU MNIST DDP job — it generates
its own training script inline, so it works as a smoke test with no external
code or dataset.

## Files

| File | Purpose |
|---|---|
| `docker/Dockerfile` | CUDA 12.8 + PyTorch + flash-attn + spconv (B200) |
| `docker/docker_build.sh` | Build / test / push to KCR (reads `.env`) |
| `kubeflow/training-runtime.yaml` | Reusable `TrainingRuntime` with image and parallelism policy |
| `kubeflow/example-training.yaml` | MNIST DDP smoke-test `TrainJob` |
