-- Texture-free local weather and distant wildlife. Pools stay bounded at any trip length.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")

local Atmosphere = {}
local activeCleanup
local UP = Vector3.new(0, 1, 0)
local RAIN_COUNT = 112
local BIRD_COUNT = 15

local function visualPart(className, name, size, color, parent)
	local part = Instance.new(className)
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

local function bird(parent, index)
	local model = Instance.new("Model")
	model.Name = "AlpineSwift" .. index
	model.Parent = parent
	local color = Color3.fromRGB(55, 62, 64)
	local body = visualPart("Part", "Body", Vector3.new(0.2, 0.21, 0.68), color, model)
	local bodyMesh = Instance.new("SpecialMesh")
	bodyMesh.MeshType = Enum.MeshType.Sphere
	bodyMesh.Parent = body
	local left = visualPart("WedgePart", "LeftWing", Vector3.new(0.065, 1.26, 0.62), color, model)
	local right = visualPart("WedgePart", "RightWing", Vector3.new(0.065, 1.26, 0.62), color, model)
	local tail = visualPart("WedgePart", "Tail", Vector3.new(0.045, 0.36, 0.42), color, model)
	return { body = body, left = left, right = right, tail = tail, index = index }
end

function Atmosphere.start()
	if activeCleanup then
		return activeCleanup
	end
	local player = Players.LocalPlayer
	local state = ReplicatedStorage:WaitForChild("RoadTrip")
	local random = Random.new(729103)
	local folder = Instance.new("Folder")
	folder.Name = "RoadTripLocalAtmosphere"
	folder.Parent = workspace
	local flash = Instance.new("ColorCorrectionEffect")
	flash.Name = "RoadTripDistantLightning"
	flash.Parent = Lighting
	local rain = table.create(RAIN_COUNT)
	local birds = table.create(BIRD_COUNT)
	for index = 1, RAIN_COUNT do
		local length = random:NextNumber(0.6, 1.65)
		local part = visualPart("Part", "Rain", Vector3.new(0.022, length, 0.022), Color3.fromRGB(200, 217, 228), folder)
		part.Transparency = 1
		rain[index] = { part = part, position = Vector3.zero, floor = -math.huge, length = length, spawned = false, age = 0 }
	end
	for index = 1, BIRD_COUNT do
		birds[index] = bird(folder, index)
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = false
	local function updateFilter()
		local ignore = { folder }
		if player.Character then
			table.insert(ignore, player.Character)
		end
		rayParams.FilterDescendantsInstances = ignore
	end
	updateFilter()
	local characterConnection = player.CharacterAdded:Connect(updateFilter)
	local elapsed, rainLevel, weatherPoll, shelterPoll = 0, 0, 1, 1
	local precipitation, wind, sheltered, storm = 0, 0.18, false, false
	local flashValue, nextLightning = 0, 22
	local flockCenter
	local deerEntries = {}
	local deerScan, deerTick = 2, 0

	local function restoreDeer(entry)
		for part, original in pairs(entry.originals) do
			if part.Parent then
				part.CFrame = original
			end
		end
	end

	local function scanDeer(cameraPosition)
		local nearby = {}
		for _, model in ipairs(CollectionService:GetTagged("RoadTripDeer")) do
			local body = model:FindFirstChild("Body")
			if model:IsDescendantOf(workspace) and body and body:IsA("BasePart") then
				local distance = (body.Position - cameraPosition).Magnitude
				if distance < 350 then
					table.insert(nearby, { model = model, body = body, distance = distance })
				end
			end
		end
		table.sort(nearby, function(a, b) return a.distance < b.distance end)
		local selected = {}
		for index = 1, math.min(10, #nearby) do
			local item = nearby[index]
			selected[item.model] = true
			if not deerEntries[item.model] then
				local originals = {}
				for _, part in ipairs(item.model:GetChildren()) do
					if part:IsA("BasePart") and (part.Name == "Neck" or part.Name == "Head" or part.Name == "Ear" or part.Name == "Tail") then
						originals[part] = part.CFrame
					end
				end
				deerEntries[item.model] = {
					originals = originals,
					pivot = item.body.CFrame * CFrame.new(0, 0, -0.6),
					phase = (item.body.Position.X * 0.13 + item.body.Position.Z * 0.07) % (math.pi * 2),
				}
			end
		end
		for model, entry in pairs(deerEntries) do
			if not selected[model] then
				restoreDeer(entry)
				deerEntries[model] = nil
			end
		end
	end

	local function spawnDrop(drop, cameraPosition, forward)
		local center = cameraPosition + forward * (sheltered and 20 or 10)
		drop.position = center + Vector3.new(random:NextNumber(-24, 24), random:NextNumber(-8, 20), random:NextNumber(-24, 24))
		-- Reject covered positions, and stop a streak when it reaches terrain or a roof.
		local hit = workspace:Raycast(drop.position + UP * 20, -UP * 90, rayParams)
		drop.floor = hit and hit.Position.Y or cameraPosition.Y - 65
		drop.spawned = drop.position.Y > drop.floor + 0.8
		-- Back off when terrain or shelter covers the whole sampling volume.
		drop.age = drop.spawned and 0 or -random:NextNumber(0.1, 0.3)
	end

	local connection = RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		dt = math.min(dt, 0.1)
		elapsed += dt
		weatherPoll += dt
		shelterPoll += dt
		local cameraPosition = camera.CFrame.Position
		local look = camera.CFrame.LookVector
		local horizontal = Vector3.new(look.X, 0, look.Z)
		local forward = horizontal.Magnitude > 0.01 and horizontal.Unit or Vector3.new(0, 0, -1)
		deerScan += dt
		deerTick += dt
		if deerScan >= 2 then
			deerScan = 0
			scanDeer(cameraPosition)
		end
		if deerTick >= 1 / 12 then
			deerTick = 0
			for model, entry in pairs(deerEntries) do
				if model.Parent then
					local graze = math.clamp(0.5 + math.sin(elapsed * 0.32 + entry.phase) * 0.72, 0, 1)
					local turn = CFrame.Angles(-0.08 - graze * 1.17, math.sin(elapsed * 0.22 + entry.phase) * 0.16, 0)
					local rotation = entry.pivot * turn * entry.pivot:Inverse()
					for part, original in pairs(entry.originals) do
						if part.Parent then
							if part.Name == "Tail" then
								part.CFrame = original * CFrame.Angles(0, math.sin(elapsed * 2.2 + entry.phase) * 0.12, 0)
							else
								part.CFrame = rotation * original
							end
						end
					end
				end
			end
		end
		if weatherPoll >= 0.4 then
			weatherPoll = 0
			precipitation = state:GetAttribute("Precipitation") or 0
			wind = state:GetAttribute("WindStrength") or 0.18
			storm = state:GetAttribute("Weather") == "Storm"
		end
		if shelterPoll >= 0.3 then
			shelterPoll = 0
			sheltered = workspace:Raycast(cameraPosition, UP * 24, rayParams) ~= nil
		end
		rainLevel += (precipitation - rainLevel) * (1 - math.exp(-dt * 2))
		local activeCount = math.floor(RAIN_COUNT * rainLevel)
		local velocity = Vector3.new(7 + wind * 15, -67 - wind * 15, wind * 5)
		local direction = velocity.Unit
		for index, drop in ipairs(rain) do
			if index <= activeCount then
				drop.age += dt
				drop.position += velocity * dt
				local offset = drop.position - cameraPosition
				local needsSpawn = not drop.spawned and drop.age >= 0
				local expired = drop.spawned and (drop.position.Y < drop.floor + drop.length or offset.Magnitude > 65 or drop.age > 0.85)
				if needsSpawn or expired then
					spawnDrop(drop, cameraPosition, forward)
				end
				if drop.spawned then
					drop.part.CFrame = CFrame.lookAt(drop.position, drop.position + direction) * CFrame.Angles(math.pi / 2, 0, 0)
					drop.part.Transparency = 0.71 + (1 - rainLevel) * 0.13
				else
					drop.part.Transparency = 1
				end
			else
				drop.part.Transparency = 1
				drop.spawned = false
			end
		end

		-- Swifts circle in loose, uneven flocks, well beyond the vehicle's immediate space.
		local separation = flockCenter and flockCenter - cameraPosition
		if not flockCenter or separation.Magnitude > 520 or separation:Dot(forward) < -155 then
			flockCenter = cameraPosition + forward * 250 + UP * 76
			local ground = workspace:Raycast(flockCenter + UP * 400, -UP * 650, rayParams)
			if ground then
				flockCenter = Vector3.new(flockCenter.X, math.max(flockCenter.Y, ground.Position.Y + 75), flockCenter.Z)
			end
		end
		for index, item in ipairs(birds) do
			local flock = math.floor((index - 1) / 5)
			local phase = elapsed * (0.22 + flock * 0.024) + index * 0.41 + flock * 2.3
			local radius = 40 + flock * 28
			local formation = Vector3.new((index % 5 - 2) * 4, math.sin(index * 7.3) * 6 + flock * 14, (index % 5) * 2)
			local position = flockCenter + Vector3.new(math.cos(phase) * radius, math.sin(phase * 1.6) * 5, math.sin(phase) * radius) + formation
			local heading = Vector3.new(-math.sin(phase), math.cos(phase * 1.6) * 0.07, math.cos(phase))
			local frame = CFrame.lookAt(position, position + heading) * CFrame.Angles(0, 0, math.sin(phase) * 0.15)
			local flap = math.sin(elapsed * (8.3 + (index % 3) * 0.7) + index) * 0.48
			if math.sin(elapsed * 0.41 + index) > 0.45 then
				flap = 0.06 -- An intermittent glide reads more naturally than continuous flapping.
			end
			item.body.CFrame = frame
			item.left.CFrame = frame * CFrame.new(-0.63, 0.04, 0.03) * CFrame.Angles(0, 0, math.pi / 2 + flap)
			item.right.CFrame = frame * CFrame.new(0.63, 0.04, 0.03) * CFrame.Angles(0, math.pi, -math.pi / 2 - flap)
			item.tail.CFrame = frame * CFrame.new(0, 0, 0.45) * CFrame.Angles(0, 0, math.pi / 2)
			local transparency = math.clamp(rainLevel * 0.9, 0, 0.9)
			item.body.Transparency = transparency
			item.left.Transparency = transparency
			item.right.Transparency = transparency
			item.tail.Transparency = transparency
		end

		if storm and elapsed >= nextLightning then
			flashValue = 0.085
			nextLightning = elapsed + random:NextNumber(23, 41)
		elseif not storm then
			nextLightning = math.max(nextLightning, elapsed + 16)
		end
		flashValue *= math.exp(-dt * 5)
		flash.Brightness = flashValue
	end)

	local stopped = false
	activeCleanup = function()
		if stopped then
			return
		end
		stopped = true
		connection:Disconnect()
		characterConnection:Disconnect()
		for _, entry in pairs(deerEntries) do
			restoreDeer(entry)
		end
		table.clear(deerEntries)
		folder:Destroy()
		flash:Destroy()
		activeCleanup = nil
	end
	return activeCleanup
end

return Atmosphere
