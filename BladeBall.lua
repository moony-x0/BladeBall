if game.GameId ~= 4777817887 then return end
if not game:IsLoaded() then game.Loaded:Wait() end
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Stats             = game:GetService("Stats")
local Debris            = game:GetService("Debris")
local CoreGui           = game:GetService("CoreGui")
local Lighting          = game:GetService("Lighting")
local SoundService      = game:GetService("SoundService")
local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera
local isMobile = UserInputService.TouchEnabled and not (UserInputService.KeyboardEnabled or UserInputService.MouseEnabled)
local Runtime = workspace:FindFirstChild("Runtime")
workspace.ChildAdded:Connect(function(c) if c.Name == "Runtime" then Runtime = c end end)
local tornadoTimestamp = tick()
local isTornadoActive  = false
local parryCount       = 0
local Parried          = false
local Lerp_Radians     = 0
local Last_Warping     = tick()
local Curving          = tick()
local function FireParry()
    if isMobile then
        local ok, btn = pcall(function()
            return LocalPlayer.PlayerGui.Hotbar.Block
        end)
        if ok and btn then
            for _, s in ipairs(btn:GetDescendants()) do
                if s:IsA("Sound") then s.Volume = 0 end
            end
            pcall(function() firesignal(btn.Activated) end)
            for _, s in ipairs(btn:GetDescendants()) do
                if s:IsA("Sound") then s.Volume = 1 end
            end
        end
    else
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true,  game, 0)
        task.defer(function()
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        end)
    end
end
local AP_Engine  = {}
local closestPlayer = nil
local speedBiasAmount = 8
function AP_Engine.GetBalls()
    local list = {}
    local folder = workspace:FindFirstChild("Balls")
    if not folder then return list end
    for _, inst in ipairs(folder:GetChildren()) do
        if inst:GetAttribute("realBall") then
            inst.CanCollide = false
            table.insert(list, inst)
        end
    end
    return list
end
function AP_Engine.GetBall()
    local folder = workspace:FindFirstChild("Balls")
    if not folder then return nil end
    for _, inst in ipairs(folder:GetChildren()) do
        if inst:GetAttribute("realBall") then
            inst.CanCollide = false
            return inst
        end
    end
    return nil
end
function AP_Engine.ClosestPlayer()
    local maxDist  = math.huge
    local found    = nil
    local alive    = workspace:FindFirstChild("Alive")
    if not alive then return nil end
    for _, ent in ipairs(alive:GetChildren()) do
        if tostring(ent) ~= tostring(LocalPlayer) and ent.PrimaryPart then
            local d = LocalPlayer:DistanceFromCharacter(ent.PrimaryPart.Position)
            if d < maxDist then maxDist = d; found = ent end
        end
    end
    closestPlayer = found
    return found
end
function AP_Engine.GetBallProperties()
    local ball = AP_Engine.GetBall()
    if not ball then return { Velocity=Vector3.zero, Direction=Vector3.zero, Distance=0, Dot=0 } end
    local char = LocalPlayer.Character
    if not char or not char.PrimaryPart then return { Velocity=Vector3.zero, Direction=Vector3.zero, Distance=0, Dot=0 } end
    local dir  = (char.PrimaryPart.Position - ball.Position).Unit
    local dist = (char.PrimaryPart.Position - ball.Position).Magnitude
    return { Velocity=Vector3.zero, Direction=dir, Distance=dist, Dot=0 }
end
function AP_Engine.GetEntityProperties()
    AP_Engine.ClosestPlayer()
    if not closestPlayer then return false end
    local char = LocalPlayer.Character
    if not char or not char.PrimaryPart then return false end
    return {
        Velocity  = closestPlayer.PrimaryPart.Velocity,
        Direction = (char.PrimaryPart.Position - closestPlayer.PrimaryPart.Position).Unit,
        Distance  = (char.PrimaryPart.Position - closestPlayer.PrimaryPart.Position).Magnitude,
    }
end
function AP_Engine.Lerp(a, b, t) return a + (b - a) * t end
function AP_Engine.IsCurved()
    local ball = AP_Engine.GetBall(); if not ball then return false end
    local zoomies = ball:FindFirstChild("zoomies"); if not zoomies then return false end
    local char = LocalPlayer.Character; if not char or not char.PrimaryPart then return false end
    local velocity         = zoomies.VectorVelocity
    local ballDir          = velocity.Unit
    local direction        = (char.PrimaryPart.Position - ball.Position).Unit
    local dot              = direction:Dot(ballDir)
    local speed            = velocity.Magnitude
    local speedThreshold   = math.min(speed / 100, 40)
    local dirDiff          = (ballDir - velocity).Unit
    local dirSimilarity    = direction:Dot(dirDiff)
    local dotDiff          = dot - dirSimilarity
    local distance         = (char.PrimaryPart.Position - ball.Position).Magnitude
    local pings            = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    local dotThreshold     = 0.5 - (pings / 1000)
    local reachTime        = distance / speed - (pings / 1000)
    local ballDistThresh   = 15 - math.min(distance / 1000, 15) + speedThreshold
    local clampedDot       = math.clamp(dot, -1, 1)
    local radians          = math.rad(math.asin(clampedDot))
    Lerp_Radians = AP_Engine.Lerp(Lerp_Radians, radians, 0.8)
    if speed > 100 and reachTime > pings / 10 then
        ballDistThresh = math.max(ballDistThresh - 15, 15)
    end
    if distance < ballDistThresh    then return false end
    if dotDiff  < dotThreshold      then return true  end
    if Lerp_Radians < 0.018         then Last_Warping = tick() end
    if (tick() - Last_Warping) < (reachTime / 1.5) then return true end
    if (tick() - Curving)      < (reachTime / 1.5) then return true end
    return dot < dotThreshold
end
function AP_Engine.ShouldParry(ball)
    if not ball then return false end
    local char = LocalPlayer.Character; if not char or not char.PrimaryPart then return false end
    local zoomies = ball:FindFirstChild("zoomies"); if not zoomies then return false end
    if ball:GetAttribute("target") ~= tostring(LocalPlayer) then return false end
    if ball:FindFirstChild("ComboCounter") then return false end
    if ball:FindFirstChild("AeroDynamicSlashVFX") then
        Debris:AddItem(ball.AeroDynamicSlashVFX, 0)
        tornadoTimestamp = tick()
    end
    if Runtime and Runtime:FindFirstChild("Tornado") then
        local dur = (Runtime.Tornado:GetAttribute("TornadoTime") or 1) + 0.314159
        if (tick() - tornadoTimestamp) < dur then return false end
    end
    local velocity   = zoomies.VectorVelocity
    local speed      = velocity.Magnitude
    local distance   = (char.PrimaryPart.Position - ball.Position).Magnitude
    local ping       = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 10
    local speedBias  = math.min(speed / 20, speedBiasAmount)
    local triggerDist = speed / 2.9 + ping - speedBias
    local oneBall = AP_Engine.GetBall()
    if oneBall and oneBall:GetAttribute("target") == tostring(LocalPlayer) and AP_Engine.IsCurved() then
        return false
    end
    if char.PrimaryPart:FindFirstChild("SingularityCape") then return false end
    return distance <= triggerDist
end
function AP_Engine.SpamService(spamData)
    local ball = AP_Engine.GetBall(); if not ball then return 0 end
    AP_Engine.ClosestPlayer(); if not closestPlayer then return 0 end
    local result = 0
    local alv    = ball.AssemblyLinearVelocity
    local mag    = alv.Magnitude
    local approachDot = (LocalPlayer.Character.PrimaryPart.Position - ball.Position).Unit:Dot(alv.Unit)
    local distToClose = LocalPlayer:DistanceFromCharacter(closestPlayer.PrimaryPart.Position)
    local adjPing = spamData.Ping + math.min(mag / 6.5, 95)
    if adjPing < spamData.Entity_Properties.Distance then return result end
    if adjPing < spamData.Ball_Properties.Distance   then return result end
    if adjPing < distToClose                          then return result end
    local speedPenalty = 5 - math.min(mag / 5, 5)
    return adjPing - math.clamp(approachDot, -1, 0) * speedPenalty
end
local function CreateBallTracker(p)
    local tracker = { activeBalls={}, ballConns={}, folderConns={}, wsConn=nil }
    local function onAdded(ball)
        if not ball:IsA("Part") then return end
        if not (ball:GetAttribute("realBall")==true or ball.Name:match("^%d+$")) then return end
        if not ball.Parent then return end
        if ball.Parent.Name ~= "Balls" and ball.Parent.Name ~= "TrainingBalls" then return end
        if ball:GetAttribute("target") == p.Name then tracker.activeBalls[ball] = true end
        tracker.ballConns[ball] = ball:GetAttributeChangedSignal("target"):Connect(function()
            tracker.activeBalls[ball] = (ball:GetAttribute("target") == p.Name) or nil
        end)
        ball.AncestryChanged:Connect(function(_, par)
            if not par then
                if tracker.ballConns[ball] then tracker.ballConns[ball]:Disconnect() end
                tracker.ballConns[ball] = nil; tracker.activeBalls[ball] = nil
            end
        end)
    end
    local function onRemoved(ball)
        if tracker.ballConns[ball] then tracker.ballConns[ball]:Disconnect() end
        tracker.ballConns[ball] = nil; tracker.activeBalls[ball] = nil
    end
    local function connectFolder(folder)
        if tracker.folderConns[folder] then return end
        for _, b in ipairs(folder:GetChildren()) do onAdded(b) end
        tracker.folderConns[folder] = {
            a = folder.ChildAdded:Connect(onAdded),
            r = folder.ChildRemoved:Connect(onRemoved),
        }
    end
    tracker.wsConn = workspace.ChildAdded:Connect(function(c)
        if c.Name=="Balls" or c.Name=="TrainingBalls" then connectFolder(c) end
    end)
    for _, c in ipairs(workspace:GetChildren()) do
        if c.Name=="Balls" or c.Name=="TrainingBalls" then connectFolder(c) end
    end
    function tracker:GetActiveBalls()
        local list = {}
        for ball in pairs(self.activeBalls) do
            if ball and ball.Parent then table.insert(list, ball)
            else self.activeBalls[ball] = nil end
        end
        return list
    end
    function tracker:Destroy()
        if self.wsConn then self.wsConn:Disconnect() end
        for _, conns in pairs(self.folderConns) do conns.a:Disconnect(); conns.r:Disconnect() end
        for _, c in pairs(self.ballConns) do c:Disconnect() end
        self.ballConns = {}; self.activeBalls = {}
    end
    return tracker
