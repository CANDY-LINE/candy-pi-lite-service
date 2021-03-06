# -*- coding: utf-8 -*-

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
from datetime import datetime
import time
import subprocess
import atexit
import re
import candy_board_qws
import logging
import logging.handlers
from croniter import croniter

# sys.argv[0] ... Serial Port
# sys.argv[1] ... The path to socket file,
#                 e.g. /var/run/candy-board-service.sock
# sys.argv[2] ... The network interface name to be monitored

LED = 'gpio%s' % (os.environ['LED2'] if 'LED2' in os.environ else '4')
PIDFILE = '/var/run/candy-pi-lite-service.pid'
logger = logging.getLogger('candy-pi-lite')
logger.setLevel(logging.INFO)
handler = logging.handlers.SysLogHandler(address='/dev/log')
logger.addHandler(handler)
formatter = logging.Formatter('candy-pi-lite: %(module)s.%(funcName)s: %(message)s')
handler.setFormatter(formatter)
led_sec = float(os.environ['BLINKY_INTERVAL_SEC']) \
    if 'BLINKY_INTERVAL_SEC' in os.environ else 1.0
if led_sec < 0 or led_sec > 60:
    led_sec = 1.0
BLINKY_PATTERN = {
    True:  [1, 1, 1, 1, 0, 0],  # for USB Serial Connection
    False: [1, 0, 1, 0, 0, 0]   # for UART Serial Connection
}
DISABLE_DEFAULT_ROUTE_ADJUSTER = \
    int(os.environ['DISABLE_DEFAULT_ROUTE_ADJUSTER']) \
    if 'DISABLE_DEFAULT_ROUTE_ADJUSTER' in os.environ else 0
PPP_PING_INTERVAL_SEC = float(os.environ['PPP_PING_INTERVAL_SEC']) \
    if 'PPP_PING_INTERVAL_SEC' in os.environ else 0.0
PPP_PING_OFFLINE_THRESHOLD = float(os.environ['PPP_PING_OFFLINE_THRESHOLD']) \
    if 'PPP_PING_OFFLINE_THRESHOLD' in os.environ else 0.0
PPP_PING_TYPE = os.environ['PPP_PING_TYPE'] \
    if 'PPP_PING_TYPE' in os.environ else ''
PPP_PING_DESTINATION = os.environ['PPP_PING_DESTINATION'] \
    if 'PPP_PING_DESTINATION' in os.environ else ''
PPP_PING_IP_VERSION = int(os.environ['PPP_PING_IP_VERSION']) \
    if 'PPP_PING_IP_VERSION' in os.environ else 4
PPP_PING_RESTART_IF_OFFLINE = int(os.environ['PPP_PING_RESTART_IF_OFFLINE']) \
    if 'PPP_PING_RESTART_IF_OFFLINE' in os.environ else 0
online = False
offline_since = time.time()
OFFLINE_PERIOD_SEC = float(os.environ['OFFLINE_PERIOD_SEC']) \
    if 'OFFLINE_PERIOD_SEC' in os.environ else 30.0
shutdown_state_file = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                   '__shutdown')
pppd_exit_code_file = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                   '__pppd_exit_code')
ip_reachable_file = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                 '__ip_reachable')
PID = str(os.getpid())
BUTTON_EXT = int(os.environ['BUTTON_EXT']) \
    if 'BUTTON_EXT' in os.environ else 0
BUTTON_LED = '%s/value' % os.environ['BUTTON_LED_PIN']
BUTTON_IN = '%s/value' % os.environ['BUTTON_IN_PIN']

