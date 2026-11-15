--[==[
	QuestsController - fishing-game "Quests" (sea candy edition)

	Objectives are modelled on Tiny Fishing's actual loop - cast, depth reached,
	fish per cast, fish value, rarity, species collected - rather than generic
	simulator busywork, plus this game's own systems (bait reel, zones, rebirth).

	Three tabs:
	    📅 Daily      - 6 quests drawn from a pool of 18, rotate every day, 24h reset
	    🗓️ Weekly     - 4 quests drawn from a pool of 14, rotate every week, 7d reset
	    🏅 Milestones  - 11 permanent tiered goals, claim each tier as you pass it

	STATE (player attributes, same convention as Set_<key> / Zone_<id>):
	    QP_<questId>  progress on an active daily/weekly
	    QC_<questId>  true once claimed
	    QT_<verb>     lifetime total for a verb (drives Milestones)
	    MT_<mileId>   highest milestone tier claimed
	    Q_DayStamp / Q_WeekStamp   period rollover + rotation seed
	  and on this ScreenGui: Claimable = how many quests / tiers can be claimed right now.

	REPORTING - this is the hook for the fishing loop when it exists:
	    QuestsMenu.Report:Fire(verb, amount)            (client)
	    ReplicatedStorage.QuestRemotes.Report:FireClient(plr, verb, amount)  (server)
	  verbs: cast · catch · earn · depth · rare · legendary · cap
	         roll · discover · rebirth · travel   <- these 4 are auto-wired already

	ALL ELEVEN VERBS ARE LIVE. GameClient reports cast / depth / catch / rare /
	legendary / cap / earn out of the real fishing loop, and roll / discover /
	rebirth / travel are auto-wired below. Nothing in the pools sits dead at 0 -
	if you add a quest, check its verb is on that list first.

	Test hook: QuestsMenu.DevQuest:Fire(verb, amount) / :Fire("__COMPLETE__")
	           / :Fire("__RESET__") / :Fire("__OPEN__") / :Fire("__ROLLOVER__", n)

	2026-10-10 - THE LOOK MOVED ONTO ReplicatedStorage.ShopKit (the rebuilt Shop's "sea candy" kit), together
	with the other eight MenuBar menus, at the owner's request ("rework the uis ... based on this theme ... i just
	want it to look better"). ONLY THE DRAWING CHANGED: every pool, attribute, remote, Dev verb, TouchKit.press,
	the MenuFit fit and the phone layout are the same code as before. What it draws now:
	  * UI.window: lagoon body with rising bubbles and light rays, a coral header with a wave crest, the gold
	    title, the 📜 breaking out of the top-left corner, the red key X (still a TextButton named "TextButton" -
	    TutorialController's closeButtonOf() finds every window's X by that; it is the only one in this gui);
	  * your coins and pearls in static key pills (the Shop's cash pill), tabs as candy keys (gold = the tab you
	    are on, sea = the others) with a red "!" disc when something on them can be claimed, and the old
	    header subtitle as a navy clock chip at the end of the tab row;
	  * every quest a UI.candyRow slab in its VERB's candy colour (VERB_CANDY / MILE_CANDY), its emoji on a soft
	    glow, a candy progress bar (dark rounded track, INK outline, a lime fill that turns gold once the goal is
	    reached), a gold reward chip, and ONE key in the state's colour: grey IN PROGRESS, green CLAIM!, gold
	    CLAIMED / COMPLETE with the check badge (and the card's gold ring);
	  * the toast is the Shop's chip at the window's foot. It no longer fades, so the old bug of a fade tween
	    outliving its token (a toast that arrived 2.1-2.5 s after the last one stayed invisible) went with it.
	The 📜 reaches 44 design px over the window, so off a phone fit() holds the scale to what keeps it under the
	Roblox top bar (clearTopBar - the Shop's rule: body centred, the reach under the bar); a phone puts the
	emoji inside its 62 px header instead and is centred on the screen (MenuFit.centre, 2026-10-11). Pre-candy source:
	ServerStorage.MenuBackup_PreCandy_2026-10-10.QuestsController.
]==]

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local StarterGui        = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService        = game:GetService("GuiService")
-- Touch: gives every control below a 44px hit pad on phones (art is untouched).
local TouchKit = require(ReplicatedStorage:WaitForChild("TouchKit"))
-- The look (2026-10-10): the Shop's kit. Shared by the Shop and every menu - never edited from here.
local UI = require(ReplicatedStorage:WaitForChild("ShopKit"))

local plr = Players.LocalPlayer
local pg  = plr:WaitForChild("PlayerGui")
local gui = script.Parent

----------------------------------------------------------------------
-- small helpers
----------------------------------------------------------------------
local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end
local V2 = Vector2.new
local make = UI.new   -- Instance.new + props (+ BorderSizePixel 0 on GuiObjects)

local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local function abbrev(n)
	n = math.floor(n + 0.5)
	if n < 1000 then return tostring(n) end
	local tier = math.clamp(math.floor(math.log(n, 1000)), 1, #SUFFIX - 1)
	return string.format("%.2f%s", n / (1000 ^ tier), SUFFIX[tier + 1])
end
local function money(n) return "$" .. abbrev(n) end
local function commas(n)
	local s = tostring(math.floor(n))
	local o = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (o:gsub("^,", ""))
end

----------------------------------------------------------------------
-- quest pools.  Every emoji here is <= Unicode 11.0 (newer ones tofu).
--   verb  = which reported event feeds it
--   mode  = "sum" (default, accumulates) or "max" (best single value, e.g. depth)
--   fmt   = "num" (default) or "money"
--   (accent is the pre-candy card colour; the cards now take VERB_CANDY below)
----------------------------------------------------------------------
local DAILY_POOL = {
	{ id="d_cast",     icon="🎣", accent=rgb(92,204,224),  name="Wet the Line",   desc="Cast your line %d times",                      verb="cast",     goal=25,    coins=2500 },
	{ id="d_catch",    icon="🐟", accent=rgb(96,196,246),  name="Full Bucket",    desc="Reel in %d fish",                              verb="catch",    goal=50,    coins=4000 },
	{ id="d_depth",    icon="⚓", accent=rgb(96,172,242),  name="Down Deep",      desc="Reach %dm on a single cast",  mode="max",      verb="depth",    goal=60,    coins=3500 },
	{ id="d_rare",     icon="✨", accent=rgb(182,142,244), name="Something Shiny", desc="Hook %d Rare or better fish",                 verb="rare",     goal=3,     coins=5000 },
	{ id="d_earn",     icon="💰", accent=rgb(240,202,84),  name="Day's Haul",     desc="Earn %s from your catch",     fmt="money",     verb="earn",     goal=10000, coins=3000 },
	{ id="d_roll",     icon="🐛", accent=rgb(242,124,182), name="Bait Up",        desc="Roll the bait reel %d times",                  verb="roll",     goal=5,     coins=2000 },
	{ id="d_cap",      icon="🐠", accent=rgb(70,204,180),  name="Line 'Em Up",    desc="Catch %d fish on a single cast", mode="max",   verb="cap",      goal=5,     coins=3000 },
	{ id="d_discover", icon="📖", accent=rgb(96,214,128),  name="New Face",       desc="Discover %d new species",                      verb="discover", goal=1,     coins=4000 },
	-- 2026-09-02: pool 8 -> 18, and the daily line-up 4 -> 6. The second entry for a verb
	-- is deliberately a STRETCH version of the first (75 casts against 25, 150 fish against
	-- 50) rather than a re-skin, so a day that rolls both still reads as two jobs. Payouts
	-- stay inside the old 2K-5K band's shape, just scaled to the bigger goals.
	{ id="d_cast2",    icon="🌊", accent=rgb(72,182,232),  name="All Day Angler", desc="Cast your line %d times",                      verb="cast",     goal=75,     coins=5000 },
	{ id="d_catch2",   icon="💧", accent=rgb(120,208,246), name="Overflowing Net",desc="Reel in %d fish",                              verb="catch",    goal=150,    coins=7000 },
	{ id="d_depth2",   icon="🌀", accent=rgb(72,122,220),  name="The Long Drop",  desc="Reach %dm on a single cast",  mode="max",      verb="depth",    goal=150,    coins=6500 },
	{ id="d_rare2",    icon="💎", accent=rgb(150,120,244), name="Jewel Hunter",   desc="Hook %d Rare or better fish",                  verb="rare",     goal=10,     coins=8000 },
	{ id="d_earn2",    icon="💵", accent=rgb(96,232,138),  name="Big Day Out",    desc="Earn %s from your catch",     fmt="money",     verb="earn",     goal=150000, coins=7500 },
	{ id="d_roll2",    icon="🎁", accent=rgb(242,150,196), name="Bait Hoarder",   desc="Roll the bait reel %d times",                  verb="roll",     goal=20,     coins=5500 },
	{ id="d_cap2",     icon="🦈", accent=rgb(70,190,180),  name="Loaded Hook",    desc="Catch %d fish on a single cast", mode="max",   verb="cap",      goal=9,      coins=6000 },
	{ id="d_legend",   icon="👑", accent=rgb(250,190,52),  name="For the Wall",   desc="Land %d Legendary fish",                       verb="legendary",goal=1,      coins=9000 },
	{ id="d_travel",   icon="🗺", accent=rgb(70,214,128),  name="Change of Water",desc="Travel between fishing zones %d times",        verb="travel",   goal=1,      coins=3000 },
	{ id="d_discover2",icon="🔍", accent=rgb(120,220,150), name="Field Notes",    desc="Discover %d new species",                      verb="discover", goal=3,      coins=9000 },
}
local WEEKLY_POOL = {
	{ id="w_catch",    icon="🐠", accent=rgb(96,196,246),  name="Trawlerman",     desc="Reel in %d fish",                              verb="catch",    goal=500,     coins=60000,  pearls=2 },
	{ id="w_depth",    icon="⚓", accent=rgb(72,122,220),  name="Trench Runner",  desc="Reach %dm on a single cast",  mode="max",      verb="depth",    goal=200,     coins=80000,  pearls=3 },
	{ id="w_legend",   icon="👑", accent=rgb(250,190,52),  name="Trophy Catch",   desc="Land %d Legendary fish",                       verb="legendary",goal=1,       coins=120000, pearls=5 },
	{ id="w_earn",     icon="💎", accent=rgb(120,246,246), name="Big Money",      desc="Earn %s from your catch",     fmt="money",     verb="earn",     goal=1000000, coins=75000,  pearls=3 },
	{ id="w_discover", icon="📖", accent=rgb(96,214,128),  name="Naturalist",     desc="Discover %d new species",                      verb="discover", goal=5,       coins=90000,  pearls=4 },
	{ id="w_travel",   icon="🗺", accent=rgb(70,214,128),  name="Fresh Water",    desc="Travel between fishing zones %d times",        verb="travel",   goal=3,       coins=50000,  pearls=2 },
	-- 2026-09-02: pool 6 -> 14, weekly line-up 3 -> 4. A weekly is a WEEK of the daily it
	-- shadows (1200 casts ≈ 75/day x 16 sessions), and the two hardest - Abyss Bound and
	-- Fortune Seeker - are deliberately end-game: 450m needs most of the depth ladder plus
	-- a late rod, and $50M is roughly an hour at a maxed income.
	{ id="w_cast",     icon="🎣", accent=rgb(92,204,224),  name="Tireless Hands", desc="Cast your line %d times",                      verb="cast",     goal=1200,     coins=70000,  pearls=3 },
	{ id="w_rare",     icon="✨", accent=rgb(182,142,244), name="Rare Collector", desc="Hook %d Rare or better fish",                  verb="rare",     goal=60,       coins=95000,  pearls=4 },
	{ id="w_roll",     icon="🐛", accent=rgb(242,124,182), name="Reel Fanatic",   desc="Roll the bait reel %d times",                  verb="roll",     goal=200,      coins=60000,  pearls=2 },
	{ id="w_cap",      icon="💧", accent=rgb(70,204,180),  name="Full House",     desc="Catch %d fish on a single cast", mode="max",   verb="cap",      goal=12,       coins=85000,  pearls=4 },
	{ id="w_depth2",   icon="🌀", accent=rgb(60,100,200),  name="Abyss Bound",    desc="Reach %dm on a single cast",  mode="max",      verb="depth",    goal=450,      coins=160000, pearls=7 },
	{ id="w_earn2",    icon="🏆", accent=rgb(255,206,84),  name="Fortune Seeker", desc="Earn %s from your catch",     fmt="money",     verb="earn",     goal=50000000, coins=180000, pearls=8 },
	{ id="w_catch2",   icon="🐳", accent=rgb(80,170,236),  name="Deep Harvest",   desc="Reel in %d fish",                              verb="catch",    goal=2500,     coins=170000, pearls=7 },
	{ id="w_rebirth",  icon="🌊", accent=rgb(132,110,240), name="Turn of the Tide",desc="Rebirth %dx this week",                       verb="rebirth",  goal=1,        coins=250000, pearls=12 },
}

-- Milestones read live/lifetime state rather than a per-period counter.
local MILESTONES = {
	{ id="m_angler",  icon="🎣", accent=rgb(92,204,224),  name="Angler",      unit="fish caught",       stat=function() return plr:GetAttribute("QT_catch") or 0 end,
	  tiers={100,1000,10000,100000},   coins={5000,50000,600000,9000000},  pearls={0,1,3,8} },
	{ id="m_deep",    icon="⚓", accent=rgb(96,172,242),  name="Deep Diver",  unit="metres deep",       stat=function() return plr:GetAttribute("QT_depth") or 0 end,
	  tiers={50,150,400,1000},         coins={4000,40000,500000,7500000},  pearls={0,1,3,8} },
	{ id="m_collect", icon="📖", accent=rgb(96,214,128),  name="Collector",   unit="species found",     stat=function()
			local ix = pg:FindFirstChild("IndexMenu")
			return (ix and ix:GetAttribute("Discovered")) or 0
		end,
	  tiers={10,25,40,61},             coins={6000,60000,750000,12000000}, pearls={1,2,5,12} },
	{ id="m_rich",    icon="💰", accent=rgb(240,202,84),  name="Tycoon",      unit="earned", fmt="money", stat=function() return plr:GetAttribute("QT_earn") or 0 end,
	  tiers={100000,10000000,1000000000,1000000000000}, coins={8000,80000,900000,15000000}, pearls={0,2,4,10} },
	{ id="m_reborn",  icon="🌀", accent=rgb(132,110,240), name="Reborn",      unit="rebirths", unitOne="rebirth", stat=function() return plr:GetAttribute("Rebirths") or 0 end,
	  tiers={1,5,10,25},               coins={10000,120000,1500000,20000000}, pearls={2,5,10,25} },
	{ id="m_explore", icon="🗺", accent=rgb(70,214,128),  name="Explorer",    unit="zones unlocked",    stat=function()
			local n = 0
			for i = 1, 6 do if i == 1 or plr:GetAttribute("Zone_" .. i) == true then n += 1 end end
			return n
		end,
	  tiers={2,3,4,6},                 coins={20000,200000,2000000,25000000}, pearls={1,3,6,15} },
	{ id="m_bait",    icon="🐛", accent=rgb(242,124,182), name="Bait Master", unit="baits rolled",      stat=function() return plr:GetAttribute("QT_roll") or 0 end,
	  tiers={50,500,5000,50000},       coins={5000,50000,600000,8000000},  pearls={0,1,3,8} },
	-- 2026-09-02: four more permanent ladders. Each reads a QT_ total report() already
	-- keeps, so they backfill from play that happened before this edit rather than
	-- starting everyone at zero. Full Hook tops out at 17 on purpose - that is exactly
	-- BASE_CAP 3 + the Hook Capacity branch's 14 tiers, i.e. "max out your hook".
	{ id="m_caster",  icon="🌊", accent=rgb(72,182,232),  name="Caster",      unit="casts made", unitOne="cast made", stat=function() return plr:GetAttribute("QT_cast") or 0 end,
	  tiers={250,2500,25000,250000},   coins={4000,45000,550000,8000000},  pearls={0,1,3,8} },
	{ id="m_rare",    icon="✨", accent=rgb(182,142,244), name="Treasure Hunter", unit="rare fish landed", stat=function() return plr:GetAttribute("QT_rare") or 0 end,
	  tiers={25,250,2500,25000},       coins={7000,70000,800000,11000000}, pearls={1,2,5,12} },
	{ id="m_legend",  icon="👑", accent=rgb(250,190,52),  name="Legend Hunter", unit="Legendary fish landed", stat=function() return plr:GetAttribute("QT_legendary") or 0 end,
	  tiers={1,10,100,1000},           coins={15000,150000,1800000,22000000}, pearls={2,6,12,30} },
	{ id="m_haul",    icon="🐠", accent=rgb(242,152,90),  name="Full Hook",   unit="fish on one cast", stat=function() return plr:GetAttribute("QT_cap") or 0 end,
	  tiers={5,10,15,17},              coins={6000,60000,700000,10000000}, pearls={1,2,5,12} },
}

-- 2026-10-10: a card is a candy slab in its VERB's colour (UI.CANDY), so depth quests read royal blue on
-- every tab and the milestone that counts the same thing matches them.
local VERB_CANDY = {
	cast = "cyan", catch = "blue", depth = "royal", rare = "purple", legendary = "fire", earn = "orange",
	roll = "pink", cap = "teal", discover = "emerald", travel = "aurora", rebirth = "cosmic",
}
local MILE_CANDY = {
	m_angler = "blue", m_deep = "royal", m_collect = "emerald", m_rich = "orange", m_reborn = "cosmic",
	m_explore = "aurora", m_bait = "pink", m_caster = "cyan", m_rare = "purple", m_legend = "fire", m_haul = "teal",
}

-- How many of each pool are live at once. Raised with the pools (4 -> 6, 3 -> 4): the
-- cards sit in a ScrollingFrame, so a longer list scrolls rather than overflowing,
-- and pickN's seeded shuffle still gives a different line-up every period.
local DAILY_COUNT, WEEKLY_COUNT = 6, 4

----------------------------------------------------------------------
-- state
----------------------------------------------------------------------
local function progOf(id)    return plr:GetAttribute("QP_" .. id) or 0 end
local function claimedOf(id) return plr:GetAttribute("QC_" .. id) == true end
local function tierOf(id)    return plr:GetAttribute("MT_" .. id) or 0 end

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
-- No shared currency exists yet (every other menu keeps its own demo balance), so
-- coins land in leaderstats if a real one ever appears, else on a Coins attribute
-- as the forward-looking home. Pearls are REAL — RebirthController reads them.
local function addCoins(n)
	local m = coinSource()
	if m then pcall(function() m.Value = m.Value + n end)
	else plr:SetAttribute("Coins", getCoins() + n) end
end
local function getPearls() return plr:GetAttribute("Pearls") or 0 end
local function addPearls(n) plr:SetAttribute("Pearls", getPearls() + n) end

----------------------------------------------------------------------
-- period rollover + deterministic rotation
----------------------------------------------------------------------
local DAY, WEEK = 86400, 604800
local function dayIndex()  return math.floor(os.time() / DAY) end
local function weekIndex() return math.floor(os.time() / WEEK) end

-- seeded shuffle so every session/client agrees on today's line-up
local function pickN(pool, n, seed)
	local rng = Random.new(seed)
	local idx = {}
	for i = 1, #pool do idx[i] = i end
	for i = #idx, 2, -1 do
		local j = rng:NextInteger(1, i)
		idx[i], idx[j] = idx[j], idx[i]
	end
	local chosen = {}
	for i = 1, math.min(n, #pool) do chosen[#chosen+1] = idx[i] end
	table.sort(chosen)                     -- stable display order
	local out = {}
	for _, i in ipairs(chosen) do out[#out+1] = pool[i] end
	return out
end

local activeDaily, activeWeekly = {}, {}
local function clearPeriod(pool)
	for _, q in ipairs(pool) do
		plr:SetAttribute("QP_" .. q.id, 0)
		plr:SetAttribute("QC_" .. q.id, false)
	end
end
local function rollPeriods()
	if plr:GetAttribute("Q_DayStamp") ~= dayIndex() then
		clearPeriod(DAILY_POOL)
		plr:SetAttribute("Q_DayStamp", dayIndex())
	end
	if plr:GetAttribute("Q_WeekStamp") ~= weekIndex() then
		clearPeriod(WEEKLY_POOL)
		plr:SetAttribute("Q_WeekStamp", weekIndex())
	end
	activeDaily  = pickN(DAILY_POOL,  DAILY_COUNT,  dayIndex())
	activeWeekly = pickN(WEEKLY_POOL, WEEKLY_COUNT, weekIndex())
end
rollPeriods()

local function timeLeft(period)
	local rem = period - (os.time() % period)
	local d = math.floor(rem / DAY)
	local h = math.floor((rem % DAY) / 3600)
	local m = math.floor((rem % 3600) / 60)
	if d > 0 then return string.format("%dd %dh", d, h) end
	if h > 0 then return string.format("%dh %dm", h, m) end
	return string.format("%dm", math.max(m, 1))
end

----------------------------------------------------------------------
-- reporting — the hook the fishing loop calls
----------------------------------------------------------------------
local refreshAll   -- fwd decl
local updateNotif  -- fwd decl

local function bump(id, verb, mode, amount)
	local cur = progOf(id)
	if mode == "max" then
		if amount > cur then plr:SetAttribute("QP_" .. id, amount) end
	else
		plr:SetAttribute("QP_" .. id, cur + amount)
	end
end

local function report(verb, amount)
	amount = tonumber(amount) or 1
	if amount <= 0 then return end

	-- lifetime totals feed the Milestones
	local key = "QT_" .. verb
	if verb == "depth" or verb == "cap" then
		if amount > (plr:GetAttribute(key) or 0) then plr:SetAttribute(key, amount) end
	else
		plr:SetAttribute(key, (plr:GetAttribute(key) or 0) + amount)
	end
	-- a Legendary/rare catch is still a catch of that rarity band
	if verb == "legendary" then
		plr:SetAttribute("QT_rare", (plr:GetAttribute("QT_rare") or 0) + amount)
	end

	for _, pool in ipairs({ activeDaily, activeWeekly }) do
		for _, q in ipairs(pool) do
			if q.verb == verb and not claimedOf(q.id) then
				bump(q.id, verb, q.mode, amount)
			end
			-- Legendary also satisfies a generic "rare or better" objective
			if verb == "legendary" and q.verb == "rare" and not claimedOf(q.id) then
				bump(q.id, "rare", q.mode, amount)
			end
		end
	end
	if refreshAll then refreshAll() end
	if updateNotif then updateNotif() end
end

----------------------------------------------------------------------
-- auto-wiring: the four signals this game already emits
----------------------------------------------------------------------
task.spawn(function()
	-- bait reel: RollerController sets gui.LastRoll on every roll
	local br = pg:WaitForChild("BaitRoller", 20)
	if br then
		br:GetAttributeChangedSignal("LastRoll"):Connect(function() report("roll", 1) end)
	end
end)
task.spawn(function()
	-- fish index: IndexController keeps a Discovered count
	local ix = pg:WaitForChild("IndexMenu", 20)
	if not ix then return end
	-- nil until IndexController's first count: that first count is a restored collection, not N new catches
	local last = ix:GetAttribute("Discovered")
	ix:GetAttributeChangedSignal("Discovered"):Connect(function()
		local now = ix:GetAttribute("Discovered") or 0
		if last ~= nil and now > last then report("discover", now - last) end
		last = now
	end)
end)
do
	local lastRb = plr:GetAttribute("Rebirths") or 0
	plr:GetAttributeChangedSignal("Rebirths"):Connect(function()
		local now = plr:GetAttribute("Rebirths") or 0
		if now > lastRb then report("rebirth", now - lastRb) end
		lastRb = now
	end)
	-- Only a REAL move counts. ZonesController writes CurrentZone for the first time on
	-- join (nil -> 1), which fired a "travel" nobody made - harmless while the only travel
	-- quest needed three of them, not now that a daily needs one. Same nil/no-op guard as
	-- the Rebirths and Discovered watchers above.
	local lastZone = plr:GetAttribute("CurrentZone")
	plr:GetAttributeChangedSignal("CurrentZone"):Connect(function()
		local now = plr:GetAttribute("CurrentZone")
		if lastZone ~= nil and now ~= nil and now ~= lastZone then report("travel", 1) end
		lastZone = now
	end)
end

-- server-side hook for the future fishing loop
local remotes = ReplicatedStorage:FindFirstChild("QuestRemotes")
if not remotes then
	remotes = make("Folder", { Name = "QuestRemotes" }, ReplicatedStorage)
end
local reportRemote = remotes:FindFirstChild("Report")
if not reportRemote then
	reportRemote = make("RemoteEvent", { Name = "Report" }, remotes)
end
reportRemote.OnClientEvent:Connect(function(verb, amount) report(verb, amount) end)

-- client-side hook
local reportBindable = gui:FindFirstChild("Report") or make("BindableEvent", { Name = "Report" }, gui)
reportBindable.Event:Connect(function(verb, amount) report(verb, amount) end)

----------------------------------------------------------------------
-- window: ShopKit's UI.window (see the 2026-10-10 note at the top)
----------------------------------------------------------------------
local WIN_W, WIN_H = 1100, 640
-- the window's pieces and metrics live on ONE table (Luau's 200-locals-per-function cap).
-- REACH: how far the 📜 breaks out above the window; DROP: the window's hard drop; WAVE_D: a crest scallop
local Q = { REACH = 44, DROP = 9, WAVE_D = 26 }

-- a full-screen tap-to-close BUTTON behind the window (a Frame would let the tap through and cast the rod)
local backdrop = make("TextButton", {
	Name = "Backdrop", Text = "", AutoButtonColor = false, Selectable = false, BackgroundColor3 = rgb(2,10,26),
	BackgroundTransparency = 0.45, AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(4, 4), ZIndex = 1,
}, gui)

Q.win = UI.window(gui, "QUESTS", { Name = "Window", w = WIN_W, h = WIN_H, emoji = "📜", headColour = "coral", ZIndex = 5 })
local root = Q.win.root
local uiscale = make("UIScale", { Scale = 1 }, root)
-- the crest's scallops, left to right (relayout re-centres them on a phone's narrower design width)
Q.waves = {}
for _, d in ipairs(Q.win.crest:GetChildren()) do
	if d:IsA("GuiObject") then table.insert(Q.waves, d) end
end
table.sort(Q.waves, function(a, b) return a.Position.X.Offset < b.Position.X.Offset end)

-- Shared with every other pop-up window in the game. On a small screen it makes the window
-- SHORTER rather than smaller, so the WIDTH drives the scale (+30-38% text on a phone) and
-- centres it below the Roblox top bar instead of underneath it. MIN_H is the shortest design
-- height this layout survives. Re-derived 2026-10-10 for the candy layout: outside the list
-- there is only the header, the tab row (its drop ends at y 159) and the list's 16 px foot, so
-- nothing pokes out of the window at any height over ~180 - MIN_H is the shortest window whose
-- list still shows ONE whole card with its drop: 160 + 10 + 120 + 10 + 16 = 316 -> 320.
-- Desktop and iPad keep the authored height.
local MenuFit = require(ReplicatedStorage:WaitForChild("MenuFit"))
local MIN_H = 320
-- PHONE LAYOUT (2026-09-25 mobile pass, redrawn 2026-10-10). Fed the 1100-wide design, MenuFit
-- landed a 667px phone at 0.58. On a compact screen (short side < 500) the window is designed
-- NARROWER instead - W is picked so MenuFit lands near LAY.S (~735 wide on that phone) - with a
-- 62px header (the 📜 moves INSIDE it), shorter tabs and cards (ROW_M / CARD_M .compact).
-- Re-decided on every fit() (open + ViewportSize change), never once at build time.
-- LAY.MIN_H: 140 (list top) + 10 + 110 (one phone card) + 10 + 12 (foot) = 282 -> 284.
local LAY = { compact = false, W = WIN_W, S = 0.85, MIN_H = 284 }
local relayout   -- fwd decl: assigned once every piece of the window exists (bottom of file)
-- What fit() would pick for the screen as it is right now.
local function decide()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.zero
	-- The ScreenGui's own size is the device SAFE area (ScreenInsets), but it can be stale:
	-- measured, switching phones with this menu closed left it reading the previous phone's
	-- width on the next open. A stale LARGER value is rejected here; a stale smaller one is
	-- corrected by the AbsoluteSize watcher further down once the real size lands.
	local gs = gui.AbsoluteSize
	local safeW = (gs.X > 100 and gs.X <= vp.X + 1) and gs.X or vp.X
	local compact = math.min(vp.X, vp.Y) < 500
	local W = compact and math.clamp(math.floor(safeW / LAY.S - 50), 700, WIN_W) or WIN_W
	return vp, compact, W, safeW
end
-- THE 📜 NEEDS ROOM ABOVE THE WINDOW. MenuFit centres the window and leaves ~25 px over it; the emoji
-- reaches 44 design px above the top edge, so at MenuFit's scale it ran off the top of a 751-tall screen and
-- under Roblox's own top-left buttons. So off a phone the scale is held to what keeps it under the top bar -
-- ShopController's layout() rule: a centred window stays centred (body on the middle of the screen), one MenuFit
-- placed in the band under the bar has its whole footprint (emoji .. drop) fitted into that band instead.
local function clearTopBar()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or V2(1280, 720)
	local abs = gui.AbsoluteSize
	local ch = (abs.Y > 100 and abs.Y < vp.Y) and abs.Y or vp.Y
	local gh = abs.Y > 100 and abs.Y or ch
	local bar = GuiService.TopbarInset.Max.Y
	local top = (bar > 0 and bar or 58) + 4
	local s, h = uiscale.Scale, root.Size.Y.Offset
	if s <= 0 or h <= 0 or ch < 100 then return end
	local pos = root.Position
	if pos.Y.Scale > 0 then
		local cy = pos.Y.Scale * gh + pos.Y.Offset
		s = math.min(s, (cy - top) / (h / 2 + Q.REACH), (ch - 8 - cy) / (h / 2 + Q.DROP))
	else
		local avail = ch - 8 - top
		s = math.min(s, avail / (h + Q.REACH + Q.DROP))
		local cy = top + Q.REACH * s + math.max(avail - (h + Q.REACH + Q.DROP) * s, 0) / 2 + h * s / 2
		root.Position = UDim2.new(0.5, 0, 0, math.floor(cy + 0.5))
	end
	uiscale.Scale = math.max(s, 0.3)
end
local function fit()
	local vp, compact, W, safeW = decide()
	if vp.X < 100 or vp.Y < 100 then return end   -- viewport not settled yet (same guard as MenuFit)
	-- a re-fit while the open "pop" is still playing would be undone when that tween lands
	if LAY.tween then LAY.tween:Cancel(); LAY.tween = nil end
	LAY.safeW = safeW
	if compact ~= LAY.compact or W ~= LAY.W then
		LAY.compact, LAY.W = compact, W
		if relayout then relayout() end
	end
	if not compact then
		MenuFit.apply(root, uiscale, WIN_W, WIN_H, 0.4, 1.1, MIN_H)
		clearTopBar()
		return
	end
	MenuFit.apply(root, uiscale, W, WIN_H, 0.4, 1.1, LAY.MIN_H)
	-- MenuFit measures the camera viewport; on a real notched phone the SAFE area this
	-- ScreenGui lives in is narrower, so never let the window run past 97% of it.
	local maxS = safeW * 0.97 / W
	if uiscale.Scale > maxS then
		uiscale.Scale = maxS
		local availH = math.max(160, vp.Y - GuiService:GetGuiInset().Y - 12)
		root.Size = UDim2.fromOffset(W, math.floor(math.clamp(availH / maxS, LAY.MIN_H, WIN_H)))
	end
	-- CENTRED ON THE PHONE SCREEN (2026-10-11, the owner: "make the button uis centered to the phone screen"), not in
	-- the band under the top bar: the 📜 sits inside the 62 px header here (ROW_M.compact), so nothing reaches above
	-- the box - only the drop below it. MenuFit.centre shrinks the scale just enough for the top to clear the bar.
	MenuFit.centre(root, uiscale, 0, Q.DROP)
end
fit()

-- the window catches its own taps (the Shop's ClickGuards): transparent, handler-less buttons over the body and
-- its drop (ZIndex 3: over Shadow / Body, under everything drawn on them) and over the emoji. Silent: SndHooked is
-- set before they are parented, so AudioController leaves them alone. (A plain Active Frame does not stop the
-- Backdrop under it.)
local function clickGuard(parent, size, z)
	local b = make("TextButton", {
		Name = "ClickGuard", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Selectable = false,
		Size = size, ZIndex = z,
	})
	b:SetAttribute("SndHooked", true)
	b.Parent = parent
	return b
end
UI.corner(clickGuard(root, UDim2.new(1, 0, 1, Q.DROP), 3), 24)
if Q.win.icon then clickGuard(Q.win.icon, UDim2.new(1, 0, 1, 5), 20) end

-- the sea behind the cards (the Shop's): light rays and rising bubbles in the window's Ocean layer; only the gaps
-- between cards show them. Driven by the decor loop further down.
do
	local ocean = Q.win.ocean
	Q.rays, Q.bubbles = {}, {}
	for i, x in ipairs({ 0.1, 0.3, 0.5, 0.7, 0.9 }) do
		local ray = make("Frame", {
			Name = "Ray", BackgroundColor3 = UI.WHITE, AnchorPoint = V2(0.5, 0), Position = UDim2.new(x, 0, 0, -40),
			Size = UDim2.new(0, 50 + (i % 2) * 30, 1.3, 0), Rotation = 18, BackgroundTransparency = 0.82, ZIndex = 1,
		}, ocean)
		make("UIGradient", {
			Rotation = 90, Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.6, 0.75), NumberSequenceKeypoint.new(1, 1),
			}),
		}, ray)
		table.insert(Q.rays, { f = ray, phase = i * 1.3 })
	end
	for i = 1, 26 do
		local s = 6 + (i * 7) % 13
		local b = make("Frame", {
			Name = "Bubble", BackgroundColor3 = UI.WHITE, BackgroundTransparency = 0.78, AnchorPoint = V2(0.5, 0.5),
			Size = UDim2.fromOffset(s, s), ZIndex = 2,
		}, ocean)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
		make("UIStroke", { Color = UI.WHITE, Thickness = 1.5, Transparency = 0.35 }, b)
		table.insert(Q.bubbles, { f = b, x = (i * 0.618) % 1, y = (i * 0.377) % 1, speed = 0.05 + (i % 5) * 0.012, wob = (i % 3) + 1, phase = i })
	end
	for _, b in ipairs(Q.bubbles) do b.f.Position = UDim2.new(b.x, 0, b.y, 0) end
end

----------------------------------------------------------------------
-- kit helpers
----------------------------------------------------------------------
-- a ShopKit label's max text size, on the label AND its hard-drop twin (TextScaled + a UITextSizeConstraint)
local function setMax(l, size)
	local twin = l.Parent and l.Parent:FindFirstChild(l.Name .. "Drop")
	for _, t in ipairs({ l, twin or l }) do
		local c = t:FindFirstChildOfClass("UITextSizeConstraint")
		if c then
			c.MaxTextSize = size
			c.MinTextSize = math.min(9, size)
		end
	end
end
-- lay pieces side by side, centred on a face `width` px wide (ShopController's layRow, plus a gap per piece).
-- items: { obj, textSize?, gap = px before it } - a textSize marks a TextScaled label, sized to its text (+ the
-- outline's slack: with none, TextScaled wraps); when the line is too wide the labels narrow together and their
-- text shrinks with them. Hidden pieces take no room.
local function lay(items, width, pad)
	local shown, fixed, want = {}, 0, 0
	for _, it in ipairs(items) do
		if it[1].Visible then
			table.insert(shown, it)
			if it[2] then
				it.w = math.ceil(UI.textWidth(it[1].Text, it[2])) + 6 + math.ceil(it[2] * 0.3)
				want += it.w
			else
				fixed += it[1].Size.X.Offset
			end
		end
	end
	for i = 2, #shown do fixed += shown[i].gap or 6 end
	local k = want > 0 and math.clamp((width - (pad or 16) - fixed) / want, 0.3, 1) or 1
	local total = fixed
	for _, it in ipairs(shown) do
		if it[2] then
			it.w = math.max(math.floor(it.w * k), 1)
			it[1].Size = UDim2.fromOffset(it.w, it[1].Size.Y.Offset)
			total += it.w
		end
	end
	local x = (width - total) / 2
	for i, it in ipairs(shown) do
		if i > 1 then x += it.gap or 6 end
		it[1].AnchorPoint = V2(0, 0.5)
		it[1].Position = UDim2.new(0, math.floor(x + 0.5), 0.5, 0)
		x += it[2] and it.w or it[1].Size.X.Offset
	end
end
-- an emoji as a scaled TextLabel: no outline and no hard drop (an emoji cannot be recoloured, so an INK drop copy
-- would draw a second full-colour emoji under it)
local function emoji(parent, e, size, z, name)
	return make("TextLabel", {
		Name = name or "Emoji", BackgroundTransparency = 1, Text = e, TextScaled = true, FontFace = UI.FONT,
		TextColor3 = UI.WHITE, Size = UDim2.fromOffset(size, size), ZIndex = z or 4,
	}, parent)
end

-- the window furniture's design numbers: desk = the 1100 x 640 window, compact = the phone design
local ROW_M = {
	desk = { hh = 74, titleS = 46, iconS = 124, iconX = -36, iconY = -44, titleX = 112,
		pillY = 13, pillH = 48, pillR = 96, pillGap = 12, coinW = 196, pearlW = 150, pillTS = 28, coinIc = 40, pearlIc = 30,
		tabX = 18, tabY = 122, tabW = 244, tabH = 54, tabGap = 16, tabTS = 28, tabEm = 30,
		timerH = 46, timerTS = 22, timerIc = 30, listY = 160, listB = 16 },
	compact = { hh = 62, titleS = 38, iconS = 56, iconX = 10, iconY = 3, titleX = 76,
		pillY = 10, pillH = 42, pillR = 90, pillGap = 10, coinW = 170, pearlW = 124, pillTS = 24, coinIc = 34, pearlIc = 26,
		tabX = 14, tabY = 106, tabW = 150, tabH = 48, tabGap = 10, tabTS = 24, tabEm = 24,
		timerH = 42, timerTS = 20, timerIc = 26, listY = 140, listB = 12 },
}
local function HM() return LAY.compact and ROW_M.compact or ROW_M.desk end

----------------------------------------------------------------------
-- header: your coins and pearls in static key pills left of the X (the Shop's cash pill)
----------------------------------------------------------------------
Q.coinPill = UI.candyKey(root, "gold", {
	Name = "CoinPill", static = true, Size = UDim2.fromOffset(196, 48), Position = UDim2.fromOffset(WIN_W - 96 - 196, 13), ZIndex = 7,
})
Q.pearlPill = UI.candyKey(root, "sea", {
	Name = "PearlPill", static = true, Size = UDim2.fromOffset(150, 48), Position = UDim2.fromOffset(WIN_W - 96 - 196 - 12 - 150, 13), ZIndex = 7,
})
function Q.setCoins(v)
	local s = UI.cash(v)
	if Q.coinShown == s then return end
	Q.coinShown = s
	local M = HM()
	Q.coinPill.setParts(nil, { { icon = "coins", size = M.coinIc, drop = 0 }, { text = s, size = M.pillTS, o = 4, drop = 2 } }, { gap = 6 })
end
function Q.setPearls(v)
	local s = UI.num(v)
	if Q.pearlShown == s then return end
	Q.pearlShown = s
	local M = HM()
	Q.pearlPill.setParts(nil, { { text = "🦪", size = M.pearlIc, o = 0, drop = 0 }, { text = s, size = M.pillTS, o = 4, drop = 2 } }, { gap = 6 })
end
-- the coin pill follows your wallet live while the menu is up (leaderstats.Money, else the Coins attribute)
do
	local conn
	local function bind()
		if conn then conn:Disconnect(); conn = nil end
		local m = coinSource()
		if m then conn = m.Changed:Connect(function() if gui.Enabled then Q.setCoins(getCoins()) end end) end
		Q.setCoins(getCoins())
	end
	bind()
	plr.ChildAdded:Connect(function(c)
		if c.Name == "leaderstats" then
			task.wait(0.2)
			bind()
		end
	end)
end

----------------------------------------------------------------------
-- toast: the Shop's chip at the window's foot (kind colour: green = claimed, gold = a milestone tier)
----------------------------------------------------------------------
Q.toastChip = UI.chip(root, "navy", {
	Name = "Toast", height = 50, textSize = 22, pad = 26, minWidth = 240, AnchorPoint = V2(0.5, 1), ZIndex = 40,
	Position = UDim2.new(0.5, 0, 1, -18),
})
Q.toastChip.block.root.Visible = false
Q.toastScale = make("UIScale", {}, Q.toastChip.block.root)
local function showToast(text, colour)
	local c = Q.toastChip
	local rootB = c.block.root
	c.set(text, colour or "navy")
	-- never wider than the window (a phone's is ~700 design px)
	local maxW = LAY.W - 80
	local w = rootB.Size.X.Offset
	if w > maxW then
		c.label.TextSize = math.max(12, math.floor(22 * (maxW - 58) / math.max(w - 58, 1)))
		rootB.Size = UDim2.fromOffset(maxW, rootB.Size.Y.Offset)
	else
		c.label.TextSize = 22
	end
	rootB.Visible = true
	UI.punch(Q.toastScale, 0.6, 0.28)
	Q.toastToken = (Q.toastToken or 0) + 1
	local my = Q.toastToken
	task.delay(2.4, function()
		if Q.toastToken == my then rootB.Visible = false end
	end)
end

----------------------------------------------------------------------
-- the lists: one ScrollingFrame per tab, the Shop's scroll style (gold thumb on a see-through INK track)
----------------------------------------------------------------------
local content = make("Frame", {
	Name = "Content", BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 160), Size = UDim2.new(1, -28, 1, -176), ZIndex = 6,
}, root)
Q.track = make("Frame", {
	Name = "ListTrack", BackgroundColor3 = UI.SCROLL.track, BackgroundTransparency = UI.SCROLL.trackTransparency,
	Position = UDim2.new(1, -28, 0, 160), Size = UDim2.new(0, 10, 1, -176), ZIndex = 5,
}, root)
UI.corner(Q.track, 5)
local function makePage(name)
	local p = make("ScrollingFrame", {
		Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false,
		ScrollBarThickness = 10, ScrollBarImageColor3 = UI.SCROLL.thumb, ScrollBarImageTransparency = 0,
		VerticalScrollBarInset = Enum.ScrollBarInset.None, ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 6,
	}, content)
	-- 20 px between cards: room for each one's drop and outline (the Shop's spacing)
	make("UIListLayout", { Padding = UDim.new(0, 20), SortOrder = Enum.SortOrder.LayoutOrder }, p)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 16) }, p)
	return p
end
local pages = { daily = makePage("Daily"), weekly = makePage("Weekly"), miles = makePage("Milestones") }

----------------------------------------------------------------------
-- the tab row: three candy keys, then the reset timer in a navy clock chip running to the right edge
----------------------------------------------------------------------
Q.timer = UI.block(root, "navy", {
	Name = "Timer", AnchorPoint = V2(0, 0.5), Position = UDim2.fromOffset(800, 122), Size = UDim2.fromOffset(282, 46),
	lip = 6, radius = 14, highlight = { top = 3, inset = 12, height = 4 }, ZIndex = 7,
})
Q.timerIc = UI.icon(Q.timer.face, "clock", 30, { Name = "Clock", flat = true, ZIndex = 4 })
UI.iconDrop(Q.timerIc, 3, 0.5)
Q.timerTxt = UI.label(Q.timer.face, "", { Name = "Text", size = 22, outline = 0.14, ZIndex = 5, Size = UDim2.fromOffset(10, 36) })
local function subtitleFor(tab)
	if tab == "miles" then return "Claim every tier you pass" end
	local left = timeLeft(tab == "daily" and DAY or WEEK)
	return (LAY.compact and "Resets in " or "New quests in ") .. left
end
function Q.setTimer(s)
	if Q.timerShown == s then return end
	Q.timerShown = s
	local M = HM()
	Q.timerTxt.Text = s
	Q.timerTxt.Size = UDim2.fromOffset(Q.timerTxt.Size.X.Offset, M.timerH - 10)
	setMax(Q.timerTxt, M.timerTS)
	Q.timerIc.Size = UDim2.fromOffset(M.timerIc, M.timerIc)
	lay({ { Q.timerIc }, { Q.timerTxt, M.timerTS, gap = 8 } }, Q.timer.root.Size.X.Offset, 22)
end

local TAB_DEFS = {
	{ name = "daily",  word = "DAILY",      emoji = "📅" },
	{ name = "weekly", word = "WEEKLY",     emoji = "🗓" },
	{ name = "miles",  word = "MILESTONES", emoji = "🏅" },
}
local tabChips = {}
local currentTab = TAB_DEFS[1].name
local function selectTab(name)
	currentTab = name
	for _, def in ipairs(TAB_DEFS) do
		local on = (def.name == name)
		if def.lit ~= on then
			def.lit = on
			def.key.recolour(on and "gold" or "sea")
		end
		pages[def.name].Visible = on
	end
	Q.setTimer(subtitleFor(name))
end
for i, def in ipairs(TAB_DEFS) do
	def.key = UI.candyKey(root, "sea", {
		Name = def.word:sub(1, 1) .. def.word:sub(2):lower() .. "Tab", Size = UDim2.fromOffset(244, 54), AnchorPoint = V2(0.5, 0.5),
		Position = UDim2.fromOffset(18 + (i - 1) * 260 + 122, 122), ZIndex = 7,
	})
	TouchKit.press(def.key.button, function() selectTab(def.name) end)
	tabChips[def.name] = def.key.button
	-- "claimable" badge pinned ON the key's top-right corner, like the MenuBar's Notif badges. At (1,-10,0,2) it
	-- covered the last letters of a phone's MILESTONES (dot 127..153, text to 143 - measured); on the corner it clears.
	local dot = make("Frame", {
		Name = "Dot", AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(1, -4, 0, -2), Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = UI.WHITE, Visible = false, ZIndex = 8,
	}, def.key.button)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dot)
	UI.stroke(dot, 3)
	UI.vgrad(dot, { UI.KEY.red.hi, UI.KEY.red.base })
	UI.label(dot, "!", { Name = "Mark", size = 18, outline = 0.18, ZIndex = 2 })
end

----------------------------------------------------------------------
-- cards: a UI.candyRow slab per quest (the Shop's row) -
--   [emoji on a glow] [title / what to do / candy bar] [reward chip over the one key]
----------------------------------------------------------------------
local recs = {}
-- desk = the 1100-wide window; compact = the phone design (~0.85: copy 17 px+ real, the key ~40 px + its touch pad)
local CARD_M = {
	desk = { h = 120, iconX = 16, iconS = 80, glow = 116, badge = 34, colX = 114, colGap = 30, rbW = 210, rbR = 16,
		nameY = 6, nameH = 42, nameS = 32, descY = 46, descH = 30, descS = 23, barY = 82, barH = 28, barS = 20,
		rwY = 8, rwH = 40, rwS = 22, rwIc = 26, clY = 58, clH = 50, clS = 30, lead = 44 },
	compact = { h = 110, iconX = 10, iconS = 62, glow = 92, badge = 28, colX = 84, colGap = 26, rbW = 172, rbR = 12,
		nameY = 4, nameH = 36, nameS = 28, descY = 38, descH = 28, descS = 20, barY = 72, barH = 26, barS = 18,
		rwY = 8, rwH = 36, rwS = 20, rwIc = 22, clY = 54, clH = 46, clS = 26, lead = 40 },
}
local function CM() return LAY.compact and CARD_M.compact or CARD_M.desk end
-- the bar's fill: lime on its way, gold once the goal is reached
local FILL = {
	go   = ColorSequence.new(rgb(196, 255, 120), rgb(64, 204, 40)),
	done = ColorSequence.new(rgb(255, 240, 130), rgb(255, 166, 0)),
}

local function styleCard(rec)
	local m = CM()
	local r = rec.row
	local w = LAY.W - 56   -- the list is W-28 wide: 8 px in, then a 10 px gap and the 10 px scroll lane on the right
	r.w, r.h = w, m.h
	r.button.Size = UDim2.fromOffset(w, m.h)
	local rbX = w - m.rbR - m.rbW
	local colW = rbX - m.colGap - m.colX
	r.midW = colW
	r.mid.Position = UDim2.fromOffset(m.colX, 0)
	r.mid.Size = UDim2.fromOffset(colW, m.h)
	local cx, cy = m.iconX + m.iconS / 2, m.h / 2
	rec.glow.Position = UDim2.fromOffset(cx, cy)
	rec.glow.Size = UDim2.fromOffset(m.glow, m.glow)
	rec.icon.Position = UDim2.fromOffset(cx, cy)
	rec.icon.Size = UDim2.fromOffset(m.iconS, m.iconS)
	if rec.tier then
		local bx, by = m.iconX + m.iconS - 4, cy - m.iconS / 2 + 6
		rec.tier.Position = UDim2.fromOffset(bx, by)
		rec.tier.Size = UDim2.fromOffset(m.badge, m.badge)
		rec.tierDrop.Position = UDim2.fromOffset(bx, by + 3)
		rec.tierDrop.Size = UDim2.fromOffset(m.badge, m.badge)
		setMax(rec.tierTxt, math.floor(m.badge * 0.62))
	end
	rec.nameLbl.Position = UDim2.fromOffset(0, m.nameY)
	rec.nameLbl.Size = UDim2.new(1, 0, 0, m.nameH)
	setMax(rec.nameLbl, m.nameS)
	rec.descLbl.Position = UDim2.fromOffset(0, m.descY)
	rec.descLbl.Size = UDim2.new(1, 0, 0, m.descH)
	setMax(rec.descLbl, m.descS)
	rec.bar.Position = UDim2.fromOffset(0, m.barY)
	rec.bar.Size = UDim2.new(1, 0, 0, m.barH)
	rec.barCorner.CornerRadius = UDim.new(0, math.floor(m.barH / 2))
	rec.fillCorner.CornerRadius = UDim.new(0, math.floor((m.barH - 6) / 2))
	setMax(rec.barTxt, m.barS)
	-- a sliver of progress still draws as a round blob, never as a squashed one
	rec.minFrac = (m.barH - 6) / math.max(colW - 6, 1)
	rec.reward.root.Position = UDim2.fromOffset(rbX, m.rwY)
	rec.reward.root.Size = UDim2.fromOffset(m.rbW, m.rwH)
	rec.claim.button.Position = UDim2.fromOffset(rbX, m.clY)
	rec.claim.button.Size = UDim2.fromOffset(m.rbW, m.clH)
	-- everything laid out from these sizes is laid out again on the next refresh
	rec.keyState, rec.rwSig, rec.shownFrac = nil, nil, nil
end

local function buildCard(page, order, id, icon, candy, name)
	local m = CM()
	local r = UI.candyRow(page, {
		kind = "card", Name = id, colour = candy, key = false, LayoutOrder = order, w = LAY.W - 56, h = m.h,
		mid = { x = m.colX, w = 400 },
	})
	local rec = { row = r }
	-- the emoji on the soft white glow (the Shop's row icon spot)
	rec.glow = make("ImageLabel", {
		Name = "Glow", BackgroundTransparency = 1, Image = UI.ICONS.glow or "", ScaleType = Enum.ScaleType.Stretch,
		AnchorPoint = V2(0.5, 0.5), ImageTransparency = 0.15, ZIndex = 4,
	}, r.button)
	rec.icon = emoji(r.button, icon, m.iconS, 6, "Icon")
	rec.icon.AnchorPoint = V2(0.5, 0.5)
	rec.icon.Rotation = -6
	-- the text column: the quest's name, what to do, and the candy bar
	rec.nameLbl = UI.label(r.mid, name, { Name = "Title", size = m.nameS, drop = 3, outline = 0.14, ZIndex = 3 })
	rec.descLbl = UI.label(r.mid, "", { Name = "Desc", size = m.descS, drop = 2, outline = 0.13, ZIndex = 3 })
	rec.bar = make("Frame", { Name = "Bar", BackgroundColor3 = UI.INK, BackgroundTransparency = 0.5, ZIndex = 2 }, r.mid)
	rec.barCorner = UI.corner(rec.bar, 14)
	UI.stroke(rec.bar, 3)
	rec.track = make("Frame", {
		Name = "Inner", BackgroundTransparency = 1, Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), ZIndex = 3,
	}, rec.bar)
	rec.fill = make("Frame", { Name = "Fill", BackgroundColor3 = UI.WHITE, Size = UDim2.new(0, 0, 1, 0), Visible = false, ZIndex = 3 }, rec.track)
	rec.fillCorner = UI.corner(rec.fill, 11)
	rec.fillGrad = make("UIGradient", { Rotation = 90, Color = FILL.go }, rec.fill)
	UI.gloss(rec.fill, { frac = 0.5, alpha = 0.5, inset = 2, radius = 8, ZIndex = 4 })
	rec.barTxt = UI.label(rec.bar, "", {
		Name = "Count", size = m.barS, outline = 0.16, ZIndex = 6, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0),
	})
	-- the right-hand block: what it pays (a gold chip), over the one key
	rec.reward = UI.block(r.button, "gold", {
		Name = "Reward", lip = 6, radius = 14, highlight = { top = 3, inset = 12, height = 4 }, ZIndex = 10,
	})
	local face = rec.reward.face
	rec.rwCoinIc = emoji(face, "💰", m.rwIc, 3, "CoinIcon")
	rec.rwCoin = UI.label(face, "", { Name = "Coins", size = m.rwS, outline = 0.15, ZIndex = 4, Size = UDim2.fromOffset(10, 30) })
	rec.rwPearlIc = emoji(face, "🦪", m.rwIc, 3, "PearlIcon")
	rec.rwPearl = UI.label(face, "", { Name = "Pearls", size = m.rwS, outline = 0.15, ZIndex = 4, Size = UDim2.fromOffset(10, 30) })
	rec.claim = UI.candyKey(r.button, "grey", { Name = "Claim", ZIndex = 10 })
	styleCard(rec)
	return rec
end

-- the key, in the STATE's colour: grey IN PROGRESS, green CLAIM!, gold CLAIMED / COMPLETE (+ the card's gold ring)
local function setKey(rec, state)
	if rec.keyState == state then return end
	rec.keyState = state
	local m, k = CM(), rec.claim
	if state == "claim" then
		k.recolour("green")
		k.setParts(nil, { { text = "CLAIM!", size = m.clS } })
	elseif state == "claimed" or state == "complete" then
		k.recolour("gold")
		k.setParts("check", { { text = state == "claimed" and "CLAIMED" or "COMPLETE", size = m.clS - 4 } }, { leadSize = m.lead })
	else
		k.recolour("grey")
		k.setParts(nil, { { text = "IN PROGRESS", size = m.clS - 6 } })
	end
	rec.row.setOwned(state == "claimed" or state == "complete")
