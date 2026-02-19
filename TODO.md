# TODO

## Now
- [todo] Verify Dropbox push/pull after recent renames
  Why: Confirm wrappers and renamed scripts still behave exactly as expected end-to-end.
  Notes: `./push.sh --dry-run`, `./pull.sh --dry-run`, then real runs with `--yes`.

- [todo] Decide final Dropbox remote path naming
  Why: Keep a single canonical path for long-term consistency (`/echolab_sync` currently).
  Notes: Check `dropbox.toml` (`default_sync_dir`, `sync_folder_name`) and README examples.

## Next
- [todo] Implement CPU state + single-step execution scaffold in `src/`.

- [todo] Add a memory bus abstraction layer and route machine memory accesses through it.

- [todo] Create deterministic trace-based tests for CPU/memory/video tick behavior.

- [todo] Model video VBlank edge semantics in the scan timing path.

- [todo] Add keyboard strobe/read-clear behavior tests matching hardware contracts.

- [todo] Emulate accurate CRT/power-down shutdown sequence
  Why: Match real shutdown artifacts with one unified physical model instead of isolated effects.
  Methods:
  - Power rail collapse dynamics
    Notes: B+, heater, and HV do not fall together; different time constants drive temporary deflection and gain shifts.
  - Sync/separator + oscillator unlock
    Notes: As signal amplitude drops, H/V PLLs lose lock intermittently, causing bar hopping, diagonal tearing, and re-lock bursts.
  - Deflection amplifier/yoke nonlinear response
    Notes: Under supply sag, vertical and horizontal stages compress differently (anisotropic collapse), with ringing and partial rebounds.
  - Blanking/beam current/AGC behavior
    Notes: Undervoltage shifts blanking thresholds and AGC, producing bright lines, noise bursts, and black-level pumping.
  - HV/flyback interaction with beam focus/size
    Notes: HV droop and flyback behavior alter spot size, bloom, and width/height coupling during collapse.

- [todo] Emulate the composite video signal path end-to-end
  Why: Model the same information and distortions a real display receives, not just post-decoder pixels.
  Notes: Include sync pulse generation, burst/chroma+luma encoding, line timing/jitter, bandwidth limits, noise/interference, and decode back into display-domain behavior.

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
