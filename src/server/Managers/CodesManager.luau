-- Promo code redemption -- CodesProximityPanel.luau's Redeem button, fired
-- from the plaza's "Codes" floor marker. Validated against CodesConfig
-- (never trust a client-provided reward amount), one redemption per code
-- per save (session.RedeemedCodes), case-insensitive (uppercased before
-- both the lookup and the RedeemedCodes key, so "launch"/"Launch"/"LAUNCH"
-- are all the same code).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CodesConfig = require(ReplicatedStorage.Modules.CodesConfig)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)

local redeemCode = RemotesBootstrap:WaitForChild("RedeemCode")
local codeRedeemResult = RemotesBootstrap:WaitForChild("CodeRedeemResult")
local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")

redeemCode.OnServerEvent:Connect(function(player: Player, rawCode: string)
	local session = DataManager.Get(player)
	if not session then
		return
	end

	if typeof(rawCode) ~= "string" then
		return
	end

	local code = string.upper(string.gsub(rawCode, "%s+", ""))
	if code == "" then
		codeRedeemResult:FireClient(player, false, "Enter a code first.")
		return
	end

	local reward = CodesConfig.Codes[code]
	if not reward then
		codeRedeemResult:FireClient(player, false, "That code isn't valid.")
		return
	end

	if session.RedeemedCodes[code] then
		codeRedeemResult:FireClient(player, false, "You already redeemed that code.")
		return
	end

	session.RedeemedCodes[code] = true

	if reward.CashAmount then
		session.Cash += reward.CashAmount
	end

	local message = reward.CashAmount and string.format("Code redeemed: +%s!", NumberFormat.FormatCash(reward.CashAmount)) or "Code redeemed!"
	codeRedeemResult:FireClient(player, true, message)
	systemMessage:FireClient(player, message)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
end)

-- Side-effect-only module -- see RollManager.luau's tail comment for why
-- this return is required even though nothing is exported.
return true
