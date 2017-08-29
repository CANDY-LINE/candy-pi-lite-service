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

MODEM_BAUDRATE=${MODEM_BAUDRATE:-%MODEM_BAUDRATE%}
UART_PORT="/dev/ttySC1"
QWS_UC20_PORT="/dev/QWS.UC20.MODEM"
QWS_EC21_PORT="/dev/QWS.EC21.MODEM"
IF_NAME="${IF_NAME:-ppp0}"
DELAY_SEC=${DELAY_SEC:-1}

function assert_root {
  if [[ $EUID -ne 0 ]]; then
     echo "This script must be run as root"
     exit 1
  fi
}

function log {
  logger -t ${PRODUCT_DIR_NAME} $1
  if [ "${DEBUG}" ]; then
    echo ${PRODUCT_DIR_NAME} $1
  fi
}

function detect_usb_device {
  USB_SERIAL=`lsusb | grep "2c7c:0121"`
  if [ "$?" == "0" ]; then
    USB_SERIAL_PORT=${QWS_EC21_PORT}
  else
    USB_SERIAL=`lsusb | grep "05c6:9003"`
    if [ "$?" == "0" ]; then
      USB_SERIAL_PORT=${QWS_UC20_PORT}
    fi
  fi
  USB_SERIAL=""
}

function look_for_modem_port {
  MODEM_SERIAL_PORT=`/usr/bin/env python -c "import candy_board_qws; print(candy_board_qws.SerialPort.resolve_modem_port())"`
  if [ "${MODEM_SERIAL_PORT}" == "None" ]; then
    MODEM_SERIAL_PORT=""
    return
  elif [ -n "${USB_SERIAL_PORT}" ] && [ "${USB_SERIAL_PORT}" != "${MODEM_SERIAL_PORT}" ]; then
    MODEM_SERIAL_PORT=""
    return
  fi
  log "Serial port: ${MODEM_SERIAL_PORT} is selected"
}

function init_serialport {
  CURRENT_BAUDRATE="None"
  if [ -z "${MODEM_SERIAL_PORT}" ]; then
    look_for_modem_port
    if [ -z "${MODEM_SERIAL_PORT}" ]; then
      return
    fi
  fi
  if [ "${MODEM_INIT}" != "0" ]; then
    return
  fi
  if [ "${MODEM_SERIAL_PORT}" != "${UART_PORT}" ]; then
    if [ -e "${MODEM_SERIAL_PORT}" ]; then
      CURRENT_BAUDRATE=115200
      MODEM_INIT=1
      log "[INFO] Initialization Done. Modem Serial Port => ${MODEM_SERIAL_PORT}"
    else
      log "[ERROR] The path [${MODEM_SERIAL_PORT}] is missing"
      return
    fi
    return
  fi
  CURRENT_BAUDRATE=`/usr/bin/env python -c "import candy_board_qws; print(candy_board_qws.SerialPort.resolve_modem_baudrate('${UART_PORT}'))"`
  if [ "${CURRENT_BAUDRATE}" == "None" ]; then
    log "[ERROR] Modem is missing"
    return
  elif [ -n "${MODEM_BAUDRATE}" ]; then
    candy_command modem "{\"action\":\"init\",\"baudrate\":\"${MODEM_BAUDRATE}\"}"
    log "[INFO] Modem baudrate changed: ${CURRENT_BAUDRATE} => ${MODEM_BAUDRATE}"
    CURRENT_BAUDRATE=${MODEM_BAUDRATE}
  else
    candy_command modem init
  fi
  MODEM_INIT=1
  log "[INFO] Initialization Done. Modem Serial Port => ${MODEM_SERIAL_PORT} Modem baudrate => ${CURRENT_BAUDRATE}"
}

function candy_command {
  CURRENT_BAUDRATE=${CURRENT_BAUDRATE:-${MODEM_BAUDRATE:-115200}}
  RESULT=`/usr/bin/env python /opt/candy-line/${PRODUCT_DIR_NAME}/server_main.py $1 $2 ${MODEM_SERIAL_PORT} ${CURRENT_BAUDRATE} /var/run/candy-board-service.sock`
  RET=$?
}

function perst {
  # Make PERST_PIN low to reset module
  echo 0 > ${PERST_PIN}/value
  sleep 1
  # Make PERST_PIN high again
  echo 1 > ${PERST_PIN}/value
}

function wait_for_ppp_offline {
  RET=`ifconfig ${IF_NAME}`
  if [ "$?" != "0" ]; then
    return
  fi
  poff -a
  MAX=40
  COUNTER=0
  while [ ${COUNTER} -lt ${MAX} ];
  do
    RET=`ifconfig ${IF_NAME}`
    RET="$?"
    if [ "${RET}" != "0" ]; then
      break
    fi
    sleep 1
    let COUNTER=COUNTER+1
  done
  if [ "${RET}" == "0" ]; then
    log "[ERROR] PPP cannot be offline"
    exit 1
  fi
}

function wait_for_ppp_online {
  RET=`ip link show ${IF_NAME} | grep ${IF_NAME} | grep -v "state DOWN"`
  if [ "$?" == "0" ]; then
    return
  fi
  MAX=70
  COUNTER=0
  while [ ${COUNTER} -lt ${MAX} ];
  do
    RET=`ip link show ${IF_NAME} | grep ${IF_NAME} | grep -v "state DOWN"`
    RET="$?"
    if [ "${RET}" == "0" ]; then
      break
    fi
    sleep 1
    let COUNTER=COUNTER+1
  done
  if [ "${RET}" != "0" ]; then
    log "[ERROR] PPP cannot be online"
    return
  fi
}

function wait_for_serial_available {
  init_serialport
  if [ "${MODEM_INIT}" != "0" ]; then
    return
  fi
  MAX=40
  COUNTER=0
  while [ ${COUNTER} -lt ${MAX} ];
  do
    init_serialport
    if [ "${CURRENT_BAUDRATE}" != "None" ]; then
      break
    fi
    sleep 1
    let COUNTER=COUNTER+1
  done
  if [ "${MODEM_INIT}" == "0" ]; then
    log "[ERROR] No serialport is available"
    exit 1
  fi
}

function adjust_time {
  # init_modem must be performed prior to this function
  candy_command modem show
  MODEL=`/usr/bin/env python -c "import json;r=json.loads('${RESULT}');print(r['result']['model'])"`
  DATETIME=`/usr/bin/env python -c "import json;r=json.loads('${RESULT}');print(r['result']['datetime'])"`
  EPOCHTIME=`/usr/bin/env python -c "import datetime;print(int(datetime.datetime.strptime('${DATETIME}', '%y/%m/%d,%H:%M:%S').strftime('%s'))+${DELAY_SEC})"`
  date -s "@${EPOCHTIME}"
  log "[INFO] Module Model: ${MODEL}"
  log "[INFO] Adjusted the current time => ${DATETIME}"
}

function init_modem {
  MODEM_INIT=0
  detect_usb_device
  wait_for_ppp_offline
  perst
  wait_for_serial_available
  if [ "${MODEM_INIT}" == "0" ]; then
    exit 1
  fi
  adjust_time
}
