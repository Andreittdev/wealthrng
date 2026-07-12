-- NPC-ul care sta langa masa (Desk) standului de Rebirth Token Shop,
-- face cu mana si are deasupra capului textul care explica ce face standul.
--
-- IMPORTANT: e un ModuleScript, apelat explicit de TokenShopStand.server.luau
-- DUPA ce standul e relocat (stall:PivotTo(...)) -- daca ar fi fost un script
-- separat, care isi citeste singur pozitia lui Desk la pornirea serverului,
-- exista risc de race condition: cele doua scripturi ruleaza concurent, iar
-- NPC-ul putea sa apuce sa-si calculeze pozitia INAINTE ca standul sa fie
-- mutat la noua lui locatie, ramanand "fantoma" la vechiul loc.

local NPCKeeperBuilder = require(script.Parent:WaitForChild("NPCKeeperBuilder"))

local TokenShopKeeper = {}

local GOLD_ACCENT = Color3.fromRGB(255, 205, 95)
local BADGE_BG = Color3.fromRGB(24, 17, 15)
local BADGE_STROKE = Color3.fromRGB(255, 140, 45)

-- stall = Model-ul TokenShopStall, DEJA relocat la pozitia lui finala.
function TokenShopKeeper.Spawn(stall)
	local workspaceParent = stall.Parent

	-- Reconstruim intotdeauna de la zero, ca sa nu ramana tween-uri vechi
	-- legate de un NPC dintr-o sesiune anterioara sau de la o pozitie veche.
	local existingKeeper = workspaceParent:FindFirstChild("TokenShopKeeper")
	if existingKeeper then
		existingKeeper:Destroy()
	end

	-- Pozitie fixa, primita direct de la jucator (coordonatele HumanoidRootPart
	-- din Studio, stand langa masa).
	local KEEPER_POSITION = Vector3.new(-44.50, 6.66, -316.68)

	local keeperCFrame = CFrame.new(KEEPER_POSITION)
		* CFrame.Angles(0, math.rad(180), 0)

	local keeper = NPCKeeperBuilder.Build(keeperCFrame, "TokenShopKeeper")
	keeper.Parent = workspaceParent

	NPCKeeperBuilder.StartWave(keeper)

	-- ================= Text deasupra capului =================

	local head = keeper:FindFirstChild("Head")

	if head then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "KeeperLabel"
		billboard.Size = UDim2.new(0, 140, 0, 36)
		billboard.StudsOffset = Vector3.new(0, 1.6, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 60
		billboard.LightInfluence = 0
		billboard.Adornee = head
		billboard.Parent = head

		local badge = Instance.new("Frame")
		badge.BackgroundColor3 = BADGE_BG
		badge.BackgroundTransparency = 0.15
		badge.Size = UDim2.new(1, 0, 1, 0)
		badge.Parent = billboard

		Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 10)

		local badgeStroke = Instance.new("UIStroke")
		badgeStroke.Color = BADGE_STROKE
		badgeStroke.Thickness = 1.5
		badgeStroke.Transparency = 0.3
		badgeStroke.Parent = badge

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, -12, 1, -10)
		label.Position = UDim2.new(0, 6, 0, 5)
		label.Text = "Exchange Rebirth Tokens for Upgrades"
		label.TextColor3 = GOLD_ACCENT
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.TextStrokeTransparency = 0.5
		label.Font = Enum.Font.FredokaOne
		label.TextWrapped = true
		label.TextScaled = true
		label.Parent = badge
	end

	return keeper
end

return TokenShopKeeper
