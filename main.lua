-- main.lua - CorruptedLootCouncil (Vanilla 1.12, Lua 5.0 safe)

local ADDON = "CorruptedLootCouncil"

-- require-like: stelle sicher, dass utils & database geladen sind (TOC Reihenfolge!)
-- Hier keine realen require() Aufrufe, Classic lädt via .toc

CLC_SyntheticSent = CLC_SyntheticSent or {}  -- [itemKey] = true für diese Session
CLC_AnnouncedByItem = CLC_AnnouncedByItem or {}
local TOP_PAD, ROW_H, BOT_PAD = 60, 20, 16
local BOT_BAR_H = 36  -- << NEU: Höhe der Fußleiste

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

local function normalizedRank(name)
  local r = getGuildRankByRoster(name)
  if r == "" then return "" end
  -- Raider Veteran ⇒ wie besprochen nicht council-fähig, aber im Panel als "Raider"
  if r == "Raider Veteran" then return "Raider" end
  -- Alle höheren Ränge im Panel als "Raider" anzeigen
  if CLC_DB.rankRaidTwink[name] or CLC_DB.rankTwink[name] then
    -- Twink-Maps schlagen Umbenennung
    if CLC_DB.rankRaidTwink[name] then return "Raid Twink" end
    return "Twink"
  end
  if CLC_DB.councilRanks[r] then return "Raider" end
  return r
end

function isCouncil(name)
  -- Nur Officer/Bereichsleitung/RL/ML dürfen Panel sehen (kein Assist-Auto-Open)
  local i
  for i=1, GetNumRaidMembers() do
    local n, rank, subgroup, level, class, file, zone, online, isDead, role, isML = GetRaidRosterInfo(i)
    if n == name then
      local isLead = IsRaidLeader()
      if isML then return true end
      local gname, grank = GetGuildInfo("raid"..i)
      if grank == "Raider Veteran" then return false end
      if grank and CLC_DB.councilRanks and CLC_DB.councilRanks[grank] then return true end
      if isLead then return true end
      return false
    end
  end
  if name == CLC_playerName() then
    local gname, grank = GetGuildInfo("player")
    if grank == "Raider Veteran" then return false end
    if grank and CLC_DB.councilRanks and CLC_DB.councilRanks[grank] then return true end
  end
  return false
end

------------------------------------------------------------
-- AddonMessage
------------------------------------------------------------
if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix("CLC") end
local function CLC_Send(tag, payload)
  local body = tag .. "^" .. (payload or "")
  if CLC_isRaid() then
    SendAddonMessage("CLC", body, "RAID")
  else
    SendAddonMessage("CLC", body, "PARTY")
  end
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

function CanPlayerTriggerLoot()
  local method = GetLootMethod()
  if method == "master" then
    return PlayerIsMasterLooter()
  else
    -- Fallback: Nur der Raidlead darf auslösen, wenn kein Master Loot aktiv ist
    return IsRaidLeader()
  end
end

local function CLC_UpdateAnnounceButton()
  if not CLC_OfficerFrame or not CLC_OfficerFrame.announceBtn then return end
  local allow = IsRaidLeader() or PlayerIsMasterLooter()
  if allow then
    CLC_OfficerFrame.announceBtn:Enable()
  else
    CLC_OfficerFrame.announceBtn:Disable()
  end
end

------------------------------------------------------------
-- Zonen & Mindestgröße
------------------------------------------------------------
local function hasZoneWhitelist()
  local k,v
  for k,v in pairs(CLC_DB.zones or {}) do if v then return true end end
  return false
end

local function raidHasEnoughPlayers()
  local n = GetNumRaidMembers() or 0
  return n >= (CLC_MIN_RAID_SIZE or 15)
end

local function inAllowedZone()
  local z = GetRealZoneText()
  if not z or not hasZoneWhitelist() then return true end
  return CLC_DB.zones[z] == true
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

    -- 1) LOKAL alle ItemWindows schließen (ML sieht sonst seine eigenen weiter)
    if CLC_ItemWindows then
      local _, f
      for _, f in pairs(CLC_ItemWindows) do
        if f and f.Hide then f:Hide() end     -- löst OnHide -> Untrack + Reflow aus
      end
    end
    CLC_ItemWindows = {}
    CLC_WindowOrder = {}
    if CLC_ReflowWindows then CLC_ReflowWindows() end

    -- 2) UI aufräumen
    CLC_HideMLFrame()
    CLC_AnnouncedRowData = nil
    CLC_WipePerSessionState()
	CLC_AnnouncedByItem = {}
    -- 3) Raid informieren
    CLC_Send("SESSION_END", CLC_playerName())
	CLC_SyntheticSent = {}
  end
end

local function startSessionIfNeeded()
  if not CLC_SessionActive then
    CLC_SessionActive = true
    CLC_Items, CLC_Responses, CLC_Votes = {}, {}, {}
    CLC_Send("SESSION_START", CLC_playerName())
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00"..ADDON.."|r: Loot-Session gestartet.")
  end
end

