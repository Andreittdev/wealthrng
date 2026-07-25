-- ModuleScript, not a Script: requiring it (from init.server.luau, or from
-- any manager that needs a remote) deterministically creates
-- ReplicatedStorage.Remotes before anything else runs -- Roblox does not
-- guarantee execution order between sibling auto-run Scripts, so remote
-- creation can't safely live in one of those.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Modules.RemoteNames)

local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

local function ensureRemoteEvent(name: string)
	if not remotesFolder:FindFirstChild(name) then
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotesFolder
	end
end

local function ensureRemoteFunction(name: string)
	if not remotesFolder:FindFirstChild(name) then
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = remotesFolder
	end
end

for _, name in RemoteNames.Events do
	ensureRemoteEvent(name)
end

for _, name in RemoteNames.Functions do
	ensureRemoteFunction(name)
end

return remotesFolder
