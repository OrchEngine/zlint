//! ## What This Rule Does
//!
//! Approximates cyclomatic complexity by counting decision keywords in a
//! function body. Off by default; enabled by `zlint.json`.

const std = @import("std");
const zlint = @import("zlint");

const Rule = zlint.linter.rule.Rule;
const NodeWrapper = zlint.linter.rule.NodeWrapper;
const LinterContext = zlint.linter.lint_context;

const MaxComplexity = @This();

max_complexity: u32 = 20,
allow_tests: bool = true,

pub const meta: Rule.Meta = .{
    .name = "max-complexity",
    .category = .style,
    .default = .off,
};

pub fn runOnNode(self: *const MaxComplexity, wrapper: NodeWrapper, ctx: *LinterContext) void {
    if (wrapper.node.tag != .fn_decl) return;
    if (self.allow_tests and zlint.linter.ast_utils.isInTest(ctx, wrapper.idx)) return;

    const ast = ctx.ast();
    const first = ast.firstToken(wrapper.idx);
    const last = ast.lastToken(wrapper.idx);
    var complexity: u32 = 1;
    var tok = first;
    while (tok <= last) : (tok += 1) {
        switch (ast.tokenTag(tok)) {
            .keyword_if, .keyword_while, .keyword_for, .keyword_switch, .keyword_catch, .keyword_orelse, .keyword_and, .keyword_or => complexity += 1,
            else => {},
        }
    }
    if (complexity <= self.max_complexity) return;

    var buf: [1]zlint.Semantic.Ast.Node.Index = undefined;
    const proto = ast.fullFnProto(&buf, wrapper.idx) orelse return;
    const name_tok = proto.name_token orelse wrapper.node.main_token;
    ctx.report(ctx.diagnosticf(
        "function `{s}` has cyclomatic complexity {d} (max {d})",
        .{ ast.tokenSlice(name_tok), complexity, self.max_complexity },
        .{ctx.spanT(name_tok)},
    ));
}

pub fn rule(self: *MaxComplexity) Rule {
    return Rule.init(self);
}
