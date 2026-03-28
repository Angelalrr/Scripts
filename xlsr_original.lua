-- ============================================================
--  XLSR  ·  AUTO STEAL + SMART FLOOR + CAM AIM + TARGET LOCK
-- ============================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")
local TweenService      = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui           = game:GetService("CoreGui")
local StarterGui        = game:GetService("StarterGui")
local LocalPlayer       = Players.LocalPlayer

-- ============================================================
--  HELPERS & CLEANUP
-- ============================================================
local R = Color3.fromRGB

local function RC(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 12)
    c.Parent = p
end

local function TW(o, props, t)
    TweenService:Create(o, TweenInfo.new(t or .2, Enum.EasingStyle.Quart), props):Play()
end

local function MakeGui(name, order)
    local sg = Instance.new("ScreenGui")
    sg.Name           = name
    sg.ResetOnSpawn   = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.DisplayOrder   = order or 100
    if not pcall(function() sg.Parent = CoreGui end) then
        sg.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    return sg
end

for _, n in ipairs({"XLSR_Floor_GUI", "XLSR_AS_GUI", "XLSR_Rush_GUI", "TitanMobile", "TitanESP", "InstantGrabGui"}) do
    pcall(function()
        local g = CoreGui:FindFirstChild(n); if g then g:Destroy() end
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then local g2 = pg:FindFirstChild(n); if g2 then g2:Destroy() end end
    end)
end

local COLORS = {
    BG         = R(15, 15, 18),
    BG_DARK    = R(10, 10, 12),
    ELEMENT    = R(25, 25, 30),
    BORDER     = R(40, 40, 45),
    ACCENT     = R(255, 65, 65),
    SUCCESS    = R(50, 200, 100),
    WARNING    = R(255, 180, 50),
    TEXT       = R(240, 240, 240),
    TEXT_DIM   = R(160, 160, 170),
}

local function Notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {Title = title, Text = text, Icon = "rbxassetid://10860368504", Duration = 3})
    end)
end

-- ============================================================
--  DETECCIÓN DE ROBO & SPEED COIL
-- ============================================================
local function isMeStealing()
    local character = LocalPlayer.Character
    if not character then return false end
    local taggedObjects = CollectionService:GetTagged("ClientRenderBrainrot")
    for _, obj in pairs(taggedObjects) do
        if obj:IsDescendantOf(character) then return true end
        if obj:IsA("BasePart") then
            for _, child in pairs(character:GetDescendants()) do
                if child:IsA("Weld") or child:IsA("WeldConstraint") then
                    if child.Part0 == obj or child.Part1 == obj then return true end
                end
            end
        end
        local isStolenAttr = obj:GetAttribute("__render_stolen")
        local root = character:FindFirstChild("HumanoidRootPart")
        if isStolenAttr == true and root then
            if obj:IsA("BasePart") and (obj.Position - root.Position).Magnitude < 6 then return true end
        end
    end
    return false
end

local function handleSpeedCoil(equip)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local currentTool = char:FindFirstChildOfClass("Tool")
    
    if equip and not isMeStealing() then
        local coil = LocalPlayer.Backpack:FindFirstChild("Speed Coil") or char:FindFirstChild("Speed Coil")
        if coil and coil.Parent == LocalPlayer.Backpack then
            hum:EquipTool(coil)
        end
    else
        if currentTool and currentTool.Name == "Speed Coil" then
            hum:UnequipTools()
        end
    end
end

-- ============================================================
--  SMART FLOOR (ANTI-KNOCKBACK & PERSISTENCIA)
-- ============================================================
local floorPart = nil
local floorState = false
local targetFloorHeight = nil

local function SetStealFloor(state, targetY)
    if floorState == state then 
        if state and targetY then targetFloorHeight = targetY end
        return 
    end
    
    floorState = state
    targetFloorHeight = targetY
    
    if state then
        if not floorPart then
            floorPart = Instance.new("Part")
            floorPart.Size = Vector3.new(16, 1, 16)
            floorPart.Anchored = true
            floorPart.CanCollide = true
            floorPart.Color = R(200, 35, 35)
            floorPart.Material = Enum.Material.Neon
            floorPart.Transparency = 0.3
            floorPart.Parent = workspace
            
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then 
                floorPart.CFrame = CFrame.new(hrp.Position.X, hrp.Position.Y - 3.5, hrp.Position.Z) 
            end
        end
    else
        if floorPart then 
            floorPart:Destroy()
            floorPart = nil 
        end
    end
end

RunService.Heartbeat:Connect(function(dt)
    if floorState and floorPart then
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp and targetFloorHeight then
            local currentY = floorPart.Position.Y
            local desiredY = targetFloorHeight - 3.5
            
            if hrp.Position.Y < currentY - 5 then
                currentY = hrp.Position.Y - 3.5
            end
            
            if currentY < desiredY then
                currentY = math.min(currentY + 1.8, desiredY)
            end
            
            floorPart.CFrame = CFrame.new(hrp.Position.X, currentY, hrp.Position.Z)
        end
    end
end)

