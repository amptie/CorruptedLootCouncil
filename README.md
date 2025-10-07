📘 CorruptedLootCouncil – Slash Commands<br><br>
Allgemein<br>
Befehl	Beschreibung<br>
/clc show	Öffnet das Officer-Panel (nur für berechtigte Ränge).<br>
/clc end	Beendet die aktuelle Loot-Session (nur ML).<br>
/clc anchor	Zeigt/verbirgt den Loot-Anker zum Verschieben der Popup-Position.<br>
/clc anchor reset	Setzt den Loot-Anker auf Standardposition zurück.<br><br>
Zonen-Whitelist<br>
Befehl	Beschreibung<br>
/clc zone add <Zonenname>	Fügt eine Zone zur Whitelist hinzu.<br>
/clc zone remove <Zonenname>	Entfernt eine Zone aus der Whitelist.<br>
/clc zone list	Zeigt die aktuell erlaubten Zonen.<br>
/clc zone reset	Leert die Zonen-Whitelist.<br>
/clc zones push	Sendet die aktuelle Zonen-Whitelist an alle Raid-Teilnehmer (nur RL/RA/ML).<br>
/clc zones accept on/off	Spieler akzeptiert oder blockiert zukünftige Whitelist-Pushes.<br><br>
<br>
💡 Wenn die Whitelist leer ist, ist das Addon in allen Zonen aktiv.<br>
Wenn Zonen eingetragen sind, ist das Addon nur dort aktiv – außer bei Items in der Item-Whitelist.<br><br>

Interne Logik<br>
Feature	Beschreibung<br>
Epische Items & Item-Whitelist	Starten Loot-Popups (außerhalb Whitelist-Zonen nur Whitelist-Items).<br>
Loot-Timer	45 Sekunden (sichtbarer Countdown-Balken).<br>
Roll-Buttons	TMOG (1-10) und Roll (1-100) führen echte Chat-Rolls aus.<br>
Offi-Panel	Zeigt alle Bewerber, Votes, Kommentare, Top-Rolls & Tooltip-Infos.<br>
Rang-Darstellung	Officer/Bereichsleitung/„Raider Veteran“ → „Raider“. Twinks nach Whitelist.<br>
Votes	Klick = Vote/Unvote, Tooltip zeigt alle Voter.<br>
Schnell-Close	„X“ oben rechts im Loot-Popup entspricht „Pass“.<br>
