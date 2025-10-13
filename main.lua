-- CorruptedLootCouncil.lua - WoW 1.12 (Lua 5.0) compatible, using SendAddonMessage

------------------------------------------------------------
-- SavedVariables / Defaults
------------------------------------------------------------
local CLC_ITEM_RARITY_DECLARATION = 4
-- Minimale Raidgröße, damit das Addon aktiv ist (z. B. 15 = nur K40)
local MIN_RAID_SIZE = 2

local ADDON = "CorruptedLootCouncil"
CLC_DB = CLC_DB or {
  zones = {
  ["Tower of Karazhan"] = true,
  ["The Rock of Desolation"] = true,
  ["Rock of Desolation"] = true,
  },
  itemWhitelist = {
  ["Carapace Handguards"] = true,
  ["Gloves of the Primordial Burrower"] = true,
  ["Badge of the Swarmguard"] = true,
  ["Eyestalk Waist Cord"] = true,
  ["Yshgo'lar, Cowl of Fanatical Devotion"] = true,
  ["Spotted Qiraji Battle Tank"] = true,
  ["Kiss of the Spider"] = true,
  ["Cloak of the Necropolis"] = true,
  ["Slayer's Crest"] = true,
  ["The Restrained Essence of Sapphiron"] = true,
  ["Hammer of the Twisting Nether"] = true,
  ["Plagues Riding Spider"] = true,
  ["Emerald Drake"] = true,
  ["Formula: Eternal Dreamstone Shard"] = true,
  ["Tiny Warp Stalker"] = true,
  -- TESTING
  ["Wool Cloth"] = true,
  },
  meta = CLC_DB and CLC_DB.meta or {
    zonesVersion = 1,
    acceptZonePush = true,
  },
  councilRanks = {
    ["Officer"] = true,
    ["Offizier"] = true,
    ["Bereichsleitung"] = true,
  },
  rankRaidTwink = CLC_DB and CLC_DB.rankRaidTwink or {
	["Arather"]=true, -- Celebrindal
	 -- Dresche
	 -- Xarak
	["Jimbowf"]=true, -- Jimbo
	 -- Enturius
	["Vaschar"]=true, -- Vascher
	["Leelooh"]=true, -- Gutschy
	["Shiranola"]=true, -- Sarungal
	["Thymae"]=true, -- Ariestelle
	["Yatamo"]=true, -- Yaijin
	["Zacki"]=true, -- Zacka
	["Sheeld"]=true, -- Sheed
  },
  rankTwink     = CLC_DB and CLC_DB.rankTwink     or {
	["Velaria"]=true, -- Celebrindal
	["Takumo"]=true, -- Celebrindal
	["Finkle"]=true, -- Celebrindal
	["Tinnuviel"]=true, -- Celebrindal
	["Kessie"]=true, -- Celebrindal
	["Minidresche"]=true, -- Dresche
	["Smashhead"]=true, -- Xarak
	["Mowlwurph"]=true, -- Jimbo
	["Jimdrood"]=true, -- Jimbo
	["Jimbohunt"]=true, -- Jimbo
	["Holyjimbo"]=true, -- Jimbo
	-- Enturius
	["Vischa"]=true, -- Vascher
	["Vaschi"]=true, -- Vascher
	["Vasch"]=true, -- Vascher
	["Huntersolo"]=true, -- Gutschy
	["Xaraahlai"]=true, -- Gutschy
	["Leeloohh"]=true, -- Gutschy
	["Silverwrath"]=true, -- Sarungal
	["Summergale"]=true, -- Sarungal
	["Zaark"]=true, -- Ariestelle
	["Napok"]=true, -- Ariestelle
	["Borgan"]=true, -- Ariestelle
	["Deadra"]=true, -- Ariestelle
	["Tamyo"]=true, -- Yaijin
	["Yok"]=true, -- Yaijin
	["Zaggus"]=true, -- Zacka
	["Nornson"]=true, -- Zacka
	["Jackrackham"]=true, -- Zacka
	["Whalla"]=true, -- Zacka
	["Sheedt"]=true, -- Sheed
	["Shead"]=true, -- Sheed
	["Sheedtha"]=true, -- Sheed
	["Bulco"]=true, -- Sheed
  },
  lootDuration = 60,
  ui = {
    anchor = { point="CENTER", rel="CENTER", x=0, y=0 },
    officer = { point="CENTER", rel="CENTER", x=0, y=0 },
    ml      = { point="TOPRIGHT", rel="TOPRIGHT", x=-40, y=-160 },
  },
}

-- robust initialisieren
function CLC_EnsureDB()
  CLC_DB = CLC_DB or {}
  CLC_DB.zones = CLC_DB.zones or {}
  CLC_DB.itemWhitelist = CLC_DB.itemWhitelist or {}
  CLC_DB.councilRanks = CLC_DB.councilRanks or {}
  CLC_DB.rankRaidTwink = CLC_DB.rankRaidTwink or {}
  CLC_DB.rankTwink     = CLC_DB.rankTwink     or {}
  CLC_DB.meta = CLC_DB.meta or {}
  if CLC_DB.meta.zonesVersion == nil then CLC_DB.meta.zonesVersion = 1 end
  if CLC_DB.meta.acceptZonePush == nil then CLC_DB.meta.acceptZonePush = true end
  if CLC_DB.lootDuration == nil then CLC_DB.lootDuration = 45 end
  CLC_DB.ui = CLC_DB.ui or {
    anchor  = { point="CENTER",   rel="CENTER",   x=0,   y=0   },
    officer = { point="CENTER",   rel="CENTER",   x=0,   y=0   },
    ml      = { point="TOPRIGHT", rel="TOPRIGHT", x=-40, y=-160 },
  }
end
CLC_EnsureDB()

------------------------------------------------------------
-- State & Frame
------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("VARIABLES_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOOT_METHOD_CHANGED")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("RAID_ROSTER_UPDATE")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_INDOORS")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

CLC_IsRaid = false
CLC_InAllowedZone = true
CLC_SessionActive = false

-- Antworten je Item: key -> { {name=, choice=, comment=, roll=} ... }
CLC_Responses = {}
CLC_Items = {}
CLC_Votes = {}

CLC_OfficerIndex = 1
CLC_ItemWindows = {}
CLC_AnchorFrame = nil
CLC_EditSeq = CLC_EditSeq or 0

-- Pending Rolls (echte Chat-Rolls abwarten)
CLC_PendingRollQueues = CLC_PendingRollQueues or { ["1-10"] = {}, ["1-100"] = {} }

