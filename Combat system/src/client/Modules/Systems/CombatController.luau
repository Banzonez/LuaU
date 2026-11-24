--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local CombatInterface = require(script.Parent.CombatInterface)

local player = Players.LocalPlayer
local events = ReplicatedStorage:WaitForChild("Events", 15)
assert(events, "Combat events were not replicated.")
local event = events:WaitForChild("CombatEvent", 15)
assert(event and event:IsA("RemoteEvent"), "CombatEvent must be a RemoteEvent.")
local combatEvent: RemoteEvent = event

local abilityKeys = {
	[Enum.KeyCode.One] = "1",
	[Enum.KeyCode.Two] = "2",
	[Enum.KeyCode.Three] = "3",
	[Enum.KeyCode.Four] = "4",
	[Enum.KeyCode.ButtonL1] = "1",
	[Enum.KeyCode.ButtonR1] = "2",
	[Enum.KeyCode.ButtonX] = "3",
	[Enum.KeyCode.ButtonY] = "4",
}

local characterConnections: { RBXScriptConnection } = {}
local characterRevision = 0
local attackHeld = false
local keyboardBlock = false
local buttonBlock = false
local nextRequest = 0
local lastJumpRequest = -math.huge
local heldSkills: { [Enum.KeyCode]: string } = {}
local initialized = false
local combat = {}

local function block(blocking: boolean)
	combatEvent:FireServer("Block", blocking)
end

local function attack()
	if not player.Character or UserInputService:GetFocusedTextBox() then
		return
	end

	local uppercut = UserInputService:IsKeyDown(Enum.KeyCode.Space) or os.clock() - lastJumpRequest < 0.15
	combatEvent:FireServer(
		"Clicks",
		if UserInputService.TouchEnabled then Enum.UserInputType.Touch else Enum.UserInputType.MouseButton1,
		uppercut
	)
end

local function dash()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not root or not root:IsA("BasePart") then
		return
	end

	local x = (if UserInputService:IsKeyDown(Enum.KeyCode.D) then 1 else 0)
		- (if UserInputService:IsKeyDown(Enum.KeyCode.A) then 1 else 0)
	local z = (if UserInputService:IsKeyDown(Enum.KeyCode.S) then 1 else 0)
		- (if UserInputService:IsKeyDown(Enum.KeyCode.W) then 1 else 0)
	local camera = workspace.CurrentCamera
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local direction = if camera and (x ~= 0 or z ~= 0)
		then camera.CFrame:VectorToWorldSpace(Vector3.new(x, 0, z))
		else (if humanoid and humanoid.MoveDirection.Magnitude > 0.1
			then humanoid.MoveDirection
			else root.CFrame.LookVector)
	local horizontal = Vector3.new(direction.X, 0, direction.Z)

	if horizontal.Magnitude > 0.01 then
		local relative = if camera then camera.CFrame:VectorToObjectSpace(horizontal.Unit) else Vector3.new(0, 0, -1)
		local name = if math.abs(relative.Z) >= math.abs(relative.X)
			then (if relative.Z < 0 then "Front" else "Back")
			else (if relative.X < 0 then "Left" else "Right")
		combatEvent:FireServer("Dash", horizontal.Unit, name)
	end
end

local function clearCharacter()
	characterRevision += 1
	CombatInterface.reset()
	table.clear(heldSkills)
	lastJumpRequest = -math.huge
	attackHeld = false
	keyboardBlock = false
	buttonBlock = false

	for _, connection in ipairs(characterConnections) do
		connection:Disconnect()
	end

	table.clear(characterConnections)
end

local function setupCharacter(character: Model)
	if player.Character ~= character then
		return
	end

	clearCharacter()
	local revision = characterRevision
	local instance = character:WaitForChild("Humanoid", 10)

	if
		not instance
		or not instance:IsA("Humanoid")
		or player.Character ~= character
		or revision ~= characterRevision
	then
		return
	end

	local humanoid = instance
	local jumpEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)

	local function updateJump()
		local locked = character:GetAttribute("CombatJumpLocked") == true
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not locked and jumpEnabled)

		if locked then
			humanoid.Jump = false
		end
	end

	table.insert(characterConnections, character:GetAttributeChangedSignal("CombatJumpLocked"):Connect(updateJump))
	table.insert(
		characterConnections,
		character:GetAttributeChangedSignal("CombatState"):Connect(function()
			if character:GetAttribute("CombatState") == "Idle" and (keyboardBlock or buttonBlock) then
				block(true)
			end
		end)
	)
	updateJump()
	table.insert(
		characterConnections,
		character:GetAttributeChangedSignal("CombatStyle"):Connect(function()
			combatEvent:FireServer("Ready")
		end)
	)
	combatEvent:FireServer("Ready")
end

function combat.init()
	if initialized then
		return
	end

	initialized = true
	combatEvent.OnClientEvent:Connect(function(action: string, value)
		if action == "State" and type(value) == "table" then
			CombatInterface.updateState(value)
		elseif action == "Notice" and type(value) == "string" then
			CombatInterface.showNotice(value)
		end
	end)

	CombatInterface.init({
		attack = attack,
		attackHeld = function(held)
			attackHeld = held

			if held then
				nextRequest = os.clock() + 0.1
				attack()
			end
		end,
		block = function(held)
			buttonBlock = held
			block(keyboardBlock or buttonBlock)
		end,
		dash = dash,
		ability = function(key)
			combatEvent:FireServer("Ability", key)
		end,
		ultimate = function()
			combatEvent:FireServer("Ult")
		end,
		npc = function(mode)
			combatEvent:FireServer("Npc", mode)
		end,
	})
	player.CharacterAdded:Connect(setupCharacter)
	player.CharacterRemoving:Connect(clearCharacter)

	if player.Character then
		task.spawn(setupCharacter, player.Character)
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			attackHeld = true
			nextRequest = os.clock() + 0.1
			attack()
		elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonL2 then
			keyboardBlock = true
			block(true)
		elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonB then
			dash()
		elseif abilityKeys[input.KeyCode] then
			heldSkills[input.KeyCode] = abilityKeys[input.KeyCode]
			CombatInterface.beginPress(abilityKeys[input.KeyCode])
		elseif input.KeyCode == Enum.KeyCode.G or input.KeyCode == Enum.KeyCode.DPadUp then
			heldSkills[input.KeyCode] = "Ult"
			CombatInterface.beginPress("Ult")
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		local key = heldSkills[input.KeyCode]

		if key then
			heldSkills[input.KeyCode] = nil
			CombatInterface.endPress(key, input.UserInputState == Enum.UserInputState.Cancel)
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			attackHeld = false
		elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonL2 then
			keyboardBlock = false
			block(buttonBlock)
		end
	end)

	UserInputService.JumpRequest:Connect(function()
		lastJumpRequest = os.clock()
	end)

	local function cancelInput()
		table.clear(heldSkills)
		CombatInterface.cancelPresses()
		attackHeld = false
		keyboardBlock = false
		buttonBlock = false
		lastJumpRequest = -math.huge
		block(false)
	end

	UserInputService.WindowFocusReleased:Connect(cancelInput)
	UserInputService.TextBoxFocused:Connect(cancelInput)
	UserInputService.GamepadDisconnected:Connect(cancelInput)
	GuiService.MenuOpened:Connect(cancelInput)
	RunService.Heartbeat:Connect(function()
		if attackHeld and os.clock() >= nextRequest then
			nextRequest = os.clock() + 0.1
			attack()
		end
	end)
end

return combat
