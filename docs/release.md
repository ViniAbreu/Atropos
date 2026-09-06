# Release process

Publish only from a clean `main` branch with every dependent pull request integrated.

## Checklist

1. Update the version and release notes.
2. Verify the pinned DelphiAST submodule commit.
3. Run the complete quality gate.
4. Confirm DUnitX, builds, and smoke tests on Win32 and Win64.
5. Confirm coverage is above the required threshold.
6. Generate `Atropos-<version>-Win32.zip` and `Atropos-<version>-Win64.zip`.
7. Publish SHA-256 checksums.
8. Sign executables when a certificate is available.
9. Document changes, limitations, and compatibility.
10. Test the downloaded packages on a clean machine.

The current pipeline validates the code; automated publishing and signing are not implemented yet.
