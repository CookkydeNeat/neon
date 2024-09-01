// Couldn't find any runtime comparaison function so I made my own

/// Compare two integers and return the minimum value
pub fn min(comptime T: type, a: T, b: T) T {
    switch (@typeInfo(T)) {
        .Int => {
            if (a>b) {
                return b;
            } else {
                return a;
            }
        },
        else => {
            @compileError("Type " ++ @typeName(T) ++ " is not comparable");
        }
    }
}

/// Compare two integers and return the maximum value
pub fn max(comptime T: type, a: T, b: T) T {
    switch (@typeInfo(T)) {
        .Int => {
            if (a>b) {
                return a;
            } else {
                return b;
            }
        },
        else => {
            @compileError("Type " ++ @typeName(T) ++ " is not comparable");
        }
    }
}
