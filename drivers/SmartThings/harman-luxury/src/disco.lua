local mdns = require "st.mdns"
local socket = require "cosock.socket"
local log = require "log"

local disco_helper = require "disco_helper"
local devices = require "devices"
local const = require "constants"

local Discovery = {}

local function update_device_discovery_cache(driver, dni, params)
    log.info(string.format("update_device_discovery_cache for device dni: dni=%s, ip=%s", dni, params.ip))
    local device_info = devices.get_device_info(dni, params)
    driver.registered_devices[dni] = {
        ip = params.ip,
        device_info = device_info
    }
end

local function try_add_device(driver, device_dni, device_params)
    log.trace(string.format("try_add_device : dni=%s, ip=%s", device_dni, device_params.ip))

    update_device_discovery_cache(driver, device_dni, device_params)

    local device_info = devices.get_device_info(device_dni, device_params)

    if not device_info then
        log.error(string.format("failed to create device create msg. device_info is nil. dni=%s", device_dni))
        return nil
    end

    driver:try_create_device(device_info)
end

function Discovery.set_device_field(driver, device)
    log.info(string.format("set_device_field : dni=%s", device.device_network_id))
    local device_cache_value = driver.registered_devices[device.device_network_id]

    -- persistent fields
    device:set_field(const.IP, device_cache_value.ip, {
        persist = true
    })
    device:set_field(const.DEVICE_INFO, device_cache_value.device_info, {
        persist = true
    })
end

local function find_params_table(driver)
    log.info("Discovery.find_params_table")

    local discovery_responses = mdns.discover(const.SERVICE_TYPE, const.DOMAIN) or {}

    local dni_params_table = disco_helper.get_dni_ip_table_from_mdns_responses(driver, const.SERVICE_TYPE, const.DOMAIN,
        discovery_responses)

    return dni_params_table
end

local function discovery_device(driver)
    local unknown_discovered_devices = {}
    local known_discovered_devices = {}
    local known_devices = {}

    log.debug("\n\n--- Initialising known devices list ---\n")
    for _, device in pairs(driver:get_devices()) do
        known_devices[device.device_network_id] = device
    end

    log.debug("\n\n--- Creating the parameters table ---\n")
    local params_table = find_params_table(driver)

    log.debug("\n\n--- Checking if devices are known or not ---\n")
    for dni, params in pairs(params_table) do
        log.info(string.format("discovery_device dni=%s, ip=%s", dni, params.ip))
        if not known_devices or not known_devices[dni] then
            unknown_discovered_devices[dni] = params
        else
            known_discovered_devices[dni] = params
        end
    end

    log.debug("\n\n--- Update devices cache ---\n")
    for dni, params in pairs(known_discovered_devices) do
        log.trace(string.format("known dni=%s, ip=%s", dni, params.ip))
        if driver.registered_devices[dni] then
            update_device_discovery_cache(driver, dni, params)
            Discovery.set_device_field(driver, known_devices[dni])
        end
    end

    if unknown_discovered_devices then
        log.debug("\n\n--- Try to create unkown devices ---\n")
        for dni, ip in pairs(unknown_discovered_devices) do
            log.trace(string.format("unknown dni=%s, ip=%s", dni, ip))
            if not driver.registered_devices[dni] then
                try_add_device(driver, dni, params_table[dni])
            end
        end
    end
end

function Discovery.find_ip_table(driver)
    log.info("Discovery.find_ip_table")

    local dni_params_table = find_params_table(driver)

    local dni_ip_table = {}
    for dni, params in pairs(dni_params_table) do
        dni_ip_table[dni] = params.ip
    end

    return dni_ip_table
end

function Discovery.discovery_handler(driver, _, should_continue)
    log.info("Starting Harman Luxury discovery")

    while should_continue() do
        discovery_device(driver)
        socket.sleep(0.5)
    end
    log.info("Ending Harman Luxury discovery")
end

return Discovery
