<?xml version="1.0"?>
<!DOCTYPE profile>
<profile xmlns="http://www.suse.com/1.0/yast2ns"
         xmlns:config="http://www.suse.com/1.0/configns">

  <!-- General Settings -->
  <general>
    <mode>
      <confirm config:type="boolean">false</confirm>
      <final_reboot config:type="boolean">true</final_reboot>
    </mode>
    <signature-handling>
      <accept_unsigned_file config:type="boolean">true</accept_unsigned_file>
      <accept_non_trusted_gpg_key config:type="boolean">true</accept_non_trusted_gpg_key>
    </signature-handling>
  </general>

  <!-- Product Selection: MicroOS -->
  <software>
    <products config:type="list">
      <product>MicroOS</product>
    </products>
    <patterns config:type="list">
      <pattern>microos_base</pattern>
      <pattern>microos_base_zypper</pattern>
      <pattern>microos_defaults</pattern>
      <pattern>microos_hardware</pattern>
      <pattern>microos_selinux</pattern>
      <pattern>container_runtime</pattern>
    </patterns>
  </software>

  <!-- Partitioning: mdadm RAID-0 + btrfs (dynamically generated at runtime) -->
  <partitioning config:type="list">
DISK_CONFIG_PLACEHOLDER
  </partitioning>

  <!-- Bootloader: systemd-boot for MicroOS -->
  <bootloader>
    <loader_type>systemd-boot</loader_type>
    <global>
      <append>security=selinux selinux=1</append>
      <timeout config:type="integer">3</timeout>
    </global>
  </bootloader>

  <!-- Networking: Preserve installer network config (set via linuxrc ifcfg=*) -->
  <!-- The kexec script passes ifcfg=*=$IP/$PREFIX,$GW,$DNS which configures any available interface -->
  <networking>
    <keep_install_network config:type="boolean">true</keep_install_network>
    <dns>
      <hostname>${hostname}</hostname>
      <nameservers config:type="list">
NAMESERVERS_PLACEHOLDER
      </nameservers>
    </dns>
  </networking>

  <!-- Users: root with SSH key authentication only -->
  <!-- Note: authorized_keys in users section doesn't work for root (known AutoYaST bug) -->
  <!-- SSH key is added via chroot-script; SELinux context fixed by selinux-ssh-setup.service on boot -->
  <users config:type="list">
    <user>
      <username>root</username>
      <user_password>!</user_password>
      <encrypted config:type="boolean">false</encrypted>
    </user>
  </users>

  <!-- Security: SELinux -->
  <security>
    <selinux_mode>enforcing</selinux_mode>
  </security>

  <!-- Firewall: Open SSH port -->
  <firewall>
    <enable_firewall config:type="boolean">true</enable_firewall>
    <default_zone>public</default_zone>
    <zones config:type="list">
      <zone>
        <name>public</name>
        <ports config:type="list">
          <port>${ssh_port}/tcp</port>
        </ports>
      </zone>
    </zones>
  </firewall>

  <!-- Systemd Services Configuration -->
  <services-manager>
    <default_target>multi-user</default_target>
    <services>
      <disable config:type="list">
        <!-- Disable rebootmgr (use kured instead for coordinated reboots) -->
        <service>rebootmgr</service>
      </disable>
      <enable config:type="list">
        <!-- Enable SSH -->
        <service>sshd</service>
        <!-- Enable SELinux SSH setup (restorecon + custom port, must run before sshd) -->
        <service>selinux-ssh-setup</service>
      </enable>
    </services>
  </services-manager>

  <!-- Configuration Files (created natively by AutoYaST) -->
  <!-- Note: files section works on MicroOS because it writes before read-only snapshot -->
  <!-- SSH authorized_keys is created via chroot-script (not here) due to AutoYaST root user bug -->
  <files config:type="list">
    <!-- SSH hardening (from kube-hetzner) -->
    <file>
      <file_path>/etc/ssh/sshd_config.d/hardening.conf</file_path>
      <file_contents><![CDATA[Port ${ssh_port}
PasswordAuthentication no
X11Forwarding no
MaxAuthTries 3
AllowTcpForwarding no
AllowAgentForwarding no
AuthorizedKeysFile .ssh/authorized_keys
]]></file_contents>
      <file_owner>root:root</file_owner>
      <file_permissions>644</file_permissions>
    </file>

    <!-- Transactional update config: use kured for reboots -->
    <file>
      <file_path>/etc/transactional-update.conf</file_path>
      <file_contents><![CDATA[REBOOT_METHOD=kured
]]></file_contents>
      <file_owner>root:root</file_owner>
      <file_permissions>644</file_permissions>
    </file>

    <!-- Journal size limits (from kube-hetzner) -->
    <file>
      <file_path>/etc/systemd/journald.conf.d/size.conf</file_path>
      <file_contents><![CDATA[[Journal]
SystemMaxUse=3G
MaxRetentionSec=1week
]]></file_contents>
      <file_owner>root:root</file_owner>
      <file_permissions>644</file_permissions>
    </file>

    <!-- SELinux SSH configuration (runs before sshd on every boot) -->
    <!-- Must run restorecon because SELinux is not active during installation -->
    <!-- Files created during installation get wrong context (unlabeled/admin_home_t) -->
    <file>
      <file_path>/etc/systemd/system/selinux-ssh-setup.service</file_path>
      <file_contents><![CDATA[[Unit]
Description=Configure SELinux for SSH (custom port + fix contexts)
DefaultDependencies=no
Before=sshd.service
After=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
# Fix SELinux context on SSH authorized_keys (required - created during installation without SELinux)
ExecStart=/usr/sbin/restorecon -R /root/.ssh
# Add custom SSH port to SELinux policy (ignore error if already exists)
ExecStart=-/usr/sbin/semanage port -a -t ssh_port_t -p tcp ${ssh_port}

[Install]
WantedBy=multi-user.target
]]></file_contents>
      <file_owner>root:root</file_owner>
      <file_permissions>644</file_permissions>
    </file>
  </files>

  <!-- Custom scripts section -->
  <!-- chroot-scripts run before first reboot, while filesystem is still writable -->
  <scripts>
    <chroot-scripts config:type="list">
      <script>
        <chrooted config:type="boolean">true</chrooted>
        <filename>setup-ssh-authorized-keys.sh</filename>
        <interpreter>shell</interpreter>
        <source><![CDATA[#!/bin/bash
# Set up SSH authorized_keys for root
# Note: SELinux is NOT active during installation, so files get wrong context.
# The selinux-ssh-setup.service runs restorecon on first boot to fix this.

mkdir -p /root/.ssh
chmod 700 /root/.ssh
cat > /root/.ssh/authorized_keys << 'SSHKEY'
${ssh_public_key}
SSHKEY
chmod 600 /root/.ssh/authorized_keys
chown -R root:root /root/.ssh

echo "SSH authorized_keys configured for root"
ls -la /root/.ssh/
]]></source>
      </script>
    </chroot-scripts>
  </scripts>

</profile>