end
-- the reward chip: 💰 coins (+ 🦪 pearls), or a grey MAXED once a milestone has no tier left
local function setReward(rec, coins, pearls, maxed)
	local sig = maxed and "max" or (tostring(coins or 0) .. "|" .. tostring(pearls or 0))
	if rec.rwSig == sig then return end
	rec.rwSig = sig
	local m = CM()
	local hasP = (not maxed) and (pearls or 0) > 0
	UI.recolour(rec.reward, maxed and "grey" or "gold")
	rec.rwCoinIc.Visible = not maxed
	rec.rwPearlIc.Visible, rec.rwPearl.Visible = hasP, hasP
	rec.rwCoin.Text = maxed and "MAXED" or UI.cash(coins or 0):sub(2)
	rec.rwPearl.Text = tostring(pearls or 0)
	for _, ic in ipairs({ rec.rwCoinIc, rec.rwPearlIc }) do ic.Size = UDim2.fromOffset(m.rwIc, m.rwIc) end
	for _, l in ipairs({ rec.rwCoin, rec.rwPearl }) do
		l.Size = UDim2.fromOffset(l.Size.X.Offset, m.rwH - 8)
		setMax(l, m.rwS)
	end
	lay({ { rec.rwCoinIc }, { rec.rwCoin, m.rwS, gap = 4 }, { rec.rwPearlIc, gap = 12 }, { rec.rwPearl, m.rwS, gap = 4 } }, m.rbW, 16)