end
local BallTracker = CreateBallTracker(LocalPlayer)
local function HasActiveBall() return #BallTracker:GetActiveBalls() > 0 end
local autoParryConns = {}
local function cleanupLoop(name)
    if not autoParryConns[name] then return end
    for _, c in ipairs(autoParryConns[name]) do
        if c and c.Connected then c:Disconnect() end
    end
    autoParryConns[name] = nil
end
local function CreateAutoParryLoop(name, action, instant)
    cleanupLoop(name)
    local conns = {}
    table.insert(conns, RunService.PreSimulation:Connect(function()
        if not getgenv()[name] then return end
        local char = LocalPlayer.Character; if not char or not char.PrimaryPart then return end
        if Parried then return end
        for _, ball in ipairs(AP_Engine.GetBalls()) do
            if AP_Engine.ShouldParry(ball) then
                action()
                Parried = true
                ball:GetAttributeChangedSignal("target"):Once(function() Parried = false end)
                parryCount += 1
                task.delay(0.5, function() if parryCount > 0 then parryCount -= 1 end end)
                break
            end
        end
    end))
    if instant then
        table.insert(conns, RunService.RenderStepped:Connect(function()
            if not getgenv()[name] then return end
            if HasActiveBall() then
                local ball = AP_Engine.GetBall()
                if ball and AP_Engine.ShouldParry(ball) then action() end
            end
        end))
    end
    autoParryConns[name] = conns
end
local spamDistanceOffset = 20
local autoSpamEnabled = false
local autoSpamConns   = {}
local function toggleAutoSpam(state)
    if state == autoSpamEnabled then return end
    autoSpamEnabled = state
    if autoSpamEnabled then
        local function doSpam()
            local char = LocalPlayer.Character; if not char or not char.PrimaryPart then return end
            local ball = AP_Engine.GetBall(); if not ball then return end
            local zoomies = ball:FindFirstChild("zoomies"); if not zoomies then return end
            AP_Engine.ClosestPlayer(); if not closestPlayer then return end
            local rawPing    = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
            local clampedPing = math.clamp(rawPing / 10, 10, 16)
            local spamCtx = {
                Ball_Properties   = AP_Engine.GetBallProperties(),
                Entity_Properties = AP_Engine.GetEntityProperties(),
                Ping              = clampedPing,
            }
            local score    = AP_Engine.SpamService(spamCtx)
            local ballDist = LocalPlayer:DistanceFromCharacter(ball.Position)
            local plrDist  = LocalPlayer:DistanceFromCharacter(closestPlayer.PrimaryPart.Position)
            local tgtModel = workspace.Alive and workspace.Alive:FindFirstChild(ball:GetAttribute("target"))
            if tgtModel and score >= plrDist and score >= ballDist then
                if ballDist <= score + spamDistanceOffset and parryCount > 1 then
                    FireParry()
                end
            end
        end
        autoSpamConns[1] = RunService.PreSimulation:Connect(function() if autoSpamEnabled then doSpam() end end)
        autoSpamConns[2] = RunService.RenderStepped:Connect(function() if autoSpamEnabled then doSpam() end end)
        autoSpamConns[3] = RunService.Heartbeat:Connect(function()     if autoSpamEnabled then doSpam() end end)
    else
        for _, c in ipairs(autoSpamConns) do
            if c and c.Connected then c:Disconnect() end
        end
        autoSpamConns = {}
    end
end
pcall(function()
    ReplicatedStorage.Remotes.ParrySuccessAll.OnClientEvent:Connect(function(_, parrySourceModel)
        local primary = LocalPlayer.Character and LocalPlayer.Character.PrimaryPart
        if not primary then return end
        local ball = AP_Engine.GetBall(); if not ball then return end
        local zoomies = ball:FindFirstChild("zoomies"); if not zoomies then return end
        local speed    = zoomies.VectorVelocity.Magnitude
        local distance = (primary.Position - ball.Position).Magnitude
        local pings    = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
        local speedThresh     = math.min(speed / 100, 40)
        local reachTime       = distance / speed - (pings / 1000)
        local ballDistThresh  = 15 - math.min(distance / 1000, 15) + speedThresh
        if speed > 100 and reachTime > pings / 10 then
            ballDistThresh = math.max(ballDistThresh - 15, 15)
        end
        if parrySourceModel ~= primary and distance > ballDistThresh then
            Curving = tick()
        end
    end)
end)
pcall(function()
    if Runtime then
        Runtime.ChildAdded:Connect(function(c)
            if c.Name == "Tornado" then tornadoTimestamp = tick(); isTornadoActive = true end
        end)
    end
end)
pcall(function()
    local BallsFolder = workspace:WaitForChild("Balls", 10)
    if BallsFolder then
        BallsFolder.ChildAdded:Connect(function()   Parried = false end)
        BallsFolder.ChildRemoved:Connect(function() parryCount = 0; Parried = false end)
    end
end)
task.spawn(FireParry)
local G = {}
local T = {
    Win   = Color3.fromRGB(5,6,14),   WTr  = 0.46,
    Side  = Color3.fromRGB(4,5,12),   STr  = 0.40,
    Panel = Color3.fromRGB(9,11,24),  PTr  = 0.52,
    Card  = Color3.fromRGB(14,17,36), CTr  = 0.64,
    CHov  = Color3.fromRGB(22,27,52), CHTr = 0.45,
    Bdr   = Color3.fromRGB(255,255,255), BdrTr = 0.82,
    Txt   = Color3.fromRGB(228,232,255),
    TxtS  = Color3.fromRGB(145,155,200),
    TxtD  = Color3.fromRGB(75,85,130),
    Blue  = Color3.fromRGB(58,130,255),
    Purple= Color3.fromRGB(120,72,255),
    Green = Color3.fromRGB(36,200,120),
    Red   = Color3.fromRGB(255,58,80),
    Orange= Color3.fromRGB(255,148,30),
    Teal  = Color3.fromRGB(0,210,200),
    Pink  = Color3.fromRGB(255,80,185),
    Yellow= Color3.fromRGB(255,212,0),
    Cyan  = Color3.fromRGB(0,200,240),
    TOn   = Color3.fromRGB(58,130,255),
    TOff  = Color3.fromRGB(38,44,72),
}
local SFX  = { click=6026984224, toggle=4157535107, open=3846828635, close=4157535107, notify=6026984224 }
local SVOL = { click=0.15, toggle=0.18, open=0.15, close=0.13, notify=0.16 }
local function sfx(name)
    pcall(function()
        local s = Instance.new("Sound", workspace)
        s.SoundId = "rbxassetid://" .. (SFX[name] or SFX.click)
        s.Volume  = SVOL[name] or 0.15
        s.RollOffMaxDistance = 0
        s:Play()
        s.Ended:Connect(function() s:Destroy() end)
    end)
end
local function tw(obj, props, t, style, dir)
    pcall(function()
        TweenService:Create(obj, TweenInfo.new(t or 0.2, style or Enum.EasingStyle.Quart, dir or Enum.EasingDirection.Out), props):Play()
    end)
end
local function corner(frame, r)
    local c = Instance.new("UICorner", frame)
    c.CornerRadius = UDim.new(0, r or 8)
    return c
end
local function stroke(frame, col, th, tr)
    local s = Instance.new("UIStroke", frame)
    s.Color = col or Color3.new(1,1,1)
    s.Thickness = th or 1
    s.Transparency = tr or 0.78
    return s
end
local function lbl(parent, text, size, col, font, xa)
    local l = Instance.new("TextLabel", parent)
    l.Text = text or ""
    l.TextSize = size or 13
    l.TextColor3 = col or T.Txt
    l.Font = font or Enum.Font.Gotham
    l.BackgroundTransparency = 1
    l.Size = UDim2.new(1,0,1,0)
    l.TextXAlignment = xa or Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.TextWrapped = true
    return l
end
local function makeCard(parent, h, zi)
    local c = Instance.new("Frame", parent)
    c.Size = UDim2.new(1, 0, 0, h or 50)
    c.BackgroundColor3 = T.Card
    c.BackgroundTransparency = T.CTr
    c.BorderSizePixel = 0
    c.ZIndex = zi or 6
    corner(c, 10)
    stroke(c, T.Bdr, 1, T.BdrTr)
    return c
