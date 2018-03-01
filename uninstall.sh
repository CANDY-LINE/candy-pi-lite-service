#!/usr/bin/env bash

# Copyright (c) 2018 CANDY LINE INC.
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
SERVICE_HOME=${VENDOR_HOME}/candy-pi-lite

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

function assert_root {
  if [[ $EUID -ne 0 ]]; then
     echo "This script must be run as root"
     exit 1
  fi
}

function setup {
  echo
}

function uninstall_ppp {
  RET=`which ufw`
  RET=$?
  if [ "${RET}" == "0" ]; then
    ufw --force disable
    ufw delete allow in on eth-rpi
    OUTPUT=`ufw --force reset`
    for f in `${echo $OUTPUT | grep -oP "/etc/ufw/[0-9a-zA-Z_\.]*"}`
    do
      rm -f ${f}
    done
  fi
  rm -f /etc/ppp/ipv6-up.d/000resolveconf_candy-pi-lite
}

function uninstall_candy_board {
  pip uninstall -y candy-board-qws
  pip uninstall -y candy-board-cli
}

function uninstall_service {
  RET=`systemctl | grep ${SERVICE_NAME}.service | grep running`
  RET=$?
  if [ "${RET}" == "0" ]; then
    systemctl stop ${SERVICE_NAME}
  fi
  systemctl disable ${SERVICE_NAME}

  LIB_SYSTEMD="$(dirname $(dirname $(which systemctl)))/lib/systemd"
  rm -f ${LIB_SYSTEMD}/system/${SERVICE_NAME}.service
  rm -f ${SERVICE_HOME}/environment
  rm -f ${SERVICE_HOME}/*.sh
  rm -f ${SERVICE_HOME}/*.py
  rm -f ${SERVICE_HOME}/*.pyc
  rm -f ${SERVICE_HOME}/*.json
  rm -f ${SERVICE_HOME}/__shutdown
  rm -f ${SERVICE_HOME}/__pppd_exit_code
  rm -f ${SERVICE_HOME}/*apn
  systemctl daemon-reload
  info "${SERVICE_NAME} has been uninstalled"
  REBOOT=1
}

function uninstall_udev_rules {
  rm -f /etc/udev/rules.d/70-enocean-stick.rules
  rm -f /etc/udev/rules.d/76-rpi-ether-netnames.rules
}

function teardown {
  [ "$(ls -A ${SERVICE_HOME})" ] || rmdir ${SERVICE_HOME}
  [ "$(ls -A ${VENDOR_HOME})" ] || rmdir ${VENDOR_HOME}
  if [ "${REBOOT}" == "1" ]; then
    alert "*** Please reboot the system! (enter 'sudo reboot') ***"
  fi
}

# main
assert_root
setup
uninstall_service
uninstall_candy_board
uninstall_ppp
uninstall_udev_rules
teardown
