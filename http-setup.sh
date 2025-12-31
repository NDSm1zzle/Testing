#!/bin/bash

yum install -y httpd
firewall-cmd --add-service=http --permanent
firewall-cmd --reload
systemctl enable --now httpd

mkdir -p /var/www/html/RHEL-9/x86_64/
mountpoint -q /mnt || mount -o ro /dev/sr0 /mnt
cp -r /mnt/* /var/www/html/RHEL-9/x86_64/
umount /mnt

systemctl restart httpd 
