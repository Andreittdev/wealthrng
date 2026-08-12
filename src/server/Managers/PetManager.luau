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
local Debris = game:GetService("Debris")
local ServerScriptService = game:GetService("ServerScriptService")

local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local EndlessModeConfig = require(ReplicatedStorage.Modules.EndlessModeConfig)
local EndlessModeBuildingConfig = require(ReplicatedStorage.Modules.EndlessModeBuildingConfig)
local EndlessModeUnitRoleConfig = require(ReplicatedStorage.Modules.EndlessModeUnitRoleConfig)
local DataManager = require(ServerScriptService.Managers.DataManager)
local AssetManager = require(ServerScriptService.Managers.AssetManager)
local InventoryManager = require(ServerScriptService.Managers.InventoryManager)
local EndlessModeClaimManager = require(ServerScriptService.Managers.EndlessModeClaimManager)
local EndlessModeMobRegistry = require(ServerScriptService.Managers.EndlessModeMobRegistry)
local EndlessModeAllyManager = require(ServerScriptService.Managers.EndlessModeAllyManager)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)

local placeEndlessModeEstate = RemotesBootstrap:WaitForChild("PlaceEndlessModeEstate")
local endlessModeHeldEstateUpdated = RemotesBootstrap:WaitForChild("EndlessModeHeldEstateUpdated")
local selectEndlessModeHeldEstate = RemotesBootstrap:WaitForChild("SelectEndlessModeHeldEstate")
local endlessModeBuildingSelected = RemotesBootstrap:WaitForChild("EndlessModeBuildingSelected")
local upgradeEndlessModeBuilding = RemotesBootstrap:WaitForChild("UpgradeEndlessModeBuilding")
local pickUpEndlessModeBuilding = RemotesBootstrap:WaitForChild("PickUpEndlessModeBuilding")
local endlessModeCashUpdated = RemotesBootstrap:WaitForChild("EndlessModeCashUpdated")
local endlessModeGameOver = RemotesBootstrap:WaitForChild("EndlessModeGameOver")
local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")

local PetManager = {}

type PlacedBuilding = {
	AssetId: string,
	CFrame: CFrame,
	UpgradeLevel: number,
	HP: number,
	Model: Model,
	-- Floating HP bar above the building -- same "filled Frame shrinking
	-- left-to-right, green fading to red, N/MAX text overlaid on top" style
	-- EndlessModeMobManager.luau's own mobs use, per explicit "vreau si la
	-- ele sa fie un health bar ca la mobi" request (buildings used to show
	-- plain "N/MAX HP" text alone). HpBillboard stored directly (not derived
	-- via HpLabel.Parent.Parent) so rescalePlacedBuilding doesn't need to
	-- know/assume the exact nesting depth.
	HpBillboard: BillboardGui,
	HpBarFill: Frame,
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

-- Which equipped Estate (or the equipped Crate-exclusive item) the player
-- picked, via a EndlessModeLoadoutHotbar.luau square, to be the ONE actually
-- held/placeable in Endless Mode right now -- per explicit "4 patrate, dai
-- equip la unu si se adauga in patratul ala" request (up to
-- AssetDatabase.MaxEquippedEndlessMode Estates can be equipped/in the
-- loadout at once, but only one is ever actively "in hand"). Nil means "no
-- explicit pick yet (or it stopped being equipped)" -- doRefreshPets below
-- falls back to the first equipped Estate in that case. Not persisted --
-- resets to the default fallback on rejoin, same as selectedPlacementId
-- above.
local selectedHeldAssetId: { [Player]: string? } = {}

-- Forward-declared (assigned further down, past doRefreshPets) -- the
-- placement/upgrade/pickup remote handlers need to call this, but are
-- defined textually earlier in the file than the real definition, so a
-- plain `local function refreshPets` down there would capture an unrelated
-- global instead of this upvalue.
local refreshPets: (Player) -> ()

-- Slots 1-4 fan out behind the character -- sized for AssetDatabase.
-- MaxEquippedEndlessMode (Endless Mode's own, bigger equip cap), even
-- though the Hub's own MaxEquipped stays at 2 (AssetManager.
-- TrimEquippedToHubCap trims back down to it on the way out of Endless
-- Mode, so a Hub floating pet realistically only ever uses slots 1-2, but
-- the extra slots are harmless/future-proof to keep defined). Offset from
-- HumanoidRootPart in ITS local space (+Z is behind a character's default
-- facing, +Y is up). Y was 3 (level with/above head) -- lowered to sit
-- around waist height instead. Slot 5 is dedicated to an equipped Crate-
-- exclusive Estate item (session.EquippedItemId, separate from the equipped
-- Assets in slots 1-4) -- centered, further back so it doesn't overlap any
-- Asset slot.
-- Slots 1 and 2 are the ORIGINAL left/right pair (unchanged from before the
-- 4-slot Endless loadout existed) -- per explicit bug report, they'd both
-- ended up on the SAME (left) side when this first grew from 2 to 4 slots,
-- since the array was ordered left-to-right (-4.5,-1.5,1.5,4.5) instead of
-- interleaved. The Hub only ever actually populates slots 1-2 (its own
-- MaxEquipped stays at 2), so THOSE two specifically have to keep matching
-- the pre-existing look; slots 3/4 (only ever relevant for a moment, if at
-- all, right as a player carrying 4 from Endless Mode lands back in the
-- Hub before AssetManager.TrimEquippedToHubCap's push settles) just flank
-- further out on their matching side.
local SLOT_OFFSETS = {
	Vector3.new(-2, 0.5, 6),
	Vector3.new(2, 0.5, 6),
	Vector3.new(-4.5, 0.5, 6.5),
	Vector3.new(4.5, 0.5, 6.5),
	Vector3.new(0, 0.5, 9),
}
local EQUIPPED_ITEM_SLOT_INDEX = #SLOT_OFFSETS
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
local function findSourceById(assetId: string): { Name: string, Id: string, Rarity: string? }?
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
-- comment) get the tighter 3-copy cap -- includes the 4 Crate-exclusive
-- Estates now that they're real AssetDatabase Assets (Rarity = "Exclusive").
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
	return math.floor(baseMaxHP * EndlessModeUnitRoleConfig.GetTankHPMultiplier(assetId, upgradeLevel))
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
	local role = EndlessModeUnitRoleConfig.GetRole(building.AssetId)

	local payload = {
		PlacementId = placementId,
		AssetId = building.AssetId,
		Name = (source and source.Name) or building.AssetId,
		HP = building.HP,
		MaxHP = getEffectiveMaxHP(building.AssetId, building.UpgradeLevel),
		UpgradeLevel = building.UpgradeLevel,
		UpgradeCost = EndlessModeBuildingConfig.GetUpgradeCost(building.UpgradeLevel),
		Role = role,
		-- Ground position -- EndlessModeRangeIndicator.luau needs this to
		-- draw a Damage building's range circle at the right spot.
		Position = building.CFrame.Position,
	}

	-- Role-specific combat stats, per explicit request -- shown under HP/
	-- Level in EndlessModeBuildingPanel.luau so the player can see what
	-- they're actually paying to upgrade, not just a bigger HP number.
	if role == "Damage" then
		payload.Damage = math.floor(EndlessModeUnitRoleConfig.DamageAmount * EndlessModeUnitRoleConfig.GetDamageAmountMultiplier(building.AssetId, building.UpgradeLevel))
		payload.Range = math.floor(EndlessModeUnitRoleConfig.DamageRangeStuds * EndlessModeUnitRoleConfig.GetDamageRangeMultiplier(building.AssetId, building.UpgradeLevel))
		payload.Cooldown = EndlessModeUnitRoleConfig.GetDamageCooldownSeconds(building.AssetId, building.UpgradeLevel)
	elseif role == "Spawner" then
		local spawnerPowerMultiplier = EndlessModeUnitRoleConfig.GetSpawnerPowerMultiplier(building.AssetId, building.UpgradeLevel)
		payload.AllyCount = EndlessModeUnitRoleConfig.GetSpawnerAllyCount(building.UpgradeLevel)
		payload.AllyDamage = math.floor(EndlessModeUnitRoleConfig.AllyDamagePerTick * spawnerPowerMultiplier)
		payload.AllyHP = math.floor(EndlessModeUnitRoleConfig.AllyHP * spawnerPowerMultiplier)
	end

	return payload
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

