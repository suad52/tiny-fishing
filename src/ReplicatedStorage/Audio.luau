--[[
	Audio — the one place anything in this game asks for a sound.

	The clips themselves live in SoundService.GameAudio/<Bus>/<Name> and are already
	routed to the SoundGroup bus that SettingsController's volume sliders drive
	(Master > Music/SFX/UI/Ambient), so nothing here needs to know about volume
	settings or muting — turning a slider down turns these down with it.

	EVERY PLAY IS A CLONE. Calling :Play() on the template restarts the one shared
	instance, so two fish caught 80ms apart would cut each other off; a clone per
	shot lets them overlap and lets each carry its own pitch. The clone is parented
	to SoundService (not to a part) because this is all 2D UI/loop audio — a Sound
	under a BasePart becomes positional and gets quiet when the camera moves.

		Audio.play("Splash", { pitch = 1.1, volume = 0.8 })
		Audio.startLoop("ReelLoop")  /  Audio.stopLoop("ReelLoop", 0.25)
		Audio.music("Zone3")         -- crossfades from whatever was playing
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris       = game:GetService("Debris")

local Audio = {}

local lib = SoundService:WaitForChild("GameAudio", 20)

-- Names are unique across the buses, so callers say "Splash", not "SFX.Splash" —
-- which bus a clip sits on is a mixing decision, not something call sites should care
-- about. Resolved once and cached; a miss is cached as false so a typo doesn't rescan
-- the whole library on every frame of a render loop.
local cache = {}
local function find(name)
	local hit = cache[name]
	if hit ~= nil then return hit or nil end
	if not lib then cache[name] = false; return nil end
	for _, bus in ipairs(lib:GetChildren()) do
		local s = bus:FindFirstChild(name)
		if s and s:IsA("Sound") then cache[name] = s; return s end
	end
	cache[name] = false
	return nil
end

-- A clip that hasn't streamed in yet reports TimeLength 0, so the cleanup delay falls
-- back to a few seconds rather than destroying the clone before it makes a sound.
local function lifetime(s)
	local len = (s.TimeLength > 0) and s.TimeLength or 4
	return len / math.max(s.PlaybackSpeed, 0.05) + 0.5
end

function Audio.play(name, opts)
	local tpl = find(name)
	if not tpl then return nil end
	opts = opts or {}
	local s = tpl:Clone()
	s.Looped = false
	if opts.pitch  then s.PlaybackSpeed = opts.pitch end
	if opts.volume then s.Volume = tpl.Volume * opts.volume end
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, lifetime(s))
	return s
end

----------------------------------------------------------------------
-- loops
----------------------------------------------------------------------
-- Keyed by name, so startLoop is idempotent: the reel calling it every frame it is
-- reeling is a no-op after the first, which keeps the call sites free of "did I
-- already start this" bookkeeping.
local loops = {}

function Audio.startLoop(name, volume)
	local live = loops[name]
	if live and live.Parent then return live end
	local tpl = find(name)
	if not tpl then return nil end
	local s = tpl:Clone()
	s.Looped = true
	s.Volume = tpl.Volume * (volume or 1)
	s.Parent = SoundService
	s:Play()
	loops[name] = s
	return s
end

function Audio.stopLoop(name, fade)
	local s = loops[name]
	if not s then return end
	loops[name] = nil
	if fade and fade > 0 then
		-- fade rather than cut: a reel loop stopping dead is more noticeable than the
		-- sound itself, and Debris cleans up the faded-out clone
		TweenService:Create(s, TweenInfo.new(fade), { Volume = 0 }):Play()
		Debris:AddItem(s, fade + 0.2)
	else
		s:Destroy()
	end
end

----------------------------------------------------------------------
-- music
----------------------------------------------------------------------
local current, currentName = nil, nil

-- Crossfade. Guarded on the name so re-asserting the current track (which the zone
-- watcher does on every CurrentZone write, including redundant ones) doesn't restart it.
function Audio.music(name, fade)
	if currentName == name then return end
	currentName = name
	fade = fade or 1.4

	local old = current
	if old then
		TweenService:Create(old, TweenInfo.new(fade), { Volume = 0 }):Play()
		Debris:AddItem(old, fade + 0.3)
	end

	local tpl = name and find(name)
	if not tpl then current = nil; return end
	local s = tpl:Clone()
	s.Looped = true
	s.Volume = 0
	s.Parent = SoundService
	s:Play()
	TweenService:Create(s, TweenInfo.new(fade), { Volume = tpl.Volume }):Play()
	current = s
end

function Audio.currentMusic() return currentName end

return Audio
