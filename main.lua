-- ENI V29 — ESP
-- Защита от двойного запуска
if getgenv().__ENI_RUNNING then
    warn("ENI: Уже запущен, пропускаем")
    return
end
getgenv().__ENI_RUNNING = true

-- Авто-перезапуск после телепорта (регаем прямо тут, до всего остального)
local queueTP = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
if queueTP then
    queueTP([[
        task.wait(3)
        loadstring(game:HttpGet("https://raw.githubusercontent.com/juushimatsu/rbxsnipeh/refs/heads/main/main.lua"))()
    ]])
    print("ENI: queue_on_teleport зарегистрирован")
else
    warn("ENI: queue_on_teleport НЕ поддерживается")
end

print("!!! ENI V29 START !!!")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

-- Ждём загрузки игры и персонажа
if not game:IsLoaded() then game.Loaded:Wait() end
if not lp then lp = Players:GetPropertyChangedSignal("LocalPlayer"):Wait(); lp = Players.LocalPlayer end
task.wait(1)

local trackedModels = {}
local enemyHolder = nil
local friendlyHolder = nil
local heartbeatConn = nil
local scanRunning = false
local connections = {} -- для отключения при cleanup

local function DisconnectAll()
    if heartbeatConn then
        pcall(function() heartbeatConn:Disconnect() end)
        heartbeatConn = nil
    end
    for _, conn in ipairs(connections) do
        pcall(function() conn:Disconnect() end)
    end
    connections = {}
end

local function Cleanup()
    pcall(function()
        for model, _ in pairs(trackedModels) do
            if model then
                pcall(function()
                    local hl = model:FindFirstChild("ENI_HL")
                    if hl then hl:Destroy() end
                end)
            end
        end
    end)
    trackedModels = {}
    enemyHolder = nil
    friendlyHolder = nil
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

    if enemyHolder and enemyHolder.Parent then
        if model:IsDescendantOf(enemyHolder) then return false end
    end
    if friendlyHolder and friendlyHolder.Parent then
        if model:IsDescendantOf(friendlyHolder) then return true end
    end

    local p = Players:GetPlayerFromCharacter(model)
    if p then
        if p == lp then return true end
        if enemyHolder and enemyHolder.Parent and enemyHolder:FindFirstChild(p.Name) then return false end
        if friendlyHolder and friendlyHolder.Parent and friendlyHolder:FindFirstChild(p.Name) then return true end
        return true
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

local function ScanForModels()
    pcall(function()
        -- Персонажи игроков
        for _, p in ipairs(Players:GetPlayers()) do
            local char = p.Character
            if char and char.Parent and char:FindFirstChildOfClass("Humanoid") then
                trackedModels[char] = true
            end
        end

        -- Модели из holders
        if enemyHolder and enemyHolder.Parent then
            for _, child in ipairs(enemyHolder:GetChildren()) do
                if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
                    trackedModels[child] = true
                end
            end
        end

        -- Прямые дети workspace + один уровень вглубь
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
                trackedModels[obj] = true
            end
            if obj:IsA("Folder") or (obj:IsA("Model") and not obj:FindFirstChildOfClass("Humanoid")) then
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

local function StartESP()
    print("ENI: ESP запущен")
    Cleanup()
    DisconnectAll()

    -- Heartbeat — обновление подсветки каждый кадр
    heartbeatConn = RunService.Heartbeat:Connect(function()
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

    -- Сканер моделей
    if not scanRunning then
        scanRunning = true
        task.spawn(function()
            while scanRunning do
                task.wait(2)
                ScanForModels()
            end
        end)
    end

    -- Подписка на новых игроков
    local conn = Players.PlayerAdded:Connect(function(p)
        p.CharacterAdded:Connect(function(char)
            task.wait(0.5)
            if char and char.Parent then
                trackedModels[char] = true
            end
        end)
    end)
    table.insert(connections, conn)

    -- Существующие игроки — подписка на респавн
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then
            trackedModels[p.Character] = true
        end
        local c = p.CharacterAdded:Connect(function(char)
            task.wait(0.5)
            if char and char.Parent then
                trackedModels[char] = true
            end
        end)
        table.insert(connections, c)
    end

    -- Первый скан сразу
    ScanForModels()
end

local function WatchForRound()
    while true do
        local ok, err = pcall(function()
            local highlight = workspace:WaitForChild("Highlight", 9999)
            if not highlight then return end

            local enemy = highlight:WaitForChild("Enemy", 9999)
            if not enemy then return end

            local holder = enemy:WaitForChild("HighlightHolder", 9999)
            if not holder then return end

            print("ENI: Обнаружен раунд, запускаем ESP")
            task.wait(1)
            StartESP()

            -- Ждём конца раунда (holder или enemy удалится)
            while enemy and enemy.Parent and holder and holder.Parent do
                task.wait(2)
            end

            print("ENI: Раунд закончен")
            Cleanup()
            DisconnectAll()
            scanRunning = false
        end)

        if not ok then
            warn("ENI: Ошибка: " .. tostring(err))
            Cleanup()
            DisconnectAll()
            scanRunning = false
            task.wait(5)
        end

        task.wait(1)
    end
end

task.spawn(WatchForRound)
print("!!! ENI V29 LOADED !!!")