------------------------------------------------------------
-- Utils (Lua 5.0 safe)
------------------------------------------------------------
local function tlen(t) return table.getn(t) end
local function now() return time() end
local function playerName() local n=UnitName("player"); return n or "?" end
local function isRaid() return GetNumRaidMembers() and GetNumRaidMembers() > 0 end

-- Ersatz für string.match (Lua 5.0 hat oft kein .match)
local function SMATCH(str, pattern)
  local a,b,c,d,e,f,g,h,i,j = string.find(str, pattern)
  return c,d,e,f,g,h,i,j
end

-- true, wenn die Zonen-Whitelist mindestens einen Eintrag hat
local function hasZoneWhitelist()
  if not CLC_DB or not CLC_DB.zones then return false end
  local k,v
  for k,v in pairs(CLC_DB.zones) do
    if v then return true end
  end
  return false
end

local function raidHasEnoughPlayers()
  -- In 1.12 gibt es kein IsInRaid(), daher nutzen wir GetNumRaidMembers()
  local n = GetNumRaidMembers() or 0
  return n >= MIN_RAID_SIZE
end

-- Whitelist-Logik: leer => überall erlaubt, sonst nur erlaubte Zonen
local function inAllowedZone()
  local z = GetRealZoneText()
  if not z or not hasZoneWhitelist() then
    return true
  end
  return CLC_DB.zones[z] == true
end

local function itemKeyFromLink(link) return link or "?" end

-- Chat-Safety (gegen CTL)
function CLC_EscapeChat(msg)
  if not msg then return "" end
  msg = string.gsub(msg, "|", "||")
  msg = string.gsub(msg, "%c", "")
  if string.len(msg) > 240 then msg = string.sub(msg, 1, 240) end
  return msg
end

function CLC_ItemTextFromLink(link)
  if not link then return "[]" end
  local name = SMATCH(link, "%[([^%]]+)%]")
  if name then return "["..name.."]" end
  return tostring(link)
end

-- Backdrop helper
local function ApplyDialogBackdrop(f)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
  })
end

-- Saved positions
local function SavePos(frameRef, slot)
  CLC_EnsureDB()
  local p, _, rp, x, y = frameRef:GetPoint(1)
  if not CLC_DB.ui then CLC_DB.ui = {} end
  CLC_DB.ui[slot] = {
    point = p or "CENTER",
    rel   = rp or "CENTER",
    x     = math.floor((x or 0)+0.5),
    y     = math.floor((y or 0)+0.5),
  }
end

local function RestorePos(frameRef, slot, defaultPoint, defaultRel, dx, dy)
  CLC_EnsureDB()
  if not CLC_DB.ui then CLC_DB.ui = {} end
  local s = CLC_DB.ui[slot] or { point=defaultPoint, rel=defaultRel, x=dx, y=dy }
  frameRef:ClearAllPoints()
  frameRef:SetPoint(s.point or defaultPoint, UIParent, s.rel or defaultRel, s.x or dx, s.y or dy)
end

------------------------------------------------------------
-- Ränge / Council
------------------------------------------------------------
local function refreshGuildRoster() GuildRoster() end

local function getGuildRankByRoster(name)
  local num = GetNumGuildMembers()
  if not num or num <= 0 then return "" end
  local i
  for i=1, num do
    local fullName, rankName = GetGuildRosterInfo(i)
    if fullName and fullName == name then return rankName or "" end
  end
  return ""
end

local function getGuildRank(name)
  local r = getGuildRankByRoster(name)
  if r ~= "" then return r end
  local i
  for i=1, GetNumRaidMembers() do
    local unit = "raid"..i
    if UnitName(unit) == name then
      local g, rname = GetGuildInfo(unit)
      return rname or ""
    end
  end
  if name == playerName() then
    local g, rname = GetGuildInfo("player")
    return rname or ""
  end
  return ""
end

-- Sichtbarer Rang im Officer-Panel:
-- 1) Whitelists zuerst (Raid Twink / Twink)
-- 2) "Raider Veteran" -> "Raider"
-- 3) Council-Ränge -> "Raider"
local function getDisplayRank(name)
  if CLC_DB.rankRaidTwink and CLC_DB.rankRaidTwink[name] then
    return "Raid Twink"
  end
  if CLC_DB.rankTwink and CLC_DB.rankTwink[name] then
    return "Twink"
  end
  local r = getGuildRank(name) or ""
  if r == "Raider Veteran" then
    return "Raider"
  end
  if r ~= "" and CLC_DB.councilRanks and CLC_DB.councilRanks[r] then
    return "Raider"
  end
  return r
end

-- Wer darf das Officer-Panel sehen (wie von dir gewünscht: kein Raider Veteran; RL/RA erlaubt)
local function isCouncil(name)
  local i
  for i=1, GetNumRaidMembers() do
    local unit = "raid"..i
    local uname = UnitName(unit)
    if uname == name then
      local gname, rank = GetGuildInfo(unit)
      local isLead = IsRaidLeader(unit)
      local isAssist = IsRaidOfficer(unit)
      if rank == "Raider Veteran" then
        return (isLead or isAssist) and true or false
      end
      if rank and CLC_DB.councilRanks and CLC_DB.councilRanks[rank] then
        return true
      end
      if isLead or isAssist then return true end
      return false
    end
  end
  if name == playerName() then
    local gname, rank = GetGuildInfo("player")
    if rank == "Raider Veteran" then return false end
    if rank and CLC_DB.councilRanks and CLC_DB.councilRanks[rank] then return true end
  end
  return false
end

------------------------------------------------------------
-- AddonMessage
------------------------------------------------------------
if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix("CLC") end
local function CLC_Send(tag, payload)
  local body = tag.."^"..(payload or "")
  if isRaid() then SendAddonMessage("CLC", body, "RAID") else SendAddonMessage("CLC", body, "PARTY") end
end

------------------------------------------------------------
-- Loot-Trigger-Rechte
------------------------------------------------------------
local function PlayerIsMasterLooter()
  local method, mlParty, mlRaid = GetLootMethod()
  if method ~= "master" then return false end
  if mlRaid then
    return UnitIsUnit("raid"..mlRaid, "player")
  elseif mlParty ~= nil then
    if mlParty == 0 then return true end -- 0 = du selbst
    return UnitIsUnit("party"..mlParty, "player")
  end
  return false
end

