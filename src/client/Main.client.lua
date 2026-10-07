-- NORTHBOUND · first-person driving, local suspension and cockpit controls.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("RoadTrip")
local scenery = workspace:WaitForChild("Scenery")
local action = shared:WaitForChild("Action")
local Physics = require(shared:WaitForChild("VehiclePhysics"))
local Route = require(shared:WaitForChild("Route"))
local Interface = require(script.Parent:WaitForChild("Interface"))
local Atmosphere = require(script.Parent:WaitForChild("Atmosphere"))
local driving = false
local localRoadReady = false
local vehicle, chassis, controller, eye
local keys, touch = {}, {}
local yaw, pitch, steer = 0, 0, 0
local looking = false
local elapsed, menuTime, wheelTime = 0, 0, 0
local cameraBump = Vector3.zero
local hiddenCharacter
local steeringJoint, steeringBase, wipers, gauges = nil, nil, {}, {}
local lastVelocity = Vector3.zero
local gamepadThrottle, gamepadSteer = 0, 0
local rightTrigger, leftTrigger = 0, 0

task.spawn(function()
    local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
    playerModule:GetControls():Disable()
end)

local function request(kind)
    local state, ending = kind:match("^(%a+)(On)$")
    if not state then state, ending = kind:match("^(%a+)(Off)$") end
    if state then touch[state] = ending == "On"; return end
    if kind == "Drive" and shared:GetAttribute("WorldReady") then
        action:FireServer("Drive")
    elseif kind == "Lights" or kind == "Wipers" or kind == "Recover" then
        action:FireServer(kind)
    end
end
local ui = Interface.new(request)
Atmosphere.start()

local function hideCharacter(character)
    hiddenCharacter = character
    for _, child in character:GetDescendants() do
        if child:IsA("BasePart") then child.LocalTransparencyModifier = 1 end
    end
end

local function adoptCar(car)
    if vehicle == car then return end
    if controller then controller:destroy() end
    vehicle = car
    localRoadReady = false
    chassis = car:WaitForChild("Chassis")
    eye = chassis:WaitForChild("DriverEye")
    controller = Physics.new(car)
    steeringJoint = chassis:FindFirstChild("Steering")
    steeringBase = steeringJoint and steeringJoint.C0
    gauges = {}
    for index = 1, 3 do
        local joint = chassis:FindFirstChild("Gauge" .. index)
        if joint then table.insert(gauges, {joint=joint, base=joint.C0, index=index}) end
    end
    wipers = {}
    for _, name in {"WiperL", "WiperR"} do
        local joint = chassis:FindFirstChild(name)
        if joint and joint:IsA("Motor6D") then table.insert(wipers, {joint = joint, base = joint.C0}) end
    end
    task.spawn(function()
        pcall(function() player:RequestStreamAroundAsync(chassis.Position, 12) end)
        local filter = RaycastParams.new()
        filter.FilterType = Enum.RaycastFilterType.Exclude
        filter.FilterDescendantsInstances = {car, player.Character}
        while vehicle == car and car.Parent do
            local hit = workspace:Raycast(chassis.Position + Vector3.new(0,10,0), Vector3.new(0,-30,0), filter)
            if hit and hit.Material ~= Enum.Material.Water then localRoadReady = true; break end
            task.wait(.2)
        end
    end)
end

task.spawn(function()
    local folder = workspace:WaitForChild("Vehicles")
    while true do
        local car = folder:FindFirstChild("Aster_" .. player.UserId)
        if car and car ~= vehicle then adoptCar(car) end
        task.wait(0.3)
    end
end)

local function updateDriving()
    driving = player:GetAttribute("Driving") == true
    ui:setDriving(driving)
    if driving and player.Character then hideCharacter(player.Character) end
end
player:GetAttributeChangedSignal("Driving"):Connect(updateDriving)
player.CharacterAdded:Connect(function(character)
    if driving then task.defer(hideCharacter, character) end
end)
updateDriving()

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then looking = true end
    keys[input.KeyCode] = true
    if not driving then return end
    if input.KeyCode == Enum.KeyCode.H then request("Lights")
    elseif input.KeyCode == Enum.KeyCode.V then request("Wipers")
    elseif input.KeyCode == Enum.KeyCode.R then request("Recover") end
