//! ## What This Rule Does
//!
//! Reports private, container-level free functions with no semantic
//! references. Test references count as uses. Off by default.
//!
//! Methods are skipped because zlint does not yet resolve member calls.

const std = @import("std");
const zlint = @import("zlint");

const Rule = zlint.linter.rule.Rule;
const LinterContext = zlint.linter.lint_context;
const Semantic = zlint.Semantic;
const Symbol = Semantic.Symbol;

const UncalledPrivateFunction = @This();

allow_tests: bool = true,

pub const meta: Rule.Meta = .{
    .name = "uncalled-private-function",
    .category = .suspicious,
    .default = .off,
};

pub fn runOnSymbol(self: *const UncalledPrivateFunction, symbol: Symbol.Id, ctx: *LinterContext) void {
    _ = self;
    const symbols = ctx.symbols().symbols.slice();
    const s = symbol.int();

    const flags: Symbol.Flags = symbols.items(.flags)[s];
    if (!flags.s_fn or flags.s_export or flags.s_extern) return;
    if (symbols.items(.visibility)[s] != .private) return;

    // Only free functions at root scope; methods are unresolved by this
    // analyzer and would produce false positives.
    if (!symbols.items(.scope)[s].eql(.root)) return;

    const references = symbols.items(.references)[s].items;
    if (references.len != 0) return;

    const name = symbols.items(.name)[s];
    if (name.len == 0 or std.mem.eql(u8, name, "main")) return;

    const token = symbols.items(.token)[s].unwrap() orelse return;
    ctx.report(ctx.diagnosticf(
        "private function `{s}` has no references",
        .{name},
        .{ctx.spanT(token.int())},
    ));
}

pub fn rule(self: *UncalledPrivateFunction) Rule {
    return Rule.init(self);
}
