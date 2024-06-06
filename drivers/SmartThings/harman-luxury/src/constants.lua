local Constants = {
  -- device constants
  IP = "device_ipv4",
  DEVICE_INFO = "device_info",
  CREDENTIAL = "credential",
  INITIALISED = "initialised",
  STATUS = "status",
  HEALTH_TIMER = "health_timer",
  UPDATE_TIMER = "value_updates_timer",
  WEBSOCKET = "websocket",

  -- intervals constants (in seconds)
  UPDATE_INTERVAL = 3,
  HEALTH_CHEACK_INTERVAL = 10,
  HTTP_TIMEOUT = 5,
  RETRY_CONNECT = 3,
  RECONNECT_PERIOD = 30,

  -- discovery constants
  SERVICE_TYPE = "_sue-st._tcp",
  DOMAIN = "local",
  MAC = "mac",
  DNI = "dni",
  MNID = "mnid",
  SETUP_ID = "setupid",

  -- device setup constants
  DEFAULT_DEVICE_NAME = "HarmanLuxury",
  DEFAULT_MANUFACTURER_NAME = "Harman Luxury Audio",
  DEFAULT_MODEL_NAME = "Harman Luxury",
  DEFAULT_PRODUCT_NAME = "Harman Luxury",

  -- general consts
  VOL_STEP = 5,
  WS_PORT = 50002,
}
return Constants
