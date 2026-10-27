-- =========================================================
-- AUTO HARVEST DIRT FARM (FULL AUTOMATIC) - OPTIMIZED
-- Fitur: Auto Harvest, Smart Collect (No Gems), Auto Drop ke Storage
-- Optimasi: Row Skipping, O(1) Storage Cache, Anti-Packet Flood, Proximity Check
-- =========================================================

-- Compatibility layer: memastikan kompatibilitas antar versi GrowLauncher
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
-- KONFIGURASI DEFAULT & KONTROL BOT
-- =========================================================
local botRunning = false
local currentStatus = "Idle (Buka /harvest untuk setting)"

-- Pengaturan Gudang (Dapat diubah lewat Dialog Menu In-Game)
local STORAGE_WORLD = "MYSTORAGE"    -- Nama world gudang tujuan drop
local STORAGE_DOOR  = ""             -- Door ID gudang (kosongkan jika White Door)
local DROP_LIMIT    = 190            -- Batas isi tas sebelum berangkat drop (default 190)

-- Pengaturan World Utama
local currentMainWorld = nil
local MAIN_WORLD_DOOR = ""

-- Pointer posisi drop terakhir di gudang (dimulai dari ujung kanan X = 98)
local lastDropBlockX = 98
local lastDropSeedX  = 98

-- Counter Statistik
local totalHarvested = 0
local totalBlockDropped = 0
local totalSeedDropped = 0

-- Target Item IDs (Pohon, Block, Seed) - 0 = Auto-Detect
local targetTreeID  = 0
local targetBlockID = 0
local targetSeedID  = 0

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

-- State transfer
local isTransferring = false

-- =========================================================
-- FUNGSI MODFLY & ANTIBOUNCE
-- =========================================================
function setModFly(enable)
    local names = {"ModFly", "Mod Fly", "Fly", "[C] ModFly"}
    if editToggle then
        for _, n in ipairs(names) do pcall(editToggle, n, enable) end
    end
    if setValue then
        for _, n in ipairs(names) do pcall(setValue, n, enable) end
    end
end

function setAntiBounce(enable)
    local names = {"Antibounce", "AntiBounce", "Anti Bounce", "[C] Antibounce"}
    if editToggle then
        for _, n in ipairs(names) do pcall(editToggle, n, enable) end
    end
    if setValue then
        for _, n in ipairs(names) do pcall(setValue, n, enable) end
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
    if isTransferring then return true end
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
-- FUNGSI DASAR JARINGAN & GAMEPLAY
-- =========================================================
function punch(x, y)
    local me = GetLocal()
    local packet = {}
    packet.type = 3
    packet.state = 2592
    packet.value = 18
    packet.px = x
    packet.py = y
    packet.x = me and me.posX or (x * 32)
    packet.y = me and me.posY or (y * 32)
    SendPacketRaw(false, packet)
end

function collectRaw(object)
    -- PROTEKSI KETAT: Dilarang collect jika di world storage atau saat transfer!
    if isTransferring or isInStorageWorld() then return end

    local packet = {}
    packet.type = 11
    packet.value = object.id
    packet.x = object.posX
    packet.y = object.posY
    SendPacketRaw(false, packet)
end

function findItem(itemID)
    if not itemID or itemID == 0 then return 0 end
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
        amount = math.min(amount, 200) -- Maksimal 200 per drop
        SendPacket(2, "action|drop\nitemID|" .. id)
        humanSleep(400, 550)
        SendPacket(2, "action|dialog_return\ndialog_name|drop_item\nitemID|" .. id .. "|\ncount|" .. amount)
        humanSleep(400, 550)
    end
end

