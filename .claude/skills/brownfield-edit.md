---
name: brownfield-edit
description: Strategies for modifying existing legacy codebases safely.
applies_to:
  - all
triggers:
  - keyword: "refactor"
  - keyword: "fix"
  - keyword: "update"
  - keyword: "modify"
---

# Brownfield Code Modification Strategy

When modifying existing code, you must adhere to the principle of **Minimum Invasive Surgery**.

## Protocols

1.  **Respect the Legacy**: Do not rewrite code just because it looks "old" or "ugly". Only change what is necessary for the task.
2.  **Match the Style**: Use the same variable naming conventions (camelCase vs snake_case), indentation (tabs vs spaces), and comment style as the surrounding code.
3.  **Preserve Behavior**: Ensure that existing public interfaces remain compatible unless a breaking change is explicitly requested.
4.  **Test First**: Before making changes, run existing tests to establish a baseline. If no tests exist, create a reproduction test case for the bug or feature.

## Checklist

- [ ] Identified the scope of change (files, functions).
- [ ] Verified existing tests pass.
- [ ] Implemented the change (surgical).
- [ ] Added/Updated tests.
- [ ] Verified all tests pass.
