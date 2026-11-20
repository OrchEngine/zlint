//! ## What This Rule Does
//! Enforces the canonical aliases for `std.mem` and `std.mem.Allocator`.
//!
//! Files that use `std.mem` should import it as `mem` and reference the alias
//! instead of spelling out `std.mem` at every call site. Files that use
//! `std.mem.Allocator` should import it as `Allocator`, derived from the `mem`
//! alias.
//!
//! The canonical header is:
//! ```zig
//! const std = @import("std");
//! const mem = std.mem;
//! const Allocator = mem.Allocator;
//! ```
//!
//! The alias declarations themselves are not reported. References to a
//! different `mem` namespace (for example a struct field or parameter named
//! `mem`) are ignored.
//!
//! ## Examples
//!
//! Examples of **incorrect** code for this rule:
//! ```zig
//! const std = @import("std");
//!
//! fn eql(a: []const u8, b: []const u8) bool {
//!   return std.mem.eql(u8, a, b);
//! }
//!
//! fn allocatorCopy(allocator: std.mem.Allocator) ![]u8 {
//!   return allocator.dupe(u8, "x");
//! }
//! ```
//!
//! ```zig
//! const std = @import("std");
//! const mem = std.mem;
//! const Allocator = mem.Allocator;
//!
//! fn allocatorCopy(allocator: mem.Allocator) ![]u8 {
//!   return allocator.dupe(u8, "x");
//! }
//! ```
//!
//! Examples of **correct** code for this rule:
//! ```zig
//! const std = @import("std");
//! const mem = std.mem;
//! const Allocator = mem.Allocator;
//!
//! fn eql(a: []const u8, b: []const u8) bool {
//!   return mem.eql(u8, a, b);
//! }
//!
//! fn allocatorCopy(allocator: Allocator) ![]u8 {
//!   return allocator.dupe(u8, "x");
//! }
//! ```

const std = @import("std");
const util = @import("util");
const Semantic = @import("../../Semantic.zig");
const ast_utils = @import("../ast_utils.zig");
const _rule = @import("../rule.zig");
const _fix = @import("../fix.zig");
const _span = @import("../../span.zig");
const Error = @import("../../Error.zig");

const Ast = Semantic.Ast;
const Node = Ast.Node;
const TokenIndex = Ast.TokenIndex;
const LinterContext = @import("../lint_context.zig");
const Rule = _rule.Rule;
const NodeWrapper = _rule.NodeWrapper;
const Fix = _fix.Fix;
const Span = _span.Span;
const LabeledSpan = _span.LabeledSpan;
const Cow = util.Cow(false);

const StdAliases = @This();
pub const meta: Rule.Meta = .{
    .name = "std-aliases",
    .category = .style,
    .default = .off,
    .fix = Fix.Meta.safe_fix,
};

const AliasFix = struct {
    span: Span,
    kind: Kind,
    member: []const u8 = "",

    const Kind = enum {
        mem_namespace,
        mem_member,
        allocator,
    };
};

const Chain = struct {
    /// The original chain node.
    node: Node.Index,
    /// The left-most identifier node.
    leftmost: Node.Index,
    /// Identifiers in source order.
    segments: [8][]const u8 = undefined,
    /// Token of each identifier in `segments`.
    tokens: [8]TokenIndex = undefined,
    len: usize = 0,

    fn startsWith(self: Chain, prefix: []const u8) bool {
        return self.len > 0 and std.mem.eql(u8, self.segments[0], prefix);
    }
};

/// Split a field access chain into its identifiers.
///
/// `foo.bar.baz` -> `{ "foo", "bar", "baz" }`
fn getChain(ctx: *LinterContext, node: Node.Index) ?Chain {
    const ast = ctx.ast();
    var chain: Chain = .{ .node = node, .leftmost = .root };
    var curr = node;

    while (true) {
        switch (ast.nodeTag(curr)) {
            .field_access => {
                if (chain.len == chain.segments.len) return null;
                const data = ast.nodeData(curr).node_and_token;
                const token: TokenIndex = data[1];
                chain.segments[chain.len] = ctx.semantic.tokenSlice(token);
                chain.tokens[chain.len] = token;
                chain.len += 1;
                curr = data[0];
            },
            .identifier => {
                if (chain.len == chain.segments.len) return null;
                const token = ast.nodeMainToken(curr);
                chain.segments[chain.len] = ctx.semantic.tokenSlice(token);
                chain.tokens[chain.len] = token;
                chain.len += 1;
                chain.leftmost = curr;
                break;
            },
            else => return null,
        }
    }

    std.mem.reverse([]const u8, chain.segments[0..chain.len]);
    std.mem.reverse(TokenIndex, chain.tokens[0..chain.len]);
    return chain;
}

