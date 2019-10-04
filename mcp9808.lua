--MCP9808, collection of functions for use with the MCP9808
-- digital temperature sensor
-- based on NodeMCU 2.2

-- created April 12, 2019
-- modified April 12, 2019

--[[
Copyright 2019 Owain Martin

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
--]]


-- i2c setup
-- id - always 0
-- pinSDA - 2 - board pin 4  can be any pin 
-- pinSCL - 1 - board pin 5  can be any pin 
-- speed - only i2c.SLOW supported

-- Note adafruit documentation has board pin 4 & 5 to NodeMCU 2 & 1 reversed

--i2c.setup(0, 2, 1, i2c.SLOW)
--i2cAddress = 0x18-

module("mcp9808", package.seeall)

-- single byte read
function read_register(devAddr, regAddr)

    local ack, lsb, data
    
    i2c.start(0)
    ack = i2c.address(0,devAddr,i2c.TRANSMITTER) 
    i2c.write(0,regAddr) -- address of register to read
    i2c.start(0)    
    i2c.address(0, devAddr, i2c.RECEIVER)
    data = i2c.read(0,1)
    i2c.stop(0)

    lsb = string.byte(data)

    return lsb
end

-- single word read
function read_word_register(devAddr, regAddr)

    local ack, data, msb, lsb
    
    i2c.start(0)
    ack = i2c.address(0,devAddr,i2c.TRANSMITTER)
    i2c.write(0,regAddr) -- address of register to read
    i2c.start(0)    
    i2c.address(0, devAddr, i2c.RECEIVER)
    data = i2c.read(0,2)    
    i2c.stop(0)

    msb, lsb = string.byte(data,1,2)

    return msb, lsb
end

-- single byte write
function write_register(devAddr, regAddr, regValue)

    local ack
    
    i2c.start(0)
    ack = i2c.address(0,devAddr,i2c.TRANSMITTER) 
    i2c.write(0,regAddr, regValue)       
    i2c.stop(0)

    return
end

-- single word write
function write_word_register(devAddr, regAddr, regValue)

    local msb, lsb, ack

    -- break regValue into msb & lsb
    msb = bit.band(regValue, 0xFF00)
    msb = bit.rshift(msb, 8)  -- 0x1F
    lsb = bit.band(regValue, 0x00FF) -- 0x8C

    -- send data
    i2c.start(0)
    ack = i2c.address(0,devAddr,i2c.TRANSMITTER) 
    i2c.write(0,regAddr,{msb, lsb})    
    i2c.stop(0)

    return
end

function twos_complement_conversion(value)

    -- test the sign bit, bit 12    
    if bit.isset(value, 12) == true then
        --print("negative number")
        value = bit.band(value, 0xFFF) -- strip off sign bit
        value = bit.bxor(value, 0xFFF)
        value = -(value+1)
        value = value/16
    else
        --print("positive number")
        value = value/16  

    end

    return value
end

function conversion_to_twos_complement(value)

    if value < 0 then
        --print("negative number")
        value = value * -16
        value = bit.band(value, 0xFFF)
        value = bit.bxor(value, 0x1FFF)
        value = value + 1
    else
        --print("positive number")
        value = value * 16
        value = bit.band(value, 0xFFF)
    end

    return value
end

function mcp9808.read_temperature()

    -- read_temperature, function to return the temperature
    -- value stored in register 0x05 (T ambient)

    local msb, lsb, temperature

    msb, lsb = read_word_register(0x18, 0x05)   -- read data from sensor Ta register
    temperature = bit.lshift(msb, 8) + lsb      -- combine 2 bytes of data together
    --print(string.format("%x", temperature))
    temperature = bit.band(temperature, 0x1FFF) -- strip off alert flags from temperature data
    temperature = twos_complement_conversion(temperature)  -- convert 2s comp to normal 

    return temperature
end



