# PXE Server for RHEL 9 and ESXi 8

This repository provides a set of scripts to build a Preboot Execution Environment (PXE) server capable of deploying both Red Hat Enterprise Linux 9 (RHEL 9) and ESXi 8.

## Overview

This project facilitates the network booting of RHEL 9 and ESXi 8 installers on client machines. It automates the configuration of the necessary services (DHCP, TFTP, and HTTP) required to serve boot images and installation media. This setup is designed for a UEFI-based boot process for both operating systems.

## Prerequisites

Before running the setup scripts, ensure your environment meets the following criteria:

*   **Operating System:** A fresh installation of RHEL 9.
*   **Privileges:** You must have `root` or `sudo` access to run these scripts.
*   **Network Configuration:** The scripts will configure a static IP for the server. However, you **must review the variables** inside each script (especially `nic-setup.sh` and `dhcp-setup.sh`) to ensure they match your network environment.
*   **Installation Media:** The RHEL 9 and ESXi installation ISOs must be attached to the server (e.g., as a virtual CD/DVD drive). The `setup-local-repo.sh` and `esxi-tftp-setup.sh` scripts will automatically detect them.

## Scripts Overview

This project is composed of several scripts. The core setup scripts (`nic-setup.sh`, `dhcp-setup.sh`, `http-setup.sh`, `tftp-setup.sh`) establish the foundational PXE services. Additionally, there are specific scripts for setting up RHEL 9 and ESXi 8 installation sources.

### Core PXE Services Setup (Run in order)

1.  `nic-setup.sh`: Configures the server's network interface with a static IP address using NetworkManager. This is a critical first step.
2.  `dhcp-setup.sh`: Installs and configures a DHCP server. It is set up to serve IP addresses and intelligently direct PXE clients to the correct bootloaders for both RHEL 9 and ESXi 8.
3.  `http-setup.sh`: Installs and configures the Apache HTTP server (`httpd`). It makes the RHEL 9 repository and ESXi installation files available over the network for clients.
4.  `tftp-setup.sh`: Installs and configures a TFTP server. It copies the necessary UEFI boot files for RHEL 9 from the local repository and creates a GRUB configuration file that points clients to the HTTP server.

### RHEL 9 Specific Setup

*   `setup-local-repo.sh`: Prepares the server by creating a local DNF/YUM repository from the attached RHEL 9 ISO. This allows the server to install all required packages without needing an internet connection. The ISO contents are copied to `/var/repo/rhel9/`.

### ESXi 8 Specific Setup

*   `esxi-tftp-setup.sh`: Finds an attached ESXi ISO, mounts it, copies essential EFI boot files to the TFTP server's ESXi directory for PXE booting, and copies the entire ISO content to an HTTP directory.

## Setup Instructions

### 1. Review and Customize Scripts

Before execution, carefully review the configuration variables at the top of each script to ensure they match your environment. This is the most important step.

*   `nic-setup.sh`: Verify `INTERFACE`, `PXE_SERVER_IP`, `GATEWAY`, and `DNS_SERVER`.
*   `dhcp-setup.sh`: Verify the subnet, range, and IP addresses match the settings in `nic-setup.sh`, and ensure the `next-server` and `filename` options are appropriate for your PXE boot environment.

### 2. Execute the Setup Scripts

Run these scripts as a privileged user in the following order to establish the PXE server and prepare both RHEL 9 and ESXi 8 installation sources.

```bash
# 1. Configure the server's network interface
sudo bash ./nic-setup.sh

# 2. Set up the local RHEL 9 repository from the ISO
#    (Attach RHEL 9 ISO before running)
sudo bash ./setup-local-repo.sh

# 3. Set up the HTTP server to serve the repositories
sudo bash ./http-setup.sh

# 4. Set up the TFTP server for RHEL 9 network boot
sudo bash ./tftp-setup.sh

# 5. Set up ESXi boot files and HTTP content from the ESXi ISO
#    (Attach ESXi ISO before running)
sudo bash ./esxi-tftp-setup.sh

# 6. Set up the DHCP server to direct clients to the appropriate bootloaders
sudo bash ./dhcp-setup.sh
```

## Usage

After successfully running all necessary setup scripts, the PXE server is ready.

1.  Connect a client machine to the same network segment as the PXE server.
2.  Power on the client and enter its BIOS/UEFI boot menu.
3.  Select "Network Boot" or "PXE Boot" as the boot device.

The client should receive a DHCP address and then download the appropriate bootloader (GRUB for RHEL 9, mboot.efi for ESXi) from the TFTP/HTTP server.

## License

[Insert License Information Here]
