-- ENI Unified Hub
print("ENI Unified Hub: starting...")

-- ============================================================
-- SERVICES
-- ============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera

-- ============================================================
-- SHUTDOWN PREVIOUS INSTANCE
-- ============================================================
pcall(function()
    if _G._ENI_ALIVE then _G._ENI_ALIVE.Value = false end
end)

pcall(function()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Highlight") and obj.Name == "ENI_HL" then obj:Destroy() end
    end
end)

local aliveFlag = Instance.new("BoolValue")
aliveFlag.Value = true
_G._ENI_ALIVE = aliveFlag

task.wait(0.5)

local lp = Players.LocalPlayer
if not lp then
    lp = Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    lp = Players.LocalPlayer
end

print("ENI: LocalPlayer = " .. tostring(lp))

-- ============================================================
-- CONFIGS
-- ============================================================
local AimConfig = {
    AimbotEnabled = false,
    HoldToAim = true,
    FovRadius = 150,
    Smoothness = 3,
    AutoFire = false,
    FireDelay = 0.0,
    AimDelay = 0.0,
    ShowFov = true,
    VisibleCheck = true,
    BlockShot = true,
}

local ESPConfig = {
    Enabled = false,
    FillColor = Color3.fromRGB(255, 0, 0),
    OutlineColor = Color3.fromRGB(255, 255, 255),
    FillTransparency = 0.5,
}

local TPConfig = {
    Enabled = false,
    Distance = 18,
    Offset = Vector3.new(3, 2, 0),
    Sensitivity = 0.5,
}

local MenuConfig = {
    MenuOpen = true,
    ActiveTab = "Aim",
}
local MainFrame = nil

-- ============================================================
-- SHARED STATE
-- ============================================================
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
    if not lp or not lp.Character then return true end
    if model == lp.Character then return true end
    local cam = workspace:FindFirstChildOfClass("Camera")
    if cam and model:IsDescendantOf(cam) then return true end
    local holdersExist = (enemyHolder and enemyHolder.Parent) or (friendlyHolder and friendlyHolder.Parent)
    if not holdersExist then return true end
    if friendlyHolder and friendlyHolder.Parent and model:IsDescendantOf(friendlyHolder) then return true end
    if enemyHolder and enemyHolder.Parent and model:IsDescendantOf(enemyHolder) then return false end
    local p = Players:GetPlayerFromCharacter(model)
    if p then
        if p == lp then return true end
        if friendlyHolder and friendlyHolder:FindFirstChild(p.Name) then return true end
        if enemyHolder and enemyHolder:FindFirstChild(p.Name) then return false end
        return true
    end
    local fullName = model:GetFullName()
    if fullName:find("Enemy") then return false end
    if fullName:find("Friendly") then return true end
    return true
end

local function IsVisible(part, character)
    if not AimConfig.VisibleCheck then return true end
    if not lp or not lp.Character then return false end
    if not Camera then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {lp.Character, Camera}
    local result = workspace:Raycast(Camera.CFrame.Position, (part.Position - Camera.CFrame.Position).Unit * 1000, params)
    return result and result.Instance:IsDescendantOf(character)
end

-- ============================================================
-- AIMBOT STATE
-- ============================================================
local lmbHeld = false
local shotAllowed = true
local aimDelayTimer = 0

local FovCircle = Drawing.new("Circle")
FovCircle.Thickness = 1
FovCircle.Color = Color3.fromRGB(255, 0, 0)
FovCircle.Transparency = 0.8
FovCircle.Filled = false

local function GetClosestTarget()
    if not lp or not lp.Character then return nil end
    if not Camera then return nil end
    local closestTarget = nil
    local shortestDistance = AimConfig.FovRadius
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

-- ============================================================
-- THIRDPERSON STATE
-- ============================================================
local tpActive = false
local tpYaw = 0
local tpPitch = 0

local function forceDisableTP()
    tpActive = false
    if Camera then Camera.CameraType = Enum.CameraType.Custom end
    if lp then lp.CameraMode = Enum.CameraMode.LockFirstPerson end
    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

