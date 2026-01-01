# PXE Server for RHEL 9

This repository provides a set of scripts to build a Preboot Execution Environment (PXE) server using Red Hat Enterprise Linux 9 (RHEL 9).

## Overview

This project facilitates the network booting of RHEL 9 installers on client machines. It automates the configuration of the necessary services (DHCP, TFTP, and HTTP) required to serve boot images and installation media.

These scripts are designed for a UEFI-based boot process.

## Prerequisites

Before running the setup scripts, ensure your environment meets the following criteria:

*   **Operating System:** A fresh installation of RHEL 9.
*   **Privileges:** You must have `root` or `sudo` access.
*   **Static IP Address:** The server must be configured with a static IP address. **The scripts hardcode the server's IP as `10.0.0.253` on the `10.0.0.0/24` subnet.**
*   **Network Interface:** The `dhcp-setup.sh` script specifically targets the `ens34` network interface.
*   **Installation Media:** The RHEL 9 installation ISO must be attached to the server, for example as a virtual CD/DVD drive at `/dev/sr0`.

## Scripts Overview

This repository contains three main setup scripts:

*   `http-setup.sh`: Installs and configures the Apache HTTP server (`httpd`). It copies the entire RHEL 9 installation media from `/dev/sr0` to `/var/www/html/RHEL-9/x86_64/`, making it available as a network installation repository.
*   `tftp-setup.sh`: Installs and configures a TFTP server. It copies the necessary UEFI boot files and kernel images from the ISO. It also creates a GRUB configuration file that points clients to the HTTP repository for the actual installation files.
*   `dhcp-setup.sh`: Installs and configures a DHCP server. It is configured to serve IP addresses on the `10.0.0.0/24` network and directs PXE clients to the TFTP server (`10.0.0.253`) to download the bootloader.

## Setup Instructions

### 1. Review and Customize Scripts (Optional)

If your network environment differs from the hardcoded values, you must edit the scripts before execution.

*   **Server IP and Subnet:** If your server's IP is not `10.0.0.253` or the subnet is not `10.0.0.0/24`, you must update the IP addresses and subnet masks in `dhcp-setup.sh` and `tftp-setup.sh` (`grub.cfg` portion).
*   **Network Interface:** If your network interface is not `ens34`, you must edit `dhcp-setup.sh`.

### 2. Attach RHEL 9 ISO

Ensure the RHEL 9 installer ISO is attached to your server and available at `/dev/sr0`. On a virtual machine, this can be done by connecting the ISO file to the VM's virtual CD/DVD drive.

### 3. Execute the Scripts

Run the scripts as a privileged user in the following order. Each script is self-contained and will install dependencies, configure services, and open required firewall ports.

```bash
# Set up the HTTP installation repository first
sudo bash ./http-setup.sh

# Set up the TFTP server to provide boot files
sudo bash ./tftp-setup.sh

# Set up the DHCP server to direct clients
sudo bash ./dhcp-setup.sh
```

## Usage

After successfully running the setup scripts, the PXE server is ready.

1.  Connect a client machine to the same network segment as the PXE server.
2.  Power on the client and enter its BIOS/UEFI boot menu.
3.  Select "Network Boot" or "PXE Boot" as the boot device.

The client should receive a DHCP address and then download the GRUB bootloader from the TFTP server, which will then present a menu to start the RHEL 9 network installation.

## License

[Insert License Information Here]
