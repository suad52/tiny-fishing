--[[
	GameClient — the actual 2.5D Tiny-Fishing loop (zone 1).

	SIDE-ON 2.5D SETUP
	  Everything playable lives on the plane Z = 0. The camera sits far back on +Z
	  looking down -Z with a NARROW FOV — that's the trick that fakes orthographic:
	  at FOV 10 / ~290 studs back, the island at Z=-216 is only ~1.7x further than
	  the boat, so it stays big and reads as a backdrop instead of shrinking into
	  the distance. A wide FOV up close would make the island a distant speck.
	  Screen X = world X, screen Y = world Y.

	  camera(+Z) ---> boat & fish (Z=0) ---> water backdrop (Z=-3) ---> island (Z=-108)

	THE LOOP  (modelled on Tiny Fishing)
	  click -> the hook is thrown down and sinks fast to your MaxDepth. Nothing is
	  caught on the way down — the descent just buys you depth.
	  at max depth the line reels back up, slower, and THAT is the catching pass:
	  steer left/right with the mouse to sweep fish onto the hook, up to capacity.
	  back at the surface the haul pays out: each fish is flung up into the air with
	  a +$ pop and the money counter ticks up, one fish at a time.

	STATE
	  MaxDepth / HookCapacity are player attributes so the Upgrades tree can raise
	  them later. Catches report into the systems already built:
	    QuestsMenu.Report ("cast" / "catch" / "depth" / "rare" / "legendary" / "earn")
	    InventoryMenu.AddCatch (fish name -> the bucket / Index)
--]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UIS               = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local plr = Players.LocalPlayer
local pg  = plr:WaitForChild("PlayerGui")
local cam = workspace.CurrentCamera

local FishData   = require(ReplicatedStorage:WaitForChild("FishData"))
local FishModels = ReplicatedStorage:WaitForChild("FishModels")
-- One local, deliberately: this chunk sits just under Luau's 200-local ceiling (see the
-- FX note below), so the audio layer gets a single handle and everything goes through it.
local Audio      = require(ReplicatedStorage:WaitForChild("Audio"))
-- Same rule: ONE handle for the touch layer. It gives the on-screen buttons a 44px hit
-- area on phones, and TouchKit.wanted() is also what decides whether the hint says "Tap"
-- or "Click" - inlined at its two call sites rather than kept in a local, for the ceiling.
local TouchKit   = require(ReplicatedStorage:WaitForChild("TouchKit"))

----------------------------------------------------------------------
-- tuning
----------------------------------------------------------------------
local PLAY_Z        = 0
local WATER_Y       = 0
local TARGET_VIEW_W = 92      -- studs visible across the play plane (boat is 16.4)
local CAM_FOV       = 20      -- narrow = fake orthographic = island stays big
local MAX_CAM_DIST  = 140     -- never sit far enough back for Roblox to cull the island
-- At rest the camera rides ABOVE the waterline so the sea is only a strip along the
-- bottom (~26%) and the boat + island carry the frame. The visible half-height is
-- 130*tan(FOV/2) = 22.9, so the waterline (y=0) lands at 0.5 + IDLE_CAM_Y/45.85
-- down the screen - raise this and you see less water, lower it and you see more.
local IDLE_CAM_Y    = 11
local PLAY_CAM_Y    = -13     -- once you cast it drops to the fishing framing
local CAM_LEAD      = 9       -- REELING: the camera rides this far ABOVE the hook, so the water it climbs into is in shot
local SINK_LEAD     = 4       -- SINKING: the hook rides this far ABOVE centre, so you see what it is diving into

-- THE PLUNGE. The drop is a straight, committed dive: you aim it with the cast and
-- have NO steering until it bottoms out. It runs fast, then brakes over the last
-- SINK_BRAKE studs so the handover to the steerable reel reads as the hook settling
-- rather than as an abrupt stop.
local SINK_SPEED      = 132   -- studs/sec down - nothing bites on the drop
local SINK_BRAKE      = 30    -- studs above max depth where it starts slowing
local SINK_BRAKE_MIN  = 0.16  -- floor on the braking factor, so it never crawls
local REEL_SPEED      = 20    -- (2026-10-10, the owner: "a bit slower, it feels really fast": was 26) studs/sec up — slower than the drop, but still brisk: the catching pass
local FULL_REEL_SPEED = 115   -- (was 165, slowed with REEL_SPEED) hook's full, nothing left to catch — bolt for the surface
-- Drag is inherently at its WORST exactly when the hook is full, which used to eat most of
-- the bolt (72 * 0.46 ~ 33, barely above the 26 catching pass) and made a full hook feel
-- slower than an empty one. Cap it low while bolting so the haul always reads as fast;
-- so the bolt always reads as a fast haul rather than a crawl.
local FULL_DRAG_CAP   = 0.22

-- THE CAST. Three beats before the hook ever touches water: the rod sweeps back over
-- the angler's shoulder carrying the hook with it, whips forward, and slings the hook
-- out on an arc into the sea. The rig has ZERO Motor6D joints (it's the newer
-- constraint/AnimationConstraint avatar), so limbs can't be posed the old way — but the
-- Tool hangs off a plain `RightGrip` Weld, and rotating THAT swings the whole 7.8-stud
-- rod without fighting the sit animation. See rodSwing().
-- The ANGLES live in ROD.CAST now, as ABSOLUTE pitch rather than a rotation composed onto
-- whatever the sit animation left. These two only have to agree with that track:
--   CAST_WINDUP = backswing 0.40 + the PAUSE AT THE TOP 0.10
--   CAST_THROW  = 70% of the 0.21s power stroke, so the hook LEAVES at t=0.647 (pitch 60.1)
--                 with 12 degrees of forward sweep still to come. Every instructional source
--                 is unanimous that a spinning reel is released around 11 o'clock and you
--                 then follow through - the old code released at the terminal angle, off a
--                 rod that had already stopped.
-- BOTH ARE STILL READ by the released branch below (castT - CAST_WINDUP - CAST_THROW).
local CAST_WINDUP     = 0.50  -- backswing, then HOLD at the top
local CAST_THROW      = 0.147 -- to the RELEASE point, not to the end of the stroke
local CAST_FLY        = 0.44  -- hook arcs out and splashes down
local CAST_ARC        = 4.5   -- how high the thrown hook bulges over its straight line
local CAST_CLEAR      = 6     -- the hook lands at least this far past the BOW (see bowX)
local SPLASH_GRAV     = 46

-- THE REEL lives in ROD.stepPump now: phase ACCUMULATED (never (reelT*hz)%1, which
-- teleported the pump the instant the hook filled and hz jumped 2.4x), and the load
-- scaling INVERTED - a heavy fish gets slow deep pumps at 0.40Hz, a light hook a quick
-- shallow bob at 0.75Hz. The old 1.35Hz was 0.74s per cycle, about 3x the real cadence,
-- and it sped UP under load.

-- THE SURFACE BREAK. Everything comes out of the water at once here, and the rod used to
-- sit dead still through it — the moment the angler is working hardest was the one moment
-- nothing moved. It now heaves: a fast pull up that drags the strung catch clear of the
-- surface, then a slower settle back to rest. HAUL_LIFT is the line that pull takes in, so
-- the fish rise WITH the rod instead of hanging where the hook happened to stop.
-- (one table, not five locals: this chunk runs within a handful of slots of Luau's
--  200-local ceiling, and five more constants at file scope is enough to blow it)
-- ang/rise/fall moved into ROD (they are absolute pitch keyframes now, not a delta).
-- lift stays: it is a GAMEPLAY number the strung catch rides. trail stays: it is an FX
-- timer. Neither is an angle.
local HAUL = {
	lift  = 3.6,            -- studs of line the heave takes in (scaled by the haul)
	trail = 0.03,           -- seconds between dots on the bait's trail
}

local HOOK_X_RANGE  = 34      -- outer safety cap on steering; the real limit is steerBounds() (stay in open water, not behind the side HUD panels)
local CATCH_R       = 2.6     -- hook<->fish catch radius (plus the fish's own size)

-- HOW THE CATCH RIDES THE LINE. Hooked fish are strung in a column under the bait and
-- follow it up. The follow is an exponential lerp, so its steady-state lag is
-- (hook speed / CATCH_FOLLOW) — which means the faster the reel, the further the catch
-- strings out behind the bait. At the full-hook bolt's ~130 studs/s the old rate of 14
-- left them trailing 9+ studs below it, strung across open water. So the rate is raised
-- AND the offset is hard-clamped: the lerp still smooths small moves, but the catch can
-- never fall further than CATCH_MAX_LAG from its slot no matter how fast the line comes up.
local CATCH_LEAD    = 0.7     -- the first fish sits this far under the bait
local CATCH_STACK_L = 0.42    -- per-fish spacing: this share of the fish's own length...
local CATCH_STACK_P = 0.28    -- ...plus this padding
local CATCH_FOLLOW  = 30      -- how hard a fish is pulled toward its slot
local CATCH_MAX_LAG = 1.1     -- but it is never allowed further than this from it

-- HOW MANY FISH ARE IN THE WATER is a DENSITY, not a count. With the rarity ladder now
-- stretched over ~620 studs, a fixed 52 fish spread down a late-game column left the deep
-- water all but empty. Capped at FISH_MAX so a deep column stays affordable to render,
-- which does mean the deep end is a little sparser per stud than the shallows - that is
-- deliberate, and it is part of what stops a big rod from simply out-earning the curve.
local FISH_PER_STUD = 0.34
local FISH_MIN      = 44
local FISH_MAX      = 96
local function fishTarget(span) return math.clamp(math.floor(span * FISH_PER_STUD), FISH_MIN, FISH_MAX) end
local SPAWN_X       = 58      -- fish wrap outside this

-- ALTERATIONS. Every spawn rolls for a rare finish worth a cash multiple. Rolled
-- rarest-first so the tiers don't shadow each other. Payout/visual ONLY - a shiny Cod
-- is still a Cod to the bucket and the Index, so nothing downstream learns about them.
-- ⚠️ MEASURE THE COMBINED RATE, NOT THE INDIVIDUAL ODDS. These are four INDEPENDENT rolls, so
-- what the player actually sees is 1 - prod(1 - chance). History: 0.004/0.018/0.055/0.030 was
-- 10.3%, cut to 0.0012/0.006/0.025/0.014 = 4.5%, and now cut again to a 1.04% BASE - because a
-- flat rate meant a brand-new player and a fully-kitted one saw exactly the same number of shinies
-- and there was nothing to play towards. The rate is now EARNED: see the luck curve below.
local VARIANTS = {
	{ key = "rainbow", label = "Rainbow", chance = 0.00025, mult = 25, tint = Color3.fromRGB(255,120,220), neon = true, cycle = true },
	{ key = "gold",    label = "Gold",    chance = 0.0013,  mult = 8,  tint = Color3.fromRGB(255,201,54),  neon = true  },
	{ key = "shiny",   label = "Shiny",   chance = 0.0055,  mult = 3,  tint = Color3.fromRGB(158,238,255), neon = true  },
	{ key = "albino",  label = "Albino",  chance = 0.0030,  mult = 2,  tint = Color3.fromRGB(248,244,236), neon = false },
}
-- LUCK now drives the finish odds, and SUPERLINEARLY on purpose (pow > 1): the first few luck
-- points barely move the needle, so a rare finish stays rare until real progression sits behind
-- it. The permanent ladder is what this is tuned against - upgrades, rod and boat cap the luck
-- sum at 1.53 between them - and the CAP exists so one Leviathan bait (+1000% luck, a
-- consumable) cannot skip the ladder it is supposed to reward.
--   luck 0.00  fresh player          x1.00   combined 1.04%   ~1 fish in 96
--   luck 0.20  a few tiers in        x1.27   combined 1.32%
--   luck 0.50                        x1.84   combined 1.91%
--   luck 1.00                        x3.00   combined 3.06%
--   luck 1.53  permanent maxed       x4.41   combined 4.37%   ~1 in 23
--   luck 3.00+ with a strong bait    x8.00   combined 7.87%   (cap)
-- Rainbow runs 1 in 4,000 at base and 1 in 500 at the cap.
local FINISH_GAIN, FINISH_POW, FINISH_CAP = 2.0, 1.25, 8
-- THE one luck total. Upgrades + rod + boat are PERMANENT and cap at 1.53 between them
-- (UpgLuck 0.60 + RodLuck 0.55 + BoatLuck 0.38); bait and the Luck Potion are consumable and can
-- push it far past that for a while. One function rather than the sum written out at each site,
-- because that has already gone wrong once - StatsHUD's copy of it still omits BoostLuck, so the
-- stats panel does not move when you drink a potion.
local function luckSum()
	return (plr:GetAttribute("UpgLuck") or 0) + (plr:GetAttribute("RodLuck") or 0)
		+ (plr:GetAttribute("BaitLuck") or 0) + (plr:GetAttribute("BoatLuck") or 0)
		+ (plr:GetAttribute("BoostLuck") or 0)
end

local function rollVariant()
	-- Luck Potion also lifts the FINISH odds, and that is deliberate rather than generous: the
	-- luck sum in speciesForDepth cancels wherever only one depth band is in range (see the note
	-- there), so a potion that only fed that sum would do nothing across most of the column. The
	-- finish roll has no such problem - it is a flat per-fish chance - so it is what guarantees
	-- the player can SEE the potion working.
	-- BoostFinish (the Luck Potion, x2) multiplies on TOP of the capped luck curve rather than
	-- being folded under the cap: a potion should scale what you have earned, not stand in for it.
	local k = math.min(FINISH_CAP, 1 + FINISH_GAIN * luckSum() ^ FINISH_POW)
		* (plr:GetAttribute("BoostFinish") or 1)
	for _, v in ipairs(VARIANTS) do
		if math.random() < v.chance * k then return v end
	end
	return nil
end

-- Seconds between fish popping up. This used to be 0.3, which read as a dead beat: the
-- catch cleared the water and then hung motionless waiting its turn (measured: fish 3 sat
-- still for ~0.5s). The freeze is fixed properly by holdPending() below — this is just
-- tightened so the throws land as one continuous ripple rather than three separate events.
local PAYOUT_GAP    = 0.14
-- A paid-out fish is THROWN UP and then FALLS BACK INTO THE BOAT. Peak rise is
-- vy^2/(2*FLY_GRAV) with vy = FLY_UP..FLY_UP+7, so the arc tops out ~7..12 studs above
-- the launch: high enough to read as a throw, and safely under the haul total's text
-- (lower edge y 14.8) so the two never collide. launchFlyer solves the flight time from
-- these and aims the fish at the hull. Re-check if IDLE_CAM_Y / CAM_FOV / TOTAL_Y move.
-- ⚠️ THESE TWO ARE A PAIR — they set the SHAPE and the SPEED of the throw separately,
-- and only one of those is safe to change on its own. Peak rise is vy^2/(2g) and flight
-- time is ~2*vy/g, so scaling vy by k AND g by k^2 leaves the arc pixel-identical while
-- dividing the flight time by k. That is the ONLY knob for "same throw, faster": raising
-- FLY_UP alone lobs the fish up into the haul total, and raising FLY_GRAV alone flattens
-- the arc into a slide. Was 17/20 (a ~1.6-2.4s flight, which read as a slow float);
-- k = sqrt(2) took it to 24/40 for a ~1.1-1.7s throw with the exact same arc.
-- The landing box and vx need no touching — launchFlyer re-solves vx from T every throw.
local FLY_UP        = 24      -- launch speed of a paid-out fish
local FLY_GRAV      = 40      -- gentle arc, but a brisk one
-- Where a thrown fish lands. Measured off the real hull (rim top y 3.75, floor y 1.15):
-- a sight-line raycast from the game camera shows the near gunwale HIDES anything at
-- y <= 2 across x -4..+4, so the fish drops out of sight into the boat on its own and
-- we never see it despawn. The angler sits at x 3.73 — keep landings left of them.
local BOAT_LAND_Y   = 1.3
local BOAT_LAND_X0  = -4.0
local BOAT_LAND_X1  = 2.5

-- Both are the Upgrades-tree attribute PLUS whatever the equipped rod adds. The rod is
-- deliberately the bigger lever on DEPTH, because depth is what gates rarity (see BANDS):
-- buying the next rod is the thing that physically reaches the next class of fish.
-- InventoryController publishes RodDepth / RodCap; see its ROD_STATS table.
-- ⚠️ HARD FLOOR, and it belongs HERE rather than at every writer. Whatever feeds
-- MaxDepth or RodDepth - the upgrade tree, a rod, a rebirth perk, a future server
-- payload, a tampered attribute - the hook must never sink past the painted column
-- (DepthStrata's floor is -660) or the player ends up in an empty black void with
-- fish swimming in nothing. Verified: depth tier 400 used to reach -4120.
-- The legitimate maximum is 620 (branch 320 + rod 300), so 640 leaves headroom
-- without ever leaving the art. Raise DepthStrata's C.BOT before raising this.
local DEPTH_LIMIT = 640
-- BoatDepth is the third contributor (BoatClient publishes it). It sits INSIDE the
-- DEPTH_LIMIT clamp below like everything else, which is the point: a maxed depth branch
-- (320) plus a tier-10 rod (300) is already 620 of the 640 ceiling, so the last boats'
-- depth is partly eaten by the clamp at full endgame and fully effective before that.
-- Raising the ceiling means repainting the water column in BOTH DepthStrata and
-- DeepScenery (their floor is -660), which is why it is not raised here.
local function maxDepth()
	local d = (tonumber(plr:GetAttribute("MaxDepth")) or 120)
		+ (tonumber(plr:GetAttribute("RodDepth")) or 0)
		+ (tonumber(plr:GetAttribute("BoatDepth")) or 0)
	if d ~= d then d = 120 end              -- NaN
	return math.clamp(d, 10, DEPTH_LIMIT)
end
local function capacity()
	-- + the Shop's passes: +1 Hook Slot adds one, Double Catch doubles the lot
	return ((plr:GetAttribute("HookCapacity") or 3) + (plr:GetAttribute("RodCap") or 0)
		+ (plr:GetAttribute("BoatCap") or 0) + (plr:GetAttribute("Pass_slot") == true and 1 or 0))
		* (plr:GetAttribute("Pass_double") == true and 2 or 1)
end
if plr:GetAttribute("MaxDepth") == nil then plr:SetAttribute("MaxDepth", 120) end
if plr:GetAttribute("HookCapacity") == nil then plr:SetAttribute("HookCapacity", 3) end

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

-- Fish lengths span 5cm to 4000cm — a literal scale makes minnows invisible and
-- whales bigger than the boat. Compress it so everything reads between ~2 and 9
-- studs, with size still tracking rarity/length.
local function studLength(cm)
	return math.clamp(1.6 + 2.4 * (cm / 100) ^ 0.45, 1.8, 9)
end

local function comma(n)
	local s = tostring(math.floor(n))
	local k
	repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
	return s
end
local function money(n) return "$" .. comma(n) end

-- Prices match InventoryController's SELL ALL so a fish is worth the same
-- whichever way it leaves the bucket. Keep the two tables in step.
-- 2026-07-18 REBALANCE: payouts were far too generous - one full-depth haul cleared
-- ~$146k, so every price in the game was met in a couple of casts. Bases cut ~9x AND
-- the length term softened from /40 to /70, which bites hardest on the giant Mythics
-- that paid millions off one catch. ~9x less for a small Common, ~19x less for a
-- 4000cm Mythic, so the curve is flatter as well as lower.
-- 2026-07-18 (2) RE-FLATTENED alongside the depth restretch. Rarity is now gated by
-- DEPTH, so the old 1:1900 Common-to-Mythic spread turned the depth ladder into an income
-- CLIFF: measured across the rod tiers it ran $0.007M/hr -> $250M/hr, which made the early
-- game a 40-minute grind for the second rod and the endgame trivial. Note the length term
-- already multiplies a 4000cm Kraken by 58x on its own, so the BASE table does not have to
-- be steep to produce a dramatic ladder. Bases are now 120 * 1.5^rank, which restores both
-- ends of the previously tuned economy (~$0.27M/hr fresh, ~$72M/hr fully maxed) while the
-- depth gating - not poverty - does the pacing. Average values a player actually sees:
-- Common $150 / Uncommon $289 / Rare $596 / Epic $2.6K / Legendary $9.4K / Mythic $53K.
-- ⚠️ PAIRED WITH THE BAND CHANGE BELOW, AND MUST NOT BE RETUNED WITHOUT IT. Making the top
-- tiers 2-4x rarer takes 60-70% of the income out of deep water on its own, because a Mythic was
-- ~20% of catches at 620m and is worth 350x a Common. Raising what the survivors pay is what
-- keeps rarity meaning "valuable" instead of meaning "the game is three times slower". Measured
-- net effect on $/fish: x0.80 / x0.63 / x0.87 at 120m / 320m / 620m.
-- ⚠️ InventoryController has its OWN copy of this table for the bucket price - change both.
local RARITY_BASE = { Common = 120, Uncommon = 180, Rare = 330, Epic = 700, Legendary = 1150, Mythic = 2400 }
local function fishValue(def) return math.floor((RARITY_BASE[def.rarity] or 120) * (1 + def.lengthCm / 70)) end

-- What a fish is worth to the player right now. The popup shown the instant it's
-- hooked and the payout at the surface MUST agree, so both go through here.
local function valueOf(def, vmult)
	return math.floor(fishValue(def)
		* (plr:GetAttribute("ZoneCoinMult") or 1)      -- zone benefit
		* (plr:GetAttribute("BoatCoinMult") or 1)      -- the boat you are sailing
		* (plr:GetAttribute("UpgValueMult") or 1)      -- Fish Value upgrade branch
		-- Bait value applies to the CATCH only. InventoryController's fishValue deliberately
		-- does not carry it: the bait was spent on this cast, not on a later bucket sale.
		* (plr:GetAttribute("BaitValueMult") or 1)
		-- PROGRESSION THAT SURVIVES A REBIRTH. Both are published by RebirthController:
		-- RebirthMult is the "Tide Current" the rank ladder advertises (x1 + 0.25 each
		-- rebirth) and PerkValueMult is the Tide Fortune pearl perk (+8% per tier). Before
		-- 2026-09-03 NOTHING read either of them, so the whole prestige loop - the one thing
		-- that costs you your cash, your upgrade tree and your zones - paid out in numbers
		-- that multiplied nothing. These two are what make income scale with progression
		-- past the point where the depth ladder runs out.
		* (plr:GetAttribute("RebirthMult") or 1)
		* (plr:GetAttribute("PerkValueMult") or 1)
		-- Money Potion. Published by BoostClient, which owns every consumable's duration.
		* (plr:GetAttribute("BoostValueMult") or 1)
		* (vmult or 1))                                -- rare-finish alteration
end

-- Coins live in leaderstats if a real one ever appears, else on a Coins
-- attribute — same convention as the Quests/Inventory controllers.
local function coinSource()
	local stats = plr:FindFirstChild("leaderstats")
	local m = stats and (stats:FindFirstChild("Money") or stats:FindFirstChild("Cash"))
	if m and m:IsA("ValueBase") then return m end
	return nil
end
local function getCoins()
	local m = coinSource()
	if m then return m.Value end
	return plr:GetAttribute("Coins") or 0
end
local function addCoins(n)
	local m = coinSource()
	if m then pcall(function() m.Value = m.Value + n end)
	else plr:SetAttribute("Coins", getCoins() + n) end
end

-- DEPTH IS THE GATE, and it is the whole progression: a rarity only exists inside its
-- own band, so the only way to meet better fish is to reach deeper water.
--
-- 2026-07-18 RESTRETCH. The old ladder ran Common -4..-34 through Mythic -160..-240 -
-- which put the LEGENDARY band at -110, inside the 120 studs a brand-new player reaches
-- on their very first cast with the starter rod. Epic was ~75% of draws at the bottom of
-- that cast. Good fish arrived in the first minute, and the cost curve behind them (zones,
-- upgrades, rods) was met almost immediately. The ladder now spans ~620 studs, and no
-- rod-1 player can reach past Uncommon: depth has to be BOUGHT, through the Line Depth
-- branch and above all through better rods (ROD_STATS in InventoryController).
-- ⚠️ WHAT MAKES A RARITY COMMON HERE IS THE GEOMETRY, NOT THE WEIGHT. A band only competes
-- where it OVERLAPS another one; wherever a stretch of water has exactly one band in range, the
-- pool is all that rarity and the weights cancel out completely. Measured on the old extents:
-- 434 of 618 studs (70%) were single-band, including a 140-stud Mythic-ONLY tail below -480 -
-- which is why one catch in five at max depth was the Kraken, whatever its 0.9 weight said.
--
-- Each band's TOP edge is unchanged, so WHERE a rarity becomes possible - the whole depth-gate
-- progression - is exactly as it was. Only the TAILS are longer, and Legendary now reaches the
-- floor so no water is Mythic-only. Measured: Mythic at 620m 19.9% -> 4.5%, Epic at 320m
-- 33.4% -> 17.0%. Mythic's weight is raised because it now has to compete down there at all.
local BANDS = {
	Common    = { -2,   -160 },
	Uncommon  = { -30,  -230 },
	Rare      = { -100, -320 },
	Epic      = { -190, -440 },
	Legendary = { -320, -620 },
	Mythic    = { -450, -620 },
}
local BAND_WEIGHT = { Common = 60, Uncommon = 34, Rare = 16, Epic = 7, Legendary = 2.4, Mythic = 4.0 }
-- A band does not switch on at full strength the instant you cross its top edge - it
-- RAMPS IN over the first BAND_LEAD studs. Without this, nicking the top of a band by a
-- few studs immediately floods the pool with it, which is the other half of why good fish
-- used to show up so early. At LEAD 70 / RAMP 1.8 a player 10 studs into the Rare band
-- draws Rare about 1.4% of the time, so an early Rare is a genuine surprise; 70 studs in,
-- it is the normal catch.
local BAND_LEAD = 70
local BAND_RAMP = 1.8
-- how far up the rarity ladder each band sits - the Luck branch scales weight by this
local RARITY_RANK = { Common = 0, Uncommon = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }

local byRarity = {}
for _, f in ipairs(FishData.fish) do
	byRarity[f.rarity] = byRarity[f.rarity] or {}
	table.insert(byRarity[f.rarity], f)
end

-- pick a species that belongs at this depth
local function speciesForDepth(y)
	local pool = {}
	-- the Luck branch, the equipped rod and the equipped bait all stack into one number
	-- ⚠️ JACKPOT CAST CANNOT BE DELIVERED BY TILTING THESE WEIGHTS, and that is why it does not
	-- try. Within one band every species carries the SAME w and the pool is normalised by the
	-- total below, so the (1 + luck * rank) factor CANCELS EXACTLY wherever only one band is in
	-- range - which is 438 of the column's 620 studs. "1000x luck" fed through the sum would do
	-- nothing at all for most of a cast. So a jackpot does not tilt the pool: it takes the best
	-- band actually available at this depth, which is the promise the blurb makes.
	if plr:GetAttribute("JackpotActive") then
		local bestRank, bestRarity = -1, nil
		for rarity, band in pairs(BANDS) do
			if y <= band[1] and y >= band[2] then
				local rk = RARITY_RANK[rarity] or 0
				if rk > bestRank then bestRank, bestRarity = rk, rarity end
			end
		end
		local list = bestRarity and byRarity[bestRarity]
		if list and #list > 0 then return list[math.random(1, #list)] end
	end
	local luck = luckSum()
	for rarity, band in pairs(BANDS) do
		local hi, lo = band[1], band[2]
		if y <= hi and y >= lo then
			-- how far past this band's top edge we are, 0 -> 1 over BAND_LEAD studs
			local t = math.clamp((hi - y) / BAND_LEAD, 0, 1)
			local w = (BAND_WEIGHT[rarity] or 1) * (t ^ BAND_RAMP)
			-- Luck tilts the pool toward the rare end: the bonus scales with how far up the
			-- ladder a band sits, so it compounds into a real shift at Mythic while never
			-- making Commons impossible to draw.
			w = w * (1 + luck * (RARITY_RANK[rarity] or 0))
			if w > 0 then
				for _, f in ipairs(byRarity[rarity] or {}) do pool[#pool+1] = { f = f, w = w } end
			end
		end
	end
	if #pool == 0 then
		local c = byRarity.Common
		return c[math.random(1, #c)]
	end
	local total = 0
	for _, e in ipairs(pool) do total += e.w end
	local r = math.random() * total
	local acc = 0
	for _, e in ipairs(pool) do
		acc += e.w
		if r <= acc then return e.f end
	end
	return pool[#pool].f
end

----------------------------------------------------------------------
-- stage refs
----------------------------------------------------------------------
local zone = workspace:WaitForChild("Zone1")
local boat = workspace:WaitForChild("Rowboat")

local fishFolder = workspace:FindFirstChild("LiveFish")
if fishFolder then fishFolder:Destroy() end
fishFolder = make("Folder", { Name = "LiveFish" }, workspace)

----------------------------------------------------------------------
-- camera
----------------------------------------------------------------------
local function camDistance()
	local vp = cam.ViewportSize
	local aspect = vp.X / math.max(vp.Y, 1)
	local halfH = (TARGET_VIEW_W / 2) / aspect
	return math.min(halfH / math.tan(math.rad(CAM_FOV / 2)), MAX_CAM_DIST)
end

-- what the play plane ACTUALLY spans once the clamp bites; steering reads off this
local function viewWidth()
	local vp = cam.ViewportSize
	local aspect = vp.X / math.max(vp.Y, 1)
	return 2 * camDistance() * math.tan(math.rad(CAM_FOV / 2)) * aspect
end

-- Keep the hook in the OPEN WATER between the two edge HUD panels. The BaitRoller hugs
-- the left edge and the MainMenu bar the right; steering the reel behind either would
-- hide the line and its +$ tags. We read the LIVE panels (not a guessed pixel count) so
-- this tracks their real size and even widens if a panel is hidden. Converted px->world
-- every call because viewWidth and the viewport both change with window size / aspect.
-- Falls back to +/-HOOK_X_RANGE (the outer safety cap) until a panel has rendered.
local STEER_PAD = 16   -- stay this many px clear of a panel edge instead of flush to it
local function edgePanel(guiName, frameName)
	local scr = pg:FindFirstChild(guiName)
	if not (scr and scr.Enabled) then return nil end
	local f = scr:FindFirstChild(frameName)
	if f and f.Visible and f.AbsoluteSize.X > 4 then return f end
	return nil
end
local function steerBounds()
	local vp = cam.ViewportSize
	local vw = viewWidth()
	local function toWorld(px) return (px / math.max(vp.X, 1) - 0.5) * vw end
	local leftPx, rightPx = 0, vp.X
	local lp = edgePanel("BaitRoller", "Panel")
	if lp then leftPx = lp.AbsolutePosition.X + lp.AbsoluteSize.X + STEER_PAD end
	local rp = edgePanel("MainMenu", "MenuBar")
	if rp then rightPx = rp.AbsolutePosition.X - STEER_PAD end
	local minX = math.max(toWorld(leftPx), -HOOK_X_RANGE)
	local maxX = math.min(toWorld(rightPx), HOOK_X_RANGE)
	if minX > maxX then local m = (minX + maxX) * 0.5; return m, m end  -- panels overlap: pin centre
	return minX, maxX
end

local camY = IDLE_CAM_Y
local function applyCamera()
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = CAM_FOV
	local d = camDistance()
	cam.CFrame = CFrame.lookAt(Vector3.new(0, camY, PLAY_Z + d), Vector3.new(0, camY, PLAY_Z))
end
applyCamera()

----------------------------------------------------------------------
-- hook + line
----------------------------------------------------------------------
local hook = make("Part", {
	Name = "Hook", Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 1.1, 1.1),
	Color = Color3.fromRGB(228, 56, 56), Material = Enum.Material.SmoothPlastic,
	Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
	CastShadow = false, Transparency = 1,
	CFrame = CFrame.new(0, WATER_Y, PLAY_Z),
}, zone)
local hookBand = make("Part", {
	Name = "HookBand", Shape = Enum.PartType.Ball, Size = Vector3.new(1.14, 0.5, 1.14),
	Color = Color3.fromRGB(250, 250, 250), Material = Enum.Material.SmoothPlastic,
	Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
	CastShadow = false, Transparency = 1,
}, zone)
local hookAtt = make("Attachment", { Name = "HookAtt" }, hook)

-- Segments 4 was two bugs at once. A Beam is a CUBIC BEZIER, and a 4-segment cubic is a
-- 4-gon polyline that cannot render a sag at all. Separately, Roblox divides Segments by a
-- static integer at low graphics quality, and a beam whose reduced count falls under the
-- visibility threshold does not render AT ALL - so the fishing line may be INVISIBLE on
-- minimum settings today. 16 fixes both. Attachment0/1 are assigned by ROD.onBind.
local line = make("Beam", {
	Name = "Line", Attachment1 = hookAtt,
	Width0 = 0.10, Width1 = 0.055, FaceCamera = true, Segments = 16,
	Color = ColorSequence.new(Color3.fromRGB(240, 240, 226)),
	Transparency = NumberSequence.new(1),
	Enabled = false,
}, hook)

-- The rod tip is ROD.tipPos now: solved ANALYTICALLY from the commanded pose rather than
-- read back off Tip.LineOrigin.WorldPosition. A Weld's C0 written in RenderStepped is not
-- solved until AFTER the frame renders, so a read-back is one frame stale - 0.9 studs
-- (~15px) of hook-to-tip detachment during the whip. It is also cheaper (no instance
-- lookup) and correct on the frame a rod tier is swapped.

----------------------------------------------------------------------
-- the bait lantern - dark zones only
----------------------------------------------------------------------
-- Zone 5 "Midnight Trench" is painted near-black, so a bait dropped into it just
-- disappears. There the hook carries its own lamp: a real PointLight (so the hull,
-- the line and any fish that swims past are genuinely lit by it) plus an unlit
-- billboard halo so the bait itself is the brightest thing on screen.
-- LightInfluence = 0 on the halo - it must not be dimmed by the darkness it exists
-- to cut through. BillboardGui Size SCALE is measured in studs, not pixels: use
-- fromScale here or the halo shrinks to nothing at the camera's 140+ stud distance.
-- What colour the lamp burns in each zone. This table is NO LONGER the gate.
-- It used to be: only zones 5 and 6 were dark enough to need a lamp. Since
-- DepthStrata, EVERY zone goes near-black at the Glowfield (-330) and below, so
-- the gate is now DEPTH (see LAMP_DEPTH_Y) and this is only the palette.
-- ⚠️ A lamp must out-VALUE its background, not match its hue - z6's water is
-- already orange and an amber lamp vanished into it, hence white-gold there.
local ZONE_LAMPS = {
	[1] = Color3.fromRGB(150, 226, 255),   -- Lighthouse Cove: cold blue-white
	[2] = Color3.fromRGB(190, 255, 246),   -- Tropical Reef: pale aqua
	[3] = Color3.fromRGB(255, 236, 190),   -- Sunset Bay: warm cream
	[4] = Color3.fromRGB(214, 246, 255),   -- Frostbite Fjord: icy white
	[5] = Color3.fromRGB(150, 226, 255),   -- Midnight Trench: cold moonlit white
	[6] = Color3.fromRGB(255, 240, 196),   -- Molten Abyss: white-hot gold
}
-- Below this the water is dark enough that an unlit bait simply disappears. It is
-- the top of the Glowfield stratum - keep it in step with DepthStrata's STRATA.
local LAMP_DEPTH_Y = -330
local LAMP_COLOR = ZONE_LAMPS[5]
local HALO_STUDS = 9

local baitLamp = make("PointLight", {
	Name = "BaitLamp", Color = LAMP_COLOR, Brightness = 4, Range = 32,
	Shadows = false, Enabled = false,
}, hook)

local halo = make("BillboardGui", {
	Name = "BaitHalo", Size = UDim2.fromScale(HALO_STUDS, HALO_STUDS),
	LightInfluence = 0, AlwaysOnTop = false, Enabled = false,
}, hook)
local haloRings = {}
for i, spec in ipairs({ {1.00, 0.88}, {0.62, 0.68}, {0.34, 0.34}, {0.15, 0.00} }) do
	local f = make("Frame", {
		Name = "Ring" .. i, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(spec[1], spec[1]),
		BackgroundColor3 = (i >= 3) and Color3.fromRGB(238, 253, 255) or LAMP_COLOR,
		BackgroundTransparency = spec[2], BorderSizePixel = 0, ZIndex = i,
	}, halo)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
	haloRings[i] = { f = f, a0 = spec[2] }
end

-- lampDark: zones 5 and 6 are dark from the surface; everywhere else the lamp
-- comes on once the hook sinks past LAMP_DEPTH_Y.
local lampZoneOK, lampCast, lampDark = false, false, false
local function refreshLamp()
	local on = lampCast and (lampZoneOK or lampDark)
	baitLamp.Enabled = on
	halo.Enabled = on
end
local function applyZoneLamp()
	local z = plr:GetAttribute("CurrentZone") or 1
	local c = ZONE_LAMPS[z] or ZONE_LAMPS[1]
	lampZoneOK = (z == 5 or z == 6)
	baitLamp.Color = c
	for i, r in ipairs(haloRings) do
		r.f.BackgroundColor3 = (i >= 3) and c:Lerp(Color3.new(1, 1, 1), 0.72) or c
	end
	refreshLamp()
end
plr:GetAttributeChangedSignal("CurrentZone"):Connect(applyZoneLamp)
applyZoneLamp()

-- Breathe, and burn brighter the deeper it goes: down in the trench the lamp is the
-- only thing on screen, so it has to carry the frame on its own.
RunService.RenderStepped:Connect(function()
	-- Evaluate the depth gate BEFORE the early-return, or the lamp could never switch
	-- itself on - it would be waiting on a check that only runs while it is already on.
	local dark = hook.Position.Y <= LAMP_DEPTH_Y
	if dark ~= lampDark then lampDark = dark; refreshLamp() end
	if not baitLamp.Enabled then return end
	local breathe = 0.5 + 0.5 * math.sin(os.clock() * 2.1)
	local depth   = math.clamp((WATER_Y - hook.Position.Y) / 90, 0, 1)
	baitLamp.Brightness = 3.6 + 1.8 * depth + 0.5 * breathe
	baitLamp.Range      = 30 + 12 * depth
	local s = HALO_STUDS * (1 + 0.07 * breathe + 0.10 * depth)
	halo.Size = UDim2.fromScale(s, s)
	for i, r in ipairs(haloRings) do
		local amp = (i <= 2) and 0.12 or 0.05
		r.f.BackgroundTransparency = math.clamp(r.a0 - amp * breathe, 0, 1)
	end
end)

-- Roblox attribute names allow only [A-Za-z0-9_] and several baits have spaces
-- ("Golden Roe", "Leviathan Bait"), so the store key is the stripped name.
-- InventoryController and RollerController strip it exactly the same way - keep all three
-- in step or the counts silently diverge. Declared up here because BOTH refreshHUD and
-- consumeBait use it and they sit far apart further down.
local function baitKey(n) return (string.gsub(n, "[^%w]", "")) end

-- THE BAIT ON THE HOOK. The bobber is the red thing the player actually watches, and the
-- bait is literally what is on it - so the equipped bait rides there as a rarity-tinted
-- disc carrying the bait's emoji, hanging just off the bobber.
-- WARNING: BillboardGui Size SCALE is measured in STUDS, not pixels. The camera sits 130+
-- studs back, so an Offset-sized tag renders as a speck - same trap as the payout labels
-- and the bait halo above. AlwaysOnTop so the sea and passing fish never swallow it.
local baitTag = make("BillboardGui", {
	-- Sits DIRECTLY ABOVE the bobber, riding the line. Up is the only reliably clear
	-- direction: caught fish stack BELOW the hook and each carries its own "+$N" tag, and
	-- at an up-RIGHT offset the disc landed straight on top of that tag the moment a fish
	-- was hooked. Nothing else occupies the line above the bobber.
	Name = "BaitTag", Size = UDim2.fromScale(2.9, 2.9),
	-- Measured, not guessed: at +2.7 the disc's bottom edge cleared the price tag of a
	-- fish on the hook by only 6.6px. +3.4 puts that gap at ~19px at 17.1 px/stud.
	StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0),
	LightInfluence = 0, AlwaysOnTop = true, Enabled = false,
}, hook)
local baitDisc = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BorderSizePixel = 0, ZIndex = 2,
}, baitTag)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, baitDisc)
make("UIStroke", { Color = Color3.fromRGB(8, 22, 44), Thickness = 3,
	LineJoinMode = Enum.LineJoinMode.Round }, baitDisc)
local baitIconLbl = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.74, 0.74), BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne, TextScaled = true, Text = "", ZIndex = 3,
}, baitTag)

