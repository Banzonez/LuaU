--[[
    GuiAnimator — Módulo de animações para GUI (LuaU)

    SETUP:
        local anim = GuiAnimator.new(meuFrame, "PopIn")
        anim:Play()    -- anima entrada, seta Visible = true
        anim:Return()  -- anima saída,   seta Visible = false

    ESTILOS:
        "SlideUp"   — sobe da parte inferior
        "PopIn"     — escala de zero com bounce
        "FadeSlide" — fade + deslize lateral
        "Flip"      — simula virada no eixo Y
        "Elastic"   — overshoot elástico
        "Swoop"     — momentum de canto com aceleração

    CONFIGURE (campos disponíveis):
        Duracao              number          duração da entrada em segundos
        EasingStyle          EasingStyle
        EasingDirection      EasingDirection
        DeslocamentoOffset   UDim2           offset de posição no estado inicial
        EscalaInicial        Vector2         escala de partida via UIScale
        TransparenciaInicial number          BackgroundTransparency inicial (0–1)
        IntroSound           string          "rbxassetid://..."
        EndSound             string

    RECEITAS:
        Frame / painel       GuiAnimator.new(frame, "SlideUp")
        Popup / modal        GuiAnimator.new(popup, "Elastic")
        Botão de clique      GuiAnimator.new(btn, "PopIn") + Configure({ Duracao=0.18, EscalaInicial=Vector2.new(0.88,0.88) })
        Tooltip              GuiAnimator.new(tip, "FadeSlide") + Configure({ Duracao=0.22, DeslocamentoOffset=UDim2.new(-0.04,0,0,0) })
        Card virando         GuiAnimator.new(card, "Flip")
        Entrada dramática    GuiAnimator.new(el, "Swoop") + Configure({ Duracao=0.75 })
--]]

local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local EstilosConfig = {
	SlideUp = {
		Duracao = 0.55,
		EasingStyle = Enum.EasingStyle.Quint,
		EasingDirection = Enum.EasingDirection.Out,
		DeslocamentoOffset = UDim2.new(0, 0, 0.18, 0),
		TransparenciaInicial = 0.6,
		IntroSound = "rbxassetid://10128766965",
		EndSound = "rbxassetid://139719503904449",
	},
	PopIn = {
		Duracao = 0.45,
		EasingStyle = Enum.EasingStyle.Back,
		EasingDirection = Enum.EasingDirection.Out,
		EscalaInicial = Vector2.new(0.7, 0.7),
		TransparenciaInicial = 0,
		IntroSound = "rbxassetid://139800881181209",
		EndSound = "rbxassetid://139719503904449",
	},
	FadeSlide = {
		Duracao = 0.5,
		EasingStyle = Enum.EasingStyle.Quad,
		EasingDirection = Enum.EasingDirection.Out,
		DeslocamentoOffset = UDim2.new(-0.08, 0, 0, 0),
		TransparenciaInicial = 1,
		IntroSound = "rbxassetid://10128766965",
		EndSound = "rbxassetid://139719503904449",
	},
	Flip = {
		Duracao = 0.5,
		EasingStyle = Enum.EasingStyle.Cubic,
		EasingDirection = Enum.EasingDirection.Out,
		EscalaInicial = Vector2.new(1, 0.05),
		TransparenciaInicial = 0.4,
		IntroSound = "rbxassetid://10128766965",
		EndSound = "rbxassetid://139719503904449",
	},
	Elastic = {
		Duracao = 0.65,
		EasingStyle = Enum.EasingStyle.Elastic,
		EasingDirection = Enum.EasingDirection.Out,
		EscalaInicial = Vector2.new(0.55, 0.55),
		TransparenciaInicial = 0,
		IntroSound = "rbxassetid://139800881181209",
		EndSound = "rbxassetid://139719503904449",
	},
	Swoop = {
		Duracao = 0.6,
		EasingStyle = Enum.EasingStyle.Quart,
		EasingDirection = Enum.EasingDirection.Out,
		DeslocamentoOffset = UDim2.new(0.12, 0, 0.1, 0),
		EscalaInicial = Vector2.new(0.85, 0.85),
		TransparenciaInicial = 0.7,
		IntroSound = "rbxassetid://10128766965",
		EndSound = "rbxassetid://139719503904449",
	},
}

