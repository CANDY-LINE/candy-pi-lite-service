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

MODEM_SERIAL_PORT=${MODEM_SERIAL_PORT:-%MODEM_SERIAL_PORT%}
MODEM_BAUDRATE=${MODEM_BAUDRATE:-%MODEM_BAUDRATE%}
UART_PORT="/dev/ttySC1"
QWS_UC20_PORT="/dev/QWS.UC20.AT"
QWS_EC21_PORT="/dev/QWS.EC21.AT"
IF_NAME="${IF_NAME:-ppp0}"

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

function look_for_modem_port {
  MODEM_SERIAL_PORT=`/usr/bin/env python -c "import candy_board_qws; print(candy_board_qws.SerialPort.resolve_modem_port())"`
  if [ "${MODEM_SERIAL_PORT}" == "None" ]; then
    if [ -e "${UART_PORT}" ]; then
      log "[INFO] Trying to adjust baudrate"
      CURRENT_BAUDRATE=`/usr/bin/env python -c "import candy_board_qws; print(candy_board_qws.SerialPort.resolve_modem_baudrate('${UART_PORT}'))"`
      if [ "${CURRENT_BAUDRATE}" != "None" ]; then
        MODEM_SERIAL_PORT=${UART_PORT}
      else
        log "[ERROR] Serial port is missing, good-bye"
        exit 10
      fi
    else
      log "[ERROR] Serial port is missing, bye"
      exit 10
    fi
  else
    log "Serial port: ${MODEM_SERIAL_PORT} is selected"
  fi
}

function init_serialport {
  if [ "${MODEM_SERIAL_PORT}" != "${UART_PORT}" ]; then
    return
  fi
  CURRENT_BAUDRATE=`/usr/bin/env python -c "import candy_board_qws; print(candy_board_qws.SerialPort.resolve_modem_baudrate('${UART_PORT}'))"`
  if [ "${CURRENT_BAUDRATE}" == "None" ]; then
    log "[ERROR] Modem is missing, bye"
    exit 1
  elif [ -n "${MODEM_BAUDRATE}" ]; then
    candy_command modem "{\"action\":\"init\",\"baudrate\":\"${MODEM_BAUDRATE}\"}"
    log "[INFO] Modem baudrate changed: ${CURRENT_BAUDRATE} => ${MODEM_BAUDRATE}"
    CURRENT_BAUDRATE=${MODEM_BAUDRATE}
  else
    candy_command modem init
  fi
  log "[INFO] Modem baudrate => ${CURRENT_BAUDRATE}"
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
  poff
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

function _adjust_time {
  # init_modem must be performed prior to this function
  DATETIME=`/usr/bin/env python -c "import json;r=json.loads('${RESULT}');print(r['result']['datetime'])"`
  EPOCHTIME=`/usr/bin/env python -c "import datetime;print(int(datetime.datetime.strptime('${DATETIME}', '%y/%m/%d,%H:%M:%S').strftime('%s'))+1)"`
  date -s "@${EPOCHTIME}"
}

function init_modem {
  wait_for_ppp_offline
  perst
  sleep 0.1
  init_serialport
  _adjust_time
}
