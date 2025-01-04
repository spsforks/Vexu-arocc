pub const std = @import("std");

const Attribute = @import("Attribute.zig");
const Compilation = @import("Compilation.zig");
const LangOpts = @import("LangOpts.zig");
const record_layout = @import("record_layout.zig");
const Parser = @import("Parser.zig");
const StringInterner = @import("StringInterner.zig");
const StringId = StringInterner.StringId;
const target_util = @import("target.zig");
const Tree = @import("Tree.zig");
const Node = Tree.Node;
const TokenIndex = Tree.TokenIndex;

const Repr = struct {
    tag: Tag,
    /// If a Type has a child type it is stored in data[0].
    data: [2]u32,

    pub const Tag = enum(u8) {
        complex,
        bit_int,
        atomic,
        func,
        func_variadic,
        func_old_style,
        func_zero,
        func_variadic_zero,
        func_old_style_zero,
        func_one,
        func_variadic_one,
        func_old_style_one,
        pointer,
        pointer_decayed,
        array_incomplete,
        array_fixed,
        array_static,
        array_variable,
        array_unspecified_variable,
        vector,
        @"struct",
        struct_incomplete,
        @"union",
        union_incomplete,
        @"enum",
        enum_fixed,
        enum_incomplete,
        typeof,
        typeof_expr,
        typedef,
        attributed,
        attributed_one,
    };
};

const Index = enum(u29) {
    /// A NaN-like poison value
    invalid = std.math.maxInt(u29) - 0,
    /// GNU auto type
    /// This is a placeholder specifier - it must be replaced by the actual type specifier (determined by the initializer)
    auto_type = std.math.maxInt(u29) - 1,
    /// C23 auto, behaves like auto_type
    c23_auto = std.math.maxInt(u29) - 2,
    void = std.math.maxInt(u29) - 3,
    bool = std.math.maxInt(u29) - 4,
    nullptr_t = std.math.maxInt(u29) - 5,
    int_char = std.math.maxInt(u29) - 6,
    int_schar = std.math.maxInt(u29) - 7,
    int_uchar = std.math.maxInt(u29) - 8,
    int_short = std.math.maxInt(u29) - 9,
    int_ushort = std.math.maxInt(u29) - 10,
    int_int = std.math.maxInt(u29) - 11,
    int_uint = std.math.maxInt(u29) - 12,
    int_long = std.math.maxInt(u29) - 13,
    int_ulong = std.math.maxInt(u29) - 14,
    int_long_long = std.math.maxInt(u29) - 15,
    int_ulong_long = std.math.maxInt(u29) - 16,
    int_int128 = std.math.maxInt(u29) - 17,
    int_uint128 = std.math.maxInt(u29) - 18,
    float_fp16 = std.math.maxInt(u29) - 19,
    float_float16 = std.math.maxInt(u29) - 20,
    float_float = std.math.maxInt(u29) - 21,
    float_double = std.math.maxInt(u29) - 22,
    float_long_double = std.math.maxInt(u29) - 23,
    float_float128 = std.math.maxInt(u29) - 24,
    void_pointer = std.math.maxInt(u29) - 25,
    char_pointer = std.math.maxInt(u29) - 26,
    int_pointer = std.math.maxInt(u29) - 27,
    _,
};

const TypeStore = @This();

