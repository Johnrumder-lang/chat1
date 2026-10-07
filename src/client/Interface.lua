-- NORTHBOUND: a quiet, responsive interface built entirely from native Roblox UI.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Interface = {}
Interface.__index = Interface

local INK = Color3.fromRGB(21, 30, 29)
local IVORY = Color3.fromRGB(237, 233, 218)
local MUTED = Color3.fromRGB(171, 187, 173)
local SAGE = Color3.fromRGB(178, 199, 167)
local WHITE = Color3.fromRGB(251, 249, 239)

local function create(className, properties, parent)
	local object = Instance.new(className)
	for property, value in pairs(properties or {}) do
		object[property] = value
	end
	object.Parent = parent
	return object
end

local function label(parent, text, position, size, fontSize, color, font)
	return create("TextLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = text,
		Position = position,
		Size = size,
		Font = font or Enum.Font.Gotham,
		TextSize = fontSize,
		TextColor3 = color or IVORY,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, parent)
end

local function line(parent, position, size, transparency)
	return create("Frame", {
		BackgroundColor3 = IVORY,
		BackgroundTransparency = transparency or 0.8,
		BorderSizePixel = 0,
		Position = position,
		Size = size,
	}, parent)
end

local function setText(object, value)
	if object.Text ~= value then
		object.Text = value
	end
end

local function tween(object, duration, properties)
	local animation = TweenService:Create(object, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), properties)
	animation:Play()
	return animation
end

local function finite(value, fallback)
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return fallback
	end
	return value
end

