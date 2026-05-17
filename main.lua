-- ENI V31 — ESP
-- Если уже запущен — убиваем старый инстанс и перезапускаем
if getgenv().__ENI_STOP then
    getgenv().__ENI_STOP()
end

print("!!! ENI V31 START !!!")

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
local alive = true -- флаг жизни этого инстанса
local allConnections = {}

-- Функция остановки (вызывается при повторном execute)
getgenv().__ENI_STOP = function()
    alive = false
    for _, conn in ipairs(allConnections) do
        pcall(function() conn:Disconnect() end)
    end
    allConnections = {}
    -- Убираем все подсветки
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
    print("ENI: Старый инстанс остановлен")
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

    -- Камера
    local cam = workspace:FindFirstChildOfClass("Camera")
    if cam and model:IsDescendantOf(cam) then return true end

    -- Проверяем holders (если они существуют = раунд идёт)
    local holdersExist = (enemyHolder and enemyHolder.Parent) or (friendlyHolder and friendlyHolder.Parent)

    if not holdersExist then
        -- Нет holders = лобби или режим без команд — не подсвечиваем никого
        return true
    end

    -- Модель напрямую в friendlyHolder — дружественный бот
    if friendlyHolder and friendlyHolder.Parent then
        if model:IsDescendantOf(friendlyHolder) then return true end
    end

    -- Модель напрямую в enemyHolder — враг
    if enemyHolder and enemyHolder.Parent then
        if model:IsDescendantOf(enemyHolder) then return false end
    end

    -- Проверяем игрока по имени в holders
    local p = Players:GetPlayerFromCharacter(model)
    if p then
        if p == lp then return true end

        -- Ищем в friendly
        if friendlyHolder and friendlyHolder.Parent then
            if friendlyHolder:FindFirstChild(p.Name) then return true end
        end

        -- Ищем в enemy
        if enemyHolder and enemyHolder.Parent then
            if enemyHolder:FindFirstChild(p.Name) then return false end
        end

        -- Игрок не найден ни в одном holder — НЕ подсвечиваем (безопасно)
        return true
    end

    -- NPC/бот не в holders напрямую — проверяем по полному пути
    local fullName = model:GetFullName()
    if fullName:find("Highlight") and fullName:find("Enemy") then return false end
    if fullName:find("Highlight") and fullName:find("Friendly") then return true end

    -- Неизвестная модель — не подсвечиваем
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
local hbConn = RunService.Heartbeat:Connect(function()
    if not alive then return end
    pcall(function()
        GetHolders()

        local toRemove = {}
        for model, _ in pairs(trackedModels) do
            if not model or not model.Parent then
                table.insert(toRemove, model)
            else
                local ok, hum = pcall(function() return model:FindFirstChildOfClass("Humanoid") end)
                if ok and hum then
                    local isAlive = hum.Health > 0
                    SetHighlight(model, isAlive and not IsFriendly(model))
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
table.insert(allConnections, hbConn)

-- === СКАНЕР ===
task.spawn(function()
    while alive do
        task.wait(2)
        if not alive then break end
        pcall(function()
            GetHolders()

            -- Персонажи игроков
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

            -- Модели из friendly holder (чтобы корректно определять friendly)
            if friendlyHolder and friendlyHolder.Parent then
                for _, child in ipairs(friendlyHolder:GetChildren()) do
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

-- === Подписка на игроков ===
local function TrackPlayer(p)
    if p.Character and p.Character:FindFirstChildOfClass("Humanoid") then
        trackedModels[p.Character] = true
    end
    local conn = p.CharacterAdded:Connect(function(char)
        task.wait(0.5)
        if alive and char and char.Parent then
            trackedModels[char] = true
        end
    end)
    table.insert(allConnections, conn)
end

for _, p in ipairs(Players:GetPlayers()) do
    TrackPlayer(p)
end

local paConn = Players.PlayerAdded:Connect(function(p)
    if alive then TrackPlayer(p) end
end)
table.insert(allConnections, paConn)

print("!!! ENI V31 LOADED — ESP ACTIVE !!!")