pub const QualType = packed struct(u32) {
    @"const": bool = false,
    @"volatile": bool = false,
    restrict: bool = false,

    _index: Index,

    pub const invalid: QualType = .{ ._index = .invalid };
    pub const auto_type: QualType = .{ ._index = .auto_type };
    pub const c23_auto: QualType = .{ ._index = .c23_auto };
    pub const @"void": QualType = .{ ._index = .void };
    pub const @"bool": QualType = .{ ._index = .bool };
    pub const nullptr_t: QualType = .{ ._index = .nullptr_t };
    pub const char: QualType = .{ ._index = .int_char };
    pub const schar: QualType = .{ ._index = .int_schar };
    pub const uchar: QualType = .{ ._index = .int_uchar };
    pub const short: QualType = .{ ._index = .int_short };
    pub const ushort: QualType = .{ ._index = .int_ushort };
    pub const int: QualType = .{ ._index = .int_int };
    pub const uint: QualType = .{ ._index = .int_uint };
    pub const long: QualType = .{ ._index = .int_long };
    pub const ulong: QualType = .{ ._index = .int_ulong };
    pub const long_long: QualType = .{ ._index = .int_long_long };
    pub const ulong_long: QualType = .{ ._index = .int_ulong_long };
    pub const int128: QualType = .{ ._index = .int_int128 };
    pub const uint128: QualType = .{ ._index = .int_uint128 };
    pub const fp16: QualType = .{ ._index = .float_fp16 };
    pub const float16: QualType = .{ ._index = .float_float16 };
    pub const float: QualType = .{ ._index = .float_float };
    pub const double: QualType = .{ ._index = .float_double };
    pub const long_double: QualType = .{ ._index = .float_long_double };
    pub const float128: QualType = .{ ._index = .float_float128 };
    pub const void_pointer: QualType = .{ ._index = .void_pointer };
    pub const char_pointer: QualType = .{ ._index = .char_pointer };
    pub const int_pointer: QualType = .{ ._index = .int_pointer };

    pub fn isInvalid(qt: QualType) bool {
        return qt._index == .invalid;
    }

    pub fn isAutoType(qt: QualType) bool {
        return qt._index == .auto_type;
    }

    pub fn isC23Auto(qt: QualType) bool {
        return qt._index == .c23_auto;
    }

    pub fn isQualified(qt: QualType) bool {
        return qt.@"const" or qt.@"volatile" or qt.restrict;
    }

    pub fn unqualified(qt: QualType) QualType {
        return .{ ._index = qt._index };
    }

    pub fn withQualifiers(target: QualType, quals_from: QualType) QualType {
        return .{
            ._index = target._index,
            .@"const" = quals_from.@"const",
            .@"volatile" = quals_from.@"volatile",
            .restrict = quals_from.restrict,
        };
    }

    pub fn @"type"(qt: QualType, comp: *const Compilation) Type {
        switch (qt._index) {
            .invalid => unreachable,
            .auto_type => unreachable,
            .c23_auto => unreachable,
            .void => return .void,
            .bool => return .bool,
            .nullptr_t => return .nullptr_t,
            .int_char => return .{ .int = .char },
            .int_schar => return .{ .int = .schar },
            .int_uchar => return .{ .int = .uchar },
            .int_short => return .{ .int = .short },
            .int_ushort => return .{ .int = .ushort },
            .int_int => return .{ .int = .int },
            .int_uint => return .{ .int = .uint },
            .int_long => return .{ .int = .long },
            .int_ulong => return .{ .int = .ulong },
            .int_long_long => return .{ .int = .long_long },
            .int_ulong_long => return .{ .int = .ulong_long },
            .int_int128 => return .{ .int = .int128 },
            .int_uint128 => return .{ .int = .uint128 },
            .float_fp16 => return .{ .float = .fp16 },
            .float_float16 => return .{ .float = .float16 },
            .float_float => return .{ .float = .float },
            .float_double => return .{ .float = .double },
            .float_long_double => return .{ .float = .long_double },
            .float_float128 => return .{ .float = .float128 },
            .void_pointer => return .{ .pointer = .{ .child = .void, .decayed = null } },
            .char_pointer => return .{ .pointer = .{ .child = .char, .decayed = null } },
            .int_pointer => return .{ .pointer = .{ .child = .int, .decayed = null } },

            else => {},
        }

        const repr = comp.type_store.types.get(@intFromEnum(qt._index));
        return switch (repr.tag) {
            .complex => .{ .complex = @bitCast(repr.data[0]) },
            .atomic => .{ .atomic = @bitCast(repr.data[0]) },
            .bit_int => .{ .bit_int = .{
                .bits = @intCast(repr.data[0]),
                .signedness = @enumFromInt(repr.data[1]),
            } },
            .func_zero => .{ .func = .{
                .return_type = @bitCast(repr.data[0]),
                .kind = .normal,
                .params = &.{},
            } },
            .func_variadic_zero => .{ .func = .{
                .return_type = @bitCast(repr.data[0]),
                .kind = .variadic,
                .params = &.{},
            } },
            .func_old_style_zero => .{ .func = .{
                .return_type = @bitCast(repr.data[0]),
                .kind = .old_style,
                .params = &.{},
            } },
            .func_one,
            .func_variadic_one,
            .func_old_style_one,
            .func,
            .func_variadic,
            .func_old_style,
            => {
                const param_size = 3;
                const extra = comp.type_store.extra.items;
                const params_len = switch (repr.tag) {
                    .func_one, .func_variadic_one, .func_old_style_one => 1 * param_size,
                    .func, .func_variadic, .func_old_style => extra[repr.data[1]] * param_size,
                    else => unreachable,
                };
                const extra_params = extra[repr.data[1] + @intFromBool(params_len > 1) ..][0..params_len];

                return .{ .func = .{
                    .return_type = @bitCast(repr.data[0]),
                    .kind = switch (repr.tag) {
                        .func_one, .func => .normal,
                        .func_variadic_one, .func_variadic => .variadic,
                        .func_old_style_one, .func_old_style => .old_style,
                        else => unreachable,
                    },
                    .params = std.mem.bytesAsSlice(Type.Func.Param, std.mem.sliceAsBytes(extra_params)),
                } };
            },
            .pointer => .{ .pointer = .{
                .child = @bitCast(repr.data[0]),
                .decayed = null,
            } },
            .pointer_decayed => .{ .pointer = .{
                .child = @bitCast(repr.data[0]),
                .decayed = @bitCast(repr.data[1]),
            } },
            .array_incomplete => .{ .array = .{
                .elem = @bitCast(repr.data[0]),
                .len = .incomplete,
            } },
            .array_fixed => .{ .array = .{
                .elem = @bitCast(repr.data[0]),
                .len = .{ .fixed = @bitCast(comp.type_store.extra.items[repr.data[1]..][0..2].*) },
            } },
            .array_static => .{ .array = .{
                .elem = @bitCast(repr.data[0]),
                .len = .{ .static = @bitCast(comp.type_store.extra.items[repr.data[1]..][0..2].*) },
            } },
            .array_variable => .{ .array = .{
                .elem = @bitCast(repr.data[0]),
                .len = .{ .variable = @enumFromInt(repr.data[1]) },
            } },
            .array_unspecified_variable => .{ .array = .{
                .elem = @bitCast(repr.data[0]),
                .len = .unspecified_variable,
            } },
            .vector => .{ .vector = .{
                .elem = @bitCast(repr.data[0]),
                .len = repr.data[1],
            } },
            .@"struct", .@"union" => {
                const layout_size = 6;
                const field_size = 10;
                const extra = comp.type_store.extra.items;
                const layout = @as(*Type.Record.Layout, @alignCast(@ptrCast(extra[repr.data[1]..][0..layout_size]))).*;
                const fields_len = extra[repr.data[1] + layout_size] * field_size;
                const extra_fields = extra[repr.data[1] + layout_size + 1 ..][0..fields_len];

                const record: Type.Record = .{
                    .name = @enumFromInt(repr.data[0]),
                    .layout = layout,
                    .fields = std.mem.bytesAsSlice(Type.Record.Field, std.mem.sliceAsBytes(extra_fields)),
                };
                return switch (repr.tag) {
                    .@"struct" => .{ .@"struct" = record },
                    .@"union" => .{ .@"union" = record },
                    else => unreachable,
                };
            },
            .struct_incomplete => .{ .@"struct" = .{
                .name = @enumFromInt(repr.data[0]),
                .layout = null,
                .fields = &.{},
            } },
            .union_incomplete => .{ .@"union" = .{
                .name = @enumFromInt(repr.data[0]),
                .layout = null,
                .fields = &.{},
            } },
            .@"enum", .enum_fixed => {
                const extra = comp.type_store.extra.items;
                return .{ .@"enum" = .{
                    .name = @enumFromInt(extra[repr.data[1]]),
                    .tag = @bitCast(repr.data[0]),
                    .fixed = repr.tag == .enum_fixed,
                    .fields = std.mem.bytesAsSlice(Type.Enum.Field, std.mem.sliceAsBytes(extra[repr.data[1] + 1 ..][0 .. repr.data[1] + 2])),
                } };
            },
            .enum_incomplete => .{ .@"enum" = .{
                .name = @enumFromInt(repr.data[0]),
                .tag = null,
                .fixed = false,
                .fields = &.{},
            } },
            .typeof => .{ .typeof = .{
                .base = @bitCast(repr.data[0]),
                .expr = null,
            } },
            .typeof_expr => .{ .typeof = .{
                .base = @bitCast(repr.data[0]),
                .expr = @enumFromInt(repr.data[1]),
            } },
            .typedef => .{ .typedef = .{
                .base = @bitCast(repr.data[0]),
                .name = @enumFromInt(repr.data[1]),
            } },
            .attributed => {
                const extra = comp.type_store.extra.items;
                return .{ .attributed = .{
                    .base = @bitCast(repr.data[0]),
                    .attributes = comp.type_store.attributes.items[extra[repr.data[1]]..][0..extra[repr.data[1] + 1]],
                } };
            },
            .attributed_one => .{ .attributed = .{
                .base = @bitCast(repr.data[0]),
                .attributes = comp.type_store.attributes.items[repr.data[1]..][0..1],
            } },
        };
    }

    pub fn base(qt: QualType, comp: *const Compilation) struct { type: Type, qt: QualType } {
        var cur = qt;
        // TODO handle invalid autotype c23auto here?
        while (true) switch (cur.type(comp)) {
            .typeof => |typeof| cur = typeof.base,
            .typedef => |typedef| cur = typedef.base,
            .attributed => |attributed| cur = attributed.base,
            else => |ty| return .{ .type = ty, .qt = cur },
        };
    }

    pub fn get(qt: QualType, comp: *const Compilation, comptime tag: std.meta.Tag(Type)) ?@FieldType(Type, @tagName(tag)) {
        comptime std.debug.assert(tag != .typeof and tag != .attributed and tag != .typedef);
        const base_type = qt.base(comp).type;
        if (base_type == tag) return @field(base_type, @tagName(tag));
        return null;
    }

    pub fn is(qt: QualType, comp: *const Compilation, comptime tag: std.meta.Tag(Type)) bool {
        return qt.get(comp, tag) != null;
    }

    pub fn childType(qt: QualType, comp: *const Compilation) QualType {
        if (qt._index == .invalid) return .invalid;
        return switch (qt.base(comp).type) {
            .complex => |complex| complex,
            .func => |func| func.return_type,
            .pointer => |pointer| pointer.child,
            .array => |array| array.elem,
            .vector => |vector| vector.elem,
            .@"enum" => |@"enum"| @"enum".tag.?,
            else => unreachable,
        };
    }

    pub fn arrayLen(qt: QualType, comp: *Compilation) ?u64 {
        const array_type = switch (qt.base(comp).type) {
            .array => |array| array,
            .pointer => |pointer| blk: {
                const decayed = pointer.decayed orelse return null;
                break :blk decayed.get(comp, .array) orelse return null;
            },
            else => return null,
        };
        switch (array_type.len) {
            .fixed, .static => |len| return len,
            else => return null,
        }
    }

    pub fn sizeof(qt: QualType, comp: *const Compilation) u64 {
        _ = qt;
        _ = comp;
        @panic("TODO");
    }

    pub fn sizeofOrNull(qt: QualType, comp: *const Compilation) ?u64 {
        if (qt.isInvalid()) return null;
        _ = comp;
        @panic("TODO");
    }

    pub fn bitSizeof(qt: QualType, comp: *const Compilation) u64 {
        _ = qt;
        _ = comp;
        @panic("TODO");
    }

    pub fn bitSizeofOrNull(qt: QualType, comp: *const Compilation) ?u64 {
        if (qt.isInvalid()) return null;
        _ = comp;
        @panic("TODO");
    }

    pub fn signedness(qt: QualType, comp: *const Compilation) std.builtin.Signedness {
        _ = qt;
        _ = comp;
        @panic("TODO");
    }

    pub fn alignof(qt: QualType, comp: *const Compilation) u32 {
        _ = qt;
        _ = comp;
        @panic("TODO");
    }

    /// Suffix for integer values of this type
    pub fn intValueSuffix(qt: QualType, comp: *const Compilation) []const u8 {
        return switch (qt.get(comp, .int).?) {
            .short, .int => "",
            .long => "L",
            .long_long => "LL",
            .schar, .uchar, .char => {
                // Only 8-bit char supported currently;
                // TODO: handle platforms with 16-bit int + 16-bit char
                std.debug.assert(qt.sizeof(comp) == 1);
                return "";
            },
            .ushort => {
                if (qt.sizeof(comp) < int.sizeof(comp)) {
                    return "";
                }
                return "U";
            },
            .uint => "U",
            .ulong => "UL",
            .ulong_long => "ULL",
            else => unreachable, // TODO
        };
    }

    /// printf format modifier
    pub fn formatModifier(qt: QualType, comp: *const Compilation) []const u8 {
        return switch (qt.get(comp, .int).?) {
            .schar, .uchar => "hh",
            .short, .ushort => "h",
            .int, .uint => "",
            .long, .ulong => "l",
            .long_long, .ulong_long => "ll",
            else => unreachable, // TODO
        };
    }

    /// Make real int type unsigned.
    /// Discards attributes.
    pub fn makeIntUnsigned(qt: QualType, comp: *Compilation) !QualType {
        switch (qt.base(comp).type) {
            .int => |kind| switch (kind) {
                .char => return .uchar,
                .schar => return .uchar,
                .uchar => return .uchar,
                .short => return .ushort,
                .ushort => return .ushort,
                .int => return .uint,
                .uint => return .uint,
                .long => return .ulong,
                .ulong => return .ulong,
                .long_long => return .ulong_long,
                .ulong_long => return .ulong_long,
                .int128 => return .uint128,
                .uint128 => return .uint128,
            },
            .bit_int => |bit_int| {
                return try comp.type_store.put(comp.gpa, .{ .bit_int = .{
                    .signedness = .unsigned,
                    .bits = bit_int.bits,
                } });
            },
            else => unreachable,
        }
    }

    pub fn toReal(qt: QualType, comp: *const Compilation) QualType {
        _ = qt;
        _ = comp;
        @panic("TODO");
    }

    pub fn toComplex(qt: QualType, comp: *Compilation) !QualType {
        _ = qt;
        _ = comp;
        @panic("TODO");
    }

    pub fn decay(qt: QualType, comp: *Compilation) !QualType {
        switch (qt.base(comp).type) {
            .array => |array_ty| {
                if (array_ty.elem.isInvalid()) return .invalid;
                var ptr_qt = try comp.type_store.put(comp.gpa, .{ .pointer = .{
                    .child = array_ty.elem,
                    .decayed = qt,
                } });
                // Copy qualifiers
                ptr_qt.@"const" = qt.@"const";
                ptr_qt.@"volatile" = qt.@"volatile";
                ptr_qt.restrict = qt.restrict;
                return ptr_qt;
            },
            .func => |func_ty| {
                if (func_ty.return_type.isInvalid()) {
                    return .invalid;
                }
                for (func_ty.params) |param| {
                    if (param.qt.isInvalid()) {
                        return .invalid;
                    }
                }

                return comp.type_store.put(comp.gpa, .{ .pointer = .{
                    .child = qt,
                    .decayed = null,
                } });
            },
            else => return qt,
        }
    }

    /// Rank for floating point conversions, ignoring domain (complex vs real)
    /// Asserts that ty is a floating point type
    pub fn floatRank(qt: QualType, comp: *const Compilation) usize {
        _ = qt;
        _ = comp;
        @panic("TODO");
    }

    /// Rank for integer conversions, ignoring domain (complex vs real)
    /// Asserts that ty is an integer type
    pub fn intRank(qt: QualType, comp: *const Compilation) usize {
        _ = qt;
        _ = comp;
        @panic("TODO");
    }

    pub fn intRankOrder(a: QualType, b: QualType, comp: *const Compilation) std.math.Order {
        std.debug.assert(a.isInt(comp) and b.isInt(comp));

        const a_unsigned = a.signedness(comp) == .unsigned;
        const b_unsigned = b.signedness(comp) == .unsigned;

        const a_rank = a.intRank(comp);
        const b_rank = b.intRank(comp);
        if (a_unsigned == b_unsigned) {
            return std.math.order(a_rank, b_rank);
        }
        if (a_unsigned) {
            if (a_rank >= b_rank) return .gt;
            return .lt;
        }
        std.debug.assert(b_unsigned);
        if (b_rank >= a_rank) return .lt;
        return .gt;
    }

    pub fn promoteInt(qt: QualType, comp: *const Compilation) QualType {
        const int_qt = switch (qt.base(comp).type) {
            .@"enum" => |@"enum"| @"enum".tag orelse return .int,
            .bit_int => return qt,
            .complex => return qt, // Assume complex integer type
            else => qt, // Not an integer type
        };
        return switch (int_qt.get(comp, .int)) {
            .bool, .char, .schar, .uchar, .short => .int,
            .ushort => if (Type.Int.uchar.bits(comp) == Type.Int.int.bits(comp)) .uint else .int,
            else => return int_qt,
        };
    }

    pub const ScalarKind = enum {
        @"enum",
        bool,
        int,
        float,
        pointer,
        nullptr_t,
        void_pointer,
        complex_int,
        complex_float,
        none,

        pub fn isInt(sk: ScalarKind) bool {
            return switch (sk) {
                .bool, .@"enum", .int, .complex_int => true,
                else => false,
            };
        }

        pub fn isFloat(sk: ScalarKind) bool {
            return switch (sk) {
                .float, .complex_float => true,
                else => false,
            };
        }

        pub fn isReal(sk: ScalarKind) bool {
            return switch (sk) {
                .complex_int, .complex_float => false,
                else => true,
            };
        }

        pub fn isPointer(sk: ScalarKind) bool {
            return switch (sk) {
                .pointer, .nullptr_t, .void_pointer => false,
                else => true,
            };
        }

        pub fn isArithmetic(sk: ScalarKind) bool {
            return switch (sk) {
                .bool, .@"enum", .int, .complex_int, .float, .complex_float => true,
                else => false,
            };
        }
    };

    pub fn scalarKind(qt: QualType, comp: *const Compilation) ScalarKind {
        loop: switch (qt.base(comp).type) {
            .bool => return .bool,
            .int, .bit_int => return .int,
            .float => return .float,
            .nullptr_t => return .nullptr_t,
            .pointer => |pointer| switch (pointer.child.base(comp).type) {
                .void => return .void_pointer,
                else => return .pointer,
            },
            .@"enum" => return .@"enum",
            .complex => |complex| switch (complex.base(comp).type) {
                .int, .bit_int => return .complex_int,
                .float => return .complex_float,
                else => unreachable,
            },
            .atomic => |atomic| continue :loop atomic.base(comp).type,
            else => return .none,
        }
    }

    // Prefer calling scalarKind directly if checking multiple kinds.
    pub fn isInt(qt: QualType, comp: *const Compilation) bool {
        return qt.scalarKind(comp).isInt();
    }

    // Prefer calling scalarKind directly if checking multiple kinds.
    pub fn isFloat(qt: QualType, comp: *const Compilation) bool {
        return qt.scalarKind(comp).isFloat();
    }

    // Prefer calling scalarKind directly if checking multiple kinds.
    pub fn isPointer(qt: QualType, comp: *const Compilation) bool {
        return qt.scalarKind(comp).isPointer();
    }

    pub fn eqlQualified(a_qt: QualType, b_qt: QualType, comp: *const Compilation) bool {
        if (a_qt.@"const" != b_qt.@"const") return false;
        if (a_qt.@"volatile" != b_qt.@"volatile") return false;
        if (a_qt.restrict != b_qt.restrict) return false;

        return a_qt.eql(b_qt, comp);
    }

    pub fn eql(a_qt: QualType, b_qt: QualType, comp: *const Compilation) bool {
        if (a_qt.isInvalid() or b_qt.isInvalid()) return false;
        if (a_qt._index == b_qt._index) return true;

        const a_type = a_qt.base(comp).type;
        const b_type = b_qt.base(comp).type;

        if (std.meta.activeTag(a_type) != b_type) return false;
        switch (a_type) {
            .void => unreachable, // Handled in _index check above.
            .bool => unreachable, // Handled in _index check above.
            .nullptr_t => unreachable, // Handled in _index check above.
            .int => unreachable, // Handled in _index check above.
            .float => unreachable, // Handled in _index check above.

            .complex => |a_complex| {
                const b_complex = b_type.complex;
                // Complex child type cannot be qualified.
                return a_complex.eql(b_complex, comp);
            },
            .bit_int => |a_bit_int| {
                const b_bit_int = b_type.bit_int;
                if (a_bit_int.bits != b_bit_int.bits) return false;
                if (a_bit_int.signedness != b_bit_int.signedness) return false;
                return true;
            },
            .atomic => |a_atomic| {
                const b_atomic = b_type.atomic;
                // Atomic child type cannot be qualified.
                return a_atomic.eql(b_atomic, comp);
            },
            .func => |a_func| {
                const b_func = b_type.func;

                if (a_func.params.len != b_func.params.len) {
                    if (a_func.kind == .old_style or b_func.kind == .old_style) {
                        if (true) @panic("TODO is this correct?");
                        const maybe_has_params = if (a_func.kind == .old_style) b_func else a_func;

                        // Check if any args undergo default argument promotion.
                        for (maybe_has_params.params) |param| {
                            switch (param.qt.base(comp).type) {
                                .bool => return false,
                                .int => |int_ty| switch (int_ty) {
                                    .char, .uchar, .schar => return false,
                                    else => {},
                                },
                                .float => |float_ty| if (float_ty != .double) return false,
                                .@"enum" => |enum_ty| {
                                    if (comp.langopts.emulate == .clang and enum_ty.tag == null) return false;
                                },
                                else => {},
                            }
                        }
                        return true;
                    }
                    return false;
                }

                if ((a_func.kind == .normal) != (b_func.kind == .normal)) return false;

                // Function return type cannot be qualified.
                if (!a_func.return_type.eql(b_func.return_type, comp)) return false;

                for (a_func.params, b_func.params) |a_param, b_param| {
                    // Function parameters cannot be qualified.
                    if (!a_param.qt.eql(b_param.qt, comp)) return false;
                }
                return true;
            },
            .pointer => |a_pointer| {
                const b_pointer = b_type.pointer;
                return a_pointer.child.eqlQualified(b_pointer.child, comp);
            },
            .array => |a_array| {
                const b_array = b_type.array;
                // Array element qualifiers are ignored.
                return a_array.elem.eql(b_array.elem, comp);
            },
            .vector => |a_vector| {
                const b_vector = b_type.vector;
                // Vector elemnent qualifiers are checked.
                return a_vector.elem.eqlQualified(b_vector.elem, comp);
            },
            .@"struct", .@"union", .@"enum" => return false, // Should have matched in the _index check above.

            .typeof => unreachable, // Never returned from base()
            .typedef => unreachable, // Never returned from base()
            .attributed => unreachable, // Never returned from base()
        }
    }

    pub fn hasAttribute(qt: QualType, comp: *const Compilation, tag: Attribute.Tag) bool {
        var it = Attribute.Iterator.initType(qt, comp);
        while (it.next()) |item| {
            const attr, _ = item;
            if (attr.tag == tag) return true;
        }
        return false;
    }

    pub fn requestedAlignment(qt: QualType, comp: *const Compilation) ?u32 {
        return annotationAlignment(comp, Attribute.Iterator.initType(qt, comp));
    }

    pub fn annotationAlignment(comp: *const Compilation, attrs: Attribute.Iterator) ?u32 {
        var it = attrs;
        var max_requested: ?u32 = null;
        var last_aligned_index: ?usize = null;
        while (it.next()) |item| {
            const attribute, const index = item;
            if (attribute.tag != .aligned) continue;
            if (last_aligned_index) |aligned_index| {
                // once we recurse into a new type, after an `aligned` attribute was found, we're done
                if (index <= aligned_index) break;
            }
            last_aligned_index = index;
            const requested = if (attribute.args.aligned.alignment) |alignment| alignment.requested else target_util.defaultAlignment(comp.target);
            if (max_requested == null or max_requested.? < requested) {
                max_requested = requested;
            }
        }
        return max_requested;
    }

    pub fn print(qt: QualType, comp: *const Compilation, w: anytype) @TypeOf(w).Error!void {
        _ = qt;
        _ = comp;
        @panic("TODO");
    }

    pub fn dump(qt: QualType, comp: *const Compilation, w: anytype) @TypeOf(w).Error!void {
        _ = qt;
        _ = comp;
        @panic("TODO");
    }
};

