-- Player-to-player trading -- Assets and rolled Items, NOT Investments
-- (deliberate scope, per explicit request -- Investments were dropped
-- from trading entirely; Roll Items took their place). Requested via the
-- sidebar Trade button's player picker (RequestTrade remote) -- no
-- physical proximity prompt, trading works with anyone in the server
-- regardless of location. Target Accepts/Declines; once accepted, both
-- sides build an offer and Confirm -- changing an offer un-confirms both
-- sides again (no bait-and-switch after someone's already agreed). Only
-- once BOTH are confirmed AND stay that way for CONFIRM_HOLD_SECONDS
-- straight does the swap execute (see confirmTradeOffer below) -- gives
-- either side a last-second window to back out.
--
-- Server-authoritative at every step, not just at the end: ownership/cash
-- are checked when an offer is set (for immediate feedback) AND again
-- right before the swap executes (in case something changed in between).
-- Items are pulled/granted via InventoryManager.RemoveItem/AddItem (not
-- manipulated directly here) so a traded item gets a fresh Uid in the
-- receiver's own sequence and OwnedItemCounts/InventoryTotalValue stay in
-- sync automatically, same as every other place items move. A traded
-- Asset can't be accepted by someone who already owns that type
-- (OwnedAssets is a boolean flag, not stackable) -- that offer just fails
-- validation.
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

local TradeConfig = require(ReplicatedStorage.Modules.TradeConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)
local InventoryManager = require(ServerScriptService.Managers.InventoryManager)
local AssetManager = require(ServerScriptService.Managers.AssetManager)

local requestTrade = RemotesBootstrap:WaitForChild("RequestTrade")
local tradeRequestReceived = RemotesBootstrap:WaitForChild("TradeRequestReceived")
local respondTradeRequest = RemotesBootstrap:WaitForChild("RespondTradeRequest")
local tradeStateUpdated = RemotesBootstrap:WaitForChild("TradeStateUpdated")
local updateTradeOffer = RemotesBootstrap:WaitForChild("UpdateTradeOffer")
local confirmTradeOffer = RemotesBootstrap:WaitForChild("ConfirmTradeOffer")
local cancelTrade = RemotesBootstrap:WaitForChild("CancelTrade")
local inventoryUpdated = RemotesBootstrap:WaitForChild("InventoryUpdated")
local equippedItemsUpdated = RemotesBootstrap:WaitForChild("EquippedItemsUpdated")
local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")

local TRADE_REQUEST_COOLDOWN_SECONDS = 3

local function meetsTradeRequirement(player: Player): boolean
	return StatsManager.ComputeNetWorth(player) >= TradeConfig.MinNetWorth
end

type TradeOffer = { AssetIds: { string }, ItemUids: { number }, Cash: number }
type TradeSession = {
	PlayerA: Player,
	PlayerB: Player,
	OfferA: TradeOffer,
	OfferB: TradeOffer,
	ConfirmedA: boolean,
	ConfirmedB: boolean,
	-- Bumped every time BOTH sides become confirmed at once -- the 5s
	-- delayed executeTrade call below captures its own generation number
	-- and only actually swaps if this hasn't moved on since (nothing
	-- un-confirmed/changed the offer/re-confirmed in the meantime).
	ConfirmGeneration: number,
	-- Set the moment this session ends for ANY reason (cancel, disconnect,
	-- completion) -- a still-in-flight 5s delayed execution checks this so
	-- it can never fire a swap for a trade that's already been torn down.
	Cancelled: boolean,
}

-- One incoming request at a time per target (a newer request just
-- overwrites an older unanswered one).
local pendingRequestsByTarget: { [Player]: Player } = {}
local lastRequestAt: { [Player]: number } = {}