-- A freshly-placed (level 0) building is SMALL (EndlessModeBuildingConfig.
-- GetScaleMultiplier), which left its HP label floating almost right on top
-- of a barely-visible model -- a flat MIN clearance (not just half the
-- model's own tiny height) keeps the label readable regardless of how small
-- the building currently is, per explicit "nu prea il vad" (can't really
-- see it) feedback.
local HP_LABEL_MIN_CLEARANCE_STUDS = 6

local function hpLabelStudsUp(boundingSize: Vector3): number
	return math.max(boundingSize.Y / 2 + 3, HP_LABEL_MIN_CLEARANCE_STUDS)
end

-- Same visual constants/idiom as EndlessModeMobManager.luau's own mob HP
-- bars -- green at full health, sliding to red as it empties.
local HP_BAR_SIZE = UDim2.new(0, 120, 0, 24)
local HP_BAR_BACKGROUND_COLOR = Color3.fromRGB(35, 35, 35)
local HP_BAR_FULL_COLOR = Color3.fromRGB(90, 220, 100)
local HP_BAR_LOW_COLOR = Color3.fromRGB(220, 60, 60)

local function updateBuildingHpBar(fill: Frame, label: TextLabel, hp: number, maxHp: number)
	local fraction = maxHp > 0 and math.clamp(hp / maxHp, 0, 1) or 0
	fill.Size = UDim2.new(fraction, 0, 1, 0)
	fill.BackgroundColor3 = HP_BAR_LOW_COLOR:Lerp(HP_BAR_FULL_COLOR, fraction)
	label.Text = string.format("%d/%d", math.max(hp, 0), maxHp)
end

-- Builds the actual standalone Workspace model for ONE placed building
-- instance. Returns (model, hpBillboard, hpBarFill, hpLabel), or nils if
-- there's no matching pet
-- template (same "silently skip if missing" convention as everything else
-- in this file).
local function createPlacedBuildingModel(
	player: Player,
	placementId: string,
	assetId: string,
	cframe: CFrame,
	upgradeLevel: number,
	hp: number
): (Model?, BillboardGui?, Frame?, TextLabel?)
	local source = findSourceById(assetId)
	if not source then
		return nil, nil, nil, nil
	end

	local template = findPetTemplate(source)
	if not template then
		if not warnedMissingTemplates[assetId] then
			warnedMissingTemplates[assetId] = true
			warn(string.format("[PetManager] No pet model found for '%s' (Id: %s) -- expected a Model named '%s' or '%s' in ReplicatedStorage.PetModels or Workspace.", source.Name, source.Id, source.Name, source.Id))
		end
		return nil, nil, nil, nil
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

	-- Floating HP bar -- same style as EndlessModeMobManager.luau's own mob
	-- bars (filled Frame shrinking left-to-right, green fading to red, N/MAX
	-- text overlaid), per explicit "vreau si la ele sa fie un health bar ca
	-- la mobi" request -- StudsOffset instead of a dedicated anchor part
	-- since `anchor` already sits at the right X/Z, just needs lifting above
	-- the roofline.
	local hpBillboard = Instance.new("BillboardGui")
	hpBillboard.Name = "HPDisplay"
	hpBillboard.Size = HP_BAR_SIZE
	hpBillboard.StudsOffset = Vector3.new(0, hpLabelStudsUp(boundingSize), 0)
	hpBillboard.AlwaysOnTop = true
	hpBillboard.Adornee = anchor
	hpBillboard.Parent = anchor

	local hpBarBackground = Instance.new("Frame")
	hpBarBackground.Size = UDim2.new(1, 0, 1, 0)
	hpBarBackground.BackgroundColor3 = HP_BAR_BACKGROUND_COLOR
	hpBarBackground.BorderSizePixel = 0
	hpBarBackground.Parent = hpBillboard

	local hpBarFill = Instance.new("Frame")
	hpBarFill.Size = UDim2.new(1, 0, 1, 0)
	hpBarFill.BackgroundColor3 = HP_BAR_FULL_COLOR
	hpBarFill.BorderSizePixel = 0
	hpBarFill.Parent = hpBarBackground

	local hpLabel = Instance.new("TextLabel")
	hpLabel.Size = UDim2.new(1, 0, 1, 0)
	hpLabel.BackgroundTransparency = 1
	hpLabel.Font = Enum.Font.LuckiestGuy
	hpLabel.TextColor3 = Color3.new(1, 1, 1)
	hpLabel.TextStrokeTransparency = 0
	hpLabel.TextStrokeColor3 = Color3.fromRGB(10, 10, 10)
	hpLabel.TextScaled = true
	hpLabel.Parent = hpBarBackground

	updateBuildingHpBar(hpBarFill, hpLabel, hp, getEffectiveMaxHP(assetId, upgradeLevel))

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

	return pet, hpBillboard, hpBarFill, hpLabel
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

	if building.HpBillboard then
		building.HpBillboard.StudsOffset = Vector3.new(0, hpLabelStudsUp(boundingSize), 0)
	end
end

-- Held-in-hand (Endless Mode, still room to place more) or floating (Hub)
-- pet for an EQUIPPED asset slot. Returns (success, isHeldInHand) -- the 2nd
-- value is only meaningful when true, used by doRefreshPets below to figure
-- out which equipped Estate (if any) should be reported as "held" for the
-- client's placement preview. Placed copies are entirely separate objects
-- now (see createPlacedBuildingModel above) -- this function never renders
-- one.
--
-- `wantsHand`, per explicit "4 patrate, un singur Estate activ" request:
-- with up to AssetDatabase.MaxEquippedEndlessMode (4) Estates equipped at once, only
-- ONE of them is ever actually held/welded in front of the character in
-- Endless Mode at a time (whichever hotbar square is selected, see
-- selectedHeldAssetId/doRefreshPets below) -- every OTHER equipped Estate
-- still counts as equipped (its other effects, e.g. income, still apply)
-- but renders no hand model at all while in Endless Mode, same as already
-- being at the placement cap. Without this, every placeable equipped Estate
-- would weld to the SAME fixed HAND_GRIP_OFFSET simultaneously and visibly
-- overlap/z-fight.
local function spawnEquippedPet(player: Player, character: Model, hrp: BasePart, source: { Name: string, Id: string }, slotIndex: number, wantsHand: boolean): (boolean, boolean)
	local template = findPetTemplate(source)
	if not template then
		if not warnedMissingTemplates[source.Id] then
			warnedMissingTemplates[source.Id] = true
			warn(string.format("[PetManager] No pet model found for '%s' (Id: %s) -- expected a Model named '%s' or '%s' in ReplicatedStorage.PetModels or Workspace.", source.Name, source.Id, source.Name, source.Id))
		end
		return false, false
	end

	local inEndlessMode = EndlessModeConfig.IsCharacterInEndlessMode(character)
	local heldInHand = inEndlessMode and wantsHand and canPlaceMore(player, source.Id)

	if inEndlessMode and not heldInHand then
		-- Equipped and in Endless Mode, but either already at this type's
		-- (or the overall) placement cap, or simply not the currently-
		-- selected hand slot -- nothing to hold/place right now, so no pet
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

	-- Only ONE equipped Estate is ever actually "held"/welded at a time now
	-- (per explicit request, see spawnEquippedPet's wantsHand comment) --
	-- whichever the player last picked via a EndlessModeLoadoutHotbar.luau
	-- square (selectedHeldAssetId), falling back to the FIRST equipped
	-- Estate (or the equipped item, if no Estates are equipped) the moment
	-- nothing's been explicitly picked yet, or the pick stopped being
	-- equipped (unequipped, or swapped out by hitting the 4-slot cap).
	local desiredHeldAssetId = selectedHeldAssetId[player]
	if desiredHeldAssetId and table.find(session.EquippedAssets, desiredHeldAssetId) == nil and session.EquippedItemId ~= desiredHeldAssetId then
		desiredHeldAssetId = nil
	end
	if not desiredHeldAssetId then
		desiredHeldAssetId = session.EquippedAssets[1] or session.EquippedItemId
	end

	local heldAssetId: string? = nil

	for slotIndex, assetId in session.EquippedAssets do
		local asset = AssetDatabase.GetAsset(assetId)
		if asset then
			local _, heldInHand = spawnEquippedPet(player, character, hrp, asset, slotIndex, assetId == desiredHeldAssetId)
			if heldInHand then
				heldAssetId = assetId
			end
		end
	end

	-- Slot 5 -- an equipped Crate-exclusive Estate item (session.
	-- EquippedItemId, from InventoryManager, separate from the equipped
	-- Assets above). Only Crate-exclusive items get a pet -- a regular
	-- rolled item (watch, sneakers, etc.) isn't an Estate and was never
	-- meant to float a model behind the player.
	if session.EquippedItemId then
		local item = ItemDatabase.GetItem(session.EquippedItemId)
		if item and item.CrateExclusive then
			local _, heldInHand = spawnEquippedPet(player, character, hrp, item, EQUIPPED_ITEM_SLOT_INDEX, session.EquippedItemId == desiredHeldAssetId)
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

-- Destroys every placed-Estate Model this player currently has and clears
-- placedBuildings[player] entirely -- shared by the disconnect handler
-- below AND the "base destroyed" reset (see EndlessModeClaimManager.
-- BaseDestroyed listener further down), so a lost run wipes buildings the
-- exact same way leaving does.
local function clearAllPlacedBuildings(player: Player)
	local playerPlaced = placedBuildings[player]
	if playerPlaced then
		for _, building in playerPlaced do
			if building.Model then
				building.Model:Destroy()
			end
		end
	end
	placedBuildings[player] = nil
end

Players.PlayerRemoving:Connect(function(player: Player)
	activePets[player] = nil
	latestRefreshGeneration[player] = nil

	clearAllPlacedBuildings(player)
	EndlessModeAllyManager.ClearAlliesForOwner(player)
	selectedPlacementId[player] = nil
	selectedHeldAssetId[player] = nil
end)

-- Per explicit request ("baza aia de 200 HP... se duce tot progresul"):
-- losing a run (the claimed side's base hits 0 HP, EndlessModeClaimManager.
-- DamageBase) wipes it exactly like leaving would -- every placed building
-- destroyed, everything unequipped (also closes the selection panel/clears
-- the held estate if either was active), session progress reset back to a
-- fresh start (DataManager.ResetEndlessModeProgress -- same wave/cash reset
-- a disconnect uses). EndlessModeClaimManager has already released the
-- claim itself by the time this fires (its own responsibility, not this
-- file's) -- this only owns building/equip/session state, then tells the
-- client to show the "You Died!" screen.
EndlessModeClaimManager.BaseDestroyed.Event:Connect(function(side: string, owner: Player)
	clearAllPlacedBuildings(owner)
	EndlessModeAllyManager.ClearAlliesForOwner(owner)
	if selectedPlacementId[owner] then
		selectedPlacementId[owner] = nil
		endlessModeBuildingSelected:FireClient(owner, nil)
	end
	selectedHeldAssetId[owner] = nil

	-- Fires AssetManager.EquippedAssetsChanged, which refreshPets is already
	-- subscribed to (see above) -- no separate refreshPets call needed here.
	AssetManager.UnequipAll(owner)

	DataManager.ResetEndlessModeProgress(owner)
	local session = DataManager.Get(owner)
	if session then
		endlessModeCashUpdated:FireClient(owner, session.EndlessModeCash)
	end

	endlessModeGameOver:FireClient(owner)
end)

-- Right only for now -- matches EndlessModeClaimManager/EndlessModeMobManager's
-- own "Right only" scope.
local PLACEABLE_SIDE = "Right"

-- Current mob damage for `player` -- scales with their own wave progress
-- (session.EndlessModeWave, event-gated now -- see EndlessModeMobManager.
-- luau), same idiom EndlessModeMobManager.luau's own getMobDamage uses.
-- Needed here just to hand off to a Spawner's Ally (EndlessModeAllyManager.
-- SpawnAlly) so it knows how hard the mob it ends up fighting will hit back.
local function getMobDamage(player: Player): number
	local session = DataManager.Get(player)
	local wave = (session and session.EndlessModeWave) or 1
	return EndlessModeUnitRoleConfig.GetMobDamageForWave(wave)
end

-- Credits `player`'s EndlessModeCash for actually DEFEATING a mob (its own
-- HP hit 0, not just "delivered a hit and despawned") -- called wherever
-- EndlessModeMobRegistry.Damage returns true. Wave-scaled the same way
-- getMobDamage is, per explicit request.
local function awardMobKillReward(player: Player)
	local session = DataManager.Get(player)
	if not session then
		return
	end
	local wave = session.EndlessModeWave
	session.EndlessModeCash += EndlessModeUnitRoleConfig.GetMobKillRewardForWave(wave)
	endlessModeCashUpdated:FireClient(player, session.EndlessModeCash)
end

-- Visual-only -- a Damage building's attack was completely silent/invisible
-- before (the mob just lost HP with no on-screen sign anything fired at
-- all). 3 different effects, per explicit request ("nu vreau sa aiba toate
-- efect de laser") -- EndlessModeUnitRoleConfig.GetDamageEffectType picks
-- one per Estate, grouped by rarity: Common/Rare get a small traveling
-- bullet, Epic/Legendary get a laser beam, Godly/Exclusive get a bigger
-- impact/explosion at the target. Debris cleans all of them up shortly
-- after so nothing piles up.
local DAMAGE_EFFECT_COLOR = Color3.fromRGB(255, 70, 70)
-- Roughly building height -- effects originate from here instead of
-- literally ground level so they don't look like they're firing out of the
-- dirt.
local DAMAGE_EFFECT_ORIGIN_HEIGHT_STUDS = 3

-- Laser -- a thin Neon Part stretched between the two points (CFrame.new
-- (from, to) points its local -Z at `to`, then nudging it forward by half
-- the distance centers it on the midpoint, same "stretch a part into a
-- beam" trick used all over Roblox dev since there's no lightweight
-- built-in "draw a line in 3D" primitive). Thickness scales with the SAME
-- DamageAmount multiplier that scales its actual damage -- a cheap/weak
-- Damage Estate's beam reads as a thin, unimpressive zap, a maxed one reads
-- as a thick, powerful blast. Capped so even the strongest (90x) doesn't
-- blow up into something absurd.
local LASER_LIFETIME_SECONDS = 0.15
local LASER_MIN_THICKNESS_STUDS = 0.15
local LASER_MAX_THICKNESS_STUDS = 1
local LASER_THICKNESS_PER_MULTIPLIER_POINT = 0.01

local function getLaserThickness(assetId: string, upgradeLevel: number): number
	local multiplier = EndlessModeUnitRoleConfig.GetDamageAmountMultiplier(assetId, upgradeLevel)
	local thickness = LASER_MIN_THICKNESS_STUDS + (multiplier - 1) * LASER_THICKNESS_PER_MULTIPLIER_POINT
	return math.clamp(thickness, LASER_MIN_THICKNESS_STUDS, LASER_MAX_THICKNESS_STUDS)
end

local function showLaser(fromPosition: Vector3, toPosition: Vector3, thickness: number)
	local distance = (toPosition - fromPosition).Magnitude
	if distance <= 0 then
		return
	end

	local beam = Instance.new("Part")
	beam.Name = "EndlessModeDamageLaser"
	beam.Size = Vector3.new(thickness, thickness, distance)
	beam.CFrame = CFrame.new(fromPosition, toPosition) * CFrame.new(0, 0, -distance / 2)
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanTouch = false
	beam.Material = Enum.Material.Neon
	beam.Color = DAMAGE_EFFECT_COLOR
	beam.Parent = Workspace

	Debris:AddItem(beam, LASER_LIFETIME_SECONDS)
end

-- Custom-model support, shared by any Damage effect that can fly a real 3D
-- prop instead of a generated primitive shape (Bullet's ball, the pig
-- throw's ball below) -- same "manually placed Studio content wins over the
-- generated fallback" idiom PetModels already uses for Estates/Pets.
-- Looked up by exact Instance name under ReplicatedStorage.EndlessModeEffects.
local effectTemplateWarned: { [string]: boolean } = {}

local function getEffectTemplate(templateName: string): Instance?
	local effectsFolder = ReplicatedStorage:FindFirstChild("EndlessModeEffects")
	if not effectsFolder then
		return nil
	end
	return effectsFolder:FindFirstChild(templateName)
end

-- Works for both a Model (moved via PivotTo -- no PrimaryPart needed, it
-- falls back to an auto-computed bounding-box pivot when one isn't set) and
-- a single BasePart/MeshPart (moved via .CFrame directly).
local function pivotFlyingInstance(instance: Instance, cframe: CFrame)
	if instance:IsA("Model") then
		instance:PivotTo(cframe)
	elseif instance:IsA("BasePart") then
		instance.CFrame = cframe
	end
end

-- Clones `templateName` (if a usable Model/BasePart exists under
-- ReplicatedStorage.EndlessModeEffects with that exact name) and flies it in
-- a straight line from `fromPosition` to `toPosition` over `durationSeconds`,
-- spinning the whole way, firing `onArrive` (then destroying the clone) once
-- it lands. Returns false and does nothing else if no usable template was
-- found, so the caller falls back to its own generated primitive shape.
local function tryFlyCustomModel(
	templateName: string,
	fromPosition: Vector3,
	toPosition: Vector3,
	durationSeconds: number,
	spinDegreesPerSecond: number,
	onArrive: (() -> ())?
): boolean
	local template = getEffectTemplate(templateName)
	local usableTemplate = template and (template:IsA("Model") or template:IsA("BasePart")) and template

	if not usableTemplate then
		if not effectTemplateWarned[templateName] then
			effectTemplateWarned[templateName] = true
			if not template then
				warn(string.format("[PetManager] No %s found -- expected ReplicatedStorage.EndlessModeEffects.%s. Using the generated effect instead.", templateName, templateName))
			else
				warn(string.format("[PetManager] ReplicatedStorage.EndlessModeEffects.%s is a %s, not a Model or BasePart -- using the generated effect instead.", templateName, template.ClassName))
			end
		end
		return false
	end

	local instanceClone = usableTemplate:Clone()

	-- A Humanoid anywhere in the model makes Roblox's default overhead
	-- nameplate (name + health bar) show above it -- not wanted for a
	-- flying prop with no animation/rig needs, so it's stripped out.
	local humanoid = instanceClone:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid then
		humanoid:Destroy()
	end

	-- Manually placed Studio models routinely come in with Anchored = false
	-- on some/all of their parts (same gotcha anchorTemplate above fixes for
	-- pet templates) -- this clone is driven entirely by the anchor's own
	-- tween below (never physics), so an unanchored part visibly sinks/falls
	-- out from under the animation instead of flying where it's told to.
	if instanceClone:IsA("Model") then
		anchorTemplate(instanceClone)
	elseif instanceClone:IsA("BasePart") then
		instanceClone.Anchored = true
	end

	pivotFlyingInstance(instanceClone, CFrame.new(fromPosition))
	instanceClone.Parent = Workspace

	-- TweenService can't animate a whole Model's position directly -- an
	-- invisible anchor Part is tweened instead, and the clone is re-pivoted
	-- to match it on every step (its CFrame changing every tweened frame is
	-- what drives that).
	local anchor = Instance.new("Part")
	anchor.Name = "EndlessModeFlyingEffectAnchor"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CFrame = CFrame.new(fromPosition)
	anchor.Parent = Workspace

	local changedConnection = anchor:GetPropertyChangedSignal("CFrame"):Connect(function()
		pivotFlyingInstance(instanceClone, anchor.CFrame)
	end)

	local spinCFrame = CFrame.Angles(0, 0, math.rad(spinDegreesPerSecond * durationSeconds))
	local tween = TweenService:Create(anchor, TweenInfo.new(durationSeconds, Enum.EasingStyle.Linear), {
		CFrame = CFrame.new(toPosition) * spinCFrame,
	})
	tween.Completed:Connect(function()
		changedConnection:Disconnect()
		anchor:Destroy()
		instanceClone:Destroy()
		if onArrive then
			onArrive()
		end
	end)
	tween:Play()

	return true
end

-- Bullet -- a small ball that visibly travels from the building to the mob
-- over a short tween, per explicit "un mic efect" request for the weakest
-- (Common/Rare) Damage Estates. DowntownCondo flies a real model (LabTable,
-- per explicit request) instead of the generated ball, same "custom model
-- wins if it exists" idiom Old Farm's pig throw below already established.
local BULLET_SIZE_STUDS = 0.6
local BULLET_SPEED_STUDS_PER_SECOND = 60
local BULLET_SPIN_DEGREES_PER_SECOND = 360
local BULLET_MODEL_NAME_BY_ASSET_ID: { [string]: string } = {
	DowntownCondo = "LabTable",
}

local function showBullet(assetId: string, fromPosition: Vector3, toPosition: Vector3, onImpact: (() -> ())?)
	local distance = (toPosition - fromPosition).Magnitude
	local duration = math.max(distance / BULLET_SPEED_STUDS_PER_SECOND, 0.05)

	local customModelName = BULLET_MODEL_NAME_BY_ASSET_ID[assetId]
	if customModelName and tryFlyCustomModel(customModelName, fromPosition, toPosition, duration, BULLET_SPIN_DEGREES_PER_SECOND, onImpact) then
		return
	end

	local bullet = Instance.new("Part")
	bullet.Name = "EndlessModeDamageBullet"
	bullet.Shape = Enum.PartType.Ball
	bullet.Size = Vector3.new(BULLET_SIZE_STUDS, BULLET_SIZE_STUDS, BULLET_SIZE_STUDS)
	bullet.CFrame = CFrame.new(fromPosition)
	bullet.Anchored = true
	bullet.CanCollide = false
	bullet.CanTouch = false
	bullet.Material = Enum.Material.Neon
	bullet.Color = DAMAGE_EFFECT_COLOR
	bullet.Parent = Workspace

	local tween = TweenService:Create(bullet, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Position = toPosition })
	if onImpact then
		tween.Completed:Connect(onImpact)
	end
	tween:Play()

	Debris:AddItem(bullet, duration + 0.05)
end

-- Explosion -- a layered VFX burst AT the target, per explicit request for
-- the strongest (Godly/Exclusive) Damage Estates -- a bigger, more dramatic
-- impact than a mere beam/bullet. "sa arate ca bubuie tare" (make it look
-- like it booms hard), explicitly requested after the first pass (a single
-- fading sphere) read as too weak -- then later upgraded again ("vreau un
-- efect mai premium de explosion nu ala clasic") away from Roblox's stock
-- Instance.new("Explosion") toward a fully custom look: a near-white flash
-- CORE that snaps in then shrinks away fast (the "impact" instant), a
-- translucent 3D shockwave SHELL expanding outward in every direction, a
-- flat expanding shockwave RING on the ground (same "Cylinder rotated flat"
-- trick EndlessModeRangeIndicator.luau already uses for the range circle),
-- and a one-shot ParticleEmitter burst (embers/smoke/sparks, see
-- emitExplosionParticles above) for the actual fireball look.
local EXPLOSION_CORE_START_DIAMETER_STUDS = 2.5
local EXPLOSION_CORE_END_DIAMETER_STUDS = 0.5
local EXPLOSION_CORE_COLOR = Color3.fromRGB(255, 230, 150)
local EXPLOSION_CORE_DURATION_SECONDS = 0.15

-- Ring diameter matches EndlessModeUnitRoleConfig.ExplosionAoeRadiusStuds
-- (the ACTUAL AOE hit radius) so the visual reads honestly -- a mob
-- standing where the ring reaches is a mob that really does take the hit.
local EXPLOSION_RING_HEIGHT_STUDS = 0.3
local EXPLOSION_RING_START_DIAMETER_STUDS = 1
local EXPLOSION_RING_END_DIAMETER_STUDS = EndlessModeUnitRoleConfig.ExplosionAoeRadiusStuds * 2
local EXPLOSION_RING_DURATION_SECONDS = 0.35

-- Translucent 3D shockwave shell -- expands outward from the core in every
-- direction (not just flat on the ground like the ring below), giving the
-- blast actual volume instead of reading as a flat decal.
local EXPLOSION_SHELL_START_DIAMETER_STUDS = 1.5
local EXPLOSION_SHELL_END_DIAMETER_STUDS = EndlessModeUnitRoleConfig.ExplosionAoeRadiusStuds * 1.6
local EXPLOSION_SHELL_DURATION_SECONDS = 0.3
local EXPLOSION_SHELL_COLOR = Color3.fromRGB(255, 140, 40)

-- One-shot particle burst -- per explicit "vreau un efect mai premium de
-- explosion nu ala clasic" request, replaces Roblox's stock
-- Instance.new("Explosion") (generic fireball/smoke everyone recognizes)
-- with a layered custom burst: hot embers rocketing outward and cooling as
-- they fade, a rising smoke puff, and bright streaking sparks. Built
-- entirely from ParticleEmitters on a throwaway anchored Part -- no Studio-
-- placed assets needed, unlike the thrown-projectile models above.
local EXPLOSION_PARTICLE_CLEANUP_SECONDS = 1.2

local function emitExplosionParticles(atPosition: Vector3)
	local anchor = Instance.new("Part")
	anchor.Name = "EndlessModeDamageExplosionParticles"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CFrame = CFrame.new(atPosition)
	anchor.Parent = Workspace

	local embers = Instance.new("ParticleEmitter")
	embers.Texture = "rbxasset://textures/particles/fire_main.dds"
	embers.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 235, 150)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 120, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 30, 10)),
	})
	embers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	embers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	embers.Lifetime = NumberRange.new(0.35, 0.55)
	embers.Speed = NumberRange.new(14, 22)
	embers.SpreadAngle = Vector2.new(180, 180)
	embers.Rate = 0
	embers.Parent = anchor
	embers:Emit(26)

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 90, 95))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 5),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.7, 0.9)
	smoke.Speed = NumberRange.new(3, 6)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rate = 0
	smoke.Parent = anchor
	smoke:Emit(10)

	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 245, 200))
	sparks.Size = NumberSequence.new(0.25)
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Lifetime = NumberRange.new(0.2, 0.35)
	sparks.Speed = NumberRange.new(24, 36)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 0
	sparks.Parent = anchor
	sparks:Emit(18)

	Debris:AddItem(anchor, EXPLOSION_PARTICLE_CLEANUP_SECONDS)
