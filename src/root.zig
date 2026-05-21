const std = @import("std");

pub const UniquePtr = @import("unique-ptr.zig").UniquePtr;

test {
    std.testing.refAllDecls(@This());
}