local function CanPlayerTriggerLoot()
  local method = select(1, GetLootMethod())
  if method == "master" then
    return PlayerIsMasterLooter()
  else
    -- Fallback: Nur der Raidlead darf auslösen, wenn kein Master Loot aktiv ist
    return IsRaidLeader()
  end
end

------------------------------------------------------------
-- Session & Loot-Scan
------------------------------------------------------------
local function isEpicOrWhitelisted(slot)
  local texture, name, qty, quality = GetLootSlotInfo(slot)
  if not name then return false end
  if CLC_DB.itemWhitelist[name] then return true end
  if quality and quality >= CLC_ITEM_RARITY_DECLARATION then return true end
  return false
end

local function endSession()
  if CLC_SessionActive then
    CLC_SessionActive = false
    CLC_Send("SESSION_END", playerName())
  end
end

local function startSessionIfNeeded()
  if not CLC_SessionActive then
    CLC_SessionActive = true
    CLC_Items, CLC_Responses, CLC_Votes = {}, {}, {}
    CLC_Send("SESSION_START", playerName())
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00"..ADDON.."|r: Loot-Session gestartet.")
  end
end

local function collectQualifyingLoot()
  local out = {}
  local i
  for i=1, GetNumLootItems() do
    if isEpicOrWhitelisted(i) then
      local tex = select(1, GetLootSlotInfo(i))
      local link = GetLootSlotLink(i)
      if link then table.insert(out, { link=link, tex=tex }) end
    end
  end
  return out
end

function CLC_BroadcastLoot()
  if not raidHasEnoughPlayers() then return end
  if CLC_SessionActive then return end
  if not CLC_IsRaid then return end
  if not CanPlayerTriggerLoot() then return end

  local items = collectQualifyingLoot()
  if tlen(items) == 0 then return end

  -- Außerhalb erlaubter Zonen: NUR Whitelist-Items anzeigen (auch wenn Epics dabei sind)
  if not CLC_InAllowedZone then
    local filtered = {}
    local i
    for i=1, tlen(items) do
      local link = items[i].link
      local name = link and SMATCH(link, "%[([^%]]+)%]")
      if name and CLC_DB.itemWhitelist[name] then
        table.insert(filtered, items[i])
      end
    end
    items = filtered
    if tlen(items) == 0 then return end
  end

  startSessionIfNeeded()
  local i
  for i=1, tlen(items) do
    CLC_Send("ITEM", items[i].link.."^"..(items[i].tex or ""))
  end
  -- ML-Panel nur zeigen, wenn ich wirklich ML bin (oder RL ohne master)
  if CanPlayerTriggerLoot() then
    CLC_ShowMLFrame()
  end
end

function CLC_UpdateAnnouncedRow(playerName, choice)
    if not CLC_RowFrames then return end
    -- alte grün markierte Zeile zurücksetzen
    if CLC_LastAnnouncedRow then
        local row = CLC_LastAnnouncedRow
        row:SetBackdropColor(0,0,0,0)
        row.nameFS:SetTextColor(1,1,1)
        row.choiceFS:SetTextColor(1,1,1)
        row.rankFS:SetTextColor(1,1,1)
        row.commentFS:SetTextColor(1,1,1)
    end

    for _, row in ipairs(CLC_RowFrames) do
        local rowName = row.nameFS:GetText() or ""
        local rowChoice = row.choiceFS:GetText() or ""

        -- Extrahiere nur den reinen Choice-Text (vor Klammern)
        local pureChoice = string.match(rowChoice, "^[^(]+") or rowChoice
        pureChoice = pureChoice:gsub("%s+$","") -- trim

        local cleanChoice = choice:gsub("%s+$","") -- trim Announce-Choice

        if rowName == playerName and pureChoice == cleanChoice then
            row:SetBackdropColor(0,0.6,0,0.5)  -- grün
            row.nameFS:SetTextColor(1,1,1)
            row.choiceFS:SetTextColor(1,1,1)
            row.rankFS:SetTextColor(1,1,1)
            row.commentFS:SetTextColor(1,1,1)
            CLC_LastAnnouncedRow = row
            break
        end
    end
end

------------------------------------------------------------
-- Loot-Anker
------------------------------------------------------------
local function EnsureAnchor()
  if CLC_AnchorFrame then return end
  local f = CreateFrame("Frame", "CLC_Anchor", UIParent)
  f:SetWidth(140); f:SetHeight(28); f:SetFrameStrata("DIALOG"); ApplyDialogBackdrop(f)
  local label=f:CreateFontString(nil,"OVERLAY","GameFontNormal"); label:SetPoint("CENTER", f, "CENTER", 0, 0); label:SetText("CLC Loot-Anker")
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function() this:StopMovingOrSizing(); SavePos(this, "anchor") end)
  RestorePos(f, "anchor", "CENTER", "CENTER", 0, 0); f:Hide()
  CLC_AnchorFrame = f
end
local function ShowAnchor() EnsureAnchor(); CLC_AnchorFrame:Show() end
local function HideAnchor() if CLC_AnchorFrame then CLC_AnchorFrame:Hide() end end
local function ResetAnchor() EnsureAnchor(); CLC_DB.ui.anchor={point="CENTER",rel="CENTER",x=0,y=0}; RestorePos(CLC_AnchorFrame,"anchor","CENTER","CENTER",0,0) end

------------------------------------------------------------
-- Loot-Popup (draggable, kompakt, Roll-Buttons)
------------------------------------------------------------
local function CLC_CloseItemWindow(key) local f=CLC_ItemWindows[key]; if f then f:Hide(); CLC_ItemWindows[key]=nil end end

local function CLC_SendResponse(key, choice, comment, roll)
  if not choice then choice="PASS" end
  if not comment then comment="" end
  if not roll then roll="" end
  local payload = key.."^"..playerName().."^"..choice.."^"..comment.."^"..tostring(roll)
  CLC_Send("RESPONSE", payload)
end

local function CLC_SortOrder(choice)
  if choice=="TMOG" then return 1 end
  if choice=="BIS" then return 2 end
  if choice=="UPGRADE" then return 3 end
  if choice=="OS+" then return 4 end
  if choice=="OS" then return 5 end
  if choice=="ROLL" then return 6 end
  return 99
end

local function PositionLootWindow(f, idx)
  EnsureAnchor()
  local s = CLC_DB.ui.anchor or { point="CENTER", rel="CENTER", x=0, y=0 }
  f:ClearAllPoints()
  local y = (s.y or 0) - (idx - 1) * (f:GetHeight() + 8)
  f:SetPoint(s.point or "CENTER", UIParent, s.rel or "CENTER", s.x or 0, y)
