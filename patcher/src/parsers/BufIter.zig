const std = @import("std");
const mem = std.mem;
// TODO: Assert a bunch of shit
const assert = std.debug.assert;

const Self = @This();

buf: []const u8,
ptr: usize = 0,

/// A call to next will show the first character
pub fn init(buf: []const u8) Self {
    return Self{
        .buf = buf,
        .ptr = 0,
    };
}

/// A call to back will show the last character
pub fn initBack(buf: []const u8) Self {
    return Self{
        .buf = buf,
        .ptr = buf.len,
    };
}

pub fn isDone(self: Self) bool {
    return self.ptr < 0 or self.ptr >= self.buf.len;
}

pub fn isDoneReverse(self: Self) bool {
    return self.ptr <= 0 or self.ptr > self.buf.len;
}

pub fn peek(self: Self) ?u8 {
    if (self.isDone()) return null;
    return self.buf[self.ptr];
}

pub fn next(self: *Self) ?u8 {
    defer self.ptr += 1;
    return self.peek();
}

pub fn peekBack(self: Self) ?u8 {
    if (self.isDoneReverse()) return null;
    return self.buf[self.ptr - 1];
}

pub fn back(self: *Self) ?u8 {
    defer if (!self.isDoneReverse()) {
        self.ptr -= 1;
    };
    return self.peekBack();
}

pub fn peekNextLuaString(self: Self) ?[]const u8 {
    const start = self.findLuaStringOpeningAfter() orelse return null;
    const stop = self.findLuaStringClosingOn() orelse return null;
    return self.buf[start..stop];
}

/// Returns the slice before the next lua string
///    "String"
///    ^
///   Until this is returned
pub fn peekNextUntilLuaString(self: Self) ?[]const u8 {
    if (self.isDone()) return null;
    const string_start = self.findLuaStringOpeningOn() orelse return null;
    return self.buf[self.ptr..string_start];
}

/// This function is equal to the following:
/// `{key}\s*=\s*{string}`
/// where:
///   {key}    is your input,
///   \s*      is any amount of whitespace excluding \n,
///   =        is the literal character,
///   {string} is the lua string,
///
/// It returns a slice from self.ptr to the first character of the key
pub fn peekUntilNextLuaStringKey(self: Self, key: []const u8) ?[]const u8 {
    const before_string = self.peekNextUntilLuaString() orelse return null;

    if (before_string.len <= key.len) return null;

    var iter = initBack(before_string);
    while (iter.back()) |char| {
        if (isWhitespace(char)) continue;
        if (char == '=') break;

        // Non white space character is not '='
        return null;
    }

    const last_key_char = key[key.len - 1];

    while (iter.back()) |char| {
        if (isWhitespace(char)) continue;
        if (char != last_key_char) return null;

        // Make sure to include the end char
        _ = iter.next();
        break;
    }

    if (iter.ptr >= key.len and
        mem.eql(u8, key, iter.buf[(iter.ptr - key.len)..iter.ptr]))
    {
        return iter.buf[0..(iter.ptr - key.len)];
    } else {
        return null;
    }
}
pub fn nextUntilBefore(self: *Self, until: []const u8) ?[]const u8 {
    const str = self.peekUntilBefore(until) orelse return null;
    self.ptr += str.len;
    return str;
}

pub fn peekUntilBefore(self: Self, until: []const u8) ?[]const u8 {
    if ((self.ptr + until.len) >= self.buf.len) return null;

    for ((self.ptr)..(self.buf.len - until.len + 1)) |ptr| {
        if (!std.mem.eql(u8, self.buf[ptr..(ptr + until.len)], until))
            continue;

        return self.buf[self.ptr..ptr];
    }
    return null;
}

pub fn nextUntilAfter(self: *Self, until: []const u8) ?[]const u8 {
    const str = self.peekUntilAfter(until) orelse return null;
    self.ptr += str.len;
    return str;
}

pub fn peekUntilAfter(self: Self, until: []const u8) ?[]const u8 {
    if ((self.ptr + until.len) >= self.buf.len) return null;

    for ((self.ptr)..(self.buf.len - until.len + 1)) |ptr| {
        if (!std.mem.eql(u8, self.buf[ptr..(ptr + until.len)], until))
            continue;

        return self.buf[self.ptr..(ptr + until.len)];
    }
    return null;
}

pub fn nextUntilAfterLuaString(self: *Self) ?[]const u8 {
    const end_ptr = self.findLuaStringClosingAfter() orelse return null;
    defer self.ptr = end_ptr;
    return self.buf[self.ptr..end_ptr];
}

