//  What Marea's AI can ask for. Each tool only PROPOSES: the worker hands the
//  proposal to Marea's logic, which shows it to the user when it has to,
//  does it, and answers. The model never touches the machine.
//
//  `looks`: it changes nothing (listing, looking). Marea does those without
//  asking, and they do not count against the actions a turn may take.
//  `why`: every action that changes something says what for, in the user's
//  language; that is what the user reads on the card before allowing it.

import { Type } from "typebox";

const pid = Type.Integer({ description: "The window's process number, from desktop_windows" });
const why = Type.String({ description: "What this is for, in a few words, in the user's language: they read it before allowing it", maxLength: 160 });
const x = Type.Number({ description: "Pixels from the left of desktop_look's picture of that window" });
const y = Type.Number({ description: "Pixels from the top of desktop_look's picture of that window" });

export const TOOLS = [
    {
        name: "desktop_windows",
        looks: true,
        description: "Lists the windows on the user's desktop: process number (pid), program, title, box, whether it is seen and whether it has the user's keyboard.",
        parameters: Type.Object({}),
    },
    {
        name: "desktop_look",
        looks: true,
        description: "A picture of one window, as it is now. Its pixels are the coordinates the other desktop tools take. Look again after anything that changes the page: what was at a point may not be there any more.",
        parameters: Type.Object({ pid }),
    },
    {
        name: "desktop_click",
        description: "Clicks in a window with your own pointer (not the user's). Look first: the point must be on what you mean to press.",
        parameters: Type.Object({
            pid, x, y,
            button: Type.Optional(Type.Union([Type.Literal("left"), Type.Literal("right"), Type.Literal("middle")])),
            count: Type.Optional(Type.Integer({ minimum: 1, maximum: 3, description: "2 for a double click" })),
            why,
        }),
    },
    {
        name: "desktop_type",
        description: "Types text into a window with your own keyboard, where its caret is (click the field first). ASCII only: no accents, ñ or emoji.",
        parameters: Type.Object({ pid, text: Type.String({ maxLength: 4000 }), why }),
    },
    {
        name: "desktop_key",
        description: "Presses one key in a window: enter, tab, escape, backspace, space, up, down, left, right, delete, home, end, pageup, pagedown, f1…f12.",
        parameters: Type.Object({ pid, key: Type.String({ maxLength: 16 }), why }),
    },
    {
        name: "desktop_hotkey",
        description: "A key with modifiers in a window: ctrl+l (a browser's address bar), ctrl+t, ctrl+w, ctrl+f, alt+left…",
        parameters: Type.Object({ pid, keys: Type.String({ maxLength: 32, description: "Like ctrl+shift+t" }), why }),
    },
    {
        name: "desktop_scroll",
        description: "Scrolls a window with the wheel, at a point over what scrolls (the page, not a sidebar).",
        parameters: Type.Object({
            pid, x, y,
            direction: Type.Union([Type.Literal("up"), Type.Literal("down"), Type.Literal("left"), Type.Literal("right")]),
            steps: Type.Optional(Type.Integer({ minimum: 1, maximum: 30 })),
            why,
        }),
    },
    {
        name: "desktop_drag",
        description: "Presses at one point of a window, glides to another and lets go.",
        parameters: Type.Object({ pid, x1: x, y1: y, x2: x, y2: y, why }),
    },
    {
        name: "desktop_focus",
        description: "Gives a window the user's keyboard and shows its workspace. It moves what the user sees: only when a window you need is not seen.",
        parameters: Type.Object({ pid, why }),
    },
    {
        name: "open_app",
        description: "Opens a program installed on the user's computer, by its name (Firefox, Files, Calculator…).",
        parameters: Type.Object({ name: Type.String({ maxLength: 80 }), why }),
    },
];

export function toolNamed(name) {
    return TOOLS.find((t) => t.name === name) ?? null;
}
