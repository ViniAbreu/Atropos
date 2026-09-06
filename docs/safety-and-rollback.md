# Safety, backups, and rollback

Each execution is handled as a transaction:

1. build the original project;
2. stop without changing source files if the baseline fails;
3. create one internal backup before each write;
4. apply the transformations;
5. build again;
6. commit and remove internal backups on success;
7. restore the files after a failure, cancellation, or exception.

Existing user-created `.bak` files are preserved. Rollback is not a replacement for Git or functional tests.

## Recommended practice

- keep the worktree clean and under version control;
- run one instance per project;
- review the diff and run the project's tests;
- create an external backup when version control is unavailable.

AutoBuild uses `bds.exe`. Child processes are assigned to a Windows Job Object so they can be terminated together; the default timeout is 10 minutes.

## Legacy script

The root-level `clean_and_move_uses.ps1` is not part of the safe workflow. It recursively deletes `.bak` files and changes source files without the same verification and rollback guarantees. Do not use it in production.
