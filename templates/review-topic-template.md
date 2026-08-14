# Conversation State — <Topic>

Tanggal mulai: <date>
Repo: <repo name/path>
Scope: <what this covers, what's explicitly excluded/deferred and why>

## Delegation tally
Three-bridge mode (templates/CLAUDE.md):
Antigravity — Analyzer: <N> | Coder: <N> | Release Writer: <N> || Codex QA: <N> | Codex Security: <N>

Two-bridge mode (templates/CLAUDE-two-bridge.md) — use this line instead if
no Codex bridge is registered:
Antigravity — Analyzer: <N> | Coder: <N> | QA lens: <N> | Security lens: <N> | Release Writer: <N>

(Updated at every checkpoint. Roles are fixed per bridge/role — this tally is
for observability/cost tracking only, not for routing decisions. A QA or
Security count of 0 on a Standard or High-stakes unit marked SELESAI is not a
red flag, it is a gate violation — that unit goes back to step 4 and the skip
gets logged below. Analyzer/Release Writer legitimately stay 0 on units with
no doc input or no ship step yet, and a Trivial unit legitimately has zeroes
across the board. Delete whichever mode's line doesn't apply.)

## Konteks
<why this task exists, what the overall scope is>

---

## Status: <Unit N — Name> — SELESAI/IN PROGRESS

Tier: <Trivial / Standard / High-stakes — assigned at step 1, before
implementation. Trivial is the only tier that permits a direct edit.>

### Requirement summary
<cite exact doc/spec sections — future reader must be able to re-verify>

### Implementasi aktual
<what exists in code, with file:line or module references>

### Bukti (step 3 checks)
| Check | Hasil |
|---|---|
| Scope: `git diff --name-only` vs plan Touch list | <match / files outside list + accepted reason> |
| Acceptance command re-run by Claude Code | `<command>` → exit `<code>` |
| Coder attempts on this plan | <1 or 2 — at 2 rejections the plan goes back to step 1, not a third round> |

### Delegasi (jika ada)
<role: Analyzer / Coder / Release Writer (semua antigravity, tapi session
terpisah per role — jangan follow_up lintas role); lalu, three-bridge mode:
QA (codex-qa) / Security (codex-security), threadId per server (tidak bisa
ditukar); two-bridge mode: QA lens / Security lens (keduanya antigravity
adversarial_review, session terpisah, jangan follow_up satu ke lainnya);
hasil singkat — tandai setiap klaim VERIFIED (sitasi file:line sudah
di-spot-check) atau UNVERIFIED. Untuk hasil "clean pass" tanpa temuan:
VERIFIED hanya jika ada coverage statement (file/fungsi yang diperiksa,
dipetakan ke acceptance criteria) dan daftar itu cocok dengan file yang
memang tersentuh diff — tanpa itu, UNVERIFIED.>

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
