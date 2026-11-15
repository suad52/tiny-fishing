--[==[
	BoatBuilder - turns a BoatData `hull` spec into a cartoon flat-shaded boat model.

	WHY HAND-BUILT AND NOT A TOOLBOX MESH. The stage is a strict side-on 2.5D frame with a
	painted flat backdrop. Marketplace boats are realistic, textured and 40-80 studs long;
	scaled into this frame their detail collapses into noise and their shading fights the
	flat art. They also cannot honour the rig contract (see BoatData) - the seat is fixed,
	so a hull has to be authored AROUND a given point. Two candidates were inserted and
	photographed side-on before this call was made.

	HOW A HULL IS BUILT. The boat is a lofted set of STATIONS along the keel. For each
	station we know three curves:
	  keelY(u)  - the bottom. Rises out of the water toward the bow, so the hull rockers.
	  sheerY(u) - the top edge. Lifts at the bow (bowRise) and a little at the stern.
	  width(u)  - the plan taper: a fine point at the bow, full beam at ~44% aft, then
	              easing back to `transom` at the stern.
	Each station emits a SOLID underbody from keelY up to the deck (split at the waterline
	so the bottom paint and the topsides are different colours, with an optional boot
	stripe between them), a thin deck plate, and two thin BULWARK plates above the deck.

	The underbody is solid but everything above the deck is only side walls - that is
	deliberate. The angler is seated at local y 2.175 and would be buried inside a solid
	hull. Every `deck` value in BoatData is <= 2.05 for the same reason.

	THE CLEAR CORRIDOR. The seated character occupies roughly local x -1.5..+1.5,
	z -1.5..+1.5, y 2.0..6.5, and the rod sweeps forward and down from their hands. So no
	deco may occupy x -6.5..+2.5 above y 2.5. Every overhead structure (T-top, flybridge,
	gantry beam, crane boom) is therefore placed either aft of x +2.5 or forward of x -6.5.
	Break this and the rod clips through a cabin roof on every cast.

	OUTPUT. `build(t)` returns a Model in LOCAL coordinates with an invisible `Root`
	PrimaryPart at the local origin, already pivoted to the world placement. Re-pivot it
	freely for a ViewportFrame. Every part is Anchored, CanCollide=false, CanQuery=false.
]==]

local BoatData = require(script.Parent:WaitForChild("BoatData"))

local B = {}

local SM = Enum.Material.SmoothPlastic
local SMOOTH = Enum.SurfaceType.Smooth

----------------------------------------------------------------------
-- primitives
----------------------------------------------------------------------
local function shape(class, parent, name, size, cf, color, mat, trans)
	local p = Instance.new(class)
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or SM
	p.Transparency = trans or 0
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	if p:IsA("Part") then
		p.TopSurface = SMOOTH
		p.BottomSurface = SMOOTH
	end
	p.Parent = parent
	return p
end

local function box(parent, name, size, cf, color, mat, trans)
	return shape("Part", parent, name, size, cf, color, mat, trans)
end

local function wedge(parent, name, size, cf, color, mat)
	return shape("WedgePart", parent, name, size, cf, color, mat)
end

local function cyl(parent, name, size, cf, color, mat, trans)
	local p = shape("Part", parent, name, size, cf, color, mat, trans)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent, name, d, cf, color, mat)
	local p = shape("Part", parent, name, Vector3.new(d, d, d), cf, color, mat)
	p.Shape = Enum.PartType.Ball
	return p
end

-- A cylinder standing on its Y axis (Roblox cylinders are X-axis by default).
local function post(parent, name, d, len, x, y, z, color, mat)
	return cyl(parent, name, Vector3.new(len, d, d),
		CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(90)), color, mat)
end

local function at(x, y, z) return CFrame.new(x, y, z) end
local function lerp(a, b, t) return a + (b - a) * t end

local function darken(c, k)
	return Color3.new(c.R * (1 - k), c.G * (1 - k), c.B * (1 - k))
end
local function lighten(c, k)
	return Color3.new(c.R + (1 - c.R) * k, c.G + (1 - c.G) * k, c.B + (1 - c.B) * k)
end

----------------------------------------------------------------------
-- the three hull curves
----------------------------------------------------------------------
-- u runs 0 at the bow tip to 1 at the transom.
--
-- FOUR STYLE TABLES, and they are the whole point of this section. Eight boats run through
-- one lofted-station routine read as ONE BOAT IN EIGHT SIZES unless the curves themselves
-- differ - which is exactly what the first version shipped. Dimensions, paint and deck
-- clutter are not enough; the sheer line, the rocker, the section and the plan taper are
-- what the eye actually reads at 250 px wide.

-- PLAN: beam as a fraction of h.beam along the length.
local PLAN = {
	fine = function(u, tr)        -- classic small boat: fine entry, full beam ~44% aft
		if u < 0.44 then return 0.07 + 0.93 * (u / 0.44) ^ 0.62 end
		return 1 - (1 - tr) * ((u - 0.44) / 0.56) ^ 1.35
	end,
	wide = function(u, tr)        -- planing hull: beam comes on fast and is carried aft
		if u < 0.30 then return 0.10 + 0.90 * (u / 0.30) ^ 0.50 end
		return 1 - (1 - tr) * ((u - 0.30) / 0.70) ^ 2.2
	end,
	sharp = function(u, tr)       -- long fine entry, narrow quarters (cruiser)
		if u < 0.56 then return 0.05 + 0.95 * (u / 0.56) ^ 0.88 end
		return 1 - (1 - tr) * ((u - 0.56) / 0.44) ^ 1.2
	end,
	blunt = function(u, tr)       -- ship: bluff bow and a long parallel middle body
		if u < 0.22 then return 0.34 + 0.66 * (u / 0.22) ^ 0.7 end
		return 1 - (1 - tr) * ((u - 0.22) / 0.78) ^ 3.0
	end,
}

-- SECTION: width as a fraction of the station beam, in three bands from keel to deck.
-- This is what separates a flat-bottomed skiff from a deep-V console at the same length.
local SECTION = {
	round = { 0.58, 0.86, 1.00 },   -- displacement bilge
	vee   = { 0.24, 0.64, 1.00 },   -- deep V
	flat  = { 0.92, 0.99, 1.00 },   -- hard chine, flat bottom
	slab  = { 0.95, 1.00, 1.00 },   -- ship sides, near vertical
}

