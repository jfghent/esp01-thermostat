require("mcp9808")
require("param")

zone = 2
mqtt_host = "192.168.1.46"
mqtt_port = 1885

mqtt_cmd_path = "home/command/climate/zone"..zone
mqtt_state_path = "home/state/climate/zone"..zone

wifi_state = "X"
mqtt_connected = false
thermostat_state = "Idle"
fan_state = 0
fan_indicator = " "
set_temp = 70 --default, safe temp
therm_mode = -1 --0=cool, 1=heat, -1=not set
cool_on_offset = 2.0 
cool_off_offset = 2.0 
heat_on_offset = 2.0 
heat_off_offset = 2.0 
tempF = 0
tempC = 0
run_delay = true

output_register_curr = 0x70 --all off

fan_on = 0xEF --bit 4   
heat_on = 0xBF --bit 6  
cool_on = 0xDF --bit 5  
heat_cool_off = 0x60 

function initI2C()
   local sda = 3 -- GPIO2
   local scl = 4 -- GPIO0
    i2c.setup(0, sda, scl, i2c.SLOW)
end

function initDisplay()
   
   disp = u8g2.ssd1306_i2c_128x64_noname(0,0x3c)
   disp:setFont(u8g2.font_6x10_tf)  
   local brt = load_param("bright")
   if not brt then brt = 254 end
   disp:setContrast(brt)

end

function start_run_delay()
    run_delay = true
    tmr.create():alarm(60000, tmr.ALARM_SINGLE, function()
        run_delay = false
    end)
    thermostat_state = "DLY"
end

function start_cooling()
    thermostat_state = "Cool ON"
    output_register_curr = bit.bor(output_register_curr,heat_cool_off)
    output_register_curr = bit.band(output_register_curr,cool_on)
    write_pcf8574(output_register_curr)
    running = true
end

function stop_cooling()
    thermostat_state = "Cool"
    output_register_curr = bit.bor(output_register_curr,heat_cool_off)
    write_pcf8574(output_register_curr)
    if running then
        start_run_delay()
    end
    running = false
end

function start_heating()
    thermostat_state = "Heat ON"
    output_register_curr = bit.bor(output_register_curr,heat_cool_off)
    output_register_curr = bit.band(output_register_curr,heat_on)
    write_pcf8574(output_register_curr)
    running = true
end

function stop_heating()
    thermostat_state = "Heat"
    output_register_curr = bit.bor(output_register_curr,heat_cool_off)
    write_pcf8574(output_register_curr)
    if running then
        start_run_delay()
    end
    running = false
end


function updateTemp()
    --read temp
    tempC = mcp9808.read_temperature()
    --convert to F
    tempF = tempC * 9 / 5 + 32
    
    if run_delay then return end
    
    if therm_mode == 0 then --cooling
        if not running and tempF > (set_temp + cool_on_offset) then
            start_cooling()
        elseif running and tempF <= (set_temp - cool_off_offset) then
            stop_cooling()
        end
    elseif therm_mode == 1 then --heating
        if not running and tempF < (set_temp - heat_on_offset) then
            start_heating()
         elseif running and tempF >= (set_temp + heat_off_offset) then
            stop_heating()
        end
    else
        thermostat_state = "Wait"
        output_register_curr = bit.bor(output_register_curr,heat_cool_off)
        write_pcf8574(output_register_curr)
        running = false
    end

end

function update_display()

    --write to display
    disp:clearBuffer()
    disp:setFont(u8g2.font_fub35_tn)
    disp:drawStr(64,60,string.format("%02d",tempF))
    disp:setFont(u8g2.font_6x10_tf) 
    disp:drawStr(1,8,"Set: " .. set_temp .. " " .. wifi_state .. " ".. fan_indicator)
    disp:drawStr(80,8,thermostat_state)
    disp:drawStr(1,32,"Current")
    disp:drawStr(1,40,"  Temp:")
    disp:drawStr(1,64,zone)
    disp:sendBuffer()

end

function read_pcf8574(dev_addr)
     
     i2c.address(0, 0x20 , i2c.RECEIVER)
     bdata = i2c.read(busid,1)  
     
     return bdata
end

function write_pcf8574(value)
     
     i2c.start(0)
     i2c.address(0, 0x20, i2c.TRANSMITTER)
     i2c.write(0,value)
     i2c.stop(0)
end


initI2C()
initDisplay()
update_display()
write_pcf8574(0xFF)

wifi.sta.disconnect()

station_cfg={}
--station_cfg.ssid="TreeHouse"