-- Cheap per-player debounce shared by UpdateTradeOffer/ConfirmTradeOffer/
-- CancelTrade -- not a theft-prevention measure (none of these can be
-- forged as another player, see this file's header), just stops a
-- scripted client from spamming the server/both clients with rapid-fire
-- pushState broadcasts.
local lastActionAt: { [Player]: number } = {}
local ACTION_DEBOUNCE_SECONDS = 0.15

local function onActionCooldown(player: Player): boolean
	local now = os.clock()
	local last = lastActionAt[player]
	if last and now - last < ACTION_DEBOUNCE_SECONDS then
		return true
	end
	lastActionAt[player] = now
	return false
end

-- Both PlayerA and PlayerB key into the SAME session table.
local activeTradeByPlayer: { [Player]: TradeSession } = {}

-- TheirOffer's items are pre-resolved to plain ItemIds (not raw Uids) --
-- the client only needs ItemDatabase.GetItem(id) to render a read-only
-- card, same treatment AssetIds already got.
local function resolveItemIds(ownerSessionData, uids: { number }): { string }
	local resolved = {}
	for _, uid in uids do
		for _, entry in ownerSessionData.Inventory do
			if entry.Uid == uid then
				table.insert(resolved, entry.ItemId)
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
		MyOffer = { AssetIds = myOffer.AssetIds, ItemUids = myOffer.ItemUids, Cash = myOffer.Cash },
		TheirOffer = {
			AssetIds = theirOfferRaw.AssetIds,
			ItemIds = partnerSessionData and resolveItemIds(partnerSessionData, theirOfferRaw.ItemUids) or {},
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

-- Shown to BOTH sides (not just whoever triggered it) -- silently closing
-- the window with no explanation left the other player guessing whether
-- anything happened at all.
local END_REASON_MESSAGES: { [string]: string } = {
	cancelled = "Trade declined.",
	invalid = "Trade failed -- something changed before it could complete.",
	left = "Trade cancelled -- the other player left.",
	error = "Trade failed -- something went wrong.",
}

local function endTrade(session: TradeSession, reason: string)
	session.Cancelled = true
	activeTradeByPlayer[session.PlayerA] = nil
	activeTradeByPlayer[session.PlayerB] = nil
	tradeStateUpdated:FireClient(session.PlayerA, { Active = false, Reason = reason })
	tradeStateUpdated:FireClient(session.PlayerB, { Active = false, Reason = reason })

	local message = END_REASON_MESSAGES[reason]
	if message then
		systemMessage:FireClient(session.PlayerA, message)
		systemMessage:FireClient(session.PlayerB, message)
	end
end

local function assetsStillValid(giverSessionData, receiverSessionData, assetIds: { string }): boolean
	for _, assetId in assetIds do
		if not giverSessionData.OwnedAssets[assetId] then
			return false
		end
		-- OwnedAssets is a boolean flag, not stackable, for most Estates --
		-- the receiver can't hold a second copy of a type they already own.
		-- Top1Estate/Top2Estate/Top3Estate are the exception (see
		-- AssetManager.MultiOwnableAssetIds) -- those CAN stack, so a
		-- receiver already owning one is still a valid trade.
		if receiverSessionData.OwnedAssets[assetId] and not AssetManager.MultiOwnableAssetIds[assetId] then
			return false
		end
	end
	return true
end

local function ownsAllItems(sessionData, uids: { number }): boolean
	for _, uid in uids do
		local found = false
		for _, entry in sessionData.Inventory do
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

-- Returns the serial number (EstateExistenceManager.luau) that traveled
-- with each removed asset, keyed by assetId -- a traded Estate is the SAME
-- physical copy changing hands, not a newly-minted one, so its permanent
-- serial has to move WITH it to the receiver instead of being left behind
-- (stale on the giver) or dropped entirely (blank on the receiver).
local function pullAssets(sessionData, assetIds: { string }): { [string]: number? }
	local movedSerials: { [string]: number? } = {}
	for _, assetId in assetIds do
		sessionData.OwnedAssets[assetId] = nil
		local equippedIndex = table.find(sessionData.EquippedAssets, assetId)
		if equippedIndex then
			table.remove(sessionData.EquippedAssets, equippedIndex)
		end

		local serials = sessionData.AssetSerialNumbers[assetId]
		if serials and #serials > 0 then
			movedSerials[assetId] = table.remove(serials)
		end
	end
	return movedSerials
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
	if not ownsAllItems(sessionA, session.OfferA.ItemUids) or not ownsAllItems(sessionB, session.OfferB.ItemUids) then
		endTrade(session, "invalid")
		return
	end

	-- Pull items via InventoryManager (not direct table surgery) so
	-- Uid assignment/OwnedItemCounts/InventoryTotalValue stay correct on
	-- both the giving and receiving side automatically, same as every
	-- other place an item moves (selling, rolling, Crate grants).
	local itemIdsFromA = {}
	for _, uid in session.OfferA.ItemUids do
		local removed = InventoryManager.RemoveItem(session.PlayerA, uid)
		if removed then
			table.insert(itemIdsFromA, removed.ItemId)
		end
	end
	local itemIdsFromB = {}
	for _, uid in session.OfferB.ItemUids do
		local removed = InventoryManager.RemoveItem(session.PlayerB, uid)
		if removed then
			table.insert(itemIdsFromB, removed.ItemId)
		end
	end

	local movedSerialsFromA = pullAssets(sessionA, session.OfferA.AssetIds)
	local movedSerialsFromB = pullAssets(sessionB, session.OfferB.AssetIds)

	for _, assetId in session.OfferA.AssetIds do
		sessionB.OwnedAssets[assetId] = true
		local serial = movedSerialsFromA[assetId]
		if serial then
			sessionB.AssetSerialNumbers[assetId] = sessionB.AssetSerialNumbers[assetId] or {}
			table.insert(sessionB.AssetSerialNumbers[assetId], serial)
		end
	end
	for _, assetId in session.OfferB.AssetIds do
		sessionA.OwnedAssets[assetId] = true
		local serial = movedSerialsFromB[assetId]
		if serial then
			sessionA.AssetSerialNumbers[assetId] = sessionA.AssetSerialNumbers[assetId] or {}
			table.insert(sessionA.AssetSerialNumbers[assetId], serial)
		end
	end

	for _, itemId in itemIdsFromA do
		InventoryManager.AddItem(session.PlayerB, itemId)
	end
	for _, itemId in itemIdsFromB do
		InventoryManager.AddItem(session.PlayerA, itemId)
	end

	sessionA.Cash = sessionA.Cash - session.OfferA.Cash + session.OfferB.Cash
	sessionB.Cash = sessionB.Cash - session.OfferB.Cash + session.OfferA.Cash

	activeTradeByPlayer[session.PlayerA] = nil
	activeTradeByPlayer[session.PlayerB] = nil

	AssetManager.PushUpdate(session.PlayerA, sessionA)
	AssetManager.PushUpdate(session.PlayerB, sessionB)
	inventoryUpdated:FireClient(session.PlayerA, sessionA.Inventory)
	inventoryUpdated:FireClient(session.PlayerB, sessionB.Inventory)
	-- A traded-away equipped item is force-unequipped by InventoryManager.
	-- RemoveItem already (mutates EquippedItemUids), this just tells the
	-- client so its equip UI can't drift from reality.
	equippedItemsUpdated:FireClient(session.PlayerA, sessionA.EquippedItemUids)
	equippedItemsUpdated:FireClient(session.PlayerB, sessionB.EquippedItemUids)
	StatsManager.Recompute(session.PlayerA)
	StatsManager.Recompute(session.PlayerB)
	LeaderboardManager.MarkDirty(session.PlayerA)
	LeaderboardManager.MarkDirty(session.PlayerB)

	tradeStateUpdated:FireClient(session.PlayerA, { Active = false, Completed = true })
	tradeStateUpdated:FireClient(session.PlayerB, { Active = false, Completed = true })
	systemMessage:FireClient(session.PlayerA, "Trade completed!")
	systemMessage:FireClient(session.PlayerB, "Trade completed!")
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
		OfferA = { AssetIds = {}, ItemUids = {}, Cash = 0 },
		OfferB = { AssetIds = {}, ItemUids = {}, Cash = 0 },
		ConfirmedA = false,
		ConfirmedB = false,
		ConfirmGeneration = 0,
		Cancelled = false,
	}
	activeTradeByPlayer[requester] = session
	activeTradeByPlayer[player] = session

	pushState(session)
end)

