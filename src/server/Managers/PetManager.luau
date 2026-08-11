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
--
-- Endless Mode placed buildings (see createPlacedBuildingModel below) are a
-- SEPARATE, independent system from the above -- once planted, a building is
-- a standalone Workspace object with its own lifecycle (destroyed only on
-- pickup or mob-kill), not tied to the character-follow pet's
-- destroy-and-rebuild-on-every-equip-change cycle. Multiple copies of the
-- SAME Estate can be placed simultaneously (up to per-type/total caps, see
-- MAX_TOTAL_PLACED etc.), so placements are keyed by a generated placementId,
-- not by AssetId.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local EndlessModeConfig = require(ReplicatedStorage.Modules.EndlessModeConfig)
local EndlessModeBuildingConfig = require(ReplicatedStorage.Modules.EndlessModeBuildingConfig)
local EndlessModeUnitRoleConfig = require(ReplicatedStorage.Modules.EndlessModeUnitRoleConfig)
local WaveConfig = require(ReplicatedStorage.Modules.WaveConfig)
local DataManager = require(ServerScriptService.Managers.DataManager)
local AssetManager = require(ServerScriptService.Managers.AssetManager)
local InventoryManager = require(ServerScriptService.Managers.InventoryManager)
local EndlessModeClaimManager = require(ServerScriptService.Managers.EndlessModeClaimManager)
local EndlessModeMobRegistry = require(ServerScriptService.Managers.EndlessModeMobRegistry)
local EndlessModeAllyManager = require(ServerScriptService.Managers.EndlessModeAllyManager)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)

local placeEndlessModeEstate = RemotesBootstrap:WaitForChild("PlaceEndlessModeEstate")
local endlessModeHeldEstateUpdated = RemotesBootstrap:WaitForChild("EndlessModeHeldEstateUpdated")
local endlessModeBuildingSelected = RemotesBootstrap:WaitForChild("EndlessModeBuildingSelected")
local upgradeEndlessModeBuilding = RemotesBootstrap:WaitForChild("UpgradeEndlessModeBuilding")
local pickUpEndlessModeBuilding = RemotesBootstrap:WaitForChild("PickUpEndlessModeBuilding")
local endlessModeCashUpdated = RemotesBootstrap:WaitForChild("EndlessModeCashUpdated")
local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")

local PetManager = {}

type PlacedBuilding = {
	AssetId: string,
	CFrame: CFrame,
	UpgradeLevel: number,
	HP: number,
	Model: Model,
	HpLabel: TextLabel,
	-- "col,row" (EndlessModeClaimManager.SnapToPatchCell) -- which grid tile
	-- of the checkerboard patch this building occupies, so a second
	-- placement can't land on the same tile.
	CellKey: string,
}

-- Per-player, per-placementId placed building -- keyed by a generated GUID,
-- NOT by AssetId, since several copies of the SAME Estate can now be placed
-- at once (see MAX_TOTAL_PLACED/MAX_COPIES_PER_ASSET_TYPE below). In-memory
-- only, same as the rest of Endless Mode's state (EndlessModeClaimManager.
-- luau etc.) -- cleared (and every Model destroyed) on disconnect, not
-- persisted.
local placedBuildings: { [Player]: { [string]: PlacedBuilding } } = {}

-- Which of a player's OWN placed buildings currently has the right-side HP/
-- upgrade panel open client-side (EndlessModeBuildingPanel.luau) -- at most
-- one at a time, per explicit "only while that specific Estate is just-
-- placed/selected" request. Nil means no panel is open. Keyed by placementId
-- (a specific instance), not AssetId, for the same reason as above.
local selectedPlacementId: { [Player]: string? } = {}

-- Forward-declared (assigned further down, past doRefreshPets) -- the
-- placement/upgrade/pickup remote handlers need to call this, but are
-- defined textually earlier in the file than the real definition, so a
-- plain `local function refreshPets` down there would capture an unrelated
-- global instead of this upvalue.
local refreshPets: (Player) -> ()

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
-- Applied to a PLACED Estate -- was 2.5 (bigger than the Hub's floating-pet
-- scale), dropped to natural/unscaled per explicit "very big and looks
-- damaged" feedback on the matching client-side ghost preview.
local ENDLESS_MODE_PET_SCALE = 1
-- Applied while HELD in hand instead -- small, not the full placed-building
-- scale, per explicit feedback.
local ENDLESS_MODE_HELD_SCALE = 0.8
-- Local offset from HumanoidRootPart (local -Z is always "forward" for a
-- character) the held model sits at -- in front of the chest, per explicit
-- request, not tied to the actual hand bone's pose.
local HAND_GRIP_OFFSET = CFrame.new(0, 0, -2.5)

