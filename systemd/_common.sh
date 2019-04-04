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

MODEM_BAUDRATE=${MODEM_BAUDRATE:-%MODEM_BAUDRATE%}
UART_PORT="/dev/ttySC1"
QWS_UC20="/dev/QWS.UC20"
QWS_EC21="/dev/QWS.EC21"
QWS_EC25="/dev/QWS.EC25"
QWS_BG96="/dev/QWS.BG96"
QWS_UC20_PORT="${QWS_UC20}.MODEM"
QWS_EC21_PORT="${QWS_EC21}.MODEM"
QWS_EC25_PORT="${QWS_EC25}.MODEM"
QWS_BG96_PORT="${QWS_BG96}.MODEM"
IF_NAME="${IF_NAME:-ppp0}"
DELAY_SEC=${DELAY_SEC:-1}
SHOW_CANDY_CMD_ERROR=0
PPPD_RUNNING_FILE="/opt/candy-line/${PRODUCT_DIR_NAME}/__pppd_running"
IP_REACHABLE_FILE="/opt/candy-line/${PRODUCT_DIR_NAME}/__ip_reachable"
MODEM_INFO_FILE="/opt/candy-line/${PRODUCT_DIR_NAME}/__modem_info"
PIDFILE="/var/run/candy-pi-lite-service.pid"
SOCK_PATH=${SOCK_PATH:-"/var/run/candy-board-service.sock"}
SIM_STATE="N/A"
PPP_MAX_FAIL=${PPP_MAX_FAIL:-3}

function assert_root {
  if [[ $EUID -ne 0 ]]; then
     echo "This script must be run as root"
     exit 1
  fi
}

function assert_service_is_running {
  if [ ! -f "${PIDFILE}" ]; then
    log "${PRODUCT} Service is missing"
    exit 1
  fi
  PID=`cat ${PIDFILE}`
  if ! kill -0 ${PID} > /dev/null 2>&1; then
    log "${PRODUCT} Service isn't running"
    exit 2
  fi
}

function log {
  logger -t ${PRODUCT_DIR_NAME} $1
  if [ "${DEBUG}" ]; then
    echo [${PRODUCT_DIR_NAME}] $1
  fi
}

function detect_usb_device {
  if [ -n "${USB_SERIAL_PORT}" ]; then
    return
  fi
  USB_SERIAL=`lsusb | grep "2c7c:0121"`
  if [ "$?" == "0" ]; then
    USB_SERIAL_PORT=${QWS_EC21_PORT}
    USB_SERIAL_AT_PORT="${QWS_EC21}.AT"
  else
    USB_SERIAL=`lsusb | grep "05c6:9003"`
    if [ "$?" == "0" ]; then
      USB_SERIAL_PORT=${QWS_UC20_PORT}
      USB_SERIAL_AT_PORT="${QWS_UC20}.AT"
    else
      USB_SERIAL=`lsusb | grep "2c7c:0125"`
      if [ "$?" == "0" ]; then
        USB_SERIAL_PORT=${QWS_EC25_PORT}
        USB_SERIAL_AT_PORT="${QWS_EC25}.AT"
      else
        USB_SERIAL=`lsusb | grep "2c7c:0296"`
        if [ "$?" == "0" ]; then
          USB_SERIAL_PORT=${QWS_BG96_PORT}
          USB_SERIAL_AT_PORT="${QWS_BG96}.AT"
        fi
      fi
    fi
  fi
  USB_SERIAL=""
  if [ -n "${USB_SERIAL_PORT}" ]; then
    log "[INFO] USB Serial Ports are found => ${USB_SERIAL_PORT}, ${USB_SERIAL_AT_PORT}"
  fi
}

function detect_board {
  if [ -z "${BOARD}" ]; then
    if [ -f "/proc/board_info" ]; then
      DT_MODEL=`cat /proc/board_info 2>&1`
      if [ -z "${DT_MODEL}" ]; then
        RESOLVE_MAX=30
        RESOLVE_COUNTER=0
        while [ ${RESOLVE_COUNTER} -lt ${RESOLVE_MAX} ];
        do
          DT_MODEL=`cat /proc/board_info 2>&1`
          if [ -n "${DT_MODEL}" ]; then
            break
          fi
          sleep 2
          let RESOLVE_COUNTER=RESOLVE_COUNTER+1
        done
      fi
      case ${DT_MODEL} in
        "Tinker Board" | "Tinker Board S")
          BOARD="ATB"
          ;;
        *)
          BOARD=""
          ;;
      esac
    else
      python -c "import RPi.GPIO" > /dev/null 2>&1
      if [ "$?" == "0" ]; then
        BOARD="RPi"
      fi
    fi
  fi
}

