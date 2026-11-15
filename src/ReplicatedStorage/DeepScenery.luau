--[[
	DeepScenery - the water column as REAL 3D GEOMETRY.

	The previous DepthStrata painted all five underwater bands onto flat SurfaceGui
	panels. This builds them out of actual anchored Parts spread across Z, which buys
	four things a painted plane cannot have:

	  * real vertical parallax. The camera only ever moves in Y (GameClient pins it to
	    x=0, z=+dist), so sinking past geometry at different Z genuinely separates it.
	  * real materials. Basalt / CrackedLava / Glacier / Slate carry surface detail that
	    a flat Frame has to fake with noise.
	  * real occlusion - a near stalk actually passes in front of a far one.
	  * DEPTH FOG. Lighting.FogColor is driven from the band's water colour, so distance
	    dissolves into the water instead of being hand-painted. This is the single
	    biggest reason the 3D version reads as underwater.

	CAMERA CONTRACT (mirrors GameClient - do not drift from it):
	  PLAY_Z = 0, CAM_FOV = 20, camera distance clamped to MAX_CAM_DIST = 140, x = 0.
	  So at world Z the visible half-height is (140 - z) * tan(10 deg) and the half-width
	  is that times the aspect. halfW/halfH below are the only place that maths lives.

	THE THREE RULES PAID FOR BY THE PAINTED VERSION, still true in 3D:
	  1. The middle 60% of the frame is all the player can see - BaitRoller owns the left
	     of the screen and MainMenu the right. Hero features go inside |x| < 0.6 * halfW.
	  2. Rock reads by being DARKER than the water, never lighter. Distance underwater is
	     darker and hazier; anything that recedes toward a lighter tone renders as pale
	     slabs floating in the middle of the frame.
	  3. The throat stays open. Walls hug the edges; the centre column is water, because
	     that is where the hook and the fish actually are.

	Nothing in here may enter the play plane: the hook, the line and 46-96 live fish all
	live at z = 0. Z_NEAR is the closest any scenery gets.
--]]

local M = {}

----------------------------------------------------------------------
-- the column
----------------------------------------------------------------------
M.BOT = -660          -- column floor; GameClient's deepest band ends at -620

M.BANDS = {
	{ key = "shallows", y0 = 0,    y1 = -70  },
	{ key = "kelp",     y0 = -70,  y1 = -190 },
	{ key = "cavern",   y0 = -190, y1 = -330 },
	{ key = "glow",     y0 = -330, y1 = -470 },
	{ key = "trench",   y0 = -470, y1 = -660 },
}

-- Z layers. Everything is built at one of these depths (plus jitter) so the parallax
-- separates into readable planes instead of mush.
local Z_NEAR = -20    -- big dark framing silhouettes, edges only
local Z_MID  = -58    -- the main structures - this is where the scene lives
local Z_FAR  = -128   -- hazy massifs, mostly eaten by fog
local Z_MURK = -250   -- the backdrop wall; fully fogged, exists only to hide the sky
-- ...and a NEAR backdrop sheet, just in front of the painted surface panels at -45.
-- See the NearMurk note in M.build for why the far wall cannot do this job.
local Z_SKIRT = -42
M.Z_NEAR, M.Z_MID, M.Z_FAR, M.Z_MURK = Z_NEAR, Z_MID, Z_FAR, Z_MURK
M.Z_SKIRT = Z_SKIRT

local TAN_HALF = math.tan(math.rad(10))   -- CAM_FOV 20 / 2
local CAM_Z    = 140                      -- MAX_CAM_DIST; the clamp always bites here

function M.halfH(z) return (CAM_Z - z) * TAN_HALF end
-- ⚠️ TWO DIFFERENT HALF-WIDTHS, AND USING THE WRONG ONE COSTS YOU THE WHOLE SIDE OF THE
-- FRAME. The first pass built everything against a wide 2.1 aspect, so on an ordinary
-- 16:9 screen both canyon walls sat entirely off-camera and the shot was empty water
-- with one feature floating in it.
--   halfW  = the NARROW frame - guaranteed visible on every screen. Anything that has
--            to be SEEN is placed inside this.
--   wideW  = the widest frame anyone will have. Anything that has to COVER an edge
--            (walls, ceilings, floors) must extend out to here or ultrawide players
--            see past it.
function M.halfW(z, aspect) return M.halfH(z) * (aspect or 1.62) end
function M.wideW(z) return M.halfH(z) * 2.25 end
-- ⚠️ AND A THIRD ONE. BaitRoller owns the left of the screen and MainMenu the right, so
-- only about the middle HALF of the frame is ever actually seen. Rock parked at 0.65 of
-- halfW is behind the HUD - correct for framing, useless as content. Hero features go
-- inside clearW; walls aim their inner edge AT it so they just peek past the panels.
function M.clearW(z) return M.halfW(z) * 0.52 end

