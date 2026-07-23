# Design — Claude Code sebagai Head Orchestrator untuk Antigravity

Tanggal: 2026-07-23

## Latar Belakang

Pain point awal: kerja sehari-hari dipecah antara Claude Code dan Antigravity,
harus pindah-pindah window/tools secara manual. Selain itu, di sesi kerja yang
panjang atau task besar, agent kehilangan konteks/keputusan yang sudah diambil
sebelumnya ("makin bodoh").

Tools yang sempat dievaluasi dan alasan tidak dipakai (untuk sekarang):

- **Hermes Agent** — orchestrator umum dengan memory persisten dan skill resmi
  untuk delegasi ke Claude Code. Tidak dipakai karena belum ada skill resmi ke
  Antigravity (masih feature request terbuka di repo), dan butuh infra 24/7
  (VPS/Docker) yang tidak dibutuhkan untuk kasus pemakaian saat ini.
- **9Router** — proxy API LLM (round-robin akun, fallback provider, hemat
  token). Solusi valid untuk masalah kuota/rate-limit, tapi itu masalah yang
  belum benar-benar dialami sekarang. Tidak termasuk dalam desain ini; jadi
  kandidat tambahan kalau nanti kena rate-limit nyata.
- **Kilo Code** — agent coding standalone (kompetitor Antigravity/Claude Code),
  bukan bridge. Menambahnya hanya menambah satu tool lagi untuk di-juggle,
  tidak menyelesaikan masalah apa pun di sini.
- **Bridge dua arah (Antigravity → Claude Code)** — ada di ekosistem MCP (mis.
  anderson-suga/claude-advisor) tapi ditolak karena Antigravity tidak bisa
  dijalankan di VS Code, jadi tidak ada skenario di mana user mulai kerja dari
  Antigravity. Dua arah juga membawa risiko ping-pong loop delegasi tanpa
  guard rail yang jelas.

## Keputusan Desain

**Satu head, satu arah delegasi:**

```
Claude Code (CLI atau VS Code extension)
        │  MCP call, satu arah
        ▼
Antigravity CLI (agy) — worker, jalan headless/tmux di background
        │
        ▼
hasil diverifikasi balik ke Claude Code
```

- Claude Code adalah satu-satunya entry point kerja sehari-hari, baik dari
  terminal maupun dari dalam VS Code (Claude Code punya extension resmi).
- Antigravity tidak dibuka manual sebagai IDE terpisah dalam alur normal;
  dia dipanggil sebagai worker lewat MCP bridge saat Claude Code menilai
  suatu task cocok didelegasikan (task berat, butuh Gemini, dsb).
- Bridge yang dipakai: salah satu dari MCP server yang sudah ada di
  ekosistem (mis. `antigravity-for-claude-code`, `agy-bridge`, atau
  `claude-to-agy`) — dipilih dan dievaluasi maturity-nya saat tahap
  implementasi, bukan bagian dari desain ini.
- Tidak ada delegasi balik dari Antigravity ke Claude Code. Ini menghindari
  risiko ping-pong loop dan cocok dengan kenyataan bahwa user selalu mulai
  kerja dari Claude Code.

## Manajemen Konteks Sesi Panjang

Masalah: context window Claude Code sendiri bisa di-auto-compact (lossy)
di tengah sesi panjang, sebelum sempat dicatat. Auto-compaction bawaan
harness bersifat generik dan tidak bisa diandalkan untuk menyimpan detail
task-specific (keputusan, pendekatan yang gagal, dsb).

**Solusi: progress file per topik/task**, mengikuti pola skill
`session-progress-notes`, dengan satu tambahan struktur:

- Section standar: Konteks, Status per unit kerja (requirement/hasil kerja,
  referensi file:line, gap list, kesimpulan), daftar "belum dikerjakan".
- **Tambahan wajib**: section **"Pendekatan yang sudah dicoba & gagal"** —
  mencatat apa yang sudah dicoba, kenapa gagal/ditolak, supaya sesi baru
  yang fresh tidak mengulang jalan buntu yang sama (termasuk buang-buang
  delegasi ke Antigravity untuk pendekatan yang sudah terbukti salah).

**Aturan checkpoint (kapan file di-update):**

- Setiap kali satu delegasi ke Antigravity selesai dan hasilnya diverifikasi.
- Setiap kali keputusan besar diambil (pilihan pendekatan, pembatalan arah).
- Bukan hanya di akhir sesi — supaya informasi tidak hilang duluan kalau
  context ke-compact di tengah jalan.

**Aturan baca (fresh session):**

- Sesi baru (atau setelah context di-compact) membaca progress file dulu,
  tidak mencoba menerka ulang dari riwayat mentah/transkrip lama.
- Klaim yang menyebut kode spesifik (file/fungsi) di-reverifikasi saat
  dipakai, karena kode bisa berubah sejak terakhir dicatat.
- Delegasi ke Antigravity via MCP secara natural sudah "fresh" per panggilan
  (tiap panggilan `agy --print` stateless) — konteks yang dibutuhkan harus
  disuntikkan eksplisit oleh Claude Code di setiap task envelope, bukan
  diasumsikan diingat dari panggilan sebelumnya.

## Di Luar Cakupan (Deferred)

- Hermes sebagai orchestrator 24/7 dengan memory sendiri — dipertimbangkan
  lagi jika muncul kebutuhan automation yang jalan tanpa user di depan
  laptop (mis. kontrol lewat Telegram/Discord).
- 9Router untuk round-robin akun/model — dipertimbangkan lagi jika rate
  limit/kuota API benar-benar jadi masalah nyata.
- Bridge dua arah Antigravity → Claude Code — dipertimbangkan lagi jika
  muncul skenario kerja yang benar-benar dimulai dari sisi Antigravity.

## Langkah Implementasi Berikutnya (di luar spec ini)

1. Evaluasi maturity 2-3 MCP bridge candidate (stars, last commit, issue
   terbuka) dan pilih satu.
2. Setup bridge tersebut di config MCP Claude Code (CLI + VS Code).
3. Tulis template progress file (extend `session-progress-notes` dengan
   section "Pendekatan yang sudah dicoba & gagal").
4. Tulis aturan checkpoint di atas sebagai instruksi project (mis. di
   CLAUDE.md project yang akan pakai setup ini).