end

local function CLC_CreateItemWindow(itemLink, iconTex)
  local key = itemKeyFromLink(itemLink)
  if CLC_ItemWindows[key] then CLC_CloseItemWindow(key) end

  local f = CreateFrame("Frame", "CLC_ItemWin_"..tostring(now()), UIParent)
  f:SetWidth(380); f:SetHeight(150); f:SetFrameStrata("DIALOG"); ApplyDialogBackdrop(f)

  -- Close-Button (X) oben rechts: entspricht "Pass"
  local closeX = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  closeX:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  closeX:SetScript("OnClick", function() CLC_SendResponse(key, "PASS", ""); CLC_CloseItemWindow(key) end)

  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop",  function() this:StopMovingOrSizing() end)
  f:SetClampedToScreen(true)


  -- Buttons kompakt in 2 Reihen
  local function mkBtn(label, x, y, w)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetText(label); b:SetWidth(w or 60); b:SetHeight(20); b:SetPoint("TOPLEFT", f, "TOPLEFT", x, y); return b
  end
  local bBiS  = mkBtn("BiS",     14, -46)
  local bUpg  = mkBtn("Upgrade", 14+64, -46, 76)
  local bOSp  = mkBtn("OS+",     14+64+84, -46)
  local bOS   = mkBtn("OS",      14+64+84+64, -46)
  local bTM   = mkBtn("TMOG",    14, -46-24, 76)
  local bRoll = mkBtn("Roll",    14+84, -46-24, 60)
  local bPass = mkBtn("Pass",    14+84+68, -46-24, 60)

  -- Kommentar rechts, tiefer
  CLC_EditSeq = CLC_EditSeq + 1
  local edit = CreateFrame("EditBox", "CLC_ItemEdit_"..tostring(CLC_EditSeq), f, "InputBoxTemplate")
  edit:SetAutoFocus(false); edit:SetWidth(200); edit:SetHeight(20)
  edit:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -105)
  edit:SetFrameLevel(f:GetFrameLevel() + 1)
  local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  lbl:SetPoint("BOTTOMRIGHT", edit, "TOPRIGHT", 0, 2); lbl:SetText("Kommentar")

	------------- TOOLTIP -----------------
	 -- Icon-Button statt separatem Texture
	local iconButton = CreateFrame("Button", nil, f)
	iconButton:SetWidth(30)
	iconButton:SetHeight(30)
	iconButton:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)

	-- Texture für Icon
	local tex = iconButton:CreateTexture(nil, "BACKGROUND")
	tex:SetAllPoints(iconButton)
	tex:SetTexture(iconTex or "Interface\\Icons\\INV_Misc_QuestionMark")
	tex:SetTexCoord(0.06, 0.94, 0.06, 0.94)

	-- Mouseover Tooltip
	iconButton.itemLink = itemLink
	iconButton:SetScript("OnEnter", function()
		if not this.itemLink then return end
		GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
		if string.match(this.itemLink, "|Hitem:%d+:") then
			GameTooltip:SetHyperlink(this.itemLink)
		else
			local name = string.match(this.itemLink, "%[([^%]]+)%]") or "Unknown Item"
			GameTooltip:SetText(name)
		end
		GameTooltip:Show()
	end)
	iconButton:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Item-Link FontString neben Icon
	local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fs:SetPoint("LEFT", iconButton, "RIGHT", 8, 0)
	fs:SetText(itemLink)


  -- Countdown-Balken (1.12)
  local barW = f:GetWidth() - 28
  local barH = 8

  local barBG = f:CreateTexture(nil, "BACKGROUND")
  barBG:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
  barBG:SetWidth(barW); barBG:SetHeight(barH)
  barBG:SetTexture(0, 0, 0); barBG:SetAlpha(0.5)

  local bar = CreateFrame("StatusBar", nil, f)
  bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
  bar:SetWidth(barW); bar:SetHeight(barH)
  bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
  bar:SetStatusBarColor(0.0, 0.7, 1.0)
  bar:SetMinMaxValues(0, CLC_DB.lootDuration)
  bar:SetValue(CLC_DB.lootDuration)

  local timeText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  timeText:SetPoint("CENTER", bar, "CENTER", 0, 0)
  timeText:SetText(tostring(CLC_DB.lootDuration).."s")

  -- Gemeinsames OnUpdate
  f.key       = key
  f.bar       = bar
  f.timeText  = timeText
  f.timeLeft  = CLC_DB.lootDuration
  f:SetScript("OnUpdate", function()
    this.timeLeft = this.timeLeft - arg1
    if this.timeLeft < 0 then this.timeLeft = 0 end
    this.bar:SetValue(this.timeLeft)
    this.timeText:SetText(tostring(math.floor(this.timeLeft)).."s")
    if this.timeLeft <= 0 then
      CLC_CloseItemWindow(this.key)
      this:SetScript("OnUpdate", nil)
    end
  end)

  local function chooseAndClose(choice, roll, doRollChatMin, doRollChatMax)
    CLC_SendResponse(key, choice, edit:GetText(), roll)
    if doRollChatMin and doRollChatMax then RandomRoll(doRollChatMin, doRollChatMax) end
    CLC_CloseItemWindow(key)
  end

  bBiS:SetScript("OnClick", function() chooseAndClose("BIS") end)
  bUpg:SetScript("OnClick", function() chooseAndClose("UPGRADE") end)
  bOSp:SetScript("OnClick", function() chooseAndClose("OS+") end)
  bOS:SetScript("OnClick",  function() chooseAndClose("OS") end)

  bTM:SetScript("OnClick", function()
    CLC_PendingRollQueues["1-10"] = CLC_PendingRollQueues["1-10"] or {}
    table.insert(CLC_PendingRollQueues["1-10"], { key=key, choice="TMOG", comment=edit:GetText() or "" })
    RandomRoll(1,10)
    CLC_CloseItemWindow(key)
  end)

  bRoll:SetScript("OnClick", function()
    CLC_PendingRollQueues["1-100"] = CLC_PendingRollQueues["1-100"] or {}
    table.insert(CLC_PendingRollQueues["1-100"], { key=key, choice="ROLL", comment=edit:GetText() or "" })
    RandomRoll(1,100)
    CLC_CloseItemWindow(key)
  end)

  bPass:SetScript("OnClick", function() chooseAndClose("PASS") end)

  CLC_ItemWindows[key] = f
  local idx = 1; local k,_f; for k,_f in pairs(CLC_ItemWindows) do if _f ~= f then idx = idx + 1 end end
  PositionLootWindow(f, idx)
  f:Show()
