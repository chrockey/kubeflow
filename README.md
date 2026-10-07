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

### 0. Clone this repo in your Kakao Cloud notebook

Open a terminal in your Kakao Cloud notebook instance (which already has
`kubectl` and `docker` configured for your namespace) and clone the repo:

```bash
git clone https://github.com/chrockey/kubeflow.git
cd kubeflow
```

All subsequent steps run from this directory.

### 1. Create `.env` at the repo root

```bash
REGISTRY_URL=your-registry-url         # e.g. postech-a.kr-central-2.kcr.dev
REGISTRY_NAMESPACE=your-kcr-namespace  # your KCR account, usually your user name
REGISTRY_USERNAME=your-kcr-username
REGISTRY_PASSWORD=your-kcr-password
WANDB_API_KEY=your-wandb-key   # https://wandb.ai/authorize
WANDB_ENTITY=your-wandb-entity # your W&B user or team; set explicitly (see "W&B" below)
```

`.env` is gitignored and holds per-user credentials and registry info.
`docker_build.sh` reads everything from it, and step 3 below loads it into a
Kubernetes Secret for the TrainJob.

> [!NOTE]
> `REGISTRY_NAMESPACE` is your **Kakao Container Registry account**
> (usually your user name), *not* the Kubernetes namespace of your cluster
> (e.g. `kbm-g-np-postech-a`). The two are unrelated. The full image tag
> built by `docker_build.sh` will be
> `${REGISTRY_URL}/${REGISTRY_NAMESPACE}/kubeflow-train:latest`.

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

Then set `secretKeyRef.name` in `kubeflow/example-training.yaml` to the Secret
you just created (`train-env-<your-name>`), and replace `<your-name>` in the job name. The TrainJob will then read
`WANDB_API_KEY` and `WANDB_ENTITY` (and any other variable in `.env`) from your
Secret with no per-job edits.

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
kubectl logs -f -n kbm-g-np-postech-a -l trainer.kubeflow.org/trainjob-name=example-training-<your-name>
```

`example-training.yaml` is a self-contained 2-GPU MNIST DDP job — it generates
its own training script inline, so it works as a smoke test with no external
code or dataset.

## Working in the shared namespace (practices as of 2026-10)

`kbm-g-np-postech-a` is one namespace shared by several people. Kubernetes objects carry no owner, so
everything below is about keeping your jobs, runs and files distinguishable from everyone else's.

### Names

- **End every job name with your user name**, e.g. `myproj-run12-<your-name>`. The name at the end is the only way to tell
  whose GPUs a pod holds; a project prefix (`pg-...`) says nothing about who to ask.
- Namespace-scoped objects with a fixed name collide: a second `kubectl apply` of `example-runtime` or
  `train-env` overwrites the first user's. Give **TrainingRuntimes and Secrets your name too**
  (`<your-name>-runtime`, `train-env-<your-name>`, `wandb-secret-<your-name>`).
- Throughout this README and the YAML files, **replace `<your-name>` with your own user name.**

### W&B: never log into someone else's account or run

- Keep your key in **your own Secret** and read it with `secretKeyRef` (step 3); never put a key in a manifest
  or a shared `.env`.
- Set **`WANDB_ENTITY` and `WANDB_PROJECT` explicitly in every job.** The default entity is whatever the key
  belongs to; a borrowed or stale key silently sends your runs to another person's account.
- In the notebook, check `wandb whoami` before launching; the notebook's `~/.netrc` may hold an old login.
- Make resumes continue the same run: store the run id next to the checkpoints (e.g. `wandb_id.txt`) and pass
  it back with `WANDB_RUN_ID=<id> WANDB_RESUME=allow`. Without it every restart opens a new run.
- Put `WANDB_DIR` (and the offline cache) inside your own directory on the PVC, not a shared `/workspace/wandb`.

### GPUs, CPUs and memory

- Since 2026-10 there is **no per-member GPU allocation**: anyone may use any free GPU, up to the namespace
  cap of **16 GPUs**. Others do the same, so a job may wait.
- A job that cannot be admitted stays *podless* (the TrainJob exists, no pod appears). Find out why with
  `kubectl get events --sort-by=.lastTimestamp | grep FailedCreate`: either the namespace quota is full (wait),
  or the admission webhook rejected the request.
- The webhook limits **host memory to about 239 Gi per GPU**, and to 128 Gi for a pod without GPUs.
- **CPU is the scarcer quota** (one CPU pool for the whole namespace). We size training at 8 CPU per GPU and a
  1-GPU simulator eval at 8-16 CPU; ask for what the job uses, not the node's maximum.
- Mount a memory-backed `/dev/shm` when DataLoader workers pass large batches (all ranks of a pod share it):

  ```yaml
  podTemplateOverrides:
    - targetJobs: [{name: node}]
      spec:
        volumes: [{name: dshm, emptyDir: {medium: Memory, sizeLimit: 64Gi}}]
        containers: [{name: node, volumeMounts: [{name: dshm, mountPath: /dev/shm}]}]
  ```

### Storage

- The notebook's home (`/home/jovyan`) is a small quota-limited disk. Writes fail with `EDQUOT` when it is
  full. Keep code, data, checkpoints and **caches** (`HF_HOME`, `TORCH_HOME`, `UV_CACHE_DIR`, `PIP_CACHE_DIR`,
  `WANDB_DIR`) on the shared PVC. Mount it in pods the same way the notebook sees it (e.g. PVC at `/workspace` =
  `/home/jovyan/<pvc>` in the notebook).
- Work under your own directory on the PVC (`/workspace/users/<your-name>/`).
- Pods run as root, so files they write are root-owned in the notebook (`sudo chown` to edit them).

### Code that a pod reads live

- A pod that runs code from the PVC reads the checkout **as it is when each file is imported**. Commit before
  launching, and do not switch branches in a checkout a running job uses. Use one `git worktree` per experiment.
- Do not edit a running shell script in place: bash reads it lazily and executes the edited bytes. Write a new
  file and `mv` it over the old one.

### Images

- Bake every dependency into the image (`docker/Dockerfile`, or an in-cluster kaniko build). A `pip install` at
  job start is slow, fragile and makes runs irreproducible.
- Tag images with a date (`myimage:20261007`), not only `latest`, and record the tag with each run.

### Long runs

- Save `model-last.pt` (with the optimizer state) periodically and wrap the training command in a retry loop that
  resumes from it, so a pod restart or an NCCL timeout costs minutes, not the run.
- Set a long collective timeout (`timeout=` in `init_process_group`) if one rank can stall on I/O.
- A node that keeps failing can be excluded with `nodeAffinity` `NotIn` on `kubernetes.io/hostname`.

### Watching

```bash
kubectl get trainjobs | grep <your-name>                         # your jobs
kubectl get pods | grep <your-name>                              # Pending = waiting for quota
kubectl logs -f -l trainer.kubeflow.org/trainjob-name=<job>
kubectl delete trainjob <job>                              # frees its GPUs immediately
```

## Files

| File | Purpose |
|---|---|
| `docker/Dockerfile` | Minimal CUDA 12.8 + PyTorch + torchvision + wandb image |
| `docker/docker_build.sh` | Build / test / push to KCR (reads `.env`) |
| `kubeflow/training-runtime.yaml` | Reusable `TrainingRuntime` with image and parallelism policy |
| `kubeflow/example-training.yaml` | MNIST DDP smoke-test `TrainJob` |
