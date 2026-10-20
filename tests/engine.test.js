// Run with: node tests/engine.test.js
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../src/TypingEngine.js"), "utf8")
    .replace(/^\.pragma library\s*$/m, "");
const E = {};
vm.runInNewContext(source + "\nObject.assign(E,{createGenerator,generate,createState,appendWords,typeChar,space,backspace,deleteWord,charCounts,wpm,rawWpm,accuracy,sample,consistency,result,configKey,totalTypedChars,copyWords});", { E, Math });

let passed = 0;
function test(name, fn) { fn(); passed += 1; console.log("ok  " + name); }
function typeString(s, text, end) {
    for (const ch of text) {
        if (ch === " ") E.space(s, end); else E.typeChar(s, ch, end);
    }
}
function seeded(seed) { return () => (seed = (seed * 1664525 + 1013904223) % 4294967296) / 4294967296; }

test("typing a word right counts every character", () => {
    const s = E.createState(["hello", "world"]);
    typeString(s, "hello ", false);
    assert.strictEqual(s.index, 1);
    assert.strictEqual(s.correctKeystrokes, 6);
    assert.strictEqual(E.accuracy(s), 100);
});

test("a wrong letter is a mistake and lowers accuracy", () => {
    const s = E.createState(["hello"]);
    typeString(s, "hexlo", false);
    assert.strictEqual(s.incorrectKeystrokes, 1);
    assert.strictEqual(E.accuracy(s), 80);
});

test("letters past the end are extra and capped", () => {
    const s = E.createState(["a", "b"]);
    for (let i = 0; i < 40; ++i) E.typeChar(s, "x", false);
    assert.strictEqual(s.typed[0].length, 1 + 19);
    const c = E.charCounts(s, false);
    assert.strictEqual(c.extra, 19);
});

test("space on an empty word does nothing", () => {
    const s = E.createState(["one", "two"]);
    assert.strictEqual(E.space(s, false), false);
    assert.strictEqual(s.index, 0);
});

test("space after a short word leaves its letters missed", () => {
    const s = E.createState(["testing", "x"]);
    typeString(s, "test ", false);
    assert.strictEqual(s.index, 1);
    const c = E.charCounts(s, false);
    assert.strictEqual(c.missed, 3);
    assert.strictEqual(c.correct, 4);
    assert.strictEqual(c.wordChars, 0);
});

test("backspace only steps back into a wrong word", () => {
    const s = E.createState(["cat", "dog", "emu"]);
    typeString(s, "cat ", false);
    assert.strictEqual(E.backspace(s), false);
    assert.strictEqual(s.index, 1);
    typeString(s, "dxg ", false);
    assert.strictEqual(s.index, 2);
    assert.strictEqual(E.backspace(s), true);
    assert.strictEqual(s.index, 1);
    assert.strictEqual(s.typed[1], "dxg");
    E.backspace(s); E.backspace(s);
    typeString(s, "og", false);
    assert.strictEqual(s.typed[1], "dog");
});

test("ctrl+backspace clears the word, then the wrong one before it", () => {
    const s = E.createState(["cat", "dog"]);
    typeString(s, "cxt do", false);
    E.deleteWord(s);
    assert.strictEqual(s.typed[1], "");
    E.deleteWord(s);
    assert.strictEqual(s.index, 0);
    assert.strictEqual(s.typed[0], "");
});

test("a words test ends when the last word is typed out", () => {
    const s = E.createState(["a", "bc"]);
    typeString(s, "a b", true);
    assert.strictEqual(s.finished, false);
    typeString(s, "c", true);
    assert.strictEqual(s.finished, true);
    assert.strictEqual(E.typeChar(s, "x", true), false);
});

test("a time test does not end on the last word", () => {
    const s = E.createState(["a"]);
    typeString(s, "a", false);
    assert.strictEqual(s.finished, false);
});

test("wpm is correct characters over five per minute", () => {
    const s = E.createState(["aaaaa", "bbbbb"]);
    typeString(s, "aaaaa bbbbb ", false);
    // 12 characters with spaces, 12 / 5 words over a quarter minute.
    assert.ok(Math.abs(E.wpm(s, 15) - 12 / 5 * 4) < 1e-9);
    assert.ok(Math.abs(E.rawWpm(s, 15) - E.wpm(s, 15)) < 1e-9);
});

test("a wrong word counts toward raw but not wpm", () => {
    const s = E.createState(["aaaaa", "bbbbb"]);
    typeString(s, "axaaa bbbbb ", false);
    assert.ok(E.rawWpm(s, 30) > E.wpm(s, 30));
});

test("samples are taken per stretch and drive consistency", () => {
    const s = E.createState(E.generate(60, {}, seeded(1)));
    for (let sec = 1; sec <= 10; ++sec) {
        for (const ch of s.words[s.index]) E.typeChar(s, ch, false);
        E.space(s, false);
        E.sample(s, sec);
    }
    assert.strictEqual(s.samples.length, 10);
    assert.ok(E.consistency(s.samples) > 0);
    const steady = [{ raw: 60 }, { raw: 60 }, { raw: 60 }];
    assert.strictEqual(Math.round(E.consistency(steady)), 100);
    const wild = [{ raw: 10 }, { raw: 200 }, { raw: 20 }, { raw: 190 }];
    assert.ok(E.consistency(wild) < 40);
});

test("result closes the last stretch and counts missed letters", () => {
    const s = E.createState(["abc", "def"]);
    typeString(s, "abc de", false);
    const r = E.result(s, 5);
    assert.strictEqual(r.correct, 5);
    assert.strictEqual(r.missed, 1);
    assert.strictEqual(r.samples.length, 1);
    assert.ok(r.accuracy === 100);
});

test("generator never repeats a word back to back", () => {
    const w = E.generate(500, {}, seeded(7));
    for (let i = 1; i < w.length; ++i) assert.notStrictEqual(w[i], w[i - 1]);
});

test("punctuation capitalises after a stop and adds marks", () => {
    const w = E.generate(300, { punctuation: true }, seeded(3));
    assert.ok(/^[A-Z]/.test(w[0]));
    for (let i = 1; i < w.length; ++i)
        if (/[.?!]$/.test(w[i - 1])) assert.ok(/^["]?[A-Z0-9]/.test(w[i]), w[i - 1] + " " + w[i]);
    assert.ok(w.some(x => /[,.]$/.test(x)));
});

test("numbers mode mixes in digits without leading zeros", () => {
    const w = E.generate(400, { numbers: true }, seeded(5));
    const nums = w.filter(x => /^[0-9]+$/.test(x));
    assert.ok(nums.length > 10);
    nums.forEach(n => assert.ok(n.length === 1 || n[0] !== "0", n));
});

test("every word can be typed on a plain keyboard", () => {
    E.copyWords().forEach(w => assert.ok(/^[A-Za-z]+$/.test(w), w));
});

test("config keys separate settings", () => {
    const a = E.configKey({ mode: "time", amount: 30, punctuation: false, numbers: false });
    const b = E.configKey({ mode: "time", amount: 30, punctuation: true, numbers: false });
    assert.notStrictEqual(a, b);
});

console.log("\n" + passed + " passed");
