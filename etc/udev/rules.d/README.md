udev rules
===

## Quectel UC20 and EC21

`99-qws-usb-serial.rules` creates the following aliases when you connect UC20 and/or EC21 to Raspberry Pi via USB.

- `/dev/QWS.UC20.AT` ... AT command interface for UC20
- `/dev/QWS.UC20.MODEM` ... MODEM interface for UC20
- `/dev/QWS.EC21.AT` ... AT command interface for EC21
- `/dev/QWS.EC21.MODEM` ... MODEM command interface for EC21

## EnOcean USB Dongle

`70-enocean-stick.rules` creates the following alias when EnOcean USB Gateway is inserted to Raspberry Pi.

- `/dev/enocean` ... EnOcean Serial Port

This rule doesn't expect 2 or more USB Gateways are connected to the same Raspberry Pi.

Supported USB Gateways are

1. USB 300
1. USB 400J

## Fixed network interface name for RPi

`76-rpi-ether-netnames.rules` assigns the fixed nic name `rpi-eth` to the primary ethernet network interface.
