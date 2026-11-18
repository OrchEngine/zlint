# zdepends fork milestones

This fork of [zlint](https://github.com/DonIsaac/zlint) adds project-specific
rules and the `zdepends` report binary. Upstream: `DonIsaac/zlint`, MIT.

## Status

- Fork: `OrchEngine/zlint`
- Integration branch: `zdepends`
- Zig toolchain: **0.17.1**
- Base: upstream `main` at `421c419`
- Includes `don/chore/zig-17` (`f09c7a33`)
- `zig build` succeeds.
- `zig build test` passes (unit tests).
- `zig build test-e2e` needs `zig-out/repos` fixtures and currently fails with
  “Could not find git repos to test”.

### Local patches currently required

- `chameleon` vendored under `vendor/chameleon`; `b.args` replaced with
  `addPassthruArgs()`.
- `smart_pointers` vendored under `vendor/smart_pointers`; `ptr.is_const`
  replaced with `ptr.attrs.@"const"`.
- `recover` vendored under `vendor/recover`; removed `@cImport` and uses an
  opaque `setjmp`/`longjmp` context.
- `sort-imports` uses `BufferFirstAllocator`.
- Suppression masks use `.empty` / `.full`.
- Removed the 0.16-era `errdefer |err|` test case.

## Milestones

### M0 — Fork bootstrap

- [x] Fork upstream zlint
- [x] Add as `orchengine-zig/tools/zlint` submodule
- [x] Create `zdepends` integration branch
- [x] Fetch upstream branches

### M1 — Zig 0.17.1 compatibility

- [x] Merge upstream `main` + `don/chore/zig-17`
- [x] Resolve disable-directive merge conflicts
- [x] Fix `**` string repetition in tests
- [x] Patch chameleon for 0.17
- [x] Patch smart_pointers for 0.17
- [x] Patch recover for 0.17
- [x] Patch `sort-imports` for `BufferFirstAllocator`
- [x] `zig build` passes
- [x] `zig build test` passes
- [ ] `zig build test-e2e` passes with repo fixtures
- [ ] Remove vendored patches once upstream supports 0.17

### M2 — Custom structural rules

- [x] `max-function-lines` (default off; project config enables)
- [x] `max-complexity`
- [x] `max-params`
- [x] `forbid-casts`
- [x] `max-nesting`
- [x] `production-file-size`
- [x] `max-file-imports`
- [x] `uncalled-private-function`
- [x] `mutual-type-cycles`
- [x] audited `src/opaque.zig` helper and project cast migration
- [ ] `import-cycles` (needs cross-file graph; keep in zdepends for now)
- [ ] `recursion` (needs cross-file call graph; keep in zdepends for now)
- [ ] full naming-convention rule (types, fields, files)
- [ ] rule tests for every custom rule
- [ ] docs generation for custom rules

### M3 — Project lint gate

- [x] `zlint.json` in `orchengine-zig`
- [x] Ignore submodule and generated files
- [x] Enable all zlint rules except `line-length`, `homeless-try`, `no-unresolved`
- [x] Custom rules enabled; production-file-size and max-file-imports are warnings
- [x] Replace `lint_rules.sh`
- [x] Fix all `sort-imports` findings (9)
- [x] Fix all `suppressed-errors` findings (6)
- [x] Fix all `unsafe-undefined` findings (3)
- [x] Fix casts via `src/opaque.zig`; 0 cast findings
- [x] Clear function-length, parameter, complexity findings
- [x] Remaining errors: 0
- [x] `make lint` passes with 6 advisory warnings (4 production-size, 2 max-file-imports)
- [ ] Resolve advisory production-size/fan-out warnings

### M4 — `zdepends` report binary

- [ ] Move report/debt/ownership modules into the fork
- [ ] Add `zdepends` executable to `build.zig`
- [ ] Share zlint AST/Semantic where practical
- [ ] `--lint` mode: no HTML/Graphviz/browser
- [ ] `--no-open` report mode
- [ ] Generated-file filtering in report
- [ ] Capability and field/ownership sections

### M5 — Rule registry, suppression, test scope

- [ ] Stable `ZD*` rule IDs
- [ ] Inline `// zigdepends-ignore ZDxxxx: reason`
- [ ] Config suppression with mandatory reason
- [ ] Visible Suppressed report section
- [ ] Parse `test_decl` ranges
- [ ] Production LOC excluding tests/test-only helpers
- [ ] Test calls used for liveness only
- [ ] `test_only` helper classification

### M6 — Additional zdepends rules

- [ ] `ZD1000` production file size > 500 LOC (advisory)
- [ ] `ZD1701` uncalled private function (debt)
- [ ] `ZD2000` naming conventions (debt)
- [ ] `ZD1409` mutual type cycles through fields (debt)
- [ ] `ZD1410` coupling (advisory + config denials)
- [ ] `ZD1401` import cycles suppressible

### M7 — Integration and CI

- [ ] Pin submodule commit
- [ ] Build zlint from submodule in CI
- [ ] Run `zlint --deny-warnings`
- [x] Remove `make lint-rules` from CI/Makefile
- [ ] Update AGENTS and code-style guide
- [ ] Keep `testaudit.sh` and `workflow_e2e.sh`
- [ ] `make verify` passes

## Notes

- `std.log.*` is allowed.
- `std.debug.print` / `std.debug.info` are forbidden debug output.
- Use one audited `fromOpaque` helper for `@ptrCast/@alignCast`; lint every
  other cast.
- Tests are invisible in metrics but must count for liveness.
- Generated files are parse boundaries, not metric participants.