function Interface.new(onAction)
	local self = setmetatable({}, Interface)
	self.onAction = onAction
	self.connections = {}
	self.holds = {}
	self.state = {}
	self.ready = false
	self.driving = false
	self.destroyed = false
	self.transition = 0
	self.touch = UserInputService.TouchEnabled

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = create("ScreenGui", {
		Name = "NorthboundInterface",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 20,
	}, playerGui)
	self.menu = create("CanvasGroup", {
		Name = "JourneyMenu",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 0,
	}, self.gui)
	local veil = create("Frame", {
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, self.menu)
	create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.38, 0.13),
			NumberSequenceKeypoint.new(0.77, 0.74),
			NumberSequenceKeypoint.new(1, 0.89),
		}),
	}, veil)
	self.menuContent = create("Frame", {
		Name = "Editorial",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.075, 0, 0.5, 0),
		Size = UDim2.fromOffset(580, 680),
	}, self.menu)
	self.menuScale = create("UIScale", { Scale = 1 }, self.menuContent)

	-- A small horizon mark remains legible without image assets.
	local mark = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(34, 28),
		Position = UDim2.fromOffset(0, 8),
	}, self.menuContent)
	line(mark, UDim2.fromOffset(3, 12), UDim2.fromOffset(15, 2), 0.05).Rotation = -48
	line(mark, UDim2.fromOffset(13, 12), UDim2.fromOffset(15, 2), 0.05).Rotation = 48
	line(mark, UDim2.fromOffset(0, 25), UDim2.fromOffset(32, 1), 0.32)
	label(self.menuContent, "NORTHBOUND", UDim2.fromOffset(48, 4), UDim2.fromOffset(440, 34), 24, IVORY, Enum.Font.GothamMedium)
	label(self.menuContent, "A L P I N E   T O U R I N G    /    V O L U M E   0 1", UDim2.fromOffset(1, 65), UDim2.fromOffset(570, 22), 11, MUTED)
	line(self.menuContent, UDim2.fromOffset(0, 109), UDim2.fromOffset(504, 1), 0.74)

	local headline = label(self.menuContent, "Take the long\nway home.", UDim2.fromOffset(-3, 139), UDim2.fromOffset(580, 170), 76, WHITE, Enum.Font.Garamond)
	headline.TextYAlignment = Enum.TextYAlignment.Top
	headline.LineHeight = 1
	local description = label(self.menuContent, "Beyond the last town, the road keeps going.\nFind your own pace in the high country.", UDim2.fromOffset(1, 326), UDim2.fromOffset(540, 65), 16, MUTED)
	description.LineHeight = 1.45
	description.TextYAlignment = Enum.TextYAlignment.Top

	line(self.menuContent, UDim2.fromOffset(0, 424), UDim2.fromOffset(504, 1), 0.85)
	label(self.menuContent, "YOUR COMPANION", UDim2.fromOffset(0, 443), UDim2.fromOffset(260, 20), 10, MUTED)
	label(self.menuContent, "ASTER", UDim2.fromOffset(0, 465), UDim2.fromOffset(160, 30), 23, IVORY, Enum.Font.GothamMedium)
	label(self.menuContent, "4WD  /  TOURING", UDim2.fromOffset(167, 471), UDim2.fromOffset(290, 22), 11, MUTED)

	self.begin = create("TextButton", {
		Name = "BeginJourney",
		Position = UDim2.fromOffset(0, 529),
		Size = UDim2.fromOffset(504, 58),
		BackgroundColor3 = Color3.fromRGB(78, 94, 81),
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Text = "Preparing the route...",
		TextColor3 = Color3.fromRGB(189, 204, 186),
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		AutoButtonColor = false,
		Active = false,
		Selectable = false,
	}, self.menuContent)
	create("UICorner", { CornerRadius = UDim.new(0, 3) }, self.begin)
	self.loadStatus = label(self.menuContent, "PREPARING THE HIGH COUNTRY", UDim2.fromOffset(0, 609), UDim2.fromOffset(504, 20), 10, MUTED)
	local track = create("Frame", {
		Size = UDim2.fromOffset(504, 1),
		Position = UDim2.fromOffset(0, 647),
		BorderSizePixel = 0,
		BackgroundColor3 = IVORY,
		BackgroundTransparency = 0.88,
		ClipsDescendants = true,
	}, self.menuContent)
	self.progress = create("Frame", {
		Size = UDim2.fromScale(0.2, 1),
		Position = UDim2.fromScale(-0.2, 0),
		BorderSizePixel = 0,
		BackgroundColor3 = SAGE,
		BackgroundTransparency = 0.1,
	}, track)
	self.loadingTween = TweenService:Create(self.progress, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1), { Position = UDim2.fromScale(1, 0) })
	self.loadingTween:Play()
	self.menuNote = label(self.menu, "NO DESTINATION REQUIRED.", UDim2.new(1, -286, 1, -51), UDim2.fromOffset(245, 20), 10, IVORY)
	self.menuNote.TextXAlignment = Enum.TextXAlignment.Right
	self.menuNote.TextTransparency = 0.25

	self.hud = create("CanvasGroup", {
		Name = "DrivingInstruments",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = false,
	}, self.gui)
	local bottomShade = create("Frame", {
		Size = UDim2.new(1, 0, 0, 220),
		Position = UDim2.new(0, 0, 1, -220),
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(9, 18, 19),
		BackgroundTransparency = 0.28,
	}, self.hud)
	create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.1) }),
	}, bottomShade)
	local topShade = create("Frame", {
		Size = UDim2.new(1, 0, 0, 110),
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(9, 18, 19),
		BackgroundTransparency = 0.53,
	}, self.hud)
	create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
	}, topShade)

	self.locationBlock = create("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(34, 65), Size = UDim2.fromOffset(350, 55) }, self.hud)
	label(self.locationBlock, "N O R T H B O U N D", UDim2.fromOffset(0, 0), UDim2.fromOffset(280, 15), 10, MUTED, Enum.Font.GothamMedium)
	self.location = label(self.locationBlock, "THE HIGH COUNTRY", UDim2.fromOffset(0, 22), UDim2.fromOffset(350, 20), 12, IVORY)

	self.compassBlock = create("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -34, 0, 65), Size = UDim2.fromOffset(170, 52) }, self.hud)
	self.compass = label(self.compassBlock, "N  /  000°", UDim2.fromOffset(0, 0), UDim2.fromOffset(170, 20), 14, IVORY, Enum.Font.GothamMedium)
	self.compass.TextXAlignment = Enum.TextXAlignment.Right
	self.clock = label(self.compassBlock, "", UDim2.fromOffset(0, 26), UDim2.fromOffset(170, 18), 11, MUTED)
	self.clock.TextXAlignment = Enum.TextXAlignment.Right

	self.speedBlock = create("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 34, 1, -177), Size = UDim2.fromOffset(300, 125) }, self.hud)
	self.surface = label(self.speedBlock, "TOURING", UDim2.fromOffset(1, 0), UDim2.fromOffset(240, 18), 10, MUTED)
	self.speed = label(self.speedBlock, "0", UDim2.fromOffset(-3, 15), UDim2.fromOffset(148, 78), 62, WHITE, Enum.Font.Gotham)
	label(self.speedBlock, "KM/H", UDim2.fromOffset(152, 58), UDim2.fromOffset(80, 21), 11, MUTED)
	self.gear = label(self.speedBlock, "N", UDim2.fromOffset(237, 41), UDim2.fromOffset(38, 39), 20, IVORY, Enum.Font.GothamMedium)
	self.gear.TextXAlignment = Enum.TextXAlignment.Center
	line(self.speedBlock, UDim2.fromOffset(221, 47), UDim2.fromOffset(1, 26), 0.65)
	line(self.speedBlock, UDim2.fromOffset(0, 99), UDim2.fromOffset(268, 1), 0.8)
	self.distance = label(self.speedBlock, "JOURNEY  /  0.0 KM", UDim2.fromOffset(1, 110), UDim2.fromOffset(280, 20), 10, MUTED)

	self.conditionsBlock = create("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -34, 1, -135), Size = UDim2.fromOffset(270, 100) }, self.hud)
	self.weather = label(self.conditionsBlock, "", UDim2.fromOffset(0, 0), UDim2.fromOffset(270, 24), 13, IVORY)
	self.weather.TextXAlignment = Enum.TextXAlignment.Right
	self.temperature = label(self.conditionsBlock, "", UDim2.fromOffset(0, 29), UDim2.fromOffset(270, 18), 11, MUTED)
	self.temperature.TextXAlignment = Enum.TextXAlignment.Right
	self.actionButtons = {}
	for index, item in ipairs({ { "LIGHTS", "Lights", "H" }, { "WIPERS", "Wipers", "V" }, { "RECOVER", "Recover", "R" } }) do
		local button = create("TextButton", {
			Name = item[2],
			Size = UDim2.fromOffset(84, 30),
			Position = UDim2.fromOffset((index - 1) * 92, 63),
			BackgroundColor3 = INK,
			BackgroundTransparency = 0.62,
			BorderSizePixel = 0,
			Text = (self.touch and "" or item[3] .. " ") .. item[1],
			Font = Enum.Font.GothamMedium,
			TextSize = 9,
			TextColor3 = IVORY,
			AutoButtonColor = true,
		}, self.conditionsBlock)
		create("UICorner", { CornerRadius = UDim.new(0, 3) }, button)
		self.actionButtons[item[2]] = button
		table.insert(self.connections, button.Activated:Connect(function()
			if self.driving then self.onAction(item[2]) end
		end))
	end
	self.controls = label(self.hud, "W / S  drive     A / D  steer     SPACE  brake     RMB  look     ESC  menu", UDim2.new(0.5, -340, 1, -29), UDim2.fromOffset(680, 17), 9, MUTED)
	self.controls.TextXAlignment = Enum.TextXAlignment.Center
	self.controls.TextTransparency = 0.12

	self.touchControls = create("Frame", {
		Name = "TouchControls",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = self.touch,
	}, self.hud)
	self:_holdButton("LEFT", "Left", UDim2.new(0, 24, 1, -109), UDim2.fromOffset(72, 74))
	self:_holdButton("RIGHT", "Right", UDim2.new(0, 106, 1, -109), UDim2.fromOffset(72, 74))
	self:_holdButton("BRAKE", "Brake", UDim2.new(0.5, -35, 1, -95), UDim2.fromOffset(70, 60))
	self:_holdButton("REV", "Reverse", UDim2.new(1, -180, 1, -109), UDim2.fromOffset(72, 74))
	self:_holdButton("GO", "Throttle", UDim2.new(1, -98, 1, -133), UDim2.fromOffset(74, 98))

	table.insert(self.connections, self.begin.Activated:Connect(function()
		if self.ready and not self.driving then
			self.onAction("Drive")
		end
	end))
	table.insert(self.connections, self.begin.MouseEnter:Connect(function()
		if self.ready then tween(self.begin, 0.2, { BackgroundColor3 = IVORY }) end
	end))
	table.insert(self.connections, self.begin.MouseLeave:Connect(function()
		if self.ready then tween(self.begin, 0.2, { BackgroundColor3 = SAGE }) end
	end))
	table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
		for _, hold in ipairs(self.holds) do
			if hold.input == input then self:_releaseHold(hold) end
		end
	end))
	table.insert(self.connections, UserInputService.WindowFocusReleased:Connect(function()
		for _, hold in ipairs(self.holds) do self:_releaseHold(hold) end
	end))

	local function connectCamera()
		if self.viewportConnection then self.viewportConnection:Disconnect() end
		local camera = workspace.CurrentCamera
		if camera then
			self.viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function() self:_resize(camera.ViewportSize) end)
			self:_resize(camera.ViewportSize)
		end
	end
	table.insert(self.connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(connectCamera))
	connectCamera()
	return self
end

function Interface:_holdButton(text, action, position, size)
	local button = create("TextButton", {
		Name = action,
		Position = position,
		Size = size,
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.34,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = IVORY,
		TextSize = 12,
		Font = Enum.Font.GothamMedium,
		AutoButtonColor = false,
	}, self.touchControls)
	create("UICorner", { CornerRadius = UDim.new(0, 8) }, button)
	create("UIStroke", { Color = IVORY, Transparency = 0.68, Thickness = 1 }, button)
	local hold = { action = action, button = button, input = nil }
	table.insert(self.holds, hold)
	table.insert(self.connections, button.InputBegan:Connect(function(input)
		if not self.driving or hold.input then return end
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			hold.input = input
			button.BackgroundColor3 = SAGE
			button.TextColor3 = INK
			button.BackgroundTransparency = 0.1
			self.onAction(action .. "On")
		end
	end))
	table.insert(self.connections, button.InputEnded:Connect(function(input)
		if hold.input == input then self:_releaseHold(hold) end
	end))
end

function Interface:_releaseHold(hold)
	if not hold.input then return end
	hold.input = nil
	hold.button.BackgroundColor3 = INK
	hold.button.BackgroundTransparency = 0.34
	hold.button.TextColor3 = IVORY
	self.onAction(hold.action .. "Off")
end

function Interface:_resize(viewport)
	local width, height = viewport.X, viewport.Y
	if width < 1 or height < 1 then return end
	self.menuScale.Scale = math.clamp(math.min(width * 0.86 / 580, height * 0.84 / 680), 0.35, 1.15)
	self.menuContent.Position = UDim2.new(0.075, 0, 0.5, 0)
	self.menuNote.Visible = width >= 1024 and height >= 580
	local margin = width < 650 and 20 or 34
	self.locationBlock.Position = UDim2.fromOffset(margin, 65)
	self.compassBlock.Position = UDim2.new(1, -margin, 0, 65)
	self.controls.Visible = not self.touch and width >= 850
	self.speedBlock.Position = UDim2.new(0, margin, 1, self.touch and -278 or -177)
	self.conditionsBlock.Position = UDim2.new(1, -margin, 1, self.touch and -245 or -135)
	local compact = width < 650
	self.location.TextSize = compact and 10 or 12
	self.speedBlock.Size = UDim2.fromOffset(300, 125)
	local speedScale = self.speedBlock:FindFirstChildOfClass("UIScale") or create("UIScale", {}, self.speedBlock)
	speedScale.Scale = compact and 0.75 or 1
	local weatherScale = self.conditionsBlock:FindFirstChildOfClass("UIScale") or create("UIScale", {}, self.conditionsBlock)
	weatherScale.Scale = compact and 0.75 or 1
	if self.touch and compact and height >= 520 then
		self.conditionsBlock.Position = UDim2.new(1, -margin, 0, 126)
	end
	-- On a short phone screen, keep the instruments just above the pedals.
	if self.touch and height < 520 then
		self.speedBlock.Position = UDim2.new(0, margin, 1, -222)
		self.conditionsBlock.Position = UDim2.new(1, -margin, 1, -225)
		speedScale.Scale = 0.68
		weatherScale.Scale = 0.8
	end
	if self.touch then
		local pedalWidth = math.clamp((width - 64) / 5, 48, 74)
		for _, hold in ipairs(self.holds) do
			local button = hold.button
			if hold.action == "Left" then
				button.Position = UDim2.new(0, 16, 1, -109)
				button.Size = UDim2.fromOffset(pedalWidth, 74)
			elseif hold.action == "Right" then
				button.Position = UDim2.new(0, 24 + pedalWidth, 1, -109)
				button.Size = UDim2.fromOffset(pedalWidth, 74)
			elseif hold.action == "Reverse" then
				button.Position = UDim2.new(1, -24 - pedalWidth * 2, 1, -109)
				button.Size = UDim2.fromOffset(pedalWidth, 74)
			elseif hold.action == "Throttle" then
				button.Position = UDim2.new(1, -16 - pedalWidth, 1, -133)
				button.Size = UDim2.fromOffset(pedalWidth, 98)
			elseif hold.action == "Brake" then
				button.Position = UDim2.new(0.5, -pedalWidth / 2, 1, -95)
				button.Size = UDim2.fromOffset(pedalWidth, 60)
			end
		end
	end
end

function Interface:update(state)
	if self.destroyed then return end
	for key, value in pairs(state or {}) do self.state[key] = value end
	state = self.state
	local ready = state.ready == true
	if ready ~= self.ready then
		self.ready = ready
		self.begin.Active = ready
		self.begin.Selectable = ready
		if ready then
			self.loadingTween:Cancel()
			self.progress.Position = UDim2.fromScale(0, 0)
			tween(self.progress, 0.7, { Size = UDim2.fromScale(1, 1) })
			tween(self.begin, 0.45, { BackgroundColor3 = SAGE, BackgroundTransparency = 0, TextColor3 = INK })
			setText(self.begin, "Begin journey  →")
		else
			self.progress.Size = UDim2.fromScale(0.2, 1)
			self.progress.Position = UDim2.fromScale(-0.2, 0)
			self.loadingTween:Play()
			tween(self.begin, 0.2, { BackgroundColor3 = Color3.fromRGB(78, 94, 81), BackgroundTransparency = 0.12, TextColor3 = MUTED })
			setText(self.begin, "Preparing the route...")
		end
	end
	if self.ready then
		setText(self.loadStatus, "THE ROAD IS READY.  TAKE YOUR TIME.")
	else
		local chunks = math.max(0, math.floor(finite(state.chunks, 0)))
		setText(self.loadStatus, chunks > 0 and string.format("BUILDING THE HIGH COUNTRY  /  %d REGIONS READY", chunks) or "PREPARING THE HIGH COUNTRY")
	end

	local speed = math.max(0, math.abs(finite(state.speed, 0)))
	setText(self.speed, tostring(math.floor(speed + 0.5)))
	setText(self.gear, tostring(state.gear or "N"))
	setText(self.distance, string.format("JOURNEY  /  %.1f KM", math.max(0, finite(state.distance, 0))))
	setText(self.surface, string.upper(tostring(state.surface or "Touring")))
	setText(self.weather, string.upper(tostring(state.weather or "")))
	setText(self.temperature, type(state.temperature) == "number" and string.format("%d°C  /  OUTSIDE", math.floor(finite(state.temperature, 0) + 0.5)) or "")
	if type(state.clock) == "number" then
		local totalMinutes = math.floor((finite(state.clock, 0) % 24) * 60)
		setText(self.clock, string.format("%02d:%02d  /  LOCAL TIME", math.floor(totalMinutes / 60), totalMinutes % 60))
	end
	local heading = finite(state.heading, 0) % 360
	local cardinal = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
	setText(self.compass, string.format("%s  /  %03d°", cardinal[math.floor((heading + 22.5) / 45) % 8 + 1], math.floor(heading + 0.5) % 360))
	if state.biome then
		setText(self.location, string.upper(tostring(state.biome)))
	end
	self.actionButtons.Lights.TextColor3 = state.headlights and SAGE or IVORY
	self.actionButtons.Wipers.TextColor3 = state.wipers and SAGE or IVORY
end

function Interface:setDriving(driving)
	if self.destroyed then return end
	driving = driving == true
	if self.driving == driving then return end
	self.driving = driving
	self.transition = self.transition + 1
	local transition = self.transition
	if self.menuFade then self.menuFade:Cancel() end
	if self.hudFade then self.hudFade:Cancel() end
	self.menu.Visible = true
	self.hud.Visible = true
	self.menuFade = tween(self.menu, 0.7, { GroupTransparency = driving and 1 or 0 })
	self.hudFade = tween(self.hud, 0.8, { GroupTransparency = driving and 0 or 1 })
	if not driving then
		for _, hold in ipairs(self.holds) do self:_releaseHold(hold) end
	end
	task.delay(0.85, function()
		if self.destroyed or self.transition ~= transition then return end
		self.menu.Visible = not driving
		self.hud.Visible = driving
	end)
end

function Interface:destroy()
	if self.destroyed then return end
	self.destroyed = true
	for _, hold in ipairs(self.holds) do self:_releaseHold(hold) end
	if self.loadingTween then self.loadingTween:Cancel() end
	if self.menuFade then self.menuFade:Cancel() end
	if self.hudFade then self.hudFade:Cancel() end
	if self.viewportConnection then self.viewportConnection:Disconnect() end
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	self.gui:Destroy()
end

return Interface
