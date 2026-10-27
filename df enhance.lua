-- Compatibility layer: memastikan kompatibilitas antar versi GrowLauncher (case-sensitive safety)
local Sleep = Sleep or sleep
local sleep = Sleep
local SendPacket = SendPacket or sendPacket
local sendPacket = SendPacket
local SendPacketRaw = SendPacketRaw or sendPacketRaw
local sendPacketRaw = SendPacketRaw
local GetLocal = GetLocal or getLocal
local getLocal = GetLocal
local GetTile = GetTile or getTile
local getTile = GetTile
local GetTiles = GetTiles or getTiles
local getTiles = GetTiles
local GetInventory = GetInventory or getInventory
local getInventory = GetInventory
local GetObjectList = GetObjectList or getObjectList or getObjects or GetObjects
local getObjectList = GetObjectList
local FindPath = FindPath or findPath
local findPath = FindPath
local AddHook = AddHook or addHook
local addHook = AddHook
local editToggle = editToggle or EditToggle
local setValue = setValue or SetValue
local runThread = runThread or RunThread or (coroutine and coroutine.wrap)
local SendVariant = SendVariant or sendVariant
local sendVariant = SendVariant
local LogToConsole = LogToConsole or logToConsole or log or Log


-- =========================================================
-- STATUS & KONTROL BOT
-- =========================================================
local botRunning = false
local currentStatus = "Idle (Tekan START)"

-- Proteksi Anti-Ban & Jitter Seed
pcall(math.randomseed, os.time())
local lastWarpTime = 0
local MIN_WARP_INTERVAL = 4 -- Jeda aman natural (detik) antar warp untuk proteksi sub-server rate limit

-- Fungsi Sleep dengan variasi manusiawi (Human Jitter)
function humanSleep(minMs, maxMs)
    if not maxMs or maxMs <= minMs then
        Sleep(minMs)
    else
        Sleep(math.random(minMs, maxMs))
    end
end

-- =========================================================
-- KONFIGURASI GUDANG & WORLD PENYIMPANAN
-- =========================================================
local STORAGE_WORLD = "PLATSTORES" -- World gudang penyimpanan & restock

local MAIN_WORLD = ""              -- Kosongkan jika ingin auto-detect world saat ini
local MAIN_WORLD_DOOR = ""         -- Door ID world utama (jika ada)

-- Mapping Door ID di dalam world PLATSTORES untuk setiap item yang disetor
local ITEM_DOOR_MAP = {
    [3]   = "DSEED",  -- Dirt Seed (hanya drop 50 saat limit, sisakan 150 untuk kebun & farm)
    [4]   = "LBLOCK", -- Lava Block
    [5]   = "LSEED",  -- Lava Seed
    [10]  = "RBLOCK", -- Rock Block
    [11]  = "RSEED",  -- Rock Seed
    [15]  = "CSEED",  -- Cave BG Seed
    [102] = "PLAT"    -- Wooden Platform (tempat restock)
}

-- Whitelist item yang dipungut oleh bot (termasuk Dirt Block & Cave BG untuk ditrash lokal)
local COLLECT_WHITELIST = {
    [2]   = true, -- Dirt Block (auto trash 100 jika >= 200)
    [3]   = true, -- Dirt Seed (drop ke DSEED)
    [4]   = true, -- Lava Block (drop ke LBLOCK)
    [5]   = true, -- Lava Seed (drop ke LSEED)
    [10]  = true, -- Rock Block (drop ke RBLOCK)
    [11]  = true, -- Rock Seed (drop ke RSEED)
    [14]   = true, -- Cave Background (auto trash 200 jika >= 200)
    [15]   = true, -- Cave BG Seed (drop ke CSEED)
    [102]  = true, -- Wooden Platform
    [112]  = true, -- Gems
    [2914] = true, -- Wiggly Worm (disimpan di tas, tidak di-drop/trash)
    [2915] = true  -- Wiggly Worm Seed
}

local currentMainWorld = nil

function getMainWorldName()
    if MAIN_WORLD ~= "" then
        return MAIN_WORLD
    end
    if currentMainWorld and currentMainWorld ~= "" then
        return currentMainWorld
    end
    local name = (GetWorldName and GetWorldName()) or 
                 (getWorldName and getWorldName()) or 
                 (getCurrentWorldName and getCurrentWorldName()) or
                 (GetWorld and GetWorld() and GetWorld().name) or
                 (getWorld and getWorld() and getWorld().name)
    if name and name ~= "" and name:upper() ~= STORAGE_WORLD then
        currentMainWorld = name:upper()
        return currentMainWorld
    end
    return currentMainWorld
end

-- =========================================================
-- FUNGSI MODFLY & ANTIBOUNCE
-- =========================================================
function setModFly(enable)
    if editToggle then
        pcall(editToggle, "ModFly", enable)
        pcall(editToggle, "Mod Fly", enable)
        pcall(editToggle, "Fly", enable)
    end
    if setValue then
        pcall(setValue, "ModFly", enable)
        pcall(setValue, "Mod Fly", enable)
        pcall(setValue, "Fly", enable)
    end
end

function setAntiBounce(enable)
    local names = {"Antibounce", "AntiBounce", "Anti Bounce", "[C] Antibounce"}
    if editToggle then
        for _, n in ipairs(names) do
            pcall(editToggle, n, enable)
        end
    end
    if setValue then
        for _, n in ipairs(names) do
            pcall(setValue, n, enable)
        end
    end
end

-- Kontrol Auto Collect Client (dimatikan saat di gudang agar tidak memungut item floating)
function setAutoCollect(enable)
    local names = {"Auto Collect", "Collect", "AutoCollect", "[C] Auto Collect", "Magnet", "[C] Magnet"}
    if editToggle then
        for _, n in ipairs(names) do pcall(editToggle, n, enable) end
    end
    if setValue then
        for _, n in ipairs(names) do pcall(setValue, n, enable) end
    end
end

-- Deteksi apakah saat ini sedang berada di world storage atau proses transfer
function isInStorageWorld()
    local name = (GetWorldName and GetWorldName()) or 
                 (getWorldName and getWorldName()) or 
                 (getCurrentWorldName and getCurrentWorldName()) or
                 (GetWorld and GetWorld() and GetWorld().name) or
                 (getWorld and getWorld() and getWorld().name)
    if name and STORAGE_WORLD and STORAGE_WORLD ~= "" then
        return name:upper() == STORAGE_WORLD:upper()
    end
    return false
end

-- =========================================================
-- FUNGSI DASAR GAMEPLAY & JARINGAN
-- =========================================================
function punch(x, y)
    local packet = {}
    packet.type = 3
    packet.state = 2592
    packet.value = 18
    packet.px = x
    packet.py = y
    packet.x = (GetLocal().posX)
    packet.y = (GetLocal().posY)
    SendPacketRaw(false, packet)
end

function place(x, y, id)
    local packet = {}
    packet.type = 3
    packet.value = id
    packet.px = x
    packet.py = y
    packet.x = (GetLocal().posX)
    packet.y = (GetLocal().posY)
    SendPacketRaw(false, packet)
end

function collectRaw(object)
    -- PROTEKSI KETAT: Dilarang collect di world storage kecuali jika sedang restock platform!
    if (isTransferring or isInStorageWorld()) and not isRestockingPlatform then
        return
    end

    local packet = {}
    packet.type = 11
    packet.value = object.id
    packet.x = object.posX
    packet.y = object.posY
    SendPacketRaw(false, packet)
end

function findItem(itemID)
    for _, item in pairs(GetInventory()) do
        if item.id == itemID then
            return item.amount
        end
    end
    return 0
end

function dropItem(id, count)
    local amount = count or findItem(id)
    if amount > 0 then
        SendPacket(2, "action|drop\nitemID|" .. id)
        humanSleep(450, 600) -- Jeda drop dialog natural
        SendPacket(2, "action|dialog_return\ndialog_name|drop_item\nitemID|" .. id .. "|\ncount|" .. amount)
        humanSleep(450, 600)
    end
