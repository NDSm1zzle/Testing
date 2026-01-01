# PXE Server for RHEL 9

This repository provides a set of scripts to build a Preboot Execution Environment (PXE) server using Red Hat Enterprise Linux 9 (RHEL 9).

## Overview

This project facilitates the network booting of RHEL 9 installers on client machines. It automates the configuration of the necessary services (DHCP, TFTP, and HTTP) required to serve boot images and installation media. This setup is designed for a UEFI-based boot process.

## Prerequisites

Before running the setup scripts, ensure your environment meets the following criteria:

*   **Operating System:** A fresh installation of RHEL 9.
*   **Privileges:** You must have `root` or `sudo` access to run these scripts.
*   **Network Configuration:** The scripts will configure a static IP for the server. However, you **must review the variables** inside each script (especially `nic-setup.sh` and `dhcp-setup.sh`) to ensure they match your network environment.
*   **Installation Media:** The RHEL 9 installation ISO must be attached to the server (e.g., as a virtual CD/DVD drive). The `setup-local-repo.sh` script will automatically detect it.

## Scripts Overview

This project is composed of five scripts that must be run in order:

1.  `nic-setup.sh`: Configures the server's network interface with a static IP address using NetworkManager. This is a critical first step.
2.  `setup-local-repo.sh`: Prepares the server by creating a local DNF/YUM repository from the attached RHEL 9 ISO. This allows the server to install all required packages without needing an internet connection. The ISO contents are copied to `/var/repo/rhel9/`.
3.  `http-setup.sh`: Installs and configures the Apache HTTP server (`httpd`). It makes the repository available over the network for clients by linking the web root to the repository files.
4.  `tftp-setup.sh`: Installs and configures a TFTP server. It copies the necessary UEFI boot files from the local repository and creates a GRUB configuration file that points clients to the HTTP server.
5.  `dhcp-setup.sh`: Installs and configures a DHCP server. It is set up to serve IP addresses and direct PXE clients to the TFTP server.

## Setup Instructions

### 1. Review and Customize Scripts

Before execution, carefully review the configuration variables at the top of each script to ensure they match your environment. This is the most important step.

*   `nic-setup.sh`: Verify `INTERFACE`, `PXE_SERVER_IP`, `GATEWAY`, and `DNS_SERVER`.
*   `dhcp-setup.sh`: Verify the subnet, range, and IP addresses match the settings in `nic-setup.sh`.
*   `tftp-setup.sh`: Verify the hardcoded server IP in the `grub.cfg` section.

### 2. Execute the Scripts

Run the scripts as a privileged user in the following order.

```bash
# 1. Configure the server's network interface
sudo bash ./nic-setup.sh

# 2. Set up the local repository from the ISO
sudo bash ./setup-local-repo.sh

# 3. Set up the HTTP server to serve the repository
sudo bash ./http-setup.sh

# 4. Set up the TFTP server for network boot
sudo bash ./tftp-setup.sh

# 5. Set up the DHCP server to direct clients
sudo bash ./dhcp-setup.sh
```

## Usage

After successfully running all setup scripts, the PXE server is ready.

1.  Connect a client machine to the same network segment as the PXE server.
2.  Power on the client and enter its BIOS/UEFI boot menu.
3.  Select "Network Boot" or "PXE Boot" as the boot device.

The client should receive a DHCP address and then download the GRUB bootloader from the TFTP server.

## License

[Insert License Information Here]
