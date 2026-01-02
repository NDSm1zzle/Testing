#!/bin/bash

# This script finds an attached ESXi ISO, mounts it, and copies essential EFI
# boot files to the HTTP server's ESXi directory for network booting.

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

echo "--- Setting up ESXi HTTP Boot Files ---"

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo."
  exit 1
fi

ESXI_ISO_MOUNT_POINT="/mnt/esxi_iso"
ESXI_HTTP_DEST="/var/www/html/esxi"
KS_DEST_DIR="/var/www/html/esxi_ksFiles"

# 1. Find the ESXi installation media (CD-ROM or USB)
ISO_DEVICE=""

# First, look for a virtual CD-ROM (ISO)
echo "Searching for ESXi installation media..."
CD_DEVICE_CANDIDATE=$(lsblk -no NAME,TYPE | awk '$2=="rom"{print "/dev/"$1}' | head -n 1)

if [ -n "$CD_DEVICE_CANDIDATE" ]; then
    echo "Found CD-ROM device at $CD_DEVICE_CANDIDATE. Checking for media..."
    if dd if="$CD_DEVICE_CANDIDATE" of=/dev/null count=1 >/dev/null 2>&1; then
        ISO_DEVICE="$CD_DEVICE_CANDIDATE"
        echo "Found usable ESXi ISO media in $ISO_DEVICE."
    else
        echo "No media found in $CD_DEVICE_CANDIDATE."
    fi
fi

