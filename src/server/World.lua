-- Bounded, deterministic smooth-terrain streaming. No external asset IDs.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Route = require(ReplicatedStorage:WaitForChild("RoadTrip"):WaitForChild("Route"))

local World = {}
World.__index = World

local TERRAIN_RESOLUTION = 4
local TILE_SIZE = 64
local BASE_Y = -64
local TOP_Y = 384
local ROAD_STEP = 16
local UP = Vector3.yAxis

local COLORS = {
	asphalt = Color3.fromRGB(57, 59, 59),
	dirt = Color3.fromRGB(124, 105, 76),
	shoulder = Color3.fromRGB(130, 128, 116),
	white = Color3.fromRGB(214, 215, 198),
	yellow = Color3.fromRGB(224, 184, 91),
	metal = Color3.fromRGB(132, 141, 144),
	wood = Color3.fromRGB(83, 72, 58),
}

local function part(parent, name, size, cf, color, material, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = collide == true
	p.CanTouch = false
	p.CanQuery = collide == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = true
	p.Parent = parent
	return p
end

local function cylinder(parent, name, a, b, width, color, material, collide)
	local length = (b - a).Magnitude
	local axis = CFrame.lookAt((a + b) * 0.5, b) * CFrame.Angles(0, math.pi / 2, 0)
	local p = part(parent, name, Vector3.new(length, width, width), axis, color, material, collide)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent, name, size, cf, color, material)
	local p = part(parent, name, size, cf, color, material, false)
	p.Shape = Enum.PartType.Ball
	return p
end

local function roadFrame(a, b)
	local first = Route.sample(a).Position
	local last = Route.sample(b).Position
	return CFrame.lookAt((first + last) * 0.5, last, UP), (last - first).Magnitude
end

function World.new(folder, config)
	local self = setmetatable({}, World)
	config = config or {}
	self.folder = folder
	self.terrain = Workspace.Terrain
	self.chunks = {}
	self.generating = {}
	self.running = false
	self.halfWidth = math.floor((config.terrainHalfWidth or 640) / TILE_SIZE) * TILE_SIZE
	self.maxChunks = math.max(5, config.maxChunks or 11)
	self.ahead = config.chunksAhead or 4
	self.behind = config.chunksBehind or 2
	self.treeDensity = config.treeDensity or 1
	self.count = 0
	self.folder:SetAttribute("Ready", false)
	self.folder:SetAttribute("GeneratedChunks", 0)
	self.folder:SetAttribute("WorldSeed", Route.seed)
	self.terrain.WaterColor = Color3.fromRGB(54, 102, 110)
	self.terrain.WaterTransparency = 0.32
	self.terrain.WaterReflectance = 0.42
	self.terrain.WaterWaveSize = 0.16
	self.terrain.WaterWaveSpeed = 7
	pcall(function()
		self.terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(82, 100, 66))
		self.terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(100, 84, 64))
		self.terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(102, 108, 106))
		self.terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(141, 132, 107))
		self.terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(68, 86, 57))
	end)
	return self
end