local ESTILOS_VALIDOS = {}
for nome in pairs(EstilosConfig) do
	ESTILOS_VALIDOS[nome] = true
end

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function playSound(id, shouldWait)
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Parent = SoundService
	sound:Play()
	if shouldWait then
		sound.Ended:Wait()
	end
	game:GetService("Debris"):AddItem(sound, 10)
end

-- Salva BackgroundTransparency, TextTransparency e ImageTransparency de cada filho
-- para poder restaurar corretamente no Return (sem sobrescrever valores customizados)
local function capturarTransparenciasFilhos(pai)
	local snapshot = {}
	local function capturar(obj)
		for _, filho in ipairs(obj:GetChildren()) do
			if filho:IsA("GuiObject") then
				local r = { BackgroundTransparency = filho.BackgroundTransparency }
				if filho:IsA("TextLabel") or filho:IsA("TextButton") or filho:IsA("TextBox") then
					r.TextTransparency = filho.TextTransparency
				end
				if filho:IsA("ImageLabel") or filho:IsA("ImageButton") then
					r.ImageTransparency = filho.ImageTransparency
				end
				snapshot[filho] = r
				capturar(filho)
			end
		end
	end
	capturar(pai)
	return snapshot
end

-- Seta filhos instantaneamente — usado antes do tween começar (estado inicial)
local function setarTransparenciaFilhos(snapshot, transparencia, fator)
	for filho, original in pairs(snapshot) do
		if filho.Parent then
			filho.BackgroundTransparency = original.BackgroundTransparency
				+ (transparencia - original.BackgroundTransparency) * fator
			if original.TextTransparency ~= nil then
				filho.TextTransparency = original.TextTransparency + (transparencia - original.TextTransparency) * fator
			end
			if original.ImageTransparency ~= nil then
				filho.ImageTransparency = original.ImageTransparency
					+ (transparencia - original.ImageTransparency) * fator
			end
		end
	end
end

-- Anima filhos via tween junto com o pai para evitar flash/pop visual
local function tweenTransparenciaFilhos(snapshot, transparencia, fator, info)
	for filho, original in pairs(snapshot) do
		if filho.Parent then
			local alvo = {}
			alvo.BackgroundTransparency = original.BackgroundTransparency
				+ (transparencia - original.BackgroundTransparency) * fator
			if original.TextTransparency ~= nil then
				alvo.TextTransparency = original.TextTransparency + (transparencia - original.TextTransparency) * fator
			end
			if original.ImageTransparency ~= nil then
				alvo.ImageTransparency = original.ImageTransparency
					+ (transparencia - original.ImageTransparency) * fator
			end
			TweenService:Create(filho, info, alvo):Play()
		end
	end
end

-- ─── Classe ──────────────────────────────────────────────────────────────────

local GuiAnimator = {}
GuiAnimator.__index = GuiAnimator

