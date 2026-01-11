locals {
  # Read the packer template to extract package list and installation commands
  # This ensures dedicated servers use the same configuration as cloud servers
  packer_template_path = "${path.module}/../../.terraform/modules/kube_hetzner/packer-template/hcloud-microos-snapshots.pkr.hcl"
  packer_template      = file(local.packer_template_path)

  # Extract the base packages from the packer template (the list in needed_packages)
  # Pattern matches: ["package1 package2 ..."]
  packages_regex  = "concat\\(\\[\"([^\"]+)\"\\]"
  packages_match  = regex(local.packages_regex, local.packer_template)
  needed_packages = local.packages_match[0]
}

# Fetch existing server data
data "hrobot_server" "server" {
  server_id = var.server_id
}

# Firewall is disabled for dedicated servers to avoid Hetzner's 10-rule limit
# and to allow all traffic including VXLAN (port 8472) for Cilium networking
resource "null_resource" "disable_firewall" {
  triggers = {
    server_id = var.server_id
  }

  provisioner "local-exec" {
    environment = {
      HROBOT_USERNAME = nonsensitive(var.hrobot_username)
      HROBOT_PASSWORD = nonsensitive(var.hrobot_password)
      SERVER_ID       = var.server_id
    }
    command = "${path.module}/scripts/00-disable-firewall.sh"
  }
}

# Random string for temporary identity file
resource "random_string" "identity_file" {
  length  = 20
  lower   = true
  special = false
  numeric = true
  upper   = false
}

# AutoYaST configuration (replaces cloud-init)
locals {
  # AutoYaST profile for kexec-based MicroOS installation
  autoyast_profile = templatefile("${path.module}/templates/autoyast-microos.xml.tpl", {
    hostname       = var.server_name
    ssh_public_key = var.ssh_public_key
    ssh_port       = var.ssh_port
  })
}

# MicroOS Installation via rescue mode (kexec + AutoYaST)
resource "null_resource" "microos_installation" {
  triggers = {
    server_id   = var.server_id
    config_hash = sha256(local.autoyast_profile)
  }

  # Step 1: Enable rescue mode and reset server
  provisioner "local-exec" {
    environment = {
      HROBOT_USERNAME  = nonsensitive(var.hrobot_username)
      HROBOT_PASSWORD  = nonsensitive(var.hrobot_password)
      SERVER_ID        = var.server_id
      SSH_FINGERPRINT  = var.ssh_key_fingerprint
      RESCUE_BOOT_WAIT = var.rescue_boot_wait
    }
    command = "${path.module}/scripts/01-enable-rescue.sh"
  }

  # Step 2: Install MicroOS via kexec + AutoYaST
  provisioner "local-exec" {
    environment = {
      SSH_PRIVATE_KEY    = nonsensitive(var.ssh_private_key)
      SERVER_IP          = data.hrobot_server.server.server_ip
      IDENTITY_FILE_NAME = random_string.identity_file.id
      HROBOT_USERNAME    = nonsensitive(var.hrobot_username)
      HROBOT_PASSWORD    = nonsensitive(var.hrobot_password)
      SERVER_ID          = var.server_id
      SSH_PORT           = var.ssh_port
      INSTALL_SCRIPT = templatefile("${path.module}/scripts/remote/install-microos-kexec.sh", {
        server_id                = var.server_id
        server_name              = var.server_name
        ssh_public_key           = var.ssh_public_key
        autoyast_template_base64 = base64encode(local.autoyast_profile)
      })
    }
    command = "${path.module}/scripts/02-install-microos.sh"
  }

}

