local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local NPCDatabase = require(modulesFolder:WaitForChild("NPCDatabase"))
local TradeManager = require(script.Parent:WaitForChild("TradeManager"))
local InventoryManager = require(script.Parent:WaitForChild("InventoryManager"))
local SellManager = require(script.Parent:WaitForChild("SellManager"))
local DataManager = require(script.Parent.Parent:WaitForChild("DataManager"))
local MarketManager = require(modulesFolder:WaitForChild("Market"):WaitForChild("MarketManager"))
local StandDisplayManager = require(script.Parent:WaitForChild("StandDisplayManager"))
local CosmeticManager = require(script.Parent.Parent:WaitForChild("CosmeticManager"))
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))
local PetManager = require(script.Parent.Parent:WaitForChild("PetManager"))

local showTradeEvent = remotesFolder:WaitForChild("ShowTrade")
local buyItemEvent = remotesFolder:WaitForChild("BuyItem")
local skipTradeEvent = remotesFolder:WaitForChild("SkipTrade")
local sellFirstItemEvent = remotesFolder:WaitForChild("SellFirstItem")
local sellSelectedItemEvent = remotesFolder:WaitForChild("SellSelectedItem")
local requestInventoryEvent = remotesFolder:WaitForChild("RequestInventory")
local showInventoryEvent = remotesFolder:WaitForChild("ShowInventory")
local showNotificationEvent = remotesFolder:WaitForChild("ShowNotification")
local marketUpdateEvent = remotesFolder:WaitForChild("MarketUpdate")
local openPetCrateEvent = remotesFolder:WaitForChild("OpenPetCrate")
local petOpenedEvent = remotesFolder:WaitForChild("PetOpened")

local INVENTORY_PASS_ID = 1899734044
local DEFAULT_MAX_INVENTORY = 50
local PASS_MAX_INVENTORY = 150

local npcFolder = ServerStorage:WaitForChild("NPCs")
local npcTemplate = npcFolder:WaitForChild("TestNPC")

local activeTrades = {}

local function getStandLevel(player)
	local standLevel = player:FindFirstChild("StandLevel")

	if standLevel then
		return standLevel.Value
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local levelValue = leaderstats:FindFirstChild("StandLevel")
		if levelValue then
			return levelValue.Value
		end
	end

	return 1
end

local function getStandBonuses(player)
	local level = getStandLevel(player)
	return Economy.StandBonuses[level] or Economy.StandBonuses[1]
end

local function getSpawnDelay(player)
	local bonuses = getStandBonuses(player)
	local cosmeticBonuses = CosmeticManager.GetBonuses(player)
	local petBonuses = PetManager.GetBonuses(player)

	local totalSpeed = bonuses.Speed + (cosmeticBonuses.NpcSpeed or 0) + (petBonuses.NpcSpeed or 0)
	totalSpeed = math.clamp(totalSpeed, 0, Economy.Caps.Speed)

	local reduction = 1 - (totalSpeed / 100)

	local minDelay = Economy.NPCSpawnInterval.Min * reduction
	local maxDelay = Economy.NPCSpawnInterval.Max * reduction

	return minDelay + math.random() * (maxDelay - minDelay)
end

local function sendInventory(player)
	local inventory = player:FindFirstChild("Inventory")
	local items = {}

	if inventory then
		for _, item in ipairs(inventory:GetChildren()) do
			table.insert(items, {
				Id = item.Name,
				ItemName = item:FindFirstChild("ItemName") and item.ItemName.Value or item.Name,
				Rarity = item:FindFirstChild("Rarity") and item.Rarity.Value or "Common",
				Category = item:FindFirstChild("Category") and item.Category.Value or "Unknown",
				BuyPrice = item:FindFirstChild("BuyPrice") and item.BuyPrice.Value or 0,
				Image = item:FindFirstChild("Image") and item.Image.Value or ""
			})
		end
	end

	showInventoryEvent:FireClient(player, items)
