----------------------------------------------------------
-- Inclusions
----------------------------------------------------------
-- SmartThings inclusions
local Driver = require "st.driver"
local capabilities = require "st.capabilities"
local json = require "st.json"
local st_utils = require "st.utils"
local log = require "log"
local socket = require "cosock.socket"
local cosock = require "cosock"

-- local Harman Luxury inclusions
local discovery = require "disco"
local hlws = require "hl_websocket"
local api = require "api.apis"
local const = require "constants"

----------------------------------------------------------
-- Device Functions
----------------------------------------------------------

local function device_removed(_, device)
  local device_dni = device.device_network_id
  log.info(string.format("Device removed - dni=\"%s\"", device_dni))
  -- close websocket
  local device_ws = device:get_field(const.WEBSOCKET)
  if device_ws then
    device_ws:stop()
  end
end

local function refresh(_, device)
  local ip = device:get_field(const.IP)

  -- check and update device status
  local power_state
  power_state, _ = api.GetPowerState(ip)
  if power_state then
    log.debug(string.format("Current power state: %s", power_state))

    if power_state == "online" then
      device:emit_event(capabilities.switch.switch.on())
      local player_state, audioTrackData

      -- get player state
      player_state, _ = api.GetPlayerState(ip)
      if player_state then
        if player_state == "playing" then
          device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
        elseif player_state == "paused" then
          device:emit_event(capabilities.mediaPlayback.playbackStatus.paused())
        else
          device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
        end
      end

      -- get audio track data
      audioTrackData, _ = api.getAudioTrackData(ip)
      if audioTrackData then
        device:emit_event(capabilities.audioTrackData.audioTrackData(audioTrackData.trackdata))
        device:emit_event(capabilities.mediaPlayback.supportedPlaybackCommands(
                            audioTrackData.supportedPlaybackCommands))
        device:emit_event(capabilities.mediaTrackControl.supportedTrackControlCommands(
                            audioTrackData.supportedTrackControlCommands))
        device:emit_event(capabilities.audioTrackData.totalTime(audioTrackData.totalTime or 0))
      end
    elseif device:get_field(const.STATUS) then
      device:emit_event(capabilities.switch.switch.off())
      device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
    end
  end

  -- get media presets list
  local presets
  presets, _ = api.GetMediaPresets(ip)
  if presets then
    device:emit_event(capabilities.mediaPresets.presets(presets))
  end

  -- check and update device volume and mute status
  local vol, mute
  vol, _ = api.GetVol(ip)
  if vol then
    device:emit_event(capabilities.audioVolume.volume(vol))
  end
  mute, _ = api.GetMute(ip)
  if type(mute) == "boolean" then
    if mute then
      device:emit_event(capabilities.audioMute.mute.muted())
    else
      device:emit_event(capabilities.audioMute.mute.unmuted())
    end
  end

  -- check and update device media input source
  local inputSource
  inputSource, _ = api.GetInputSource(ip)
  if inputSource then
    device:emit_event(capabilities.mediaInputSource.inputSource(inputSource))
  end
end

local function device_init(driver, device)
  log.info(string.format("Initiating device: %s", device.label))

  local device_ip = device:get_field(const.IP)
  local device_dni = device.device_network_id
  if driver.datastore.discovery_cache[device_dni] then
    log.warn("set unsaved device field")
    discovery.set_device_field(driver, device)
  end

  -- start websocket
  cosock.spawn(function()
    while true do
      local device_ws = hlws.create_device_websocket(driver, device)
      device:set_field(const.WEBSOCKET, device_ws)
      if device_ws:start() then
        log.info(string.format("%s successfully connected to websocket", device_dni))
        break
      else
        log.info(string.format("%s failed to connect to websocket. Trying again in %d seconds", device_dni,
                               const.RETRY_CONNECT))
      end
      socket.sleep(const.RETRY_CONNECT)
    end
  end)

  -- set supported default media playback commands
  device:emit_event(capabilities.mediaPlayback.supportedPlaybackCommands(
                      {capabilities.mediaPlayback.commands.play.NAME, capabilities.mediaPlayback.commands.pause.NAME,
                       capabilities.mediaPlayback.commands.stop.NAME}))
  device:emit_event(capabilities.mediaTrackControl.supportedTrackControlCommands(
                      {capabilities.mediaTrackControl.commands.nextTrack.NAME,
                       capabilities.mediaTrackControl.commands.previousTrack.NAME}))

  -- set supported input sources
  local supportedInputSources, _ = api.GetSupportedInputSources(device_ip)
  device:emit_event(capabilities.mediaInputSource.supportedInputSources(supportedInputSources))

  -- set supported keypad inputs
  device:emit_event(capabilities.keypadInput.supportedKeyCodes(
                      {"UP", "DOWN", "LEFT", "RIGHT", "SELECT", "BACK", "EXIT", "MENU", "SETTINGS", "HOME", "NUMBER0",
                       "NUMBER1", "NUMBER2", "NUMBER3", "NUMBER4", "NUMBER5", "NUMBER6", "NUMBER7", "NUMBER8",
                       "NUMBER9"}))

  refresh(driver, device)
