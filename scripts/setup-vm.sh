#!/bin/bash

source scripts/util.sh
source ./.idv-config

vm_dir="$cdir/vm"

function create_vm_dir() {
(mkdir -p {$vm_dir,$vm_dir/fw,$vm_dir/disk,$vm_dir/iso,$vm_dir/scripts})
}

function build_fw_directory() {
  [[ -f /usr/share/qemu/bios.bin ]] && run_as_root "cp /usr/share/qemu/bios.bin $vm_dir/fw" \
      || echo "Error: can't find /usr/share/qemu/bios.bin file"
  [[ -f /usr/share/qemu/OVMF.fd ]] && run_as_root "cp /usr/share/qemu/OVMF.fd $vm_dir/fw" \
      || echo "Error: can't find /usr/share/qemu/OVMF.fd file"
}

CREATE_VGPU="$vm_dir/create-vgpu"
INSTALL_GUEST="$vm_dir/install-guest"
START_GUEST="$vm_dir/start-guest"

gvt_disp_ports_mask="/sys/class/drm/card0/gvt_disp_ports_mask"
mdev_dir="/sys/bus/pci/devices/0000:00:02.0/mdev_supported_types"

function build_create_vgpu() {
  unset temp
  vgpuinfo=$1

  temp+=( "#!/bin/bash" )

  temp+=( "# This file is auto generated by IDV setup.sh file." )
  # set VGPU
  vgpu_opt=($(grep "VGPU" $idv_config_file))
  temp+=( "${vgpu_opt[@]}" )

  # set port mask
  opt=($(grep "port_mask=" $idv_config_file))
  temp+=( "echo \"${opt#*=}\" > $gvt_disp_ports_mask" )

  for i in ${vgpu_opt[@]}; do
    temp+=( "echo \"${i%%=*}\" > $mdev_dir/$mdev_type/create" )
  done

  printf "%s\n"  "Creating $CREATE_VGPU-$vgpuinfo.sh file.. " 
  printf "%s\n"  "${temp[@]}" > ./temp_file
  run_as_root "cp ./temp_file $CREATE_VGPU-$vgpuinfo.sh"
  run_as_root "chmod +x $CREATE_VGPU-$vgpuinfo.sh"
  $(rm temp_file)
}