end

local function getMaxInventory(player)
	local maxInventory = DEFAULT_MAX_INVENTORY

	local success, ownsPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, INVENTORY_PASS_ID)
	end)

	if success and ownsPass then
		maxInventory = PASS_MAX_INVENTORY
	end

	return maxInventory
end

local function getRandomNPCType()
	local totalWeight = 0
	local pool = {}

	for npcType, npcData in pairs(NPCDatabase.Types) do
		local weight = npcData.SpawnChance or 0

		if weight > 0 then
			totalWeight += weight

			table.insert(pool, {
				Type = npcType,
				Weight = weight
			})
		end
	end

	if totalWeight <= 0 then
		warn("No NPC spawn weights found")
		return nil
	end

	local roll = math.random() * totalWeight
	local current = 0

	for _, npc in ipairs(pool) do
		current += npc.Weight

		if roll <= current then
			return npc.Type
		end
	end

	return pool[1].Type
end

local function getPlayerStand(player)
	local standsFolder = workspace:WaitForChild("GeneratedStands")

	for _, stand in ipairs(standsFolder:GetChildren()) do
		if stand:GetAttribute("OwnerUserId") == player.UserId then
			return stand
		end
	end

	return nil
end

local function getNPCSpotPosition(stand)
	local base = stand:FindFirstChild("Base")
	if not base then
		return nil
	end

	local npcSpot = base:FindFirstChild("NPCSpot")
	if not npcSpot then
		return nil
	end

	return npcSpot.Position
end

local function moveNPCTo(npc, destination)
	local humanoid = npc:WaitForChild("Humanoid")
	local rootPart = npc:WaitForChild("HumanoidRootPart")

	local path = PathfindingService:CreatePath()
	path:ComputeAsync(rootPart.Position, destination)

	if path.Status ~= Enum.PathStatus.Success then
		warn("NPC path failed")
		return
	end

	for _, waypoint in ipairs(path:GetWaypoints()) do
		humanoid:MoveTo(waypoint.Position)
		humanoid.MoveToFinished:Wait()
	end
end

local function removeNPC(player)
	local trade = activeTrades[player]

	if trade and trade.NPC then
		trade.NPC:Destroy()
	end

	activeTrades[player] = nil
end

local function spawnNPCForPlayer(player)
	if activeTrades[player] then
		return
	end

	local stand = getPlayerStand(player)
	if not stand then
		return
	end

	local npcSpotPosition = getNPCSpotPosition(stand)
	if not npcSpotPosition then
		return
	end

	local npcType = getRandomNPCType()
	if not npcType then
		return
	end

	local npcData = NPCDatabase.Types[npcType]
	if not npcData then
		return
	end

	local npc = npcTemplate:Clone()
	npc.Name = npcData.DisplayName
	npc.Parent = workspace

	local humanoid = npc:WaitForChild("Humanoid")
	local rootPart = npc:WaitForChild("HumanoidRootPart")

	local bonuses = getStandBonuses(player)
	local cosmeticBonuses = CosmeticManager.GetBonuses(player)

	local speedMultiplier = 1 + (bonuses.Speed / 100)
	local baseWalkSpeed = npcData.WalkSpeed or 12
	humanoid.WalkSpeed = baseWalkSpeed * speedMultiplier

	rootPart.CFrame = CFrame.new(npcSpotPosition + Vector3.new(0, 0, -35))

	task.wait(1)
	moveNPCTo(npc, npcSpotPosition)

	local petBonuses = PetManager.GetBonuses(player)
	local vipLuck = player:GetAttribute("IsVIP") and Economy.VIP.Luck or 0

	local totalLuck = bonuses.Luck + cosmeticBonuses.NpcLuck + petBonuses.NpcLuck + vipLuck
	totalLuck = math.clamp(totalLuck, 0, Economy.Caps.Luck)

	local offer = TradeManager.CreateOffer(npcType, totalLuck)

	if offer then
		activeTrades[player] = {
			NPC = npc,
			Offer = offer,
		}

		showTradeEvent:FireClient(player, offer)
	end
