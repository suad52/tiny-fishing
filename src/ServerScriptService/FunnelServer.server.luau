--[==[
	FunnelServer - logs the Roblox Analytics funnels defined in ReplicatedStorage.FunnelDefs.

	AnalyticsService is server-only, while this game's tutorial and economy live on the client, so
	the client REPORTS (AnalyticsRemotes.Funnel) and this script LOGS:
		("Onboarding", key)          a tutorial beat, by FunnelDefs.ONBOARDING key
		("Onboarding", "skip", step) the Skip button -> custom event "TutorialSkipped", value = the step
		(<funnel name>, level)       a progression funnel reached a new level
	The step-1 baselines (Joined, Zone 1, Rod 1, ...) are logged here on PlayerAdded.

	TRUST: the reports are client-asserted, like the rest of this economy. What is enforced here is
	shape (known funnel, whole number in range), order (a step only ever moves forward, so a late or
	repeated report is a no-op), and a per-player budget so a spammer cannot flood the event quota.

	Every step between the last logged one and the new one is logged too, so each carries its name.
	Roblox counts a step once per user (funnelSessionId nil), so a rejoin re-reporting is harmless.

	Off switch: set this script's attribute Funnels = false. In Studio nothing reaches the
	dashboard; each step prints "[Funnel]" so the wiring can be checked.
]==]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local AnalyticsService  = game:GetService("AnalyticsService")

local Defs = require(ReplicatedStorage:WaitForChild("FunnelDefs"))

local folder = ReplicatedStorage:FindFirstChild("AnalyticsRemotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "AnalyticsRemotes"
	folder.Parent = ReplicatedStorage
end
local remote = folder:FindFirstChild("Funnel")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "Funnel"
	remote.Parent = folder
end

local STUDIO = RunService:IsStudio()
local BUDGET, REFILL = 30, 1   -- burst of 30 reports, then 1 a second
local state = {}

local function on() return script:GetAttribute("Funnels") ~= false end

local function note(plr, what)
	if STUDIO then print("[Funnel] " .. plr.Name .. " " .. what) end
end

local function logOnboard(plr, idx)
	local st = state[plr]
	if not st or not on() or idx <= st.onboard then return end
	for i = st.onboard + 1, idx do
		local name = Defs.ONBOARDING[i].name
		local ok, err = pcall(AnalyticsService.LogOnboardingFunnelStepEvent, AnalyticsService, plr, i, name)
		if not ok then warn("[Funnel] onboarding " .. i .. ": " .. tostring(err)) end
		note(plr, "Onboarding " .. i .. " " .. name)
	end
	st.onboard = idx
end

local function logFunnel(plr, f, level)
	local st = state[plr]
	if not st or not on() then return end
	local last = st.funnels[f.name] or 0
	if level <= last then return end
	for i = last + 1, level do
		local ok, err = pcall(AnalyticsService.LogFunnelStepEvent, AnalyticsService, plr, f.name, nil, i, f.steps[i])
		if not ok then warn("[Funnel] " .. f.name .. " " .. i .. ": " .. tostring(err)) end
		note(plr, f.name .. " " .. i .. " " .. f.steps[i])
	end
	st.funnels[f.name] = level
end

local function onJoin(plr)
	if state[plr] then return end
	state[plr] = { onboard = 0, funnels = {}, budget = BUDGET, t = os.clock() }
	logOnboard(plr, 1)
	for _, f in ipairs(Defs.FUNNELS) do logFunnel(plr, f, 1) end
end

remote.OnServerEvent:Connect(function(plr, kind, a, b)
	local st = state[plr]
	if not st or type(kind) ~= "string" then return end
	local now = os.clock()
	st.budget = math.min(BUDGET, st.budget + (now - st.t) * REFILL)
	st.t = now
	if st.budget < 1 then return end
	st.budget -= 1

	if kind == "Onboarding" then
		if a == "skip" then
			local at = tonumber(b)
			if st.skipped or not at or at ~= at then return end
			st.skipped = true
			if on() then
				pcall(AnalyticsService.LogCustomEvent, AnalyticsService, plr, "TutorialSkipped", math.clamp(math.floor(at), 0, 99))
				note(plr, "TutorialSkipped at step " .. math.floor(at))
			end
			return
		end
		local idx = type(a) == "string" and Defs.ONBOARD_INDEX[a]
		if idx and idx >= 2 then logOnboard(plr, idx) end
		return
	end

	local f = Defs.byName[kind]
	if not f or type(a) ~= "number" or a ~= a then return end
	logFunnel(plr, f, math.clamp(math.floor(a), 1, #f.steps))
end)

Players.PlayerAdded:Connect(onJoin)
Players.PlayerRemoving:Connect(function(plr) state[plr] = nil end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onJoin, p) end

local n = 0
for _, f in ipairs(Defs.FUNNELS) do n += #f.steps end
print(("[FunnelServer] online - Onboarding (%d steps) + %d progression funnels (%d steps)"):format(
	#Defs.ONBOARDING, #Defs.FUNNELS, n))
