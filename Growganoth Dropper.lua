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
local dropX             = 0       -- Koordinat X pusaran (Diset via Menu)
local dropY             = 0       -- Koordinat Y pusaran (Diset via Menu)
local targetItemID      = 2572    -- Default: Ripper Wings (2572) / Battle Trout (3064)
local dropDelay         = 450     -- Jeda drop dalam milidetik (ms)
local totalDropped      = 0       -- Total item yang berhasil dikorbankan
local autoExitOnFinish  = true    -- Keluar world otomatis saat item habis

-- Daftar Preset Nama Item
local ITEM_PRESETS = {
    [2572] = "Ripper Wings",
    [3064] = "Battle Trout",
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

function setModFly(state)
    local fn = setBool or SetBool
    if fn then
        pcall(fn, "ModFly", state)
        pcall(fn, "modfly", state)
    end
end

function setAntiBounce(state)
    local fn = setBool or SetBool
    if fn then
        pcall(fn, "AntiBounce", state)
        pcall(fn, "antibounce", state)
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

-- =========================================================
-- SISTEM DROP TEPAT 1 ITEM (PRECISE SACRIFICE)
-- =========================================================
function dropSingleItem(id)
    if findItem(id) <= 0 then return false end

    -- Buka dialog drop untuk item target
    SendPacket(2, "action|drop\nitemID|" .. id)
    humanSleep(180, 240)

    -- Kirim dialog_return tepat dengan count = 1
    SendPacket(2, "action|dialog_return\ndialog_name|drop_item\nitemID|" .. id .. "|\ncount|1")
    
    -- Jeda pengorbanan yang disesuaikan dengan konfigurasi user
    local halfDelay = math.floor(dropDelay / 2)
    humanSleep(halfDelay, halfDelay + 60)
    return true
end

-- =========================================================
-- NAVIGASI MENUJU PUSARAN (VORTEX POSITIONING)
-- =========================================================
function reachDropPosition()
    local me = GetLocal()
    if not me then return false end

    local curX = math.floor(me.posX / 32)
    local curY = math.floor(me.posY / 32)

    -- Jika sudah berada tepat di pusaran
    if curX == dropX and curY == dropY then
        return true
    end

    setModFly(true)
    setAntiBounce(true)
    FindPath(dropX, dropY)

    -- Tunggu bot sampai di koordinat tujuan
    local wait = 0
    while wait < 35 and botRunning do
        sleep(100)
        me = GetLocal()
        if me then
            curX = math.floor(me.posX / 32)
            curY = math.floor(me.posY / 32)
            if curX == dropX and curY == dropY then
                return true
            end
        end
        wait = wait + 1
    end

    return false
end

-- Keluar dari world saat seluruh item habis
function exitWorld()
    if LogToConsole then
        pcall(LogToConsole, "`4[Growganoth] `wSemua item telah habis! Keluar dari world...")
    end
    currentStatus = "Item habis, keluar dari world..."
    SendPacket(3, "action|quit_to_exit")
    sleep(600)
    SendPacket(3, "action|join_request\nname|EXIT\ninvitedWorld|0")
    sleep(1000)
end

-- =========================================================
-- MAIN LOOP: EKSEKUSI PENGORBANAN KE GROWGANOTH
-- =========================================================
function mainGrowganothLoop()
    if not botRunning then return end

    -- Validasi 1: Koordinat Pusaran harus sudah ditentukan!
    if dropX == 0 and dropY == 0 then
        currentStatus = "`4Posisi pusaran belum diset! (Klik Simpan Posisi)"
        botRunning = false
        if LogToConsole then
            pcall(LogToConsole, "`4[Growganoth Error] `wHarap tentukan posisi pusaran terlebih dahulu di menu (/gw)!")
        end
        showMenuDialog()
        return
    end

    -- Validasi 2: Item harus tersedia di dalam tas
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
        pcall(LogToConsole, string.format("`2[Growganoth] `wDropper dimulai! Target: %s (%d item) | Posisi: (%d, %d)", 
              getItemDisplayName(targetItemID), initialCount, dropX, dropY))
    end

    while botRunning do
        local count = findItem(targetItemID)
        if count <= 0 then
            -- Seluruh item telah habis dikorbankan
            break
        end

        currentStatus = string.format("Naik ke pusaran (%d, %d)... [Sisa: %d]", dropX, dropY, count)
        local arrived = reachDropPosition()

        if not botRunning then break end

        if arrived then
            currentStatus = string.format("Drop 1 item ke pusaran... [Sisa: %d]", count)
            
            local beforeCount = count
            dropSingleItem(targetItemID)

            -- Verifikasi apakah item berkurang
            local afterCount = findItem(targetItemID)
            if afterCount < beforeCount then
                totalDropped = totalDropped + (beforeCount - afterCount)
            else
                -- Jika packet drop terlewat atau cooldown dialog, beri jeda singkat
                humanSleep(150, 250)
            end
        else
            -- Jika gagal mencapai posisi (misal terpental atau respawn di White Door), istirahat sejenak
            humanSleep(250, 400)
        end
    end

    botRunning = false
    currentStatus = "Selesai (Semua item telah dikorbankan!)"

    if LogToConsole then
        pcall(LogToConsole, string.format("`2[Growganoth] `wTuntas! Total `2%d `witem berhasil dikorbankan ke pusaran.", totalDropped))
    end

    -- Keluar dari world jika opsi auto exit aktif
    if autoExitOnFinish then
        exitWorld()
    end

    showMenuDialog()
end

-- =========================================================
-- MENU GUI IN-GAME DIALOG (/gw atau /growganoth)
-- =========================================================
function showMenuDialog()
    local statusText = botRunning and "`2[RUNNING] `w" .. currentStatus or "`4[STOPPED] `w" .. currentStatus
    local posText = (dropX > 0 and dropY > 0) 
        and string.format("`2X: %d, Y: %d `w(Terkunci)", dropX, dropY) 
        or "`4Belum diset! (Harap klik Simpan Posisi)"
    local bagCount = findItem(targetItemID)
    local itemName = getItemDisplayName(targetItemID)

    local lines = {}
    table.insert(lines, "set_default_color|`o")
    table.insert(lines, "add_label_with_icon|big|`4Growganoth `2Sacrifice Dropper|left|3808|")
    table.insert(lines, "add_spacer|small|")
    table.insert(lines, "add_textbox|`oStatus: " .. statusText .. "|left|")
    table.insert(lines, "add_textbox|`oPosisi Pusaran: " .. posText .. "|left|")
    table.insert(lines, "add_textbox|`oTarget Item: " .. itemName .. "|left|")
    table.insert(lines, "add_textbox|`oSisa di Tas: `2" .. bagCount .. " `witem | Total Terbuang: `2" .. totalDropped .. " `witem|left|")
    table.insert(lines, "add_spacer|small|")

    table.insert(lines, "add_button|btn_save_pos|`3[ 📍 Simpan Posisi Saat Ini ]|noflags|0|0|")
    table.insert(lines, "add_spacer|small|")

    table.insert(lines, "add_text_input|input_item_id|Target Item ID:|" .. targetItemID .. "|6|")
    table.insert(lines, "add_text_input|input_drop_delay|Jeda Drop (ms):|" .. dropDelay .. "|5|")
    table.insert(lines, "add_spacer|small|")

    -- Tombol Preset Cepat Pilihan Populer
    table.insert(lines, "add_button|btn_preset_ripper|`5Preset: Ripper Wings (2572)|noflags|0|0|")
    table.insert(lines, "add_button|btn_preset_trout|`1Preset: Battle Trout (3064)|noflags|0|0|")
    table.insert(lines, "add_spacer|small|")

    if botRunning then
        table.insert(lines, "add_button|btn_stop|`4[ STOP BOT ]|noflags|0|0|")
    else
        table.insert(lines, "add_button|btn_start|`2[ START DROPPER ]|noflags|0|0|")
    end

    table.insert(lines, "add_button|btn_refresh|`9Refresh Status|noflags|0|0|")
    table.insert(lines, "add_quick_exit|")
    table.insert(lines, "end_dialog|growganoth_menu|Simpan & Tutup||")

    local dialog = table.concat(lines, "\n")
    local sendVar = sendVariant or SendVariant
    if sendVar then
        sendVar({[0] = "OnDialogRequest", [1] = dialog})
    end
end

-- =========================================================
-- HOOK EVENT HANDLERS
-- =========================================================
function hookVariant(variant)
    if not variant then return false end

    -- Blokir dialog bawaan game saat membuka menu kustom
    if variant.v1 == "OnDialogRequest" then
        if variant.v2 and variant.v2:find("growganoth_menu") then
            return false
        end
        return true
    end
    return false
end

function hookSendPacket(type, pkt)
    if not pkt then return false end

    -- Command Chat: /gw, /growganoth, atau /drop
    if pkt:find("/gw") or pkt:find("/growganoth") or pkt:find("/drop") then
        showMenuDialog()
        return true
    end

    -- Tangkap interaksi pada menu Growganoth
    if pkt:find("dialog_name|growganoth_menu") then
        -- Tangkap input form ID & Delay
        local newId = pkt:match("input_item_id|([^|\n]+)")
        if newId and tonumber(newId) then
            targetItemID = tonumber(newId)
        end

        local newDelay = pkt:match("input_drop_delay|([^|\n]+)")
        if newDelay and tonumber(newDelay) then
            dropDelay = math.max(250, tonumber(newDelay))
        end

        local threadFunc = runThread or RunThread
        local function startTask(fn)
            if threadFunc then
                threadFunc(fn)
            else
                local co = coroutine.create(fn)
                coroutine.resume(co)
            end
        end

        -- 1. Tombol Simpan Posisi Saat Ini
        if pkt:find("buttonClicked|btn_save_pos") then
            local me = GetLocal()
            if me then
                dropX = math.floor(me.posX / 32)
                dropY = math.floor(me.posY / 32)
                currentStatus = string.format("Posisi pusaran terkunci di (%d, %d)", dropX, dropY)
                if LogToConsole then
                    pcall(LogToConsole, string.format("`2[Growganoth] `wPosisi pusaran berhasil disimpan: `2(%d, %d)", dropX, dropY))
                end
            end
            showMenuDialog()
            return true

        -- 2. Preset Ripper Wings
        elseif pkt:find("buttonClicked|btn_preset_ripper") then
            targetItemID = 2572
            if LogToConsole then
                pcall(LogToConsole, "`5[Growganoth] `wTarget diatur ke Ripper Wings (ID: 2572)")
            end
            showMenuDialog()
            return true

        -- 3. Preset Battle Trout
        elseif pkt:find("buttonClicked|btn_preset_trout") then
            targetItemID = 3064
            if LogToConsole then
                pcall(LogToConsole, "`1[Growganoth] `wTarget diatur ke Battle Trout (ID: 3064)")
            end
            showMenuDialog()
            return true

        -- 4. Tombol Start
        elseif pkt:find("buttonClicked|btn_start") then
            if not botRunning then
                if dropX == 0 and dropY == 0 then
                    currentStatus = "`4Gagal Start: Kunci koordinat pusaran dulu!"
                    if LogToConsole then
                        pcall(LogToConsole, "`4[Peringatan] `wHarap berdiri di atas pusaran lalu klik '[ 📍 Simpan Posisi Saat Ini ]' terlebih dahulu!")
                    end
                elseif findItem(targetItemID) <= 0 then
                    currentStatus = "`4Gagal Start: Item tidak ada di tas!"
                    if LogToConsole then
                        pcall(LogToConsole, string.format("`4[Peringatan] `wItem %s tidak ditemukan di tas!", getItemDisplayName(targetItemID)))
                    end
                else
                    botRunning = true
                    currentStatus = "Memulai pengorbanan ke Growganoth..."
                    startTask(mainGrowganothLoop)
                end
            end
            showMenuDialog()
            return true

        -- 5. Tombol Stop
        elseif pkt:find("buttonClicked|btn_stop") then
            botRunning = false
            currentStatus = "Bot Dihentikan (Stopped)"
            showMenuDialog()
            return true

        -- 6. Tombol Refresh
        elseif pkt:find("buttonClicked|btn_refresh") then
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

if LogToConsole then
    pcall(LogToConsole, "`4[Growganoth Dropper] `wScript siap! Ketik `2/gw `watau `2/growganoth `wuntuk membuka menu.")
end
