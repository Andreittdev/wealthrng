-- Single list of remote names shared by RemotesBootstrap (server) and every
-- client/server reference, so a typo'd string can't silently create a
-- mismatched pair of remotes.

local RemoteNames = {
	Events = {
		"RollRequested", -- client -> server, no payload
		"RollResult", -- server -> client, payload: Item, SpecialRollTiers (see SpecialRollStateUpdated
		-- below -- piggybacked on the SAME fire as this roll's item so RollPanel.luau can apply the
		-- progress-badge snapshot at the exact moment IT shows this specific roll's reveal, not
		-- before), isSpecial (boolean -- true only when this roll came from a claimed Special Roll
		-- tier, not a normal roll; RollPanel.luau always shows the reveal for these even while Hide
		-- Rolls is on, since they're the rare/exciting ones worth seeing regardless)
		"SellItem", -- client -> server, payload: uid
		"InventoryUpdated", -- server -> client, payload: { {Uid, ItemId} }
		"EquipItem", -- client -> server, payload: uid
		"UnequipItem", -- client -> server, payload: uid
		"EquippedItemsUpdated", -- server -> client, payload: { uid }
		"StatsUpdated", -- server -> client, payload: { Cash, NetWorth, Title, IsVIP, OwnsAutoRoll, OwnsAutoClaim, OwnsLuckPass, OwnsUltraLuckPass, OwnsFastRoll, OwnsDoubleCash, BattleRankPoints, FriendBonusPercent, ItemsIncomePerSecond, AssetsIncomePerMinute }
		"BuyAsset", -- client -> server, payload: assetId
		"EquipAsset", -- client -> server, payload: assetId
		"UnequipAsset", -- client -> server, payload: assetId
		"AssetUpdated", -- server -> client, payload: { Owned: {[assetId]: boolean}, Equipped: {assetId} }
		"BuyInvestment", -- client -> server, payload: investmentId, quantity (1/10/100 from the shop buttons)
		"SellInvestment", -- client -> server, payload: uid, quantity (units to sell -- omit/invalid = sell all of that entry)
		"InvestmentUpdated", -- server -> client, payload: { {Uid, Id, PurchasedAt, Quantity} }
		"BuyPotion", -- client -> server, payload: potionId
		"PotionUpdated", -- server -> client, payload: { [potionId] = expiresAt }
		"RequestTrade", -- client -> server, payload: target (Player) -- from the sidebar Trade button's player picker
		"TradeRequestReceived", -- server -> client, payload: fromPlayer (Player)
		"RespondTradeRequest", -- client -> server, payload: requester (Player), accepted (boolean)
		"TradeStateUpdated", -- server -> client, payload: TradeState (see TradeManager.luau)
		"UpdateTradeOffer", -- client -> server, payload: { AssetIds: {string}, InvestmentUids: {number}, Cash: number }
		"ConfirmTradeOffer", -- client -> server, no payload
		"CancelTrade", -- client -> server, no payload
		"SetAutoSellDuplicate", -- client -> server, payload: rarity (string), enabled (boolean)
		"AutoSellDuplicatesUpdated", -- server -> client, payload: { [rarity]: boolean }
		"SetPreference", -- client -> server, payload: key ("Music"/"SFX"/"VFX"), enabled (boolean)
		"PreferencesUpdated", -- server -> client, payload: { [key]: boolean }
		"SystemMessage", -- server -> client, payload: text (string, supports rich text) -- shown via
		-- TextChatService AND as a toast (NotificationToast.luau). Fired at one player only for rank
		-- changes, purchases/sells (Asset/Investment/Item/Potion/Upgrade), gamepass grants, and Group
		-- Rewards claims; fired to EVERYONE (FireAllClients) for RollManager.luau's Ultra-item unlock callout.
		"BuyUpgrade", -- client -> server, payload: trackId (string)
		"UpgradesUpdated", -- server -> client, payload: { [trackId]: level }
		"ClientReady", -- client -> server, no payload -- fired once MainUI has built every panel and
		-- connected every OnClientEvent listener, so the server's "here's your saved data" initial
		-- pushes (Inventory/Assets/Investments/etc.) can't fire before anything is listening for them.
		"PlayerRankUpdated", -- server -> client, payload: boardIndex (number), label (string), rank (number), value (number)
		-- -- fired per board whenever LeaderboardManager's 60s refresh finds this player in that
		-- board's top 100; drives the always-visible bottom-of-screen RankHUD.luau.
		"SetAutoRoll", -- client -> server, payload: enabled (boolean) -- rejected server-side unless the
		-- player owns the Auto Roll gamepass (AutoRollConfig.GamepassId).
		"AutoRollUpdated", -- server -> client, payload: enabled (boolean) -- echoes the actual server-side
		-- state back (e.g. after a rejected enable) so the client toggle can't drift from reality.
		"SetAutoClaim", -- client -> server, payload: enabled (boolean) -- rejected server-side unless the
		-- player owns the Auto Claim gamepass (AutoClaimConfig.GamepassId). Unlike Auto Roll (a pure
		-- client-driven loop, no server memory needed), Auto Claim's actual claiming happens in
		-- RollManager.luau's server-side per-second loop, so this toggle IS persisted (session.AutoClaimEnabled).
		"AutoClaimUpdated", -- server -> client, payload: enabled (boolean) -- echoes the actual persisted
		-- session.AutoClaimEnabled, pushed on join and again after a successful SetAutoClaim toggle.
		"ClaimGroupReward", -- client -> server, no payload -- rejected server-side unless the player is
		-- in GroupRewardsConfig.GroupId and hasn't already claimed it this save.
		"GroupRewardStateUpdated", -- server -> client, payload: claimed (boolean) -- current
		-- session.ClaimedGroupReward, pushed on join and again after a successful claim.
		"ClaimDailyReward", -- client -> server, no payload -- rejected server-side if still on cooldown
		-- (session.LastDailyRewardClaimAt + DailyRewardsConfig.ClaimIntervalSeconds).
		"DailyRewardStateUpdated", -- server -> client, payload: { Day (1-7), CanClaim (boolean),
		-- SecondsRemaining (number) } -- pushed on join and again after a successful claim.
		"RollSpecial", -- client -> server, payload: tierId (string, e.g. "Golden") -- claims that
		-- Special Roll tier (see SpecialRollConfig.luau); rejected server-side unless
		-- session.SpecialRollProgress[tierId] has reached that tier's own Threshold. Golden/Diamond/
		-- Ruby/Emerald progress independently and simultaneously -- more than one can be claimable
		-- at once.
		"SpecialRollStateUpdated", -- server -> client, payload: { { TierId, TierName, Threshold,
		-- Color, Image, Progress, Available (boolean) }, ... } -- one entry per tier. ONLY fired once,
		-- on join (see Main.server.luau's sendInitialState) -- every subsequent update rides along on
		-- RollResult's 2nd argument instead (see its own comment above), so the client applies each
		-- snapshot exactly when it shows that specific roll's reveal, not before.
		"JoinBattleQueue", -- client -> server, no payload -- LARP Battles (BattleManager.luau)
		-- "Multiplayer" card, fired from BattlePanel.luau's zone menu. Matched against the next
		-- other queued player automatically -- no opponent picking, no bot fallback (see
		-- JoinCasualBattle below for that).
		"LeaveBattleQueue", -- client -> server, no payload -- fired when the player closes the
		-- menu or walks out of the zone while still queued.
		"BattleQueueUpdated", -- server -> client, payload: { InQueue: boolean, Count: number } --
		-- echoes real queue membership/size back so the client's "1/2 Wait for opponent" state
		-- can't drift from reality.
		"JoinCasualBattle", -- client -> server, no payload -- LARP Battles "Casual" card: resolves
		-- INSTANTLY against the "Practice Dummy" bot, no queueing at all. Counts toward the weekly
		-- Most Points leaderboard, deliberately does NOT touch ranked BattleRankPoints (see
		-- BattleManager.luau's runBotBattle).
		"BattleResult", -- server -> client, payload: { Opponent: string, WinsMine: number,
		-- WinsOpponent: number, Won: boolean?, Categories: { { Name: string, Outcome: number } } }
		-- -- Won is nil on a draw (no category winner reached 2/3). Outcome: 1 = this player won that
		-- category, 2 = opponent won it, 0 = tied.
		"RedeemCode", -- client -> server, payload: code (string) -- CodesProximityPanel.luau's Redeem
		-- button, fired from the "Codes" plaza marker. Validated + granted server-side
		-- (CodesManager.luau/CodesConfig.luau); case-insensitive, one redemption per code per save.
		"CodeRedeemResult", -- server -> client, payload: success (boolean), message (string) -- direct
		-- reply to THIS redeem attempt (shown inline in the panel), separate from the general
		-- SystemMessage toast a successful redeem also fires.
		"RobuxManShowChoices", -- server -> client, payload: { { Id: string, Text: string }, ... } --
		-- fired at just the one player who triggered Robux Man's "Talk" prompt, right after his
		-- greeting bubble, so only they see the small reply-choice buttons (MapBuilder.luau/
		-- RobuxManDialogChoices.luau).
		"RobuxManChoiceSelected", -- client -> server, payload: id (string) -- which choice button was
		-- clicked; server replies with the matching bubble line (or nothing, for "End the
		-- conversation") and the client hides the choice buttons either way.
	},
	Functions = {},
}

return RemoteNames