-- No real player will ever legitimately offer more than this many distinct
-- Assets/Items in one trade -- rejecting oversized payloads outright stops
-- a scripted client from making the server chew through a huge garbage
-- array on every single offer update.
local MAX_OFFER_ENTRIES = 100

updateTradeOffer.OnServerEvent:Connect(function(player: Player, payload: { AssetIds: { string }, ItemUids: { number }, Cash: number })
	local session = activeTradeByPlayer[player]
	if not session then
		return
	end
	if onActionCooldown(player) then
		return
	end
	if
		typeof(payload) ~= "table"
		or typeof(payload.AssetIds) ~= "table"
		or typeof(payload.ItemUids) ~= "table"
		or typeof(payload.Cash) ~= "number"
		or #payload.AssetIds > MAX_OFFER_ENTRIES
		or #payload.ItemUids > MAX_OFFER_ENTRIES
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

	local itemUids = {}
	local seenItems: { [number]: boolean } = {}
	for _, uid in payload.ItemUids do
		if typeof(uid) == "number" and not seenItems[uid] then
			local owned = false
			for _, entry in playerSessionData.Inventory do
				if entry.Uid == uid then
					owned = true
					break
				end
			end
			if owned then
				seenItems[uid] = true
				table.insert(itemUids, uid)
			end
		end
	end

	local isA = session.PlayerA == player
	if isA then
		session.OfferA = { AssetIds = assetIds, ItemUids = itemUids, Cash = cash }
	else
		session.OfferB = { AssetIds = assetIds, ItemUids = itemUids, Cash = cash }
	end
	-- Changing either side's offer un-confirms both -- if I already agreed
	-- and the other side changes something, I need to look again.
	session.ConfirmedA = false
	session.ConfirmedB = false

	pushState(session)
end)

