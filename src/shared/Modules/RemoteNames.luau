-- Single list of remote names shared by RemotesBootstrap (server) and every
-- client/server reference, so a typo'd string can't silently create a
-- mismatched pair of remotes.

local RemoteNames = {
	Events = {
		"RollRequested", -- client -> server, no payload
		"RollResult", -- server -> client, payload: Item
		"SellItem", -- client -> server, payload: uid
		"InventoryUpdated", -- server -> client, payload: { {Uid, ItemId} }
		"StatsUpdated", -- server -> client, payload: { Cash, NetWorth, Title }
		"BuyAsset", -- client -> server, payload: assetId
		"SellAsset", -- client -> server, payload: assetId
		"EquipAsset", -- client -> server, payload: assetId
		"UnequipAsset", -- client -> server, payload: assetId
		"AssetUpdated", -- server -> client, payload: { Owned: {[assetId]: boolean}, Equipped: {assetId} }
		"BuyInvestment", -- client -> server, payload: investmentId
		"SellInvestment", -- client -> server, payload: uid
		"InvestmentUpdated", -- server -> client, payload: { {Uid, Id} }
		"BuyPotion", -- client -> server, payload: potionId
		"PotionUpdated", -- server -> client, payload: { [potionId] = expiresAt }
	},
	Functions = {},
}

return RemoteNames
