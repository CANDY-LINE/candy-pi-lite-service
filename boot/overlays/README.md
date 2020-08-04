Device Tree for SC16IS750 & SC16IS752
===

The compiled dtbo file will allocate serial UART interfaces to `/dev/ttySC0` and `/dev/ttySC1` (SC16IS752 only).

- [RPi] sc16is752-spi0-ce1.dts for SC16IS752 via SPI0 with CE/CS=1
- [ATB] sc16is752-spi2-ce1-atb.dts for SC16IS752 via SPI2 with CE/CS=1

Annotations:
 - [RPi] ... For Raspberry Pi
 - [ATB] ... For ASUS Tinker Board

References:

- [SC16IS752 SPI0 CE0 DTS for Raspberry Pi Linux](https://github.com/raspberrypi/linux/blob/rpi-5.4.y/arch/arm/boot/dts/overlays/sc16is752-spi0-overlay.dts)
