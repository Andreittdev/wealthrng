-- "Hide Other Players" setting (SettingsPanel.luau): when on, every OTHER
-- player's character is made invisible on THIS client only, via
-- LocalTransparencyModifier -- purely a rendering-cost cut (fewer visible
-- rigs/accessories/clothing to draw), never touches the actual server-side
-- Transparency property, so it can't affect anyone else's view, hitboxes,
-- or any gameplay logic. Reversible instantly by toggling back off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HideOtherPlayers = {}

local enabled = false

local function setCharacterHidden(character: Model, hidden: boolean)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			descendant.LocalTransparencyModifier = hidden and 1 or 0
		end
	end
end

local function onCharacterAdded(character: Model)
	setCharacterHidden(character, enabled)
	-- Accessories/tools often attach their parts a moment after the
	-- character spawns (and worn accessories specifically stream in
	-- separately from the base rig) -- catches those instead of only
	-- hiding whatever existed at the exact instant this connected.
	character.DescendantAdded:Connect(function(descendant)
		if enabled and (descendant:IsA("BasePart") or descendant:IsA("Decal")) then
			descendant.LocalTransparencyModifier = 1
		end
	end)
end

local function onPlayerAdded(player: Player)
	if player == Players.LocalPlayer then
		return
	end
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

local function applyToAll()
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer and player.Character then
			setCharacterHidden(player.Character, enabled)
		end
	end
end

function HideOtherPlayers.SetEnabled(newEnabled: boolean)
	if enabled == newEnabled then
		return
	end
	enabled = newEnabled
	applyToAll()
end

function HideOtherPlayers.Init()
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	local preferencesUpdated = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PreferencesUpdated")
	preferencesUpdated.OnClientEvent:Connect(function(map: { [string]: boolean })
		HideOtherPlayers.SetEnabled(map.HideOtherPlayers == true)
	end)
end

return HideOtherPlayers