-- Shown only when a bait is equipped AND the hook is actually in the water: an empty
-- bobber has no bait on it, and the tag would otherwise hang in mid-air at the rod tip.
local function refreshBaitTag()
	local name = plr:GetAttribute("EquippedBait")
	local icon = plr:GetAttribute("BaitIcon")
	local on = lampCast and name ~= nil and name ~= "" and icon ~= nil and icon ~= ""
	baitTag.Enabled = on
	if on then
		baitIconLbl.Text = icon
		baitDisc.BackgroundColor3 = plr:GetAttribute("BaitTint") or Color3.fromRGB(255, 255, 255)
	end
end

local function setHookVisible(v)
	hook.Transparency = v and 0 or 1
	hookBand.Transparency = v and 0 or 1
	line.Enabled = v
	line.Transparency = NumberSequence.new(v and 0.1 or 1)
	lampCast = v
	refreshLamp()
	refreshBaitTag()
end

----------------------------------------------------------------------
-- casting: swinging the rod, and the splash it lands in
----------------------------------------------------------------------
local function easeOutCubic(p) local u = 1 - p; return 1 - u*u*u end
-- The rod poser used to live here. It is now ROD, declared just below the state block
-- (search "THE ROD RIG") so it can close over STATE / caught / hookX / line / capacity().
-- A local declared AFTER a function body is not an upvalue of it, so that block cannot
-- move up here. rodSwing composed a rotation onto whatever C0 the weld was authored with,
-- which made the REST pose "whatever the hand happens to be doing" - measured live at
-- 2.5 degrees off horizontal, yawed 34 into the camera. ROD solves the weld for a chosen
-- WORLD-SPACE direction instead.

----------------------------------------------------------------------
-- FX POOL
----------------------------------------------------------------------
-- Splash droplets, surface ripples, bubbles, drips and the streak the bait drags all do
-- the same thing: an anchored part on the play plane that moves, grows, fades and dies.
-- So they share one list and one update pass at the bottom of the render loop, and each
-- spawner below only has to describe its motion.
-- Everything here fades, so nothing here is Neon: a see-through Neon part loses its glow.
-- One table rather than a local per spawner: this chunk sits a few slots under Luau's
-- 200-local ceiling, and nine more file-scope locals overflows it outright.
local FX = {
	list = {},
	max  = 320,   -- ceiling; a stalled frame must not leave hundreds of parts behind
	foam = Color3.fromRGB(232, 252, 255),
}

function FX.spawn(props, m)
	if #FX.list >= FX.max then return end
	local pos = props.CFrame.Position
	m.p, m.t, m.size0 = make("Part", props, zone), 0, props.Size
	m.tr0 = props.Transparency or 0
	m.x, m.y = pos.X, pos.Y
	FX.list[#FX.list + 1] = m
	return m
end

-- Side-on, a ring lying on the water would be seen edge-on and read as nothing at all,
-- so the ripple is two thin bars sliding apart along the waterline instead.
function FX.ripple(x, power)
	for s = -1, 1, 2 do
		FX.spawn({
			Name = "Ripple", Size = Vector3.new(1.6 * power, 0.16, 0.6),
			Color = FX.foam, Material = Enum.Material.SmoothPlastic, Transparency = 0.15,
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
			CastShadow = false, CFrame = CFrame.new(x + s * 0.7, WATER_Y, PLAY_Z),
		}, { vx = s * (6 + 4 * power), vy = 0, life = 0.45 + 0.25 * power, grow = 2.4 })
	end
end

-- Water thrown up where the line breaks the surface — going in on the cast, and coming
-- back out with the haul. `power` scales the whole thing, so a heavy catch makes a mess.
function FX.splash(x, power)
	power = power or 1
	local n = math.floor(9 * math.min(power, 2.2))
	for i = 1, n do
		local a = (i / n) * math.pi * 2
		FX.spawn({
			Name = "Splash", Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.42, 0.42, 0.42) * (0.7 + math.random() * 0.8) * power,
			Color = FX.foam, Material = Enum.Material.SmoothPlastic,
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
			CastShadow = false, CFrame = CFrame.new(x, WATER_Y, PLAY_Z),
		}, {
			vx = math.cos(a) * (2.5 + math.random() * 4) * power,
			vy = (6 + math.random() * 7) * power,
			grav = SPLASH_GRAV, life = 0.45 + 0.2 * power,
		})
	end
	-- The crown: a few tall jets straight up out of the entry point. This is what actually
	-- sells the hit — a ring of droplets on its own just reads as a puff of dust.
	for _ = 1, 3 do
		FX.spawn({
			Name = "Jet", Size = Vector3.new(0.34, 1.5 * power, 0.34),
			Color = FX.foam, Material = Enum.Material.SmoothPlastic, Transparency = 0.1,
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
			CastShadow = false,
			CFrame = CFrame.new(x + (math.random() - 0.5) * 1.6, WATER_Y, PLAY_Z),
		}, {
			vx = (math.random() - 0.5) * 3, vy = (9 + math.random() * 6) * power,
			grav = SPLASH_GRAV, life = 0.4 + 0.15 * power,
		})
	end
	FX.ripple(x, power)
end

-- A bubble off the bait, or off a fish as it's taken. Rises, swells slightly, pops.
function FX.bubble(x, y, r, tint)
	FX.spawn({
		Name = "Bubble", Shape = Enum.PartType.Ball,
		Size = Vector3.new(r, r, r), Color = tint or FX.foam,
		Material = Enum.Material.SmoothPlastic, Transparency = 0.35,
		Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		CastShadow = false, CFrame = CFrame.new(x, y, PLAY_Z),
	}, { vx = (math.random() - 0.5) * 2.4, vy = 3 + math.random() * 4,
	     life = 0.5 + math.random() * 0.5, grow = 0.5 })
end

-- Water shaken off a fish as it's flung into the boat: falls away instead of rising.
function FX.drip(x, y)
	FX.spawn({
		Name = "Drip", Shape = Enum.PartType.Ball, Size = Vector3.new(0.26, 0.26, 0.26),
		Color = FX.foam, Material = Enum.Material.SmoothPlastic, Transparency = 0.2,
		Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		CastShadow = false, CFrame = CFrame.new(x, y, PLAY_Z),
	}, { vx = (math.random() - 0.5) * 6, vy = 2 + math.random() * 4,
	     grav = SPLASH_GRAV, life = 0.5 })
end

-- The streak the bait drags on the way out and on the way down: a fading dot dropped
-- every HAUL.trail seconds, so a fast line reads as fast instead of as a teleport.
function FX.streak(x, y)
	FX.spawn({
		Name = "Streak", Shape = Enum.PartType.Ball, Size = Vector3.new(0.3, 0.3, 0.3),
		Color = FX.foam, Material = Enum.Material.SmoothPlastic, Transparency = 0.5,
		Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		CastShadow = false, CFrame = CFrame.new(x, y, PLAY_Z),
	}, { vx = 0, vy = 0.6, life = 0.28, grow = -0.6 })
end

