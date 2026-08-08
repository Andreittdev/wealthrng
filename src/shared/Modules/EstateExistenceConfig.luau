-- Which Estates get a global "X exist" flex counter shown on their
-- InventoryPanel detail view (EstateExistenceManager.luau) -- every Estate,
-- every rarity tier (Roll Items are NOT covered, only AssetDatabase
-- Estates). Derived straight from AssetDatabase.GetAllAssets() so a newly
-- added Estate is automatically tracked without touching this file.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)

local EstateExistenceConfig = {}

local TRACKED_ASSET_IDS: { [string]: boolean } = {}
for _, asset in AssetDatabase.GetAllAssets() do
	TRACKED_ASSET_IDS[asset.Id] = true
end
EstateExistenceConfig.TrackedAssetIds = TRACKED_ASSET_IDS

function EstateExistenceConfig.IsTracked(assetId: string): boolean
	return TRACKED_ASSET_IDS[assetId] == true
end

return EstateExistenceConfig