end

------------------------------------------------------------
-- Officer-Panel (schmal, Header, dynamische Höhe, Votes)
------------------------------------------------------------
local CLC_OfficerFrame = nil
local CLC_RowFrames = nil
local CLC_MAX_ROWS = 40
local ROW_H = 18
local TOP_PAD = 64
local BOT_PAD = 48

local function CLC_HasVoted(itemKey, voter, target)
  if not CLC_Votes[itemKey] or not CLC_Votes[itemKey][voter] then return false end
  return CLC_Votes[itemKey][voter][target] == true
end

local function CLC_VoteCount(itemKey, target)
  local t = CLC_Votes[itemKey] or {}
  local n=0; for k,vt in pairs(t) do if vt[target] then n=n+1 end end
  return n
end

-- Nur Top-Roller je Kategorie TMOG/ROLL
local function filterTopRolls(rows)
  local sawTMOG, sawROLL = false, false
  local maxTMOG, maxROLL = nil, nil
  local i
  for i=1, tlen(rows) do
    local r = rows[i]
    if r.choice == "TMOG" then
      sawTMOG = true
      if not maxTMOG or (r.roll or 0) > maxTMOG then maxTMOG = r.roll or 0 end
    elseif r.choice == "ROLL" then
      sawROLL = true
      if not maxROLL or (r.roll or 0) > maxROLL then maxROLL = r.roll or 0 end
    end
  end
  if not sawTMOG and not sawROLL then return rows end

  local out = {}
  for i=1, tlen(rows) do
    local r = rows[i]
    if r.choice == "TMOG" then
      if not sawTMOG or r.roll == maxTMOG then table.insert(out, r) end
    elseif r.choice == "ROLL" then
      if not sawROLL or r.roll == maxROLL then table.insert(out, r) end
    else
      table.insert(out, r)
    end
  end
  return out
end

local function CLC_SortResponsesFor(itemKey)
  local t = CLC_Responses[itemKey] or {}
  table.sort(t, function(a,b)
    local sa = CLC_SortOrder(a.choice)
    local sb = CLC_SortOrder(b.choice)
    if sa ~= sb then return sa < sb end
    if a.choice=="TMOG" or a.choice=="ROLL" then
      local ra = tonumber(a.roll or 0) or 0
      local rb = tonumber(b.roll or 0) or 0
      if ra ~= rb then return ra > rb end
    end
    return (a.name or "") < (b.name or "")
  end)
end

local function CLC_GetVoters(itemKey, target)
  local out = {}
  local book = CLC_Votes[itemKey] or {}
  local voter, map
  for voter, map in pairs(book) do
    if map[target] then table.insert(out, voter) end
  end
  table.sort(out)
  return out
end

------------------------------------------------------------
-- Refresh Officer Panel
------------------------------------------------------------
function CLC_RefreshOfficerList()
    if not CLC_OfficerFrame then return end
    local idx = CLC_OfficerIndex
    local key = CLC_Items[idx]

    -- Höhe des Panels anpassen
    local function setHeightFor(n)
        local h = TOP_PAD + (n * ROW_H) + BOT_PAD
        if h < 180 then h = 180 end
        if h > 800 then h = 800 end
        CLC_OfficerFrame:SetHeight(h)
    end

    -- Kein Item vorhanden
    if not key then
        CLC_OfficerFrame.title:SetText("Keine Items")
        for i=1, CLC_MAX_ROWS do
            CLC_RowFrames[i]:Hide()
        end
        setHeightFor(0)
        return
    end

    CLC_OfficerFrame.title:SetText(CLC_ItemTextFromLink(key))

    -- Rows vorbereiten
    local rows = {}
    local src = CLC_Responses[key] or {}
    for i=1, tlen(src) do
        local r = src[i]
        if r.choice ~= "PASS" then table.insert(rows, r) end
    end

    CLC_SortResponsesFor(key)
    rows = filterTopRolls(rows)

    local count = tlen(rows)
    setHeightFor(count)

    for i=1, CLC_MAX_ROWS do
        local rf = CLC_RowFrames[i]
        local r = rows[i]

        if rf then
            if r then
                -- FontStrings setzen
                rf.nameFS:SetText(r.name or "?")
                local choiceTxt = tostring(r.choice or "?")
                if (r.choice == "TMOG" or r.choice == "ROLL") and (r.roll or 0) > 0 then
                    choiceTxt = choiceTxt.." ("..tostring(r.roll)..")"
                end
                rf.choiceFS:SetText(choiceTxt)
                rf.rankFS:SetText(getDisplayRank(r.name or ""))
                rf.commentFS:SetText(r.comment or "")

                -- Vote Button
                local voted = CLC_HasVoted(key, playerName(), r.name or "")
                rf.voteBtn:SetText(voted and "Unvote" or "Vote")
                rf.voteBtn:SetScript("OnClick", function()
                    CLC_ToggleVote(key, r.name or "")
                    CLC_RefreshOfficerList()
                end)

                -- Vote Count
                rf.countFS:SetText(tostring(CLC_VoteCount(key, r.name or "")))

                -- Zeile anzeigen
                rf:Show()

                -- -------------- ANOUNCE MARKIERUNG -----------------
                local rowPlayer = r.name or ""
                local rowChoice = tostring(r.choice or "")
                rowChoice = string.gsub(rowChoice, "%s*%(.+%)", "") -- Roll entfernen
                rowChoice = string.gsub(rowChoice, "^%s*(.-)%s*$","%1") -- trim whitespace

                if CLC_AnnouncedRowData
                   and CLC_AnnouncedRowData.playerName == rowPlayer
                   and CLC_AnnouncedRowData.choice == rowChoice then
                    rf:SetBackdropColor(0,0,0,0)  -- grün
                    rf.nameFS:SetTextColor(0,0.6,0,0.5)
                    rf.choiceFS:SetTextColor(0,0.6,0,0.5)
                    rf.rankFS:SetTextColor(0,0.6,0,0.5)
                    rf.commentFS:SetTextColor(0,0.6,0,0.5)
                else
                    rf:SetBackdropColor(0,0,0,0) -- Standardfarbe
                    rf.nameFS:SetTextColor(1,1,1)
                    rf.choiceFS:SetTextColor(1,1,1)
                    rf.rankFS:SetTextColor(1,1,1)
                    rf.commentFS:SetTextColor(1,1,1)
                end

            else
                rf:Hide()
            end
        end
    end
