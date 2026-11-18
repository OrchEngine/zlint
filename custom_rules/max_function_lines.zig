//! ## What This Rule Does
//!
//! Flags functions longer than `max_lines` source lines.
//!
//! This is a zdepends fork rule. It is off by default and enabled by the
//! project's `zlint.json`.

const std = @import("std");
const zlint = @import("zlint");

const Rule = zlint.linter.rule.Rule;
const NodeWrapper = zlint.linter.rule.NodeWrapper;
const LinterContext = zlint.linter.lint_context;

const MaxFunctionLines = @This();

max_lines: u32 = 60,
allow_tests: bool = true,

pub const meta: Rule.Meta = .{
    .name = "max-function-lines",
    .category = .style,
    .default = .off,
};

pub fn runOnNode(self: *const MaxFunctionLines, wrapper: NodeWrapper, ctx: *LinterContext) void {
    if (wrapper.node.tag != .fn_decl) return;
    if (self.allow_tests and zlint.linter.ast_utils.isInTest(ctx, wrapper.idx)) return;

    const ast = ctx.ast();
    const span = ctx.semantic.nodeSpan(wrapper.idx);
    const text = ctx.source.text()[span.start..span.end];
    const lines: u32 = @intCast(std.mem.countScalar(u8, text, '\n') + 1);
    if (lines <= self.max_lines) return;

    var buf: [1]zlint.Semantic.Ast.Node.Index = undefined;
    const proto = ast.fullFnProto(&buf, wrapper.idx) orelse return;
    const name_tok = proto.name_token orelse wrapper.node.main_token;
    ctx.report(ctx.diagnosticf(
        "function `{s}` is {d} lines long (max {d})",
        .{ ast.tokenSlice(name_tok), lines, self.max_lines },
        .{ctx.spanT(name_tok)},
    ));
}

pub fn rule(self: *MaxFunctionLines) Rule {
    return Rule.init(self);
}
