-- database.lua - Defaults & EnsureDB

-- TESTMODE (oben im Addon wie gewünscht)
TESTMODE = false
CLC_ITEM_RARITY_DECLARATION = (TESTMODE and 0) or 4          -- 0 im Test, 4 = episch live
CLC_MIN_RAID_SIZE           = (TESTMODE and 2) or 15          -- 2 im Test, 15 live

-- SavedVariables-Root
CLC_DB = CLC_DB or {
  zones = {
    ["Tower of Karazhan"] = true,   -- K40 & K10 teilen Zone-Text => wir gate’n über MinRaidSize
    ["The Rock of Desolation"] = true,
    ["The Stockade"] = true,
  },
  itemWhitelist = {
    -- Deine Key-Items (Beispiele aus deiner Datei)
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
  },
  meta = { zonesVersion = 1, acceptZonePush = true },
  councilRanks = { ["Officer"]=true, ["Offizier"]=true, ["Bereichsleitung"]=true },
  -- Deine Whitelists (aus deiner bestehenden Datei übernommen)
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
    -- >>> NEU: Boss → Quest-Item-Mapping <<<
  bossQuestItems = {
    ["Ley-Watcher Incantagos"] = {
      itemID = 41403,
      name   = "Enchanted Amethyst",
      icon   = "Interface\\Icons\\INV_Enchant_ShardGlowingSmall",
      quality= 4,
    },
    ["Mephistroth"] = {
      itemID = 55579,
      name   = "Heart of Mephistroth",
      icon   = "Interface\\Icons\\BTNHeartAmulet",
      quality= 4,
    },
  },
  lootDuration = 60, -- Lootzeit
  ui = {
    anchor  = { point="CENTER",   rel="CENTER",   x=0,   y=0   },
    officer = { point="CENTER",   rel="CENTER",   x=0,   y=0   },
    ml      = { point="TOPRIGHT", rel="TOPRIGHT", x=-40, y=-160 },
  },
}


-- Robust initialisieren (keine Nil-Tabellen)
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

