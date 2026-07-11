local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Modules:WaitForChild("EconomyConfig"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local upgradeStandEvent = remotes:WaitForChild("UpgradeStand")
local updateStandLevelEvent = remotes:WaitForChild("UpdateStandLevel")
local requestStandLevelEvent = remotes:WaitForChild("RequestStandLevel")

local MAX_LEVEL = 5

local function getUpgradeCost(level)
	return Economy.StandUpgradeCosts[level] or 0
end

local function getStandLevel(player)
	local level = player:FindFirstChild("StandLevel")

	if not level then
		level = Instance.new("IntValue")
		level.Name = "StandLevel"
		level.Value = 1
		level.Parent = player
	end

	return level
end

local function setVisible(part, visible)
	if part and part:IsA("BasePart") then
		part.Transparency = visible and 0 or 1
	end
end

local function updateStandVisual(player, level)
	local generatedStands = workspace:FindFirstChild("GeneratedStands")
	if not generatedStands then return end

	for _, stand in ipairs(generatedStands:GetChildren()) do
		if stand:GetAttribute("OwnerUserId") == player.UserId then
			setVisible(stand:FindFirstChild("Level2Banner", true), level >= 2)

			local upgrades = stand:FindFirstChild("Upgrades", true)
			if upgrades then
				setVisible(upgrades:FindFirstChild("Level3ShelfLeft"), level >= 3)
				setVisible(upgrades:FindFirstChild("Level3ShelfRight"), level >= 3)
			end

			break
		end
	end
end

local function sendLevel(player)
	local standLevel = getStandLevel(player)
	updateStandLevelEvent:FireClient(player, standLevel.Value)
	updateStandVisual(player, standLevel.Value)
end

requestStandLevelEvent.OnServerEvent:Connect(function(player)
	sendLevel(player)
end)

upgradeStandEvent.OnServerEvent:Connect(function(player)
	local standLevel = getStandLevel(player)

	if standLevel.Value >= MAX_LEVEL then
		sendLevel(player)
		return
	end

	local cost = getUpgradeCost(standLevel.Value)

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local money = leaderstats:FindFirstChild("Money")
	if not money then return end

	if money.Value < cost then
		warn("Not enough money for upgrade. Need $" .. cost)
		sendLevel(player)
		return
	end

	money.Value -= cost
	standLevel.Value += 1

	sendLevel(player)

	print(player.Name .. " upgraded stand to level " .. standLevel.Value)
end)