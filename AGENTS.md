Please make it simple, elegant and NEVER overengineer. I want straightforward implementation that any human can read sequentially.

use conventional commit format with a SINGLE LINE MESSAGE. DO NOT COMMIT UNLESS REQUESTED. run tests before committing.

Always ask yourself if what you are about to commit is the best way to do it? Best long term maintainable clean architecture? AND SIMPLEST possible way to achieve the goal. not the implementation but the architecture.

Always update Scroblebler.xcodeproj/project.pbxproj file when making changes to the project structure. Adding/removing files, groups, targets, build phases etc.

system has GNU (not BSD) sed: `sed -i 's/old/new/g'`