-- Sammle Items & gruppiere Duplikate: key -> { link, tex, count }
local function collectGroupedLoot()
  local map = {}
  local order = {}
  local i
  for i=1, GetNumLootItems() do
    if isEpicOrWhitelisted(i) then
      local tex, name, qty, quality = GetLootSlotInfo(i)
      local link = GetLootSlotLink(i)
      if link then
        local key = CLC_itemKeyFromLink(link)
        if not map[key] then
          map[key] = { link = link, tex = tex, count = 1 }
          table.insert(order, key)
        else
          map[key].count = (map[key].count or 1) + 1
        end
      end
    end
  end
  -- Filter: außerhalb erlaubter Zonen NUR Whitelist
  if not inAllowedZone() then
    local outMap, outOrder = {}, {}
    local j
    for j=1, table.getn(order) do
      local k = order[j]; local rec = map[k]
      local name = rec and SMATCH(rec.link, "%[([^%]]+)%]")
      if name and CLC_DB.itemWhitelist[name] then
        outMap[k] = rec; table.insert(outOrder, k)
      end
    end
    map, order = outMap, outOrder
  end
  return map, order
end

function CLC_BroadcastLoot()
  if not raidHasEnoughPlayers() then return end
  if CLC_SessionActive then return end
  if not CLC_IsRaid then return end
  if not CanPlayerTriggerLoot() then return end

  local map, order = collectGroupedLoot()
  if table.getn(order) == 0 then return end

  startSessionIfNeeded()
  local i
  for i=1, table.getn(order) do
    local k = order[i]; local rec = map[k]
    -- Sende: ITEM ^ link ^ texture ^ count
    CLC_Send("ITEM", (rec.link or "").."^"..(rec.tex or "").."^"..tostring(rec.count or 1))
  end
  if CanPlayerTriggerLoot() then CLC_ShowMLFrame() end
end

------------------------------------------------------------
-- Messaging
------------------------------------------------------------
local function CLC_OnMessage(sender, message)
  if not message then return end
  local tag, payload = SMATCH(message, "([^% ^]+)%^(.*)")
  if not tag then return end

  if tag == "SESSION_START" then
    CLC_SessionActive = true; CLC_Items = {}; CLC_Responses = {}; CLC_Votes = {}
    refreshGuildRoster(); if isCouncil(CLC_playerName()) then CLC_ShowOfficerPanel() end

  elseif tag == "SESSION_END" then
    CLC_SessionActive = false
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON.."|r: Loot-Session beendet.")
    local k,f
    for k,f in pairs(CLC_ItemWindows) do if f then f:Hide() end end
    CLC_ItemWindows = {}
    if CLC_OfficerFrame then CLC_OfficerFrame:Hide() end
    CLC_HideMLFrame()
    CLC_WipePerSessionState()
	CLC_ItemWindows = {}
	CLC_AnnouncedByItem = {}
	CLC_WindowOrder = {}
	CLC_SyntheticSent = {}

  elseif tag == "ITEM" then
    local lnk, icon, cntStr = SMATCH(payload, "([^^]+)%^([^%^]*)%^(.*)")
    local count = tonumber(cntStr or "1") or 1
    if lnk then
      local key = CLC_itemKeyFromLink(lnk)
      table.insert(CLC_Items, key)
      CLC_Responses[key] = {}
      CLC_CreateItemWindow(lnk, icon, count)
      if isCouncil(CLC_playerName()) and CLC_OfficerFrame and CLC_OfficerFrame:IsShown() then
        CLC_RefreshOfficerList()
      end
    end

  elseif tag == "RESPONSE" then
	  local key, name, choice, comment, roll = SMATCH(payload, "([^\^]+)%^([^\^]+)%^([^\^]+)%^([^\^]*)%^(.*)")
	  if not key or not name or not choice then return end
	  local nroll = tonumber(roll or 0) or 0
	  CLC_Responses[key] = CLC_Responses[key] or {}
	  local list = CLC_Responses[key]

	  -- WICHTIG: nach (name, choice) deduplizieren – nicht nur nach name!
	  local i, found = 1, false
	  for i=1, table.getn(list) do
		if list[i].name == name and list[i].choice == choice then
		  list[i].comment = comment
		  list[i].roll    = nroll
		  found = true
		  break
		end
	  end
	  if not found then
		table.insert(list, { name=name, choice=choice, comment=comment, roll=nroll })
	  end

	  if isCouncil(CLC_playerName()) and CLC_OfficerFrame and CLC_OfficerFrame:IsShown() then
		CLC_RefreshOfficerList()
	  end

  elseif tag == "VOTE" then
    local key, voter, target = SMATCH(payload, "([^\^]+)%^([^\^]+)%^(.*)")
    if key and voter and target then
      CLC_Votes[key] = CLC_Votes[key] or {}; CLC_Votes[key][voter] = CLC_Votes[key][voter] or {}
      CLC_Votes[key][voter][target] = true
      if isCouncil(CLC_playerName()) and CLC_OfficerFrame and CLC_OfficerFrame:IsShown() then CLC_RefreshOfficerList() end
    end

  elseif tag == "VOTE_REVOKE" then
    local key, voter, target = SMATCH(payload, "([^\^]+)%^([^\^]+)%^(.*)")
    if key and voter and target and CLC_Votes[key] and CLC_Votes[key][voter] then
      CLC_Votes[key][voter][target] = nil
      if isCouncil(CLC_playerName()) and CLC_OfficerFrame and CLC_OfficerFrame:IsShown() then CLC_RefreshOfficerList() end
    end

  elseif tag == "TMOGROLL" then
	  local itemKey, who, rollv = SMATCH(payload or "", "^([^%^]+)%^([^%^]+)%^(.+)$")
	  local r = tonumber(rollv or "0") or 0
	  if itemKey and who and r > 0 then
		-- 1) interne TMOG-Roll-Tabelle
		CLC_TmogRolls[itemKey] = CLC_TmogRolls[itemKey] or {}
		CLC_TmogRolls[itemKey][who] = r

		-- 2) eigenständigen RESPONSE-Eintrag "TMOG" (zusätzlich zu evtl. späterer Auswahl) anlegen/aktualisieren
		CLC_Responses[itemKey] = CLC_Responses[itemKey] or {}
		local list = CLC_Responses[itemKey]
		local i, found = 1, false
		for i=1, table.getn(list) do
		  if list[i].name == who and list[i].choice == "TMOG" then
			list[i].roll = r
			found = true
			break
		  end
		end
		if not found then
		  table.insert(list, { name=who, choice="TMOG", comment="", roll=r })
		end

		if isCouncil(CLC_playerName()) and CLC_OfficerFrame and CLC_OfficerFrame:IsShown() then
		  CLC_RefreshOfficerList()
		end
	  end

  elseif tag == "ZONES_SET" then
    if CLC_DB.meta.acceptZonePush then
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

