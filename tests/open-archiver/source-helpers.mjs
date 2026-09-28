import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

export function source(path) {
    return readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
}

// Extract the repository's two-space YAML blocks, not a general YAML parser.
// Unsupported or ambiguous shapes fail instead of silently omitting assertions.
export function entry(text, key) {
    const lines = text.split("\n");
    const matches = lines.flatMap((line, index) => line.startsWith(`${key}:`) ? [index] : []);
    assert.equal(matches.length, 1, `expected exactly one YAML entry for ${key}`);
    const start = matches[0];
    let end = start + 1;
    while (end < lines.length) {
        const line = lines[end];
        if (line.trim() && !line.trimStart().startsWith("#") && !line.startsWith("  ")) break;
        end += 1;
    }
    return {
        value: scalar(lines[start].slice(key.length + 1)),
        body: lines.slice(start + 1, end).map((line) =>
            line.startsWith("  ") ? line.slice(2) : line
        ).join("\n"),
    };
}

export function keys(text) {
    const result = [];
    for (const line of text.split("\n")) {
        if (!line.trim() || line.trimStart().startsWith("#") || line.startsWith("  ")) continue;
        const match = line.match(/^([A-Za-z0-9_-]+):(?:[ \t]|$)/);
        assert.ok(match, `unsupported YAML mapping line: ${line}`);
        assert.ok(!result.includes(match[1]), `duplicate YAML mapping key: ${match[1]}`);
        result.push(match[1]);
    }
    return result;
}

export function scalar(text) {
    const value = text.trim();
    if (value.startsWith('"')) return JSON.parse(value);
    if (value.startsWith("'")) {
        assert.ok(value.endsWith("'"), "unterminated YAML single-quoted scalar");
        return value.slice(1, -1).replaceAll("''", "'");
    }
    return value.replace(/\s+#.*$/, "");
}

export function items(text) {
    const result = [];
    for (const line of text.split("\n")) {
        if (line.startsWith("- ")) {
            result.push([line.slice(2)]);
        } else if (line.startsWith("  ") && result.length) {
            result.at(-1).push(line.slice(2));
        } else if (!line.trim()) {
            if (result.length) result.at(-1).push("");
        } else {
            assert.ok(line.trimStart().startsWith("#"), `unsupported YAML list line: ${line}`);
        }
    }
    return result.map((lines) => lines.join("\n"));
}

export function fields(text) {
    return Object.fromEntries(keys(text).map((key) => [key, entry(text, key).value]));
}
