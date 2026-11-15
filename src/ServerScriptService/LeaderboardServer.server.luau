--[==[
	LeaderboardServer - GLOBAL, ALL-TIME leaderboards (2026-10-11, the owner: "do the all-time totals").

	Servers are 1 player now, so a per-server board only ever showed you. Each of the four boards is an
	OrderedDataStore keyed by UserId whose value is that player's running total over EVERY visit:
	    robux  Robux spent      SERVER-AUTHORITATIVE: product receipts (ProductServer fires
	                            ServerStorage.LeaderboardRobux after a grant) + this game's own game passes
	    rolls  bait rolls       }
	    fish   fish caught      }  client-reported session totals (QT_roll / QT_catch / QT_earn), turned into
	    coins  coins earned     }  DELTAS here - only the increase since the last report is ever added

	WRITES ONLY EVER ADD. Each player's unsaved delta goes in through UpdateAsync(old + d) about once a minute and on
	leave / shutdown, so a player rejoining while the old server is still flushing can't clobber anything. A failed save
	keeps its delta for the next try.
	⚠️ NOT IncrementAsync: its delta is a 32-bit int, so a coins delta above 2,147,483,647 arrives as -2^31 and
	silently LOWERS the stored total (late-game hauls are billions). UpdateAsync's value is the store's 64-bit integer.
	The stored total UpdateAsync returns is also the truth for the display: base = stored - saved this visit, which
	repairs a base whose join read failed and absorbs anything an older server added after that read.

	READS: all four top-50s load at startup, then one board every REFRESH/4 s (GetSortedAsync), names resolved in one
	batch through UserService, pushed to every client on LeaderboardRemotes.Boards. Each player's own live total
	(base + saved + unsaved) is published on them as LB_<key>, so YOUR row never waits for a save + refresh.

	TRUST: rolls / fish / coins come from the client like the rest of this economy, so each report may add at most
	RATE[k] per second since the last accepted report (10 s max) - an honest player never reaches it, a forged total
	trickles in at the honest rate. Robux is never taken from the client: receipts come from ProcessReceipt, and a
	game pass counts only if it is one of THIS game's passes (ShopProducts.PASS_IDS, priced from PASS_ROBUX), the
	player owns it, and it has never been counted for them before (LB_PassCounted_v1 - a pass is bought once ever).

	BUDGET at 1 player / server: GetSortedAsync 4 at start then ~3.2/min (limit 7), UpdateAsync <= 4/min,
	GetAsync 4 per join. Store names end in _v1 - renumbering a board means a new name, never a reuse.

	STUDIO: DataStores are off without API access, so a Studio session falls back to an in-memory stand-in with the
	same calls (print says which). Dev hook: script.DevLeaderboard:Fire("seed") puts a few sample anglers into the
	STUDIO stand-in only; :Fire("refresh") refreshes every board now; :Fire("flush") saves now.
]==]

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerStorage      = game:GetService("ServerStorage")
local DataStoreService   = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local UserService        = game:GetService("UserService")
local RunService         = game:GetService("RunService")

local ShopProducts = require(ReplicatedStorage:WaitForChild("ShopProducts"))

local KEYS     = { "robux", "rolls", "fish", "coins" }
-- per second, from the real economy (a bait roll is a 3 s spin; a full haul is ~17 fish; a perfect late-game cast
-- pays ~2e10/s) with headroom. Robux is server-only and never in this table.
local RATE     = { rolls = 1, fish = 8, coins = 2e10 }
local BURST    = 10       -- seconds of RATE one report may cash in after a quiet spell
local MAX      = 9e15     -- OrderedDataStore values are 64-bit; stay well inside
local TOP_N    = 50
local REFRESH  = 75       -- seconds to cycle all four boards after the startup load
local SAVE_EVERY = 60
local MIN_GAP  = 1        -- seconds between accepted reports from one player (clients send every 3 s at most)
local ASK_GAP  = 5        -- seconds between "send me the boards" requests from one player

