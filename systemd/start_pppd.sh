#!/usr/bin/env bash

PRODUCT_DIR_NAME="candy-pi-lite"

# Run `poff` to stop

APN=${APN:-"soracom.io"}
CREDS=`/usr/bin/env python -c "with open('apn-list.json') as f:import json;c=json.load(f)['${APN}'];print('APN_USER=%s APN_PASSWORD=%s' % (c['user'],c['password']))"`
eval ${CREDS}
if [ -n "${DEBUG}" ]; then DEBUG="debug"; fi

CONNECT="'chat -s -v \
ABORT \"NO CARRIER\" \
ABORT \"ERROR\" \
ABORT \"NO DIALTONE\" \
ABORT \"BUSY\" \
ABORT \"NO ANSWER\" \
\"\" AT \
OK ATE0 \
OK AT+CGDCONT=1,\\\"IP\\\",\\\"${APN}\\\",,0,0 \
OK ATD*99# \
CONNECT \
'"

DISCONNECT="'chat -s -v \
ABORT OK \
ABORT BUSY \
ABORT DELAYED \
ABORT \"NO ANSWER\" \
ABORT \"NO CARRIER\" \
ABORT \"NO DIALTONE\" \
ABORT VOICE \
ABORT ERROR \
ABORT RINGING \
TIMEOUT 12 \
\"\" \K \
\"\" \K \
\"\" \K \
\"\" +++ATH \
\"\" +++ATH \
\"\" +++ATH \
\"\" ATZ \
SAY \"\nGoodbye from CANDY Pi Lite\n\" \
'"

pppd ${MODEM_SERIAL_PORT} ${MODEM_BAUDRATE} ${DEBUG} \
  user "${APN_USER}" \
  password "${APN_PASSWORD}" \
  connect "'${CONNECT}'" \
  disconnect "'${DISCONNECT}'" \
  hide-password \
  nolock \
  nocrtscts \
  usepeerdns \
  noauth \
  noipdefault \
  defaultroute \
  ipcp-accept-local \
  ipcp-accept-remote \
  &
