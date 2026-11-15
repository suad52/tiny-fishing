local Tool=script.Parent
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local plr=Players.LocalPlayer
local char,hum,hrp,rightHand,leftHand,upperTorso
local ikR,ikL,tRAtt,tLAtt
local token=0
local casting=false

local REST_GRIP=CFrame.Angles(math.rad(33),0,0)
local WIND_GRIP=CFrame.Angles(math.rad(-40),0,0)
local CAST_GRIP=CFrame.Angles(math.rad(78),0,0)
local REST_R=Vector3.new(0.7,0.4,-1.0); local REST_L=Vector3.new(0.1,0.3,-1.0)
local WIND_R=Vector3.new(0.6,2.4,0.7);  local WIND_L=Vector3.new(-0.1,2.0,0.4)
local CAST_R=Vector3.new(0.55,1.5,-2.0);local CAST_L=Vector3.new(0.1,1.4,-1.15)
local function smooth(t) return t*t*(3-2*t) end

local function setupRig()
  char=Tool.Parent
  hum=char:FindFirstChildOfClass("Humanoid"); hrp=char:FindFirstChild("HumanoidRootPart")
  rightHand=char:FindFirstChild("RightHand"); leftHand=char:FindFirstChild("LeftHand"); upperTorso=char:FindFirstChild("UpperTorso")
  if not (hum and hrp and rightHand and leftHand and upperTorso) then return end
  tRAtt=Instance.new("Attachment"); tRAtt.Name="RodRTarget"; tRAtt.Parent=hrp
  tLAtt=Instance.new("Attachment"); tLAtt.Name="RodLTarget"; tLAtt.Parent=hrp
  ikR=Instance.new("IKControl"); ikR.Type=Enum.IKControlType.Position; ikR.ChainRoot=upperTorso; ikR.EndEffector=rightHand; ikR.Target=tRAtt; ikR.Weight=0; ikR.Parent=hum
  ikL=Instance.new("IKControl"); ikL.Type=Enum.IKControlType.Position; ikL.ChainRoot=upperTorso; ikL.EndEffector=leftHand; ikL.Target=tLAtt; ikL.Weight=0; ikL.Parent=hum
end
local function teardownRig()
  token+=1
  if ikR then ikR:Destroy() end; if ikL then ikL:Destroy() end
  if tRAtt then tRAtt:Destroy() end; if tLAtt then tLAtt:Destroy() end
  ikR,ikL,tRAtt,tLAtt=nil,nil,nil,nil
  Tool.Grip=REST_GRIP
end
local function setPose(w,rT,lT,grip)
  if ikR then ikR.Weight=w; tRAtt.Position=rT end
  if ikL then ikL.Weight=w; tLAtt.Position=lT end
  Tool.Grip=grip
end
local function launchBobber()
  local tip=Tool:FindFirstChild("Tip"); local lo=tip and tip:FindFirstChild("LineOrigin")
  if not lo or not hrp then return end
  local old=workspace:FindFirstChild("FR_Bobber"); if old then old:Destroy() end
  local startP=lo.WorldPosition
  local aim=hrp.CFrame.LookVector
  local ahead=startP+aim*38
  local rp=RaycastParams.new(); rp.FilterType=Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances={char}
  local hit=workspace:Raycast(ahead+Vector3.new(0,40,0),Vector3.new(0,-200,0),rp)
  local target=hit and (hit.Position+Vector3.new(0,0.4,0)) or (ahead+Vector3.new(0,-startP.Y+1,0))
  local bob=Instance.new("Part"); bob.Name="FR_Bobber"; bob.Shape=Enum.PartType.Ball
  bob.Size=Vector3.new(0.9,0.9,0.9); bob.Color=Color3.fromRGB(220,50,50); bob.Anchored=true; bob.CanCollide=false; bob.Parent=workspace
  local band=Instance.new("Part"); band.Shape=Enum.PartType.Ball; band.Size=Vector3.new(0.92,0.45,0.92)
  band.Color=Color3.fromRGB(245,245,245); band.Anchored=true; band.CanCollide=false; band.Parent=bob
  local wc=Instance.new("WeldConstraint"); wc.Part0=bob; wc.Part1=band; wc.Parent=bob; band.CFrame=bob.CFrame
  local a1=Instance.new("Attachment"); a1.Parent=bob
  local beam=Instance.new("Beam"); beam.Attachment0=lo; beam.Attachment1=a1
  beam.Width0=0.06; beam.Width1=0.06; beam.FaceCamera=true; beam.Segments=6
  beam.Color=ColorSequence.new(Color3.fromRGB(235,235,220)); beam.Transparency=NumberSequence.new(0.15); beam.Parent=bob
  local myTok=token
  task.spawn(function()
    local dur=0.65; local t0=os.clock()
    while os.clock()-t0<dur do
      if myTok~=token then bob:Destroy(); return end
      local a=(os.clock()-t0)/dur
      bob.CFrame=CFrame.new(startP:Lerp(target,a)+Vector3.new(0,math.sin(a*math.pi)*9,0))
      band.CFrame=bob.CFrame; RunService.RenderStepped:Wait()
    end
    bob.CFrame=CFrame.new(target); band.CFrame=bob.CFrame
    task.wait(5); if bob and bob.Parent then bob:Destroy() end
  end)
end
local function playCast(myTok)
  local function phase(dur,ease,a0r,a0l,a0g,a1r,a1l,a1g,wStart,wEnd,fireAt,fire)
    local t0=os.clock(); local fired=false
    while os.clock()-t0<dur do
      if myTok~=token then return false end
      local a=(os.clock()-t0)/dur; local e=ease(a)
      setPose(wStart+(wEnd-wStart)*e, a0r:Lerp(a1r,e), a0l:Lerp(a1l,e), a0g:Lerp(a1g,e))
      if fire and not fired and a>=fireAt then fired=true; fire() end
      RunService.RenderStepped:Wait()
    end
    return true
  end
  if not phase(0.30,smooth,REST_R,REST_L,REST_GRIP,WIND_R,WIND_L,WIND_GRIP,0,1) then return end
  if not phase(0.18,function(a) return a*a end,WIND_R,WIND_L,WIND_GRIP,CAST_R,CAST_L,CAST_GRIP,1,1,0.6,launchBobber) then return end
  if not phase(0.30,smooth,CAST_R,CAST_L,CAST_GRIP,REST_R,REST_L,REST_GRIP,1,0) then return end
  setPose(0,REST_R,REST_L,REST_GRIP)
end

Tool.Equipped:Connect(function() setupRig(); Tool.Grip=REST_GRIP end)
Tool.Unequipped:Connect(function() teardownRig() end)
Tool.Activated:Connect(function()
  if casting or not ikR then return end
  casting=true; local myTok=token; playCast(myTok); casting=false
end)