class Pinger(threading.Thread):
    DEST_ADDR = '<broadcast>'
    DEST_PORT = 60100

    def __init__(self, ping_interval_sec, ping_type, nic,
                 ping_destination, ping_ip_version, ping_offline_threshold):
        super(Pinger, self).__init__()
        self.nic = nic
        self.ping_interval_sec = ping_interval_sec
        self.ping_type = ping_type
        if self.ping_type == 'RETAIN':
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.socket.bind(('', 0))
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            self.last_tx_bytes = 0
            self.cat_tx_stat = ('cat /sys/class/net/%s/statistics/tx_bytes' %
                                self.nic)
        elif self.ping_type == 'TEST':
            self.ping_destination = ping_destination
            self.ping_ip_version = ping_ip_version
            self.ping_offline_threshold = ping_offline_threshold
            self.offline_since = 0

    def _run_retain(self):
        while self.ping_interval_sec >= 5:
            if not os.path.isfile(self.cat_tx_stat):
                time.sleep(self.ping_interval_sec)
                continue
            try:
                self.tx_bytes = subprocess.Popen(self.cat_tx_stat,
                                                 shell=True,
                                                 stdout=subprocess.PIPE
                                                 ).stdout.read().decode()
                if int(self.tx_bytes) != self.last_tx_bytes:
                    self.socket.sendto('',
                                       (Pinger.DEST_ADDR, Pinger.DEST_PORT))
                    time.sleep(self.ping_interval_sec)
                    self.last_tx_bytes = int(self.tx_bytes)
            except Exception:
                time.sleep(self.ping_interval_sec)
                pass

    def _run_test(self):
        atexit.register(delete_path, ip_reachable_file)
        while self.ping_interval_sec >= 5:
            err = subprocess.call("ping -%s -c 1 -I %s -W 5 -s 1 %s" %
                                  (self.ping_ip_version, self.nic,
                                   self.ping_destination),
                                  shell=True,
                                  stdout=Monitor.FNULL,
                                  stderr=subprocess.STDOUT)
            if err == 0:
                if self.offline_since > 0:
                    logger.info("[NOTICE] <candy-pi-lite> back to onlne")
                self.offline_since = 0
                if not os.path.isfile(ip_reachable_file):
                    open(ip_reachable_file, 'a').close()
            else:
                logger.warn("[NOTICE] <candy-pi-lite> IP unreachable")
                if self.offline_since == 0:
                    self.offline_since = datetime.now()
                else:
                    diff = (datetime.now() - self.offline_since)
                    if diff.total_seconds() > self.ping_offline_threshold:
                        delete_path(ip_reachable_file)
                        if PPP_PING_RESTART_IF_OFFLINE:
                            self.restart()
                        return
            time.sleep(self.ping_interval_sec)

    def run(self):
        if self.ping_type == 'RETAIN':
            self._run_retain()
        elif self.ping_type == 'TEST':
            self._run_test()
        else:
            pass

    def restart(self):
        if os.path.isfile(shutdown_state_file):
            return False
        # exit from non-main thread
        logger.error(
            "[NOTICE] <candy-pi-lite> RESTARTING SERVICE (IP Unreachable)")
        os.kill(os.getpid(), signal.SIGHUP)
        return True


