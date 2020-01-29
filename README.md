A small experiment in making a HAMT-based map and set in Zig, mostly based on a [great writeup](https://hypirion.com/musings/understanding-persistent-vector-pt-1) on how Clojure's vectors work. The ones in this project aren't really immutable like the name implies, because you need to clone them manually, but cloning is very fast...in theory. Do `zig build test` to run. Don't use this for anything serious, dummy.

```zig
var m1 = try Map([]const u8, []const u8, stringHasher, stringEquals).init(allocator);
defer m1.deinit();
try m1.put("name", "Bob");
try m1.put("country", "USA");

var m2 = try m1.clone();
defer m2.deinit();
try m2.put("name", "Alice");

std.debug.warn("{}\n", m1.get("name"));    // Bob
std.debug.warn("{}\n", m2.get("name"));    // Alice
std.debug.warn("{}\n", m2.get("country")); // USA
```