end

local function device_added(driver, device)
  log.info(string.format("Device added: %s", device.label))
  discovery.set_device_field(driver, device)
  local device_dni = device.device_network_id
  discovery.joined_device[device_dni] = nil
  -- ensuring device is initialised
  device_init(driver, device)
end

local function device_changeInfo(_, device, _, _)
  log.info(string.format("Device added: %s", device.label))
  local ip = device:get_field(const.IP)
  local _, err = api.SetDeviceName(ip, device.label)
  if err then
    log.info(string.format("device_changeInfo: Error occured during attempt to change device name. Error message: %s",
                           err))
  end
end

local function message_sender(_, device, cmd)
  local msg, value = {}, {}
  local device_ws = device:get_field(const.WEBSOCKET)
  local token = device:get_field(const.CREDENTIAL)

  value[const.CAPABILITY] = cmd.capability
  value[const.COMMAND] = cmd.command
  value[const.ARG] = cmd.args
  msg[const.MESSAGE] = value
  msg[const.CREDENTIAL] = token

  msg = json.encode(msg)

  device_ws:send_msg(msg)
end

local function do_refresh(_, device, cmd)
  log.info(string.format("Starting do_refresh: %s", device.label))

  -- restart websocket if needed
  local device_ws = device:get_field(const.WEBSOCKET)
  if device_ws and (device_ws:is_stopped() or device_ws.websocket == nil) then
    device.log.info("Trying to restart websocket client for device updates")
    device_ws:stop()
    socket.sleep(1) -- give time for Lustre to close the websocket
    if not device_ws:start() then
      log.warn("%s failed to restart listening websocket client for device updates", device.device_network_id)
      return
    end
  end
  message_sender(_, device, cmd)
end

----------------------------------------------------------
-- Driver Definition
----------------------------------------------------------

--- @type Driver
local driver = Driver("Harman Luxury", {
  discovery = discovery.discovery_handler,
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    removed = device_removed,
    infoChanged = device_changeInfo,
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = message_sender,
      [capabilities.switch.commands.off.NAME] = message_sender,
    },
    [capabilities.audioMute.ID] = {
      [capabilities.audioMute.commands.mute.NAME] = message_sender,
      [capabilities.audioMute.commands.unmute.NAME] = message_sender,
      [capabilities.audioMute.commands.setMute.NAME] = message_sender,
    },
    [capabilities.audioVolume.ID] = {
      [capabilities.audioVolume.commands.volumeUp.NAME] = message_sender,
      [capabilities.audioVolume.commands.volumeDown.NAME] = message_sender,
      [capabilities.audioVolume.commands.setVolume.NAME] = message_sender,
    },
    [capabilities.mediaInputSource.ID] = {
      [capabilities.mediaInputSource.commands.setInputSource.NAME] = message_sender,
    },
    [capabilities.mediaPresets.ID] = {
      [capabilities.mediaPresets.commands.playPreset.NAME] = message_sender,
    },
    [capabilities.audioNotification.ID] = {
      [capabilities.audioNotification.commands.playTrack.NAME] = message_sender,
      [capabilities.audioNotification.commands.playTrackAndResume.NAME] = message_sender,
      [capabilities.audioNotification.commands.playTrackAndRestore.NAME] = message_sender,
    },
    [capabilities.mediaPlayback.ID] = {
      [capabilities.mediaPlayback.commands.pause.NAME] = message_sender,
      [capabilities.mediaPlayback.commands.play.NAME] = message_sender,
      [capabilities.mediaPlayback.commands.stop.NAME] = message_sender,
    },
    [capabilities.mediaTrackControl.ID] = {
      [capabilities.mediaTrackControl.commands.nextTrack.NAME] = message_sender,
      [capabilities.mediaTrackControl.commands.previousTrack.NAME] = message_sender,
    },
    [capabilities.keypadInput.ID] = {
      [capabilities.keypadInput.commands.sendKey.NAME] = message_sender,
    },
  },
  supported_capabilities = {capabilities.switch, capabilities.audioMute, capabilities.audioVolume,
                            capabilities.mediaPresets, capabilities.audioNotification, capabilities.mediaPlayback,
                            capabilities.mediaTrackControl, capabilities.refresh},
})

----------------------------------------------------------
-- main
----------------------------------------------------------

-- initialise data store for Harman Luxury driver

if driver.datastore.discovery_cache == nil then
  driver.datastore.discovery_cache = {}
end

-- start driver run loop

log.info("Starting Harman Luxury run loop")
driver:run()
log.info("Exiting Harman Luxury run loop")
