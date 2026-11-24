--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local ACCENT = Color3.fromRGB(77, 221, 227)
local HOLD_DURATION = 1.2
local CRACK_COUNT = 161
local CHIP_COUNT = 12
local SPRING_SPEED = 23
local SPRING_DAMPING = 0.72
local CHARGE_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

type combatView = {
	character: Model?,
	actionId: number?,
	abilities: { [string]: string },
	abilityCooldowns: { [string]: number },
	nextClickTime: number,
	nextDashTime: number,
	ultCharge: number,
	ultRequired: number,
	ultExpiresAt: number,
	ultDuration: number?,
	styleName: string?,
}

type pressState = {
	button: TextButton,
	scale: UIScale,
	cracks: { Frame },
	chips: { Frame },
	order: { number },
	startedAt: number?,
	input: InputObject?,
	value: number,
	velocity: number,
	progress: number,
}

type callbacks = {
	attack: () -> (),
	attackHeld: (boolean) -> (),
	block: (boolean) -> (),
	dash: () -> (),
	ability: (string) -> (),
	ultimate: () -> (),
	npc: (string) -> (),
}

local player = Players.LocalPlayer
local view: combatView = {
	abilities = {},
	abilityCooldowns = {},
	nextClickTime = 0,
	nextDashTime = 0,
	ultCharge = 0,
	ultRequired = 100,
	ultExpiresAt = 0,
}
local presses: { [string]: pressState } = {}
local connections: { RBXScriptConnection } = {}
local gui: ScreenGui? = nil
local guiWatcher: RBXScriptConnection? = nil
local bindingQueued = false
local actions: callbacks? = nil
local notice = ""
local noticeUntil = 0
local chargeTween: Tween? = nil
local chargeTarget: number? = nil
local interface = {}

local function cancelChargeTween()
	if chargeTween then
		chargeTween:Cancel()
		chargeTween = nil
	end

	chargeTarget = nil
end

local function connect(signal: RBXScriptSignal, callback: (...any) -> ())
	table.insert(connections, signal:Connect(callback))
end

local function hasChildren(parent: Instance, names: { string }): boolean
	for _, name in ipairs(names) do
		if not parent:FindFirstChild(name) then
			return false
		end
	end

	return true
end

local function ready(screen: ScreenGui): boolean
	if not hasChildren(screen, { "Hud", "Status", "Training", "TrainingMenu", "Touch" }) then
		return false
	end

	local hud = screen:FindFirstChild("Hud") :: Instance
	local menu = screen:FindFirstChild("TrainingMenu") :: Instance
	local touch = screen:FindFirstChild("Touch") :: Instance

	if
		not hasChildren(hud, { "Mode", "Ultimate", "Health", "Ability1", "Ability2", "Ability3", "Ability4" })
		or not hasChildren(menu, { "Block", "Attack", "Mixed", "Clear" })
		or not hasChildren(touch, { "Attack", "Block", "Dash" })
		or not (hud:FindFirstChild("Health") :: Instance):FindFirstChild("Fill")
	then
		return false
	end

	for _, name in ipairs({ "Ultimate", "Ability1", "Ability2", "Ability3", "Ability4" }) do
		local button = hud:FindFirstChild(name) :: Instance

		if not hasChildren(button, { "PressScale", "Cracks", "Fragments" }) then
			return false
		end

		local cracks = button:FindFirstChild("Cracks") :: Instance
		local fragments = button:FindFirstChild("Fragments") :: Instance

		if name == "Ultimate" then
			if not button:FindFirstChild("Charge") then
				return false
			end
		elseif not hasChildren(button, { "Input", "Name", "Cooldown", "Remaining" }) then
			return false
		end

		for index = 1, CRACK_COUNT do
			if not cracks:FindFirstChild("Crack" .. index) then
				return false
			end
		end

		for index = 1, CHIP_COUNT do
			if not fragments:FindFirstChild("Chip" .. index) then
				return false
			end
		end
	end

	return true
end