-- ============================================================
--  ESCANEO DE DATOS
-- ============================================================
local autoStealEnabled    = true
local selectedTargetIndex = 1
local allAnimals          = {}
local activeTarget        = nil 

local progressFill, progressText, espGui, espText
local tracerBeam       
local targetAttachment 

local function getModule(name)
    local found = ReplicatedStorage:FindFirstChild(name, true)
    if found and found:IsA("ModuleScript") then return require(found) end
end

local AnimalsData  = getModule("Animals")
local Synchronizer = getModule("Synchronizer")

local function getChannelsTable()
    if not Synchronizer then return nil end
    local ok, ch = pcall(getupvalue, Synchronizer.GetAllChannels, 1)
    if ok and type(ch) == "table" then return ch end
    for i = 1, 5 do
        local ok2, val = pcall(getupvalue, Synchronizer.Get, i)
        if ok2 and type(val) == "table" then return val end
    end
end

local function parseToNumber(str)
    if type(str) == "number" then return str end
    if not str then return 0 end
    str = tostring(str):gsub("<[^>]+>",""):upper()
    local numStr = str:match("[%d%.]+"); if not numStr then return 0 end
    local num = tonumber(numStr) or 0
    if str:find("K") then num*=1e3 elseif str:find("M") then num*=1e6
    elseif str:find("B") then num*=1e9 elseif str:find("T") then num*=1e12
    elseif str:find("QA") then num*=1e15 elseif str:find("QI") then num*=1e18 end
    return num
end

local function isOnCarpet(part)
    local rayOrigin = part.Position
    local rayDirection = Vector3.new(0, -999, 0)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local filter = {}
    if workspace:FindFirstChild("Debris") then table.insert(filter, workspace.Debris) end
    if LocalPlayer.Character then table.insert(filter, LocalPlayer.Character) end
    params.FilterDescendantsInstances = filter
    local result = workspace:Raycast(rayOrigin, rayDirection, params)
    if result and result.Instance then
        local inst = result.Instance
        if inst.Name == "Carpet" or inst:GetFullName():find("Map%.Carpet") then return true end
        local mapFolder = workspace:FindFirstChild("Map")
        if mapFolder then
            local carpetFolder = mapFolder:FindFirstChild("Carpet")
            if carpetFolder and (inst == carpetFolder or inst:IsDescendantOf(carpetFolder)) then return true end
        end
    end
    return false
end

local function getPriceAndPosFromDebris(targetName, usedSet)
    local debris = workspace:FindFirstChild("Debris")
    if not debris then return nil, nil, false, nil end
    for _, child in ipairs(debris:GetChildren()) do
        local overhead = child:FindFirstChild("AnimalOverhead") or child:FindFirstChild("AnimalOverhead",true)
        if overhead then
            local part = nil
            if overhead.Parent:IsA("Attachment") then part = overhead.Parent.Parent
            elseif overhead.Parent:IsA("BasePart") then part = overhead.Parent
            elseif overhead.Parent:IsA("Model") then part = overhead.Parent.PrimaryPart or overhead.Parent:FindFirstChildWhichIsA("BasePart",true) end
            if part and part:IsA("BasePart") and not usedSet[part] then
                if isOnCarpet(part) then continue end
                local nameObj = overhead:FindFirstChild("DisplayName")
                local genObj  = overhead:FindFirstChild("Generation")
                if nameObj and genObj and nameObj:IsA("TextLabel") and genObj:IsA("TextLabel") then
                    local cleanName  = nameObj.Text:gsub("<[^>]+>","")
                    local rawGenText = genObj.Text:gsub("<[^>]+>","")
                    if cleanName == targetName or cleanName:find(targetName, 1, true) then
                        local lowerText = rawGenText:lower()
                        local isFusion = not lowerText:find("/s") and (lowerText:match("%d+s") or lowerText:match("%d+m") or lowerText:match("%d+h")) and true or false
                        usedSet[part] = true
                        return rawGenText, parseToNumber(rawGenText), isFusion, part.Position
                    end
                end
            end
        end
    end
    return nil, nil, false, nil
end

function scanAllPlots()
    local channels = getChannelsTable(); if not channels then return end
    local newAnimals = {}
    local usedDebrisParts = {} 
    for channelId, channelObj in pairs(channels) do
        local ok, data = pcall(function() return channelObj:GetTable() end)
        if ok and data and type(data)=="table" and data.AnimalList then
            local isMe = false
            local owner = data.Owner
            if owner then
                if typeof(owner)=="Instance" and owner==LocalPlayer then isMe=true
                elseif type(owner)=="table" and owner.UserId==LocalPlayer.UserId then isMe=true end
            end
            if not isMe then
                for slot, animal in pairs(data.AnimalList) do
                    local info = AnimalsData and AnimalsData[animal.Index]
                    if info or animal.Index then
                        local displayName = (info and info.DisplayName) or animal.Index
                        local mpsText, mpsValue, isFusion, pos = getPriceAndPosFromDebris(displayName, usedDebrisParts)
                        if isFusion then continue end
                        if not pos then continue end
                        if not mpsText then
                            local baseGen = (info and (info.Generation or info.BaseGeneration)) or 1
                            mpsValue = parseToNumber(baseGen)
                            mpsText  = "$"..mpsValue.."/s (Base)"
                        end
                        local coordStr = string.format("📍 %.1f, %.1f, %.1f", pos.X, pos.Y, pos.Z)
                        table.insert(newAnimals, {name=displayName, mpsValue=mpsValue, mpsText=mpsText, plotName=channelId, slot=tostring(slot), mutation=animal.Mutation or "None", pos=pos, coordsStr=coordStr, uid=channelId.."_"..tostring(slot)})
                    end
                end
            end
        end
    end
    table.sort(newAnimals, function(a,b) return a.mpsValue > b.mpsValue end)
    allAnimals = newAnimals
