# Conversation State — <Topic>

Tanggal mulai: <date>
Repo: <repo name/path>
Scope: <what this covers, what's explicitly excluded/deferred and why>

## Delegation tally
Three-bridge mode (templates/CLAUDE.md):
Antigravity — Analyzer: <N> | Coder: <N> | Release Writer: <N> || Codex QA: <N> | Codex Security: <N>

Two-bridge mode (templates/CLAUDE.md + templates/CLAUDE-two-bridge-overlay.md)
— use this line instead if no Codex bridge is registered:
Antigravity — Analyzer: <N> | Coder: <N> | QA lens: <N> | Security lens: <N> | Release Writer: <N>

(Updated at every checkpoint. Roles are fixed per bridge/role — this tally is
for observability/cost tracking only, not for routing decisions. A QA or
Security count of 0 on a unit marked SELESAI is a red flag: that role was
skipped. Analyzer/Release Writer legitimately stay 0 on units with no doc
input or no ship step yet. Delete whichever mode's line doesn't apply.)

## Konteks
<why this task exists, what the overall scope is>

---

## Status: <Unit N — Name> — SELESAI/IN PROGRESS

### Requirement summary
<cite exact doc/spec sections — future reader must be able to re-verify>

### Implementasi aktual
<what exists in code, with file:line or module references>

### Delegasi (jika ada)
<role: Analyzer / Coder / Release Writer (semua antigravity, tapi session
terpisah per role — jangan follow_up lintas role); lalu, three-bridge mode:
QA (codex-qa) / Security (codex-security), threadId per server (tidak bisa
ditukar); two-bridge mode: QA lens / Security lens (keduanya antigravity
adversarial_review, session terpisah, jangan follow_up satu ke lainnya);
hasil singkat — tandai setiap klaim VERIFIED (sitasi file:line sudah
di-spot-check) atau UNVERIFIED>

Referensi: skill `delegation-pipeline` dari plugin `agent-bridges` (semua
mode; lihat juga `two-bridge.md` di dalamnya untuk two-bridge mode).

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