# Install packages (matching packer-template/hcloud-microos-snapshots.pkr.hcl)
resource "null_resource" "microos_packages" {
  triggers = {
    installation = null_resource.microos_installation.id
    packages     = local.needed_packages
  }

  provisioner "local-exec" {
    environment = {
      SSH_PRIVATE_KEY     = nonsensitive(var.ssh_private_key)
      SERVER_IP           = data.hrobot_server.server.server_ip
      IDENTITY_FILE_NAME  = random_string.identity_file.id
      SSH_PORT            = var.ssh_port
      NEEDED_PACKAGES     = local.needed_packages
      MICROOS_BOOT_WAIT   = var.microos_boot_wait
      MICROOS_REBOOT_WAIT = var.microos_reboot_wait
      PACKAGES_SCRIPT = templatefile("${path.module}/scripts/remote/install-packages.sh", {
        needed_packages = local.needed_packages
      })
    }
    command = "${path.module}/scripts/03-install-packages.sh"
  }

  depends_on = [null_resource.microos_installation]
}

# K3s agent configuration
locals {
  k3s_config = yamlencode({
    "node-name"          = var.server_name
    "server"             = var.k3s_endpoint
    "token"              = var.k3s_token
    "node-ip"            = var.node_ip
    "prefer-bundled-bin" = true
    "selinux"            = true
    "kubelet-arg" = [
      "cloud-provider=external",
      "volume-plugin-dir=/var/lib/kubelet/volumeplugins",
      "kube-reserved=cpu=50m,memory=300Mi,ephemeral-storage=1Gi",
      "system-reserved=cpu=250m,memory=300Mi"
    ]
    "node-label" = concat(var.node_labels, ["k3s_upgrade=true"])
  })
}

# Configure vSwitch VLAN for cluster networking
resource "null_resource" "vlan_configuration" {
  triggers = {
    packages        = null_resource.microos_packages.id
    vswitch_vlan_id = var.vswitch_vlan_id
    node_ip         = var.node_ip
  }

  provisioner "local-exec" {
    environment = {
      SSH_PRIVATE_KEY    = nonsensitive(var.ssh_private_key)
      SERVER_IP          = data.hrobot_server.server.server_ip
      IDENTITY_FILE_NAME = random_string.identity_file.id
      SSH_PORT           = var.ssh_port
      VLAN_SCRIPT = templatefile("${path.module}/scripts/remote/configure-vlan.sh", {
        vswitch_vlan_id     = var.vswitch_vlan_id
        vswitch_gateway     = var.vswitch_gateway
        vswitch_subnet_cidr = var.vswitch_subnet_cidr
        node_ip             = var.node_ip
      })
    }
    command = "${path.module}/scripts/04-configure-vlan.sh"
  }

  depends_on = [null_resource.microos_packages]
}

# Install k3s-agent
resource "null_resource" "k3s_agent_installation" {
  triggers = {
    vlan_config  = null_resource.vlan_configuration.id
    k3s_endpoint = var.k3s_endpoint
    config_hash  = nonsensitive(sha256(local.k3s_config))
  }

  provisioner "local-exec" {
    environment = {
      SSH_PRIVATE_KEY        = nonsensitive(var.ssh_private_key)
      SERVER_IP              = data.hrobot_server.server.server_ip
      IDENTITY_FILE_NAME     = random_string.identity_file.id
      SSH_PORT               = var.ssh_port
      K3S_CONFIG             = nonsensitive(local.k3s_config)
      K3S_INSTALL_SCRIPT = templatefile("${path.module}/scripts/remote/install-k3s.sh", {
        k3s_channel = var.k3s_channel
      })
      CLEANUP_SCRIPT = nonsensitive(templatefile("${path.module}/scripts/remote/cleanup-stale-node.sh", {
        server_name        = var.server_name
        kubeconfig_content = var.kubeconfig
      }))
      START_SCRIPT = nonsensitive(templatefile("${path.module}/scripts/remote/start-k3s-agent.sh", {
        server_name        = var.server_name
        kubeconfig_content = var.kubeconfig
      }))
    }
    command = "${path.module}/scripts/05-install-k3s.sh"
  }

  depends_on = [null_resource.vlan_configuration]
}