pub const Type = union(enum) {
    void,
    bool,
    /// C23 nullptr_t
    nullptr_t,

    int: Int,
    float: Float,
    complex: QualType,
    bit_int: BitInt,
    atomic: QualType,

    func: Func,
    pointer: Pointer,
    array: Array,
    vector: Vector,

    @"struct": Record,
    @"union": Record,
    @"enum": Enum,

    typeof: TypeOf,
    typedef: TypeDef,
    attributed: Attributed,

    pub const Int = enum {
        char,
        schar,
        uchar,
        short,
        ushort,
        int,
        uint,
        long,
        ulong,
        long_long,
        ulong_long,
        int128,
        uint128,

        pub fn bits(int: Int, comp: *const Compilation) u16 {
            return switch (int) {
                .char => comp.target.cTypeBitSize(.char),
                .schar => comp.target.cTypeBitSize(.char),
                .uchar => comp.target.cTypeBitSize(.char),
                .short => comp.target.cTypeBitSize(.short),
                .ushort => comp.target.cTypeBitSize(.ushort),
                .int => comp.target.cTypeBitSize(.int),
                .uint => comp.target.cTypeBitSize(.uint),
                .long => comp.target.cTypeBitSize(.long),
                .ulong => comp.target.cTypeBitSize(.ulong),
                .long_long => comp.target.cTypeBitSize(.longlong),
                .ulong_long => comp.target.cTypeBitSize(.ulonglong),
                .int128 => 128,
                .uint128 => 128,
            };
        }
    };

    pub const Float = enum {
        fp16,
        float16,
        float,
        double,
        long_double,
        float128,

        pub fn bits(float: Float, comp: *const Compilation) u16 {
            return switch (float) {
                .fp16 => 16,
                .float16 => 16,
                .float => comp.target.cTypeBitSize(.float),
                .double => comp.target.cTypeBitSize(.double),
                .long_double => comp.target.cTypeBitSize(.longdouble),
                .float128 => 128,
            };
        }
    };

    pub const BitInt = struct {
        /// Must be >= 1 if unsigned and >= 2 if signed
        bits: u16,
        signedness: std.builtin.Signedness,
    };

    pub const Func = struct {
        return_type: QualType,
        kind: enum {
            /// int foo(int bar, char baz) and int (void)
            normal,
            /// int foo(int bar, char baz, ...)
            variadic,
            /// int foo(bar, baz) and int foo()
            /// is also var args, but we can give warnings about incorrect amounts of parameters
            old_style,
        },
        params: []const Param,

        pub const Param = extern struct {
            qt: QualType,
            name: StringId,
            node: Node.OptIndex,
        };
    };

    pub const Pointer = struct {
        child: QualType,
        decayed: ?QualType,
    };

    pub const Array = struct {
        elem: QualType,
        len: union(enum) {
            incomplete,
            fixed: u64,
            static: u64,
            variable: Node.Index,
            unspecified_variable,
        },
    };

    pub const Vector = struct {
        elem: QualType,
        len: u32,
    };

    pub const Record = struct {
        name: StringId,
        layout: ?Layout = null,
        fields: []const Field,

        pub const Field = extern struct {
            qt: QualType,
            name: StringId,
            /// zero for anonymous fields
            name_tok: TokenIndex = 0,
            bit_width: enum(u32) {
                null = std.math.maxInt(u32),
                _,

                pub fn unpack(width: @This()) ?u32 {
                    if (width == .null) return null;
                    return @intFromEnum(width);
                }
            } = .null,
            layout: Field.Layout = .{
                .offset_bits = 0,
                .size_bits = 0,
            },
            _attr_index: u32 = 0,
            _attr_len: u32 = 0,

            pub fn attributes(field: Field, comp: *const Compilation) []const Attribute {
                return comp.type_store.attributes.items[field._attr_index..][0..field._attr_len];
            }

            pub const Layout = extern struct {
                /// `offset_bits` and `size_bits` should both be INVALID if and only if the field
                /// is an unnamed bitfield. There is no way to reference an unnamed bitfield in C, so
                /// there should be no way to observe these values. If it is used, this value will
                /// maximize the chance that a safety-checked overflow will occur.
                const INVALID = std.math.maxInt(u64);

                /// The offset of the field, in bits, from the start of the struct.
                offset_bits: u64 align(4) = INVALID,
                /// The size, in bits, of the field.
                ///
                /// For bit-fields, this is the width of the field.
                size_bits: u64 align(4) = INVALID,

                pub fn isUnnamed(self: Field.Layout) bool {
                    return self.offset_bits == INVALID and self.size_bits == INVALID;
                }
            };
        };

        pub const Layout = extern struct {
            /// The size of the type in bits.
            ///
            /// This is the value returned by `sizeof` in C
            /// (but in bits instead of bytes). This is a multiple of `pointer_alignment_bits`.
            size_bits: u64 align(4),
            /// The alignment of the type, in bits, when used as a field in a record.
            ///
            /// This is usually the value returned by `_Alignof` in C, but there are some edge
            /// cases in GCC where `_Alignof` returns a smaller value.
            field_alignment_bits: u32,
            /// The alignment, in bits, of valid pointers to this type.
            /// `size_bits` is a multiple of this value.
            pointer_alignment_bits: u32,
            /// The required alignment of the type in bits.
            ///
            /// This value is only used by MSVC targets. It is 8 on all other
            /// targets. On MSVC targets, this value restricts the effects of `#pragma pack` except
            /// in some cases involving bit-fields.
            required_alignment_bits: u32,
        };

        pub fn isAnonymous(record: Record, comp: *const Compilation) bool {
            // anonymous records can be recognized by their names which are in
            // the format "(anonymous TAG at path:line:col)".
            return record.name.lookup(comp)[0] == '(';
        }
    };

    pub const Enum = struct {
        tag: ?QualType,
        fixed: bool,
        name: StringId,
        fields: []const Field,

        pub const Field = extern struct {
            type: QualType,
            name: StringId,
            name_tok: TokenIndex,
            node: Node.Index,
        };
    };

    pub const TypeOf = struct {
        base: QualType,
        expr: ?Node.Index,
    };

    pub const TypeDef = struct {
        base: QualType,
        name: StringId,
    };

    pub const Attributed = struct {
        base: QualType,
        attributes: []const Attribute,
    };
};

