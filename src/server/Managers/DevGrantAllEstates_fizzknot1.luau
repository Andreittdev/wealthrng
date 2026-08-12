-- DEV-ONLY test cheat, explicitly requested: fizzknot1 always owns every
-- Estate in the game (both AssetDatabase's own catalog AND the 4 Crate-
-- exclusive "Estate" items from ItemDatabase -- Storage Unit/Premium
-- Restaurant/Central Bank/Dream Castle, which aren't in AssetDatabase at
-- all), re-granted on EVERY join -- not a one-time migration like
-- ResetUpgrades_fizzknot1.luau, this is meant to just always be true for
-- this one account so testing Endless Mode's full loadout never needs a
-- manual Command Bar grant. Safe to leave in permanently -- entirely gated
-- by TARGET_USERNAME, a no-op for every other player.
--
-- Skips anything already owned (checked first) instead of blindly
-- re-granting every join -- AssetManager.GrantAsset is itself idempotent
-- for single-copy Estates, but InventoryManager.AddItem is NOT (it always
-- inserts a fresh Inventory entry with a new Uid), so re-running this every
-- join without the check would silently stack duplicate Crate-exclusive
-- items forever.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local DataManager = require(ServerScriptService.Managers.DataManager)
local AssetManager = require(ServerScriptService.Managers.AssetManager)
local InventoryManager = require(ServerScriptService.Managers.InventoryManager)

local TARGET_USERNAME = "fizzknot1"

-- Not in AssetDatabase at all -- a separate ItemDatabase system, so these
-- need InventoryManager.AddItem instead of AssetManager.GrantAsset.
local CRATE_EXCLUSIVE_ESTATE_ITEM_IDS = { "CrateVilla", "CrateManor", "CratePalace", "CrateCastle" }

-- DataManager.Load can still be mid-flight (its own DataStore round-trip)
-- by the time PlayerAdded listeners in a DIFFERENT module fire -- same
-- "poll until the session actually exists" idiom PetManager.luau's own
-- refreshPets retry uses, rather than assuming Main.server.luau's own
-- onPlayerAdded has already finished.
local SESSION_WAIT_RETRY_SECONDS = 0.5
local SESSION_WAIT_MAX_SECONDS = 15

local function grantEverything(player: Player)
	local session = DataManager.Get(player)
	if not session then
		return
	end

	for assetId in AssetDatabase.GetAllAssets() do
		if not session.OwnedAssets[assetId] then
			AssetManager.GrantAsset(player, session, assetId)
		end
	end

	for _, itemId in CRATE_EXCLUSIVE_ESTATE_ITEM_IDS do
		if (session.OwnedItemCounts[itemId] or 0) <= 0 then
			InventoryManager.AddItem(player, itemId)
		end
	end
end

local function onPlayerAdded(player: Player)
	if player.Name ~= TARGET_USERNAME then
		return
	end

	task.spawn(function()
		local waited = 0
		while waited < SESSION_WAIT_MAX_SECONDS do
			if DataManager.Get(player) then
				grantEverything(player)
				return
			end
			task.wait(SESSION_WAIT_RETRY_SECONDS)
			waited += SESSION_WAIT_RETRY_SECONDS
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

-- Side-effect-only module -- see RollManager.luau's tail comment for why
-- this return is required even though nothing is exported.
return true
