#!/usr/bin/env bash

set -o errexit 
set -o errtrace 
set -o nounset 
set -o pipefail 
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR
trap 'die "Script interrupted."' INT

function error_exit() {
  trap - ERR
  local DEFAULT='Unknown failure occured.'
  local REASON="\e[97m${1:-$DEFAULT}\e[39m"
  local FLAG="\e[91m[ERROR:LXC] \e[93m$EXIT@$LINE"
  msg "$FLAG $REASON"
  exit $EXIT
}
function msg() {
  local TEXT="$1"
  echo -e "$TEXT"
}

CROSS='\033[1;31m\xE2\x9D\x8C\033[0m'
RD=`echo "\033[01;31m"`
BL=`echo "\033[36m"`
CM='\xE2\x9C\x94\033'
GN=`echo "\033[1;92m"`
CL=`echo "\033[m"`
RETRY_NUM=5
RETRY_EVERY=3
NUM=$RETRY_NUM

echo -en "${GN} Setting up Container OS... "
sed -i "/$LANG/ s/\(^# \)//" /etc/locale.gen
locale-gen >/dev/null
while [ "$(hostname -I)" = "" ]; do
  1>&2 echo -en "${CROSS}${RD}  No Network! "
  sleep $RETRY_EVERY
  ((NUM--))
  if [ $NUM -eq 0 ]
  then
    1>&2 echo -e "${CROSS}${RD}  No Network After $RETRY_NUM Tries${CL}"    
    exit 1
  fi
done
echo -e "${CM}${CL} \r"
echo -en "${GN} Network Connected: ${BL}$(hostname -I)${CL} "
echo -e "${CM}${CL} \r"

echo -en "${GN} Updating Container OS... "
apt update &>/dev/null
apt-get -qqy upgrade &>/dev/null
echo -e "${CM}${CL} \r"

echo -en "${GN} Installing Dependencies... "
apt-get install -y curl &>/dev/null
apt-get install -y sudo &>/dev/null
echo -e "${CM}${CL} \r"

echo -en "${GN} Installing pip3... "
apt-get install -y python3-pip &>/dev/null
echo -e "${CM}${CL} \r"

echo -en "${GN} Installing Docker... "
DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
mkdir -p $(dirname $DOCKER_CONFIG_PATH)
cat >$DOCKER_CONFIG_PATH <<'EOF'
{
  "log-driver": "journald"
}
EOF
sh <(curl -sSL https://get.docker.com) &>/dev/null
echo -e "${CM}${CL} \r"

echo -en "${GN} Pulling Portainer Image... "
docker pull portainer/portainer-ce:latest &>/dev/null
echo -e "${CM}${CL} \r"

echo -en "${GN} Installing Portainer Image... "
docker volume create portainer_data >/dev/null
docker run -d \
  -p 8000:8000 \
  -p 9000:9000 \
  --name=portainer \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest &>/dev/null
echo -e "${CM}${CL} \r"

echo -en "${GN} Pulling Home Assistant Image... "
docker pull homeassistant/home-assistant:stable &>/dev/null
echo -e "${CM}${CL} \r"

echo -en "${GN} Installing Home Assistant Image... "
docker volume create hass_config >/dev/null
docker run -d \
  --name homeassistant \
  --privileged \
  --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /dev:/dev \
  -v hass_config:/config \
  -v /etc/localtime:/etc/localtime:ro \
  --net=host \
  homeassistant/home-assistant:stable &>/dev/null
echo -e "${CM}${CL} \r"

echo -en "${GN} Creating Update Menu Script... "
pip3 install runlike &>/dev/null
UPDATE_PATH='/root/update'
UPDATE_CONTAINERS_PATH='/root/update-containers.sh'
cat >$UPDATE_PATH <<'EOF'
#!/bin/sh
set -o errexit
show_menu(){
    normal=`echo "\033[m"`
    safe=`echo "\033[32m"`
    menu=`echo "\033[36m"`
    number=`echo "\033[33m"`
    bgred=`echo "\033[41m"`
    fgred=`echo "\033[31m"`
    hostname -I
    printf "\n${menu}*********************************************${normal}\n"
    printf "${menu}**${number} 1)${safe} Switch to Stable Branch ${normal}\n"
    printf "${menu}**${number} 2)${number} Switch to Beta Branch ${normal}\n"
    printf "${menu}**${number} 3)${fgred} Switch to Dev Branch ${normal}\n"
    printf "${menu}**${number} 4)${safe} Backup Home Assistant Data (to root) ${normal}\n"
    printf "${menu}**${number} 5)${number} Restore Home Assistant Data ${normal}\n"
    printf "${menu}**${number} 6)${fgred} Edit Home Assistant Configuration ${normal}\n"
    printf "${menu}**${number} 7)${safe} Restart Home Assistant ${normal}\n"
    printf "${menu}**${number} 8)${safe} Just Update Containers ${normal}\n"
    printf "${menu}**${number} 9)${number} Remove Unused Images ${normal}\n"
    printf "${menu}**${number} 10)${safe} Update Host OS ${normal}\n"
    printf "${menu}**${number} 11)${safe} Reboot Host OS ${normal}\n"
    printf "${menu}*********************************************${normal}\n"
    printf "Please choose an option from the menu and enter or ${fgred}x to exit. ${normal}"
    read opt
}
option_picked(){
    msgcolor=`echo "\033[01;31m"`
    normal=`echo "\033[00;00m"`
    message=${@:-"${normal}Error: No message passed"}
    printf "${msgcolor}${message}${normal}\n"
}
clear
show_menu
while [ $opt != '' ]
    do
    if [ $opt = '' ]; then
      exit;
    else
      case $opt in
        1) clear;
            option_picked "Switching to Stable Branch";
            TAG=stable
            break;
        ;;
        2) clear;
            option_picked "Switching to Beta Branch";
            TAG=beta
            break;
        ;;
        3) while true; do
            read -p "Are you sure you want to Switch to Dev Branch? Proceed(y/n)?" yn
            case $yn in
            [Yy]* ) break;;
            [Nn]* ) exit;;
                * ) echo "Please answer yes or no.";;
            esac
           done
           clear;
            option_picked "Switching to Dev Branch";
            TAG=dev
            break;
        ;;
        4) clear;
            option_picked "Backing up Home Assistant Data to root (hass_config)";
            rm -r hass_config;
            cp -pR /var/lib/docker/volumes/hass_config/ /root/;
            sleep 2;
            clear;
            show_menu;
        ;;
        5) while true; do
            read -p "Are you sure you want to Restore Home Assistant Data? Proceed(y/n)?" yn
            case $yn in
            [Yy]* ) break;;
            [Nn]* ) exit;;
                * ) echo "Please answer yes or no.";;
            esac
           done
           clear;
            option_picked "Restoring Home Assistant Data from root (hass_config)";
            rm -r /var/lib/docker/volumes/hass_config/_data;
            cp -pR /root/hass_config/_data /var/lib/docker/volumes/hass_config/;
            sleep 2;
            clear;
            show_menu;
        ;;
        6) while true; do
            read -p "Are you sure you want to Edit Home Assistant Configuration? Proceed(y/n)?" yn
            case $yn in
            [Yy]* ) break;;
            [Nn]* ) exit;;
                * ) echo "Please answer yes or no.";;
            esac
           done
           clear;
            option_picked "Editing Home Assistant Configuration";
            nano /var/lib/docker/volumes/hass_config/_data/configuration.yaml;
            clear;
            show_menu;
        ;;
        7) clear;
            option_picked "Restarting Home Assistant";
            docker restart homeassistant;
            exit;
        ;;
        8) clear;
            option_picked "Just Updating Containers";
            ./update-containers.sh;
            sleep 2;
            clear;
            show_menu;
        ;;
        9) clear;
            option_picked "Removing Unused Images";
            docker image prune -af;
            sleep 2;
            clear;
            show_menu;
        ;;
        10) clear;
            option_picked "Updating Host OS";
            apt update && apt upgrade -y;
            sleep 2;
            clear;
            show_menu;
        ;;
        11) clear;
            option_picked "Reboot Host OS";
            reboot;
            exit;
        ;;
        x)exit;
        ;;
        \n)exit;
        ;;
        *)clear;
            option_picked "Please choose an option from the menu";
            show_menu;
        ;;
      esac
    fi
  done
