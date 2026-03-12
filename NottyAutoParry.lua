if game.GameId ~= 4777817887 then return end
if not game:IsLoaded() then game.Loaded:Wait() end

local Players             = game:GetService("Players")
local Workspace           = game:GetService("Workspace")
local RunService          = game:GetService("RunService")
local Stats               = game:GetService("Stats")
local UserInputService    = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Debris              = game:GetService("Debris")
local CoreGui             = game:GetService("CoreGui")

local cloneref = cloneref or function(...) end
local service = setmetatable({}, {__index = function(self, key)
    local cache = cloneref(game:GetService(key))
    rawset(self, key, cache)
    return cache
end})

local LocalPlayer = Players.LocalPlayer
local player      = LocalPlayer

local Runtime = workspace:FindFirstChild("Runtime")
workspace.ChildAdded:Connect(function(c)
    if c.Name == "Runtime" then Runtime = c end
end)

local Tornado_Time             = tick()
local Lerp_Radians             = 0
local Last_Warping             = tick()
local Curving                  = tick()
local Closest_Entity           = nil
local Parried                  = false
local Parries                  = 0
local Infinity                 = false
local Speed_Divisor_Multiplier = 1.1
local ParryThreshold           = 2.5

local _CachedParryData = nil
local _CachedRemote    = nil

local function GetCamera()
    return Workspace.CurrentCamera
end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(GetCamera)

local function GetParryData()
    if _CachedParryData then
        return _CachedParryData
    end
    for _, Object in filtergc("function", {"SwordsController"}) do
        if type(Object) == "function" then
            local Upvalues = debug.getupvalues(Object)
            for _, Upvalue in Upvalues do
                if type(Upvalue) == "table" and rawget(Upvalue, 1) and rawget(Upvalue, 4) and type(rawget(Upvalue, 4)) == "table" then
                    if type(rawget(Upvalue, 1)) == "string" and rawget(Upvalue, 1):find("SwordsController") then
                        _CachedParryData = Upvalue
                        break
                    end
                end
            end
            if _CachedParryData then
                break
            end
        end
    end
    return _CachedParryData
end

local function GetRemoteEvent()
    if _CachedRemote then
        return _CachedRemote
    end
    local ParryData = GetParryData()
    if not ParryData then return nil end
    for _, Object in filtergc("table", {true}) do
        if type(Object) == "table" and typeof(rawget(Object, 0)) == "Instance" and type(rawget(Object, 1)) == "table" and typeof(rawget(Object, 2)) == "Instance" and typeof(rawget(Object, 3)) == "Instance" then
            local Remote = rawget(Object, rawget(rawget(ParryData, 4), 3))
            if Remote and typeof(Remote) == "Instance" and Remote:IsA("RemoteEvent") then
                _CachedRemote = Remote
                break
            end
        end
    end
    return _CachedRemote
end

local function FireParry()
    local ParryData = GetParryData()
    local Remote = GetRemoteEvent()
    if not ParryData or not Remote then return end
    local UUIDs = {}
    for _, Value in ParryData do
        if type(Value) == "string" and Value:match("^%x%x%x%x%x%x%x%x%-") then
            table.insert(UUIDs, Value)
        end
    end
    local Selector = rawget(rawget(ParryData, 4), 3)
    local UUID = UUIDs[Selector]
    local Hash = rawget(rawget(ParryData, 4), 2)
    Remote:FireServer(unpack({UUID, Hash, 0, GetCamera().CFrame, {}, {GetCamera().ViewportSize.X / 2, GetCamera().ViewportSize.Y / 2}, false}))
end

local function FireParry2()
    local ParryData = GetParryData()
    local Remote = GetRemoteEvent()
    if not ParryData or not Remote then return end
    local UUIDs = {}
    for _, Value in ParryData do
        if type(Value) == "string" and Value:match("^%x%x%x%x%x%x%x%x%-") then
            table.insert(UUIDs, Value)
        end
    end
    local Selector = rawget(rawget(ParryData, 4), 3)
    local UUID = UUIDs[Selector]
    local Hash = rawget(rawget(ParryData, 4), 2)
    Remote.FireServer(unpack({Remote, UUID, Hash, 0, GetCamera().CFrame, {}, {GetCamera().ViewportSize.X / 2, GetCamera().ViewportSize.Y / 2}, false}))
end

local Auto_Parry = {}

