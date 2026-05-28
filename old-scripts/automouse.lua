-- ENI COMBAT V3 — Fast Response & LMB Focus
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera
local lp = Players.LocalPlayer

-- === КОНФИГУРАЦИЯ ===
local Config = {
    AimbotEnabled = false,
    HoldToAim = true,
    AimKey = Enum.UserInputType.MouseButton1,
    FovRadius = 150,
    Smoothness = 3,
    AutoFire = false,
    FireDelay = 0.0,
    AimDelay = 0.0,
    ShowFov = true,
    VisibleCheck = true,
    MenuOpen = true,
    BlockShot = true -- блокировка нативного выстрела когда aimbot активен
}

-- === СОСТОЯНИЕ ===
local aimActive = false
local lmbHeld = false
local shotAllowed = true
local aimDelayTimer = 0

-- === FOV КРУГ ===
local FovCircle = Drawing.new("Circle")
FovCircle.Thickness = 1
FovCircle.Color = Color3.fromRGB(255, 0, 0)
FovCircle.Transparency = 0.8
FovCircle.Filled = false

-- === СИСТЕМА КЕШИРОВАНИЯ ЦЕЛЕЙ ===
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

task.spawn(function()
    while true do
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

        task.wait(1)
    end
end)

-- === ПРОВЕРКА ВИДИМОСТИ ===
local function IsVisible(part, character)
    if not Config.VisibleCheck then return true end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {lp.Character, Camera}

    local result = workspace:Raycast(Camera.CFrame.Position, (part.Position - Camera.CFrame.Position).Unit * 1000, params)
    return result and result.Instance:IsDescendantOf(character)
end

-- === ПОИСК ЦЕЛИ ===
local function GetClosestTarget()
    local closestTarget = nil
    local shortestDistance = Config.FovRadius
    local mousePos = UserInputService:GetMouseLocation()

    for model, _ in pairs(trackedModels) do
        if model and model.Parent and model:FindFirstChild("Head") and model:FindFirstChild("Humanoid") then
            if model.Humanoid.Health > 0 and not IsFriendly(model) then
                local head = model.Head
                local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position)

                if onScreen then
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    if dist < shortestDistance then
                        if IsVisible(head, model) then
                            shortestDistance = dist
                            closestTarget = head
                        end
                    end
                end
            end
        end
    end
    return closestTarget
end

-- === ПЕРЕХВАТ ЛКМ ===
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        lmbHeld = true

        if Config.AimbotEnabled and Config.HoldToAim then
            -- Сбрасываем таймер задержки
            aimDelayTimer = Config.AimDelay

            -- Блокируем нативный выстрел если включен BlockShot
            if Config.BlockShot and not gameProcessed then
                return
            end
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        lmbHeld = false
        shotAllowed = true
    end
end)

-- === ГЛАВНЫЙ ЦИКЛ ===
RunService.RenderStepped:Connect(function(dt)
    FovCircle.Visible = Config.ShowFov
    FovCircle.Radius = Config.FovRadius
    FovCircle.Position = UserInputService:GetMouseLocation()

    if Config.AimbotEnabled then
        local shouldAim = not Config.HoldToAim or lmbHeld

        -- Уменьшаем таймер задержки
        if aimDelayTimer > 0 then
            aimDelayTimer = aimDelayTimer - dt
            shouldAim = false
        end

        if shouldAim then
            local target = GetClosestTarget()
            if target then
                local targetPos = Camera:WorldToViewportPoint(target.Position)
                local mousePos = UserInputService:GetMouseLocation()

                local moveX = (targetPos.X - mousePos.X) / Config.Smoothness
                local moveY = (targetPos.Y - mousePos.Y) / Config.Smoothness

                mousemoverel(moveX, moveY)

                -- Авто-выстрел с задержкой
                if Config.AutoFire and shotAllowed then
                    shotAllowed = false
                    if Config.FireDelay > 0 then
                        task.delay(Config.FireDelay, function()
                            mouse1press()
                            task.wait(0.01)
                            mouse1release()
                            shotAllowed = true
                        end)
                    else
                        mouse1press()
                        task.wait(0.01)
                        mouse1release()
                        shotAllowed = true
                    end
                end
            end
        end
    end
end)

-- === МЕНЮ (GUI) ===
local ScreenGui = Instance.new("ScreenGui", game.CoreGui)
local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size = UDim2.new(0, 260, 0, 420)
MainFrame.Position = UDim2.new(0.5, -130, 0.5, -210)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
MainFrame.Visible = Config.MenuOpen
MainFrame.Active = true
MainFrame.Draggable = true

local Title = Instance.new("TextLabel", MainFrame)
Title.Size = UDim2.new(1, 0, 0, 40)
Title.Text = "ENI COMBAT V3 (LMB)"
Title.TextColor3 = Color3.new(1, 1, 1)
Title.BackgroundColor3 = Color3.fromRGB(40, 40, 40)

local function CreateToggle(name, prop, pos)
    local btn = Instance.new("TextButton", MainFrame)
    btn.Size = UDim2.new(0.9, 0, 0, 30)
    btn.Position = UDim2.new(0.05, 0, 0, pos)
    btn.Text = name .. ": " .. (Config[prop] and "ON" or "OFF")
    btn.BackgroundColor3 = Config[prop] and Color3.fromRGB(0, 100, 0) or Color3.fromRGB(100, 0, 0)

    btn.MouseButton1Click:Connect(function()
        Config[prop] = not Config[prop]
        btn.Text = name .. ": " .. (Config[prop] and "ON" or "OFF")
        btn.BackgroundColor3 = Config[prop] and Color3.fromRGB(0, 100, 0) or Color3.fromRGB(100, 0, 0)
    end)
end

local function CreateSlider(name, prop, min, max, pos)
    local label = Instance.new("TextLabel", MainFrame)
    label.Size = UDim2.new(0.9, 0, 0, 20)
    label.Position = UDim2.new(0.05, 0, 0, pos)
    label.Text = name .. ": " .. Config[prop]
    label.TextColor3 = Color3.new(1, 1, 1)
    label.BackgroundTransparency = 1

    local btn = Instance.new("TextButton", MainFrame)
    btn.Size = UDim2.new(0.9, 0, 0, 10)
    btn.Position = UDim2.new(0.05, 0, 0, pos + 20)
    btn.Text = ""

    btn.MouseButton1Click:Connect(function()
        if Config[prop] >= max then Config[prop] = min else Config[prop] = Config[prop] + (max/10) end
        label.Text = name .. ": " .. math.floor(Config[prop] * 10) / 10
    end)
end

CreateToggle("Enable Aimbot", "AimbotEnabled", 50)
CreateToggle("Hold LMB to Aim", "HoldToAim", 90)
CreateToggle("Auto Fire", "AutoFire", 130)
CreateToggle("Block Native Shot", "BlockShot", 170)
CreateSlider("Fire Delay (s)", "FireDelay", 0, 0.5, 210)
CreateSlider("Aim Delay (s)", "AimDelay", 0, 1, 255)
CreateSlider("FOV Size", "FovRadius", 50, 600, 300)
CreateSlider("Smoothing (Low = Fast)", "Smoothness", 1, 20, 345)
CreateToggle("Show FOV", "ShowFov", 390)
CreateToggle("Wall Check", "VisibleCheck", 430)

UserInputService.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.Insert then
        Config.MenuOpen = not Config.MenuOpen
        MainFrame.Visible = Config.MenuOpen
    end
end)

print("!!! ENI COMBAT V3 LOADED — LMB MODE !!!")