----------------------------------------------------------
-- Inclusions
----------------------------------------------------------
-- SmartThings inclusions
local Driver = require "st.driver"
local capabilities = require "st.capabilities"
local st_utils = require "st.utils"
local log = require "log"
local socket = require "cosock.socket"
local cosock = require "cosock"

-- local Harman Luxury inclusions
local discovery = require "disco"
local handlers = require "handlers"
local listener = require "listener"
local api = require "api.apis"
local const = require "constants"

----------------------------------------------------------
-- Device Functions
----------------------------------------------------------

local function device_removed(_, device)
  local device_dni = device.device_network_id
  log.info(string.format("Device removed - dni=\"%s\"", device_dni))
  -- close websocket listener
  local device_listener = device:get_field(const.LISTENER)
  if device_listener then device_listener:stop() end
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

  -- start websocket listener
  cosock.spawn(function()
    while true do
      local device_listener = listener.create_device_event_listener(driver, device)
      device:set_field(const.LISTENER, device_listener)
      if device_listener:start() then
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

local function do_refresh(driver, device, _)
  log.info(string.format("Starting do_refresh: %s", device.label))

  -- check and update device values
  refresh(driver, device)

  -- restart listener if needed
  local device_listener = device:get_field(const.LISTENER)
  if device_listener and (device_listener:is_stopped() or device_listener.websocket == nil) then
    device.log.info("Restarting listening websocket client for device updates")
    device_listener:stop()
    socket.sleep(1) -- give time for Lustre to close the websocket
    if not device_listener:start() then
      log.warn("%s failed to restart listening websocket client for device updates", device.device_network_id)
    end
  end
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
      [capabilities.switch.commands.on.NAME] = handlers.handle_on,
      [capabilities.switch.commands.off.NAME] = handlers.handle_off,
    },
    [capabilities.audioMute.ID] = {
      [capabilities.audioMute.commands.mute.NAME] = handlers.handle_mute,
      [capabilities.audioMute.commands.unmute.NAME] = handlers.handle_unmute,
      [capabilities.audioMute.commands.setMute.NAME] = handlers.handle_set_mute,
    },
    [capabilities.audioVolume.ID] = {
      [capabilities.audioVolume.commands.volumeUp.NAME] = handlers.handle_volume_up,
      [capabilities.audioVolume.commands.volumeDown.NAME] = handlers.handle_volume_down,
      [capabilities.audioVolume.commands.setVolume.NAME] = handlers.handle_set_volume,
    },
    [capabilities.mediaInputSource.ID] = {
      [capabilities.mediaInputSource.commands.setInputSource.NAME] = handlers.handle_setInputSource,
    },
    [capabilities.mediaPresets.ID] = {
      [capabilities.mediaPresets.commands.playPreset.NAME] = handlers.handle_play_preset,
    },
    [capabilities.audioNotification.ID] = {
      [capabilities.audioNotification.commands.playTrack.NAME] = handlers.handle_audio_notification,
      [capabilities.audioNotification.commands.playTrackAndResume.NAME] = handlers.handle_audio_notification,
      [capabilities.audioNotification.commands.playTrackAndRestore.NAME] = handlers.handle_audio_notification,
    },
    [capabilities.mediaPlayback.ID] = {
      [capabilities.mediaPlayback.commands.pause.NAME] = handlers.handle_pause,
      [capabilities.mediaPlayback.commands.play.NAME] = handlers.handle_play,
      [capabilities.mediaPlayback.commands.stop.NAME] = handlers.handle_stop,
    },
    [capabilities.mediaTrackControl.ID] = {
      [capabilities.mediaTrackControl.commands.nextTrack.NAME] = handlers.handle_next_track,
      [capabilities.mediaTrackControl.commands.previousTrack.NAME] = handlers.handle_previous_track,
    },
    [capabilities.keypadInput.ID] = {
      [capabilities.keypadInput.commands.sendKey.NAME] = handlers.handle_send_key,
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
