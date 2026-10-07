Please make it simple, elegant and NEVER overengineer. I want straightforward implementation that any human can read sequentially.

use conventional commit format with a SINGLE LINE MESSAGE. DO NOT COMMIT UNLESS REQUESTED. run tests before committing.

Always ask yourself if what you are about to commit is the best way to do it? Best long term maintainable clean architecture? AND SIMPLEST possible way to achieve the goal. not the implementation but the architecture.

system has BSD sed: `sed -i '' 's/old/new/g'`

## Build & Run (no Xcode project)

```sh
# Run tests
make test

# Build build/Scroblebler.app (add CONFIGURATION=release for a universal release build)
make app

# Check signature, architectures and minimum macOS of the built app
make verify

# Launch the fresh build
pkill -f "Scroblebler.app" 2>/dev/null; sleep 1
open build/Scroblebler.app

# Tail logs (real-time)
log stream --predicate 'subsystem == "com.tonioriol.scroblebler"' --info --debug

# Show recent logs (last N minutes/seconds)
log show --predicate 'subsystem == "com.tonioriol.scroblebler"' --info --debug --last 5m

# Filter logs by keyword
log show --predicate 'subsystem == "com.tonioriol.scroblebler"' --info --debug --last 5m 2>&1 | grep -i "backfill\|error\|scrobble"
```
