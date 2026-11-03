// Helper for js_binary_string.march: byte strings built the way binary-reading
// externs build them (march_bytes_to_string), plus a clock for the O(1) check.
import { march_bytes_to_string } from "./march_runtime.mjs";

export function allBytes() {
  const b = new Uint8Array(256);
  for (let i = 0; i < 256; i++) b[i] = i;
  return march_bytes_to_string(b);
}

export function bigBinary(n) {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = i % 256;
  return march_bytes_to_string(b);
}

export function nowMs() { return Math.round(performance.now()); }