end
-- the candy bar: fill fraction (a tween while the menu is up), lime -> gold when reached, the count on top
local function setBar(rec, frac, done, text)
	rec.barTxt.Text = text
	local col = done and "done" or "go"
	if rec.fillCol ~= col then
		rec.fillCol = col
		rec.fillGrad.Color = FILL[col]
	end
	local show = frac > 0 and math.min(math.max(frac, rec.minFrac or 0), 1) or 0
	if rec.shownFrac == show then return end
	rec.shownFrac = show
	rec.fill.Visible = show > 0
	local goal = UDim2.new(show, 0, 1, 0)
	if gui.Enabled then
		TweenService:Create(rec.fill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = goal }):Play()
	else
		rec.fill.Size = goal
	end
end
local function rewardPlain(coins, pearls)
	local s = "+" .. UI.cash(coins or 0)
	if (pearls or 0) > 0 then s ..= "  +" .. pearls .. (pearls == 1 and " pearl" or " pearls") end
	return s
end

----------------------------------------------------------------------
-- quest cards (daily / weekly)
----------------------------------------------------------------------
local function claimQuest(q)
	if claimedOf(q.id) then return end
	if progOf(q.id) < q.goal then return end
	plr:SetAttribute("QC_" .. q.id, true)
	addCoins(q.coins or 0)
	if (q.pearls or 0) > 0 then addPearls(q.pearls) end
	showToast(q.name .. " claimed!  " .. rewardPlain(q.coins, q.pearls), "green")
	refreshAll(); updateNotif()
