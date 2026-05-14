-- KCx Translator
-- Personal local-only Spanish <-> English translation helper for WoW TBC Classic.
--
-- Design goals:
-- 1) Blizzard-compliant informational addon only (no automation, no auto-send).
-- 2) Beginner-readable and heavily commented.
-- 3) Easy to expand by adding new dictionary lines.

local ADDON_NAME = "KCx Translator"
KCxTranslatorDB = KCxTranslatorDB or {}

-- Toggle for incoming chat translation (off by default).
local autoTranslateChat = false
local debugMode = false
local debugVerbose = false
local incomingRecent = {}
local incomingPublicThrottle = { windowStart = 0, count = 0 }

-- ----------------------------------------------------------------------------
-- Color helpers (WoW color codes)
-- ----------------------------------------------------------------------------
local COLOR_GREEN = "|cff00ff00"
local COLOR_RED = "|cffff4040"
local COLOR_YELLOW = "|cffffcc00"
local COLOR_BLUE = "|cff9ad8ff"
local COLOR_WHITE = "|cffffffff"
local COLOR_RESET = "|r"
local translatorWindow = nil
local translatorLog = nil
local translatorCopyBox = nil
local lastTranslatedText = ""
local handleSlashCommand
local translateDetailed
local showChannelSetupHelp
local KCxTranslatorAddLine
local actionButtons = {}
local minimapButton = nil
local channelSetupHelpWindow = nil
local channelsWindow = nil
local refreshChannelButtons
local channelToggleButtons = {}

local function createChannelToggleButton(parent, label, toggleType, keyOrNumber, x, y, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 70, 18)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", x, y)
    b.baseLabel = label
    b.toggleType = toggleType
    b.keyOrNumber = keyOrNumber
    table.insert(channelToggleButtons, b)
    return b
end

local function createChannelsWindow()
    if channelsWindow then
        return
    end

    channelsWindow = CreateFrame("Frame", "KCxTranslatorChannelsWindow", UIParent, "BackdropTemplate")
    channelsWindow:SetSize(760, 118)
    channelsWindow:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
    channelsWindow:SetFrameStrata("DIALOG")
    channelsWindow:SetFrameLevel(20)
    channelsWindow:SetClampedToScreen(true)
    channelsWindow:SetMovable(true)
    channelsWindow:EnableMouse(true)
    channelsWindow:RegisterForDrag("LeftButton")
    channelsWindow:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    channelsWindow:SetBackdropColor(0, 0, 0, 0.75)
    channelsWindow:SetScript("OnDragStart", function(self) self:StartMoving() end)
    channelsWindow:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        KCxTranslatorDB.channelsWindowPoint = point
        KCxTranslatorDB.channelsWindowRelPoint = relPoint
        KCxTranslatorDB.channelsWindowX = x
        KCxTranslatorDB.channelsWindowY = y
    end)

    local title = channelsWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 12, -9)
    title:SetText("KCx Channels")

    local closeButton = CreateFrame("Button", nil, channelsWindow, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -2, -2)
    closeButton:SetScript("OnClick", function() channelsWindow:Hide() end)

    local defs = {
        { "Guild", "built_in", "GUILD", 72, 12, -30 },
        { "Party", "built_in", "PARTY", 72, 90, -30 },
        { "Raid", "built_in", "RAID", 72, 168, -30 },
        { "Whisper", "built_in", "WHISPER", 72, 246, -30 },
        { "General /1", "numbered", 1, 96, 12, -56 },
        { "Trade /2", "numbered", 2, 96, 112, -56 },
        { "LocalDef /3", "numbered", 3, 96, 212, -56 },
        { "WorldDef /4", "numbered", 4, 96, 312, -56 },
        { "LFG /5", "numbered", 5, 96, 412, -56 },
        { "Num 6", "numbered", 6, 72, 512, -56 },
        { "Num 7", "numbered", 7, 72, 590, -56 },
        { "Num 8", "numbered", 8, 72, 668, -56 },
    }

    for _, def in ipairs(defs) do
        local btn = createChannelToggleButton(channelsWindow, def[1], def[2], def[3], def[5], def[6], def[4])
        btn:SetScript("OnClick", function(self)
            if handleSlashCommand then
                if self.toggleType == "built_in" then
                    handleSlashCommand("channel " .. string.lower(tostring(self.keyOrNumber)) .. " toggle")
                else
                    handleSlashCommand("channelnum " .. tostring(self.keyOrNumber) .. " toggle")
                end
                if refreshChannelButtons then
                    refreshChannelButtons()
                end
            end
        end)
    end

    local helpButton = CreateFrame("Button", nil, channelsWindow, "UIPanelButtonTemplate")
    helpButton:SetSize(72, 18)
    helpButton:SetPoint("TOPRIGHT", channelsWindow, "TOPRIGHT", -34, -30)
    helpButton:SetText("Help")
    helpButton:SetScript("OnClick", function()
        if showChannelSetupHelp then
            showChannelSetupHelp()
        end
    end)

    if KCxTranslatorDB.channelsWindowPoint and KCxTranslatorDB.channelsWindowRelPoint and KCxTranslatorDB.channelsWindowX and KCxTranslatorDB.channelsWindowY then
        channelsWindow:ClearAllPoints()
        channelsWindow:SetPoint(KCxTranslatorDB.channelsWindowPoint, UIParent, KCxTranslatorDB.channelsWindowRelPoint, KCxTranslatorDB.channelsWindowX, KCxTranslatorDB.channelsWindowY)
    end
    channelsWindow:Hide()
end

local function ensureIncomingDefaults()
    KCxTranslatorDB = KCxTranslatorDB or {}
    if KCxTranslatorDB.incomingEnabled == nil then KCxTranslatorDB.incomingEnabled = true end
    KCxTranslatorDB.enabledChannels = KCxTranslatorDB.enabledChannels or {}
    KCxTranslatorDB.enabledChannelNumbers = KCxTranslatorDB.enabledChannelNumbers or {}
    if KCxTranslatorDB.enabledChannels.GUILD == nil then KCxTranslatorDB.enabledChannels.GUILD = true end
    if KCxTranslatorDB.enabledChannels.PARTY == nil then KCxTranslatorDB.enabledChannels.PARTY = true end
    if KCxTranslatorDB.enabledChannels.RAID == nil then KCxTranslatorDB.enabledChannels.RAID = true end
    if KCxTranslatorDB.enabledChannels.WHISPER == nil then KCxTranslatorDB.enabledChannels.WHISPER = true end
    if KCxTranslatorDB.enabledChannels.PARTY_LEADER == nil then KCxTranslatorDB.enabledChannels.PARTY_LEADER = true end
    if KCxTranslatorDB.enabledChannels.RAID_LEADER == nil then KCxTranslatorDB.enabledChannels.RAID_LEADER = true end
    if KCxTranslatorDB.enabledChannels.RAID_WARNING == nil then KCxTranslatorDB.enabledChannels.RAID_WARNING = true end
    if KCxTranslatorDB.enabledChannels.BN_WHISPER == nil then KCxTranslatorDB.enabledChannels.BN_WHISPER = true end
    if KCxTranslatorDB.enabledChannels.GENERAL == nil then KCxTranslatorDB.enabledChannels.GENERAL = true end
    if KCxTranslatorDB.enabledChannels.TRADE == nil then KCxTranslatorDB.enabledChannels.TRADE = false end
    if KCxTranslatorDB.enabledChannels.LOCALDEFENSE == nil then KCxTranslatorDB.enabledChannels.LOCALDEFENSE = false end
    if KCxTranslatorDB.enabledChannels.LOOKINGFORGROUP == nil then KCxTranslatorDB.enabledChannels.LOOKINGFORGROUP = true end
    if KCxTranslatorDB.enabledChannels.CHANNEL == nil then KCxTranslatorDB.enabledChannels.CHANNEL = false end
    if KCxTranslatorDB.enabledChannels.SAY == nil then KCxTranslatorDB.enabledChannels.SAY = false end
    if KCxTranslatorDB.enabledChannels.YELL == nil then KCxTranslatorDB.enabledChannels.YELL = false end
    if KCxTranslatorDB.enabledChannels.OFFICER == nil then KCxTranslatorDB.enabledChannels.OFFICER = false end
    if KCxTranslatorDB.enabledChannels.INSTANCE_CHAT == nil then KCxTranslatorDB.enabledChannels.INSTANCE_CHAT = false end
    if KCxTranslatorDB.enabledChannels.INSTANCE_CHAT_LEADER == nil then KCxTranslatorDB.enabledChannels.INSTANCE_CHAT_LEADER = false end
    if KCxTranslatorDB.enabledChannels.BATTLEGROUND == nil then KCxTranslatorDB.enabledChannels.BATTLEGROUND = false end
    if KCxTranslatorDB.enabledChannels.BATTLEGROUND_LEADER == nil then KCxTranslatorDB.enabledChannels.BATTLEGROUND_LEADER = false end
    if KCxTranslatorDB.enabledChannels.GUILDRECRUITMENT == nil then KCxTranslatorDB.enabledChannels.GUILDRECRUITMENT = false end
    if KCxTranslatorDB.enabledChannels.SERVICES == nil then KCxTranslatorDB.enabledChannels.SERVICES = false end
    if KCxTranslatorDB.enabledChannelNumbers[1] == nil then KCxTranslatorDB.enabledChannelNumbers[1] = true end
    if KCxTranslatorDB.enabledChannelNumbers[2] == nil then KCxTranslatorDB.enabledChannelNumbers[2] = false end
    if KCxTranslatorDB.enabledChannelNumbers[3] == nil then KCxTranslatorDB.enabledChannelNumbers[3] = false end
    if KCxTranslatorDB.enabledChannelNumbers[4] == nil then KCxTranslatorDB.enabledChannelNumbers[4] = false end
    if KCxTranslatorDB.enabledChannelNumbers[5] == nil then KCxTranslatorDB.enabledChannelNumbers[5] = true end
    if KCxTranslatorDB.enabledChannelNumbers[6] == nil then KCxTranslatorDB.enabledChannelNumbers[6] = false end
    if KCxTranslatorDB.enabledChannelNumbers[7] == nil then KCxTranslatorDB.enabledChannelNumbers[7] = false end
    if KCxTranslatorDB.enabledChannelNumbers[8] == nil then KCxTranslatorDB.enabledChannelNumbers[8] = false end
    if KCxTranslatorDB.maxHistoryLines == nil then KCxTranslatorDB.maxHistoryLines = 500 end
    if KCxTranslatorDB.showConfidence == nil then KCxTranslatorDB.showConfidence = true end
    if KCxTranslatorDB.maxChannelMessagesPerSecond == nil then KCxTranslatorDB.maxChannelMessagesPerSecond = 2 end
    if KCxTranslatorDB.maxTradeLength == nil then KCxTranslatorDB.maxTradeLength = 180 end
    if KCxTranslatorDB.skipHyperlinkHeavyMessages == nil then KCxTranslatorDB.skipHyperlinkHeavyMessages = true end
end

local function createTranslatorWindow()
    if translatorWindow then
        return
    end

    translatorWindow = CreateFrame("Frame", "KCxTranslatorWindow", UIParent, "BackdropTemplate")
    translatorWindow:SetSize(520, 250)
    translatorWindow:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    translatorWindow:SetClampedToScreen(true)
    translatorWindow:SetMovable(true)
    translatorWindow:EnableMouse(true)
    translatorWindow:RegisterForDrag("LeftButton")
    translatorWindow:SetResizable(true)
    if translatorWindow.SetResizeBounds then
        translatorWindow:SetResizeBounds(360, 220, 900, 600)
    else
        if translatorWindow.SetMinResize then
            translatorWindow:SetMinResize(360, 220)
        end
        if translatorWindow.SetMaxResize then
            translatorWindow:SetMaxResize(900, 600)
        end
    end
    translatorWindow:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    translatorWindow:SetBackdropColor(0, 0, 0, 0.70)

    translatorWindow:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    translatorWindow:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        KCxTranslatorDB.windowPoint = point
        KCxTranslatorDB.windowRelPoint = relPoint
        KCxTranslatorDB.windowX = x
        KCxTranslatorDB.windowY = y
        KCxTranslatorDB.windowWidth = self:GetWidth()
        KCxTranslatorDB.windowHeight = self:GetHeight()
    end)
    translatorWindow:SetScript("OnSizeChanged", function(self)
        KCxTranslatorDB.windowWidth = self:GetWidth()
        KCxTranslatorDB.windowHeight = self:GetHeight()
    end)

    local title = translatorWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 12, -9)
    title:SetText("KCx Translator")

    local closeButton = CreateFrame("Button", nil, translatorWindow, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -2, -2)
    closeButton:SetScript("OnClick", function()
        translatorWindow:Hide()
        KCxTranslatorDB.windowShown = false
    end)

    local resizeHandle = CreateFrame("Button", nil, translatorWindow)
    resizeHandle:SetSize(16, 16)
    resizeHandle:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeHandle:EnableMouse(true)
    resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeHandle:SetScript("OnMouseDown", function()
        translatorWindow:StartSizing("BOTTOMRIGHT")
    end)
    resizeHandle:SetScript("OnMouseUp", function()
        translatorWindow:StopMovingOrSizing()
    end)

    translatorLog = CreateFrame("ScrollingMessageFrame", nil, translatorWindow)
    translatorLog:ClearAllPoints()
    translatorLog:SetPoint("TOPLEFT", 12, -54)
    translatorLog:SetPoint("BOTTOMRIGHT", -14, 88)
    translatorLog:SetFrameLevel(translatorWindow:GetFrameLevel() + 1)
    translatorLog:SetFontObject(GameFontHighlightSmall)
    translatorLog:SetJustifyH("LEFT")
    translatorLog:SetFading(false)
    translatorLog:SetMaxLines(KCxTranslatorDB.maxHistoryLines or 500)
    translatorLog:SetIndentedWordWrap(true)
    translatorLog:EnableMouseWheel(true)
    translatorLog:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp()
        else
            self:ScrollDown()
        end
    end)

    local function createSmallButton(label, x, y, cmd)
        local b = CreateFrame("Button", nil, translatorWindow, "UIPanelButtonTemplate")
        b:SetSize(76, 18)
        b:SetFrameLevel(translatorWindow:GetFrameLevel() + 10)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", x, y)
        b:SetText(label)
        b:SetScript("OnClick", function()
            if handleSlashCommand then
                handleSlashCommand(cmd)
            end
        end)
        return b
    end

    actionButtons.incoming = createSmallButton("Incoming", 12, -28, "incoming on")
    actionButtons.clear = createSmallButton("Clear", 92, -28, "clear")
    actionButtons.copylast = createSmallButton("Copy Last", 172, -28, "copylast")
    actionButtons.stats = createSmallButton("Stats", 252, -28, "stats")
    actionButtons.test = createSmallButton("Test", 332, -28, "test")
    actionButtons.channels = createSmallButton("Channels", 412, -28, "channels")
    actionButtons.channels:SetScript("OnClick", function()
        createChannelsWindow()
        if channelsWindow then
            if channelsWindow:IsShown() then
                channelsWindow:Hide()
            else
                channelsWindow:Show()
            end
        end
    end)

    refreshChannelButtons = function()
    ensureIncomingDefaults()
    local ec = KCxTranslatorDB.enabledChannels or {}
    local ecn = KCxTranslatorDB.enabledChannelNumbers or {}

    for _, b in ipairs(channelToggleButtons) do
        local isOn = false

        if b.toggleType == "built_in" then
            isOn = (ec[b.keyOrNumber] == true)
        else
            local numKey = tonumber(b.keyOrNumber)
            local strKey = tostring(b.keyOrNumber)
            isOn = (ecn[numKey] == true) or (ecn[strKey] == true)
        end

        b:SetText(b.baseLabel .. ":" .. (isOn and "ON" or "OFF"))
    end
end

    actionButtons.incoming:ClearAllPoints()
    actionButtons.incoming:SetPoint("TOPLEFT", translatorWindow, "TOPLEFT", 12, -28)
    actionButtons.clear:ClearAllPoints()
    actionButtons.clear:SetPoint("TOPLEFT", translatorWindow, "TOPLEFT", 92, -28)
    actionButtons.copylast:ClearAllPoints()
    actionButtons.copylast:SetPoint("TOPLEFT", translatorWindow, "TOPLEFT", 172, -28)
    actionButtons.stats:ClearAllPoints()
    actionButtons.stats:SetPoint("TOPLEFT", translatorWindow, "TOPLEFT", 252, -28)
    actionButtons.test:ClearAllPoints()
    actionButtons.test:SetPoint("TOPLEFT", translatorWindow, "TOPLEFT", 332, -28)
    actionButtons.channels:ClearAllPoints()
    actionButtons.channels:SetPoint("TOPLEFT", translatorWindow, "TOPLEFT", 412, -28)

    createChannelsWindow()

    local function refreshButtonLabels()
        ensureIncomingDefaults()
        actionButtons.incoming:SetText("Incoming: " .. (KCxTranslatorDB.incomingEnabled and "ON" or "OFF"))
        refreshChannelButtons()
    end

    actionButtons.incoming:SetScript("OnClick", function()
        if handleSlashCommand then
            if KCxTranslatorDB.incomingEnabled then handleSlashCommand("incoming off") else handleSlashCommand("incoming on") end
            refreshButtonLabels()
        end
    end)
    local copyHint = translatorWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    copyHint:SetPoint("BOTTOMLEFT", 12, 50)
    copyHint:SetText("Click a translation to copy (or /kcxt copylast)")

    translatorCopyBox = CreateFrame("EditBox", nil, translatorWindow, "InputBoxTemplate")
    translatorCopyBox:SetPoint("BOTTOMLEFT", 12, 24)
    translatorCopyBox:SetPoint("BOTTOMRIGHT", -14, 24)
    translatorCopyBox:SetHeight(20)
    translatorCopyBox:SetAutoFocus(false)
    translatorCopyBox:SetMaxLetters(1024)
    translatorCopyBox:SetText("")
    translatorCopyBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    if KCxTranslatorDB.windowWidth and KCxTranslatorDB.windowHeight then
        translatorWindow:SetSize(KCxTranslatorDB.windowWidth, KCxTranslatorDB.windowHeight)
    end
    if KCxTranslatorDB.windowPoint and KCxTranslatorDB.windowRelPoint and KCxTranslatorDB.windowX and KCxTranslatorDB.windowY then
        translatorWindow:ClearAllPoints()
        translatorWindow:SetPoint(KCxTranslatorDB.windowPoint, UIParent, KCxTranslatorDB.windowRelPoint, KCxTranslatorDB.windowX, KCxTranslatorDB.windowY)
    end

    if KCxTranslatorDB.windowShown == nil or KCxTranslatorDB.windowShown == true then
        translatorWindow:Show()
    else
        translatorWindow:Hide()
    end
    refreshButtonLabels()
end

local function createChannelSetupHelpWindow()
    if channelSetupHelpWindow then
        return
    end

    channelSetupHelpWindow = CreateFrame("Frame", "KCxTranslatorChannelSetupHelpWindow", UIParent, "BackdropTemplate")
    channelSetupHelpWindow:SetSize(480, 250)
    channelSetupHelpWindow:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    channelSetupHelpWindow:SetFrameStrata("DIALOG")
    channelSetupHelpWindow:SetMovable(true)
    channelSetupHelpWindow:EnableMouse(true)
    channelSetupHelpWindow:RegisterForDrag("LeftButton")
    channelSetupHelpWindow:SetScript("OnDragStart", function(self) self:StartMoving() end)
    channelSetupHelpWindow:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    channelSetupHelpWindow:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    channelSetupHelpWindow:SetBackdropColor(0, 0, 0, 0.80)
    channelSetupHelpWindow:Hide()

    local title = channelSetupHelpWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("KCx Translator Channel Setup")

    local closeButton = CreateFrame("Button", nil, channelSetupHelpWindow, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -2, -2)
    closeButton:SetScript("OnClick", function()
        channelSetupHelpWindow:Hide()
    end)

    local body = channelSetupHelpWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    body:SetPoint("TOPLEFT", 14, -34)
    body:SetPoint("TOPRIGHT", -14, -34)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetText(
        "Built-in chats (Say, Yell, Guild, Party, Raid, Whisper, Officer) are detected automatically.\n\n" ..
        "Public/world channels are safest by number because servers/addons can rename or reorder them.\n\n" ..
        "Recommended order:\n" ..
        "/1 General\n/2 Trade\n/3 LocalDefense\n/4 WorldDefense\n/5 LookingForGroup\n/6 GuildRecruitment\n/7 Services\n/8 Layer\n\n" ..
        "If your server uses different numbers, toggle the matching /1-/8 buttons in KCx Channels.\n\n" ..
        "This addon does not move channels automatically."
    )

    local okButton = CreateFrame("Button", nil, channelSetupHelpWindow, "UIPanelButtonTemplate")
    okButton:SetSize(90, 22)
    okButton:SetPoint("BOTTOMRIGHT", -14, 12)
    okButton:SetText("OK")
    okButton:SetScript("OnClick", function()
        channelSetupHelpWindow:Hide()
    end)

    local hideButton = CreateFrame("Button", nil, channelSetupHelpWindow, "UIPanelButtonTemplate")
    hideButton:SetSize(140, 22)
    hideButton:SetPoint("RIGHT", okButton, "LEFT", -8, 0)
    hideButton:SetText("Don't show again")
    hideButton:SetScript("OnClick", function()
        KCxTranslatorDB.hideChannelSetupHelp = true
        channelSetupHelpWindow:Hide()
    end)
end

showChannelSetupHelp = function()
    ensureIncomingDefaults()
    createChannelSetupHelpWindow()
    if channelSetupHelpWindow then
        channelSetupHelpWindow:Show()
    end
end

local function copyToTranslatorBox(text)
    if not translatorWindow then
        createTranslatorWindow()
    end
    if not translatorCopyBox then
        return
    end
    translatorCopyBox:SetText(tostring(text or ""))
    translatorCopyBox:SetFocus()
    translatorCopyBox:HighlightText()
end

local function createMinimapButton()
    if minimapButton or not Minimap then
        return
    end

    minimapButton = CreateFrame("Button", "KCxTranslatorMinimapButton", Minimap)
    minimapButton:SetSize(32, 32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetMovable(true)
    minimapButton:EnableMouse(true)
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    minimapButton:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -5, 5)

    local icon = minimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(minimapButton)
    icon:SetTexture("Interface\\AddOns\\KCxTranslator\\Media\\KCxTranslatorIcon")

    local function clampToMinimapEdge()
        local mx, my = Minimap:GetCenter()
        local bx, by = minimapButton:GetCenter()
        if not mx or not my or not bx or not by then
            return
        end
        local dx = bx - mx
        local dy = by - my
        local angle = math.atan2(dy, dx)
        local radius = 78
        local x = math.cos(angle) * radius
        local y = math.sin(angle) * radius
        minimapButton:ClearAllPoints()
        minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    minimapButton:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    minimapButton:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        clampToMinimapEdge()
    end)

    minimapButton:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then
            if not translatorWindow then
                createTranslatorWindow()
            end
            if translatorWindow:IsShown() then
                translatorWindow:Hide()
                KCxTranslatorDB.windowShown = false
            else
                translatorWindow:Show()
                KCxTranslatorDB.windowShown = true
            end
        elseif button == "RightButton" then
            if showChannelSetupHelp then
                showChannelSetupHelp()
            end
        end
    end)

    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("KCx Translator")
        GameTooltip:AddLine("Left Click: Toggle Window", 1, 1, 1)
        GameTooltip:AddLine("Right Click: Channel Setup Help", 1, 1, 1)
        GameTooltip:AddLine("Drag: Move Button", 1, 1, 1)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    minimapButton:Show()
end


