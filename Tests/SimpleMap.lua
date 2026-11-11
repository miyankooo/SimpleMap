-- Checks the overlay data, the reveal, the move and resize maths and the onboarding against stubs of the client.
-- Run from the repo root: lua Tests/SimpleMap.lua
local failures = 0
local function Check(label, condition)
    print((condition and "  pass  " or "  FAIL  ") .. label)
    if not condition then failures = failures + 1 end
end

-- A frame that records what the addon sets on it and ignores every other call.
local function Frame(fields)
    local frame = fields or {}
    frame.scripts, frame.scale = {}, 1
    function frame:SetPoint(...) self.point = { ... } end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetScript(name, script) self.scripts[name] = script end
    function frame:HookScript(name, script) self.scripts[name] = script end
    function frame:SetScale(scale) self.scale = scale end
    function frame:GetScale() return self.scale end
    function frame:Hide() self.hidden = true end
    function frame:EnableMouse(enabled) self.mouse = enabled end
    function frame:IsVisible() return false end
    function frame:GetFrameLevel() return 1 end
    return setmetatable(frame, { __index = function() return function() end end })
end

local function FontString()
    return {
        SetText = function(self, text) self.text = text end,
        GetText = function(self) return self.text end,
        SetVertexColor = function() end,
    }
end

function hooksecurefunc(object, name, hook)
    local original = object[name]
    object[name] = function(...)
        original(...)
        hook(...)
    end
end

