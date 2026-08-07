-- LARP Battles: BattlePanel.luau shows a 3-card zone menu (Casual/
-- Multiplayer/Rewards) while standing near the physical marker (MapBuilder's
-- black line, where the old Next Update board used to be). "Casual" fights
-- the bot instantly (see runBotBattle); "Multiplayer" queues for a real 2nd
-- player, matched automatically the moment one joins. Either way, their
-- best-owned item in 3 categories is compared -- best of 3 wins:
--   - Best Roll item, by RARITY (highest tier owned, not Value)
--   - Best Estate (Asset), by Price
--   - Best Investment, by current appreciated value
-- A tied category (including both sides owning nothing in it) counts
-- toward neither player -- with only 3 categories, that can produce an
-- overall 1-1 draw, which awards no point to either side.
-- Winner gets +1 Point toward the weekly "Most Points" leaderboard (see
-- BattlePointsConfig.luau for why the week-reset math lives in its own
-- shared module instead of here).
--
-- Each category's actual winning item (Name + Image) is sent to the client
-- alongside the win/loss outcome, not just the outcome number -- BattlePanel
-- .luau uses that to play a "spin through your inventory, then land on the
-- best item" reveal per category instead of a flat instant result.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local InvestmentDatabase = require(ReplicatedStorage.Modules.InvestmentDatabase)
local BattlePointsConfig = require(ReplicatedStorage.Modules.BattlePointsConfig)
local BattleRankConfig = require(ReplicatedStorage.Modules.BattleRankConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)

local joinBattleQueue = RemotesBootstrap:WaitForChild("JoinBattleQueue")
local leaveBattleQueue = RemotesBootstrap:WaitForChild("LeaveBattleQueue")
local battleQueueUpdated = RemotesBootstrap:WaitForChild("BattleQueueUpdated")
local joinCasualBattle = RemotesBootstrap:WaitForChild("JoinCasualBattle")
local battleResult = RemotesBootstrap:WaitForChild("BattleResult")
local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")

local BattleManager = {}

-- Held after the queue hits 2/2 (see joinBattleQueue below), so both
-- players get a "Match Found!" beat instead of jumping straight from
-- "1/2 Waiting" to the reveal starting with no acknowledgment.
local MATCH_FOUND_PAUSE_SECONDS = 1.5

local rarityRank: { [string]: number } = {}
for index, rarity in RarityConfig.Order do
	rarityRank[rarity] = index
end

local queue: { Player } = {}

-- Both matched players are removed from `queue` the instant #queue hits
-- 2/2, before the MATCH_FOUND_PAUSE_SECONDS beat and runBattle actually
-- run -- during that ~1.5s window, joinBattleQueue's "already queued" guard
-- (table.find(queue, player)) no longer sees them, so without this separate
-- set either player could re-join and get matched into a SECOND concurrent
-- battle before the first one resolves, stacking more than one Battle
-- Point/RP change per "tick." Cleared the moment runBattle (or the
-- disconnect-during-pause fallback) finishes handling that pairing.
local matchedPlayers: { [Player]: boolean } = {}

-- { Name, Image } for anything with those 2 fields (ItemDatabase.Item,
-- AssetDatabase.Asset, InvestmentDatabase.Investment all qualify) -- nil
-- passes through as nil (category owned nothing), which the client reads
-- as "Nothing owned" instead of a broken image.
local function describeItem(entry: { Name: string, Image: string }?)
	if not entry then
		return nil
	end
	return { Name = entry.Name, Image = entry.Image }
end

local function getBestRollItem(session): (number, ItemDatabase.Item?)
	local bestRank, bestItem = 0, nil
	for _, entry in session.Inventory do
		local item = ItemDatabase.GetItem(entry.ItemId)
		if item then
			local rank = rarityRank[item.Rarity] or 0
			if rank > bestRank then
				bestRank, bestItem = rank, item
			end
		end
	end
	return bestRank, bestItem
end

local function getBestAsset(session): (number, AssetDatabase.Asset?)
	local bestPrice, bestAsset = 0, nil
	for id, owned in session.OwnedAssets do
		if owned then
			local asset = AssetDatabase.GetAsset(id)
			if asset and asset.Price > bestPrice then
				bestPrice, bestAsset = asset.Price, asset
			end
		end
	end
	return bestPrice, bestAsset
