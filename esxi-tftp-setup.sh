#!/bin/bash

# This script finds an attached ESXi ISO, mounts it, and copies essential EFI
# boot files to the TFTP server's ESXi directory for PXE booting.

set -e

# Source the shared configuration to get the PXE_SERVER_IP
CONF_DIR="/etc/pxe-server"
CONF_FILE="${CONF_DIR}/pxe.conf"

if [ ! -f "$CONF_FILE" ]; then
    echo "Error: Configuration file $CONF_FILE not found."
    echo "Please run nic-setup.sh first to generate it."
    exit 1
fi
source "$CONF_FILE"

echo "--- Setting up ESXi TFTP Boot Files ---"

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo."
  exit 1
fi

ESXI_ISO_MOUNT_POINT="/mnt/esxi_iso"
ESXI_TFTP_DEST="/var/lib/tftpboot/esxi"
ESXI_HTTP_DEST="/var/www/html/esxi"

# 1. Find the ISO device (virtual DVD/CD-ROM)
ISO_DEVICE=$(lsblk -no NAME,TYPE | awk '$2=="rom"{print "/dev/"$1}' | head -n 1)

if [ -z "$ISO_DEVICE" ]; then
    echo "Error: Could not find an attached ISO device (virtual DVD/CD-ROM)."
    echo "Please attach an ESXi installation ISO and run the script again."
    exit 1
fi

echo "Found ESXi ISO device at $ISO_DEVICE."

# 2. Create mount point
echo "Creating ESXi mount point at $ESXI_ISO_MOUNT_POINT..."
mkdir -p "$ESXI_ISO_MOUNT_POINT"

# 3. Mount the ESXi ISO
echo "Mounting $ISO_DEVICE to $ESXI_ISO_MOUNT_POINT..."
# Unmount if it's already mounted to avoid errors
if mount | grep -q " on ${ESXI_ISO_MOUNT_POINT} "; then
    echo "A device is already mounted at ${ESXI_ISO_MOUNT_POINT}. Unmounting first."
    umount "${ESXI_ISO_MOUNT_POINT}"
fi
mount -o ro "$ISO_DEVICE" "$ESXI_ISO_MOUNT_POINT"
if [ $? -ne 0 ]; then
    echo "Error: Failed to mount the ESXi ISO."
    exit 1
fi

echo "Successfully mounted $ISO_DEVICE at $ESXI_ISO_MOUNT_POINT."

# 4. Create destination directory for ESXi boot files
echo "Creating ESXi TFTP destination directory $ESXI_TFTP_DEST..."
mkdir -p "$ESXI_TFTP_DEST"

# Create ESXi HTTP destination directory
echo "Creating ESXi HTTP destination directory $ESXI_HTTP_DEST..."
mkdir -p "$ESXI_HTTP_DEST"

# Copy ESXi EFI bootloader to HTTP destination and rename
echo "Copying ESXi EFI bootloader to $ESXI_HTTP_DEST/mboot.efi..."
cp "$ESXI_ISO_MOUNT_POINT"/efi/boot/bootx64.efi "$ESXI_HTTP_DEST"/mboot.efi

# Copy entire ISO content to HTTP destination
# Dynamically determine ESXi version for HTTP content directory
ESXI_VERSION=""

# 1. Try to extract version from ISO filename
ISO_FILENAME=$(basename "$ISO_DEVICE")
# Example: VMware-VMvisor-Installer-8.0U3-24022510-x86_64.iso
# Regex to match version pattern like 8.0U3-24022510-x86_64
VERSION_FROM_FILENAME=$(echo "$ISO_FILENAME" | grep -oE '[0-9]+\.[0-9]+U?[0-9]*-[0-9]+\-x86_64' || true)

if [ -n "$VERSION_FROM_FILENAME" ]; then
    ESXI_VERSION="$VERSION_FROM_FILENAME"
else
    # 2. Fallback: Try to extract BUILD_NUMBER from esx.version
    ESXI_VERSION=$(grep -E "^BUILD_NUMBER=" "$ESXI_ISO_MOUNT_POINT/esx.version" | cut -d'=' -f2 | tr -d ' ' || true)

    if [ -z "$ESXI_VERSION" ]; then
        # NEW: Try to extract 'build=' format
        ESXI_VERSION=$(grep -E "^build=" "$ESXI_ISO_MOUNT_POINT/esx.version" | cut -d'=' -f2 | tr -d ' ' || true)
    fi

    if [ -z "$ESXI_VERSION" ]; then
        # 3. Fallback: Try to extract 'VERSION =' format if BUILD_NUMBER not found
        ESXI_VERSION=$(grep "VERSION =" "$ESXI_ISO_MOUNT_POINT/esx.version" | awk -F "'" '{print $2}' | tr -d ' ' || true)
    fi
