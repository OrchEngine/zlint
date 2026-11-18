//! ## What This Rule Does
//!
//! Reports mutual cycles between local types through declared field types.
//! Self-recursion (`next: ?*Node`) is ignored. Off by default.

const std = @import("std");
const zlint = @import("zlint");

const Rule = zlint.linter.rule.Rule;
const LinterContext = zlint.linter.lint_context;
const Ast = zlint.Semantic.Ast;

const MutualTypeCycles = @This();

pub const meta: Rule.Meta = .{
    .name = "mutual-type-cycles",
    .category = .suspicious,
    .default = .off,
};

const Type = struct {
    name: []const u8,
    token: Ast.TokenIndex,
    edges: std.ArrayList(u32) = .empty,
};

fn isContainer(tag: Ast.Node.Tag) bool {
    return switch (tag) {
        .container_decl, .container_decl_trailing, .container_decl_two, .container_decl_two_trailing, .container_decl_arg, .container_decl_arg_trailing => true,
        else => false,
    };
}

fn containsWord(haystack: []const u8, needle: []const u8) bool {
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, i, needle)) |at| {
        const before_ok = at == 0 or !std.ascii.isAlphanumeric(haystack[at - 1]) and haystack[at - 1] != '_';
        const end = at + needle.len;
        const after_ok = end == haystack.len or !std.ascii.isAlphanumeric(haystack[end]) and haystack[end] != '_';
        if (before_ok and after_ok) return true;
        i = at + 1;
    }
    return false;
}

fn findType(types: []const Type, name: []const u8) ?u32 {
    for (types, 0..) |t, i| {
        if (std.mem.eql(u8, t.name, name)) return @intCast(i);
    }
    return null;
}

pub fn runOnce(_: *const MutualTypeCycles, ctx: *LinterContext) void {
    const ast = ctx.ast();
    const source = ctx.source.text();
    var types: std.ArrayList(Type) = .empty;
    defer {
        for (types.items) |*t| t.edges.deinit(ctx.gpa);
        types.deinit(ctx.gpa);
    }

    // Collect named containers.
    var container_names: std.AutoHashMapUnmanaged(u32, []const u8) = .empty;
    defer container_names.deinit(ctx.gpa);
    for (ast.nodes.items(.tag), 0..) |tag, raw| {
        switch (tag) {
            .simple_var_decl, .global_var_decl, .local_var_decl, .aligned_var_decl => {},
            else => continue,
        }
        const node: Ast.Node.Index = @fromBackingInt(@intCast(raw));
        const vd = ast.fullVarDecl(node) orelse continue;
        const init = vd.ast.init_node.unwrap() orelse continue;
        if (!isContainer(ast.nodeTag(init))) continue;
        const name_tok = vd.ast.mut_token + 1;
        container_names.put(ctx.gpa, @backingInt(init), ast.tokenSlice(name_tok)) catch return;
    }

    for (ast.nodes.items(.tag), 0..) |tag, raw| {
        if (!isContainer(tag)) continue;
        const node: Ast.Node.Index = @fromBackingInt(@intCast(raw));
        const name = container_names.get(@backingInt(node)) orelse continue;
        types.append(ctx.gpa, .{ .name = name, .token = ast.nodeMainToken(node) }) catch return;
    }

    // Build field edges between local types.
    for (ast.nodes.items(.tag), 0..) |tag, raw| {
        switch (tag) {
            .container_field_init, .container_field_align, .container_field => {},
            else => continue,
        }
        const node: Ast.Node.Index = @fromBackingInt(@intCast(raw));
        const field = ast.fullContainerField(node) orelse continue;
        const type_expr = field.ast.type_expr.unwrap() orelse continue;
        const type_text = source[ctx.semantic.nodeSpan(type_expr).start..ctx.semantic.nodeSpan(type_expr).end];

        // Find the enclosing container by span.
        var owner: ?u32 = null;
        var best: u32 = std.math.maxInt(u32);
        for (ast.nodes.items(.tag), 0..) |other_tag, other_raw| {
            if (!isContainer(other_tag)) continue;
            const other: Ast.Node.Index = @fromBackingInt(@intCast(other_raw));
            const span = ctx.semantic.nodeSpan(other);
            const fspan = ctx.semantic.nodeSpan(node);
            if (fspan.start >= span.start and fspan.end <= span.end) {
                const width = span.end - span.start;
                if (width < best) {
                    best = width;
                    owner = @intCast(other_raw);
                }
            }
        }
        if (owner == null) continue;
        const owner_name = container_names.get(owner.?) orelse continue;
        const from = findType(types.items, owner_name) orelse continue;

        for (types.items, 0..) |target, target_idx| {
            if (target_idx == from) continue;
            if (!containsWord(type_text, target.name)) continue;
            types.items[from].edges.append(ctx.gpa, @intCast(target_idx)) catch return;
        }
    }

    // Report strongly connected components with at least two types.
    const n = types.items.len;
    const index = ctx.gpa.alloc(i32, n) catch return;
    defer ctx.gpa.free(index);
    const low = ctx.gpa.alloc(u32, n) catch return;
    defer ctx.gpa.free(low);
    const on_stack = ctx.gpa.alloc(bool, n) catch return;
    defer ctx.gpa.free(on_stack);
    var stack: std.ArrayList(u32) = .empty;
    defer stack.deinit(ctx.gpa);
    @memset(index, -1);
    @memset(on_stack, false);

    var next_index: u32 = 0;
    for (0..n) |i| {
        if (index[i] >= 0) continue;
        var frame = StrongConnect{
            .ctx = ctx,
            .types = types.items,
            .index = index,
            .low = low,
            .on_stack = on_stack,
            .stack = &stack,
            .next_index = &next_index,
        };
        frame.visit(@intCast(i)) catch return;
    }
}

const StrongConnect = struct {
    ctx: *LinterContext,
    types: []Type,
    index: []i32,
    low: []u32,
    on_stack: []bool,
    stack: *std.ArrayList(u32),
    next_index: *u32,

    fn visit(self: *StrongConnect, v: u32) !void {
        self.index[v] = @intCast(self.next_index.*);
        self.low[v] = self.next_index.*;
        self.next_index.* += 1;
        try self.stack.append(self.ctx.gpa, v);
        self.on_stack[v] = true;

        for (self.types[v].edges.items) |w| {
            if (self.index[w] < 0) {
                try self.visit(w);
                self.low[v] = @min(self.low[v], self.low[w]);
            } else if (self.on_stack[w]) {
                self.low[v] = @min(self.low[v], @as(u32, @intCast(self.index[w])));
            }
        }

        if (self.low[v] == @as(u32, @intCast(self.index[v]))) {
            var component: std.ArrayList(u32) = .empty;
            defer component.deinit(self.ctx.gpa);
            while (true) {
                const w = self.stack.pop().?;
                self.on_stack[w] = false;
                try component.append(self.ctx.gpa, w);
                if (w == v) break;
            }
            if (component.items.len > 1) {
                for (component.items) |idx| {
                    self.ctx.report(self.ctx.diagnosticf(
                        "type `{s}` is part of a mutual field-type cycle",
                        .{self.types[idx].name},
                        .{self.ctx.spanT(self.types[idx].token)},
                    ));
                }
            }
        }
    }
};

pub fn rule(self: *MutualTypeCycles) Rule {
    return Rule.init(self);
}