end
local function makeToggle(parent, zBase, isOn, onChange)
    local bg = Instance.new("Frame", parent)
    bg.Size = UDim2.fromOffset(40, 22)
    bg.BackgroundColor3 = isOn and T.TOn or T.TOff
    bg.BorderSizePixel = 0
    bg.ZIndex = zBase or 6
    corner(bg, 50)
    stroke(bg, T.Bdr, 1, 0.84)
    local knob = Instance.new("Frame", bg)
    knob.Size = UDim2.fromOffset(18, 18)
    knob.Position = isOn and UDim2.fromOffset(20, 2) or UDim2.fromOffset(2, 2)
    knob.BackgroundColor3 = Color3.fromRGB(235, 240, 255)
    knob.BorderSizePixel = 0
    knob.ZIndex = (zBase or 6) + 1
    corner(knob, 50)
    local tb = Instance.new("TextButton", bg)
    tb.Size = UDim2.fromScale(1, 1)
    tb.BackgroundTransparency = 1
    tb.Text = ""
    tb.ZIndex = (zBase or 6) + 2
    local val = isOn
    tb.MouseButton1Click:Connect(function()
        sfx("toggle")
        val = not val
        tw(bg,   { BackgroundColor3 = val and T.TOn or T.TOff }, 0.14)
        tw(knob, { Position = val and UDim2.fromOffset(20, 2) or UDim2.fromOffset(2, 2) }, 0.14, Enum.EasingStyle.Back)
        if onChange then onChange(val) end
    end)
    return bg
end
local function makeSlider(parent, zi, labelTxt, initVal, minV, maxV, onChange, fmtStr)
    fmtStr = fmtStr or "%.1f"
    local card = makeCard(parent, 56, zi or 6)
    local nl = lbl(card, labelTxt, 10, T.TxtS, Enum.Font.Gotham)
    nl.Size = UDim2.new(1, -70, 0, 18); nl.Position = UDim2.fromOffset(12, 5); nl.ZIndex = (zi or 6)+1
    local vl = lbl(card, string.format(fmtStr, initVal), 10, T.Blue, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
    vl.Size = UDim2.fromOffset(58, 18); vl.Position = UDim2.new(1,-68,0,5); vl.ZIndex = (zi or 6)+1
    local trk = Instance.new("Frame", card)
    trk.Size = UDim2.new(1,-24,0,5); trk.Position = UDim2.fromOffset(12,36)
    trk.BackgroundColor3 = T.TOff; trk.BackgroundTransparency = 0.4
    trk.BorderSizePixel = 0; trk.ZIndex = (zi or 6)+1; corner(trk,3)
    local pct = math.clamp((initVal-minV)/math.max(0.001,maxV-minV),0,1)
    local fl = Instance.new("Frame", trk)
    fl.Size = UDim2.new(pct,0,1,0); fl.BackgroundColor3 = T.Blue
    fl.BorderSizePixel = 0; fl.ZIndex = (zi or 6)+2; corner(fl,3)
    local knob = Instance.new("Frame", trk)
    knob.Size = UDim2.fromOffset(12,12); knob.AnchorPoint = Vector2.new(0.5,0.5)
    knob.Position = UDim2.new(pct,0,0.5,0)
    knob.BackgroundColor3 = Color3.new(1,1,1); knob.BorderSizePixel=0
    knob.ZIndex = (zi or 6)+3; corner(knob,50)
    local hitZone = Instance.new("TextButton", card)
    hitZone.Size = UDim2.new(1,0,1,-24); hitZone.Position = UDim2.fromOffset(0,24)
    hitZone.BackgroundTransparency = 1; hitZone.Text = ""; hitZone.ZIndex = (zi or 6)+4
    local dragging = false
    local function upd(ax)
        local np = math.clamp((ax-trk.AbsolutePosition.X)/math.max(1,trk.AbsoluteSize.X),0,1)
        local nv = minV + np*(maxV-minV)
        if (maxV-minV)>5 then nv = math.floor(nv+0.5) end
        fl.Size = UDim2.new(np,0,1,0); knob.Position = UDim2.new(np,0,0.5,0)
        vl.Text = string.format(fmtStr, nv)
        if onChange then onChange(nv) end
    end
    hitZone.MouseButton1Down:Connect(function(x) dragging=true upd(x) end)
    hitZone.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.Touch then dragging=true upd(i.Position.X) end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then upd(i.Position.X) end
    end)
    return card
