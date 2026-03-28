-- ============================================================
--  XLSR · AUTO STEAL + SMART FLOOR + CAM AIM + TARGET LOCK
--  Versión mejorada: estabilidad, rendimiento y mantenibilidad
-- ============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local R = Color3.fromRGB

-- ============================================================
--  CONFIG
-- ============================================================
local CFG = {
    SCAN_INTERVAL = 0.12, -- antes 0.05; menor carga de CPU
    ESP_INTERVAL = 0.07,
    WALK_STEP = 0.06,
    WALK_TIMEOUT = 20,
    FLOOR_OFFSET_Y = 3.5,
    FLOOR_SIZE = Vector3.new(16, 1, 16),
    GRAB_DISTANCE = 25,
    PROMPT_DISTANCE = 9e99,
}

local COLORS = {
    BG = R(15, 15, 18),
    BG_DARK = R(10, 10, 12),
    ELEMENT = R(25, 25, 30),
    BORDER = R(40, 40, 45),
    ACCENT = R(255, 65, 65),
    SUCCESS = R(50, 200, 100),
    WARNING = R(255, 180, 50),
    TEXT = R(240, 240, 240),
    TEXT_DIM = R(160, 160, 170),
}

-- ============================================================
--  HELPERS
-- ============================================================
local function RC(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 12)
    c.Parent = parent
    return c
end

local function TW(object, props, duration)
    local tw = TweenService:Create(object, TweenInfo.new(duration or 0.2, Enum.EasingStyle.Quart), props)
    tw:Play()
    return tw
end

local function safeJSONDecode(body)
    local ok, data = pcall(HttpService.JSONDecode, HttpService, body)
    if ok then return data end
    return nil
end

local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Icon = "rbxassetid://10860368504",
            Duration = 3,
        })
    end)
end

local function makeGui(name, order)
    local sg = Instance.new("ScreenGui")
    sg.Name = name
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.DisplayOrder = order or 100

    if not pcall(function() sg.Parent = CoreGui end) then
        sg.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    return sg
end

local function destroyExistingUIs(names)
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    for _, name in ipairs(names) do
        pcall(function()
            local a = CoreGui:FindFirstChild(name)
            if a then a:Destroy() end
            local b = playerGui and playerGui:FindFirstChild(name)
            if b then b:Destroy() end
        end)
    end
end

local function getHumanoidAndRoot()
    local char = LocalPlayer.Character
    if not char then return nil, nil end
    return char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
end

-- ============================================================
--  CLEANUP
-- ============================================================
destroyExistingUIs({
    "XLSR_Floor_GUI", "XLSR_AS_GUI", "XLSR_Rush_GUI", "TitanMobile", "TitanESP", "InstantGrabGui",
})

-- ============================================================
--  GAME DATA
-- ============================================================
local function getModule(name)
    local found = ReplicatedStorage:FindFirstChild(name, true)
    if found and found:IsA("ModuleScript") then
        local ok, mod = pcall(require, found)
        if ok then return mod end
    end
    return nil
end

local AnimalsData = getModule("Animals")
local Synchronizer = getModule("Synchronizer")

local function getChannelsTable()
    if not Synchronizer then return nil end

    local okA, channels = pcall(getupvalue, Synchronizer.GetAllChannels, 1)
    if okA and type(channels) == "table" then return channels end

    for i = 1, 8 do
        local okB, value = pcall(getupvalue, Synchronizer.Get, i)
        if okB and type(value) == "table" then return value end
    end
    return nil
end

-- ============================================================
--  PARSING / SCAN
-- ============================================================
local function parseToNumber(raw)
    if type(raw) == "number" then return raw end
    if raw == nil then return 0 end

    local text = tostring(raw):gsub("<[^>]+>", ""):upper()
    local n = tonumber(text:match("[%d%.]+") or "0") or 0

    if text:find("QA", 1, true) then return n * 1e15 end
    if text:find("QI", 1, true) then return n * 1e18 end
    if text:find("T", 1, true) then return n * 1e12 end
    if text:find("B", 1, true) then return n * 1e9 end
    if text:find("M", 1, true) then return n * 1e6 end
    if text:find("K", 1, true) then return n * 1e3 end
    return n
