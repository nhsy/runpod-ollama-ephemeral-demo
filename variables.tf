locals {
  # Exact list of GPU type IDs from https://docs.runpod.io/api-reference/pods/POST/pods
  allowed_gpu_types = [
    "NVIDIA GeForce RTX 4090",
    "NVIDIA A40",
    "NVIDIA RTX A5000",
    "NVIDIA GeForce RTX 5090",
    "NVIDIA H100 80GB HBM3",
    "NVIDIA GeForce RTX 3090",
    "NVIDIA RTX A4500",
    "NVIDIA L40S",
    "NVIDIA H200",
    "NVIDIA L4",
    "NVIDIA RTX 6000 Ada Generation",
    "NVIDIA A100-SXM4-80GB",
    "NVIDIA RTX 4000 Ada Generation",
    "NVIDIA RTX A6000",
    "NVIDIA A100 80GB PCIe",
    "NVIDIA RTX 2000 Ada Generation",
    "NVIDIA RTX A4000",
    "NVIDIA RTX PRO 6000 Blackwell Server Edition",
    "NVIDIA H100 PCIe",
    "NVIDIA H100 NVL",
    "NVIDIA L40",
    "NVIDIA B200",
    "NVIDIA GeForce RTX 3080 Ti",
    "NVIDIA RTX PRO 6000 Blackwell Workstation Edition",
    "NVIDIA GeForce RTX 3080",
    "NVIDIA GeForce RTX 3070",
    "AMD Instinct MI300X OAM",
    "NVIDIA GeForce RTX 4080 SUPER",
    "Tesla V100-PCIE-16GB",
    "Tesla V100-SXM2-32GB",
    "NVIDIA RTX 5000 Ada Generation",
    "NVIDIA GeForce RTX 4070 Ti",
    "NVIDIA RTX 4000 SFF Ada Generation",
    "NVIDIA GeForce RTX 3090 Ti",
    "NVIDIA RTX A2000",
    "NVIDIA GeForce RTX 4080",
    "NVIDIA A30",
    "NVIDIA GeForce RTX 5080",
    "Tesla V100-FHHL-16GB",
    "NVIDIA H200 NVL",
    "Tesla V100-SXM2-16GB",
    "NVIDIA RTX PRO 6000 Blackwell Max-Q Workstation Edition",
    "NVIDIA A5000 Ada",
    "Tesla V100-PCIE-32GB",
    "NVIDIA GeForce RTX 3080TI",
    "Tesla T4",
    "NVIDIA RTX A30"
  ]

  # Country codes identified in documentation (e.g. from EU-RO-1, CA-MTL-1, US-TX-1)
  allowed_country_codes = ["AU", "CA", "CZ", "DE", "FR", "IS", "JP", "NL", "NO", "PL", "RO", "SE", "US"]
}

variable "ssh_public_keys" {
  description = "List of SSH public keys to authorize (contents of ~/.ssh/*.pub)"
  type        = list(string)
}

variable "ollama_models" {
  description = "Comma-separated Ollama model tags to pull on startup"
  type        = string
  default     = "qwen3.6:27b"
}

variable "gpu_types" {
  type    = list(string)
  default = ["NVIDIA GeForce RTX 4090", "NVIDIA GeForce RTX 3090"]

  validation {
    condition     = alltrue([for g in var.gpu_types : contains(local.allowed_gpu_types, g)])
    error_message = "One or more provided GPU types are invalid. Must exactly match a valid RunPod gpuTypeId (e.g., 'NVIDIA GeForce RTX 4090')."
  }
}

variable "country_codes" {
  description = "ISO country codes to restrict GPU search. Set to null to accept all regions."
  type        = list(string)
  default     = ["NL", "CZ", "FR", "SE", "DE", "PL"]

  validation {
    condition     = var.country_codes == null || alltrue([for c in var.country_codes : contains(local.allowed_country_codes, c)])
    error_message = "All country codes must be valid RunPod ISO codes (e.g., US, NL, RO)."
  }
}

variable "gpu_count" {
  type    = number
  default = 1
}

variable "container_disk_in_gb" {
  type    = number
  default = 100
}

variable "volume_in_gb" {
  type    = number
  default = 0
}

variable "interruptible" {
  type    = bool
  default = false
}
