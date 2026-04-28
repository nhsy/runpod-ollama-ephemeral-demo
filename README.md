# RunPod Ollama — Ephemeral GPU Inference

Ephemeral GPU inference on RunPod via Terraform + SSH tunnel. No persistent storage — models are downloaded fresh each session. Zero idle cost after `task down`.

## Quick Start

```bash
# First time setup
task init

# Deploy pod and connect
task up

# Verify Ollama is available
task verify

# End session (destroys pod)
task down
```

## Prerequisites

- [Taskfile](https://taskfile.dev) — task runner
- [Terraform](https://terraform.io) — infrastructure as code
- [runpodctl](https://github.com/runpod/runpodctl) — RunPod CLI
- [jq](https://stedolan.github.io/jq/) — JSON parser

## Available Tasks

| Task | Description |
|------|-------------|
| `up` | Deploy pod, wait for SSH, update config, open tunnel, wait for models |
| `down` | Destroy pod — zero ongoing cost |
| `redeploy` | Destroy and redeploy (picks up config changes) |
| `wait` | Poll until pod SSH is ready |
| `ssh-config` | Update ~/.ssh/config with pod IP/port |
| `ssh` | Open interactive SSH session |
| `start` | Start pod (if stopped) |
| `stop` | Stop pod and close tunnel |
| `tunnel` | Open Ollama tunnel in background (binds 0.0.0.0 for Docker access) |
| `tunnel:stop` | Close background tunnel |
| `forward` | Forward Ollama port 11434 to localhost (simple -L forward) |
| `verify` | Confirm Ollama is reachable |
| `status` | Show pod status and SSH endpoint |
| `cost` | Show estimated session cost |
| `models` | List loaded Ollama models |
| `gpu` | Show available GPUs with pricing |
| `bench` | Benchmark loaded models |
| `unload` | Unload a model from VRAM |
| `tf-plan` | Preview Terraform changes without applying |
| `lint` | Run linters |
| `init` | Terraform init |

## Environment

Set `RUNPOD_API_KEY` in `.env`:
```bash
echo "RUNPOD_API_KEY=rp_xxx" > .env
```

## Changing Models

Edit `terraform.tfvars` before running `task up`:

```hcl
ollama_models = "gemma4:e4b,qwen3.6:27b"
```

Or override inline:

```bash
TF_VAR_ollama_models="gemma4:e4b" task up
```

## GPU Recommendations

| GPU | VRAM | Cost | Notes |
|------|------|------|-------|
| **RTX A6000** | 48 GB | ~$0.33/hr | Mid-range option |
| **L40S** | 48 GB | ~$0.79/hr | High performance |
| **A100 PCIe** | 80 GB | ~$1.19/hr | Data center grade |
| **RTX PRO 6000 Blackwell** | 96 GB | ~$1.69/hr | Recommended for qwen3-coder-next |

**VRAM requirements for qwen3-coder-next:**
- Q4_K_M quantized: ~18 GB
- Recommended: 60 GB+ for best performance

## Cost

Costs vary by GPU. Examples (on-demand pricing):
- RTX A6000: ~$0.33/hour
- L40S: ~$0.79/hour
- A100 PCIe: ~$1.19/hour
- RTX PRO 6000 Blackwell: ~$1.69/hour

Zero idle cost — `task down` destroys the pod completely.