end)
UserInputService.InputEnded:Connect(function(input)
    keys[input.KeyCode] = nil
    if input.UserInputType == Enum.UserInputType.MouseButton2 then looking = false end
end)
UserInputService.WindowFocusReleased:Connect(function()
    keys, touch = {}, {}
    gamepadThrottle, gamepadSteer, rightTrigger, leftTrigger = 0, 0, 0, 0
    looking = false
end)
UserInputService.InputChanged:Connect(function(input, processed)
    if input.UserInputType == Enum.UserInputType.MouseMovement and looking and driving then
        yaw = math.clamp(yaw - input.Delta.X * 0.003, -1.45, 1.45)
        pitch = math.clamp(pitch - input.Delta.Y * 0.003, -0.65, 0.55)
    elseif input.UserInputType == Enum.UserInputType.Touch and not processed and driving then
        -- Swipe above the driving controls to look around the cabin.
        local camera = workspace.CurrentCamera
        if camera and input.Position.Y < camera.ViewportSize.Y * 0.65 then
            yaw = math.clamp(yaw - input.Delta.X * 0.0025, -1.45, 1.45)
            pitch = math.clamp(pitch - input.Delta.Y * 0.0025, -0.65, 0.55)
        end
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Thumbstick1 then gamepadSteer = input.Position.X
    elseif input.KeyCode == Enum.KeyCode.ButtonR2 then rightTrigger = input.Position.Z
    elseif input.KeyCode == Enum.KeyCode.ButtonL2 then leftTrigger = input.Position.Z end
    gamepadThrottle = rightTrigger - leftTrigger
end)

-- Consume jump so the driver stays seated while Space acts as the handbrake.
ContextActionService:BindAction("TouringBrake", function(_, state)
    keys[Enum.KeyCode.Space] = state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change
    return driving and Enum.ContextActionResult.Sink or Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)

RunService.Heartbeat:Connect(function(dt)
    if not controller or not chassis or not chassis.Parent then return end
    local forward = keys[Enum.KeyCode.W] or keys[Enum.KeyCode.Up] or touch.Throttle
    local backward = keys[Enum.KeyCode.S] or keys[Enum.KeyCode.Down] or touch.Reverse
    local right = keys[Enum.KeyCode.D] or keys[Enum.KeyCode.Right] or touch.Right
    local left = keys[Enum.KeyCode.A] or keys[Enum.KeyCode.Left] or touch.Left
    local throttle = driving and math.clamp((forward and 1 or 0) - (backward and 1 or 0) + gamepadThrottle, -1, 1) or 0
    local targetSteer = driving and math.clamp((right and 1 or 0) - (left and 1 or 0) + gamepadSteer, -1, 1) or 0
    steer += (targetSteer - steer) * (1 - math.exp(-dt * 7))
    controller:step(dt, throttle, steer, keys[Enum.KeyCode.Space] or touch.Brake or not driving)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if driving and humanoid and not humanoid.SeatPart and humanoid.Health > 0 then
        -- On a streaming or character respawn delay, let the server reseat once.
        elapsed += dt
        if elapsed > 1.5 then elapsed = 0; action:FireServer("Drive") end
    else elapsed = 0 end
end)

