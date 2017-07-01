#!/usr/bin/env bash

PRODUCT="CANDY Pi Lite Board"
PRODUCT_DIR_NAME="candy-pi-lite"
SHUDOWN_STATE_FILE=/opt/candy-line/${PRODUCT_DIR_NAME}/__shutdown

function led_off {
  . /opt/candy-line/${PRODUCT_DIR_NAME}/_pin_settings.sh > /dev/null 2>&1
  echo 0 > ${LED2_PIN}/value
}

# start banner
logger -t ${PRODUCT_DIR_NAME} "Inactivating ${PRODUCT}..."
touch ${SHUDOWN_STATE_FILE}

poff
/opt/candy-line/${PRODUCT_DIR_NAME}/modem_off.sh > /dev/null 2>&1
led_off
led_off # ensure LED off
systemctl restart dhcpcd

# end banner
logger -t ${PRODUCT_DIR_NAME} "${PRODUCT} is inactivated successfully!"
rm -f ${SHUDOWN_STATE_FILE}
