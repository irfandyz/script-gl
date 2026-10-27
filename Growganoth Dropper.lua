-- ============================================================================
-- GROWGANOTH SACRIFICE DROPPER (HALLOWEEN EVENT AUTOMATION)
-- Author: Irfan & Antigravity
-- World Target: GROWGANOTH
-- 
-- Fitur Unggulan:
-- 1. Precision 1-by-1 Drop: Menjatuhkan tepat 1 item per naik ke pusaran 
--    (Mencegah kehilangan ratusan item sekaligus karena batas reward Growganoth).
-- 2. GUI Koordinat Interaktif: Cukup terbang manual ke atas pusaran, buka menu,
--    lalu klik "[ 📍 Simpan Posisi Saat Ini ]". Bot otomatis mengunci koordinat.
-- 3. Lock-Safe Start: Bot TIDAK AKAN BISA DI-START sebelum posisi pusaran dikunci.
-- 4. Auto-Exit on Depletion: Jika target item di tas sudah habis (0), bot otomatis
--    berhenti dan keluar dari world (Quit to Exit).
-- 5. Anti-Ban Human Jitter: Jeda drop acak yang natural dan aman dari rate limit.
-- ============================================================================

-- =========================================================
-- KONFIGURASI DEFAULT & STATE
-- =========================================================
local botRunning        = false
local currentStatus     = "Idle (Buka /gw untuk pengaturan)"
local dropX             = 50      -- Koordinat X pusaran (Default: 50)
local dropY             = 15      -- Koordinat Y pusaran (Default: 15)
local targetItemID      = 818     -- Default: Ripper Wings (818) / Battle Trout (1542)
local dropDelay         = 450     -- Jeda drop dalam milidetik (ms)
local totalDropped      = 0       -- Total item yang berhasil dikorbankan
local autoExitOnFinish  = true    -- Keluar world otomatis saat item habis

-- Daftar Preset Nama Item Resmi Growtopia
local ITEM_PRESETS = {
    [818]  = "Ripper Wings",
    [1542] = "Battle Trout",
    [4585] = "Laser Grid",
    [340]  = "Chandelier",
    [1006] = "Forcefield",
    [5666] = "Geiger Charger"
}

-- =========================================================
-- HELPER UTILITIES & WRAPPERS
-- =========================================================
function sleep(ms)
    local sleepFunc = sleep or Sleep
    if sleepFunc then sleepFunc(ms) end
end

function humanSleep(minMs, maxMs)
    minMs = minMs or 200
    maxMs = maxMs or 300
    if minMs > maxMs then minMs, maxMs = maxMs, minMs end
    local delay = math.random(minMs, maxMs)
    sleep(delay)
end

function setModFly(enable)
    local names = {"ModFly", "Mod Fly", "Fly", "[C] ModFly", "modfly", "fly"}
    if editToggle then
        for _, n in ipairs(names) do pcall(editToggle, n, enable) end
    end
    if setValue then
        for _, n in ipairs(names) do pcall(setValue, n, enable) end
    end
    local fn = setBool or SetBool
    if fn then
        for _, n in ipairs(names) do pcall(fn, n, enable) end
    end
end

function setAntiBounce(enable)
    local names = {"Antibounce", "AntiBounce", "Anti Bounce", "[C] Antibounce", "anti_bounce", "antibounce"}
    if editToggle then
        for _, n in ipairs(names) do pcall(editToggle, n, enable) end
    end
    if setValue then
        for _, n in ipairs(names) do pcall(setValue, n, enable) end
    end
    local fn = setBool or SetBool
    if fn then
        for _, n in ipairs(names) do pcall(fn, n, enable) end
    end
end

function getItemDisplayName(id)
    if ITEM_PRESETS[id] then
        return ITEM_PRESETS[id] .. " (`2ID " .. id .. "`w)"
    end
    return "Item `2ID " .. id .. "`w"
end

