# Kakao Cloud + Kubeflow training template

A minimal, working example of how to run distributed PyTorch training on
[Kakao Cloud](https://www.kakaocloud.com/) using
[Kubeflow Trainer](https://www.kubeflow.org/docs/components/trainer/) (`trainer.kubeflow.org/v1alpha1`).

The repo contains:
- A Dockerfile and build/push script for the
  [Kakao Container Registry (KCR)](https://www.kakaocloud.com/service/container-registry).
- A `TrainingRuntime` and a `TrainJob` you can `kubectl apply` as-is to verify
  your cluster wiring.
- A `Secret` template for injecting your WANDB API key without committing it.

## Prerequisites

- A Kakao Cloud Kubernetes namespace (this repo uses `kbm-g-np-postech-a` as an example).
- `kubectl` configured for that cluster, with the Kubeflow Trainer CRDs already installed.
- `docker` on your local machine, with access to push to KCR (`postech-a.kr-central-2.kcr.dev`).

## Workflow

### Step 1 — Build and push the training image

1. Copy the credentials template and fill it in:
   ```bash
   cp docker/.env.registry.example docker/.env.registry
   $EDITOR docker/.env.registry   # set REGISTRY_USERNAME and REGISTRY_PASSWORD
   ```
   `docker/.env.registry` is gitignored.

2. Build and push:
   ```bash
   ./docker/docker_build.sh latest --push
   ```
   The script logs in to KCR with the credentials above, builds
   `docker/Dockerfile`, and pushes the result. Image tags follow the format
   `postech-a.kr-central-2.kcr.dev/<your-username>/<image-name>:<tag>`. Edit
   `REGISTRY` and `IMAGE_NAME` in `docker/docker_build.sh` to match your KCR
   namespace.

### Step 2 — Create the WANDB secret (optional)

If you use [Weights & Biases](https://wandb.ai/), inject your API key as a
Kubernetes `Secret` so the key never touches your YAML manifests.

```bash
cp kubeflow/wandb-secret.example.yaml kubeflow/wandb-secret.yaml
$EDITOR kubeflow/wandb-secret.yaml   # paste your key from https://wandb.ai/authorize
kubectl apply -f kubeflow/wandb-secret.yaml
```

`kubeflow/wandb-secret.yaml` is gitignored — only the `*.example.yaml` template
is tracked.

If you don't care about secret hygiene, you can skip this step and hard-code
`WANDB_API_KEY` (and any other tokens like `HF_TOKEN`) directly in the
`TrainJob`'s `env:` block. Simpler, but **do not commit** that variant.

### Step 3 — Apply the TrainingRuntime

```bash
kubectl apply -f kubeflow/training-runtime.yaml
```

`TrainingRuntime` is a reusable template that pins the container image and
parallelism policy. Multiple `TrainJob`s can reference the same runtime by
name. Edit the `image:` field to point at the tag you pushed in Step 1.

### Step 4 — Submit a TrainJob

The included `example-training.yaml` is a self-contained 2-GPU MNIST DDP job —
it generates its own training script inline, so you can verify the whole stack
without any external code or dataset.

```bash
kubectl apply -f kubeflow/example-training.yaml
kubectl get trainjobs -n kbm-g-np-postech-a
kubectl logs -f -n kbm-g-np-postech-a -l trainer.kubeflow.org/trainjob-name=example-training
```

To adapt this for a real training job, change:
- `metadata.name` — unique per job
- `spec.trainer.numProcPerNode` and `resourcesPerNode` — GPUs/CPU/memory per node
- `spec.trainer.env` — env vars and secret refs (e.g. `HF_TOKEN`, `ATTN_BACKEND`)
- `spec.trainer.args` — the bash block that runs `torchrun ... train.py ...`
- `spec.podTemplateOverrides` — add `volumes` / `volumeMounts` if you need a PVC
  for datasets or checkpoints (e.g. mount a shared PVC at `/workspace`)

## File reference

| File | Purpose |
|---|---|
| `docker/Dockerfile` | CUDA 12.8 + PyTorch + flash-attn + spconv image (Blackwell / B200) |
| `docker/docker_build.sh` | Build, optionally test, optionally push to KCR |
| `docker/.env.registry.example` | Template for KCR credentials (copy to `.env.registry`) |
| `kubeflow/training-runtime.yaml` | `TrainingRuntime` referenced by every `TrainJob` |
| `kubeflow/example-training.yaml` | Self-contained MNIST DDP `TrainJob` — use as a smoke test |
| `kubeflow/wandb-secret.example.yaml` | Template for the WANDB API-key `Secret` |

## Troubleshooting

- **`ImagePullBackOff`** — the cluster cannot pull from KCR. Make sure the
  namespace has an `imagePullSecret` for `postech-a.kr-central-2.kcr.dev`, or
  push the image to a registry the cluster already trusts.
- **`Bus error` / DataLoader crashes** — `/dev/shm` is too small. Mount an
  in-memory `emptyDir` at `/dev/shm` (see the `dshm` volume pattern in your own
  `TrainJob` after adapting from the example).
- **Sidecar interferes with NCCL** — disable Istio injection on the pod with
  `sidecar.istio.io/inject: "false"` (already set in `training-runtime.yaml`).
