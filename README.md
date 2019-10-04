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
