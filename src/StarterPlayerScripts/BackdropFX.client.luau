local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local plr        = Players.LocalPlayer

local TAU = math.pi * 2

local function rootsFor(id)
	local roots = {}
	local function collect(folder)
		if not folder then return end
		for _, p in ipairs(folder:GetChildren()) do
			local sg = p:FindFirstChildWhichIsA("SurfaceGui")
			local r  = sg and sg:FindFirstChild("Root")
			if r then
				local pps = sg.PixelsPerStud
				roots[#roots + 1] = { r = r, H = p.Size.Y * pps, W = p.Size.X * pps }
			end
		end
	end
	if id == 1 then
		local z1 = workspace:FindFirstChild("Zone1")
		collect(z1 and z1:FindFirstChild("Horizon"))
	else
		local bd = workspace:FindFirstChild("ZoneBackdrops")
		collect(bd and bd:FindFirstChild("Zone" .. id))
	end
	return roots
end

local fxList = {}
local function num(o, k, d) local v = o:GetAttribute(k); if v == nil then return d end return v end

local function rescan()
	table.clear(fxList)
	local id = plr:GetAttribute("CurrentZone") or 1
	for _, rr in ipairs(rootsFor(id)) do
		for _, d in ipairs(rr.r:GetDescendants()) do
			local kind = d:GetAttribute("FX")
			if kind then
				fxList[#fxList + 1] = {
					o = d, k = kind, H = rr.H, W = rr.W,
					spd = num(d, "spd", 5), rate = num(d, "rate", 1), ph = num(d, "ph", 0),
					amp = num(d, "amp", 0.2), a0 = d:GetAttribute("a0"), d0 = d:GetAttribute("d0"),
					vy = num(d, "vy", 30), sp = num(d, "sp", 1), sway = num(d, "amp", 10),
					bx = num(d, "bx", d.Position.X.Offset), by = num(d, "by", d.Position.Y.Offset),
					bob = num(d, "bob", 5),
					fx = d.Position.X.Offset, fy = d.Position.Y.Offset,
				}
			end
		end
	end
end

plr:GetAttributeChangedSignal("CurrentZone"):Connect(rescan)
task.defer(rescan)

RunService.Heartbeat:Connect(function(dt)
	local t = os.clock()
	for _, e in ipairs(fxList) do
		local o = e.o
		if o.Parent then
			local k = e.k
			if k == "cloud" then
				e.fx = e.fx + e.spd * dt
				if e.fx > e.W + 150 then e.fx = -150 end
				o.Position = UDim2.new(0, e.fx, 0, e.fy)
			elseif k == "bird" then
				e.fx = e.fx + e.spd * dt
				if e.fx > e.W + 90 then e.fx = -90 end
				o.Position = UDim2.new(0, e.fx, 0, e.by + e.bob * math.sin(t * 1.6 + e.ph))
			elseif k == "star" then
				o.BackgroundTransparency = math.clamp((e.a0 or 0) + 0.5 * (0.5 + 0.5 * math.sin(t * e.rate + e.ph)), 0, 1)
			elseif k == "snow" then
				e.fy = e.fy + e.vy * dt
				if e.fy > e.H + 10 then e.fy = -10 end
				o.Position = UDim2.new(0, e.bx + e.sway * math.sin(t * e.sp + e.ph), 0, e.fy)
			elseif k == "ember" then
				e.fy = e.fy + e.vy * dt
				if e.fy < -10 then e.fy = e.H + 10 end
				o.Position = UDim2.new(0, e.bx + e.sway * math.sin(t * e.sp + e.ph), 0, e.fy)
			elseif k == "glow" then
				local osc = 0.5 + 0.5 * math.sin(t * e.rate * TAU * 0.25 + e.ph)
				if e.d0 then
					local d = e.d0 * (1 + 0.05 * math.sin(t * e.rate * TAU * 0.25 + e.ph))
					o.Size = UDim2.fromOffset(d, d)
				elseif e.a0 then
					o.BackgroundTransparency = math.clamp(e.a0 - e.amp * osc, 0, 1)
				end
			elseif k == "shoot" then
				local phase = (t * 0.16 + e.ph) % 1
				if phase < 0.12 then
					local fr = phase / 0.12
					o.BackgroundTransparency = 0.1 + 0.85 * fr
					o.Position = UDim2.fromOffset(e.bx + fr * e.W * 0.134, e.by + fr * e.H * 0.3125)
				else
					o.BackgroundTransparency = 1
				end
			end
		end
	end
end)

print(string.format("[BackdropFX] online -- %d animated elements on zone %d", #fxList, plr:GetAttribute("CurrentZone") or 1))
