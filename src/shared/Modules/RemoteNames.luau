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
	},
	Functions = {},
}

return RemoteNames
