// js_byte_view_cache — a byte view's cache lookup must not compare string contents.
// JavaScriptCore compares a multi-megabyte string with itself in time linear in its
// length, so the old `===` scan made every byte_at on a 3.5 MB world file cost ~150 us
// in Safari and loading it never finished. Four cached strings of one length make V8
// pay the same way (each miss compares every byte), so this fails under node too.
import { march_string_byte_at } from "../march_runtime.mjs";

const n = 2_000_000;
const make = (last) => "é".repeat(n - 1) + last;   // non-byte units, so each needs a view
const [s, a, b, c] = ["a", "b", "c", "d"].map(make);
for (const t of [s, a, b, c]) march_string_byte_at(t, 0);   // cache holds all four; s is oldest

const t0 = performance.now();
let sum = 0;
for (let i = 0; i < 4000; i++) sum += march_string_byte_at(s, i);
const ms = performance.now() - t0;
console.log(sum === 2000 * (0xC3 + 0xA9) ? "bytes ok" : "bytes wrong: " + sum);
console.log(ms < 250 ? "lookups fast" : `lookups slow: ${Math.round(ms)} ms for 4000`);
