# Upstream Contribution: github.com/Eiton/vulkan Android Fixes

This directory contains patches and documentation for fixes that should be submitted upstream to the [Eiton/vulkan](https://github.com/Eiton/vulkan) Go Vulkan bindings library.

## Issue Summary

The `vk_wrapper_android.c` file in the Eiton/vulkan library has bugs that prevent compilation on Android:

### Problem 1: Invalid Architecture Flags

**File:** `vulkan_android.go`

The CGO CFLAGS include Apple-style `-arch amd64 -arch arm64` flags that are not recognized by the Android NDK clang compiler. The NDK already embeds the target architecture in the compiler binary name (e.g., `aarch64-linux-android34-clang`).

**Original:**
```go
// #cgo CFLAGS: -x objective-c -arch amd64 -arch arm64
```

**Fixed:**
```go
// #cgo CFLAGS: -x objective-c
```

### Problem 2: Undeclared Identifiers in vkInit()

**File:** `vk_wrapper_android.c` (lines 218-220)

The Android wrapper's `vkInit()` function references `getInstanceProcAddress` and `instance` variables that are **not declared** in the Android wrapper (unlike the desktop wrapper which has these).

**Original (broken):**
```c
vgo_vkCmdPushDescriptorSetKHR = (PFN_vkCmdPushDescriptorSetKHR)((*getInstanceProcAddress)(instance, "vkCmdPushDescriptorSetKHR"));
vgo_vkCmdBeginRendering = (PFN_vkCmdBeginRendering)((*getInstanceProcAddress)(instance, "vkCmdBeginRendering"));
vgo_vkCmdEndRendering = (PFN_vkCmdEndRendering)((*getInstanceProcAddress)(instance, "vkCmdEndRendering"));
```

**Compiler errors:**
```
vk_wrapper_android.c:220:71: error: use of undeclared identifier 'getInstanceProcAddress'
vk_wrapper_android.c:220:95: error: use of undeclared identifier 'instance'
```

### Solution

These function pointers must be loaded in `vkInitInstance()` (which receives a valid `VkInstance` parameter) rather than in `vkInit()` (which runs before any instance is created).

**Fixed `vkInitInstance()`:**
```c
int vkInitInstance(VkInstance instance) {
    if (!vgo_vkGetInstanceProcAddr) {
        return -1;
    }
    // Load extension function pointers that require a valid VkInstance
    vgo_vkCmdPushDescriptorSetKHR = (PFN_vkCmdPushDescriptorSetKHR)((*vgo_vkGetInstanceProcAddr)(instance, "vkCmdPushDescriptorSetKHR"));
    vgo_vkCmdBeginRendering = (PFN_vkCmdBeginRendering)((*vgo_vkGetInstanceProcAddr)(instance, "vkCmdBeginRendering"));
    vgo_vkCmdEndRendering = (PFN_vkCmdEndRendering)((*vgo_vkGetInstanceProcAddr)(instance, "vkCmdEndRendering"));
    return 0;
}
```

## Files

- `vk_wrapper_android.c.patch` - Unified diff patch for the C wrapper file
- `vulkan_android.go.patch` - Unified diff patch for the Go Android file
- `combined.patch` - Combined patch for both files

## Applying Patches

To test locally before submitting upstream:

```bash
cd $GOMODCACHE/github.com/!eiton/vulkan@v0.0.0-20251125114215-6585a2a8590b
patch -p1 < /path/to/combined.patch
```

## Upstream PR Template

```markdown
## Summary

Fix Android compilation errors in vk_wrapper_android.c

## Problem

The Android Vulkan wrapper fails to compile with errors:
- `use of undeclared identifier 'getInstanceProcAddress'`
- `use of undeclared identifier 'instance'`

Additionally, the CGO CFLAGS include Apple-style `-arch` flags that are invalid for Android NDK clang.

## Solution

1. Remove `-arch amd64 -arch arm64` from CFLAGS (NDK handles architecture via compiler name)
2. Move `vkCmdPushDescriptorSetKHR`, `vkCmdBeginRendering`, `vkCmdEndRendering` function pointer loading from `vkInit()` to `vkInitInstance()` where a valid VkInstance is available

## Testing

Tested with:
- Android NDK r27d
- Target: aarch64-linux-android34 (Android 14, ARM64)
- Ikemen-GO fighting game engine
```

## Related Issues

- Ikemen-GO Android build: Snapdragon 8 Elite requires Vulkan renderer as OpenGL ES 3.2 has compatibility issues
- Affects all Android devices using Vulkan 1.3 with dynamic rendering and push descriptors
