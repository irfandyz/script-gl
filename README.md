# Growtopia Automation Scripts (GrowLauncher)

Koleksi script otomatisasi Growtopia berbasis Lua untuk **GrowLauncher** yang dilengkapi fitur proteksi akun, Anti-Ban / Humanized Jitter, dan Anti-Stuck.

---

## 📁 Daftar Script

### 1. `df enhance.lua`
Script pembuat **Dirt Farm (DF)** otomatis dari awal sampai selesai dengan fitur:
- **Pembersihan Lava Cepat**: Membersihkan lava dengan efisien tanpa delay berlebihan.
- **QC & Sapu Bersih World**: Memastikan lorong pohon (baris ganjil: Y 25, 27, ..., 53) bersih dari sisa block/batu tanpa merusak jalur tanam Dirt Farm (baris genap: Y 24, 26, 28, ..., 54).
- **Safe Pathfinding & Anti-Stuck**: Otomatis mendeteksi dan menghancurkan rintangan jika stuck tanpa merusak struktur farm.
- **Anti-Ban Protection**:
  - Humanized delay/jitter acak pada setiap aksi.
  - Cooldown otomatis jika terjadi kegagalan warp berulang.
  - Deteksi peringatan server (server warning detector).
- **Native In-game Dialog**: Menu kontrol visual langsung di dalam game.

### 2. `Auto Harvest.lua`
Script pemanen otomatis untuk berbagai jenis farmable dengan fitur:
- **Auto-Detect**: Mendeteksi pohon matang, block ID, dan seed ID secara otomatis.
- **Selective Collect**: Mengambil block/seed dan otomatis mengabaikan Gems (ID 112).
- **Drop Terapung (Floating Drop)**: Menjatuhkan seed 2 tile melayang di atas tumpukan block (`blockDropY - 2`) dengan koordinat X terpisah agar tidak bertumpuk/penuh.
- **Zero-Pickup Storage Protection**: 4-lapis proteksi saat berada di storage world agar bot tidak mengambil kembali item yang sudah di-drop.
- **Anti-Ban & Humanized Delays**: Proteksi interval warp dan jeda antar-panen.

### 3. `Growganoth Dropper.lua`
Script otomatisasi pengorbanan item pada **Event Halloween Growganoth** dengan fitur:
- **Precision 1-by-1 Drop**: Menjatuhkan item tepat 1 per 1 (`count = 1`) setiap kali naik ke pusaran untuk mencegah hilangnya ratusan item sekaligus akibat limitasi reward Growganoth.
- **Interactive Coordinate Locking**: Terbang manual ke atas pusaran Growganoth, buka menu dialog (`/gw`), lalu klik `[ 📍 Simpan Posisi Saat Ini ]` untuk mengunci koordinat.
- **Lock-Safe Protection**: Bot tidak dapat di-start sebelum posisi pusaran berhasil disimpan dan item target terdeteksi di tas.
- **Quick Preset**: Pilihan tombol cepat untuk item populer event: **Ripper Wings** (ID: 2572) dan **Battle Trout** (ID: 3064), serta input custom ID.
- **Auto-Exit on Finish**: Begitu seluruh item di tas habis dikorbankan (0), bot otomatis berhenti dan keluar dari world (`Quit to Exit`).

---

## 🚀 Cara Penggunaan
1. Salin script (`df enhance.lua`, `Auto Harvest.lua`, atau `Growganoth Dropper.lua`) ke folder Lua GrowLauncher Anda:
   ```
   /storage/emulated/0/launcher.powerkuy.growlauncher/ScriptLua/
   ```
2. Buka menu script pada GrowLauncher dan jalankan script yang diinginkan.
3. Buka menu in-game menggunakan command chat:
   - `/df` untuk menu Dirt Farm Builder
   - `/ht` untuk menu Auto Harvest
   - `/gw` untuk menu Growganoth Dropper
