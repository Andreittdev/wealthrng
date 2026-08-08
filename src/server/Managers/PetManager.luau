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

-- Imported meshes (Meshy etc.) routinely come in with Anchored = false on
-- some/all of their parts -- MapBuilder.luau already force-anchors its own
-- placed world props for exactly this reason ("Meshy Stadium" etc.), but
-- pet TEMPLATES (only ever read via FindFirstChild here, never touched)
-- never got the same treatment. Left unanchored, gravity slowly pulls the
-- source template itself down through the map every single Play session
-- until it crosses Workspace.FallenPartsDestroyHeight and Roblox destroys
-- it outright -- explains a template working fine for the first N seconds
-- then permanently vanishing (taking every future spawnPet for that
-- assetId down with it) with no warning/error anywhere, since nothing in
-- this codebase ever did the destroying. Anchoring is idempotent, so it's
-- safe to just redo it on every single lookup instead of tracking "have I
-- already fixed this one" separately.
local function anchorTemplate(template: Model)
	for _, descendant in template:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

-- Anchoring only on lookup (findPetTemplate below) isn't enough on its own
-- -- a template nobody has equipped yet keeps falling completely
-- unaddressed, and can cross Workspace.FallenPartsDestroyHeight and get
-- destroyed BEFORE its very first lookup ever happens, taking that Estate's
-- pet down before anyone ever sees it once. This proactively anchors every
-- known pet template ONCE, right when the server starts, so nothing is ever
-- left falling unattended regardless of equip order.
local function anchorAllKnownTemplates()
	local petsFolder = ReplicatedStorage:FindFirstChild("PetModels")
	if petsFolder then
		for _, child in petsFolder:GetChildren() do
			if child:IsA("Model") then
				anchorTemplate(child)
			end
		end
	end

	-- Workspace fallback -- only touches models whose name actually matches
	-- a known Estate/Crate-exclusive Item, so this can't accidentally
	-- anchor an unrelated loose Workspace prop that just happens to be
	-- there for some other reason.
	local knownNames: { [string]: boolean } = {}
	for _, asset in AssetDatabase.GetAllAssets() do
		knownNames[asset.Name] = true
		knownNames[asset.Id] = true
	end
	for _, item in ItemDatabase.GetAllItems() do
		if item.CrateExclusive then
			knownNames[item.Name] = true
			knownNames[item.Id] = true
		end
	end

	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and knownNames[child.Name] then
			anchorTemplate(child)
		end
	end
end

anchorAllKnownTemplates()

-- `source` just needs .Name/.Id -- works for both an AssetDatabase Asset and
-- an ItemDatabase Item, so the same lookup covers equipped Assets AND an
-- equipped Crate-exclusive Estate item.
local function findPetTemplate(source: { Name: string, Id: string }): Model?
	local petsFolder = ReplicatedStorage:FindFirstChild("PetModels")
	if petsFolder then
		local byName = petsFolder:FindFirstChild(source.Name)
		if byName and byName:IsA("Model") then
			anchorTemplate(byName)
			return byName
		end
		local byId = petsFolder:FindFirstChild(source.Id)
		if byId and byId:IsA("Model") then
			anchorTemplate(byId)
			return byId
		end
	end

	local byNameWorkspace = Workspace:FindFirstChild(source.Name)
	if byNameWorkspace and byNameWorkspace:IsA("Model") then
		anchorTemplate(byNameWorkspace)
		return byNameWorkspace
	end
	local byIdWorkspace = Workspace:FindFirstChild(source.Id)
	if byIdWorkspace and byIdWorkspace:IsA("Model") then
		anchorTemplate(byIdWorkspace)
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

-- Each spawnPet call below creates a fresh "PetSlotN" Attachment parented
-- to the CHARACTER'S OWN HumanoidRootPart (not inside the pet model) --
-- clearPets above only destroys the pet models themselves, so those HRP
-- attachments were never actually cleaned up, silently piling up on every
-- single equip/unequip toggle for as long as the character stuck around.
-- Harmless on its own (AlignPosition/AlignOrientation reference the exact
-- new Attachment INSTANCE, not a name lookup, so a stale duplicate can't
-- accidentally get grabbed instead) but still a real leak -- wipe any
-- leftover ones before rebuilding so the count never grows unbounded.
local function clearHrpAttachments(hrp: BasePart)
	for _, child in hrp:GetChildren() do
		if child:IsA("Attachment") and string.match(child.Name, "^PetSlot%d+$") then
			child:Destroy()
		end
	end
end

-- Warns ONCE per missing assetId (not every single equip/respawn, which
-- would otherwise spam the Output every time refreshPets reruns) so it's
-- easy to spot in Studio exactly which Estates/Items still need a model
-- placed/named correctly in ReplicatedStorage.PetModels or Workspace,
-- instead of the pet just silently never showing up with no clue why.
local warnedMissingTemplates: { [string]: boolean } = {}

