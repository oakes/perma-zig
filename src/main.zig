const std = @import("std");
const testing = std.testing;

const Hash = u64;
const bits = 1;
const width = 1 << bits;
const mask = width - 1;
const parts = @sizeOf(Hash) * 8 / bits;

fn KeyValue(comptime KT: type, comptime VT: type) type {
    return struct {
        const Self = @This();

        key: KT,
        value: VT,
        nextValue: ?*Self = null,
        prevValue: ?*Self = null,
        allocator: *std.mem.Allocator,

        fn init(key: KT, value: VT, prevValue: ?*Self, allocator: *std.mem.Allocator) !*Self {
            const v = try allocator.create(Self);
            v.* = KeyValue(KT, VT){
                .key = key,
                .value = value,
                .prevValue = prevValue,
                .allocator = allocator,
            };
            return v;
        }

        fn deinit(self: *Self) void {
            if (self.nextValue) |unwrappedValue| {
                unwrappedValue.deinit();
            }
            self.allocator.destroy(self);
        }

        fn clone(self: *Self) error{OutOfMemory}!*Self {
            const v = try Self.init(self.key, self.value, null, self.allocator);
            if (self.nextValue) |nextValue| {
                var next = try nextValue.clone();
                v.nextValue = next;
                next.prevValue = self;
            }
            return v;
        }
    };
}

fn Node(comptime KT: type, comptime VT: type, comptime equalsFn: fn (KT, KT) bool) type {
    return struct {
        const Self = @This();

        value: ?*KeyValue(KT, VT) = null,
        left: ?*Self = null,
        right: ?*Self = null,
        allocator: *std.mem.Allocator,
        refCount: i32 = 1,

        fn init(allocator: *std.mem.Allocator) !*Self {
            const node = try allocator.create(Self);
            node.* = Self{
                .allocator = allocator,
            };
            return node;
        }

        fn deinit(self: *Self) void {
            if (self.left) |unwrappedLeft| {
                unwrappedLeft.deinit();
            }
            if (self.right) |unwrappedRight| {
                unwrappedRight.deinit();
            }
            self.refCount -= 1;
            if (self.refCount == 0) {
                if (self.value) |unwrappedValue| {
                    unwrappedValue.deinit();
                }
                self.allocator.destroy(self);
            }
        }

        fn incRefCount(self: *Self) void {
            self.refCount += 1;
            if (self.left) |left| {
                left.incRefCount();
            }
            if (self.right) |right| {
                right.incRefCount();
            }
        }

        fn get(self: *Self, key: KT) ?*KeyValue(KT, VT) {
            var maybeValue: ?*KeyValue(KT, VT) = self.value;
            while (true) {
                var valuePtr = maybeValue orelse break;
                if (equalsFn(key, valuePtr.key)) {
                    return maybeValue;
                } else {
                    maybeValue = valuePtr.nextValue orelse break;
                }
            }
            return null;
        }

        fn put(self: *Self, key: KT, value: VT) !void {
            if (self.value) |existingValue| {
                var valuePtr: *KeyValue(KT, VT) = existingValue;
                while (true) {
                    if (equalsFn(key, valuePtr.key)) {
                        valuePtr.value = value;
                        return;
                    } else {
                        if (valuePtr.nextValue) |nextValue| {
                            valuePtr = nextValue;
                        } else {
                            valuePtr.nextValue = try KeyValue(KT, VT).init(key, value, valuePtr, self.allocator);
                            return;
                        }
                    }
                }
            } else {
                self.value = try KeyValue(KT, VT).init(key, value, null, self.allocator);
            }
        }

        fn remove(self: *Self, key: KT) void {
            var valueToRemove = self.get(key) orelse return;
            if (self.value) |existingValue| {
                var valuePtr: *KeyValue(KT, VT) = existingValue;
                while (true) {
                    if (valuePtr == valueToRemove) {
                        if (valuePtr.prevValue) |prevValue| {
                            prevValue.nextValue = valuePtr.nextValue;
                        } else {
                            self.value = valuePtr.nextValue;
                        }
                        self.allocator.destroy(valuePtr);
                        return;
                    } else {
                        if (valuePtr.nextValue) |nextValue| {
                            valuePtr = nextValue;
                        } else {
                            return;
                        }
                    }
                }
            }
        }
    };
}