local function updateThirdPersonCamera()
    if not tpActive then return end
    if not lp or not lp.Character then return end
    local root = lp.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local rotation = CFrame.Angles(0, math.rad(tpYaw), 0) * CFrame.Angles(math.rad(tpPitch), 0, 0)
    local targetCFrame = CFrame.new(root.Position) * rotation * CFrame.new(TPConfig.Offset.X, TPConfig.Offset.Y, TPConfig.Distance)
    Camera.CFrame = targetCFrame
    root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, math.rad(tpYaw), 0)
    for _, part in pairs(lp.Character:GetDescendants()) do
        if part:IsA("BasePart") then part.LocalTransparencyModifier = 0 end
    end
end

-- Watch TPConfig.Enabled — force-disable when toggled OFF in menu
local tpEnabledChanged = false
local tpEnabledmt = {__index = TPConfig}
tpEnabledmt.__newindex = function(t, k, v)
    rawset(t, k, v)
    if k == "Enabled" and v == false then
        forceDisableTP()
    end
end
setmetatable(TPConfig, tpEnabledmt)

-- ============================================================
-- INPUT HANDLERS
-- ============================================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    -- Menu toggle
    if input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.Insert then
        if MainFrame then
            MenuConfig.MenuOpen = not MenuConfig.MenuOpen
            MainFrame.Visible = MenuConfig.MenuOpen
        end
    end

    -- LMB
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        lmbHeld = true
        if AimConfig.AimbotEnabled and AimConfig.HoldToAim then
            aimDelayTimer = AimConfig.AimDelay
            if AimConfig.BlockShot and not gameProcessed then return end
        end
    end

    -- V
    if input.KeyCode == Enum.KeyCode.V and TPConfig.Enabled and not gameProcessed then
        tpActive = not tpActive
        if tpActive then
            Camera.CameraType = Enum.CameraType.Scriptable
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        else
            Camera.CameraType = Enum.CameraType.Custom
            lp.CameraMode = Enum.CameraMode.LockFirstPerson
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        lmbHeld = false
        shotAllowed = true
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if tpActive and input.UserInputType == Enum.UserInputType.MouseMovement then
        tpYaw = tpYaw - input.Delta.X * TPConfig.Sensitivity
        tpPitch = math.clamp(tpPitch - input.Delta.Y * TPConfig.Sensitivity, -75, 75)
    end
end)

-- ============================================================
-- RENDER LOOPS (protected)
-- ============================================================
RunService.RenderStepped:Connect(function(dt)
    pcall(function()
        FovCircle.Visible = AimConfig.ShowFov
        FovCircle.Radius = AimConfig.FovRadius
        FovCircle.Position = UserInputService:GetMouseLocation()

        if AimConfig.AimbotEnabled then
            if not lp or not lp.Character or not lp.Character:FindFirstChild("HumanoidRootPart") then return end
            local shouldAim = not AimConfig.HoldToAim or lmbHeld
            if aimDelayTimer > 0 then
                aimDelayTimer = aimDelayTimer - dt
                shouldAim = false
            end
            if shouldAim then
                local target = GetClosestTarget()
                if target then
                    local targetPos = Camera:WorldToViewportPoint(target.Position)
                    local mousePos = UserInputService:GetMouseLocation()
                    local moveX = (targetPos.X - mousePos.X) / AimConfig.Smoothness
                    local moveY = (targetPos.Y - mousePos.Y) / AimConfig.Smoothness
                    mousemoverel(moveX, moveY)

                    if AimConfig.AutoFire and shotAllowed then
                        shotAllowed = false
                        if AimConfig.FireDelay > 0 then
                            task.delay(AimConfig.FireDelay, function()
                                pcall(function()
                                    mouse1press(); task.wait(0.01); mouse1release()
                                end)
                                shotAllowed = true
                            end)
                        else
                            pcall(function()
                                mouse1press(); task.wait(0.01); mouse1release()
                            end)
                            shotAllowed = true
                        end
                    end
                end
            end
        end
    end)
end)