end

local function getBestInvestment(session): (number, InvestmentDatabase.Investment?)
	local bestValue, bestInvestment = 0, nil
	local now = os.time()
	for _, entry in session.Investments do
		local value = InvestmentDatabase.ComputeEntryValue(entry, now)
		if value > bestValue then
			bestValue = value
			bestInvestment = InvestmentDatabase.GetInvestment(entry.Id)
		end
	end
	return bestValue, bestInvestment
end

-- One entry per real database, each a random pick with its own Value --
-- the "Practice Dummy" bot flexes a real, coherent item/value pair instead
-- of a bare random number with no matching visual.
--
-- `difficulty` restricts the pick to a strict THIRD of that database --
-- "hard" = top third, "medium" = middle third, "easy" = bottom third.
-- "medium" used to mean "no filter at all" (the full, unrestricted
-- database), which let a Gold-tier bot ("medium") occasionally out-flex a
-- Platinum/Diamond-tier bot ("hard") or land as low as a Bronze/Silver-tier
-- bot ("easy") -- contradicting the whole point of tying item quality to
-- the bot's named tier. Three strictly-ordered, non-overlapping bands fix
-- that: easy's ceiling can never reach medium's floor, medium's ceiling can
-- never reach hard's floor. Deliberately undocumented anywhere a player can
-- read it; the whole point is that it's discovered by playing, not looked up.
export type BotDifficulty = "hard" | "medium" | "easy"

local HARD_ROLL_RARITIES = { Ultra = true, Luxury = true }
local MEDIUM_ROLL_RARITIES = { Epic = true, Legendary = true }
local EASY_ROLL_RARITIES = { Common = true, Rare = true }

