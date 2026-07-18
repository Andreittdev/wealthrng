local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Toate RemoteEvent/RemoteFunction-urile jocului erau plasate manual, direct
-- in fisierul de Studio -- NU sincronizate prin Rojo, deci nu existau nicaieri
-- in git. Daca fisierul de Studio s-ar pierde/reseta vreodata, tot jocul ar
-- crapa (fiecare manager foloseste WaitForChild si ar astepta la nesfarsit
-- un remote care nu mai exista). Script centralizat, sincronizat prin Rojo --
-- creeaza folderul Remotes si toate RemoteEvent/Function-urile o singura
-- data, la pornirea serverului, indiferent de starea fisierului de Studio.
--
-- Idempotent (FindFirstChild inainte de Instance.new peste tot) -- unele
-- manageri (DailyRewardsManager, RebirthManager, TokenShopManager, IndexStand,
-- PetEquipManager, TokenShopStand, MarketManager) mai au propriul lor fallback
-- de creare pentru remote-ul lor -- lasate neatinse, nu creeaza duplicate,
-- primul script care ruleaza "castiga".

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local function ensureRemoteEvent(name)
	if remotes:FindFirstChild(name) then
		return
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
end

local function ensureRemoteFunction(name)
	if remotes:FindFirstChild(name) then
		return
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = remotes
end

-- Ordinea nu conteaza -- toti consumatorii folosesc WaitForChild (asteapta),
-- nu FindFirstChild simplu, deci nu exista risc de cursa cu alte scripturi.
local REMOTE_EVENTS = {
	"BuyItem",
	"CodeResult",
	"DailyClaimResult",
	"DailyStatusResult",
	"DepositMoney",
	"EggHatchResult",
	"EquipPet",
	"EquipTitle",
	"MarketUpdate",
	"OpenBank",
	"OpenEggShop",
	"OpenIndex",
	"OpenPetCrate",
	"OpenTokenShop",
	"PetInventoryRequest",
	"PetInventoryUpdate",
	"PetOpened",
	"RebirthResult",
	"RedeemCode",
	"RequestDailyClaim",
	"RequestDailyStatus",
	"RequestEggHatch",
	"RequestInventory",
	"RequestRebirth",
	"RequestStandLevel",
	"RequestTokenPurchase",
	"SellFirstItem",
	"SellSelectedItem",
	"SetGiftTarget",
	"ShowInventory",
	"ShowNotification",
	"ShowTrade",
	"SkipTrade",
	"TokenPurchaseResult",
	"UpdateStandLevel",
	"UpgradeStand",
	"WithdrawMoney"
}

-- Doar astea 2 folosesc InvokeServer/OnServerInvoke in tot codul -- restul
-- sunt toate RemoteEvent (FireServer/OnServerEvent).
local REMOTE_FUNCTIONS = {
	"GetBankData",
	"GetMarketData"
}

for _, name in ipairs(REMOTE_EVENTS) do
	ensureRemoteEvent(name)
end

for _, name in ipairs(REMOTE_FUNCTIONS) do
	ensureRemoteFunction(name)
end