function Auto_Parry.Get_Balls()
    local Balls = {}
    local ballsFolder = workspace:FindFirstChild("Balls")
    if not ballsFolder then return Balls end
    for _, inst in pairs(ballsFolder:GetChildren()) do
        if inst:GetAttribute("realBall") then
            inst.CanCollide = false
            table.insert(Balls, inst)
        end
    end
    return Balls
end

function Auto_Parry.Get_Ball()
    local ballsFolder = workspace:FindFirstChild("Balls")
    if not ballsFolder then return nil end
    for _, inst in pairs(ballsFolder:GetChildren()) do
        if inst:GetAttribute("realBall") then
            inst.CanCollide = false
            return inst
        end
    end
    return nil
end

function Auto_Parry.Closest_Player()
    local Max_Distance = math.huge
    local Found_Entity = nil
    local Alive = workspace:FindFirstChild("Alive")
    if not Alive then return nil end
    for _, Entity in pairs(Alive:GetChildren()) do
        if tostring(Entity) ~= tostring(player) and Entity.PrimaryPart then
            local d = player:DistanceFromCharacter(Entity.PrimaryPart.Position)
            if d < Max_Distance then
                Max_Distance = d
                Found_Entity = Entity
            end
        end
    end
    Closest_Entity = Found_Entity
    return Found_Entity
end

function Auto_Parry:Get_Entity_Properties()
    Auto_Parry.Closest_Player()
    if not Closest_Entity then return false end
    return {
        Velocity  = Closest_Entity.PrimaryPart.Velocity,
        Direction = (player.Character.PrimaryPart.Position - Closest_Entity.PrimaryPart.Position).Unit,
        Distance  = (player.Character.PrimaryPart.Position - Closest_Entity.PrimaryPart.Position).Magnitude,
    }
end

function Auto_Parry:Get_Ball_Properties()
    local Ball = Auto_Parry.Get_Ball()
    if not Ball then return { Velocity = Vector3.zero, Direction = Vector3.zero, Distance = 0, Dot = 0 } end
    local Ball_Direction = (player.Character.PrimaryPart.Position - Ball.Position).Unit
    local Ball_Distance  = (player.Character.PrimaryPart.Position - Ball.Position).Magnitude
    return { Velocity = Vector3.zero, Direction = Ball_Direction, Distance = Ball_Distance, Dot = 0 }
end

function Auto_Parry.Linear_Interpolation(a, b, t)
    return a + (b - a) * t
end

function Auto_Parry.Is_Curved()
    local Ball = Auto_Parry.Get_Ball()
    if not Ball then return false end
    local Zoomies = Ball:FindFirstChild("zoomies")
    if not Zoomies then return false end
    local char = player.Character
    if not char or not char.PrimaryPart then return false end

    local Velocity             = Zoomies.VectorVelocity
    local Ball_Direction       = Velocity.Unit
    local Direction            = (char.PrimaryPart.Position - Ball.Position).Unit
    local Dot                  = Direction:Dot(Ball_Direction)
    local Speed                = Velocity.Magnitude
    if Speed < 1 then return false end

    local Speed_Threshold      = math.min(Speed / 100, 40)
    local Direction_Difference = (Ball_Direction - Velocity).Unit
    local Direction_Similarity = Direction:Dot(Direction_Difference)
    local Dot_Difference       = Dot - Direction_Similarity
    local Distance             = (char.PrimaryPart.Position - Ball.Position).Magnitude
    local Pings                = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    local Dot_Threshold        = 0.5 - (Pings / 1000)
    local Reach_Time           = Distance / Speed - (Pings / 1000)
    local Ball_Distance_Threshold = 15 - math.min(Distance / 1000, 15) + Speed_Threshold

    local Clamped_Dot = math.clamp(Dot, -1, 1)
    local Radians     = math.rad(math.asin(Clamped_Dot))
    Lerp_Radians = Auto_Parry.Linear_Interpolation(Lerp_Radians, Radians, 0.8)

    if Speed > 100 and Reach_Time > Pings / 10 then
        Ball_Distance_Threshold = math.max(Ball_Distance_Threshold - 15, 15)
    end

    if Distance < Ball_Distance_Threshold then return false end
    if Dot_Difference < Dot_Threshold     then return true  end

    if Lerp_Radians < 0.018 then Last_Warping = tick() end
    if (tick() - Last_Warping) < (Reach_Time / 1.5) then return true end
    if (tick() - Curving)     < (Reach_Time / 1.5) then return true end

    return Dot < Dot_Threshold
