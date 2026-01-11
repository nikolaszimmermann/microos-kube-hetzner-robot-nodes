# Server identification
variable "server_id" {
  description = "Hetzner Robot server ID (numeric)."
  type        = number
}

variable "server_name" {
  description = "Human-readable server name."
  type        = string
}

# SSH configuration (used for both rescue mode and installed OS)
variable "ssh_public_key" {
  description = "SSH public key for server access (registered with Hetzner Robot for rescue mode)."
  type        = string
}

variable "ssh_key_fingerprint" {
  description = "Fingerprint of the SSH key registered with Hetzner Robot (for rescue mode)."
  type        = string
}

variable "ssh_private_key" {
  description = "SSH private key for provisioning."
  type        = string
  sensitive   = true
}

variable "ssh_port" {
  description = "SSH port for server access."
  type        = number
  default     = 2277

  validation {
    condition     = var.ssh_port >= 1 && var.ssh_port <= 65535
    error_message = "SSH port must be between 1 and 65535."
  }
}

# Hetzner Robot API credentials (for rescue mode API calls)
variable "hrobot_username" {
  description = "Hetzner Robot API username."
  type        = string
  sensitive   = true
}

variable "hrobot_password" {
  description = "Hetzner Robot API password."
  type        = string
  sensitive   = true
}

# K3s cluster configuration
variable "k3s_token" {
  description = "K3s cluster token for agent registration."
  type        = string
  sensitive   = true
}

variable "k3s_endpoint" {
  description = "K3s API server endpoint (e.g., https://10.0.0.2:6443)."
  type        = string

  validation {
    condition     = can(regex("^https://", var.k3s_endpoint))
    error_message = "k3s_endpoint must be a valid HTTPS URL (e.g., https://10.0.0.2:6443)."
  }
}

variable "k3s_channel" {
  description = "K3s channel to install from (e.g., v1.31). Must match the cluster's initial_k3s_channel."
  type        = string

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+$", var.k3s_channel))
    error_message = "k3s_channel must be a valid version format (e.g., v1.31)."
  }
}

# vSwitch network configuration
variable "node_ip" {
  description = "Private IP address for the node on vSwitch network."
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.node_ip))
    error_message = "node_ip must be a valid IPv4 address (e.g., 10.1.0.10)."
  }
}

variable "vswitch_vlan_id" {
  description = "VLAN ID for vSwitch."
  type        = number
  default     = 4000
}

variable "vswitch_gateway" {
  description = "Gateway IP for vSwitch network (first IP of the subnet)."
  type        = string
  default     = "10.1.0.1"

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.vswitch_gateway))
    error_message = "vswitch_gateway must be a valid IPv4 address (e.g., 10.1.0.1)."
  }
}

variable "vswitch_subnet_cidr" {
  description = "Subnet CIDR for node IP on vSwitch network (e.g., /24)."
  type        = string
  default     = "/24"
}

variable "node_labels" {
  description = "Labels to apply to the k3s node."
  type        = list(string)
  default     = ["instance.hetzner.cloud/provided-by=robot"]
}

# Cluster access for node management
variable "kubeconfig" {
  description = "Kubeconfig for cluster access (used to delete stale node before reinstall)."
  type        = string
  sensitive   = true
}

# Provisioning timeouts (seconds)
variable "rescue_boot_wait" {
  description = "Seconds to wait for rescue system to boot after hardware reset."
  type        = number
  default     = 90
}

variable "microos_boot_wait" {
  description = "Seconds to wait for MicroOS to boot after installation."
  type        = number
  default     = 120
}

variable "microos_reboot_wait" {
  description = "Seconds to wait for MicroOS to reboot after package installation."
  type        = number
  default     = 60
}