end

local function addQuestCards(pool, page)
	for i, q in ipairs(pool) do
		local rec = buildCard(page, i, q.id, q.icon, VERB_CANDY[q.verb] or "blue", q.name)
		rec.quest = q
		recs[#recs+1] = rec
		TouchKit.press(rec.claim.button, function()
			local was = claimedOf(q.id)
			claimQuest(q)
			if not was and claimedOf(q.id) then UI.punch(rec.row.scale, 1.04, 0.25) end
		end)
	end
end

local function refreshQuestRec(rec)
	local q = rec.quest
	local prog = progOf(q.id)
	local done = prog >= q.goal
	local claimed = claimedOf(q.id)
	local fmtN = (q.fmt == "money") and money or commas

	rec.descLbl.Text = string.format(q.desc, (q.fmt == "money") and money(q.goal) or q.goal)
	setReward(rec, q.coins, q.pearls)
	setBar(rec, math.clamp(prog / q.goal, 0, 1), done, fmtN(math.min(prog, q.goal)) .. "  /  " .. fmtN(q.goal))
	setKey(rec, claimed and "claimed" or (done and "claim" or "progress"))
end

----------------------------------------------------------------------
-- milestone cards (tiered, permanent)
----------------------------------------------------------------------
local function claimMilestone(m)
	local t = tierOf(m.id)
	if t >= #m.tiers then return end
	if m.stat() < m.tiers[t+1] then return end
	plr:SetAttribute("MT_" .. m.id, t + 1)
	addCoins(m.coins[t+1] or 0)
	if (m.pearls[t+1] or 0) > 0 then addPearls(m.pearls[t+1]) end
	showToast(m.name .. " tier " .. (t+1) .. "!  " .. rewardPlain(m.coins[t+1], m.pearls[t+1]), "gold")
	refreshAll(); updateNotif()
end

local function addMilestoneCards(page)
	for i, m in ipairs(MILESTONES) do
		local rec = buildCard(page, i, m.id, m.icon, MILE_CANDY[m.id] or "blue", m.name)
		rec.mile = m
		-- the tier number on a gold disc pinned to the emoji's corner (green once every tier is claimed)
		rec.tierDrop = make("Frame", {
			Name = "TierDrop", BackgroundColor3 = UI.INK, BackgroundTransparency = 0.5, AnchorPoint = V2(0.5, 0.5), ZIndex = 7,
		}, rec.row.button)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, rec.tierDrop)
		UI.stroke(rec.tierDrop, 3).Transparency = 0.5
		rec.tier = make("Frame", {
			Name = "Tier", BackgroundColor3 = UI.WHITE, AnchorPoint = V2(0.5, 0.5), Rotation = 8, ZIndex = 8,
		}, rec.row.button)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, rec.tier)
		UI.stroke(rec.tier, 3)
		UI.vgrad(rec.tier, { rgb(255, 238, 120), rgb(255, 176, 20) })
		rec.tierTxt = UI.label(rec.tier, "0", { Name = "N", size = 21, outline = 0.16, ZIndex = 2 })
		styleCard(rec)
		recs[#recs+1] = rec
		TouchKit.press(rec.claim.button, function()
			local was = tierOf(m.id)
			claimMilestone(m)
			if tierOf(m.id) > was then UI.punch(rec.row.scale, 1.04, 0.25) end
		end)
	end
end

-- "next: 1 rebirths" reads wrong, so a milestone may carry a singular form
local function unitFor(m, v) return (v == 1 and m.unitOne) or m.unit end

local function refreshMileRec(rec)
	local m = rec.mile
	local t = tierOf(m.id)
	local val = m.stat()
	local maxed = t >= #m.tiers
	local fmtN = (m.fmt == "money") and money or commas

	rec.tierTxt.Text = tostring(t)
	if rec.tierMaxed ~= maxed then
		rec.tierMaxed = maxed
		UI.vgrad(rec.tier, maxed and { rgb(150, 250, 100), rgb(40, 190, 40) } or { rgb(255, 238, 120), rgb(255, 176, 20) })
	end

	if maxed then
		rec.descLbl.Text = "All tiers complete  ·  " .. fmtN(val) .. " " .. unitFor(m, val)
		setReward(rec, nil, nil, true)
		setBar(rec, 1, true, "MAX")
		setKey(rec, "complete")
		return
	end

	local goal = m.tiers[t+1]
	local done = val >= goal
	rec.descLbl.Text = string.format("Tier %d of %d  ·  next: %s %s", t, #m.tiers, fmtN(goal), unitFor(m, goal))
	setReward(rec, m.coins[t+1], m.pearls[t+1])
	setBar(rec, math.clamp(val / goal, 0, 1), done, fmtN(math.min(val, goal)) .. "  /  " .. fmtN(goal))
	setKey(rec, done and "claim" or "progress")
end

-- ⚠️ CARDS MUST BE REBUILT WHEN THE LINE-UP ROLLS OVER.
-- rollPeriods() re-picks activeDaily / activeWeekly at runtime (the 20s ticker and the
-- Enabled handler both call it), but the cards used to be built exactly once at load and
-- `recs` is append-only - so a session that crossed 00:00 UTC kept showing YESTERDAY's
-- line-up forever. report() bumps TODAY's ids, which then have no card, so the visible
-- cards sit at 0/goal reading "IN PROGRESS"; meanwhile claimableIn() iterates the LIVE
-- active list, so the tab dot and the MainMenu "!" badge light up with no CLAIM! button
-- anywhere on the page - an alert the player cannot clear without rejoining. ResetOnSpawn
-- is false on this ScreenGui, so dying does not heal it.
-- Keyed on the actual id list, not on the stamp: a re-pick that happens to draw the same
-- quests must NOT throw away cards the player is looking at.
local function periodKey()
	local ids = {}
	for _, q in ipairs(activeDaily)  do ids[#ids+1] = q.id end
	ids[#ids+1] = "|"
	for _, q in ipairs(activeWeekly) do ids[#ids+1] = q.id end
	return table.concat(ids, ",")
end
local builtKey = nil
local function rebuildPeriodCards()
	local key = periodKey()
	if key == builtKey then return false end
	builtKey = key
	for _, page in ipairs({ pages.daily, pages.weekly }) do
		-- cards only: a UIListLayout / UIPadding is not a GuiObject, so the layout survives
		for _, c in ipairs(page:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
	end
	-- drop the stale quest recs and keep the milestone ones - MILESTONES is a constant
	-- table whose cards are still valid
	for i = #recs, 1, -1 do if recs[i].quest then table.remove(recs, i) end end
	addQuestCards(activeDaily,  pages.daily)
	addQuestCards(activeWeekly, pages.weekly)
	-- both are forward-declared and still nil during the FIRST build; same guard report() uses
	if refreshAll  then refreshAll()  end
	if updateNotif then updateNotif() end
	return true
end
rebuildPeriodCards()
addMilestoneCards(pages.miles)

----------------------------------------------------------------------
-- claimable count -> tab dots + the MainMenu Quests "!" badge
----------------------------------------------------------------------
local function claimableIn(tab)
	local n = 0
	if tab == "daily" or tab == "weekly" then
		for _, q in ipairs(tab == "daily" and activeDaily or activeWeekly) do
			if not claimedOf(q.id) and progOf(q.id) >= q.goal then n += 1 end
		end
	else
		for _, m in ipairs(MILESTONES) do
			local t = tierOf(m.id)
			if t < #m.tiers and m.stat() >= m.tiers[t+1] then n += 1 end
		end
	end
	return n
end

-- The Quests button ships without a Notif (Upgrades/Zones/Rebirth have one), so
-- clone theirs rather than re-styling it by hand.
local function ensureNotif()
	local mm = pg:FindFirstChild("MainMenu")
	local list = mm and mm:FindFirstChild("MenuBar") and mm.MenuBar:FindFirstChild("List")
	local btn = list and list:FindFirstChild("Quests")
	if not btn then return nil end
	local n = btn:FindFirstChild("Notif")
	if not n then
		local donor = list:FindFirstChild("Upgrades") and list.Upgrades:FindFirstChild("Notif")
		if not donor then return nil end
		n = donor:Clone()
		n.Parent = btn
	end
	return n
end

function updateNotif()
	local total = claimableIn("daily") + claimableIn("weekly") + claimableIn("miles")
	for _, def in ipairs(TAB_DEFS) do
		local dot = tabChips[def.name]:FindFirstChild("Dot")
		if dot then dot.Visible = claimableIn(def.name) > 0 end
	end
	local n = ensureNotif()
	if n then n.Visible = total > 0 end
	gui:SetAttribute("Claimable", total)
end

----------------------------------------------------------------------
-- refresh
----------------------------------------------------------------------
function refreshAll()
	-- Nothing here is seen while the menu is shut, and report() calls this for every fish; opening the menu runs it
	-- (the Enabled handler below). The tab dots and the MainMenu badge are updateNotif's and always run.
	if not gui.Enabled then return end
	Q.setCoins(getCoins())
	Q.setPearls(getPearls())
	Q.setTimer(subtitleFor(currentTab))
	for _, rec in ipairs(recs) do
		if rec.quest then refreshQuestRec(rec) else refreshMileRec(rec) end
	end
end

plr:GetAttributeChangedSignal("Pearls"):Connect(function() refreshAll() end)
plr:GetAttributeChangedSignal("Coins"):Connect(function() refreshAll() end)

----------------------------------------------------------------------
-- decor loop (obeys Settings > Menu Animations, like every other menu)
----------------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
	if not gui.Enabled then return end
	if plr:GetAttribute("Set_MenuFX") == false then return end
	local t = os.clock()
	for _, b in ipairs(Q.bubbles) do
		b.y -= b.speed * dt
		if b.y < -0.05 then
			b.y = 1.05
			b.x = (b.x + 0.37) % 1
		end
		b.f.Position = UDim2.new(b.x, math.sin(t * b.wob + b.phase) * 6, b.y, 0)
	end
	for _, r in ipairs(Q.rays) do
		r.f.BackgroundTransparency = 0.8 + 0.08 * math.sin(t * 0.7 + r.phase)
	end
end)

-- keep the reset countdown honest while the menu sits open
task.spawn(function()
	while true do
		task.wait(20)
		if gui.Enabled then
			rollPeriods()
			rebuildPeriodCards()   -- midnight can land while the menu is sitting open
			Q.setTimer(subtitleFor(currentTab))
		end
	end
end)

----------------------------------------------------------------------
-- open / close
----------------------------------------------------------------------
local function close() gui.Enabled = false end
TouchKit.press(Q.win.close.button, close)
TouchKit.press(backdrop, close)

local prevBackpack = true
local function setInventoryHidden(hidden)
	pcall(function()
		if hidden then
			prevBackpack = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		else
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, prevBackpack)
		end
	end)
end
gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if gui.Enabled then
		fit(); rollPeriods(); rebuildPeriodCards(); refreshAll(); selectTab(currentTab); setInventoryHidden(true)
		-- every list opens at its top (CanvasPosition is in screen px, so a list left scrolled would slide during the pop)
		for _, p in pairs(pages) do p.CanvasPosition = Vector2.zero end
		Q.toastChip.block.root.Visible = false
		-- the Shop's open: the scrim fades in, the window pops from 0.6
		backdrop.BackgroundTransparency = 1
		TweenService:Create(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 0.45 }):Play()
		local target = uiscale.Scale
		uiscale.Scale = target * 0.6
		LAY.tween = TweenService:Create(uiscale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target })
		LAY.tween:Play()
	else
		setInventoryHidden(false)
	end
end)
if gui.Enabled then setInventoryHidden(true) end

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function() if gui.Enabled then fit() end end)
end
-- ...and again when the gui's own (safe-area) size catches up with a viewport change
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if not gui.Enabled then return end
	local _, compact, W, safeW = decide()
	if compact ~= LAY.compact or W ~= LAY.W or safeW ~= LAY.safeW then fit() end
