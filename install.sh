#!/usr/bin/env bash

# Copyright (c) 2017 CANDY LINE INC.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

VENDOR_HOME=/opt/candy-line

SERVICE_NAME=candy-pi-lite
GITHUB_ID=CANDY-LINE/candy-pi-lite-service
VERSION=1.8.0
# Channel B
UART_PORT="/dev/ttySC1"
MODEM_BAUDRATE=${MODEM_BAUDRATE:-460800}

# v6 Maintenance LTS : April 2018 - April 2019
# v8 Active LTS Start on 2017-10-31, Maintenance LTS : April 2019 - December 2019
ARMv6_NODEJS_VERSION="6.12.0"
NODEJS_VERSIONS="v6"

SERVICE_HOME=${VENDOR_HOME}/${SERVICE_NAME}
SRC_DIR="${SRC_DIR:-/tmp/$(basename ${GITHUB_ID})-${VERSION}}"
CANDY_RED=${CANDY_RED:-1}
KERNEL="${KERNEL:-$(uname -r)}"
CONTAINER_MODE=0
if [ "${KERNEL}" != "$(uname -r)" ]; then
  CONTAINER_MODE=1
fi
if [ "${FORCE_INSTALL}" != "1" ]; then
  WELCOME_FLOW_URL=https://git.io/vKhk3
fi
PPP_PING_INTERVAL_SEC=${PPP_PING_INTERVAL_SEC:-0}
NTP_DISABLED=${NTP_DISABLED:-1}
PPPD_DEBUG=${PPPD_DEBUG:-""}
CHAT_VERBOSE=${CHAT_VERBOSE:-""}
RESTART_SCHEDULE_CRON=${RESTART_SCHEDULE_CRON:-""}
CONFIGURE_STATIC_IP_ON_BOOT=${CONFIGURE_STATIC_IP_ON_BOOT:-""}
OFFLINE_PERIOD_SEC=${OFFLINE_PERIOD_SEC:-30}
ENABLE_WATCHDOG=${ENABLE_WATCHDOG:-1}
COFIGURE_ENOCEAN_PORT=${COFIGURE_ENOCEAN_PORT:-1}
CANDY_PI_LITE_APT_GET_UPDATED=${CANDY_PI_LITE_APT_GET_UPDATED:-0}
CANDY_RED_BIND_IPV4_ADDR=${CANDY_RED_BIND_IPV4_ADDR:-false}
DISABLE_DEFAULT_ROUTE_ADJUSTER=${DISABLE_DEFAULT_ROUTE_ADJUSTER:-0}

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
  python -c "import RPi.GPIO" > /dev/null 2>&1
  if [ "$?" == "0" ]; then
    BOARD="RPi"
  else
    DT_MODEL=`cat /proc/device-tree/model 2>&1 | sed '/\x00/d'`
    case ${DT_MODEL} in
      "Tinker Board")
        BOARD="ATB"
        ;;
      *)
        BOARD=""
        ;;
    esac
  fi
}

function assert_root {
  if [[ $EUID -ne 0 ]]; then
     alert "This script must be run as root"
     exit 1
  fi
}

