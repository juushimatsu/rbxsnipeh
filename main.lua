-- ENI V30 — ESP (запускается сразу, не ждёт раунд)
if getgenv().__ENI_RUNNING then
    warn("ENI: Уже запущен, пропускаем")
    return
end
getgenv().__ENI_RUNNING = true

print("!!! ENI V30 START !!!")

-- queue_on_teleport
local queueTP = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
if queueTP then
    queueTP([[task.wait(3) loadstring(game:HttpGet("https://raw.githubusercontent.com/juushimatsu/rbxsnipeh/refs/heads/main/main.lua"))()]])
    print("ENI: queue_on_teleport OK")
else
    warn("ENI: queue_on_teleport не поддерживается")
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(1)

local lp = Players.LocalPlayer
local trackedModels = {}
local enemyHolder = nil
local friendlyHolder = nil

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

    -- Камера
    local cam = workspace:FindFirstChildOfClass("Camera")
    if cam and model:IsDescendantOf(cam) then return true end

    -- Если holders есть — используем их
    if enemyHolder and enemyHolder.Parent then
        if model:IsDescendantOf(enemyHolder) then return false end
    end
    if friendlyHolder and friendlyHolder.Parent then
        if model:IsDescendantOf(friendlyHolder) then return true end
    end

    -- Проверяем по имени игрока в holders
    local p = Players:GetPlayerFromCharacter(model)
    if p then
        if p == lp then return true end
        if enemyHolder and enemyHolder.Parent and enemyHolder:FindFirstChild(p.Name) then return false end
        if friendlyHolder and friendlyHolder.Parent and friendlyHolder:FindFirstChild(p.Name) then return true end
        -- Игрок есть, но не в holders — считаем врагом (в раунде все кроме тиммейтов враги)
        -- Если holders вообще нет — не подсвечиваем (лобби)
        if enemyHolder and enemyHolder.Parent then
            return false -- раунд идёт, но игрока нет в friendly = враг
        end
        return true -- holders нет = лобби, не подсвечиваем
    end

    -- NPC/бот — если в enemyHolder или просто модель с Humanoid
    -- Если holders есть и модель не в friendly — враг
    if enemyHolder and enemyHolder.Parent then
        return false
    end

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

-- === HEARTBEAT: обновляем подсветку каждый кадр ===
RunService.Heartbeat:Connect(function()
    pcall(function()
        GetHolders()

        local toRemove = {}
        for model, _ in pairs(trackedModels) do
            if not model or not model.Parent then
                table.insert(toRemove, model)
            else
                local ok, hum = pcall(function() return model:FindFirstChildOfClass("Humanoid") end)
                if ok and hum then
                    local alive = hum.Health > 0
                    SetHighlight(model, alive and not IsFriendly(model))
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

-- === СКАНЕР: ищем модели каждые 2 секунды ===
task.spawn(function()
    while true do
        task.wait(2)
        pcall(function()
            -- Персонажи всех игроков
            for _, p in ipairs(Players:GetPlayers()) do
                local char = p.Character
                if char and char.Parent and char:FindFirstChildOfClass("Humanoid") then
                    trackedModels[char] = true
                end
            end

            -- Модели из enemy holder
            if enemyHolder and enemyHolder.Parent then
                for _, child in ipairs(enemyHolder:GetChildren()) do
                    if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
                        trackedModels[child] = true
                    end
                end
            end

            -- Workspace: прямые дети + один уровень вглубь папок
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

-- === Подписка на новых игроков и респавн ===
local function TrackPlayer(p)
    if p.Character and p.Character:FindFirstChildOfClass("Humanoid") then
        trackedModels[p.Character] = true
    end
    p.CharacterAdded:Connect(function(char)
        task.wait(0.5)
        if char and char.Parent then
            trackedModels[char] = true
        end
    end)
end

for _, p in ipairs(Players:GetPlayers()) do
    TrackPlayer(p)
end
Players.PlayerAdded:Connect(TrackPlayer)

print("!!! ENI V30 LOADED — ESP ACTIVE !!!")
