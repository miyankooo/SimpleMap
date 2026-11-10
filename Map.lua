local addonName, ns = ...

-- Below half size the full map's text and buttons get hard to read.
local MIN_SCALE = 0.5

local db, resizeStart

-- Partial tiles sit in power-of-two files of at least 16 px (MapExplorationDataProvider.lua:121-153).
local function FileSize(pixels)
    local size = 16
    while size < pixels do
        size = size * 2
    end
    return size
end

-- Draws every overlay of the zone the player has not explored, on the pin, layer and tile grid Blizzard uses
-- for the explored ones (MapExplorationDataProvider.lua:96-178).
local function Reveal(pin, textures)
    textures:ReleaseAll()
    local map = pin:GetMap()
    local mapID = map:GetMapID()
    local overlays = mapID and ns.overlays[C_Map.GetMapArtID(mapID)]
    if not overlays then
        return
    end

    local explored = {}
    for _, info in ipairs(C_MapExplorationInfo.GetExploredMapTextures(mapID) or {}) do
        explored[info.fileDataIDs[1]] = true
    end
    local layer = C_Map.GetMapArtLayers(mapID)[map:GetCanvasContainer():GetCurrentLayerIndex()]
    local tileWidth, tileHeight = layer.tileWidth, layer.tileHeight

    for _, overlay in ipairs(overlays) do
        local width, height, offsetX, offsetY = overlay[1], overlay[2], overlay[3], overlay[4]
        if not explored[overlay[5]] then
            local columns = math.ceil(width / tileWidth)
            for i = 5, #overlay do
                local column = (i - 5) % columns
                local row = math.floor((i - 5) / columns)
                local pixelWidth = math.min(tileWidth, width - column * tileWidth)
                local pixelHeight = math.min(tileHeight, height - row * tileHeight)
                local texture = textures:Acquire()
                texture:SetSize(pixelWidth, pixelHeight)
                texture:SetTexCoord(0, pixelWidth / FileSize(pixelWidth), 0, pixelHeight / FileSize(pixelHeight))
                texture:SetPoint("TOPLEFT", offsetX + column * tileWidth, -(offsetY + row * tileHeight))
                texture:SetTexture(overlay[i], nil, nil, "TRILINEAR")
                texture:Show()
            end
        end
    end
end

local function Mode()
    return WorldMapFrame:IsMaximized() and "expanded" or "compact"
end

-- Each mode's place is its top-left corner in UIParent units, so it holds at any scale.
local function SavePlace()
    local scale = WorldMapFrame:GetScale()
    db[Mode()] = { WorldMapFrame:GetLeft() * scale, WorldMapFrame:GetTop() * scale }
end

-- Blizzard's panel manager anchors the map on every open, mode change and other panel's open
-- (UIParentPanelManager.lua:141-143, 643), so this runs after each of its SetPoint calls.
local placing
local function Place()
    local place = db[Mode()]
    if placing or not place then
        return
    end
    placing = true
    local scale = WorldMapFrame:GetScale()
    WorldMapFrame:ClearAllPoints()
    WorldMapFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", place[1] / scale, place[2] / scale)
    placing = false
end

-- Scales the full map with the cursor's travel since the press, its top-left corner fixed and its size kept on
-- screen. The scroll container keeps its own size, so Blizzard's zoom levels and its cursor maths, which divide
-- by the map's effective scale (MapCanvas_ScrollContainerMixin.lua:819-823), stay right.
local function Resize()
    local x, y = GetCursorPosition()
    local uiScale = UIParent:GetEffectiveScale()
    local width, height = WorldMapFrame:GetSize()
    local start = resizeStart
    local grow = ((x / uiScale - start.x) / width + (start.y - y / uiScale) / height) / 2
    local place = db.expanded
    local fit = math.min((UIParent:GetWidth() - place[1]) / width, place[2] / height)
    db.scale = Clamp(start.scale + grow, MIN_SCALE, math.max(fit, MIN_SCALE))
    WorldMapFrame:SetScale(db.scale)
    Place()
