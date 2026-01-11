# Hetzner Robot Dedicated Servers as k3s Agents

This Terraform module enables provisioning Hetzner bare-metal dedicated servers as worker nodes in a k3s cluster managed by the kube-hetzner module. The module uses a kexec-based installation approach that boots the openSUSE installer directly from the Hetzner rescue system using an embedded AutoYaST profile.

## Provisioning Pipeline

The provisioning pipeline works in stages:

1. Disabling the Hetzner firewall (to avoid the 10-rule limit and allow Cilium VXLAN traffic)
2. Booting into rescue mode via the Robot API
3. Running the MicroOS installer with AutoYaST to configure RAID-0 across all disks
4. Installing packages to match cloud nodes by extracting the list from the kube-hetzner packer template
5. Setting up vSwitch VLAN networking for cluster communication
6. Joining the k3s cluster as an agent node

## AutoYaST Configuration

The AutoYaST profile configures MicroOS with:

- SELinux enforcing
- systemd-boot
- Custom SSH port with key-only authentication
- A systemd service that runs restorecon on boot to fix SELinux contexts for files created during installation

Network configuration is preserved from the rescue system through the installer via linuxrc ifcfg parameters.

## Disk Handling

Disk handling uses disk-by-id paths sorted by serial number to ensure deterministic ordering across reboots, since NVMe device names like nvme0n1 can change based on driver probe timing.
