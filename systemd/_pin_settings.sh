#!/usr/bin/env bash

# Copyright (c) 2017 CANDY LINE INC.
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

# Orange LED (Online Status Indicator)
LED2=4
LED2_PIN="/sys/class/gpio/gpio${LED2}"
LED2_DIR="${LED2_PIN}/direction"
LED2_DEFAULT=0

# SC16IS75X RESET & PERST
PERST=20
PERST_PIN="/sys/class/gpio/gpio${PERST}"
PERST_DIR="${PERST_PIN}/direction"
PERST_DEFAULT=1

# W_DISABLE
W_DISABLE=12
W_DISABLE_PIN="/sys/class/gpio/gpio${W_DISABLE}"
W_DISABLE_DIR="${W_DISABLE_PIN}/direction"
W_DISABLE_DEFAULT=1

function setup_ports {
  for p in LED2 PERST W_DISABLE; do
    if [ ! -f "/sys/class/gpio/gpio${!p}/direction" ]; then
      echo "${!p}"  > /sys/class/gpio/export
      echo "out" > "/sys/class/gpio/gpio${!p}/direction"
      default_value="${p}_DEFAULT"
      pin_value="${p}_PIN"
      echo "${!default_value}" > "${!pin_value}/value"
    fi
  done
}

setup_ports
