-- Grants the Estates from an "Exclusive Crate" purchase (CrateConfig.luau) --
-- called from CashPackManager.luau's shared ProcessReceipt once a Crate
-- Developer Product purchase is confirmed (Roblox only allows ONE
-- ProcessReceipt callback per game, same reason PotionManager.GrantPotionFree
-- is called from there instead of owning its own). Never required by
-- RollManager/StatsManager/etc. -- this only ever runs from a purchase, not
-- from anything roll-related.
--
-- Grants via AssetManager.GrantAsset (session.OwnedAssets), NOT
-- InventoryManager.AddItem -- per explicit "lasa sa fie si ele Estateuri
-- normale sa le dai equip normal ca la restu" request, the 4 Crate-exclusive
-- Estates are real AssetDatabase Assets now (see AssetDatabase.luau's own
-- comment on them), equipped/placed through the exact same system as every
-- other Estate instead of a separate one-off path. GrantAsset already
-- handles its own pushUpdate/StatsManager.Recompute/LeaderboardManager.
-- MarkDirty/serial-numbering per call (AssetManager.MULTI_OWNABLE_ASSET_IDS
-- includes all 4, so a repeat pull of one already owned still grants a
-- fresh serial instead of being a silent no-op) -- nothing extra needed
-- here beyond calling it once per crate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CrateConfig = require(ReplicatedStorage.Modules.CrateConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local AssetManager = require(ServerScriptService.Managers.AssetManager)

local crateOpenResult = RemotesBootstrap:WaitForChild("CrateOpenResult")
local discoveredItemsUpdated = RemotesBootstrap:WaitForChild("DiscoveredItemsUpdated")

local CrateManager = {}

local random = Random.new()

-- Opens `quantity` crates for `player`, granting one of the 4 Crate-exclusive
-- Estates per crate (CrateConfig.RollItemId picks directly, no rarity tier
-- indirection anymore). Fires ONE CrateOpenResult with every item won (not
-- one fire per crate) so ShopPanel.luau's Crate section can show a single
-- batch-reveal instead of N popups.
function CrateManager.OpenCrates(player: Player, session, quantity: number)
	local wonItems = {}
	local discoveredSomethingNew = false

	for _ = 1, quantity do
		local itemId = CrateConfig.RollItemId(random)
		AssetManager.GrantAsset(player, session, itemId)
		table.insert(wonItems, { ItemId = itemId })

		-- Same permanent discovery tracking as RollManager.luau -- backs
		-- CatalogPanel.luau's Index "unlocked" state for the 4
		-- Crate-exclusive Estates, which stays keyed off ItemDatabase's
		-- DiscoveredItemIds regardless of the ownership mechanism above.
		if not session.DiscoveredItemIds[itemId] then
			session.DiscoveredItemIds[itemId] = true
			discoveredSomethingNew = true
		end
	end

	if #wonItems > 0 then
		crateOpenResult:FireClient(player, wonItems)
		if discoveredSomethingNew then
			discoveredItemsUpdated:FireClient(player, session.DiscoveredItemIds)
		end
	end
end

return CrateManager
