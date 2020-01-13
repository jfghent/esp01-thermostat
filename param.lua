    
function load_param(name)
    local temp = nil
    if file.open(name..".par","r") then 
        s = file.stat(name..".par")
        temp = file.read(s.size-1)
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