------------------------------------------------------------
-- UI: Loot-Master Mini-Panel (End Session)
------------------------------------------------------------
function CLC_ShowMLFrame()
  if not CLC_MLFrame then
    local f = CreateFrame("Frame", "CLC_MLFrame", UIParent)
    f:SetWidth(180); f:SetHeight(60); f:SetFrameStrata("DIALOG"); CLC_ApplyDialogBackdrop(f)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop",  function() this:StopMovingOrSizing(); CLC_SavePos(this, "ml") end)
    f:SetClampedToScreen(true)
    CLC_RestorePos(f, "ml", "TOPRIGHT", "TOPRIGHT", -40, -160)

    local b = CreateFrame("Button", "CLC_EndBtn", f, "UIPanelButtonTemplate")
    b:SetText("Session beenden"); b:SetWidth(140); b:SetHeight(24)
    b:SetPoint("CENTER", f, "CENTER", 0, 0)
    b:SetScript("OnClick", function() endSession() end)

    f:Hide(); CLC_MLFrame = f
  end
  CLC_MLFrame:Show()
end
function CLC_HideMLFrame() if CLC_MLFrame then CLC_MLFrame:Hide() end end

------------------------------------------------------------
-- UI: Lootfenster
------------------------------------------------------------
CLC_TmogRolls   = CLC_TmogRolls   or {}   -- [itemKey][player] = roll
CLC_PendingRoll = CLC_PendingRoll or nil  -- nur für TMOG 1–10
CLC_PendingRollQueues = CLC_PendingRollQueues or { ["1-10"] = {}, ["1-100"] = {} }

local function CLC_CloseItemWindow(uniqKey)
  local f = CLC_ItemWindows[uniqKey]
  if not f then return end
  CLC_ItemWindows[uniqKey] = nil
  f:Hide()   -- OnHide übernimmt Untrack + Reflow
end

local function CLC_SendResponse(itemKey, choice, comment, roll)
  local payload = (itemKey or "?").."^"..CLC_playerName().."^"..(choice or "PASS").."^"..(comment or "").."^"..tostring(roll or "")
  CLC_Send("RESPONSE", payload)
end

-- TMOG-Roll verteilen (Message)
function CLC_SendTmogRoll(itemKey, roll)
  local p = UnitName("player")
  CLC_TmogRolls[itemKey] = CLC_TmogRolls[itemKey] or {}
  CLC_TmogRolls[itemKey][p] = roll
  CLC_Send("TMOGROLL", itemKey.."^"..p.."^"..tostring(roll))
end

-- Enqueue für ROLL (1–100) und ggf. andere Bereiche:
function CLC_EnqueueRoll(itemKey, choice, comment, mn, mx)
  local kk = tostring(mn).."-"..tostring(mx)
  CLC_PendingRollQueues[kk] = CLC_PendingRollQueues[kk] or {}
  table.insert(CLC_PendingRollQueues[kk], { key=itemKey, choice=choice, comment=comment or "" })
end

-- TMOG: echten 1–10 Roll auslösen, Fenster bleibt offen!
function CLC_PerformTMOG(frame)
  if frame._tmogDone then return end
  frame._tmogDone = true
  if frame.bTM then frame.bTM:Disable(); frame.bTM:SetText("TMOG ✓") end
  CLC_PendingRoll = { player=UnitName("player"), low=1, high=10, itemKey=frame._itemKey, expires=(GetTime and GetTime() or 0)+10 }
  RandomRoll(1,10)
end

