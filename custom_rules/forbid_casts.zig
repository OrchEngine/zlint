//! ## What This Rule Does
//!
//! Flags raw pointer casts. The project should route type-erased vtable
//! contexts through one audited `fromOpaque` helper. Off by default; enabled by
//! `zlint.json`.

const std = @import("std");
const zlint = @import("zlint");

const Rule = zlint.linter.rule.Rule;
const NodeWrapper = zlint.linter.rule.NodeWrapper;
const LinterContext = zlint.linter.lint_context;

const ForbidCasts = @This();

allow_tests: bool = true,
allow_paths: []const []const u8 = &[_][]const u8{},

pub const meta: Rule.Meta = .{
    .name = "forbid-casts",
    .category = .restriction,
    .default = .off,
};

fn isBuiltinCall(tag: zlint.Semantic.Ast.Node.Tag) bool {
    return switch (tag) {
        .builtin_call, .builtin_call_comma, .builtin_call_two, .builtin_call_two_comma => true,
        else => false,
    };
}

fn banned(name: []const u8) bool {
    return std.mem.eql(u8, name, "@ptrCast") or
        std.mem.eql(u8, name, "@alignCast") or
        std.mem.eql(u8, name, "@constCast") or
        std.mem.eql(u8, name, "@intFromPtr") or
        std.mem.eql(u8, name, "@ptrFromInt");
}

pub fn runOnNode(self: *const ForbidCasts, wrapper: NodeWrapper, ctx: *LinterContext) void {
    if (!isBuiltinCall(wrapper.node.tag)) return;
    if (self.allow_tests and zlint.linter.ast_utils.isInTest(ctx, wrapper.idx)) return;

    const pathname = ctx.source.pathname orelse "";
    for (self.allow_paths) |allowed| {
        if (std.mem.endsWith(u8, pathname, allowed)) return;
    }

    const ast = ctx.ast();
    const name = ast.tokenSlice(wrapper.node.main_token);
    if (!banned(name)) return;

    ctx.report(ctx.diagnosticf(
        "raw `{s}` is not allowed outside the audited opaque-cast helper",
        .{name},
        .{ctx.spanT(wrapper.node.main_token)},
    ));
}

pub fn rule(self: *ForbidCasts) Rule {
    return Rule.init(self);
}
