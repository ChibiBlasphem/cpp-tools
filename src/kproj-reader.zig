const std = @import("std");

pub const KProjConfig = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    output: []const u8,
    files: [][]const u8,
    standard: union(enum) {
        @"c++14": void,
        @"c++20": void,
    },

    fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator, .files = undefined, .output = undefined, .standard = undefined };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.output);
        self.allocator.free(self.files);
    }
};

const KProjSchema = union(enum) {
    output: void,
    files: void,
    standard: void,
};

fn allocSplit(comptime T: type, allocator: std.mem.Allocator, i: []const T, delimiter: []const T) ![][]const T {
    var al = std.ArrayList([]const T).init(allocator);
    var it = std.mem.split(T, i, delimiter);
    while (it.next()) |item| {
        try al.append(item);
    }
    return al.toOwnedSlice();
}

fn getValue(allocator: std.mem.Allocator, comptime T: type, input: []const u8) !T {
    const ti = @typeInfo(T);

    if (ti == .Union) {
        if (ti.Union.tag_type == null) {
            return error.UnsupportedType;
        }

        inline for (std.meta.fields(T)) |fd| {
            const trimmed_input = std.mem.trim(u8, input, " ");
            if (std.mem.eql(u8, fd.name, trimmed_input)) {
                return @unionInit(T, fd.name, {});
            }
        }

        return error.UnsupportedValueForUnion;
    }

    if (ti == .Pointer and ti.Pointer.size == .Slice) {
        if (ti.Pointer.child == u8) {
            return allocator.dupe(u8, input);
        }
        const ChildType = ti.Pointer.child;
        const child_ti = @typeInfo(ChildType);
        if (child_ti == .Pointer and child_ti.Pointer.size == .Slice and child_ti.Pointer.child == u8) {
            return allocSplit(u8, allocator, input, " ");
        }
    }

    return error.UnsupportedType;
}

pub fn parseKprojFile(allocator: std.mem.Allocator, contents: []const u8) !KProjConfig {
    var lines = std.mem.split(u8, contents, "\n");
    var kproj_config = KProjConfig.init(allocator);
    errdefer kproj_config.deinit();

    while (lines.next()) |line| {
        inline for (std.meta.fields(KProjSchema)) |fd| {
            var start_line: [fd.name.len + 1]u8 = undefined;
            _ = try std.fmt.bufPrint(&start_line, "{s}:", .{fd.name});
            if (std.mem.startsWith(u8, line, &start_line)) {
                const field_type = @TypeOf(@field(kproj_config, fd.name));
                @field(kproj_config, fd.name) = try getValue(allocator, field_type, line[fd.name.len + 2 ..]);
            }
        }
    }

    return kproj_config;
}

const testing = std.testing;
test "Should parse kproj file" {
    const contents = "output: main\nfiles: main.cpp";
    const kprojConfig = try parseKprojFile(std.testing.allocator, contents);
    defer kprojConfig.deinit();

    try testing.expectEqualSlices(u8, "main", kprojConfig.output);
    try testing.expectEqual(1, kprojConfig.files.len);
    try testing.expectEqualSlices(u8, "main.cpp", kprojConfig.files[0]);
}

test "Should parse kproj file with multiple files" {
    const contents = "output: main\nfiles: main.cpp add.cpp square.cpp";
    const kprojConfig = try parseKprojFile(std.testing.allocator, contents);
    defer kprojConfig.deinit();

    try testing.expectEqualSlices(u8, "main", kprojConfig.output);
    try testing.expectEqual(3, kprojConfig.files.len);
    try testing.expectEqualSlices(u8, "main.cpp", kprojConfig.files[0]);
    try testing.expectEqualSlices(u8, "add.cpp", kprojConfig.files[1]);
    try testing.expectEqualSlices(u8, "square.cpp", kprojConfig.files[2]);
}
