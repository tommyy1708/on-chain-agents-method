---
status: NEW
from: hub
needs: authorised — execute this shift
reply: to-hub/2026-01-05-digest-rework.md
---

# Rework: the legacy test asserts nothing

The review found this; the finding is transcribed here. **You are not being asked to agree
with the reviewer — you are being asked to make the named guarantee true.**

## What is wanted

`never sends the digest twice` must fail when deduplication is removed.

**Done means:** deleting the deduplication turns that test red. Verify it by deleting it.

## How

1. Reproduce first: delete the deduplication, run the suite, confirm 815 green. **Do not
   fix anything until you have seen it green with the feature gone.**
2. Then either give the test a retry, or delete it and let the new tests own the guarantee.
   **If you delete it, say so plainly in the reply — a disappearing guarantee needs a
   sentence, not a silent removal.**
3. Re-run the knife. It must be red now.

## ⛔ Out of bounds

- Do not touch the deduplication itself. It was accepted; this is about the test.
- Do not rename anything else in the legacy suite.

## How it will be proven

The same knife, before and after: green before, **red after**, with the exact message.