/// Check whether `node` is the initializer of a declaration named `name`.
///
/// This exempts `const mem = std.mem;` and `const Allocator = mem.Allocator;`.
fn isDeclInit(ctx: *LinterContext, node: Node.Index, name: []const u8) bool {
    var parents = ctx.links().iterParentIds(node);
    while (parents.next()) |parent| {
        if (parent == node) continue;

        const var_decl = ctx.ast().fullVarDecl(parent) orelse continue;
        const init = var_decl.ast.init_node.unwrap() orelse continue;
        if (init != node) continue;

        const name_token = var_decl.ast.mut_token + 1;
        return std.mem.eql(u8, name, ctx.semantic.tokenSlice(name_token));
    }
    return false;
}

/// Check for a top-level alias declaration whose initializer is exactly
/// `expected`.
fn hasTopLevelAlias(ctx: *LinterContext, name: []const u8, expected: []const u8) bool {
    const ast = ctx.ast();
    for (ast.rootDecls()) |decl| {
        const var_decl = ast.fullVarDecl(decl) orelse continue;
        const name_token = var_decl.ast.mut_token + 1;
        if (!std.mem.eql(u8, name, ctx.semantic.tokenSlice(name_token))) continue;

        const init = var_decl.ast.init_node.unwrap() orelse continue;
        if (std.mem.eql(u8, expected, ast.getNodeSource(init))) return true;
    }
    return false;
}

fn hasMemAlias(ctx: *LinterContext) bool {
    return hasTopLevelAlias(ctx, "mem", "std.mem");
}

fn hasAllocatorAlias(ctx: *LinterContext) bool {
    return hasTopLevelAlias(ctx, "Allocator", "mem.Allocator") or
        hasTopLevelAlias(ctx, "Allocator", "std.mem.Allocator");
}

/// Does the chain's left-most identifier resolve to `std.mem`?
fn resolvesToStdMem(ctx: *LinterContext, chain: Chain) bool {
    const init = ast_utils.resolveConstAlias(ctx, chain.leftmost) orelse return false;
    return std.mem.eql(u8, "std.mem", ctx.ast().getNodeSource(init));
}

fn chainSpan(ctx: *LinterContext, chain: Chain) Span {
    const first = ctx.semantic.tokenSpan(chain.tokens[0]);
    const last = ctx.semantic.tokenSpan(chain.tokens[chain.len - 1]);
    return Span.new(first.start, last.end);
}

fn memDiagnostic(ctx: *LinterContext, chain: Chain) Error {
    const member = chain.segments[2];
    var e = ctx.diagnosticf(
        "Use the `mem` alias instead of `std.mem.{s}`.",
        .{member},
        .{LabeledSpan.labeled(chainSpan(ctx, chain), Cow.static("use the `mem` alias"))},
    );
    e.help = Cow.static("Declare `const mem = std.mem;` and reference `mem` instead of `std.mem`.");
    return e;
}

fn memNamespaceDiagnostic(ctx: *LinterContext, chain: Chain) Error {
    var e = ctx.diagnostic(
        "Use the `mem` alias instead of `std.mem`.",
        .{LabeledSpan.labeled(chainSpan(ctx, chain), Cow.static("use the `mem` alias"))},
    );
    e.help = Cow.static("Declare `const mem = std.mem;` and reference `mem` instead of `std.mem`.");
    return e;
}

fn allocatorDiagnostic(ctx: *LinterContext, chain: Chain) Error {
    var e = ctx.diagnosticf(
        "Use the `Allocator` alias instead of `{s}`.",
        .{ctx.ast().getNodeSource(chain.node)},
        .{LabeledSpan.labeled(chainSpan(ctx, chain), Cow.static("use the `Allocator` alias"))},
    );
    e.help = Cow.static("Declare `const Allocator = mem.Allocator;` and use `Allocator` instead.");
    return e;
}