end

local function isTargetStillValid(uid)
    for _, animal in ipairs(allAnimals) do
        if animal.uid == uid then return true end
    end
    return false
end

-- ============================================================
-- LÓGICA DE CÁMARA & ROBO (CORREGIDA)
-- ============================================================
local InternalStealCache = {}
local PromptMemoryCache  = {}
local CameraAimState     = { lastUID = nil, aimed = false }

local function resetCameraAim()
    CameraAimState.lastUID = nil
    CameraAimState.aimed = false
end

local function findPrompt(plotName, slotName)
    local uid = plotName .. "_" .. slotName
    local cached = PromptMemoryCache[uid]
    if cached and cached.Parent and cached:IsDescendantOf(workspace) then 
        return cached 
    end

    local plot = workspace:FindFirstChild("Plots") and workspace.Plots:FindFirstChild(plotName)
    local podium = plot and plot:FindFirstChild("AnimalPodiums") and plot.AnimalPodiums:FindFirstChild(slotName)
    
    local prompt = nil
    if podium and podium:FindFirstChild("Base") and podium.Base:FindFirstChild("Spawn") and podium.Base.Spawn:FindFirstChild("PromptAttachment") then
        prompt = podium.Base.Spawn.PromptAttachment:FindFirstChildOfClass("ProximityPrompt")
    end
    
    if not prompt and podium then
        prompt = podium:FindFirstChildWhichIsA("ProximityPrompt", true)
    end

    if prompt then PromptMemoryCache[uid] = prompt end
    return prompt
end

local function buildStealCallbacks(prompt)
    if InternalStealCache[prompt] then return InternalStealCache[prompt] end
    local data = { holdCallbacks = {}, triggerCallbacks = {} }
    
    local ok1, conns1 = pcall(getconnections, prompt.PromptButtonHoldBegan)
    if ok1 then for _, c in ipairs(conns1) do table.insert(data.holdCallbacks, c.Function) end end
    
    local ok2, conns2 = pcall(getconnections, prompt.Triggered)
    if ok2 then for _, c in ipairs(conns2) do table.insert(data.triggerCallbacks, c.Function) end end
    
    InternalStealCache[prompt] = data
    return data
end

local function forceGrabSpam(target)
    local prompt = findPrompt(target.plotName, target.slot)
    if not prompt or not prompt:IsDescendantOf(workspace) then return false end
    
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    local basePart = prompt.Parent
    if basePart:IsA("Attachment") then basePart = basePart.Parent end
    if not basePart or not basePart:IsA("BasePart") then return false end
    
    local promptPos = basePart.Position
    local dist = (hrp.Position - promptPos).Magnitude
    
    if dist <= 25 then
        if CameraAimState.lastUID ~= target.uid then
            CameraAimState.lastUID = target.uid
            CameraAimState.aimed = false
        end

        local cam = workspace.CurrentCamera
        if cam and not CameraAimState.aimed then
            cam.CFrame = CFrame.lookAt(cam.CFrame.Position, promptPos)
            CameraAimState.aimed = true
        end
        
        local data = buildStealCallbacks(prompt)
        
        pcall(function()
            prompt.HoldDuration = 0
            prompt.RequiresLineOfSight = false
            prompt.MaxActivationDistance = 9e99
            prompt.Enabled = true
        end)
        
        if fireproximityprompt then
            pcall(function() fireproximityprompt(prompt, 0); fireproximityprompt(prompt, 1); fireproximityprompt(prompt) end)
        end
        
        pcall(function() prompt:InputHoldBegin() task.wait() prompt:InputHoldEnd() end)
        
        if data then
            for _, fn in ipairs(data.holdCallbacks) do task.spawn(fn) end
            for _, fn in ipairs(data.triggerCallbacks) do task.spawn(fn) end
        end
    end
    return true
end

local function cleanAnimalName(name)
    if not name then return "" end
    return tostring(name):gsub("%s*%[.-%]%s*$",""):gsub("%s*%(.-%)%s*$",""):match("^(.-)%s*$") or tostring(name)
end

local _imgCache = {}
local _fetching = {}
local WIKI_API  = "https://stealabrainrot.fandom.com/api.php"