function getMainWorldName()
    if currentMainWorld and currentMainWorld ~= "" then
        return currentMainWorld
    end
    local name = (GetWorldName and GetWorldName()) or 
                 (getWorldName and getWorldName()) or 
                 (getCurrentWorldName and getCurrentWorldName()) or
                 (GetWorld and GetWorld() and GetWorld().name) or
                 (getWorld and getWorld() and getWorld().name)
    if name and name ~= "" and name:upper() ~= STORAGE_WORLD:upper() then
        currentMainWorld = name:upper()
        return currentMainWorld
    end
    return currentMainWorld or ""
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
-- DETEKSI POHON & ANALISIS WORLD
-- =========================================================
function detectFarmableTree()
    if targetTreeID and targetTreeID > 0 then
        targetSeedID  = targetTreeID
        targetBlockID = targetTreeID - 1
        return true
    end

    for _, tile in pairs(GetTiles()) do
        -- Di Growtopia, bibit pohon selalu ID ganjil (tree/seed) dan memiliki properti readyharvest
        if tile.readyharvest and tile.fg and tile.fg % 2 == 1 and tile.fg > 1 then
            targetTreeID  = tile.fg
            targetSeedID  = tile.fg      -- Di Growtopia, ID Seed = ID Pohon
            targetBlockID = tile.fg - 1  -- Di Growtopia, ID Balok = ID Pohon - 1
            if LogToConsole then
                pcall(LogToConsole, "`2[Harvest] `wTerdeteksi Pohon ID: `2" .. targetTreeID .. 
                      " `w(Block ID: `2" .. targetBlockID .. "`w, Seed ID: `2" .. targetSeedID .. "`w)")
            end
            return true
        end
    end
    return false
end

-- Hitung total pohon matang yang tersisa di world
function countMatureTrees()
    if not targetTreeID or targetTreeID == 0 then return 0 end
    local count = 0
    for _, tile in pairs(GetTiles()) do
        if tile.fg == targetTreeID and tile.readyharvest then
            count = count + 1
        end
    end
    return count
end

-- Optimasi Kecepatan: Cek apakah suatu baris Y memiliki pohon matang
function rowHasMatureTrees(rowY)
    if not targetTreeID or targetTreeID == 0 then return false end
    for x = 2, 97 do
        local t = GetTile(x, rowY)
        if t and t.fg == targetTreeID and t.readyharvest then
            return true
        end
    end
    return false
end

-- =========================================================
-- SMART COLLECT (HANYA BLOCK & SEED, GEMS DIABAIKAN)
-- =========================================================
function collectHarvestDrops(range)
    range = range or 4
    if isTransferring or isInStorageWorld() then return end

    local me = GetLocal()
    if not me then return end
    local myX = me.posX
    local myY = me.posY

    local rawObjs = GetObjectList()
    if not rawObjs then return end

    for _, obj in pairs(rawObjs) do
        -- KHUSUS: Hanya ambil Block dan Seed target!
        -- GEMS (Item ID 112) TIDAK AKAN PERNAH DI-COLLECT!
        if obj.itemid == targetBlockID or obj.itemid == targetSeedID then
            if math.abs(myX - obj.posX) <= (32 * range) and math.abs(myY - obj.posY) <= (32 * range) then
                if findItem(obj.itemid) < 200 then
                    collectRaw(obj)
                    sleep(20)
                end
            end
        end
    end
end

-- =========================================================
-- SISTEM DROP CERDAS DI WORLD STORAGE (DARI KANAN KE KIRI)
-- Auto-Shift jika Penuh/Terhalang & Verifikasi Sukses Drop
-- =========================================================

-- Hitung akurat total floating items pada koordinat (tileX, tileY)
local function getFloatingCountAt(tileX, tileY)
    local total = 0
    local rawObjs = GetObjectList()
    if rawObjs then
        for _, obj in pairs(rawObjs) do
            local ox = math.floor((obj.posX or obj.x or 0) / 32)
            local oy = math.floor((obj.posY or obj.y or 0) / 32)
            if ox == tileX and oy == tileY then
                local count = obj.count or obj.amount or 1
                total = total + count
            end
        end
    end
    return total
end

