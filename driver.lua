require "json"

JSON=(loadstring(json.JSON_LIBRARY_CHUNK))()

function GetState()
    getPlugState()
    UpdateState()
end

function SetState()
    UpdateState()
end

function UpdateState()
    C4:SendToProxy(5001, "ICON_CHANGED", { icon = strState, icon_description = strState })
    C4:UpdateProperty("Current State", strState)
end

function ReceivedFromProxy(idBinding, strCommand, tParams)
    if strCommand == "SELECT" then
        if strState == "On" then
            turnPlugOff()
        else
		  if strState == "Off" then
			 turnPlugOn()
		  end
        end
    end
end

function OnPropertyChanged(strProperty)
    strIP = Properties["IP Address"]
end

function OnDriverInit()
    strState = "Off"
    strIP = ""

    for k,v in pairs(Properties) do
	   OnPropertyChanged(k)
    end

    GetState()
    C4:UpdateProperty ('Driver Version', C4:GetDriverConfigInfo ("version"))
    C4:SetTimer(5000, function(timer, skips) getPlugState() end, true)
end



-- Turn the plug on
function turnPlugOn()
    strCommand = '{"system":{"set_relay_state":{"state":1}}}'
    sendData(strCommand)
end

-- Turn the plug off
function turnPlugOff()
    strCommand = '{"system":{"set_relay_state":{"state":0}}}'
    sendData(strCommand)
end

-- Get the Plug status
function getPlugState()
    strCommand = '{"system":{"get_sysinfo":{}}}'
    szData = tpEndcodeData(strCommand)
    sendOverSocket(szData, 3000, function(info, err)
        if (info ~= nil) then
            strResult = tpDecodeData(info)
            jsonData = JSON:decode(strResult)
            iState = jsonData['system']['get_sysinfo']['relay_state']
            if (iState == 1) then
                strState = "On"
            else
                strState = "Off"
            end
            UpdateState()
        else
		  strState = "Error"
		  UpdateState()	   
        end
    end)
end

-- Send the encoded data to the plug and get a response, or an error
function sendData(strCommand)
    szData = tpEndcodeData(strCommand)
    sendOverSocket(szData, 3000, function(info, err)
        if (info ~= nil) then
            strResult = tpDecodeData(info)
            jsonData = JSON:decode(strResult)
            getPlugState()
        else
		  strState = "Error"
		  UpdateState()
        end
    end)
end

-- Send data over a socket with a timeout
function sendOverSocket(szData, timeout, done)
    local timer
    local completed = false

    local complete = function(data, errMsg)
        if (not completed) then
            completed = true
            if (timer ~= nil) then
                timer:Cancel()
            end
            done(data, errMsg)
        end
    end

    local cli = C4:CreateTCPClient()
        :OnConnect(function(client)
            local remote = client:GetRemoteAddress()
            client:Write(szData):ReadUpTo(1024)
        end)

        :OnDisconnect(function(client, errCode, errMsg)
            if (errCode ~= 0) then
                complete(nil, "Disconnected with error " .. errCode .. ": " .. errMsg)
            else
                complete(nil, "Disconnected and no response received")
            end
        end)

        :OnRead(function(client, data)
            client:Close()
            complete(data)
        end)

        :OnError(function(client, errCode, errMsg)
		  strState = "Error"
            complete(nil, "Error " .. errCode .. ": " .. errMsg)
        end)
        :Connect(strIP, 9999)

    if (timeout > 0) then
        timer = C4:SetTimer(timeout, function()
            cli:Close()
            complete(nil, "Timed out!")
        end)
    end

end

-- Encode the data for the plug using a autokey cipher
-- Use an inital vector of -85 (171)
function tpEndcodeData(strData)
    local key = 171
    result = "\0\0\0\0"

    for i = 1, #strData do
        local ord = string.byte( strData, i )
        local val = bit.bxor(key, ord)
        key = val
        result = result .. string.char(val)
    end

    return result
end

-- Decode the data from the plug using a autokey cipher
-- Use an inital vector of -85 (171)
function tpDecodeData(szData)
    local key = 171

    result = ""
    for i = 5, #szData do
        local char = string.byte( szData, i )
        val = bit.bxor(char,key)
        key = char
        result = result .. string.char(val)
    end

    return result
end

-- Helper function to convert string to hex
function string.fromhex(str)
    return (str:gsub('..', function (cc)
        return string.char(tonumber(cc, 16))
    end))
end

-- Helper function to convert hex to string
function string.tohex(str)
    return (str:gsub('.', function (c)
        return string.format('%02X', string.byte(c))
    end))
end