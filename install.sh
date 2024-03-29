#!/usr/bin/env bash

# Copyright (c) 2019 CANDY LINE INC.
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
VERSION=10.4.0
# Channel B
UART_PORT="/dev/ttySC1"
MODEM_BAUDRATE=${MODEM_BAUDRATE:-460800}

# v12 Active LTS Start on 2019-10-22, Maintenance LTS : November 2020   - April 2022
# v14 Active LTS Start on 2020-10-27, Maintenance LTS : October 2021   - April 2023
ARM_NODEJS_VERSION="12.22.6"
NODEJS_VERSIONS="v12"

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
PPP_PING_TYPE=${PPP_PING_TYPE:-NONE}
PPP_PING_DESTINATION=${PPP_PING_DESTINATION:-"1.1.1.1"}
PPP_PING_IP_VERSION=${PPP_PING_IP_VERSION:-4}
PPP_PING_OFFLINE_THRESHOLD=${PPP_PING_OFFLINE_THRESHOLD:-30}
PPP_PING_RESTART_IF_OFFLINE=${PPP_PING_RESTART_IF_OFFLINE:-0}
NTP_DISABLED=${NTP_DISABLED:-1}
PPPD_DEBUG=${PPPD_DEBUG:-""}
CHAT_VERBOSE=${CHAT_VERBOSE:-""}
RESTART_SCHEDULE_CRON=${RESTART_SCHEDULE_CRON:-""}
CONFIGURE_STATIC_IP_ON_BOOT=${CONFIGURE_STATIC_IP_ON_BOOT:-""}
OFFLINE_PERIOD_SEC=${OFFLINE_PERIOD_SEC:-5}
ENABLE_WATCHDOG=${ENABLE_WATCHDOG:-1}
COFIGURE_ENOCEAN_PORT=${COFIGURE_ENOCEAN_PORT:-1}
CANDY_PI_LITE_APT_GET_UPDATED=${CANDY_PI_LITE_APT_GET_UPDATED:-0}
CANDY_RED_BIND_IPV4_ADDR=${CANDY_RED_BIND_IPV4_ADDR:-false}
DISABLE_DEFAULT_ROUTE_ADJUSTER=${DISABLE_DEFAULT_ROUTE_ADJUSTER:-0}
SERIAL_PORT_TYPE=${SERIAL_PORT_TYPE:-auto}
COFIGURE_SMARTMESH_PORT=${COFIGURE_SMARTMESH_PORT:-1}
CONNECT_ON_STARTUP=${CONNECT_ON_STARTUP:-1}
GNSS_ON_STARTUP=${GNSS_ON_STARTUP:-0}
SLEEP_SEC_BEFORE_RETRY=${SLEEP_SEC_BEFORE_RETRY:-30}
PYTHON=""
PKGS="candy-board-qws==3.1.0 candy-board-cli==4.0.0 croniter"
BUTTON_EXT=${BUTTON_EXT:-0}
RPi_BUTTON_LED=${RPi_BUTTON_LED:-17}
RPi_BUTTON_IN=${RPi_BUTTON_IN:-27}
ATB_BUTTON_LED=${ATB_BUTTON_LED:-164}
ATB_BUTTON_IN=${ATB_BUTTON_IN:-166}

ALERT_MESSAGE=""

REBOOT=0

function err {
  echo -e "\033[91m[ERROR] $1\033[0m"
}

function warn {
  echo -e "\033[95m[WARN] $1\033[0m"
}

function info {
  echo -e "\033[92m[INFO] $1\033[0m"
}

function alert {
  echo -e "\033[93m[ALERT] $1\033[0m"
}

