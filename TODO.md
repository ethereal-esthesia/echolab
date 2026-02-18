# TODO

## Now
- [todo] Verify Dropbox push/pull after recent renames
  Why: Confirm wrappers and renamed scripts still behave exactly as expected end-to-end.
  Notes: `./push.sh --dry-run`, `./pull.sh --dry-run`, then real runs with `--yes`.

- [todo] Decide final Dropbox remote path naming
  Why: Keep a single canonical path for long-term consistency (`/echolab_sync` currently).
  Notes: Check `dropbox.toml` (`default_sync_dir`, `sync_folder_name`) and README examples.

## Next
- [todo] Extract shared shell helpers into one file
  Why: Reduce duplication (`parse_toml`, token env resolution, timestamp parsing) across scripts.
  Notes: Candidate file: `tools/shell/dropbox_common.sh`.

- [todo] Tighten README Dropbox section
  Why: Keep setup/usage concise after multiple iterations.
  Notes: Focus on one happy-path push/pull example each.

## Later
- [todo] Consider stronger sync state model if needed
  Why: One-file timestamp model is simple, but may miss some edge cases when mtimes are preserved.
  Notes: Revisit only if false-skip/false-upload issues appear in real use.

- [todo] Add lightweight smoke script for workflow checks
  Why: Quick confidence before releases/large changes.
  Notes: Run `bash -n` for scripts + dry-run push/pull summary checks.
