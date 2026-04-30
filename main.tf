resource "runpod_pod" "ollama" {
  name       = "ollama-ephemeral"
  image_name = "runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04"

  gpu_count    = var.gpu_count
  gpu_type_ids = var.gpu_types

  cloud_type           = "COMMUNITY"
  compute_type         = "GPU"
  country_codes        = var.country_codes
  data_center_priority = "availability"
  gpu_type_priority    = var.gpu_type_priority
  interruptible        = var.interruptible

  ports             = ["22/tcp"]
  support_public_ip = true

  # No network volume — container disk holds OS + models for session
  container_disk_in_gb = var.container_disk_in_gb
  volume_in_gb         = var.volume_in_gb

  env = {
    PUBLIC_KEYS = join("\n", var.ssh_public_keys)
    MODELS      = var.ollama_models

    # Ollama server tuning — adjust these to control VRAM usage
    OLLAMA_HOST              = "127.0.0.1"
    OLLAMA_FLASH_ATTENTION   = "1"
    OLLAMA_KV_CACHE_TYPE     = "q4_0"
    OLLAMA_NUM_CTX           = "65536"
    OLLAMA_KEEP_ALIVE        = "10m"
    OLLAMA_MAX_LOADED_MODELS = "1"
    OLLAMA_NUM_PARALLEL      = "1"
  }

  docker_start_cmd = [
    "bash", "-c", <<-EOT
      apt-get update -qq && apt-get install -y -qq openssh-server curl zstd htop

      mkdir -p /run/sshd ~/.ssh
      [ -n "$PUBLIC_KEYS" ] && echo "$PUBLIC_KEYS" >> ~/.ssh/authorized_keys
      chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
      sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/'              /etc/ssh/sshd_config
      sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/'    /etc/ssh/sshd_config
      sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
      /usr/sbin/sshd

      echo 'export TERM=xterm-256color' >> ~/.bashrc

      curl -fsSL https://ollama.com/install.sh | sh

      /usr/local/bin/ollama serve &
      sleep 8

      echo "$MODELS" | tr "," "\n" | while read -r model; do
        [ -n "$model" ] && /usr/local/bin/ollama pull "$model"
      done

      sleep infinity
    EOT
  ]

  lifecycle {
    ignore_changes = [gpu_type_ids]
  }
}

# --- Write pod ID to disk via Terraform ---
# Replaces the shell redirect `terraform output -raw pod_id > .pod_id`
# The file is created/updated on every apply and deleted on destroy.

resource "local_file" "pod_id" {
  content  = runpod_pod.ollama.id
  filename = "${path.module}/.pod_id"
}

# --- Outputs ---

output "pod_id" {
  value = runpod_pod.ollama.id
}

output "ollama_models" {
  value = var.ollama_models
}

output "cost_per_hr" {
  value = runpod_pod.ollama.cost_per_hr
}

output "actual_data_center" {
  value = runpod_pod.ollama.actual_data_center
}
