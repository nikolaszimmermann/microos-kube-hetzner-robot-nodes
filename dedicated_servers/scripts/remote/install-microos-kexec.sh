#!/bin/bash
# Install MicroOS on dedicated server using kexec + AutoYaST
# This script runs on the Hetzner rescue system via SSH
# Variables substituted by terraform templatefile():
#   - server_id, server_name, ssh_public_key, autoyast_template_base64
set -e

printf "\n##### Step 2.1: Installing dependencies...\n"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y kexec-tools cpio xz-utils perl

#############################################################################
# Detect ALL disks and sort by serial number for deterministic ordering
#############################################################################
# CRITICAL: NVMe device names (nvme0n1, nvme1n1) are NON-DETERMINISTIC between boots!
# The kernel enumerates NVMe devices based on driver probe timing, which varies.
# We MUST sort by stable identifier (serial number) to ensure consistent disk ordering.

# Function to get stable disk identifier for sorting (works for NVMe and SATA/SAS)
get_disk_serial() {
  cat "/sys/block/$(basename "$1")/device/serial" 2>/dev/null | tr -d ' '
}

# Function to get disk-by-id path (stable across reboots)
get_disk_by_id() {
  local disk=$1
  local serial=$(get_disk_serial "$disk")
  if [ -n "$serial" ]; then
    # Find the by-id link that matches this serial
    for link in /dev/disk/by-id/*; do
      if [ -L "$link" ] && [ "$(readlink -f "$link")" = "$disk" ]; then
        # Prefer nvme-* or scsi-* links over wwn-* or ata-*
        case "$(basename "$link")" in
          nvme-*|scsi-*) echo "/dev/disk/by-id/$(basename "$link")"; return ;;
        esac
      fi
    done
    # Fallback to first matching link
    for link in /dev/disk/by-id/*; do
      if [ -L "$link" ] && [ "$(readlink -f "$link")" = "$disk" ]; then
        echo "/dev/disk/by-id/$(basename "$link")"
        return
      fi
    done
  fi
  # Final fallback to device name
  echo "$disk"
}

ALL_DISKS=""
for disk in /dev/sd[a-z] /dev/nvme[0-9]n1; do
  if [ -b "$disk" ]; then
    ALL_DISKS="$ALL_DISKS $disk"
  fi
done
ALL_DISKS=$(echo $ALL_DISKS | xargs)  # trim whitespace

# Sort disks by serial number for deterministic ordering across reboots
if [ -n "$ALL_DISKS" ]; then
  SORTED_DISKS=""
  for disk in $ALL_DISKS; do
    serial=$(get_disk_serial "$disk")
    if [ -z "$serial" ]; then
      serial="unknown_$(basename "$disk")"  # fallback to device name if no serial
    fi
    SORTED_DISKS="$SORTED_DISKS $serial:$disk"
  done
  # Sort by serial number, then extract just the device paths
  ALL_DISKS=$(echo $SORTED_DISKS | tr ' ' '\n' | sort | cut -d: -f2 | tr '\n' ' ' | xargs)
  echo "Disk serial numbers (sorted):"
  echo "$SORTED_DISKS" | tr ' ' '\n' | sort
fi

if [ -z "$ALL_DISKS" ]; then
  echo "ERROR: No suitable target disk found"
  lsblk
  exit 1
fi

FIRST_DISK=$(echo $ALL_DISKS | awk '{print $1}')
DISK_COUNT=$(echo $ALL_DISKS | wc -w)
echo "All disks found: $ALL_DISKS"
echo "Disk count: $DISK_COUNT"
echo "First disk: $FIRST_DISK"

# Require at least 2 disks for RAID-0
if [ "$DISK_COUNT" -lt 2 ]; then
  echo "ERROR: This module requires at least 2 disks for RAID-0. Found: $DISK_COUNT"
  exit 1
fi

# Get disk-by-id paths for AutoYaST
echo "Mapping disks to disk-by-id paths..."
DISK_BY_ID_LIST=""
for disk in $ALL_DISKS; do
  by_id=$(get_disk_by_id "$disk")
  DISK_BY_ID_LIST="$DISK_BY_ID_LIST $by_id"
  echo "  $disk -> $by_id"
done
DISK_BY_ID_LIST=$(echo $DISK_BY_ID_LIST | xargs)

#############################################################################
# Capture network configuration from rescue system
#############################################################################
NETDEV=$(ip -o route get to 1.1.1.1 | sed -n 's/.*dev \([a-z0-9.]\+\).*/\1/p')
NET_IP=$(ip -o route get to 1.1.1.1 | sed -n 's/.*src \([0-9.]\+\).*/\1/p')
NET_GW=$(ip -o route get to 1.1.1.1 | sed -n 's/.*via \([0-9.]\+\).*/\1/p')
NET_CIDR=$(ip -o addr show dev "$NETDEV" | awk '{print $4}' | head -1)
NET_PREFIX=$(echo "$NET_CIDR" | cut -d'/' -f2)
# Extract DNS servers from systemd-resolved's upstream config (IPv4 only)
# Store as newline-separated list, get first one separately for ifcfg
NET_DNS_ALL=$(grep '^nameserver' /run/systemd/resolve/resolv.conf | awk '{print $2}' | grep -v ':')
NET_DNS_FIRST=$(echo "$NET_DNS_ALL" | head -1)
echo "Network config: IP=$NET_IP, Gateway=$NET_GW, Prefix=$NET_PREFIX, Device=$NETDEV"
echo "DNS servers: $(echo $NET_DNS_ALL | tr '\n' ' ')"

#############################################################################
# Prepare disks (wipe all to ensure clean slate)
#############################################################################
printf "\n##### Step 2.2: Preparing disks...\n"
# Unmount any existing partitions from ALL disks
for disk in $ALL_DISKS; do
  echo "Checking $disk..."
  for part in $(lsblk -ln -o NAME "$disk" 2>/dev/null | tail -n +2); do
    if mountpoint -q /dev/$part 2>/dev/null || mount | grep -q "/dev/$part"; then
      echo "Unmounting /dev/$part..."
      umount -f /dev/$part 2>/dev/null || true
    fi
  done
done

# Deactivate any LVM/RAID on all disks
vgchange -an 2>/dev/null || true
mdadm --stop --scan 2>/dev/null || true

# Wipe ALL disks to ensure clean slate
echo "Wiping all disks..."
for disk in $ALL_DISKS; do
  echo "Wiping $disk..."
  wipefs -af "$disk" 2>/dev/null || true
  dd if=/dev/zero of="$disk" bs=1M count=1 status=none 2>/dev/null || true
  dd if=/dev/zero of="$disk" bs=1M seek=$(($(blockdev --getsz "$disk") / 2048 - 1)) count=1 status=none 2>/dev/null || true
  blockdev --rereadpt "$disk" 2>/dev/null || true
  partprobe "$disk" 2>/dev/null || true
done

udevadm settle
sleep 2

#############################################################################
# Download Tumbleweed installer kernel and initrd
#############################################################################
printf "\n##### Step 2.3: Downloading installer...\n"
INSTALLER_BASE="https://download.opensuse.org/tumbleweed/repo/oss/boot/x86_64/loader"
wget --progress=bar:force:noscroll "$INSTALLER_BASE/linux" -O /tmp/linux 2>&1
wget --progress=bar:force:noscroll "$INSTALLER_BASE/initrd" -O /tmp/initrd 2>&1

#############################################################################
# Generate AutoYaST profile from template
#############################################################################
printf "\n##### Step 2.4: Generating AutoYaST profile...\n"

# Get the AutoYaST template (passed from Terraform as base64 to avoid quoting issues)
AUTOYAST_TEMPLATE=$(echo '${autoyast_template_base64}' | base64 -d)

# Generate disk configuration XML
# First disk: EFI + RAID member, Additional disks: RAID member only
DISK_CONFIG=""
DISK_INDEX=0
FIRST_DISK_BY_ID=""

for disk_by_id in $DISK_BY_ID_LIST; do
  if [ $DISK_INDEX -eq 0 ]; then
    FIRST_DISK_BY_ID="$disk_by_id"
    # First disk: EFI partition + RAID member
    DISK_CONFIG="$DISK_CONFIG
    <!-- First disk: EFI + RAID member -->
    <drive>
      <device>$disk_by_id</device>
      <disklabel>gpt</disklabel>
      <use>all</use>
      <partitions config:type=\"list\">
        <partition>
          <create config:type=\"boolean\">true</create>
          <size>512M</size>
          <filesystem config:type=\"symbol\">vfat</filesystem>
          <mount>/boot/efi</mount>
          <partition_id config:type=\"integer\">259</partition_id>
        </partition>
        <partition>
          <create config:type=\"boolean\">true</create>
          <size>max</size>
          <raid_name>/dev/md/root</raid_name>
        </partition>
      </partitions>
    </drive>"
  else
    # Additional disks: full disk as RAID member
    DISK_CONFIG="$DISK_CONFIG
    <!-- Additional disk: RAID member -->
    <drive>
      <device>$disk_by_id</device>
      <disklabel>gpt</disklabel>
      <use>all</use>
      <partitions config:type=\"list\">
        <partition>
          <create config:type=\"boolean\">true</create>
          <size>max</size>
          <raid_name>/dev/md/root</raid_name>
        </partition>
      </partitions>
    </drive>"
  fi
  DISK_INDEX=$((DISK_INDEX + 1))
done

# Add RAID array definition
DISK_CONFIG="$DISK_CONFIG
    <!-- mdadm RAID-0 array -->
    <drive>
      <device>/dev/md/root</device>
      <raid_options>
        <raid_type>raid0</raid_type>
        <chunk_size>512K</chunk_size>
      </raid_options>
      <partitions config:type=\"list\">
        <partition>
          <filesystem config:type=\"symbol\">btrfs</filesystem>
          <mount>/</mount>
          <size>max</size>
        </partition>
      </partitions>
      <use>all</use>
    </drive>"

# Generate nameservers XML (one entry per DNS server)
NAMESERVERS_XML=""
for dns in $NET_DNS_ALL; do
  [ -n "$NAMESERVERS_XML" ] && NAMESERVERS_XML="$NAMESERVERS_XML
"
  NAMESERVERS_XML="$NAMESERVERS_XML        <nameserver>$dns</nameserver>"
done

# Substitute placeholders in the AutoYaST template
# Note: Network IP/mask/gateway are NOT substituted here - they come from linuxrc ifcfg=*
# which is preserved via keep_install_network=true in the AutoYaST profile
# Use perl for multi-line substitution (sed can't handle newlines in replacement)
export DISK_CONFIG NAMESERVERS_XML
echo "$AUTOYAST_TEMPLATE" | perl -pe '
  BEGIN {
    $disk = $ENV{"DISK_CONFIG"};
    $ns = $ENV{"NAMESERVERS_XML"};
  }
  s/DISK_CONFIG_PLACEHOLDER/$disk/g;
  s/NAMESERVERS_PLACEHOLDER/$ns/g;
' > /tmp/autoinst.xml

echo "Generated AutoYaST profile:"
echo "============================="
cat /tmp/autoinst.xml
echo "============================="

#############################################################################
# Embed AutoYaST profile in initrd
#############################################################################
printf "\n##### Step 2.5: Embedding AutoYaST profile in initrd...\n"

mkdir -p /tmp/initrd-work
cd /tmp/initrd-work

# Detect initrd compression format and extract
echo "Detecting initrd compression format..."
INITRD_TYPE=$(file /tmp/initrd)
echo "Initrd type: $INITRD_TYPE"

if echo "$INITRD_TYPE" | grep -q "XZ compressed"; then
  echo "Extracting XZ compressed initrd..."
  xz -d < /tmp/initrd | cpio -idm 2>/dev/null
elif echo "$INITRD_TYPE" | grep -q "gzip compressed"; then
  echo "Extracting gzip compressed initrd..."
  gzip -d < /tmp/initrd | cpio -idm 2>/dev/null
elif echo "$INITRD_TYPE" | grep -q "Zstandard compressed"; then
  echo "Extracting zstd compressed initrd..."
  apt-get install -y zstd
  zstd -d < /tmp/initrd | cpio -idm 2>/dev/null
else
  echo "ERROR: Unknown initrd compression format: $INITRD_TYPE"
  exit 1
fi

# Copy AutoYaST profile to initrd root
cp /tmp/autoinst.xml ./autoinst.xml
echo "AutoYaST profile embedded in initrd root"

# Repack initrd with the same compression
echo "Repacking initrd..."
if echo "$INITRD_TYPE" | grep -q "XZ compressed"; then
  find . | cpio -o -H newc 2>/dev/null | xz --check=crc32 > /tmp/initrd-custom
elif echo "$INITRD_TYPE" | grep -q "gzip compressed"; then
  find . | cpio -o -H newc 2>/dev/null | gzip > /tmp/initrd-custom
elif echo "$INITRD_TYPE" | grep -q "Zstandard compressed"; then
  find . | cpio -o -H newc 2>/dev/null | zstd > /tmp/initrd-custom
fi

cd /
rm -rf /tmp/initrd-work

echo "Custom initrd created: $(ls -lh /tmp/initrd-custom)"

#############################################################################
# Execute kexec into MicroOS installer
#############################################################################
printf "\n##### Step 2.6: Booting into MicroOS installer via kexec...\n"

# Build kernel command line
# AutoYaST profile is auto-detected from /autoinst.xml in the initrd (no autoyast= needed)
# install= - Installation source URL
# ifcfg= - Network configuration for installer
# self_update=0 - Disable installer self-update (faster)
# textmode=1 - No graphical installer
CMDLINE="install=https://download.opensuse.org/tumbleweed/repo/oss/"
CMDLINE="$CMDLINE ifcfg=*=$NET_IP/$NET_PREFIX,$NET_GW,$NET_DNS_FIRST"
CMDLINE="$CMDLINE self_update=0"
CMDLINE="$CMDLINE textmode=1"

echo "Kernel command line:"
echo "$CMDLINE"

# Load the kernel and initrd
echo "Loading kernel and initrd..."
kexec --load /tmp/linux --initrd=/tmp/initrd-custom --command-line="$CMDLINE"

# Execute kexec - this will not return!
echo ""
echo "=============================================="
echo "Executing kexec into MicroOS installer..."
echo "The installation will proceed automatically."
echo "This SSH session will now disconnect."
echo "=============================================="
echo ""

# Give time for the message to be sent
sleep 2

kexec -e
