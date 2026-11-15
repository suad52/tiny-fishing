--[==[
	BoatData - the boat progression catalog.

	EIGHT TIERS. Tier 1 is the Wooden Rowboat that was already in the world; tiers 2-8 are
	built at runtime by BoatBuilder from the `hull` spec below. Owning a boat is the player
	attribute `Boat_<id>`; the one you are sailing is `CurrentBoat`. BoatClient turns the
	active tier into the `Boat*` stat attributes that GameClient reads.

	THE RIG CONTRACT (do not break these - the whole 2.5D stage is measured off them)
	  * The seat is FIXED. `Workspace.Rowboat.RowSeat` sits at world (3.7295, 2.175, 2.400)
	    and FishingServer sits the player there. It is one server-owned instance shared by
	    everyone, so it can never move per-player. Every hull is therefore authored AROUND
	    that point: local origin is the waterline directly under the seat, and each boat must
	    put walkable deck at local (0, deckY, 0) with a seat pedestal reaching seatY 2.175.
	  * Local +X points AFT (stern, screen-right), local -X FORWARD (bow, screen-left),
	    local +Z toward the camera, local Y up with the waterline at 0.
	  * The model is placed at CFrame.new(3.7295, 0, 2.400) * CFrame.Angles(0, -30deg, 0),
	    which is the same 30-degree three-quarter yaw the original rowboat has. So local +X
	    maps to world (0.866, 0, 0.5) and local +Z maps to world (-0.5, 0, 0.866): a local
	    length L along the keel only shows 0.866*L of on-screen width, and the beam adds
	    another 0.5*beam/2 at each end.

	STAYING IN FRAME. The play camera is clamped to MAX_CAM_DIST 140 at FOV 20, so on 16:9
	the visible span is ~87.8 studs (+/-43.9). The BaitRoller owns the left ~22.8% and the
	MainMenu bar the right ~22.8%, leaving a centre channel of ~54.6% = ~48 studs, i.e.
	roughly world X -24 .. +24. Every hull below is sized so its world AABB lands inside
	that, which is why `aft` grows only slowly while `fwd` carries the length: the angler is
	pinned at x 3.73, so a boat can only get longer by reaching further to screen-left.
	The `span` column in each entry is the measured world-X width - keep it under ~35.
]==]

local M = {}

-- Where the fixed seat is, and the yaw every hull is placed at.
M.SEAT_POS  = Vector3.new(3.7295, 2.175, 2.400)
M.ORIGIN    = Vector3.new(3.7295, 0, 2.400)   -- waterline under the seat = each hull's local origin
M.YAW       = -30                              -- degrees
M.SEAT_Y    = 2.175                            -- local Y the seat pedestal has to reach

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