local function fetchWikiImage(cleanName)
    if not cleanName or cleanName == "" then return end
    if _imgCache[cleanName] or _fetching[cleanName] then return end
    _fetching[cleanName] = true
    task.spawn(function()
        local ok, res = pcall(function() return request({Url=WIKI_API.."?action=query&titles="..HttpService:UrlEncode(cleanName).."&prop=pageimages&pithumbsize=256&format=json&origin=*", Method="GET"}) end)
        if not ok or not res or res.StatusCode~=200 then _fetching[cleanName] = false; return end
        local data = pcall(function() return HttpService:JSONDecode(res.Body) end) and HttpService:JSONDecode(res.Body)
        if not data then _fetching[cleanName] = false; return end
        local thumbUrl
        if data.query and data.query.pages then for _,page in pairs(data.query.pages) do if page.thumbnail then thumbUrl=page.thumbnail.source; break end end end
        if not thumbUrl then _fetching[cleanName] = false; return end
        local ok2, imgData = pcall(function() return request({Url=thumbUrl,Method="GET"}).Body end)
        if not ok2 or not imgData then _fetching[cleanName] = false; return end
        local fname = "xlsr_img_"..HttpService:GenerateGUID(false):sub(1,8)..".png"
        pcall(function() writefile(fname, imgData); _imgCache[cleanName] = getcustomasset(fname) end)
    end)
end

-- ============================================================
--  INTERFACES PREVIAS & ESTADOS
-- ============================================================
local asfRunning   = false
local asfThread    = nil
local asfLockPos   = nil 
local asfBtnOuter, asfBtnLbl, asfStatusLbl
local RushBtn

local function resetASFBtn()
    if asfBtnOuter then TW(asfBtnOuter, {BackgroundColor3 = COLORS.ELEMENT}, .2) end
    if asfBtnLbl then asfBtnLbl.Text = "🏠 INICIAR AUTO STEAL FLOOR" end
    if RushBtn then 
        RushBtn.Text = "⚡ INICIAR ASF"
        RushBtn.BackgroundColor3 = R(140, 30, 30)
    end
end

local function setASFStatus(txt, col)
    if asfStatusLbl and asfStatusLbl.Parent then
        asfStatusLbl.Text = txt or ""
        asfStatusLbl.TextColor3 = col or COLORS.TEXT_DIM
    end
end

local function stopMainASF()
    asfRunning = false
    asfLockPos = nil 
    activeTarget = nil 
    resetCameraAim()
    if asfThread then pcall(function() task.cancel(asfThread) end); asfThread=nil end
    SetStealFloor(false)
    LocalPlayer.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Zoom
    handleSpeedCoil(false)
    resetASFBtn()
    setASFStatus("⛔ Detenido", R(255,100,100))
end

-- ============================================================
--  FAILSAFE GLOBAL & AUTO STEAL LOGIC
-- ============================================================
RunService.Heartbeat:Connect(function()
    if isMeStealing() then
        if floorState then SetStealFloor(false) end
        handleSpeedCoil(false)
    end

    if asfRunning and asfLockPos then
        local char = LocalPlayer.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if hum and hrp then
            if isMeStealing() then
                asfLockPos = nil
                return
            end
            asfLockPos = Vector3.new(asfLockPos.X, hrp.Position.Y, asfLockPos.Z)
            hum:MoveTo(asfLockPos)
        end
    end
end)

local function asfWalkTo(lockedTarget, timeout)
    local char = LocalPlayer.Character; if not char then return false end
    local hrp  = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    handleSpeedCoil(true)
    
    local elapsed = 0
    while elapsed < (timeout or 20) and asfRunning do
        if isMeStealing() then asfLockPos = nil return false end
        
        -- Verificación global (No requiere que el prompt esté renderizado)
        if not isTargetStillValid(lockedTarget.uid) then
            asfLockPos = nil
            return false
        end
        
        local pos = lockedTarget.pos
        asfLockPos = Vector3.new(pos.X, hrp.Position.Y, pos.Z)
        local flatDist = Vector3.new(hrp.Position.X - pos.X, 0, hrp.Position.Z - pos.Z).Magnitude
        if flatDist < 3.5 then break end
        task.wait(0.05)
        elapsed += 0.05
    end
    return true
end