function GuiAnimator.new(guiObject: GuiObject, estilo: string)
	assert(
		typeof(guiObject) == "Instance" and guiObject:IsA("GuiObject"),
		"[GuiAnimator] Primeiro argumento deve ser um GuiObject válido."
	)
	assert(
		ESTILOS_VALIDOS[estilo],
		"[GuiAnimator] Estilo inválido: '"
			.. tostring(estilo)
			.. "'. Válidos: SlideUp, PopIn, FadeSlide, Flip, Elastic, Swoop"
	)

	local self = setmetatable({}, GuiAnimator)

	self._gui = guiObject
	self._estilo = estilo

	-- Cópia rasa para que :Configure() não afete outras instâncias do mesmo estilo
	self._config = {}
	for k, v in pairs(EstilosConfig[estilo]) do
		self._config[k] = v
	end

	-- Estado original salvo no new() — usado para restaurar após Return()
	self._posicaoOriginal = guiObject.Position
	self._tamanhoOriginal = guiObject.Size
	self._transparenciaOriginal = guiObject.BackgroundTransparency
	self._snapshotFilhos = capturarTransparenciasFilhos(guiObject)

	self._tweenAtivo = nil
	self._tweensParalelos = {}
	self._callbackConcluido = nil
	self.State = "Idle" -- "Idle" | "Playing" | "Returning"

	self._uiScale = nil
	self._uiScaleCriado = false
	if self._config.EscalaInicial then
		self:_garantirUIScale()
	end

	return self
end

-- Sobrescreve campos da config desta instância sem afetar outras do mesmo estilo
-- Valida o campo antes de aceitar para evitar typo silencioso
function GuiAnimator:Configure(overrides: { [string]: any })
	for campo, valor in pairs(overrides) do
		assert(self._config[campo] ~= nil, "[GuiAnimator] Campo inválido em Configure(): '" .. tostring(campo) .. "'")
		self._config[campo] = valor
	end
	if overrides.EscalaInicial and not self._uiScale then
		self:_garantirUIScale()
	end
end

function GuiAnimator:SetEasing(estilo: Enum.EasingStyle, direcao: Enum.EasingDirection)
	self._config.EasingStyle = estilo
	self._config.EasingDirection = direcao
end

function GuiAnimator:OnComplete(callback: (any, string) -> ())
	self._callbackConcluido = callback
end

function GuiAnimator:PlaySound(shouldWait: boolean?)
	local id = (self.State == "Returning") and self._config.EndSound or self._config.IntroSound
	if id then
		playSound(id, shouldWait or false)
	end
end

function GuiAnimator:Play(waitSound: boolean?)
	self:_cancelarTweens()
	self._gui.Visible = true
	self:_aplicarEstadoInicial()

	local config = self._config
	local info = TweenInfo.new(config.Duracao, config.EasingStyle, config.EasingDirection)
	local alvoEscala, alvoGui = self:_construirAlvos(false)

	local principal = TweenService:Create(alvoEscala and self._uiScale or self._gui, info, alvoEscala or alvoGui)

	if alvoEscala and alvoGui then -- tween paralelo no gui quando o principal é no UIScale
		local tp = TweenService:Create(self._gui, info, alvoGui)
		tp:Play()
		table.insert(self._tweensParalelos, tp)
	end
	tweenTransparenciaFilhos(self._snapshotFilhos, config.TransparenciaInicial, 0, info) -- anima filhos junto

	self._tweenAtivo = principal
	self.State = "Playing"

	principal.Completed:Connect(function(estado)
		if estado ~= Enum.PlaybackState.Completed then
			return
		end
		self._tweenAtivo = nil
		self.State = "Idle"
		if self._callbackConcluido then
			self._callbackConcluido(self, "Play")
		end
	end)

	principal:Play()
	self:PlaySound(waitSound)
end

function GuiAnimator:Return(waitSound: boolean?)
	self:_cancelarTweens()

	local config = self._config
	local info = TweenInfo.new(config.Duracao * 0.85, config.EasingStyle, Enum.EasingDirection.In) -- saída levemente mais rápida
	local alvoEscala, alvoGui = self:_construirAlvos(true)

	local principal = TweenService:Create(alvoEscala and self._uiScale or self._gui, info, alvoEscala or alvoGui)

	if alvoEscala and alvoGui then
		local tp = TweenService:Create(self._gui, info, alvoGui)
		tp:Play()
		table.insert(self._tweensParalelos, tp)
	end
	tweenTransparenciaFilhos(self._snapshotFilhos, config.TransparenciaInicial, 1, info) -- anima filhos junto

	self._tweenAtivo = principal
	self.State = "Returning"

	principal.Completed:Connect(function(estado)
		if estado ~= Enum.PlaybackState.Completed then
			return
		end
		self._tweenAtivo = nil
		self.State = "Idle"
		self._gui.Visible = false
		if self._callbackConcluido then
			self._callbackConcluido(self, "Return")
		end
	end)

	principal:Play()
	self:PlaySound(waitSound)