function World:_terrainTile(x0, z0)
	local cells = TILE_SIZE / TERRAIN_RESOLUTION
	local heights, surfaceMaterials = {}, {}
	local minHeight, maxHeight = math.huge, -math.huge
	for ix = 1, cells do
		heights[ix], surfaceMaterials[ix] = {}, {}
		local x = x0 + (ix - 0.5) * TERRAIN_RESOLUTION
		for iz = 1, cells do
			local z = z0 + (iz - 0.5) * TERRAIN_RESOLUTION
			local h = Route.height(x, z)
			heights[ix][iz] = h
			minHeight, maxHeight = math.min(minHeight, h), math.max(maxHeight, h)
			local roughness = math.abs(Route.height(x + 4, z) - h) + math.abs(Route.height(x, z + 4) - h)
			local surface = Enum.Material.Grass
			if h < Route.waterHeight + 3 then
				surface = Enum.Material.Sand
			elseif h > 222 then
				surface = Enum.Material.Snow
			elseif roughness > 7 or h > 155 then
				surface = Enum.Material.Rock
			elseif math.noise(x / 33, z / 33, 45) > 0.18 then
				surface = Enum.Material.LeafyGrass
			end
			surfaceMaterials[ix][iz] = surface
		end
	end
	local minY = math.max(BASE_Y, math.floor((minHeight - 8) / 4) * 4)
	local maxY = math.min(TOP_Y, math.ceil((math.max(maxHeight + 4, Route.waterHeight)) / 4) * 4)
	if minY > BASE_Y then
		self.terrain:FillBlock(CFrame.new(x0 + TILE_SIZE / 2, (BASE_Y + minY) / 2, z0 + TILE_SIZE / 2), Vector3.new(TILE_SIZE, minY - BASE_Y, TILE_SIZE), Enum.Material.Rock)
	end
	local yCells = (maxY - minY) / TERRAIN_RESOLUTION
	local materials, occupancy = {}, {}
	for ix = 1, cells do
		materials[ix], occupancy[ix] = {}, {}
		for iy = 1, yCells do
			materials[ix][iy], occupancy[ix][iy] = {}, {}
			local bottom = minY + (iy - 1) * TERRAIN_RESOLUTION
			for iz = 1, cells do
				local h = heights[ix][iz]
				local filled = math.clamp((h - bottom) / TERRAIN_RESOLUTION, 0, 1)
				local material = Enum.Material.Air
				if filled > 0 then
					material = if bottom < h - 7 then Enum.Material.Rock else surfaceMaterials[ix][iz]
				elseif bottom < Route.waterHeight then
					material = Enum.Material.Water
					filled = math.clamp((Route.waterHeight - bottom) / TERRAIN_RESOLUTION, 0, 1)
				end
				materials[ix][iy][iz] = material
				occupancy[ix][iy][iz] = filled
			end
		end
	end
	local region = Region3.new(Vector3.new(x0, minY, z0), Vector3.new(x0 + TILE_SIZE, maxY, z0 + TILE_SIZE))
	self.terrain:WriteVoxels(region, TERRAIN_RESOLUTION, materials, occupancy)
end