------------------------------------------------------------------------------------------------ remotes
local remotes = ReplicatedStorage:FindFirstChild("LeaderboardRemotes") or Instance.new("Folder")
remotes.Name = "LeaderboardRemotes"
remotes.Parent = ReplicatedStorage
local function remote(name)
	local r = remotes:FindFirstChild(name) or Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local report = remote("Report")     -- client -> server: { rolls = n, fish = n, coins = n } session totals
local boards = remote("Boards")     -- server -> client: (key, { {u, n, v}, ... });  client -> server: request all

local robuxIn = ServerStorage:FindFirstChild("LeaderboardRobux") or Instance.new("BindableEvent")
robuxIn.Name = "LeaderboardRobux"
robuxIn.Parent = ServerStorage

------------------------------------------------------------------------------------------------ stores
local function mockStore()
	local data = {}
	local m = {}
	function m:GetAsync(k) return data[k] end
	function m:UpdateAsync(k, fn)
		local v = fn(data[k])
		if v ~= nil then data[k] = v end
		return data[k]
	end
	function m:GetSortedAsync(asc, size)
		local rows = {}
		for k, v in pairs(data) do rows[#rows + 1] = { key = k, value = v } end
		table.sort(rows, function(a, b) if asc then return a.value < b.value end return a.value > b.value end)
		local page = {}
		for i = 1, math.min(size, #rows) do page[i] = rows[i] end
		return { GetCurrentPage = function() return page end }
	end
	return m
end

local stores, mocked = {}, false
for _, k in ipairs(KEYS) do
	local ok, st = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, "LB_AllTime_v1_" .. k)
	stores[k] = ok and st or nil
end
local okPass, passStore = pcall(DataStoreService.GetDataStore, DataStoreService, "LB_PassCounted_v1")
passStore = okPass and passStore or nil
-- Studio without API access: every call errors. Probe once and swap in the stand-in so the boards still work.
-- (IsStudio-gated: a live server whose probe fails during an outage keeps the real stores and just retries.)
if RunService:IsStudio() then
	local ok = stores.rolls and pcall(function() return stores.rolls:GetAsync("probe") end)
	if not ok then
		mocked = true
		for _, k in ipairs(KEYS) do stores[k] = mockStore() end
		passStore = mockStore()
	end
end

local function retry(fn, tries)
	tries = tries or 3
	for i = 1, tries do
		local ok, res = pcall(fn)
		if ok then return true, res end
		if i < tries then task.wait(1.5 * i) end
	end
	return false
end

-- add d to the stored total; returns ok, the new stored total
local function addStored(k, userId, d)
	return retry(function()
		return stores[k]:UpdateAsync(tostring(userId), function(old)
			return math.min(math.floor((tonumber(old) or 0) + d), MAX)
		end)
	end, 3)
end

------------------------------------------------------------------------------------------------ per-player totals
-- state[plr] = { base = {k = stored total before this visit's saves, nil = not known yet}, saved = {k}, pending = {k},
--                last = {k = last reported session value}, t = last accepted report clock, seen = {receipt = true},
--                asked = last boards request clock, busy = a flush is running }
local state = {}

local function publish(plr)
	local st = state[plr]
	if not st then return end
	for _, k in ipairs(KEYS) do
		local total = (st.base[k] or 0) + st.saved[k] + st.pending[k]
		plr:SetAttribute("LB_" .. k, math.min(math.floor(total), MAX))
	end
end

local function add(plr, k, amount)
	local st = state[plr]
	amount = math.floor(tonumber(amount) or 0)
	if not st or amount <= 0 or amount ~= amount then return end
	st.pending[k] = math.min(st.pending[k] + amount, MAX)
	publish(plr)
end

local function readBase(plr, st, k)
	local ok, v = retry(function() return stores[k] and stores[k]:GetAsync(tostring(plr.UserId)) end, 3)
	if ok and state[plr] == st then
		-- the stored value already includes whatever this visit saved before the read landed
		st.base[k] = (tonumber(v) or 0) - st.saved[k]
		publish(plr)
	end
	-- a failed read leaves base nil (unknown, shown as 0) - the next flush learns it instead of assuming 0 forever
end

local function flush(plr)
	local st = state[plr]
	if not st then return end
	-- ONE flush per player at a time: the minute loop, PlayerRemoving and BindToClose can all land together, and two
	-- flushes reading the same pending delta would add it twice
	while st.busy do task.wait(0.2) end
	st.busy = true
	for _, k in ipairs(KEYS) do
		local d = st.pending[k]
		if d > 0 and stores[k] then
			local ok, total = addStored(k, plr.UserId, d)
			if ok then
				-- pending may have grown while the call was in flight: take off only what was saved
				st.pending[k] -= d
				st.saved[k] += d
				if tonumber(total) then st.base[k] = tonumber(total) - st.saved[k] end
			end
		elseif st.base[k] == nil and stores[k] then
			readBase(plr, st, k)
		end
	end
	st.busy = false
	publish(plr)
end

local function onJoin(plr)
	if state[plr] then return end
	local st = { base = {}, saved = {}, pending = {}, last = {}, t = 0, seen = {}, asked = 0 }
	for _, k in ipairs(KEYS) do st.saved[k], st.pending[k] = 0, 0 end
	state[plr] = st
	publish(plr)
	for _, k in ipairs(KEYS) do task.spawn(readBase, plr, st, k) end
end

report.OnServerEvent:Connect(function(plr, t)
	local st = state[plr]
	if not st or type(t) ~= "table" then return end
	local now = os.clock()
	if now - st.t < MIN_GAP then return end
	local dt = math.clamp(now - st.t, MIN_GAP, BURST)
	st.t = now
	for k, rate in pairs(RATE) do
		local v = tonumber(t[k])
		if v and v == v and v >= 0 and v < math.huge then   -- (v == v rejects NaN)
			v = math.floor(math.min(v, MAX))
			local last = st.last[k]
			local d
			if last == nil then
				-- the first report of a visit is the BASELINE: QT_* are saved lifetime totals now (SaveServer), so
				-- counting them again would add a player's whole history to every board on every join
				d = 0
			elseif v >= last then
				d = v - last
			else
				d = v                      -- the session counter was reset (a dev reset): count from zero
			end
			st.last[k] = v
			if d > 0 then add(plr, k, math.min(d, rate * dt)) end
		end
	end
end)

------------------------------------------------------------------------------------------------ Robux (server only)
robuxIn.Event:Connect(function(plr, spent, purchaseId)
	local st = state[plr]
	if not st then return end
	if purchaseId then
		if st.seen[purchaseId] then return end
		st.seen[purchaseId] = true
	end
	add(plr, "robux", spent)
end)

-- this game's own passes: id -> Robux, from the same table the Shop sells them from
local PASS_PRICE = {}
for key, id in pairs(ShopProducts.PASS_IDS or {}) do
	local price = ShopProducts.PASS_ROBUX and ShopProducts.PASS_ROBUX[key]
	if tonumber(id) and id > 0 and tonumber(price) then PASS_PRICE[id] = price end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, purchased)
	local st = state[plr]
	local price = PASS_PRICE[passId]
	if not purchased or not st or not price or not passStore then return end
	if st.seen["pass" .. passId] then return end
	st.seen["pass" .. passId] = true
	-- this event can be fired from a client, so it is only a hint: the pass must really be owned...
	local okOwn, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, plr.UserId, passId)
	if not (okOwn and owns) then st.seen["pass" .. passId] = nil return end
	-- ...and counted once EVER (a pass is bought once per account), whichever server sees it first
	local created = false
	local ok = retry(function()
		created = false
		return passStore:UpdateAsync(plr.UserId .. "_" .. passId, function(old)
			if old then return nil end   -- already counted: cancel the write
			created = true
			return true
		end)
	end, 3)
	if ok and created then add(plr, "robux", price) end