end

function ns.Reset()
    db.compact, db.expanded, db.scale = nil, nil, nil
    if WorldMapFrame:IsMaximized() then
        WorldMapFrame:SetScale(1)
        WorldMapFrame:ClearAllPoints()
        WorldMapFrame:SetPoint("TOP") -- Blizzard's maximizePoint (Blizzard_WorldMap.lua:135)
    end
end

local function Setup()
    local border = WorldMapFrame.BorderFrame

    -- The full map no longer hides the world behind it or blocks clicks on it.
    WorldMapFrame.BlackoutFrame.Blackout:Hide()
    WorldMapFrame.BlackoutFrame:EnableMouse(false)

    -- Hooks only, never a write to Blizzard's map tables: a tainted refresh makes its pins call the protected
    -- SetPassThroughButtons (Blizzard_MapCanvas.lua:331), which is blocked in combat.
    for pin in WorldMapFrame:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
        local textures = CreateTexturePool(pin, pin.dataProvider:GetDrawLayer())
        hooksecurefunc(pin, "RefreshOverlays", function()
            Reveal(pin, textures)
        end)
    end

    WorldMapFrame:SetMovable(true)
    WorldMapFrame:SetClampedToScreen(true)
    hooksecurefunc(WorldMapFrame, "SetPoint", Place)

    -- The title bar moves the map. It sits under the bar's buttons, which keep their clicks.
    local handle = CreateFrame("Frame", nil, border)
    handle:SetAllPoints(border.TitleContainer)
    handle:SetFrameLevel(border:GetFrameLevel())
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
        WorldMapFrame:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        WorldMapFrame:StopMovingOrSizing()
        SavePlace()
        ns.RetireTip()
    end)

    -- Blizzard's resize grabber, driving the scale instead of the size.
    local grip = CreateFrame("Button", nil, border, "PanelResizeButtonTemplate")
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetFrameLevel(border.TitleContainer:GetFrameLevel())
    grip:Hide()
    grip:HookScript("OnEnter", function(self)
        -- The template's UI_RESIZE_CURSOR draws large; Blizzard's 32 px resize arrow replaces it.
        SetCursor("Interface\\Cursor\\UI-Cursor-SizeRight")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip_SetTitle(GameTooltip, ns.title)
        GameTooltip_AddNormalLine(GameTooltip, "Drag to resize the map. Type /sm reset to restore its place and size.")
        GameTooltip:Show()
    end)
    grip:HookScript("OnLeave", GameTooltip_Hide)
    grip:SetScript("OnMouseDown", function()
        SavePlace()
        local x, y = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        resizeStart = { x = x / uiScale, y = y / uiScale, scale = WorldMapFrame:GetScale() }
        grip:SetScript("OnUpdate", Resize)
    end)
    grip:SetScript("OnMouseUp", function()
        grip:SetScript("OnUpdate", nil)
        ns.RetireTip()
    end)
    ns.ShowTip, ns.RetireTip = ns.AttachTip(grip)

    -- Only the full map scales. Blizzard fires these before it sizes and places the map (Blizzard_WorldMap.lua:40-62).
    EventRegistry:RegisterCallback("WorldMapMaximized", function()
        WorldMapFrame:SetScale(db.scale or 1)
        grip:Show()
    end, ns)
    EventRegistry:RegisterCallback("WorldMapMinimized", function()
        WorldMapFrame:SetScale(1)
        grip:Hide()
    end, ns)
end

-- No saved table yet means the account's first login with the addon.
EventUtil.ContinueOnAddOnLoaded(addonName, function()
    ns.firstRun = SimpleMapDB == nil
    SimpleMapDB = SimpleMapDB or {}
    db = SimpleMapDB
    ns.db = db
    EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", Setup)
end)