function CLC_CreateItemWindow(itemLink, iconTex, count)
  local logicalKey = CLC_itemKeyFromLink(itemLink)
  local uniqKey = CLC_NewWindowKeyForItem(logicalKey)

  local f = CreateFrame("Frame", "CLC_ItemWin_"..tostring(CLC_now()), UIParent)
  f:SetWidth(380); f:SetHeight(150); f:SetFrameStrata("DIALOG"); CLC_ApplyDialogBackdrop(f)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop",  function() this:StopMovingOrSizing() end)
  f:SetClampedToScreen(true)

  f:SetScript("OnHide", function()
  CLC_UntrackWindow(this)
  if CLC_ReflowWindows then CLC_ReflowWindows() end
	end)

  f._itemKey = logicalKey
  f._uniqKey = uniqKey

  local closeX = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  closeX:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  closeX:SetScript("OnClick", function()
    CLC_SendResponse(f._itemKey, "PASS", "")
    CLC_CloseItemWindow(f._uniqKey)
  end)

	  -- === Tooltip- und Label-Teil (drop-in) ===
	-- Erwartet: lokale Variablen: f (Frame), itemLink (voller Itemlink), count (xN), iconTexture


	-- Icon-Button (Overlay)
	local iconBtn = CreateFrame("Button", nil, f)
	iconBtn:SetWidth(32); iconBtn:SetHeight(32)
	iconBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)

	iconBtn:EnableMouse(true)
	iconBtn:RegisterForClicks("AnyUp")

	local tex = iconBtn:CreateTexture(nil, "BORDER")
	tex:SetAllPoints(iconBtn)
	tex:SetTexCoord(0.06,0.94,0.06,0.94)
	tex:SetTexture(iconTex or iconTexture or "Interface\\Icons\\INV_Misc_QuestionMark")

	iconBtn.itemLink = itemLink

	-- ItemID sicher aus vollem Link ziehen (Vanilla-safe)
	local itemID = nil
	if itemLink then
	  -- sucht nach "Hitem:<ID>:" oder "|Hitem:<ID>:" robust
	  local id1 = SMATCH(itemLink, "Hitem:(%d+):")
	  local id2 = SMATCH(itemLink, "|Hitem:(%d+):")
	  itemID = tonumber(id1 or id2 or "")
	end
	local tooltipLink = itemID and ("item:" .. tostring(itemID)) or itemLink

	-- Lokale Tooltip-Handler (Scope-sicher)
	local function ShowTooltip(owner)
	  if not tooltipLink then return end
	  GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
	  -- nackte URI "item:<ID>" ist AtlasLoot-freundlich
	  GameTooltip:SetHyperlink(tooltipLink)
	  if count and count > 1 then
		GameTooltip:AddLine("x" .. tostring(count), 1, 0.95, 0.2)
	  end
	  GameTooltip:Show()
	end

	local function HideTooltip()
	  GameTooltip:Hide()
	end

	-- Icon-Interaktion
	iconBtn:SetScript("OnEnter", function() ShowTooltip(this) end)
	iconBtn:SetScript("OnLeave", HideTooltip)
	iconBtn:RegisterForClicks("AnyUp")
	iconBtn:SetScript("OnClick", function()
	  if IsControlKeyDown() and iconBtn.itemLink then
		DressUpItemLink(iconBtn.itemLink)
	  elseif IsControlKeyDown() and itemLink then
		DressUpItemLink(itemLink)
	  end
	end)

	-- Titel: FontString + unsichtbarer Button (für Tooltip & Klick)
	local titleFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	titleFS:SetPoint("LEFT", iconBtn, "RIGHT", 8, 0)
	local shownText = itemLink
	if count and count > 1 then
	  shownText = shownText .. "  |cffffcc00x" .. tostring(count) .. "|r"
	end
	titleFS:SetText(shownText)

	local titleBtn = CreateFrame("Button", nil, f)
	local tw = titleFS:GetStringWidth() + 6
	local _, fontHeight = titleFS:GetFont()
	local th = (fontHeight or 14) + 4
	titleBtn:SetWidth(tw); titleBtn:SetHeight(th)
	titleBtn:SetPoint("LEFT", titleFS, "LEFT", 0, 0)
	titleBtn:SetScript("OnEnter", function() ShowTooltip(titleBtn) end)
	titleBtn:SetScript("OnLeave", HideTooltip)
	titleBtn:SetScript("OnClick", function()
	  if IsControlKeyDown() and itemLink then
		DressUpItemLink(itemLink)
	  end
	end)

  -- Buttons (kompakt)
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

  CLC_EditSeq = CLC_EditSeq + 1
  local edit = CreateFrame("EditBox", "CLC_ItemEdit_"..tostring(CLC_EditSeq), f, "InputBoxTemplate")
  edit:SetAutoFocus(false); edit:SetWidth(200); edit:SetHeight(20)
  edit:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -105)
  edit:SetFrameLevel(f:GetFrameLevel() + 1)
  local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  lbl:SetPoint("BOTTOMRIGHT", edit, "TOPRIGHT", 0, 2); lbl:SetText("Kommentar")

  -- Countdown-Balken
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

  f.key       = logicalKey
  f.bar       = bar
  f.timeText  = timeText
  f.timeLeft  = CLC_DB.lootDuration
  f.bTM = bTM

  f:SetScript("OnUpdate", function()
    this.timeLeft = this.timeLeft - arg1
    if this.timeLeft < 0 then this.timeLeft = 0 end
    this.bar:SetValue(this.timeLeft)
    this.timeText:SetText(tostring(math.floor(this.timeLeft)).."s")
    if this.timeLeft <= 0 then
      CLC_CloseItemWindow(this._uniqKey)
      this:SetScript("OnUpdate", nil)
    end
  end)

  local function chooseAndClose(choice, roll, doRollChatMin, doRollChatMax)
    CLC_SendResponse(logicalKey, choice, edit:GetText(), roll)
    if doRollChatMin and doRollChatMax then RandomRoll(doRollChatMin, doRollChatMax) end
    CLC_CloseItemWindow(uniqKey)
  end

  bBiS:SetScript("OnClick", function() chooseAndClose("BIS") end)
  bUpg:SetScript("OnClick", function() chooseAndClose("UPGRADE") end)
  bOSp:SetScript("OnClick", function() chooseAndClose("OS+") end)
  bOS:SetScript("OnClick",  function() chooseAndClose("OS") end)

  bTM:SetScript("OnClick", function()
    CLC_PerformTMOG(f)                  -- feuert echten /roll 1-10

  end)

  bRoll:SetScript("OnClick", function()
	  local comm = (edit and edit:GetText()) or ""
	  CLC_EnqueueRoll(f._itemKey, "ROLL", comm, 1, 100)
	  RandomRoll(1, 100)
	  CLC_CloseItemWindow(f._uniqKey)
	end)

  bPass:SetScript("OnClick", function() chooseAndClose("PASS") end)

  CLC_ItemWindows[uniqKey] = f
  CLC_EnsureAnchor()
  CLC_TrackWindow(f)
  CLC_ReflowWindows()
  f:Show()