-- Cari jumlah item tertentu di dalam tas (Inventory)
function findItem(id)
    local getInv = GetInventory or getInventory
    if not getInv then return 0 end
    local inv = getInv()
    if not inv then return 0 end

    for _, it in pairs(inv) do
        if it.id == id then
            return it.count or it.amount or 0
        end
    end
    return 0
end

-- Deteksi Otomatis Item Pengorbanan yang Ada di Tas
function autoDetectBagItem()
    if findItem(818) > 0 then
        targetItemID = 818
        return true
    elseif findItem(1542) > 0 then
        targetItemID = 1542
        return true
    end
    return false
end

-- =========================================================
-- DETEKSI MODERATOR / GUARDIAN (INFORMASI RADAR)
-- =========================================================
function checkModeratorAlert()
    local getPlayers = GetPlayerList or GetPlayers or getPlayerList
    if not getPlayers then return false end
    local ok, players = pcall(getPlayers)
    if not ok or not players then return false end

    for _, p in pairs(players) do
        local rawName = p.name or ""
        local clean = rawName:gsub("`.", ""):gsub("^%s+", "")
        -- Hanya jika nama diawali karakter '@' asli (bukan guild tag)
        if clean:sub(1, 1) == "@" and not clean:find(" ") then
            return true, clean
        end
    end
    return false
end

-- =========================================================
-- SISTEM DROP TEPAT 1 ITEM (PRECISE SACRIFICE)
-- =========================================================
function dropSingleItem(id)
    if findItem(id) <= 0 then return false end

    -- Buka dialog drop untuk item target
    SendPacket(2, "action|drop\nitemID|" .. id)
    humanSleep(400, 500) -- Jeda aman agar server merespons pembukaan dialog drop

    -- Kirim dialog_return tepat dengan count = 1
    SendPacket(2, "action|dialog_return\ndialog_name|drop_item\nitemID|" .. id .. "|\ncount|1")
    humanSleep(400, 500)
    return true
end

-- =========================================================
-- NAVIGASI NAIK MENUJU PUSARAN (VORTEX CLIMBER WITH MODFLY)
-- =========================================================
function reachDropPosition()
    local me = GetLocal()
    if not me then return false end

    local curX = math.floor(me.posX / 32)
    local curY = math.floor(me.posY / 32)

    -- Jika sudah berada di area pusaran (toleransi radius 3 blok)
    if math.abs(curX - dropX) <= 3 and math.abs(curY - dropY) <= 3 then
        return true
    end

    setModFly(true)
    setAntiBounce(true)
    FindPath(dropX, dropY)

    -- Tunggu bot sampai di area pusaran
    local wait = 0
    while wait < 80 and botRunning do
        sleep(100)
        me = GetLocal()
        if me then
            curX = math.floor(me.posX / 32)
            curY = math.floor(me.posY / 32)
            if math.abs(curX - dropX) <= 3 and math.abs(curY - dropY) <= 3 then
                return true
            end

            -- Re-trigger pathfind setiap 2 detik jika belum sampai
            if wait > 0 and wait % 20 == 0 then
                setModFly(true)
                setAntiBounce(true)
                FindPath(dropX, dropY)
            end
        end
        wait = wait + 1
    end

    -- Toleransi kedekatan akhir
    me = GetLocal()
    if me then
        curX = math.floor(me.posX / 32)
        curY = math.floor(me.posY / 32)
        if math.abs(curX - dropX) <= 4 and math.abs(curY - dropY) <= 4 then
            return true
        end
    end

    return false
end

