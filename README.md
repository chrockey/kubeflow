# Kakao Cloud + Kubeflow training template

A minimal, working example of how to run distributed PyTorch training on
[Kakao Cloud](https://www.kakaocloud.com/) using
[Kubeflow Trainer](https://www.kubeflow.org/docs/components/trainer/) (`trainer.kubeflow.org/v1alpha1`).

The repo contains:
- A Dockerfile and build/push script for the Kakao Container Registry (KCR).
- A `TrainingRuntime` and a `TrainJob` you can `kubectl apply` as-is to verify
  your cluster wiring.

## Prerequisites

- A Kakao Cloud Kubernetes namespace (this repo uses `kbm-g-np-postech-a` as an example).
- `kubectl` configured for that cluster, with the Kubeflow Trainer CRDs already installed.
- `docker` on your local machine, with access to push to KCR (`postech-a.kr-central-2.kcr.dev`).

## Workflow

### Step 1 — Set up your local `.env`

Create a `.env` file at the repo root with your credentials:

```bash
REGISTRY_USERNAME=your-kcr-username
REGISTRY_PASSWORD=your-kcr-password
WANDB_API_KEY=your-wandb-key   # from https://wandb.ai/authorize
```

`.env` is gitignored. `docker_build.sh` reads `REGISTRY_USERNAME` /
`REGISTRY_PASSWORD` from it, and you can substitute `WANDB_API_KEY` into
`example-training.yaml` at apply time (see Step 4) instead of creating a
Kubernetes `Secret`.

### Step 2 — Build and push the training image

```bash
./docker/docker_build.sh latest --push
```

The script logs in to KCR with the credentials from `.env`, builds
`docker/Dockerfile`, and pushes the result. Image tags follow the format
`postech-a.kr-central-2.kcr.dev/<your-username>/<image-name>:<tag>`. Edit
`REGISTRY` and `IMAGE_NAME` in `docker/docker_build.sh` to match your KCR
namespace.

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

`example-training.yaml` has `WANDB_API_KEY` set to a placeholder
`<YOUR_WANDB_API_KEY>`. Substitute it from `.env` at apply time:

```bash
set -a && source .env && set +a
sed "s|<YOUR_WANDB_API_KEY>|$WANDB_API_KEY|" kubeflow/example-training.yaml \
  | kubectl apply -f -

kubectl get trainjobs -n kbm-g-np-postech-a
kubectl logs -f -n kbm-g-np-postech-a -l trainer.kubeflow.org/trainjob-name=example-training
```

To adapt this for a real training job, change:
- `metadata.name` — unique per job
- `spec.trainer.numProcPerNode` and `resourcesPerNode` — GPUs/CPU/memory per node
- `spec.trainer.env` — env vars (e.g. `HF_TOKEN`, `ATTN_BACKEND`)
- `spec.trainer.args` — the bash block that runs `torchrun ... train.py ...`
- `spec.podTemplateOverrides` — add `volumes` / `volumeMounts` if you need a PVC
  for datasets or checkpoints (e.g. mount a shared PVC at `/workspace`)

## File reference

| File | Purpose |
|---|---|
| `docker/Dockerfile` | CUDA 12.8 + PyTorch + flash-attn + spconv image (Blackwell / B200) |
| `docker/docker_build.sh` | Build, optionally test, optionally push to KCR (reads `.env`) |
| `kubeflow/training-runtime.yaml` | `TrainingRuntime` referenced by every `TrainJob` |
| `kubeflow/example-training.yaml` | Self-contained MNIST DDP `TrainJob` — use as a smoke test |

## Troubleshooting

- **`ImagePullBackOff`** — the cluster cannot pull from KCR. Make sure the
  namespace has an `imagePullSecret` for `postech-a.kr-central-2.kcr.dev`, or
  push the image to a registry the cluster already trusts.
- **`Bus error` / DataLoader crashes** — `/dev/shm` is too small. Mount an
  in-memory `emptyDir` at `/dev/shm` (see the `dshm` volume pattern in your own
  `TrainJob` after adapting from the example).
- **Sidecar interferes with NCCL** — disable Istio injection on the pod with
  `sidecar.istio.io/inject: "false"` (already set in `training-runtime.yaml`).