function World:_road(model, chunkStart)
	for offset = 0, Route.chunkLength - ROAD_STEP, ROAD_STEP do
		local d = chunkStart + offset
		local cf, length = roadFrame(d, d + ROAD_STEP)
		local surface = Route.surface(d + ROAD_STEP / 2)
		local dirt = surface == "Dirt"
		local bridge = surface == "Bridge"
		if bridge then
			part(model, "Bridge deck", Vector3.new(35, 1.8, length + 0.45), cf * CFrame.new(0, -1.08, 0), Color3.fromRGB(118, 124, 121), Enum.Material.Concrete, true)
		else
			part(model, "Compacted shoulder", Vector3.new(41, 0.72, length + 0.5), cf * CFrame.new(0, -0.52, 0), if dirt then COLORS.dirt else COLORS.shoulder, if dirt then Enum.Material.Ground else Enum.Material.Pebble, true)
		end
		local deck = part(model, if dirt then "Forest road" else "Mountain highway", Vector3.new(30, 0.65, length + 0.45), cf * CFrame.new(0, -0.325, 0), if dirt then COLORS.dirt else COLORS.asphalt, if dirt then Enum.Material.Ground else Enum.Material.Asphalt, true)
		deck:SetAttribute("RoadSurface", surface)
		deck.CustomPhysicalProperties = PhysicalProperties.new(2.4, if dirt then 0.72 else 0.88, 0, 100, 1)
		if not dirt then
			for _, side in ipairs({ -1, 1 }) do
				part(model, "Road edge paint", Vector3.new(0.19, 0.022, length + 0.1), cf * CFrame.new(side * 13.9, 0.025, 0), COLORS.white, Enum.Material.SmoothPlastic, false).CastShadow = false
			end
			if math.floor(d / ROAD_STEP) % 2 == 0 then
				part(model, "Center dash", Vector3.new(0.21, 0.025, 8), cf * CFrame.new(0, 0.027, 0), COLORS.yellow, Enum.Material.SmoothPlastic, false).CastShadow = false
			end
		else
			for _, x in ipairs({ -10.2, -3.1, 3.1, 10.2 }) do
				part(model, "Packed wheel track", Vector3.new(0.9, 0.015, length + 0.1), cf * CFrame.new(x, 0.018, 0), Color3.fromRGB(110, 96, 73), Enum.Material.Ground, false).CastShadow = false
			end
		end
		if bridge then
			for _, side in ipairs({ -1, 1 }) do
				part(model, "Bridge curb", Vector3.new(0.85, 0.65, length + 0.5), cf * CFrame.new(side * 16.25, 0.24, 0), Color3.fromRGB(144, 146, 137), Enum.Material.Concrete, true)
				part(model, "Bridge safety rail", Vector3.new(0.48, 0.48, length + 0.5), cf * CFrame.new(side * 16.25, 3.0, 0), COLORS.metal, Enum.Material.Metal, true)
				part(model, "Bridge lower rail", Vector3.new(0.35, 0.25, length + 0.5), cf * CFrame.new(side * 16.25, 1.55, 0), COLORS.metal, Enum.Material.Metal, true)
				part(model, "Bridge rail upright", Vector3.new(0.46, 3.1, 0.46), cf * CFrame.new(side * 16.25, 1.5, 0), COLORS.metal, Enum.Material.Metal, true)
			end
			if math.floor(d / ROAD_STEP) % 3 == 0 then
				local position = cf.Position
				local terrainY = Route.height(position.X, position.Z)
				local height = math.max(1, position.Y - terrainY - 1)
				part(model, "Bridge pier", Vector3.new(23, height, 4.5), CFrame.new(position.X, terrainY + height / 2, position.Z), Color3.fromRGB(107, 117, 112), Enum.Material.Concrete, true)
			end
		end
		-- Galvanized crash barrier follows the exposed lakeside bend.
		local phase = d % Route.period
		if not bridge and phase >= 320 and phase < 768 then
			local cycle = math.floor(d / Route.period)
			local side = if cycle % 2 == 0 then 1 else -1
			part(model, "Lakeside guard rail", Vector3.new(0.36, 0.82, length + 0.55), cf * CFrame.new(side * 20.6, 1.6, 0), COLORS.metal, Enum.Material.Metal, true)
			part(model, "Barrier post", Vector3.new(0.45, 2.1, 0.45), cf * CFrame.new(side * 20.8, 0.8, 0), Color3.fromRGB(113, 124, 122), Enum.Material.Metal, true)
		end
		if math.floor(d / ROAD_STEP) % 4 == 0 and not bridge then
			for _, side in ipairs({ -1, 1 }) do
				local postCF = Route.sample(d + 8) * CFrame.new(side * 20, 1.25, 0)
				part(model, "Road delineator", Vector3.new(0.38, 2.5, 0.4), postCF, Color3.fromRGB(212, 209, 192), Enum.Material.SmoothPlastic, false)
				part(model, "Reflector", Vector3.new(0.41, 0.3, 0.08), postCF * CFrame.new(0, 0.55, 0.23), if side > 0 then Color3.fromRGB(235, 182, 74) else Color3.fromRGB(215, 224, 205), Enum.Material.Neon, false)
			end
		end
	end
end

