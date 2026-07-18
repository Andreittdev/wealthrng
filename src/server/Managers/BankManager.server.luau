local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local depositMoneyEvent = remotes:WaitForChild("DepositMoney")
local withdrawMoneyEvent = remotes:WaitForChild("WithdrawMoney")
local getBankDataFunction = remotes:WaitForChild("GetBankData")

local function getBankMoney(player)
	local bankMoney = player:FindFirstChild("BankMoney")

	if not bankMoney then
		bankMoney = Instance.new("IntValue")
		bankMoney.Name = "BankMoney"
		bankMoney.Value = 0
		bankMoney.Parent = player
	end

	return bankMoney
end

local function getCash(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return nil end

	return leaderstats:FindFirstChild("Money")
end

depositMoneyEvent.OnServerEvent:Connect(function(player, amount)
	amount = tonumber(amount)
	if not amount or amount <= 0 then return end
	amount = math.floor(amount)

	local cash = getCash(player)
	local bankMoney = getBankMoney(player)

	if not cash then return end
	if cash.Value < amount then return end

	cash.Value -= amount
	bankMoney.Value += amount
end)

withdrawMoneyEvent.OnServerEvent:Connect(function(player, amount)
	amount = tonumber(amount)
	if not amount or amount <= 0 then return end
	amount = math.floor(amount)

	local cash = getCash(player)
	local bankMoney = getBankMoney(player)

	if not cash then return end
	if bankMoney.Value < amount then return end

	bankMoney.Value -= amount

	-- Suprimam tracker-ul de CashEarned cat timp setam Money -- banii astia
	-- erau deja ai jucatorului (doar ii mutam inapoi din banca), nu bani noi
	-- castigati -- altfel depune+retrage in bucla umfla clasamentul gratis.
	player:SetAttribute("SuppressCashEarnedTracking", true)
	cash.Value += amount
	player:SetAttribute("SuppressCashEarnedTracking", false)
end)

getBankDataFunction.OnServerInvoke = function(player)
	local cash = getCash(player)
	local bankMoney = getBankMoney(player)

	return {
		Cash = cash and cash.Value or 0,
		Bank = bankMoney.Value
	}
end