docker pull homeassistant/home-assistant:$TAG
docker rm --force homeassistant
docker run -d \
  --name homeassistant \
  --privileged \
  --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /dev:/dev \
  -v hass_config:/config \
  -v /etc/localtime:/etc/localtime:ro \
  -v /etc/timezone:/etc/timezone:ro \
  --net=host \
  homeassistant/home-assistant:$TAG
EOF
sudo chmod +x /root/update
cat >$UPDATE_CONTAINERS_PATH <<'EOF'
#!/bin/bash
set -o errexit
CONTAINER_LIST="${1:-$(docker ps -q)}"
for container in ${CONTAINER_LIST}; do
  CONTAINER_IMAGE="$(docker inspect --format "{{.Config.Image}}" --type container ${container})"
  RUNNING_IMAGE="$(docker inspect --format "{{.Image}}" --type container "${container}")"
  docker pull "${CONTAINER_IMAGE}"
  LATEST_IMAGE="$(docker inspect --format "{{.Id}}" --type image "${CONTAINER_IMAGE}")"
  if [[ "${RUNNING_IMAGE}" != "${LATEST_IMAGE}" ]]; then
    echo "Updating ${container} image ${CONTAINER_IMAGE}"
    DOCKER_COMMAND="$(runlike "${container}")"
    docker rm --force "${container}"
    eval ${DOCKER_COMMAND}
  fi 
done
EOF
sudo chmod +x /root/update-containers.sh
echo -e "${CM}${CL} \r"
mkdir /root/hass_config
echo -en "${GN} Customizing Container... "
rm /etc/motd
rm /etc/update-motd.d/10-uname
touch ~/.hushlogin
GETTY_OVERRIDE="/etc/systemd/system/container-getty@1.service.d/override.conf"
mkdir -p $(dirname $GETTY_OVERRIDE)
cat << EOF > $GETTY_OVERRIDE
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud tty%I 115200,38400,9600 \$TERM
EOF
systemctl daemon-reload
systemctl restart $(basename $(dirname $GETTY_OVERRIDE) | sed 's/\.d//')
echo -e "${CM}${CL} \r"

echo -en "${GN} Cleanup... "
apt-get autoremove >/dev/null
apt-get autoclean >/dev/null
rm -rf /var/{cache,log}/* /var/lib/apt/lists/*
echo -e "${CM}${CL} \n"
