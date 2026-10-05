//  What Marea's AI can ask for. Each tool only PROPOSES: the worker hands the
//  proposal to Marea's logic, which shows it to the user when it has to,
//  does it, and answers. The model never touches the machine.
//
//  `looks`: it changes nothing (listing, looking). Marea does those without
//  asking, and they do not count against the actions a turn may take.
//  `why`: every action that changes something says what for, in the user's
//  language; that is what the user reads on the card before allowing it.

import { Type } from "typebox";

//  A window, as desktop_windows names it: its process (4521), or one of a
//  program's several windows (4521.3).
const pid = Type.Union([Type.Integer(), Type.String({ pattern: "^[0-9]+(\\.[0-9]+)?$" })], { description: "The window, as desktop_windows names it: 4521, or 4521.3 for one of a program's several windows" });
const why = Type.String({ description: "What this is for, in a few words, in the user's language: they read it before allowing it", maxLength: 160 });
//  When the user lets her use the computer without asking each step, the
//  steps marked `final` still ask: that is how the line is kept.
const final = Type.Optional(Type.Boolean({ description: "true when THIS step publishes, sends, buys, pays, deletes, follows, likes, accepts terms or changes a setting (the press of the button that does it): the user is always asked first" }));
const x = Type.Number({ description: "Pixels from the left of desktop_look's picture of that window" });
const y = Type.Number({ description: "Pixels from the top of desktop_look's picture of that window" });

export const TOOLS = [
    {
        name: "desktop_windows",
        looks: true,
        description: "Lists the windows on the user's desktop —process number (pid), program, title, box, the monitor it is seen on, whether it has the user's keyboard, and «dialog of PID» for a dialog— and the monitors. A dialog (save, open, a confirmation) is a window of its own, often of another program.",
        parameters: Type.Object({}),
    },
    {
        name: "desktop_look",
        looks: true,
        description: "A picture of one window, as it is now. Its pixels are the coordinates the other desktop tools take. If the program has a dialog open (save, open, a confirmation), the picture is the dialog, and the actions on that pid go to it. Look again after anything that changes the page: what was at a point may not be there any more.",
        parameters: Type.Object({ pid }),
    },
    {
        name: "desktop_click",
        description: "Clicks in a window with your own pointer (not the user's). Look first: the point must be on what you mean to press.",
        parameters: Type.Object({
            pid, x, y,
            button: Type.Optional(Type.Union([Type.Literal("left"), Type.Literal("right"), Type.Literal("middle")])),
            count: Type.Optional(Type.Integer({ minimum: 1, maximum: 3, description: "2 for a double click" })),
            why, final,
        }),
    },
    {
        name: "desktop_type",
        description: "Types text into a window with your own keyboard, where its caret is (click the field first). Any text: accents, ñ and emoji too.",
        parameters: Type.Object({ pid, text: Type.String({ maxLength: 4000 }), why, final }),
    },
    {
        name: "desktop_key",
        description: "Presses one key in a window: enter, tab, escape, backspace, space, up, down, left, right, delete, home, end, pageup, pagedown, f1…f12.",
        parameters: Type.Object({ pid, key: Type.String({ maxLength: 16 }), why, final }),
    },
    {
        name: "desktop_hotkey",
        description: "A key with modifiers in a window: ctrl+l (a browser's address bar), ctrl+t, ctrl+w, ctrl+f, alt+left…",
        parameters: Type.Object({ pid, keys: Type.String({ maxLength: 32, description: "Like ctrl+shift+t" }), why, final }),
    },
    {
        name: "desktop_scroll",
        description: "Scrolls a window with the wheel, at a point over what scrolls (the page, not a sidebar).",
        parameters: Type.Object({
            pid, x, y,
            direction: Type.Union([Type.Literal("up"), Type.Literal("down"), Type.Literal("left"), Type.Literal("right")]),
            steps: Type.Optional(Type.Integer({ minimum: 1, maximum: 30 })),
            why, final,
        }),
    },
    {
        name: "desktop_drag",
        description: "Presses at one point of a window, glides to another and lets go.",
        parameters: Type.Object({ pid, x1: x, y1: y, x2: x, y2: y, why, final }),
    },
    {
        name: "desktop_focus",
        description: "Gives a window the user's keyboard and shows its workspace. It moves what the user sees: only when a window you need is not seen.",
        parameters: Type.Object({ pid, why, final }),
    },
    {
        name: "desktop_to_monitor",
        description: "Moves a window to another monitor (desktop_windows says where each one is, and lists the monitors by number). For when the user names one: «on the other monitor».",
        parameters: Type.Object({ pid, monitor: Type.Integer({ minimum: 0, maximum: 7, description: "The monitor's number, from desktop_windows" }), why, final }),
    },
    {
        name: "open_app",
        description: "Opens a program installed on the user's computer, by its name (Firefox, Dolphin, Calculator…) or what it is (a file manager, a terminal, a browser). If none matches, it answers with the programs there are. Its window opens on the monitor where the user is: desktop_windows to find it.",
        parameters: Type.Object({ name: Type.String({ maxLength: 80 }), why, final }),
    },
];

export function toolNamed(name) {
    return TOOLS.find((t) => t.name === name) ?? null;
}
