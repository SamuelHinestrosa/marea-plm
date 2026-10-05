import assert from "node:assert/strict";
import { test } from "node:test";
import { desktopPolicy, describeDesktopTool } from "./desktop-policy.mjs";
import { TOOLS } from "./tools.mjs";

test("Windows describes shared input without changing the compositor tool contract", () => {
    assert.match(desktopPolicy("win32"), /user's shared keyboard and pointer/);
    assert.match(desktopPolicy("linux"), /pointer and keyboard of your own/);
    for (const tool of TOOLS) {
        assert.equal(describeDesktopTool(tool,"linux"), tool.description);
        assert.doesNotMatch(describeDesktopTool(tool,"win32"), /own pointer|own keyboard|not the user's/);
    }
});

test("Windows launch descriptions do not promise compositor-only placement", () => {
    const tool=TOOLS.find(t=>t.name==="open_app");
    assert.match(tool.description,/monitor you work on/);
    assert.match(describeDesktopTool(tool,"win32"),/monitor parameter is currently unsupported/);
    assert.match(describeDesktopTool(tool,"win32"),/may activate itself/);
    assert.doesNotMatch(describeDesktopTool(tool,"win32"),/opens there|lit first|without taking/);
});
