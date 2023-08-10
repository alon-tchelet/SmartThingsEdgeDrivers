local nsdk = require "api.nsdk"
local log = require "log"

Gets = {}

----------------------------------------------------------
--- Helper Functions
----------------------------------------------------------

--- get value from path in ip
---@param ip string
---@param path string
---@param type string
---@return boolean, boolean|number|string|table|ErrMsg
local function GetValue(ip, path, type)
	local ret, val = nsdk.GetData {
		ip = ip,
		path = path
	}
	if ret then
		return true, val[type]
	else
		return false, val
	end
end

----------------------------------------------------------
--- GetTYPE Functions
----------------------------------------------------------

--- get bool value from path in ip
---@param ip string
---@param path string
---@return boolean, boolean|ErrMsg
function Gets.Bool(ip, path)
	return GetValue(ip, path, "bool_")
end

--- get byte value from path in ip
---@param ip string
---@param path string
---@return boolean, number|ErrMsg
function Gets.Byte(ip, path)
	return GetValue(ip, path, "byte_")
end

--- get i16 value from path in ip
---@param ip string
---@param path string
---@return boolean, number|ErrMsg
function Gets.I16(ip, path)
	return GetValue(ip, path, "i16_")
end

--- get i32 value from path in ip
---@param ip string
---@param path string
---@return boolean, number|ErrMsg
function Gets.I32(ip, path)
	return GetValue(ip, path, "i32_")
end

--- get i64 value from path in ip
---@param ip string
---@param path string
---@return boolean, number|ErrMsg
function Gets.I64(ip, path)
	return GetValue(ip, path, "i64_")
end

--- get double value from path in ip
---@param ip string
---@param path string
---@return boolean, number|ErrMsg
function Gets.Double(ip, path)
	return GetValue(ip, path, "double_")
end

--- get string value from path in ip
---@param ip string
---@param path string
---@return boolean, string|ErrMsg
function Gets.String(ip, path)
	return GetValue(ip, path, "string_")
end

return Gets