end

-- `withRing` defaults true for the other Explosion-tier Estates -- Old
-- Farm's own showExplosionProjectile config passes false, per explicit
-- request, since the thrown OldFarmPig model itself is meant to read as the
-- "special" part of that hit instead of the same flat ring every Explosion
-- Estate shows.
local function showExplosion(atPosition: Vector3, withRing: boolean?)
	local core = Instance.new("Part")
	core.Name = "EndlessModeDamageExplosionCore"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(EXPLOSION_CORE_START_DIAMETER_STUDS, EXPLOSION_CORE_START_DIAMETER_STUDS, EXPLOSION_CORE_START_DIAMETER_STUDS)
	core.CFrame = CFrame.new(atPosition)
	core.Anchored = true
	core.CanCollide = false
	core.CanTouch = false
	core.Material = Enum.Material.Neon
	core.Color = EXPLOSION_CORE_COLOR
	core.Transparency = 0
	core.Parent = Workspace

	TweenService:Create(core, TweenInfo.new(EXPLOSION_CORE_DURATION_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(EXPLOSION_CORE_END_DIAMETER_STUDS, EXPLOSION_CORE_END_DIAMETER_STUDS, EXPLOSION_CORE_END_DIAMETER_STUDS),
		Transparency = 1,
	}):Play()
	Debris:AddItem(core, EXPLOSION_CORE_DURATION_SECONDS + 0.05)

	local shell = Instance.new("Part")
	shell.Name = "EndlessModeDamageExplosionShell"
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.new(EXPLOSION_SHELL_START_DIAMETER_STUDS, EXPLOSION_SHELL_START_DIAMETER_STUDS, EXPLOSION_SHELL_START_DIAMETER_STUDS)
	shell.CFrame = CFrame.new(atPosition)
	shell.Anchored = true
	shell.CanCollide = false
	shell.CanTouch = false
	shell.Material = Enum.Material.ForceField
	shell.Color = EXPLOSION_SHELL_COLOR
	shell.Transparency = 0.35
	shell.Parent = Workspace

	TweenService:Create(shell, TweenInfo.new(EXPLOSION_SHELL_DURATION_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(EXPLOSION_SHELL_END_DIAMETER_STUDS, EXPLOSION_SHELL_END_DIAMETER_STUDS, EXPLOSION_SHELL_END_DIAMETER_STUDS),
		Transparency = 1,
	}):Play()
	Debris:AddItem(shell, EXPLOSION_SHELL_DURATION_SECONDS + 0.05)

	if withRing ~= false then
		local ring = Instance.new("Part")
		ring.Name = "EndlessModeDamageExplosionRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(EXPLOSION_RING_HEIGHT_STUDS, EXPLOSION_RING_START_DIAMETER_STUDS, EXPLOSION_RING_START_DIAMETER_STUDS)
		ring.CFrame = CFrame.new(atPosition) * CFrame.Angles(0, 0, math.rad(90))
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanTouch = false
		ring.Material = Enum.Material.Neon
		ring.Color = DAMAGE_EFFECT_COLOR
		ring.Transparency = 0.2
		ring.Parent = Workspace

		TweenService:Create(ring, TweenInfo.new(EXPLOSION_RING_DURATION_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(EXPLOSION_RING_HEIGHT_STUDS, EXPLOSION_RING_END_DIAMETER_STUDS, EXPLOSION_RING_END_DIAMETER_STUDS),
			Transparency = 1,
		}):Play()
		Debris:AddItem(ring, EXPLOSION_RING_DURATION_SECONDS + 0.05)
	end

	emitExplosionParticles(atPosition)