function World:_tree(parent, position, random, far)
	local model = Instance.new("Model")
	model.Name = "Alpine fir"
	model.Parent = parent
	local height = random:NextNumber(24, 49)
	local radius = height * random:NextNumber(0.12, 0.18)
	local trunkColor = Color3.fromRGB(random:NextInteger(72, 91), random:NextInteger(65, 75), 56)
	cylinder(model, "Bark", position, position + UP * height * 0.88, height * 0.044, trunkColor, Enum.Material.Wood, not far)
	local green = random:NextInteger(-8, 10)
	local rings = if far then 4 else 6
	for layer = 1, rings do
		local t = (layer - 1) / rings
		local y = height * (0.3 + t * 0.61)
		local width = radius * (1 - t * 0.72)
		local branchCF = CFrame.new(position + UP * y) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0)
		local color = Color3.fromRGB(36 + green + layer, 65 + green + layer * 2, 48 + green)
		ball(model, "Needle canopy", Vector3.new(width * 2, height * 0.19, width * 2), branchCF, color, Enum.Material.Grass)
		if not far and layer <= 3 then
			for branch = 0, 2 do
				local angle = branch * math.pi * 2 / 3 + layer
				local tip = position + Vector3.new(math.cos(angle) * width, y - 0.3, math.sin(angle) * width)
				cylinder(model, "Branch", position + UP * (y - 1), tip, 0.25, trunkColor, Enum.Material.Wood, false)
			end
		end
	end
	ball(model, "Crown", Vector3.new(radius * 0.55, height * 0.27, radius * 0.55), CFrame.new(position + UP * height * 0.9), Color3.fromRGB(43 + green, 72 + green, 53 + green), Enum.Material.Grass)
	if random:NextNumber() < 0.15 and not far then
		cylinder(model, "Exposed root", position + Vector3.new(-2, 0.2, 0), position + Vector3.new(1.3, 0.5, 1.8), 0.6, trunkColor, Enum.Material.Wood, false)
	end
end

function World:_rock(parent, position, random, scale)
	local color = random:NextInteger(91, 131)
	local size = Vector3.new(random:NextNumber(3, 10), random:NextNumber(2, 8), random:NextNumber(3, 9)) * scale
	local cf = CFrame.new(position + UP * size.Y * 0.22) * CFrame.Angles(random:NextNumber(-0.2, 0.2), random:NextNumber(0, 6.28), random:NextNumber(-0.25, 0.25))
	local rock = ball(parent, "Weathered granite", size, cf, Color3.fromRGB(color, color + 5, color + 3), Enum.Material.Rock)
	rock.CanCollide = true
	rock.CanQuery = true
	if scale > 1 then
		ball(parent, "Moss on stone", size * Vector3.new(0.66, 0.2, 0.71), cf * CFrame.new(0, size.Y * 0.38, 0), Color3.fromRGB(71, 84, 58), Enum.Material.Grass)
	end
end

function World:_sign(parent, distance, text, subtitle)
	local cf = Route.sample(distance) * CFrame.new(23.8, 0, 0)
	local baseY = Route.height(cf.Position.X, cf.Position.Z)
	local base = Vector3.new(cf.Position.X, baseY, cf.Position.Z)
	cylinder(parent, "Sign post", base, base + UP * 8.3, 0.35, COLORS.metal, Enum.Material.Metal, false)
	local board = part(parent, "Route sign", Vector3.new(10, 4.4, 0.25), CFrame.new(base + UP * 7.2) * cf.Rotation, Color3.fromRGB(38, 66, 61), Enum.Material.Metal, false)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.CanvasSize = Vector2.new(700, 300)
	gui.LightInfluence = 0.8
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 0.65)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = COLORS.white
	label.Font = Enum.Font.GothamBold
	label.TextSize = 53
	label.Parent = gui
	local sub = label:Clone()
	sub.Position = UDim2.fromScale(0, 0.61)
	sub.Size = UDim2.fromScale(1, 0.28)
	sub.Text = subtitle
	sub.Font = Enum.Font.Gotham
	sub.TextSize = 29
	sub.Parent = gui
end