local function pickRandomRollItem(difficulty: BotDifficulty): (number, ItemDatabase.Item?)
	local all = {}
	for _, item in ItemDatabase.GetAllItems() do
		if
			(difficulty == "hard" and HARD_ROLL_RARITIES[item.Rarity])
			or (difficulty == "medium" and MEDIUM_ROLL_RARITIES[item.Rarity])
			or (difficulty == "easy" and EASY_ROLL_RARITIES[item.Rarity])
		then
			table.insert(all, item)
		end
	end
	if #all == 0 then
		return 0, nil
	end

	-- A flat uniform pick across the whole rarity band let a bot's "best
	-- item" land on the CHEAPEST possible entry in that band just as often
	-- as the priciest one (e.g. "easy" spans Cap at $20 up to ~$780 --
	-- getting Cap made a $500M-Net-Worth bot's flex look absurd). Sort by
	-- Value and only pick from the top half of the band instead, so the
	-- item at least reads as a plausible "best" within what that tier is
	-- allowed to flex.
	table.sort(all, function(a, b)
		return a.Value > b.Value
	end)
	local topHalfCount = math.max(1, math.floor(#all / 2))

	local item = all[math.random(1, topHalfCount)]
	return rarityRank[item.Rarity] or 0, item
end

-- Sorts a list of { Price: number } entries (highest first) and keeps only
-- one strict third -- shared by pickRandomAsset/pickRandomInvestment.
-- "top"/"middle"/"bottom" partition the list into 3 non-overlapping,
-- strictly price-ordered bands (any leftover entries from a length not
-- divisible by 3 land in "middle", which only makes its band wider, never
-- overlapping the other two).
local function thirdByPrice(entries: { { Price: number } }, band: "top" | "middle" | "bottom"): { { Price: number } }
	table.sort(entries, function(a, b)
		return a.Price > b.Price
	end)
	local count = math.floor(#entries / 3)
	if count == 0 then
		return entries
	end
	local startIndex, endIndex
	if band == "top" then
		startIndex, endIndex = 1, count
	elseif band == "bottom" then
		startIndex, endIndex = #entries - count + 1, #entries
	else
		startIndex, endIndex = count + 1, #entries - count
	end
	local slice = {}
	for i = startIndex, endIndex do
		table.insert(slice, entries[i])
	end
	return slice
end

local function pickRandomAsset(difficulty: BotDifficulty): (number, AssetDatabase.Asset?)
	local all = {}
	for _, asset in AssetDatabase.GetAllAssets() do
		-- NotPurchasable assets (the weekly leaderboard's exclusive Top 3
		-- reward Estates) must never show up as a bot's flex -- they're
		-- meant to be unobtainable outside that leaderboard, and they're
		-- priced high enough to otherwise dominate the "hard" band.
		if not asset.NotPurchasable then
			table.insert(all, asset)
		end
	end
	if difficulty == "hard" then
		all = thirdByPrice(all, "top") :: any
	elseif difficulty == "medium" then
		all = thirdByPrice(all, "middle") :: any
	elseif difficulty == "easy" then
		all = thirdByPrice(all, "bottom") :: any
	end
	if #all == 0 then
		return 0, nil
	end
	local asset = all[math.random(1, #all)]
	return asset.Price, asset
end

local function pickRandomInvestment(difficulty: BotDifficulty): (number, InvestmentDatabase.Investment?)
	local all = {}
	for _, investment in InvestmentDatabase.GetAllInvestments() do
		table.insert(all, investment)
	end
	if difficulty == "hard" then
		all = thirdByPrice(all, "top") :: any
	elseif difficulty == "medium" then
		all = thirdByPrice(all, "middle") :: any
	elseif difficulty == "easy" then
		all = thirdByPrice(all, "bottom") :: any
	end
	if #all == 0 then
		return 0, nil
	end
	local investment = all[math.random(1, #all)]
	return investment.Price, investment
end

-- 1 = a wins this category, 2 = b wins it, 0 = tied (including both zero).
local function compareCategory(a: number, b: number): number
	if a > b then
		return 1
	elseif b > a then
		return 2
	end
	return 0
end

local function runBattle(playerA: Player, playerB: Player)
	local sessionA = DataManager.Get(playerA)
	local sessionB = DataManager.Get(playerB)
	if not sessionA or not sessionB then
		return
	end

	local rollRankA, rollItemA = getBestRollItem(sessionA)
	local rollRankB, rollItemB = getBestRollItem(sessionB)
	local assetPriceA, assetA = getBestAsset(sessionA)
	local assetPriceB, assetB = getBestAsset(sessionB)
	local investValueA, investA = getBestInvestment(sessionA)
	local investValueB, investB = getBestInvestment(sessionB)

	local categories = {
		{ Name = "Best Roll Item", A = rollRankA, B = rollRankB, ItemA = describeItem(rollItemA), ItemB = describeItem(rollItemB) },
		{ Name = "Best Estate", A = assetPriceA, B = assetPriceB, ItemA = describeItem(assetA), ItemB = describeItem(assetB) },
		{ Name = "Best Investment", A = investValueA, B = investValueB, ItemA = describeItem(investA), ItemB = describeItem(investB) },
	}

	local winsA, winsB = 0, 0
	local outcomesForA, outcomesForB = {}, {}
	for _, category in categories do
		local outcome = compareCategory(category.A, category.B)
		if outcome == 1 then
			winsA += 1
		elseif outcome == 2 then
			winsB += 1
		end

		table.insert(outcomesForA, { Name = category.Name, Outcome = outcome, MyItem = category.ItemA, OpponentItem = category.ItemB })
		-- Flipped for B's client -- 1/2 mean "this player"/"the opponent"
		-- from the RECEIVING client's point of view, not a fixed A/B.
		local flipped = outcome
		if flipped == 1 then
			flipped = 2
		elseif flipped == 2 then
			flipped = 1
		end
		table.insert(outcomesForB, { Name = category.Name, Outcome = flipped, MyItem = category.ItemB, OpponentItem = category.ItemA })
	end

	local winner: Player? = nil
	if winsA > winsB then
		winner = playerA
	elseif winsB > winsA then
		winner = playerB
	end

	if winner then
		local winnerSession = DataManager.Get(winner)
		if winnerSession then
			BattlePointsConfig.EnsureCurrentWeek(winnerSession)
			winnerSession.BattlePoints += 1
			LeaderboardManager.MarkDirty(winner)
		end
	end

	-- NOT `winner ~= nil and winner == playerA or nil` -- that idiom breaks
	-- the moment the middle expression evaluates to `false` (the loser's
	-- case), since `x and false or nil` always collapses to `nil`, which
	-- would misreport a loss as a draw on the client. Plain if/else instead.
	local wonA: boolean? = nil
	if winner == playerA then
		wonA = true
	elseif winner == playerB then
		wonA = false
	end
	local wonB: boolean? = nil
	if winner == playerB then
		wonB = true
	elseif winner == playerA then
		wonB = false
	end

	-- Ranked RP (BattleRankConfig.luau) -- separate from the +1 weekly
	-- Point above, permanent, applies to BOTH players (not just the
	-- winner) since a loss also costs RP.
	sessionA.BattleRankPoints = BattleRankConfig.ApplyRPChange(sessionA.BattleRankPoints, wonA)
	sessionB.BattleRankPoints = BattleRankConfig.ApplyRPChange(sessionB.BattleRankPoints, wonB)
	StatsManager.Recompute(playerA)
	StatsManager.Recompute(playerB)

	local netWorthA = StatsManager.ComputeNetWorth(playerA)
	local netWorthB = StatsManager.ComputeNetWorth(playerB)

	battleResult:FireClient(playerA, {
		Opponent = playerB.Name,
		OpponentUserId = playerB.UserId,
		MyNetWorth = netWorthA,
		OpponentNetWorth = netWorthB,
		WinsMine = winsA,
		WinsOpponent = winsB,
		Won = wonA,
		Categories = outcomesForA,
	})
	battleResult:FireClient(playerB, {
		Opponent = playerA.Name,
		OpponentUserId = playerA.UserId,
		MyNetWorth = netWorthB,
		OpponentNetWorth = netWorthA,
		WinsMine = winsB,
		WinsOpponent = winsA,
		Won = wonB,
		Categories = outcomesForB,
	})

	if winner then
		local loser = winner == playerA and playerB or playerA
		systemMessage:FireClient(winner, string.format("You won the LARP Battle vs %s! +1 Point, +%d RP", loser.Name, BattleRankConfig.WinRP))
		systemMessage:FireClient(loser, string.format("You lost the LARP Battle vs %s. %d RP", winner.Name, BattleRankConfig.LossRP))
	else
		systemMessage:FireClient(playerA, string.format("LARP Battle vs %s ended in a draw.", playerB.Name))
		systemMessage:FireClient(playerB, string.format("LARP Battle vs %s ended in a draw.", playerA.Name))
	end
end

-- "Casual" card (BattlePanel.luau's zone menu) -- resolves INSTANTLY
-- against a fake bot opponent flexing a real random item/Asset/Investment
-- (see pickRandom* above), no queueing at all. Also doubles as the
-- practice/solo-testing path. The bot's NAME (and its flexed Net
-- Worth/item quality, see below) is themed off the player's own current
-- rank (BattleRankConfig), so practicing against a "Bronze Warrior" vs. a
-- "Diamond Legend" echoes the rank display BattlePanel.luau's menu already
-- shows, instead of being an unrelated random flavor.
local BOT_NAMES_BY_TIER = {
	Bronze = "Bronze Warrior",
	Silver = "Silver Fighter",
	Gold = "Gold Gladiator",
	Platinum = "Platinum Champion",
	Diamond = "Diamond Legend",
}
local DEFAULT_BOT_NAME = "Practice Dummy"

-- Bot's flexed Net Worth is randomized WITHIN its own named tier's Net
-- Worth band (BattleRankConfig.Tiers), not around the player's own Net
-- Worth -- a "Bronze Warrior" should flex a Bronze-ish number, a "Diamond
-- Legend" a Diamond-ish one, regardless of what the player themselves has.
-- Top tier (Diamond) has no upper gate, so it gets a synthetic spread
-- (1x-3x its floor) instead of an unbounded range.
local function getBotNetWorthRange(tierName: string): (number, number)
	local tiers = BattleRankConfig.Tiers
	for index, tier in tiers do
		if tier.Name == tierName then
			local nextTier = tiers[index + 1]
			if nextTier then
				return tier.MinNetWorth, nextTier.MinNetWorth
			end
			return tier.MinNetWorth, tier.MinNetWorth * 3
		end
	end
	return 0, 1000000
end

-- Item quality now tracks the bot's OWN named tier (BOT_NAMES_BY_TIER
-- above), not a hidden curve based on the player's Net Worth -- a "Bronze
-- Warrior" flexes weak items, a "Gold Gladiator" a real middle ground, a
-- "Diamond Legend" top-end ones, matching what its name/Net Worth already
-- implies instead of contradicting it. "hard"/"medium"/"easy" = top/middle/
-- bottom THIRD of the pool (see pickRandomRollItem/thirdByPrice above) --
-- naming carried over from when this was a difficulty curve, "hard" still
-- just means "the bot flexes the HARD-to-beat, top-end stuff."
local BOT_ITEM_DIFFICULTY_BY_TIER: { [string]: BotDifficulty } = {
	Bronze = "easy",
	Silver = "easy",
	Gold = "medium",
	Platinum = "hard",
	Diamond = "hard",
}

local function runBotBattle(player: Player)
	local session = DataManager.Get(player)
	if not session then
		return
	end

	local rollRank, rollItem = getBestRollItem(session)
	local assetPrice, asset = getBestAsset(session)
	local investValue, investment = getBestInvestment(session)

	local myNetWorth = StatsManager.ComputeNetWorth(player)
	local myTier = BattleRankConfig.GetTier(session.BattleRankPoints, myNetWorth)
	local botName = BOT_NAMES_BY_TIER[myTier.Name] or DEFAULT_BOT_NAME
	local difficulty = BOT_ITEM_DIFFICULTY_BY_TIER[myTier.Name] or "medium"

	local botRollRank, botRollItem = pickRandomRollItem(difficulty)
	local botAssetPrice, botAsset = pickRandomAsset(difficulty)
	local botInvestValue, botInvestment = pickRandomInvestment(difficulty)

	local categories = {
		{ Name = "Best Roll Item", Mine = rollRank, Bot = botRollRank, MyItem = describeItem(rollItem), BotItem = describeItem(botRollItem) },
		{ Name = "Best Estate", Mine = assetPrice, Bot = botAssetPrice, MyItem = describeItem(asset), BotItem = describeItem(botAsset) },
		{ Name = "Best Investment", Mine = investValue, Bot = botInvestValue, MyItem = describeItem(investment), BotItem = describeItem(botInvestment) },
	}

	local winsMine, winsBot = 0, 0
	local outcomes = {}
	for _, category in categories do
		local outcome = compareCategory(category.Mine, category.Bot)
		if outcome == 1 then
			winsMine += 1
		elseif outcome == 2 then
			winsBot += 1
		end
		table.insert(outcomes, { Name = category.Name, Outcome = outcome, MyItem = category.MyItem, OpponentItem = category.BotItem })
	end

	local won: boolean? = nil
	if winsMine > winsBot then
		won = true
		BattlePointsConfig.EnsureCurrentWeek(session)
		session.BattlePoints += 1
	elseif winsBot > winsMine then
		won = false
	end

	-- Now also affects BattleRankPoints, per explicit request -- same
	-- ApplyRPChange formula the real Multiplayer path uses (win/loss/draw),
	-- so Casual is no longer risk-free for rank. MarkDirty unconditionally
	-- (not just on a win) since RP can change either way now, unlike the
	-- weekly Points counter above which only ever increments on a win.
	session.BattleRankPoints = BattleRankConfig.ApplyRPChange(session.BattleRankPoints, won)
	LeaderboardManager.MarkDirty(player)

	-- No real bot account to read a net worth from -- fabricate one that
	-- matches the bot's OWN named tier (see getBotNetWorthRange above),
	-- not the player's.
	local minBotNetWorth, maxBotNetWorth = getBotNetWorthRange(myTier.Name)
	local botNetWorth = math.floor(minBotNetWorth + math.random() * (maxBotNetWorth - minBotNetWorth))

	battleResult:FireClient(player, {
		Opponent = botName,
		OpponentUserId = 0, -- sentinel: BattlePanel.luau shows a bot placeholder instead of an rbxthumb avatar
		MyNetWorth = myNetWorth,
		OpponentNetWorth = botNetWorth,
		WinsMine = winsMine,
		WinsOpponent = winsBot,
		Won = won,
		Categories = outcomes,
	})
end

local function removeFromQueue(player: Player)
	local index = table.find(queue, player)
	if index then
		table.remove(queue, index)
	end
end

-- Server-side cooldown for BOTH battle entry points below -- neither
-- runBattle nor runBotBattle yields on anything client-pacing-dependent
-- (no server-side wait matching the client's ~5s spin+reveal animation),
-- so without this a modified client could fire either remote in a tight
-- loop for unbounded BattleRankPoints and weekly-leaderboard Points --
-- worth real, otherwise-unobtainable Top1Estate/Top2Estate rewards. Same
-- `os.clock()`-keyed pattern as RollManager's lastRollAt (immune to a
-- client claiming a different cooldown than what actually elapsed).
local lastBattleJoinAt: { [Player]: number } = {}
local BATTLE_JOIN_COOLDOWN_SECONDS = 4

local function onBattleJoinCooldown(player: Player): boolean
	local nowClock = os.clock()
	local last = lastBattleJoinAt[player]
	if last and nowClock - last < BATTLE_JOIN_COOLDOWN_SECONDS then
		return true
	end
	lastBattleJoinAt[player] = nowClock
	return false
end

-- "Multiplayer" card -- a real, genuine wait for a 2nd player, no bot
-- fallback (that's "Casual"'s job, see joinCasualBattle below). Fires
-- battleQueueUpdated with the current queue size both times so the
-- client's "1/2 Wait for opponent" text can't drift from reality.
joinBattleQueue.OnServerEvent:Connect(function(player: Player)
	if table.find(queue, player) or matchedPlayers[player] then
		return
	end
	if not DataManager.Get(player) then
		return
	end
	if onBattleJoinCooldown(player) then
		return
	end

	table.insert(queue, player)
	battleQueueUpdated:FireClient(player, { InQueue = true, Count = #queue })

	if #queue >= 2 then
		local playerA = table.remove(queue, 1) :: Player
		local playerB = table.remove(queue, 1) :: Player
		matchedPlayers[playerA] = true
		matchedPlayers[playerB] = true
		-- Briefly show "2/2" to both before actually starting -- a beat of
		-- "Match Found!" instead of jumping straight from "1/2 Waiting" to
		-- the reveal with no acknowledgment a 2nd player showed up at all.
		battleQueueUpdated:FireClient(playerA, { InQueue = true, Count = 2 })
		battleQueueUpdated:FireClient(playerB, { InQueue = true, Count = 2 })
		task.wait(MATCH_FOUND_PAUSE_SECONDS)

		-- Either side can disconnect during that wait -- re-check both
		-- sessions before firing InQueue=false unconditionally (which used
		-- to happen even when one side had already left, silently
		-- stranding the other with no battleResult ever coming and no
		-- explanation -- the "Match Found!" banner would just vanish with
		-- no follow-up).
		local sessionA = DataManager.Get(playerA)
		local sessionB = DataManager.Get(playerB)
		if sessionA and sessionB then
			battleQueueUpdated:FireClient(playerA, { InQueue = false, Count = 0 })
			battleQueueUpdated:FireClient(playerB, { InQueue = false, Count = 0 })
			runBattle(playerA, playerB)
		elseif sessionA then
			battleQueueUpdated:FireClient(playerA, { InQueue = false, Count = 0 })
			systemMessage:FireClient(playerA, "Your opponent disconnected before the match started. Try again!")
		elseif sessionB then
			battleQueueUpdated:FireClient(playerB, { InQueue = false, Count = 0 })
			systemMessage:FireClient(playerB, "Your opponent disconnected before the match started. Try again!")
		end

		matchedPlayers[playerA] = nil
		matchedPlayers[playerB] = nil
	end
end)

leaveBattleQueue.OnServerEvent:Connect(function(player: Player)
	if table.find(queue, player) then
		removeFromQueue(player)
		battleQueueUpdated:FireClient(player, { InQueue = false, Count = 0 })
	end
end)

-- "Casual" card -- always instant, always vs the bot, no queue involved.
joinCasualBattle.OnServerEvent:Connect(function(player: Player)
	if not DataManager.Get(player) then
		return
	end
	if onBattleJoinCooldown(player) then
		return
	end
	runBotBattle(player)
end)

Players.PlayerRemoving:Connect(function(player)
	removeFromQueue(player)
	matchedPlayers[player] = nil
	lastBattleJoinAt[player] = nil
end)

return BattleManager
