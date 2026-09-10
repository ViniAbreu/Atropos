# Safety, backups, and rollback

Each manifest save writes to a uniquely named temporary sibling file before atomic
replacement. Saves do not reuse the legacy `.atropos-transaction.json.tmp` path,
so a handle retained on that path cannot block creation of the next temporary
manifest. Cleanup only targets the temporary file allocated by that save. This
does not bypass a lock on the actual manifest or change transaction ownership.

Each execution is handled as a transaction:

1. build the original project;
2. stop without changing source files if the baseline fails;
3. record each file in a versioned transaction manifest and create one internal backup before each write;
4. apply the transformations;
5. build again;
6. commit and remove internal backups on success;
7. restore the files after a failure, cancellation, or exception.

When several interface dependencies move together, their original relative
order is preserved in the implementation clause. This matters when different
units export the same identifier and Delphi resolves it by uses-clause order.
Helper methods used in an implementation also retain access to receiver types
declared by interface method signatures, so dependencies such as
`System.SysUtils` are not removed from calls like `SmallInt.ToString`.
If the verification build fails, the report marks every listed transformation
as rolled back and retains the actual project, duration, unit, and search-path
counts for diagnosis.

Existing user-created `.bak` files are preserved. Rollback is not a replacement for Git or functional tests.

The analyzer records decisions per import section. Unknown providers and ambiguous
candidates are retained with reasons in the report. A parser exception preserves
the consumer and is reported as unknown analysis. Adapters can explicitly signal
incomplete analysis through a separate diagnostics port, which vetoes changes for
that consumer. Known direct lifecycle effects retain an import even when its source
belongs to the Delphi installation. Explicit import graphs propagate these effects
through dependencies and cycles. Unknown dependency metadata also preserves imports,
and diagnostics identify a dependency path. These safeguards do not yet provide
complete symbol binding, final compiler-context equivalence or all implicit effects.

Active includes are loaded with source provenance and SHA-256 hashes. A missing
include or an include cycle raises a parser error, preserving the consumer through
the same unknown-analysis path. Uses entries originating in includes veto consumer
edits because the current editor cannot safely address their original file. These
hashes also participate in the production parser's analysis snapshot.

The application collects every unit decision before applying any uses edit. Its
production parser records the exact bytes read from consumers, lazily resolved
providers and includes, then verifies all recorded hashes before applying the plan.
Different content observed in repeated reads invalidates the plan even if the file
is subsequently restored. A changed or deleted source aborts before the first write;
the existing exception/rollback path remains responsible for transaction recovery.
Dry-run consumes the same collected and validated plan. Cancellation is checked
during collection, before application and between applications.

This is a source consistency check, not filesystem locking. External changes after
the pre-application check remain a concurrency limitation. The default target workflow
also validates project/import file hashes and combines only actions supported by all
analyzed contexts. Compiler settings produced by tasks and source lookup directory
listings are not fully captured. Custom parsers without the optional snapshot port still get analysis
before writing, but do not provide the production adapter's byte validation.

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
