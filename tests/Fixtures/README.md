# Representative fixtures

`RepresentativeConsole` validates namespaces, `in` aliases, conditional directives, an unused unit, and preservation of `initialization`/`finalization` sections.

`RepresentativeVCL` validates a VCL project with a real DFM form and a removable dependency.

`RollbackConsole` forces a deterministic failure only during the second build and confirms that the modified source file is restored. The main console fixture also starts with a pending transactional backup to validate automatic recovery.

The projects do not depend on external commercial components. The gate copies each fixture to a temporary directory, runs Atropos, and confirms the build, report, expected transformation, and preservation of versioned files. Project groups, packages, and DLLs remain outside the declared scope.
