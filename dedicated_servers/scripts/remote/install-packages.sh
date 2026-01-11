#!/bin/bash
# Install packages on MicroOS via transactional-update
# This script runs on the installed MicroOS via SSH
# Variables substituted by terraform templatefile():
#   - needed_packages
set -e

printf "\n##### Step 2.1: Installing base packages...\n"
transactional-update --continue pkg install -y ${needed_packages}

printf "\n##### Step 2.2: Configuring snapper limits...\n"
transactional-update --continue shell << 'EOF'
# Reduce snapshot limits (from kube-hetzner)
if [ -f /etc/snapper/configs/root ]; then
  sed -i 's/NUMBER_LIMIT="2-10"/NUMBER_LIMIT="4"/g' /etc/snapper/configs/root
  sed -i 's/NUMBER_LIMIT_IMPORTANT="4-10"/NUMBER_LIMIT_IMPORTANT="3"/g' /etc/snapper/configs/root
  echo "Snapper limits configured"
else
  echo "Snapper config not found (will be configured later)"
fi
EOF

printf "\n##### Step 2.3: Installing k3s-selinux and custom policy...\n"
# Note: SELinux may be disabled on first boot (MicroOS ContainerHost default).
# We install k3s-selinux and create custom policy - they'll be effective after reboot.
transactional-update --continue shell << 'EOF'
# Set permissive mode if SELinux is enabled (ignore failure if disabled)
setenforce 0 2>/dev/null || echo "SELinux not yet enabled (expected on first boot)"

rpm --import https://rpm.rancher.io/public.key
zypper install -y https://github.com/k3s-io/k3s-selinux/releases/download/v1.6.stable.1/k3s-selinux-1.6-1.sle.noarch.rpm
zypper addlock k3s-selinux

# Create SELinux policy module for k3s/containers (from kube-hetzner)
cat > /root/kube_hetzner_selinux.te << 'SELINUXEOF'
module kube_hetzner_selinux 1.0;

require {
    type kernel_t, bin_t, kernel_generic_helper_t, iscsid_t, iscsid_exec_t, var_run_t, var_lib_t,
        init_t, unlabeled_t, systemd_logind_t, systemd_hostnamed_t, container_t,
        cert_t, container_var_lib_t, etc_t, usr_t, container_file_t, container_log_t,
        container_share_t, container_runtime_exec_t, container_runtime_t, var_log_t, proc_t, io_uring_t, fuse_device_t, http_port_t,
        container_var_run_t;
    class key { read view };
    class file { open read execute execute_no_trans create link lock rename write append setattr unlink getattr watch };
    class sock_file { watch write create unlink };
    class unix_dgram_socket create;
    class unix_stream_socket { connectto read write };
    class dir { add_name create getattr link lock read rename remove_name reparent rmdir setattr unlink search write watch };
    class lnk_file { read create };
    class system module_request;
    class filesystem associate;
    class bpf map_create;
    class io_uring sqpoll;
    class anon_inode { create map read write };
    class tcp_socket name_connect;
    class chr_file { open read write };
}

#============= kernel_generic_helper_t ==============
allow kernel_generic_helper_t bin_t:file execute_no_trans;
allow kernel_generic_helper_t kernel_t:key { read view };
allow kernel_generic_helper_t self:unix_dgram_socket create;

#============= iscsid_t ==============
allow iscsid_t iscsid_exec_t:file execute;
allow iscsid_t var_run_t:sock_file write;
allow iscsid_t var_run_t:unix_stream_socket connectto;

#============= init_t ==============
allow init_t unlabeled_t:dir { add_name remove_name rmdir search };
allow init_t unlabeled_t:lnk_file create;
allow init_t container_t:file { open read };
allow init_t container_file_t:file { execute execute_no_trans };
allow init_t fuse_device_t:chr_file { open read write };
allow init_t http_port_t:tcp_socket name_connect;

#============= systemd_logind_t ==============
allow systemd_logind_t unlabeled_t:dir search;

#============= systemd_hostnamed_t ==============
allow systemd_hostnamed_t unlabeled_t:dir search;

#============= container_t ==============
allow container_t { cert_t container_log_t }:dir read;
allow container_t { cert_t container_log_t }:lnk_file read;
allow container_t cert_t:file { read open };
allow container_t container_var_lib_t:dir { add_name remove_name write read create };
allow container_t container_var_lib_t:file { append create open read write rename lock setattr getattr unlink };
allow container_t etc_t:dir { add_name remove_name write create setattr watch };
allow container_t etc_t:file { create setattr unlink write };
allow container_t etc_t:sock_file { create unlink };
allow container_t usr_t:dir { add_name create getattr link lock read rename remove_name reparent rmdir setattr unlink search write };
allow container_t usr_t:file { append create execute getattr link lock read rename setattr unlink write };
allow container_t container_file_t:file { open read write append getattr setattr lock };
allow container_t container_file_t:sock_file watch;
allow container_t container_log_t:file { open read write append getattr setattr watch };
allow container_t container_share_t:dir { read write add_name remove_name };
allow container_t container_share_t:file { read write create unlink };
allow container_t container_runtime_exec_t:file { read execute execute_no_trans open };
allow container_t container_runtime_t:unix_stream_socket { connectto read write };
allow container_t kernel_t:system module_request;
allow container_t var_log_t:dir { add_name write remove_name watch read };
allow container_t var_log_t:file { create lock open read setattr write unlink getattr };
allow container_t var_lib_t:dir { add_name remove_name write read create };
allow container_t var_lib_t:file { append create open read write rename lock setattr getattr unlink };
allow container_t proc_t:filesystem associate;
allow container_t self:bpf map_create;
allow container_t self:io_uring sqpoll;
allow container_t io_uring_t:anon_inode { create map read write };
allow container_t container_var_run_t:dir { add_name remove_name write };
allow container_t container_var_run_t:file { create open read rename unlink write };
SELINUXEOF

# Compile and install SELinux module
if command -v checkmodule &>/dev/null; then
  echo "Compiling SELinux policy module..."
  checkmodule -M -m -o /root/kube_hetzner_selinux.mod /root/kube_hetzner_selinux.te
  semodule_package -o /root/kube_hetzner_selinux.pp -m /root/kube_hetzner_selinux.mod
  semodule -i /root/kube_hetzner_selinux.pp
  setsebool -P virt_use_samba 1
  setsebool -P domain_kernel_load_modules 1
  rm -f /root/kube_hetzner_selinux.pp /root/kube_hetzner_selinux.mod /root/kube_hetzner_selinux.te
  echo "SELinux policy module installed"
else
  echo "WARNING: checkmodule not available, skipping SELinux policy"
fi

# Restore SELinux contexts (effective after SELinux is enabled on reboot)
restorecon -Rv /etc/selinux/targeted/policy 2>/dev/null || true
restorecon -Rv /var/lib 2>/dev/null || true

# Re-enable enforcing mode if SELinux is enabled (ignore failure if disabled)
setenforce 1 2>/dev/null || echo "SELinux will be enabled after reboot"
EOF

printf "\n##### Step 2.4: Rebooting to apply changes (SELinux will be enforcing)...\n"
sleep 1 && udevadm settle && reboot
