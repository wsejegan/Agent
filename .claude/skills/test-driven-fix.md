---
name: test-driven-fix
description: Methodology for fixing bugs by first writing a reproduction test.
applies_to:
  - all
triggers:
  - keyword: "bug"
  - keyword: "error"
  - keyword: "fail"
  - keyword: "fix"
---

# Test-Driven Bug Fix Protocol

When fixing a reported bug, you MUST ensure that you reproduce it before fixing it.

## Steps

1.  **Reproduce**: Create a failing test case that demonstrates the bug.
2.  **Verify Failure**: Run the test to confirm it fails as expected.
3.  **Implement Fix**: Modify the code to resolve the issue.
4.  **Verify Pass**: Run the test again to confirm it passes.
5.  **Clean Up**: Check for any side effects or regressions.

## Checklist

- [ ] Analyze the bug report or error message.
- [ ] Create a new test file or add a new test case to an existing file.
- [ ] Run the test (ensure failure).
- [ ] Implement the fix.
- [ ] Run the test (ensure success).
