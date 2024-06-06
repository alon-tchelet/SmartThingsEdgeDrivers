local get = require "api.gets"
local set = require "api.sets"

----------------------------------------------------------
--- Definitions
----------------------------------------------------------

--- system paths -----------------------------------------

local UUID_PATH = "settings:/system/memberId"
local MAC_PATH = "settings:/system/primaryMacAddress"
local MEMBER_ID_PATH = "settings:/system/memberId"
local MANUFACTURER_NAME_PATH = "settings:/system/manufacturer"
local DEVICE_NAME_PATH = "settings:/deviceName"
local MODEL_NAME_PATH = "settings:/system/modelName"
local PRODUCT_NAME_PATH = "settings:/system/productName"

----------------------------------------------------------
--- APIs
----------------------------------------------------------

local APIs = {}

--- system APIs ------------------------------------------

--- get UUID from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.GetUUID(ip)
  return get.String(ip, UUID_PATH)
end

--- get MAC address from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.GetMAC(ip)
  return get.String(ip, MAC_PATH)
end

--- get Member ID from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.GetMemberId(ip)
  return get.String(ip, MEMBER_ID_PATH)
end

--- get device manufacturer name from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.GetManufacturerName(ip)
  return get.String(ip, MANUFACTURER_NAME_PATH)
end

--- get device name from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.GetDeviceName(ip)
  return get.String(ip, DEVICE_NAME_PATH)
end

--- get model name from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.GetModelName(ip)
  return get.String(ip, MODEL_NAME_PATH)
end

--- get product name from Harman Luxury on ip
---@param ip string
---@return string|nil, nil|string
function APIs.GetProductName(ip)
  return get.String(ip, PRODUCT_NAME_PATH)
end

--- set product name from Harman Luxury on ip
---@param ip string
---@param value string
---@return boolean|number|string|table|nil, nil|string
function APIs.SetDeviceName(ip, value)
  return set.String(ip, DEVICE_NAME_PATH, value)
end

return APIs
