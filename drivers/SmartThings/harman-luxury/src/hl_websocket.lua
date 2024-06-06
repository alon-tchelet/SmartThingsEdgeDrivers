local log = require "log"
local lustre = require "lustre"
local ws = lustre.WebSocket
local const = require "constants"

local Config = require"lustre".Config
local CloseCode = require"lustre.frame.close".CloseCode
local capabilities = require "st.capabilities"
local json = require "st.json"
local st_utils = require "st.utils"
local socket = require "cosock.socket"

--- a websocket to get updates from Harman Luxury devices
--- @class harman-luxury.HLWebsocket
--- @field driver table the driver the device is a memeber of
--- @field device table the device the websocket is connected to
--- @field websocket table|nil the websocket connection to the device
local HLWebsocket = {}
HLWebsocket.__index = HLWebsocket

--- hendles capabilities and sends the commands to the device
---@param msg any device that sends the command
function HLWebsocket:send_msg(msg)
  local dni = self.device.device_network_id
  log.debug(string.format("Sending this message to %s: %s", dni, st_utils.stringify_table(msg)))
  self.websocket:send_text(msg)
end

--- handles listener event messages to update relevant SmartThings capbilities
---@param msg any|table
function HLWebsocket:handle_incoming_message(msg)
  if msg["disconnect"] then
    local dni = self.device.device_network_id
    log.info(string.format("%s is being disconnected by device (likely a new hub has added it)", dni))
    -- clear token - device will remain offline until removed and added again
    self.device:set_field(const.CREDENTIAL, nil, {
      persist = true,
    })
    self:stop()
  end
  -- check for a power state change
  if msg[capabilities.switch.ID] then
    local powerState = msg[capabilities.switch.ID]
    if powerState == capabilities.switch.commands.on.NAME then
      self.device:emit_event(capabilities.switch.switch.on())
    elseif powerState == capabilities.switch.commands.off.NAME then
      self.device:emit_event(capabilities.switch.switch.off())
    end
  end
  -- check for a player state change
  if msg[capabilities.mediaPlayback.ID] then
    local playerState = msg[capabilities.mediaPlayback.ID]
    if playerState == capabilities.mediaPlayback.commands.play.NAME then
      self.device:emit_event(capabilities.mediaPlayback.playbackStatus.playing())
    elseif playerState == capabilities.mediaPlayback.commands.pause.NAME then
      log.debug("playerState - changed to paused")
      self.device:emit_event(capabilities.mediaPlayback.playbackStatus.paused())
    else
      self.device:emit_event(capabilities.mediaPlayback.playbackStatus.stopped())
    end
  end
  -- check for a audio track data change
  if msg[capabilities.audioTrackData.ID] then
    local audioTrackData = msg[capabilities.audioTrackData.ID]
    local trackdata = {}
    if type(audioTrackData.title) == "string" then
      trackdata.title = audioTrackData.title
    else
      trackdata.title = ""
    end
    if type(audioTrackData.artist) == "string" then
      trackdata.artist = audioTrackData.artist
    end
    if type(audioTrackData.album) == "string" then
      trackdata.album = audioTrackData.album
    end
    if type(audioTrackData.albumArtUrl) == "string" then
      trackdata.albumArtUrl = audioTrackData.albumArtUrl
    end
    if type(audioTrackData.mediaSource) == "string" then
      trackdata.mediaSource = audioTrackData.mediaSource
    end
    -- if track changed
    self.device:emit_event(capabilities.audioTrackData.audioTrackData(trackdata))

    self.device:emit_event(capabilities.mediaPlayback.supportedPlaybackCommands(
                             audioTrackData.supportedPlaybackCommands) or {"play", "stop", "pause"})
    self.device:emit_event(capabilities.mediaTrackControl.supportedTrackControlCommands(
                             audioTrackData.supportedTrackControlCommands) or {"nextTrack", "previousTrack"})
    self.device:emit_event(capabilities.audioTrackData.totalTime(audioTrackData.totalTime or 0))
    if audioTrackData.elapsedTime then
      self.device:emit_event(capabilities.audioTrackData.elapsedTime(audioTrackData.elapsedTime))
    end
  end
  -- check for a media presets change
  if msg[capabilities.mediaPresets.ID] and type(msg[capabilities.mediaPresets.ID].presets) == "table" then
    self.device:emit_event(capabilities.mediaPresets.presets(msg[capabilities.mediaPresets.ID].presets))
  end
  -- check for a media input source change
  if msg[capabilities.mediaInputSource.ID] then
    self.device:emit_event(capabilities.mediaInputSource.inputSource(msg[capabilities.mediaInputSource.ID]))
  end
  -- check for a volume value change
  if msg[capabilities.audioVolume.ID] then
    self.device:emit_event(capabilities.audioVolume.volume(msg[capabilities.audioVolume.ID]))
  end
  -- check for a mute value change
  if msg[capabilities.audioMute.ID] ~= nil then
    if msg[capabilities.audioMute.ID] then
      self.device:emit_event(capabilities.audioMute.mute.muted())
    else
      self.device:emit_event(capabilities.audioMute.mute.unmuted())
    end
  end