end

local function isOnCarpet(part)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude

    local ignore = {}
    local debris = workspace:FindFirstChild("Debris")
    if debris then table.insert(ignore, debris) end
    if LocalPlayer.Character then table.insert(ignore, LocalPlayer.Character) end
    params.FilterDescendantsInstances = ignore

    local result = workspace:Raycast(part.Position, Vector3.new(0, -999, 0), params)
    if not result or not result.Instance then return false end

    local inst = result.Instance
    if inst.Name == "Carpet" or inst:GetFullName():find("Map%.Carpet") then
        return true
    end

    local map = workspace:FindFirstChild("Map")
    local carpet = map and map:FindFirstChild("Carpet")
    return carpet and (inst == carpet or inst:IsDescendantOf(carpet)) or false
end

local function findPartByOverhead(overhead)
    if overhead.Parent:IsA("Attachment") then
        return overhead.Parent.Parent
    elseif overhead.Parent:IsA("BasePart") then
        return overhead.Parent
    elseif overhead.Parent:IsA("Model") then
        return overhead.Parent.PrimaryPart or overhead.Parent:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function getPriceAndPosFromDebris(targetName, usedSet)
    local debris = workspace:FindFirstChild("Debris")
    if not debris then return nil, nil, false, nil end

    for _, child in ipairs(debris:GetChildren()) do
        local overhead = child:FindFirstChild("AnimalOverhead") or child:FindFirstChild("AnimalOverhead", true)
        if not overhead then continue end

        local part = findPartByOverhead(overhead)
        if not part or not part:IsA("BasePart") or usedSet[part] then continue end
        if isOnCarpet(part) then continue end

        local nameObj = overhead:FindFirstChild("DisplayName")
        local genObj = overhead:FindFirstChild("Generation")
        if not (nameObj and genObj and nameObj:IsA("TextLabel") and genObj:IsA("TextLabel")) then continue end

        local cleanName = nameObj.Text:gsub("<[^>]+>", "")
        if cleanName ~= targetName and not cleanName:find(targetName, 1, true) then continue end

        local rawGenText = genObj.Text:gsub("<[^>]+>", "")
        local low = rawGenText:lower()
        local isFusion = (not low:find("/s")) and (low:match("%d+s") or low:match("%d+m") or low:match("%d+h")) and true or false

        usedSet[part] = true
        return rawGenText, parseToNumber(rawGenText), isFusion, part.Position
    end

    return nil, nil, false, nil
end

local allAnimals = {}
local selectedTargetIndex = 1

local function scanAllPlots()
    local channels = getChannelsTable()
    if not channels then
        allAnimals = {}
        return
    end

    local nextAnimals = {}
    local usedDebrisParts = {}

    for channelId, channelObj in pairs(channels) do
        local ok, data = pcall(function() return channelObj:GetTable() end)
        if not (ok and type(data) == "table" and data.AnimalList) then continue end

        local owner = data.Owner
        local isMe = (typeof(owner) == "Instance" and owner == LocalPlayer)
            or (type(owner) == "table" and owner.UserId == LocalPlayer.UserId)
        if isMe then continue end

        for slot, animal in pairs(data.AnimalList) do
            local info = AnimalsData and AnimalsData[animal.Index]
            local displayName = (info and info.DisplayName) or animal.Index
            if not displayName then continue end

            local mpsText, mpsValue, isFusion, pos = getPriceAndPosFromDebris(displayName, usedDebrisParts)
            if isFusion or not pos then continue end

            if not mpsText then
                local baseGen = (info and (info.Generation or info.BaseGeneration)) or 1
                mpsValue = parseToNumber(baseGen)
                mpsText = "$" .. tostring(mpsValue) .. "/s (Base)"
            end

            table.insert(nextAnimals, {
                uid = tostring(channelId) .. "_" .. tostring(slot),
                plotName = channelId,
                slot = tostring(slot),
                name = displayName,
                mutation = animal.Mutation or "None",
                mpsText = mpsText,
                mpsValue = mpsValue,
                pos = pos,
                coordsStr = string.format("📍 %.1f, %.1f, %.1f", pos.X, pos.Y, pos.Z),
            })
        end
    end

    table.sort(nextAnimals, function(a, b)
        return (a.mpsValue or 0) > (b.mpsValue or 0)
    end)

    allAnimals = nextAnimals