pub fn rest(self: *Self) ?[]const u8 {
    if (self.isDone()) return null;
    defer self.ptr = self.buf.len;
    return self.buf[self.ptr..];
}

pub fn peekRest(self: *Self) ?[]const u8 {
    if (self.isDone()) return null;
    return self.buf[self.ptr..];
}

fn isWhitespace(char: u8) bool {
    return char == ' ' or char == '\t';
}

fn findLuaStringOpeningOn(self: Self) ?usize {
    if (self.isDone()) {
        return null;
    }

    var iter = init(self.buf[self.ptr..]);

    while (iter.next()) |char| {
        if (char == '\'') break;

        if (char == '"') break;

        if (char == '[' and iter.peek() != null and iter.peek() == '[')
            break;
    }

    if (iter.isDone()) {
        return null;
    } else {
        return self.ptr + iter.ptr - 1;
    }
}
fn findLuaStringOpeningAfter(self: Self) ?usize {
    const ptr = self.findLuaStringOpeningOn() orelse return null;
    if (self.buf[ptr] == '[') {
        return ptr + 2;
    } else {
        return ptr + 1;
    }
}

fn findLuaStringClosingOn(self: Self) ?usize {
    if (self.isDone()) {
        return null;
    }

    const start = self.findLuaStringOpeningAfter() orelse return null;
    var iter = init(self.buf[start..]);

    while (iter.next()) |char| {
        if (char == '\'') break;

        if (char == '"') break;

        if (char == ']' and iter.peek() != null and iter.peek() == ']') {
            break;
        }
    }

    if (iter.isDone() and iter.ptr != iter.buf.len) {
        return null;
    } else {
        return start + iter.ptr - 1;
    }
}

fn findLuaStringClosingAfter(self: Self) ?usize {
    const ptr = self.findLuaStringClosingOn() orelse return null;
    if (self.buf[ptr] == ']') {
        return ptr + 2;
    } else {
        return ptr + 1;
    }
}

const tst = std.testing;
const expect = tst.expect;
const expectEqual = tst.expectEqual;
const expectEqualStrings = tst.expectEqualStrings;
const alloc = tst.allocator;

test "next/ peek" {
    const in = "abc";
    var iter = init(in);
    try expectEqual('a', iter.peek());
    try expectEqual('a', iter.peek());
    try expectEqual('a', iter.next());

    try expectEqual('b', iter.peek());
    try expectEqual('b', iter.peek());
    try expectEqual('b', iter.next());

    try expectEqual('c', iter.peek());
    try expectEqual('c', iter.peek());
    try expectEqual('c', iter.next());

    try expectEqual(null, iter.peek());
    try expectEqual(null, iter.peek());
    try expectEqual(null, iter.next());
    try expectEqual(null, iter.next());
}

test "back/ peekBack" {
    const in = "abc";
    var iter = initBack(in);
    try expectEqual('c', iter.peekBack());
    try expectEqual('c', iter.peekBack());
    try expectEqual('c', iter.back());

    try expectEqual('b', iter.peekBack());
    try expectEqual('b', iter.peekBack());
    try expectEqual('b', iter.back());

    try expectEqual('a', iter.peekBack());
    try expectEqual('a', iter.peekBack());
    try expectEqual('a', iter.back());

    try expectEqual(null, iter.peekBack());
    try expectEqual(null, iter.peekBack());
    try expectEqual(null, iter.back());
    try expectEqual(null, iter.back());
}

test "nextLuaString double" {
    const in =
        \\garbage"hello"garbage"garbage"
    ;
    var iter = init(in);
    try expectEqualStrings("hello", iter.peekNextLuaString().?);
    try expectEqualStrings("hello", iter.peekNextLuaString().?);
}

test "nextLuaString single" {
    const in =
        \\garbage'hello'garbage'garbage'
    ;
    var iter = init(in);
    try expectEqualStrings("hello", iter.peekNextLuaString().?);
    try expectEqualStrings("hello", iter.peekNextLuaString().?);
}

test "nextLuaString multiline" {
    const in =
        \\garbage[[hello
        \\world]]garbage[[garbage]]
    ;
    var iter = init(in);
    try expectEqualStrings("hello\nworld", iter.peekNextLuaString().?);
    try expectEqualStrings("hello\nworld", iter.peekNextLuaString().?);
}

test "nextLuaString empty" {
    const in =
        \\[[]]
    ;
    var iter = init(in);
    try expectEqualStrings("", iter.peekNextLuaString().?);
    try expectEqualStrings("", iter.peekNextLuaString().?);
}

test "nextLuaString first char" {
    const in =
        \\[[hello world]]
    ;
    var iter = init(in);
    try expectEqualStrings("hello world", iter.peekNextLuaString().?);
    try expectEqualStrings("hello world", iter.peekNextLuaString().?);
}

