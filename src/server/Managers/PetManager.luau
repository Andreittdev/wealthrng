-- Floating "pet" cosmetics: whenever a player has an Estate equipped (see
-- AssetManager.luau, up to AssetDatabase.MaxEquipped = 2 at once), a small
-- version of that Estate's real 3D model floats behind/above them and
-- follows wherever they go -- visible to every player, not just the owner
-- (built server-side, parented under the real Character, so it replicates
-- automatically like any other part).
--
-- Model source: tries `ReplicatedStorage.PetModels.<Asset.Name>` /
-- `<Asset.Id>` first (a dedicated folder of TEMPLATES meant to be cloned
-- many times, unlike MapBuilder.luau's singular placed-in-Workspace props),
-- then falls back to a loose `Workspace.<Asset.Name>` / `<Asset.Id>` in
-- case that's where they ended up instead. No fallback beyond that -- an
-- equipped Estate with no matching model just floats nothing, same
-- "silently skip if missing" convention MapBuilder's own placed models use.
--
-- Follow behavior: NOT a weld (rigid, no bob) -- an Attachment on the
-- character's HumanoidRootPart + AlignPosition/AlignOrientation on a
-- dedicated invisible anchor Part inside the cloned pet (every real
-- geometry part WeldConstraint'd rigidly to that one anchor, same "one
-- dedicated anchor part" idiom MapBuilder uses for ProximityPrompts) --
-- lets the HRP-side Attachment's Position be tweened for a gentle bob
-- without fighting a rigid weld.
--
-- Pet size is NOT touched here -- whatever scale the source model already
-- has in Workspace/PetModels is used as-is. An earlier version force-
-- normalized every pet's largest dimension to a fixed TARGET_SIZE_STUDS,
-- which fought against models the source already had manually scaled to
-- look right, making some come out too big/small at equip time. Scale each
-- source model directly in Workspace/PetModels to the size it should
-- appear as a pet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ServerScriptService = game:GetService("ServerScriptService")

local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local DataManager = require(ServerScriptService.Managers.DataManager)
local AssetManager = require(ServerScriptService.Managers.AssetManager)
local InventoryManager = require(ServerScriptService.Managers.InventoryManager)

local PetManager = {}

-- Slot 1 sits left-behind, slot 2 right-behind -- offset from
-- HumanoidRootPart in ITS local space (+Z is behind a character's default
-- facing, +Y is up). Y was 3 (level with/above head) -- lowered to sit
-- around waist height instead. Slot 3 is dedicated to an equipped
-- Crate-exclusive Estate item (session.EquippedItemId, separate from the up-
-- to-2 equipped Assets in slots 1-2) -- centered, a bit further back so it
-- doesn't overlap either Asset slot.
local SLOT_OFFSETS = { Vector3.new(-2, 0.5, 6), Vector3.new(2, 0.5, 6), Vector3.new(0, 0.5, 8) }
local BOB_HEIGHT_STUDS = 1.4
local BOB_SECONDS = 1.8

local activePets: { [Player]: { Model } } = {}

-- `source` just needs .Name/.Id -- works for both an AssetDatabase Asset and
-- an ItemDatabase Item, so the same lookup covers equipped Assets AND an
-- equipped Crate-exclusive Estate item.
local function findPetTemplate(source: { Name: string, Id: string }): Model?
	local petsFolder = ReplicatedStorage:FindFirstChild("PetModels")
	if petsFolder then
		local byName = petsFolder:FindFirstChild(source.Name)
		if byName and byName:IsA("Model") then
			return byName
		end
		local byId = petsFolder:FindFirstChild(source.Id)
		if byId and byId:IsA("Model") then
			return byId
		end
	end

	local byNameWorkspace = Workspace:FindFirstChild(source.Name)
	if byNameWorkspace and byNameWorkspace:IsA("Model") then
		return byNameWorkspace
	end
	local byIdWorkspace = Workspace:FindFirstChild(source.Id)
	if byIdWorkspace and byIdWorkspace:IsA("Model") then
		return byIdWorkspace
	end

	return nil
end

local function clearPets(player: Player)
	local pets = activePets[player]
	if not pets then
		return
	end
	for _, pet in pets do
		pet:Destroy()
	end
	activePets[player] = nil
end

local function spawnPet(player: Player, character: Model, hrp: BasePart, source: { Name: string, Id: string }, slotIndex: number)
	local template = findPetTemplate(source)
	if not template then
		return
	end

	local pet = template:Clone()
	pet.Name = "Pet_" .. source.Id

	-- Anchor at the model's real bounding-box CENTER, not its native pivot
	-- -- an imported mesh's pivot is frequently off-center (often near its
	-- base, sometimes at the import origin), so anchoring at the pivot left
	-- most of the model hanging below the anchor point, reading as "sunk
	-- into the ground" once it's floating at a fixed height behind the
	-- player. Bounding box center floats every model symmetrically around
	-- the anchor regardless of where its source pivot happened to be.
	--
	-- Anchor rotation is IDENTITY, not the pivot's rotation -- baking the
	-- pivot's rotation in here got welded into the geometry's captured
	-- offset, so any model whose pivot didn't already face the same way as
	-- its own visible geometry (Beachfront Villa did this) ended up
	-- spinning to face backwards once AlignOrientation took over. Identity
	-- keeps each model in its own natural/as-placed orientation, so
	-- AlignOrientation rotating the anchor to match the player's facing
	-- rotates the model exactly as much and no more.
	--
	-- Must run BEFORE PrimaryPart is set below -- GetBoundingBox orients
	-- itself off PrimaryPart if one is already assigned.
	local boundingCFrame = pet:GetBoundingBox()

	-- One dedicated invisible anchor part -- every real geometry part gets
	-- rigidly WeldConstraint'd to it, and it alone is what the
	-- AlignPosition/AlignOrientation constraints below actually drive.
	local anchor = Instance.new("Part")
	anchor.Name = "PetAnchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.Massless = true
	anchor.CFrame = CFrame.new(boundingCFrame.Position)
	anchor.Parent = pet
	pet.PrimaryPart = anchor

	for _, descendant in pet:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= anchor then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = anchor
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end

	local baseOffset = SLOT_OFFSETS[slotIndex] or SLOT_OFFSETS[#SLOT_OFFSETS]

	local hrpAttachment = Instance.new("Attachment")
	hrpAttachment.Name = "PetSlot" .. slotIndex
	hrpAttachment.Position = baseOffset
	hrpAttachment.Parent = hrp

	local petAttachment = Instance.new("Attachment")
	petAttachment.Parent = anchor

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Attachment0 = petAttachment
	alignPosition.Attachment1 = hrpAttachment
	alignPosition.MaxForce = 100000
	alignPosition.Responsiveness = 40
	alignPosition.Parent = anchor

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Attachment0 = petAttachment
	alignOrientation.Attachment1 = hrpAttachment
	alignOrientation.MaxTorque = 100000
	alignOrientation.Responsiveness = 20
	alignOrientation.Parent = anchor

	-- Gentle up/down float -- tweens the HRP-side attachment's own offset
	-- (not the pet directly), so AlignPosition just smoothly chases it.
	TweenService:Create(
		hrpAttachment,
		TweenInfo.new(BOB_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = baseOffset + Vector3.new(0, BOB_HEIGHT_STUDS, 0) }
	):Play()

	pet.Parent = character

	local pets = activePets[player]
	if not pets then
		pets = {}
		activePets[player] = pets
	end
	table.insert(pets, pet)
end

local function refreshPets(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	clearPets(player)

	local session = DataManager.Get(player)
	if not session then
		return
	end

	for slotIndex, assetId in session.EquippedAssets do
		local asset = AssetDatabase.GetAsset(assetId)
		if asset then
			spawnPet(player, character, hrp, asset, slotIndex)
		end
	end

	-- Slot 3 -- an equipped Crate-exclusive Estate item (session.
	-- EquippedItemId, from InventoryManager, separate from the up-to-2
	-- equipped Assets above). Only Crate-exclusive items get a pet -- a
	-- regular rolled item (watch, sneakers, etc.) isn't an Estate and was
	-- never meant to float a model behind the player.
	if session.EquippedItemId then
		local item = ItemDatabase.GetItem(session.EquippedItemId)
		if item and item.CrateExclusive then
			spawnPet(player, character, hrp, item, 3)
		end
	end
end

AssetManager.EquippedAssetsChanged.Event:Connect(refreshPets)
InventoryManager.EquippedItemChanged.Event:Connect(refreshPets)

local function onCharacterAdded(player: Player, character: Model)
	character:WaitForChild("HumanoidRootPart", 10)
	refreshPets(player)
end

Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end)
for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

Players.PlayerRemoving:Connect(function(player: Player)
	activePets[player] = nil
end)

return PetManager
