#!/usr/bin/env bash

# Copyright (c) 2018 CANDY LINE INC.
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

PRODUCT="CANDY Pi Lite Board"
PRODUCT_DIR_NAME="candy-pi-lite"
if [ "$1" == "-q" ]; then
  DEBUG=""
else
  DEBUG="1"
fi

function init {
  . /opt/candy-line/${PRODUCT_DIR_NAME}/_common.sh > /dev/null 2>&1
}

function assert_connected {
  if [ -f "${PPPD_RUNNING_FILE}" ]; then
    log "The connection is already established"
    exit 3
  fi
  if [ ! -f "${PIDFILE}" ]; then
    log "PID file is missing"
    exit 4
  fi
}

function send_signal_user2 {
  # SIGUSR2(12)
  kill -12 $(cat ${PIDFILE})
  CONN_MAX=10
  CONN_COUNTER=0
  RET=""
  while [ ${CONN_COUNTER} -lt ${CONN_MAX} ];
  do
    TEST=`candy service version 2>&1`
    RET="$?"
    if [ "${RET}" == 2 ]; then
      break
    fi
    sleep 1
    let CONN_COUNTER=CONN_COUNTER+1
  done
  if [ "${RET}" != "2" ]; then
    log "Timeout"
    exit 1
  fi
}

init
assert_root
assert_service_is_running
assert_connected
send_signal_user2
