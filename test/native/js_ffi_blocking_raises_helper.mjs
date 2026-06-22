// Helper for js_ffi_blocking_raises.march — async, throws on negative input.
export async function asyncParsePos(s) {
  const n = parseInt(s, 10);
  if (isNaN(n) || n < 0) throw new Error("not a non-negative integer: " + s);
  return n;
}
