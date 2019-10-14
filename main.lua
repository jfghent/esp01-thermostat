require("mcp9808")

wifi_state = "X"
mqtt_connected = false
thermostat_state = "Idle"
fan_state = 0
fan_indicator = " "
set_temp = 70 --default, safe temp
therm_mode = -1 --0=cool, 1=heat, -1=not set
cool_on_offset = 1 --added to set_temp to prevent over-cycling
cool_off_offset = 0.5 --subtracted from set_temp to prevent over-cycling
heat_on_offset = 1 --subtracted from set_temp to prevent over-cycling
heat_off_offset = 0.5 --added to set_temp to prevent over-cycling
tempF = 0
tempC = 0
run_delay = true

output_register_curr = 0x00 --all off

fan_on = 0xBF --bit 6  --0x04 --bit 2 0x08 --bit 3, 0x10 --bit 4
heat_on = 0xDF --bit 5    ----0x02 -- bit 1
cool_on = 0xEF --bit 4    ----0x01 -- bit 0
--heat_cool_off = 0xFC --bit.band(0xFF,bit.bnot(bit.band(heat_on,cool_on)))
heat_cool_off = 0x70 --bit.bxor(0xFF,bit.band(heat_on,cool_on))

function initI2C()
   local sda = 3 -- GPIO2
   local scl = 4 -- GPIO0
   --local sla = 0x3c
   i2c.setup(0, sda, scl, i2c.SLOW)
end

function initDisplay()
   --print("initializing display")
   
   disp = u8g2.ssd1306_i2c_128x64_noname(0,0x3c)
   disp:setFont(u8g2.font_6x10_tf)  
   disp:setContrast(254)
   --disp:setColorIndex(1)   
   --disp:setRot180() 
   --print("display initialized")
end

function start_run_delay()
    run_delay = true
    tmr.create():alarm(60000, tmr.ALARM_SINGLE, function()
        run_delay = false
    end)
    thermostat_state = thermostat_state .." DLY"
end

function updateTemp()
    --read temp
    tempC = mcp9808.read_temperature()
    --convert to F
    tempF = tempC * 9 / 5 + 32

    if therm_mode == 0 then --cooling
        if tempF > (set_temp + cool_on_offset) and not run_delay then
            thermostat_state = "Cool ON"
            output_register_curr = bit.bor(output_register_curr,heat_cool_off)
            output_register_curr = bit.band(output_register_curr,cool_on)
            write_pcf8574(output_register_curr)
            running = true
        elseif tempF <= (set_temp - cool_off_offset) and not run_delay then
            thermostat_state = "Cool"
            --write_pcf8574(0xFE)
            print("output_register_curr: " .. output_register_curr)
            print("heat_cool_off: " .. heat_cool_off)
            output_register_curr = bit.bor(output_register_curr,heat_cool_off)
            write_pcf8574(output_register_curr)
            if running then
                start_run_delay()
            end
            running = false
        end
    elseif therm_mode == 1 then --heating
        if tempF < (set_temp - heat_on_offset) and not run_delay then
            thermostat_state = "Heat ON"
            output_register_curr = bit.bor(output_register_curr,heat_cool_off)
            output_register_curr = bit.band(output_register_curr,heat_on)
            write_pcf8574(output_register_curr)
            running = true
         elseif tempF >= (set_temp + heat_off_offset) and not run_delay then
            thermostat_state = "Heat"
            output_register_curr = bit.bor(output_register_curr,heat_cool_off)
            write_pcf8574(output_register_curr)
            if running then
                start_run_delay()
            end
            running = false
        end
    else
        thermostat_state = "Wait"
        output_register_curr = bit.bor(output_register_curr,heat_cool_off)
        write_pcf8574(output_register_curr)
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
    disp:sendBuffer()

end

function read_pcf8574(dev_addr)
     --i2c.start(0)
     i2c.address(0, 0x20 , i2c.RECEIVER)
     bdata = i2c.read(busid,1)  -- Reads one byte
     --i2c.stop(busid)
     return bdata
