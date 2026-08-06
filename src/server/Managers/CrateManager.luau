-- Grants the items from an "Exclusive Crate" purchase (CrateConfig.luau) --
-- called from CashPackManager.luau's shared ProcessReceipt once a Crate
-- Developer Product purchase is confirmed (Roblox only allows ONE
-- ProcessReceipt callback per game, same reason PotionManager.GrantPotionFree
-- is called from there instead of owning its own). Never required by
-- RollManager/StatsManager/etc. -- this only ever runs from a purchase, not
-- from anything roll-related.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CrateConfig = require(ReplicatedStorage.Modules.CrateConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local InventoryManager = require(ServerScriptService.Managers.InventoryManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)

local inventoryUpdated = RemotesBootstrap:WaitForChild("InventoryUpdated")
local crateOpenResult = RemotesBootstrap:WaitForChild("CrateOpenResult")

local CrateManager = {}

local random = Random.new()

-- Opens `quantity` crates for `player`, granting one of the 4 Crate-exclusive
-- Estates per crate (CrateConfig.RollItemId picks directly, no rarity tier
-- indirection anymore). Fires ONE CrateOpenResult with every item won (not
-- one fire per crate) so ShopPanel.luau's Crate section can show a single
-- batch-reveal instead of N popups.
function CrateManager.OpenCrates(player: Player, session, quantity: number)
	local wonItems = {}

	for _ = 1, quantity do
		local itemId = CrateConfig.RollItemId(random)
		local entry = InventoryManager.AddItem(player, itemId)
		if entry then
			table.insert(wonItems, { ItemId = itemId, Uid = entry.Uid })
		end
	end

	if #wonItems > 0 then
		crateOpenResult:FireClient(player, wonItems)
		inventoryUpdated:FireClient(player, session.Inventory)
		StatsManager.Recompute(player)
		LeaderboardManager.MarkDirty(player)
	end
end

return CrateManager