end

-- Some Explosion-tier Estates throw a specific object that detonates
-- (the same showExplosion above) once it actually lands, instead of the
-- blast just appearing instantly at the target -- Old Farm's pig ("sa
-- arunce cu un porc care sa explodeze cand ajunge in Mob"), Luxury Hotel
-- Chain's diamond, and Construction Shop's Construction Worker, per explicit
-- requests. Real-model support: if the user
-- has manually dropped a model into ReplicatedStorage.EndlessModeEffects
-- with the given name (a Model or a single BasePart/MeshPart, either
-- works -- same "manually placed Studio content" idiom PetModels already
-- uses for Estates/Pets), that's cloned and flown instead of the generated
-- fallback ball, same as showBullet's custom-model support above.
local EXPLOSION_PROJECTILE_CONFIG: {
	[string]: {
		ModelName: string,
		FallbackColor: Color3,
		FallbackSizeStuds: number,
		SpeedStudsPerSecond: number,
		SpinDegreesPerSecond: number,
		WithRing: boolean,
		IsTornado: boolean?,
		IsDiamondBurst: boolean?,
	},
} = {
	OldFarm = {
		ModelName = "OldFarmPig",
		FallbackColor = Color3.fromRGB(255, 170, 180),
		FallbackSizeStuds = 1.4,
		SpeedStudsPerSecond = 40,
		SpinDegreesPerSecond = 720,
		-- Per explicit request, no ring for the pig -- it's meant to read
		-- as the "special" part of that hit by itself.
		WithRing = false,
	},
	-- Per explicit request ("vreau un efect si la ala mai special ca da cu
	-- diamante") -- a small glittering CLUSTER (see showDiamondBurstProjectile
	-- below) instead of a single Diamond: one full-size "hero" diamond at
	-- the center plus several smaller ones orbiting it for the whole
	-- flight, trailing sparkles -- the ONLY Explosion-tier Estate with
	-- IsDiamondBurst set.
	LuxuryHotelChain = {
		ModelName = "Diamond",
		FallbackColor = Color3.fromRGB(150, 220, 255),
		FallbackSizeStuds = 1.2,
		SpeedStudsPerSecond = 50,
		SpinDegreesPerSecond = 540,
		WithRing = true,
		IsDiamondBurst = true,
	},
	-- Per explicit request ("sa arunce cu tornada aia si in jurul ei sa fie
	-- Construction Worker") -- the TORNADO ITSELF is the thing that flies
	-- from the building to the mob (see showTornadoProjectile below), with
	-- several Construction Worker models orbiting around it the whole
	-- flight -- the ONLY Explosion-tier Estate with IsTornado set.
	ConstructionShop = {
		ModelName = "Construction Worker",
		FallbackColor = Color3.fromRGB(255, 200, 60),
		FallbackSizeStuds = 1.6,
		SpeedStudsPerSecond = 45,
		SpinDegreesPerSecond = 480,
		WithRing = true,
		IsTornado = true,
	},
}

local function throwOneExplosionProjectile(
	config: { ModelName: string, FallbackColor: Color3, FallbackSizeStuds: number, SpinDegreesPerSecond: number },
	fromPosition: Vector3,
	toPosition: Vector3,
	duration: number,
	onArrive: () -> ()
)
	if tryFlyCustomModel(config.ModelName, fromPosition, toPosition, duration, config.SpinDegreesPerSecond, onArrive) then
		return
	end

	local projectile = Instance.new("Part")
	projectile.Name = "EndlessModeDamageExplosionProjectile"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(config.FallbackSizeStuds, config.FallbackSizeStuds, config.FallbackSizeStuds)
	projectile.CFrame = CFrame.new(fromPosition)
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CanTouch = false
	projectile.Material = Enum.Material.Neon
	projectile.Color = config.FallbackColor
	projectile.Parent = Workspace

	TweenService:Create(projectile, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Orientation = Vector3.new(0, 0, config.SpinDegreesPerSecond * duration),
	}):Play()

	local flightTween = TweenService:Create(projectile, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Position = toPosition })
	flightTween.Completed:Connect(function()
		projectile:Destroy()
		onArrive()
	end)
	flightTween:Play()