function World:_wildlife(parent, chunkStart, random)
	if math.floor(chunkStart / Route.chunkLength) % 3 == 1 then
		local d = chunkStart + random:NextNumber(45, 200)
		local x = Route.centerX(d) + random:NextNumber(67, 98)
		local y = Route.height(x, -d)
		if y > Route.waterHeight + 3 then
			for deer = 1, random:NextInteger(1, 3) do
				local base = Vector3.new(x + deer * 7, Route.height(x + deer * 7, -d - deer * 4), -d - deer * 4)
				local model = Instance.new("Model")
				model.Name = "Roe deer"
				model.Parent = parent
				local frame = CFrame.new(base) * CFrame.Angles(0, random:NextNumber(0, 6.28), 0)
				local coat = Color3.fromRGB(122, 89, 60)
				ball(model, "Body", Vector3.new(1.8, 2.05, 3.55), frame * CFrame.new(0, 3, 0), coat, Enum.Material.SmoothPlastic)
				ball(model, "Neck", Vector3.new(1.05, 2.1, 1), frame * CFrame.new(0, 4.05, -1.2) * CFrame.Angles(-0.3, 0, 0), coat, Enum.Material.SmoothPlastic)
				ball(model, "Head", Vector3.new(0.95, 1.1, 1.5), frame * CFrame.new(0, 4.85, -1.7), coat, Enum.Material.SmoothPlastic)
				for _, side in ipairs({ -1, 1 }) do
					ball(model, "Ear", Vector3.new(0.35, 0.8, 0.32), frame * CFrame.new(side * 0.48, 5.45, -1.55) * CFrame.Angles(0, 0, side * -0.4), coat, Enum.Material.SmoothPlastic)
					for _, depth in ipairs({ -0.95, 0.95 }) do
						local top = frame:PointToWorldSpace(Vector3.new(side * 0.65, 2.7, depth))
						local bottom = frame:PointToWorldSpace(Vector3.new(side * 0.63, 0.2, depth + 0.1))
						cylinder(model, "Leg", top, bottom, 0.22, coat, Enum.Material.SmoothPlastic, false)
					end
				end
				ball(model, "Tail", Vector3.new(0.5, 0.6, 0.6), frame * CFrame.new(0, 3.5, 1.7), Color3.fromRGB(201, 190, 169), Enum.Material.SmoothPlastic)
				model:SetAttribute("Wildlife", "Deer")
				CollectionService:AddTag(model, "RoadTripDeer")
			end
		end
	end
end

