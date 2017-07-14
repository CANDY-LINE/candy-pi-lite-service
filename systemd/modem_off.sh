#!/usr/bin/env bash

PRODUCT_DIR_NAME="candy-pi-lite"

function init {
  . /opt/candy-line/${PRODUCT_DIR_NAME}/_common.sh > /dev/null 2>&1
  . /opt/candy-line/${PRODUCT_DIR_NAME}/_pin_settings.sh > /dev/null 2>&1
  export LED2
}

function modem_off {
  candy_command modem off
}

init
assert_root
look_for_modem_port
init_serialport
modem_off
echo "OK"
