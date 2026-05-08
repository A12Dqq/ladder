--[[
 .____                  ________ ___.    _____                           __                
 |    |    __ _______   \_____  \\_ |___/ ____\_ __  ______ ____ _____ _/  |_  ___________ 
 |    |   |  |  \__  \   /   |   \| __ \   __\  |  \/  ___// ___\\__  \\   __\/  _ \_  __ \
 |    |___|  |  // __ \_/    |    \ \_\ \  | |  |  /\___ \\  \___ / __ \|  | (  <_> )  | \/
-- GLOBAL VARIABLES
local player = game.Players.LocalPlayer
local camera = workspace.CurrentCamera
local run, UIS = game:GetService("RunService"), game:GetService("UserInputService")
local starterGui = game:GetService("StarterGui")
local VIM = game:GetService("VirtualInputManager")

local holding, target, holdDistance, anchoredWhileHolding = false, nil, 10, false
local holdLeft, holdRight, holdQ, holdE = false, false, false, false

-- Script Life Cycle
local scriptRunning = true

-- Physics/Noclip State
local noclipActive = false

-- Physical Forces
local vel = Instance.new("BodyVelocity")
vel.MaxForce = Vector3.new(1, 1, 1) * 1e5
vel.P = 12500

local gyro = Instance.new("BodyGyro")
gyro.MaxTorque = Vector3.new(1, 1, 1) * 1e6
gyro.P = 3000

local originalRotation = nil

-- Visual Outline (SelectionBox)
local SelectionBox = Instance.new("SelectionBox")
SelectionBox.Name = "Outline"
SelectionBox.LineThickness = 0.08
SelectionBox.Parent = game:GetService("CoreGui")

-- Magnet Settings
local magnetActive, magnetRadius, magnetForce = false, 30, 200
local magnetObjects, gravityBackup = {}, {}
local currentRadius = magnetRadius

-- Advanced Visual Circle
local usingDrawing = Drawing and Drawing.new and typeof(Drawing.new)=="function"
local magnetCircle, circleGui, circleImg
local circleColor = Color3.fromRGB(0,170,255)
local surfacePos, surfaceNormal = Vector3.zero, Vector3.new(0,1,0)

if usingDrawing then
	magnetCircle = Drawing.new("Circle")
	magnetCircle.Visible, magnetCircle.Transparency, magnetCircle.Color, magnetCircle.Thickness, magnetCircle.Filled = false, 1, circleColor, 2, false
else
	circleGui = Instance.new("BillboardGui")
	circleGui.Name, circleGui.Size, circleGui.SizeOffset, circleGui.AlwaysOnTop = "MagnetCircleGui", UDim2.new(2,0,2,0), Vector2.new(0,0), true
	circleGui.Parent = workspace
	circleImg = Instance.new("ImageLabel")
	circleImg.BackgroundTransparency, circleImg.Image, circleImg.ImageColor3 = 1, "rbxassetid://13523341990", circleColor
	circleImg.AnchorPoint, circleImg.Position, circleImg.Size = Vector2.new(0.5,0.5), UDim2.fromScale(0.5,0.5), UDim2.fromScale(1,1)
	circleImg.Parent, circleGui.Enabled = circleImg, false
end

-- Virtual mouse
local virtualMouseSize = 60 
local virtualMouseEnabled = UIS.TouchEnabled 
local virtualMouseCenter = Vector2.new(0.5, 0.45)

-- GUI references
local GUIrefs = {}
local guiHidden = false

-- Utilities
local function notify(title, text)
    starterGui:SetCore("SendNotification", {
        Title = title;
        Text = text;
        Duration = 2;
    })
end

local function isCharacterPart(obj)
	for _, plr in ipairs(game.Players:GetPlayers()) do
		if plr.Character and obj:IsDescendantOf(plr.Character) then return true end
	end
	return false
end

local function isAccessory(obj)
    return obj:FindFirstAncestorOfClass("Accessory") ~= nil
end

local function restoreGravity()
	for obj, oldGravity in pairs(gravityBackup) do
		if obj and obj:IsDescendantOf(workspace) then obj.CustomPhysicalProperties = oldGravity end
	end
	gravityBackup = {}
end

local function lerpVec3(a, b, t) return a + (b - a) * t end

local function getScreenSize()
	local vs = camera.ViewportSize
	return vs.X, vs.Y
end

local function computeVirtualCenterPixels()
	local sx, sy = getScreenSize()
	return Vector2.new(sx * virtualMouseCenter.X, sy * virtualMouseCenter.Y)
end

local function getInputPosition()
	if UIS.TouchEnabled and virtualMouseEnabled then
		local vmPos = computeVirtualCenterPixels()
		return vmPos.X, vmPos.Y
	end
	local pos = UIS:GetMouseLocation()
	return pos.X, pos.Y
end

local function raycastFromScreen(x, y, maxDist)
	local ray = camera:ScreenPointToRay(x, y)
	local dist = maxDist or 1000
	return workspace:FindPartOnRayWithIgnoreList(Ray.new(ray.Origin, ray.Direction * dist), {player.Character})
end

-- KILL SCRIPT
local function killScript()
    scriptRunning = false
    noclipActive = false
    if GUIrefs.screenGui then GUIrefs.screenGui:Destroy() end
    if SelectionBox then SelectionBox:Destroy() end
    if magnetCircle then magnetCircle:Remove() end
    if circleGui then circleGui:Destroy() end
    for _, part in pairs(workspace:GetDescendants()) do
        if part:IsA("BasePart") then part.CanCollide = true end
    end
    restoreGravity()
    if vel then vel:Destroy() end
    if gyro then gyro:Destroy() end
    notify("Status", "Script Terminated")
end

local function updateButtonStates()
	if not scriptRunning then return end
	if GUIrefs.magnetBtn and GUIrefs.grabBtn and GUIrefs.noclipBtn then
		if magnetActive then
			GUIrefs.magnetBtn.BackgroundColor3 = Color3.fromRGB(25,130,255)
			GUIrefs.magnetBtn.Text = "Magnet ✓"
		else
			GUIrefs.magnetBtn.BackgroundColor3 = Color3.fromRGB(30,30,30)
			GUIrefs.magnetBtn.Text = "Magnet"
		end
		
		if holding then
			GUIrefs.grabBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
			GUIrefs.grabBtn.Text = "Release"
		else
			GUIrefs.grabBtn.BackgroundColor3 = Color3.fromRGB(30,30,30)
			GUIrefs.grabBtn.Text = "Grab"
		end
		
		if noclipActive then
			GUIrefs.noclipBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
			GUIrefs.noclipBtn.Text = "Noclip ON"
		else
			GUIrefs.noclipBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
			GUIrefs.noclipBtn.Text = "Noclip OFF"
		end
	end
end

local function updateVMVisuals()
	if not scriptRunning then return end
	local screenX, screenY = getScreenSize()
	local vPos = computeVirtualCenterPixels()
	if not GUIrefs.screenGui then return end
	
	if GUIrefs.vm and vPos then
		local px = math.clamp(vPos.X - virtualMouseSize/2, 0, screenX - virtualMouseSize)
		local py = math.clamp(vPos.Y - virtualMouseSize/2, 0, screenY - virtualMouseSize)
		GUIrefs.vm.Position = UDim2.new(0, px, 0, py)
		GUIrefs.vm.Visible = not guiHidden
	end
	
	if GUIrefs.vmCircle then
		local cx, cy = getInputPosition()
		local radiusScreenScale = 2.0 
		local radPx = math.clamp(math.floor(magnetRadius * radiusScreenScale), 8, math.min(screenX, screenY))
		GUIrefs.vmCircle.Size = UDim2.new(0, radPx*2, 0, radPx*2)
		GUIrefs.vmCircle.Position = UDim2.new(0, cx - radPx, 0, cy - radPx)
		GUIrefs.vmCircle.ImageColor3 = magnetActive and Color3.fromRGB(60,170,255) or Color3.fromRGB(80,80,80)
		GUIrefs.vmCircle.Visible = magnetActive and (not guiHidden)
	end
end

run.RenderStepped:Connect(function()
	if not scriptRunning then return end
	if guiHidden then
		SelectionBox.Adornee = nil
	else
		if magnetActive and not holding then
			SelectionBox.Adornee = nil
		else
			if holding and target then
				SelectionBox.Color3, SelectionBox.Adornee = Color3.fromRGB(150, 50, 255), target
			else
				local sx, sy = getInputPosition()
				local hit, pos = raycastFromScreen(sx, sy, 1000)
				if hit and hit:IsA("BasePart") and not hit.Anchored and not isCharacterPart(hit) then
					SelectionBox.Color3, SelectionBox.Adornee = Color3.fromRGB(0,170,255), hit
				else
					SelectionBox.Adornee = nil
				end
			end
		end
	end

	if magnetActive and not guiHidden then
		local sx, sy = getInputPosition()
		local ray = camera:ScreenPointToRay(sx, sy)
		local hit, pos, norm = workspace:FindPartOnRayWithIgnoreList(Ray.new(ray.Origin, ray.Direction * 1000), {player.Character})
		if hit then
			surfacePos, surfaceNormal = lerpVec3(surfacePos,pos,0.35), lerpVec3(surfaceNormal,norm,0.35)
		else
			local defPos = ray.Origin + ray.Direction * 15
			surfacePos, surfaceNormal = lerpVec3(surfacePos,defPos,0.15), lerpVec3(surfaceNormal,Vector3.new(0,1,0),0.15)
		end
		currentRadius = currentRadius + (magnetRadius - currentRadius) * 0.25
		if usingDrawing then
			local screenPos = camera:WorldToViewportPoint(surfacePos)
			magnetCircle.Visible, magnetCircle.Position, magnetCircle.Radius = true, Vector2.new(screenPos.X, screenPos.Y), currentRadius
		else
			circleGui.Enabled, circleGui.Size = true, UDim2.new(0,currentRadius*2,0,currentRadius*2)
			circleGui.CFrame = CFrame.new(surfacePos, surfacePos + camera.CFrame.LookVector)
				* CFrame.fromMatrix(Vector3.zero,
					surfaceNormal:Cross(Vector3.new(0,1,0)).Magnitude>0.01 and surfaceNormal:Cross(Vector3.new(0,1,0)).Unit or Vector3.new(1,0,0),
					surfaceNormal,
					-surfaceNormal:Cross(Vector3.new(1,0,0)).Unit)
			circleGui.Position = surfacePos
		end
	else
		if usingDrawing then magnetCircle.Visible = false
		elseif circleGui then circleGui.Enabled = false end
	end
	updateVMVisuals()
	updateButtonStates()
end)

run.Heartbeat:Connect(function()
	if not scriptRunning then return end
    if player.Character then
        for _, item in pairs(player.Character:GetDescendants()) do
            if item:IsA("BasePart") and isAccessory(item) then item.CanCollide = false end
        end
    end
    if noclipActive then
        for _, part in pairs(workspace:GetDescendants()) do
            if part:IsA("BasePart") and not part.Anchored and not isCharacterPart(part) and not isAccessory(part) then
                part.CanCollide = false
            end
        end
    end

	if holding and target then
		if not anchoredWhileHolding then
			local sx, sy = getInputPosition()
			local ray = camera:ScreenPointToRay(sx, sy)
			local grabPos = ray.Origin + ray.Direction.Unit * holdDistance
			vel.Velocity = (grabPos - target.Position) * 5
			if originalRotation then gyro.CFrame = originalRotation + target.Position end
		else
			vel.Velocity = Vector3.zero
		end
	end

	if magnetActive then
		local center, newAttracted = surfacePos, {}
		local nearby = workspace:GetPartBoundsInBox(CFrame.new(center), Vector3.new(magnetRadius*2, magnetRadius*2, magnetRadius*2))
		for _, obj in ipairs(nearby) do
			if obj:IsA("BasePart") and not obj.Anchored and not isCharacterPart(obj) and obj.Transparency < 1 and obj.CanCollide and obj ~= target then
				local bv = obj:FindFirstChild("MagnetBV") or Instance.new("BodyVelocity")
				bv.Name, bv.MaxForce, bv.P = "MagnetBV", Vector3.new(1,1,1)*1e5, 15000
				local dir = (center - obj.Position) * Vector3.new(1,0,1)
				bv.Velocity = dir.Magnitude > 0 and dir.Unit * magnetForce or Vector3.zero
				bv.Parent = obj
				if not gravityBackup[obj] then
					gravityBackup[obj] = obj.CustomPhysicalProperties
					obj.CustomPhysicalProperties = PhysicalProperties.new(0, 0.3, 0.5, 1, 1)
				end
				newAttracted[obj] = true
			end
		end
		for obj in pairs(magnetObjects) do
			if not newAttracted[obj] then
				if obj and obj:FindFirstChild("MagnetBV") then obj.MagnetBV:Destroy() end
				if gravityBackup[obj] then obj.CustomPhysicalProperties = gravityBackup[obj]; gravityBackup[obj] = nil end
			end
		end
		magnetObjects = newAttracted
	else
		for obj in pairs(magnetObjects) do if obj and obj:FindFirstChild("MagnetBV") then obj.MagnetBV:Destroy() end end
		restoreGravity()
		magnetObjects = {}
	end

	if magnetActive then
		if holdLeft or holdQ then magnetRadius = math.max(5, magnetRadius - 1.3)
		elseif holdRight or holdE then magnetRadius = math.min(200, magnetRadius + 1.3) end
	else
		if holdLeft or holdQ then holdDistance = math.max(2, holdDistance - 0.4)
		elseif holdRight or holdE then holdDistance = math.min(1000, holdDistance + 0.4) end
	end
end)

function grabOrRelease()
	if not scriptRunning or magnetActive then return end
	if holding then
		originalRotation, vel.Parent, gyro.Parent, anchoredWhileHolding, target, holding = nil, nil, nil, false, nil, false
		notify("Grabber", "Object Released ✋")
	else
		local sx, sy = getInputPosition()
		local part, pos = raycastFromScreen(sx, sy, 1000)
		if part and part:IsA("BasePart") and not part.Anchored and not isCharacterPart(part) then
			target, anchoredWhileHolding = part, false
			originalRotation = part.CFrame - part.Position
			gyro.CFrame, gyro.Parent, vel.Velocity, vel.Parent = originalRotation + part.Position, part, Vector3.zero, part
			holdDistance = (camera.CFrame.Position - pos).Magnitude
			holding = true
			notify("Grabber", "Object Caught ✊")
		end
	end
    updateButtonStates()
end

function throw()
	if not scriptRunning or magnetActive or not holding or not target then return end
	if anchoredWhileHolding then target.Anchored, anchoredWhileHolding = false, false end
	vel.Parent, gyro.Parent, holding, originalRotation = nil, nil, false, nil
	local impulse = Instance.new("BodyVelocity")
	impulse.Velocity, impulse.MaxForce, impulse.P, impulse.Parent = camera.CFrame.LookVector * 1000, Vector3.new(1,1,1)*1e6, 12500, target
	game:GetService("Debris"):AddItem(impulse, 0.5)
	target = nil
	notify("Grabber", "Object Thrown")
	updateButtonStates()
end

function toggleAnchor()
	if not scriptRunning or magnetActive or not holding or not target then return end
	anchoredWhileHolding = not anchoredWhileHolding
	target.Anchored = anchoredWhileHolding
	if anchoredWhileHolding then
		vel.Parent, gyro.Parent = nil, nil
		target.AssemblyLinearVelocity, target.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		notify("Anchor", "Object Locked 📌")
	else
		vel.Parent, gyro.Parent = target, target
		notify("Anchor", "Object Unlocked ❌")
	end
end

function toggleMagnet()
	if not scriptRunning or holding then return end
	magnetActive = not magnetActive
	if not magnetActive then restoreGravity() end
	notify("Magnet", magnetActive and "Magnet Enabled 🧲" or "Magnet Disabled ❌")
	updateButtonStates()
end

function toggleNoclip()
    if not scriptRunning then return end
    noclipActive = not noclipActive
    if not noclipActive then
        for _, part in pairs(workspace:GetDescendants()) do
            if part:IsA("BasePart") and not part.Anchored and not isCharacterPart(part) and not isAccessory(part) then
                part.CanCollide = true
            end
        end
    end
    notify("Noclip", noclipActive and "Noclip Enabled 👻" or "Noclip Disabled ❌")
    updateButtonStates()
end

-- BYPASS LOGIC
local isBypassRunning = false
local bypassCancelTriggered = false

local function executeBypassSequence(btn)
    if isBypassRunning then
        bypassCancelTriggered = true
        return
    end

    isBypassRunning = true
    bypassCancelTriggered = false
    
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    
    if not root then 
        btn.Text = "Error: Char"
        isBypassRunning = false
        return 
    end

    root.CFrame = root.CFrame * CFrame.new(0, 99999999, 0)

    local ladder = player.Backpack:FindFirstChild("Ladder") or char:FindFirstChild("Ladder")
    if ladder then
        ladder.Parent = char 
        task.wait(0.2) 
        ladder:Activate() 
        VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    end

    btn.Text = "SEARCHING..."
    local targetItem = nil
    while not targetItem do
        if bypassCancelTriggered then break end
        targetItem = workspace:FindFirstChild("ELION003_ladder", true)
        if not targetItem then task.wait(0.1) end
    end

    if bypassCancelTriggered then
        btn.Text = "Bypass"
        isBypassRunning = false
        return
    end

    local savedStates = {}
    local parts = targetItem:IsA("Model") and targetItem:GetDescendants() or {targetItem}
    for _, p in pairs(parts) do
        if p:IsA("BasePart") then
            savedStates[p] = p.Anchored
            p.Anchored = true
        end
    end

    for i = 3, 1, -1 do
        if bypassCancelTriggered then break end
        btn.Text = "CANCEL (" .. i .. "s)"
        task.wait(1)
    end

    if not bypassCancelTriggered then
        local spawnPos = root.CFrame * CFrame.new(0, 0, -3.5)
        if targetItem:IsA("Model") then targetItem:PivotTo(spawnPos) else targetItem.CFrame = spawnPos end
        btn.Text = "FINISHED!"
        notify("Bypass", "Ladder Bypassed 📶")
        task.wait(1.2)
    end
    
    for p, state in pairs(savedStates) do p.Anchored = state end
    btn.Text = "Bypass"
    isBypassRunning = false
end

-- BRING LADDER LOGIC
local isBringRunning = false
local function bringLadder(btn)
    if isBringRunning then return end
    isBringRunning = true
    
    local itemName = "ELION003_ladder"
    local distance = 5
    local char = player.Character or player.CharacterAdded:Wait()
    local rootPart = char:FindFirstChild("HumanoidRootPart")
    local item = workspace:FindFirstChild(itemName, true)

    if item and rootPart then
        local spawnPos = rootPart.CFrame + (rootPart.CFrame.LookVector * distance)
        btn.Text = "Teleporting..."

        -- 1. Teleport and Anchor
        if item:IsA("Model") then
            item:PivotTo(spawnPos)
            for _, p in pairs(item:GetDescendants()) do
                if p:IsA("BasePart") then p.Anchored = true end
            end
        elseif item:IsA("BasePart") then
            item.CFrame = spawnPos
            item.Anchored = true
        end

        task.wait(0.5)

        -- 3. Unanchor
        if item:IsA("Model") then
            for _, p in pairs(item:GetDescendants()) do
                if p:IsA("BasePart") then p.Anchored = false end
            end
        elseif item:IsA("BasePart") then
            item.Anchored = false
        end
        
        btn.Text = "Done!"
        notify("Bring", "Ladder Brought 🔒")
        task.wait(1)
    else
        btn.Text = item and "No Character" or "Not Found"
        task.wait(1.5)
    end
    
    btn.Text = "Bring"
    isBringRunning = false
end

-- MOBILE GUI
local function createMobileGUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name, screenGui.ResetOnSpawn, screenGui.Parent = "LevitatoMobileGui", false, player:WaitForChild("PlayerGui")
	GUIrefs.screenGui = screenGui

	local bottomBar = Instance.new("Frame", screenGui)
	bottomBar.AnchorPoint, bottomBar.Size, bottomBar.Position = Vector2.new(0.5, 1), UDim2.new(0.9, 0, 0, 115), UDim2.new(0.5, 0, 1, -20)
	bottomBar.BackgroundColor3, bottomBar.BackgroundTransparency, bottomBar.BorderSizePixel = Color3.fromRGB(20,20,20), 0.45, 0
	Instance.new("UICorner", bottomBar).CornerRadius = UDim.new(0, 18)
	local stroke = Instance.new("UIStroke", bottomBar)
	stroke.Color, stroke.Thickness = Color3.fromRGB(80,80,80), 2

    local creditLabel = Instance.new("TextLabel")
    creditLabel.Size, creditLabel.Position, creditLabel.BackgroundTransparency, creditLabel.Text, creditLabel.TextColor3, creditLabel.Font, creditLabel.TextSize, creditLabel.ZIndex, creditLabel.Parent = UDim2.new(1,0,0,25), UDim2.new(0,0,0,8), 1, "MADE BY A12Dqq", Color3.fromRGB(255,255,255), Enum.Font.GothamBold, 13, 5, bottomBar

    local buttonContainer = Instance.new("Frame", bottomBar)
    buttonContainer.Size, buttonContainer.Position, buttonContainer.BackgroundTransparency = UDim2.new(1,0,1,-35), UDim2.new(0,0,0,32), 1

	local layout = Instance.new("UIListLayout", buttonContainer)
	layout.FillDirection, layout.HorizontalAlignment, layout.VerticalAlignment, layout.Padding, layout.SortOrder = Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center, UDim.new(0, 8), Enum.SortOrder.LayoutOrder

	local function makeButton(name, text, size, order)
		local b = Instance.new("TextButton")
		b.Name, b.Text, b.Size, b.LayoutOrder, b.Font, b.TextScaled, b.TextColor3 = name, text, size or UDim2.new(0,90,0,60), order or 0, Enum.Font.GothamBold, true, Color3.fromRGB(240,240,240)
		b.BackgroundColor3, b.BackgroundTransparency = Color3.fromRGB(30,30,30), 0.55
		Instance.new("UICorner", b).CornerRadius = UDim.new(0,14)
		return b
	end

    local bypassBtn = makeButton("BypassBtn", "Bypass", UDim2.new(0,85,0,62), 1)
    bypassBtn.Parent = buttonContainer
    bypassBtn.MouseButton1Click:Connect(function() executeBypassSequence(bypassBtn) end)

    local bringBtn = makeButton("BringBtn", "Bring", UDim2.new(0,85,0,62), 2)
    bringBtn.Parent = buttonContainer
    bringBtn.MouseButton1Click:Connect(function() bringLadder(bringBtn) end)

    local anchorBtn = makeButton("AnchorBtn", "Anchor", UDim2.new(0,80,0,62), 3)
    anchorBtn.Parent = buttonContainer
    anchorBtn.MouseButton1Click:Connect(toggleAnchor)

	local grabBtn = makeButton("GrabBtn", "Grab", UDim2.new(0,85,0,62), 4)
	grabBtn.Parent = buttonContainer

    local noclipBtn = makeButton("NoclipBtn", "Noclip OFF", UDim2.new(0,90,0,62), 5)
	noclipBtn.Parent = buttonContainer

	local magnetBtn = makeButton("MagnetBtn", "Magnet", UDim2.new(0,85,0,62), 6)
	magnetBtn.Parent = buttonContainer

	local throwBtn = makeButton("ThrowBtn", "Throw", UDim2.new(0,85,0,62), 7)
	throwBtn.Parent = buttonContainer

    local zoomStack = Instance.new("Frame", buttonContainer)
    zoomStack.Size, zoomStack.BackgroundTransparency, zoomStack.LayoutOrder = UDim2.new(0,45,0,62), 1, 8
    local stackLayout = Instance.new("UIListLayout", zoomStack)
    stackLayout.Padding, stackLayout.HorizontalAlignment, stackLayout.VerticalAlignment = UDim.new(0,4), Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center

	local zoomInBtn = makeButton("ZoomInBtn", "+", UDim2.new(0,45,0,29), 1)
	zoomInBtn.Parent = zoomStack
	local zoomOutBtn = makeButton("ZoomOutBtn", "-", UDim2.new(0,45,0,29), 2)
	zoomOutBtn.Parent = zoomStack

	GUIrefs.noclipBtn, GUIrefs.anchorBtn, GUIrefs.zoomInBtn, GUIrefs.zoomOutBtn, GUIrefs.magnetBtn, GUIrefs.grabBtn, GUIrefs.throwBtn = noclipBtn, anchorBtn, zoomInBtn, zoomOutBtn, magnetBtn, grabBtn, throwBtn

    noclipBtn.MouseButton1Click:Connect(toggleNoclip)
	magnetBtn.MouseButton1Click:Connect(toggleMagnet)
	grabBtn.MouseButton1Click:Connect(grabOrRelease)
	throwBtn.MouseButton1Click:Connect(throw)
	zoomInBtn.MouseButton1Down:Connect(function() holdRight = true end)
	zoomInBtn.MouseButton1Up:Connect(function() holdRight = false end)
	zoomOutBtn.MouseButton1Down:Connect(function() holdLeft = true end)
	zoomOutBtn.MouseButton1Up:Connect(function() holdLeft = false end)

    local hideBtn = makeButton("HideBtn", "Hide UI", UDim2.new(0, 80, 0, 35))
    hideBtn.AnchorPoint, hideBtn.Position, hideBtn.Parent = Vector2.new(1, 0), UDim2.new(1, -10, 0, 10), screenGui
    
    local closeBtn = makeButton("CloseBtn", "X", UDim2.new(0, 25, 0, 25))
    closeBtn.BackgroundColor3, closeBtn.AnchorPoint, closeBtn.Position, closeBtn.ZIndex, closeBtn.Visible, closeBtn.Parent = Color3.fromRGB(200, 50, 50), Vector2.new(1, 0), UDim2.new(1, -5, 0, -10), 10, false, hideBtn
    
    hideBtn.MouseButton1Click:Connect(function()
        guiHidden = not guiHidden
        bottomBar.Visible = not guiHidden
        closeBtn.Visible = guiHidden 
        hideBtn.Text = guiHidden and "Show UI" or "Hide UI"
    end)
    
    closeBtn.MouseButton1Click:Connect(killScript)

	local vm = Instance.new("Frame", screenGui)
	vm.Size, vm.BackgroundTransparency, vm.BackgroundColor3, vm.ZIndex = UDim2.new(0,virtualMouseSize,0,virtualMouseSize), 0.6, Color3.fromRGB(10,10,10), 2
	Instance.new("UICorner", vm).CornerRadius = UDim.new(1,0)
	Instance.new("UIStroke", vm).Color, Instance.new("UIStroke", vm).Thickness = Color3.fromRGB(60,160,255), 2
	GUIrefs.vm = vm

	local vmCircle = Instance.new("ImageLabel", screenGui)
	vmCircle.BackgroundTransparency, vmCircle.Image, vmCircle.ImageColor3, vmCircle.ImageTransparency, vmCircle.ZIndex = 1, "rbxassetid://13523341990", circleColor, 0.5, 1
	GUIrefs.vmCircle = vmCircle

	screenGui.Enabled = UIS.TouchEnabled
end

createMobileGUI()
updateButtonStates()
notify("Script Status", "Ready to Use")
 |_______ \____/(____  /\_______  /___  /__| |____//____  >\___  >____  /__|  \____/|__|   
         \/          \/         \/    \/                \/     \/     \/                   
          \_Welcome to LuaObfuscator.com   (Alpha 0.10.9) ~  Much Love, Ferib 

]]--

local obf_stringchar = string.char;
local obf_stringbyte = string.byte;
local obf_stringsub = string.sub;
local obf_bitlib = bit32 or bit;
local obf_XOR = obf_bitlib.bxor;
local obf_tableconcat = table.concat;
local obf_tableinsert = table.insert;
local function LUAOBFUSACTOR_DECRYPT_STR_0(LUAOBFUSACTOR_STR, LUAOBFUSACTOR_KEY)
	local result = {};
	for i = 1, #LUAOBFUSACTOR_STR do
		obf_tableinsert(result, obf_stringchar(obf_XOR(obf_stringbyte(obf_stringsub(LUAOBFUSACTOR_STR, i, i + 1)), obf_stringbyte(obf_stringsub(LUAOBFUSACTOR_KEY, 1 + (i % #LUAOBFUSACTOR_KEY), 1 + (i % #LUAOBFUSACTOR_KEY) + 1))) % 256));
	end
	return obf_tableconcat(result);
end
local player = game.Players.LocalPlayer;
local camera = workspace.CurrentCamera;
local run, UIS = game:GetService(LUAOBFUSACTOR_DECRYPT_STR_0("\227\214\213\22\227\169\209\23\210\198", "\126\177\163\187\69\134\219\167")), game:GetService(LUAOBFUSACTOR_DECRYPT_STR_0("\22\222\47\215\213\45\221\63\209\207\38\223\60\204\255\38", "\156\67\173\74\165"));
local starterGui = game:GetService(LUAOBFUSACTOR_DECRYPT_STR_0("\7\163\72\4\168\35\84\19\162\64", "\38\84\215\41\118\220\70"));
local VIM = game:GetService(LUAOBFUSACTOR_DECRYPT_STR_0("\102\31\48\6\235\81\26\11\28\238\69\2\15\19\240\81\17\39\0", "\158\48\118\66\114"));
local holding, target, holdDistance, anchoredWhileHolding = false, nil, 10, false;
local holdLeft, holdRight, holdQ, holdE = false, false, false, false;
local scriptRunning = true;
local noclipActive = false;
local vel = Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\137\43\20\47\69\160\247\164\39\25\34\106", "\155\203\68\112\86\19\197"));
vel.MaxForce = Vector3.new(1, 1, 1) * 100000;
vel.P = 12500;
local gyro = Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\100\210\50\229\103\97\247\247", "\152\38\189\86\156\32\24\133"));
gyro.MaxTorque = Vector3.new(1, 1, 1) * 1000000;
gyro.P = 3000;
local originalRotation = nil;
local SelectionBox = Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\207\82\171\67\255\67\174\73\242\117\168\94", "\38\156\55\199"));
SelectionBox.Name = LUAOBFUSACTOR_DECRYPT_STR_0("\135\104\104\36\26\122\255", "\35\200\29\28\72\115\20\154");
SelectionBox.LineThickness = 0.08;
SelectionBox.Parent = game:GetService(LUAOBFUSACTOR_DECRYPT_STR_0("\58\176\195\218\170\57\61", "\84\121\223\177\191\237\76"));
local magnetActive, magnetRadius, magnetForce = false, 30, 200;
local magnetObjects, gravityBackup = {}, {};
local currentRadius = magnetRadius;
local usingDrawing = Drawing and Drawing.new and (typeof(Drawing.new) == LUAOBFUSACTOR_DECRYPT_STR_0("\189\67\199\163\46\89\63\207", "\161\219\54\169\192\90\48\80"));
local magnetCircle, circleGui, circleImg;
local circleColor = Color3.fromRGB(0, 170, 255);
local surfacePos, surfaceNormal = Vector3.zero, Vector3.new(0, 1, 0);
if usingDrawing then
	magnetCircle = Drawing.new(LUAOBFUSACTOR_DECRYPT_STR_0("\106\75\18\38\69\71", "\69\41\34\96"));
	magnetCircle.Visible, magnetCircle.Transparency, magnetCircle.Color, magnetCircle.Thickness, magnetCircle.Filled = false, 1, circleColor, 2, false;
else
	circleGui = Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\158\202\219\6\0\36\189\209\211\45\23\34", "\75\220\163\183\106\98"));
	circleGui.Name, circleGui.Size, circleGui.SizeOffset, circleGui.AlwaysOnTop = LUAOBFUSACTOR_DECRYPT_STR_0("\47\187\140\57\220\22\153\130\37\218\14\191\172\34\208", "\185\98\218\235\87"), UDim2.new(2, 0, 2, 0), Vector2.new(0, 0), true;
	circleGui.Parent = workspace;
	circleImg = Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\226\49\38\225\219\134\202\62\34\234", "\202\171\92\71\134\190"));
	circleImg.BackgroundTransparency, circleImg.Image, circleImg.ImageColor3 = 1, LUAOBFUSACTOR_DECRYPT_STR_0("\59\195\52\137\58\210\41\156\32\197\118\199\102\144\127\221\123\146\127\220\120\152\117\216", "\232\73\161\76"), circleColor;
	circleImg.AnchorPoint, circleImg.Position, circleImg.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1);
	circleImg.Parent, circleGui.Enabled = circleImg, false;
end
local virtualMouseSize = 60;
local virtualMouseEnabled = UIS.TouchEnabled;
local virtualMouseCenter = Vector2.new(0.5, 0.45);
local GUIrefs = {};
local guiHidden = false;
local function notify(title, text)
	starterGui:SetCore(LUAOBFUSACTOR_DECRYPT_STR_0("\136\220\76\89\48\180\205\75\91\23\184\216\86\84\17\181", "\126\219\185\34\61"), {[LUAOBFUSACTOR_DECRYPT_STR_0("\56\199\74\126\123", "\135\108\174\62\18\30\23\147")]=title,[LUAOBFUSACTOR_DECRYPT_STR_0("\130\236\50\223", "\167\214\137\74\171\120\206\83")]=text,[LUAOBFUSACTOR_DECRYPT_STR_0("\175\229\32\92\236\174\132\254", "\199\235\144\82\61\152")]=2});
end
local function isCharacterPart(obj)
	for _, plr in ipairs(game.Players:GetPlayers()) do
		if (plr.Character and obj:IsDescendantOf(plr.Character)) then
			return true;
		end
	end
	return false;
end
local function isAccessory(obj)
	return obj:FindFirstAncestorOfClass(LUAOBFUSACTOR_DECRYPT_STR_0("\38\21\186\46\20\5\182\57\30", "\75\103\118\217")) ~= nil;
end
local function restoreGravity()
	for obj, oldGravity in pairs(gravityBackup) do
		if (obj and obj:IsDescendantOf(workspace)) then
			obj.CustomPhysicalProperties = oldGravity;
		end
	end
	gravityBackup = {};
end
local function lerpVec3(a, b, t)
	return a + ((b - a) * t);
end
local function getScreenSize()
	local vs = camera.ViewportSize;
	return vs.X, vs.Y;
end
local function computeVirtualCenterPixels()
	local sx, sy = getScreenSize();
	return Vector2.new(sx * virtualMouseCenter.X, sy * virtualMouseCenter.Y);
end
local function getInputPosition()
	if (UIS.TouchEnabled and virtualMouseEnabled) then
		local vmPos = computeVirtualCenterPixels();
		return vmPos.X, vmPos.Y;
	end
	local pos = UIS:GetMouseLocation();
	return pos.X, pos.Y;
end
local function raycastFromScreen(x, y, maxDist)
	local ray = camera:ScreenPointToRay(x, y);
	local dist = maxDist or 1000;
	return workspace:FindPartOnRayWithIgnoreList(Ray.new(ray.Origin, ray.Direction * dist), {player.Character});
end
local function killScript()
	scriptRunning = false;
	noclipActive = false;
	if GUIrefs.screenGui then
		GUIrefs.screenGui:Destroy();
	end
	if SelectionBox then
		SelectionBox:Destroy();
	end
	if magnetCircle then
		magnetCircle:Remove();
	end
	if circleGui then
		circleGui:Destroy();
	end
	for _, part in pairs(workspace:GetDescendants()) do
		if part:IsA(LUAOBFUSACTOR_DECRYPT_STR_0("\229\85\99\17\137\31\213\64", "\126\167\52\16\116\217")) then
			part.CanCollide = true;
		end
	end
	restoreGravity();
	if vel then
		vel:Destroy();
	end
	if gyro then
		gyro:Destroy();
	end
	notify(LUAOBFUSACTOR_DECRYPT_STR_0("\251\58\33\148\161\10", "\156\168\78\64\224\212\121"), LUAOBFUSACTOR_DECRYPT_STR_0("\52\237\183\199\23\250\229\250\2\252\168\199\9\239\177\203\3", "\174\103\142\197"));
end
local function updateButtonStates()
	if not scriptRunning then
		return;
	end
	if (GUIrefs.magnetBtn and GUIrefs.grabBtn and GUIrefs.noclipBtn) then
		if magnetActive then
			GUIrefs.magnetBtn.BackgroundColor3 = Color3.fromRGB(25, 130, 255);
			GUIrefs.magnetBtn.Text = "Magnet ✓";
		else
			GUIrefs.magnetBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30);
			GUIrefs.magnetBtn.Text = LUAOBFUSACTOR_DECRYPT_STR_0("\123\41\88\54\32\74", "\152\54\72\63\88\69\62");
		end
		if holding then
			GUIrefs.grabBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 100);
			GUIrefs.grabBtn.Text = LUAOBFUSACTOR_DECRYPT_STR_0("\230\193\226\89\213\215\235", "\60\180\164\142");
		else
			GUIrefs.grabBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30);
			GUIrefs.grabBtn.Text = LUAOBFUSACTOR_DECRYPT_STR_0("\127\76\4\43", "\114\56\62\101\73\71\141");
		end
		if noclipActive then
			GUIrefs.noclipBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 100);
			GUIrefs.noclipBtn.Text = LUAOBFUSACTOR_DECRYPT_STR_0("\150\230\216\200\177\249\155\235\150", "\164\216\137\187");
		else
			GUIrefs.noclipBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30);
			GUIrefs.noclipBtn.Text = LUAOBFUSACTOR_DECRYPT_STR_0("\252\233\50\190\175\238\75\253\192\23", "\107\178\134\81\210\198\158");
		end
	end
end
local function updateVMVisuals()
	if not scriptRunning then
		return;
	end
	local screenX, screenY = getScreenSize();
	local vPos = computeVirtualCenterPixels();
	if not GUIrefs.screenGui then
		return;
	end
	if (GUIrefs.vm and vPos) then
		local px = math.clamp(vPos.X - (virtualMouseSize / 2), 0, screenX - virtualMouseSize);
		local py = math.clamp(vPos.Y - (virtualMouseSize / 2), 0, screenY - virtualMouseSize);
		GUIrefs.vm.Position = UDim2.new(0, px, 0, py);
		GUIrefs.vm.Visible = not guiHidden;
	end
	if GUIrefs.vmCircle then
		local cx, cy = getInputPosition();
		local radiusScreenScale = 2;
		local radPx = math.clamp(math.floor(magnetRadius * radiusScreenScale), 8, math.min(screenX, screenY));
		GUIrefs.vmCircle.Size = UDim2.new(0, radPx * 2, 0, radPx * 2);
		GUIrefs.vmCircle.Position = UDim2.new(0, cx - radPx, 0, cy - radPx);
		GUIrefs.vmCircle.ImageColor3 = (magnetActive and Color3.fromRGB(60, 170, 255)) or Color3.fromRGB(80, 80, 80);
		GUIrefs.vmCircle.Visible = magnetActive and not guiHidden;
	end
end
run.RenderStepped:Connect(function()
	if not scriptRunning then
		return;
	end
	if guiHidden then
		SelectionBox.Adornee = nil;
	elseif (magnetActive and not holding) then
		SelectionBox.Adornee = nil;
	elseif (holding and target) then
		SelectionBox.Color3, SelectionBox.Adornee = Color3.fromRGB(150, 50, 255), target;
	else
		local sx, sy = getInputPosition();
		local hit, pos = raycastFromScreen(sx, sy, 1000);
		if (hit and hit:IsA(LUAOBFUSACTOR_DECRYPT_STR_0("\26\15\145\195\154\57\28\150", "\202\88\110\226\166")) and not hit.Anchored and not isCharacterPart(hit)) then
			SelectionBox.Color3, SelectionBox.Adornee = Color3.fromRGB(0, 170, 255), hit;
		else
			SelectionBox.Adornee = nil;
		end
	end
	if (magnetActive and not guiHidden) then
		local sx, sy = getInputPosition();
		local ray = camera:ScreenPointToRay(sx, sy);
		local hit, pos, norm = workspace:FindPartOnRayWithIgnoreList(Ray.new(ray.Origin, ray.Direction * 1000), {player.Character});
		if hit then
			surfacePos, surfaceNormal = lerpVec3(surfacePos, pos, 0.35), lerpVec3(surfaceNormal, norm, 0.35);
		else
			local defPos = ray.Origin + (ray.Direction * 15);
			surfacePos, surfaceNormal = lerpVec3(surfacePos, defPos, 0.15), lerpVec3(surfaceNormal, Vector3.new(0, 1, 0), 0.15);
		end
		currentRadius = currentRadius + ((magnetRadius - currentRadius) * 0.25);
		if usingDrawing then
			local screenPos = camera:WorldToViewportPoint(surfacePos);
			magnetCircle.Visible, magnetCircle.Position, magnetCircle.Radius = true, Vector2.new(screenPos.X, screenPos.Y), currentRadius;
		else
			circleGui.Enabled, circleGui.Size = true, UDim2.new(0, currentRadius * 2, 0, currentRadius * 2);
			circleGui.CFrame = CFrame.new(surfacePos, surfacePos + camera.CFrame.LookVector) * CFrame.fromMatrix(Vector3.zero, ((surfaceNormal:Cross(Vector3.new(0, 1, 0)).Magnitude > 0.01) and surfaceNormal:Cross(Vector3.new(0, 1, 0)).Unit) or Vector3.new(1, 0, 0), surfaceNormal, -surfaceNormal:Cross(Vector3.new(1, 0, 0)).Unit);
			circleGui.Position = surfacePos;
		end
	elseif usingDrawing then
		magnetCircle.Visible = false;
	elseif circleGui then
		circleGui.Enabled = false;
	end
	updateVMVisuals();
	updateButtonStates();
end);
run.Heartbeat:Connect(function()
	if not scriptRunning then
		return;
	end
	if player.Character then
		for _, item in pairs(player.Character:GetDescendants()) do
			if (item:IsA(LUAOBFUSACTOR_DECRYPT_STR_0("\225\14\145\242\250\194\29\150", "\170\163\111\226\151")) and isAccessory(item)) then
				item.CanCollide = false;
			end
		end
	end
	if noclipActive then
		for _, part in pairs(workspace:GetDescendants()) do
			if (part:IsA(LUAOBFUSACTOR_DECRYPT_STR_0("\51\49\161\61\126\54\59\5", "\73\113\80\210\88\46\87")) and not part.Anchored and not isCharacterPart(part) and not isAccessory(part)) then
				part.CanCollide = false;
			end
		end
	end
	if (holding and target) then
		if not anchoredWhileHolding then
			local sx, sy = getInputPosition();
			local ray = camera:ScreenPointToRay(sx, sy);
			local grabPos = ray.Origin + (ray.Direction.Unit * holdDistance);
			vel.Velocity = (grabPos - target.Position) * 5;
			if originalRotation then
				gyro.CFrame = originalRotation + target.Position;
			end
		else
			vel.Velocity = Vector3.zero;
		end
	end
	if magnetActive then
		local center, newAttracted = surfacePos, {};
		local nearby = workspace:GetPartBoundsInBox(CFrame.new(center), Vector3.new(magnetRadius * 2, magnetRadius * 2, magnetRadius * 2));
		for _, obj in ipairs(nearby) do
			if (obj:IsA(LUAOBFUSACTOR_DECRYPT_STR_0("\163\45\222\23\215\128\62\217", "\135\225\76\173\114")) and not obj.Anchored and not isCharacterPart(obj) and (obj.Transparency < 1) and obj.CanCollide and (obj ~= target)) then
				local bv = obj:FindFirstChild(LUAOBFUSACTOR_DECRYPT_STR_0("\55\236\191\190\169\169\133\44", "\199\122\141\216\208\204\221")) or Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\143\210\20\233\78\243\161\210\19\249\108\239", "\150\205\189\112\144\24"));
				bv.Name, bv.MaxForce, bv.P = LUAOBFUSACTOR_DECRYPT_STR_0("\8\133\184\66\1\156\51\38", "\112\69\228\223\44\100\232\113"), Vector3.new(1, 1, 1) * 100000, 15000;
				local dir = (center - obj.Position) * Vector3.new(1, 0, 1);
				bv.Velocity = ((dir.Magnitude > 0) and (dir.Unit * magnetForce)) or Vector3.zero;
				bv.Parent = obj;
				if not gravityBackup[obj] then
					gravityBackup[obj] = obj.CustomPhysicalProperties;
					obj.CustomPhysicalProperties = PhysicalProperties.new(0, 0.3, 0.5, 1, 1);
				end
				newAttracted[obj] = true;
			end
		end
		for obj in pairs(magnetObjects) do
			if not newAttracted[obj] then
				if (obj and obj:FindFirstChild(LUAOBFUSACTOR_DECRYPT_STR_0("\249\30\0\221\179\104\164\226", "\230\180\127\103\179\214\28"))) then
					obj.MagnetBV:Destroy();
				end
				if gravityBackup[obj] then
					obj.CustomPhysicalProperties = gravityBackup[obj];
					gravityBackup[obj] = nil;
				end
			end
		end
		magnetObjects = newAttracted;
	else
		for obj in pairs(magnetObjects) do
			if (obj and obj:FindFirstChild(LUAOBFUSACTOR_DECRYPT_STR_0("\161\4\88\72\225\85\194\186", "\128\236\101\63\38\132\33"))) then
				obj.MagnetBV:Destroy();
			end
		end
		restoreGravity();
		magnetObjects = {};
	end
	if magnetActive then
		if (holdLeft or holdQ) then
			magnetRadius = math.max(5, magnetRadius - 1.3);
		elseif (holdRight or holdE) then
			magnetRadius = math.min(200, magnetRadius + 1.3);
		end
	elseif (holdLeft or holdQ) then
		holdDistance = math.max(2, holdDistance - 0.4);
	elseif (holdRight or holdE) then
		holdDistance = math.min(1000, holdDistance + 0.4);
	end
end);
function grabOrRelease()
	if (not scriptRunning or magnetActive) then
		return;
	end
	if holding then
		originalRotation, vel.Parent, gyro.Parent, anchoredWhileHolding, target, holding = nil, nil, nil, false, nil, false;
		notify(LUAOBFUSACTOR_DECRYPT_STR_0("\139\187\16\70\180\238\221", "\175\204\201\113\36\214\139"), "Object Released ✋");
	else
		local sx, sy = getInputPosition();
		local part, pos = raycastFromScreen(sx, sy, 1000);
		if (part and part:IsA(LUAOBFUSACTOR_DECRYPT_STR_0("\101\205\38\217\52\70\222\33", "\100\39\172\85\188")) and not part.Anchored and not isCharacterPart(part)) then
			target, anchoredWhileHolding = part, false;
			originalRotation = part.CFrame - part.Position;
			gyro.CFrame, gyro.Parent, vel.Velocity, vel.Parent = originalRotation + part.Position, part, Vector3.zero, part;
			holdDistance = (camera.CFrame.Position - pos).Magnitude;
			holding = true;
			notify(LUAOBFUSACTOR_DECRYPT_STR_0("\138\106\184\130\49\168\106", "\83\205\24\217\224"), "Object Caught ✊");
		end
	end
	updateButtonStates();
end
function throw()
	if (not scriptRunning or magnetActive or not holding or not target) then
		return;
	end
	if anchoredWhileHolding then
		target.Anchored, anchoredWhileHolding = false, false;
	end
	vel.Parent, gyro.Parent, holding, originalRotation = nil, nil, false, nil;
	local impulse = Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\196\202\201\36\208\192\193\50\229\204\217\36", "\93\134\165\173"));
	impulse.Velocity, impulse.MaxForce, impulse.P, impulse.Parent = camera.CFrame.LookVector * 1000, Vector3.new(1, 1, 1) * 1000000, 12500, target;
	game:GetService(LUAOBFUSACTOR_DECRYPT_STR_0("\154\247\195\208\51\221", "\30\222\146\161\162\90\174\210")):AddItem(impulse, 0.5);
	target = nil;
	notify(LUAOBFUSACTOR_DECRYPT_STR_0("\194\92\113\8\231\75\98", "\106\133\46\16"), LUAOBFUSACTOR_DECRYPT_STR_0("\119\34\121\249\89\84\24\20\123\238\85\87\86", "\32\56\64\19\156\58"));
	updateButtonStates();
end
function toggleAnchor()
	if (not scriptRunning or magnetActive or not holding or not target) then
		return;
	end
	anchoredWhileHolding = not anchoredWhileHolding;
	target.Anchored = anchoredWhileHolding;
	if anchoredWhileHolding then
		vel.Parent, gyro.Parent = nil, nil;
		target.AssemblyLinearVelocity, target.AssemblyAngularVelocity = Vector3.zero, Vector3.zero;
		notify(LUAOBFUSACTOR_DECRYPT_STR_0("\123\198\230\94\85\224", "\224\58\168\133\54\58\146"), "Object Locked 📌");
	else
		vel.Parent, gyro.Parent = target, target;
		notify(LUAOBFUSACTOR_DECRYPT_STR_0("\120\88\72\245\122\148", "\107\57\54\43\157\21\230\231"), "Object Unlocked ❌");
	end
end
function toggleMagnet()
	if (not scriptRunning or holding) then
		return;
	end
	magnetActive = not magnetActive;
	if not magnetActive then
		restoreGravity();
	end
	notify(LUAOBFUSACTOR_DECRYPT_STR_0("\246\138\22\251\188\200", "\175\187\235\113\149\217\188"), (magnetActive and "Magnet Enabled 🧲") or "Magnet Disabled ❌");
	updateButtonStates();
end
function toggleNoclip()
	if not scriptRunning then
		return;
	end
	noclipActive = not noclipActive;
	if not noclipActive then
		for _, part in pairs(workspace:GetDescendants()) do
			if (part:IsA(LUAOBFUSACTOR_DECRYPT_STR_0("\30\174\146\73\211\120\106\40", "\24\92\207\225\44\131\25")) and not part.Anchored and not isCharacterPart(part) and not isAccessory(part)) then
				part.CanCollide = true;
			end
		end
	end
	notify(LUAOBFUSACTOR_DECRYPT_STR_0("\101\220\187\64\18\109", "\29\43\179\216\44\123"), (noclipActive and "Noclip Enabled 👻") or "Noclip Disabled ❌");
	updateButtonStates();
end
local isBypassRunning = false;
local bypassCancelTriggered = false;
local function executeBypassSequence(btn)
	if isBypassRunning then
		bypassCancelTriggered = true;
		return;
	end
	isBypassRunning = true;
	bypassCancelTriggered = false;
	local char = player.Character;
	local root = char and char:FindFirstChild(LUAOBFUSACTOR_DECRYPT_STR_0("\149\204\45\77\179\214\41\72\143\214\47\88\141\216\50\88", "\44\221\185\64"));
	if not root then
		btn.Text = LUAOBFUSACTOR_DECRYPT_STR_0("\36\245\90\80\97\91\167\107\87\114\19", "\19\97\135\40\63");
		isBypassRunning = false;
		return;
	end
	root.CFrame = root.CFrame * CFrame.new(0, 99999999, 0);
	local ladder = player.Backpack:FindFirstChild(LUAOBFUSACTOR_DECRYPT_STR_0("\130\93\55\63\42\35", "\81\206\60\83\91\79")) or char:FindFirstChild(LUAOBFUSACTOR_DECRYPT_STR_0("\98\170\212\118\42\209", "\196\46\203\176\18\79\163\45"));
	if ladder then
		ladder.Parent = char;
		task.wait(0.2);
		ladder:Activate();
		VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0);
		VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0);
	end
	btn.Text = LUAOBFUSACTOR_DECRYPT_STR_0("\139\7\95\44\7\211\198\150\5\48\80\106", "\143\216\66\30\126\68\155");
	local targetItem = nil;
	while not targetItem do
		if bypassCancelTriggered then
			break;
		end
		targetItem = workspace:FindFirstChild(LUAOBFUSACTOR_DECRYPT_STR_0("\143\228\36\228\235\243\135\178\149\196\12\207\193\166\197", "\129\202\168\109\171\165\195\183"), true);
		if not targetItem then
			task.wait(0.1);
		end
	end
	if bypassCancelTriggered then
		btn.Text = LUAOBFUSACTOR_DECRYPT_STR_0("\0\65\39\217\205\7", "\134\66\56\87\184\190\116");
		isBypassRunning = false;
		return;
	end
	local savedStates = {};
	local parts = (targetItem:IsA(LUAOBFUSACTOR_DECRYPT_STR_0("\17\62\13\190\21", "\85\92\81\105\219\121\139\65")) and targetItem:GetDescendants()) or {targetItem};
	for _, p in pairs(parts) do
		if p:IsA(LUAOBFUSACTOR_DECRYPT_STR_0("\223\178\67\64\76\222\239\167", "\191\157\211\48\37\28")) then
			savedStates[p] = p.Anchored;
			p.Anchored = true;
		end
	end
	for i = 3, 1, -1 do
		if bypassCancelTriggered then
			break;
		end
		btn.Text = LUAOBFUSACTOR_DECRYPT_STR_0("\252\62\218\63\31\243\95\188", "\90\191\127\148\124") .. i .. LUAOBFUSACTOR_DECRYPT_STR_0("\107\206", "\119\24\231\78");
		task.wait(1);
	end
	if not bypassCancelTriggered then
		local spawnPos = root.CFrame * CFrame.new(0, 0, -3.5);
		if targetItem:IsA(LUAOBFUSACTOR_DECRYPT_STR_0("\175\34\161\79\208", "\113\226\77\197\42\188\32")) then
			targetItem:PivotTo(spawnPos);
		else
			targetItem.CFrame = spawnPos;
		end
		btn.Text = LUAOBFUSACTOR_DECRYPT_STR_0("\28\63\218\156\9\62\209\145\123", "\213\90\118\148");
		notify(LUAOBFUSACTOR_DECRYPT_STR_0("\121\55\164\87\94\72", "\45\59\78\212\54"), "Ladder Bypassed 📶");
		task.wait(1.2);
	end
	for p, state in pairs(savedStates) do
		p.Anchored = state;
	end
	btn.Text = LUAOBFUSACTOR_DECRYPT_STR_0("\50\79\147\138\149\61", "\144\112\54\227\235\230\78\205");
	isBypassRunning = false;