-- Helper pencari petak kosong berikutnya dari kanan ke kiri
local function findNextDropLocation(currentX, currentY, isSeed)
    local curX = currentX or 98
    local curY = currentY

    while botRunning do
        while curX >= 1 and botRunning do
            local tile = GetTile(curX, curY)
            -- Cek apakah terhalang blok solid (hanya boleh udara kosong fg==0 atau platform fg==102)
            local isBlocked = tile and (tile.fg ~= 0 and tile.fg ~= 102)
            if not isBlocked then
                local floatingCount = getFloatingCountAt(curX, curY)
                if floatingCount < 3800 then
                    return curX, curY
                end
            end
            -- Jika ada blok atau sudah penuh (>= 3800), geser 1 tile ke kiri!
            curX = curX - 1
        end

        -- Jika satu baris sudah penuh sampai X = 1, pindah baris
        curX = 98
        if isSeed then
            -- Untuk Seed: naik 2 baris ke atas
            curY = curY - 2
            if curY < 2 then
                if LogToConsole then
                    pcall(LogToConsole, "`4[Storage Penuh] `wPeringatan: Seluruh baris seed gudang sudah penuh!")
                end
                return 98, 2
            end
        else
            -- Untuk Block: turun 2 baris ke bawah
            curY = curY + 2
            if curY > 54 then
                if LogToConsole then
                    pcall(LogToConsole, "`4[Storage Penuh] `wPeringatan: Seluruh lantai block gudang sudah penuh!")
                end
                return 98, 54
            end
        end
    end
    return curX, curY
end

