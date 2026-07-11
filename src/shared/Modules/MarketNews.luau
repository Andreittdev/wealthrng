local MarketNews = {}

local newsByCategory = {
	Clothing = {
		"Fashion Week boosts clothing demand.",
		"Vintage clothing is trending again.",
		"Streetwear hype pushes clothing prices up.",
		"Clothing demand cools down this week.",
		"New styles shake up the clothing market."
	},

	Shoes = {
		"Sneaker convention attracts collectors.",
		"Limited sneakers are trending.",
		"Resellers are chasing rare shoes.",
		"Shoe demand slows down.",
		"Collectors are watching the sneaker market."
	},

	Accessories = {
		"Accessories gain popularity among collectors.",
		"Luxury accessories are moving fast.",
		"Collectors are hunting rare accessories.",
		"Accessory demand drops slightly.",
		"New accessory trend hits the market."
	}
}

function MarketNews.GetRandomNews(category)
	local list = newsByCategory[category]

	if not list or #list == 0 then
		return "Market conditions are changing."
	end

	return list[math.random(1, #list)]
end

return MarketNews