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
DEBUG=""

DHCPCD_CNF="/etc/dhcpcd.conf"
DHCPCD_ORG="/etc/dhcpcd.conf.org_candy"
DHCPCD_TMP="/etc/dhcpcd.conf.org_tmp"
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

function boot_apn {
  if [ -f "/boot/apn" ]; then
    log "[INFO] Provisioning APN..."
    BOOT_APN=`/usr/bin/env python -c "
import json
apn = ''
apn_list = {}
with open('/opt/candy-line/${PRODUCT_DIR_NAME}/apn-list.json') as f:
    apn_list = json.load(f)
with open('/boot/apn') as f:
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
    with open('/boot/apn', 'w') as f:
        f.write(apn)
print(str(apn).strip() in apn_list)
"`
    if [ "${BOOT_APN}" != "True" ]; then
      log "[ERROR] Invalid /boot/apn content => $(cat /boot/apn), /boot/apn file is ignored"
    else
      log "[INFO] APN[$(cat /boot/apn)] is set"
      mv -f /boot/apn /opt/candy-line/${PRODUCT_DIR_NAME}/apn
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
  interface=""
  if [ -e "/sys/class/net/eth0" ]; then
    interface="eth0"
  elif [ -e "/sys/class/net/eth-rpi" ]; then
    interface="eth-rpi"
  else
    log "[INFO] Skip to configure IP address as fixed NIC name is missing"
    return
  fi
  LIST=`ls -1 /boot/boot-ip*.json`
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
  for p in ip_address routers domain_name_servers
  do
    VAL=`/usr/bin/env python -c "with open('${LIST}') as f:import json;print(('${p}=%s') % json.load(f)['${p}'])"`
    if [ "$?" != "0" ]; then
      log "[ERROR] Unexpected format => ${LIST}. Configruation aborted."
      unset LIST # not remove boot-ip*.json files
      return
    fi
    eval ${VAL}
  done

  interface=${interface:-"eth-rpi"}
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

function connect {
  ip route del default
  CONN_MAX=5
  CONN_COUNTER=0
  while [ ${CONN_COUNTER} -lt ${CONN_MAX} ];
  do
    . /opt/candy-line/${PRODUCT_DIR_NAME}/start_pppd.sh &
    PPPD_PID="$!"
    wait_for_ppp_online
    if [ "${RET}" == "0" ]; then
      break
    fi
    poff -a > /dev/null 2>&1
    kill -9 ${PPPD_PID}
    let CONN_COUNTER=CONN_COUNTER+1
  done
  if [ "${RET}" != "0" ]; then
    log "[ERROR] RESTARTING ${PRODUCT}..."
    exit 3
  fi
}

# main
init

# Configuring APN
boot_apn

# Configuring boot-ip
boot_ip_reset
boot_ip_addr
boot_ip_addr_fin

# start banner
log "[INFO] Initializing ${PRODUCT}..."
init_modem
wait_for_network_registration
if [ "${NTP_DISABLED}" == "1" ]; then
  stop_ntp
fi
connect
if [ "${NTP_DISABLED}" == "1" ]; then
  if [ "$(date +%Y)" == "1980" ]; then
    log "[INFO] Trying to close the first connetion for time adjustment..."
    if [ "${RET}" == "0" ]; then
      poff -a > /dev/null 2>&1
      sleep 3 # waiting for pppd exiting
      adjust_time
      log "[INFO] Time adjusted. Trying to establish the data connetion..."
      connect
    else
      log "[INFO] Failed to connect. Restart this service in order to adjust time later."
    fi
  fi
elif [ "${RET}" != "0" ]; then
  log "[INFO] Failed to connect. Restart this service later."
fi

# end banner
log "[INFO] ${PRODUCT} is initialized successfully!"
/usr/bin/env python /opt/candy-line/${PRODUCT_DIR_NAME}/server_main.py ${AT_SERIAL_PORT} ${MODEM_BAUDRATE} ${IF_NAME}
EXIT_CODE="$?"
if [ "${EXIT_CODE}" == "143" ] && [ ! -f "${SHUDOWN_STATE_FILE}" ]; then
  # SIGTERM(15) is signaled by a thread in server_main module
  exit 0
else
  exit ${EXIT_CODE}
fi