function fix_perm_issues {
  ETC_DEFAULT_PERMS=`namei -m /etc/default 2>&1`
  if [[ ! ${ETC_DEFAULT_PERMS} == *"drwxr-xr-x etc"* ]]; then
    chmod 755 /etc
  fi
  if [[ ! ${ETC_DEFAULT_PERMS} == *"drwxr-xr-x default"* ]]; then
    chmod 755 /etc/default
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
    alert "Please uninstall candy-pi-lite-service first by 'sudo ${SERVICE_HOME}/uninstall.sh'"
    exit 1
  fi
  if [ -f "${VENDOR_HOME}/ltepi2/environment" ]; then
    alert "Please uninstall ltepi2-service first by 'sudo ${VENDOR_HOME}/ltepi2/uninstall.sh'"
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
  cp -f ${SRC_DIR}/etc/ufw/*.rules /etc/ufw/
  if [ "${FORCE_INSTALL}" != "1" ]; then
    ufw --force disable
    if [ "${BOARD}" == "RPi" ]; then
      if [ ! -e "/sys/class/net/eth0" ]; then
        if [ "${CONFIGURE_STATIC_IP_ON_BOOT}" == "1" ]; then
          ufw allow in on eth-rpi
        fi
      fi
    fi
    for n in `ls /sys/class/net`
    do
      if [ "${n}" != "lo" ] && [ "${n}" != "ppp0" ] && [ "${n}" != "wwan0" ]; then
        ufw allow in on ${n}
        if [ "$?" != "0" ]; then
          err "Failed to configure ufw for the network interface: ${n}"
          exit 4
        fi
      fi
    done
    ufw --force enable
  fi
}

function configure_sc16is7xx {
  if [ "${FORCE_INSTALL}" != "1" ]; then
    if [ -z "${BOARD}" ]; then
      return
    fi
  fi
  info "Configuring SC16IS7xx..."
  case ${BOARD} in
    RPi)
      do_configure_sc16is7xx_rpi
      ;;
    ATB)
      do_configure_sc16is7xx_atb
      ;;
    *)
      err "Unsupported board: ${BOARD}"
      exit 5
      ;;
  esac
  info "SC16IS7xx configuration done"
}

function do_configure_sc16is7xx_rpi {
  SC16IS7xx_DT_NAME="sc16is752-spi0-ce1"
  SC16IS7xx_DTB="/boot/overlays/${SC16IS7xx_DT_NAME}.dtbo"
  if [ ! -f "${SC16IS7xx_DTB}" ]; then
    info "Installing SC16IS7xx Device Tree Blob..."
    dtc -@ -I dts -O dtb -o ${SC16IS7xx_DTB} ${SRC_DIR}/boot/overlays/${SC16IS7xx_DT_NAME}.dts
  fi

  RET=`grep "^dtoverlay=${SC16IS7xx_DT_NAME}" /boot/config.txt`
  if [ "$?" != "0" ]; then
    if [ ! -f "/boot/config.txt.bak" ]; then
      cp /boot/config.txt /boot/config.txt.bak
    fi
    echo "dtoverlay=${SC16IS7xx_DT_NAME}" >> /boot/config.txt
  fi
}

function do_configure_sc16is7xx_atb {
  RET=`grep "sc16is7xx.ko" /lib/modules/$(uname -r)/modules.dep`
  if [ "$?" != "0" ]; then
    info "Installing SC16IS7xx Kernel Module..."
    mkdir -p /lib/modules/$(uname -r)/kernel/drivers/tty/serial/
    cp -f ${SRC_DIR}/lib/modules/4.4.71+/kernel/drivers/tty/serial/sc16is7xx.ko \
      /lib/modules/$(uname -r)/kernel/drivers/tty/serial/
    depmod -a
  fi

  SC16IS7xx_DT_NAME="sc16is752-spi2-ce1-atb"
  SC16IS7xx_DTB="/boot/overlays/${SC16IS7xx_DT_NAME}.dtbo"
  if [ ! -f "${SC16IS7xx_DTB}" ]; then
    info "Installing SC16IS7xx Device Tree Blob..."
    cp -f ${SRC_DIR}/boot/overlays/${SC16IS7xx_DT_NAME}.dtbo ${SC16IS7xx_DTB}
  fi

  RET=`grep "^intf:dtoverlay=${SC16IS7xx_DT_NAME}" /boot/hw_intf.conf`
  if [ "$?" != "0" ]; then
    if [ ! -f "/boot/hw_intf.conf.bak" ]; then
      cp /boot/hw_intf.conf /boot/hw_intf.conf.bak
    fi
    echo "intf:dtoverlay=${SC16IS7xx_DT_NAME}" >> /boot/hw_intf.conf
  fi
}

function configure_watchdog {
  if [ "${FORCE_INSTALL}" != "1" ]; then
    if [ -z "${BOARD}" ]; then
      return
    fi
  fi
  if [ "${ENABLE_WATCHDOG}" != "1" ]; then
    return
  fi
  info "Configuring Hardware Watchdog..."
  case ${BOARD} in
    RPi)
      if [ "${FORCE_INSTALL}" != "1" ]; then
        RET=`modprobe bcm2835_wdt`
        if [ "$?" != "0" ]; then
          info "bcm2835_wdt is missing. Skip to configue Hardware Watchdog."
          return
        fi
      fi
      do_configure_bcm2835_wdt
      ;;
    ATB)
      info "Hardware Watchdog isn't yet supported on ASUS Tinker Board."
      return
      ;;
    *)
      err "Unsupported board: ${BOARD}"
      exit 5
      ;;
  esac
  info "Hardware Watchdog configuration done"
}

function do_configure_bcm2835_wdt {
  RET=`grep "^dtparam=watchdog=on" /boot/config.txt`
  if [ "$?" != "0" ]; then
    RET=`grep "^dtparam=watchdog=off" /boot/config.txt`
    if [ "$?" != "0" ]; then
      echo "dtparam=watchdog=on" >> /boot/config.txt
    else
      info "Skip to configure Hardware Watchdog as it's already disabled."
      return
    fi
  fi
  if [ ! -f "/etc/modprobe.d/bcm2835-wdt.conf" ]; then
    echo "options bcm2835_wdt heartbeat=14 nowayout=0" >> /etc/modprobe.d/bcm2835-wdt.conf
  fi
  if [ -f "/etc/systemd/system.conf" ]; then
    RET=`grep "^RuntimeWatchdogSec=" /etc/systemd/system.conf`
    if [ "$?" != "0" ]; then
      RET=`grep "^#RuntimeWatchdogSec=" /etc/systemd/system.conf`
      if [ "$?" != "0" ]; then
        echo "RuntimeWatchdogSec=14" >> /etc/systemd/system.conf
      else
        sed -i -e "s/#RuntimeWatchdogSec=.*/RuntimeWatchdogSec=14/g" /etc/systemd/system.conf
        rm -f /etc/systemd/system.conf-e
      fi
    fi
  fi
}

