const std = @import("std");
const testing = std.testing;

const Hash = u64;
const bits = 1;
const width = 1 << bits;
const mask = width - 1;
const parts = @sizeOf(Hash) * 8 / bits;

fn KeyValue(comptime KT: type, comptime VT: type) type {
    return struct {
        key: KT,
        value: VT,
        nextValue: ?*@This() = null,
        prevValue: ?*@This() = null,
    };
}

fn newValue(comptime KT: type, comptime VT: type, key: KT, value: VT, prevValue: ?*KeyValue(KT, VT), allocator: *std.mem.Allocator) !*KeyValue(KT, VT) {
    const v: *KeyValue(KT, VT) = try allocator.create(KeyValue(KT, VT));
    v.* = KeyValue(KT, VT){
        .key = key,
        .value = value,
        .prevValue = prevValue,
    };
    return v;
}

fn Node(comptime KT: type, comptime VT: type) type {
    return struct {
        value: ?*KeyValue(KT, VT) = null,
        left: ?*@This() = null,
        right: ?*@This() = null,

        fn get(self: *@This(), key: KT, equalsFn: fn (KT, KT) bool) ?*KeyValue(KT, VT) {
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

        fn put(self: *@This(), key: KT, value: VT, allocator: *std.mem.Allocator, equalsFn: fn (KT, KT) bool) !void {
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
                            valuePtr.nextValue = try newValue(KT, VT, key, value, valuePtr, allocator);
                            return;
                        }
                    }
                }
            } else {
                self.value = try newValue(KT, VT, key, value, null, allocator);
            }
        }

        fn remove(self: *@This(), key: KT, allocator: *std.mem.Allocator, equalsFn: fn (KT, KT) bool) void {
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
                        allocator.destroy(valuePtr);
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

fn newNode(comptime KT: type, comptime VT: type, allocator: *std.mem.Allocator) !*Node(KT, VT) {
    const node: *Node(KT, VT) = try allocator.create(Node(KT, VT));
    node.* = Node(KT, VT){};
    return node;
}

fn Map(comptime KT: type, comptime VT: type, hashFn: fn (KT) Hash, equalsFn: fn (KT, KT) bool) type {
    return struct {
        const Self = @This();

        head: *Node(KT, VT),

        fn getNode(self: Self, key: KT, maybeAllocator: ?*std.mem.Allocator) !?*Node(KT, VT) {
            const keyHash = hashFn(key);
            var node = self.head;
            var level: u6 = parts - 1;
            while (true) {
                var bit = (keyHash >> level) & mask;
                var maybeNode = if (bit == 0) node.left else node.right;
                if (maybeNode) |unwrappedNode| {
                    node = unwrappedNode;
                } else {
                    if (maybeAllocator) |allocator| {
                        var nextNode = try newNode(KT, VT, allocator);
                        if (bit == 0) {
                            node.left = nextNode;
                        } else {
                            node.right = nextNode;
                        }
                        node = nextNode;
                    } else {
                        return null;
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

        fn put(self: *Self, key: KT, value: VT, allocator: *std.mem.Allocator) !void {
            var maybeNode = self.getNode(key, allocator) catch |e| return e;
            if (maybeNode) |node| {
                try node.put(key, value, allocator, equalsFn);
            }
        }

        fn get(self: *Self, key: KT) !?VT {
            var maybeNode = self.getNode(key, null) catch |e| return e;
            if (maybeNode) |node| {
                var v = node.get(key, equalsFn) orelse return null;
                return v.value;
            } else {
                return null;
            }
        }

        fn remove(self: *Self, key: KT, allocator: *std.mem.Allocator) !void {
            var maybeNode = self.getNode(key, null) catch |e| return e;
            if (maybeNode) |node| {
                node.remove(key, allocator, equalsFn);
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
    var m = Map([]const u8, []const u8, stringHasher, stringEquals){
        .head = try newNode([]const u8, []const u8, da),
    };
    try m.put("name", "zach", da);
    try m.put("name2", "zach2", da);
    try m.remove("name", da);
    var name = try m.get("name");
    std.debug.warn("{}\n", name);
}
