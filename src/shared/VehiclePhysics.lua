-- Four independently sprung tyres; all impulses are applied to the physical chassis.
-- The server grants network ownership only to the seated driver. Call from Heartbeat.
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehiclePhysics = {}
VehiclePhysics.__index = VehiclePhysics

local CONFIG = {
	WheelRadius = 1.4,
	RestLength = 1.8,
	MaxLength = 2.5,
	StaticSag = 0.35,
	DampingRatio = 0.82,
	ForwardLimit = 144, -- 90 mph with one stud = 0.28 m
	ReverseLimit = 30,
	EngineAcceleration = 29,
	BrakeDeceleration = 58,
	TyreFriction = 1.55,
	LateralResponse = 9,
	Drag = 0.00022,
	RollingResistance = 0.65,
	SteerRadians = math.rad(31),
	AntiRoll = 0.16,
}
VehiclePhysics.Config = table.freeze(CONFIG)

local WHEELS = {
	{ name = "WheelFL", x = -3.45, z = -4.6, front = true },
	{ name = "WheelFR", x = 3.45, z = -4.6, front = true },
	{ name = "WheelRL", x = -3.45, z = 4.6, front = false },
	{ name = "WheelRR", x = 3.45, z = 4.6, front = false },
}

local function approach(value, target, rate, dt)
	return value + (target - value) * (1 - math.exp(-rate * dt))
end

local function clampMagnitude(vector, maximum)
	local length = vector.Magnitude
	return length > maximum and vector * (maximum / length) or vector
end

function VehiclePhysics.new(model)
	local root = model:FindFirstChild("Chassis", true)
	assert(root and root:IsA("BasePart"), "VehiclePhysics requires Chassis")
	local self = setmetatable({
		model = model,
		root = root,
		steering = 0,
		throttle = 0,
		spin = 0,
		wheels = {},
		dead = false,
	}, VehiclePhysics)
	self.raycast = RaycastParams.new()
	self.raycast.FilterType = Enum.RaycastFilterType.Exclude
	self.raycast.IgnoreWater = false
	for _, spec in ipairs(WHEELS) do
		local wheelPart
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant.Name == spec.name and descendant:IsA("BasePart") then
				wheelPart = descendant
				break
			end
		end
		local motor
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("Motor6D") and descendant.Part1 == wheelPart then
				motor = descendant
				break
			end
		end
		table.insert(self.wheels, {
			spec = spec,
			motor = motor,
			length = CONFIG.RestLength - CONFIG.StaticSag,
			visualLength = CONFIG.RestLength - CONFIG.StaticSag,
			origin = Vector3.new(spec.x, 0.85, spec.z),
			load = 0,
			contact = nil,
		})
	end
	return self
end

