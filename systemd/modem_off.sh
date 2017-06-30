#!/usr/bin/env bash

PRODUCT_DIR_NAME="candy-pi-lite"

function init {
  . /opt/candy-line/${PRODUCT_DIR_NAME}/_common.sh > /dev/null 2>&1
}

function modem_off {
  candy_command modem off
}

init
assert_root
look_for_serial_port
init_serialport
modem_off
echo "OK"
