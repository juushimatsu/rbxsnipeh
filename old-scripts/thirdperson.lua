local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local lp = Players.LocalPlayer
local mouse = lp:GetMouse()
local camera = workspace.CurrentCamera

-- === НАСТРОЙКИ ===
local active = false
local distance = 18 -- Дистанция отдаления
local offset = Vector3.new(3, 2, 0) -- Смещение (вправо, вверх)
local sensitivity = 0.5 -- Чувствительность вращения

local yaw = 0   -- Поворот влево/вправо
local pitch = 0 -- Поворот вверх/вниз

-- === ФУНКЦИЯ ОБНОВЛЕНИЯ КАМЕРЫ ===
local function updateCamera()
    if not active then return end
    
    local character = lp.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    
    if root then
        -- Рассчитываем вращение
        local rotation = CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)
        
        -- Позиция камеры: Позиция игрока + Вращение * (Смещение + Дистанция назад)
        local targetCFrame = CFrame.new(root.Position) * rotation * CFrame.new(offset.X, offset.Y, distance)
        
        camera.CFrame = targetCFrame
        
        -- Заставляем персонажа поворачиваться лицом туда, куда смотрит камера
        root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, math.rad(yaw), 0)
        
        -- Делаем части тела видимыми (голову и т.д.)
        for _, part in pairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.LocalTransparencyModifier = 0
            end
        end
    end
end

-- === УПРАВЛЕНИЕ МЫШЬЮ ===
UserInputService.InputChanged:Connect(function(input)
    if active and input.UserInputType == Enum.UserInputType.MouseMovement then
        yaw = yaw - input.Delta.X * sensitivity
        pitch = math.clamp(pitch - input.Delta.Y * sensitivity, -75, 75) -- Ограничиваем наклон вверх/вниз
    end
end)

-- === ВКЛЮЧЕНИЕ / ВЫКЛЮЧЕНИЕ ===
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    
    if input.KeyCode == Enum.KeyCode.V then
        active = not active
        
        if active then
            camera.CameraType = Enum.CameraType.Scriptable
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
            print("ENI: Custom Camera Active")
        else
            camera.CameraType = Enum.CameraType.Custom -- Возвращаем стандартную камеру
            lp.CameraMode = Enum.CameraMode.LockFirstPerson
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            print("ENI: Back to First Person")
        end
    end
end)

-- Рендер-цикл
RunService:BindToRenderStep("ENI_ThirdPerson", Enum.RenderPriority.Camera.Value + 1, function()
    if active then
        updateCamera()
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
    end
end)

print("!!! ENI SCRIPTABLE CAMERA V3 LOADED (V) !!!")