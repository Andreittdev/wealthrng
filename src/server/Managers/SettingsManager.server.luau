local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataManager = require(script.Parent:WaitForChild("DataManager"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local updateSettingsEvent = remotes:FindFirstChild("UpdateSettings")
if not updateSettingsEvent then
	updateSettingsEvent = Instance.new("RemoteEvent")
	updateSettingsEvent.Name = "UpdateSettings"
	updateSettingsEvent.Parent = remotes
end

local function clampVolume(value)
	local number = tonumber(value)

	-- number ~= number e adevarat DOAR pentru NaN (0/0) -- fara verificarea
	-- asta, un client modificat putea trimite NaN, care trece prin
	-- math.clamp neschimbat (toate comparatiile cu NaN sunt false) si e
	-- "truthy" in Lua (doar nil/false sunt falsy), deci SetAttribute il
	-- accepta -- iar DataStore RESPINGE NaN la SetAsync, ceea ce insemna ca
	-- absolut NIMIC din contul acelui jucator (bani, iteme, pet-uri) nu se
	-- mai salva pentru tot restul sesiunii.
	if not number or number ~= number then
		return nil
	end

	return math.clamp(number, 0, 1)
end

-- Setari boolean simple (attribute = valoare trimisa, fara alta validare) --
-- o lista, nu 13 blocuri identice de cod repetat.
local SIMPLE_BOOLEAN_SETTINGS = {
	"NotificationsEnabled",
	"LowGraphicsMode",
	"AutoRebirthEnabled",
	"SellDuplicatesEnabled",
	"AutoBuyFilterCommon",
	"AutoBuyFilterRare",
	"AutoBuyFilterEpic",
	"AutoBuyFilterLegendary",
	"AutoBuyFilterMythic",
	"AutoSellPassEnabled",
	"AutoBuyPassEnabled",
	"AutoSellFilterClothing",
	"AutoSellFilterShoes",
	"AutoSellFilterElectronics",
	"AutoSellFilterLuxury",
	"AutoSellFilterCollectibles"
}

-- Clientul trimite un tabel PARTIAL (doar ce s-a schimbat) -- setarile care
-- lipsesc din tabel raman neatinse. Validam fiecare camp separat inainte
-- sa-l acceptam, ca un client modificat sa nu poata trimite valori invalide
-- (tip gresit, volum in afara [0,1]).
local function onUpdateSettings(player, settings)
	if typeof(settings) ~= "table" then
		return
	end

	for _, key in ipairs(SIMPLE_BOOLEAN_SETTINGS) do
		if settings[key] ~= nil then
			player:SetAttribute(key, settings[key] == true)
		end
	end

	if settings.MusicVolume ~= nil then
		local volume = clampVolume(settings.MusicVolume)
		if volume then
			player:SetAttribute("MusicVolume", volume)
		end
	end

	if settings.SFXVolume ~= nil then
		local volume = clampVolume(settings.SFXVolume)
		if volume then
			player:SetAttribute("SFXVolume", volume)
		end
	end

	DataManager.SaveData(player)
end

updateSettingsEvent.OnServerEvent:Connect(onUpdateSettings)