local uiElapsed = 0
RunService:BindToRenderStep("NorthboundCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
    local camera = workspace.CurrentCamera
    if not camera then return end
    dt = math.min(dt, 1 / 15)
    camera.CameraType = Enum.CameraType.Scriptable
    menuTime += dt
    if chassis and chassis.Parent and driving then
        UserInputService.MouseBehavior = looking and Enum.MouseBehavior.LockCurrentPosition or Enum.MouseBehavior.Default
        if not looking and not UserInputService.TouchEnabled then
            yaw *= math.exp(-dt * 2.2); pitch *= math.exp(-dt * 2.2)
        end
        local velocity = chassis.AssemblyLinearVelocity
        local localAcceleration = chassis.CFrame:VectorToObjectSpace((velocity - lastVelocity) / math.max(dt, 1/120))
        lastVelocity = velocity
        local targetBump = Vector3.new(math.clamp(-localAcceleration.X * 0.0009,-0.045,0.045), math.clamp(-localAcceleration.Y * 0.0007,-0.035,0.035), math.clamp(-localAcceleration.Z * 0.0008,-0.04,0.04))
        cameraBump = cameraBump:Lerp(targetBump, 1-math.exp(-dt*7))
        camera.CFrame = chassis.CFrame * eye.CFrame * CFrame.new(cameraBump) * CFrame.Angles(pitch,yaw,math.clamp(-steer*velocity.Magnitude*.00004,-.008,.008))
        camera.FieldOfView += ((72 + math.min(velocity.Magnitude/100,1)*4) - camera.FieldOfView) * (1-math.exp(-dt*3))
        if player.Character then
            if hiddenCharacter ~= player.Character then hideCharacter(player.Character) end
            for _, part in player.Character:GetChildren() do
                if part:IsA("BasePart") then part.LocalTransparencyModifier = 1 end
            end
        end
        local wet = shared:GetAttribute("Precipitation") or 0
        if steeringJoint then steeringJoint.C0 = steeringBase * CFrame.Angles(0,0,-steer*2.1) end
        for _, gauge in gauges do
            local ratio = gauge.index == 1 and math.clamp(velocity.Magnitude / 160,0,1)
                or gauge.index == 2 and math.clamp((vehicle:GetAttribute("LocalRPM") or 850)/7000,0,1) or .75
            gauge.joint.C0 = gauge.base * CFrame.Angles(0,0,-ratio*3.7)
        end
        wheelTime += dt * (wet > .6 and 5.5 or 3.2)
        for _, wiper in wipers do
            local angle = vehicle:GetAttribute("Wipers") and wet > .04 and (0.5-0.5*math.cos(wheelTime))*1.15 or 0
            wiper.joint.C0 = wiper.base * CFrame.Angles(0,0,angle)
        end
    else
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        local focus = chassis and chassis.Position or Vector3.new(-7,35,0)
        local angle = -0.55 + math.sin(menuTime * 0.025) * 0.08
        local offset = Vector3.new(math.sin(angle)*29,8, -math.cos(angle)*29)
        camera.CFrame = CFrame.lookAt(focus + offset,focus+Vector3.new(0,1.0,0))
        camera.FieldOfView = 52
    end
    uiElapsed += dt
    if uiElapsed >= .1 then
        uiElapsed = 0
        local speed = chassis and chassis.AssemblyLinearVelocity.Magnitude * 1.008 or 0
        local forwardSpeed = chassis and chassis.CFrame.LookVector:Dot(chassis.AssemblyLinearVelocity) or 0
        local distance = chassis and -chassis.Position.Z or 0
        local heading = chassis and math.deg(math.atan2(chassis.CFrame.LookVector.X, -chassis.CFrame.LookVector.Z)) or 0
        ui:update({ready=shared:GetAttribute("WorldReady") == true and controller ~= nil and localRoadReady, chunks=scenery:GetAttribute("GeneratedChunks") or 0,
            speed=speed, gear=forwardSpeed < -1 and "R" or speed < 1 and "N" or tostring(math.clamp(math.floor(speed/28)+1,1,5)),
            distance=vehicle and vehicle:GetAttribute("Odometer") or 0, weather=shared:GetAttribute("Weather") or "Clear",
            temperature=shared:GetAttribute("Temperature") or 16, clock=shared:GetAttribute("ClockTime") or 16.35,
            heading=heading, surface=Route.surface(distance), biome=Route.biome(chassis and chassis.Position.X or 0, -distance),
            headlights=vehicle and vehicle:GetAttribute("Headlights") or false, wipers=vehicle and vehicle:GetAttribute("Wipers") or false})
    end
end)