end

local function isTargetStillValid(uid)
    for _, a in ipairs(allAnimals) do
        if a.uid == uid then return true end
    end
    return false
end

-- ============================================================
--  STEAL / FLOOR
-- ============================================================
local floorPart = nil
local floorEnabled = false
local floorTargetY = nil

local function setStealFloor(enabled, targetY)
    floorEnabled = enabled
    floorTargetY = targetY

    if not enabled then
        if floorPart then
            floorPart:Destroy()
            floorPart = nil
        end
        return
    end

    if floorPart then return end

    floorPart = Instance.new("Part")
    floorPart.Size = CFG.FLOOR_SIZE
    floorPart.Anchored = true
    floorPart.CanCollide = true
    floorPart.Color = R(200, 35, 35)
    floorPart.Material = Enum.Material.Neon
    floorPart.Transparency = 0.3
    floorPart.Name = "XLSR_Floor"
    floorPart.Parent = workspace

    local _, hrp = getHumanoidAndRoot()
    if hrp then
        floorPart.CFrame = CFrame.new(hrp.Position.X, hrp.Position.Y - CFG.FLOOR_OFFSET_Y, hrp.Position.Z)
    end
end

local function isMeStealing()
    local char = LocalPlayer.Character
    if not char then return false end

    local root = char:FindFirstChild("HumanoidRootPart")
    for _, obj in ipairs(CollectionService:GetTagged("ClientRenderBrainrot")) do
        if obj:IsDescendantOf(char) then return true end

        if obj:IsA("BasePart") and root then
            if obj:GetAttribute("__render_stolen") == true and (obj.Position - root.Position).Magnitude < 6 then
                return true
            end
        end
    end
    return false
end

local function handleSpeedCoil(equip)
    local hum = getHumanoidAndRoot()
    if not hum then return end

    local char = LocalPlayer.Character
    local current = char and char:FindFirstChildOfClass("Tool")

    if equip and not isMeStealing() then
        local coil = LocalPlayer.Backpack:FindFirstChild("Speed Coil") or (char and char:FindFirstChild("Speed Coil"))
        if coil and coil.Parent == LocalPlayer.Backpack then
            hum:EquipTool(coil)
        end
        return
    end

    if current and current.Name == "Speed Coil" then
        hum:UnequipTools()
    end
end

local promptCache = {}

local function findPrompt(plotName, slotName)
    local uid = plotName .. "_" .. slotName
    local cached = promptCache[uid]
    if cached and cached.Parent and cached:IsDescendantOf(workspace) then
        return cached
    end

    local plots = workspace:FindFirstChild("Plots")
    local plot = plots and plots:FindFirstChild(plotName)
    local podium = plot and plot:FindFirstChild("AnimalPodiums") and plot.AnimalPodiums:FindFirstChild(slotName)

    local prompt = nil
    if podium and podium:FindFirstChild("Base") and podium.Base:FindFirstChild("Spawn") and podium.Base.Spawn:FindFirstChild("PromptAttachment") then
        prompt = podium.Base.Spawn.PromptAttachment:FindFirstChildOfClass("ProximityPrompt")
    end
    if not prompt and podium then
        prompt = podium:FindFirstChildWhichIsA("ProximityPrompt", true)
    end

    if prompt then promptCache[uid] = prompt end
    return prompt
end

local function forceGrab(target)
    local prompt = findPrompt(target.plotName, target.slot)
    if not prompt or not prompt:IsDescendantOf(workspace) then return false end

    local _, hrp = getHumanoidAndRoot()
    if not hrp then return false end

    local basePart = prompt.Parent
    if basePart and basePart:IsA("Attachment") then basePart = basePart.Parent end
    if not (basePart and basePart:IsA("BasePart")) then return false end

    if (hrp.Position - basePart.Position).Magnitude > CFG.GRAB_DISTANCE then return false end

    pcall(function()
        prompt.HoldDuration = 0
        prompt.RequiresLineOfSight = false
        prompt.MaxActivationDistance = CFG.PROMPT_DISTANCE
        prompt.Enabled = true
    end)

    if fireproximityprompt then
        pcall(fireproximityprompt, prompt, 0)
        pcall(fireproximityprompt, prompt, 1)
        pcall(fireproximityprompt, prompt)
    end

    pcall(function()
        prompt:InputHoldBegin()
        task.wait()
        prompt:InputHoldEnd()
    end)

    return true