fn replaceAlias(fix: AliasFix, builder: Fix.Builder) !Fix {
    return switch (fix.kind) {
        .mem_namespace => builder.replace(fix.span, Cow.static("mem")),
        .mem_member => builder.replacef(fix.span, "mem.{s}", .{fix.member}),
        .allocator => builder.replace(fix.span, Cow.static("Allocator")),
    };
}

pub fn runOnNode(_: *const StdAliases, wrapper: NodeWrapper, ctx: *LinterContext) void {
    const node = wrapper.idx;
    if (ctx.ast().nodeTag(node) != .field_access) return;
    // Only inspect the outermost field access in a chain.
    if (ctx.links().getParent(node)) |parent| {
        if (ctx.ast().nodeTag(parent) == .field_access and
            ctx.ast().nodeData(parent).node_and_token[0] == node)
        {
            return;
        }
    }

    const chain = getChain(ctx, node) orelse return;

    // `std.mem` used as a value, outside of `const mem = std.mem;`.
    if (chain.startsWith("std") and chain.len == 2 and
        std.mem.eql(u8, chain.segments[1], "mem") and
        !isDeclInit(ctx, node, "mem"))
    {
        reportMemNamespace(ctx, chain, if (hasMemAlias(ctx))
            .{ .span = chainSpan(ctx, chain), .kind = .mem_namespace }
        else
            null);
        return;
    }

    // `std.mem.<member>`
    if (chain.startsWith("std") and chain.len >= 3 and std.mem.eql(u8, chain.segments[1], "mem")) {
        if (chain.len == 3 and std.mem.eql(u8, chain.segments[2], "Allocator")) {
            // `const Allocator = std.mem.Allocator;` must become
            // `const Allocator = mem.Allocator;`, not a self-reference.
            const fix: ?AliasFix = if (isDeclInit(ctx, node, "Allocator"))
                (if (hasMemAlias(ctx))
                    .{ .span = chainSpan(ctx, chain), .kind = .mem_member, .member = "Allocator" }
                else
                    null)
            else if (hasAllocatorAlias(ctx))
                .{ .span = chainSpan(ctx, chain), .kind = .allocator }
            else
                null;
            reportAllocator(ctx, chain, fix);
            return;
        }

        if (chain.len == 3) {
            const fix: ?AliasFix = if (hasMemAlias(ctx))
                .{ .span = chainSpan(ctx, chain), .kind = .mem_member, .member = chain.segments[2] }
            else
                null;
            reportMem(ctx, chain, fix);
        }
        return;
    }

    // `mem.Allocator`, but only when `mem` resolves to `std.mem`.
    if (chain.len == 2 and chain.startsWith("mem") and
        std.mem.eql(u8, chain.segments[1], "Allocator") and
        !isDeclInit(ctx, node, "Allocator") and
        resolvesToStdMem(ctx, chain))
    {
        const fix: ?AliasFix = if (hasAllocatorAlias(ctx))
            .{ .span = chainSpan(ctx, chain), .kind = .allocator }
        else
            null;
        reportAllocator(ctx, chain, fix);
    }
}

fn reportMemNamespace(ctx: *LinterContext, chain: Chain, fix: ?AliasFix) void {
    const diagnostic = memNamespaceDiagnostic(ctx, chain);
    if (fix) |f| {
        ctx.reportWithFix(f, diagnostic, &replaceAlias);
    } else {
        ctx.report(diagnostic);
    }
}

fn reportMem(ctx: *LinterContext, chain: Chain, fix: ?AliasFix) void {
    const diagnostic = memDiagnostic(ctx, chain);
    if (fix) |f| {
        ctx.reportWithFix(f, diagnostic, &replaceAlias);
    } else {
        ctx.report(diagnostic);
    }
}

fn reportAllocator(ctx: *LinterContext, chain: Chain, fix: ?AliasFix) void {
    const diagnostic = allocatorDiagnostic(ctx, chain);
    if (fix) |f| {
        ctx.reportWithFix(f, diagnostic, &replaceAlias);
    } else {
        ctx.report(diagnostic);
    }
}

