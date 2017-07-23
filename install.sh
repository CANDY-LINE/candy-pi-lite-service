#!/usr/bin/env bash

VENDOR_HOME=/opt/candy-line

SERVICE_NAME=candy-pi-lite
GITHUB_ID=CANDY-LINE/candy-pi-lite-service
VERSION=1.0.0
BOOT_APN=${BOOT_APN:-soracom.io}
# Channel B
UART_PORT="/dev/ttySC1"
MODEM_BAUDRATE=${MODEM_BAUDRATE:-460800}
SC16IS7xx_DT_NAME="sc16is752-spi0-ce1"

NODEJS_VERSIONS="v4"
CANDY_RED_NODE_OPTS="--max-old-space-size=256"

SERVICE_HOME=${VENDOR_HOME}/${SERVICE_NAME}
SRC_DIR="${SRC_DIR:-/tmp/$(basename ${GITHUB_ID})-${VERSION}}"
CANDY_RED=${CANDY_RED:-1}
KERNEL="${KERNEL:-$(uname -r)}"
CONTAINER_MODE=0
if [ "${KERNEL}" != "$(uname -r)" ]; then
  CONTAINER_MODE=1
fi
WELCOME_FLOW_URL=https://git.io/vKhk3
PPP_PING_INTERVAL_SEC=${PPP_PING_INTERVAL_SEC:-0}
NTP_DISABLED=${NTP_DISABLED:-1}

REBOOT=0

function err {
  echo -e "\033[91m[ERROR] $1\033[0m"
}

function info {
  echo -e "\033[92m[INFO] $1\033[0m"
}

function alert {
  echo -e "\033[93m[ALERT] $1\033[0m"
}

function setup {
  [ "${DEBUG}" ] || rm -fr ${SRC_DIR}
}

function assert_root {
  if [[ $EUID -ne 0 ]]; then
     alert "This script must be run as root"
     exit 1
  fi
}

function test_connectivity {
  curl -s --head --fail -o /dev/null https://github.com 2>&1
  if [ "$?" != 0 ]; then
    alert "Internet connection is required"
    exit 1
  fi
}

function ask_to_unistall_if_installed {
  if [ -f "${SERVICE_HOME}/environment" ]; then
    alert "Please uninstall candy-pi-lite-service first by 'sudo /opt/candy-line/candy-pi-lite/uninstall.sh'"
    exit 1
  fi
}

function download {
  if [ -d "${SRC_DIR}" ]; then
    return
  fi
  cd /tmp
  curl -L https://github.com/${GITHUB_ID}/archive/${VERSION}.tar.gz | tar zx
  if [ "$?" != "0" ]; then
    err "Make sure internet is available"
    exit 1
  fi
}

function _ufw_setup {
  info "Configuring ufw..."
  ufw --force disable
  ufw deny in on ppp0
  for n in `ls /sys/class/net`
  do
    if [ "${n}" != "lo" ] && [ "${n}" != "ppp0" ]; then
      ufw allow in on ${n}
      if [ "$?" != "0" ]; then
        err "Failed to configure ufw for the network interface: ${n}"
        exit 4
      fi
    fi
  done
  ufw --force enable
}

function configure_sc16is7xx {
  info "Configuring SC16IS7xx..."
  SC16IS7xx_DTO="/boot/overlays/${SC16IS7xx_DT_NAME}.dtbo"
  if [ ! -f "${SC16IS7xx_DTO}" ]; then
    dtc -@ -I dts -O dtb -o ${SC16IS7xx_DTO} ${SRC_DIR}/boot/overlays/${SC16IS7xx_DT_NAME}.dts
  fi
  RET=`grep "^dtoverlay=${SC16IS7xx_DT_NAME}" /boot/config.txt`
  if [ "$?" != "0" ]; then
    if [ ! -f "/boot/config.txt.bak" ]; then
      cp /boot/config.txt /boot/config.txt.bak
    fi
    echo "dtoverlay=${SC16IS7xx_DT_NAME}" >> /boot/config.txt
  fi
}

function install_ppp {
  info "Installing ufw and ppp..."
  apt-get update -y
  apt-get install -y ufw ppp pppconfig

  cp -f ${SRC_DIR}/systemd/start_pppd.sh ${SERVICE_HOME}/start_pppd.sh
  cp -f ${SRC_DIR}/systemd/apn-list.json ${SERVICE_HOME}/apn-list.json
  port="${UART_PORT}"
  sed -i -e "s/%MODEM_SERIAL_PORT%/${port//\//\\/}/g" ${SERVICE_HOME}/start_pppd.sh
  sed -i -e "s/%MODEM_BAUDRATE%/${MODEM_BAUDRATE//\//\\/}/g" ${SERVICE_HOME}/start_pppd.sh

  _ufw_setup
}

function install_candy_board {
  RET=`which pip`
  RET=$?
  if [ "${RET}" != "0" ]; then
    info "Installing pip..."
    curl -L https://bootstrap.pypa.io/get-pip.py | /usr/bin/env python
  fi

  pip install --upgrade candy-board-cli
  pip install --upgrade candy-board-qws
}

