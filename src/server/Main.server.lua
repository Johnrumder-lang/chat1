-- NORTHBOUND · server lifecycle and authoritative vehicle ownership.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local shared = ReplicatedStorage:WaitForChild("RoadTrip")
local Route = require(shared.Route)
local World = require(script.Parent.World)
local Weather = require(script.Parent.Weather)
local cars = workspace:WaitForChild("Vehicles")
local scenery = workspace:WaitForChild("Scenery")
local remote = shared:WaitForChild("Action")
local template = ServerStorage:WaitForChild("AsterTouring")
local preview = workspace:FindFirstChild("EditorPreview")
shared:SetAttribute("WorldReady", false)
shared:SetAttribute("Title", "NORTHBOUND")

local vehicles = {}
local cooldowns = {}
local allowedActions = {Drive=true, Recover=true, Lights=true, Wipers=true}
local world = World.new(scenery)
Weather.start()

local function rootOf(car)
    return car and car:FindFirstChild("Chassis", true)
end

local function setLights(car, enabled)
    car:SetAttribute("Headlights", enabled)
    for _, item in car:GetDescendants() do
        if item:IsA("SpotLight") and item.Name == "RoadLamp" then
            item.Enabled = enabled
        elseif item:IsA("BasePart") and item.Name == "Headlight" then
            item.Material = enabled and Enum.Material.Neon or Enum.Material.Glass
        end
    end
end

local function putInCar(player)
    local car = vehicles[player]
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local seat = car and car:FindFirstChild("DriverSeat", true)
    if not humanoid or not seat or humanoid.Health <= 0 then return end
    humanoid.JumpPower = 0
    humanoid.JumpHeight = 0
    if humanoid.SeatPart == seat then return end
    character:PivotTo(seat.CFrame * CFrame.new(0, 2, 0))
    seat:Sit(humanoid)
    -- Seat weld creation is asynchronous. One bounded retry handles a fresh spawn.
    task.delay(0.35, function()
        if player.Character == character and humanoid.Health > 0 and seat.Parent and not seat.Occupant then
            seat:Sit(humanoid)
        end
    end)
end

local function createCar(player)
    if vehicles[player] then return vehicles[player] end
    local car = template:Clone()
    car.Name = "Aster_" .. player.UserId
    car:SetAttribute("OwnerUserId", player.UserId)
    car:SetAttribute("Headlights", true)
    car:SetAttribute("Wipers", true)
    car:SetAttribute("Odometer", 0)
    local index = #cars:GetChildren()
    car:PivotTo(Route.spawn(-index * 24, -7) * CFrame.new(0,-1.4,0))
    local root = rootOf(car)
    -- A parked car stays safe while the client streams the opening road.
    root.Anchored = true
    car.Parent = cars
    vehicles[player] = car
    setLights(car, true)
    return car
end

local function characterAdded(player, character)
    while not shared:GetAttribute("WorldReady") and player.Parent do task.wait(0.2) end
    if not player.Parent or player.Character ~= character then return end
    local car = createCar(player)
    local humanoid = character:WaitForChild("Humanoid")
    humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    character:PivotTo(car:GetPivot() * CFrame.new(-8, 3, 0))
    if player:GetAttribute("Driving") then task.delay(0.25, putInCar, player) end
end

local function playerAdded(player)
    player:SetAttribute("Driving", false)
    player.CharacterAdded:Connect(function(character) characterAdded(player, character) end)
    if player.Character then task.spawn(characterAdded, player, player.Character) end
end
Players.PlayerAdded:Connect(playerAdded)
for _, player in Players:GetPlayers() do playerAdded(player) end
Players.PlayerRemoving:Connect(function(player)
    if vehicles[player] then vehicles[player]:Destroy() end
    vehicles[player], cooldowns[player] = nil, nil
end)

remote.OnServerEvent:Connect(function(player, action)
    if type(action) ~= "string" or not allowedActions[action] or not shared:GetAttribute("WorldReady") then return end
    local now = os.clock()
    local recent = cooldowns[player] or {}
    cooldowns[player] = recent
    local interval = action == "Recover" and 5 or 0.35
    if now - (recent[action] or -100) < interval then return end
    recent[action] = now
    local car = vehicles[player]
    if not car then return end
    if action == "Drive" then
        local root = rootOf(car)
        if root.Anchored then
            root.Anchored = false
            root:SetNetworkOwner(player)
        end
        player:SetAttribute("Driving", true)
        putInCar(player)
    elseif not player:GetAttribute("Driving") then
        return
    elseif action == "Recover" then
        local root = rootOf(car)
        local distance = math.clamp(-root.Position.Z, -128, 20000000)
        -- The nearby road already exists; recovering never accepts a client position.
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        car:PivotTo(Route.spawn(distance, -7))
        root:SetNetworkOwner(player)
        putInCar(player)
    elseif action == "Lights" then
        setLights(car, not car:GetAttribute("Headlights"))
    elseif action == "Wipers" then
        car:SetAttribute("Wipers", not car:GetAttribute("Wipers"))
    end
end)

world:ensureAround(0)
if preview then preview:Destroy() end
shared:SetAttribute("WorldReady", true)
world:start(function()
    local positions = {}
    for _, car in pairs(vehicles) do
        local root = rootOf(car)
        if root then table.insert(positions, root.Position) end
    end
    if #positions == 0 then positions[1] = Route.sample(0).Position end
    return positions
end)

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
    elapsed += dt
    if elapsed < 0.5 then return end
    local step = elapsed
    elapsed = 0
    for player, car in pairs(vehicles) do
        local root = rootOf(car)
        if root then
            local speed = math.min(root.AssemblyLinearVelocity.Magnitude, 250)
            car:SetAttribute("Odometer", (car:GetAttribute("Odometer") or 0) + speed * step * 0.28 / 1000)
            if root.Position.Y < -150 then
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                car:PivotTo(Route.spawn(-root.Position.Z, -7))
                root:SetNetworkOwner(player)
            end
        end
    end
end)
