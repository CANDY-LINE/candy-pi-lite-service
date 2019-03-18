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

PRODUCT="CANDY Pi Lite Board"
PRODUCT_DIR_NAME="candy-pi-lite"
DEBUG=""

DHCPCD_CNF="/etc/dhcpcd.conf"
DHCPCD_ORG="/etc/dhcpcd.conf.org_candy"
DHCPCD_TMP="/etc/dhcpcd.conf.org_tmp"
SHUDOWN_STATE_FILE="/opt/candy-line/${PRODUCT_DIR_NAME}/__shutdown"
PPPD_EXIT_CODE_FILE="/opt/candy-line/${PRODUCT_DIR_NAME}/__pppd_exit_code"
CONNECT_ON_STARTUP_FILE="/opt/candy-line/${PRODUCT_DIR_NAME}/__connect_on_startup"
MODEM_SERIAL_PORT_FILE="/opt/candy-line/${PRODUCT_DIR_NAME}/__modem_serial_port"

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

function boot_apn {
  APN_FILE=""
  if [ -f "/boot/apn" ]; then
    APN_FILE="/boot/apn"
  elif [ -f "/boot/apn.txt" ]; then
    APN_FILE="/boot/apn.txt"
  fi
  if [ -n "${APN_FILE}" ]; then
    log "[INFO] Provisioning APN..."
    BOOT_APN=`/usr/bin/env python -c "
import json
apn = ''
apn_list = {}
with open('/opt/candy-line/${PRODUCT_DIR_NAME}/apn-list.json') as f:
    apn_list = json.load(f)
with open('${APN_FILE}') as f:
    try:
        apn = f.read()
        apn = json.loads(apn)
    except:
        pass
if 'apn' in apn:
    apn_list[apn['apn']] = {
        'user': apn['user'] if 'user' in apn else '',
        'password': apn['password'] if 'password' in apn else ''
    }
    with open('/opt/candy-line/${PRODUCT_DIR_NAME}/apn-list.json', 'w') as f:
        json.dump(apn_list, f)
    apn = apn['apn']
    with open('${APN_FILE}', 'w') as f:
        f.write(apn)
print(str(apn).strip() in apn_list)
"`
    if [ "${BOOT_APN}" != "True" ]; then
      log "[WARN] Invalid ${APN_FILE} content => $(cat ${APN_FILE}), ${APN_FILE} file is IGNORED"
    else
      log "[INFO] APN[$(cat ${APN_FILE})] is set"
      mv -f ${APN_FILE} /opt/candy-line/${PRODUCT_DIR_NAME}/apn
    fi
  fi
}

function boot_ip_reset {
  if [ -f "/boot/boot-ip-reset" ]; then
    rm -f "/boot/boot-ip-reset"
    if [ -f "${DHCPCD_ORG}" ]; then
      mv -f "${DHCPCD_ORG}" "${DHCPCD_CNF}"
      log "[INFO] Rebooting for resetting boot-ip..."
      reboot
    fi
  fi
}

function boot_ip_addr {
  resolved_interface=""
  if [ -e "/sys/class/net/eth-rpi" ]; then
    resolved_interface="eth-rpi"
  elif [ -e "/sys/class/net/eth0" ]; then
    resolved_interface="eth0"
  elif [ -e "/sys/class/net/usb0" ]; then
    resolved_interface="usb0"
  else
    log "[INFO] Skip to configure IP address as fixed NIC name is missing"
    return
  fi
  LIST=`ls -1 /boot/boot-ip*.json 2>&1`
  if [ "$?" == "0" ]; then
    NUM=`ls -1 /boot/boot-ip*.json | wc -l`
    if [ "${NUM}" != "1" ]; then
      log "[INFO] Skip to configure IP address as more than 2 boot-ip files are found => [${LIST}]"
      unset LIST # not remove boot-ip*.json files
      return
    fi
  else
    return
  fi
  if [ ! -f "${LIST}" ]; then
    log "[ERROR] ${LIST} is missing." # this should not happen
    unset LIST
    return
  fi
  SIZE=`ls -lrt ${LIST} | nawk '{print $5}'`
  if [[ "${SIZE}" -gt "1000" ]]; then
    log "[ERROR] Too big to read. Aborted."
    unset LIST # not remove boot-ip*.json files
    return
  fi

  log "[INFO] Checking /etc/dhcpcd.conf..."
  for p in ip_address routers domain_name_servers interface
  do
    VAL=`/usr/bin/env python -c "with open('${LIST}') as f:import json;c=json.load(f);print(('${p}=%s') % (c['${p}'] if '${p}' in c else ''))"`
    if [ "$?" != "0" ]; then
      log "[ERROR] Unexpected format => ${LIST}. Configruation aborted."
      unset LIST # not remove boot-ip*.json files
      return
    fi
    eval ${VAL}
  done

  interface=${interface:-${resolved_interface}}
  if [ -z ${interface} ]; then
    log "[ERROR] No network interface has been resolved."
    return
  fi
  NUM=`grep -wc "^[^#;]*interface\s*${interface}" "${DHCPCD_CNF}"`
  if [ "${NUM}" == "0" ]; then # update org_candy unless I/F is configured
    cp -f "${DHCPCD_CNF}" "${DHCPCD_ORG}"
  fi

  if [ -f "${DHCPCD_ORG}" ]; then
    rm -f "${DHCPCD_TMP}"
    cp -f "${DHCPCD_ORG}" "${DHCPCD_TMP}"
  else
    log "[INFO] Static IP is already configured in ${DHCPCD_CNF}"
    return
  fi

  NUM=`grep -wc "^[^#;]*interface\s*${interface}" "${DHCPCD_TMP}"`
  if [ "${NUM}" != "0" ]; then # double-check
    log "[INFO] Cannot configure IP as static IP is already configured..."
    rm -f "${DHCPCD_ORG}"
    return
  fi

  log "[INFO] Configuring IP address..."
  echo -e "# Appended by candy-pi-lite-service" >> "${DHCPCD_TMP}"
  echo -e "interface ${interface}" >> "${DHCPCD_TMP}"
  for p in ip_address routers domain_name_servers
  do
    echo -e "static ${p}=${!p}" >> "${DHCPCD_TMP}"
  done
  rm -f "${LIST}"
  if [ ! -f "${LIST}" ]; then
    mv -f ${DHCPCD_TMP} ${DHCPCD_CNF}
    if [ ! -f "${DHCPCD_TMP}" ] && [ -f "${DHCPCD_CNF}" ]; then
      log "[INFO] Restarting..."
      reboot
    fi
  fi
}

