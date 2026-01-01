#!/bin/bash

# This script configures a local DNF/YUM repository from a RHEL 9 ISO file.

# 1. Check if the script is being run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

# 2. Find the ISO device (virtual DVD/CD-ROM)
ISO_DEVICE=$(lsblk -no NAME,TYPE | awk '$2=="rom"{print "/dev/"$1}' | head -n 1)

if [ -z "$ISO_DEVICE" ]; then
    echo "Error: Could not find an attached ISO device (virtual DVD/CD-ROM)."
    echo "Please attach a RHEL 9 installation ISO and run the script again."
    exit 1
fi

echo "Found ISO device at $ISO_DEVICE."


# 3. Define paths and create directories
MOUNT_POINT="/mnt/iso_temp"
REPO_PATH="/var/repo/rhel9" # Permanent location for repo files
echo "Creating temporary mount point at $MOUNT_POINT..."
mkdir -p "$MOUNT_POINT"
echo "Creating permanent repository path at $REPO_PATH..."
mkdir -p "$REPO_PATH"

# 4. Mount the ISO, copy files, and unmount
echo "Mounting $ISO_DEVICE to $MOUNT_POINT..."
# Unmount if it's already mounted to avoid errors
if mount | grep -q " on ${MOUNT_POINT} "; then
    echo "A device is already mounted at ${MOUNT_POINT}. Unmounting first."
    umount "${MOUNT_POINT}"
fi
mount -o ro "$ISO_DEVICE" "$MOUNT_POINT"
if [ $? -ne 0 ]; then
    echo "Error: Failed to mount the ISO."
    exit 1
fi

echo "Copying repository files to $REPO_PATH. This may take a few minutes..."
cp -rT "$MOUNT_POINT" "$REPO_PATH"

echo "Unmounting ISO..."
umount "$MOUNT_POINT"
rmdir "$MOUNT_POINT"

# 5. Create the local repository configuration file
REPO_FILE="/etc/yum.repos.d/local.repo"
echo "Creating repository configuration file at $REPO_FILE..."
cat <<EOF > "$REPO_FILE"
[local-baseos]
name=Local RHEL 9 BaseOS
baseurl=file://${REPO_PATH}/BaseOS
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-appstream]
name=Local RHEL 9 AppStream
baseurl=file://${REPO_PATH}/AppStream
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
EOF

# 6. Clean DNF cache and verify the repositories
echo "Cleaning DNF cache..."
dnf clean all > /dev/null

echo "Verifying repositories..."
dnf repolist --enabled | grep 'local-'

echo ""
echo "Local repository setup is complete."
echo "You can now run the c3po-pxe.sh script."