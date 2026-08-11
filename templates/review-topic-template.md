# Conversation State — <Topic>

Tanggal mulai: <date>
Repo: <repo name/path>
Scope: <what this covers, what's explicitly excluded/deferred and why>

## Delegation tally
Antigravity: <N> calls | Codex: <N> calls
(Updated at every checkpoint. Used only to break ties in the review/second-opinion swap zone — see "Balancing the swap zone" in templates/CLAUDE.md.)

## Konteks
<why this task exists, what the overall scope is>

---

## Status: <Unit N — Name> — SELESAI/IN PROGRESS

### Requirement summary
<cite exact doc/spec sections — future reader must be able to re-verify>

### Implementasi aktual
<what exists in code, with file:line or module references>

### Delegasi (jika ada)
<provider: Antigravity atau Codex; tool dipakai; session_id untuk Antigravity
follow_up atau threadId untuk Codex codex-reply; hasil singkat — tandai setiap
klaim VERIFIED (sitasi file:line sudah di-spot-check) atau UNVERIFIED>

### Gap list
| # | Gap | Severity | Catatan |
|---|-----|----------|---------|

### Kesimpulan
<verdict + concrete next step, not just a status word>

---

## Pendekatan yang sudah dicoba & gagal
| # | Pendekatan | Kenapa gagal/ditolak | Tanggal |
|---|-----------|----------------------|---------|

---

## Belum dikerjakan (lanjutan sesi berikutnya)
- [ ] <unit not yet started>
- [ ] <unit explicitly skipped, with reason>

---

## Arsip
Unit yang sudah SELESAI dan tidak lagi dirujuk oleh gap terbuka dipindahkan ke
`review-<topic>-archive.md`, sisakan ringkasan satu baris di sini. File ini
dibaca ulang setiap awal sesi — jaga tetap ramping.
