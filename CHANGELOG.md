# Dropped Frame Alarm

## 2.1.0

- OSX no longer requires manual script modification

## 2.0.0

- Add Rendering and Encoding lagged frames.
  - This may require a small edit to the script on OS X
- Add separate alarm levels for each type of failed frame.
- Add new graph layers for other frame types
- Add settable color properties to graph source.
- Add setting for alarm repeat rate.
- Removed [`dump_obs`](https://gist.github.com/JustinLove/0f45f026c0c3f00b6bbbe364962d2774) debugging function and other unused code.
- Ran through LuaCheck linter