types: std.MultiArrayList(Repr) = .empty,
extra: std.ArrayListUnmanaged(u32) = .empty,
attributes: std.ArrayListUnmanaged(Attribute) = .empty,

wchar: QualType = .invalid,
uint_least16_t: QualType = .invalid,
uint_least32_t: QualType = .invalid,
ptrdiff: QualType = .invalid,
size: QualType = .invalid,
va_list: QualType = .invalid,
pid_t: QualType = .invalid,
ns_constant_string: QualType = .invalid,
file: QualType = .invalid,
jmp_buf: QualType = .invalid,
sigjmp_buf: QualType = .invalid,
ucontext_t: QualType = .invalid,
intmax: QualType = .invalid,
intptr: QualType = .invalid,
int16: QualType = .invalid,
int64: QualType = .invalid,

pub fn deinit(ts: *TypeStore, gpa: std.mem.Allocator) void {
    ts.types.deinit(gpa);
    ts.extra.deinit(gpa);
    ts.attributes.deinit(gpa);
    ts.* = undefined;
}

pub fn put(ts: *TypeStore, gpa: std.mem.Allocator, ty: Type) !QualType {
    return .{ ._index = try ts.putExtra(gpa, ty) };
}

pub fn putExtra(ts: *TypeStore, gpa: std.mem.Allocator, ty: Type) !Index {
    switch (ty) {
        .void => return .void,
        .bool => return .bool,
        .nullptr_t => return .nullptr_t,
        .int => |int| switch (int) {
            .char => return .int_char,
            .schar => return .int_schar,
            .uchar => return .int_uchar,
            .short => return .int_short,
            .ushort => return .int_ushort,
            .int => return .int_int,
            .uint => return .int_uint,
            .long => return .int_long,
            .ulong => return .int_ulong,
            .long_long => return .int_long_long,
            .ulong_long => return .int_ulong_long,
            .int128 => return .int_int128,
            .uint128 => return .int_uint128,
        },
        .float => |float| switch (float) {
            .fp16 => return .float_fp16,
            .float16 => return .float_float16,
            .float => return .float_float,
            .double => return .float_double,
            .long_double => return .float_long_double,
            .float128 => return .float_float128,
        },
        else => {},
    }
    const index = try ts.types.addOne(gpa);
    try ts.set(gpa, ty, index);
    return @enumFromInt(index);
}

