#!/usr/bin/env bash

echo -e "\033[93m[WARN] *** INTERNAL USE, DO NOT RUN DIRECTLY *** \033[0m"

# Orange LED (Online Status Indicator)
LED2=4
LED2_PIN="/sys/class/gpio/gpio${LED2}"
LED2_DIR="${LED2_PIN}/direction"

# SC16IS75X RESET & PERST
PERST=20
PERST_PIN="/sys/class/gpio/gpio${PERST}"
PERST_DIR="${PERST_PIN}/direction"

function setup_ports {
  for p in ${LED2} ${PERST}; do
    [[ ! -f "/sys/class/gpio/gpio${p}/direction" ]] && echo  "${p}"  > /sys/class/gpio/export
  done
}

function setup_pin_directions {
  echo "out" > ${LED2_DIR}
  echo "out" > ${PERST_DIR}
}