end

-- Clones the Construction Worker template (or a small fallback ball if none
-- exists under ReplicatedStorage.EndlessModeEffects) for orbiting around
-- the flying tornado below -- same "strip the Humanoid so no nameplate
-- shows" treatment tryFlyCustomModel gives its own clones.
local function createOrbitingInstance(config: { ModelName: string, FallbackColor: Color3, FallbackSizeStuds: number }): Instance
	local template = getEffectTemplate(config.ModelName)
	local usableTemplate = template and (template:IsA("Model") or template:IsA("BasePart")) and template

	if usableTemplate then
		local clone = usableTemplate:Clone()
		local humanoid = clone:FindFirstChildWhichIsA("Humanoid", true)
		if humanoid then
			humanoid:Destroy()
		end
		-- Same "Studio models come in unanchored" fix tryFlyCustomModel
		-- above applies -- these orbit for the whole flight duration
		-- (showTornadoProjectile/showDiamondBurstProjectile), driven purely
		-- by pivotFlyingInstance each frame, so an unanchored part visibly
		-- sags/falls out of orbit instead of staying pinned to it.
		if clone:IsA("Model") then
			anchorTemplate(clone)
		elseif clone:IsA("BasePart") then
			clone.Anchored = true
		end
		clone.Parent = Workspace
		return clone
	end

	local ball = Instance.new("Part")
	ball.Name = "EndlessModeTornadoOrbitFallback"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(config.FallbackSizeStuds, config.FallbackSizeStuds, config.FallbackSizeStuds)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanTouch = false
	ball.Material = Enum.Material.Neon
	ball.Color = config.FallbackColor
	ball.Parent = Workspace
	return ball
