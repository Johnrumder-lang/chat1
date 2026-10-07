-- Alpine weather is server-authoritative; visual transitions are deliberately slow.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Weather = {}
local activeCleanup

local STATES = {
	Clear = {
		intensity = 0.18, precipitation = 0, temperature = 17, wind = 0.18,
		clouds = { Cover = 0.27, Density = 0.62, Color = Color3.fromRGB(249, 242, 229) },
		atmosphere = { Density = 0.285, Offset = 0.13, Haze = 1.5, Glare = 0.16,
			Color = Color3.fromRGB(211, 222, 232), Decay = Color3.fromRGB(132, 148, 162) },
		lighting = { Brightness = 2.55, ExposureCompensation = -0.08,
			Ambient = Color3.fromRGB(89, 99, 116), OutdoorAmbient = Color3.fromRGB(124, 133, 147) },
		grade = { Brightness = 0.015, Contrast = 0.09, Saturation = -0.08, TintColor = Color3.fromRGB(255, 248, 235) },
		rays = 0.045,
	},
	Overcast = {
		intensity = 0.65, precipitation = 0, temperature = 13, wind = 0.4,
		clouds = { Cover = 0.84, Density = 0.82, Color = Color3.fromRGB(182, 192, 200) },
		atmosphere = { Density = 0.335, Offset = 0.06, Haze = 2.25, Glare = 0,
			Color = Color3.fromRGB(193, 208, 218), Decay = Color3.fromRGB(112, 130, 142) },
		lighting = { Brightness = 1.75, ExposureCompensation = -0.13,
			Ambient = Color3.fromRGB(89, 100, 112), OutdoorAmbient = Color3.fromRGB(124, 137, 149) },
		grade = { Brightness = 0, Contrast = 0.06, Saturation = -0.18, TintColor = Color3.fromRGB(232, 243, 255) },
		rays = 0.008,
	},
	Rain = {
		intensity = 0.76, precipitation = 0.78, temperature = 10, wind = 0.58,
		clouds = { Cover = 0.94, Density = 0.91, Color = Color3.fromRGB(145, 160, 178) },
		atmosphere = { Density = 0.37, Offset = 0, Haze = 2.65, Glare = 0,
			Color = Color3.fromRGB(177, 194, 209), Decay = Color3.fromRGB(103, 124, 140) },
		lighting = { Brightness = 1.35, ExposureCompensation = -0.16,
			Ambient = Color3.fromRGB(77, 89, 105), OutdoorAmbient = Color3.fromRGB(108, 122, 138) },
		grade = { Brightness = -0.015, Contrast = 0.08, Saturation = -0.24, TintColor = Color3.fromRGB(226, 239, 255) },
		rays = 0,
	},
	Storm = {
		intensity = 1, precipitation = 1, temperature = 8, wind = 0.88,
		clouds = { Cover = 0.99, Density = 0.96, Color = Color3.fromRGB(113, 131, 154) },
		atmosphere = { Density = 0.4, Offset = -0.02, Haze = 3.05, Glare = 0,
			Color = Color3.fromRGB(163, 181, 201), Decay = Color3.fromRGB(89, 109, 135) },
		lighting = { Brightness = 1.05, ExposureCompensation = -0.2,
			Ambient = Color3.fromRGB(72, 85, 105), OutdoorAmbient = Color3.fromRGB(101, 115, 136) },
		grade = { Brightness = -0.02, Contrast = 0.08, Saturation = -0.3, TintColor = Color3.fromRGB(220, 233, 252) },
		rays = 0,
	},
	Fog = {
		intensity = 0.75, precipitation = 0, temperature = 11, wind = 0.13,
		clouds = { Cover = 0.62, Density = 0.67, Color = Color3.fromRGB(214, 220, 219) },
		atmosphere = { Density = 0.465, Offset = -0.15, Haze = 3.3, Glare = 0.035,
			Color = Color3.fromRGB(207, 217, 216), Decay = Color3.fromRGB(145, 162, 163) },
		lighting = { Brightness = 1.8, ExposureCompensation = -0.09,
			Ambient = Color3.fromRGB(104, 115, 119), OutdoorAmbient = Color3.fromRGB(139, 151, 151) },
		grade = { Brightness = 0.015, Contrast = 0.035, Saturation = -0.24, TintColor = Color3.fromRGB(239, 247, 242) },
		rays = 0.016,
	},
}

local SEQUENCE = {
	{ "Clear", 150 }, { "Overcast", 85 }, { "Rain", 140 }, { "Fog", 100 },
	{ "Clear", 190 }, { "Overcast", 80 }, { "Storm", 110 }, { "Rain", 100 }, { "Clear", 170 },
}