end
local function makeDropdown(parent, zi, labelTxt, opts, initVal, onChange)
    local z = zi or 6
    local card = makeCard(parent, 36, z)
    card.ClipsDescendants = false
    local selVal = initVal or (opts and opts[1]) or ""
    local isOpen = false
    local headerBtn = Instance.new("TextButton", card)
    headerBtn.Size = UDim2.fromScale(1,1); headerBtn.BackgroundTransparency=1; headerBtn.Text=""; headerBtn.ZIndex=z+3
    local nl = lbl(card, labelTxt, 9, T.TxtD); nl.Size=UDim2.new(0.5,-12,0,36); nl.Position=UDim2.fromOffset(12,0); nl.ZIndex=z+1
    local selLbl = lbl(card, selVal, 10, T.Txt, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
    selLbl.Size=UDim2.new(0.5,-30,0,36); selLbl.Position=UDim2.new(0.5,0,0,0); selLbl.ZIndex=z+1
    local arrow = lbl(card,"▾",9,T.TxtD,Enum.Font.GothamBold,Enum.TextXAlignment.Right)
    arrow.Size=UDim2.fromOffset(18,36); arrow.Position=UDim2.new(1,-20,0,0); arrow.ZIndex=z+1
    local dropMenu = Instance.new("Frame", card)
    dropMenu.Size=UDim2.new(1,0,0,#opts*30+6); dropMenu.Position=UDim2.new(0,0,1,2)
    dropMenu.BackgroundColor3=Color3.fromRGB(10,12,28); dropMenu.BackgroundTransparency=0.12
    dropMenu.BorderSizePixel=0; dropMenu.ZIndex=z+10; dropMenu.Visible=false
    corner(dropMenu,8); stroke(dropMenu,T.Blue,1,0.6)
    Instance.new("UIListLayout",dropMenu).Padding=UDim.new(0,2)
    for _, optName in ipairs(opts) do
        local isAct = optName==selVal
        local ob = Instance.new("TextButton", dropMenu)
        ob.Size=UDim2.new(1,0,0,26); ob.BackgroundColor3=isAct and T.Blue or T.Card
        ob.BackgroundTransparency=isAct and 0.6 or 0.8; ob.Text=optName
        ob.Font=Enum.Font.Gotham; ob.TextSize=10; ob.TextColor3=isAct and T.Blue or T.TxtS
        ob.AutoButtonColor=false; ob.BorderSizePixel=0; ob.ZIndex=z+11; corner(ob,6)
        ob.MouseButton1Click:Connect(function()
            sfx("click"); selVal=optName; selLbl.Text=optName
            for _, c in ipairs(dropMenu:GetChildren()) do
                if c:IsA("TextButton") then
                    local a=c.Text==optName
                    tw(c,{BackgroundColor3=a and T.Blue or T.Card,BackgroundTransparency=a and 0.6 or 0.8,TextColor3=a and T.Blue or T.TxtS},0.1)
                end
            end
            isOpen=false; tw(dropMenu,{Size=UDim2.new(1,0,0,0)},0.18,Enum.EasingStyle.Quart)
            tw(arrow,{TextColor3=T.TxtD,Rotation=0},0.18)
            task.wait(0.18); dropMenu.Visible=false
            if onChange then onChange(optName) end
        end)
    end
    headerBtn.MouseButton1Click:Connect(function()
        sfx("click"); isOpen=not isOpen
        if isOpen then
            dropMenu.Size=UDim2.new(1,0,0,0); dropMenu.Visible=true
            tw(dropMenu,{Size=UDim2.new(1,0,0,#opts*30+6)},0.22,Enum.EasingStyle.Back)
            tw(arrow,{TextColor3=T.Blue,Rotation=180},0.18)
        else
            tw(dropMenu,{Size=UDim2.new(1,0,0,0)},0.16,Enum.EasingStyle.Quart)
            tw(arrow,{TextColor3=T.TxtD,Rotation=0},0.18)
            task.wait(0.16); dropMenu.Visible=false
        end
    end)
    return card
end
local function makeButton(parent, zi, labelTxt, btnTxt, col, onClick)
    local card = makeCard(parent, 40, zi or 6)
    local nl = lbl(card, labelTxt, 10, T.TxtS)
    nl.Size=UDim2.new(1,-90,1,0); nl.Position=UDim2.fromOffset(12,0); nl.ZIndex=(zi or 6)+1
    local btn = Instance.new("TextButton", card)
    btn.Size=UDim2.fromOffset(72,24); btn.AnchorPoint=Vector2.new(1,0.5)
    btn.Position=UDim2.new(1,-10,0.5,0)
    btn.BackgroundColor3=col or T.Blue; btn.BackgroundTransparency=0.72
    btn.Text=btnTxt or "Run"; btn.Font=Enum.Font.GothamBold; btn.TextSize=9
    btn.TextColor3=col or T.Blue; btn.AutoButtonColor=false; btn.BorderSizePixel=0; btn.ZIndex=(zi or 6)+2
    corner(btn,6)
    btn.MouseEnter:Connect(function() tw(btn,{BackgroundTransparency=0.5},0.08) end)
    btn.MouseLeave:Connect(function() tw(btn,{BackgroundTransparency=0.72},0.08) end)
    btn.MouseButton1Click:Connect(function()
        sfx("click")
        tw(btn,{Size=UDim2.fromOffset(68,22)},0.06)
        task.delay(0.1, function() tw(btn,{Size=UDim2.fromOffset(72,24)},0.12,Enum.EasingStyle.Back) end)
        if onClick then onClick() end
    end)
    return card
end
local function makeRow(parent, labelTxt, descTxt, isOn, accentCol, zi, onChange)
    local row = Instance.new("Frame", parent)
    row.Size=UDim2.new(1,0,0,44); row.BackgroundColor3=Color3.fromRGB(6,8,18)
    row.BackgroundTransparency=0.5; row.BorderSizePixel=0; row.ZIndex=zi or 5
    corner(row,8)
    local acBar = Instance.new("Frame", row)
    acBar.Size=UDim2.fromOffset(2, isOn and 24 or 0); acBar.AnchorPoint=Vector2.new(0,0.5)
    acBar.Position=UDim2.new(0,0,0.5,0); acBar.BackgroundColor3=accentCol or T.Blue
    acBar.BorderSizePixel=0; acBar.ZIndex=(zi or 5)+1; corner(acBar,2); acBar.Name="AccentBar"
    local nl = lbl(row, labelTxt, 11, T.Txt, Enum.Font.GothamBold)
    nl.Size=UDim2.new(1,-60,0,18); nl.Position=UDim2.fromOffset(10,4); nl.ZIndex=(zi or 5)+1
    if descTxt and descTxt~="" then
        local dl = lbl(row, descTxt, 9, T.TxtD)
        dl.Size=UDim2.new(1,-60,0,14); dl.Position=UDim2.fromOffset(10,22); dl.ZIndex=(zi or 5)+1
    end
    local tog = makeToggle(row, (zi or 5)+1, isOn, function(v)
        local ab = row:FindFirstChild("AccentBar")
        if ab then tw(ab, {Size=UDim2.fromOffset(2, v and 24 or 0)}, 0.15, Enum.EasingStyle.Back) end
        if onChange then onChange(v) end
    end)
    tog.Position=UDim2.new(1,-46,0.5,-10)
    return row
end
local function secHdr(parent, text, lo)
    local f = Instance.new("Frame", parent)
    f.Size=UDim2.new(1,0,0,18); f.BackgroundTransparency=1; f.BorderSizePixel=0; f.LayoutOrder=lo or 0
    local l = lbl(f, text:upper(), 8, T.TxtD, Enum.Font.GothamBold)
    l.Size=UDim2.new(1,-12,1,0); l.Position=UDim2.fromOffset(12,0)
    local sep = Instance.new("Frame", f)
    sep.Size=UDim2.new(1,-12,0,1); sep.Position=UDim2.new(0,6,1,-1)
    sep.BackgroundColor3=T.TxtD; sep.BackgroundTransparency=0.7; sep.BorderSizePixel=0
    return f
end
local State = {
    Visible    = false,
    ActivePage = "combat",
    Keybind    = Enum.KeyCode.RightShift,
}
local sg = Instance.new("ScreenGui")
sg.Name = "NotHubUI"; sg.ResetOnSpawn = false; sg.DisplayOrder = 200
sg.IgnoreGuiInset = true; sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = CoreGui
local Win = Instance.new("Frame", sg)
Win.Name = "Win"; Win.Size = UDim2.fromOffset(520, 330)
Win.AnchorPoint = Vector2.new(0.5, 0.5); Win.Position = UDim2.fromScale(0.5, 0.5)
Win.BackgroundColor3 = T.Win; Win.BackgroundTransparency = T.WTr
Win.BorderSizePixel = 0; Win.Visible = false
corner(Win, 12); stroke(Win, T.Bdr, 1, T.BdrTr)
G.Win = Win
local topBar = Instance.new("Frame", Win)
topBar.Size = UDim2.new(1, 0, 0, 2); topBar.Position = UDim2.fromOffset(0, 0)
topBar.BackgroundColor3 = T.Blue; topBar.BorderSizePixel = 0; topBar.ZIndex = 8
do
    local tg = Instance.new("UIGradient", topBar)
    tg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   T.Blue),
        ColorSequenceKeypoint.new(0.5, T.Purple),
        ColorSequenceKeypoint.new(1,   T.Blue),
    })
end
local sideBar = Instance.new("Frame", Win)
sideBar.Size = UDim2.new(0, 110, 1, 0); sideBar.Position = UDim2.fromOffset(0, 0)
sideBar.BackgroundColor3 = T.Side; sideBar.BackgroundTransparency = T.STr
sideBar.BorderSizePixel = 0; sideBar.ZIndex = 5
corner(sideBar, 12)
do local sq = Instance.new("Frame", sideBar)
sq.Size=UDim2.new(0,12,1,0); sq.Position=UDim2.new(1,-12,0,0)
sq.BackgroundColor3=T.Side; sq.BackgroundTransparency=T.STr; sq.BorderSizePixel=0 end
local logoLbl = Instance.new("TextLabel", sideBar)
logoLbl.Size=UDim2.new(1,0,0,28); logoLbl.Position=UDim2.fromOffset(0,10)
logoLbl.BackgroundTransparency=1; logoLbl.Font=Enum.Font.GothamBold; logoLbl.TextSize=15
logoLbl.TextColor3=T.Txt; logoLbl.Text="NOTHUB"; logoLbl.TextXAlignment=Enum.TextXAlignment.Center
logoLbl.ZIndex=6
local subLogoLbl = Instance.new("TextLabel", sideBar)
subLogoLbl.Size=UDim2.new(1,0,0,12); subLogoLbl.Position=UDim2.fromOffset(0,36)
subLogoLbl.BackgroundTransparency=1; subLogoLbl.Font=Enum.Font.Gotham; subLogoLbl.TextSize=8
subLogoLbl.TextColor3=T.Purple; subLogoLbl.Text="blade ball v3.0"; subLogoLbl.TextXAlignment=Enum.TextXAlignment.Center
subLogoLbl.ZIndex=6
local navList = Instance.new("Frame", sideBar)
navList.Size=UDim2.new(1,-12,1,-62); navList.Position=UDim2.fromOffset(6,54)
navList.BackgroundTransparency=1; navList.BorderSizePixel=0; navList.ZIndex=5
do Instance.new("UIListLayout",navList).Padding=UDim.new(0,3) end
local content = Instance.new("Frame", Win)
content.Size=UDim2.new(1,-110,1,-2); content.Position=UDim2.fromOffset(110,2)
content.BackgroundTransparency=1; content.BorderSizePixel=0; content.ZIndex=4
local pages = {}
local function makePageScroll(pageFrame)
    local sf = Instance.new("ScrollingFrame", pageFrame)
    sf.Size=UDim2.fromScale(1,1); sf.Position=UDim2.fromOffset(0,0)
    sf.BackgroundTransparency=1; sf.BorderSizePixel=0; sf.ZIndex=5
    sf.ScrollBarThickness=3; sf.ScrollBarImageColor3=T.Blue
    sf.CanvasSize=UDim2.new(0,0,0,0); sf.AutomaticCanvasSize=Enum.AutomaticSize.Y
    local ll = Instance.new("UIListLayout", sf)
    ll.Padding=UDim.new(0,4); ll.HorizontalAlignment=Enum.HorizontalAlignment.Center
    local pad = Instance.new("UIPadding", sf)
    pad.PaddingLeft=UDim.new(0,8); pad.PaddingRight=UDim.new(0,8)
    pad.PaddingTop=UDim.new(0,6);  pad.PaddingBottom=UDim.new(0,8)
    return sf
end
local navBtns = {}
local function newPage(id, label, accentCol)
    local frame = Instance.new("Frame", content)
    frame.Size=UDim2.fromScale(1,1); frame.BackgroundTransparency=1
    frame.BorderSizePixel=0; frame.Visible=false; frame.ZIndex=4
    pages[id] = frame
    local btn = Instance.new("TextButton", navList)
    btn.Size=UDim2.new(1,0,0,30); btn.BackgroundColor3=T.Card
    btn.BackgroundTransparency=0.85; btn.BorderSizePixel=0; btn.ZIndex=6
    btn.Text=""; btn.AutoButtonColor=false
    corner(btn, 8)
    local acBar = Instance.new("Frame", btn)
    acBar.Name="NavAccent"; acBar.Size=UDim2.fromOffset(2,0)
    acBar.AnchorPoint=Vector2.new(0,0.5); acBar.Position=UDim2.new(0,0,0.5,0)
    acBar.BackgroundColor3=accentCol or T.Blue; acBar.BorderSizePixel=0; acBar.ZIndex=7
    corner(acBar,2)
    local lText = Instance.new("TextLabel", btn)
    lText.Size=UDim2.new(1,-12,1,0); lText.Position=UDim2.fromOffset(10,0)
    lText.BackgroundTransparency=1; lText.Font=Enum.Font.GothamBold; lText.TextSize=10
    lText.TextColor3=T.TxtD; lText.Text=label; lText.TextXAlignment=Enum.TextXAlignment.Left; lText.ZIndex=7
    navBtns[id]={btn=btn,lText=lText,acBar=acBar,accent=accentCol or T.Blue}
    btn.MouseEnter:Connect(function()
        if State.ActivePage ~= id then tw(btn,{BackgroundTransparency=0.7},0.08) end
    end)
    btn.MouseLeave:Connect(function()
        if State.ActivePage ~= id then tw(btn,{BackgroundTransparency=0.85},0.08) end
    end)
    btn.MouseButton1Click:Connect(function()
        sfx("click"); G.showPage(id)
    end)
    return frame
end
G.showPage = function(id)
    State.ActivePage = id
    for pid, pf in pairs(pages) do pf.Visible = (pid==id) end
    for nid, nb in pairs(navBtns) do
        local active = nid==id
        tw(nb.btn,   {BackgroundTransparency=active and 0.55 or 0.85}, 0.12)
        tw(nb.lText, {TextColor3=active and nb.accent or T.TxtD}, 0.12)
        tw(nb.acBar, {Size=UDim2.fromOffset(2, active and 20 or 0)}, 0.15, Enum.EasingStyle.Back)
    end
end
local function makeNotif(title, desc, ntype)
    pcall(function()
        local nsg = Instance.new("ScreenGui")
        nsg.Name="BladeNotif"; nsg.ResetOnSpawn=false; nsg.DisplayOrder=300
        nsg.IgnoreGuiInset=true; nsg.Parent=CoreGui
        local vp = Camera.ViewportSize
        local ncard = Instance.new("Frame", nsg)
        ncard.Size=UDim2.fromOffset(240,52); ncard.AnchorPoint=Vector2.new(1,1)
        ncard.Position=UDim2.new(1,-12,1,-12)
        ncard.BackgroundColor3=T.Panel; ncard.BackgroundTransparency=0.25
        ncard.BorderSizePixel=0; ncard.ZIndex=10
        corner(ncard,8); stroke(ncard,T.Bdr,1,0.78)
        local col = ntype=="error" and T.Red or ntype=="success" and T.Green or T.Blue
        local sb = Instance.new("Frame",ncard); sb.Size=UDim2.fromOffset(2,40)
        sb.Position=UDim2.fromOffset(0,6); sb.BackgroundColor3=col
        sb.BorderSizePixel=0; sb.ZIndex=11; corner(sb,2)
        local tl = Instance.new("TextLabel",ncard)
        tl.Size=UDim2.new(1,-14,0,18); tl.Position=UDim2.fromOffset(8,4)
        tl.BackgroundTransparency=1; tl.Font=Enum.Font.GothamBold; tl.TextSize=10
        tl.TextColor3=col; tl.Text=title; tl.TextXAlignment=Enum.TextXAlignment.Left; tl.ZIndex=11
        local dl = Instance.new("TextLabel",ncard)
        dl.Size=UDim2.new(1,-14,0,24); dl.Position=UDim2.fromOffset(8,20)
        dl.BackgroundTransparency=1; dl.Font=Enum.Font.Gotham; dl.TextSize=9
        dl.TextColor3=T.TxtS; dl.Text=desc; dl.TextXAlignment=Enum.TextXAlignment.Left
        dl.TextWrapped=true; dl.ZIndex=11
        ncard.Position=UDim2.new(1,260,1,-12)
        tw(ncard,{Position=UDim2.new(1,-12,1,-12)},0.3,Enum.EasingStyle.Back)
        task.delay(3.5, function()
            tw(ncard,{Position=UDim2.new(1,260,1,-12)},0.28,Enum.EasingStyle.Quart)
            task.wait(0.3); nsg:Destroy()
        end)
    end)
end
G.notify = makeNotif
G.openClient = function()
    State.Visible=true; Win.Visible=true
    tw(Win,{BackgroundTransparency=T.WTr},0.22)
    sfx("open")
end
G.closeClient = function()
    State.Visible=false
    tw(Win,{BackgroundTransparency=1},0.18)
    sfx("close")
    task.wait(0.2); Win.Visible=false
end
UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == State.Keybind then
        if State.Visible then G.closeClient() else G.openClient() end
    end
end)
do
    local dragStart, startPos, dragging = nil, nil, false
    local dragBar = Instance.new("TextButton", Win)
    dragBar.Size=UDim2.new(1,-110,0,28); dragBar.Position=UDim2.fromOffset(110,0)
    dragBar.BackgroundTransparency=1; dragBar.Text=""; dragBar.ZIndex=9; dragBar.AutoButtonColor=false
    dragBar.MouseButton1Down:Connect(function(x,y)
        dragging=true; dragStart=Vector2.new(x,y)
        startPos=Win.Position
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then
            local delta = Vector2.new(i.Position.X,i.Position.Y) - dragStart
            Win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+delta.X, startPos.Y.Scale, startPos.Y.Offset+delta.Y)
        end
    end)