end

-- Construction Shop's own thrown effect -- a small funnel of stacked
-- spinning discs (same "Cylinder rotated flat" trick showExplosion's ring
-- uses, just several stacked at rising heights/diameters instead of one,
-- narrow at the bottom/wide at the top like a real tornado's cloud) travels
-- the full distance from the building to the mob, with ORBIT_WORKER_COUNT
-- Construction Worker models circling around it (at different heights/
-- start angles) for the entire flight, like debris caught inside. Manual
-- per-frame loop (not TweenService) since both the funnel's own spin AND
-- each worker's orbit angle need to keep advancing independently of the
-- shared translation from fromPosition to toPosition.
local TORNADO_SEGMENT_COUNT = 4
local TORNADO_BASE_DIAMETER_STUDS = 0.8
local TORNADO_TOP_DIAMETER_STUDS = 3.2
local TORNADO_HEIGHT_STUDS = 4.5
local TORNADO_SEGMENT_THICKNESS_STUDS = 0.3
local TORNADO_SPIN_DEGREES_PER_SECOND = 900
-- Flat neutral gray, per explicit "tornada sa fie gri" request (was a
-- lighter, slightly blue-tinted gray before).
local TORNADO_COLOR = Color3.fromRGB(120, 120, 120)

local TORNADO_ORBIT_WORKER_COUNT = 3
local TORNADO_ORBIT_RADIUS_STUDS = 2.5
local TORNADO_ORBIT_DEGREES_PER_SECOND = 420

local function showTornadoProjectile(
	config: { ModelName: string, FallbackColor: Color3, FallbackSizeStuds: number },
	fromPosition: Vector3,
	toPosition: Vector3,
	duration: number,
	onArrive: () -> ()
)
	local segments = {}
	for i = 1, TORNADO_SEGMENT_COUNT do
		local t = (i - 1) / (TORNADO_SEGMENT_COUNT - 1)
		local diameter = TORNADO_BASE_DIAMETER_STUDS + (TORNADO_TOP_DIAMETER_STUDS - TORNADO_BASE_DIAMETER_STUDS) * t

		local segment = Instance.new("Part")
		segment.Name = "EndlessModeTornadoSegment"
		segment.Shape = Enum.PartType.Cylinder
		segment.Size = Vector3.new(TORNADO_SEGMENT_THICKNESS_STUDS, diameter, diameter)
		segment.Anchored = true
		segment.CanCollide = false
		segment.CanTouch = false
		segment.Material = Enum.Material.Neon
		segment.Color = TORNADO_COLOR
		segment.Transparency = 0.35 + t * 0.3
		-- Positioned right away at fromPosition (elapsed=0) instead of
		-- waiting for the loop's first task.wait() to run -- otherwise
		-- these sit at the default Instance.new origin for one frame
		-- before ever being placed, a brief flash at (0,0,0).
		segment.CFrame = CFrame.new(fromPosition + Vector3.new(0, t * TORNADO_HEIGHT_STUDS, 0)) * CFrame.Angles(0, 0, math.rad(90))
		segment.Parent = Workspace
		table.insert(segments, { Part = segment, HeightOffset = t * TORNADO_HEIGHT_STUDS, Spin = 0 })
	end

	local workers = {}
	for i = 1, TORNADO_ORBIT_WORKER_COUNT do
		local angleOffsetDegrees = (i - 1) * (360 / TORNADO_ORBIT_WORKER_COUNT)
		local heightOffset = (i - 1) * (TORNADO_HEIGHT_STUDS / TORNADO_ORBIT_WORKER_COUNT)
		local instance = createOrbitingInstance(config)
		local initialAngleRadians = math.rad(angleOffsetDegrees)
		local initialOrbitPosition = fromPosition
			+ Vector3.new(math.cos(initialAngleRadians) * TORNADO_ORBIT_RADIUS_STUDS, heightOffset, math.sin(initialAngleRadians) * TORNADO_ORBIT_RADIUS_STUDS)
		pivotFlyingInstance(instance, CFrame.new(initialOrbitPosition) * CFrame.Angles(0, initialAngleRadians, 0))
		table.insert(workers, {
			Instance = instance,
			AngleOffsetDegrees = angleOffsetDegrees,
			HeightOffset = heightOffset,
		})
	end

	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			local dt = task.wait()
			elapsed = math.min(elapsed + dt, duration)
			local currentCenter = fromPosition:Lerp(toPosition, elapsed / duration)

			for _, segment in segments do
				segment.Spin += TORNADO_SPIN_DEGREES_PER_SECOND * dt
				-- The 90-degree Z rotation makes local X the segment's
				-- vertical axis, so spinning around local X spins the disc
				-- around the world-vertical axis it's now standing on.
				segment.Part.CFrame = CFrame.new(currentCenter + Vector3.new(0, segment.HeightOffset, 0))
					* CFrame.Angles(0, 0, math.rad(90))
					* CFrame.Angles(math.rad(segment.Spin), 0, 0)
			end

			for _, worker in workers do
				local angleRadians = math.rad(worker.AngleOffsetDegrees + TORNADO_ORBIT_DEGREES_PER_SECOND * elapsed)
				local orbitPosition = currentCenter
					+ Vector3.new(math.cos(angleRadians) * TORNADO_ORBIT_RADIUS_STUDS, worker.HeightOffset, math.sin(angleRadians) * TORNADO_ORBIT_RADIUS_STUDS)
				pivotFlyingInstance(worker.Instance, CFrame.new(orbitPosition) * CFrame.Angles(0, angleRadians, 0))
			end
		end

		for _, segment in segments do
			segment.Part:Destroy()
		end
		for _, worker in workers do
			worker.Instance:Destroy()
		end

		onArrive()
	end)
