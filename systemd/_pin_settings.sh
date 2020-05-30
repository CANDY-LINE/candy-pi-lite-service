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

echo -e "\033[93m[WARN] *** INTERNAL USE, DO NOT RUN DIRECTLY *** \033[0m"

if [ ! -e "/proc/device-tree/model" ]; then
  log "[FATAL] *** UNSUPPORTED OS ***"
  exit 3
fi

detect_board
case ${BOARD} in
  "RPi")
    LED2=4
    PERST=20
    W_DISABLE=12
    ;;
  "ATB")
    LED2=17
    PERST=187
    W_DISABLE=239
    ;;
  *)
    DT_MODEL=`cat /proc/device-tree/model 2>&1`
    log "[FATAL] UNSUPPORTED BOARD => [${DT_MODEL}]"
    exit 3
    ;;
esac

# Orange LED (Online Status Indicator)
LED2_PIN="/sys/class/gpio/gpio${LED2}"
LED2_DEFAULT=0
# SC16IS75X RESET & PERST
PERST_PIN="/sys/class/gpio/gpio${PERST}"
PERST_DEFAULT=1
# W_DISABLE
W_DISABLE_PIN="/sys/class/gpio/gpio${W_DISABLE}"
W_DISABLE_DEFAULT=1

function setup_output_ports {
  for p in $1; do
    pin_value="${p}_PIN"
    default_value="${p}_DEFAULT"
    if [ ! -f "${!pin_value}/direction" ]; then
      echo "${!p}"  > /sys/class/gpio/export
      if [ "$?" != "0" ]; then
        log "[FATAL] Failed to export GPIO${!p}"
        exit 3
      fi
      echo "out" > "${!pin_value}/direction"
      echo "${!default_value}" > "${!pin_value}/value"
    fi
  done
}

function setup_input_ports {
  for p in $1; do
    pin_value="${p}_PIN"
    if [ ! -f "${!pin_value}/direction" ]; then
      echo "${!p}"  > /sys/class/gpio/export
      if [ "$?" != "0" ]; then
        log "[FATAL] Failed to export GPIO${!p}"
        exit 3
      fi
      echo "in" > "${!pin_value}/direction"
    fi
    case ${BOARD} in
      "RPi")
        ${PYTHON} -c "import RPi.GPIO as GPIO; GPIO.setmode(GPIO.BCM); GPIO.setup(${!p}, GPIO.IN)"
        if [ "$?" != "0" ]; then
          error=1
          if [ "${PYTHON}" == "python3" ]; then
            python -c "import RPi.GPIO as GPIO; GPIO.setmode(GPIO.BCM); GPIO.setup(${!p}, GPIO.IN)"
            error=$?
          fi
          if [ "$?" != "0" ]; then
            log "[FATAL] Failed to set up GPIO${!p}"
            exit 3
          fi
        fi
        ;;
      *)
        log "[FATAL] NOT YET SUPPORTED for ${BOARD}"
        exit 3
        ;;
    esac
  done
}

setup_output_ports "LED2 PERST W_DISABLE"

if [ "${BUTTON_EXT}" == "1" ]; then
  # BUTTON_LED
  BUTTON_LED_ENV="${BOARD}_BUTTON_LED"
  BUTTON_LED=${!BUTTON_LED_ENV}
  BUTTON_LED_PIN="/sys/class/gpio/gpio${BUTTON_LED}"
  BUTTON_LED_DEFAULT=1

  setup_output_ports "BUTTON_LED"

  # BUTTON_IN
  BUTTON_IN_ENV="${BOARD}_BUTTON_IN"
  BUTTON_IN=${!BUTTON_IN_ENV}
  BUTTON_IN_PIN="/sys/class/gpio/gpio${BUTTON_IN}"

  setup_input_ports "BUTTON_IN"
fi