end

function GuiAnimator:Destroy()
	self:_cancelarTweens()
	if self._uiScaleCriado and self._uiScale and self._uiScale.Parent then
		self._uiScale:Destroy()
	end
	self._gui = nil
	self._uiScale = nil
	self._snapshotFilhos = nil
	self._callbackConcluido = nil
end

-- ─── Privados ─────────────────────────────────────────────────────────────────

function GuiAnimator:_garantirUIScale()
	local existente = self._gui:FindFirstChildOfClass("UIScale")
	if existente then
		self._uiScale = existente
		self._uiScaleCriado = false -- não foi criado por nós, não destruímos no Destroy()
	else
		local nova = Instance.new("UIScale")
		nova.Scale = 1
		nova.Parent = self._gui
		self._uiScale = nova
		self._uiScaleCriado = true
	end
end

function GuiAnimator:_cancelarTweens()
	local activeTween = self._tweenAtivo
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end

	for _, tp in ipairs(self._tweensParalelos) do
		tp:Cancel()
	end
	self._tweensParalelos = {}
end

function GuiAnimator:_aplicarEstadoInicial()
	local config = self._config
	local gui = self._gui

	if config.DeslocamentoOffset then
		gui.Position = self._posicaoOriginal + config.DeslocamentoOffset
	end

	if config.EscalaInicial then
		self:_garantirUIScale()
		self._uiScale.Scale = config.EscalaInicial.X
	end

	if self._estilo == "Flip" then -- Flip manipula Size diretamente no eixo Y para simular virada
		gui.Size = UDim2.new(
			self._tamanhoOriginal.X.Scale,
			self._tamanhoOriginal.X.Offset,
			self._tamanhoOriginal.Y.Scale * config.EscalaInicial.Y,
			self._tamanhoOriginal.Y.Offset * config.EscalaInicial.Y
		)
	end

	if config.TransparenciaInicial ~= nil then
		gui.BackgroundTransparency = config.TransparenciaInicial
		setarTransparenciaFilhos(self._snapshotFilhos, config.TransparenciaInicial, 1)
	end
end

-- Retorna (alvoEscala, alvoGui): quando alvoEscala ~= nil o tween principal vai no UIScale
-- e um tween paralelo roda no gui. Quando nil, tudo vai num tween único no gui.
function GuiAnimator:_construirAlvos(saindo: boolean)
	local config = self._config

	local posicaoFinal = saindo and (self._posicaoOriginal + (config.DeslocamentoOffset or UDim2.new()))
		or self._posicaoOriginal
	local transparenciaFinal = saindo and config.TransparenciaInicial or self._transparenciaOriginal

	if config.EscalaInicial and self._uiScale then
		local alvoGui = { BackgroundTransparency = transparenciaFinal }
		if config.DeslocamentoOffset then
			alvoGui.Position = posicaoFinal
		end
		return { Scale = saindo and config.EscalaInicial.X or 1 }, alvoGui
	end

	local alvoGui = { Position = posicaoFinal, BackgroundTransparency = transparenciaFinal }

	if self._estilo == "Flip" then
		local escalaY = saindo and config.EscalaInicial.Y or 1
		alvoGui.Size = UDim2.new(
			self._tamanhoOriginal.X.Scale,
			self._tamanhoOriginal.X.Offset,
			self._tamanhoOriginal.Y.Scale * escalaY,
			self._tamanhoOriginal.Y.Offset * escalaY
		)
	else
		alvoGui.Size = self._tamanhoOriginal
	end

	return nil, alvoGui
end

return GuiAnimator
