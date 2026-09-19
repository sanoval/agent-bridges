# Conversation State — Migrasi bridge Antigravity: agy-bridge → agy-mcp

Tanggal mulai: 2026-09-19
Repo: sanoval/agent-bridges (branch `claude/wizardly-dirac-avnwi2`)
Scope: mengganti bridge Antigravity dari `agy-bridge` (MCP blocking, timeout
ceiling) ke `agy-mcp` (job async + wake hook). Termasuk: penyesuaian kontrak
payload di `delegation-pipeline`, pin per-lens untuk two-bridge mode, rilis
plugin 0.3.0, panduan migrasi pengguna. **Tidak termasuk**: mengganti bridge
Codex QA/Security (tetap `openai/codex-plugin-cc`), dan mengevaluasi proxy
lintas-provider seperti 9Router (lihat `docs/ARCHITECTURE.md` → Status).

## Delegation tally
Two-bridge mode (templates/CLAUDE.md + templates/CLAUDE-two-bridge-overlay.md):
Antigravity — Analyzer: 0 | Coder: 0 | QA lens: 0 | Security lens: 0 | Release Writer: 0

Tally 0 di semua peran **bukan** red flag untuk unit-unit di file ini: seluruh
pekerjaan ini adalah penyuntingan delegation config repo ini sendiri, yang
secara eksplisit dikecualikan dari Gate (`templates/CLAUDE.md` → "Do NOT
delegate", butir 3: *"editing this delegation config"*). Unit yang menyentuh
kode aplikasi di luar itu tetap wajib lewat Coder.

## Konteks

Call Coder ke `agy-bridge` rutin menggantung sampai ~600 detik lalu mati tanpa
hasil. Akar masalahnya bukan kelambatan: budget internal tool `delegate`
(600s) besarnya **sama persis** dengan client timeout yang disarankan
(`600000` ms), jadi tidak ada margin — dua deadline identik saling balapan.
Menaikkan timeout ditolak sebagai solusi (buang waktu); arah yang dipilih
adalah menghilangkan model blocking-nya sama sekali.

`agy-mcp` mengembalikan `job_id` seketika dan membangunkan Claude Code lewat
hook `PostToolUse` saat job selesai, sehingga job lambat tidak lagi menempati
request yang bisa timeout.

Panduan migrasi pengguna: `docs/MIGRATION.md`.

---

## Status: Unit 0 — Fase 0: Pre-flight — BELUM MULAI

Tidak ada perubahan konfigurasi apa pun di unit ini. Tujuannya mengumpulkan
baseline, karena tanpa angka pembanding kita tidak bisa membuktikan migrasi
berhasil.

### Requirement summary
- `agy` CLI **≥ 1.1.15** — hard floor `agy-mcp` (README `tphakala/agy-mcp`),
  bukan rekomendasi.
- Hanya boleh ada **satu** registrasi MCP bernama `antigravity`.
- Baseline performa `agy-bridge` tercatat sebelum diubah.

### Langkah (dijalankan di mesin lokal)

```bash
agy --version
claude mcp list
```

Lalu periksa `~/.claude.json` → `mcpServers.antigravity`. Jika ada, itu
duplikat dari registrasi milik plugin — **simpan isinya** (itu bahan rollback,
lihat `docs/MIGRATION.md` → Rollback), lalu hapus entri tersebut.

### Yang direkam di sini
| Item | Nilai |
|---|---|
| `agy --version` | 1.2.7 — di atas floor 1.1.15, lolos |
| Duplikat `antigravity` di user scope? | <isi> |
| Jumlah entri `antigravity` setelah dibersihkan | <isi — harus 1> |
| Durasi call Coder yang **berhasil**, kira-kira | <isi> |
| Dari ~5 delegasi terakhir, berapa yang kena ~600s | <isi> |

### Gap list
| # | Gap | Severity | Catatan |
|---|-----|----------|---------|
| 1 | Duplikat `antigravity` belum dicek, baseline durasi/rasio-timeout belum dicatat | Medium | Tidak menghalangi instalasi binary `agy-mcp` (Unit 1 langkah 1), tapi perbandingan performa di Unit 1 tidak bisa disimpulkan valid tanpa ini |

### Kesimpulan
IN PROGRESS — versi CLI lolos, lanjut ke instalasi binary `agy-mcp` (Unit 1
langkah 1) sambil item lain di unit ini masih terbuka.

---

## Status: Unit 1 — Fase 1: Pilot berdampingan — BELUM MULAI

`agy-bridge` **tetap jalan dan tidak disentuh**. `agy-mcp` didaftarkan sebagai
server kedua dengan nama berbeda, dipakai manual untuk satu unit kerja nyata.
Tidak ada perubahan pada skill/template di fase ini. Risiko ke pipeline
sehari-hari: nol — kalau pilot gagal, cukup hapus registrasi keduanya.

### Requirement summary

Tiga klaim di bawah ini berasal dari README `agy-mcp` dan **belum pernah
diverifikasi langsung**. Fase 1 ada khusus untuk itu. Kegagalan salah satu =
berhenti, jangan lanjut ke Fase 2.

| # | Klaim yang diuji | Kriteria lulus |
|---|---|---|
| 1 | `mode: "plan"` benar-benar read-only | `git status` bersih setelah call selesai |
| 2 | Hook wake benar-benar membangunkan Claude Code | Dapat pesan satu baris berisi `job_id` tanpa polling manual |
| 3 | Dua job bisa jalan konkuren | Dua `job_id` berbeda aktif bersamaan, hasil tidak tertukar |

### Catatan verifikasi binary (sebelum langkah di bawah)

`agy-mcp` v2.6.1 (dari `brew install tphakala/tap/agy-mcp`) terpasang di
`/opt/homebrew/bin/agy-mcp`. Sempat muncul kekhawatiran `hook-wait` tidak ada
(WebFetch sebelumnya salah meringkas 10 release notes terakhir sebagai
"tidak menyebut hook-wait/PostToolUse" — itu ringkasan yang keliru, bukan
fakta rilis). README mentah `main` branch mendokumentasikan `hook-wait`
secara rinci (baris 201-243). Uji manual:
- `agy-mcp wait-job -h` → tampil help text normal, subcommand-dispatch jalan.
- `agy-mcp hook-wait -h` → kosong, exit code `0`. Konsisten dengan desain
  yang didokumentasikan ("reads PostToolUse payload from stdin... on any
  internal error exits 0 silently"), **bukan** tanda command tidak ada
  (yang akan exit 127). Tidak bisa diverifikasi lebih jauh lewat pemanggilan
  manual — README eksplisit bilang "not useful to invoke by hand". Klaim #2
  di bawah baru benar-benar teruji lewat call `agy_run` sungguhan.

### Keputusan scope: global (user), bukan project

Pengguna memilih scope **user**, bukan project/local — alasan: kesederhanaan
operasional pribadi, bukan untuk distribusi tim. Konsekuensi yang sudah
dicatat ke pengguna: (1) blast radius pilot jadi semua project yang dibuka,
bukan cuma satu project uji; (2) ini di luar model distribusi plugin
`agent-bridges` (yang berbasis per-project enable) — kalau produksi nanti
juga dipilih scope user, `agent-bridges` berhenti jadi sesuatu yang bisa
dibagi ke tim untuk bagian bridge Antigravity-nya. Belum ada keputusan final
soal ini untuk Fase 3 — dicatat sebagai keputusan terbuka.

`~/.claude/settings.json` pengguna ternyata sudah kompleks: terintegrasi
dengan sistem hook eksternal (`~/.orca/agent-hooks/*`) dan status bar
iTerm2 di hampir semua event hook, plus `PostToolUse` sudah punya 2 entry
wildcard sebelum migrasi ini. Overwrite penuh ditolak — dipakai `jq` untuk
menambah satu elemen ke array `PostToolUse` yang sudah ada:

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq '.hooks.PostToolUse += [{
  "matcher": "mcp__antigravity_next__agy_run(_sync)?",
  "hooks": [
    { "type": "command", "command": "agy-mcp hook-wait", "asyncRewake": true, "timeout": 3700 }
  ]
}]' ~/.claude/settings.json > /tmp/settings.json.new && mv /tmp/settings.json.new ~/.claude/settings.json
```

**Terverifikasi:** `jq empty` valid, `PostToolUse | length` naik dari 2 ke 3.
Backup ada di `~/.claude/settings.json.bak`.

Catatan lain dari file yang sama (bukan bagian migrasi ini, sekadar temuan):
`enabledPlugins` pengguna sudah mengaktifkan `codex@openai-codex` **dan**
`agent-bridges@agent-bridges` — kemungkinan besar pengguna sudah three-bridge
mode di sebagian besar project, bukan two-bridge seperti asumsi diskusi pin
QA/Security lens sebelumnya. Pin `gemini-3.1-pro-high`/
`claude-opus-4-6-thinking` di langkah migrasi hanya relevan untuk project
yang benar-benar memakai overlay two-bridge — verifikasi per-project sebelum
menerapkannya.

### Langkah (dijalankan di mesin lokal)

1. Pasang binary — **sudah selesai**: `agy-mcp` v2.6.1 di
   `/opt/homebrew/bin/agy-mcp`.
1b. Hook wake — **sudah selesai** (di atas), scope user/global.
1c. **Belum selesai** — registrasi MCP server-nya sendiri (file berbeda,
    `~/.claude.json`, bukan `settings.json`):
    ```bash
    claude mcp add antigravity_next agy-mcp --scope user
    ```
    lalu restart Claude Code sebelum lanjut ke uji klaim 1-3.
   ```bash
   brew install tphakala/tap/agy-mcp   # atau: go install github.com/tphakala/agy-mcp/v2@latest
   agy-mcp --version && which agy-mcp
   ```
2. Di project pilot (bukan repo ini), daftarkan sebagai server **kedua** —
   `.mcp.json` project itu:
   ```json
   {
     "mcpServers": {
       "antigravity_next": { "command": "agy-mcp" }
     }
   }
   ```
3. Plugin 0.3.0 belum ada, jadi hook wake dipasang manual dulu di
   `.claude/settings.json` project pilot — perhatikan matcher-nya memakai nama
   `antigravity_next`, bukan `agy` (upstream) atau `antigravity`:
   ```json
   {
     "hooks": {
       "PostToolUse": [
         {
           "matcher": "mcp__antigravity_next__agy_run(_sync)?",
           "hooks": [
             { "type": "command", "command": "agy-mcp hook-wait", "asyncRewake": true, "timeout": 3700 }
           ]
         }
       ]
     }
   }
   ```
4. Uji klaim 1: satu call `agy_run` dengan `mode: "plan"` + `model:
   gemini-3.8-flash-medium`, lalu `git status`.
5. Uji klaim 2: satu call `agy_run` Coder sungguhan (`mode: "accept-edits"`)
   untuk unit kerja nyata. Jangan polling — tunggu, lihat apakah dibangunkan.
6. Uji klaim 3: jalankan dua `agy_run` berurutan tanpa menunggu yang pertama
   (pakai framing QA lens `gemini-3.1-pro-high` dan Security lens
   `claude-opus-4-6-thinking` — sekalian menguji pin baru dari
   `docs/MIGRATION.md` langkah 5).

### Yang direkam di sini
| # | Klaim | Lulus? | Bukti / catatan |
|---|---|---|---|
| 1 | `mode: "plan"` read-only | **LULUS** | Diminta review README, agy-mcp mengembalikan plan/usulan tanpa menyentuh file — dikonfirmasi tidak ada perubahan tercatat |
| 2 | Hook wake berfungsi | **LULUS** | Dikonfirmasi pengguna, tanpa detail tambahan (tidak ada timing/observasi spesifik dicatat) |
| 3 | Job konkuren | **LULUS** | Dikonfirmasi pengguna, tanpa detail tambahan |
| — | Durasi call Coder via `agy-mcp` | — | Tidak dicatat — baseline Fase 0 juga belum diisi, jadi perbandingan kuantitatif belum bisa dibuat meski klaim kualitatif (tidak hang, wake bekerja) sudah terbukti |
| — | Ada call yang menggantung? | — | Tidak dilaporkan selama tiga uji |

### Gap list
| # | Gap | Severity | Catatan |
|---|-----|----------|---------|

### Kesimpulan
**LANJUT ke Fase 2.** Ketiga klaim README yang belum terverifikasi di awal
sesi ini — read-only via `mode: "plan"`, wake otomatis lewat hook (bukan
polling), dan job konkuren tanpa cross-talk — semuanya lulus uji nyata,
bukan cuma dugaan dari dokumentasi. Ini menutup keraguan yang sempat muncul
di tengah jalan (kekeliruan riset soal `hook-wait` tidak ada — lihat
"Pendekatan yang sudah dicoba & gagal" #4).

Yang **belum** tervalidasi dan tetap jadi utang sebelum rilis produksi
(Fase 3): perbandingan durasi kuantitatif terhadap `agy-bridge` (baseline
Fase 0 tidak pernah diisi), dan perilaku di bawah beban/paralelisme lebih
dari dua job sekaligus (three-bridge mode bisa memicu Coder + Analyzer +
Release Writer semua lewat server yang sama dalam satu sesi panjang).
Direkomendasikan: isi baseline itu retroaktif kalau memungkinkan, atau
jalankan satu unit kerja penuh (bukan cuma uji terisolasi) sebelum Fase 3
sebagai uji akhir.

---

## Pendekatan yang sudah dicoba & gagal
| # | Pendekatan | Kenapa gagal/ditolak | Tanggal |
|---|-----------|----------------------|---------|
| 1 | Naikkan `AGY_TIMEOUT_DELEGATE` + client timeout supaya ada margin | Ditolak pemilik repo: memperpanjang tunggu bukan solusi, cuma memindahkan ceiling. Berguna hanya sebagai alat diagnosis, bukan konfigurasi produksi | 2026-09-19 |
| 2 | Hipotesis: chain `adversarial_review` diam-diam jatuh ke `AGY_DEFAULT_MODEL` (= pin Coder), sehingga lens QA/Security selama ini mereview karya sendiri | **Terbantah** oleh output `agy models`: `gemini-3.1-pro-high` tersedia di akun ini, jadi picker mengambilnya. Independensi model two-bridge selama ini nyata | 2026-09-19 |
| 3 | Adopsi `agy-executor` sebagai pengganti bridge | Ditolak: 0 star, 7 commit, tanpa rilis, tanpa fallback/model chain. Risiko jadi maintainer tunggal proyek orang lain yang terbengkalai | 2026-09-19 |
| 4 | Kesimpulan awal: subcommand `hook-wait` tidak ada di `agy-mcp` v2.6.1 | **Kesalahan riset**, bukan fakta rilis — WebFetch salah meringkas 10 release notes terakhir. README mentah `main` mendokumentasikannya rinci; uji manual (`exit code 0`, bukan 127) dan akhirnya uji end-to-end (Unit 1 klaim #2) mengonfirmasi fiturnya nyata dan berfungsi | 2026-09-19 |

---

## Belum dikerjakan (lanjutan sesi berikutnya)
- [x] **Fase 2** — tulis ulang kontrak payload: tabel pemetaan 6 tool lama →
      `agy_run`, `follow_up(session_id)` → `conversation_id`, `mode: "plan"`
      wajib untuk Analyzer/Release Writer/lens, `json_schema` menggantikan
      `AGY_MAX_OUTPUT_CHARS`. Selesai di `SKILL.md`, `two-bridge.md`.
- [x] **Fase 2** — revisi `CLAUDE-two-bridge-overlay.md` "Why this is
      weaker": klaim *"same vendor family"* diganti — pin eksplisit bisa
      memberi independensi model asal dipilih beda keluarga, tapi risiko
      infrastruktur bersama (satu akun/CLI `agy`) tetap ada dan itu yang
      dijelaskan ulang sebagai kelemahan sisa.
- [x] **Fase 2** — bagian "Model exception" di `two-bridge.md` diganti
      "Model pins (two-bridge lenses)" dengan tabel pin eksplisit; chain
      `adversarial_review` tidak lagi direferensikan di mana pun.
- [x] **Fase 2 (bonus, tidak direncanakan semula)** — QA/Security lens
      sekarang dijelaskan berjalan **paralel** (backgrounded, concurrent
      `agy_run`), bukan sekuensial — closes gap nyata vs three-bridge mode,
      ditemukan berkat Uji 3 Fase 1 yang membuktikan job konkuren bekerja.
- [ ] **Fase 2.5 (belum dikerjakan)** — belum ada verifikasi bahwa isi
      SKILL.md/two-bridge.md/overlay hasil tulis ulang ini benar-benar
      dijalankan sebagai unit kerja nyata (baru diperiksa lewat pembacaan,
      bukan dipraktikkan). Rekomendasi: jalankan satu unit lengkap
      (Analyze→Coder→Review→QA lens+Security lens paralel→Release) di
      project pilot memakai instruksi baru ini persis apa adanya, sebelum
      Fase 3.
- [ ] **Fase 3** — flip default: `.mcp.json` → `agy-mcp`, `hooks.json` +=
      `PostToolUse` (matcher `mcp__antigravity__agy_run(_sync)?`), bump
      `plugin.json` **dan** `marketplace.json` ke 0.3.0, hapus baris "Status"
      di `docs/MIGRATION.md`.
- [ ] **Fase 3** — perbaiki disiplin version bump: commit `d61189d` memperbaiki
      pin 3.7→3.8 di main tapi `plugin.json` tidak ikut dinaikkan, jadi
      pengguna di cache 0.2.0 tidak pernah menerimanya.
- [ ] **Fase 4** — deprecation window: pertahankan instruksi `agy-bridge`
      sebagai jalur rollback beberapa minggu, lalu hapus.

---

## Arsip
Unit yang sudah SELESAI dan tidak lagi dirujuk oleh gap terbuka dipindahkan ke
`review-agy-mcp-migration-archive.md`, sisakan ringkasan satu baris di sini.
File ini dibaca ulang setiap awal sesi — jaga tetap ramping.
