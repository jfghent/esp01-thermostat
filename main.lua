require("mcp9808")
require("param")
require("lcd")

print(node.heap())

zone = 1
--mqtt_host = "192.168.1.46"
--mqtt_port = 1885

mqtt_cmd_path = "home/command/climate/zone"..zone
mqtt_state_path = "home/state/climate/zone"..zone

m = mqtt.Client("ThermostatZone"..zone,120)

--wifi_state = "X"
mqtt_connected = false
--thermostat_state = "Boot"
--cycle_state = ""
--fan_state = 0
--fan_indicator = " "
set_temp = 70 --default, safe temp
therm_mode = -1 --0=cool, 1=heat, -1=not set
on_offset = 2.0 
off_offset = 2.0 
--tempF = 0
--tempC = 0
run_delay = true
tmr_delay = 60000

output_register_curr = 0x07 --all off --TODO: Read from PFC directly?

fan_on = 0xFE --bit 0   
--heat_on = 0xBF --bit 6  
--cool_on = 0xDF --bit 5  
--heat_cool_off = 0x60
running = false

print(node.heap())

function initI2C()
   local sda = 3 -- GPIO2
   local scl = 4 -- GPIO0
   i2c.setup(0, sda, scl, i2c.SLOW)
end

function start_run_delay()
    run_delay = true
    tmr.create():alarm(tmr_delay, tmr.ALARM_SINGLE, function()
        run_delay = false
        lcd.cycle_state("")
        --cycle_state = ""
    end)
    lcd.cycle_state("DLY")
end

function start_cycle(type)
    output_register_curr = bit.band(output_register_curr,type)
    write_pcf8574(output_register_curr)
    lcd.cycle_state("ON")
    running = true
end

function stop_cycle()
    set_heat_cool_off()
    if running then 
        start_run_delay() 
    elseif not run_delay then
        lcd.cycle_state("")    
    end
    running = false
end

function set_heat_cool_off()
    --print("output_register_curr: "..string.format("%02d",output_register_curr))
    output_register_curr = bit.bor(output_register_curr,0x06) --0b0000 0110 
    --print("output_register_curr: "..string.format("%02d",output_register_curr))
    write_pcf8574(output_register_curr)
    --print("IO write complete")
end

function set_therm_mode(tm)
    --print("turning everything off")
    stop_cycle()
    if tm == 0 then
        print("going to cool mode")
        therm_mode = tm
        set_temperature(param.load("ctemp"))
        on_offset = tonumber(param.load("swing_cool_on"))
        off_offset = tonumber(param.load("swing_cool_off"))
        --thermostat_state = "Cool"
        lcd.therm_state("Cool")
    elseif tm == 1 then
        print("going to heat mode")
        therm_mode = tm
        set_temperature(param.load("htemp"))
        on_offset = tonumber(param.load("swing_heat_on"))
        off_offset = tonumber(param.load("swing_heat_off"))
        --thermostat_state = "Heat"
        lcd.therm_state("Heat")
    else
        --print("invalid therm mode")
        therm_mode = -1
       --thermostat_state = "Idle"
       lcd.therm_state("Idle")
    end
    param.save("mode",tostring(therm_mode))
    --print("therm_mode = " .. tostring(therm_mode))
end

function updateTemp()
    --read temp
    local tempC = mcp9808.read_temperature()
    --convert to F
    local tempF = tempC * 1.8 + 32
    lcd.curr_temp(tempF)
    
    if therm_mode == 0 then --cooling
        if not running and not run_delay and tempF > (set_temp + on_offset) then
            start_cycle(0xFD)--cool_on) --0b1111 1101
        elseif running and tempF <= (set_temp - off_offset) then
            stop_cycle()
        end
    elseif therm_mode == 1 then --heating
        if not running and not run_delay and tempF < (set_temp - on_offset) then
            start_cycle(0xFB)--heat_on) --0b1111 1011
        elseif running and tempF >= (set_temp + off_offset) then
            stop_cycle()
        end
    else
        set_heat_cool_off()
        running = false
    end
    
    return tempF
end



--function read_pcf8574(dev_addr)
 --    i2c.address(0, 0x20 , i2c.RECEIVER)
--     bdata = i2c.read(busid,1)  
--     return bdata
--end

function write_pcf8574(value)
     i2c.start(0)
     i2c.address(0, 0x20, i2c.TRANSMITTER)
     i2c.write(0,value)
     i2c.stop(0)
end

function mqtt_connect()
    if mqtt_connected then return end
    m:close()
    if(m:connect("192.168.1.46","1885",
        function(client) 
            --print("mqtt connected")
            mqtt_connected = true
            lcd.wifi_state("W")
            client:subscribe(mqtt_cmd_path.."/#", 0, 
                function(client) 
                    --lcd.wifi_state("W")
                    --print("subscribe success") 
            end)
            --client:publish(mqtt_state_path.."/state","online",0,0)
        end, 
        function(client, reason) 
            --print("connection failed" .. reason)
            mqtt_connected = false
       end)) 
     then
       --print("m:connect returned success")
    else
        --print("m:connect returned failure")
    end 
