const std = @import("std");
const testing = std.testing;

const Hash = u64;
const bits = 1;
const width = 1 << bits;
const mask = width - 1;
const parts = @sizeOf(Hash) * 8 / bits;

fn Node(comptime T: type) type {
    return struct {
        value: ?T = null,
        left: ?*@This() = null,
        right: ?*@This() = null,
    };
}

fn newNode(allocator: *std.mem.Allocator, comptime T: type) !*Node(T) {
    const node: *Node(T) = try allocator.create(Node(T));
    node.* = Node(T){};
    return node;
}

fn Map(allocator: *std.mem.Allocator, comptime KT: type, comptime VT: type, hashFn: fn (KT) Hash) type {
    return struct {
        const Self = @This();

        head: *Node(VT),

        fn lookup(self: Self, key: KT, write: bool) !?*Node(VT) {
            const keyHash = hashFn(key);
            var node = self.head;
            var level: u6 = parts - 1;
            while (true) {
                var bit = (keyHash >> level) & mask;
                var maybeNode = if (bit == 0) node.left else node.right;
                if (maybeNode == null) {
                    if (write) {
                        var nextNode = try newNode(allocator, VT);
                        if (bit == 0) {
                            node.left = nextNode;
                        } else {
                            node.right = nextNode;
                        }
                        node = nextNode;
                    } else {
                        return null;
                    }
                } else {
                    node = maybeNode orelse return error.LookupFailed;
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
            var maybeNode = self.lookup(key, true) catch |e| return e;
            var node: *Node(VT) = maybeNode orelse return error.PutFailed;
            node.value = value;
        }

        fn get(self: *Self, key: KT) !?VT {
            var maybeNode = self.lookup(key, false) catch |e| return e;
            var node: *Node(VT) = maybeNode orelse return null;
            return node.value;
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

test "basic map functionality" {
    std.debug.warn("\n");
    const da = std.heap.direct_allocator;
    var m = Map(da, []const u8, []const u8, stringHasher){
        .head = try newNode(da, []const u8),
    };
    try m.put("name", "zach");
    var name = try m.get("name");
    std.debug.warn("{}\n", name);
}
