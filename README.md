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
REGISTRY_URL=your-registry-url   # e.g. postech-a.kr-central-2.kcr.dev
REGISTRY_NAMESPACE=your-kcr-namespace
REGISTRY_USERNAME=your-kcr-username
REGISTRY_PASSWORD=your-kcr-password
WANDB_API_KEY=your-wandb-key   # https://wandb.ai/authorize
```

`.env` is gitignored and holds per-user credentials and registry info.
`docker_build.sh` reads everything from it, and step 3 below loads it into a
Kubernetes Secret for the TrainJob.

The image name itself (`kubeflow-train`) is defined in `docker/docker_build.sh`
and must match the `image:` field in `kubeflow/training-runtime.yaml`. Change
both if you want a different name.

### 2. Build and push the image

```bash
./docker/docker_build.sh latest --push
```

Image tag is built as `${REGISTRY_URL}/${REGISTRY_NAMESPACE}/kubeflow-train:latest`.

### 3. Load `.env` into a Kubernetes Secret (one-time)

Secrets are namespace-scoped, so in a shared namespace pick a unique name
(e.g. `train-env-<your-name>`) to avoid clobbering other users:

```bash
kubectl create secret generic train-env-<your-name> \
  --from-env-file=.env \
  -n kbm-g-np-postech-a
```

Then update `kubeflow/example-training.yaml` so its `secretKeyRef.name`
matches the Secret you just created. The TrainJob will then read
`WANDB_API_KEY` (and any other variable in `.env`) from your Secret with no
per-job edits.

### 4. Apply the TrainingRuntime

Replace the `REGISTRY_URL` and `REGISTRY_NAMESPACE` placeholders in the
`image:` field of `kubeflow/training-runtime.yaml` with your real values from
`.env`, then:

```bash
kubectl apply -f kubeflow/training-runtime.yaml
```

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
| `docker/Dockerfile` | Minimal CUDA 12.8 + PyTorch + torchvision + wandb image |
| `docker/docker_build.sh` | Build / test / push to KCR (reads `.env`) |
| `kubeflow/training-runtime.yaml` | Reusable `TrainingRuntime` with image and parallelism policy |
| `kubeflow/example-training.yaml` | MNIST DDP smoke-test `TrainJob` |