function install_candy_red {
  if [ "${CANDY_RED}" == "0" ]; then
    return
  fi
  NODEJS_VER=`node -v`
  if [ "$?" == "0" ]; then
    for v in ${NODEJS_VERSIONS}
    do
      echo ${NODEJS_VER} | grep -oE "${v/./\\.}\..*"
      if [ "$?" == "0" ]; then
        unset NODEJS_VER
      fi
    done
  else
    NODEJS_VER="N/A"
  fi
  apt-get update -y
  if [ -n "${NODEJS_VER}" ]; then
    info "Installing Node.js..."
    MODEL_NAME=`cat /proc/cpuinfo | grep "model name"`
    if [ "$?" != "0" ]; then
      alert "Unsupported environment"
      exit 1
    fi
    apt-get remove -y nodered nodejs nodejs-legacy npm
    echo ${MODEL_NAME} | grep -o "ARMv6"
    if [ "$?" == "0" ]; then
      cd /tmp
      wget http://node-arm.herokuapp.com/node_archive_armhf.deb
      dpkg -i node_archive_armhf.deb
    else
      curl -sL https://deb.nodesource.com/setup_4.x | sudo bash -
      apt-get install -y nodejs
    fi
  fi
  info "Installing dependencies..."
  apt-get install -y python-dev python-rpi.gpio bluez libudev-dev
  cd ~
  npm cache clean
  info "Installing CANDY-RED..."
  WELCOME_FLOW_URL=${WELCOME_FLOW_URL} NODE_OPTS=${CANDY_RED_NODE_OPTS} npm install -g --unsafe-perm candy-red
  REBOOT=1
}

function test_boot_apn {
  CREDS=`/usr/bin/env python -c "with open('${SRC_DIR}/systemd/apn-list.json') as f:import json;c=json.load(f);print('${BOOT_APN}' in c)"`
  if [ "${CREDS}" != "True" ]; then
    err "Invalid BOOT_APN value => ${BOOT_APN}"
    exit 1
  fi
}

function install_service {
  info "Installing system service ..."
  RET=`systemctl | grep ${SERVICE_NAME}.service | grep -v not-found`
  RET=$?
  if [ "${RET}" == "0" ]; then
    return
  fi
  download
  test_boot_apn

  LIB_SYSTEMD="$(dirname $(dirname $(which systemctl)))"
  if [ "${LIB_SYSTEMD}" == "/" ]; then
    LIB_SYSTEMD=""
  fi
  LIB_SYSTEMD="${LIB_SYSTEMD}/lib/systemd"

  mkdir -p ${SERVICE_HOME}
  cp -f ${SRC_DIR}/systemd/boot-ip.*.json ${SERVICE_HOME}
  cp -f ${SRC_DIR}/systemd/environment.txt ${SERVICE_HOME}/environment
  sed -i -e "s/%VERSION%/${VERSION//\//\\/}/g" ${SERVICE_HOME}/environment
  sed -i -e "s/%BOOT_APN%/${BOOT_APN//\//\\/}/g" ${SERVICE_HOME}/environment
  sed -i -e "s/%PPP_PING_INTERVAL_SEC%/${PPP_PING_INTERVAL_SEC//\//\\/}/g" ${SERVICE_HOME}/environment
  sed -i -e "s/%NTP_DISABLED%/${NTP_DISABLED//\//\\/}/g" ${SERVICE_HOME}/environment
  FILES=`ls ${SRC_DIR}/systemd/*.sh`
  FILES="${FILES} `ls ${SRC_DIR}/systemd/server_*.py`"
  for f in ${FILES}
  do
    install -o root -g root -D -m 755 ${f} ${SERVICE_HOME}
  done

  cp -f ${SRC_DIR}/systemd/${SERVICE_NAME}.service.txt ${SRC_DIR}/systemd/${SERVICE_NAME}.service
  sed -i -e "s/%VERSION%/${VERSION//\//\\/}/g" ${SRC_DIR}/systemd/${SERVICE_NAME}.service

  install -o root -g root -D -m 644 ${SRC_DIR}/systemd/${SERVICE_NAME}.service ${LIB_SYSTEMD}/system/
  systemctl enable ${SERVICE_NAME}

  install -o root -g root -D -m 755 ${SRC_DIR}/uninstall.sh ${SERVICE_HOME}/uninstall.sh

  info "${SERVICE_NAME} service has been installed"
  REBOOT=1
}

function teardown {
  [ "${DEBUG}" ] || rm -fr ${SRC_DIR}
  if [ "${CONTAINER_MODE}" == "0" ] && [ "${REBOOT}" == "1" ]; then
    alert "*** Please reboot the system (enter 'sudo reboot') ***"
  fi
}

function package {
  rm -f $(basename ${GITHUB_ID})-*.tgz
  # http://unix.stackexchange.com/a/9865
  COPYFILE_DISABLE=1 tar --exclude="./.*" --exclude=Makefile -zcf $(basename ${GITHUB_ID})-${VERSION}.tgz *
}

# main
if [ "$1" == "pack" ]; then
  package
  exit 0
fi
assert_root
test_connectivity
ask_to_unistall_if_installed
setup
install_candy_board
install_candy_red
install_service
install_ppp
configure_sc16is7xx
teardown