-- Water thrown off the ROD rather than off the bait: the film on the line and the guides,
-- flicked away by the whip and shaken off when the catch breaks the surface. FX.streak's
-- dot is deliberately static (it reads as a smear along the bait's arc); this one inherits
-- a velocity so it trails the direction the tip was actually moving, which is the whole
-- difference between "a dot appeared" and "the rod threw that".
function FX.tipwash(x, y, vx, vy, r)
	FX.spawn({
		Name = "TipWash", Shape = Enum.PartType.Ball, Size = Vector3.new(r, r, r),
		Color = FX.foam, Material = Enum.Material.SmoothPlastic, Transparency = 0.42,
		Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		CastShadow = false, CFrame = CFrame.new(x, y, PLAY_Z),
	}, { vx = vx, vy = vy, grav = SPLASH_GRAV * 0.55,
	     life = 0.24 + math.random() * 0.12, grow = -0.55 })
end

----------------------------------------------------------------------
-- SWIM - the fish animation. ONE file-scope local; everything else hangs off it.
--
-- THE WHOLE DESIGN IN ONE LINE: at FOV 20 and 140 studs back this camera is
-- near-orthographic, so the ONLY rotation that moves anything on screen is rotation
-- about Z. Yaw is a pure cosine foreshorten (+/-30 deg = 13% length change = 8px on a
-- 60px fish, spread over a whole cycle - invisible). Roll changes a box silhouette by
-- <10% at 25 deg. So every fish is animated as (x, y, thetaZ): a 2D sprite that happens
-- to be built out of 3D parts. A real fish's tail beat is a HORIZONTAL yaw sweep and it
-- is deliberately NOT simulated, because side-on it cannot be seen - which is the same
-- cheat every 2D fish sprite has ever used.
----------------------------------------------------------------------
local SWIM = {
	----- the in-plane rock ---------------------------------------------------
	-- Videler & Hess's carangiform amplitude envelope has its NODE at 0.254 L behind the
	-- nose. A RIGID model rotated about that node reproduces the envelope to first order
	-- FOR FREE - which is why this needs no per-part body deformation at all. The spine we
	-- are not simulating is IMPLIED by rotating about the point it would pivot on.
	NODE    = 0.246,        -- node, measured FORWARD from the bbox centre, in lengths
	TAILARM = 0.746,        -- node -> caudal tip, as a fraction of length
	AMP_PX  = 0.33,         -- exaggeration floor: min tail half-excursion, studs (~6px)
	AMP_LO  = 0.131,        -- rad(7.5): the honest value, asin(0.10 / 0.746)
	AMP_HI  = 0.244,        -- rad(14) cap, or a 40px minnow reads as a windscreen wiper
	----- beat frequency ------------------------------------------------------
	-- U = 0.706*L*f over ~1200 fish and cetaceans, so f = 1.416*U/L. Clamped both ends:
	-- 4.4 Hz on a 40px fish is a buzz, 0.35 Hz on a whale is a stall.
	KF   = 2 * math.pi * 1.416,
	W_LO = 3.77,            -- 0.60 Hz
	W_HI = 16.34,           -- 2.60 Hz
	----- attitude ------------------------------------------------------------
	-- Real fish do NOT point along their path: a swimbladder does the depth work and the
	-- body holds a flatter, slightly nose-up trim. PIT_K < 1 is that fact.
	PIT_K    = 0.70,
	PIT_MAX  = 0.349,       -- rad(20). The raw path angle peaks at 27 deg on a slow deep
	                        -- fish with a big bob, which reads as climbing a hill.
	PIT_DISC = 0.157,       -- rad(9): a pectoral cruiser holds level
	PIT_TRIM = 0.0698,      -- rad(4) nose-up. DELIBERATELY NOT signed by dir - the rock is
	                        -- applied INSIDE the heading flip, so +theta is nose-up for
	                        -- both headings. Signing it would make every left-swimming
	                        -- fish swim nose-DOWN.
	PIT_LAG  = 5,           -- 1/tau, tau = 0.2s. This lag IS the follow-through; without
	                        -- it the heading snaps and reads as a puppet.
	PIT_LEAD = 0.35,        -- rad of phase the attitude runs AHEAD of the path, so the nose
	                        -- turns into the climb before the body gets there
	----- burst and coast -----------------------------------------------------
	-- A constant-velocity conveyor is the strongest "not alive" cue there is. Real fish
	-- hold tail frequency CONSTANT and modulate the burst:coast ratio, so omega never
	-- moves and one envelope scales speed and amplitude together.
	B_RISE = 0.30,          -- share of the cycle spent accelerating
	B_SPD  = 0.90,          -- speed swing; mean(e)=0.5, so MEAN SPEED IS UNCHANGED
	B_AMP  = 0.82,          -- tail goes nearly still on the coast
	----- caudal fin ----------------------------------------------------------
	-- ⚠️ PER BODY PLAN, and the reason is that the fin is the ONLY motion a DISC or WIDE fish
	-- has. 3.6 studs was set for BCF, where the body already rocks 7.5-10.7 deg and the fin is a
	-- garnish; on a tang or a stingray the body is damped to 2-3 deg deliberately, so gating the
	-- fin on the same length left 21 of 61 species with a measured tail-tip excursion of
	-- 0.05-0.12 studs - one to two pixels. That is the "swims sideways doing nothing" bug.
	-- BCF keeps 3.6 exactly, so none of the 40 species that already read well change at all.
	TAIL_MIN = { 3.6, 2.0, 2.0 },
	-- Sweep is bigger off BCF for the same reason: it is carrying the whole performance. A ray's
	-- trailing whip and a turtle's rear flippers genuinely swing further than a tuna's caudal.
	TAIL_A   = { 0.42, 0.50, 0.55 },   -- rad(24 / 29 / 32) of fin sweep relative to the body
	-- Body rock by body plan. Was a bare 0.30 / 0.15 inline; raised because those produced
	-- 2.3-3.4 deg and 1.1-1.3 deg respectively, which is not "restrained", it is nothing.
	-- Still well under BCF so a tang never reads as a tuna - the plate must not spin.
	MODE_AMP = { 1, 0.45, 0.30 },
	-- ...and a fish with no fin the rig can find has ONLY its body left, so it gets most of the
	-- BCF rock back. Self-targeting: seven species (Angelfish, Betta, Jellyfish, Seahorse,
	-- King Crab, Octopus, Starfish) have no part that passes tailOf's arm test, and this is what
	-- stops them being the new dead set once everything else gains a tail.
	FINLESS  = 0.70,
	TAIL_LAG = 1.55,        -- ~quarter cycle BEHIND the body. This lag is the whole point:
	                        -- a fin moving WITH the body is just a rigid model.
	TAIL_WIN = 0.15,        -- collect parts within this share of length of the rearmost
	TAIL_MAX = 3,           -- a forked tail is two plates; three is the ceiling
	TAIL_ARM = 0.35,        -- studs: minimum fin rear-extent, or the sweep is <6px
	----- hooked --------------------------------------------------------------
	CAUGHT_W = 9,           -- rad/s thrash on the line (~1.4 Hz)
	CAUGHT_A = 0.30,        -- rad(17)
	CAUGHT_K = 3,           -- blend rate from the swim pose into the thrash
	----- culling -------------------------------------------------------------
	TANH  = math.tan(math.rad(CAM_FOV / 2)),
	SLACK = 14,             -- half a fish + max bob + margin; the driver ADDS the measured
	                        -- per-frame camera step on top (see the cull line there)
	cull  = 40,             -- recomputed once a frame in the render loop
	lastCamY = 0,
	YAW_R = CFrame.identity,
	YAW_L = CFrame.Angles(0, math.pi, 0),
}

-- Rotation about the fish's own +Z, applied about a point `n` studs ahead of the pivot
-- along the body axis, in ONE constructor with no multiply:
--   T(n,0,0) * Rz(a) * T(-n,0,0)  ==  Rz(a) with translation (n - n*cos a, -n*sin a, 0)
-- fromMatrix's implied third axis is vX:Cross(vY) = (c,s,0)x(-s,c,0) = (0,0,1). Correct.
function SWIM.rotZ(a, n)
	local c, s = math.cos(a), math.sin(a)
	return CFrame.fromMatrix(Vector3.new(n - n * c, -n * s, 0),
		Vector3.new(c, s, 0), Vector3.new(-s, c, 0))
end

-- Body type, straight off the bounding box buildFish already measures. Every part in
-- every model is named "Part", so shape is the ONLY thing we can classify on.
-- DISC matters: a tang is a flat plate FACING THE CAMERA, and rocking a plate about its
-- own middle reads as a spinning coin, not a fish. Biology agrees - surgeonfish, angels
-- and butterflies are labriform pectoral cruisers and puffers are tetraodontiform; both
-- hold the body LEVEL and only use the tail to bolt.
-- THE `cm` GATE IS LOAD-BEARING, and geometry alone cannot replace it. A shark's
-- BOUNDING BOX includes its dorsal and caudal fins, so all three sharks measure
-- X/Y = 1.23, Z/Y = 0.45 and trip the DISC test - which would make the roster's most
-- powerful swimmers its STIFFEST fish (0.3x rock, 9 deg pitch cap, and no tail wag at all,
-- since the fin rig is mode-1 only). Measured alternatives that do NOT work: a fin-excluding
-- "core" bbox turns Tuna and Salmon into WIDE, and the bbox/core inflation ratio ranks
-- Angelfish (3.91) and Betta (3.17) alongside the sharks (2.99-4.68). The game's own
-- lengthCm separates them outright: every genuine disc fish is <= 120cm (Halibut, a real
-- flatfish) and the sharks are 500-1000cm.
function SWIM.mode(sz, cm)
	local h = math.max(sz.Y, 0.01)
	if sz.Z / h > 1.2 then return 3 end                     -- WIDE: turtle, ray, whale
	if sz.X / h < 1.5 and sz.Z / h < 0.6 and (cm or 0) < 200 then
		return 2                                            -- DISC: tang, angel, puffer
	end
	return 1                                                -- BCF: everything else
end

-- The caudal fin, found WITHOUT names: the rearmost part(s) that are small RELATIVE TO
-- THE MODEL. Must be called AFTER ScaleTo, with the scaled bounding size.
function SWIM.tailOf(m, sz)
	local piv  = m:GetPivot()
	local prim = m.PrimaryPart
	local best, bw, cand = math.huge, 0, {}
	for _, d in ipairs(m:GetDescendants()) do
		-- NEVER the PrimaryPart. GetPivot() IS PrimaryPart.CFrame, so PivotTo derives its
		-- rigid delta from it - bend that part and the next PivotTo carries the bend into
		-- every other part and the model TUMBLES, permanently. Absolute writes protect every
		-- part except this one. A species whose rearmost plate is primary just gets no wag.
		if d:IsA("BasePart") and d ~= prim then
			local q = d.Size
			if math.max(q.X, q.Y, q.Z) < 0.5 * sz.X then
				local lx = piv:ToObjectSpace(d.CFrame).Position.X
				cand[#cand + 1] = { d, lx }
				if lx < best then best, bw = lx, q.X end
			end
		end
	end
	if best == math.huge then return false, false, 0 end
	local hx = best + 0.06 * sz.X   -- hinge at the fin ROOT: a fin swinging about its own
	                                -- middle visibly detaches from the peduncle
	-- The arm is to the fin's rear EXTENT, not to `best` (a part CFrame is its CENTRE and a
	-- caudal plate carries most of its area behind that point). Under TAIL_ARM the sweep is
	-- <6px - don't pay a per-part write for motion nobody can see.
	if (hx - (best - 0.5 * bw)) < SWIM.TAIL_ARM then return false, false, 0 end
	local win = best + SWIM.TAIL_WIN * sz.X
	local parts, poses = {}, {}
	for _, c in ipairs(cand) do
		if c[2] <= win and #parts < SWIM.TAIL_MAX then
			parts[#parts + 1] = c[1]
			poses[#poses + 1] = piv:ToObjectSpace(c[1].CFrame)
		end
	end
	if #parts == 0 then return false, false, 0 end
	return parts, poses, hx
end

-- Speed modulation AND the glide path. Fast in, slow out, smoothstepped so there is no
-- corner in the acceleration. mean(e) = 0.5 by construction, so B_SPD leaves each fish's
-- AVERAGE speed exactly what it was: wrap rate and pool turnover are undisturbed.
-- Runs for EVERY fish, culled or not - the glide path is SIMULATION, not render, because
-- tryCatch's hitbox reads it. placeFish only DRAWS it.
function SWIM.burst(f, dt)
	f.bph += f.bw * dt
	f.yy   = f.y + math.sin(f.bph) * f.bob
	f.bst += f.ibT * dt
	if f.bst >= 1 then f.bst %= 1 end
	local e = f.bst
	e = (e < SWIM.B_RISE) and (e / SWIM.B_RISE) or ((1 - e) / (1 - SWIM.B_RISE))
	e = e * e * (3 - 2 * e)
	if f.mode ~= 1 then e = 0.5 + (e - 0.5) * 0.45 end   -- gliders cruise, they don't bolt
	f.sp = f.speed * (0.55 + SWIM.B_SPD * e)
	return e
end

----------------------------------------------------------------------
-- fish pool
----------------------------------------------------------------------
local fishes = {}

local function buildFish(y)
	local def = speciesForDepth(y)
	local src = FishModels:FindFirstChild(def.model)
	if not src then return nil end
	local m = src:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BillboardGui") or d:IsA("SurfaceGui") then d:Destroy() end
		if d:IsA("BasePart") then
			d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
			d.CastShadow = false
		end
	end
	local _, sz0 = m:GetBoundingBox()
	local longest = math.max(sz0.X, sz0.Y, sz0.Z)
	local want = studLength(def.lengthCm)
	if longest > 0 then pcall(function() m:ScaleTo(want / longest) end) end
	m.Name = def.name

	-- SWIM RIG. Measured ONCE, here, and AFTER ScaleTo - so nothing has to assume whether
	-- ScaleTo scales about GetPivot() or about WorldPivot. Post-scale geometry is
	-- post-scale geometry. Every part in every model is called "Part", so shape is the
	-- only handle we have on anatomy.
	local bb, sz = m:GetBoundingBox()
	local mode = SWIM.mode(sz, def.lengthCm)
	-- The rock node, in PIVOT space. The pivot is neither the nose nor the centre (the
	-- Minnow's sits 0.70 ahead of the bbox centre), so go via the box. Clamped as
	-- insurance: if some model's pivot orientation is NOT aligned with its build axes, an
	-- unclamped node would send the fish orbiting a point off its own body.
	local node = math.clamp(m:GetPivot():ToObjectSpace(bb).Position.X + SWIM.NODE * sz.X,
		-0.6 * want, 0.6 * want)
	local sp = 2.2 + math.random() * 3.4
	if mode == 3 then sp *= 0.75 end
	-- ⚠️ THE FIN IS RIGGED BEFORE THE AMPLITUDE IS CHOSEN, because whether one was found is an
	-- INPUT to that choice: a body plan with nothing to wag has to carry the motion itself.
	local tail, tailP, hx = false, false, 0
	if want >= SWIM.TAIL_MIN[mode] then tail, tailP, hx = SWIM.tailOf(m, sz) end
	-- Honest amplitude is 0.10 L at the tail = 7.5 deg; the AMP_PX floor exaggerates the
	-- small ones because 0.10 L on a 2-stud minnow is 3px, which is unreadable.
	local amp = math.clamp(SWIM.AMP_PX / (SWIM.TAILARM * want), SWIM.AMP_LO, SWIM.AMP_HI)
	amp *= tail and SWIM.MODE_AMP[mode] or math.max(SWIM.MODE_AMP[mode], SWIM.FINLESS)

	-- rare finishes: tint every part toward the variant colour and (for the glowing
	-- tiers) go Neon. Fish parts are opaque so Neon is safe here - a Neon part with
	-- Transparency > 0 loses its glow entirely.
	local variant = rollVariant()
	local vparts = nil
	if variant then
		vparts = {}
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Color = d.Color:Lerp(variant.tint, 0.82)
				if variant.neon then d.Material = Enum.Material.Neon end
				vparts[#vparts + 1] = d
			end
		end
		m.Name = variant.label .. " " .. def.name
	end

	m.Parent = fishFolder
	-- PLACE IT NOW, before a frame can render it. With the render cull in placeFish this
	-- fish may not be DRAWN for minutes, and every master in FishModels sits within ~1 stud
	-- of the origin - which is the WATERLINE AT SCREEN CENTRE, the most visible point in
	-- the frame. An unplaced clone is not "off screen", it is a fish sitting on the surface
	-- in the middle of the shot. Hits the initial spawn, syncFishPool and respawnFish.
	local x0  = math.random(-SPAWN_X, SPAWN_X)
	local dr0 = (math.random() < 0.5) and 1 or -1
	m:PivotTo(CFrame.new(x0, y, PLAY_Z) * ((dr0 > 0) and SWIM.YAW_R or SWIM.YAW_L))
	-- EVERY KEY HERE MUST BE NON-NIL. respawnFish copies with pairs(), which SKIPS NILS, so
	-- a nil key silently leaves the PREVIOUS fish's value in place - and `tail` would then
	-- be a live reference to parts that were just destroyed, which throws on the next
	-- write. That is the exact trap the comment in respawnFish documents for vparts.
	-- Use false / 0, never nil.
	return {
		model = m, def = def, len = want,
		variant = variant, vmult = variant and variant.mult or 1, vparts = vparts,
		x = x0,
		y = y,
		yy = y,                                  -- the live glide path; the HITBOX reads this
		dir = dr0,
		speed = sp,                              -- CRUISE baseline; f.sp is the live one
		phase = math.random() * 6.28,            -- still the rainbow hue's offset
		bob = (0.5 + math.random() * 1.1) * ((mode == 1) and 1 or 1.35),
		caught = false,
		----- swim rig -------------------------------------------------------
		mode = mode,
		node = node,
		amp  = amp,
		-- omega is FIXED for the fish's whole life: real burst-and-coast holds frequency
		-- constant and modulates the duty cycle. The +/-8% jitter is the desync rule from
		-- crowd animation - without it 96 fish of a species tick as one metronome.
		w   = math.clamp(SWIM.KF * sp / want, SWIM.W_LO, SWIM.W_HI)
		      * (0.92 + math.random() * 0.16),
		bw  = (0.45 + math.random() * 0.55) * ((mode == 1) and 1 or 0.62),
		-- INTEGRATED phases. Never sin(w * os.clock()): t is ~1e5 and shared, so any omega
		-- change without a rebuild would teleport the tail.
		ph  = math.random() * 6.28,
		bph = math.random() * 6.28,
		pit = 0,                                 -- lagged attitude
		ang = 0,                                 -- composite angle last written
		sp  = sp,
		bst = math.random(),                     -- burst/coast cursor, 0..1
		ibT = 1 / ((0.9 + 0.22 * want) * (0.8 + math.random() * 0.4)),
		tail = tail, tailP = tailP, hx = hx,
		ta = SWIM.TAIL_A[mode],                  -- fin sweep, resolved once per fish
	}
end

-- ONE PivotTo per fish, exactly as before: the animation lives entirely in the CFrame we
-- hand it, so the BODY costs zero extra writes. The fin is the only per-part work and it
-- is written ABSOLUTELY from `piv`, never from its own current CFrame, so a bend can
-- never accumulate through the rigid PivotTo.
local function placeFish(f, t, dt, e)
	-- CULL THE RENDER, NEVER THE SIMULATION. The caller still advances x, the burst, the
	-- glide path and the wrap for every fish, or the pool stalls at its edges. The camera
	-- follows the hook down a column up to 640 studs deep while the visible band is ~49
	-- studs tall, so this removes 45% (shallow) to 90% (deep) of the loop's work - and it
	-- is what pays for everything below.
	if math.abs(f.y - camY) > SWIM.cull then return end

	-- PIT_LEAD evaluates the derivative slightly AHEAD, so the nose turns into the climb
	-- before the body arrives. That reads as intent; without it, as a puppet on a wire.
	local yy = f.yy
	local vy = f.bw * f.bob * math.cos(f.bph + SWIM.PIT_LEAD)
	-- vy/|vx| instead of atan2: the angle is small and it is clamped and scaled by 0.70
	-- anyway. NOTE there is no `dir` term - pitch depends only on climb rate over ground
	-- speed, and +theta is nose-up for BOTH headings (see the flip below).
	local pmax = (f.mode == 2) and SWIM.PIT_DISC or SWIM.PIT_MAX
	local tgt = math.clamp(SWIM.PIT_K * vy / math.max(f.sp, 0.5), -pmax, pmax)
		+ SWIM.PIT_TRIM
	f.pit += (tgt - f.pit) * math.min(1, dt * SWIM.PIT_LAG)

	-- THE ROCK. Attitude and body beat are the SAME degree of freedom, so they add before
	-- any trig runs: one sin, one cos, one CFrame. Both act about the node 0.254 L behind
	-- the nose, which is what makes a rigid model read as having a spine.
	f.ph += f.w * dt
	local ang = f.pit + f.amp * (0.18 + SWIM.B_AMP * e) * math.sin(f.ph)
	f.ang = ang                                  -- placeCaught blends out of this
	-- models are built length-along-X; flip 180 deg to swim the other way. The rock goes
	-- INSIDE that flip, which is why +ang is nose-up for both headings.
	local piv = CFrame.new(f.x, yy, PLAY_Z)
		* ((f.dir > 0) and SWIM.YAW_R or SWIM.YAW_L)
		* SWIM.rotZ(ang, f.node)
	f.model:PivotTo(piv)

	-- THE CAUDAL FIN, on fish over ~65px only. A quarter cycle BEHIND the body: a fin that
	-- moves with the body is just a rigid model, and a fin that moves while the body is
	-- dead still is the broken case. Recomputed from `piv` and the build-time pose every
	-- frame, so PivotTo cannot carry the bend forward.
	if f.tail then
		local sw = piv * SWIM.rotZ(f.ta * (0.18 + SWIM.B_AMP * e)
			* math.sin(f.ph - SWIM.TAIL_LAG), f.hx)
		local tp = f.tailP
		for i = 1, #f.tail do
			local p = f.tail[i]
			if p.Parent then p.CFrame = sw * tp[i] end
		end
	end

	-- The rainbow tier cycles hue so it reads as special even at this camera distance.
	-- Deliberately still driven by raw `t` and NOT an integrated phase - the opposite of
	-- the rule above: the hue must be a pure function of wall time so a culled rainbow fish
	-- resumes on the colour it WOULD have had, not the one it left on.
	if f.variant and f.variant.cycle and f.vparts then
		local c = Color3.fromHSV((t * 0.35 + f.phase * 0.16) % 1, 0.72, 1)
		for _, p in ipairs(f.vparts) do
			if p.Parent then p.Color = c end   -- a destroyed part would throw here
		end
	end
end

local function respawnFish(f)
	if f.model then f.model:Destroy() end
	local y = -math.random(4, math.max(6, math.floor(maxDepth() * 1.15)))
	local nf = buildFish(y)
	if not nf then return end
	-- pairs() skips nil values, so a plain copy leaves the OLD variant/vparts in place
	-- when the replacement is an ordinary fish - and vparts would then point at parts
	-- we just destroyed, which throws on the next recolour. Clear them explicitly.
	-- SAME TRAP, SAME SHAPE, for the swim rig: buildFish returns tail/tailP as FALSE and hx
	-- as 0, never nil, so they always copy and a stale fin reference is impossible. Any swim
	-- key added later must be non-nil there too, or cleared on this line.
	f.variant, f.vparts, f.vmult = nil, nil, 1
	for k, v in pairs(nf) do f[k] = v end
end

local function fishSpan() return math.max(30, maxDepth() * 1.15) end

-- Restock the sea when the reachable column changes. maxDepth() moves whenever a Line
-- Depth tier is bought or a different rod is equipped, and without this the water a
-- player just paid to reach would be empty. Fish already ON the hook are never culled -
-- the reel holds references to them.
local function syncFishPool()
	local span = fishSpan()
	local want = fishTarget(span)
	local i = #fishes
	while #fishes > want and i >= 1 do
		local f = fishes[i]
		if not f.caught then
			if f.model then f.model:Destroy() end
			table.remove(fishes, i)
		end
		i -= 1
	end
	while #fishes < want do
		local f = buildFish(-(4 + math.random() * span))
		if not f then break end
		fishes[#fishes+1] = f
	end
end

do
	local span = fishSpan()
	local want = fishTarget(span)
	for i = 1, want do
		local y = -(4 + (i - 0.5) / want * span) - math.random(-3, 3)
		local f = buildFish(y)
		if f then fishes[#fishes+1] = f end
	end
end

plr.AttributeChanged:Connect(function(a)
	if a == "MaxDepth" or a == "RodDepth" or a == "BoatDepth" then syncFishPool() end
	-- The landing box is per boat now. These three are ASSIGNED rather than read per throw
	-- because this chunk is a handful of slots off Luau's 200-local ceiling and a new
	-- file-scope local here fails at run time, not in Studio.
	if a == "BoatLandY"  then BOAT_LAND_Y  = tonumber(plr:GetAttribute("BoatLandY"))  or BOAT_LAND_Y  end
	if a == "BoatLandX0" then BOAT_LAND_X0 = tonumber(plr:GetAttribute("BoatLandX0")) or BOAT_LAND_X0 end
	if a == "BoatLandX1" then BOAT_LAND_X1 = tonumber(plr:GetAttribute("BoatLandX1")) or BOAT_LAND_X1 end
end)
-- Seed them once: BoatClient and this script are both StarterPlayerScripts and their start
-- order is not defined, so the publish may already have happened.
BOAT_LAND_Y  = tonumber(plr:GetAttribute("BoatLandY"))  or BOAT_LAND_Y
BOAT_LAND_X0 = tonumber(plr:GetAttribute("BoatLandX0")) or BOAT_LAND_X0
BOAT_LAND_X1 = tonumber(plr:GetAttribute("BoatLandX1")) or BOAT_LAND_X1

----------------------------------------------------------------------
-- HUD  (kept narrow + centred: the BaitRoller owns the left edge and the
--       MainMenu bar owns the right)
----------------------------------------------------------------------
local hud = pg:FindFirstChild("FishingHUD")
if hud then hud:Destroy() end
hud = make("ScreenGui", { Name = "FishingHUD", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 12 }, pg)
-- AFTER IgnoreGuiInset (setting that resets it): every HUD gui shares the safe-area origin (HUD_CONTRACT §1)
hud.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

local FONT = Enum.Font.FredokaOne
local INK  = Color3.fromRGB(8, 22, 44)
local GOLD = Color3.fromRGB(255, 214, 64)
-- Cartoon pill: fat ink outline, saturated blue body lit from the top, glossy cap.
-- Deep blue ON PURPOSE — the sky behind these is pale, so a light pill washes into it.
local PILL_W, PILL_H, PILL_GAP = 172, 48, 14

-- The three pills used to be pinned at 0.5 +/- 186, i.e. a fixed 544px span centred on the
-- SCREEN. That is only correct on a wide monitor. The play area is the channel BETWEEN the
-- BaitRoller (left) and the MenuBar (right) - the same channel steerBounds keeps the hook
-- inside - and on an 812x375 phone that channel is 514px wide, so the outer pills used to
-- sit underneath both panels; on a 480-wide screen they ran off both edges of the screen.
-- They are a row now: centred in the live channel, and scaled down when it is too narrow.
local hudRow = make("Frame", { Name = "Pills", AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.fromOffset(PILL_W * 3 + PILL_GAP * 2, PILL_H),
	BackgroundTransparency = 1, ZIndex = 2 }, hud)
local hudRowScale = make("UIScale", { Scale = 1 }, hudRow)
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, PILL_GAP),
	SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center }, hudRow)

local function pill(order)
	local f = make("Frame", { LayoutOrder = order,
		Size = UDim2.fromOffset(PILL_W, PILL_H),
		BackgroundColor3 = Color3.new(1, 1, 1),   -- white: UIGradient TINTS, so let it own the colour
		BorderSizePixel = 0, ZIndex = 2 }, hudRow)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
	make("UIStroke", { Color = INK, Thickness = 4, LineJoinMode = Enum.LineJoinMode.Round }, f)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(102, 184, 240)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(58, 130, 200)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(32, 88, 158)),
	})}, f)
	-- glossy cap: sits under the text (ZIndex 3 < 4) so it never eats the label
	local shine = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(1, -22, 0, 9), BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.66, BorderSizePixel = 0, ZIndex = 3 }, f)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, shine)
	local t = make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = FONT,
		TextSize = 20, TextColor3 = Color3.fromRGB(255, 255, 255), Text = "", ZIndex = 4 }, f)
	make("UIStroke", { Color = INK, Thickness = 3, LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, t)
	return t
end
local depthLbl = pill(1)
local haulLbl  = pill(2)
local coinLbl  = pill(3)
coinLbl.TextColor3 = GOLD

-- The equipped-bait readout lives in StatsHUD (bottom-left, stacked on the luck line with
-- the rest of the live bonuses) rather than up here - the top-centre pills are the cast's
-- own state, and the middle of the frame is the play area.

-- AUTO-FISHING TOGGLE. Only exists once the Auto Fishing node is bought; hands-off casting
-- is something you have to be able to STOP without respeccing, which is the whole reason
-- this button exists. Safe to click: the cast is bound to UIS.InputBegan and returns early
-- on gameProcessedEvent, so a press here is swallowed by the GUI and never also casts.
local autoBtn = make("TextButton", { Name = "AutoToggle", AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0, 0, 0, 100), Size = UDim2.fromOffset(190, 40),
	BackgroundColor3 = Color3.fromRGB(92, 112, 142), AutoButtonColor = false,
	Text = "", BorderSizePixel = 0, ZIndex = 2, Visible = false }, hud)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, autoBtn)
make("UIStroke", { Color = INK, Thickness = 4, LineJoinMode = Enum.LineJoinMode.Round }, autoBtn)
make("UIScale", { Name = "FitScale", Scale = 1 }, autoBtn)   -- fitHud: 0.75 on phones, 1 elsewhere
-- glossy cap, same cartoon treatment as the pills above
local autoShine = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 5),
	Size = UDim2.new(1, -20, 0, 8), BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.66, BorderSizePixel = 0, ZIndex = 3 }, autoBtn)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, autoShine)
-- the text is a LABEL, not the button's own Text: a TextButton only honours one UIStroke,
-- and the pill needs a border stroke while the glyphs need a contextual one. Labels do not
-- consume input, so the click still lands on the button underneath.
local autoLbl = make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
	Font = FONT, TextSize = 19, TextColor3 = Color3.fromRGB(255, 255, 255), Text = "", ZIndex = 4 }, autoBtn)
