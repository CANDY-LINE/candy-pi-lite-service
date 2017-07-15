#!/usr/bin/env bash

PRODUCT="CANDY Pi Lite Board"
PRODUCT_DIR_NAME="candy-pi-lite"
SHUDOWN_STATE_FILE=/opt/candy-line/${PRODUCT_DIR_NAME}/__shutdown

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

function led_off {
  echo 0 > ${LED2_PIN}/value
}

# start banner
logger -t ${PRODUCT_DIR_NAME} "Inactivating ${PRODUCT}..."
touch ${SHUDOWN_STATE_FILE}

init
poff
led_off
systemctl restart dhcpcd
if [ "${NTP_DISABLED}" == "1" ]; then
  systemctl start ntp
fi

# end banner
logger -t ${PRODUCT_DIR_NAME} "${PRODUCT} is inactivated successfully!"
rm -f ${SHUDOWN_STATE_FILE}
