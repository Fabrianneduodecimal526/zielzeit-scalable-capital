---
name: release
description: Use when the user asks to cut, make, ship, or publish a new release of Zielzeit, or says "release" with no other object.
---

# Cutting a Zielzeit release

Run the script. Do not perform the steps by hand.

```sh
Scripts/release              # infer the version from the commits since the last tag
Scripts/release 1.4          # use this version
Scripts/release minor        # force the bump kind
Scripts/release --dry-run    # print the plan, change nothing
```

It bumps `Info.plist`, runs the tests, opens the version-bump PR (main is protected,
so a direct push is rejected), waits for CI, merges, tags, waits for the release
build, and then verifies the published release actually carries the `.dmg` and
`.zip` — v1.1 shipped with an empty asset list, so a green workflow is not the
check that matters.

## If it stops

Every exit is a real failure with the reason on stderr. Report it and stop; do not
proceed to the next step by hand, and do not re-run to get past a check.

- **`gh pr merge` is blocked by the permission classifier** — this is the one step
  that may need the user. Ask them to merge, then re-run; the script skips work
  already done.
- **Version inferred wrongly** — the history mixes conventional and plain subjects,
  so an unprefixed commit counts as a patch. Pass the version explicitly.
- **Tag pushed but no release** — the tag is not deleted automatically. Say so
  plainly; retagging is the user's call.
