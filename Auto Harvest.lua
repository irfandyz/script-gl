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
-- O(1) Instant Hash Map Lookup & Stack-Overflow Protection
-- =========================================================
local floatingItemMap = {}

local function rebuildFloatingMap()
    floatingItemMap = {}
    local rawObjs = GetObjectList()
    if rawObjs then
        for _, obj in pairs(rawObjs) do
            local ox = math.floor(obj.posX / 32)
            local oy = math.floor(obj.posY / 32)
            local key = ox .. "," .. oy
            floatingItemMap[key] = (floatingItemMap[key] or 0) + (obj.amount or 0)
        end
    end
end

function dropAllToStorage()
    local blockCount = findItem(targetBlockID)
    local seedCount  = findItem(targetSeedID)

    -- Cek apakah memenuhi syarat drop
    if blockCount < DROP_LIMIT and seedCount < DROP_LIMIT then
        return
    end

    local mainWorld = getMainWorldName()
    if not mainWorld or mainWorld == "" then return end

    isTransferring = true
    setAutoCollect(false) -- MATIKAN auto collect client sebelum melangkah ke gudang

    local me = GetLocal()
    local savedX = me and math.floor(me.posX / 32) or 50
    local savedY = me and math.floor(me.posY / 32) or 23

    currentStatus = "Menyetor hasil panen ke " .. STORAGE_WORLD .. "..."
    if LogToConsole then
        pcall(LogToConsole, "`2[Storage] `wKapasitas tas tercapai (" .. blockCount .. " Block, " .. seedCount .. " Seed). Menuju " .. STORAGE_WORLD .. "...")
    end

    -- Masuk ke World Gudang Penyimpanan
    join(STORAGE_WORLD, STORAGE_DOOR ~= "" and STORAGE_DOOR or nil)

    setModFly(true)
    setAntiBounce(true)
    setAutoCollect(false) -- Pastikan auto collect TETAP MATI selama di world storage
    humanSleep(200, 300)

    -- Bangun lookup table item floating secara instan (O(1))
    rebuildFloatingMap()

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

    -- 1. Helper pencari posisi drop Block (dengan proteksi batas lantai Y <= 54)
    local function findNextBlockDropTile(startY)
        if startY > 54 then
            if LogToConsole then
                pcall(LogToConsole, "`4[Storage Penuh] `wPeringatan: Baris drop block telah mencapai batas lantai Y = 54!")
            end
            return 98, 54
        end

        local curX = lastDropBlockX
        while curX >= 1 and botRunning do
            local tile = GetTile(curX, startY)
            local isBlocked = tile and (tile.fg ~= 0 and tile.fg ~= 102)
            if not isBlocked then
                local floatingCount = floatingItemMap[curX .. "," .. startY] or 0
                if floatingCount < 3800 then
                    lastDropBlockX = curX
                    floatingItemMap[curX .. "," .. startY] = floatingCount + 200 -- Update cache
                    return curX, startY
                end
            end
            curX = curX - 1
        end
        -- Jika baris penuh sampai X = 1, turun 2 baris
        lastDropBlockX = 98
        return findNextBlockDropTile(startY + 2)
    end

    -- 2. Helper pencari posisi drop Seed (dengan proteksi batas langit Y >= 2)
    local function findNextSeedDropTile(startY)
        if startY < 2 then
            if LogToConsole then
                pcall(LogToConsole, "`4[Storage Penuh] `wPeringatan: Baris drop seed telah mencapai batas langit Y = 2!")
            end
            return 98, 2
        end

        local curX = lastDropSeedX
        while curX >= 1 and botRunning do
            local tile = GetTile(curX, startY)
            local isBlocked = tile and (tile.fg ~= 0 and tile.fg ~= 102)
            if not isBlocked then
                local floatingCount = floatingItemMap[curX .. "," .. startY] or 0
                if floatingCount < 3800 then
                    lastDropSeedX = curX
                    floatingItemMap[curX .. "," .. startY] = floatingCount + 200 -- Update cache
                    return curX, startY
                end
            end
            curX = curX - 1
        end
        -- Jika baris Seed penuh sampai X = 1, naik 2 baris ke atas
        lastDropSeedX = 98
        return findNextSeedDropTile(startY - 2)
    end

    -- Drop Block jika memenuhi syarat (SEJAJAR White Door di baris blockDropY)
    if findItem(targetBlockID) >= DROP_LIMIT then
        local toDrop = findItem(targetBlockID)
        local targetX, targetY = findNextBlockDropTile(blockDropY)

        -- Berdiri tepat di targetY (sejajar White Door, bukan 1 blok di atas)
        FindPath(targetX, targetY)
        sleep(250)

        local p = GetLocal()
        if p then
            SendPacketRaw(false, {type = 0, x = p.posX, y = p.posY, state = 0})
            sleep(120)
        end
        dropItem(targetBlockID, toDrop)
        totalBlockDropped = totalBlockDropped + toDrop
        sleep(200)
    end

    -- Drop Seed jika memenuhi syarat (MELAYANG 2 BLOK DI ATAS White Door di seedDropY)
    if findItem(targetSeedID) >= DROP_LIMIT then
        local toDrop = findItem(targetSeedID)
        local targetX, targetY = findNextSeedDropTile(seedDropY)

        -- Melayang tepat di targetY (2 blok di atas White Door)
        FindPath(targetX, targetY)
        sleep(250)

        local p = GetLocal()
        if p then
            SendPacketRaw(false, {type = 0, x = p.posX, y = p.posY, state = 0})
            sleep(120)
        end
        dropItem(targetSeedID, toDrop)
        totalSeedDropped = totalSeedDropped + toDrop
        sleep(200)
    end

    -- Selesai Drop: Pulang kembali ke world Dirt Farm
    currentStatus = "Kembali ke world farm..."
    join(mainWorld, MAIN_WORLD_DOOR ~= "" and MAIN_WORLD_DOOR or nil)

    setModFly(true)
    setAntiBounce(true)
    humanSleep(200, 300)

    -- Kembali ke titik kerja terakhir saat panen
    local pathRetry = 0
    while (math.floor(GetLocal().posX / 32) ~= savedX or math.floor(GetLocal().posY / 32) ~= savedY) and pathRetry < 25 and botRunning do
        FindPath(savedX, savedY)
        sleep(250)
        pathRetry = pathRetry + 1
    end

    isTransferring = false
    setAutoCollect(true) -- AKTIFKAN KEMBALI auto collect hanya setelah aman tiba di world farm