function VehiclePhysics:step(dt, throttle, steer, handbrake)
	if self.dead or not self.root.Parent or self.root.Anchored then return end
	-- Never integrate a stalled frame as an enormous impulse.
	dt = math.clamp(dt, 0, 1 / 30)
	if dt <= 0 then return end
	throttle = math.clamp(tonumber(throttle) or 0, -1, 1)
	steer = math.clamp(tonumber(steer) or 0, -1, 1)
	local root = self.root
	local mass = root.AssemblyMass
	if mass <= 0 or mass == math.huge then return end
	local cf = root.CFrame
	local velocity = root.AssemblyLinearVelocity
	local forwardSpeed = velocity:Dot(cf.LookVector)
	local speed = velocity.Magnitude
	self.throttle = approach(self.throttle, throttle, 6, dt)
	-- Gradually reduce steering lock at speed; retain fine motorway control.
	local steeringLock = CONFIG.SteerRadians / (1 + math.abs(forwardSpeed) / 60)
	self.steering = approach(self.steering, steer * steeringLock, 8, dt)
	self.spin = (self.spin - forwardSpeed / CONFIG.WheelRadius * dt) % (math.pi * 2)
	local excluded = { self.model }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(excluded, player.Character) end
	end
	local scenery = Workspace:FindFirstChild("AtmosphereFX")
	if scenery then table.insert(excluded, scenery) end
	self.raycast.FilterDescendantsInstances = excluded
	local gravity = Workspace.Gravity
	local sprungMass = mass / 4
	local spring = sprungMass * gravity / CONFIG.StaticSag
	local damper = 2 * math.sqrt(spring * sprungMass) * CONFIG.DampingRatio
	local grounded = 0
	local roadTrip = ReplicatedStorage:FindFirstChild("RoadTrip")
	local rain = math.clamp(tonumber(roadTrip and roadTrip:GetAttribute("Precipitation")) or 0, 0, 1)
	local grip = CONFIG.TyreFriction * (1 - rain * 0.28)

	-- Gather contacts first so axle anti-roll can compare the two springs.
	for _, wheel in ipairs(self.wheels) do
		local origin = cf:PointToWorldSpace(wheel.origin)
		local hit = Workspace:Raycast(origin, -cf.UpVector * (CONFIG.MaxLength + CONFIG.WheelRadius), self.raycast)
		wheel.contact = nil
		wheel.load = 0
		wheel.length = CONFIG.MaxLength
		if hit and hit.Material ~= Enum.Material.Water and hit.Normal:Dot(cf.UpVector) > 0.22 then
			wheel.length = math.clamp(hit.Distance - CONFIG.WheelRadius, 0.12, CONFIG.MaxLength)
			local compression = CONFIG.RestLength - wheel.length
			local pointVelocity = root:GetVelocityAtPosition(origin)
			local force = compression * spring - pointVelocity:Dot(hit.Normal) * damper
			wheel.load = math.clamp(force, 0, mass * gravity * 1.5)
			wheel.contact = hit
			grounded += 1
		end
	end

	for index, wheel in ipairs(self.wheels) do
		local hit = wheel.contact
		if hit then
			local pair = self.wheels[index % 2 == 1 and index + 1 or index - 1]
			local antiRoll = pair.contact and (pair.length - wheel.length) * spring * CONFIG.AntiRoll or 0
			local load = math.clamp(wheel.load + antiRoll, 0, mass * gravity * 1.5)
			-- An impulse above each wheel preserves pitch/roll response and avoids
			-- applying suspension force through the terrain below the centre of mass.
			local origin = cf:PointToWorldSpace(wheel.origin)
			root:ApplyImpulseAtPosition(hit.Normal * load * dt, origin)
			local angle = wheel.spec.front and self.steering or 0
			local heading = cf:VectorToWorldSpace(Vector3.new(math.sin(angle), 0, -math.cos(angle)))
			local projected = heading - hit.Normal * heading:Dot(hit.Normal)
			if projected.Magnitude > 0.1 then
				local forward = projected.Unit
				local right = forward:Cross(hit.Normal).Unit
				local atTyre = root:GetVelocityAtPosition(hit.Position)
				local longitudinal = atTyre:Dot(forward)
				local lateral = atTyre:Dot(right)
				local reversingBrake = (throttle < -0.05 and forwardSpeed > 2.5)
					or (throttle > 0.05 and forwardSpeed < -2.5)
				local brake = reversingBrake or handbrake
				local engine = 0
				if not brake then
					local limit = self.throttle >= 0 and CONFIG.ForwardLimit or CONFIG.ReverseLimit
					local fade = math.clamp(1 - (math.abs(forwardSpeed) / limit) ^ 6, 0, 1)
					engine = self.throttle * CONFIG.EngineAcceleration * sprungMass * fade
				end
				local rolling = math.abs(longitudinal) > 0.15
					and -math.sign(longitudinal) * sprungMass * CONFIG.RollingResistance or 0
				local longitudinalForce = engine + rolling
				if brake then
					local deceleration = handbrake and not wheel.spec.front and 85 or CONFIG.BrakeDeceleration
					longitudinalForce = -math.clamp(longitudinal * sprungMass / dt, -sprungMass * deceleration, sprungMass * deceleration)
				end
				local lateralForce = -lateral * sprungMass * CONFIG.LateralResponse
				if handbrake and not wheel.spec.front then lateralForce *= 0.48 end
				-- Dirt and wet tarmac each have a useful, tangible reduction in grip.
				local terrainGrip = (hit.Material == Enum.Material.Ground or hit.Material == Enum.Material.Mud
					or hit.Material == Enum.Material.Sand) and 0.70 or 1
				local tyreForce = clampMagnitude(forward * longitudinalForce + right * lateralForce, load * grip * terrainGrip)
				-- Near-hub application reduces artificial rollover from very tall tyre contacts.
				local tractionPoint = cf:PointToWorldSpace(Vector3.new(wheel.spec.x, -0.4, wheel.spec.z))
				root:ApplyImpulseAtPosition(tyreForce * dt, tractionPoint)
			end
		end
		wheel.visualLength = approach(wheel.visualLength, wheel.length, 18, dt)
		if wheel.motor then
			local angle = wheel.spec.front and -self.steering or 0
			wheel.motor.C0 = CFrame.new(wheel.spec.x, 0.85 - wheel.visualLength, wheel.spec.z)
				* CFrame.Angles(0, angle, 0) * CFrame.Angles(self.spin, 0, 0)
		end
	end

	-- Drag always opposes motion and does not clamp or teleport the assembly.
	if speed > 0.05 then root:ApplyImpulse(-velocity * speed * mass * CONFIG.Drag * dt) end
	-- Mild angular damping dissipates chatter, while leaving suspension and collisions free.
	if grounded > 0 then
		local angular = root.AssemblyAngularVelocity
		local localAngular = cf:VectorToObjectSpace(angular)
		local damping = Vector3.new(localAngular.X * 1.3, localAngular.Y * 0.15, localAngular.Z * 1.7)
		root:ApplyAngularImpulse(-cf:VectorToWorldSpace(damping) * mass * 4 * dt)
	end
	self.model:SetAttribute("LocalSpeed", math.abs(forwardSpeed))
	local gear = forwardSpeed < -1 and -1 or math.clamp(math.floor(math.abs(forwardSpeed) / 27) + 1, 1, 5)
	self.model:SetAttribute("LocalGear", gear)
	self.model:SetAttribute("LocalRPM", 850 + (math.abs(forwardSpeed) % 27) / 27 * 3500 + math.abs(self.throttle) * 500)
	self.model:SetAttribute("GroundedWheels", grounded)
end

function VehiclePhysics:destroy()
	self.dead = true
	self.wheels = {}
end

return VehiclePhysics