-- Placement caps, per explicit request -- 20 across everything a player has
-- planted, 5 copies max of any one ordinary Estate type, but only 3 for the
-- rarer Exclusive/Leaderboards tier (Top1Estate/Top2Estate/Top3Estate,
-- OldFarm, Supermarket, SolarPark, ConstructionShop -- see AssetDatabase's
-- Rarity field). Ordinary purchasable Estates (Common..Godly) and
-- Crate-exclusive ItemDatabase Estates both get the normal 5-copy cap.
local MAX_TOTAL_PLACED = 20
local MAX_COPIES_PER_ASSET_TYPE = 5
local MAX_COPIES_PER_RARE_ASSET_TYPE = 3

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

-- `assetId` alone is all a placed building's own data carries for identity
-- -- looks it back up against both databases the same way doRefreshPets'
-- equipped-slots loop does, so templates/names can be resolved from either.
local function findSourceById(assetId: string): { Name: string, Id: string }?
	local asset = AssetDatabase.GetAsset(assetId)
	if asset then
		return asset
	end
	local item = ItemDatabase.GetItem(assetId)
	if item and item.CrateExclusive then
		return item
	end
	return nil
end

-- Exclusive/Leaderboards-tier Estates (see AssetDatabase's Rarity field
-- comment) get the tighter 3-copy cap -- Crate-exclusive ItemDatabase
-- "Estates" don't carry an equivalent field (different database), so they
-- fall through to the ordinary 5-copy cap.
local function maxCopiesForAsset(assetId: string): number
	local asset = AssetDatabase.GetAsset(assetId)
	if asset and (asset.Rarity == "Exclusive" or asset.Rarity == "Leaderboards") then
		return MAX_COPIES_PER_RARE_ASSET_TYPE
	end
	return MAX_COPIES_PER_ASSET_TYPE
end

local function countPlaced(player: Player, assetId: string): (number, number)
	local playerPlaced = placedBuildings[player]
	if not playerPlaced then
		return 0, 0
	end
	local total = 0
	local ofType = 0
	for _, building in playerPlaced do
		total += 1
		if building.AssetId == assetId then
			ofType += 1
		end
	end
	return total, ofType
end

-- Whether ANOTHER copy of this Estate can still be placed -- both the
-- overall 20-total cap and the per-type cap (5, or 3 for Exclusive/
-- Leaderboards) have to allow it.
local function canPlaceMore(player: Player, assetId: string): boolean
	local total, ofType = countPlaced(player, assetId)
	if total >= MAX_TOTAL_PLACED then
		return false
	end
	return ofType < maxCopiesForAsset(assetId)
end

