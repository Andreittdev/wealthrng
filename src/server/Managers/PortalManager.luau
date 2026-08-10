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

local PortalManager = {}

local TRIGGER_RADIUS_STUDS = 5
-- Long enough that a player standing right at a TriggerZone (e.g. lingering
-- at the landing spot, which is only 6 studs from the OTHER sign's own
-- TriggerZone) can't immediately bounce back and forth every Heartbeat.
local TELEPORT_COOLDOWN_SECONDS = 3
-- Gives PortalLoadingScreen.luau's fade-in (0.2s) plus network round-trip
-- time to actually paint the screen black BEFORE the HumanoidRootPart jump
-- happens -- teleporting immediately would let the player see (or the
-- camera catch) the instant position snap peeking out from behind an
-- still-fading-in overlay.
local TELEPORT_DELAY_SECONDS = 0.3

local lastTeleportAt: { [Player]: number } = {}

task.spawn(function()
	local mapFolder = Workspace:WaitForChild("Map")
	local hubTrigger = mapFolder:WaitForChild("Portal_TriggerZone", 10) :: BasePart?
	local hubLanding = mapFolder:WaitForChild("Portal_LandingSpot", 10) :: BasePart?
	local endlessTrigger = mapFolder:WaitForChild("EndlessReturn_TriggerZone", 10) :: BasePart?
	local endlessLanding = mapFolder:WaitForChild("EndlessReturn_LandingSpot", 10) :: BasePart?
	local portalTeleport = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PortalTeleport")

	if not (hubTrigger and hubLanding and endlessTrigger and endlessLanding) then
		warn("[PortalManager] Missing one or more portal markers -- teleport disabled")
		return
	end

	-- Cooldown is set IMMEDIATELY (not after the delay) so a player standing
	-- right at a TriggerZone for the whole TELEPORT_DELAY_SECONDS window
	-- can't queue up a second teleport before the first one even lands.
	local function beginTeleport(player: Player, landingSpot: BasePart, destinationLabel: string)
		lastTeleportAt[player] = os.clock()
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
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			if lastTeleportAt[player] and now - lastTeleportAt[player] < TELEPORT_COOLDOWN_SECONDS then
				continue
			end

			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp then
				continue
			end

			if (hrp.Position - hubTrigger.Position).Magnitude <= TRIGGER_RADIUS_STUDS then
				-- Floating Estate pets (PetManager.luau) don't belong in
				-- Endless Mode, per explicit request -- unequipped right as
				-- the portal fade starts covering the screen, same timing
				-- reasoning as the sidebar/CashHud visibility toggles.
				AssetManager.UnequipAll(player)
				beginTeleport(player, endlessLanding, "Endless Mode")
			elseif (hrp.Position - endlessTrigger.Position).Magnitude <= TRIGGER_RADIUS_STUDS then
				beginTeleport(player, hubLanding, "Hub")
			end
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastTeleportAt[player] = nil
end)

return PortalManager
