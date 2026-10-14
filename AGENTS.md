# Project coding rules

- Do not use assertions in production code. Assertions are appropriate in tests.
- Avoid pass-through wrappers and unnecessary abstraction. Call the underlying API directly unless a helper performs meaningful validation, transformation, or shared processing.
- Keep implementation helpers local to their consuming module. Expose shared helpers only when multiple modules need them.
- Reuse appropriate existing uevrUtils helpers. Name custom helpers clearly after the additional behavior they provide.
- Call plugin.executeFunction directly and check nil/error responses at each call site; do not wrap it in a shared call helper.
- In production code, handle expected failures with explicit return values and check them at each call site. Do not raise errors for runtime validation or rely on an outer protected call to catch failed validation.
