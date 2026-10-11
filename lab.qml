//@ pragma Env QSG_RENDER_LOOP=threaded
import Quickshell
import "lab"

// The prototype lab, not the shell: `LAB_SCENE=press qs -p lab.qml` puts one
// scene of prototypes at the bottom of the screen, scripted, for recording.
// Scenes: press, popup, bead, light. See lab/Lab.qml.
ShellRoot {
    Lab {}
}