function dropAllToStorage(forceAll)
    local blockCount = findItem(targetBlockID)
    local seedCount  = findItem(targetSeedID)

    -- Cek apakah memenuhi syarat drop
    if not forceAll then
        if blockCount < DROP_LIMIT and seedCount < DROP_LIMIT then
            return
        end
    else
        -- Jika forceAll (misal saat tree habis), cukup ada sisa (> 0) sudah harus drop semua
        if blockCount == 0 and seedCount == 0 then
            return
        end
    end

    local mainWorld = getMainWorldName()
    if not mainWorld or mainWorld == "" then return end

    isTransferring = true
    setAutoCollect(false) -- MATIKAN auto collect client sebelum melangkah ke gudang

    local me = GetLocal()
    local savedX = me and math.floor(me.posX / 32) or 50
    local savedY = me and math.floor(me.posY / 32) or 23

    currentStatus = forceAll and "Menyetor SEMUA sisa hasil panen ke " .. STORAGE_WORLD .. "..."
                            or "Menyetor hasil panen ke " .. STORAGE_WORLD .. "..."
    if LogToConsole then
        local msg = forceAll and string.format("`2[Storage] `wTree habis! Menyetor sisa tas (%d Block, %d Seed) ke %s...", blockCount, seedCount, STORAGE_WORLD)
                             or string.format("`2[Storage] `wKapasitas tas tercapai (%d Block, %d Seed). Menuju %s...", blockCount, seedCount, STORAGE_WORLD)
        pcall(LogToConsole, msg)
    end

    -- Masuk ke World Gudang Penyimpanan
    join(STORAGE_WORLD, STORAGE_DOOR ~= "" and STORAGE_DOOR or nil)

    setModFly(true)
    setAntiBounce(true)
    setAutoCollect(false) -- Pastikan auto collect TETAP MATI selama di world storage
    humanSleep(200, 300)

    -- Deteksi baris lantai drop di Storage (cari White Door)
    local whiteDoorY = 23
    for _, tile in pairs(GetTiles()) do
        if tile.fg == 6 then -- White Door
            whiteDoorY = tile.y
            break
        end
    end

    -- Block Drop sejajar tepat dengan White Door (Y = whiteDoorY)
    local blockDropY = whiteDoorY

    -- Seed Drop melayang tepat 2 blok di atas White Door (Y = whiteDoorY - 2)
    local seedDropY = math.max(2, whiteDoorY - 2)

    -- 1. DROP BLOCK (SEJAJAR White Door, Auto-Shift ke kiri jika penuh/terhalang)
    local shouldDropBlock = forceAll and (findItem(targetBlockID) > 0) or (findItem(targetBlockID) >= DROP_LIMIT)
    if shouldDropBlock then
        currentStatus = "Menyetor Block ke storage..."
        local dropTries = 0

        while findItem(targetBlockID) > 0 and dropTries < 40 and botRunning do
            local targetX, targetY = findNextDropLocation(lastDropBlockX, blockDropY, false)
            lastDropBlockX = targetX

            -- Berdiri tepat di targetY (sejajar White Door)
            FindPath(targetX, targetY)
            humanSleep(200, 300)

            local p = GetLocal()
            if p then
                SendPacketRaw(false, {type = 0, x = p.posX, y = p.posY, state = 0})
                humanSleep(100, 150)
            end

            local beforeCount = findItem(targetBlockID)
            local toDrop = math.min(beforeCount, 200)
            dropItem(targetBlockID, toDrop)
            humanSleep(350, 450)

            local afterCount = findItem(targetBlockID)
            if afterCount < beforeCount then
                -- Drop BERHASIL
                local dropped = beforeCount - afterCount
                totalBlockDropped = totalBlockDropped + dropped
                -- Jika petak ini sekarang penuh (>= 3800), geser 1 tile ke kiri untuk drop selanjutnya
                if getFloatingCountAt(targetX, targetY) >= 3800 then
                    lastDropBlockX = math.max(1, targetX - 1)
                end
            else
                -- Drop GAGAL (Tile penuh / terhalang)! Geser 1 tile ke kiri dan ulangi drop
                if LogToConsole then
                    pcall(LogToConsole, string.format("`6[Storage] `wTile Block (%d, %d) penuh/terhalang, menggeser 1 tile ke kiri...", targetX, targetY))
                end
                lastDropBlockX = math.max(1, targetX - 1)
                dropTries = dropTries + 1
            end
        end
    end

    -- 2. DROP SEED (MELAYANG 2 BLOK DI ATAS White Door, Auto-Shift ke kiri jika penuh)
    local shouldDropSeed = forceAll and (findItem(targetSeedID) > 0) or (findItem(targetSeedID) >= DROP_LIMIT)
    if shouldDropSeed then
        currentStatus = "Menyetor Seed ke storage..."
        local dropTries = 0

        while findItem(targetSeedID) > 0 and dropTries < 40 and botRunning do
            local targetX, targetY = findNextDropLocation(lastDropSeedX, seedDropY, true)
            lastDropSeedX = targetX

            -- Melayang tepat di targetY (2 blok di atas White Door)
            FindPath(targetX, targetY)
            humanSleep(200, 300)

            local p = GetLocal()
            if p then
                SendPacketRaw(false, {type = 0, x = p.posX, y = p.posY, state = 0})
                humanSleep(100, 150)
            end

            local beforeCount = findItem(targetSeedID)
            local toDrop = math.min(beforeCount, 200)
            dropItem(targetSeedID, toDrop)
            humanSleep(350, 450)

            local afterCount = findItem(targetSeedID)
            if afterCount < beforeCount then
                -- Drop BERHASIL
                local dropped = beforeCount - afterCount
                totalSeedDropped = totalSeedDropped + dropped
                -- Jika petak ini sekarang penuh (>= 3800), geser 1 tile ke kiri untuk drop selanjutnya
                if getFloatingCountAt(targetX, targetY) >= 3800 then
                    lastDropSeedX = math.max(1, targetX - 1)
                end
            else
                -- Drop GAGAL (Tile penuh / terhalang)! Geser 1 tile ke kiri dan ulangi drop
                if LogToConsole then
                    pcall(LogToConsole, string.format("`6[Storage] `wTile Seed (%d, %d) penuh/terhalang, menggeser 1 tile ke kiri...", targetX, targetY))
                end
                lastDropSeedX = math.max(1, targetX - 1)
                dropTries = dropTries + 1
            end
        end
    end

    -- Selesai Drop: Pulang kembali ke world Dirt Farm
    currentStatus = "Kembali ke world farm..."
    join(mainWorld, MAIN_WORLD_DOOR ~= "" and MAIN_WORLD_DOOR or nil)

    setModFly(true)
    setAntiBounce(true)
    humanSleep(200, 300)

    -- Kembali ke titik kerja terakhir saat panen (hanya jika masih ada sisa pohon untuk dipanen)
    if not forceAll then
        local pathRetry = 0
        while (math.floor(GetLocal().posX / 32) ~= savedX or math.floor(GetLocal().posY / 32) ~= savedY) and pathRetry < 25 and botRunning do
            FindPath(savedX, savedY)
            sleep(250)
            pathRetry = pathRetry + 1
        end
    end

    isTransferring = false
    setAutoCollect(true) -- AKTIFKAN KEMBALI auto collect hanya setelah aman tiba di world farm