end

------------------------------------------------------------
-- Officer Panel (mit Lootmaster-Announce)
------------------------------------------------------------
local TOP_PAD, ROW_H, BOT_PAD = 60, 20, 16
CLC_MAX_ROWS = 28
CLC_RowFrames = CLC_RowFrames or {}
CLC_OfficerIndex = CLC_OfficerIndex or 1
CLC_AnnouncedRowData = CLC_AnnouncedRowData or nil
CLC_LastAnnouncedRow = CLC_LastAnnouncedRow or nil

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

local function CLC_SortOrder(choice)
  if choice == "TMOG" then return 0 end
  if choice == "BIS" then return 1 end
  if choice == "UPGRADE" then return 2 end
  if choice == "OS+" then return 3 end
  if choice == "OS" then return 4 end
  if choice == "ROLL" then return 5 end
  return 6
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

local function bestRollFiltered(rows)
  local sawTMOG, sawROLL = false, false
  local maxTMOG, maxROLL = nil, nil
  local i
  for i=1, table.getn(rows) do
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
  for i=1, table.getn(rows) do
    local r = rows[i]
    if r.choice == "TMOG" then
      if r.roll == maxTMOG then table.insert(out, r) end
    elseif r.choice == "ROLL" then
      if r.roll == maxROLL then table.insert(out, r) end
    else
      table.insert(out, r)
    end
  end
  return out
end