RunService:BindToRenderStep("ENI_ThirdPerson", Enum.RenderPriority.Camera.Value + 1, function()
    pcall(function()
        if tpActive then
            updateThirdPersonCamera()
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        end
    end)
end)

-- ============================================================
-- ESP HIGHLIGHT LOGIC
-- ============================================================
local function SetHighlight(model, enable)
    if not model or not model.Parent then return end
    local ok, hl = pcall(function() return model:FindFirstChild("ENI_HL") end)
    if not ok then return end
    if enable then
        if not hl then
            pcall(function()
                local h = Instance.new("Highlight")
                h.Name = "ENI_HL"
                h.FillColor = ESPConfig.FillColor
                h.OutlineColor = ESPConfig.OutlineColor
                h.FillTransparency = ESPConfig.FillTransparency
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.Parent = model
            end)
        else
            pcall(function()
                hl.FillColor = ESPConfig.FillColor
                hl.OutlineColor = ESPConfig.OutlineColor
                hl.FillTransparency = ESPConfig.FillTransparency
            end)
        end
    else
        if hl then pcall(function() hl:Destroy() end) end
    end
end

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
                    SetHighlight(model, hum.Health > 0 and not IsFriendly(model))
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

-- ============================================================
-- SCANNER
-- ============================================================
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
            for _, holder in ipairs({enemyHolder, friendlyHolder}) do
                if holder and holder.Parent then
                    for _, child in ipairs(holder:GetChildren()) do
                        if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
                            trackedModels[child] = true
                        end
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

for _, p in ipairs(Players:GetPlayers()) do TrackPlayer(p) end
Players.PlayerAdded:Connect(function(p)
    if IsAlive() then TrackPlayer(p) end
end)

-- ============================================================
-- UNIFIED GUI MENU
-- ============================================================
local ScreenGui = Instance.new("ScreenGui", game.CoreGui)
ScreenGui.Name = "ENI_Menu"

MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size = UDim2.new(0, 300, 0, 460)
MainFrame.Position = UDim2.new(0.5, -150, 0.5, -230)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
MainFrame.BorderSizePixel = 0
MainFrame.Visible = MenuConfig.MenuOpen
MainFrame.Active = true
MainFrame.Draggable = true

-- Title bar
local TitleBar = Instance.new("Frame", MainFrame)
TitleBar.Size = UDim2.new(1, 0, 0, 38)
TitleBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
TitleBar.BorderSizePixel = 0

local Title = Instance.new("TextLabel", TitleBar)
Title.Size = UDim2.new(1, 0, 1, 0)
Title.Text = "ENI HUB"
Title.TextColor3 = Color3.new(1, 1, 1)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.TextSize = 15

-- Tab bar
local TabBar = Instance.new("Frame", MainFrame)
TabBar.Size = UDim2.new(1, 0, 0, 32)
TabBar.Position = UDim2.new(0, 0, 0, 38)
TabBar.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
TabBar.BorderSizePixel = 0

local TabList = Instance.new("UIListLayout", TabBar)
TabList.FillDirection = Enum.FillDirection.Horizontal
TabList.HorizontalAlignment = Enum.HorizontalAlignment.Center
TabList.VerticalAlignment = Enum.VerticalAlignment.Center

local TabNames = {"Aim", "ESP", "Misc"}
local tabButtons = {}
for _, name in ipairs(TabNames) do
    local btn = Instance.new("TextButton", TabBar)
    btn.Size = UDim2.new(0, 100, 0, 28)
    btn.Text = name
    btn.TextColor3 = Color3.new(0.4, 0.4, 0.4)
    btn.BackgroundTransparency = 1
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.AutoButtonColor = false
    tabButtons[name] = btn
end