function setup {
  [ "${DEBUG}" ] || rm -fr ${SRC_DIR}
  info "Installing CANDY Pi Lite Board Service software Version: ${VERSION}"
  info "OS Version: $(cat /etc/debian_version)"
  info "Kernel Version: ${KERNEL}"
  info "Architecture: $(uname -m)"
  RET=`which python3`
  RET=$?
  if [ "${RET}" == "0" ]; then
    info "Using 'python3' command for Python scripts."
    PYTHON="python3"
  else
    info "Using 'python' command for Python scripts."
    PYTHON="python"
  fi
  if [ -z "${BOARD}" ]; then
    DT_MODEL=""
    if [ -f "/proc/board_info" ]; then
      DT_MODEL=`tr -d '\0' < /proc/board_info`
    elif [ -f "/proc/device-tree/model" ]; then
      DT_MODEL=`tr -d '\0' < /proc/device-tree/model`
    fi
    case ${DT_MODEL} in
      "Tinker Board" | "Tinker Board S" | "Rockchip RK3288 Tinker Board")
        BOARD="ATB"
        ;;
      *)
        BOARD=""
        ;;
    esac
    if [ -z "${BOARD}" ]; then
      grep "Raspberry Pi " /proc/device-tree/model > /dev/null
      if [ "$?" == "0" ]; then
        BOARD="RPi"
      else
        BOARD="/proc/device-tree/model => $(tr -d '\0' < /proc/device-tree/model)"
      fi
    fi
  fi
  case ${BOARD} in
    RPi|ATB)
      info "Board Type: ${BOARD}"
      ;;
    *)
      err "Unsupported board: ${BOARD}"
      exit 5
      ;;
  esac
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
  if [ -x "${SERVICE_HOME}/uninstall.sh" ]; then
    alert "Please uninstall candy-pi-lite-service first by 'sudo ${SERVICE_HOME}/uninstall.sh'"
    exit 1
  fi
  if [ -x "${VENDOR_HOME}/ltepi2/uninstall.sh" ]; then
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
  if [ "${FORCE_INSTALL}" == "1" ]; then
    sed -i -e "s/ENABLED=no/ENABLED=yes/g" /etc/ufw/ufw.conf
  else
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
  info "Configuring SC16IS7xx for ${BOARD} ..."
  case ${BOARD} in
    RPi)
      do_configure_sc16is7xx_rpi
      ;;
    ATB)
      do_configure_sc16is7xx_atb
      ;;
  esac
  info "SC16IS7xx configuration done"
}

function do_configure_sc16is7xx_rpi {
  SC16IS7xx_DT_NAME="sc16is752-spi0-ce1"
  SC16IS7xx_DTB="/boot/overlays/${SC16IS7xx_DT_NAME}.dtbo"
  info "Installing SC16IS7xx Device Tree Blob..."
  dtc -@ -I dts -O dtb -o ${SC16IS7xx_DTB} ${SRC_DIR}/boot/overlays/${SC16IS7xx_DT_NAME}.dts

  RET=`grep "^dtoverlay=${SC16IS7xx_DT_NAME}" /boot/config.txt`
  if [ "$?" != "0" ]; then
    if [ ! -f "/boot/config.txt.bak" ]; then
      cp /boot/config.txt /boot/config.txt.bak
    fi
    echo "dtoverlay=${SC16IS7xx_DT_NAME}" >> /boot/config.txt
  fi
}

function do_configure_sc16is7xx_atb {
  RET=`grep "sc16is7xx.ko" /lib/modules/${KERNEL}/modules.dep`
  if [ "$?" != "0" ]; then
    info "Installing SC16IS7xx Kernel Module...(Kernel Version:${KERNEL})"
    KO_FILE_PATH="${SRC_DIR}/lib/modules/${KERNEL}/kernel/drivers/tty/serial/sc16is7xx.ko"
    if [ -f "${KO_FILE_PATH}" ]; then
      mkdir -p /lib/modules/${KERNEL}/kernel/drivers/tty/serial/
      cp -f ${KO_FILE_PATH} /lib/modules/${KERNEL}/kernel/drivers/tty/serial/
      depmod -a
    else
      ALERT_MESSAGE="GPIO(SPI) connection is NOT AVAILABLE because the kernel version:${KERNEL} is unsupported. Use USB/UART connection, instead."
      warn "Cannot install SC16IS7xx Kernel Module. GPIO(SPI) is NOT Available."
      warn "Don't warry. You can use USB/UART, instead."
      info "Skip to install Device Tree Blob."
      return
    fi
  fi

  SC16IS7xx_DT_NAME="sc16is752-spi2-ce1-atb"
  SC16IS7xx_DTB="/boot/overlays/${SC16IS7xx_DT_NAME}.dtbo"
  info "Installing SC16IS7xx Device Tree Blob..."
  cp -f ${SRC_DIR}/boot/overlays/${SC16IS7xx_DT_NAME}.dtbo ${SC16IS7xx_DTB}

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
  info "Configuring Hardware Watchdog for ${BOARD} ..."
  case ${BOARD} in
    RPi)
      if [ "${FORCE_INSTALL}" != "1" ]; then
        test_wdt_driver bcm2835_wdt
        if [ "$RET" != "0" ]; then
          return
        fi
      fi
      do_configure_bcm2835_wdt
      ;;
    ATB)
      if [ "${FORCE_INSTALL}" != "1" ]; then
        test_wdt_driver dw_wdt
        if [ "$RET" != "0" ]; then
          return
        fi
      fi
      do_configure_dw_wdt
      ;;
  esac
  info "Hardware Watchdog configuration done"
}