-- EndlessModeBuildingConfig's Base+per-upgrade formula is the SAME for every
-- building regardless of type -- Tank-role Estates get an extra multiplier
-- on top (EndlessModeUnitRoleConfig.GetTankHPMultiplier, 1 for anything
-- that isn't a Tank), scaled by how hard that specific Estate is to obtain.
-- math.floor keeps HP a clean integer even where the multiplier doesn't
-- divide evenly.
local function getEffectiveMaxHP(assetId: string, upgradeLevel: number): number
	local baseMaxHP = EndlessModeBuildingConfig.GetMaxHP(upgradeLevel)
	return math.floor(baseMaxHP * EndlessModeUnitRoleConfig.GetTankHPMultiplier(assetId))
end

-- Nil if that placementId isn't actually placed for this player anymore
-- (picked up, unequipped, destroyed by mobs, etc.) -- callers treat that as
-- "close the panel".
local function buildSelectionPayload(player: Player, placementId: string)
	local playerPlaced = placedBuildings[player]
	local building = playerPlaced and playerPlaced[placementId]
	if not building then
		return nil
	end

	local source = findSourceById(building.AssetId)

	return {
		PlacementId = placementId,
		AssetId = building.AssetId,
		Name = (source and source.Name) or building.AssetId,
		HP = building.HP,
		MaxHP = getEffectiveMaxHP(building.AssetId, building.UpgradeLevel),
		UpgradeLevel = building.UpgradeLevel,
		UpgradeCost = EndlessModeBuildingConfig.GetUpgradeCost(building.UpgradeLevel),
	}
end

-- Dedicated Workspace folder for placed buildings -- separate from the
-- character-bound pets in activePets, since these are standalone, fixed-
-- position objects with their own lifecycle (destroyed only on pickup or
-- mob-kill), not rebuilt every time doRefreshPets runs for unrelated
-- equip-change reasons.
local function getPlacedBuildingsFolder(): Folder
	local mapFolder = Workspace:FindFirstChild("Map")
	local parent: Instance = mapFolder or Workspace
	local folder = parent:FindFirstChild("EndlessModePlacedBuildings")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "EndlessModePlacedBuildings"
		folder.Parent = parent
	end
	return folder :: Folder
end

local warnedMissingTemplates: { [string]: boolean } = {}

-- Builds the actual standalone Workspace model for ONE placed building
-- instance. Returns (model, hpLabel), or nil if there's no matching pet
-- template (same "silently skip if missing" convention as everything else
-- in this file).
local function createPlacedBuildingModel(player: Player, placementId: string, assetId: string, cframe: CFrame, upgradeLevel: number, hp: number): (Model?, TextLabel?)
	local source = findSourceById(assetId)
	if not source then
		return nil, nil
	end

	local template = findPetTemplate(source)
	if not template then
		if not warnedMissingTemplates[assetId] then
			warnedMissingTemplates[assetId] = true
			warn(string.format("[PetManager] No pet model found for '%s' (Id: %s) -- expected a Model named '%s' or '%s' in ReplicatedStorage.PetModels or Workspace.", source.Name, source.Id, source.Name, source.Id))
		end
		return nil, nil
	end

	-- Read BEFORE cloning -- `template` is the permanent, already-settled
	-- instance living in ReplicatedStorage.PetModels, unlike the clone,
	-- which (same class of bug as the GetBoundingBox saga elsewhere in this
	-- file) can't be trusted to report its own properties correctly right
	-- after being created/reparented.
	local templateScale = template:GetScale()

	local pet = template:Clone()
	pet.Name = "PlacedEstate_" .. assetId
	pet.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	-- Parented BEFORE ScaleTo/GetBoundingBox below, not after -- calling
	-- either on a clone that isn't in the DataModel yet produced wildly
	-- inconsistent results, see the header comment / git history for the
	-- full saga.
	pet.Parent = getPlacedBuildingsFolder()

	-- Relative to the TEMPLATE's own already-authored Scale, not an absolute
	-- reset to ENDLESS_MODE_PET_SCALE -- a flat ScaleTo(1) here undid any
	-- manual downsizing done on the source template in Studio (e.g. Sol
	-- Stadium scaled to 0.1 there), snapping it back to full native size
	-- every time it got placed, even though the SAME template floated at the
	-- correct (already-scaled) size in the Hub, where nothing calls ScaleTo
	-- at all. Also folds in GetScaleMultiplier(upgradeLevel) -- a freshly
	-- placed (level 0) Estate starts small and grows with each upgrade, per
	-- explicit request; upgradeEndlessModeBuilding's handler re-scales this
	-- same Model again later as the level climbs (see rescalePlacedBuilding).
	pet:ScaleTo(templateScale * ENDLESS_MODE_PET_SCALE * EndlessModeBuildingConfig.GetScaleMultiplier(upgradeLevel))

	-- Anchor at the model's real bounding-box CENTER, not its native pivot
	-- -- an imported mesh's pivot is frequently off-center, so anchoring at
	-- the pivot instead left the model reading as sunk/floating wrong.
	-- Bounding box center is symmetric regardless of where the source
	-- pivot happened to be. Must run BEFORE PrimaryPart is set below --
	-- GetBoundingBox orients itself off PrimaryPart if one is already
	-- assigned.
	local boundingCFrame, boundingSize = pet:GetBoundingBox()

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

	-- Model:PivotTo (not a direct anchor.CFrame set) -- setting only the
	-- anchor part's CFrame and relying on its WeldConstraints to drag the
	-- rest of the (still-unanchored) descendants along proved unreliable in
	-- testing (the anchor would snap back to the template's native authored
	-- position moments after being set correctly). PivotTo moves every
	-- descendant by the same rigid delta in one synchronous script-level
	-- operation -- nothing left to race.
	pet:PivotTo(cframe + Vector3.new(0, boundingSize.Y / 2, 0))
	anchor.Anchored = true

	-- Floating "N/MAX HP" label -- same idiom as EndlessModeClaimManager's
	-- base HP display, StudsOffset instead of a dedicated anchor part since
	-- `anchor` already sits at the right X/Z, just needs lifting above the
	-- roofline.
	local hpBillboard = Instance.new("BillboardGui")
	hpBillboard.Name = "HPDisplay"
	hpBillboard.Size = UDim2.new(0, 120, 0, 28)
	hpBillboard.StudsOffset = Vector3.new(0, boundingSize.Y / 2 + 2, 0)
	hpBillboard.AlwaysOnTop = true
	hpBillboard.Adornee = anchor
	hpBillboard.Parent = anchor

	local hpLabel = Instance.new("TextLabel")
	hpLabel.Size = UDim2.new(1, 0, 1, 0)
	hpLabel.BackgroundTransparency = 1
	hpLabel.Font = Enum.Font.LuckiestGuy
	hpLabel.Text = string.format("%d/%d HP", hp, getEffectiveMaxHP(assetId, upgradeLevel))
	hpLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
	hpLabel.TextStrokeTransparency = 0
	hpLabel.TextStrokeColor3 = Color3.fromRGB(10, 10, 10)
	hpLabel.TextScaled = true
	hpLabel.Parent = hpBillboard

	-- Clicking a placed building toggles the right-side HP/upgrade panel
	-- (EndlessModeBuildingPanel.luau) instead of picking it up directly --
	-- the panel has its own "Pick Up" button now that a bare click can't do
	-- both select AND pick up unambiguously.
	for _, descendant in pet:GetDescendants() do
		if descendant:IsA("BasePart") then
			local clickDetector = Instance.new("ClickDetector")
			clickDetector.MaxActivationDistance = 25
			clickDetector.Parent = descendant
			clickDetector.MouseClick:Connect(function(clickingPlayer: Player)
				if clickingPlayer ~= player then
					return
				end
				local playerPlaced = placedBuildings[player]
				if not playerPlaced or not playerPlaced[placementId] then
					return
				end
				if selectedPlacementId[player] == placementId then
					selectedPlacementId[player] = nil
					endlessModeBuildingSelected:FireClient(player, nil)
				else
					selectedPlacementId[player] = placementId
					endlessModeBuildingSelected:FireClient(player, buildSelectionPayload(player, placementId))
				end
			end)
		end
	end

	return pet, hpLabel
end

-- Re-scales an ALREADY-PLACED building's Model in place (not a fresh clone)
-- after its UpgradeLevel changes -- EndlessModeBuildingConfig.
-- GetScaleMultiplier grows with level, so a building visibly gets bigger as
-- it's upgraded instead of only its HP number changing. Re-derives the
-- template's own Scale the same way createPlacedBuildingModel did (no need
-- to have stored it separately) -- re-pivots afterward too, since a bigger
-- bounding box shifts the ground-offset (anchor sits at bounding-box
-- CENTER, not bottom), and nudges the floating HP billboard's StudsOffset up
-- to match the new roofline.
local function rescalePlacedBuilding(building: PlacedBuilding)
	local model = building.Model
	if not model or not model.Parent then
		return
	end

	local source = findSourceById(building.AssetId)
	local template = source and findPetTemplate(source)
	if not template then
		return
	end

	local templateScale = template:GetScale()
	model:ScaleTo(templateScale * ENDLESS_MODE_PET_SCALE * EndlessModeBuildingConfig.GetScaleMultiplier(building.UpgradeLevel))

	local _, boundingSize = model:GetBoundingBox()
	model:PivotTo(building.CFrame + Vector3.new(0, boundingSize.Y / 2, 0))

	local billboard = building.HpLabel and building.HpLabel.Parent
	if billboard and billboard:IsA("BillboardGui") then
		billboard.StudsOffset = Vector3.new(0, boundingSize.Y / 2 + 2, 0)
	end
