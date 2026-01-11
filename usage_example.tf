# FIXME: This is not a complete example, it depends on variables defined out of scope.
# This is part of a larger infrastructure, and I haven't had time to extract a proper standalone
# example -- but other than the "incomplete" variable definitions, which should be easy to deduce
# this is complete.

# Hetzner Robot provider for dedicated servers
provider "hrobot" {
  username = var.hrobot_username
  password = var.hrobot_password
}

# Single SSH key for all dedicated servers (Hetzner Robot doesn't allow duplicate public keys)
resource "hrobot_ssh_key" "dedicated_servers" {
  name       = "dedicated-servers"
  public_key = var.ssh_public_key
}

# Wait for kube_hetzner cluster to be ready before installing dedicated servers.
# We explicitly depend on specific outputs rather than the entire module to avoid
# waiting for autoscaled_node_registries which can delay the installation.
resource "null_resource" "kube_hetzner_ready" {
  triggers = {
    k3s_token    = module.kube_hetzner.k3s_token
    k3s_endpoint = module.kube_hetzner.k3s_endpoint
    kubeconfig   = module.kube_hetzner.kubeconfig
    network_id   = module.kube_hetzner.network_id
  }
}

locals {
  # vSwitch configuration for cloud <-> bare metal networking
  vswitch_name    = "cloud-bare-metal-bridge"
  vswitch_vlan_id = 4000

  # Dedicated server configuration
  test_server_1_id   = 1234567
  test_server_1_name = "some-robot-node"
  test_server_1_ip   = "10.1.0.2"
}

# vSwitch to bridge the cloud <-> bare metal networks
resource "hrobot_vswitch" "cloud_bridge" {
  name = local.vswitch_name
  vlan = local.vswitch_vlan_id

  # Attach dedicated servers to vSwitch
  servers = [
    local.test_server_1_id
  ]
}

# Connect HCloud network to vSwitch for cloud <-> bare metal communication
resource "hcloud_network_subnet" "vswitch" {
  network_id   = module.kube_hetzner.network_id
  type         = "vswitch"
  vswitch_id   = hrobot_vswitch.cloud_bridge.id
  network_zone = "eu-central"
  ip_range     = "10.1.0.0/24"
}

# Enable route exposure to vSwitch for cloud <-> bare metal routing
# The kube_hetzner module creates the network without this setting, so we patch it via API
# Required for: https://docs.hetzner.com/cloud/networks/connect-dedi-vswitch/
resource "null_resource" "enable_vswitch_routes" {
  triggers = {
    network_id = module.kube_hetzner.network_id
    vswitch_id = hrobot_vswitch.cloud_bridge.id
  }

  provisioner "local-exec" {
    environment = {
      HCLOUD_TOKEN = nonsensitive(var.hcloud_token)
      NETWORK_ID   = module.kube_hetzner.network_id
    }
    command = "${path.module}/modules/dedicated_servers/scripts/enable-vswitch-routes.sh"
  }

  depends_on = [hcloud_network_subnet.vswitch]
}

# Dedicated server: test-server-1
module "test_server_1" {
  source = "./modules/dedicated_servers"

  server_id   = local.test_server_1_id
  server_name = local.test_server_1_name
  node_ip     = local.test_server_1_ip

  # SSH configuration (registered with Hetzner Robot for rescue mode)
  ssh_public_key      = var.ssh_public_key
  ssh_key_fingerprint = hrobot_ssh_key.dedicated_servers.fingerprint
  ssh_private_key     = var.ssh_private_key
  ssh_port            = var.ssh_port

  # Hetzner Robot API credentials (for rescue mode)
  hrobot_username = var.hrobot_username
  hrobot_password = var.hrobot_password

  # k3s agent configuration
  k3s_token       = module.kube_hetzner.k3s_token
  k3s_endpoint    = module.kube_hetzner.k3s_endpoint
  k3s_channel     = var.k3s_channel
  vswitch_vlan_id = hrobot_vswitch.cloud_bridge.vlan
  kubeconfig      = module.kube_hetzner.kubeconfig

  node_labels = [
    "instance.hetzner.cloud/provided-by=robot",
    "kubernetes.io/arch=amd64"
  ]

  depends_on = [null_resource.kube_hetzner_ready, hrobot_vswitch.cloud_bridge]
}