end

-- =========================================================
-- ALUR UTAMA HARVEST UNIVERSAL (LACAK SEMUA POHON MATANG DI WORLD)
-- Dimulai dari Kiri Atas, Zigzag Otomatis (Tanpa Batasan Layout/Alas)
-- =========================================================
function harvestTreeAt(x, y)
    if not botRunning then return end

    local tile = GetTile(x, y)
    if not tile or tile.fg ~= targetTreeID or not tile.readyharvest then
        return
    end

    local me = GetLocal()
    local curX = me and math.floor(me.posX / 32) or -1
    local curY = me and math.floor(me.posY / 32) or -1

    -- Cek Proximity: Hanya panggil FindPath jika belum berada di titik pohon
    if curX ~= x or curY ~= y then
        FindPath(x, y)
        humanSleep(60, 90)
    end

    local retry = 0
    while GetTile(x, y).fg == targetTreeID and retry < 25 and botRunning do
        punch(x, y)
        humanSleep(180, 220) -- Variasi punch alami manusiawi (Human Jitter)
        retry = retry + 1
    end

    totalHarvested = totalHarvested + 1
    humanSleep(25, 45)
    collectHarvestDrops(4)

    -- Cek apakah tas penuh untuk drop ke gudang
    if findItem(targetBlockID) >= DROP_LIMIT or findItem(targetSeedID) >= DROP_LIMIT then
        dropAllToStorage()
    end
end