pub fn set(ts: *TypeStore, gpa: std.mem.Allocator, ty: Type, index: usize) !void {
    var repr: Repr = undefined;
    switch (ty) {
        .void => unreachable,
        .bool => unreachable,
        .nullptr_t => unreachable,
        .int => unreachable,
        .float => unreachable,
        .complex => |complex| {
            repr.tag = .complex;
            repr.data[0] = @bitCast(complex);
        },
        .bit_int => |bit_int| {
            repr.tag = .bit_int;
            repr.data[0] = bit_int.bits;
            repr.data[1] = @intFromEnum(bit_int.signedness);
        },
        .atomic => |atomic| {
            repr.tag = .atomic;
            std.debug.assert(!atomic.@"const" and !atomic.@"volatile");
            repr.data[0] = @bitCast(atomic);
        },
        .func => |func| {
            repr.data[0] = @bitCast(func.return_type);

            const extra_index: u32 = @intCast(ts.extra.items.len);
            repr.data[1] = extra_index;
            if (func.params.len > 1) {
                try ts.extra.append(gpa, @intCast(func.params.len));
            }

            const param_size = 3;
            comptime std.debug.assert(@sizeOf(Type.Func.Param) == @sizeOf(u32) * param_size);

            try ts.extra.ensureUnusedCapacity(gpa, func.params.len * param_size);
            for (func.params) |*param| {
                const casted: *const [param_size]u32 = @ptrCast(param);
                ts.extra.appendSliceAssumeCapacity(casted);
            }

            repr.tag = switch (func.kind) {
                .normal => switch (func.params.len) {
                    0 => .func_zero,
                    1 => .func_one,
                    else => .func,
                },
                .variadic => switch (func.params.len) {
                    0 => .func_variadic_zero,
                    1 => .func_variadic_one,
                    else => .func_variadic,
                },
                .old_style => switch (func.params.len) {
                    0 => .func_variadic_zero,
                    1 => .func_variadic_one,
                    else => .func_variadic,
                },
            };
        },
        .pointer => |pointer| {
            repr.data[0] = @bitCast(pointer.child);
            if (pointer.decayed) |array| {
                repr.tag = .pointer_decayed;
                repr.data[1] = @bitCast(array);
            } else {
                repr.tag = .pointer;
            }
        },
        .array => |array| {
            repr.data[0] = @bitCast(array.elem);

            const extra_index: u32 = @intCast(ts.extra.items.len);
            switch (array.len) {
                .incomplete => {
                    repr.tag = .array_incomplete;
                },
                .fixed => |len| {
                    repr.tag = .array_fixed;
                    repr.data[1] = extra_index;
                    try ts.extra.appendSlice(gpa, &@as([2]u32, @bitCast(len)));
                },
                .static => |len| {
                    repr.tag = .array_static;
                    repr.data[1] = extra_index;
                    try ts.extra.appendSlice(gpa, &@as([2]u32, @bitCast(len)));
                },
                .variable => |expr| {
                    repr.tag = .array_variable;
                    repr.data[1] = @intFromEnum(expr);
                },
                .unspecified_variable => {
                    repr.tag = .array_unspecified_variable;
                },
            }
        },
        .vector => |vector| {
            repr.tag = .vector;
            repr.data[0] = @bitCast(vector.elem);
            repr.data[1] = vector.len;
        },
        .@"struct", .@"union" => |record| record: {
            repr.data[0] = @intFromEnum(record.name);
            const layout = record.layout orelse {
                std.debug.assert(record.fields.len == 0);
                repr.tag = switch (ty) {
                    .@"struct" => .struct_incomplete,
                    .@"union" => .union_incomplete,
                    else => unreachable,
                };
                break :record;
            };
            repr.tag = switch (ty) {
                .@"struct" => .@"struct",
                .@"union" => .@"union",
                else => unreachable,
            };

            const extra_index: u32 = @intCast(ts.extra.items.len);
            repr.data[1] = extra_index;

            const layout_size = 5;
            comptime std.debug.assert(@sizeOf(Type.Record.Layout) == @sizeOf(u32) * layout_size);
            const field_size = 10;
            comptime std.debug.assert(@sizeOf(Type.Record.Field) == @sizeOf(u32) * field_size);
            try ts.extra.ensureUnusedCapacity(gpa, record.fields.len * field_size + layout_size + 1);

            const casted_layout: *const [layout_size]u32 = @ptrCast(&layout);
            ts.extra.appendSliceAssumeCapacity(casted_layout);
            ts.extra.appendAssumeCapacity(@intCast(record.fields.len));

            for (record.fields) |*field| {
                const casted: *const [field_size]u32 = @ptrCast(field);
                ts.extra.appendSliceAssumeCapacity(casted);
            }
        },
        .@"enum" => |@"enum"| @"enum": {
            const tag_ty = @"enum".tag orelse {
                std.debug.assert(@"enum".fields.len == 0);
                repr.tag = .enum_incomplete;
                repr.data[0] = @intFromEnum(@"enum".name);
                break :@"enum";
            };
            repr.data[0] = @bitCast(tag_ty);
            repr.tag = if (@"enum".fixed) .enum_fixed else .@"enum";

            const extra_index: u32 = @intCast(ts.extra.items.len);
            repr.data[1] = extra_index;

            const field_size = 4;
            comptime std.debug.assert(@sizeOf(Type.Enum.Field) == @sizeOf(u32) * field_size);
            try ts.extra.ensureUnusedCapacity(gpa, @"enum".fields.len * field_size + 1 + 1);

            ts.extra.appendAssumeCapacity(@intFromEnum(@"enum".name));
            ts.extra.appendAssumeCapacity(@intCast(@"enum".fields.len));

            for (@"enum".fields) |*field| {
                const casted: *const [field_size]u32 = @ptrCast(field);
                ts.extra.appendSliceAssumeCapacity(casted);
            }
        },
        .typeof => |typeof| {
            repr.data[0] = @bitCast(typeof.base);
            if (typeof.expr) |some| {
                repr.tag = .typeof_expr;
                repr.data[1] = @intFromEnum(some);
            } else {
                repr.tag = .typeof;
            }
        },
        .typedef => |typedef| {
            repr.tag = .typedef;
            repr.data[0] = @bitCast(typedef.base);
            repr.data[1] = @intFromEnum(typedef.name);
        },
        .attributed => |attributed| {
            repr.data[0] = @bitCast(attributed.base);

            const attr_index: u32 = @intCast(ts.attributes.items.len);
            const attr_count: u32 = @intCast(attributed.attributes.len);
            try ts.attributes.appendSlice(gpa, attributed.attributes);
            if (attr_count > 1) {
                repr.tag = .attributed;
                const extra_index: u32 = @intCast(ts.extra.items.len);
                repr.data[0] = extra_index;
                try ts.extra.appendSlice(gpa, &.{ attr_index, attr_count });
            } else {
                repr.tag = .attributed_one;
                repr.data[0] = attr_index;
            }
        },
    }
    ts.types.set(index, repr);
}

pub fn initNamedTypes(ts: *TypeStore, comp: *Compilation) !void {
    const os = comp.target.os.tag;
    ts.wchar = switch (comp.target.cpu.arch) {
        .xcore => .uchar,
        .ve, .msp430 => .uint,
        .arm, .armeb, .thumb, .thumbeb => if (os != .windows and os != .netbsd and os != .openbsd) .uint else .int,
        .aarch64, .aarch64_be => if (!os.isDarwin() and os != .netbsd) .uint else .int,
        .x86_64, .x86 => if (os == .windows) .ushort else .int,
        else => .int,
    };

    const ptr_width = comp.target.ptrBitWidth();
    ts.ptrdiff = if (os == .windows and ptr_width == 64)
        .long_long
    else switch (ptr_width) {
        16 => .int,
        32 => .int,
        64 => .long,
        else => unreachable,
    };

    ts.size = if (os == .windows and ptr_width == 64)
        .ulong_long
    else switch (ptr_width) {
        16 => .uint,
        32 => .uint,
        64 => .ulong,
        else => unreachable,
    };

    ts.pid_t = switch (os) {
        .haiku => .long,
        // Todo: pid_t is required to "a signed integer type"; are there any systems
        // on which it is `short int`?
        else => .int,
    };

    ts.intmax = target_util.intMaxType(comp.target);
    ts.intptr = target_util.intPtrType(comp.target);
    ts.int16 = target_util.int16Type(comp.target);
    ts.int64 = target_util.int64Type(comp.target);
    ts.uint_least16_t = comp.intLeastN(16, .unsigned);
    ts.uint_least32_t = comp.intLeastN(32, .unsigned);

    ts.ns_constant_string = try ts.generateNsConstantStringType(comp);
    ts.va_list = try ts.generateVaListType(comp);
}

fn generateNsConstantStringType(ts: *TypeStore, comp: *Compilation) !QualType {
    const const_int_ptr: QualType = .{ .@"const" = true, ._index = .int_pointer };
    const const_char_ptr: QualType = .{ .@"const" = true, ._index = .char_pointer };

    var record: Type.Record = .{
        .name = try comp.internString("__NSConstantString_tag"),
        .layout = null,
        .fields = &.{},
    };
    const qt = try ts.put(comp.gpa, .{ .@"struct" = record });

    var fields: [4]Type.Record.Field = .{
        .{ .name = try comp.internString("isa"), .qt = const_int_ptr },
        .{ .name = try comp.internString("flags"), .qt = .int },
        .{ .name = try comp.internString("str"), .qt = const_char_ptr },
        .{ .name = try comp.internString("length"), .qt = .long },
    };
    record.fields = &fields;
    record.layout = record_layout.compute(&fields, qt, comp, null) catch unreachable;
    try ts.set(comp.gpa, .{ .@"struct" = record }, @intFromEnum(qt._index));

    return qt;
}