function look_for_usb_device {
  if [ "${SERIAL_PORT_TYPE}" == "uart" ]; then
    return
  fi
  MAX=40
  COUNTER=0
  while [ ${COUNTER} -lt ${MAX} ];
  do
    detect_usb_device
    if [ "${SERIAL_PORT_TYPE}" == "auto" ] || [ -n "${USB_SERIAL_PORT}" ]; then
      break
    fi
    sleep 1
    let COUNTER=COUNTER+1
  done
  if [ "${SERIAL_PORT_TYPE}" == "usb" ] && [ -z "${USB_SERIAL_PORT}" ]; then
    log "[ERROR] USB Serial Ports are missing."
    exit 2
  fi
}

function retry_usb_auto_detection {
  USB_SERIAL_DETECTED=""
  if [ "${SERIAL_PORT_TYPE}" != "auto" ]; then
    return
  fi
  if [ -z "${USB_SERIAL_PORT}" ]; then
    detect_usb_device
    if [ -n "${USB_SERIAL_PORT}" ]; then
      USB_SERIAL_DETECTED=1
      MODEM_INIT=0
      MODEM_SERIAL_PORT=""
      AT_SERIAL_PORT=""
    fi
  fi
}

function look_for_modem_at_port {
  MODEM_SERIAL_PORT=`/usr/bin/env python -c "import candy_board_qws; print(candy_board_qws.SerialPort.resolve_modem_port())"`
  AT_SERIAL_PORT="${USB_SERIAL_AT_PORT:-${MODEM_SERIAL_PORT}}"
  if [ "${MODEM_SERIAL_PORT}" == "None" ]; then
    MODEM_SERIAL_PORT=""
    AT_SERIAL_PORT=""
    return
  elif [ -n "${USB_SERIAL_PORT}" ] && [ "${USB_SERIAL_PORT}" != "${MODEM_SERIAL_PORT}" ]; then
    MODEM_SERIAL_PORT=""
    AT_SERIAL_PORT=""
    return
  fi
  log "[INFO] Modem Serial port: ${MODEM_SERIAL_PORT} and AT Serial port: ${AT_SERIAL_PORT} are selected"
}

function init_serialport {
  CURRENT_BAUDRATE="None"
  if [ -z "${MODEM_SERIAL_PORT}" ]; then
    look_for_modem_at_port
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
      RET=1
      MAX=40
      COUNTER=0
      while [ ${COUNTER} -lt ${MAX} ];
      do
        candy_command modem init
        if [ "${RET}" == "0" ]; then
          break
        fi
        sleep 1
        let COUNTER=COUNTER+1
      done
      if [ "${RET}" != "0" ]; then
        log "[ERROR] Modem returned error (USB)"
        return
      fi
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
    log "[INFO] Initializing modem with baudrate:${MODEM_BAUDRATE}"
    MAX=40
    COUNTER=0
    while [ ${COUNTER} -lt ${MAX} ];
    do
      candy_command modem "{\"action\":\"init\",\"baudrate\":\"${MODEM_BAUDRATE}\"}"
      if [ "${RET}" == "0" ]; then
        break
      fi
      sleep 1
      let COUNTER=COUNTER+1
    done
    if [ "${RET}" != "0" ]; then
      log "[ERROR] Modem returned error (UART)"
      return
    fi
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
  RESULT=`/usr/bin/env python /opt/candy-line/${PRODUCT_DIR_NAME}/server_main.py $1 $2 ${MODEM_SERIAL_PORT} ${CURRENT_BAUDRATE} ${SOCK_PATH}`
  RET=$?
  if [ "${SHOW_CANDY_CMD_ERROR}" == "1" ] && [ "${RET}" != "0" ]; then
    log "[INFO] candy_command[category:$1][action:$2] => [${RESULT}]"
  fi
}