local function doOneCycle()
    if isMeStealing() then
        setASFStatus("⏸ Manos ocupadas...", COLORS.WARNING)
        handleSpeedCoil(false)
        return false 
    end

    setASFStatus("🔍 Escaneando mapa...", COLORS.WARNING)
    scanAllPlots()
    
    local target = allAnimals[selectedTargetIndex]
    if not target then setASFStatus("❌ Sin objetivos", R(255,80,80)) task.wait(0.5); return false end
    if not activeTarget or activeTarget.uid ~= target.uid then
        resetCameraAim()
    end
    activeTarget = target

    local brainrotPos = target.pos
    if not brainrotPos or brainrotPos.Magnitude == 0 then task.wait(0.5); activeTarget = nil return false end

    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then activeTarget = nil return false end

    local yDiff = brainrotPos.Y - hrp.Position.Y
    local needFloor = yDiff > 10 

    setASFStatus("🚶 Acercándose a "..target.name, R(100,200,255))
    local walkSuccess = asfWalkTo(target, 20)

    if not asfRunning then asfLockPos = nil; handleSpeedCoil(false); activeTarget = nil return false end
    if not walkSuccess then asfLockPos = nil; handleSpeedCoil(false); activeTarget = nil return false end

    if needFloor then
        setASFStatus("⬆ Subiendo plataforma...", COLORS.WARNING)
        handleSpeedCoil(false)
        SetStealFloor(true, brainrotPos.Y)
        
        -- Espera a que el jugador suba junto con la plataforma
        local ft = 0
        while ft < 8 and asfRunning do 
            if isMeStealing() then 
                SetStealFloor(false)
                asfLockPos = nil
                return false
            end
            
            if not isTargetStillValid(target.uid) then
                SetStealFloor(false)
                asfLockPos = nil
                return false
            end
            
            local currentHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if currentHrp and currentHrp.Position.Y >= brainrotPos.Y - 6 then
                break -- Llegamos arriba
            end
            
            task.wait(0.1); ft += 0.1 
        end
        if not asfRunning then SetStealFloor(false); asfLockPos=nil return false end
        task.wait(0.05)
    else
        if floorState then SetStealFloor(false) end
    end

    setASFStatus("⚡ Robando "..target.name, COLORS.ACCENT)
    
    while not isMeStealing() and asfRunning do
        if not isTargetStillValid(target.uid) then 
            break 
        end
        forceGrabSpam(target)
        task.wait(0.05)
    end
    
    if isMeStealing() then
         setASFStatus("✅ ¡Éxito!", COLORS.SUCCESS)
         local escapeTimeout = 0
         while isMeStealing() and asfRunning do 
             task.wait(0.1) 
             escapeTimeout += 0.1
             if escapeTimeout > 3 then break end
         end
    else
         setASFStatus("⏱ Desapareció...", COLORS.WARNING)
         if floorState then SetStealFloor(false) end
    end

    asfLockPos = nil 
    handleSpeedCoil(false)
    activeTarget = nil
    resetCameraAim()
    task.wait(0.1)
    return true
end

local function runAutoStealFloor()
    while asfRunning do
        doOneCycle()
        if not asfRunning then break end
        task.wait(0.05) 
    end
    stopMainASF()
end

-- ============================================================
--  GUI MODERNA
-- ============================================================
local ASGui = MakeGui("XLSR_AS_GUI", 101)
local RushGui = MakeGui("XLSR_Rush_GUI", 102)

-- Panel Principal
local ASPanel = Instance.new("Frame", ASGui)
ASPanel.Name = "ASPanel"
ASPanel.Size = UDim2.new(0, 280, 0, 480)
ASPanel.Position = UDim2.new(0.5, -140, 0.5, -240)
ASPanel.BackgroundColor3 = COLORS.BG
ASPanel.BorderSizePixel = 0
ASPanel.Active = true
ASPanel.Draggable = true
ASPanel.ClipsDescendants = true
RC(ASPanel, 12)

local borderStroke = Instance.new("UIStroke", ASPanel)
borderStroke.Thickness = 1.5
borderStroke.Color = COLORS.ACCENT
task.spawn(function() while ASPanel and ASPanel.Parent do TW(borderStroke, {Color=COLORS.ACCENT}, 1.5) task.wait(1.5) TW(borderStroke, {Color=R(120, 40, 40)}, 1.5) task.wait(1.5) end end)

local Header = Instance.new("Frame", ASPanel)
Header.Size = UDim2.new(1,0,0, 45)
Header.BackgroundColor3 = COLORS.BG_DARK
Header.BorderSizePixel = 0
RC(Header, 12)

local TitleLbl = Instance.new("TextLabel", Header)
TitleLbl.Size = UDim2.new(1, -80, 1, 0)
TitleLbl.Position = UDim2.new(0, 15, 0, 0)
TitleLbl.BackgroundTransparency = 1
TitleLbl.Text = "XLSR // HUB"
TitleLbl.TextColor3 = COLORS.TEXT
TitleLbl.Font = Enum.Font.GothamBlack
TitleLbl.TextSize = 16
TitleLbl.TextXAlignment = Enum.TextXAlignment.Left

local CloseBtn = Instance.new("TextButton", Header)
CloseBtn.Size = UDim2.new(0, 30, 0, 25)
CloseBtn.Position = UDim2.new(1, -35, 0.5, -12)
CloseBtn.BackgroundColor3 = R(200, 50, 50)
CloseBtn.Text = "X"
CloseBtn.TextColor3 = COLORS.TEXT
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 14
RC(CloseBtn, 6)

local MinBtn = Instance.new("TextButton", Header)
MinBtn.Size = UDim2.new(0, 30, 0, 25)
MinBtn.Position = UDim2.new(1, -70, 0.5, -12)
MinBtn.BackgroundColor3 = COLORS.ELEMENT
MinBtn.Text = "-"
MinBtn.TextColor3 = COLORS.TEXT
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 18
RC(MinBtn, 6)

local isMinimized = false
local fullSize = UDim2.new(0, 280, 0, 480)
local minSize = UDim2.new(0, 280, 0, 45)

MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then TW(ASPanel, {Size = minSize}, 0.3) MinBtn.Text = "+"
    else TW(ASPanel, {Size = fullSize}, 0.3) MinBtn.Text = "-" end
end)