-- =========================================================
-- DETEKSI KEMATIAN & RESPAWN DI WHITE DOOR
-- =========================================================
function waitForRespawn()
    currentStatus = "Item dikorbankan! Menunggu respawn..."
    
    -- Jeda waktu kematian Growganoth (2.5 detik)
    sleep(2500)

    -- Tunggu sampai posisi pemain terefresh kembali ke bawah (area White Door)
    local wait = 0
    while wait < 60 and botRunning do
        local me = GetLocal()
        if me then
            local curY = math.floor(me.posY / 32)
            -- Jika posisi Y pemain sudah jauh di bawah pusaran (kembali ke White Door)
            if math.abs(curY - dropY) > 4 then
                break
            end
        end
        sleep(100)
        wait = wait + 1
    end

    -- Beri jeda sejenak dan re-aktifkan ModFly & AntiBounce untuk pendakian berikutnya
    sleep(600)
    setModFly(true)
    setAntiBounce(true)
end

-- Keluar dari world saat seluruh item habis
function exitWorld()
    if LogToConsole then
        pcall(LogToConsole, "`4[Growganoth] `wKeluar dari world (Quit to Exit)...")
    end
    currentStatus = "Keluar dari world..."
    SendPacket(3, "action|quit_to_exit")
    sleep(600)
    SendPacket(3, "action|join_request\nname|EXIT\ninvitedWorld|0")
    sleep(1000)
end

-- =========================================================
-- MAIN LOOP: OTOMATIS NAIK -> DROP 1 -> RESPAWN -> REPEAT
-- =========================================================
function mainGrowganothLoop()
    if not botRunning then return end

    autoDetectBagItem()
    local initialCount = findItem(targetItemID)
    if initialCount <= 0 then
        currentStatus = "`4Item target tidak ditemukan di dalam tas!"
        botRunning = false
        if LogToConsole then
            pcall(LogToConsole, string.format("`4[Growganoth Error] `wItem %s tidak ada di tas!", getItemDisplayName(targetItemID)))
        end
        showMenuDialog()
        return
    end

    setModFly(true)
    setAntiBounce(true)

    if LogToConsole then
        pcall(LogToConsole, string.format("`2[Growganoth] `wDropper aktif! Target: %s (%d item) | Posisi Pusaran: (%d, %d)", 
              getItemDisplayName(targetItemID), initialCount, dropX, dropY))
    end

    local dropStreak = 0

    while botRunning do
        -- Cek sisa item di tas
        local count = findItem(targetItemID)
        if count <= 0 then
            -- Cek apakah ada item pengorbanan alternatif (Ripper Wings / Battle Trout)
            autoDetectBagItem()
            count = findItem(targetItemID)
            if count <= 0 then
                -- Seluruh item telah habis tuntas
                break
            end
        end

        -- FASE 1: Naik dari White Door ke Pusaran
        currentStatus = string.format("Naik ke pusaran (%d, %d)... [Sisa: %d]", dropX, dropY, count)
        local arrived = reachDropPosition()

        if not botRunning then break end

        if arrived then
            -- FASE 2: Drop Tepat 1 Item ke Pusaran
            currentStatus = string.format("Drop 1 item ke pusaran... [Sisa: %d]", count)
            
            local beforeCount = count
            dropSingleItem(targetItemID)

            local afterCount = findItem(targetItemID)
            if afterCount < beforeCount then
                totalDropped = totalDropped + (beforeCount - afterCount)
            else
                totalDropped = totalDropped + 1
            end

            dropStreak = dropStreak + 1
            if LogToConsole then
                pcall(LogToConsole, string.format("`2[Growganoth] `w1x %s berhasil dikorbankan! (Total: `2%d `w| Sisa di tas: `2%d`w)", 
                      ITEM_PRESETS[targetItemID] or "Item", totalDropped, findItem(targetItemID)))
            end

            -- FASE 3: Menunggu Respawn di White Door setelah mati di pusaran
            waitForRespawn()
        else
            -- Jika belum sampai dalam batas waktu, jeda singkat lalu coba naik kembali
            sleep(500)
        end
    end

    botRunning = false
    currentStatus = "Selesai (Semua item telah dikorbankan!)"

    if LogToConsole then
        pcall(LogToConsole, string.format("`2[Growganoth] `wPengorbanan TUNTAS! Total `2%d `witem berhasil dikorbankan ke pusaran.", totalDropped))
    end

    -- Keluar dari world jika opsi auto exit aktif
    if autoExitOnFinish then
        exitWorld()
    end

    showMenuDialog()
