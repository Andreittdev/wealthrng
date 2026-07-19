local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

-- Model REAL per pet -- pui un Model/MeshPart in ServerStorage.PetModels,
-- numit EXACT ca PetId-ul din PetDatabase.luau (ex: "KingOfKicks"), generat
-- cu AI Mesh Generator din Studio sau adus din Toolbox. Pana nu exista un
-- model real pentru un pet, NU aratam nimic in lume pentru el (doar iconita
-- 2D din slotul de pe ecran, vezi PetEquipSlots.client.luau) -- fara sfera
-- placeholder, cerut explicit.
local petModelsFolder = ServerStorage:FindFirstChild("PetModels")
if not petModelsFolder then
	petModelsFolder = Instance.new("Folder")
	petModelsFolder.Name = "PetModels"
	petModelsFolder.Parent = ServerStorage
end

local petVisualsFolder = workspace:FindFirstChild("PetVisuals")
if not petVisualsFolder then
	petVisualsFolder = Instance.new("Folder")
	petVisualsFolder.Name = "PetVisuals"
	petVisualsFolder.Parent = workspace
end

-- Jucatorul poate pune fie un Model (eventual fara PrimaryPart setat), fie
-- direct o singura Part/MeshPart, fara niciun Model in jurul ei (cazul cel
-- mai simplu -- un model generat/adus din Toolbox vine adesea ca o singura
-- piesa). Il impachetam mereu intr-un Model proaspat, cu PrimaryPart garantat
-- setat, ca restul codului (sanitizeModel, bucla de urmarire) sa functioneze
-- identic indiferent ce a adus jucatorul.
local function wrapInModel(instance, name)
	if instance:IsA("Model") then
		if not instance.PrimaryPart then
			local firstPart = instance:FindFirstChildWhichIsA("BasePart", true)
			if firstPart then
				instance.PrimaryPart = firstPart
			end
		end
		instance.Name = name
		return instance
	end

	if not instance:IsA("BasePart") then
		-- Nici Model, nici Part/MeshPart (ex: cineva a pus din greseala un
		-- Folder in ServerStorage.PetModels) -- model.PrimaryPart = instance
		-- ar arunca eroare mai jos, fiindca PrimaryPart accepta doar BasePart.
		-- Tratam ca "niciun model real", la fel ca atunci cand folderul nu are
		-- deloc o intrare pentru acest pet.
		warn("PetVisualManager: " .. instance:GetFullName() .. " nu e nici Model, nici BasePart -- ignorat.")
		instance:Destroy()
		return nil
	end

	local model = Instance.new("Model")
	model.Name = name
	instance.Parent = model
	model.PrimaryPart = instance
	return model
end

-- Modelele aduse din Toolbox/AI Mesh Generator pot avea coliziune/greutate
-- proprie -- le facem inofensive (nu blocheaza jucatorul, nu cad din cauza
-- gravitatiei) si le ancoram, ca pozitionarea manuala din bucla de mai jos
-- sa functioneze identic pentru placeholder SI pentru modelul real.
local function sanitizeModel(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
end

-- Intoarce nil daca nu exista inca un model real pus in ServerStorage.
-- PetModels pentru acest pet -- apelantul (attachSlot) nu ataseaza nimic in
-- lume in acel caz (nicio sfera placeholder).
local function getRealModel(petId)
	local template = petModelsFolder:FindFirstChild(petId)
	if not template then
		return nil
	end

	local clone = template:Clone()
	local model = wrapInModel(clone, petId .. "Model")
	if not model then
		return nil
	end
	sanitizeModel(model)
	return model
end

local SLOT_OFFSETS = {
	Slot1 = Vector3.new(-2.5, 2, 2.5),
	Slot2 = Vector3.new(2.5, 2, 2.5)
}

-- attachedPets[player][slotName] = {Model = Model, PetId = string}
local attachedPets = {}

local function detachSlot(player, slotName)
	local pets = attachedPets[player]
	if not pets or not pets[slotName] then
		return
	end

	pets[slotName].Model:Destroy()
	pets[slotName] = nil
end

local function attachSlot(player, slotName, petId)
	detachSlot(player, slotName)

	if not petId or petId == "" then
		return
	end

	local model = getRealModel(petId)
	if not model then
		-- Niciun model real inca pentru acest pet -- nu aratam nimic in lume
		-- (doar iconita 2D din slotul de pe ecran).
		return
	end

	if not model.PrimaryPart then
		-- Model real, dar fara niciun BasePart valid (ex: MeshPart lipsa) --
		-- n-are ce sa pozitionam.
		model:Destroy()
		return
	end

	model.Name = player.Name .. "_" .. slotName .. "_" .. petId
	model.Parent = petVisualsFolder

	attachedPets[player] = attachedPets[player] or {}
	attachedPets[player][slotName] = {Model = model, PetId = petId}
end

local function watchEquippedPets(player)
	local equippedPets = player:WaitForChild("EquippedPets", 10)
	if not equippedPets then
		return
	end

	local slot1 = equippedPets:WaitForChild("Slot1", 5)
	if slot1 then
		attachSlot(player, "Slot1", slot1.Value)
		slot1:GetPropertyChangedSignal("Value"):Connect(function()
			attachSlot(player, "Slot1", slot1.Value)
		end)
	end

	local slot2 = equippedPets:WaitForChild("Slot2", 5)
	if slot2 then
		attachSlot(player, "Slot2", slot2.Value)
		slot2:GetPropertyChangedSignal("Value"):Connect(function()
			attachSlot(player, "Slot2", slot2.Value)
		end)
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(watchEquippedPets, player)
end)

Players.PlayerRemoving:Connect(function(player)
	local pets = attachedPets[player]
	if pets then
		for _, entry in pairs(pets) do
			entry.Model:Destroy()
		end
	end
	attachedPets[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(watchEquippedPets, player)
end

-- Pozitioneaza fiecare pet echipat in spatele jucatorului sau, cu o usoara
-- plutire sinusoidala -- server-side, cu parti ANCORATE (nu simulate fizic),
-- ca miscarea sa se replice corect la TOTI jucatorii, nu doar la proprietar
-- (parti neancorate ar depinde de network ownership, mult mai fragil).
RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()

	for player, pets in pairs(attachedPets) do
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")

		if rootPart then
			for slotName, entry in pairs(pets) do
				local model = entry.Model

				if model and model.PrimaryPart then
					local offset = SLOT_OFFSETS[slotName] or Vector3.new(0, 2, 2.5)
					local bobPhase = (slotName == "Slot2") and math.pi or 0
					local bob = math.sin(now * 2 + bobPhase) * 0.3

					local targetPosition = rootPart.CFrame:PointToWorldSpace(offset) + Vector3.new(0, bob, 0)
					local targetCFrame = CFrame.new(targetPosition, targetPosition + rootPart.CFrame.LookVector)

					local currentCFrame = model:GetPivot()
					model:PivotTo(currentCFrame:Lerp(targetCFrame, math.clamp(dt * 6, 0, 1)))
				end
			end
		end
	end
end)