make("UIStroke", { Color = INK, Thickness = 3, LineJoinMode = Enum.LineJoinMode.Round,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, autoLbl)

-- Defaults to ON the moment you unlock it - you just paid for hands-off fishing - so the
-- attribute stores only the OPT-OUT. Hence the `~= false` reads rather than truthiness.
local function autoRunning()
	return (plr:GetAttribute("UpgAuto") or 0) >= 1 and plr:GetAttribute("AutoCastOn") ~= false
end
local function refreshAuto()
	local unlocked = (plr:GetAttribute("UpgAuto") or 0) >= 1
	autoBtn.Visible = unlocked
	if not unlocked then return end
	local on = plr:GetAttribute("AutoCastOn") ~= false
	autoLbl.Text = on and "🤖  AUTO: ON" or "🤖  AUTO: OFF"
	autoBtn.BackgroundColor3 = on and Color3.fromRGB(64, 196, 104) or Color3.fromRGB(92, 112, 142)
end
TouchKit.press(autoBtn, function()
	plr:SetAttribute("AutoCastOn", plr:GetAttribute("AutoCastOn") == false)
	refreshAuto()
end)
plr.AttributeChanged:Connect(function(a)
	if a == "UpgAuto" or a == "AutoCastOn" then refreshAuto() end
end)
refreshAuto()

-- Named so ProgressController can read its LIVE top instead of mirroring fitHud's maths.
-- "Tap" also keys off the viewport: Studio's emulator reports MouseEnabled on a phone.
local hintLbl = make("TextLabel", { Name = "CastHint", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0, 0, 1, -26),
	Size = UDim2.fromOffset(460, 34), BackgroundTransparency = 1, Font = FONT, TextSize = 22,
	TextColor3 = Color3.fromRGB(255, 246, 210),
	Text = ((TouchKit.wanted() or math.min(cam.ViewportSize.X, cam.ViewportSize.Y) < 500) and "Tap" or "Click") .. " to cast", ZIndex = 2 }, hud)
make("UIStroke", { Color = INK, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, hintLbl)
-- phone: TextScaled into the main lane, capped 11..15 px (fitHud sets it); wide leaves it inert
make("UITextSizeConstraint", { Name = "FitCap", MinTextSize = 1, MaxTextSize = 100 }, hintLbl)

-- Everything above is centred on the CHANNEL, not on the screen (HUD_CONTRACT §1). All maths is in
-- this gui's LOCAL px (AbsolutePosition - hud.AbsolutePosition) with W,H = the SAFE area, so it is
-- right on a notched phone and never 58px off. This is the ONE place the top stack is decided: its
-- bottom is published as FishingHUD "TopStackBottom", and ProgressHUD, TutorialHUD and AfkHUD all
-- stack under that instead of mirroring these numbers. Constants live in here, not at chunk
-- level - GameClient sits a few registers under Luau's 200-local ceiling.
local function fitHud()
	local O, sz = hud.AbsolutePosition, hud.AbsoluteSize
	if sz.X < 2 then sz = cam.ViewportSize end
	local W, H = sz.X, sz.Y
	local phone = math.min(W, H) < 500
	local left, right = 0, W
	local lp = edgePanel("BaitRoller", "Panel")
	if lp then left = lp.AbsolutePosition.X + lp.AbsoluteSize.X - O.X end
	local rp = edgePanel("MainMenu", "MenuBar")
	if rp then right = rp.AbsolutePosition.X - O.X end
	-- The Daily/Wheel cluster narrows the top channel ONLY while it hangs inside it (desktop).
	-- Docked into a rail (phone / tablet) it must not. Geometric, so start order cannot matter.
	local topLeft = left
	local cluster = edgePanel("RewardsHUD", "Cluster")
	if cluster then
		local cl = cluster.AbsolutePosition.X - O.X
		local cr = cl + cluster.AbsoluteSize.X
		if cl >= left - 1 and cr <= right + 1 then topLeft = math.max(topLeft, cr) end
	end

	local topSpan = math.max(120, right - topLeft - 2 * (phone and 8 or 12))
	local centreTop = math.floor((topLeft + right) / 2 + 0.5)
	-- phone: floor 0.6 / cap 0.72 keeps the pill text 12..14 px; wide: today's 0.5..1
	local ps = phone and math.clamp(topSpan / (PILL_W * 3 + PILL_GAP * 2), 0.6, 0.72)
		or math.clamp(topSpan / (PILL_W * 3 + PILL_GAP * 2), 0.5, 1)
	hudRowScale.Scale = ps
	hudRow.Position = UDim2.new(0, centreTop, 0, 44)
	-- AutoToggle: 8px under the pills, 0.75 scale on a phone (30px tall, label 14 px)
	local autoScale = phone and 0.75 or 1
	local autoTop = math.floor(44 + PILL_H * ps + 8 + 0.5)
	local fs = autoBtn:FindFirstChild("FitScale")
	if fs then fs.Scale = autoScale end
	autoBtn.Position = UDim2.new(0, centreTop, 0, autoTop)
	hud:SetAttribute("TopStackBottom", math.floor((autoBtn.Visible and (autoTop + 40 * autoScale)
		or (44 + PILL_H * ps)) + 0.5))

	local cap = hintLbl:FindFirstChild("FitCap")
	local hs = hintLbl:FindFirstChildOfClass("UIStroke")
	if phone then
		-- The MAIN LANE's foot. StatsHUD and the boost chips own the 150px LEFT LANE beside it
		-- (x LR+8..LR+158), so the two can never share an x and never collide.
		local l0, l1 = left + 166, right - 8
		hintLbl.Position = UDim2.new(0, math.floor((l0 + l1) / 2 + 0.5), 1, -8)
		hintLbl.Size = UDim2.fromOffset(math.max(60, math.floor(l1 - l0)), 22)
		hintLbl.TextScaled = true
		if cap then cap.MinTextSize, cap.MaxTextSize = 11, 15 end
		if hs then hs.Thickness = 2 end
	else
		-- Bottom 6px above the bottom-left column: StatsHUD, plus BoostHUD's chips when they sit
		-- down there too (tablet). Only a piece in the BOTTOM half counts, so a frame that has
		-- not been placed yet (y 0) cannot fling the hint to the top. On desktop this is
		-- exactly the old `lift` (654..688 on a laptop).
		local top = H - 20
		for _, spec in ipairs({ { "StatsHUD", "Stats" }, { "BoostHUD", "Boosts" } }) do
			local f = edgePanel(spec[1], spec[2])
			-- Boosts count only when BOTTOM-anchored (tablet stacks them on the stats). The desktop
			-- strip hangs down from the rewards cluster, and with 4+ live boosts its centre crossed
			-- H/2 and flung the hint up to y 280, onto the AFK pill (measured on a laptop).
			if f and f.AbsoluteSize.Y > 4 and f.AbsolutePosition.Y - O.Y + f.AbsoluteSize.Y / 2 > H / 2
				and (spec[2] ~= "Boosts" or f.AnchorPoint.Y > 0.5) then
				top = math.min(top, f.AbsolutePosition.Y - O.Y)
			end
		end
		hintLbl.Position = UDim2.new(0, math.floor((left + right) / 2 + 0.5), 0, math.floor(top - 6 + 0.5))
		hintLbl.Size = UDim2.fromOffset(math.min(460, math.floor(math.max(160, right - left - 24))), 34)
		hintLbl.TextScaled = false
		if cap then cap.MinTextSize, cap.MaxTextSize = 1, 100 end
		if hs then hs.Thickness = 3 end
	end
end
fitHud()
cam:GetPropertyChangedSignal("ViewportSize"):Connect(fitHud)
hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitHud)
-- refreshAuto is defined above fitHud, so it re-publishes TopStackBottom through this instead
autoBtn:GetPropertyChangedSignal("Visible"):Connect(fitHud)
-- Watching ViewportSize alone is NOT enough, and a bounded startup loop is worse: the
-- panels this reads are resized by OTHER scripts (RollerController drives both its own
-- panel and the MenuBar off the same scale), and there is no ordering guarantee between
-- their resize and this one on a rotate. Watch the panels themselves, the way StatsHUD and
-- RewardsHUD do, and keep polling only until they exist to be watched.
-- Latched by EXISTENCE (FindFirstChild), not by edgePanel: BoostHUD is disabled until a boost is
-- live, and a watch that waits for it to be visible would never be connected.
task.spawn(function()
	local watched = {}
	for _ = 1, 60 do
		local all = true
		for _, spec in ipairs({ { "BaitRoller", "Panel" }, { "MainMenu", "MenuBar" }, { "RewardsHUD", "Cluster" },
			{ "StatsHUD", "Stats" }, { "BoostHUD", "Boosts" } }) do
			local scr = pg:FindFirstChild(spec[1])
			local f = scr and scr:FindFirstChild(spec[2])
			if f and not watched[f] then
				watched[f] = true
				f:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitHud)
				f:GetPropertyChangedSignal("AbsolutePosition"):Connect(fitHud)
				f:GetPropertyChangedSignal("Visible"):Connect(fitHud)
				scr:GetPropertyChangedSignal("Enabled"):Connect(fitHud)
			end
			if not f then all = false end
		end
		fitHud()
		if all then break end
		task.wait(0.2)
	end
end)

----------------------------------------------------------------------
-- state machine
----------------------------------------------------------------------
local STATE = "idle"       -- idle | casting | sinking | reeling | payout
local castT = 0            -- seconds into the cast
local castP0, castC, castP1 = nil, nil, nil   -- the thrown hook's Bezier; nil = not released yet
local hookX, hookY = 0, WATER_Y
local sinkDrop = 0         -- how far the hook fell THIS frame; the plunge camera rides it (see "camera" below)
local castAimX = nil       -- a DevCast's aim (world x) for that one cast; nil = the mouse, as for every real cast
local caught = {}
local deepest = 0
local flyers = {}
-- (reelT/reelTug are gone: the pump keeps its own ACCUMULATED phase inside ROD, and a bite
--  is a velocity impulse into the wrist oscillator rather than a decaying position offset.)
-- The surface-break flick: `pose` is the running heave (nil when the rod is at rest),
-- `lift` is how much line it has taken in (the strung catch hangs off that), and `trail`
-- is the countdown to the next dot on the bait's trail. One table, for the local budget.
local flick = { pose = nil, lift = 0, trail = 0 }
-- Fish hauled up but not yet thrown into the boat: { model, tag, rot }. Declared here with
-- the rest of the state because startCast() clears it, and startCast is defined above the
-- payout code - a local declared next to holdPending() would not be in scope up there.
local pending = {}

----------------------------------------------------------------------
-- THE ROD RIG - one owner, one write per joint per frame
----------------------------------------------------------------------
-- ONE file-scope local for the whole rig: constants, state and methods are all fields,
-- and every method is `function ROD.x()`, never `local function`. This chunk runs within a
-- handful of slots of Luau's 200-REGISTER ceiling, and that limit does NOT fail in Studio -
-- the script fails to load on the CLIENT at run time with "Out of local registers", and
-- until you press Play and read the console the file looks perfectly fine. NOTHING about
-- the rod may ever be declared at file scope again.
--
-- WHY IT SITS HERE: below `local pending = {}` so it closes over STATE / caught / hookX /
-- hookY / line / hook, and above startCast() so every call site can see it.
--
-- SOLVE THE WELD, DON'T COMPOSE ONTO IT:
--   Weld:  Part0.CFrame * C0 == Part1.CFrame * C1   (Part0 = RightHand, Part1 = Handle)
--          => Handle = rh * C0 * C1^-1  =>  C0 = rh^-1 * wantHandle * C1
--   base = (rh * gripC0 * C1^-1).Position      -- where the fist holds it
--   h    = ( cos YAW, 0, sin YAW)              -- aim, horizontal
--   side = (-sin YAW, 0, cos YAW)              -- the swing axis, horizontal
--   dir  = h*cos(p) + yAxis*sin(p)             -- the blank, sweeping a VERTICAL plane
--   want = CFrame.fromMatrix(base, side, dir)  -- +X = side, +Y = dir
-- fromMatrix takes the COLUMNS of the rotation matrix (vX -> RightVector, vY -> UpVector)
-- and computes the third as vX:Cross(vY), so the basis is right-handed. Worked out,
-- side x dir = (-cosY*sin p, cos p, -sinY*sin p), so handle-local -Z = h*sin(p) -
-- yAxis*cos(p): DOWN and forward at every sane pitch. The reel (local z -0.62) and all
-- three Guides (z -0.16) hang UNDER the blank, which is what a spinning reel does.
--
-- C1 IS READ LIVE, NEVER CACHED. C1 is Tool.Grip: per-tier, and the tool's own
-- FishingClient lerps it across 0.78s on Tool.Activated. We never WRITE Tool.Grip.
--
-- MOTION: pitch = base + pump + wob + breathe, where `base` is a cubic Hermite keyframe
-- track whose FIRST KEY IS SEEDED WITH THE LIVE (pitch, velocity). That one trick makes
-- every handover C1 BY CONSTRUCTION - cast interrupting idle, sink interrupting the cast,
-- haul interrupting a mid-pump reel, a tool swapped mid-whip.
local ROD = {
	----- AIM ---------------------------------------------------------------
	YAW       = math.rad(15),  -- 34 deg cost 18% of the rod's on-screen length to
	                           -- foreshortening; 15 costs 4% and still gives the blank
	                           -- depth instead of a flat 2D line coplanar with the boat.
	TIP_MIN_Y = 1.6,           -- hard floor, with margin for basePos.Y riding the idle anim
	BREAK_Y   = 3.4,           -- where the reel hands over to the haul. NOT the live tip:
	                           -- the rest tip moved 3.2 -> 7.7, so reeling to it would
	                           -- leave the catch hanging in the air while finishHaul's
	                           -- splash fired at the waterline.
	----- POSE ANGLES, absolute degrees above the horizon --------------------
	-- rest 38 -> back 104 -> release 60 -> stop 48. Arc 56 deg; the reference brackets a
	-- 50ft cast at 40-55. The old 115 -> -16 was a 131 deg sweep, i.e. world-record
	-- distance casting, performed sitting down.
	-- Tip clearance at base.Y 2.91, len 7.8 (need pitch >= -12.66):
	--   104 -> 10.48   72 -> 10.33   48 -> 8.71   38 -> 7.71   32 -> 7.04   20 -> 5.58
	P_REST = 38, P_BACK = 135, P_STOP = 48, P_FOLLOW = 12,
	-- P_BACK 104 -> 135 (2026-10-10, the owner: "thrown back over the shoulder"): with both hands on the rod the
	-- backswing now carries the blank BACK past vertical, over the right shoulder, before the two-handed toss.
	P_SINK = 20, P_REEL = 32,
	-- P_FOLLOW (2026-10-10, the owner: "make the rod go down a bit lower so it doesn't look so static"): after the
	-- release the tip FOLLOWS THE LINE down toward the water instead of freezing at the stop. 12 clears the
	-- tip-clearance floor (-12.66) by a mile.
	----- THE WRIST ---------------------------------------------------------
	-- A damped oscillator driven by the track's own analytic angular ACCELERATION - a mass
	-- on a spring attached to an accelerating frame. One mechanism, three cues: the tip
	-- LAGS while the butt accelerates, WHIPS PAST straight at the stop, then RINGS DOWN.
	WOB_HZ = 3.6, WOB_ZETA = 0.18, WOB_LAG = 0.25, WOB_MAX = 10, WOB_H = 1/90,
	TUG_KICK = 130,   -- deg/s impulse on a strike
	----- THE PUMP ----------------------------------------------------------
	PUMP_HZ_LIGHT = 0.75, PUMP_HZ_HEAVY = 0.40, PUMP_BOLT_HZ = 0.60,
	PUMP_A_LIGHT  = 3.5,  PUMP_A_HEAVY  = 13.0, PUMP_BOLT_A  = 0.55,
	PUMP_HEAVE = 0.62,  -- share of the cycle spent heaving: the wind is 1.63x faster
	PUMP_DROP  = 0.35,  -- and the tip goes BELOW the mean at the bottom of the wind
	PUMP_IN_HZ = 1.6, HEFT_HZ = 0.6, BOLT_HZ = 0.7,   -- rate limits
	----- THE HAUL ----------------------------------------------------------
	HAUL_RISE = 0.16, HAUL_FALL = 0.46, HAUL_UP_MIN = 24, HAUL_UP_MAX = 40,
	----- BREATH: rad/s and degrees -----------------------------------------
	-- 0.23 / 0.41 / 0.79 Hz. Ratios 1.783 and 3.435 - no small-integer relationship, so
	-- the sum never repeats and never reads as a loop. Worst case 1.92 deg = 4.4px peak.
	W1 = 1.445, A1 = 1.15,
	W2 = 2.576, A2 = 0.55,
	W3 = 4.964, A3 = 0.22,
	----- STATE -------------------------------------------------------------
	grip = nil, gripC0 = nil, gripPos = Vector3.zero, att = nil, tool = nil,
	len = 7.8, tipLocal = Vector3.new(0, 7.8, 0),
	fy = 7.8, fz = 0,                           -- flexed tip offset (Stage 4 drives these)
	flexZ = 0,                                  -- tip deflection in studs (Stage 4)
	want = CFrame.identity,
	tipPos   = Vector3.new(9.53, 7.71, 5.43),   -- computed rest tip, as a seed
	tipDrawn = Vector3.new(9.53, 7.71, 5.43),
	tipVel = 0, pitch = 0.663,
	cur = nil, st = 0, seedP = 38, seedV = 0,
	base = 38, baseVel = 0, baseAcc = 0,
	wob = 0, wobVel = 0,
	phase = 0, pump = 0, pumpVel = 0, pumpAmp = 0, pumpAmpVel = 0,
	heft = 0, heftVel = 0, heftT = 0,
	bolt = 0, boltVel = 0, boltT = 0,
	reeling = false, rate = 0, brk = 1, ten = 0,
}
-- YAW never animates (0.8 deg of yaw breathing moves the tip 0.38px), so these are
-- computed ONCE and the poser never spends a trig call on them.
ROD.ax, ROD.az = math.cos(ROD.YAW), math.sin(ROD.YAW)
ROD.side = Vector3.new(-ROD.az, 0, ROD.ax)

-- TRACKS: flat {t, pitch, vel} triples. Flat because a table per key would allocate on
-- every play() and because flat indexing is the fastest thing Luau does. Key 1's
-- pitch/vel are placeholders - the evaluator substitutes the live seed.
ROD.CAST = {
	0.00, 0, 0,                 -- seeded live
	0.40, ROD.P_BACK, 0,        -- top of the backswing. Peak 248 deg/s (ref backcast 300)
	0.50, ROD.P_BACK, 0,        -- THE PAUSE, 0.10s (ref 0.05-0.20)
	0.71, ROD.P_STOP, -160,     -- through the STOP still moving (the release, CAST_THROW, is just behind it)
	0.90, ROD.P_FOLLOW, 0,      -- the FOLLOW-THROUGH: the tip drops after the line, toward the water
	1.08, ROD.P_FOLLOW + 9, 0,  -- a small recoil off the bottom
	1.30, ROD.P_SINK, 0,        -- and it settles into the sink pose - no half second of dead hold
}
ROD.SINK = { 0.00, 0, 0,  0.85, ROD.P_SINK, 0 }
ROD.REEL = { 0.00, 0, 0,  0.35, ROD.P_REEL, 0 }
ROD.HAUL = { 0.00, 0, 0,  ROD.HAUL_RISE, 0, 0,
             ROD.HAUL_RISE + ROD.HAUL_FALL, ROD.P_REST, 0 }   -- [5] set by ROD.haul

-- Exact closed-form critically-damped smoothing. Unconditionally stable at ANY dt (no
-- clamp, no substep, no blow-up on a hitch), returns two values so it allocates nothing.
function ROD.smooth(cur, vel, tgt, hz, dt)
	local w = 6.2831853 * hz
	local a = cur - tgt
	local b = vel + w * a
	local m = a + b * dt
	local e = math.exp(-w * dt)
	return tgt + m * e, (b - w * m) * e
end

-- Start a track. Seeds key 1 with where the rod ACTUALLY is and how fast it is actually
-- going, so the handover is C1 no matter what interrupted what.
function ROD.play(track)
	ROD.seedP = ROD.base + ROD.pump
	ROD.seedV = ROD.baseVel + ROD.pumpVel
	ROD.pump, ROD.pumpVel, ROD.pumpAmp, ROD.pumpAmpVel = 0, 0, 0, 0
	ROD.cur, ROD.st = track, 0
	ROD.reeling = (track == ROD.REEL)
	if ROD.reeling then
		ROD.phase = 0                       -- open on a heave, not mid-cycle
	else
		ROD.heftT, ROD.boltT, ROD.rate = 0, 0, 0
	end
end

-- The surface break. Mutating HAUL[5] is safe: one haul at a time, single thread.
function ROD.haul(heft)
	ROD.HAUL[5] = ROD.P_REEL + ROD.HAUL_UP_MIN
		+ (ROD.HAUL_UP_MAX - ROD.HAUL_UP_MIN) * heft
	ROD.play(ROD.HAUL)
end

-- A strike IS an impulse and a real tip snaps, so this is the ONE velocity discontinuity
-- in the rig and it is deliberate. FLOORED, because two fish taken within ~0.2s would
-- otherwise stack and drive the wob onto the saturation wall.
function ROD.bite(l)
	local v = ROD.wobVel - ROD.TUG_KICK * (0.5 + 0.5 * math.clamp((l or 3) / 9, 0, 1))
	local floor = -ROD.TUG_KICK * 1.35
	ROD.wobVel = (v < floor) and floor or v
end

-- Cubic Hermite through position AND velocity, plus its analytic 1st and 2nd derivatives.
-- Analytic rather than differenced because the wrist oscillator eats the acceleration and
-- differencing at a variable dt would inject frame jitter straight into a style term.
function ROD.evalTrack()
	local k = ROD.cur
	if not k then ROD.baseVel, ROD.baseAcc = 0, 0; return end
	local t, n, i = ROD.st, #k, 1
	while i + 3 <= n and t >= k[i + 3] do i += 3 end
	local p0, v0 = k[i + 1], k[i + 2]
	if i == 1 then p0, v0 = ROD.seedP, ROD.seedV end
	if i + 3 > n then                                   -- past the last key: hold
		ROD.base, ROD.baseVel, ROD.baseAcc = p0, 0, 0
		return
	end
	local p1, v1 = k[i + 4], k[i + 5]
	local T  = k[i + 3] - k[i]
	local u  = (t - k[i]) / T
	local u2 = u * u
	local u3 = u2 * u
	local dp = p0 - p1
	ROD.base = (2*u3 - 3*u2 + 1) * p0 + (u3 - 2*u2 + u) * T * v0
	         + (3*u2 - 2*u3)     * p1 + (u3 - u2)       * T * v1
	ROD.baseVel = ((6*u2 - 6*u) * dp) / T
	            + (3*u2 - 4*u + 1) * v0 + (3*u2 - 2*u) * v1
	ROD.baseAcc = ((12*u - 6) * dp) / (T * T)
	            + ((6*u - 4) * v0 + (6*u - 2) * v1) / T
end

function ROD.stepPump(dt)
	-- Rate-limited so catching a fish cannot snap the pump. hz is DERIVED from these, so
	-- the frequency is C1 too - and the phase is ACCUMULATED, never reelT*hz.
	ROD.heft, ROD.heftVel = ROD.smooth(ROD.heft, ROD.heftVel, ROD.heftT, ROD.HEFT_HZ, dt)
	ROD.bolt, ROD.boltVel = ROD.smooth(ROD.bolt, ROD.boltVel, ROD.boltT, ROD.BOLT_HZ, dt)

	local wantA, hz = 0, 0
	if ROD.reeling then
		wantA = (ROD.PUMP_A_LIGHT + (ROD.PUMP_A_HEAVY - ROD.PUMP_A_LIGHT) * ROD.heft)
			* (1 - ROD.PUMP_BOLT_A * ROD.bolt)
		hz = (ROD.PUMP_HZ_LIGHT + (ROD.PUMP_HZ_HEAVY - ROD.PUMP_HZ_LIGHT) * ROD.heft)
			* (1 + ROD.PUMP_BOLT_HZ * ROD.bolt)
	end
	ROD.pumpAmp, ROD.pumpAmpVel =
		ROD.smooth(ROD.pumpAmp, ROD.pumpAmpVel, wantA, ROD.PUMP_IN_HZ, dt)

	-- BOUNDED per frame. This is the only unbounded accumulator in the rig, and a 1s hitch
	-- would step the phase up to 26 deg of pitch in one frame. hz is 0 off the reel, so the
	-- phase FREEZES rather than oscillating on under the haul flick.
	local dph = hz * dt
	ROD.phase = (ROD.phase + ((dph > 0.25) and 0.25 or dph)) % 1

	local H = ROD.PUMP_HEAVE
	local s, dsdp
	if ROD.phase < H then s = ROD.phase / H; dsdp = 1 / H
	else s = 1 - (ROD.phase - H) / (1 - H); dsdp = -1 / (1 - H) end
	-- C1 across BOTH seams: s -> 1 from either side of the turnaround and s -> 0 from
	-- either side of the wrap, and smoothstep' is 0 at 0 and at 1. The rod hangs a beat at
	-- the top of the heave and the bottom of the wind, which is what a pump looks like.
	local shape  = s * s * (3 - 2 * s)
	local dshape = 6 * s * (1 - s) * dsdp
	local body   = 1.35 * shape - ROD.PUMP_DROP
	ROD.pump    = ROD.pumpAmp * body
	ROD.pumpVel = ROD.pumpAmpVel * body + ROD.pumpAmp * 1.35 * dshape * hz
end

function ROD.stepWob(dt)
	local w = 6.2831853 * ROD.WOB_HZ
	local f = -ROD.WOB_LAG * ROD.baseAcc
	local k = w * w
	local c = 2 * ROD.WOB_ZETA * w
	-- Semi-implicit Euler at a fixed 1/90 substep: w*h = 0.251, comfortably stable. dt is
	-- clamped HERE only - the schedule clock ROD.st is never clamped, so a hitch cannot
	-- desynchronise the rod from the hook.
	local left = (dt < 0.10) and dt or 0.10
	while left > 1e-6 do
		local h = (left < ROD.WOB_H) and left or ROD.WOB_H
		ROD.wobVel += (f - k * ROD.wob - c * ROD.wobVel) * h
		ROD.wob    += ROD.wobVel * h
		left -= h
	end
	if ROD.wob > ROD.WOB_MAX then
		ROD.wob, ROD.wobVel = ROD.WOB_MAX, math.min(ROD.wobVel, 0)
	elseif ROD.wob < -ROD.WOB_MAX then
		ROD.wob, ROD.wobVel = -ROD.WOB_MAX, math.max(ROD.wobVel, 0)
	end
