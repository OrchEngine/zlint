//! ## What This Rule Does
//!
//! Flags functions with more than `max_params` parameters. Off by default;
//! enabled by `zlint.json`.

const zlint = @import("zlint");

const Rule = zlint.linter.rule.Rule;
const NodeWrapper = zlint.linter.rule.NodeWrapper;
const LinterContext = zlint.linter.lint_context;

const MaxParams = @This();

max_params: u32 = 5,
allow_tests: bool = true,

pub const meta: Rule.Meta = .{
    .name = "max-params",
    .category = .style,
    .default = .off,
};

pub fn runOnNode(self: *const MaxParams, wrapper: NodeWrapper, ctx: *LinterContext) void {
    if (wrapper.node.tag != .fn_decl) return;
    if (self.allow_tests and zlint.linter.ast_utils.isInTest(ctx, wrapper.idx)) return;

    const ast = ctx.ast();
    var buf: [1]zlint.Semantic.Ast.Node.Index = undefined;
    const proto = ast.fullFnProto(&buf, wrapper.idx) orelse return;
    const name_tok = proto.name_token orelse wrapper.node.main_token;
    var count: u32 = 0;
    var it = proto.iterate(ast);
    while (it.next()) |_| count += 1;
    if (count <= self.max_params) return;

    ctx.report(ctx.diagnosticf(
        "function `{s}` has {d} parameters (max {d})",
        .{ ast.tokenSlice(name_tok), count, self.max_params },
        .{ctx.spanT(name_tok)},
    ));
}

pub fn rule(self: *MaxParams) Rule {
    return Rule.init(self);
}
