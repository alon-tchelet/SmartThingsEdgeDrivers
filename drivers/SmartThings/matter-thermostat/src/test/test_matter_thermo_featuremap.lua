-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local utils = require "st.utils"
local Uint32 = require "st.matter.data_types".Uint32
local clusters = require "st.matter.clusters"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("thermostat-humidity-fan.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER"},
        {
          cluster_id = clusters.Thermostat.ID,
          cluster_revision=5,
          cluster_type="SERVER",
          feature_map=1, -- Heat feature only.
        },
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"}
      }
    }
  }
})

local mock_device_simple = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("thermostat.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = clusters.Thermostat.ID,
          cluster_revision=5,
          cluster_type="SERVER",
          events={},
          feature_map=2, -- Cool feature only.
        },
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
      }
    }
  }
})

local function test_init()
  local cluster_subscribe_list = {
    clusters.Thermostat.attributes.LocalTemperature,
    clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
    clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
    clusters.Thermostat.attributes.SystemMode,
    clusters.Thermostat.attributes.ThermostatRunningState,
    clusters.Thermostat.attributes.ControlSequenceOfOperation,
    clusters.Thermostat.attributes.LocalTemperature,
    clusters.TemperatureMeasurement.attributes.MeasuredValue,
    clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
    clusters.FanControl.attributes.FanMode,
    clusters.FanControl.attributes.FanModeSequence,
  }
  local cluster_subscribe_list_simple = {
    clusters.Thermostat.attributes.LocalTemperature,
    clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
    clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
    clusters.Thermostat.attributes.SystemMode,
    clusters.Thermostat.attributes.ThermostatRunningState,
    clusters.Thermostat.attributes.ControlSequenceOfOperation,
    clusters.Thermostat.attributes.LocalTemperature,
    clusters.TemperatureMeasurement.attributes.MeasuredValue,
  }

  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  local subscribe_request_simple = cluster_subscribe_list_simple[1]:subscribe(mock_device_simple)
  for i, cluster in ipairs(cluster_subscribe_list_simple) do
    if i > 1 then
      subscribe_request_simple:merge(cluster:subscribe(mock_device_simple))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.socket.matter:__expect_send({mock_device_simple.id, subscribe_request_simple})
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_device_simple)
end
test.set_test_init_function(test_init)

local function configure(device, is_heat)
  test.socket.device_lifecycle:__queue_receive({ device.id, "doConfigure" })
  local read_limits
  if is_heat then
    read_limits = clusters.Thermostat.attributes.AbsMinHeatSetpointLimit:read()
    read_limits:merge(clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit:read())
  else
    read_limits = clusters.Thermostat.attributes.AbsMinCoolSetpointLimit:read()
    read_limits:merge(clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit:read())
  end
  test.socket.matter:__expect_send({device.id, read_limits})
  test.socket.matter:__expect_send({
    device.id,
    clusters.Thermostat.attributes.AttributeList:read(device, 1)
  })
end

test.register_coroutine_test(
  "Profile change on doConfigure lifecycle event due to cluster heating feature map",
  function()
    configure(mock_device, true)
    mock_device:expect_metadata_update({ profile = "thermostat-humidity-fan-heating-only-nostate" })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device_simple.id,
      clusters.Thermostat.attributes.AttributeList:build_test_report_data(mock_device_simple, 1, {Uint32(0x2)}),
    })
end
)

test.register_coroutine_test(
  "Profile change on doConfigure lifecycle event due to cluster cooling feature map",
  function()
    configure(mock_device_simple, false)
    mock_device_simple:expect_metadata_update({ profile = "thermostat-cooling-only-nostate" })
    mock_device_simple:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device_simple.id,
      clusters.Thermostat.attributes.AttributeList:build_test_report_data(mock_device_simple, 1, {Uint32(0x1)}),
    })
end
)

test.register_coroutine_test(
  "Profile change due to Thermostat attribute list",
  function()
    configure(mock_device_simple, false)
    mock_device_simple:expect_metadata_update({ profile = "thermostat-cooling-only-nostate" })
    mock_device_simple:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device_simple.id,
      clusters.Thermostat.attributes.AttributeList:build_test_report_data(mock_device_simple, 1, {Uint32(0x29)}),
    })
    mock_device_simple:expect_metadata_update({ profile = "thermostat-cooling-only" })
end
)

test.run_registered_tests()