fi

if [ -z "$ESXI_VERSION" ]; then
    echo "Warning: Could not determine ESXi version from any source. Using generic name."
    ESXI_VERSION="ESXi-ISO-Content"
fi

ESXI_HTTP_ISO_CONTENT_DEST="${ESXI_HTTP_DEST}/${ESXI_VERSION}"
echo "Determined ESXi version: $ESXI_VERSION"
echo "Creating ESXi HTTP ISO content directory $ESXI_HTTP_ISO_CONTENT_DEST..."
mkdir -p "$ESXI_HTTP_ISO_CONTENT_DEST"

echo "Copying entire ESXi ISO content from $ESXI_ISO_MOUNT_POINT to $ESXI_HTTP_ISO_CONTENT_DEST..."
# Ensure rsync is installed for efficient copying, or fall back to cp -a
if command -v rsync &> /dev/null; then
    rsync -av --progress "$ESXI_ISO_MOUNT_POINT"/* "$ESXI_HTTP_ISO_CONTENT_DEST"/
else
    cp -a "$ESXI_ISO_MOUNT_POINT"/* "$ESXI_HTTP_ISO_CONTENT_DEST"/
fi

if [ $? -ne 0 ]; then
    echo "Error: Failed to copy ESXi ISO content to HTTP destination."
    # Attempt to unmount before exiting
    umount "$ESXI_ISO_MOUNT_POINT" || true
    exit 1
fi
echo "ESXi ISO content copied successfully to $ESXI_HTTP_ISO_CONTENT_DEST."

# Modify boot.cfg for HTTP boot
BOOT_CFG_FILE="${ESXI_HTTP_ISO_CONTENT_DEST}/boot.cfg"
if [ -f "$BOOT_CFG_FILE" ]; then
    echo "Modifying $BOOT_CFG_FILE to add HTTP boot prefix..."
    # Remove leading slash from kernel= line
    sed -i 's|^kernel=/|kernel=|g' "$BOOT_CFG_FILE"
    # Remove leading slash from modules= line
    sed -i '/^modules=/ s| /| |g; s|^modules=/|modules=|g' "$BOOT_CFG_FILE"
    # Remove 'cdromBoot' from kernelopt= line
    sed -i 's|cdromBoot||g' "$BOOT_CFG_FILE"
    SERVER_IP="$PXE_SERVER_IP"
    echo "prefix=http://${SERVER_IP}/esxi/${ESXI_VERSION}/" >> "$BOOT_CFG_FILE"
    echo "Added 'prefix=http://${SERVER_IP}/esxi/${ESXI_VERSION}/' to $BOOT_CFG_FILE."
else
    echo "Warning: boot.cfg not found at $BOOT_CFG_FILE. Skipping prefix modification."
fi

# Copy the boot.cfg to same directory as mboot.efi for UEFI HTTP boot
echo "Copying modified boot.cfg to $ESXI_HTTP_DEST for UEFI HTTP boot..."
cp "$BOOT_CFG_FILE" "$ESXI_HTTP_DEST"/boot.cfg

# 6. Unmount the ESXi ISO
echo "Unmounting $ESXI_ISO_MOUNT_POINT..."
umount "$ESXI_ISO_MOUNT_POINT"
if [ $? -ne 0 ]; then
    echo "Warning: Failed to unmount ESXi ISO from $ESXI_ISO_MOUNT_POINT."
else
    echo "ESXi ISO unmounted successfully."
fi

# Set permissions for boot directories
echo "Setting permissions for boot directories..."
chmod -R 755 "$ESXI_TFTP_DEST" "$ESXI_HTTP_DEST" "$ESXI_HTTP_ISO_CONTENT_DEST"
# Set SELinux context for HTTP directories
echo "Setting SELinux context for ESXi HTTP directories..."
semanage fcontext -a -t httpd_sys_content_t "${ESXI_HTTP_DEST}(/.*)?" || true
semanage fcontext -a -t httpd_sys_content_t "${ESXI_HTTP_ISO_CONTENT_DEST}(/.*)?" || true
restorecon -R "$ESXI_TFTP_DEST" "$ESXI_HTTP_DEST" "$ESXI_HTTP_ISO_CONTENT_DEST" || true # restorecon might not be available everywhere, so make it non-critical

echo "ESXi TFTP and HTTP boot files setup complete."

exit 0