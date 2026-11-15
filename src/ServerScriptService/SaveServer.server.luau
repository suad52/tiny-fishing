--[==[
	SaveServer - player progress survives leaving (2026-10-11, the owner: "why doesnt the game save").

	Before this, every number in the game lived only in the player's client for one visit: money, rods, boats, zones,
	upgrades, rebirths, baits, potions, the Fish Index, quests, settings. Leaving lost all of it, including things
	bought with Robux. This script is the one place progress is loaded and stored.

	HOW IT FITS A CLIENT-SIDE ECONOMY
	  * LOAD FIRST, THEN SPAWN. Players.CharacterAutoLoads is off. At PlayerAdded the profile is loaded and written onto
	    the Player as attributes (server-set attributes replicate down), DataLoaded = true goes LAST, and only then is
	    LoadCharacter called. Every StarterGui menu (ResetOnSpawn = false) is cloned at that first spawn, so they all
	    start up already seeing the restored values and their "if nil then default" seeds leave them alone.
	    StarterPlayerScripts start at join, before the data: CurrencyClient / BoostClient / BoatClient / IdleClient /
	    GameClient were taught to follow the restore (SavedCoins, BoostSaved_<key>, DataLoaded).
	  * WRITE ONCE. After that load the server never writes a progress attribute again: a later server write would
	    replicate down and overwrite what the player has done since.
	  * SNAPSHOTS. StarterPlayerScripts.SaveClient sends an allowlisted snapshot (SaveRemotes.Snapshot) a few seconds
	    after anything changes and every 30 s. It is re-validated here against RULES and kept in memory. The profile
	    is written every 60 s, on leave, and at shutdown.
	  * ONE SERVER AT A TIME. The profile carries a lock {job, t}. A server that finds another server's fresh lock
	    waits for it to be released (the old server's leave-save clears it) before loading, and a save never
	    overwrites a profile another server has taken over. So a fast rejoin can't load stale data and then save it
	    over the newer copy.
	  * A FAILED LOAD NEVER SAVES. If the profile can't be read, the player is told and kicked rather than playing on
	    defaults that would then be saved over their real progress (DailyServer and WheelServer have that bug).
	  * ROBUX. ProductServer asks SaveApi before granting ("hasReceipt") and after ("commitReceipt"): a receipt only
	    returns PurchaseGranted once the client has acknowledged the grant in a snapshot AND that snapshot is saved.
	    If the player leaves first, Roblox re-sends the receipt next visit. Granted ids live in the profile.

	NOT SAVED HERE, on purpose: derived stats (MaxDepth, Boost*, Rod*/Bait*/Boat* stats, RebirthMult, ...), session
	flags (TutorialActive, JackpotActive, ReelStarts, Afk, gift clock), game passes (Roblox owns those), and things
	that already have their own store (daily streak, wheel spins, Deep Pockets rate, Robux zones, leaderboards).

	STUDIO: without API access the store is an in-memory stand-in seeded from ServerStorage.__StudioSaves (JSON) and
	written back into it, so a test can copy it between Play sessions to fake a rejoin. Prints which one it uses.
]==]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local DataStoreService  = game:GetService("DataStoreService")
local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")

local STORE_NAME = "PlayerSave_v1"
local SAVE_EVERY = 60
local LOCK_TTL   = 150      -- a lock not refreshed for this long belongs to a dead server
local LOCK_WAIT  = 20       -- seconds to wait for another server to release a fresh lock before taking it
local MAX_KEYS   = 450
local RECEIPTS   = 200      -- newest granted receipt ids kept in the profile
local JOB        = game.JobId ~= "" and game.JobId or "studio"

Players.CharacterAutoLoads = false

------------------------------------------------------------------------------------------------ what may be saved
-- name pattern -> allowed type(s). The client's SaveClient mirrors this list; this copy is the one that counts.
local RULES = {
	{ "^Rebirths$", "number" }, { "^Pearls$", "number" }, { "^Perk_%a+$", "number" }, { "^Upg_%a+$", "number" },
	{ "^EquippedRod$", "number" }, { "^Bait_%w+$", "number" }, { "^Inv_[%w_]+$", "number" },
	{ "^JackpotCasts$", "number" }, { "^CurrentZone$", "number" }, { "^CurrentBoat$", "number" },
	{ "^QP_[%w_]+$", "number" }, { "^QT_%a+$", "number" }, { "^MT_[%w_]+$", "number" },
	{ "^Q_DayStamp$", "number" }, { "^Q_WeekStamp$", "number" }, { "^BaitPity%d$", "number" },
	{ "^BoostLeft_[%w_]+$", "number" },
	{ "^Rod_%d+$", "boolean" }, { "^Zone_%d+$", "boolean" }, { "^Boat_%d+$", "boolean" }, { "^QC_[%w_]+$", "boolean" },
	{ "^IX_%w+$", "boolean" }, { "^TutorialDone$", "boolean" }, { "^StarterBought$", "boolean" },
	{ "^AutoCastOn$", "boolean" },
	{ "^Set_%w+$", "boolean", "number" },
	{ "^EquippedBait$", "string", 40 }, { "^IndexSeen$", "string", 4000 },
}
local function valid(name, v)
	if type(name) ~= "string" or #name > 40 then return false end
	local t = type(v)
	for _, r in ipairs(RULES) do
		if name:match(r[1]) then
			if t == "number" then
				return (r[2] == "number" or r[3] == "number") and v == v and v > -1e18 and v < 1e18
			elseif t == "boolean" then
				return r[2] == "boolean" or r[3] == "boolean"
			elseif t == "string" then
				return r[2] == "string" and #v <= (r[3] or 0)
			end
			return false
		end
	end
	return false
end

------------------------------------------------------------------------------------------------ the store
local store, mocked = nil, false
do
	local ok, st = pcall(DataStoreService.GetDataStore, DataStoreService, STORE_NAME)
	store = ok and st or nil
	if RunService:IsStudio() then
		local probe = store and pcall(function() return store:GetAsync("probe") end)
		if not probe then
			-- Studio without API access: an in-memory stand-in, seeded from / written back to a StringValue
			mocked = true
			local holder = ServerStorage:FindFirstChild("__StudioSaves")
			local data = {}
			if holder then pcall(function() data = HttpService:JSONDecode(holder.Value) end) end
			local function flushMock()
				local h = ServerStorage:FindFirstChild("__StudioSaves") or Instance.new("StringValue")
				h.Name = "__StudioSaves"
				h.Value = HttpService:JSONEncode(data)
				h.Parent = ServerStorage
			end
			store = {}
			function store:GetAsync(k) return data[k] end
			function store:UpdateAsync(k, fn)
				local v = fn(data[k])
				if v ~= nil then data[k] = v; flushMock() end
				return data[k]
			end
		end
	end
end

------------------------------------------------------------------------------------------------ remotes / api
local remotes = ReplicatedStorage:FindFirstChild("SaveRemotes") or Instance.new("Folder")
remotes.Name = "SaveRemotes"
remotes.Parent = ReplicatedStorage
local snapEv = remotes:FindFirstChild("Snapshot") or Instance.new("RemoteEvent")
snapEv.Name = "Snapshot"
snapEv.Parent = remotes

local api = ServerStorage:FindFirstChild("SaveApi") or Instance.new("BindableFunction")
api.Name = "SaveApi"
api.Parent = ServerStorage

------------------------------------------------------------------------------------------------ per player
-- state[plr] = { key, attrs, coins, receipts = {id = os.time()}, dirty, busy, bucket, t }
local state = {}
local committed = {}   -- ["<userId>:<receipt>"] = true once a saved profile contained it (survives the leave)

local function keyOf(plr) return "u_" .. plr.UserId end

-- Load with a lock. Returns the profile table, or nil if the store could not be read.
local function lockAndLoad(plr)
	local key = keyOf(plr)
	local t0 = os.clock()
	local attempt = 0
	while plr.Parent do
		attempt += 1
		local verdict
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old)
				old = type(old) == "table" and old or { v = 1, attrs = {}, receipts = {} }
				local lock = old.lock
				if type(lock) == "table" and lock.job ~= JOB and os.time() - (tonumber(lock.t) or 0) < LOCK_TTL
					and os.clock() - t0 < LOCK_WAIT then
					verdict = "locked"
					return nil                      -- another server still has them: don't touch it yet
				end
				old.lock = { job = JOB, t = os.time() }
				verdict = old
				return old
			end)
		end)
		if ok and type(verdict) == "table" then return verdict end
		if not ok then
			warn("[SaveServer] load failed for " .. plr.Name .. " (try " .. attempt .. "): " .. tostring(err))
			if attempt >= 5 then return nil end
		end
		task.wait(math.min(1 + attempt, 5))
	end
	return nil
