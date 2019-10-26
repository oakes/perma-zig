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

        fn init(key: KT, value: VT, prevValue: ?*Self, allocator: *std.mem.Allocator) !*Self {
            const v = try allocator.create(KeyValue(KT, VT));
            v.* = KeyValue(KT, VT){
                .key = key,
                .value = value,
                .prevValue = prevValue,
            };
            return v;
        }
    };
}

fn Node(comptime KT: type, comptime VT: type) type {
    return struct {
        const Self = @This();

        value: ?*KeyValue(KT, VT) = null,
        left: ?*Self = null,
        right: ?*Self = null,
        allocator: *std.mem.Allocator,

        fn init(allocator: *std.mem.Allocator) !*Self {
            const node = try allocator.create(Node(KT, VT));
            node.* = Self{
                .allocator = allocator,
            };
            return node;
        }

        fn get(self: *Self, key: KT, equalsFn: fn (KT, KT) bool) ?*KeyValue(KT, VT) {
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

        fn put(self: *Self, key: KT, value: VT, equalsFn: fn (KT, KT) bool) !void {
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

        fn remove(self: *Self, key: KT, equalsFn: fn (KT, KT) bool) void {
            var valueToRemove = self.get(key, equalsFn) orelse return;
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

fn Map(comptime KT: type, comptime VT: type, hashFn: fn (KT) Hash, equalsFn: fn (KT, KT) bool) type {
    return struct {
        const Self = @This();

        head: *Node(KT, VT),
        allocator: *std.mem.Allocator,

        fn init(allocator: *std.mem.Allocator) !Self {
            return Self{
                .head = try Node([]const u8, []const u8).init(allocator),
                .allocator = allocator,
            };
        }

        fn getNode(self: Self, key: KT, comptime write: bool) !*Node(KT, VT) {
            const keyHash = hashFn(key);
            var node = self.head;
            var level: u6 = parts - 1;
            while (true) {
                var bit = (keyHash >> level) & mask;
                var maybeNode = if (bit == 0) node.left else node.right;
                if (maybeNode) |unwrappedNode| {
                    node = unwrappedNode;
                } else {
                    if (write) {
                        var nextNode = try Node(KT, VT).init(self.allocator);
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

        fn put(self: *Self, key: KT, value: VT) !void {
            var node = self.getNode(key, true) catch |e| return e;
            try node.put(key, value, equalsFn);
        }

        fn get(self: *Self, key: KT) ?VT {
            var maybeNode = self.getNode(key, false) catch null;
            if (maybeNode) |node| {
                var v = node.get(key, equalsFn) orelse return null;
                return v.value;
            } else {
                return null;
            }
        }

        fn remove(self: *Self, key: KT) void {
            var maybeNode = self.getNode(key, false) catch null;
            if (maybeNode) |node| {
                node.remove(key, equalsFn);
            }
        }
    };
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
    std.debug.warn("\n");
    const da = std.heap.direct_allocator;
    var m = try Map([]const u8, []const u8, stringHasher, stringEquals).init(da);
    try m.put("name", "zach");
    try m.put("name2", "zach2");
    m.remove("name");
    var name = m.get("name");
    std.debug.warn("{}\n", name);
}