function perst {
  # Make PERST_PIN low to reset module
  echo 0 > ${PERST_PIN}/value
  sleep 1
  # Make PERST_PIN high again
  echo 1 > ${PERST_PIN}/value
}

function clean_up_ppp_state {
  rm -f ${MODEM_INFO_FILE}
  rm -f ${MODEM_SERIAL_PORT_FILE}
  rm -f ${PPPD_RUNNING_FILE}
  rm -f ${IP_REACHABLE_FILE}
}

function wait_for_ppp_offline {
  RET=`ifconfig ${IF_NAME} > /dev/null 2>&1`
  if [ "$?" != "0" ]; then
    clean_up_ppp_state
    return
  fi
  poff -a > /dev/null 2>&1
  MAX=40
  COUNTER=0
  while [ ${COUNTER} -lt ${MAX} ];
  do
    RET=`ifconfig ${IF_NAME} > /dev/null 2>&1`
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
  clean_up_ppp_state
}

function wait_for_ppp_online {
  MAX=70
  COUNTER=0
  while [ ${COUNTER} -lt ${MAX} ];
  do
    RET=`ip link show ${IF_NAME} 2>&1 | grep ${IF_NAME} | grep "state" | grep -v "state DOWN"`
    RET="$?"
    if [ "${RET}" == "0" ]; then
      break
    fi
    sleep 1
    if [ ! -f "${PPPD_RUNNING_FILE}" ]; then
      break;
    fi
    let COUNTER=COUNTER+1
  done
  if [ "${RET}" != "0" ]; then
    log "[ERROR] PPP cannot be online"
    return
  fi
  log "[INFO] PPP goes online"
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

function wait_for_network_registration {
  # init_modem must be performed prior to this function
  REG_KEY="ps"
  if [ "$1" == "True" ]; then
    REG_KEY="cs"
  fi
  MAX=600
  COUNTER=0
  while [ ${COUNTER} -lt ${MAX} ];
  do
    candy_command network show
    if [ "${RET}" == "0" ]; then
      OPERATOR=`/usr/bin/env python -c "import json;r=json.loads('${RESULT}');print(r['result']['operator'])" 2>&1`
      log "[INFO] Operator => ${OPERATOR}"
      STAT=`
/usr/bin/env python -c \
"import json;r=json.loads('${RESULT}');
print('N/A' if r['status'] != 'OK' else r['result']['registration']['${REG_KEY}'])" 2>&1`
      if [ "$?" != "0" ]; then
        RET=1
      elif [ "${STAT}" == "Registered" ]; then
        log "[INFO] OK. Registered in the home ${REG_KEY} network"
        break
      elif [ "${STAT}" == "Roaming" ]; then
        log "[INFO] OK. Registered in the ROAMING ${REG_KEY} network"
        break
      else
        log "[INFO] Waiting for network registration => Status:${STAT}"
        RET=1
      fi
    fi
    sleep 1
    let COUNTER=COUNTER+1
  done
  if [ "${RET}" != "0" ]; then
    log "[ERROR] Network Registration Failed"
    exit 1
  fi
}

function test_functionality {
  # init_modem must be performed prior to this function
  candy_command modem show
  if [ "${RET}" != 0 ]; then
    log "[INFO] Restarting ${PRODUCT} Service as the module isn't connected properly"
    exit 1
  fi
  MODEM_SHOW=`/usr/bin/env python -c "
import json, time, datetime
r = json.loads('${RESULT}')
print('MODEL=%s FUNC=%s' % (
    r['result']['model'],
    r['result']['functionality']
))
"`
  eval ${MODEM_SHOW}
  log "[INFO] ${MODEL} Phone Functionality => ${FUNC}"
  if [ "${FUNC}" == "Anomaly" ]; then
    log "[ERROR] The module doesn't work properly. Functionality Recovery in progress..."
    candy_command modem reset
    log "[INFO] Restarting ${PRODUCT} Service as the module has been reset"
    exit 1
  fi
}

function save_apn {
  # init_modem must be performed prior to this function
  candy_command apn "{\"action\":\"set\",\"name\":\"$1\",\"user_id\":\"$2\",\"password\":\"$3\",\"type\":\"$4\"}"
  log "[INFO] Saved APN => $1"
  if [ "$5" == "True" ]; then
    candy_command network deregister
    if [ -n "$6" ]; then
      log "[INFO] Manual Operator Selection => [$6]"
      candy_command network "{\"action\":\"register\",\"operator\":\"$6\"}"
    else
      log "[INFO] Network Re-registering"
      candy_command network register
    fi
  fi
}

function adjust_time {
  # init_modem must be performed prior to this function
  candy_command modem show
  ADJUSTMENT=`/usr/bin/env python -c "
import json, time, datetime
r = json.loads('${RESULT}')
epochtime = int(datetime.datetime.strptime(r['result']['datetime'],
    '%y/%m/%d,%H:%M:%S').strftime('%s')) - time.timezone + ${DELAY_SEC}
if abs(epochtime - time.time()) < 1:
  epochtime = 0
print('MODEL=%s DATETIME=%s TIMEZONE=%s EPOCHTIME=%d' % (
    r['result']['model'],
    r['result']['datetime'],
    r['result']['timezone'],
    epochtime
))
"`
  if [ "${ADJUSTMENT}" == "ERROR" ]; then
    log "[ERROR] Failed to adjust time"
    return
  fi
  eval ${ADJUSTMENT}
  log "[INFO] Module Model: ${MODEL}"
  log "[INFO] Network Timezone: ${TIMEZONE}"
  if [ "${EPOCHTIME}" == "0" ]; then
    log "[INFO] Skipped to adjust time"
  else
    date -s "@${EPOCHTIME}"
    log "[INFO] Adjusted the current time => ${DATETIME} UTC"
  fi
}

function init_modem {
  MODEM_INIT=0
  wait_for_ppp_offline
  perst
  look_for_usb_device
  wait_for_serial_available
  if [ "${MODEM_INIT}" == "0" ]; then
    exit 1
  fi
}

function stop_ntp {
  systemctl status ntp > /dev/null 2>&1
  if [ "$?" == "0" ]; then
    systemctl stop ntp
  fi
  if [ -n "$(which timedatectl)" ]; then
    timedatectl set-ntp false
  fi
}

function start_ntp {
  systemctl status ntp > /dev/null 2>&1
  if [ "$?" == "0" ]; then
    systemctl --no-block start ntp
  fi
  if [ -n "$(which timedatectl)" ]; then
    timedatectl set-ntp true
  fi
}

function load_apn {
  FALLBACK_APN=$(cat /opt/candy-line/${PRODUCT_DIR_NAME}/fallback_apn)
  if [ -f "/opt/candy-line/${PRODUCT_DIR_NAME}/apn" ]; then
    APN=`cat /opt/candy-line/${PRODUCT_DIR_NAME}/apn`
  fi
  APN=${APN:-${FALLBACK_APN}}

  CREDS=`
    /usr/bin/env python -c \
    "with open('/opt/candy-line/${PRODUCT_DIR_NAME}/apn-list.json') as f:
    import json;c=json.load(f)['${APN}'];
    print('APN=%s APN_USER=%s APN_PASSWORD=%s APN_NW=%s ' \
    'APN_PDP=%s APN_CS=%s APN_OPS=%s APN_MCC=%s APN_MNC=%s APN_IPV6DNS1=%s APN_IPV6DNS2=%s' %
    (
      c['apn'] if 'apn' in c else '${APN}',
      c['user'],
      c['password'],
      c['nw'] if 'nw' in c else 'auto',
      c['pdp'] if 'pdp' in c else 'ipv4',
      c['cs'] if 'cs' in c else False,
      c['ops'] if 'ops' in c else False,
      c['mcc'] if 'mcc' in c else '',
      c['mnc'] if 'mnc' in c else '',
      c['ipv6dns1'] if 'ipv6dns1' in c else '',
      c['ipv6dns2'] if 'ipv6dns2' in c else '',
    ))" \
    2>&1`
  if [ "$?" != "0" ]; then
    log "[ERROR] Failed to load APN. Error=>${CREDS}"
    exit 1
  fi
  eval ${CREDS}
}
