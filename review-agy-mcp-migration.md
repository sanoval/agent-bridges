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
| `agy --version` | <isi> |
| Duplikat `antigravity` di user scope? | <ya/tidak — jika ya, isi JSON-nya disimpan di mana> |
| Jumlah entri `antigravity` setelah dibersihkan | <isi — harus 1> |
| Durasi call Coder yang **berhasil**, kira-kira | <isi> |
| Dari ~5 delegasi terakhir, berapa yang kena ~600s | <isi> |

### Gap list
| # | Gap | Severity | Catatan |
|---|-----|----------|---------|

### Kesimpulan
<isi setelah dijalankan>

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

### Langkah (dijalankan di mesin lokal)

1. Pasang binary:
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
| 1 | `mode: "plan"` read-only | <isi> | <isi> |
| 2 | Hook wake berfungsi | <isi> | <isi> |
| 3 | Job konkuren | <isi> | <isi> |
| — | Durasi call Coder via `agy-mcp` | — | <isi — bandingkan dengan baseline Unit 0> |
| — | Ada call yang menggantung? | — | <isi> |

### Gap list
| # | Gap | Severity | Catatan |
|---|-----|----------|---------|

### Kesimpulan
<isi — verdict eksplisit: LANJUT ke Fase 2, atau BERHENTI + alasan>

---

## Pendekatan yang sudah dicoba & gagal
| # | Pendekatan | Kenapa gagal/ditolak | Tanggal |
|---|-----------|----------------------|---------|
| 1 | Naikkan `AGY_TIMEOUT_DELEGATE` + client timeout supaya ada margin | Ditolak pemilik repo: memperpanjang tunggu bukan solusi, cuma memindahkan ceiling. Berguna hanya sebagai alat diagnosis, bukan konfigurasi produksi | 2026-09-19 |
| 2 | Hipotesis: chain `adversarial_review` diam-diam jatuh ke `AGY_DEFAULT_MODEL` (= pin Coder), sehingga lens QA/Security selama ini mereview karya sendiri | **Terbantah** oleh output `agy models`: `gemini-3.1-pro-high` tersedia di akun ini, jadi picker mengambilnya. Independensi model two-bridge selama ini nyata | 2026-09-19 |
| 3 | Adopsi `agy-executor` sebagai pengganti bridge | Ditolak: 0 star, 7 commit, tanpa rilis, tanpa fallback/model chain. Risiko jadi maintainer tunggal proyek orang lain yang terbengkalai | 2026-09-19 |

---

## Belum dikerjakan (lanjutan sesi berikutnya)
- [ ] **Fase 2** — tulis ulang kontrak payload: tabel pemetaan 6 tool lama →
      `agy_run`, `follow_up(session_id)` → `conversation_id`, `mode: "plan"`
      wajib untuk Analyzer/Release Writer/lens, `json_schema` menggantikan
      `AGY_MAX_OUTPUT_CHARS`, fallback chain jadi retry eksplisit.
- [ ] **Fase 2** — revisi `CLAUDE-two-bridge-overlay.md:21-37`: klaim *"both
      lenses come from the same vendor's family"* tidak lagi benar setelah
      Security lens pindah ke `claude-opus-4-6-thinking`.
- [ ] **Fase 2** — hapus bagian "Model exception" di `two-bridge.md:19-26`;
      tidak ada lagi chain yang perlu dilindungi.
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