end

-- ============================================================
--  UI (mínima, centrada en estabilidad)
-- ============================================================
local ASGui = makeGui("XLSR_AS_GUI", 101)
local RushGui = makeGui("XLSR_Rush_GUI", 102)

local panel = Instance.new("Frame")
panel.Name = "ASPanel"
panel.Size = UDim2.new(0, 280, 0, 420)
panel.Position = UDim2.new(0.5, -140, 0.5, -210)
panel.BackgroundColor3 = COLORS.BG
panel.BorderSizePixel = 0
panel.Active = true
panel.Draggable = true
panel.Parent = ASGui
RC(panel, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 36)
title.Position = UDim2.new(0, 10, 0, 8)
title.BackgroundTransparency = 1
title.Text = "XLSR // HUB (Mejorado)"
title.TextColor3 = COLORS.TEXT
title.Font = Enum.Font.GothamBlack
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 18)
status.Position = UDim2.new(0, 10, 1, -28)
status.BackgroundTransparency = 1
status.Text = "Listo"
status.TextColor3 = COLORS.TEXT_DIM
status.Font = Enum.Font.Gotham
status.TextSize = 10
status.TextXAlignment = Enum.TextXAlignment.Center
status.Parent = panel

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -20, 0, 260)
list.Position = UDim2.new(0, 10, 0, 48)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.CanvasSize = UDim2.new(0, 0, 0, 600)
list.Parent = panel

local rows = {}
for i = 1, 10 do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -8, 0, 55)
    btn.Position = UDim2.new(0, 0, 0, (i - 1) * 60)
    btn.BackgroundColor3 = COLORS.ELEMENT
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = list
    RC(btn, 8)

    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = COLORS.BORDER

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Size = UDim2.new(1, -16, 0, 18)
    nameLbl.Position = UDim2.new(0, 8, 0, 8)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = "Cargando..."
    nameLbl.TextColor3 = COLORS.TEXT
    nameLbl.Font = Enum.Font.GothamBold
    nameLbl.TextSize = 12
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.Parent = btn

    local metaLbl = Instance.new("TextLabel")
    metaLbl.Size = UDim2.new(1, -16, 0, 16)
    metaLbl.Position = UDim2.new(0, 8, 0, 30)
    metaLbl.BackgroundTransparency = 1
    metaLbl.Text = ""
    metaLbl.TextColor3 = COLORS.SUCCESS
    metaLbl.Font = Enum.Font.Gotham
    metaLbl.TextSize = 10
    metaLbl.TextXAlignment = Enum.TextXAlignment.Left
    metaLbl.Parent = btn

    btn.MouseButton1Click:Connect(function()
        selectedTargetIndex = i
        for j, row in ipairs(rows) do
            row.stroke.Color = (j == selectedTargetIndex) and COLORS.ACCENT or COLORS.BORDER
        end
    end)

    rows[i] = {btn = btn, stroke = stroke, name = nameLbl, meta = metaLbl}
end

local asfRunning = false
local activeTarget = nil
local asfLockPos = nil

local runBtn = Instance.new("TextButton")
runBtn.Size = UDim2.new(1, -20, 0, 32)
runBtn.Position = UDim2.new(0, 10, 0, 318)
runBtn.BackgroundColor3 = R(140, 30, 30)
runBtn.Text = "⚡ INICIAR ASF"
runBtn.Font = Enum.Font.GothamBold
runBtn.TextSize = 11
runBtn.TextColor3 = COLORS.TEXT
runBtn.Parent = panel
RC(runBtn, 6)