function World:_decorate(model, chunkStart, index)
	local random = Random.new((Route.seed + index * 7919) % 2147483647)
	for attempt = 1, math.floor(72 * self.treeDensity) do
		local d = chunkStart + random:NextNumber(2, Route.chunkLength - 2)
		local side = if random:NextNumber() < 0.5 then -1 else 1
		local offset = random:NextNumber(34, self.halfWidth - 55)
		local x = Route.centerX(d) + offset * side
		if math.abs(x) < self.halfWidth - 15 then
			local y = Route.height(x, -d)
			local gradient = math.abs(Route.height(x + 5, -d) - y)
			if y > Route.waterHeight + 4 and y < 158 and gradient < 9 and Route.lakeDistance(x, d) > 1.05 then
				self:_tree(model, Vector3.new(x, y - 0.25, -d), random, offset > 185)
			end
		end
	end
	for _ = 1, 21 do
		local d = chunkStart + random:NextNumber(2, Route.chunkLength - 2)
		local side = if random:NextNumber() < 0.5 then -1 else 1
		local offset = random:NextNumber(29, self.halfWidth - 155)
		local x = Route.centerX(d) + side * offset
		local y = Route.height(x, -d)
		if y > Route.waterHeight + 1 then
			self:_rock(model, Vector3.new(x, y, -d), random, if offset > 100 then random:NextNumber(0.8, 2.6) else 0.75)
		end
	end
	for _ = 1, 13 do
		local d = chunkStart + random:NextNumber(4, Route.chunkLength - 4)
		local side = if random:NextNumber() < 0.5 then -1 else 1
		local x = Route.centerX(d) + side * random:NextNumber(28, 120)
		local y = Route.height(x, -d)
		if y > Route.waterHeight + 4 and y < 140 then
			local width = random:NextNumber(2, 4.5)
			for leaf = 1, 3 do
				local position = Vector3.new(x + random:NextNumber(-1.5, 1.5), y + width * 0.3, -d + random:NextNumber(-1, 1))
				ball(model, "Mountain heather", Vector3.new(width, width * 0.65, width), CFrame.new(position), Color3.fromRGB(65 + leaf * 4, 80 + leaf * 5, 51 + leaf * 3), Enum.Material.LeafyGrass)
			end
		end
	end
	if index % 2 == 0 then
		local d = chunkStart + 185
		local x = Route.centerX(d) - 58
		local y = Route.height(x, -d)
		if y > Route.waterHeight + 3 then
			local a = Vector3.new(x - 6, y + 0.95, -d - 3)
			local b = Vector3.new(x + 6, y + 1.3, -d + 3)
			cylinder(model, "Fallen spruce", a, b, 1.9, Color3.fromRGB(82, 72, 57), Enum.Material.Wood, true)
			local axis = (b - a).Unit
			cylinder(model, "Exposed timber", b, b + axis * 0.025, 1.58, Color3.fromRGB(161, 140, 102), Enum.Material.Wood, false)
		end
	end
	-- A small pull-off cabin repeats only once every twelve terrain chunks.
	if index % 12 == 0 then
		local d = chunkStart + 110
		local road = Route.sample(d)
		local center = road.Position + road.RightVector * 48
		local groundY = Route.height(center.X, center.Z)
		local cf = CFrame.new(center.X, groundY, center.Z) * road.Rotation
		local cabin = Instance.new("Model")
		cabin.Name = "Trail shelter"
		cabin.Parent = model
		part(cabin, "Stone foundation", Vector3.new(17, 2.3, 13), cf * CFrame.new(0, 0.6, 0), Color3.fromRGB(112, 116, 109), Enum.Material.Slate, true)
		for _, side in ipairs({ -1, 1 }) do
			part(cabin, "Timber post", Vector3.new(0.65, 8, 0.65), cf * CFrame.new(side * 7, 5, -5), COLORS.wood, Enum.Material.Wood, true)
			part(cabin, "Timber post", Vector3.new(0.65, 8, 0.65), cf * CFrame.new(side * 7, 5, 5), COLORS.wood, Enum.Material.Wood, true)
			part(cabin, "Pitched shelter roof", Vector3.new(9.2, 0.65, 15), cf * CFrame.new(side * 4.1, 9.8, 0) * CFrame.Angles(0, 0, -side * 0.3), Color3.fromRGB(72, 76, 72), Enum.Material.Slate, true)
		end
		part(cabin, "Bench seat", Vector3.new(12, 0.55, 2), cf * CFrame.new(0, 3, 3.8), COLORS.wood, Enum.Material.Wood, true)
		part(cabin, "Bench back", Vector3.new(12, 2.5, 0.4), cf * CFrame.new(0, 4.15, 4.8), COLORS.wood, Enum.Material.Wood, true)
		self:_sign(model, chunkStart + 40, "ALPINE ROUTE", "SCENIC DRIVE  /  KEEP RIGHT")
	elseif index % 12 == 3 then
		self:_sign(model, chunkStart + 80, "RIVER CROSSING", "NARROW BRIDGE AHEAD")
	elseif index % 12 == 7 then
		self:_sign(model, chunkStart + 40, "FOREST ROAD", "LOOSE SURFACE  /  SLOW")
	end
	self:_wildlife(model, chunkStart, random)
end

