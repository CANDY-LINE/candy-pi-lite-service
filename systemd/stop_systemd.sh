#!/usr/bin/env bash

PRODUCT="CANDY Pi Lite Board"
PRODUCT_DIR_NAME="candy-pi-lite"
MODULE_SUPPORTED=0
SHUDOWN_STATE_FILE=/opt/candy-line/${PRODUCT_DIR_NAME}/__shutdown

function led_off {
  . /opt/candy-line/${PRODUCT_DIR_NAME}/_pin_settings.sh > /dev/null 2>&1
  echo 0 > ${LED2_PIN}/value
}

function stop_ppp {
  if [ "${ROUTER_ENABLED}" == "0" ]; then
    poff
    sleep 17
    poff
    sleep 18
    poff
  fi
}

function diagnose_self {
  RET=`dmesg | grep "register 'cdc_ether'"`
  RET=$?
  if [ "${RET}" != "0" ]; then
    return
  fi

  RET=`lsusb | grep 1ecb:0208`
  RET=$?
  if [ "${RET}" == "0" ]; then
    MODULE_SUPPORTED=1
  fi
}

# LTE/3G USB Ethernet
function inactivate_lte {
  if [ "${MODULE_SUPPORTED}" != "1" ]; then
    return
  fi

  logger -t ${PRODUCT_DIR_NAME} "Inactivating LTE/3G Module..."
  USB_ID=`dmesg | grep "New USB device found, idVendor=1ecb, idProduct=0208" | sed 's/^.*\] //g' | cut -f 1 -d ':' | cut -f 2 -d ' ' | tail -1`
  IF_NAME=`dmesg | grep " ${USB_ID}" | grep "register 'cdc_ether'" | cut -f 2 -d ':' | cut -f 2 -d ' ' | tail -1`
  RET=`ifconfig ${IF_NAME}`
  RET=$?
  if [ "${RET}" != "0" ]; then
    # When renamed
    IF_NAME=`dmesg | grep "renamed network interface usb1" | sed 's/^.* usb1 to //g' | cut -f 1 -d ' ' | tail -1`
  fi
  if [ -n "${IF_NAME}" ]; then
    ifconfig ${IF_NAME} down
    logger -t ${PRODUCT_DIR_NAME} "The interface [${IF_NAME}] is down!"
  fi
}

# start banner
logger -t ${PRODUCT_DIR_NAME} "Inactivating ${PRODUCT}..."
touch ${SHUDOWN_STATE_FILE}

stop_ppp
diagnose_self
inactivate_lte
/opt/candy-line/${PRODUCT_DIR_NAME}/modem_off.sh > /dev/null 2>&1
led_off
led_off # ensure LED off

# end banner
logger -t ${PRODUCT_DIR_NAME} "${PRODUCT} is inactivated successfully!"
rm -f ${SHUDOWN_STATE_FILE}