end

-- Held-in-hand (Endless Mode, still room to place more) or floating (Hub)
-- pet for an EQUIPPED asset slot. Returns (success, isHeldInHand) -- the 2nd
-- value is only meaningful when true, used by doRefreshPets below to figure
-- out which equipped Estate (if any) should be reported as "held" for the
-- client's placement preview. Placed copies are entirely separate objects
-- now (see createPlacedBuildingModel above) -- this function never renders
-- one.
local function spawnEquippedPet(player: Player, character: Model, hrp: BasePart, source: { Name: string, Id: string }, slotIndex: number): (boolean, boolean)
	local template = findPetTemplate(source)
	if not template then
		if not warnedMissingTemplates[source.Id] then
			warnedMissingTemplates[source.Id] = true
			warn(string.format("[PetManager] No pet model found for '%s' (Id: %s) -- expected a Model named '%s' or '%s' in ReplicatedStorage.PetModels or Workspace.", source.Name, source.Id, source.Name, source.Id))
		end
		return false, false
	end

	local inEndlessMode = EndlessModeConfig.IsCharacterInEndlessMode(character)
	local heldInHand = inEndlessMode and canPlaceMore(player, source.Id)

	if inEndlessMode and not heldInHand then
		-- Equipped and in Endless Mode, but already at this type's (or the
		-- overall) placement cap -- nothing left to hold/place, so no pet
		-- renders for this slot at all. The Estate's other effects (income
		-- etc.) still apply from simply being equipped.
		return true, false
	end

	-- Read BEFORE cloning -- see createPlacedBuildingModel's identical
	-- comment for why the clone itself can't be trusted here.
	local templateScale = template:GetScale()

	local pet = template:Clone()
	pet.Name = "Pet_" .. source.Id
	pet.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	pet.Parent = character

	if heldInHand then
		-- Relative to the template's own Scale, same fix as
		-- createPlacedBuildingModel's -- an absolute ScaleTo would reset any
		-- manual downsizing done on the source template in Studio.
		pet:ScaleTo(templateScale * ENDLESS_MODE_HELD_SCALE)
	end

	local boundingCFrame = pet:GetBoundingBox()

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

	if heldInHand then
		-- Held "in hand" reads here as "in front of the character", not a
		-- literal grab of the hand bone -- per explicit request, it should
		-- show in front even if the actual hand isn't posed out front.
		-- HumanoidRootPart's axes are predictable (local -Z is always
		-- "forward"), unlike a hand bone's, so this welds to HRP instead --
		-- also stable/non-wobbly for free.
		local motor = Instance.new("Motor6D")
		motor.Name = "PetHandGrip"
		motor.Part0 = hrp
		motor.Part1 = anchor
		motor.C0 = HAND_GRIP_OFFSET
		motor.Parent = hrp
	else
		-- Floating (hub) -- unchanged from the original behavior.
		local baseOffset = SLOT_OFFSETS[slotIndex] or SLOT_OFFSETS[#SLOT_OFFSETS]

		local hrpAttachment = Instance.new("Attachment")
		hrpAttachment.Name = "PetSlot" .. slotIndex
		hrpAttachment.Position = baseOffset
		hrpAttachment.Parent = hrp

		local petAttachment = Instance.new("Attachment")
		petAttachment.Parent = anchor

		-- MaxForce/MaxTorque are math.huge, not a large-but-finite number --
		-- a big imported mesh (many/large welded parts) can still add up to
		-- more effective weight than a finite force can reliably out-pull,
		-- letting gravity slowly win and sink the pet through the map over
		-- time despite Massless being set on every part.
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

		-- Gentle up/down float -- tweens the HRP-side attachment's own
		-- offset (not the pet directly), so AlignPosition just smoothly
		-- chases it.
		TweenService:Create(
			hrpAttachment,
			TweenInfo.new(BOB_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = baseOffset + Vector3.new(0, BOB_HEIGHT_STUDS, 0) }
		):Play()
	end

	local pets = activePets[player]
	if not pets then
		pets = {}
		activePets[player] = pets
	end
	table.insert(pets, pet)
	return true, heldInHand
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

-- Each spawnEquippedPet call above creates a fresh "PetSlotN" Attachment
-- parented to the CHARACTER'S OWN HumanoidRootPart (not inside the pet
-- model) -- clearPets above only destroys the pet models themselves, so
-- those HRP attachments were never actually cleaned up, silently piling up
-- on every single equip/unequip toggle for as long as the character stuck
-- around. Harmless on its own (AlignPosition/AlignOrientation reference the
-- exact new Attachment INSTANCE, not a name lookup) but still a real leak --
-- wipe any leftover ones before rebuilding so the count never grows
-- unbounded.
local function clearHrpAttachments(hrp: BasePart)
	for _, child in hrp:GetChildren() do
		if child:IsA("Attachment") and string.match(child.Name, "^PetSlot%d+$") then
			child:Destroy()
		end
	end
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

