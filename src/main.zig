const std = @import("std");
const args = @import("args.zig");
const kproj_reader = @import("kproj-reader.zig");

const project_template = @embedFile("./templates/.kproj");
const main_cpp = @embedFile("./templates/main.cpp");

// Build tools for C++ projects without any IDE
// Should be able to setup a project and make a config file to:
//      - Track which files to compile
//      - Compile arguments, such as warning, standard to use
// Should be able to build and run in debug & release mode based on the config file

const Commands = union(enum) {
    init: void,
    build: void,
    run: void,
};

// Init command create a scaffolding of a config file and main.cpp boilerplate
// If a path is specified all the scaffolding happens in this folder,
// (the folder is created if it does not exist)
pub fn initCommand(command_args: [][]const u8) !void {
    const path = if (command_args.len >= 1) command_args[0] else null;
    var dir = std.fs.cwd();

    if (path) |p| {
        dir.access(p, .{}) catch {
            try dir.makeDir(p);
        };
        dir = try dir.openDir(p, .{});
    }

    _ = try dir.writeFile(".kproj", project_template);
    _ = try dir.writeFile("main.cpp", main_cpp);
}

fn buildCommand(allocator: std.mem.Allocator, command_args: [][]const u8) !void {
    _ = command_args;

    const kproj_file = try std.fs.cwd().openFile(".kproj", .{});

    const kproj_content = try kproj_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(kproj_content);

    const parsed_kproj = try kproj_reader.parseKprojFile(
        allocator,
        kproj_content,
    );
    defer parsed_kproj.deinit();

    const clang_std_arg = try std.fmt.allocPrint(allocator, "-std={s}", .{@tagName(parsed_kproj.standard)});
    defer allocator.free(clang_std_arg);

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.appendSlice(&[_][]const u8{ "clang++", clang_std_arg, "-g" });
    try argv.appendSlice(parsed_kproj.files);
    try argv.appendSlice(&[_][]const u8{ "-o", parsed_kproj.output });

    const command = try std.mem.join(allocator, " ", argv.items);
    defer allocator.free(command);

    std.debug.print("Running: {s}\n", .{command});

    var a = std.heap.ArenaAllocator.init(allocator);
    defer a.deinit();

    const aa = a.allocator();
    const result = try std.ChildProcess.run(.{
        .allocator = aa,
        .argv = argv.items,
    });

    if (result.term.Exited != 0) {
        std.debug.print("{s}\n", .{result.stderr});
        return;
    }
}

fn runCommand(allocator: std.mem.Allocator, command_args: [][]const u8) !void {
    try buildCommand(allocator, command_args);

    var a = std.heap.ArenaAllocator.init(allocator);
    defer a.deinit();

    const aa = a.allocator();
    return std.process.execv(aa, &[_][]const u8{"./main"});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const parsed_args = try args.parseProcessArgs(allocator, Commands);
    defer parsed_args.deinit();

    switch (parsed_args.command) {
        .init => {
            try initCommand(parsed_args.args);
        },
        .build => {
            try buildCommand(allocator, parsed_args.args);
        },
        .run => {
            try runCommand(allocator, parsed_args.args);
        },
    }
}
