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

PRODUCT="CANDY Pi Lite Board"
PRODUCT_DIR_NAME="candy-pi-lite"
SHUDOWN_STATE_FILE="/opt/candy-line/${PRODUCT_DIR_NAME}/__shutdown"

function init {
  . /opt/candy-line/${PRODUCT_DIR_NAME}/_common.sh > /dev/null 2>&1
  if [ -e "${UART_PORT}" ] || [ -e "${QWS_UC20_PORT}" ] || [ -e "${QWS_EC21_PORT}" ] || [ -e "${QWS_EC25_PORT}" ]; then
    . /opt/candy-line/${PRODUCT_DIR_NAME}/_pin_settings.sh > /dev/null 2>&1
    export LED2
  else
    log "[ERROR] Modem is missing"
    exit 11
  fi
}

function stop_server_main {
  rm -f ${SHUDOWN_STATE_FILE}
  if [ ! -f "${PIDFILE}" ]; then
    return
  fi
  PID=`cat ${PIDFILE}`
  rm -f ${PIDFILE}
  MAX=40
  COUNTER=0
  while [ ${COUNTER} -lt ${MAX} ];
  do
    RET=`ps ${PID}`
    if [ "$?" != "0" ]; then
      return
    fi
    sleep 1
    let COUNTER=COUNTER+1
  done
  kill -9 ${PID}
  rm -f "${PIDFILE}"
  log "[WARN] Forcedly stopped server_main module"
}

function led_off {
  echo 0 > ${LED2_PIN}/value
}

touch ${SHUDOWN_STATE_FILE}
init

# start banner
log "[INFO] Inactivating ${PRODUCT}..."

poff -a > /dev/null 2>&1
stop_server_main
led_off
systemctl --no-block restart dhcpcd
if [ "${NTP_DISABLED}" == "1" ]; then
  start_ntp
fi

# end banner
log "[INFO] ${PRODUCT} is inactivated successfully!"