end
local function handleOpenPetCrate(player)
	local pet = PetManager.OpenCrate(player)

	if not pet then
		warn("Pet crate failed for " .. player.Name)
		return
	end

	petOpenedEvent:FireClient(player, pet)

	showNotificationEvent:FireClient(
		player,
		"?? You received " .. pet.DisplayName .. " (" .. pet.Rarity .. ")"
	)
end

local function handleBuy(player, clientOffer)
	local trade = activeTrades[player]
	if not trade then return end

	local offer = trade.Offer
	if not offer then return end

	if not clientOffer or clientOffer.ItemId ~= offer.ItemId then
		warn("Invalid offer from " .. player.Name)
		return
	end

	local inventory = player:FindFirstChild("Inventory")
	if not inventory then return end

	local maxInventory = getMaxInventory(player)

	if #inventory:GetChildren() >= getMaxInventory(player) then
		showNotificationEvent:FireClient(player, "?? Inventory Full! Press + to upgrade.")
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local money = leaderstats:FindFirstChild("Money")
	if not money then return end

	local buyPrice = tonumber(offer.BuyPrice) or 0

	if money.Value < buyPrice then
		showNotificationEvent:FireClient(player, "? Not enough money")
		return
	end

	money.Value -= buyPrice

	InventoryManager.AddItem(player, offer)
	StandDisplayManager.UpdateStand(player)
	sendInventory(player)

	showNotificationEvent:FireClient(player, "? Bought " .. tostring(offer.ItemName) .. " for $" .. tostring(buyPrice))

	removeNPC(player)

	task.wait(getSpawnDelay(player))
	spawnNPCForPlayer(player)
end

local function handleSkip(player)
	removeNPC(player)

	task.wait(getSpawnDelay(player) + 2) -- skip ram�ne pu?in mai lent dec�t buy, ca penalizare naturala
	spawnNPCForPlayer(player)
end

local function handleSellFirstItem(player)
	local inventory = player:FindFirstChild("Inventory")
	if not inventory then return end

	local firstItem = inventory:FindFirstChild("1")

	if not firstItem then
		showNotificationEvent:FireClient(player, "?? Inventory is empty")
		return
	end

	local success = SellManager.SellItem(player, firstItem)

	if success then
		showNotificationEvent:FireClient(player, "?? Sold item successfully")
		sendInventory(player)
		StandDisplayManager.UpdateStand(player)
	end
end

local function handleSellSelectedItem(player, itemId)
	local inventory = player:FindFirstChild("Inventory")
	if not inventory then return end

	local item = inventory:FindFirstChild(tostring(itemId))

	if not item then
		showNotificationEvent:FireClient(player, "? Item not found")
		return
	end

	local success = SellManager.SellItem(player, item)

	if success then
		showNotificationEvent:FireClient(player, "?? Sold selected item")
		sendInventory(player)
		StandDisplayManager.UpdateStand(player)
	end
end

local function onPlayerAdded(player)
	local data = DataManager.LoadData(player)

	task.wait(1)
	DataManager.ApplyData(player, data)

	marketUpdateEvent:FireClient(player, state, event)

	task.wait(7)
	spawnNPCForPlayer(player)
end

local function onPlayerRemoving(player)
	removeNPC(player)
	DataManager.SaveData(player)
end

buyItemEvent.OnServerEvent:Connect(handleBuy)
skipTradeEvent.OnServerEvent:Connect(handleSkip)
sellFirstItemEvent.OnServerEvent:Connect(handleSellFirstItem)
sellSelectedItemEvent.OnServerEvent:Connect(handleSellSelectedItem)
requestInventoryEvent.OnServerEvent:Connect(sendInventory)
openPetCrateEvent.OnServerEvent:Connect(handleOpenPetCrate)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end