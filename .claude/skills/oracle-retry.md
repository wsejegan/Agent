---
name: oracle-retry
description: Strategy for analyzing and fixing validation failures.
applies_to:
  - all
triggers:
  - keyword: "retry"
  - keyword: "fail"
  - keyword: "error"
  - keyword: "test failed"
---

# Oracle Retry Protocol

When the Oracle verification fails, you must analyze the output and fix the code.

## Protocol

1.  **Analyze**: Read the failure message carefully. Identify the failing test or check.
2.  **Debug**: Use print statements or logging to understand the failure if necessary.
3.  **Fix**: Apply a minimal fix to resolve the failure.
4.  **Verify**: Run the verification again.

## Common Failures

- **Syntax Error**: Fix the syntax.
- **Logic Error**: Fix the logic.
- **Test Failure**: Update the test or fix the code.
- **Lint Error**: Fix the lint issue.