function build_install_qemu_batch() {
  vgpu=$1
  low_vgpu="$( echo $vgpu | tr '[:upper:]' '[:lower:]' )"
  unset str

  str+=( "#!/bin/bash" )
  str+=( "# This file is auto generated by IDV setup.sh file." )
  str+=( "/usr/local/bin/qemu-system-x86_64 \\" )
  str+=( "-m 4096 -smp 1 -M q35 \\" )
  str+=( "-enable-kvm \\" )

  qcow_opt=($(grep "GUEST_QCOW2_$vgpu" $idv_config_file))
  filename=${qcow_opt##*/}
  IFS='.' read fname fext <<< "${filename}"
  str+=( "-name  $fname-$low_vgpu \\" )
  str+=( "-boot d \\" )

  opt=($(grep "GUEST_ISO_$vgpu=" $idv_config_file))
  str+=( "-cdrom ${opt##*=} \\" )
  temp=${qcow_opt##*=}
  str+=( "-drive file=${temp%.*}-$low_vgpu.$fext \\" )

  fw_opt=($(grep "FW_$vgpu" $idv_config_file))
  str+=( "-bios ${fw_opt##*=} \\" )

  str+=( "-cpu host -usb -device usb-tablet \\" )
  str+=( "-vga cirrus \\" )
  str+=( "-k en-us \\" )
  str+=( "-vnc :0" )

  printf "%s\n"  "Creating $INSTALL_GUEST-$low_vgpu.sh file.. "
  printf "%s\n"  "${str[@]}" > ./temp_file
  run_as_root "cp ./temp_file $INSTALL_GUEST-$low_vgpu.sh"
  run_as_root "chmod +x $INSTALL_GUEST-$low_vgpu.sh"
  $(rm temp_file)
}

gfx_device="/sys/bus/pci/devices/0000:00:02.0"
function build_start_qemu_batch() {
  vgpu=$1
  low_vgpu="$( echo $vgpu | tr '[:upper:]' '[:lower:]' )"

  unset str

O_IFS=${IFS}
IFS=$'\n'
  str+=( "#!/bin/bash -x" )
  str+=( "# This file is auto generated by IDV setup.sh file." )
  str+=( "/usr/bin/qemu-system-x86_64 \\" )
  str+=( "-m 4096 -smp 1 -M q35 \\" )
  str+=( "-enable-kvm \\" )


  qcow_opt=($(grep "GUEST_QCOW2_$vgpu" $idv_config_file))
  filename=${qcow_opt##*/}
  IFS='.' read fname fext <<< "${filename}"
  str+=( "-name  $fname-$low_vgpu \\" )

  temp=${qcow_opt##*=}
  str+=( "-hda ${temp%.*}-$low_vgpu.$fext \\" )

  fw_opt=($(grep "FW_$vgpu" $idv_config_file))
  str+=( "-bios ${fw_opt##*=} \\" )

  str+=( "-cpu host -usb -device usb-tablet \\" )
  str+=( "-vga none \\" )
  str+=( "-k en-us \\" )
  str+=( "-vnc :0 \\" )
  str+=( "-cpu host -usb -device usb-tablet \\" )

  vgpu_opt=($(grep "VGPU" $idv_config_file))
  if [[ -z $vgpu_opt ]]; then
    str+=( "-device vfio-pci,sysfsdev=$gfx_device/$VGPU1,display=off,x-igd-opregion=on" )
  else
    str+=( "-device vfio-pci,sysfsdev=$gfx_device/$VGPU1,display=off,x-igd-opregion=on \\" )
    opt=($(grep "QEMU_USB" $idv_config_file))
    temp="${opt#*=\"}"
    str+=( ${temp%\"} )
  fi

  printf "%s\n"  "Creating $START_GUEST-$low_vgpu.sh file.. "
  printf "%s\n"  "${str[@]}" > ./temp_file
  run_as_root "cp ./temp_file $START_GUEST-$low_vgpu.sh"
  run_as_root "chmod +x $START_GUEST-$low_vgpu.sh"
IFS=${O_IFS}
  $(rm temp_file)
}

_iso_="$cdir/iso/*.iso"
QEMU_IMG="/usr/bin/qemu-img"
#====================================================
# Create *.qcow2 file if user select the ISO file
#====================================================
function get_user_option() {
  isofiles=( $_iso_ )
#  echo "iso: ${isofiles[@]}"
  vgpuinfo=$1

  [[ ${isofiles[0]} == "$_iso_" ]] && update_idv_config "GUEST_ISO_$vgpuinfo" "" \
    && dialog --msgbox "Can't find ISO files in $cdir/iso. Please download guest OS ISO file to $cdir/iso\n\n" 10 40 && exit 1

  for (( i=0; i<${#isofiles[@]}; i++ )); do
    list+=($i "${isofiles[$i]##*\/}" off "${isofiles[$i]}")
    echo "($i)list: ${list[@]}"
  done

  cmd=(dialog --item-help --radiolist "Please choose ISO files from ./iso for your guest OS." 30 80 5)
  list=(${list[@]})
  choices=$("${cmd[@]}" "${list[@]}" 2>&1 >/dev/tty)

  [[ $? -eq 1 ]] && exit 0    # cancel pressed

#  echo "choices: $choices, cmd: $? (OK/Cancel)"

  for (( i=0; i<${#list[@]}; $((i+=4)) )); do
    echo "($i): ${list[$i]}"
    if [[ $choices == ${list[$i]} ]]; then
      update_idv_config "GUEST_ISO_$vgpuinfo" "${list[$((i+3))]}"
      ($QEMU_IMG create -f qcow2 temp.qcow2 60G)
      run_as_root "mv temp.qcow2 $vm_dir/disk/${list[$((i+1))]%%.*}.qcow2"
      update_idv_config "GUEST_QCOW2_$vgpuinfo" "$vm_dir/disk/${list[$((i+1))]%%.*}.qcow2"
      run_as_root "rm -f temp.qcow2"
    fi
  done
}


function create_files() {
  vgpuinfo=$1
  echo "temp: $vgpuinfo"

  build_fw_directory
  build_create_vgpu "$vgpuinfo"
  build_install_qemu_batch "$vgpuinfo"
  build_start_qemu_batch "$vgpuinfo"
}

