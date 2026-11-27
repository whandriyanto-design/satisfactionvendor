-- =====================================================================
-- Kebijakan Row Level Security (RLS) untuk Monitoring Surat
-- =====================================================================
-- Tujuan: hanya ADMIN yang boleh menambah / mengubah / menghapus data,
-- VIEWER hanya boleh membaca, dan pengguna yang belum login tidak bisa
-- membaca apa pun. Aturan ini ditegakkan oleh database, sehingga tetap
-- berlaku walaupun kode di browser diubah oleh pengguna.
--
-- Cara pakai:
--   1. Buka Supabase Dashboard > SQL Editor.
--   2. JALANKAN DULU query "CEK" di bawah untuk melihat kebijakan yang
--      sudah ada. Kebijakan RLS bersifat OR: kalau masih ada kebijakan
--      lama yang longgar (mis. "Enable all access" / using (true) untuk
--      insert/update/delete), viewer TETAP bisa mengubah data. Hapus
--      kebijakan lama seperti itu (DROP POLICY "<nama>" ON <tabel>;).
--   3. Jalankan sisa skrip ini. Skrip aman dijalankan ulang.
--   4. Uji: login sebagai viewer, coba ubah status -> harus muncul pesan
--      "Perubahan ditolak oleh server".
--
-- Asumsi struktur: public.user_roles(user_id uuid, role text) dengan
-- role = 'admin' untuk admin. Sesuaikan bila berbeda.
-- =====================================================================

-- CEK: daftar kebijakan yang sudah ada
-- select tablename, policyname, cmd, roles, qual, with_check
-- from pg_policies
-- where schemaname = 'public' and tablename in ('perusahaan', 'pengajuan', 'user_roles')
-- order by tablename, cmd;


-- ---------- Fungsi bantu: apakah user yang login adalah admin? ----------
-- SECURITY DEFINER agar bisa membaca user_roles tanpa terhalang RLS-nya sendiri.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid() and role = 'admin'
  );
$$;

revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;


-- ---------- Aktifkan RLS ----------
alter table public.perusahaan enable row level security;
alter table public.pengajuan  enable row level security;
alter table public.user_roles enable row level security;


-- ---------- perusahaan ----------
drop policy if exists "perusahaan_select_login" on public.perusahaan;
drop policy if exists "perusahaan_insert_admin" on public.perusahaan;
drop policy if exists "perusahaan_update_admin" on public.perusahaan;
drop policy if exists "perusahaan_delete_admin" on public.perusahaan;

create policy "perusahaan_select_login" on public.perusahaan
  for select to authenticated using (true);
create policy "perusahaan_insert_admin" on public.perusahaan
  for insert to authenticated with check (public.is_admin());
create policy "perusahaan_update_admin" on public.perusahaan
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "perusahaan_delete_admin" on public.perusahaan
  for delete to authenticated using (public.is_admin());


-- ---------- pengajuan ----------
drop policy if exists "pengajuan_select_login" on public.pengajuan;
drop policy if exists "pengajuan_insert_admin" on public.pengajuan;
drop policy if exists "pengajuan_update_admin" on public.pengajuan;
drop policy if exists "pengajuan_delete_admin" on public.pengajuan;

create policy "pengajuan_select_login" on public.pengajuan
  for select to authenticated using (true);
create policy "pengajuan_insert_admin" on public.pengajuan
  for insert to authenticated with check (public.is_admin());
create policy "pengajuan_update_admin" on public.pengajuan
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "pengajuan_delete_admin" on public.pengajuan
  for delete to authenticated using (public.is_admin());


-- ---------- user_roles ----------
-- Setiap user hanya bisa membaca perannya sendiri.
-- Tidak ada kebijakan insert/update/delete: peran hanya bisa diubah lewat
-- Supabase Dashboard (Table Editor), sehingga viewer tidak bisa menjadikan
-- dirinya admin.
drop policy if exists "user_roles_select_self" on public.user_roles;

create policy "user_roles_select_self" on public.user_roles
  for select to authenticated using (user_id = auth.uid());