local function effect(className, name, parent)
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

function Weather.start()
	if activeCleanup then
		return activeCleanup
	end
	local stateFolder = ReplicatedStorage:WaitForChild("RoadTrip")
	local terrain = workspace.Terrain
	local clouds = terrain:FindFirstChildOfClass("Clouds") or effect("Clouds", "RoadTripClouds", terrain)
	clouds.Enabled = true
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or effect("Atmosphere", "RoadTripAtmosphere", Lighting)
	local grade = effect("ColorCorrectionEffect", "RoadTripGrade", Lighting)
	local bloom = effect("BloomEffect", "RoadTripBloom", Lighting)
	bloom.Intensity = 0.09
	bloom.Size = 22
	bloom.Threshold = 1.8
	local rays = effect("SunRaysEffect", "RoadTripSunRays", Lighting)
	rays.Spread = 0.7
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3
	Lighting.EnvironmentDiffuseScale = 0.65
	Lighting.EnvironmentSpecularScale = 0.9
	Lighting.GeographicLatitude = 43
	Lighting.FogStart = 0
	Lighting.FogEnd = 100000
	Lighting.ClockTime = 16.35

	local currentTweens = {}
	local values = { intensity = 0.18, precipitation = 0, temperature = 17, wind = 0.18 }
	local fromValues = table.clone(values)
	local targetValues = table.clone(values)
	local elapsed, sequenceElapsed, transitionElapsed, updateElapsed = 0, 0, 35, 0
	local sequenceIndex = 1
	local transitionDuration = 35

	local function setProperties(object, properties, instant)
		if instant then
			for key, value in pairs(properties) do
				object[key] = value
			end
		else
			local tween = TweenService:Create(object, TweenInfo.new(transitionDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), properties)
			table.insert(currentTweens, tween)
			tween:Play()
		end
	end

	local function changeWeather(name, instant)
		for _, tween in ipairs(currentTweens) do
			tween:Cancel()
		end
		table.clear(currentTweens)
		local state = STATES[name]
		stateFolder:SetAttribute("Weather", name)
		fromValues = table.clone(values)
		targetValues = {
			intensity = state.intensity, precipitation = state.precipitation,
			temperature = state.temperature, wind = state.wind,
		}
		transitionElapsed = instant and transitionDuration or 0
		if instant then
			values = table.clone(targetValues)
		end
		setProperties(clouds, state.clouds, instant)
		setProperties(atmosphere, state.atmosphere, instant)
		setProperties(Lighting, state.lighting, instant)
		setProperties(grade, state.grade, instant)
		setProperties(rays, { Intensity = state.rays }, instant)
	end

	local function publish()
		stateFolder:SetAttribute("WeatherIntensity", math.round(values.intensity * 1000) / 1000)
		stateFolder:SetAttribute("Precipitation", math.round(values.precipitation * 1000) / 1000)
		stateFolder:SetAttribute("Temperature", math.round(values.temperature * 10) / 10)
		stateFolder:SetAttribute("WindStrength", math.round(values.wind * 1000) / 1000)
		stateFolder:SetAttribute("ClockTime", Lighting.ClockTime)
	end

	changeWeather("Clear", true)
	publish()
	local connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		sequenceElapsed += dt
		transitionElapsed = math.min(transitionElapsed + dt, transitionDuration)
		updateElapsed += dt
		if sequenceElapsed >= SEQUENCE[sequenceIndex][2] then
			sequenceElapsed = 0
			sequenceIndex = sequenceIndex % #SEQUENCE + 1
			changeWeather(SEQUENCE[sequenceIndex][1], false)
		end
		if updateElapsed < 0.5 then
			return
		end
		updateElapsed = 0
		local alpha = 0.5 - math.cos(math.pi * transitionElapsed / transitionDuration) * 0.5
		for key, target in pairs(targetValues) do
			values[key] = fromValues[key] + (target - fromValues[key]) * alpha
		end
		-- Roughly one real hour to reach dusk; a full day takes twelve hours.
		Lighting.ClockTime = (16.35 + elapsed / 1800) % 24
		publish()
	end)

	local stopped = false
	activeCleanup = function()
		if stopped then
			return
		end
		stopped = true
		connection:Disconnect()
		for _, tween in ipairs(currentTweens) do
			tween:Cancel()
		end
		table.clear(currentTweens)
		activeCleanup = nil
	end
	return activeCleanup
end

return Weather