end

--- try reconnect webclient
function HLWebsocket:try_reconnect()
  local retries = 0
  local dni = self.device.device_network_id
  local ip = self.device:get_field(const.IP)
  if not ip then
    log.warn(string.format("%s cannot reconnect because no device ip", dni))
    return
  end
  log.info(string.format("%s attempting to reconnect websocket for speaker at %s", dni, ip))
  while true do
    if self:start() then
      self.driver:inject_capability_command(self.device, {
        capability = capabilities.refresh.ID,
        command = capabilities.refresh.commands.refresh.NAME,
        args = {},
      })
      return
    end
    retries = retries + 1
    log.info(string.format("Reconnect attempt %s in %s seconds", retries, const.RECONNECT_PERIOD))
    socket.sleep(const.RECONNECT_PERIOD)
  end
end

--- functionto start the websocket connection
--- @return boolean boolean
function HLWebsocket:start()
  local sock, err = socket.tcp()
  local ip = self.device:get_field(const.IP)
  local dni = self.device.device_network_id
  if not ip then
    log.error(string.format("Failed to start %s websocket connection, no ip address for device", dni))
    return false
  end
  log.info(string.format("%s starting websocket client on %s", dni, ip))
  if err then
    log.error(string.format("%s failed to get tcp socket: %s", dni, err))
    return false
  end
  sock:settimeout(const.HEALTH_CHEACK_INTERVAL)
  local config = Config.default():keep_alive(const.HEALTH_CHEACK_INTERVAL * 2)
  local websocket = ws.client(sock, "/", config)
  websocket:register_message_cb(function(msg)
    log.trace(string.format("%s received websocket message: %s", dni, msg.data))
    self:handle_incoming_message(json.decode(msg.data))
  end):register_error_cb(function(err)
    log.error(string.format("%s Websocket error: %s", dni, err))
    if err and (err:match("closed") or err:match("no response to keep alive ping commands")) then
      self.device:offline()
      self:try_reconnect()
    end
  end)
  websocket:register_close_cb(function(reason)
    log.info(string.format("%s Websocket closed: %s", dni, reason))
    self.websocket = nil
    if not self._stopped then
      self:try_reconnect()
    end
  end)
  local _
  _, err = websocket:connect(ip, const.WS_PORT)
  if err then
    log.error(string.format("%s failed to connect websocket: %s", dni, err))
    return false
  end
  local msg = {}
  -- send device token in first connection
  if not self.device:get_field(const.INITIALISED) then
    local token = self.device:get_field(const.CREDENTIAL)
    msg[const.CREDENTIAL] = token
    msg = json.encode(msg)
    websocket:send_text(msg)
    self.device:set_field(const.INITIALISED, true, {
      persist = true,
    })
  end
  log.info(string.format("%s Connected websocket successfully", dni))
  self._stopped = false
  self.websocket = websocket
  self.device:online()
  return true
end

--- creates a Harman Luxury websocket object for the device
---@param driver any
---@param device any
---@return HLWebsocket
function HLWebsocket.create_device_websocket(driver, device)
  return setmetatable({
    device = device,
    driver = driver,
    _stopped = true,
  }, HLWebsocket)
end

--- stops webclient
function HLWebsocket:stop()
  local dni = self.device.device_network_id
  self._stopped = true
  if not self.websocket then
    log.warn(string.format("%s no websocket exists to close", dni))
    return
  end
  local suc, err = self.websocket:close(CloseCode.normal())
  if not suc then
    log.error(string.format("%s failed to close websocket: %s", dni, err))
  end
end

--- tests if the websocket connection is stopped or not
--- @return boolean isStopped
function HLWebsocket:is_stopped()
  return self._stopped
end

return HLWebsocket