function boot_ip_addr_fin {
  rm -f "${DHCPCD_TMP}"
  if [ -f "${LIST}" ]; then
    rm -f "${LIST}"
  fi
}

function resolve_sim_state {
  SIM_MAX=5
  SIM_COUNTER=0
  while [ ${SIM_COUNTER} -lt ${SIM_MAX} ];
  do
    candy_command sim show
    SIM_STATE=`/usr/bin/env python -c "import json;r=json.loads('${RESULT}');print(r['result']['state'])" 2>&1`
    if [ "${SIM_STATE}" == "SIM_STATE_READY" ]; then
      break
    fi
    let SIM_COUNTER=SIM_COUNTER+1
    sleep 1
  done
  log "[INFO] SIM card state => ${SIM_STATE}"
}

function register_network {
  if [ "${SIM_STATE}" != "SIM_STATE_READY" ]; then
    log "[INFO] Skip network registration as SIM card is absent"
    return
  fi
  test_functionality
  save_apn "${APN}" "${APN_USER}" "${APN_PASSWORD}" "${APN_PDP}" "${APN_OPS}" "${APN_MCC}${APN_MNC}"
  wait_for_network_registration "${APN_CS}"
}

function set_normal_ppp_exit_code {
  echo "5" > ${PPPD_EXIT_CODE_FILE}
}

function connect {
  ip route del default
  CONN_MAX=3
  CONN_COUNTER=0
  if [[ "${OPERATOR}" == *"KDDI"* ]]; then
    PPP_MAX_FAIL=1
    log "[INFO] PPP_MAX_FAIL => ${PPP_MAX_FAIL}"
  fi
  RET=""
  while [ ${CONN_COUNTER} -lt ${CONN_MAX} ];
  do
    log "[INFO] Trying to connect...(Trial:$((CONN_COUNTER+1))/${CONN_MAX})"
    . /opt/candy-line/${PRODUCT_DIR_NAME}/start_pppd.sh &
    PPPD_PID="$!"
    wait_for_ppp_online
    if [ "${RET}" == "0" ]; then
      break
    fi
    poff -a > /dev/null 2>&1
    PPPD_RUNNING_TIMEOUT=0
    while [ ${PPPD_RUNNING_TIMEOUT} -lt 30 ]; do
      if [ ! -f "${PPPD_RUNNING_FILE}" ]; then
        break;
      fi
      let PPPD_RUNNING_TIMEOUT=PPPD_RUNNING_TIMEOUT+1
      sleep 1
    done
    if [ -f ${PPPD_EXIT_CODE_FILE} ]; then
      PPPD_EXIT_CODE=`cat ${PPPD_EXIT_CODE_FILE}`
    else
      PPPD_EXIT_CODE=""
    fi
    kill -9 ${PPPD_PID} > /dev/null 2>&1
    clean_up_ppp_state
    if [ "${PPPD_EXIT_CODE}" == "12" ]; then
      exit ${PPPD_EXIT_CODE}
    fi
    if [[ "${OPERATOR}" == *"KDDI"* ]]; then
      log "[ERROR] The module isn't ready for KDDI network. Setup in progress..."
      candy_command modem reset
      log "[INFO] Restarting ${PRODUCT} Service as the module has been reset"
      exit 1
    fi
    let CONN_COUNTER=CONN_COUNTER+1
  done
  if [ "${RET}" != "0" ]; then
    set_normal_ppp_exit_code
  fi
}