end

-- ONE shared tension scalar drives the rod's load bend (Stage 4) AND the line's sag
-- (Stage 2), so the two can never disagree.
function ROD.tension()
	if STATE == "sinking" then return ROD.brk end   -- taut on the plunge, slack as it brakes
	if STATE == "reeling" then
		return math.min(1, 0.45 + 0.55 * #caught / math.max(1, capacity()))
	end
	if STATE == "casting" then return line.Enabled and 0.80 or 0 end
	return 0
end

-- The tool ships its OWN rod animator (FishingClient, in StarterPack and all ten
-- ServerStorage masters). It fires on Tool.Activated - every real click, never on DevCast -
-- and on Tool.Equipped it builds two IKControls plus their HRP target attachments, and its
-- cast spawns FR_Bobber carrying a SECOND Beam on the SAME Tip.LineOrigin this game uses.
-- Disabled = true is the ONLY thing that stops it: its Activated guard is
-- `if casting or not ikR`, ikR is a Lua upvalue, and a DESTROYED instance is still truthy.
-- Disabling alone is also not enough, because the instances it already created on Equipped
-- stay live and would accumulate one pair per tier swap. Do both.
function ROD.silence(tool)
	local fc = tool and tool:FindFirstChild("FishingClient")
	if fc and fc:IsA("LuaSourceContainer") then pcall(function() fc.Disabled = true end) end
	local char = plr.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		for _, d in ipairs(hum:GetChildren()) do
			if d:IsA("IKControl") then d.Enabled = false; d:Destroy() end
		end
	end
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local a = hrp:FindFirstChild("RodRTarget"); if a then a:Destroy() end
		local b = hrp:FindFirstChild("RodLTarget"); if b then b:Destroy() end
	end
	local bob = workspace:FindFirstChild("FR_Bobber"); if bob then bob:Destroy() end
end

-- Re-bind on a NEW RightGrip instance: re-equip, respawn, or a tier swap (the engine
-- destroys and recreates the weld every time). Capturing gripC0 here is safe precisely
-- because the instance is new, so its C0 is still the authored one.
function ROD.bind(g)
	ROD.grip, ROD.gripC0, ROD.gripPos = g, g.C0, g.C0.Position
	ROD.att, ROD.tipLocal, ROD.len = nil, Vector3.new(0, 7.8, 0), 7.8
	local handle = g.Part1
	local tool   = handle and handle.Parent
	ROD.tool = tool
	local tip = tool and tool:FindFirstChild("Tip")
	local lo  = tip and tip:FindFirstChild("LineOrigin")
	if handle and lo and lo:IsA("Attachment") then
		ROD.att = lo
		-- MEASURED, not hardcoded. PointToObjectSpace on a rigidly welded descendant is
		-- pose-invariant, so this is correct even before the weld has solved.
		local v = handle.CFrame:PointToObjectSpace(lo.WorldPosition)
		if v.Y > 1 then ROD.tipLocal, ROD.len = v, v.Y end
	end
	ROD.fy, ROD.fz = ROD.tipLocal.Y, ROD.tipLocal.Z
	ROD.silence(tool)
	ROD.onBind(tool)          -- Stages 2/4 hang their per-rod setup here
end

-- THE LINE.
--   SAG_K   sag depth as a share of the tip->hook span when fully slack. Reference sag for
--           slack fraction e is span*sqrt(3e/8); 2% slack gives 0.087.
--   SAG_MAX studs, so a 600-stud column cannot bow absurdly.
--   WHIP_K  how far the line trails behind the lure per stud/s of cast speed.
ROD.SAG_K, ROD.SAG_MAX, ROD.WHIP_K = 0.085, 7.0, 0.055
ROD.lastHook = Vector3.zero

-- Per-rod setup. Runs once per RightGrip instance (equip / respawn / tier swap).
-- The line's control-point attachments are created ONCE and never destroyed: an anchored
-- helper in `zone` rather than an attachment on the Tip part, because the helper is written
-- ANALYTICALLY from ROD.tipDrawn - it is never one frame stale, it never fights the joint
-- solver, and it does not have to be rebuilt on any of the ten tier swaps.
function ROD.onBind(tool)
	if not ROD.tipA then
		local p = make("Part", {
			Name = "RG_TipAnchor", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1,
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
			CastShadow = false, CFrame = CFrame.new(ROD.tipPos),
		}, zone)
		ROD.tipA = make("Attachment", { Name = "RG_TipA" }, p)
	end
	if not ROD.hookA then
		ROD.hookA = make("Attachment", { Name = "RG_HookA" }, hook)
	end
	line.Attachment0, line.Attachment1 = ROD.tipA, ROD.hookA
	-- Tier swap / unequip / respawn all route through here (a new RightGrip instance).
	-- ROD.rig calls ROD.strip on the incoming tool FIRST, and strip is a pure function of
	-- the tool, so a double-arm is impossible: after strip the tool is byte-identical to
	-- its authored joint configuration and ROD.carriers is rebuilt wholesale.
	if ROD.prevTool and ROD.prevTool ~= tool then ROD.strip(ROD.prevTool) end
	ROD.prevTool = tool
	ROD.rig(tool)
	-- NOT RODFX.rig(tool) here. `local RODFX` is declared ~22k chars BELOW this function
	-- body, and a local declared after a body is not an upvalue of it - the name would
	-- resolve to a nil GLOBAL, throw inside ROD.step, get swallowed by its pcall, and leave
	-- the rod frozen with only a warn to show for it. RODFX.step picks the tool change up
	-- instead, one frame later and after its own declaration.
end

-- A Beam is a cubic Bezier:
--   P1 = A0.WorldPosition + A0.WorldCFrame.RightVector * CurveSize0
--   P2 = A1.WorldPosition - A1.WorldCFrame.RightVector * CurveSize1     <- note the MINUS
-- so for both control points to fall on the SAME side of the chord the two +X axes must
-- point OPPOSITE ways. Sag depth at t=0.5 is then exactly 0.375*(CurveSize0 + CurveSize1).
--
-- THE SAG AXIS IS THE CHORD PERPENDICULAR, NOT WORLD -Y. This line is near-VERTICAL for
-- the whole sink and most of the reel (tip Y ~3, hook down to -640), and a control point
-- pushed along world -Y from a vertical chord lands ON the chord: a full 7-stud sag on a
-- 203-stud vertical span bows it 0.34 studs = 6px perpendicular, and puts P2 below the
-- bobber so the beam pokes out underneath it.
function ROD.line()
	if not (line.Enabled and ROD.tipA and ROD.hookA) then
		if line.CurveSize0 ~= 0 then line.CurveSize0 = 0 end
		if line.CurveSize1 ~= 0 then line.CurveSize1 = 0 end
		return
	end
	local tp = ROD.tipDrawn          -- the tip the hook was placed on this frame
	local hp = hook.Position
	local dx, dy = hp.X - tp.X, hp.Y - tp.Y
	local span = math.sqrt(dx * dx + dy * dy)
	if span < 0.25 then              -- hook still on the tip: no curve to draw
		if line.CurveSize0 ~= 0 then line.CurveSize0 = 0 end
		if line.CurveSize1 ~= 0 then line.CurveSize1 = 0 end
		ROD.lastHook = hp
		return
	end
	local px, py = dy / span, -dx / span
	if py > 0 then px, py = -px, -py end          -- force the LOW side
	local perp = Vector3.new(px, py, 0)
	ROD.tipA.Parent.CFrame = CFrame.fromMatrix(tp, perp, Vector3.zAxis)

	local cs0, cs1
	if STATE == "casting" then
		-- the line trails BEHIND the lure on the way out: point the hook control along the
		-- hook's velocity, so P2 (which SUBTRACTS it) lands behind the hook
		local vel = hp - ROD.lastHook
		local sp = vel.Magnitude
		if sp > 0.05 then
			ROD.hookA.CFrame = CFrame.fromMatrix(Vector3.zero, vel / sp, Vector3.zAxis)
		end
		cs0 = 0.35
		cs1 = math.min(ROD.WHIP_K * sp * 60, ROD.SAG_MAX)
	else
		-- P2 subtracts, so the hook end carries -perp to land on the same side as P1
		ROD.hookA.CFrame = CFrame.fromMatrix(Vector3.zero, -perp, Vector3.zAxis)
		local sag = math.min(ROD.SAG_K * span * (1 - ROD.ten), ROD.SAG_MAX)
		cs0 = sag * 1.333          -- depth at t=0.5 is exactly 0.375*(cs0+cs1)
		cs1 = cs0
	end
	ROD.lastHook = hp
	if math.abs(line.CurveSize0 - cs0) > 0.01 then line.CurveSize0 = cs0 end
	if math.abs(line.CurveSize1 - cs1) > 0.01 then line.CurveSize1 = cs1 end
end

----------------------------------------------------------------------
-- THE BLANK FLEX
----------------------------------------------------------------------
-- WHY WELDS, NOT MOTOR6D, NOT FREE CFRAME. The blank is joined to Handle by
-- WeldConstraints, which capture their offset once and expose nothing to animate. A Weld
-- is a JointInstance with C0/C1 and - crucially - NO .Transform, so the Animator (which
-- rewrites Motor6D/AnimationConstraint Transform every frame, even with no track playing)
-- can never touch it, and client C0 writes never replicate. Unwelding and writing CFrame is
-- worst: these are unanchored massless members of the seated character's assembly.
-- STAR, NOT CHAIN. Every driven Weld keeps Part0 = Handle, exactly like the WeldConstraint
-- it replaces, so the assembly graph is the same tree it already was, no C0 depends on
-- another, and nothing accumulates error.
ROD.FLEXN     = 3
ROD.FLEX_HZ   = 4.0     -- first bending mode. Free fly rods measure 2.65Hz, but the
ROD.FLEX_TIER = 0.13    -- casting study's 0.05s from rod-straight to max counterflex is a
ROD.FLEX_Z    = 0.22    -- QUARTER period, i.e. ~5Hz for a hand-held line-loaded rod.
ROD.TAPER     = 1.8     -- curvature k(s) ~ (s/L)^taper. The tip-loaded cantilever curve
                        -- everyone quotes, (s/L)^2*(3-s/L)/2, is for a PRISMATIC beam and
                        -- puts peak curvature at the BUTT. This blank runs 0.52 -> 0.10
                        -- studs across and I ~ d^4, so EI at the tip is ~1/1300 of EI at
                        -- the butt; fitting the built geometry gives ~2.24, softened to 1.8
                        -- because with three driven sections a very tip-heavy profile dumps
                        -- nearly all the angle into the last joint and reads as a hinge.
ROD.ACC_S     = 2.30e-4 -- studs of static tip deflection per deg/s^2 of commanded angular
                        -- acceleration. Peak |baseAcc| on the power stroke is
                        -- 6*56/0.21^2 = 7619, so static ~0.95 studs; dynamic amplification
                        -- was predicted at ~1.47, but MEASURED in play the stroke's forcing
                        -- is too brief for the spring to reach equilibrium: at 1.25e-4 the
                        -- peak came out 0.728 studs (12px, only 9% of L) against the
                        -- reference's 16-27% casting band. Scaled 1.84x off that measurement
                        -- to land ~1.34 studs = 23px = 17% of L. LINEAR: halve it to halve.
ROD.TEN_IDLE  = 0.06    -- studs of rest bend from the terminal tackle (~1% of L; real)
ROD.TEN_LOAD  = 0.95    -- ...plus this at full line tension
ROD.X_MAX     = 2.1     -- studs, 27% of L: the measured casting maximum
ROD.C_MAX     = 1.25    -- rad, hard cap on the tip TANGENT angle
ROD.FLEX_EPS  = 2e-4    -- below this change in C, skip the writes (a joint C0 write dirties
                        -- its whole assembly and they are NOT coalesced per frame)
ROD.flexV, ROD.flexC, ROD.flexLast = 0, 0, nil
ROD.carriers = {}
-- The authored joints this rig switched off, kept so they can be RE-ASSERTED every frame.
-- WeldConstraint.Enabled is a SERVER-OWNED REPLICATED property: these constraints are
-- server-made, so a client `Enabled = false` holds only until the server next replicates the
-- instance - which it does whenever the Tool is re-parented, i.e. on every equip/unequip and
-- therefore on every one of the ten tier swaps. MEASURED: after 10 swaps all 13 came back
-- Enabled with our RG_Off tag still set, which double-jointed every guide, wrap and knot
-- back onto the rigid Handle while the blank bent underneath them - the blank flexed and its
-- fittings stayed on the straight line. Re-asserting is 13 boolean reads a frame and only
-- writes on the frames the server actually clobbered us.
ROD.offWC = {}

-- Rest transform in handle space, extent along the blank axis, widest cross extent.
function ROD.rest(inv, p)
	local r  = inv * p.CFrame
	local z  = p.Size
	local rv, uv, lv = r.RightVector, r.UpVector, r.LookVector
	local ey = math.abs(rv.Y)*z.X + math.abs(uv.Y)*z.Y + math.abs(lv.Y)*z.Z
	local ex = math.abs(rv.X)*z.X + math.abs(uv.X)*z.Y + math.abs(lv.X)*z.Z
	local ez = math.abs(rv.Z)*z.X + math.abs(uv.Z)*z.Y + math.abs(lv.Z)*z.Z
	return r, ey, math.max(ex, ez)
end

-- THE BEND. Curvature k(s) ~ (s/L)^(n-1), so the tangent angle is theta(s) = C*(s/L)^n and
-- C is exactly the TIP TANGENT ANGLE - one number. The centreline Y = int cos(theta),
-- Z = int sin(theta) has no closed form for a non-uniform profile, but it has an EXACT
-- term-by-term series in C. Three terms; the first dropped sine term is C^7/(5040*(7n+1)),
-- which at the C_MAX clamp is 4.6e-5, i.e. one 280th of a pixel at L=7.8.
-- No quadrature, and - unlike the closed-form circular arc - NO 1/kappa singularity to
-- branch around: at C = 0 this returns exactly (a*L, 0, 0).
function ROD.bendAt(a, w, C, L, n)
	local aw = a * w
	local w2 = w * w
	local C2 = C * C
	local y = a
		- C2      * (aw * w)       / (2   * (2*n + 1))
		+ C2 * C2 * (aw * w2 * w)  / (24  * (4*n + 1))
	local z = C       * aw         / (n + 1)
		- C2 * C  * (aw * w2)      / (6   * (3*n + 1))
		+ C2*C2*C * (aw * w2 * w2) / (120 * (5*n + 1))
	return L * y, L * z, C * w
end

-- Pure function of the tool: reads no Lua state, so it undoes ANY generation's rig.
function ROD.strip(tool)
	if not tool then return end
	local h = tool:FindFirstChild("Handle")
	-- 1. Put every part we moved back on its authored offset BY HAND, and do it BEFORE
	--    step 3. WeldConstraint.Enabled = true RE-CAPTURES the current relative offset at
	--    the instant of enabling - re-enabling one while the rod is bent bakes that bend
	--    into the tool PERMANENTLY, for every future equip. Writing part.CFrame is
	--    immediate (no solver round-trip), so the re-capture sees the rest pose.
	if h then
		local hc = h.CFrame
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("BasePart") then
				local r = d:GetAttribute("RG_Rest")
				if typeof(r) == "CFrame" then
					d.CFrame = hc * r
					d:SetAttribute("RG_Rest", nil)
				end
			end
		end
	end
	-- 2. Drop everything we created. NEVER :Destroy() an authored WeldConstraint: they are
	--    server-made and replicated, and hum:EquipTool MOVES the same Tool instance in and
	--    out of the character rather than re-cloning it, so a client destroy is permanent
	--    for the session and the rod falls apart for good.
	for _, d in ipairs(tool:GetDescendants()) do
		if d.Name:sub(1, 5) == "RG_W_" or d.Name:sub(1, 5) == "RG_P_" then d:Destroy() end
	end
	-- 3. Hand back ONLY the joints THIS rig switched off, tagged with RG_Off when we did it.
	--    A blanket "re-enable every WeldConstraint under Handle" is wrong and was measured
	--    breaking the crank: RODFX owns CrankArm/CrankKnob on the SAME Handle, so whenever
	--    ROD re-bound after RODFX had rigged, it switched the crank's authored constraints
	--    back on underneath it. The arm still turned (its Weld wins) but the knob stayed
	--    pinned to the Handle, so the crank read as motionless. Tagging makes the two rigs
	--    order-independent instead of relying on who ran last.
	if h then
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("WeldConstraint") and d:GetAttribute("RG_Off") then
				d.Enabled = true
				d:SetAttribute("RG_Off", nil)
			end
		end
	end
end

function ROD.rig(tool)
	table.clear(ROD.carriers)
	table.clear(ROD.offWC)
	ROD.flexZ, ROD.flexV, ROD.flexC, ROD.flexLast = 0, 0, 0, nil
	ROD.fy, ROD.fz = ROD.tipLocal.Y, ROD.tipLocal.Z
	if not tool then return end
	ROD.strip(tool)                                -- idempotent: undo whatever was left here
	local h  = tool:FindFirstChild("Handle")
	local lo = ROD.att
	local tip = lo and lo.Parent
	if not (h and tip and tip.Parent == tool) then return end
	local L = ROD.len
	if L ~= L or L < 1 or L > 60 then return end

	local inv = h.CFrame:Inverse()
	local parts = {}
	for _, p in ipairs(tool:GetChildren()) do
		if p:IsA("BasePart") and p ~= h then
			local r, ey, ew = ROD.rest(inv, p)
			local s = r.Position.Y
			if s == s then parts[#parts+1] = { p = p, r = r, s = s, ey = ey, ew = ew } end
		end
	end

	-- CARRIERS chosen by GEOMETRY, never by name: tiers 2-10 hang Foam, ButtGem, Trigger,
	-- Stripe, Strut, Gear, GalaxyCore, Aura, Planet and Star off this same skeleton at
	-- arbitrary offsets. Long + slender + above the grip picks out the blank.
	-- 0.20*L excludes the whole reel assembly, which stays on the rigid Handle - so a crank
	-- rig is a separate star and cannot conflict with this one.
	local car = {}
	for _, e in ipairs(parts) do
		if e.s >= 0.20 * L and e.ey >= 0.10 * L and e.ey >= 3.0 * math.max(e.ew, 0.01) then
			e.drive = true
			car[#car+1] = e
		end
	end
	table.sort(car, function(a, b) return a.s < b.s end)
	while #car > math.clamp(ROD.FLEXN, 1, 3) do table.remove(car, 1).drive = nil end
	if #car < 2 then return end                    -- unknown skeleton: rigid beats guessing

	-- The tip part MUST be driven. LineOrigin is its child, so it follows the flex for free -
	-- but if the tip stayed welded to the rigid Handle the line would leave the rod from the
	-- UNBENT rest tip while the blank curved away from it. Refuse to build rather than ship that.
	local ok = false
	for _, c in ipairs(car) do if c.p == tip then ok = true end end
	if not ok then return end

	-- PASSENGERS (guides, feet, wraps, knots, tier quirks) ride whichever carrier they sit
	-- above. Anything below 0.20*L keeps its original weld on the rigid Handle.
	for _, e in ipairs(parts) do
		if not e.drive and e.s >= 0.20 * L then
			local best, bd = nil, math.huge
			for _, c in ipairs(car) do
				local d = math.abs(e.s - c.s) - c.ey * 0.5
				if d < bd then best, bd = c, d end
			end
			e.host = best
		end
	end

	-- Map part -> its authored WeldConstraint. Scan the whole Tool once, not just Handle's
	-- children: a constraint whose endpoints are NOT Handle would be missed by a
	-- Handle-only scan, leaving that part double-jointed and pinned rigid against the bend.
	local wcOf, dup = {}, false
	for _, w in ipairs(tool:GetDescendants()) do
		if w:IsA("WeldConstraint") and w.Part0 and w.Part1 then
			local other = (w.Part0 == h) and w.Part1 or ((w.Part1 == h) and w.Part0 or nil)
			if other then
				if wcOf[other] then dup = true end
				wcOf[other] = w
			end
		end
	end
	-- FAIL CLOSED. If any driven or hosted part has no mapped constraint (or has two),
	-- abandon. Leaving one live alongside ours double-joints that part: the solver
	-- over-constrains it and it pins rigid while its neighbours bend - a visibly broken rod,
	-- with no error, on whichever tier has the odd topology. Rigid beats pinned-and-wrong.
	if dup then return end
	for _, e in ipairs(parts) do
		if (e.drive or e.host) and not wcOf[e.p] then return end
	end

	-- No yields from here on: the joint solve runs at PreSimulation, AFTER render, so the
	-- parts are never loose between switching the old joints off and the new ones on. Every
	-- part's authored offset is snapshotted ONTO THE PART, so strip needs no Lua state.
	local n = ROD.TAPER + 1
	for _, e in ipairs(parts) do
		if e.drive or e.host then e.p:SetAttribute("RG_Rest", e.r) end
	end
	local i = 0
	for _, c in ipairs(car) do
		i += 1
		local w = Instance.new("Weld")
		w.Name = "RG_W_" .. i
		w.Part0, w.Part1 = h, c.p
		w.C0, w.C1 = c.r, CFrame.identity        -- exactly the rest pose
		w.Parent = h
		wcOf[c.p].Enabled = false
		wcOf[c.p]:SetAttribute("RG_Off", true)   -- so strip re-enables exactly this one
		ROD.offWC[#ROD.offWC + 1] = wcOf[c.p]
		local a = math.min(c.s / L, 1.15)        -- a quirk above the tip: don't extrapolate
		ROD.carriers[i] = { weld = w, rest = c.r, s = c.s,
			a = a, w = a ^ n, last = c.r }
	end
	local m = 0
	for _, e in ipairs(parts) do
		if e.host then
			-- a WeldConstraint captures the relative offset when it goes active, and the rod
			-- is still at rest here, so the capture is the rest offset. Correct by
			-- construction. Create ours FIRST, then disable the old: for that instant both
			-- express the identical transform, so there is never a loose part.
			m += 1
			local pc = Instance.new("WeldConstraint")
			pc.Name = "RG_P_" .. m
			pc.Part0, pc.Part1 = e.host.p, e.p
			pc.Parent = h
			wcOf[e.p].Enabled = false
			wcOf[e.p]:SetAttribute("RG_Off", true)
			ROD.offWC[#ROD.offWC + 1] = wcOf[e.p]
		end
	end
	ROD.flexN = n
	ROD.flexL = L
end

-- Integrate the tip deflection. EXACT ANALYTIC STEP of the damped oscillator with the drive
-- zero-order-held: semi-implicit Euler on this spring is stable only for omega*dt < 2, i.e.
-- below 14fps, and a dt clamp merely hides the instability while running the animation in
-- slow motion. This is not an approximation and it CANNOT diverge for any dt, because
-- |exp(-zeta*omega*dt)| < 1 always.
--
-- DRIVEN BY ROD.baseAcc, the track's own ANALYTIC angular acceleration - not by a frame
-- difference of the commanded angle. During acceleration x_e is positive, so the tip
-- deflects toward local +Z = up and BACK: the tip trails while the butt drives forward,
-- which is loading. At the STOP baseAcc flips sign, the spring is already displaced, and it
-- drives through zero into negative - the tip OVERTAKES the butt going forward and DOWN.
-- That is counterflex, and it falls out of the physics; no beat is scripted.
function ROD.flexStep(dt)
	if #ROD.carriers < 2 then ROD.flexZ = 0; return end
	-- Re-assert the joints the server keeps handing back (see ROD.offWC). Read-then-write, so
	-- a settled frame costs 13 property reads and no writes at all.
	for i = 1, #ROD.offWC do
		local w = ROD.offWC[i]
		if w.Parent and w.Enabled then w.Enabled = false end
	end
	local w = 6.2831853 * (ROD.FLEX_HZ + ROD.FLEX_TIER
		* (math.clamp(tonumber(plr:GetAttribute("EquippedRod")) or 1, 1, 10) - 1))
	local zw = ROD.FLEX_Z * w
	local wd = w * math.sqrt(1 - ROD.FLEX_Z * ROD.FLEX_Z)

	-- LINE TENSION, projected onto the bend plane - one dot product covers every case. A
	-- hook hanging straight below bends the tip DOWN (and correctly weakens as the rod is
	-- raised toward vertical); a hook out in front on the cast bends it FORWARD.
	local ten = 0
	if line.Enabled then
		local d = hook.Position - ROD.tipPos
		if d.Magnitude > 0.5 then
			ten = (ROD.TEN_IDLE + ROD.TEN_LOAD * ROD.ten) * d.Unit:Dot(-ROD.want.LookVector)
		end
	else
		ten = -ROD.TEN_IDLE * math.cos(ROD.pitch)
	end
	local xe = -ROD.ACC_S * ROD.baseAcc + ten

	local e  = math.exp(-zw * dt)
	local c  = math.cos(wd * dt)
	local s  = math.sin(wd * dt)
	local d0 = ROD.flexZ - xe
	local b  = (ROD.flexV + zw * d0) / wd
	local x  = xe + e * (d0 * c + b * s)
	local v  =      e * (ROD.flexV * c - (zw * b + d0 * wd) * s)
	if x ~= x or v ~= v then x, v = 0, 0 end
	if x >  ROD.X_MAX then x =  ROD.X_MAX; if v > 0 then v = 0 end
	elseif x < -ROD.X_MAX then x = -ROD.X_MAX; if v < 0 then v = 0 end end
	ROD.flexZ, ROD.flexV = x, v

	-- C, the tip TANGENT angle, from x, the tip DEFLECTION. Z(L)/L = C/(n+1) to first order;
	-- the cubic term recovers the fold-over at big bends.
	local n = ROD.flexN
	local r = x / ROD.flexL
	local C = (n + 1) * r + ((n + 1)^4 / (6 * (3*n + 1))) * r * r * r
	if C > ROD.C_MAX then C = ROD.C_MAX elseif C < -ROD.C_MAX then C = -ROD.C_MAX end
	ROD.flexC = C
	-- Publish the FLEXED tip offset so ROD.aim's clearance clamp and ROD.tipPos both see
	-- it. The bend is NOT a pitch term - it displaces the tip along handle-local +Z, which
	-- lands on world Y as fz*cos(pitch). A pitch-only clamp would let a loaded blank spear
	-- the sea with every pitch term legal.
	local by, bz = ROD.bendAt(1, 1, C, ROD.flexL, n)
	ROD.fy, ROD.fz = by, bz + ROD.tipLocal.Z
end

function ROD.flexApply()
	local C = ROD.flexC
	-- 2e-4 rad of C is L*dC/(n+1) = 4e-4 studs of tip travel = 0.007px. Below that, don't
	-- dirty the assembly: nothing else writes these welds, so they hold their last pose.
	if ROD.flexLast and math.abs(C - ROD.flexLast) < ROD.FLEX_EPS then return end
	ROD.flexLast = C
	local L, n = ROD.flexL, ROD.flexN
	for _, c in ipairs(ROD.carriers) do
		if c.weld.Parent then
			local by, bz, th = ROD.bendAt(c.a, c.w, C, L, n)
			-- C0 = Bend(s) * CFrame.new(0,-s,0) * R, entirely in HANDLE space, so off-axis
			-- rest components survive correctly and no child's own rotation is involved.
			-- At C = 0 this collapses to exactly R - no branch, no singularity.
			c.weld.C0 = CFrame.new(0, by, bz) * CFrame.Angles(th, 0, 0)
				* CFrame.new(0, -c.s, 0) * c.rest
		end
	end
end

function ROD.aim(pitchDeg)
	local char = plr.Character
	local rh   = char and char:FindFirstChild("RightHand")
	local g    = rh and rh:FindFirstChild("RightGrip")
	-- Missing character / unequipped / the one frame between two tools: write NOTHING. No
	-- instance is created here, so there is nothing to leak.
	if not g then ROD.grip = nil; return end
	if g ~= ROD.grip then ROD.bind(g) end

	local c1  = g.C1                        -- LIVE. Never cache: see the header.
	local hcf = rh.CFrame
	-- Grip.Position is (0,0,0) on every tier, and for a C1 with no translation
	-- (A*B*C1^-1).Position == (A*B).Position, so basePos collapses to one CFrame*Vector3 -
	-- a native vector result that allocates nothing. The general branch stays for a
	-- hypothetical tier that puts a translation in its Grip.
	local q = c1.Position
	local base
	if q.X == 0 and q.Y == 0 and q.Z == 0 then
		base = hcf * ROD.gripPos
	else
		base = (hcf * ROD.gripC0 * c1:Inverse()).Position
	end

	local p  = pitchDeg * 0.017453293
	local sp, cp = math.sin(p), math.cos(p)
	-- TIP CLEARANCE, against the LIVE hand height rather than a constant (basePos.Y rides
	-- the idle animation) and against the FLEXED tip offset (fy, fz) rather than a bare
	-- length - the blank's own bend displaces the tip along local +Z, which lands on world
	-- Y as fz*cos(p). A length-only clamp lets a loaded blank spear the sea with every
	-- pitch term legal. Exact: a*sin(p) + b*cos(p) = R*sin(p + phi).
	local a, b = ROD.fy, ROD.fz
	local m = ROD.TIP_MIN_Y - base.Y
	if a * sp + b * cp < m then
		local r = math.sqrt(a * a + b * b)
		local s = m / r
		p = ((s >= 1) and 1.5707963 or math.asin(s)) - math.atan2(b, a)
		sp, cp = math.sin(p), math.cos(p)
	end
	ROD.pitch = p

	local want = CFrame.fromMatrix(base, ROD.side,
		Vector3.new(ROD.ax * cp, sp, ROD.az * cp))
	g.C0 = hcf:Inverse() * want * c1
	ROD.want = want
	-- Analytic, so it costs nothing, needs no instance lookup, and is exact on the frame a
	-- tool is swapped. Read one step later by the cast branch, which makes it the tip that
	-- is currently ON SCREEN (a Weld's C0 is solved after the render).
	ROD.tipPos = want * Vector3.new(ROD.tipLocal.X, a, b)
end

-- TWO HANDS ON THE ROD (2026-10-10, the owner: "held by both hands, thrown back over the shoulder, and then
-- tossed while still being held with both hands"). Two IKControls on the Humanoid (RodArmR / RodArmL), their targets
-- Attachments on the HRP. The RIGHT hand rides a path keyed by the rod's own pitch - in front of the belly at rest, up
-- and back past the right shoulder at the top of the backswing, pushed forward on the stroke, low and forward on the
-- follow-through - and the rod rides with it, because ROD.aim solves the weld off RightHand every frame. The LEFT hand
-- holds the butt, ROD.BUTT studs down the blank from the right. Measured seated (HRP space, -Z forward): shoulders at
-- x +-1.13, y 0.29; the targets stay inside both arms' reach (~2 studs). ROD.ARMS rows: { pitch, x, y, z }.
-- Everything is a ROD field: GameClient is at Luau's 200-register ceiling (see the header above ROD).
ROD.ARMS = {
	{ 12,  0.35, -0.10, -1.55 },   -- follow-through: low and forward
	{ 38,  0.35,  0.05, -1.25 },   -- rest: in front of the belly, near the middle
	{ 60,  0.55,  0.45, -1.15 },   -- the stroke
	{ 82,  0.75,  0.62, -1.08 },
	{ 104, 0.90,  0.72, -1.00 },
	{ 135, 1.00,  0.76, -0.95 },   -- the top of the backswing: hands at shoulder height out in FRONT of the chest, the
	                               -- rod swung back over the right shoulder. The camera looks at the angler's right side,
	                               -- so a hand raised to head height draws OVER the face even when it is beside it in 3D:
	                               -- the hands stay under the chin (y <= 0.76) and the rod does the travelling.
}
-- (2026-10-10, the owner: "one of the arms is weird (the left one)". MEASURED geometry, seated, HRP space (-Z
-- forward): shoulder JOINTS at (+-0.92, 0.65, 0.10); arm reach ~2.4; head box x +-0.6, y 0.98..2.18, z -0.42..0.78;
-- chest box x +-0.92, y -0.9..1.0, z -0.5..0.57. Rules every row keeps: the right hand 0.95-1.9 from its shoulder (an
-- arm cannot fold tighter - the old backswing rows sat 0.3 from it and missed by 0.5), the LEFT hand's butt target
-- <= 2.0 from its shoulder (the old rows, out by the right side, put it out of reach: the hand stalled at the midline
-- and flipped behind the back), both hands in FRONT of the chest and clear of the head.)
ROD.POLE_R = Vector3.new(2.6, -0.4, 0.9)    -- right elbow: out and back
ROD.POLE_L = Vector3.new(-2.0, -1.0, -2.0)  -- left elbow: out, down and forward (measured best of 8)
ROD.BUTT = 0.55
function ROD.armPos(p)
	local K = ROD.ARMS
	local a = K[1]
	if p <= a[1] then return Vector3.new(a[2], a[3], a[4]) end
	for i = 2, #K do
		local b = K[i]
		if p <= b[1] then
			local u = (p - a[1]) / (b[1] - a[1])
			return Vector3.new(a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u, a[4] + (b[4] - a[4]) * u)
		end
		a = b
	end
	return Vector3.new(a[2], a[3], a[4])
end
function ROD.arms()
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	-- the chains start at the SHOULDERS: rooted at UpperTorso the solver bent the whole spine to reach and the angler
	-- hunched over the rod
	local ru = char and char:FindFirstChild("RightUpperArm")
	local lu = char and char:FindFirstChild("LeftUpperArm")
	local rh, lh = char and char:FindFirstChild("RightHand"), char and char:FindFirstChild("LeftHand")
	if not (hum and hrp and ru and lu and rh and lh) then return end
	-- (re)build on a new character, or after ROD.silence swept the Humanoid's IKControls
	if not (ROD.ikR and ROD.ikR.Parent == hum and ROD.ikL and ROD.ikL.Parent == hum and ROD.tR and ROD.tR.Parent == hrp) then
		for _, n in ipairs({ "RodArmR", "RodArmL" }) do local o = hum:FindFirstChild(n); if o then o:Destroy() end end
		for _, n in ipairs({ "RodArmRT", "RodArmLT", "RodArmRP", "RodArmLP" }) do local o = hrp:FindFirstChild(n); if o then o:Destroy() end end
		ROD.tR = Instance.new("Attachment"); ROD.tR.Name = "RodArmRT"; ROD.tR.Parent = hrp
		ROD.tL = Instance.new("Attachment"); ROD.tL.Name = "RodArmLT"; ROD.tL.Parent = hrp
		ROD.pR = Instance.new("Attachment"); ROD.pR.Name = "RodArmRP"; ROD.pR.Parent = hrp; ROD.pR.Position = ROD.POLE_R
		ROD.pL = Instance.new("Attachment"); ROD.pL.Name = "RodArmLP"; ROD.pL.Parent = hrp; ROD.pL.Position = ROD.POLE_L
		local function arm(name, root, hand, target, pole)
			local ik = Instance.new("IKControl")
			ik.Name, ik.Type, ik.ChainRoot, ik.EndEffector, ik.Target = name, Enum.IKControlType.Position, root, hand, target
			ik.Pole = pole
			ik.SmoothTime, ik.Weight = 0.02, 0
			ik.Parent = hum
			return ik
		end
		ROD.ikR = arm("RodArmR", ru, rh, ROD.tR, ROD.pR)
		ROD.ikL = arm("RodArmL", lu, lh, ROD.tL, ROD.pL)
	end
	local w = ROD.grip and 1 or 0         -- no rod in the hand: let the seat animation have the arms back
	if ROD.ikR.Weight ~= w then ROD.ikR.Weight, ROD.ikL.Weight = w, w end
	if w == 0 then return end
	ROD.tR.Position = ROD.armPos(ROD.base + ROD.pump)
	if ROD.want then ROD.tL.WorldPosition = ROD.want.Position - ROD.want.UpVector * ROD.BUTT end
end

function ROD.step(dt)
	ROD.st += dt
	ROD.ten = ROD.tension()
	ROD.evalTrack()
	-- Studio-only pose freeze for tuning the arms/rod by eye: hook:SetAttribute("RG_PosePitch", 104) holds that pitch
	if ROD.studio == nil then ROD.studio = game:GetService("RunService"):IsStudio() end
	if ROD.studio and hook:GetAttribute("RG_PosePitch") then
		ROD.base, ROD.baseVel, ROD.baseAcc = hook:GetAttribute("RG_PosePitch"), 0, 0
	end
	ROD.stepPump(dt)
	ROD.stepWob(dt)
	ROD.flexStep(dt)                        -- no-op until Stage 4; sets ROD.fy/fz/flexZ
	ROD.tipDrawn = ROD.tipPos               -- the tip the hook was placed on THIS frame
	-- SIGNED tip speed, studs/s: +ve travelling back/up (loading), -ve forward/down (the
	-- stroke). Analytic, so no differencing and no frame-rate dependence.
	ROD.tipVel = ROD.len * 0.017453293 * (ROD.baseVel + ROD.pumpVel + ROD.wobVel)
	-- Breath is added AFTER the oscillator on purpose: it is far too slow to flex a rod,
	-- and ROD.baseAcc must stay a clean signal for the flex rig to read.
	local c = os.clock()
	ROD.aim(ROD.base + ROD.pump + ROD.wob
		+ ROD.A1 * math.sin(c * ROD.W1)
		+ ROD.A2 * math.sin(c * ROD.W2 + 1.7)
		+ ROD.A3 * math.sin(c * ROD.W3 + 4.1))
	ROD.flexApply()                         -- no-op until Stage 4
	ROD.arms()                              -- both hands on the rod, riding the same pose
	-- Telemetry channel. ROD is a file-scope LOCAL, so no execute_luau script can index it;
	-- attributes are the only way out. Gated, so normal play pays nothing.
	if hook:GetAttribute("RG_Debug") then
		hook:SetAttribute("RG_phase", ROD.phase)
		hook:SetAttribute("RG_tipVel", ROD.tipVel)
		hook:SetAttribute("RG_wob", ROD.wob)
		hook:SetAttribute("RG_flexZ", ROD.flexZ)
		hook:SetAttribute("RG_ten", ROD.ten)
		hook:SetAttribute("RG_rate", ROD.rate)
	end
end

----------------------------------------------------------------------
-- RODFX - sound and particles, hung off the motion system's beats
----------------------------------------------------------------------
-- The SECOND and LAST file-scope local this work adds. Same rule as ROD: every constant,
-- every piece of state and every method is a field.
--
-- No external asset was verified as suitable (the closest free Creator Store hits are
-- servo motors, not reel mechanisms), so every cue below is synthesised from clips that
-- already load: Cast, Splash, SplashBig, Bite, Tick, ReelLoop.
local RODFX = {
	----- reel -----------------------------------------------------------------
	-- VISUAL gearing, not real gearing. A real spinning reel recovers ~2.3 studs/turn,
	-- which at this game's arcade-fast 26 studs/s catching pass would be 690rpm. 16
	-- studs/turn puts the catching pass at 1.63 rev/s - dead centre of the 1-2 rev/s a real
	-- angler cranks - and lets the full-hook bolt pin against the cap instead.
	STUDS_PER_TURN = 16,
	MAX_REV   = 4.2,   -- rev/s ceiling: 25 deg/frame at 60fps, clear of wagon-wheel aliasing
	SPIN_EASE = 8,     -- ~0.4s spin-up/down, so the pump's stall/spin reads as a crank
	                   -- being worked rather than a strobe
	DRIVE_REF = 2.4,   -- rev/s at which the reel loop counts as fully driven
	PUMP_IDLE = 0.15,  -- crank multiplier during the HEAVE half of a pump
	----- audio ----------------------------------------------------------------
	-- MEASURED IN PLAY, not estimated. tipVel = len*(pi/180)*baseVel, so the backswing peaks
	-- at 7.8*0.01745*(1.5*66/0.40) = +34 studs/s and the power stroke at
	-- -7.8*0.01745*(1.5*56/0.21) = -54 (57 with the wrist term). The design's 62 was ABOVE
	-- the achievable peak, so the stroke whoosh - the loudest beat in the cast - never fired
	-- at all. 44 sits cleanly between the two peaks.
	AIR_LO = 26,       -- tip studs/s: the backswing (peak +34) trips only this one
	AIR_HI = 44,       -- ...and nothing but the power stroke (peak -57) trips this one
	----- vfx ------------------------------------------------------------------
	TRAIL_MIN = 30,    -- tip studs/s below which the whip throws nothing off
	TRAIL_GAP = 0.016, -- ~one dot a frame at 60fps; denser just stacks parts in a pixel
	----- state ----------------------------------------------------------------
	rev = 0, duty = 1, trail = 0, phasePrev = 0,
	airLo = false, airHi = false, loop = nil, loopBase = 0.375,
}

-- THE AIR. Two whooshes off the SIGNED tip speed rather than off a clock, so they track
-- whatever the motion curves settle on and can never drift out of step with them. Firing
-- on the RISING edge is the point: a sample has attack time, so crossing the gate a few
-- frames early is what lands the loudest part of the clip ON the stop - which is where
-- peak tip speed actually is (measured within 20ms of the hand stop). The sign split makes
-- double-firing structurally impossible.
function RODFX.air(spd)
	if spd < -RODFX.AIR_HI then
		if not RODFX.airHi then
			RODFX.airHi = true
			Audio.play("Cast", { pitch = 0.92 + math.random() * 0.10,
				volume = 0.75 + 0.35 * math.clamp((-spd - RODFX.AIR_HI) / 40, 0, 1) })
		end
	elseif spd > -RODFX.AIR_HI * 0.65 then RODFX.airHi = false end

	if spd > RODFX.AIR_LO then
		if not RODFX.airLo then
			RODFX.airLo = true
			-- the backswing: the same clip pitched up and quiet, so it reads as a lighter,
			-- faster movement of air and not as a second cast
			Audio.play("Cast", { pitch = 1.45 + math.random() * 0.12, volume = 0.30 })
		end
	elseif spd < RODFX.AIR_LO * 0.6 then RODFX.airLo = false end
end

-- THE REEL LOOP. Re-acquired through Audio.startLoop every frame rather than cached:
-- startLoop is idempotent by name and hands back the LIVE clone, so this self-heals if the
-- loop is ever stopped and restarted and can never write to a dead instance.
-- ONLY ever called while STATE == "reeling" - startLoop would otherwise RESURRECT a loop
-- finishHaul has just stopped, and a per-frame Volume write would fight stopLoop's fade.
function RODFX.reel()
	local s = Audio.startLoop("ReelLoop", 0.75)
	if not s then return end
	if s ~= RODFX.loop then RODFX.loop, RODFX.loopBase = s, s.Volume end

	local drive  = math.clamp(RODFX.rev / RODFX.DRIVE_REF, 0, 1)
	-- Loaded but NOT recovering line = the drag is giving, and the honest sound for that is
	-- the reel's own whirr run FASTER over a stalled handle. Not a fudge: when a drag slips
	-- the spool really does spin under a handle that is not turning.
	local strain = ROD.heft * (1 - drive)
	-- The strain coefficients are held BELOW the drive coefficients on purpose. reelPose's
	-- heft is the SUM of caught fish lengths over 12, so it pins at 1.0 after about four
	-- average fish. At 0.85/0.42 that made pitch = 1.43 - 0.13*drive: nearly flat AND
	-- INVERTED - the loop would drop as the crank sped up, the exact opposite of the cue.
	-- Monotone in drive at every heft needs 0.72 > 0.45*heft and 0.50 > 0.28*heft.
	local pitch = 0.58 + 0.72 * drive + 0.45 * strain
	local vol   = RODFX.loopBase * (0.34 + 0.50 * drive + 0.28 * strain)
	-- epsilon-gated: both are flat for most of a pump and a Sound property write fires
	-- change signals
	if math.abs(s.PlaybackSpeed - pitch) > 0.01 then s.PlaybackSpeed = pitch end
	if math.abs(s.Volume - vol) > 0.004 then s.Volume = vol end
end

-- THE CRANK. The reel is correctly built and has simply never been ROTATED:
-- ReelBody.CFrame.Rotation resolves its CylinderMesh axis to handle-local +Z, and CrankKnob
-- at handle-local (0.85, -0.05, -0.62) minus the reel centre (0, -0.05, -0.62) is
-- (0.85, 0, 0) - entirely perpendicular to that axis, i.e. 0.85 studs of real throw.
-- (Rotating it about handle-local X, the axis it is NOT mounted on, spins the knob in
-- place, which is where the "zero throw" reading came from. No offset link is needed.)
RODFX.THROW_MIN = 0.15   -- a crank with less offset from its own axis than this cannot read
                         -- as turning however fast it spins, so it is skipped rather than
                         -- costing a joint write every frame for zero pixels
RODFX.crankAng, RODFX.crank, RODFX.crankPiv, RODFX.crankRest = 0, nil, nil, nil
RODFX.crankTool = nil

-- Self-contained: touches only RG_C_*, a disjoint part set from the flex rig's
-- RG_W_*/RG_P_*, so Stage 5 is independently revertible.
function RODFX.strip(tool)
	if not tool then return end
	local h = tool:FindFirstChild("Handle")
	if h then
		local hc = h.CFrame
		for _, d in ipairs(tool:GetChildren()) do
			if d:IsA("BasePart") then
				local r = d:GetAttribute("RG_CRest")
				if typeof(r) == "CFrame" then d.CFrame = hc * r; d:SetAttribute("RG_CRest", nil) end
			end
		end
		for _, d in ipairs(h:GetChildren()) do
			if d.Name:sub(1, 5) == "RG_C_" then d:Destroy() end
		end
		-- Only the ones WE switched off, tagged RG_COff - a different tag from the flex rig's
		-- RG_Off, so the two strips can never hand each other's joints back.
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("WeldConstraint") and d:GetAttribute("RG_COff") then
				d.Enabled = true
				d:SetAttribute("RG_COff", nil)
			end
		end
	end
end

function RODFX.rig(tool)
	RODFX.crank, RODFX.crankPiv, RODFX.crankRest = nil, nil, nil
	if RODFX.crankTool and RODFX.crankTool ~= tool then RODFX.strip(RODFX.crankTool) end
	RODFX.crankTool = tool
	if not tool then return end
	RODFX.strip(tool)
	local h    = tool:FindFirstChild("Handle")
	local body = tool:FindFirstChild("ReelBody")
	local arm  = tool:FindFirstChild("CrankArm")
	local knob = tool:FindFirstChild("CrankKnob")
	if not (h and body and arm) then return end

	-- The reel's axis, solved from the LIVE parts so all ten tiers answer for themselves and
	-- not one offset is hardcoded. ReelBody is a legacy CylinderMesh disc, so it spins about
	-- its own part-local Y; on tier 1 that resolves to handle-local +Z.
	local inv  = h.CFrame:Inverse()
	local piv  = inv * body.CFrame
	local axis = piv.UpVector
	local rest = inv * arm.CFrame
	local d    = rest.Position - piv.Position
	local perp = d - axis * d:Dot(axis)
	if perp.Magnitude < RODFX.THROW_MIN then return end   -- measured 0.85 on tier 1

	-- Find the authored constraints. Fail closed if either is missing or duplicated.
	local wA, wK, dup = nil, nil, false
	for _, w in ipairs(tool:GetDescendants()) do
		if w:IsA("WeldConstraint") and w.Enabled then
			local a, b = w.Part0, w.Part1
			if a == arm or b == arm then if wA then dup = true end; wA = w
			elseif knob and (a == knob or b == knob) then if wK then dup = true end; wK = w end
		end
	end
	if dup or not wA or (knob and not wK) then return end

	arm:SetAttribute("RG_CRest", rest)
	-- CARRIER PATTERN: convert only the ARM and let the KNOB ride it, so the whole crank
	-- costs ONE C0 write a frame rather than two. Create the knob's rider FIRST, while
	-- everything is at rest: both constraints express the identical transform for that
	-- instant, so there is no fight and no frame in which the knob is loose.
	-- Enabled = false, never :Destroy() - these are server-replicated and EquipTool moves
	-- the SAME Tool instance, so a client destroy is permanent for the session.
	if knob then
		local pc = Instance.new("WeldConstraint")
		pc.Name = "RG_C_Knob"
		pc.Part0, pc.Part1 = arm, knob
		pc.Parent = h
		wK.Enabled = false
		wK:SetAttribute("RG_COff", true)
		RODFX.knobWC = wK
	end
	local w = Instance.new("Weld")
	w.Name = "RG_C_Arm"
	w.Part0, w.Part1 = h, arm
	w.C0, w.C1 = rest, CFrame.identity
	w.Parent = h
	wA.Enabled = false
	wA:SetAttribute("RG_COff", true)
	RODFX.crank, RODFX.crankPiv = w, CFrame.new(piv.Position)
	RODFX.crankPivInv = RODFX.crankPiv:Inverse()
	RODFX.crankRest, RODFX.crankAxis = rest, axis
	RODFX.armWC = wA
end

function RODFX.crankApply(dt)
	local w = RODFX.crank
	if not (w and w.Parent) then return end
	if RODFX.rev <= 0 then return end
	-- PHASE ACCUMULATED, never derived from absolute time: the rate changes on every single
	-- hooked fish, and reading (t * rate) would teleport the handle the moment it did.
	-- Wrapped, so the angle cannot grow without bound over a long session.
	RODFX.crankAng = (RODFX.crankAng + RODFX.rev * 6.2831853 * dt) % 6.2831853
	w.C0 = RODFX.crankPiv * CFrame.fromAxisAngle(RODFX.crankAxis, RODFX.crankAng)
		* RODFX.crankPivInv * RODFX.crankRest
end

function RODFX.step(dt)
	-- REEL ON THE DOWN STROKE ONLY: you lift, then you wind. Universal across every
	-- angling source, and it is what makes the crank and the reel loop STALL on the heave
	-- and pick up on the wind - the strongest single cue in the retrieve.
	-- It drives the CRANK AND THE AUDIO ONLY - deliberately never hookY. Modulating the
	-- hook's own travel is cycle-average-neutral for TRAVEL TIME but NOT for CATCH RATE:
	-- tryCatch samples once a frame and takes at most one fish, so the frames a fish spends
	-- inside the catch radius scale as 1/speed, and at tier-10 speeds the wind half runs
	-- 6.2 studs a frame against a ~7.7-stud catch diameter - fish get tunnelled through.
	-- NOT while the hook is FULL: that branch is a flat-out crank, not a pump.
	-- Tool change (equip / respawn / any of the ten tier swaps) is picked up HERE rather
	-- than from ROD.onBind, for the upvalue reason documented there. RODFX.rig is idempotent
	-- and sets crankTool, so this fires exactly once per change.
	if RODFX.crankTool ~= ROD.tool then RODFX.rig(ROD.tool) end
	-- Same server-re-replication problem as ROD.offWC: Enabled is server-owned, so an equip
	-- hands these back on. Re-assert rather than re-rig - rebuilding the joints every time
	-- would churn instances, and the two writes here are the whole fix.
	local wA, wK = RODFX.armWC, RODFX.knobWC
	if wA and wA.Parent and wA.Enabled then wA.Enabled = false end
	if wK and wK.Parent and wK.Enabled then wK.Enabled = false end

	local reeling = (STATE == "reeling")
	RODFX.duty = (reeling and ROD.bolt < 0.5)
		and ((ROD.phase < ROD.PUMP_HEAVE) and RODFX.PUMP_IDLE
			or (1 - RODFX.PUMP_IDLE * ROD.PUMP_HEAVE) / (1 - ROD.PUMP_HEAVE))
		or 1

	-- PHASE IS ACCUMULATED by ROD; RODFX only reads it. Crank rate is geared to the LINE,
	-- not the clock, so the handle visibly stalls whenever line stops being recovered.
	local want = math.clamp((reeling and ROD.rate * RODFX.duty or 0) / RODFX.STUDS_PER_TURN,
		0, RODFX.MAX_REV)
	RODFX.rev += (want - RODFX.rev) * math.min(1, dt * RODFX.SPIN_EASE)
	if RODFX.rev < 0.05 then RODFX.rev = 0 end
	RODFX.crankApply(dt)

	if reeling then
		RODFX.reel()
		-- ONE beat per cycle at the TOP of the heave (phase crossing PUMP_HEAVE, where the
		-- rod is at max lift and the drag is under most strain). NOT at the phase wrap:
		-- phase 0 is the BOTTOM of the heave, which would put the pawl 0.62 of a cycle
		-- ahead of the motion it punctuates.
		if RODFX.phasePrev < ROD.PUMP_HEAVE and ROD.phase >= ROD.PUMP_HEAVE
			and ROD.heft > 0.25 then
			Audio.play("Tick", { pitch = 1.55 + 0.35 * ROD.heft + math.random() * 0.10,
				volume = 0.22 + 0.30 * ROD.heft })
		end
	end
	RODFX.phasePrev = ROD.phase

	-- Whooshes belong to the CAST and nothing else. The surface-break flick sweeps its
	-- pitch fast enough to trip AIR_LO, so ungated it would fire a cast whoosh over
	-- SplashBig on every single haul.
	RODFX.air((STATE == "casting") and ROD.tipVel or 0)

	-- what the whip throws off the tip and the guides
	local a = math.abs(ROD.tipVel)
	if a > RODFX.TRAIL_MIN and STATE == "casting" then
		RODFX.trail -= dt
		if RODFX.trail <= 0 then
			RODFX.trail = RODFX.TRAIL_GAP
			local tp = ROD.tipDrawn
			local k = -ROD.tipVel * 0.05        -- inherit a slice of the tip's own travel
			FX.tipwash(tp.X + (math.random() - 0.5) * 0.5,
			           tp.Y + (math.random() - 0.5) * 0.5,
			           k * 0.35 + (math.random() - 0.5) * 3,
			           math.abs(k) * 0.2 + math.random() * 2,
			           0.16 + math.random() * 0.12)
		end
	else
		RODFX.trail = 0
	end
end

-- Discrete beats, fire-and-forget.
function RODFX.on(beat, a, b)
	if beat == "cast" then
		RODFX.airLo, RODFX.airHi, RODFX.trail = false, false, 0

	elseif beat == "release" then
		-- no whistle clip exists; Cast pitched right up and held quiet is a thin airy tail
		-- under the arcing hook
		Audio.play("Cast", { pitch = 1.70 + math.random() * 0.10, volume = 0.22 })

	elseif beat == "splash" then
		-- scaled by how hard it actually arrives: a fast entry cracks, a lob plops
		local imp = math.clamp((a or 40) / 70, 0, 1)
		FX.splash(b, 0.9 + 0.7 * imp)
		Audio.play("Splash", { pitch = 1.06 - 0.16 * imp + math.random() * 0.08,
			volume = 0.8 + 0.4 * imp })

	elseif beat == "strike" then
		Audio.play("Bite", { pitch = 1.28 - 0.45 * math.clamp((a or 3) / 9, 0, 1) })
		local tp = ROD.tipDrawn
		for _ = 1, 2 do   -- the rod jolts and throws the film off its guides
			FX.tipwash(tp.X + (math.random() - 0.5) * 0.8, tp.Y,
				(math.random() - 0.5) * 5, 1 + math.random() * 3,
				0.15 + math.random() * 0.1)
		end

	elseif beat == "break" then
		-- Drop the loop handle in the SAME beat that stops it, or RODFX.reel's per-frame
		-- Volume write fights stopLoop's fade tween and the loop never goes away.
		RODFX.loop, RODFX.rev = nil, 0
		local heft = a or 0
		local tp = ROD.tipDrawn
		local n = 4 + math.floor(8 * heft)
		for i = 1, n do            -- the line comes out of the sea WET
			local u = i / (n + 1)
			FX.tipwash(hookX + (tp.X - hookX) * u, WATER_Y + (tp.Y - WATER_Y) * u,
				(math.random() - 0.5) * 7, 2 + math.random() * 6,
				0.2 + math.random() * 0.18)
		end
	end
end

----------------------------------------------------------------------
-- the haul total — one big cartoony number in the sky over the payout.
-- The per-fish "+$N" tags say what each FISH was worth; this says what the whole
-- HAUL is worth, and punches every time a fish feeds it.
----------------------------------------------------------------------
-- Idle frame top is camY + camDist*tan(FOV/2) ~ 35 and the HUD pills end ~y26, so
-- this is the low end of the free band: pulled DOWN to 18 to sit nearer frame centre.
-- Fish arcs cap at y ~16, so the text's lower edge (18 - 6.4/2 = 14.8) is grazed by
-- them — that's fine and intended, the coins fly INTO it, and AlwaysOnTop keeps it
-- legible over the fish. Re-check with IDLE_CAM_Y / CAM_FOV / FLY_UP.
local TOTAL_Y = 18
local TOTAL_W, TOTAL_H = 24, 6.4
local totalPart = make("Part", {
	Name = "HaulTotal", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1,
	Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
	CastShadow = false, CFrame = CFrame.new(0, TOTAL_Y, PLAY_Z),
}, zone)
-- Scale (studs), not Offset — the camera is ~140 back and Offset pixels render as a speck
local totalBB = make("BillboardGui", {
	Name = "TotalBB", Adornee = totalPart, Size = UDim2.fromScale(TOTAL_W, TOTAL_H),
	AlwaysOnTop = true, LightInfluence = 0, Enabled = false,
}, totalPart)
local totalLbl = make("TextLabel", {
	BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = FONT,
	TextScaled = true, TextColor3 = Color3.new(1, 1, 1), Text = "+$0",
}, totalBB)
-- UIGradient TINTS the text, so the label must be white for this to read as gold
make("UIGradient", { Rotation = 90, Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 246, 170)),
	ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 214, 64)),
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 152, 28)),
})}, totalLbl)
local totalStroke = make("UIStroke", { Color = INK, Thickness = 6 }, totalLbl)