end

local function trimReceipts(r)
	local list = {}
	for id, t in pairs(r) do list[#list + 1] = { id, tonumber(t) or 0 } end
	if #list <= RECEIPTS then return r end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	local out = {}
	for i = 1, RECEIPTS do out[list[i][1]] = list[i][2] end
	return out
end

-- returns "ok" (written), "foreign" (another server holds them now: never overwrite), "closed" (the leave/shutdown
-- save already owns this session) or "error" (the call failed - worth retrying)
local function save(plr, final)
	local st = state[plr]
	if not st then return "error" end
	-- a final save marks the session closed BEFORE waiting, so an autosave / receipt save queued behind it can't
	-- run afterwards and write the lock back (the next join would then wait the lock out with no character)
	if final then st.closed = true end
	while st.busy do task.wait(0.1) end
	if not final and st.closed then return "closed" end
	st.busy = true
	st.receipts = trimReceipts(st.receipts)
	-- a COPY: an ack landing while the write is in flight must not be marked committed by a write that lacked it
	local rc = table.clone(st.receipts)
	local profile = { v = 1, attrs = st.attrs, coins = st.coins, receipts = rc, saved = os.time() }
	local wrote = false
	local ok, err = pcall(function()
		store:UpdateAsync(st.key, function(old)
			local lock = type(old) == "table" and old.lock
			if type(lock) == "table" and lock.job ~= JOB and os.time() - (tonumber(lock.t) or 0) < LOCK_TTL then
				wrote = false
				return nil                          -- another server took this player over: never overwrite it
			end
			profile.lock = (not final) and { job = JOB, t = os.time() } or nil
			wrote = true
			return profile
		end)
	end)
	st.busy = false
	if not ok then warn("[SaveServer] save failed for " .. plr.Name .. ": " .. tostring(err)) return "error" end
	if not wrote then return "foreign" end
	st.dirty = false
	for id in pairs(rc) do committed[plr.UserId .. ":" .. id] = true end
	return "ok"
end

-- the leave / shutdown save: one DataStore hiccup must not lose everything since the last autosave
local function saveFinal(plr)
	local r = "error"
	for i = 1, 4 do
		r = save(plr, true)
		if r ~= "error" then return r end
		if i < 4 then task.wait(math.min(2 ^ (i - 1), 4)) end
	end
	warn("[SaveServer] final save gave up for " .. plr.Name)
	return r
end

-- Write the profile onto the Player, in the order the menus need, then DataLoaded LAST.
local function applyAttributes(plr, profile)
	local attrs = type(profile.attrs) == "table" and profile.attrs or {}
	local function ok(n) return attrs[n] ~= nil and valid(n, attrs[n]) end
	-- 1. Rebirths first: ZonesController / QuestsController take it as their baseline at startup
	if ok("Rebirths") then plr:SetAttribute("Rebirths", attrs.Rebirths) end
	-- 2. ownership (only the owned ones; absent already means not owned)
	for n, v in pairs(attrs) do
		if (n:match("^Zone_%d+$") or n:match("^Boat_%d+$") or n:match("^Rod_%d+$")) and v == true then
			plr:SetAttribute(n, true)
		end
	end
	-- 3. selections, validated against that ownership (travelTo / applyBoat never check it themselves)
	local function pick(n, maxId, prefix)
		local id = math.clamp(math.floor(tonumber(attrs[n]) or 1), 1, maxId)
		if id > 1 and attrs[prefix .. id] ~= true then id = 1 end
		plr:SetAttribute(n, id)
	end
	pick("CurrentZone", 6, "Zone_")
	pick("CurrentBoat", 8, "Boat_")
	pick("EquippedRod", 10, "Rod_")
	-- 4. everything else
	local done = { Rebirths = true, CurrentZone = true, CurrentBoat = true, EquippedRod = true }
	for n, v in pairs(attrs) do
		if not done[n] and not n:match("^Zone_%d+$") and not n:match("^Boat_%d+$") and not n:match("^Rod_%d+$")
			and valid(n, v) then
			local potion = n:match("^BoostLeft_([%w_]+)$")
			if potion then
				-- restore-only name: BoostClient resumes the potion from it (it keeps writing BoostLeft_ itself)
				if v > 0 then plr:SetAttribute("BoostSaved_" .. potion, math.floor(v)) end
			else
				plr:SetAttribute(n, v)
			end
		end
	end
	-- 5. money, under a restore-only name the client never writes (CurrencyClient copies it into leaderstats.Money)
	local coins = tonumber(profile.coins)
	if coins and coins == coins and coins >= 0 and coins < 1e18 then plr:SetAttribute("SavedCoins", coins) end
	-- 6. LAST: everything above has replicated by the time a client sees this
	plr:SetAttribute("DataLoaded", true)
end

local function spawnCharacter(plr)
	plr.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid", 10)
		if hum then
			hum.Died:Connect(function()
				-- CharacterAutoLoads is off, so a death (or Reset) respawns here
				task.delay(Players.RespawnTime, function()
					if plr.Parent and plr.Character == char then pcall(function() plr:LoadCharacter() end) end
				end)
			end)
		end
	end)
	pcall(function() plr:LoadCharacter() end)
