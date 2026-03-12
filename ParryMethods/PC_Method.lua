local parrydata = {}

local t
for _,v in filtergc('table', {}) do
    local cont 
    for i = 0, 1 do
        local r = rawget(v, i)
        if not (typeof(r) == 'Instance' and r:IsA('RemoteEvent')) then
            cont = true
            break
        end
    end
    if cont then
        continue
    end
    t = v 
    break
end

assert(t, 'failed to retrieve table') --if it errors another way that means the table layout changed

local uuids = {}
for _,v in pairs(t) do
    if type(v) == 'string' and v:match('%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x') then
        table.insert(uuids, v)
    end
end

local info = rawget(t, 3)
local selector = rawget(info, 3)
parrydata.uuid = uuids[selector]
parrydata.hash = rawget(info, 2)

local remoteyield = Instance.new('BindableEvent')

--[[local mt = getrawmetatable(game)
local namecall; namecall = hookfunction(mt.__namecall, function(self, ...)
    if not checkcaller() and getnamecallmethod() == 'FireServer' and select(1, ...) == parrydata.uuid and select(2, ...) == parrydata.hash then
        print('NAMECALL', ...)
        hookfunction(mt.__namecall, namecall)
        remoteyield:Fire(self)
    end
        
    return namecall(self, ...)
end)]]

local waxfireserver = (game:FindFirstChildWhichIsA('RemoteEvent', true) or Instance.new('RemoteEvent')).FireServer
local fireserver; fireserver = hookfunction(waxfireserver, function(self, ...)
    if not checkcaller() and self:IsA('RemoteEvent') and select(1, ...) == parrydata.uuid and select(2, ...) == parrydata.hash then
        --print('INDEXCALL', ...)
        hookfunction(waxfireserver, fireserver)
        remoteyield:Fire(self)
    end
        
    return fireserver(self, ...)
end)


local remote = remoteyield.Event:Wait()
local function Parry(cf)
    local camera = workspace.CurrentCamera
    if not camera then  --do note that it is not possible for execution to be stopped until the script yields, so existance only needs to be checked for once
        return
    end
    remote:FireServer(parrydata.uuid, parrydata.hash, 0.5, cf or camera.CFrame, {}, {camera.ViewportSize.X/2, camera.ViewportSize.Y/2}, false)
end

return Parry