end

------------------------------------------------------------
-- Show Officer Panel
------------------------------------------------------------
function CLC_ShowOfficerPanel()
    if not isCouncil(playerName()) then return end
    if not CLC_OfficerFrame then
        local f = CreateFrame("Frame", "CLC_OfficerFrame", UIParent)
        f:SetWidth(640); f:SetHeight(260); f:SetFrameStrata("DIALOG"); ApplyDialogBackdrop(f)
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function() this:StartMoving() end)
        f:SetScript("OnDragStop", function() this:StopMovingOrSizing(); SavePos(this, "officer") end)
        f:SetClampedToScreen(true)
        RestorePos(f, "officer", "CENTER", "CENTER", 0, 0)

        -- Titel
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        title:SetPoint("TOP", f, "TOP", 0, -12)
        title:SetText("Item"); f.title = title

        -- Navigationspfeile
        local prev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        prev:SetText("<"); prev:SetWidth(22); prev:SetHeight(20)
        prev:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -12)
        prev:SetScript("OnClick", function()
            if tlen(CLC_Items) == 0 then return end
            CLC_OfficerIndex = CLC_OfficerIndex - 1
            if CLC_OfficerIndex < 1 then CLC_OfficerIndex = tlen(CLC_Items) end
            CLC_RefreshOfficerList()
        end)

        local nextb = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        nextb:SetText(">"); nextb:SetWidth(22); nextb:SetHeight(20)
        nextb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -12)
        nextb:SetScript("OnClick", function()
            if tlen(CLC_Items) == 0 then return end
            CLC_OfficerIndex = CLC_OfficerIndex + 1
            if CLC_OfficerIndex > tlen(CLC_Items) then CLC_OfficerIndex = 1 end
            CLC_RefreshOfficerList()
        end)

        -- Spaltenbreiten
        local X0 = 20
        local W_NAME, W_CHOICE, W_RANK, W_COMM, W_VOTE, W_COUNT = 120, 60, 90, 230, 50, 35
        local GAP = 6

        -- Header
        local hName = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
        hName:SetPoint("TOPLEFT", f, "TOPLEFT", X0, -40); hName:SetWidth(W_NAME); hName:SetJustifyH("LEFT"); hName:SetText("Name")
        local hChoice = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
        hChoice:SetPoint("LEFT", hName, "RIGHT", GAP, 0); hChoice:SetWidth(W_CHOICE); hChoice:SetText("Auswahl")
        local hRank = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
        hRank:SetPoint("LEFT", hChoice, "RIGHT", GAP, 0); hRank:SetWidth(W_RANK); hRank:SetText("Rang")
        local hComm = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
        hComm:SetPoint("LEFT", hRank, "RIGHT", GAP, 0); hComm:SetWidth(W_COMM); hComm:SetJustifyH("LEFT"); hComm:SetText("Kommentar")
        local hVote = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
        hVote:SetPoint("LEFT", hComm, "RIGHT", GAP, 0); hVote:SetWidth(W_VOTE); hVote:SetText("Vote")
        local hCount = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
        hCount:SetPoint("LEFT", hVote, "RIGHT", GAP, 0); hCount:SetWidth(W_COUNT); hCount:SetText("Cnt")

        -- Zeilen
        CLC_RowFrames = {}
        for i=1, CLC_MAX_ROWS do
            local row = CreateFrame("Button", nil, f)
            row:SetWidth(600)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", hName, "BOTTOMLEFT", 0, -(i-1)*ROW_H)
            row:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background"})
            row:SetBackdropColor(0,0,0,0)

            -- Zeile klickbar nur für PM
            if CanPlayerTriggerLoot() then
                row:EnableMouse(true)
                row:RegisterForClicks("LeftButtonUp")
                row:SetScript("OnMouseDown", function()
                    if CLC_SelectedRow and CLC_SelectedRow ~= this then
                        CLC_SelectedRow:SetBackdropColor(0,0,0,0)
                        CLC_SelectedRow.nameFS:SetTextColor(1,1,1)
                        CLC_SelectedRow.choiceFS:SetTextColor(1,1,1)
                        CLC_SelectedRow.rankFS:SetTextColor(1,1,1)
                        CLC_SelectedRow.commentFS:SetTextColor(1,1,1)
                    end
                    CLC_SelectedRow = this
                    this:SetBackdropColor(0,0.5,0.5,0.5)
                    this.nameFS:SetTextColor(1,1,0)
                    this.choiceFS:SetTextColor(1,1,0)
                    this.rankFS:SetTextColor(1,1,0)
                    this.commentFS:SetTextColor(1,1,0)
                end)
            else
                row:EnableMouse(false)
            end

            local nameFS = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            nameFS:SetPoint("LEFT", row, "LEFT", 0, 0); nameFS:SetWidth(W_NAME); nameFS:SetJustifyH("LEFT")
            local choiceFS = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            choiceFS:SetPoint("LEFT", nameFS, "RIGHT", GAP, 0); choiceFS:SetWidth(W_CHOICE)
            local rankFS = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            rankFS:SetPoint("LEFT", choiceFS, "RIGHT", GAP, 0); rankFS:SetWidth(W_RANK)
            local commentFS = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            commentFS:SetPoint("LEFT", rankFS, "RIGHT", GAP, 0); commentFS:SetWidth(W_COMM); commentFS:SetJustifyH("LEFT")

            local voteBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            voteBtn:SetWidth(W_VOTE); voteBtn:SetHeight(18)
            voteBtn:SetPoint("LEFT", commentFS, "RIGHT", GAP, 0); voteBtn:SetText("Vote")

            local countBtn = CreateFrame("Button", nil, row)
            countBtn:SetWidth(W_COUNT); countBtn:SetHeight(18)
            countBtn:SetPoint("LEFT", voteBtn, "RIGHT", GAP, 0)
            local countFS = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            countFS:SetPoint("CENTER", countBtn, "CENTER", 0, 0); countFS:SetWidth(W_COUNT)

            row.nameFS=nameFS; row.choiceFS=choiceFS; row.rankFS=rankFS; row.commentFS=commentFS; row.voteBtn=voteBtn; row.countFS=countFS; row.countBtn=countBtn
            row:Hide(); CLC_RowFrames[i]=row
        end

        -- Announce Button nur für PM
        local announceButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        announceButton:SetWidth(120); announceButton:SetHeight(22)
        announceButton:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
        announceButton:SetText("Announce")
        if CanPlayerTriggerLoot() then
            announceButton:SetScript("OnClick", function()
                if not CLC_SelectedRow then return end
                local playerName = CLC_SelectedRow.nameFS:GetText()
                local itemName   = f.title:GetText()
                local choiceRaw = CLC_SelectedRow.choiceFS:GetText() or ""
				local choice = string.gsub(choiceRaw, "%s*%(.+%)", "")  -- Roll entfernen

                -- RaidWarning lokal
                SendChatMessage(string.format("%s bekommt %s für %s", playerName, itemName, choice), "RAID_WARNING")

                -- Broadcast an alle Offiziere
                if isRaid() then
                    SendAddonMessage("CLC_ROW_ANNOUNCE", playerName.."^"..choice, "RAID")
                else
                    SendAddonMessage("CLC_ROW_ANNOUNCE", playerName.."^"..choice, "PARTY")
                end

                -- Speicherung für Refresh
                CLC_AnnouncedRowData = { playerName = playerName, choice = choice }

                -- Refresh Panel
                CLC_RefreshOfficerList()
            end)
        else
            announceButton:Hide()
        end

        -- Close Button
        local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        close:SetText("Schließen"); close:SetWidth(90); close:SetHeight(22)
        close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
        close:SetScript("OnClick", function() f:Hide() end)

        f:Hide()
        CLC_OfficerFrame = f
    end

    CLC_RefreshOfficerList()
    CLC_OfficerFrame:Show()
