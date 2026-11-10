local addonName, ns = ...

ns.title = C_AddOns.GetAddOnMetadata(addonName, "Title")

-- Every chat line: the toc title in brackets in the gold of Blizzard's own chat links (ItemRef.lua), the
-- message in the chat frame's own colour.
function ns.Print(message)
    print(NORMAL_FONT_COLOR:WrapTextInColorCode("[" .. ns.title .. "]") .. ": " .. message)
end

-- The addon has no window or settings page: its surface is the map itself. So the welcome line has no link;
-- it says what the addon does, where to start and where the commands are. The help line opens with the same
-- where-to-start sentence.
local START = "Drag a map's title to move it, or the bottom-right corner of the full-screen map to resize it."
local WELCOME = "Reveals every area of the world map and lets you move and resize it. " .. START
    .. " Type /sm help for the commands."
local HELP = START .. " Type /sm reset to restore the map's place and size, /sm intro to see the welcome line"
    .. " and the tip again, or /sm help for this list."

-- Blizzard's yellow callout as an own HelpTipTemplate frame, never HelpTip:Show, whose shared pool taints the
-- tips Blizzard shows later. It points down at the resize grabber and opens to the left, off the map's edge.
function ns.AttachTip(target)
    local tip
    local info = {
        text = "Drag the title to move the map and this corner to resize it.",
        buttonStyle = HelpTip.ButtonStyle.Close,
        targetPoint = HelpTip.Point.TopEdgeCenter,
        alignment = HelpTip.Alignment.Right,
        onAcknowledgeCallback = function() ns.db.tipSeen = true end,
    }
    local function ShowTip()
        if ns.db.tipSeen or (tip and tip:IsShown()) then return end
        if not tip then
            tip = CreateFrame("Frame", nil, target, "HelpTipTemplate")
            tip.width = HelpTip.width
            tip:SetWidth(tip.width)
        end
        tip:Reset()
        tip:Init(target, info, target)
        tip:Show()
    end
    target:HookScript("OnShow", ShowTip)
    if target:IsVisible() then ShowTip() end

    -- The player used the feature: the tip goes for good, shown or not.
    local function Retire()
        if tip and tip.info then tip:Acknowledge() else ns.db.tipSeen = true end
    end
    return ShowTip, Retire
end

-- At login the client's own load lines are already in chat.
EventUtil.ContinueOnPlayerLogin(function()
    if ns.firstRun then
        ns.Print(WELCOME)
    end
end)

-- With nothing to open, the bare command prints the help line.
SLASH_SIMPLEMAP1, SLASH_SIMPLEMAP2 = "/simplemap", "/sm"
SlashCmdList.SIMPLEMAP = function(message)
    local command = strtrim(message or ""):lower()
    if command == "" or command == "help" or command == "?" then
        ns.Print(HELP)
    elseif command == "intro" then
        ns.Print(WELCOME)
        ns.db.tipSeen = nil
        ns.ShowTip()
    elseif command == "reset" then
        ns.Reset()
        ns.Print("Map place and size reset.")
    else
        ns.Print("Unknown command. Type /sm help for the list.")
    end
end
