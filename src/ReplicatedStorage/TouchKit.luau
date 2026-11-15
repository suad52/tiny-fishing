--[==[
	TouchKit — a 44px hit area under every control, WITHOUT resizing any art.

	WHY. Every menu in this game is authored against a ~1100x680 design window and then
	shrunk to fit by a UIScale: `clamp(min(vw/(W+50), vh/(H+50)), 0.4, 1.1)`. On an
	812x375 phone that lands around 0.5-0.67, so a 40px close button renders at 20-27px.
	Measured on the simulated device matrix: 143 distinct clickable controls fall under the
	44px touch floor on a phone, and 60+ still do on an iPad. The ROLL button — the bait
	roller's primary action — is 134x29. The close X on most windows is 24-27px square.

	WHAT THIS DOES. A GuiButton's clickable region IS its rect; Roblox has no hit-slop
	property. So the only way to widen the target without widening the art is a second,
	invisible button underneath: the "pad". Transparent, sized to 44 / chainScale in
	unscaled offset so it lands at 44 REAL pixels, centred on the control.

	WHAT THIS DOES NOT DO. It does not fix legibility. 6pt text is still 6pt text. The
	aspect-aware window fit (see each controller's fit()) is what addresses that.

	THREE THINGS THAT ARE EASY TO GET WRONG, all learned the hard way:

	1. NEVER decide "is this already big enough?" at wiring time. A panel builds at
	   whatever scale is current and the window's UIScale is applied to the tree it is
	   already inside — but the menu's fit() runs again on open and on rotate. Every
	   judgement has to come from LIVE AbsoluteSize, re-made on AbsoluteSize changes.

	2. A pad CANNOT forward to the button it serves. There is no way to fire a GuiButton's
	   Activated from a script. So the pad has to be wired to the SAME handler, which is
	   why the API is `TouchKit.press(btn, fn)` replacing `btn.MouseButton1Click:Connect(fn)`.

	3. Pad parenting is not a free choice — it is a search up the tree. See hostFor() for
	   the two properties that disqualify an ancestor (a layout would lay the pad out; an
	   AutomaticSize one would grow around it, forever). The pad always sorts BELOW the
	   subtree it serves, which is the whole safety argument for letting it be generous: it
	   can only ever catch a tap that would otherwise hit nothing.

	4. And it must never reach a NEIGHBOURING control — see neighbourLimits(). Where a row
	   is too dense for 44px the pad simply grows less. A short pad is a worse target; a
	   greedy one fires the wrong button, which is not a trade worth making.

	Pads are TOUCH-ONLY (see wanted() below). Nothing about a desktop client changes.
]==]

local UserInputService = game:GetService("UserInputService")
local Players          = game:GetService("Players")

local TouchKit = {}

local TARGET      = 44   -- Apple/Google minimum touch target, in real screen pixels
local MAX_GROWTH  = 4    -- a 1px control must not be allowed to claim a minefield
local PAD_NAME    = "__TouchPad"

-- Sibling pads need unique names so two controls in the same parent do not collide.
-- (GetDebugId is not callable from a LocalScript, hence a plain counter.)
local padSeq = 0
local padOf = setmetatable({}, { __mode = "k" })

----------------------------------------------------------------------
-- is this a touch-primary device?
----------------------------------------------------------------------
-- TouchEnabled alone is true on touchscreen laptops, where the mouse is the real pointer
-- and the hover feedback is worth keeping; MouseEnabled is false on a real phone/tablet.
--
-- Studio's Device Emulator reports BOTH as true, so this branch cannot be exercised there.
-- TEST HOOK, in the same spirit as the DevZone / DevRoll / DevCast BindableEvents this
-- codebase already uses: set the attribute "ForceTouchUI" on ReplicatedStorage (in Studio,
-- so it is in the place file and has replicated before any LocalScript runs) and every
-- client behaves as if it were a phone. Nothing in the game ever writes it.
local forced = nil
function TouchKit.wanted()
	if forced ~= nil then return forced end
	if game:GetService("ReplicatedStorage"):GetAttribute("ForceTouchUI") == true then return true end
	local plr = Players.LocalPlayer
	if plr and plr:GetAttribute("ForceTouchUI") == true then return true end
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- test hook: TouchKit.force(true) / TouchKit.force(nil)
function TouchKit.force(v) forced = v end

----------------------------------------------------------------------
-- internals
----------------------------------------------------------------------

-- product of every UIScale from `obj` up to (and including) the ScreenGui.
-- The pad is sized in the control's OWN parent space, so it has to divide the target
-- by however much that space is being scaled down.
local function chainScale(obj)
	local s, n = 1, obj
	while n and not n:IsA("LayerCollector") do
		if n:IsA("GuiObject") then
			local us = n:FindFirstChildOfClass("UIScale")
			if us then s *= us.Scale end
		end
		n = n.Parent
	end
	return s > 0 and s or 1
end

local function layoutOf(o)
	return o:FindFirstChildOfClass("UIListLayout")
		or o:FindFirstChildOfClass("UIGridLayout")
		or o:FindFirstChildOfClass("UITableLayout")
		or o:FindFirstChildOfClass("UIPageLayout")
end

-- WHERE THE PAD GOES. Not a free choice, and the two disqualifying properties are the
-- reason this is a search up the tree rather than "the control's parent":
--
--   * a UIListLayout / UIGridLayout parent would LAY THE PAD OUT as another list item and
--     shove the whole row along;
--   * an AutomaticSize ancestor RESIZES ITSELF AROUND ITS CHILDREN, so a pad placed inside
--     one makes it grow, the pad re-measures against the bigger parent and grows again.
--     That is not theoretical: parenting pads inside the AutomaticSize tab chips took six
--     menus' tabs to between 90,000 and 530,000 pixels wide within a second.
--
-- So the pad goes in the nearest ancestor that does neither, and sorts below `anchor` -
-- the child of that ancestor which contains the control - so it is underneath the entire
-- row rather than competing inside it. A non-Active Frame does not consume input, so
-- sitting behind the row's decoration still leaves the pad reachable.
local function hostFor(btn)
	local anchor, host = btn, btn.Parent
	while host and host:IsA("GuiObject") do
		if not layoutOf(host) and host.AutomaticSize == Enum.AutomaticSize.None then
			return host, anchor
		end
		anchor, host = host, host.Parent
	end
	return nil, nil   -- nothing safe all the way to the ScreenGui: no pad
end

-- THE RULE THAT MAKES A PAD SAFE: it may never reach a NEIGHBOURING control.
--
-- A sibling pad sorts underneath its control (ZIndex - 1) so it can only catch taps that
-- would otherwise hit nothing. An INSIDE pad cannot: every ScreenGui here is
-- ZIndexBehavior.Sibling, under which a child always draws above its parent AND a later
-- sibling's whole subtree draws above an earlier one's. So in a row of five 19px stars,
-- star 5's 44px pad renders on top of star 4 - and tapping star 4 would set rating 5.
-- Measured, not theorised: GetGuiObjectsAtPosition caught exactly that on the Feedback
-- menu's star row and on the Shop's featured buttons.
--
-- So every side of the pad stops at the midpoint of the gap to the nearest neighbouring
-- control. Where a row is too dense to reach 44px the pad simply grows less, and the
-- coverage report says so - which is the honest outcome, not a silent mis-tap.
local function neighbourLimits(btn)
	local p = btn.Parent
	local x1, y1 = btn.AbsolutePosition.X, btn.AbsolutePosition.Y
	local x2, y2 = x1 + btn.AbsoluteSize.X, y1 + btn.AbsoluteSize.Y
	local L, R, T, B = -math.huge, math.huge, -math.huge, math.huge
	if not p then return L, R, T, B end
	for _, c in ipairs(p:GetChildren()) do
		if c ~= btn and c:IsA("GuiButton") and c.Visible and c.Name:sub(1, #PAD_NAME) ~= PAD_NAME then
			local a1, b1 = c.AbsolutePosition.X, c.AbsolutePosition.Y
			local a2, b2 = a1 + c.AbsoluteSize.X, b1 + c.AbsoluteSize.Y
			if b1 < y2 and b2 > y1 then                      -- overlaps vertically: limits X
				if a1 >= x2 then R = math.min(R, (x2 + a1) / 2)
				elseif a2 <= x1 then L = math.max(L, (a2 + x1) / 2) end
			end
			if a1 < x2 and a2 > x1 then                      -- overlaps horizontally: limits Y
				if b1 >= y2 then B = math.min(B, (y2 + b1) / 2)
				elseif b2 <= y1 then T = math.max(T, (b2 + y1) / 2) end
			end
		end
	end
	return L, R, T, B
end

-- Grow [lo, hi] outwards by `want` on each side without crossing [limLo, limHi]. Slack on
-- a blocked side is handed to the other one, so an end-of-row control still gets its 44px.
local function grow(lo, hi, want, limLo, limHi)
	local target = (hi - lo) + want * 2
	local nlo = math.max(limLo, lo - want)
	local nhi = math.min(limHi, hi + want)
	local short = target - (nhi - nlo)
	if short > 0 then
		local take = math.min(short, limHi - nhi); nhi += take; short -= take
		nlo -= math.min(short, nlo - limLo)
	end
	return nlo, nhi
end

-- Size + position the pad so it reaches TARGET real pixels where the layout allows it.
local function layoutPad(btn, pad, host)
	local sz, pos = btn.AbsoluteSize, btn.AbsolutePosition
	if sz.X < 0.5 or sz.Y < 0.5 then pad.Visible = false; return false end
	if sz.X >= TARGET and sz.Y >= TARGET then pad.Visible = false; return false end
	-- A HIDDEN control keeps its AbsoluteSize, so a window re-fit (open pop, rotate) re-ran this
	-- and switched its pad back on: an invisible live tap target (measured by InventoryMenu on an
	-- owned rod's hidden Robux button). The pad lives in HOST, outside the control, so it never
	-- inherits the control's own Visible.
	if not btn.Visible then pad.Visible = false; return false end

	-- The pad's offsets live in HOST's space, so they are divided by the UIScale chain above
	-- HOST - not the one above the button, which would also include the button's own UIScale
	-- (several controls here carry one for their press/pop tween).
	local scale = chainScale(host)
	local x1, y1 = pos.X, pos.Y
	local x2, y2 = x1 + sz.X, y1 + sz.Y
	local wantX = math.max(0, (TARGET - sz.X) / 2)
	local wantY = math.max(0, (TARGET - sz.Y) / 2)
	-- MAX_GROWTH still applies: a 1px control must not claim a minefield
	wantX = math.min(wantX, sz.X * (MAX_GROWTH - 1) / 2)
	wantY = math.min(wantY, sz.Y * (MAX_GROWTH - 1) / 2)

	local L, R, T, B = neighbourLimits(btn)
	local nx1, nx2 = grow(x1, x2, wantX, L, R)
	local ny1, ny2 = grow(y1, y2, wantY, T, B)

	-- back into the pad's own parent space, undoing the UIScale chain
	local hAbs = host and host.AbsolutePosition or Vector2.zero
	pad.Visible = true
	pad.AnchorPoint = Vector2.new(0, 0)
	pad.Position = UDim2.fromOffset(math.floor((nx1 - hAbs.X) / scale + 0.5), math.floor((ny1 - hAbs.Y) / scale + 0.5))
	pad.Size = UDim2.fromOffset(math.max(1, math.floor((nx2 - nx1) / scale + 0.5)), math.max(1, math.floor((ny2 - ny1) / scale + 0.5)))
	return true
end

----------------------------------------------------------------------
-- public
----------------------------------------------------------------------

-- Give `btn` a 44px hit area. Safe to call twice.
--
-- The pad INSTANCE is created lazily, the first time the control is actually measured too
-- small. That matters: press() is called on ~450 controls, most of which are grid tiles
-- that never need one, and a pad that is never needed should not exist. What is NOT lazy
-- is the DECISION - it is re-made on every AbsoluteSize change, because a control that is
-- big enough now is not big enough after the window's fit() runs again on open or rotate.
-- (Deciding once, at wiring time, is the classic version of this bug.)
function TouchKit.pad(btn)
	if not TouchKit.wanted() then return nil end
	if not (btn and btn:IsA("GuiButton")) then return nil end
	if padOf[btn] then return padOf[btn] end

	local host, anchor = hostFor(btn)
	if not host then return nil end
	local pad, handlers = nil, {}

	local function ensure()
		if pad then return pad end
		pad = Instance.new("TextButton")
		padSeq += 1
		pad.Name = PAD_NAME .. padSeq
		pad.Text = ""
		pad.AutoButtonColor = false
		pad.BackgroundTransparency = 1
		pad.BorderSizePixel = 0
		pad.Visible = false
		-- Strictly BELOW the subtree it serves. Not clamped to 1: most of the Shop's rows sit
		-- at ZIndex 1, and clamping tied them with their own pad, which then sorted on top by
		-- child order and swallowed the control's hover feedback. ZIndex may go to 0 and below.
		pad.ZIndex = anchor.ZIndex - 1
		pad.Parent = host
		for _, fn in ipairs(handlers) do pad.MouseButton1Click:Connect(fn) end
		btn.Destroying:Connect(function() if pad and pad.Parent then pad:Destroy() end end)
		return pad
	end

	local function relayout()
		local sz = btn.AbsoluteSize
		if not pad then
			if sz.X < 0.5 or sz.Y < 0.5 then return end
			if sz.X >= TARGET and sz.Y >= TARGET then return end   -- not needed yet
			ensure()
		end
		layoutPad(btn, pad, host)
	end

	local handle = {
		connect = function(fn)
			table.insert(handlers, fn)
			if pad then pad.MouseButton1Click:Connect(fn) end
		end,
	}
	padOf[btn] = handle

	relayout()
	btn:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	btn:GetPropertyChangedSignal("AbsolutePosition"):Connect(function() if pad then relayout() end end)
	btn:GetPropertyChangedSignal("Visible"):Connect(function()
		if pad and not btn.Visible then pad.Visible = false elseif btn.Visible then relayout() end
	end)
	return handle
end

-- Drop-in for `btn.MouseButton1Click:Connect(fn)`. The closing bracket lands in the same
-- place, which is what makes this a safe mechanical substitution across the codebase.
function TouchKit.press(btn, fn)
	if not (btn and btn:IsA("GuiButton")) then return nil end
	local conn = btn.MouseButton1Click:Connect(fn)
	local handle = TouchKit.pad(btn)
	if handle then handle.connect(fn) end
	return conn
end

-- Kept SEPARATE from press on purpose: Activated also fires for gamepad and keyboard, and
-- hands (inputObject, clickCount) where MouseButton1Click hands (x, y).
function TouchKit.activated(btn, fn)
	if not (btn and btn:IsA("GuiButton")) then return nil end
	local conn = btn.Activated:Connect(fn)
	-- Activated hands (inputObject, clickCount) where MouseButton1Click hands (x, y), so the
	-- pad's own MouseButton1Click is wrapped to keep the signature the caller expects.
	local handle = TouchKit.pad(btn)
	if handle then handle.connect(function() fn(nil, 1) end) end
	return conn
end

return TouchKit
