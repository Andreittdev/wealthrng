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
		"StatsUpdated", -- server -> client, payload: { Cash, NetWorth, Title, IsVIP, OwnsAutoRoll, ItemsIncomePerSecond, AssetsIncomePerMinute }
		"BuyAsset", -- client -> server, payload: assetId
		"SellAsset", -- client -> server, payload: assetId
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
		"SystemMessage", -- server -> client, payload: text (string) -- shown via TextChatService AND as a
		-- toast (NotificationToast.luau), this player only. Fired for rank changes, purchases/sells
		-- (Asset/Investment/Item/Potion/Upgrade), gamepass grants, and Group Rewards claims.
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
		"ClaimGroupReward", -- client -> server, no payload -- rejected server-side unless the player is
		-- in GroupRewardsConfig.GroupId and hasn't already claimed it this save.
		"GroupRewardStateUpdated", -- server -> client, payload: claimed (boolean) -- current
		-- session.ClaimedGroupReward, pushed on join and again after a successful claim.
		"ClaimDailyReward", -- client -> server, no payload -- rejected server-side if still on cooldown
		-- (session.LastDailyRewardClaimAt + DailyRewardsConfig.ClaimIntervalSeconds).
		"DailyRewardStateUpdated", -- server -> client, payload: { Day (1-7), CanClaim (boolean),
		-- SecondsRemaining (number) } -- pushed on join and again after a successful claim.
		"ClaimPlaytimeReward", -- client -> server, payload: milestoneIndex (number, 1-based index into
		-- PlaytimeRewardsConfig.Milestones) -- rejected server-side unless PlaytimeSeconds has reached
		-- that milestone's ThresholdSeconds and it hasn't already been claimed.
		"PlaytimeRewardStateUpdated", -- server -> client, payload: { PlaytimeSeconds (number),
		-- Claimed: {[milestoneIndex]: true}, CycleStartSeconds (number) } -- pushed on join, every ~5s
		-- while online (so each milestone card's countdown keeps moving), and again after a successful
		-- claim. CycleStartSeconds advances (and Claimed resets) once the whole ladder is claimed, so
		-- it loops instead of being a one-time list.
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
	},
	Functions = {},
}

return RemoteNames