end

local function ShouldParry(Ball)
    if not Ball then return false end
    local char = player.Character
    if not char or not char.PrimaryPart then return false end
    local Zoomies = Ball:FindFirstChild("zoomies")
    if not Zoomies then return false end
    if Ball:GetAttribute("target") ~= tostring(player) then return false end
    if Ball:FindFirstChild("ComboCounter") then return false end

    if Ball:FindFirstChild("AeroDynamicSlashVFX") then
        Debris:AddItem(Ball.AeroDynamicSlashVFX, 0)
        Tornado_Time = tick()
    end
    if Runtime and Runtime:FindFirstChild("Tornado") then
        local dur = (Runtime.Tornado:GetAttribute("TornadoTime") or 1) + 0.314159
        if (tick() - Tornado_Time) < dur then return false end
    end

    local Velocity   = Zoomies.VectorVelocity
    local Speed      = Velocity.Magnitude
    local Distance   = (char.PrimaryPart.Position - Ball.Position).Magnitude
    local Ping       = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 10
    local PingThresh = math.clamp(Ping / 10, 5, 17)

    local effectiveMultiplier = Speed_Divisor_Multiplier
    if getgenv().RandomParryAccuracyEnabled then
        if Speed < 200 then
            effectiveMultiplier = 0.7 + (math.random(40, 100) - 1) * (0.35 / 99)
        else
            effectiveMultiplier = 0.7 + (math.random(1, 100) - 1) * (0.35 / 99)
        end
    end

    local capped   = math.min(math.max(Speed - 9.5, 0), 650)
    local divisor  = (2.4 + capped * 0.002) * effectiveMultiplier
    local Accuracy = PingThresh + math.max(Speed / divisor, 9.5)

    local oneBall = Auto_Parry.Get_Ball()
    if oneBall and oneBall:GetAttribute("target") == tostring(player) and Auto_Parry.Is_Curved() then
        return false
    end

    if char.PrimaryPart:FindFirstChild("SingularityCape") then return false end
    if getgenv().InfinityDetection and Infinity then return false end

    return Distance <= Accuracy
end

ReplicatedStorage.Remotes.InfinityBall.OnClientEvent:Connect(function(a, b)
    Infinity = b and true or false
end)

ReplicatedStorage.Remotes.ParrySuccessAll.OnClientEvent:Connect(function(a, b)
    local char = player.Character
    if not char or not char.PrimaryPart then return end
    local Ball = Auto_Parry.Get_Ball()
    if not Ball then return end
    local Zoomies = Ball:FindFirstChild("zoomies")
    if not Zoomies then return end

    local Speed    = Zoomies.VectorVelocity.Magnitude
    if Speed < 1 then return end
    local Distance = (char.PrimaryPart.Position - Ball.Position).Magnitude
    local Pings    = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()

    local Speed_Threshold         = math.min(Speed / 100, 40)
    local Reach_Time              = Distance / Speed - (Pings / 1000)
    local Ball_Distance_Threshold = 15 - math.min(Distance / 1000, 15) + Speed_Threshold

    if Speed > 100 and Reach_Time > Pings / 10 then
        Ball_Distance_Threshold = math.max(Ball_Distance_Threshold - 15, 15)
    end

    if b ~= char.PrimaryPart and Distance > Ball_Distance_Threshold then
        Curving = tick()
    end
end)

local BallsFolder = workspace:WaitForChild("Balls")
BallsFolder.ChildAdded:Connect(function()   Parried = false end)
BallsFolder.ChildRemoved:Connect(function() Parries = 0; Parried = false end)

