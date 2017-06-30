#!/usr/bin/env bash

function init {
  . /opt/candy-line/${PRODUCT_DIR_NAME}/_common.sh > /dev/null 2>&1
}

function perst {
  # Make PERST_PIN low to reset module
  echo 0 > ${PERST_PIN}/value
  sleep 1
  # Make PERST_PIN high again
  echo 1 > ${PERST_PIN}/value
}

function modem_reboot {
  . /opt/candy-line/${PRODUCT_DIR_NAME}/_pin_settings.sh > /dev/null 2>&1
  perst
}

init
assert_root
modem_reboot
echo "OK"
