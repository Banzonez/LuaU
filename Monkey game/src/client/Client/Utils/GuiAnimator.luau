--[[
	GuiAnimator provides reusable show and hide animations for GuiObjects.

	Example:
		local animator = GuiAnimator.new(frame, "PopIn", {
			Duration = 0.25,
			ShowSound = "rbxassetid://123",
		})

		animator:Show()
		animator:Hide()
]]

local tweenService = game:GetService("TweenService")
local replicatedStorage = game:GetService("ReplicatedStorage")

local soundUtils = require(replicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("SoundUtils"))

local GuiAnimator = {}
GuiAnimator.__index = GuiAnimator

local STYLE_CONFIGS = {
	SlideUp = {
		Duration = 0.55, EasingStyle = Enum.EasingStyle.Quint, EasingDirection = Enum.EasingDirection.Out,
		PositionOffset = UDim2.new(0, 0, 0.18, 0), StartTransparency = 0.6,
		AnimateBackground = false,
		ShowSound = "rbxassetid://10128766965", HideSound = "rbxassetid://139719503904449",
	},
	PopIn = {
		Duration = 0.45, EasingStyle = Enum.EasingStyle.Back, EasingDirection = Enum.EasingDirection.Out,
		StartScale = Vector2.new(0.7, 0.7), StartTransparency = 0,
		AnimateBackground = false,
		ShowSound = "rbxassetid://139800881181209", HideSound = "rbxassetid://139719503904449",
	},
	FadeSlide = {
		Duration = 0.5, EasingStyle = Enum.EasingStyle.Quad, EasingDirection = Enum.EasingDirection.Out,
		PositionOffset = UDim2.new(-0.08, 0, 0, 0), StartTransparency = 1,
		AnimateBackground = false,
		ShowSound = "rbxassetid://10128766965", HideSound = "rbxassetid://139719503904449",
	},
	Flip = {
		Duration = 0.5, EasingStyle = Enum.EasingStyle.Cubic, EasingDirection = Enum.EasingDirection.Out,
		StartScale = Vector2.new(1, 0.05), StartTransparency = 0.4,
		AnimateBackground = false,
		ShowSound = "rbxassetid://10128766965", HideSound = "rbxassetid://139719503904449",
	},
	Elastic = {
		Duration = 0.65, EasingStyle = Enum.EasingStyle.Elastic, EasingDirection = Enum.EasingDirection.Out,
		StartScale = Vector2.new(0.55, 0.55), StartTransparency = 0,
		AnimateBackground = false,
		ShowSound = "rbxassetid://139800881181209", HideSound = "rbxassetid://139719503904449",
	},
	Swoop = {
		Duration = 0.6, EasingStyle = Enum.EasingStyle.Quart, EasingDirection = Enum.EasingDirection.Out,
		PositionOffset = UDim2.new(0.12, 0, 0.1, 0), StartScale = Vector2.new(0.85, 0.85), StartTransparency = 0.7,
		AnimateBackground = false,
		ShowSound = "rbxassetid://10128766965", HideSound = "rbxassetid://139719503904449",
	},
}

type TransparencyState = { BackgroundTransparency: number, TextTransparency: number?, ImageTransparency: number? }

local function copyConfig(config)
	local copy = {}
	for key, value in pairs(config) do
		copy[key] = value
	end
	return copy
end

local function getTransparencyState(guiObject: GuiObject): TransparencyState
	local state: TransparencyState = { BackgroundTransparency = guiObject.BackgroundTransparency }
	if guiObject:IsA("TextLabel") or guiObject:IsA("TextButton") or guiObject:IsA("TextBox") then
		state.TextTransparency = guiObject.TextTransparency
	end
	if guiObject:IsA("ImageLabel") or guiObject:IsA("ImageButton") then
		state.ImageTransparency = guiObject.ImageTransparency
	end
	return state
end

