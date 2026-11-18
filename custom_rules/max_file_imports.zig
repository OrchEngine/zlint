//! ## What This Rule Does
//!
//! Reports files with more than `max_imports` local file imports. Advisory and
//! configurable; off by default.

const std = @import("std");
const zlint = @import("zlint");

const Rule = zlint.linter.rule.Rule;
const LinterContext = zlint.linter.lint_context;

const MaxFileImports = @This();

max_imports: u32 = 10,

pub const meta: Rule.Meta = .{
    .name = "max-file-imports",
    .category = .style,
    .default = .off,
};

pub fn runOnce(self: *const MaxFileImports, ctx: *LinterContext) void {
    var count: u32 = 0;
    var first_node: ?zlint.Semantic.Ast.Node.Index = null;
    for (ctx.semantic.modules.imports.items) |entry| {
        if (entry.kind != .file) continue;
        count += 1;
        if (first_node == null) first_node = entry.node;
    }
    if (count <= self.max_imports) return;
    const node = first_node orelse return;
    ctx.report(ctx.diagnosticf(
        "file has {d} local imports (max {d})",
        .{ count, self.max_imports },
        .{ctx.spanN(node)},
    ));
}

pub fn rule(self: *MaxFileImports) Rule {
    return Rule.init(self);
}