end

local function onJoin(plr)
	if state[plr] then return end
	local profile = lockAndLoad(plr)
	if not plr.Parent then
		-- they left while we loaded: hand the lock straight back so their next server needn't wait it out
		if profile then
			pcall(function()
				store:UpdateAsync(keyOf(plr), function(old)
					if type(old) == "table" and type(old.lock) == "table" and old.lock.job == JOB then
						old.lock = nil
						return old
					end
					return nil
				end)
			end)
		end
		return
	end
	if not profile then
		plr:Kick("We couldn't load your save, so we stopped before anything could be lost. Please rejoin in a minute.")
		return
	end
	local receipts = {}
	if type(profile.receipts) == "table" then
		for id, t in pairs(profile.receipts) do
			if type(id) == "string" then receipts[id] = tonumber(t) or 0 end
		end
	end
	state[plr] = {
		key = keyOf(plr),
		attrs = type(profile.attrs) == "table" and profile.attrs or {},
		coins = tonumber(profile.coins),
		receipts = receipts,
		dirty = false, busy = false, bucket = 5, t = os.clock(),
	}
	for id in pairs(receipts) do committed[plr.UserId .. ":" .. id] = true end
	applyAttributes(plr, profile)
	spawnCharacter(plr)
	print(("[SaveServer] loaded %s: %d values, $%s"):format(plr.Name,
		(function() local n = 0 for _ in pairs(state[plr].attrs) do n += 1 end return n end)(),
		tostring(state[plr].coins or 0)))
