-- Recomputes Cash / NetWorth / Title / IsVIP after any mutation (roll, sell,
-- or a fresh VIP purchase) and pushes to the client + leaderstats only when
-- something actually changed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TitleConfig = require(ReplicatedStorage.Modules.TitleConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local InventoryManager = require(ServerScriptService.Managers.InventoryManager)
local Leaderstats = require(ServerScriptService.Managers.Leaderstats)
local VIPManager = require(ServerScriptService.Managers.VIPManager)

local statsUpdated = RemotesBootstrap:WaitForChild("StatsUpdated")

local StatsManager = {}

local lastStats: { [Player]: { Cash: number, NetWorth: number, Title: string, IsVIP: boolean } } = {}

function StatsManager.Recompute(player: Player)
	local session = DataManager.Get(player)
	if not session then
		return
	end

	local netWorth = session.Cash + InventoryManager.GetValue(player)
	local title = TitleConfig.GetTitleForNetWorth(netWorth)
	local isVIP = VIPManager.IsVIP(player)

	local previous = lastStats[player]
	if
		previous
		and previous.Cash == session.Cash
		and previous.NetWorth == netWorth
		and previous.Title == title
		and previous.IsVIP == isVIP
	then
		return
	end

	lastStats[player] = { Cash = session.Cash, NetWorth = netWorth, Title = title, IsVIP = isVIP }
	Leaderstats.SetCash(player, session.Cash)
	statsUpdated:FireClient(player, { Cash = session.Cash, NetWorth = netWorth, Title = title, IsVIP = isVIP })
end

return StatsManager
