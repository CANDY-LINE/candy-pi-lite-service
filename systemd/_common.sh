#!/usr/bin/env bash

UART_PORT="/dev/ttySC0"

function assert_root {
  if [[ $EUID -ne 0 ]]; then
     echo "This script must be run as root"
     exit 1
  fi
}

function log {
  logger -t ${PRODUCT_DIR_NAME} $1
  if [ "${DEBUG}" ]; then
    echo ${PRODUCT_DIR_NAME} $1
  fi
}

function look_for_modem_port {
  MODEM_SERIAL_PORT=`/usr/bin/env python -c "import candy_board_qws; print(candy_board_qws.SerialPort.resolve_modem_port())"`
  if [ "${MODEM_SERIAL_PORT}" == "None" ]; then
    if [ -e "${UART_PORT}" ]; then
      log "[INFO] Trying to adjust baudrate"
      MODEM_BAUDRATE=`/usr/bin/env python -c "import candy_board_qws; print(candy_board_qws.SerialPort.resolve_modem_baudrate('${UART_PORT}'))"`
      if [ "${MODEM_BAUDRATE}" != "None" ]; then
        MODEM_SERIAL_PORT=${UART_PORT}
      else
        log "[ERROR] Serial port is missing, good-bye"
        exit 10
      fi
    else
      log "[ERROR] Serial port is missing, bye"
      exit 10
    fi
  else
    log "Serial port: ${MODEM_SERIAL_PORT} is selected"
  fi
}

function init_serialport {
  if [ "${MODEM_SERIAL_PORT}" != "${UART_PORT}" ]; then
    return
  fi
  MODEM_BAUDRATE=`/usr/bin/env python -c "import candy_board_qws; print(candy_board_qws.SerialPort.resolve_modem_baudrate('${UART_PORT}'))"`
  if [ "${MODEM_BAUDRATE}" == "None" ]; then
    log "[ERROR] Modem is missing, bye"
    exit 1
  elif [ -n "${BAUDRATE}" ]; then
    candy_command modem "{\"action\":\"init\",\"baudrate\":\"${BAUDRATE}\"}"
    log "[INFO] Modem baudrate changed: ${MODEM_BAUDRATE} => ${BAUDRATE}"
    MODEM_BAUDRATE=${BAUDRATE}
  else
    candy_command modem init
  fi
  log "[INFO] Modem baudrate => ${MODEM_BAUDRATE}"
}

function candy_command {
  MODEM_BAUDRATE=${MODEM_BAUDRATE:-115200}
  RESULT=`/usr/bin/env python /opt/candy-line/${PRODUCT_DIR_NAME}/server_main.py $1 $2 ${MODEM_SERIAL_PORT} ${MODEM_BAUDRATE} /var/run/candy-board-service.sock`
  RET=$?
}
