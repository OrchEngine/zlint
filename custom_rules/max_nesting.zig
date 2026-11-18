//! ## What This Rule Does
//!
//! Flags control-flow nesting deeper than `max_depth` inside a function.
//! Off by default; enabled by `zlint.json`.

const std = @import("std");
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

const Ctrl = struct {
    idx: Ast.Node.Index,
    start: u32,
    end: u32,
    depth: u32 = 0,
    is_if: bool,
};

fn isControl(tag: Ast.Node.Tag) bool {
    return switch (tag) {
        .if_simple, .@"if", .while_simple, .while_cont, .@"while", .for_simple, .@"for", .@"switch", .switch_comma, .@"catch" => true,
        else => false,
    };
}

fn lessBySize(_: void, a: Ctrl, b: Ctrl) bool {
    return (a.end - a.start) < (b.end - b.start);
}

fn isElseIf(ast: *const Ast, parent: Ast.Node.Index, child: Ast.Node.Index) bool {
    const info = ast.fullIf(parent) orelse return false;
    const else_expr = info.ast.else_expr.unwrap() orelse return false;
    return else_expr == child;
}

fn nestingDepth(ctx: *LinterContext, fn_node: Ast.Node.Index, fn_start: u32, fn_end: u32) u32 {
    const ast = ctx.ast();
    var controls: std.ArrayList(Ctrl) = .empty;
    defer controls.deinit(ctx.gpa);

    for (ast.nodes.items(.tag), 0..) |tag, raw| {
        if (!isControl(tag)) continue;
        const node: Ast.Node.Index = @fromBackingInt(@intCast(raw));
        const span = ctx.semantic.nodeSpan(node);
        if (span.start < fn_start or span.end > fn_end) continue;
        if (node == fn_node) continue;
        controls.append(ctx.gpa, .{
            .idx = node,
            .start = span.start,
            .end = span.end,
            .is_if = tag == .@"if" or tag == .if_simple,
        }) catch return 0;
    }

    std.mem.sort(Ctrl, controls.items, {}, lessBySize);
    var max: u32 = 0;
    for (controls.items, 0..) |*item, i| {
        var parent: ?*const Ctrl = null;
        for (controls.items[0..i]) |*candidate| {
            if (candidate.start <= item.start and candidate.end >= item.end) {
                if (parent == null or candidate.depth > parent.?.depth) parent = candidate;
            }
        }
        if (parent) |p| {
            if (item.is_if and p.is_if and isElseIf(ast, p.idx, item.idx)) {
                item.depth = p.depth;
            } else {
                item.depth = p.depth + 1;
            }
        } else {
            item.depth = 1;
        }
        if (item.depth > max) max = item.depth;
    }
    return max;
}

pub fn runOnNode(self: *const MaxNesting, wrapper: NodeWrapper, ctx: *LinterContext) void {
    if (wrapper.node.tag != .fn_decl) return;
    if (self.allow_tests and zlint.linter.ast_utils.isInTest(ctx, wrapper.idx)) return;

    const ast = ctx.ast();
    const span = ctx.semantic.nodeSpan(wrapper.idx);
    const depth = nestingDepth(ctx, wrapper.idx, span.start, span.end);
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