# If no usable CD-ROM was found, look for a USB device.
if [ -z "$ISO_DEVICE" ]; then
    echo "No usable CD-ROM found. Looking for a bootable USB installation media..."
    USB_DISK_NAME=$(lsblk -no NAME,TRAN | awk '$2=="usb"{print $1}' | head -n 1)

    if [ -n "$USB_DISK_NAME" ]; then
        echo "Found USB disk: ${USB_DISK_NAME}"
        mapfile -t USB_PARTITIONS < <(lsblk -lno NAME,TYPE "/dev/${USB_DISK_NAME}" | awk '$2=="part"{print "/dev/"$1}')

        if [ ${#USB_PARTITIONS[@]} -gt 0 ]; then
            ISO_DEVICE="${USB_PARTITIONS[0]}"
            echo "Using first partition for ESXi installation media: $ISO_DEVICE."

            if [ ${#USB_PARTITIONS[@]} -gt 1 ]; then
                KICKSTART_PARTITION="${USB_PARTITIONS[1]}"
                echo "Found second partition to check for kickstart file: $KICKSTART_PARTITION."
                
                KS_DEST_FILE="${KS_DEST_DIR}/ks.cfg"
                KS_MOUNT_POINT=""
                MOUNT_INFO=$(mount | grep "^$KICKSTART_PARTITION ")

                if [ -n "$MOUNT_INFO" ]; then
                    KS_MOUNT_POINT=$(echo "$MOUNT_INFO" | awk '{print $3}')
                    echo "Kickstart partition $KICKSTART_PARTITION is already mounted at $KS_MOUNT_POINT."
                else
                    KS_MOUNT_POINT="/mnt/ks_partition"
                    mkdir -p "$KS_MOUNT_POINT"
                    echo "Mounting $KICKSTART_PARTITION to check for ks.cfg..."
                    mount -o ro "$KICKSTART_PARTITION" "$KS_MOUNT_POINT"
                fi
                
                KS_SRC_FILE="${KS_MOUNT_POINT}/ks.cfg"

                if [ -f "$KS_SRC_FILE" ]; then
                    echo "Found kickstart file at $KS_SRC_FILE."
                    mkdir -p "$KS_DEST_DIR"
                    cp "$KS_SRC_FILE" "$KS_DEST_FILE"
                    echo "Successfully copied ks.cfg to $KS_DEST_FILE."
                    chmod 644 "$KS_DEST_FILE"
                    chown apache:apache "$KS_DEST_FILE" || true
                else
                    echo "Warning: ks.cfg was not found at $KS_SRC_FILE."
                fi
                
                # Unmount only if we mounted it
                if [ -z "$MOUNT_INFO" ]; then
                    umount "$KS_MOUNT_POINT"
                fi
            else
                echo "Info: Only one partition found. No second partition to check for kickstart file."
            fi
        else
            echo "Error: No partitions found on USB disk ${USB_DISK_NAME}."
        fi
    fi
fi

if [ -z "$ISO_DEVICE" ]; then
    echo "Error: Could not find an attached ESXi installation media (CD-ROM or bootable USB)."
    exit 1
fi

# 2. Mount the ESXi installation media
echo "Creating ESXi mount point at $ESXI_ISO_MOUNT_POINT..."
mkdir -p "$ESXI_ISO_MOUNT_POINT"

if mount | grep -q " on ${ESXI_ISO_MOUNT_POINT} "; then
    echo "$ESXI_ISO_MOUNT_POINT is already in use. Unmounting..."
    umount "${ESXI_ISO_MOUNT_POINT}"
fi
echo "Mounting $ISO_DEVICE to $ESXI_ISO_MOUNT_POINT..."
mount -o ro "$ISO_DEVICE" "$ESXI_ISO_MOUNT_POINT"
echo "Successfully mounted $ISO_DEVICE at $ESXI_ISO_MOUNT_POINT."

# 3. Create destination directories
echo "Creating ESXi HTTP destination directory $ESXI_HTTP_DEST..."
mkdir -p "$ESXI_HTTP_DEST"

# 4. Copy ISO content and boot files
ESXI_VERSION="ESXi-ISO-Content"
ESXI_HTTP_ISO_CONTENT_DEST="${ESXI_HTTP_DEST}/${ESXI_VERSION}"

echo "Creating ESXi HTTP ISO content directory $ESXI_HTTP_ISO_CONTENT_DEST..."
mkdir -p "$ESXI_HTTP_ISO_CONTENT_DEST"

echo "Copying entire ESXi ISO content to $ESXI_HTTP_ISO_CONTENT_DEST..."
rsync -av --delete --progress "$ESXI_ISO_MOUNT_POINT/" "$ESXI_HTTP_ISO_CONTENT_DEST"/
echo "ESXi ISO content copied successfully."

echo "Copying ESXi EFI bootloader to $ESXI_HTTP_DEST/mboot.efi..."
EFI_BOOT_FILE=$(find "$ESXI_ISO_MOUNT_POINT/efi/boot/" -iname "bootx64.efi" | head -n 1)
if [ -n "$EFI_BOOT_FILE" ]; then
    cp "$EFI_BOOT_FILE" "$ESXI_HTTP_DEST"/mboot.efi
else
    echo "Error: Could not find bootx64.efi. Cannot set up HTTP boot."
    umount "$ESXI_ISO_MOUNT_POINT"
    exit 1
fi

# 5. Modify boot.cfg for HTTP boot
BOOT_CFG_FILE=$(find "$ESXI_HTTP_ISO_CONTENT_DEST" -maxdepth 1 -iname "boot.cfg" | head -n 1)

if [ -n "$BOOT_CFG_FILE" ]; then
    echo "Found boot config at $BOOT_CFG_FILE. Modifying for HTTP boot..."
    
    # Temporarily remove all kernelopt lines from the original file to avoid duplicates
    # and preserve the modules line
    MODULES_LINE=$(grep "^modules=" "$BOOT_CFG_FILE")
    sed -i '/^kernelopt=/d' "$BOOT_CFG_FILE"
    
    # Add the correct kernelopt for a scripted or interactive install
    KICKSTART_URL="http://${PXE_SERVER_IP}/esxi_ksFiles/ks.cfg"
    if [ -f "$KS_DEST_DIR/ks.cfg" ]; then
        echo "kernelopt=ks=${KICKSTART_URL}" >> "$BOOT_CFG_FILE"
        echo "Set kernelopt for kickstart installation in $BOOT_CFG_FILE."
    else
        # If no ks.cfg, default to interactive install
        echo "kernelopt=runweasel" >> "$BOOT_CFG_FILE"
        echo "Warning: Kickstart file not found. The installer will be interactive."
    fi
    # Restore the modules line if it was removed
    if ! grep -q "^modules=" "$BOOT_CFG_FILE"; then
        echo "$MODULES_LINE" >> "$BOOT_CFG_FILE"
    fi
    
    # Remove any existing prefix and add the correct one at the end
    sed -i '/^prefix=/d' "$BOOT_CFG_FILE"
    PREFIX_LINE="prefix=http://${PXE_SERVER_IP}/esxi/${ESXI_VERSION}"
    echo "$PREFIX_LINE" >> "$BOOT_CFG_FILE"
    echo "Set HTTP boot prefix in $BOOT_CFG_FILE."

    # Copy the modified boot config to the final destination for the bootloader
    echo "Copying modified boot config to $ESXI_HTTP_DEST/boot.cfg..."
    cp "$BOOT_CFG_FILE" "$ESXI_HTTP_DEST/boot.cfg"
else
    echo "Warning: boot.cfg or BOOT.CFG not found in $ESXI_HTTP_ISO_CONTENT_DEST. Cannot configure HTTP boot."
fi

# 6. Unmount the ESXi ISO
echo "Unmounting $ESXI_ISO_MOUNT_POINT..."
umount "$ESXI_ISO_MOUNT_POINT"
echo "ESXi ISO unmounted successfully."

# 7. Set permissions
echo "Setting permissions for boot directories..."
chmod -R 755 "$ESXI_HTTP_DEST"
if [ -d "$KS_DEST_DIR" ]; then
    chmod -R 755 "$KS_DEST_DIR"
fi
# Set SELinux context for HTTP directories
echo "Setting SELinux context for ESXi HTTP directories..."
semanage fcontext -a -t httpd_sys_content_t "${ESXI_HTTP_DEST}(/.*)?" || true
semanage fcontext -a -t httpd_sys_content_t "${KS_DEST_DIR}(/.*)?" || true
restorecon -R "$ESXI_HTTP_DEST" "$KS_DEST_DIR" || true

echo "ESXi HTTP boot files setup complete."

exit 0