local tot = { real = 0, shown = 0, t = 0, punch = 0, tilt = 0, hold = 0, out = 0, live = false }

-- The "+$N" labels peeled off the paid-out fish, in flight up to the total. A coin
-- pays into the number when it ARRIVES, not when its fish launches — that's what makes
-- the total climb in step with the money visibly landing in it.
local coinFlights = {}
local TAG_W, TAG_H  = 11, 3.1   -- must match makeTag's BillboardGui, so flights can shrink it
local TAG_HANDOFF   = 0.28      -- how long a tag rides its fish before peeling off
local COIN_FLIGHT   = 0.42      -- seconds from fish to total

-- overshoot-and-settle: the cartoon pop
local function easeOutBack(t)
	local u = t - 1
	return 1 + 2.70158 * u * u * u + 1.70158 * u * u
end

local function hideTotal()
	tot.live = false
	totalBB.Enabled = false
	-- drop coins still in the air, or a cast started mid-payout leaves them orbiting a
	-- dead total. Inlined because destroyTag isn't declared until further down.
	for i = #coinFlights, 1, -1 do
		local f = coinFlights[i]
		if f.tag and f.tag.lbl then f.tag.lbl:Destroy() end
		table.remove(coinFlights, i)
	end
end

local function beginTotal()
	tot.real, tot.shown = 0, 0
	tot.t, tot.punch, tot.tilt, tot.out = 0, 0, 0, 0
	tot.hold = 1.3   -- grace: without it the fade starts in the frames before fish #1 lands
	tot.live = true
	totalLbl.Text = "+$0"
	totalLbl.TextTransparency = 0
	totalStroke.Transparency = 0
	totalBB.Enabled = true