-- SHEER: returns (bowTerm, sternTerm), scaled by h.bowRise / h.sternRise. A NEGATIVE
-- stern term LOWERS the sheer aft - that is what carves a sportfisher's cockpit.
local SHEER = {
	sweep = function(u)           -- classic curve, low ~62% aft, lifting to both ends
		return math.clamp((0.62 - u) / 0.62, 0, 1) ^ 1.85,
		       math.clamp((u - 0.62) / 0.38, 0, 1) ^ 1.75
	end,
	flat = function(u)            -- workboat: near-straight, all the lift at the stem
		return math.clamp((0.20 - u) / 0.20, 0, 1) ^ 1.35, 0
	end,
	rise = function(u)            -- one long continuous lift forward (deep-V runabout)
		return math.clamp((0.80 - u) / 0.80, 0, 1) ^ 2.1, 0
	end,
	drop = function(u)            -- high bow falling to a LOW deck aft
		return math.clamp((0.58 - u) / 0.58, 0, 1) ^ 1.3,
		       -math.clamp((u - 0.58) / 0.42, 0, 1) ^ 1.15
	end,
	ship = function(u)            -- long straight run with a slight lift at each end
		return math.clamp((0.34 - u) / 0.34, 0, 1) ^ 1.1,
		       math.clamp((u - 0.76) / 0.24, 0, 1) ^ 1.3
	end,
}

-- ROCKER: 0 at the stem, 1 at full draft. How fast the forefoot goes deep.
local ROCKER = {
	round = function(u) return math.clamp((u / 0.34) ^ 0.85, 0, 1) end,   -- displacement
	flat  = function(u) return math.clamp((u / 0.13) ^ 0.65, 0, 1) end,   -- flat bottom
	vee   = function(u) return math.clamp((u / 0.30) ^ 1.35, 0, 1) end,   -- fine entry
	deep  = function(u) return math.clamp((u / 0.44) ^ 0.70, 0, 1) end,   -- long deep forefoot
	ship  = function(u) return math.clamp((u / 0.09) ^ 0.55, 0, 1) end,   -- plumb, deep at once
}

local function beamAt(u, h)
	return (PLAN[h.plan or "fine"])(u, h.transom)
end

-- THE ROCKER. The forefoot lifts clear of the water over the forward third. What happens
-- aft is the difference between a rowboat and a powerboat, so it is spec-driven:
-- sternRocker 0 keeps the run deep all the way to a transom, 1 sweeps it up like the bow.
local function keelY(u, h)
	local bowLift = (ROCKER[h.rocker or "round"])(u)
	local sr = h.sternRocker or 0
	local aft = 1 - sr * math.clamp((u - 0.66) / 0.34, 0, 1) ^ 1.5
	return -h.draft * bowLift * aft
end

-- THE SHEER. One continuous sweep with its low point ~62% aft, lifting to both ends.
-- This curve is doing ALL the silhouette work: at a 30-degree yaw the plan taper only
-- shows 0.5x of itself on screen, so a hull whose sheer is nearly flat reads as a packing
-- crate no matter how nicely it tapers in Z. Measured on the first build: bowRise 1.05
-- spread over 34% of the length was a 16-pixel lift across a 250-pixel boat - invisible.
local function sheerY(u, h)
	local bow, stn = (SHEER[h.sheerStyle or "sweep"])(u)
	return h.sheer + h.bowRise * bow + h.sternRise * stn
end

local function xAt(u, h) return -h.fwd + u * (h.fwd + h.aft) end