function mainHarvestLoop()
    if not botRunning then return end

    getMainWorldName()
    setModFly(true)
    setAntiBounce(true)
    setAutoCollect(true)
    isTransferring = false
    sleep(200)

    currentStatus = "Mendeteksi pohon farmable matang di world..."
    if targetTreeID == 0 then
        local found = detectFarmableTree()
        if not found then
            currentStatus = "Tidak ada pohon matang yang ditemukan!"
            botRunning = false
            showMenuDialog()
            return
        end
    else
        detectFarmableTree()
    end

    -- Pindai SELURUH WORLD secara dinamis:
    -- Lacak setiap pohon matang di mana pun berada (alas tanah, platform, batu, langit, dll)
    local rowMap = {}   -- rowMap[y] = { x1, x2, ... }
    local rowList = {}  -- daftar baris Y yang memiliki pohon

    for _, tile in pairs(GetTiles()) do
        if tile.fg == targetTreeID and tile.readyharvest then
            if not rowMap[tile.y] then
                rowMap[tile.y] = {}
                table.insert(rowList, tile.y)
            end
            table.insert(rowMap[tile.y], tile.x)
        end
    end

    -- Urutkan baris dari ATAS ke BAWAH (Y terkecil ke terbesar)
    table.sort(rowList)

    if #rowList == 0 then
        currentStatus = "Semua pohon sudah dipanen!"
        -- Jika pohon sudah habis tapi di tas masih ada sisa block / seed, drop semua ke gudang
        if findItem(targetBlockID) > 0 or findItem(targetSeedID) > 0 then
            currentStatus = "Setor sisa panen ke gudang..."
            dropAllToStorage(true)
        end
        botRunning = false
        showMenuDialog()
        return
    end

    local totalRows = #rowList
    for idx, rowY in ipairs(rowList) do
        if not botRunning then break end

        local xList = rowMap[rowY] or {}
        -- Pola Zigzag: Mulai dari KIRI ATAS (baris ganjil: kiri -> kanan, baris genap: kanan -> kiri)
        if idx % 2 == 1 then
            table.sort(xList, function(a, b) return a < b end)
        else
            table.sort(xList, function(a, b) return a > b end)
        end

        currentStatus = string.format("Memanen Baris Y = %d (%d/%d, %d pohon)...", rowY, idx, totalRows, #xList)

        for _, colX in ipairs(xList) do
            if not botRunning then break end
            harvestTreeAt(colX, rowY)
        end

        sleep(60)
    end

    -- Setor SEMUA sisa hasil panen terakhir (berapapun jumlahnya) ke gudang karena pohon sudah habis
    if findItem(targetBlockID) > 0 or findItem(targetSeedID) > 0 then
        currentStatus = "Setor sisa panen ke gudang..."
        dropAllToStorage(true)
    end

    botRunning = false
    currentStatus = "Panen Selesai (Completed!)"
    if LogToConsole then
        pcall(LogToConsole, string.format("`2[Harvest] `wPanen tuntas! Total: `2%d `wPohon | Setor: `2%d `wBlock, `2%d `wSeed.", 
              totalHarvested, totalBlockDropped, totalSeedDropped))
    end
    showMenuDialog()
end

-- =========================================================
-- MENU GUI IN-GAME DIALOG (100% CRASH-PROOF)
-- =========================================================
function showMenuDialog()
    local statusText = botRunning and "`2[RUNNING] `w" .. currentStatus or "`4[STOPPED] `wIdle"
    local treeInfo = (targetTreeID and targetTreeID > 0)
        and ("ID `2" .. targetTreeID .. " `w(Block: `2" .. targetBlockID .. "`w, Seed: `2" .. targetSeedID .. "`w)")
        or "Otomatis (Auto-Detect saat Start)"

    local matureLeft = countMatureTrees()

    local lines = {}
    table.insert(lines, "set_default_color|`o")
    table.insert(lines, "add_label_with_icon|big|`2Auto Harvest Dirt Farm|left|18|")
    table.insert(lines, "add_spacer|small|")
    table.insert(lines, "add_textbox|`oStatus: " .. statusText .. "|left|")
    table.insert(lines, "add_textbox|`oTarget: " .. treeInfo .. "|left|")
    table.insert(lines, "add_textbox|`oPohon Matang di World: `2" .. matureLeft .. " Pohon|left|")
    table.insert(lines, "add_textbox|`oTotal Panen: `2" .. totalHarvested .. " Pohon `w| Setor: `2" .. totalBlockDropped .. " Block, " .. totalSeedDropped .. " Seed|left|")
    table.insert(lines, "add_spacer|small|")
    table.insert(lines, "add_text_input|input_storage_world|World Gudang Storage:|" .. STORAGE_WORLD .. "|20|")
    table.insert(lines, "add_text_input|input_storage_door|Door ID Gudang (Opsional):|" .. STORAGE_DOOR .. "|20|")
    table.insert(lines, "add_text_input|input_drop_limit|Batas Drop Tas (Default 190):|" .. DROP_LIMIT .. "|5|")
    table.insert(lines, "add_text_input|input_tree_id|Target Tree ID (0 = Auto-Detect):|" .. targetTreeID .. "|6|")
    table.insert(lines, "add_spacer|small|")

    if botRunning then
        table.insert(lines, "add_button|btn_stop|`4[ STOP BOT ]|noflags|0|0|")
    else
        table.insert(lines, "add_button|btn_start|`2[ START HARVEST ]|noflags|0|0|")
    end

    table.insert(lines, "add_button|btn_refresh|`9Refresh Status|noflags|0|0|")
    table.insert(lines, "add_quick_exit|")
    table.insert(lines, "end_dialog|harvest_menu|Simpan & Tutup||")

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
                pcall(LogToConsole, "`4[Anti-Ban Alert] `wBot otomatis berhenti untuk melindungi akun & IP Anda!")
            end
            botRunning = false
            currentStatus = "Dijeda Otomatis (Server Warning Detected)"
            return false
        end
    end

    if variant.v1 == "OnDialogRequest" then
        if variant.v2 and variant.v2:find("harvest_menu") then
            return false
        end
        return true
    end
    return false
end

-- Hook paket string keluar untuk menangkap input formulir & blokir collect di gudang
function hookSendPacket(type, pkt)
    -- BLOKIR TOTAL: Jangan collect apapun saat berada di world storage / proses transfer!
    if isTransferring or isInStorageWorld() then
        if type == 11 or (pkt and (pkt:find("action|collect") or pkt:find("item_collect"))) then
            return true -- Blokir pengiriman paket collect string ke server
        end
    end

    if not pkt then return false end

    -- Command chat /ht, /harvest, atau /menu
    if pkt:find("/ht") or pkt:find("/harvest") or pkt:find("/menu") then
        showMenuDialog()
        return true
    end

    if pkt:find("dialog_name|harvest_menu") then
        -- Tangkap input form jika user mengubah pengaturan
        local newWorld = pkt:match("input_storage_world|([^|\n]+)")
        if newWorld and newWorld ~= "" then STORAGE_WORLD = newWorld:upper():gsub(" ", "") end

        local newDoor = pkt:match("input_storage_door|([^|\n]+)")
        if newDoor then STORAGE_DOOR = newDoor:gsub(" ", "") end

        local newLimit = pkt:match("input_drop_limit|([^|\n]+)")
        if newLimit and tonumber(newLimit) then DROP_LIMIT = tonumber(newLimit) end

        local newTreeId = pkt:match("input_tree_id|([^|\n]+)")
        if newTreeId and tonumber(newTreeId) then
            targetTreeID = tonumber(newTreeId)
            if targetTreeID > 0 then
                targetSeedID  = targetTreeID
                targetBlockID = targetTreeID - 1
            end
        end

        local threadFunc = runThread or RunThread
        local function startTask(fn)
            if threadFunc then threadFunc(fn) else local co = coroutine.create(fn); coroutine.resume(co) end
        end

        if pkt:find("buttonClicked|btn_start") then
            if not botRunning then
                botRunning = true
                currentStatus = "Memulai Auto Harvest..."
                startTask(mainHarvestLoop)
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
    if isTransferring or isInStorageWorld() then
        if packet.type == 11 then
            return true -- Blokir pengiriman paket collect raw ke server (100% tidak bisa mengambil item)
        end
    end
    return false
end

-- Daftarkan event hook (mendukung variasi urutan argumen launcher)
if AddHook then
    pcall(AddHook, hookVariant, "OnVariant")
    pcall(AddHook, "OnVariant", hookVariant)
    pcall(AddHook, hookSendPacket, "OnSendPacket")
    pcall(AddHook, "OnSendPacket", hookSendPacket)
    pcall(AddHook, hookSendPacketRaw, "OnSendPacketRaw")
    pcall(AddHook, "OnSendPacketRaw", hookSendPacketRaw)
end

if LogToConsole then
    pcall(LogToConsole, "`2[Auto Harvest] `wScript dimuat! Ketik `2/ht `watau `2/harvest `wuntuk membuka menu.")
end

showMenuDialog()
