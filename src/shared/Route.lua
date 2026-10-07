-- Shared, deterministic route geometry. Distances increase toward world -Z.
local Route = {}

Route.seed = 24681357
Route.roadHalfWidth = 15
Route.chunkLength = 256
Route.waterHeight = 20
Route.period = 3072

local function smoothstep(a, b, x)
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

function Route.centerX(distance)
	return 88 * math.sin(distance / 810) + 36 * math.sin(distance / 305)
end

function Route.roadHeight(distance)
	-- The analytical minimum is 23: even the lowest road stays above water (20).
	return 32 + 6 * math.sin(distance / 1120) + 3 * math.sin(distance / 430)
end

function Route.sample(distance)
	local p = Vector3.new(Route.centerX(distance), Route.roadHeight(distance), -distance)
	local nextP = Vector3.new(Route.centerX(distance + 1), Route.roadHeight(distance + 1), -distance - 1)
	return CFrame.lookAt(p, nextP, Vector3.yAxis)
end

function Route.spawn(distance, laneOffset)
	return Route.sample(distance) * CFrame.new(laneOffset or 6.5, 3.4, 0)
end

function Route.surface(distance)
	local phase = distance % Route.period
	if phase >= 944 and phase < 1152 then
		return "Bridge"
	elseif phase >= 1888 and phase < 2688 then
		return "Dirt"
	end
	return "Asphalt"
end

function Route.riverDistance(x, distance)
	local cycle = math.floor((distance - 1048 + Route.period / 2) / Route.period)
	local crossing = cycle * Route.period + 1048
	return math.abs(distance - (crossing + 25 * math.sin(x / 140) + x * 0.045))
end

function Route.lakeDistance(x, distance)
	local cycle = math.floor((distance - 390 + Route.period / 2) / Route.period)
	local centerD = cycle * Route.period + 390
	local side = if cycle % 2 == 0 then 1 else -1
	local centerX = Route.centerX(centerD) + side * 205
	return math.sqrt(((x - centerX) / 138) ^ 2 + ((distance - centerD) / 215) ^ 2)
end

function Route.height(x, z)
	local d = -z
	local roadY = Route.roadHeight(d)
	local offset = math.abs(x - Route.centerX(d))
	local n1 = math.noise(x / 360, z / 430, Route.seed % 10000)
	local n2 = math.noise(x / 130, z / 165, 93.7)
	local n3 = math.noise(x / 48, z / 52, 22.4)
	local mountainRise = smoothstep(55, 465, offset)
	local ridge = 80 + 200 * math.abs(n1) + 40 * math.sin(d / 1600 + x / 410) ^ 2
	local height = roadY - 1.2 + mountainRise * ridge + n2 * 24 + n3 * 7
	-- A wide, level verge avoids terrain protruding through the road collider.
	height = (roadY - 0.75) + (height - (roadY - 0.75)) * smoothstep(19, 46, offset)
	local lake = Route.lakeDistance(x, d)
	if lake < 1.32 then
		local basin = 9 + 7 * lake * lake
		height = basin + (height - basin) * smoothstep(0.85, 1.32, lake)
	end
	local riverDistance = Route.riverDistance(x, d)
	local riverBed = 9 + math.min(riverDistance, 34) * 0.13
	height = riverBed + (height - riverBed) * smoothstep(22, 86, riverDistance)
	-- Away from bridges, the final road clearance wins over valleys and lakes.
	if Route.surface(d) ~= "Bridge" and offset < 32 then
		local roadBlend = 1 - smoothstep(19, 32, offset)
		height = height + (roadY - 0.75 - height) * roadBlend
	end
	return height
end

function Route.biome(x, z)
	local h = Route.height(x, z)
	if h < Route.waterHeight + 3 then
		return "Shore"
	elseif h > 171 then
		return "Alpine"
	elseif Route.surface(-z) == "Dirt" then
		return "Forest"
	end
	return "Meadow"
end

return Route
