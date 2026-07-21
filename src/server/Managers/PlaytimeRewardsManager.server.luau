local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local showNotificationEvent = remotes:WaitForChild("ShowNotification")
local SFXServer = require(script.Parent:WaitForChild("SFXServer"))
local PetManager = require(script.Parent:WaitForChild("PetManager"))

-- Recompense pe SESIUNEA curenta (vezi Economy.PlaytimeRewards) -- pragurile
-- mici dau bani, pragurile mari (30 min/1h) dau peturi EXCLUSIVE, care nu
-- apar in niciun ou.
local function grantMilestone(player, milestone)
	-- Jucatorul a plecat inainte sa treaca timpul -- task.delay tot ruleaza
	-- callback-ul mai tarziu, trebuie verificat explicit.
	if not player.Parent then
		return
	end

	if milestone.Type == "Money" then
		local leaderstats = player:FindFirstChild("leaderstats")
		local money = leaderstats and leaderstats:FindFirstChild("Money")
		if not money then
			return
		end

		money.Value += milestone.Money

		showNotificationEvent:FireClient(
			player,
			"🕒 " .. milestone.Label .. " played! +$" .. milestone.Money
		)
	elseif milestone.Type == "Pet" then
		-- Deliberat REPETABIL, o data pe sesiune (nu o singura data per cont)
		-- -- cerut explicit, ca duplicate sa se poata aduna pentru un viitor
		-- sistem de Golden/Rainbow Pets (upgrade din duplicate). Fara asta,
		-- jucatorul n-ar mai avea niciun motiv sa revina dupa prima primire.
		local pet = PetManager.GrantSpecificPet(player, milestone.Pet)
		if not pet then
			return
		end

		showNotificationEvent:FireClient(
			player,
			"🕒 " .. milestone.Label .. " played! Exclusive pet: " .. milestone.Pet.DisplayName .. "!"
		)
	else
		return
	end

	SFXServer.Play(player, "Purchase")
end

Players.PlayerAdded:Connect(function(player)
	for _, milestone in ipairs(Economy.PlaytimeRewards.Milestones) do
		task.delay(milestone.Seconds, grantMilestone, player, milestone)
	end
end)
