--[==[
	BoatClient - owns which boat you are sailing, and swaps the hull in the world.

	CLIENT-SIDE, ON PURPOSE. Same call the Zones system makes: the stage is rendered per
	player, so each player sees their own boat without a remote or any server authority.
	The one thing that CANNOT be per-player is the seat - `Workspace.Rowboat.RowSeat` is a
	single server-owned instance that FishingServer sits everyone on - so every hull in
	BoatData is authored around that fixed point instead. Nothing here ever moves it.

	WHAT IT WRITES
	  Boat_<id>     bool   - do you own tier <id>?  (Boat_1 is forced true)
	  CurrentBoat   number - the tier you are sailing. THIS is the input: set it and this
	                         script does the rest. BoatsController never touches the world.
	  BoatCoinMult / BoatCap / BoatLuck / BoatReelMult / BoatDepth
	                       - the stat payload GameClient folds into its existing chains.
	  BoatLandY / BoatLandX0 / BoatLandX1
	                       - where a paid-out fish is thrown, per hull. A bigger boat has a
	                         higher deck and a longer open well, and the fish has to land
	                         BELOW the near gunwale or it never disappears.
	  BoatName / BoatSpan  - for the HUD and for debugging.

	HIDING TIER 1. The rowboat is authored, server-replicated and 537 instances deep, so it
	is hidden by remembering and restoring each part's own Transparency rather than by
	reparenting or destroying - a destroyed instance could not be brought back when the
	player sails home to the rowboat, and reparenting a replicated instance from the client
	is asking for trouble. RowSeat is deliberately skipped: it belongs to the server.

	Built hulls are cached OUTSIDE Workspace so the seven you are not sailing cost nothing
	to render, and they are built LAZILY - a player who never buys a boat never pays for
	one. Nothing here persists across sessions (neither does money, or zones).
]==]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local plr = Players.LocalPlayer

local BoatData    = require(ReplicatedStorage:WaitForChild("BoatData"))
local BoatBuilder = require(ReplicatedStorage:WaitForChild("BoatBuilder"))

----------------------------------------------------------------------
-- cache
----------------------------------------------------------------------
-- A client-only folder outside Workspace: instances in here are in the DataModel but not
-- in the render pipeline, so seven spare hulls (~2000 parts total) cost nothing per frame.
local cache = ReplicatedStorage:FindFirstChild("BoatCache")
if not cache then
	cache = Instance.new("Folder")
	cache.Name = "BoatCache"
	cache.Parent = ReplicatedStorage
end