function apt_get_update {
  if [ "${CANDY_PI_LITE_APT_GET_UPDATED}" == "1" ]; then
    return
  fi
  CANDY_PI_LITE_APT_GET_UPDATED=1
  apt-get update -y
}

function install_ppp {
  info "Installing ufw and ppp..."
  if [ "${FORCE_INSTALL}" != "1" ]; then
    apt_get_update
    apt-get install -y ufw ppp
  fi

  # _common.sh is copied by install_service
  cp -f ${SRC_DIR}/systemd/apn-list.json ${SERVICE_HOME}/apn-list.json
  port="${UART_PORT}"
  sed -i -e "s/%MODEM_BAUDRATE%/${MODEM_BAUDRATE//\//\\/}/g" ${SERVICE_HOME}/_common.sh

  _ufw_setup
}

function install_avahi_daemon {
  if [ "${FORCE_INSTALL}" != "1" ]; then
    systemctl status avahi-daemon > /dev/null 2>&1
    if [ "$?" != "0" ]; then
      info "Installing avahi daemon..."
      apt_get_update
      apt-get install -y avahi-daemon
    fi
  fi
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
  pip install --upgrade croniter
}

function install_candy_red {
  if [ "${CANDY_RED}" == "0" ]; then
    return
  fi
  if [ "${FORCE_INSTALL}" != "1" ]; then
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
    apt_get_update
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
        wget https://nodejs.org/dist/v${ARMv6_NODEJS_VERSION}/node-v${ARMv6_NODEJS_VERSION}-linux-armv6l.tar.gz
        tar zxf node-v${ARMv6_NODEJS_VERSION}-linux-armv6l.tar.gz
        cd node-v${ARMv6_NODEJS_VERSION}-linux-armv6l/
        cp -R * /usr/local/
      else
        curl -sL https://deb.nodesource.com/setup_6.x | sudo bash -
        apt-get install -y nodejs
      fi
    fi
    info "Installing dependencies..."
    apt-get install -y python-dev bluez libudev-dev
    if [ "${BOARD}" == "RPi" ]; then
      apt-get install -y python-rpi.gpio
    fi
  fi
  cd ~
  npm cache clean
  info "Installing CANDY RED..."
  if [ "${BOARD}" == "ATB" ]; then
    CANDY_RED_BIND_IPV4_ADDR=true
  fi
  WELCOME_FLOW_URL=${WELCOME_FLOW_URL} \
    NODES_CSV_PATH=${NODES_CSV_PATH} \
    CANDY_RED_APT_GET_UPDATED=${CANDY_PI_LITE_APT_GET_UPDATED} \
    CANDY_RED_BIND_IPV4_ADDR=${CANDY_RED_BIND_IPV4_ADDR} \
    npm install -g --unsafe-perm candy-red
  REBOOT=1
  CANDY_PI_LITE_APT_GET_UPDATED=1
}

