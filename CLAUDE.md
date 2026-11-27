# CLAUDE.md — Monitoring Surat Survey Pasar (PLN UIT JBT)

Panduan untuk Claude (dan developer) saat bekerja di repositori ini. Baca seluruh file ini sebelum mengubah kode.

## 1. Ringkasan arsitektur

Aplikasi web satu halaman (single-page) untuk memantau proses surat survey pasar
(SKSO, SPSO, SKKP, SKPV) dari vendor/perusahaan di PT PLN (Persero) UIT JBT.

- **Tanpa build step dan tanpa backend sendiri.** Semua kode (CSS, HTML, JavaScript) ada di
  `index.html`. Tidak ada `package.json`, bundler, atau framework.
- **Backend = Supabase** (Auth + PostgreSQL), diakses langsung dari browser memakai
  `@supabase/supabase-js@2` dari CDN jsDelivr.
- **Hosting:** situs statis yang diambil dari branch `main`. Perubahan baru tampil setelah
  di-merge ke `main`; pengguna mungkin perlu hard refresh (Ctrl+Shift+R).
- **Perlindungan data yang sebenarnya ada di Row Level Security (RLS) Supabase**, bukan di
  JavaScript. Kode di browser hanya mengatur tampilan.

### Struktur file

```
├── index.html                 Seluruh aplikasi: CSS, markup, dan JavaScript
├── supabase/
│   └── rls_policies.sql       Kebijakan RLS + fungsi public.is_admin() (dijalankan manual di Supabase)
├── logo-pln.png               Logo PLN (login & header) — 664 KB, perlu diperkecil
├── logo_danan.png             Logo Danantara (header)
├── logo-tambahan.png          TIDAK dipakai di kode
├── clirit.png                 Favicon (sebenarnya file JPEG 810×1440)
└── CLAUDE.md                  File ini
```

### Isi `index.html` (urutan dari atas ke bawah)

| Bagian | Isi |
|---|---|
| `<style>` | Variabel warna di `:root`, gaya login, header, kartu statistik, form admin, tabel, detail, pagination, breakpoint `1100px` dan `800px` |
| `#loginPage` | Form email/password |
| `#mainApp` | Header (logo, judul, badge peran, Logout, jam), `#statsArea`, `#adminForms`, filter, `#mainTable`, `#pagination` |
| `SUPABASE CONFIG` | `SUPABASE_URL`, `SUPABASE_ANON_KEY` (kunci *publishable*, memang boleh publik), client dengan sesi di `sessionStorage` |
| Konstanta | `DURASI_JAM` (batas jam per aktivitas), `aktivitasList` (6 aktivitas), `ITEMS_PER_PAGE`, `JENIS_MAP` |
| `HELPER` | `esc()` (escape HTML), `todayLocal()` (tanggal lokal YYYY-MM-DD), `formatSisaWaktu()` |
| Autentikasi | `doLogin`, `startSession`, `sessionExpired`, `handleAuthError`, `showMainApp`, `logout`, `updateUIByRole`, `checkAdmin` |
| `VALIDASI URUTAN` | `isPreviousStepCompleted`, `canUpdateStatus` |
| `FUNGSI SUPABASE` | `loadData`, `tambahPerusahaan`, `tambahPengajuan`, `updateStatus`, `hapusPengajuan`, `hapusPerusahaan` |
| `FUNGSI RENDER` | `getSummary`, `getPerusahaanSummary`, `renderTable`, `generateDetailHTML`, `toggleDetail`, `exportToCSV` |
| Inisialisasi | Event listener, lalu cek sesi dengan `supabaseClient.auth.getSession()` |

### Model data (Supabase, schema `public`)

| Tabel | Kolom penting |
|---|---|
| `perusahaan` | `id`, `nama` |
| `pengajuan` | `id`, `perusahaan_id` → `perusahaan.id`, `nomor_registrasi`, `jenis_surat`, `tgl_pengajuan`, `statuses` (array 6 elemen: `belum`/`proses`/`selesai`), `start_times` (array 6 elemen ISO timestamp atau `null`), `nomor_surat_balasan` |
| `user_roles` | `user_id` (uuid = `auth.users.id`), `role` (`'admin'`; selain itu dianggap viewer) |

### Alur bisnis

1. Setiap pengajuan melewati 6 aktivitas **berurutan** (`aktivitasList`). Tiap aktivitas: Belum → Proses → Selesai.
2. Saat aktivitas mulai "proses", waktu mulai disimpan di `start_times[i]`. Lewat dari `DURASI_JAM[i]` jam → status Terlambat.
3. Aktivitas ke-5 ("Sent a letter to Vendor") hanya bisa diselesaikan bila **Nomor Surat Balasan** diisi; nomor surat dan status disimpan dalam **satu** update.
4. "Belum" hanya boleh dipilih bila semua aktivitas sesudahnya masih "Belum".
5. Status perusahaan diturunkan dari pengajuannya: ada terlambat → "Ada terlambat"; ada proses → "Sedang proses"; semua selesai → "Semua selesai".