local TargetHeader = Instance.new("TextLabel", ASPanel)
TargetHeader.Size = UDim2.new(1, -20, 0, 20)
TargetHeader.Position = UDim2.new(0, 15, 0, 50)
TargetHeader.BackgroundTransparency = 1
TargetHeader.Text = "TOP 10 TARGETS"
TargetHeader.TextColor3 = COLORS.TEXT_DIM
TargetHeader.Font = Enum.Font.GothamBold
TargetHeader.TextSize = 10
TargetHeader.TextXAlignment = Enum.TextXAlignment.Left

local ScrollList = Instance.new("ScrollingFrame", ASPanel)
ScrollList.Size = UDim2.new(1, -20, 0, 220)
ScrollList.Position = UDim2.new(0, 10, 0, 75)
ScrollList.BackgroundTransparency = 1
ScrollList.BorderSizePixel = 0
ScrollList.ScrollBarThickness = 4
ScrollList.CanvasSize = UDim2.new(0, 0, 0, 10 * 60)

local slotList = {}
local function updateHighlight() 
    for j = 1, 10 do 
        if selectedTargetIndex == j then 
            slotList[j].stroke.Color = COLORS.ACCENT 
            slotList[j].stroke.Thickness = 1.5 
            TW(slotList[j].btn, {BackgroundColor3 = R(35, 35, 40)}, 0.1) 
        else 
            slotList[j].stroke.Color = COLORS.BORDER 
            slotList[j].stroke.Thickness = 1 
            TW(slotList[j].btn, {BackgroundColor3 = COLORS.ELEMENT}, 0.1) 
        end 
    end 
end

for i = 1, 10 do
    local b = Instance.new("TextButton", ScrollList)
    b.Size = UDim2.new(1, -8, 0, 55)
    b.Position = UDim2.new(0, 0, 0, (i-1)*60)
    b.BackgroundColor3 = COLORS.ELEMENT
    b.Text = ""
    b.AutoButtonColor = false
    RC(b, 8)
    local bStroke = Instance.new("UIStroke", b) bStroke.Color = COLORS.BORDER bStroke.Thickness = 1
    
    local numLbl = Instance.new("TextLabel", b) numLbl.Size = UDim2.new(0,20,0,20) numLbl.Position = UDim2.new(0,5,0,5) numLbl.BackgroundTransparency = 1 numLbl.Text = "#"..i numLbl.TextColor3 = COLORS.TEXT_DIM numLbl.Font = Enum.Font.GothamBold numLbl.TextSize = 10
    
    local imgBorder = Instance.new("Frame", b) imgBorder.Size = UDim2.new(0,42,0,42) imgBorder.Position = UDim2.new(0,25,0.5,-21) imgBorder.BackgroundColor3 = COLORS.BG_DARK imgBorder.BorderSizePixel = 0 RC(imgBorder, 8)
    local imgLabel = Instance.new("ImageLabel", imgBorder) imgLabel.Size = UDim2.new(1,-4,1,-4) imgLabel.Position = UDim2.new(0,2,0,2) imgLabel.BackgroundColor3 = COLORS.ELEMENT imgLabel.BorderSizePixel = 0 imgLabel.ScaleType = Enum.ScaleType.Crop imgLabel.Image = "" RC(imgLabel, 6)
    local nameLbl = Instance.new("TextLabel", b) nameLbl.Size = UDim2.new(1,-80,0,18) nameLbl.Position = UDim2.new(0,75,0,6) nameLbl.BackgroundTransparency = 1 nameLbl.Text = "Cargando..." nameLbl.TextColor3 = COLORS.TEXT nameLbl.Font = Enum.Font.GothamBold nameLbl.TextSize = 12 nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    local mpsLbl = Instance.new("TextLabel", b) mpsLbl.Size = UDim2.new(1,-80,0,14) mpsLbl.Position = UDim2.new(0,75,0,22) mpsLbl.BackgroundTransparency = 1 mpsLbl.Text = "$0" mpsLbl.TextColor3 = COLORS.SUCCESS mpsLbl.Font = Enum.Font.Gotham mpsLbl.TextSize = 11 mpsLbl.TextXAlignment = Enum.TextXAlignment.Left
    local coordsLbl = Instance.new("TextLabel", b) coordsLbl.Size = UDim2.new(1,-80,0,12) coordsLbl.Position = UDim2.new(0,75,0,36) coordsLbl.BackgroundTransparency = 1 coordsLbl.Text = "📍 X, Y, Z" coordsLbl.TextColor3 = COLORS.TEXT_DIM coordsLbl.Font = Enum.Font.Gotham coordsLbl.TextSize = 9 coordsLbl.TextXAlignment = Enum.TextXAlignment.Left
    b.MouseButton1Click:Connect(function() selectedTargetIndex = i updateHighlight() end)
    slotList[i] = {btn=b, stroke=bStroke, img=imgLabel, nameLbl=nameLbl, mpsLbl=mpsLbl, coordsLbl=coordsLbl}
end

