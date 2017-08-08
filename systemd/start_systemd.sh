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

PRODUCT="CANDY Pi Lite Board"
PRODUCT_DIR_NAME="candy-pi-lite"
DEBUG=""

DHCPCD_CNF="/etc/dhcpcd.conf"
DHCPCD_ORG="/etc/dhcpcd.conf.org_candy"
DHCPCD_TMP="/etc/dhcpcd.conf.org_tmp"
SHUDOWN_STATE_FILE="/opt/candy-line/${PRODUCT_DIR_NAME}/__shutdown"

function init {
  . /opt/candy-line/${PRODUCT_DIR_NAME}/_common.sh > /dev/null 2>&1
  if [ -e "${UART_PORT}" ] || [ -e "${QWS_UC20_PORT}" ] || [ -e "${QWS_EC21_PORT}" ]; then
    . /opt/candy-line/${PRODUCT_DIR_NAME}/_pin_settings.sh > /dev/null 2>&1
    export LED2
  else
    log "[ERROR] Modem is missing"
    exit 11
  fi
}

function boot_ip_reset {
  if [ -f "/boot/boot-ip-reset" ]; then
    rm -f "/boot/boot-ip-reset"
    if [ -f "${DHCPCD_ORG}" ]; then
      mv -f "${DHCPCD_ORG}" "${DHCPCD_CNF}"
      log "Rebooting for resetting boot-ip..."
      reboot
    fi
  fi
}

function boot_ip_addr {
  LIST=`ls -1 /boot/boot-ip*.json`
  if [ "$?" == "0" ]; then
    NUM=`ls -1 /boot/boot-ip*.json | wc -l`
    if [ "${NUM}" != "1" ]; then
      log "Skip to configure IP address as more than 2 boot-ip files are found => [${LIST}]"
      unset LIST # not remove boot-ip*.json files
      return
    fi
  else
    return
  fi
  if [ ! -f "${LIST}" ]; then
    log "${LIST} is missing." # this should not happen
    unset LIST
    return
  fi
  SIZE=`ls -lrt ${LIST} | nawk '{print $5}'`
  if [[ "${SIZE}" -gt "1000" ]]; then
    log "Too big to read. Aborted."
    unset LIST # not remove boot-ip*.json files
    return
  fi

  log "Checking /etc/dhcpcd.conf..."
  for p in interface ip_address routers domain_name_servers
  do
    VAL=`/usr/bin/env python -c "with open('${LIST}') as f:import json;print(('${p}=%s') % json.load(f)['${p}'])"`
    if [ "$?" != "0" ]; then
      log "Unexpected format => ${LIST}. Configruation aborted."
      unset LIST # not remove boot-ip*.json files
      return
    fi
    eval ${VAL}
  done

  NUM=`grep -wc "^[^#;]*interface\s*${interface}" "${DHCPCD_CNF}"`
  if [ "${NUM}" == "0" ]; then # update org_candy unless I/F is configured
    cp -f "${DHCPCD_CNF}" "${DHCPCD_ORG}"
  fi

  if [ -f "${DHCPCD_ORG}" ]; then
    rm -f "${DHCPCD_TMP}"
    cp -f "${DHCPCD_ORG}" "${DHCPCD_TMP}"
  else
    log "Static IP is already configured in ${DHCPCD_CNF}"
    return
  fi

  NUM=`grep -wc "^[^#;]*interface\s*${interface}" "${DHCPCD_TMP}"`
  if [ "${NUM}" != "0" ]; then # double-check
    log "Cannot configure IP as static IP is already configured..."
    rm -f "${DHCPCD_ORG}"
    return
  fi

  log "Configuring IP address..."
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
      log "Restarting..."
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
  . /opt/candy-line/${PRODUCT_DIR_NAME}/start_pppd.sh
}

# main
init

# Configuring boot-ip
boot_ip_reset
boot_ip_addr
boot_ip_addr_fin

# start banner
log "Initializing ${PRODUCT}..."
init_modem
connect
if [ "${NTP_DISABLED}" == "1" ]; then
  systemctl stop ntp
fi

# end banner
log "${PRODUCT} is initialized successfully!"
/usr/bin/env python /opt/candy-line/${PRODUCT_DIR_NAME}/server_main.py ${MODEM_SERIAL_PORT} ${MODEM_BAUDRATE} ${IF_NAME}
EXIT_CODE="$?"
if [ "${EXIT_CODE}" == "143" ] && [ ! -f "${SHUDOWN_STATE_FILE}" ]; then
  # SIGTERM(15) is signaled by a thread in server_main module
  exit 0
else
  exit ${EXIT_CODE}
fi