fn generateVaListType(ts: *TypeStore, comp: *Compilation) !QualType {
    const Kind = enum { aarch64_va_list, x86_64_va_list };
    const kind: Kind = switch (comp.target.cpu.arch) {
        .aarch64 => switch (comp.target.os.tag) {
            .windows => return .char_pointer,
            .ios, .macos, .tvos, .watchos => return .char_pointer,
            else => .aarch64_va_list,
        },
        .sparc, .wasm32, .wasm64, .bpfel, .bpfeb, .riscv32, .riscv64, .avr, .spirv32, .spirv64 => return .void_pointer,
        .powerpc => switch (comp.target.os.tag) {
            .ios, .macos, .tvos, .watchos, .aix => return .char_pointer,
            else => return .void, // unknown
        },
        .x86, .msp430 => return .char_pointer,
        .x86_64 => switch (comp.target.os.tag) {
            .windows => return .char_pointer,
            else => .x86_64_va_list,
        },
        else => return .void, // unknown
    };

    switch (kind) {
        .aarch64_va_list => {
            var record: Type.Record = .{
                .name = try comp.internString("__va_list_tag"),
                .layout = null,
                .fields = &.{},
            };
            const qt = try ts.put(comp.gpa, .{ .@"struct" = record });

            var fields: [5]Type.Record.Field = .{
                .{ .name = try comp.internString("__stack"), .qt = .void_pointer },
                .{ .name = try comp.internString("__gr_top"), .qt = .void_pointer },
                .{ .name = try comp.internString("__vr_top"), .qt = .void_pointer },
                .{ .name = try comp.internString("__gr_offs"), .qt = .int },
                .{ .name = try comp.internString("__vr_offs"), .qt = .int },
            };
            record.fields = &fields;
            record.layout = record_layout.compute(&fields, qt, comp, null) catch unreachable;
            try ts.set(comp.gpa, .{ .@"struct" = record }, @intFromEnum(qt._index));

            return qt;
        },
        .x86_64_va_list => {
            var record: Type.Record = .{
                .name = try comp.internString("__va_list_tag"),
                .layout = null,
                .fields = &.{},
            };
            const qt = try ts.put(comp.gpa, .{ .@"struct" = record });

            var fields: [4]Type.Record.Field = .{
                .{ .name = try comp.internString("gp_offset"), .qt = .uint },
                .{ .name = try comp.internString("fp_offset"), .qt = .uint },
                .{ .name = try comp.internString("overflow_arg_area"), .qt = .void_pointer },
                .{ .name = try comp.internString("reg_save_area"), .qt = .void_pointer },
            };
            record.fields = &fields;
            record.layout = record_layout.compute(&fields, qt, comp, null) catch unreachable;
            try ts.set(comp.gpa, .{ .@"struct" = record }, @intFromEnum(qt._index));

            return qt;
        },
    }
}