local function normalizeChannelText(text)
    text = tostring(text or ""):lower()
    text = text:gsub("[%p%c]", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("%s+", " ")
    return text
end

local function normalizeChannelName(channelName)
    local original = tostring(channelName or "")
    local cleaned = string.upper(normalizeChannelText(original))
    cleaned = string.gsub(cleaned, "%s+", " ")

    local compact = string.gsub(cleaned, "%s+", "")
    local key = "CHANNEL"
    if string.find(compact, "TRADE", 1, true) or string.find(compact, "COMERCIO", 1, true) then
        key = "TRADE"
    elseif string.find(compact, "GENERAL", 1, true) then
        key = "GENERAL"
    elseif string.find(compact, "WHISPER", 1, true) then
        key = "WHISPER"
    elseif string.find(compact, "PARTYLEADER", 1, true) then
        key = "PARTY_LEADER"
    elseif string.find(compact, "PARTY", 1, true) then
        key = "PARTY"
    elseif string.find(compact, "RAIDLEADER", 1, true) then
        key = "RAID_LEADER"
    elseif string.find(compact, "RAIDWARNING", 1, true) then
        key = "RAID_WARNING"
    elseif string.find(compact, "RAID", 1, true) then
        key = "RAID"
    elseif string.find(compact, "GUILD", 1, true) then
        key = "GUILD"
    elseif string.find(compact, "LOCALDEFENSE", 1, true) then
        key = "LOCALDEFENSE"
    elseif string.find(compact, "LOOKINGFORGROUP", 1, true) or string.find(compact, "LFG", 1, true) then
        key = "LOOKINGFORGROUP"
    elseif string.find(compact, "GUILDRECRUITMENT", 1, true) then
        key = "GUILDRECRUITMENT"
    elseif string.find(compact, "SERVICES", 1, true) then
        key = "SERVICES"
    end

    if debugMode and debugVerbose then
        KCxTranslatorAddLine("channel normalize: '" .. original .. "' -> '" .. cleaned .. "' -> " .. key, "debug")
    end
    return key
end

local function standardChannelNumberForKey(channelKey)
    local map = {
        GENERAL = 1,
        TRADE = 2,
        LOCALDEFENSE = 3,
        LOOKINGFORGROUP = 5,
    }
    return map[channelKey]
end

local function resolveIncomingChannel(event, channelDisplayName, channelNumberArg, channelNameArg)
    local eventMap = {
        CHAT_MSG_SAY = "SAY",
        CHAT_MSG_GUILD = "GUILD",
        CHAT_MSG_PARTY = "PARTY",
        CHAT_MSG_PARTY_LEADER = "PARTY_LEADER",
        CHAT_MSG_RAID = "RAID",
        CHAT_MSG_RAID_LEADER = "RAID_LEADER",
        CHAT_MSG_RAID_WARNING = "RAID_WARNING",
        CHAT_MSG_YELL = "YELL",
        CHAT_MSG_WHISPER = "WHISPER",
        CHAT_MSG_BN_WHISPER = "BN_WHISPER",
        CHAT_MSG_OFFICER = "OFFICER",
        CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT",
        CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT_LEADER",
        CHAT_MSG_BATTLEGROUND = "BATTLEGROUND",
        CHAT_MSG_BATTLEGROUND_LEADER = "BATTLEGROUND_LEADER",
    }

    if event ~= "CHAT_MSG_CHANNEL" then
        local stableKey = eventMap[event]
        return stableKey, nil, stableKey
    end

    local channelNumber = tonumber(channelNumberArg)
    local rawChannelName = channelNameArg
    if not rawChannelName or rawChannelName == "" then
        rawChannelName = channelDisplayName
    end
    rawChannelName = tostring(rawChannelName or "")

    local channelKey = normalizeChannelName(rawChannelName)
    if not channelKey or channelKey == "" then
        channelKey = "CHANNEL"
    end

    return channelKey, channelNumber, rawChannelName
end

local function confidenceLabel(confidence)
    local c = tonumber(confidence or 0) or 0
    if c >= 0.70 then
        return "HIGH"
    end
    if c >= 0.30 then
        return "PARTIAL"
    end
    return "LOW"
end

local function normalizeEarlyText(text)
    text = tostring(text or ""):lower()
    text = text:gsub("[%p%c]", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("%s+", " ")
    return text
end

local function isLikelyGarbage(msg)
    local normalized = normalizeEarlyText(msg)
    if normalized == "" then
        return true
    end
    if string.len(normalized) > 220 then
        return true
    end
    return false
end

local function isDuplicateRecent(channel, sender, msg)
    local now = GetTime and GetTime() or 0
    local key = tostring(channel or "") .. "|" .. tostring(sender or "") .. "|" .. tostring(msg or "")
    local last = incomingRecent[key]
    incomingRecent[key] = now
    if last and (now - last) < 2.0 then
        return true
    end
    return false
end

local function isPublicChannelKey(channelKey)
    return channelKey == "TRADE"
        or channelKey == "GENERAL"
        or channelKey == "LOOKINGFORGROUP"
        or channelKey == "SERVICES"
        or channelKey == "LOCALDEFENSE"
        or channelKey == "WORLDDEFENSE"
        or channelKey == "GUILDRECRUITMENT"
        or channelKey == "CHANNEL"
end

local function countPattern(text, pattern)
    local n = 0
    for _ in string.gmatch(text or "", pattern) do
        n = n + 1
    end
    return n
end

local function hasLikelySpanishPublicContent(msg)
    local t = normalizeEarlyText(msg or "")
    if t == "" then return false end
    local strongPhrases = {
        "busco", "buscamos", "necesito", "necesitamos", "vendo", "compro", "invito",
        "grupo para", "para karazhan", "tanque para", "sanador para",
        "que pueda", "pueda", "raidear", "para mas info", "mas info",
        "busco guild", "hola me llamo", "me llamo", "reclutando", "hermandad",
        "jugadores", "bienvenidos", "horario", "servidor",
    }
    for _, p in ipairs(strongPhrases) do
        if string.find(" " .. t .. " ", " " .. p .. " ", 1, true) then
            return true
        end
    end

    -- Mixed Spanish recruitment phrasing often includes short Spanish bridges.
    local hasRecruitBridge =
        string.find(t, "que pueda", 1, true) or
        string.find(t, "para mas info", 1, true) or
        string.find(t, "martes jueves", 1, true) or
        string.find(t, "viernes", 1, true)
    if hasRecruitBridge then
        return true
    end

    local count = 0
    for token in string.gmatch(t, "%S+") do
        if isConfidentSpanishPublicToken and isConfidentSpanishPublicToken(token) then
            count = count + 1
        end
    end
    return count >= 2
end

local function isProtectedPublicToken(token)
    local t = tostring(token or "")
    if t == "" then return true end
    if string.find(t, "^|H") or string.find(t, "|H") then return true end
    if string.find(t, "^%[.*%]$") then return true end
    if string.find(string.lower(t), "http") or string.find(string.lower(t), "www%.") or string.find(string.lower(t), "discord") then return true end
    if string.find(t, "^<.*>$") then return true end
    return false
end

local function isCommonEnglishPublicToken(token)
    local t = normalizeEarlyText(token or "")
    local common = {
        what = true, is = true, gold = true, need = true, summon = true, black = true,
        temple = true, tonight = true, lf1m = true, pst = true, wts = true, wtb = true,
        guild = true, raid = true, healer = true, tank = true, lfm = true, lfg = true,
        rfk = true, shattrath = true,
    }
    return common[t] == true
end

local function isConfidentSpanishPublicToken(token)
    local t = normalizeEarlyText(token or "")
    if t == "" then return false end
    if t == "what" then return false end
    local confident = {
        que = true, para = true, con = true, sin = true, necesito = true, necesitamos = true,
        busca = true, busco = true, buscamos = true, tanque = true, sanador = true, curador = true,
        mazmorra = true, banda = true, hermandad = true, hoy = true, manana = true, ahora = true,
        oro = true, vendo = true, compro = true, invito = true, gracias = true, por = true,
        favor = true, alguien = true, viernes = true, sabado = true, domingo = true, martes = true,
        miercoles = true, jueves = true,
    }
    return confident[t] == true
end

local function translateSpanishSegmentsOnly(msg)
    local tokens = {}
    for token in string.gmatch(tostring(msg or ""), "%S+") do
        table.insert(tokens, token)
    end
    local out = {}
    local spanishCount = 0
    local protectedCount = 0
    local englishCommonCount = 0
    local strongPhraseHit = false
    local normalizedMsg = normalizeEarlyText(msg or "")
    local strongPhrases = {
        "busco", "buscamos", "necesito", "necesitamos", "vendo", "compro", "invito",
        "grupo para", "para karazhan", "tanque para", "sanador para",
    }
    for _, p in ipairs(strongPhrases) do
        if string.find(" " .. normalizedMsg .. " ", " " .. p .. " ", 1, true) then
            strongPhraseHit = true
            break
        end
    end

    for _, token in ipairs(tokens) do
        if isProtectedPublicToken(token) then
            table.insert(out, token)
            protectedCount = protectedCount + 1
        else
            local cleaned = normalizeEarlyText(token)
            if isCommonEnglishPublicToken(cleaned) then
                englishCommonCount = englishCommonCount + 1
                table.insert(out, token)
            elseif isConfidentSpanishPublicToken(cleaned) then
                local translated, info = translateDetailed(cleaned, true, true)
                if translated and info and tonumber(info.confidence or 0) >= 0.30 then
                    table.insert(out, "[" .. translated .. "]")
                    spanishCount = spanishCount + 1
                else
                    table.insert(out, token)
                end
            else
                table.insert(out, token)
            end
        end
    end

    if spanishCount < 2 and not strongPhraseHit then
        return nil, spanishCount, protectedCount, englishCommonCount
    end
    return table.concat(out, " "), spanishCount, protectedCount, englishCommonCount
end

local function shouldAutoScroll(frame)
    if not frame or not frame.GetCurrentScroll or not frame.GetMaxScroll then
        return true
    end
    return (frame:GetMaxScroll() - frame:GetCurrentScroll()) <= 20
end

local function formatTimestampPrefix()
    if KCxTranslatorDB.showTimestamps == false then
        return ""
    end
    return string.format("[%s] ", date("%H:%M"))
end

KCxTranslatorAddLine = function(message, category)
    if not translatorWindow then
        createTranslatorWindow()
    end
    if not translatorLog then
        return
    end

    local color = COLOR_WHITE
    local label = "[INFO]"
    if category == "success" then
        color = COLOR_GREEN
        label = "[EN -> ES]"
    elseif category == "debug" then
        color = COLOR_YELLOW
        label = "[DEBUG]"
    elseif category == "error" then
        color = COLOR_RED
        label = "[NO MATCH]"
    end

    local text = tostring(message or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")

    local body = text
    if category == "success" or category == "error" then
        body = text .. "\n\n|cff8a8a8a---|r"
    elseif category == "debug" then
        body = text .. "\n|cff8a8a8a---|r"
    end

    local line = color .. formatTimestampPrefix() .. label .. COLOR_RESET .. "\n" .. body
    local pinBottom = shouldAutoScroll(translatorLog)
    translatorLog:AddMessage(line)
    if pinBottom then
        translatorLog:ScrollToBottom()
    end
end

_G.KCxTranslatorAddLine = _G.KCxTranslatorAddLine or function(text, category)
    return KCxTranslatorAddLine(text, category)
end

local function KCxTranslatorPrint(message, isDebug)
    if isDebug and not debugMode then
        return
    end

    KCxTranslatorAddLine(tostring(message or ""), isDebug and "debug" or "info")
end

local function printSuccess(msg)
    local onlyTranslated = tostring(msg or "")
    local arrowPos = string.find(onlyTranslated, "-> ", 1, true)
    if arrowPos then
        onlyTranslated = string.sub(onlyTranslated, arrowPos + 3)
    end
    lastTranslatedText = onlyTranslated
    KCxTranslatorAddLine(msg, "success")
end

local function printError(msg)
    KCxTranslatorAddLine(msg, "error")
end

local function printInfo(msg)
    KCxTranslatorAddLine(msg, "info")
end

-- ----------------------------------------------------------------------------
-- Text normalization
-- ----------------------------------------------------------------------------
-- normalizeText(text)
-- Safely cleans incoming text so dictionary lookups are reliable.
-- Required behavior:
-- - handle nil
-- - lowercase
-- - trim surrounding spaces
-- - collapse repeated spaces
-- - remove punctuation while preserving letters (including Spanish accents)
local function normalizeText(text)
    if text == nil then
        return ""
    end

    -- Convert to string in case non-string data is passed.
    text = tostring(text)

    -- Lowercase for case-insensitive matching.
    text = string.lower(text)

    -- Remove punctuation-like symbols but keep letters/numbers/spaces.
    -- This keeps accented letters intact on UTF-8 clients by only stripping ASCII punctuation.
    text = string.gsub(text, "[%p%c]", " ")

    -- Collapse repeated whitespace to a single space.
    text = string.gsub(text, "%s+", " ")

    -- Trim leading and trailing spaces.
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")

    return text
end

-- ----------------------------------------------------------------------------
-- Translation database (local only, no internet)
-- ----------------------------------------------------------------------------
-- We keep one table with BOTH directions:
-- English -> Spanish and Spanish -> English.
-- This makes the addon useful for translating incoming and outgoing text.
local translationDB = {
    -- BASIC CHAT
    ["como esta"] = "how are you",
["como estas"] = "how are you",

["how are you"] = "como estas",

["que pasa"] = "whats up",
["whats up"] = "que pasa",

["buenas"] = "hello",
["buenos dias"] = "good morning",
["buenas noches"] = "good night",

["vamos"] = "lets go",
["vamanos"] = "lets go",

["listo?"] = "ready?",
["ready?"] = "listo?",

["gracias amigo"] = "thanks friend",
["thanks friend"] = "gracias amigo",
    ["hello"] = "hola",
    ["hola"] = "hello",
    ["hi"] = "hola",
    ["thanks"] = "gracias",
    ["thank you"] = "gracias",
    ["gracias"] = "thank you",
    ["youre welcome"] = "de nada",
    ["de nada"] = "you are welcome",
    ["sorry"] = "perdon",
    ["perdon"] = "sorry",
    ["please"] = "por favor",
    ["por favor"] = "please",
    ["yes"] = "si",
    ["si"] = "yes",
    ["no"] = "no",
    ["wait"] = "espera",
    ["espera"] = "wait",
    ["ready"] = "listo",
    ["listo"] = "ready",
    ["go"] = "vamos",
    ["vamos"] = "lets go",
    ["estas loco"] = "you are crazy",
    ["estas loco mi hombre"] = "you are crazy my man",
    ["mi hombre"] = "my man",
    ["como estas"] = "how are you",
    ["que haces"] = "what are you doing",
    ["follow"] = "sigue",
    ["sigue"] = "follow",
    ["help"] = "ayuda",
    ["ayuda"] = "help",
    ["i need help"] = "necesito ayuda",
    ["necesito ayuda"] = "i need help",
    ["good luck"] = "buena suerte",
    ["buena suerte"] = "good luck",
    ["have fun"] = "diviertete",
    ["diviertete"] = "have fun",
    ["brb"] = "vuelvo enseguida",
    ["afk"] = "ausente",
    ["nice"] = "bien",
    ["lol"] = "jaja",
    ["lolol"] = "jajaja",
    ["haha"] = "jaja",
    ["jaja"] = "haha",

    -- COMMON SPANISH / ENGLISH CONVERSATION
    ["que"] = "what",
    ["what"] = "que",
    ["quien"] = "who",
    ["who"] = "quien",
    ["cuando"] = "when",
    ["when"] = "cuando",
    ["donde"] = "where",
    ["where"] = "donde",
    ["porque"] = "why",
    ["why"] = "porque",
    ["because"] = "porque",
    ["como"] = "how",
    ["how"] = "como",
    ["cual"] = "which",
    ["which"] = "cual",
    ["aqui"] = "here",
    ["here"] = "aqui",
    ["alli"] = "there",
    ["there"] = "alli",
    ["ahora"] = "now",
    ["now"] = "ahora",
    ["luego"] = "later",
    ["later"] = "luego",
    ["hoy"] = "today",
    ["today"] = "hoy",
    ["manana"] = "tomorrow",
    ["tomorrow"] = "manana",
    ["ayer"] = "yesterday",
    ["yesterday"] = "ayer",
    ["necesito"] = "i need",
    ["i need"] = "necesito",
    ["quiero"] = "i want",
    ["i want"] = "quiero",
    ["tengo"] = "i have",
    ["i have"] = "tengo",
    ["tienes"] = "you have",
    ["you have"] = "tienes",
    ["for"] = "para",
    ["para"] = "for",
    ["puedo"] = "i can",
    ["i can"] = "puedo",
    ["puedes"] = "you can",
    ["you can"] = "puedes",
    ["ven"] = "come",
    ["come"] = "ven",
    ["sigue"] = "follow",
    ["espera"] = "wait",
    ["para"] = "stop",
    ["stop"] = "para",
    ["rapido"] = "fast",
    ["fast"] = "rapido",
    ["lento"] = "slow",
    ["slow"] = "lento",
    ["bueno"] = "good",
    ["good"] = "bueno",
    ["malo"] = "bad",
    ["bad"] = "malo",
    ["bien"] = "fine",
    ["fine"] = "bien",
    ["mal"] = "bad",
    ["mucho"] = "a lot",
    ["a lot"] = "mucho",
    ["poco"] = "little",
    ["little"] = "poco",
    ["uno"] = "one",
    ["one"] = "uno",
    ["dos"] = "two",
    ["two"] = "dos",
    ["tres"] = "three",
    ["three"] = "tres",
    ["todos"] = "everyone",
    ["everyone"] = "todos",
    ["alguien"] = "someone",
    ["someone"] = "alguien",
    ["nadie"] = "nobody",
    ["nobody"] = "nadie",
    ["yo"] = "i",
    ["i"] = "yo",
    ["tu"] = "you",
    ["you"] = "tu",
    ["el"] = "he",
    ["he"] = "el",
    ["ella"] = "she",
    ["she"] = "ella",
    ["nosotros"] = "we",
    ["we"] = "nosotros",
    ["ellos"] = "they",
    ["they"] = "ellos",
    ["mi"] = "my",
    ["my"] = "mi",
    ["tuyo"] = "yours",
    ["yours"] = "tuyo",
    ["enemigo"] = "enemy",
    ["enemy"] = "enemigo",
    ["enemigos"] = "enemies",
    ["enemies"] = "enemigos",
    ["curar"] = "heal",
    ["muerto"] = "dead",
    ["dead"] = "muerto",
    ["como estas"] = "how are you",
    ["how are you"] = "como estas",
    ["que onda"] = "whats up",
    ["whats up"] = "que onda",
    ["que haces"] = "what are you doing",
    ["what are you doing"] = "que haces",
    ["no entiendo"] = "i do not understand",
    ["i do not understand"] = "no entiendo",
    ["hablas ingles"] = "do you speak english",
    ["do you speak english"] = "hablas ingles",
    ["hablo poco espanol"] = "i speak a little spanish",
    ["i speak a little spanish"] = "hablo poco espanol",
    ["estoy usando traductor"] = "i am using a translator",
    ["i am using a translator"] = "estoy usando traductor",
    ["puedes repetir"] = "can you repeat",
    ["can you repeat"] = "puedes repetir",
    ["donde estas"] = "where are you",
    ["where are you"] = "donde estas",
    ["ven aqui"] = "come here",
    ["come here"] = "ven aqui",
    ["espera por favor"] = "wait please",
    ["wait please"] = "espera por favor",
    ["estoy listo"] = "i am ready",
    ["i am ready"] = "estoy listo",
    ["no tengo mana"] = "i have no mana",
    ["i have no mana"] = "no tengo mana",
    ["estoy muerto"] = "i am dead",
    ["i am dead"] = "estoy muerto",
    ["necesito curacion"] = "i need healing",
    ["i need healing"] = "necesito curacion",
    ["vamos a la mazmorra"] = "lets go to the dungeon",
    ["lets go to the dungeon"] = "vamos a la mazmorra",
    ["ok"] = "ok",
    ["vale"] = "ok",
    ["claro"] = "of course",
    ["of course"] = "claro",
    ["no se"] = "i dont know",
    ["i dont know"] = "no se",
    ["entiendo"] = "i understand",
    ["i understand"] = "entiendo",
    ["sin problema"] = "no problem",
    ["no problem"] = "sin problema",
    ["de nada"] = "you are welcome",
    ["you are welcome"] = "de nada",
    ["por que"] = "why",
    ["ahi"] = "there",
    ["izquierda"] = "left",
    ["left"] = "izquierda",
    ["derecha"] = "right",
    ["right"] = "derecha",
    ["arriba"] = "up",
    ["up"] = "arriba",
    ["abajo"] = "down",
    ["down"] = "abajo",
    ["despues"] = "after",
    ["after"] = "despues",
    ["antes"] = "before",
    ["before"] = "antes",
    ["siempre"] = "always",
    ["always"] = "siempre",
    ["nunca"] = "never",
    ["never"] = "nunca",
    ["mas"] = "more",
    ["more"] = "mas",
    ["menos"] = "less",
    ["less"] = "menos",
    ["grupo"] = "group",
    ["mazmorra"] = "dungeon",
    ["mision"] = "quest",
    ["jefe"] = "boss",
    ["tanque"] = "tank",
    ["sanador"] = "healer",
    ["vida"] = "health",
    ["health"] = "vida",
    ["listo"] = "ready",
    ["ready"] = "listo",
    ["gracias"] = "thanks",
    ["thanks"] = "gracias",
    ["perdon"] = "sorry",
    ["sorry"] = "perdon",

    -- GROUP / SOCIAL
    ["invite"] = "invita",
    ["invita"] = "invite",
    ["invite me"] = "invitame",
    ["invitame"] = "invite me",
    ["inv"] = "inv",
    ["group"] = "grupo",
    ["grupo"] = "group",
    ["party"] = "grupo",
    ["raid"] = "banda",
    ["banda"] = "raid",
    ["guild"] = "hermandad",
    ["hermandad"] = "guild",
    ["friend"] = "amigo",
    ["amigo"] = "friend",
    ["whisper"] = "susurro",
    ["susurro"] = "whisper",
    ["trade"] = "comercio",
    ["comercio"] = "trade",
    ["lf"] = "busco",
    ["busco"] = "looking for",
    ["lf1m"] = "falta 1",
    ["lf2m"] = "faltan 2",
    ["lf3m"] = "faltan 3",
    ["lfg"] = "busco grupo",
    ["busco grupo"] = "lfg",
    ["lfm"] = "busco mas",
    ["busco mas"] = "lfm",
    ["need tank"] = "necesitamos tanque",
    ["necesitamos tanque"] = "need tank",
    ["need healer"] = "necesitamos healer",
    ["necesitamos healer"] = "need healer",
    ["need dps"] = "necesitamos dps",
    ["necesitamos dps"] = "need dps",
    ["looking for"] = "buscando",
    ["buscando"] = "looking for",
    ["looking for more"] = "buscamos mas",
    ["buscamos mas"] = "looking for more",

    -- ROLES
    ["tank"] = "tanque",
    ["tanque"] = "tank",
    ["healer"] = "sanador",
    ["sanador"] = "healer",
    ["dps"] = "dps",
    ["damage"] = "danio",
    ["danio"] = "damage",
    ["melee"] = "mele",
    ["ranged"] = "a distancia",
    ["a distancia"] = "ranged",
    ["caster"] = "lanzador",
    ["lanzador"] = "caster",

    -- DUNGEON / RAID
    ["dungeon"] = "mazmorra",
    ["mazmorra"] = "dungeon",
    ["heroic"] = "heroico",
    ["heroico"] = "heroic",
    ["h"] = "heroico",
    ["hc"] = "heroico",
    ["boss"] = "jefe",
    ["jefe"] = "boss",
    ["trash"] = "basura",
    ["adds"] = "adds",
    ["mob"] = "mob",
    ["mobs"] = "mobs",
    ["pull"] = "pull",
    ["big pull"] = "pull grande",
    ["pull grande"] = "big pull",
    ["small pull"] = "pull pequeno",
    ["pull pequeno"] = "small pull",
    ["skip"] = "saltar",
    ["saltar"] = "skip",
    ["wipe"] = "wipe",
    ["reset"] = "reiniciar",
    ["reiniciar"] = "reset",
    ["loot"] = "botin",
    ["botin"] = "loot",
    ["roll"] = "tirar",
    ["tirar"] = "roll",
    ["need"] = "necesito",
    ["necesidad"] = "need",
    ["greed"] = "codicia",
    ["codicia"] = "greed",
    ["pass"] = "paso",
    ["paso"] = "pass",
    ["quest"] = "mision",
    ["mision"] = "quest",
    ["cc"] = "control",
    ["crowd control"] = "control de masas",
    ["control de masas"] = "crowd control",
    ["stack"] = "juntarse",
    ["juntarse"] = "stack",
    ["spread"] = "separarse",
    ["separarse"] = "spread",
    ["interrupt"] = "interrumpe",
    ["interrumpe"] = "interrupt",
    ["kick"] = "corta",
    ["corta"] = "kick",
    ["stun"] = "aturdir",
    ["aturdir"] = "stun",
    ["sheep"] = "oveja",
    ["polymorph"] = "polimorfia",
    ["polimorfia"] = "polymorph",
    ["fear"] = "miedo",
    ["miedo"] = "fear",
    ["dispel"] = "disipar",
    ["disipar"] = "dispel",
    ["cleanse"] = "limpiar",
    ["limpiar"] = "cleanse",
    ["heal"] = "cura",
    ["cura"] = "heal",
    ["resurrect"] = "resucitar",
    ["resucitar"] = "resurrect",
    ["rez"] = "rez",
    ["buff"] = "mejora",
    ["mejora"] = "buff",
    ["debuff"] = "perjuicio",
    ["perjuicio"] = "debuff",
    ["cooldown"] = "reutilizacion",
    ["reutilizacion"] = "cooldown",
    ["mana"] = "mana",
    ["oom"] = "sin mana",
    ["sin mana"] = "oom",
    ["hp"] = "vida",
    ["vida"] = "hp",
    ["low hp"] = "poca vida",
    ["poca vida"] = "low hp",
    ["aggro"] = "agro",
    ["agro"] = "aggro",
    ["threat"] = "amenaza",
    ["amenaza"] = "threat",
    ["ready check"] = "check listo",
    ["r"] = "listo",
    ["r?"] = "listo?",
    ["wrong chat"] = "chat equivocado",
    ["chat equivocado"] = "wrong chat",
    ["wc"] = "chat mundial",

    -- CLASSES
    ["mage"] = "mago",
    ["mago"] = "mage",
    ["priest"] = "sacerdote",
    ["sacerdote"] = "priest",
    ["warrior"] = "guerrero",
    ["guerrero"] = "warrior",
    ["paladin"] = "paladin",
    ["shaman"] = "chaman",
    ["chaman"] = "shaman",
    ["rogue"] = "picaro",
    ["picaro"] = "rogue",
    ["hunter"] = "cazador",
    ["cazador"] = "hunter",
    ["warlock"] = "brujo",
    ["brujo"] = "warlock",
    ["druid"] = "druida",
    ["druida"] = "druid",

    -- WORLD / TRAVEL
    ["mount"] = "montura",
    ["montura"] = "mount",
    ["hearth"] = "piedra hogar",
    ["hearthstone"] = "piedra hogar",
    ["piedra hogar"] = "hearthstone",
    ["flight path"] = "ruta de vuelo",
    ["ruta de vuelo"] = "flight path",
    ["vendor"] = "vendedor",
    ["vendedor"] = "vendor",
    ["repair"] = "reparar",
    ["reparar"] = "repair",
    ["bank"] = "banco",
    ["banco"] = "bank",
    ["auction house"] = "casa de subastas",
    ["casa de subastas"] = "auction house",
    ["ah"] = "cs",
    ["summon"] = "invocar",
    ["invocar"] = "summon",
    ["sum"] = "invoca",

    -- QUESTING
    ["where is the quest"] = "donde esta la mision",
    ["donde esta la mision"] = "where is the quest",
    ["where is quest"] = "donde esta la quest",
    ["turn in quest"] = "entregar mision",
    ["entregar mision"] = "turn in quest",
    ["accept quest"] = "aceptar mision",
    ["aceptar mision"] = "accept quest",
    ["share quest"] = "compartir mision",
    ["compartir mision"] = "share quest",
    ["kill mobs"] = "matar mobs",
    ["matar mobs"] = "kill mobs",
    ["collect items"] = "recolectar objetos",
    ["recolectar objetos"] = "collect items",
    ["escort"] = "escolta",
    ["escolta"] = "escort",

    -- PVP
    ["pvp"] = "pvp",
    ["battleground"] = "campo de batalla",
    ["campo de batalla"] = "battleground",
    ["arena"] = "arena",
    ["flag"] = "bandera",
    ["bandera"] = "flag",
    ["defend"] = "defender",
    ["defender"] = "defend",
    ["attack base"] = "atacar base",
    ["atacar base"] = "attack base",
    ["incoming"] = "inc",
    ["inc"] = "incoming",
    ["help base"] = "ayuda base",
    ["ayuda base"] = "help base",

    -- TRADE / ECONOMY
    ["buy"] = "comprar",
    ["comprar"] = "buy",
    ["sell"] = "vender",
    ["vender"] = "sell",
    ["price"] = "precio",
    ["precio"] = "price",
    ["gold"] = "oro",
    ["oro"] = "gold",
    ["cheap"] = "barato",
    ["barato"] = "cheap",
    ["expensive"] = "caro",
    ["caro"] = "expensive",
    ["wtb"] = "compro",
    ["compro"] = "wtb",
    ["wts"] = "vendo",
    ["vendo"] = "wts",
    ["wtt"] = "cambio",
    ["cambio"] = "wtt",
    ["mats"] = "materiales",
    ["materials"] = "materiales",
    ["materiales"] = "materials",
    ["pot"] = "pocion",
    ["potion"] = "pocion",
    ["pocion"] = "potion",
    ["flask"] = "frasco",
    ["frasco"] = "flask",
    ["boost"] = "boost",
    ["boosting"] = "boosteo",
    ["boosteo"] = "boosting",

    -- TBC CLASSIC TRADE / RAID TERMS
    ["gdkp"] = "gdkp",
    ["bis"] = "bis",
    ["best in slot"] = "mejor en ranura",
    ["mejor en ranura"] = "best in slot",
    ["rep"] = "reputacion",
    ["reputation"] = "reputacion",
    ["reputacion"] = "reputation",
    ["mongoose"] = "mongoose",
    ["enchant"] = "encantar",
    ["encantar"] = "enchant",
    ["enchanting"] = "encantamiento",
    ["encantamiento"] = "enchanting",
    ["enchanter"] = "encantador",
    ["encantador"] = "enchanter",
    ["jewelcrafting"] = "joyeria",
    ["joyeria"] = "jewelcrafting",
    ["jc"] = "jc",
    ["achievement"] = "logro",
    ["logro"] = "achievement",
    ["achiev"] = "logro",
    ["link achiev"] = "linkea logro",
    ["link achievement"] = "linkea logro",
    ["link curve"] = "linkea curve",
    ["ninja"] = "ninja",
    ["gz"] = "felicidades",
    ["gratz"] = "felicidades",
    ["congrats"] = "felicidades",
    ["felicidades"] = "grats",

    -- WOW SLANG / CASUAL TERMS
    ["noob"] = "noob",
    ["newbie"] = "novato",
    ["novato"] = "newbie",
    ["dude"] = "tipo",
    ["tipo"] = "dude",
    ["bro"] = "bro",
    ["mate"] = "amigo",
    ["m8"] = "amigo",
}

-- ----------------------------------------------------------------------------
-- Translation metadata and expansion helpers
-- ----------------------------------------------------------------------------
local translationMeta = {}
local buildLookupIndexes
local exactLookup = {}
local canonicalLookup = {}
local generalDictionaryDB = {}
local generalExactLookup = {}
local generalCanonicalLookup = {}
local stats = {
    specializedEntries = 0,
    generalEntries = 0,
    phraseEntries = 0,
    structuredEntries = 0,
    shorthandEntries = 0,
    socialEntries = 0,
    raidEntries = 0,
    pvpEntries = 0,
    generalSkippedOverrides = 0,
    generalLoadedStrings = 0,
    generalLoadedStructured = 0,
}

local contextKeywords = {
    trade = {
        "wtb", "wts", "wtt", "gold", "price", "precio", "sell", "buy", "auction",
        "ah", "mats", "mat", "materiales", "flask", "potion", "pot", "enchant",
        "jc", "jewelcrafting", "vendor", "bank", "cheap", "expensive", "boost"
    },
    combat = {
        "tank", "healer", "dps", "boss", "pull", "cc", "interrupt", "kick", "stun",
        "sheep", "fear", "dispel", "cleanse", "heal", "rez", "resurrect", "mana",
        "oom", "hp", "aggro", "threat", "heroic", "dungeon", "raid", "trash",
        "skip", "wipe", "reset", "ready", "buff", "debuff", "cooldown", "mob", "mobs"
    },
    pvp = {
        "pvp", "arena", "battleground", "flag", "inc", "incoming", "defend", "attack",
        "base", "mid", "left", "right", "yell", "focus", "rogue", "stealth"
    },
    social = {
        "hello", "hola", "thanks", "gracias", "sorry", "perdon", "bro", "dude",
        "friend", "amigo", "how", "what", "why", "where", "como", "que", "donde",
        "guild", "whisper", "help", "please", "por", "favor", "translator"
    },
}

local typoAliases = {
    ["q"] = "que",
    ["k"] = "que",
    ["xq"] = "porque",
    ["pq"] = "porque",
    ["porq"] = "porque",
    ["pls"] = "please",
    ["pls"] = "please",
    ["plz"] = "please",
    ["thx"] = "thanks",
    ["ty"] = "thank you",
    ["np"] = "no problem",
    ["u"] = "you",
    ["ur"] = "your",
    ["im"] = "i am",
    ["cant"] = "cannot",
    ["idk"] = "i dont know",
    ["bruh"] = "bro",
    ["hloa"] = "hola",
    ["graias"] = "gracias",
    ["grasias"] = "gracias",
    ["grasiaz"] = "gracias",
    ["ola"] = "hola",
    ["ke"] = "que",
    ["aki"] = "aqui",
    ["alli"] = "alli",
    ["xfa"] = "por favor",
    ["xfa"] = "por favor",
    ["invv"] = "inv",
    ["sumon"] = "summon",
    ["shatt"] = "shattrath",
    ["shat"] = "shattrath",
    ["heloer"] = "healer",
    ["heeler"] = "healer",
    ["tnak"] = "tank",
    ["hlr"] = "healer",
    ["heals"] = "healer",
}

local function addEntry(source, target, category, contexts)
    translationDB[source] = target
    translationMeta[source] = {
        category = category or "general",
        contexts = contexts or { "social" },
    }
end

local function addBidirectionalEntry(a, b, category, contexts)
    addEntry(a, b, category, contexts)
    addEntry(b, a, category, contexts)
end

KCxTranslator_RegisterDictionary = function(dict, name)
    if not dict then
        printError("Failed loading dictionary: " .. tostring(name))
        return
    end

    for source, entry in pairs(dict) do
        local target = entry
        local category = "general"
        local contexts = { "social" }

        if type(entry) == "table" then
            target = entry.target
            category = entry.category or category
            contexts = entry.contexts or contexts
        end

        if target then
            addEntry(source, target, category, contexts)
            stats.specializedEntries = stats.specializedEntries + 1
            if type(source) == "string" and string.find(source, " ", 1, true) then
                stats.phraseEntries = stats.phraseEntries + 1
            end
            if type(entry) == "table" then
                stats.structuredEntries = stats.structuredEntries + 1
            end
            if type(source) == "string" and string.len(source) <= 4 then
                stats.shorthandEntries = stats.shorthandEntries + 1
            end
            local lname = string.lower(tostring(name or ""))
            if lname == "social" then
                stats.socialEntries = stats.socialEntries + 1
            elseif lname == "raids" then
                stats.raidEntries = stats.raidEntries + 1
            elseif lname == "pvp" then
                stats.pvpEntries = stats.pvpEntries + 1
            end
        end
    end

    if buildLookupIndexes then
        buildLookupIndexes()
    end

    if debugMode then
        local count = 0
        for _ in pairs(dict) do
            count = count + 1
        end

        printInfo(
            "Loaded " ..
            tostring(count) ..
            " entries from " ..
            tostring(name)
        )
    end
end

local function normalizeGeneralLookupText(text)
    text = tostring(text or ""):lower()
    text = text:gsub("[%p%c]", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("%s+", " ")
    return text
end

KCxTranslator_RegisterGeneralDictionary = function(dict, name)
    if not dict then
        return
    end
    local processed = 0
    local loadedString = 0
    local loadedStructured = 0
    local skipped = 0

    for source, entry in pairs(dict) do
        processed = processed + 1
        local target = entry
        local sourceNormalized = normalizeGeneralLookupText(source)

        if type(entry) == "table" then
            target = entry.target
        end

        if target == nil or target == "" then
            skipped = skipped + 1
        elseif not exactLookup[normalizeText(source)] and not canonicalLookup[sourceNormalized] then
            generalDictionaryDB[source] = target
            if type(entry) == "table" then
                loadedStructured = loadedStructured + 1
                stats.generalLoadedStructured = stats.generalLoadedStructured + 1
            else
                loadedString = loadedString + 1
                stats.generalLoadedStrings = stats.generalLoadedStrings + 1
            end
        else
            skipped = skipped + 1
            stats.generalSkippedOverrides = stats.generalSkippedOverrides + 1
            if debugMode then
                printInfo("General skipped (specialized exists): " .. tostring(source))
            end
        end
    end

    generalExactLookup = {}
    generalCanonicalLookup = {}
    for source, target in pairs(generalDictionaryDB) do
        generalExactLookup[normalizeGeneralLookupText(source)] = target
        generalCanonicalLookup[normalizeGeneralLookupText(source)] = target
    end
    local gcount = 0
    for _ in pairs(generalDictionaryDB) do
        gcount = gcount + 1
    end
    stats.generalEntries = gcount
    if debugMode then
        printInfo("Loaded general dictionary: " .. tostring(name or "General"))
        printInfo("General stats processed=" .. tostring(processed) ..
            " strings=" .. tostring(loadedString) ..
            " structured=" .. tostring(loadedStructured) ..
            " skipped=" .. tostring(skipped))
        local verifyKeys = { "is", "now", "food", "for", "tonight", "incoming" }
        for _, key in ipairs(verifyKeys) do
            local n = normalizeGeneralLookupText(key)
            local exactHit = generalExactLookup[n] and "yes" or "no"
            local canonicalHit = generalCanonicalLookup[n] and "yes" or "no"
            printInfo("General verify '" .. key .. "' exact=" .. exactHit .. " canonical=" .. canonicalHit)
        end
    end
end

local function seedMetadata()
    for source in pairs(translationDB) do
        if not translationMeta[source] then
            translationMeta[source] = {
                category = "general",
                contexts = { "social" },
            }
        end
    end
end

local function addHighPriorityEntries()
    local entries = {
        { "summon pls", "invoca por favor", "group", { "combat", "social" } },
        { "inv pls", "invita por favor", "group", { "social" } },
        { "port to shatt", "portal a shattrath", "travel", { "social" } },
        { "port to shattrath", "portal a shattrath", "travel", { "social" } },
        { "shattrath", "shattrath", "travel", { "social" } },
        { "kara", "karazhan", "raid", { "combat" } },
        { "karazhan", "karazhan", "raid", { "combat" } },
        { "gruul", "gruul", "raid", { "combat" } },
        { "mag", "magtheridon", "raid", { "combat" } },
        { "magtheridon", "magtheridon", "raid", { "combat" } },
        { "ssc", "serpentshrine cavern", "raid", { "combat" } },
        { "serpentshrine cavern", "caverna santuario serpiente", "raid", { "combat" } },
        { "tk", "tempest keep", "raid", { "combat" } },
        { "tempest keep", "fortaleza de la tempestad", "raid", { "combat" } },
        { "hyjal", "hyjal", "raid", { "combat" } },
        { "black temple", "templo oscuro", "raid", { "combat" } },
        { "templo oscuro", "black temple", "raid", { "combat" } },
        { "za", "zul aman", "raid", { "combat" } },
        { "zul aman", "zul aman", "raid", { "combat" } },
        { "sunwell", "meseta de la fuente del sol", "raid", { "combat" } },
        { "heroism", "heroismo", "ability", { "combat" } },
        { "bloodlust", "ansia de sangre", "ability", { "combat" } },
        { "taunt", "provocar", "ability", { "combat" } },
        { "kick cast", "corta casteo", "ability", { "combat" } },
        { "line of sight", "linea de vision", "ability", { "combat", "pvp" } },
        { "los", "linea de vision", "ability", { "combat", "pvp" } },
        { "sap", "savia", "ability", { "combat", "pvp" } },
        { "trap", "trampa", "ability", { "combat", "pvp" } },
        { "banish", "desterrar", "ability", { "combat" } },
        { "curse", "maldicion", "ability", { "combat" } },
        { "totem", "totem", "ability", { "combat" } },
        { "shield wall", "muro de escudo", "ability", { "combat" } },
        { "bubble", "burbuja", "ability", { "combat", "pvp" } },
        { "divine shield", "escudo divino", "ability", { "combat" } },
        { "ice block", "bloque de hielo", "ability", { "combat" } },
        { "vanish", "desvanecerse", "ability", { "combat", "pvp" } },
        { "stealth", "sigilo", "ability", { "combat", "pvp" } },
        { "focus target", "objetivo foco", "combat", { "combat", "pvp" } },
        { "kill skull", "mata calavera", "combat", { "combat" } },
        { "sheep moon", "oveja luna", "combat", { "combat" } },
        { "trap square", "trampa cuadrado", "combat", { "combat" } },
        { "fear ward", "guardia de miedo", "ability", { "combat" } },
        { "soulstone", "piedra de alma", "ability", { "combat" } },
        { "healthstone", "piedra de salud", "ability", { "combat" } },
        { "battle rez", "resurreccion en combate", "ability", { "combat" } },
        { "innervate", "inervar", "ability", { "combat" } },
        { "misdirect", "redirigir", "ability", { "combat" } },
        { "evocate", "evocar", "ability", { "combat" } },
        { "drink", "beber", "combat", { "combat", "social" } },
        { "food", "comida", "combat", { "combat", "social" } },
        { "water", "agua", "combat", { "combat", "social" } },
        -- Mixed Spanish raid/trade phrase-first cleanup (longest chunk wins in phrase matcher).
        { "hola me llamo", "hello my name is", "social", { "social", "trade" } },
        { "me llamo", "my name is", "social", { "social", "trade" } },
        { "que pueda raidear", "who can raid", "raid", { "combat", "trade", "social" } },
        { "que pueda", "who can", "social", { "social", "trade" } },
        { "para mas info", "for more info", "trade", { "trade", "social" } },
        { "para más info", "for more info", "trade", { "trade", "social" } },
        { "los martes jueves y viernes", "tuesdays, thursdays, and fridays", "schedule", { "social", "trade" } },
        { "martes jueves y viernes", "tuesdays, thursdays, and fridays", "schedule", { "social", "trade" } },
        { "martes y jueves", "tuesdays and thursdays", "schedule", { "social", "trade" } },
        { "viernes", "friday", "schedule", { "social", "trade" } },
        { "reclutando", "recruiting", "trade", { "trade", "social" } },
        { "busca dps", "looking for dps", "trade", { "trade", "combat" } },
        { "busca", "looking for", "trade", { "trade", "social" } },
        -- Conversational/storytelling phrase-first coverage.
        { "traveled through", "viajaron por", "social", { "social" } },
        { "searching for", "buscando", "social", { "social", "trade" } },
        { "instead of", "en lugar de", "social", { "social" } },
        { "became allies", "se convirtieron en aliados", "social", { "social" } },
        { "offered peace", "ofrecieron paz", "social", { "social" } },
        { "dark forest", "bosque oscuro", "social", { "social" } },
        { "near a mountain", "cerca de una montana", "social", { "social" } },
        { "after many battles", "despues de muchas batallas", "social", { "social" } },
        { "sleeping near", "durmiendo cerca de", "social", { "social" } },
        { "found the dragon", "encontraron al dragon", "social", { "social" } },
        { "warrior and mage", "guerrero y mago", "social", { "social", "combat" } },
        { "they offered", "ofrecieron", "social", { "social" } },
        { "they became", "se convirtieron", "social", { "social" } },
        { "fighting", "peleando", "combat", { "combat", "social" } },
        { "peace", "paz", "social", { "social" } },
        { "dragon", "dragon", "social", { "social", "combat" } },
        { "forest", "bosque", "social", { "social" } },
        { "warrior", "guerrero", "combat", { "combat", "social" } },
        { "mage", "mago", "combat", { "combat", "social" } },
        { "allies", "aliados", "social", { "social", "combat" } },
        { "became", "se convirtio", "social", { "social" } },
        { "offered", "ofrecio", "social", { "social" } },
        { "guerrero y mago", "warrior and mage", "social", { "social", "combat" } },
        { "bosque oscuro", "dark forest", "social", { "social" } },
        { "buscando", "searching for", "social", { "social", "trade" } },
        { "peleando", "fighting", "combat", { "combat", "social" } },
        { "ofrecieron paz", "offered peace", "social", { "social" } },
        { "se convirtieron en aliados", "became allies", "social", { "social" } },
        { "viajaron por", "traveled through", "social", { "social" } },
        { "looking for group", "buscando grupo", "group", { "social", "trade" } },
        { "buscando grupo", "looking for group", "group", { "social", "trade" } },
        { "looking for more", "buscando mas", "group", { "social", "trade" } },
        { "buscando mas", "looking for more", "group", { "social", "trade" } },
        { "need healer", "necesito sanador", "group", { "social", "combat" } },
        { "necesito sanador", "need healer", "group", { "social", "combat" } },
        { "need tank", "necesito tanque", "group", { "social", "combat" } },
        { "necesito tanque", "need tank", "group", { "social", "combat" } },
        { "need dps", "necesito dps", "group", { "social", "combat" } },
        { "necesito dps", "need dps", "group", { "social", "combat" } },
        { "fast run", "carrera rapida", "group", { "social", "trade" } },
        { "carrera rapida", "fast run", "group", { "social", "trade" } },
        { "smooth run", "carrera fluida", "group", { "social", "trade" } },
        { "carrera fluida", "smooth run", "group", { "social", "trade" } },
        { "full clear", "limpieza completa", "group", { "social", "combat" } },
        { "limpieza completa", "full clear", "group", { "social", "combat" } },
        { "hard reserve", "reserva dura", "group", { "social", "trade" } },
        { "reserva dura", "hard reserve", "group", { "social", "trade" } },
        { "summon available", "summon disponible", "group", { "social", "trade" } },
        { "whisper me", "susurrame", "social", { "social" } },
        { "message me", "mandame mensaje", "social", { "social", "trade" } },
        { "join us", "unete", "social", { "social", "group" } },
        { "unete", "join us", "social", { "social", "group" } },
        { "good group", "buen grupo", "social", { "social", "group" } },
        { "good run", "buena carrera", "social", { "social", "group" } },
        { "after work", "despues del trabajo", "social", { "social" } },
        { "despues del trabajo", "after work", "social", { "social" } },
        { "see you tomorrow", "nos vemos manana", "social", { "social" } },
        { "nos vemos manana", "see you tomorrow", "social", { "social" } },
        { "lf tank", "buscando tanque", "group", { "social", "trade", "combat" } },
        { "buscando tanque", "looking for tank", "group", { "social", "trade", "combat" } },
        { "lf healer", "buscando sanador", "group", { "social", "trade", "combat" } },
        { "buscando sanador", "looking for healer", "group", { "social", "trade", "combat" } },
        { "lf dps", "buscando dps", "group", { "social", "trade", "combat" } },
        { "buscando dps", "looking for dps", "group", { "social", "trade", "combat" } },
        { "need summon", "necesito summon", "group", { "social", "trade" } },
        { "summon ready", "summon listo", "group", { "social", "trade" } },
        { "summon listo", "summon ready", "group", { "social", "trade" } },
        { "inv for group", "invita al grupo", "group", { "social", "trade" } },
        { "need attune", "necesito attune", "group", { "social", "trade" } },
        { "necesito attune", "need attune", "group", { "social", "trade" } },
        { "fresh run", "run fresco", "group", { "social", "trade" } },
        { "chill run", "run tranquilo", "group", { "social", "trade" } },
        { "run tranquilo", "chill run", "group", { "social", "trade" } },
        { "quick run", "run rapido", "group", { "social", "trade" } },
        { "run rapido", "quick run", "group", { "social", "trade" } },
        { "no wipe", "sin wipes", "group", { "social", "combat" } },
        { "sin wipes", "no wipe", "group", { "social", "combat" } },
        { "guild run", "run de guild", "group", { "social", "trade" } },
        { "farming rep", "farmeando reputacion", "trade", { "social", "trade" } },
        { "farmeando reputacion", "farming rep", "trade", { "social", "trade" } },
        { "grinding gold", "farmeando oro", "trade", { "social", "trade" } },
        { "farmeando oro", "grinding gold", "trade", { "social", "trade" } },
        { "doing quests", "haciendo quests", "social", { "social" } },
        { "haciendo quests", "doing quests", "social", { "social" } },
        { "looking for guild", "buscando guild", "social", { "social", "trade" } },
        { "buscando guild", "looking for guild", "social", { "social", "trade" } },
        { "casual guild", "guild casual", "social", { "social", "trade" } },
        { "guild casual", "casual guild", "social", { "social", "trade" } },
        { "raid tonight", "raid esta noche", "group", { "social", "combat" } },
        { "raid esta noche", "raid tonight", "group", { "social", "combat" } },
        { "healer needed", "sanador necesario", "group", { "social", "combat" } },
        { "tank needed", "tanque necesario", "group", { "social", "combat" } },
        { "dps needed", "dps necesario", "group", { "social", "combat" } },
        { "buff food", "comida de buf", "combat", { "combat" } },
        { "ready for pull", "listo para pull", "combat", { "combat" } },
        { "pulling now", "pull ahora", "combat", { "combat" } },
        { "big damage", "mucho dano", "combat", { "combat" } },
        { "watch threat", "cuidado con amenaza", "combat", { "combat" } },
        { "low mana wait", "poca mana espera", "combat", { "combat" } },
        { "need one more", "falta uno mas", "group", { "social" } },
        { "need two more", "faltan dos mas", "group", { "social" } },
        { "full group", "grupo completo", "group", { "social" } },
        { "on my way", "voy para alla", "social", { "social" } },
        { "im coming", "ya voy", "social", { "social" } },
        { "i am coming", "ya voy", "social", { "social" } },
        { "one minute", "un minuto", "social", { "social" } },
        { "five minutes", "cinco minutos", "social", { "social" } },
        { "5m", "cinco minutos", "social", { "social", "trade" } },
        { "5 more", "cinco mas", "social", { "social" } },
        { "sec", "segundo", "social", { "social" } },
        { "minute", "minuto", "social", { "social" } },
        { "minutes", "minutos", "social", { "social" } },
        { "seconds", "segundos", "social", { "social" } },
        { "all good brother", "todo bien hermano", "social", { "social" } },
        { "thanks for the run", "gracias por la run", "social", { "social" } },
        { "good people", "buena gente", "social", { "social" } },
        { "you are chill", "eres tranquilo", "social", { "social" } },
        { "you are funny", "eres gracioso", "social", { "social" } },
        { "that was close", "eso estuvo cerca", "social", { "combat", "social" } },
        { "nice save", "buena salvada", "social", { "combat", "social" } },
        { "my spanish is bad", "mi espanol es malo", "social", { "social" } },
        { "my english is bad", "mi ingles es malo", "social", { "social" } },
        { "can we do one more", "podemos hacer una mas", "social", { "social" } },
        { "brb bio", "vuelvo bano", "social", { "social" } },
        { "lag", "lag", "social", { "combat", "social", "pvp" } },
        { "dc", "desconectado", "social", { "combat", "social" } },
        { "disconnect", "desconexion", "social", { "combat", "social" } },
        { "craft", "fabricar", "trade", { "trade" } },
        { "crafted", "fabricado", "trade", { "trade" } },
        { "recipe", "receta", "trade", { "trade" } },
        { "pattern", "patron", "trade", { "trade" } },
        { "cooldown craft", "fabricacion con reutilizacion", "trade", { "trade" } },
        { "alchemist", "alquimista", "trade", { "trade" } },
        { "blacksmith", "herrero", "trade", { "trade" } },
        { "tailor", "sastre", "trade", { "trade" } },
        { "leatherworker", "peletero", "trade", { "trade" } },
        { "enchant mats", "materiales de encantamiento", "trade", { "trade" } },
        { "nether", "abisal", "trade", { "trade" } },
        { "primal", "primigenio", "trade", { "trade" } },
        { "gem", "gema", "trade", { "trade" } },
        { "socket", "ranura", "trade", { "trade" } },
        { "resilience", "temple", "pvp", { "pvp" } },
        { "graveyard", "cementerio", "pvp", { "pvp" } },
        { "farm", "granja", "pvp", { "pvp", "trade" } },
        { "stables", "establos", "pvp", { "pvp" } },
        { "blacksmith base", "base herreria", "pvp", { "pvp" } },
        { "incoming left", "inc izquierda", "pvp", { "pvp" } },
        { "incoming right", "inc derecha", "pvp", { "pvp" } },
        { "need help now", "necesito ayuda ahora", "pvp", { "pvp", "combat" } },

        -- KARAZHAN
        { "attumen", "attumen", "raid", { "combat" } },
        { "midnight", "midnight", "raid", { "combat" } },
        { "moroes", "moroes", "raid", { "combat" } },
        { "maiden", "doncella", "raid", { "combat" } },
        { "opera", "opera", "raid", { "combat" } },
        { "big bad wolf", "lobo feroz", "raid", { "combat" } },
        { "romulo and julianne", "romulo y julianne", "raid", { "combat" } },
        { "curator", "curador", "raid", { "combat" } },
        { "shade of aran", "sombra de aran", "raid", { "combat" } },
        { "chess event", "evento de ajedrez", "raid", { "combat" } },
        { "prince", "principe", "raid", { "combat" } },
        { "netherspite", "netherspite", "raid", { "combat" } },
        { "nightbane", "nightbane", "raid", { "combat" } },
        { "dont break sheep on moroes", "no rompan oveja en moroes", "raid", { "combat" } },
        { "decurse on maiden", "quita maldicion en doncella", "raid", { "combat" } },
        { "beam colors on netherspite", "colores de rayos en netherspite", "raid", { "combat" } },
        { "flame wreath dont move", "corona de llamas no se muevan", "raid", { "combat" } },
        { "enfeeble", "debilitar", "raid", { "combat" } },
        { "arcane missiles", "misiles arcanos", "raid", { "combat" } },
        { "skip to opera", "salta hasta opera", "raid", { "combat" } },
        { "clear to curator", "limpia hasta curador", "raid", { "combat" } },
        { "red beam", "rayo rojo", "raid", { "combat" } },
        { "blue beam", "rayo azul", "raid", { "combat" } },
        { "green beam", "rayo verde", "raid", { "combat" } },
        { "infernal on prince", "infernal en principe", "raid", { "combat" } },
        { "chains on maiden", "cadenas en doncella", "raid", { "combat" } },
        { "aoe on curator flares", "area para chispas del curador", "raid", { "combat" } },

        -- GRUUL / MAGTHERIDON
        { "gruul", "gruul", "raid", { "combat" } },
        { "shatter combo", "combo de despedazar", "raid", { "combat" } },
        { "move out for shatter", "sal para despedazar", "raid", { "combat" } },
        { "stack for shatter", "juntense para despedazar", "raid", { "combat" } },
        { "growth stacks", "acumulaciones de crecimiento", "raid", { "combat" } },
        { "ground slam", "golpe de suelo", "raid", { "combat" } },
        { "magtheridon", "magtheridon", "raid", { "combat" } },
        { "click cube", "clic en cubo", "raid", { "combat" } },
        { "channel cube", "canaliza cubo", "raid", { "combat" } },
        { "cube clickers", "clicadores de cubo", "raid", { "combat" } },
        { "warder", "guarda", "raid", { "combat" } },
        { "blast nova", "nova explosiva", "raid", { "combat" } },
        { "debris", "escombros", "raid", { "combat" } },

        -- SERPENTSHRINE CAVERN
        { "hydross", "hydross", "raid", { "combat" } },
        { "lurker", "acechador", "raid", { "combat" } },
        { "leotheras", "leotheras", "raid", { "combat" } },
        { "karathress", "karathress", "raid", { "combat" } },
        { "morogrim", "morogrim", "raid", { "combat" } },
        { "vashj", "vashj", "raid", { "combat" } },
        { "tainted core", "nucleo contaminado", "raid", { "combat" } },
        { "spore bat", "murcielago de esporas", "raid", { "combat" } },
        { "inner demon", "demonio interior", "raid", { "combat" } },
        { "whirlwind", "torbellino", "raid", { "combat" } },
        { "phase 2", "fase 2", "raid", { "combat" } },
        { "phase 3", "fase 3", "raid", { "combat" } },
        { "water tomb", "tumba de agua", "raid", { "combat" } },
        { "strider", "zancudo", "raid", { "combat" } },
        { "kite the strider", "kitea el zancudo", "raid", { "combat" } },
        { "core to the middle", "lleva el nucleo al centro", "raid", { "combat" } },

        -- TEMPEST KEEP
        { "alar", "alar", "raid", { "combat" } },
        { "void reaver", "atracador del vacio", "raid", { "combat" } },
        { "solarian", "solarian", "raid", { "combat" } },
        { "kaelthas", "kaelthas", "raid", { "combat" } },
        { "kael", "kael", "raid", { "combat" } },
        { "dive bomb", "bombardeo en picado", "raid", { "combat" } },
        { "flame patch", "parche de fuego", "raid", { "combat" } },
        { "pounding", "machaque", "raid", { "combat" } },
        { "bombs", "bombas", "raid", { "combat" } },
        { "arcane orb", "orbe arcano", "raid", { "combat" } },
        { "weapon phase", "fase de armas", "raid", { "combat" } },
        { "gravity lapse", "lapso gravitatorio", "raid", { "combat" } },
        { "advisor", "asesor", "raid", { "combat" } },
        { "move from arcane orb", "muevete del orbe arcano", "raid", { "combat" } },

        -- HYJAL / BLACK TEMPLE / ZA
        { "trash waves", "oleadas de basura", "raid", { "combat" } },
        { "wave count", "conteo de oleadas", "raid", { "combat" } },
        { "boss wave", "oleada de jefe", "raid", { "combat" } },
        { "ghouls", "necroros", "raid", { "combat" } },
        { "abominations", "abominaciones", "raid", { "combat" } },
        { "gargoyles", "gargolas", "raid", { "combat" } },
        { "frost wyrm", "verme de escarcha", "raid", { "combat" } },
        { "najentus", "najentus", "raid", { "combat" } },
        { "supremus", "supremus", "raid", { "combat" } },
        { "akama", "akama", "raid", { "combat" } },
        { "teron", "teron", "raid", { "combat" } },
        { "gurtogg", "gurtogg", "raid", { "combat" } },
        { "reliquary", "relicario", "raid", { "combat" } },
        { "mother", "madre", "raid", { "combat" } },
        { "illidari council", "consejo illidari", "raid", { "combat" } },
        { "illidan", "illidan", "raid", { "combat" } },
        { "glaive catch", "agarra guja", "raid", { "combat" } },
        { "fire wall", "muro de fuego", "raid", { "combat" } },
        { "construct", "constructo", "raid", { "combat" } },
        { "shield phase", "fase de escudo", "raid", { "combat" } },
        { "tank phase", "fase de tanque", "raid", { "combat" } },
        { "demon phase", "fase demonio", "raid", { "combat" } },
        { "bear timer", "tiempo del oso", "raid", { "combat" } },
        { "eagle timer", "tiempo del aguila", "raid", { "combat" } },
        { "lynx timer", "tiempo del lince", "raid", { "combat" } },
        { "dragonhawk timer", "tiempo del halcon dragon", "raid", { "combat" } },
        { "gong", "gong", "raid", { "combat" } },
        { "chest", "cofre", "raid", { "combat", "trade" } },
        { "mount run", "run de montura", "raid", { "combat", "social" } },
        { "amani war bear", "oso de guerra amani", "raid", { "combat" } },

        -- HEROIC DUNGEONS / LOCATIONS
        { "shattered halls gauntlet", "guantelete de salones destrozados", "dungeon", { "combat" } },
        { "shadow labyrinth ambassador", "embajador de laberinto de las sombras", "dungeon", { "combat" } },
        { "arcatraz third boss fears", "el tercer jefe de arcatraz hace miedos", "dungeon", { "combat" } },
        { "sethekk halls", "salas sethekk", "dungeon", { "combat" } },
        { "shadow lab", "laberinto de las sombras", "dungeon", { "combat" } },
        { "steamvault", "camara de vapor", "dungeon", { "combat" } },
        { "slave pens", "recinto de los esclavos", "dungeon", { "combat" } },
        { "underbog", "sotano", "dungeon", { "combat" } },
        { "ramps", "murallas", "dungeon", { "combat" } },
        { "blood furnace", "horno de sangre", "dungeon", { "combat" } },
        { "shattered halls", "salones destrozados", "dungeon", { "combat" } },
        { "mana tombs", "tumbas de mana", "dungeon", { "combat" } },
        { "auchenai crypts", "criptas auchenai", "dungeon", { "combat" } },
        { "old hillsbrad", "viejas laderas de trabajomas", "dungeon", { "combat" } },
        { "black morass", "cienaga negra", "dungeon", { "combat" } },
        { "mechanar", "mecanar", "dungeon", { "combat" } },
        { "botanica", "botanica", "dungeon", { "combat" } },
        { "arcatraz", "arcatraz", "dungeon", { "combat" } },

        -- PALADIN
        { "seal of blood", "sello de sangre", "ability", { "combat" } },
        { "seal of vengeance", "sello de venganza", "ability", { "combat" } },
        { "blessing of kings", "bendicion de reyes", "ability", { "combat", "social" } },
        { "blessing of wisdom", "bendicion de sabiduria", "ability", { "combat" } },
        { "blessing of might", "bendicion de poderio", "ability", { "combat" } },
        { "blessing of salvation", "bendicion de salvacion", "ability", { "combat" } },
        { "judge wisdom", "juzga sabiduria", "ability", { "combat" } },
        { "judge light", "juzga luz", "ability", { "combat" } },
        { "crusader strike", "golpe de cruzado", "ability", { "combat" } },
        { "consecration", "consagracion", "ability", { "combat" } },
        { "exorcism", "exorcismo", "ability", { "combat" } },
        { "hammer of wrath", "martillo de colera", "ability", { "combat" } },
        { "salv tank", "salvacion al tanque", "ability", { "combat" } },
        { "freedom", "libertad", "ability", { "combat", "pvp" } },
        { "bubble wall", "burbuja muro", "ability", { "combat", "pvp" } },
        { "lay on hands", "imposicion de manos", "ability", { "combat" } },
        { "divine intervention", "intervencion divina", "ability", { "combat" } },

        -- WARRIOR
        { "mortal strike", "golpe mortal", "ability", { "combat", "pvp" } },
        { "bloodthirst", "sed de sangre", "ability", { "combat" } },
        { "execute", "ejecutar", "ability", { "combat" } },
        { "shield slam", "embate con escudo", "ability", { "combat" } },
        { "devastate", "devastar", "ability", { "combat" } },
        { "sunder armor", "hender armadura", "ability", { "combat" } },
        { "battle shout", "grito de batalla", "ability", { "combat" } },
        { "commanding shout", "grito de orden", "ability", { "combat" } },
        { "demo shout", "grito desmoralizador", "ability", { "combat" } },
        { "last stand up", "ultima resistencia activa", "ability", { "combat" } },
        { "shield wall ready", "muro de escudo listo", "ability", { "combat" } },
        { "spell reflect", "reflejo de hechizos", "ability", { "combat", "pvp" } },
        { "disarm", "desarmar", "ability", { "combat", "pvp" } },

        -- MAGE / PRIEST
        { "frostbolt", "descarga de escarcha", "ability", { "combat" } },
        { "fireball", "bola de fuego", "ability", { "combat" } },
        { "scorch", "agostar", "ability", { "combat" } },
        { "remove curse", "eliminar maldicion", "ability", { "combat" } },
        { "poly sheep", "poli oveja", "ability", { "combat" } },
        { "poly pig", "poli cerdo", "ability", { "combat" } },
        { "sheep break", "se rompio oveja", "ability", { "combat" } },
        { "dont break poly", "no rompan poli", "ability", { "combat" } },
        { "ai buff", "buf de intelecto arcano", "ability", { "combat", "social" } },
        { "int buff", "buf de intelecto", "ability", { "combat" } },
        { "table", "mesa", "ability", { "combat", "social" } },
        { "portal", "portal", "ability", { "combat", "social" } },
        { "slow fall", "caida lenta", "ability", { "combat", "social" } },
        { "power infusion", "infusion de poder", "ability", { "combat" } },
        { "pain suppression", "supresion de dolor", "ability", { "combat" } },
        { "mana burn", "quemadura de mana", "ability", { "combat", "pvp" } },
        { "circle of healing", "circulo de sanacion", "ability", { "combat" } },
        { "prayer of mending", "rezo de alivio", "ability", { "combat" } },
        { "prayer of healing", "rezo de sanacion", "ability", { "combat" } },
        { "renew", "renovar", "ability", { "combat" } },
        { "flash heal", "sanacion relampago", "ability", { "combat" } },
        { "greater heal", "sanacion superior", "ability", { "combat" } },
        { "mind blast", "estallido mental", "ability", { "combat", "pvp" } },
        { "mind flay", "azote mental", "ability", { "combat", "pvp" } },
        { "shadow word pain", "palabra de las sombras dolor", "ability", { "combat", "pvp" } },
        { "vampiric embrace", "abrazo vampirico", "ability", { "combat" } },
        { "vampiric touch", "toque vampirico", "ability", { "combat" } },
        { "fort buff", "buf de entereza", "ability", { "combat", "social" } },
        { "spirit buff", "buf de espiritu", "ability", { "combat" } },
        { "shadow protection", "proteccion de sombras", "ability", { "combat" } },
        { "shackle", "encadenar", "ability", { "combat" } },
        { "mass dispel", "disipacion en masa", "ability", { "combat", "pvp" } },

        -- WARLOCK / SHAMAN
        { "shadow bolt", "descarga de las sombras", "ability", { "combat" } },
        { "incinerate", "incinerar", "ability", { "combat" } },
        { "immolate", "inmolar", "ability", { "combat" } },
        { "corruption", "corrupcion", "ability", { "combat" } },
        { "curse of agony", "maldicion de agonia", "ability", { "combat" } },
        { "curse of elements", "maldicion de los elementos", "ability", { "combat" } },
        { "curse of doom", "maldicion del apocalipsis", "ability", { "combat" } },
        { "felguard", "guardia vil", "ability", { "combat" } },
        { "succubus", "succubo", "ability", { "combat" } },
        { "felhunter spell lock", "manafago bloqueo de hechizo", "ability", { "combat", "pvp" } },
        { "imp blood pact", "diablillo pacto de sangre", "ability", { "combat" } },
        { "soulstone on healer", "piedra de alma al healer", "ability", { "combat" } },
        { "howl of terror", "aullido de terror", "ability", { "combat", "pvp" } },
        { "seed of corruption", "semilla de corrupcion", "ability", { "combat" } },
        { "windfury totem", "totem viento furioso", "ability", { "combat" } },
        { "wrath of air", "ira del aire", "ability", { "combat" } },
        { "mana spring", "marea de mana", "ability", { "combat" } },
        { "healing stream", "corriente de sanacion", "ability", { "combat" } },
        { "earthbind", "nexo terrestre", "ability", { "combat", "pvp" } },
        { "tremor", "temblor", "ability", { "combat", "pvp" } },
        { "grounding", "capacitador", "ability", { "combat", "pvp" } },
        { "poison cleansing", "limpieza de veneno", "ability", { "combat" } },
        { "disease cleansing", "limpieza de enfermedad", "ability", { "combat" } },
        { "chain heal", "sanacion en cadena", "ability", { "combat" } },
        { "healing wave", "ola de sanacion", "ability", { "combat" } },
        { "lesser healing wave", "ola de sanacion inferior", "ability", { "combat" } },
        { "earth shield", "escudo de tierra", "ability", { "combat" } },
        { "lightning bolt", "descarga de relampagos", "ability", { "combat" } },
        { "chain lightning", "cadena de relampagos", "ability", { "combat" } },
        { "shock", "choque", "ability", { "combat", "pvp" } },
        { "stormstrike", "golpe de tormenta", "ability", { "combat" } },
        { "purge", "purga", "ability", { "combat", "pvp" } },

        -- HUNTER / ROGUE / DRUID
        { "steady shot", "disparo firme", "ability", { "combat" } },
        { "multi shot", "disparo multiple", "ability", { "combat" } },
        { "aimed shot", "disparo de punteria", "ability", { "combat", "pvp" } },
        { "serpent sting", "picadura de serpiente", "ability", { "combat" } },
        { "viper sting", "picadura de vibora", "ability", { "combat", "pvp" } },
        { "frost trap", "trampa de escarcha", "ability", { "combat", "pvp" } },
        { "freezing trap", "trampa congelante", "ability", { "combat", "pvp" } },
        { "explosive trap", "trampa explosiva", "ability", { "combat" } },
        { "snake trap", "trampa de serpientes", "ability", { "combat", "pvp" } },
        { "aspect of the viper", "aspecto de la vibora", "ability", { "combat" } },
        { "aspect of the hawk", "aspecto del halcon", "ability", { "combat" } },
        { "tranq shot", "disparo tranquilizante", "ability", { "combat" } },
        { "pet attack", "mascota ataca", "ability", { "combat" } },
        { "pet follow", "mascota sigue", "ability", { "combat" } },
        { "pet passive", "mascota pasiva", "ability", { "combat" } },
        { "pet growl on", "gruñido de mascota activado", "ability", { "combat" } },
        { "pet growl off", "gruñido de mascota desactivado", "ability", { "combat" } },
        { "sinister strike", "golpe siniestro", "ability", { "combat" } },
        { "backstab", "apuñalar", "ability", { "combat", "pvp" } },
        { "hemorrhage", "hemorragia", "ability", { "combat", "pvp" } },
        { "mutilate", "mutilar", "ability", { "combat", "pvp" } },
        { "eviscerate", "eviscerar", "ability", { "combat", "pvp" } },
        { "rupture", "ruptura", "ability", { "combat", "pvp" } },
        { "sap skull", "sap a calavera", "ability", { "combat" } },
        { "sap square", "sap a cuadrado", "ability", { "combat" } },
        { "kidney shot", "golpe de rinon", "ability", { "combat", "pvp" } },
        { "blind", "ceguera", "ability", { "combat", "pvp" } },
        { "cloak of shadows", "capa de las sombras", "ability", { "combat", "pvp" } },
        { "evasion", "evasion", "ability", { "combat", "pvp" } },
        { "sprint", "esprintar", "ability", { "combat", "pvp" } },
        { "expose armor", "exponer armadura", "ability", { "combat" } },
        { "slice and dice", "hacer picadillo", "ability", { "combat" } },
        { "adrenaline rush", "subidon de adrenalina", "ability", { "combat" } },
        { "mangle", "magullar", "ability", { "combat" } },
        { "shred", "despedazar", "ability", { "combat" } },
        { "rip", "desgarrar", "ability", { "combat" } },
        { "ferocious bite", "mordedura feroz", "ability", { "combat" } },
        { "maul", "magullar oso", "ability", { "combat" } },
        { "swipe", "flagelo", "ability", { "combat" } },
        { "faerie fire", "fuego feerico", "ability", { "combat" } },
        { "demoralizing roar", "rugido desmoralizador", "ability", { "combat" } },
        { "starfire", "fuego estelar", "ability", { "combat" } },
        { "wrath", "colera", "ability", { "combat" } },
        { "moonfire", "fuego lunar", "ability", { "combat" } },
        { "insect swarm", "enjambre de insectos", "ability", { "combat" } },
        { "hurricane", "huracan", "ability", { "combat" } },
        { "rejuvenation", "rejuvenecimiento", "ability", { "combat" } },
        { "regrowth", "recrecimiento", "ability", { "combat" } },
        { "healing touch", "toque de sanacion", "ability", { "combat" } },
        { "lifebloom", "flor de vida", "ability", { "combat" } },
        { "swiftmend", "alivio presto", "ability", { "combat" } },
        { "tranquility", "tranquilidad", "ability", { "combat" } },
        { "roots", "raices", "ability", { "combat", "pvp" } },
        { "cyclone", "ciclon", "ability", { "combat", "pvp" } },
        { "feral charge", "carga feral", "ability", { "combat", "pvp" } },
        { "bear form", "forma de oso", "ability", { "combat" } },
        { "cat form", "forma felina", "ability", { "combat" } },
        { "travel form", "forma de viaje", "ability", { "combat", "social" } },
        { "flight form", "forma de vuelo", "ability", { "combat", "social" } },
        { "moonkin form", "forma de lechucico lunar", "ability", { "combat" } },
        { "tree form", "forma de arbol", "ability", { "combat" } },

        -- RAID COORDINATION / LOOT / CONSUMABLES
        { "dkp bid", "puja dkp", "trade", { "trade", "social" } },
        { "ep gp", "ep gp", "trade", { "trade", "social" } },
        { "loot council", "consejo de botin", "trade", { "trade", "social" } },
        { "main spec", "especializacion principal", "trade", { "trade" } },
        { "off spec", "especializacion secundaria", "trade", { "trade" } },
        { "tier token", "token de tier", "trade", { "trade" } },
        { "pattern drop", "drop de patron", "trade", { "trade" } },
        { "reserved", "reservado", "trade", { "trade" } },
        { "soft reserve", "reserva suave", "trade", { "trade" } },
        { "hard reserve", "reserva dura", "trade", { "trade" } },
        { "master loot", "botin de maestro", "trade", { "trade" } },
        { "group loot", "botin de grupo", "trade", { "trade" } },
        { "main tank", "tanque principal", "combat", { "combat" } },
        { "off tank", "tanque secundario", "combat", { "combat" } },
        { "tank swap", "cambio de tanque", "combat", { "combat" } },
        { "melee group", "grupo melee", "combat", { "combat" } },
        { "ranged group", "grupo rango", "combat", { "combat" } },
        { "healer assignments", "asignaciones de healers", "combat", { "combat" } },
        { "shadow priest group", "grupo de priest sombras", "combat", { "combat" } },
        { "shaman group", "grupo de shaman", "combat", { "combat" } },
        { "paladin group", "grupo de paladin", "combat", { "combat" } },
        { "mark of the wild", "marca de lo salvaje", "ability", { "combat" } },
        { "gift of the wild", "don de lo salvaje", "ability", { "combat" } },
        { "arcane brilliance", "luminosidad arcana", "ability", { "combat" } },
        { "divine spirit", "espiritu divino", "ability", { "combat" } },
        { "prayer of fortitude", "rezo de entereza", "ability", { "combat" } },
        { "blessing rotation", "rotacion de bendiciones", "combat", { "combat" } },
        { "pally power", "pally power", "combat", { "combat" } },
        { "flask of blinding light", "frasco de luz cegadora", "trade", { "trade", "combat" } },
        { "flask of mighty restoration", "frasco de restauracion poderosa", "trade", { "trade", "combat" } },
        { "flask of relentless assault", "frasco de asalto implacable", "trade", { "trade", "combat" } },
        { "elixir of major agility", "elixir de agilidad sublime", "trade", { "trade", "combat" } },
        { "adepts elixir", "elixir del adepto", "trade", { "trade", "combat" } },
        { "elixir of draenic wisdom", "elixir de sabiduria draenica", "trade", { "trade", "combat" } },
        { "fishermans feast", "festin de pescador", "trade", { "trade", "combat" } },
        { "blackened sporefish", "esporapez ennegrecido", "trade", { "trade", "combat" } },
        { "golden fish sticks", "palitos de pescado dorado", "trade", { "trade", "combat" } },
        { "scroll of agility", "pergamino de agilidad", "trade", { "trade" } },
        { "scroll of strength", "pergamino de fuerza", "trade", { "trade" } },
        { "scroll of protection", "pergamino de proteccion", "trade", { "trade" } },
        { "spread 10 yards", "separense 10 yardas", "combat", { "combat", "pvp" } },
        { "stack tight", "juntense cerrados", "combat", { "combat" } },
        { "ranged spread", "rango separados", "combat", { "combat" } },
        { "melee collapse", "melees al centro", "combat", { "combat" } },
        { "move to marker", "muevanse al marcador", "combat", { "combat" } },
        { "skull marker", "marcador calavera", "combat", { "combat" } },
        { "moon marker", "marcador luna", "combat", { "combat" } },
        { "square marker", "marcador cuadrado", "combat", { "combat" } },
        { "triangle marker", "marcador triangulo", "combat", { "combat" } },
        { "left platform", "plataforma izquierda", "combat", { "combat", "pvp" } },
        { "right platform", "plataforma derecha", "combat", { "combat", "pvp" } },
        { "center", "centro", "combat", { "combat", "pvp" } },
        { "north", "norte", "combat", { "combat", "pvp" } },
        { "south", "sur", "combat", { "combat", "pvp" } },
        { "east", "este", "combat", { "combat", "pvp" } },
        { "west", "oeste", "combat", { "combat", "pvp" } },

        -- BATTLEGROUNDS / ARENA
        { "grab flag", "agarra bandera", "pvp", { "pvp" } },
        { "flag carrier", "portador de bandera", "pvp", { "pvp" } },
        { "fc", "portador de bandera", "pvp", { "pvp" } },
        { "return flag", "devuelve bandera", "pvp", { "pvp" } },
        { "mid control", "control de medio", "pvp", { "pvp" } },
        { "roof", "techo", "pvp", { "pvp" } },
        { "tunnel", "tunel", "pvp", { "pvp" } },
        { "gy", "cementerio", "pvp", { "pvp" } },
        { "efc", "portador enemigo de la bandera", "pvp", { "pvp" } },
        { "our fc", "nuestro portador de bandera", "pvp", { "pvp" } },
        { "protect fc", "protejan al portador", "pvp", { "pvp" } },
        { "kill efc", "maten al portador enemigo", "pvp", { "pvp" } },
        { "st", "establos", "pvp", { "pvp" } },
        { "blacksmith", "herreria", "pvp", { "pvp" } },
        { "bs", "herreria", "pvp", { "pvp" } },
        { "lumber mill", "aserradero", "pvp", { "pvp" } },
        { "lm", "aserradero", "pvp", { "pvp" } },
        { "gold mine", "mina de oro", "pvp", { "pvp" } },
        { "gm", "mina de oro", "pvp", { "pvp" } },
        { "fm", "granja", "pvp", { "pvp" } },
        { "3 cap win", "con 3 bases ganamos", "pvp", { "pvp" } },
        { "4 cap", "4 bases", "pvp", { "pvp" } },
        { "5 cap", "5 bases", "pvp", { "pvp" } },
        { "need 3 bases", "necesitamos 3 bases", "pvp", { "pvp" } },
        { "defend farm", "defiendan granja", "pvp", { "pvp" } },
        { "attack bs", "ataquen herreria", "pvp", { "pvp" } },
        { "cap tower", "capturen torre", "pvp", { "pvp" } },
        { "burn tower", "quemen torre", "pvp", { "pvp" } },
        { "defend gy", "defiendan cementerio", "pvp", { "pvp" } },
        { "take gy", "tomen cementerio", "pvp", { "pvp" } },
        { "galv", "galv", "pvp", { "pvp" } },
        { "balinda", "balinda", "pvp", { "pvp" } },
        { "drek", "drek", "pvp", { "pvp" } },
        { "vann", "vann", "pvp", { "pvp" } },
        { "lok", "lok", "pvp", { "pvp" } },
        { "ivus", "ivus", "pvp", { "pvp" } },
        { "ram", "carnero", "pvp", { "pvp" } },
        { "wolf", "lobo", "pvp", { "pvp" } },
        { "mine", "mina", "pvp", { "pvp", "trade" } },
        { "scraps", "sobras", "pvp", { "pvp" } },
        { "blood", "sangre", "pvp", { "pvp" } },
        { "armor", "armadura", "pvp", { "pvp", "trade" } },
        { "defend draenei", "defiendan draenei", "pvp", { "pvp" } },
        { "defend fel reaver", "defiendan atracador vil", "pvp", { "pvp" } },
        { "defend mage tower", "defiendan torre de magos", "pvp", { "pvp" } },
        { "defend blood elf", "defiendan sangre elfo", "pvp", { "pvp" } },
        { "pillar", "columna", "pvp", { "pvp" } },
        { "reset", "reinicia", "pvp", { "pvp", "combat" } },
        { "go healer", "vayan healer", "pvp", { "pvp" } },
        { "go dps", "vayan dps", "pvp", { "pvp" } },
        { "cc healer", "cc al healer", "pvp", { "pvp" } },
        { "rmp", "rmp", "pvp", { "pvp" } },
        { "rld", "rld", "pvp", { "pvp" } },
        { "cleave", "cleave", "pvp", { "pvp" } },
        { "melee cleave", "cleave melee", "pvp", { "pvp" } },

        -- PROFESSIONS / MATERIALS / ZONES
        { "mining", "mineria", "trade", { "trade" } },
        { "herbalism", "herboristeria", "trade", { "trade" } },
        { "skinning", "desuello", "trade", { "trade" } },
        { "alchemy", "alquimia", "trade", { "trade" } },
        { "blacksmithing", "herreria", "trade", { "trade" } },
        { "engineering", "ingenieria", "trade", { "trade" } },
        { "enchanting", "encantamiento", "trade", { "trade" } },
        { "tailoring", "sastreria", "trade", { "trade" } },
        { "leatherworking", "peleteria", "trade", { "trade" } },
        { "jewelcrafting", "joyeria", "trade", { "trade" } },
        { "375 skill", "375 de habilidad", "trade", { "trade" } },
        { "max profession", "profesion al maximo", "trade", { "trade" } },
        { "leveling profession", "subiendo profesion", "trade", { "trade" } },
        { "mongoose", "mangosta", "trade", { "trade" } },
        { "spellstrike", "golpehechizo", "trade", { "trade" } },
        { "spellfire", "fuego de hechizo", "trade", { "trade" } },
        { "shadoweave", "tejido de sombras", "trade", { "trade" } },
        { "primal mooncloth", "tela lunar primigenia", "trade", { "trade" } },
        { "frozen shadoweave", "tejido de sombras congelado", "trade", { "trade" } },
        { "imbued netherweave", "tejido abisal imbuido", "trade", { "trade" } },
        { "netherweave bag", "bolsa de tejido abisal", "trade", { "trade" } },
        { "fel iron", "hierro vil", "trade", { "trade" } },
        { "adamantite", "adamantita", "trade", { "trade" } },
        { "khorium", "korio", "trade", { "trade" } },
        { "eternium", "eternium", "trade", { "trade" } },
        { "felsteel", "acero vil", "trade", { "trade" } },
        { "felweed", "hierba vil", "trade", { "trade" } },
        { "dreaming glory", "gloria onirica", "trade", { "trade" } },
        { "terocone", "teropiña", "trade", { "trade" } },
        { "ragveil", "velada", "trade", { "trade" } },
        { "flame cap", "seta flamigera", "trade", { "trade" } },
        { "nightmare vine", "vid pesadilla", "trade", { "trade" } },
        { "netherbloom", "flor abisal", "trade", { "trade" } },
        { "mana thistle", "cardo de mana", "trade", { "trade" } },
        { "primal fire", "fuego primigenio", "trade", { "trade" } },
        { "primal water", "agua primigenia", "trade", { "trade" } },
        { "primal earth", "tierra primigenia", "trade", { "trade" } },
        { "primal air", "aire primigenio", "trade", { "trade" } },
        { "primal shadow", "sombra primigenia", "trade", { "trade" } },
        { "primal life", "vida primigenia", "trade", { "trade" } },
        { "primal mana", "mana primigenio", "trade", { "trade" } },
        { "motes to primals", "motas a primigenios", "trade", { "trade" } },
        { "spellstrike hood", "capucha de golpehechizo", "trade", { "trade" } },
        { "frozen shadoweave shoulders", "hombreras de tejido de sombras congelado", "trade", { "trade" } },
        { "whitemend pants", "pantalones de remiendo blanco", "trade", { "trade" } },
        { "hellfire peninsula", "peninsula del fuego infernal", "travel", { "social" } },
        { "hfp", "peninsula del fuego infernal", "travel", { "social" } },
        { "zangarmarsh", "marisma de zangar", "travel", { "social" } },
        { "terokkar forest", "bosque de terokkar", "travel", { "social" } },
        { "nagrand", "nagrand", "travel", { "social" } },
        { "blades edge", "filo de la navaja", "travel", { "social" } },
        { "netherstorm", "tormenta abisal", "travel", { "social" } },
        { "shadowmoon valley", "valle sombraluna", "travel", { "social" } },
        { "isle of queldanas", "isla de queldanas", "travel", { "social" } },
        { "sunwell isle", "isla de la fuente del sol", "travel", { "social" } },
        { "area 52", "area 52", "travel", { "social" } },
        { "telaar", "telaar", "travel", { "social" } },
        { "thrallmar", "thrallmar", "travel", { "social" } },
        { "honor hold", "fortaleza del honor", "travel", { "social" } },
        { "falcon watch", "vigilia del halcon", "travel", { "social" } },
        { "cenarion refuge", "refugio cenarion", "travel", { "social" } },
        { "coilfang reservoir", "reserva colmillo torcido", "travel", { "social", "combat" } },
        { "tempest keep dungeons", "mazmorras de fortaleza de la tempestad", "travel", { "social", "combat" } },
        { "auchindoun", "auchindoun", "travel", { "social", "combat" } },
        { "caverns of time", "cavernas del tiempo", "travel", { "social", "combat" } },
        { "fly to shatt", "vuela a shattrath", "travel", { "social" } },
        { "fly to area 52", "vuela a area 52", "travel", { "social" } },
        { "flight master", "maestro de vuelo", "travel", { "social" } },

        -- SOCIAL / EMOTIONAL / TIME / TYPOS
        { "this is hard", "esto esta dificil", "social", { "social", "combat" } },
        { "we keep wiping", "seguimos wipeando", "social", { "social", "combat" } },
        { "too many mistakes", "demasiados errores", "social", { "social", "combat" } },
        { "need better gear", "necesitamos mejor equipo", "social", { "social", "combat" } },
        { "lag spike", "pico de lag", "social", { "social", "combat", "pvp" } },
        { "dc again", "dc otra vez", "social", { "social", "combat" } },
        { "server lag", "lag del servidor", "social", { "social", "combat" } },
        { "instance server", "servidor de instancia", "social", { "social", "combat" } },
        { "cant see boss", "no veo al jefe", "social", { "social", "combat" } },
        { "we got this", "podemos hacerlo", "social", { "social", "combat" } },
        { "one more try", "un intento mas", "social", { "social", "combat" } },
        { "almost had it", "casi lo logramos", "social", { "social", "combat" } },
        { "so close", "tan cerca", "social", { "social", "combat" } },
        { "we can do it", "si podemos", "social", { "social", "combat" } },
        { "nice try", "buen intento", "social", { "social", "combat" } },
        { "unlucky", "mala suerte", "social", { "social", "combat" } },
        { "bad rng", "mal rng", "social", { "social", "combat" } },
        { "well get it next time", "la proxima sale", "social", { "social", "combat" } },
        { "first kill", "primer kill", "social", { "social", "combat" } },
        { "realm first", "primero del reino", "social", { "social", "combat" } },
        { "server first", "primero del servidor", "social", { "social", "combat" } },
        { "guild first", "primero de la guild", "social", { "social", "combat" } },
        { "finally", "por fin", "social", { "social", "combat" } },
        { "epic drop", "drop epico", "social", { "social", "combat", "trade" } },
        { "legendary drop", "drop legendario", "social", { "social", "combat", "trade" } },
        { "bis drop", "drop bis", "social", { "social", "combat", "trade" } },
        { "upgrade", "mejora", "social", { "social", "combat", "trade" } },
        { "my fault", "mi culpa", "social", { "social", "combat" } },
        { "i messed up", "la cague", "social", { "social", "combat" } },
        { "sorry about that", "perdon por eso", "social", { "social", "combat" } },
        { "wont happen again", "no pasara otra vez", "social", { "social", "combat" } },
        { "didnt see it", "no lo vi", "social", { "social", "combat" } },
        { "wasnt paying attention", "no estaba atento", "social", { "social", "combat" } },
        { "alt tabbed", "estaba alt tab", "social", { "social", "combat" } },
        { "what time tomorrow", "a que hora manana", "social", { "social" } },
        { "raid time", "hora de raid", "social", { "social" } },
        { "invites at 7", "invitaciones a las 7", "social", { "social" } },
        { "start time", "hora de inicio", "social", { "social" } },
        { "how long", "cuanto tiempo", "social", { "social" } },
        { "need to leave by", "me tengo que ir para", "social", { "social" } },
        { "have to go soon", "me tengo que ir pronto", "social", { "social" } },
        { "last pull", "ultimo pull", "social", { "social", "combat" } },
        { "that was crazy", "eso estuvo loco", "social", { "social", "combat" } },
        { "how did we survive", "como sobrevivimos", "social", { "social", "combat" } },
        { "youre insane", "estas loco", "social", { "social", "combat" } },
        { "clutch play", "jugada clutch", "social", { "social", "combat" } },
        { "lol what", "jaja que", "social", { "social" } },
        { "are you serious", "hablas en serio", "social", { "social" } },
        { "no way", "no puede ser", "social", { "social" } },
        { "thats impossible", "eso es imposible", "social", { "social" } },
        { "ten seconds", "diez segundos", "social", { "social", "combat" } },
        { "thirty seconds", "treinta segundos", "social", { "social", "combat" } },
        { "ten minutes", "diez minutos", "social", { "social" } },
        { "thirty minutes", "treinta minutos", "social", { "social" } },
        { "one hour", "una hora", "social", { "social" } },
        { "after this", "despues de esto", "social", { "social", "combat" } },
        { "before reset", "antes del reset", "social", { "social" } },
        { "daily reset", "reset diario", "social", { "social" } },
        { "weekly reset", "reset semanal", "social", { "social" } },
        { "boss at 50", "jefe al 50", "combat", { "combat", "pvp" } },
        { "boss at 25", "jefe al 25", "combat", { "combat", "pvp" } },
        { "burn phase", "fase de quemar", "combat", { "combat" } },
        { "gj", "buen trabajo", "social", { "social", "combat" } },
        { "omg", "dios mio", "social", { "social" } },
        { "wtf", "que demonios", "social", { "social" } },
        { "lmao", "me muero de risa", "social", { "social" } },
        { "rofl", "rodando de risa", "social", { "social" } },
        { "idc", "no me importa", "social", { "social" } },
        { "g2g", "me tengo que ir", "social", { "social" } },
        { "gtg", "me tengo que ir", "social", { "social" } },
        { "bbl", "vuelvo luego", "social", { "social" } },
        { "ttyl", "hablamos luego", "social", { "social" } },
        { "tb", "tambien", "social", { "social" } },
        { "tmb", "tambien", "social", { "social" } },
        { "porfa", "please", "social", { "social" } },
        { "sumn", "summon", "social", { "social" } },
        { "invt", "invite", "social", { "social" } },
        { "healr", "healer", "social", { "combat" } },
        { "hlr", "healer", "social", { "combat" } },
        { "heal", "sanar", "social", { "combat" } },
    }

    for _, entry in ipairs(entries) do
        addBidirectionalEntry(entry[1], entry[2], entry[3], entry[4])
    end

    -- Override a few ambiguous one-word mappings with more natural chat defaults.
    addEntry("need", "necesito", "general", { "social", "combat", "trade" })
    addEntry("necesidad", "need", "general", { "social", "combat" })
    addEntry("para", "for", "general", { "social", "trade", "combat" })
    addEntry("stop", "alto", "general", { "social", "combat", "pvp" })
    addEntry("invite pls", "invita por favor", "group", { "social" })
    addEntry("need summon", "necesito summon", "group", { "social", "combat" })
    addEntry("necesito summon", "need summon", "group", { "social", "combat" })
    addEntry("quick run", "run rapido", "group", { "social", "trade" })
    addEntry("run rapido", "quick run", "group", { "social", "trade" })
    addEntry("group ready", "grupo listo", "group", { "social", "combat" })
    addEntry("who needs", "quien necesita", "group", { "social" })
    addEntry("wait mana", "espera mana", "combat", { "combat" })
    addEntry("rez pls", "res por favor", "combat", { "combat" })
    addEntry("run back", "corre de vuelta", "combat", { "combat" })
    addEntry("buff pls", "buf por favor", "combat", { "combat" })
    addEntry("repair", "reparar", "combat", { "combat", "social" })
    addEntry("reset instance", "reinicia instancia", "combat", { "combat" })
    addEntry("cc skull", "cc calavera", "combat", { "combat" })
    addEntry("focus skull", "foco calavera", "combat", { "combat" })
    addEntry("pulling", "jalando", "combat", { "combat" })
    addEntry("heroic shattered halls", "salones destrozados heroico", "dungeon", { "combat" })
    addEntry("shh", "salones destrozados heroico", "dungeon", { "combat" })
    addEntry("slabs", "laberinto de las sombras", "dungeon", { "combat" })
    addEntry("shadow labs", "laberinto de las sombras", "dungeon", { "combat" })
    addEntry("steamvaults", "camara de vapor", "dungeon", { "combat" })
    addEntry("sv", "camara de vapor", "dungeon", { "combat" })
    addEntry("mt", "tumbas de mana", "dungeon", { "combat" })
    addEntry("bm", "cienaga negra", "dungeon", { "combat" })
    addEntry("ramparts", "murallas", "dungeon", { "combat" })
    addEntry("bf", "horno de sangre", "dungeon", { "combat" })
    addEntry("ub", "soto eterno", "dungeon", { "combat" })
    addEntry("mech", "mecanar", "dungeon", { "combat" })
    addEntry("bot", "botanica", "dungeon", { "combat" })
    addEntry("arc", "arcatraz", "dungeon", { "combat" })
    addEntry("prot pally", "paladin proteccion", "class", { "combat" })
    addEntry("holy priest", "sacerdote sagrado", "class", { "combat" })
    addEntry("resto shaman", "chaman restauracion", "class", { "combat" })
    addEntry("feral druid", "druida feral", "class", { "combat" })
    addEntry("boomkin", "pollo lunar", "class", { "combat" })
    addEntry("enh shaman", "chaman mejora", "class", { "combat" })
    addEntry("ele shaman", "chaman elemental", "class", { "combat" })
    addEntry("shadow priest", "sacerdote sombras", "class", { "combat" })
    addEntry("spriest", "sacerdote sombras", "class", { "combat" })
    addEntry("ret pally", "paladin reprension", "class", { "combat" })
    addEntry("arms warrior", "guerrero armas", "class", { "combat" })
    addEntry("fury warrior", "guerrero furia", "class", { "combat" })
    addEntry("lock", "brujo", "class", { "social", "combat" })
    addEntry("enemy rogue", "rogue enemigo", "pvp", { "pvp", "combat" })
    addEntry("defend flag", "defiende bandera", "pvp", { "pvp" })
    addEntry("cap flag", "captura bandera", "pvp", { "pvp" })
    addEntry("lumber mill", "aserradero", "pvp", { "pvp" })
    addEntry("inv plz", "invite please", "group", { "social" })
    addEntry("sum pls", "summon please", "group", { "social", "combat" })
    addEntry("need hlr", "need healer", "group", { "social", "combat" })
    addEntry("need tk", "need tank", "group", { "social", "combat" })
    addEntry("pls inv", "please invite", "group", { "social" })
    addEntry("kara attune", "attunement kara", "raid", { "social", "combat" })
    addEntry("attunement", "atunacion", "raid", { "social", "combat" })
    addEntry("heroic key", "llave heroica", "dungeon", { "social", "combat" })
    addEntry("rep grind", "farmeo de reputacion", "social", { "social", "combat" })
    addEntry("crazy", "loco", "social", { "social" })
    addEntry("mad", "loco", "social", { "social" })
    addEntry("man", "hombre", "social", { "social" })
    addEntry("friend", "amigo", "social", { "social" })
    addEntry("bro", "bro", "social", { "social" })
    addEntry("funny", "gracioso", "social", { "social" })
    addEntry("cool", "buena onda", "social", { "social" })
    addEntry("awesome", "genial", "social", { "social" })
    addEntry("good", "bueno", "social", { "social" })
    addEntry("bad", "malo", "social", { "social" })
    addEntry("job", "trabajo", "social", { "social" })
    addEntry("quest", "mision", "social", { "social", "combat" })
    addEntry("help", "ayuda", "social", { "social", "combat" })
    addEntry("with", "con", "social", { "social" })
    addEntry("a", "un", "social", { "social" })
    addEntry("the", "el", "social", { "social" })
    addEntry("my", "mi", "social", { "social" })
    addEntry("your", "tu", "social", { "social" })
    addEntry("are", "estas", "social", { "social" })
    addEntry("you are", "estas", "social", { "social" })
    addEntry("i am", "estoy", "social", { "social" })
    addEntry("loco", "crazy", "social", { "social" })
    addEntry("hombre", "man", "social", { "social" })
    addEntry("amigo", "friend", "social", { "social" })
    addEntry("gracioso", "funny", "social", { "social" })
    addEntry("genial", "awesome", "social", { "social" })
    addEntry("buena onda", "cool", "social", { "social" })
    addEntry("mision", "quest", "social", { "social", "combat" })
    addEntry("ayuda", "help", "social", { "social", "combat" })
    addEntry("con", "with", "social", { "social" })
end

local function stripAccents(text)
    local accentMap = {
        [string.char(195, 161)] = "a",
        [string.char(195, 160)] = "a",
        [string.char(195, 164)] = "a",
        [string.char(195, 162)] = "a",
        [string.char(195, 169)] = "e",
        [string.char(195, 168)] = "e",
        [string.char(195, 171)] = "e",
        [string.char(195, 170)] = "e",
        [string.char(195, 173)] = "i",
        [string.char(195, 172)] = "i",
        [string.char(195, 175)] = "i",
        [string.char(195, 174)] = "i",
        [string.char(195, 179)] = "o",
        [string.char(195, 178)] = "o",
        [string.char(195, 182)] = "o",
        [string.char(195, 180)] = "o",
        [string.char(195, 186)] = "u",
        [string.char(195, 185)] = "u",
        [string.char(195, 188)] = "u",
        [string.char(195, 187)] = "u",
        [string.char(195, 177)] = "n",
    }

    for source, target in pairs(accentMap) do
        text = string.gsub(text, source, target)
    end

    return text
end

local function countWords(text)
    local count = 0
    for _ in string.gmatch(text, "%S+") do
        count = count + 1
    end
    return count
end

local function applyTyposAndAliases(text)
    local rebuilt = {}
    for word in string.gmatch(text, "%S+") do
        table.insert(rebuilt, typoAliases[word] or word)
    end
    return table.concat(rebuilt, " ")
end

local function stripChatChannelPrefix(text)
    local normalized = normalizeText(text)
    local prefix, rest = string.match(normalized, "^(%S+)%s+(.+)$")
    if not prefix or not rest then
        return normalized
    end

    local channelPrefixes = {
        g = true, guild = true, p = true, party = true, raid = true, r = true,
        s = true, say = true, y = true, yell = true, w = true, whisper = true,
    }

    if channelPrefixes[prefix] then
        return normalizeText(rest)
    end

    return normalized
end

local spanishDirectionIndicators = {
    ["necesito"] = true,
    ["necesitas"] = true,
    ["tengo"] = true,
    ["tienes"] = true,
    ["vamos"] = true,
    ["ayuda"] = true,
    ["gracias"] = true,
    ["hola"] = true,
    ["listo"] = true,
    ["espera"] = true,
    ["donde"] = true,
    ["que"] = true,
    ["como"] = true,
    ["cuando"] = true,
    ["porque"] = true,
    ["por"] = true,
    ["favor"] = true,
    ["sanador"] = true,
    ["tanque"] = true,
    ["banda"] = true,
    ["mazmorra"] = true,
    ["mision"] = true,
}

local englishDirectionIndicators = {
    ["i"] = true,
    ["need"] = true,
    ["have"] = true,
    ["you"] = true,
    ["hello"] = true,
    ["thanks"] = true,
    ["please"] = true,
    ["ready"] = true,
    ["wait"] = true,
    ["where"] = true,
    ["what"] = true,
    ["how"] = true,
    ["when"] = true,
    ["why"] = true,
    ["healer"] = true,
    ["tank"] = true,
    ["raid"] = true,
    ["dungeon"] = true,
    ["quest"] = true,
    ["guild"] = true,
}

local protectedWowTerms = {
    ["healer"] = true,
    ["tank"] = true,
    ["dps"] = true,
    ["raid"] = true,
    ["party"] = true,
    ["guild"] = true,
    ["pull"] = true,
    ["aggro"] = true,
    ["oom"] = true,
    ["mana"] = true,
    ["hp"] = true,
    ["cc"] = true,
    ["boss"] = true,
    ["trash"] = true,
    ["adds"] = true,
    ["mob"] = true,
    ["mobs"] = true,
    ["kara"] = true,
    ["aq"] = true,
    ["aq20"] = true,
    ["aq25"] = true,
    ["gruul"] = true,
    ["mag"] = true,
    ["ssc"] = true,
    ["tk"] = true,
    ["hyjal"] = true,
    ["bt"] = true,
    ["sunwell"] = true,
    ["discord"] = true,
    ["dbm"] = true,
    ["omen"] = true,
    ["recount"] = true,
    ["gdkp"] = true,
    ["bis"] = true,
    ["buff"] = true,
    ["debuff"] = true,
    ["loot"] = true,
    ["roll"] = true,
    ["need"] = true,
    ["greed"] = true,
    ["pass"] = true,
    ["summon"] = true,
    ["heroic"] = true,
    ["dungeon"] = true,
    ["attune"] = true,
    ["run"] = true,
    ["wipe"] = true,
    ["portal"] = true,
    ["warlock"] = true,
    ["mage"] = true,
    ["priest"] = true,
    ["rogue"] = true,
    ["hunter"] = true,
    ["shaman"] = true,
    ["druid"] = true,
    ["paladin"] = true,
    ["warrior"] = true,
}

local function normalizeLookupText(text)
    local normalized = normalizeText(text)
    normalized = stripAccents(normalized)
    normalized = applyTyposAndAliases(normalized)
    normalized = string.gsub(normalized, "%s+", " ")
    normalized = string.gsub(normalized, "^%s+", "")
    normalized = string.gsub(normalized, "%s+$", "")
    return normalized
end

local function splitWords(text)
    local words = {}
    for word in string.gmatch(text, "%S+") do
        table.insert(words, word)
    end
    return words
end

local function resolveTokenWithFallback(word)
    local originalWord = tostring(word or "")
    local normalizedWord = normalizeGeneralLookupText(word)
    local specialized = exactLookup[normalizedWord] or canonicalLookup[normalizedWord]
    if specialized then
        if debugMode and debugVerbose then
            KCxTranslatorAddLine("token '" .. originalWord .. "' -> '" .. normalizedWord .. "' -> specialized", "debug")
            if normalizedWord == "inc" or normalizedWord == "incoming" or normalizedWord == "gy" or normalizedWord == "rez" or normalizedWord == "lfg" or normalizedWord == "lfm" then
                KCxTranslatorAddLine("shorthand structured translation used: " .. normalizedWord, "debug")
            end
        end
        return specialized, "specialized"
    end
    local general = generalExactLookup[normalizedWord] or generalCanonicalLookup[normalizedWord]
    if general then
        if debugMode and debugVerbose then
            KCxTranslatorAddLine("token '" .. originalWord .. "' -> '" .. normalizedWord .. "' -> general", "debug")
        end
        return general, "general"
    end

    -- Lightweight suffix normalization for conversational fallbacks:
    -- try a simple base-form lookup for -ing / -ed tokens before miss.
    local function tryBaseForm(base)
        if not base or base == "" then
            return nil, nil
        end
        local s = exactLookup[base] or canonicalLookup[base]
        if s then
            return s, "specialized"
        end
        local g = generalExactLookup[base] or generalCanonicalLookup[base]
        if g then
            return g, "general"
        end
        return nil, nil
    end

    local base = nil
    if normalizedWord:match("^[a-z]+ing$") and #normalizedWord > 4 then
        base = normalizedWord:sub(1, -4) -- fighting -> fight
        local found, source = tryBaseForm(base)
        if not found and #base >= 2 and base:sub(-1) == base:sub(-2, -2) then
            found, source = tryBaseForm(base:sub(1, -2)) -- running -> run
        end
        if found then
            if debugMode and debugVerbose then
                KCxTranslatorAddLine("token '" .. originalWord .. "' normalized via -ing -> '" .. base .. "' -> " .. source, "debug")
            end
            return found, source
        end
    elseif normalizedWord:match("^[a-z]+ed$") and #normalizedWord > 3 then
        base = normalizedWord:sub(1, -3) -- searched -> search
        local found, source = tryBaseForm(base)
        if not found then
            found, source = tryBaseForm(base .. "e") -- offered -> offer
        end
        if not found and #base >= 2 and base:sub(-1) == base:sub(-2, -2) then
            found, source = tryBaseForm(base:sub(1, -2)) -- stopped -> stop
        end
        if found then
            if debugMode and debugVerbose then
                KCxTranslatorAddLine("token '" .. originalWord .. "' normalized via -ed -> '" .. base .. "' -> " .. source, "debug")
            end
            return found, source
        end
    end

    if debugMode and debugVerbose then
        KCxTranslatorAddLine("token '" .. originalWord .. "' -> '" .. normalizedWord .. "' -> miss", "debug")
    end
    return nil, "unknown"
end

local function normalizeConversationalOutput(text)
    if not text or text == "" then
        return text
    end

    local out = tostring(text)
    out = out:gsub("%[%s*%]", " ")
    out = out:gsub("%[%s+([^%]]-)%s+%]", "[%1]")
    out = out:gsub("%s+", " ")

    out = out:gsub("(%f[%a])y%s+y(%f[%A])", "y")
    out = out:gsub("(%f[%a])con%s+con(%f[%A])", "con")
    out = out:gsub("(%f[%a])para%s+para(%f[%A])", "para")
    out = out:gsub("(%f[%a])the%s+the(%f[%A])", "the")

    out = out:gsub("(%f[%a])looking%s+for(%f[%A])", "busco")
    out = out:gsub("(%f[%a])need%s+tank(%f[%A])", "necesito tanque")
    out = out:gsub("(%f[%a])need%s+healer(%f[%A])", "necesito sanador")
    out = out:gsub("(%f[%a])need%s+dps(%f[%A])", "necesito dps")
    out = out:gsub("(%f[%a])guild%s+recruiting(%f[%A])", "hermandad reclutando")
    out = out:gsub("(%f[%a])summon%s+available(%f[%A])", "summon disponible")

    local preserved = {
        "dps", "pst", "summon", "heroic", "kara", "ssc", "tk", "hyjal", "bt", "attune", "res", "aoe", "cleave",
        "full clear", "fast run", "smooth run", "hard reserve"
    }
    for _, token in ipairs(preserved) do
        local escaped = token:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        out = out:gsub("%[%s*" .. escaped .. "%s*%]", token)
    end

    out = out:gsub("%s+", " ")
    out = out:gsub("^%s+", "")
    out = out:gsub("%s+$", "")
    return out
end

local function cleanupFillerFragments(text)
    if not text or text == "" then
        return text
    end

    local out = tostring(text)

    -- Drop obvious orphan bracket fragments first.
    out = out:gsub("%[%s*%]", " ")
    out = out:gsub("%[%s*([^%]]-)%s*%]%s*%[%s*([^%]]-)%s*%]", "[%1 %2]")

    -- Low-value filler suppression for bracketed tokens only.
    local filler = {
        what = true, the = true, a = true, an = true, ["for"] = true, ["to"] = true, ["of"] = true,
        it = true, is = true, are = true, ["with"] = true, ["and"] = true, ["or"] = true,
        that = true, this = true,
        un = true, una = true, el = true, la = true, los = true, las = true, de = true, del = true
    }
    out = out:gsub("%[([^%]]+)%]", function(inner)
        local token = string.lower((inner or ""):gsub("^%s+", ""):gsub("%s+$", ""))
        if filler[token] then
            return " "
        end
        return "[" .. inner .. "]"
    end)

    -- Additional tiny readability cleanup.
    out = out:gsub("(%f[%a])y%s+y(%f[%A])", "y")
    out = out:gsub("(%f[%a])and%s+and(%f[%A])", "and")
    out = out:gsub("(%f[%a])un%s+un(%f[%A])", "un")
    out = out:gsub("(%f[%a])group%s+group(%f[%A])", "group")
    out = out:gsub("(%f[%a])guild%s+guild(%f[%A])", "guild")
    out = out:gsub("(%f[%a])run%s+run(%f[%A])", "run")
    out = out:gsub("(%f[%a])con%s+con(%f[%A])", "con")
    out = out:gsub("(%f[%a])para%s+para(%f[%A])", "para")
    out = out:gsub("(%f[%a])de%s+de(%f[%A])", "de")
    out = out:gsub("%s+([,%.%!%?;:])", "%1")
    out = out:gsub("%[([^%]]+)%]%s*([,%.%!%?;:])", "%2")
    out = out:gsub("%(%s+", "("):gsub("%s+%)", ")")
    out = out:gsub("%s+", " ")
    out = out:gsub("^%s+", "")
    out = out:gsub("%s+$", "")
    return out
end

local function polishTranslatedOutput(text)
    local out = normalizeConversationalOutput(tostring(text or ""))
    out = cleanupFillerFragments(out)
    local wowNameMap = {
        ["karazhan"] = "Karazhan",
        ["tempest keep"] = "Tempest Keep",
        ["black temple"] = "Black Temple",
        ["templo oscuro"] = "Black Temple",
        ["fortaleza de la tempestad"] = "Tempest Keep",
        ["meseta de la fuente del sol"] = "Sunwell",
        ["caverna santuario serpiente"] = "Serpentshrine Cavern",
        ["zul aman"] = "Zul'Aman",
        ["sunwell"] = "Sunwell",
        ["meseta de hyjal"] = "Hyjal",
        ["gruul"] = "Gruul",
        ["magtheridon"] = "Magtheridon",
        ["shattrath"] = "Shattrath",
        ["serpentshrine cavern"] = "Serpentshrine Cavern",
        ["hyjal"] = "Hyjal",
        ["netherspite"] = "Netherspite",
        ["nightbane"] = "Nightbane",
    }

    for lowerName, displayName in pairs(wowNameMap) do
        out = string.gsub(out, lowerName, displayName)
    end

    return out
end

-- Forward declarations used by natural assembly helpers.
local translateWordByWord
local translateExactLookup

local function assembleNaturalPhrase(text)
    local normalized = normalizeLookupText(text)
    local words = splitWords(normalized)
    if #words == 0 then
        return nil
    end

    local roleMap = {
        tank = "tanque",
        healer = "sanador",
        dps = "dps",
        caster = "caster",
        melee = "melee",
    }

    local function normalizeRoleToken(token, firstWord)
        if token == "hlr" or token == "heals" then
            return "healer"
        end
        if token == "tnak" then
            return "tank"
        end
        if token == "tk" and (firstWord == "need" or firstWord == "lf" or firstWord == "lfm" or firstWord == "looking") then
            return "tank"
        end
        return token
    end

    local head = words[1]
    local second = words[2] or ""
    local third = words[3] or ""
    local roleToken = normalizeRoleToken(second, head)
    local role = roleMap[roleToken]

    local function translateTail(startIndex)
        if startIndex > #words then
            return nil
        end
        local tail = table.concat(words, " ", startIndex)
        local tailExact = translateExactLookup(tail)
        if tailExact then
            return tailExact, tail
        end
        local tailWord, _, _ = translateWordByWord(tail, "combat")
        return tailWord or tail, tail
    end

    if head == "need" and role then
        if third == "for" then
            local dungeonTranslated, dungeonRaw = translateTail(4)
            if dungeonTranslated and dungeonTranslated ~= "" then
                return "necesitamos " .. role .. " para " .. dungeonTranslated, "NEED_ROLE_FOR", roleToken, dungeonRaw
            end
        end
        return "necesitamos " .. role, "NEED_ROLE", roleToken, nil
    end

    if (head == "lf" or head == "lfm") and role then
        if third == "for" then
            local dungeonTranslated, dungeonRaw = translateTail(4)
            if dungeonTranslated and dungeonTranslated ~= "" then
                return "buscando " .. role .. " para " .. dungeonTranslated, "LF_ROLE_FOR", roleToken, dungeonRaw
            end
        end
        if #words >= 3 then
            local dungeonTranslated, dungeonRaw = translateTail(3)
            if dungeonTranslated and dungeonTranslated ~= "" then
                return "buscando " .. role .. " para " .. dungeonTranslated, "LF_ROLE_FOR", roleToken, dungeonRaw
            end
        end
        return "buscando " .. role, "LF_ROLE", roleToken, nil
    end

    if head == "looking" and second == "for" then
        local roleFromLooking = normalizeRoleToken(third, head)
        local roleTranslated = roleMap[roleFromLooking]
        if roleTranslated then
            if words[4] == "for" then
                local dungeonTranslated, dungeonRaw = translateTail(5)
                if dungeonTranslated and dungeonTranslated ~= "" then
                    return "buscando " .. roleTranslated .. " para " .. dungeonTranslated, "LOOKING_FOR_ROLE_FOR", roleFromLooking, dungeonRaw
                end
            end
            return "buscando " .. roleTranslated, "LOOKING_FOR_ROLE", roleFromLooking, nil
        end
    end

    return nil
end

local function assembleSocialPhrase(text, originalText)
    local normalized = normalizeLookupText(text)
    local words = splitWords(normalized)
    if #words == 0 then
        return nil
    end

    local originalWords = splitWords(tostring(originalText or text or ""))
    local preservedName = nil
    local socialIgnore = { I = true, You = true, We = true, They = true, Hey = true, Hello = true, Hi = true }

    if originalWords[1] and string.match(originalWords[1], "^[A-Z]") and not socialIgnore[originalWords[1]] then
        preservedName = originalWords[1]
        table.remove(words, 1)
    end

    if #words == 0 then
        return nil
    end

    local phrase = table.concat(words, " ")
    local function withName(result, rule)
        if preservedName then
            return preservedName .. " " .. result, rule, preservedName, "none"
        end
        return result, rule, nil, "none"
    end

    local exactSocialMap = {
        ["you are crazy"] = "estas loco",
        ["you are a crazy man"] = "eres un hombre loco",
        ["you are a crazy mad man"] = "eres un hombre loco",
        ["you are funny"] = "eres gracioso",
        ["you are cool"] = "eres buena onda",
        ["you are awesome"] = "eres genial",
        ["you are good"] = "eres bueno",
        ["you are bad"] = "eres malo",
        ["you are my friend"] = "eres mi amigo",
        ["thanks friend"] = "gracias amigo",
        ["thanks bro"] = "gracias bro",
        ["thank you bro"] = "gracias bro",
        ["good job"] = "buen trabajo",
        ["nice job"] = "buen trabajo",
        ["good game"] = "buen juego",
        ["gg"] = "buen juego",
        ["i dont understand"] = "no entiendo",
        ["i speak a little spanish"] = "hablo un poco de espanol",
        ["do you speak english"] = "hablas ingles",
        ["can you help me"] = "me puedes ayudar",
        ["i need help"] = "necesito ayuda",
        ["i need help with a quest"] = "necesito ayuda con una mision",
        ["where are you"] = "donde estas",
        ["come here"] = "ven aqui",
        ["wait please"] = "espera por favor",
        ["one minute"] = "un minuto",
        ["be right back"] = "vuelvo enseguida",
        ["brb"] = "vuelvo enseguida",
        ["sorry my spanish is bad"] = "perdon mi espanol es malo",
        ["estas loco"] = "you are crazy",
        ["eres un hombre loco"] = "you are a crazy man",
        ["gracias amigo"] = "thanks friend",
        ["buen trabajo"] = "good job",
        ["donde estas"] = "where are you",
        ["ven aqui"] = "come here",
    }

    if exactSocialMap[phrase] then
        return withName(exactSocialMap[phrase], "SOCIAL_EXACT")
    end

    local socialWordMap = {
        crazy = "loco", mad = "loco", man = "hombre", friend = "amigo", bro = "bro",
        funny = "gracioso", cool = "buena onda", awesome = "genial", good = "bueno",
        bad = "malo", job = "trabajo", quest = "mision", help = "ayuda", with = "con",
        a = "un", the = "el", my = "mi", your = "tu", are = "estas", ["i"] = "yo", am = "estoy",
        loco = "crazy", hombre = "man", amigo = "friend", gracioso = "funny", genial = "awesome",
        mision = "quest", ayuda = "help", con = "with",
    }

    if #words >= 3 and words[1] == "you" and words[2] == "are" then
        local tail = {}
        for i = 3, #words do
            table.insert(tail, socialWordMap[words[i]] or words[i])
        end
        local merged = "estas " .. table.concat(tail, " ")
        return withName(merged, "SOCIAL_YOU_ARE")
    end

    if #words >= 4 and words[1] == "i" and words[2] == "need" and words[3] == "help" and words[4] == "with" then
        local tail = {}
        for i = 5, #words do
            table.insert(tail, socialWordMap[words[i]] or words[i])
        end
        local merged = "necesito ayuda con " .. table.concat(tail, " ")
        return withName(merged, "SOCIAL_NEED_HELP_WITH")
    end

    return nil
end

local function scoreDirectionWords(words)
    local spanishScore = 0
    local englishScore = 0

    for _, word in ipairs(words) do
        if spanishDirectionIndicators[word] then
            spanishScore = spanishScore + 1
        end

        if englishDirectionIndicators[word] then
            englishScore = englishScore + 1
        end
    end

    return spanishScore, englishScore
end

local function detectInputDirection(text)
    local normalized = normalizeLookupText(text)
    local words = splitWords(normalized)
    local spanishScore, englishScore = scoreDirectionWords(words)

    if spanishScore > englishScore then
        return "ES_TO_EN", spanishScore, englishScore
    end

    if englishScore > spanishScore then
        return "EN_TO_ES", spanishScore, englishScore
    end

    return "UNKNOWN", spanishScore, englishScore
end

buildLookupIndexes = function()
    exactLookup = {}
    canonicalLookup = {}

    for source, translated in pairs(translationDB) do
        exactLookup[normalizeText(source)] = translated
        canonicalLookup[normalizeLookupText(source)] = translated
    end
end

local function detectContext(text)
    local normalized = normalizeLookupText(text)
    local bestContext = "social"
    local bestScore = 0

    for contextName, keywords in pairs(contextKeywords) do
        local score = 0
        for _, keyword in ipairs(keywords) do
            if string.find(normalized, keyword, 1, true) then
                score = score + 1
            end
        end

        if score > bestScore then
            bestScore = score
            bestContext = contextName
        end
    end

    return bestContext, bestScore
end

local function contextMatches(meta, contextName)
    if not meta or not meta.contexts then
        return false
    end

    for _, taggedContext in ipairs(meta.contexts) do
        if taggedContext == contextName then
            return true
        end
    end

    return false
end

local function debugTranslation(info)
    if not debugMode or not info then
        return
    end

    local msg = string.format(
        "context: %s\nstage: %s\nconfidence: %.2f\nwords: %d",
        info.context or "social",
        info.severity or "REFUSE",
        info.confidence or 0,
        info.wordCount or 0
    )

    if info.reason and info.reason ~= "" then
        msg = msg .. "\nreason: " .. info.reason
    end

    KCxTranslatorAddLine(msg, "debug")
    if not debugVerbose then
        return
    end

    if info.originalInput then
        KCxTranslatorAddLine("input original: " .. info.originalInput, "debug")
    end
    if info.strippedInput then
        KCxTranslatorAddLine("input stripped: " .. info.strippedInput, "debug")
    end
    if info.exactResult then
        KCxTranslatorAddLine("exact: " .. info.exactResult, "debug")
    end
    if info.phraseResult then
        KCxTranslatorAddLine("phrase: " .. info.phraseResult, "debug")
    end
    if info.chunkResult then
        KCxTranslatorAddLine("chunks: " .. info.chunkResult, "debug")
    end
    if info.wordResult then
        KCxTranslatorAddLine("words: " .. info.wordResult, "debug")
    end
    if info.failedTokens and info.failedTokens ~= "" then
        KCxTranslatorAddLine("failed tokens: " .. info.failedTokens, "debug")
    end
    if info.assemblyRule then
        KCxTranslatorAddLine("assembly rule: " .. info.assemblyRule, "debug")
    end
    if info.assemblyRole then
        KCxTranslatorAddLine("role: " .. info.assemblyRole, "debug")
    end
    if info.assemblyDungeon then
        KCxTranslatorAddLine("dungeon: " .. info.assemblyDungeon, "debug")
    end
    if info.socialRule then
        KCxTranslatorAddLine("assembly rule: " .. info.socialRule, "debug")
    end
    if info.preservedName then
        KCxTranslatorAddLine("name preserved: " .. info.preservedName, "debug")
    end
    if info.socialUnknown then
        KCxTranslatorAddLine("unknown preserved: " .. info.socialUnknown, "debug")
    end
    if info.generalHits then
        KCxTranslatorAddLine("general hits: " .. tostring(info.generalHits), "debug")
    end
    if info.recognizedTokens then
        KCxTranslatorAddLine("recognized tokens: " .. tostring(info.recognizedTokens), "debug")
    end
    if info.unknownTokens then
        KCxTranslatorAddLine("unknown tokens: " .. tostring(info.unknownTokens), "debug")
    end
    if info.partialMode then
        KCxTranslatorAddLine("partial mode: " .. tostring(info.partialMode), "debug")
    end
end

seedMetadata()
addHighPriorityEntries()
seedMetadata()
buildLookupIndexes()

-- ----------------------------------------------------------------------------
-- Translation logic
-- ----------------------------------------------------------------------------
translateExactLookup = function(text)
    local normalized = normalizeText(text)
    local canonical = normalizeLookupText(text)

    if normalized == "" then
        return nil
    end

    return exactLookup[normalized] or canonicalLookup[canonical]
end

local function translatePhraseMatch(text, contextName)
    local normalized = normalizeLookupText(text)
    local totalWords = countWords(normalized)
    local bestMatch = nil
    local bestLen = 0
    local bestConfidence = 0

    for phrase, translated in pairs(translationDB) do
        local candidate = normalizeLookupText(phrase)
        local phraseWords = countWords(candidate)
        local phraseLen = string.len(candidate)

        if phraseLen >= 3 and phraseWords >= 2 then
            if string.find(normalized, candidate, 1, true) then
                local coverage = phraseWords / math.max(totalWords, 1)
                local confidence = coverage
                local meta = translationMeta[phrase]

                if contextMatches(meta, contextName) then
                    confidence = confidence + 0.20
                end

                if phraseLen > bestLen or (phraseLen == bestLen and confidence > bestConfidence) then
                    bestMatch = translated
                    bestLen = phraseLen
                    bestConfidence = confidence
                end
            end
        end
    end

    if bestMatch and bestConfidence >= 0.45 then
        return bestMatch, bestConfidence
    end

    return nil, bestConfidence
end

local function translatePhraseWithRemainder(text, contextName)
    local traceInput = tostring(text or "")
    local dirTag = detectInputDirection(traceInput)
    if debugMode and debugVerbose then
        KCxTranslatorAddLine("[KCX TRACE] enter translatePhraseWithRemainder dir=" .. tostring(dirTag) .. " text=" .. traceInput, "debug")
    end
    local normalized = normalizeLookupText(text)
    local words = splitWords(normalized)
    if #words == 0 then
        return nil, 0
    end

    -- Phrase-first locking: select longest matches globally, then lock spans.
    local lockedByIndex = {}
    local lockedSegments = {}
    local matchedPhrases = 0
    local recognized = 0
    local candidates = {}

    for i = 1, #words do
        for n = math.min(8, #words - i + 1), 2, -1 do
            local candidate = table.concat(words, " ", i, i + n - 1)
            local t = translateExactLookup(candidate)
            if t then
                if debugMode and debugVerbose then
                    KCxTranslatorAddLine("[KCX TRACE] phrase candidate start=" .. tostring(i) .. " stop=" .. tostring(i + n - 1) .. " phrase=" .. candidate .. " result=" .. tostring(t), "debug")
                end
                table.insert(candidates, { s = i, e = i + n - 1, n = n, t = t })
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.n ~= b.n then
            return a.n > b.n
        end
        return a.s < b.s
    end)

    for _, c in ipairs(candidates) do
        local overlaps = false
        for j = c.s, c.e do
            if lockedByIndex[j] then
                overlaps = true
                break
            end
        end
        if not overlaps then
            local marker = "__KCX_LOCK_" .. tostring(#lockedSegments + 1) .. "__"
            table.insert(lockedSegments, c.t)
            if debugMode and debugVerbose then
                local phrase = table.concat(words, " ", c.s, c.e)
                KCxTranslatorAddLine("[KCX TRACE] phrase locked start=" .. tostring(c.s) .. " stop=" .. tostring(c.e) .. " phrase=" .. phrase .. " result=" .. tostring(c.t), "debug")
            end
            for j = c.s, c.e do
                lockedByIndex[j] = marker
            end
            matchedPhrases = matchedPhrases + 1
            recognized = recognized + c.n
        end
    end

    local rebuilt = {}
    i = 1
    while i <= #words do
        local marker = lockedByIndex[i]
        if marker then
            if debugMode and debugVerbose then
                KCxTranslatorAddLine("[KCX TRACE] fallback skipped locked token index=" .. tostring(i) .. " token=" .. tostring(words[i]), "debug")
            end
            table.insert(rebuilt, marker)
            while i <= #words and lockedByIndex[i] == marker do
                i = i + 1
            end
        else
            if debugMode and debugVerbose then
                KCxTranslatorAddLine("[KCX TRACE] fallback token index=" .. tostring(i) .. " token=" .. tostring(words[i]) .. " locked=false", "debug")
            end
            if protectedWowTerms[words[i]] then
                if debugMode and debugVerbose then
                    KCxTranslatorAddLine("[KCX TRACE] protected preserve token=" .. tostring(words[i]), "debug")
                end
                table.insert(rebuilt, words[i])
                recognized = recognized + 1
            else
                local single, _ = resolveTokenWithFallback(words[i])
                if single then
                    table.insert(rebuilt, single)
                    recognized = recognized + 1
                else
                    table.insert(rebuilt, "[" .. words[i] .. "]")
                end
            end
            i = i + 1
        end
    end

    if matchedPhrases == 0 then
        return nil, 0
    end

    local confidence = recognized / math.max(#words, 1)
    if contextName == "combat" or contextName == "pvp" then
        confidence = confidence + 0.05
    end

    local assembled = table.concat(rebuilt, " ")
    for idx, chunk in ipairs(lockedSegments) do
        assembled = assembled:gsub("__KCX_LOCK_" .. tostring(idx) .. "__", chunk)
    end
    if debugMode and debugVerbose then
        KCxTranslatorAddLine("[KCX TRACE] phraseWithRemainder result=" .. tostring(assembled), "debug")
    end
    return assembled, confidence
end

translateWordByWord = function(text, contextName)
    local normalized = normalizeLookupText(text)
    local totalWords = countWords(normalized)
    local directionLock = detectInputDirection(text)

    if normalized == "" or totalWords == 0 then
        return nil, 0, "empty"
    end

    if totalWords > 8 then
        return nil, 0, "long message refused"
    end

    local translatedWords = {}
    local translatedCount = 0
    local unknownCount = 0
    local generalHits = 0

    for word in string.gmatch(normalized, "%S+") do
        if protectedWowTerms[word] then
            local protectedTranslation = resolveTokenWithFallback(word)
            if protectedTranslation then
                table.insert(translatedWords, protectedTranslation)
            else
                table.insert(translatedWords, word)
            end
            translatedCount = translatedCount + 1
        else
        local wordTranslation, sourceType = resolveTokenWithFallback(word)
        local usedGeneral = false
        if sourceType == "general" then
            usedGeneral = true
        end
        local allowTranslation = true

        if directionLock ~= "UNKNOWN" then
            local spanishScore, englishScore = scoreDirectionWords({ word })

            if directionLock == "ES_TO_EN" then
                if englishScore > spanishScore then
                    allowTranslation = false
                end
            elseif directionLock == "EN_TO_ES" then
                if spanishScore > englishScore then
                    allowTranslation = false
                end
            end
        end

        if wordTranslation and allowTranslation then
            table.insert(translatedWords, wordTranslation)
            translatedCount = translatedCount + 1
            if usedGeneral then
                generalHits = generalHits + 1
            end
        else
            table.insert(translatedWords, "[" .. word .. "]")
            unknownCount = unknownCount + 1
        end
        end
    end

    if translatedCount == 0 then
        return nil, 0, "no known words"
    end

    local confidence = translatedCount / totalWords
    if contextName == "combat" or contextName == "pvp" then
        confidence = confidence + 0.10
    end

    if translatedCount == 1 and totalWords >= 3 then
        confidence = confidence - 0.25
    end

    if unknownCount >= translatedCount then
        confidence = confidence - 0.15
    end

    local partialMode = false
    if confidence >= 0.70 then
        partialMode = false
    elseif confidence >= 0.30 then
        partialMode = true
    else
        return nil, confidence, "No reliable translation found.", translatedCount, unknownCount, false
    end

    local reason = "word fallback " .. string.lower(directionLock)
    if generalHits > 0 then
        reason = reason .. " general_hits=" .. tostring(generalHits)
    end
    if partialMode then
        reason = reason .. " partial_mode"
    end
    return table.concat(translatedWords, " "), confidence, reason, translatedCount, unknownCount, partialMode
end

local importantFallbackTokens = {
    ["asshole"] = true,
    ["bitch"] = true,
    ["idiot"] = true,
    ["idiota"] = true,
    ["imbecil"] = true,
    ["pendejo"] = true,
    ["puta"] = true,
    ["cabron"] = true,
    ["mierda"] = true,
    ["callate"] = true,
    ["stupid"] = true,
    ["tonto"] = true,
    ["moron"] = true,
    ["loser"] = true,
    ["pathetic"] = true,
    ["clown"] = true,
    ["basura"] = true,
    ["toxic"] = true,
    ["toxico"] = true,
}

-- Small manual-only phrase aids to improve readability in relaxed fallback.
local manualRelaxedPhraseMap = {
    ["but honestly"] = "pero honestamente",
    ["should uninstall the game"] = "deberia desinstalar el juego",
    ["uninstall the game"] = "desinstalar el juego",
    ["translator is just fucked"] = "traductor esta muy jodido",
    ["my translator is just fucked"] = "mi traductor esta muy jodido",
    ["because we lost"] = "porque nosotros perdimos",
    ["called me"] = "me llamo",
    ["called you"] = "te llamo",
    ["called him"] = "lo llamo",
    ["called her"] = "la llamo",
    ["was called"] = "fue llamado",
    ["earlier"] = "antes",
    ["some"] = "algun",
}

local manualConversationalNormalizePairs = {
    { " saying they were ", " diciendo que ellos eran " },
    { " saying she was ", " diciendo que ella era " },
    { " saying he was ", " diciendo que el era " },
    { " saying i was ", " diciendo que yo era " },
    { " saying yo was ", " diciendo que yo era " },
    { " saying ", " diciendo " },
    { " but honestly ", " pero honestamente " },
    { " should uninstall the game ", " deberia desinstalar el juego " },
    { " uninstall the game ", " desinstalar el juego " },
    { " my translator is just fucked ", " mi traductor esta muy jodido " },
    { " translator is just fucked ", " traductor esta muy jodido " },
    { " because we lost ", " porque nosotros perdimos " },
    { " i was trash ", " yo era basura " },
    { " was trash ", " era basura " },
    { " is just fucked ", " esta muy jodido " },
    { " just fucked ", " muy jodido " },
    { " the game ", " el juego " },
    { " yo was ", " yo era " },
    { " yo is ", " yo estoy " },
    { " y should ", " y deberia " },
    { " then ", " entonces " },
    { " i am ", " yo estoy " },
    { " i was ", " yo estaba " },
    { " i will be ", " yo estare " },
    { " he is ", " el esta " },
    { " she is ", " ella esta " },
    { " they are ", " ellos estan " },
    { " we are ", " nosotros estamos " },
    { " we lost ", " nosotros perdimos " },
    { " we won ", " nosotros ganamos " },
    { " kept calling ", " seguia llamando " },
    { " was calling ", " estaba llamando " },
    { " called me ", " me llamo " },
    { " whispered me ", " me susurro " },
    { " trying to ", " tratando de " },
    { " going to ", " voy a " },
    { " just tired ", " solo cansado " },
    { " right now ", " ahora mismo " },
    { " last night ", " anoche " },
    { " earlier today ", " mas temprano hoy " },
    { " because my internet ", " porque mi internet " },
    { " battery died ", " bateria murio " },
    { " phone died ", " telefono murio " },
    { " internet died ", " internet murio " },
    { " esta fucked ", " esta jodido " },
    { " this game sucks ", " este juego apesta " },
    { " toxic guy ", " tipo toxico " },
    { " trash player ", " jugador basura " },
    { " the match ", " la partida " },
    { " honestly ", " honestamente " },
}

local function normalizeManualConversationalOutput(text)
    local s = " " .. tostring(text or "") .. " "
    for _, pair in ipairs(manualConversationalNormalizePairs) do
        s = string.gsub(s, pair[1], pair[2])
    end
    s = string.gsub(s, "%s+", " ")
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

translateDetailed = function(text, allowPhraseMatch, allowWordFallback, allowRelaxedManualFallback)
    local traceDir = detectInputDirection(tostring(text or ""))
    if debugMode and debugVerbose then
        KCxTranslatorAddLine("[KCX TRACE] enter translateDetailed dir=" .. tostring(traceDir) .. " text=" .. tostring(text or ""), "debug")
    end
    local preprocessed = stripChatChannelPrefix(text)
    local normalized = normalizeText(preprocessed)
    local contextName, contextScore = detectContext(preprocessed)
    local info = {
        context = contextName,
        contextScore = contextScore,
        normalized = normalized,
        wordCount = countWords(normalized),
        severity = "REFUSE",
        confidence = 0,
        reason = "no translation",
        originalInput = tostring(text or ""),
        strippedInput = preprocessed,
        exactResult = "none",
        phraseResult = "none",
        chunkResult = "none",
        wordResult = "none",
        failedTokens = "",
    }

    if normalized == "" then
        info.reason = "empty input"
        return nil, info
    end

    -- Earliest phrase-lock route for EN->ES mixed MMO/social lines.
    -- This must run before any social, natural, role, dungeon, or combat assembly.
    if allowPhraseMatch == true then
        local inputDir = detectInputDirection(preprocessed)
        if inputDir ~= "ES_TO_EN" then
            if debugMode and debugVerbose then
                KCxTranslatorAddLine("[KCX TRACE] pre-assembly phrase-lock check text=" .. tostring(preprocessed or ""), "debug")
            end
            local prePhraseTranslation, prePhraseConfidence = translatePhraseWithRemainder(preprocessed, contextName)
            if prePhraseTranslation and prePhraseTranslation ~= "" then
                local normalizedIn = normalizeLookupText(preprocessed)
                local normalizedOut = normalizeLookupText(prePhraseTranslation)
                local changed = (normalizedOut ~= "" and normalizedOut ~= normalizedIn)
                if changed then
                    info.phraseResult = "hit(pre-assembly)"
                    info.severity = "PHRASE"
                    info.confidence = prePhraseConfidence or 0.55
                    info.reason = "pre-assembly phrase-lock"
                    local finalOut = polishTranslatedOutput(prePhraseTranslation)
                    if debugMode and debugVerbose then
                        KCxTranslatorAddLine("[KCX TRACE] pre-assembly phrase-lock accepted result=" .. tostring(finalOut), "debug")
                        KCxTranslatorAddLine("[KCX TRACE] final translateDetailed result=" .. tostring(finalOut), "debug")
                    end
                    return finalOut, info
                elseif debugMode and debugVerbose then
                    KCxTranslatorAddLine("[KCX TRACE] pre-assembly phrase-lock skipped reason=not_useful", "debug")
                end
            elseif debugMode and debugVerbose then
                KCxTranslatorAddLine("[KCX TRACE] pre-assembly phrase-lock skipped reason=no_match", "debug")
            end
        elseif debugMode and debugVerbose then
            KCxTranslatorAddLine("[KCX TRACE] pre-assembly phrase-lock skipped reason=reverse_direction", "debug")
        end
    end

    local exactTranslation = translateExactLookup(preprocessed)
    if exactTranslation then
        info.exactResult = "hit"
        info.severity = "EXACT"
        info.confidence = 1.00
        info.reason = "exact lookup"
        return polishTranslatedOutput(exactTranslation), info
    end

    info.exactResult = "miss"

    local socialAssembled, socialRule, preservedName, socialUnknown = assembleSocialPhrase(preprocessed, text)
    if socialAssembled then
        info.severity = "ASSEMBLY"
        info.confidence = 0.84
        info.reason = "social assembly"
        info.socialRule = socialRule
        info.preservedName = preservedName
        info.socialUnknown = socialUnknown
        return polishTranslatedOutput(socialAssembled), info
    end

    local assembled, ruleName, roleName, dungeonName = assembleNaturalPhrase(preprocessed)
    if assembled then
        info.severity = "ASSEMBLY"
        info.confidence = 0.88
        info.reason = "natural assembly"
        info.phraseResult = "assembly"
        info.chunkResult = "assembly"
        info.assemblyRule = ruleName
        info.assemblyRole = roleName
        info.assemblyDungeon = dungeonName
        return polishTranslatedOutput(assembled), info
    end

    if allowPhraseMatch and info.wordCount <= 8 then
        local phraseTranslation, phraseConfidence = translatePhraseWithRemainder(preprocessed, contextName)
        if debugMode and debugVerbose then
            KCxTranslatorAddLine("[KCX TRACE] after phraseWithRemainder result=" .. tostring(phraseTranslation), "debug")
        end
        if phraseTranslation then
            info.phraseResult = "hit"
            info.severity = "PHRASE"
            info.confidence = phraseConfidence
            info.reason = "phrase + remainder assembly"
            local finalOut = polishTranslatedOutput(phraseTranslation)
            if debugMode and debugVerbose then
                local loweredInput = normalizeLookupText(preprocessed)
                if string.find(loweredInput, "quick run", 1, true)
                    and string.find(loweredInput, "need summon", 1, true)
                    and string.find(loweredInput, "raid", 1, true) then
                    local loweredResult = string.lower(tostring(finalOut or ""))
                    if string.find(loweredResult, "%[quick%]") or string.find(loweredResult, "correr", 1, true)
                        or string.find(loweredResult, "necesitar", 1, true) or string.find(loweredResult, "invocar", 1, true)
                        or string.find(loweredResult, "banda", 1, true) then
                        KCxTranslatorAddLine("[KCX TRACE] BAD FALLBACK LEAK result=" .. tostring(finalOut), "debug")
                    end
                end
                KCxTranslatorAddLine("[KCX TRACE] final translateDetailed result=" .. tostring(finalOut), "debug")
            end
            return finalOut, info
        end
        info.phraseResult = "miss"
    end

    if allowWordFallback then
        if info.wordCount >= 3 then
            local words = splitWords(normalizeLookupText(preprocessed))
            local rebuilt = {}
            local i = 1
            local matchedChunks = 0
            local chunkDetails = {}
            while i <= #words do
                local consumed = 1
                local translatedChunk = nil
                for n = math.min(4, #words - i + 1), 2, -1 do
                    local candidate = table.concat(words, " ", i, i + n - 1)
                    translatedChunk = translateExactLookup(candidate)
                    if translatedChunk then
                        consumed = n
                        break
                    end
                end
                if not translatedChunk and allowRelaxedManualFallback then
                    for n = math.min(2, #words - i + 1), 1, -1 do
                        local candidate = table.concat(words, " ", i, i + n - 1)
                        local relaxedChunk = manualRelaxedPhraseMap[candidate]
                        if relaxedChunk then
                            translatedChunk = relaxedChunk
                            consumed = n
                            break
                        end
                    end
                end
                if translatedChunk then
                    table.insert(rebuilt, translatedChunk)
                    matchedChunks = matchedChunks + 1
                    table.insert(chunkDetails, translatedChunk)
                else
                    local tokenResolved, tokenSource = resolveTokenWithFallback(words[i])
                    if tokenResolved then
                        table.insert(rebuilt, tokenResolved)
                        if tokenSource == "general" then
                            table.insert(chunkDetails, "g:" .. tokenResolved)
                        end
                    else
                        if allowRelaxedManualFallback then
                            table.insert(rebuilt, words[i])
                        else
                            table.insert(rebuilt, "[" .. words[i] .. "]")
                        end
                    end
                end
                i = i + consumed
            end
            if matchedChunks > 0 then
                local chunkOutput = table.concat(rebuilt, " ")
                if allowRelaxedManualFallback then
                    chunkOutput = normalizeManualConversationalOutput(chunkOutput)
                end
                info.chunkResult = "hit(" .. matchedChunks .. "): " .. table.concat(chunkDetails, " | ")
                info.severity = "PHRASE"
                info.confidence = math.min(0.90, 0.50 + (matchedChunks * 0.12))
                info.reason = "chunked phrase fallback"
                return polishTranslatedOutput(chunkOutput), info
            end
            info.chunkResult = "miss"
        end

        local wordTranslation, wordConfidence, reason, recognizedTokens, unknownTokens, partialMode = translateWordByWord(preprocessed, contextName)
        if wordTranslation then
            info.wordResult = "hit"
            info.severity = "WORD"
            info.confidence = wordConfidence
            info.reason = reason
            info.recognizedTokens = recognizedTokens or 0
            info.unknownTokens = unknownTokens or 0
            info.partialMode = partialMode and "on" or "off"
            local finalOut = polishTranslatedOutput(wordTranslation)
            if debugMode and debugVerbose then
                local loweredInput = normalizeLookupText(preprocessed)
                if string.find(loweredInput, "quick run", 1, true)
                    and string.find(loweredInput, "need summon", 1, true)
                    and string.find(loweredInput, "raid", 1, true) then
                    local loweredResult = string.lower(tostring(finalOut or ""))
                    if string.find(loweredResult, "%[quick%]") or string.find(loweredResult, "correr", 1, true)
                        or string.find(loweredResult, "necesitar", 1, true) or string.find(loweredResult, "invocar", 1, true)
                        or string.find(loweredResult, "banda", 1, true) then
                        KCxTranslatorAddLine("[KCX TRACE] BAD FALLBACK LEAK result=" .. tostring(finalOut), "debug")
                    end
                end
                KCxTranslatorAddLine("[KCX TRACE] final translateDetailed result=" .. tostring(finalOut), "debug")
            end
            return finalOut, info
        end

        info.wordResult = "miss"
        local failed = {}
        for w in string.gmatch(normalizeLookupText(preprocessed), "%S+") do
            local known = resolveTokenWithFallback(w) or protectedWowTerms[w]
            if not known then
                table.insert(failed, w)
            end
        end
        info.failedTokens = table.concat(failed, ",")
        info.reason = reason or info.reason
        info.confidence = wordConfidence or 0

        -- Final general dictionary fallback (lowest priority).
        local normalizedGeneral = normalizeLookupText(preprocessed)
        local out = {}
        local known = 0
        local total = 0
        local usedGeneral = 0
        for w in string.gmatch(normalizedGeneral, "%S+") do
            total = total + 1
            local tokenResolved, tokenSource = resolveTokenWithFallback(w)
            if tokenResolved then
                table.insert(out, tokenResolved)
                known = known + 1
                if tokenSource == "general" then
                    usedGeneral = usedGeneral + 1
                end
            else
                if allowRelaxedManualFallback then
                    table.insert(out, w)
                else
                    table.insert(out, "[" .. w .. "]")
                end
            end
        end

        if total > 0 and known > 0 then
            local generalConfidence = known / total
            if generalConfidence >= 0.60 then
                info.severity = "GENERAL"
                info.confidence = generalConfidence
                info.reason = "general dictionary fallback"
                info.generalHits = usedGeneral
                local finalOut = polishTranslatedOutput(table.concat(out, " "))
                if debugMode and debugVerbose then
                    KCxTranslatorAddLine("[KCX TRACE] final translateDetailed result=" .. tostring(finalOut), "debug")
                end
                return finalOut, info
            end

            -- Manual relaxed fallback for longer mixed sentences:
            -- return partial translation if at least two known tokens, or one important token.
            if allowRelaxedManualFallback then
                local importantHits = 0
                for w in string.gmatch(normalizedGeneral, "%S+") do
                    if importantFallbackTokens[w] then
                        importantHits = importantHits + 1
                    end
                end

                if known >= 2 or importantHits >= 1 then
                    local relaxedOutput = table.concat(out, " ")
                    relaxedOutput = normalizeManualConversationalOutput(relaxedOutput)
                    info.severity = "GENERAL"
                    info.confidence = math.max(0.30, math.min(0.55, generalConfidence))
                    info.reason = "manual relaxed general fallback"
                    info.generalHits = usedGeneral
                    info.importantHits = importantHits
                    info.partialMode = "on"
                    local finalOut = polishTranslatedOutput(relaxedOutput)
                    if debugMode and debugVerbose then
                        KCxTranslatorAddLine("[KCX TRACE] final translateDetailed result=" .. tostring(finalOut), "debug")
                    end
                    return finalOut, info
                end
            end
        end
    elseif info.wordCount > 8 then
        info.reason = "long message requires exact match"
    end

    if debugMode and debugVerbose then
        KCxTranslatorAddLine("[KCX TRACE] final translateDetailed result=nil", "debug")
    end
    return nil, info
end

local function translateText(text)
    local translated = translateDetailed(text, true, true, true)
    return translated
end

-- Exact-only plus safe word fallback (used by manual /kcxtsay sending).
local function translateExactText(text)
    local translated = translateDetailed(text, true, true, true)
    return translated
end

-- ----------------------------------------------------------------------------
-- Help menu
-- ----------------------------------------------------------------------------
local function printHelp()
    printInfo("==============================")
    printInfo("KCx Translator Commands")
    printInfo("==============================")
    printInfo("[Translation]")
    printInfo("/kcxt <text>")
    printInfo("/kcxt test")
    printInfo("/kcxt stats")
    printInfo("/kcxt copylast")
    printInfo("/kcxtsay g <text>")
    printInfo("Examples:")
    printInfo("* /kcxt need healer")
    printInfo("* /kcxt lfg heroic")
    printInfo("* /kcxt summon please")
    printInfo("[Window]")
    printInfo("/kcxt show")
    printInfo("/kcxt hide")
    printInfo("/kcxt clear")
    printInfo("/kcxt window")
    printInfo("[Debug]")
    printInfo("/kcxt debug on")
    printInfo("/kcxt debug off")
    printInfo("/kcxt debug verbose on")
    printInfo("/kcxt debug verbose off")
    printInfo("[Display]")
    printInfo("/kcxt timestamps on")
    printInfo("/kcxt timestamps off")
    printInfo("/kcxt incoming on")
    printInfo("/kcxt incoming off")
    printInfo("/kcxt channel all on|off")
    printInfo("/kcxt channel <name> on|off")
    printInfo("/kcxt channelnum 5 toggle")
    printInfo("/kcxt channels")
    printInfo("[Notes]")
    printInfo("* Local-only translation")
    printInfo("* No automatic chat sending")
    printInfo("* Blizzard-safe manual behavior")
    printInfo("* Use /kcxt window for buttons and translator history.")
    printInfo("* /kcxt channelnum 5 toggle - toggle numbered global channel /5")
    printInfo("* Global channel filtering works best with standard order: /1 General, /2 Trade, /3 LocalDefense, /4 WorldDefense, /5 LookingForGroup.")
    printInfo("* Built-in chats like /g, /p, /s, /y, /w are handled directly.")
end

-- ----------------------------------------------------------------------------
-- Slash command handler
-- ----------------------------------------------------------------------------
handleSlashCommand = function(msg)
    ensureIncomingDefaults()
    local input = normalizeText(msg)

    if input == "" or input == "help" then
        printHelp()
        return
    end

    if input == "on" then
        autoTranslateChat = true
        KCxTranslatorDB.incomingEnabled = true
        printInfo("Incoming local chat translation enabled.")
        return
    end

    if input == "off" then
        autoTranslateChat = false
        KCxTranslatorDB.incomingEnabled = false
        printInfo("Incoming local chat translation disabled.")
        return
    end

    if input == "incoming on" then
        autoTranslateChat = true
        KCxTranslatorDB.incomingEnabled = true
        printInfo("Incoming translation window feed enabled.")
        return
    end

    if input == "incoming off" then
        autoTranslateChat = false
        KCxTranslatorDB.incomingEnabled = false
        printInfo("Incoming translation window feed disabled.")
        return
    end

    if input == "channels" then
        local ec = KCxTranslatorDB.enabledChannels
        local ecn = KCxTranslatorDB.enabledChannelNumbers or {}
        printInfo("[KCx Channels]")
        printInfo("WHISPER: " .. (ec.WHISPER and "ON" or "OFF"))
        printInfo("PARTY: " .. (ec.PARTY and "ON" or "OFF"))
        printInfo("RAID: " .. (ec.RAID and "ON" or "OFF"))
        printInfo("GUILD: " .. (ec.GUILD and "ON" or "OFF"))
        printInfo("TRADE: " .. (ec.TRADE and "ON" or "OFF"))
        printInfo("GENERAL: " .. (ec.GENERAL and "ON" or "OFF"))
        printInfo("CHANNEL fallback: " .. (ec.CHANNEL and "ON" or "OFF"))
        printInfo("/1 GENERAL: " .. ((ecn[1] ~= false) and "ON" or "OFF"))
        printInfo("/2 TRADE: " .. ((ecn[2] ~= false) and "ON" or "OFF"))
        printInfo("/3 LOCALDEFENSE: " .. ((ecn[3] ~= false) and "ON" or "OFF"))
        printInfo("/4 WORLDDEFENSE: " .. ((ecn[4] ~= false) and "ON" or "OFF"))
        printInfo("/5 LOOKINGFORGROUP: " .. ((ecn[5] ~= false) and "ON" or "OFF"))
        return
    end

    local channelNumTarget, channelNumSwitch = string.match(input, "^channelnum%s+(%d+)%s+(on|off)$")
    if channelNumTarget and channelNumSwitch then
        local channelNumber = tonumber(channelNumTarget)
        if channelNumber and channelNumber >= 1 and channelNumber <= 8 then
            local enabled = (channelNumSwitch == "on")
            KCxTranslatorDB.enabledChannelNumbers[channelNumber] = enabled
            KCxTranslatorDB.enabledChannelNumbers[tostring(channelNumber)] = enabled
            printInfo("Incoming global channel /" .. channelNumber .. " " .. (enabled and "enabled." or "disabled."))
            return
        end
    end

    local channelNumToggle = string.match(input, "^channelnum%s+(%d+)%s+toggle$")
    if channelNumToggle then
        local channelNumber = tonumber(channelNumToggle)
        if channelNumber and channelNumber >= 1 and channelNumber <= 8 then
            local current = (KCxTranslatorDB.enabledChannelNumbers[channelNumber] ~= false)
            KCxTranslatorDB.enabledChannelNumbers[channelNumber] = not current
            KCxTranslatorDB.enabledChannelNumbers[tostring(channelNumber)] = not current
            printInfo("Incoming global channel /" .. channelNumber .. " " .. ((not current) and "enabled." or "disabled."))
            return
        end
    end

    local channelTarget, channelSwitch = string.match(input, "^channel%s+(%S+)%s+(on|off)$")
    if channelTarget and channelSwitch then
        local enabled = (channelSwitch == "on")
        if channelTarget == "all" then
            for key in pairs(KCxTranslatorDB.enabledChannels) do
                KCxTranslatorDB.enabledChannels[key] = enabled
            end
            for i = 1, 8 do
                KCxTranslatorDB.enabledChannelNumbers[i] = enabled
            end
            printInfo("All incoming channels " .. (enabled and "enabled." or "disabled."))
            return
        end
        local key = normalizeChannelName(channelTarget)
        KCxTranslatorDB.enabledChannels[key] = enabled
        local standardChannelNumber = standardChannelNumberForKey(key)
        if standardChannelNumber then
            KCxTranslatorDB.enabledChannelNumbers[standardChannelNumber] = enabled
        end
        printInfo("Incoming channel " .. key .. " " .. (enabled and "enabled." or "disabled."))
        return
    end

    local channelToggle = string.match(input, "^channel%s+(%S+)%s+toggle$")
    if channelToggle then
        local key = normalizeChannelName(channelToggle)
        local current = (KCxTranslatorDB.enabledChannels[key] ~= false)
        KCxTranslatorDB.enabledChannels[key] = not current
        local standardChannelNumber = standardChannelNumberForKey(key)
        if standardChannelNumber then
            KCxTranslatorDB.enabledChannelNumbers[standardChannelNumber] = current
        end
        printInfo("Incoming channel " .. key .. " " .. ((not current) and "enabled." or "disabled."))
        return
    end

    if input == "debug on" then
        debugMode = true
        printInfo("Debug mode enabled.")
        return
    end

    if input == "debug off" then
        debugMode = false
        printInfo("Debug mode disabled.")
        return
    end

    if input == "debug verbose on" then
        debugVerbose = true
        printInfo("Debug verbose enabled.")
        return
    end

    if input == "debug verbose off" then
        debugVerbose = false
        printInfo("Debug verbose disabled.")
        return
    end

    if input == "timestamps on" then
        KCxTranslatorDB.showTimestamps = true
        printInfo("Timestamps enabled.")
        return
    end

    if input == "timestamps off" then
        KCxTranslatorDB.showTimestamps = false
        printInfo("Timestamps disabled.")
        return
    end

    if input == "test" then
        local tests = {
            "where is tk now",
            "need food for raid tonight",
            "bs inc",
            "tk blargword now",
            "lfm kara",
            "need rez",
            "black temple tonight",
            "need summon to shattrath",
            "summon to tk now",
            "asdf qwer zxcv",
        }

        printInfo("[KCx Test]")
        for i, sample in ipairs(tests) do
            local translated, _ = translateDetailed(sample, true, true)
            printInfo(tostring(i) .. ". " .. sample)
            if translated then
                printInfo("-> " .. translated)
            else
                printInfo("-> No reliable translation found.")
            end
        end
        return
    end

    if input == "stats" then
        local gExactCount = 0
        local gCanonicalCount = 0
        for _ in pairs(generalExactLookup) do gExactCount = gExactCount + 1 end
        for _ in pairs(generalCanonicalLookup) do gCanonicalCount = gCanonicalCount + 1 end
        printInfo("[KCx Stats]")
        printInfo("Specialized Entries: " .. tostring(stats.specializedEntries))
        printInfo("General Entries: " .. tostring(stats.generalEntries))
        printInfo("Phrase Entries: " .. tostring(stats.phraseEntries))
        printInfo("Structured Entries: " .. tostring(stats.structuredEntries))
        printInfo("Shorthand Entries: " .. tostring(stats.shorthandEntries))
        printInfo("Social Entries: " .. tostring(stats.socialEntries))
        printInfo("Raid Entries: " .. tostring(stats.raidEntries))
        printInfo("PvP Entries: " .. tostring(stats.pvpEntries))
        printInfo("Skipped Overrides: " .. tostring(stats.generalSkippedOverrides))
        printInfo("Debug: " .. (debugMode and "ON" or "OFF"))
        printInfo("Debug Verbose: " .. (debugVerbose and "ON" or "OFF"))
        printInfo("Language Direction: Auto Detect")
        printInfo("Partial Translation: ON")
        printInfo("Confidence: High >= 70% | Partial >= 30%")
        printInfo("General Loaded Strings: " .. tostring(stats.generalLoadedStrings))
        printInfo("General Loaded Structured: " .. tostring(stats.generalLoadedStructured))
        printInfo("General Exact Lookups: " .. tostring(gExactCount))
        printInfo("General Canonical Lookups: " .. tostring(gCanonicalCount))
        printInfo("Test Suite: Available")
        return
    end

    if input == "copylast" then
        if lastTranslatedText and lastTranslatedText ~= "" then
            copyToTranslatorBox(lastTranslatedText)
            printInfo("Copied last translation to copy box.")
        else
            printInfo("No translation available to copy yet.")
        end
        return
    end

    if input == "window" then
        if not translatorWindow then
            createTranslatorWindow()
        end
        if translatorWindow:IsShown() then
            translatorWindow:Hide()
            KCxTranslatorDB.windowShown = false
        else
            translatorWindow:Show()
            KCxTranslatorDB.windowShown = true
        end
        return
    end

    if input == "show" then
        if not translatorWindow then
            createTranslatorWindow()
        end
        translatorWindow:Show()
        KCxTranslatorDB.windowShown = true
        return
    end

    if input == "hide" then
        if translatorWindow then
            translatorWindow:Hide()
        end
        KCxTranslatorDB.windowShown = false
        return
    end

    if input == "clear" then
        if not translatorWindow then
            createTranslatorWindow()
        end
        if translatorLog then
            translatorLog:Clear()
        end
        return
    end

    -- Manual outgoing helper: translate and print only.
    local translated, info = translateDetailed(msg, true, true, true)
    debugTranslation(info)
    if translated then
        local stripped = stripChatChannelPrefix(msg)
        printSuccess(stripped .. "\n" .. "-> " .. translated)
    else
        printError("No translation found.")
    end
end

-- ----------------------------------------------------------------------------
-- Manual translated send command handler (/kcxtsay)
-- ----------------------------------------------------------------------------
-- This is strictly user-initiated:
-- - It never auto-replies.
-- - It never sends incoming translations.
-- - It only sends when user explicitly runs /kcxtsay.
local function handleSlashSayCommand(msg)
    local trimmed = tostring(msg or "")
    trimmed = string.gsub(trimmed, "^%s+", "")
    trimmed = string.gsub(trimmed, "%s+$", "")

    if trimmed == "" then
        printInfo("Usage: /kcxtsay <party|p|say|s|guild|g|raid|r|yell|y|whisper|w> <message>")
        return
    end

    local channelInput, rest = string.match(trimmed, "^(%S+)%s+(.+)$")
    if not channelInput or not rest then
        printInfo("Usage: /kcxtsay <party|p|say|s|guild|g|raid|r|yell|y|whisper|w> <message>")
        return
    end

    channelInput = string.lower(channelInput)

    local sendChannel = nil
    local translated = nil
    local whisperTarget = nil
    local originalMessage = nil

    if channelInput == "party" or channelInput == "p" then
        sendChannel = "PARTY"
        originalMessage = rest
        translated = translateExactText(rest)
    elseif channelInput == "say" or channelInput == "s" then
        sendChannel = "SAY"
        originalMessage = rest
        translated = translateExactText(rest)
    elseif channelInput == "guild" or channelInput == "g" then
        sendChannel = "GUILD"
        originalMessage = rest
        translated = translateExactText(rest)
    elseif channelInput == "raid" or channelInput == "r" then
        sendChannel = "RAID"
        originalMessage = rest
        translated = translateExactText(rest)
    elseif channelInput == "yell" or channelInput == "y" then
        sendChannel = "YELL"
        originalMessage = rest
        translated = translateExactText(rest)
    elseif channelInput == "whisper" or channelInput == "w" then
        local target, whisperMessage = string.match(rest, "^(%S+)%s+(.+)$")
        if not target or not whisperMessage then
            printInfo("Usage: /kcxtsay whisper PlayerName <message>")
            return
        end
        sendChannel = "WHISPER"
        whisperTarget = target
        originalMessage = whisperMessage
        translated = translateExactText(whisperMessage)
    else
        printInfo("Unknown channel. Use party/p, say/s, guild/g, raid/r, yell/y, whisper/w.")
        return
    end

    if not translated then
        printError("No translation found.\nNot sending.")
        return
    end

    local finalizedTranslation = translated

    if debugMode and debugVerbose then
        KCxTranslatorAddLine("[KCX TRACE] kcxtsay preview=" .. tostring(finalizedTranslation), "debug")
    end

    -- Manual send only. Called exclusively from /kcxtsay.
    if sendChannel == "WHISPER" then
        if debugMode and debugVerbose then
            KCxTranslatorAddLine("[KCX TRACE] kcxtsay send=" .. tostring(finalizedTranslation), "debug")
        end
        SendChatMessage(finalizedTranslation, sendChannel, nil, whisperTarget)
        printSuccess(originalMessage .. "\n" .. "-> " .. finalizedTranslation)
    else
        if debugMode and debugVerbose then
            KCxTranslatorAddLine("[KCX TRACE] kcxtsay send=" .. tostring(finalizedTranslation), "debug")
        end
        SendChatMessage(finalizedTranslation, sendChannel)
        printSuccess(originalMessage .. "\n" .. "-> " .. finalizedTranslation)
    end
end

-- ----------------------------------------------------------------------------
-- Incoming chat translation handler
-- ----------------------------------------------------------------------------
local chatEvents = {
    CHAT_MSG_WHISPER = true,
    CHAT_MSG_BN_WHISPER = true,
    CHAT_MSG_SAY = true,
    CHAT_MSG_YELL = true,
    CHAT_MSG_GUILD = true,
    CHAT_MSG_OFFICER = true,
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_INSTANCE_CHAT = true,
    CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_BATTLEGROUND = true,
    CHAT_MSG_BATTLEGROUND_LEADER = true,
    CHAT_MSG_CHANNEL = true,
}

local frame = CreateFrame("Frame")
local function safeRegisterEvent(targetFrame, eventName)
    if not targetFrame or not eventName then
        return
    end
    local ok = pcall(targetFrame.RegisterEvent, targetFrame, eventName)
    if not ok and debugMode then
        printInfo("Skipped unsupported event: " .. tostring(eventName))
    end
end

for eventName in pairs(chatEvents) do
    if eventName ~= "CHAT_MSG_BATTLEGROUND_LEADER" then
        safeRegisterEvent(frame, eventName)
    end
end

ensureIncomingDefaults()
autoTranslateChat = KCxTranslatorDB.incomingEnabled and true or false
createMinimapButton()
if KCxTranslatorDB.hideChannelSetupHelp ~= true then
    showChannelSetupHelp()
end

frame:SetScript("OnEvent", function(_, event, message, sender, languageName, channelDisplayName, target, flags, channelNumberArg, channelNameArg)
    ensureIncomingDefaults()
    if not autoTranslateChat or not KCxTranslatorDB.incomingEnabled then
        return
    end
    local channelKey, channelNumber, channelName = resolveIncomingChannel(event, channelDisplayName, channelNumberArg, channelNameArg)
    if event == "CHAT_MSG_CHANNEL" and not channelNumber then
    local parsedNumber =
    tonumber(channelNumberArg)
    or tonumber(string.match(tostring(channelDisplayName or ""), "^(%d+)"))
    or tonumber(string.match(tostring(channelDisplayName or ""), "%[(%d+)"))
    or tonumber(string.match(tostring(channelDisplayName or ""), "(%d+)%."))
    if parsedNumber then
        channelNumber = parsedNumber
    end
end
    if not channelKey then
        return
    end

    local enabledChannels = KCxTranslatorDB.enabledChannels or {}
    local enabledChannelNumbers = KCxTranslatorDB.enabledChannelNumbers or {}
    local allowed = false
    if event == "CHAT_MSG_CHANNEL" then
        local n = tonumber(channelNumber)
        if n then
            allowed =
            (enabledChannelNumbers[n] == true)
            or
            (enabledChannelNumbers[tostring(n)] == true)
        elseif channelKey then
            allowed = (enabledChannels[channelKey] == true)
        end
    elseif channelKey then
        allowed = (enabledChannels[channelKey] == true)
    end

    if not allowed then
        if debugMode then
            print("KCx blocked: event=" .. tostring(event) .. " key=" .. tostring(channelKey) .. " num=" .. tostring(channelNumber))
        end
        return
    end

    local displayChannel = channelKey
    local publicSpanishDetected = false
    if event == "CHAT_MSG_CHANNEL" then
        if debugMode and debugVerbose then
            KCxTranslatorAddLine(
                "event: " .. tostring(event) ..
                " channelKey: " .. tostring(channelKey) ..
                " channelNumber: " .. tostring(channelNumber) ..
                " channelName: " .. tostring(channelName) ..
                " allowed: " .. tostring(allowed),
                "debug"
            )
        end

        local loweredChannelName = string.lower(tostring(channelName or ""))
        if string.find(loweredChannelName, "layer", 1, true) then
            if not channelNumber or KCxTranslatorDB.enabledChannelNumbers[channelNumber] ~= true then
                if debugMode then print("KCx skipped: channel disabled " .. tostring(channelKey)) end
                return
            end
        end

        if isPublicChannelKey(channelKey) then
            if string.len(tostring(message or "")) > (KCxTranslatorDB.maxTradeLength or 180) then
                if debugMode then print("KCx public skipped: too long") end
                return
            end
            if KCxTranslatorDB.skipHyperlinkHeavyMessages then
                local hLinks = countPattern(message, "|H")
                local bracketed = countPattern(message, "%b[]")
                if hLinks > 3 or bracketed > 6 then
                    if debugMode then print("KCx public skipped: too many links") end
                    return
                end
            end
            local now = GetTime and GetTime() or 0
            if (now - incomingPublicThrottle.windowStart) >= 1 then
                incomingPublicThrottle.windowStart = now
                incomingPublicThrottle.count = 0
            end
            incomingPublicThrottle.count = incomingPublicThrottle.count + 1
            if incomingPublicThrottle.count > (KCxTranslatorDB.maxChannelMessagesPerSecond or 2) then
                if debugMode then print("KCx public skipped: throttle") end
                return
            end
        end

        if not hasLikelySpanishPublicContent(message) then
            if debugMode then
                print("KCx public skipped: no Spanish detected")
            end
            return
        end
        publicSpanishDetected = true
    else
        if debugMode and debugVerbose then
            KCxTranslatorAddLine(
                "event: " .. tostring(event) ..
                " channelKey: " .. tostring(channelKey) ..
                " channelNumber: nil" ..
                " channelName: " .. tostring(channelName) ..
                " allowed: " .. tostring(allowed),
                "debug"
            )
        end
    end

    if debugMode then
        print("KCx translating: " .. tostring(channelKey))
    end
    if isLikelyGarbage(message) then
        return
    end
    if isDuplicateRecent(channelKey, sender, message) then
        return
    end
    local translated = nil
    local info = nil
    local spanishAssist = nil
    local spanishDetectedCount = 0
    local protectedSkippedCount = 0

    if event == "CHAT_MSG_CHANNEL" then
        local englishCommonCount = 0
        spanishAssist, spanishDetectedCount, protectedSkippedCount, englishCommonCount = translateSpanishSegmentsOnly(message)
        if not spanishAssist or spanishDetectedCount <= 0 then
            if debugMode and debugVerbose then
                KCxTranslatorAddLine("skipped: insufficient Spanish confidence in public channel", "debug")
                KCxTranslatorAddLine("Spanish confident token count: " .. tostring(spanishDetectedCount or 0), "debug")
                KCxTranslatorAddLine("protected token count: " .. tostring(protectedSkippedCount or 0), "debug")
                KCxTranslatorAddLine("English/common token count: " .. tostring(englishCommonCount or 0), "debug")
            end
            return
        end
        if debugMode then
            print("KCx path: public Spanish-segment mode")
            if debugVerbose then
                KCxTranslatorAddLine("Spanish tokens detected count: " .. tostring(spanishDetectedCount), "debug")
                KCxTranslatorAddLine("skipped protected tokens count: " .. tostring(protectedSkippedCount), "debug")
            end
        end
    else
        translated, info = translateDetailed(message, true, true)
        debugTranslation(info)
    end

    if (spanishAssist and spanishDetectedCount > 0) or (translated and info and (tonumber(info.confidence or 0) >= 0.30)) then
        local ts = date("%H:%M")
        local head = "[" .. ts .. "][" .. displayChannel .. "]"
        if publicSpanishDetected then
            head = head .. "[SPANISH DETECTED]"
        end
        if KCxTranslatorDB.showConfidence and info then
            local cLabel = confidenceLabel(info.confidence)
            head = head .. "[" .. cLabel .. "]"
        end
        local block = nil
        if spanishAssist and spanishDetectedCount > 0 then
            block = head .. "\nOriginal:\n" .. tostring(message or "") .. "\n\nSpanish Assist:\n" .. tostring(spanishAssist or "")
        else
            block = head .. "\nOriginal:\n" .. tostring(message or "") .. "\n\nTranslated:\n" .. tostring(translated or "")
        end
        KCxTranslatorAddLine(block, "info")
    end
end)

-- Register EXACT slash commands requested.
SLASH_KCXTRANSLATOR1 = "/kcxt"
SLASH_KCXTRANSLATOR2 = "/KCXT"
SLASH_KCXTRANSLATOR3 = "/KCxt"
SlashCmdList["KCXTRANSLATOR"] = handleSlashCommand

SLASH_KCXTRANSLATORSAY1 = "/kcxtsay"
SlashCmdList["KCXTRANSLATORSAY"] = handleSlashSayCommand

-- Startup message
DEFAULT_CHAT_FRAME:AddMessage(COLOR_YELLOW .. ADDON_NAME .. ": " .. COLOR_RESET .. "Loaded. Type /kcxt help for commands.")