-- NOTE: only rebuilds the held-in-hand/floating pets (spawnEquippedPet) --
-- placed buildings are standalone objects (createPlacedBuildingModel) with
-- their own independent lifecycle and are never touched here.
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

	-- Whichever equipped Estate can still be planted (under its cap) is
	-- reported to the client as "this is what you're holding, show the
	-- placement preview" -- if more than one is somehow holdable at once
	-- (MaxEquipped is 2), the LAST one wins, simplest reasonable default
	-- since only one placement preview can sensibly show at a time.
	local heldAssetId: string? = nil

	for slotIndex, assetId in session.EquippedAssets do
		local asset = AssetDatabase.GetAsset(assetId)
		if asset then
			local _, heldInHand = spawnEquippedPet(player, character, hrp, asset, slotIndex)
			if heldInHand then
				heldAssetId = assetId
			end
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
			local _, heldInHand = spawnEquippedPet(player, character, hrp, item, 3)
			if heldInHand then
				heldAssetId = session.EquippedItemId
			end
		end
	end

	-- If the currently-selected (panel-open) building stopped being both
	-- placed and (physically) in Endless Mode, close the stale panel --
	-- placed buildings persist regardless of equip state now, so only those
	-- two things matter (unequipping the type no longer affects it).
	local selectedId = selectedPlacementId[player]
	if selectedId then
		local stillInEndlessMode = EndlessModeConfig.IsCharacterInEndlessMode(character)
		local stillPlaced = placedBuildings[player] and placedBuildings[player][selectedId]
		if not stillInEndlessMode or not stillPlaced then
			selectedPlacementId[player] = nil
			endlessModeBuildingSelected:FireClient(player, nil)
		end
	end

	endlessModeHeldEstateUpdated:FireClient(player, heldAssetId)
