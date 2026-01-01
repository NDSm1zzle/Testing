#!/bin/bash

# This script installs and configures the TFTP server for PXE booting.
# It copies boot files from the local repository created by setup-local-repo.sh.

set -e

echo "--- Setting up TFTP Server ---"

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo."
  exit 1
fi

echo "Installing tftp-server..."
# Install tftp-server package for IPv4
yum install -y tftp-server tftp

# Set up tftp service (the default socket can cause conflicts)
echo "Configuring tftp service..."
systemctl disable --now tftp.socket
cp /usr/lib/systemd/system/tftp.service /etc/systemd/system/tftp-server.service
cp /usr/lib/systemd/system/tftp.socket /etc/systemd/system/tftp-server.socket
sed -i -e '/^ExecStart=/ s/-s/-p -s/' -e 's/tftp.socket/tftp-server.socket/' /etc/systemd/system/tftp-server.service

echo "Configuring firewall to allow TFTP traffic..."
firewall-cmd --add-service=tftp --permanent
firewall-cmd --reload

REPO_PATH="/var/repo/rhel9"
if [ ! -d "$REPO_PATH" ]; then
    echo "Error: Repository path $REPO_PATH not found."
    echo "Please run setup-local-repo.sh first."
    exit 1
fi

# Copy boot files from the local repository
echo "Copying boot files from $REPO_PATH..."
mkdir -p /var/lib/tftpboot/redhat
cp -r "$REPO_PATH"/EFI /var/lib/tftpboot/redhat/

mkdir -p /var/lib/tftpboot/images/RHEL-9/
cp "$REPO_PATH"/images/pxeboot/{vmlinuz,initrd.img} /var/lib/tftpboot/images/RHEL-9/

# Set permissions for TFTP root
chmod -R 755 /var/lib/tftpboot/
restorecon -R /var/lib/tftpboot/

# Create the GRUB configuration for the PXE client
echo "Creating GRUB boot configuration..."
cat <<EOF > /var/lib/tftpboot/redhat/EFI/BOOT/grub.cfg
set timeout=60
menuentry 'Install RHEL 9' {
  linuxefi images/RHEL-9/vmlinuz ip=dhcp inst.repo=http://10.0.0.253/RHEL-9/
  initrdefi images/RHEL-9/initrd.img
}
EOF

echo "Starting TFTP service..."
systemctl daemon-reload
systemctl enable --now tftp-server.socket

# Functional test for TFTP server
echo "Performing local TFTP test..."
echo "TFTP test successful" > /var/lib/tftpboot/tftp_test.txt
rm -f ./tftp_test.txt
tftp 127.0.0.1 -c get tftp_test.txt

if [ -f ./tftp_test.txt ] && grep -q "TFTP test successful" ./tftp_test.txt; then
    echo "TFTP Service is working correctly."
    rm -f ./tftp_test.txt /var/lib/tftpboot/tftp_test.txt
else
    echo "TFTP Service test FAILED."
    exit 1
fi