end

------------------------------------------------------------------------------------------------ snapshots
snapEv.OnServerEvent:Connect(function(plr, snap)
	local st = state[plr]
	if not st or type(snap) ~= "table" then return end
	-- token bucket: SaveClient sends at most every 2.5 s; anything far faster is not SaveClient
	local now = os.clock()
	st.bucket = math.min(5, st.bucket + (now - st.t) * 1)
	st.t = now
	if st.bucket < 1 then return end
	st.bucket -= 1

	if type(snap.attrs) == "table" then
		local attrs, n = {}, 0
		for name, v in pairs(snap.attrs) do
			if valid(name, v) then
				n += 1
				if n > MAX_KEYS then break end
				attrs[name] = v
			end
		end
		st.attrs = attrs          -- REPLACED, never merged: a zone re-locked by a rebirth must stay locked
	end
	local coins = tonumber(snap.coins)
	if coins and coins == coins and coins >= 0 and coins < 1e18 then st.coins = coins end
	if type(snap.acks) == "table" then
		for i, id in ipairs(snap.acks) do
			if i > 50 then break end
			if type(id) == "string" and #id <= 80 and not st.receipts[id] then st.receipts[id] = os.time() end
		end
	end
	st.dirty = true
end)

------------------------------------------------------------------------------------------------ receipts api
api.OnInvoke = function(verb, plr, receiptId, timeout)
	if typeof(plr) ~= "Instance" or not plr:IsA("Player") or type(receiptId) ~= "string" then return false end
	local ck = plr.UserId .. ":" .. receiptId
	-- wait for the profile to load (a receipt can arrive the moment someone joins)
	local t0 = os.clock()
	while plr.Parent and not state[plr] and os.clock() - t0 < 30 do task.wait(0.2) end
	if verb == "hasReceipt" then
		if committed[ck] then return true end
		local st = state[plr]
		if not st then return nil end   -- not loaded: UNKNOWN, and ProductServer must not grant on a guess
		return st.receipts[receiptId] ~= nil
	elseif verb == "commitReceipt" then
		-- the grant counts once a snapshot that contains it has been SAVED
		local limit = os.clock() + (tonumber(timeout) or 30)
		while os.clock() < limit do
			if committed[ck] then return true end
			local st = state[plr]
			if not st then
				-- they left: the leave-save wrote whatever their last snapshot held
				task.wait(0.5)
				return committed[ck] == true
			end
			if st.receipts[receiptId] then
				local r = save(plr, false)
				if r == "closed" then
					-- they're leaving: the final save carries this ack; report what it committed
					local t1 = os.clock()
					while not committed[ck] and state[plr] and os.clock() - t1 < 30 do task.wait(0.25) end
				end
				return committed[ck] == true
			end
			task.wait(0.25)
		end
		return committed[ck] == true
	end
	return false