class Monitor(threading.Thread):
    FNULL = open(os.devnull, 'w')

    def __init__(self, nic):
        super(Monitor, self).__init__()
        self.nic = nic
        try:
            self.restart_at = None
            base = datetime.now()
            cron = croniter(os.environ['RESTART_SCHEDULE_CRON'], base) \
                if 'RESTART_SCHEDULE_CRON' in os.environ else None
            if cron:
                self.restart_at = cron.get_next(datetime)
                if (self.restart_at - datetime.now()).total_seconds() < 60:
                    self.restart_at = cron.get_next(datetime)
                logger.info(
                    "[NOTICE] <candy-pi-lite> Will restart around %s %s" %
                    (self.restart_at.strftime('%Y-%m-%dT%H:%M:%S'),
                     time.strftime('%Z')))
        except Exception:
            logger.warn("[NOTICE] <candy-pi-lite> " +
                        "RESTART_SCHEDULE_CRON=>[%s] is ignored" %
                        os.environ['RESTART_SCHEDULE_CRON'])

    def terminate_with_service_restart(self):
        if os.path.isfile(shutdown_state_file):
            return False
        # exit from non-main thread
        logger.error("[NOTICE] <candy-pi-lite> RESTARTING SERVICE")
        os.kill(os.getpid(), signal.SIGHUP)
        return True

    def terminate_with_reconnect(self):
        if os.path.isfile(shutdown_state_file):
            return False
        # exit from non-main thread
        logger.error("[NOTICE] <candy-pi-lite> RECONNECTING")
        os.kill(os.getpid(), signal.SIGUSR1)
        return True

    def terminate(self):
        if os.path.isfile(shutdown_state_file):
            return False
        # exit from non-main thread
        logger.error("[NOTICE] <candy-pi-lite> SHUTTING DOWN")
        os.kill(os.getpid(), signal.SIGTERM)
        return True

    def time_to_restart(self):
        if self.restart_at is None:
            return False
        return self.restart_at <= datetime.now()

    def ls_nic(self, ipv, position):
        ls_nic_cmd = ("ip -%s route | grep default | grep -v %s "
                      "| tr -s ' ' | cut -d ' ' -f %d"
                      ) % (ipv, self.nic, position)
        ls_nic = subprocess.Popen(ls_nic_cmd,
                                  shell=True,
                                  stdout=subprocess.PIPE
                                  ).stdout.read().decode()
        return ls_nic

    def del_default(self, ipv):
        if DISABLE_DEFAULT_ROUTE_ADJUSTER:
            return
        err = subprocess.call("ip -%s route | grep default | grep -v %s" %
                              (ipv, self.nic), shell=True,
                              stdout=Monitor.FNULL,
                              stderr=subprocess.STDOUT)
        if err == 0:
            ls_nic = self.ls_nic(ipv, 5)
            if ls_nic[0:6] == 'kernel':
                ls_nic = self.ls_nic(ipv, 3)
            logger.debug("ipv => [%s] : ls_nic => [%s]" % (ipv, ls_nic))
            for nic in ls_nic.split("\n"):
                if nic:
                    ip_cmd = ("ip -%s route | grep %s "
                              "| awk '/default/ { print $2,$3 }'") % (ipv, nic)
                    ip_cmd_out = subprocess.Popen(ip_cmd, shell=True,
                                                  stdout=subprocess.PIPE
                                                  ).stdout.read().decode().split(' ')
                    prop = ip_cmd_out[0]
                    if prop == 'via':
                        ip = ip_cmd_out[1]
                        subprocess.call("ip -%s route del default via %s" %
                                        (ipv, ip),
                                        shell=True)

        ip_cmd = ("ip -%s route | grep %s "
                  "| awk '{ print $9 }'"
                  ) % (ipv, self.nic)
        ip = subprocess.Popen(ip_cmd, shell=True,
                              stdout=subprocess.PIPE
                              ).stdout.read().decode()
        subprocess.call(
            "ip -%s route add default via %s" % (ipv, ip),
            shell=True,
            stdout=Monitor.FNULL,
            stderr=subprocess.STDOUT)

    def pppd_exited_unexpectedly(self):
        if not os.path.isfile(pppd_exit_code_file):
            return True
        with open(pppd_exit_code_file, 'r') as f:
            try:
                pid = int(f.read())
            except ValueError:
                pid = -1
        if pid != 5 and pid != 16:
            # 5=>Exit by poff, 16=>Exit by Modem hangup
            return True
        return False

    def pppd_exited_by_modem_hangup(self):
        if not os.path.isfile(pppd_exit_code_file):
            return False
        with open(pppd_exit_code_file, 'r') as f:
            try:
                pid = int(f.read())
            except ValueError:
                pid = -1
        if pid == 16:
            # 16=>Exit by Modem hangup
            return True
        return False

    def run(self):
        global online
        global offline_since
        while True:
            try:
                if self.time_to_restart() \
                  and self.terminate_with_service_restart():
                    return
                if not os.path.isfile(PIDFILE):
                    if self.terminate():
                        return
                err = subprocess.call("ip link show %s" % self.nic,
                                      shell=True,
                                      stdout=Monitor.FNULL,
                                      stderr=subprocess.STDOUT)
                was_online = online
                online = (err == 0)
                if not online:
                    if was_online:
                        online = False
                        offline_since = time.time()
                    elif time.time() - offline_since > OFFLINE_PERIOD_SEC:
                        if self.pppd_exited_unexpectedly() \
                          and self.terminate_with_service_restart():
                            return
                        elif self.pppd_exited_by_modem_hangup():
                            if self.terminate_with_reconnect():
                                return
                    time.sleep(5)
                    continue

                self.del_default('6')
                self.del_default('4')
                time.sleep(5)

            except Exception:
                logging.exception("Error on monitoring")
                if not self.terminate():
                    continue


class ButtonExtension(threading.Thread):
    def __init__(self, monitor):
        super(ButtonExtension, self).__init__()
        self.sequence = 0
        self.monitor = monitor

    def button_pushed(self):
        pushed = 0
        with open(BUTTON_IN, 'r') as f:
            pushed = int(f.read()) ^ 1
        return pushed

    def sequence_match(self, val):
        return self.sequence & val == val
    
    def eval_func(self):
        if self.sequence_match(0b11111111):
            logger.info(
                "Button Pushed for 8+ sec. Shutting down...")
            # 8+sec push down => halt
            self.halt()
    
    def halt(self):
        err = subprocess.call("halt",
                                shell=True,
                                stdout=Monitor.FNULL,
                                stderr=subprocess.STDOUT)
        if err == 0:
            logger.info("[NOTICE] <candy-pi-lite> Hating the system")
        else:
            logger.error("[NOTICE] <candy-pi-lite> Error while halting. Code:%d" % err)

    def run(self):
        while BUTTON_EXT == 1:
            try:
                self.sequence = (self.sequence << 1 & 0b1111111111) | self.button_pushed()
                self.eval_func()
                time.sleep(1)
            except Exception:
                logging.exception("Error on waiting for button input")
                if not os.path.isfile(shutdown_state_file):
                    continue
        logger.info('[NOTICE] <candy-pi-lite> Button Extension is terminated.')