end

------------------------------------------------------------
-- ML-Panel
------------------------------------------------------------
local CLC_MLFrame = nil
function CLC_ShowMLFrame()
  if not CanPlayerTriggerLoot() then return end
  if not CLC_MLFrame then
    local f = CreateFrame("Frame", "CLC_MLFrame", UIParent)
    f:SetWidth(180); f:SetHeight(60); f:SetFrameStrata("DIALOG"); ApplyDialogBackdrop(f)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop",  function() this:StopMovingOrSizing(); SavePos(this, "ml") end)
    f:SetClampedToScreen(true)
    RestorePos(f, "ml", "TOPRIGHT", "TOPRIGHT", -40, -160)

    local b = CreateFrame("Button", "CLC_EndBtn", f, "UIPanelButtonTemplate")
    b:SetText("Session beenden"); b:SetWidth(140); b:SetHeight(24)
    b:SetPoint("CENTER", f, "CENTER", 0, 0)
    b:SetScript("OnClick", function() endSession() end)

    f:Hide(); CLC_MLFrame = f
  end
  CLC_MLFrame:Show()
end
local function CLC_HideMLFrame() if CLC_MLFrame then CLC_MLFrame:Hide() end end

------------------------------------------------------------
-- Messaging
------------------------------------------------------------
local function CLC_OnMessage(sender, message)
  if not message then return end
  local tag, payload = SMATCH(message, "([^% ^]+)%^(.*)")
  if not tag then return end

  if tag == "SESSION_START" then
    CLC_SessionActive = true; CLC_Items = {}; CLC_Responses = {}; CLC_Votes = {}
    refreshGuildRoster(); if isCouncil(playerName()) then CLC_ShowOfficerPanel() end

  elseif tag == "SESSION_END" then
    CLC_SessionActive = false
	DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON.."|r: Loot-Session beendet.")
    local k; for k,_ in pairs(CLC_ItemWindows) do CLC_CloseItemWindow(k) end
    if CLC_OfficerFrame then CLC_OfficerFrame:Hide() end
    CLC_HideMLFrame()

  elseif tag == "ITEM" then
    local lnk, icon = SMATCH(payload, "(.+)%^(.*)")
    if lnk then
      local key = itemKeyFromLink(lnk)
      table.insert(CLC_Items, key)
      CLC_Responses[key] = {}
      CLC_CreateItemWindow(lnk, icon)
      if isCouncil(playerName()) and CLC_OfficerFrame and CLC_OfficerFrame:IsShown() then CLC_RefreshOfficerList() end
    end

  elseif tag == "RESPONSE" then
    -- payload: key ^ name ^ choice ^ comment ^ roll
    local key, name, choice, comment, roll = SMATCH(payload, "([^\^]+)%^([^\^]+)%^([^\^]+)%^([^\^]*)%^(.*)")
    if not key or not name or not choice then return end
    local nroll = tonumber(roll or 0) or 0
    CLC_Responses[key] = CLC_Responses[key] or {}
    local list = CLC_Responses[key]
    local i, found=1,false
    for i=1, tlen(list) do
      if list[i].name == name then
        list[i].choice, list[i].comment, list[i].roll = choice, comment, nroll
        found=true; break
      end
    end
    if not found then
      table.insert(list, { name=name, choice=choice, comment=comment, roll=nroll })
    end
    if isCouncil(playerName()) and CLC_OfficerFrame and CLC_OfficerFrame:IsShown() then CLC_RefreshOfficerList() end

  elseif tag == "VOTE" then
    local key, voter, target = SMATCH(payload, "([^\^]+)%^([^\^]+)%^(.*)")
    if key and voter and target then
      CLC_Votes[key] = CLC_Votes[key] or {}; CLC_Votes[key][voter] = CLC_Votes[key][voter] or {}
      CLC_Votes[key][voter][target] = true
      if isCouncil(playerName()) and CLC_OfficerFrame and CLC_OfficerFrame:IsShown() then CLC_RefreshOfficerList() end
    end

  elseif tag == "VOTE_REVOKE" then
    local key, voter, target = SMATCH(payload, "([^\^]+)%^([^\^]+)%^(.*)")
    if key and voter and target and CLC_Votes[key] and CLC_Votes[key][voter] then
      CLC_Votes[key][voter][target] = nil
      if isCouncil(playerName()) and CLC_OfficerFrame and CLC_OfficerFrame:IsShown() then CLC_RefreshOfficerList() end
    end

  elseif tag == "ZONES_SET" then
    if CLC_DB.meta.acceptZonePush then
      -- einfache Serialisierung: "Zone1;Zone2;..."
      CLC_DB.zones = {}
      if payload and payload ~= "" then
        local z
        for z in string.gfind(payload, "([^;]+)") do CLC_DB.zones[z] = true end
      end
      CLC_InAllowedZone = inAllowedZone()
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00CLC|r: Zonen-Whitelist aktualisiert: "..(payload ~= "" and payload or "(leer)"))
    end
  end
end

