	-- ENI V34 — ESP for Velocity
print("ENI V34: Скрипт начал выполнение")

-- Убиваем старый инстанс
pcall(function()
    if _G._ENI_ALIVE then
        _G._ENI_ALIVE.Value = false
        print("ENI: Старый инстанс остановлен")
    end
end)

-- Чистим старые подсветки
pcall(function()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Highlight") and obj.Name == "ENI_HL" then
            obj:Destroy()
        end
    end
end)

-- Флаг жизни
local aliveFlag = Instance.new("BoolValue")
aliveFlag.Value = true
_G._ENI_ALIVE = aliveFlag

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- НЕ ждём game:IsLoaded() — после телепорта игра уже загружена
-- Просто маленькая пауза
task.wait(0.5)

local lp = Players.LocalPlayer
if not lp then
    print("ENI: Ждём LocalPlayer...")
    lp = Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    lp = Players.LocalPlayer
end

print("ENI: LocalPlayer = " .. tostring(lp))

local trackedModels = {}
local enemyHolder = nil
local friendlyHolder = nil

local function IsAlive()
    return aliveFlag and aliveFlag.Value == true
end

local function GetHolders()
    local hl = workspace:FindFirstChild("Highlight")
    if not hl then
        enemyHolder = nil
        friendlyHolder = nil
        return
    end
    local e = hl:FindFirstChild("Enemy")
    local f = hl:FindFirstChild("Friendly")
    enemyHolder = e and e:FindFirstChild("HighlightHolder")
    friendlyHolder = f and f:FindFirstChild("HighlightHolder")
end

local function IsFriendly(model)
    if not model or not model.Parent then return true end
    if model == lp.Character then return true end

    local cam = workspace:FindFirstChildOfClass("Camera")
    if cam and model:IsDescendantOf(cam) then return true end

    local holdersExist = (enemyHolder and enemyHolder.Parent) or (friendlyHolder and friendlyHolder.Parent)
    if not holdersExist then
        return true
    end

    if friendlyHolder and friendlyHolder.Parent then
        if model:IsDescendantOf(friendlyHolder) then return true end
    end

    if enemyHolder and enemyHolder.Parent then
        if model:IsDescendantOf(enemyHolder) then return false end
    end

    local p = Players:GetPlayerFromCharacter(model)
    if p then
        if p == lp then return true end
        if friendlyHolder and friendlyHolder.Parent and friendlyHolder:FindFirstChild(p.Name) then return true end
        if enemyHolder and enemyHolder.Parent and enemyHolder:FindFirstChild(p.Name) then return false end
        return true
    end

    local fullName = model:GetFullName()
    if fullName:find("Enemy") then return false end
    if fullName:find("Friendly") then return true end

    return true
end

local function SetHighlight(model, enable)
    if not model or not model.Parent then return end
    local ok, hl = pcall(function() return model:FindFirstChild("ENI_HL") end)
    if not ok then return end

    if enable then
        if not hl then
            pcall(function()
                local h = Instance.new("Highlight")
                h.Name = "ENI_HL"
                h.FillColor = Color3.fromRGB(255, 0, 0)
                h.OutlineColor = Color3.fromRGB(255, 255, 255)
                h.FillTransparency = 0.5
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.Parent = model
            end)
        end
    else
        if hl then
            pcall(function() hl:Destroy() end)
        end
    end
end

-- === HEARTBEAT ===
RunService.Heartbeat:Connect(function()
    if not IsAlive() then return end
    pcall(function()
        GetHolders()

        local toRemove = {}
        for model, _ in pairs(trackedModels) do
            if not model or not model.Parent then
                table.insert(toRemove, model)
            else
                local ok, hum = pcall(function() return model:FindFirstChildOfClass("Humanoid") end)
                if ok and hum then
                    local hp = hum.Health > 0
                    SetHighlight(model, hp and not IsFriendly(model))
                else
                    SetHighlight(model, false)
                end
            end
        end

        for _, model in ipairs(toRemove) do
            pcall(function()
                if model then
                    local hl = model:FindFirstChild("ENI_HL")
                    if hl then hl:Destroy() end
                end
            end)
            trackedModels[model] = nil
        end
    end)
end)

-- === СКАНЕР ===
task.spawn(function()
    while IsAlive() do
        task.wait(2)
        if not IsAlive() then break end
        pcall(function()
            GetHolders()

            for _, p in ipairs(Players:GetPlayers()) do
                local char = p.Character
                if char and char.Parent and char:FindFirstChildOfClass("Humanoid") then
                    trackedModels[char] = true
                end
            end

            if enemyHolder and enemyHolder.Parent then
                for _, child in ipairs(enemyHolder:GetChildren()) do
                    if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
                        trackedModels[child] = true
                    end
                end
            end

            if friendlyHolder and friendlyHolder.Parent then
                for _, child in ipairs(friendlyHolder:GetChildren()) do
                    if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
                        trackedModels[child] = true
                    end
                end
            end

            for _, obj in ipairs(workspace:GetChildren()) do
                if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
                    trackedModels[obj] = true
                end
                if obj:IsA("Folder") then
                    pcall(function()
                        for _, sub in ipairs(obj:GetChildren()) do
                            if sub:IsA("Model") and sub:FindFirstChildOfClass("Humanoid") then
                                trackedModels[sub] = true
                            end
                        end
                    end)
                end
            end
        end)
    end
end)

-- === Подписка на игроков ===
local function TrackPlayer(p)
    if p.Character and p.Character:FindFirstChildOfClass("Humanoid") then
        trackedModels[p.Character] = true
    end
    p.CharacterAdded:Connect(function(char)
        task.wait(0.5)
        if IsAlive() and char and char.Parent then
            trackedModels[char] = true
        end
    end)
end

for _, p in ipairs(Players:GetPlayers()) do
    TrackPlayer(p)
end
Players.PlayerAdded:Connect(function(p)
    if IsAlive() then TrackPlayer(p) end
end)

print("!!! ENI V34 LOADED — ESP ACTIVE !!!")