end)

------------------------------------------------------------------------------------------------ top lists
local cache = {}         -- cache[k] = { {u = userId, n = display name, v = value}, ... }
local names = {}         -- userId -> { n = display name, t = clock }
local NAME_TTL = 600

local function resolveNames(ids)
	local want = {}
	for _, id in ipairs(ids) do
		local c = names[id]
		if not c or os.clock() - c.t > NAME_TTL then want[#want + 1] = id end
	end
	if #want > 0 then
		local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, want)
		if ok and type(infos) == "table" then
			for _, info in ipairs(infos) do
				names[info.Id] = { n = info.DisplayName or info.Username, t = os.clock() }
			end
		end
		for _, id in ipairs(want) do
			if not names[id] then
				local p = Players:GetPlayerByUserId(id)
				names[id] = { n = p and p.DisplayName or ("Angler " .. id), t = os.clock() - NAME_TTL + 60 }
			end
		end
	end
end

local function refresh(k)
	local st = stores[k]
	if not st then return end
	local ok, page = retry(function() return st:GetSortedAsync(false, TOP_N):GetCurrentPage() end, 2)
	if not ok or type(page) ~= "table" then return end
	local ids, list = {}, {}
	for _, e in ipairs(page) do
		local id, v = tonumber(e.key), tonumber(e.value)
		if id and v and v > 0 then
			ids[#ids + 1] = id
			list[#list + 1] = { u = id, v = v }
		end
	end
	resolveNames(ids)
	for _, row in ipairs(list) do row.n = names[row.u] and names[row.u].n or ("Angler " .. row.u) end
	cache[k] = list
	boards:FireAllClients(k, list)
end

boards.OnServerEvent:Connect(function(plr)
	local st = state[plr]
	if not st or os.clock() - st.asked < ASK_GAP then return end
	st.asked = os.clock()
	for _, k in ipairs(KEYS) do
		if cache[k] then boards:FireClient(plr, k, cache[k]) end
	end
end)

------------------------------------------------------------------------------------------------ loops
Players.PlayerAdded:Connect(onJoin)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onJoin, p) end
Players.PlayerRemoving:Connect(function(plr)
	flush(plr)
	state[plr] = nil
end)
game:BindToClose(function()
	local left = 0
	for plr in pairs(state) do
		left += 1
		task.spawn(function() flush(plr); left -= 1 end)
	end
	local t0 = os.clock()
	while left > 0 and os.clock() - t0 < 25 do task.wait(0.25) end
end)

task.spawn(function()
	while true do
		task.wait(SAVE_EVERY)
		for plr in pairs(state) do task.spawn(flush, plr) end
	end
end)

task.spawn(function()
	-- every board at once on startup, so nobody opens an empty board for a minute; then round-robin. The first
	-- minute costs 4 GetSortedAsync, the steady state ~3.2/min - both inside 5 + 2/player.
	task.wait(2)
	for _, k in ipairs(KEYS) do task.spawn(refresh, k) end
	task.wait(REFRESH)
	local i = 0
	while true do
		i = i % #KEYS + 1
		task.spawn(refresh, KEYS[i])
		task.wait(REFRESH / #KEYS)
	end
end)

------------------------------------------------------------------------------------------------ dev hook
local dev = script:FindFirstChild("DevLeaderboard") or Instance.new("BindableEvent")
dev.Name = "DevLeaderboard"
dev.Parent = script
dev.Event:Connect(function(verb)
	if verb == "seed" and mocked then
		-- STUDIO stand-in only: a few anglers to look at. Never runs against the real stores.
		local sample = { { 1, 5e3, 12e3, 3e4, 9e6 }, { 156, 120, 9e3, 2e4, 4e6 }, { 261, 0, 4e3, 8e3, 1e6 },
			{ 1001, 899, 1500, 2600, 3e5 }, { 2002, 49, 700, 900, 9e4 } }
		for _, s in ipairs(sample) do
			for j, k in ipairs(KEYS) do
				if s[j + 1] > 0 then addStored(k, s[1], s[j + 1]) end
			end
		end
		for _, k in ipairs(KEYS) do task.spawn(refresh, k) end
	elseif verb == "refresh" then
		for _, k in ipairs(KEYS) do task.spawn(refresh, k) end
	elseif verb == "flush" then
		for plr in pairs(state) do task.spawn(flush, plr) end
	end
end)

print(("[LeaderboardServer] online - %d ALL-TIME global boards (%s), top %d"):format(
	#KEYS, mocked and "Studio stand-in, nothing saved" or "OrderedDataStore", TOP_N))