local function available(key: string): boolean
	if not gui or not gui.Enabled or UserInputService:GetFocusedTextBox() then
		return false
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if
		not character
		or not humanoid
		or humanoid.Health <= 0
		or view.character ~= character
		or character:GetAttribute("CombatState") ~= "Idle"
	then
		return false
	end

	local now = workspace:GetServerTimeNow()

	return if key == "Ult"
		then view.ultCharge >= view.ultRequired and now >= view.ultExpiresAt
		else view.abilities[key] ~= nil and now >= (view.abilityCooldowns[key] or 0)
end

function interface.beginPress(key: string, input: InputObject?)
	local press = presses[key]

	if not press or press.startedAt or not available(key) then
		return
	end

	for index = #press.order, 2, -1 do
		local other = math.random(index)
		press.order[index], press.order[other] = press.order[other], press.order[index]
	end

	press.startedAt = os.clock()
	press.input = input
	press.velocity = 0
end

function interface.endPress(key: string, cancelled: boolean?)
	local press = presses[key]

	if not press or not press.startedAt then
		return
	end

	local strength = math.clamp((os.clock() - press.startedAt) / HOLD_DURATION, 0, 1)
	press.startedAt = nil
	press.input = nil
	press.progress = 0
	press.velocity = if cancelled then 0 else 2.2 + strength * 7

	if not cancelled and available(key) and actions then
		if key == "Ult" then
			actions.ultimate()
		else
			actions.ability(key)
		end
	end
end

function interface.cancelPresses()
	for key in pairs(presses) do
		interface.endPress(key, true)
	end
end

function interface.reset()
	interface.cancelPresses()
	cancelChargeTween()
	view = {
		abilities = {},
		abilityCooldowns = {},
		nextClickTime = 0,
		nextDashTime = 0,
		ultCharge = 0,
		ultRequired = 100,
		ultExpiresAt = 0,
	}
	noticeUntil = 0
end

function interface.updateState(state: combatView)
	if state.character ~= player.Character then
		return
	end

	if view.character == state.character and (state.actionId or 0) < (view.actionId or 0) then
		return
	end

	view = state
end

function interface.showNotice(message: string)
	notice = message
	noticeUntil = os.clock() + 3
end

local function bindPress(key: string, item: TextButton)
	local scale = item:FindFirstChild("PressScale") :: UIScale
	local crackContainer = item:FindFirstChild("Cracks") :: Frame
	local fragmentContainer = item:FindFirstChild("Fragments") :: Frame
	local cracks: { Frame } = {}
	local chips: { Frame } = {}
	local segments: { { from: Vector2, to: Vector2 } } = {}
	local order: { number } = {}

	for index = 1, CRACK_COUNT do
		local crack = crackContainer:FindFirstChild("Crack" .. index) :: Frame
		local from = crack:GetAttribute("CrackStart")
		local to = crack:GetAttribute("CrackEnd")

		if typeof(from) ~= "Vector2" or typeof(to) ~= "Vector2" then
			local center = Vector2.new(crack.Position.X.Scale, crack.Position.Y.Scale)
			local angle = math.rad(crack.Rotation)
			local half = Vector2.new(math.cos(angle), math.sin(angle)) * crack.Size.X.Scale / 2
			from = center - half
			to = center + half
			crack:SetAttribute("CrackStart", from)
			crack:SetAttribute("CrackEnd", to)
		end

		table.insert(segments, { from = from :: Vector2, to = to :: Vector2 })
		table.insert(cracks, crack)
		order[index] = index
	end

	local function layoutCracks()
		for index, segment in ipairs(segments) do
			local start = segment.from * item.AbsoluteSize
			local finish = segment.to * item.AbsoluteSize
			local offset = finish - start
			local crack = cracks[index]
			crack.Position = UDim2.fromScale((segment.from.X + segment.to.X) / 2, (segment.from.Y + segment.to.Y) / 2)
			crack.Rotation = math.deg(math.atan2(offset.Y, offset.X))
			crack.Size = UDim2.new(offset.Magnitude / math.max(1, item.AbsoluteSize.X), 0, 0, 1)
		end
	end

	connect(item:GetPropertyChangedSignal("AbsoluteSize"), layoutCracks)
	layoutCracks()

	for index = 1, CHIP_COUNT do
		table.insert(chips, fragmentContainer:FindFirstChild("Chip" .. index) :: Frame)
	end

	presses[key] = {
		button = item,
		scale = scale,
		cracks = cracks,
		chips = chips,
		order = order,
		startedAt = nil,
		input = nil,
		value = 1,
		velocity = 0,
		progress = 0,
	}
	connect(item.InputBegan, function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
		then
			interface.beginPress(key, input)
		end
	end)

	connect(item.SelectionLost, function()
		interface.endPress(key, true)
	end)