local built = {}
local function modelFor(id)
	if built[id] and built[id].Parent then return built[id] end
	local t = BoatData.get(id)
	-- `authored` tiers are already in the world (tier 1's rowboat). It carries a hull spec
	-- purely so the menu can draw a likeness of it, and building that into Workspace would
	-- put a second, worse rowboat on top of the real one.
	if t.authored or not t.hull then return nil end
	local ok, m = pcall(BoatBuilder.build, t)
	if not ok or not m then
		warn("[BoatClient] could not build tier " .. tostring(id) .. ": " .. tostring(m))
		return nil
	end
	m.Parent = cache
	built[id] = m
	return m
end

----------------------------------------------------------------------
-- the authored tier-1 rowboat
----------------------------------------------------------------------
local rowboat = workspace:WaitForChild("Rowboat")
local seat    = rowboat:WaitForChild("RowSeat")

-- Read BEFORE anything can move it: the rocking section at the bottom writes this
-- Seat's CFrame every frame, and it needs the authored pose to rock around.
local seatBase = seat.CFrame
-- Whichever hull is actually in the world and visible right now - the authored
-- rowboat on tier 1, a built model otherwise. applyBoat is the only writer.
local activeHull = nil

local origT = {}          -- instance -> its own authored Transparency
local tier1Visible = true

local function applyHide(d)
	if d == seat then return end
	if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
		if origT[d] == nil then origT[d] = d.Transparency end
		d.Transparency = tier1Visible and origT[d] or 1
	end
end

local function setTier1(visible)
	tier1Visible = visible
	for _, d in ipairs(rowboat:GetDescendants()) do applyHide(d) end
end

-- Parts can still be replicating in when this script first runs, and a part that arrives
-- after the hide pass would pop back into frame on top of a tier-8 factory ship.
rowboat.DescendantAdded:Connect(function(d)
	task.defer(applyHide, d)
end)

----------------------------------------------------------------------
-- apply
----------------------------------------------------------------------
local function applyBoat(id)
	id = math.clamp(tonumber(id) or 1, 1, BoatData.MAX_TIER)
	local t = BoatData.get(id)

	-- stats first, so a menu that reads them right after setting CurrentBoat is correct
	plr:SetAttribute("BoatCoinMult", t.coin)
	plr:SetAttribute("BoatCap",      t.cap)
	plr:SetAttribute("BoatLuck",     t.luck)
	plr:SetAttribute("BoatReelMult", t.reel)
	plr:SetAttribute("BoatDepth",    t.depth)
	plr:SetAttribute("BoatName",     t.name)
	plr:SetAttribute("BoatSpan",     t.span)
	plr:SetAttribute("BoatLandY",    t.land.y)
	plr:SetAttribute("BoatLandX0",   t.land.x0)
	plr:SetAttribute("BoatLandX1",   t.land.x1)

	-- visual: park every other built hull, then show this one
	for tier, m in pairs(built) do
		if tier ~= id and m.Parent ~= cache then m.Parent = cache end
	end

	if id == 1 then
		setTier1(true)
		activeHull = rowboat
	else
		local m = modelFor(id)
		if m then
			m.Parent = workspace
			setTier1(false)
			activeHull = m
		else
			-- Build failed: never leave the player on an invisible boat. Fall the STATS back
			-- too - the tier-8 landing box on a rowboat throws every paid-out fish clear of
			-- the rim, where the player watches it despawn in mid-air.
			setTier1(true)
			activeHull = rowboat
			local t1 = BoatData.get(1)
			plr:SetAttribute("BoatLandY",  t1.land.y)
			plr:SetAttribute("BoatLandX0", t1.land.x0)
			plr:SetAttribute("BoatLandX1", t1.land.x1)
		end
	end
end

----------------------------------------------------------------------
-- state
----------------------------------------------------------------------
plr:SetAttribute("Boat_1", true)              -- the rowboat is always yours
if plr:GetAttribute("CurrentBoat") == nil then plr:SetAttribute("CurrentBoat", 1) end

-- Sailing a boat you do not own is not a state the menu can produce, but an attribute is
-- writable by anything, so fall back rather than trust it.
-- It WRITES THE DEMOTION BACK. Silently sailing tier 1 while CurrentBoat still says 8
-- would leave BoatsController's header claiming "Sailing: Abyssal Factory Ship" next to a
-- card rendered LOCKED, with the world matching neither - and nothing would ever
-- reconcile it, because this script only listens to CurrentBoat.
local function currentOwned()
	local raw = tonumber(plr:GetAttribute("CurrentBoat")) or 1
	if raw ~= raw then raw = 1 end                        -- NaN
	local id = math.clamp(math.floor(raw), 1, BoatData.MAX_TIER)
	if id > 1 and plr:GetAttribute("Boat_" .. id) ~= true then id = 1 end
	-- not before the save has loaded: this script starts at join, before SaveServer restores Boat_<n>, and writing
	-- the demotion back then would turn a saved CurrentBoat of 5 into 1 for good
	if id ~= plr:GetAttribute("CurrentBoat") and plr:GetAttribute("DataLoaded") == true then
		plr:SetAttribute("CurrentBoat", id)
	end
	return id
end

plr:GetAttributeChangedSignal("CurrentBoat"):Connect(function()
	applyBoat(currentOwned())
end)
-- the save has landed: sail the boat it restored
plr:GetAttributeChangedSignal("DataLoaded"):Connect(function()
	applyBoat(currentOwned())
end)

applyBoat(currentOwned())

----------------------------------------------------------------------
-- rocking on the swell
----------------------------------------------------------------------
-- The boat used to sit dead flat on a sea whose entire point is that it undulates
-- (SeaFX's wave ribbon IS the visible waterline). This rides it: the hull samples
-- ReplicatedStorage.SeaWave at the world x of its own two ends and takes HEAVE from
-- their average and PITCH from their difference, which is the real slope of the
-- water under this particular hull.
--
-- Nothing here is tuned per tier and that is the point. A 15-stud rowboat spans a
-- good fraction of a wavelength and gets tossed (~2.8 deg measured); a 33-stud
-- factory ship bridges several crests, so the ends cancel and it barely tilts
-- (~1 deg) while heaving more. Big boats riding steadier falls out of the sampling
-- for free - a sine per tier would have to fake it, and would fake it wrong.
--
-- THE SEAT COMES WITH IT. RowSeat is the fixed point every hull is authored around,
-- so a hull rocking under a seat that does not leaves the angler hovering bolt
-- upright off the deck. Moving the Seat carries the seated character - and with it
-- the rod, which is welded to the arm - because the SeatWeld drags the assembly.
-- This is a client-only write to a server-owned anchored part, so it never
-- replicates, and FishingServer goes on reading the seat's authored server CFrame
-- for its re-seat rescue. That is the behaviour you want: being put back in the
-- boat should drop you on the authored spot, not on whatever phase of the swell
-- this client happened to be rendering.
--
-- The pivot is the authored hull point (the waterline UNDER the seat), not the hull
-- centre, so pitch moves the angler as little as it can: the rod tip and the cast
-- origin are solved off the character, and every stud they wander is a stud of aim
-- the player did not ask for.
local RunService = game:GetService("RunService")
local SeaWave    = require(ReplicatedStorage:WaitForChild("SeaWave"))

-- The frame every hull in BoatData is authored around, carrying the same -30 yaw
-- the authored rowboat has.
local HULL_CF  = CFrame.new(3.7295, 0, 2.400) * CFrame.Angles(0, math.rad(-30), 0)
local HULL_INV = HULL_CF:Inverse()
-- Local +X maps to world (0.866, 0, 0.5), so a keel of length L spans only 0.866*L
-- of the world X the wave is a function of. Converting back is what makes the tilt
-- the slope along the KEEL rather than along the screen.
local X_PER_KEEL = math.cos(math.rad(30))

-- Readability multipliers over the true surface slope. The honest numbers are ~2.8
-- deg of pitch and 0.2 studs of heave on the rowboat, and under 1 deg on the
-- longest hulls: correct, but at ~11 px/stud on screen the heave especially reads
-- as nothing at all. These lift it to something visible without turning a fishing
-- boat into a fairground ride. MAX_PITCH is the backstop if the swell is ever
-- retuned upward - the wave is shared now, so it can be.
local PITCH_GAIN = 1.8
local HEAVE_GAIN = 2.2
local MAX_PITCH  = math.rad(7)

local rockBase = {}     -- model -> { pivot = CFrame, x0 = number, x1 = number }
local lastHull = nil
local rocking  = false

-- Exact world-X extent, measured ONCE per hull. A per-frame Model:GetBoundingBox is
-- a full descendant walk, and that is what cost the boat previews 20 fps; this is
-- the same trap and the same fix.
local function measure(m)
	local x0, x1 = math.huge, -math.huge
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf, s = d.CFrame, d.Size
			local hx = 0.5 * (math.abs(cf.RightVector.X) * s.X
				+ math.abs(cf.UpVector.X) * s.Y
				+ math.abs(cf.LookVector.X) * s.Z)
			local cx = cf.Position.X
			if cx - hx < x0 then x0 = cx - hx end
			if cx + hx > x1 then x1 = cx + hx end
		end
	end
	return x0, x1
end

local function baseOf(m)
	local b = rockBase[m]
	if not b then
		local x0, x1 = measure(m)
		if x0 >= x1 then return nil end            -- no parts yet; try again next frame
		b = { pivot = m:GetPivot(), x0 = x0, x1 = x1 }
		rockBase[m] = b
	end
	return b
end

-- Put a hull back on its authored lines. A hull parked in the cache mid-roll would
-- otherwise sit there tilted and come back tilted for the one frame before the loop
-- catches up with it.
local function rest(m)
	local b = m and rockBase[m]
	if b then m:PivotTo(b.pivot) end
end

local function rockStep()
	local m = activeHull
	if m ~= lastHull then
		rest(lastHull)
		lastHull = m
	end
	if not (m and m.Parent) then return end
	local b = baseOf(m)
	if not b then return end
	local t = os.clock()
	local h0 = SeaWave.heightAt(b.x0, t)
	local h1 = SeaWave.heightAt(b.x1, t)
	local heave = ((h0 + h1) * 0.5 - SeaWave.BASE) * HEAVE_GAIN
	-- x1 is the world-x-max end, which is local +X, and CFrame.Angles(0, 0, p) lifts
	-- local +X: a crest under that end is a POSITIVE pitch.
	local pitch = math.atan((h1 - h0) * X_PER_KEEL / (b.x1 - b.x0)) * PITCH_GAIN
	pitch = math.clamp(pitch, -MAX_PITCH, MAX_PITCH)
	local delta = CFrame.new(0, heave, 0) * HULL_CF * CFrame.Angles(0, 0, pitch) * HULL_INV
	m:PivotTo(delta * b.pivot)
	-- Redundant on tier 1 (the seat is a descendant of the rowboat, so PivotTo has
	-- already landed it exactly here) and load-bearing on every other tier, where the
	-- hull that moved is a built model the seat is not part of.
	seat.CFrame = delta * seatBase
end

-- Set_WaterFX off means SeaFX hides the ribbon and restores the flat foam strip -
-- the sea genuinely IS flat then, so a boat rocking on it is rocking on nothing.
-- Same live re-read on change that SeaFX does.
local function setRocking(v)
	if v == rocking then return end
	rocking = v
	if not v then
		rest(activeHull)
		seat.CFrame = seatBase
	end
end
plr:GetAttributeChangedSignal("Set_WaterFX"):Connect(function()
	setRocking(plr:GetAttribute("Set_WaterFX") ~= false)
end)

-- Deliberately delayed. The rowboat is 347 replicated parts and DescendantAdded is
-- still firing on join; PivotTo carries whatever is in the model at the time, so a
-- part landing mid-roll would be carried from its authored pose by the wrong delta
-- and sit permanently offset. Two seconds is well past replication, and a boat that
-- holds still for the first moment of a session reads as nothing at all.
task.delay(2, function()
	setRocking(plr:GetAttribute("Set_WaterFX") ~= false)
	RunService.Heartbeat:Connect(function()
		if rocking then rockStep() end
	end)
end)

print(string.format("[BoatClient] online - %d tiers, sailing #%d (%s)",
	BoatData.MAX_TIER, currentOwned(), tostring(plr:GetAttribute("BoatName"))))