local function spawnPet(player: Player, character: Model, hrp: BasePart, source: { Name: string, Id: string }, slotIndex: number): boolean
	local template = findPetTemplate(source)
	if not template then
		if not warnedMissingTemplates[source.Id] then
			warnedMissingTemplates[source.Id] = true
			warn(string.format("[PetManager] No pet model found for '%s' (Id: %s) -- expected a Model named '%s' or '%s' in ReplicatedStorage.PetModels or Workspace.", source.Name, source.Id, source.Name, source.Id))
		end
		return false
	end

	local pet = template:Clone()
	pet.Name = "Pet_" .. source.Id

	-- Roblox's per-client content streaming can deprioritize/delay sending
	-- a newly-created instance to weaker or slower-connected clients
	-- (mobile especially) -- matches the reported "sometimes shows on PC,
	-- rarely/never on phone" symptom exactly. Persistent tells the engine
	-- this should always replicate promptly to every client regardless of
	-- distance/priority heuristics, instead of being treated like an
	-- ordinary streamable prop.
	pet.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

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

	-- MaxForce/MaxTorque are math.huge, not a large-but-finite number -- a
	-- big imported mesh (many/large welded parts) can still add up to more
	-- effective weight than a finite force can reliably out-pull, letting
	-- gravity slowly win and sink the pet through the map over time despite
	-- Massless being set on every part. Infinite force/torque means gravity
	-- can never out-compete the constraint regardless of the model's size.
	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Attachment0 = petAttachment
	alignPosition.Attachment1 = hrpAttachment
	alignPosition.MaxForce = math.huge
	alignPosition.Responsiveness = 40
	alignPosition.Parent = anchor

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Attachment0 = petAttachment
	alignOrientation.Attachment1 = hrpAttachment
	alignOrientation.MaxTorque = math.huge
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
	return true
end

-- If an equip/unequip races the character not being fully loaded yet
-- (just joined, mid-respawn, a network hiccup), refreshPets used to just
-- silently give up -- EquippedAssetsChanged/EquippedItemChanged only fire
-- ONCE per change, so a missed attempt meant no pet at all until the next
-- equip toggle or respawn happened to trigger a fresh refresh. Retrying
-- for a bounded window instead closes that gap.
local REFRESH_RETRY_SECONDS = 0.5
local REFRESH_MAX_WAIT_SECONDS = 10

-- Rapidly spamming equip/unequip (e.g. swapping which 2 Estates are
-- equipped, tapped several times fast) used to rebuild the pets from
-- scratch on EVERY single toggle -- a full destroy-then-recreate burst,
-- replicated to every client each time. On a slower/higher-latency
-- connection (reported specifically on phone), that burst of rapid
-- create/destroy replication can arrive out of order or get coalesced
-- wrong client-side, leaving the pet never actually rendered even though
-- the final server state is correct. Debouncing collapses a rapid burst
-- of toggles into a single rebuild once the player actually stops
-- spamming, so at most one create is ever replicated per settled state.
local REFRESH_DEBOUNCE_SECONDS = 0.15

-- Bumped at the START of every refreshPets call (including every toggle in
-- a rapid-fire burst) -- both the debounce delay below and the character/
-- session retry loops check this before acting on their wakeup, so a stale
-- pending call can never fire AFTER a newer one has already taken over,
-- which would otherwise risk overlapping rebuilds stepping on each other's
-- HRP attachments/pet list.
local latestRefreshGeneration: { [Player]: number } = {}

local function doRefreshPets(player: Player, myGeneration: number)
	if latestRefreshGeneration[player] ~= myGeneration then
		return
	end

	local character = player.Character
	local hrp = character and (character:FindFirstChild("HumanoidRootPart") :: BasePart?)
	if not character or not hrp then
		task.spawn(function()
			local waited = 0
			while waited < REFRESH_MAX_WAIT_SECONDS do
				task.wait(REFRESH_RETRY_SECONDS)
				waited += REFRESH_RETRY_SECONDS
				if latestRefreshGeneration[player] ~= myGeneration then
					return
				end
				local retryCharacter = player.Character
				if retryCharacter and retryCharacter:FindFirstChild("HumanoidRootPart") then
					doRefreshPets(player, myGeneration)
					return
				end
			end
		end)
		return
	end

	clearPets(player)
	clearHrpAttachments(hrp)

	-- Same race as the character-not-ready retry above, different cause:
	-- PetManager's own PlayerAdded/CharacterAdded listeners are wired
	-- independently of Main.server.luau's DataManager.Load(player) call, so
	-- the Character can already exist (passing the check above) while this
	-- player's session hasn't finished its own DataStore round-trip yet.
	-- EquippedAssetsChanged/EquippedItemChanged only fire on a CHANGE, not
	-- on initial load, so without a retry here, a player who reconnects
	-- with Estates already equipped from last time would silently get NO
	-- pets at all until they manually re-equip something.
	local session = DataManager.Get(player)
	if not session then
		task.spawn(function()
			local waited = 0
			while waited < REFRESH_MAX_WAIT_SECONDS do
				task.wait(REFRESH_RETRY_SECONDS)
				waited += REFRESH_RETRY_SECONDS
				if latestRefreshGeneration[player] ~= myGeneration then
					return
				end
				if DataManager.Get(player) then
					doRefreshPets(player, myGeneration)
					return
				end
			end
		end)
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

local function refreshPets(player: Player)
	local myGeneration = (latestRefreshGeneration[player] or 0) + 1
	latestRefreshGeneration[player] = myGeneration
	task.delay(REFRESH_DEBOUNCE_SECONDS, doRefreshPets, player, myGeneration)
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
	latestRefreshGeneration[player] = nil
end)

return PetManager