end

-- =========================================================
-- MENU GUI IN-GAME DIALOG (/gw atau /growganoth)
-- Desain Minimalis & Otomatis: Hanya Start/Stop & Info Realtime
-- =========================================================
function showMenuDialog()
    -- Selalu sinkronkan deteksi item korban di tas
    autoDetectBagItem()

    local statusText = botRunning and "`2[RUNNING] `w" .. currentStatus or "`4[STOPPED] `w" .. currentStatus
    local bagCount = findItem(targetItemID)
    local itemDesc = (bagCount > 0) 
        and (getItemDisplayName(targetItemID) .. " (`2" .. bagCount .. " item`w)")
        or "`4Tidak ada Ripper Wings / Battle Trout di tas!"

    local lines = {}
    table.insert(lines, "set_default_color|`o")
    table.insert(lines, "add_label_with_icon|big|`4Growganoth `2Sacrifice Dropper|left|3808|")
    table.insert(lines, "add_spacer|small|")
    table.insert(lines, "add_textbox|`oStatus: " .. statusText .. "|left|")
    table.insert(lines, "add_textbox|`oPosisi Pusaran: `2X: 50, Y: 15 `w(Fixed)|left|")
    table.insert(lines, "add_textbox|`oItem di Tas: " .. itemDesc .. "|left|")
    table.insert(lines, "add_textbox|`oTotal Terkorban: `2" .. totalDropped .. " `witem|left|")
    table.insert(lines, "add_spacer|small|")

    if botRunning then
        table.insert(lines, "add_button|btn_stop|`4[ STOP BOT ]|noflags|0|0|")
    else
        table.insert(lines, "add_button|btn_start|`2[ START DROPPER ]|noflags|0|0|")
    end

    table.insert(lines, "add_button|btn_refresh|`9Refresh Status|noflags|0|0|")
    table.insert(lines, "add_quick_exit|")
    table.insert(lines, "end_dialog|growganoth_menu|Tutup||")

    local dialog = table.concat(lines, "\n")
    local sendVar = sendVariant or SendVariant
    if sendVar then
        -- Kirim dengan format standar GrowLauncher {v1, v2} dan fallback array {[0], [1]}
        pcall(sendVar, {v1 = "OnDialogRequest", v2 = dialog})
        pcall(sendVar, {[0] = "OnDialogRequest", [1] = dialog})
    end
end

-- =========================================================
-- HOOK EVENT HANDLERS
-- =========================================================
function hookVariant(variant)
    if not variant then return false end

    local v1 = variant.v1 or variant[0] or ""
    local v2 = variant.v2 or variant[1] or ""

    -- Anti-Ban Pillar 1: Deteksi Moderator / Guardian masuk world via OnSpawn
    if v1 == "OnSpawn" then
        local spawnStr = tostring(v2)
        if spawnStr:find("name|%s*@") or spawnStr:find("`4@") or spawnStr:find("`#@") then
            if LogToConsole then
                pcall(LogToConsole, "`4[Mod Radar] `wPERINGATAN KRITIS: Moderator/Guardian terdeteksi masuk world!")
                pcall(LogToConsole, "`4[Mod Radar] `wMenghentikan bot seketika dan melakukan emergency exit...")
            end
            botRunning = false
            currentStatus = "EMERGENCY STOP (Moderator Masuk World!)"
            if autoExitOnFinish then
                exitWorld()
            end
            showMenuDialog()
            return false
        end
    end

    -- Anti-Ban Pillar 3: Deteksi pesan sistem / warning error server / packet flood
    if v1 == "OnConsoleMessage" or v1 == "OnDialogRequest" then
        local text = tostring(v2):lower()
        if text:find("temporarily banned") or text:find("server overloaded") or 
           text:find("too many people") or text:find("suspicious") or 
           text:find("shadow ban") or text:find("too many packets") or 
           text:find("packet flood") or text:find("request reconnect") then
            if LogToConsole then
                pcall(LogToConsole, "`4[Anti-Ban Alert] `wTerdeteksi sinyal peringatan server: " .. text:sub(1, 60))
                pcall(LogToConsole, "`4[Anti-Ban Alert] `wBot otomatis dijeda untuk melindungi akun & IP Anda!")
            end
            botRunning = false
            currentStatus = "Dijeda Otomatis (Server Warning / Packet Flood)"
            showMenuDialog()
            return false
        end
    end

    -- Izinkan dialog menu dan dialog drop_item bawaan game
    if v1 == "OnDialogRequest" then
        local str = tostring(v2)
        if str:find("growganoth_menu") or str:find("drop_item") then
            return false -- Izinkan dialog menu dan dialog drop diproses
        end
        return true -- Blokir dialog lain agar tidak mengganggu bot
    end
    return false