local asToggle = Instance.new("TextButton", ASPanel)
asToggle.Size = UDim2.new(1,-20,0,28)
asToggle.Position = UDim2.new(0,10,0,310)
asToggle.BackgroundColor3 = COLORS.SUCCESS
asToggle.Text = "AUTO STEAL: ON"
asToggle.Font = Enum.Font.GothamBold
asToggle.TextSize = 11
asToggle.TextColor3 = COLORS.TEXT
RC(asToggle, 6)
asToggle.MouseButton1Click:Connect(function()
    autoStealEnabled = not autoStealEnabled
    asToggle.Text = "AUTO STEAL: "..(autoStealEnabled and "ON" or "OFF")
    asToggle.BackgroundColor3 = autoStealEnabled and COLORS.SUCCESS or R(180,40,40)
    if not autoStealEnabled then if espGui then espGui.Enabled = false end if tracerBeam then tracerBeam.Enabled = false end end
end)

asfBtnOuter = Instance.new("Frame", ASPanel)
asfBtnOuter.Size = UDim2.new(1,-20,0,32)
asfBtnOuter.Position = UDim2.new(0,10,0,348)
asfBtnOuter.BackgroundColor3 = COLORS.ELEMENT
asfBtnOuter.BorderSizePixel = 0
RC(asfBtnOuter, 6)

local asfBtnClick = Instance.new("TextButton", asfBtnOuter)
asfBtnClick.Size = UDim2.new(1,0,1,0)
asfBtnClick.BackgroundTransparency = 1
asfBtnClick.Text = ""

asfBtnLbl = Instance.new("TextLabel", asfBtnClick)
asfBtnLbl.Size = UDim2.new(1,0,1,0)
asfBtnLbl.BackgroundTransparency = 1
asfBtnLbl.Font = Enum.Font.GothamBold
asfBtnLbl.TextSize = 11
asfBtnLbl.TextXAlignment = Enum.TextXAlignment.Center
asfBtnLbl.TextColor3 = COLORS.TEXT
asfBtnLbl.Text = "🏠 AUTO STEAL FLOOR"

local function activateMainASF()
    if asfRunning then return end
    
    asfRunning = true
    LocalPlayer.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
    
    TW(asfBtnOuter, {BackgroundColor3 = COLORS.ACCENT}, .1)
    asfBtnLbl.Text = "🏠 ASF ACTIVO"
    
    RushBtn.Text = "⛔ CANCELAR ASF"
    RushBtn.BackgroundColor3 = R(200, 40, 40)
    
    asfThread = task.spawn(runAutoStealFloor)
end

asfBtnClick.MouseEnter:Connect(function() TW(asfBtnOuter, {BackgroundColor3 = R(45, 45, 50)}, .1) end)
asfBtnClick.MouseLeave:Connect(function() TW(asfBtnOuter, {BackgroundColor3 = COLORS.ELEMENT}, .1) end)
asfBtnClick.MouseButton1Click:Connect(function()
    if asfRunning then stopMainASF() else activateMainASF() end
end)

asfStatusLbl = Instance.new("TextLabel", ASPanel)
asfStatusLbl.Size = UDim2.new(1,-20,0,16)
asfStatusLbl.Position = UDim2.new(0,10,0,385)
asfStatusLbl.BackgroundTransparency = 1
asfStatusLbl.Font = Enum.Font.Gotham
asfStatusLbl.TextSize = 10
asfStatusLbl.TextColor3 = COLORS.TEXT_DIM
asfStatusLbl.TextXAlignment = Enum.TextXAlignment.Center
asfStatusLbl.Text = "Listo."

local stopOuter = Instance.new("TextButton", ASPanel)
stopOuter.Size = UDim2.new(1,-20,0,28)
stopOuter.Position = UDim2.new(0,10,0,405)
stopOuter.BackgroundColor3 = R(40,6,6)
stopOuter.BorderSizePixel = 0
stopOuter.Text = ""
stopOuter.AutoButtonColor = false
RC(stopOuter, 6)

local stopLbl = Instance.new("TextLabel", stopOuter)
stopLbl.Size = UDim2.new(1,0,1,0)
stopLbl.BackgroundTransparency = 1
stopLbl.Font = Enum.Font.GothamBold
stopLbl.TextSize = 11
stopLbl.TextXAlignment = Enum.TextXAlignment.Center
stopLbl.TextColor3 = R(255,80,80)
stopLbl.Text = "⛔ STOP ALL"

stopOuter.MouseButton1Click:Connect(stopMainASF)

-- ============================================================
--  BOTÓN FLOTANTE (TOGGLE)
-- ============================================================
RushBtn = Instance.new("TextButton", RushGui)
RushBtn.Name = "RushBtn"
RushBtn.Size = UDim2.new(0, 150, 0, 35)
RushBtn.Position = UDim2.new(0, 20, 0.5, 60)
RushBtn.BackgroundColor3 = R(140, 30, 30)
RushBtn.Text = "⚡ INICIAR ASF"
RushBtn.Font = Enum.Font.GothamBlack
RushBtn.TextSize = 12
RushBtn.TextColor3 = R(255, 255, 255)
RushBtn.Active = true
RushBtn.Draggable = true
RC(RushBtn, 8)
local rushStroke = Instance.new("UIStroke", RushBtn) rushStroke.Color = R(80, 20, 20) rushStroke.Thickness = 2

