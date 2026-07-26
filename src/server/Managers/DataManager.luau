-- Vanilla DataStore persistence. One in-memory Lua session table per player
-- (Cash, Inventory, NextUid) instead of Instance Values -- a single field
-- list instead of duplicating each field across load/save/apply/default.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local DataManager = {}

local store = DataStoreService:GetDataStore("WealthRNG_PlayerData_V1")

local RETRY_COUNT = 3
local RETRY_BACKOFF_SECONDS = 2
local AUTOSAVE_INTERVAL_SECONDS = 120

export type Session = {
	Cash: number,
	Inventory: { { Uid: number, ItemId: string } },
	NextUid: number,
	EquippedItemUids: { number },
	TotalRolls: number,
	OwnedAssets: { [string]: boolean },
	EquippedAssets: { string },
	Investments: { { Uid: number, Id: string, PurchasedAt: number } },
	NextInvestmentUid: number,
	ActivePotions: { [string]: number },
	LoadedOk: boolean,
}

local sessions: { [Player]: Session } = {}

local function newDefaultSession(): Session
	return {
		Cash = 0,
		Inventory = {},
		NextUid = 1,
		EquippedItemUids = {},
		TotalRolls = 0,
		OwnedAssets = {},
		EquippedAssets = {},
		Investments = {},
		NextInvestmentUid = 1,
		ActivePotions = {},
		LoadedOk = true,
	}
end

local function attempt(fn): (boolean, any)
	for i = 1, RETRY_COUNT do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if i < RETRY_COUNT then
			task.wait(RETRY_BACKOFF_SECONDS)
		end
	end
	return false, nil
end

function DataManager.Load(player: Player): Session
	local key = "Player_" .. player.UserId
	local ok, data = attempt(function()
		return store:GetAsync(key)
	end)

	local session: Session
	if ok then
		if data then
			session = {
				Cash = data.Cash or 0,
				Inventory = data.Inventory or {},
				NextUid = data.NextUid or 1,
				EquippedItemUids = data.EquippedItemUids or {},
				TotalRolls = data.TotalRolls or 0,
				OwnedAssets = data.OwnedAssets or {},
				EquippedAssets = data.EquippedAssets or {},
				Investments = data.Investments or {},
				NextInvestmentUid = data.NextInvestmentUid or 1,
				ActivePotions = data.ActivePotions or {},
				LoadedOk = true,
			}
		else
			session = newDefaultSession()
		end
	else
		-- Load failed: fall back to an in-memory-only default session and
		-- never let Save() persist over the player's real saved data.
		session = newDefaultSession()
		session.LoadedOk = false
		warn(string.format("[DataManager] Failed to load data for %s (%d) after %d attempts", player.Name, player.UserId, RETRY_COUNT))
	end

	sessions[player] = session
	return session
end

function DataManager.Get(player: Player): Session?
	return sessions[player]
end

function DataManager.Save(player: Player)
	local session = sessions[player]
	if not session or not session.LoadedOk then
		return
	end

	local key = "Player_" .. player.UserId
	local payload = {
		Cash = session.Cash,
		Inventory = session.Inventory,
		NextUid = session.NextUid,
		EquippedItemUids = session.EquippedItemUids,
		TotalRolls = session.TotalRolls,
		OwnedAssets = session.OwnedAssets,
		EquippedAssets = session.EquippedAssets,
		Investments = session.Investments,
		NextInvestmentUid = session.NextInvestmentUid,
		ActivePotions = session.ActivePotions,
	}

	local ok = attempt(function()
		store:SetAsync(key, payload)
	end)

	if not ok then
		warn(string.format("[DataManager] Failed to save data for %s (%d) after %d attempts", player.Name, player.UserId, RETRY_COUNT))
	end
end

function DataManager.Release(player: Player)
	sessions[player] = nil
end

Players.PlayerRemoving:Connect(function(player)
	DataManager.Save(player)
	DataManager.Release(player)
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		DataManager.Save(player)
	end
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL_SECONDS)
		for _, player in Players:GetPlayers() do
			DataManager.Save(player)
		end
	end
end)

return DataManager