-- Content container
local ContentFrame = Instance.new("Frame", MainFrame)
ContentFrame.Size = UDim2.new(1, 0, 1, -78)
ContentFrame.Position = UDim2.new(0, 0, 0, 70)
ContentFrame.BackgroundTransparency = 1
ContentFrame.BorderSizePixel = 0

-- Tab content pages
local tabPages = {}

-- ============================================================
-- WIDGET HELPERS
-- ============================================================
local ELEM_W = 0.88
local ELEM_H = 36  -- fixed height for all elements

local function makePage(parent)
    local page = Instance.new("ScrollingFrame", parent)
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 4
    page.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 80)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.CanvasSize = UDim2.new(0, 0, 0, 0)

    local layout = Instance.new("UIListLayout", page)
    layout.Padding = UDim.new(0, 5)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    return page
end

local function sec(parent, name)
    local l = Instance.new("TextLabel", parent)
    l.Size = UDim2.new(ELEM_W, 0, 0, 22)
    l.Text = "— " .. name .. " —"
    l.TextColor3 = Color3.fromRGB(100, 100, 100)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.GothamBold
    l.TextSize = 11
    return l
end

local function toggle(parent, name, key, cfg)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(ELEM_W, 0, 0, ELEM_H)
    btn.Text = name .. ": " .. (cfg[key] and "ON" or "OFF")
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.BackgroundColor3 = cfg[key] and Color3.fromRGB(0, 120, 55) or Color3.fromRGB(120, 25, 25)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 13
    btn.AutoButtonColor = false
    btn.MouseButton1Click:Connect(function()
        cfg[key] = not cfg[key]
        btn.Text = name .. ": " .. (cfg[key] and "ON" or "OFF")
        btn.BackgroundColor3 = cfg[key] and Color3.fromRGB(0, 120, 55) or Color3.fromRGB(120, 25, 25)
    end)
    return btn
end

