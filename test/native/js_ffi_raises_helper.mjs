// Helper for js_ffi_raises.march — throws on invalid input, returns bare value on success.
export function parseNum(s) {
  const n = parseInt(s, 10);
  if (isNaN(n)) throw new Error("not a number: " + s);
  return n;
}
