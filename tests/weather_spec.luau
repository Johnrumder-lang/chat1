
local function parent()
 return {FindFirstChild=function() return nil end, FindFirstChildOfClass=function() return nil end}
end
local attributes = {}
local replicatedFolder = {SetAttribute=function(self, name, value) attributes[name] = value end}
local lighting = parent()
local heartbeatCallback
local disconnected = false
local services = {
 Lighting = lighting,
 ReplicatedStorage = {WaitForChild=function(self, name) assert(name == "RoadTrip") return replicatedFolder end},
 RunService = {Heartbeat={Connect=function(self, callback)
  heartbeatCallback=callback
  return {Disconnect=function() disconnected=true end}
 end}},
 TweenService = {Create=function(self, object, _, properties)
  return {Play=function() for key,value in pairs(properties) do object[key]=value end end, Cancel=function() end}
 end},
}
local game = {GetService=function(self, name) assert(services[name], name) return services[name] end}
local workspace = {Terrain=parent()}
local Instance = {new=function(className) return parent() end}
local Color3 = {fromRGB=function(r,g,b) return {r,g,b} end}
local Enum = {EasingStyle={Sine=1}, EasingDirection={InOut=1}}
local TweenInfo = {new=function(...) return {} end}
local Weather = (function()
-- WEATHER_MODULE
end)()
local cleanup = Weather.start()
assert(cleanup == Weather.start(), "start must be idempotent")
assert(attributes.Weather == "Clear", "initial clear")
assert(attributes.Precipitation == 0, "initial dry")
assert(attributes.Temperature == 17, "initial temperature")
assert(attributes.ClockTime == 16.35, "initial time")
local seen = {}
local rainSeen = false
for second = 1, 2400 do
 heartbeatCallback(1)
 seen[attributes.Weather] = true
 assert(attributes.WeatherIntensity >= 0 and attributes.WeatherIntensity <= 1, "weather intensity bounds")
 assert(attributes.Precipitation >= 0 and attributes.Precipitation <= 1, "precipitation bounds")
 assert(attributes.WindStrength >= 0 and attributes.WindStrength <= 1, "wind bounds")
 assert(attributes.Temperature >= 8 and attributes.Temperature <= 17, "temperature bounds")
 assert(math.abs(attributes.ClockTime - (16.35 + second / 1800)) < 0.000001, "slow daylight progression")
 if attributes.Weather == "Rain" and attributes.Precipitation > 0.7 then rainSeen=true end
end
for _,name in ipairs({"Clear", "Overcast", "Rain", "Storm", "Fog"}) do assert(seen[name], "missing state "..name) end
assert(rainSeen, "rain must reach expected intensity")
cleanup()
assert(disconnected, "cleanup disconnects heartbeat")
cleanup()
print("PASS: 2,400-second weather lifecycle, all five states, interpolation bounds, slow day, idempotence, cleanup")