-- Slider: full-width block with label on top + big clickable button below
local function slider(parent, name, key, cfg, minV, maxV, fmtFn)
    local block = Instance.new("Frame", parent)
    block.Size = UDim2.new(ELEM_W, 0, 0, ELEM_H)

    local lbl = Instance.new("TextLabel", block)
    lbl.Size = UDim2.new(1, 0, 0, 18)
    lbl.Position = UDim2.new(0, 0, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextColor3 = Color3.new(1, 1, 1)

    local btn = Instance.new("TextButton", block)
    btn.Size = UDim2.new(1, 0, 0, 16)
    btn.Position = UDim2.new(0, 0, 0, 20)
    btn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    btn.Text = "[ CLICK TO CHANGE ]"
    btn.AutoButtonColor = false

    local function update()
        lbl.Text = name .. ": " .. (fmtFn and fmtFn(cfg[key]) or tostring(cfg[key]))
    end
    update()

    btn.MouseButton1Click:Connect(function()
        cfg[key] = cfg[key] + (maxV - minV) * 0.1
        if cfg[key] > maxV then cfg[key] = minV end
        update()
    end)

    return block, lbl, btn
end

-- Color block: header + swatch + R/G/B controls + presets
local function colorBlock(parent, name, key, cfg)
    local block = Instance.new("Frame", parent)
    block.Size = UDim2.new(ELEM_W, 0, 0, 80)

    local header = Instance.new("TextLabel", block)
    header.Size = UDim2.new(1, 0, 0, 16)
    header.Position = UDim2.new(0, 0, 0, 0)
    header.Text = name
    header.TextColor3 = Color3.fromRGB(140, 140, 140)
    header.BackgroundTransparency = 1
    header.Font = Enum.Font.GothamBold
    header.TextSize = 10
    header.TextXAlignment = Enum.TextXAlignment.Left

    -- Swatch + RGB controls
    local row = Instance.new("Frame", block)
    row.Size = UDim2.new(1, 0, 0, 26)
    row.Position = UDim2.new(0, 0, 0, 18)
    row.BackgroundTransparency = 1

    local hLayout = Instance.new("UIListLayout", row)
    hLayout.FillDirection = Enum.FillDirection.Horizontal
    hLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    hLayout.Padding = UDim.new(0, 4)

    -- Swatch
    local swatch = Instance.new("Frame", row)
    swatch.Size = UDim2.new(0, 26, 0, 26)
    swatch.BackgroundColor3 = cfg[key]
    swatch.BorderSizePixel = 0
    local swatchStroke = Instance.new("UIStroke", swatch)
    swatchStroke.Color = Color3.fromRGB(90, 90, 90)
    swatchStroke.Thickness = 1

    -- R / G / B columns
    for _, col in ipairs({"R", "G", "B"}) do
        local colFrame = Instance.new("Frame", row)
        colFrame.Size = UDim2.new(0, 34, 0, 26)
        colFrame.BackgroundTransparency = 1

        local colLbl = Instance.new("TextLabel", colFrame)
        colLbl.Size = UDim2.new(1, 0, 0, 12)
        colLbl.BackgroundTransparency = 1
        colLbl.Font = Enum.Font.GothamBold
        colLbl.TextSize = 9
        colLbl.TextXAlignment = Enum.TextXAlignment.Left
        local c = cfg[key]
        if col == "R" then colLbl.Text = "R:" colLbl.TextColor3 = Color3.fromRGB(255, 80, 80)
        elseif col == "G" then colLbl.Text = "G:" colLbl.TextColor3 = Color3.fromRGB(80, 255, 80)
        else colLbl.Text = "B:" colLbl.TextColor3 = Color3.fromRGB(80, 80, 255) end

        local colBtn = Instance.new("TextButton", colFrame)
        colBtn.Size = UDim2.new(1, 0, 0, 12)
        colBtn.Position = UDim2.new(0, 0, 0, 14)
        colBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        colBtn.Text = "+25"
        colBtn.TextColor3 = Color3.new(1, 1, 1)
        colBtn.Font = Enum.Font.GothamBold
        colBtn.TextSize = 9
        colBtn.AutoButtonColor = false
        colBtn.MouseButton1Click:Connect(function()
            local cur = cfg[key]
            local r, g, b = math.floor(cur.R * 255), math.floor(cur.G * 255), math.floor(cur.B * 255)
            if col == "R" then r = (r + 25) % 256
            elseif col == "G" then g = (g + 25) % 256
            else b = (b + 25) % 256 end
            cfg[key] = Color3.fromRGB(r, g, b)
            updateAll()
        end)
    end

    -- Presets row
    local presets = {
        {n = "Red", r = 255, g = 0, b = 0},
        {n = "Green", r = 0, g = 255, b = 0},
        {n = "Blue", r = 0, g = 0, b = 255},
        {n = "Yellow", r = 255, g = 255, b = 0},
        {n = "Cyan", r = 0, g = 255, b = 255},
        {n = "White", r = 255, g = 255, b = 255},
    }

    local presetRow = Instance.new("Frame", block)
    presetRow.Size = UDim2.new(1, 0, 0, 22)
    presetRow.Position = UDim2.new(0, 0, 0, 50)
    presetRow.BackgroundTransparency = 1
    local pLayout = Instance.new("UIListLayout", presetRow)
    pLayout.FillDirection = Enum.FillDirection.Horizontal
    pLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    pLayout.Padding = UDim.new(0, 3)

    for _, pre in ipairs(presets) do
        local pb = Instance.new("TextButton", presetRow)
        pb.Size = UDim2.new(0, 40, 0, 22)
        pb.Text = pre.n
        pb.TextColor3 = Color3.new(1, 1, 1)
        pb.BackgroundColor3 = Color3.fromRGB(
            math.clamp(pre.r * 0.4 + 80, 0, 255),
            math.clamp(pre.g * 0.4 + 80, 0, 255),
            math.clamp(pre.b * 0.4 + 80, 0, 255)
        )
        pb.Font = Enum.Font.Gotham
        pb.TextSize = 9
        pb.AutoButtonColor = false
        pb.MouseButton1Click:Connect(function()
            cfg[key] = Color3.fromRGB(pre.r, pre.g, pre.b)
            updateAll()
        end)
    end

    -- Update function — updates swatch color and R/G/B labels inside row
    local function updateAll()
        local c = cfg[key]
        swatch.BackgroundColor3 = c
        local children = row:GetChildren()
        local colIdx = 1
        for _, child in ipairs(children) do
            if child:IsA("Frame") and child ~= swatch then
                local txt = child:FindFirstChildWhichIsA("TextLabel")
                if txt then
                    local val
                    if colIdx == 1 then val = math.floor(c.R * 255)
                    elseif colIdx == 2 then val = math.floor(c.G * 255)
                    else val = math.floor(c.B * 255) end
                    txt.Text = (colIdx == 1 and "R:" or colIdx == 2 and "G:" or "B:") .. " " .. val
                end
                colIdx = colIdx + 1
            end
        end
    end

    return block, header, swatch
end

-- ============================================================
-- BUILD AIM TAB
-- ============================================================
do
    local page = makePage(ContentFrame)
    tabPages["Aim"] = page

    sec(page, "GENERAL")
    toggle(page, "Enable Aimbot", "AimbotEnabled", AimConfig)
    toggle(page, "Hold LMB to Aim", "HoldToAim", AimConfig)
    toggle(page, "Auto Fire", "AutoFire", AimConfig)

    sec(page, "TIMING")
    slider(page, "Fire Delay (s)", "FireDelay", AimConfig, 0, 0.5, function(v) return string.format("%.1f", v) end)
    slider(page, "Aim Delay (s)", "AimDelay", AimConfig, 0, 1, function(v) return string.format("%.1f", v) end)

    sec(page, "TARGETING")
    slider(page, "FOV Radius", "FovRadius", AimConfig, 30, 600, function(v) return math.floor(v) end)
    slider(page, "Smoothness (Low=Fast)", "Smoothness", AimConfig, 1, 20, function(v) return math.floor(v) end)
    toggle(page, "Wall Check", "VisibleCheck", AimConfig)
    toggle(page, "Block Native Shot", "BlockShot", AimConfig)

    sec(page, "VISUAL")
    toggle(page, "Show FOV Circle", "ShowFov", AimConfig)
end

-- ============================================================
-- BUILD ESP TAB
-- ============================================================
do
    local page = makePage(ContentFrame)
    page.Visible = false
    tabPages["ESP"] = page

    sec(page, "ENABLE")
    toggle(page, "Enable ESP", "Enabled", ESPConfig)

    sec(page, "FILL COLOR")
    colorBlock(page, "Fill Color", "FillColor", ESPConfig)

    sec(page, "OUTLINE COLOR")
    colorBlock(page, "Outline Color", "OutlineColor", ESPConfig)

    sec(page, "APPEARANCE")
    slider(page, "Fill Transparency", "FillTransparency", ESPConfig, 0, 1, function(v) return string.format("%.1f", v) end)
end

-- ============================================================
-- BUILD MISC TAB
-- ============================================================
do
    local page = makePage(ContentFrame)
    page.Visible = false
    tabPages["Misc"] = page

    sec(page, "CAMERA")
    toggle(page, "Enable Third Person (V)", "Enabled", TPConfig)
end

-- ============================================================
-- TAB SWITCHING
-- ============================================================
local function switchTab(name)
    MenuConfig.ActiveTab = name
    for tabName, btn in pairs(tabButtons) do
        btn.TextColor3 = (tabName == name) and Color3.new(1, 1, 1) or Color3.new(0.4, 0.4, 0.4)
    end
    for tabName, page in pairs(tabPages) do
        page.Visible = (tabName == name)
    end
end

for tabName, btn in pairs(tabButtons) do
    btn.MouseButton1Click:Connect(function()
        switchTab(tabName)
    end)
end

switchTab("Aim")

print("!!! ENI UNIFIED HUB LOADED !!!")