function test_boot_apn {
  FALLBACK_APN=$(cat ${SRC_DIR}/systemd/fallback_apn)
  BOOT_APN=${BOOT_APN:-${FALLBACK_APN}}
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
  cp -f ${SRC_DIR}/systemd/fallback_apn ${SERVICE_HOME}

  for e in VERSION \
      DISABLE_DEFAULT_ROUTE_ADJUSTER \
      PPP_PING_INTERVAL_SEC \
      NTP_DISABLED \
      PPPD_DEBUG \
      CHAT_VERBOSE \
      RESTART_SCHEDULE_CRON \
      OFFLINE_PERIOD_SEC; do
    sed -i -e "s/%${e}%/${!e//\//\\/}/g" ${SERVICE_HOME}/environment
  done
  FILES=`ls ${SRC_DIR}/systemd/*.sh`
  FILES="${FILES} `ls ${SRC_DIR}/systemd/server_*.py`"
  for f in ${FILES}
  do
    install -o root -g root -D -m 755 ${f} ${SERVICE_HOME}
  done

  echo "${BOOT_APN}" > ${SERVICE_HOME}/apn

  cp -f ${SRC_DIR}/systemd/${SERVICE_NAME}.service.txt ${SRC_DIR}/systemd/${SERVICE_NAME}.service
  sed -i -e "s/%VERSION%/${VERSION//\//\\/}/g" ${SRC_DIR}/systemd/${SERVICE_NAME}.service

  install -o root -g root -D -m 644 ${SRC_DIR}/systemd/${SERVICE_NAME}.service ${LIB_SYSTEMD}/system/
  systemctl enable ${SERVICE_NAME}

  install -o root -g root -D -m 755 ${SRC_DIR}/uninstall.sh ${SERVICE_HOME}/uninstall.sh

  cp -f ${SRC_DIR}/etc/udev/rules.d/99* /etc/udev/rules.d/
  if [ "${BOARD}" == "RPi" ]; then
    if [ ! -e "/sys/class/net/eth0" ]; then
      if [ "${CONFIGURE_STATIC_IP_ON_BOOT}" == "1" ]; then
        # assign the fixed name `eth-rpi` for RPi B+/2B/3B
        cp -f ${SRC_DIR}/etc/udev/rules.d/76-rpi-ether-netnames.rules /etc/udev/rules.d/
      fi
    fi
  fi
  if [ "${COFIGURE_ENOCEAN_PORT}" == "1" ]; then
    cp -f ${SRC_DIR}/etc/udev/rules.d/70-enocean-stick.rules /etc/udev/rules.d/
  fi

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
fix_perm_issues
install_candy_board
install_candy_red
install_service
install_ppp
install_avahi_daemon
configure_sc16is7xx
configure_watchdog
teardown
