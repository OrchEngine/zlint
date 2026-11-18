//! ## What This Rule Does
//!
//! Reports production files larger than `max_lines` non-blank, non-comment
//! lines outside `test` blocks. Advisory; off by default.

const std = @import("std");
const zlint = @import("zlint");

const Rule = zlint.linter.rule.Rule;
const LinterContext = zlint.linter.lint_context;
const Ast = zlint.Semantic.Ast;

const ProductionFileSize = @This();

max_lines: u32 = 500,

pub const meta: Rule.Meta = .{
    .name = "production-file-size",
    .category = .style,
    .default = .off,
};

pub fn runOnce(self: *const ProductionFileSize, ctx: *LinterContext) void {
    const ast = ctx.ast();
    const source = ctx.source.text();

    var test_ranges: std.ArrayList(struct { start: u32, end: u32 }) = .empty;
    defer test_ranges.deinit(ctx.gpa);
    for (ast.nodes.items(.tag), 0..) |tag, raw| {
        if (tag != .test_decl) continue;
        const node: Ast.Node.Index = @fromBackingInt(@intCast(raw));
        const span = ctx.semantic.nodeSpan(node);
        test_ranges.append(ctx.gpa, .{ .start = span.start, .end = span.end }) catch return;
    }

    var prod_lines: u32 = 0;
    var offset: u32 = 0;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const line_start = offset;
        const line_end = offset + @as(u32, @intCast(line.len));
        offset = line_end + 1;

        var in_test = false;
        for (test_ranges.items) |range| {
            if (line_start >= range.start and line_start < range.end) {
                in_test = true;
                break;
            }
        }
        if (in_test) continue;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (std.mem.startsWith(u8, trimmed, "//")) continue;
        prod_lines += 1;
    }

    if (prod_lines <= self.max_lines) return;
    ctx.report(ctx.diagnosticf(
        "production file has {d} lines (max {d})",
        .{ prod_lines, self.max_lines },
        .{ctx.spanT(0)},
    ));
}

pub fn rule(self: *ProductionFileSize) Rule {
    return Rule.init(self);
}