function test_wdt_driver {
  RET=`modprobe $1`
  if [ "$?" != "0" ]; then
    info "$1 is missing. Skip to configue Hardware Watchdog."
    RET=1
    return
  fi
  RET=0
}

function do_configure_watchdog {
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
  do_configure_watchdog
}

function do_configure_dw_wdt {
  if [ ! -f "/etc/modprobe.d/dw-wdt.conf" ]; then
    echo "options dw_wdt nowayout=0" >> /etc/modprobe.d/dw-wdt.conf
  fi
  do_configure_watchdog
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

  FILES=`ls ${SRC_DIR}/etc/ppp/ipv6-up.d/0*`
  for f in ${FILES}
  do
    install -o root -g root -D -m 755 ${f} /etc/ppp/ipv6-up.d/
  done
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

function install_logrotate {
  if [ "${FORCE_INSTALL}" != "1" ]; then
    dpkg -l | grep logrotate > /dev/null 2>&1
    if [ "$?" != "0" ]; then
      info "Installing logrotate..."
      apt_get_update
      apt-get install -y logrotate
    fi
  fi
}

function install_candy_board {
  PIP="${PYTHON} -m pip"
  PIP_VERSION=`${PIP} -V`
  RET=$?
  if [ "${RET}" == "0" ]; then
    info "Using ${PIP_VERSION}"
  else
    info "Installing pip..."
    apt_get_update
    apt-get install -y ${PYTHON}-pip
    info "Installed `${PIP} -V`"
  fi

  SETUPTOOLS=`${PYTHON} -c "import setuptools" > /dev/null 2>&1`
  RET=$?
  if [ "${RET}" != "0" ]; then
    info "Installing setuptools..."
    apt_get_update
    apt-get install -y ${PYTHON}-setuptools ${PYTHON}-wheel
    info "Installed setuptools"
  fi

  for p in ${PKGS}
  do
    ${PIP} install --upgrade ${p}
  done
}

function install_candy_red {
  if [ "${CANDY_RED}" == "0" ]; then
    return
  fi
  BINARY_UPDATE_REQUIRED=`systemctl is-enabled candy-red`
  if [ "$?" == "0" ]; then
    BINARY_UPDATE_REQUIRED="yes"
    systemctl stop candy-red
  else
    BINARY_UPDATE_REQUIRED="no"
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
        MODEL_NAME=`uname -m`
        if [ "$?" != "0" ]; then
          alert "Cannot Resolve CPU Architecture."
          exit 1
        fi
      fi
      apt-get remove -y nodered nodejs nodejs-legacy npm
      rm -f \
        /usr/bin/node \
        /usr/bin/npm \
        /usr/sbin/node \
        /usr/sbin/npm \
        /usr/local/bin/node \
        /usr/local/bin/npm
      if [[ ${MODEL_NAME} = *"ARMv6 "* || ${MODEL_NAME} = *"ARMv6-"* ]]; then
        ARM_ARCH_VERSION=armv6l
        NODEJS_BASE_URL=https://unofficial-builds.nodejs.org/download/release/v
      elif [[ ${MODEL_NAME} = *"ARMv7 "* || ${MODEL_NAME} = *"ARMv7-"* || ${MODEL_NAME} = *"ARMv8 "* || ${MODEL_NAME} = *"ARMv8-"* ]]; then
        ARM_ARCH_VERSION=${ARM_ARCH:-armv7l}
        NODEJS_BASE_URL=https://nodejs.org/dist/v
      elif [[ ${MODEL_NAME} = *"aarch64"* ]]; then
        ARM_ARCH_VERSION=${ARM_ARCH:-arm64}
        NODEJS_BASE_URL=https://nodejs.org/dist/v
     else
        alert "Unsupported architecture. Detected text:${MODEL_NAME}"
        exit 1
      fi
      cd /tmp
      wget ${NODEJS_BASE_URL}${ARM_NODEJS_VERSION}/node-v${ARM_NODEJS_VERSION}-linux-${ARM_ARCH_VERSION}.tar.gz
      if [ "$?" != "0" ]; then
        alert "Failed to download a tarball from '${NODEJS_BASE_URL}${ARM_NODEJS_VERSION}/node-v${ARM_NODEJS_VERSION}-linux-${ARM_ARCH_VERSION}.tar.gz'"
        exit 1
      fi
      tar zxf node-v${ARM_NODEJS_VERSION}-linux-${ARM_ARCH_VERSION}.tar.gz
      cd node-v${ARM_NODEJS_VERSION}-linux-${ARM_ARCH_VERSION}/
      cp -R * /usr/
      rm -f /usr/CHANGELOG.md /usr/LICENSE /usr/README.md
    fi
  fi
  cd ~
  npm cache clean --force
  info "Installing CANDY RED..."
  if [ "${BOARD}" == "ATB" ]; then
    CANDY_RED_BIND_IPV4_ADDR=true
  fi
  WELCOME_FLOW_URL=${WELCOME_FLOW_URL} \
    NODES_CSV_PATH=${NODES_CSV_PATH} \
    CANDY_RED_APT_GET_UPDATED=${CANDY_PI_LITE_APT_GET_UPDATED} \
    CANDY_RED_BIND_IPV4_ADDR=${CANDY_RED_BIND_IPV4_ADDR} \
    npm install -g --unsafe-perm --production candy-red
  RET="$?"
  if [ "${RET}" != "0" ]; then
    err "Failed to install CANDY RED"
    if [ "${BOARD}" == "RPi" ]; then
      err "Consider to use the presinstalled OS image at https://forums.candy-line.io/tags/os, instead."
    fi
    exit ${RET}
  fi
  if [ "${BINARY_UPDATE_REQUIRED}" == "yes" ]; then
    info "Updating Binaries..."
    pushd $(npm -g root)/candy-red
    npm --unsafe-perm rebuild --update-binary
    popd
    pushd /opt/candy-red/.node-red
    npm --unsafe-perm rebuild --update-binary
    popd
    info "All binaries are updated."
  fi
  REBOOT=1
  CANDY_PI_LITE_APT_GET_UPDATED=1
}

function test_boot_apn {
  FALLBACK_APN=$(cat ${SRC_DIR}/systemd/fallback_apn)
  BOOT_APN=${BOOT_APN:-${FALLBACK_APN}}
  CREDS=`/usr/bin/env ${PYTHON} -c "with open('${SRC_DIR}/systemd/apn-list.json') as f:import json;c=json.load(f);print('${BOOT_APN}' in c)"`
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
      PYTHON \
      BUTTON_EXT \
      RPi_BUTTON_LED \
      RPi_BUTTON_IN \
      ATB_BUTTON_LED \
      ATB_BUTTON_IN \
      SERIAL_PORT_TYPE \
      DISABLE_DEFAULT_ROUTE_ADJUSTER \
      PPP_PING_INTERVAL_SEC \
      PPP_PING_TYPE \
      PPP_PING_DESTINATION \
      PPP_PING_IP_VERSION \
      PPP_PING_OFFLINE_THRESHOLD \
      PPP_PING_RESTART_IF_OFFLINE \
      NTP_DISABLED \
      PPPD_DEBUG \
      CHAT_VERBOSE \
      RESTART_SCHEDULE_CRON \
      CONNECT_ON_STARTUP \
      GNSS_ON_STARTUP \
      SLEEP_SEC_BEFORE_RETRY \
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
  if [ "${COFIGURE_SMARTMESH_PORT}" == "1" ]; then
    cp -f ${SRC_DIR}/etc/udev/rules.d/70-smartmesh.rules /etc/udev/rules.d/
  fi

  info "${SERVICE_NAME} service has been installed"
  REBOOT=1
}

function teardown {
  [ "${DEBUG}" ] || rm -fr ${SRC_DIR}
  if [ "${CONTAINER_MODE}" == "0" ] && [ "${REBOOT}" == "1" ]; then
    alert "*** Please reboot the system (enter 'sudo reboot') ***"
  fi
  if [ -n "${ALERT_MESSAGE}" ]; then
    alert "${ALERT_MESSAGE}"
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
install_logrotate
configure_sc16is7xx
configure_watchdog
teardown
