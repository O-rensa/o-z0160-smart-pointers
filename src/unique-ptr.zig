const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn UniquePtr(comptime T: type) type {
    return struct {
        const Self = @This();

        ptr: ?*T,
        allocator: Allocator,

        /// Allocates space on the heap and initializes the inner value
        pub fn init(allocator: Allocator, value: T) !Self {
            const heap_ptr = try allocator.create(T);
            heap_ptr.* = value;
            return Self{
                .ptr = heap_ptr,
                .allocator = allocator,
            };
        }

        /// Cleans up the inner resource and frees the heap memory.
        pub fn deinit(self: *Self) void {
            if (self.ptr) |actual_ptr| {
                const info = @typeInfo(T);

                const is_container = match: {
                    switch (info) {
                        .@"struct", .@"enum", .@"union", .@"opaque" => break :match true,
                        else => break :match false,
                    }
                };

                if (is_container and @hasDecl(T, "deinit")) {
                    T.deinit(actual_ptr);
                }

                self.allocator.destroy(actual_ptr);
                self.ptr = null;
            }
        }

        /// Returns the pointer, or an error if it has been moved/released.
        /// This replaces runtime panics with standard Zig error handling.
        pub const GetError = error{PointerMoved};

        pub fn get(self: *const Self) GetError!*T {
            return self.ptr orelse GetError.PointerMoved;
        }

        /// Transports unique ownership to a new container instance.
        pub fn move(self: *Self) GetError!Self {
            const current_ptr = self.ptr orelse return GetError.PointerMoved;

            const new_container = Self{
                .ptr = current_ptr,
                .allocator = self.allocator,
            };

            self.ptr = null;
            return new_container;
        }

        /// Relinquishes ownership entirely, returning the raw heap pointer.
        pub fn release(self: *Self) GetError!*T {
            const current_ptr = self.ptr orelse return GetError.PointerMoved;
            self.ptr = null;
            return current_ptr;
        }
    };
}

const testing = std.testing;

test "UniquePtr - basic lifecycle allocation and deinit" {
    // We use the testing allocator to ensure no memory leaks occur
    const allocator = testing.allocator;

    // Allocate a basic integer
    var u_ptr = try UniquePtr(i32).init(allocator, 1234);
    defer u_ptr.deinit();

    const value_ptr = try u_ptr.get();
    try testing.expectEqual(@as(i32, 1234), value_ptr.*);

    // Modify the value through the pointer
    value_ptr.* = 5678;
    try testing.expectEqual(@as(i32, 5678), (try u_ptr.get()).*);
}

test "UniquePtr - moving ownership" {
    const allocator = testing.allocator;

    var original = try UniquePtr(f64).init(allocator, 3.14159);
    // Explicitly do not defer original.deinit() yet, as ownership will move

    // Move ownership to a new handle
    var moved_to = try original.move();
    defer moved_to.deinit();

    // The original container should now throw an error on access
    try testing.expectError(UniquePtr(f64).GetError.PointerMoved, original.get());
    try testing.expectError(UniquePtr(f64).GetError.PointerMoved, original.move());

    // The new container should hold the valid data
    const val = try moved_to.get();
    try testing.expectEqual(@as(f64, 3.14159), val.*);

    // It is safe to call deinit on the empty original container (it does nothing)
    original.deinit();
}

test "UniquePtr - releasing raw pointer" {
    const allocator = testing.allocator;

    var u_ptr = try UniquePtr(u8).init(allocator, 'Z');

    // Release ownership completely
    const raw_ptr = try u_ptr.release();

    // The container is now spent
    try testing.expectError(UniquePtr(u8).GetError.PointerMoved, u_ptr.get());

    // We are now completely responsible for cleaning up the raw pointer ourselves
    try testing.expectEqual(@as(u8, 'Z'), raw_ptr.*);
    allocator.destroy(raw_ptr);

    // Safety check: container deinit shouldn't double-free
    u_ptr.deinit();
}

test "UniquePtr - automatic nested deinit execution" {
    const allocator = testing.allocator;

    // A mock struct that tracks if its own deinit function was run
    const MockResource = struct {
        const Self = @This();
        was_deinitialized: *bool,

        pub fn deinit(self: *Self) void {
            self.was_deinitialized.* = true;
        }
    };

    var custom_deinit_called = false;
    const resource = MockResource{ .was_deinitialized = &custom_deinit_called };

    var u_ptr = try UniquePtr(MockResource).init(allocator, resource);

    try testing.expect(!custom_deinit_called);

    // This should automatically call MockResource.deinit() via the compile-time @hasDecl check
    u_ptr.deinit();

    try testing.expect(custom_deinit_called);
}
