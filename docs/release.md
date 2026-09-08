# Release process

Publish only from a clean `main` branch with every dependent pull request integrated. The release script refuses a dirty worktree or a DelphiAST checkout that differs from the gitlink recorded by the source commit.

## Checklist

1. Update release notes, limitations, and compatibility documentation.
2. From the clean release commit, run `scripts\build-release.ps1 -Version <version>`.
3. Run the complete quality gate and confirm DUnitX, builds, coverage, and smoke tests on Win32 and Win64.
4. Verify both ZIPs against `SHA256SUMS.txt`.
5. Test the packages on a clean machine.
6. Create and push the matching annotated tag `v<version>`; the release workflow rebuilds, revalidates, and publishes it.

## Reproducibility contract

The script generates `Atropos-<version>-Win32.zip`, `Atropos-<version>-Win64.zip`, and `SHA256SUMS.txt`. Each ZIP contains CLI and VCL executables, the license, documentation, and `release-manifest.json`. The manifest records its schema, semantic version, platform, source commit, pinned DelphiAST commit, RAD Studio version, normalized source timestamp, file sizes, and SHA-256 hashes.

Delphi writes build-time timestamps into the PE and resource headers. Before hashing, the script normalizes only those metadata timestamps to the source commit timestamp. ZIP entries use a fixed timestamp and stable path order. Two builds from the same commit, version, DelphiAST commit, and RAD Studio toolchain therefore produce identical package hashes.

The executables are currently unsigned. Authenticode signing and timestamping alter the binaries and are deliberately outside the reproducible artifact contract until a project certificate and a documented deterministic signing policy are available.

## Local command

```powershell
.\scripts\build-release.ps1 -Version 1.2.3 -BdsVersion 23.0
Get-Content .\artifacts\release\SHA256SUMS.txt
```

Manual workflow dispatch builds and validates downloadable workflow artifacts without publishing a GitHub release. Pushing a `vX.Y.Z` tag publishes only after the complete quality gate passes.