end
local pCombat = newPage("combat", "Combat", T.Red)
local sfCombat = makePageScroll(pCombat)
local lo = 0
local pingLabel
do
    local s = secHdr(sfCombat, "auto parry", lo); s.LayoutOrder=lo; lo=lo+1
    makeRow(sfCombat, "Auto Parry", "fires parry when ball is in range", false, T.Red, 5, function(v)
        getgenv().ap_blade = v
        if v then
            CreateAutoParryLoop("ap_blade", FireParry, false)
        else
            cleanupLoop("ap_blade")
        end
    end).LayoutOrder=lo; lo=lo+1
    makeRow(sfCombat, "Instant Mode", "RenderStepped pre-fire for fast balls", false, T.Orange, 5, function(v)
        getgenv().ap_blade_instant = v
        if v then
            CreateAutoParryLoop("ap_blade_instant", FireParry, true)
        else
            cleanupLoop("ap_blade_instant")
        end
    end).LayoutOrder=lo; lo=lo+1
    local biasCard = makeSlider(sfCombat, 5, "Speed Bias", speedBiasAmount, 0, 20, function(v)
        speedBiasAmount = v
    end, "%.0f")
    biasCard.LayoutOrder=lo; lo=lo+1
    local s2 = secHdr(sfCombat, "auto spam", lo); s2.LayoutOrder=lo; lo=lo+1
    makeRow(sfCombat, "Auto Spam", "spams parry when ball is very close", false, T.Pink, 5, function(v)
        toggleAutoSpam(v)
    end).LayoutOrder=lo; lo=lo+1
    local spamOffCard = makeSlider(sfCombat, 5, "Spam Distance Offset", spamDistanceOffset, 5, 60, function(v)
        spamDistanceOffset = v
    end, "%.0f")
    spamOffCard.LayoutOrder=lo; lo=lo+1
    local s3 = secHdr(sfCombat, "visualiser", lo); s3.LayoutOrder=lo; lo=lo+1
    local isVisualizerActive = false
    local visualizerPart = Instance.new("Part")
    visualizerPart.Shape=Enum.PartType.Ball; visualizerPart.Anchored=true
    visualizerPart.CanCollide=false; visualizerPart.Material=Enum.Material.ForceField
    visualizerPart.Transparency=0.5; visualizerPart.Size=Vector3.new(0,0,0); visualizerPart.Parent=workspace
    RunService.RenderStepped:Connect(function()
        if not isVisualizerActive then return end
        local char = LocalPlayer.Character; if not char or not char.PrimaryPart then return end
        local ball = AP_Engine.GetBall()
        if ball and char.PrimaryPart then
            local spd = (ball:FindFirstChild("zoomies") and ball.zoomies.VectorVelocity.Magnitude) or 0
            local radius = math.clamp(spd / 2.4 + 10, 15, 200)
            visualizerPart.Size = Vector3.new(radius, radius, radius)
            visualizerPart.CFrame = char.PrimaryPart.CFrame
        else
            visualizerPart.Size = Vector3.new(0,0,0)
        end
    end)
    makeRow(sfCombat, "Parry Range Visualiser", "shows a sphere around your parry range", false, T.Teal, 5, function(v)
        isVisualizerActive = v
        if not v then visualizerPart.Size = Vector3.new(0,0,0) end
    end).LayoutOrder=lo; lo=lo+1
    local s4 = secHdr(sfCombat, "live info", lo); s4.LayoutOrder=lo; lo=lo+1
    local infoCard = makeCard(sfCombat, 36, 5)
    infoCard.LayoutOrder = lo; lo = lo+1
    local infoLbl = lbl(infoCard, "Ping: --ms  |  Ball Speed: --  |  Parries: 0", 10, T.TxtS, Enum.Font.Code)
    infoLbl.Position=UDim2.fromOffset(10,0); infoLbl.Size=UDim2.new(1,-12,1,0); infoLbl.ZIndex=6
    pingLabel = infoLbl
    RunService.Heartbeat:Connect(function()
        local ping  = pcall(function() return math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end) and math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) or 0
        local ball  = AP_Engine.GetBall()
        local speed = 0
        if ball then
            local z = ball:FindFirstChild("zoomies")
            if z then speed = math.floor(z.VectorVelocity.Magnitude) end
        end
        if pingLabel and pingLabel.Parent then
            pingLabel.Text = string.format("Ping: %dms  |  Speed: %d  |  Parries: %d", ping, speed, parryCount)
        end
    end)