local function CreateBallTracker(p)
    local tracker = { activeBalls = {}, ballConns = {}, folderConns = {}, wsConn = nil }

    local function onAdded(ball)
        if not ball:IsA("Part") then return end
        if not (ball:GetAttribute("realBall") == true or ball.Name:match("^%d+$")) then return end
        if not ball.Parent then return end
        if ball.Parent.Name ~= "Balls" and ball.Parent.Name ~= "TrainingBalls" then return end
        if ball:GetAttribute("target") == p.Name then tracker.activeBalls[ball] = true end
        tracker.ballConns[ball] = ball:GetAttributeChangedSignal("target"):Connect(function()
            tracker.activeBalls[ball] = (ball:GetAttribute("target") == p.Name) or nil
        end)
        ball.AncestryChanged:Connect(function(_, parent)
            if not parent then
                if tracker.ballConns[ball] then tracker.ballConns[ball]:Disconnect() end
                tracker.ballConns[ball]   = nil
                tracker.activeBalls[ball] = nil
            end
        end)
    end

    local function onRemoved(ball)
        if tracker.ballConns[ball] then tracker.ballConns[ball]:Disconnect() end
        tracker.ballConns[ball]   = nil
        tracker.activeBalls[ball] = nil
    end

    local function connectFolder(folder)
        if tracker.folderConns[folder] then return end
        for _, b in ipairs(folder:GetChildren()) do onAdded(b) end
        tracker.folderConns[folder] = {
            a = folder.ChildAdded:Connect(onAdded),
            r = folder.ChildRemoved:Connect(onRemoved),
        }
    end

    tracker.wsConn = Workspace.ChildAdded:Connect(function(c)
        if c.Name == "Balls" or c.Name == "TrainingBalls" then connectFolder(c) end
    end)
    for _, c in ipairs(Workspace:GetChildren()) do
        if c.Name == "Balls" or c.Name == "TrainingBalls" then connectFolder(c) end
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

local BallTracker = CreateBallTracker(player)

local function HasActiveBall()
    return #BallTracker:GetActiveBalls() > 0
end

local autoParryConns = {}

local function cleanupLoop(tbl, name)
    if not tbl[name] then return end
    for _, c in ipairs(tbl[name]) do
        if c and c.Connected then c:Disconnect() end
    end
    tbl[name] = nil
end

local function CreateAutoParryLoop(name, action, instant)
    cleanupLoop(autoParryConns, name)
    local conns = {}

    table.insert(conns, RunService.PreSimulation:Connect(function()
        if not getgenv()[name] then return end
        local char = player.Character
        if not char or not char.PrimaryPart then return end
        if Parried then return end
        for _, Ball in pairs(Auto_Parry.Get_Balls()) do
            if ShouldParry(Ball) then
                action()
                Parried = true
                Ball:GetAttributeChangedSignal("target"):Once(function() Parried = false end)
                Parries += 1
                task.delay(0.5, function() if Parries > 0 then Parries -= 1 end end)
                break
            end
        end
    end))

    if instant then
        table.insert(conns, RunService.RenderStepped:Connect(function()
            if not getgenv()[name] then return end
            if HasActiveBall() then
                local Ball = Auto_Parry.Get_Ball()
                if Ball and ShouldParry(Ball) then action() end
            end
        end))
    end

    autoParryConns[name] = conns
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "NottyAutoParry"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = CoreGui

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(0, 230, 0, 110)
Frame.Position = UDim2.new(0.5, -115, 0.05, 0)
Frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Draggable = true
Frame.Parent = ScreenGui
Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 8)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 28)
Title.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
Title.Text = "Notty Auto Parry"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 13
Title.Parent = Frame
Instance.new("UICorner", Title).CornerRadius = UDim.new(0, 8)

local function MakeButton(text, yPos)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -16, 0, 32)
    btn.Position = UDim2.new(0, 8, 0, yPos)
    btn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    btn.Text = "[OFF] " .. text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 13
    btn.BorderSizePixel = 0
    btn.Parent = Frame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    return btn
end

local Btn1 = MakeButton("Auto Parry 1", 34)
local Btn2 = MakeButton("Auto Parry 2", 72)

local en1 = false
Btn1.MouseButton1Click:Connect(function()
    en1 = not en1
    getgenv().ap1_notty = en1
    if en1 then
        CreateAutoParryLoop("ap1_notty", FireParry, false)
        Btn1.BackgroundColor3 = Color3.fromRGB(0, 160, 70)
        Btn1.Text = "[ON] Auto Parry 1"
    else
        cleanupLoop(autoParryConns, "ap1_notty")
        Btn1.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
        Btn1.Text = "[OFF] Auto Parry 1"
    end
end)

local en2 = false
Btn2.MouseButton1Click:Connect(function()
    en2 = not en2
    getgenv().ap2_notty = en2
    if en2 then
        CreateAutoParryLoop("ap2_notty", FireParry2, false)
        Btn2.BackgroundColor3 = Color3.fromRGB(0, 160, 70)
        Btn2.Text = "[ON] Auto Parry 2"
    else
        cleanupLoop(autoParryConns, "ap2_notty")
        Btn2.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
        Btn2.Text = "[OFF] Auto Parry 2"
    end
end)