end
local isBringRunning = false;
local function bringLadder(btn)
	if isBringRunning then
		return;
	end
	isBringRunning = true;
	local itemName = LUAOBFUSACTOR_DECRYPT_STR_0("\150\4\38\211\254\11\227\123\48\240\209\95\183\45\29", "\59\211\72\111\156\176");
	local distance = 5;
	local char = player.Character or player.CharacterAdded:Wait();
	local rootPart = char:FindFirstChild(LUAOBFUSACTOR_DECRYPT_STR_0("\102\146\238\44\64\136\234\41\124\136\236\57\126\134\241\57", "\77\46\231\131"));
	local item = workspace:FindFirstChild(itemName, true);
	if (item and rootPart) then
		local spawnPos = rootPart.CFrame + (rootPart.CFrame.LookVector * distance);
		btn.Text = LUAOBFUSACTOR_DECRYPT_STR_0("\142\81\186\69\170\91\164\84\179\90\177\14\244\26", "\32\218\52\214");
		if item:IsA(LUAOBFUSACTOR_DECRYPT_STR_0("\99\24\53\173\253", "\58\46\119\81\200\145\208\37")) then
			item:PivotTo(spawnPos);
			for _, p in pairs(item:GetDescendants()) do
				if p:IsA(LUAOBFUSACTOR_DECRYPT_STR_0("\9\141\35\169\153\188\36\63", "\86\75\236\80\204\201\221")) then
					p.Anchored = true;
				end
			end
		elseif item:IsA(LUAOBFUSACTOR_DECRYPT_STR_0("\80\64\100\128\206\138\96\85", "\235\18\33\23\229\158")) then
			item.CFrame = spawnPos;
			item.Anchored = true;
		end
		task.wait(0.5);
		if item:IsA(LUAOBFUSACTOR_DECRYPT_STR_0("\125\181\197\190\92", "\219\48\218\161")) then
			for _, p in pairs(item:GetDescendants()) do
				if p:IsA(LUAOBFUSACTOR_DECRYPT_STR_0("\198\112\111\76\235\78\242\240", "\128\132\17\28\41\187\47")) then
					p.Anchored = false;
				end
			end
		elseif item:IsA(LUAOBFUSACTOR_DECRYPT_STR_0("\35\51\21\63\109\0\32\18", "\61\97\82\102\90")) then
			item.Anchored = false;
		end
		btn.Text = LUAOBFUSACTOR_DECRYPT_STR_0("\136\33\165\78\134", "\105\204\78\203\43\167\55\126");
		notify(LUAOBFUSACTOR_DECRYPT_STR_0("\135\184\42\16\20", "\49\197\202\67\126\115\100\167"), "Ladder Brought 🔒");
		task.wait(1);
	else
		btn.Text = (item and LUAOBFUSACTOR_DECRYPT_STR_0("\25\84\159\10\136\87\76\54\88\203\44\146", "\62\87\59\191\73\224\54")) or LUAOBFUSACTOR_DECRYPT_STR_0("\201\13\238\137\193\13\239\199\227", "\169\135\98\154");
		task.wait(1.5);
	end
	btn.Text = LUAOBFUSACTOR_DECRYPT_STR_0("\233\101\45\90\250", "\168\171\23\68\52\157\83");
	isBringRunning = false;