end

-- a fish just paid out: add it to the number and kick it. Each bump re-arms the
-- hold, so the total leaves 'hold' seconds after the LAST fish, not the first.
local function bumpTotal(value)
	tot.real += value
	tot.punch = 0.34
	tot.tilt = (math.random() < 0.5 and -1 or 1) * 6
	tot.hold = 1.3
	tot.out = 0      -- un-fade: any fade already begun is otherwise permanent
end

-- peel a fish's price tag off and send it up into the total; it pays in on arrival
local function sendToTotal(tag, value, fromX, fromY)
	if not tag then return end
	coinFlights[#coinFlights + 1] = {
		tag = tag, value = value, x0 = fromX, y0 = fromY,
		-- bow the path sideways so back-to-back coins don't stack into one streak
		cx = fromX * 0.35 + (math.random() - 0.5) * 10,
		cy = (fromY + TOTAL_Y) * 0.5 + 3.5,
		t = 0,
	}
end

local function report(verb, amount)
	local qm = pg:FindFirstChild("QuestsMenu")
	local rep = qm and qm:FindFirstChild("Report")
	if rep then pcall(function() rep:Fire(verb, amount) end) end
end

local function refreshHUD()
	local d = math.max(0, math.floor(WATER_Y - hookY))
	depthLbl.Text = (STATE == "idle" or STATE == "payout" or STATE == "casting")
		and ("MAX  " .. math.floor(maxDepth()) .. "m")
		or (d .. "m  /  " .. math.floor(maxDepth()) .. "m")
	haulLbl.Text = "🐟  " .. #caught .. " / " .. capacity()
	if STATE == "idle" then
		hintLbl.Text = autoRunning() and "Auto fishing\226\128\166"
			or (((TouchKit.wanted() or math.min(cam.ViewportSize.X, cam.ViewportSize.Y) < 500) and "Tap" or "Click") .. " to cast")
	elseif STATE == "casting" then
		hintLbl.Text = "Casting…"
	elseif STATE == "sinking" then
		hintLbl.Text = "Diving - hold on…"
	elseif STATE == "reeling" then
		hintLbl.Text = (#caught >= capacity()) and "Hook full — hauling up!" or "Reeling up — steer into the fish!"
	end
	-- payout leaves the haul line that finishHaul wrote
end

-- Equipping or spending a bait has to update both indicators immediately. refreshHUD only
-- runs on state changes and mid-cast frames, so without this, equipping while idle would
-- show nothing until the next throw.
plr.AttributeChanged:Connect(function(a)
	if a == "EquippedBait" or a == "BaitIcon" then refreshBaitTag() end
	-- Buying a boat changes the MAX depth and the hook capacity this HUD prints, and
	-- refreshHUD only runs on state changes and mid-cast frames - so without this the
	-- readout keeps the old boat's numbers until the next cast finishes. (Measured live:
	-- a tier-5 trawler carrying +58 depth still showed "MAX 120m".)
	if a == "BoatDepth" or a == "BoatCap" or a == "Pass_slot" or a == "Pass_double" then refreshHUD() end
end)

-- ONE BAIT IS SPENT PER CAST. This is what "using" a bait means, and nothing did it
-- before. Clearing EquippedBait on the last one makes InventoryController republish the
-- buffs as zero, so the effect, the HUD chip and the bobber tag all switch off together
-- without GameClient needing to know what the buff actually was.
local function consumeBait()
	local name = plr:GetAttribute("EquippedBait")
	if not name or name == "" then return end
	local key = "Bait_" .. baitKey(name)
	local n = (plr:GetAttribute(key) or 0) - 1
	if n <= 0 then
		plr:SetAttribute(key, 0)
		plr:SetAttribute("EquippedBait", nil)
	else
		plr:SetAttribute(key, n)
	end
end

local function startCast(aimX)
	-- not before the save has loaded: a catch on the starting balance would be overwritten by the restored one
	if STATE ~= "idle" or plr:GetAttribute("DataLoaded") ~= true then return end
	castAimX = tonumber(aimX)   -- only DevCast passes one; a click or an auto cast passes nothing
	hideTotal()
	local start = ROD.tipPos
	local minX, maxX = steerBounds()
	hookX = math.clamp(start.X, minX, maxX)
	hookY = start.Y
	deepest = 0
	caught = {}
	castT = 0
	flick.pose, flick.lift = nil, 0    -- a new cast cancels a flick still settling
	RODFX.on("cast")                   -- re-arm the tip-speed whoosh gates and the trail
	ROD.play(ROD.CAST)                 -- seeded from wherever the rod actually is, so a
	                                   -- cast can interrupt a still-settling haul flick
	                                   -- without a pop
	for i = #pending, 1, -1 do pending[i] = nil end   -- a new cast never inherits old holds
	castP0, castC, castP1 = nil, nil, nil
	consumeBait()              -- the bait goes in the water with the hook
	STATE = "casting"          -- the hook goes over the shoulder first; sinking starts on splashdown
	setHookVisible(true)
	line.Enabled = false       -- no line until the hook actually leaves the rod
	-- JACKPOT CAST is spent HERE, once, so the whole cast runs under it - the pool that fills
	-- while the hook is down is the pool the hook fishes. Cleared again when the haul finishes,
	-- or a single charge would keep seeding the sea with Mythics forever.
	local jc = plr:GetAttribute("JackpotCasts") or 0
	if jc > 0 then
		plr:SetAttribute("JackpotCasts", jc - 1)
		plr:SetAttribute("JackpotActive", true)
		-- ⚠️ AND RE-SEED THE WATER, or the charge does nothing you can SEE. JackpotActive only
		-- changes what speciesForDepth returns for fish built FROM NOW ON - but the fish this cast
		-- is about to catch were spawned minutes ago under ordinary luck and are already floating
		-- out there. Without this the charge would only improve the fish that REPLACE the ones you
		-- catch, i.e. it would pay out on the cast AFTER the one you spent it on. Re-rolling the
		-- live pool is what makes "1000x luck on your next cast" true of that cast.
		for _, f in ipairs(fishes) do
			if not f.caught then respawnFish(f) end
		end
	end
	report("cast", 1)
	refreshHUD()
end

-- Dev hook, same shape as the menus' DevRoll / DevZone / DevDiscover. Tool-driven
-- tests can't click reliably (and a whole cast finishes inside one tool round-trip),
-- so this lets a test fire a cast and sample it in the same call. :Fire(x) aims that one cast at world x
-- (still held off the bow, exactly like the mouse); :Fire() aims it with the mouse.
local devCast = make("BindableEvent", { Name = "DevCast" }, hud)
devCast.Event:Connect(startCast)

-- Auto Fishing is a SINGLE unlock now (it used to be 6 tiers, 5 of which did nothing but
-- shave 12% off the pause). Owning it is necessary but not sufficient - autoRunning() also
-- checks the on-screen toggle. It drives the very same startCast() a click would, so
-- nothing else in the loop needs to know who threw the line.
local AUTO_PAUSE = 1.6
local autoAt = nil
RunService.Heartbeat:Connect(function()
	if not autoRunning() or STATE ~= "idle" then autoAt = nil; return end
	if not autoAt then
		autoAt = os.clock() + AUTO_PAUSE
	elseif os.clock() >= autoAt then
		autoAt = nil
		startCast()
	end
end)

-- A "+$N" price tag that RIDES its fish. Made the instant the fish is hooked and
-- stuck to it the whole way — trailing up the line, then on through the payout
-- fling — so you can always see what's hanging on the hook. ONE tag per fish for its
-- whole life: the flyer inherits it rather than making a second one, or you'd get two
-- labels on the same fish at the surface. The coins are still only paid in the haul.
local function makeTag(text, color)
	local lbl = make("Part", {
		Name = "PriceTag", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1,
		Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		CastShadow = false,
	}, zone)
	-- BillboardGui Offset pixels shrink with distance, so size this in Scale (studs)
	-- or it renders as a speck.
	local bb = make("BillboardGui", {
		Adornee = lbl, Size = UDim2.fromScale(11, 3.1),
		StudsOffsetWorldSpace = Vector3.new(0, 1.8, 0),
		AlwaysOnTop = true, LightInfluence = 0,
	}, lbl)
	local txt = make("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = FONT,
		TextScaled = true, TextColor3 = color, Text = text,
	}, bb)
	local stroke = make("UIStroke", { Color = INK, Thickness = 3 }, txt)
	return { lbl = lbl, txt = txt, stroke = stroke, bb = bb }
end
local function moveTag(tag, x, y)
	if tag then tag.lbl.CFrame = CFrame.new(x, y, PLAY_Z) end
end
local function destroyTag(tag)
	if tag and tag.lbl then tag.lbl:Destroy() end
end

