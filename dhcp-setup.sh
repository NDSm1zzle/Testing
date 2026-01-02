#!/bin/bash


# Install dhcp-server package for IPv4

yum install -y dhcp-server


cp /usr/lib/systemd/system/dhcpd.service /etc/systemd/system/


# Source the shared configuration to get the interface name
CONF_DIR="/etc/pxe-server"
CONF_FILE="${CONF_DIR}/pxe.conf"

if [ ! -f "$CONF_FILE" ]; then
    echo "Error: Configuration file $CONF_FILE not found."
    echo "Please run nic-setup.sh first to generate it."
    exit 1
fi
source "$CONF_FILE"

echo "DEBUG: INTERFACE from $CONF_FILE is: $INTERFACE"
echo "DEBUG: PXE_SERVER_IP from $CONF_FILE is: $PXE_SERVER_IP"

if [ -z "$INTERFACE" ]; then
    echo "Error: INTERFACE variable not set in $CONF_FILE."
    exit 1
fi

echo "Configuring DHCP server to run on interface: $INTERFACE"
sed -i "/^ExecStart=/ s/$/ $INTERFACE/" /etc/systemd/system/dhcpd.service


cat <<EOF > /etc/dhcp/dhcpd.conf
# DHCP Server Configuration file.
#   see /usr/share/doc/dhcp-server/dhcpd.conf.example
#   see dhcpd.conf(5) man page

# This is a very basic subnet declaration.

option domain-name "example.com";
default-lease-time 600;
max-lease-time 7200;

authoritative;

# No service will be given on this subnet, but declaring it helps the 
# DHCP server to understand the network topology.

subnet 192.168.12.0 netmask 255.255.255.0 {
}

option architecture-type code 93 = unsigned integer 16;

subnet 10.0.0.0 netmask 255.255.255.0 {
  option routers 10.0.0.1;
  option domain-name-servers 10.0.0.1;
  range 10.0.0.100 10.0.0.200;
  next-server 10.0.0.253;

  # Differentiate between BIOS and UEFI clients
  if option architecture-type = 00:00 {
    # BIOS client
    filename "pxelinux/pxelinux.0";
  } elsif option architecture-type = 00:07 OR option architecture-type = 00:09 {
    # UEFI client
    if substring (option vendor-class-identifier, 0, 10) = "HTTPClient" {
      # ESXi UEFI HTTP CLient
      filename "http://10.0.0.253/esxi/mboot.efi";
    } else {
      # RHEL UEFI PXE Client
      filename "redhat/EFI/BOOT/BOOTX64.EFI";
    }
  }
}
EOF

# Test configuration before restarting service
dhcpd -t -cf /etc/dhcp/dhcpd.conf

systemctl --system daemon-reload
systemctl enable --now dhcpd
# Ensure restart happens if already running to pick up config changes
systemctl restart dhcpd

firewall-cmd --add-service=dhcp --permanent
firewall-cmd --reload

# Verify DHCP service is active
if systemctl is-active --quiet dhcpd; then
    echo "DHCP Service is running successfully."
else
    echo "DHCP Service FAILED to start."
    exit 1
fi
