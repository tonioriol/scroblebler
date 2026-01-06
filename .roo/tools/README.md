# Xcode Project Manager Tool

Add/remove Swift files from Xcode projects via xcodeproj Ruby gem.

## Usage

```typescript
// Add files
add_files_to_xcode({
  projectPath: "Scroblebler.xcodeproj",
  targetName: "Scroblebler", 
  action: "add",
  files: [{ path: "Scroblebler/Services/MyService.swift", group: "Scroblebler/Services" }]
})

// Remove files  
add_files_to_xcode({
  projectPath: "Scroblebler.xcodeproj",
  targetName: "Scroblebler",
  action: "remove", 
  files: [{ path: "Scroblebler/Services/MyService.swift" }]
})
```

## Setup Issues Solved

1. **@roo-code/types doesn't bundle** - Roo's esbuild can't resolve it. Use plain `zod` instead.
2. **defineCustomTool breaks** - Export plain object instead.
3. **Optional params validation** - Use `z.string().optional()` not `.partial()`.
4. **Tool caching** - Reload tools from Roo settings after changes.

## Requirements

```bash
gem install xcodeproj --user-install
```