-- Vote Toggle
function CLC_ToggleVote(itemKey, target)
  local voter = playerName()
  if not itemKey then itemKey = "?" end
  if not target or target == "" then target = "?" end
  local itemText = CLC_ItemTextFromLink(tostring(itemKey) or "?")

  CLC_Votes[itemKey] = CLC_Votes[itemKey] or {}
  CLC_Votes[itemKey][voter] = CLC_Votes[itemKey][voter] or {}

  if CLC_Votes[itemKey][voter][target] then
    CLC_Votes[itemKey][voter][target] = nil
    CLC_Send("VOTE_REVOKE", itemKey.."^"..voter.."^"..target)
  else
    CLC_Votes[itemKey][voter][target] = true
    CLC_Send("VOTE", itemKey.."^"..voter.."^"..target)
  end
end

------------------------------------------------------------
-- Slash Commands
------------------------------------------------------------
local function CLC_SerializeZones()
  local t = {}
  local k,v
  for k,v in pairs(CLC_DB.zones or {}) do
    if v then table.insert(t, k) end
  end
  table.sort(t)
  return table.concat(t, ";")
end

SLASH_CLC1 = "/clc"
SlashCmdList["CLC"] = function(msg)
  local cmd = string.lower(msg or "")
  if cmd == "show" then
    CLC_ShowOfficerPanel()

  elseif cmd == "end" then
    if CanPlayerTriggerLoot() then endSession() end

  elseif cmd == "anchor" then
    EnsureAnchor()
    if CLC_AnchorFrame:IsShown() then HideAnchor(); DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON.."|r: Loot-Anker versteckt.")
    else ShowAnchor(); DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON.."|r: Loot-Anker anzeigen (ziehen, um zu verschieben).") end

  elseif cmd == "anchor reset" then
    ResetAnchor(); DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON.."|r: Loot-Anker zurückgesetzt.")

  elseif string.sub(cmd,1,9) == "zone add " then
    local z = string.sub(cmd, 10)
    if z and z ~= "" then
      CLC_DB.zones[z] = true
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00CLC|r: Zone hinzugefügt: "..z)
    end

  elseif string.sub(cmd,1,12) == "zone remove " then
    local z = string.sub(cmd, 13)
    if z and z ~= "" then
      CLC_DB.zones[z] = nil
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00CLC|r: Zone entfernt: "..z)
    end

  elseif cmd == "zone list" then
    local s = CLC_SerializeZones()
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00CLC|r Zonen-Whitelist: "..(s ~= "" and s or "(leer)"))

  elseif cmd == "zone reset" then
    CLC_DB.zones = {}
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00CLC|r: Zonen-Whitelist geleert.")

  elseif string.sub(cmd,1,12) == "zones accept" then
    local arg = string.lower(string.sub(cmd,14) or "")
    if arg == "on" or arg == "1" or arg == "true" then
      CLC_DB.meta.acceptZonePush = true
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00CLC|r: Zonen-Push akzeptieren: |cff00ff00AN|r")
    elseif arg == "off" or arg == "0" or arg == "false" then
      CLC_DB.meta.acceptZonePush = false
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00CLC|r: Zonen-Push akzeptieren: |cffff0000AUS|r")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00CLC|r: /clc zones accept on|off")
    end

  elseif cmd == "zones push" then
    if not (IsRaidLeader() or IsRaidOfficer() or CanPlayerTriggerLoot()) then
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00CLC|r: Nur RL/RA/ML dürfen pushen.")
    else
      local payload = CLC_SerializeZones()
      CLC_Send("ZONES_SET", payload)
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00CLC|r: Zonen-Whitelist an Raid gepusht.")
    end

  else
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON.."|r: /clc show  |  /clc end  |  /clc anchor  |  /clc anchor reset")
  end
end

------------------------------------------------------------
-- Events
------------------------------------------------------------
function CLC_OnEvent()
  if event == "VARIABLES_LOADED" or event == "PLAYER_LOGIN" then
    CLC_EnsureDB()
    CLC_IsRaid = isRaid(); CLC_InAllowedZone = inAllowedZone(); refreshGuildRoster()

  elseif event == "PLAYER_ENTERING_WORLD" or event == "RAID_ROSTER_UPDATE" then
    CLC_IsRaid = isRaid(); CLC_InAllowedZone = inAllowedZone(); refreshGuildRoster()

  elseif event == "PLAYER_LOOT_METHOD_CHANGED" then
    -- nichts nötig, CanPlayerTriggerLoot() prüft live

  elseif event == "LOOT_OPENED" then
    if not CLC_SessionActive then
      CLC_BroadcastLoot()
    end

  elseif event == "GUILD_ROSTER_UPDATE" then
    if isCouncil(playerName()) and CLC_OfficerFrame and CLC_OfficerFrame:IsShown() then CLC_RefreshOfficerList() end

  elseif event == "CHAT_MSG_ADDON" then
    local prefix, message, channel, sender = arg1, arg2, arg3, arg4
    if prefix == "CLC" then CLC_OnMessage(sender, message)
	elseif prefix == "CLC_ROW_ANNOUNCE" then
		local sepPos = string.find(message, "^", 1, true)
		local playerName, choice
		if sepPos then
			playerName = string.sub(message, 1, sepPos-1)
			choice = string.sub(message, sepPos+1)
		else
			return
		end

		-- Sicherstellen, dass nichts nil ist
		if not playerName or not choice then return end

		CLC_AnnouncedRowData = { playerName = playerName, choice = choice }

		if CLC_OfficerFrame and CLC_OfficerFrame:IsShown() then
			CLC_RefreshOfficerList()
		end
	end

  elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
    CLC_InAllowedZone = inAllowedZone()

  elseif event == "CHAT_MSG_SYSTEM" then
    local msg = arg1
    if not msg then return end
    local who, rollStr, minStr, maxStr = SMATCH(msg, "^([^%s]+).-(%d+)%s*%((%d+)%-(%d+)%)")
    if not who or not rollStr or not minStr or not maxStr then return end
    if who ~= playerName() then return end

    local mn = tonumber(minStr) or 0
    local mx = tonumber(maxStr) or 0
    local k  = tostring(mn).."-"..tostring(mx)
    local q = CLC_PendingRollQueues and CLC_PendingRollQueues[k]
    if not q or table.getn(q) == 0 then return end

    local entry = table.remove(q, 1)
    local rnum  = tonumber(rollStr) or 0
    CLC_Send("RESPONSE", entry.key.."^"..playerName().."^"..entry.choice.."^"..entry.comment.."^"..tostring(rnum))
  end
end
frame:SetScript("OnEvent", CLC_OnEvent)