--[[
	Each tier:
	  id / name / emoji / blurb   - presentation
	  cost                        - price in the shared money balance (0 = free starter)
	  coin / cap / luck / reel / depth
	                              - the stat payload. coin and reel are MULTIPLIERS folded
	                                into GameClient's existing product chains; cap, luck and
	                                depth are ADDITIVE terms in its existing sums.
	                                NOTE ON DEPTH: GameClient clamps total depth to
	                                DEPTH_LIMIT 640 because the painted water column only
	                                runs to -660. A player with the depth branch maxed (320)
	                                and a tier-10 rod (300) is already at 620, so the last
	                                boats' depth is partly eaten by that clamp at full
	                                endgame. It is fully effective everywhere before that.
	  land                        - where a paid-out fish is thrown. y must sit BELOW the
	                                near gunwale so the fish drops out of sight into the
	                                hull on its own; x0..x1 must be open deck, never the
	                                cabin roof and never on top of the angler at x 3.73.
	  hull                        - geometry for BoatBuilder (tier 1 has none: it is the
	                                authored model already in Workspace).
]]
M.TIERS = {
	{
		id = 1,
		name = "Wooden Rowboat",
		short = "Rowboat",
		emoji = "\u{1F6A3}",
		blurb = "Grandpa's leaky clinker rowboat. It floats, mostly, and it is yours.",
		cost = 0,
		coin = 1.00, cap = 0, luck = 0.00, reel = 1.00, depth = 0,
		land = { y = 1.3, x0 = -4.0, x1 = 2.5 },
		authored = true,        -- the model already in Workspace.Rowboat, not built
		span = 15.1,
		-- Tier 1 still carries a hull spec, but ONLY so the menu has something to draw in its
		-- ViewportFrame - a likeness of the authored rowboat. `authored` is what stops it
		-- being built into the world; the real 537-instance model stays where it is.
		hull = {
			-- DOUBLE-ENDER: pointed at both ends, heavy rocker, no transom at all.
			sheerStyle = "sweep", rocker = "round", section = "round", plan = "fine",
			stem = "canoe", stern = "canoe",
			aft = 2.6, fwd = 11.0, beam = 6.0, draft = 1.5, deck = 1.15, sheer = 2.70,
			bowRise = 1.85, sternRise = 1.45, sternRocker = 0.85, transom = 0.16, planks = 5,
			hullTop = rgb(104, 74, 52), hullBot = rgb(62, 46, 36), deckCol = rgb(150, 112, 76),
			trim = rgb(176, 138, 92), accent = rgb(74, 54, 40), cabin = rgb(150, 112, 76),
			deco = { seat = "thwart", oars = true, rail = true, ribs = 3, crate = { x = -7.8 } },
		},
	},

	{
		id = 2,
		name = "Reinforced Wooden Skiff",
		short = "Skiff",
		emoji = "\u{1F6F6}",
		blurb = "Doubled ribs, fresh pitch and a brass rail. The same boat that stopped sinking.",
		cost = 5000,
		coin = 1.15, cap = 1, luck = 0.02, reel = 1.05, depth = 10,
		land = { y = 1.5, x0 = -4.5, x1 = 2.4 },
		span = 16.9,
		hull = {
			-- FLAT-BOTTOMED PUNT: hard chine, straight sheer, wide square transom. The bottom
			-- runs dead flat and the sides go up almost vertically - a wedge, not a curve.
			sheerStyle = "flat", rocker = "flat", section = "flat", plan = "wide",
			stem = "raked", stemRake = 26, stern = "transom", transomRake = 4, chine = true,
			aft = 3.2, fwd = 12.5, beam = 6.6, draft = 1.4, deck = 1.30, sheer = 2.75,
			bowRise = 1.55, sternRise = 0.00, sternRocker = 0.06, transom = 0.86, planks = 5,
			hullTop = rgb(168, 118, 74), hullBot = rgb(96, 70, 52), deckCol = rgb(196, 152, 104),
			trim = rgb(214, 174, 96), accent = rgb(120, 78, 52), cabin = rgb(196, 152, 104),
			deco = {
				seat = "thwart", oars = true, rail = true, ribs = 4,
				crate = { x = -8.2 }, lamp = { x = -10.0 },
			},
		},
	},

	{
		id = 3,
		name = "Aluminum Bass Boat",
		short = "Bass Boat",
		emoji = "\u{1F3A3}",
		blurb = "Riveted aluminium, a flat casting deck and an outboard that actually starts.",
		cost = 45000,
		coin = 1.35, cap = 1, luck = 0.05, reel = 1.14, depth = 24,
		land = { y = 1.75, x0 = -5.0, x1 = 2.4 },
		span = 19.7,
		hull = {
			-- PLANING WEDGE: the lowest freeboard-to-length of the eight, a dead-flat run aft,
			-- a sharply raked pointed bow, and raised casting platforms fore and aft.
			sheerStyle = "flat", rocker = "flat", section = "flat", plan = "wide",
			stem = "raked", stemRake = 34, stern = "transom", transomRake = 2, chine = true,
			-- fore deck stops at u 0.27 so it does not swallow the console at x -8.6
			deckStep = { { 0.05, 0.27, 0.42 }, { 0.90, 1.00, 0.34 } },
			aft = 3.6, fwd = 15.0, beam = 7.2, draft = 1.15, deck = 1.40, sheer = 2.40,
			bowRise = 1.30, sternRise = 0.00, sternRocker = 0.00, transom = 0.94, planks = 3,
			hullTop = rgb(186, 194, 202), hullBot = rgb(120, 130, 140), deckCol = rgb(96, 104, 112),
			trim = rgb(196, 46, 46), accent = rgb(38, 42, 48), cabin = rgb(210, 216, 222),
			deco = {
				seat = "pedestal", outboard = "small", rail = true, stripe = true, rodholders = 2,
				console = { kind = "small", x = -8.6 },
				-- no livewell: the forward casting platform now occupies that stretch of deck
			},
		},
	},

	{
		id = 4,
		name = "Fiberglass Center Console",
		short = "Center Console",
		emoji = "\u{1F6E5}",
		blurb = "Gelcoat white, a teak sole and a T-top you can finally stand under.",
		cost = 400000,
		coin = 1.65, cap = 2, luck = 0.09, reel = 1.22, depth = 40,
		land = { y = 1.95, x0 = -5.5, x1 = 2.4 },
		span = 22.8,
		hull = {
			-- DEEP V: a narrow knife at the keel opening out to full beam at the rail, with one
			-- long continuous sheer lift to a tall flared bow. Nothing else here is V-sectioned.
			sheerStyle = "rise", rocker = "vee", section = "vee", plan = "sharp",
			stem = "raked", stemRake = 24, stern = "transom", transomRake = 8,
			aft = 4.2, fwd = 17.5, beam = 8.0, draft = 2.15, deck = 1.55, sheer = 2.85,
			bowRise = 2.95, sternRise = 0.00, sternRocker = 0.00, transom = 0.88, planks = 4,
			hullTop = rgb(244, 246, 249), hullBot = rgb(30, 58, 104), deckCol = rgb(188, 146, 96),
			trim = rgb(26, 72, 148), accent = rgb(52, 60, 70), cabin = rgb(238, 241, 245),
			deco = {
				seat = "chair", outboard = "twin", rail = true, stripe = true,
				rodholders = 4, bowrail = true,
				console = { kind = "ttop", x = -9.8 },
				cooler = { x = -14.2 },
			},
		},
	},

	{
		id = 5,
		name = "Commercial Trawler",
		short = "Trawler",
		emoji = "\u{26F4}",
		blurb = "Steel, diesel and a net winch. This is the boat that turns fishing into a job.",
		cost = 3500000,
		coin = 2.10, cap = 3, luck = 0.14, reel = 1.32, depth = 58,
		land = { y = 2.10, x0 = -6.0, x1 = 2.4 },
		span = 26.2,
		hull = {
			-- ROUND-BILGE DISPLACEMENT: deep long forefoot, plumb stem, and the tallest
			-- bulwarks of any tier - a chunky, heavy, high-sided workboat.
			sheerStyle = "sweep", rocker = "deep", section = "round", plan = "fine",
			stem = "plumb", stern = "transom", transomRake = 16,
			aft = 5.0, fwd = 20.0, beam = 9.0, draft = 2.6, deck = 1.70, sheer = 4.05,
			bowRise = 2.05, sternRise = 0.85, sternRocker = 0.30, transom = 0.74, planks = 5,
			hullTop = rgb(46, 108, 88), hullBot = rgb(126, 60, 44), deckCol = rgb(120, 112, 98),
			trim = rgb(238, 226, 196), accent = rgb(38, 44, 50), cabin = rgb(238, 226, 196),
			deco = {
				seat = "stool", rail = true, stripe = true, tyres = 3,
				wheelhouse = { x0 = -17.5, x1 = -10.0, h = 4.2, windows = 4 },
				funnel = { x = -12.2 },
				mast = { x = -8.6, base = 1.9, h = 5.0, floods = true },
				nets = { x = 3.6 },
				gantry = { x = 4.5 },
			},
		},
	},

	{
		id = 6,
		name = "Sportfishing Cabin Cruiser",
		short = "Cabin Cruiser",
		emoji = "\u{1F6E5}",
		blurb = "Flybridge, outriggers and a fighting chair bolted to the cockpit sole.",
		-- \226\154\160 Tiers 6-8 were 30M / 250M / 2,000M. That top rung alone was 94% of the price of
		-- EVERYTHING in the game (all rods 18M + all zones 29M + the whole upgrade tree 87M = 134M),
		-- which made every other price in the game read as pocket change. The early rungs are
		-- untouched - they were fine; only the runaway tail is compressed, so the curve now
		-- DECELERATES (9x, 8.9x, 8.75x, 4.3x, 3.3x, 3x) instead of running 8.5x to the moon.
		cost = 15000000,
		coin = 2.70, cap = 4, luck = 0.20, reel = 1.44, depth = 74,
		land = { y = 2.10, x0 = -6.0, x1 = 2.4 },
		span = 29.2,
		hull = {
			-- LONG AND LOW: a fine entry, a raked bow, and a sheer that FALLS aft into a
			-- cut-down cockpit - the sportfisher signature. Its height is all superstructure.
			sheerStyle = "drop", rocker = "vee", section = "vee", plan = "sharp",
			stem = "raked", stemRake = 18, stern = "transom", transomRake = 6,
			aft = 7.1, fwd = 21.0, beam = 9.8, draft = 1.9, deck = 1.60, sheer = 3.45,
			bowRise = 2.55, sternRise = 1.05, sternRocker = 0.06, transom = 0.86, planks = 4,
			hullTop = rgb(246, 248, 251), hullBot = rgb(22, 46, 92), deckCol = rgb(196, 154, 102),
			trim = rgb(28, 84, 176), accent = rgb(46, 54, 64), cabin = rgb(240, 243, 247),
			deco = {
				seat = "fightingchair", rail = true, stripe = true, rodholders = 5, bowrail = true,
				-- x1 -7.0 not -6.8: the roof lip overhangs the cabin by 0.475 a side, and at
				-- -6.8 it just crossed the x -6.5 corridor edge
				cabin = { x0 = -15.6, x1 = -7.0, h = 3.0, windows = 5 },
				flybridge = { x = -10.9 },
				-- forward of the flybridge helm seat (which sits at flybridge.x + 1.1); at
				-- x -11.0 the mast was driven straight through it
				mast = { x = -12.6, base = "roof", h = 2.8, radar = true },
				-- mounted at the bridge, not amidships: at x -3.4 the near pole rose out of the
				-- frame right beside the seated angler's head
				outriggers = { x = -7.2 },
			},
		},
	},

	{
		id = 7,
		name = "Deep-Sea Crabber",
		short = "Crabber",
		emoji = "\u{1F980}",
		blurb = "Pot stacks to the rail and a picking crane. Built for weather that bites back.",
		cost = 50000000,
		coin = 3.50, cap = 6, luck = 0.28, reel = 1.56, depth = 92,
		land = { y = 2.30, x0 = -6.5, x1 = 2.4 },
		span = 31.9,
		hull = {
			-- HIGH BOW, LOW WORKING DECK: the most dramatic sheer of the eight - a towering
			-- flared forefoot dropping away to a long low deck you could roll a pot across.
			sheerStyle = "drop", rocker = "deep", section = "round", plan = "blunt",
			stem = "plumb", stern = "transom", transomRake = 14,
			aft = 8.7, fwd = 22.0, beam = 10.6, draft = 2.7, deck = 1.72, sheer = 4.15,
			bowRise = 3.45, sternRise = 1.15, sternRocker = 0.28, transom = 0.80, planks = 5,
			hullTop = rgb(206, 96, 40), hullBot = rgb(96, 44, 34), deckCol = rgb(112, 106, 96),
			trim = rgb(232, 236, 240), accent = rgb(40, 46, 54), cabin = rgb(214, 220, 226),
			deco = {
				seat = "stool", rail = true, stripe = true, tyres = 4,
				wheelhouse = { x0 = -20.5, x1 = -14.2, h = 4.4, windows = 4 },
				funnel = { x = -16.5 },
				-- ON the wheelhouse roof. Deck-stepped at x -14.8 it ran straight through the
				-- third pot stack and both of its floodlights.
				mast = { x = -17.2, base = "roof", h = 4.2, floods = true },
				pots = { n = 6, x = -8.0, step = 2.3 },
				gantry = { x = 7.0 },
			},
		},
	},

	{
		id = 8,
		name = "Abyssal Factory Ship",
		short = "Factory Ship",
		emoji = "\u{1F6A2}",
		blurb = "A processing deck, a sonar mast and a hold that has never once been filled.",
		cost = 150000000,
		coin = 4.60, cap = 8, luck = 0.38, reel = 1.70, depth = 112,
		land = { y = 2.40, x0 = -7.0, x1 = 2.4 },
		span = 34.5,
		hull = {
			-- A SHIP, NOT A BOAT: slab sides, a bluff bow with a bulb, a long parallel middle
			-- body, near-straight sheer carried at full height end to end, and a counter stern.
			sheerStyle = "ship", rocker = "ship", section = "slab", plan = "blunt",
			stem = "bulb", stern = "counter", transomRake = 2,
			aft = 10.3, fwd = 23.0, beam = 11.4, draft = 2.9, deck = 1.75, sheer = 4.75,
			bowRise = 1.15, sternRise = 0.45, sternRocker = 0.08, transom = 0.90, planks = 6,
			hullTop = rgb(38, 62, 96), hullBot = rgb(24, 34, 52), deckCol = rgb(96, 102, 112),
			trim = rgb(240, 196, 78), accent = rgb(28, 34, 44), cabin = rgb(226, 232, 240),
			deco = {
				seat = "stool", rail = true, stripe = true, tyres = 4,
				wheelhouse = { x0 = -21.5, x1 = -14.0, h = 4.8, windows = 5 },
				funnel = { x = -16.8 },
				mast = { x = -19.0, base = "roof", h = 5.0, radar = true, floods = true },
				containers = { n = 3, x = -7.8, step = 2.4 },
				crane = { x = 5.4, reach = 4.6 },
			},
		},
	},
}

