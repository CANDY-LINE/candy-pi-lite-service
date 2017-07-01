#!/usr/bin/env bash

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

function uninstall_ppp {
  PPP_MODE_DETECTED=0
  for f in "/etc/chatscripts/candy-pi-lite" "/etc/ppp/peers/candy-pi-lite"
  do
    if [ -f "${f}" ]; then
      rm -f "${f}"
      PPP_MODE_DETECTED=1
    fi
  done
  if [ "${PPP_MODE_DETECTED}" == "0" ]; then
    return
  fi

  RET=`which ufw`
  RET=$?
  if [ "${RET}" == "0" ]; then
    ufw --force disable
    OUTPUT=`ufw --force reset`
    for f in `${echo $OUTPUT | grep -oP "/etc/ufw/[0-9a-zA-Z_\.]*"}`
    do
      rm -f ${f}
    done
  fi
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
  rm -f /etc/chatscripts/candy-pi-lite-*
  rm -f /etc/ppp/peers/candy-pi-lite*
  systemctl daemon-reload
  info "${SERVICE_NAME} has been uninstalled"
  REBOOT=1
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
uninstall_service
uninstall_candy_board
uninstall_ppp
teardown
