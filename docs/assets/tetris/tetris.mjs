import { march_div_zero, march_float_round, march_float_to_string, march_int_and, march_int_div, march_int_div_euclid, march_int_div_floor, march_int_mod, march_int_mod_euclid, march_int_mod_floor, march_int_not, march_int_or, march_int_ovf, march_int_popcount, march_int_shl, march_int_shr, march_int_wrapping_add, march_int_wrapping_mul, march_int_wrapping_sub, march_int_xor, march_mod_zero, march_panic_error, march_panic_site, march_string_byte_length, march_string_concat_n, march_string_join, march_string_split, march_string_to_int, march_try_finally, march_unix_time, march_unix_time_ms } from "./march_runtime.mjs";

import { march_dom_set_timeout as dom_set_timeout, march_dom_prevent_default as dom_prevent_default, march_dom_event_key as dom_event_key, march_dom_add_event_listener as dom_add_event_listener, march_dom_set_style as dom_set_style, march_dom_class_add as dom_class_add, march_dom_set_attribute as dom_set_attribute, march_dom_get_attribute as dom_get_attribute, march_dom_set_text as dom_set_text, march_dom_append_child as dom_append_child, march_dom_create_element as dom_create_element, march_dom_body as dom_body, march_dom_get_element_by_id as dom_get_element_by_id } from "./march_dom.mjs";


const int_to_string   = { _0: ($_, x) => String(x) };
const bool_to_string  = { _0: ($_, x) => String(x) };
const int_to_float    = { _0: ($_, x) => x };
const float_to_int    = { _0: ($_, x) => Math.trunc(x) };
const float_truncate  = { _0: ($_, x) => Math.trunc(x) };
const string_is_empty = { _0: ($_, x) => x === "" };
const not_bool        = { _0: ($_, x) => !x };
const negate_int      = { _0: ($_, x) => march_int_ovf(-x, 3) };
const negate_float    = { _0: ($_, x) => -x };
const float_abs       = { _0: ($_, x) => Math.abs(x) };
const float_floor     = { _0: ($_, x) => Math.floor(x) };
const float_ceil      = { _0: ($_, x) => Math.ceil(x) };
const root_cap        = undefined;
const float_to_string = { _0: ($_, x) => march_float_to_string(x) };
const string_length = { _0: ($_, x) => march_string_byte_length(x) };
const string_byte_length = { _0: ($_, x) => march_string_byte_length(x) };
const int_and = { _0: ($_, a, b) => march_int_and(a, b) };
const int_or = { _0: ($_, a, b) => march_int_or(a, b) };
const int_xor = { _0: ($_, a, b) => march_int_xor(a, b) };
const int_shl = { _0: ($_, a, b) => march_int_shl(a, b) };
const int_shr = { _0: ($_, a, b) => march_int_shr(a, b) };
const int_mod = { _0: ($_, a, b) => march_int_mod(a, b) };
const int_div = { _0: ($_, a, b) => march_int_div(a, b) };
const int_mod_euclid = { _0: ($_, a, b) => march_int_mod_euclid(a, b) };
const int_div_euclid = { _0: ($_, a, b) => march_int_div_euclid(a, b) };
const int_mod_floor = { _0: ($_, a, b) => march_int_mod_floor(a, b) };
const int_div_floor = { _0: ($_, a, b) => march_int_div_floor(a, b) };
const int_wrapping_add = { _0: ($_, a, b) => march_int_wrapping_add(a, b) };
const int_wrapping_sub = { _0: ($_, a, b) => march_int_wrapping_sub(a, b) };
const int_wrapping_mul = { _0: ($_, a, b) => march_int_wrapping_mul(a, b) };
const int_not = { _0: ($_, a) => march_int_not(a) };
const int_popcount = { _0: ($_, a) => march_int_popcount(a) };
const int_abs = { _0: ($_, a) => Math.abs(a) };
const unix_time = { _0: ($_) => march_unix_time() };
const unix_time_ms = { _0: ($_) => march_unix_time_ms() };
const float_round = { _0: ($_, a) => march_float_round(a) };
const try_finally = { _0: ($_, a, c) => march_try_finally(a, c) };
const dom_get_element_by_id$clo = { _0: ($_, p0) => dom_get_element_by_id(p0) };
const dom_body$clo = { _0: ($_, ) => dom_body() };
const dom_create_element$clo = { _0: ($_, p0) => dom_create_element(p0) };
const dom_append_child$clo = { _0: ($_, p0, p1) => dom_append_child(p0, p1) };
const dom_set_text$clo = { _0: ($_, p0, p1) => dom_set_text(p0, p1) };
const dom_get_attribute$clo = { _0: ($_, p0, p1) => dom_get_attribute(p0, p1) };
const dom_set_attribute$clo = { _0: ($_, p0, p1, p2) => dom_set_attribute(p0, p1, p2) };
const dom_class_add$clo = { _0: ($_, p0, p1) => dom_class_add(p0, p1) };
const dom_set_style$clo = { _0: ($_, p0, p1, p2) => dom_set_style(p0, p1, p2) };
const dom_add_event_listener$clo = { _0: ($_, p0, p1, p2) => dom_add_event_listener(p0, p1, p2) };
const dom_event_key$clo = { _0: ($_, p0) => dom_event_key(p0) };
const dom_prevent_default$clo = { _0: ($_, p0) => dom_prevent_default(p0) };
const dom_set_timeout$clo = { _0: ($_, p0, p1) => dom_set_timeout(p0, p1) };

