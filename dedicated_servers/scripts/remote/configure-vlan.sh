#!/bin/bash
# Configure vSwitch VLAN interface on MicroOS
# This script runs on MicroOS via SSH
# Variables substituted by terraform templatefile():
#   - vswitch_vlan_id, vswitch_gateway, vswitch_subnet_cidr, node_ip
set -e

# Detect main ethernet interface (the one with default route)
MAIN_IFACE=$(ip -o route get to 1.1.1.1 | sed -n 's/.*dev \([a-z0-9]\+\).*/\1/p')
echo "Main interface: $MAIN_IFACE"

# Gateway for the vSwitch subnet (passed from terraform)
VSWITCH_GATEWAY="${vswitch_gateway}"

# Check if VLAN interface already exists
if nmcli connection show vlan${vswitch_vlan_id} &>/dev/null; then
  echo "VLAN interface vlan${vswitch_vlan_id} already exists, updating..."
  nmcli connection modify vlan${vswitch_vlan_id} \
    802-3-ethernet.mtu 1400 \
    ipv4.addresses '${node_ip}${vswitch_subnet_cidr}' \
    ipv4.method manual \
    ipv4.routes "10.0.0.0/8 $VSWITCH_GATEWAY"
else
  echo "Creating VLAN interface vlan${vswitch_vlan_id}..."
  nmcli connection add type vlan con-name vlan${vswitch_vlan_id} \
    ifname vlan${vswitch_vlan_id} \
    vlan.parent "$MAIN_IFACE" \
    vlan.id ${vswitch_vlan_id}

  # Configure VLAN interface (MTU 1400 required for vSwitch)
  nmcli connection modify vlan${vswitch_vlan_id} \
    802-3-ethernet.mtu 1400 \
    ipv4.addresses '${node_ip}${vswitch_subnet_cidr}' \
    ipv4.method manual \
    ipv4.routes "10.0.0.0/8 $VSWITCH_GATEWAY"
fi

# Bring up the VLAN interface
nmcli connection up vlan${vswitch_vlan_id}
echo "VLAN interface configured:"
ip addr show vlan${vswitch_vlan_id}

# Configure firewall to allow all traffic on the VLAN interface
# The vSwitch VLAN is used for Cilium VXLAN tunneling (port 8472) and health checks (port 4240)
# Cloud servers don't have firewalld, but MicroOS on dedicated servers does
# Without this, the interface defaults to the "public" zone which only allows SSH
if command -v firewall-cmd &>/dev/null; then
  echo "Configuring firewall zone for vlan${vswitch_vlan_id}..."
  firewall-cmd --zone=trusted --change-interface=vlan${vswitch_vlan_id} --permanent
  firewall-cmd --reload
  echo "VLAN interface added to trusted firewall zone"
fi
