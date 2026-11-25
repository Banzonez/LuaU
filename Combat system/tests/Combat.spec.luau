--!strict

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local systems = ServerScriptService.Server.Modules.Systems
local CombatService = require(systems.CombatService)
local CombatSetup = require(systems.CombatSetup)
local StateHandler = require(systems.CombatStateHandler)

local tests = {}

function tests.run()
	assert(RunService:IsStudio() and RunService:IsServer(), "Run these tests in a Studio server play session.")
	local template = ServerStorage:FindFirstChild("CombatNpc")
	assert(template and template:IsA("Model"), "The test rig is missing.")
	StateHandler.init()
	CombatSetup.init()
	require(systems.Parent.Utils.CombatUtil).init()
	local folder = Instance.new("Folder")
	folder.Name = "CombatTestFixtures"
	folder.Parent = workspace
	local passed: { string } = {}
	local failed: { string } = {}

	local function actor(name: string, position: Vector3)
		local model = template:Clone()
		model.Name = name
		for _, item in ipairs(model:GetDescendants()) do
			if item:IsA("LuaSourceContainer") then
				item:Destroy()
			end
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		assert(root and root:IsA("BasePart") and humanoid)
		model.PrimaryPart = root
		model:PivotTo(CFrame.new(position))
		root.Anchored = true
		humanoid.MaxHealth = 100
		humanoid.Health = 100
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
		model.Parent = folder
		local object = CombatSetup.createCharacterObj(model, nil, {
			ClickDamage = 7,
			Attacks = {
				Click1 = { animation = "__Test", hitDelay = 0.04, activeDuration = 0.2, recovery = 0.35 },
				Uppercut = { animation = "__Test", damage = 9, hitDelay = 0.04, knockback = Vector3.zero },
				Downcut = { animation = "__Test", damage = 11, hitDelay = 0.04, knockback = Vector3.zero },
			},
		})
		for _, ability in pairs(object.Style.Abilities) do
			ability.settings.attack.animation = "__Test"
		end
		return model, humanoid, root, object
	end

	local origin = Vector3.new(1000, 80, 1000)
	local function fixture()
		local a, ah, ar, object = actor("Attacker", origin)
		local b, bh, br = actor("Target", origin + Vector3.new(0, 0, -3.5))
		br.CFrame = CFrame.lookAt(br.Position, ar.Position)
		return a, ah, ar, object, b, bh, br
	end

	local function check(name: string, run: () -> ())
		local success, message = pcall(function()
			run()
			return true
		end)
		if success then
			table.insert(passed, name)
		else
			table.insert(failed, name .. ": " .. tostring(message))
		end
		for _, model in ipairs(folder:GetChildren()) do
			model:Destroy()
		end
		task.wait()
	end

	check("partial settings and independent defaults", function()
		local a, _, _, object = actor("A", origin)
		local _, _, _, other = actor("B", origin + Vector3.new(20, 0, 0))
		assert(object.Settings.ClickDamage == 7)
		assert(object.Settings.Attacks.Click1.damage == 7)
		assert(object.Settings.Attacks.Click1.hitboxSize == Vector3.new(4, 5, 5))
		object.Settings.Attacks.Click1.maxTargets = 3
		assert(other.Settings.Attacks.Click1.maxTargets == 1)
		assert(a:GetAttribute("CombatStyle") == "BasicStyle")
	end)
	check("single hit and M1 cooldown", function()
		local a, _, _, _, _, target = fixture()
		assert(CombatService.tryAttack(a))
		assert(not CombatService.tryAttack(a))
		task.wait(0.28)
		assert(target.Health == 93, tostring(target.Health))
		task.wait(0.1)
		assert(target.Health == 93)
	end)
	check("hitbox catches a target crossed between frames", function()
		local a, _, root, _, b, target = fixture()
		b:PivotTo(CFrame.new(origin + Vector3.new(0, 0, -9)))
		assert(CombatService.tryAttack(a))
		task.wait(0.07)
		assert(target.Health == 100)
		a:PivotTo(root.CFrame + Vector3.new(0, 0, -16))
		task.wait(0.1)
		assert(target.Health == 93, tostring(target.Health))
	end)
	check("hitbox follows rotation", function()
		local a, _, root, _, b, target = fixture()
		b:PivotTo(CFrame.new(origin + Vector3.new(4, 0, 0)))
		assert(CombatService.tryAttack(a))
		task.wait(0.07)
		assert(target.Health == 100)
		a:PivotTo(CFrame.lookAt(root.Position, root.Position + Vector3.xAxis))
		task.wait(0.1)
		assert(target.Health == 93, tostring(target.Health))
	end)
	check("per-attack target cap", function()
		local a, _, _, _, _, first = fixture()
		local _, second = actor("Second", origin + Vector3.new(1, 0, -4))
		assert(CombatService.tryAttack(a))
		task.wait(0.15)
		assert(first.Health == 93 and second.Health == 100)
	end)
	check("frontal block", function()
		local a, _, _, _, b, target = fixture()
		StateHandler.setCharacterState(b, "Blocking", nil, 6)
		assert(CombatService.tryAttack(a))
		task.wait(0.15)
		assert(target.Health == 100)
	end)
	check("back attack bypasses block", function()
		local a, _, _, _, b, target, root = fixture()
		root.CFrame = CFrame.new(root.Position)
		StateHandler.setCharacterState(b, "Blocking", nil, 6)
		assert(CombatService.tryAttack(a))
		task.wait(0.15)
		assert(target.Health == 93)
	end)
	check("guard break", function()
		local a, _, _, object, b, target = fixture()
		StateHandler.setCharacterState(b, "Blocking", nil, 6)
		object.Settings.Attacks.Click1.guardBreak = true
		assert(CombatService.tryAttack(a))
		task.wait(0.15)
		assert(target.Health == 93 and StateHandler.getCharacterState(b).State == "Stunned")
	end)
	check("wall occlusion", function()
		local a, _, _, _, _, target = fixture()
		local wall = Instance.new("Part")
		wall.Size = Vector3.new(10, 10, 0.5)
		wall.CFrame = CFrame.new(origin + Vector3.new(0, 0, -1.5))
		wall.Anchored = true
		wall.Parent = folder
		assert(CombatService.tryAttack(a))
		task.wait(0.15)
		assert(target.Health == 100)
	end)
	check("cancellation before hit and jump lock", function()
		local a, humanoid, _, _, _, target = fixture()
		assert(CombatService.tryAttack(a))
		assert(humanoid.JumpPower == 0 and not humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping))
		StateHandler:StunHumanoid(humanoid, 0.3)
		task.wait(0.15)
		assert(target.Health == 100 and not CombatService.tryAttack(a))
		task.wait(0.22)
		assert(StateHandler.getCharacterState(a).State == "Idle" and humanoid.JumpPower == 50)
	end)
	check("stun cannot be shortened by a later hit", function()
		local a, humanoid = actor("Stunned", origin)
		StateHandler:StunHumanoid(humanoid, 0.3)
		task.wait(0.05)
		StateHandler:StunHumanoid(humanoid, 0.04)
		task.wait(0.1)
		assert(StateHandler.getCharacterState(a).State == "Stunned")
		task.wait(0.2)
		assert(StateHandler.getCharacterState(a).State == "Idle" and humanoid.WalkSpeed == 16)
	end)
	check("character removal cancels a pending hit", function()
		local a, _, _, _, _, target = fixture()
		assert(CombatService.tryAttack(a))
		a:Destroy()
		task.wait(0.15)
		assert(target.Health == 100)
	end)
	check("uppercut only on second hit and NPC charge", function()
		local a, h, root, object, _, target = fixture()
		local floor = Instance.new("Part")
		floor.Anchored = true
		floor.Size = Vector3.new(8, 1, 8)
		floor.Position = root.Position - Vector3.new(0, h.HipHeight + root.Size.Y / 2 + 0.5, 0)
		floor.Parent = folder
		root.Anchored = false
		task.wait(0.15)
		assert(h.FloorMaterial ~= Enum.Material.Air)
		assert(CombatService.tryAttack(a, true))
		task.wait(0.6)
		assert(object.State.ClickCombo == 1 and object.State.ultCharge == 3.5 and object.Settings.ultRequired == 200)
		assert(CombatService.tryAttack(a, true))
		assert(object.State.ClickCombo == 0 and object.State.LastUppercut > 0)
		task.wait(0.15)
		assert(target.Health == 84, tostring(target.Health))
	end)
	check("falling downcut", function()
		local a, _, root, _, b, target = fixture()
		assert(CombatService.tryAttack(a))
		task.wait(0.6)
		a:PivotTo(CFrame.new(origin + Vector3.new(0, 5, 0)))
		b:PivotTo(CFrame.new(origin + Vector3.new(0, 2, -3)))
		root.Anchored = false
		root.AssemblyLinearVelocity = Vector3.new(0, -10, 0)
		assert(CombatService.tryAttack(a))
		task.wait(0.15)
		assert(target.Health == 82, tostring(target.Health))
	end)
	check("dash rejects malformed vectors and state overlap", function()
		local a, humanoid = actor("Dash", origin)
		assert(not CombatService.tryDash(a, Vector3.new(math.huge, 0, 0)))
		assert(not CombatService.tryDash(a, Vector3.new(0 / 0, 0, 0)))
		assert(not CombatService.tryDash(a, Vector3.zero))
		StateHandler:StunHumanoid(humanoid, 0.2)
		assert(not CombatService.tryDash(a, Vector3.xAxis))
	end)
	check("dash movement and constraint cleanup", function()
		local a, _, root = actor("Dash", origin)
		root.Anchored = false
		assert(CombatService.tryDash(a, Vector3.xAxis))
		assert(not CombatService.tryDash(a, Vector3.xAxis))
		task.wait(0.12)
		assert(root.Position.X > origin.X + 1)
		task.wait(0.3)
		assert(not root:FindFirstChildWhichIsA("LinearVelocity"))
	end)
	for index = 1, 4 do
		check("ability " .. index .. " executes and reserves cooldown", function()
			local a, _, _, object, _, target = fixture()
			local key = tostring(index)
			if index == 4 then
				local ground = Instance.new("Part")
				ground.Size = Vector3.new(30, 1, 30)
				ground.Position = origin - Vector3.new(0, 2, 0)
				ground.Anchored = true
				ground.Parent = folder
			end
			assert(CombatService.tryAbility(a, key))
			assert(object.State.AbilitiesCooldowns[key] > workspace:GetServerTimeNow())
			assert(not CombatService.tryAbility(a, key))
			task.wait(if index == 4 then 0.65 else 0.35)
			assert(target.Health < 100, tostring(target.Health))
		end)
	end
	check("configured multi-target attack", function()
		local a, _, _, object, _, first = fixture()
		local _, second = actor("Second", origin + Vector3.new(1, 0, -4))
		object.Settings.Attacks.Click1.maxTargets = 2
		assert(CombatService.tryAttack(a))
		task.wait(0.15)
		assert(first.Health == 93 and second.Health == 93, tostring(first.Health) .. ", " .. tostring(second.Health))
	end)
	check("simultaneous attackers stay independent", function()
		local a, _, _, _, _, first = fixture()
		local c = actor("OtherAttacker", origin + Vector3.new(20, 0, 0))
		local _, second = actor("OtherTarget", origin + Vector3.new(20, 0, -3.5))
		assert(CombatService.tryAttack(a) and CombatService.tryAttack(c))
		task.wait(0.15)
		assert(first.Health == 93 and second.Health == 93)
	end)
	check("force field protects health and guard", function()
		local a, _, _, object, b, target = fixture()
		local shield = Instance.new("ForceField")
		shield.Parent = b
		StateHandler.setCharacterState(b, "Blocking", nil, 6)
		object.Settings.Attacks.Click1.guardBreak = true
		assert(CombatService.tryAttack(a))
		task.wait(0.15)
		assert(target.Health == 100 and StateHandler.getCharacterState(b).State == "Blocking")
	end)
	check("stale state callbacks preserve the replacement attack", function()
		local a, _, _, object, _, target = fixture()
		assert(CombatService.tryAttack(a))
		StateHandler.setCharacterState(a, "Idle")
		object.State.NextClickTime = 0
		assert(CombatService.tryAttack(a))
		task.wait(0.25)
		assert(
			target.Health == 93,
			tostring(target.Health) .. " state " .. object.State.State .. " action " .. object.State.actionId
		)
	end)
	check("dash stops before a wall", function()
		local a, _, root = actor("Dash", origin)
		local wall = Instance.new("Part")
		wall.Size = Vector3.new(1, 20, 20)
		wall.CFrame = CFrame.new(origin + Vector3.new(5, 0, 0))
		wall.Anchored = true
		wall.Parent = folder
		root.Anchored = false
		assert(CombatService.tryDash(a, Vector3.xAxis, "Right"))
		task.wait(0.3)
		assert(root.Position.X < origin.X + 5)
	end)
	check("late humanoid inherits movement restrictions and cleans up on death", function()
		local model = template:Clone()
		local oldHumanoid = model:FindFirstChildOfClass("Humanoid")
		if oldHumanoid then
			oldHumanoid:Destroy()
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		assert(root and root:IsA("BasePart"))
		root.Anchored = true
		model.Parent = folder
		CombatSetup.createCharacterObj(model)
		StateHandler.setCharacterState(model, "Blocking", nil, 6)
		local humanoid = Instance.new("Humanoid")
		humanoid.RequiresNeck = false
		humanoid.Parent = model
		task.wait()
		assert(humanoid.WalkSpeed == 6 and model:GetAttribute("CombatJumpLocked"))
		StateHandler.setCharacterState(model, "Idle")
		assert(humanoid.WalkSpeed == 16 and not model:GetAttribute("CombatJumpLocked"))
		humanoid.Health = 0
		task.wait(0.05)
		assert(CombatSetup.getCharacterObj(model) == nil)
	end)
	check("ultimate gate, damage bonus and expiration", function()
		local a, _, _, object, _, target = fixture()
		assert(not CombatService.tryUlt(a))
		object.State.ultCharge = object.Settings.ultRequired
		assert(CombatService.tryUlt(a))
		assert(object.State.ultCharge == 0 and not CombatService.tryUlt(a))
		task.wait(0.65)
		assert(CombatService.tryAttack(a))
		task.wait(0.15)
		assert(math.abs(target.Health - 90.2) < 0.05, tostring(target.Health))
		object.State.ultExpiresAt = workspace:GetServerTimeNow() - 1
		task.wait()
		assert(object.State.ultExpiresAt == 0)
	end)
	check("living reset restores movement and invalidates pending damage", function()
		local a, humanoid, _, _, _, target = fixture()
		assert(CombatService.tryAttack(a))
		StateHandler.resetCharacter(a)
		assert(humanoid.WalkSpeed == 16 and humanoid.JumpPower == 50)
		task.wait(0.15)
		assert(target.Health == 100)
	end)
	check("idle reset preserves current movement and immediately invalidates the old object", function()
		local a, humanoid = actor("IdleReset", origin)
		humanoid.WalkSpeed = 28
		StateHandler.resetCharacter(a)
		assert(humanoid.WalkSpeed == 28 and CombatSetup.getCharacterObj(a) == nil)
		assert(CombatService.tryAttack(a))
		local replacement = CombatSetup.getCharacterObj(a)
		assert(replacement and replacement.State == StateHandler.peekCharacterState(a))
	end)
	check("old removal preserves a replacement registration", function()
		local a = actor("Replacement", origin)
		StateHandler.removeCharacter(a)
		local replacement = CombatSetup.createCharacterObj(a)
		task.wait()
		assert(CombatSetup.getCharacterObj(a) == replacement)
	end)
	check("conflicting hit timing names the attack", function()
		local a = actor("InvalidTiming", origin)
		local ok, message = pcall(function()
			CombatSetup.createCharacterObj(
				a,
				nil,
				{ Attacks = { Click1 = { useHitMarker = true, waitForLanding = true } } }
			)
		end)
		assert(not ok and string.find(tostring(message), "Click1 cannot use both", 1, true))
	end)
	check("invalid combo configuration fails before combat starts", function()
		local a = actor("InvalidSettings", origin)
		local ok = pcall(function()
			CombatSetup.createCharacterObj(a, nil, { ClicksToFinishCombo = 0 })
		end)
		assert(not ok)
	end)
	check("invalid ultimate timing fails before combat starts", function()
		local a = actor("InvalidUltimate", origin)
		for _, cooldown in ipairs({ -1, math.huge, 0 / 0 }) do
			for _, field in ipairs({ "ClickCooldown", "ClickComboCooldown" }) do
				local ok = pcall(function()
					CombatSetup.createCharacterObj(a, nil, {
						UltSettings = if field == "ClickCooldown"
							then { ClickCooldown = cooldown }
							else { ClickComboCooldown = cooldown },
					})
				end)
				assert(not ok, field .. " accepted invalid timing")
			end
		end
	end)
	check("a side dash cannot request frontal damage", function()
		local a, _, root, _, _, target = fixture()
		root.Anchored = false
		assert(CombatService.tryDash(a, Vector3.xAxis, "Front"))
		task.wait(0.2)
		assert(target.Health == 100)
	end)
	check("marker-only attack does not use its timing fallback", function()
		local a, _, _, object, _, target = fixture()
		object.Settings.Attacks.Click1.useHitMarker = true
		assert(CombatService.tryAttack(a))
		task.wait(0.3)
		assert(target.Health == 100)
	end)

	folder:Destroy()
	return { passed = passed, failed = failed }
end

return tests
