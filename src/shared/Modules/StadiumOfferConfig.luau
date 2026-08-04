-- The Meshy Stadium 3D model (placed directly in Workspace, positioned by
-- MapBuilder.luau) is a physical vendor for Sol Stadium (AssetDatabase's
-- Top3Estate) -- the one Estate in the game that can be owned more than
-- once, sold from a shared GLOBAL stock pool (StadiumOfferManager.luau),
-- not a per-player one. Cash price comes straight from AssetDatabase (Sol
-- Stadium's own Price field) instead of duplicating the number here, so
-- retuning one can't silently drift from the other.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)

local StadiumOfferConfig = {}

StadiumOfferConfig.AssetId = "Top3Estate"
StadiumOfferConfig.TotalStock = 200
-- Per-player cap on CASH purchases only -- Robux purchases are unlimited.
StadiumOfferConfig.MaxCashPurchases = 3
-- Developer Product -- grants +1 Sol Stadium copy, no cap, doesn't touch
-- the shared stock pool (CashPackManager.luau's ProcessReceipt).
StadiumOfferConfig.RobuxProductId = 3613227905

function StadiumOfferConfig.GetCashPrice(): number
	local asset = AssetDatabase.GetAsset(StadiumOfferConfig.AssetId)
	return asset and asset.Price or 0
end

-- session.SolStadiumOwned is the TOTAL owned (cash + Robux combined) --
-- the MaxCashPurchases cap only applies to the cash-sourced portion, so
-- this subtracts out however many were granted via Robux
-- (GrantedStadiumOfferPurchaseIds, unlimited by design) to get the count
-- that actually counts against the cap. Shared (not just server-side) so
-- DataManager.luau and StadiumOfferManager.luau can't compute this two
-- different ways and drift apart.
function StadiumOfferConfig.CountCashOwned(session: { SolStadiumOwned: number, GrantedStadiumOfferPurchaseIds: { [string]: boolean } }): number
	local robuxGrantedCount = 0
	for _ in session.GrantedStadiumOfferPurchaseIds do
		robuxGrantedCount += 1
	end
	return session.SolStadiumOwned - robuxGrantedCount
end

return StadiumOfferConfig
