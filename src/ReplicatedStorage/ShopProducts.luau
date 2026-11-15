--[==[
	ShopProducts - the ONE place every purchasable inventory item is priced, in BOTH
	currencies, plus the Developer Product IDs that make the Robux side live.

	Shared deliberately: InventoryController reads the prices to draw the buttons, and
	ProductServer reads the SAME table in reverse (product id -> what to grant) inside
	ProcessReceipt. If those two ever disagree a player pays for one thing and receives
	another, so they are not allowed to be two tables.

	=== TO MAKE ROBUX PURCHASES LIVE ===
	Every id below is 0, which means "not set up yet". While an id is 0 the Robux button
	renders disabled and explains itself - it CANNOT charge anyone. Nothing here can take
	Robux and hand back nothing.
	To turn one on: create a Developer Product on the Creator Dashboard
	(create.roblox.com -> your experience -> Monetization -> Developer Products), set its
	price to the `robux` value beside it here, then paste the product id into PRODUCTS.
	That is the only step - the receipt handler and the grant already exist.

	=== CASH ===
	The cash side works today and needs no setup. It spends the shared client-side
	leaderstats.Money balance, the same one fishing pays into.
]==]

local M = {}

----------------------------------------------------------------------
-- 1. DEVELOPER PRODUCT IDS  (paste yours in; 0 = not set up yet)
----------------------------------------------------------------------
M.PRODUCTS = {
	-- rods, by tier
	rod_2 = 3717795287, rod_3 = 3717795354, rod_4  = 3717795420, rod_5  = 3717795482, rod_6 = 3717795541,
	rod_7 = 3717795588, rod_8 = 3717795656, rod_9  = 3717795717, rod_10 = 3717795773,

	-- baits, keyed by the stripped name (the same akey the Bait_<key> attributes use)
	bait_Breadcrumbs   = 3717795856, bait_Grub        = 3717795924, bait_Minnow      = 3717796015,
	bait_Shrimp        = 3717796101, bait_Squid       = 3717796178, bait_OctopusInk  = 3717796243,
	bait_Glowworm      = 3717796306, bait_GoldenRoe   = 3717796380, bait_BlackPearl  = 3717796439,
	bait_SirenSong     = 3717796488, bait_AbyssalChum = 3717796555, bait_LeviathanBait = 3717796602,

	-- boosts, keyed by the Inv_<key> attribute key
	boost_potion_luck  = 3717795018, boost_potion_cast  = 3717795127, boost_potion_bite = 3717795184,
	boost_potion_money = 3717795076, boost_jackpot      = 3717795235,

	-- the Shop window's own products (StarterGui.ShopMenu): cash packs by CASH_PACKS key, and the Starter Pack.
	-- ProductServer sends these to the shop over ShopRemotes.ShopGranted (InventoryController doesn't grant them).
	cash_1 = 3717794630, cash_2 = 3717794722, cash_3 = 3717794787, cash_4 = 3717794848, cash_5 = 3717794904, cash_6 = 3717794968,
	starter_pack = 3717794488,

	-- zones 2-6 (StarterGui.ZonesMenu), by zone id. 0 = not set up yet: create one Developer Product per zone at its
	-- ZONE_ROBUX price below and paste the id here. ProductServer sends these over ShopRemotes.ZoneGranted.
	zone_2 = 3717832223, zone_3 = 3717832272, zone_4 = 3717832355, zone_5 = 3717832411, zone_6 = 3717832544,
}

----------------------------------------------------------------------
-- 2. RODS
----------------------------------------------------------------------
-- Cash ladder (unchanged - this is the table InventoryController used to hold). Scaled
-- against simulated income at each tier so the next rod is roughly 1.5 -> 24 minutes of
-- fishing at the rate of the rod you are on.
M.ROD_CASH = {
	[2] = 7000,      [3] = 20000,     [4] = 65000,      [5] = 140000,
	[6] = 450000,    [7] = 900000,    [8] = 2500000,    [9] = 5000000,   [10] = 18000000,
}
-- Robux ladder. Priced as "skip the grind", not as a second economy: each rung is roughly
-- what the cash cost is worth in time at that stage of the game.
M.ROD_ROBUX = {
	[2] = 49,        [3] = 79,        [4] = 99,         [5] = 149,
	[6] = 199,       [7] = 299,       [8] = 399,        [9] = 599,       [10] = 899,
}
-- Zones (ZonesController; the cash costs live there - $20K / $120K / $900K / $6M / $22M). Priced ON the rods' ladder:
-- each zone takes the Robux rung of the rod whose cash cost is nearest its own, so a zone and a rod that cost the same
-- coins cost the same Robux. Same rule as the cash key: only the zone after your last one can be bought (2026-10-10).
M.ZONE_ROBUX = { [2] = 299, [3] = 399, [4] = 599, [5] = 699, [6] = 899 }   -- (2026-10-10, the owner's ladder; first 79 / 149 / 299 / 599 / 899)

----------------------------------------------------------------------
-- 3. BAITS  (priced by RARITY, not per bait - the roller's odds already span 1/2 to
--    1/435,000,000 and pricing off that curve directly gives absurd numbers)
----------------------------------------------------------------------
-- `pack` is how many you get per purchase: commons come in tens because you burn one per
-- cast, a Divine comes one at a time because it is a 1-in-435-million pull.
M.BAIT_BY_RARITY = {
	Common    = { cash = 500,      robux = 9,   pack = 10 },
	Uncommon  = { cash = 2500,     robux = 19,  pack = 5  },
	Rare      = { cash = 15000,    robux = 39,  pack = 3  },
	Epic      = { cash = 90000,    robux = 79,  pack = 2  },
	Legendary = { cash = 600000,   robux = 149, pack = 1  },
	Mythic    = { cash = 4000000,  robux = 299, pack = 1  },
	Divine    = { cash = 30000000, robux = 599, pack = 1  },
}

----------------------------------------------------------------------
-- 4. BOOSTS  (the Inventory's four potions + the jackpot cast)
----------------------------------------------------------------------
-- Robux matches ShopController's existing 1x potion price (29) so the same item does not
-- cost two different amounts depending on which menu you buy it from.
M.BOOST = {
	potion_luck  = { cash = 75000,  robux = 29, pack = 1 },
	potion_cast  = { cash = 75000,  robux = 29, pack = 1 },
	potion_bite  = { cash = 75000,  robux = 29, pack = 1 },
	potion_money = { cash = 75000,  robux = 29, pack = 1 },
	jackpot      = { cash = 250000, robux = 49, pack = 1 },
}

----------------------------------------------------------------------
-- 5. lookups
----------------------------------------------------------------------
-- Attribute names only allow [A-Za-z0-9_], so bait keys are the stripped name. Keep this
-- identical to InventoryController's and RollerController's akey().
function M.akey(s) return (string.gsub(s, "[^%w]", "")) end

-- kind is "rod" | "bait" | "boost"; key is the tier number, the bait akey, or the boost key
function M.productKey(kind, key)
	return kind .. "_" .. tostring(key)
end

function M.productId(kind, key)
	return M.PRODUCTS[M.productKey(kind, key)] or 0
end

-- What a purchase hands over. Used by the client to grant a CASH buy and by the server's
-- ProcessReceipt to grant a ROBUX one, so both routes deliver exactly the same thing.
function M.grant(kind, key)
	if kind == "rod" then
		return { kind = "rod", tier = tonumber(key), qty = 1 }
	elseif kind == "bait" then
		return { kind = "bait", key = key, qty = 1 }      -- qty filled by the caller from pack
	elseif kind == "boost" then
		return { kind = "boost", key = key, qty = 1 }
	elseif kind == "zone" then
		return { kind = "zone", id = tonumber(key), qty = 1 }
	end
	return nil
end

-- REVERSE map, built once: product id -> { kind, key }. Ids left at 0 are skipped, and a
-- duplicate id is a configuration error worth shouting about rather than silently
-- granting whichever entry happened to be iterated last.
function M.byProductId()
	local map = {}
	for pkey, id in pairs(M.PRODUCTS) do
		if type(id) == "number" and id > 0 then
			local kind, key = pkey:match("^(%a+)_(.+)$")
			if kind then
				if map[id] then
					warn(string.format("[ShopProducts] product id %d is used by BOTH %s and %s_%s",
						id, map[id].kind .. "_" .. tostring(map[id].key), kind, key))
				else
					map[id] = { kind = kind, key = key }
				end
			end
		end
	end
	return map
end

-- How many of a thing one purchase grants.
function M.packFor(kind, key, rarity)
	if kind == "bait" then
		local r = M.BAIT_BY_RARITY[rarity or ""]
		return r and r.pack or 1
	elseif kind == "boost" then
		local b = M.BOOST[key]
		return b and b.pack or 1
	end
	return 1
end

----------------------------------------------------------------------
-- 6. THE SHOP WINDOW (StarterGui.ShopMenu, rebuilt 2026-10-10 in the +1 snowball shop's design)
----------------------------------------------------------------------
-- Game pass ids (0 = not set up yet) and the Robux price each shows until Roblox's live price loads. A pass the player
-- owns is published as the attribute Pass_<key> = true (the passes' effects are not wired into the game yet).
M.PASS_IDS = { luck = 2026382652, money = 2026988676, cast = 2025194660, bite = 2025590681, slot = 2025434674, double = 2026706646 }
M.PASS_ROBUX = { luck = 399, money = 399, cast = 399, bite = 399, slot = 399, double = 899 }

-- Cash packs: product "cash_<key>"; `cash` is what one purchase pays into leaderstats.Money. Sized against this economy
-- (the last rod is $18M, the last boat $150M); bigger packs give more per Robux.
M.CASH_PACKS = {
	{ key = "1", cash = 50000,    robux = 39 },
	{ key = "2", cash = 150000,   robux = 99 },
	{ key = "3", cash = 400000,   robux = 199 },
	{ key = "4", cash = 1200000,  robux = 499 },
	{ key = "5", cash = 3000000,  robux = 999 },
	{ key = "6", cash = 10000000, robux = 2499 },
}
function M.cashPack(key)
	for _, p in ipairs(M.CASH_PACKS) do
		if tostring(p.key) == tostring(key) then return p end
	end
	return nil
end

-- The Starter Pack (product "starter_pack"; one per session: the StarterBought attribute): what it hands over.
M.STARTER = { robux = 99, potions = 2, jackpot = 1, cash = 25000 }

-- Product kinds only the Shop window grants: ProductServer fires these on ShopRemotes.ShopGranted, not Granted.
M.SHOP_KINDS = { cash = true, starter = true }
-- ...and the kind only the Zones window grants: ProductServer fires it on ShopRemotes.ZoneGranted.
M.ZONE_KINDS = { zone = true }

return M
