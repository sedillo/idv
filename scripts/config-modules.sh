#!/bin/bash -e

#================================================
# 3) Add modules for KVM/GVTg
#================================================
function add_modules() {
modules=(kvmgt vfio-iommu-type1 vfio-mdev vfio-pci)

  echo "${green}Adding kernel modules.${NC}"
  for i in "${modules[@]}"; do
    echo $i
    grep -qxF $i /etc/initramfs-tools/modules || echo $i >> /etc/initramfs-tools/modules
  done
  update-initramfs -u -k all
}

add_modules

