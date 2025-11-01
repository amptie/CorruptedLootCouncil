-- utils.lua - Vanilla 1.12 (Lua 5.0) kompatible Helfer

-- Globale Tabellen, die von main.lua genutzt werden (bewusst global, da 1.12)
CLC_WindowOrder     = CLC_WindowOrder     or {}
CLC_ItemWindows     = CLC_ItemWindows     or {}
CLC_EditSeq         = CLC_EditSeq         or 0
CLC_UniqCounter     = CLC_UniqCounter     or 0
CLC_TmogRolls       = CLC_TmogRolls       or {}   -- [itemKey][player]=roll
CLC_PendingRoll     = CLC_PendingRoll     or nil  -- {player,low,high,itemKey,expires}
CLC_PendingRollQueues = CLC_PendingRollQueues or { ["1-10"] = {}, ["1-100"] = {} }

-- Lua 5.0 safe helpers
function CLC_tlen(t) return table.getn(t) end
function CLC_now() return time() end
function CLC_playerName() local n = UnitName("player"); return n or "?" end
function CLC_isRaid() local n = GetNumRaidMembers(); return n and n > 0 end

-- Ersatz für string.match ⇒ gibt nur Captures zurück
function SMATCH(str, pattern)
  if not str or not pattern then return end
  local a,b,c,d,e,f,g,h,i,j = string.find(str, pattern)
  return c,d,e,f,g,h,i,j
end

-- Chat-Safety (gegen CTL / fehlerhafte Escapes)
function CLC_EscapeChat(msg)
  if not msg then return "" end
  msg = string.gsub(msg, "|", "||")
  msg = string.gsub(msg, "%c", "")
  if string.len(msg) > 240 then msg = string.sub(msg, 1, 240) end
  return msg
end

-- Item-Key & Anzeige-Text
function CLC_ItemTextFromLink(link)
  if not link then return "[]" end
  local name = SMATCH(link, "%[([^%]]+)%]")
  if name then return "[" .. name .. "]" end
  return tostring(link)
end

function CLC_itemKeyFromLink(link)
  -- Bewusst einfach: der verlinkte String ist unser logischer Key
  return link or "?"
end

-- Backdrop (Classic Dialog)
function CLC_ApplyDialogBackdrop(f)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
  })
end

-- Frame-Positionen speichern/wiederherstellen
function CLC_SavePos(frameRef, slot)
  if not CLC_DB then return end
  local p, _, rp, x, y = frameRef:GetPoint(1)
  CLC_DB.ui = CLC_DB.ui or {}
  CLC_DB.ui[slot] = {
    point = p or "CENTER",
    rel   = rp or "CENTER",
    x     = math.floor((x or 0) + 0.5),
    y     = math.floor((y or 0) + 0.5),
  }
end

function CLC_RestorePos(frameRef, slot, defaultPoint, defaultRel, dx, dy)
  if not CLC_DB then return end
  CLC_DB.ui = CLC_DB.ui or {}
  local s = CLC_DB.ui[slot] or { point=defaultPoint, rel=defaultRel, x=dx, y=dy }
  frameRef:ClearAllPoints()
  frameRef:SetPoint(s.point or defaultPoint, UIParent, s.rel or defaultRel, s.x or dx, s.y or dy)
end

-- Loot-Anker / Stacking-Logik
local function _positionStacked(f)
  CLC_CompactWindowOrder()
  local s = (CLC_DB and CLC_DB.ui and CLC_DB.ui.anchor) or { point="CENTER", rel="CENTER", x=0, y=0 }
  local idx = 1
  local i
  for i=1, table.getn(CLC_WindowOrder) do
    if CLC_WindowOrder[i] == f then idx = i; break end
  end
  f:ClearAllPoints()
  local y = (s.y or 0) - (idx - 1) * (f:GetHeight() + 8)
  f:SetPoint(s.point or "CENTER", UIParent, s.rel or "CENTER", s.x or 0, y)
end

function CLC_TrackWindow(f)
  local i
  for i=1, table.getn(CLC_WindowOrder) do
    if CLC_WindowOrder[i] == f then return end
  end
  table.insert(CLC_WindowOrder, f)
  _positionStacked(f)
end

function CLC_UntrackWindow(f)
  local out = {}
  local i
  for i=1, table.getn(CLC_WindowOrder) do
    if CLC_WindowOrder[i] ~= f then table.insert(out, CLC_WindowOrder[i]) end
  end
  CLC_WindowOrder = out
  for i=1, table.getn(CLC_WindowOrder) do
    _positionStacked(CLC_WindowOrder[i])
  end
end

-- Anchor-Frame
function CLC_EnsureAnchor()
  if CLC_AnchorFrame then return end
  local f = CreateFrame("Frame", "CLC_Anchor", UIParent)
  f:SetWidth(140); f:SetHeight(28); f:SetFrameStrata("DIALOG")
  CLC_ApplyDialogBackdrop(f)
  local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("CENTER", f, "CENTER", 0, 0); label:SetText("CLC Loot-Anker")
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop",  function() this:StopMovingOrSizing(); CLC_SavePos(this, "anchor") end)
  CLC_RestorePos(f, "anchor", "CENTER", "CENTER", 0, 0)
  f:Hide()
  CLC_AnchorFrame = f
end

function CLC_ShowAnchor() CLC_EnsureAnchor(); CLC_AnchorFrame:Show() end
function CLC_HideAnchor() if CLC_AnchorFrame then CLC_AnchorFrame:Hide() end end
function CLC_ResetAnchor()
  CLC_EnsureAnchor()
  CLC_DB.ui.anchor = { point="CENTER", rel="CENTER", x=0, y=0 }
  CLC_RestorePos(CLC_AnchorFrame, "anchor", "CENTER", "CENTER", 0, 0)
end

-- Uniq-Key für einzelne Fenster (auch bei Duplikaten wichtig)
local function _newWindowKey()
  CLC_UniqCounter = (CLC_UniqCounter or 0) + 1
  return "occ#" .. tostring(CLC_UniqCounter)
end

function CLC_NewWindowKeyForItem(itemKey)
  return itemKey .. "::" .. _newWindowKey()
end

-- Per-Session Reset
function CLC_WipePerSessionState()
  CLC_TmogRolls = {}
  CLC_PendingRoll = nil
  CLC_PendingRollQueues = { ["1-10"] = {}, ["1-100"] = {} }
end

function CLC_CompactWindowOrder()
  local out = {}
  local i
  for i=1, table.getn(CLC_WindowOrder) do
    local f = CLC_WindowOrder[i]
    if f and f:IsShown() then
      table.insert(out, f)
    end
  end
  CLC_WindowOrder = out
end

function CLC_ReflowWindows()
  CLC_CompactWindowOrder()
  local i
  for i=1, table.getn(CLC_WindowOrder) do
    local f = CLC_WindowOrder[i]
    if f then
      -- nutze deine vorhandene _positionStacked(f)
      -- falls die Funktion lokal ist, rufe den internen Repos-Code hier nochmal auf
      -- oder exponiere _positionStacked als global
      -- Beispiel (wenn global):
      _positionStacked(f)
    end
  end
end