end

function write_pcf8574(value)
     --print("Writing Output: " .. value)
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
station_cfg.ssid="TreeHouse"

file.open("pw.cfg","r")
station_cfg.pwd=file.read(file.stat("pw.cfg").size-1) -- need the -1 otherwise it returns an EOL character in addition to the text
file.close()
--station_cfg.pwd="ropeladder"
print("WiFi Password: " .. station_cfg.pwd)
station_cfg.auto=true
station_cfg.save=false
station_cfg.connected_cb=function() end --print("Wifi connected") end
station_cfg.got_ip_cb=function() 
    --print("IP assigned")
    wifi_state = "i"
    update_display()
    mqtt_connect()
    end

function mqtt_connect()
    if mqtt_connected then return end
    m:close()
    if(m:connect("192.168.1.46",1885,
        function(client) 
            print("mqtt connected")
            mqtt_connected = true
            client:subscribe("home/command/climate/zone3/#", 0, 
                function(client) 
                    wifi_state = "W"
                    print("subscribe success") 
            end)
            client:publish("home/climate/zone3/status/state","online",0,0)
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

m = mqtt.Client("ThermostatZone3",120)

m:on("connect", function(client) print("mqtt connected_") end)
m:on("offline", function(client) wifi_state = "i" print("mqtt offline") mqtt_connected = false end)

m:on("message", function(client,topic,data)
    
    print(topic .. ":")
    if data ~= nil then
        print(data)
    end
    
    if topic=="home/command/climate/zone3/set_temp" then
        set_temp = tonumber(data)
    elseif topic=="home/command/climate/zone3/set_mode" then
        if data == "cool" then
            therm_mode = 0
        elseif data == "heat" then
            therm_mode = 1
        else
            therm_mode = -1
        end
    elseif topic=="home/command/climate/zone3/display_brightness" then
        disp:setContrast(tonumber(data))
    elseif topic=="home/command/climate/zone3/fan" then
        if data == "on" then
            fan_state = 1
            fan_indicator = "F"
            output_register_curr = bit.bor(output_register_curr,fan_on)
            write_pcf8574(output_register_curr)
        else 
            fan_state = 0 
            fan_indicator = " "
            output_register_curr = bit.band(output_register_curr,bit.bnot(fan_on))
            write_pcf8574(output_register_curr)
        end
    end
    config_save()
end)

function config_save()
    print("Saving config")
    print("   therm_mode: " .. therm_mode)
    print("   set_temp: " .. set_temp)
    
    file.open('mode.cfg',"w+")
    file.write(tostring(therm_mode).." ")
    file.flush()
    file.close()
    
    file.open("temp.cfg","w+")
    file.write(tostring(set_temp).." ")
    file.flush()
    file.close()
end

function config_load()
    if file.open("temp.cfg","r") then 
        set_temp = tonumber(file.readline())
        file.close()
    end
    if file.open("mode.cfg","r") then
        therm_mode = tonumber(file.readline())
        file.close()
    end
end

config_load()
start_run_delay()


tmr.create():alarm(4000, tmr.ALARM_AUTO, function()
  update_display()
  updateTemp()
  --m:publish("home/state/climate/zone3/ambient_temp",string.format("%02d",tempF),0,0)
  --m:publish("home/state/climate/zone3/fan_state",fan_state,0,0)
  --m:publish("home/state/climate/zone3/cool_heat_mode",tostring(therm_mode),0,0)
  --m:publish("home/state/climate/zone3/run_state",thermostat_state,0,0)
  --m:publish("home/state/climate/zone3/set_temp",set_temp,0,0)
  if mqtt_connected then 
    m:publish("home/state/climate/zone3/all",string.format("%02d",tempF).."|"..set_temp.."|"..thermostat_state.."|"..tostring(therm_mode).."|"..tostring(fan_state), 0,0)
  else
    mqtt_connect()
  end    
  
end)