end

-- Luxury Hotel Chain's own thrown effect -- a small glittering CLUSTER
-- instead of a single Diamond: one full-size "hero" diamond travels the
-- straight line from building to mob (spinning the whole way), with
-- DIAMOND_BURST_SATELLITE_COUNT smaller diamonds orbiting it, plus a
-- continuous sparkle trail for extra shine. Same moving-orbit technique
-- showTornadoProjectile above uses (a shared `currentCenter` interpolated
-- every frame, satellites offset from it by a rotating angle).
local DIAMOND_BURST_SATELLITE_COUNT = 4
local DIAMOND_BURST_ORBIT_RADIUS_STUDS = 2
local DIAMOND_BURST_ORBIT_DEGREES_PER_SECOND = 540
local DIAMOND_BURST_SATELLITE_SCALE = 0.5
local DIAMOND_BURST_CENTRAL_SPIN_DEGREES_PER_SECOND = 420
local DIAMOND_BURST_SPARKLE_INTERVAL_SECONDS = 0.08

local function scaleFlyingInstance(instance: Instance, scaleFactor: number)
	if instance:IsA("Model") then
		instance:ScaleTo(scaleFactor)
	elseif instance:IsA("BasePart") then
		instance.Size = instance.Size * scaleFactor
	end
end

-- Small one-shot sparkle puff -- reuses the same ParticleEmitter idiom
-- emitExplosionParticles above uses, just a lighter/faster burst meant to
-- read as glinting light off the diamonds rather than an impact.
local function emitDiamondSparkle(atPosition: Vector3)
	local anchor = Instance.new("Part")
	anchor.Name = "EndlessModeDiamondSparkle"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CFrame = CFrame.new(atPosition)
	anchor.Parent = Workspace

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(210, 240, 255))
	sparkle.Size = NumberSequence.new(0.18)
	sparkle.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparkle.Lifetime = NumberRange.new(0.15, 0.25)
	sparkle.Speed = NumberRange.new(2, 5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Rate = 0
	sparkle.Parent = anchor
	sparkle:Emit(3)

	Debris:AddItem(anchor, 0.4)
end

local function showDiamondBurstProjectile(
	config: { ModelName: string, FallbackColor: Color3, FallbackSizeStuds: number },
	fromPosition: Vector3,
	toPosition: Vector3,
	duration: number,
	onArrive: () -> ()
)
	local central = createOrbitingInstance(config)
	pivotFlyingInstance(central, CFrame.new(fromPosition))

	local satellites = {}
	for i = 1, DIAMOND_BURST_SATELLITE_COUNT do
		local angleOffsetDegrees = (i - 1) * (360 / DIAMOND_BURST_SATELLITE_COUNT)
		local instance = createOrbitingInstance(config)
		scaleFlyingInstance(instance, DIAMOND_BURST_SATELLITE_SCALE)
		local initialAngleRadians = math.rad(angleOffsetDegrees)
		local initialOrbitPosition = fromPosition
			+ Vector3.new(math.cos(initialAngleRadians) * DIAMOND_BURST_ORBIT_RADIUS_STUDS, 0, math.sin(initialAngleRadians) * DIAMOND_BURST_ORBIT_RADIUS_STUDS)
		pivotFlyingInstance(instance, CFrame.new(initialOrbitPosition) * CFrame.Angles(0, initialAngleRadians, 0))
		table.insert(satellites, { Instance = instance, AngleOffsetDegrees = angleOffsetDegrees })
	end

	task.spawn(function()
		local elapsed = 0
		local centralSpin = 0
		local sparkleTimer = 0
		while elapsed < duration do
			local dt = task.wait()
			elapsed = math.min(elapsed + dt, duration)
			centralSpin += DIAMOND_BURST_CENTRAL_SPIN_DEGREES_PER_SECOND * dt
			sparkleTimer += dt
			local currentCenter = fromPosition:Lerp(toPosition, elapsed / duration)

			pivotFlyingInstance(central, CFrame.new(currentCenter) * CFrame.Angles(0, math.rad(centralSpin), 0))

			for _, satellite in satellites do
				local angleRadians = math.rad(satellite.AngleOffsetDegrees + DIAMOND_BURST_ORBIT_DEGREES_PER_SECOND * elapsed)
				local orbitPosition = currentCenter
					+ Vector3.new(math.cos(angleRadians) * DIAMOND_BURST_ORBIT_RADIUS_STUDS, 0, math.sin(angleRadians) * DIAMOND_BURST_ORBIT_RADIUS_STUDS)
				pivotFlyingInstance(satellite.Instance, CFrame.new(orbitPosition) * CFrame.Angles(0, angleRadians, 0))
			end

			if sparkleTimer >= DIAMOND_BURST_SPARKLE_INTERVAL_SECONDS then
				sparkleTimer = 0
				emitDiamondSparkle(currentCenter)
			end
		end

		central:Destroy()
		for _, satellite in satellites do
			satellite.Instance:Destroy()
		end

		onArrive()
	end)
end

local function showExplosionProjectile(assetId: string, fromPosition: Vector3, toPosition: Vector3, onImpact: (() -> ())?)
	local config = EXPLOSION_PROJECTILE_CONFIG[assetId]
	local duration = math.max((toPosition - fromPosition).Magnitude / config.SpeedStudsPerSecond, 0.05)

	-- Damage lands exactly when the effect actually arrives, not when the
	-- throw starts -- per explicit "vreau sa moara fix cand porcul intra in
	-- el" request (kept for every thrown Explosion effect, not just the
	-- pig).
	local function detonate()
		if onImpact then
			onImpact()
		end
		showExplosion(toPosition, config.WithRing)
	end

	if config.IsTornado then
		showTornadoProjectile(config, fromPosition, toPosition, duration, detonate)
		return
	end

	if config.IsDiamondBurst then
		showDiamondBurstProjectile(config, fromPosition, toPosition, duration, detonate)
		return
	end

	throwOneExplosionProjectile(config, fromPosition, toPosition, duration, detonate)
end