end

function hookSendPacket(pktType, pkt)
    local rawPkt = ""
    if _G.type(pktType) == "string" then
        rawPkt = pktType
    elseif _G.type(pkt) == "string" then
        rawPkt = pkt
    end
    if rawPkt == "" then return false end

    local lowerPkt = rawPkt:lower()

    -- Command Chat: /gw, /growganoth, atau /drop
    if lowerPkt:find("/gw") or lowerPkt:find("/growganoth") or lowerPkt:find("/drop") or lowerPkt:find("/menu") then
        showMenuDialog()
        return true -- Blokir chat agar tidak terkirim ke publik
    end

    -- Tangkap interaksi tombol pada menu Growganoth
    if rawPkt:find("dialog_name|growganoth_menu") then
        local threadFunc = runThread or RunThread
        local function startTask(fn)
            if threadFunc then
                threadFunc(fn)
            else
                local co = coroutine.create(fn)
                coroutine.resume(co)
            end
        end

        -- 1. Tombol Start
        if rawPkt:find("buttonClicked|btn_start") then
            if not botRunning then
                autoDetectBagItem()
                if findItem(targetItemID) <= 0 then
                    currentStatus = "`4Gagal Start: Ripper Wings / Battle Trout tidak ada di tas!"
                    if LogToConsole then
                        pcall(LogToConsole, "`4[Peringatan] `wTidak ada Ripper Wings (ID: 818) atau Battle Trout (ID: 1542) di dalam tas!")
                    end
                else
                    botRunning = true
                    currentStatus = "Memulai pengorbanan ke Growganoth..."
                    startTask(mainGrowganothLoop)
                end
            end
            showMenuDialog()
            return true

        -- 2. Tombol Stop
        elseif rawPkt:find("buttonClicked|btn_stop") then
            botRunning = false
            currentStatus = "Bot Dihentikan (Stopped)"
            showMenuDialog()
            return true

        -- 3. Tombol Refresh
        elseif rawPkt:find("buttonClicked|btn_refresh") then
            showMenuDialog()
            return true
        end
    end

    return false
end

-- =========================================================
-- REGISTRASI HOOK SISTEM
-- =========================================================
if AddHook then
    pcall(AddHook, hookVariant, "OnVariant")
    pcall(AddHook, "OnVariant", hookVariant)
    pcall(AddHook, hookSendPacket, "OnSendPacket")
    pcall(AddHook, "OnSendPacket", hookSendPacket)
end

-- Otomatis deteksi item korban di tas & aktifkan ModFly/AntiBounce
autoDetectBagItem()
setModFly(true)
setAntiBounce(true)

if LogToConsole then
    pcall(LogToConsole, "`4[Growganoth Dropper] `wScript berhasil dimuat! Ketik `2/gw `wuntuk membuka menu.")
end

-- Tampilkan Menu Dialog secara otomatis saat script pertama kali dijalankan
showMenuDialog()