end

refreshPets = function(player: Player)
	local myGeneration = (latestRefreshGeneration[player] or 0) + 1
	latestRefreshGeneration[player] = myGeneration
	task.delay(REFRESH_DEBOUNCE_SECONDS, doRefreshPets, player, myGeneration)
end

-- Exposed so PortalManager.luau can force a rebuild on the Endless Mode ->
-- Hub trip -- nothing else changes EquippedAssets on that crossing, so
-- without this an Estate equipped (and welded to the hand) while in Endless
-- Mode would stay rigidly stuck there instead of switching back to floating
-- once back in the hub.
PetManager.Refresh = refreshPets

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

	local playerPlaced = placedBuildings[player]
	if playerPlaced then
		for _, building in playerPlaced do
			if building.Model then
				building.Model:Destroy()
			end
		end
	end
	placedBuildings[player] = nil
	selectedPlacementId[player] = nil
end)

-- Right only for now -- matches EndlessModeClaimManager/EndlessModeMobManager's
-- own "Right only" scope.
local PLACEABLE_SIDE = "Right"

-- Current mob damage for `player` -- scales with their own wave progress
-- (WaveConfig.GetWaveForElapsedSeconds off session.EndlessModeElapsedSeconds),
-- same idiom EndlessModeMobManager.luau's own getMobDamage uses. Needed here
-- just to hand off to a Spawner's Ally (EndlessModeAllyManager.SpawnAlly) so
-- it knows how hard the mob it ends up fighting will hit back.
local function getMobDamage(player: Player): number
	local session = DataManager.Get(player)
	local wave = session and WaveConfig.GetWaveForElapsedSeconds(session.EndlessModeElapsedSeconds) or 1
	return EndlessModeUnitRoleConfig.GetMobDamageForWave(wave)
end

-- Started once, right after a Damage-role building is placed -- ticks for as
-- long as `placementId` stays in placedBuildings (checked fresh every tick,
-- no separate "still alive" flag needed), attacking whichever mob is nearest
-- within range. Stops itself the instant the building is picked up,
-- destroyed by mobs, or the player disconnects (all three just remove the
-- placedBuildings entry).
local function startDamageLoop(player: Player, placementId: string)
	task.spawn(function()
		while true do
			task.wait(EndlessModeUnitRoleConfig.DamageTickSeconds)
			local playerPlaced = placedBuildings[player]
			local building = playerPlaced and playerPlaced[placementId]
			if not building then
				return
			end
			local range = EndlessModeUnitRoleConfig.DamageRangeStuds * EndlessModeUnitRoleConfig.GetDamageRangeMultiplier(building.AssetId)
			local mob = EndlessModeMobRegistry.GetNearestAliveMob(building.CFrame.Position, range)
			if mob then
				local amount = EndlessModeUnitRoleConfig.DamageAmount * EndlessModeUnitRoleConfig.GetDamageAmountMultiplier(building.AssetId)
				EndlessModeMobRegistry.Damage(mob, amount)
			end
		end
	end)
end

-- Same lifetime idiom as startDamageLoop above, but for Spawner-role
-- buildings -- periodically hands off to EndlessModeAllyManager to actually
-- create and run the ally.
local function startSpawnerLoop(player: Player, placementId: string)
	task.spawn(function()
		while true do
			task.wait(EndlessModeUnitRoleConfig.SpawnerIntervalSeconds)
			local playerPlaced = placedBuildings[player]
			local building = playerPlaced and playerPlaced[placementId]
			if not building then
				return
			end
			EndlessModeAllyManager.SpawnAlly(building.CFrame.Position, getMobDamage(player))
		end
	end)
end