function CLC_ShowOfficerPanel()
  if not isCouncil(CLC_playerName()) then return end
  if not CLC_OfficerFrame then
    local f = CreateFrame("Frame", "CLC_OfficerFrame", UIParent)
    f:SetWidth(640); f:SetHeight(260); f:SetFrameStrata("DIALOG"); CLC_ApplyDialogBackdrop(f)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop",  function() this:StopMovingOrSizing(); CLC_SavePos(this, "officer") end)
    f:SetClampedToScreen(true)
    CLC_RestorePos(f, "officer", "CENTER", "CENTER", 0, 0)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", f, "TOP", 0, -12); title:SetText("Item"); f.title = title

    local prev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    prev:SetText("<"); prev:SetWidth(22); prev:SetHeight(20)
    prev:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -12)
    prev:SetScript("OnClick", function()
      if table.getn(CLC_Items) == 0 then return end
      CLC_OfficerIndex = CLC_OfficerIndex - 1
      if CLC_OfficerIndex < 1 then CLC_OfficerIndex = table.getn(CLC_Items) end
	  CLC_SelectedRow, CLC_SelectedName = nil, nil
      CLC_RefreshOfficerList()
    end)
    local nextb = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    nextb:SetText(">"); nextb:SetWidth(22); nextb:SetHeight(20)
    nextb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -12)
    nextb:SetScript("OnClick", function()
      if table.getn(CLC_Items) == 0 then return end
      CLC_OfficerIndex = CLC_OfficerIndex + 1
      if CLC_OfficerIndex > table.getn(CLC_Items) then CLC_OfficerIndex = 1 end
	  CLC_SelectedRow, CLC_SelectedName = nil, nil
      CLC_RefreshOfficerList()
    end)

    -- Spalten
    local X0 = 20
    local W_NAME, W_CHOICE, W_RANK, W_COMM, W_VOTE, W_COUNT = 120, 60, 90, 230, 50, 35
    local GAP = 6

    local hName   = f:CreateFontString(nil,"OVERLAY","GameFontNormal"); hName:SetPoint("TOPLEFT", f, "TOPLEFT", X0, -40); hName:SetWidth(W_NAME);   hName:SetJustifyH("LEFT"); hName:SetText("Name")
    local hChoice = f:CreateFontString(nil,"OVERLAY","GameFontNormal"); hChoice:SetPoint("LEFT", hName, "RIGHT", GAP, 0);   hChoice:SetWidth(W_CHOICE); hChoice:SetText("Auswahl")
    local hRank   = f:CreateFontString(nil,"OVERLAY","GameFontNormal"); hRank:SetPoint("LEFT", hChoice, "RIGHT", GAP, 0);   hRank:SetWidth(W_RANK);   hRank:SetText("Rang")
    local hComm   = f:CreateFontString(nil,"OVERLAY","GameFontNormal"); hComm:SetPoint("LEFT", hRank, "RIGHT", GAP, 0);     hComm:SetWidth(W_COMM);   hComm:SetJustifyH("LEFT"); hComm:SetText("Kommentar")
    local hVote   = f:CreateFontString(nil,"OVERLAY","GameFontNormal"); hVote:SetPoint("LEFT", hComm, "RIGHT", GAP, 0);     hVote:SetWidth(W_VOTE);   hVote:SetText("Vote")
    local hCount  = f:CreateFontString(nil,"OVERLAY","GameFontNormal"); hCount:SetPoint("LEFT", hVote, "RIGHT", GAP, 0);    hCount:SetWidth(W_COUNT); hCount:SetText("Cnt")

    CLC_RowFrames = {}
    local i
    for i=1, CLC_MAX_ROWS do
      local row = CreateFrame("Button", nil, f) -- Button, damit selektierbar
      row:SetWidth(600); row:SetHeight(ROW_H)
      row:SetPoint("TOPLEFT", hName, "BOTTOMLEFT", 0, -(i-1)*ROW_H)

      row.nameFS   = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.nameFS:SetPoint("LEFT", row, "LEFT", 0, 0);   row.nameFS:SetWidth(W_NAME);   row.nameFS:SetJustifyH("LEFT")
      row.choiceFS = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.choiceFS:SetPoint("LEFT", row.nameFS, "RIGHT", GAP, 0); row.choiceFS:SetWidth(W_CHOICE)
      row.rankFS   = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.rankFS:SetPoint("LEFT", row.choiceFS, "RIGHT", GAP, 0); row.rankFS:SetWidth(W_RANK)
      row.commentFS= row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.commentFS:SetPoint("LEFT", row.rankFS, "RIGHT", GAP, 0); row.commentFS:SetWidth(W_COMM); row.commentFS:SetJustifyH("LEFT")

      row.voteBtn  = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
      row.voteBtn:SetWidth(W_VOTE); row.voteBtn:SetHeight(18)
      row.voteBtn:SetPoint("LEFT", row.commentFS, "RIGHT", GAP, 0); row.voteBtn:SetText("Vote")

      row.countBtn = CreateFrame("Button", nil, row)
      row.countBtn:SetWidth(W_COUNT); row.countBtn:SetHeight(18)
      row.countBtn:SetPoint("LEFT", row.voteBtn, "RIGHT", GAP, 0)
      row.countFS  = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.countFS:SetPoint("CENTER", row.countBtn, "CENTER", 0, 0); row.countFS:SetWidth(W_COUNT)

      row:SetScript("OnClick", function()
		  -- alle Zeilen vollständig ent-rahmen
		  local i
		  for i=1, CLC_MAX_ROWS do
			local rw = CLC_RowFrames[i]
			if rw and rw:IsShown() then
			  rw:SetBackdrop(nil)
			  rw._selected = false
			end
		  end

		  -- aktuelle Auswahl markieren
		  CLC_SelectedRow  = this
		  CLC_SelectedName = this.nameFS and this.nameFS:GetText() or nil
		  this._selected   = true
		  this:SetBackdrop({ edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=12 })
	  end)

      row.countBtn:SetScript("OnEnter", function()
        local idx = CLC_OfficerIndex
        local key = CLC_Items[idx]
		local ann = CLC_AnnouncedByItem[key]
        if not key then return end
        local target = row.nameFS:GetText() or "?"
        local voters = CLC_GetVoters(key, target)
        GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("Votes: "..tostring(table.getn(voters)), 1,1,1)
        if table.getn(voters) > 0 then
          local ii
          for ii=1, table.getn(voters) do GameTooltip:AddLine(voters[ii], 0.9,0.9,0.9) end
        else
          GameTooltip:AddLine("Keine", 0.7,0.7,0.7)
        end
        GameTooltip:Show()
      end)
      row.countBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

      CLC_RowFrames[i] = row
    end

	-- === Fußleiste: fester Klickbereich über den Zeilen ===
	local bottomBar = CreateFrame("Frame", nil, f)
	bottomBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
	bottomBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	bottomBar:SetHeight(BOT_BAR_H)
	bottomBar:EnableMouse(true)  -- blockt Zeilen-Klicks sicher
	bottomBar:SetFrameLevel(f:GetFrameLevel() + 5)
	-- dezente Optik (optional)
	local bbtex = bottomBar:CreateTexture(nil, "BACKGROUND")
	bbtex:SetAllPoints(bottomBar)

	-- Buttons: rechts, nebeneinander
	f.announceBtn = CreateFrame("Button", nil, bottomBar, "UIPanelButtonTemplate")
	f.announceBtn:SetText("Announce"); f.announceBtn:SetWidth(100); f.announceBtn:SetHeight(22)
	f.announceBtn:SetPoint("RIGHT", bottomBar, "CENTER", 40, 3)

	f.closeBtn = CreateFrame("Button", nil, bottomBar, "UIPanelButtonTemplate")
	f.closeBtn:SetText("Schließen"); f.closeBtn:SetWidth(100); f.closeBtn:SetHeight(22)
	f.closeBtn:SetPoint("RIGHT", bottomBar, "RIGHT", -10, 3)

	-- Handler bleiben wie gehabt:
	f.announceBtn:SetScript("OnClick", function()
	  if not CanPlayerTriggerLoot() or not CLC_SelectedRow then return end
	  local idx = CLC_OfficerIndex
	  local key = CLC_Items[idx]; if not key then return end
	  local pName  = CLC_SelectedRow.nameFS:GetText() or "?"
	  local choice = CLC_SelectedRow.choiceFS:GetText() or "?"
	  SendChatMessage(pName.." bekommt "..CLC_ItemTextFromLink(key).." für "..choice, "RAID_WARNING")
	  -- (keine grüne Markierung mehr gewünscht)
	end)
	f.closeBtn:SetScript("OnClick", function() f:Hide() end)

    CLC_OfficerFrame = f
  end
  CLC_OfficerFrame:Show()
  CLC_RefreshOfficerList()
  CLC_UpdateAnnounceButton()
end

local function setOfficerHeightFor(n)
  local h = TOP_PAD + (n * ROW_H) + BOT_PAD + BOT_BAR_H  -- << BOT_BAR_H addiert
  if h < 180 then h = 180 end
  if h > 800 then h = 800 end
  CLC_OfficerFrame:SetHeight(h)
end

-- Merker für die aktuelle Auswahl (optional)
CLC_SelectedName = CLC_SelectedName or nil


