# Branch protection

## Status: not applied yet

`main` is **not** protected on GitHub until the ruleset below is applied to the new `bylaaabs/baaar`.
The repository is public, so rulesets are available on the organisation's Free plan.

Until it is applied, the rules in `CONTRIBUTING.md` are the honour system. **They still apply.**

## How to turn it on

```
gh api -X POST repos/bylaaabs/baaar/rulesets --input .github/branch-ruleset.json
```

Verify with:

```
gh api repos/bylaaabs/baaar/rulesets -q '.[] | "\(.name): \(.enforcement)"'
```

## What the ruleset enforces

Applied to `refs/heads/main` and any future `refs/heads/release/*`:

| Rule | Effect |
|---|---|
| `pull_request` | No direct pushes. Review threads resolved before merge. Stale reviews dismissed on push |
| `non_fast_forward` | No force pushes |
| `deletion` | The branch cannot be deleted |

**Squash and merge commits are both allowed**, deliberately. `CONTRIBUTING.md` explains when to use
which. There is no `required_linear_history` rule: it forbids merge commits, which would make the
merge-commit half of that policy impossible.

## Zero required approvals, for now

baaar has one maintainer, and GitHub does not let you approve your own pull request. With
`required_approving_review_count: 1` nothing could ever merge, so the ruleset requires a pull request
but no approving review.

That does not relax the rule for agents: **nothing merges without the maintainer's explicit approval**,
given in the conversation where the merge happens. See `AGENTS.md`.

When a second person reviews baaar, raise the count to `1` and update the ruleset:

```
gh api repos/bylaaabs/baaar/rulesets -q '.[] | "\(.id) \(.name)"'
gh api -X PUT repos/bylaaabs/baaar/rulesets/<id> --input .github/branch-ruleset.json
```

## Until then

- **Never push directly to `main`.** Branch, pull request, merge
- **Never merge without the maintainer's explicit approval**
- **Never force push** to it