end)
-- ...and when Roblox's top bar changes height (clearTopBar measures it)
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function() if gui.Enabled then fit() end end)

----------------------------------------------------------------------
-- dev hook
----------------------------------------------------------------------
local devHook = gui:FindFirstChild("DevQuest") or make("BindableEvent", { Name = "DevQuest" }, gui)
devHook.Event:Connect(function(a, b)
	if a == "__OPEN__" then
		gui.Enabled = true
	elseif a == "__RESET__" then
		for _, pool in ipairs({ DAILY_POOL, WEEKLY_POOL }) do clearPeriod(pool) end
		for _, m in ipairs(MILESTONES) do plr:SetAttribute("MT_" .. m.id, 0) end
		for _, v in ipairs({ "cast","catch","earn","depth","rare","legendary","cap","roll","discover","rebirth","travel" }) do
			plr:SetAttribute("QT_" .. v, 0)
		end
		refreshAll(); updateNotif()
	elseif a == "__ROLLOVER__" then
		-- Jump the line-up forward N periods WITHOUT waiting for midnight. This exists
		-- because the card-rebuild bug above could only ever be reproduced by a session
		-- crossing 00:00 UTC, which is why it survived so long. rollPeriods() re-derives
		-- the seed from os.time(), so the next tick or menu open reverts this by itself -
		-- which also exercises the rebuild in the other direction.
		local n = tonumber(b) or 1
		clearPeriod(DAILY_POOL); clearPeriod(WEEKLY_POOL)
		activeDaily  = pickN(DAILY_POOL,  DAILY_COUNT,  dayIndex()  + n)
		activeWeekly = pickN(WEEKLY_POOL, WEEKLY_COUNT, weekIndex() + n)
		rebuildPeriodCards()
	elseif a == "__COMPLETE__" then
		-- fill every active daily/weekly to its goal
		for _, pool in ipairs({ activeDaily, activeWeekly }) do
			for _, q in ipairs(pool) do plr:SetAttribute("QP_" .. q.id, q.goal) end
		end
		refreshAll(); updateNotif()
	elseif typeof(a) == "string" then
		report(a, b or 1)
	end
end)

