-- Player-to-player trading -- Assets and Investments only, not rolled
-- items (deliberate scope: Assets/Invest are the deliberate, saved-for
-- purchases; trading those is "I'll swap my Beachfront Villa for your
-- Gold Bar", not giving away RNG luck). Requested via the sidebar Trade
-- button's player picker (RequestTrade remote) -- no physical proximity
-- prompt, trading works with anyone in the server regardless of location.
-- Target Accepts/Declines; once accepted, both sides build an offer and
-- Confirm -- changing an offer un-confirms both sides again (no bait-and-
-- switch after someone's already agreed). Only once BOTH are confirmed
-- does the swap execute.
--
-- Server-authoritative at every step, not just at the end: ownership/cash
-- are checked when an offer is set (for immediate feedback) AND again
-- right before the swap executes (in case something changed in between).
-- A traded Investment keeps its original PurchasedAt (the receiver gets
-- exactly the appreciation the sender had built up, not a reset timer) but
-- gets a fresh Uid in the receiver's own sequence. A traded Asset can't be
-- accepted by someone who already owns that type (OwnedAssets is a
-- boolean flag, not stackable) -- that offer just fails validation.
--
-- Trade state is in-memory only (not part of DataManager's Session) --
-- it's ephemeral, nothing about an in-progress trade needs to survive a
-- server restart or get saved to the DataStore.
--
-- Gated behind TradeConfig.MinNetWorth -- both requester AND target must
-- qualify, checked in onTradeRequested.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local InvestmentDatabase = require(ReplicatedStorage.Modules.InvestmentDatabase)
local TradeConfig = require(ReplicatedStorage.Modules.TradeConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)

local requestTrade = RemotesBootstrap:WaitForChild("RequestTrade")
local tradeRequestReceived = RemotesBootstrap:WaitForChild("TradeRequestReceived")
local respondTradeRequest = RemotesBootstrap:WaitForChild("RespondTradeRequest")
local tradeStateUpdated = RemotesBootstrap:WaitForChild("TradeStateUpdated")
local updateTradeOffer = RemotesBootstrap:WaitForChild("UpdateTradeOffer")
local confirmTradeOffer = RemotesBootstrap:WaitForChild("ConfirmTradeOffer")
local cancelTrade = RemotesBootstrap:WaitForChild("CancelTrade")
local assetUpdated = RemotesBootstrap:WaitForChild("AssetUpdated")
local investmentUpdated = RemotesBootstrap:WaitForChild("InvestmentUpdated")

local TRADE_REQUEST_COOLDOWN_SECONDS = 3

local function meetsTradeRequirement(player: Player): boolean
	return StatsManager.ComputeNetWorth(player) >= TradeConfig.MinNetWorth
end

type TradeOffer = { AssetIds: { string }, InvestmentUids: { number }, Cash: number }
type TradeSession = {
	PlayerA: Player,
	PlayerB: Player,
	OfferA: TradeOffer,
	OfferB: TradeOffer,
	ConfirmedA: boolean,
	ConfirmedB: boolean,
}

-- One incoming request at a time per target (a newer request just
-- overwrites an older unanswered one).
local pendingRequestsByTarget: { [Player]: Player } = {}
local lastRequestAt: { [Player]: number } = {}

-- Both PlayerA and PlayerB key into the SAME session table.
local activeTradeByPlayer: { [Player]: TradeSession } = {}

local function resolveInvestments(ownerSessionData, uids: { number })
	local now = os.time()
	local resolved = {}
	for _, uid in uids do
		for _, entry in ownerSessionData.Investments do
			if entry.Uid == uid then
				table.insert(resolved, {
					Id = entry.Id,
					CurrentValue = InvestmentDatabase.ComputeEntryValue(entry, now),
					Quantity = entry.Quantity,
				})
				break
			end
		end
	end
	return resolved
end

local function stateFor(session: TradeSession, player: Player)
	local isA = session.PlayerA == player
	local myOffer = isA and session.OfferA or session.OfferB
	local theirOfferRaw = isA and session.OfferB or session.OfferA
	local partner = isA and session.PlayerB or session.PlayerA
	local partnerSessionData = DataManager.Get(partner)

	return {
		Active = true,
		Partner = partner,
		MyOffer = { AssetIds = myOffer.AssetIds, InvestmentUids = myOffer.InvestmentUids, Cash = myOffer.Cash },
		-- TheirOffer.AssetIds are directly resolvable client-side (shared
		-- AssetDatabase), but TheirOffer's Investments need this player's
		-- PurchasedAt (only the server has both sessions), so they're
		-- pre-resolved to {Id, CurrentValue} here instead of raw Uids.
		TheirOffer = {
			AssetIds = theirOfferRaw.AssetIds,
			Investments = partnerSessionData and resolveInvestments(partnerSessionData, theirOfferRaw.InvestmentUids) or {},
			Cash = theirOfferRaw.Cash,
		},
		-- NOT `isA and session.ConfirmedA or session.ConfirmedB` -- that
		-- idiom breaks the moment session.ConfirmedA is `false` (the exact
		-- "haven't confirmed yet" case this field exists to report): `true
		-- and false` collapses to `false`, so the whole expression falls
		-- through to `session.ConfirmedB` instead, silently reporting the
		-- OTHER player's confirmation state as this player's own. Plain
		-- if/else instead.
		MyConfirmed = if isA then session.ConfirmedA else session.ConfirmedB,
		TheirConfirmed = if isA then session.ConfirmedB else session.ConfirmedA,
	}
end

local function pushState(session: TradeSession)
	tradeStateUpdated:FireClient(session.PlayerA, stateFor(session, session.PlayerA))
	tradeStateUpdated:FireClient(session.PlayerB, stateFor(session, session.PlayerB))
end

local function endTrade(session: TradeSession, reason: string)
	activeTradeByPlayer[session.PlayerA] = nil
	activeTradeByPlayer[session.PlayerB] = nil
	tradeStateUpdated:FireClient(session.PlayerA, { Active = false, Reason = reason })
	tradeStateUpdated:FireClient(session.PlayerB, { Active = false, Reason = reason })
end

local function assetsStillValid(giverSessionData, receiverSessionData, assetIds: { string }): boolean
	for _, assetId in assetIds do
		if not giverSessionData.OwnedAssets[assetId] then
			return false
		end
		if receiverSessionData.OwnedAssets[assetId] then
			-- OwnedAssets is a boolean flag, not stackable -- the receiver
			-- can't hold a second copy of a type they already own.
			return false
		end
	end
	return true
end

local function ownsAllInvestments(sessionData, uids: { number }): boolean
	for _, uid in uids do
		local found = false
		for _, entry in sessionData.Investments do
			if entry.Uid == uid then
				found = true
				break
			end
		end
		if not found then
			return false
		end
	end
	return true
end

local function pullAssets(sessionData, assetIds: { string })
	for _, assetId in assetIds do
		sessionData.OwnedAssets[assetId] = nil
		local equippedIndex = table.find(sessionData.EquippedAssets, assetId)
		if equippedIndex then
			table.remove(sessionData.EquippedAssets, equippedIndex)
		end
	end
end

local function pullInvestments(sessionData, uids: { number })
	local pulled = {}
	for _, uid in uids do
		for index, entry in sessionData.Investments do
			if entry.Uid == uid then
				table.insert(pulled, entry)
				table.remove(sessionData.Investments, index)
				break
			end
		end
	end
	return pulled
end

local function executeTrade(session: TradeSession)
	local sessionA = DataManager.Get(session.PlayerA)
	local sessionB = DataManager.Get(session.PlayerB)
	if not sessionA or not sessionB then
		endTrade(session, "error")
		return
	end

	-- Re-validate right before swapping -- offers were only checked when
	-- set, state may have changed since (spent cash / sold an asset
	-- elsewhere while the trade window was still open).
	if sessionA.Cash < session.OfferA.Cash or sessionB.Cash < session.OfferB.Cash then
		endTrade(session, "invalid")
		return
	end
	if
		not assetsStillValid(sessionA, sessionB, session.OfferA.AssetIds)
		or not assetsStillValid(sessionB, sessionA, session.OfferB.AssetIds)
	then
		endTrade(session, "invalid")
		return
	end
	if not ownsAllInvestments(sessionA, session.OfferA.InvestmentUids) or not ownsAllInvestments(sessionB, session.OfferB.InvestmentUids) then
		endTrade(session, "invalid")
		return
	end

	local investmentsFromA = pullInvestments(sessionA, session.OfferA.InvestmentUids)
	local investmentsFromB = pullInvestments(sessionB, session.OfferB.InvestmentUids)

	pullAssets(sessionA, session.OfferA.AssetIds)
	pullAssets(sessionB, session.OfferB.AssetIds)

	for _, assetId in session.OfferA.AssetIds do
		sessionB.OwnedAssets[assetId] = true
	end
	for _, assetId in session.OfferB.AssetIds do
		sessionA.OwnedAssets[assetId] = true
	end

	for _, entry in investmentsFromA do
		local newUid = sessionB.NextInvestmentUid
		sessionB.NextInvestmentUid += 1
		table.insert(sessionB.Investments, { Uid = newUid, Id = entry.Id, PurchasedAt = entry.PurchasedAt, Quantity = entry.Quantity })
	end
	for _, entry in investmentsFromB do
		local newUid = sessionA.NextInvestmentUid
		sessionA.NextInvestmentUid += 1
		table.insert(sessionA.Investments, { Uid = newUid, Id = entry.Id, PurchasedAt = entry.PurchasedAt, Quantity = entry.Quantity })
	end

	sessionA.Cash = sessionA.Cash - session.OfferA.Cash + session.OfferB.Cash
	sessionB.Cash = sessionB.Cash - session.OfferB.Cash + session.OfferA.Cash

	activeTradeByPlayer[session.PlayerA] = nil
	activeTradeByPlayer[session.PlayerB] = nil

	assetUpdated:FireClient(session.PlayerA, { Owned = sessionA.OwnedAssets, Equipped = sessionA.EquippedAssets })
	assetUpdated:FireClient(session.PlayerB, { Owned = sessionB.OwnedAssets, Equipped = sessionB.EquippedAssets })
	investmentUpdated:FireClient(session.PlayerA, sessionA.Investments)
	investmentUpdated:FireClient(session.PlayerB, sessionB.Investments)
	StatsManager.Recompute(session.PlayerA)
	StatsManager.Recompute(session.PlayerB)
	LeaderboardManager.MarkDirty(session.PlayerA)
	LeaderboardManager.MarkDirty(session.PlayerB)

	tradeStateUpdated:FireClient(session.PlayerA, { Active = false, Completed = true })
	tradeStateUpdated:FireClient(session.PlayerB, { Active = false, Completed = true })
end

local function onTradeRequested(requester: Player, target: Player)
	local now = os.clock()
	local last = lastRequestAt[requester]
	if last and now - last < TRADE_REQUEST_COOLDOWN_SECONDS then
		return
	end
	lastRequestAt[requester] = now

	if activeTradeByPlayer[requester] or activeTradeByPlayer[target] then
		return
	end

	if not meetsTradeRequirement(requester) or not meetsTradeRequirement(target) then
		return
	end

	pendingRequestsByTarget[target] = requester
	tradeRequestReceived:FireClient(target, requester)
end

requestTrade.OnServerEvent:Connect(function(player: Player, target: Player)
	if typeof(target) ~= "Instance" or not target:IsA("Player") then
		return
	end
	if target == player then
		return
	end
	onTradeRequested(player, target)
end)

respondTradeRequest.OnServerEvent:Connect(function(player: Player, requester: Player, accepted: boolean)
	if typeof(requester) ~= "Instance" or not requester:IsA("Player") then
		return
	end
	if typeof(accepted) ~= "boolean" then
		return
	end
	if pendingRequestsByTarget[player] ~= requester then
		return
	end
	pendingRequestsByTarget[player] = nil

	if not accepted then
		return
	end
	if not requester.Parent then
		return
	end
	if activeTradeByPlayer[player] or activeTradeByPlayer[requester] then
		return
	end

	local session: TradeSession = {
		PlayerA = requester,
		PlayerB = player,
		OfferA = { AssetIds = {}, InvestmentUids = {}, Cash = 0 },
		OfferB = { AssetIds = {}, InvestmentUids = {}, Cash = 0 },
		ConfirmedA = false,
		ConfirmedB = false,
	}
	activeTradeByPlayer[requester] = session
	activeTradeByPlayer[player] = session

	pushState(session)
end)

updateTradeOffer.OnServerEvent:Connect(function(player: Player, payload: { AssetIds: { string }, InvestmentUids: { number }, Cash: number })
	local session = activeTradeByPlayer[player]
	if not session then
		return
	end
	if
		typeof(payload) ~= "table"
		or typeof(payload.AssetIds) ~= "table"
		or typeof(payload.InvestmentUids) ~= "table"
		or typeof(payload.Cash) ~= "number"
	then
		return
	end

	local playerSessionData = DataManager.Get(player)
	if not playerSessionData then
		return
	end

	local cash = math.floor(math.max(payload.Cash, 0))
	if cash > playerSessionData.Cash then
		cash = playerSessionData.Cash
	end

	local assetIds = {}
	local seenAssets: { [string]: boolean } = {}
	for _, assetId in payload.AssetIds do
		if typeof(assetId) == "string" and not seenAssets[assetId] and playerSessionData.OwnedAssets[assetId] then
			seenAssets[assetId] = true
			table.insert(assetIds, assetId)
		end
	end

	local investmentUids = {}
	local seenInvestments: { [number]: boolean } = {}
	for _, uid in payload.InvestmentUids do
		if typeof(uid) == "number" and not seenInvestments[uid] then
			local owned = false
			for _, entry in playerSessionData.Investments do
				if entry.Uid == uid then
					owned = true
					break
				end
			end
			if owned then
				seenInvestments[uid] = true
				table.insert(investmentUids, uid)
			end
		end
	end

	local isA = session.PlayerA == player
	if isA then
		session.OfferA = { AssetIds = assetIds, InvestmentUids = investmentUids, Cash = cash }
	else
		session.OfferB = { AssetIds = assetIds, InvestmentUids = investmentUids, Cash = cash }
	end
	-- Changing either side's offer un-confirms both -- if I already agreed
	-- and the other side changes something, I need to look again.
	session.ConfirmedA = false
	session.ConfirmedB = false

	pushState(session)
end)

confirmTradeOffer.OnServerEvent:Connect(function(player: Player)
	local session = activeTradeByPlayer[player]
	if not session then
		return
	end

	if session.PlayerA == player then
		session.ConfirmedA = true
	else
		session.ConfirmedB = true
	end

	if session.ConfirmedA and session.ConfirmedB then
		executeTrade(session)
		return
	end

	pushState(session)
end)

cancelTrade.OnServerEvent:Connect(function(player: Player)
	local session = activeTradeByPlayer[player]
	if not session then
		return
	end
	endTrade(session, "cancelled")
end)

Players.PlayerRemoving:Connect(function(player)
	pendingRequestsByTarget[player] = nil
	for target, requester in pendingRequestsByTarget do
		if requester == player then
			pendingRequestsByTarget[target] = nil
		end
	end

	local session = activeTradeByPlayer[player]
	if session then
		endTrade(session, "left")
	end
end)

-- Side-effect-only module -- see RollManager.luau's tail comment for why
-- this return is required even though nothing is exported.
return true