-- a paid-out fish: flung up off the boat still wearing its price tag, then gone
local function launchFlyer(model, value, tag)
	tag = tag or makeTag("+" .. money(value), GOLD)   -- it should already have one
	if not model or not model.Parent then
		-- no fish to fling, but the money must still reach the total or it under-reports
		sendToTotal(tag, value, 0, 6)
		return
	end
	local p = model:GetPivot().Position
	moveTag(tag, p.X, p.Y)
	-- it came out of the sea a second ago, so it sheds water as it's thrown
	for _ = 1, 3 do
		FX.drip(p.X + (math.random() - 0.5) * 1.5, p.Y + (math.random() - 0.5) * 1.0)
	end

	local vy = FLY_UP + math.random() * 7   -- spread scales with FLY_UP; see the pair note
	local xLand = BOAT_LAND_X0 + math.random() * (BOAT_LAND_X1 - BOAT_LAND_X0)
	-- Flight time to fall back into the hull: solve p.Y + vy*T - FLY_GRAV/2 * T^2 = BOAT_LAND_Y
	-- for the LATER root (the way down). disc can't go negative here (the target is below
	-- the launch) but clamp anyway — a NaN T would strand the fish on screen forever.
	local disc = vy*vy - 2 * FLY_GRAV * (BOAT_LAND_Y - p.Y)
	local T = (vy + math.sqrt(math.max(disc, 0))) / FLY_GRAV
	-- fade targets: the gunwale hides the landing, but a long fish still pokes over the
	-- rim, and popping it out of existence is ugly
	local fadeable = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then
			fadeable[#fadeable+1] = { inst = d, t0 = d.Transparency }
		end
	end

	flyers[#flyers+1] = {
		model = model, tag = tag, value = value, fadeable = fadeable,
		x = p.X, y = p.Y,
		vx = (xLand - p.X) / T,     -- aimed AT the boat, not a random drift
		vy = vy, T = T,
		rot = 0, spin = (math.random() < 0.5 and -1 or 1) * (6 + math.random() * 8),
		t = 0,
	}
end

-- Fish waiting their turn in the payout used to FREEZE in mid-air, because placeCaught
-- only runs while sinking/reeling and the state has already moved to "payout". That is
-- the pause between the catch clearing the water and being thrown. They are now kept
-- strung under the ROD TIP, still easing toward their slot, until they are flung — so the
-- haul reads as one motion: rise out of the water, hang on the line, peel off into the boat.
local function unpend(model)
	for i, p in ipairs(pending) do
		if p.model == model then table.remove(pending, i); return end
	end
end
local function holdPending(dt)
	if #pending == 0 then return end
	-- Hold them where the HOOK finished, not at the rod tip: the hook ends wherever you
	-- steered it, so anchoring to the tip would slide the catch sideways - and with the
	-- CATCH_MAX_LAG leash that slide happens in a single frame, i.e. a visible teleport.
	-- + haulLift: the flick took line in, so the string hangs HIGHER than where the hook
	-- stopped. Without it the rod heaves and the catch ignores it, hanging in the water.
	local base = Vector3.new(hookX, hookY + flick.lift, PLAY_Z)
	for i, p in ipairs(pending) do
		if p.model and p.model.Parent then
			local slot = Vector3.new(base.X, base.Y - CATCH_LEAD - (i - 1) * 1.7, PLAY_Z)
			local cur = p.model:GetPivot().Position
			local np = cur:Lerp(slot, math.min(1, dt * CATCH_FOLLOW))
			local off = np - slot
			if off.Magnitude > CATCH_MAX_LAG then np = slot + off.Unit * CATCH_MAX_LAG end
			p.model:PivotTo(CFrame.new(np) * p.rot)
			moveTag(p.tag, np.X, np.Y)
		end
	end
end

local function finishHaul()
	local list = caught
	caught = {}
	setHookVisible(false)
	Audio.stopLoop("ReelLoop", 0.2)
	Audio.stopLoop("Underwater", 0.5)
	-- THE BREAK. The rod used to snap straight back to rest on this line, so everything
	-- arriving at the surface at once happened while the angler held perfectly still. Start
	-- the heave instead: it pulls the whole strung catch clear of the water and then settles
	-- back to rest on its own. The pose deliberately outlives this call — STATE is about to
	-- become payout, which reelPose no longer drives, so the render loop runs it out.
	local heft = math.clamp(#list / math.max(1, capacity()), 0, 1)
	-- The ANGLE is ROD's now (a seeded keyframe track, so it takes over from mid-pump
	-- without a reversal). flick keeps only the LIFT, which is a gameplay number the
	-- strung catch rides, not an angle.
	ROD.haul(heft)
	flick.pose = { t = 0, lift = HAUL.lift * (0.45 + 0.55 * heft) }
	FX.splash(hookX, 1 + 1.1 * heft)   -- and the catch bursts back out through the surface
	Audio.play("SplashBig", { pitch = 1.05 - 0.15 * heft, volume = 0.9 + 0.4 * heft })
	for _ = 1, 4 + math.floor(6 * heft) do
		FX.bubble(hookX + (math.random() - 0.5) * 3, WATER_Y - math.random() * 4,
			0.3 + math.random() * 0.4)
	end
	RODFX.on("break", heft)   -- water shed all the way up the line, and drop the loop handle
	if deepest > 0 then report("depth", math.floor(deepest)) end

	if #list == 0 then
		STATE = "idle"
		plr:SetAttribute("JackpotActive", false)   -- an empty jackpot cast still spends the charge
		ROD.rate, ROD.heftT, ROD.boltT = 0, 0, 0
		refreshHUD()
		hintLbl.Text = "Empty hook — try again"
		return
	end

	STATE = "payout"
	beginTotal()

	local rare, legend = 0, 0
	for _, c in ipairs(list) do
		local r = c.def.rarity
		if r == "Rare" or r == "Epic" or r == "Mythic" then rare += 1 end
		if r == "Legendary" then legend += 1 end
	end
	report("catch", #list)
	if rare > 0 then report("rare", rare) end
	if legend > 0 then report("legendary", legend) end
	-- the sting is reserved for a Legendary; firing it on every haul would make the one
	-- catch in a hundred that deserves it sound like all the others
	if legend > 0 then task.delay(0.35, function() Audio.play("Fanfare") end) end
	report("cap", #list)

	-- No bucket any more: a catch is paid out in cash right here, so storing a second copy
	-- of it in Inventory just meant SELL ALL paid for the same fish twice.
	-- The Fish Index has to be told too, or the Fishdex never fills in from actual fishing:
	-- it only ever showed its demo seed because nothing here fired Discover. Same shape as
	-- AddCatch — a BindableEvent on the menu, fired best-effort so a missing menu is harmless.
	local dex      = pg:FindFirstChild("IndexMenu")
	local discover = dex and dex:FindFirstChild("Discover")

	for i, c in ipairs(list) do
		local f = c.f
		local model = f.model
		f.model = nil          -- the flyer owns it now; a fresh fish takes its place below
		respawnFish(f)
		local value = valueOf(c.def, c.vmult)
		if model and model.Parent then
			local piv = model:GetPivot()
			pending[#pending+1] = { model = model, tag = c.tag, rot = piv - piv.Position }
		end
		-- one fish at a time, so the money visibly counts up
		task.delay((i - 1) * PAYOUT_GAP, function()
			unpend(model)      -- stop holding it: launchFlyer owns its motion from here
			if discover then pcall(function() discover:Fire(c.def.name) end) end
			addCoins(value)
			report("earn", value)
			-- climbing pitch down the haul, so a big catch pays out as a rising run
			-- rather than the same note N times. Capped, or fish 12 is a squeak.
			Audio.play("Coin", { pitch = 1 + math.min(i - 1, 7) * 0.06 })
			-- no bumpTotal here: the fish's +$ tag flies up and pays into the total when
			-- it ARRIVES, so the number climbs in step with the money landing in it
			launchFlyer(model, value, c.tag)   -- hand over the tag it's already wearing
		end)
	end

	refreshHUD()
	-- the haul's money is the sky total's job now, so this line just celebrates the catch
	hintLbl.Text = "Hauled " .. #list .. " fish!"
	task.delay((#list - 1) * PAYOUT_GAP + 1.5, function()
		if STATE == "payout" then
			STATE = "idle"
			plr:SetAttribute("JackpotActive", false)   -- the charge covered this cast only
			ROD.rate, ROD.heftT, ROD.boltT = 0, 0, 0
			refreshHUD()
		end
	end)
end

local function tryCatch()
	if #caught >= capacity() then return end
	local hp = Vector2.new(hookX, hookY)
	for _, f in ipairs(fishes) do
		if not f.caught and f.model and f.model.Parent then
			-- f.x / f.yy, NOT model:GetPivot(): the render is CULLED now, so a pivot read would
			-- freeze at a stale position for any off-screen fish. The swim pose also offsets the
			-- pivot from the body by up to node*sin(theta), which would wobble the hitbox at the
			-- tail-beat frequency. The catch tracks the SIMULATION: identical on-screen and off.
			local px, py = f.x, f.yy
			local d = (Vector2.new(px, py) - hp).Magnitude
			if d < (CATCH_R + (plr:GetAttribute("UpgCatchRadius") or 0) + f.len * 0.42) then
				f.caught = true
				-- the tag calls out the finish, so a Gold catch reads as a win on sight
				local label = "+" .. money(valueOf(f.def, f.vmult))
				if f.variant then label = f.variant.label .. " " .. label end
				local tag = makeTag(label, f.variant and f.variant.tint or GOLD)
				moveTag(tag, px, py)
				caught[#caught+1] = { f = f, def = f.def, tag = tag, vmult = f.vmult or 1 }
				ROD.bite(f.len)      -- the rod kicks the moment it takes the weight, sized
				                     -- by the fish, and RINGS instead of just decaying
				-- Pitched by SIZE, not rarity: a deep note reads as something heavy on the
				-- line, which is the thing you actually want telegraphed mid-reel.
				RODFX.on("strike", f.len)
				-- the take: a burst off the bait, tinted for a rare finish so a Gold hit
				-- shows in the water before you've had time to read its tag
				for _ = 1, 6 do
					FX.bubble(px + (math.random() - 0.5) * 2.4, py + (math.random() - 0.5) * 2,
						0.24 + math.random() * 0.34, f.variant and f.variant.tint or nil)
				end
				-- pop
				local s  = f.model:GetScale()
				local mm = f.model   -- NOT f.model inside the closure: finishHaul sets f.model = nil
				                     -- and respawnFish puts a NEW fish there inside this 0.12s, so
				                     -- the restore would rescale the replacement. SWIM.tailP is only
				                     -- valid at the scale it was measured at, so that fish's caudal
				                     -- fin would then sit detached from its body for the rest of
				                     -- its life.
				pcall(function() mm:ScaleTo(s * 1.25) end)
				task.delay(0.12, function()
					if mm.Parent then pcall(function() mm:ScaleTo(s) end) end
				end)
				refreshHUD()
				return
			end
		end
	end
end

-- How fast the line comes up. The Reel Speed branch multiplies it; the WEIGHT of what you
-- have already hooked drags it back down, so a heavy haul is a slower catching pass.
-- The counter is the ROD (RodPower, from the equipped tier). The cap is back at 0.55: it
-- was briefly dropped to 0.40 during the window when nothing offset drag at all, but with
-- that cap a heavy hook pins against it and the early rod tiers change nothing — measured
-- tier 1 and tier 2 as identical. 0.55 gives RodPower room to actually show up.
local function reelSpeed()
	local full = (#caught >= capacity())
	local base = full and FULL_REEL_SPEED or REEL_SPEED
	local load = 0
	for _, c in ipairs(caught) do load += (c.f and c.f.len or 3) end
	-- The ROD is the line strength now: each tier past Oakwood shrugs off more of the drag
	-- a heavy haul puts on the reel. This is the mechanic the old Rod Power upgrade used to
	-- provide, moved onto the thing it was always describing. InventoryController publishes
	-- RodPower whenever you equip.
	local drag = math.clamp(load * 0.030 / (1 + (plr:GetAttribute("RodPower") or 0)), 0,
		full and FULL_DRAG_CAP or 0.55)
	-- Rod tier multiplies reel speed on top of the Reel branch. It has to: a tier-10 rod
	-- opens a column several hundred studs deep, and winding that back at the base 26
	-- studs/sec would make the reward for buying it feel like a punishment.
	return base * (plr:GetAttribute("UpgReelMult") or 1)
		* (plr:GetAttribute("BoostReelMult") or 1)      -- Cast Speed potion
		* (plr:GetAttribute("RodReelMult") or 1)
		* (plr:GetAttribute("BoatReelMult") or 1)   -- the boat's winch
		* (plr:GetAttribute("BaitHaste") or 1) * (1 - drag)
end

-- Publishes the fight's WEIGHT to the rig for one frame of the catching pass. The pump
-- itself lives in ROD.stepPump: phase ACCUMULATED, amplitude and frequency rate-limited,
-- frequency INVERTED from the old code (heavy load -> slow deliberate pumps, not faster
-- ones). heft here is the sum of caught fish LENGTHS over 12, which is not the same
-- quantity as finishHaul's #list/capacity - both are wanted, in their own places.
local function reelPose()
	local load = 0
	for _, c in ipairs(caught) do load += (c.f and c.f.len or 3) end
	ROD.heftT = math.clamp(load / 12, 0, 1)
	ROD.boltT = (#caught >= capacity()) and 1 or 0
end

UIS.InputBegan:Connect(function(io, gpe)
	if gpe then return end
	if io.UserInputType ~= Enum.UserInputType.MouseButton1 and io.UserInputType ~= Enum.UserInputType.Touch then return end
	-- the cast is hands-off once thrown: it sinks to max depth, then reels itself up
	if STATE == "idle" then startCast() end
end)

----------------------------------------------------------------------
-- main loop
----------------------------------------------------------------------
-- screen X -> world X on the play plane
local function mouseWorldX()
	local m = UIS:GetMouseLocation()
	local vp = cam.ViewportSize
	local frac = (m.X / math.max(vp.X, 1)) - 0.5
	local minX, maxX = steerBounds()   -- keep the reel in the water, not behind the HUD
	return math.clamp(frac * viewWidth(), minX, maxX)
end

-- World x of the BOW of the boat you are sailing: the furthest +X point of its VISIBLE hull at the waterline
-- (parts below y 6, so a mast, outrigger or rod holder overhead does not count). NOT the seat's model: every
-- tier sits on the server's one Workspace.Rowboat.RowSeat, and a bigger boat is a separate hull BoatClient
-- parents into Workspace as "Boat_<tier>" while it hides the rowboat's parts (Transparency 1, so they drop out
-- here). Measured once per tier - hulls end at x 7.2 (Rowboat) .. 16.4 (Factory Ship) - and half the BoatSpan
-- stands in until that hull is in the world.
local bowCache = { tier = nil, x = 8 }
local function bowX()
	local tier = plr:GetAttribute("CurrentBoat") or 1
	if bowCache.tier == tier then return bowCache.x end
	local hull = (tier == 1) and workspace:FindFirstChild("Rowboat") or nil
	if tier ~= 1 then   -- by name, but never a player's character ("Boat_2" is a legal username)
		for _, c in ipairs(workspace:GetChildren()) do
			if c.Name == "Boat_" .. tier and not Players:GetPlayerFromCharacter(c) then hull = c break end
		end
	end
	local hi = -math.huge
	if hull then
		for _, p in ipairs(hull:GetDescendants()) do
			if p:IsA("BasePart") and p.Transparency < 1 then
				local cf, h = p.CFrame, p.Size * 0.5
				for sx = -1, 1, 2 do for sy = -1, 1, 2 do for sz = -1, 1, 2 do
					local w = cf:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
					if w.Y < 6 and w.X > hi then hi = w.X end
				end end end
			end
		end
	end
	if hi == -math.huge then return (tonumber(plr:GetAttribute("BoatSpan")) or 16) / 2 end   -- not built yet: next cast
	bowCache.tier, bowCache.x = tier, hi
	return hi
end

local shownCoins = getCoins()

-- Strings the catch under the bait. This is deliberately NOT done in the drift pass below:
-- that pass runs BEFORE the state machine moves the hook, so anything placed there renders
-- against LAST frame's hook position — about 2 studs of trailing on its own once the
-- full-hook bolt is running at ~130 studs/s. Called after the hook's CFrame is written so
-- the fish are placed against where the bait actually is this frame.
local function placeCaught(dt)
	for _, f in ipairs(fishes) do
		if f.caught and f.model and f.model.Parent then
			local idx, tag = 0, nil
			for i, c in ipairs(caught) do if c.f == f then idx = i; tag = c.tag end end
			local ty = hookY - CATCH_LEAD - (idx - 1) * (f.len * CATCH_STACK_L + CATCH_STACK_P)
			local slot = Vector3.new(hookX, ty, PLAY_Z)
			local cur = f.model:GetPivot().Position
			local np = cur:Lerp(slot, math.min(1, dt * CATCH_FOLLOW))
			-- speed-independent leash: without this the lag scales with the reel speed
			local off = np - slot
			if off.Magnitude > CATCH_MAX_LAG then np = slot + off.Unit * CATCH_MAX_LAG end
			-- A hooked fish used to SNAP flat on this line - up to 38 deg in one frame, at the
			-- exact moment the camera is on it - and then ride all the way up perfectly rigid.
			-- Blend out of whatever pose it was swimming in, and into a thrash on the line.
			f.ph += SWIM.CAUGHT_W * dt
			f.ang += (SWIM.CAUGHT_A * math.sin(f.ph) - f.ang) * math.min(1, dt * SWIM.CAUGHT_K)
			f.model:PivotTo(CFrame.new(np)
				* ((f.dir > 0) and SWIM.YAW_R or SWIM.YAW_L)
				* SWIM.rotZ(f.ang, f.node))
			moveTag(tag, np.X, np.Y)   -- its price tag rides it all the way up
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()

	-- THE CULL. Half the visible band taken from the CAMERA rather than hardcoded, so it
	-- stays right on any aspect, plus slack. camY is read one frame stale and steps by
	-- v*dt per frame - 6.7 studs at 400 studs/s and 60fps, 12+ at 30fps, and reelSpeed()
	-- runs into the hundreds on a late rod during the full-hook bolt. A FIXED slack would
	-- go NEGATIVE there and the un-cull snap would happen ON screen, to a whole band of
	-- fish at once, on the haul. So carry the measured step (x3: it is one frame late and
	-- the camera is still accelerating).
	local dcam = math.abs(camY - SWIM.lastCamY)
	SWIM.lastCamY = camY
	SWIM.cull = camDistance() * SWIM.TANH + SWIM.SLACK + dcam * 3

	-- fish drift (uncaught only — the catch is placed after the hook moves, see placeCaught)
	for _, f in ipairs(fishes) do
		if f.model and f.model.Parent and not f.caught then
			-- burst/coast owns f.sp and f.yy and runs for EVERY fish, on screen or not
			local e = SWIM.burst(f, dt)
			f.x += f.dir * f.sp * dt
			-- A wrap used to KEEP the fish's species and hand it a brand-new random depth.
			-- That quietly decorrelated species from depth: a fish crosses the 116-stud span
			-- every ~30s, so within a couple of minutes the pool was fully scrambled and
			-- Legendaries were drifting up into shallow water - the exact thing the bands
			-- exist to prevent, arriving through the back door. Re-roll the fish for its new
			-- depth instead, which is the same draw the initial spawn makes. Heading is
			-- preserved and the entry edge forced, so it still swims in from the far side.
			if f.x > SPAWN_X or f.x < -SPAWN_X then
				local dir   = f.dir
				local entry = (f.x > 0) and -SPAWN_X or SPAWN_X
				respawnFish(f)
				f.x, f.dir = entry, dir
			end
			placeFish(f, t, dt, e)
		end
	end

	-- hook
	sinkDrop = 0
	if STATE == "casting" then
		castT += dt
		-- ROD.tipPos is the tip of the pose CURRENTLY ON SCREEN (ROD.step runs further down
		-- this callback, and a Weld's C0 is not solved until after the render), so the hook
		-- sits on a tip the player can actually see. It is also analytic, so this costs no
		-- instance lookup and is correct on a tool-swap frame.
		local tipPos = ROD.tipPos
		if castT < CAST_WINDUP then
			-- 1. backswing + THE PAUSE AT THE TOP: the hook rides the tip over the shoulder
			hook.CFrame = CFrame.new(tipPos)
		elseif castT < CAST_WINDUP + CAST_THROW then
			-- 2. the power stroke, as far as the RELEASE point. The whoosh is no longer fired
			-- from here: it rides the TIP SPEED (RODFX.air), which lands it on the STOP rather
			-- than the start - measured, peak tip speed is within 20ms of the hand stop, and
			-- this block fired it 160ms early. Riding the speed also gives the backswing its
			-- own lighter whoosh for free and re-tunes itself if these durations ever move.
			hook.CFrame = CFrame.new(tipPos)
		else
			-- 3. released: hook arcs off the tip into the water while the rod settles.
			--    Aim is read HERE, not at cast start, so you can still adjust during the wind-up.
			if not castP0 then
				castP0 = tipPos
				-- OFF THE BOW (2026-10-11, the owner: "the reel is thrown out on top of the character rather than to
				-- the right of him"). This was mouseWorldX() verbatim, so a mouse resting over the boat - or a phone
				-- tap on it - threw the hook BACK over the angler's head and dropped it into the hull (the trailer
				-- shoot's cursor sat at x -5.3, inside a rowboat spanning -8.0..7.2). The rod points +X, so the
				-- landing is held to open water CAST_CLEAR past the bow of whatever boat you are sailing; aiming
				-- further out works exactly as before.
				local _, maxX = steerBounds()
				local minX = math.min(bowX() + CAST_CLEAR, maxX)   -- a screen too narrow for both: stay on screen
				castP1 = Vector3.new(math.clamp(castAimX or mouseWorldX(), minX, maxX), WATER_Y, PLAY_Z)
				castAimX = nil
				-- a lifted control point guarantees a pretty arc; solving ballistics from a
				-- rod tip 11 studs up just throws it flat at the water
				castC = (castP0 + castP1) * 0.5 + Vector3.new(0, CAST_ARC, 0)
				line.Enabled = true
				RODFX.on("release")
			end
			local p = math.clamp((castT - CAST_WINDUP - CAST_THROW) / CAST_FLY, 0, 1)
			local u = 1 - p
			hook.CFrame = CFrame.new(castP0 * (u*u) + castC * (2*u*p) + castP1 * (p*p))
			-- deliberately NO pose call: the rod is still sweeping the last 30% of its
			-- stroke UNDER the departing hook, which is the release cue
			flick.trail -= dt
			if flick.trail <= 0 then
				local hp = hook.CFrame.Position
				FX.streak(hp.X, hp.Y)   -- the bait leaves a trail across the arc
				flick.trail = HAUL.trail
			end
			if p >= 1 then
				-- both the splash and its FX now scale with how fast the hook actually
				-- arrives, instead of a hardcoded 1.15. Bezier speed at p=1 is
				-- 2*(P1-C)/CAST_FLY, which is free here.
				RODFX.on("splash", (2 * (castP1 - castC) / CAST_FLY).Magnitude, castP1.X)
				-- the bed stays under the whole submerged stretch and lifts at the break
				Audio.startLoop("Underwater", 0.9)
				hookX, hookY = castP1.X, WATER_Y
				castP0, castC, castP1 = nil, nil, nil
				-- the tip now follows the line down toward the entry point instead of
				-- freezing for the whole multi-second plunge
				ROD.play(ROD.SINK)
				STATE = "sinking"      -- hand off to the existing loop, untouched
			end
		end
		hookBand.CFrame = hook.CFrame
		refreshHUD()
	elseif STATE == "sinking" then
		-- Straight down, NO steering: the plunge is committed, you aimed it on the cast.
		-- hookX is deliberately left alone here so the line stays vertical.
		local remaining = hookY - (WATER_Y - maxDepth())
		local brake = (remaining < SINK_BRAKE)
			and math.max(SINK_BRAKE_MIN, remaining / SINK_BRAKE) or 1
		local y0 = hookY
		hookY -= SINK_SPEED * brake * (plr:GetAttribute("BaitHaste") or 1)
			* (plr:GetAttribute("BoostHaste") or 1) * dt   -- Hook Speed potion
		ROD.brk = brake   -- the line is taut at full plunge and slackens as the hook brakes
		deepest = math.max(deepest, WATER_Y - hookY)
		if hookY <= WATER_Y - maxDepth() then
			hookY = WATER_Y - maxDepth()
			STATE = "reeling"
			ROD.play(ROD.REEL)                  -- and the pump blends in from zero
			Audio.startLoop("ReelLoop", 0.75)   -- the catching pass has a sound now
			-- Published for the TUTORIAL, whose CAST step holds until here. Its next line is
			-- "move as it reels back up", and the plunge above deliberately ignores steering, so
			-- advancing on the cast itself put that instruction on screen seconds before it was
			-- true. A COUNTER, not a flag: GetAttributeChangedSignal does not fire when a value
			-- is rewritten with the one it already holds, so a flag would go silent from the
			-- second cast onwards. This is the ONLY transition into "reeling".
			plr:SetAttribute("ReelStarts", (plr:GetAttribute("ReelStarts") or 0) + 1)
		end
		sinkDrop = y0 - hookY
		refreshHUD()
	elseif STATE == "reeling" then
		-- a full hook can't catch anything else, so stop dawdling and haul it in
		ROD.rate = reelSpeed()   -- the crank is geared to the LINE, so it stalls when this does
		hookY += ROD.rate * dt
		hookX += (mouseWorldX() - hookX) * math.min(1, dt * 7)
		tryCatch()
		reelPose()
		-- ROD.BREAK_Y, NOT the live tip. The rest pose moved 2.5 -> 38 degrees, which lifted
		-- the tip from ~3.2 to ~7.7: reeling all the way to it would leave the catch hanging
		-- in the air while finishHaul's splash fired at the waterline. It would also be a
		-- MOVING target - the pump swings the tip +/-1.2 studs.
		local top = ROD.tipPos.Y
		if top > ROD.BREAK_Y then top = ROD.BREAK_Y end
		if hookY >= top then finishHaul() end
		refreshHUD()
	end

	-- THE HAUL'S LIFT. Still on its own timer rather than off STATE, because the whole
	-- point is that it outlives the move to payout - ROD's haul track does the same. The
	-- ANGLE is ROD's now; this is bookkeeping only.
	if flick.pose then
		local h = flick.pose
		h.t += dt
		-- The lift only ever grows: line that has been pulled in doesn't pay back out, so the
		-- catch stays up where the heave put it while the rod itself settles back down.
		-- smoothstep, not easeOutCubic: easeOutCubic'(0) = 3, so the lift's RATE jumped
		-- 0 -> 67 studs/s in one frame and holdPending fed that straight into the strung
		-- catch. Still monotone on [0,1], so the contract is unchanged.
		local p = math.clamp(h.t / ROD.HAUL_RISE, 0, 1)
		flick.lift = h.lift * (p * p * (3 - 2 * p))
		if h.t >= ROD.HAUL_RISE + ROD.HAUL_FALL then flick.pose = nil end
	end

	if STATE == "sinking" or STATE == "reeling" then
		hook.CFrame = CFrame.new(hookX, hookY, PLAY_Z)
		hookBand.CFrame = hook.CFrame
		-- The bait is never silent under water: speed streaks on the committed plunge, and
		-- the odd bubble off it while the reel works its way back up.
		flick.trail -= dt
		if flick.trail <= 0 then
			if STATE == "sinking" then
				FX.streak(hookX + (math.random() - 0.5) * 0.6, hookY)
				flick.trail = HAUL.trail
			else
				FX.bubble(hookX + (math.random() - 0.5) * 1.2, hookY, 0.2 + math.random() * 0.24)
				flick.trail = HAUL.trail * 6
			end
		end
		placeCaught(dt)      -- now that the bait has moved, hang the catch off it
	elseif STATE == "payout" then
		holdPending(dt)      -- keep un-thrown fish alive on the line instead of frozen
	end

	-- THE ONE C0 WRITE IN THE CLIENT, every frame including idle, from the ONE existing
	-- connection - so no new ordering surface is introduced and the old "sometimes write,
	-- sometimes restore gripC0" special case is gone. It runs AFTER the state machine, so
	-- the ROD.tipPos read up there is the pose currently ON SCREEN.
	-- pcall because this single callback also runs the fish, the FX pool, the flyers, the
	-- coin flights and the camera: an unguarded error in the rod code freezes the entire
	-- game, which reads as a hang rather than as a rod bug.
	local rok, rerr = pcall(ROD.step, dt)
	if not rok and (t - (ROD.faultAt or 0)) > 2 then
		ROD.faultAt = t
		warn("[ROD] " .. tostring(rerr))
	end
	-- AFTER hook.CFrame, so the sag is solved against THIS frame's hook rather than last
	-- frame's. Uses ROD.tipDrawn - the same tip the hook was placed on - so the beam's
	-- origin and the hook never disagree by a frame at whip speed.
	ROD.line()
	RODFX.step(dt)

	-- one pass over every droplet, jet, ripple, bubble, drip and trail dot in the air
	for i = #FX.list, 1, -1 do
		local e = FX.list[i]
		e.t += dt
		if e.grav then e.vy -= e.grav * dt end
		e.x += e.vx * dt
		e.y += e.vy * dt
		local p = math.clamp(e.t / e.life, 0, 1)
		if e.grow then e.p.Size = e.size0 * math.max(0.05, 1 + e.grow * p) end
		e.p.CFrame = CFrame.new(e.x, e.y, PLAY_Z)
		e.p.Transparency = e.tr0 + (1 - e.tr0) * p
		if p >= 1 then e.p:Destroy(); table.remove(FX.list, i) end
	end

	-- fish flung up at payout
	for i = #flyers, 1, -1 do
		local fl = flyers[i]
		fl.t += dt
		fl.vy -= FLY_GRAV * dt
		fl.x += fl.vx * dt
		fl.y += fl.vy * dt
		fl.rot += fl.spin * dt
		if fl.model.Parent then
			fl.model:PivotTo(CFrame.new(fl.x, fl.y, PLAY_Z) * CFrame.Angles(0, 0, fl.rot))
		end
		-- the tag rides its fish just long enough to read, then peels off to the total
		if fl.tag then
			moveTag(fl.tag, fl.x, fl.y)
			if fl.t >= TAG_HANDOFF then
				sendToTotal(fl.tag, fl.value, fl.x, fl.y)
				fl.tag = nil
			end
		end
		-- it drops behind the near gunwale on the way in, so this only ever shows on a
		-- long fish poking over the rim — but that pop is exactly what you'd notice
		-- 0.21, not 0.30: this window has to cover a fixed DISTANCE above the rim, not a
		-- fixed time. The fish falls sqrt(2)x faster since FLY_GRAV went to 40, so the old
		-- 0.30s started the fade half a fish-length higher and ghosted it out in clear air.
		local fade = math.clamp((fl.t - (fl.T - 0.21)) / 0.21, 0, 1)
		if fade > 0 then
			for _, r in ipairs(fl.fadeable) do
				if r.inst.Parent then r.inst.Transparency = r.t0 + (1 - r.t0) * fade end
			end
		end
		if fl.t >= fl.T then          -- landed in the boat
			fl.model:Destroy()
			if fl.tag then destroyTag(fl.tag) end
			table.remove(flyers, i)
		end
	end

	-- fish money flying up into the total; each coin pays in the moment it lands
	for i = #coinFlights, 1, -1 do
		local f = coinFlights[i]
		f.t += dt
		local p = math.clamp(f.t / COIN_FLIGHT, 0, 1)
		local e = p * p                       -- hang off the fish, then zip in
		local u = 1 - e
		-- quadratic Bezier fish -> bowed control -> the total
		moveTag(f.tag,
			u*u*f.x0 + 2*u*e*f.cx,
			u*u*f.y0 + 2*u*e*f.cy + e*e*TOTAL_Y)
		local s = 1 - 0.45 * e                -- shrink as it's swallowed
		f.tag.bb.Size = UDim2.fromScale(TAG_W * s, TAG_H * s)
		-- dissolve over the last stretch so it merges INTO the number. Both are
		-- AlwaysOnTop, so without this the coin visibly clips through the total.
		local fade = math.max(0, (e - 0.72) / 0.28)
		f.tag.txt.TextTransparency = fade
		f.tag.stroke.Transparency = fade
		if p >= 1 then
			bumpTotal(f.value)                -- THIS is what makes the number climb
			destroyTag(f.tag)
			table.remove(coinFlights, i)
		end
	end

	-- the haul total: springs in, punches on every fish, counts up, then floats off
	if tot.live then
		tot.t += dt
		tot.shown += (tot.real - tot.shown) * math.min(1, dt * 10)
		if math.abs(tot.real - tot.shown) < 1 then tot.shown = tot.real end
		totalLbl.Text = "+" .. money(tot.shown + 0.5)

		tot.punch -= tot.punch * math.min(1, dt * 11)
		tot.tilt  -= tot.tilt  * math.min(1, dt * 9)
		if tot.hold > 0 then tot.hold -= dt else tot.out = math.min(1, tot.out + dt / 0.7) end

		local scale = easeOutBack(math.clamp(tot.t / 0.22, 0, 1)) * (1 + tot.punch)
		totalBB.Size = UDim2.fromScale(TOTAL_W * scale, TOTAL_H * scale)
		totalBB.StudsOffsetWorldSpace = Vector3.new(0, tot.punch * 1.4 + tot.out * 5, 0)
		totalLbl.Rotation = tot.tilt
		totalLbl.TextTransparency = tot.out
		totalStroke.Transparency = tot.out
		if tot.out >= 1 then hideTotal() end
	end

	-- money ticks up toward the real total, Tiny-Fishing style
	local real = getCoins()
	if shownCoins ~= real then
		shownCoins += (real - shownCoins) * math.min(1, dt * 5)
		if math.abs(real - shownCoins) < 1 then shownCoins = real end
	end
	coinLbl.Text = "💰  " .. money(shownCoins + 0.5)

	-- camera: high and wide at rest, drops to follow the hook down once you cast
	local wantY = IDLE_CAM_Y
	local camRate = 5
	if STATE == "sinking" then
		-- TRACK THE HOOK, NOT THE LINE (2026-10-11, the owner: "its not tracking the tip where the red sphere is,
		-- its tracking the line"). An eased follow settles speed/camRate BEHIND a moving target: on the 132 stud/s
		-- plunge that is 26 studs, and with the reel's CAM_LEAD on top the hook rode ~35 studs below centre in a
		-- frame only ~29 tall, so the whole dive showed line and no hook. The camera now RIDES the hook - moves by
		-- exactly this frame's drop - and eases only the framing, which lags at no speed (BaitHaste and the Hook
		-- Speed potion included). It holds at PLAY_CAM_Y until the hook is deep enough to need following.
		-- Across the BRAKE ZONE the framing slides from SINK_LEAD to the reel's CAM_LEAD and the ride fades out,
		-- so the frame the hook bottoms out already has the reel camera's target and speed. Switched in one
		-- frame instead, the camera reversed from falling 21 stud/s to rising 64 (3x the reel) and the whole
		-- scene jerked - this is what lets the handover still read as the hook settling (see SINK_BRAKE).
		local s = 1 - math.clamp((hookY - (WATER_Y - maxDepth())) / SINK_BRAKE, 0, 1)
		wantY = math.min(PLAY_CAM_Y, hookY - SINK_LEAD + (SINK_LEAD + CAM_LEAD) * s)
		if wantY < PLAY_CAM_Y then camY -= sinkDrop * (1 - s) end
	elseif STATE == "reeling" then
		wantY = math.min(PLAY_CAM_Y, hookY + CAM_LEAD)
		-- the full-hook sprint outruns a lazy lerp and leaves the hook off the top of frame
		if #caught >= capacity() then camRate = 10 end
	end
	camY += (wantY - camY) * math.min(1, dt * camRate)
	applyCamera()
end)

cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyCamera)
setHookVisible(false)
refreshHUD()

print(string.format("[GameClient] 2.5D loop online — FOV %d, %.0f studs across, %d fish, max depth %dm",
	CAM_FOV, TARGET_VIEW_W, #fishes, maxDepth()))