function CLC_RefreshOfficerList()
  if not CLC_OfficerFrame then return end
  local idx = CLC_OfficerIndex
  local key = CLC_Items[idx]
  local ann = (CLC_AnnouncedByItem and CLC_AnnouncedByItem[key]) or CLC_AnnouncedRowData

  if not key then
    CLC_OfficerFrame.title:SetText("Keine Items")
    local i
	for i=1, CLC_MAX_ROWS do
	  local rw = CLC_RowFrames[i]
	  if rw then rw:SetBackdrop(nil) end
	end
  end

  CLC_OfficerFrame.title:SetText(CLC_ItemTextFromLink(key))
  local base = CLC_Responses[key] or {}
  CLC_SortResponsesFor(key)

  -- Filtern: PASS raus; TMOG/ROLL nur höchste
  local rows = {}
  local i
  for i=1, table.getn(base) do
    local r = base[i]
    if r.choice ~= "PASS" then table.insert(rows, r) end
  end
  rows = bestRollFiltered(rows)

  -- Rendern
  local vis = math.min(table.getn(rows), CLC_MAX_ROWS)
  for i=1, CLC_MAX_ROWS do
    local row = CLC_RowFrames[i]
    if i <= vis then
      local r = rows[i]
      row:Show()
      row.nameFS:SetText(r.name or "?")
      local ch = r.choice or "?"
      if ch == "TMOG" or ch == "ROLL" then
        local rv = tonumber(r.roll or 0) or 0
        ch = ch.." ("..tostring(rv)..")"
      end
      row.choiceFS:SetText(ch)
      row.rankFS:SetText(normalizedRank(r.name or "?"))
      row.commentFS:SetText(r.comment or "")

      -- Vote-Button-Logik
		if r.choice == "TMOG" or r.choice == "ROLL" then
		  -- TMOG / ROLL brauchen keine Votes
		  row.voteBtn:Disable()
		  row.voteBtn:SetText("")
		  row.voteBtn:SetAlpha(0.4)          -- leicht ausgegraut
		else
		  row.voteBtn:Enable()
		  row.voteBtn:SetAlpha(1)
		  row.voteBtn:SetText("Vote")
		  row.voteBtn:SetScript("OnClick", function()
			local voter = CLC_playerName()
			local target = r.name or "?"
			CLC_Votes[key] = CLC_Votes[key] or {}
			CLC_Votes[key][voter] = CLC_Votes[key][voter] or {}
			if CLC_Votes[key][voter][target] then
			  CLC_Votes[key][voter][target] = nil
			  CLC_Send("VOTE_REVOKE", key.."^"..voter.."^"..target)
			else
			  CLC_Votes[key][voter][target] = true
			  CLC_Send("VOTE", key.."^"..voter.."^"..target)
			end
			CLC_RefreshOfficerList()
		  end)
		end

      local voters = CLC_GetVoters(key, r.name or "?")
      row.countFS:SetText(tostring(table.getn(voters)))

	row:SetBackdrop(nil)

    else
      row:Hide()
    end
  end
  setOfficerHeightFor(vis)
end

------------------------------------------------------------
-- Slash-Commands (inkl. Zonenverwaltung & Anchor)
------------------------------------------------------------
local function CLC_SerializeZones()
  local t = {}
  local k,v
  for k,v in pairs(CLC_DB.zones or {}) do if v then table.insert(t, k) end end
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
    CLC_EnsureAnchor()
    if CLC_AnchorFrame:IsShown() then CLC_HideAnchor(); DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON.."|r: Loot-Anker versteckt.")
    else CLC_ShowAnchor(); DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON.."|r: Loot-Anker anzeigen (ziehen, um zu verschieben).") end
  elseif cmd == "anchor reset" then
    CLC_ResetAnchor(); DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..ADDON.."|r: Loot-Anker zurückgesetzt.")
  elseif string.sub(cmd,1,9) == "zone add " then
    local z = string.sub(cmd, 10); if z and z ~= "" then CLC_DB.zones[z] = true; DEFAULT_CHAT_FRAME:AddMessage("|cffffff00CLC|r: Zone hinzugefügt: "..z) end
  elseif string.sub(cmd,1,12) == "zone remove " then
    local z = string.sub(cmd, 13); if z and z ~= "" then CLC_DB.zones[z] = nil; DEFAULT_CHAT_FRAME:AddMessage("|cffffff00CLC|r: Zone entfernt: "..z) end
  elseif cmd == "zone list" then
    local s = CLC_SerializeZones(); DEFAULT_CHAT_FRAME:AddMessage("|cffffff00CLC|r Zonen-Whitelist: "..(s ~= "" and s or "(leer)"))
  elseif cmd == "zone reset" then
    CLC_DB.zones = {}; DEFAULT_CHAT_FRAME:AddMessage("|cffffff00CLC|r: Zonen-Whitelist geleert.")
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
local function onSystemRoll(msg)
  -- „Name rolls X (A-B)“ (DE/EN)
  local who, rollStr, minStr, maxStr = SMATCH(msg, "^([^%s]+)%s+.*(%d+)%s*%((%d+)%-(%d+)%)")
  if not who then
    -- Fallback DE: "Name würfelt X (A-B)"
    who, rollStr, minStr, maxStr = SMATCH(msg, "^([^%s]+)%s+%S+%s+(%d+)%s*%((%d+)%-(%d+)%)")
  end
  local r = tonumber(rollStr or "0") or 0
  local lo = tonumber(minStr or "0") or 0
  local hi = tonumber(maxStr or "0") or 0
  if r <= 0 or hi <= 0 then return end

  -- TMOG oder ROLL pending?
  if CLC_PendingRoll and CLC_PendingRoll.player == who and CLC_PendingRoll.high == hi then
    if hi == 10 then CLC_SendTmogRoll(CLC_PendingRoll.itemKey, r) end
    CLC_PendingRoll = nil
    return
  end
