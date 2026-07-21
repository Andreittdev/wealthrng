local Workspace = game:GetService("Workspace")

-- "Bobux Man" a fost sters din greseala si inlocuit cu un model nou,
-- "Millionaire" -- acelasi loc, aceeasi logica, doar numele modelului cautat
-- in Workspace s-a schimbat.
local NPC_MODEL_NAME = "Millionaire"

-- Animatia default "Wave" din Roblox (aceeasi cu /e wave), pentru rig R15.
-- Daca modelul e R6 (rig vechi), schimba id-ul cu "rbxassetid://128777973"
-- (Wave-ul default pentru R6) -- spune-mi daca nu se misca deloc in joc.
local WAVE_ANIMATION_ID = "rbxassetid://507770239"
local WAVE_PAUSE_SECONDS = 5

-- Pozitie EXACTA, data de user (coordonatele personajului lui, luate chiar
-- din locul unde vrea sa stea NPC-ul, dupa geamul bancii) -- folosita direct,
-- fara niciun calcul relativ la banca.
local TELLER_POSITION = Vector3.new(56.046993255615234, 10.437660217285156, 737.3899536132812)

-- Cerut: rotit + mutat putin mai in spate (departe de strada, spre +X) fata
-- de pozitia originala a lui Bobux Man -- valori usor de ajustat daca nu
-- sunt exact cat trebuie.
local TELLER_ROTATION_OFFSET_DEGREES = 90
local TELLER_BACK_OFFSET = Vector3.new(2, 0, 0)

-- "Bobux Man" (numele Modelului) apare plutind deasupra capului -- e nametag-ul
-- implicit al Roblox pentru orice model cu Humanoid (ia automat Model.Name).
-- DisplayDistanceType = None il opreste complet, indiferent de Model.Name.
local function hideNameTag(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	-- Daca mai exista un BillboardGui separat, pus manual (nu cel implicit de
	-- Humanoid), il scoatem si pe ala.
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BillboardGui") and descendant.Name:lower():find("name") then
			descendant:Destroy()
		end
	end
end

local function anchorModel(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

-- Ruleaza animatia de "wave" in bucla (o data, pauza, o data, pauza...) --
-- functioneaza si cu partile ancorate (Anchored nu opreste Motor6D-urile
-- animate, doar fizica/coliziunea).
local function startWaveLoop(npc)
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("BankTeller: '" .. npc.Name .. "' nu are Humanoid -- nu pot rula animatia de wave.")
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = WAVE_ANIMATION_ID

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not ok or not track then
		warn("BankTeller: nu am putut incarca animatia de wave pentru '" .. npc.Name .. "' -- " .. tostring(track))
		return
	end

	track.Priority = Enum.AnimationPriority.Action
	print("BankTeller: animatia de wave incarcata pentru '" .. npc.Name .. "' (Length=" .. tostring(track.Length) .. "), pornesc bucla.")

	task.spawn(function()
		while npc.Parent do
			track:Play()
			track.Stopped:Wait()
			task.wait(WAVE_PAUSE_SECONDS)
		end
	end)
end

local function positionTeller(npc)
	local npcCFrame = npc:GetPivot()
	local position = TELLER_POSITION + TELLER_BACK_OFFSET
	local rotation = npcCFrame.Rotation * CFrame.Angles(0, math.rad(TELLER_ROTATION_OFFSET_DEGREES), 0)

	npc:PivotTo(CFrame.new(position) * rotation)

	anchorModel(npc)
	hideNameTag(npc)

	print("BankTeller: '" .. npc.Name .. "' pus la " .. tostring(TELLER_POSITION) .. ".")
end

local function trySetup()
	local npc = Workspace:FindFirstChild(NPC_MODEL_NAME)
	if not npc then
		return
	end

	if not npc:GetAttribute("TellerPositioned") then
		positionTeller(npc)
		npc:SetAttribute("TellerPositioned", true)
	end

	-- Separat de flag-ul de pozitionare -- daca serverul a fost repornit si
	-- NPC-ul era deja pozitionat dintr-o sesiune anterioara salvata, tot
	-- pornim bucla de wave (altfel n-ar mai porni niciodata).
	if not npc:GetAttribute("WaveLoopStarted") then
		startWaveLoop(npc)
		npc:SetAttribute("WaveLoopStarted", true)
	end
end

trySetup()

Workspace.ChildAdded:Connect(function(child)
	if child.Name == NPC_MODEL_NAME then
		task.wait(0.5)
		trySetup()
	end
end)