end

function interface.destroy()
	interface.cancelPresses()
	cancelChargeTween()

	if guiWatcher then
		guiWatcher:Disconnect()
		guiWatcher = nil
	end

	actions = nil

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	table.clear(connections)
	table.clear(presses)
	local previous = gui
	gui = nil

	if previous then
		previous:Destroy()
	end
end

function interface.init(callbacks: callbacks)
	if gui then
		return
	end

	actions = callbacks
	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)

	if not playerGui or not playerGui:IsA("PlayerGui") then
		return
	end

	if not guiWatcher then
		guiWatcher = playerGui.DescendantAdded:Connect(function(item)
			local screen = playerGui:FindFirstChild("CombatInterface")

			if gui or bindingQueued or not screen or (item ~= screen and not item:IsDescendantOf(screen)) then
				return
			end

			bindingQueued = true
			task.defer(function()
				bindingQueued = false

				if actions then
					interface.init(actions)
				end
			end)
		end)
	end

	local screen = playerGui:FindFirstChild("CombatInterface")

	if not screen or not screen:IsA("ScreenGui") or not ready(screen) then
		return
	end

	gui = screen
	local hud = screen:FindFirstChild("Hud") :: Frame
	local title = hud:FindFirstChild("Mode") :: TextLabel
	local ultimate = hud:FindFirstChild("Ultimate") :: TextButton
	local ultFill = ultimate:FindFirstChild("Charge") :: Frame
	bindPress("Ult", ultimate)
	local slots: { [string]: TextLabel } = {}
	local counters: { [string]: TextLabel } = {}
	local covers: { [string]: Frame } = {}

	for index = 1, 4 do
		local key = tostring(index)
		local slot = hud:FindFirstChild("Ability" .. key) :: TextButton
		bindPress(key, slot)
		slots[key] = slot:FindFirstChild("Name") :: TextLabel
		covers[key] = slot:FindFirstChild("Cooldown") :: Frame
		counters[key] = slot:FindFirstChild("Remaining") :: TextLabel
	end

	local healthFill = (hud:FindFirstChild("Health") :: Frame):FindFirstChild("Fill") :: Frame
	local status = screen:FindFirstChild("Status") :: TextLabel
	local training = screen:FindFirstChild("Training") :: TextButton
	local menu = screen:FindFirstChild("TrainingMenu") :: Frame

	for _, mode in ipairs({ "Block", "Attack", "Mixed", "Clear" }) do
		local item = menu:FindFirstChild(mode) :: TextButton
		connect(item.Activated, function()
			callbacks.npc(mode)
		end)
	end

	connect(training.Activated, function()
		menu.Visible = not menu.Visible
	end)

	local controls = screen:FindFirstChild("Touch") :: Frame
	local attack = controls:FindFirstChild("Attack") :: TextButton
	local block = controls:FindFirstChild("Block") :: TextButton
	local dash = controls:FindFirstChild("Dash") :: TextButton
	local savedHudPosition = hud:GetAttribute("HomePosition")
	local savedControlsPosition = controls:GetAttribute("HomePosition")
	local hudPosition = if typeof(savedHudPosition) == "UDim2" then savedHudPosition else hud.Position
	local controlsPosition = if typeof(savedControlsPosition) == "UDim2"
		then savedControlsPosition
		else controls.Position
	hud:SetAttribute("HomePosition", hudPosition)
	controls:SetAttribute("HomePosition", controlsPosition)
	local jumpButton: GuiObject? = nil

	local function layoutTouch()
		local jump = jumpButton

		if not UserInputService.TouchEnabled or not jump or not jump.Parent then
			hud.Position = hudPosition
			controls.Position = controlsPosition
			return
		end

		local origin = screen.AbsolutePosition
		local size = screen.AbsoluteSize
		local panel = controls.AbsoluteSize
		local right = math.min(origin.X + size.X - 12, jump.AbsolutePosition.X + jump.AbsoluteSize.X)
		local bottom = jump.AbsolutePosition.Y - 12
		controls.Position = UDim2.fromOffset(right - origin.X, bottom - origin.Y)
		hud.Position = if size.X < size.Y
			then UDim2.new(hudPosition.X.Scale, hudPosition.X.Offset, 0, bottom - panel.Y - origin.Y - 12)
			else hudPosition
	end

	local function bindJump(item: Instance)
		if item.Name ~= "JumpButton" or not item:IsA("GuiObject") or item == jumpButton then
			return
		end

		jumpButton = item
		connect(item:GetPropertyChangedSignal("AbsolutePosition"), layoutTouch)
		connect(item:GetPropertyChangedSignal("AbsoluteSize"), layoutTouch)
		layoutTouch()
	end

	connect(playerGui.DescendantAdded, bindJump)
	connect(screen:GetPropertyChangedSignal("AbsoluteSize"), layoutTouch)
	connect(screen:GetPropertyChangedSignal("AbsolutePosition"), layoutTouch)
	connect(controls:GetPropertyChangedSignal("AbsoluteSize"), layoutTouch)
	local existingJump = playerGui:FindFirstChild("JumpButton", true)

	if existingJump then
		bindJump(existingJump)
	end

	local attackInput: InputObject? = nil
	local blockInput: InputObject? = nil
	connect(attack.InputBegan, function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			attackInput = input
			callbacks.attackHeld(true)
		end
	end)

	connect(block.InputBegan, function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			blockInput = input
			callbacks.block(true)
		end
	end)

	connect(dash.Activated, callbacks.dash)
	connect(UserInputService.InputEnded, function(input: InputObject)
		for key, press in pairs(presses) do
			if press.input == input then
				interface.endPress(key, input.UserInputState == Enum.UserInputState.Cancel)
			end
		end

		if input == attackInput then
			attackInput = nil
			callbacks.attackHeld(false)
		end

		if input == blockInput then
			blockInput = nil
			callbacks.block(false)
		end
	end)

	local function cancel()
		interface.cancelPresses()
		attackInput = nil
		blockInput = nil
		callbacks.attackHeld(false)
		callbacks.block(false)
	end

	connect(UserInputService.WindowFocusReleased, cancel)
	connect(GuiService.MenuOpened, cancel)
	connect(screen:GetPropertyChangedSignal("Enabled"), function()
		if not screen.Enabled then
			cancel()
		end
	end)

	connect(player.CharacterRemoving, function()
		cancel()
		interface.reset()
	end)

	local elapsed = 0
	connect(RunService.RenderStepped, function(delta: number)
		local now = os.clock()

		for key, press in pairs(presses) do
			if press.startedAt or math.abs(press.value - 1) > 0.001 or math.abs(press.velocity) > 0.001 then
				if press.startedAt then
					if not available(key) then
						interface.endPress(key, true)
					else
						press.progress = math.clamp((now - press.startedAt) / HOLD_DURATION, 0, 1)
						press.value = 0.97 - press.progress * 0.13
					end
				else
					local dt = math.min(delta, 1 / 30)

					for _ = 1, 2 do
						local step = dt / 2
						press.velocity += ((1 - press.value) * SPRING_SPEED * SPRING_SPEED - 2 * SPRING_DAMPING * SPRING_SPEED * press.velocity) * step
						press.value += press.velocity * step
					end
				end

				press.scale.Scale = math.clamp(press.value, 0.8, 1.3)

				for index, crack in ipairs(press.cracks) do
					local threshold = (press.order[index] - 1) / CRACK_COUNT * 0.9
					crack.Visible = press.startedAt ~= nil and press.progress > threshold
					crack.BackgroundTransparency = 1 - math.clamp((press.progress - threshold) / 0.09, 0, 0.82)
				end

				for index, chip in ipairs(press.chips) do
					local detached = math.clamp((press.progress - index / CHIP_COUNT * 0.8) * 5, 0, 1)
					chip.Visible = press.startedAt ~= nil
					chip.Position = UDim2.fromScale(
						((index - 1) % 4) / 4 + (if index % 2 == 0 then 1 else -1) * detached * 0.15,
						math.floor((index - 1) / 4) / 3 + detached * 0.12
					)
					chip.Rotation = detached * (if index % 2 == 0 then 18 else -18)
					chip.BackgroundTransparency = detached
				end

				press.button.BackgroundTransparency = if press.startedAt then 1 elseif available(key) then 0.12 else 0.45
			end
		end

		elapsed += delta

		if elapsed < 0.05 then
			return
		end

		elapsed = 0
		local serverNow = workspace:GetServerTimeNow()
		local lastInput = UserInputService:GetLastInputType()
		local gamepad = lastInput == Enum.UserInputType.Gamepad1
			or (lastInput == Enum.UserInputType.Focus and UserInputService.GamepadEnabled)
		controls.Visible = UserInputService.TouchEnabled and not gamepad

		for key, press in pairs(presses) do
			if not press.startedAt then
				press.button.BackgroundTransparency = if available(key) then 0.12 else 0.45
			end
		end

		for index = 1, 4 do
			local key = tostring(index)
			local name = view.abilities[key] or "—"

			if slots[key].Text ~= name then
				slots[key].Text = name
			end

			local remaining = math.max(0, (view.abilityCooldowns[key] or 0) - serverNow)
			counters[key].Text = if remaining > 0 then string.format("%.1f", remaining) else ""
			covers[key].Size = UDim2.fromScale(1, if remaining > 0 then 1 else 0)
		end

		local active = view.ultExpiresAt > serverNow
		local styleTitle = if view.styleName == "BasicStyle"
			then "MUAY THAI"
			else string.upper(view.styleName or "COMBAT")
		title.Text = if active
			then styleTitle .. " / AWAKENED"
			else styleTitle .. "  /  " .. (if gamepad
				then "D-PAD UP"
				elseif controls.Visible then "ULTIMATE"
				else "G")
		local charge = if active
			then math.clamp((view.ultExpiresAt - serverNow) / math.max(0.01, view.ultDuration or 20), 0, 1)
			else math.clamp(view.ultCharge / math.max(1, view.ultRequired), 0, 1)
		local target = if active then view.ultExpiresAt else charge

		if chargeTarget ~= target then
			cancelChargeTween()
			chargeTarget = target
			local tween: Tween

			if active then
				ultFill.Size = UDim2.fromScale(charge, 1)
				tween = TweenService:Create(
					ultFill,
					TweenInfo.new(math.max(0.01, view.ultExpiresAt - serverNow), Enum.EasingStyle.Linear),
					{ Size = UDim2.fromScale(0, 1) }
				)
			else
				tween = TweenService:Create(ultFill, CHARGE_TWEEN, { Size = UDim2.fromScale(charge, 1) })
			end

			chargeTween = tween
			tween:Play()
		end

		ultFill.BackgroundColor3 = if active then Color3.fromRGB(255, 187, 91) else ACCENT
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local healthRatio = if humanoid then math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1) else 0
		healthFill.Size = UDim2.fromScale(healthRatio, 1)
		healthFill.BackgroundColor3 = if healthRatio < 0.25
			then Color3.fromRGB(235, 82, 72)
			else Color3.fromRGB(180, 83, 78)
		status.Text = if now < noticeUntil then notice else ""
	end)

	connect(screen.Destroying, function()
		if gui == screen then
			cancel()
			cancelChargeTween()

			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end

			table.clear(connections)
			table.clear(presses)
			gui = nil
		end
	end)
end

return interface