end
local function createMobileGUI()
	local screenGui = Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\199\114\231\168\32\35\160\225\120", "\231\148\17\149\205\69\77"));
	screenGui.Name, screenGui.ResetOnSpawn, screenGui.Parent = LUAOBFUSACTOR_DECRYPT_STR_0("\172\162\209\242\67\254\148\168\234\244\85\246\140\162\224\238\94", "\159\224\199\167\155\55"), false, player:WaitForChild(LUAOBFUSACTOR_DECRYPT_STR_0("\199\255\61\203\242\225\27\199\254", "\178\151\147\92"));
	GUIrefs.screenGui = screenGui;
	local bottomBar = Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\170\239\77\63\23", "\26\236\157\44\82\114\44"), screenGui);
	bottomBar.AnchorPoint, bottomBar.Size, bottomBar.Position = Vector2.new(0.5, 1), UDim2.new(0.9, 0, 0, 115), UDim2.new(0.5, 0, 1, -20);
	bottomBar.BackgroundColor3, bottomBar.BackgroundTransparency, bottomBar.BorderSizePixel = Color3.fromRGB(20, 20, 20), 0.45, 0;
	Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\31\7\246\84\56\32\208\73", "\59\74\78\181"), bottomBar).CornerRadius = UDim.new(0, 18);
	local stroke = Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\16\248\105\78\161\42\218\95", "\211\69\177\58\58"), bottomBar);
	stroke.Color, stroke.Thickness = Color3.fromRGB(80, 80, 80), 2;
	local creditLabel = Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\131\224\97\225\197\202\181\224\117", "\171\215\133\25\149\137"));
	creditLabel.Size, creditLabel.Position, creditLabel.BackgroundTransparency, creditLabel.Text, creditLabel.TextColor3, creditLabel.Font, creditLabel.TextSize, creditLabel.ZIndex, creditLabel.Parent = UDim2.new(1, 0, 0, 25), UDim2.new(0, 0, 0, 8), 1, LUAOBFUSACTOR_DECRYPT_STR_0("\204\233\22\223\175\18\197\2\192\153\96\222\254\33", "\34\129\168\82\154\143\80\156"), Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 13, 5, bottomBar;
	local buttonContainer = Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\163\160\50\6\77", "\233\229\210\83\107\40\46"), bottomBar);
	buttonContainer.Size, buttonContainer.Position, buttonContainer.BackgroundTransparency = UDim2.new(1, 0, 1, -35), UDim2.new(0, 0, 0, 32), 1;
	local layout = Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\244\107\30\223\22\213\110\51\207\10\212\86", "\101\161\34\82\182"), buttonContainer);
	layout.FillDirection, layout.HorizontalAlignment, layout.VerticalAlignment, layout.Padding, layout.SortOrder = Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center, UDim.new(0, 8), Enum.SortOrder.LayoutOrder;
	local function makeButton(name, text, size, order)
		local b = Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\220\8\65\234\249\247\150\58\231\3", "\78\136\109\57\158\187\130\226"));
		b.Name, b.Text, b.Size, b.LayoutOrder, b.Font, b.TextScaled, b.TextColor3 = name, text, size or UDim2.new(0, 90, 0, 60), order or 0, Enum.Font.GothamBold, true, Color3.fromRGB(240, 240, 240);
		b.BackgroundColor3, b.BackgroundTransparency = Color3.fromRGB(30, 30, 30), 0.55;
		Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\11\22\218\254\44\49\252\227", "\145\94\95\153"), b).CornerRadius = UDim.new(0, 14);
		return b;
	end
	local bypassBtn = makeButton(LUAOBFUSACTOR_DECRYPT_STR_0("\223\212\4\212\93\164\223\217\26", "\215\157\173\116\181\46"), LUAOBFUSACTOR_DECRYPT_STR_0("\23\173\155\243\201\38", "\186\85\212\235\146"), UDim2.new(0, 85, 0, 62), 1);
	bypassBtn.Parent = buttonContainer;
	bypassBtn.MouseButton1Click:Connect(function()
		executeBypassSequence(bypassBtn);
	end);
	local bringBtn = makeButton(LUAOBFUSACTOR_DECRYPT_STR_0("\224\147\31\240\62\204\76\204", "\56\162\225\118\158\89\142"), LUAOBFUSACTOR_DECRYPT_STR_0("\126\23\201\161\37", "\184\60\101\160\207\66"), UDim2.new(0, 85, 0, 62), 2);
	bringBtn.Parent = buttonContainer;
	bringBtn.MouseButton1Click:Connect(function()
		bringLadder(bringBtn);
	end);
	local anchorBtn = makeButton(LUAOBFUSACTOR_DECRYPT_STR_0("\16\140\127\180\62\144\94\168\63", "\220\81\226\28"), LUAOBFUSACTOR_DECRYPT_STR_0("\50\219\129\243\229\213", "\167\115\181\226\155\138"), UDim2.new(0, 80, 0, 62), 3);
	anchorBtn.Parent = buttonContainer;
	anchorBtn.MouseButton1Click:Connect(toggleAnchor);
	local grabBtn = makeButton(LUAOBFUSACTOR_DECRYPT_STR_0("\197\48\230\94\89\101\200", "\166\130\66\135\60\27\17"), LUAOBFUSACTOR_DECRYPT_STR_0("\99\88\207\119", "\80\36\42\174\21"), UDim2.new(0, 85, 0, 62), 4);
	grabBtn.Parent = buttonContainer;
	local noclipBtn = makeButton(LUAOBFUSACTOR_DECRYPT_STR_0("\96\31\52\118\71\0\21\110\64", "\26\46\112\87"), LUAOBFUSACTOR_DECRYPT_STR_0("\151\44\168\120\182\175\5\155\159\5", "\212\217\67\203\20\223\223\37"), UDim2.new(0, 90, 0, 62), 5);
	noclipBtn.Parent = buttonContainer;
	local magnetBtn = makeButton(LUAOBFUSACTOR_DECRYPT_STR_0("\151\140\175\220\191\153\138\198\180", "\178\218\237\200"), LUAOBFUSACTOR_DECRYPT_STR_0("\155\180\225\222\179\161", "\176\214\213\134"), UDim2.new(0, 85, 0, 62), 6);
	magnetBtn.Parent = buttonContainer;
	local throwBtn = makeButton(LUAOBFUSACTOR_DECRYPT_STR_0("\192\165\164\219\191\116\77\250", "\57\148\205\214\180\200\54"), LUAOBFUSACTOR_DECRYPT_STR_0("\38\245\39\59\97", "\22\114\157\85\84"), UDim2.new(0, 85, 0, 62), 7);
	throwBtn.Parent = buttonContainer;
	local zoomStack = Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\226\217\18\201\88", "\200\164\171\115\164\61\150"), buttonContainer);
	zoomStack.Size, zoomStack.BackgroundTransparency, zoomStack.LayoutOrder = UDim2.new(0, 45, 0, 62), 1, 8;
	local stackLayout = Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\139\221\47\76\144\170\216\2\92\140\171\224", "\227\222\148\99\37"), zoomStack);
	stackLayout.Padding, stackLayout.HorizontalAlignment, stackLayout.VerticalAlignment = UDim.new(0, 4), Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center;
	local zoomInBtn = makeButton(LUAOBFUSACTOR_DECRYPT_STR_0("\9\93\93\251\208\61\112\70\248", "\153\83\50\50\150"), "+", UDim2.new(0, 45, 0, 29), 1);
	zoomInBtn.Parent = zoomStack;
	local zoomOutBtn = makeButton(LUAOBFUSACTOR_DECRYPT_STR_0("\103\121\124\17\92\190\89\127\98\125", "\45\61\22\19\124\19\203"), "-", UDim2.new(0, 45, 0, 29), 2);
	zoomOutBtn.Parent = zoomStack;
	GUIrefs.noclipBtn, GUIrefs.anchorBtn, GUIrefs.zoomInBtn, GUIrefs.zoomOutBtn, GUIrefs.magnetBtn, GUIrefs.grabBtn, GUIrefs.throwBtn = noclipBtn, anchorBtn, zoomInBtn, zoomOutBtn, magnetBtn, grabBtn, throwBtn;
	noclipBtn.MouseButton1Click:Connect(toggleNoclip);
	magnetBtn.MouseButton1Click:Connect(toggleMagnet);
	grabBtn.MouseButton1Click:Connect(grabOrRelease);
	throwBtn.MouseButton1Click:Connect(throw);
	zoomInBtn.MouseButton1Down:Connect(function()
		holdRight = true;
	end);
	zoomInBtn.MouseButton1Up:Connect(function()
		holdRight = false;
	end);
	zoomOutBtn.MouseButton1Down:Connect(function()
		holdLeft = true;
	end);
	zoomOutBtn.MouseButton1Up:Connect(function()
		holdLeft = false;
	end);
	local hideBtn = makeButton(LUAOBFUSACTOR_DECRYPT_STR_0("\233\27\9\240\32\100\183", "\217\161\114\109\149\98\16"), LUAOBFUSACTOR_DECRYPT_STR_0("\58\41\60\121\252\65\59", "\20\114\64\88\28\220"), UDim2.new(0, 80, 0, 35));
	hideBtn.AnchorPoint, hideBtn.Position, hideBtn.Parent = Vector2.new(1, 0), UDim2.new(1, -10, 0, 10), screenGui;
	local closeBtn = makeButton(LUAOBFUSACTOR_DECRYPT_STR_0("\18\13\221\167\253\242\169\63", "\221\81\97\178\212\152\176"), "X", UDim2.new(0, 25, 0, 25));
	closeBtn.BackgroundColor3, closeBtn.AnchorPoint, closeBtn.Position, closeBtn.ZIndex, closeBtn.Visible, closeBtn.Parent = Color3.fromRGB(200, 50, 50), Vector2.new(1, 0), UDim2.new(1, -5, 0, -10), 10, false, hideBtn;
	hideBtn.MouseButton1Click:Connect(function()
		guiHidden = not guiHidden;
		bottomBar.Visible = not guiHidden;
		closeBtn.Visible = guiHidden;
		hideBtn.Text = (guiHidden and LUAOBFUSACTOR_DECRYPT_STR_0("\254\239\18\236\90\248\206", "\122\173\135\125\155")) or LUAOBFUSACTOR_DECRYPT_STR_0("\172\200\4\188\127\4\225", "\168\228\161\96\217\95\81");
	end);
	closeBtn.MouseButton1Click:Connect(killScript);
	local vm = Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\253\195\47\81\42", "\55\187\177\78\60\79"), screenGui);
	vm.Size, vm.BackgroundTransparency, vm.BackgroundColor3, vm.ZIndex = UDim2.new(0, virtualMouseSize, 0, virtualMouseSize), 0.6, Color3.fromRGB(10, 10, 10), 2;
	Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\24\231\124\228\84\193\133\63", "\224\77\174\63\139\38\175"), vm).CornerRadius = UDim.new(1, 0);
	Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\177\104\107\58\150\78\83\43", "\78\228\33\56"), vm).Color, Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\251\87\129\23\151\193\117\183", "\229\174\30\210\99"), vm).Thickness = Color3.fromRGB(60, 160, 255), 2;
	GUIrefs.vm = vm;
	local vmCircle = Instance.new(LUAOBFUSACTOR_DECRYPT_STR_0("\50\224\135\86\232\17\56\25\232\138", "\89\123\141\230\49\141\93"), screenGui);
	vmCircle.BackgroundTransparency, vmCircle.Image, vmCircle.ImageColor3, vmCircle.ImageTransparency, vmCircle.ZIndex = 1, LUAOBFUSACTOR_DECRYPT_STR_0("\225\115\238\13\3\89\246\101\255\8\74\5\188\32\165\89\66\25\160\37\167\85\73\26", "\42\147\17\150\108\112"), circleColor, 0.5, 1;
	GUIrefs.vmCircle = vmCircle;
	screenGui.Enabled = UIS.TouchEnabled;
end
createMobileGUI();
updateButtonStates();
notify(LUAOBFUSACTOR_DECRYPT_STR_0("\60\165\63\118\247\252\79\149\57\126\243\253\28", "\136\111\198\77\31\135"), LUAOBFUSACTOR_DECRYPT_STR_0("\48\12\166\82\164\164\3\166\66\60\180\83", "\201\98\105\199\54\221\132\119"));