M.MAX_TIER = #M.TIERS

function M.get(id)
	-- math.clamp passes NaN straight through (it is neither < min nor > max), and
	-- TIERS[NaN] is nil, which would crash the caller on the next field access. Attributes
	-- are client-writable, so this is reachable by anything that writes a bad CurrentBoat.
	id = tonumber(id) or 1
	if id ~= id then id = 1 end
	return M.TIERS[math.clamp(math.floor(id), 1, M.MAX_TIER)]
end

-- Short money label for the cards: 5000 -> "$5K", 2e9 -> "$2B".
function M.price(n)
	if n <= 0 then return "FREE" end
	local a = math.abs(n)
	if a >= 1e12 then return string.format("$%.4g", n / 1e12) .. "T" end
	if a >= 1e9  then return string.format("$%.4g", n / 1e9)  .. "B" end
	if a >= 1e6  then return string.format("$%.4g", n / 1e6)  .. "M" end
	if a >= 1e3  then return string.format("$%.4g", n / 1e3)  .. "K" end
	return "$" .. tostring(math.floor(n))
end

-- The badge that sits ON the preview. One term only - the full list is five stats long
-- and an AutomaticSize badge carrying all of them runs straight off the side of the card
-- and gets clipped, which is what the first build did.
function M.headline(t)
	if not t.coin or t.coin <= 1 then return "Starter boat" end
	return string.format("x%.2g coins", t.coin)
end

-- The full stat line under the boat's name. Only prints the terms that actually differ
-- from the rowboat, so tier 1 reads "Starter boat" instead of a row of +0s.
function M.benefits(t)
	local p = {}
	if t.coin  and t.coin  > 1 then table.insert(p, string.format("x%.2g coins", t.coin)) end
	if t.cap   and t.cap   > 0 then table.insert(p, "+" .. t.cap .. " hook") end
	if t.depth and t.depth > 0 then table.insert(p, "+" .. t.depth .. " depth") end
	if t.luck  and t.luck  > 0 then table.insert(p, string.format("+%d%% luck", math.floor(t.luck * 100 + 0.5))) end
	if t.reel  and t.reel  > 1 then table.insert(p, string.format("x%.2g reel", t.reel)) end
	if #p == 0 then return "Starter boat" end
	return table.concat(p, "  \u{2022}  ")
end

return M