-- Both sides have to stay confirmed for a continuous hold, not just
-- momentarily both true at once -- gives either side a last-second window
-- to back out (cancel/change the offer) before anything actually swaps,
-- instead of the trade executing the instant the 2nd Confirm lands.
local CONFIRM_HOLD_SECONDS = 5

-- Toggle, not a one-way flag -- pressing the button again while already
-- confirmed (its label swaps to "Cancel" client-side) un-confirms just
-- THIS player, without touching the offer or ending the trade, unlike
-- Decline (cancelTrade below, which ends the whole session for both).
confirmTradeOffer.OnServerEvent:Connect(function(player: Player)
	local session = activeTradeByPlayer[player]
	if not session then
		return
	end
	if onActionCooldown(player) then
		return
	end

	if session.PlayerA == player then
		session.ConfirmedA = not session.ConfirmedA
	else
		session.ConfirmedB = not session.ConfirmedB
	end

	if session.ConfirmedA and session.ConfirmedB then
		-- Own generation number for THIS confirm -- if the offer changes
		-- (which resets both ConfirmedA/B to false) or either side
		-- re-confirms again before the hold elapses (bumping this same
		-- generation further), this specific delayed call recognizes it's
		-- stale and never executes, instead of every overlapping confirm
		-- scheduling its own redundant (and potentially double-executing)
		-- swap.
		session.ConfirmGeneration += 1
		local generation = session.ConfirmGeneration
		task.delay(CONFIRM_HOLD_SECONDS, function()
			if session.Cancelled or session.ConfirmGeneration ~= generation then
				return
			end
			if session.ConfirmedA and session.ConfirmedB then
				executeTrade(session)
			end
		end)
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
	lastActionAt[player] = nil
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