/// An unfinished Type
pub const Builder = struct {
    parser: *Parser,

    @"const": ?TokenIndex = null,
    atomic: ?TokenIndex = null,
    @"volatile": ?TokenIndex = null,
    restrict: ?TokenIndex = null,

    complex_tok: ?TokenIndex = null,
    bit_int_tok: ?TokenIndex = null,
    typedef: bool = false,
    typeof: ?QualType = null,

    type: Specifier = .none,
    /// When true an error is returned instead of adding a diagnostic message.
    /// Used for trying to combine typedef types.
    error_on_invalid: bool = false,

    pub const Specifier = union(enum) {
        none,
        void,
        /// GNU __auto_type extension
        auto_type,
        /// C23 auto
        c23_auto,
        nullptr_t,
        bool,
        char,
        schar,
        uchar,
        complex_char,
        complex_schar,
        complex_uchar,

        unsigned,
        signed,
        short,
        sshort,
        ushort,
        short_int,
        sshort_int,
        ushort_int,
        int,
        sint,
        uint,
        long,
        slong,
        ulong,
        long_int,
        slong_int,
        ulong_int,
        long_long,
        slong_long,
        ulong_long,
        long_long_int,
        slong_long_int,
        ulong_long_int,
        int128,
        sint128,
        uint128,
        complex_unsigned,
        complex_signed,
        complex_short,
        complex_sshort,
        complex_ushort,
        complex_short_int,
        complex_sshort_int,
        complex_ushort_int,
        complex_int,
        complex_sint,
        complex_uint,
        complex_long,
        complex_slong,
        complex_ulong,
        complex_long_int,
        complex_slong_int,
        complex_ulong_int,
        complex_long_long,
        complex_slong_long,
        complex_ulong_long,
        complex_long_long_int,
        complex_slong_long_int,
        complex_ulong_long_int,
        complex_int128,
        complex_sint128,
        complex_uint128,
        bit_int: u64,
        sbit_int: u64,
        ubit_int: u64,
        complex_bit_int: u64,
        complex_sbit_int: u64,
        complex_ubit_int: u64,

        fp16,
        float16,
        float,
        double,
        long_double,
        float128,
        complex,
        complex_float16,
        complex_float,
        complex_double,
        complex_long_double,
        complex_float128,

        // Any not simply constructed from specifier keywords.
        other: QualType,

        pub fn str(spec: Builder.Specifier, langopts: LangOpts) ?[]const u8 {
            return switch (spec) {
                .none => unreachable,
                .void => "void",
                .auto_type => "__auto_type",
                .c23_auto => "auto",
                .nullptr_t => "nullptr_t",
                .bool => if (langopts.standard.atLeast(.c23)) "bool" else "_Bool",
                .char => "char",
                .schar => "signed char",
                .uchar => "unsigned char",
                .unsigned => "unsigned",
                .signed => "signed",
                .short => "short",
                .ushort => "unsigned short",
                .sshort => "signed short",
                .short_int => "short int",
                .sshort_int => "signed short int",
                .ushort_int => "unsigned short int",
                .int => "int",
                .sint => "signed int",
                .uint => "unsigned int",
                .long => "long",
                .slong => "signed long",
                .ulong => "unsigned long",
                .long_int => "long int",
                .slong_int => "signed long int",
                .ulong_int => "unsigned long int",
                .long_long => "long long",
                .slong_long => "signed long long",
                .ulong_long => "unsigned long long",
                .long_long_int => "long long int",
                .slong_long_int => "signed long long int",
                .ulong_long_int => "unsigned long long int",
                .int128 => "__int128",
                .sint128 => "signed __int128",
                .uint128 => "unsigned __int128",
                .complex_char => "_Complex char",
                .complex_schar => "_Complex signed char",
                .complex_uchar => "_Complex unsigned char",
                .complex_unsigned => "_Complex unsigned",
                .complex_signed => "_Complex signed",
                .complex_short => "_Complex short",
                .complex_ushort => "_Complex unsigned short",
                .complex_sshort => "_Complex signed short",
                .complex_short_int => "_Complex short int",
                .complex_sshort_int => "_Complex signed short int",
                .complex_ushort_int => "_Complex unsigned short int",
                .complex_int => "_Complex int",
                .complex_sint => "_Complex signed int",
                .complex_uint => "_Complex unsigned int",
                .complex_long => "_Complex long",
                .complex_slong => "_Complex signed long",
                .complex_ulong => "_Complex unsigned long",
                .complex_long_int => "_Complex long int",
                .complex_slong_int => "_Complex signed long int",
                .complex_ulong_int => "_Complex unsigned long int",
                .complex_long_long => "_Complex long long",
                .complex_slong_long => "_Complex signed long long",
                .complex_ulong_long => "_Complex unsigned long long",
                .complex_long_long_int => "_Complex long long int",
                .complex_slong_long_int => "_Complex signed long long int",
                .complex_ulong_long_int => "_Complex unsigned long long int",
                .complex_int128 => "_Complex __int128",
                .complex_sint128 => "_Complex signed __int128",
                .complex_uint128 => "_Complex unsigned __int128",

                .fp16 => "__fp16",
                .float16 => "_Float16",
                .float => "float",
                .double => "double",
                .long_double => "long double",
                .float128 => "__float128",
                .complex => "_Complex",
                .complex_float16 => "_Complex _Float16",
                .complex_float => "_Complex float",
                .complex_double => "_Complex double",
                .complex_long_double => "_Complex long double",
                .complex_float128 => "_Complex __float128",

                else => null,
            };
        }
    };

    pub fn finish(b: Builder) Parser.Error!QualType {
        const qt: QualType = switch (b.type) {
            .none => blk: {
                if (b.typeof) |typeof| {
                    break :blk typeof;
                } else {
                    if (b.parser.comp.langopts.standard.atLeast(.c23)) {
                        try b.parser.err(.missing_type_specifier_c23);
                    } else {
                        try b.parser.err(.missing_type_specifier);
                    }
                    break :blk .int;
                }
            },
            .void => .void,
            .auto_type => .auto_type,
            .c23_auto => .c23_auto,
            .nullptr_t => unreachable, // nullptr_t can only be accessed via typeof(nullptr)
            .bool => .bool,
            .char => .char,
            .schar => .schar,
            .uchar => .uchar,

            .unsigned => .uint,
            .signed => .int,
            .short_int, .sshort_int, .short, .sshort => .short,
            .ushort, .ushort_int => .ushort,
            .int, .sint => .int,
            .uint => .uint,
            .long, .slong, .long_int, .slong_int => .long,
            .ulong, .ulong_int => .ulong,
            .long_long, .slong_long, .long_long_int, .slong_long_int => .long_long,
            .ulong_long, .ulong_long_int => .ulong_long,
            .int128, .sint128 => .int128,
            .uint128 => .uint128,

            .complex_char,
            .complex_schar,
            .complex_uchar,
            .complex_unsigned,
            .complex_signed,
            .complex_short_int,
            .complex_sshort_int,
            .complex_short,
            .complex_sshort,
            .complex_ushort,
            .complex_ushort_int,
            .complex_int,
            .complex_sint,
            .complex_uint,
            .complex_long,
            .complex_slong,
            .complex_long_int,
            .complex_slong_int,
            .complex_ulong,
            .complex_ulong_int,
            .complex_long_long,
            .complex_slong_long,
            .complex_long_long_int,
            .complex_slong_long_int,
            .complex_ulong_long,
            .complex_ulong_long_int,
            .complex_int128,
            .complex_sint128,
            .complex_uint128,
            => blk: {
                const base_qt: QualType = switch (b.type) {
                    .complex_char => .char,
                    .complex_schar => .schar,
                    .complex_uchar => .uchar,
                    .complex_unsigned => .uint,
                    .complex_signed => .int,
                    .complex_short_int, .complex_sshort_int, .complex_short, .complex_sshort => .short,
                    .complex_ushort, .complex_ushort_int => .ushort,
                    .complex_int, .complex_sint => .int,
                    .complex_uint => .uint,
                    .complex_long, .complex_slong, .complex_long_int, .complex_slong_int => .long,
                    .complex_ulong, .complex_ulong_int => .ulong,
                    .complex_long_long, .complex_slong_long, .complex_long_long_int, .complex_slong_long_int => .long_long,
                    .complex_ulong_long, .complex_ulong_long_int => .ulong_long,
                    .complex_int128, .complex_sint128 => .int128,
                    .complex_uint128 => .uint128,
                    else => unreachable,
                };
                if (b.complex_tok) |tok| try b.parser.errTok(.complex_int, tok);
                break :blk try base_qt.toComplex(b.parser.comp);
            },

            .bit_int, .sbit_int, .ubit_int, .complex_bit_int, .complex_ubit_int, .complex_sbit_int => |bits| blk: {
                const unsigned = b.type == .ubit_int or b.type == .complex_ubit_int;
                const complex = b.type == .complex_bit_int or b.type == .complex_ubit_int or b.type == .complex_sbit_int;
                const complex_str = if (complex) "_Complex " else "";

                if (unsigned) {
                    if (bits < 1) {
                        try b.parser.errStr(.unsigned_bit_int_too_small, b.bit_int_tok.?, complex_str);
                        return .invalid;
                    }
                } else {
                    if (bits < 2) {
                        try b.parser.errStr(.signed_bit_int_too_small, b.bit_int_tok.?, complex_str);
                        return .invalid;
                    }
                }
                if (bits > Compilation.bit_int_max_bits) {
                    try b.parser.errStr(if (unsigned) .unsigned_bit_int_too_big else .signed_bit_int_too_big, b.bit_int_tok.?, complex_str);
                    return .invalid;
                }
                if (b.complex_tok) |tok| try b.parser.errTok(.complex_int, tok);

                const qt = try b.parser.comp.type_store.put(b.parser.gpa, .{ .bit_int = .{
                    .signedness = if (unsigned) .unsigned else .signed,
                    .bits = @intCast(bits),
                } });
                break :blk if (complex) try qt.toComplex(b.parser.comp) else qt;
            },

            .fp16 => .fp16,
            .float16 => .float16,
            .float => .float,
            .double => .double,
            .long_double => .long_double,
            .float128 => .float128,

            .complex_float16,
            .complex_float,
            .complex_double,
            .complex_long_double,
            .complex_float128,
            .complex,
            => blk: {
                const base_qt: QualType = switch (b.type) {
                    .complex_float16 => .float16,
                    .complex_float => .float,
                    .complex_double => .double,
                    .complex_long_double => .long_double,
                    .complex_float128 => .float128,
                    .complex => .double,
                    else => unreachable,
                };
                if (b.type == .complex) try b.parser.errTok(.plain_complex, b.parser.tok_i - 1);
                break :blk try base_qt.toComplex(b.parser.comp);
            },

            .other => |qt| qt,
        };
        return b.finishQuals(qt);
    }

    pub fn finishQuals(b: Builder, qt: QualType) !QualType {
        var result_qt = qt;
        if (b.@"const" != null) result_qt.@"const" = true;
        if (b.@"volatile" != null) result_qt.@"volatile" = true;

        if (b.restrict) |restrict_tok| {
            switch (qt.base(b.parser.comp).type) {
                .array, .pointer => result_qt.restrict = true,
                else => {
                    try b.parser.errStr(.restrict_non_pointer, restrict_tok, try b.parser.typeStr(qt));
                },
            }
        }

        if (b.atomic) |atomic_tok| {
            _ = atomic_tok;
            // if (qt.isArray()) try b.parser.errStr(.atomic_array, atomic_tok, try b.parser.typeStr(qt));
            // if (qt.isFunc()) try b.parser.errStr(.atomic_func, atomic_tok, try b.parser.typeStr(qt));
            // if (qt.hasIncompleteSize()) try b.parser.errStr(.atomic_incomplete, atomic_tok, try b.parser.typeStr(qt));
            // TODO erro if quals
            // TODO make atomic
        }
        return result_qt;
    }

    fn cannotCombine(b: Builder, source_tok: TokenIndex) !void {
        if (b.error_on_invalid) return error.CannotCombine;
        const ty_str = b.type.str(b.parser.comp.langopts) orelse try b.parser.typeStr(try b.finish());
        if (b.typedef) {
            try b.parser.errStr(.cannot_combine_with_typedef, source_tok, ty_str);
        } else {
            try b.parser.errExtra(.cannot_combine_spec, source_tok, .{ .str = ty_str });
        }
    }

    fn duplicateSpec(b: *Builder, source_tok: TokenIndex, spec: []const u8) !void {
        if (b.error_on_invalid) return error.CannotCombine;
        if (b.parser.comp.langopts.emulate != .clang) return b.cannotCombine(source_tok);
        try b.parser.errStr(.duplicate_decl_spec, b.parser.tok_i, spec);
    }

    pub fn combineFromTypeof(b: *Builder, new: QualType, source_tok: TokenIndex) Compilation.Error!void {
        if (b.typedef) return b.parser.errStr(.cannot_combine_spec, source_tok, "type-name");
        if (b.typeof != null) return b.parser.errStr(.cannot_combine_spec, source_tok, "typeof");
        if (b.type != .none) return b.parser.errStr(.cannot_combine_with_typeof, source_tok, @tagName(b.type));
        b.type = .{ .other = new };
    }

    /// Try to combine type from typedef, returns true if successful.
    pub fn combineTypedef(b: *Builder, typedef_qt: QualType) bool {
        if (typedef_qt.isInvalid()) return false;
        if (b.type != .none) return false;

        b.error_on_invalid = true;
        defer b.error_on_invalid = false;

        b.typedef = true;
        b.type = .{ .other = typedef_qt };
        return true;
    }

    pub fn combine(b: *Builder, new: Builder.Specifier, source_tok: TokenIndex) !void {
        b.combineExtra(new, source_tok) catch |err| switch (err) {
            error.CannotCombine => unreachable,
            else => |e| return e,
        };
    }

    fn combineExtra(b: *Builder, new: Builder.Specifier, source_tok: TokenIndex) !void {
        if (b.typeof != null) {
            if (b.error_on_invalid) return error.CannotCombine;
            try b.parser.errStr(.cannot_combine_with_typeof, source_tok, @tagName(new));
        }

        switch (new) {
            .complex => b.complex_tok = source_tok,
            .bit_int => b.bit_int_tok = source_tok,
            else => {},
        }

        if (new == .int128 and !target_util.hasInt128(b.parser.comp.target)) {
            try b.parser.errStr(.type_not_supported_on_target, source_tok, "__int128");
        }

        b.type = switch (new) {
            else => switch (b.type) {
                .none => new,
                else => return b.cannotCombine(source_tok),
            },
            .signed => switch (b.type) {
                .none => .signed,
                .char => .schar,
                .short => .sshort,
                .short_int => .sshort_int,
                .int => .sint,
                .long => .slong,
                .long_int => .slong_int,
                .long_long => .slong_long,
                .long_long_int => .slong_long_int,
                .int128 => .sint128,
                .bit_int => |bits| .{ .sbit_int = bits },
                .complex => .signed,
                .complex_char => .schar,
                .complex_short => .sshort,
                .complex_short_int => .sshort_int,
                .complex_int => .sint,
                .complex_long => .slong,
                .complex_long_int => .slong_int,
                .complex_long_long => .slong_long,
                .complex_long_long_int => .slong_long_int,
                .complex_int128 => .sint128,
                .complex_bit_int => |bits| .{ .complex_sbit_int = bits },
                .signed,
                .sshort,
                .sshort_int,
                .sint,
                .slong,
                .slong_int,
                .slong_long,
                .slong_long_int,
                .sint128,
                .sbit_int,
                .complex_schar,
                .complex_signed,
                .complex_sshort,
                .complex_sshort_int,
                .complex_sint,
                .complex_slong,
                .complex_slong_int,
                .complex_slong_long,
                .complex_slong_long_int,
                .complex_sint128,
                .complex_sbit_int,
                => return b.duplicateSpec(source_tok, "signed"),
                else => return b.cannotCombine(source_tok),
            },
            .unsigned => switch (b.type) {
                .none => .unsigned,
                .char => .uchar,
                .short => .ushort,
                .short_int => .ushort_int,
                .int => .uint,
                .long => .ulong,
                .long_int => .ulong_int,
                .long_long => .ulong_long,
                .long_long_int => .ulong_long_int,
                .int128 => .uint128,
                .bit_int => |bits| .{ .ubit_int = bits },
                .complex => .unsigned,
                .complex_char => .uchar,
                .complex_short => .ushort,
                .complex_short_int => .ushort_int,
                .complex_int => .uint,
                .complex_long => .ulong,
                .complex_long_int => .ulong_int,
                .complex_long_long => .ulong_long,
                .complex_long_long_int => .ulong_long_int,
                .complex_int128 => .uint128,
                .complex_bit_int => |bits| .{ .complex_ubit_int = bits },
                .unsigned,
                .ushort,
                .ushort_int,
                .uint,
                .ulong,
                .ulong_int,
                .ulong_long,
                .ulong_long_int,
                .uint128,
                .ubit_int,
                .complex_uchar,
                .complex_unsigned,
                .complex_ushort,
                .complex_ushort_int,
                .complex_uint,
                .complex_ulong,
                .complex_ulong_int,
                .complex_ulong_long,
                .complex_ulong_long_int,
                .complex_uint128,
                .complex_ubit_int,
                => return b.duplicateSpec(source_tok, "unsigned"),
                else => return b.cannotCombine(source_tok),
            },
            .char => switch (b.type) {
                .none => .char,
                .unsigned => .uchar,
                .signed => .schar,
                .complex => .char,
                .complex_signed => .schar,
                .complex_unsigned => .uchar,
                else => return b.cannotCombine(source_tok),
            },
            .short => switch (b.type) {
                .none => .short,
                .unsigned => .ushort,
                .signed => .sshort,
                .int => .short_int,
                .sint => .sshort_int,
                .uint => .ushort_int,
                .complex => .short,
                .complex_signed => .sshort,
                .complex_unsigned => .ushort,
                else => return b.cannotCombine(source_tok),
            },
            .int => switch (b.type) {
                .none => .int,
                .signed => .sint,
                .unsigned => .uint,
                .short => .short_int,
                .sshort => .sshort_int,
                .ushort => .ushort_int,
                .long => .long_int,
                .slong => .slong_int,
                .ulong => .ulong_int,
                .long_long => .long_long_int,
                .slong_long => .slong_long_int,
                .ulong_long => .ulong_long_int,
                .complex => .int,
                .complex_signed => .sint,
                .complex_unsigned => .uint,
                .complex_short => .short_int,
                .complex_sshort => .sshort_int,
                .complex_ushort => .ushort_int,
                .complex_long => .long_int,
                .complex_slong => .slong_int,
                .complex_ulong => .ulong_int,
                .complex_long_long => .long_long_int,
                .complex_slong_long => .slong_long_int,
                .complex_ulong_long => .ulong_long_int,
                else => return b.cannotCombine(source_tok),
            },
            .long => switch (b.type) {
                .none => .long,
                .double => .long_double,
                .long => .long_long,
                .unsigned => .ulong,
                .signed => .long,
                .int => .long_int,
                .sint => .slong_int,
                .ulong => .ulong_long,
                .complex => .long,
                .complex_signed => .slong,
                .complex_unsigned => .ulong,
                .complex_long => .long_long,
                .complex_slong => .slong_long,
                .complex_ulong => .ulong_long,
                .complex_double => .long_double,
                else => return b.cannotCombine(source_tok),
            },
            .int128 => switch (b.type) {
                .none => .int128,
                .unsigned => .uint128,
                .signed => .sint128,
                .complex => .int128,
                .complex_signed => .sint128,
                .complex_unsigned => .uint128,
                else => return b.cannotCombine(source_tok),
            },
            .bit_int => switch (b.type) {
                .none => .{ .bit_int = new.bit_int },
                .unsigned => .{ .ubit_int = new.bit_int },
                .signed => .{ .sbit_int = new.bit_int },
                .complex => .{ .complex_bit_int = new.bit_int },
                .complex_signed => .{ .complex_sbit_int = new.bit_int },
                .complex_unsigned => .{ .complex_ubit_int = new.bit_int },
                else => return b.cannotCombine(source_tok),
            },
            .auto_type => switch (b.type) {
                .none => .auto_type,
                else => return b.cannotCombine(source_tok),
            },
            .c23_auto => switch (b.type) {
                .none => .c23_auto,
                else => return b.cannotCombine(source_tok),
            },
            .fp16 => switch (b.type) {
                .none => .fp16,
                else => return b.cannotCombine(source_tok),
            },
            .float16 => switch (b.type) {
                .none => .float16,
                .complex => .float16,
                else => return b.cannotCombine(source_tok),
            },
            .float => switch (b.type) {
                .none => .float,
                .complex => .float,
                else => return b.cannotCombine(source_tok),
            },
            .double => switch (b.type) {
                .none => .double,
                .long => .long_double,
                .complex_long => .long_double,
                .complex => .double,
                else => return b.cannotCombine(source_tok),
            },
            .float128 => switch (b.type) {
                .none => .float128,
                .complex => .float128,
                else => return b.cannotCombine(source_tok),
            },
            .complex => switch (b.type) {
                .none => .complex,
                .float16 => .float16,
                .float => .float,
                .double => .double,
                .long_double => .long_double,
                .float128 => .float128,
                .char => .char,
                .schar => .schar,
                .uchar => .uchar,
                .unsigned => .unsigned,
                .signed => .signed,
                .short => .short,
                .sshort => .sshort,
                .ushort => .ushort,
                .short_int => .short_int,
                .sshort_int => .sshort_int,
                .ushort_int => .ushort_int,
                .int => .int,
                .sint => .sint,
                .uint => .uint,
                .long => .long,
                .slong => .slong,
                .ulong => .ulong,
                .long_int => .long_int,
                .slong_int => .slong_int,
                .ulong_int => .ulong_int,
                .long_long => .long_long,
                .slong_long => .slong_long,
                .ulong_long => .ulong_long,
                .long_long_int => .long_long_int,
                .slong_long_int => .slong_long_int,
                .ulong_long_int => .ulong_long_int,
                .int128 => .int128,
                .sint128 => .sint128,
                .uint128 => .uint128,
                .bit_int => |bits| .{ .complex_bit_int = bits },
                .sbit_int => |bits| .{ .complex_sbit_int = bits },
                .ubit_int => |bits| .{ .complex_ubit_int = bits },
                .complex,
                .complex_float,
                .complex_double,
                .complex_long_double,
                .complex_float128,
                .complex_char,
                .complex_schar,
                .complex_uchar,
                .complex_unsigned,
                .complex_signed,
                .complex_short,
                .complex_sshort,
                .complex_ushort,
                .complex_short_int,
                .complex_sshort_int,
                .complex_ushort_int,
                .complex_int,
                .complex_sint,
                .complex_uint,
                .complex_long,
                .complex_slong,
                .complex_ulong,
                .complex_long_int,
                .complex_slong_int,
                .complex_ulong_int,
                .complex_long_long,
                .complex_slong_long,
                .complex_ulong_long,
                .complex_long_long_int,
                .complex_slong_long_int,
                .complex_ulong_long_int,
                .complex_int128,
                .complex_sint128,
                .complex_uint128,
                .complex_bit_int,
                .complex_sbit_int,
                .complex_ubit_int,
                => return b.duplicateSpec(source_tok, "_Complex"),
                else => return b.cannotCombine(source_tok),
            },
        };
    }

    pub fn fromType(comp: *const Compilation, qt: QualType) Builder.Specifier {
        return switch (qt.base(comp).type) {
            .void => .void,
            .nullptr_t => .nullptr_t,
            .bool => .bool,
            .int => |int| switch (int) {
                .char => .char,
                .schar => .schar,
                .uchar => .uchar,
                .short => .short,
                .ushort => .ushort,
                .int => .int,
                .uint => .uint,
                .long => .long,
                .ulong => .ulong,
                .long_long => .long_long,
                .ulong_long => .ulong_long,
                .int128 => .int128,
                .uint128 => .uint128,
            },
            .bit_int => |bit_int| if (bit_int.signedness == .unsigned) {
                return .{ .ubit_int = bit_int.bits };
            } else {
                return .{ .bit_int = bit_int.bits };
            },
            .float => |float| switch (float) {
                .fp16 => .fp16,
                .float16 => .float16,
                .float => .float,
                .double => .double,
                .long_double => .long_double,
                .float128 => .float128,
            },
            .complex => |complex| switch (complex.base(comp).type) {
                .int => |int| switch (int) {
                    .char => .char,
                    .schar => .schar,
                    .uchar => .uchar,
                    .short => .short,
                    .ushort => .ushort,
                    .int => .int,
                    .uint => .uint,
                    .long => .long,
                    .ulong => .ulong,
                    .long_long => .long_long,
                    .ulong_long => .ulong_long,
                    .int128 => .int128,
                    .uint128 => .uint128,
                },
                .bit_int => |bit_int| if (bit_int.signedness == .unsigned) {
                    return .{ .complex_ubit_int = bit_int.bits };
                } else {
                    return .{ .complex_bit_int = bit_int.bits };
                },
                .float => |float| switch (float) {
                    .fp16 => unreachable,
                    .float16 => .float16,
                    .float => .float,
                    .double => .double,
                    .long_double => .long_double,
                    .float128 => .float128,
                },
                else => unreachable,
            },
            else => .{ .other = qt },
        };
    }
};
