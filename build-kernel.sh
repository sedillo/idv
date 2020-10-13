#!/bin/bash

source ./scripts/util.sh

function install_kernel() {
  debs=$( ls $cdir/*.deb )
  echo "${yellow}$debs${NC}"

  [[ -z "$debs" ]] && echo -e "${red}✖${NC} Can't find *.deb file" && exit 1

  source $cdir/scripts/config-grub.sh
  run_as_root "dpkg -i *.deb"
  source $cdir/scripts/config-modules.sh

  echo "reboot in 5 seconds. Control + C to abort.."
  sleep 5
  run_as_root "reboot" 
}

# check for install option.
[[ $1 == "install" ]] && echo "installing kernel" && exit 0

run_as_root "apt install dialog"

echo "idv config file: $idv_config_file"
source $idv_config_file

# if repo is not set, then run config-kernel to get option for kernel repo
[[ -z $repo || -z $branch ]] && source $cdir/scripts/config-kernel-new.sh

# Install docker to host if not installed
source $cdir/scripts/install-docker.sh

# delete linux*.deb file before building new
( rm -rf linux*.deb )

# run docker as user to build kernel
run_as_root "docker run --rm -v $cdir:/build \
        -u $(id -u ${USER}):$(id -g ${USER}) \
       --name bob mydocker/bob_the_builder  bash -c \"cd /build/docker; ./build-docker.sh\""

debs=$( ls $cdir/*.deb )
echo "${yellow}$debs${NC}"

[[ -z "$debs" ]] && echo -e "${red}✖${NC} Oops.. kernel build error" && exit 1

read -r -p "\n ${green}✔${NC} Want to install the kernel and reboot? [y/N] " answer
case "$answer" in
  [yY]) intall_kernel;;
  *) echo "you can install kernel using ${yellow}$0 install${NC}";;
esac