-- Client fires this after raycasting the ground under its own mouse/touch --
-- server still re-validates ownership, Endless Mode presence, the placement
-- caps, and clamps the position onto the actual claimed brown patch (not
-- just "anywhere on the ground") before trusting it.
placeEndlessModeEstate.OnServerEvent:Connect(function(player: Player, assetId: string, position: Vector3)
	if typeof(assetId) ~= "string" or typeof(position) ~= "Vector3" then
		return
	end

	local character = player.Character
	if not EndlessModeConfig.IsCharacterInEndlessMode(character) then
		return
	end

	local session = DataManager.Get(player)
	if not session then
		return
	end

	local isEquipped = table.find(session.EquippedAssets, assetId) ~= nil or session.EquippedItemId == assetId
	if not isEquipped then
		return
	end

	if not canPlaceMore(player, assetId) then
		systemMessage:FireClient(player, "You've reached the placement limit for this Estate!")
		return
	end

	-- Snaps to the checkerboard patch's own grid (EndlessModeClaimManager.
	-- spawnPatch's tiles) instead of free-form placement -- per explicit
	-- request, so Estates land in tidy invisible slots instead of
	-- overlapping/scattered wherever the player happened to click.
	local snappedPosition, cellKey = EndlessModeClaimManager.SnapToPatchCell(PLACEABLE_SIDE, position)
	if not snappedPosition or not cellKey then
		return
	end

	local playerPlaced = placedBuildings[player]
	if playerPlaced then
		for _, existingBuilding in playerPlaced do
			if existingBuilding.CellKey == cellKey then
				systemMessage:FireClient(player, "That spot is already taken!")
				return
			end
		end
	end

	local clampedPosition = Vector3.new(snappedPosition.X, EndlessModeConfig.GroundOrigin.Y, snappedPosition.Z)
	local cframe = CFrame.new(clampedPosition)

	local placementId = HttpService:GenerateGUID(false)
	local initialMaxHP = getEffectiveMaxHP(assetId, 0)
	local model, hpLabel = createPlacedBuildingModel(player, placementId, assetId, cframe, 0, initialMaxHP)
	if not model or not hpLabel then
		return
	end

	if not playerPlaced then
		playerPlaced = {}
		placedBuildings[player] = playerPlaced
	end
	playerPlaced[placementId] = {
		AssetId = assetId,
		CFrame = cframe,
		UpgradeLevel = 0,
		HP = initialMaxHP,
		Model = model,
		HpLabel = hpLabel,
		CellKey = cellKey,
	}

	-- Opens the HP/upgrade panel immediately on placement, per explicit
	-- "only while that specific Estate is just-placed/selected" request.
	selectedPlacementId[player] = placementId
	endlessModeBuildingSelected:FireClient(player, buildSelectionPayload(player, placementId))

	-- Combat role (EndlessModeUnitRoleConfig) -- Tank doesn't need anything
	-- started here, it's purely reactive (EndlessModeMobManager.luau checks
	-- the role when a mob ARRIVES). Damage/Spawner are active instead, so
	-- they get their own ticking loop for as long as this placement exists.
	local role = EndlessModeUnitRoleConfig.GetRole(assetId)
	if role == "Damage" then
		startDamageLoop(player, placementId)
	elseif role == "Spawner" then
		startSpawnerLoop(player, placementId)
	end

	-- Re-evaluates the held-in-hand preview -- this placement may have just
	-- hit the per-type/total cap, in which case the held pet/ghost needs to
	-- disappear now that no more can be planted.
	refreshPets(player)
end)