RushBtn.MouseButton1Click:Connect(function()
    if asfRunning then 
        stopMainASF() 
    else 
        activateMainASF() 
    end
end)

CloseBtn.MouseButton1Click:Connect(function()
    stopMainASF()
    ASGui:Destroy()
    RushGui:Destroy()
end)

espGui = Instance.new("BillboardGui", ASGui) espGui.Name = "TitanESP" espGui.Size = UDim2.new(0,150,0,50) espGui.StudsOffset = Vector3.new(0,4.5,0) espGui.AlwaysOnTop = true espGui.Enabled = false
espText = Instance.new("TextLabel", espGui) espText.Size = UDim2.new(1,0,1,0) espText.BackgroundTransparency = 1 espText.TextColor3 = R(255,255,0) espText.TextStrokeColor3 = R(0,0,0) espText.TextStrokeTransparency = 0 espText.Font = Enum.Font.GothamBold espText.TextScaled = true

-- Bucle de Escaneo ULTRA Rápido (0.05s)
task.spawn(function()
    local lastNames = {}
    local lastTopUID = ""
    
    while task.wait(0.05) do
        if not ASPanel or not ASPanel.Parent then break end
        pcall(function()
            scanAllPlots()
            
            if allAnimals[1] and allAnimals[1].uid ~= lastTopUID then
                if lastTopUID ~= "" then 
                    Notify("¡Nuevo Top Brainrot!", allAnimals[1].name .. " [" .. allAnimals[1].mpsText .. "]")
                end
                lastTopUID = allAnimals[1].uid
            end
            
            for i = 1, 10 do
                local pet = allAnimals[i]
                if pet then
                    local safeName = tostring(pet.name or "Desconocido")
                    local mutText = (pet.mutation and pet.mutation~="None") and (" ["..tostring(pet.mutation).."]") or ""
                    slotList[i].nameLbl.Text = safeName .. mutText
                    slotList[i].mpsLbl.Text = tostring(pet.mpsText or "")
                    slotList[i].coordsLbl.Text = tostring(pet.coordsStr or "")
                    local cName = cleanAnimalName(safeName)
                    if lastNames[i] ~= cName then lastNames[i] = cName slotList[i].img.Image = "" fetchWikiImage(cName) end
                    if _imgCache[cName] then slotList[i].img.Image = _imgCache[cName] end
                else
                    slotList[i].nameLbl.Text = "Ranura #"..i.." Vacía" slotList[i].mpsLbl.Text = "" slotList[i].coordsLbl.Text = "" slotList[i].img.Image = "" lastNames[i] = nil
                end
            end
            updateHighlight()
        end)
    end
end)

-- Loop ESP y Robo Secundario Sincronizado
task.spawn(function()
    while true do
        task.wait(0.05)
        pcall(function()
            if not tracerBeam or not tracerBeam.Parent then tracerBeam = Instance.new("Beam") tracerBeam.Color = ColorSequence.new(R(255,0,100), R(255,100,200)) tracerBeam.Width0 = 0.15 tracerBeam.Width1 = 0.15 tracerBeam.FaceCamera = true tracerBeam.LightEmission = 1 tracerBeam.Transparency = NumberSequence.new(0.2) tracerBeam.Parent = workspace.Terrain end
            if not targetAttachment or not targetAttachment.Parent then targetAttachment = Instance.new("Attachment") targetAttachment.Parent = workspace.Terrain end
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then local att = hrp:FindFirstChild("TitanTracerOrigin") if not att then att = Instance.new("Attachment") att.Name = "TitanTracerOrigin" att.Parent = hrp end tracerBeam.Attachment0 = att else tracerBeam.Attachment0 = nil end
            
            if autoStealEnabled and hrp then
                local target = (asfRunning and activeTarget) or allAnimals[selectedTargetIndex]
                
                if target then
                    local prompt = findPrompt(target.plotName, target.slot)
                    if prompt and prompt:IsDescendantOf(workspace) then
                        local basePart = prompt.Parent
                        if basePart:IsA("Attachment") then basePart = basePart.Parent end
                        
                        if basePart and basePart:IsA("BasePart") then
                            if espGui then espGui.Adornee = basePart espText.Text = "🎯 "..tostring(target.name).."\n"..tostring(target.mpsText) espGui.Enabled = true end
                            targetAttachment.Parent = basePart targetAttachment.Position = Vector3.new(0,0,0) tracerBeam.Attachment1 = targetAttachment tracerBeam.Enabled = true
                            
                            local distance = (hrp.Position - basePart.Position).Magnitude
                            if distance <= 25 and not isMeStealing() then 
                                forceGrabSpam(target)
                            end
                        else
                            if espGui then espGui.Enabled = false end tracerBeam.Enabled = false
                        end
                    else
                        if espGui then espGui.Enabled = false end tracerBeam.Enabled = false
                    end
                else 
                    if espGui then espGui.Enabled = false end tracerBeam.Enabled = false 
                end
            else 
                if espGui then espGui.Enabled = false end if tracerBeam then tracerBeam.Enabled = false end
            end
        end)
    end
end)