end

function trashItem(id, count)
    local amount = count or findItem(id)
    if amount > 0 then
        SendPacket(2, "action|trash\nitemID|" .. id)
        sleep(200)
        SendPacket(2, "action|dialog_return\ndialog_name|trash\nitemID|" .. id .. "|\ncount|" .. amount)
        SendPacket(2, "action|dialog_return\ndialog_name|trash_item\nitemID|" .. id .. "|\ncount|" .. amount)
        sleep(200)
    end
end

-- Fungsi Join Cepat & Aman (Direct Warp tanpa quit_to_exit + Anti-Ban Rate Limiter 4s)
function join(world, id)
    if not world or world == "" then return end
    local targetName = world:upper():gsub(" ", "")

    -- Cek nama world saat ini
    local curName = (GetWorldName and GetWorldName()) or 
                    (getWorldName and getWorldName()) or 
                    (getCurrentWorldName and getCurrentWorldName()) or
                    (GetWorld and GetWorld() and GetWorld().name) or
                    (getWorld and getWorld() and getWorld().name) or ""
    curName = curName:upper():gsub(" ", "")

    -- Jika sudah berada di world tujuan (dan tanpa door ID tertentu), tidak perlu warp!
    if curName == targetName and (not id or id == "") then
        return
    end

    -- 1. Anti-Ban Rate Limiter: Pastikan jeda minimal 4s antar request warp ke server
    local now = os.time()
    local elapsed = now - lastWarpTime
    if elapsed < MIN_WARP_INTERVAL then
        local waitSec = MIN_WARP_INTERVAL - elapsed
        Sleep(waitSec * 1000)
    end

    -- 2. Direct Warp: Langsung request join ke world tujuan (tanpa quit_to_exit yang memakan 12s)
    local targetDoor = (id and id ~= "") and id:upper():gsub(" ", "") or nil
    local joinString = targetDoor and ("action|join_request\nname|" .. targetName .. "|" .. targetDoor .. "\ninvitedWorld|0")
                                  or ("action|join_request\nname|" .. targetName .. "\ninvitedWorld|0")

    local attempt = 0
    local maxRetries = 5

    while botRunning do
        attempt = attempt + 1
        if attempt > maxRetries then
            if LogToConsole then
                pcall(LogToConsole, "`4[Anti-Ban] `wSub-server tersendat (5x gagal). Pendinginan IP 25s...")
            end
            currentStatus = "Cooldown Anti-Ban (25s)..."
            Sleep(25000)
            attempt = 0
        end

        SendPacket(3, joinString)

        -- Polling responsif: tunggu sampai pemain tiba di world tujuan (maks 5s)
        local arrived = false
        for _ = 1, 25 do
            if not botRunning then break end
            humanSleep(180, 220)
            local checkName = (GetWorldName and GetWorldName()) or 
                              (getWorldName and getWorldName()) or 
                              (getCurrentWorldName and getCurrentWorldName()) or
                              (GetWorld and GetWorld() and GetWorld().name) or
                              (getWorld and getWorld() and getWorld().name) or ""
            if checkName:upper():gsub(" ", "") == targetName and getLocal() then
                arrived = true
                break
            end
        end

        if arrived then
            -- Jeda singkat manusiawi agar tile ter-render
            humanSleep(350, 500)

            -- Cek jika spawn tersangkut di White Door
            local p = GetLocal()
            if p then
                local spawnTile = GetTile(math.floor(p.posX / 32), math.floor(p.posY / 32))
                if spawnTile and spawnTile.fg == 6 then
                    SendPacket(3, joinString)
                    humanSleep(1200, 1800)
                end
            end
            break
        end
    end

    lastWarpTime = os.time()
end

-- =========================================================
-- MANAJEMEN WHITE DOOR & KEBUN BIBIT DINAMIS
-- =========================================================
local doorX, doorY = nil, nil

function getWhiteDoor()
    if doorX and doorY then
        return doorX, doorY
    end
    for _, tile in pairs(GetTiles()) do
        if tile.fg == 6 then
            doorX, doorY = tile.x, tile.y
            return doorX, doorY
        end
    end
    local me = GetLocal()
    doorX = math.floor(me.posX / 32)
    doorY = math.floor(me.posY / 32)
    return doorX, doorY
end

function getNurseryRange()
    local dX, dY = getWhiteDoor()
    if dX < 50 then
        return 50, 73, dY
    else
        return 10, 33, dY
    end
end

-- =========================================================
-- AUTO-DROP KE WORLD PLATSTORES (MULTI-WORLD STORAGE)
-- =========================================================
local isTransferring = false
local isBuildingDF = false
local isRestockingPlatform = false

function checkLocalTrash(forceAll)
    -- Saat sedang membangun farm (placeDirt), jangan buang apapun (dirt sangat dibutuhkan)
    if isBuildingDF then return end

    -- Cave BG Block (ID 14): Tidak berguna, langsung trash semua (200)
    local caveBlockCount = findItem(14)
    if caveBlockCount >= 200 or (forceAll and caveBlockCount > 0) then
        trashItem(14, caveBlockCount)
    end

    -- Dirt Block (ID 2): Jika penuh 200, buang 100 saja (sisakan 100 di tas untuk bangun farm)
    local dirtBlockCount = findItem(2)
    if dirtBlockCount >= 200 then
        trashItem(2, 100)
    end
end