-- Buys the next upgrade level (more max HP) for whichever placed building is
-- currently selected -- selection is re-validated server-side (not just
-- trusted from the client's last-known panel state) so a stale/foreign
-- placementId can't be upgraded by replaying an old FireServer call.
upgradeEndlessModeBuilding.OnServerEvent:Connect(function(player: Player, placementId: string)
	if typeof(placementId) ~= "string" then
		return
	end
	if not EndlessModeConfig.IsCharacterInEndlessMode(player.Character) then
		return
	end
	if selectedPlacementId[player] ~= placementId then
		return
	end

	local playerPlaced = placedBuildings[player]
	local building = playerPlaced and playerPlaced[placementId]
	if not building then
		return
	end

	local cost = EndlessModeBuildingConfig.GetUpgradeCost(building.UpgradeLevel)
	if not cost then
		return
	end

	local session = DataManager.Get(player)
	if not session then
		return
	end
	-- Paid from EndlessModeCash (earned in Endless Mode), not the Hub's own
	-- Cash -- per explicit request, upgrades are entirely funded by the
	-- separate Endless Mode economy.
	if session.EndlessModeCash < cost then
		systemMessage:FireClient(player, "You don't have enough Endless Cash!")
		return
	end

	session.EndlessModeCash -= cost
	endlessModeCashUpdated:FireClient(player, session.EndlessModeCash)
	building.UpgradeLevel += 1
	-- Also fully heals -- paying to upgrade a building that's currently
	-- half-dead from mob damage and getting LESS max HP than before it
	-- healed would feel bad, so an upgrade always tops it back up to its
	-- new (higher) max.
	building.HP = getEffectiveMaxHP(building.AssetId, building.UpgradeLevel)

	if building.HpLabel then
		building.HpLabel.Text = string.format("%d/%d HP", building.HP, building.HP)
	end

	-- Grows the actual Model too, per explicit request -- starts small at
	-- level 0, gets visibly bigger with each upgrade.
	rescalePlacedBuilding(building)

	endlessModeBuildingSelected:FireClient(player, buildSelectionPayload(player, placementId))
end)

-- The panel's "Pick Up" button -- destroys this specific placed instance and
-- frees up a placement-cap slot. Doesn't put it back in a special "held"
-- state of its own -- with multiple copies allowed now, "held" just means
-- "this equipped type has room for one more", so the existing held preview
-- (or a freshly-reappearing one, via refreshPets below) covers replanting.
pickUpEndlessModeBuilding.OnServerEvent:Connect(function(player: Player, placementId: string)
	if typeof(placementId) ~= "string" then
		return
	end
	if not EndlessModeConfig.IsCharacterInEndlessMode(player.Character) then
		return
	end
	if selectedPlacementId[player] ~= placementId then
		return
	end

	local playerPlaced = placedBuildings[player]
	local building = playerPlaced and playerPlaced[placementId]
	if not building then
		return
	end

	if building.Model then
		building.Model:Destroy()
	end
	playerPlaced[placementId] = nil
	selectedPlacementId[player] = nil
	endlessModeBuildingSelected:FireClient(player, nil)

	refreshPets(player)
end)

-- Lets EndlessModeMobManager.luau find live targets for a claimed side's
-- owner -- mobs attack placed Estates before the main base, per explicit
-- request, only falling back to the base once none are left standing.
-- AssetId is included so the mob manager can look up EndlessModeUnitRoleConfig
-- .GetRole(AssetId) and decide whether arriving there means "Tank -- block
-- and melee" or "deal one hit and despawn" like before.
function PetManager.GetAlivePlacedBuildings(player: Player): { { PlacementId: string, AssetId: string, Position: Vector3 } }
	local result = {}
	local playerPlaced = placedBuildings[player]
	if not playerPlaced then
		return result
	end
	for placementId, building in playerPlaced do
		if building.HP > 0 then
			table.insert(result, { PlacementId = placementId, AssetId = building.AssetId, Position = building.CFrame.Position })
		end
	end
	return result
end

-- Lets EndlessModeMobManager.luau re-check a specific Tank mid-melee
-- (it might have died to this mob's own counter-hits, or been picked up)
-- without needing a whole GetAlivePlacedBuildings scan.
function PetManager.IsBuildingAlive(player: Player, placementId: string): boolean
	local playerPlaced = placedBuildings[player]
	local building = playerPlaced and playerPlaced[placementId]
	return building ~= nil and building.HP > 0
end

-- Called by EndlessModeMobManager.luau when a mob reaches a placed Estate
-- instead of the base. Clamped at 0; hitting 0 destroys that specific
-- building outright (model destroyed, removed from placedBuildings, panel
-- closed if it was the selected one, and its cap slot freed up) -- unlike
-- EndlessModeClaimManager.DamageBase's shared base HP (which just sits at 0,
-- nothing to "lose"), an individual building can actually be lost here.
function PetManager.DamageBuilding(player: Player, placementId: string, amount: number)
	local playerPlaced = placedBuildings[player]
	local building = playerPlaced and playerPlaced[placementId]
	if not building then
		return
	end

	building.HP = math.max(0, building.HP - amount)

	if building.HP <= 0 then
		if building.Model then
			building.Model:Destroy()
		end
		playerPlaced[placementId] = nil
		if selectedPlacementId[player] == placementId then
			selectedPlacementId[player] = nil
			endlessModeBuildingSelected:FireClient(player, nil)
		end
		-- Freed up a placement-cap slot -- re-evaluate whether the held
		-- preview for this Estate type should reappear.
		refreshPets(player)
		return
	end

	if building.HpLabel then
		building.HpLabel.Text = string.format("%d/%d HP", building.HP, getEffectiveMaxHP(building.AssetId, building.UpgradeLevel))
	end

	if selectedPlacementId[player] == placementId then
		endlessModeBuildingSelected:FireClient(player, buildSelectionPayload(player, placementId))
	end
end

return PetManager