----------------------------------------------------------------------
-- phone <-> desktop relayout. fit() calls this whenever the mode or the design width
-- changes; the desk branch restores the authored numbers exactly.
----------------------------------------------------------------------
relayout = function()
	local c, W = LAY.compact, LAY.W
	local M = c and ROW_M.compact or ROW_M.desk
	local win = Q.win
	-- the header (a phone's is shorter) and what hangs off its bottom edge
	win.header.Size = UDim2.new(1, 0, 0, M.hh)
	win.ocean.Position = UDim2.fromOffset(0, M.hh)
	win.ocean.Size = UDim2.new(1, 0, 1, -M.hh)
	win.crest.Position = UDim2.fromOffset(0, M.hh)
	-- the wave crest was built for the full 1100 width: re-centre it on this design width
	local n = math.ceil((W - 10) / Q.WAVE_D)
	local x0 = (W - n * Q.WAVE_D) / 2
	for i, d in ipairs(Q.waves) do
		d.Visible = i <= n
		d.Position = UDim2.fromOffset(math.floor(x0 + (i - 1) * Q.WAVE_D + 0.5), -1)
	end
	-- the title runs up to the pills; the 📜 breaks out of the corner, or sits inside a phone's header
	local coinX = W - M.pillR - M.coinW
	local pearlX = coinX - M.pillGap - M.pearlW
	win.title.Position = UDim2.fromOffset(M.titleX, 0)
	win.title.Size = UDim2.fromOffset(pearlX - 12 - M.titleX, M.hh)
	setMax(win.title, M.titleS)
	if win.icon then
		win.icon.Size = UDim2.fromOffset(M.iconS, M.iconS)
		win.icon.Position = UDim2.fromOffset(M.iconX, M.iconY)
	end
	Q.coinPill.button.Position = UDim2.fromOffset(coinX, M.pillY)
	Q.coinPill.button.Size = UDim2.fromOffset(M.coinW, M.pillH)
	Q.pearlPill.button.Position = UDim2.fromOffset(pearlX, M.pillY)
	Q.pearlPill.button.Size = UDim2.fromOffset(M.pearlW, M.pillH)
	Q.coinShown, Q.pearlShown = nil, nil
	Q.setCoins(getCoins())
	Q.setPearls(getPearls())
	-- the tab row: three keys, then the timer chip to the right edge
	for i, def in ipairs(TAB_DEFS) do
		def.key.button.Size = UDim2.fromOffset(M.tabW, M.tabH)
		def.key.button.Position = UDim2.fromOffset(M.tabX + (i - 1) * (M.tabW + M.tabGap) + M.tabW / 2, M.tabY)
		def.key.setParts(nil, { { text = def.emoji, size = M.tabEm, o = 0, drop = 0 }, { text = def.word, size = M.tabTS, gap = 8 } })
	end
	local tx = M.tabX + 3 * M.tabW + 2 * M.tabGap + M.tabX
	Q.timer.root.Position = UDim2.fromOffset(tx, M.tabY)
	Q.timer.root.Size = UDim2.fromOffset(W - M.tabX - tx, M.timerH)
	Q.timerShown = nil
	Q.setTimer(subtitleFor(currentTab))
	-- the list (and its scroll lane) from under the tab row to the window's foot
	content.Position = UDim2.fromOffset(10, M.listY)
	content.Size = UDim2.new(1, -28, 1, -(M.listY + M.listB))
	Q.track.Position = UDim2.new(1, -28, 0, M.listY)
	Q.track.Size = UDim2.new(0, 10, 1, -(M.listY + M.listB))
	for _, rec in ipairs(recs) do styleCard(rec) end
	if refreshAll then refreshAll() end
end
relayout()

----------------------------------------------------------------------
-- first paint
----------------------------------------------------------------------
selectTab(TAB_DEFS[1].name)
refreshAll()
task.defer(updateNotif)

print(string.format("[Quests] built — %d daily (of %d), %d weekly (of %d), %d milestones · day #%d (sea candy)",
	#activeDaily, #DAILY_POOL, #activeWeekly, #WEEKLY_POOL, #MILESTONES, dayIndex()))