end

local function CLC_ML_MaybeInjectBossQuestItem()
  if not (CanPlayerTriggerLoot() and CLC_DB and CLC_DB.bossQuestItems) then return end

  local boss = UnitName("target")
  local entry = boss and CLC_DB.bossQuestItems[boss]
  if not entry then return end

  local wantedID = entry.itemID
  if not wantedID then return end

  -- 1) Prüfen, ob das Item in der WIRKLICHEN Lootliste ist
  local present = false
  local i
  for i = 1, GetNumLootItems() do
    local link = GetLootSlotLink(i)
    if link then
      local id1 = SMATCH(link, "Hitem:(%d+):")
      local id2 = SMATCH(link, "|Hitem:(%d+):")
      local iid = tonumber(id1 or id2 or "0") or 0
      if iid == wantedID then present = true; break end
    end
  end
  if present then return end  -- ML sieht es → nichts synthetisch senden

  -- 2) Key & Dedupe (gegen bereits gesendete synthetische Items der Session)
  local link = string.format("|cffa335ee|Hitem:%d:0:0:0|h[%s]|h|r", wantedID, entry.name)
  local key = CLC_itemKeyFromLink(link)
  if CLC_SyntheticSent[key] then return end  -- bereits gesendet (z. B. erneuter Klick)
  -- (zusätzlich schützt deine ITEM-Verarbeitung ohnehin via CLC_Items vor Duplikaten)

  -- 3) Icon bestimmen (DB → GetItemInfo → Fallback)
  local icon = entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
  local iname, ilink, iquality, _, _, _, _, _, _, iicon = GetItemInfo(wantedID)
  if ilink then link = ilink end
  if iicon then icon = iicon end

  -- 4) Session sicherstellen (ML darf starten)
  if not CLC_SessionActive then
    -- kleine Sicherheit: nur starten, wenn wirklich etwas zu senden ist
    startSessionIfNeeded()
  end

  -- 5) Senden & merken
  CLC_Send("ITEM", link.."^"..icon.."^1")
  CLC_SyntheticSent[key] = true
end

function CLC_OnEvent()
  if event == "VARIABLES_LOADED" or event == "PLAYER_LOGIN" then
    CLC_EnsureDB()
    CLC_IsRaid = CLC_isRaid(); CLC_InAllowedZone = inAllowedZone(); refreshGuildRoster()

  elseif event == "PLAYER_ENTERING_WORLD" or event == "RAID_ROSTER_UPDATE" then
    CLC_IsRaid = CLC_isRaid(); CLC_InAllowedZone = inAllowedZone(); refreshGuildRoster()

  elseif event == "PLAYER_LOOT_METHOD_CHANGED" then
	CLC_IsRaid = CLC_isRaid(); CLC_InAllowedZone = inAllowedZone(); refreshGuildRoster()
	CLC_UpdateAnnounceButton()

  elseif event == "LOOT_OPENED" then
    if not CLC_SessionActive then CLC_BroadcastLoot() end
	-- ML-only: Boss-Quest-Items synthetisch hinzufügen, falls sie nicht sichtbar sind
	CLC_ML_MaybeInjectBossQuestItem()

  elseif event == "GUILD_ROSTER_UPDATE" then
    if isCouncil(CLC_playerName()) and CLC_OfficerFrame and CLC_OfficerFrame:IsShown() then CLC_RefreshOfficerList() end

  elseif event == "CHAT_MSG_ADDON" then
    local prefix, message, channel, sender = arg1, arg2, arg3, arg4
    if prefix == "CLC" then CLC_OnMessage(sender, message) end

  elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
    CLC_InAllowedZone = inAllowedZone()

  elseif event == "CHAT_MSG_SYSTEM" then
	local msg = arg1
	if not msg then return end

	local who, rollStr, minStr, maxStr = SMATCH(msg, "^([^%s]+).-(%d+)%s*%((%d+)%-(%d+)%)")
	if not who then return end
	local r = tonumber(rollStr or "0") or 0
	local lo = tonumber(minStr or "0") or 0
	local hi = tonumber(maxStr or "0") or 0
	if r <= 0 or hi <= 0 then return end

	-- 1) TMOG pending (1–10)
	if CLC_PendingRoll and who == CLC_playerName() and lo == 1 and hi == 10 then
	  CLC_Send("TMOGROLL", (CLC_PendingRoll.itemKey or "?").."^"..CLC_playerName().."^"..tostring(r))
	  CLC_PendingRoll = nil
	  return
	end

	-- 2) ROLL-Queue (1–100) etc.
	if who ~= CLC_playerName() then return end
	local key = tostring(lo).."-"..tostring(hi)
	local q = CLC_PendingRollQueues and CLC_PendingRollQueues[key]
	if not q or table.getn(q) == 0 then return end
	local entry = table.remove(q, 1)
	CLC_Send("RESPONSE", entry.key.."^"..CLC_playerName().."^"..entry.choice.."^"..(entry.comment or "").."^"..tostring(r))
  end
end

------------------------------------------------------------
-- Frame + Register
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
frame:SetScript("OnEvent", CLC_OnEvent)

-- State
CLC_IsRaid = false
CLC_InAllowedZone = true
CLC_SessionActive = false
CLC_Responses = CLC_Responses or {}
CLC_Items     = CLC_Items     or {}
CLC_Votes     = CLC_Votes     or {}