local floatBtn = runBtn:Clone()
floatBtn.Size = UDim2.new(0, 150, 0, 35)
floatBtn.Position = UDim2.new(0, 20, 0.5, 60)
floatBtn.Parent = RushGui
floatBtn.Active = true
floatBtn.Draggable = true

local function setRunningUI(enabled)
    asfRunning = enabled
    runBtn.Text = enabled and "⛔ DETENER ASF" or "⚡ INICIAR ASF"
    runBtn.BackgroundColor3 = enabled and R(200, 40, 40) or R(140, 30, 30)
    floatBtn.Text = runBtn.Text
    floatBtn.BackgroundColor3 = runBtn.BackgroundColor3
end

local function asfWalkTo(target, timeout)
    local hum, hrp = getHumanoidAndRoot()
    if not (hum and hrp) then return false end

    handleSpeedCoil(true)

    local elapsed = 0
    while asfRunning and elapsed < (timeout or CFG.WALK_TIMEOUT) do
        if isMeStealing() then
            asfLockPos = nil
            return false
        end

        if not isTargetStillValid(target.uid) then
            asfLockPos = nil
            return false
        end

        asfLockPos = Vector3.new(target.pos.X, hrp.Position.Y, target.pos.Z)
        if (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(target.pos.X, 0, target.pos.Z)).Magnitude < 3.5 then
            break
        end

        task.wait(CFG.WALK_STEP)
        elapsed += CFG.WALK_STEP
    end

    return asfRunning
end

local function doOneCycle()
    if isMeStealing() then
        status.Text = "⏸ Manos ocupadas"
        status.TextColor3 = COLORS.WARNING
        return false
    end

    status.Text = "🔍 Escaneando"
    status.TextColor3 = COLORS.WARNING
    scanAllPlots()

    local target = allAnimals[selectedTargetIndex]
    if not target then
        status.Text = "❌ Sin objetivos"
        status.TextColor3 = R(255, 80, 80)
        return false
    end

    activeTarget = target
    status.Text = "🚶 " .. target.name
    status.TextColor3 = R(100, 200, 255)

    if not asfWalkTo(target, CFG.WALK_TIMEOUT) then
        handleSpeedCoil(false)
        activeTarget = nil
        return false
    end

    local _, hrp = getHumanoidAndRoot()
    local needFloor = hrp and ((target.pos.Y - hrp.Position.Y) > 10) or false

    if needFloor then
        setStealFloor(true, target.pos.Y)
        local t = 0
        while asfRunning and t < 8 do
            local _, now = getHumanoidAndRoot()
            if now and now.Position.Y >= target.pos.Y - 6 then break end
            if isMeStealing() or not isTargetStillValid(target.uid) then break end
            task.wait(0.1)
            t += 0.1
        end
    else
        setStealFloor(false)
    end

    status.Text = "⚡ Robando " .. target.name
    status.TextColor3 = COLORS.ACCENT

    while asfRunning and not isMeStealing() and isTargetStillValid(target.uid) do
        forceGrab(target)
        task.wait(0.05)
    end

    if isMeStealing() then
        status.Text = "✅ ¡Éxito!"
        status.TextColor3 = COLORS.SUCCESS
    else
        status.Text = "⏱ Objetivo perdido"
        status.TextColor3 = COLORS.WARNING
    end

    setStealFloor(false)
    asfLockPos = nil
    activeTarget = nil
    handleSpeedCoil(false)
    return true
end

local function stopASF()
    setRunningUI(false)
    asfLockPos = nil
    activeTarget = nil
    setStealFloor(false)
    handleSpeedCoil(false)
    status.Text = "⛔ Detenido"
    status.TextColor3 = R(255, 100, 100)
end

local function startASF()
    if asfRunning then return end
    setRunningUI(true)

    task.spawn(function()
        while asfRunning do
            doOneCycle()
            task.wait(0.06)
        end
        stopASF()
    end)
end

runBtn.MouseButton1Click:Connect(function()
    if asfRunning then stopASF() else startASF() end
end)
floatBtn.MouseButton1Click:Connect(function()
    if asfRunning then stopASF() else startASF() end
end)