----------------------------------------------------------------------
-- hull
----------------------------------------------------------------------
local function buildHull(model, h, deco, simple)
	local folder = Instance.new("Folder")
	folder.Name = "Hull"
	folder.Parent = model

	local L = h.fwd + h.aft
	-- Stations scale with length so the bow taper never reads as chunky steps. In `simple`
	-- mode (the menu's ViewportFrames) they are cut hard: a card preview is ~330x130 px, so
	-- none of this resolution survives anyway, and eight live viewports of the full model
	-- would be ~2000 parts rendering every frame behind the menu.
	local N = simple and math.clamp(math.floor(L / 4.2 + 0.5), 7, 10)
		or math.clamp(math.floor(L / 1.35 + 0.5), 14, 26)
	local seg = L / N
	local WALL = math.max(0.26, h.beam * 0.052)   -- bulwark thickness
	local stripeH = deco.stripe and 0.34 or 0

	for i = 0, N - 1 do
		local u0, u1 = i / N, (i + 1) / N
		local um = (u0 + u1) * 0.5
		local x = xAt(um, h)
		local w = math.max(0.22, h.beam * beamAt(um, h))
		local ky = keelY(um, h)
		local sy = sheerY(um, h)
		local dy = math.min(h.deck, sy - 0.30)
		-- a hair of overlap kills the seams between neighbouring stations
		local sx = seg * 1.04

		-- 1. bottom paint, below the waterline, plus a keel strip that FOLLOWS the rocker.
		-- (A single straight keel box spanning most of the length was the first build's worst
		-- artefact: at the ends the hull rockers up and the strip stayed put, drawing a flat
		-- black line hanging under the boat.)
		if ky < -0.02 and not simple then
			-- keel strip that FOLLOWS the rocker. (A single straight keel box spanning most
			-- of the length was the first build's worst artefact: at the ends the hull rockers
			-- up and the strip stayed put, drawing a flat black line hanging under the boat.)
			local k0, k1 = keelY(u0, h), keelY(u1, h)
			local ktilt = math.atan2(k1 - k0, seg)
			box(folder, "Keel", Vector3.new(seg / math.cos(ktilt) * 1.05, 0.20,
				math.max(0.30, math.min(w * 0.42, h.beam * 0.13))),
				at(x, (k0 + k1) * 0.5 + 0.02, 0) * CFrame.Angles(0, 0, ktilt),
				darken(h.hullBot, 0.28))
		end

		-- 2-3. THE BODY, keel up to the deck, in three width bands (the SECTION). Each band
		-- is split again at the waterline so the bottom paint stops exactly at y 0.
		local sec = SECTION[h.section or "round"]
		local function band(y0, y1, bw)
			if y1 <= y0 + 0.02 then return end
			if y0 < -0.01 and y1 > 0.01 then
				box(folder, "HullBot", Vector3.new(sx, -y0, bw), at(x, y0 * 0.5, 0), h.hullBot)
				box(folder, "HullTop", Vector3.new(sx, y1, bw), at(x, y1 * 0.5, 0), h.hullTop)
			else
				local mid = (y0 + y1) * 0.5
				box(folder, mid < 0 and "HullBot" or "HullTop",
					Vector3.new(sx, y1 - y0, bw), at(x, mid, 0),
					mid < 0 and h.hullBot or h.hullTop)
			end
		end
		if dy > ky + 0.05 then
			local span = dy - ky
			for b = 1, 3 do
				band(ky + span * (b - 1) / 3, ky + span * b / 3, math.max(0.2, w * sec[b]))
			end
			-- hard chine: the crease where a flat bottom turns up into the topsides. On a
			-- planing hull this line is most of what tells you what kind of boat it is.
			if h.chine and not simple and w > 0.7 then
				box(folder, "Chine", Vector3.new(sx, 0.17, math.max(0.3, w * sec[1] + 0.14)),
					at(x, ky + span / 3, 0), darken(h.hullBot, 0.22))
			end
		end
		-- boot stripe on the waterline
		if stripeH > 0 and dy > stripeH and ky < -0.02 then
			box(folder, "Stripe", Vector3.new(sx, stripeH, w * sec[2] + 0.06),
				at(x, stripeH * 0.5, 0), h.trim)
		end
		-- 4. The deck itself - a thin plate so the sole has its own colour. It hangs BELOW
		-- dy rather than sitting on top of it: with the plate centred at dy+0.08 the walkable
		-- surface was h.deck + 0.16, which on tiers 7 and 8 put the sole at 2.21 - ABOVE the
		-- seat pan at 2.175 - and squeezed the seat furniture down to Roblox's 0.001 minimum.
		-- The sole top must equal h.deck, which is what the <= 2.05 rule in BoatData assumes.
		if um > 0.12 and w > 1.1 then
			box(folder, "Deck", Vector3.new(sx, 0.16, math.max(0.3, w - WALL * 2)),
				at(x, dy - 0.08, 0), h.deckCol)
		end
		-- 5. bulwarks: side walls only, so the cockpit stays open for the angler
		if sy > dy + 0.12 and w > 0.6 then
			local wallH = sy - dy
			for _, s in ipairs({ 1, -1 }) do
				box(folder, "Bulwark", Vector3.new(sx, wallH, WALL),
					at(x, dy + wallH * 0.5, s * (w * 0.5 - WALL * 0.5)), h.hullTop)
			end
		end
		-- 6. gunwale cap, tilted to follow the sheer so the top edge reads as one curve
		if deco.rail ~= false and w > 0.5 then
			local sy0, sy1 = sheerY(u0, h), sheerY(u1, h)
			local tilt = math.atan2(sy1 - sy0, seg)
			box(folder, "Rail", Vector3.new(seg / math.cos(tilt) * 1.04, 0.19, w + 0.16),
				at(x, (sy0 + sy1) * 0.5, 0) * CFrame.Angles(0, 0, tilt), h.trim)
		end
		-- 7. planking seams. Thin proud strips at a few heights up the side, following the
		-- sheer. Cheaper than banding every station into N coloured boxes and it is what
		-- actually reads at this scale - a flat side is the other half of the crate look.
		local seams = simple and 0 or math.max(0, (h.planks or 4) - 1)
		if seams > 0 and w > 0.7 then
			local sy0, sy1 = sheerY(u0, h), sheerY(u1, h)
			local tilt = math.atan2(sy1 - sy0, seg)
			local lo = stripeH + 0.10
			for s = 1, seams do
				local fy = lo + (sy - lo) * (s / (seams + 1))
				if fy < sy - 0.30 then
					box(folder, "Seam", Vector3.new(seg / math.cos(tilt) * 1.04, 0.09, w + 0.07),
						at(x, fy, 0) * CFrame.Angles(0, 0, tilt), darken(h.hullTop, 0.17))
				end
			end
			-- rub rail: one heavier strip at deck level, in the trim colour
			box(folder, "RubRail", Vector3.new(seg / math.cos(tilt) * 1.04, 0.20, w + 0.15),
				at(x, dy + 0.06, 0) * CFrame.Angles(0, 0, tilt), h.trim)
		end
	end

	-- ------------------------------------------------------------------
	-- STERN. `canoe` closes to a point (double-ender) and gets no transom at all.
	-- ------------------------------------------------------------------
	local uT = 1 - 0.5 / N
	local wT = math.max(0.5, h.beam * beamAt(1, h))
	local kT, sT = keelY(uT, h), sheerY(1, h)
	local stern = h.stern or "transom"
	if stern ~= "canoe" then
		local rake = math.rad(h.transomRake or 11)
		local tx = h.aft - 0.12
		if kT < -0.02 then
			box(folder, "TransomBot", Vector3.new(0.34, -kT, wT),
				at(tx, kT * 0.5, 0) * CFrame.Angles(0, 0, rake), h.hullBot)
		end
		local tTop = math.max(0.1, sT - math.max(kT, 0))
		box(folder, "Transom", Vector3.new(0.34, tTop, wT),
			at(tx + math.sin(rake) * tTop * 0.5, math.max(kT, 0) + tTop * 0.5, 0)
				* CFrame.Angles(0, 0, rake), darken(h.hullTop, 0.08))
		box(folder, "TransomCap", Vector3.new(0.34, 0.2, wT + 0.14),
			at(tx + math.sin(rake) * tTop * 0.9, sT, 0), h.trim)
		if stern == "counter" then
			-- an overhanging counter above a tucked-up run: reads as a SHIP stern
			box(folder, "Counter", Vector3.new(1.5, 0.5, wT * 0.92),
				at(h.aft + 0.5, sT - 0.34, 0), h.hullTop)
			box(folder, "CounterCap", Vector3.new(1.7, 0.2, wT + 0.1),
				at(h.aft + 0.5, sT, 0), h.trim)
		end
	else
		box(folder, "SternPost", Vector3.new(0.34, sT - math.min(kT, 0) + 0.1, 0.3),
			at(h.aft - 0.1, (sT + math.min(kT, 0)) * 0.5, 0), h.trim)
	end

	-- ------------------------------------------------------------------
	-- STEM. The bow's leading edge is one of the few lines that survives at 250 px, so it
	-- is spec-driven too: a raked stem overhangs its own waterline, a plumb one is a
	-- vertical knife, and a bulb marks the hull out as a ship rather than a big boat.
	-- ------------------------------------------------------------------
	local sB, kB = sheerY(0, h), keelY(0.02, h)
	local hgt = sB - kB + 0.1
	local stem = h.stem or "raked"
	if stem == "plumb" or stem == "bulb" then
		box(folder, "Stem", Vector3.new(0.46, hgt, 0.42),
			at(-h.fwd + 0.14, (sB + kB) * 0.5, 0), h.trim)
		if stem == "bulb" then
			-- bulbous forefoot, sitting on the waterline and reaching ahead of the stem
			local bd = math.max(0.9, h.beam * 0.20)
			cyl(folder, "BulbBow", Vector3.new(1.9, bd, bd),
				at(-h.fwd - 0.35, -h.draft * 0.42, 0), h.hullBot)
			ball(folder, "BulbNose", bd, at(-h.fwd - 1.25, -h.draft * 0.42, 0), h.hullBot)
		end
	elseif stem == "canoe" then
		box(folder, "Stem", Vector3.new(0.32, hgt, 0.30),
			at(-h.fwd + 0.12, (sB + kB) * 0.5, 0), h.trim)
	else
		-- raked: lean the top forward (toward -X) about the stem foot
		local rk = math.rad(h.stemRake or 20)
		box(folder, "Stem", Vector3.new(0.42, hgt, 0.36),
			at(-h.fwd + 0.14 - math.sin(rk) * hgt * 0.5, (sB + kB) * 0.5, 0)
				* CFrame.Angles(0, 0, rk), h.trim)
	end

	-- Raised casting decks: a bass boat's fore and aft platforms. Emitted after the loop as
	-- a platform + riser rather than by lifting stations, so the hull curves stay intact.
	if h.deckStep then
		for _, ds in ipairs(h.deckStep) do
			local ua, ub, rise = ds[1], ds[2], ds[3]
			local xa, xb = xAt(ua, h), xAt(ub, h)
			local umid = (ua + ub) * 0.5
			local wm = math.max(0.5, h.beam * beamAt(umid, h))
			local dd = math.min(h.deck, sheerY(umid, h) - 0.30)
			box(folder, "CastDeck", Vector3.new(xb - xa, 0.22, math.max(0.4, wm - WALL * 2)),
				at((xa + xb) * 0.5, dd + rise, 0), lighten(h.deckCol, 0.14))
			-- riser on the inboard end, facing the cockpit
			local rx = (umid < 0.5) and xb or xa
			box(folder, "DeckRiser", Vector3.new(0.24, rise, math.max(0.4, wm - WALL * 2)),
				at(rx, dd + rise * 0.5, 0), darken(h.deckCol, 0.22))
		end
	end

	return { L = L, N = N, WALL = WALL }
end

----------------------------------------------------------------------
-- deco: everything that turns a hull into a particular boat
----------------------------------------------------------------------
local function deckYAt(u, h)
	return math.min(h.deck, sheerY(u, h) - 0.30)
end
local function uOf(x, h) return (x + h.fwd) / (h.fwd + h.aft) end
local function widthAtX(x, h)
	return math.max(0.22, h.beam * beamAt(math.clamp(uOf(x, h), 0, 1), h))
end
local function sheerAtX(x, h) return sheerY(math.clamp(uOf(x, h), 0, 1), h) end

-- How tall a deck item has to be to CLEAR THE RAIL at that station. The bulwarks run
-- 1.5-3 studs above the deck, so anything sized off the deck alone is swallowed whole and
-- the boat reads as an empty tub. Everything the player is supposed to see - crates,
-- coolers, live wells, pots - is sized through here instead.
local function pokeH(x, h, extra)
	local u = math.clamp(uOf(x, h), 0, 1)
	return math.max(0.8, (sheerY(u, h) - deckYAt(u, h)) + (extra or 0.55))
end

-- The seat pedestal. Every boat needs deck-to-2.175 furniture under the fixed seat or
-- the angler floats. `kind` only changes what it looks like.
local function addSeat(f, h, kind)
	local SEAT_Y = BoatData.SEAT_Y
	local dy = deckYAt(uOf(0, h), h)          -- the sole top; the deck plate hangs below it
	local c = h.accent
	-- If a tier ever sets `deck` high enough that there is no room for furniture, say so
	-- loudly rather than shipping an angler perched on a 0.001-stud sliver.
	if SEAT_Y - dy < 0.25 then
		warn(string.format("[BoatBuilder] deck %.2f leaves only %.2f studs under the seat at %.2f",
			dy, SEAT_Y - dy, SEAT_Y))
	end

	if kind == "thwart" then
		local w = widthAtX(0, h)
		box(f, "Thwart", Vector3.new(1.5, 0.22, w - 0.5), at(0, SEAT_Y, 0), h.deckCol)
		box(f, "ThwartKnee", Vector3.new(0.3, SEAT_Y - dy, 0.5), at(0, (SEAT_Y + dy) * 0.5, 0), c)
	elseif kind == "pedestal" then
		post(f, "SeatPost", 0.42, SEAT_Y - dy, 0, (SEAT_Y + dy) * 0.5, 0, c)
		local p = cyl(f, "SeatPad", Vector3.new(0.26, 1.7, 1.7),
			at(0, SEAT_Y - 0.06, 0) * CFrame.Angles(0, 0, math.rad(90)), h.trim)
		p.Name = "SeatPad"
	elseif kind == "chair" or kind == "fightingchair" then
		post(f, "SeatPost", 0.5, SEAT_Y - dy - 0.2, 0, (SEAT_Y + dy) * 0.5 - 0.1, 0, c)
		box(f, "SeatPad", Vector3.new(1.5, 0.3, 1.6), at(0, SEAT_Y - 0.1, 0), h.trim)
		box(f, "SeatBack", Vector3.new(0.32, 1.5, 1.5), at(0.72, SEAT_Y + 0.7, 0), h.trim)
		if kind == "fightingchair" then
			box(f, "SeatArm", Vector3.new(1.3, 0.18, 0.18), at(-0.1, SEAT_Y + 0.55, 0.78), c)
			box(f, "SeatArm", Vector3.new(1.3, 0.18, 0.18), at(-0.1, SEAT_Y + 0.55, -0.78), c)
			box(f, "FootRest", Vector3.new(0.9, 0.18, 1.3), at(-1.5, dy + 0.62, 0), c)
			post(f, "GimbalCup", 0.34, 0.5, -0.55, SEAT_Y + 0.05, 0, h.trim)
		end
	else -- "stool"
		box(f, "SeatBox", Vector3.new(1.5, SEAT_Y - dy, 1.5), at(0, (SEAT_Y + dy) * 0.5, 0), c)
		box(f, "SeatPad", Vector3.new(1.6, 0.22, 1.6), at(0, SEAT_Y - 0.05, 0), h.trim)
	end
end

-- A cabin block with a raked front, a dark roof, a trim band and a row of windows.
-- x0/x1 are the fore and aft faces; callers must keep those out of the rod corridor.
-- The roof and band are deliberately DARK: a white superstructure on a pale sky is the
-- one thing that vanished completely in the first contact sheet, and every boat from
-- tier 4 up has a white house.
local function addCabin(f, h, x0, x1, baseY, height, width, col, windows, dark)
	local cx, cl = (x0 + x1) * 0.5, x1 - x0
	dark = dark or darken(col, 0.55)
	box(f, "CabinWall", Vector3.new(cl, height, width), at(cx, baseY + height * 0.5, 0), col)
	wedge(f, "CabinRake", Vector3.new(width, height * 0.40, 0.95),
		at(x0 - 0.48, baseY + height - height * 0.20, 0)
			* CFrame.Angles(0, math.rad(-90), 0), col)
	-- window band: one dark strip the glass panes sit inside, so the house reads at range
	box(f, "WindowBand", Vector3.new(cl - 0.3, height * 0.40, width + 0.14),
		at(cx, baseY + height * 0.68, 0), dark)
	box(f, "CabinRoof", Vector3.new(cl + 0.8, 0.28, width + 0.7),
		at(cx - 0.15, baseY + height + 0.14, 0), dark)
	box(f, "CabinLip", Vector3.new(cl + 0.95, 0.14, width + 0.85),
		at(cx - 0.15, baseY + height + 0.02, 0), h.trim)
	if windows and windows > 0 then
		local gw = math.max(0.5, math.min(1.4, (cl - 1.0) / windows - 0.26))
		for i = 1, windows do
			local wx = x0 + 0.55 + (i - 0.5) * (cl - 1.1) / windows
			for _, s in ipairs({ 1, -1 }) do
				box(f, "Window", Vector3.new(gw, height * 0.26, 0.14),
					at(wx, baseY + height * 0.68, s * (width * 0.5 + 0.08)),
					Color3.fromRGB(126, 196, 226))
			end
		end
	end
	return baseY + height + 0.28   -- roof level, for masts and funnels
end

local function addMast(f, h, x, baseY, height, col, radar, floods)
	post(f, "Mast", 0.30, height, x, baseY + height * 0.5, 0, col)
	box(f, "Crosstree", Vector3.new(0.22, 0.22, height * 0.42),
		at(x, baseY + height * 0.74, 0), col)
	if radar then
		box(f, "RadarBar", Vector3.new(0.5, 0.22, 2.6), at(x, baseY + height + 0.2, 0),
			Color3.fromRGB(236, 240, 244))
		post(f, "RadarHub", 0.42, 0.36, x, baseY + height + 0.02, 0, Color3.fromRGB(90, 96, 104))
	end
	if floods then
		for _, s in ipairs({ 1, -1 }) do
			local l = box(f, "Flood", Vector3.new(0.34, 0.34, 0.34),
				at(x - 0.25, baseY + height * 0.70, s * height * 0.20),
				Color3.fromRGB(255, 244, 196), Enum.Material.Neon)
			l.Name = "Flood"
		end
	end
end

local function addOutboard(f, h, kind)
	local x = h.aft + 0.35
	local dy = deckYAt(1, h)
	local offs = (kind == "twin") and { 0.95, -0.95 } or { 0 }
	for _, z in ipairs(offs) do
		box(f, "MotorCowl", Vector3.new(1.25, 1.45, 1.0), at(x, dy + 0.55, z), h.accent)
		box(f, "MotorLeg", Vector3.new(0.42, 1.9, 0.5), at(x + 0.1, dy - 0.75, z), darken(h.accent, 0.2))
		box(f, "MotorFoot", Vector3.new(1.2, 0.34, 0.42), at(x + 0.25, dy - 1.65, z), darken(h.accent, 0.2))
		box(f, "MotorCap", Vector3.new(1.3, 0.16, 1.05), at(x, dy + 1.3, z), h.trim)
	end
end

-- Deck rails: thin stanchions + a top wire. Fore of the corridor only.
local function addBowRail(f, h, col)
	local xs = { -h.fwd * 0.93, -h.fwd * 0.80, -h.fwd * 0.66, -h.fwd * 0.52 }
	for _, x in ipairs(xs) do
		local w = widthAtX(x, h)
		local sy = sheerY(math.clamp(uOf(x, h), 0, 1), h)
		for _, s in ipairs({ 1, -1 }) do
			post(f, "Stanchion", 0.13, 0.85, x, sy + 0.42, s * (w * 0.5 - 0.1), col)
		end
	end
	local xa, xb = xs[1], xs[#xs]
	for _, s in ipairs({ 1, -1 }) do
		local wa, wb = widthAtX(xa, h), widthAtX(xb, h)
		local ya = sheerY(math.clamp(uOf(xa, h), 0, 1), h) + 0.82
		local yb = sheerY(math.clamp(uOf(xb, h), 0, 1), h) + 0.82
		local p0 = Vector3.new(xa, ya, s * (wa * 0.5 - 0.1))
		local p1 = Vector3.new(xb, yb, s * (wb * 0.5 - 0.1))
		local mid = (p0 + p1) * 0.5
		box(f, "RailWire", Vector3.new((p1 - p0).Magnitude, 0.1, 0.1),
			CFrame.lookAt(mid, p1) * CFrame.Angles(0, math.rad(90), 0), col)
	end
end

local function addRodHolders(f, h, n, col)
	for i = 1, n do
		local x = 1.2 + (i - 1) * 0.85
		if x > h.aft - 0.4 then x = h.aft - 0.4 - (i - 1) * 0.3 end
		local w = widthAtX(x, h)
		local sy = sheerY(math.clamp(uOf(x, h), 0, 1), h)
		for _, s in ipairs({ 1, -1 }) do
			cyl(f, "RodTube", Vector3.new(0.85, 0.26, 0.26),
				at(x, sy + 0.30, s * (w * 0.5 - 0.22)) * CFrame.Angles(0, 0, math.rad(64)), col)
		end
	end
end

local function addPots(f, h, n, col, trim, startX, step)
	-- crab pots stacked forward of the corridor, two high per row
	local x = startX or -7.4
	step = step or 2.0
	local placed = 0
	local rows = 0
	while placed < n and rows < 6 do
		local w = widthAtX(x, h)
		local dy = deckYAt(math.clamp(uOf(x, h), 0, 1), h) + 0.2
		-- Two-high stacks, sized so the UPPER pot clears the bulwark. The first build used
		-- 1.75-stud pots sitting on the deck and the whole stack disappeared behind the rail.
		local high = (placed + 2 <= n) and 2 or 1
		local s = 2.3
		local topY = dy
		for lvl = 0, high - 1 do
			if placed >= n then break end
			local zw = math.max(0.8, math.min(s, w - 0.7))
			box(f, "CrabPot", Vector3.new(s, s * 0.72, zw),
				at(x, dy + s * 0.36 + lvl * s * 0.78, 0), col)
			-- light frame bands on a dark cage: the pots were a dark grey mass against a dark
			-- hull and simply did not read at range
			-- Inset in X, proud in Z: stacks are stowed flush against each other, so a band
			-- wider than its own pot pokes into the neighbouring stack.
			box(f, "PotBand", Vector3.new(s - 0.06, 0.16, zw + 0.10),
				at(x, dy + s * 0.72 + lvl * s * 0.78, 0), trim)
			box(f, "PotBand", Vector3.new(s - 0.06, 0.14, zw + 0.10),
				at(x, dy + s * 0.06 + lvl * s * 0.78, 0), trim)
			topY = dy + s * 0.72 + lvl * s * 0.78
			placed += 1
		end
		-- a marker buoy on top of every other stack
		if rows % 2 == 0 then
			ball(f, "PotBuoy", 0.95, at(x, topY + 0.55, 0.2), Color3.fromRGB(240, 122, 40))
			post(f, "BuoyStick", 0.12, 1.1, x, topY + 1.2, 0.2, Color3.fromRGB(30, 34, 40))
		end
		x -= step
		rows += 1
	end
end

local function addGantry(f, h, col, atX)
	-- A-frame over the stern, AFT of the corridor
	local x = atX or (h.aft - 0.9)
	local w = widthAtX(x, h)
	local sy = sheerY(math.clamp(uOf(x, h), 0, 1), h)
	local top = sy + 4.2
	for _, s in ipairs({ 1, -1 }) do
		local p0 = Vector3.new(x, sy, s * (w * 0.5 - 0.2))
		local p1 = Vector3.new(x - 0.8, top, s * (w * 0.5 - 1.0))
		local mid = (p0 + p1) * 0.5
		box(f, "GantryLeg", Vector3.new(0.34, (p1 - p0).Magnitude, 0.34),
			CFrame.lookAt(mid, p1) * CFrame.Angles(math.rad(90), 0, 0), col)
	end
	box(f, "GantryBeam", Vector3.new(0.36, 0.36, w - 1.6), at(x - 0.8, top, 0), col)
	box(f, "GantryBlock", Vector3.new(0.5, 0.6, 0.5), at(x - 0.8, top - 0.55, 0), darken(col, 0.25))
end

local function addCrane(f, h, col, trim, atX, reach)
	-- picking crane. `reach` is signed: negative booms forward, positive booms aft over
	-- the stern. It must never sweep the rod corridor, so a crane mounted aft of the
	-- angler booms further aft rather than back across them.
	local x = atX or -7.0
	reach = reach or -5.4
	local dy = deckYAt(math.clamp(uOf(x, h), 0, 1), h)
	post(f, "CranePost", 0.62, 3.6, x, dy + 1.8, 0, col)
	post(f, "CraneHub", 0.95, 0.7, x, dy + 3.7, 0, trim)
	local p0 = Vector3.new(x, dy + 3.7, 0)
	local p1 = Vector3.new(x + reach, dy + 6.3, 0)
	local mid = (p0 + p1) * 0.5
	box(f, "CraneBoom", Vector3.new(0.42, (p1 - p0).Magnitude, 0.42),
		CFrame.lookAt(mid, p1) * CFrame.Angles(math.rad(90), 0, 0), trim)
	box(f, "CraneHook", Vector3.new(0.26, 1.0, 0.26), at(p1.X + 0.2, p1.Y - 0.9, 0), col)
end

local function addNets(f, h, col, trim, atX)
	local x = atX or (h.aft - 2.4)
	local w = widthAtX(x, h)
	local dy = deckYAt(math.clamp(uOf(x, h), 0, 1), h)
	-- ATHWARTSHIPS. A Roblox cylinder's axis is its own X, so CFrame.Angles(rad(90),0,0)
	-- spins it about that axis and changes NOTHING - the drum was built fore-and-aft, a
	-- 5.6-stud barrel lying down the centreline straight through the seated angler's lap.
	-- Rotating about Y is what actually lays it across the boat. Compare post() above.
	cyl(f, "NetDrum", Vector3.new(math.max(1.6, w - 1.8), 1.9, 1.9),
		at(x, dy + 1.15, 0) * CFrame.Angles(0, math.rad(90), 0), trim)
	cyl(f, "NetBundle", Vector3.new(math.max(1.3, w - 2.4), 2.5, 2.5),
		at(x, dy + 1.15, 0) * CFrame.Angles(0, math.rad(90), 0), col, Enum.Material.Fabric)
end

local function addOutriggers(f, h, col, atX)
	local x = atX or -3.2
	local w = widthAtX(x, h)
	local sy = sheerY(math.clamp(uOf(x, h), 0, 1), h)
	for _, s in ipairs({ 1, -1 }) do
		local p0 = Vector3.new(x, sy + 2.6, s * (w * 0.5 - 0.3))
		local p1 = Vector3.new(x - 3.0, sy + 9.4, s * (w * 0.5 + 6.4))
		local mid = (p0 + p1) * 0.5
		box(f, "Outrigger", Vector3.new(0.24, (p1 - p0).Magnitude, 0.24),
			CFrame.lookAt(mid, p1) * CFrame.Angles(math.rad(90), 0, 0), col)
	end
end

local function addFunnel(f, h, x, baseY, col, trim)
	box(f, "Funnel", Vector3.new(1.15, 1.9, 1.35), at(x, baseY + 0.95, 0), col)
	box(f, "FunnelBand", Vector3.new(1.25, 0.34, 1.45), at(x, baseY + 1.62, 0), trim)
end

local function addTyres(f, h, n, col)
	for i = 1, n do
		local x = h.aft - 1.2 - (i - 1) * 2.1
		local w = widthAtX(x, h)
		local sy = sheerY(math.clamp(uOf(x, h), 0, 1), h)
		cyl(f, "Fender", Vector3.new(0.34, 1.25, 1.25),
			at(x, sy - 0.75, w * 0.5 + 0.16), col)
	end
end

local function addContainers(f, h, n, cols, startX, step)
	for i = 1, n do
		local x = (startX or -11.5) - (i - 1) * (step or 2.6)
		local w = widthAtX(x, h)
		if w < 2.2 then break end
		local dy = deckYAt(math.clamp(uOf(x, h), 0, 1), h) + 0.2
		-- sized through pokeH so the stack shows above the bulwark rather than vanishing
		local hh = pokeH(x, h, 0.9)
		box(f, "Container", Vector3.new(2.4, hh, math.min(2.8, w - 0.9)),
			at(x, dy + hh * 0.5, 0), cols[(i - 1) % #cols + 1])
		box(f, "ContainerRib", Vector3.new(2.5, 0.14, math.min(2.9, w - 0.85)),
			at(x, dy + hh - 0.2, 0), darken(cols[(i - 1) % #cols + 1], 0.3))
	end
end

----------------------------------------------------------------------
-- per-tier composition
----------------------------------------------------------------------
-- The rod corridor. Nothing centred may sit inside this X range above the rail.
local CORRIDOR_FWD, CORRIDOR_AFT = -6.5, 2.5

-- deco values may be `true`, a count, or a table of placement params
local function cfg(v)
	if type(v) == "table" then return v end
	if type(v) == "number" then return { n = v } end
	return {}
end

local function buildDeco(model, h, deco, simple)
	local f = Instance.new("Folder")
	f.Name = "Deco"
	f.Parent = model

	addSeat(f, h, deco.seat)

	-- Fine trim is dropped from menu previews: individually these are 4-30 parts each and
	-- none of them is a pixel wide on a card.
	if simple then
		deco = table.clone(deco)
		deco.ribs, deco.rodholders, deco.tyres, deco.bowrail = nil, nil, nil, nil
	end

	if deco.ribs then
		for i = 1, deco.ribs do
			local x = -1.6 - i * (h.fwd - 2.2) / (deco.ribs + 1)
			local w = widthAtX(x, h)
			local dy = deckYAt(math.clamp(uOf(x, h), 0, 1), h)
			local sy = sheerY(math.clamp(uOf(x, h), 0, 1), h)
			box(f, "Rib", Vector3.new(0.3, sy - dy, w - 0.3), at(x, (sy + dy) * 0.5, 0), h.accent)
		end
	end

	if deco.oars then
		-- shipped along the rail, so they read against the sky rather than vanishing inboard
		for _, s in ipairs({ 1, -1 }) do
			local w = widthAtX(-5.2, h)
			local y = sheerAtX(-5.2, h) + 0.12
			box(f, "Oar", Vector3.new(7.0, 0.22, 0.22), at(-5.2, y, s * (w * 0.5 - 0.45)),
				lighten(h.deckCol, 0.12))
			box(f, "OarBlade", Vector3.new(1.6, 0.14, 0.66),
				at(-8.6, y, s * (w * 0.5 - 0.45)), lighten(h.deckCol, 0.12))
		end
	end

	-- Deck furniture. All of it is placed EXPLICITLY by the tier, because the generic
	-- "put it amidships" defaults the first build used dropped a 2.5-stud crate right where
	-- the rod sweeps, and stacked the crabber's pot rows straight through its own
	-- wheelhouse. Nothing centred may sit inside x CORRIDOR_FWD..CORRIDOR_AFT above the rail.
	local function deckBox(name, x, len, wid, col, lid, zoff)
		local hh = pokeH(x, h, 0.55)
		box(f, name, Vector3.new(len, hh, wid), at(x, h.deck + hh * 0.5, zoff or 0), col)
		box(f, name .. "Lid", Vector3.new(len + 0.16, 0.18, wid + 0.16),
			at(x, h.deck + hh + 0.09, zoff or 0), lid)
	end

	if deco.crate then
		deckBox("Crate", cfg(deco.crate).x or -8.2, 1.7, 1.5, h.accent, h.trim, 0.3)
	end
	if deco.livewell then
		deckBox("Livewell", cfg(deco.livewell).x or -8.5, 2.1, 1.8,
			lighten(h.deckCol, 0.25), h.trim)
	end
	if deco.cooler then
		deckBox("Cooler", cfg(deco.cooler).x or (h.aft - 1.1), 2.0, 1.7,
			Color3.fromRGB(238, 242, 246), h.trim)
	end
	if deco.lamp then
		local x = cfg(deco.lamp).x or -8.8
		local top = sheerAtX(x, h) + 0.9
		post(f, "LampPost", 0.16, top - h.deck, x, (top + h.deck) * 0.5, -0.9, h.accent)
		ball(f, "LampGlass", 0.6, at(x, top + 0.2, -0.9),
			Color3.fromRGB(255, 236, 176), Enum.Material.Neon)
	end

	-- consoles / cabins ------------------------------------------------
	local roofY = nil
	local cs = cfg(deco.console)
	if cs.kind == "small" then
		local x = cs.x or -8.5
		box(f, "Console", Vector3.new(1.8, 1.7, 2.2), at(x, h.deck + 0.95, 0), h.cabin)
		box(f, "Screen", Vector3.new(0.16, 0.85, 1.6), at(x - 0.98, h.deck + 1.45, 0),
			Color3.fromRGB(126, 196, 226))
		box(f, "Windscreen", Vector3.new(0.14, 1.1, 2.1), at(x - 0.9, h.deck + 2.35, 0),
			Color3.fromRGB(176, 220, 238), SM, 0.35)
		box(f, "ConsoleCap", Vector3.new(2.0, 0.16, 2.35), at(x, h.deck + 1.85, 0), h.accent)
	elseif cs.kind == "ttop" then
		local x = cs.x or -9.4
		box(f, "Console", Vector3.new(2.6, 2.1, 2.7), at(x, h.deck + 1.15, 0), h.cabin)
		box(f, "Screen", Vector3.new(0.16, 1.0, 1.9), at(x - 1.38, h.deck + 1.75, 0),
			Color3.fromRGB(126, 196, 226))
		box(f, "ConsoleCap", Vector3.new(2.8, 0.18, 2.9), at(x, h.deck + 2.28, 0), h.accent)
		for _, dx in ipairs({ -1.15, 1.15 }) do
			for _, dz in ipairs({ -1.15, 1.15 }) do
				post(f, "TopLeg", 0.2, 3.0, x + dx, h.deck + 3.85, dz, h.trim)
			end
		end
		box(f, "TTop", Vector3.new(4.0, 0.26, 3.8), at(x, h.deck + 5.45, 0), h.accent)
		box(f, "TTopLip", Vector3.new(4.25, 0.14, 4.05), at(x, h.deck + 5.28, 0), h.trim)
	end

	-- A deckhouse may not be wider than the hull it stands on. Sizing purely off h.beam
	-- put a 7.75-wide house on tier 8's 3.88-wide forward stations, so at the 30-degree
	-- yaw its near corner hung ~2 studs outboard of the topsides over open water.
	local function houseW(x0, x1, frac)
		local want = math.max(2.6, h.beam * frac)
		local fore = widthAtX(x0, h)
		local mid  = widthAtX((x0 + x1) * 0.5, h)
		return math.max(2.0, math.min(want, math.min(fore, mid) + 0.7))
	end

	local wh = cfg(deco.wheelhouse)
	if wh.x0 then
		roofY = addCabin(f, h, wh.x0, wh.x1, h.deck, wh.h or 3.8,
			houseW(wh.x0, wh.x1, wh.beam or 0.68), h.cabin, wh.windows or 4, h.accent)
	end
	local cb = cfg(deco.cabin)
	if cb.x0 then
		roofY = addCabin(f, h, cb.x0, cb.x1, h.deck, cb.h or 2.9,
			houseW(cb.x0, cb.x1, cb.beam or 0.72), h.cabin, cb.windows or 4, h.accent)
	end

	local fb = cfg(deco.flybridge)
	if fb.x and roofY then
		local bw = math.max(2.2, h.beam * 0.52)
		box(f, "Flybridge", Vector3.new(4.8, 1.7, bw), at(fb.x, roofY + 0.85, 0), h.cabin)
		box(f, "FlyScreen", Vector3.new(0.16, 1.2, bw * 0.92),
			at(fb.x - 2.45, roofY + 1.5, 0), Color3.fromRGB(176, 220, 238), SM, 0.3)
		box(f, "FlyRail", Vector3.new(5.0, 0.18, bw + 0.35), at(fb.x, roofY + 1.78, 0), h.trim)
		box(f, "FlySeat", Vector3.new(1.1, 0.9, 1.4), at(fb.x + 1.1, roofY + 2.2, 0), h.accent)
		roofY = roofY + 1.9
	end

	local fn = cfg(deco.funnel)
	if fn.x then addFunnel(f, h, fn.x, roofY or (h.deck + 3.6), h.accent, h.trim) end

	local ms = cfg(deco.mast)
	if ms.x then
		-- base "roof" steps the mast up onto whatever house was just built; a number is a
		-- literal local Y for a deck-stepped mast standing clear of the house.
		local base = (ms.base == "roof") and (roofY or (h.deck + 3.4))
			or (tonumber(ms.base) or (h.deck + 0.2))
		addMast(f, h, ms.x, base, ms.h or 5.2, h.trim, ms.radar, ms.floods)
	end

	local gy = cfg(deco.gantry)
	if gy.x then addGantry(f, h, h.accent, gy.x) end
	local cr = cfg(deco.crane)
	if cr.x then addCrane(f, h, h.accent, h.trim, cr.x, cr.reach) end
	local nt = cfg(deco.nets)
	if nt.x then addNets(f, h, darken(h.trim, 0.35), h.accent, nt.x) end
	local og = cfg(deco.outriggers)
	if og.x then addOutriggers(f, h, h.trim, og.x) end
	local pt = cfg(deco.pots)
	if pt.n then addPots(f, h, pt.n, Color3.fromRGB(48, 56, 62), h.trim, pt.x, pt.step) end
	local ct = cfg(deco.containers)
	if ct.n then
		addContainers(f, h, ct.n,
			{ Color3.fromRGB(196, 76, 60), Color3.fromRGB(56, 118, 152), Color3.fromRGB(206, 166, 70) },
			ct.x, ct.step)
	end
	if deco.outboard then addOutboard(f, h, deco.outboard) end
	if deco.bowrail then addBowRail(f, h, h.trim) end
	if deco.rodholders then addRodHolders(f, h, deco.rodholders, h.accent) end
	if deco.tyres then addTyres(f, h, deco.tyres, Color3.fromRGB(38, 40, 44)) end
end

----------------------------------------------------------------------
-- public
----------------------------------------------------------------------
function B.worldCFrame()
	return CFrame.new(BoatData.ORIGIN) * CFrame.Angles(0, math.rad(BoatData.YAW), 0)
end

-- Build tier `t` (a BoatData entry). Returns a Model already placed in the world frame.
-- `simple` builds a reduced-part version for the menu's ViewportFrames.
function B.build(t, simple)
	assert(t and t.hull, "BoatBuilder.build needs a tier with a hull spec")
	local h = t.hull
	local deco = h.deco or {}

	local model = Instance.new("Model")
	model.Name = "Boat_" .. t.id

	local root = box(model, "Root", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), h.hullTop)
	root.Transparency = 1
	model.PrimaryPart = root

	buildHull(model, h, deco, simple)
	buildDeco(model, h, deco, simple)

	model:SetAttribute("BoatTier", t.id)
	model:PivotTo(B.worldCFrame())
	return model
end

-- World-space AABB of a built model, for the framing check.
function B.measure(model)
	local mn = Vector3.new(1e9, 1e9, 1e9)
	local mx = Vector3.new(-1e9, -1e9, -1e9)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Root" then
			local cf, s = d.CFrame, d.Size
			for i = -1, 1, 2 do for j = -1, 1, 2 do for k = -1, 1, 2 do
				local p = cf * Vector3.new(s.X * 0.5 * i, s.Y * 0.5 * j, s.Z * 0.5 * k)
				mn = Vector3.new(math.min(mn.X, p.X), math.min(mn.Y, p.Y), math.min(mn.Z, p.Z))
				mx = Vector3.new(math.max(mx.X, p.X), math.max(mx.Y, p.Y), math.max(mx.Z, p.Z))
			end end end
		end
	end
	return mn, mx
end

return B
