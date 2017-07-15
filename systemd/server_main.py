# -*- coding: utf-8 -*-

import fcntl
import json
import os
import signal
import socket
import select
import struct
import sys
import termios
import threading
import time
import subprocess
import atexit
import re
import candy_board_qws
import logging
import logging.handlers

# sys.argv[0] ... Serial Port
# sys.argv[1] ... The path to socket file,
#                 e.g. /var/run/candy-board-service.sock
# sys.argv[2] ... The network interface name to be monitored

LED = 'gpio%s' % (os.environ['LED2'] if 'LED2' in os.environ else '4')
logger = logging.getLogger('candy-pi-lite')
logger.setLevel(logging.INFO)
handler = logging.handlers.SysLogHandler(address='/dev/log')
logger.addHandler(handler)
formatter = logging.Formatter('%(module)s.%(funcName)s: %(message)s')
handler.setFormatter(formatter)
led = 0
led_sec = float(os.environ['BLINKY_INTERVAL_SEC']) \
    if 'BLINKY_INTERVAL_SEC' in os.environ else 1.0
if led_sec < 0 or led_sec > 60:
    led_sec = 1.0
PPP_PING_INTERVAL_SEC = float(os.environ['PPP_PING_INTERVAL_SEC']) \
    if 'PPP_PING_INTERVAL_SEC' in os.environ else 0.0
online = False
shutdown_state_file = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                   '__shutdown')


class Pinger(threading.Thread):
    DEST_ADDR = '<broadcast>'
    DEST_PORT = 60100
    CAT_PPP0_TX_STAT = 'cat /sys/class/net/ppp0/statistics/tx_bytes'

    def __init__(self, interval_sec):
        super(Pinger, self).__init__()
        self.interval_sec = interval_sec
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.bind(('', 0))
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self.last_tx_bytes = 0

    def run(self):
        while self.interval_sec >= 5:
            if not os.path.isfile(Pinger.CAT_PPP0_TX_STAT):
                time.sleep(self.interval_sec)
                continue
            try:
                self.tx_bytes = subprocess.Popen(Pinger.CAT_PPP0_TX_STAT,
                                                 shell=True,
                                                 stdout=subprocess.PIPE
                                                 ).stdout.read()
                if int(self.tx_bytes) != self.last_tx_bytes:
                    self.socket.sendto('',
                                       (Pinger.DEST_ADDR, Pinger.DEST_PORT))
                    time.sleep(self.interval_sec)
                    self.last_tx_bytes = int(self.tx_bytes)
            except Exception:
                time.sleep(self.interval_sec)
                pass


class Monitor(threading.Thread):
    FNULL = open(os.devnull, 'w')

    def __init__(self, nic):
        super(Monitor, self).__init__()
        self.nic = nic

    def terminate(self):
        if os.path.isfile(shutdown_state_file):
            return False
        logger.error("CANDY Pi Lite modem is terminated. Shutting down.")
        # exit from non-main thread
        os.kill(os.getpid(), signal.SIGTERM)
        return True

    def run(self):
        global online
        while True:
            try:
                err = subprocess.call("ip link show %s" % self.nic,
                                      shell=True,
                                      stdout=Monitor.FNULL,
                                      stderr=subprocess.STDOUT)
                online = (err == 0)
                if not online:
                    time.sleep(5)
                    continue

                err = subprocess.call("ip route | grep default | grep -v %s" %
                                      self.nic, shell=True,
                                      stdout=Monitor.FNULL,
                                      stderr=subprocess.STDOUT)
                if err == 0:
                    ls_nic_cmd = ("ip route | grep default | grep -v %s " +
                                  "| tr -s ' ' | cut -d ' ' -f 5") % self.nic
                    ls_nic = subprocess.Popen(ls_nic_cmd,
                                              shell=True,
                                              stdout=subprocess.PIPE
                                              ).stdout.read()
                    logger.debug("ls_nic => %s" % ls_nic)
                    for nic in ls_nic.split("\n"):
                        if nic:
                            ip_cmd = ("ip route | grep %s " +
                                      "| awk '/default/ { print $3 }'") % nic
                            ip = subprocess.Popen(ip_cmd, shell=True,
                                                  stdout=subprocess.PIPE
                                                  ).stdout.read()
                            subprocess.call("ip route del default via %s" % ip,
                                            shell=True)
                time.sleep(5)

            except Exception:
                logger.error("Error on monitoring")
                if not self.terminate():
                    continue


