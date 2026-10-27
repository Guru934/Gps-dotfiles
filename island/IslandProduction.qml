// Production entrypoint for the GPS island.
// Keep the implementation in Island.qml so test and production instances
// cannot drift apart.  Start this through scripts/switch-island.fish.
import Quickshell

ShellRoot {
    Island {}
}
