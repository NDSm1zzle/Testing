#!/bin/bash

set -e

# Install tftp-server package for IPv4
yum install -y tftp-server tftp
# Disable default socket to prevent port 69 conflict
systemctl disable --now tftp.socket
cp /usr/lib/systemd/system/tftp.service /etc/systemd/system/tftp-server.service
cp /usr/lib/systemd/system/tftp.socket /etc/systemd/system/tftp-server.socket
sed -i -e '/^ExecStart=/ s/-s/-p -s/' -e 's/tftp.socket/tftp-server.socket/' /etc/systemd/system/tftp-server.service


firewall-cmd --add-service=tftp --permanent
firewall-cmd --reload

mkdir -p /var/lib/tftpboot/redhat
mountpoint -q /mnt || mount -o ro /dev/sr0 /mnt
cp -r /mnt/EFI /var/lib/tftpboot/redhat/

mkdir -p /var/lib/tftpboot/images/RHEL-9/
cp /mnt/images/pxeboot/{vmlinuz,initrd.img} /var/lib/tftpboot/images/RHEL-9/

umount /mnt

chmod -R 755 /var/lib/tftpboot/
restorecon -R /var/lib/tftpboot/

cat <<EOF > /var/lib/tftpboot/redhat/EFI/BOOT/grub.cfg
set timeout=60
menuentry 'RHEL 9' {
  linux images/RHEL-9/vmlinuz ip=dhcp inst.repo=http://10.0.0.253/RHEL-9/x86_64/
  initrd images/RHEL-9/initrd.img
}
EOF

systemctl daemon-reload
systemctl enable --now tftp-server.socket

# Functional test for TFTP server
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