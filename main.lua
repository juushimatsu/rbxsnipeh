-- Проверяем чтобы не запустить дважды
if getgenv().__ENI_RUNNING then return end
getgenv().__ENI_RUNNING = true

print("!!! ENI V27 START !!!")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local trackedModels = {}
local enemyHolder = nil
local friendlyHolder = nil
local heartbeatConn = nil
local scanRunning = false

local function Cleanup()
    for model, _ in pairs(trackedModels) do
        if model then
            local hl = model:FindFirstChild("ENI_HL")
            if hl then hl:Destroy() end
        end
    end
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
    if model == lp.Character then return true end
    if model:IsDescendantOf(workspace.CurrentCamera) then return true end
    if enemyHolder and model:IsDescendantOf(enemyHolder) then return false end
    if friendlyHolder and model:IsDescendantOf(friendlyHolder) then return true end
    local p = Players:GetPlayerFromCharacter(model)
    if p then
        if p == lp then return true end
        if enemyHolder and enemyHolder:FindFirstChild(p.Name) then return false end
        if friendlyHolder and friendlyHolder:FindFirstChild(p.Name) then return true end
        return true
    end
    return true
end

local function SetHighlight(model, enable)
    local hl = model:FindFirstChild("ENI_HL")
    if enable then
        if not hl then
            hl = Instance.new("Highlight")
            hl.Name = "ENI_HL"
            hl.Parent = model
            hl.FillColor = Color3.fromRGB(255, 0, 0)
            hl.OutlineColor = Color3.fromRGB(255, 255, 255)
            hl.FillTransparency = 0.5
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        end
    else
        if hl then hl:Destroy() end
    end
end

local function StartESP()
    print("ENI: ESP запущен")
    Cleanup()

    if heartbeatConn then heartbeatConn:Disconnect() end
    heartbeatConn = RunService.Heartbeat:Connect(function()
        GetHolders()
        for model, _ in pairs(trackedModels) do
            if not model or not model.Parent then
                local hl = model and model:FindFirstChild("ENI_HL")
                if hl then hl:Destroy() end
                trackedModels[model] = nil
            else
                local hum = model:FindFirstChildOfClass("Humanoid")
                local alive = hum and hum.Health > 0
                SetHighlight(model, alive and not IsFriendly(model))
            end
        end
    end)

    if not scanRunning then
        scanRunning = true
        task.spawn(function()
            while task.wait(2) do
                GetHolders()
                for _, obj in pairs(workspace:GetDescendants()) do
                    if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
                        trackedModels[obj] = true
                    end
                end
                for _, p in pairs(Players:GetPlayers()) do
                    local char = p.Character
                    if char and char:FindFirstChildOfClass("Humanoid") then
                        trackedModels[char] = true
                    end
                end
            end
        end)
    end

    Players.PlayerAdded:Connect(function(p)
        p.CharacterAdded:Connect(function(char)
            trackedModels[char] = true
        end)
    end)
end

local function WatchForRound()
    while true do
        local highlight = workspace:WaitForChild("Highlight", 999)
        local enemy = highlight:WaitForChild("Enemy", 999)
        enemy:WaitForChild("HighlightHolder", 999)
        print("ENI: Обнаружен новый раунд")
        task.wait(1)
        StartESP()
        while enemy and enemy.Parent do
            task.wait(2)
        end
        print("ENI: Раунд закончен, ожидаем следующий...")
        Cleanup()
        scanRunning = false
    end
end

-- Авто-перезапуск после телепорта
task.spawn(function()
    while true do
        task.wait(1)
        -- Если игра перезагрузилась (телепорт) — сбрасываем флаг и перезапускаем
        if not game:IsLoaded() then
            getgenv().__ENI_RUNNING = false
            Cleanup()
            if heartbeatConn then
                heartbeatConn:Disconnect()
                heartbeatConn = nil
            end
            -- Ждём загрузки
            game.Loaded:Wait()
            task.wait(3)
            -- Перезапускаем
            getgenv().__ENI_RUNNING = true
            lp = Players.LocalPlayer
            scanRunning = false
            trackedModels = {}
            print("ENI: Перезапуск после телепорта")
            task.spawn(WatchForRound)
        end
    end
end)

task.spawn(WatchForRound)
print("!!! ENI V27 LOADED !!!")