test "nextLuaStringHasKey no key" {
    const in = "[[hello]]";
    var iter = init(in);
    try expectEqual(null, iter.peekUntilNextLuaStringKey("some-key"));
}

test "nextLuaStringHasKey wrong key" {
    const in = "some-key = [[hello]]";
    var iter = init(in);
    try expectEqual(null, iter.peekUntilNextLuaStringKey("other-key"));
}

test "nextLuaStringHasKey right key" {
    const in = "some-key = [[hello]]";
    var iter = init(in);
    try expectEqualStrings("", iter.peekUntilNextLuaStringKey("some-key").?);
}

test "nextLuaStringHasKey no whitespace" {
    const in = "some-key=[[hello]]";
    var iter = init(in);
    try expectEqualStrings("", iter.peekUntilNextLuaStringKey("some-key").?);
}

test "nextLuaStringHasKey lost of whitespace" {
    const in = "   some-key    =       [[hello]]";
    var iter = init(in);
    try expectEqualStrings("   ", iter.peekUntilNextLuaStringKey("some-key").?);
}

test "nextLuaStringHasKey newline after =" {
    const in = "some-key =\n [[hello]]";
    var iter = init(in);
    try expectEqual(null, iter.peekUntilNextLuaStringKey("some-key"));
}

test "nextLuaStringHasKey newline before =" {
    const in = "some-key\n = [[hello]]";
    var iter = init(in);
    try expectEqual(null, iter.peekUntilNextLuaStringKey("some-key"));
}

test "nextLuaStringHasKey key obstructed" {
    const in = "some-key, = [[hello]]";
    var iter = init(in);
    try expectEqual(null, iter.peekUntilNextLuaStringKey("some-key"));
}

test "nextLuaStringHasKey no string" {
    const in = "garbage garbage";
    var iter = init(in);
    try expectEqual(null, iter.peekUntilNextLuaStringKey("some-key"));
}

test "skipAfterLuaString" {
    const in = "garbage[[hello]]x";
    var iter = init(in);
    try expect(iter.nextUntilAfterLuaString() != null);
    try expectEqual('x', iter.next());
}

test "string after skip" {
    const in = "[[Hello]] 'world'";
    var iter = init(in);
    try expect(iter.nextUntilAfterLuaString() != null);
    try expectEqualStrings("world", iter.peekNextLuaString().?);
}

test "findLuaStringClosing multiline" {
    const in = "[[h]]";
    var iter = init(in);
    try expectEqual(3, iter.findLuaStringClosingOn().?);
    try expectEqual(5, iter.findLuaStringClosingAfter().?);
}

test "findLuaStringClosing normal" {
    const in = "'h'";
    var iter = init(in);
    try expectEqual(2, iter.findLuaStringClosingOn().?);
    try expectEqual(3, iter.findLuaStringClosingAfter().?);
}

test "findLuaStringOpening multiline" {
    const in = "[[h]]";
    var iter = init(in);
    try expectEqual(0, iter.findLuaStringOpeningOn().?);
    try expectEqual(2, iter.findLuaStringOpeningAfter().?);
}

test "findLuaStringOpening normal" {
    const in = "'h'";
    var iter = init(in);
    try expectEqual(0, iter.findLuaStringOpeningOn().?);
    try expectEqual(1, iter.findLuaStringOpeningAfter().?);
}

test "nextUntilBefore single char" {
    const in = "hello|world|";
    var iter = init(in);
    try expectEqualStrings("hello", iter.nextUntilBefore("|").?);
    try expectEqual('|', iter.next().?);
    try expectEqualStrings("world", iter.nextUntilBefore("|").?);
    try expectEqual('|', iter.next().?);

    try expectEqual(null, iter.nextUntilBefore("|"));
}

test "nextUntilBefore rest" {
    const in = "hello|world";
    var iter = init(in);
    try expectEqualStrings("hello", iter.nextUntilBefore("|").?);
    try expectEqual('|', iter.next().?);
    try expectEqual(null, iter.nextUntilBefore("|"));
}

test "nextUntilBefore multi char" {
    const in = "hello|world|||";
    var iter = init(in);
    try expectEqualStrings("hello|world", iter.nextUntilBefore("|||").?);
    try expectEqual(null, iter.nextUntilBefore("|||"));
}

test "nextUntilBefore not present" {
    const in = "hello|world";
    var iter = init(in);
    try expectEqual(null, iter.nextUntilBefore("||"));
}

test "nextUntilBefore larger than str" {
    const in = "-";
    var iter = init(in);
    try expectEqual(null, iter.nextUntilBefore("||"));
}