-- ============================================================
--  LOOPS
-- ============================================================
RunService.Heartbeat:Connect(function()
    if floorEnabled and floorPart and floorTargetY then
        local _, hrp = getHumanoidAndRoot()
        if hrp then
            local currentY = floorPart.Position.Y
            local desiredY = floorTargetY - CFG.FLOOR_OFFSET_Y

            if hrp.Position.Y < currentY - 5 then
                currentY = hrp.Position.Y - CFG.FLOOR_OFFSET_Y
            end
            if currentY < desiredY then
                currentY = math.min(currentY + 1.8, desiredY)
            end

            floorPart.CFrame = CFrame.new(hrp.Position.X, currentY, hrp.Position.Z)
        end
    end

    if asfRunning and asfLockPos then
        local hum, hrp = getHumanoidAndRoot()
        if hum and hrp and not isMeStealing() then
            asfLockPos = Vector3.new(asfLockPos.X, hrp.Position.Y, asfLockPos.Z)
            hum:MoveTo(asfLockPos)
        end
    end
end)

task.spawn(function()
    local lastTop = ""
    while task.wait(CFG.SCAN_INTERVAL) do
        if not panel.Parent then break end

        scanAllPlots()
        local top = allAnimals[1]
        if top and top.uid ~= lastTop then
            if lastTop ~= "" then
                notify("¡Nuevo Top Brainrot!", string.format("%s [%s]", top.name, top.mpsText))
            end
            lastTop = top.uid
        end

        for i = 1, 10 do
            local row = rows[i]
            local pet = allAnimals[i]
            if pet then
                local mut = (pet.mutation ~= "None") and (" [" .. tostring(pet.mutation) .. "]") or ""
                row.name.Text = string.format("#%d %s%s", i, tostring(pet.name), mut)
                row.meta.Text = string.format("%s · %s", tostring(pet.mpsText), tostring(pet.coordsStr))
            else
                row.name.Text = string.format("#%d (vacío)", i)
                row.meta.Text = ""
            end
            row.stroke.Color = (i == selectedTargetIndex) and COLORS.ACCENT or COLORS.BORDER
        end
    end
end)

-- ============================================================
--  MINI WIKI IMAGE FETCH (opcional cache local)
-- ============================================================
local WIKI_API = "https://stealabrainrot.fandom.com/api.php"
local imageCache = {}
local pending = {}

local function cleanAnimalName(name)
    if not name then return "" end
    return tostring(name)
        :gsub("%s*%[.-%]%s*$", "")
        :gsub("%s*%(.-%)%s*$", "")
        :match("^(.-)%s*$") or tostring(name)
end

local function fetchWikiImage(cleanName)
    if cleanName == "" or imageCache[cleanName] or pending[cleanName] then return end
    pending[cleanName] = true

    task.spawn(function()
        local okReq, res = pcall(function()
            return request({
                Url = WIKI_API
                    .. "?action=query&titles=" .. HttpService:UrlEncode(cleanName)
                    .. "&prop=pageimages&pithumbsize=256&format=json&origin=*",
                Method = "GET",
            })
        end)

        if not (okReq and res and res.StatusCode == 200) then
            pending[cleanName] = nil
            return
        end

        local data = safeJSONDecode(res.Body)
        if not data or not data.query or not data.query.pages then
            pending[cleanName] = nil
            return
        end

        local thumbUrl = nil
        for _, page in pairs(data.query.pages) do
            if page.thumbnail and page.thumbnail.source then
                thumbUrl = page.thumbnail.source
                break
            end
        end
        if not thumbUrl then
            pending[cleanName] = nil
            return
        end

        local okImg, imgRes = pcall(function()
            return request({Url = thumbUrl, Method = "GET"})
        end)
        if not (okImg and imgRes and imgRes.Body) then
            pending[cleanName] = nil
            return
        end

        local fileName = "xlsr_img_" .. HttpService:GenerateGUID(false):sub(1, 8) .. ".png"
        pcall(function()
            writefile(fileName, imgRes.Body)
            imageCache[cleanName] = getcustomasset(fileName)
        end)

        pending[cleanName] = nil
    end)
end

-- ejemplo de uso no invasivo
if allAnimals[1] and allAnimals[1].name then
    fetchWikiImage(cleanAnimalName(allAnimals[1].name))
end
