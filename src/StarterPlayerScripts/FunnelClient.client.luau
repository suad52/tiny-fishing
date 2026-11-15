--[==[
	FunnelClient - reports progression to FunnelServer, which logs the Analytics funnels.

	Watches the attributes the client-side economy already writes (Zone_N, Rod_N, Boat_N, Rebirths,
	QT_earn, Discovered - see FunnelDefs.FUNNELS) and sends a report only when a funnel reaches a
	level it has not reported before, so a long session costs a handful of remote calls, not one
	per fish. Also reports the "Loaded In" onboarding step when the loading screen lifts.
	The tutorial's own beats are reported by TutorialController.
]==]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local plr    = Players.LocalPlayer
local Defs   = require(ReplicatedStorage:WaitForChild("FunnelDefs"))
local remote = ReplicatedStorage:WaitForChild("AnalyticsRemotes"):WaitForChild("Funnel")

local sent = {}   -- funnel name -> highest level reported (the server logged 1 on join)

local function check(f)
	local lvl = Defs.levelOf(plr, f)
	if lvl > (sent[f.name] or 1) then
		sent[f.name] = lvl
		remote:FireServer(f.name, lvl)
	end
end

plr.AttributeChanged:Connect(function(name)
	local f = Defs.funnelFor(name)
	if f then check(f) end
end)

-- one sweep once the menus have seeded their attributes (a Robux zone restored at join, say)
task.delay(3, function()
	for _, f in ipairs(Defs.FUNNELS) do check(f) end
end)

local loadedSent = false
local function loaded()
	if loadedSent or not plr:GetAttribute("LoadingDone") then return end
	loadedSent = true
	remote:FireServer("Onboarding", "loaded")
end
plr:GetAttributeChangedSignal("LoadingDone"):Connect(loaded)
loaded()