local onLoaded, onLogin, mapEvents = {}, nil, {}
EventUtil = {
    ContinueOnAddOnLoaded = function(name, callback) onLoaded[name] = callback end,
    ContinueOnPlayerLogin = function(callback) onLogin = callback end,
}
EventRegistry = { RegisterCallback = function(_, event, callback) mapEvents[event] = callback end }
C_AddOns = { GetAddOnMetadata = function() return "Simple Map" end }
NORMAL_FONT_COLOR = { WrapTextInColorCode = function(_, text) return "<gold>" .. text .. "</gold>" end }
HelpTip = { ButtonStyle = {}, Point = {}, Alignment = {} }
strtrim = function(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end
Clamp = function(value, low, high) return math.min(math.max(value, low), high) end
SlashCmdList = {}
local cursor
SetCursor = function(name) cursor = name end
GameTooltip = setmetatable({}, { __index = function() return function() end end })
GameTooltip_SetTitle, GameTooltip_AddNormalLine = function() end, function() end

AREA_NAME_FONT_COLOR = { GetRGB = function() return 1, 1, 1 end }

local grip, label
CreateFrame = function(_, _, _, template)
    local frame = Frame()
    if template == "PanelResizeButtonTemplate" then grip = frame end
    if template == "AreaLabelFrameTemplate" then
        label = frame
        frame.Name = FontString()
    end
    return frame
end

-- The cursor in UIParent units, on a UI scale of 2.
local cursorX, cursorY = 0, 0
GetCursorPosition = function() return cursorX * 2, cursorY * 2 end
UIParent = Frame({ GetEffectiveScale = function() return 2 end, GetWidth = function() return 1400 end })

local textures = {}
CreateTexturePool = function()
    return {
        ReleaseAll = function() textures = {} end,
        Acquire = function()
            local texture = Frame()
            function texture:SetSize(width, height) self.size = { width, height } end
            function texture:SetTexCoord(...) self.coords = { ... } end
            function texture:SetTexture(file) self.file = file end
            table.insert(textures, texture)
            return texture
        end,
    }
end
local areaNames = { [11] = "Goldshire", [13] = "Lion's Pride Inn" }
C_Map = {
    GetMapArtID = function() return 99 end,
    GetMapArtLayers = function() return { { layerWidth = 1000, layerHeight = 700, tileWidth = 256, tileHeight = 256 } } end,
    GetAreaInfo = function(areaID) return areaNames[areaID] end,
}
C_MapExplorationInfo = { GetExploredMapTextures = function() return { { fileDataIDs = { 2001 } } } end }

local maximized = false
local map = { GetMapID = function() return 1 end }
function map.GetCanvasContainer() return { GetCurrentLayerIndex = function() return 1 end } end
local pin = Frame({ dataProvider = { GetDrawLayer = function() return "ARTWORK", 0 end } })
pin.RefreshOverlays = function() end
function pin.GetMap() return map end
-- Blizzard's area label and another data provider with a label of its own.
local labelProvider = { Label = Frame({ Name = FontString() }), SetOffsetY = function() end }
local mouseFocus, cursorMapX, cursorMapY = false, 0, 0
-- A 1000 x 700 map whose top-left corner sits at 100, 750.
WorldMapFrame = Frame({
    BlackoutFrame = Frame({ Blackout = Frame() }),
    BorderFrame = Frame({ TitleContainer = Frame() }),
    dataProviders = { [labelProvider] = true, [{ Label = Frame() }] = true },
})
function WorldMapFrame.IsMaximized() return maximized end
function WorldMapFrame.IsCanvasMouseFocus() return mouseFocus end
function WorldMapFrame.GetNormalizedCursorPosition() return cursorMapX, cursorMapY end
function WorldMapFrame.GetLeft() return 100 end
function WorldMapFrame.GetTop() return 750 end
function WorldMapFrame.GetSize() return 1000, 700 end
function WorldMapFrame.EnumeratePinsByTemplate()
    local given
    return function() if not given then given = true return pin end end
end

local function Capture(call)
    local lines, realPrint = {}, print
    print = function(line) table.insert(lines, line) end
    call()
    print = realPrint
    return lines
end

local function Load(savedVariables)
    SimpleMapDB = savedVariables
    local ns = {}
    for _, file in ipairs({ "Data.lua", "Onboarding.lua", "Map.lua" }) do
        assert(loadfile(file))("SimpleMap", ns)
    end
    local loaded = Capture(function()
        onLoaded.SimpleMap()
        onLoaded.Blizzard_WorldMap()
    end)
    return ns, loaded, Capture(onLogin)
end

local ns, loaded, login = Load(nil)

-- Data.lua: every overlay carries its full tile grid.
local complete, count = true, 0
for _, overlays in pairs(ns.overlays) do
    for _, overlay in ipairs(overlays) do
        count = count + 1
        complete = complete and #overlay - 9 == math.ceil(overlay[1] / 256) * math.ceil(overlay[2] / 256)
            and overlay[5] > 0 and overlay[6] < overlay[8] and overlay[7] < overlay[9]
    end
end
Check(("Data.lua lists %d overlays, each with its area, hit rect and full tile grid"):format(count),
    count > 0 and complete)

-- Onboarding.
local PREFIX = "<gold>[Simple Map]</gold>: "
local WELCOME_START = PREFIX .. "Reveals every area of the world map"
Check("the first load prints nothing and creates the saved table", #loaded == 0 and type(SimpleMapDB) == "table")
Check("the first login prints one welcome line", #login == 1 and login[1]:find(WELCOME_START, 1, true) == 1)
Check("it ends with where the commands are", login[1]:find("Type /sm help for the commands.", 1, true) ~= nil)
Check("the full map hides no world and blocks no clicks",
    WorldMapFrame.BlackoutFrame.Blackout.hidden and WorldMapFrame.BlackoutFrame.mouse == false)

-- Reveal: a 300 x 200 overlay in two tiles, an explored 256 x 256 one and a small one inside the first.
ns.overlays = { [99] = {
    { 300, 200, 10, 20, 11, 10, 20, 310, 220, 1001, 1002 },
    { 256, 256, 0, 0, 12, 0, 0, 256, 256, 2001 },
    { 32, 32, 100, 100, 13, 100, 100, 132, 132, 3001 },
} }
pin:RefreshOverlays()
Check("only the unexplored overlays are drawn, one texture per tile", #textures == 3)
local full, part = textures[1], textures[2]
Check("a full tile reads its whole 256 px file",
    full.size[1] == 256 and full.size[2] == 200 and full.coords[2] == 1 and full.coords[4] == 200 / 256)
Check("a partial tile reads its power-of-two file", part.size[1] == 44 and part.coords[2] == 44 / 64)
Check("tiles sit on the overlay's offset, row by row",
    full.point[2] == 10 and full.point[3] == -20 and part.point[2] == 266 and part.file == 1002)
pin:RefreshOverlays()
Check("a refresh replaces the textures", #textures == 3)

-- Hover names, at art pixels on the 1000 x 700 art.
local function Hover(x, y)
    cursorMapX, cursorMapY = x / 1000, y / 700
    label.scripts.OnUpdate()
    return label.Name.text
end
mouseFocus = true
Check("hovering a revealed area names it", Hover(200, 150) == "Goldshire")
Check("the smallest hit rect wins where two overlap", Hover(116, 116) == "Lion's Pride Inn")
Check("an explored area gets no second name", Hover(5, 5) == nil)
labelProvider.Label.Name:SetText("Elwynn Forest")
Check("Blizzard's own label keeps priority", Hover(200, 150) == nil)
labelProvider.Label.Name:SetText("")
mouseFocus = false
Check("the name goes when the cursor leaves the map", Hover(200, 150) == nil)

-- Move: Blizzard's next anchor gives way to the saved place, in UIParent units.
SimpleMapDB.compact = { 100, 500 }
WorldMapFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
local point = WorldMapFrame.point
Check("Blizzard's anchor gives way to the saved place",
    point[3] == "BOTTOMLEFT" and point[4] == 100 and point[5] == 500)

-- Resize: the scale follows the cursor, at least 0.5 and never past the screen.
maximized = true
mapEvents.WorldMapMaximized()
Check("the grabber shows on the full map", grip ~= nil and grip.scripts.OnMouseDown ~= nil)
grip.scripts.OnEnter(grip)
Check("hovering it shows the small resize cursor", cursor == "Interface\\Cursor\\UI-Cursor-SizeRight")
cursorX, cursorY = 1100, 50
grip.scripts.OnMouseDown()
Check("a press saves the full map's top-left corner", SimpleMapDB.expanded[1] == 100 and SimpleMapDB.expanded[2] == 750)
cursorX, cursorY = 900, 190
grip.scripts.OnUpdate()
Check("a drag of 200 left and 140 down shrinks the 1000 x 700 map to 0.8", math.abs(SimpleMapDB.scale - 0.8) < 1e-9)
point = WorldMapFrame.point
Check("its top-left corner stays put", WorldMapFrame.scale == SimpleMapDB.scale
    and math.abs(point[4] * WorldMapFrame.scale - 100) < 1e-9 and math.abs(point[5] * WorldMapFrame.scale - 750) < 1e-9)
cursorX, cursorY = 100, 50
grip.scripts.OnUpdate()
Check("a drag far left stops at half size", SimpleMapDB.scale == 0.5)
cursorX, cursorY = 2100, -950
grip.scripts.OnUpdate()
Check("a drag far out stops where the map still fits on screen", math.abs(SimpleMapDB.scale - 750 / 700) < 1e-9)
mapEvents.WorldMapMinimized()
Check("the small map keeps its own size", WorldMapFrame.scale == 1)
mapEvents.WorldMapMaximized()
Check("the full map gets its saved size back", WorldMapFrame.scale == SimpleMapDB.scale)

-- Slash commands.
local function Slash(message)
    return Capture(function() SlashCmdList.SIMPLEMAP(message) end)
end
local START = PREFIX .. "Drag a map's title to move it, or the bottom-right corner of the full-screen map to resize it."
for _, message in ipairs({ "", "help", "?", " HELP " }) do
    local lines = Slash(message)
    Check(("/sm %q prints the help line"):format(message), #lines == 1 and lines[1]:find(START, 1, true) == 1)
end
SimpleMapDB.tipSeen = true
local lines = Slash("intro")
Check("/sm intro prints the welcome line and brings the tip back",
    #lines == 1 and lines[1]:find(WELCOME_START, 1, true) == 1 and SimpleMapDB.tipSeen == nil)
lines = Slash("reset")
Check("/sm reset forgets every place and size", SimpleMapDB.compact == nil and SimpleMapDB.expanded == nil
    and SimpleMapDB.scale == nil and WorldMapFrame.scale == 1 and lines[1] == PREFIX .. "Map place and size reset.")
lines = Slash("minimap")
Check("an unknown word prints the hint", lines[1] == PREFIX .. "Unknown command. Type /sm help for the list.")

ns, loaded, login = Load({})
Check("a later load and login print nothing", #loaded == 0 and #login == 0)

print(failures == 0 and "SimpleMap: all checks passed" or ("SimpleMap: " .. failures .. " failed"))
os.exit(failures == 0 and 0 or 1)
