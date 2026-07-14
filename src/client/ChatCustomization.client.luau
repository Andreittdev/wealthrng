local TextChatService = game:GetService("TextChatService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))

-- VIP are prioritate peste orice titlu (gamepass platit > titlu castigat).
-- Galben, la fel ca eticheta "VIP" de deasupra capului (VIPManager).
local VIP_COLOR = Color3.fromRGB(255, 215, 60)

-- Titlu -> {Nume afisat, Culoare} construit din Economy.TokenShop.Items
-- (ChatColor-ul fiecarui titlu e definit acolo), ca sa nu tinem doua surse
-- de adevar pentru aceleasi date.
local TITLE_INFO = {}
for _, item in ipairs(Economy.TokenShop.Items) do
	if item.Type == "Title" then
		TITLE_INFO[item.Id] = {Name = item.Name, Color = item.ChatColor or Color3.fromRGB(255, 255, 255)}
	end
end

local function toHex(color)
	return string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
end

-- Ambele etichete pot aparea deodata (VIP + un titlu echipat) -- VIP mereu
-- primul (mai valoros, e platit), apoi titlul. Culoarea textului din chat
-- e data de PRIMA eticheta (cea mai valoroasa) -- daca ai VIP, chatul e
-- galben, indiferent ce titlu ai echipat pe langa el.
local function getTagsForPlayer(player)
	local tags = {}

	if player:GetAttribute("IsVIP") == true then
		table.insert(tags, {Name = "VIP", Color = VIP_COLOR})
	end

	local equippedTitle = player:GetAttribute("EquippedTitle")
	local info = equippedTitle and equippedTitle ~= "" and TITLE_INFO[equippedTitle]

	if info then
		table.insert(tags, {Name = info.Name, Color = info.Color})
	end

	return tags
end

TextChatService.OnIncomingMessage = function(message)
	local properties = Instance.new("TextChatMessageProperties")

	local textSource = message.TextSource
	if not textSource then
		return properties
	end

	local player = Players:GetPlayerByUserId(textSource.UserId)
	if not player then
		return properties
	end

	local tags = getTagsForPlayer(player)
	if #tags == 0 then
		return properties
	end

	local tagText = ""
	for _, tag in ipairs(tags) do
		tagText = tagText .. string.format('<font color="%s">[%s]</font> ', toHex(tag.Color), tag.Name)
	end

	-- Culoarea textului mesajului = prima (cea mai valoroasa) eticheta.
	local textHex = toHex(tags[1].Color)

	properties.PrefixText = tagText .. message.PrefixText
	properties.Text = string.format('<font color="%s">%s</font>', textHex, message.Text)

	return properties
end