end

------------------------------------------------------------------------------------------------ lifecycle
Players.PlayerAdded:Connect(onJoin)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onJoin, p) end

Players.PlayerRemoving:Connect(function(plr)
	if state[plr] then
		saveFinal(plr)
		state[plr] = nil
	end
end)

game:BindToClose(function()
	local left = 0
	for plr in pairs(state) do
		left += 1
		task.spawn(function() saveFinal(plr); left -= 1 end)
	end
	local t0 = os.clock()
	while left > 0 and os.clock() - t0 < 25 do task.wait(0.25) end
end)

task.spawn(function()
	while true do
		task.wait(SAVE_EVERY)
		-- every player, dirty or not: the save also refreshes the lock this server holds on them
		for plr in pairs(state) do task.spawn(save, plr, false) end
	end
end)

-- dev hook (tests): script.DevSave:Fire("saveall") saves everyone now, as a minute tick would
local dev = script:FindFirstChild("DevSave") or Instance.new("BindableEvent")
dev.Name = "DevSave"
dev.Parent = script
dev.Event:Connect(function(verb)
	if verb == "saveall" then
		for plr in pairs(state) do task.spawn(save, plr, false) end
	end
end)

print("[SaveServer] online - " .. STORE_NAME .. (mocked and " (Studio stand-in: ServerStorage.__StudioSaves)" or ""))
