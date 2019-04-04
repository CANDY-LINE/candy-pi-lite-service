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

# Run `poff` to stop

if [ -n "${PPPD_DEBUG}" ]; then
  PPPD_DEBUG="debug"
  CHAT_VERBOSE="-v"
elif [ -n "${CHAT_VERBOSE}" ]; then
  CHAT_VERBOSE="-v"
fi

NW_CMD=""
if [ "${APN_NW}" == "3g" ]; then
  NW_CMD="OK AT+QCFG=\\\"nwscanmode\\\",2,1"
elif [ "${APN_NW}" == "lte" ]; then
  NW_CMD="OK AT+QCFG=\\\"nwscanmode\\\",3,1"
elif [ "${APN_NW}" == "2g" ]; then
  NW_CMD="OK AT+QCFG=\\\"nwscanmode\\\",1,1"
else
  NW_CMD="OK AT+QCFG=\\\"nwscanmode\\\",0,1"
fi

PPPD_IPV6=""
if [ "${APN_PDP}" == "ipv6" ]; then
  PPPD_IPV6="+ipv6 ipv6cp-accept-local ipv6cp-accept-remote"
elif [ "${APN_PDP}" == "ipv4v6" ]; then
  PPPD_IPV6="+ipv6 ipv6cp-accept-local ipv6cp-accept-remote"
fi

CONNECT="'chat -s ${CHAT_VERBOSE} \
ABORT \"NO CARRIER\" \
ABORT \"ERROR\" \
ABORT \"NO DIALTONE\" \
ABORT \"BUSY\" \
ABORT \"NO ANSWER\" \
\"\" AT \
OK ATE0 \
${NW_CMD} \
OK AT+QCFG=\\\"nwscanmode\\\" \
OK ATD*99# \
CONNECT \
'"

DISCONNECT="'chat -s ${CHAT_VERBOSE} \
ABORT OK \
ABORT BUSY \
ABORT DELAYED \
ABORT \"NO ANSWER\" \
ABORT \"NO CARRIER\" \
ABORT \"NO DIALTONE\" \
ABORT VOICE \
ABORT ERROR \
ABORT RINGING \
TIMEOUT 12 \
\"\" \K \
\"\" \K \
\"\" \K \
\"\" +++ATH \
\"\" +++ATH \
\"\" +++ATH \
\"\" ATZ \
SAY \"\nGoodbye from CANDY Pi Lite\n\" \
'"

function init {
  . /opt/candy-line/${PRODUCT_DIR_NAME}/_common.sh > /dev/null 2>&1
  if [ -e "${UART_PORT}" ] || [ -e "${QWS_UC20_PORT}" ] || [ -e "${QWS_EC21_PORT}" ] || [ -e "${QWS_EC25_PORT}" ] || [ -e "${QWS_BG96_PORT}" ]; then
    . /opt/candy-line/${PRODUCT_DIR_NAME}/_pin_settings.sh > /dev/null 2>&1
  else
    log "[ERROR] Modem is missing"
    exit_pppd 11
  fi
}

function connect {
  echo "${MODEM_SERIAL_PORT}" > ${MODEM_SERIAL_PORT_FILE}
  rm -f ${PPPD_EXIT_CODE_FILE}
  touch ${PPPD_RUNNING_FILE}
  pppd ${MODEM_SERIAL_PORT} ${MODEM_BAUDRATE} ${PPPD_DEBUG} ${PPPD_IPV6} \
    user "${APN_USER}" \
    password "${APN_PASSWORD}" \
    connect "'${CONNECT}'" \
    disconnect "'${DISCONNECT}'" \
    hide-password \
    nocrtscts \
    usepeerdns \
    noauth \
    noipdefault \
    defaultroute \
    ipcp-accept-local \
    ipcp-accept-remote \
    novj \
    novjccomp \
    noccp \
    ipcp-max-configure 30 \
    local \
    lock \
    modem \
    persist \
    maxfail ${PPP_MAX_FAIL} \
    nodetach > /dev/null 2>&1
}

function exit_pppd {
  log "[INFO] start_pppd.sh terminated: Exit Code => $1"
  # EXIT_CODE: poff=>5, Modem hangup=>16
  echo $1 > ${PPPD_EXIT_CODE_FILE}
  rm -f ${NW_INFO_FILE}
  rm -f ${MODEM_INFO_FILE}
  rm -f ${MODEM_SERIAL_PORT_FILE}
  rm -f ${PPPD_RUNNING_FILE}
  rm -f ${IP_REACHABLE_FILE}
  exit $1
}

# main
log "[INFO] Starting PPP: ${MODEM_SERIAL_PORT}"
init
assert_root
connect
exit_pppd "$?"
