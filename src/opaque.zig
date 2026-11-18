//! Approved boundary for type-erased vtable/context pointers.

/// Recover a typed pointer from an erased vtable/context pointer.
/// The caller must uphold the alignment and lifetime invariants.
pub fn fromOpaque(comptime T: type, ptr: *anyopaque) *T {
    return @ptrCast(@alignCast(ptr));
}
