--[[
	Scenery3DClient - drives ReplicatedStorage.DeepScenery.

	Replaces StarterPlayerScripts.DepthStrata, which painted all five underwater bands
	onto flat SurfaceGui panels. That script is DISABLED, not deleted, and everything this
	one changes is recorded in ServerStorage.Scenery3D_Snapshot - see the revert notes at
	the bottom of this file.

	What this owns:
	  * building the active zone's 3D column (rebuilt on CurrentZone, ~120ms)
	  * the per-frame step: band animation, the murk wall, and the underwater light rig
	  * publishing DepthStratum / DepthStratumName, which GameClient's bait lamp reads
	  * the Settings contract (Set_Particles / Set_WaterFX)

	What it deliberately does NOT own: the waterline. SeaFX still owns the wave ribbon,
	foam and surface motes, and ZonesController still owns surface Lighting - the light
	rig captures whatever ZonesController last set and hands it straight back on the way
	up, rather than trying to second-guess it.
--]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS         = game:GetService("ReplicatedStorage")

local plr = Players.LocalPlayer
local DS  = require(RS:WaitForChild("DeepScenery"))

----------------------------------------------------------------------
-- take over from the painted version
----------------------------------------------------------------------
local zone = workspace:WaitForChild("Zone1")

-- The painted ZoneBackdrops (three flat SurfaceGui panels per zone carrying sky, horizon
-- and a sea band) are replaced by the real 3D surface scenery. They also reach from
-- y=+68 down to y=-46, so left on they would hang BELOW the waterline in front of the
-- shallows now that WaterBack no longer hides them.
--
-- ⚠️ FIGHTING ZonesController OVER `Enabled` DOES NOT WORK. Its showBackdrop(id) runs on
-- join and on every travel, so a one-shot sweep gets undone a second later; latching each
-- SurfaceGui with GetPropertyChangedSignal did not hold either. Meanwhile the panels sit
-- at z=-45..-115, IN FRONT of the 3D land at z=-165 and beyond, so the volcano zone was
-- rendering Lighthouse Cove's painted cartoon mountains straight over the real geometry.
--
-- So move the PARTS instead. ZonesController only ever touches Enabled, never position,
-- which makes parking them somewhere else completely stable - and exactly reversible,
-- since each part records the Y it came from.
-- ⚠⚠ THESE PANELS ARE SERVER-OWNED AND EVERY ONE-SHOT FIX GETS UNDONE, SILENTLY.
-- Three approaches were tried and all three lost:
--   1. disable the SurfaceGuis at startup  -> ZonesController's showBackdrop re-enables
--      them on join and on every travel
--   2. latch each one with GetPropertyChangedSignal("Enabled") -> did not hold either
--   3. move the PARTS out of the scene -> the moves and even the marker attributes were
--      reverted within a second (replication reasserting server state), so the sweep ran
--      over and over reporting "parked 18" on parts that were already back where they
--      started
-- What cannot lose a race is enforcing it from the render loop. 18 boolean writes a frame
-- is nothing, it depends on no startup ordering, and it is trivially reversible - the
-- originals are recorded in ServerStorage.Scenery3D_Snapshot.
local painted = {}
local function collectPainted(f)
	if not f then return end
	for _, d in ipairs(f:GetDescendants()) do
		if d:IsA("SurfaceGui") then painted[d] = true end
	end
end
-- Only when the 3D surface is actually replacing them. With DeepScenery.SURFACE_3D off
-- the painted backdrops ARE the surface and must be left alone.
local function hidePainted()
	if not DS.SURFACE_3D then return end
	for g in pairs(painted) do
		if g.Enabled then g.Enabled = false end
	end
end
-- ⚠️ WaitForChild, NOT FindFirstChild. These are folders nested a level down and they
-- have not replicated to the client yet when this script first runs - FindFirstChild
-- returned nil for BOTH of them, parkPainted silently did nothing, and the painted
-- backdrops stayed in the scene with no error anywhere to show for it. The second pass
-- catches anything that arrived even later.
-- ⚠️ STARTUP ORDER HERE IS NOT WORTH FIGHTING, AND EVERY FAILURE IS SILENT.
-- LocalScripts in StarterPlayerScripts start in arbitrary order (across runs this script
-- came up both first and dead last), the Zone1.Horizon / ZoneBackdrops folders have often
-- not replicated yet when it does, and ZonesController re-asserts its own state on join
-- and on every travel. A one-shot takeover at the top of the file appeared to work,
-- errored nowhere, and left the painted backdrops standing in the scene.
-- So: make the takeover IDEMPOTENT and just keep doing it for the first few seconds.
local function takeOver()
	-- WaterBack is an OPAQUE slab at Z=-3 spanning the entire column, so it sits in FRONT
	-- of every piece of 3D scenery. The murk wall plus depth fog do its job now.
	local wb = zone:FindFirstChild("WaterBack")
	if wb and wb.Transparency < 1 then
		wb.Transparency = 1
		for _, d in ipairs(wb:GetDescendants()) do
			if d:IsA("SurfaceGui") then d.Enabled = false end
		end
	end
	collectPainted(zone:FindFirstChild("Horizon"))
	collectPainted(workspace:FindFirstChild("ZoneBackdrops"))
	hidePainted()
	-- DepthStrata is always replaced (it owns the underwater bands). BackdropFX only
	-- animates the painted SURFACE panels, so it stays alive unless those are gone.
	local ds = script.Parent:FindFirstChild("DepthStrata")
	if ds and ds:IsA("LocalScript") and not ds.Disabled then ds.Disabled = true end
	local bf = script.Parent:FindFirstChild("BackdropFX")
	if bf and bf:IsA("LocalScript") and DS.SURFACE_3D and not bf.Disabled then
		bf.Disabled = true
	end
	-- DepthStrata may have already built its painted planes before losing the race
	local col = workspace:FindFirstChild("DepthColumn")
	if col then
		for _, ch in ipairs(col:GetChildren()) do
			if ch:IsA("BasePart") then ch:Destroy() end
		end
	end
end
takeOver()

local root = workspace:FindFirstChild("Scenery3D")
	or Instance.new("Folder")
root.Name = "Scenery3D"
root.Parent = workspace

----------------------------------------------------------------------
-- build
----------------------------------------------------------------------
local state
local function currentZone() return plr:GetAttribute("CurrentZone") or 1 end

local fx = { parts = true, water = true }
local function readSettings()
	fx.parts = plr:GetAttribute("Set_Particles") ~= false
	fx.water = plr:GetAttribute("Set_WaterFX") ~= false
	if state then DS.setParticles(state, fx.parts) end
end

local function rebuild(zid)
	takeOver()
	state = DS.build(zid, root)
	-- ⚠️ A rebuild makes every element from scratch, so the settings have to be re-applied
	-- or travelling with particles switched off silently brings them all back.
	readSettings()
end

plr:GetAttributeChangedSignal("Set_Particles"):Connect(readSettings)
plr:GetAttributeChangedSignal("Set_WaterFX"):Connect(readSettings)

rebuild(currentZone())
plr:GetAttributeChangedSignal("CurrentZone"):Connect(function() rebuild(currentZone()) end)

----------------------------------------------------------------------
-- publish the stratum
--
-- ⚠️ Re-publish on ZONE change, not just on stratum index. The index is the same 1 before
-- and after travelling, so gating on it alone leaves the NAME stale - standing in zone
-- 1's shallows still reporting "Ash Shallows".
----------------------------------------------------------------------
local lastI, lastZ
local function publish(idx, zid)
	if lastI == idx and lastZ == zid then return end
	lastI, lastZ = idx, zid
	plr:SetAttribute("DepthStratum", idx)
	plr:SetAttribute("DepthStratumName", DS.theme(zid, idx).name)
end

----------------------------------------------------------------------
-- per-frame
----------------------------------------------------------------------
local settled, nextSweep = 0, 0
RunService.Heartbeat:Connect(function()
	local cam = workspace.CurrentCamera
	if not cam or not state then return end
	-- keep sweeping for the first 10 seconds: that covers late replication and anything
	-- ZonesController re-enables on its own join pass
	hidePainted()
	-- the folders replicate late, so keep re-collecting for the first few seconds
	if settled < 12 and os.clock() > nextSweep then
		nextSweep = os.clock() + 1
		settled += 1
		takeOver()
	end
	local camY = cam.CFrame.Position.Y
	-- Set_WaterFX freezes the MOTION but leaves the scenery standing: the structure IS
	-- the environment, so hiding it would delete the feature rather than cheapen it.
	local idx = DS.step(state, camY, os.clock(), fx.water, true)
	publish(idx, state.zone)
end)

----------------------------------------------------------------------
-- dev hook, same convention as DevZone / DevRoll / DevStrata: MCP cannot click, and
-- the deep bands are hundreds of studs down where no screenshot reaches.
--   :Fire(<zoneId>)  rebuild the column with that zone
----------------------------------------------------------------------
local dev = root:FindFirstChild("DevScenery") or Instance.new("BindableEvent")
dev.Name = "DevScenery"
dev.Parent = root
dev.Event:Connect(function(arg)
	if type(arg) == "number" then rebuild(arg) end
end)

print(string.format("[Scenery3D] online - zone %d, %d parts, %s -> %s",
	state.zone, state.count, DS.theme(state.zone, 1).name, DS.theme(state.zone, 5).name))
