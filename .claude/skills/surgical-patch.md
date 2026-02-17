---
name: surgical-patch
description: Executing minimal, focused code changes.
applies_to:
  - all
triggers:
  - keyword: "patch"
  - keyword: "minimal"
  - keyword: "surgical"
---

# Surgical Patch Protocol

When applying changes, modify ONLY the necessary lines. Avoid large-scale rewrites or refactoring unless explicitly requested.

## Protocol

1.  **Locate**: Use `grep` or `find` (via shell) to pinpoint the exact location of the change.
2.  **Verify Context**: Ensure you understand the surrounding code logic.
3.  **Apply Change**: Make the smallest possible edit that satisfies the requirement.
4.  **Confirm**: Check the diff to ensure no unrelated changes were introduced.

## Avoid
- Reformatting files (unless fixing lint errors).
- Changing variable names unrelated to the task.
- Adding unrelated comments.