station_cfg.ssid = load_param("ssid")
station_cfg.pwd = load_param("pwd")
--file.open("pw.cfg","r")
--station_cfg.pwd=file.read(file.stat("pw.cfg").size-1) 
--file.close()
print("ssid:" .. station_cfg.ssid)
print("pw: " .. station_cfg.pwd)
station_cfg.auto=true
station_cfg.save=false
station_cfg.connected_cb=function() end 
station_cfg.got_ip_cb=function() 
    wifi_state = "i"
    update_display()
    mqtt_connect()
    end

function mqtt_connect()
    if mqtt_connected then return end
    m:close()
    if(m:connect(mqtt_host,mqtt_port,
        function(client) 
            print("mqtt connected")
            mqtt_connected = true
            client:subscribe(mqtt_cmd_path.."/#", 0, 
                function(client) 
                    wifi_state = "W"
                    print("subscribe success") 
            end)
            client:publish(mqtt_state_path.."/state","online",0,0)
        end, 
        function(client, reason) 
            print("connection failed")
            mqtt_connected = false
        end)) then
        print("m:connect returned success")
    else
        print("m:connect returned failure")
    end 
end

wifi.setmode(wifi.STATION)

wifi.sta.config(station_cfg)

m = mqtt.Client("ThermostatZone"..zone,120)

m:on("connect", function(client) print("mqtt connected_") end)
m:on("offline", function(client) wifi_state = "i" print("mqtt offline") mqtt_connected = false end)

m:on("message", function(client,topic,data)
    
    print(topic .. ":")
    if data ~= nil then
        print(data)
    end
    
    if topic==mqtt_cmd_path.."/set_temp" then
        set_temp = tonumber(data)
        save_param("temp",set_temp)
    elseif topic==mqtt_cmd_path.."/set_mode" then
        if data == "cool" then
            therm_mode = 0
        elseif data == "heat" then
            therm_mode = 1
        else
            therm_mode = -1
        end
        save_param("mode",therm_mode)
    elseif topic==mqtt_cmd_path.."/display_brightness" then
        disp:setContrast(tonumber(data))
        save_param("bright",data)
    elseif topic==mqtt_cmd_path.."/fan" then
        print("output register 1:" .. output_register_curr)
        if data == "on" then
            fan_state = 1
            fan_indicator = "F"
            output_register_curr = bit.band(output_register_curr,fan_on)
            print("output register 2:" .. output_register_curr)
            write_pcf8574(output_register_curr)
        else 
            fan_state = 0 
            fan_indicator = " "
            output_register_curr = bit.bor(output_register_curr,bit.band(0xFF,bit.bnot(fan_on)))
            print("output register 3:" .. output_register_curr)
            write_pcf8574(output_register_curr)
        end
    elseif topic == mqtt_cmd_path.."/cool_on_swing" then
        cool_on_offset = tonumber(data) --added to set_temp to prevent over-cycling
        save_param("swing_cool_on",cool_on_offset)
    elseif topic == mqtt_cmd_path.."/cool_off_swing" then
        cool_off_offset = tonumber(data) --subtracted from set_temp to prevent over-cycling
        save_param("swing_cool_off",cool_off_offset)
    elseif topic == mqtt_cmd_path.."/heat_on_swing" then
        heat_on_offset = tonumber(data) --subtracted from set_temp to prevent over-cycling
        save_param("swing_heat_on",heat_on_offset)
    elseif topic == mqtt_cmd_path.."/heat_off_swing" then
        heat_off_offset = tonumber(data) --added to set_temp to prevent over-cycling    
        save_param("swing_heat_off",heat_off_offset)
    end
    --config_save()
end)

function config_load()
    set_temp = load_param("temp")
    therm_mode = load_param("mode")
    cool_on_offset = load_param("swing_cool_on")
    cool_off_offset = load_param("swing_cool_off")
    heat_on_offset = load_param("swing_heat_on")
    heat_off_offset = load_param("swing_heat_off")
    
end

config_load()
start_run_delay()


tmr.create():alarm(4000, tmr.ALARM_AUTO, function()
  update_display()
  updateTemp()
  if mqtt_connected then
    data_string = string.format("%.1f",tempF)
    data_string = data_string.."|"..set_temp.."|"..thermostat_state.."|"..tostring(therm_mode).."|"..tostring(fan_state)
    data_string = data_string.."|"..tostring(cool_on_offset).."|"..tostring(cool_off_offset).."|"..tostring(heat_on_offset).."|"..tostring(heat_off_offset)
    m:publish(mqtt_state_path.."/all",data_string,0,0) --"home/state/climate/zone3/all",data_string,0,0)
  else
    mqtt_connect()
  end    
  
end)