def delete_sock_path(sock_path):
    # remove sock_path
    try:
        os.unlink(sock_path)
    except OSError:
        if os.path.exists(sock_path):
            raise


def resolve_version():
    if 'VERSION' in os.environ:
        return os.environ['VERSION']
    return 'N/A'


def resolve_boot_apn():
    dir = os.path.dirname(os.path.abspath(__file__))
    apn_json = dir + '/boot-apn.json'
    if not os.path.isfile(apn_json):
        return None
    with open(apn_json) as apn_creds:
        apn = json.load(apn_creds)
    if 'PRESERVE_APN' not in os.environ or os.environ['PRESERVE_APN'] != '1':
        os.remove(apn_json)
    else:
        logger.info('Preserving the APN file[%s]' % apn_json)
    return apn


def candy_command(category, action, serial_port, baudrate,
                  sock_path='/var/run/candy-board-service.sock'):
    delete_sock_path(sock_path)
    atexit.register(delete_sock_path, sock_path)

    serial = candy_board_qws.SerialPort(serial_port, baudrate)
    server = candy_board_qws.SockServer(resolve_version(),
                                        resolve_boot_apn(),
                                        sock_path, serial)
    args = {}
    try:
        args = json.loads(action)
    except ValueError:
        args['action'] = action
    args['category'] = category
    ret = server.perform(args)
    logger.debug("candy_command() : %s:%s => %s" %
                 (category, args['action'], ret))
    sys.exit(json.loads(ret)['status'] != 'OK')


def blinky():
    global led, led_sec, online
    if not online:
        led = 1
    led = 0 if led != 0 else 1
    if led == 0:
        subprocess.call("echo %d > /sys/class/gpio/%s/value" % (led, LED),
                        shell=True, stdout=Monitor.FNULL,
                        stderr=subprocess.STDOUT)
        threading.Timer(led_sec, blinky, ()).start()
    else:
        subprocess.call("echo %d > /sys/class/gpio/%s/value" % (1, LED),
                        shell=True, stdout=Monitor.FNULL,
                        stderr=subprocess.STDOUT)
        time.sleep(led_sec / 3)
        subprocess.call("echo %d > /sys/class/gpio/%s/value" % (0, LED),
                        shell=True, stdout=Monitor.FNULL,
                        stderr=subprocess.STDOUT)
        time.sleep(led_sec / 3)
        subprocess.call("echo %d > /sys/class/gpio/%s/value" % (1, LED),
                        shell=True, stdout=Monitor.FNULL,
                        stderr=subprocess.STDOUT)
        threading.Timer(led_sec / 3, blinky, ()).start()


def server_main(serial_port, bps, nic,
                sock_path='/var/run/candy-board-service.sock'):
    delete_sock_path(sock_path)
    atexit.register(delete_sock_path, sock_path)

    logger.debug("server_main() : Setting up SerialPort...")
    serial = candy_board_qws.LazySerialPort(serial_port, bps)
    logger.debug("server_main() : Setting up SockServer...")
    server = candy_board_qws.SockServer(resolve_version(),
                                        resolve_boot_apn(),
                                        sock_path, serial)
    if 'DEBUG' in os.environ and os.environ['DEBUG'] == "1":
        server.debug = True

    if 'BLINKY' in os.environ and os.environ['BLINKY'] == "1":
        logger.debug("server_main() : Starting blinky timer...")
        blinky()
    logger.debug("server_main() : Setting up Monitor...")
    monitor = Monitor(nic)
    logger.debug("server_main() : Setting up Pinger...")
    pinger = Pinger(PPP_PING_INTERVAL_SEC)

    logger.debug("server_main() : Starting SockServer...")
    server.start()
    logger.debug("server_main() : Starting Monitor...")
    monitor.start()
    logger.debug("server_main() : Starting Pinger...")
    pinger.start()

    logger.debug("server_main() : Joining Monitor thread into main...")
    monitor.join()
    logger.debug("server_main() : Joining Pinger thread into main...")
    pinger.join()
    logger.debug("server_main() : Joining SockServer thread into main...")
    server.join()


if __name__ == '__main__':
    if len(sys.argv) < 4:
        logger.error("The Network Interface isn't ready. " +
                     "Shutting down.")
    elif len(sys.argv) > 4:
        candy_command(
            sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    else:
        logger.info("serial_port:%s (%s bps), nic:%s" %
                    (sys.argv[1], sys.argv[2], sys.argv[3]))
        try:
            server_main(sys.argv[1], sys.argv[2], sys.argv[3])
        except KeyboardInterrupt:
            pass