function __eq_Option(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "None": {
      return true;
    }
    case "Some": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Result(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Ok": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Err": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_List(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Nil": {
      return true;
    }
    case "Cons": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Hamt$HEntry(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "HEmpty": {
      return true;
    }
    case "HLeaf": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
    case "HBranch": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
    case "HCollision": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Map$Map(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "HamtMap": {
      if (!__eq_HEntry(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Map$HEntry(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "HEmpty": {
      return true;
    }
    case "HLeaf": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
    case "HBranch": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
    case "HCollision": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_LinearMap$LinearMap(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "LinearMapRep": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (!__eq_Map(a._2, b._2)) return false;
      return true;
    }
  }
  return true;
}

function __eq_LinearMap$LinearSlot(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "LinearSlotRep": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (!__eq_Map(a._3, b._3)) return false;
      return true;
    }
  }
  return true;
}

function __eq_IOList$IOList(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Empty": {
      return true;
    }
    case "Str": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Segments": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Deque$Deque(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Deque": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      if (!__eq_List(a._2, b._2)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Html$Safe(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Safe": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Html$TrustedHtml(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "TrustedHtml": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Html$TrustedAttr(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "TrustedAttr": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Html$TrustedUrl(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "TrustedUrl": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Html$TrustedCss(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "TrustedCss": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Html$TrustedJs(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "TrustedJs": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Http$Method(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Get": {
      return true;
    }
    case "Post": {
      return true;
    }
    case "Put": {
      return true;
    }
    case "Patch": {
      return true;
    }
    case "Delete": {
      return true;
    }
    case "Head": {
      return true;
    }
    case "Options": {
      return true;
    }
    case "Trace": {
      return true;
    }
    case "Connect": {
      return true;
    }
    case "Other": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Http$Scheme(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "SchemeHttp": {
      return true;
    }
    case "SchemeHttps": {
      return true;
    }
  }
  return true;
}

function __eq_Http$Status(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Status": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Http$Header(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Header": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_Http$UrlError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "InvalidScheme": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "MissingHost": {
      return true;
    }
    case "InvalidPort": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "MalformedUrl": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Http$Request(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Request": {
      if (!__eq_Method(a._0, b._0)) return false;
      if (!__eq_Scheme(a._1, b._1)) return false;
      if (a._2 !== b._2) return false;
      if (!__eq_Option(a._3, b._3)) return false;
      if (a._4 !== b._4) return false;
      if (!__eq_Option(a._5, b._5)) return false;
      if (!__eq_List(a._6, b._6)) return false;
      if (a._7 !== b._7) return false;
      return true;
    }
  }
  return true;
}

function __eq_Http$Response(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Response": {
      if (!__eq_Status(a._0, b._0)) return false;
      if (!__eq_List(a._1, b._1)) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
  }
  return true;
}

function __eq_HttpTransport$TransportError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ConnectionRefused": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "ConnTimeout": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "SendError": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "RecvError": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "ConnParseError": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Closed": {
      return true;
    }
    case "SchemeNotSupported": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_HttpClient$TransportError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ConnectionRefused": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "ConnTimeout": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "SendError": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "RecvError": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "ConnParseError": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Closed": {
      return true;
    }
  }
  return true;
}

function __eq_HttpClient$HttpError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "HttpTransportError": {
      if (!__eq_TransportError(a._0, b._0)) return false;
      return true;
    }
    case "StepError": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "TooManyRedirects": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "OutOfScope": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "RedirectRefused": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "MethodRefused": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_HttpClient$RequestStepEntry(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "RequestStepEntry": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_HttpClient$ResponseStepEntry(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ResponseStepEntry": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_HttpClient$ErrorRecovery(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Recover": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Fail": {
      if (!__eq_HttpError(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_HttpClient$ErrorStepEntry(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ErrorStepEntry": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_HttpClient$Client(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Client": {
      if (!__eq_List(a._0, b._0)) return false;
      if (!__eq_List(a._1, b._1)) return false;
      if (!__eq_List(a._2, b._2)) return false;
      if (a._3 !== b._3) return false;
      if (a._4 !== b._4) return false;
      if (a._5 !== b._5) return false;
      return true;
    }
  }
  return true;
}

function __eq_Seq$Step(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Continue": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Halt": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Seq$Seq(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Seq": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_File$FileError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "NotFound": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Permission": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "IsDirectory": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "NotEmpty": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "IoError": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_File$FileKind(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "RegularFile": {
      return true;
    }
    case "Directory": {
      return true;
    }
    case "Symlink": {
      return true;
    }
    case "OtherKind": {
      return true;
    }
  }
  return true;
}

function __eq_File$FileStat(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "FileStat": {
      if (a._0 !== b._0) return false;
      if (!__eq_FileKind(a._1, b._1)) return false;
      if (a._2 !== b._2) return false;
      if (a._3 !== b._3) return false;
      return true;
    }
  }
  return true;
}

function __eq_File$Seq(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Seq": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Sort$Heap(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "HLeaf": {
      return true;
    }
    case "HNode": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (!__eq_Heap(a._2, b._2)) return false;
      if (!__eq_Heap(a._3, b._3)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Csv$CsvError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "FileError": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "CsvParseError": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Csv$CsvRow(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "CsvEof": {
      return true;
    }
    case "Row": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_WebSocket$WsFrame(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "TextFrame": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "BinaryFrame": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Ping": {
      return true;
    }
    case "Pong": {
      return true;
    }
    case "Close": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_WebSocket$WsSocket(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "WsSocket": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_WebSocket$SelectResult(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "WsData": {
      if (!__eq_WsFrame(a._0, b._0)) return false;
      return true;
    }
    case "ActorMsg": {
      return true;
    }
    case "Timeout": {
      return true;
    }
  }
  return true;
}

function __eq_HttpServer$Upgrade(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "NoUpgrade": {
      return true;
    }
    case "WebSocketUpgrade": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_HttpServer$Conn(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Conn": {
      if (a._0 !== b._0) return false;
      if (!__eq_Atom(a._1, b._1)) return false;
      if (a._2 !== b._2) return false;
      if (!__eq_List(a._3, b._3)) return false;
      if (a._4 !== b._4) return false;
      if (!__eq_List(a._5, b._5)) return false;
      if (a._6 !== b._6) return false;
      if (a._7 !== b._7) return false;
      if (!__eq_List(a._8, b._8)) return false;
      if (a._9 !== b._9) return false;
      if (a._10 !== b._10) return false;
      if (!__eq_List(a._11, b._11)) return false;
      if (!__eq_Upgrade(a._12, b._12)) return false;
      return true;
    }
  }
  return true;
}

function __eq_HttpServer$Server(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Server": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      if (a._2 !== b._2) return false;
      if (a._3 !== b._3) return false;
      return true;
    }
  }
  return true;
}

function __eq_Set$SEntry(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "SEmpty": {
      return true;
    }
    case "SLeaf": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "SBranch": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
    case "SCollision": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Set$Set(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "HamtSet": {
      if (a._0 !== b._0) return false;
      if (!__eq_SEntry(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_HashMap$HEntry(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "HEmpty": {
      return true;
    }
    case "HLeaf": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
    case "HBranch": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
    case "HCollision": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_HashMap$HashMap(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "HamtHashMap": {
      if (!__eq_HEntry(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Array$TrieNode(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "TrieEmpty": {
      return true;
    }
    case "TrieLeaf": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
    case "TrieBranch": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Array$PVec(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "PVec": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (!__eq_TrieNode(a._2, b._2)) return false;
      if (!__eq_List(a._3, b._3)) return false;
      return true;
    }
  }
  return true;
}

function __eq_BigInt$BigInt(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "BigInt": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Decimal$Decimal(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Decimal": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_Duration$Duration(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Duration": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Bytes$Bytes(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Bytes": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Msgpack$Value(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Null": {
      return true;
    }
    case "Bool": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Int": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Str": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Bin": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
    case "Array": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
    case "Map": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Compress$Error(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "InvalidInput": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "InsufficientOutput": {
      return true;
    }
    case "Io": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Compress$Gzip$Level(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "BestSpeed": {
      return true;
    }
    case "Default": {
      return true;
    }
    case "BestCompression": {
      return true;
    }
    case "Custom": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Compress$Zstd$Level(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Fast": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Default": {
      return true;
    }
    case "Best": {
      return true;
    }
  }
  return true;
}

function __eq_Compress$Brotli$Mode(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Generic": {
      return true;
    }
    case "Text": {
      return true;
    }
    case "Font": {
      return true;
    }
  }
  return true;
}

function __eq_Compress$Brotli$Level(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Level": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Parser$Expected(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ExpLit": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "ExpLabel": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "ExpEof": {
      return true;
    }
  }
  return true;
}

function __eq_Parser$ParseErr(a, b) {
  if (a.pos !== b.pos) return false;
  if (!__eq_List(a.expected, b.expected)) return false;
  if (!__eq_List(a.context, b.context)) return false;
  return true;
}

function __eq_Parser$ParseReply(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ROk": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
    case "RFail": {
      if (!__eq_ParseErr(a._0, b._0)) return false;
      return true;
    }
    case "RCut": {
      if (!__eq_ParseErr(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Parser$Parser(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Parser": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Toml$TomlValue(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "TStr": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "TInt": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "TFloat": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "TBool": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "TNull": {
      return true;
    }
    case "TDatetime": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "TArray": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
    case "TTable": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Toml$TomlError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "TomlError": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
  }
  return true;
}

function __eq_Xml$XmlNode(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Element": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      if (!__eq_List(a._2, b._2)) return false;
      return true;
    }
    case "Text": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "CData": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Comment": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "ProcessingInstruction": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_Xml$XmlDoc(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "XmlDoc": {
      if (!__eq_Option(a._0, b._0)) return false;
      if (!__eq_XmlNode(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Xml$XmlError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "XmlError": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
  }
  return true;
}

function __eq_Xml$XmlFrame(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "XmlFrame": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      if (!__eq_List(a._2, b._2)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Yaml$YamlValue(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "YStr": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "YInt": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "YFloat": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "YBool": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "YNull": {
      return true;
    }
    case "YSeq": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
    case "YMap": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Yaml$YamlError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "YamlError": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
  }
  return true;
}

function __eq_Socket$SocketError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ConnectionFailed": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "WriteFailed": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "RecvFailed": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "RecvTimeout": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "SocketOptionFailed": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Dns$DnsError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "NotFound": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "ResolveError": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Udp$UdpError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "OpenFailed": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "ResolveFailed": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "ConnectFailed": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "SendFailed": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "RecvFailed": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Udp$UdpSocket(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "UdpSocket": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Udp$UdpAddr(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "UdpAddr": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Udp$UdpOptions(a, b) {
  if (a.reuse_addr !== b.reuse_addr) return false;
  if (a.reuse_port !== b.reuse_port) return false;
  if (a.broadcast !== b.broadcast) return false;
  if (a.gso !== b.gso) return false;
  if (a.gro !== b.gro) return false;
  if (a.recv_buffer !== b.recv_buffer) return false;
  if (a.send_buffer !== b.send_buffer) return false;
  return true;
}

function __eq_Udp$UdpStats(a, b) {
  if (a.rx_dropped !== b.rx_dropped) return false;
  if (a.tx_stalls !== b.tx_stalls) return false;
  return true;
}

function __eq_Process$ProcessResult(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ProcessResult": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
  }
  return true;
}

function __eq_Process$LiveProcess(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "LiveProcess": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_Cluster$NodeAddr(a, b) {
  if (a.host !== b.host) return false;
  if (a.port !== b.port) return false;
  return true;
}

function __eq_ClusterLoad$NodeLoad(a, b) {
  if (a.node_id !== b.node_id) return false;
  if (a.cpu_count !== b.cpu_count) return false;
  if (a.cpu_load_milli !== b.cpu_load_milli) return false;
  if (a.mem_total_mb !== b.mem_total_mb) return false;
  if (a.mem_avail_mb !== b.mem_avail_mb) return false;
  if (a.sampled_at !== b.sampled_at) return false;
  return true;
}

function __eq_ConsistentHash$HashRing(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "HashRing": {
      if (!__eq_List(a._0, b._0)) return false;
      if (!__eq_Map(a._1, b._1)) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
  }
  return true;
}

function __eq_Logger$Level(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Debug": {
      return true;
    }
    case "Info": {
      return true;
    }
    case "Warn": {
      return true;
    }
    case "Error": {
      return true;
    }
  }
  return true;
}

function __eq_Logger$LogValue(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "LStr": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "LInt": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "LFloat": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "LBool": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "LAtom": {
      if (!__eq_Atom(a._0, b._0)) return false;
      return true;
    }
    case "LNull": {
      return true;
    }
  }
  return true;
}

function __eq_Logger$LogField(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "LogField": {
      if (a._0 !== b._0) return false;
      if (!__eq_LogValue(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Logger$LogEntry(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "LogEntry": {
      if (!__eq_Level(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (a._3 !== b._3) return false;
      if (!__eq_List(a._4, b._4)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Logger$Appender(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Appender": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_Logger$AppenderCall(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "AppenderCall": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (a._3 !== b._3) return false;
      if (!__eq_List(a._4, b._4)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Diagnostics$CrashKind(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Panic": {
      return true;
    }
    case "ActorCrashed": {
      return true;
    }
    case "TaskFailed": {
      return true;
    }
  }
  return true;
}

function __eq_Diagnostics$DiagnosticValue(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "DStr": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "DInt": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "DFloat": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "DBool": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "DNull": {
      return true;
    }
  }
  return true;
}

function __eq_Diagnostics$SourceLocation(a, b) {
  if (a.file !== b.file) return false;
  if (a.line !== b.line) return false;
  return true;
}

function __eq_Diagnostics$StackFrame(a, b) {
  if (a.name !== b.name) return false;
  if (a.file !== b.file) return false;
  if (a.line !== b.line) return false;
  return true;
}

function __eq_Diagnostics$ProcessInfo(a, b) {
  if (a.pid !== b.pid) return false;
  if (a.supervised !== b.supervised) return false;
  return true;
}

function __eq_Diagnostics$CrashReport(a, b) {
  if (!__eq_CrashKind(a.kind, b.kind)) return false;
  if (a.message !== b.message) return false;
  if (!__eq_Option(a.location, b.location)) return false;
  if (!__eq_List(a.backtrace, b.backtrace)) return false;
  if (!__eq_ProcessInfo(a.process, b.process)) return false;
  if (!__eq_List(a.context, b.context)) return false;
  return true;
}

function __eq_Diagnostics$ObserverHandle(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ObserverHandle": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Diagnostics$DiagFrame(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "DiagFrame": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
  }
  return true;
}

function __eq_Diagnostics$DiagCrash(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "DiagCrash": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (!__eq_List(a._2, b._2)) return false;
      if (a._3 !== b._3) return false;
      if (a._4 !== b._4) return false;
      if (!__eq_List(a._5, b._5)) return false;
      if (a._6 !== b._6) return false;
      if (a._7 !== b._7) return false;
      return true;
    }
  }
  return true;
}

function __eq_Actor$InspectError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "InspectTimeout": {
      return true;
    }
    case "InspectDead": {
      return true;
    }
    case "InspectSelf": {
      return true;
    }
    case "InspectFailed": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Actor$Theory$ActorEnv(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "EnvMsg": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "EnvDown": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "EnvReply": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_Actor$Theory$ActorQueue(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "QEnd": {
      return true;
    }
    case "QThen": {
      if (!__eq_ActorEnv(a._0, b._0)) return false;
      if (!__eq_ActorQueue(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Actor$Theory$ActorMons(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "MonEnd": {
      return true;
    }
    case "MonThen": {
      if (a._0 !== b._0) return false;
      if (!__eq_ActorMons(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Flow$Stage(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Stage": {
      if (!__eq_Seq(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Json$JsonValue(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Null": {
      return true;
    }
    case "Bool": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Number": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Str": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Array": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
    case "Object": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Json$JsonPathStep(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "JPathField": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "JPathIndex": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Json$DecodeError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "DecodeError": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
  }
  return true;
}

function __eq_Json$JsonPath(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Key": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Index": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_JsonStream$Event(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "EvObjStart": {
      return true;
    }
    case "EvObjEnd": {
      return true;
    }
    case "EvArrStart": {
      return true;
    }
    case "EvArrEnd": {
      return true;
    }
    case "EvKey": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "EvStr": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "EvNum": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "EvNumRaw": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "EvBool": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "EvNull": {
      return true;
    }
  }
  return true;
}

function __eq_JsonStream$JsonStreamError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "EMalformed": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "EDepthLimit": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "ETokenLimit": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "ETruncated": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_JsonStream$JsonLimits(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "JsonLimits": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_JsonStream$JsMode(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "MTop": {
      return true;
    }
    case "MDone": {
      return true;
    }
    case "MArrFirst": {
      return true;
    }
    case "MArrValue": {
      return true;
    }
    case "MArrNext": {
      return true;
    }
    case "MObjFirst": {
      return true;
    }
    case "MObjKey": {
      return true;
    }
    case "MObjColon": {
      return true;
    }
    case "MObjValue": {
      return true;
    }
    case "MObjNext": {
      return true;
    }
  }
  return true;
}

function __eq_JsonStream$JsEsc(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "SPlain": {
      return true;
    }
    case "SEsc": {
      return true;
    }
    case "SHex": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_JsonStream$JsPartial(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "PNone": {
      return true;
    }
    case "PLit": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
    case "PStr": {
      if (!__eq_List(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      if (!__eq_JsEsc(a._2, b._2)) return false;
      if (a._3 !== b._3) return false;
      if (a._4 !== b._4) return false;
      return true;
    }
    case "PNum": {
      if (!__eq_List(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
  }
  return true;
}

function __eq_JsonStream$JsCfg(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "JsCfg": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (a._3 !== b._3) return false;
      return true;
    }
  }
  return true;
}

function __eq_JsonStream$JsState(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "StOk": {
      if (!__eq_JsCfg(a._0, b._0)) return false;
      if (!__eq_JsMode(a._1, b._1)) return false;
      if (!__eq_List(a._2, b._2)) return false;
      if (a._3 !== b._3) return false;
      if (!__eq_JsPartial(a._4, b._4)) return false;
      if (a._5 !== b._5) return false;
      return true;
    }
  }
  return true;
}

function __eq_JsonStream$JsFrame(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "FArr": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
    case "FObjK": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
    case "FObjV": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Recon$ActorInfo(a, b) {
  if (a.pid !== b.pid) return false;
  if (a.type_name !== b.type_name) return false;
  if (!__eq_List(a.names, b.names)) return false;
  if (a.status !== b.status) return false;
  if (a.mbox !== b.mbox) return false;
  if (a.held !== b.held) return false;
  if (!__eq_Option(a.parent, b.parent)) return false;
  if (a.children !== b.children) return false;
  if (a.slices !== b.slices) return false;
  if (a.msgs_in !== b.msgs_in) return false;
  if (a.msgs_out !== b.msgs_out) return false;
  if (a.crashes !== b.crashes) return false;
  if (a.child_crashes !== b.child_crashes) return false;
  return true;
}

function __eq_Recon$Supervision(a, b) {
  if (a.policy !== b.policy) return false;
  if (a.limit !== b.limit) return false;
  if (a.window_secs !== b.window_secs) return false;
  if (a.held !== b.held) return false;
  return true;
}

function __eq_Recon$TopRow(a, b) {
  if (a.pid !== b.pid) return false;
  if (a.type_name !== b.type_name) return false;
  if (!__eq_List(a.names, b.names)) return false;
  if (a.status !== b.status) return false;
  if (a.value !== b.value) return false;
  if (a.mbox !== b.mbox) return false;
  if (a.stack_bytes !== b.stack_bytes) return false;
  if (a.link !== b.link) return false;
  if (!__eq_Option(a.parent, b.parent)) return false;
  if (a.parent_type !== b.parent_type) return false;
  if (!__eq_Option(a.spawned_by, b.spawned_by)) return false;
  if (a.children !== b.children) return false;
  if (a.crashes !== b.crashes) return false;
  if (a.child_crashes !== b.child_crashes) return false;
  if (!__eq_Option(a.supervision, b.supervision)) return false;
  return true;
}

function __eq_Recon$SupNode(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "SupNode": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (!__eq_List(a._2, b._2)) return false;
      if (!__eq_List(a._3, b._3)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Recon$NodeStats(a, b) {
  if (a.actors !== b.actors) return false;
  if (a.queued !== b.queued) return false;
  if (!__eq_Option(a.rss_bytes, b.rss_bytes)) return false;
  if (!__eq_Option(a.live_objects, b.live_objects)) return false;
  if (a.schedulers !== b.schedulers) return false;
  if (a.crashes_total !== b.crashes_total) return false;
  return true;
}

function __eq_Recon$CrashReport(a, b) {
  if (a.seq !== b.seq) return false;
  if (a.kind !== b.kind) return false;
  if (!__eq_Option(a.pid, b.pid)) return false;
  if (a.type_name !== b.type_name) return false;
  if (!__eq_Option(a.supervisor, b.supervisor)) return false;
  if (a.restart !== b.restart) return false;
  if (a.at_ms !== b.at_ms) return false;
  return true;
}

function __eq_Recon$EpochReport(a, b) {
  if (a.current !== b.current) return false;
  if (!__eq_List(a.pins, b.pins)) return false;
  return true;
}

function __eq_Recon$FnVersion(a, b) {
  if (a.name !== b.name) return false;
  if (a.impl_hash !== b.impl_hash) return false;
  if (!__eq_Option(a.baseline_hash, b.baseline_hash)) return false;
  if (a.patched !== b.patched) return false;
  if (a.epoch !== b.epoch) return false;
  if (a.activated_at_ms !== b.activated_at_ms) return false;
  return true;
}

function __eq_Diagnose$Finding(a, b) {
  if (a.id !== b.id) return false;
  if (a.severity !== b.severity) return false;
  if (!__eq_List(a.rows, b.rows)) return false;
  if (a.next !== b.next) return false;
  return true;
}

function __eq_Trace$Limit(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "MaxEvents": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Rate": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_Trace$EventKind(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Sent": {
      return true;
    }
    case "Received": {
      return true;
    }
    case "Spawned": {
      return true;
    }
    case "Exited": {
      return true;
    }
    case "Dropped": {
      return true;
    }
  }
  return true;
}

function __eq_Trace$Options(a, b) {
  if (!__eq_List(a.fns, b.fns)) return false;
  if (!__eq_List(a.events, b.events)) return false;
  if (!__eq_List(a.pids, b.pids)) return false;
  return true;
}

function __eq_Trace$ActorEvent(a, b) {
  if (!__eq_EventKind(a.kind, b.kind)) return false;
  if (a.pid !== b.pid) return false;
  if (!__eq_Option(a.peer, b.peer)) return false;
  if (!__eq_Option(a.msg_tag, b.msg_tag)) return false;
  if (!__eq_Option(a.reason, b.reason)) return false;
  if (a.epoch !== b.epoch) return false;
  if (a.at_ns !== b.at_ns) return false;
  return true;
}

function __eq_Trace$TraceId(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "TraceId": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Trace$CallEvent(a, b) {
  if (a.caller !== b.caller) return false;
  if (a.fn_name !== b.fn_name) return false;
  if (a.epoch !== b.epoch) return false;
  if (a.at_ns !== b.at_ns) return false;
  return true;
}

function __eq_Trace$Batch(a, b) {
  if (!__eq_List(a.events, b.events)) return false;
  if (!__eq_List(a.actor_events, b.actor_events)) return false;
  if (a.recorded !== b.recorded) return false;
  if (a.dropped !== b.dropped) return false;
  if (a.rate_dropped !== b.rate_dropped) return false;
  if (a.queued !== b.queued) return false;
  if (a.done !== b.done) return false;
  if (!__eq_Option(a.why, b.why)) return false;
  return true;
}

function __eq_Trace$TraceError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "LimitOutOfRange": {
      return true;
    }
    case "UnknownFunction": {
      return true;
    }
    case "TooManySessions": {
      return true;
    }
    case "NoSuchSession": {
      return true;
    }
    case "BadRequest": {
      return true;
    }
    case "PidsRequired": {
      return true;
    }
    case "UnknownPid": {
      return true;
    }
    case "Unavailable": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Regex$RegexAtom(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "RALit": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "RAAny": {
      return true;
    }
    case "RAClass": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
    case "RADigit": {
      return true;
    }
    case "RAWord": {
      return true;
    }
    case "RASpace": {
      return true;
    }
    case "RANotDigit": {
      return true;
    }
    case "RANotWord": {
      return true;
    }
    case "RANotSpace": {
      return true;
    }
  }
  return true;
}

function __eq_Regex$RegexQuant(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "QOne": {
      return true;
    }
    case "QZeroOrMore": {
      return true;
    }
    case "QOneOrMore": {
      return true;
    }
    case "QOptional": {
      return true;
    }
  }
  return true;
}

function __eq_Regex$RegexItem(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "RegexItem": {
      if (!__eq_RegexAtom(a._0, b._0)) return false;
      if (!__eq_RegexQuant(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Regex$RegexPattern(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "RegexPattern": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
  }
  return true;
}

function __eq_Regex$RegexOpts(a, b) {
  if (a.case_insensitive !== b.case_insensitive) return false;
  if (a.multiline !== b.multiline) return false;
  return true;
}

function __eq_DateTime$Date(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Date": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
  }
  return true;
}

function __eq_DateTime$Time(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Time": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
  }
  return true;
}

function __eq_DateTime$DateTime(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "DateTime": {
      if (!__eq_Date(a._0, b._0)) return false;
      if (!__eq_Time(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_DateTime$Tz(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Tz": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_DateTime$LocalDateTime(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "LocalDateTime": {
      if (!__eq_DateTime(a._0, b._0)) return false;
      if (!__eq_Tz(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Queue$Queue(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Queue": {
      if (!__eq_List(a._0, b._0)) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_AhoCorasick$AcNode(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "AcNode": {
      if (!__eq_List(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      if (!__eq_List(a._2, b._2)) return false;
      return true;
    }
  }
  return true;
}

function __eq_AhoCorasick$Automaton(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Automaton": {
      if (!__eq_Array$PVec(a._0, b._0)) return false;
      if (!__eq_Array$PVec(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_AhoCorasick$Match(a, b) {
  if (a.start !== b.start) return false;
  if (a.stop !== b.stop) return false;
  if (a.pattern_index !== b.pattern_index) return false;
  if (a.pattern !== b.pattern) return false;
  return true;
}

function __eq_Random$Rng(a, b) {
  if (a.s0 !== b.s0) return false;
  if (a.s1 !== b.s1) return false;
  if (a.s2 !== b.s2) return false;
  if (a.s3 !== b.s3) return false;
  return true;
}

function __eq_Gen$Thunk(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Thunk": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Gen$GenTree(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "GenTree": {
      if (a._0 !== b._0) return false;
      if (!__eq_Thunk(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Gen$GenRng(a, b) {
  if (a.s0 !== b.s0) return false;
  if (a.s1 !== b.s1) return false;
  if (a.s2 !== b.s2) return false;
  if (a.s3 !== b.s3) return false;
  return true;
}

function __eq_Gen$Generator(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Generator": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Check$CheckConfig(a, b) {
  if (a.num_runs !== b.num_runs) return false;
  if (!__eq_Option(a.seed, b.seed)) return false;
  if (a.max_shrink_steps !== b.max_shrink_steps) return false;
  if (a.max_size !== b.max_size) return false;
  return true;
}

function __eq_Stats$QuantileMethod(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "InvertedCdf": {
      return true;
    }
    case "AveragedInvertedCdf": {
      return true;
    }
    case "ClosestObservation": {
      return true;
    }
    case "InterpolatedInvertedCdf": {
      return true;
    }
    case "Hazen": {
      return true;
    }
    case "Weibull": {
      return true;
    }
    case "Linear": {
      return true;
    }
    case "MedianUnbiased": {
      return true;
    }
    case "NormalUnbiased": {
      return true;
    }
  }
  return true;
}

function __eq_Plot$Color(a, b) {
  if (a.r !== b.r) return false;
  if (a.g !== b.g) return false;
  if (a.b !== b.b) return false;
  return true;
}

function __eq_Plot$Style(a, b) {
  if (!__eq_Color(a.line_color, b.line_color)) return false;
  if (!__eq_Color(a.fill_color, b.fill_color)) return false;
  if (a.line_width !== b.line_width) return false;
  if (a.point_radius !== b.point_radius) return false;
  if (a.font_size !== b.font_size) return false;
  if (a.opacity !== b.opacity) return false;
  return true;
}

function __eq_Plot$SeriesKind(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Line": {
      return true;
    }
    case "Scatter": {
      return true;
    }
    case "Bar": {
      return true;
    }
    case "HistogramSeries": {
      return true;
    }
  }
  return true;
}

function __eq_Plot$Series(a, b) {
  if (!__eq_SeriesKind(a.kind, b.kind)) return false;
  if (!__eq_List(a.xs, b.xs)) return false;
  if (!__eq_List(a.ys, b.ys)) return false;
  if (!__eq_Option(a.label, b.label)) return false;
  if (!__eq_Style(a.style, b.style)) return false;
  return true;
}

function __eq_Plot$Axis(a, b) {
  if (!__eq_Option(a.label, b.label)) return false;
  if (!__eq_Option(a.data_min, b.data_min)) return false;
  if (!__eq_Option(a.data_max, b.data_max)) return false;
  if (a.tick_count !== b.tick_count) return false;
  return true;
}

function __eq_Plot$Plot(a, b) {
  if (!__eq_Option(a.title, b.title)) return false;
  if (!__eq_List(a.series, b.series)) return false;
  if (!__eq_Axis(a.x_axis, b.x_axis)) return false;
  if (!__eq_Axis(a.y_axis, b.y_axis)) return false;
  if (a.width !== b.width) return false;
  if (a.height !== b.height) return false;
  if (a.margin !== b.margin) return false;
  if (a.show_legend !== b.show_legend) return false;
  if (a.show_grid !== b.show_grid) return false;
  return true;
}

function __eq_DataFrame$Value(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "IntVal": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "FloatVal": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "StrVal": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "BoolVal": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "NullVal": {
      return true;
    }
  }
  return true;
}

function __eq_DataFrame$Column(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "IntCol": {
      if (a._0 !== b._0) return false;
      if (!__eq_NativeIntArr(a._1, b._1)) return false;
      return true;
    }
    case "FloatCol": {
      if (a._0 !== b._0) return false;
      if (!__eq_NativeFloatArr(a._1, b._1)) return false;
      return true;
    }
    case "StrCol": {
      if (a._0 !== b._0) return false;
      if (!__eq_TypedArray(a._1, b._1)) return false;
      return true;
    }
    case "BoolCol": {
      if (a._0 !== b._0) return false;
      if (!__eq_TypedArray(a._1, b._1)) return false;
      return true;
    }
    case "NullableIntCol": {
      if (a._0 !== b._0) return false;
      if (!__eq_NativeIntArr(a._1, b._1)) return false;
      if (!__eq_TypedArray(a._2, b._2)) return false;
      return true;
    }
    case "NullableFloatCol": {
      if (a._0 !== b._0) return false;
      if (!__eq_NativeFloatArr(a._1, b._1)) return false;
      if (!__eq_TypedArray(a._2, b._2)) return false;
      return true;
    }
    case "NullableStrCol": {
      if (a._0 !== b._0) return false;
      if (!__eq_TypedArray(a._1, b._1)) return false;
      if (!__eq_TypedArray(a._2, b._2)) return false;
      return true;
    }
    case "NullableBoolCol": {
      if (a._0 !== b._0) return false;
      if (!__eq_TypedArray(a._1, b._1)) return false;
      if (!__eq_TypedArray(a._2, b._2)) return false;
      return true;
    }
  }
  return true;
}

function __eq_DataFrame$Row(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Row": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_DataFrame$DataFrame(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "DataFrame": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_DataFrame$ColumnBuilder(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "IntBuilder": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
    case "FloatBuilder": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
    case "StrBuilder": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
    case "BoolBuilder": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
    case "NullBuilder": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_DataFrame$ColExpr(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Col": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "LitInt": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "LitFloat": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "LitStr": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "LitBool": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Eq": {
      if (!__eq_ColExpr(a._0, b._0)) return false;
      if (!__eq_ColExpr(a._1, b._1)) return false;
      return true;
    }
    case "Neq": {
      if (!__eq_ColExpr(a._0, b._0)) return false;
      if (!__eq_ColExpr(a._1, b._1)) return false;
      return true;
    }
    case "Lt": {
      if (!__eq_ColExpr(a._0, b._0)) return false;
      if (!__eq_ColExpr(a._1, b._1)) return false;
      return true;
    }
    case "Lte": {
      if (!__eq_ColExpr(a._0, b._0)) return false;
      if (!__eq_ColExpr(a._1, b._1)) return false;
      return true;
    }
    case "Gt": {
      if (!__eq_ColExpr(a._0, b._0)) return false;
      if (!__eq_ColExpr(a._1, b._1)) return false;
      return true;
    }
    case "Gte": {
      if (!__eq_ColExpr(a._0, b._0)) return false;
      if (!__eq_ColExpr(a._1, b._1)) return false;
      return true;
    }
    case "And": {
      if (!__eq_ColExpr(a._0, b._0)) return false;
      if (!__eq_ColExpr(a._1, b._1)) return false;
      return true;
    }
    case "Or": {
      if (!__eq_ColExpr(a._0, b._0)) return false;
      if (!__eq_ColExpr(a._1, b._1)) return false;
      return true;
    }
    case "Not": {
      if (!__eq_ColExpr(a._0, b._0)) return false;
      return true;
    }
    case "Add": {
      if (!__eq_ColExpr(a._0, b._0)) return false;
      if (!__eq_ColExpr(a._1, b._1)) return false;
      return true;
    }
    case "Sub": {
      if (!__eq_ColExpr(a._0, b._0)) return false;
      if (!__eq_ColExpr(a._1, b._1)) return false;
      return true;
    }
    case "Mul": {
      if (!__eq_ColExpr(a._0, b._0)) return false;
      if (!__eq_ColExpr(a._1, b._1)) return false;
      return true;
    }
    case "Div": {
      if (!__eq_ColExpr(a._0, b._0)) return false;
      if (!__eq_ColExpr(a._1, b._1)) return false;
      return true;
    }
    case "StrContains": {
      if (!__eq_ColExpr(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "StrStartsWith": {
      if (!__eq_ColExpr(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "StrEndsWith": {
      if (!__eq_ColExpr(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "IsNull": {
      if (!__eq_ColExpr(a._0, b._0)) return false;
      return true;
    }
    case "IsNotNull": {
      if (!__eq_ColExpr(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_DataFrame$SortDir(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Asc": {
      return true;
    }
    case "Desc": {
      return true;
    }
  }
  return true;
}

function __eq_DataFrame$JoinKind(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Inner": {
      return true;
    }
    case "Left": {
      return true;
    }
    case "Right": {
      return true;
    }
    case "Outer": {
      return true;
    }
  }
  return true;
}

function __eq_DataFrame$Plan(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Source": {
      if (!__eq_DataFrame(a._0, b._0)) return false;
      return true;
    }
    case "Select": {
      if (!__eq_Plan(a._0, b._0)) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
    case "Filter": {
      if (!__eq_Plan(a._0, b._0)) return false;
      if (!__eq_ColExpr(a._1, b._1)) return false;
      return true;
    }
    case "WithColumn": {
      if (!__eq_Plan(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
    case "SortBy": {
      if (!__eq_Plan(a._0, b._0)) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
    case "Limit": {
      if (!__eq_Plan(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "Offset": {
      if (!__eq_Plan(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "Rename": {
      if (!__eq_Plan(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
    case "DropCols": {
      if (!__eq_Plan(a._0, b._0)) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
    case "Join": {
      if (!__eq_Plan(a._0, b._0)) return false;
      if (!__eq_Plan(a._1, b._1)) return false;
      if (!__eq_List(a._2, b._2)) return false;
      if (!__eq_JoinKind(a._3, b._3)) return false;
      return true;
    }
  }
  return true;
}

function __eq_DataFrame$LazyFrame(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "LazyFrame": {
      if (!__eq_Plan(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_DataFrame$CsvWriteOpts(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "CsvWriteOpts": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
  }
  return true;
}

function __eq_DataFrame$AggExpr(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Sum": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Mean": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Min": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Max": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Count": {
      return true;
    }
    case "CountDistinct": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Std": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Variance": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "First": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Last": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Median": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "AggAs": {
      if (!__eq_AggExpr(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_DataFrame$GroupKey(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "GroupKey": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_DataFrame$GroupedFrame(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "GroupedFrame": {
      if (!__eq_DataFrame(a._0, b._0)) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_DataFrame$ColStats(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ColStats": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (!__eq_Option(a._3, b._3)) return false;
      if (!__eq_Option(a._4, b._4)) return false;
      if (!__eq_Option(a._5, b._5)) return false;
      if (!__eq_Option(a._6, b._6)) return false;
      if (!__eq_Option(a._7, b._7)) return false;
      if (!__eq_Option(a._8, b._8)) return false;
      if (!__eq_Option(a._9, b._9)) return false;
      return true;
    }
  }
  return true;
}

function __eq_DataFrame$WindowExpr(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "RowNum": {
      return true;
    }
    case "Rank": {
      if (a._0 !== b._0) return false;
      if (!__eq_SortDir(a._1, b._1)) return false;
      return true;
    }
    case "DenseRank": {
      if (a._0 !== b._0) return false;
      if (!__eq_SortDir(a._1, b._1)) return false;
      return true;
    }
    case "RunningSum": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "RunningMean": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Lag": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (!__eq_Value(a._2, b._2)) return false;
      return true;
    }
    case "Lead": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (!__eq_Value(a._2, b._2)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Tls$TlsVersion(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Tls12": {
      return true;
    }
    case "Tls13": {
      return true;
    }
  }
  return true;
}

function __eq_Tls$TlsError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "TlsHandshakeFailed": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "TlsCertError": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "TlsReadError": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "TlsWriteError": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "TlsContextError": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "TlsReadTimeout": {
      return true;
    }
  }
  return true;
}

function __eq_Tls$TlsConfig(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "TlsConfig": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (!__eq_List(a._3, b._3)) return false;
      if (!__eq_TlsVersion(a._4, b._4)) return false;
      if (a._5 !== b._5) return false;
      return true;
    }
  }
  return true;
}

function __eq_Tls$TlsCtx(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "TlsCtx": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Tls$TlsConn(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "TlsConn": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_UUID$UUID(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "UUID": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Channel$Socket(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Socket": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (!__eq_List(a._3, b._3)) return false;
      if (a._4 !== b._4) return false;
      return true;
    }
  }
  return true;
}

function __eq_Channel$HandleResult(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Reply": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
    case "NoReply": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Stop": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_Channel$ChannelMailbox(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ChannelIn": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
    case "ChannelBroadcast": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
    case "ChannelBroadcastFrom": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (a._3 !== b._3) return false;
      return true;
    }
    case "ChannelPush": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "ChannelLeave": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "ChannelStop": {
      return true;
    }
  }
  return true;
}

function __eq_Channel$PubSubMsg(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "PubSubSubscribe": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "PubSubUnsubscribe": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "PubSubBroadcast": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (a._3 !== b._3) return false;
      return true;
    }
  }
  return true;
}

function __eq_Channel$BroadcastMsg(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "BroadcastMsg": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_Channel$LeaveReason(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "NormalLeave": {
      return true;
    }
    case "Disconnect": {
      return true;
    }
    case "Kicked": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Channel$ChannelRoute(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ChannelRoute": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_Channel$ChannelMsg(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ChannelMsg": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (a._3 !== b._3) return false;
      if (a._4 !== b._4) return false;
      return true;
    }
  }
  return true;
}

function __eq_PubSub$PubSubState(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "PubSubState": {
      if (!__eq_Map(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_ChannelServer$JoinResult(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "JoinOk": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "JoinErr": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_ChannelServer$ChannelConfig(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ChannelConfig": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (a._3 !== b._3) return false;
      if (a._4 !== b._4) return false;
      if (a._5 !== b._5) return false;
      return true;
    }
  }
  return true;
}

function __eq_ChannelSocket$SocketConfig(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "SocketConfig": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      if (a._2 !== b._2) return false;
      if (!__eq_List(a._3, b._3)) return false;
      return true;
    }
  }
  return true;
}

function __eq_ChannelSocket$ActiveChannels(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ActiveChannels": {
      if (!__eq_Map(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Presence$PresenceMeta(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "PresenceMeta": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_Presence$PresenceEntry(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "PresenceEntry": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Presence$PresenceState(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "PresenceState": {
      if (!__eq_Map(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Config$Value(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "CfgInt": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "CfgFloat": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "CfgString": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "CfgBool": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "CfgAtom": {
      if (!__eq_Atom(a._0, b._0)) return false;
      return true;
    }
    case "CfgList": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Config$Codec(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Codec": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
  }
  return true;
}

function __eq_Config$Key(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Key": {
      if (a._0 !== b._0) return false;
      if (!__eq_Codec(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Config$Error(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "KeyMissing": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "KeyWrongType": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
  }
  return true;
}

function __eq_Cli$FlagArity(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "BoolFlag": {
      return true;
    }
    case "ValueFlag": {
      return true;
    }
  }
  return true;
}

function __eq_Cli$FlagSpec(a, b) {
  if (a.long !== b.long) return false;
  if (!__eq_Option(a.short, b.short)) return false;
  if (!__eq_FlagArity(a.arity, b.arity)) return false;
  if (!__eq_Option(a.default, b.default)) return false;
  if (a.required !== b.required) return false;
  if (a.help !== b.help) return false;
  return true;
}

function __eq_Cli$CliError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "UnknownFlag": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "MissingValue": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "MissingRequired": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Cli$ParsedArgs(a, b) {
  if (!__eq_List(a.values, b.values)) return false;
  if (!__eq_List(a.positional, b.positional)) return false;
  return true;
}

function __eq_OrderedMap$Tree(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Leaf": {
      return true;
    }
    case "Node": {
      if (!__eq_Tree(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (!__eq_Tree(a._3, b._3)) return false;
      if (a._4 !== b._4) return false;
      return true;
    }
  }
  return true;
}

function __eq_SortedSet$AvlTree(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "AvlLeaf": {
      return true;
    }
    case "AvlNode": {
      if (!__eq_AvlTree(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      if (!__eq_AvlTree(a._2, b._2)) return false;
      if (a._3 !== b._3) return false;
      return true;
    }
  }
  return true;
}

function __eq_Range$IntRange(a, b) {
  if (a.start !== b.start) return false;
  if (a.stop !== b.stop) return false;
  if (a.step !== b.step) return false;
  return true;
}

function __eq_MlKem$KeyPair(a, b) {
  if (!__eq_Bytes(a.public_key, b.public_key)) return false;
  if (!__eq_Bytes(a.secret_key, b.secret_key)) return false;
  return true;
}

function __eq_MlDsa$KeyPair(a, b) {
  if (!__eq_Bytes(a.public_key, b.public_key)) return false;
  if (!__eq_Bytes(a.secret_key, b.secret_key)) return false;
  return true;
}

function __eq_Signal$Sig(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Term": {
      return true;
    }
    case "Int": {
      return true;
    }
    case "Hup": {
      return true;
    }
    case "Usr1": {
      return true;
    }
    case "Usr2": {
      return true;
    }
  }
  return true;
}

function __eq_RRB$Vec(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Vec": {
      if (!__eq_Array$PVec(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_RRB$Slice(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Slice": {
      if (!__eq_Array$PVec(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
  }
  return true;
}

function __eq_Uri$URI(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "URI": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (!__eq_Option(a._2, b._2)) return false;
      if (a._3 !== b._3) return false;
      if (a._4 !== b._4) return false;
      if (a._5 !== b._5) return false;
      return true;
    }
  }
  return true;
}

function __eq_Handle$Handle(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Handle": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_VectorClock$VectorClock(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "VectorClock": {
      if (!__eq_Map(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_VectorClock$ClockOrder(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Before": {
      return true;
    }
    case "After": {
      return true;
    }
    case "Concurrent": {
      return true;
    }
    case "Equal": {
      return true;
    }
  }
  return true;
}

function __eq_CRDT$GCounter$T(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "GCounter": {
      if (!__eq_Map(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_CRDT$PNCounter$T(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "PNCounter": {
      if (!__eq_Map(a._0, b._0)) return false;
      if (!__eq_Map(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_CRDT$LWWRegister$T(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "LWWRegister": {
      if (a._0 !== b._0) return false;
      if (!__eq_VectorClock(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_CRDT$ORSet$T(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ORSet": {
      if (!__eq_Map(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Merkle$MerkleTree(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "MLeaf": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "MBranch": {
      if (a._0 !== b._0) return false;
      if (!__eq_MerkleTree(a._1, b._1)) return false;
      if (!__eq_MerkleTree(a._2, b._2)) return false;
      return true;
    }
  }
  return true;
}

function __eq_NodeCert$Cert(a, b) {
  if (a.node !== b.node) return false;
  if (!__eq_List(a.roles, b.roles)) return false;
  if (!__eq_List(a.flags, b.flags)) return false;
  if (a.not_after !== b.not_after) return false;
  if (a.issuer !== b.issuer) return false;
  if (a.pubkey !== b.pubkey) return false;
  if (a.serial !== b.serial) return false;
  return true;
}

function __eq_NodeCert$Signed(a, b) {
  if (!__eq_Cert(a.cert, b.cert)) return false;
  if (!__eq_List(a.body, b.body)) return false;
  if (!__eq_Bytes(a.signature, b.signature)) return false;
  return true;
}

function __eq_NodeCert$Revocation(a, b) {
  if (a.node !== b.node) return false;
  if (a.serial !== b.serial) return false;
  if (a.issued_at !== b.issued_at) return false;
  return true;
}

function __eq_NodeCert$SignedRevocation(a, b) {
  if (!__eq_Revocation(a.rev, b.rev)) return false;
  if (!__eq_List(a.body, b.body)) return false;
  if (!__eq_Bytes(a.signature, b.signature)) return false;
  return true;
}

function __eq_NodeCert$Credentials(a, b) {
  if (!__eq_Signed(a.signed, b.signed)) return false;
  if (!__eq_Bytes(a.secret_key, b.secret_key)) return false;
  if (!__eq_Bytes(a.operator_pubkey, b.operator_pubkey)) return false;
  if (a.revoked !== b.revoked) return false;
  return true;
}

function __eq_ClusterAuth$Auth(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Secret": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Certified": {
      if (!__eq_NodeCert$Credentials(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_ClusterAuth$FrameKeys(a, b) {
  if (!__eq_Bytes(a.tx_key, b.tx_key)) return false;
  if (!__eq_Bytes(a.rx_key, b.rx_key)) return false;
  return true;
}

function __eq_NodeIdentity$Identity(a, b) {
  if (a.name !== b.name) return false;
  if (a.node_id !== b.node_id) return false;
  if (a.incarnation !== b.incarnation) return false;
  return true;
}

function __eq_Handshake$HelloCert(a, b) {
  if (!__eq_List(a.cert, b.cert)) return false;
  if (!__eq_List(a.eph, b.eph)) return false;
  return true;
}

function __eq_Handshake$Hello(a, b) {
  if (!__eq_NodeIdentity$Identity(a.identity, b.identity)) return false;
  if (a.nonce !== b.nonce) return false;
  if (a.role !== b.role) return false;
  if (a.addr !== b.addr) return false;
  if (!__eq_Option(a.cert, b.cert)) return false;
  return true;
}

function __eq_GlobalPid$Pid(a, b) {
  if (a.node_id !== b.node_id) return false;
  if (a.local_pid !== b.local_pid) return false;
  if (a.creation !== b.creation) return false;
  return true;
}

function __eq_RemoteCall$RemoteRef(a, b) {
  if (a.module_name !== b.module_name) return false;
  if (a.fn_name !== b.fn_name) return false;
  if (a.sig_hash !== b.sig_hash) return false;
  if (a.impl_hash !== b.impl_hash) return false;
  return true;
}

function __eq_RemoteCall$CallError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "DeadlineExceeded": {
      return true;
    }
    case "NoConnection": {
      return true;
    }
    case "RemoteExit": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "TypeMismatch": {
      return true;
    }
    case "VersionSkew": {
      return true;
    }
    case "NoTarget": {
      return true;
    }
    case "Forbidden": {
      return true;
    }
  }
  return true;
}

function __eq_RemoteCall$Verdict(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Accept": {
      return true;
    }
    case "Reject": {
      if (!__eq_CallError(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_RemoteCall$ReplyResult(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Returned": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
    case "Failed": {
      if (!__eq_CallError(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_RemoteCall$CallRequest(a, b) {
  if (!__eq_RemoteRef(a.fref, b.fref)) return false;
  if (!__eq_List(a.args, b.args)) return false;
  if (!__eq_Pid(a.reply_to, b.reply_to)) return false;
  if (a.deadline !== b.deadline) return false;
  if (a.correlation !== b.correlation) return false;
  return true;
}

function __eq_RemoteCall$CallReply(a, b) {
  if (a.correlation !== b.correlation) return false;
  if (!__eq_ReplyResult(a.result, b.result)) return false;
  return true;
}

function __eq_NodeRpc$Target(a, b) {
  if (a.sig_hash !== b.sig_hash) return false;
  if (a.impl_hash !== b.impl_hash) return false;
  if (a.invoke !== b.invoke) return false;
  return true;
}

function __eq_NodeRpc$Targets(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Targets": {
      if (!__eq_Map(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_PeerRegistry$Peer(a, b) {
  if (a.node_id !== b.node_id) return false;
  if (!__eq_NodeIdentity$Identity(a.identity, b.identity)) return false;
  if (a.fd !== b.fd) return false;
  if (a.data_fd !== b.data_fd) return false;
  return true;
}

function __eq_PeerRegistry$Registry(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Registry": {
      if (!__eq_Map(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_NetKernel$MacKeys(a, b) {
  if (!__eq_Bytes(a.tx_key, b.tx_key)) return false;
  if (!__eq_Bytes(a.rx_key, b.rx_key)) return false;
  return true;
}

function __eq_NetKernel$Authed(a, b) {
  if (!__eq_NodeIdentity$Identity(a.identity, b.identity)) return false;
  if (a.role !== b.role) return false;
  if (a.addr !== b.addr) return false;
  if (!__eq_Option(a.cert, b.cert)) return false;
  if (a.mac !== b.mac) return false;
  return true;
}

function __eq_Membership$MemberStatus(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Alive": {
      return true;
    }
    case "Suspect": {
      return true;
    }
    case "Dead": {
      return true;
    }
  }
  return true;
}

function __eq_Membership$Member(a, b) {
  if (a.node_id !== b.node_id) return false;
  if (!__eq_MemberStatus(a.status, b.status)) return false;
  if (a.incarnation !== b.incarnation) return false;
  if (a.creation !== b.creation) return false;
  if (a.name !== b.name) return false;
  if (a.addr !== b.addr) return false;
  return true;
}

function __eq_Membership$Members(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Members": {
      if (!__eq_Map(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Swim$Config(a, b) {
  if (a.ack_timeout_ms !== b.ack_timeout_ms) return false;
  if (a.suspect_timeout_ms !== b.suspect_timeout_ms) return false;
  if (a.indirect_k !== b.indirect_k) return false;
  return true;
}

function __eq_Swim$Probe(a, b) {
  if (a.target !== b.target) return false;
  if (a.sent_at !== b.sent_at) return false;
  if (a.indirect_sent !== b.indirect_sent) return false;
  if (a.acked !== b.acked) return false;
  return true;
}

function __eq_Swim$State(a, b) {
  if (a.me !== b.me) return false;
  if (a.incarnation !== b.incarnation) return false;
  if (!__eq_Members(a.members, b.members)) return false;
  if (!__eq_Config(a.config, b.config)) return false;
  if (!__eq_Option(a.probe, b.probe)) return false;
  if (!__eq_Map(a.suspect_deadlines, b.suspect_deadlines)) return false;
  return true;
}

function __eq_Swim$Action(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "SendPing": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "SendPingReq": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "Gossip": {
      if (!__eq_Member(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_SwimDriver$State(a, b) {
  if (!__eq_Swim$State(a.swim, b.swim)) return false;
  if (!__eq_Random$Rng(a.rng, b.rng)) return false;
  if (a.period_ms !== b.period_ms) return false;
  if (a.period_end !== b.period_end) return false;
  if (!__eq_Map(a.peer_loads, b.peer_loads)) return false;
  if (a.anti_entropy_next !== b.anti_entropy_next) return false;
  return true;
}

function __eq_SwimDriver$Event(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "PingAck": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "GossipFrame": {
      if (!__eq_Member(a._0, b._0)) return false;
      return true;
    }
    case "GossipWithLoad": {
      if (!__eq_Member(a._0, b._0)) return false;
      if (!__eq_NodeLoad(a._1, b._1)) return false;
      return true;
    }
    case "PeerDown": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "ConnLost": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_SwimDriver$WireMsg(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "SwimPing": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "SwimPingAck": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "SwimPingReq": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "SwimGossip": {
      if (a._0 !== b._0) return false;
      if (!__eq_MemberStatus(a._1, b._1)) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
    case "SwimGossipLoad": {
      if (a._0 !== b._0) return false;
      if (!__eq_MemberStatus(a._1, b._1)) return false;
      if (a._2 !== b._2) return false;
      if (!__eq_NodeLoad(a._3, b._3)) return false;
      return true;
    }
  }
  return true;
}

function __eq_GlobalRegistry$Entry(a, b) {
  if (a.node_id !== b.node_id) return false;
  if (a.pid !== b.pid) return false;
  if (!__eq_VectorClock(a.clock, b.clock)) return false;
  if (a.present !== b.present) return false;
  if (a.creation !== b.creation) return false;
  if (a.registrant !== b.registrant) return false;
  if (a.retired_at !== b.retired_at) return false;
  return true;
}

function __eq_GlobalRegistry$Names(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Names": {
      if (!__eq_Map(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_NodeSend$SendError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "NoConnection": {
      return true;
    }
    case "Refused": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_NodeSend$Delivery(a, b) {
  if (a.seq !== b.seq) return false;
  if (a.to_local_pid !== b.to_local_pid) return false;
  if (a.to_creation !== b.to_creation) return false;
  if (a.type_tag !== b.type_tag) return false;
  if (!__eq_List(a.payload, b.payload)) return false;
  if (a.schema !== b.schema) return false;
  if (a.from_node !== b.from_node) return false;
  return true;
}

function __eq_NodeQueue$Policy(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "DropNew": {
      return true;
    }
    case "DropOld": {
      return true;
    }
    case "BlockSender": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Unbounded": {
      return true;
    }
  }
  return true;
}

function __eq_NodeQueue$EnqueueError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Backpressure": {
      return true;
    }
    case "NoConnection": {
      return true;
    }
    case "NotAuthorized": {
      return true;
    }
  }
  return true;
}

function __eq_NodeQueue$WriterState(a, b) {
  if (a.fd !== b.fd) return false;
  if (a.granted !== b.granted) return false;
  if (a.sent !== b.sent) return false;
  if (!__eq_Deque$Deque(a.pending, b.pending)) return false;
  if (!__eq_List(a.evicted, b.evicted)) return false;
  if (a.budget !== b.budget) return false;
  if (a.dead !== b.dead) return false;
  if (!__eq_Deque$Deque(a.waiting, b.waiting)) return false;
  if (!__eq_Deque$Deque(a.waiters, b.waiters)) return false;
  return true;
}

function __eq_NodeQueue__Writer_State(a, b) {
  if (a.budget !== b.budget) return false;
  if (a.dead !== b.dead) return false;
  if (!__eq_List(a.evicted, b.evicted)) return false;
  if (a.fd !== b.fd) return false;
  if (a.granted !== b.granted) return false;
  if (!__eq_Deque$Deque(a.pending, b.pending)) return false;
  if (a.sent !== b.sent) return false;
  if (!__eq_Deque$Deque(a.waiters, b.waiters)) return false;
  if (!__eq_Deque$Deque(a.waiting, b.waiting)) return false;
  return true;
}

function __eq_NodeQueue__Writer_Msg(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "TakeEvicted": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Wait": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Configure": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "Enqueue": {
      if (a._0 !== b._0) return false;
      if (!__eq_Bytes(a._1, b._1)) return false;
      return true;
    }
    case "EnqueueEvicting": {
      if (a._0 !== b._0) return false;
      if (!__eq_Bytes(a._1, b._1)) return false;
      return true;
    }
    case "Credit": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Waiting": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (!__eq_Bytes(a._2, b._2)) return false;
      return true;
    }
    case "Withdraw": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Close": {
      return true;
    }
    case "CloseFd": {
      return true;
    }
  }
  return true;
}

function __eq_NodeQueue__Writer_Actor(a, b) {
  if (a.$d_dispatch !== b.$d_dispatch) return false;
  if (a.$e_alive !== b.$e_alive) return false;
  if (a.budget !== b.budget) return false;
  if (a.dead !== b.dead) return false;
  if (!__eq_List(a.evicted, b.evicted)) return false;
  if (a.fd !== b.fd) return false;
  if (a.granted !== b.granted) return false;
  if (!__eq_Deque$Deque(a.pending, b.pending)) return false;
  if (a.sent !== b.sent) return false;
  if (!__eq_Deque$Deque(a.waiters, b.waiters)) return false;
  if (!__eq_Deque$Deque(a.waiting, b.waiting)) return false;
  return true;
}

function __eq_NodeQueue$WriterReq(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "EvictedReq": {
      return true;
    }
    case "WaitReq": {
      return true;
    }
  }
  return true;
}

function __eq_DistLink$DownReason(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Normal": {
      return true;
    }
    case "Killed": {
      return true;
    }
    case "Crash": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "NodeDown": {
      return true;
    }
  }
  return true;
}

function __eq_DistLink$MonitorRef(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "MonitorRef": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_DistLink$PendingMonitor(a, b) {
  if (!__eq_MonitorRef(a.ref, b.ref)) return false;
  if (a.target_node !== b.target_node) return false;
  if (a.target_pid !== b.target_pid) return false;
  if (!__eq_GlobalPid$Pid(a.watcher_pid, b.watcher_pid)) return false;
  return true;
}

function __eq_DistLink$MonitorTable(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "MonitorTable": {
      if (!__eq_Map(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_DistSupervisor$RestartStrategy(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Permanent": {
      return true;
    }
    case "Transient": {
      return true;
    }
    case "Temporary": {
      return true;
    }
  }
  return true;
}

function __eq_DistSupervisor$SupervisionStrategy(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "OneForOne": {
      return true;
    }
    case "OneForAll": {
      return true;
    }
    case "RestForOne": {
      return true;
    }
  }
  return true;
}

function __eq_DistSupervisor$RemoteChild(a, b) {
  if (!__eq_RemoteRef(a.fn_ref, b.fn_ref)) return false;
  if (a.node_id !== b.node_id) return false;
  if (!__eq_RestartStrategy(a.restart, b.restart)) return false;
  return true;
}

function __eq_DistSupervisor$ChildState(a, b) {
  if (!__eq_RemoteChild(a.spec, b.spec)) return false;
  if (!__eq_GlobalPid$Pid(a.global_pid, b.global_pid)) return false;
  if (!__eq_DistLink$MonitorRef(a.ref, b.ref)) return false;
  return true;
}

function __eq_DistSupervisor$State(a, b) {
  if (!__eq_SupervisionStrategy(a.sup_strategy, b.sup_strategy)) return false;
  if (!__eq_List(a.children, b.children)) return false;
  return true;
}

function __eq_Session$Ops(a, b) {
  if (a.register !== b.register) return false;
  if (a.emit !== b.emit) return false;
  if (a.suspend !== b.suspend) return false;
  if (a.close !== b.close) return false;
  if (a.fail !== b.fail) return false;
  if (a.on_cancel !== b.on_cancel) return false;
  if (a.leave !== b.leave) return false;
  if (a.on_crash !== b.on_crash) return false;
  if (a.suspend_at_boundary !== b.suspend_at_boundary) return false;
  if (a.on_drain !== b.on_drain) return false;
  return true;
}

function __eq_Session$Outcome(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Finished": {
      return true;
    }
    case "Drained": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Session$InProcess(a, b) {
  if (!__eq_Ops(a.ops, b.ops)) return false;
  if (a.drain !== b.drain) return false;
  if (a.take !== b.take) return false;
  if (a.crash !== b.crash) return false;
  if (a.queued !== b.queued) return false;
  if (a.step !== b.step) return false;
  if (a.drain_role !== b.drain_role) return false;
  if (a.undelivered !== b.undelivered) return false;
  if (a.drained !== b.drained) return false;
  if (a.sent !== b.sent) return false;
  if (a.consumed !== b.consumed) return false;
  if (a.returned !== b.returned) return false;
  if (a.close !== b.close) return false;
  return true;
}

function __eq_Session$InProcessState(a, b) {
  if (!__eq_Vault(a.handlers, b.handlers)) return false;
  if (!__eq_Vault(a.waiting, b.waiting)) return false;
  if (!__eq_Vault(a.cancel_hs, b.cancel_hs)) return false;
  if (!__eq_Vault(a.crash_hs, b.crash_hs)) return false;
  if (!__eq_Vault(a.drain_hs, b.drain_hs)) return false;
  if (!__eq_Vault(a.boundary, b.boundary)) return false;
  if (!__eq_Vault(a.draining, b.draining)) return false;
  if (!__eq_Vault(a.undeliv, b.undeliv)) return false;
  if (!__eq_Vault(a.gone, b.gone)) return false;
  if (!__eq_Vault(a.meta, b.meta)) return false;
  if (!__eq_Vault(a.roles, b.roles)) return false;
  if (!__eq_Vault(a.queue, b.queue)) return false;
  if (a.trace !== b.trace) return false;
  return true;
}

function __eq_Session$Theory$SessionGlobal(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "GEnd": {
      return true;
    }
    case "GMsg": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (!__eq_SessionGlobal(a._3, b._3)) return false;
      return true;
    }
    case "GChoice": {
      if (a._0 !== b._0) return false;
      if (!__eq_SessionGBranches(a._1, b._1)) return false;
      return true;
    }
    case "GLoop": {
      if (!__eq_SessionGlobal(a._0, b._0)) return false;
      if (!__eq_SessionGlobal(a._1, b._1)) return false;
      return true;
    }
    case "GVar": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Session$Theory$SessionGBranches(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "GBNil": {
      return true;
    }
    case "GBCons": {
      if (a._0 !== b._0) return false;
      if (!__eq_SessionGlobal(a._1, b._1)) return false;
      if (!__eq_SessionGBranches(a._2, b._2)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Session$Theory$SessionLocal(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "LEnd": {
      return true;
    }
    case "LSend": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (!__eq_SessionLocal(a._2, b._2)) return false;
      return true;
    }
    case "LRecv": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (!__eq_SessionLocal(a._2, b._2)) return false;
      return true;
    }
    case "LChoose": {
      if (!__eq_SessionLBranches(a._0, b._0)) return false;
      return true;
    }
    case "LOffer": {
      if (!__eq_SessionLBranches(a._0, b._0)) return false;
      return true;
    }
    case "LRec": {
      if (!__eq_SessionLocal(a._0, b._0)) return false;
      return true;
    }
    case "LVar": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Session$Theory$SessionLBranches(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "LBNil": {
      return true;
    }
    case "LBCons": {
      if (a._0 !== b._0) return false;
      if (!__eq_SessionLocal(a._1, b._1)) return false;
      if (!__eq_SessionLBranches(a._2, b._2)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Session$Theory$SessionRoles(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "RoleEnd": {
      return true;
    }
    case "RoleThen": {
      if (a._0 !== b._0) return false;
      if (!__eq_SessionRoles(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Session$Theory$SessionActs(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ActEnd": {
      return true;
    }
    case "ActThen": {
      if (!__eq_SessionAct(a._0, b._0)) return false;
      if (!__eq_SessionActs(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Session$Theory$SessionPicks(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "PickEnd": {
      return true;
    }
    case "PickThen": {
      if (a._0 !== b._0) return false;
      if (!__eq_SessionPicks(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Session$Theory$SessionAct(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ActMsg": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
    case "ActPick": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (a._3 !== b._3) return false;
      return true;
    }
  }
  return true;
}

function __eq_Session$Theory$SessionCfg(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "CfgEnd": {
      return true;
    }
    case "CfgRole": {
      if (a._0 !== b._0) return false;
      if (!__eq_SessionLocal(a._1, b._1)) return false;
      if (!__eq_SessionCfg(a._2, b._2)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Session$Theory$SessionCfgStep(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "CfgStuck": {
      return true;
    }
    case "CfgMoved": {
      if (!__eq_SessionCfg(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Session$Theory$SessionLStep(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "StepBad": {
      return true;
    }
    case "StepOk": {
      if (!__eq_SessionLocal(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_ClusterNode$CnConfig(a, b) {
  if (a.name !== b.name) return false;
  if (a.listen_port !== b.listen_port) return false;
  if (a.advertise !== b.advertise) return false;
  if (!__eq_List(a.seeds, b.seeds)) return false;
  if (a.secret !== b.secret) return false;
  if (a.creation !== b.creation) return false;
  if (!__eq_Swim$Config(a.swim, b.swim)) return false;
  if (a.period_ms !== b.period_ms) return false;
  if (a.tick_ms !== b.tick_ms) return false;
  if (a.redial_min_ms !== b.redial_min_ms) return false;
  if (a.redial_max_ms !== b.redial_max_ms) return false;
  if (a.dial_timeout_ms !== b.dial_timeout_ms) return false;
  if (a.handshake_timeout_ms !== b.handshake_timeout_ms) return false;
  if (!__eq_ClusterAuth$Auth(a.auth, b.auth)) return false;
  if (!__eq_List(a.revocations, b.revocations)) return false;
  if (!__eq_Option(a.cert_files, b.cert_files)) return false;
  if (a.tombstone_grace_ms !== b.tombstone_grace_ms) return false;
  return true;
}

function __eq_ClusterNode$CertFiles(a, b) {
  if (a.cert !== b.cert) return false;
  if (a.key !== b.key) return false;
  if (a.poll_ms !== b.poll_ms) return false;
  return true;
}

function __eq_ClusterNode$NodeInfo(a, b) {
  if (a.node_id !== b.node_id) return false;
  if (a.name !== b.name) return false;
  if (a.addr !== b.addr) return false;
  if (a.creation !== b.creation) return false;
  if (a.incarnation !== b.incarnation) return false;
  return true;
}

function __eq_ClusterNode$NodeEvent(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "NodeUp": {
      if (!__eq_NodeInfo(a._0, b._0)) return false;
      return true;
    }
    case "NodeSuspect": {
      if (!__eq_NodeInfo(a._0, b._0)) return false;
      return true;
    }
    case "NodeDead": {
      if (!__eq_NodeInfo(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "NodeRejoined": {
      if (!__eq_NodeInfo(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_ClusterNode$SecurityEvent(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "HandshakeRejected": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "FrameRejected": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "RawSendRefused": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "CertReplaced": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "CertRefused": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_ClusterNode$CnLink(a, b) {
  if (a.node_id !== b.node_id) return false;
  if (a.gen !== b.gen) return false;
  if (a.cfd !== b.cfd) return false;
  if (a.dfd !== b.dfd) return false;
  if (a.dialer !== b.dialer) return false;
  if (a.cw !== b.cw) return false;
  if (a.creation !== b.creation) return false;
  if (!__eq_Bytes(a.binding, b.binding)) return false;
  if (a.cu_sent !== b.cu_sent) return false;
  if (a.cu_seen !== b.cu_seen) return false;
  return true;
}

function __eq_ClusterNode$CnHalf(a, b) {
  if (a.cfd !== b.cfd) return false;
  if (a.dfd !== b.dfd) return false;
  if (a.name !== b.name) return false;
  if (a.addr !== b.addr) return false;
  if (a.creation !== b.creation) return false;
  return true;
}

function __eq_ClusterNode$CnState(a, b) {
  if (!__eq_CnConfig(a.cfg, b.cfg)) return false;
  if (a.me !== b.me) return false;
  if (!__eq_SwimDriver$State(a.driver, b.driver)) return false;
  if (!__eq_Map(a.links, b.links)) return false;
  if (!__eq_Map(a.halves, b.halves)) return false;
  if (a.gen !== b.gen) return false;
  if (!__eq_Map(a.dialing, b.dialing)) return false;
  if (!__eq_Map(a.backoff, b.backoff)) return false;
  if (!__eq_List(a.pending, b.pending)) return false;
  if (!__eq_Map(a.relays, b.relays)) return false;
  if (!__eq_List(a.refused, b.refused)) return false;
  if (!__eq_Map(a.seed_ids, b.seed_ids)) return false;
  if (!__eq_List(a.rejoining, b.rejoining)) return false;
  if (a.stopped !== b.stopped) return false;
  if (!__eq_GlobalRegistry$Names(a.reg, b.reg)) return false;
  if (!__eq_Map(a.regs, b.regs)) return false;
  if (!__eq_Map(a.vis, b.vis)) return false;
  if (!__eq_Map(a.certs, b.certs)) return false;
  if (!__eq_List(a.revs, b.revs)) return false;
  if (!__eq_Map(a.cert_dead, b.cert_dead)) return false;
  if (a.rotated !== b.rotated) return false;
  if (a.reg_swept_at !== b.reg_swept_at) return false;
  if (a.remembered !== b.remembered) return false;
  if (a.reg_synced !== b.reg_synced) return false;
  return true;
}

function __eq_ClusterNode$NameEvent(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Bound": {
      if (a._0 !== b._0) return false;
      if (!__eq_GlobalPid$Pid(a._1, b._1)) return false;
      return true;
    }
    case "Unbound": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Lost": {
      if (a._0 !== b._0) return false;
      if (!__eq_GlobalPid$Pid(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_ClusterNode$RegisterError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Taken": {
      if (!__eq_GlobalPid$Pid(a._0, b._0)) return false;
      return true;
    }
    case "Stopped": {
      return true;
    }
  }
  return true;
}

function __eq_ClusterNode$CnEffect(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Send": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
    case "Dial": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Install": {
      if (!__eq_CnLink(a._0, b._0)) return false;
      return true;
    }
    case "Drop": {
      if (!__eq_CnLink(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "Discard": {
      if (!__eq_CnLink(a._0, b._0)) return false;
      return true;
    }
    case "Emit": {
      if (!__eq_NodeEvent(a._0, b._0)) return false;
      return true;
    }
    case "Named": {
      if (a._0 !== b._0) return false;
      if (!__eq_NameEvent(a._1, b._1)) return false;
      return true;
    }
    case "Unwatch": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_ClusterNode__CtlWriter_State(a, b) {
  if (a.dead !== b.dead) return false;
  if (a.fd !== b.fd) return false;
  return true;
}

function __eq_ClusterNode__CtlWriter_Msg(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "CtlUse": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "CtlWrite": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
    case "CtlStop": {
      return true;
    }
    case "CtlClose": {
      return true;
    }
  }
  return true;
}

function __eq_ClusterNode__CtlWriter_Actor(a, b) {
  if (a.$d_dispatch !== b.$d_dispatch) return false;
  if (a.$e_alive !== b.$e_alive) return false;
  if (a.dead !== b.dead) return false;
  if (a.fd !== b.fd) return false;
  return true;
}

function __eq_ClusterNode$CnHandle(a, b) {
  if (a.pid !== b.pid) return false;
  if (a.name !== b.name) return false;
  if (a.node_id !== b.node_id) return false;
  if (a.advertise !== b.advertise) return false;
  if (!__eq_Vault(a.members, b.members)) return false;
  if (!__eq_Vault(a.subs, b.subs)) return false;
  if (!__eq_Vault(a.meta, b.meta)) return false;
  if (!__eq_Vault(a.names, b.names)) return false;
  if (!__eq_Vault(a.claims, b.claims)) return false;
  if (!__eq_Vault(a.watches, b.watches)) return false;
  if (!__eq_Vault(a.links, b.links)) return false;
  if (!__eq_Vault(a.qs, b.qs)) return false;
  if (!__eq_Vault(a.causes, b.causes)) return false;
  if (!__eq_Vault(a.routes, b.routes)) return false;
  if (!__eq_Vault(a.closes, b.closes)) return false;
  if (!__eq_Vault(a.downs, b.downs)) return false;
  if (!__eq_Vault(a.fired, b.fired)) return false;
  if (!__eq_Vault(a.failed, b.failed)) return false;
  if (!__eq_Vault(a.sfailed, b.sfailed)) return false;
  if (!__eq_Vault(a.certs, b.certs)) return false;
  if (!__eq_Vault(a.sec, b.sec)) return false;
  if (!__eq_Vault(a.revs, b.revs)) return false;
  if (!__eq_Bytes(a.op_pub, b.op_pub)) return false;
  if (!__eq_Vault(a.auth, b.auth)) return false;
  if (!__eq_Vault(a.strs, b.strs)) return false;
  if (!__eq_Vault(a.registrants, b.registrants)) return false;
  return true;
}

function __eq_ClusterNode__RegWatch_State(a, b) {
  if (a.n !== b.n) return false;
  return true;
}

function __eq_ClusterNode__RegWatch_Msg(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "WatchPid": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_ClusterNode__RegWatch_Actor(a, b) {
  if (a.$d_dispatch !== b.$d_dispatch) return false;
  if (a.$e_alive !== b.$e_alive) return false;
  if (a.n !== b.n) return false;
  return true;
}

function __eq_ClusterNode__ClusterNodeActor_State(a, b) {
  if (!__eq_CnHandle(a.h, b.h)) return false;
  if (!__eq_CnState(a.st, b.st)) return false;
  if (a.started !== b.started) return false;
  return true;
}

function __eq_ClusterNode__ClusterNodeActor_Msg(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Boot": {
      if (!__eq_CnState(a._0, b._0)) return false;
      if (!__eq_CnHandle(a._1, b._1)) return false;
      return true;
    }
    case "Tick": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Accepted": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (a._3 !== b._3) return false;
      if (a._4 !== b._4) return false;
      if (a._5 !== b._5) return false;
      if (!__eq_Option(a._6, b._6)) return false;
      return true;
    }
    case "Dialed": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (a._3 !== b._3) return false;
      if (a._4 !== b._4) return false;
      if (a._5 !== b._5) return false;
      if (a._6 !== b._6) return false;
      if (!__eq_Option(a._7, b._7)) return false;
      return true;
    }
    case "SeedIsSelf": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "DialFailed": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
    case "CtlFrame": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (!__eq_List(a._3, b._3)) return false;
      return true;
    }
    case "ReplaceCert": {
      if (!__eq_NodeCert$Signed(a._0, b._0)) return false;
      if (!__eq_Bytes(a._1, b._1)) return false;
      return true;
    }
    case "LinkClosed": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "Register": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
    case "Revoke": {
      if (!__eq_NodeCert$SignedRevocation(a._0, b._0)) return false;
      return true;
    }
    case "Unregister": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "LocalDown": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "MoveReader": {
      if (a._0 !== b._0) return false;
      if (!__eq_CnLink(a._1, b._1)) return false;
      if (!__eq_List(a._2, b._2)) return false;
      if (!__eq_List(a._3, b._3)) return false;
      return true;
    }
    case "MoveTicker": {
      return true;
    }
    case "MoveAcceptor": {
      return true;
    }
    case "Shutdown": {
      return true;
    }
  }
  return true;
}

function __eq_ClusterNode__ClusterNodeActor_Actor(a, b) {
  if (a.$d_dispatch !== b.$d_dispatch) return false;
  if (a.$e_alive !== b.$e_alive) return false;
  if (!__eq_CnHandle(a.h, b.h)) return false;
  if (!__eq_CnState(a.st, b.st)) return false;
  if (a.started !== b.started) return false;
  return true;
}

function __eq_ClusterNode$NodeActorState(a, b) {
  if (!__eq_CnState(a.st, b.st)) return false;
  if (!__eq_CnHandle(a.h, b.h)) return false;
  if (a.started !== b.started) return false;
  return true;
}

function __eq_ClusterNode$ClusterOps(a, b) {
  if (a.node_id !== b.node_id) return false;
  if (a.stop !== b.stop) return false;
  if (a.subscribe !== b.subscribe) return false;
  if (a.unsubscribe !== b.unsubscribe) return false;
  if (a.members !== b.members) return false;
  if (a.all_members !== b.all_members) return false;
  if (a.addr_of !== b.addr_of) return false;
  if (a.name_of !== b.name_of) return false;
  if (a.link_count !== b.link_count) return false;
  if (a.register !== b.register) return false;
  if (a.unregister !== b.unregister) return false;
  if (a.lookup !== b.lookup) return false;
  if (a.registrant !== b.registrant) return false;
  if (a.names !== b.names) return false;
  if (a.watch !== b.watch) return false;
  if (a.unwatch !== b.unwatch) return false;
  if (a.stale_bindings !== b.stale_bindings) return false;
  if (a.creation !== b.creation) return false;
  if (a.next_id !== b.next_id) return false;
  if (a.queue_for !== b.queue_for) return false;
  if (a.session_queue_for !== b.session_queue_for) return false;
  if (a.send_msg !== b.send_msg) return false;
  if (a.route !== b.route) return false;
  if (a.route_type !== b.route_type) return false;
  if (a.route_session !== b.route_session) return false;
  if (a.unroute !== b.unroute) return false;
  if (a.on_peer_closed !== b.on_peer_closed) return false;
  if (a.off_peer_closed !== b.off_peer_closed) return false;
  if (a.on_delivery_failed !== b.on_delivery_failed) return false;
  if (a.on_session_failed !== b.on_session_failed) return false;
  if (a.off_session_failed !== b.off_session_failed) return false;
  if (a.monitor_remote !== b.monitor_remote) return false;
  if (a.demonitor_remote !== b.demonitor_remote) return false;
  if (a.peer_cert !== b.peer_cert) return false;
  if (a.own_cert !== b.own_cert) return false;
  if (a.frames_rejected !== b.frames_rejected) return false;
  if (a.raw_refused !== b.raw_refused) return false;
  if (a.revoke !== b.revoke) return false;
  if (a.revocations !== b.revocations) return false;
  if (a.replace_cert !== b.replace_cert) return false;
  if (a.on_security_event !== b.on_security_event) return false;
  if (a.off_security_event !== b.off_security_event) return false;
  if (a.registry_synced !== b.registry_synced) return false;
  if (a.rejoined_at !== b.rejoined_at) return false;
  if (a.attach_session !== b.attach_session) return false;
  if (a.handshake !== b.handshake) return false;
  return true;
}

function __eq_SessionNode$Link(a, b) {
  if (a.role !== b.role) return false;
  if (a.data_fd !== b.data_fd) return false;
  if (a.control_fd !== b.control_fd) return false;
  if (!__eq_GlobalPid$Pid(a.peer, b.peer)) return false;
  if (a.q !== b.q) return false;
  if (!__eq_Task(a.control, b.control)) return false;
  return true;
}

function __eq_SessionNode$EndpointState(a, b) {
  if (a.n !== b.n) return false;
  if (a.links !== b.links) return false;
  if (a.ended !== b.ended) return false;
  if (!__eq_List(a.failed, b.failed)) return false;
  if (!__eq_List(a.waiters, b.waiters)) return false;
  return true;
}

function __eq_SessionNode$Party(a, b) {
  if (a.my_role !== b.my_role) return false;
  if (a.node_id !== b.node_id) return false;
  if (!__eq_Vault(a.handlers, b.handlers)) return false;
  if (!__eq_Vault(a.waiting, b.waiting)) return false;
  if (!__eq_Vault(a.pending, b.pending)) return false;
  if (!__eq_Vault(a.meta, b.meta)) return false;
  if (!__eq_Vault(a.forward, b.forward)) return false;
  if (!__eq_Vault(a.why, b.why)) return false;
  if (!__eq_Vault(a.gone, b.gone)) return false;
  if (!__eq_Vault(a.cancel_hs, b.cancel_hs)) return false;
  if (!__eq_Vault(a.crash_hs, b.crash_hs)) return false;
  if (!__eq_Vault(a.forward_cancel, b.forward_cancel)) return false;
  if (!__eq_Vault(a.forward_crash, b.forward_crash)) return false;
  if (!__eq_Vault(a.heard, b.heard)) return false;
  if (!__eq_Vault(a.drain_hs, b.drain_hs)) return false;
  if (!__eq_Pid(a.ep, b.ep)) return false;
  if (!__eq_List(a.links, b.links)) return false;
  if (a.on_close !== b.on_close) return false;
  return true;
}

function __eq_SessionNode__HostWatch_State(a, b) {
  if (a.n !== b.n) return false;
  return true;
}

function __eq_SessionNode__HostWatch_Msg(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Watch": {
      if (!__eq_Party(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_SessionNode__HostWatch_Actor(a, b) {
  if (a.$d_dispatch !== b.$d_dispatch) return false;
  if (a.$e_alive !== b.$e_alive) return false;
  if (a.n !== b.n) return false;
  return true;
}

function __eq_SessionNode__Endpoint_State(a, b) {
  if (a.ended !== b.ended) return false;
  if (!__eq_List(a.failed, b.failed)) return false;
  if (a.links !== b.links) return false;
  if (a.n !== b.n) return false;
  if (!__eq_List(a.waiters, b.waiters)) return false;
  return true;
}

function __eq_SessionNode__Endpoint_Msg(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Deliver": {
      if (!__eq_Party(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (!__eq_Bytes(a._3, b._3)) return false;
      return true;
    }
    case "AwaitOutcome": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Expect": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "LinkEnded": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "Drain": {
      if (!__eq_Party(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "PeerGone": {
      if (!__eq_Party(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
    case "HostDown": {
      if (!__eq_Party(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
    case "ReleaseEpoch": {
      return true;
    }
    case "Leave": {
      if (!__eq_Party(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
    case "Early": {
      if (!__eq_Vault(a._0, b._0)) return false;
      if (!__eq_Party(a._1, b._1)) return false;
      if (a._2 !== b._2) return false;
      if (!__eq_Bytes(a._3, b._3)) return false;
      return true;
    }
    case "Ready": {
      if (!__eq_Party(a._0, b._0)) return false;
      return true;
    }
    case "DeliverDraining": {
      if (!__eq_Party(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (!__eq_Bytes(a._3, b._3)) return false;
      return true;
    }
    case "Returned": {
      if (!__eq_Party(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      if (!__eq_Bytes(a._2, b._2)) return false;
      return true;
    }
  }
  return true;
}

function __eq_SessionNode__Endpoint_Actor(a, b) {
  if (a.$d_dispatch !== b.$d_dispatch) return false;
  if (a.$e_alive !== b.$e_alive) return false;
  if (a.ended !== b.ended) return false;
  if (!__eq_List(a.failed, b.failed)) return false;
  if (a.links !== b.links) return false;
  if (a.n !== b.n) return false;
  if (!__eq_List(a.waiters, b.waiters)) return false;
  return true;
}

function __eq_SessionNode$EndpointReq(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "DeliverReq": {
      return true;
    }
    case "OutcomeReq": {
      return true;
    }
  }
  return true;
}

function __eq_SessionNode$Addr(a, b) {
  if (a.role !== b.role) return false;
  if (a.host !== b.host) return false;
  if (a.port !== b.port) return false;
  return true;
}

function __eq_SessionNode$Addrs(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "List": {
      if (!__eq_Addr(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_SessionNode$RunError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Cancelled": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "Protocol": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "HostGone": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Left": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Listen": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "Accept": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Connect": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "NoOffer": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "AlreadyOffered": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Unauthorized": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_SessionNode$OfferCount(a, b) {
  if (a.active !== b.active) return false;
  return true;
}

function __eq_SessionNode$Offer(a, b) {
  if (!__eq_Cap(a.node, b.node)) return false;
  if (a.proto !== b.proto) return false;
  if (a.fingerprint !== b.fingerprint) return false;
  if (!__eq_List(a.roles, b.roles)) return false;
  if (!__eq_List(a.compat, b.compat)) return false;
  if (a.my_role !== b.my_role) return false;
  if (a.capacity !== b.capacity) return false;
  if (a.name !== b.name) return false;
  if (a.id !== b.id) return false;
  if (!__eq_Vault(a.flags, b.flags)) return false;
  if (!__eq_Vault(a.strs, b.strs)) return false;
  if (a.start !== b.start) return false;
  if (!__eq_Pid(a.worker, b.worker)) return false;
  return true;
}

function __eq_SessionNode__OfferActor_State(a, b) {
  if (a.active !== b.active) return false;
  return true;
}

function __eq_SessionNode__OfferActor_Msg(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Invite": {
      if (!__eq_Offer(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (!__eq_List(a._3, b._3)) return false;
      if (!__eq_GlobalPid$Pid(a._4, b._4)) return false;
      if (a._5 !== b._5) return false;
      if (a._6 !== b._6) return false;
      return true;
    }
    case "Withdraw": {
      if (!__eq_Offer(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "Ended": {
      if (!__eq_Offer(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "Close": {
      if (!__eq_Offer(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_SessionNode__OfferActor_Actor(a, b) {
  if (a.$d_dispatch !== b.$d_dispatch) return false;
  if (a.$e_alive !== b.$e_alive) return false;
  if (a.active !== b.active) return false;
  return true;
}

function __eq_SessionNode__ApInbox_State(a, b) {
  if (a.n !== b.n) return false;
  return true;
}

function __eq_SessionNode__ApInbox_Msg(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Nop": {
      return true;
    }
  }
  return true;
}

function __eq_SessionNode__ApInbox_Actor(a, b) {
  if (a.$d_dispatch !== b.$d_dispatch) return false;
  if (a.$e_alive !== b.$e_alive) return false;
  if (a.n !== b.n) return false;
  return true;
}

function __eq_SessionNode$ApWait(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Answered": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "OfferGone": {
      return true;
    }
    case "NoAnswer": {
      return true;
    }
  }
  return true;
}

function __eq_SessionNode$ApMix(a, b) {
  if (a.fp !== b.fp) return false;
  if (!__eq_List(a.rows, b.rows)) return false;
  if (a.me !== b.me) return false;
  if (a.other !== b.other) return false;
  if (a.older !== b.older) return false;
  if (!__eq_List(a.filled, b.filled)) return false;
  return true;
}

function __eq_Topology$TopoPlacement(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "PlaceEverywhere": {
      return true;
    }
    case "PlaceOn": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "PlaceCount": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "PlaceCountOn": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "PlaceNowhere": {
      return true;
    }
  }
  return true;
}

function __eq_Topology$TopoOpened(a, b) {
  if (!__eq_SessionNode$Offer(a.ap, b.ap)) return false;
  if (a.alive !== b.alive) return false;
  if (a.capacity !== b.capacity) return false;
  if (a.stop !== b.stop) return false;
  return true;
}

function __eq_Topology$TopoRole(a, b) {
  if (a.name !== b.name) return false;
  if (!__eq_TopoPlacement(a.place, b.place)) return false;
  if (a.capacity !== b.capacity) return false;
  if (a.pinned !== b.pinned) return false;
  if (a.open !== b.open) return false;
  return true;
}

function __eq_Topology$TopoAnchorState(a, b) {
  if (a.topology_anchor_marks !== b.topology_anchor_marks) return false;
  return true;
}

function __eq_Topology__Anchor_State(a, b) {
  if (a.topology_anchor_marks !== b.topology_anchor_marks) return false;
  return true;
}

function __eq_Topology__Anchor_Msg(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Nop": {
      return true;
    }
    case "Respawn": {
      if (!__eq_Cap(a._0, b._0)) return false;
      if (!__eq_TopoState(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Topology__Anchor_Actor(a, b) {
  if (a.$d_dispatch !== b.$d_dispatch) return false;
  if (a.$e_alive !== b.$e_alive) return false;
  if (a.topology_anchor_marks !== b.topology_anchor_marks) return false;
  return true;
}

function __eq_Topology$TopoState(a, b) {
  if (!__eq_Vault(a.meta, b.meta)) return false;
  if (!__eq_Vault(a.strs, b.strs)) return false;
  if (!__eq_Vault(a.offers, b.offers)) return false;
  if (!__eq_Vault(a.draining, b.draining)) return false;
  if (!__eq_Vault(a.roles, b.roles)) return false;
  if (!__eq_Vault(a.anchor, b.anchor)) return false;
  return true;
}

function __eq_Topology$TopoDesired(a, b) {
  if (a.d_name !== b.d_name) return false;
  if (!__eq_TopoPlacement(a.d_place, b.d_place)) return false;
  if (a.d_capacity !== b.d_capacity) return false;
  return true;
}

function __eq_Control$CtlHosts(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "HostsCanary": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "HostsRest": {
      return true;
    }
    case "HostsAll": {
      return true;
    }
  }
  return true;
}

function __eq_Control$CtlAction(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "DoActivate": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "DoTopology": {
      return true;
    }
    case "DoDrain": {
      return true;
    }
    case "DoCerts": {
      return true;
    }
  }
  return true;
}

function __eq_Control$CtlGate(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "GateNone": {
      return true;
    }
    case "GateHealthy": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Control$CtlStep(a, b) {
  if (a.id !== b.id) return false;
  if (!__eq_List(a.pools, b.pools)) return false;
  if (!__eq_CtlHosts(a.hosts, b.hosts)) return false;
  if (!__eq_CtlAction(a.action, b.action)) return false;
  if (!__eq_CtlGate(a.gate, b.gate)) return false;
  if (a.batch !== b.batch) return false;
  return true;
}

function __eq_Control$CtlBuild(a, b) {
  if (a.name !== b.name) return false;
  if (a.base !== b.base) return false;
  if (a.manifest !== b.manifest) return false;
  return true;
}

function __eq_Control$CtlDrain(a, b) {
  if (a.epoch !== b.epoch) return false;
  if (a.soft_ms !== b.soft_ms) return false;
  if (a.hard_ms !== b.hard_ms) return false;
  return true;
}

function __eq_Control$CtlLine(a, b) {
  if (a.step !== b.step) return false;
  if (a.text !== b.text) return false;
  return true;
}

function __eq_Control$CtlCert(a, b) {
  if (a.node !== b.node) return false;
  if (a.cert !== b.cert) return false;
  return true;
}

function __eq_Control$CtlRelease(a, b) {
  if (a.seq !== b.seq) return false;
  if (a.parent !== b.parent) return false;
  if (a.env !== b.env) return false;
  if (a.topology !== b.topology) return false;
  if (!__eq_List(a.builds, b.builds)) return false;
  if (!__eq_List(a.steps, b.steps)) return false;
  if (!__eq_List(a.lines, b.lines)) return false;
  if (!__eq_List(a.certs, b.certs)) return false;
  if (!__eq_List(a.revokes, b.revokes)) return false;
  if (!__eq_Option(a.drain, b.drain)) return false;
  if (a.signature !== b.signature) return false;
  return true;
}

function __eq_Control$CtlMember(a, b) {
  if (a.node !== b.node) return false;
  if (!__eq_List(a.pools, b.pools)) return false;
  return true;
}

function __eq_Control$CtlVersion(a, b) {
  if (a.build !== b.build) return false;
  if (a.manifest !== b.manifest) return false;
  return true;
}

function __eq_Control$CtlFailure(a, b) {
  if (a.seq !== b.seq) return false;
  if (a.step !== b.step) return false;
  if (a.why !== b.why) return false;
  return true;
}

function __eq_Control$AgentReport(a, b) {
  if (a.node !== b.node) return false;
  if (a.seq !== b.seq) return false;
  if (a.versions !== b.versions) return false;
  if (a.topology !== b.topology) return false;
  if (a.drained !== b.drained) return false;
  if (a.healthy !== b.healthy) return false;
  if (a.failed_seq !== b.failed_seq) return false;
  if (a.failed_step !== b.failed_step) return false;
  if (a.failed_why !== b.failed_why) return false;
  if (a.detail !== b.detail) return false;
  if (a.pools !== b.pools) return false;
  if (a.certs !== b.certs) return false;
  return true;
}

function __eq_Control$StepOrder(a, b) {
  if (a.seq !== b.seq) return false;
  if (a.release !== b.release) return false;
  if (a.step !== b.step) return false;
  if (a.node !== b.node) return false;
  if (a.action !== b.action) return false;
  if (a.want !== b.want) return false;
  if (a.artifacts !== b.artifacts) return false;
  if (a.lines !== b.lines) return false;
  return true;
}

function __eq_Control$StepResult(a, b) {
  if (a.seq !== b.seq) return false;
  if (a.step !== b.step) return false;
  if (a.node !== b.node) return false;
  if (a.ok !== b.ok) return false;
  if (a.detail !== b.detail) return false;
  return true;
}

function __eq_Control$CtlObs(a, b) {
  if (!__eq_AgentReport(a.report, b.report)) return false;
  if (!__eq_Option(a.healthy_since, b.healthy_since)) return false;
  return true;
}

function __eq_Control$CtlDecision(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "RolloutApply": {
      if (a._0 !== b._0) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
    case "RolloutWait": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "RolloutHalted": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
    case "RolloutComplete": {
      return true;
    }
    case "RolloutBehind": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Control$CtlLeader(a, b) {
  if (!__eq_Option(a.release, b.release)) return false;
  if (!__eq_List(a.obs, b.obs)) return false;
  if (!__eq_List(a.inflight, b.inflight)) return false;
  if (!__eq_Option(a.halted, b.halted)) return false;
  return true;
}

function __eq_Control$AgentOps(a, b) {
  if (a.report !== b.report) return false;
  if (a.has !== b.has) return false;
  if (a.request !== b.request) return false;
  return true;
}

function __eq_Control$CertOps(a, b) {
  if (a.name !== b.name) return false;
  if (!__eq_Bytes(a.deploy_key, b.deploy_key)) return false;
  if (a.serial !== b.serial) return false;
  if (a.replace !== b.replace) return false;
  if (a.revoke !== b.revoke) return false;
  if (a.floor !== b.floor) return false;
  return true;
}

function __eq_Control$CtlChunk(a, b) {
  if (a.offset !== b.offset) return false;
  if (a.data !== b.data) return false;
  if (a.last !== b.last) return false;
  return true;
}

function __eq_Control$CtlNext(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "NextOrder": {
      if (!__eq_StepOrder(a._0, b._0)) return false;
      return true;
    }
    case "NextPoll": {
      return true;
    }
    case "NextBye": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_Control$ControlOps(a, b) {
  if (a.report !== b.report) return false;
  if (a.stepped !== b.stepped) return false;
  if (a.next !== b.next) return false;
  if (a.head !== b.head) return false;
  return true;
}

function __eq_Js$Dom$Node(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
  }
  return true;
}

function __eq_Js$Dom$Event(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
  }
  return true;
}

function __eq_Js$Canvas$Context(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
  }
  return true;
}

function __eq_Js$Canvas$Image(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
  }
  return true;
}

function __eq_Js$Audio$Ctx(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
  }
  return true;
}

function __eq_TetrisLogic$Piece(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "I": {
      return true;
    }
    case "O": {
      return true;
    }
    case "T": {
      return true;
    }
    case "S": {
      return true;
    }
    case "Z": {
      return true;
    }
    case "J": {
      return true;
    }
    case "L": {
      return true;
    }
  }
  return true;
}

function Js$Dom$find(id) {
  {
    const $rc_2416 = dom_get_element_by_id$clo._0(dom_get_element_by_id$clo, id);
    return $rc_2416;
  }
}
const Js$Dom$find$clo = { _0: ($_, id) => Js$Dom$find(id) };

function Js$Dom$create(tag) {
  {
    const $rc_2419 = dom_create_element$clo._0(dom_create_element$clo, tag);
    return $rc_2419;
  }
}
const Js$Dom$create$clo = { _0: ($_, tag) => Js$Dom$create(tag) };

function Js$Dom$append(parent, child) {
  {
    const $rc_2422 = dom_append_child$clo._0(dom_append_child$clo, parent, child);
    return $rc_2422;
  }
}
const Js$Dom$append$clo = { _0: ($_, parent, child) => Js$Dom$append(parent, child) };

function Js$Dom$get_attr(el, name) {
  {
    const $rc_2435 = dom_get_attribute$clo._0(dom_get_attribute$clo, el, name);
    return $rc_2435;
  }
}
const Js$Dom$get_attr$clo = { _0: ($_, el, name) => Js$Dom$get_attr(el, name) };

function Js$Dom$set_attr(el, name, val) {
  {
    const $rc_2436 = dom_set_attribute$clo._0(dom_set_attribute$clo, el, name, val);
    return $rc_2436;
  }
}
const Js$Dom$set_attr$clo = { _0: ($_, el, name, val) => Js$Dom$set_attr(el, name, val) };

function Js$Dom$add_class(el, cls) {
  {
    const $rc_2439 = dom_class_add$clo._0(dom_class_add$clo, el, cls);
    return $rc_2439;
  }
}
const Js$Dom$add_class$clo = { _0: ($_, el, cls) => Js$Dom$add_class(el, cls) };

function Js$Dom$set_style(el, prop, val) {
  {
    const $rc_2443 = dom_set_style$clo._0(dom_set_style$clo, el, prop, val);
    return $rc_2443;
  }
}
const Js$Dom$set_style$clo = { _0: ($_, el, prop, val) => Js$Dom$set_style(el, prop, val) };

function Js$Dom$listen(el, event, handler) {
  {
    const $rc_2447 = dom_add_event_listener$clo._0(dom_add_event_listener$clo, el, event, handler);
    return $rc_2447;
  }
}
const Js$Dom$listen$clo = { _0: ($_, el, event, handler) => Js$Dom$listen(el, event, handler) };

function Js$Dom$set_timeout(ms, cb) {
  return dom_set_timeout$clo._0(dom_set_timeout$clo, ms, cb);
}
const Js$Dom$set_timeout$clo = { _0: ($_, ms, cb) => Js$Dom$set_timeout(ms, cb) };

function TetrisLogic$piece_cells(p) {
  switch (p.$) {
    case "I": {
      {
        const $t46641 = { _0: 0, _1: 1 };
        {
          const $t46642 = { _0: 1, _1: 1 };
          {
            const $t46643 = { _0: 2, _1: 1 };
            {
              const $t46644 = { _0: 3, _1: 1 };
              {
                const $t46645 = { $: "Nil" };
                {
                  const $t46646 = { $: "Cons", _0: $t46644, _1: $t46645 };
                  {
                    const $t46647 = { $: "Cons", _0: $t46643, _1: $t46646 };
                    {
                      const $t46648 = { $: "Cons", _0: $t46642, _1: $t46647 };
                      return { $: "Cons", _0: $t46641, _1: $t46648 };
                    }
                  }
                }
              }
            }
          }
        }
      }
      break;
    }
    case "O": {
      {
        const $t46649 = { _0: 1, _1: 1 };
        {
          const $t46650 = { _0: 2, _1: 1 };
          {
            const $t46651 = { _0: 1, _1: 2 };
            {
              const $t46652 = { _0: 2, _1: 2 };
              {
                const $t46653 = { $: "Nil" };
                {
                  const $t46654 = { $: "Cons", _0: $t46652, _1: $t46653 };
                  {
                    const $t46655 = { $: "Cons", _0: $t46651, _1: $t46654 };
                    {
                      const $t46656 = { $: "Cons", _0: $t46650, _1: $t46655 };
                      return { $: "Cons", _0: $t46649, _1: $t46656 };
                    }
                  }
                }
              }
            }
          }
        }
      }
      break;
    }
    case "T": {
      {
        const $t46657 = { _0: 1, _1: 1 };
        {
          const $t46658 = { _0: 0, _1: 2 };
          {
            const $t46659 = { _0: 1, _1: 2 };
            {
              const $t46660 = { _0: 2, _1: 2 };
              {
                const $t46661 = { $: "Nil" };
                {
                  const $t46662 = { $: "Cons", _0: $t46660, _1: $t46661 };
                  {
                    const $t46663 = { $: "Cons", _0: $t46659, _1: $t46662 };
                    {
                      const $t46664 = { $: "Cons", _0: $t46658, _1: $t46663 };
                      return { $: "Cons", _0: $t46657, _1: $t46664 };
                    }
                  }
                }
              }
            }
          }
        }
      }
      break;
    }
    case "S": {
      {
        const $t46665 = { _0: 1, _1: 1 };
        {
          const $t46666 = { _0: 2, _1: 1 };
          {
            const $t46667 = { _0: 0, _1: 2 };
            {
              const $t46668 = { _0: 1, _1: 2 };
              {
                const $t46669 = { $: "Nil" };
                {
                  const $t46670 = { $: "Cons", _0: $t46668, _1: $t46669 };
                  {
                    const $t46671 = { $: "Cons", _0: $t46667, _1: $t46670 };
                    {
                      const $t46672 = { $: "Cons", _0: $t46666, _1: $t46671 };
                      return { $: "Cons", _0: $t46665, _1: $t46672 };
                    }
                  }
                }
              }
            }
          }
        }
      }
      break;
    }
    case "Z": {
      {
        const $t46673 = { _0: 0, _1: 1 };
        {
          const $t46674 = { _0: 1, _1: 1 };
          {
            const $t46675 = { _0: 1, _1: 2 };
            {
              const $t46676 = { _0: 2, _1: 2 };
              {
                const $t46677 = { $: "Nil" };
                {
                  const $t46678 = { $: "Cons", _0: $t46676, _1: $t46677 };
                  {
                    const $t46679 = { $: "Cons", _0: $t46675, _1: $t46678 };
                    {
                      const $t46680 = { $: "Cons", _0: $t46674, _1: $t46679 };
                      return { $: "Cons", _0: $t46673, _1: $t46680 };
                    }
                  }
                }
              }
            }
          }
        }
      }
      break;
    }
    case "J": {
      {
        const $t46681 = { _0: 0, _1: 1 };
        {
          const $t46682 = { _0: 0, _1: 2 };
          {
            const $t46683 = { _0: 1, _1: 2 };
            {
              const $t46684 = { _0: 2, _1: 2 };
              {
                const $t46685 = { $: "Nil" };
                {
                  const $t46686 = { $: "Cons", _0: $t46684, _1: $t46685 };
                  {
                    const $t46687 = { $: "Cons", _0: $t46683, _1: $t46686 };
                    {
                      const $t46688 = { $: "Cons", _0: $t46682, _1: $t46687 };
                      return { $: "Cons", _0: $t46681, _1: $t46688 };
                    }
                  }
                }
              }
            }
          }
        }
      }
      break;
    }
    case "L": {
      {
        const $t46689 = { _0: 2, _1: 1 };
        {
          const $t46690 = { _0: 0, _1: 2 };
          {
            const $t46691 = { _0: 1, _1: 2 };
            {
              const $t46692 = { _0: 2, _1: 2 };
              {
                const $t46693 = { $: "Nil" };
                {
                  const $t46694 = { $: "Cons", _0: $t46692, _1: $t46693 };
                  {
                    const $t46695 = { $: "Cons", _0: $t46691, _1: $t46694 };
                    {
                      const $t46696 = { $: "Cons", _0: $t46690, _1: $t46695 };
                      return { $: "Cons", _0: $t46689, _1: $t46696 };
                    }
                  }
                }
              }
            }
          }
        }
      }
      break;
    }
    default: {
      return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
    }
  }
}
const TetrisLogic$piece_cells$clo = { _0: ($_, p) => TetrisLogic$piece_cells(p) };

function TetrisLogic$level_for_lines(total_lines) {
  return (10 === 0 ? march_div_zero() : (total_lines - total_lines % 10) / 10);
}
const TetrisLogic$level_for_lines$clo = { _0: ($_, total_lines) => TetrisLogic$level_for_lines(total_lines) };

function TetrisLogic$rotate_cell(c) {
  const $f46706 = c._0;
  const $f46707 = c._1;
  {
    const y = $f46707;
    {
      const x = $f46706;
      {
        const $t46705 = ((3 - y) < 4611686018427387904 && (3 - y) >= -4611686018427387904 ? (3 - y) : march_int_ovf((3 - y), 1));
        return { _0: $t46705, _1: x };
      }
    }
  }
}
const TetrisLogic$rotate_cell$clo = { _0: ($_, c) => TetrisLogic$rotate_cell(c) };

function TetrisLogic$clear_lines(board) {
  {
    let rows;
    {
      const go_i5176 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
      {
        const $t802_i5178 = { $: "Nil" };
        rows = go$apply$0_List_range(go_i5176, 19, $t802_i5178);
      }
    }
    {
      let $t46755;
      $t46755 = { $: "$Clo_$lam0_TetrisLogic_clear_lines$0_TetrisLogic_clear_lines", _0: $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines, _1: board };
      {
        const kept_rows = List$filter$List_Int$Fn_Int_Bool(rows, $t46755);
        {
          let cleared;
          {
            let $t46757;
            {  };
            $t46757 = List$length_onto$List_Int$Int(kept_rows, 0);
            cleared = ((20 - $t46757) < 4611686018427387904 && (20 - $t46757) >= -4611686018427387904 ? (20 - $t46757) : march_int_ovf((20 - $t46757), 1));
          }
          {
            const $t46759 = { $: "$Clo_$lam1_TetrisLogic_clear_lines$1_TetrisLogic_clear_lines", _0: $lam1_TetrisLogic_clear_lines$apply$1_TetrisLogic_clear_lines, _1: board };
            {
              let kept_cells;
              {
                const f_i5171 = $t46759;
                {
                  const $t894_i5172 = { $: "Nil" };
                  kept_cells = List$flat_map_go$List_Int$List_Int$Fn_Int_List_Int($t894_i5172, kept_rows, f_i5171);
                }
              }
              {
                const $t46761 = ((cleared * 10) < 4611686018427387904 && (cleared * 10) >= -4611686018427387904 ? (cleared * 10) : march_int_ovf((cleared * 10), 2));
                {
                  let blank_cells;
                  {
                    const go_i5168 = { $: "$Clo_go$0_List_repeat_Int_Int", _0: go$apply$0_List_repeat_Int_Int, _1: 0 };
                    {
                      const $t797_i5169 = { $: "Nil" };
                      blank_cells = go$apply$0_List_repeat_Int_Int(go_i5168, $t46761, $t797_i5169);
                    }
                  }
                  {
                    let new_board;
                    {
                      let $t46762;
                      {
                        const xs_i13526 = blank_cells;
                        {
                          const ys_i13527 = kept_cells;
                          switch (xs_i13526.$) {
                            case "Nil": {
                              $t46762 = kept_cells;
                              break;
                            }
                            case "Cons": {
                              const $f873_i13528 = xs_i13526._0;
                              const $f874_i13529 = xs_i13526._1;
                              {
                                const t_i13530 = $f874_i13529;
                                {
                                  const h_i13531 = $f873_i13528;
                                  {
                                    const $trmc11_i13532 = { $: "Cons", _0: h_i13531, _1: null };
                                    List$append$dps$List_Int$List_Int$List_Int(t_i13530, kept_cells, $trmc11_i13532);
                                    $t46762 = $trmc11_i13532;
                                  }
                                }
                              }
                              break;
                            }
                            default: {
                              throw march_panic_error("panic: ", "non-exhaustive pattern match");
                              break;
                            }
                          }
                        }
                      }
                      new_board = Array$from_list$List_Int($t46762);
                    }
                    return { _0: new_board, _1: cleared };
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
const TetrisLogic$clear_lines$clo = { _0: ($_, board) => TetrisLogic$clear_lines(board) };

function int_list_to_string(xs) {
  {
    const $t46764 = { $: "$Clo_$lam0_int_list_to_string$0_int_list_to_string", _0: $lam0_int_list_to_string$apply$0_int_list_to_string };
    {
      let $t46765;
      {
        const xs_i13533 = xs;
        {
          const f_i13534 = $t46764;
          switch (xs_i13533.$) {
            case "Nil": {
              $t46765 = { $: "Nil" };
              break;
            }
            case "Cons": {
              const $f881_i13535 = xs_i13533._0;
              const $f882_i13536 = xs_i13533._1;
              {
                const t_i13537 = $f882_i13536;
                {
                  const h_i13538 = $f881_i13535;
                  {
                    let $t879_i13539;
                    $t879_i13539 = f_i13534._0(f_i13534, h_i13538);
                    {
                      const $trmc15_i13540 = { $: "Cons", _0: $t879_i13539, _1: null };
                      List$map$dps$List_Int$Fn_Int_String$List_String(t_i13537, f_i13534, $trmc15_i13540);
                      $t46765 = $trmc15_i13540;
                    }
                  }
                }
              }
              break;
            }
            default: {
              throw march_panic_error("panic: ", "non-exhaustive pattern match");
              break;
            }
          }
        }
      }
      {
        const $rc_2498 = march_string_join($t46765, ",");
        return $rc_2498;
      }
    }
  }
}
const int_list_to_string$clo = { _0: ($_, xs) => int_list_to_string(xs) };

function piece_to_string(p) {
  switch (p.$) {
    case "I": {
      return "I";
      break;
    }
    case "O": {
      return "O";
      break;
    }
    case "T": {
      return "T";
      break;
    }
    case "S": {
      return "S";
      break;
    }
    case "Z": {
      return "Z";
      break;
    }
    case "J": {
      return "J";
      break;
    }
    case "L": {
      return "L";
      break;
    }
    default: {
      return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
    }
  }
}
const piece_to_string$clo = { _0: ($_, p) => piece_to_string(p) };

function next_piece(rng) {
  {
    const $t46788 = { $: "I" };
    {
      const $t46789 = { $: "O" };
      {
        const $t46790 = { $: "T" };
        {
          const $t46791 = { $: "S" };
          {
            const $t46792 = { $: "Z" };
            {
              const $t46793 = { $: "J" };
              {
                const $t46794 = { $: "L" };
                {
                  const $t46795 = { $: "Nil" };
                  {
                    const $t46796 = { $: "Cons", _0: $t46794, _1: $t46795 };
                    {
                      const $t46797 = { $: "Cons", _0: $t46793, _1: $t46796 };
                      {
                        const $t46798 = { $: "Cons", _0: $t46792, _1: $t46797 };
                        {
                          const $t46799 = { $: "Cons", _0: $t46791, _1: $t46798 };
                          {
                            const $t46800 = { $: "Cons", _0: $t46790, _1: $t46799 };
                            {
                              const $t46801 = { $: "Cons", _0: $t46789, _1: $t46800 };
                              {
                                const pieces = { $: "Cons", _0: $t46788, _1: $t46801 };
                                {
                                  let rng2;
                                  {
                                    const $t46770_i12311 = ((rng * 16807) < 4611686018427387904 && (rng * 16807) >= -4611686018427387904 ? (rng * 16807) : march_int_ovf((rng * 16807), 2));
                                    rng2 = (2147483647 === 0 ? march_mod_zero() : $t46770_i12311 % 2147483647);
                                  }
                                  {
                                    const idx = (7 === 0 ? march_mod_zero() : rng2 % 7);
                                    {
                                      let result;
                                      {
                                        const $t46802 = List$nth$List_Piece$Int(pieces, idx);
                                        result = { _0: $t46802, _1: rng2 };
                                      }
                                      return result;
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
const next_piece$clo = { _0: ($_, rng) => next_piece(rng) };

function state_el() {
  {
    const $t46803 = Js$Dom$find("game-state");
    switch ($t46803.$) {
      case "Some": {
        const $f46804 = $t46803._0;
        {
          const el = $f46804;
          return el;
        }
        break;
      }
      case "None": {
        march_panic_site("tetris.march", 254, 18, 62);
        return (() => { throw march_panic_error("panic: ", "Tetris: #game-state element missing"); })();
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
  }
}
const state_el$clo = { _0: ($_) => state_el() };

function get_int_attr(el, name, _default) {
  {
    const $t46805 = Js$Dom$get_attr(el, name);
    switch ($t46805.$) {
      case "Some": {
        const $f46807 = $t46805._0;
        {
          const s = $f46807;
          {
            let $t46806;
            {
              const $rc_2500 = march_string_to_int(s);
              $t46806 = $rc_2500;
            }
            {
              const $rc_2499 = Option$unwrap_or$Option_Int$Int($t46806, _default);
              return $rc_2499;
            }
          }
        }
        break;
      }
      case "None": {
        return _default;
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
  }
}
const get_int_attr$clo = { _0: ($_, el, name, _default) => get_int_attr(el, name, _default) };

function get_str_attr(el, name, _default) {
  {
    const $t46808 = Js$Dom$get_attr(el, name);
    switch ($t46808.$) {
      case "Some": {
        const $f46809 = $t46808._0;
        {
          const s = $f46809;
          return s;
        }
        break;
      }
      case "None": {
        return _default;
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
  }
}
const get_str_attr$clo = { _0: ($_, el, name, _default) => get_str_attr(el, name, _default) };

function rotate_n($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const cells = $tco_a0;
    const n = $tco_a1;
    if (n === 0) {
      return cells;
    } else {
      {
        let $t46810;
        {
          const xs_i13541 = cells;
          {
            const f_i13542 = TetrisLogic$rotate_cell$clo;
            switch (xs_i13541.$) {
              case "Nil": {
                $t46810 = { $: "Nil" };
                break;
              }
              case "Cons": {
                const $f881_i13543 = xs_i13541._0;
                const $f882_i13544 = xs_i13541._1;
                {
                  const t_i13545 = $f882_i13544;
                  {
                    const h_i13546 = $f881_i13543;
                    {
                      let $t879_i13547;
                      $t879_i13547 = f_i13542._0(f_i13542, h_i13546);
                      {
                        const $trmc15_i13548 = { $: "Cons", _0: $t879_i13547, _1: null };
                        List$map$dps$List_T_Int_Int$Fn_T_Int_Int_T_Int_Int$List_T_Int_Int(t_i13545, f_i13542, $trmc15_i13548);
                        $t46810 = $trmc15_i13548;
                      }
                    }
                  }
                }
                break;
              }
              default: {
                throw march_panic_error("panic: ", "non-exhaustive pattern match");
                break;
              }
            }
          }
        }
        {
          const $t46811 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
          {
            $tco_a0 = $t46810;
            $tco_a1 = $t46811;
            continue __tco;
          }
        }
      }
    }
    return undefined;
  }
}
const rotate_n$clo = { _0: ($_, cells, n) => rotate_n(cells, n) };

function spawn_piece(next, board, rng) {
  {
    const cells = TetrisLogic$piece_cells(next);
    {
      let over;
      {
        const $t46730_i5188 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: 3, _3: 0 };
        over = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t46730_i5188);
      }
      {
        const $t46814 = next_piece(rng);
        const $f46815 = $t46814._0;
        const $f46816 = $t46814._1;
        {
          const rng2 = $f46816;
          {
            const next2 = $f46815;
            return { _0: next, _1: 0, _2: 3, _3: 0, _4: next2, _5: rng2, _6: over };
          }
        }
      }
    }
  }
}
const spawn_piece$clo = { _0: ($_, next, board, rng) => spawn_piece(next, board, rng) };

function set_text_if_found(id, text) {
  {
    const $t46857 = Js$Dom$find(id);
    switch ($t46857.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f46858 = $t46857._0;
        {
          const el = $f46858;
          {
            const el_i12312 = el;
            {
              const text_i12313 = text;
              {
                const $rc_2432_i12314 = dom_set_text$clo._0(dom_set_text$clo, el, text);
                return $rc_2432_i12314;
              }
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
  }
}
const set_text_if_found$clo = { _0: ($_, id, text) => set_text_if_found(id, text) };

function with_state(f) {
  {
    const el = state_el();
    {
      let over;
      {
        let $t46859;
        $t46859 = get_str_attr(el, "data-over", "false");
        {
          const $rc_2509 = ($t46859 === "true");
          over = $rc_2509;
        }
      }
      if (over === true) {
        return {  };
      } else if (over === false) {
        {
          let board;
          {
            let $t46860;
            $t46860 = get_str_attr(el, "data-board", "");
            {
              let $t46861;
              {
                let $rc_2508;
                {
                  const $t46766_i5218 = march_string_split($t46860, ",");
                  {
                    const $t46769_i5219 = { $: "$Clo_$lam0_string_to_int_list$0_string_to_int_list", _0: $lam0_string_to_int_list$apply$0_string_to_int_list };
                    $rc_2508 = List$map$List_String$Fn_String_Int($t46766_i5218, $t46769_i5219);
                  }
                }
                $t46861 = $rc_2508;
              }
              board = Array$from_list$List_Int($t46861);
            }
          }
          {
            let piece;
            {
              let $t46862;
              $t46862 = get_str_attr(el, "data-piece", "I");
              {
                let $rc_2507;
                if ($t46862 === "I") {
                  $rc_2507 = { $: "I" };
                } else if ($t46862 === "O") {
                  $rc_2507 = { $: "O" };
                } else if ($t46862 === "T") {
                  $rc_2507 = { $: "T" };
                } else if ($t46862 === "S") {
                  $rc_2507 = { $: "S" };
                } else if ($t46862 === "Z") {
                  $rc_2507 = { $: "Z" };
                } else if ($t46862 === "J") {
                  $rc_2507 = { $: "J" };
                } else {
                  $rc_2507 = { $: "L" };
                }
                piece = $rc_2507;
              }
            }
            {
              let rot;
              rot = get_int_attr(el, "data-rot", 0);
              {
                let x;
                x = get_int_attr(el, "data-x", 3);
                {
                  let y;
                  y = get_int_attr(el, "data-y", 0);
                  {
                    let next;
                    {
                      let $t46863;
                      $t46863 = get_str_attr(el, "data-next", "O");
                      {
                        let $rc_2506;
                        if ($t46863 === "I") {
                          $rc_2506 = { $: "I" };
                        } else if ($t46863 === "O") {
                          $rc_2506 = { $: "O" };
                        } else if ($t46863 === "T") {
                          $rc_2506 = { $: "T" };
                        } else if ($t46863 === "S") {
                          $rc_2506 = { $: "S" };
                        } else if ($t46863 === "Z") {
                          $rc_2506 = { $: "Z" };
                        } else if ($t46863 === "J") {
                          $rc_2506 = { $: "J" };
                        } else {
                          $rc_2506 = { $: "L" };
                        }
                        next = $rc_2506;
                      }
                    }
                    {
                      let score;
                      score = get_int_attr(el, "data-score", 0);
                      {
                        let lines;
                        lines = get_int_attr(el, "data-lines", 0);
                        {
                          let rng;
                          rng = get_int_attr(el, "data-rng", 1);
                          {
                            let seq;
                            seq = get_int_attr(el, "data-seq", 0);
                            {
                              const $t46864 = f._0(f, board, piece, rot, x, y, next, score, lines, rng);
                              const $f46884 = $t46864._0;
                              const $f46885 = $t46864._1;
                              const $f46886 = $t46864._2;
                              const $f46887 = $t46864._3;
                              const $f46888 = $t46864._4;
                              const $f46889 = $t46864._5;
                              const $f46890 = $t46864._6;
                              const $f46891 = $t46864._7;
                              const $f46892 = $t46864._8;
                              const $f46893 = $t46864._9;
                              {
                                const over2 = $f46893;
                                {
                                  const rng2 = $f46892;
                                  {
                                    const lines2 = $f46891;
                                    {
                                      const score2 = $f46890;
                                      {
                                        const next2 = $f46889;
                                        {
                                          const y2 = $f46888;
                                          {
                                            const x2 = $f46887;
                                            {
                                              const rot2 = $f46886;
                                              {
                                                const piece2 = $f46885;
                                                {
                                                  const board2 = $f46884;
                                                  {
                                                    let $eff;
                                                    {
                                                      let $t46822_i5213;
                                                      {
                                                        const go_i13469 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                                                        {
                                                          const $t802_i13471 = { $: "Nil" };
                                                          $t46822_i5213 = go$apply$0_List_range(go_i13469, 19, $t802_i13471);
                                                        }
                                                      }
                                                      {
                                                        const $t46834_i5214 = { $: "$Clo_$lam0_render_board$0_render_board", _0: $lam0_render_board$apply$0_render_board, _1: board2 };
                                                        {
                                                          const f_i13465 = $t46834_i5214;
                                                          {
                                                            const go_i13466 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i13465 };
                                                            $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i13466, $t46822_i5213);
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                  {
                                                    let $eff;
                                                    if (over2 === false) {
                                                      {
                                                        const base_cells_i5208 = TetrisLogic$piece_cells(piece2);
                                                        {
                                                          const rotated_i5209 = rotate_n(base_cells_i5208, rot2);
                                                          {
                                                            const $t46856_i5210 = { $: "$Clo_$lam0_render_falling$0_render_falling", _0: $lam0_render_falling$apply$0_render_falling, _1: x2, _2: y2, _3: piece2 };
                                                            {
                                                              const f_i13462 = $t46856_i5210;
                                                              {
                                                                const go_i13463 = { $: "$Clo_go$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_", _0: go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_, _1: f_i13462 };
                                                                $eff = go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_(go_i13463, rotated_i5209);
                                                              }
                                                            }
                                                          }
                                                        }
                                                      }
                                                    } else if (over2 === true) {
                                                      $eff = {  };
                                                    } else {
                                                      throw march_panic_error("panic: ", "non-exhaustive pattern match");
                                                    }
                                                  }
                                                  {
                                                    let $eff;
                                                    {
                                                      let $t46866;
                                                      {
                                                        const $t46865 = String(score2);
                                                        {
                                                          const $rc_2505 = ("Score: " + $t46865);
                                                          $t46866 = $rc_2505;
                                                        }
                                                      }
                                                      $eff = set_text_if_found("score", $t46866);
                                                    }
                                                  }
                                                  {
                                                    let $eff;
                                                    {
                                                      let $t46869;
                                                      {
                                                        let $t46868;
                                                        {
                                                          const $t46867 = TetrisLogic$level_for_lines(lines2);
                                                          $t46868 = String($t46867);
                                                        }
                                                        {
                                                          const $rc_2504 = ("Level: " + $t46868);
                                                          $t46869 = $rc_2504;
                                                        }
                                                      }
                                                      $eff = set_text_if_found("level", $t46869);
                                                    }
                                                  }
                                                  {
                                                    let $eff;
                                                    {
                                                      let $t46871;
                                                      {
                                                        const $t46870 = piece_to_string(next2);
                                                        {
                                                          const $rc_2503 = ("Next: " + $t46870);
                                                          $t46871 = $rc_2503;
                                                        }
                                                      }
                                                      $eff = set_text_if_found("next", $t46871);
                                                    }
                                                  }
                                                  {
                                                    let game_over_text;
                                                    if (over2 === true) {
                                                      game_over_text = "Game Over — press R to restart";
                                                    } else if (over2 === false) {
                                                      game_over_text = "";
                                                    } else {
                                                      throw march_panic_error("panic: ", "non-exhaustive pattern match");
                                                    }
                                                    set_text_if_found("game-over", game_over_text);
                                                    {
                                                      let $eff;
                                                      {
                                                        let $t46873;
                                                        {
                                                          let $t46872;
                                                          {
                                                            const $t8665_i5201 = { $: "Nil" };
                                                            {
                                                              const $t8667_i5202 = { $: "$Clo_$lam0_Array_to_list$0_Array_to_list_PVec_Int", _0: $lam0_Array_to_list$apply$0_Array_to_list_PVec_Int };
                                                              {
                                                                const rev_i5203 = Array$fold_left$PVec_Int$List_Int$Fn_List_Int_Int_List_Int(board2, $t8665_i5201, $t8667_i5202);
                                                                {
                                                                  const go_i13459 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                                                                  {
                                                                    const $t8250_i13460 = { $: "Nil" };
                                                                    $t46872 = go$apply$0_Array_lst_rev_List_Int(go_i13459, rev_i5203, $t8250_i13460);
                                                                  }
                                                                }
                                                              }
                                                            }
                                                          }
                                                          $t46873 = int_list_to_string($t46872);
                                                        }
                                                        $eff = Js$Dom$set_attr(el, "data-board", $t46873);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        let $t46874;
                                                        {
                                                          const $rc_2502 = piece_to_string(piece2);
                                                          $t46874 = $rc_2502;
                                                        }
                                                        $eff = Js$Dom$set_attr(el, "data-piece", $t46874);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t46875 = String(rot2);
                                                        $eff = Js$Dom$set_attr(el, "data-rot", $t46875);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t46876 = String(x2);
                                                        $eff = Js$Dom$set_attr(el, "data-x", $t46876);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t46877 = String(y2);
                                                        $eff = Js$Dom$set_attr(el, "data-y", $t46877);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        let $t46878;
                                                        {
                                                          const $rc_2501 = piece_to_string(next2);
                                                          $t46878 = $rc_2501;
                                                        }
                                                        $eff = Js$Dom$set_attr(el, "data-next", $t46878);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t46879 = String(score2);
                                                        $eff = Js$Dom$set_attr(el, "data-score", $t46879);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t46880 = String(lines2);
                                                        $eff = Js$Dom$set_attr(el, "data-lines", $t46880);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t46881 = String(rng2);
                                                        $eff = Js$Dom$set_attr(el, "data-rng", $t46881);
                                                      }
                                                    }
                                                    {
                                                      let over2_s;
                                                      if (over2 === true) {
                                                        over2_s = "true";
                                                      } else if (over2 === false) {
                                                        over2_s = "false";
                                                      } else {
                                                        throw march_panic_error("panic: ", "non-exhaustive pattern match");
                                                      }
                                                      {
                                                        let $eff;
                                                        $eff = Js$Dom$set_attr(el, "data-over", over2_s);
                                                      }
                                                      {
                                                        let $t46883;
                                                        {
                                                          const $t46882 = ((seq + 1) < 4611686018427387904 && (seq + 1) >= -4611686018427387904 ? (seq + 1) : march_int_ovf((seq + 1), 0));
                                                          $t46883 = String($t46882);
                                                        }
                                                        return Js$Dom$set_attr(el, "data-seq", $t46883);
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      } else {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
  }
}
const with_state$clo = { _0: ($_, f) => with_state(f) };

function lock_and_advance(board, piece, rot, x, y, next, score, lines, rng) {
  {
    const $t46930 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t46930, rot);
      {
        let locked;
        {
          let $t46931;
          switch (piece.$) {
            case "I": {
              $t46931 = 1;
              break;
            }
            case "O": {
              $t46931 = 2;
              break;
            }
            case "T": {
              $t46931 = 3;
              break;
            }
            case "S": {
              $t46931 = 4;
              break;
            }
            case "Z": {
              $t46931 = 5;
              break;
            }
            case "J": {
              $t46931 = 6;
              break;
            }
            case "L": {
              $t46931 = 7;
              break;
            }
            default: {
              throw march_panic_error("panic: ", "non-exhaustive pattern match");
              break;
            }
          }
          {
            const $t46740_i5226 = { $: "$Clo_$lam0_TetrisLogic_lock_piece$0_TetrisLogic_lock_piece", _0: $lam0_TetrisLogic_lock_piece$apply$0_TetrisLogic_lock_piece, _1: $t46931, _2: x, _3: y };
            locked = List$fold_left$List_T_Int_Int$PVec_Int$Fn_PVec_Int_T_Int_Int_PVec_Int(cells, board, $t46740_i5226);
          }
        }
        {
          const $t46932 = TetrisLogic$clear_lines(locked);
          const $f46966 = $t46932._0;
          const $f46967 = $t46932._1;
          {
            const n = $f46967;
            {
              const cleared_board = $f46966;
              {
                let new_score;
                {
                  let $t46933;
                  if (n === 1) {
                    $t46933 = 100;
                  } else if (n === 2) {
                    $t46933 = 300;
                  } else if (n === 3) {
                    $t46933 = 500;
                  } else if (n === 4) {
                    $t46933 = 800;
                  } else {
                    $t46933 = 0;
                  }
                  new_score = ((score + $t46933) < 4611686018427387904 && (score + $t46933) >= -4611686018427387904 ? (score + $t46933) : march_int_ovf((score + $t46933), 0));
                }
                {
                  const new_lines = ((lines + n) < 4611686018427387904 && (lines + n) >= -4611686018427387904 ? (lines + n) : march_int_ovf((lines + n), 0));
                  {
                    let $t46934;
                    $t46934 = spawn_piece(next, cleared_board, rng);
                    const $f46935 = $t46934._0;
                    const $f46936 = $t46934._1;
                    const $f46937 = $t46934._2;
                    const $f46938 = $t46934._3;
                    const $f46939 = $t46934._4;
                    const $f46940 = $t46934._5;
                    const $f46941 = $t46934._6;
                    {
                      const over = $f46941;
                      {
                        const rng2 = $f46940;
                        {
                          const next2 = $f46939;
                          {
                            const y2 = $f46938;
                            {
                              const x2 = $f46937;
                              {
                                const rot2 = $f46936;
                                {
                                  const piece2 = $f46935;
                                  return { _0: cleared_board, _1: piece2, _2: rot2, _3: x2, _4: y2, _5: next2, _6: new_score, _7: new_lines, _8: rng2, _9: over };
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
const lock_and_advance$clo = { _0: ($_, board, piece, rot, x, y, next, score, lines, rng) => lock_and_advance(board, piece, rot, x, y, next, score, lines, rng) };

function is_paused() {
  {
    let $t46973;
    {
      const $t46972 = state_el();
      $t46973 = get_str_attr($t46972, "data-paused", "false");
    }
    {
      const $rc_2510 = ($t46973 === "true");
      return $rc_2510;
    }
  }
}
const is_paused$clo = { _0: ($_) => is_paused() };

function set_paused(el, paused) {
  {
    let paused_s;
    if (paused === true) {
      paused_s = "true";
    } else if (paused === false) {
      paused_s = "false";
    } else {
      throw march_panic_error("panic: ", "non-exhaustive pattern match");
    }
    {
      let status_s;
      if (paused === true) {
        status_s = "Paused — press P to resume";
      } else if (paused === false) {
        status_s = "";
      } else {
        throw march_panic_error("panic: ", "non-exhaustive pattern match");
      }
      Js$Dom$set_attr(el, "data-paused", paused_s);
      return set_text_if_found("pause-status", status_s);
    }
  }
}
const set_paused$clo = { _0: ($_, el, paused) => set_paused(el, paused) };

function toggle_pause() {
  {
    const el = state_el();
    {
      let over;
      {
        let $t46974;
        $t46974 = get_str_attr(el, "data-over", "false");
        {
          const $rc_2511 = ($t46974 === "true");
          over = $rc_2511;
        }
      }
      if (over === true) {
        return {  };
      } else if (over === false) {
        {
          let $t46976;
          {
            const $t46975 = is_paused();
            $t46976 = (!$t46975);
          }
          return set_paused(el, $t46976);
        }
      } else {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
  }
}
const toggle_pause$clo = { _0: ($_) => toggle_pause() };

function fall_from($tco_a0, $tco_a1, $tco_a2, $tco_a3) {
  __tco: for (;;) {
    const board = $tco_a0;
    const cells = $tco_a1;
    const x = $tco_a2;
    const cur_y = $tco_a3;
    {
      let $t47003;
      {
        const $t47002 = ((cur_y + 1) < 4611686018427387904 && (cur_y + 1) >= -4611686018427387904 ? (cur_y + 1) : march_int_ovf((cur_y + 1), 0));
        {
          const $t46730_i5234 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: x, _3: $t47002 };
          $t47003 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t46730_i5234);
        }
      }
      if ($t47003 === true) {
        return cur_y;
      } else if ($t47003 === false) {
        {
          const $t47004 = ((cur_y + 1) < 4611686018427387904 && (cur_y + 1) >= -4611686018427387904 ? (cur_y + 1) : march_int_ovf((cur_y + 1), 0));
          {
            $tco_a0 = board;
            $tco_a1 = cells;
            $tco_a2 = x;
            $tco_a3 = $t47004;
            continue __tco;
          }
        }
      } else {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
    return undefined;
  }
}
const fall_from$clo = { _0: ($_, board, cells, x, cur_y) => fall_from(board, cells, x, cur_y) };

function restart() {
  {
    const el = state_el();
    {
      let board;
      {
        let $t46704_i5253;
        {
          const go_i13490 = { $: "$Clo_go$0_List_repeat_Int_Int", _0: go$apply$0_List_repeat_Int_Int, _1: 0 };
          {
            const $t797_i13491 = { $: "Nil" };
            $t46704_i5253 = go$apply$0_List_repeat_Int_Int(go_i13490, 200, $t797_i13491);
          }
        }
        board = Array$from_list$List_Int($t46704_i5253);
      }
      {
        let rng0;
        {
          let raw_i12320;
          {
            let $t46774_i12319;
            {
              let $t46773_i12318;
              {
                let $t46772_i12317;
                {
                  const $t46771_i12316 = {  };
                  $t46772_i12317 = march_unix_time();
                }
                $t46773_i12318 = ($t46772_i12317 * 1000000.);
              }
              $t46774_i12319 = Math.trunc($t46773_i12318);
            }
            raw_i12320 = march_int_mod($t46774_i12319, 2147483646);
          }
          {
            const $t46775_i12321 = (raw_i12320 <= 0);
            if ($t46775_i12321 === true) {
              rng0 = ((raw_i12320 + 2147483646) < 4611686018427387904 && (raw_i12320 + 2147483646) >= -4611686018427387904 ? (raw_i12320 + 2147483646) : march_int_ovf((raw_i12320 + 2147483646), 0));
            } else if ($t46775_i12321 === false) {
              rng0 = raw_i12320;
            } else {
              throw march_panic_error("panic: ", "non-exhaustive pattern match");
            }
          }
        }
        {
          const $t47008 = next_piece(rng0);
          const $f47054 = $t47008._0;
          const $f47055 = $t47008._1;
          {
            const rng1 = $f47055;
            {
              const first = $f47054;
              {
                let $t47009;
                $t47009 = spawn_piece(first, board, rng1);
                const $f47023 = $t47009._0;
                const $f47024 = $t47009._1;
                const $f47025 = $t47009._2;
                const $f47026 = $t47009._3;
                const $f47027 = $t47009._4;
                const $f47028 = $t47009._5;
                const $f47029 = $t47009._6;
                {
                  const rng2 = $f47028;
                  {
                    const next = $f47027;
                    {
                      const y = $f47026;
                      {
                        const x = $f47025;
                        {
                          const rot = $f47024;
                          {
                            const piece = $f47023;
                            {
                              let $eff;
                              {
                                let $t46822_i5248;
                                {
                                  const go_i13485 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                                  {
                                    const $t802_i13487 = { $: "Nil" };
                                    $t46822_i5248 = go$apply$0_List_range(go_i13485, 19, $t802_i13487);
                                  }
                                }
                                {
                                  const $t46834_i5249 = { $: "$Clo_$lam0_render_board$0_render_board", _0: $lam0_render_board$apply$0_render_board, _1: board };
                                  {
                                    const f_i13481 = $t46834_i5249;
                                    {
                                      const go_i13482 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i13481 };
                                      $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i13482, $t46822_i5248);
                                    }
                                  }
                                }
                              }
                            }
                            {
                              let $eff;
                              {
                                const base_cells_i5243 = TetrisLogic$piece_cells(piece);
                                {
                                  const rotated_i5244 = rotate_n(base_cells_i5243, rot);
                                  {
                                    const $t46856_i5245 = { $: "$Clo_$lam0_render_falling$0_render_falling", _0: $lam0_render_falling$apply$0_render_falling, _1: x, _2: y, _3: piece };
                                    {
                                      const f_i13478 = $t46856_i5245;
                                      {
                                        const go_i13479 = { $: "$Clo_go$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_", _0: go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_, _1: f_i13478 };
                                        $eff = go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_(go_i13479, rotated_i5244);
                                      }
                                    }
                                  }
                                }
                              }
                            }
                            set_text_if_found("score", "Score: 0");
                            set_text_if_found("level", "Level: 0");
                            {
                              let $eff;
                              {
                                let $t47011;
                                {
                                  const $t47010 = piece_to_string(next);
                                  {
                                    const $rc_2514 = ("Next: " + $t47010);
                                    $t47011 = $rc_2514;
                                  }
                                }
                                $eff = set_text_if_found("next", $t47011);
                              }
                            }
                            set_text_if_found("game-over", "");
                            {
                              let $eff;
                              $eff = set_paused(el, false);
                            }
                            {
                              let $eff;
                              {
                                let $t47013;
                                {
                                  let $t47012;
                                  {
                                    const $t8665_i5236 = { $: "Nil" };
                                    {
                                      const $t8667_i5237 = { $: "$Clo_$lam0_Array_to_list$0_Array_to_list_PVec_Int", _0: $lam0_Array_to_list$apply$0_Array_to_list_PVec_Int };
                                      {
                                        const rev_i5238 = Array$fold_left$PVec_Int$List_Int$Fn_List_Int_Int_List_Int(board, $t8665_i5236, $t8667_i5237);
                                        {
                                          const go_i13475 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                                          {
                                            const $t8250_i13476 = { $: "Nil" };
                                            $t47012 = go$apply$0_Array_lst_rev_List_Int(go_i13475, rev_i5238, $t8250_i13476);
                                          }
                                        }
                                      }
                                    }
                                  }
                                  $t47013 = int_list_to_string($t47012);
                                }
                                $eff = Js$Dom$set_attr(el, "data-board", $t47013);
                              }
                            }
                            {
                              let $eff;
                              {
                                let $t47014;
                                {
                                  const $rc_2513 = piece_to_string(piece);
                                  $t47014 = $rc_2513;
                                }
                                $eff = Js$Dom$set_attr(el, "data-piece", $t47014);
                              }
                            }
                            {
                              let $eff;
                              {
                                const $t47015 = String(rot);
                                $eff = Js$Dom$set_attr(el, "data-rot", $t47015);
                              }
                            }
                            {
                              let $eff;
                              {
                                const $t47016 = String(x);
                                $eff = Js$Dom$set_attr(el, "data-x", $t47016);
                              }
                            }
                            {
                              let $eff;
                              {
                                const $t47017 = String(y);
                                $eff = Js$Dom$set_attr(el, "data-y", $t47017);
                              }
                            }
                            {
                              let $eff;
                              {
                                let $t47018;
                                {
                                  const $rc_2512 = piece_to_string(next);
                                  $t47018 = $rc_2512;
                                }
                                $eff = Js$Dom$set_attr(el, "data-next", $t47018);
                              }
                            }
                            {
                              let $eff;
                              $eff = Js$Dom$set_attr(el, "data-score", "0");
                            }
                            {
                              let $eff;
                              $eff = Js$Dom$set_attr(el, "data-lines", "0");
                            }
                            {
                              let $eff;
                              {
                                const $t47019 = String(rng2);
                                $eff = Js$Dom$set_attr(el, "data-rng", $t47019);
                              }
                            }
                            {
                              let $eff;
                              $eff = Js$Dom$set_attr(el, "data-over", "false");
                            }
                            {
                              let $t47022;
                              {
                                let $t47021;
                                {
                                  let $t47020;
                                  $t47020 = get_int_attr(el, "data-seq", 0);
                                  $t47021 = (($t47020 + 1) < 4611686018427387904 && ($t47020 + 1) >= -4611686018427387904 ? ($t47020 + 1) : march_int_ovf(($t47020 + 1), 0));
                                }
                                $t47022 = String($t47021);
                              }
                              return Js$Dom$set_attr(el, "data-seq", $t47022);
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
const restart$clo = { _0: ($_) => restart() };

function restore_from_request() {
  {
    const $t47060 = Js$Dom$find("restore-request");
    switch ($t47060.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f47076 = $t47060._0;
        {
          const req = $f47076;
          {
            const el = state_el();
            {
              let board_s;
              board_s = get_str_attr(req, "data-board", "");
              {
                let piece_s;
                piece_s = get_str_attr(req, "data-piece", "I");
                {
                  let rot;
                  rot = get_int_attr(req, "data-rot", 0);
                  {
                    let x;
                    x = get_int_attr(req, "data-x", 3);
                    {
                      let y;
                      y = get_int_attr(req, "data-y", 0);
                      {
                        let next_s;
                        next_s = get_str_attr(req, "data-next", "O");
                        {
                          let score;
                          score = get_int_attr(req, "data-score", 0);
                          {
                            let lines;
                            lines = get_int_attr(req, "data-lines", 0);
                            {
                              let rng_s;
                              rng_s = get_str_attr(req, "data-rng", "1");
                              {
                                let over;
                                {
                                  let $t47061;
                                  $t47061 = get_str_attr(req, "data-over", "false");
                                  {
                                    const $rc_2520 = ($t47061 === "true");
                                    over = $rc_2520;
                                  }
                                }
                                {
                                  let paused;
                                  {
                                    const $t47062 = get_str_attr(req, "data-paused", "false");
                                    {
                                      const $rc_2519 = ($t47062 === "true");
                                      paused = $rc_2519;
                                    }
                                  }
                                  {
                                    let board;
                                    {
                                      let $t47063;
                                      {
                                        const $t46766_i5268 = march_string_split(board_s, ",");
                                        {
                                          const $t46769_i5269 = { $: "$Clo_$lam0_string_to_int_list$0_string_to_int_list", _0: $lam0_string_to_int_list$apply$0_string_to_int_list };
                                          $t47063 = List$map$List_String$Fn_String_Int($t46766_i5268, $t46769_i5269);
                                        }
                                      }
                                      board = Array$from_list$List_Int($t47063);
                                    }
                                    {
                                      let piece;
                                      if (piece_s === "I") {
                                        piece = { $: "I" };
                                      } else if (piece_s === "O") {
                                        piece = { $: "O" };
                                      } else if (piece_s === "T") {
                                        piece = { $: "T" };
                                      } else if (piece_s === "S") {
                                        piece = { $: "S" };
                                      } else if (piece_s === "Z") {
                                        piece = { $: "Z" };
                                      } else if (piece_s === "J") {
                                        piece = { $: "J" };
                                      } else {
                                        piece = { $: "L" };
                                      }
                                      {
                                        let next;
                                        if (next_s === "I") {
                                          next = { $: "I" };
                                        } else if (next_s === "O") {
                                          next = { $: "O" };
                                        } else if (next_s === "T") {
                                          next = { $: "T" };
                                        } else if (next_s === "S") {
                                          next = { $: "S" };
                                        } else if (next_s === "Z") {
                                          next = { $: "Z" };
                                        } else if (next_s === "J") {
                                          next = { $: "J" };
                                        } else {
                                          next = { $: "L" };
                                        }
                                        {
                                          let $eff;
                                          {
                                            let $t46822_i5263;
                                            {
                                              const go_i13500 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                                              {
                                                const $t802_i13502 = { $: "Nil" };
                                                $t46822_i5263 = go$apply$0_List_range(go_i13500, 19, $t802_i13502);
                                              }
                                            }
                                            {
                                              const $t46834_i5264 = { $: "$Clo_$lam0_render_board$0_render_board", _0: $lam0_render_board$apply$0_render_board, _1: board };
                                              {
                                                const f_i13496 = $t46834_i5264;
                                                {
                                                  const go_i13497 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i13496 };
                                                  $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i13497, $t46822_i5263);
                                                }
                                              }
                                            }
                                          }
                                        }
                                        {
                                          let $eff;
                                          if (over === false) {
                                            {
                                              const base_cells_i5258 = TetrisLogic$piece_cells(piece);
                                              {
                                                const rotated_i5259 = rotate_n(base_cells_i5258, rot);
                                                {
                                                  const $t46856_i5260 = { $: "$Clo_$lam0_render_falling$0_render_falling", _0: $lam0_render_falling$apply$0_render_falling, _1: x, _2: y, _3: piece };
                                                  {
                                                    const f_i13493 = $t46856_i5260;
                                                    {
                                                      const go_i13494 = { $: "$Clo_go$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_", _0: go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_, _1: f_i13493 };
                                                      $eff = go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_(go_i13494, rotated_i5259);
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          } else if (over === true) {
                                            $eff = {  };
                                          } else {
                                            throw march_panic_error("panic: ", "non-exhaustive pattern match");
                                          }
                                        }
                                        {
                                          let $eff;
                                          {
                                            let $t47065;
                                            {
                                              const $t47064 = String(score);
                                              {
                                                const $rc_2518 = ("Score: " + $t47064);
                                                $t47065 = $rc_2518;
                                              }
                                            }
                                            $eff = set_text_if_found("score", $t47065);
                                          }
                                        }
                                        {
                                          let $eff;
                                          {
                                            let $t47068;
                                            {
                                              let $t47067;
                                              {
                                                const $t47066 = TetrisLogic$level_for_lines(lines);
                                                $t47067 = String($t47066);
                                              }
                                              {
                                                const $rc_2517 = ("Level: " + $t47067);
                                                $t47068 = $rc_2517;
                                              }
                                            }
                                            $eff = set_text_if_found("level", $t47068);
                                          }
                                        }
                                        {
                                          let $eff;
                                          {
                                            let $t47070;
                                            {
                                              let $t47069;
                                              {
                                                const $rc_2516 = piece_to_string(next);
                                                $t47069 = $rc_2516;
                                              }
                                              {
                                                const $rc_2515 = ("Next: " + $t47069);
                                                $t47070 = $rc_2515;
                                              }
                                            }
                                            $eff = set_text_if_found("next", $t47070);
                                          }
                                        }
                                        {
                                          let game_over_text;
                                          if (over === true) {
                                            game_over_text = "Game Over — press R to restart";
                                          } else if (over === false) {
                                            game_over_text = "";
                                          } else {
                                            throw march_panic_error("panic: ", "non-exhaustive pattern match");
                                          }
                                          set_text_if_found("game-over", game_over_text);
                                          {
                                            let $eff;
                                            $eff = set_paused(el, paused);
                                          }
                                          {
                                            let $eff;
                                            $eff = Js$Dom$set_attr(el, "data-board", board_s);
                                          }
                                          {
                                            let $eff;
                                            $eff = Js$Dom$set_attr(el, "data-piece", piece_s);
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t47071 = String(rot);
                                              $eff = Js$Dom$set_attr(el, "data-rot", $t47071);
                                            }
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t47072 = String(x);
                                              $eff = Js$Dom$set_attr(el, "data-x", $t47072);
                                            }
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t47073 = String(y);
                                              $eff = Js$Dom$set_attr(el, "data-y", $t47073);
                                            }
                                          }
                                          {
                                            let $eff;
                                            $eff = Js$Dom$set_attr(el, "data-next", next_s);
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t47074 = String(score);
                                              $eff = Js$Dom$set_attr(el, "data-score", $t47074);
                                            }
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t47075 = String(lines);
                                              $eff = Js$Dom$set_attr(el, "data-lines", $t47075);
                                            }
                                          }
                                          {
                                            let $eff;
                                            $eff = Js$Dom$set_attr(el, "data-rng", rng_s);
                                          }
                                          {
                                            let over_s;
                                            if (over === true) {
                                              over_s = "true";
                                            } else if (over === false) {
                                              over_s = "false";
                                            } else {
                                              throw march_panic_error("panic: ", "non-exhaustive pattern match");
                                            }
                                            return Js$Dom$set_attr(el, "data-over", over_s);
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
  }
}
const restore_from_request$clo = { _0: ($_) => restore_from_request() };

function handle_key(ev) {
  {
    let key;
    {
      const ev_i12324 = ev;
      {
        const $rc_2451_i12325 = dom_event_key$clo._0(dom_event_key$clo, ev);
        key = $rc_2451_i12325;
      }
    }
    {
      let $eff;
      {
        let $t47088;
        if (key === "ArrowLeft") {
          $t47088 = true;
        } else if (key === "ArrowRight") {
          $t47088 = true;
        } else if (key === "ArrowDown") {
          $t47088 = true;
        } else if (key === "ArrowUp") {
          $t47088 = true;
        } else if (key === " ") {
          $t47088 = true;
        } else {
          $t47088 = false;
        }
        if ($t47088 === true) {
          {
            const ev_i12322 = ev;
            {
              const $rc_2452_i12323 = dom_prevent_default$clo._0(dom_prevent_default$clo, ev);
              $eff = $rc_2452_i12323;
            }
          }
        } else if ($t47088 === false) {
          $eff = {  };
        } else {
          throw march_panic_error("panic: ", "non-exhaustive pattern match");
        }
      }
    }
    if (key === "r") {
      return restart();
    } else if (key === "R") {
      return restart();
    } else if (key === "p") {
      return toggle_pause();
    } else if (key === "P") {
      return toggle_pause();
    } else {
      {
        const k = key;
        {
          const $t47089 = is_paused();
          if ($t47089 === true) {
            return {  };
          } else if ($t47089 === false) {
            if (k === "ArrowLeft") {
              {
                const $t47090 = march_int_ovf(-(1), 3);
                {
                  const $t46996_i5280 = { $: "$Clo_$lam0_try_move$0_try_move", _0: $lam0_try_move$apply$0_try_move, _1: $t47090, _2: 0 };
                  return with_state($t46996_i5280);
                }
              }
            } else if (k === "ArrowRight") {
              {
                const $t46996_i5283 = { $: "$Clo_$lam0_try_move$0_try_move", _0: $lam0_try_move$apply$0_try_move, _1: 1, _2: 0 };
                return with_state($t46996_i5283);
              }
            } else if (k === "ArrowDown") {
              {
                const $t46996_i5286 = { $: "$Clo_$lam0_try_move$0_try_move", _0: $lam0_try_move$apply$0_try_move, _1: 0, _2: 1 };
                return with_state($t46996_i5286);
              }
            } else if (k === "ArrowUp") {
              {
                const $t47001_i5287 = { $: "$Clo_$lam0_try_rotate$0_try_rotate", _0: $lam0_try_rotate$apply$0_try_rotate };
                return with_state($t47001_i5287);
              }
            } else if (k === " ") {
              {
                const $t47007_i5288 = { $: "$Clo_$lam0_hard_drop$0_hard_drop", _0: $lam0_hard_drop$apply$0_hard_drop };
                return with_state($t47007_i5288);
              }
            } else {
              return {  };
            }
          } else {
            return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          }
        }
      }
    }
  }
}
const handle_key$clo = { _0: ($_, ev) => handle_key(ev) };

function main(_cap_clock, _cap_foreign) {
  {
    const $t47109 = Js$Dom$find("board");
    switch ($t47109.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f47117 = $t47109._0;
        {
          const board_el = $f47117;
          {
            let $eff;
            {
              let $t47078_i5297;
              {
                const go_i13514 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                {
                  const $t802_i13516 = { $: "Nil" };
                  $t47078_i5297 = go$apply$0_List_range(go_i13514, 19, $t802_i13516);
                }
              }
              {
                const $t47087_i5298 = { $: "$Clo_$lam0_build_board_dom$0_build_board_dom", _0: $lam0_build_board_dom$apply$0_build_board_dom, _1: board_el };
                {
                  const f_i13510 = $t47087_i5298;
                  {
                    const go_i13511 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i13510 };
                    $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i13511, $t47078_i5297);
                  }
                }
              }
            }
          }
          restart();
          {
            let $eff;
            {
              const $t47110 = dom_body();
              {
                const $t47112 = { $: "$Clo_$lam0_main$0_main", _0: $lam0_main$apply$0_main };
                $eff = Js$Dom$listen($t47110, "keydown", $t47112);
              }
            }
          }
          {
            let $eff;
            {
              let level_i5292;
              {
                let $t46985_i5291;
                {
                  const $t46984_i5290 = state_el();
                  $t46985_i5291 = get_int_attr($t46984_i5290, "data-lines", 0);
                }
                level_i5292 = TetrisLogic$level_for_lines($t46985_i5291);
              }
              {
                let $t46986_i5293;
                {
                  let $t46698_i13507;
                  {
                    const $t46697_i13506 = ((level_i5292 * 40) < 4611686018427387904 && (level_i5292 * 40) >= -4611686018427387904 ? (level_i5292 * 40) : march_int_ovf((level_i5292 * 40), 2));
                    $t46698_i13507 = ((500 - $t46697_i13506) < 4611686018427387904 && (500 - $t46697_i13506) >= -4611686018427387904 ? (500 - $t46697_i13506) : march_int_ovf((500 - $t46697_i13506), 1));
                  }
                  {
                    const $t2349_i5151_i13508 = ($t46698_i13507 > 100);
                    if ($t2349_i5151_i13508 === true) {
                      $t46986_i5293 = $t46698_i13507;
                    } else {
                      $t46986_i5293 = 100;
                    }
                  }
                }
                {
                  const $t46988_i5294 = { $: "$Clo_$lam0_schedule_tick$0_schedule_tick", _0: $lam0_schedule_tick$apply$0_schedule_tick };
                  $eff = Js$Dom$set_timeout($t46986_i5293, $t46988_i5294);
                }
              }
            }
          }
          {
            const $t47113 = Js$Dom$find("restore-trigger");
            switch ($t47113.$) {
              case "None": {
                return {  };
                break;
              }
              case "Some": {
                const $f47116 = $t47113._0;
                {
                  const trigger = $f47116;
                  {
                    const $t47115 = { $: "$Clo_$lam1_main$1_main", _0: $lam1_main$apply$1_main };
                    return Js$Dom$listen(trigger, "click", $t47115);
                  }
                }
                break;
              }
              default: {
                return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
              }
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
  }
}
const main$clo = { _0: ($_, _cap_clock, _cap_foreign) => main(_cap_clock, _cap_foreign) };

function panic(msg) {
  return (() => { throw march_panic_error("panic: ", msg); })();
}
const panic$clo = { _0: ($_, msg) => panic(msg) };

function List$all$List_Int$Fn_Int_Bool($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const xs = $tco_a0;
    const pred = $tco_a1;
    switch (xs.$) {
      case "Nil": {
        return true;
        break;
      }
      case "Cons": {
        const $f1037 = xs._0;
        const $f1038 = xs._1;
        {
          const t = $f1038;
          {
            let h;
            h = $f1037;
            {
              let $t1036;
              $t1036 = pred._0(pred, h);
              if ($t1036 === true) {
                {
                  $tco_a0 = t;
                  $tco_a1 = pred;
                  continue __tco;
                }
              } else {
                return false;
              }
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
    return undefined;
  }
}
const List$all$List_Int$Fn_Int_Bool$clo = { _0: ($_, xs, pred) => List$all$List_Int$Fn_Int_Bool(xs, pred) };

function List$filter$List_Int$Fn_Int_Bool($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const xs = $tco_a0;
    const pred = $tco_a1;
    switch (xs.$) {
      case "Nil": {
        return { $: "Nil" };
        break;
      }
      case "Cons": {
        const $f911 = xs._0;
        const $f912 = xs._1;
        {
          const t = $f912;
          {
            const h = $f911;
            {
              let $t909;
              $t909 = pred._0(pred, h);
              if ($t909 === true) {
                {
                  const $trmc24 = { $: "Cons", _0: h, _1: null };
                  List$filter$dps$List_Int$Fn_Int_Bool$List_Int(t, pred, $trmc24);
                  return $trmc24;
                }
              } else {
                {
                  $tco_a0 = t;
                  $tco_a1 = pred;
                  continue __tco;
                }
              }
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
    return undefined;
  }
}
const List$filter$List_Int$Fn_Int_Bool$clo = { _0: ($_, xs, pred) => List$filter$List_Int$Fn_Int_Bool(xs, pred) };

function Option$unwrap_or$Option_Int$Int(opt, _default) {
  switch (opt.$) {
    case "Some": {
      const $f740 = opt._0;
      {
        let x;
        x = $f740;
        return x;
      }
      break;
    }
    case "None": {
      return _default;
      break;
    }
    default: {
      return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
    }
  }
}
const Option$unwrap_or$Option_Int$Int$clo = { _0: ($_, opt, _default) => Option$unwrap_or$Option_Int$Int(opt, _default) };

function Array$from_list$List_Int(xs) {
  {
    let n;
    {
      const go_i5619 = { $: "$Clo_go$0_Array_lst_len_List_Int", _0: go$apply$0_Array_lst_len_List_Int };
      n = go$apply$0_Array_lst_len_List_Int(go_i5619, xs, 0);
    }
    {
      const $t8772 = (n === 0);
      if ($t8772 === true) {
        {
          const $t8456_i5616 = { $: "TrieEmpty" };
          {
            const $t8457_i5617 = { $: "Nil" };
            return { $: "PVec", _0: 0, _1: 0, _2: $t8456_i5616, _3: $t8457_i5617 };
          }
        }
      } else {
        {
          let tail_len;
          {
            let $t8775;
            {
              let $t8774;
              {
                const $t8773 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                $t8774 = (32 === 0 ? march_div_zero() : ($t8773 - $t8773 % 32) / 32);
              }
              $t8775 = ((32 * $t8774) < 4611686018427387904 && (32 * $t8774) >= -4611686018427387904 ? (32 * $t8774) : march_int_ovf((32 * $t8774), 2));
            }
            tail_len = ((n - $t8775) < 4611686018427387904 && (n - $t8775) >= -4611686018427387904 ? (n - $t8775) : march_int_ovf((n - $t8775), 1));
          }
          {
            let $p8797;
            {
              const $t8776 = ((n - tail_len) < 4611686018427387904 && (n - tail_len) >= -4611686018427387904 ? (n - tail_len) : march_int_ovf((n - tail_len), 1));
              {
                const go_i5614 = { $: "$Clo_go$0_Array_lst_split_List_Int_Int", _0: go$apply$0_Array_lst_split_List_Int_Int };
                {
                  const $t8684_i5615 = { $: "Nil" };
                  $p8797 = go$apply$0_Array_lst_split_List_Int_Int(go_i5614, xs, $t8776, $t8684_i5615);
                }
              }
            }
            {
              const front = $p8797._0;
              {
                const tail = $p8797._1;
                {
                  const $t8777 = (n === tail_len);
                  if ($t8777 === true) {
                    {
                      const $t8778 = { $: "TrieEmpty" };
                      {
                        const $rc_2630 = { $: "PVec", _0: n, _1: 0, _2: $t8778, _3: tail };
                        return $rc_2630;
                      }
                    }
                  } else {
                    {
                      const up = { $: "$Clo_up$0_Array_from_list_List_Int", _0: up$apply$0_Array_from_list_List_Int };
                      {
                        let $p8796;
                        {
                          const $t8794 = { $: "$Clo_$lam0_Array_from_list$2_Array_from_list_List_Int", _0: $lam0_Array_from_list$apply$2_Array_from_list_List_Int };
                          {
                            let $t8795;
                            {
                              const wrap_i5608 = $t8794;
                              {
                                const chunk_i5609 = { $: "$Clo_chunk$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int", _0: chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int, _1: wrap_i5608 };
                                {
                                  const $t8704_i5610 = { $: "Nil" };
                                  {
                                    const $t8705_i5611 = { $: "Nil" };
                                    $t8795 = chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int(chunk_i5609, front, 0, $t8704_i5610, $t8705_i5611);
                                  }
                                }
                              }
                            }
                            $p8796 = up$apply$0_Array_from_list_List_Int(up, $t8795, 0);
                          }
                        }
                        {
                          const root = $p8796._0;
                          {
                            const shift = $p8796._1;
                            {
                              const $rc_2626 = { $: "PVec", _0: n, _1: shift, _2: root, _3: tail };
                              return $rc_2626;
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
const Array$from_list$List_Int$clo = { _0: ($_, xs) => Array$from_list$List_Int(xs) };

function List$any$List_T_Int_Int$Fn_T_Int_Int_Bool($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const xs = $tco_a0;
    const pred = $tco_a1;
    switch (xs.$) {
      case "Nil": {
        return false;
        break;
      }
      case "Cons": {
        const $f1030 = xs._0;
        const $f1031 = xs._1;
        {
          const t = $f1031;
          {
            const h = $f1030;
            {
              let $t1029;
              $t1029 = pred._0(pred, h);
              if ($t1029 === true) {
                return true;
              } else {
                {
                  $tco_a0 = t;
                  $tco_a1 = pred;
                  continue __tco;
                }
              }
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
    return undefined;
  }
}
const List$any$List_T_Int_Int$Fn_T_Int_Int_Bool$clo = { _0: ($_, xs, pred) => List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(xs, pred) };

function Array$get$PVec_Int$Int(v, idx) {
  switch (v.$) {
    case "PVec": {
      const $f8511 = v._0;
      const $f8512 = v._1;
      const $f8513 = v._2;
      const $f8514 = v._3;
      {
        const tail = $f8514;
        {
          const root = $f8513;
          {
            const shift = $f8512;
            {
              const n = $f8511;
              {
                let $t8508;
                {
                  const $t8506 = (idx < 0);
                  {
                    const $t8507 = (idx >= n);
                    $t8508 = ($t8506 || $t8507);
                  }
                }
                if ($t8508 === true) {
                  march_panic_site("stdlib/array.march", 432, 32, 70);
                  return (() => { throw march_panic_error("panic: ", "Array.get: index out of range"); })();
                } else {
                  {
                    let tail_len;
                    {
                      const go_i5621 = { $: "$Clo_go$0_Array_lst_len_List_Int", _0: go$apply$0_Array_lst_len_List_Int };
                      tail_len = go$apply$0_Array_lst_len_List_Int(go_i5621, tail, 0);
                    }
                    {
                      const tail_offset = ((n - tail_len) < 4611686018427387904 && (n - tail_len) >= -4611686018427387904 ? (n - tail_len) : march_int_ovf((n - tail_len), 1));
                      {
                        const $t8509 = (idx >= tail_offset);
                        if ($t8509 === true) {
                          {
                            const $t8510 = ((idx - tail_offset) < 4611686018427387904 && (idx - tail_offset) >= -4611686018427387904 ? (idx - tail_offset) : march_int_ovf((idx - tail_offset), 1));
                            {
                              const $rc_2631 = Array$lst_nth$List_Int$Int(tail, $t8510);
                              return $rc_2631;
                            }
                          }
                        } else {
                          return Array$trie_get$TrieNode_Int$Int$Int(root, idx, shift);
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
      break;
    }
    default: {
      return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
    }
  }
}
const Array$get$PVec_Int$Int$clo = { _0: ($_, v, idx) => Array$get$PVec_Int$Int(v, idx) };

function List$fold_left$List_T_Int_Int$PVec_Int$Fn_PVec_Int_T_Int_Int_PVec_Int($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const xs = $tco_a0;
    const acc = $tco_a1;
    const f = $tco_a2;
    switch (xs.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f967 = xs._0;
        const $f968 = xs._1;
        {
          const t = $f968;
          {
            const h = $f967;
            {
              let $t966;
              $t966 = f._0(f, acc, h);
              {
                $tco_a0 = t;
                $tco_a1 = $t966;
                $tco_a2 = f;
                continue __tco;
              }
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
    return undefined;
  }
}
const List$fold_left$List_T_Int_Int$PVec_Int$Fn_PVec_Int_T_Int_Int_PVec_Int$clo = { _0: ($_, xs, acc, f) => List$fold_left$List_T_Int_Int$PVec_Int$Fn_PVec_Int_T_Int_Int_PVec_Int(xs, acc, f) };

function Array$set$PVec_Int$Int$Int(v, idx, val) {
  switch (v.$) {
    case "PVec": {
      const $f8534 = v._0;
      const $f8535 = v._1;
      const $f8536 = v._2;
      const $f8537 = v._3;
      {
        const tail = $f8537;
        {
          const root = $f8536;
          {
            const shift = $f8535;
            {
              const n = $f8534;
              {
                let $t8529;
                {
                  const $t8527 = (idx < 0);
                  {
                    const $t8528 = (idx >= n);
                    $t8529 = ($t8527 || $t8528);
                  }
                }
                if ($t8529 === true) {
                  march_panic_site("stdlib/array.march", 463, 32, 70);
                  return (() => { throw march_panic_error("panic: ", "Array.set: index out of range"); })();
                } else {
                  {
                    let tail_len;
                    {
                      const go_i5634 = { $: "$Clo_go$0_Array_lst_len_List_Int", _0: go$apply$0_Array_lst_len_List_Int };
                      tail_len = go$apply$0_Array_lst_len_List_Int(go_i5634, tail, 0);
                    }
                    {
                      const tail_offset = ((n - tail_len) < 4611686018427387904 && (n - tail_len) >= -4611686018427387904 ? (n - tail_len) : march_int_ovf((n - tail_len), 1));
                      {
                        const $t8530 = (idx >= tail_offset);
                        if ($t8530 === true) {
                          {
                            const $t8531 = ((idx - tail_offset) < 4611686018427387904 && (idx - tail_offset) >= -4611686018427387904 ? (idx - tail_offset) : march_int_ovf((idx - tail_offset), 1));
                            {
                              let $t8532;
                              {
                                const rev_onto_i5630 = { $: "$Clo_rev_onto$0_Array_lst_set_List_Int_Int_Int", _0: rev_onto$apply$0_Array_lst_set_List_Int_Int_Int };
                                {
                                  const go_i5631 = { $: "$Clo_go$1_Array_lst_set_List_Int_Int_Int", _0: go$apply$1_Array_lst_set_List_Int_Int_Int, _1: rev_onto_i5630, _2: val };
                                  {
                                    const $t8282_i5632 = { $: "Nil" };
                                    $t8532 = go$apply$1_Array_lst_set_List_Int_Int_Int(go_i5631, tail, $t8531, $t8282_i5632);
                                  }
                                }
                              }
                              return { $: "PVec", _0: n, _1: shift, _2: root, _3: $t8532 };
                            }
                          }
                        } else {
                          {
                            let $t8533;
                            {
                              const $t8366_i5626 = { $: "Nil" };
                              $t8533 = Array$trie_update_down$TrieNode_Int$Int$List_T_List_TrieNode_Int_Int$Int$Int(root, shift, $t8366_i5626, idx, val);
                            }
                            return { $: "PVec", _0: n, _1: shift, _2: $t8533, _3: tail };
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
      break;
    }
    default: {
      return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
    }
  }
}
const Array$set$PVec_Int$Int$Int$clo = { _0: ($_, v, idx, val) => Array$set$PVec_Int$Int$Int(v, idx, val) };

function List$map$List_String$Fn_String_Int(xs, f) {
  switch (xs.$) {
    case "Nil": {
      return { $: "Nil" };
      break;
    }
    case "Cons": {
      const $f881 = xs._0;
      const $f882 = xs._1;
      {
        const t = $f882;
        {
          const h = $f881;
          {
            let $t879;
            $t879 = f._0(f, h);
            {
              const $trmc15 = { $: "Cons", _0: $t879, _1: null };
              List$map$dps$List_String$Fn_String_Int$List_Int(t, f, $trmc15);
              return $trmc15;
            }
          }
        }
      }
      break;
    }
    default: {
      return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
    }
  }
}
const List$map$List_String$Fn_String_Int$clo = { _0: ($_, xs, f) => List$map$List_String$Fn_String_Int(xs, f) };

function List$nth$List_Piece$Int($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const xs = $tco_a0;
    const n = $tco_a1;
    switch (xs.$) {
      case "Nil": {
        march_panic_site("stdlib/list.march", 227, 18, 56);
        return (() => { throw march_panic_error("panic: ", "List.nth: index out of bounds"); })();
        break;
      }
      case "Cons": {
        const $f843 = xs._0;
        const $f844 = xs._1;
        {
          const t = $f844;
          {
            const h = $f843;
            {
              const $t841 = (n === 0);
              if ($t841 === true) {
                return h;
              } else {
                {
                  const $t842 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                  {
                    $tco_a0 = t;
                    $tco_a1 = $t842;
                    continue __tco;
                  }
                }
              }
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
    return undefined;
  }
}
const List$nth$List_Piece$Int$clo = { _0: ($_, xs, n) => List$nth$List_Piece$Int(xs, n) };

function List$map$dps$List_Int$Fn_Int_String$List_String($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const xs = $tco_a0;
    const f = $tco_a1;
    const $dst = $tco_a2;
    switch (xs.$) {
      case "Nil": {
        {
          const $trmc13 = { $: "Nil" };
          return ($dst._1 = $trmc13, undefined);
        }
        break;
      }
      case "Cons": {
        const $f881 = xs._0;
        const $f882 = xs._1;
        {
          const t = $f882;
          {
            const h = $f881;
            {
              let $t879;
              $t879 = f._0(f, h);
              {
                const $trmc14 = { $: "Cons", _0: $t879, _1: null };
                ($dst._1 = $trmc14, undefined);
                {
                  $tco_a0 = t;
                  $tco_a1 = f;
                  $tco_a2 = $trmc14;
                  continue __tco;
                }
              }
            }
          }
        }
        break;
      }
      default: {
        {
          const $trmc12 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc12, undefined);
        }
      }
    }
    return undefined;
  }
}
const List$map$dps$List_Int$Fn_Int_String$List_String$clo = { _0: ($_, xs, f, $dst) => List$map$dps$List_Int$Fn_Int_String$List_String(xs, f, $dst) };

function List$map$dps$List_Int$Fn_Int_Int$List_Int($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const xs = $tco_a0;
    const f = $tco_a1;
    const $dst = $tco_a2;
    switch (xs.$) {
      case "Nil": {
        {
          const $trmc13 = { $: "Nil" };
          return ($dst._1 = $trmc13, undefined);
        }
        break;
      }
      case "Cons": {
        const $f881 = xs._0;
        const $f882 = xs._1;
        {
          const t = $f882;
          {
            const h = $f881;
            {
              let $t879;
              $t879 = f._0(f, h);
              {
                const $trmc14 = { $: "Cons", _0: $t879, _1: null };
                ($dst._1 = $trmc14, undefined);
                {
                  $tco_a0 = t;
                  $tco_a1 = f;
                  $tco_a2 = $trmc14;
                  continue __tco;
                }
              }
            }
          }
        }
        break;
      }
      default: {
        {
          const $trmc12 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc12, undefined);
        }
      }
    }
    return undefined;
  }
}
const List$map$dps$List_Int$Fn_Int_Int$List_Int$clo = { _0: ($_, xs, f, $dst) => List$map$dps$List_Int$Fn_Int_Int$List_Int(xs, f, $dst) };

function List$append$dps$List_Int$List_Int$List_Int($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const xs = $tco_a0;
    const ys = $tco_a1;
    const $dst = $tco_a2;
    switch (xs.$) {
      case "Nil": {
        return ($dst._1 = ys, undefined);
        break;
      }
      case "Cons": {
        const $f873 = xs._0;
        const $f874 = xs._1;
        {
          const t = $f874;
          {
            const h = $f873;
            {
              const $trmc10 = { $: "Cons", _0: h, _1: null };
              ($dst._1 = $trmc10, undefined);
              {
                $tco_a0 = t;
                $tco_a1 = ys;
                $tco_a2 = $trmc10;
                continue __tco;
              }
            }
          }
        }
        break;
      }
      default: {
        {
          const $trmc8 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc8, undefined);
        }
      }
    }
    return undefined;
  }
}
const List$append$dps$List_Int$List_Int$List_Int$clo = { _0: ($_, xs, ys, $dst) => List$append$dps$List_Int$List_Int$List_Int(xs, ys, $dst) };

function List$length_onto$List_Int$Int($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const lst = $tco_a0;
    const acc = $tco_a1;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f858 = lst._0;
        const $f859 = lst._1;
        {
          const t = $f859;
          {
            const $t857 = ((acc + 1) < 4611686018427387904 && (acc + 1) >= -4611686018427387904 ? (acc + 1) : march_int_ovf((acc + 1), 0));
            {
              $tco_a0 = t;
              $tco_a1 = $t857;
              continue __tco;
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
    return undefined;
  }
}
const List$length_onto$List_Int$Int$clo = { _0: ($_, lst, acc) => List$length_onto$List_Int$Int(lst, acc) };

function List$filter$dps$List_Int$Fn_Int_Bool$List_Int($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const xs = $tco_a0;
    const pred = $tco_a1;
    const $dst = $tco_a2;
    switch (xs.$) {
      case "Nil": {
        {
          const $trmc22 = { $: "Nil" };
          return ($dst._1 = $trmc22, undefined);
        }
        break;
      }
      case "Cons": {
        const $f911 = xs._0;
        const $f912 = xs._1;
        {
          const t = $f912;
          {
            const h = $f911;
            {
              let $t909;
              $t909 = pred._0(pred, h);
              if ($t909 === true) {
                {
                  const $trmc23 = { $: "Cons", _0: h, _1: null };
                  ($dst._1 = $trmc23, undefined);
                  {
                    $tco_a0 = t;
                    $tco_a1 = pred;
                    $tco_a2 = $trmc23;
                    continue __tco;
                  }
                }
              } else {
                {
                  $tco_a0 = t;
                  $tco_a1 = pred;
                  $tco_a2 = $dst;
                  continue __tco;
                }
              }
            }
          }
        }
        break;
      }
      default: {
        {
          const $trmc21 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc21, undefined);
        }
      }
    }
    return undefined;
  }
}
const List$filter$dps$List_Int$Fn_Int_Bool$List_Int$clo = { _0: ($_, xs, pred, $dst) => List$filter$dps$List_Int$Fn_Int_Bool$List_Int(xs, pred, $dst) };

function List$map$dps$List_T_Int_Int$Fn_T_Int_Int_T_Int_Int$List_T_Int_Int($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const xs = $tco_a0;
    const f = $tco_a1;
    const $dst = $tco_a2;
    switch (xs.$) {
      case "Nil": {
        {
          const $trmc13 = { $: "Nil" };
          return ($dst._1 = $trmc13, undefined);
        }
        break;
      }
      case "Cons": {
        const $f881 = xs._0;
        const $f882 = xs._1;
        {
          const t = $f882;
          {
            const h = $f881;
            {
              let $t879;
              $t879 = f._0(f, h);
              {
                const $trmc14 = { $: "Cons", _0: $t879, _1: null };
                ($dst._1 = $trmc14, undefined);
                {
                  $tco_a0 = t;
                  $tco_a1 = f;
                  $tco_a2 = $trmc14;
                  continue __tco;
                }
              }
            }
          }
        }
        break;
      }
      default: {
        {
          const $trmc12 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc12, undefined);
        }
      }
    }
    return undefined;
  }
}
const List$map$dps$List_T_Int_Int$Fn_T_Int_Int_T_Int_Int$List_T_Int_Int$clo = { _0: ($_, xs, f, $dst) => List$map$dps$List_T_Int_Int$Fn_T_Int_Int_T_Int_Int$List_T_Int_Int(xs, f, $dst) };

function Array$lst_nth$List_Int$Int($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const lst = $tco_a0;
    const n = $tco_a1;
    switch (lst.$) {
      case "Nil": {
        march_panic_site("stdlib/array.march", 53, 11, 46);
        return (() => { throw march_panic_error("panic: ", "Array: index out of bounds"); })();
        break;
      }
      case "Cons": {
        const $f8253 = lst._0;
        const $f8254 = lst._1;
        {
          const t = $f8254;
          {
            let h;
            h = $f8253;
            {
              const $t8251 = (n === 0);
              if ($t8251 === true) {
                return h;
              } else {
                {
                  const $t8252 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                  {
                    $tco_a0 = t;
                    $tco_a1 = $t8252;
                    continue __tco;
                  }
                }
              }
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
    return undefined;
  }
}
const Array$lst_nth$List_Int$Int$clo = { _0: ($_, lst, n) => Array$lst_nth$List_Int$Int(lst, n) };

function Array$trie_get$TrieNode_Int$Int$Int($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const node = $tco_a0;
    const idx = $tco_a1;
    const shift = $tco_a2;
    switch (node.$) {
      case "TrieEmpty": {
        march_panic_site("stdlib/array.march", 167, 17, 49);
        return (() => { throw march_panic_error("panic: ", "Array.get: missing node"); })();
        break;
      }
      case "TrieLeaf": {
        const $f8347 = node._0;
        {
          const values = $f8347;
          {
            const $t8344 = ((idx | 0) === idx && (31 | 0) === 31 ? (idx & 31) : march_int_and(idx, 31));
            {
              const $rc_2696 = Array$lst_nth$List_Int$Int(values, $t8344);
              return $rc_2696;
            }
          }
        }
        break;
      }
      case "TrieBranch": {
        const $f8348 = node._0;
        {
          const children = $f8348;
          {
            let slot;
            {
              const $t8343_i7154 = ((idx | 0) === idx && shift >= 0 && shift < 32 ? (idx >> shift) : march_int_shr(idx, shift));
              slot = (($t8343_i7154 | 0) === $t8343_i7154 && (31 | 0) === 31 ? ($t8343_i7154 & 31) : march_int_and($t8343_i7154, 31));
            }
            {
              const $t8345 = Array$lst_nth$List_TrieNode_Int$Int(children, slot);
              {
                const $t8346 = ((shift - 5) < 4611686018427387904 && (shift - 5) >= -4611686018427387904 ? (shift - 5) : march_int_ovf((shift - 5), 1));
                {
                  $tco_a0 = $t8345;
                  $tco_a1 = idx;
                  $tco_a2 = $t8346;
                  continue __tco;
                }
              }
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
    return undefined;
  }
}
const Array$trie_get$TrieNode_Int$Int$Int$clo = { _0: ($_, node, idx, shift) => Array$trie_get$TrieNode_Int$Int$Int(node, idx, shift) };

function List$flat_map_go$List_Int$List_Int$Fn_Int_List_Int($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const sub = $tco_a0;
    const lst = $tco_a1;
    const f = $tco_a2;
    switch (sub.$) {
      case "Cons": {
        const $f903 = sub._0;
        const $f904 = sub._1;
        {
          const rest = $f904;
          {
            const x = $f903;
            {
              const $trmc20 = { $: "Cons", _0: x, _1: null };
              List$flat_map_go$dps$List_Int$List_Int$Fn_Int_List_Int$List_Int(rest, lst, f, $trmc20);
              return $trmc20;
            }
          }
        }
        break;
      }
      case "Nil": {
        switch (lst.$) {
          case "Nil": {
            return { $: "Nil" };
            break;
          }
          case "Cons": {
            const $f897 = lst._0;
            const $f898 = lst._1;
            {
              const t = $f898;
              {
                const h = $f897;
                {
                  let $t896;
                  $t896 = f._0(f, h);
                  {
                    $tco_a0 = $t896;
                    $tco_a1 = t;
                    $tco_a2 = f;
                    continue __tco;
                  }
                }
              }
            }
            break;
          }
          default: {
            return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          }
        }
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
    return undefined;
  }
}
const List$flat_map_go$List_Int$List_Int$Fn_Int_List_Int$clo = { _0: ($_, sub, lst, f) => List$flat_map_go$List_Int$List_Int$Fn_Int_List_Int(sub, lst, f) };

function List$map$dps$List_String$Fn_String_Int$List_Int($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const xs = $tco_a0;
    const f = $tco_a1;
    const $dst = $tco_a2;
    switch (xs.$) {
      case "Nil": {
        {
          const $trmc13 = { $: "Nil" };
          return ($dst._1 = $trmc13, undefined);
        }
        break;
      }
      case "Cons": {
        const $f881 = xs._0;
        const $f882 = xs._1;
        {
          const t = $f882;
          {
            const h = $f881;
            {
              let $t879;
              $t879 = f._0(f, h);
              {
                const $trmc14 = { $: "Cons", _0: $t879, _1: null };
                ($dst._1 = $trmc14, undefined);
                {
                  $tco_a0 = t;
                  $tco_a1 = f;
                  $tco_a2 = $trmc14;
                  continue __tco;
                }
              }
            }
          }
        }
        break;
      }
      default: {
        {
          const $trmc12 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc12, undefined);
        }
      }
    }
    return undefined;
  }
}
const List$map$dps$List_String$Fn_String_Int$List_Int$clo = { _0: ($_, xs, f, $dst) => List$map$dps$List_String$Fn_String_Int$List_Int(xs, f, $dst) };

function Array$fold_left$PVec_Int$List_Int$Fn_List_Int_Int_List_Int(v, acc, f) {
  switch (v.$) {
    case "PVec": {
      const $f8649 = v._0;
      const $f8650 = v._1;
      const $f8651 = v._2;
      const $f8652 = v._3;
      {
        const tail = $f8652;
        {
          const root = $f8651;
          {
            let acc2;
            acc2 = Array$trie_fold$List_Int$TrieNode_Int$Fn_List_Int_Int_List_Int(acc, root, f);
            {
              const go = { $: "$Clo_go$0_Array_fold_left_PVec_Int_List_Int_Fn_List_Int_Int_List_Int", _0: go$apply$0_Array_fold_left_PVec_Int_List_Int_Fn_List_Int_Int_List_Int, _1: f };
              return go$apply$0_Array_fold_left_PVec_Int_List_Int_Fn_List_Int_Int_List_Int(go, acc2, tail);
            }
          }
        }
      }
      break;
    }
    default: {
      return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
    }
  }
}
const Array$fold_left$PVec_Int$List_Int$Fn_List_Int_Int_List_Int$clo = { _0: ($_, v, acc, f) => Array$fold_left$PVec_Int$List_Int$Fn_List_Int_Int_List_Int(v, acc, f) };

function Array$lst_nth$List_TrieNode_Int$Int($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const lst = $tco_a0;
    const n = $tco_a1;
    switch (lst.$) {
      case "Nil": {
        march_panic_site("stdlib/array.march", 53, 11, 46);
        return (() => { throw march_panic_error("panic: ", "Array: index out of bounds"); })();
        break;
      }
      case "Cons": {
        const $f8253 = lst._0;
        const $f8254 = lst._1;
        {
          const t = $f8254;
          {
            const h = $f8253;
            {
              const $t8251 = (n === 0);
              if ($t8251 === true) {
                return h;
              } else {
                {
                  const $t8252 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                  {
                    $tco_a0 = t;
                    $tco_a1 = $t8252;
                    continue __tco;
                  }
                }
              }
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
    return undefined;
  }
}
const Array$lst_nth$List_TrieNode_Int$Int$clo = { _0: ($_, lst, n) => Array$lst_nth$List_TrieNode_Int$Int(lst, n) };

function Array$trie_update_down$TrieNode_Int$Int$List_T_List_TrieNode_Int_Int$Int$Int($tco_a0, $tco_a1, $tco_a2, $tco_a3, $tco_a4) {
  __tco: for (;;) {
    const n = $tco_a0;
    const s = $tco_a1;
    const path = $tco_a2;
    const idx = $tco_a3;
    const val = $tco_a4;
    switch (n.$) {
      case "TrieEmpty": {
        march_panic_site("stdlib/array.march", 196, 17, 49);
        return (() => { throw march_panic_error("panic: ", "Array.set: missing node"); })();
        break;
      }
      case "TrieLeaf": {
        const $f8364 = n._0;
        {
          const values = $f8364;
          {
            let $t8360;
            {
              const $t8358 = ((idx | 0) === idx && (31 | 0) === 31 ? (idx & 31) : march_int_and(idx, 31));
              {
                let $t8359;
                {
                  const rev_onto_i7220 = { $: "$Clo_rev_onto$0_Array_lst_set_List_Int_Int_Int", _0: rev_onto$apply$0_Array_lst_set_List_Int_Int_Int };
                  {
                    const go_i7221 = { $: "$Clo_go$1_Array_lst_set_List_Int_Int_Int", _0: go$apply$1_Array_lst_set_List_Int_Int_Int, _1: rev_onto_i7220, _2: val };
                    {
                      const $t8282_i7222 = { $: "Nil" };
                      $t8359 = go$apply$1_Array_lst_set_List_Int_Int_Int(go_i7221, values, $t8358, $t8282_i7222);
                    }
                  }
                }
                $t8360 = { $: "TrieLeaf", _0: $t8359 };
              }
            }
            {
              const $rc_2716 = Array$trie_update_up$TrieNode_Int$List_T_List_TrieNode_Int_Int($t8360, path);
              return $rc_2716;
            }
          }
        }
        break;
      }
      case "TrieBranch": {
        const $f8365 = n._0;
        {
          const children = $f8365;
          {
            let slot;
            {
              const $t8343_i7225 = ((idx | 0) === idx && s >= 0 && s < 32 ? (idx >> s) : march_int_shr(idx, s));
              slot = (($t8343_i7225 | 0) === $t8343_i7225 && (31 | 0) === 31 ? ($t8343_i7225 & 31) : march_int_and($t8343_i7225, 31));
            }
            {
              let child;
              child = Array$lst_nth$List_TrieNode_Int$Int(children, slot);
              {
                const $t8361 = ((s - 5) < 4611686018427387904 && (s - 5) >= -4611686018427387904 ? (s - 5) : march_int_ovf((s - 5), 1));
                {
                  const $t8362 = { _0: children, _1: slot };
                  {
                    const $t8363 = { $: "Cons", _0: $t8362, _1: path };
                    {
                      $tco_a0 = child;
                      $tco_a1 = $t8361;
                      $tco_a2 = $t8363;
                      $tco_a3 = idx;
                      $tco_a4 = val;
                      continue __tco;
                    }
                  }
                }
              }
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
    return undefined;
  }
}
const Array$trie_update_down$TrieNode_Int$Int$List_T_List_TrieNode_Int_Int$Int$Int$clo = { _0: ($_, n, s, path, idx, val) => Array$trie_update_down$TrieNode_Int$Int$List_T_List_TrieNode_Int_Int$Int$Int(n, s, path, idx, val) };

function List$flat_map_go$dps$List_Int$List_Int$Fn_Int_List_Int$List_Int($tco_a0, $tco_a1, $tco_a2, $tco_a3) {
  __tco: for (;;) {
    const sub = $tco_a0;
    const lst = $tco_a1;
    const f = $tco_a2;
    const $dst = $tco_a3;
    switch (sub.$) {
      case "Cons": {
        const $f903 = sub._0;
        const $f904 = sub._1;
        {
          const rest = $f904;
          {
            const x = $f903;
            {
              const $trmc17 = { $: "Cons", _0: x, _1: null };
              ($dst._1 = $trmc17, undefined);
              {
                $tco_a0 = rest;
                $tco_a1 = lst;
                $tco_a2 = f;
                $tco_a3 = $trmc17;
                continue __tco;
              }
            }
          }
        }
        break;
      }
      case "Nil": {
        switch (lst.$) {
          case "Nil": {
            {
              const $trmc19 = { $: "Nil" };
              return ($dst._1 = $trmc19, undefined);
            }
            break;
          }
          case "Cons": {
            const $f897 = lst._0;
            const $f898 = lst._1;
            {
              const t = $f898;
              {
                const h = $f897;
                {
                  let $t896;
                  $t896 = f._0(f, h);
                  {
                    $tco_a0 = $t896;
                    $tco_a1 = t;
                    $tco_a2 = f;
                    $tco_a3 = $dst;
                    continue __tco;
                  }
                }
              }
            }
            break;
          }
          default: {
            {
              const $trmc18 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
              return ($dst._1 = $trmc18, undefined);
            }
          }
        }
        break;
      }
      default: {
        {
          const $trmc16 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc16, undefined);
        }
      }
    }
    return undefined;
  }
}
const List$flat_map_go$dps$List_Int$List_Int$Fn_Int_List_Int$List_Int$clo = { _0: ($_, sub, lst, f, $dst) => List$flat_map_go$dps$List_Int$List_Int$Fn_Int_List_Int$List_Int(sub, lst, f, $dst) };

function Array$trie_fold$List_Int$TrieNode_Int$Fn_List_Int_Int_List_Int(acc, node, f) {
  switch (node.$) {
    case "TrieEmpty": {
      return acc;
      break;
    }
    case "TrieLeaf": {
      const $f8454 = node._0;
      {
        const values = $f8454;
        {
          const go = { $: "$Clo_go$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int", _0: go$apply$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int, _1: f };
          return go$apply$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int(go, acc, values);
        }
      }
      break;
    }
    case "TrieBranch": {
      const $f8455 = node._0;
      {
        const children = $f8455;
        {
          const go = { $: "$Clo_go$1_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int", _0: go$apply$1_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int, _1: f };
          return go$apply$1_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int(go, acc, children);
        }
      }
      break;
    }
    default: {
      return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
    }
  }
}
const Array$trie_fold$List_Int$TrieNode_Int$Fn_List_Int_Int_List_Int$clo = { _0: ($_, acc, node, f) => Array$trie_fold$List_Int$TrieNode_Int$Fn_List_Int_Int_List_Int(acc, node, f) };

function Array$trie_update_up$TrieNode_Int$List_T_List_TrieNode_Int_Int($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const nd = $tco_a0;
    const stk = $tco_a1;
    switch (stk.$) {
      case "Nil": {
        return nd;
        break;
      }
      case "Cons": {
        const $f8352 = stk._0;
        const $f8353 = stk._1;
        {
          const rest = $f8353;
          {
            const frame = $f8352;
            {
              const children = frame._0;
              {
                const slot = frame._1;
                {
                  let $t8350;
                  {
                    let $t8349;
                    {
                      const rev_onto_i7294 = { $: "$Clo_rev_onto$0_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int", _0: rev_onto$apply$0_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int };
                      {
                        const go_i7295 = { $: "$Clo_go$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int", _0: go$apply$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int, _1: nd, _2: rev_onto_i7294 };
                        {
                          const $t8342_i7296 = { $: "Nil" };
                          $t8349 = go$apply$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int(go_i7295, children, slot, $t8342_i7296);
                        }
                      }
                    }
                    $t8350 = { $: "TrieBranch", _0: $t8349 };
                  }
                  {
                    $tco_a0 = $t8350;
                    $tco_a1 = rest;
                    continue __tco;
                  }
                }
              }
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
    return undefined;
  }
}
const Array$trie_update_up$TrieNode_Int$List_T_List_TrieNode_Int_Int$clo = { _0: ($_, nd, stk) => Array$trie_update_up$TrieNode_Int$List_T_List_TrieNode_Int_Int(nd, stk) };

function go$apply$0_List_range($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const $clo = $tco_a0;
    const i = $tco_a1;
    const acc = $tco_a2;
    {
      let go;
      go = $clo;
      {
        const start = $clo._1;
        {
          const $t798 = (i < start);
          if ($t798 === true) {
            return acc;
          } else {
            {
              const $t799 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
              {
                const $t800 = { $: "Cons", _0: i, _1: acc };
                {
                  $tco_a0 = go;
                  $tco_a1 = $t799;
                  $tco_a2 = $t800;
                  continue __tco;
                }
              }
            }
          }
        }
      }
    }
    return undefined;
  }
}
const go$apply$0_List_range$clo = { _0: ($_, $clo, i, acc) => go$apply$0_List_range($clo, i, acc) };

function $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides($clo, c) {
  {
    const board = $clo._1;
    {
      const origin_x = $clo._2;
      {
        const origin_y = $clo._3;
        const $f46724 = c._0;
        const $f46725 = c._1;
        {
          const dy = $f46725;
          {
            const dx = $f46724;
            {
              const x = ((origin_x + dx) < 4611686018427387904 && (origin_x + dx) >= -4611686018427387904 ? (origin_x + dx) : march_int_ovf((origin_x + dx), 0));
              {
                const y = ((origin_y + dy) < 4611686018427387904 && (origin_y + dy) >= -4611686018427387904 ? (origin_y + dy) : march_int_ovf((origin_y + dy), 0));
                {
                  let $t46721;
                  {
                    let $t46717_i8089;
                    {
                      let $t46715_i8087;
                      {
                        const $t46712_i8084 = (x >= 0);
                        {
                          const $t46714_i8086 = (x < 10);
                          $t46715_i8087 = ($t46712_i8084 && $t46714_i8086);
                        }
                      }
                      {
                        const $t46716_i8088 = (y >= 0);
                        $t46717_i8089 = ($t46715_i8087 && $t46716_i8088);
                      }
                    }
                    {
                      const $t46719_i8091 = (y < 20);
                      $t46721 = ($t46717_i8089 && $t46719_i8091);
                    }
                  }
                  if ($t46721 === false) {
                    return true;
                  } else if ($t46721 === true) {
                    {
                      let $t46723;
                      {
                        let $t46722;
                        {
                          const $t46700_i8081 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
                          $t46722 = (($t46700_i8081 + x) < 4611686018427387904 && ($t46700_i8081 + x) >= -4611686018427387904 ? ($t46700_i8081 + x) : march_int_ovf(($t46700_i8081 + x), 0));
                        }
                        $t46723 = Array$get$PVec_Int$Int(board, $t46722);
                      }
                      return ($t46723 !== 0);
                    }
                  } else {
                    return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides$clo = { _0: ($_, $clo, c) => $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides($clo, c) };

function $lam0_TetrisLogic_lock_piece$apply$0_TetrisLogic_lock_piece($clo, b, c) {
  {
    const color_idx = $clo._1;
    {
      const origin_x = $clo._2;
      {
        const origin_y = $clo._3;
        const $f46734 = c._0;
        const $f46735 = c._1;
        {
          const dy = $f46735;
          {
            const dx = $f46734;
            {
              const x = ((origin_x + dx) < 4611686018427387904 && (origin_x + dx) >= -4611686018427387904 ? (origin_x + dx) : march_int_ovf((origin_x + dx), 0));
              {
                const y = ((origin_y + dy) < 4611686018427387904 && (origin_y + dy) >= -4611686018427387904 ? (origin_y + dy) : march_int_ovf((origin_y + dy), 0));
                {
                  let $t46732;
                  {
                    let $t46717_i8103;
                    {
                      let $t46715_i8101;
                      {
                        const $t46712_i8098 = (x >= 0);
                        {
                          const $t46714_i8100 = (x < 10);
                          $t46715_i8101 = ($t46712_i8098 && $t46714_i8100);
                        }
                      }
                      {
                        const $t46716_i8102 = (y >= 0);
                        $t46717_i8103 = ($t46715_i8101 && $t46716_i8102);
                      }
                    }
                    {
                      const $t46719_i8105 = (y < 20);
                      $t46732 = ($t46717_i8103 && $t46719_i8105);
                    }
                  }
                  if ($t46732 === true) {
                    {
                      let $t46733;
                      {
                        const $t46700_i8095 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
                        $t46733 = (($t46700_i8095 + x) < 4611686018427387904 && ($t46700_i8095 + x) >= -4611686018427387904 ? ($t46700_i8095 + x) : march_int_ovf(($t46700_i8095 + x), 0));
                      }
                      return Array$set$PVec_Int$Int$Int(b, $t46733, color_idx);
                    }
                  } else if ($t46732 === false) {
                    return b;
                  } else {
                    return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam0_TetrisLogic_lock_piece$apply$0_TetrisLogic_lock_piece$clo = { _0: ($_, $clo, b, c) => $lam0_TetrisLogic_lock_piece$apply$0_TetrisLogic_lock_piece($clo, b, c) };

function $lam0_TetrisLogic_row_full$apply$0_TetrisLogic_row_full($clo, x) {
  {
    const board = $clo._1;
    {
      const y = $clo._2;
      {
        let $t46745;
        {
          let $t46744;
          {
            const $t46700_i8109 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
            $t46744 = (($t46700_i8109 + x) < 4611686018427387904 && ($t46700_i8109 + x) >= -4611686018427387904 ? ($t46700_i8109 + x) : march_int_ovf(($t46700_i8109 + x), 0));
          }
          $t46745 = Array$get$PVec_Int$Int(board, $t46744);
        }
        return ($t46745 !== 0);
      }
    }
  }
}
const $lam0_TetrisLogic_row_full$apply$0_TetrisLogic_row_full$clo = { _0: ($_, $clo, x) => $lam0_TetrisLogic_row_full$apply$0_TetrisLogic_row_full($clo, x) };

function $lam0_TetrisLogic_row_cells$apply$0_TetrisLogic_row_cells($clo, x) {
  {
    const board = $clo._1;
    {
      const y = $clo._2;
      {
        let $t46750;
        {
          const $t46700_i8113 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
          $t46750 = (($t46700_i8113 + x) < 4611686018427387904 && ($t46700_i8113 + x) >= -4611686018427387904 ? ($t46700_i8113 + x) : march_int_ovf(($t46700_i8113 + x), 0));
        }
        return Array$get$PVec_Int$Int(board, $t46750);
      }
    }
  }
}
const $lam0_TetrisLogic_row_cells$apply$0_TetrisLogic_row_cells$clo = { _0: ($_, $clo, x) => $lam0_TetrisLogic_row_cells$apply$0_TetrisLogic_row_cells($clo, x) };

function $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines($clo, y) {
  {
    const board = $clo._1;
    {
      let $t46754;
      {
        let $t46742_i13354;
        {
          const go_i5158_i13351 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
          {
            const $t802_i5160_i13353 = { $: "Nil" };
            $t46742_i13354 = go$apply$0_List_range(go_i5158_i13351, 9, $t802_i5160_i13353);
          }
        }
        {
          const $t46746_i13355 = { $: "$Clo_$lam0_TetrisLogic_row_full$0_TetrisLogic_row_full", _0: $lam0_TetrisLogic_row_full$apply$0_TetrisLogic_row_full, _1: board, _2: y };
          {
            const $rc_2497_i13356 = List$all$List_Int$Fn_Int_Bool($t46742_i13354, $t46746_i13355);
            $t46754 = $rc_2497_i13356;
          }
        }
      }
      return (!$t46754);
    }
  }
}
const $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines$clo = { _0: ($_, $clo, y) => $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines($clo, y) };

function $lam1_TetrisLogic_clear_lines$apply$1_TetrisLogic_clear_lines($clo, y) {
  {
    const board = $clo._1;
    {
      let $t46748_i8117;
      {
        const go_i13519 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
        {
          const $t802_i13521 = { $: "Nil" };
          $t46748_i8117 = go$apply$0_List_range(go_i13519, 9, $t802_i13521);
        }
      }
      {
        const $t46751_i8118 = { $: "$Clo_$lam0_TetrisLogic_row_cells$0_TetrisLogic_row_cells", _0: $lam0_TetrisLogic_row_cells$apply$0_TetrisLogic_row_cells, _1: board, _2: y };
        {
          const xs_i13549 = $t46748_i8117;
          {
            const f_i13550 = $t46751_i8118;
            switch (xs_i13549.$) {
              case "Nil": {
                return { $: "Nil" };
                break;
              }
              case "Cons": {
                const $f881_i13551 = xs_i13549._0;
                const $f882_i13552 = xs_i13549._1;
                {
                  const t_i13553 = $f882_i13552;
                  {
                    const h_i13554 = $f881_i13551;
                    {
                      let $t879_i13555;
                      $t879_i13555 = f_i13550._0(f_i13550, h_i13554);
                      {
                        const $trmc15_i13556 = { $: "Cons", _0: $t879_i13555, _1: null };
                        List$map$dps$List_Int$Fn_Int_Int$List_Int(t_i13553, f_i13550, $trmc15_i13556);
                        return $trmc15_i13556;
                      }
                    }
                  }
                }
                break;
              }
              default: {
                return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
              }
            }
          }
        }
      }
    }
  }
}
const $lam1_TetrisLogic_clear_lines$apply$1_TetrisLogic_clear_lines$clo = { _0: ($_, $clo, y) => $lam1_TetrisLogic_clear_lines$apply$1_TetrisLogic_clear_lines($clo, y) };

function $lam0_int_list_to_string$apply$0_int_list_to_string($clo, x) {
  return String(x);
}
const $lam0_int_list_to_string$apply$0_int_list_to_string$clo = { _0: ($_, $clo, x) => $lam0_int_list_to_string$apply$0_int_list_to_string($clo, x) };

function $lam0_string_to_int_list$apply$0_string_to_int_list($clo, x) {
  {
    let $t46768;
    {
      const $rc_3244 = march_string_to_int(x);
      $t46768 = $rc_3244;
    }
    {
      const $rc_3243 = Option$unwrap_or$Option_Int$Int($t46768, 0);
      return $rc_3243;
    }
  }
}
const $lam0_string_to_int_list$apply$0_string_to_int_list$clo = { _0: ($_, $clo, x) => $lam0_string_to_int_list$apply$0_string_to_int_list($clo, x) };

function $lam0_render_board$apply$0_render_board($clo, y) {
  {
    const board = $clo._1;
    {
      let $t46825;
      {
        const go_i8124 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
        {
          const $t802_i8126 = { $: "Nil" };
          $t46825 = go$apply$0_List_range(go_i8124, 9, $t802_i8126);
        }
      }
      {
        let $t46833;
        $t46833 = { $: "$Clo_$lam0__lam0_render_board$1_render_board", _0: $lam0__lam0_render_board$apply$1_render_board, _1: board, _2: y };
        {
          const f_i8120 = $t46833;
          {
            const go_i8121 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i8120 };
            return go$apply$0_List_each_List_Int_Fn_Int_T_(go_i8121, $t46825);
          }
        }
      }
    }
  }
}
const $lam0_render_board$apply$0_render_board$clo = { _0: ($_, $clo, y) => $lam0_render_board$apply$0_render_board($clo, y) };

function $lam0__lam0_render_board$apply$1_render_board($clo, x) {
  {
    const board = $clo._1;
    {
      const y = $clo._2;
      {
        let idx;
        {
          const $t46700_i8131 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
          idx = (($t46700_i8131 + x) < 4611686018427387904 && ($t46700_i8131 + x) >= -4611686018427387904 ? ($t46700_i8131 + x) : march_int_ovf(($t46700_i8131 + x), 0));
        }
        {
          let v;
          v = Array$get$PVec_Int$Int(board, idx);
          {
            let id;
            {
              const $t46827 = String(x);
              {
                const $t46828 = String(y);
                {
                  const $rc_3245 = march_string_concat_n("cell-", $t46827, "-", $t46828);
                  id = $rc_3245;
                }
              }
            }
            {
              const $t46829 = Js$Dom$find(id);
              switch ($t46829.$) {
                case "None": {
                  return {  };
                  break;
                }
                case "Some": {
                  const $f46832 = $t46829._0;
                  {
                    const cell = $f46832;
                    {
                      const $t46830 = (v === 0);
                      if ($t46830 === true) {
                        return Js$Dom$set_style(cell, "background", "");
                      } else if ($t46830 === false) {
                        {
                          let $t46831;
                          if (v === 1) {
                            $t46831 = "#00CED1";
                          } else if (v === 2) {
                            $t46831 = "#FFD700";
                          } else if (v === 3) {
                            $t46831 = "#9B59B6";
                          } else if (v === 4) {
                            $t46831 = "#2ECC71";
                          } else if (v === 5) {
                            $t46831 = "#E74C3C";
                          } else if (v === 6) {
                            $t46831 = "#3498DB";
                          } else if (v === 7) {
                            $t46831 = "#F39C12";
                          } else {
                            $t46831 = "";
                          }
                          return Js$Dom$set_style(cell, "background", $t46831);
                        }
                      } else {
                        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
                      }
                    }
                  }
                  break;
                }
                default: {
                  return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam0__lam0_render_board$apply$1_render_board$clo = { _0: ($_, $clo, x) => $lam0__lam0_render_board$apply$1_render_board($clo, x) };

function $lam0_render_falling$apply$0_render_falling($clo, c) {
  {
    const ox = $clo._1;
    {
      const oy = $clo._2;
      {
        const piece = $clo._3;
        const $f46850 = c._0;
        const $f46851 = c._1;
        {
          const dy = $f46851;
          {
            const dx = $f46850;
            {
              const x = ((ox + dx) < 4611686018427387904 && (ox + dx) >= -4611686018427387904 ? (ox + dx) : march_int_ovf((ox + dx), 0));
              {
                const y = ((oy + dy) < 4611686018427387904 && (oy + dy) >= -4611686018427387904 ? (oy + dy) : march_int_ovf((oy + dy), 0));
                {
                  let $t46844;
                  {
                    let $t46841;
                    {
                      let $t46839;
                      {
                        const $t46836 = (x >= 0);
                        {
                          const $t46838 = (x < 10);
                          $t46839 = ($t46836 && $t46838);
                        }
                      }
                      {
                        const $t46840 = (y >= 0);
                        $t46841 = ($t46839 && $t46840);
                      }
                    }
                    {
                      const $t46843 = (y < 20);
                      $t46844 = ($t46841 && $t46843);
                    }
                  }
                  if ($t46844 === false) {
                    return {  };
                  } else if ($t46844 === true) {
                    {
                      let id;
                      {
                        const $t46845 = String(x);
                        {
                          const $t46846 = String(y);
                          {
                            const $rc_3246 = march_string_concat_n("cell-", $t46845, "-", $t46846);
                            id = $rc_3246;
                          }
                        }
                      }
                      {
                        const $t46847 = Js$Dom$find(id);
                        switch ($t46847.$) {
                          case "None": {
                            return {  };
                            break;
                          }
                          case "Some": {
                            const $f46849 = $t46847._0;
                            {
                              const cell = $f46849;
                              {
                                let $t46848;
                                switch (piece.$) {
                                  case "I": {
                                    $t46848 = "#00CED1";
                                    break;
                                  }
                                  case "O": {
                                    $t46848 = "#FFD700";
                                    break;
                                  }
                                  case "T": {
                                    $t46848 = "#9B59B6";
                                    break;
                                  }
                                  case "S": {
                                    $t46848 = "#2ECC71";
                                    break;
                                  }
                                  case "Z": {
                                    $t46848 = "#E74C3C";
                                    break;
                                  }
                                  case "J": {
                                    $t46848 = "#3498DB";
                                    break;
                                  }
                                  case "L": {
                                    $t46848 = "#F39C12";
                                    break;
                                  }
                                  default: {
                                    throw march_panic_error("panic: ", "non-exhaustive pattern match");
                                    break;
                                  }
                                }
                                return Js$Dom$set_style(cell, "background", $t46848);
                              }
                            }
                            break;
                          }
                          default: {
                            return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
                          }
                        }
                      }
                    }
                  } else {
                    return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam0_render_falling$apply$0_render_falling$clo = { _0: ($_, $clo, c) => $lam0_render_falling$apply$0_render_falling($clo, c) };

function $lam0_tick$apply$0_tick($clo, board, piece, rot, x, y, next, score, lines, rng) {
  {
    const $t46979 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t46979, rot);
      {
        let $t46981;
        {
          const $t46980 = ((y + 1) < 4611686018427387904 && (y + 1) >= -4611686018427387904 ? (y + 1) : march_int_ovf((y + 1), 0));
          {
            const $t46730_i8136 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: x, _3: $t46980 };
            $t46981 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t46730_i8136);
          }
        }
        if ($t46981 === true) {
          {
            const $rc_3247 = lock_and_advance(board, piece, rot, x, y, next, score, lines, rng);
            return $rc_3247;
          }
        } else if ($t46981 === false) {
          {
            const $t46982 = ((y + 1) < 4611686018427387904 && (y + 1) >= -4611686018427387904 ? (y + 1) : march_int_ovf((y + 1), 0));
            return { _0: board, _1: piece, _2: rot, _3: x, _4: $t46982, _5: next, _6: score, _7: lines, _8: rng, _9: false };
          }
        } else {
          return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const $lam0_tick$apply$0_tick$clo = { _0: ($_, $clo, board, piece, rot, x, y, next, score, lines, rng) => $lam0_tick$apply$0_tick($clo, board, piece, rot, x, y, next, score, lines, rng) };

function $lam0_schedule_tick$apply$0_schedule_tick($clo, _) {
  {
    let $eff;
    {
      const $t46977_i13358 = is_paused();
      if ($t46977_i13358 === true) {
        $eff = {  };
      } else if ($t46977_i13358 === false) {
        {
          const $t46983_i13359 = { $: "$Clo_$lam0_tick$0_tick", _0: $lam0_tick$apply$0_tick };
          $eff = with_state($t46983_i13359);
        }
      } else {
        throw march_panic_error("panic: ", "non-exhaustive pattern match");
      }
    }
  }
  {
    let level_i8139;
    {
      let $t46985_i8138;
      {
        const $t46984_i8137 = state_el();
        $t46985_i8138 = get_int_attr($t46984_i8137, "data-lines", 0);
      }
      level_i8139 = TetrisLogic$level_for_lines($t46985_i8138);
    }
    {
      let $t46986_i8140;
      {
        let $t46698_i13524;
        {
          const $t46697_i13523 = ((level_i8139 * 40) < 4611686018427387904 && (level_i8139 * 40) >= -4611686018427387904 ? (level_i8139 * 40) : march_int_ovf((level_i8139 * 40), 2));
          $t46698_i13524 = ((500 - $t46697_i13523) < 4611686018427387904 && (500 - $t46697_i13523) >= -4611686018427387904 ? (500 - $t46697_i13523) : march_int_ovf((500 - $t46697_i13523), 1));
        }
        {
          const $t2349_i5151_i13525 = ($t46698_i13524 > 100);
          if ($t2349_i5151_i13525 === true) {
            $t46986_i8140 = $t46698_i13524;
          } else {
            $t46986_i8140 = 100;
          }
        }
      }
      {
        const $t46988_i8141 = { $: "$Clo_$lam0_schedule_tick$0_schedule_tick", _0: $lam0_schedule_tick$apply$0_schedule_tick };
        return Js$Dom$set_timeout($t46986_i8140, $t46988_i8141);
      }
    }
  }
}
const $lam0_schedule_tick$apply$0_schedule_tick$clo = { _0: ($_, $clo, _) => $lam0_schedule_tick$apply$0_schedule_tick($clo, _) };

function $lam0_try_move$apply$0_try_move($clo, board, piece, rot, x, y, next, score, lines, rng) {
  {
    const dx = $clo._1;
    {
      const dy = $clo._2;
      {
        const $t46990 = TetrisLogic$piece_cells(piece);
        {
          const cells = rotate_n($t46990, rot);
          {
            let $t46993;
            {
              const $t46991 = ((x + dx) < 4611686018427387904 && (x + dx) >= -4611686018427387904 ? (x + dx) : march_int_ovf((x + dx), 0));
              {
                const $t46992 = ((y + dy) < 4611686018427387904 && (y + dy) >= -4611686018427387904 ? (y + dy) : march_int_ovf((y + dy), 0));
                {
                  const $t46730_i8146 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: $t46991, _3: $t46992 };
                  $t46993 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t46730_i8146);
                }
              }
            }
            if ($t46993 === true) {
              return { _0: board, _1: piece, _2: rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: rng, _9: false };
            } else if ($t46993 === false) {
              {
                const $t46994 = ((x + dx) < 4611686018427387904 && (x + dx) >= -4611686018427387904 ? (x + dx) : march_int_ovf((x + dx), 0));
                {
                  const $t46995 = ((y + dy) < 4611686018427387904 && (y + dy) >= -4611686018427387904 ? (y + dy) : march_int_ovf((y + dy), 0));
                  return { _0: board, _1: piece, _2: rot, _3: $t46994, _4: $t46995, _5: next, _6: score, _7: lines, _8: rng, _9: false };
                }
              }
            } else {
              return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
            }
          }
        }
      }
    }
  }
}
const $lam0_try_move$apply$0_try_move$clo = { _0: ($_, $clo, board, piece, rot, x, y, next, score, lines, rng) => $lam0_try_move$apply$0_try_move($clo, board, piece, rot, x, y, next, score, lines, rng) };

function $lam0_try_rotate$apply$0_try_rotate($clo, board, piece, rot, x, y, next, score, lines, rng) {
  {
    let new_rot;
    {
      const $t46998 = ((rot + 1) < 4611686018427387904 && (rot + 1) >= -4611686018427387904 ? (rot + 1) : march_int_ovf((rot + 1), 0));
      new_rot = (4 === 0 ? march_mod_zero() : $t46998 % 4);
    }
    {
      const $t46999 = TetrisLogic$piece_cells(piece);
      {
        const cells = rotate_n($t46999, new_rot);
        {
          let $t47000;
          {
            const $t46730_i8151 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: x, _3: y };
            $t47000 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t46730_i8151);
          }
          if ($t47000 === true) {
            return { _0: board, _1: piece, _2: rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: rng, _9: false };
          } else if ($t47000 === false) {
            return { _0: board, _1: piece, _2: new_rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: rng, _9: false };
          } else {
            return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          }
        }
      }
    }
  }
}
const $lam0_try_rotate$apply$0_try_rotate$clo = { _0: ($_, $clo, board, piece, rot, x, y, next, score, lines, rng) => $lam0_try_rotate$apply$0_try_rotate($clo, board, piece, rot, x, y, next, score, lines, rng) };

function $lam0_hard_drop$apply$0_hard_drop($clo, board, piece, rot, x, y, next, score, lines, rng) {
  {
    const $t47006 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t47006, rot);
      {
        let final_y;
        final_y = fall_from(board, cells, x, y);
        {
          const $rc_3248 = lock_and_advance(board, piece, rot, x, final_y, next, score, lines, rng);
          return $rc_3248;
        }
      }
    }
  }
}
const $lam0_hard_drop$apply$0_hard_drop$clo = { _0: ($_, $clo, board, piece, rot, x, y, next, score, lines, rng) => $lam0_hard_drop$apply$0_hard_drop($clo, board, piece, rot, x, y, next, score, lines, rng) };

function $lam0_build_board_dom$apply$0_build_board_dom($clo, y) {
  {
    const container = $clo._1;
    {
      const row = Js$Dom$create("div");
      {
        let $eff;
        $eff = Js$Dom$add_class(row, "tetris-row");
      }
      {
        let $eff;
        {
          let $t47081;
          {
            const go_i8157 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
            {
              const $t802_i8159 = { $: "Nil" };
              $t47081 = go$apply$0_List_range(go_i8157, 9, $t802_i8159);
            }
          }
          {
            let $t47086;
            $t47086 = { $: "$Clo_$lam0__lam0_build_board_dom$1_build_board_dom", _0: $lam0__lam0_build_board_dom$apply$1_build_board_dom, _1: row, _2: y };
            {
              const f_i8153 = $t47086;
              {
                const go_i8154 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i8153 };
                $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i8154, $t47081);
              }
            }
          }
        }
      }
      return Js$Dom$append(container, row);
    }
  }
}
const $lam0_build_board_dom$apply$0_build_board_dom$clo = { _0: ($_, $clo, y) => $lam0_build_board_dom$apply$0_build_board_dom($clo, y) };

function $lam0__lam0_build_board_dom$apply$1_build_board_dom($clo, x) {
  {
    const row = $clo._1;
    {
      const y = $clo._2;
      {
        const cell = Js$Dom$create("div");
        {
          let $eff;
          $eff = Js$Dom$add_class(cell, "tetris-cell");
        }
        {
          let $eff;
          {
            let $t47085;
            {
              const $t47083 = String(x);
              {
                const $t47084 = String(y);
                {
                  const $rc_3249 = march_string_concat_n("cell-", $t47083, "-", $t47084);
                  $t47085 = $rc_3249;
                }
              }
            }
            $eff = Js$Dom$set_attr(cell, "id", $t47085);
          }
        }
        return Js$Dom$append(row, cell);
      }
    }
  }
}
const $lam0__lam0_build_board_dom$apply$1_build_board_dom$clo = { _0: ($_, $clo, x) => $lam0__lam0_build_board_dom$apply$1_build_board_dom($clo, x) };

function $lam0_main$apply$0_main($clo, ev) {
  return handle_key(ev);
}
const $lam0_main$apply$0_main$clo = { _0: ($_, $clo, ev) => $lam0_main$apply$0_main($clo, ev) };

function $lam1_main$apply$1_main($clo, _) {
  return restore_from_request();
}
const $lam1_main$apply$1_main$clo = { _0: ($_, $clo, _) => $lam1_main$apply$1_main($clo, _) };

function go$apply$0_List_repeat_Int_Int($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const $clo = $tco_a0;
    const i = $tco_a1;
    const acc = $tco_a2;
    {
      let go;
      go = $clo;
      {
        const x = $clo._1;
        {
          const $t794 = (i <= 0);
          if ($t794 === true) {
            return acc;
          } else {
            {
              const $t795 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
              {
                const $t796 = { $: "Cons", _0: x, _1: acc };
                {
                  $tco_a0 = go;
                  $tco_a1 = $t795;
                  $tco_a2 = $t796;
                  continue __tco;
                }
              }
            }
          }
        }
      }
    }
    return undefined;
  }
}
const go$apply$0_List_repeat_Int_Int$clo = { _0: ($_, $clo, i, acc) => go$apply$0_List_repeat_Int_Int($clo, i, acc) };

function up$apply$0_Array_from_list_List_Int($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const $clo = $tco_a0;
    const nodes = $tco_a1;
    const shift = $tco_a2;
    {
      const up = $clo;
      {
        const $t8780 = { $: "$Clo_$lam0_Array_from_list_up$1_Array_from_list_List_Int", _0: $lam0_Array_from_list_up$apply$1_Array_from_list_List_Int };
        {
          let parents;
          {
            const wrap_i8295 = $t8780;
            {
              const chunk_i8296 = { $: "$Clo_chunk$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int", _0: chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int, _1: wrap_i8295 };
              {
                const $t8704_i8297 = { $: "Nil" };
                {
                  const $t8705_i8298 = { $: "Nil" };
                  parents = chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int(chunk_i8296, nodes, 0, $t8704_i8297, $t8705_i8298);
                }
              }
            }
          }
          {
            let $t8782;
            {
              let $t8781;
              {
                const go_i8293 = { $: "$Clo_go$0_Array_lst_len_List_TrieNode_Int", _0: go$apply$0_Array_lst_len_List_TrieNode_Int };
                $t8781 = go$apply$0_Array_lst_len_List_TrieNode_Int(go_i8293, parents, 0);
              }
              $t8782 = ($t8781 === 1);
            }
            if ($t8782 === true) {
              switch (parents.$) {
                case "Cons": {
                  const $f8786 = parents._0;
                  const $f8787 = parents._1;
                  {
                    const root = $f8786;
                    {
                      const $t8783 = ((shift + 5) < 4611686018427387904 && (shift + 5) >= -4611686018427387904 ? (shift + 5) : march_int_ovf((shift + 5), 0));
                      return { _0: root, _1: $t8783 };
                    }
                  }
                  break;
                }
                case "Nil": {
                  {
                    const $t8784 = { $: "TrieEmpty" };
                    {
                      const $t8785 = ((shift + 5) < 4611686018427387904 && (shift + 5) >= -4611686018427387904 ? (shift + 5) : march_int_ovf((shift + 5), 0));
                      return { _0: $t8784, _1: $t8785 };
                    }
                  }
                  break;
                }
                default: {
                  return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
                }
              }
            } else {
              {
                const $t8792 = ((shift + 5) < 4611686018427387904 && (shift + 5) >= -4611686018427387904 ? (shift + 5) : march_int_ovf((shift + 5), 0));
                {
                  $tco_a0 = $clo;
                  $tco_a1 = parents;
                  $tco_a2 = $t8792;
                  continue __tco;
                }
              }
            }
          }
        }
      }
    }
    return undefined;
  }
}
const up$apply$0_Array_from_list_List_Int$clo = { _0: ($_, $clo, nodes, shift) => up$apply$0_Array_from_list_List_Int($clo, nodes, shift) };

function $lam0_Array_from_list_up$apply$1_Array_from_list_List_Int($clo, cs) {
  return { $: "TrieBranch", _0: cs };
}
const $lam0_Array_from_list_up$apply$1_Array_from_list_List_Int$clo = { _0: ($_, $clo, cs) => $lam0_Array_from_list_up$apply$1_Array_from_list_List_Int($clo, cs) };

function $lam0_Array_from_list$apply$2_Array_from_list_List_Int($clo, vs) {
  return { $: "TrieLeaf", _0: vs };
}
const $lam0_Array_from_list$apply$2_Array_from_list_List_Int$clo = { _0: ($_, $clo, vs) => $lam0_Array_from_list$apply$2_Array_from_list_List_Int($clo, vs) };

function go$apply$0_List_each_List_Int_Fn_Int_T_($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const $clo = $tco_a0;
    const lst = $tco_a1;
    {
      let go;
      go = $clo;
      {
        const f = $clo._1;
        switch (lst.$) {
          case "Nil": {
            return {  };
            break;
          }
          case "Cons": {
            const $f888 = lst._0;
            const $f889 = lst._1;
            {
              const t = $f889;
              {
                const h = $f888;
                {
                  let $p887;
                  $p887 = f._0(f, h);
                  {
                    $tco_a0 = go;
                    $tco_a1 = t;
                    continue __tco;
                  }
                }
              }
            }
            break;
          }
          default: {
            return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          }
        }
      }
    }
    return undefined;
  }
}
const go$apply$0_List_each_List_Int_Fn_Int_T_$clo = { _0: ($_, $clo, lst) => go$apply$0_List_each_List_Int_Fn_Int_T_($clo, lst) };

function go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const $clo = $tco_a0;
    const lst = $tco_a1;
    {
      let go;
      go = $clo;
      {
        const f = $clo._1;
        switch (lst.$) {
          case "Nil": {
            return {  };
            break;
          }
          case "Cons": {
            const $f888 = lst._0;
            const $f889 = lst._1;
            {
              const t = $f889;
              {
                const h = $f888;
                {
                  let $p887;
                  $p887 = f._0(f, h);
                  {
                    $tco_a0 = go;
                    $tco_a1 = t;
                    continue __tco;
                  }
                }
              }
            }
            break;
          }
          default: {
            return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          }
        }
      }
    }
    return undefined;
  }
}
const go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_$clo = { _0: ($_, $clo, lst) => go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_($clo, lst) };

function $lam0_Array_to_list$apply$0_Array_to_list_PVec_Int($clo, acc, x) {
  return { $: "Cons", _0: x, _1: acc };
}
const $lam0_Array_to_list$apply$0_Array_to_list_PVec_Int$clo = { _0: ($_, $clo, acc, x) => $lam0_Array_to_list$apply$0_Array_to_list_PVec_Int($clo, acc, x) };

function go$apply$0_Array_lst_len_List_TrieNode_Int($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const $clo = $tco_a0;
    const xs = $tco_a1;
    const acc = $tco_a2;
    {
      const go = $clo;
      switch (xs.$) {
        case "Nil": {
          return acc;
          break;
        }
        case "Cons": {
          const $f8284 = xs._0;
          const $f8285 = xs._1;
          {
            const t = $f8285;
            {
              const $t8283 = ((acc + 1) < 4611686018427387904 && (acc + 1) >= -4611686018427387904 ? (acc + 1) : march_int_ovf((acc + 1), 0));
              {
                $tco_a0 = $clo;
                $tco_a1 = t;
                $tco_a2 = $t8283;
                continue __tco;
              }
            }
          }
          break;
        }
        default: {
          return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
        }
      }
    }
    return undefined;
  }
}
const go$apply$0_Array_lst_len_List_TrieNode_Int$clo = { _0: ($_, $clo, xs, acc) => go$apply$0_Array_lst_len_List_TrieNode_Int($clo, xs, acc) };

function chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int($tco_a0, $tco_a1, $tco_a2, $tco_a3, $tco_a4) {
  __tco: for (;;) {
    const $clo = $tco_a0;
    const ys = $tco_a1;
    const i = $tco_a2;
    const cur = $tco_a3;
    const out = $tco_a4;
    {
      let chunk;
      chunk = $clo;
      {
        const wrap = $clo._1;
        switch (ys.$) {
          case "Nil": {
            switch (cur.$) {
              case "Nil": {
                {
                  const go_i8378 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                  {
                    const $t8250_i8379 = { $: "Nil" };
                    return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i8378, out, $t8250_i8379);
                  }
                }
                break;
              }
              default: {
                {
                  let $t8686;
                  {
                    let $t8685;
                    {
                      const go_i8375 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                      {
                        const $t8250_i8376 = { $: "Nil" };
                        $t8685 = go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i8375, cur, $t8250_i8376);
                      }
                    }
                    $t8686 = wrap._0(wrap, $t8685);
                  }
                  {
                    const $t8687 = { $: "Cons", _0: $t8686, _1: out };
                    {
                      const go_i8372 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                      {
                        const $t8250_i8373 = { $: "Nil" };
                        return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i8372, $t8687, $t8250_i8373);
                      }
                    }
                  }
                }
              }
            }
            break;
          }
          case "Cons": {
            const $f8698 = ys._0;
            const $f8699 = ys._1;
            {
              const t = $f8699;
              {
                const h = $f8698;
                {
                  const $t8690 = (i === 31);
                  if ($t8690 === true) {
                    {
                      const $t8691 = { $: "Nil" };
                      {
                        let $t8694;
                        {
                          const $t8692 = { $: "Cons", _0: h, _1: cur };
                          {
                            let $t8693;
                            {
                              const go_i8381 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                              {
                                const $t8250_i8382 = { $: "Nil" };
                                $t8693 = go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i8381, $t8692, $t8250_i8382);
                              }
                            }
                            $t8694 = wrap._0(wrap, $t8693);
                          }
                        }
                        {
                          const $t8695 = { $: "Cons", _0: $t8694, _1: out };
                          {
                            $tco_a0 = chunk;
                            $tco_a1 = t;
                            $tco_a2 = 0;
                            $tco_a3 = $t8691;
                            $tco_a4 = $t8695;
                            continue __tco;
                          }
                        }
                      }
                    }
                  } else {
                    {
                      const $t8696 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                      {
                        const $t8697 = { $: "Cons", _0: h, _1: cur };
                        {
                          $tco_a0 = chunk;
                          $tco_a1 = t;
                          $tco_a2 = $t8696;
                          $tco_a3 = $t8697;
                          $tco_a4 = out;
                          continue __tco;
                        }
                      }
                    }
                  }
                }
              }
            }
            break;
          }
          default: {
            return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          }
        }
      }
    }
    return undefined;
  }
}
const chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int$clo = { _0: ($_, $clo, ys, i, cur, out) => chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int($clo, ys, i, cur, out) };

function chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int($tco_a0, $tco_a1, $tco_a2, $tco_a3, $tco_a4) {
  __tco: for (;;) {
    const $clo = $tco_a0;
    const ys = $tco_a1;
    const i = $tco_a2;
    const cur = $tco_a3;
    const out = $tco_a4;
    {
      let chunk;
      chunk = $clo;
      {
        const wrap = $clo._1;
        switch (ys.$) {
          case "Nil": {
            switch (cur.$) {
              case "Nil": {
                {
                  const go_i8390 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                  {
                    const $t8250_i8391 = { $: "Nil" };
                    return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i8390, out, $t8250_i8391);
                  }
                }
                break;
              }
              default: {
                {
                  let $t8686;
                  {
                    let $t8685;
                    {
                      const go_i8387 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                      {
                        const $t8250_i8388 = { $: "Nil" };
                        $t8685 = go$apply$0_Array_lst_rev_List_Int(go_i8387, cur, $t8250_i8388);
                      }
                    }
                    $t8686 = wrap._0(wrap, $t8685);
                  }
                  {
                    const $t8687 = { $: "Cons", _0: $t8686, _1: out };
                    {
                      const go_i8384 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                      {
                        const $t8250_i8385 = { $: "Nil" };
                        return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i8384, $t8687, $t8250_i8385);
                      }
                    }
                  }
                }
              }
            }
            break;
          }
          case "Cons": {
            const $f8698 = ys._0;
            const $f8699 = ys._1;
            {
              const t = $f8699;
              {
                const h = $f8698;
                {
                  const $t8690 = (i === 31);
                  if ($t8690 === true) {
                    {
                      const $t8691 = { $: "Nil" };
                      {
                        let $t8694;
                        {
                          const $t8692 = { $: "Cons", _0: h, _1: cur };
                          {
                            let $t8693;
                            {
                              const go_i8393 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                              {
                                const $t8250_i8394 = { $: "Nil" };
                                $t8693 = go$apply$0_Array_lst_rev_List_Int(go_i8393, $t8692, $t8250_i8394);
                              }
                            }
                            $t8694 = wrap._0(wrap, $t8693);
                          }
                        }
                        {
                          const $t8695 = { $: "Cons", _0: $t8694, _1: out };
                          {
                            $tco_a0 = chunk;
                            $tco_a1 = t;
                            $tco_a2 = 0;
                            $tco_a3 = $t8691;
                            $tco_a4 = $t8695;
                            continue __tco;
                          }
                        }
                      }
                    }
                  } else {
                    {
                      const $t8696 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                      {
                        const $t8697 = { $: "Cons", _0: h, _1: cur };
                        {
                          $tco_a0 = chunk;
                          $tco_a1 = t;
                          $tco_a2 = $t8696;
                          $tco_a3 = $t8697;
                          $tco_a4 = out;
                          continue __tco;
                        }
                      }
                    }
                  }
                }
              }
            }
            break;
          }
          default: {
            return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          }
        }
      }
    }
    return undefined;
  }
}
const chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int$clo = { _0: ($_, $clo, ys, i, cur, out) => chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int($clo, ys, i, cur, out) };

function go$apply$0_Array_lst_split_List_Int_Int($tco_a0, $tco_a1, $tco_a2, $tco_a3) {
  __tco: for (;;) {
    const $clo = $tco_a0;
    const ys = $tco_a1;
    const i = $tco_a2;
    const acc = $tco_a3;
    {
      const go = $clo;
      {
        const $t8672 = (i === 0);
        if ($t8672 === true) {
          {
            let $t8673;
            {
              const go_i8399 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
              {
                const $t8250_i8400 = { $: "Nil" };
                $t8673 = go$apply$0_Array_lst_rev_List_Int(go_i8399, acc, $t8250_i8400);
              }
            }
            return { _0: $t8673, _1: ys };
          }
        } else {
          switch (ys.$) {
            case "Nil": {
              {
                let $t8674;
                {
                  const go_i8396 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                  {
                    const $t8250_i8397 = { $: "Nil" };
                    $t8674 = go$apply$0_Array_lst_rev_List_Int(go_i8396, acc, $t8250_i8397);
                  }
                }
                {
                  const $t8675 = { $: "Nil" };
                  return { _0: $t8674, _1: $t8675 };
                }
              }
              break;
            }
            case "Cons": {
              const $f8678 = ys._0;
              const $f8679 = ys._1;
              {
                const t = $f8679;
                {
                  const h = $f8678;
                  {
                    const $t8676 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
                    {
                      const $t8677 = { $: "Cons", _0: h, _1: acc };
                      {
                        $tco_a0 = $clo;
                        $tco_a1 = t;
                        $tco_a2 = $t8676;
                        $tco_a3 = $t8677;
                        continue __tco;
                      }
                    }
                  }
                }
              }
              break;
            }
            default: {
              return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
            }
          }
        }
      }
    }
    return undefined;
  }
}
const go$apply$0_Array_lst_split_List_Int_Int$clo = { _0: ($_, $clo, ys, i, acc) => go$apply$0_Array_lst_split_List_Int_Int($clo, ys, i, acc) };

function go$apply$0_Array_lst_len_List_Int($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const $clo = $tco_a0;
    const xs = $tco_a1;
    const acc = $tco_a2;
    {
      const go = $clo;
      switch (xs.$) {
        case "Nil": {
          return acc;
          break;
        }
        case "Cons": {
          const $f8284 = xs._0;
          const $f8285 = xs._1;
          {
            const t = $f8285;
            {
              const $t8283 = ((acc + 1) < 4611686018427387904 && (acc + 1) >= -4611686018427387904 ? (acc + 1) : march_int_ovf((acc + 1), 0));
              {
                $tco_a0 = $clo;
                $tco_a1 = t;
                $tco_a2 = $t8283;
                continue __tco;
              }
            }
          }
          break;
        }
        default: {
          return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
        }
      }
    }
    return undefined;
  }
}
const go$apply$0_Array_lst_len_List_Int$clo = { _0: ($_, $clo, xs, acc) => go$apply$0_Array_lst_len_List_Int($clo, xs, acc) };

function rev_onto$apply$0_Array_lst_set_List_Int_Int_Int($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const $clo = $tco_a0;
    const rev_xs = $tco_a1;
    const ys = $tco_a2;
    {
      const rev_onto = $clo;
      switch (rev_xs.$) {
        case "Nil": {
          return ys;
          break;
        }
        case "Cons": {
          const $f8260 = rev_xs._0;
          const $f8261 = rev_xs._1;
          {
            const rest = $f8261;
            {
              const a = $f8260;
              {
                const $t8259 = { $: "Cons", _0: a, _1: ys };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = rest;
                  $tco_a2 = $t8259;
                  continue __tco;
                }
              }
            }
          }
          break;
        }
        default: {
          return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
        }
      }
    }
    return undefined;
  }
}
const rev_onto$apply$0_Array_lst_set_List_Int_Int_Int$clo = { _0: ($_, $clo, rev_xs, ys) => rev_onto$apply$0_Array_lst_set_List_Int_Int_Int($clo, rev_xs, ys) };

function go$apply$1_Array_lst_set_List_Int_Int_Int($tco_a0, $tco_a1, $tco_a2, $tco_a3) {
  __tco: for (;;) {
    const $clo = $tco_a0;
    const xs = $tco_a1;
    const i = $tco_a2;
    const acc = $tco_a3;
    {
      let go;
      go = $clo;
      {
        const rev_onto = $clo._1;
        {
          const v = $clo._2;
          {
            const $t8266 = (i === 0);
            if ($t8266 === true) {
              switch (xs.$) {
                case "Nil": {
                  {
                    const go_i8405 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                    {
                      const $t8250_i8406 = { $: "Nil" };
                      return go$apply$0_Array_lst_rev_List_Int(go_i8405, acc, $t8250_i8406);
                    }
                  }
                  break;
                }
                case "Cons": {
                  const $f8268 = xs._0;
                  const $f8269 = xs._1;
                  {
                    const t = $f8269;
                    {
                      const $t8267 = { $: "Cons", _0: v, _1: t };
                      return rev_onto._0(rev_onto, acc, $t8267);
                    }
                  }
                  break;
                }
                default: {
                  return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
                }
              }
            } else {
              switch (xs.$) {
                case "Nil": {
                  {
                    const go_i8402 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                    {
                      const $t8250_i8403 = { $: "Nil" };
                      return go$apply$0_Array_lst_rev_List_Int(go_i8402, acc, $t8250_i8403);
                    }
                  }
                  break;
                }
                case "Cons": {
                  const $f8276 = xs._0;
                  const $f8277 = xs._1;
                  {
                    const t = $f8277;
                    {
                      const h = $f8276;
                      {
                        const $t8274 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
                        {
                          const $t8275 = { $: "Cons", _0: h, _1: acc };
                          {
                            $tco_a0 = go;
                            $tco_a1 = t;
                            $tco_a2 = $t8274;
                            $tco_a3 = $t8275;
                            continue __tco;
                          }
                        }
                      }
                    }
                  }
                  break;
                }
                default: {
                  return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
                }
              }
            }
          }
        }
      }
    }
    return undefined;
  }
}
const go$apply$1_Array_lst_set_List_Int_Int_Int$clo = { _0: ($_, $clo, xs, i, acc) => go$apply$1_Array_lst_set_List_Int_Int_Int($clo, xs, i, acc) };

function go$apply$0_Array_lst_rev_List_Int($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const $clo = $tco_a0;
    const xs = $tco_a1;
    const acc = $tco_a2;
    {
      const go = $clo;
      switch (xs.$) {
        case "Nil": {
          return acc;
          break;
        }
        case "Cons": {
          const $f8244 = xs._0;
          const $f8245 = xs._1;
          {
            const t = $f8245;
            {
              const h = $f8244;
              {
                const $t8243 = { $: "Cons", _0: h, _1: acc };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = t;
                  $tco_a2 = $t8243;
                  continue __tco;
                }
              }
            }
          }
          break;
        }
        default: {
          return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
        }
      }
    }
    return undefined;
  }
}
const go$apply$0_Array_lst_rev_List_Int$clo = { _0: ($_, $clo, xs, acc) => go$apply$0_Array_lst_rev_List_Int($clo, xs, acc) };

function go$apply$0_Array_fold_left_PVec_Int_List_Int_Fn_List_Int_Int_List_Int($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const $clo = $tco_a0;
    const a = $tco_a1;
    const xs = $tco_a2;
    {
      let go;
      go = $clo;
      {
        const f = $clo._1;
        switch (xs.$) {
          case "Nil": {
            return a;
            break;
          }
          case "Cons": {
            const $f8643 = xs._0;
            const $f8644 = xs._1;
            {
              const rest = $f8644;
              {
                const x = $f8643;
                {
                  let $t8642;
                  $t8642 = f._0(f, a, x);
                  {
                    $tco_a0 = go;
                    $tco_a1 = $t8642;
                    $tco_a2 = rest;
                    continue __tco;
                  }
                }
              }
            }
            break;
          }
          default: {
            return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          }
        }
      }
    }
    return undefined;
  }
}
const go$apply$0_Array_fold_left_PVec_Int_List_Int_Fn_List_Int_Int_List_Int$clo = { _0: ($_, $clo, a, xs) => go$apply$0_Array_fold_left_PVec_Int_List_Int_Fn_List_Int_Int_List_Int($clo, a, xs) };

function go$apply$0_Array_lst_rev_List_TrieNode_Int($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const $clo = $tco_a0;
    const xs = $tco_a1;
    const acc = $tco_a2;
    {
      const go = $clo;
      switch (xs.$) {
        case "Nil": {
          return acc;
          break;
        }
        case "Cons": {
          const $f8244 = xs._0;
          const $f8245 = xs._1;
          {
            const t = $f8245;
            {
              const h = $f8244;
              {
                const $t8243 = { $: "Cons", _0: h, _1: acc };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = t;
                  $tco_a2 = $t8243;
                  continue __tco;
                }
              }
            }
          }
          break;
        }
        default: {
          return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
        }
      }
    }
    return undefined;
  }
}
const go$apply$0_Array_lst_rev_List_TrieNode_Int$clo = { _0: ($_, $clo, xs, acc) => go$apply$0_Array_lst_rev_List_TrieNode_Int($clo, xs, acc) };

function go$apply$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const $clo = $tco_a0;
    const a = $tco_a1;
    const vs = $tco_a2;
    {
      let go;
      go = $clo;
      {
        const f = $clo._1;
        switch (vs.$) {
          case "Nil": {
            return a;
            break;
          }
          case "Cons": {
            const $f8441 = vs._0;
            const $f8442 = vs._1;
            {
              const rest = $f8442;
              {
                const v = $f8441;
                {
                  let $t8440;
                  $t8440 = f._0(f, a, v);
                  {
                    $tco_a0 = go;
                    $tco_a1 = $t8440;
                    $tco_a2 = rest;
                    continue __tco;
                  }
                }
              }
            }
            break;
          }
          default: {
            return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          }
        }
      }
    }
    return undefined;
  }
}
const go$apply$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int$clo = { _0: ($_, $clo, a, vs) => go$apply$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int($clo, a, vs) };

function go$apply$1_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const $clo = $tco_a0;
    const a = $tco_a1;
    const cs = $tco_a2;
    {
      let go;
      go = $clo;
      {
        const f = $clo._1;
        switch (cs.$) {
          case "Nil": {
            return a;
            break;
          }
          case "Cons": {
            const $f8448 = cs._0;
            const $f8449 = cs._1;
            {
              const rest = $f8449;
              {
                const child = $f8448;
                {
                  let $t8447;
                  $t8447 = Array$trie_fold$List_Int$TrieNode_Int$Fn_List_Int_Int_List_Int(a, child, f);
                  {
                    $tco_a0 = go;
                    $tco_a1 = $t8447;
                    $tco_a2 = rest;
                    continue __tco;
                  }
                }
              }
            }
            break;
          }
          default: {
            return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          }
        }
      }
    }
    return undefined;
  }
}
const go$apply$1_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int$clo = { _0: ($_, $clo, a, cs) => go$apply$1_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int($clo, a, cs) };

function rev_onto$apply$0_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const $clo = $tco_a0;
    const rev_xs = $tco_a1;
    const ys = $tco_a2;
    {
      const rev_onto = $clo;
      switch (rev_xs.$) {
        case "Nil": {
          return ys;
          break;
        }
        case "Cons": {
          const $f8326 = rev_xs._0;
          const $f8327 = rev_xs._1;
          {
            const rest = $f8327;
            {
              const a = $f8326;
              {
                const $t8325 = { $: "Cons", _0: a, _1: ys };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = rest;
                  $tco_a2 = $t8325;
                  continue __tco;
                }
              }
            }
          }
          break;
        }
        default: {
          return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
        }
      }
    }
    return undefined;
  }
}
const rev_onto$apply$0_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int$clo = { _0: ($_, $clo, rev_xs, ys) => rev_onto$apply$0_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int($clo, rev_xs, ys) };

function go$apply$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int($tco_a0, $tco_a1, $tco_a2, $tco_a3) {
  __tco: for (;;) {
    const $clo = $tco_a0;
    const xs = $tco_a1;
    const i = $tco_a2;
    const acc = $tco_a3;
    {
      let go;
      go = $clo;
      {
        const node = $clo._1;
        {
          const rev_onto = $clo._2;
          switch (xs.$) {
            case "Nil": {
              {
                const go_i8818 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                {
                  const $t8250_i8819 = { $: "Nil" };
                  return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i8818, acc, $t8250_i8819);
                }
              }
              break;
            }
            case "Cons": {
              const $f8336 = xs._0;
              const $f8337 = xs._1;
              {
                const t = $f8337;
                {
                  const h = $f8336;
                  {
                    const $t8332 = (i === 0);
                    if ($t8332 === true) {
                      {
                        let $t8333;
                        $t8333 = { $: "Cons", _0: node, _1: t };
                        return rev_onto._0(rev_onto, acc, $t8333);
                      }
                    } else {
                      {
                        const $t8334 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
                        {
                          const $t8335 = { $: "Cons", _0: h, _1: acc };
                          {
                            $tco_a0 = go;
                            $tco_a1 = t;
                            $tco_a2 = $t8334;
                            $tco_a3 = $t8335;
                            continue __tco;
                          }
                        }
                      }
                    }
                  }
                }
              }
              break;
            }
            default: {
              return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
            }
          }
        }
      }
    }
    return undefined;
  }
}
const go$apply$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int$clo = { _0: ($_, $clo, xs, i, acc) => go$apply$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int($clo, xs, i, acc) };

export { main };
main();
//# sourceMappingURL=tetris.mjs.map
