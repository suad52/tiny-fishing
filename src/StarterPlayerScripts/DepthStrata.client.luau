--[[
	DepthStrata - the water column is FIVE DIFFERENT PLACES, not one blue gradient.

	Before this, everything below the waterline was a single 270-stud plane wearing
	one surface->abyss UIGradient. Two problems:
	  1. the depth ladder now runs to -620 (GameClient's BANDS) but the painted sea
	     stopped at -270, so a deep cast fell off the bottom of the art entirely
	  2. sinking felt like nothing was happening - the depth number went up and the
	     picture did not change

	The column is now cut into 5 strata whose boundaries LINE UP with GameClient's
	rarity bands, so the scenery telegraphs what you are fishing for:

	     0 .. -70    shallows   sunlit open water, a passing school   (Common)
	   -70 .. -190   kelp       a forest you sink through             (Uncommon/Rare)
	  -190 .. -330   cavern     rock walls close in overhead          (Rare/Epic)
	  -330 .. -470   glow       bioluminescent field in the dark      (Epic/Legendary)
	  -470 .. -660   trench     near-black, hydrothermal vents        (Mythic)

	Each of the 6 zones RESKINS all five (see LINEUP): a kelp forest is swaying
	green weed in Lighthouse Cove, an icicle colonnade in Frostbite Fjord and a
	field of charred stumps in Molten Abyss. Only the ACTIVE zone's art is built
	(5 planes, rebuilt on travel) - instantiating all 30 would leave 30 canvases
	resident for no reason.

	Division of labour with SeaFX: SeaFX owns the WATERLINE (wave ribbon, foam,
	god rays, surface motes). This script owns the WATER COLOUR - the WaterBack
	gradient is assembled here from the strata, so SeaFX's applySea no longer
	writes grad.Color - plus everything structural below the surface.

	GOTCHAS baked in here, all of them previously paid for elsewhere in this game:
	- These SurfaceGuis sit on the BACK face seen from the front, so canvas X is
	  MIRRORED on screen. Every piece of art below is built symmetric about the
	  canvas centre so it cannot matter. Do not add an asymmetric feature without
	  checking which side it actually lands on.
	- SurfaceGui.SizingMode defaults to FixedSize (800x600) - it MUST be set to
	  PixelsPerStud or the canvas silently ignores the panel's real dimensions.
	- UDim.Offset is an INTEGER. Anything moving less than 1px/frame needs a float
	  accumulator (the fx/fy fields below) or it rounds away and nothing moves.
	- Roblox does not clip ROTATED gui elements, so ClipsDescendants will not save
	  a tilted shaft that pokes out of its plane.
--]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local plr   = Players.LocalPlayer
local zone  = workspace:WaitForChild("Zone1")
local water = zone:WaitForChild("WaterBack")

-- one table, not 6 locals: GameClient blew Luau's 200-local ceiling doing this the
-- other way and the failure only shows up at runtime on the client.
local C = {
	BOT  = -660,   -- column floor; GameClient's deepest band ends at -620
	-- ⚠️ W must be the VISIBLE width, not a comfortable margin. At 140 the walls and
	-- spikes sat in the ~24 studs either side that is never on screen and the cavern
	-- rendered as empty water. GameClient holds TARGET_VIEW_W = 92 studs across by
	-- deriving camera distance from aspect, and NARROWS past the MAX_CAM_DIST clamp -
	-- so 92 is the widest the player ever sees and 96 is the right panel width.
	W    = 96,
	PPS  = 16,     -- viewport is ~17.5 screen px/stud here; below that the art blurs
	-- ⚠️ NOT -2.8. WaterBack is an OPAQUE 1-stud slab centred at Z=-3, so it spans
	-- -3.5..-2.5 and its gradient face is at -2.5. A panel at -2.8 sits INSIDE that
	-- volume and is completely hidden behind the water plane - the art built fine,
	-- animated fine, and was invisible. The gui face must clear -2.5 toward the
	-- camera while staying behind SeaFX's wave ribbon (body spans -2.4..-1.8).
	Z    = -2.3,
	THK  = 0.2,    -- thin, so the Back (+Z) gui face lands at -2.2
	NEAR = 210,    -- studs either side of the camera a stratum keeps rendering
}

local STRATA = {
	{ key = "shallows", y0 = 0,    y1 = -70  },
	{ key = "kelp",     y0 = -70,  y1 = -190 },
	{ key = "cavern",   y0 = -190, y1 = -330 },
	{ key = "glow",     y0 = -330, y1 = -470 },
	{ key = "trench",   y0 = -470, y1 = -660 },
}

local function h(n)
	return Color3.fromRGB(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
end

local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

-- name, water top, water bottom, rock, accent (the stratum's "life" colour), glow, style
-- name, which BUILDER to use, water top/bottom, rock, accent (the band's "life"
-- colour) and an optional glow.
local function z(name, kind, top, bot, rock, accent, glow)
	return { name = name, kind = kind, top = h(top), bot = h(bot), rock = h(rock),
		accent = h(accent), glow = glow and h(glow) or nil }
end

-- ⚠️ EACH ZONE RUNS A DIFFERENT SEQUENCE OF PLACES, not the same five recoloured.
-- The first version reskinned one lineup (shallows/kelp/cavern/glow/trench) six times,
-- so every zone read as identical scenery in a different palette - which is exactly what
-- it looked like in game. `kind` picks the BUILDER, so the silhouettes themselves differ.
-- The water ramps are kept from the tuned version; only the structures changed.
--
-- The KELP FOREST and the SEA CAVE now belong to Zone 1 alone and are the two most
-- detailed builders in here; no other zone reuses them.
local LINEUP = {
	[1] = { -- Lighthouse Cove: the classic temperate ocean. Kelp forest, then a sea cave.
		z("Sunlit Shallows",  "shallows", 0x84EEF7, 0x28A2DE, 0x34505C, 0xCEFAFF),
		z("Kelp Forest",      "kelp",     0x28A2DE, 0x126096, 0x2A4450, 0x2E9660),
		z("Sunken Cavern",    "cavern",   0x126096, 0x0A2C56, 0x263444, 0x3A4C60, 0x60BEDC),
		z("Glowfield",        "glow",     0x0A2C56, 0x051430, 0x16223A, 0x3C5A82, 0x78DCFF),
		z("Abyssal Trench",   "trench",   0x051430, 0x07142E, 0x1E2840, 0x2E3C58, 0x96E2FF),
	},
	[2] = { -- Tropical Reef: a coral garden, then a wreck, then the drop-off
		z("Coral Shallows",   "shallows", 0x96F0E6, 0x40CEC4, 0xD8BE96, 0xD6FFFA),
		z("Coral Garden",     "coral",    0x40CEC4, 0x1A9696, 0xD8BE96, 0xFF8C78, 0xFFD24A),
		z("The Wreck",        "wreck",    0x1A9696, 0x0A5C66, 0x4A3A2E, 0x6E5A46, 0x78FFEB),
		z("The Blue Hole",    "bluehole", 0x0A5C66, 0x043A44, 0x14464E, 0x286E78, 0xFF78C8),
		z("Turquoise Abyss",  "trench",   0x043A44, 0x03202A, 0x11414C, 0x1E5460, 0x5AFFDC),
	},
	[3] = { -- Golden Sunset Bay: soft meadow, eroded arches, a jellyfish bloom
		z("Amber Shallows",   "shallows", 0xFFC884, 0xEC925C, 0x784C3A, 0xFFE4B0),
		z("Seagrass Meadow",  "seagrass", 0xEC925C, 0xB0604A, 0x6E4636, 0xC69642),
		z("Sandstone Arches", "arches",   0xB0604A, 0x6E343C, 0x92583C, 0xB27450, 0xFFBE6E),
		z("Jellyfish Bloom",  "glow",     0x6E343C, 0x3E1A2E, 0x46242C, 0x6E3C3C, 0xFFAA5A),
		z("Dusk Trench",      "trench",   0x3E1A2E, 0x1C0A1C, 0x3A1C2E, 0x54303E, 0xFF923C),
	},
	[4] = { -- Frostbite Fjord: under the pack ice, down a crevasse, into the aurora
		z("Ice Shallows",     "shallows", 0xD0ECF8, 0x9CCEE6, 0xB2CEE0, 0xF4FCFF),
		z("Under the Ice",    "iceshelf", 0x9CCEE6, 0x609EC4, 0xC8E4F4, 0xEAF7FF),
		z("Glacier Crevasse", "crevasse", 0x609EC4, 0x2C608E, 0x78B0D0, 0xA8D6EE, 0xB4F0FF),
		z("Aurora Field",     "aurora",   0x2C608E, 0x14385E, 0x1E4264, 0x3C6E96, 0x78FFD2),
		z("Frozen Trench",    "trench",   0x14385E, 0x08182E, 0x1E3A5C, 0x315878, 0xA0E6FF),
	},
	[5] = { -- Midnight Trench: a whale fall, black spires, then the bloom
		z("Moonlit Shallows", "shallows", 0x22466C, 0x163254, 0x0E1626, 0x8AC4EC),
		z("Whale Fall",       "whalefall",0x163254, 0x0C203A, 0x1A2030, 0xC8D2E0),
		z("Obsidian Spires",  "spires",   0x0C203A, 0x061226, 0x0A0E1A, 0x141C2E, 0x4696FF),
		z("Bioluminescence",  "glow",     0x061226, 0x020816, 0x080C1A, 0x182846, 0x78FFF0),
		z("The Deep Dark",    "trench",   0x020816, 0x030A18, 0x121A2C, 0x1E2840, 0x96E2FF),
	},
	[6] = { -- Molten Abyss: a burnt forest, lava tubes, a field of embers
		z("Ash Shallows",     "shallows", 0xE46832, 0xB2421C, 0x301C16, 0xFFBC76),
		z("Charred Stumps",   "charred",  0xB2421C, 0x7A2A14, 0x301C16, 0x261814, 0xFF6A18),
		z("Lava Tubes",       "tubes",    0x7A2A14, 0x4E1A0E, 0x1E1210, 0x301C18, 0xFF8228),
		z("Ember Field",      "embers",   0x4E1A0E, 0x30100A, 0x1C0E0C, 0x462016, 0xFFA03C),
		z("Magma Trench",     "trench",   0x30100A, 0x1E0805, 0x35190F, 0x4A2618, 0xFF781E),
	},
}

----------------------------------------------------------------------
-- the rig: one invisible plane per stratum, stacked down the column
----------------------------------------------------------------------
-- Backgrounds are TRANSPARENT and carry structure only. The continuous water
-- colour lives on WaterBack behind them, which is what makes the stratum seams
-- invisible - butting five opaque painted panels together would show every join.
local planes = {}     -- [i] = { part, gui, root, y0, y1 }
local A = {}          -- animated elements: { f = frame, k = kind, ... }

local function pos(y) return (0 - y) / (0 - C.BOT) end

local function buildGradient(zid)
	local T = LINEUP[zid] or LINEUP[1]
	local kps = { ColorSequenceKeypoint.new(0, T[1].top) }
	for i, st in ipairs(STRATA) do
		local span = st.y0 - st.y1
		-- 15% / 85% into each band. That gives every stratum a solid core of its own
		-- colour and leaves a smooth 30%-wide blend across each boundary. Putting the
		-- keypoints ON the boundaries needs two keypoints at one time value, which
		-- ColorSequence rejects outright.
		kps[#kps+1] = ColorSequenceKeypoint.new(pos(st.y0 - span * 0.15), T[i].top)
		kps[#kps+1] = ColorSequenceKeypoint.new(pos(st.y0 - span * 0.85), T[i].bot)
	end
	kps[#kps+1] = ColorSequenceKeypoint.new(1, T[#STRATA].bot)
	return ColorSequence.new(kps)
end

local function buildPlanes()
	-- Reuse the folder and clear only the panels. Destroying it would take the
	-- DevStrata BindableEvent with it on every zone travel.
	local folder = workspace:FindFirstChild("DepthColumn")
		or mk("Folder", { Name = "DepthColumn" }, workspace)
	for _, c in ipairs(folder:GetChildren()) do
		if c:IsA("BasePart") then c:Destroy() end
	end
	table.clear(planes)
	for i, st in ipairs(STRATA) do
		local hgt = st.y0 - st.y1
		local part = mk("Part", {
			Name = "S" .. i .. "_" .. st.key,
			Size = Vector3.new(C.W, hgt, C.THK),
			CFrame = CFrame.new(0, (st.y0 + st.y1) / 2, C.Z),
			Transparency = 1, Anchored = true, CanCollide = false,
			CanQuery = false, CanTouch = false, CastShadow = false,
		}, folder)
		local gui = mk("SurfaceGui", {
			Name = "Art", Face = Enum.NormalId.Back,
			-- MUST be PixelsPerStud. The default is FixedSize, which pins the canvas
			-- at 800x600 and silently ignores the panel's real size.
			SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
			PixelsPerStud = C.PPS, LightInfluence = 0, AlwaysOnTop = false,
		}, part)
		local root = mk("Frame", { Name = "Root", BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1), ZIndex = 1 }, gui)
		planes[i] = { part = part, gui = gui, root = root, y0 = st.y0, y1 = st.y1,
			w = C.W * C.PPS, h = hgt * C.PPS }
	end
end

----------------------------------------------------------------------
-- builders - ONE PER PLACE. LINEUP picks which of these each zone's band uses,
-- so the zones differ in silhouette, not just in palette.
----------------------------------------------------------------------
local B = {}

-- ---------- shared primitives ----------
local function corner(f, r) mk("UICorner", { CornerRadius = UDim.new(r or 1, 0) }, f) end

local function fade(f, rot, a, b)
	mk("UIGradient", { Rotation = rot or 90, Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) }) }, f)
end

-- rounded mass. The workhorse: rock, hulls, stems, ice all come out of this.
local function blob(root, x, y, w, hh, col, zi, rot, anch)
	local f = mk("Frame", { BackgroundColor3 = col, BorderSizePixel = 0, ZIndex = zi or 4,
		AnchorPoint = anch or Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(math.floor(x), math.floor(y)),
		Size = UDim2.fromOffset(math.floor(w), math.floor(hh)), Rotation = rot or 0 }, root)
	corner(f, 0.5)
	return f
end

-- a 45-degree rotated square: the only way to get a POINT out of Roblox UI.
local function diamond(root, x, y, sd, col, zi)
	return mk("Frame", { BackgroundColor3 = col, BorderSizePixel = 0, ZIndex = zi or 4,
		AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45,
		Position = UDim2.fromOffset(math.floor(x), math.floor(y)),
		Size = UDim2.fromOffset(math.floor(sd), math.floor(sd)) }, root)
end

local function disc(root, x, y, d, col, zi, tr)
	local f = mk("Frame", { BackgroundColor3 = col, BorderSizePixel = 0, ZIndex = zi or 4,
		BackgroundTransparency = tr or 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(math.floor(x), math.floor(y)),
		Size = UDim2.fromOffset(math.floor(d), math.floor(d)) }, root)
	corner(f, 1)
	return f
end

-- a tapered column, built from stacked narrowing segments (UI cannot taper a frame)
local function taper(root, x, yBase, hgt, wBase, col, zi, segs, up)
	segs = segs or 5
	local parts = {}
	for k = 1, segs do
		local t0 = (k - 1) / segs
		local w = wBase * (1 - t0 * 0.72)
		local y = yBase + (up and -1 or 1) * (hgt * (t0 + 0.5 / segs))
		parts[k] = blob(root, x, y, math.max(2, w), hgt / segs * 1.25, col, zi)
	end
	return parts
end

local function sway(f, amp, sp)
	A[#A+1] = { f = f, k = "sway", amp = amp, sp = sp or (0.35 + math.random() * 0.4),
		ph = math.random() * 6.28 }
end
local function pulse(f, a0, amp, sp)
	A[#A+1] = { f = f, k = "pulse", a0 = a0, amp = amp,
		sp = sp or (0.5 + math.random() * 0.7), ph = math.random() * 6.28 }
end

-- suspended particles. Always tagged pc so Set_Particles can switch them off.
local function motes(root, W, H, n, col, minS, maxS, spdLo, spdHi, tr, zi)
	for _ = 1, n do
		local sz = math.max(1, W * (minS + math.random() * (maxS - minS)))
		local x, y = math.random(0, W), math.random(0, H)
		local f = disc(root, x, y, sz, col, zi or 3, tr or 0.4)
		A[#A+1] = { f = f, k = "rise", pc = true, fx = x, fy = y,
			sp = spdLo + math.random() * (spdHi - spdLo),
			amp = W * 0.007, ph = math.random() * 6.28, H = H }
	end
end

-- a jagged rock wall hugging one edge, in `layers` depth bands (far/hazier first)
-- ⚠️ `reach` IS THE FRACTION OF THE CANVAS THIS WALL COVERS, and the width must NOT be
-- doubled. It used to write `wdt * 2`, so at reach 0.30 each side spanned up to 72% of
-- the canvas - the two walls met in the middle, buried the water, and the whole band
-- rendered as a black box with a few shapes floating in it. Keep the widest row at
-- roughly `reach` so the throat stays open.
local function rockWall(root, W, H, side, col, layers, reach, zi)
	for L = 1, layers do
		local t0 = (L - 1) / math.max(1, layers - 1)
		local c = col:Lerp(Color3.new(0, 0, 0), 0.10 + 0.16 * (1 - t0))
		local rows = 16 + L * 4
		for k = 1, rows do
			local wdt = W * reach * (0.45 + math.random() * 0.55) * (0.70 + 0.30 * t0)
			local jit = (math.random() - 0.5) * (H / rows) * 0.9
			local f = blob(root, side < 0 and 0 or W, H * ((k - 0.5) / rows) + jit,
				wdt, H * (2.0 / rows), c, (zi or 4) + L)
			f.AnchorPoint = Vector2.new(side < 0 and 0 or 1, 0.5)
			f.Position = UDim2.fromOffset(side < 0 and 0 or W, math.floor(H * ((k - 0.5) / rows) + jit))
		end
	end
end

-- ---------- 1. SHALLOWS ----------
-- Open sunlit water. SeaFX owns the god rays on the waterline and GameClient keeps
-- 46-96 REAL fish swimming here, so this band deliberately adds almost nothing solid.
-- ⚠️ It once drew flat silhouette fish; beside the real 3D models they read as pale
-- blue arrows. Anything figurative here competes with the actual fish and loses.
function B.shallows(root, t, W, H)
	local band = mk("Frame", { Name = "Shimmer", BackgroundColor3 = t.accent,
		Size = UDim2.fromOffset(W, H * 0.26), BorderSizePixel = 0, ZIndex = 2 }, root)
	fade(band, 90, 0.58, 1)
	motes(root, W, H, 34, t.accent, 0.0016, 0.005, 2, 7, 0.45)
end

-- ---------- 2. KELP FOREST (Zone 1 only) ----------
-- The showpiece of the upper column, and deliberately the densest thing in here.
-- Built in THREE DEPTH LAYERS: far kelp is smaller, darker and sways least; near kelp
-- is bigger, brighter and sways most. That parallax is what stops it reading as a row
-- of green bars, which is exactly what the first version looked like.
function B.kelp(root, t, W, H)
	local rubble = t.rock
	-- seabed the forest is rooted in
	for k = 1, 16 do
		local w = W * (0.05 + math.random() * 0.11)
		blob(root, math.random(0, W), H - math.random(0, math.floor(H * 0.035)),
			w, w * (0.34 + math.random() * 0.3), rubble:Lerp(Color3.new(0,0,0), math.random() * 0.25), 6)
	end
	blob(root, W / 2, H + H * 0.02, W * 2.2, H * 0.09, rubble, 6)

	local LAYER = {
		{ n = 16, sc = 0.62, dark = 0.42, amp = 1.6, zi = 3 },   -- far
		{ n = 13, sc = 0.84, dark = 0.20, amp = 2.8, zi = 5 },   -- mid
		{ n = 10, sc = 1.10, dark = 0.00, amp = 4.2, zi = 7 },   -- near
	}
	for _, L in ipairs(LAYER) do
		local col = t.accent:Lerp(Color3.fromRGB(6, 26, 20), L.dark)
		local blade = col:Lerp(Color3.new(1, 1, 1), 0.10)
		for k = 1, L.n do
			local x = W * ((k - 0.5) / L.n) + (math.random() - 0.5) * (W / L.n) * 0.9
			local hgt = H * (0.46 + math.random() * 0.48) * L.sc
			local wid = W * (0.006 + math.random() * 0.005) * L.sc
			-- the stalk pivots at its HOLDFAST, so the whole plant leans as one
			local stem = mk("Frame", { BackgroundTransparency = 1, ZIndex = L.zi,
				AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(math.floor(x), H),
				Size = UDim2.fromOffset(math.max(2, wid), math.floor(hgt)) }, root)
			-- holdfast: the knot of roots gripping the rock
			disc(stem, wid / 2, hgt - wid * 0.4, wid * 3.4, rubble:Lerp(col, 0.35), L.zi)
			-- the stipe, tapering as it rises
			for seg = 1, 6 do
				local t0 = (seg - 1) / 6
				blob(stem, wid / 2 + math.sin(t0 * 3.1) * wid * 1.2, hgt * (1 - t0 - 0.08),
					math.max(2, wid * (1 - t0 * 0.45)), hgt / 6 * 1.3, col, L.zi)
			end
			-- blades + gas bladders alternating up the stipe
			local nb = math.max(4, math.floor(hgt / (H * 0.075)))
			for bI = 1, nb do
				local f0 = bI / (nb + 1)
				local side = (bI % 2 == 0) and 1 or -1
				local by = hgt * (1 - f0)
				local bx = wid / 2 + math.sin(f0 * 3.1) * wid * 1.2
				local bl = blob(stem, bx + side * wid * 2.6, by,
					wid * (5.5 + math.random() * 3), wid * (1.5 + math.random() * 0.8),
					blade, L.zi - 1, side * (-18 - math.random() * 22))
				fade(bl, side > 0 and 0 or 180, 0, 0.45)
				if bI % 2 == 1 then
					disc(stem, bx + side * wid * 0.9, by, wid * 1.7,
						blade:Lerp(Color3.new(1,1,1), 0.25), L.zi)
				end
			end
			sway(stem, L.amp + math.random() * 1.4, 0.3 + math.random() * 0.35)
		end
	end

	-- light filtering down between the fronds, and drifting spores
	for k = 1, 6 do
		local f = mk("Frame", { BackgroundColor3 = t.top, BorderSizePixel = 0, ZIndex = 2,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(math.floor(W * (0.1 + 0.16 * k)), 0),
			Size = UDim2.fromOffset(math.floor(W * (0.02 + math.random() * 0.03)), math.floor(H * 0.7)),
			Rotation = -8 + math.random() * 16 }, root)
		fade(f, 90, 0.62, 1)
		pulse(f, 0.7, 0.12, 0.25 + math.random() * 0.2)
	end
	motes(root, W, H, 30, t.accent:Lerp(Color3.new(1,1,1), 0.5), 0.0016, 0.0038, 1.5, 5, 0.45)
end

-- ---------- 3. SUNKEN CAVERN (Zone 1 only) ----------
-- Rock closes in from both sides with a THROAT down the middle. The gap matters: a
-- solid ceiling or floor reads as "you cannot go deeper", which is a lie.
-- Built in depth layers like the kelp - a hazy far wall behind, dark near rock in
-- front - plus strata banding, columns, rubble and a shaft of light through a crack.
-- The first version was 11 flat blobs a side and looked exactly that simple.
function B.cavern(root, t, W, H)
	-- ⚠️ 0.44 left the walls as ~8% slivers at the frame edges: the throat spanned
	-- canvas 0.28..0.72 while only 0.21..0.80 is visible past the HUD panels, so almost
	-- the whole visible frame was open water and the cave read as empty. 0.30 puts real
	-- rock in the shot. The hook steers wider than this, but every wall sits BEHIND the
	-- play plane, so the hook simply passes in front of it.
	local GAP  = 0.30
	local edge = W * (0.5 - GAP / 2)
	-- ⚠️ CONTRAST, measured not guessed. rgb(38,52,68) rock against water that renders
	-- around rgb(20,40,75) at this depth is no contrast at all - the walls were present
	-- and simply did not read. Push the near rock toward black so it SILHOUETTES, and
	-- keep the far wall hazy so the layers still separate.
	-- ⚠️ EVERY LAYER MUST BE DARKER THAN THE WATER, just by different amounts.
	-- Lerping the far wall toward t.top made it LIGHTER than the water at this depth,
	-- so it rendered as pale geometric slabs floating in the middle of the cave - the
	-- "hourglass" in the frame. Underwater, distance means darker and hazier, never
	-- brighter. Ramp all three off the band's own water colour instead.
	-- The rock reads by being DARKER than the water, so the water has to stay bright.
	-- near = closest and darkest (a silhouette), far = receding toward the water colour.
	local far  = t.rock:Lerp(t.bot, 0.55)
	local mid  = t.rock:Lerp(Color3.new(0, 0, 0), 0.25)
	local near = t.rock:Lerp(Color3.new(0, 0, 0), 0.50)

	-- ⚠️ THE FAR WALL MUST STAY BEHIND THE WALLS, NOT ACROSS THE THROAT. Scattering 14
	-- big dark blobs over the full width dragged the ENTIRE frame toward black, so the
	-- rock had nothing left to contrast against and the cave read as an empty dark box.
	-- Keep it in the outer thirds; the throat is water and must stay water.
	for k = 1, 12 do
		local side = (k % 2 == 0) and 1 or -1
		local x = (side < 0) and (W * math.random() * 0.34) or (W - W * math.random() * 0.34)
		blob(root, x, H * (math.random() * 1.0),
			W * (0.16 + math.random() * 0.2), H * (0.16 + math.random() * 0.16), far, 2)
	end

	rockWall(root, W, H, -1, mid, 2, 0.34, 3)
	rockWall(root, W, H,  1, mid, 2, 0.34, 3)

	-- ceiling + floor slabs flanking the throat, with strata lines through them
	local function slab(top, thick, inset)
		for _, side in ipairs({ -1, 1 }) do
			local f = mk("Frame", { BackgroundColor3 = near, BorderSizePixel = 0, ZIndex = 8,
				AnchorPoint = Vector2.new(side < 0 and 0 or 1, top and 0 or 1),
				Position = UDim2.fromOffset(side < 0 and 0 or W, top and 0 or H),
				Size = UDim2.fromOffset(math.floor(edge + inset), math.floor(thick)) }, root)
			corner(f, 0.18)
			for b = 1, 3 do
				local bar = mk("Frame", { BackgroundColor3 = near:Lerp(far, 0.30),
					BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 9,
					Position = UDim2.fromScale(0, 0.18 * b + 0.12), Size = UDim2.fromScale(1, 0.06) }, f)
			end
		end
	end
	slab(true,  H * 0.085, W * 0.02)
	slab(false, H * 0.100, W * 0.05)

	-- stalactites / stalagmites, tapered and varied; the slabs (higher ZIndex) hide the roots
	for k = 1, 13 do
		local down = k <= 8
		local sd   = W * (0.020 + math.random() * 0.05)
		local hgt  = H * (0.05 + math.random() * (down and 0.20 or 0.13))
		local x    = (k % 2 == 0) and (W * 0.015 + math.random() * edge)
		                          or (W - W * 0.015 - math.random() * edge)
		taper(root, x, down and (H * 0.085) or (H - H * 0.10), hgt, sd, near, 7, 5, not down)
	end
	-- a couple of full-height columns where they have met and fused
	for _, cx in ipairs({ W * 0.10, W * 0.88 }) do
		blob(root, cx + (math.random() - 0.5) * W * 0.05, H * 0.5,
			W * (0.035 + math.random() * 0.02), H * 0.9, near, 7)
	end

	-- rubble heaped along the base of each wall
	for k = 1, 14 do
		local side = (k % 2 == 0) and 1 or -1
		local w = W * (0.03 + math.random() * 0.06)
		blob(root, side < 0 and (W * 0.16 + math.random() * edge * 0.9)
		                     or (W - W * 0.16 - math.random() * edge * 0.9),
			H - H * 0.10 - math.random() * H * 0.03, w, w * 0.6, near:Lerp(mid, 0.4), 8)
	end

	-- A single soft shaft down the throat. Kept very faint: at 0.55 opacity it read as
	-- a hard pale wedge rather than light, and there is no daylight this deep anyway -
	-- this is just enough to give the empty middle some shape.
	local shaft = mk("Frame", { BackgroundColor3 = t.top, BorderSizePixel = 0, ZIndex = 3,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(math.floor(W * 0.46), math.floor(H * 0.05)),
		Size = UDim2.fromOffset(math.floor(W * 0.07), math.floor(H * 0.55)), Rotation = 4 }, root)
	fade(shaft, 90, 0.86, 1)
	pulse(shaft, 0.88, 0.05, 0.3)

	-- glowing veins in the rock, and water dripping from the roof
	if t.glow then
		for k = 1, 16 do
			local side = (k % 2 == 0) and 1 or -1
			local f = mk("Frame", { BackgroundColor3 = t.glow, BorderSizePixel = 0, ZIndex = 10,
				BackgroundTransparency = 0.18, AnchorPoint = Vector2.new(0.5, 0.5),
				Rotation = -50 + math.random() * 100,
				-- canvas 0.22..0.33 / 0.67..0.78 - ON the rock and inside the window the
				-- HUD panels leave (0.21..0.80). At 0.02..0.18 they sat behind the
				-- BaitRoller entirely; at 0.20..0.36 they floated in the open throat.
				Position = UDim2.fromOffset(
					math.floor(side < 0 and (W * 0.22 + math.random() * W * 0.11)
					                    or (W * 0.67 + math.random() * W * 0.11)),
					math.floor(H * (0.10 + math.random() * 0.80))),
				-- thin and short: at 14x220px these read as cyan STICKS lying across the
				-- frame rather than cracks in the rock.
				Size = UDim2.fromOffset(math.max(2, W * 0.005),
					math.floor(H * (0.018 + math.random() * 0.035))) }, root)
			f.BackgroundTransparency = 0.35
			pulse(f, 0.35, 0.22)
		end
	end
	motes(root, W, H, 22, t.glow or t.accent, 0.0014, 0.003, 2, 6, 0.5)
end

-- ---------- CORAL GARDEN (Zone 2) ----------
function B.coral(root, t, W, H)
	blob(root, W / 2, H + H * 0.02, W * 2.2, H * 0.12, t.rock, 6)   -- sand
	local PAL = { t.accent, t.accent:Lerp(Color3.fromRGB(255,220,90), 0.5),
	              t.accent:Lerp(Color3.fromRGB(150,90,255), 0.45), t.glow or t.accent }
	-- branching corals: a trunk that forks twice
	for k = 1, 12 do
		local x = W * ((k - 0.5) / 12) + (math.random() - 0.5) * W * 0.05
		local col = PAL[math.random(1, #PAL)]
		local hgt = H * (0.14 + math.random() * 0.20)
		local base = mk("Frame", { BackgroundTransparency = 1, ZIndex = 6,
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(math.floor(x), H),
			Size = UDim2.fromOffset(math.max(3, W * 0.02), math.floor(hgt)) }, root)
		local w = W * 0.011
		blob(base, W * 0.01, hgt * 0.72, w, hgt * 0.58, col, 6)
		for _, sgn in ipairs({ -1, 1 }) do
			blob(base, W * 0.01 + sgn * w * 1.5, hgt * 0.34, w * 0.75, hgt * 0.5, col, 6, sgn * 22)
			blob(base, W * 0.01 + sgn * w * 2.6, hgt * 0.12, w * 0.6, hgt * 0.32, col, 6, sgn * 34)
		end
		sway(base, 1.2 + math.random(), 0.3 + math.random() * 0.3)
	end
	-- brain corals + sea fans + anemones
	for k = 1, 9 do
		local x, d = math.random(0, W), W * (0.03 + math.random() * 0.04)
		local c = PAL[math.random(1, #PAL)]
		local br = disc(root, x, H - H * 0.05 - d * 0.2, d, c, 7)
		for r = 1, 3 do disc(br, d / 2, d / 2, d * (1 - r * 0.22), c:Lerp(Color3.new(0,0,0), 0.18 * r), 7, 0.25) end
	end
	for k = 1, 7 do
		local x = math.random(0, W)
		local d = W * (0.05 + math.random() * 0.05)
		local fan = disc(root, x, H - H * 0.10 - d * 0.35, d, PAL[math.random(1,#PAL)], 5, 0.22)
		sway(fan, 2.2, 0.4)
	end
	for k = 1, 10 do
		local x, y = math.random(0, W), H - H * (0.05 + math.random() * 0.05)
		local c = t.glow or t.accent
		for a = 1, 7 do
			local ten = blob(root, x, y, math.max(2, W * 0.004), H * 0.035, c, 8, -55 + a * 18)
			ten.AnchorPoint = Vector2.new(0.5, 1)
			ten.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
		end
	end
	motes(root, W, H, 26, t.glow or t.accent, 0.0016, 0.0034, 2, 6, 0.45)
end

-- ---------- THE WRECK (Zone 2) ----------
function B.wreck(root, t, W, H)
	local hull = t.rock
	local rust = hull:Lerp(Color3.fromRGB(120, 60, 30), 0.4)
	blob(root, W / 2, H + H * 0.02, W * 2.2, H * 0.12, t.rock:Lerp(Color3.fromRGB(216,190,150), 0.6), 3)
	-- the hull, listing to one side, broken in two
	local hy = H * 0.66
	local bow = blob(root, W * 0.34, hy, W * 0.52, H * 0.30, hull, 6, -12)
	local stern = blob(root, W * 0.78, hy + H * 0.05, W * 0.34, H * 0.24, hull, 6, 8)
	-- deck line + portholes, some still lit
	for k = 1, 7 do
		local px = W * (0.16 + 0.075 * k)
		local lit = (k % 3 == 0) and t.glow or hull:Lerp(Color3.new(0,0,0), 0.5)
		local p = disc(root, px, hy - H * 0.02 - (px - W * 0.34) * 0.20, W * 0.018, lit, 8)
		if k % 3 == 0 then pulse(p, 0.15, 0.25) end
	end
	-- ribs of the broken midsection
	for k = 1, 6 do
		blob(root, W * (0.56 + k * 0.016), hy - H * 0.02, math.max(2, W * 0.006), H * 0.22,
			rust, 7, -18 + k * 5)
	end
	-- snapped mast + rigging
	blob(root, W * 0.30, H * 0.40, math.max(3, W * 0.010), H * 0.46, rust, 7, 24)
	blob(root, W * 0.46, H * 0.30, math.max(2, W * 0.006), H * 0.20, rust, 7, -38)
	-- growth reclaiming it
	for k = 1, 14 do
		local x = W * (0.12 + math.random() * 0.78)
		local d = W * (0.012 + math.random() * 0.02)
		disc(root, x, hy - H * 0.10 + math.random() * H * 0.16, d,
			(t.glow or t.accent):Lerp(hull, 0.35), 9, 0.25)
	end
	motes(root, W, H, 24, t.glow or t.accent, 0.0014, 0.003, 2, 5, 0.5)
end

-- ---------- THE BLUE HOLE (Zone 2) ----------
-- A vast open drop: walls fall away on both sides and the middle is simply empty.
function B.bluehole(root, t, W, H)
	rockWall(root, W, H, -1, t.rock, 3, 0.20, 3)
	rockWall(root, W, H,  1, t.rock, 3, 0.20, 3)
	-- ledges stepping down the inside of the shaft
	for k = 1, 8 do
		local side = (k % 2 == 0) and 1 or -1
		local lw = W * (0.10 + math.random() * 0.09)
		local f = blob(root, side < 0 and lw * 0.5 or W - lw * 0.5,
			H * (0.10 + 0.11 * k), lw, H * 0.030, t.rock:Lerp(Color3.new(0,0,0), 0.25), 7)
	end
	-- the bright mouth far above, fading into the dark
	local mouth = mk("Frame", { BackgroundColor3 = t.top, BorderSizePixel = 0, ZIndex = 2,
		Size = UDim2.fromOffset(W, math.floor(H * 0.34)) }, root)
	fade(mouth, 90, 0.45, 1)
	motes(root, W, H, 34, t.glow or t.accent, 0.0012, 0.0028, 3, 8, 0.5)
end

-- ---------- SEAGRASS MEADOW (Zone 3) ----------
function B.seagrass(root, t, W, H)
	blob(root, W / 2, H + H * 0.02, W * 2.2, H * 0.10, t.rock, 6)
	for k = 1, 90 do
		local x = math.random(0, W)
		local hgt = H * (0.10 + math.random() * 0.26)
		local col = t.accent:Lerp(Color3.new(0, 0, 0), math.random() * 0.35)
		local g = mk("Frame", { BackgroundColor3 = col, BorderSizePixel = 0, ZIndex = 5,
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(x, H),
			Size = UDim2.fromOffset(math.max(2, W * 0.004), math.floor(hgt)),
			Rotation = -12 + math.random() * 24 }, root)
		corner(g, 1)
		if k % 3 == 0 then sway(g, 3 + math.random() * 3, 0.5 + math.random() * 0.4) end
	end
	for k = 1, 10 do   -- shells and stones in the sand
		local d = W * (0.012 + math.random() * 0.018)
		disc(root, math.random(0, W), H - H * 0.03 - math.random() * H * 0.02, d,
			t.rock:Lerp(Color3.new(1,1,1), 0.3), 7)
	end
	motes(root, W, H, 28, t.accent:Lerp(Color3.new(1,1,1), 0.4), 0.0014, 0.003, 2, 6, 0.45)
end

-- ---------- SANDSTONE ARCHES (Zone 3) ----------
function B.arches(root, t, W, H)
	local stone = t.rock
	blob(root, W / 2, H + H * 0.02, W * 2.2, H * 0.10, stone, 3)
	-- an arch = two legs + a span. Roblox UI cannot cut a hole, so build the frame.
	local function arch(cx, spanW, hgt, col, zi)
		local legW = spanW * 0.22
		blob(root, cx - spanW / 2, H - hgt / 2, legW, hgt, col, zi)
		blob(root, cx + spanW / 2, H - hgt / 2, legW, hgt, col, zi)
		blob(root, cx, H - hgt + legW * 0.35, spanW + legW, legW * 1.5, col, zi)
		for b = 1, 3 do   -- weathered strata banding
			blob(root, cx, H - hgt * (0.22 * b + 0.1), spanW * 1.4, hgt * 0.035,
				col:Lerp(Color3.new(1,1,1), 0.18), zi + 1).BackgroundTransparency = 0.45
		end
	end
	arch(W * 0.20, W * 0.26, H * 0.52, stone:Lerp(t.top, 0.30), 4)   -- far, hazier
	arch(W * 0.78, W * 0.22, H * 0.44, stone:Lerp(t.top, 0.30), 4)
	arch(W * 0.46, W * 0.34, H * 0.70, stone, 6)                     -- near
	rockWall(root, W, H, -1, stone, 1, 0.16, 7)
	rockWall(root, W, H,  1, stone, 1, 0.16, 7)
	if t.glow then
		for k = 1, 7 do
			local f = disc(root, math.random(0, W), H * (0.3 + math.random() * 0.6),
				W * 0.02, t.glow, 8, 0.4)
			pulse(f, 0.4, 0.25)
		end
	end
	motes(root, W, H, 24, t.accent, 0.0014, 0.003, 2, 5, 0.5)
end

-- ---------- UNDER THE ICE (Zone 4) ----------
function B.iceshelf(root, t, W, H)
	local ice = t.rock
	-- the pack ice ceiling, with pressure ridges and cracks of daylight
	local roof = mk("Frame", { BackgroundColor3 = ice, BorderSizePixel = 0, ZIndex = 7,
		Size = UDim2.fromOffset(W, math.floor(H * 0.20)) }, root)
	for k = 1, 9 do
		blob(root, W * ((k - 0.5) / 9), H * 0.20, W * (0.12 + math.random() * 0.1),
			H * (0.05 + math.random() * 0.06), ice, 7)
	end
	for k = 1, 6 do   -- light through the cracks
		local f = mk("Frame", { BackgroundColor3 = t.accent, BorderSizePixel = 0, ZIndex = 6,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(math.floor(W * (0.08 + 0.16 * k)), math.floor(H * 0.18)),
			Size = UDim2.fromOffset(math.floor(W * (0.015 + math.random() * 0.02)), math.floor(H * 0.55)),
			Rotation = -10 + math.random() * 20 }, root)
		fade(f, 90, 0.5, 1)
		pulse(f, 0.55, 0.14, 0.25)
	end
	-- icicles hanging from the underside
	for k = 1, 22 do
		taper(root, W * ((k - 0.5) / 22) + (math.random() - 0.5) * W * 0.03, H * 0.22,
			H * (0.05 + math.random() * 0.22), W * (0.008 + math.random() * 0.012),
			ice:Lerp(Color3.new(1,1,1), 0.25), 8, 5, false)
	end
	-- brash ice drifting below
	for k = 1, 12 do
		local d = W * (0.02 + math.random() * 0.045)
		local f = diamond(root, math.random(0, W), H * (0.45 + math.random() * 0.5), d,
			ice:Lerp(Color3.new(1,1,1), 0.15), 5)
		sway(f, 6, 0.25 + math.random() * 0.2)
	end
	motes(root, W, H, 26, Color3.fromRGB(235,248,255), 0.0012, 0.0028, 1.5, 4, 0.5)
end

-- ---------- GLACIER CREVASSE (Zone 4) ----------
function B.crevasse(root, t, W, H)
	local ice = t.rock
	-- two towering ice walls converging toward the bottom
	for _, side in ipairs({ -1, 1 }) do
		for k = 1, 18 do
			local t0 = (k - 0.5) / 18
			local reach = W * (0.16 + t0 * 0.20)          -- closes in with depth
			local f = blob(root, side < 0 and 0 or W, H * t0, reach * 2, H * (2.1 / 18),
				ice:Lerp(Color3.new(0,0,0), 0.10 + t0 * 0.25), 5)
			f.AnchorPoint = Vector2.new(side < 0 and 0 or 1, 0.5)
			f.Position = UDim2.fromOffset(side < 0 and 0 or W, math.floor(H * t0))
		end
		-- vertical striations in the ice face
		for k = 1, 10 do
			local x = side < 0 and (W * 0.02 + math.random() * W * 0.22)
			                    or (W - W * 0.02 - math.random() * W * 0.22)
			blob(root, x, H * (0.1 + math.random() * 0.8), math.max(2, W * 0.005),
				H * (0.12 + math.random() * 0.2), ice:Lerp(Color3.new(1,1,1), 0.3), 6,
				-6 + math.random() * 12).BackgroundTransparency = 0.45
		end
	end
	-- the bright slot of sky far above
	local slot = mk("Frame", { BackgroundColor3 = t.accent, BorderSizePixel = 0, ZIndex = 2,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(math.floor(W / 2), 0),
		Size = UDim2.fromOffset(math.floor(W * 0.30), math.floor(H * 0.5)) }, root)
	fade(slot, 90, 0.35, 1)
	if t.glow then
		for k = 1, 12 do
			local f = blob(root, math.random(0, W), H * (0.15 + math.random() * 0.8),
				math.max(2, W * 0.006), H * (0.04 + math.random() * 0.07), t.glow, 8,
				-40 + math.random() * 80)
			pulse(f, 0.25, 0.25)
		end
	end
	motes(root, W, H, 22, Color3.fromRGB(210,240,255), 0.0012, 0.0026, 2, 5, 0.5)
end

-- ---------- AURORA FIELD (Zone 4) ----------
-- Curtains of light, not creatures - deliberately unlike the Glowfield.
function B.aurora(root, t, W, H)
	local g = t.glow or t.accent
	for k = 1, 9 do
		local x = W * ((k - 0.5) / 9) + (math.random() - 0.5) * W * 0.06
		local curtain = mk("Frame", { BackgroundColor3 = g:Lerp(Color3.fromRGB(120,180,255), math.random() * 0.5),
			BorderSizePixel = 0, ZIndex = 4, AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(math.floor(x), math.floor(H * (math.random() * 0.2))),
			Size = UDim2.fromOffset(math.floor(W * (0.04 + math.random() * 0.06)),
				math.floor(H * (0.5 + math.random() * 0.45))),
			Rotation = -7 + math.random() * 14 }, root)
		fade(curtain, 90, 0.55, 1)
		corner(curtain, 0.4)
		sway(curtain, 3 + math.random() * 3, 0.18 + math.random() * 0.18)
		pulse(curtain, 0.55, 0.2, 0.22 + math.random() * 0.2)
	end
	motes(root, W, H, 40, g, 0.0012, 0.0032, 2, 7, 0.35)
end

-- ---------- WHALE FALL (Zone 5) ----------
function B.whalefall(root, t, W, H)
	local bone = t.accent
	blob(root, W / 2, H + H * 0.02, W * 2.2, H * 0.10, t.rock, 3)
	local spineY = H * 0.80
	blob(root, W * 0.5, spineY, W * 0.72, H * 0.022, bone, 6, -3)   -- spine
	-- ribs arcing up from it, longest at the middle
	for k = 1, 9 do
		local f0 = (k - 0.5) / 9
		local x = W * (0.17 + f0 * 0.66)
		local len = H * (0.10 + 0.26 * math.sin(f0 * 3.14159))
		for _, sgn in ipairs({ -1, 1 }) do
			local rib = blob(root, x + sgn * len * 0.20, spineY - len * 0.45,
				math.max(2, W * 0.008), len, bone, 5, sgn * 26)
			rib.BackgroundTransparency = 0.05
		end
	end
	-- skull
	blob(root, W * 0.12, spineY - H * 0.03, W * 0.15, H * 0.10, bone, 6, -8)
	blob(root, W * 0.06, spineY + H * 0.005, W * 0.10, H * 0.045, bone, 6, -8)
	-- scavengers and drifting matter
	for k = 1, 12 do
		local f = disc(root, math.random(0, W), spineY - math.random() * H * 0.25,
			W * (0.006 + math.random() * 0.006), bone:Lerp(t.top, 0.4), 7, 0.3)
	end
	motes(root, W, H, 34, bone:Lerp(Color3.new(1,1,1), 0.3), 0.0012, 0.0026, 1.5, 4, 0.55)
end

-- ---------- OBSIDIAN SPIRES (Zone 5) ----------
function B.spires(root, t, W, H)
	local rock = t.rock
	for k = 1, 11 do
		local x = W * ((k - 0.5) / 11) + (math.random() - 0.5) * W * 0.05
		local up = math.random() > 0.35
		local hgt = H * (0.3 + math.random() * 0.55)
		taper(root, x, up and H or 0, hgt, W * (0.02 + math.random() * 0.03),
			rock:Lerp(Color3.new(0,0,0), math.random() * 0.3), up and 6 or 5, 6, up)
		if t.glow and k % 2 == 0 then   -- faint rim light down one edge
			local f = blob(root, x + W * 0.012, (up and H or 0) + (up and -hgt * 0.5 or hgt * 0.5),
				math.max(2, W * 0.004), hgt * 0.7, t.glow, 8)
			f.BackgroundTransparency = 0.55
			pulse(f, 0.55, 0.2)
		end
	end
	rockWall(root, W, H, -1, rock, 1, 0.14, 3)
	rockWall(root, W, H,  1, rock, 1, 0.14, 3)
	motes(root, W, H, 26, t.glow or t.accent, 0.0012, 0.0026, 2, 6, 0.55)
end

-- ---------- LAVA TUBES (Zone 6) ----------
function B.tubes(root, t, W, H)
	local rock = t.rock
	rockWall(root, W, H, -1, rock, 2, 0.26, 3)
	rockWall(root, W, H,  1, rock, 2, 0.26, 3)
	-- basalt columns
	for k = 1, 9 do
		local x = W * ((k - 0.5) / 9)
		blob(root, x, H * (0.2 + math.random() * 0.6), W * (0.02 + math.random() * 0.02),
			H * (0.2 + math.random() * 0.3), rock:Lerp(Color3.new(0,0,0), 0.3), 6)
	end
	-- tube mouths in the walls, glowing from inside
	for k = 1, 7 do
		local side = (k % 2 == 0) and 1 or -1
		local d = W * (0.05 + math.random() * 0.05)
		local x = side < 0 and (W * 0.05 + math.random() * W * 0.12)
		                    or (W - W * 0.05 - math.random() * W * 0.12)
		local y = H * (0.12 + math.random() * 0.72)
		disc(root, x, y, d * 1.25, rock:Lerp(Color3.new(0,0,0), 0.45), 8)
		local core = disc(root, x, y, d * 0.72, t.glow or t.accent, 9, 0.1)
		pulse(core, 0.1, 0.22)
		-- lava spilling from the mouth
		local run = blob(root, x + side * d * 0.1, y + H * 0.10, math.max(3, d * 0.3), H * 0.2,
			t.glow or t.accent, 7, side * 6)
		fade(run, 90, 0.25, 1)
	end
	motes(root, W, H, 40, t.glow or t.accent, 0.0016, 0.0036, 4, 10, 0.35)
end

-- ---------- EMBER FIELD (Zone 6) ----------
function B.embers(root, t, W, H)
	local g = t.glow or t.accent
	-- magma glowing through cracks in the floor
	blob(root, W / 2, H + H * 0.02, W * 2.2, H * 0.12, t.rock, 5)
	for k = 1, 10 do
		local f = blob(root, math.random(0, W), H - H * 0.06, W * (0.04 + math.random() * 0.07),
			H * 0.02, g, 6, -8 + math.random() * 16)
		pulse(f, 0.2, 0.28)
	end
	-- heat columns rising off them
	for k = 1, 7 do
		local col = mk("Frame", { BackgroundColor3 = g, BorderSizePixel = 0, ZIndex = 4,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(math.floor(W * (0.08 + 0.13 * k)), math.floor(H * 0.95)),
			Size = UDim2.fromOffset(math.floor(W * (0.05 + math.random() * 0.05)),
				math.floor(H * (0.35 + math.random() * 0.35))) }, root)
		fade(col, 90, 1, 0.45)
		sway(col, 2, 0.2 + math.random() * 0.2)
	end
	motes(root, W, H, 60, g, 0.0018, 0.004, 5, 13, 0.3)
end

-- ---------- CHARRED STUMPS (Zone 6) ----------
function B.charred(root, t, W, H)
	blob(root, W / 2, H + H * 0.02, W * 2.2, H * 0.10, t.rock, 5)
	for k = 1, 18 do
		local x = W * ((k - 0.5) / 18) + (math.random() - 0.5) * W * 0.04
		local hgt = H * (0.15 + math.random() * 0.45)
		local wid = W * (0.008 + math.random() * 0.008)
		local col = t.accent:Lerp(Color3.new(0,0,0), math.random() * 0.4)
		taper(root, x, H, hgt, wid * 2.2, col, 6, 5, true)
		for b = 1, 2 do   -- a couple of bare snapped branches
			local sgn = (b == 1) and 1 or -1
			blob(root, x + sgn * wid * 3, H - hgt * (0.45 + b * 0.18),
				wid * 5, math.max(2, wid * 1.1), col, 6, sgn * -34)
		end
		if t.glow and k % 4 == 0 then   -- a few still smouldering at the base
			local e = disc(root, x, H - H * 0.02, W * 0.012, t.glow, 8, 0.3)
			pulse(e, 0.3, 0.3)
		end
	end
	motes(root, W, H, 44, t.glow or t.accent, 0.0014, 0.0032, 3, 9, 0.4)
end

-- ---------- GLOWFIELD (Zones 1, 3, 5) ----------
-- The water is nearly black here, so everything visible is something alive.
function B.glow(root, t, W, H)
	local g = t.glow or t.accent
	for _ = 1, 20 do
		local sz = W * (0.010 + math.random() * 0.015)
		local x, y = math.random(W * 0.04, W * 0.96), math.random(H * 0.06, H * 0.94)
		local holder = mk("Frame", { BackgroundTransparency = 1, ZIndex = 4,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(math.floor(sz * 4), math.floor(sz * 4)) }, root)
		local rings = {}
		for _, ring in ipairs({ { 1.00, 0.93 }, { 0.62, 0.78 }, { 0.40, 0.38 } }) do
			local r = mk("Frame", { BackgroundColor3 = g, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(ring[1], ring[1]),
				BackgroundTransparency = ring[2], BorderSizePixel = 0, ZIndex = 4 }, holder)
			corner(r, 1)
			rings[#rings+1] = { f = r, a = ring[2] }
		end
		for jj = 1, 4 do
			local st = mk("Frame", { BackgroundColor3 = g, AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.38 + jj * 0.08, 0.52),
				Size = UDim2.fromOffset(math.max(1, sz * 0.07), math.floor(sz * (0.9 + math.random()))),
				BackgroundTransparency = 0.62, BorderSizePixel = 0, ZIndex = 4 }, holder)
			corner(st, 1)
		end
		-- ⚠️ size-breathe the holder, but pulse each RING's own transparency: writing
		-- transparency on the holder does nothing, it is a container at transparency 1.
		local jsp, jph = 0.4 + math.random() * 0.6, math.random() * 6.28
		A[#A+1] = { f = holder, k = "pulse", a0 = 0, amp = 0, sp = jsp, ph = jph,
			s0 = sz * 4, samp = 0.10 }
		for _, r in ipairs(rings) do
			A[#A+1] = { f = r.f, k = "pulse", a0 = r.a, amp = 0.16, sp = jsp, ph = jph }
		end
		A[#A+1] = { f = holder, k = "rise", fx = x, fy = y, sp = 1.2 + math.random() * 2.4,
			amp = W * 0.010, ph = math.random() * 6.28, H = H }
	end
	motes(root, W, H, 26, g, 0.0018, 0.0048, 3, 9, 0.3)
end

-- ---------- ABYSSAL TRENCH (all six zones' floor) ----------
-- ⚠️ This band is 190 studs tall but a maxed cast only reaches -620, so the seabed at
-- -641 is barely ever on screen. Parking all the art on the floor left 150 studs of
-- pure black water above it. The CANYON WALLS are what make the descent read as a
-- trench, and the wall vents are what light it.
function B.trench(root, t, W, H)
	local g = t.glow or t.accent
	local FLOOR = H * 0.93

	local function vent(x, baseY, sd)
		local R = sd * 0.7071                 -- half-diagonal of the rotated square
		diamond(root, x, baseY, sd, t.rock, 5)
		-- The crater must FIT the cone or it reads as a table floating on a neck: at
		-- height h above the base the cone is only (R - h) wide either side.
		local ch = R * 0.70
		local cw = math.max(3, (R - ch) * 2)
		local cr = disc(root, x, baseY - ch, cw, g, 7, 0.10)
		cr.Size = UDim2.fromOffset(math.floor(cw), math.floor(math.max(2, cw * 0.5)))
		pulse(cr, 0.10, 0.22)
		local plume = mk("Frame", { BackgroundColor3 = g, BorderSizePixel = 0, ZIndex = 4,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(math.floor(x), math.floor(baseY - ch)),
			Size = UDim2.fromOffset(math.max(3, math.floor(cw * 1.6)),
				math.floor(H * (0.16 + math.random() * 0.16))) }, root)
		fade(plume, 90, 1, 0.5)
		A[#A+1] = { f = plume, k = "pulse", a0 = 0, amp = 0,
			sp = 0.3 + math.random() * 0.4, ph = math.random() * 6.28,
			s0 = plume.Size.Y.Offset, samp = 0.16, axis = "y" }
	end

	-- canyon walls, the full height of the band, plus ledges each carrying a vent so
	-- something lit is always within a screen of you
	for _, side in ipairs({ -1, 1 }) do
		rockWall(root, W, H, side, t.rock, 2, 0.22, 4)
		for k = 1, 5 do
			local ly = H * (0.10 + 0.18 * (k - 1)) + (math.random() - 0.5) * H * 0.05
			local lw = W * (0.13 + math.random() * 0.10)
			local lg = blob(root, side < 0 and lw * 0.5 or W - lw * 0.5, ly, lw, H * 0.030, t.rock, 6)
			vent(side < 0 and lw * 0.72 or W - lw * 0.72, ly - H * 0.014,
				W * (0.055 + math.random() * 0.035))
		end
	end

	local fl = mk("Frame", { BackgroundColor3 = t.rock, BorderSizePixel = 0, ZIndex = 6,
		Position = UDim2.fromOffset(0, math.floor(FLOOR)),
		Size = UDim2.fromOffset(W, math.floor(H - FLOOR + 4)) }, root)
	corner(fl, 0.06)
	for k = 1, 4 do
		vent(W * (0.16 + 0.23 * (k - 1)) + (math.random() - 0.5) * W * 0.05,
			FLOOR, W * (0.11 + math.random() * 0.09))
	end
	motes(root, W, H, 55, g, 0.0022, 0.0062, 4, 14, 0.35)
end

----------------------------------------------------------------------
-- assembly
----------------------------------------------------------------------
-- The sea plane only spanned 0..-270 while the depth ladder runs to -620, so a
-- deep cast dropped off the bottom of the painted water. Stretch it to the floor.
water.Size   = Vector3.new(water.Size.X, -C.BOT, water.Size.Z)
water.CFrame = CFrame.new(water.Position.X, C.BOT / 2, water.Position.Z)

local function currentZone() return plr:GetAttribute("CurrentZone") or 1 end

-- ⚠️ SETTINGS CONTRACT. Every other FX script in this game honours Set_Particles /
-- Set_WaterFX (SeaFX drops its whole Motes folder), and the strata pile ~115 more
-- animated motes on top of SeaFX's. A player who turns particles off - or picks a low
-- quality preset - must not still be paying for them. Split deliberately:
--   Set_Particles -> the suspended motes/ash/plankton HIDE (they are pure dressing)
--   Set_WaterFX   -> the scenery FREEZES but stays visible (kelp sway, jelly pulse,
--                    vent plumes). The structure IS the environment; hiding it would
--                    delete the feature rather than cheapen it.
local fxOn = { parts = true, water = true }
local function fxRefresh()
	fxOn.parts = plr:GetAttribute("Set_Particles") ~= false
	fxOn.water = plr:GetAttribute("Set_WaterFX") ~= false
	for _, p in ipairs(planes) do
		if p.fx then
			for _, e in ipairs(p.fx) do
				if e.pc then e.f.Visible = fxOn.parts end
			end
		end
	end
end
plr:GetAttributeChangedSignal("Set_Particles"):Connect(fxRefresh)
plr:GetAttributeChangedSignal("Set_WaterFX"):Connect(fxRefresh)

local function rebuild(zid)
	local T = LINEUP[zid] or LINEUP[1]
	buildPlanes()
	for i, p in ipairs(planes) do
		-- Rebinding the `A` upvalue re-points every builder's append target at this
		-- plane's own list, so animation can be skipped per-plane when it is culled.
		p.fx = {}
		A = p.fx
		local build = B[T[i].kind]
		if build then build(p.root, T[i], p.w, p.h) end
	end
	local gf    = water:FindFirstChild("Grad")
	local frame = gf and gf:FindFirstChild("Frame")
	local grad  = frame and frame:FindFirstChild("UIGradient")
	if grad then grad.Color = buildGradient(zid) end
	-- a zone travel rebuilds every element, so re-apply the settings to the new art
	-- or turning particles off then travelling silently brings them all back
	fxRefresh()
end

----------------------------------------------------------------------
-- animate + cull
----------------------------------------------------------------------
local forceAll = false

local function animate(list, t, dt)
	for _, e in ipairs(list) do
		local k = e.k
		if (e.pc and not fxOn.parts) or (not e.pc and not fxOn.water) then
			k = nil                          -- switched off: skip every branch below
		end
		if k == "swim" then
			e.fx += e.sp * dt
			if e.fx > e.W + 40 then e.fx = -40 end
			-- ⚠️ float accumulator -> floor -> Offset. UDim.Offset is an integer, so
			-- writing sub-pixel movement straight to Position rounds it away and
			-- NOTHING moves, silently.
			e.f.Position = UDim2.fromOffset(math.floor(e.fx),
				math.floor(e.fy + math.sin(t * 0.8 + e.ph) * e.amp))
		elseif k == "sway" then
			e.f.Rotation = math.sin(t * e.sp + e.ph) * e.amp
		elseif k == "rise" then
			e.fy -= e.sp * dt
			if e.fy < -10 then e.fy = e.H + 10 end
			e.f.Position = UDim2.fromOffset(
				math.floor(e.fx + math.sin(t * 0.6 + e.ph) * e.amp), math.floor(e.fy))
		elseif k == "pulse" then
			local w = math.sin(t * e.sp + e.ph)
			if e.amp > 0 then
				e.f.BackgroundTransparency = math.clamp(e.a0 + w * e.amp, 0, 1)
			end
			if e.s0 then
				local sc = math.floor(e.s0 * (1 + w * e.samp))
				e.f.Size = (e.axis == "y") and UDim2.fromOffset(e.f.Size.X.Offset, sc)
					or UDim2.fromOffset(sc, sc)
			end
		end
	end
end

-- Which stratum the camera is in, published so the rest of the game can react to
-- depth without duplicating this table (GameClient's bait lamp reads it).
-- ⚠️ Must re-publish when the ZONE changes too, not just the stratum index. The
-- index is the same 1 before and after travelling, so gating on it alone left the
-- NAME stale: standing in zone 1's shallows still reported "Ash Shallows" from
-- zone 6. Track both.
local lastPub = { i = nil, z = nil }
local function publishStratum(camY, zid)
	local T = LINEUP[zid] or LINEUP[1]
	-- The idle camera sits ABOVE the water (y=+11), which is in no stratum at all.
	-- Clamp so being at the surface reads as stratum 1 instead of going stale.
	local y = math.min(camY, -0.01)
	for i, st in ipairs(STRATA) do
		if y <= st.y0 and y > st.y1 then
			if lastPub.i ~= i or lastPub.z ~= zid then
				lastPub.i, lastPub.z = i, zid
				plr:SetAttribute("DepthStratum", i)
				plr:SetAttribute("DepthStratumName", T[i].name)
			end
			return
		end
	end
end

RunService.Heartbeat:Connect(function(dt)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local camY = cam.CFrame.Position.Y
	local t = os.clock()
	for _, p in ipairs(planes) do
		-- Only the stratum you are actually in (plus a screen either side) renders
		-- or animates. Five full canvases of frames animating at once is pure waste
		-- when four of them are hundreds of studs off screen.
		local near = forceAll or (camY < p.y0 + C.NEAR and camY > p.y1 - C.NEAR)
		if p.gui.Enabled ~= near then p.gui.Enabled = near end
		if near and p.fx then animate(p.fx, t, dt) end
	end
	publishStratum(camY, currentZone())
end)

----------------------------------------------------------------------
-- zone travel + dev hook
----------------------------------------------------------------------
rebuild(currentZone())
plr:GetAttributeChangedSignal("CurrentZone"):Connect(function() rebuild(currentZone()) end)

-- Same dev-hook convention as DevZone / DevRoll / DevDiscover: MCP cannot click,
-- and the deep strata are hundreds of studs down where no screenshot reaches.
--   :Fire("__ALL__")  render every stratum at once (for capture)
--   :Fire("__CULL__") resume normal culling
--   :Fire(<zoneId>)   rebuild the column with that zone's themes
local col = workspace:WaitForChild("DepthColumn")
local dev = col:FindFirstChild("DevStrata") or mk("BindableEvent", { Name = "DevStrata" }, col)
dev.Event:Connect(function(arg)
	if arg == "__ALL__" then forceAll = true
	elseif arg == "__CULL__" then forceAll = false
	elseif type(arg) == "number" then rebuild(arg) end
end)

print(string.format("[DepthStrata] online - %d strata, zone %d (%s -> %s), column 0..%d",
	#planes, currentZone(), LINEUP[currentZone()][1].name,
	LINEUP[currentZone()][#STRATA].name, C.BOT))
