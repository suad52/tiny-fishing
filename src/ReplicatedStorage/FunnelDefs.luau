--[==[
	FunnelDefs - every Roblox Analytics funnel this game logs, in ONE table both ends read.

	FunnelServer logs the steps (AnalyticsService is server-only); FunnelClient watches the
	player attributes the client-side economy writes and reports when a new step is reached;
	TutorialController reports its beats by KEY. Nothing else needs to know the numbering.

	ONBOARDING  -> AnalyticsService:LogOnboardingFunnelStepEvent  (the dashboard's Onboarding funnel)
	FUNNELS     -> AnalyticsService:LogFunnelStepEvent, funnelSessionId = nil = ONE-TIME per user,
	               so each step counts the players who EVER reached it.

	Every progression funnel is a "reached at least level N" ladder (highest zone / rod / boat
	owned, rebirth count, a threshold crossed), never a mix of tracks: Roblox fills in any step a
	player skips past, and that is only true when step N really implies every step below it.

	⚠️ Never renumber or reorder a live funnel - accounts that already logged step 4 would read as
	having reached whatever is step 4 now. Add steps at the END, or retire the funnel under a new name.
]==]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local D = {}

-- The tutorial, beat by beat. "joined" is logged by the server on PlayerAdded; "loaded" by
-- FunnelClient when the loading screen lifts; the rest by TutorialController.
D.ONBOARDING = {
	{ key = "joined",   name = "Joined" },
	{ key = "loaded",   name = "Loaded In" },
	{ key = "shown",    name = "Tutorial Started" },
	{ key = "cast",     name = "First Cast" },
	{ key = "catch",    name = "First Catch" },
	{ key = "paid",     name = "First Payout" },
	{ key = "rolled",   name = "Rolled Bait" },
	{ key = "baits",    name = "Opened Baits" },
	{ key = "equipped", name = "Equipped Bait" },
	{ key = "upgrades", name = "Opened Upgrades" },
	{ key = "bought",   name = "First Purchase" },
	{ key = "zones",    name = "Opened Zones" },
	{ key = "complete", name = "Tutorial Complete" },
}
D.ONBOARD_INDEX = {}
for i, s in ipairs(D.ONBOARDING) do D.ONBOARD_INDEX[s.key] = i end

local function money(n)
	if n >= 1e9 then return "$" .. (n / 1e9) .. "B" end
	if n >= 1e6 then return "$" .. (n / 1e6) .. "M" end
	if n >= 1e3 then return "$" .. (n / 1e3) .. "K" end
	return "$" .. n
end

local boatSteps = {}
do
	local ok, BoatData = pcall(function() return require(ReplicatedStorage:WaitForChild("BoatData", 10)) end)
	local tiers = ok and BoatData and BoatData.TIERS or {}
	for i = 1, math.max(#tiers, 8) do
		local b = tiers[i]
		boatSteps[i] = "Boat " .. i .. ": " .. tostring(b and b.name or ("Tier " .. i))
	end
end

local EARN = { 0, 1, 1e3, 1e4, 5e4, 2.5e5, 1e6, 5e6, 2.5e7, 1e8, 1e9 }
local earnSteps = { "Joined", "First Sale" }
for i = 3, #EARN do earnSteps[i] = "Earned " .. money(EARN[i]) end

local SPECIES = { 0, 1, 5, 10, 20, 30, 40, 50, 61 }
local indexSteps = { "Joined" }
for i = 2, #SPECIES do
	indexSteps[i] = SPECIES[i] == 61 and "All 61 Species" or (SPECIES[i] .. " Species")
end

-- name    : the funnel name on the dashboard (Roblox allows only a handful per experience - keep these few)
-- steps   : step names; step 1 is the baseline every player has, logged by the server on join
-- attr    : how FunnelClient reads the player's level ("highest" = highest <prefix>N that is true,
--           "count" = attribute + 1, "threshold" = how many thresholds the attribute has reached)
D.FUNNELS = {
	{ name = "Zones", attr = { kind = "highest", prefix = "Zone_" }, steps = {
		"Zone 1: Lighthouse Cove", "Zone 2: Tropical Reef", "Zone 3: Golden Sunset Bay",
		"Zone 4: Frostbite Fjord", "Zone 5: Midnight Trench", "Zone 6: Molten Abyss",
	} },
	{ name = "Rods", attr = { kind = "highest", prefix = "Rod_" }, steps = {
		"Rod 1: Oakwood", "Rod 2: Fiberglass", "Rod 3: Carbon", "Rod 4: Bronze Angler", "Rod 5: Silver Tide",
		"Rod 6: Golden Lure", "Rod 7: Emerald", "Rod 8: Frost Crystal", "Rod 9: Inferno", "Rod 10: Cosmic",
	} },
	{ name = "Boats", attr = { kind = "highest", prefix = "Boat_" }, steps = boatSteps },
	{ name = "Rebirths", attr = { kind = "count", name = "Rebirths" }, steps = {
		"Start: Tide Pool Novice", "Rebirth 1: Shallows Angler", "Rebirth 2: Reef Diver", "Rebirth 3: Kelp Ranger",
		"Rebirth 4: Open Water Sailor", "Rebirth 5: Deep Sea Hunter", "Rebirth 6: Twilight Diver",
		"Rebirth 7: Midnight Master", "Rebirth 8: Abyssal Legend", "Rebirth 9: Trench Sovereign",
		"Rebirth 10: Leviathan Lord", "Rebirth 11: Kraken Ascendant",
	} },
	-- QT_earn is QuestsController's running total of everything earned this session
	{ name = "Earnings", attr = { kind = "threshold", name = "QT_earn", at = EARN }, steps = earnSteps },
	{ name = "Fish Index", attr = { kind = "threshold", name = "Discovered", at = SPECIES }, steps = indexSteps },
}
D.byName = {}
for _, f in ipairs(D.FUNNELS) do D.byName[f.name] = f end

-- The level a player is at on funnel f, from their attributes (1 = the baseline).
function D.levelOf(plr, f)
	local a, n = f.attr, #f.steps
	if a.kind == "highest" then
		for i = n, 2, -1 do
			if plr:GetAttribute(a.prefix .. i) == true then return i end
		end
		return 1
	elseif a.kind == "count" then
		return math.clamp((tonumber(plr:GetAttribute(a.name)) or 0) + 1, 1, n)
	else
		local v, lvl = tonumber(plr:GetAttribute(a.name)) or 0, 1
		for i, t in ipairs(a.at) do
			if v >= t then lvl = i end
		end
		return math.min(lvl, n)
	end
end

-- Which funnel an attribute change can move, or nil.
function D.funnelFor(attrName)
	for _, f in ipairs(D.FUNNELS) do
		local a = f.attr
		if a.prefix then
			if attrName:match("^" .. a.prefix .. "%d+$") then return f end
		elseif a.name == attrName then
			return f
		end
	end
	return nil
end

return D