end

-- =========================================================
-- ALUR UTAMA HARVEST DIRT FARM (ZIGZAG PATH DENGAN PROXIMITY CHECK)
-- =========================================================
function harvestRow(y, startX, endX, stepX)
    for x = startX, endX, stepX do
        if not botRunning then return end

        local tile = GetTile(x, y)
        -- Jika terdapat pohon yang siap panen
        if tile and tile.fg == targetTreeID and tile.readyharvest then
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
            humanSleep(30, 50)
            collectHarvestDrops(4)

            -- Cek apakah tas penuh untuk drop ke gudang
            if findItem(targetBlockID) >= DROP_LIMIT or findItem(targetSeedID) >= DROP_LIMIT then
                dropAllToStorage()
            end
        end
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

    currentStatus = "Mendeteksi pohon farmable matang..."
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

    -- Di Dirt Farm: Lorong panen pohon berada di baris GANJIL
    -- Bagian Atas: Y = 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23
    -- Bagian Bawah: Y = 25, 27, 29, 31, 33, 35, 37, 39, 41, 43, 45, 47, 49, 51, 53
    local harvestRows = {}
    for y = 3, 53, 2 do
        table.insert(harvestRows, y)
    end

    local totalRows = #harvestRows
    for idx, rowY in ipairs(harvestRows) do
        if not botRunning then break end

        -- FAST ROW SKIP: Lewati baris jika tidak ada pohon matang sama sekali!
        if rowHasMatureTrees(rowY) then
            currentStatus = string.format("Memanen Baris Y = %d (%d/%d)...", rowY, idx, totalRows)

            -- Pola Zigzag: baris ganjil maju (2 -> 97), baris berikutnya mundur (97 -> 2)
            if idx % 2 == 1 then
                harvestRow(rowY, 2, 97, 1)
            else
                harvestRow(rowY, 97, 2, -1)
            end

            sleep(60)
        end
    end

    -- Setor sisa hasil panen terakhir jika ada
    if findItem(targetBlockID) > 0 or findItem(targetSeedID) > 0 then
        currentStatus = "Setor sisa panen ke gudang..."
        dropAllToStorage()
    end

    botRunning = false
    currentStatus = "Panen Selesai (Completed!)"
    if LogToConsole then
        pcall(LogToConsole, string.format("`2[Harvest] `wPanen selesai! Total: `2%d `wPohon | Setor: `2%d `wBlock, `2%d `wSeed.", 
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

    -- Command chat /harvest atau /menu
    if pkt:find("/harvest") or pkt:find("/menu") then
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
    pcall(LogToConsole, "`2[Auto Harvest] `wScript berhasil dimuat! Ketik `2/harvest `wuntuk membuka menu.")
end

showMenuDialog()