-- Dispatches to whichever of the 3 effects above matches this Estate's role.
-- `onImpact`, if given, fires exactly when the effect actually LANDS on the
-- target -- immediately for Laser/instant-Explosion (nothing travels), but
-- only once the projectile itself arrives for Bullet/the pig throw. Lets
-- the caller (startDamageLoop) apply the mob's actual damage/death in sync
-- with what's on screen, instead of the mob dying before a slow-flying
-- effect (the pig) even reaches it.
local function showDamageEffect(assetId: string, upgradeLevel: number, fromGroundPosition: Vector3, toPosition: Vector3, onImpact: (() -> ())?)
	local fromPosition = fromGroundPosition + Vector3.new(0, DAMAGE_EFFECT_ORIGIN_HEIGHT_STUDS, 0)
	local effectType = EndlessModeUnitRoleConfig.GetDamageEffectType(assetId)

	if effectType == "Bullet" then
		showBullet(assetId, fromPosition, toPosition, onImpact)
	elseif effectType == "Explosion" then
		if EXPLOSION_PROJECTILE_CONFIG[assetId] then
			showExplosionProjectile(assetId, fromPosition, toPosition, onImpact)
		else
			showExplosion(toPosition)
			if onImpact then
				onImpact()
			end
		end
	else
		showLaser(fromPosition, toPosition, getLaserThickness(assetId, upgradeLevel))
		if onImpact then
			onImpact()
		end
	end
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
			-- Cooldown itself is level-scaled now, so the building has to be
			-- read BEFORE the wait to know how long that wait should even
			-- be -- then re-read AFTER (it may have been picked up/killed,
			-- or upgraded, while waiting).
			local playerPlaced = placedBuildings[player]
			local building = playerPlaced and playerPlaced[placementId]
			if not building then
				return
			end
			task.wait(EndlessModeUnitRoleConfig.GetDamageCooldownSeconds(building.AssetId, building.UpgradeLevel))

			playerPlaced = placedBuildings[player]
			building = playerPlaced and playerPlaced[placementId]
			if not building then
				return
			end
			local range = EndlessModeUnitRoleConfig.DamageRangeStuds * EndlessModeUnitRoleConfig.GetDamageRangeMultiplier(building.AssetId, building.UpgradeLevel)
			local mob = EndlessModeMobRegistry.GetNearestAliveMob(building.CFrame.Position, range)
			if mob then
				local amount = EndlessModeUnitRoleConfig.DamageAmount * EndlessModeUnitRoleConfig.GetDamageAmountMultiplier(building.AssetId, building.UpgradeLevel)
				local isAoe = EndlessModeUnitRoleConfig.GetDamageEffectType(building.AssetId) == "Explosion"
				-- Snapshotted now, not read again after the effect lands --
				-- the AOE hit is centered on where the blast actually
				-- landed, not wherever that original mob has since walked
				-- to (it might even be dead by then, from this same hit).
				local impactPosition = mob.Position
				-- Actual damage/death is applied from showDamageEffect's
				-- onImpact callback, not right here -- for a Bullet or a
				-- thrown Explosion projectile, that's only once the effect
				-- visually REACHES the target, not the instant the attack
				-- starts (which used to let a mob die well before a
				-- slow-flying pig ever got to it).
				showDamageEffect(building.AssetId, building.UpgradeLevel, building.CFrame.Position, impactPosition, function()
					if isAoe then
						-- Per explicit request, an Explosion-tier hit isn't
						-- single-target -- it catches EVERY mob standing in
						-- the blast, so a cluster spawned close together
						-- (e.g. a heavy wave) can get wiped by one hit.
						for _, aoeMob in EndlessModeMobRegistry.GetAliveMobsWithinRadius(impactPosition, EndlessModeUnitRoleConfig.ExplosionAoeRadiusStuds) do
							if EndlessModeMobRegistry.Damage(aoeMob, amount) then
								awardMobKillReward(player)
							end
						end
					elseif EndlessModeMobRegistry.Damage(mob, amount) then
						awardMobKillReward(player)
					end
				end)
			end
		end
	end)
end

-- Same lifetime idiom as startDamageLoop above, but for Spawner-role
-- buildings -- periodically hands off to EndlessModeAllyManager to actually
-- create and run each ally in the batch (GetSpawnerAllyCount -- 1 at low
-- levels, ramping to 3 at MaxUpgradeLevel, per explicit request).
local function startSpawnerLoop(player: Player, placementId: string)
	task.spawn(function()
		while true do
			task.wait(EndlessModeUnitRoleConfig.SpawnerIntervalSeconds)
			local playerPlaced = placedBuildings[player]
			local building = playerPlaced and playerPlaced[placementId]
			if not building then
				return
			end
			local powerMultiplier = EndlessModeUnitRoleConfig.GetSpawnerPowerMultiplier(building.AssetId, building.UpgradeLevel)
			local allyCount = EndlessModeUnitRoleConfig.GetSpawnerAllyCount(building.UpgradeLevel)
			for _ = 1, allyCount do
				EndlessModeAllyManager.SpawnAlly(player, building.AssetId, building.CFrame.Position, getMobDamage(player), powerMultiplier)
			end
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

	-- Placing now costs EndlessModeCash, per explicit request -- pricier the
	-- rarer the Estate (EndlessModeBuildingConfig.GetPlacementCost), paid
	-- from the same Endless-only economy upgrades already use. `source`
	-- (AssetDatabase or, for a Crate-exclusive "Estate" item, ItemDatabase)
	-- carries the Rarity the cost is actually keyed on.
	local source = findSourceById(assetId)
	local placementCost = EndlessModeBuildingConfig.GetPlacementCost(assetId, source and source.Rarity)
	if session.EndlessModeCash < placementCost then
		systemMessage:FireClient(player, "You don't have enough cash!")
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
	local model, hpBillboard, hpBarFill, hpLabel = createPlacedBuildingModel(player, placementId, assetId, cframe, 0, initialMaxHP)
	if not model or not hpBillboard or not hpBarFill or not hpLabel then
		return
	end

	-- Deducted only now that placement has actually succeeded (not back at
	-- the affordability check above) -- nothing should be charged for a
	-- placement that fails for some OTHER reason (a bad template, etc.).
	session.EndlessModeCash -= placementCost
	endlessModeCashUpdated:FireClient(player, session.EndlessModeCash)

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
		HpBillboard = hpBillboard,
		HpBarFill = hpBarFill,
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

-- Fired by EndlessModeLoadoutHotbar.luau when the player taps one of their
-- equipped Estates' hotbar squares -- makes THAT one the single actively
-- held/placeable Estate (see selectedHeldAssetId/spawnEquippedPet's
-- wantsHand). Re-validated here (not just trusted from the client's last-
-- known equip list) so a stale FireServer replay can't select something
-- that's since been unequipped.
selectEndlessModeHeldEstate.OnServerEvent:Connect(function(player: Player, assetId: string)
	if typeof(assetId) ~= "string" then
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

	selectedHeldAssetId[player] = assetId
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
		systemMessage:FireClient(player, "You don't have enough cash!")
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

	if building.HpBarFill and building.HpLabel then
		updateBuildingHpBar(building.HpBarFill, building.HpLabel, building.HP, building.HP)
	end

	-- Grows the actual Model too, per explicit request -- starts small at
	-- level 0, gets visibly bigger with each upgrade.
	rescalePlacedBuilding(building)

	endlessModeBuildingSelected:FireClient(player, buildSelectionPayload(player, placementId))
end)

-- The panel's "Sell" button (was "Pick Up") -- destroys this specific placed
-- instance, frees up a placement-cap slot, and refunds HALF the Estate's
-- placement cost (EndlessModeBuildingConfig.GetPlacementCost, same rarity-
-- keyed cost paid when it was placed) back to EndlessModeCash, per explicit
-- request. Doesn't put it back in a special "held" state of its own -- with
-- multiple copies allowed now, "held" just means "this equipped type has
-- room for one more", so the existing held preview (or a freshly-
-- reappearing one, via refreshPets below) covers replanting.
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

	local session = DataManager.Get(player)
	if session then
		local source = findSourceById(building.AssetId)
		local placementCost = EndlessModeBuildingConfig.GetPlacementCost(building.AssetId, source and source.Rarity)
		session.EndlessModeCash += math.floor(placementCost / 2)
		endlessModeCashUpdated:FireClient(player, session.EndlessModeCash)
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
-- closed if it was the selected one) -- unlike EndlessModeClaimManager.
-- DamageBase's shared base HP (which just sits at 0, nothing to "lose"), an
-- individual building can actually be lost here.
--
-- Deliberately does NOT call refreshPets -- per explicit request, a building
-- mobs killed doesn't silently pop back into "held in hand" just because its
-- cap slot freed up. It's just gone; the player has to unequip/re-equip (or
-- place a different copy) if they want to plant that type again -- unlike
-- pickUpEndlessModeBuilding's handler below, where refreshPets is correct
-- (the player is deliberately taking it back into their hand).
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
		return
	end

	if building.HpBarFill and building.HpLabel then
		updateBuildingHpBar(building.HpBarFill, building.HpLabel, building.HP, getEffectiveMaxHP(building.AssetId, building.UpgradeLevel))
	end

	if selectedPlacementId[player] == placementId then
		endlessModeBuildingSelected:FireClient(player, buildSelectionPayload(player, placementId))
	end
end

return PetManager