## 2. Aturan keamanan (WAJIB)

1. **Peran admin selalu diverifikasi lewat Supabase.**
   - Saat halaman dibuka: `supabaseClient.auth.getSession()` → `startSession(user)` → baca `user_roles` dari database.
   - **Jangan pernah** menyimpan atau membaca peran dari `localStorage`/`sessionStorage`/cookie/URL sebagai sumber kebenaran. Nilai seperti itu bisa diubah pengguna.
   - Bila peran gagal dibaca, default ke `viewer` (gagal = akses paling kecil).
   - `userRole`, `checkAdmin()`, dan `updateUIByRole()` **hanya** untuk tampilan. Jangan menganggapnya sebagai pengaman.
2. **Pengaman sebenarnya adalah RLS** di `supabase/rls_policies.sql`:
   - `authenticated`: boleh `select` di `perusahaan` dan `pengajuan`.
   - `insert`/`update`/`delete` hanya bila `public.is_admin()` bernilai true.
   - `user_roles`: pengguna hanya boleh membaca barisnya sendiri; **tidak ada** kebijakan insert/update/delete (peran diubah lewat Dashboard).
   - `anon` (belum login): tidak boleh membaca apa pun.
   - Setiap fitur baru yang menulis ke database harus tetap lolos aturan ini. Jangan menambah kebijakan yang longgar (mis. `using (true)` untuk insert/update/delete): kebijakan RLS bersifat OR, satu kebijakan longgar membuka semuanya.
3. **Update/hapus yang ditolak RLS tidak menghasilkan error**, hanya 0 baris. Selalu tambahkan `.select('id')` lalu cek jumlah baris, dan tampilkan `TIDAK_ADA_IZIN` bila kosong (contoh: `updateStatus`, `hapusPengajuan`, `hapusPerusahaan`).
4. **Cegah XSS.** Semua teks yang berasal dari database atau input pengguna harus melalui `esc()` sebelum masuk ke `innerHTML`, atau gunakan `textContent`. Nilai numerik di atribut `onclick` dibungkus `Number(...)`.
5. **Cegah saling timpa antar admin.** Sebelum menulis ulang array `statuses`/`start_times`, baca ulang baris dari database dan bandingkan dengan data yang sedang ditampilkan (lihat `updateStatus`). Bila berbeda, batalkan dan panggil `loadData()`.
6. **Sesi habis** → gunakan `handleAuthError(error)` pada setiap error dari Supabase agar pengguna dikembalikan ke halaman login.
7. **Kunci & rahasia:** `SUPABASE_ANON_KEY` adalah kunci publik dan boleh ada di kode. **Jangan pernah** menaruh `service_role` key, password database, atau token pribadi di repositori ini.

## 3. Standar penulisan kode

### Bahasa
- **Komentar kode, pesan `alert`/`confirm`/`prompt`, label UI, dan pesan commit: Bahasa Indonesia.**
- Nama aktivitas di `aktivitasList` tetap dalam Bahasa Inggris (sudah dipakai di data dan laporan).
- Nama variabel/fungsi mengikuti gaya yang ada: camelCase, campuran Indonesia (`tambahPengajuan`, `semuaPengajuan`) — pertahankan, jangan mengganti nama massal.

### JavaScript
- JavaScript biasa (tanpa framework, tanpa TypeScript), langsung di `<script>` dalam `index.html`.
- Semua akses database lewat `supabaseClient`; tangani `error` di setiap pemanggilan.
- Fungsi yang dipanggil dari atribut `onclick` di HTML hasil render harus ada di `window` (lihat blok "Expose functions to global").
- Gunakan `aktivitasList.length` alih-alih menulis angka `6` di kode baru.
- Tanggal "hari ini" untuk disimpan: pakai `todayLocal()`, **bukan** `new Date().toISOString().split('T')[0]` (itu UTC, mundur sehari sebelum 07:00 WIB).
- Fungsi admin diawali `if (!checkAdmin()) return;` (untuk tampilan), tetapi tetap mengandalkan RLS.
- Setelah perubahan data, panggil `await loadData()` agar tampilan sinkron.