end

function set_temperature(df)
    print("df = " .. df)
    set_temp = tonumber(df)
    print("set_temp = " .. string.format("%02d",set_temp))
    if therm_mode == 0 then
            --cool_temp = set_temp
       param.save("ctemp",df)
    elseif therm_mode == 1 then
          --heat_temp = set_temp
       param.save("htemp",df)
    end 
    lcd.set_temp(df)
end

m:on("connect", function(client)
    lcd.wifi_state("W")
    end)
m:on("offline", function(client) 
    lcd.wifi_state("w")
    --print("mqtt offline") 
    mqtt_connected = false 
    end)
m:on("message", function(client,topic,data)

    --debug
    print(topic .. ":")
    if data ~= nil then
        print(data)
    end
    --end debug
    
    if topic==mqtt_cmd_path.."/set_temp" then
        set_temperature(data)
    elseif topic==mqtt_cmd_path.."/set_mode" then
        if data == "cool" then --TODO: Maybe. Redefine this so client sends 0,1,-1 instead of plain text
            set_therm_mode(0)
        elseif data == "heat" then
           set_therm_mode(1)
        else
           set_therm_mode(-1)
        end
    elseif topic==mqtt_cmd_path.."/display_brightness" then
        disp:setContrast(tonumber(data))
        save_param("bright",data)
    --elseif topic==mqtt_cmd_path.."/fan" then
      --print("output register 1:" .. output_register_curr)
      --if data == "on" then
       --    fan_state = 1
        --    fan_indicator = "F"
        --    output_register_curr = bit.band(output_register_curr,fan_on)
        --    print("output register 2:" .. output_register_curr)
        --    write_pcf8574(output_register_curr)
        --else 
        --    fan_state = 0 
        --    fan_indicator = " "
        --    output_register_curr = bit.bor(output_register_curr,bit.band(0xFF,bit.bnot(fan_on)))
        --    print("output register 3:" .. output_register_curr)
        --    write_pcf8574(output_register_curr)
        --end
    elseif topic == mqtt_cmd_path.."/cool_on_swing" then
        param.save("swing_cool_on",data)
    elseif topic == mqtt_cmd_path.."/cool_off_swing" then
        param.save("swing_cool_off",data)
    elseif topic == mqtt_cmd_path.."/heat_on_swing" then
        param.save("swing_heat_on",data)
    elseif topic == mqtt_cmd_path.."/heat_off_swing" then
        param.save("swing_heat_off",data)
    elseif topic == mqtt_cmd_path.."/delay_ovrd" then
        tmr_delay = data
    end
    --config_save()
end)

function config_load()
    local md = param.load("mode")
    print("md = " .. md)
    set_therm_mode(tonumber(md))
    --set_therm_mode(tonumber(param.load("mode")))
end

station_cfg={}
station_cfg.ssid = param.load("ssid")
station_cfg.pwd = param.load("pwd")
--print("ssid:" .. station_cfg.ssid)
print("pw: " .. station_cfg.pwd)
station_cfg.auto=true
station_cfg.save=false
station_cfg.connected_cb=function() 
    lcd.wifi_state("w")
    end 
station_cfg.disconnected_cb=function()
    lcd.wifi_state("X")
    end
station_cfg.got_ip_cb=function() 
        --wifi_state = "i"
        lcd.wifi_state("w")
        --update_display()
        print("Got IP")
        mqtt_connect()
        
    end
print(node.heap())
initI2C()

print(node.heap())

lcd.init(zone,255) --local brt = load_param("bright")
lcd.therm_state("Boot")
lcd.wifi_state("X")
lcd.curr_temp("00")

print(node.heap())

config_load()

--initDisplay()
--update_display()
print(node.heap())

wifi.sta.disconnect()
wifi.setmode(wifi.STATION)
wifi.sta.config(station_cfg)

print(node.heap())

start_run_delay()
--run_delay = false --TEMPORARY DEBUG - REMOVE WHEN start_run_delay() is reinstated

print(node.heap())

tmr.create():alarm(4000, tmr.ALARM_AUTO, function()
  --lcd.update()
  print(node.heap())
  local tempF = updateTemp()
  if mqtt_connected then
    local data_string = string.format("%.1f",tempF)
    data_string = data_string.."|"..string.format("%02d",set_temp).."|"..tostring(therm_mode).."|FAN_STATE" --..tostring(fan_state)
    data_string = data_string.."|"..tostring(cool_on_offset).."|"..tostring(cool_off_offset).."|"..tostring(heat_on_offset).."|"..tostring(heat_off_offset)
    m:publish(mqtt_state_path.."/all",data_string,0,0) --"home/state/climate/zone3/all",data_string,0,0)
  else
    mqtt_connect()
  end
  --print("Hi")
end)