def delete_path(file_path):
    # remove file_path
    path_list = [file_path]
    if type(file_path) is list:
        path_list = file_path
    for p in path_list:
        try:
            os.unlink(p)
        except OSError:
            if os.path.exists(p):
                raise


def resolve_version():
    if 'VERSION' in os.environ:
        return os.environ['VERSION']
    return 'N/A'


def candy_command(category, action, serial_port, baudrate,
                  sock_path='/var/run/candy-board-service.sock'):
    delete_path(sock_path)
    atexit.register(delete_path, sock_path)

    try:
        serial = candy_board_qws.SerialPort(serial_port, baudrate)
        server = candy_board_qws.SockServer(resolve_version(),
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
        print(ret)
        sys.exit(json.loads(ret)['status'] != 'OK')
    except Exception:
        sys.exit(1)


def blinky(*args):
    global led_sec, online
    if len(args) == 0:
        usbserial = False
    else:
        usbserial = args[0]
    if online:
        pattern = BLINKY_PATTERN[usbserial]
        separation = len(pattern)
        for l in pattern:
            subprocess.call("echo %d > /sys/class/gpio/%s/value" % (l, LED),
                            shell=True, stdout=Monitor.FNULL,
                            stderr=subprocess.STDOUT)
            time.sleep(led_sec / separation)
        threading.Timer(led_sec / separation, blinky, args).start()
    else:
        subprocess.call("echo %d > /sys/class/gpio/%s/value" % (0, LED),
                        shell=True, stdout=Monitor.FNULL,
                        stderr=subprocess.STDOUT)
        threading.Timer(led_sec, blinky, args).start()


def server_main(serial_port, bps, nic,
                sock_path='/var/run/candy-board-service.sock'):

    if os.path.isfile(PIDFILE):
        logger.error("[NOTICE] <candy-pi-lite> ALREADY RUNNING")
        sys.exit(1)
    with open(PIDFILE, 'w') as f:
        f.write(PID)
    delete_path(sock_path)

    logger.debug("server_main() : Setting up SerialPort...")
    serial = candy_board_qws.LazySerialPort(serial_port, bps)
    logger.debug("server_main() : Setting up SockServer...")
    server = candy_board_qws.SockServer(resolve_version(),
                                        sock_path, serial)
    if DISABLE_DEFAULT_ROUTE_ADJUSTER:
        logger.info(
            "[NOTICE] <candy-pi-lite> Will disable default route adjuster")

    if 'BLINKY' in os.environ and os.environ['BLINKY'] == "1":
        logger.debug("server_main() : Starting blinky timer...")
        if serial_port and serial_port.startswith('/dev/ttySC'):
            usbserial = False
        else:
            usbserial = True
        blinky(usbserial)
    logger.debug("server_main() : Setting up Monitor...")
    monitor = Monitor(nic)
    logger.debug("server_main() : Setting up Pinger...")
    pinger = Pinger(PPP_PING_INTERVAL_SEC, PPP_PING_TYPE, nic,
                    PPP_PING_DESTINATION, PPP_PING_IP_VERSION,
                    PPP_PING_OFFLINE_THRESHOLD)
    logger.debug("server_main() : Setting up ButtonExtension...")
    button_extension = ButtonExtension(monitor)

    logger.debug("server_main() : Starting SockServer...")
    server.start()
    logger.debug("server_main() : Starting Monitor...")
    monitor.start()
    logger.debug("server_main() : Starting Pinger...")
    pinger.start()
    logger.debug("server_main() : Starting ButtonExtension...")
    button_extension.start()

    logger.debug("server_main() : Joining ButtonExtension thread into main...")
    button_extension.join()
    logger.debug("server_main() : Joining Pinger thread into main...")
    pinger.join()
    logger.debug("server_main() : Joining Monitor thread into main...")
    monitor.join()
    logger.debug("server_main() : Joining SockServer thread into main...")
    server.join()


if __name__ == '__main__':
    if len(sys.argv) < 4:
        logger.error("[NOTICE] <candy-pi-lite> " +
                     "The Network Interface isn't ready. Shutting down.")
    elif len(sys.argv) > 4:
        candy_command(
            sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    else:
        logger.info("[NOTICE] <candy-pi-lite> " +
                    "serial_port:%s (%s bps), nic:%s" %
                    (sys.argv[1], sys.argv[2], sys.argv[3]))
        try:
            server_main(sys.argv[1], sys.argv[2], sys.argv[3])
        except KeyboardInterrupt:
            pass
