local Codes = {}

-- Coduri promo, redate manual din chenarul "Codes" (butonul de pe ecran).
-- Fiecare cod e o singura data per jucator (persistat prin atributul
-- "CodeRedeemed_<COD>", acelasi tipar ca TokenShopBought_<Id>).
--
-- Cheia e mereu MAJUSCULE (CodesManager face codeInput:upper():gsub("%s", "")
-- inainte de cautare, ca jucatorul sa poata scrie orice capitalizare).
--
-- Type disponibile (vezi grantHandlers din CodesManager.server.luau):
--   Money         -- {Amount = numar}
--   RebirthTokens -- {Amount = numar}
--   Pet           -- {Pet = {PetId=..., DisplayName=..., Rarity=..., Image=..., Bonuses={...}}}
--   RandomPet     -- {Rarity = "Common"/"Rare"/...} -- pet random din acea raritate
--
-- Pentru a dezactiva un cod (fara sa-l stergi, ca sa nu strici istoricul
-- jucatorilor care l-au redat deja), seteaza Active = false.
Codes.Active = {
	["RELEASE"] = {Type = "Money", Amount = 5000, Active = true},
	["WELCOME"] = {Type = "Money", Amount = 2500, Active = true},
	["THANKYOU"] = {Type = "RandomPet", Rarity = "Common", Active = true},
}

return Codes