function checkAndDropToStorage(forceAll)
    -- Saat sedang membangun farm (placeDirt), jangan pergi ke storage
    if isBuildingDF then return end

    -- 1. Penanganan Auto-Trash Lokal (Cepat di world ini, 0 world-hops):
    checkLocalTrash(forceAll)

    -- 2. Penanganan Item Berharga yang di-drop ke PLATSTORES:
    if isTransferring then return end

    local dirtSeedCount  = findItem(3)
    local rockCount      = findItem(10)
    local rockSeedCount  = findItem(11)
    local caveSeedCount  = findItem(15)
    local lavaCount      = findItem(4)
    local lavaSeedCount  = findItem(5)

    -- Aturan drop ke PLATSTORES (Ambang batas 190 agar tidak tersangkut di 195-199):
    -- Dirt Seed: hanya drop 50 saat mencapai limit agar tersisa 140-150 biji untuk kebun & bangun farm
    local needDropDirtSeed = (dirtSeedCount >= 190) or (forceAll and dirtSeedCount > 150)
    local needDropRock     = (rockCount >= 190) or (forceAll and rockCount > 0)
    local needDropRockSeed = (rockSeedCount >= 190) or (forceAll and rockSeedCount > 0)
    local needDropCaveSeed = (caveSeedCount >= 190) or (forceAll and caveSeedCount > 0)
    local needDropLava     = (lavaCount >= 190) or (forceAll and lavaCount > 0)
    local needDropLavaSeed = (lavaSeedCount >= 190) or (forceAll and lavaSeedCount > 0)

    -- Susun antrean (batch) seluruh item yang harus di-drop
    local dropQueue = {}
    if needDropDirtSeed then
        local toDrop = forceAll and (findItem(3) - 150) or 50
        if toDrop > 0 then
            table.insert(dropQueue, { id = 3, count = toDrop, door = ITEM_DOOR_MAP[3] or "DSEED" })
        end
    end
    if needDropRock and findItem(10) > 0 then
        table.insert(dropQueue, { id = 10, count = findItem(10), door = ITEM_DOOR_MAP[10] or "RBLOCK" })
    end
    if needDropRockSeed and findItem(11) > 0 then
        table.insert(dropQueue, { id = 11, count = findItem(11), door = ITEM_DOOR_MAP[11] or "RSEED" })
    end
    if needDropCaveSeed and findItem(15) > 0 then
        table.insert(dropQueue, { id = 15, count = findItem(15), door = ITEM_DOOR_MAP[15] or "CSEED" })
    end
    if needDropLava and findItem(4) > 0 then
        table.insert(dropQueue, { id = 4, count = findItem(4), door = ITEM_DOOR_MAP[4] or "LBLOCK" })
    end
    if needDropLavaSeed and findItem(5) > 0 then
        table.insert(dropQueue, { id = 5, count = findItem(5), door = ITEM_DOOR_MAP[5] or "LSEED" })
    end

    -- Jika tidak ada item yang memenuhi syarat drop, batalkan
    if #dropQueue == 0 then
        return
    end

    local mainWorld = getMainWorldName()
    if not mainWorld or mainWorld == "" then
        if LogToConsole then
            pcall(LogToConsole, "`4[Error] `wNama world utama tidak terdeteksi! Gagal setor ke PLATSTORES.")
        end
        return
    end

    isTransferring = true
    setAutoCollect(false) -- MATIKAN auto collect saat menyetor ke gudang agar tidak menyedot item orang

    local me = GetLocal()
    local savedX = me and math.floor(me.posX / 32) or 50
    local savedY = me and math.floor(me.posY / 32) or 23

    if LogToConsole then
        pcall(LogToConsole, "`2[Storage] `wMemulai setor " .. #dropQueue .. " jenis item ke " .. STORAGE_WORLD .. " (Batch Mode)...")
    end

    -- SISTEM BATCH: Masuk ke PLATSTORES dan selesaikan SEMUA drop berturut-turut
    -- JANGAN bolak-balik ke mainWorld untuk setiap item!
    local currentDoorInStorage = nil
    for _, item in ipairs(dropQueue) do
        if not botRunning then break end

        -- Berpindah ke door target di PLATSTORES (hanya jika door berbeda)
        if currentDoorInStorage ~= item.door then
            join(STORAGE_WORLD, item.door)
            currentDoorInStorage = item.door

            -- Menghadap ke kanan di marker door ID
            local localPlayer = GetLocal()
            if localPlayer then
                local pkt = {}
                pkt.type = 0
                pkt.x = localPlayer.posX
                pkt.y = localPlayer.posY
                pkt.state = 0 -- Menghadap kanan
                SendPacketRaw(false, pkt)
                humanSleep(150, 250)
            end
        end

        -- Drop item langsung ke lantai sebelah kanan
        if findItem(item.id) >= item.count then
            dropItem(item.id, item.count)
            humanSleep(350, 500)
        end
    end

    -- SETELAH SEMUA ITEM SELESAI DI-DROP: Baru kembali ke world utama (Hanya 1x kembali!)
    join(mainWorld, MAIN_WORLD_DOOR ~= "" and MAIN_WORLD_DOOR or nil)

    -- Re-aktifkan ModFly & AntiBounce
    setModFly(true)
    setAntiBounce(true)
    humanSleep(200, 300)

    -- Jika bukan sesi finishing (sedang di tengah penggalian), kembali ke koordinat kerja galian
    if not forceAll then
        local pathRetry = 0
        while (math.floor(GetLocal().posX / 32) ~= savedX or math.floor(GetLocal().posY / 32) ~= savedY) and pathRetry < 30 and botRunning do
            FindPath(savedX, savedY)
            sleep(400)
            pathRetry = pathRetry + 1
        end
    end

    if LogToConsole then
        pcall(LogToConsole, "`2[Storage] `wSelesai setor batch, kembali ke " .. mainWorld .. ".")
    end

    isTransferring = false
    setAutoCollect(true) -- AKTIFKAN KEMBALI auto collect di world farm
end

-- =========================================================
-- AUTO-RESTOCK WOODEN PLATFORM DARI PLATSTORES|PLAT
-- =========================================================
function restockPlatform()
    local mainWorld = getMainWorldName()
    if not mainWorld or mainWorld == "" then return false end

    isTransferring = true
    setAutoCollect(false)

    -- Masuk ke world PLATSTORES dengan door ID "PLAT"
    join(STORAGE_WORLD, ITEM_DOOR_MAP[102] or "PLAT")

    -- Deteksi Y White Door di PLATSTORES
    local storeDoorY = 23
    for _, tile in pairs(GetTiles()) do
        if tile.fg == 6 then
            storeDoorY = tile.y
            break
        end
    end

    -- Berjalan ke ujung paling kiri yang sejajar dengan White Door (X = 1)
    FindPath(1, storeDoorY)
    humanSleep(250, 400)

    -- Sedot HANYA Wooden Platform (ID 102) dari lantai
    isRestockingPlatform = true
    local retryCollect = 0
    while findItem(102) < 150 and retryCollect < 20 and botRunning do
        for _, obj in pairs(GetObjectList()) do
            if obj.itemid == 102 then
                collectRaw(obj)
                sleep(30)
            end
        end
        sleep(200)
        retryCollect = retryCollect + 1
    end
    isRestockingPlatform = false

    -- Kembali ke world utama
    join(mainWorld, MAIN_WORLD_DOOR ~= "" and MAIN_WORLD_DOOR or nil)

    -- Re-aktifkan ModFly & AntiBounce
    setModFly(true)
    setAntiBounce(true)
    humanSleep(200, 300)

    isTransferring = false
    setAutoCollect(true)
    return findItem(102) > 0
end

-- =========================================================
-- SMART COLLECT (RADIUS PENGAMBILAN LUAS)
-- =========================================================
function smartCollect(range)
    range = range or 4
    if isTransferring then return end

    -- Jangan pernah collect jika sedang berada di world penyimpanan PLATSTORES
    local curWorld = (getWorldName and getWorldName()) or (GetWorldName and GetWorldName())
    if curWorld and curWorld:upper() == STORAGE_WORLD then
        return
    end

    local me = GetLocal()
    if not me then return end
    local myX = me.posX
    local myY = me.posY

    for _, object in pairs(GetObjectList()) do
        -- Whitelist filter: hanya ambil item yang terdaftar di whitelist
        if COLLECT_WHITELIST[object.itemid] then
            if math.abs(myX - object.posX) <= (32 * range) and math.abs(myY - object.posY) <= (32 * range) then
                if findItem(object.itemid) < 200 then
                    collectRaw(object)
                    sleep(25)
                end
            end
        end
    end
    -- Auto-trash lokal jika Cave BG / Dirt Block penuh 200 agar tas tidak macet
    checkLocalTrash()
end

function collect(range)
    smartCollect(range)
end

-- =========================================================
-- FUNGSI PEMBERSIHAN (CLEARING) & NAVIGASI ANTI-STUCK
-- =========================================================

-- Navigasi Pintar & Anti-Spam Packet:
-- 1. Cek apakah bot sudah di posisi target sebelum kirim packet (cegah spam packet & disconnect).
-- 2. Adaptasi delay sleep berdasarkan jarak agar tidak dianggap speed/packet flood.
-- 3. Hancurkan rintangan jika terhalang di lorong ganjil.
function safeFindPath(targetX, targetY)
    local me = GetLocal()
    if me then
        local curX = math.floor(me.posX / 32)
        local curY = math.floor(me.posY / 32)
        -- Jika bot SUDAH berada di petak target, JANGAN kirim packet lagi!
        if curX == targetX and curY == targetY then
            return
        end
    end

    local startX = me and math.floor(me.posX / 32) or targetX
    local startY = me and math.floor(me.posY / 32) or targetY
    local dist = math.max(math.abs(startX - targetX), math.abs(startY - targetY))

    FindPath(targetX, targetY)

    -- Jeda adaptif manusiawi sesuai jarak (menghindari "too many packets")
    if dist > 30 then
        humanSleep(250, 350)
    elseif dist > 8 then
        humanSleep(150, 220)
    else
        humanSleep(80, 130)
    end

    -- Jika posisi belum sampai (kemungkinan terhalang blok di depan)
    me = GetLocal()
    if not me then return end
    local curX = math.floor(me.posX / 32)
    local curY = math.floor(me.posY / 32)

    if curX ~= targetX or curY ~= targetY then
        local targetTile = GetTile(targetX, targetY)
        -- PROTEKSI MUTLAK:
        -- 1. Baris Genap (targetY % 2 == 0) adalah BARIS TANAH DIRT FARM! Dilarang keras dihancurkan!
        -- 2. Platform (102), Bedrock (8), White Door (6) dilarang keras dihancurkan!
        -- 3. HANYA boleh hancurkan jika targetY adalah baris GANJIL (lorong kosong) yang terhalang!
        if targetY % 2 == 1 and targetTile and targetTile.fg ~= 0 and targetTile.fg ~= 8 and targetTile.fg ~= 6 and targetTile.fg ~= 102 then
            local pRetry = 0
            while GetTile(targetX, targetY).fg ~= 0 and pRetry < 35 and botRunning do
                punch(targetX, targetY)
                humanSleep(170, 210)
                pRetry = pRetry + 1
            end
        end
        FindPath(targetX, targetY)
        humanSleep(120, 180)
    end
end

function clearSide()
    local function clearColumn(column)
        for tiley = 24, 53 do
            if not botRunning then return end
            if GetTile(column, tiley).bg == 14 or GetTile(column + 1, tiley).bg == 14 then
                safeFindPath(column, tiley - 1)
                local retry = 0
                while GetTile(column, tiley).bg == 14 and retry < 35 and botRunning do
                    punch(column, tiley)
                    humanSleep(170, 210)
                    retry = retry + 1
                end
                retry = 0
                while GetTile(column + 1, tiley).bg == 14 and retry < 35 and botRunning do
                    punch(column + 1, tiley)
                    humanSleep(170, 210)
                    retry = retry + 1
                end
                sleep(60)
                smartCollect(4)
            end
        end
    end
    clearColumn(0)
    if not botRunning then return end
    clearColumn(98)
    if not botRunning then return end
    checkAndDropToStorage()
end

function clearDirt()
    local function needsPunch(tx, ty)
        if tx < 0 or tx > 99 or ty < 0 or ty > 59 then return false end
        local t = GetTile(tx, ty)
        if not t then return false end
        return (t.bg ~= 0 or t.fg ~= 0) and t.fg ~= 8 and t.fg ~= 6
    end

    for tiley = 27, 51, 12 do
        if not botRunning then return end

        -- Arah maju: kiri ke kanan
        for tilex = 2, 97, 1 do
            if not botRunning then return end
            if needsPunch(tilex, tiley - 2) or needsPunch(tilex, tiley) or needsPunch(tilex, tiley + 2) then 
                safeFindPath(tilex - 1, tiley)
                humanSleep(60, 90)

                -- PENTING: Utamakan hancurkan tile tengah jalur (tiley) terlebih dahulu!
                -- Ini menjamin jalan di depan player tidak pernah terhalang blok solid.
                local offsets = {0, -2, 2}
                for _, i in ipairs(offsets) do
                    if not botRunning then return end
                    local retry = 0
                    while needsPunch(tilex, tiley + i) and retry < 35 and botRunning do
                        punch(tilex, tiley + i)
                        humanSleep(170, 210)
                        retry = retry + 1
                    end
                end

                -- Garansi Anti-Stuck: Pastikan petak yang akan diinjak di langkah berikutnya benar-benar bersih!
                local pBlock = GetTile(tilex, tiley)
                if pBlock and pBlock.fg ~= 0 and pBlock.fg ~= 8 and pBlock.fg ~= 6 then
                    local retryFinish = 0
                    while GetTile(tilex, tiley).fg ~= 0 and retryFinish < 30 and botRunning do
                        punch(tilex, tiley)
                        humanSleep(170, 210)
                        retryFinish = retryFinish + 1
                    end
                end

                humanSleep(30, 50)
                smartCollect(4)
            end
            if tilex % 15 == 0 then
                checkAndDropToStorage()
            end
        end
        if not botRunning then return end
        checkAndDropToStorage()

        -- Arah mundur: kanan ke kiri
        if (tiley + 6) ~= 57 then
            for tilex = 97, 2, -1 do
                if not botRunning then return end
                if needsPunch(tilex, tiley + 4) or needsPunch(tilex, tiley + 6) or needsPunch(tilex, tiley + 8) then 
                    safeFindPath(tilex + 1, tiley + 6)
                    humanSleep(60, 90)

                    -- PENTING: Utamakan hancurkan tile tengah jalur mundur (tiley + 6)
                    local offsets = {6, 4, 8}
                    for _, i in ipairs(offsets) do
                        if not botRunning then return end
                        local retry = 0
                        while needsPunch(tilex, tiley + i) and retry < 35 and botRunning do
                            punch(tilex, tiley + i)
                            humanSleep(170, 210)
                            retry = retry + 1
                        end
                    end

                    -- Garansi Anti-Stuck: Pastikan petak yang akan diinjak di langkah berikutnya benar-benar bersih!
                    local pBlock = GetTile(tilex, tiley + 6)
                    if pBlock and pBlock.fg ~= 0 and pBlock.fg ~= 8 and pBlock.fg ~= 6 then
                        local retryFinish = 0
                        while GetTile(tilex, tiley + 6).fg ~= 0 and retryFinish < 30 and botRunning do
                            punch(tilex, tiley + 6)
                            humanSleep(170, 210)
                            retryFinish = retryFinish + 1
                        end
                    end

                    humanSleep(30, 50)
                    smartCollect(4)
                end
                if tilex % 15 == 0 then
                    checkAndDropToStorage()
                end
            end
            if not botRunning then return end
            checkAndDropToStorage()
        end
    end
end

function breakLava()
    currentStatus = "Membersihkan Lava (breakLava)..."
    for _, tile in pairs(GetTiles()) do
        if not botRunning then return end
        if tile.fg == 4 then
            -- Tentukan posisi berdiri aman di samping atau di atas lava
            local standX, standY = tile.x, tile.y - 1
            local upperT = GetTile(standX, standY)
            if upperT and upperT.fg ~= 0 and upperT.fg ~= 4 then
                if tile.x > 1 and GetTile(tile.x - 1, tile.y).fg == 0 then
                    standX, standY = tile.x - 1, tile.y
                elseif tile.x < 98 and GetTile(tile.x + 1, tile.y).fg == 0 then
                    standX, standY = tile.x + 1, tile.y
                end
            end

            local me = GetLocal()
            local curX = me and math.floor(me.posX / 32) or -1
            local curY = me and math.floor(me.posY / 32) or -1
            if math.abs(curX - standX) > 1 or math.abs(curY - standY) > 1 then
                safeFindPath(standX, standY)
            end

            -- Lava hanya butuh 3 kali hit di Growtopia! Dibatasi maksimal 12 retry cepat (150-180ms)
            local retry = 0
            while GetTile(tile.x, tile.y).fg == 4 and retry < 12 and botRunning do
                punch(tile.x, tile.y)
                humanSleep(150, 180)
                retry = retry + 1
            end

            humanSleep(30, 50)
            smartCollect(4)

            -- Tambal dengan tanah jika lava berada di baris tanah farm (baris genap Y = 24..54)
            if tile.y >= 24 and tile.y <= 54 and (tile.y % 2 == 0) and tile.x >= 2 and tile.x <= 97 and GetTile(tile.x, tile.y).fg == 0 then
                if findItem(2) == 0 then smartCollect(6) end
                if findItem(2) > 0 then
                    local placeRetry = 0
                    while GetTile(tile.x, tile.y).fg == 0 and placeRetry < 8 and findItem(2) > 0 and botRunning do
                        place(tile.x, tile.y, 2)
                        humanSleep(150, 180)
                        placeRetry = placeRetry + 1
                    end
                end
            end
        end
    end
    if not botRunning then return end
    checkAndDropToStorage()
end

-- =========================================================
-- SESI QUALITY CONTROL (QC SWEEP) & PENAMBALAN TANAH
-- Anti-Disconnect / Anti-Packet Flood: batch segment & targeted pickup
-- =========================================================
function checkAndSweepExcavation()
    currentStatus = "Pemeriksaan Akhir Galian (QC Sweep)..."
    if LogToConsole then
        pcall(LogToConsole, "`2[QC] `wMemulai pemeriksaan QC: Lava, Penambalan Tanah, & Sapu Bersih...")
    end

    -- -------------------------------------------------------------
    -- FASE 1: QC LAVA TERLEWAT (Pindai & bersihkan semua sisa Lava di world)
    -- -------------------------------------------------------------
    currentStatus = "QC: Memeriksa sisa Lava terlewat..."
    for _, tile in pairs(GetTiles()) do
        if not botRunning then break end
        if tile.fg == 4 then
            currentStatus = string.format("QC: Menghancurkan Lava terlewat di (%d, %d)...", tile.x, tile.y)
            local standX, standY = tile.x, tile.y - 1
            local upperT = GetTile(standX, standY)
            if upperT and upperT.fg ~= 0 and upperT.fg ~= 4 then
                if tile.x > 1 and GetTile(tile.x - 1, tile.y).fg == 0 then
                    standX, standY = tile.x - 1, tile.y
                elseif tile.x < 98 and GetTile(tile.x + 1, tile.y).fg == 0 then
                    standX, standY = tile.x + 1, tile.y
                end
            end

            -- Hanya bergerak jika di luar jangkauan (cegah spam teleport)
            local me = GetLocal()
            local curX = me and math.floor(me.posX / 32) or -1
            local curY = me and math.floor(me.posY / 32) or -1
            if math.abs(curX - standX) > 1 or math.abs(curY - standY) > 1 then
                safeFindPath(standX, standY)
            end

            local retry = 0
            while GetTile(tile.x, tile.y).fg == 4 and retry < 15 and botRunning do
                punch(tile.x, tile.y)
                humanSleep(150, 180)
                retry = retry + 1
            end
            smartCollect(4)

            -- Jika lava ini berada di baris tanah farm (baris genap Y = 24..54), langsung tambal dengan tanah!
            if tile.y >= 24 and tile.y <= 54 and (tile.y % 2 == 0) and tile.x >= 2 and tile.x <= 97 and GetTile(tile.x, tile.y).fg == 0 then
                if findItem(2) == 0 then smartCollect(6) end
                if findItem(2) > 0 then
                    local pRetry = 0
                    while GetTile(tile.x, tile.y).fg == 0 and pRetry < 8 and findItem(2) > 0 and botRunning do
                        place(tile.x, tile.y, 2)
                        humanSleep(150, 180)
                        pRetry = pRetry + 1
                    end
                end
            end
        end
    end

    -- -------------------------------------------------------------
    -- FASE 2: QC PENAMBALAN BLOK TANAH (Batch Segment 5-Tile per Titik Berdiri)
    -- Anti-Flood: Bot berdiri 1 kali untuk menjangkau hingga 5 petak di sekitarnya
    -- -------------------------------------------------------------
    currentStatus = "QC: Memeriksa baris tanah yang belum ditambal..."
    local checkRows = {}
    for ry = 24, 54, 2 do
        table.insert(checkRows, ry)
    end

    if not needsDirtFarm() then
        for ry = 4, 22, 2 do
            table.insert(checkRows, ry)
        end
    end

    for _, rowY in ipairs(checkRows) do
        if not botRunning then break end

        -- Cek cepat: Apakah baris ini memiliki petak yang bolong (fg == 0)?
        local hasEmptyTile = false
        for cX = 2, 97 do
            local t = GetTile(cX, rowY)
            if t and t.fg == 0 then
                hasEmptyTile = true
                break
            end
        end

        -- Jika seluruh baris sudah terisi penuh tanah/batu, lewati tanpa bergerak!
        if hasEmptyTile then
            local standY = (rowY == 24) and 23 or (rowY - 1)
            local colX = 2
            while colX <= 97 and botRunning do
                -- Cek apakah di jendela 5 tile (colX s/d colX + 4) ada petak bolong
                local endX = math.min(colX + 4, 97)
                local segmentHasHole = false
                for checkX = colX, endX do
                    local t = GetTile(checkX, rowY)
                    if t and t.fg == 0 then
                        segmentHasHole = true
                        break
                    end
                end

                if segmentHasHole then
                    -- Berdiri di tengah segmen (colX + 2)
                    local standX = math.min(colX + 2, 97)
                    safeFindPath(standX, standY)

                    -- Tambal semua petak yang bolong dalam jangkauan tanpa berpindah posisi
                    for patchX = colX, endX do
                        if not botRunning then break end
                        local t = GetTile(patchX, rowY)
                        if t and t.fg == 0 then
                            if findItem(2) == 0 then
                                smartCollect(6)
                                if findItem(2) == 0 and hasNurseryTrees() then
                                    plantHarvest(standX, standY)
                                end
                            end

                            if findItem(2) > 0 then
                                local pRetry = 0
                                while GetTile(patchX, rowY).fg == 0 and pRetry < 8 and findItem(2) > 0 and botRunning do
                                    place(patchX, rowY, 2)
                                    humanSleep(150, 180)
                                    pRetry = pRetry + 1
                                end
                            end
                        end
                    end
                    humanSleep(60, 90)
                end
                colX = colX + 5 -- Lompat 5 tile ke segmen berikutnya
            end
        end
    end

    -- -------------------------------------------------------------
    -- FASE 3: QC LORONG GANJIL (Bersihkan sisa blok solid / background di lorong pohon)
    -- -------------------------------------------------------------
    currentStatus = "QC: Memeriksa sisa galian di lorong pohon..."
    local function isUnmined(tx, ty)
        -- PROTEKSI MUTLAK: Baris Genap (ty % 2 == 0) adalah BARIS TANAH DIRT FARM! Dilarang disentuh!
        if ty % 2 == 0 then return false end

        local t = GetTile(tx, ty)
        if not t then return false end
        -- Bedrock (8), White Door (6), dan Wooden Platform (102) TIDAK boleh dihancurkan!
        if t.fg == 8 or t.fg == 6 or t.fg == 102 then return false end

        return (t.fg ~= 0 or t.bg ~= 0)
    end

    local pass = 0
    local foundMissed = true
    while foundMissed and pass < 2 and botRunning do
        foundMissed = false
        pass = pass + 1
        for y = 25, 53, 2 do -- STEP 2: HANYA lorong kosong ganjil!
            if not botRunning then break end
            for x = 2, 97 do
                if not botRunning then break end
                if isUnmined(x, y) then
                    foundMissed = true
                    local standX = (x > 2 and GetTile(x - 1, y).fg == 0) and (x - 1) or (x + 1)
                    safeFindPath(standX, y)

                    local retry = 0
                    while isUnmined(x, y) and retry < 30 and botRunning do
                        punch(x, y)
                        humanSleep(170, 210)
                        retry = retry + 1
                    end
                    smartCollect(4)
                end
            end
        end
    end

    -- -------------------------------------------------------------
    -- FASE 4: QC SAPU BERSIH FLOATING ITEMS (Targeted Pickup via ObjectList)
    -- Bebas Disconnect: Tidak ada lagi blind teleport bolak-balik 2 ke 97!
    -- -------------------------------------------------------------
    currentStatus = "QC: Mengumpulkan sisa floating items..."
    local rawObjs = GetObjectList()
    if rawObjs then
        for _, obj in pairs(rawObjs) do
            if not botRunning then break end
            if COLLECT_WHITELIST[obj.itemid] and obj.posY >= (24 * 32) then
                local ox = math.floor(obj.posX / 32)
                local oy = math.floor(obj.posY / 32)
                local targetWalkY = (oy % 2 == 1) and oy or (oy - 1)

                local me = GetLocal()
                local curX = me and math.floor(me.posX / 32) or -1
                local curY = me and math.floor(me.posY / 32) or -1

                -- Hanya gerak jika jarak > 2 petak
                if math.abs(curX - ox) > 2 or curY ~= targetWalkY then
                    safeFindPath(ox, targetWalkY)
                    humanSleep(80, 120)
                end
                smartCollect(4)
            end
        end
    end

    checkAndDropToStorage(true)
    if LogToConsole then
        pcall(LogToConsole, "`2[QC] `wPemeriksaan menyeluruh tuntas! Aman dari disconnect & world bersih.")
    end
end

-- =========================================================
-- KEBUN MANDIRI & PEMBANGUNAN BARIS TANAH
-- =========================================================
function needsDirtFarm()
    for tiley = 24, 4, -4 do
        for x = 2, 97 do
            if GetTile(x, tiley).fg == 0 or GetTile(x, tiley - 2).fg == 0 then
                return true
            end
        end
    end
    return false
end

function hasNurseryTrees()
    local startX, endX, plantY = getNurseryRange()
    for tilex = startX, endX do
        if GetTile(tilex, plantY).fg == 3 then
            return true
        end
    end
    return false
end

function cleanNursery()
    local startX, endX, plantY = getNurseryRange()
    local maxWait = 45 -- Maksimal waktu tunggu pohon matang
    local waitCount = 0

    while hasNurseryTrees() and waitCount < maxWait and botRunning do
        local harvestedAny = false

        for tilex = startX, endX do
            if not botRunning then return end
            local tile = GetTile(tilex, plantY)
            if tile.fg == 3 then
                -- Panen jika pohon sudah matang, atau tebas jika sudah menunggu > 30 detik
                if tile.readyharvest or waitCount >= 30 then
                    harvestedAny = true
                    FindPath(tilex, plantY)
                    sleep(80)

                    local retry = 0
                    while GetTile(tilex, plantY).fg == 3 and retry < 25 and botRunning do
                        punch(tilex, plantY)
                        sleep(190)
                        retry = retry + 1
                    end
                    sleep(60)
                    smartCollect(4)

                    -- JANGAN tanam ulang bibit (biarkan tile kosong)
                    -- Jika Dirt Block di tas sudah penuh (>= 150), buang (trash) agar tas tidak macet
                    if findItem(2) >= 150 then
                        trashItem(2, 100)
                        sleep(100)
                    end
                end
            end
        end

        -- Jika masih ada pohon yang belum matang, tunggu 1 detik lalu periksa lagi
        if hasNurseryTrees() and botRunning then
            sleep(1000)
            waitCount = waitCount + 1
        end
    end

    -- Selesai panen: Buang sisa Dirt Block di tas agar tas bersih & siap untuk restock platform
    if findItem(2) >= 100 then
        trashItem(2, 100)
        sleep(100)
    end
    if findItem(2) > 0 then
        trashItem(2, findItem(2))
        sleep(100)
    end
end

function plantFirst()
    -- Jika baris farm sudah selesai terisi tanah, jangan tanam lagi!
    if not botRunning or not needsDirtFarm() then return end

    local startX, endX, plantY = getNurseryRange()
    FindPath(startX, plantY)
    Sleep(500)
    for tilex = startX, endX, 1 do
        if not botRunning then return end
        if GetTile(tilex, plantY).fg == 0 then
            FindPath(tilex, plantY)
            Sleep(100)
            local retry = 0
            while GetTile(tilex, plantY).fg == 0 and retry < 25 and botRunning do
                place(tilex, plantY, 3)
                sleep(190)
                retry = retry + 1
            end
        end
    end

    -- Tunggu bibit tumbuh (maksimal 25 detik, selesai lebih cepat jika sudah matang)
    local waitCount = 0
    while waitCount < 25 and botRunning do
        local allReady = true
        for tilex = startX, endX do
            local t = GetTile(tilex, plantY)
            if t.fg == 3 and not t.readyharvest then
                allReady = false
                break
            end
        end
        if allReady then break end
        Sleep(1000)
        waitCount = waitCount + 1
    end
end

function checkEmpty(x, y)
    for i = 1, 5 do
        local tx = (x - 3) + i
        if tx >= 2 and tx <= 97 then
            if GetTile(tx, y).fg == 0 then
                return true
            end
        end
    end
    return false
end

function plantHarvest(x, y)
    local startX, endX, plantY = getNurseryRange()
    while findItem(2) == 0 and botRunning do
        local harvestedAny = false
        for tilex = startX, endX, 1 do
            if not botRunning then break end
            if GetTile(tilex, plantY).readyharvest then
                harvestedAny = true
                FindPath(tilex, plantY)
                sleep(100)
                local retry = 0
                while GetTile(tilex, plantY).fg == 3 and retry < 25 and botRunning do
                    punch(tilex, plantY)
                    sleep(190)
                    retry = retry + 1
                end
                sleep(60)
                smartCollect(4)
                retry = 0
                while GetTile(tilex, plantY).fg == 0 and retry < 25 and botRunning do
                    place(tilex, plantY, 3)
                    sleep(190)
                    retry = retry + 1
                end
            end
            if findItem(2) > 180 then
                break
            end
        end
        if findItem(2) == 0 and not harvestedAny and botRunning then
            sleep(2000)
        end
    end

    if not botRunning then return end
    local pathRetry = 0
    while (math.floor(GetLocal().posX / 32) ~= x or math.floor(GetLocal().posY / 32) ~= y) and pathRetry < 30 and botRunning do
        FindPath(x, y)
        sleep(600)
        pathRetry = pathRetry + 1
    end
end

function placeDirt()
    isBuildingDF = true
    -- Titik langkah maju (kiri ke kanan): menutup rapi sampai X = 97
    local forwardPoints = {4, 9, 14, 19, 24, 29, 34, 39, 44, 49, 54, 59, 64, 69, 74, 79, 84, 89, 94, 95}
    -- Titik langkah mundur (kanan ke kiri): menutup rapi sampai X = 2
    local backwardPoints = {95, 90, 85, 80, 75, 70, 65, 60, 55, 50, 45, 40, 35, 30, 25, 20, 15, 10, 5, 4}

    local function fillRow(targetY, standY, points)
        for _, tilex in ipairs(points) do
            if not botRunning then return end
            if checkEmpty(tilex, targetY) then
                -- Pastikan persediaan tanah cukup sebelum mulai menaruh 5 blok
                if findItem(2) < 5 then
                    plantHarvest(tilex, standY)
                    sleep(100)
                end

                FindPath(tilex, standY)
                Sleep(80)

                for i = 1, 5 do
                    if not botRunning then return end
                    local targetX = (tilex - 3) + i
                    if targetX >= 2 and targetX <= 97 then
                        if findItem(2) == 0 then
                            plantHarvest(tilex, standY)
                            sleep(100)
                        end
                        if not botRunning then return end
                        if GetTile(targetX, targetY).fg == 0 then
                            local retry = 0
                            while GetTile(targetX, targetY).fg == 0 and retry < 25 and botRunning do
                                place(targetX, targetY, 2)
                                sleep(150)
                                retry = retry + 1
                            end
                        end
                    end
                end
            end
        end
    end

    for tiley = 24, 4, -4 do
        if not botRunning then break end
        -- Arah maju: dari kiri ke kanan (baris tiley)
        fillRow(tiley, tiley + 1, forwardPoints)

        if not botRunning then break end
        -- Arah mundur: dari kanan ke kiri (baris tiley - 2)
        fillRow(tiley - 2, tiley - 1, backwardPoints)
    end

    -- Quality Control Sweep: Pastikan 100% tidak ada satu pun balok tanah yang tertinggal/bolong
    for tiley = 24, 4, -4 do
        if not botRunning then break end
        for _, rY in ipairs({tiley, tiley - 2}) do
            for cX = 2, 97 do
                if not botRunning then break end
                if GetTile(cX, rY).fg == 0 then
                    local sY = (rY == 24) and 25 or (rY - 1)
                    if findItem(2) == 0 then
                        plantHarvest(cX, sY)
                    end
                    FindPath(cX, sY)
                    sleep(80)
                    local qcRetry = 0
                    while GetTile(cX, rY).fg == 0 and qcRetry < 20 and botRunning do
                        place(cX, rY, 2)
                        sleep(150)
                        qcRetry = qcRetry + 1
                    end
                end
            end
        end
    end

    isBuildingDF = false
end

-- =========================================================
-- PELETAKAN WOODEN PLATFORM DI X = 1 DAN X = 98 (ATAS & BAWAH)
-- =========================================================
function placePlatformColumn(colX, startY, endY)
    -- Pastikan bot tiba di titik awal (colX, 3) di langit terbuka
    local navRetry = 0
    while (math.floor(GetLocal().posX / 32) ~= colX or math.floor(GetLocal().posY / 32) ~= 3) and navRetry < 30 and botRunning do
        FindPath(colX, 3)
        sleep(180)
        navRetry = navRetry + 1
    end

    -- Taruh platform paling atas di Y = 2 (ke atas kepala bot)
    if GetTile(colX, 2).fg ~= 102 and GetTile(colX, 2).fg ~= 8 then
        if findItem(102) == 0 then
            restockPlatform()
        end
        local pRetry = 0
        while GetTile(colX, 2).fg == 0 and pRetry < 20 and botRunning do
            place(colX, 2, 102)
            sleep(190)
            pRetry = pRetry + 1
        end
    end

    -- Pindah posisi ke platform Y = 2
    FindPath(colX, 2)
    sleep(100)

    -- Alur Turun Terus-Menerus: Dari Y = 3 sampai Y = endY (54)
    -- Bot berdiri di y - 1, memukul y di bawahnya sampai hancur/bersih, lalu menaruh platform jika baris genap, baru melangkah ke y!
    for y = 3, endY do
        if not botRunning then return end

        -- Jika bertemu Bedrock dasar world (ID 8), selesai!
        if GetTile(colX, y).fg == 8 then
            break
        end

        -- 1. Hancurkan balok penghalang di bawah (colX, y) dari posisi kita di atasnya (colX, y - 1)
        if GetTile(colX, y).fg ~= 0 and GetTile(colX, y).fg ~= 102 and GetTile(colX, y).fg ~= 8 then
            local punchRetry = 0
            while GetTile(colX, y).fg ~= 0 and GetTile(colX, y).fg ~= 102 and GetTile(colX, y).fg ~= 8 and punchRetry < 25 and botRunning do
                punch(colX, y)
                sleep(190)
                punchRetry = punchRetry + 1
            end
            sleep(50)
            smartCollect(4)
        end

        -- 2. Jika baris GENAP (y % 2 == 0): Ini sejajar dengan baris tanah, pasang Wooden Platform (ID 102)!
        if y % 2 == 0 then
            if GetTile(colX, y).fg ~= 102 and GetTile(colX, y).fg ~= 8 then
                if findItem(102) == 0 then
                    local success = restockPlatform()
                    if not success or findItem(102) == 0 or not botRunning then
                        break
                    end
                    -- Kembali ke posisi y - 1 setelah restock
                    local rNav = 0
                    while (math.floor(GetLocal().posX / 32) ~= colX or math.floor(GetLocal().posY / 32) ~= (y - 1)) and rNav < 30 and botRunning do
                        FindPath(colX, y - 1)
                        sleep(200)
                        rNav = rNav + 1
                    end
                end

                local placeRetry = 0
                while GetTile(colX, y).fg == 0 and placeRetry < 20 and botRunning do
                    place(colX, y, 102)
                    sleep(190)
                    placeRetry = placeRetry + 1
                end
            end
        else
            -- Baris GANJIL (y % 2 == 1): Ini adalah lorong udara (jeda 1)
            -- Jika ada sisa platform nyasar di baris ganjil, hancurkan agar lorong plong
            if GetTile(colX, y).fg == 102 then
                local pRetry = 0
                while GetTile(colX, y).fg == 102 and pRetry < 25 and botRunning do
                    punch(colX, y)
                    sleep(190)
                    pRetry = pRetry + 1
                end
                sleep(50)
                smartCollect(4)
            end
        end

        -- 3. Turun 1 langkah ke tile (colX, y) yang sekarang sudah plong / sudah ada platform
        FindPath(colX, y)
        sleep(80)
    end
end

function placeSidePlatforms()
    setModFly(true)
    setAntiBounce(true)
    sleep(100)

    -- Pastikan stok Wooden Platform cukup sebelum mulai (dibutuhkan ~52 platform untuk kiri & kanan)
    if findItem(102) < 55 then
        currentStatus = "Restock Wooden Platform..."
        restockPlatform()
        sleep(200)
    end

    currentStatus = "Memasang Platform Sisi Kiri (X = 1)..."
    placePlatformColumn(1, 2, 54)
    sleep(200)

    currentStatus = "Memasang Platform Sisi Kanan (X = 98)..."
    placePlatformColumn(98, 2, 54)
    sleep(200)
end

-- =========================================================
-- CONTROLLER & EKSEKUSI BOT
-- =========================================================
function mainBotLoop()
    if not botRunning then return end

    -- Rekam nama world utama sebelum memulai aktivitas
    getMainWorldName()

    -- 1. Aktifkan ModFly & AntiBounce
    currentStatus = "Mengaktifkan ModFly & AntiBounce"
    setModFly(true)
    setAntiBounce(true)
    sleep(200)

    -- 2. Bersihkan sisi border world
    if not botRunning then return end
    currentStatus = "Membersihkan Border World (clearSide)"
    clearSide()
    sleep(200)

    -- 3. Gali lorong bawah tanah (auto-drop ke PLATSTORES jika ada item mencapai 200)
    if not botRunning then return end
    currentStatus = "Menggali Lorong Bawah (clearDirt)"
    clearDirt()
    sleep(200)

    -- 4. Bersihkan lava dan tambal dengan tanah
    if not botRunning then return end
    currentStatus = "Membersihkan Lava (breakLava)"
    breakLava()
    sleep(200)

    -- 4b. SESI CHECKING & SWEEP QC: Pastikan 100% galian tuntas & tidak ada floating item tertinggal
    if not botRunning then return end
    currentStatus = "Pemeriksaan Akhir Galian & Sapu Bersih (QC Sweep)"
    checkAndSweepExcavation()
    sleep(200)

    -- 5 & 6. Pembangunan Baris Farm & Kebun Bibit (HANYA jika baris farm belum selesai)
    if not botRunning then return end
    if needsDirtFarm() then
        currentStatus = "Siapkan Kebun Bibit (plantFirst)"
        plantFirst()
        sleep(200)

        if not botRunning then return end
        currentStatus = "Membangun Baris Farm (placeDirt)"
        placeDirt()
        sleep(200)
    end

    -- 6b. Bersihkan sisa pohon di kebun bibit (panen tuntas & auto-trash jika dirt penuh)
    if not botRunning then return end
    if hasNurseryTrees() then
        currentStatus = "Membersihkan Sisa Pohon Kebun (cleanNursery)"
        cleanNursery()
        sleep(200)
    end

    -- 7. Pasang tangga Wooden Platform di X = 1 dan X = 98
    if not botRunning then return end
    currentStatus = "Memasang Tangga Platform (placeSidePlatforms)"
    placeSidePlatforms()
    sleep(200)

    -- 8. Setor akhir: Drop semua sisa hasil galian ke door masing-masing di PLATSTORES
    if not botRunning then return end
    currentStatus = "Setor Akhir ke PLATSTORES"
    checkAndDropToStorage(true)

    botRunning = false
    currentStatus = "Selesai (Completed!)"
    showMenuDialog()
end

-- Mode Khusus: Jalankan Sesi Platform Saja (Skip Farm)
function platformOnlyLoop()
    if not botRunning then return end
    getMainWorldName()

    currentStatus = "Mengaktifkan ModFly & AntiBounce"
    setModFly(true)
    setAntiBounce(true)
    sleep(200)

    -- Bersihkan sisa pohon jika ada dari sesi sebelumnya
    if hasNurseryTrees() then
        currentStatus = "Membersihkan Sisa Pohon Kebun (cleanNursery)"
        cleanNursery()
        sleep(200)
    end

    -- Pasang tangga Wooden Platform di X = 1 dan X = 98
    if not botRunning then return end
    currentStatus = "Memasang Tangga Platform (placeSidePlatforms)"
    placeSidePlatforms()
    sleep(200)

    -- Setor akhir ke PLATSTORES
    if not botRunning then return end
    currentStatus = "Setor Akhir ke PLATSTORES"
    checkAndDropToStorage(true)

    botRunning = false
    currentStatus = "Selesai Pasang Platform (Completed!)"
    showMenuDialog()
end

-- Mode Khusus: Hanya Bersihkan Sisa Pohon di Kebun
function cleanNurseryOnlyLoop()
    if not botRunning then return end
    getMainWorldName()
    setModFly(true)
    setAntiBounce(true)
    sleep(200)

    currentStatus = "Membersihkan Sisa Pohon Kebun..."
    cleanNursery()

    botRunning = false
    currentStatus = "Selesai Bersihkan Pohon!"
    showMenuDialog()
end

-- Mode Khusus: Hanya Jalankan QC & Sapu Bersih World
function qcOnlyLoop()
    if not botRunning then return end
    getMainWorldName()
    setModFly(true)
    setAntiBounce(true)
    sleep(200)

    currentStatus = "Memulai Sesi QC Galian & Sapu Bersih..."
    checkAndSweepExcavation()

    botRunning = false
    currentStatus = "QC & Sapu Bersih Selesai!"
    showMenuDialog()
end

-- =========================================================
-- MENU GUI (NATIVE IN-GAME DIALOG) - 100% CRASH-PROOF
-- =========================================================
function showMenuDialog()
    local statusText = botRunning and "`2[RUNNING] `w" .. currentStatus or "`4[STOPPED] `wIdle"
    local lines = {}
    table.insert(lines, "set_default_color|`o")
    table.insert(lines, "add_label_with_icon|big|`2Auto DF no Platform|left|2|")
    table.insert(lines, "add_spacer|small|")
    table.insert(lines, "add_textbox|`oStatus: " .. statusText .. "|left|")
    table.insert(lines, "add_textbox|`7Ketik `w/df `7atau `w/menu `7di chat untuk membuka menu ini lagi.|left|")
    table.insert(lines, "add_spacer|small|")

    if botRunning then
        table.insert(lines, "add_button|btn_stop|`4[ STOP BOT ]|noflags|0|0|")
    else
        table.insert(lines, "add_button|btn_start|`2[ START BOT (Full Auto) ]|noflags|0|0|")
        table.insert(lines, "add_button|btn_plat_only|`3[ HANYA PASANG PLATFORM ]|noflags|0|0|")
        table.insert(lines, "add_button|btn_clean_nursery|`e[ BERSIHKAN SISA POHON ]|noflags|0|0|")
        table.insert(lines, "add_button|btn_qc_only|`6[ QC & SAPU BERSIH WORLD ]|noflags|0|0|")
    end

    table.insert(lines, "add_button|btn_refresh|`9Refresh Status|noflags|0|0|")
    table.insert(lines, "add_quick_exit|")
    table.insert(lines, "end_dialog|df_menu|Tutup||")

    local dialog = table.concat(lines, "\n")

    local sendVar = sendVariant or SendVariant
    if sendVar then
        pcall(sendVar, {v1 = "OnDialogRequest", v2 = dialog})
    end
end

-- Hook dialog & pesan masuk dari game
function hookVariant(variant)
    if not variant then return false end

    -- Anti-Ban: Deteksi pesan sistem / warning error server
    if variant.v1 == "OnConsoleMessage" or variant.v1 == "OnDialogRequest" then
        local text = variant.v2 or ""
        if text:find("temporarily banned") or text:find("Server Overloaded") or text:find("Too many people") or text:find("Suspicious") or text:find("shadow ban") then
            if LogToConsole then
                pcall(LogToConsole, "`4[Anti-Ban Alert] `wTerdeteksi sinyal peringatan server: " .. text:sub(1, 50))
                pcall(LogToConsole, "`4[Anti-Ban Alert] `wBot otomatis dijeda untuk melindungi akun & IP Anda!")
            end
            botRunning = false
            currentStatus = "Dijeda Otomatis (Server Warning Detected)"
            return false
        end
    end

    if variant.v1 == "OnDialogRequest" then
        if variant.v2 and variant.v2:find("df_menu") then
            return false -- Izinkan dialog menu kita ditampilkan
        end
        return true -- Blokir dialog lain agar tidak mengganggu bot
    end
    return false
end

-- Hook paket string keluar untuk menangkap klik tombol menu & chat /df serta blokir collect di gudang
function hookSendPacket(type, pkt)
    -- Blokir segala paket collect saat di gudang (kecuali saat restock platform)
    if (isTransferring or isInStorageWorld()) and not isRestockingPlatform then
        if type == 11 or (pkt and (pkt:find("action|collect") or pkt:find("item_collect"))) then
            return true
        end
    end

    if not pkt then return false end

    -- Deteksi command chat /df atau /menu
    if pkt:find("/df") or pkt:find("/menu") then
        showMenuDialog()
        return true -- Blokir chat agar tidak terkirim ke publik
    end

    -- Menangkap interaksi tombol dari dialog menu
    if pkt:find("dialog_name|df_menu") then
        local threadFunc = runThread or RunThread
        local function startTask(fn)
            if threadFunc then
                threadFunc(fn)
            else
                local co = coroutine.create(fn)
                coroutine.resume(co)
            end
        end

        if pkt:find("buttonClicked|btn_start") then
            if not botRunning then
                botRunning = true
                currentStatus = "Memulai bot (Full Auto)..."
                startTask(mainBotLoop)
            end
            showMenuDialog()
            return true
        elseif pkt:find("buttonClicked|btn_plat_only") then
            if not botRunning then
                botRunning = true
                currentStatus = "Memulai Sesi Platform Saja..."
                startTask(platformOnlyLoop)
            end
            showMenuDialog()
            return true
        elseif pkt:find("buttonClicked|btn_clean_nursery") then
            if not botRunning then
                botRunning = true
                currentStatus = "Membersihkan Sisa Pohon..."
                startTask(cleanNurseryOnlyLoop)
            end
            showMenuDialog()
            return true
        elseif pkt:find("buttonClicked|btn_qc_only") then
            if not botRunning then
                botRunning = true
                currentStatus = "Memulai QC & Sapu Bersih World..."
                startTask(qcOnlyLoop)
            end
            showMenuDialog()
            return true
        elseif pkt:find("buttonClicked|btn_stop") then
            botRunning = false
            isTransferring = false
            currentStatus = "Bot Dihentikan (Stopped)"
            showMenuDialog()
            return true
        elseif pkt:find("buttonClicked|btn_refresh") then
            showMenuDialog()
            return true
        end
    end

    return false
end

-- Hook paket raw keluar: Memblokir pengiriman paket collect (Type 11) di world storage
function hookSendPacketRaw(packet)
    if not packet then return false end
    if (isTransferring or isInStorageWorld()) and not isRestockingPlatform then
        if packet.type == 11 then
            return true -- Blokir pengiriman paket collect raw ke server
        end
    end
    return false
end

-- =========================================================
-- DAFTARKAN HOOK EVENT (Mendukung kedua urutan parameter launcher)
-- =========================================================
if AddHook then
    pcall(AddHook, hookVariant, "OnVariant")
    pcall(AddHook, "OnVariant", hookVariant)
    pcall(AddHook, hookSendPacket, "OnSendPacket")
    pcall(AddHook, "OnSendPacket", hookSendPacket)
    pcall(AddHook, hookSendPacketRaw, "OnSendPacketRaw")
    pcall(AddHook, "OnSendPacketRaw", hookSendPacketRaw)
end

-- Tampilkan notifikasi di console dan buka dialog menu
if LogToConsole then
    pcall(LogToConsole, "`2[Auto DF] `wScript berhasil dimuat! Ketik `2/df `wuntuk membuka menu.")
end

showMenuDialog()