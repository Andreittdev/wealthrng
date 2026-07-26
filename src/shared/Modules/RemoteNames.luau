-- Single list of remote names shared by RemotesBootstrap (server) and every
-- client/server reference, so a typo'd string can't silently create a
-- mismatched pair of remotes.

local RemoteNames = {
	Events = {
		"RollRequested", -- client -> server, no payload
		"RollResult", -- server -> client, payload: Item
		"SellItem", -- client -> server, payload: uid
		"InventoryUpdated", -- server -> client, payload: { {Uid, ItemId} }
		"EquipItem", -- client -> server, payload: uid
		"UnequipItem", -- client -> server, payload: uid
		"EquippedItemsUpdated", -- server -> client, payload: { uid }
		"StatsUpdated", -- server -> client, payload: { Cash, NetWorth, Title, IsVIP, ItemsIncomePerSecond, AssetsIncomePerMinute }
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
		"RequestTrade", -- client -> server, payload: target (Player) -- from the sidebar Trade button's player picker
		"TradeRequestReceived", -- server -> client, payload: fromPlayer (Player)
		"RespondTradeRequest", -- client -> server, payload: requester (Player), accepted (boolean)
		"TradeStateUpdated", -- server -> client, payload: TradeState (see TradeManager.luau)
		"UpdateTradeOffer", -- client -> server, payload: { AssetIds: {string}, InvestmentUids: {number}, Cash: number }
		"ConfirmTradeOffer", -- client -> server, no payload
		"CancelTrade", -- client -> server, no payload
	},
	Functions = {},
}

return RemoteNames
