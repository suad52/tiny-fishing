--[[
	IdleServer — pays out Deep Pockets earnings for the time you were away.

	Deep Pockets (Upgrades tree) banks cash while you are offline. The rate lives on the
	CLIENT — UpgradesMenu publishes UpgIdleRate, and attributes a LocalScript sets on the
	Player do NOT replicate up — so the client reports it and this script is what actually
	persists it. Per player we keep { rate = cash/sec, at = unix time of the last save,
	pending = earned but not yet claimed }.
	On join we add (now - at) * rate to pending, capped at OFFLINE_CAP so a long absence can't
	mint an absurd sum, and skipped under MIN_AWAY so a quick rejoin isn't spammy.

	CLAIM (2026-10-11, owner: "why didnt i get the prompt to claim my offline money"). The client
	shows a card once its loading screen lifts and banks the money when the player claims it, then
	fires IdleRemotes.Claim; only then is pending zeroed (and saved at once). Leave without claiming
	and it carries to the next visit.

	⚠️ SERVERS HOLD ONE PLAYER, so a server shuts down the moment its player leaves. BindToClose
	therefore waits for the leave-saves still in flight (`saving`), or the last write was cut off.

	TRUST: the rate is client-reported and therefore spoofable. That matches the rest of
	this place — the balance itself is client-side (CurrencyClient) — so it adds no new
	exploit surface. If the economy is ever made server-authoritative, move the upgrade
	tiers to the server and read them here instead of trusting ReportRate.
]]

local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local OFFLINE_CAP = 8 * 3600   -- never bank more than 8 hours of absence
local MIN_AWAY    = 60         -- under a minute away isn't worth a popup
local MAX_RATE    = 50         -- cash/sec sanity bound on the reported rate
local MAX_PENDING = 3 * OFFLINE_CAP * MAX_RATE   -- unclaimed carry-over ceiling

local store
do
	local ok, res = pcall(function() return DataStoreService:GetDataStore("DeepPockets_v1") end)
	store = ok and res or nil
end

local remotes = ReplicatedStorage:FindFirstChild("IdleRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "IdleRemotes"
	remotes.Parent = ReplicatedStorage
end
local function remote(name)
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = remotes
	end
	return r
end
local reportRate    = remote("ReportRate")
local offlinePayout = remote("OfflinePayout")
local claimPayout   = remote("Claim")

local state = {}   -- [userId] = { rate, at, pending, away, noSave, busy }
local saving = 0   -- leave-saves in flight (see the header)
local function key(plr) return "u_" .. plr.UserId end

-- One write at a time per player, built AFTER the previous one lands: a periodic save that started before a claim
-- must not finish after it and put the claimed amount back.
local function save(plr)
	local st = state[plr.UserId]
	if not (store and st) or st.noSave then return end
	while st.busy do task.wait(0.1) end
	st.busy = true
	st.at = os.time()
	local rec = { rate = st.rate, at = st.at, pending = st.pending }
	pcall(function() store:SetAsync(key(plr), rec) end)
	st.busy = false
end

reportRate.OnServerEvent:Connect(function(plr, rate)
	if typeof(rate) ~= "number" or rate ~= rate or rate == math.huge then return end
	local st = state[plr.UserId]
	if st then st.rate = math.clamp(rate, 0, MAX_RATE) end
end)

claimPayout.OnServerEvent:Connect(function(plr)
	local st = state[plr.UserId]
	if not st or st.pending <= 0 then return end
	st.pending, st.away = 0, 0
	task.spawn(save, plr)
end)

-- data = the stored record (nil = none yet). failed = the read failed: then this session never writes, so it can't
-- save an empty pending over a real one.
local function arrive(plr, data, failed)
	local st = { rate = 0, at = os.time(), pending = 0, away = 0, noSave = failed }
	if data then
		st.rate = math.clamp(tonumber(data.rate) or 0, 0, MAX_RATE)
		st.pending = math.max(0, math.floor(tonumber(data.pending) or 0))
		local at = tonumber(data.at)
		if at and st.rate > 0 then
			local away = math.clamp(os.time() - at, 0, OFFLINE_CAP)
			if away >= MIN_AWAY then
				st.pending += math.floor(away * st.rate)
				st.away = away
			end
		end
		st.pending = math.min(st.pending, MAX_PENDING)
	end
	state[plr.UserId] = st
	if st.pending <= 0 then return end
	-- after the save has loaded (SaveServer sets DataLoaded last): the client banks it onto the restored balance.
	-- The client then holds the card until its loading screen has lifted.
	task.spawn(function()
		local t0 = os.clock()
		while plr.Parent and plr:GetAttribute("DataLoaded") ~= true and os.clock() - t0 < 60 do task.wait(0.25) end
		if plr.Parent and state[plr.UserId] == st and st.pending > 0 then
			offlinePayout:FireClient(plr, st.pending, st.away)
		end
	end)
end

Players.PlayerAdded:Connect(function(plr)
	local data, failed = nil, false
	if store then
		local ok, res
		for i = 1, 3 do
			ok, res = pcall(function() return store:GetAsync(key(plr)) end)
			if ok then break end
			if i < 3 then task.wait(i) end
		end
		if ok then
			if type(res) == "table" then data = res end
		else
			failed = true
		end
	end
	if plr.Parent then arrive(plr, data, failed) end
end)

Players.PlayerRemoving:Connect(function(plr)
	if not state[plr.UserId] then return end
	saving += 1
	save(plr)
	saving -= 1
	state[plr.UserId] = nil
end)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		if state[plr.UserId] then
			saving += 1
			task.spawn(function() save(plr); saving -= 1 end)
		end
	end
	local t0 = os.clock()
	while saving > 0 and os.clock() - t0 < 25 do task.wait(0.25) end
end)

task.spawn(function()
	while task.wait(60) do            -- periodic save so a crash doesn't lose the clock
		for _, plr in ipairs(Players:GetPlayers()) do task.spawn(save, plr) end
	end
end)

-- Studio has no DataStore unless API access is on, so a rejoin can't be faked. This replays a join instead:
--   game.ServerScriptService.IdleServer.DevOffline:Fire(player, secondsAway, cashPerSecond)
if RunService:IsStudio() then
	local dev = script:FindFirstChild("DevOffline") or Instance.new("BindableEvent")
	dev.Name = "DevOffline"
	dev.Parent = script
	dev.Event:Connect(function(plr, away, rate)
		local cur = state[plr.UserId]
		arrive(plr, { rate = rate, at = os.time() - (tonumber(away) or 0), pending = cur and cur.pending or 0 }, true)
	end)
end

print("[IdleServer] online — Deep Pockets " ..
	(store and "(DataStore ready)" or "(no DataStore — offline earnings disabled)"))