fn Map(comptime KT: type, comptime VT: type, comptime hashFn: fn (KT) Hash, comptime equalsFn: fn (KT, KT) bool) type {
    return struct {
        const Self = @This();

        head: *Node(KT, VT, equalsFn),
        allocator: *std.mem.Allocator,

        fn init(allocator: *std.mem.Allocator) !Self {
            return Self{
                .head = try Node(KT, VT, equalsFn).init(allocator),
                .allocator = allocator,
            };
        }

        fn deinit(self: *Self) void {
            self.head.deinit();
        }

        fn getNode(self: Self, key: KT, comptime writeWhenNotFound: bool, comptime writeWhenFound: bool) !*Node(KT, VT, equalsFn) {
            const keyHash = hashFn(key);
            var node = self.head;
            var level: u6 = parts - 1;
            while (true) {
                var bit = (keyHash >> level) & mask;
                var maybeNode = if (bit == 0) node.left else node.right;
                if (maybeNode) |unwrappedNode| {
                    if (writeWhenFound and unwrappedNode.refCount > 1) {
                        var nextNode = try Node(KT, VT, equalsFn).init(self.allocator);
                        if (unwrappedNode.value) |unwrappedValue| {
                            nextNode.value = try unwrappedValue.clone();
                        }
                        nextNode.left = unwrappedNode.left;
                        nextNode.right = unwrappedNode.right;
                        unwrappedNode.refCount -= 1;
                        if (bit == 0) {
                            node.left = nextNode;
                        } else {
                            node.right = nextNode;
                        }
                        node = nextNode;
                    } else {
                        node = unwrappedNode;
                    }
                } else {
                    if (writeWhenNotFound) {
                        var nextNode = try Node(KT, VT, equalsFn).init(self.allocator);
                        if (bit == 0) {
                            node.left = nextNode;
                        } else {
                            node.right = nextNode;
                        }
                        node = nextNode;
                    } else {
                        return error.NodeNotFound;
                    }
                }
                if (level == 0) {
                    break;
                } else {
                    level -= 1;
                }
            }
            return node;
        }

        fn clone(self: *Self) !Self {
            var m = try Self.init(self.allocator);
            if (self.head.left) |left| {
                left.incRefCount();
                m.head.left = left;
            }
            if (self.head.right) |right| {
                right.incRefCount();
                m.head.right = right;
            }
            return m;
        }

        fn put(self: *Self, key: KT, value: VT) !void {
            var node = try self.getNode(key, true, true);
            try node.put(key, value);
        }

        fn add(self: *Self, value: VT) !void {
            var node = try self.getNode(value, true, true);
            try node.put(value, value);
        }

        fn get(self: *Self, key: KT) ?VT {
            var maybeNode = self.getNode(key, false, false) catch null;
            if (maybeNode) |node| {
                var v = node.get(key) orelse return null;
                return v.value;
            } else {
                return null;
            }
        }

        fn remove(self: *Self, key: KT) void {
            var maybeNode = self.getNode(key, false, false) catch null;
            if (maybeNode) |node| {
                node.remove(key);
            }
        }
    };
}

fn Set(comptime T: type, comptime hashFn: fn (T) Hash, comptime equalsFn: fn (T, T) bool) type {
    return Map(T, T, hashFn, equalsFn);
}

fn stringHasher(input: []const u8) Hash {
    // djb2
    var hash: Hash = 5381;
    for (input) |c| {
        hash = 33 * hash + c;
    }
    return hash;
}

fn stringEquals(first: []const u8, second: []const u8) bool {
    return std.mem.eql(u8, first, second);
}

test "basic map functionality" {
    const da = std.heap.direct_allocator;
    var m = try Map([]const u8, []const u8, stringHasher, stringEquals).init(da);
    defer m.deinit();
    try m.put("name", "zach");
    try m.put("name2", "zach2");
    m.remove("name2");
    testing.expect(stringEquals(m.get("name") orelse "", "zach"));
    testing.expect(m.get("name2") == null);
}

test "basic set functionality" {
    const da = std.heap.direct_allocator;
    var s = try Set([]const u8, stringHasher, stringEquals).init(da);
    defer s.deinit();
    try s.add("zach");
    try s.add("zach2");
    s.remove("zach2");
    testing.expect(stringEquals(s.get("zach") orelse "", "zach"));
    testing.expect(s.get("zach2") == null);
}

test "immutable ops" {
    const da = std.heap.direct_allocator;

    var m1 = try Map([]const u8, []const u8, stringHasher, stringEquals).init(da);
    defer m1.deinit();
    try m1.put("name", "zach");
    try m1.put("name2", "zach3");
    var m2 = try m1.clone();
    try m2.put("name", "zach4");
    try m2.put("name", "zach2");
    defer m2.deinit();
    testing.expect(stringEquals(m1.get("name") orelse "", "zach"));
    testing.expect(stringEquals(m2.get("name") orelse "", "zach2"));
    testing.expect(stringEquals(m2.get("name2") orelse "", "zach3"));

    var s1 = try Set([]const u8, stringHasher, stringEquals).init(da);
    defer s1.deinit();
    try s1.add("zach");
    var s2 = try s1.clone();
    try s2.add("zach2");
    defer s2.deinit();
    testing.expect(stringEquals(s1.get("zach") orelse "", "zach"));
    testing.expect(s1.get("zach2") == null);
    testing.expect(stringEquals(s2.get("zach") orelse "", "zach"));
    testing.expect(stringEquals(s2.get("zach2") orelse "", "zach2"));
}