end
local pMovement = newPage("movement", "Movement", T.Teal)
local sfMove    = makePageScroll(pMovement)
lo = 0
do
    local bhopConn = nil; local strafeConn = nil
    local strafe_speed = 2; local noRenderConn = nil
    local function toggleBhop(enabled)
        if enabled then
            bhopConn = RunService.PostSimulation:Connect(function()
                local char = LocalPlayer.Character; if not char then return end
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum and hum:GetState() ~= Enum.HumanoidStateType.Freefall then
                    if hum.MoveDirection.Magnitude > 0 and hum.FloorMaterial ~= Enum.Material.Air then
                        hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    end
                end
            end)
        else
            if bhopConn then bhopConn:Disconnect(); bhopConn=nil end
        end
    end
    local function toggleStrafe(enabled)
        if enabled then
            strafeConn = RunService.Heartbeat:Connect(function(dt)
                local char = LocalPlayer.Character; if not char or not char.PrimaryPart then return end
                local hum  = char:FindFirstChildOfClass("Humanoid")
                if hum and hum.MoveDirection.Magnitude ~= 0 then
                    char:TranslateBy(hum.MoveDirection * strafe_speed * 2 * dt)
                end
            end)
        else
            if strafeConn then strafeConn:Disconnect(); strafeConn=nil end
        end
    end
    local function toggleNoRender(enabled)
        pcall(function()
            LocalPlayer.PlayerScripts.EffectScripts.ClientFX.Disabled = enabled
        end)
        if enabled then
            noRenderConn = workspace.Runtime and workspace.Runtime.ChildAdded:Connect(function(child)
                Debris:AddItem(child, 0)
            end)
        else
            if noRenderConn then noRenderConn:Disconnect(); noRenderConn=nil end
        end
    end
    local sm = secHdr(sfMove, "movement", lo); sm.LayoutOrder=lo; lo=lo+1
    makeRow(sfMove,"BHop","auto-jump to maintain speed",false,T.Teal,5,function(v) toggleBhop(v) end).LayoutOrder=lo; lo=lo+1
    makeRow(sfMove,"Strafe","translate in move direction",false,T.Blue,5,function(v) toggleStrafe(v) end).LayoutOrder=lo; lo=lo+1
    makeSlider(sfMove,5,"Strafe Speed",2,1,40,function(v) strafe_speed=v end,"%.0f").LayoutOrder=lo; lo=lo+1
    local sp = secHdr(sfMove,"speed",lo); sp.LayoutOrder=lo; lo=lo+1
    local walkSpeed = 16
    makeRow(sfMove,"Speed Boost","increase walk speed",false,T.Green,5,function(v)
        local char=LocalPlayer.Character; local hum=char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = v and walkSpeed or 16 end
    end).LayoutOrder=lo; lo=lo+1
    makeSlider(sfMove,5,"Walk Speed",16,16,120,function(v)
        walkSpeed=v
        local char=LocalPlayer.Character; local hum=char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed=v end
    end,"%.0f").LayoutOrder=lo; lo=lo+1
    local sm2 = secHdr(sfMove, "fly", lo); sm2.LayoutOrder=lo; lo=lo+1
    local flyEnabled = false; local flyConn = nil; local flySpeed = 36
    local bodyVel, bodyGyro
    makeRow(sfMove,"Fly","BodyVelocity-based flight",false,T.Orange,5,function(v)
        flyEnabled = v
        if v then
            local char = LocalPlayer.Character; if not char then return end
            local root = char:FindFirstChild("HumanoidRootPart"); if not root then return end
            bodyVel  = Instance.new("BodyVelocity",  root); bodyVel.MaxForce=Vector3.new(1e5,1e5,1e5)
            bodyGyro = Instance.new("BodyGyro",      root); bodyGyro.MaxTorque=Vector3.new(1e5,1e5,1e5); bodyGyro.P=1e4
            flyConn  = RunService.Heartbeat:Connect(function()
                if not flyEnabled then return end
                local cf = Camera.CFrame
                local dir = Vector3.zero
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir+=cf.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir-=cf.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir-=cf.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir+=cf.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir+=Vector3.new(0,1,0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir-=Vector3.new(0,1,0) end
                bodyVel.Velocity = dir.Magnitude>0 and dir.Unit*flySpeed or Vector3.zero
                bodyGyro.CFrame  = cf
            end)
        else
            if flyConn then flyConn:Disconnect(); flyConn=nil end
            if bodyVel  then bodyVel:Destroy();  bodyVel=nil  end
            if bodyGyro then bodyGyro:Destroy(); bodyGyro=nil end
        end
    end).LayoutOrder=lo; lo=lo+1
    makeSlider(sfMove,5,"Fly Speed",36,10,200,function(v) flySpeed=v end,"%.0f").LayoutOrder=lo; lo=lo+1
    local sp2 = secHdr(sfMove,"performance",lo); sp2.LayoutOrder=lo; lo=lo+1
    makeRow(sfMove,"No Render (FPS Boost)","disables client effects",false,T.Yellow,5,function(v)
        toggleNoRender(v)
    end).LayoutOrder=lo; lo=lo+1
end
local pVisuals = newPage("visuals", "Visuals", T.Purple)
local sfVis    = makePageScroll(pVisuals)
lo = 0
do
    local espHLs    = {}
    local ballHL    = nil
    local tracerLines = {}
    local maxTracers  = 8
    for i = 1, maxTracers do
        tracerLines[i] = Drawing.new("Line")
        tracerLines[i].Visible   = false
        tracerLines[i].Thickness = 1.5
    end
    local function togglePlayerESP(enabled)
        if enabled then
            RunService:BindToRenderStep("BladeESP", 201, function()
                local alive = workspace:FindFirstChild("Alive"); if not alive then return end
                for model, hl in pairs(espHLs) do
                    if not (model and model.Parent) then
                        pcall(function() hl:Destroy() end); espHLs[model]=nil
                    end
                end
                for _, model in ipairs(alive:GetChildren()) do
                    if tostring(model.Name) ~= tostring(LocalPlayer.Name) then
                        if not espHLs[model] then
                            local hl = Instance.new("Highlight")
                            hl.Adornee=model; hl.FillTransparency=0.5
                            hl.FillColor=Color3.fromRGB(58,130,255)
                            hl.OutlineColor=Color3.fromRGB(255,255,255)
                            hl.OutlineTransparency=0.1
                            hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
                            hl.Parent=CoreGui
                            espHLs[model]=hl
                        end
                    end
                end
            end)
        else
            RunService:UnbindFromRenderStep("BladeESP")
            for model, hl in pairs(espHLs) do pcall(function() hl:Destroy() end) end
            espHLs = {}
        end
    end
    local function toggleBallESP(enabled)
        if enabled then
            if not ballHL then
                local ball = AP_Engine.GetBall()
                if ball then
                    ballHL = Instance.new("Highlight")
                    ballHL.Adornee=ball; ballHL.FillTransparency=0.3
                    ballHL.FillColor=Color3.fromRGB(255,80,80)
                    ballHL.OutlineColor=Color3.fromRGB(255,200,50)
                    ballHL.OutlineTransparency=0
                    ballHL.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
                    ballHL.Parent=CoreGui
                end
            end
        else
            if ballHL then pcall(function() ballHL:Destroy() end); ballHL=nil end
        end
    end
    local tracerEnabled = false
    RunService.RenderStepped:Connect(function()
        if not tracerEnabled then
            for i=1,maxTracers do tracerLines[i].Visible=false end
            return
        end
        local alive = workspace:FindFirstChild("Alive"); if not alive then return end
        local sc    = Camera.ViewportSize
        local myPos = Camera.CFrame.Position
        local idx   = 0
        for _, model in ipairs(alive:GetChildren()) do
            if model.Name ~= LocalPlayer.Name and idx < maxTracers then
                idx += 1
                local root = model:FindFirstChild("HumanoidRootPart")
                if root then
                    local sp, on = Camera:WorldToScreenPoint(root.Position)
                    if on then
                        tracerLines[idx].From    = Vector2.new(sc.X/2, sc.Y)
                        tracerLines[idx].To      = Vector2.new(sp.X, sp.Y)
                        tracerLines[idx].Color   = Color3.fromRGB(58,130,255)
                        tracerLines[idx].Visible = true
                    else tracerLines[idx].Visible=false end
                else tracerLines[idx].Visible=false end
            end
        end
        for i=idx+1,maxTracers do tracerLines[i].Visible=false end
    end)
    local sv = secHdr(sfVis,"player esp",lo); sv.LayoutOrder=lo; lo=lo+1
    makeRow(sfVis,"Player Highlights","always-on-top outlines",false,T.Purple,5,function(v) togglePlayerESP(v) end).LayoutOrder=lo; lo=lo+1
    makeRow(sfVis,"Tracers","lines from screen center",false,T.Blue,5,function(v) tracerEnabled=v end).LayoutOrder=lo; lo=lo+1
    local sv2 = secHdr(sfVis,"ball esp",lo); sv2.LayoutOrder=lo; lo=lo+1
    makeRow(sfVis,"Ball Highlight","highlights the ball through walls",false,T.Red,5,function(v) toggleBallESP(v) end).LayoutOrder=lo; lo=lo+1
    local ballDistDraw  = Drawing.new("Text")
    ballDistDraw.Font   = Drawing.Fonts.Plex; ballDistDraw.Size=13
    ballDistDraw.Outline=true; ballDistDraw.Center=true; ballDistDraw.Visible=false
    ballDistDraw.Color  = Color3.fromRGB(255,200,50)
    local ballDistEnabled = false
    RunService.RenderStepped:Connect(function()
        if not ballDistEnabled then ballDistDraw.Visible=false; return end
        local ball = AP_Engine.GetBall(); if not ball then ballDistDraw.Visible=false; return end
        local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not root then ballDistDraw.Visible=false; return end
        local sp, on = Camera:WorldToScreenPoint(ball.Position)
        if on then
            local dist = (root.Position - ball.Position).Magnitude
            local z    = ball:FindFirstChild("zoomies")
            local spd  = z and math.floor(z.VectorVelocity.Magnitude) or 0
            ballDistDraw.Text     = string.format("%.1fm  %d/s", dist, spd)
            ballDistDraw.Position = Vector2.new(sp.X, sp.Y - 16)
            ballDistDraw.Visible  = true
        else ballDistDraw.Visible=false end
    end)
    makeRow(sfVis,"Ball Distance Label","shows distance + speed over ball",false,T.Cyan,5,function(v) ballDistEnabled=v end).LayoutOrder=lo; lo=lo+1
    local sv3 = secHdr(sfVis,"chams",lo); sv3.LayoutOrder=lo; lo=lo+1
    local chamHLs = {}
    local function toggleChams(enabled)
        if enabled then
            RunService:BindToRenderStep("BladeChams", 202, function()
                local alive = workspace:FindFirstChild("Alive"); if not alive then return end
                for model, hl in pairs(chamHLs) do
                    if not (model and model.Parent) then pcall(function() hl:Destroy() end); chamHLs[model]=nil end
                end
                for _, model in ipairs(alive:GetChildren()) do
                    if model.Name ~= LocalPlayer.Name and not chamHLs[model] then
                        local hl = Instance.new("Highlight")
                        hl.Adornee=model; hl.FillTransparency=0
                        hl.FillColor=Color3.fromRGB(255,60,80)
                        hl.OutlineTransparency=1
                        hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
                        hl.Parent=CoreGui; chamHLs[model]=hl
                    end
                end
            end)
        else
            RunService:UnbindFromRenderStep("BladeChams")
            for _, hl in pairs(chamHLs) do pcall(function() hl:Destroy() end) end
            chamHLs={}
        end
    end
    makeRow(sfVis,"Chams","solid fill on players",false,T.Pink,5,function(v) toggleChams(v) end).LayoutOrder=lo; lo=lo+1
    local sv4 = secHdr(sfVis,"fullbright",lo); sv4.LayoutOrder=lo; lo=lo+1
    local origBright, origAmb
    makeRow(sfVis,"Fullbright","max ambient + brightness",false,T.Yellow,5,function(v)
        if v then
            origBright = Lighting.Brightness; origAmb = Lighting.Ambient
            Lighting.Brightness=10; Lighting.Ambient=Color3.fromRGB(178,178,178)
            Lighting.GlobalShadows=false
        else
            if origBright then Lighting.Brightness=origBright end
            if origAmb    then Lighting.Ambient=origAmb end
            Lighting.GlobalShadows=true
        end
    end).LayoutOrder=lo; lo=lo+1
end
local pMisc = newPage("misc", "Misc", T.Green)
local sfMisc = makePageScroll(pMisc)
lo = 0
do
    local sm1 = secHdr(sfMisc,"crates",lo); sm1.LayoutOrder=lo; lo=lo+1
    makeButton(sfMisc,5,"Open Sword Crate","Open",T.Green,function()
        pcall(function()
            ReplicatedStorage.Remote.RemoteFunction:InvokeServer("PromptPurchaseCrate", workspace.Spawn.Crates.NormalSwordCrate)
        end)
    end).LayoutOrder=lo; lo=lo+1
    makeButton(sfMisc,5,"Open Explosion Crate","Open",T.Red,function()
        pcall(function()
            ReplicatedStorage.Remote.RemoteFunction:InvokeServer("PromptPurchaseCrate", workspace.Spawn.Crates.NormalExplosionCrate)
        end)
    end).LayoutOrder=lo; lo=lo+1
    local sm2 = secHdr(sfMisc,"auto respawn",lo); sm2.LayoutOrder=lo; lo=lo+1
    local autoRespawnEnabled = false
    makeRow(sfMisc,"Auto Respawn","respawns on death",false,T.Teal,5,function(v)
        autoRespawnEnabled = v
        if v then
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.Died:Connect(function()
                    if autoRespawnEnabled then task.wait(0.2); LocalPlayer:LoadCharacter() end
                end)
            end
        end
    end).LayoutOrder=lo; lo=lo+1
    local sm3 = secHdr(sfMisc,"infinite jump",lo); sm3.LayoutOrder=lo; lo=lo+1
    local ijConn = nil
    makeRow(sfMisc,"Infinite Jump","jump repeatedly in the air",false,T.Blue,5,function(v)
        if v then
            ijConn = UserInputService.JumpRequest:Connect(function()
                local char = LocalPlayer.Character; if not char then return end
                local hum  = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end)
        else
            if ijConn then ijConn:Disconnect(); ijConn=nil end
        end
    end).LayoutOrder=lo; lo=lo+1
    local sm4 = secHdr(sfMisc,"server hop",lo); sm4.LayoutOrder=lo; lo=lo+1
    makeButton(sfMisc,5,"Server Hop","Hop",T.Orange,function()
        local ts = game:GetService("TeleportService")
        pcall(function()
            ts:Teleport(game.PlaceId, LocalPlayer)
        end)
    end).LayoutOrder=lo; lo=lo+1
    local sm5 = secHdr(sfMisc,"keybind",lo); sm5.LayoutOrder=lo; lo=lo+1
    local kbCard = makeCard(sfMisc,36,5); kbCard.LayoutOrder=lo; lo=lo+1
    local kbLbl  = lbl(kbCard,"Toggle UI — RightShift",10,T.TxtS)
    kbLbl.Size=UDim2.new(1,-90,1,0); kbLbl.Position=UDim2.fromOffset(12,0); kbLbl.ZIndex=6
    local kbBtn  = Instance.new("TextButton",kbCard)
    kbBtn.Size=UDim2.fromOffset(72,24); kbBtn.AnchorPoint=Vector2.new(1,0.5); kbBtn.Position=UDim2.new(1,-10,0.5,0)
    kbBtn.BackgroundColor3=T.Card; kbBtn.BackgroundTransparency=0.5
    kbBtn.Text="RightShift"; kbBtn.Font=Enum.Font.GothamBold; kbBtn.TextSize=8
    kbBtn.TextColor3=T.Blue; kbBtn.AutoButtonColor=false; kbBtn.BorderSizePixel=0; kbBtn.ZIndex=6
    corner(kbBtn,5); stroke(kbBtn,T.Blue,1,0.55)
    local waiting = false
    kbBtn.MouseButton1Click:Connect(function()
        if waiting then return end
        waiting=true; kbBtn.Text="..."; tw(kbBtn,{TextColor3=T.Orange},0.1)
        local conn; conn = UserInputService.InputBegan:Connect(function(inp,gp)
            if gp then return end
            if inp.UserInputType==Enum.UserInputType.Keyboard then
                conn:Disconnect(); waiting=false
                local keyName = tostring(inp.KeyCode):gsub("Enum.KeyCode.","")
                kbBtn.Text=keyName; kbLbl.Text="Toggle UI — "..keyName
                tw(kbBtn,{TextColor3=T.Blue},0.1)
                State.Keybind=inp.KeyCode
            end
        end)
    end)
end
local pSettings = newPage("settings", "Settings", T.TxtS)
local sfSettings = makePageScroll(pSettings)
lo = 0
do
    local ss1 = secHdr(sfSettings,"ui settings",lo); ss1.LayoutOrder=lo; lo=lo+1
    makeSlider(sfSettings,5,"Window Opacity",0.54,0,1,function(v)
        tw(Win,{BackgroundTransparency=v},0.12)
        T.WTr=v
    end,"%.2f").LayoutOrder=lo; lo=lo+1
    makeDropdown(sfSettings,5,"Window Size",{"Small","Medium","Large"},
        "Medium",function(v)
            local sizes = {
                Small  = UDim2.fromOffset(420,280),
                Medium = UDim2.fromOffset(520,330),
                Large  = UDim2.fromOffset(640,400),
            }
            tw(Win, {Size=sizes[v] or sizes.Medium}, 0.28, Enum.EasingStyle.Back)
        end).LayoutOrder=lo; lo=lo+1
    local ss2 = secHdr(sfSettings,"performance",lo); ss2.LayoutOrder=lo; lo=lo+1
    makeRow(sfSettings,"FPS Boost","disables shadows + particles",false,T.Orange,5,function(v)
        pcall(function()
            Lighting.GlobalShadows = not v
            game:GetService("Workspace").StreamingEnabled = not v
        end)
    end).LayoutOrder=lo; lo=lo+1
    local ss3 = secHdr(sfSettings,"device",lo); ss3.LayoutOrder=lo; lo=lo+1
    local devCard = makeCard(sfSettings,36,5); devCard.LayoutOrder=lo; lo=lo+1
    local devLbl  = lbl(devCard, "Device: " .. (isMobile and "Mobile" or "PC"), 10, T.TxtS)
    devLbl.Position=UDim2.fromOffset(12,0); devLbl.Size=UDim2.new(1,-12,1,0); devLbl.ZIndex=6
    makeRow(sfSettings,"Force Mobile Mode","use firesignal-based parry",isMobile,T.Pink,5,function(v)
        isMobile = v
    end).LayoutOrder=lo; lo=lo+1
end
local pSponsor = newPage("sponsor", "Sponsor", T.Orange)
local sfSponsor = makePageScroll(pSponsor)
lo = 0
do
    local aCard = Instance.new("Frame", sfSponsor)
    aCard.Size=UDim2.new(1,0,0,100); aCard.BackgroundColor3=T.Blue
    aCard.BackgroundTransparency=0.88; aCard.BorderSizePixel=0; aCard.ZIndex=5
    aCard.LayoutOrder=lo; lo=lo+1
    corner(aCard,8)
    local al = lbl(aCard,"Hyphen",22,T.Blue,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    al.Position=UDim2.fromOffset(0,12); al.Size=UDim2.new(1,0,0,28); al.ZIndex=6
    local sl = lbl(aCard,"client v2.0",9,T.TxtD,Enum.Font.Gotham,Enum.TextXAlignment.Center)
    sl.Position=UDim2.fromOffset(0,40); sl.Size=UDim2.new(1,0,0,14); sl.ZIndex=6
    local cl = lbl(aCard,"Modules · Addons · Plugins · Shaders\nTextures · Environments · Full Settings",8,T.TxtD,Enum.Font.Gotham,Enum.TextXAlignment.Center)
    cl.Position=UDim2.fromOffset(0,58); cl.Size=UDim2.new(1,0,0,28); cl.ZIndex=6
    local badge = Instance.new("TextLabel", aCard)
    badge.Size=UDim2.fromOffset(68,14); badge.AnchorPoint=Vector2.new(1,0)
    badge.Position=UDim2.new(1,-6,0,6)
    badge.BackgroundColor3=T.Orange; badge.BackgroundTransparency=0.55
    badge.Font=Enum.Font.GothamBold; badge.TextSize=7
    badge.TextColor3=T.Orange; badge.Text="SPONSOR"
    badge.TextXAlignment=Enum.TextXAlignment.Center; badge.BorderSizePixel=0; badge.ZIndex=8
    corner(badge,50); stroke(badge,T.Orange,1,0.5)
    local ss = secHdr(sfSponsor,"sponsored by hyphen client",lo); ss.LayoutOrder=lo; lo=lo+1
    local descCard = makeCard(sfSponsor, 56, 5); descCard.LayoutOrder=lo; lo=lo+1
    local descLbl  = lbl(descCard,"This script is proudly sponsored by Hyphen Client — a multi-game client with modules, addons, shaders, plugins, environments, and a clean modern UI.",9,T.TxtS)
    descLbl.Size=UDim2.new(1,-20,1,0); descLbl.Position=UDim2.fromOffset(10,0); descLbl.ZIndex=6; descLbl.TextWrapped=true
    local ss2 = secHdr(sfSponsor,"what hyphen client offers",lo); ss2.LayoutOrder=lo; lo=lo+1
    local rows = {
        { "Modules",      "KillAura · Aimbot · Silent Aim · Reach · Velocity · Trigger Bot" },
        { "Movement",     "Speed · Fly · Bhop · Dash · Glide · Wall Run · Noclip · Spin Bot" },
        { "Visuals",      "ESP · Tracers · Chams · Shaders · Textures · Elements" },
        { "Environment",  "Fog · Gravity · Skybox · Weather · Ground & Player Reflections" },
        { "Utility",      "Anti-AFK · Auto Combo · Config Manager · Plugin Editor" },
        { "Platforms",    "PC & Mobile supported · open in executor and run" },
    }
    for _, row in ipairs(rows) do
        local r = Instance.new("Frame", sfSponsor)
        r.Size=UDim2.new(1,0,0,40); r.BackgroundColor3=Color3.fromRGB(6,8,18)
        r.BackgroundTransparency=0.55; r.BorderSizePixel=0; r.ZIndex=5; r.LayoutOrder=lo; lo=lo+1
        corner(r,6)
        local ab = Instance.new("Frame",r); ab.Size=UDim2.fromOffset(2,22)
        ab.AnchorPoint=Vector2.new(0,0.5); ab.Position=UDim2.new(0,0,0.5,0)
        ab.BackgroundColor3=T.Orange; ab.BorderSizePixel=0; ab.ZIndex=6; corner(ab,2)
        local nl = lbl(r,row[1],10,T.Txt,Enum.Font.GothamBold)
        nl.Size=UDim2.new(1,-12,0,18); nl.Position=UDim2.fromOffset(10,4); nl.ZIndex=6
        local dl = lbl(r,row[2],8,T.TxtD)
        dl.Size=UDim2.new(1,-12,0,14); dl.Position=UDim2.fromOffset(10,22); dl.ZIndex=6
    end
end
do
    local mg = Instance.new("ScreenGui")
    mg.Name="NotHubMobilePill"; mg.ResetOnSpawn=false; mg.DisplayOrder=150
    mg.IgnoreGuiInset=true; mg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
    mg.Parent = isMobile and LocalPlayer.PlayerGui or CoreGui
    local Pill = Instance.new("Frame", mg)
    Pill.Size=UDim2.fromOffset(88,26); Pill.AnchorPoint=Vector2.new(0.5,0)
    Pill.Position=UDim2.new(0.5,0,0,8)
    Pill.BackgroundColor3=T.Card; Pill.BackgroundTransparency=0.42
    Pill.BorderSizePixel=0; corner(Pill,50); stroke(Pill,T.Bdr,1,0.84)
    do
        local pd=Instance.new("Frame",Pill); pd.Size=UDim2.fromOffset(2,14); pd.Position=UDim2.fromOffset(10,6)
        pd.BackgroundColor3=T.Blue; pd.BorderSizePixel=0; corner(pd,2)
    end
    local pL = lbl(Pill,"NotHub",10,T.Txt,Enum.Font.GothamBold)
    pL.Size=UDim2.new(1,-28,1,0); pL.Position=UDim2.fromOffset(16,0); pL.ZIndex=5
    local pdot = Instance.new("Frame",Pill)
    pdot.Size=UDim2.fromOffset(5,5); pdot.AnchorPoint=Vector2.new(1,0.5)
    pdot.Position=UDim2.new(1,-8,0.5,0); pdot.BackgroundColor3=T.Green
    pdot.BorderSizePixel=0; corner(pdot,50)
    task.spawn(function()
        while true do
            tw(pdot,{BackgroundTransparency=0.6},1); task.wait(1)
            tw(pdot,{BackgroundTransparency=0},1);   task.wait(1)
        end
    end)
    local pb = Instance.new("TextButton",Pill)
    pb.Size=UDim2.fromScale(1,1); pb.BackgroundTransparency=1; pb.Text=""; pb.ZIndex=5
    pb.MouseButton1Down:Connect(function() tw(Pill,{Size=UDim2.fromOffset(82,22)},0.08) end)
    pb.MouseButton1Up:Connect(function()  tw(Pill,{Size=UDim2.fromOffset(88,26)},0.18,Enum.EasingStyle.Back) end)
    pb.MouseButton1Click:Connect(function()
        if State.Visible then G.closeClient() else G.openClient() end
    end)
end
do
    local ig = Instance.new("ScreenGui")
    ig.Name="NotHubIntro"; ig.ResetOnSpawn=false; ig.DisplayOrder=9999
    ig.IgnoreGuiInset=true; ig.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
    ig.Parent = CoreGui
    local bg = Instance.new("Frame",ig)
    bg.Size=UDim2.fromScale(1,1); bg.BackgroundColor3=Color3.fromRGB(2,4,10)
    bg.BackgroundTransparency=0.22; bg.BorderSizePixel=0; bg.ZIndex=1
    local introBlur = Instance.new("BlurEffect",Lighting); introBlur.Name="NotHubIntroBlur"; introBlur.Size=24
    local topGrad = Instance.new("Frame",bg)
    topGrad.Size=UDim2.new(1,0,0,2); topGrad.BackgroundColor3=T.Blue; topGrad.BorderSizePixel=0; topGrad.ZIndex=3
    do local ug=Instance.new("UIGradient",topGrad)
    ug.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,T.Blue),ColorSequenceKeypoint.new(0.5,T.Purple),ColorSequenceKeypoint.new(1,T.Blue)}) end
    local card = Instance.new("Frame",bg)
    card.Size=UDim2.fromOffset(220,110); card.AnchorPoint=Vector2.new(0.5,0.5)
    card.Position=UDim2.fromScale(0.5,0.5); card.BackgroundColor3=Color3.fromRGB(6,8,22)
    card.BackgroundTransparency=1; card.BorderSizePixel=0; card.ZIndex=2
    corner(card,12); stroke(card,T.Blue,1,0.70)
    local wordmark = Instance.new("TextLabel",card)
    wordmark.Size=UDim2.new(1,0,0,30); wordmark.Position=UDim2.fromOffset(0,16)
    wordmark.BackgroundTransparency=1; wordmark.Font=Enum.Font.GothamBold
    wordmark.TextSize=19; wordmark.TextColor3=T.Txt; wordmark.Text="NOTHUB"
    wordmark.TextXAlignment=Enum.TextXAlignment.Center; wordmark.ZIndex=3; wordmark.TextTransparency=1
    local subLbl = Instance.new("TextLabel",card)
    subLbl.Size=UDim2.new(1,0,0,14); subLbl.Position=UDim2.fromOffset(0,46)
    subLbl.BackgroundTransparency=1; subLbl.Font=Enum.Font.Gotham; subLbl.TextSize=9
    subLbl.TextColor3=T.Purple; subLbl.Text="blade ball  v3.0"
    subLbl.TextXAlignment=Enum.TextXAlignment.Center; subLbl.ZIndex=3; subLbl.TextTransparency=1
    local barTrack = Instance.new("Frame",card)
    barTrack.Size=UDim2.new(1,-28,0,2); barTrack.AnchorPoint=Vector2.new(0.5,0)
    barTrack.Position=UDim2.new(0.5,0,0,74)
    barTrack.BackgroundColor3=Color3.fromRGB(18,20,42); barTrack.BackgroundTransparency=1
    barTrack.BorderSizePixel=0; barTrack.ZIndex=3; corner(barTrack,1)
    local barFill = Instance.new("Frame",barTrack)
    barFill.Size=UDim2.new(0,0,1,0); barFill.BackgroundColor3=T.Blue
    barFill.BorderSizePixel=0; barFill.ZIndex=4; corner(barFill,1)
    local statusLbl = Instance.new("TextLabel",card)
    statusLbl.Size=UDim2.new(1,0,0,12); statusLbl.Position=UDim2.new(0,0,0,82)
    statusLbl.BackgroundTransparency=1; statusLbl.Font=Enum.Font.Gotham
    statusLbl.TextSize=8; statusLbl.TextColor3=T.TxtD; statusLbl.Text=""
    statusLbl.TextXAlignment=Enum.TextXAlignment.Center; statusLbl.ZIndex=3; statusLbl.TextTransparency=1
    task.spawn(function()
        local msgs = {
            "checking game...", "loading parry engine...",
            "building ui...", "connecting services...", "ready."
        }
        tw(card,{BackgroundTransparency=0.55},0.38)
        tw(wordmark,{TextTransparency=0},0.35)
        tw(subLbl,{TextTransparency=0},0.42)
        tw(barTrack,{BackgroundTransparency=0.3},0.3)
        tw(statusLbl,{TextTransparency=0},0.3)
        task.wait(0.2)
        for i, msg in ipairs(msgs) do
            local pct = i / #msgs
            statusLbl.Text = msg
            tw(barFill,{Size=UDim2.new(pct,0,1,0), BackgroundColor3=pct<0.45 and T.Blue or pct<0.8 and T.Purple or T.Green},0.28)
            task.wait(0.32)
        end
        task.wait(0.12)
        tw(card,{BackgroundTransparency=1},0.28)
        tw(wordmark,{TextTransparency=1},0.22); tw(subLbl,{TextTransparency=1},0.22)
        tw(barFill,{BackgroundTransparency=1},0.18); tw(statusLbl,{TextTransparency=1},0.18)
        task.wait(0.15)
        tw(introBlur,{Size=0},0.35); tw(bg,{BackgroundTransparency=1},0.35)
        task.wait(0.38)
        pcall(function() introBlur:Destroy() end); ig:Destroy()
        G.showPage("combat")
        G.openClient()
        makeNotif("NotHub", "v3.0 ready · " .. (isMobile and "Mobile" or "PC") .. " mode", "success")
    end)
end