function World:_buildChunk(index)
	if self.chunks[index] then
		return
	end
	if self.generating[index] then
		repeat task.wait(0.05) until not self.generating[index]
		return
	end
	self.generating[index] = true
	local model = Instance.new("Model")
	model.Name = string.format("Alpine_%d", index)
	model:SetAttribute("ChunkIndex", index)
	model.Parent = self.folder
	local chunkStart = index * Route.chunkLength
	local ok, failure = pcall(function()
		-- Colliders are installed first; terrain and scenery follow cooperatively.
		self:_road(model, chunkStart)
		local tileCount = 0
		local zStart = -(index + 1) * Route.chunkLength
		for x = -self.halfWidth, self.halfWidth - TILE_SIZE, TILE_SIZE do
			for z = zStart, zStart + Route.chunkLength - TILE_SIZE, TILE_SIZE do
				self:_terrainTile(x, z)
				tileCount += 1
				if tileCount % 4 == 0 then
					task.wait()
				end
			end
		end
		self:_decorate(model, chunkStart, index)
	end)
	self.generating[index] = nil
	if not ok then
		model:Destroy()
		error(string.format("Terrain chunk %d failed: %s", index, tostring(failure)))
	end
	self.chunks[index] = model
	self.count += 1
	self.folder:SetAttribute("GeneratedChunks", self.count)
end

function World:_removeChunk(index)
	local model = self.chunks[index]
	if not model then
		return
	end
	model:Destroy()
	self.chunks[index] = nil
	local zCenter = -(index + 0.5) * Route.chunkLength
	self.terrain:FillBlock(CFrame.new(0, (TOP_Y + BASE_Y) / 2, zCenter), Vector3.new(self.halfWidth * 2, TOP_Y - BASE_Y, Route.chunkLength), Enum.Material.Air)
	self.count -= 1
	self.folder:SetAttribute("GeneratedChunks", self.count)
end

function World:ensureAround(distance)
	local center = math.floor(distance / Route.chunkLength)
	for _, offset in ipairs({ 0, -1, 1 }) do
		self:_buildChunk(center + offset)
	end
	self.folder:SetAttribute("Ready", true)
end

function World:start(getFocusPositions)
	if self.running then
		return
	end
	self.running = true
	self.thread = task.spawn(function()
		while self.running do
			local ok, positions = pcall(getFocusPositions)
			if not ok or typeof(positions) ~= "table" or #positions == 0 then
				positions = { Route.sample(0).Position }
			end
			local priorities = {}
			for _, position in ipairs(positions) do
				local center = math.floor(-position.Z / Route.chunkLength)
				for offset = -self.behind, self.ahead do
					local index = center + offset
					local priority = math.abs(offset) + (if offset < 0 then 0.35 else 0)
					priorities[index] = math.min(priorities[index] or math.huge, priority)
				end
			end
			local desired = {}
			for index, priority in pairs(priorities) do
				table.insert(desired, { index = index, priority = priority })
			end
			table.sort(desired, function(a, b)
				if a.priority == b.priority then
					return a.index < b.index
				end
				return a.priority < b.priority
			end)
			local wanted = {}
			for rank = 1, math.min(#desired, self.maxChunks) do
				wanted[desired[rank].index] = true
			end
			for index in pairs(self.chunks) do
				if not wanted[index] then
					self:_removeChunk(index)
				end
			end
			local built = false
			for rank = 1, math.min(#desired, self.maxChunks) do
				local index = desired[rank].index
				if not self.chunks[index] then
					local success, reason = pcall(function() self:_buildChunk(index) end)
					if not success then
						warn("[Alpine world] " .. tostring(reason))
						self.folder:SetAttribute("GenerationError", tostring(reason))
						task.wait(1)
					end
					built = true
					break
				end
			end
			task.wait(if built then 0.04 else 0.4)
		end
	end)
end

function World:stop()
	self.running = false
end

return World
