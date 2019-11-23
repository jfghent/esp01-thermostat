    
function load_param(name)
    local temp = nil
    if file.open(name..".par","r") then 
        temp = file.readline()
        file.close()
    end
    return temp
end

function save_param(name,value)
    file.open(name..".par","w+")
    file.write(tostring(value).." ")
    file.flush()
    file.close()
    
end
