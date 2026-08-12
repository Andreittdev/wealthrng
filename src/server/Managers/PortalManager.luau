-- Walking into the hub's "Endless Mode" portal (MapBuilder.buildPortal) or
-- its paired "HUB" return portal (MapBuilder.buildEndlessModeArea) teleports
-- the player between the two, same server -- no loading screen, no separate
-- Place. Detection is a server-side Heartbeat distance check against each
-- sign's invisible TriggerZone marker (same idiom client proximity panels
-- use via ProximityWatcher, just server-side since moving the player has to
-- be server-authoritative, not something the client can request/trust).
--
-- Same-server CFrame teleport for now, not a real cross-server
-- TeleportService hop into a solo instance -- per explicit request, so this
-- stays testable directly in Studio Play while the Endless Mode concept
-- itself is still being designed (TeleportService doesn't work in Studio
-- Play at all, only on a published/live game). Swap to a real
-- ReserveServer/TeleportToPrivateServer hop once that's settled.
--
-- Self-runs on require -- no Init() call needed, matches
-- StadiumOfferManager/FriendBoostManager's convention for managers that are
-- pure background watchers with no other module depending on them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local AssetManager = require(ServerScriptService.Managers.AssetManager)
local PetManager = require(ServerScriptService.Managers.PetManager)
local EndlessModeConfig = require(ReplicatedStorage.Modules.EndlessModeConfig)

local PortalManager = {}

local TRIGGER_RADIUS_STUDS = 5
-- Gives PortalLoadingScreen.luau's fade-in (0.2s) plus network round-trip
-- time to actually paint the screen black BEFORE the HumanoidRootPart jump
-- happens -- teleporting immediately would let the player see (or the
-- camera catch) the instant position snap peeking out from behind an
-- still-fading-in overlay.
local TELEPORT_DELAY_SECONDS = 0.3

-- Which TriggerZone (if any) this player was inside on the PREVIOUS
-- Heartbeat -- the crossing itself (entering fresh, false -> true) is what
-- fires UnequipAll/TrimEquippedToHubCap + beginTeleport now, not just
-- "currently inside", per a real bug: EndlessReturn_LandingSpot sits only 6
-- studs from EndlessReturn_TriggerZone (barely outside TRIGGER_RADIUS_STUDS
-- on arrival), and the Inventory panel now auto-opens right there (per the
-- 4-slot Endless loadout feature) -- a player spending more than a few
-- seconds picking their loadout right after landing could easily still be
-- standing inside that radius once a flat re-fire cooldown lapsed, silently
-- re-trimming their equipped Estates back down to 2 (and re-teleporting
-- them) while they were still just standing there, nowhere near actually
-- leaving. Edge-triggering fixes this at the root instead of retuning
-- radius/cooldown numbers to dodge it.
local lastZone: { [Player]: "HubTrigger" | "EndlessTrigger" | nil } = {}

task.spawn(function()
	local mapFolder = Workspace:WaitForChild("Map")
	local hubTrigger = mapFolder:WaitForChild("Portal_TriggerZone", 10) :: BasePart?
	local hubLanding = mapFolder:WaitForChild("Portal_LandingSpot", 10) :: BasePart?
	local endlessTrigger = mapFolder:WaitForChild("EndlessReturn_TriggerZone", 10) :: BasePart?
	local endlessLanding = mapFolder:WaitForChild("EndlessReturn_LandingSpot", 10) :: BasePart?
	local portalTeleport = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PortalTeleport")
	local requestEndlessModeLobbyTeleport = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestEndlessModeLobbyTeleport")

	if not (hubTrigger and hubLanding and endlessTrigger and endlessLanding) then
		warn("[PortalManager] Missing one or more portal markers -- teleport disabled")
		return
	end

	local function beginTeleport(player: Player, landingSpot: BasePart, destinationLabel: string)
		portalTeleport:FireClient(player, destinationLabel)
		task.delay(TELEPORT_DELAY_SECONDS, function()
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp then
				return
			end
			hrp.CFrame = landingSpot.CFrame + Vector3.new(0, 3, 0)

			-- Rebuilds any equipped Estate pet AFTER the position actually
			-- changes -- one welded to the hand while in Endless Mode needs
			-- to switch back to floating the instant they land back in the
			-- hub (see PetManager.luau's own comment on why this is
			-- exposed). No-op on the Endless Mode arrival side, since
			-- AssetManager.UnequipAll above already cleared everything
			-- there was to rebuild.
			PetManager.Refresh(player)
		end)
	end

	RunService.Heartbeat:Connect(function()
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp then
				continue
			end

			local currentZone: "HubTrigger" | "EndlessTrigger" | nil = nil
			if (hrp.Position - hubTrigger.Position).Magnitude <= TRIGGER_RADIUS_STUDS then
				currentZone = "HubTrigger"
			elseif (hrp.Position - endlessTrigger.Position).Magnitude <= TRIGGER_RADIUS_STUDS then
				currentZone = "EndlessTrigger"
			end

			-- Only the OUTSIDE -> INSIDE crossing fires anything -- lingering
			-- inside a zone (e.g. the Inventory panel keeping a player
			-- standing right at EndlessReturn_LandingSpot, 6 studs from
			-- EndlessReturn_TriggerZone, while picking their Endless Mode
			-- loadout) must never re-trigger the same trip. See lastZone's
			-- own comment above for why a cooldown alone wasn't enough.
			if currentZone and currentZone ~= lastZone[player] then
				if currentZone == "HubTrigger" then
					-- Floating Estate pets (PetManager.luau) don't belong in
					-- Endless Mode, per explicit request -- unequipped right
					-- as the portal fade starts covering the screen, same
					-- timing reasoning as the sidebar/CashHud visibility
					-- toggles.
					AssetManager.UnequipAll(player)
					beginTeleport(player, endlessLanding, "Endless Mode")
				else
					-- Endless Mode allows equipping more Estates than the
					-- Hub does (AssetDatabase.MaxEquippedEndlessMode vs
					-- MaxEquipped, per explicit "in lobby sa poti da equip
					-- numai la 2 Estates" request) -- trims back down on the
					-- way out, same "right as the portal fade starts
					-- covering the screen" timing as UnequipAll above, so a
					-- player never arrives back in the Hub still holding
					-- more than it allows.
					AssetManager.TrimEquippedToHubCap(player)
					beginTeleport(player, hubLanding, "Hub")
				end
			end

			lastZone[player] = currentZone
		end
	end)

	-- Fired by EndlessModeGameOverPanel.luau's "Go Lobby" button -- an
	-- immediate teleport instead of requiring the player to walk over to
	-- EndlessReturn_TriggerZone themselves right after dying. Reuses the
	-- exact same beginTeleport/hubLanding/TrimEquippedToHubCap the walk-
	-- through-the-portal trigger above already uses, so the two paths can
	-- never drift apart. lastZone is deliberately left alone here -- doesn't
	-- matter whether they were "in" a trigger zone at the moment they
	-- clicked the button.
	requestEndlessModeLobbyTeleport.OnServerEvent:Connect(function(player: Player)
		if not EndlessModeConfig.IsCharacterInEndlessMode(player.Character) then
			return
		end
		AssetManager.TrimEquippedToHubCap(player)
		beginTeleport(player, hubLanding, "Hub")
	end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastZone[player] = nil
end)

return PortalManager
