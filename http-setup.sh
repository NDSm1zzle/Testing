#!/bin/bash

# This script installs and configures the Apache HTTP server (httpd)
# to serve the local repository files for PXE booting.
# It links the web directory to the repository created by setup-local-repo.sh.

set -e

echo "--- Setting up HTTP Server ---"

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo."
  exit 1
fi

echo "Installing httpd and SELinux utilities..."
yum install -y httpd policycoreutils-python-utils

echo "Configuring firewall to allow HTTP traffic..."
firewall-cmd --add-service=http --permanent
firewall-cmd --reload

echo "Enabling and starting httpd service..."
systemctl enable --now httpd

# The repo files are located in /var/repo/rhel9/ by setup-local-repo.sh.
REPO_PATH="/var/repo/rhel9"
# The GRUB config points clients to this web path.
WEB_REPO_LINK="/var/www/html/RHEL-9"

if [ ! -d "$REPO_PATH" ]; then
    echo "Error: Repository path $REPO_PATH not found."
    echo "Please run setup-local-repo.sh first."
    exit 1
fi

echo "Linking web directory $WEB_REPO_LINK to $REPO_PATH..."
# Remove existing dir/link to prevent errors and ensure parent exists
mkdir -p /var/www/html/
if [ -L "$WEB_REPO_LINK" ] || [ -d "$WEB_REPO_LINK" ]; then
    rm -rf "$WEB_REPO_LINK"
fi

# We link /var/www/html/RHEL-9 to /var/repo/rhel9.
# The grub.cfg must then use inst.repo=http://<server>/RHEL-9
# Note: The original grub.cfg used /RHEL-9/x86_64, so we will adjust it in the tftp-setup script.
ln -s "$REPO_PATH" "$WEB_REPO_LINK"

# Set SELinux context to allow httpd to read the repository files.
echo "Setting persistent SELinux context for $REPO_PATH..."
semanage fcontext -a -t httpd_sys_content_t "${REPO_PATH}(/.*)?"
restorecon -R -v "$REPO_PATH"

# Set SELinux context for web content
restorecon -r /var/www/html/

echo "Restarting httpd to apply changes..."
systemctl restart httpd

echo "HTTP server setup complete."
