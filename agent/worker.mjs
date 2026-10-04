//  Marea's AI worker: the Pi SDK, inside its sandbox (see `sandbox`), spoken
//  to by Marea's logic in JSON lines.
//
//  In, one message a line on stdin:
//    {"type":"start","model":"provider/id","locale":"es","history":[{"role":"user"|"assistant","text":"…"}]}
//    {"type":"prompt","text":"…","images":[{"path":"/state/…png"}]}
//    {"type":"result","id":"…","ok":true,"text":"…","denied":false,"image":{"path":"/state/…png"}}
//    {"type":"cancel"}   {"type":"shutdown"}
//  Out, one a line on stdout (logs go to stderr, never here):
//    ready {usable, model, reason}   delta {text}   propose {id, tool, args}
//    tool_start {id, tool}   tool_end {id, ok}   done   cancelled   failed {reason}
//
//  The rule this file keeps: the model PROPOSES. A tool call becomes a
//  `propose` and waits for Marea's `result`; whether it happened is what
//  Marea says, never what the model says.

import { createInterface } from "node:readline";
import { mkdirSync, readFileSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import {
    createAgentSession,
    createExtensionRuntime,
    defineTool,
    ModelRuntime,
    SessionManager,
    SettingsManager,
} from "@earendil-works/pi-coding-agent";
import { TOOLS, toolNamed } from "./tools.mjs";

const STATE = process.env.MAREA_AGENT_DIR || "/state";
const LIMITS = {
    line: 8 * 1024 * 1024,
    text: 8000,
    image: 6 * 1024 * 1024,
    history: 200,
    actions: 24,
    looks: 64,
};

const PROMPT = `You are Marea, a little ball of water with a face who lives at the top of the user's screen: their desktop companion. Calm, warm and brief.

You talk, and you can use the user's desktop with tools: a pointer and a keyboard of your own, apart from theirs (they keep working while you do; they see your mint cursor and the glow on the monitor you work on). You PROPOSE each action; Marea's side shows it to the user when it has to, does it, and tells you what happened. Never say you did something the result does not say happened.

Using the desktop, always the same loop: desktop_windows to find the window (its pid), desktop_look to see it, then act with the coordinates of that picture, then look again after anything that changes the page —pages move, a banner or a dialog appears—. A click on the wrong thing is worse than one more look. Prefer the keyboard where there is a shortcut: in a browser desktop_hotkey ctrl+l, desktop_type the address, desktop_key enter. Click a field before typing in it. Typing is ASCII only: no accents, ñ or emoji; write around it or say what the user will finish by hand.

You act as the user, in their accounts. Before anything that publishes, sends, buys, deletes, follows, likes, accepts terms or changes a setting, stop and ask them in the chat, even if it seems part of the task. Drafts, searches, reading and saving for later are fine. Never type a password or a payment detail; if a page asks for a login or a captcha, stop and say so. If an action comes back denied, accept it and look for another way; if there is none, say what is missing.

Answer in the user's language ({LOCALE}). Short sentences, no long lists or headings unless asked. When you finish a task on the desktop, say what you did and what you left for them.`;

//  An empty resource loader: no AGENTS.md, skills, prompts, themes or
//  extensions from anywhere. The context is what Marea gives, nothing found.
class EmptyLoader {
    constructor(systemPrompt) {
        this.systemPrompt = systemPrompt;
        this.runtime = createExtensionRuntime();
    }
    getExtensions() { return { extensions: [], errors: [], runtime: this.runtime }; }
    getSkills() { return { skills: [], diagnostics: [] }; }
    getPrompts() { return { prompts: [], diagnostics: [] }; }
    getThemes() { return { themes: [], diagnostics: [] }; }
    getAgentsFiles() { return { agentsFiles: [] }; }
    getSystemPrompt() { return this.systemPrompt; }
    getSystemPromptSource() { return undefined; }
    getAppendSystemPrompt() { return []; }
    getAppendSystemPromptSources() { return []; }
    getPathMetadata() { return new Map(); }
    extendResources() {}
    async reload() {}
}

function send(event) {
    process.stdout.write(JSON.stringify(event) + "\n");
}
function log(...what) {
    process.stderr.write(what.join(" ") + "\n");
}

//  A picture Marea left in the state folder, as Pi wants it. Only from there.
function picture(image) {
    if (!image || typeof image.path !== "string") return null;
    const path = resolve(image.path);
    if (!path.startsWith(STATE + "/")) throw new Error("image_outside_state");
    if (statSync(path).size > LIMITS.image) throw new Error("image_too_big");
    return { type: "image", data: readFileSync(path).toString("base64"), mimeType: "image/png" };
}

//  The thread Marea keeps, handed back on start: text only, honest placeholders
//  for what a restored answer does not have.
function restored(history, model) {
    const now = Date.now();
    return history.slice(-LIMITS.history).filter((h) => typeof h?.text === "string" && h.text).map((h) => h.role === "user"
        ? { role: "user", content: [{ type: "text", text: h.text }], timestamp: now }
        : {
            role: "assistant",
            content: [{ type: "text", text: h.text }],
            api: model?.api ?? "unknown",
            provider: model?.provider ?? "unknown",
            model: model?.id ?? "unknown",
            usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
            stopReason: "stop",
            timestamp: now,
        });
}

let session = null;
let usable = false;
let busy = null;            // the AbortController of the turn going on
let budget = { actions: 0, looks: 0 };
const waiting = new Map();  // proposal id → resolve(result)
let next = 0;

function propose(tool, args, signal) {
    return new Promise((done) => {
        const id = `p${++next}`;
        const spec = toolNamed(tool);
        const kind = spec?.looks ? "looks" : "actions";
        if (++budget[kind] > LIMITS[kind]) {
            done({ ok: false, text: `Too many ${kind === "looks" ? "looks" : "actions"} in one turn: stop and tell the user where you are.` });
            return;
        }
        waiting.set(id, done);
        signal?.addEventListener("abort", () => {
            if (waiting.delete(id)) done({ ok: false, text: "Cancelled by the user." });
        }, { once: true });
        send({ type: "propose", id, tool, args });
    });
}

function toolsForPi() {
    return TOOLS.map((t) => defineTool({
        name: t.name,
        label: t.name,
        description: t.description,
        parameters: t.parameters,
        execute: async (_callId, args, signal) => {
            const r = await propose(t.name, args ?? {}, signal);
            if (r.denied) {
                return { content: [{ type: "text", text: "The user denied this" + (r.text ? ` (${r.text})` : "") + ". Do not repeat it unless they ask." }], details: { denied: true } };
            }
            if (!r.ok) throw new Error(r.text || "it did not work");
            const content = [{ type: "text", text: r.text || "Done." }];
            const image = picture(r.image);
            if (image) content.push(image);
            return { content, details: {} };
        },
    }));
}

async function start(m) {
    const agentDir = join(STATE, "pi");
    const cwd = join(agentDir, "work");
    mkdirSync(cwd, { recursive: true, mode: 0o700 });
    const runtime = await ModelRuntime.create({
        authPath: join(agentDir, "auth.json"),
        modelsPath: join(agentDir, "models.json"),
        modelsStorePath: join(agentDir, "models-store.json"),
        allowModelNetwork: false,
        refreshOnCreate: false,
    });
    let model;
    if (typeof m.model === "string" && m.model.includes("/")) {
        const [provider, ...rest] = m.model.split("/");
        model = runtime.getModel(provider, rest.join("/"));
    }
    const locale = m.locale === "es" ? "Spanish" : m.locale === "en" ? "English" : "the user's";
    const created = await createAgentSession({
        cwd,
        agentDir,
        modelRuntime: runtime,
        model,
        //  Exactly ours: Pi's own bash, read, edit and write are not even
        //  registered, so nothing runs inside here claiming to be the host.
        tools: TOOLS.map((t) => t.name),
        customTools: toolsForPi(),
        resourceLoader: new EmptyLoader(PROMPT.replace("{LOCALE}", locale)),
        sessionManager: SessionManager.inMemory(cwd),
        settingsManager: SettingsManager.inMemory({ compaction: { enabled: false }, retry: { enabled: false } }),
    });
    session = created.session;
    const ok = session.model && session.model.provider !== "unknown" && session.model.id !== "unknown";
    usable = !!ok;
    if (Array.isArray(m.history) && m.history.length > 0) session.agent.state.messages = restored(m.history, session.model);
    const active = session.getActiveToolNames?.() ?? [];
    const extra = active.filter((n) => !toolNamed(n));
    if (extra.length > 0) throw new Error("unexpected_tools:" + extra.join(","));
    send({ type: "ready", usable, model: ok ? `${session.model.provider}/${session.model.id}` : null, reason: ok ? null : (model ? "model_unavailable" : "no_model") });
}

async function prompt(m) {
    if (!session || !usable) {
        send({ type: "failed", reason: session ? "no_model" : "not_started" });
        return;
    }
    if (busy) {
        send({ type: "failed", reason: "busy" });
        return;
    }
    const text = typeof m.text === "string" ? m.text.slice(0, LIMITS.text) : "";
    const images = (Array.isArray(m.images) ? m.images : []).slice(0, 3).map(picture).filter(Boolean);
    busy = new AbortController();
    budget = { actions: 0, looks: 0 };
    const signal = busy.signal;
    const unsubscribe = session.subscribe((e) => {
        if (signal.aborted) return;
        if (e.type === "tool_execution_start") send({ type: "tool_start", id: e.toolCallId, tool: e.toolName });
        else if (e.type === "tool_execution_end") send({ type: "tool_end", id: e.toolCallId, ok: e.isError !== true });
        else if (e.type === "message_update") {
            const d = e.assistantMessageEvent;
            if (d?.type === "text_delta" && typeof d.delta === "string") send({ type: "delta", text: d.delta });
        }
    });
    const stop = () => session?.abort();
    signal.addEventListener("abort", stop, { once: true });
    try {
        await session.prompt(text, images.length > 0 ? { images } : undefined);
        send({ type: signal.aborted ? "cancelled" : "done" });
    } catch (e) {
        send(signal.aborted ? { type: "cancelled" } : { type: "failed", reason: String(e?.message || e).slice(0, 300) });
    } finally {
        unsubscribe();
        busy = null;
    }
}

const input = createInterface({ input: process.stdin, crlfDelay: Infinity });
input.on("line", (line) => {
    if (line.length > LIMITS.line) return log("worker · a line too long, dropped");
    let m;
    try {
        m = JSON.parse(line);
    } catch {
        return log("worker · not JSON, dropped");
    }
    switch (m?.type) {
        case "start":
            start(m).catch((e) => send({ type: "failed", reason: "start: " + String(e?.message || e).slice(0, 300) }));
            break;
        case "prompt":
            prompt(m);
            break;
        case "result": {
            const done = waiting.get(m.id);
            if (!done) return;
            waiting.delete(m.id);
            done({ ok: m.ok === true, denied: m.denied === true, text: typeof m.text === "string" ? m.text.slice(0, 32 * 1024) : "", image: m.image });
            break;
        }
        case "cancel":
            busy?.abort();
            for (const [id, done] of waiting) {
                waiting.delete(id);
                done({ ok: false, text: "Cancelled by the user." });
            }
            break;
        case "shutdown":
            process.exit(0);
        default:
            log("worker · unknown message", String(m?.type));
    }
});
input.on("close", () => process.exit(0));