pub fn rule(self: *StdAliases) Rule {
    return Rule.init(self);
}

const RuleTester = @import("../tester.zig");
test StdAliases {
    const t = std.testing;

    var std_aliases = StdAliases{};
    var runner = RuleTester.init(t.allocator, std_aliases.rule());
    defer runner.deinit();

    const pass = &[_][:0]const u8{
        \\const std = @import("std");
        \\const mem = std.mem;
        \\const Allocator = mem.Allocator;
        \\fn eql(a: []const u8, b: []const u8) bool {
        \\    return mem.eql(u8, a, b);
        \\}
        \\fn allocatorCopy(allocator: Allocator) ![]u8 {
        \\    return allocator.dupe(u8, "x");
        \\}
        \\
        ,
        \\const std = @import("std");
        \\fn foo() void {
        \\    _ = std.testing;
        \\}
        \\
        ,
        \\const mem = struct {
        \\    const Allocator = u32;
        \\};
        \\fn foo(allocator: mem.Allocator) void { _ = allocator; }
        \\
        ,
        \\const std = @import("std");
        \\const mem = std.mem;
        \\const Allocator = mem.Allocator;
        \\fn foo(allocator: Allocator) void { _ = allocator; }
        \\
        ,
        \\fn foo(mem: struct { const Allocator = u32; }, allocator: mem.Allocator) void {
        \\    _ = allocator;
        \\}
        \\
        ,
    };

    const fail = &[_][:0]const u8{
        \\const std = @import("std");
        \\fn eql(a: []const u8, b: []const u8) bool {
        \\    return std.mem.eql(u8, a, b);
        \\}
        \\
        ,
        \\const std = @import("std");
        \\fn foo(allocator: std.mem.Allocator) void { _ = allocator; }
        \\
        ,
        \\const std = @import("std");
        \\const Allocator = std.mem.Allocator;
        \\fn foo(allocator: Allocator) void { _ = allocator; }
        \\
        ,
        \\const std = @import("std");
        \\const mem = std.mem;
        \\const Allocator = mem.Allocator;
        \\fn foo(allocator: mem.Allocator) void { _ = allocator; }
        \\
        ,
        \\const std = @import("std");
        \\const mem = std.mem;
        \\fn eql(a: []const u8, b: []const u8) bool {
        \\    return std.mem.eql(u8, a, b);
        \\}
        \\
        ,
        \\const std = @import("std");
        \\const memory = std.mem;
        \\
        ,
    };

    const fixes = &[_]RuleTester.FixCase{
        .{
            .src =
            \\const std = @import("std");
            \\const mem = std.mem;
            \\fn eql(a: []const u8, b: []const u8) bool {
            \\    return std.mem.eql(u8, a, b);
            \\}
            \\
            ,
            .expected =
            \\const std = @import("std");
            \\const mem = std.mem;
            \\fn eql(a: []const u8, b: []const u8) bool {
            \\    return mem.eql(u8, a, b);
            \\}
            \\
            ,
        },
        .{
            .src =
            \\const std = @import("std");
            \\const mem = std.mem;
            \\const Allocator = mem.Allocator;
            \\fn foo(allocator: std.mem.Allocator) void { _ = allocator; }
            \\
            ,
            .expected =
            \\const std = @import("std");
            \\const mem = std.mem;
            \\const Allocator = mem.Allocator;
            \\fn foo(allocator: Allocator) void { _ = allocator; }
            \\
            ,
        },
        .{
            .src =
            \\const std = @import("std");
            \\const mem = std.mem;
            \\const Allocator = mem.Allocator;
            \\fn foo(allocator: mem.Allocator) void { _ = allocator; }
            \\
            ,
            .expected =
            \\const std = @import("std");
            \\const mem = std.mem;
            \\const Allocator = mem.Allocator;
            \\fn foo(allocator: Allocator) void { _ = allocator; }
            \\
            ,
        },
        .{
            .src =
            \\const std = @import("std");
            \\const mem = std.mem;
            \\const memory = std.mem;
            \\
            ,
            .expected =
            \\const std = @import("std");
            \\const mem = std.mem;
            \\const memory = mem;
            \\
            ,
        },
    };

    try runner
        .withPass(pass)
        .withFail(fail)
        .withFix(fixes)
        .run();
}
