// Helper for js_bundle.march, in a subdirectory: the driver must copy it (and
// march_runtime.mjs, which it imports) next to the output.
import { march_bytes_to_string } from "../march_runtime.mjs";
export function greet() { return "hi " + march_bytes_to_string(new Uint8Array([111, 107])); }
