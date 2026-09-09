# Safety, backups, and rollback

Each execution is handled as a transaction:

1. build the original project;
2. stop without changing source files if the baseline fails;
3. record each file in a versioned transaction manifest and create one internal backup before each write;
4. apply the transformations;
5. build again;
6. commit and remove internal backups on success;
7. restore the files after a failure, cancellation, or exception.

Existing user-created `.bak` files are preserved. Rollback is not a replacement for Git or functional tests.

Every transaction uses `.atropos-transaction.json` in the project directory. The manifest associates the original and backup paths with one transaction identifier and the SHA-256 hash of the original content. Recovery validates this relationship and the hash before restoring a file. A committed manifest only completes backup cleanup; it never rolls the accepted source changes back.

Manifest or hash validation failures stop recovery and preserve all available evidence. Backups created by older Atropos versions without a manifest are also preserved and require manual review; they are never restored automatically. After confirming the intended original file, restore or remove those legacy `.atropos-*.bak` files before starting a new analysis.

## Recommended practice

- keep the worktree clean and under version control;
- run one instance per project;
- review the diff and run the project's tests;
- create an external backup when version control is unavailable.

AutoBuild prefers headless MSBuild after an isolated preflight successfully compiles a minimal program with `dcc32.exe`. The preflight runs in a temporary directory and verifies the command-line environment, compiler executable, installed edition, and license without touching the analyzed project. If the compiler is absent or command-line compilation is rejected, Atropos falls back to `bds.exe`. A license-related rejection reported later by MSBuild also triggers the fallback. Project compilation errors do not, so the original MSBuild diagnostic remains visible without opening the IDE. Child processes are assigned to a Windows Job Object so they can be terminated together; the default timeout is 10 minutes.

## Legacy script

The root-level `clean_and_move_uses.ps1` is not part of the safe workflow. It recursively deletes `.bak` files and changes source files without the same verification and rollback guarantees. Do not use it in production.
