#!/bin/bash -x
# This file is auto generated by IDV setup.sh file.
/usr/bin/qemu-system-x86_64 \
-m 4096 -smp 1 -M q35 \
-enable-kvm \
-name  android-vgpu2 \
-hda ./vm/disk/android-vgpu2.qcow2 \
-bios ./vm/fw/bios.bin \
-cpu host -usb -device usb-tablet \
-vga none \
-k en-us \
-vnc :0 \
-cpu host -usb -device usb-tablet \
-device usb-host,hostbus=1,hostport=10.2 -device usb-host,hostbus=1,hostport=10 \
-device vfio-pci,sysfsdev=/sys/bus/pci/devices/0000:00:02.0/74481d22-ffa9-11ea-a6a2-4789798d72bc,display=off,x-igd-opregion=on
