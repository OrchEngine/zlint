//! ## What This Rule Does
//!
//! Flags control-flow nesting deeper than `max_depth` inside a function.
//! Off by default; enabled by `zlint.json`.

const zlint = @import("zlint");

const Rule = zlint.linter.rule.Rule;
const NodeWrapper = zlint.linter.rule.NodeWrapper;
const LinterContext = zlint.linter.lint_context;
const Ast = zlint.Semantic.Ast;

const MaxNesting = @This();

max_depth: u32 = 4,
allow_tests: bool = true,

pub const meta: Rule.Meta = .{
    .name = "max-nesting",
    .category = .style,
    .default = .off,
};

fn isControl(tag: Ast.Node.Tag) bool {
    return switch (tag) {
        .if_simple, .@"if", .while_simple, .while_cont, .@"while", .for_simple, .@"for", .@"switch", .switch_comma, .@"catch" => true,
        else => false,
    };
}

fn isElseIf(ast: *const Ast, parent: Ast.Node.Index, child: Ast.Node.Index) bool {
    const info = ast.fullIf(parent) orelse return false;
    const else_expr = info.ast.else_expr.unwrap() orelse return false;
    return else_expr == child;
}

fn nestingDepth(ctx: *LinterContext, fn_node: Ast.Node.Index) u32 {
    const ast = ctx.ast();
    const links = ctx.links();
    var max: u32 = 0;

    for (ast.nodes.items(.tag), 0..) |tag, raw| {
        if (!isControl(tag)) continue;
        const node: Ast.Node.Index = @fromBackingInt(@intCast(raw));

        // Only control nodes whose nearest function ancestor is this function.
        var belongs = false;
        var ancestor = links.getParent(node);
        while (ancestor) |parent| {
            if (parent == fn_node) {
                belongs = true;
                break;
            }
            if (ast.nodeTag(parent) == .fn_decl) break;
            ancestor = links.getParent(parent);
        }
        if (!belongs) continue;

        var depth: u32 = 1;
        var child = node;
        ancestor = links.getParent(node);
        while (ancestor) |parent| {
            if (parent == fn_node) break;
            const parent_tag = ast.nodeTag(parent);
            if (isControl(parent_tag)) {
                if (!(parent_tag == .@"if" and ast.nodeTag(child) == .@"if" and isElseIf(ast, parent, child))) {
                    depth += 1;
                }
            }
            child = parent;
            ancestor = links.getParent(parent);
        }
        if (depth > max) max = depth;
    }
    return max;
}

pub fn runOnNode(self: *const MaxNesting, wrapper: NodeWrapper, ctx: *LinterContext) void {
    if (wrapper.node.tag != .fn_decl) return;
    if (self.allow_tests and zlint.linter.ast_utils.isInTest(ctx, wrapper.idx)) return;

    const ast = ctx.ast();
    const depth = nestingDepth(ctx, wrapper.idx);
    if (depth <= self.max_depth) return;

    var buf: [1]Ast.Node.Index = undefined;
    const proto = ast.fullFnProto(&buf, wrapper.idx) orelse return;
    const name_tok = proto.name_token orelse wrapper.node.main_token;
    ctx.report(ctx.diagnosticf(
        "function `{s}` has control-flow nesting {d} (max {d})",
        .{ ast.tokenSlice(name_tok), depth, self.max_depth },
        .{ctx.spanT(name_tok)},
    ));
}

pub fn rule(self: *MaxNesting) Rule {
    return Rule.init(self);
}