----------------------------------------------------------------------
-- palette
----------------------------------------------------------------------
local function h(n)
	return Color3.fromRGB(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
end
M.hex = h

-- name, builder kind, water top / bottom, rock, accent, glow
local function z(name, kind, top, bot, rock, accent, glow)
	return { name = name, kind = kind, top = h(top), bot = h(bot), rock = h(rock),
		accent = h(accent), glow = glow and h(glow) or nil }
end

-- Each zone runs a DIFFERENT SEQUENCE OF PLACES, not the same five recoloured - `kind`
-- picks the builder, so the silhouettes differ and not just the palette. Water ramps are
-- carried over from the tuned painted version; zone 6 is lifted (see below).
M.LINEUP = {
	[1] = { -- Lighthouse Cove: temperate ocean. Kelp forest, then a sea cave.
		z("Sunlit Shallows",  "shallows", 0x84EEF7, 0x28A2DE, 0x34505C, 0xCEFAFF),
		z("Kelp Forest",      "kelp",     0x28A2DE, 0x126096, 0x243C46, 0x2E9660),
		z("Sunken Cavern",    "cavern",   0x126096, 0x0A2C56, 0x1E2C3A, 0x3A4C60, 0x60BEDC),
		z("Glowfield",        "glow",     0x0A2C56, 0x051430, 0x101A2E, 0x3C5A82, 0x78DCFF),
		z("Abyssal Trench",   "trench",   0x051430, 0x07142E, 0x141C30, 0x2E3C58, 0x96E2FF),
	},
	[2] = { -- Tropical Reef: a coral garden, then a wreck, then the drop-off
		z("Coral Shallows",   "shallows", 0x96F0E6, 0x40CEC4, 0xC8AE86, 0xD6FFFA),
		z("Coral Garden",     "coral",    0x40CEC4, 0x1A9696, 0xC0A67E, 0xFF8C78, 0xFFD24A),
		z("The Wreck",        "wreck",    0x1A9696, 0x0A5C66, 0x3A2E24, 0x6E5A46, 0x78FFEB),
		z("The Blue Hole",    "bluehole", 0x0A5C66, 0x043A44, 0x0E3038, 0x286E78, 0xFF78C8),
		z("Turquoise Abyss",  "trench",   0x043A44, 0x03202A, 0x0B2C34, 0x1E5460, 0x5AFFDC),
	},
	[3] = { -- Golden Sunset Bay: soft meadow, eroded arches, a jellyfish bloom
		z("Amber Shallows",   "shallows", 0xFFC884, 0xEC925C, 0x6E4434, 0xFFE4B0),
		z("Seagrass Meadow",  "seagrass", 0xEC925C, 0xB0604A, 0x5E3A2C, 0xC69642),
		z("Sandstone Arches", "arches",   0xB0604A, 0x6E343C, 0x7A4630, 0xB27450, 0xFFBE6E),
		z("Jellyfish Bloom",  "glow",     0x6E343C, 0x3E1A2E, 0x341A22, 0x6E3C3C, 0xFFAA5A),
		z("Dusk Trench",      "trench",   0x3E1A2E, 0x1C0A1C, 0x2A1422, 0x54303E, 0xFF923C),
	},
	[4] = { -- Frostbite Fjord: under the pack ice, down a crevasse, into the aurora
		z("Ice Shallows",     "shallows", 0xD0ECF8, 0x9CCEE6, 0x8AA8BC, 0xF4FCFF),
		z("Under the Ice",    "iceshelf", 0x9CCEE6, 0x609EC4, 0xBEDCF0, 0xEAF7FF),
		z("Glacier Crevasse", "crevasse", 0x609EC4, 0x2C608E, 0x5A8CAC, 0xA8D6EE, 0xB4F0FF),
		z("Aurora Field",     "aurora",   0x2C608E, 0x14385E, 0x18344E, 0x3C6E96, 0x78FFD2),
		z("Frozen Trench",    "trench",   0x14385E, 0x08182E, 0x152A44, 0x315878, 0xA0E6FF),
	},
	[5] = { -- Midnight Trench: a whale fall, black spires, then the bloom
		z("Moonlit Shallows", "shallows", 0x22466C, 0x163254, 0x0C1422, 0x8AC4EC),
		z("Whale Fall",       "whalefall",0x163254, 0x0C203A, 0x141A28, 0xC8D2E0),
		z("Obsidian Spires",  "spires",   0x0C203A, 0x061226, 0x080C16, 0x141C2E, 0x4696FF),
		z("Bioluminescence",  "glow",     0x061226, 0x020816, 0x060A14, 0x182846, 0x78FFF0),
		z("The Deep Dark",    "trench",   0x020816, 0x030A18, 0x0C1220, 0x1E2840, 0x96E2FF),
	},
	-- ⚠️ ZONE 6 IS LIFTED off the old values. The painted version ran water down to
	-- rgb(30,8,5) with rock at rgb(28,14,12) - both effectively black, so the basalt
	-- never silhouetted and the whole volcano read as an unlit smear. Water is warmer
	-- and brighter at every band and the rock is pushed clear of it, which is what lets
	-- the molten neon actually sit on something.
	[6] = { -- Molten Abyss: a drowned burnt forest, lava tubes, embers, a magma trench
		z("Ash Shallows",     "shallows", 0xEC7A3E, 0xBE5024, 0x3A241C, 0xFFBC76),
		z("Charred Stumps",   "charred",  0xBE5024, 0x8A3A1A, 0x2A1A16, 0x542A18, 0xFF6A18),
		z("Lava Tubes",       "tubes",    0x8A3A1A, 0x5A240F, 0x241614, 0x3C221A, 0xFF8228),
		z("Ember Field",      "embers",   0x5A240F, 0x42190C, 0x1E1210, 0x462016, 0xFFA03C),
		-- ⚠️ The trench floor is lifted well off black ON PURPOSE. At rgb(38,14,7) the water
		-- and the rock were both effectively black, the ambient derived from it was darker
		-- still, and the deepest band in the game rendered as an empty dark rectangle.
		z("Magma Trench",     "trench",   0x42190C, 0x35130A, 0x2A1810, 0x4A2618, 0xFF781E),
	},
}

function M.theme(zid, i) return (M.LINEUP[zid] or M.LINEUP[1])[i] end

----------------------------------------------------------------------
-- primitives
--
-- Everything is Anchored / CanCollide=false / CanQuery=false. CanQuery matters more
-- than it looks: GameClient raycasts around the hook, and a rock wall that answers a
-- raycast would silently become fishable geometry.
----------------------------------------------------------------------
local rng = Random.new()
local function rr(a, b) return a + rng:NextNumber() * (b - a) end
local function pick(t) return t[rng:NextInteger(1, #t)] end
M.rr, M.pick = rr, pick

local function dark(c, k) return c:Lerp(Color3.new(0, 0, 0), k) end
local function lite(c, k) return c:Lerp(Color3.new(1, 1, 1), k) end
M.dark, M.lite = dark, lite

----------------------------------------------------------------------
-- BACKDROP RESTRAINT - the one place the scenery's loudness is dialled
--
-- The column is scenery. The GAME is 46-96 fish and a hook, all of them at z = 0,
-- all of them small, and all of them in the middle of the frame. Built at full
-- contrast the backdrop wins that fight every time - measured off the live scene:
-- the kelp forest put 383 of its 634 parts inside the clear window and 188 of them
-- in the fish's own lane, the glowfield ran 96 emissive parts out of 192, and the
-- trench rendered its rock BRIGHTER than the water it stands in (rule 2, inverted).
--
-- The levers, in order of how much they do:
--   haze     every part is lerped toward the WATER COLOUR by distance. That is what
--            water actually does to contrast, so it costs nothing stylistically and
--            it is the main knob. hazeNear applies even at the front plane: nothing
--            is exempt, because the near framing rock was shouting too.
--   throat   whatever still ends up in the fish's lane recedes HARDER than the
--            wings, so the middle of the frame reads as depth rather than as stuff.
--   hole     scatter is biased off the centre line at BUILD time (M.ux), so less
--            lands there to begin with.
--   fogReach multiplies FogEnd. THE FISH TAKE NO FOG AT ALL - they sit 140 studs
--            out and FogStart is 150 - so this dissolves the scenery without
--            touching them. Nothing else in the rig separates figure from ground
--            anywhere near as cleanly; reach for it before reaching for haze.
-- glowDim / lightDim / fx* handle the emissive kit, which is the loudest thing on
-- screen and was competing with the fish directly.
--
-- To bring the scenery forward again, lower haze*/throat/hole and raise fogReach.
-- haze/throat/hole at 0 with fogReach 1 is exactly the pre-restraint look.
----------------------------------------------------------------------
M.BACKDROP = {
	hazeNear  = 0.14,   -- lerp toward the water colour at the FRONT plane
	hazeFar   = 0.66,   -- ...and at hazeZ and beyond
	hazeZ     = -155,   -- the depth by which a part is as hazed as it gets
	hazeCurve = 0.85,   -- <1 front-loads it, so the mid plane knocks back too
	throat    = 0.26,   -- EXTRA haze at dead centre, falling off to the clear edge
	hole      = 0.30,   -- fraction of the half-frame kept clear of scattered art
	-- WARNING: THIS ONE OVERSHOOTS FAST, AND WHAT IT BREAKS IS A FEATURE, NOT A LOOK.
	-- At 0.46 (plus the depth term below) the Glowfield's jellies came back as dead
	-- grey blobs and the trench's vent caps and magma river vanished outright - i.e.
	-- the two bands whose entire identity is 'light in the dark' had their light
	-- turned off. Glow is not what was competing with the fish; glow at FISH SIZE in
	-- the fish's own lane was. Shrink and move it, dim it only a little.
	glowDim   = 0.24,   -- Neon darkened by this (NEVER faded - see M.glow)
	-- WARNING: THESE ARE NOT DECORATION IN THE MOLTEN AND MIDNIGHT ZONES - THEY ARE THE
	-- ONLY LIGHT IN THE BAND. Neon emits nothing, so every molten feature carries a real
	-- PointLight and they are what light the rock, the hook and the FISH as well. Cut to
	-- 0.50 the Ember Field went black and its fish went with it. What competes with the
	-- fish is the emissive kit (glowDim), not the lighting; keep this near 1.
	lightDim  = 0.88,   -- PointLight brightness multiplier
	fxRate    = 0.55,   -- ParticleEmitter rate multiplier
	fxFade    = 0.35,   -- pushed into every emitter's transparency, toward invisible
	-- WARNING: THIS STACKS WITH haze* AND THE TWO TOGETHER OVERSHOOT. At 0.70 the
	-- trench ran FogEnd 231 against a camera pullback of 150, so the mid plane sat at
	-- 59% fog on top of its colour haze and the whole band flattened to one tone with
	-- no silhouettes left in it. Haze is the better half of the pair - it recedes a
	-- shape without erasing it - so keep fog gentle and push haze if more is needed.
	fogReach  = 0.82,   -- FogEnd multiplier
}

-- A signed unit scatter, |value| in [hole, 1], biased outward. Every builder that
-- scatters art across the frame draws its x from this instead of rr(-1, 1).
-- WARNING: gentle on purpose. Emptying the centre completely is the exact failure
-- the trench spires were added to fix ("the clear window is empty water for the
-- whole 190-stud drop"), so this opens a LANE, not a hole - and M.recede does the
-- rest by pushing whatever still lands there back into the haze.
function M.ux()
	local hole = M.BACKDROP.hole
	local v = hole + (1 - hole) * rng:NextNumber() ^ 0.8
	return rng:NextNumber() < 0.5 and -v or v
end

local SMOOTH = Enum.SurfaceType.Smooth

-- ⚠️ NOTHING MAY COME NEARER THAN THIS. The hook, the line and 46-96 live fish all sit
-- at z = 0, so any scenery that reaches the play plane is in front of the game. It is
-- easy to do by accident: a "floor" written as 210 deep centred at z=-70 actually spans
-- -175..+35 and pokes 35 studs out in front of the boat. Caught in a live cast - the
-- ember field's floor and every particle volume were doing exactly that.
-- Rather than trust every call site, every primitive is pushed back here.
local Z_SAFE = -10

local function keepBehind(p)
	local s, cf = p.Size, p.CFrame
	local R, U, L = cf.RightVector, cf.UpVector, cf.LookVector
	-- world half-extent along Z (Size is not a world extent once a part is rotated)
	local ez = 0.5 * (math.abs(R.Z) * s.X + math.abs(U.Z) * s.Y + math.abs(L.Z) * s.Z)
	local front = cf.Position.Z + ez
	if front > Z_SAFE then p.CFrame = cf + Vector3.new(0, 0, Z_SAFE - front) end
	return p
end
M.Z_SAFE = Z_SAFE

local function newPart(parent, shape)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow, p.Locked = false, true
	p.TopSurface, p.BottomSurface = SMOOTH, SMOOTH
	if shape then p.Shape = shape end
	p.Parent = parent
	return p
end

-- axis-aligned (or freely oriented) block
function M.box(f, cf, size, col, mat, tr)
	local p = newPart(f)
	p.Size, p.CFrame, p.Color = size, cf, col
	p.Material = mat or Enum.Material.Slate
	if tr and tr > 0 then p.Transparency = tr end
	return keepBehind(p)
end

-- The ONE thing exempt from the guard: the sea surface. It is a horizontal sheet at y=0,
-- so it has to run right past the play plane and under the boat - that is what makes it
-- the waterline. At 0.7 studs thick it occludes nothing the player needs to see.
-- ⚠️ Must be declared AFTER `newPart`: a `local function` declared later is not in scope
-- here, so an earlier copy of this silently captured a nil GLOBAL instead.
function M.slab(f, cf, size, col, mat)
	local p = newPart(f)
	p.Size, p.CFrame, p.Color = size, cf, col
	p.Material = mat or Enum.Material.SmoothPlastic
	return p
end

-- A box rolled about Z so its corner points up: seen from the camera's +Z this is a
-- clean triangular peak, and unlike a WedgePart it needs no orientation guesswork.
-- Sink it so `y` is where the visible point sits and the base is buried.
function M.crystal(f, x, yTip, zz, w, hgt, col, mat, lean)
	-- a 45-degree roll turns a square of side s into a diamond of half-diagonal s*0.7071
	local s = hgt / 1.4142
	local p = newPart(f)
	p.Size = Vector3.new(s, s, math.max(2, w))
	p.CFrame = CFrame.new(x, yTip - hgt / 2, zz)
		* CFrame.Angles(0, rr(-0.5, 0.5), math.rad(45) + (lean or 0))
	p.Color, p.Material = col, mat or Enum.Material.Slate
	return keepBehind(p)
end

-- cylinder. Part.Shape=Cylinder puts the axis on LOCAL X, so Size is (length, d, d)
-- and the caller orients it with cf. Vertical = CFrame.Angles(0,0,rad(90)).
function M.cyl(f, cf, len, dia, col, mat, tr)
	local p = newPart(f, Enum.PartType.Cylinder)
	p.Size, p.CFrame, p.Color = Vector3.new(len, dia, dia), cf, col
	p.Material = mat or Enum.Material.Slate
	if tr and tr > 0 then p.Transparency = tr end
	return keepBehind(p)
end

-- upright cylinder (trunks, stalks, chimneys, poles). `lean` tilts it IN SCREEN, about
-- Z - a lean about X would tip it toward the camera where this framing barely shows it.
function M.post(f, x, yBase, zz, hgt, dia, col, mat, lean)
	lean = lean or 0
	return M.cyl(f, CFrame.new(x, yBase + hgt / 2, zz)
		* CFrame.Angles(0, 0, lean + math.rad(90)), hgt, dia, col, mat)
end

-- an ellipsoid. Part.Shape=Ball ignores non-uniform Size, so the mesh does the work.
function M.blob(f, pos, size, col, mat, tr)
	local p = newPart(f)
	p.Size, p.CFrame, p.Color = size, CFrame.new(pos), col
	p.Material = mat or Enum.Material.Slate
	if tr and tr > 0 then p.Transparency = tr end
	local m = Instance.new("SpecialMesh")
	m.MeshType, m.Scale = Enum.MeshType.Sphere, Vector3.new(1, 1, 1)
	m.Parent = p
	return keepBehind(p)
end

-- a cone, stacked out of narrowing cylinders. Roblox has no cone primitive and a
-- WedgePart only gives a triangle from one side; 5 segments reads as a cone from the
-- game's near-orthographic camera and stays cheap.
function M.taper(f, x, yBase, zz, hgt, dBase, col, mat, up, segs)
	-- ⚠️ 5 SEGMENTS IS A WEDDING CAKE. Side-on and near-orthographic, five stacked
	-- cylinders read as five distinct discs with visible stair-steps, not as a cone.
	-- 9 with generous vertical overlap is the point where it reads as a smooth taper.
	segs = segs or 9
	local out = {}
	for k = 1, segs do
		local t0 = (k - 1) / segs
		local d = dBase * (1 - t0 * 0.85)
		local y = yBase + (up == false and -1 or 1) * hgt * (t0 + 0.5 / segs)
		out[k] = M.cyl(f, CFrame.new(x, y, zz) * CFrame.Angles(0, 0, math.rad(90)),
			hgt / segs * 1.7, math.max(0.6, d), col, mat)
	end
	return out
end

-- A TRUE CONE / SPIKE, from two mirrored WedgeParts.
--
-- Probed rather than guessed: a default WedgePart is TALL AT +Z and slopes down toward
-- -Z (raycasting its top surface gives y = z exactly), and it is constant along X. So
-- rolling one 90 degrees about Y puts the vertical face on +X and the slope along X;
-- two mirrored halves meet at the middle and give a clean isoceles triangle to a camera
-- looking down -Z. That is a real cone silhouette in TWO parts.
--
-- ⚠️ This exists because the alternatives both failed visibly:
--   M.taper stacks cylinders, and side-on at this near-orthographic FOV the steps read
--     as a WEDDING CAKE however many segments you use.
--   M.crystal is a 45-degree roll, which always makes width EQUAL height - asking it for
--     a 46-stud shard also gives 46 studs of width, so they came out as black kites.
local function wedgePart(parent)
	local p = Instance.new("WedgePart")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow, p.Locked = false, true
	p.Parent = parent
	return p
end

function M.spike(f, x, yBase, zz, w, hgt, col, mat, lean, depth, down)
	lean = (lean or 0) + (down and math.pi or 0)
	depth = depth or math.max(2.5, w * 0.85)
	local hw = w / 2
	local base = CFrame.new(x, yBase, zz) * CFrame.Angles(0, 0, lean)
	local out = {}
	for i, s in ipairs({ 1, -1 }) do
		local p = wedgePart(f)
		-- local Z is the slope run and becomes world X after the roll; local X is depth
		p.Size = Vector3.new(depth, hgt, hw)
		p.CFrame = base * CFrame.new(-s * hw / 2, hgt / 2, 0)
			* CFrame.Angles(0, s * math.rad(90), 0)
		p.Color, p.Material = col, mat
		out[i] = keepBehind(p)
	end
	return out
end

-- kept as an alias so callers read as what they mean
function M.shard(f, x, yBase, zz, w, hgt, col, mat, lean)
	return M.spike(f, x, yBase, zz, w, hgt, col, mat, lean)
end

-- ⚠️ A NEON PART LIGHTS NOTHING. Emissive material is not a light source, so basalt
-- next to a lava flow still renders as a black cutout unless a real light is put there.
-- Shadows=false keeps these cheap and they are spatially spread (only one band is ever
-- on screen), which is the regime where Future lighting handles many lights fine.
function M.lamp(f, cf, col, bright, range)
	local host = newPart(f)
	host.Name, host.Size, host.CFrame = "Lamp", Vector3.new(1, 1, 1), cf
	host.Transparency = 1
	local pl = Instance.new("PointLight")
	pl.Color, pl.Brightness, pl.Range, pl.Shadows = col, bright or 3, range or 80, false
	pl.Parent = host
	return host, pl
end

-- ⚠️ NEON MUST STAY AT TRANSPARENCY 0. Under Future lighting any transparency on a
-- Neon part renders it near-black against a dark scene - dim it by darkening Color3,
-- never by fading it. This has cost real time in this place before.
function M.glow(f, cf, size, col, shape)
	local p = newPart(f, shape)
	p.Size, p.CFrame, p.Color = size, cf, col
	p.Material, p.Transparency = Enum.Material.Neon, 0
	return keepBehind(p)
end

-- a jagged wall of rock hugging one edge of the frame, in depth layers.
-- `reach` is the fraction of the HALF-width this wall eats. The throat between the two
-- walls is where the hook and the fish are and must stay open water - the painted
-- version doubled this by mistake, the walls met in the middle and the whole band
-- rendered as a black box.
-- `reach` is the fraction of the NARROW half-frame the wall eats inward. Each row runs
-- from that inner edge all the way OUT past the widest frame, so the wall is present
-- whatever the player's aspect ratio while the throat stays exactly as open as asked.
function M.rockWall(f, side, yTop, yBot, zz, reach, col, mat, layers)
	layers = layers or 2
	for L = 1, layers do
		local zl = zz - (L - 1) * 26
		local c  = dark(col, 0.06 + 0.13 * (layers - L))
		local hwl, outer = M.halfW(zl), M.wideW(zl) * 1.2
		local rows = 9
		for k = 1, rows do
			local y = yBot + (yTop - yBot) * ((k - 0.5) / rows) + rr(-4, 4)
			local inner = hwl * (1 - reach * rr(0.70, 1.30))
			local w = outer - inner
			local hgt = (yTop - yBot) / rows * rr(1.5, 2.4)
			local p = M.box(f, CFrame.new(side * (inner + w / 2), y, zl)
				* CFrame.Angles(rr(-0.12, 0.12), rr(-0.22, 0.22), rr(-0.18, 0.18)),
				Vector3.new(w, hgt, rr(14, 30)), c, mat)
			p.Name = "Wall"
			-- ⚠️ Nine tiled boxes make a SLAB, not a cliff. The inner edge is the only part
			-- anyone sees, so break it up with boulders that stand proud of it - without
			-- these the wall reads as one flat vertical face with a ruler-straight edge.
			if L == layers then
				for b = 1, 2 do
					-- darker than the wall behind them, or they read as pale lumps floating in
					-- the haze instead of as rock closer to the camera. Mixed round and
					-- angular: all-spheres came out as bubble wrap down the side of the frame.
					local bx = side * (inner + rr(-6, 10))
					local by = y + rr(-1, 1) * hgt * 0.5
					local bz = zl + rr(6, 18)
					local bc = dark(c, rr(0.25, 0.5))
					if rng:NextNumber() < 0.5 then
						M.blob(f, Vector3.new(bx, by, bz),
							Vector3.new(rr(9, 24), rr(7, 18), rr(9, 22)), bc, mat)
					else
						M.box(f, CFrame.new(bx, by, bz)
							* CFrame.Angles(rr(-0.5, 0.5), rr(-0.8, 0.8), rr(-0.5, 0.5)),
							Vector3.new(rr(8, 22), rr(8, 20), rr(8, 20)), bc, mat)
					end
				end
			end
		end
	end
	return side * M.halfW(zz) * (1 - reach)
end

----------------------------------------------------------------------
-- particles
--
-- Suspended matter is a ParticleEmitter, not hundreds of animated parts: it is a GPU
-- job, it survives the Heartbeat budget, and it actually drifts in 3D. Everything made
-- here is tagged so Set_Particles can switch the whole lot off.
----------------------------------------------------------------------
-- ⚠️ BOTH OF THESE ARE smoke_main ON PURPOSE. sparkles_main.dds did not resolve here and
-- ParticleEmitter silently falls back to an untextured QUAD - the ash and embers
-- rendered as hard-edged orange RECTANGLES tumbling through the frame. smoke_main is
-- confirmed working in this place; an ember is just a small one with LightEmission 1.
local TEX = {
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	spark = "rbxasset://textures/particles/smoke_main.dds",
}
M.TEX = TEX

function M.emitter(f, pos, size, opt)
	local host = newPart(f)
	host.Name = "FX"
	host.Size, host.CFrame = size, CFrame.new(pos)
	host.Transparency = 1
	keepBehind(host)
	local e = Instance.new("ParticleEmitter")
	e.Texture      = opt.tex or TEX.spark
	e.Color        = ColorSequence.new(opt.col or Color3.new(1, 1, 1))
	e.Size         = NumberSequence.new(opt.s0 or 1, opt.s1 or (opt.s0 or 1))
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, opt.tr or 0.5),
		NumberSequenceKeypoint.new(0.8, opt.tr or 0.5),
		NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime     = NumberRange.new(opt.lifeLo or 6, opt.lifeHi or 12)
	e.Rate         = opt.rate or 8
	e.Speed        = NumberRange.new(opt.spdLo or 0.4, opt.spdHi or 1.6)
	e.SpreadAngle  = Vector2.new(180, 180)
	e.Rotation     = NumberRange.new(0, 360)
	e.RotSpeed     = NumberRange.new(-12, 12)
	e.Acceleration = opt.acc or Vector3.new(0, 0.2, 0)
	e.LightEmission= opt.emit or 0.3
	e.LightInfluence = 0
	e.EmissionDirection = opt.dir or Enum.NormalId.Top
	e.ZOffset      = opt.zoff or 0
	e.Drag         = opt.drag or 0.4
	e.Parent       = host
	host:SetAttribute("IsFX", true)
	return host, e
end

----------------------------------------------------------------------
-- animation registry
--
-- One Heartbeat drives the ACTIVE band only. Keep this list small - particles do the
-- ambient motion, this is only for things whose shape has to move.
----------------------------------------------------------------------

-- rotate a stack of parts about a shared base, so a stalk bends instead of sliding
function M.sway(A, parts, pivot, amp, sp)
	local offs = {}
	for i, p in ipairs(parts) do
		offs[i] = CFrame.new(pivot):ToObjectSpace(p.CFrame)
	end
	A[#A + 1] = { k = "sway", parts = parts, offs = offs, pivot = pivot,
		amp = amp, sp = sp or rr(0.35, 0.8), ph = rr(0, 6.28) }
end

function M.bob(A, part, amp, sp)
	A[#A + 1] = { k = "bob", parts = { part }, base = part.CFrame,
		amp = amp, sp = sp or rr(0.2, 0.5), ph = rr(0, 6.28) }
end

-- breathe a Neon part between two colours. Transparency is not an option on Neon.
function M.throb(A, part, c0, c1, sp)
	A[#A + 1] = { k = "throb", parts = { part }, c0 = c0, c1 = c1,
		sp = sp or rr(0.4, 1.1), ph = rr(0, 6.28) }
end

function M.spin(A, part, sp)
	A[#A + 1] = { k = "spin", parts = { part }, base = part.CFrame,
		sp = sp or rr(0.1, 0.35) }
end

-- a partial ring: whale ribs, arches, cave mouths. Angles in radians, 0 = +X, CCW.
function M.arc(f, cx, cy, cz, radius, a0, a1, segs, thick, depth, col, mat)
	local out = {}
	for k = 1, segs do
		local a = a0 + (a1 - a0) * ((k - 0.5) / segs)
		local arcLen = math.abs(a1 - a0) * radius / segs * 1.2
		out[k] = M.box(f, CFrame.new(cx + math.cos(a) * radius, cy + math.sin(a) * radius, cz)
			* CFrame.Angles(0, 0, a + math.pi / 2),
			Vector3.new(thick, arcLen, depth), col, mat)
	end
	return out
end

-- a hollow ring of segments facing the camera - the only way to get a TUBE MOUTH you
-- can see into, since a solid cylinder reads as a flat disc from the front.
function M.ring(f, cx, cy, cz, radius, thick, depth, segs, col, mat)
	for k = 1, segs do
		local a = (k - 1) / segs * math.pi * 2
		-- 1.15 overlap so the segments actually meet. ⚠️ Do NOT tilt them about X or vary
		-- their size much: the first pass did both and the ring read as a ring of scattered
		-- flat petals - a sunflower, not a tube.
		local arc = (2 * math.pi * radius / segs) * 1.15
		local p = M.box(f,
			CFrame.new(cx + math.cos(a) * radius, cy + math.sin(a) * radius, cz)
				* CFrame.Angles(0, 0, a + math.pi / 2),
			Vector3.new(thick * rr(0.92, 1.12), arc, depth * rr(0.9, 1.1)),
			dark(col, rr(0, 0.18)), mat)
		p.Name = "Ring"
	end
end

function M.stepAnim(list, t)
	for _, e in ipairs(list) do
		if e.k == "sway" then
			local a = math.sin(t * e.sp + e.ph) * e.amp
			local m = CFrame.new(e.pivot) * CFrame.Angles(0, 0, a)
			for i, p in ipairs(e.parts) do p.CFrame = m * e.offs[i] end
		elseif e.k == "bob" then
			e.parts[1].CFrame = e.base + Vector3.new(0, math.sin(t * e.sp + e.ph) * e.amp, 0)
		elseif e.k == "throb" then
			local w = 0.5 + 0.5 * math.sin(t * e.sp + e.ph)
			e.parts[1].Color = e.c0:Lerp(e.c1, w)
		elseif e.k == "spin" then
			e.parts[1].CFrame = e.base * CFrame.Angles(0, t * e.sp, 0)
		end
	end
end

----------------------------------------------------------------------
-- materials
--
-- Real materials are half the reason this reads as 3D at all: Basalt, CrackedLava,
-- Glacier and Sandstone carry surface detail a painted Frame had to fake with noise.
----------------------------------------------------------------------
local Mat = Enum.Material
local MAT = {
	[1] = { rock = Mat.Slate,     soft = Mat.Sand,      grit = Mat.Rock },
	[2] = { rock = Mat.Limestone, soft = Mat.Sand,      grit = Mat.Sandstone },
	[3] = { rock = Mat.Sandstone, soft = Mat.Sand,      grit = Mat.Limestone },
	[4] = { rock = Mat.Glacier,   soft = Mat.Snow,      grit = Mat.Ice },
	[5] = { rock = Mat.Basalt,    soft = Mat.Mud,       grit = Mat.Rock },
	[6] = { rock = Mat.Basalt,    soft = Mat.CrackedLava, grit = Mat.Rock },
}

----------------------------------------------------------------------
-- builders - ONE PER PLACE. LINEUP.kind picks which one each zone's band runs.
----------------------------------------------------------------------
local B = {}
M.B = B

-- shorthand the builders all use
local function mid(c) return (c.y0 + c.y1) / 2 end

-- a soft shaft of light. Neon at transparency 0 (never faded - see M.glow).
--
-- WARNING: A LIGHT SHAFT HAS TO BE LIGHTER THAN THE WATER IT CROSSES, and for a long
-- time this one was not - in ANY band. It was built at dark(accent, 0.74), which in
-- the sunlit shallows is rgb(54,65,66) drawn over rgb(132,238,247) water: the "god
-- rays" were rendering as near-black BARS down the middle of the brightest, emptiest
-- band in the game, and they were the single most distracting thing on screen. Neon
-- is emissive, not additive - it renders AS its colour - so the colour has to be
-- picked against the water at that depth, which is what waterAt is for. Keep the lift
-- small: much past 0.22 and a shaft stops being atmosphere and becomes an object.
local function shaft(c, x, zz, yTop, len, wide)
-- WARNING: AND IT MUST NOT BE NEON EITHER. Lifted to lite(water, 0.22) the rays stopped
-- being black bars and became the opposite problem - Neon is emissive AND Lighting
-- carries a BloomEffect, so they blew out into hard-edged WHITE PLANKS standing in the
-- water, more object-like than the rock had been. A shaft IS a volume of slightly
-- brighter water, so build it as one: a lit sheet, tinted off the water at that depth,
-- and mostly transparent. That is also self-correcting across all 30 band/zone
-- combinations, where a hand-picked neon value would have to be right thirty times.
	local col = lite(M.waterAt(c.zid, yTop - len / 2), 0.42)
	local p = M.box(c.f, CFrame.new(x, yTop - len / 2, zz) * CFrame.Angles(0, 0, rr(-0.10, 0.10)),
		Vector3.new(wide, len, 0.4), col, Mat.SmoothPlastic, 0.74)
	p.Name = "Ray"
	return p
end

----------------------------------------------------------------------
-- 1. SHALLOWS (shared, reskinned) - open sunlit water
--
-- ⚠️ Deliberately almost empty of solids. GameClient keeps 46-96 REAL 3D fish swimming
-- in this band; the painted version put flat silhouette fish here and they read as pale
-- arrows next to the actual models. Light, the underside of the surface, and suspended
-- matter only.
----------------------------------------------------------------------
function B.shallows(c)
	local t = c.t
	-- ⚠️ No "underside of the surface" sheets here any more - the real 3D sea plane built
	-- by M.buildSurface sits at y=0 and IS the ceiling. Stacking translucent sheets a
	-- stud under it just z-fought with it.
	-- light shafts, angled and spread across depth so they cross each other
	-- WARNING: THESE MUST STAY IN FRONT OF Z_SKIRT. The shallows is deliberately almost
	-- empty of solids, so the shafts ARE its content - spread back to Z_MID/-90/Z_FAR,
	-- three fifths of them ended up behind the near backdrop sheet and simply were not
	-- there any more. -14..-40 still gives real parallax across the band.
	for k = 1, 9 do
		local zz = pick({ -14, Z_NEAR, -26, -34, -40 })
		shaft(c, M.ux() * M.halfW(zz) * 0.9, zz, -1, rr(38, 66), rr(1.6, 4.4))
	end
	-- ⚠️ NO "hint of the seabed below" here. Ellipsoid masses parked at the band floor
	-- read as smooth brown pancakes hanging in clear water, and worse, they hang over the
	-- TOP of whatever the next band builds. The shallows is open water; leave it open.
	M.emitter(c.f, Vector3.new(0, mid(c), -60), Vector3.new(180, c.H, 150),
		{ col = lite(t.accent, 0.2), rate = 26, s0 = 0.5, s1 = 0.9, tr = 0.55,
		  spdLo = 0.2, spdHi = 1.0, lifeLo = 8, lifeHi = 16, emit = 0.6,
		  acc = Vector3.new(0.15, 0.1, 0) })
end

----------------------------------------------------------------------
-- 4. GLOWFIELD (shared) - bioluminescent jellies in the dark
----------------------------------------------------------------------
function B.glow(c)
	local t = c.t
	local g = t.glow or t.accent
	for _, side in ipairs({ -1, 1 }) do
		M.rockWall(c.f, side, c.y0, c.y1, Z_MID, 0.30, t.rock, c.mat.rock, 2)
	end
	-- WARNING: HALF THIS BAND WAS EMISSIVE - 96 Neon parts out of 192, at full
	-- brightness, at fish scale, in the fish's own lane. Worse, GameClient's Shiny /
	-- Gold fish variants glow too, so a jelly and a rare catch read as the same event.
	-- Fewer and smaller here; M.recede dims what is left.
	for k = 1, 11 do
		local zz = pick({ Z_NEAR, -34, Z_MID, -80, Z_FAR })
		local sc = zz > -50 and rr(0.85, 1.3) or rr(0.55, 0.95)
		local x  = M.ux() * M.halfW(zz) * 0.78
		local y  = rr(c.y1 + 12, c.y0 - 12)
		local bell = M.blob(c.f, Vector3.new(x, y, zz),
			-- the bell is an ENVELOPE around the core, not a mass. At 0.45 it read as a
			-- solid pale blob the size of a fish once M.recede lerped it toward the water.
			Vector3.new(9 * sc, 7 * sc, 9 * sc), lite(g, 0.25), Mat.SmoothPlastic, 0.58)
		local core = M.glow(c.f, CFrame.new(x, y - 1 * sc, zz),
			Vector3.new(5.5 * sc, 3.4 * sc, 5.5 * sc), g)
		-- WARNING: M.glow MAKES A BLOCK. Behind a bell at 0.45 that never showed, but at
		-- 0.58 the core reads straight through as a hard-edged neon RECTANGLE - UI debris
		-- floating in the water, not a creature. Same fix M.blob uses: a Sphere
		-- SpecialMesh, which (unlike Shape = Ball) respects a non-uniform Size.
		local cmesh = Instance.new("SpecialMesh")
		cmesh.MeshType = Enum.MeshType.Sphere
		cmesh.Parent = core
		local tent = {}
		for j = 1, 5 do
			local a = (j / 5) * math.pi * 2
			tent[j] = M.box(c.f, CFrame.new(x + math.cos(a) * 2.6 * sc,
				y - rr(6, 11) * sc, zz + math.sin(a) * 2.6 * sc),
				Vector3.new(0.5 * sc, rr(10, 20) * sc, 0.5 * sc), dark(g, 0.35), Mat.Neon)
		end
		tent[#tent + 1] = bell
		tent[#tent + 1] = core
		M.sway(c.A, tent, Vector3.new(x, y + 4 * sc, zz), rr(0.05, 0.13), rr(0.3, 0.6))
		M.throb(c.A, core, dark(g, 0.5), g, rr(0.4, 0.9))
	end
	-- a few dead-still spires so the jellies have something to drift PAST
	for k = 1, 7 do
		local zz = rr(-140, -70)
		M.crystal(c.f, M.ux() * M.halfW(zz) * 0.85, rr(c.y1 + 30, c.y1 + 90), zz,
			rr(8, 18), rr(30, 70), dark(t.rock, 0.15), c.mat.rock)
	end
	M.emitter(c.f, Vector3.new(0, mid(c), -60), Vector3.new(190, c.H, 160),
		{ col = g, rate = 34, s0 = 0.35, s1 = 0.7, tr = 0.35, spdLo = 0.3, spdHi = 1.4,
		  lifeLo = 7, lifeHi = 15, emit = 1, acc = Vector3.new(0, 0.35, 0) })
end

----------------------------------------------------------------------
-- 5. TRENCH (shared) - the canyon floor, where the column bottoms out
--
-- ⚠️ A maxed cast only reaches about -620 against a floor at -645, so anything built ON
-- the floor is barely ever seen. The walls run the FULL height of the band and carry
-- ledges, so something is always within a screen of you.
----------------------------------------------------------------------
function B.trench(c)
	local t = c.t
	local g = t.glow or t.accent
	local FLOOR = -645
	for _, side in ipairs({ -1, 1 }) do
		M.rockWall(c.f, side, c.y0 + 10, FLOOR, Z_MID, 0.40, t.rock, c.mat.rock, 2)
		M.rockWall(c.f, side, c.y0 + 10, FLOOR, -30, 0.20, dark(t.rock, 0.45), c.mat.rock, 1)
		-- ⚠️ LEDGES GO AT THE HUD EDGE, NOT AT THE WALL. Hung at 0.62-0.80 of halfW every
		-- one of them sat behind a HUD panel, so a band whose whole point is "something lit
		-- is always within a screen of you" showed an empty brown middle instead.
		for k = 1, 7 do
			local y  = FLOOR + (c.y0 - FLOOR) * ((k - 0.4) / 7.2)
			local zz = pick({ Z_MID, -78, -46 })
			local lx = side * M.clearW(zz) * rr(0.72, 1.12)
			M.box(c.f, CFrame.new(lx, y, zz) * CFrame.Angles(0, rr(-0.3, 0.3), rr(-0.12, 0.12)),
				Vector3.new(rr(20, 38), rr(3, 6), rr(16, 28)), dark(t.rock, 0.1), c.mat.rock)
			M.vent(c, lx - side * rr(2, 8), y + 2, zz, rr(6, 12), g)
		end
	end
	-- SPIRES rising out of the dark through the middle of the band. Without these the
	-- clear window is empty water for the whole 190-stud drop - the floor is at -645 but
	-- a maxed cast only ever reaches about -620, so floor detail alone is never seen.
	for k = 1, 7 do
		local zz = rr(-135, -40)
		local hgt = rr(110, 240)
		M.spike(c.f, M.ux() * M.clearW(zz) * 1.15, FLOOR + rr(-10, 30), zz,
			rr(14, 34), hgt, dark(t.rock, rr(0.1, 0.4)), c.mat.rock, rr(-0.09, 0.09))
	end
	-- the floor, a far massif, and glow low down so the bottom of the world has a colour
	M.box(c.f, CFrame.new(0, FLOOR - 8, -70), Vector3.new(360, 16, 220),
		dark(t.rock, 0.2), c.mat.grit)
	for k = 1, 9 do
		M.spike(c.f, rr(-1, 1) * 150, FLOOR + rr(10, 60), rr(-175, -110),
			rr(30, 70), rr(90, 200), dark(t.rock, 0.3), c.mat.rock)
	end
	for k = 1, 6 do
		M.vent(c, M.ux() * M.clearW(-60) * 1.3, FLOOR + 6, rr(-95, -40), rr(10, 18), g)
	end
	-- a magma river along the canyon floor, and it is the band's main LIGHT source as
	-- well as its main colour - the deepest band has to be lit by what is IN it
	local river = M.glow(c.f, CFrame.new(0, FLOOR + 2, -66), Vector3.new(300, 3, 34),
		dark(g, 0.16))
	M.throb(c.A, river, dark(g, 0.42), dark(g, 0.02), 0.22)
	for k = -2, 2 do
		M.lamp(c.f, CFrame.new(k * 60, FLOOR + 22, -60), g, 2.6, 165)
	end
	M.emitter(c.f, Vector3.new(0, mid(c), -60), Vector3.new(200, c.H, 170),
		{ col = lite(g, 0.1), rate = 22, s0 = 0.4, s1 = 0.8, tr = 0.5, spdLo = 0.2, spdHi = 0.9,
		  lifeLo = 9, lifeHi = 18, emit = 0.7, acc = Vector3.new(0, 0.25, 0) })
end

-- a hydrothermal vent: a cone of chimney rock with a lit throat and a plume.
-- Used by the trench everywhere and by the volcano's ember field.
function M.vent(c, x, yBase, zz, size, g)
	M.spike(c.f, x, yBase, zz, size * 1.5, size * 2.2, dark(c.t.rock, 0.25), c.mat.rock,
		rr(-0.06, 0.06), size * 1.3)
	-- a molten DOME in the throat. A flat neon box on top read as a yellow sticky note
	-- pasted on the cone.
	-- sunk INTO the cone's throat and dimmed. Sitting proud of the tip at full neon it
	-- read as a bright yellow ball balanced on a triangle.
	-- ⚠️ It has to FIT INSIDE the cone at the height you put it. A dome wider than the
	-- cone's cross-section there pokes out both sides as an orange half-circle stuck on
	-- the tip. The cone tapers to 0.15 of its base width, so this sits at 0.79 height and
	-- is only just narrower than the rock around it.
	local cap = M.blob(c.f, Vector3.new(x, yBase + size * 1.75, zz),
		Vector3.new(size * 0.30, size * 0.22, size * 0.30), dark(g, 0.22), Enum.Material.Neon)
	cap.Transparency = 0
	M.throb(c.A, cap, dark(g, 0.55), g, rr(0.5, 1.2))
	M.lamp(c.f, CFrame.new(x, yBase + size * 2.4, zz + 6), g, 1.8, size * 3 + 26)
	M.emitter(c.f, Vector3.new(x, yBase + size * 2.4, zz), Vector3.new(2, 2, 2),
		{ tex = TEX.smoke, col = lite(g, 0.5), rate = 5, s0 = size * 0.5, s1 = size * 2.2,
		  tr = 0.72, spdLo = 3, spdHi = 7, lifeLo = 3.5, lifeHi = 7, emit = 0.5,
		  acc = Vector3.new(0, 5, 0), drag = 1.2 })
	return cap
end

----------------------------------------------------------------------
-- ZONE 6 - THE MOLTEN ABYSS
--
-- The painted version of this zone was the worst-looking thing in the game: near-black
-- rock on near-black water with a few orange smears. The whole fix is contrast, and in
-- 3D it comes for free - Basalt against CrackedLava against emissive Neon, with the
-- fog carrying the warm murk that used to have to be painted in.
----------------------------------------------------------------------

-- Glowing fissures BEDDED IN A SPECIFIC PART. ⚠️ Scattering these around a loose
-- coordinate produced exactly what it sounds like - a handful of bright orange sticks
-- hanging in open water with no rock behind them, which reads as UI debris, not heat.
-- Take the part, sit them on the face of it that points at the camera.
local function cracksOn(c, host, n, g, len)
	-- ⚠️ Size is NOT world extent for a rotated part, and half the rock in here is a
	-- rolled crystal or a cylinder (whose Size.Y is a DIAMETER, not a height). Use the
	-- real world AABB or the cracks bunch up in the middle of a 60-stud spire.
	local s, cf = host.Size, host.CFrame
	local R, U, L = cf.RightVector, cf.UpVector, cf.LookVector
	local ex = 0.5 * (math.abs(R.X) * s.X + math.abs(U.X) * s.Y + math.abs(L.X) * s.Z)
	local ey = 0.5 * (math.abs(R.Y) * s.X + math.abs(U.Y) * s.Y + math.abs(L.Y) * s.Z)
	local ez = 0.5 * (math.abs(R.Z) * s.X + math.abs(U.Z) * s.Y + math.abs(L.Z) * s.Z)
	local p0 = cf.Position
	-- ⚠️ A CRACK MUST FIT THE THING IT IS ON. Fixed 10-stud bars at up to 74 degrees of
	-- roll, stuck on 3-stud-wide trunks, hung right off the sides - the frame filled with
	-- bright orange sticks floating in open water. Length is capped against the host's
	-- own height and the roll is kept near-parallel to its long axis.
	local maxLen = math.clamp(math.min(len or 9, ey * 0.55), 1.5, 14)
	local wide = math.clamp(ex * 0.30, 0.25, 1.1)
	for k = 1, n do
		local p = M.glow(c.f, CFrame.new(p0.X + rr(-ex, ex) * 0.55,
			p0.Y + rr(-ey, ey) * 0.75, p0.Z + ez + 0.5)
			* CFrame.Angles(0, 0, rr(-0.38, 0.38)),
			Vector3.new(wide * rr(0.7, 1.3), maxLen * rr(0.45, 1.0), 0.7),
			dark(g, rr(0.34, 0.66)))
		p.Name = "Crack"
		if k % 3 == 0 then M.throb(c.A, p, dark(g, 0.82), dark(g, 0.28), rr(0.25, 0.7)) end
	end
end

-- 2. CHARRED STUMPS (-70..-190) - a drowned forest that burned before it drowned
function B.charred(c)
	local t, g = c.t, c.t.glow
	local LAYERS = { { z = -26, s = 1.35, d = 0.55 }, { z = -44, s = 1.05, d = 0.34 },
		{ z = Z_MID, s = 0.85, d = 0.16 }, { z = -92, s = 0.62, d = 0.04 },
		{ z = -124, s = 0.45, d = 0.0 } }
	for _, L in ipairs(LAYERS) do
		local hw = M.halfW(L.z)
		local n  = L.z > -45 and 6 or 12
		for k = 1, n do
			-- near trunks are pushed OUT to the edges: a big black trunk through the middle
			-- of the frame would sit right on top of the hook and the fish.
			local x = (L.z > -45)
				and (rr(0.55, 1.0) * hw * (k % 2 == 0 and 1 or -1))
				or  (rr(-0.95, 0.95) * hw)
			-- tall and THIN. Burnt trunks read by their slenderness; the first pass ran up
			-- to 14 studs across and they came out as stubby pillars, not dead trees.
			local hgt  = rr(70, 150) * L.s
			local dia  = rr(2.4, 5.5) * L.s
			local base = c.y1 - rr(0, 26)
			local col  = dark(t.rock, L.d)
			local lean = rr(-0.16, 0.16)
			local trunk = M.post(c.f, x, base, L.z, hgt, dia, col, Mat.Basalt, lean)
			trunk.Name = "Stump"
			-- ⚠️ A SPLINTERED TOP MUST BE SMALL. M.crystal is a rolled square, so it is as
			-- WIDE as it is tall - asking for dia*4.5 of height put a 40-stud diamond on top
			-- of a 9-stud trunk and the forest rendered as a field of giant kites.
			for sp = 1, 2 do
				M.crystal(c.f, x + math.sin(lean) * -hgt + rr(-1, 1) * dia,
					base + hgt + dia * rr(0.3, 1.1), L.z + rr(-2, 2),
					dia * rr(0.5, 0.9), dia * rr(0.9, 1.9), col, Mat.Basalt, lean + rr(-0.4, 0.4))
			end
			for b = 1, rng:NextInteger(0, 2) do
				local by = base + hgt * rr(0.45, 0.9)
				local dir = b % 2 == 0 and 1 or -1
				M.cyl(c.f, CFrame.new(x + dir * dia * 1.6, by, L.z + rr(-3, 3))
					* CFrame.Angles(0, rr(-0.5, 0.5), dir * rr(0.3, 0.8)),
					rr(7, 16) * L.s, dia * rr(0.25, 0.4), col, Mat.Basalt)
			end
			-- the fire is still in the roots
			if L.z > -70 then cracksOn(c, trunk, 4, g, 10) end
		end
	end
	-- the forest floor, well below the frame, hot
	M.box(c.f, CFrame.new(0, c.y1 - 22, -74), Vector3.new(340, 26, 210), dark(t.rock, 0.15),
		Mat.CrackedLava)
	for k = 1, 7 do
		local zz = rr(-90, -34)
		local r = M.crystal(c.f, M.ux() * M.clearW(zz), c.y1 + rr(4, 20), zz,
			rr(9, 20), rr(12, 30), dark(t.rock, rr(0, 0.2)), Mat.Basalt, rr(-0.3, 0.3))
		cracksOn(c, r, 4, g, 8)
	end
	-- charred logs adrift in the current
	for k = 1, 6 do
		local zz = rr(-110, -26)
		local lg = M.cyl(c.f, CFrame.new(M.ux() * M.halfW(zz) * 0.8, rr(c.y1 + 20, c.y0 - 15), zz)
			* CFrame.Angles(rr(-0.4, 0.4), rr(-0.6, 0.6), rr(-0.35, 0.35)),
			rr(14, 30), rr(2.4, 4.5), dark(t.rock, 0.25), Mat.Basalt)
		M.bob(c.A, lg, rr(1.5, 4), rr(0.15, 0.35))
	end
	-- ash, falling. Negative Y acceleration is what tells you this stuff is DEAD, as
	-- against the embers below which rise.
	M.emitter(c.f, Vector3.new(0, c.y0 + 10, -64), Vector3.new(210, 8, 180),
		{ tex = TEX.smoke, col = lite(t.rock, 0.30), rate = 30, s0 = 0.6, s1 = 1.5, tr = 0.62,
		  spdLo = 0.4, spdHi = 1.6, lifeLo = 16, lifeHi = 26, emit = 0.1,
		  acc = Vector3.new(0.4, -1.1, 0), dir = Enum.NormalId.Bottom, drag = 0.9 })
	M.emitter(c.f, Vector3.new(0, mid(c), -60), Vector3.new(200, c.H, 170),
		{ col = g, rate = 12, s0 = 0.3, s1 = 0.55, tr = 0.4, spdLo = 0.3, spdHi = 1.2,
		  lifeLo = 6, lifeHi = 12, emit = 1, acc = Vector3.new(0, 1.1, 0) })
end

-- 3. LAVA TUBES (-190..-330) - basalt plumbing, still running
function B.tubes(c)
	local t, g = c.t, c.t.glow
	local cy = mid(c) + 6
	-- THE HERO: a tube bored into the dark, receding rings with molten light at the end.
	-- Left of centre so it lands in the clear window between the HUD panels.
	-- ⚠️ SCALE. The first pass used radius 28 at z=-72 and the mouth ate the entire frame
	-- - at a 20-degree FOV the half-width down there is only ~65 studs. A hero feature
	-- wants about a THIRD of the clear window, not all of it.
	local HX = -18
	M.ring(c.f, HX, cy, -84,  17,   5,   26, 20, t.rock, Mat.Basalt)
	M.ring(c.f, HX, cy, -108, 13.5, 4.5, 22, 18, dark(t.rock, 0.18), Mat.Basalt)
	M.ring(c.f, HX, cy, -130, 10.5, 4,   18, 16, dark(t.rock, 0.36), Mat.Basalt)
	-- a DISC, not a box: a square of neon at the end of a round tube reads as a button
	-- ⚠️ Part.Shape=Cylinder puts the axis on LOCAL X, so an unrotated cylinder is a disc
	-- facing sideways - edge-on to this camera it renders as a thin vertical BAR. Turn
	-- the axis to face the camera.
	local eye = M.cyl(c.f, CFrame.new(HX, cy, -146) * CFrame.Angles(0, math.rad(90), 0),
		3, 15, dark(g, 0.06), Mat.Neon)
	eye.Transparency = 0
	M.throb(c.A, eye, dark(g, 0.4), g, 0.32)
	M.lamp(c.f, CFrame.new(HX, cy, -120), g, 4, 110)
	-- ⚠️ Heat goes ON THE RING, not across the hole. Scattering cracks about the tube's
	-- AXIS put a handful of loose orange sticks hanging in the middle of the mouth.
	for k = 1, 14 do
		local a = rr(0, 6.283)
		local rad = 17 * rr(0.86, 1.12)
		-- the ring at z=-84 is 26 deep, so it spans -71..-97: put these on its FRONT lip
		-- or they are buried inside the rock and render nothing
		local p = M.glow(c.f, CFrame.new(HX + math.cos(a) * rad, cy + math.sin(a) * rad, -69)
			* CFrame.Angles(0, 0, a + math.pi / 2 + rr(-0.4, 0.4)),
			Vector3.new(rr(0.5, 1.2), rr(3, 8), 1), dark(g, rr(0.15, 0.5)))
		if k % 4 == 0 then M.throb(c.A, p, dark(g, 0.75), g, rr(0.3, 0.8)) end
	end
	-- molten spilling out of the mouth. Two thin offset streaks, not one wide bar - a
	-- single fat rectangle of flat neon reads as a UI element pasted over the scene.
	-- it runs out of the BOTTOM LIP and down, so it never crosses the mouth
	for s = 1, 2 do
		local sx = HX + rr(-7, 7)
		local spill = M.glow(c.f, CFrame.new(sx, cy - 20 - rr(22, 34), -80)
			* CFrame.Angles(0, 0, rr(-0.09, 0.09)),
			Vector3.new(rr(1.2, 2.4), rr(40, 66), 3), dark(g, rr(0.42, 0.62)))
		M.throb(c.A, spill, dark(g, 0.72), dark(g, 0.3), rr(0.4, 0.7))
	end
	M.emitter(c.f, Vector3.new(HX, cy - 62, -78), Vector3.new(16, 4, 10),
		{ col = lite(g, 0.4), rate = 26, s0 = 0.5, s1 = 1.4, tr = 0.3, spdLo = 2, spdHi = 7,
		  lifeLo = 3, lifeHi = 7, emit = 1, acc = Vector3.new(0, 6, 0), drag = 1 })

	-- columnar jointing: bundles of hexagonal basalt posts, the signature volcanic form
	for _, side in ipairs({ -1, 1 }) do
		for cl = 1, 3 do
			-- ⚠️ Nothing at Z_NEAR down the sides: at 20 studs behind the play plane a
			-- single trunk is enormous on screen, and the first pass put an 11-stud black
			-- one straight across the clear window. Thinner, and further back.
			local zz = pick({ -34, -52, Z_MID })
			local bx = side * M.halfW(zz) * rr(0.66, 1.05)
			for k = 1, rng:NextInteger(5, 8) do
				local pst = M.post(c.f, bx + rr(-12, 12), c.y1 + rr(-30, 10), zz + rr(-12, 12),
					rr(50, 150), rr(3.5, 7.5), dark(t.rock, rr(0, 0.3)), Mat.Basalt,
					rr(-0.07, 0.07))
				if k % 3 == 0 then cracksOn(c, pst, 3, g, 12) end
			end
		end
		-- a lavafall down the wall face. ⚠️ At z=-50 and 6 studs wide this was a 70-PIXEL
		-- SOLID ORANGE BAR up the side of the screen - flat, saturated, and reading as a UI
		-- element rather than as molten rock. Narrow, dim, and set back onto the wall.
		local lz = -72
		local lx = side * M.clearW(lz) * rr(0.95, 1.15)
		-- ⚠️ A 2-stud-wide bar running the full height of the band reads as a SCRATCH on
		-- the lens, not as falling lava. Break it into a few short wide segments with gaps,
		-- like a cascade catching on ledges.
		for s = 1, 4 do
			local sy = mid(c) + c.H * (0.30 - 0.19 * s) + rr(-5, 5)
			local lf = M.glow(c.f, CFrame.new(lx + rr(-6, 6), sy, lz + 9)
				* CFrame.Angles(0, 0, rr(-0.07, 0.07)),
				Vector3.new(rr(2.6, 5.0), rr(12, 24), 2), dark(g, rr(0.4, 0.62)))
			M.throb(c.A, lf, dark(g, 0.74), dark(g, 0.3), rr(0.3, 0.6))
		end
		M.lamp(c.f, CFrame.new(lx - side * 6, mid(c), lz + 14), g, 2.0, 64)
		M.emitter(c.f, Vector3.new(lx, c.y1 + 24, lz), Vector3.new(8, 6, 8),
			{ col = lite(g, 0.3), rate = 16, s0 = 0.4, s1 = 1.2, tr = 0.35, spdLo = 2, spdHi = 6,
			  lifeLo = 3, lifeHi = 6, emit = 1, acc = Vector3.new(0, 5, 0), drag = 1 })
		-- reach 0.46 lands the inner edge right at clearW, so the wall reads as rock
		-- closing in rather than sitting entirely behind the HUD panel
		M.rockWall(c.f, side, c.y0, c.y1, -70, 0.46, t.rock, Mat.Basalt, 2)
	end
	-- MID-FRAME FURNITURE. The clear window needs its own content or the shot is one
	-- hero feature floating in empty water, which is what the first pass looked like.
	for k = 1, 7 do
		local zz = rr(-124, -46)
		local hgt = rr(16, 44)
		local o = M.crystal(c.f, M.ux() * M.clearW(zz), c.y1 + hgt + rr(-12, 24), zz,
			rr(10, 26), hgt, dark(t.rock, rr(0, 0.22)), Mat.Basalt, rr(-0.35, 0.35))
		if k % 2 == 0 then cracksOn(c, o, 3, g, 7) end
	end
	-- ceiling: you are inside the plumbing, so cap the band
	M.box(c.f, CFrame.new(0, c.y0 + 16, -80), Vector3.new(340, 34, 220), dark(t.rock, 0.3),
		Mat.Basalt)
	-- stalactites off the ceiling
	for k = 1, 10 do
		local zz = rr(-120, -30)
		M.spike(c.f, M.ux() * M.halfW(zz) * 0.9, c.y0 - 2, zz, rr(6, 14), rr(14, 38),
			dark(t.rock, 0.1), Mat.Basalt, rr(-0.1, 0.1), nil, true)
	end
	M.emitter(c.f, Vector3.new(0, mid(c), -62), Vector3.new(200, c.H, 175),
		{ col = g, rate = 20, s0 = 0.3, s1 = 0.7, tr = 0.35, spdLo = 0.4, spdHi = 1.8,
		  lifeLo = 7, lifeHi = 14, emit = 1, acc = Vector3.new(0, 1.6, 0) })
end

-- 4. EMBER FIELD (-330..-470) - terraces of cooling crust, everything still glowing
function B.embers(c)
	local t, g = c.t, c.t.glow
	for _, side in ipairs({ -1, 1 }) do
		M.rockWall(c.f, side, c.y0, c.y1, Z_MID, 0.32, t.rock, Mat.Basalt, 2)
	end
	-- stepped terraces, each a shelf of crust with heat in the seams
	-- ⚠️ Terraces stay NARROW and set BACK. At 105 studs wide and z=-34 a single shelf is
	-- wider than the whole frame, and unlit at that range it renders as a solid black bar
	-- straight across the middle of the shot.
	for k = 1, 6 do
		local y  = c.y1 + (c.H) * ((k - 0.5) / 6.5)
		local zz = pick({ -52, Z_MID, -88, Z_FAR })
		local hw = M.halfW(zz)
		local x  = M.ux() * hw * 0.55
		local w  = rr(34, 72)
		local shelf = M.box(c.f, CFrame.new(x, y, zz)
			* CFrame.Angles(0, rr(-0.25, 0.25), rr(-0.06, 0.06)),
			Vector3.new(w, rr(6, 13), rr(30, 60)), dark(t.rock, rr(0, 0.2)), Mat.CrackedLava)
		cracksOn(c, shelf, 8, g, 7)
		for v = 1, rng:NextInteger(1, 2) do
			M.vent(c, x + rr(-w * 0.4, w * 0.4), y + 5, zz + rr(-8, 14), rr(6, 12), g)
		end
	end
	-- obsidian shards - sharp, black, and the only cool thing in the frame
	for k = 1, 24 do
		local zz = rr(-140, -30)
		M.shard(c.f, M.ux() * M.halfW(zz) * 0.92, c.y1 + rr(-10, 70), zz,
			rr(2.5, 7), rr(16, 46), dark(t.rock, rr(0.15, 0.45)), Mat.Slate, rr(-0.28, 0.28))
	end
	-- a fissure running across the floor of the band
	local fis = M.glow(c.f, CFrame.new(rr(-20, 20), c.y1 + 6, -66), Vector3.new(230, 3.5, 6),
		dark(g, 0.25))
	M.throb(c.A, fis, dark(g, 0.55), g, 0.28)
	for k = -1, 1 do M.lamp(c.f, CFrame.new(k * 70, c.y1 + 16, -60), g, 2.0, 90) end
	M.box(c.f, CFrame.new(0, c.y1 - 14, -70), Vector3.new(340, 26, 210), dark(t.rock, 0.1),
		Mat.CrackedLava)
	-- THE band signature: embers rising through the whole column
	M.emitter(c.f, Vector3.new(0, c.y1 + 6, -62), Vector3.new(210, 10, 180),
		{ col = lite(g, 0.25), rate = 55, s0 = 0.35, s1 = 0.8, tr = 0.25, spdLo = 1, spdHi = 4,
		  lifeLo = 12, lifeHi = 24, emit = 1, acc = Vector3.new(0.5, 2.6, 0), drag = 0.5 })
	M.emitter(c.f, Vector3.new(0, mid(c), -70), Vector3.new(210, c.H, 180),
		{ tex = TEX.smoke, col = dark(t.rock, 0.1), rate = 8, s0 = 6, s1 = 22, tr = 0.85,
		  spdLo = 0.5, spdHi = 2, lifeLo = 10, lifeHi = 18, emit = 0.15,
		  acc = Vector3.new(0, 1.2, 0) })
end

----------------------------------------------------------------------
-- ZONE 1 - LIGHTHOUSE COVE
----------------------------------------------------------------------

-- a swaying stalk in `segs` stacked pieces, rotated about its ROOT so it bends instead
-- of sliding. Used by kelp and seagrass.
local function stalk(c, x, yBase, zz, hgt, w, col, mat, blades, bladeCol)
	local segs, parts = 3, {}
	for s = 1, segs do
		local sy = yBase + hgt * ((s - 0.5) / segs)
		parts[#parts + 1] = M.box(c.f, CFrame.new(x, sy, zz)
			* CFrame.Angles(0, 0, rr(-0.06, 0.06)),
			Vector3.new(w, hgt / segs * 1.08, w * 0.7), col, mat)
		if blades then
			for b = 1, blades do
				local dir = (b % 2 == 0) and 1 or -1
				parts[#parts + 1] = M.box(c.f,
					CFrame.new(x + dir * w * rr(1.2, 3.2), sy + rr(-6, 6), zz + rr(-2, 2))
						* CFrame.Angles(rr(-0.3, 0.3), rr(-0.6, 0.6), dir * rr(0.5, 1.1)),
					Vector3.new(rr(5, 13), rr(0.5, 1.1), rr(1.5, 3.5)), bladeCol or col, mat)
			end
		end
	end
	M.sway(c.A, parts, Vector3.new(x, yBase, zz), rr(0.04, 0.11), rr(0.25, 0.55))
	return parts
end

function B.kelp(c)
	local t = c.t
	local LAYERS = { { z = -26, s = 1.3, d = 0.5 }, { z = -46, s = 1.05, d = 0.32 },
		{ z = Z_MID, s = 0.85, d = 0.16 }, { z = -92, s = 0.65, d = 0.05 },
		{ z = -126, s = 0.5, d = 0 } }
	for _, L in ipairs(LAYERS) do
		local hw = M.halfW(L.z)
		-- WARNING: THIS BAND WAS THE WORST OFFENDER IN THE GAME - 634 parts, 383 of
		-- them overlapping the clear window and 188 in the fish's own lane. A kelp
		-- forest still reads as a forest at a third of the stalks; the rest was noise
		-- at exactly the size and colour of the fish swimming through it.
		for k = 1, (L.z > -50 and 4 or 9) do
			local col = dark(t.accent, L.d)
			local yb = c.y1 - rr(0, 24)
			-- WARNING: AND CAP THE HEIGHT. Rooted at -214 carrying 165 * 1.3 of stalk, the
			-- front layer topped out at y = 0 - so the SHALLOWS, the one band deliberately
			-- left empty because the real fish swim in it, had near-black kelp standing
			-- through it at maximum contrast against bright cyan water.
			stalk(c, M.ux() * hw * 1.02, yb, L.z + rr(-10, 10),
				math.min(rr(80, 165) * L.s, c.y0 + 4 - yb), rr(1.4, 3.0) * L.s,
				col, Mat.Grass, 2, lite(col, 0.12))
		end
	end
	-- rocky seabed the forest is rooted in, well below the band
	M.box(c.f, CFrame.new(0, c.y1 - 20, -72), Vector3.new(340, 24, 210), dark(t.rock, 0.1),
		c.mat.grit)
	for k = 1, 14 do
		local zz = rr(-130, -30)
		M.blob(c.f, Vector3.new(M.ux() * M.halfW(zz), c.y1 + rr(-4, 12), zz),
			Vector3.new(rr(10, 30), rr(7, 18), rr(10, 26)), dark(t.rock, rr(0, 0.25)), c.mat.rock)
	end
	for k = 1, 6 do shaft(c, M.ux() * M.halfW(-70), rr(-120, -40), c.y0, rr(60, 110), rr(2, 5)) end
	M.emitter(c.f, Vector3.new(0, mid(c), -60), Vector3.new(190, c.H, 165),
		{ col = lite(t.accent, 0.5), rate = 20, s0 = 0.4, s1 = 0.8, tr = 0.5, spdLo = 0.2,
		  spdHi = 1.1, lifeLo = 9, lifeHi = 17, emit = 0.5, acc = Vector3.new(0.2, 0.3, 0) })
end

function B.cavern(c)
	local t = c.t
	local g = t.glow or t.accent
	-- walls close in from both sides and a roof caps the band: you are INSIDE something
	for _, side in ipairs({ -1, 1 }) do
		M.rockWall(c.f, side, c.y0, c.y1, -60, 0.44, t.rock, c.mat.rock, 2)
		M.rockWall(c.f, side, c.y0, c.y1, -28, 0.20, dark(t.rock, 0.4), c.mat.rock, 1)
	end
	M.box(c.f, CFrame.new(0, c.y0 + 20, -76), Vector3.new(340, 42, 215), dark(t.rock, 0.25),
		c.mat.rock)
	for k = 1, 16 do
		local zz = rr(-130, -28)
		M.spike(c.f, M.ux() * M.halfW(zz) * 0.95, c.y0 - 1, zz, rr(5, 14), rr(16, 46),
			dark(t.rock, rr(0, 0.3)), c.mat.rock, rr(-0.1, 0.1), nil, true)
	end
	for k = 1, 10 do
		local zz = rr(-130, -34)
		M.spike(c.f, M.ux() * M.halfW(zz) * 0.9, c.y1 - 4, zz, rr(6, 16), rr(20, 55),
			dark(t.rock, rr(0, 0.3)), c.mat.rock, rr(-0.1, 0.1))
	end
	-- glowing weed in the cracks, and light spilling through a hole in the roof
	for k = 1, 9 do
		local zz = rr(-120, -36)
		local r = M.crystal(c.f, M.ux() * M.clearW(zz) * 1.2, rr(c.y1 + 20, c.y0 - 30), zz,
			rr(8, 20), rr(14, 34), dark(t.rock, rr(0, 0.2)), c.mat.rock, rr(-0.3, 0.3))
		cracksOn(c, r, 3, g, 6)
	end
	for k = 1, 3 do
		shaft(c, M.ux() * M.clearW(-70), rr(-100, -50), c.y0 - 8, rr(70, 120), rr(4, 9))
	end
	M.lamp(c.f, CFrame.new(0, c.y0 - 30, -60), g, 1.6, 130)
	M.emitter(c.f, Vector3.new(0, mid(c), -62), Vector3.new(190, c.H, 170),
		{ col = lite(g, 0.3), rate = 16, s0 = 0.4, s1 = 0.9, tr = 0.55, spdLo = 0.2,
		  spdHi = 0.9, lifeLo = 10, lifeHi = 18, emit = 0.4 })
end

----------------------------------------------------------------------
-- ZONE 2 - TROPICAL REEF
----------------------------------------------------------------------
local REEF = { 0xFF7A5A, 0xFFC24A, 0xFF6FA8, 0x8ADB5A, 0x6ECBFF, 0xC98AFF }

function B.coral(c)
	local t = c.t
	M.box(c.f, CFrame.new(0, c.y1 - 16, -72), Vector3.new(340, 22, 210), t.rock, c.mat.soft)
	for L, zz in ipairs({ -26, -46, Z_MID, -92, -126 }) do
		local hw, sc = M.halfW(zz), 1.35 - L * 0.17
		for k = 1, (L < 3 and 5 or 9) do
			local x = M.ux() * hw * 1.02
			local base = c.y1 - rr(0, 18)
			local col = h(pick(REEF)):Lerp(t.bot, 0.15 + L * 0.11)
			local kind = rng:NextInteger(1, 3)
			if kind == 1 then          -- brain coral: a mound of blobs
				for b = 1, 5 do
					M.blob(c.f, Vector3.new(x + rr(-10, 10) * sc, base + rr(2, 20) * sc, zz + rr(-8, 8)),
						Vector3.new(rr(9, 22), rr(8, 18), rr(9, 20)) * sc, col, Mat.Limestone)
				end
			elseif kind == 2 then      -- staghorn: branching arms
				for b = 1, 7 do
					local a = rr(-0.9, 0.9)
					M.cyl(c.f, CFrame.new(x + rr(-8, 8) * sc, base + rr(8, 34) * sc, zz + rr(-6, 6))
						* CFrame.Angles(rr(-0.4, 0.4), rr(-0.8, 0.8), a + math.rad(90)),
						rr(12, 32) * sc, rr(1.6, 3.4) * sc, col, Mat.Limestone)
				end
			else                        -- sea fan: a thin upright plate, and it sways
				local fan = M.box(c.f, CFrame.new(x, base + rr(16, 30) * sc, zz)
					* CFrame.Angles(0, rr(-0.5, 0.5), rr(-0.15, 0.15)),
					Vector3.new(rr(16, 34) * sc, rr(20, 42) * sc, 0.9), col, Mat.Fabric)
				M.sway(c.A, { fan }, Vector3.new(x, base, zz), rr(0.03, 0.07), rr(0.3, 0.6))
			end
		end
	end
	for k = 1, 5 do shaft(c, M.ux() * M.halfW(-70), rr(-120, -40), c.y0, rr(60, 110), rr(2, 5)) end
	M.emitter(c.f, Vector3.new(0, mid(c), -60), Vector3.new(190, c.H, 165),
		{ col = lite(t.accent, 0.4), rate = 24, s0 = 0.35, s1 = 0.7, tr = 0.45, spdLo = 0.3,
		  spdHi = 1.4, lifeLo = 8, lifeHi = 15, emit = 0.6, acc = Vector3.new(0, 0.8, 0) })
end

function B.wreck(c)
	local t = c.t
	local g = t.glow or t.accent
	local hull = dark(t.rock, 0.1)
	local HX, HY, HZ = rr(-14, 6), c.y1 + 26, -78
	-- a broken hull lying over on its side, bow toward the camera
	M.box(c.f, CFrame.new(HX, HY, HZ) * CFrame.Angles(0, rr(-0.3, -0.15), rr(0.18, 0.3)),
		Vector3.new(120, 26, 34), hull, Mat.WoodPlanks)
	M.box(c.f, CFrame.new(HX - 46, HY + 12, HZ) * CFrame.Angles(0, -0.22, 0.34),
		Vector3.new(40, 20, 26), hull, Mat.WoodPlanks)
	-- ribs arcing out of the broken side: the silhouette that says "shipwreck"
	for k = 1, 7 do
		M.arc(c.f, HX - 30 + k * 13, HY + 6, HZ + 10, rr(16, 26), 0.35, math.pi - 0.35, 7,
			2.2, 2.2, dark(hull, 0.2), Mat.Wood)
	end
	-- mast and spar
	M.cyl(c.f, CFrame.new(HX + 6, HY + 34, HZ + 6) * CFrame.Angles(0, 0, math.rad(60)),
		86, 4.5, dark(hull, 0.15), Mat.Wood)
	-- portholes still lit
	for k = 1, 6 do
		local p = M.glow(c.f, CFrame.new(HX - 44 + k * 15, HY + rr(-3, 5), HZ + 18)
			* CFrame.Angles(0, math.rad(90), 0), Vector3.new(1.5, 3.4, 3.4), dark(g, 0.3))
		p.Shape = Enum.PartType.Cylinder
		if k % 2 == 0 then M.throb(c.A, p, dark(g, 0.7), dark(g, 0.1), rr(0.3, 0.8)) end
	end
	M.lamp(c.f, CFrame.new(HX, HY + 6, HZ + 26), g, 2, 95)
	for _, side in ipairs({ -1, 1 }) do
		M.rockWall(c.f, side, c.y0, c.y1, -52, 0.40, t.rock, c.mat.rock, 2)
	end
	M.box(c.f, CFrame.new(0, c.y1 - 16, -74), Vector3.new(340, 24, 210), t.rock, c.mat.soft)
	-- scattered cargo and spars on the sand
	for k = 1, 12 do
		local zz = rr(-125, -34)
		M.box(c.f, CFrame.new(M.ux() * M.halfW(zz) * 0.9, c.y1 + rr(2, 12), zz)
			* CFrame.Angles(rr(-0.6, 0.6), rr(-1, 1), rr(-0.6, 0.6)),
			Vector3.new(rr(5, 14), rr(5, 12), rr(5, 14)), dark(hull, rr(0, 0.3)), Mat.Wood)
	end
	M.emitter(c.f, Vector3.new(0, mid(c), -62), Vector3.new(190, c.H, 170),
		{ col = lite(t.accent, 0.2), rate = 18, s0 = 0.4, s1 = 0.9, tr = 0.5, spdLo = 0.2,
		  spdHi = 1.0, lifeLo = 9, lifeHi = 17, emit = 0.4 })
end

function B.bluehole(c)
	local t = c.t
	local g = t.glow or t.accent
	-- a vertical shaft: the walls step INWARD as you go down, so the drop reads
	for _, side in ipairs({ -1, 1 }) do
		for k = 1, 5 do
			local yTop = c.y0 - (k - 1) * (c.H / 5)
			M.rockWall(c.f, side, yTop, yTop - c.H / 5 - 6, -56, 0.26 + k * 0.045,
				t.rock, c.mat.rock, 2)
		end
		for k = 1, 5 do
			local zz = pick({ -40, Z_MID, -92 })
			M.box(c.f, CFrame.new(side * M.clearW(zz) * rr(0.9, 1.25),
				rr(c.y1 + 20, c.y0 - 20), zz) * CFrame.Angles(0, rr(-0.4, 0.4), rr(-0.1, 0.1)),
				Vector3.new(rr(22, 44), rr(4, 9), rr(18, 32)), dark(t.rock, 0.12), c.mat.rock)
		end
	end
	-- the column of light coming down the throat of the hole
	for k = 1, 5 do
		shaft(c, M.ux() * M.clearW(-70) * 0.8, rr(-110, -46), c.y0 + 10, c.H * rr(0.6, 1.0),
			rr(5, 12))
	end
	for k = 1, 10 do
		local zz = rr(-135, -34)
		M.spike(c.f, M.ux() * M.halfW(zz) * 0.95, c.y0 - 2, zz, rr(6, 15), rr(20, 52),
			dark(t.rock, rr(0, 0.3)), c.mat.rock, rr(-0.1, 0.1), nil, true)
	end
	M.emitter(c.f, Vector3.new(0, mid(c), -62), Vector3.new(190, c.H, 170),
		{ col = g, rate = 20, s0 = 0.35, s1 = 0.7, tr = 0.42, spdLo = 0.3, spdHi = 1.2,
		  lifeLo = 9, lifeHi = 17, emit = 0.9, acc = Vector3.new(0, 0.5, 0) })
end

----------------------------------------------------------------------
-- ZONE 3 - GOLDEN SUNSET BAY
----------------------------------------------------------------------
function B.seagrass(c)
	local t = c.t
	M.box(c.f, CFrame.new(0, c.y1 - 14, -72), Vector3.new(340, 20, 210), t.rock, c.mat.soft)
	-- shorter and MUCH denser than kelp - a meadow, not a forest
	for L, zz in ipairs({ -24, -42, Z_MID, -88, -120 }) do
		local hw, sc = M.halfW(zz), 1.25 - L * 0.15
		for k = 1, (L < 3 and 10 or 18) do
			local col = dark(t.accent, 0.08 * L)
			stalk(c, M.ux() * hw * 1.02, c.y1 - rr(0, 10), zz + rr(-9, 9),
				rr(26, 62) * sc, rr(0.8, 1.8) * sc, col, Mat.LeafyGrass, 1, lite(col, 0.15))
		end
	end
	for k = 1, 12 do
		local zz = rr(-128, -30)
		M.blob(c.f, Vector3.new(M.ux() * M.halfW(zz), c.y1 + rr(-2, 10), zz),
			Vector3.new(rr(9, 26), rr(6, 15), rr(9, 22)), dark(t.rock, rr(0, 0.2)), c.mat.grit)
	end
	for k = 1, 7 do shaft(c, M.ux() * M.halfW(-70), rr(-120, -40), c.y0, rr(70, 120), rr(2, 6)) end
	M.emitter(c.f, Vector3.new(0, mid(c), -60), Vector3.new(190, c.H, 165),
		{ col = lite(t.accent, 0.4), rate = 22, s0 = 0.4, s1 = 0.8, tr = 0.5, spdLo = 0.2,
		  spdHi = 1.2, lifeLo = 9, lifeHi = 16, emit = 0.5, acc = Vector3.new(0.3, 0.4, 0) })
end

function B.arches(c)
	local t = c.t
	local g = t.glow or t.accent
	-- eroded sandstone arches at three depths, straddling the clear window
	for k, zz in ipairs({ -40, -74, -116 }) do
		local sc = 1.25 - k * 0.22
		local ax = M.ux() * M.clearW(zz) * 0.6
		local ay = c.y1 + rr(10, 40)
		local span = rr(46, 78) * sc
		local hgt  = rr(50, 86) * sc
		local col  = dark(t.rock, 0.06 * k)
		for _, s in ipairs({ -1, 1 }) do
			M.box(c.f, CFrame.new(ax + s * span / 2, ay + hgt * 0.3, zz)
				* CFrame.Angles(0, rr(-0.2, 0.2), s * rr(0.02, 0.10)),
				Vector3.new(rr(12, 22) * sc, hgt * 0.62, rr(16, 30) * sc), col, Mat.Sandstone)
		end
		M.arc(c.f, ax, ay + hgt * 0.6, zz, span / 2, 0.15, math.pi - 0.15, 9,
			rr(9, 15) * sc, rr(16, 28) * sc, col, Mat.Sandstone)
	end
	for _, side in ipairs({ -1, 1 }) do
		M.rockWall(c.f, side, c.y0, c.y1, -58, 0.40, t.rock, Mat.Sandstone, 2)
	end
	M.box(c.f, CFrame.new(0, c.y1 - 14, -72), Vector3.new(340, 20, 210), t.rock, c.mat.soft)
	for k = 1, 12 do
		local zz = rr(-130, -32)
		M.crystal(c.f, M.ux() * M.halfW(zz) * 0.95, c.y1 + rr(8, 40), zz, rr(9, 22),
			rr(14, 40), dark(t.rock, rr(0, 0.25)), Mat.Sandstone, rr(-0.3, 0.3))
	end
	for k = 1, 4 do shaft(c, M.ux() * M.clearW(-70), rr(-110, -44), c.y0, rr(70, 120), rr(3, 8)) end
	M.lamp(c.f, CFrame.new(0, mid(c), -50), lite(g, 0.2), 1.2, 120)
	M.emitter(c.f, Vector3.new(0, mid(c), -62), Vector3.new(190, c.H, 170),
		{ col = lite(t.accent, 0.3), rate = 18, s0 = 0.4, s1 = 0.9, tr = 0.5, spdLo = 0.2,
		  spdHi = 1.0, lifeLo = 9, lifeHi = 17, emit = 0.4 })
end

----------------------------------------------------------------------
-- ZONE 4 - FROSTBITE FJORD
----------------------------------------------------------------------
function B.iceshelf(c)
	local t = c.t
	local g = t.glow or t.accent
	-- a CEILING of pack ice with daylight coming through the cracks. The band's whole
	-- identity is that the sky is a solid lid over your head.
	M.box(c.f, CFrame.new(0, c.y0 + 22, -78), Vector3.new(360, 44, 220), lite(t.rock, 0.1),
		Mat.Glacier)
	for k = 1, 16 do
		local zz = rr(-135, -26)
		M.box(c.f, CFrame.new(M.ux() * M.halfW(zz), c.y0 - rr(0, 5), zz)
			* CFrame.Angles(0, rr(-0.6, 0.6), 0),
			Vector3.new(rr(20, 60), 3, rr(1.5, 4)), lite(g, 0.35), Mat.Neon)
	end
	-- ice keels hanging down
	for k = 1, 16 do
		local zz = rr(-135, -26)
		M.spike(c.f, M.ux() * M.halfW(zz) * 0.98, c.y0 - 2, zz, rr(10, 30), rr(24, 70),
			lite(t.rock, rr(0, 0.22)), Mat.Glacier, rr(-0.12, 0.12), nil, true)
	end
	for k = 1, 6 do
		shaft(c, M.ux() * M.halfW(-70), rr(-120, -40), c.y0 - 6, rr(70, 130), rr(4, 10))
	end
	for _, side in ipairs({ -1, 1 }) do
		M.rockWall(c.f, side, c.y0 - 30, c.y1, -60, 0.32, t.rock, Mat.Glacier, 2)
	end
	M.lamp(c.f, CFrame.new(0, c.y0 - 24, -56), lite(g, 0.3), 1.8, 140)
	M.emitter(c.f, Vector3.new(0, mid(c), -60), Vector3.new(190, c.H, 165),
		{ col = lite(g, 0.4), rate = 24, s0 = 0.35, s1 = 0.7, tr = 0.5, spdLo = 0.2,
		  spdHi = 1.0, lifeLo = 9, lifeHi = 17, emit = 0.7, acc = Vector3.new(0.2, 0.5, 0) })
end

function B.crevasse(c)
	local t = c.t
	local g = t.glow or t.accent
	-- a narrow slot in the ice: near-vertical walls, blue light bleeding through them
	for _, side in ipairs({ -1, 1 }) do
		M.rockWall(c.f, side, c.y0, c.y1, -56, 0.52, t.rock, Mat.Glacier, 2)
		M.rockWall(c.f, side, c.y0, c.y1, -26, 0.24, dark(t.rock, 0.3), Mat.Ice, 1)
		for k = 1, 10 do
			local zz = pick({ -40, Z_MID, -92 })
			M.glow(c.f, CFrame.new(side * M.clearW(zz) * rr(0.95, 1.3),
				rr(c.y1 + 10, c.y0 - 10), zz + 12) * CFrame.Angles(0, 0, rr(-0.25, 0.25)),
				Vector3.new(rr(1, 2.6), rr(16, 46), 1.2), dark(g, rr(0.45, 0.7)))
		end
	end
	for k = 1, 18 do
		local zz = rr(-130, -28)
		M.spike(c.f, M.ux() * M.halfW(zz) * 0.95, c.y0 - rr(0, 40), zz, rr(4, 12),
			rr(20, 60), lite(t.rock, rr(0, 0.25)), Mat.Ice, rr(-0.1, 0.1), nil, true)
	end
	for k = 1, 8 do
		local zz = rr(-120, -36)
		M.crystal(c.f, M.ux() * M.clearW(zz) * 1.2, rr(c.y1 + 20, c.y0 - 30), zz,
			rr(8, 20), rr(16, 40), lite(t.rock, rr(0, 0.2)), Mat.Ice, rr(-0.35, 0.35))
	end
	M.lamp(c.f, CFrame.new(0, mid(c), -46), g, 1.6, 130)
	M.emitter(c.f, Vector3.new(0, mid(c), -62), Vector3.new(190, c.H, 170),
		{ col = lite(g, 0.3), rate = 20, s0 = 0.35, s1 = 0.75, tr = 0.5, spdLo = 0.2,
		  spdHi = 1.0, lifeLo = 9, lifeHi = 17, emit = 0.8 })
end

function B.aurora(c)
	local t = c.t
	local g = t.glow or t.accent
	-- curtains of light hanging in dark water, with ice spires to occlude them
	for k = 1, 9 do
		local zz = rr(-140, -44)
		local cx = M.ux() * M.halfW(zz) * 0.9
		local cy = rr(c.y1 + 30, c.y0 - 20)
		local parts = {}
		for s = 1, 5 do
			parts[s] = M.glow(c.f, CFrame.new(cx + (s - 3) * rr(5, 9), cy + rr(-8, 8), zz + rr(-6, 6))
				* CFrame.Angles(0, rr(-0.3, 0.3), rr(-0.12, 0.12)),
				Vector3.new(rr(3, 7), rr(40, 90), 0.8), dark(g, rr(0.5, 0.75)))
		end
		M.sway(c.A, parts, Vector3.new(cx, cy + 50, zz), rr(0.02, 0.05), rr(0.15, 0.35))
	end
	for _, side in ipairs({ -1, 1 }) do
		M.rockWall(c.f, side, c.y0, c.y1, Z_MID, 0.30, t.rock, Mat.Glacier, 2)
	end
	for k = 1, 12 do
		local zz = rr(-140, -30)
		M.spike(c.f, M.ux() * M.halfW(zz) * 0.95, c.y1 + rr(-10, 40), zz, rr(8, 20),
			rr(40, 110), dark(t.rock, rr(0, 0.3)), Mat.Glacier, rr(-0.12, 0.12))
	end
	M.lamp(c.f, CFrame.new(0, mid(c), -60), g, 1.4, 140)
	M.emitter(c.f, Vector3.new(0, mid(c), -62), Vector3.new(190, c.H, 170),
		{ col = g, rate = 26, s0 = 0.35, s1 = 0.7, tr = 0.4, spdLo = 0.3, spdHi = 1.3,
		  lifeLo = 8, lifeHi = 16, emit = 1, acc = Vector3.new(0, 0.6, 0) })
end

----------------------------------------------------------------------
-- ZONE 5 - MIDNIGHT TRENCH
----------------------------------------------------------------------
function B.whalefall(c)
	local t = c.t
	local bone = t.accent          -- pale; the ONLY bright thing in the band
	local BX, BY, BZ = rr(-16, 4), c.y1 + 20, -76
	M.box(c.f, CFrame.new(0, c.y1 - 14, -72), Vector3.new(340, 20, 210), t.rock, c.mat.soft)
	-- spine
	for k = 1, 16 do
		M.box(c.f, CFrame.new(BX - 60 + k * 8, BY + math.sin(k * 0.35) * 3, BZ)
			* CFrame.Angles(0, 0, rr(-0.1, 0.1)),
			Vector3.new(6, rr(4, 7), rr(4, 7)), dark(bone, rr(0, 0.18)), Mat.Sand)
	end
	-- ribcage: paired arcs springing off the spine, the silhouette that carries the band
	for k = 1, 8 do
		local sx = BX - 46 + k * 9
		local rad = 22 + math.sin(k * 0.6) * 9
		M.arc(c.f, sx, BY, BZ + 2, rad, 0.25, math.pi - 0.25, 8, 2.4, 2.4,
			dark(bone, 0.10 + k * 0.01), Mat.Sand)
	end
	-- skull
	M.blob(c.f, Vector3.new(BX + 76, BY + 6, BZ), Vector3.new(46, 24, 22),
		dark(bone, 0.08), Mat.Sand)
	M.box(c.f, CFrame.new(BX + 96, BY - 4, BZ) * CFrame.Angles(0, 0, -0.14),
		Vector3.new(40, 7, 12), dark(bone, 0.14), Mat.Sand)
	-- the bacterial mat that lives on a whale fall
	for k = 1, 14 do
		local p = M.glow(c.f, CFrame.new(BX + rr(-60, 80), BY + rr(-14, 12), BZ + rr(6, 16)),
			Vector3.new(rr(3, 10), rr(1, 3), rr(3, 8)), dark(bone, rr(0.55, 0.75)))
		if k % 3 == 0 then M.throb(c.A, p, dark(bone, 0.85), dark(bone, 0.45), rr(0.2, 0.5)) end
	end
	M.lamp(c.f, CFrame.new(BX, BY + 10, BZ + 24), lite(bone, 0.1), 1.3, 110)
	for _, side in ipairs({ -1, 1 }) do
		M.rockWall(c.f, side, c.y0, c.y1, Z_MID, 0.34, t.rock, c.mat.rock, 2)
	end
	M.emitter(c.f, Vector3.new(0, c.y0 - 6, -62), Vector3.new(190, 8, 170),
		{ col = lite(t.rock, 0.5), rate = 30, s0 = 0.4, s1 = 0.9, tr = 0.55, spdLo = 0.2,
		  spdHi = 0.8, lifeLo = 16, lifeHi = 28, emit = 0.2,
		  acc = Vector3.new(0.2, -0.9, 0), dir = Enum.NormalId.Bottom })
end

function B.spires(c)
	local t = c.t
	local g = t.glow or t.accent
	-- a forest of black obsidian needles. Almost no colour: this band is silhouette only,
	-- so the murk behind has to carry every bit of the contrast.
	for L, zz in ipairs({ -24, -44, Z_MID, -92, -128 }) do
		local hw, sc = M.halfW(zz), 1.3 - L * 0.16
		for k = 1, (L < 3 and 5 or 10) do
			M.spike(c.f, M.ux() * hw * 1.02, c.y1 - rr(0, 30), zz + rr(-10, 10),
				rr(10, 26) * sc, rr(70, 180) * sc, dark(t.rock, math.max(0, 0.45 - L * 0.11)),
				Mat.Slate, rr(-0.10, 0.10))
		end
	end
	M.box(c.f, CFrame.new(0, c.y1 - 18, -74), Vector3.new(340, 24, 210), dark(t.rock, 0.1),
		c.mat.grit)
	-- a few lit tips so the eye has somewhere to land
	for k = 1, 9 do
		local zz = rr(-130, -40)
		local p = M.glow(c.f, CFrame.new(M.ux() * M.clearW(zz) * 1.3,
			rr(c.y1 + 40, c.y0 - 20), zz), Vector3.new(rr(1.2, 3), rr(4, 12), 1.4),
			dark(g, rr(0.4, 0.65)))
		M.throb(c.A, p, dark(g, 0.85), dark(g, 0.3), rr(0.25, 0.7))
	end
	M.emitter(c.f, Vector3.new(0, mid(c), -62), Vector3.new(190, c.H, 170),
		{ col = g, rate = 16, s0 = 0.3, s1 = 0.6, tr = 0.45, spdLo = 0.2, spdHi = 1.0,
		  lifeLo = 10, lifeHi = 18, emit = 1, acc = Vector3.new(0, 0.4, 0) })
end

-- fallback for any band whose builder is not written yet: plain canyon rock, so a zone
-- is never empty water while the rest are being built out.
function B.rocks(c)
	local t = c.t
	for _, side in ipairs({ -1, 1 }) do
		M.rockWall(c.f, side, c.y0, c.y1, Z_MID, 0.34, t.rock, c.mat.rock, 2)
	end
	for k = 1, 14 do
		local zz = rr(-140, -26)
		M.crystal(c.f, M.ux() * M.halfW(zz) * 0.9, rr(c.y1 + 20, c.y0 - 20), zz,
			rr(6, 18), rr(25, 80), dark(t.rock, rr(0, 0.3)), c.mat.rock, rr(-0.3, 0.3))
	end
	M.emitter(c.f, Vector3.new(0, mid(c), -60), Vector3.new(190, c.H, 165),
		{ col = lite(t.accent, 0.2), rate = 18, s0 = 0.4, s1 = 0.8, tr = 0.5,
		  spdLo = 0.2, spdHi = 1.0, lifeLo = 8, lifeHi = 16, emit = 0.5 })
end

----------------------------------------------------------------------
-- assembly + the per-frame step
----------------------------------------------------------------------

-- the water colour at a depth, interpolated inside its band. This is the fog colour,
-- and fog is what makes distance read as water rather than as empty space.
function M.waterAt(zid, y)
	local T = M.LINEUP[zid] or M.LINEUP[1]
	if y >= 0 then return T[1].top, 1 end
	for i, bd in ipairs(M.BANDS) do
		if y <= bd.y0 and y > bd.y1 then
			return T[i].top:Lerp(T[i].bot, (bd.y0 - y) / (bd.y0 - bd.y1)), i
		end
	end
	return T[#T].bot, #T
end

----------------------------------------------------------------------
-- RECEDE - the pass that turns scenery back into a BACKDROP
--
-- Runs once over every band after it is built. Everything here is a VALUE change on
-- an already-placed part, never a move, so no composition and no animation offset is
-- disturbed by it.
--
-- WARNING: IT HAS TO REACH INTO THE ANIMATION REGISTRY TOO. `throb` re-writes its
-- part's Color from a stored c0/c1 pair every frame, so a Neon part dimmed here is
-- back at full brightness one frame later unless the stored pair is dimmed with it.
-- That is the whole reason this is a pass over the state and not a tweak inside
-- M.glow: the glow builders are not the only writer of those colours.
----------------------------------------------------------------------

-- how far toward the water a part at this position should sit. Distance does most
-- of it; sitting in the fish's lane adds the rest.
local function hazeAt(x, zz)
	local BK = M.BACKDROP
	local u = math.clamp((zz - Z_SAFE) / (BK.hazeZ - Z_SAFE), 0, 1)
	local k = BK.hazeNear + (BK.hazeFar - BK.hazeNear) * u ^ BK.hazeCurve
	local cw = M.clearW(zz)
	if cw > 0 then
		k += BK.throat * (1 - math.clamp(math.abs(x) / cw, 0, 1))
	end
	return math.clamp(k, 0, 0.94)
end

function M.recede(state)
	local BK = M.BACKDROP
	local zid = state.zone
	for _, b in ipairs(state.bands) do
		for _, d in ipairs(b.folder:GetDescendants()) do
			if d:IsA("BasePart") then
				local p = d.Position
				local k = hazeAt(p.X, p.Z)
				if d.Material == Enum.Material.Neon then
					-- WARNING: DARKEN, NEVER FADE. Any transparency on a Neon part renders
					-- it near-black under Future lighting (M.glow says the same thing).
					-- Emissive things also do not take the water lerp - light does not haze
					-- toward its own background, it just carries less far.
					d.Color = dark(d.Color, math.clamp(BK.glowDim + 0.28 * k, 0, 0.88))
				else
					-- solid geometry, and the light shafts with it. A shaft is atmosphere, so
					-- hazing it toward the murk is right: distance dissolves it. Darkening it
					-- the way the glow kit is darkened is what made it a black bar.
					--
					-- WARNING: THE TARGET IS THE MURK COLOUR, NOT THE RAW WATER. lite(col, 0.26)
					-- is exactly what applyWater paints the fog and both backdrop sheets, so
					-- this is the value a part actually dissolves INTO - which is the whole
					-- point of the pass. Hazing toward the raw water instead looked identical in
					-- zone 1, where the water is bright, and destroyed zone 6, where it is a
					-- near-black red: every piece of basalt was dragged toward black, the lift
					-- the zone-6 palette exists to provide was cancelled out, and the band came
					-- back as black shapes on black with the fish invisible inside it.
					d.Color = d.Color:Lerp(lite(M.waterAt(zid, p.Y), 0.26), k)
				end
			elseif d:IsA("PointLight") then
				d.Brightness *= BK.lightDim
			elseif d:IsA("ParticleEmitter") then
				-- the trench alone ran 21 of these and their pale plumes were most of why
				-- that band came back as a milky wash with no fish readable in it
				d.Rate *= BK.fxRate
				d.LightEmission *= BK.fxRate
				local kp = {}
				for i, key in ipairs(d.Transparency.Keypoints) do
					kp[i] = NumberSequenceKeypoint.new(key.Time,
						math.clamp(key.Value + (1 - key.Value) * BK.fxFade, 0, 1))
				end
				if #kp >= 2 then d.Transparency = NumberSequence.new(kp) end
			end
		end
		for _, e in ipairs(b.anim) do
			if e.k == "throb" and e.parts[1] then
				local p = e.parts[1].Position
				local kk = math.clamp(BK.glowDim + 0.28 * hazeAt(p.X, p.Z), 0, 0.88)
				e.c0, e.c1 = dark(e.c0, kk), dark(e.c1, kk)
			end
		end
	end
end

-- A flat sheet of water: an invisible part wearing an UNLIT SurfaceGui.
--
-- WARNING: BOTH BACKDROP SHEETS MUST BE BUILT THE SAME WAY OR THEY CANNOT MATCH.
-- The far wall was a LIT SmoothPlastic relying on sitting past FogEnd to come out as
-- pure fog colour, and measured in game it does not - at 410 studs against FogEnd 376
-- it still rendered as its own colour shaded by the underwater ambient, i.e. a dull
-- sage green, while an unlit sheet painted the identical colour renders bright cyan.
-- Put the two next to each other and that difference is a hard horizontal line across
-- the play area. LightInfluence = 0 renders the colour EXACTLY (the same trick
-- WaterBack and the painted backdrops use), so two sheets given the same colour are
-- the same colour, whatever fog and ambient happen to be doing.
-- ⚠️ SizingMode MUST be PixelsPerStud - FixedSize silently renders an 800x600 canvas
-- whatever the face measures - and Face is Back, because Roblox's Front is local -Z
-- while the camera looks at these from +Z.
-- `fadeAt` (0..1 down the face) gives the sheet a SOFT BOTTOM EDGE.
--
-- WARNING: A SHEET THAT ENDS SOMEWHERE VISIBLE JUST MOVES THE SEAM. Measured: the far
-- wall and the near sheet, both unlit and both written the identical Color3, still do
-- not come out the same on screen - the far one is 380 studs out against FogEnd ~375
-- and picks up the tone-mapping differently - so the near sheet's bottom edge drew its
-- own hard line across the water. Extending it to cover the whole column removes the
-- line and ALSO removes every piece of scenery behind z=-42, which is most of it.
-- A transparency ramp is the way out: the sheet dissolves instead of ending, so there
-- is no edge to see whatever is behind it, and the ramp reads as depth haze rather
-- than as a boundary. The UIGradient carries Transparency only - its Color stays white
-- so it never tints the fill.
local function waterSheet(root, name, size, cf, fadeAt)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame = name, size, cf
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow, p.Locked = false, true
	p.Material, p.Transparency = Enum.Material.SmoothPlastic, 1
	local sg = Instance.new("SurfaceGui")
	sg.Name, sg.Face = "Fill", Enum.NormalId.Back
	sg.LightInfluence, sg.AlwaysOnTop = 0, false
	sg.SizingMode, sg.PixelsPerStud = Enum.SurfaceGuiSizingMode.PixelsPerStud, 1
	sg.Parent = p
	local fill = Instance.new("Frame")
	fill.Size, fill.BorderSizePixel = UDim2.fromScale(1, 1), 0
	fill.Parent = sg
	if fadeAt then
		local g = Instance.new("UIGradient")
		g.Rotation = 90   -- canvas top -> canvas bottom, i.e. world up -> world down
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(fadeAt, 0),
			NumberSequenceKeypoint.new(1, 1) })
		g.Parent = fill
	end
	p.Parent = root
	return p, fill
end

function M.build(zid, root)
	zid = M.LINEUP[zid] and zid or 1
	for _, ch in ipairs(root:GetChildren()) do
		if ch:IsA("Folder") or ch:IsA("BasePart") then ch:Destroy() end
	end
	local state = { zone = zid, bands = {}, count = 0 }
	for i, bd in ipairs(M.BANDS) do
		local f = Instance.new("Folder")
		f.Name = string.format("B%d_%s", i, bd.key)
		f.Parent = root
		local t = M.theme(zid, i)
		local c = { f = f, t = t, y0 = bd.y0, y1 = bd.y1, H = bd.y0 - bd.y1, A = {},
			zid = zid, mat = MAT[zid] or MAT[1] }
		;(B[t.kind] or B.rocks)(c)
		state.bands[i] = { folder = f, y0 = bd.y0, y1 = bd.y1, anim = c.A, theme = t }
		state.count += #f:GetDescendants()
	end
	M.recede(state)
	if M.SURFACE_3D then
		local sf = M.buildSurface(zid, root)
		state.surface = sf
		state.count += #sf:GetDescendants()
		M.applySurfaceEnv(zid)
	end
	-- THE MURK WALL. Fog does not touch the skybox, so without something solid out past
	-- FogEnd you look through the gaps in the scenery straight at the sky. This wall is
	-- always further away than the fog reaches, so it renders as pure water colour.
	local murk, murkFill = waterSheet(root, "MurkWall", Vector3.new(460, 400, 3),
		CFrame.new(0, -200, Z_MURK))
	state.murk, state.murkFill = murk, murkFill

	-- AND A SECOND, NEAR ONE.
	--
	-- WARNING: THE FAR WALL CANNOT HIDE THE PAINTED SURFACE PANELS, BECAUSE IT IS BEHIND
	-- THEM. While SURFACE_3D is off those panels (Zone1.Horizon and ZoneBackdrops) are
	-- still the above-water scenery, and they are not surface-only: measured, every one
	-- of them hangs from y=+24/+68 down to y=-46 (the far ones to -52) at z=-45..-115.
	-- So the first ~50 studs of EVERY dive, in every zone, had a painted SEA BAND drawn
	-- in front of the water, ending in a hard horizontal seam straight across the play
	-- area - the most prominent thing underwater after the scenery itself, and the reason
	-- the shallows looked like two different oceans stacked on each other. Confirmed by
	-- switching the three SurfaceGuis off and re-capturing: the seam vanished.
	-- Hiding the panels outright is not an option (they ARE the surface), so this sheet
	-- sits just in FRONT of the nearest one and covers their underwater skirt.
	-- Spans y +4 .. -76. Solid for the first 70% (down to y -52), which is exactly as far
	-- as the deepest painted panel reaches, then ramped away to nothing by -76. The ramp
	-- lands inside the top of the kelp band, where the band's own art breaks it up, and
	-- the tallest stalks are capped at -66 so they are veiled by it rather than cut.
	local skirt, skirtFill = waterSheet(root, "NearMurk", Vector3.new(300, 80, 0.6),
		CFrame.new(0, -36, Z_SKIRT), 0.70)
	state.skirt, state.skirtFill = skirt, skirtFill

	return state
end

-- Set_Particles gates the emitters; Set_WaterFX gates the MOTION but leaves the
-- structure standing. The scenery IS the environment - hiding it would delete the
-- feature rather than cheapen it.
function M.setParticles(state, on)
	for _, b in ipairs(state.bands) do
		for _, d in ipairs(b.folder:GetDescendants()) do
			if d:IsA("ParticleEmitter") then d.Enabled = on end
		end
	end
end

local NEAR = 230   -- studs either side of the camera a band keeps animating

----------------------------------------------------------------------
-- ABOVE THE WATERLINE
--
-- The painted ZoneBackdrops were three flat SurfaceGui panels per zone carrying a sky
-- gradient, a horizon and a sea band. Everything below is real geometry instead, which
-- buys the one thing the painted version could never have: the sea is an actual plane
-- running to an actual horizon, so islands sit ON it at their true distance and the
-- perspective is real rather than hand-drawn.
--
-- ⚠️ GameClient's camera is perfectly level (lookAt from (0,camY,+d) to (0,camY,0)), so
-- the horizon lands exactly on the screen centre line. Land has to straddle it.
----------------------------------------------------------------------

-- far / mid / near land rings. Aerial perspective is mostly Atmosphere's job now, but
-- the far ring is still pre-lightened toward the sky - haze alone is not enough contrast
-- at these distances, and distant land MUST stay lighter than near land or the depth
-- ordering reads backwards.
-- ⚠️ `spread` MUST BE READ AGAINST clearW, NOT AGAINST THE WHOLE FRAME. Scattering the
-- far ring over +/-760 studs when only the middle +/-260 is ever visible between the HUD
-- panels means two thirds of the landscape is built off screen and the shot reads as
-- empty sea. Tighter spreads and higher counts put the same amount of land where it can
-- actually be seen.
local RINGS = {
	-- ⚠️ `spread` IS MEASURED AGAINST clearW, WHICH IS TINY. At this ring's depth clearW is
	-- only ~236 studs, so a spread of 600 puts two thirds of the landscape out in the
	-- wings where the HUD panels cover it - the shot came back as empty sea with the
	-- islands sitting just off the edge of the visible window. Roughly 1.4x clearW keeps
	-- the bulk of it on screen and still lets some run off the sides for framing.
	{ z0 = -1000, z1 = -1900, hLo = 110, hHi = 300, n = 22, lift = 0.52, spread = 330 },
	{ z0 = -400,  z1 = -820,  hLo = 48,  hHi = 130, n = 16, lift = 0.24, spread = 155 },
	-- ⚠️ The near ring is SMALL. At z=-200 the visible half-height is only 60 studs, so a
	-- 62-stud peak here is a full half-frame of black rock parked in front of everything.
	-- ⚠️ At z=-200 the frame is only ~120 studs wide, and a headland is built ~3.5x its
	-- height across - so hHi=42 here produced a 185-stud island filling the entire shot.
	-- The near ring is pushed back and shrunk.
	{ z0 = -280,  z1 = -430,  hLo = 14,  hHi = 30,  n = 9,  lift = 0.06, spread = 105 },
}

-- name, sea, land, rock, sky-ish haze, cloud cover/colour, land silhouette kind
local SURF = {
	-- ⚠️ DENSITY IS TINY. Roblox's Atmosphere is calibrated for very large worlds: 0.14
	-- over the 1000-1900 studs this landscape occupies dissolved EVERY island completely
	-- into the sky, including the near ring 200 studs away. What is wanted here is a
	-- suggestion of aerial perspective, not weather - 0.03-0.08 is the whole usable range.
	[1] = { sea = 0x2E86B8, land = 0x4C7A50, hazeTo = 0xAECFE4, kind = "hill", dens = 0.05,
	        cloud = { cover = 0.52, col = 0xF2F6FA }, prop = "lighthouse" },
	[2] = { sea = 0x14B4AE, land = 0x3E8F72, hazeTo = 0xBFEFF2, kind = "hill", dens = 0.05,
	        cloud = { cover = 0.38, col = 0xFFFFFF }, prop = "palms" },
	[3] = { sea = 0x2E6E9E, land = 0x5A3A34, hazeTo = 0xFFC08A, kind = "hill", dens = 0.07,
	        cloud = { cover = 0.60, col = 0xFFD2A6 }, prop = "sun" },
	[4] = { sea = 0x6EA8C8, land = 0xBBD6E8, hazeTo = 0xDCEAF6, kind = "peak", dens = 0.08,
	        cloud = { cover = 0.72, col = 0xEAF2FA }, prop = "bergs" },
	-- ⚠️ Zones 5 and 6 run at ClockTime 0 with low Brightness, so their land has to be
	-- lifted well off black or it merges into the night sky and the ridges stop
	-- silhouetting entirely - the same failure the painted backdrops had. Their haze is
	-- also pushed brighter and denser, because the haze IS what the peaks read against.
	-- ⚠️ Density is a fraction, and above ~0.25 land at 600-1900 studs DISSOLVES COMPLETELY
	-- into the haze - zone 6 at 0.40 rendered as an empty red band with the volcanoes
	-- entirely gone. Night zones want their land LIFTED and their haze kept light, not the
	-- other way round.
	[5] = { sea = 0x16294A, land = 0x36466C, hazeTo = 0x3A4E7E, kind = "peak", dens = 0.04,
	        cloud = { cover = 0.30, col = 0x3A4A72 }, prop = "moon" },
	[6] = { sea = 0xA04828, land = 0x7A4630, hazeTo = 0xB04E24, kind = "peak", dens = 0.06,
	        cloud = { cover = 0.66, col = 0x8A3418 }, prop = "volcanoes" },
}
M.SURF = SURF

-- ⚠️ OFF BY DEFAULT, AND THIS IS A DELIBERATE CALL, NOT AN OVERSIGHT.
-- The 3D surface below WORKS - real sea plane to a real horizon, real islands, real
-- aerial perspective - but getting it to read as well as the hand-painted backdrops it
-- replaces needs an art pass this build has not had. The failure mode is specific and
-- repeatable: at this camera (FOV 20, level, 140 studs back) the visible window between
-- the HUD panels is only ~70 studs wide at 350 studs out and ~240 at 1500, so land is
-- either enormous and on top of the boat or scattered into the wings where the HUD eats
-- it, and Atmosphere strong enough to give aerial perspective is also strong enough to
-- dissolve the whole landscape into the sky.
--
-- The painted ZoneBackdrops keep the surface until that is solved. Underwater is
-- unaffected and fully 3D. Flip this to true to build the 3D surface instead.
M.SURFACE_3D = false

local P = {}   -- per-zone hero props

function P.lighthouse(f, s, hx)
	local x, zz = hx, -360
	local rock = h(s.land):Lerp(Color3.new(0, 0, 0), 0.25)
	M.blob(f, Vector3.new(x, 3, zz), Vector3.new(150, 40, 110), rock, Mat.Rock)
	M.blob(f, Vector3.new(x + rr(-40, 40), 8, zz - 30), Vector3.new(90, 30, 70),
		h(s.land), Mat.Grass)
	for k = 1, 5 do   -- banded tower
		M.cyl(f, CFrame.new(x, 20 + k * 9, zz) * CFrame.Angles(0, 0, math.rad(90)),
			9, 15 - k * 1.1, k % 2 == 0 and h(0xE04A3C) or h(0xF4F4F0), Mat.SmoothPlastic)
	end
	-- ⚠️ dimmed: full-white Neon blooms into a solid glowing column that swallows the
	-- whole tower. Neon has to stay at Transparency 0, so darken the COLOUR instead.
	M.cyl(f, CFrame.new(x, 70, zz) * CFrame.Angles(0, 0, math.rad(90)), 8, 12,
		h(0xC49A3A), Mat.Neon).Transparency = 0
	M.cyl(f, CFrame.new(x, 77, zz) * CFrame.Angles(0, 0, math.rad(90)), 4, 15,
		h(0x2E3A44), Mat.SmoothPlastic)
	M.lamp(f, CFrame.new(x, 70, zz + 14), h(0xFFE9A8), 1.6, 90)
end

function P.palms(f, s)
	for i = 1, 7 do
		local zz = rr(-380, -180)
		local x = M.ux() * M.halfW(zz) * 0.95
		local sc = (300 + zz) / 200 + 1.1
		M.blob(f, Vector3.new(x, 1, zz), Vector3.new(rr(50, 110), rr(10, 18), rr(40, 70)),
			h(0xE8D8A8), Mat.Sand)
		for p = 1, rng:NextInteger(1, 3) do
			local px, lean = x + rr(-24, 24), rr(-0.22, 0.22)
			local hgt = rr(20, 34) * sc
			M.post(f, px, 4, zz, hgt, rr(1.4, 2.4) * sc, h(0x6B5238), Mat.Wood, lean)
			for b = 1, 6 do
				local a = (b / 6) * math.pi * 2
				M.box(f, CFrame.new(px - math.sin(lean) * hgt + math.cos(a) * 7 * sc,
					4 + hgt - 1.5, zz + math.sin(a) * 5 * sc)
					* CFrame.Angles(rr(-0.3, 0.3), a, -0.32),
					Vector3.new(rr(11, 17) * sc, 0.7, rr(4, 7) * sc), h(0x2E8A4E), Mat.LeafyGrass)
			end
		end
	end
end

function P.sun(f, s, hx)
	-- ⚠️ The hero celestial must sit inside the clear window between the HUD panels. The
	-- painted version lost zone 3's sun behind MainMenu by parking it at 0.74 of the frame.
	local zz = -1750
	local d = M.cyl(f, CFrame.new(hx * 2.2, 96, zz)
		* CFrame.Angles(0, math.rad(90), 0), 4, 190, h(0xFFC96A), Mat.Neon)
	d.Transparency = 0
end

function P.bergs(f, s)
	for i = 1, 12 do
		local zz = rr(-620, -170)
		local x = M.ux() * M.halfW(zz) * 1.0
		local hgt = rr(16, 52) * (1 + (-zz) / 700)
		M.crystal(f, x, hgt, zz, rr(24, 60), hgt, h(0xE4F2FB), Mat.Glacier, rr(-0.3, 0.3))
		M.box(f, CFrame.new(x, 1, zz) * CFrame.Angles(0, rr(-0.6, 0.6), 0),
			Vector3.new(rr(30, 70), 4, rr(20, 44)), h(0xCFE6F4), Mat.Glacier)
	end
end

function P.moon(f, s, hx)
	local zz = -1800
	local x = hx * 2.5
	local d = M.cyl(f, CFrame.new(x, 150, zz) * CFrame.Angles(0, math.rad(90), 0),
		4, 130, h(0xE8EEFF), Mat.Neon)
	d.Transparency = 0
	-- ⚠️ The crescent carve only works if it matches the SKY behind it - painted the wrong
	-- tone it reads as a hole punched through the moon.
	local carve = M.cyl(f, CFrame.new(x + 34, 160, zz + 3) * CFrame.Angles(0, math.rad(90), 0),
		4, 116, h(0x0A1024), Mat.SmoothPlastic)
	carve.Name = "MoonCarve"
end

function P.volcanoes(f, s, hx)
	-- ⚠️ The hero cone has to land INSIDE the clear window between the HUD panels and low
	-- enough in frame to be seen. Spread across x by more than clearW and the glowing
	-- crater - the entire point of the zone - sits behind MainMenu.
	for i, zz in ipairs({ -1450, -980, -640 }) do
		local sc = 1 - (i - 1) * 0.22
		local x = hx + (i - 2) * M.clearW(zz) * 0.55
		local hgt = rr(150, 215) * sc
		local w = hgt * rr(1.7, 2.4)
		local col = h(s.land):Lerp(h(s.hazeTo), 0.34 * (i == 1 and 1.7 or 1))
		M.spike(f, x, 0, zz, w, hgt, col, Mat.Basalt, rr(-0.05, 0.05), w * 0.7)
		-- ⚠️ CRATER FIT: a spike's half-width at height t is (1-t)*w/2, so a crater wider
		-- than that overhangs the cone and reads as a table balanced on a triangle.
		local ch = hgt * 0.88
		local cw = (1 - 0.88) * w * 0.9
		local cr = M.glow(f, CFrame.new(x, ch, zz + 2), Vector3.new(cw, cw * 0.5, cw * 0.6),
			h(0xFF7A1E))
		M.lamp(f, CFrame.new(x, ch + 8, zz + 12), h(0xFF8A2E), 4.5, 420 * sc)
		-- embers streaming off the cone: the only motion in an otherwise still night sky
		M.emitter(f, Vector3.new(x, ch + 6, zz + 4), Vector3.new(cw, 4, cw),
			{ col = h(0xFFB05A), rate = 22, s0 = 2, s1 = 7, tr = 0.3, spdLo = 8, spdHi = 22,
			  lifeLo = 5, lifeHi = 12, emit = 1, acc = Vector3.new(4, 10, 0), drag = 0.5 })
		-- short, dim lava streaks. Long bright ones read AS the silhouette and turn the
		-- crater into a hat on a neck.
		for k = 1, 4 do
			local side = k % 2 == 0 and 1 or -1
			M.glow(f, CFrame.new(x + side * rr(4, 14) * sc, ch - hgt * 0.11, zz + 3)
				* CFrame.Angles(0, 0, side * rr(0.10, 0.22)),
				Vector3.new(rr(1.5, 3) * sc, hgt * 0.16, 1.5), h(0xC8461A))
		end
		M.emitter(f, Vector3.new(x, ch + 20, zz), Vector3.new(10, 6, 10),
			{ tex = TEX.smoke, col = h(0x4A2A20), rate = 7, s0 = 20, s1 = 90, tr = 0.72,
			  spdLo = 6, spdHi = 16, lifeLo = 10, lifeHi = 20, emit = 0.1,
			  acc = Vector3.new(3, 9, 0), drag = 0.6 })
	end
end

function M.buildSurface(zid, root)
	local s = SURF[zid] or SURF[1]
	local f = Instance.new("Folder")
	f.Name = "Surface"
	f.Parent = root

	-- THE SEA. One big plane running to the horizon, which is the whole point: the painted
	-- version had to draw a separate "sea band" onto each of three panels and fake the
	-- perspective between them.
	-- ⚠️ IT HAS TO REACH PAST THE CAMERA. The camera sits at y=+11, z=+140 looking level
	-- with a 10-degree half-angle, so the ray to the BOTTOM of the frame crosses y=0 at
	-- z=+78 - in front of any plane that starts at z=-10. Ending the sea short of that
	-- left the bottom third of the idle shot looking straight down into the kelp forest.
	-- Built with M.slab so the play-plane guard does not pull it back.
	-- ⚠️ A BasePart is capped at 2048 studs per axis and Roblox clamps SILENTLY - asking
	-- for 9000 x 5000 gave a 2048 x 2048 tile floating in the middle of the ocean with no
	-- error. The sea is a GRID of tiles, sized to cover out to the horizon.
	local TILE = 2000
	for ix = -1, 1 do
		for iz = 0, 3 do
			local t = M.slab(f, CFrame.new(ix * TILE, -0.35, 400 - iz * TILE),
				Vector3.new(TILE + 2, 0.7, TILE + 2), h(s.sea), Mat.SmoothPlastic)
			t.Name = "SeaPlane"
			t.Reflectance = 0.06
		end
	end

	-- ⚠️ KEEP-OUT FOR THE HERO PROP. The near ring runs from z=-165 to -300 with headlands
	-- up to 270 studs across, so it will happily park one in FRONT of the lighthouse and
	-- swallow the tower - which is exactly what happened. Pick the hero's x first and hold
	-- a corridor open for it.
	local heroX = rr(-45, 45)
	for r, R in ipairs(RINGS) do
		for k = 1, R.n do
			local zz = rr(R.z0, R.z1)
			-- biased toward the centre so the clear window gets the density, not the wings
			local u = rr(-1, 1)
			local x = math.sign(u) * (math.abs(u) ^ 1.5) * R.spread
			-- rings 2 AND 3 can both sit in front of a hero prop (zone 6's volcanoes run from
			-- z=-520 back to -1500), so both hold the corridor open
			if r >= 2 and math.abs(x - heroX) < 150 then
				x = heroX + (x < heroX and -1 or 1) * rr(150, 260)
			end
			local hgt = rr(R.hLo, R.hHi)
			local col = h(s.land):Lerp(h(s.hazeTo), R.lift + rr(-0.06, 0.06))
			if s.kind == "peak" then
				M.spike(f, x, -2, zz, hgt * rr(1.3, 2.2), hgt, col,
					zid == 4 and Mat.Glacier or Mat.Rock, rr(-0.06, 0.06))
			else
				-- a rounded headland: an ellipsoid mostly buried in the sea plane
				M.blob(f, Vector3.new(x, hgt * 0.10, zz),
					Vector3.new(hgt * rr(2.6, 4.4), hgt * 1.9, hgt * rr(1.4, 2.4)), col, Mat.Grass)
			end
		end
	end
	if P[s.prop] then P[s.prop](f, s, heroX) end
	return f
end

-- sky / atmosphere / clouds for the ABOVE-water half. Atmosphere was forced to Density 0
-- for the painted backdrops (it bleached the flat panels); with real geometry out at
-- 2000 studs it is the thing that gives aerial perspective, so it comes back on.
function M.applySurfaceEnv(zid)
	local Lig = game:GetService("Lighting")
	local s = SURF[zid] or SURF[1]
	-- create it if it is missing: applyWater unhooks the Atmosphere on every dive (it
	-- would otherwise make Lighting.Fog* a no-op), so surfacing can land here with none
	-- in Lighting at all
	local atm = Lig:FindFirstChildOfClass("Atmosphere")
	if not atm then
		atm = Instance.new("Atmosphere")
		atm.Parent = Lig
	end
	atm.Density = s.dens or 0.05
	atm.Haze    = 0.7
	atm.Glare   = 0
	atm.Color   = h(s.hazeTo)
	atm.Decay   = h(s.hazeTo):Lerp(h(s.sea), 0.35)
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if not clouds then
		clouds = Instance.new("Clouds")
		clouds.Parent = workspace.Terrain
	end
	clouds.Cover, clouds.Density = s.cloud.cover, 0.7
	clouds.Color = h(s.cloud.col)
end

----------------------------------------------------------------------
-- the underwater light rig
--
-- This is what actually sells the 3D, and all three parts of it were learned the hard
-- way in front of the volcano:
--
--  1. ⚠️ AN `Atmosphere` INSTANCE MAKES `Lighting.Fog*` A COMPLETE NO-OP. The first
--     underwater pass had no distance haze whatsoever and it was not obvious why. The
--     Atmosphere is taken OUT of Lighting while submerged and put straight back on
--     surfacing (the instance is kept, not destroyed).
--  2. ⚠️ THE FOG RAMP MUST START AT THE CAMERA PULLBACK, NOT AT ZERO. GameClient parks
--     the camera 140 studs back, so the CLOSEST scenery is already ~160 studs away. A
--     0..240 ramp puts every single object in the far end of the curve and the whole
--     frame flattens into one tone - which is exactly how it rendered.
--  3. ⚠️ UNDERWATER THE ONLY LIGHT IS THE WATER. Zone 6 runs ClockTime 0 with ambient
--     rgb(90,35,20); dark basalt multiplied by that is algebraically black, which is
--     why the painted version looked unlit too. Ambient is driven FROM the water
--     colour, and every molten feature carries a real PointLight (Neon emits no light).
--
-- Surface Lighting belongs to ZonesController, so its values are captured on the way
-- down and handed straight back on the way up rather than being second-guessed.
----------------------------------------------------------------------
local surf = nil

function M.applyWater(zid, camY, col)
	local Lig = game:GetService("Lighting")
	local sub = math.clamp((2 - camY) / 14, 0, 1)   -- 0 at the surface, 1 a dozen studs under

	if sub <= 0.001 then
		-- ⚠️ ZonesController's applyEnv runs on every travel and FORCES Atmosphere Density
		-- to 0 (it had to, for the painted backdrops - haze bleached the flat panels), so
		-- the 3D surface env has to be re-asserted every frame it is in use. Guarded on
		-- Density so it is a no-op almost always.
		if M.SURFACE_3D then
			local atm = Lig:FindFirstChildOfClass("Atmosphere")
			if not atm or math.abs(atm.Density - ((SURF[zid] or SURF[1]).dens or 0.05)) > 0.005 then
				M.applySurfaceEnv(zid)
			end
		end
		if surf then
			Lig.Ambient, Lig.OutdoorAmbient = surf.amb, surf.out
			Lig.Brightness, Lig.ExposureCompensation = surf.bri, surf.exp
			Lig.FogStart, Lig.FogEnd, Lig.FogColor = surf.fs, surf.fe, surf.fc
			if surf.atm then surf.atm.Parent = Lig end
			surf = nil
			-- surfacing hands the sky back its haze; the atmosphere was unhooked on the
			-- way down so that legacy fog could work at all
			if M.SURFACE_3D then M.applySurfaceEnv(zid) end
		end
		return
	end

	if not surf then
		local atm = Lig:FindFirstChildOfClass("Atmosphere")
		surf = { amb = Lig.Ambient, out = Lig.OutdoorAmbient, bri = Lig.Brightness,
			exp = Lig.ExposureCompensation, fs = Lig.FogStart, fe = Lig.FogEnd,
			fc = Lig.FogColor, atm = atm }
		if atm then atm.Parent = nil end   -- kept alive by this reference, just unhooked
	end

	col = col or M.waterAt(zid, camY)
	local deep  = math.clamp(-camY / 660, 0, 1)
	-- WARNING: FogEnd is the strongest figure/ground separator in this rig, because
	-- THE FISH TAKE NO FOG. They sit at z = 0, i.e. 140 studs out, and FogStart is
	-- 150 - so tightening this dissolves the scenery without dimming the one thing
	-- the player is trying to look at. Dialled from M.BACKDROP.fogReach.
	local reach = (470 - 170 * deep) * M.BACKDROP.fogReach     -- clearer near the surface, closing in with depth
	-- ⚠️ THE MURK HAS TO BE CLEARLY BRIGHTER THAN THE ROCK or nothing silhouettes and the
	-- frame turns into one flat tone - the exact failure the painted zone 6 had. 0.12 was
	-- not enough separation once the rock picked up ambient.
	Lig.FogColor = lite(col, 0.26)
	Lig.FogStart = 150                 -- = the camera pullback; see note 2
	-- dividing by `sub` instead of lerping toward a huge number keeps the dive smooth
	Lig.FogEnd = reach / math.max(sub, 0.02)
	-- ⚠️ Ambient well BELOW the fog colour. Lit to roughly the same value as the murk,
	-- near rock and far water converge and the whole frame goes monotone - lift the murk
	-- and drop the ambient and the silhouettes come back.
	-- ⚠️ AND A FLOOR UNDER IT. Deriving ambient from the water works right up until the
	-- water itself is nearly black, at which point the trench gets no light at all and
	-- every silhouette disappears into the background. Never go below a dim neutral.
	local a = dark(col, 0.42)
	a = Color3.new(math.max(a.R, 0.075), math.max(a.G, 0.070), math.max(a.B, 0.085))
	local o = dark(col, 0.26)
	o = Color3.new(math.max(o.R, 0.105), math.max(o.G, 0.100), math.max(o.B, 0.115))
	Lig.Ambient        = surf.amb:Lerp(a, sub)
	Lig.OutdoorAmbient = surf.out:Lerp(o, sub)
	Lig.Brightness     = surf.bri + (1.2 - surf.bri) * sub
	Lig.ExposureCompensation = surf.exp + (0.1 - surf.exp) * sub
end

-- camY -> everything that changes per frame. Returns the band index it settled on.
function M.step(state, camY, t, motion, fogOn)
	for _, b in ipairs(state.bands) do
		if motion and camY < b.y0 + NEAR and camY > b.y1 - NEAR then
			M.stepAnim(b.anim, t)
		end
	end
	local col, idx = M.waterAt(state.zone, camY)

	local murk = state.murk
	if murk then
		-- the wall rides with the camera but its top is pinned at the waterline, so
		-- surfacing never reveals a slab standing in front of the sky
		murk.CFrame = CFrame.new(0, math.min(camY - 120, -200), Z_MURK)
		-- the same colour the near sheet gets, so the two read as ONE field of water.
		-- This is FogColor by construction (applyWater sets it from the same expression),
		-- which is what the wall was always meant to render as.
		local mf = state.murkFill
		if mf then
			mf.BackgroundColor3 = lite(col, 0.26)
			local want = camY < 6 and 0 or 1
			if mf.BackgroundTransparency ~= want then mf.BackgroundTransparency = want end
		end
	end

	local skirt = state.skirt
	if skirt then
		-- the colour the FAR wall actually renders as. The murk sits past FogEnd so it
		-- comes out pure fog colour whatever its own Color3 is, while this sheet is only
		-- ~14% fogged at 182 studs. Painting it the fog colour lands both on the same
		-- value, which is what makes the join between them invisible.
		local fill = state.skirtFill
		if fill then
			fill.BackgroundColor3 = lite(col, 0.26)
			-- WARNING: CROSS-FADE, DO NOT POP. The murk can hard-switch at camY 6 because
			-- it is 400 studs away and covers the frame either way; this sheet is 42 studs
			-- behind the boat, so a hard switch is a visible flash across the whole frame
			-- every time a cast starts. The camera crosses this range in under a second.
			fill.BackgroundTransparency = math.clamp((camY + 6) / 12, 0, 1)
		end
	end

	if fogOn then M.applyWater(state.zone, camY, col) end
	return idx
end

return M
