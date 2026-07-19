local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local PetDatabase = require(modulesFolder:WaitForChild("PetDatabase"))

-- Acelasi panou "Pets" pe care il deschide si butonul din MainHUD (Row2 >
-- ItemsButton) -- ItemsGui.rbxmx asculta direct schimbarea proprietatii
-- Visible (nu un remote dedicat), deci un simplu toggle extern e sigur/
-- suportat.
-- Timeout explicit (nu WaitForChild simplu) -- la un server proaspat (harta
-- se construieste de la zero la fiecare pornire), replicarea catre client
-- poate depasi cele 5 secunde implicite, umpland consola cu avertismente
-- "Infinite yield possible" degeaba (comportament normal, nu o eroare).
local itemsGui = playerGui:WaitForChild("ItemsGui", 30)
if not itemsGui then
	warn("PetEquipSlots.client.luau: ItemsGui nu a aparut in PlayerGui dupa 30s -- sloturile de pet nu pornesc.")
	return
end

local itemsFrame = itemsGui:WaitForChild("MainFrame")

local SLOT_COUNT = 2 -- Economy.EquippedPetSlots -- vezi EconomyConfig.luau

local function computeIsMobile()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return UserInputService.TouchEnabled or viewport.X < 700 or viewport.Y < 500
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PetEquipSlotsGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local holder = Instance.new("Frame")
holder.Name = "SlotsHolder"
holder.AnchorPoint = Vector2.new(0.5, 1)
holder.BackgroundTransparency = 1
holder.ZIndex = 10
holder.Parent = screenGui

local holderLayout = Instance.new("UIListLayout")
holderLayout.FillDirection = Enum.FillDirection.Horizontal
holderLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
holderLayout.VerticalAlignment = Enum.VerticalAlignment.Center
holderLayout.Padding = UDim.new(0, 10)
holderLayout.SortOrder = Enum.SortOrder.LayoutOrder
holderLayout.Parent = holder

local function applyLayout()
	local isMobile = computeIsMobile()
	local slotSize = isMobile and 52 or 72
	local bottomGap = isMobile and 8 or 16

	holder.Position = UDim2.new(0.5, 0, 1, -bottomGap)
	holder.Size = UDim2.new(0, (slotSize + 10) * SLOT_COUNT, 0, slotSize)

	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("TextButton") then
			child.Size = UDim2.fromOffset(slotSize, slotSize)
		end
	end
end

local slots = {}

local function createSlot(order)
	local slot = Instance.new("TextButton")
	slot.Name = "Slot" .. order
	slot.LayoutOrder = order
	slot.BackgroundColor3 = Color3.fromRGB(35, 32, 42)
	slot.AutoButtonColor = false
	slot.Text = ""
	slot.ZIndex = 10
	slot.Parent = holder

	Instance.new("UICorner", slot).CornerRadius = UDim.new(0.22, 0)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 140, 255)
	stroke.Thickness = 3
	stroke.Transparency = 0
	stroke.Parent = slot

	-- Iconita generica, estompata -- afisata cat timp slotul e gol (acelasi
	-- limbaj vizual ca placeholder-ele cu model estompat din referinta primita).
	local placeholderIcon = Instance.new("TextLabel")
	placeholderIcon.Name = "PlaceholderIcon"
	placeholderIcon.BackgroundTransparency = 1
	placeholderIcon.Size = UDim2.new(1, 0, 1, 0)
	placeholderIcon.Text = "🐾"
	placeholderIcon.TextTransparency = 0.7
	placeholderIcon.TextScaled = true
	placeholderIcon.Font = Enum.Font.FredokaOne
	placeholderIcon.ZIndex = 11
	placeholderIcon.Parent = slot

	local petImage = Instance.new("ImageLabel")
	petImage.Name = "PetImage"
	petImage.BackgroundTransparency = 1
	petImage.Size = UDim2.new(0.8, 0, 0.8, 0)
	petImage.Position = UDim2.new(0.5, 0, 0.5, 0)
	petImage.AnchorPoint = Vector2.new(0.5, 0.5)
	petImage.ScaleType = Enum.ScaleType.Fit
	petImage.Visible = false
	petImage.ZIndex = 11
	petImage.Parent = slot

	local entry = {Button = slot, PlaceholderIcon = placeholderIcon, PetImage = petImage, PetId = "", InstanceName = ""}

	-- Daca slotul are un pet echipat, deschidem direct detaliile ACELUI pet
	-- (acelasi popup pe care il deschide un click pe cardul lui din lista) --
	-- nu doar panoul general. Un slot gol tot deschide doar panoul, ca inainte.
	slot.Activated:Connect(function()
		if entry.PetId ~= "" and entry.InstanceName ~= "" and _G.OpenItemDetails then
			_G.OpenItemDetails(entry.PetId, entry.InstanceName)
		end

		itemsFrame.Visible = true
	end)

	return entry
end

for i = 1, SLOT_COUNT do
	slots[i] = createSlot(i)
end

applyLayout()

local function refreshSlot(index, petId, instanceName)
	local slot = slots[index]
	if not slot then
		return
	end

	slot.PetId = petId or ""
	slot.InstanceName = instanceName or ""

	local petData = petId and petId ~= "" and PetDatabase.Pets[petId]

	if petData and petData.Image and petData.Image ~= "" then
		slot.PetImage.Image = petData.Image
		slot.PetImage.Visible = true
		slot.PlaceholderIcon.Visible = false
	else
		slot.PetImage.Visible = false
		slot.PlaceholderIcon.Visible = true
	end
end

-- WaitForChild cu timeout -- daca EquippedPets nu apare in primele secunde
-- (incarcare lenta a datelor), sloturile raman goale in loc sa astepte la
-- nesfarsit, la fel ca celelalte GUI-uri care citesc date de la DataManager.
local equippedPets = player:WaitForChild("EquippedPets", 10)

if equippedPets then
	local slot1 = equippedPets:WaitForChild("Slot1", 5)
	if slot1 then
		local function refreshSlot1()
			refreshSlot(1, slot1.Value, slot1:GetAttribute("InstanceName"))
		end

		refreshSlot1()
		slot1:GetPropertyChangedSignal("Value"):Connect(refreshSlot1)
		slot1:GetAttributeChangedSignal("InstanceName"):Connect(refreshSlot1)
	end

	local slot2 = equippedPets:WaitForChild("Slot2", 5)
	if slot2 then
		local function refreshSlot2()
			refreshSlot(2, slot2.Value, slot2:GetAttribute("InstanceName"))
		end

		refreshSlot2()
		slot2:GetPropertyChangedSignal("Value"):Connect(refreshSlot2)
		slot2:GetAttributeChangedSignal("InstanceName"):Connect(refreshSlot2)
	end
end

do
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
end

-- Ascunse cat timp orice alt panou modal e deschis (acelasi flag comun ca
-- Starter Pack/Rebirth/Daily Rewards/Token Shop/Store/Index), ca sa nu
-- ramana peste cardul deschis.
player:GetAttributeChangedSignal("ShopModalOpen"):Connect(function()
	holder.Visible = not player:GetAttribute("ShopModalOpen")
end)
