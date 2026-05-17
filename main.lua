-- ENI V28 — ESP with crash protection
if getgenv().__ENI_RUNNING then return end
getgenv().__ENI_RUNNING = true

print("!!! ENI V28 START !!!")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local trackedModels = {}
local enemyHolder = nil
local friendlyHolder = nil
local heartbeatConn = nil
local scanRunning = false

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
    if enemyHolder and enemyHolder.Parent then return end
    local hl = workspace:FindFirstChild("Highlight")
    if not hl then return end
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

    if enemyHolder and enemyHolder.Parent and model:IsDescendantOf(enemyHolder) then return false end
    if friendlyHolder and friendlyHolder.Parent and model:IsDescendantOf(friendlyHolder) then return true end

    local p = Players:GetPlayerFromCharacter(model)
    if p then
        if p == lp then return true end
        if enemyHolder and enemyHolder.Parent then
            if enemyHolder:FindFirstChild(p.Name) then return false end
        end
        if friendlyHolder and friendlyHolder.Parent then
            if friendlyHolder:FindFirstChild(p.Name) then return true end
        end
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
            local s, newHl = pcall(function()
                local h = Instance.new("Highlight")
                h.Name = "ENI_HL"
                h.FillColor = Color3.fromRGB(255, 0, 0)
                h.OutlineColor = Color3.fromRGB(255, 255, 255)
                h.FillTransparency = 0.5
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.Parent = model
                return h
            end)
        end
    else
        if hl then
            pcall(function() hl:Destroy() end)
        end
    end
end

local function StartESP()
    print("ENI: ESP запущен")
    Cleanup()

    if heartbeatConn then
        pcall(function() heartbeatConn:Disconnect() end)
    end

    heartbeatConn = RunService.Heartbeat:Connect(function()
        pcall(function()
            GetHolders()

            -- Собираем список для удаления отдельно, чтобы не менять таблицу во время итерации
            local toRemove = {}
            for model, _ in pairs(trackedModels) do
                if not model or not model.Parent then
                    table.insert(toRemove, model)
                else
                    local ok, hum = pcall(function() return model:FindFirstChildOfClass("Humanoid") end)
                    if ok and hum then
                        local alive = hum.Health > 0
                        local friendly = IsFriendly(model)
                        SetHighlight(model, alive and not friendly)
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

    if not scanRunning then
        scanRunning = true
        task.spawn(function()
            while scanRunning do
                task.wait(3) -- Увеличен интервал для снижения нагрузки

                pcall(function()
                    GetHolders()

                    -- Сканируем только детей первого уровня + персонажей игроков
                    -- вместо GetDescendants() который крашит на больших картах
                    for _, p in ipairs(Players:GetPlayers()) do
                        local char = p.Character
                        if char and char.Parent and char:FindFirstChildOfClass("Humanoid") then
                            trackedModels[char] = true
                        end
                    end

                    -- Сканируем holders напрямую если они есть
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

                    -- Ограниченный скан workspace (только прямые дети)
                    for _, obj in ipairs(workspace:GetChildren()) do
                        if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
                            trackedModels[obj] = true
                        end
                        -- Один уровень вглубь для папок
                        if obj:IsA("Folder") or obj:IsA("Model") then
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
    end

    -- Новые игроки
    Players.PlayerAdded:Connect(function(p)
        p.CharacterAdded:Connect(function(char)
            task.wait(1)
            if char and char.Parent then
                trackedModels[char] = true
            end
        end)
    end)

    -- Существующие игроки
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then
            trackedModels[p.Character] = true
        end
        p.CharacterAdded:Connect(function(char)
            task.wait(1)
            if char and char.Parent then
                trackedModels[char] = true
            end
        end)
    end
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

            print("ENI: Обнаружен новый раунд")
            task.wait(1)
            StartESP()

            -- Ждём конца раунда
            while enemy and enemy.Parent do
                task.wait(2)
            end

            print("ENI: Раунд закончен, ожидаем следующий...")
            Cleanup()
            scanRunning = false
        end)

        if not ok then
            warn("ENI: Ошибка в WatchForRound: " .. tostring(err))
            task.wait(5)
            Cleanup()
            scanRunning = false
        end

        task.wait(1)
    end
end

task.spawn(WatchForRound)
print("!!! ENI V28 LOADED !!!")
