# esp01-thermostat
esp01 based wireless thermostat for use in home automation using MQTT

Features:

* Uses ESP-01S to integrate several simple devices and libraries to function as a residential heat/cool thermostat.
* Connects by WiFi to an MQTT host
* Heat/Cool mode and temperature setting controlled via MQTT
* Features an lcd dispaly of temp, set temp, and current state
* Retains settings in memory in case of power cycle
* Incorporates a delay to prevent over cycling of HVAC system


TODO:

* Code clean-up. This was hacked together with no thoughts for speed, size, or extensibility.
* Develop push-button controls for direct hardware control.

Other notes:

* **main.lua** - main execution code for thermostat
* **mcp9808.lua** - ported library from Owain Martin adapted for use in
the version of lua that is used by Node MCU (see below) (also, sorry
Owain, I can't find where I originally downloaded this else I'd link it)
* **init.lua** - file that launches
main.lua (no brainer)

* **nodemcu-master-12-modules-2019-09-01-01-53-09-float.bin** - the
firmware compiled using https://nodemcu-build.com/

Below is the output of NodeMCU on cold boot:

>NodeMCU custom build by frightanic.com
>	branch: master
>	commit: >68c425c0451f72fcabb1b2d6d31a8555f087371b
>	SSL: false
>	modules:
>bit,dht,file,gpio,i2c,mqtt,net,node,tmr,u8g2,uart,wifi
> build created on 2019-09-01 01:52
> powered by Lua 5.1.4 on SDK 2.2.1(6ab97e9)
>

Other notes:

Here is the command used to upload the firmware from a linux command
line using esptool.py:

>esptool.py --port /dev/ttyUSB0 --baud 115200 -->trace --chip esp8266 write_flash --erase-all -->flash_freq 26m --flash_mode dout --flash_size 1MB --no-compress 0x00000 nodemcu-master-12-modules-2019-09-01-01-53-09-float.bin