function resolve_connect_on_startup {
  if [ -f "${CONNECT_ON_STARTUP_FILE}" ]; then
    CONNECT_ON_STARTUP_FROM_FILE=`cat ${CONNECT_ON_STARTUP_FILE}`
    rm -f ${CONNECT_ON_STARTUP_FILE}
  fi
  CONNECT=${CONNECT_ON_STARTUP_FROM_FILE:-${CONNECT_ON_STARTUP:-1}}
}

function restart_with_connection {
  echo "1" > ${CONNECT_ON_STARTUP_FILE}  # Always connect on startup this time
  exit 3
}

# main
init

# Configuring APN
boot_apn
load_apn

# Configuring boot-ip
boot_ip_reset
boot_ip_addr
boot_ip_addr_fin

# start banner
log "[INFO] Initializing ${PRODUCT}..."
while true;
do
  RECONNECT="0"
  init_modem
  resolve_sim_state
  if [ "${SIM_STATE}" == "SIM_STATE_READY" ]; then
    if [ "${NTP_DISABLED}" == "1" ]; then
      stop_ntp
    fi
  else
    start_ntp
  fi
  retry_usb_auto_detection
  if [ "${USB_SERIAL_DETECTED}" == "1" ]; then
    log "[INFO] New USB serial ports are detected"
    wait_for_serial_available
  fi
  if [ "${SIM_STATE}" == "SIM_STATE_READY" ]; then
    while true;
    do
      register_network
      if [ "${NTP_DISABLED}" == "1" ]; then
        adjust_time
        if [ "$(date +%Y)" == "1980" ]; then
          log "[WARN] Failed to adjust time. Set NTP_DISABLED=0 to adjust the current time"
        fi
      fi
      retry_usb_auto_detection
      if [ "${USB_SERIAL_DETECTED}" == "1" ]; then
        log "[INFO] Re-registering network as new USB serial ports are detected"
        wait_for_serial_available
        continue
      fi
      break
    done
  fi

  resolve_connect_on_startup
  while true;
  do
    if [ "${GNSS_ON_STARTUP}" == "1" ]; then
      candy_command gnss start
      if [ "${RET}" == "0" ]; then
        log "[INFO] GNSS started"
      else
        log "[WARN] Failed to start GNSS"
      fi
    fi
    if [ "${CONNECT}" == "1" ]; then
      if [ "${SIM_STATE}" == "SIM_STATE_READY" ]; then
        log "[INFO] Trying to establish a connection..."
        connect
        if [ "${RET}" != "0" ]; then
          RECONNECT="1"
          break
        fi
      else
        set_normal_ppp_exit_code
      fi
    else
      log "[INFO] Not establishing a connection on start-up"
      CONNECT="1"
      set_normal_ppp_exit_code
    fi

    # end banner
    log "[INFO] ${PRODUCT} is initialized successfully!"
    /usr/bin/env python /opt/candy-line/${PRODUCT_DIR_NAME}/server_main.py ${AT_SERIAL_PORT} ${MODEM_BAUDRATE} ${IF_NAME}
    EXIT_CODE="$?"
    if [ ! -f "${SHUDOWN_STATE_FILE}" ]; then
      if [ "${EXIT_CODE}" == "143" ]; then
        # SIGTERM(15) is signaled by a thread in server_main module
        exit 0
      elif [ "${EXIT_CODE}" == "140" ]; then
        # SIGUSR2(12) is signaled by an external program to re-establish the connection
        rm -f ${PIDFILE}
        if [ ${SIM_STATE} == "SIM_STATE_READY" ]; then
          resolve_sim_state  # Ensure if the sim card is present
        fi
        if [ ${SIM_STATE} != "SIM_STATE_READY" ]; then
          restart_with_connection  # Restart if SIM is absent
        fi
        _CREDS=${CREDS}
        load_apn
        if [ "${_CREDS}" != "${CREDS}" ]; then
          restart_with_connection  # Restart if APN is modified
        fi
        continue
      else
        log "[INFO] ${PRODUCT} is shutting down by code:${EXIT_CODE}"
        exit ${EXIT_CODE}
      fi
    else
      log "[INFO] ${PRODUCT} is shutting down by code:${EXIT_CODE}"
      exit ${EXIT_CODE}
    fi
  done
  if [ "${RECONNECT}" == "0" ]; then
    break
  else
    log "[WARN] Failed to establishing a connection. Retry after ${SLEEP_SEC_BEFORE_RETRY} seconds..."
    sleep ${SLEEP_SEC_BEFORE_RETRY}
  fi
done
