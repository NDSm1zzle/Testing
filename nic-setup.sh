#!/bin/bash

# This script configures a static IP address on the primary network interface using NetworkManager (nmcli).

set -e

# --- Configuration ---
# Edit these values to match your PXE server's network environment.
PXE_SERVER_IP="10.0.0.253"
GATEWAY="10.0.0.1"
DNS_SERVER="10.0.0.1"
# The name for the NetworkManager connection profile.
CON_NAME="pxe-static"
# Directory for shared configuration
CONF_DIR="/etc/pxe-server"
CONF_FILE="${CONF_DIR}/pxe.conf"
# --- End Configuration ---

# Function to check the exit status of the last command
check_status() {
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed during: $1"
        exit 1
    else
        echo "SUCCESS: $1"
    fi
}

echo "--- Static Network Interface Configuration ---"

# 1. Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use 'sudo bash ./nic-setup.sh'."
    exit 1
fi

# 2. Discover the highest-numbered network interface, excluding loopback and virtual bridge
echo "Discovering network interface..."
INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE '^(lo|virbr)' | sort -V | tail -n 1)

if [ -z "$INTERFACE" ]; then
    echo "ERROR: Could not automatically find a suitable network interface. Exiting."
    exit 1
fi
echo "Found interface: $INTERFACE."

# 3. Save the discovered interface for other scripts to use
echo "Saving interface configuration to $CONF_FILE..."
mkdir -p "$CONF_DIR"
echo "INTERFACE=${INTERFACE}" > "$CONF_FILE"
echo "PXE_SERVER_IP=${PXE_SERVER_IP}" >> "$CONF_FILE"
check_status "Saving interface configuration"

# 4. Find or create a connection profile for the interface
if ! nmcli con show "$CON_NAME" &> /dev/null; then
    echo "Creating new connection profile named '$CON_NAME' for $INTERFACE..."
    nmcli con add type ethernet con-name "$CON_NAME" ifname "$INTERFACE"
    check_status "Creating static IP connection profile"
else
    echo "Found existing connection profile: '$CON_NAME'. It will be modified."
fi

# 5. Modify the connection with static IP configuration
echo "Applying static IP configuration to '$CON_NAME'..."
nmcli con mod "$CON_NAME" \
    connection.interface-name "$INTERFACE" \
    ipv4.method manual \
    ipv4.addresses "$PXE_SERVER_IP/24" \
    ipv4.gateway "$GATEWAY" \
    ipv4.dns "$DNS_SERVER"
check_status "Modifying connection with static IP details"

# 6. Activate the connection
echo "Activating connection '$CON_NAME'..."
nmcli con up "$CON_NAME"
check_status "Activating static IP connection"

echo ""
echo "Configuration complete for interface '$INTERFACE'."
echo "You can verify the settings with: ip addr show ${INTERFACE}"