local function captureDescendantTransparency(guiObject: GuiObject)
	local snapshot = {}
	for _, descendant in ipairs(guiObject:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			snapshot[descendant] = getTransparencyState(descendant)
		end
	end
	return snapshot
end

local function getTransparencyValue(originalValue: number, targetTransparency: number, alpha: number): number
	return originalValue + (targetTransparency - originalValue) * alpha
end

local function applyDescendantTransparency(
	snapshot,
	targetTransparency: number,
	alpha: number,
	animateBackground: boolean
)
	for guiObject, original in pairs(snapshot) do
		if guiObject.Parent then
			if animateBackground then
				guiObject.BackgroundTransparency = getTransparencyValue(original.BackgroundTransparency, targetTransparency, alpha)
			end
			if original.TextTransparency ~= nil then
				guiObject.TextTransparency = getTransparencyValue(original.TextTransparency, targetTransparency, alpha)
			end
			if original.ImageTransparency ~= nil then
				guiObject.ImageTransparency = getTransparencyValue(original.ImageTransparency, targetTransparency, alpha)
			end
		end
	end
end

local function createDescendantTweens(
	snapshot,
	targetTransparency: number,
		alpha: number,
		tweenInfo: TweenInfo,
		animateBackground: boolean
)
	local tweens = {}
	for guiObject, original in pairs(snapshot) do
		if guiObject.Parent then
			local goals = {}
			local hasGoals = animateBackground
			if animateBackground then
				goals.BackgroundTransparency = getTransparencyValue(original.BackgroundTransparency, targetTransparency, alpha)
			end
			if original.TextTransparency ~= nil then
				goals.TextTransparency = getTransparencyValue(original.TextTransparency, targetTransparency, alpha)
				hasGoals = true
			end
			if original.ImageTransparency ~= nil then
				goals.ImageTransparency = getTransparencyValue(original.ImageTransparency, targetTransparency, alpha)
				hasGoals = true
			end
			if hasGoals then
				table.insert(tweens, tweenService:Create(guiObject, tweenInfo, goals))
			end
		end
	end
	return tweens
end

local function getStyleConfig(styleName: string)
	local config = STYLE_CONFIGS[styleName]
	assert(config, ("[GuiAnimator] Unknown style %q."):format(styleName))
	return config
end

local function playSound(assetId: string?, shouldWait: boolean)
	if not assetId then
		return
	end
	local sound = soundUtils.playAsset(assetId)
	if shouldWait and sound then
		sound.Ended:Wait()
	end
end

function GuiAnimator.new(guiObject: GuiObject, styleName: string, overrides: { [string]: any }?)
	assert(typeof(guiObject) == "Instance" and guiObject:IsA("GuiObject"), "[GuiAnimator] guiObject must be a GuiObject.")
	local self = setmetatable({}, GuiAnimator)
	self._gui = guiObject
	self._styleName = styleName
	self._config = copyConfig(getStyleConfig(styleName))
	self._originalPosition = guiObject.Position
	self._originalSize = guiObject.Size
	self._originalBackgroundTransparency = guiObject.BackgroundTransparency
	self._descendantTransparency = captureDescendantTransparency(guiObject)
	self._activeTweens = {}
	self._primaryTween = nil
	self._completionCallback = nil
	self._uiScale = nil
	self._createdUiScale = false
	self.State = "Idle"
	if overrides then
		self:Configure(overrides)
	end
	return self
end

function GuiAnimator:Configure(overrides: { [string]: any })
	for key, value in pairs(overrides) do
		assert(self._config[key] ~= nil, ("[GuiAnimator] Unknown configuration field %q."):format(key))
		self._config[key] = value
	end
	return self
end

function GuiAnimator:SetEasing(easingStyle: Enum.EasingStyle, easingDirection: Enum.EasingDirection)
	self._config.EasingStyle = easingStyle
	self._config.EasingDirection = easingDirection
	return self
end

function GuiAnimator:SetStyle(styleName: string)
	assert(self.State == "Idle", "[GuiAnimator] Cannot change style while an animation is playing.")
	self._styleName = styleName
	self._config = copyConfig(getStyleConfig(styleName))
	return self
end

function GuiAnimator:OnComplete(callback)
	self._completionCallback = callback
	return self
end

function GuiAnimator:IsPlaying(): boolean
	return self.State ~= "Idle"
end

function GuiAnimator:IsVisible(): boolean
	return self._gui ~= nil and self._gui.Visible
end

function GuiAnimator:Refresh()
	assert(self.State == "Idle", "[GuiAnimator] Cannot refresh while an animation is playing.")
	local guiObject = self._gui
	assert(guiObject, "[GuiAnimator] Cannot refresh a destroyed animator.")
	self._originalPosition = guiObject.Position
	self._originalSize = guiObject.Size
	self._originalBackgroundTransparency = guiObject.BackgroundTransparency
	self._descendantTransparency = captureDescendantTransparency(guiObject)
	return self
end

function GuiAnimator:Show(waitForSound: boolean?)
	self:_play(false, waitForSound == true)
end

function GuiAnimator:Hide(waitForSound: boolean?)
	self:_play(true, waitForSound == true)
end

function GuiAnimator:Stop()
	self:_cancelTweens()
	self.State = "Idle"
	if self._gui then
		self._gui.Visible = false
	end
	return self
end

-- Compatibility aliases for the previous API.
function GuiAnimator:Play(waitForSound: boolean?)
	self:Show(waitForSound)
end

function GuiAnimator:Return(waitForSound: boolean?)
	self:Hide(waitForSound)
end

function GuiAnimator:PlaySound(shouldWait: boolean?)
	playSound(if self.State == "Hiding" then self._config.HideSound else self._config.ShowSound, shouldWait == true)
end

function GuiAnimator:Destroy()
	self:_cancelTweens()
	if self._createdUiScale and self._uiScale and self._uiScale.Parent then
		self._uiScale:Destroy()
	end
	self._gui = nil
	self._uiScale = nil
	self._descendantTransparency = {}
	self._completionCallback = nil
end

function GuiAnimator:_ensureUiScale(): UIScale
	if self._uiScale and self._uiScale.Parent then
		return self._uiScale
	end
	local guiObject = self._gui
	assert(guiObject, "[GuiAnimator] Cannot animate a destroyed animator.")
	local existingScale = guiObject:FindFirstChildOfClass("UIScale")
	if existingScale then
		self._uiScale = existingScale
		self._createdUiScale = false
	else
		local uiScale = Instance.new("UIScale")
		uiScale.Scale = 1
		uiScale.Parent = guiObject
		self._uiScale = uiScale
		self._createdUiScale = true
	end
	return self._uiScale
end

function GuiAnimator:_cancelTweens()
	for _, tween in ipairs(self._activeTweens) do
		tween:Cancel()
	end
	table.clear(self._activeTweens)
	self._primaryTween = nil
end

function GuiAnimator:_getScaledSize(scale: Vector2): UDim2
	return UDim2.new(self._originalSize.X.Scale * scale.X, self._originalSize.X.Offset * scale.X, self._originalSize.Y.Scale * scale.Y, self._originalSize.Y.Offset * scale.Y)
end

function GuiAnimator:_applyInitialState()
	local guiObject = self._gui
	assert(guiObject, "[GuiAnimator] Cannot animate a destroyed animator.")
	local config = self._config
	guiObject.Position = self._originalPosition + (config.PositionOffset or UDim2.new())
	if config.AnimateBackground then
		guiObject.BackgroundTransparency = config.StartTransparency
	end
	applyDescendantTransparency(self._descendantTransparency, config.StartTransparency, 1, config.AnimateBackground)
	if self._styleName == "Flip" then
		guiObject.Size = self:_getScaledSize(config.StartScale)
	elseif config.StartScale then
		self:_ensureUiScale().Scale = config.StartScale.X
	else
		guiObject.Size = self._originalSize
	end
end

function GuiAnimator:_createGoals(isHiding: boolean)
	local config = self._config
	local position = if isHiding then self._originalPosition + (config.PositionOffset or UDim2.new()) else self._originalPosition
	local transparency = if isHiding then config.StartTransparency else self._originalBackgroundTransparency
	local guiGoals = { Position = position }
	if config.AnimateBackground then
		guiGoals.BackgroundTransparency = transparency
	end
	if self._styleName == "Flip" then
		guiGoals.Size = if isHiding then self:_getScaledSize(config.StartScale) else self._originalSize
		return nil, guiGoals
	end
	if config.StartScale then
		return { Scale = if isHiding then config.StartScale.X else 1 }, guiGoals
	end
	guiGoals.Size = self._originalSize
	return nil, guiGoals
end

function GuiAnimator:_play(isHiding: boolean, waitForSound: boolean)
	local guiObject = self._gui
	assert(guiObject, "[GuiAnimator] Cannot animate a destroyed animator.")
	self:_cancelTweens()
	if not isHiding then
		guiObject.Visible = true
		self:_applyInitialState()
	end

	local config = self._config
	local tweenInfo = TweenInfo.new(if isHiding then config.Duration * 0.85 else config.Duration, config.EasingStyle, if isHiding then Enum.EasingDirection.In else config.EasingDirection)
	local scaleGoals, guiGoals = self:_createGoals(isHiding)
	local primaryTween = tweenService:Create(scaleGoals and self:_ensureUiScale() or guiObject, tweenInfo, scaleGoals or guiGoals)
	self._primaryTween = primaryTween
	table.insert(self._activeTweens, primaryTween)
	if scaleGoals then
		table.insert(self._activeTweens, tweenService:Create(guiObject, tweenInfo, guiGoals))
	end
	for _, tween in ipairs(createDescendantTweens(
		self._descendantTransparency,
		config.StartTransparency,
		if isHiding then 1 else 0,
		tweenInfo,
		config.AnimateBackground
	)) do
		table.insert(self._activeTweens, tween)
	end

	self.State = if isHiding then "Hiding" else "Showing"
	primaryTween.Completed:Once(function(playbackState)
		if self._primaryTween ~= primaryTween or playbackState ~= Enum.PlaybackState.Completed then
			return
		end
		self._primaryTween = nil
		table.clear(self._activeTweens)
		self.State = "Idle"
		if isHiding and guiObject.Parent then
			guiObject.Visible = false
		end
		if self._completionCallback then
			self._completionCallback(self, if isHiding then "Hide" else "Show")
		end
	end)

	for _, tween in ipairs(self._activeTweens) do
		tween:Play()
	end
	playSound(if isHiding then config.HideSound else config.ShowSound, waitForSound)
end

return GuiAnimator