### Tampilan UI
- Warna lewat variabel CSS di `:root`: `--navy` (#1e4663, utama), `--navy-dark`, `--gold` (#f0a500, aksen), `--green` (#2c7a4d, sukses/tambah), `--red` (#c0392b, hapus/terlambat), `--line`, `--muted`, `--bg-soft`. Jangan menambah warna baru tanpa alasan.
- Status memakai kelas badge yang sudah ada: `status-belum`, `status-proses`, `status-terlambat`, `status-selesai`.
- Tombol: `.btn .btn-green` (tambah), `.btn .btn-navy` (aksi umum), `.detail-btn`, `.hapus-btn` / `.hapus-pengajuan-btn` (merah).
- Kartu: `.stat-card` (statistik), `.form-tambah` (form admin dengan `<h3>` + `.field` berlabel).
- Setiap input form wajib punya `<label>`.
- Ikon memakai emoji (🏢 📄 ⏳ ⚠️ ✅ 📊 🗑 📋), konsisten dengan yang ada.
- Responsif: cek di lebar ≥1100px, 800–1100px, dan HP (±390px). Di HP kolom `.col-status` disembunyikan dan tabel aktivitas bisa digeser ke samping.
- Pertahankan identitas visual PLN (navy + kuning) dan kedua logo di header.

### Pengujian
- Tidak ada test suite di repositori. Uji perubahan dengan membuka `index.html` di browser.
- Untuk uji otomatis tanpa akun Supabase, gunakan Playwright dan cegat request ke `**/supabase-js@2` dengan Supabase tiruan (mock `createClient` yang menyediakan `auth.getSession`, `auth.onAuthStateChange`, `from().select/update/delete/insert/eq/maybeSingle`).
- Uji minimal: tampilan Admin vs Viewer, alur 6 aktivitas, XSS (nama berisi `<img onerror>`), dan tampilan HP.

## 4. Sebelum mengubah struktur database atau logika autentikasi

### Database
- [ ] Cek kebijakan yang ada di Supabase SQL Editor:
      `select tablename, policyname, cmd, roles, qual, with_check from pg_policies where schemaname = 'public';`
- [ ] Tabel baru: aktifkan RLS (`alter table ... enable row level security`) dan tambahkan kebijakan dengan pola yang sama di `supabase/rls_policies.sql` — select untuk `authenticated`, tulis hanya untuk `public.is_admin()`.
- [ ] Mengubah panjang/urutan aktivitas: `statuses` dan `start_times` di **data lama** juga harus dimigrasi; `DURASI_JAM`, `aktivitasList`, dan nilai awal di `tambahPengajuan` harus selaras.
- [ ] Mengganti nama kolom/tabel: cari semua pemakaian di `index.html` (`from('...')`, `.eq('...')`, properti objek) dan di `rls_policies.sql`.
- [ ] `hapusPerusahaan` hanya menghapus baris `perusahaan`; pengajuannya ikut terhapus hanya bila foreign key `pengajuan.perusahaan_id` memakai `ON DELETE CASCADE` (belum diverifikasi di database). Cek sebelum mengubah relasi ini.
- [ ] Perbarui `supabase/rls_policies.sql` agar tetap mencerminkan kondisi database, dan pastikan skrip aman dijalankan ulang (`drop policy if exists` sebelum `create policy`).
- [ ] Perubahan SQL dijalankan manual di Supabase; catat di deskripsi PR langkah yang harus dilakukan.

### Autentikasi & peran
- [ ] Pastikan setiap admin punya baris `role = 'admin'` di `user_roles` **sebelum** mengubah kebijakan, agar admin tidak terkunci.
- [ ] Jangan menambah kebijakan yang membolehkan pengguna menulis ke `user_roles` sendiri (dulu ada "Users can insert own role" — itu celah eskalasi ke admin dan sudah harus dihapus).
- [ ] Bila menambah peran baru (mis. `supervisor`), ubah `startSession`, `updateUIByRole`, `checkAdmin`, **dan** fungsi/kebijakan RLS terkait.
- [ ] Sesi Supabase sengaja disimpan di `sessionStorage` (tutup tab = keluar). Mengganti ke `localStorage` mengubah perilaku login di komputer bersama — diskusikan dulu.
- [ ] Uji dengan dua akun nyata (admin dan viewer): viewer harus mendapat pesan "Perubahan ditolak oleh server" saat mencoba menulis.

## 5. Hal yang diketahui belum ditangani

- Masih ada jeda singkat antara cek konflik dan penyimpanan di `updateStatus`; penutupan penuh butuh fungsi RPC di database.
- Perubahan dari admin lain tidak muncul otomatis (belum memakai Supabase Realtime); "Sisa Waktu" hanya dihitung ulang saat data dimuat.
- Export CSV: tanda kutip belum di-escape, belum ada BOM untuk Excel, status masih kode internal.
- Tombol Tambah belum dinonaktifkan selama proses dan belum ada cek duplikat nomor registrasi; kuota 500 hanya ditampilkan.
- `logo-pln.png` terlalu besar; `logo-tambahan.png` tidak dipakai; favicon berupa JPEG.
- Versi `supabase-js` dari CDN belum dikunci ke versi pasti.
