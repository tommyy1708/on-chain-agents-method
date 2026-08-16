---
status: NEW
from: <you>
re: to-<you>/YYYY-MM-DD-<slug>.md
scope: <one line: what was touched, what was not>
---

# <Title>

**Bottom line first**: <one sentence. Done / not done / done with a cost.>

## 1. What changed

<Item by item, **with locations**. An assertion without a location is not written down.>

## 2. Proof (artifacts)

| | |
|---|---|
| Checks / tests | <before → after> |
| Build | <result> |
| Branch / commit | <values> |
| Working tree | <clean?> |

### Mutation checks

| Knife | Result | Exact failure message |
|---|---|---|
| <break X> | 🔴 / 🟢 | <verbatim> |

**Every knife must be restored, and the restore proven clean.**

## 3. Not verified

<Say what you tried and why you could not get it. **Never present reasoning as measurement.**>

## 4. Found but not done

<Out of scope, or things you believe should change but should not change yourself. **Do not write "none" here when there is something.**>

## Guardrail self-check

<Answer each prohibition in the order, with the actual end state.>
