const std = @import("std");

// Parse args line to retrieve executable name, command, and positional params
// To do so:
//      - Get args
//      - Iterate over args and store them

pub fn ParsedArgs(comptime C: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        executable_name: ?[]const u8,
        command: C,
        args: [][]const u8,

        fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .executable_name = null,
                .command = undefined,
                .args = undefined,
            };
        }

        pub fn deinit(self: Self) void {
            if (self.executable_name) |ex| {
                self.allocator.free(ex);
            }
            self.allocator.free(self.args);
        }
    };
}

pub fn parseProcessArgs(allocator: std.mem.Allocator, comptime Commands: type) !ParsedArgs(Commands) {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const executable_name = args.next() orelse {
        return error.NoExecutableName;
    };

    var parsed_args = try parseArgs(allocator, &args, Commands);
    parsed_args.executable_name = try allocator.dupe(u8, executable_name);

    return parsed_args;
}

pub fn parseArgs(allocator: std.mem.Allocator, args: anytype, comptime Commands: type) !ParsedArgs(Commands) {
    var parsed_args = ParsedArgs(Commands).init(allocator);

    const command = args.next() orelse {
        return error.NoCommandSpecified;
    };
    var found = false;
    inline for (std.meta.fields(Commands)) |fd| {
        if (std.mem.eql(u8, fd.name, command)) {
            parsed_args.command = @unionInit(Commands, fd.name, {});
            found = true;
        }
    }
    if (!found) {
        return error.UnknownCommand;
    }

    var positional_args = std.ArrayList([]const u8).init(allocator);
    while (args.next()) |posArg| {
        try positional_args.append(posArg);
    }
    parsed_args.args = try positional_args.toOwnedSlice();

    return parsed_args;
}

const TestIt = struct {
    const Self = @This();

    seq: []const []const u8,
    index: usize,

    fn init(seq: []const []const u8) Self {
        return Self{ .seq = seq, .index = 0 };
    }

    fn next(self: *Self) ?[]const u8 {
        if (self.index >= self.seq.len) {
            return null;
        }
        const res = self.seq[self.index];
        self.index += 1;
        return res;
    }
};

const testing = std.testing;
test "parse valid command with args" {
    const TestCommands = union(enum) {
        foo: void,
        bar: void,
    };

    var args = &[_][]const u8{ "foo", "positional_arg1" };
    const pos_args = args[1..];
    var test_it = TestIt.init(args);

    const parsed_args = try parseArgs(std.testing.allocator, &test_it, TestCommands);
    defer parsed_args.deinit();

    try testing.expectEqual(@as(?[]const u8, null), parsed_args.executable_name);
    try testing.expectEqual(TestCommands.foo, parsed_args.command);
    for (parsed_args.args, pos_args) |arg, pos_arg| {
        try testing.expectEqualSlices(u8, pos_arg, arg);
    }
}

test "parse unknown command" {
    const TestCommands = union(enum) {
        foo: void,
        bar: void,
    };

    const args = &[_][]const u8{"baz"};
    var test_it = TestIt.init(args);

    const parsed_args = parseArgs(std.testing.allocator, &test_it, TestCommands);
    try testing.expectError(error.UnknownCommand, parsed_args);
}
