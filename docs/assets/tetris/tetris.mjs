import { march_float_round, march_float_to_string, march_int_and, march_int_div, march_int_div_euclid, march_int_mod, march_int_mod_euclid, march_int_not, march_int_or, march_int_popcount, march_int_shl, march_int_shr, march_int_xor, march_string_byte_length, march_string_concat_n, march_string_join, march_string_split, march_string_to_int, march_unix_time, march_unix_time_ms } from "./march_runtime.mjs";

import { march_dom_set_timeout as dom_set_timeout, march_dom_prevent_default as dom_prevent_default, march_dom_event_key as dom_event_key, march_dom_add_event_listener as dom_add_event_listener, march_dom_set_style as dom_set_style, march_dom_class_add as dom_class_add, march_dom_set_attribute as dom_set_attribute, march_dom_get_attribute as dom_get_attribute, march_dom_set_text as dom_set_text, march_dom_append_child as dom_append_child, march_dom_create_element as dom_create_element, march_dom_body as dom_body, march_dom_get_element_by_id as dom_get_element_by_id } from "./march_dom.mjs";


const int_to_string   = { _0: ($_, x) => String(x) };
const bool_to_string  = { _0: ($_, x) => String(x) };
const int_to_float    = { _0: ($_, x) => x };
const float_to_int    = { _0: ($_, x) => Math.trunc(x) };
const float_truncate  = { _0: ($_, x) => Math.trunc(x) };
const string_is_empty = { _0: ($_, x) => x === "" };
const not_bool        = { _0: ($_, x) => !x };
const negate_int      = { _0: ($_, x) => -x };
const negate_float    = { _0: ($_, x) => -x };
const float_abs       = { _0: ($_, x) => Math.abs(x) };
const float_floor     = { _0: ($_, x) => Math.floor(x) };
const float_ceil      = { _0: ($_, x) => Math.ceil(x) };
const float_to_string    = { _0: ($_, x) => march_float_to_string(x) };
const string_length      = { _0: ($_, x) => march_string_byte_length(x) };
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
const int_not = { _0: ($_, a) => march_int_not(a) };
const int_popcount = { _0: ($_, a) => march_int_popcount(a) };
const int_abs     = { _0: ($_, a) => Math.abs(a) };
const unix_time   = { _0: ($_) => march_unix_time() };
const unix_time_ms = { _0: ($_) => march_unix_time_ms() };
const float_round = { _0: ($_, a) => march_float_round(a) };
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
    const $rc_2293 = dom_get_element_by_id$clo._0(dom_get_element_by_id$clo, id);
    return $rc_2293;
  }
}
const Js$Dom$find$clo = { _0: ($_, id) => Js$Dom$find(id) };

function Js$Dom$create(tag) {
  {
    const $rc_2296 = dom_create_element$clo._0(dom_create_element$clo, tag);
    return $rc_2296;
  }
}
const Js$Dom$create$clo = { _0: ($_, tag) => Js$Dom$create(tag) };

function Js$Dom$append(parent, child) {
  {
    const $rc_2299 = dom_append_child$clo._0(dom_append_child$clo, parent, child);
    return $rc_2299;
  }
}
const Js$Dom$append$clo = { _0: ($_, parent, child) => Js$Dom$append(parent, child) };

function Js$Dom$get_attr(el, name) {
  {
    const $rc_2312 = dom_get_attribute$clo._0(dom_get_attribute$clo, el, name);
    return $rc_2312;
  }
}
const Js$Dom$get_attr$clo = { _0: ($_, el, name) => Js$Dom$get_attr(el, name) };

function Js$Dom$set_attr(el, name, val) {
  {
    const $rc_2313 = dom_set_attribute$clo._0(dom_set_attribute$clo, el, name, val);
    return $rc_2313;
  }
}
const Js$Dom$set_attr$clo = { _0: ($_, el, name, val) => Js$Dom$set_attr(el, name, val) };

function Js$Dom$add_class(el, cls) {
  {
    const $rc_2316 = dom_class_add$clo._0(dom_class_add$clo, el, cls);
    return $rc_2316;
  }
}
const Js$Dom$add_class$clo = { _0: ($_, el, cls) => Js$Dom$add_class(el, cls) };

function Js$Dom$set_style(el, prop, val) {
  {
    const $rc_2320 = dom_set_style$clo._0(dom_set_style$clo, el, prop, val);
    return $rc_2320;
  }
}
const Js$Dom$set_style$clo = { _0: ($_, el, prop, val) => Js$Dom$set_style(el, prop, val) };

function Js$Dom$listen(el, event, handler) {
  {
    const $rc_2324 = dom_add_event_listener$clo._0(dom_add_event_listener$clo, el, event, handler);
    return $rc_2324;
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
        const $t44535 = { _0: 0, _1: 1 };
        {
          const $t44536 = { _0: 1, _1: 1 };
          {
            const $t44537 = { _0: 2, _1: 1 };
            {
              const $t44538 = { _0: 3, _1: 1 };
              {
                const $t44539 = { $: "Nil" };
                {
                  const $t44540 = { $: "Cons", _0: $t44538, _1: $t44539 };
                  {
                    const $t44541 = { $: "Cons", _0: $t44537, _1: $t44540 };
                    {
                      const $t44542 = { $: "Cons", _0: $t44536, _1: $t44541 };
                      return { $: "Cons", _0: $t44535, _1: $t44542 };
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
        const $t44543 = { _0: 1, _1: 1 };
        {
          const $t44544 = { _0: 2, _1: 1 };
          {
            const $t44545 = { _0: 1, _1: 2 };
            {
              const $t44546 = { _0: 2, _1: 2 };
              {
                const $t44547 = { $: "Nil" };
                {
                  const $t44548 = { $: "Cons", _0: $t44546, _1: $t44547 };
                  {
                    const $t44549 = { $: "Cons", _0: $t44545, _1: $t44548 };
                    {
                      const $t44550 = { $: "Cons", _0: $t44544, _1: $t44549 };
                      return { $: "Cons", _0: $t44543, _1: $t44550 };
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
        const $t44551 = { _0: 1, _1: 1 };
        {
          const $t44552 = { _0: 0, _1: 2 };
          {
            const $t44553 = { _0: 1, _1: 2 };
            {
              const $t44554 = { _0: 2, _1: 2 };
              {
                const $t44555 = { $: "Nil" };
                {
                  const $t44556 = { $: "Cons", _0: $t44554, _1: $t44555 };
                  {
                    const $t44557 = { $: "Cons", _0: $t44553, _1: $t44556 };
                    {
                      const $t44558 = { $: "Cons", _0: $t44552, _1: $t44557 };
                      return { $: "Cons", _0: $t44551, _1: $t44558 };
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
        const $t44559 = { _0: 1, _1: 1 };
        {
          const $t44560 = { _0: 2, _1: 1 };
          {
            const $t44561 = { _0: 0, _1: 2 };
            {
              const $t44562 = { _0: 1, _1: 2 };
              {
                const $t44563 = { $: "Nil" };
                {
                  const $t44564 = { $: "Cons", _0: $t44562, _1: $t44563 };
                  {
                    const $t44565 = { $: "Cons", _0: $t44561, _1: $t44564 };
                    {
                      const $t44566 = { $: "Cons", _0: $t44560, _1: $t44565 };
                      return { $: "Cons", _0: $t44559, _1: $t44566 };
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
        const $t44567 = { _0: 0, _1: 1 };
        {
          const $t44568 = { _0: 1, _1: 1 };
          {
            const $t44569 = { _0: 1, _1: 2 };
            {
              const $t44570 = { _0: 2, _1: 2 };
              {
                const $t44571 = { $: "Nil" };
                {
                  const $t44572 = { $: "Cons", _0: $t44570, _1: $t44571 };
                  {
                    const $t44573 = { $: "Cons", _0: $t44569, _1: $t44572 };
                    {
                      const $t44574 = { $: "Cons", _0: $t44568, _1: $t44573 };
                      return { $: "Cons", _0: $t44567, _1: $t44574 };
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
        const $t44575 = { _0: 0, _1: 1 };
        {
          const $t44576 = { _0: 0, _1: 2 };
          {
            const $t44577 = { _0: 1, _1: 2 };
            {
              const $t44578 = { _0: 2, _1: 2 };
              {
                const $t44579 = { $: "Nil" };
                {
                  const $t44580 = { $: "Cons", _0: $t44578, _1: $t44579 };
                  {
                    const $t44581 = { $: "Cons", _0: $t44577, _1: $t44580 };
                    {
                      const $t44582 = { $: "Cons", _0: $t44576, _1: $t44581 };
                      return { $: "Cons", _0: $t44575, _1: $t44582 };
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
        const $t44583 = { _0: 2, _1: 1 };
        {
          const $t44584 = { _0: 0, _1: 2 };
          {
            const $t44585 = { _0: 1, _1: 2 };
            {
              const $t44586 = { _0: 2, _1: 2 };
              {
                const $t44587 = { $: "Nil" };
                {
                  const $t44588 = { $: "Cons", _0: $t44586, _1: $t44587 };
                  {
                    const $t44589 = { $: "Cons", _0: $t44585, _1: $t44588 };
                    {
                      const $t44590 = { $: "Cons", _0: $t44584, _1: $t44589 };
                      return { $: "Cons", _0: $t44583, _1: $t44590 };
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
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const TetrisLogic$piece_cells$clo = { _0: ($_, p) => TetrisLogic$piece_cells(p) };

function TetrisLogic$level_for_lines(total_lines) {
  return ((total_lines - total_lines % 10) / 10);
}
const TetrisLogic$level_for_lines$clo = { _0: ($_, total_lines) => TetrisLogic$level_for_lines(total_lines) };

function TetrisLogic$rotate_cell(c) {
  const $f44600 = c._0;
  const $f44601 = c._1;
  {
    const y = $f44601;
    {
      const x = $f44600;
      {
        const $t44599 = (3 - y);
        return { _0: $t44599, _1: x };
      }
    }
  }
  return (() => { throw new Error("non-exhaustive pattern match"); })();
}
const TetrisLogic$rotate_cell$clo = { _0: ($_, c) => TetrisLogic$rotate_cell(c) };

function TetrisLogic$clear_lines(board) {
  {
    const rows = (() => {
      {
        const go_i5216 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
        {
          const $t659_i5218 = { $: "Nil" };
          return go$apply$0_List_range(go_i5216, 19, $t659_i5218);
        }
      }
    })();
    {
      const $t44649 = (() => {
        return { $: "$Clo_$lam0_TetrisLogic_clear_lines$0_TetrisLogic_clear_lines", _0: $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines, _1: board };
      })();
      {
        const kept_rows = List$filter$List_Int$Fn_Int_Bool(rows, $t44649);
        {
          const cleared = (() => {
            {
              const $t44651 = (() => {
                {
                  const go_i5213 = { $: "$Clo_go$0_List_length_List_Int", _0: go$apply$0_List_length_List_Int };
                  return go$apply$0_List_length_List_Int(go_i5213, kept_rows, 0);
                }
              })();
              return (20 - $t44651);
            }
          })();
          {
            const $t44653 = { $: "$Clo_$lam1_TetrisLogic_clear_lines$1_TetrisLogic_clear_lines", _0: $lam1_TetrisLogic_clear_lines$apply$1_TetrisLogic_clear_lines, _1: board };
            {
              const kept_cells = (() => {
                {
                  const f_i5210 = $t44653;
                  {
                    const $t750_i5211 = { $: "Nil" };
                    return List$flat_map_go$List_Int$List_Int$Fn_Int_List_Int($t750_i5211, kept_rows, f_i5210);
                  }
                }
              })();
              {
                const $t44655 = (cleared * 10);
                {
                  const blank_cells = (() => {
                    {
                      const go_i5207 = { $: "$Clo_go$0_List_repeat_Int_Int", _0: go$apply$0_List_repeat_Int_Int, _1: 0 };
                      {
                        const $t654_i5208 = { $: "Nil" };
                        return go$apply$0_List_repeat_Int_Int(go_i5207, $t44655, $t654_i5208);
                      }
                    }
                  })();
                  {
                    const new_board = (() => {
                      {
                        const $t44656 = (() => {
                          {
                            const xs_i13471 = blank_cells;
                            {
                              const ys_i13472 = kept_cells;
                              switch (xs_i13471.$) {
                                case "Nil": {
                                  return kept_cells;
                                  break;
                                }
                                case "Cons": {
                                  const $f729_i13473 = xs_i13471._0;
                                  const $f730_i13474 = xs_i13471._1;
                                  {
                                    const t_i13475 = $f730_i13474;
                                    {
                                      const h_i13476 = $f729_i13473;
                                      {
                                        const $trmc7_i13477 = { $: "Cons", _0: h_i13476, _1: null };
                                        List$append$dps$List_Int$List_Int$List_Int(t_i13475, kept_cells, $trmc7_i13477);
                                        return $trmc7_i13477;
                                      }
                                    }
                                  }
                                  break;
                                }
                                default: {
                                  return (() => { throw new Error("non-exhaustive pattern match"); })();
                                }
                              }
                            }
                          }
                        })();
                        return Array$from_list$List_Int($t44656);
                      }
                    })();
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
    const $t44658 = { $: "$Clo_$lam0_int_list_to_string$0_int_list_to_string", _0: $lam0_int_list_to_string$apply$0_int_list_to_string };
    {
      const $t44659 = (() => {
        {
          const xs_i13478 = xs;
          {
            const f_i13479 = $t44658;
            switch (xs_i13478.$) {
              case "Nil": {
                return { $: "Nil" };
                break;
              }
              case "Cons": {
                const $f737_i13480 = xs_i13478._0;
                const $f738_i13481 = xs_i13478._1;
                {
                  const t_i13482 = $f738_i13481;
                  {
                    const h_i13483 = $f737_i13480;
                    {
                      const $t735_i13484 = (() => {
                        return f_i13479._0(f_i13479, h_i13483);
                      })();
                      {
                        const $trmc11_i13485 = { $: "Cons", _0: $t735_i13484, _1: null };
                        List$map$dps$List_Int$Fn_Int_String$List_String(t_i13482, f_i13479, $trmc11_i13485);
                        return $trmc11_i13485;
                      }
                    }
                  }
                }
                break;
              }
              default: {
                return (() => { throw new Error("non-exhaustive pattern match"); })();
              }
            }
          }
        }
      })();
      {
        const $rc_2375 = march_string_join($t44659, ",");
        return $rc_2375;
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
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const piece_to_string$clo = { _0: ($_, p) => piece_to_string(p) };

function next_piece(rng) {
  {
    const $t44682 = { $: "I" };
    {
      const $t44683 = { $: "O" };
      {
        const $t44684 = { $: "T" };
        {
          const $t44685 = { $: "S" };
          {
            const $t44686 = { $: "Z" };
            {
              const $t44687 = { $: "J" };
              {
                const $t44688 = { $: "L" };
                {
                  const $t44689 = { $: "Nil" };
                  {
                    const $t44690 = { $: "Cons", _0: $t44688, _1: $t44689 };
                    {
                      const $t44691 = { $: "Cons", _0: $t44687, _1: $t44690 };
                      {
                        const $t44692 = { $: "Cons", _0: $t44686, _1: $t44691 };
                        {
                          const $t44693 = { $: "Cons", _0: $t44685, _1: $t44692 };
                          {
                            const $t44694 = { $: "Cons", _0: $t44684, _1: $t44693 };
                            {
                              const $t44695 = { $: "Cons", _0: $t44683, _1: $t44694 };
                              {
                                const pieces = { $: "Cons", _0: $t44682, _1: $t44695 };
                                {
                                  const rng2 = (() => {
                                    {
                                      const $t44664_i12249 = (rng * 16807);
                                      return ($t44664_i12249 % 2147483647);
                                    }
                                  })();
                                  {
                                    const idx = (rng2 % 7);
                                    {
                                      const result = (() => {
                                        {
                                          const $t44696 = List$nth$List_Piece$Int(pieces, idx);
                                          return { _0: $t44696, _1: rng2 };
                                        }
                                      })();
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
    const $t44697 = Js$Dom$find("game-state");
    switch ($t44697.$) {
      case "Some": {
        const $f44698 = $t44697._0;
        {
          const el = $f44698;
          return el;
        }
        break;
      }
      case "None": {
        undefined;
        return (() => { throw new Error("Tetris: #game-state element missing"); })();
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const state_el$clo = { _0: ($_) => state_el() };

function get_int_attr(el, name, _default) {
  {
    const $t44699 = Js$Dom$get_attr(el, name);
    switch ($t44699.$) {
      case "Some": {
        const $f44701 = $t44699._0;
        {
          const s = $f44701;
          {
            const $t44700 = (() => {
              {
                const $rc_2377 = march_string_to_int(s);
                return $rc_2377;
              }
            })();
            {
              const $rc_2376 = Option$unwrap_or$Option_Int$Int($t44700, _default);
              return $rc_2376;
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
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const get_int_attr$clo = { _0: ($_, el, name, _default) => get_int_attr(el, name, _default) };

function get_str_attr(el, name, _default) {
  {
    const $t44702 = Js$Dom$get_attr(el, name);
    switch ($t44702.$) {
      case "Some": {
        const $f44703 = $t44702._0;
        {
          const s = $f44703;
          return s;
        }
        break;
      }
      case "None": {
        return _default;
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const get_str_attr$clo = { _0: ($_, el, name, _default) => get_str_attr(el, name, _default) };

function rotate_n(cells, n) {
  if (n === 0) {
    return cells;
  } else {
    return (() => {
      {
        const $t44704 = (() => {
          {
            const xs_i13486 = cells;
            {
              const f_i13487 = TetrisLogic$rotate_cell$clo;
              switch (xs_i13486.$) {
                case "Nil": {
                  return { $: "Nil" };
                  break;
                }
                case "Cons": {
                  const $f737_i13488 = xs_i13486._0;
                  const $f738_i13489 = xs_i13486._1;
                  {
                    const t_i13490 = $f738_i13489;
                    {
                      const h_i13491 = $f737_i13488;
                      {
                        const $t735_i13492 = (() => {
                          return f_i13487._0(f_i13487, h_i13491);
                        })();
                        {
                          const $trmc11_i13493 = { $: "Cons", _0: $t735_i13492, _1: null };
                          List$map$dps$List_T_Int_Int$Fn_T_Int_Int_T_Int_Int$List_T_Int_Int(t_i13490, f_i13487, $trmc11_i13493);
                          return $trmc11_i13493;
                        }
                      }
                    }
                  }
                  break;
                }
                default: {
                  return (() => { throw new Error("non-exhaustive pattern match"); })();
                }
              }
            }
          }
        })();
        {
          const $t44705 = (n - 1);
          return rotate_n($t44704, $t44705);
        }
      }
    })();
  }
}
const rotate_n$clo = { _0: ($_, cells, n) => rotate_n(cells, n) };

function spawn_piece(next, board, rng) {
  {
    const cells = TetrisLogic$piece_cells(next);
    {
      const over = (() => {
        {
          const $t44624_i5228 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: 3, _3: 0 };
          return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t44624_i5228);
        }
      })();
      {
        const $t44708 = next_piece(rng);
        const $f44709 = $t44708._0;
        const $f44710 = $t44708._1;
        {
          const rng2 = $f44710;
          {
            const next2 = $f44709;
            return { _0: next, _1: 0, _2: 3, _3: 0, _4: next2, _5: rng2, _6: over };
          }
        }
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const spawn_piece$clo = { _0: ($_, next, board, rng) => spawn_piece(next, board, rng) };

function set_text_if_found(id, text) {
  {
    const $t44751 = Js$Dom$find(id);
    switch ($t44751.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f44752 = $t44751._0;
        {
          const el = $f44752;
          {
            const el_i12250 = el;
            {
              const text_i12251 = text;
              {
                const $rc_2309_i12252 = dom_set_text$clo._0(dom_set_text$clo, el, text);
                return $rc_2309_i12252;
              }
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const set_text_if_found$clo = { _0: ($_, id, text) => set_text_if_found(id, text) };

function with_state(f) {
  {
    const el = state_el();
    {
      const over = (() => {
        {
          const $t44753 = (() => {
            return get_str_attr(el, "data-over", "false");
          })();
          {
            const $rc_2386 = ($t44753 === "true");
            return $rc_2386;
          }
        }
      })();
      if (over === true) {
        return (() => {
          return {  };
        })();
      } else if (over === false) {
        return (() => {
          {
            const board = (() => {
              {
                const $t44754 = (() => {
                  return get_str_attr(el, "data-board", "");
                })();
                {
                  const $t44755 = (() => {
                    {
                      const $rc_2385 = (() => {
                        {
                          const $t44660_i5258 = march_string_split($t44754, ",");
                          {
                            const $t44663_i5259 = { $: "$Clo_$lam0_string_to_int_list$0_string_to_int_list", _0: $lam0_string_to_int_list$apply$0_string_to_int_list };
                            return List$map$List_String$Fn_String_Int($t44660_i5258, $t44663_i5259);
                          }
                        }
                      })();
                      return $rc_2385;
                    }
                  })();
                  return Array$from_list$List_Int($t44755);
                }
              }
            })();
            {
              const piece = (() => {
                {
                  const $t44756 = (() => {
                    return get_str_attr(el, "data-piece", "I");
                  })();
                  {
                    let $rc_2384;
                    if ($t44756 === "I") {
                      $rc_2384 = { $: "I" };
                    } else if ($t44756 === "O") {
                      $rc_2384 = { $: "O" };
                    } else if ($t44756 === "T") {
                      $rc_2384 = { $: "T" };
                    } else if ($t44756 === "S") {
                      $rc_2384 = { $: "S" };
                    } else if ($t44756 === "Z") {
                      $rc_2384 = { $: "Z" };
                    } else if ($t44756 === "J") {
                      $rc_2384 = { $: "J" };
                    } else {
                      $rc_2384 = { $: "L" };
                    }
                    return $rc_2384;
                  }
                }
              })();
              {
                const rot = (() => {
                  return get_int_attr(el, "data-rot", 0);
                })();
                {
                  const x = (() => {
                    return get_int_attr(el, "data-x", 3);
                  })();
                  {
                    const y = (() => {
                      return get_int_attr(el, "data-y", 0);
                    })();
                    {
                      const next = (() => {
                        {
                          const $t44757 = (() => {
                            return get_str_attr(el, "data-next", "O");
                          })();
                          {
                            let $rc_2383;
                            if ($t44757 === "I") {
                              $rc_2383 = { $: "I" };
                            } else if ($t44757 === "O") {
                              $rc_2383 = { $: "O" };
                            } else if ($t44757 === "T") {
                              $rc_2383 = { $: "T" };
                            } else if ($t44757 === "S") {
                              $rc_2383 = { $: "S" };
                            } else if ($t44757 === "Z") {
                              $rc_2383 = { $: "Z" };
                            } else if ($t44757 === "J") {
                              $rc_2383 = { $: "J" };
                            } else {
                              $rc_2383 = { $: "L" };
                            }
                            return $rc_2383;
                          }
                        }
                      })();
                      {
                        const score = (() => {
                          return get_int_attr(el, "data-score", 0);
                        })();
                        {
                          const lines = (() => {
                            return get_int_attr(el, "data-lines", 0);
                          })();
                          {
                            const rng = (() => {
                              return get_int_attr(el, "data-rng", 1);
                            })();
                            {
                              const seq = (() => {
                                return get_int_attr(el, "data-seq", 0);
                              })();
                              {
                                const $t44758 = f._0(f, board, piece, rot, x, y, next, score, lines, rng);
                                const $f44778 = $t44758._0;
                                const $f44779 = $t44758._1;
                                const $f44780 = $t44758._2;
                                const $f44781 = $t44758._3;
                                const $f44782 = $t44758._4;
                                const $f44783 = $t44758._5;
                                const $f44784 = $t44758._6;
                                const $f44785 = $t44758._7;
                                const $f44786 = $t44758._8;
                                const $f44787 = $t44758._9;
                                {
                                  const over2 = $f44787;
                                  {
                                    const rng2 = $f44786;
                                    {
                                      const lines2 = $f44785;
                                      {
                                        const score2 = $f44784;
                                        {
                                          const next2 = $f44783;
                                          {
                                            const y2 = $f44782;
                                            {
                                              const x2 = $f44781;
                                              {
                                                const rot2 = $f44780;
                                                {
                                                  const piece2 = $f44779;
                                                  {
                                                    const board2 = $f44778;
                                                    (() => {
                                                      {
                                                        const $t44716_i5253 = (() => {
                                                          {
                                                            const go_i13414 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                                                            {
                                                              const $t659_i13416 = { $: "Nil" };
                                                              return go$apply$0_List_range(go_i13414, 19, $t659_i13416);
                                                            }
                                                          }
                                                        })();
                                                        {
                                                          const $t44728_i5254 = { $: "$Clo_$lam0_render_board$0_render_board", _0: $lam0_render_board$apply$0_render_board, _1: board2 };
                                                          {
                                                            const f_i13410 = $t44728_i5254;
                                                            {
                                                              const go_i13411 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i13410 };
                                                              return go$apply$0_List_each_List_Int_Fn_Int_T_(go_i13411, $t44716_i5253);
                                                            }
                                                          }
                                                        }
                                                      }
                                                    })();
                                                    (() => {
                                                      if (over2 === false) {
                                                        return (() => {
                                                          {
                                                            const base_cells_i5248 = TetrisLogic$piece_cells(piece2);
                                                            {
                                                              const rotated_i5249 = rotate_n(base_cells_i5248, rot2);
                                                              {
                                                                const $t44750_i5250 = { $: "$Clo_$lam0_render_falling$0_render_falling", _0: $lam0_render_falling$apply$0_render_falling, _1: x2, _2: y2, _3: piece2 };
                                                                {
                                                                  const f_i13407 = $t44750_i5250;
                                                                  {
                                                                    const go_i13408 = { $: "$Clo_go$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_", _0: go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_, _1: f_i13407 };
                                                                    return go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_(go_i13408, rotated_i5249);
                                                                  }
                                                                }
                                                              }
                                                            }
                                                          }
                                                        })();
                                                      } else if (over2 === true) {
                                                        return {  };
                                                      } else {
                                                        return (() => { throw new Error("non-exhaustive pattern match"); })();
                                                      }
                                                    })();
                                                    (() => {
                                                      {
                                                        const $t44760 = (() => {
                                                          {
                                                            const $t44759 = String(score2);
                                                            {
                                                              const $rc_2382 = ("Score: " + $t44759);
                                                              return $rc_2382;
                                                            }
                                                          }
                                                        })();
                                                        return set_text_if_found("score", $t44760);
                                                      }
                                                    })();
                                                    (() => {
                                                      {
                                                        const $t44763 = (() => {
                                                          {
                                                            const $t44762 = (() => {
                                                              {
                                                                const $t44761 = TetrisLogic$level_for_lines(lines2);
                                                                return String($t44761);
                                                              }
                                                            })();
                                                            {
                                                              const $rc_2381 = ("Level: " + $t44762);
                                                              return $rc_2381;
                                                            }
                                                          }
                                                        })();
                                                        return set_text_if_found("level", $t44763);
                                                      }
                                                    })();
                                                    (() => {
                                                      {
                                                        const $t44765 = (() => {
                                                          {
                                                            const $t44764 = piece_to_string(next2);
                                                            {
                                                              const $rc_2380 = ("Next: " + $t44764);
                                                              return $rc_2380;
                                                            }
                                                          }
                                                        })();
                                                        return set_text_if_found("next", $t44765);
                                                      }
                                                    })();
                                                    {
                                                      let game_over_text;
                                                      if (over2 === true) {
                                                        game_over_text = "Game Over — press R to restart";
                                                      } else if (over2 === false) {
                                                        game_over_text = "";
                                                      } else {
                                                        game_over_text = (() => { throw new Error("non-exhaustive pattern match"); })();
                                                      }
                                                      set_text_if_found("game-over", game_over_text);
                                                      (() => {
                                                        {
                                                          const $t44767 = (() => {
                                                            {
                                                              const $t44766 = (() => {
                                                                {
                                                                  const $t8213_i5241 = { $: "Nil" };
                                                                  {
                                                                    const $t8215_i5242 = { $: "$Clo_$lam0_Array_to_list$0_Array_to_list_PVec_Int", _0: $lam0_Array_to_list$apply$0_Array_to_list_PVec_Int };
                                                                    {
                                                                      const rev_i5243 = Array$fold_left$PVec_Int$List_Int$Fn_List_Int_Int_List_Int(board2, $t8213_i5241, $t8215_i5242);
                                                                      {
                                                                        const go_i13404 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                                                                        {
                                                                          const $t7798_i13405 = { $: "Nil" };
                                                                          return go$apply$0_Array_lst_rev_List_Int(go_i13404, rev_i5243, $t7798_i13405);
                                                                        }
                                                                      }
                                                                    }
                                                                  }
                                                                }
                                                              })();
                                                              return int_list_to_string($t44766);
                                                            }
                                                          })();
                                                          return Js$Dom$set_attr(el, "data-board", $t44767);
                                                        }
                                                      })();
                                                      (() => {
                                                        {
                                                          const $t44768 = (() => {
                                                            {
                                                              const $rc_2379 = piece_to_string(piece2);
                                                              return $rc_2379;
                                                            }
                                                          })();
                                                          return Js$Dom$set_attr(el, "data-piece", $t44768);
                                                        }
                                                      })();
                                                      (() => {
                                                        {
                                                          const $t44769 = String(rot2);
                                                          return Js$Dom$set_attr(el, "data-rot", $t44769);
                                                        }
                                                      })();
                                                      (() => {
                                                        {
                                                          const $t44770 = String(x2);
                                                          return Js$Dom$set_attr(el, "data-x", $t44770);
                                                        }
                                                      })();
                                                      (() => {
                                                        {
                                                          const $t44771 = String(y2);
                                                          return Js$Dom$set_attr(el, "data-y", $t44771);
                                                        }
                                                      })();
                                                      (() => {
                                                        {
                                                          const $t44772 = (() => {
                                                            {
                                                              const $rc_2378 = piece_to_string(next2);
                                                              return $rc_2378;
                                                            }
                                                          })();
                                                          return Js$Dom$set_attr(el, "data-next", $t44772);
                                                        }
                                                      })();
                                                      (() => {
                                                        {
                                                          const $t44773 = String(score2);
                                                          return Js$Dom$set_attr(el, "data-score", $t44773);
                                                        }
                                                      })();
                                                      (() => {
                                                        {
                                                          const $t44774 = String(lines2);
                                                          return Js$Dom$set_attr(el, "data-lines", $t44774);
                                                        }
                                                      })();
                                                      (() => {
                                                        {
                                                          const $t44775 = String(rng2);
                                                          return Js$Dom$set_attr(el, "data-rng", $t44775);
                                                        }
                                                      })();
                                                      {
                                                        let over2_s;
                                                        if (over2 === true) {
                                                          over2_s = "true";
                                                        } else if (over2 === false) {
                                                          over2_s = "false";
                                                        } else {
                                                          over2_s = (() => { throw new Error("non-exhaustive pattern match"); })();
                                                        }
                                                        (() => {
                                                          return Js$Dom$set_attr(el, "data-over", over2_s);
                                                        })();
                                                        {
                                                          const $t44777 = (() => {
                                                            {
                                                              const $t44776 = (seq + 1);
                                                              return String($t44776);
                                                            }
                                                          })();
                                                          return Js$Dom$set_attr(el, "data-seq", $t44777);
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
                                return (() => { throw new Error("non-exhaustive pattern match"); })();
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
        })();
      } else {
        return (() => {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        })();
      }
    }
  }
}
const with_state$clo = { _0: ($_, f) => with_state(f) };

function lock_and_advance(board, piece, rot, x, y, next, score, lines, rng) {
  {
    const $t44824 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t44824, rot);
      {
        const locked = (() => {
          {
            let $t44825;
            switch (piece.$) {
              case "I": {
                $t44825 = 1;
                break;
              }
              case "O": {
                $t44825 = 2;
                break;
              }
              case "T": {
                $t44825 = 3;
                break;
              }
              case "S": {
                $t44825 = 4;
                break;
              }
              case "Z": {
                $t44825 = 5;
                break;
              }
              case "J": {
                $t44825 = 6;
                break;
              }
              case "L": {
                $t44825 = 7;
                break;
              }
              default: {
                $t44825 = (() => { throw new Error("non-exhaustive pattern match"); })();
                break;
              }
            }
            {
              const $t44634_i5266 = { $: "$Clo_$lam0_TetrisLogic_lock_piece$0_TetrisLogic_lock_piece", _0: $lam0_TetrisLogic_lock_piece$apply$0_TetrisLogic_lock_piece, _1: $t44825, _2: x, _3: y };
              return List$fold_left$List_T_Int_Int$PVec_Int$Fn_PVec_Int_T_Int_Int_PVec_Int(cells, board, $t44634_i5266);
            }
          }
        })();
        {
          const $t44826 = TetrisLogic$clear_lines(locked);
          const $f44860 = $t44826._0;
          const $f44861 = $t44826._1;
          {
            const n = $f44861;
            {
              const cleared_board = $f44860;
              {
                const new_score = (() => {
                  {
                    let $t44827;
                    if (n === 1) {
                      $t44827 = 100;
                    } else if (n === 2) {
                      $t44827 = 300;
                    } else if (n === 3) {
                      $t44827 = 500;
                    } else if (n === 4) {
                      $t44827 = 800;
                    } else {
                      $t44827 = 0;
                    }
                    return (score + $t44827);
                  }
                })();
                {
                  const new_lines = (lines + n);
                  {
                    const $t44828 = (() => {
                      return spawn_piece(next, cleared_board, rng);
                    })();
                    const $f44829 = $t44828._0;
                    const $f44830 = $t44828._1;
                    const $f44831 = $t44828._2;
                    const $f44832 = $t44828._3;
                    const $f44833 = $t44828._4;
                    const $f44834 = $t44828._5;
                    const $f44835 = $t44828._6;
                    {
                      const over = $f44835;
                      {
                        const rng2 = $f44834;
                        {
                          const next2 = $f44833;
                          {
                            const y2 = $f44832;
                            {
                              const x2 = $f44831;
                              {
                                const rot2 = $f44830;
                                {
                                  const piece2 = $f44829;
                                  return { _0: cleared_board, _1: piece2, _2: rot2, _3: x2, _4: y2, _5: next2, _6: new_score, _7: new_lines, _8: rng2, _9: over };
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                    return (() => { throw new Error("non-exhaustive pattern match"); })();
                  }
                }
              }
            }
          }
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const lock_and_advance$clo = { _0: ($_, board, piece, rot, x, y, next, score, lines, rng) => lock_and_advance(board, piece, rot, x, y, next, score, lines, rng) };

function is_paused() {
  {
    const $t44867 = (() => {
      {
        const $t44866 = state_el();
        return get_str_attr($t44866, "data-paused", "false");
      }
    })();
    {
      const $rc_2387 = ($t44867 === "true");
      return $rc_2387;
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
      paused_s = (() => { throw new Error("non-exhaustive pattern match"); })();
    }
    {
      let status_s;
      if (paused === true) {
        status_s = "Paused — press P to resume";
      } else if (paused === false) {
        status_s = "";
      } else {
        status_s = (() => { throw new Error("non-exhaustive pattern match"); })();
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
      const over = (() => {
        {
          const $t44868 = (() => {
            return get_str_attr(el, "data-over", "false");
          })();
          {
            const $rc_2388 = ($t44868 === "true");
            return $rc_2388;
          }
        }
      })();
      if (over === true) {
        return (() => {
          return {  };
        })();
      } else if (over === false) {
        return (() => {
          {
            const $t44870 = (() => {
              {
                const $t44869 = is_paused();
                return (!$t44869);
              }
            })();
            return set_paused(el, $t44870);
          }
        })();
      } else {
        return (() => {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        })();
      }
    }
  }
}
const toggle_pause$clo = { _0: ($_) => toggle_pause() };

function fall_from(board, cells, x, cur_y) {
  {
    const $t44897 = (() => {
      {
        const $t44896 = (cur_y + 1);
        {
          const $t44624_i5274 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: x, _3: $t44896 };
          return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t44624_i5274);
        }
      }
    })();
    if ($t44897 === true) {
      return (() => {
        return cur_y;
      })();
    } else if ($t44897 === false) {
      return (() => {
        {
          const $t44898 = (cur_y + 1);
          return fall_from(board, cells, x, $t44898);
        }
      })();
    } else {
      return (() => {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      })();
    }
  }
}
const fall_from$clo = { _0: ($_, board, cells, x, cur_y) => fall_from(board, cells, x, cur_y) };

function restart() {
  {
    const el = state_el();
    {
      const board = (() => {
        {
          const $t44598_i5293 = (() => {
            {
              const go_i13435 = { $: "$Clo_go$0_List_repeat_Int_Int", _0: go$apply$0_List_repeat_Int_Int, _1: 0 };
              {
                const $t654_i13436 = { $: "Nil" };
                return go$apply$0_List_repeat_Int_Int(go_i13435, 200, $t654_i13436);
              }
            }
          })();
          return Array$from_list$List_Int($t44598_i5293);
        }
      })();
      {
        const rng0 = (() => {
          {
            const raw_i12258 = (() => {
              {
                const $t44668_i12257 = (() => {
                  {
                    const $t44667_i12256 = (() => {
                      {
                        const $t44666_i12255 = (() => {
                          {
                            const $t44665_i12254 = {  };
                            return march_unix_time();
                          }
                        })();
                        return ($t44666_i12255 * 1000000.);
                      }
                    })();
                    return Math.trunc($t44667_i12256);
                  }
                })();
                return march_int_mod($t44668_i12257, 2147483646);
              }
            })();
            {
              const $t44669_i12259 = (raw_i12258 <= 0);
              if ($t44669_i12259 === true) {
                return (raw_i12258 + 2147483646);
              } else if ($t44669_i12259 === false) {
                return raw_i12258;
              } else {
                return (() => { throw new Error("non-exhaustive pattern match"); })();
              }
            }
          }
        })();
        {
          const $t44902 = next_piece(rng0);
          const $f44948 = $t44902._0;
          const $f44949 = $t44902._1;
          {
            const rng1 = $f44949;
            {
              const first = $f44948;
              {
                const $t44903 = (() => {
                  return spawn_piece(first, board, rng1);
                })();
                const $f44917 = $t44903._0;
                const $f44918 = $t44903._1;
                const $f44919 = $t44903._2;
                const $f44920 = $t44903._3;
                const $f44921 = $t44903._4;
                const $f44922 = $t44903._5;
                const $f44923 = $t44903._6;
                {
                  const rng2 = $f44922;
                  {
                    const next = $f44921;
                    {
                      const y = $f44920;
                      {
                        const x = $f44919;
                        {
                          const rot = $f44918;
                          {
                            const piece = $f44917;
                            (() => {
                              {
                                const $t44716_i5288 = (() => {
                                  {
                                    const go_i13430 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                                    {
                                      const $t659_i13432 = { $: "Nil" };
                                      return go$apply$0_List_range(go_i13430, 19, $t659_i13432);
                                    }
                                  }
                                })();
                                {
                                  const $t44728_i5289 = { $: "$Clo_$lam0_render_board$0_render_board", _0: $lam0_render_board$apply$0_render_board, _1: board };
                                  {
                                    const f_i13426 = $t44728_i5289;
                                    {
                                      const go_i13427 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i13426 };
                                      return go$apply$0_List_each_List_Int_Fn_Int_T_(go_i13427, $t44716_i5288);
                                    }
                                  }
                                }
                              }
                            })();
                            (() => {
                              {
                                const base_cells_i5283 = TetrisLogic$piece_cells(piece);
                                {
                                  const rotated_i5284 = rotate_n(base_cells_i5283, rot);
                                  {
                                    const $t44750_i5285 = { $: "$Clo_$lam0_render_falling$0_render_falling", _0: $lam0_render_falling$apply$0_render_falling, _1: x, _2: y, _3: piece };
                                    {
                                      const f_i13423 = $t44750_i5285;
                                      {
                                        const go_i13424 = { $: "$Clo_go$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_", _0: go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_, _1: f_i13423 };
                                        return go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_(go_i13424, rotated_i5284);
                                      }
                                    }
                                  }
                                }
                              }
                            })();
                            set_text_if_found("score", "Score: 0");
                            set_text_if_found("level", "Level: 0");
                            (() => {
                              {
                                const $t44905 = (() => {
                                  {
                                    const $t44904 = piece_to_string(next);
                                    {
                                      const $rc_2391 = ("Next: " + $t44904);
                                      return $rc_2391;
                                    }
                                  }
                                })();
                                return set_text_if_found("next", $t44905);
                              }
                            })();
                            set_text_if_found("game-over", "");
                            (() => {
                              return set_paused(el, false);
                            })();
                            (() => {
                              {
                                const $t44907 = (() => {
                                  {
                                    const $t44906 = (() => {
                                      {
                                        const $t8213_i5276 = { $: "Nil" };
                                        {
                                          const $t8215_i5277 = { $: "$Clo_$lam0_Array_to_list$0_Array_to_list_PVec_Int", _0: $lam0_Array_to_list$apply$0_Array_to_list_PVec_Int };
                                          {
                                            const rev_i5278 = Array$fold_left$PVec_Int$List_Int$Fn_List_Int_Int_List_Int(board, $t8213_i5276, $t8215_i5277);
                                            {
                                              const go_i13420 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                                              {
                                                const $t7798_i13421 = { $: "Nil" };
                                                return go$apply$0_Array_lst_rev_List_Int(go_i13420, rev_i5278, $t7798_i13421);
                                              }
                                            }
                                          }
                                        }
                                      }
                                    })();
                                    return int_list_to_string($t44906);
                                  }
                                })();
                                return Js$Dom$set_attr(el, "data-board", $t44907);
                              }
                            })();
                            (() => {
                              {
                                const $t44908 = (() => {
                                  {
                                    const $rc_2390 = piece_to_string(piece);
                                    return $rc_2390;
                                  }
                                })();
                                return Js$Dom$set_attr(el, "data-piece", $t44908);
                              }
                            })();
                            (() => {
                              {
                                const $t44909 = String(rot);
                                return Js$Dom$set_attr(el, "data-rot", $t44909);
                              }
                            })();
                            (() => {
                              {
                                const $t44910 = String(x);
                                return Js$Dom$set_attr(el, "data-x", $t44910);
                              }
                            })();
                            (() => {
                              {
                                const $t44911 = String(y);
                                return Js$Dom$set_attr(el, "data-y", $t44911);
                              }
                            })();
                            (() => {
                              {
                                const $t44912 = (() => {
                                  {
                                    const $rc_2389 = piece_to_string(next);
                                    return $rc_2389;
                                  }
                                })();
                                return Js$Dom$set_attr(el, "data-next", $t44912);
                              }
                            })();
                            (() => {
                              return Js$Dom$set_attr(el, "data-score", "0");
                            })();
                            (() => {
                              return Js$Dom$set_attr(el, "data-lines", "0");
                            })();
                            (() => {
                              {
                                const $t44913 = String(rng2);
                                return Js$Dom$set_attr(el, "data-rng", $t44913);
                              }
                            })();
                            (() => {
                              return Js$Dom$set_attr(el, "data-over", "false");
                            })();
                            {
                              const $t44916 = (() => {
                                {
                                  const $t44915 = (() => {
                                    {
                                      const $t44914 = (() => {
                                        return get_int_attr(el, "data-seq", 0);
                                      })();
                                      return ($t44914 + 1);
                                    }
                                  })();
                                  return String($t44915);
                                }
                              })();
                              return Js$Dom$set_attr(el, "data-seq", $t44916);
                            }
                          }
                        }
                      }
                    }
                  }
                }
                return (() => { throw new Error("non-exhaustive pattern match"); })();
              }
            }
          }
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const restart$clo = { _0: ($_) => restart() };

function restore_from_request() {
  {
    const $t44954 = Js$Dom$find("restore-request");
    switch ($t44954.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f44970 = $t44954._0;
        {
          const req = $f44970;
          {
            const el = state_el();
            {
              const board_s = (() => {
                return get_str_attr(req, "data-board", "");
              })();
              {
                const piece_s = (() => {
                  return get_str_attr(req, "data-piece", "I");
                })();
                {
                  const rot = (() => {
                    return get_int_attr(req, "data-rot", 0);
                  })();
                  {
                    const x = (() => {
                      return get_int_attr(req, "data-x", 3);
                    })();
                    {
                      const y = (() => {
                        return get_int_attr(req, "data-y", 0);
                      })();
                      {
                        const next_s = (() => {
                          return get_str_attr(req, "data-next", "O");
                        })();
                        {
                          const score = (() => {
                            return get_int_attr(req, "data-score", 0);
                          })();
                          {
                            const lines = (() => {
                              return get_int_attr(req, "data-lines", 0);
                            })();
                            {
                              const rng_s = (() => {
                                return get_str_attr(req, "data-rng", "1");
                              })();
                              {
                                const over = (() => {
                                  {
                                    const $t44955 = (() => {
                                      return get_str_attr(req, "data-over", "false");
                                    })();
                                    {
                                      const $rc_2397 = ($t44955 === "true");
                                      return $rc_2397;
                                    }
                                  }
                                })();
                                {
                                  const paused = (() => {
                                    {
                                      const $t44956 = get_str_attr(req, "data-paused", "false");
                                      {
                                        const $rc_2396 = ($t44956 === "true");
                                        return $rc_2396;
                                      }
                                    }
                                  })();
                                  {
                                    const board = (() => {
                                      {
                                        const $t44957 = (() => {
                                          {
                                            const $t44660_i5308 = march_string_split(board_s, ",");
                                            {
                                              const $t44663_i5309 = { $: "$Clo_$lam0_string_to_int_list$0_string_to_int_list", _0: $lam0_string_to_int_list$apply$0_string_to_int_list };
                                              return List$map$List_String$Fn_String_Int($t44660_i5308, $t44663_i5309);
                                            }
                                          }
                                        })();
                                        return Array$from_list$List_Int($t44957);
                                      }
                                    })();
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
                                        (() => {
                                          {
                                            const $t44716_i5303 = (() => {
                                              {
                                                const go_i13445 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                                                {
                                                  const $t659_i13447 = { $: "Nil" };
                                                  return go$apply$0_List_range(go_i13445, 19, $t659_i13447);
                                                }
                                              }
                                            })();
                                            {
                                              const $t44728_i5304 = { $: "$Clo_$lam0_render_board$0_render_board", _0: $lam0_render_board$apply$0_render_board, _1: board };
                                              {
                                                const f_i13441 = $t44728_i5304;
                                                {
                                                  const go_i13442 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i13441 };
                                                  return go$apply$0_List_each_List_Int_Fn_Int_T_(go_i13442, $t44716_i5303);
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        (() => {
                                          if (over === false) {
                                            return (() => {
                                              {
                                                const base_cells_i5298 = TetrisLogic$piece_cells(piece);
                                                {
                                                  const rotated_i5299 = rotate_n(base_cells_i5298, rot);
                                                  {
                                                    const $t44750_i5300 = { $: "$Clo_$lam0_render_falling$0_render_falling", _0: $lam0_render_falling$apply$0_render_falling, _1: x, _2: y, _3: piece };
                                                    {
                                                      const f_i13438 = $t44750_i5300;
                                                      {
                                                        const go_i13439 = { $: "$Clo_go$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_", _0: go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_, _1: f_i13438 };
                                                        return go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_(go_i13439, rotated_i5299);
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            })();
                                          } else if (over === true) {
                                            return (() => {
                                              return {  };
                                            })();
                                          } else {
                                            return (() => {
                                              return (() => { throw new Error("non-exhaustive pattern match"); })();
                                            })();
                                          }
                                        })();
                                        (() => {
                                          {
                                            const $t44959 = (() => {
                                              {
                                                const $t44958 = String(score);
                                                {
                                                  const $rc_2395 = ("Score: " + $t44958);
                                                  return $rc_2395;
                                                }
                                              }
                                            })();
                                            return set_text_if_found("score", $t44959);
                                          }
                                        })();
                                        (() => {
                                          {
                                            const $t44962 = (() => {
                                              {
                                                const $t44961 = (() => {
                                                  {
                                                    const $t44960 = TetrisLogic$level_for_lines(lines);
                                                    return String($t44960);
                                                  }
                                                })();
                                                {
                                                  const $rc_2394 = ("Level: " + $t44961);
                                                  return $rc_2394;
                                                }
                                              }
                                            })();
                                            return set_text_if_found("level", $t44962);
                                          }
                                        })();
                                        (() => {
                                          {
                                            const $t44964 = (() => {
                                              {
                                                const $t44963 = (() => {
                                                  {
                                                    const $rc_2393 = piece_to_string(next);
                                                    return $rc_2393;
                                                  }
                                                })();
                                                {
                                                  const $rc_2392 = ("Next: " + $t44963);
                                                  return $rc_2392;
                                                }
                                              }
                                            })();
                                            return set_text_if_found("next", $t44964);
                                          }
                                        })();
                                        {
                                          let game_over_text;
                                          if (over === true) {
                                            game_over_text = "Game Over — press R to restart";
                                          } else if (over === false) {
                                            game_over_text = "";
                                          } else {
                                            game_over_text = (() => { throw new Error("non-exhaustive pattern match"); })();
                                          }
                                          set_text_if_found("game-over", game_over_text);
                                          (() => {
                                            return set_paused(el, paused);
                                          })();
                                          (() => {
                                            return Js$Dom$set_attr(el, "data-board", board_s);
                                          })();
                                          (() => {
                                            return Js$Dom$set_attr(el, "data-piece", piece_s);
                                          })();
                                          (() => {
                                            {
                                              const $t44965 = String(rot);
                                              return Js$Dom$set_attr(el, "data-rot", $t44965);
                                            }
                                          })();
                                          (() => {
                                            {
                                              const $t44966 = String(x);
                                              return Js$Dom$set_attr(el, "data-x", $t44966);
                                            }
                                          })();
                                          (() => {
                                            {
                                              const $t44967 = String(y);
                                              return Js$Dom$set_attr(el, "data-y", $t44967);
                                            }
                                          })();
                                          (() => {
                                            return Js$Dom$set_attr(el, "data-next", next_s);
                                          })();
                                          (() => {
                                            {
                                              const $t44968 = String(score);
                                              return Js$Dom$set_attr(el, "data-score", $t44968);
                                            }
                                          })();
                                          (() => {
                                            {
                                              const $t44969 = String(lines);
                                              return Js$Dom$set_attr(el, "data-lines", $t44969);
                                            }
                                          })();
                                          (() => {
                                            return Js$Dom$set_attr(el, "data-rng", rng_s);
                                          })();
                                          {
                                            let over_s;
                                            if (over === true) {
                                              over_s = "true";
                                            } else if (over === false) {
                                              over_s = "false";
                                            } else {
                                              over_s = (() => { throw new Error("non-exhaustive pattern match"); })();
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
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const restore_from_request$clo = { _0: ($_) => restore_from_request() };

function handle_key(ev) {
  {
    const key = (() => {
      {
        const ev_i12262 = ev;
        {
          const $rc_2328_i12263 = dom_event_key$clo._0(dom_event_key$clo, ev);
          return $rc_2328_i12263;
        }
      }
    })();
    (() => {
      {
        let $t44982;
        if (key === "ArrowLeft") {
          $t44982 = true;
        } else if (key === "ArrowRight") {
          $t44982 = true;
        } else if (key === "ArrowDown") {
          $t44982 = true;
        } else if (key === "ArrowUp") {
          $t44982 = true;
        } else if (key === " ") {
          $t44982 = true;
        } else {
          $t44982 = false;
        }
        if ($t44982 === true) {
          return (() => {
            {
              const ev_i12260 = ev;
              {
                const $rc_2329_i12261 = dom_prevent_default$clo._0(dom_prevent_default$clo, ev);
                return $rc_2329_i12261;
              }
            }
          })();
        } else if ($t44982 === false) {
          return (() => {
            return {  };
          })();
        } else {
          return (() => {
            return (() => { throw new Error("non-exhaustive pattern match"); })();
          })();
        }
      }
    })();
    if (key === "r") {
      return (() => {
        return restart();
      })();
    } else if (key === "R") {
      return (() => {
        return restart();
      })();
    } else if (key === "p") {
      return (() => {
        return toggle_pause();
      })();
    } else if (key === "P") {
      return (() => {
        return toggle_pause();
      })();
    } else {
      return (() => {
        {
          const k = key;
          {
            const $t44983 = is_paused();
            if ($t44983 === true) {
              return (() => {
                return {  };
              })();
            } else if ($t44983 === false) {
              return (() => {
                if (k === "ArrowLeft") {
                  return (() => {
                    {
                      const $t44984 = (-1);
                      {
                        const $t44890_i5320 = { $: "$Clo_$lam0_try_move$0_try_move", _0: $lam0_try_move$apply$0_try_move, _1: $t44984, _2: 0 };
                        return with_state($t44890_i5320);
                      }
                    }
                  })();
                } else if (k === "ArrowRight") {
                  return (() => {
                    {
                      const $t44890_i5323 = { $: "$Clo_$lam0_try_move$0_try_move", _0: $lam0_try_move$apply$0_try_move, _1: 1, _2: 0 };
                      return with_state($t44890_i5323);
                    }
                  })();
                } else if (k === "ArrowDown") {
                  return (() => {
                    {
                      const $t44890_i5326 = { $: "$Clo_$lam0_try_move$0_try_move", _0: $lam0_try_move$apply$0_try_move, _1: 0, _2: 1 };
                      return with_state($t44890_i5326);
                    }
                  })();
                } else if (k === "ArrowUp") {
                  return (() => {
                    {
                      const $t44895_i5327 = { $: "$Clo_$lam0_try_rotate$0_try_rotate", _0: $lam0_try_rotate$apply$0_try_rotate };
                      return with_state($t44895_i5327);
                    }
                  })();
                } else if (k === " ") {
                  return (() => {
                    {
                      const $t44901_i5328 = { $: "$Clo_$lam0_hard_drop$0_hard_drop", _0: $lam0_hard_drop$apply$0_hard_drop };
                      return with_state($t44901_i5328);
                    }
                  })();
                } else {
                  return (() => {
                    return {  };
                  })();
                }
              })();
            } else {
              return (() => {
                return (() => { throw new Error("non-exhaustive pattern match"); })();
              })();
            }
          }
        }
      })();
    }
  }
}
const handle_key$clo = { _0: ($_, ev) => handle_key(ev) };

function main(_cap_clock, _cap_foreign) {
  {
    const $t45003 = Js$Dom$find("board");
    switch ($t45003.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f45011 = $t45003._0;
        {
          const board_el = $f45011;
          (() => {
            {
              const $t44972_i5337 = (() => {
                {
                  const go_i13459 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                  {
                    const $t659_i13461 = { $: "Nil" };
                    return go$apply$0_List_range(go_i13459, 19, $t659_i13461);
                  }
                }
              })();
              {
                const $t44981_i5338 = { $: "$Clo_$lam0_build_board_dom$0_build_board_dom", _0: $lam0_build_board_dom$apply$0_build_board_dom, _1: board_el };
                {
                  const f_i13455 = $t44981_i5338;
                  {
                    const go_i13456 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i13455 };
                    return go$apply$0_List_each_List_Int_Fn_Int_T_(go_i13456, $t44972_i5337);
                  }
                }
              }
            }
          })();
          restart();
          (() => {
            {
              const $t45004 = dom_body();
              {
                const $t45006 = { $: "$Clo_$lam0_main$0_main", _0: $lam0_main$apply$0_main };
                return Js$Dom$listen($t45004, "keydown", $t45006);
              }
            }
          })();
          (() => {
            {
              const level_i5332 = (() => {
                {
                  const $t44879_i5331 = (() => {
                    {
                      const $t44878_i5330 = state_el();
                      return get_int_attr($t44878_i5330, "data-lines", 0);
                    }
                  })();
                  return TetrisLogic$level_for_lines($t44879_i5331);
                }
              })();
              {
                const $t44880_i5333 = (() => {
                  {
                    const $t44592_i13452 = (() => {
                      {
                        const $t44591_i13451 = (level_i5332 * 40);
                        return (500 - $t44591_i13451);
                      }
                    })();
                    {
                      const $t2204_i5190_i13453 = ($t44592_i13452 > 100);
                      if ($t2204_i5190_i13453 === true) {
                        return $t44592_i13452;
                      } else {
                        return 100;
                      }
                    }
                  }
                })();
                {
                  const $t44882_i5334 = { $: "$Clo_$lam0_schedule_tick$0_schedule_tick", _0: $lam0_schedule_tick$apply$0_schedule_tick };
                  return Js$Dom$set_timeout($t44880_i5333, $t44882_i5334);
                }
              }
            }
          })();
          {
            const $t45007 = Js$Dom$find("restore-trigger");
            switch ($t45007.$) {
              case "None": {
                return {  };
                break;
              }
              case "Some": {
                const $f45010 = $t45007._0;
                {
                  const trigger = $f45010;
                  {
                    const $t45009 = { $: "$Clo_$lam1_main$1_main", _0: $lam1_main$apply$1_main };
                    return Js$Dom$listen(trigger, "click", $t45009);
                  }
                }
                break;
              }
              default: {
                return (() => { throw new Error("non-exhaustive pattern match"); })();
              }
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const main$clo = { _0: ($_, _cap_clock, _cap_foreign) => main(_cap_clock, _cap_foreign) };

function panic(msg) {
  return (() => { throw new Error(msg); })();
}
const panic$clo = { _0: ($_, msg) => panic(msg) };

function List$filter$List_Int$Fn_Int_Bool(xs, pred) {
  switch (xs.$) {
    case "Nil": {
      return { $: "Nil" };
      break;
    }
    case "Cons": {
      const $f767 = xs._0;
      const $f768 = xs._1;
      {
        const t = $f768;
        {
          const h = $f767;
          {
            const $t765 = (() => {
              return pred._0(pred, h);
            })();
            if ($t765 === true) {
              return (() => {
                {
                  const $trmc20 = { $: "Cons", _0: h, _1: null };
                  List$filter$dps$List_Int$Fn_Int_Bool$List_Int(t, pred, $trmc20);
                  return $trmc20;
                }
              })();
            } else {
              return List$filter$List_Int$Fn_Int_Bool(t, pred);
            }
          }
        }
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const List$filter$List_Int$Fn_Int_Bool$clo = { _0: ($_, xs, pred) => List$filter$List_Int$Fn_Int_Bool(xs, pred) };

function List$all$List_Int$Fn_Int_Bool(xs, pred) {
  switch (xs.$) {
    case "Nil": {
      return true;
      break;
    }
    case "Cons": {
      const $f893 = xs._0;
      const $f894 = xs._1;
      {
        const t = $f894;
        {
          const h = (() => {
            return $f893;
          })();
          {
            const $t892 = (() => {
              return pred._0(pred, h);
            })();
            if ($t892 === true) {
              return List$all$List_Int$Fn_Int_Bool(t, pred);
            } else {
              return (() => {
                return false;
              })();
            }
          }
        }
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const List$all$List_Int$Fn_Int_Bool$clo = { _0: ($_, xs, pred) => List$all$List_Int$Fn_Int_Bool(xs, pred) };

function Option$unwrap_or$Option_Int$Int(opt, _default) {
  switch (opt.$) {
    case "Some": {
      const $f597 = opt._0;
      {
        const x = (() => {
          return $f597;
        })();
        return x;
      }
      break;
    }
    case "None": {
      return _default;
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Option$unwrap_or$Option_Int$Int$clo = { _0: ($_, opt, _default) => Option$unwrap_or$Option_Int$Int(opt, _default) };

function Array$from_list$List_Int(xs) {
  {
    const n = (() => {
      {
        const go_i5646 = { $: "$Clo_go$0_Array_lst_len_List_Int", _0: go$apply$0_Array_lst_len_List_Int };
        return go$apply$0_Array_lst_len_List_Int(go_i5646, xs, 0);
      }
    })();
    {
      const $t8320 = (n === 0);
      if ($t8320 === true) {
        return (() => {
          {
            const $t8004_i5643 = { $: "TrieEmpty" };
            {
              const $t8005_i5644 = { $: "Nil" };
              return { $: "PVec", _0: 0, _1: 0, _2: $t8004_i5643, _3: $t8005_i5644 };
            }
          }
        })();
      } else {
        return (() => {
          {
            const tail_len = (() => {
              {
                const $t8323 = (() => {
                  {
                    const $t8322 = (() => {
                      {
                        const $t8321 = (n - 1);
                        return (($t8321 - $t8321 % 32) / 32);
                      }
                    })();
                    return (32 * $t8322);
                  }
                })();
                return (n - $t8323);
              }
            })();
            {
              const $p8345 = (() => {
                {
                  const $t8324 = (n - tail_len);
                  {
                    const go_i5641 = { $: "$Clo_go$0_Array_lst_split_List_Int_Int", _0: go$apply$0_Array_lst_split_List_Int_Int };
                    {
                      const $t8232_i5642 = { $: "Nil" };
                      return go$apply$0_Array_lst_split_List_Int_Int(go_i5641, xs, $t8324, $t8232_i5642);
                    }
                  }
                }
              })();
              {
                const front = $p8345._0;
                {
                  const tail = $p8345._1;
                  {
                    const $t8325 = (n === tail_len);
                    if ($t8325 === true) {
                      return (() => {
                        {
                          const $t8326 = { $: "TrieEmpty" };
                          {
                            const $rc_2505 = { $: "PVec", _0: n, _1: 0, _2: $t8326, _3: tail };
                            return $rc_2505;
                          }
                        }
                      })();
                    } else {
                      return (() => {
                        {
                          const up = { $: "$Clo_up$0_Array_from_list_List_Int", _0: up$apply$0_Array_from_list_List_Int };
                          {
                            const $p8344 = (() => {
                              {
                                const $t8342 = { $: "$Clo_$lam0_Array_from_list$2_Array_from_list_List_Int", _0: $lam0_Array_from_list$apply$2_Array_from_list_List_Int };
                                {
                                  const $t8343 = (() => {
                                    {
                                      const wrap_i5635 = $t8342;
                                      {
                                        const chunk_i5636 = { $: "$Clo_chunk$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int", _0: chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int, _1: wrap_i5635 };
                                        {
                                          const $t8252_i5637 = { $: "Nil" };
                                          {
                                            const $t8253_i5638 = { $: "Nil" };
                                            return chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int(chunk_i5636, front, 0, $t8252_i5637, $t8253_i5638);
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  return up$apply$0_Array_from_list_List_Int(up, $t8343, 0);
                                }
                              }
                            })();
                            {
                              const root = $p8344._0;
                              {
                                const shift = $p8344._1;
                                {
                                  const $rc_2501 = { $: "PVec", _0: n, _1: shift, _2: root, _3: tail };
                                  return $rc_2501;
                                }
                              }
                            }
                          }
                        }
                      })();
                    }
                  }
                }
              }
            }
          }
        })();
      }
    }
  }
}
const Array$from_list$List_Int$clo = { _0: ($_, xs) => Array$from_list$List_Int(xs) };

function List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(xs, pred) {
  switch (xs.$) {
    case "Nil": {
      return false;
      break;
    }
    case "Cons": {
      const $f886 = xs._0;
      const $f887 = xs._1;
      {
        const t = $f887;
        {
          const h = $f886;
          {
            const $t885 = (() => {
              return pred._0(pred, h);
            })();
            if ($t885 === true) {
              return (() => {
                return true;
              })();
            } else {
              return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(t, pred);
            }
          }
        }
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const List$any$List_T_Int_Int$Fn_T_Int_Int_Bool$clo = { _0: ($_, xs, pred) => List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(xs, pred) };

function Array$get$PVec_Int$Int(v, idx) {
  switch (v.$) {
    case "PVec": {
      const $f8059 = v._0;
      const $f8060 = v._1;
      const $f8061 = v._2;
      const $f8062 = v._3;
      {
        const tail = $f8062;
        {
          const root = $f8061;
          {
            const shift = $f8060;
            {
              const n = $f8059;
              {
                const $t8056 = (() => {
                  {
                    const $t8054 = (idx < 0);
                    {
                      const $t8055 = (idx >= n);
                      return ($t8054 || $t8055);
                    }
                  }
                })();
                if ($t8056 === true) {
                  return (() => {
                    undefined;
                    return (() => { throw new Error("Array.get: index out of range"); })();
                  })();
                } else {
                  return (() => {
                    {
                      const tail_len = (() => {
                        {
                          const go_i5648 = { $: "$Clo_go$0_Array_lst_len_List_Int", _0: go$apply$0_Array_lst_len_List_Int };
                          return go$apply$0_Array_lst_len_List_Int(go_i5648, tail, 0);
                        }
                      })();
                      {
                        const tail_offset = (n - tail_len);
                        {
                          const $t8057 = (idx >= tail_offset);
                          if ($t8057 === true) {
                            return (() => {
                              {
                                const $t8058 = (idx - tail_offset);
                                {
                                  const $rc_2506 = Array$lst_nth$List_Int$Int(tail, $t8058);
                                  return $rc_2506;
                                }
                              }
                            })();
                          } else {
                            return (() => {
                              return Array$trie_get$TrieNode_Int$Int$Int(root, idx, shift);
                            })();
                          }
                        }
                      }
                    }
                  })();
                }
              }
            }
          }
        }
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Array$get$PVec_Int$Int$clo = { _0: ($_, v, idx) => Array$get$PVec_Int$Int(v, idx) };

function List$fold_left$List_T_Int_Int$PVec_Int$Fn_PVec_Int_T_Int_Int_PVec_Int(xs, acc, f) {
  switch (xs.$) {
    case "Nil": {
      return acc;
      break;
    }
    case "Cons": {
      const $f823 = xs._0;
      const $f824 = xs._1;
      {
        const t = $f824;
        {
          const h = $f823;
          {
            const $t822 = (() => {
              return f._0(f, acc, h);
            })();
            return List$fold_left$List_T_Int_Int$PVec_Int$Fn_PVec_Int_T_Int_Int_PVec_Int(t, $t822, f);
          }
        }
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const List$fold_left$List_T_Int_Int$PVec_Int$Fn_PVec_Int_T_Int_Int_PVec_Int$clo = { _0: ($_, xs, acc, f) => List$fold_left$List_T_Int_Int$PVec_Int$Fn_PVec_Int_T_Int_Int_PVec_Int(xs, acc, f) };

function Array$set$PVec_Int$Int$Int(v, idx, val) {
  switch (v.$) {
    case "PVec": {
      const $f8082 = v._0;
      const $f8083 = v._1;
      const $f8084 = v._2;
      const $f8085 = v._3;
      {
        const tail = $f8085;
        {
          const root = $f8084;
          {
            const shift = $f8083;
            {
              const n = $f8082;
              {
                const $t8077 = (() => {
                  {
                    const $t8075 = (idx < 0);
                    {
                      const $t8076 = (idx >= n);
                      return ($t8075 || $t8076);
                    }
                  }
                })();
                if ($t8077 === true) {
                  return (() => {
                    undefined;
                    return (() => { throw new Error("Array.set: index out of range"); })();
                  })();
                } else {
                  return (() => {
                    {
                      const tail_len = (() => {
                        {
                          const go_i5661 = { $: "$Clo_go$0_Array_lst_len_List_Int", _0: go$apply$0_Array_lst_len_List_Int };
                          return go$apply$0_Array_lst_len_List_Int(go_i5661, tail, 0);
                        }
                      })();
                      {
                        const tail_offset = (n - tail_len);
                        {
                          const $t8078 = (idx >= tail_offset);
                          if ($t8078 === true) {
                            return (() => {
                              {
                                const $t8079 = (idx - tail_offset);
                                {
                                  const $t8080 = (() => {
                                    {
                                      const rev_onto_i5657 = { $: "$Clo_rev_onto$0_Array_lst_set_List_Int_Int_Int", _0: rev_onto$apply$0_Array_lst_set_List_Int_Int_Int };
                                      {
                                        const go_i5658 = { $: "$Clo_go$1_Array_lst_set_List_Int_Int_Int", _0: go$apply$1_Array_lst_set_List_Int_Int_Int, _1: rev_onto_i5657, _2: val };
                                        {
                                          const $t7830_i5659 = { $: "Nil" };
                                          return go$apply$1_Array_lst_set_List_Int_Int_Int(go_i5658, tail, $t8079, $t7830_i5659);
                                        }
                                      }
                                    }
                                  })();
                                  return { $: "PVec", _0: n, _1: shift, _2: root, _3: $t8080 };
                                }
                              }
                            })();
                          } else {
                            return (() => {
                              {
                                const $t8081 = (() => {
                                  {
                                    const $t7914_i5653 = { $: "Nil" };
                                    return Array$trie_update_down$TrieNode_Int$Int$List_T_List_TrieNode_Int_Int$Int$Int(root, shift, $t7914_i5653, idx, val);
                                  }
                                })();
                                return { $: "PVec", _0: n, _1: shift, _2: $t8081, _3: tail };
                              }
                            })();
                          }
                        }
                      }
                    }
                  })();
                }
              }
            }
          }
        }
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
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
      const $f737 = xs._0;
      const $f738 = xs._1;
      {
        const t = $f738;
        {
          const h = $f737;
          {
            const $t735 = (() => {
              return f._0(f, h);
            })();
            {
              const $trmc11 = { $: "Cons", _0: $t735, _1: null };
              List$map$dps$List_String$Fn_String_Int$List_Int(t, f, $trmc11);
              return $trmc11;
            }
          }
        }
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const List$map$List_String$Fn_String_Int$clo = { _0: ($_, xs, f) => List$map$List_String$Fn_String_Int(xs, f) };

function List$nth$List_Piece$Int(xs, n) {
  switch (xs.$) {
    case "Nil": {
      undefined;
      return (() => { throw new Error("List.nth: index out of bounds"); })();
      break;
    }
    case "Cons": {
      const $f699 = xs._0;
      const $f700 = xs._1;
      {
        const t = $f700;
        {
          const h = $f699;
          {
            const $t697 = (n === 0);
            if ($t697 === true) {
              return (() => {
                return h;
              })();
            } else {
              return (() => {
                {
                  const $t698 = (n - 1);
                  return List$nth$List_Piece$Int(t, $t698);
                }
              })();
            }
          }
        }
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const List$nth$List_Piece$Int$clo = { _0: ($_, xs, n) => List$nth$List_Piece$Int(xs, n) };

function List$map$dps$List_Int$Fn_Int_String$List_String(xs, f, $dst) {
  switch (xs.$) {
    case "Nil": {
      {
        const $trmc9 = { $: "Nil" };
        return ($dst._1 = $trmc9, undefined);
      }
      break;
    }
    case "Cons": {
      const $f737 = xs._0;
      const $f738 = xs._1;
      {
        const t = $f738;
        {
          const h = $f737;
          {
            const $t735 = (() => {
              return f._0(f, h);
            })();
            {
              const $trmc10 = { $: "Cons", _0: $t735, _1: null };
              ($dst._1 = $trmc10, undefined);
              return List$map$dps$List_Int$Fn_Int_String$List_String(t, f, $trmc10);
            }
          }
        }
      }
      break;
    }
    default: {
      {
        const $trmc8 = (() => { throw new Error("non-exhaustive pattern match"); })();
        return ($dst._1 = $trmc8, undefined);
      }
    }
  }
}
const List$map$dps$List_Int$Fn_Int_String$List_String$clo = { _0: ($_, xs, f, $dst) => List$map$dps$List_Int$Fn_Int_String$List_String(xs, f, $dst) };

function List$map$dps$List_Int$Fn_Int_Int$List_Int(xs, f, $dst) {
  switch (xs.$) {
    case "Nil": {
      {
        const $trmc9 = { $: "Nil" };
        return ($dst._1 = $trmc9, undefined);
      }
      break;
    }
    case "Cons": {
      const $f737 = xs._0;
      const $f738 = xs._1;
      {
        const t = $f738;
        {
          const h = $f737;
          {
            const $t735 = (() => {
              return f._0(f, h);
            })();
            {
              const $trmc10 = { $: "Cons", _0: $t735, _1: null };
              ($dst._1 = $trmc10, undefined);
              return List$map$dps$List_Int$Fn_Int_Int$List_Int(t, f, $trmc10);
            }
          }
        }
      }
      break;
    }
    default: {
      {
        const $trmc8 = (() => { throw new Error("non-exhaustive pattern match"); })();
        return ($dst._1 = $trmc8, undefined);
      }
    }
  }
}
const List$map$dps$List_Int$Fn_Int_Int$List_Int$clo = { _0: ($_, xs, f, $dst) => List$map$dps$List_Int$Fn_Int_Int$List_Int(xs, f, $dst) };

function List$append$dps$List_Int$List_Int$List_Int(xs, ys, $dst) {
  switch (xs.$) {
    case "Nil": {
      return ($dst._1 = ys, undefined);
      break;
    }
    case "Cons": {
      const $f729 = xs._0;
      const $f730 = xs._1;
      {
        const t = $f730;
        {
          const h = $f729;
          {
            const $trmc6 = { $: "Cons", _0: h, _1: null };
            ($dst._1 = $trmc6, undefined);
            return List$append$dps$List_Int$List_Int$List_Int(t, ys, $trmc6);
          }
        }
      }
      break;
    }
    default: {
      {
        const $trmc4 = (() => { throw new Error("non-exhaustive pattern match"); })();
        return ($dst._1 = $trmc4, undefined);
      }
    }
  }
}
const List$append$dps$List_Int$List_Int$List_Int$clo = { _0: ($_, xs, ys, $dst) => List$append$dps$List_Int$List_Int$List_Int(xs, ys, $dst) };

function List$filter$dps$List_Int$Fn_Int_Bool$List_Int(xs, pred, $dst) {
  switch (xs.$) {
    case "Nil": {
      {
        const $trmc18 = { $: "Nil" };
        return ($dst._1 = $trmc18, undefined);
      }
      break;
    }
    case "Cons": {
      const $f767 = xs._0;
      const $f768 = xs._1;
      {
        const t = $f768;
        {
          const h = $f767;
          {
            const $t765 = (() => {
              return pred._0(pred, h);
            })();
            if ($t765 === true) {
              return (() => {
                {
                  const $trmc19 = { $: "Cons", _0: h, _1: null };
                  ($dst._1 = $trmc19, undefined);
                  return List$filter$dps$List_Int$Fn_Int_Bool$List_Int(t, pred, $trmc19);
                }
              })();
            } else {
              return List$filter$dps$List_Int$Fn_Int_Bool$List_Int(t, pred, $dst);
            }
          }
        }
      }
      break;
    }
    default: {
      {
        const $trmc17 = (() => { throw new Error("non-exhaustive pattern match"); })();
        return ($dst._1 = $trmc17, undefined);
      }
    }
  }
}
const List$filter$dps$List_Int$Fn_Int_Bool$List_Int$clo = { _0: ($_, xs, pred, $dst) => List$filter$dps$List_Int$Fn_Int_Bool$List_Int(xs, pred, $dst) };

function List$map$dps$List_T_Int_Int$Fn_T_Int_Int_T_Int_Int$List_T_Int_Int(xs, f, $dst) {
  switch (xs.$) {
    case "Nil": {
      {
        const $trmc9 = { $: "Nil" };
        return ($dst._1 = $trmc9, undefined);
      }
      break;
    }
    case "Cons": {
      const $f737 = xs._0;
      const $f738 = xs._1;
      {
        const t = $f738;
        {
          const h = $f737;
          {
            const $t735 = (() => {
              return f._0(f, h);
            })();
            {
              const $trmc10 = { $: "Cons", _0: $t735, _1: null };
              ($dst._1 = $trmc10, undefined);
              return List$map$dps$List_T_Int_Int$Fn_T_Int_Int_T_Int_Int$List_T_Int_Int(t, f, $trmc10);
            }
          }
        }
      }
      break;
    }
    default: {
      {
        const $trmc8 = (() => { throw new Error("non-exhaustive pattern match"); })();
        return ($dst._1 = $trmc8, undefined);
      }
    }
  }
}
const List$map$dps$List_T_Int_Int$Fn_T_Int_Int_T_Int_Int$List_T_Int_Int$clo = { _0: ($_, xs, f, $dst) => List$map$dps$List_T_Int_Int$Fn_T_Int_Int_T_Int_Int$List_T_Int_Int(xs, f, $dst) };

function Array$lst_nth$List_Int$Int(lst, n) {
  switch (lst.$) {
    case "Nil": {
      undefined;
      return (() => { throw new Error("Array: index out of bounds"); })();
      break;
    }
    case "Cons": {
      const $f7801 = lst._0;
      const $f7802 = lst._1;
      {
        const t = $f7802;
        {
          const h = (() => {
            return $f7801;
          })();
          {
            const $t7799 = (n === 0);
            if ($t7799 === true) {
              return h;
            } else {
              return (() => {
                {
                  const $t7800 = (n - 1);
                  return Array$lst_nth$List_Int$Int(t, $t7800);
                }
              })();
            }
          }
        }
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Array$lst_nth$List_Int$Int$clo = { _0: ($_, lst, n) => Array$lst_nth$List_Int$Int(lst, n) };

function Array$trie_get$TrieNode_Int$Int$Int(node, idx, shift) {
  switch (node.$) {
    case "TrieEmpty": {
      undefined;
      return (() => { throw new Error("Array.get: missing node"); })();
      break;
    }
    case "TrieLeaf": {
      const $f7895 = node._0;
      {
        const values = $f7895;
        {
          const $t7892 = march_int_and(idx, 31);
          {
            const $rc_2570 = Array$lst_nth$List_Int$Int(values, $t7892);
            return $rc_2570;
          }
        }
      }
      break;
    }
    case "TrieBranch": {
      const $f7896 = node._0;
      {
        const children = $f7896;
        {
          const slot = (() => {
            {
              const $t7891_i7166 = march_int_shr(idx, shift);
              return march_int_and($t7891_i7166, 31);
            }
          })();
          {
            const $t7893 = Array$lst_nth$List_TrieNode_Int$Int(children, slot);
            {
              const $t7894 = (shift - 5);
              return Array$trie_get$TrieNode_Int$Int$Int($t7893, idx, $t7894);
            }
          }
        }
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Array$trie_get$TrieNode_Int$Int$Int$clo = { _0: ($_, node, idx, shift) => Array$trie_get$TrieNode_Int$Int$Int(node, idx, shift) };

function List$flat_map_go$List_Int$List_Int$Fn_Int_List_Int(sub, lst, f) {
  switch (sub.$) {
    case "Cons": {
      const $f759 = sub._0;
      const $f760 = sub._1;
      {
        const rest = $f760;
        {
          const x = $f759;
          {
            const $trmc16 = { $: "Cons", _0: x, _1: null };
            List$flat_map_go$dps$List_Int$List_Int$Fn_Int_List_Int$List_Int(rest, lst, f, $trmc16);
            return $trmc16;
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
          const $f753 = lst._0;
          const $f754 = lst._1;
          {
            const t = $f754;
            {
              const h = $f753;
              {
                const $t752 = (() => {
                  return f._0(f, h);
                })();
                return List$flat_map_go$List_Int$List_Int$Fn_Int_List_Int($t752, t, f);
              }
            }
          }
          break;
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const List$flat_map_go$List_Int$List_Int$Fn_Int_List_Int$clo = { _0: ($_, sub, lst, f) => List$flat_map_go$List_Int$List_Int$Fn_Int_List_Int(sub, lst, f) };

function List$map$dps$List_String$Fn_String_Int$List_Int(xs, f, $dst) {
  switch (xs.$) {
    case "Nil": {
      {
        const $trmc9 = { $: "Nil" };
        return ($dst._1 = $trmc9, undefined);
      }
      break;
    }
    case "Cons": {
      const $f737 = xs._0;
      const $f738 = xs._1;
      {
        const t = $f738;
        {
          const h = $f737;
          {
            const $t735 = (() => {
              return f._0(f, h);
            })();
            {
              const $trmc10 = { $: "Cons", _0: $t735, _1: null };
              ($dst._1 = $trmc10, undefined);
              return List$map$dps$List_String$Fn_String_Int$List_Int(t, f, $trmc10);
            }
          }
        }
      }
      break;
    }
    default: {
      {
        const $trmc8 = (() => { throw new Error("non-exhaustive pattern match"); })();
        return ($dst._1 = $trmc8, undefined);
      }
    }
  }
}
const List$map$dps$List_String$Fn_String_Int$List_Int$clo = { _0: ($_, xs, f, $dst) => List$map$dps$List_String$Fn_String_Int$List_Int(xs, f, $dst) };

function Array$fold_left$PVec_Int$List_Int$Fn_List_Int_Int_List_Int(v, acc, f) {
  switch (v.$) {
    case "PVec": {
      const $f8197 = v._0;
      const $f8198 = v._1;
      const $f8199 = v._2;
      const $f8200 = v._3;
      {
        const tail = $f8200;
        {
          const root = $f8199;
          {
            const acc2 = (() => {
              return Array$trie_fold$List_Int$TrieNode_Int$Fn_List_Int_Int_List_Int(acc, root, f);
            })();
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
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Array$fold_left$PVec_Int$List_Int$Fn_List_Int_Int_List_Int$clo = { _0: ($_, v, acc, f) => Array$fold_left$PVec_Int$List_Int$Fn_List_Int_Int_List_Int(v, acc, f) };

function Array$lst_nth$List_TrieNode_Int$Int(lst, n) {
  switch (lst.$) {
    case "Nil": {
      undefined;
      return (() => { throw new Error("Array: index out of bounds"); })();
      break;
    }
    case "Cons": {
      const $f7801 = lst._0;
      const $f7802 = lst._1;
      {
        const t = $f7802;
        {
          const h = $f7801;
          {
            const $t7799 = (n === 0);
            if ($t7799 === true) {
              return (() => {
                return h;
              })();
            } else {
              return (() => {
                {
                  const $t7800 = (n - 1);
                  return Array$lst_nth$List_TrieNode_Int$Int(t, $t7800);
                }
              })();
            }
          }
        }
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Array$lst_nth$List_TrieNode_Int$Int$clo = { _0: ($_, lst, n) => Array$lst_nth$List_TrieNode_Int$Int(lst, n) };

function Array$trie_update_down$TrieNode_Int$Int$List_T_List_TrieNode_Int_Int$Int$Int(n, s, path, idx, val) {
  switch (n.$) {
    case "TrieEmpty": {
      undefined;
      return (() => { throw new Error("Array.set: missing node"); })();
      break;
    }
    case "TrieLeaf": {
      const $f7912 = n._0;
      {
        const values = $f7912;
        {
          const $t7908 = (() => {
            {
              const $t7906 = march_int_and(idx, 31);
              {
                const $t7907 = (() => {
                  {
                    const rev_onto_i7233 = { $: "$Clo_rev_onto$0_Array_lst_set_List_Int_Int_Int", _0: rev_onto$apply$0_Array_lst_set_List_Int_Int_Int };
                    {
                      const go_i7234 = { $: "$Clo_go$1_Array_lst_set_List_Int_Int_Int", _0: go$apply$1_Array_lst_set_List_Int_Int_Int, _1: rev_onto_i7233, _2: val };
                      {
                        const $t7830_i7235 = { $: "Nil" };
                        return go$apply$1_Array_lst_set_List_Int_Int_Int(go_i7234, values, $t7906, $t7830_i7235);
                      }
                    }
                  }
                })();
                return { $: "TrieLeaf", _0: $t7907 };
              }
            }
          })();
          {
            const $rc_2590 = Array$trie_update_up$TrieNode_Int$List_T_List_TrieNode_Int_Int($t7908, path);
            return $rc_2590;
          }
        }
      }
      break;
    }
    case "TrieBranch": {
      const $f7913 = n._0;
      {
        const children = $f7913;
        {
          const slot = (() => {
            {
              const $t7891_i7238 = march_int_shr(idx, s);
              return march_int_and($t7891_i7238, 31);
            }
          })();
          {
            const child = (() => {
              return Array$lst_nth$List_TrieNode_Int$Int(children, slot);
            })();
            {
              const $t7909 = (s - 5);
              {
                const $t7910 = { _0: children, _1: slot };
                {
                  const $t7911 = { $: "Cons", _0: $t7910, _1: path };
                  return Array$trie_update_down$TrieNode_Int$Int$List_T_List_TrieNode_Int_Int$Int$Int(child, $t7909, $t7911, idx, val);
                }
              }
            }
          }
        }
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Array$trie_update_down$TrieNode_Int$Int$List_T_List_TrieNode_Int_Int$Int$Int$clo = { _0: ($_, n, s, path, idx, val) => Array$trie_update_down$TrieNode_Int$Int$List_T_List_TrieNode_Int_Int$Int$Int(n, s, path, idx, val) };

function List$flat_map_go$dps$List_Int$List_Int$Fn_Int_List_Int$List_Int(sub, lst, f, $dst) {
  switch (sub.$) {
    case "Cons": {
      const $f759 = sub._0;
      const $f760 = sub._1;
      {
        const rest = $f760;
        {
          const x = $f759;
          {
            const $trmc13 = { $: "Cons", _0: x, _1: null };
            ($dst._1 = $trmc13, undefined);
            return List$flat_map_go$dps$List_Int$List_Int$Fn_Int_List_Int$List_Int(rest, lst, f, $trmc13);
          }
        }
      }
      break;
    }
    case "Nil": {
      switch (lst.$) {
        case "Nil": {
          {
            const $trmc15 = { $: "Nil" };
            return ($dst._1 = $trmc15, undefined);
          }
          break;
        }
        case "Cons": {
          const $f753 = lst._0;
          const $f754 = lst._1;
          {
            const t = $f754;
            {
              const h = $f753;
              {
                const $t752 = (() => {
                  return f._0(f, h);
                })();
                return List$flat_map_go$dps$List_Int$List_Int$Fn_Int_List_Int$List_Int($t752, t, f, $dst);
              }
            }
          }
          break;
        }
        default: {
          {
            const $trmc14 = (() => { throw new Error("non-exhaustive pattern match"); })();
            return ($dst._1 = $trmc14, undefined);
          }
        }
      }
      break;
    }
    default: {
      {
        const $trmc12 = (() => { throw new Error("non-exhaustive pattern match"); })();
        return ($dst._1 = $trmc12, undefined);
      }
    }
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
      const $f8002 = node._0;
      {
        const values = $f8002;
        {
          const go = { $: "$Clo_go$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int", _0: go$apply$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int, _1: f };
          return go$apply$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int(go, acc, values);
        }
      }
      break;
    }
    case "TrieBranch": {
      const $f8003 = node._0;
      {
        const children = $f8003;
        {
          const go = { $: "$Clo_go$1_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int", _0: go$apply$1_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int, _1: f };
          return go$apply$1_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int(go, acc, children);
        }
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Array$trie_fold$List_Int$TrieNode_Int$Fn_List_Int_Int_List_Int$clo = { _0: ($_, acc, node, f) => Array$trie_fold$List_Int$TrieNode_Int$Fn_List_Int_Int_List_Int(acc, node, f) };

function Array$trie_update_up$TrieNode_Int$List_T_List_TrieNode_Int_Int(nd, stk) {
  switch (stk.$) {
    case "Nil": {
      return nd;
      break;
    }
    case "Cons": {
      const $f7900 = stk._0;
      const $f7901 = stk._1;
      {
        const rest = $f7901;
        {
          const frame = $f7900;
          {
            const children = frame._0;
            {
              const slot = frame._1;
              {
                const $t7898 = (() => {
                  {
                    const $t7897 = (() => {
                      {
                        const rev_onto_i7311 = { $: "$Clo_rev_onto$0_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int", _0: rev_onto$apply$0_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int };
                        {
                          const go_i7312 = { $: "$Clo_go$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int", _0: go$apply$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int, _1: nd, _2: rev_onto_i7311 };
                          {
                            const $t7890_i7313 = { $: "Nil" };
                            return go$apply$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int(go_i7312, children, slot, $t7890_i7313);
                          }
                        }
                      }
                    })();
                    return { $: "TrieBranch", _0: $t7897 };
                  }
                })();
                return Array$trie_update_up$TrieNode_Int$List_T_List_TrieNode_Int_Int($t7898, rest);
              }
            }
          }
        }
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Array$trie_update_up$TrieNode_Int$List_T_List_TrieNode_Int_Int$clo = { _0: ($_, nd, stk) => Array$trie_update_up$TrieNode_Int$List_T_List_TrieNode_Int_Int(nd, stk) };

function go$apply$0_List_range($clo, i, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const start = $clo._1;
      {
        const $t655 = (i < start);
        if ($t655 === true) {
          return (() => {
            return acc;
          })();
        } else {
          return (() => {
            {
              const $t656 = (i - 1);
              {
                const $t657 = { $: "Cons", _0: i, _1: acc };
                return go$apply$0_List_range(go, $t656, $t657);
              }
            }
          })();
        }
      }
    }
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
        const $f44618 = c._0;
        const $f44619 = c._1;
        {
          const dy = $f44619;
          {
            const dx = $f44618;
            {
              const x = (origin_x + dx);
              {
                const y = (origin_y + dy);
                {
                  const $t44615 = (() => {
                    {
                      const $t44611_i8177 = (() => {
                        {
                          const $t44609_i8175 = (() => {
                            {
                              const $t44606_i8172 = (x >= 0);
                              {
                                const $t44608_i8174 = (x < 10);
                                return ($t44606_i8172 && $t44608_i8174);
                              }
                            }
                          })();
                          {
                            const $t44610_i8176 = (y >= 0);
                            return ($t44609_i8175 && $t44610_i8176);
                          }
                        }
                      })();
                      {
                        const $t44613_i8179 = (y < 20);
                        return ($t44611_i8177 && $t44613_i8179);
                      }
                    }
                  })();
                  if ($t44615 === false) {
                    return true;
                  } else if ($t44615 === true) {
                    return (() => {
                      {
                        const $t44617 = (() => {
                          {
                            const $t44616 = (() => {
                              {
                                const $t44594_i8169 = (y * 10);
                                return ($t44594_i8169 + x);
                              }
                            })();
                            return Array$get$PVec_Int$Int(board, $t44616);
                          }
                        })();
                        return ($t44617 !== 0);
                      }
                    })();
                  } else {
                    return (() => { throw new Error("non-exhaustive pattern match"); })();
                  }
                }
              }
            }
          }
        }
        return (() => { throw new Error("non-exhaustive pattern match"); })();
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
        const $f44628 = c._0;
        const $f44629 = c._1;
        {
          const dy = $f44629;
          {
            const dx = $f44628;
            {
              const x = (origin_x + dx);
              {
                const y = (origin_y + dy);
                {
                  const $t44626 = (() => {
                    {
                      const $t44611_i8191 = (() => {
                        {
                          const $t44609_i8189 = (() => {
                            {
                              const $t44606_i8186 = (x >= 0);
                              {
                                const $t44608_i8188 = (x < 10);
                                return ($t44606_i8186 && $t44608_i8188);
                              }
                            }
                          })();
                          {
                            const $t44610_i8190 = (y >= 0);
                            return ($t44609_i8189 && $t44610_i8190);
                          }
                        }
                      })();
                      {
                        const $t44613_i8193 = (y < 20);
                        return ($t44611_i8191 && $t44613_i8193);
                      }
                    }
                  })();
                  if ($t44626 === true) {
                    return (() => {
                      {
                        const $t44627 = (() => {
                          {
                            const $t44594_i8183 = (y * 10);
                            return ($t44594_i8183 + x);
                          }
                        })();
                        return Array$set$PVec_Int$Int$Int(b, $t44627, color_idx);
                      }
                    })();
                  } else if ($t44626 === false) {
                    return b;
                  } else {
                    return (() => {
                      return (() => { throw new Error("non-exhaustive pattern match"); })();
                    })();
                  }
                }
              }
            }
          }
        }
        return (() => { throw new Error("non-exhaustive pattern match"); })();
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
        const $t44639 = (() => {
          {
            const $t44638 = (() => {
              {
                const $t44594_i8197 = (y * 10);
                return ($t44594_i8197 + x);
              }
            })();
            return Array$get$PVec_Int$Int(board, $t44638);
          }
        })();
        return ($t44639 !== 0);
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
        const $t44644 = (() => {
          {
            const $t44594_i8201 = (y * 10);
            return ($t44594_i8201 + x);
          }
        })();
        return Array$get$PVec_Int$Int(board, $t44644);
      }
    }
  }
}
const $lam0_TetrisLogic_row_cells$apply$0_TetrisLogic_row_cells$clo = { _0: ($_, $clo, x) => $lam0_TetrisLogic_row_cells$apply$0_TetrisLogic_row_cells($clo, x) };

function $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines($clo, y) {
  {
    const board = $clo._1;
    {
      const $t44648 = (() => {
        {
          const $t44636_i13289 = (() => {
            {
              const go_i5197_i13286 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
              {
                const $t659_i5199_i13288 = { $: "Nil" };
                return go$apply$0_List_range(go_i5197_i13286, 9, $t659_i5199_i13288);
              }
            }
          })();
          {
            const $t44640_i13290 = { $: "$Clo_$lam0_TetrisLogic_row_full$0_TetrisLogic_row_full", _0: $lam0_TetrisLogic_row_full$apply$0_TetrisLogic_row_full, _1: board, _2: y };
            {
              const $rc_2374_i13291 = List$all$List_Int$Fn_Int_Bool($t44636_i13289, $t44640_i13290);
              return $rc_2374_i13291;
            }
          }
        }
      })();
      return (!$t44648);
    }
  }
}
const $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines$clo = { _0: ($_, $clo, y) => $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines($clo, y) };

function $lam1_TetrisLogic_clear_lines$apply$1_TetrisLogic_clear_lines($clo, y) {
  {
    const board = $clo._1;
    {
      const $t44642_i8205 = (() => {
        {
          const go_i13464 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
          {
            const $t659_i13466 = { $: "Nil" };
            return go$apply$0_List_range(go_i13464, 9, $t659_i13466);
          }
        }
      })();
      {
        const $t44645_i8206 = { $: "$Clo_$lam0_TetrisLogic_row_cells$0_TetrisLogic_row_cells", _0: $lam0_TetrisLogic_row_cells$apply$0_TetrisLogic_row_cells, _1: board, _2: y };
        {
          const xs_i13494 = $t44642_i8205;
          {
            const f_i13495 = $t44645_i8206;
            switch (xs_i13494.$) {
              case "Nil": {
                return { $: "Nil" };
                break;
              }
              case "Cons": {
                const $f737_i13496 = xs_i13494._0;
                const $f738_i13497 = xs_i13494._1;
                {
                  const t_i13498 = $f738_i13497;
                  {
                    const h_i13499 = $f737_i13496;
                    {
                      const $t735_i13500 = (() => {
                        return f_i13495._0(f_i13495, h_i13499);
                      })();
                      {
                        const $trmc11_i13501 = { $: "Cons", _0: $t735_i13500, _1: null };
                        List$map$dps$List_Int$Fn_Int_Int$List_Int(t_i13498, f_i13495, $trmc11_i13501);
                        return $trmc11_i13501;
                      }
                    }
                  }
                }
                break;
              }
              default: {
                return (() => { throw new Error("non-exhaustive pattern match"); })();
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
    const $t44662 = (() => {
      {
        const $rc_3108 = march_string_to_int(x);
        return $rc_3108;
      }
    })();
    {
      const $rc_3107 = Option$unwrap_or$Option_Int$Int($t44662, 0);
      return $rc_3107;
    }
  }
}
const $lam0_string_to_int_list$apply$0_string_to_int_list$clo = { _0: ($_, $clo, x) => $lam0_string_to_int_list$apply$0_string_to_int_list($clo, x) };

function $lam0_render_board$apply$0_render_board($clo, y) {
  {
    const board = $clo._1;
    {
      const $t44719 = (() => {
        {
          const go_i8212 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
          {
            const $t659_i8214 = { $: "Nil" };
            return go$apply$0_List_range(go_i8212, 9, $t659_i8214);
          }
        }
      })();
      {
        const $t44727 = (() => {
          return { $: "$Clo_$lam0__lam0_render_board$1_render_board", _0: $lam0__lam0_render_board$apply$1_render_board, _1: board, _2: y };
        })();
        {
          const f_i8208 = $t44727;
          {
            const go_i8209 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i8208 };
            return go$apply$0_List_each_List_Int_Fn_Int_T_(go_i8209, $t44719);
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
        const idx = (() => {
          {
            const $t44594_i8219 = (y * 10);
            return ($t44594_i8219 + x);
          }
        })();
        {
          const v = (() => {
            return Array$get$PVec_Int$Int(board, idx);
          })();
          {
            const id = (() => {
              {
                const $t44721 = String(x);
                {
                  const $t44722 = String(y);
                  {
                    const $rc_3109 = march_string_concat_n("cell-", $t44721, "-", $t44722);
                    return $rc_3109;
                  }
                }
              }
            })();
            {
              const $t44723 = Js$Dom$find(id);
              switch ($t44723.$) {
                case "None": {
                  return {  };
                  break;
                }
                case "Some": {
                  const $f44726 = $t44723._0;
                  {
                    const cell = $f44726;
                    {
                      const $t44724 = (v === 0);
                      if ($t44724 === true) {
                        return Js$Dom$set_style(cell, "background", "");
                      } else if ($t44724 === false) {
                        return (() => {
                          {
                            let $t44725;
                            if (v === 1) {
                              $t44725 = "#00CED1";
                            } else if (v === 2) {
                              $t44725 = "#FFD700";
                            } else if (v === 3) {
                              $t44725 = "#9B59B6";
                            } else if (v === 4) {
                              $t44725 = "#2ECC71";
                            } else if (v === 5) {
                              $t44725 = "#E74C3C";
                            } else if (v === 6) {
                              $t44725 = "#3498DB";
                            } else if (v === 7) {
                              $t44725 = "#F39C12";
                            } else {
                              $t44725 = "";
                            }
                            return Js$Dom$set_style(cell, "background", $t44725);
                          }
                        })();
                      } else {
                        return (() => {
                          return (() => { throw new Error("non-exhaustive pattern match"); })();
                        })();
                      }
                    }
                  }
                  break;
                }
                default: {
                  return (() => { throw new Error("non-exhaustive pattern match"); })();
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
        const $f44744 = c._0;
        const $f44745 = c._1;
        {
          const dy = $f44745;
          {
            const dx = $f44744;
            {
              const x = (ox + dx);
              {
                const y = (oy + dy);
                {
                  const $t44738 = (() => {
                    {
                      const $t44735 = (() => {
                        {
                          const $t44733 = (() => {
                            {
                              const $t44730 = (x >= 0);
                              {
                                const $t44732 = (x < 10);
                                return ($t44730 && $t44732);
                              }
                            }
                          })();
                          {
                            const $t44734 = (y >= 0);
                            return ($t44733 && $t44734);
                          }
                        }
                      })();
                      {
                        const $t44737 = (y < 20);
                        return ($t44735 && $t44737);
                      }
                    }
                  })();
                  if ($t44738 === false) {
                    return {  };
                  } else if ($t44738 === true) {
                    return (() => {
                      {
                        const id = (() => {
                          {
                            const $t44739 = String(x);
                            {
                              const $t44740 = String(y);
                              {
                                const $rc_3110 = march_string_concat_n("cell-", $t44739, "-", $t44740);
                                return $rc_3110;
                              }
                            }
                          }
                        })();
                        {
                          const $t44741 = Js$Dom$find(id);
                          switch ($t44741.$) {
                            case "None": {
                              return {  };
                              break;
                            }
                            case "Some": {
                              const $f44743 = $t44741._0;
                              {
                                const cell = $f44743;
                                {
                                  let $t44742;
                                  switch (piece.$) {
                                    case "I": {
                                      $t44742 = "#00CED1";
                                      break;
                                    }
                                    case "O": {
                                      $t44742 = "#FFD700";
                                      break;
                                    }
                                    case "T": {
                                      $t44742 = "#9B59B6";
                                      break;
                                    }
                                    case "S": {
                                      $t44742 = "#2ECC71";
                                      break;
                                    }
                                    case "Z": {
                                      $t44742 = "#E74C3C";
                                      break;
                                    }
                                    case "J": {
                                      $t44742 = "#3498DB";
                                      break;
                                    }
                                    case "L": {
                                      $t44742 = "#F39C12";
                                      break;
                                    }
                                    default: {
                                      $t44742 = (() => { throw new Error("non-exhaustive pattern match"); })();
                                      break;
                                    }
                                  }
                                  return Js$Dom$set_style(cell, "background", $t44742);
                                }
                              }
                              break;
                            }
                            default: {
                              return (() => { throw new Error("non-exhaustive pattern match"); })();
                            }
                          }
                        }
                      }
                    })();
                  } else {
                    return (() => { throw new Error("non-exhaustive pattern match"); })();
                  }
                }
              }
            }
          }
        }
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const $lam0_render_falling$apply$0_render_falling$clo = { _0: ($_, $clo, c) => $lam0_render_falling$apply$0_render_falling($clo, c) };

function $lam0_tick$apply$0_tick($clo, board, piece, rot, x, y, next, score, lines, rng) {
  {
    const $t44873 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t44873, rot);
      {
        const $t44875 = (() => {
          {
            const $t44874 = (y + 1);
            {
              const $t44624_i8224 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: x, _3: $t44874 };
              return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t44624_i8224);
            }
          }
        })();
        if ($t44875 === true) {
          return (() => {
            {
              const $rc_3111 = lock_and_advance(board, piece, rot, x, y, next, score, lines, rng);
              return $rc_3111;
            }
          })();
        } else if ($t44875 === false) {
          return (() => {
            {
              const $t44876 = (y + 1);
              return { _0: board, _1: piece, _2: rot, _3: x, _4: $t44876, _5: next, _6: score, _7: lines, _8: rng, _9: false };
            }
          })();
        } else {
          return (() => {
            return (() => { throw new Error("non-exhaustive pattern match"); })();
          })();
        }
      }
    }
  }
}
const $lam0_tick$apply$0_tick$clo = { _0: ($_, $clo, board, piece, rot, x, y, next, score, lines, rng) => $lam0_tick$apply$0_tick($clo, board, piece, rot, x, y, next, score, lines, rng) };

function $lam0_schedule_tick$apply$0_schedule_tick($clo, _) {
  (() => {
    {
      const $t44871_i13293 = is_paused();
      if ($t44871_i13293 === true) {
        return {  };
      } else if ($t44871_i13293 === false) {
        return (() => {
          {
            const $t44877_i13294 = { $: "$Clo_$lam0_tick$0_tick", _0: $lam0_tick$apply$0_tick };
            return with_state($t44877_i13294);
          }
        })();
      } else {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  })();
  {
    const level_i8227 = (() => {
      {
        const $t44879_i8226 = (() => {
          {
            const $t44878_i8225 = state_el();
            return get_int_attr($t44878_i8225, "data-lines", 0);
          }
        })();
        return TetrisLogic$level_for_lines($t44879_i8226);
      }
    })();
    {
      const $t44880_i8228 = (() => {
        {
          const $t44592_i13469 = (() => {
            {
              const $t44591_i13468 = (level_i8227 * 40);
              return (500 - $t44591_i13468);
            }
          })();
          {
            const $t2204_i5190_i13470 = ($t44592_i13469 > 100);
            if ($t2204_i5190_i13470 === true) {
              return $t44592_i13469;
            } else {
              return 100;
            }
          }
        }
      })();
      {
        const $t44882_i8229 = { $: "$Clo_$lam0_schedule_tick$0_schedule_tick", _0: $lam0_schedule_tick$apply$0_schedule_tick };
        return Js$Dom$set_timeout($t44880_i8228, $t44882_i8229);
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
        const $t44884 = TetrisLogic$piece_cells(piece);
        {
          const cells = rotate_n($t44884, rot);
          {
            const $t44887 = (() => {
              {
                const $t44885 = (x + dx);
                {
                  const $t44886 = (y + dy);
                  {
                    const $t44624_i8234 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: $t44885, _3: $t44886 };
                    return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t44624_i8234);
                  }
                }
              }
            })();
            if ($t44887 === true) {
              return { _0: board, _1: piece, _2: rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: rng, _9: false };
            } else if ($t44887 === false) {
              return (() => {
                {
                  const $t44888 = (x + dx);
                  {
                    const $t44889 = (y + dy);
                    return { _0: board, _1: piece, _2: rot, _3: $t44888, _4: $t44889, _5: next, _6: score, _7: lines, _8: rng, _9: false };
                  }
                }
              })();
            } else {
              return (() => {
                return (() => { throw new Error("non-exhaustive pattern match"); })();
              })();
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
    const new_rot = (() => {
      {
        const $t44892 = (rot + 1);
        return ($t44892 % 4);
      }
    })();
    {
      const $t44893 = TetrisLogic$piece_cells(piece);
      {
        const cells = rotate_n($t44893, new_rot);
        {
          const $t44894 = (() => {
            {
              const $t44624_i8239 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: x, _3: y };
              return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t44624_i8239);
            }
          })();
          if ($t44894 === true) {
            return { _0: board, _1: piece, _2: rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: rng, _9: false };
          } else if ($t44894 === false) {
            return { _0: board, _1: piece, _2: new_rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: rng, _9: false };
          } else {
            return (() => {
              return (() => { throw new Error("non-exhaustive pattern match"); })();
            })();
          }
        }
      }
    }
  }
}
const $lam0_try_rotate$apply$0_try_rotate$clo = { _0: ($_, $clo, board, piece, rot, x, y, next, score, lines, rng) => $lam0_try_rotate$apply$0_try_rotate($clo, board, piece, rot, x, y, next, score, lines, rng) };

function $lam0_hard_drop$apply$0_hard_drop($clo, board, piece, rot, x, y, next, score, lines, rng) {
  {
    const $t44900 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t44900, rot);
      {
        const final_y = (() => {
          return fall_from(board, cells, x, y);
        })();
        {
          const $rc_3112 = lock_and_advance(board, piece, rot, x, final_y, next, score, lines, rng);
          return $rc_3112;
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
      (() => {
        return Js$Dom$add_class(row, "tetris-row");
      })();
      (() => {
        {
          const $t44975 = (() => {
            {
              const go_i8245 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
              {
                const $t659_i8247 = { $: "Nil" };
                return go$apply$0_List_range(go_i8245, 9, $t659_i8247);
              }
            }
          })();
          {
            const $t44980 = (() => {
              return { $: "$Clo_$lam0__lam0_build_board_dom$1_build_board_dom", _0: $lam0__lam0_build_board_dom$apply$1_build_board_dom, _1: row, _2: y };
            })();
            {
              const f_i8241 = $t44980;
              {
                const go_i8242 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i8241 };
                return go$apply$0_List_each_List_Int_Fn_Int_T_(go_i8242, $t44975);
              }
            }
          }
        }
      })();
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
        (() => {
          return Js$Dom$add_class(cell, "tetris-cell");
        })();
        (() => {
          {
            const $t44979 = (() => {
              {
                const $t44977 = String(x);
                {
                  const $t44978 = String(y);
                  {
                    const $rc_3113 = march_string_concat_n("cell-", $t44977, "-", $t44978);
                    return $rc_3113;
                  }
                }
              }
            })();
            return Js$Dom$set_attr(cell, "id", $t44979);
          }
        })();
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

function go$apply$0_List_repeat_Int_Int($clo, i, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const x = $clo._1;
      {
        const $t651 = (i <= 0);
        if ($t651 === true) {
          return (() => {
            return acc;
          })();
        } else {
          return (() => {
            {
              const $t652 = (i - 1);
              {
                const $t653 = { $: "Cons", _0: x, _1: acc };
                return go$apply$0_List_repeat_Int_Int(go, $t652, $t653);
              }
            }
          })();
        }
      }
    }
  }
}
const go$apply$0_List_repeat_Int_Int$clo = { _0: ($_, $clo, i, acc) => go$apply$0_List_repeat_Int_Int($clo, i, acc) };

function go$apply$0_List_length_List_Int($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f714 = lst._0;
        const $f715 = lst._1;
        {
          const t = $f715;
          {
            const $t713 = (acc + 1);
            return go$apply$0_List_length_List_Int($clo, t, $t713);
          }
        }
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$0_List_length_List_Int$clo = { _0: ($_, $clo, lst, acc) => go$apply$0_List_length_List_Int($clo, lst, acc) };

function up$apply$0_Array_from_list_List_Int($clo, nodes, shift) {
  {
    const up = $clo;
    {
      const $t8328 = { $: "$Clo_$lam0_Array_from_list_up$1_Array_from_list_List_Int", _0: $lam0_Array_from_list_up$apply$1_Array_from_list_List_Int };
      {
        const parents = (() => {
          {
            const wrap_i8475 = $t8328;
            {
              const chunk_i8476 = { $: "$Clo_chunk$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int", _0: chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int, _1: wrap_i8475 };
              {
                const $t8252_i8477 = { $: "Nil" };
                {
                  const $t8253_i8478 = { $: "Nil" };
                  return chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int(chunk_i8476, nodes, 0, $t8252_i8477, $t8253_i8478);
                }
              }
            }
          }
        })();
        {
          const $t8330 = (() => {
            {
              const $t8329 = (() => {
                {
                  const go_i8473 = { $: "$Clo_go$0_Array_lst_len_List_TrieNode_Int", _0: go$apply$0_Array_lst_len_List_TrieNode_Int };
                  return go$apply$0_Array_lst_len_List_TrieNode_Int(go_i8473, parents, 0);
                }
              })();
              return ($t8329 === 1);
            }
          })();
          if ($t8330 === true) {
            return (() => {
              switch (parents.$) {
                case "Cons": {
                  const $f8334 = parents._0;
                  const $f8335 = parents._1;
                  {
                    const root = $f8334;
                    {
                      const $t8331 = (shift + 5);
                      return { _0: root, _1: $t8331 };
                    }
                  }
                  break;
                }
                case "Nil": {
                  {
                    const $t8332 = { $: "TrieEmpty" };
                    {
                      const $t8333 = (shift + 5);
                      return { _0: $t8332, _1: $t8333 };
                    }
                  }
                  break;
                }
                default: {
                  return (() => { throw new Error("non-exhaustive pattern match"); })();
                }
              }
            })();
          } else {
            return (() => {
              {
                const $t8340 = (shift + 5);
                return up$apply$0_Array_from_list_List_Int($clo, parents, $t8340);
              }
            })();
          }
        }
      }
    }
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

function go$apply$0_List_each_List_Int_Fn_Int_T_($clo, lst) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          return {  };
          break;
        }
        case "Cons": {
          const $f744 = lst._0;
          const $f745 = lst._1;
          {
            const t = $f745;
            {
              const h = $f744;
              {
                const $p743 = (() => {
                  return f._0(f, h);
                })();
                return go$apply$0_List_each_List_Int_Fn_Int_T_(go, t);
              }
            }
          }
          break;
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$0_List_each_List_Int_Fn_Int_T_$clo = { _0: ($_, $clo, lst) => go$apply$0_List_each_List_Int_Fn_Int_T_($clo, lst) };

function go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_($clo, lst) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          return {  };
          break;
        }
        case "Cons": {
          const $f744 = lst._0;
          const $f745 = lst._1;
          {
            const t = $f745;
            {
              const h = $f744;
              {
                const $p743 = (() => {
                  return f._0(f, h);
                })();
                return go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_(go, t);
              }
            }
          }
          break;
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_$clo = { _0: ($_, $clo, lst) => go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_($clo, lst) };

function $lam0_Array_to_list$apply$0_Array_to_list_PVec_Int($clo, acc, x) {
  return { $: "Cons", _0: x, _1: acc };
}
const $lam0_Array_to_list$apply$0_Array_to_list_PVec_Int$clo = { _0: ($_, $clo, acc, x) => $lam0_Array_to_list$apply$0_Array_to_list_PVec_Int($clo, acc, x) };

function go$apply$0_Array_lst_len_List_TrieNode_Int($clo, xs, acc) {
  {
    const go = $clo;
    switch (xs.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f7832 = xs._0;
        const $f7833 = xs._1;
        {
          const t = $f7833;
          {
            const $t7831 = (acc + 1);
            return go$apply$0_Array_lst_len_List_TrieNode_Int($clo, t, $t7831);
          }
        }
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$0_Array_lst_len_List_TrieNode_Int$clo = { _0: ($_, $clo, xs, acc) => go$apply$0_Array_lst_len_List_TrieNode_Int($clo, xs, acc) };

function chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int($clo, ys, i, cur, out) {
  {
    const chunk = (() => {
      return $clo;
    })();
    {
      const wrap = $clo._1;
      switch (ys.$) {
        case "Nil": {
          switch (cur.$) {
            case "Nil": {
              {
                const go_i8556 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                {
                  const $t7798_i8557 = { $: "Nil" };
                  return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i8556, out, $t7798_i8557);
                }
              }
              break;
            }
            default: {
              {
                const $t8234 = (() => {
                  {
                    const $t8233 = (() => {
                      {
                        const go_i8553 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                        {
                          const $t7798_i8554 = { $: "Nil" };
                          return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i8553, cur, $t7798_i8554);
                        }
                      }
                    })();
                    return wrap._0(wrap, $t8233);
                  }
                })();
                {
                  const $t8235 = { $: "Cons", _0: $t8234, _1: out };
                  {
                    const go_i8550 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                    {
                      const $t7798_i8551 = { $: "Nil" };
                      return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i8550, $t8235, $t7798_i8551);
                    }
                  }
                }
              }
            }
          }
          break;
        }
        case "Cons": {
          const $f8246 = ys._0;
          const $f8247 = ys._1;
          {
            const t = $f8247;
            {
              const h = $f8246;
              {
                const $t8238 = (i === 31);
                if ($t8238 === true) {
                  return (() => {
                    {
                      const $t8239 = { $: "Nil" };
                      {
                        const $t8242 = (() => {
                          {
                            const $t8240 = { $: "Cons", _0: h, _1: cur };
                            {
                              const $t8241 = (() => {
                                {
                                  const go_i8559 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                                  {
                                    const $t7798_i8560 = { $: "Nil" };
                                    return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i8559, $t8240, $t7798_i8560);
                                  }
                                }
                              })();
                              return wrap._0(wrap, $t8241);
                            }
                          }
                        })();
                        {
                          const $t8243 = { $: "Cons", _0: $t8242, _1: out };
                          return chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int(chunk, t, 0, $t8239, $t8243);
                        }
                      }
                    }
                  })();
                } else {
                  return (() => {
                    {
                      const $t8244 = (i + 1);
                      {
                        const $t8245 = { $: "Cons", _0: h, _1: cur };
                        return chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int(chunk, t, $t8244, $t8245, out);
                      }
                    }
                  })();
                }
              }
            }
          }
          break;
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int$clo = { _0: ($_, $clo, ys, i, cur, out) => chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int($clo, ys, i, cur, out) };

function chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int($clo, ys, i, cur, out) {
  {
    const chunk = (() => {
      return $clo;
    })();
    {
      const wrap = $clo._1;
      switch (ys.$) {
        case "Nil": {
          switch (cur.$) {
            case "Nil": {
              {
                const go_i8568 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                {
                  const $t7798_i8569 = { $: "Nil" };
                  return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i8568, out, $t7798_i8569);
                }
              }
              break;
            }
            default: {
              {
                const $t8234 = (() => {
                  {
                    const $t8233 = (() => {
                      {
                        const go_i8565 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                        {
                          const $t7798_i8566 = { $: "Nil" };
                          return go$apply$0_Array_lst_rev_List_Int(go_i8565, cur, $t7798_i8566);
                        }
                      }
                    })();
                    return wrap._0(wrap, $t8233);
                  }
                })();
                {
                  const $t8235 = { $: "Cons", _0: $t8234, _1: out };
                  {
                    const go_i8562 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                    {
                      const $t7798_i8563 = { $: "Nil" };
                      return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i8562, $t8235, $t7798_i8563);
                    }
                  }
                }
              }
            }
          }
          break;
        }
        case "Cons": {
          const $f8246 = ys._0;
          const $f8247 = ys._1;
          {
            const t = $f8247;
            {
              const h = $f8246;
              {
                const $t8238 = (i === 31);
                if ($t8238 === true) {
                  return (() => {
                    {
                      const $t8239 = { $: "Nil" };
                      {
                        const $t8242 = (() => {
                          {
                            const $t8240 = { $: "Cons", _0: h, _1: cur };
                            {
                              const $t8241 = (() => {
                                {
                                  const go_i8571 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                                  {
                                    const $t7798_i8572 = { $: "Nil" };
                                    return go$apply$0_Array_lst_rev_List_Int(go_i8571, $t8240, $t7798_i8572);
                                  }
                                }
                              })();
                              return wrap._0(wrap, $t8241);
                            }
                          }
                        })();
                        {
                          const $t8243 = { $: "Cons", _0: $t8242, _1: out };
                          return chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int(chunk, t, 0, $t8239, $t8243);
                        }
                      }
                    }
                  })();
                } else {
                  return (() => {
                    {
                      const $t8244 = (i + 1);
                      {
                        const $t8245 = { $: "Cons", _0: h, _1: cur };
                        return chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int(chunk, t, $t8244, $t8245, out);
                      }
                    }
                  })();
                }
              }
            }
          }
          break;
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int$clo = { _0: ($_, $clo, ys, i, cur, out) => chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int($clo, ys, i, cur, out) };

function go$apply$0_Array_lst_split_List_Int_Int($clo, ys, i, acc) {
  {
    const go = $clo;
    {
      const $t8220 = (i === 0);
      if ($t8220 === true) {
        return (() => {
          {
            const $t8221 = (() => {
              {
                const go_i8577 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                {
                  const $t7798_i8578 = { $: "Nil" };
                  return go$apply$0_Array_lst_rev_List_Int(go_i8577, acc, $t7798_i8578);
                }
              }
            })();
            return { _0: $t8221, _1: ys };
          }
        })();
      } else {
        return (() => {
          switch (ys.$) {
            case "Nil": {
              {
                const $t8222 = (() => {
                  {
                    const go_i8574 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                    {
                      const $t7798_i8575 = { $: "Nil" };
                      return go$apply$0_Array_lst_rev_List_Int(go_i8574, acc, $t7798_i8575);
                    }
                  }
                })();
                {
                  const $t8223 = { $: "Nil" };
                  return { _0: $t8222, _1: $t8223 };
                }
              }
              break;
            }
            case "Cons": {
              const $f8226 = ys._0;
              const $f8227 = ys._1;
              {
                const t = $f8227;
                {
                  const h = $f8226;
                  {
                    const $t8224 = (i - 1);
                    {
                      const $t8225 = { $: "Cons", _0: h, _1: acc };
                      return go$apply$0_Array_lst_split_List_Int_Int($clo, t, $t8224, $t8225);
                    }
                  }
                }
              }
              break;
            }
            default: {
              return (() => { throw new Error("non-exhaustive pattern match"); })();
            }
          }
        })();
      }
    }
  }
}
const go$apply$0_Array_lst_split_List_Int_Int$clo = { _0: ($_, $clo, ys, i, acc) => go$apply$0_Array_lst_split_List_Int_Int($clo, ys, i, acc) };

function go$apply$0_Array_lst_len_List_Int($clo, xs, acc) {
  {
    const go = $clo;
    switch (xs.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f7832 = xs._0;
        const $f7833 = xs._1;
        {
          const t = $f7833;
          {
            const $t7831 = (acc + 1);
            return go$apply$0_Array_lst_len_List_Int($clo, t, $t7831);
          }
        }
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$0_Array_lst_len_List_Int$clo = { _0: ($_, $clo, xs, acc) => go$apply$0_Array_lst_len_List_Int($clo, xs, acc) };

function rev_onto$apply$0_Array_lst_set_List_Int_Int_Int($clo, rev_xs, ys) {
  {
    const rev_onto = $clo;
    switch (rev_xs.$) {
      case "Nil": {
        return ys;
        break;
      }
      case "Cons": {
        const $f7808 = rev_xs._0;
        const $f7809 = rev_xs._1;
        {
          const rest = $f7809;
          {
            const a = $f7808;
            {
              const $t7807 = { $: "Cons", _0: a, _1: ys };
              return rev_onto$apply$0_Array_lst_set_List_Int_Int_Int($clo, rest, $t7807);
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const rev_onto$apply$0_Array_lst_set_List_Int_Int_Int$clo = { _0: ($_, $clo, rev_xs, ys) => rev_onto$apply$0_Array_lst_set_List_Int_Int_Int($clo, rev_xs, ys) };

function go$apply$1_Array_lst_set_List_Int_Int_Int($clo, xs, i, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const rev_onto = $clo._1;
      {
        const v = $clo._2;
        {
          const $t7814 = (i === 0);
          if ($t7814 === true) {
            return (() => {
              switch (xs.$) {
                case "Nil": {
                  {
                    const go_i8583 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                    {
                      const $t7798_i8584 = { $: "Nil" };
                      return go$apply$0_Array_lst_rev_List_Int(go_i8583, acc, $t7798_i8584);
                    }
                  }
                  break;
                }
                case "Cons": {
                  const $f7816 = xs._0;
                  const $f7817 = xs._1;
                  {
                    const t = $f7817;
                    {
                      const $t7815 = { $: "Cons", _0: v, _1: t };
                      return rev_onto._0(rev_onto, acc, $t7815);
                    }
                  }
                  break;
                }
                default: {
                  return (() => { throw new Error("non-exhaustive pattern match"); })();
                }
              }
            })();
          } else {
            return (() => {
              switch (xs.$) {
                case "Nil": {
                  {
                    const go_i8580 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                    {
                      const $t7798_i8581 = { $: "Nil" };
                      return go$apply$0_Array_lst_rev_List_Int(go_i8580, acc, $t7798_i8581);
                    }
                  }
                  break;
                }
                case "Cons": {
                  const $f7824 = xs._0;
                  const $f7825 = xs._1;
                  {
                    const t = $f7825;
                    {
                      const h = $f7824;
                      {
                        const $t7822 = (i - 1);
                        {
                          const $t7823 = { $: "Cons", _0: h, _1: acc };
                          return go$apply$1_Array_lst_set_List_Int_Int_Int(go, t, $t7822, $t7823);
                        }
                      }
                    }
                  }
                  break;
                }
                default: {
                  return (() => { throw new Error("non-exhaustive pattern match"); })();
                }
              }
            })();
          }
        }
      }
    }
  }
}
const go$apply$1_Array_lst_set_List_Int_Int_Int$clo = { _0: ($_, $clo, xs, i, acc) => go$apply$1_Array_lst_set_List_Int_Int_Int($clo, xs, i, acc) };

function go$apply$0_Array_lst_rev_List_Int($clo, xs, acc) {
  {
    const go = $clo;
    switch (xs.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f7792 = xs._0;
        const $f7793 = xs._1;
        {
          const t = $f7793;
          {
            const h = $f7792;
            {
              const $t7791 = { $: "Cons", _0: h, _1: acc };
              return go$apply$0_Array_lst_rev_List_Int($clo, t, $t7791);
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$0_Array_lst_rev_List_Int$clo = { _0: ($_, $clo, xs, acc) => go$apply$0_Array_lst_rev_List_Int($clo, xs, acc) };

function go$apply$0_Array_fold_left_PVec_Int_List_Int_Fn_List_Int_Int_List_Int($clo, a, xs) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (xs.$) {
        case "Nil": {
          return a;
          break;
        }
        case "Cons": {
          const $f8191 = xs._0;
          const $f8192 = xs._1;
          {
            const rest = $f8192;
            {
              const x = $f8191;
              {
                const $t8190 = (() => {
                  return f._0(f, a, x);
                })();
                return go$apply$0_Array_fold_left_PVec_Int_List_Int_Fn_List_Int_Int_List_Int(go, $t8190, rest);
              }
            }
          }
          break;
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$0_Array_fold_left_PVec_Int_List_Int_Fn_List_Int_Int_List_Int$clo = { _0: ($_, $clo, a, xs) => go$apply$0_Array_fold_left_PVec_Int_List_Int_Fn_List_Int_Int_List_Int($clo, a, xs) };

function go$apply$0_Array_lst_rev_List_TrieNode_Int($clo, xs, acc) {
  {
    const go = $clo;
    switch (xs.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f7792 = xs._0;
        const $f7793 = xs._1;
        {
          const t = $f7793;
          {
            const h = $f7792;
            {
              const $t7791 = { $: "Cons", _0: h, _1: acc };
              return go$apply$0_Array_lst_rev_List_TrieNode_Int($clo, t, $t7791);
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$0_Array_lst_rev_List_TrieNode_Int$clo = { _0: ($_, $clo, xs, acc) => go$apply$0_Array_lst_rev_List_TrieNode_Int($clo, xs, acc) };

function go$apply$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int($clo, a, vs) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (vs.$) {
        case "Nil": {
          return a;
          break;
        }
        case "Cons": {
          const $f7989 = vs._0;
          const $f7990 = vs._1;
          {
            const rest = $f7990;
            {
              const v = $f7989;
              {
                const $t7988 = (() => {
                  return f._0(f, a, v);
                })();
                return go$apply$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int(go, $t7988, rest);
              }
            }
          }
          break;
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int$clo = { _0: ($_, $clo, a, vs) => go$apply$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int($clo, a, vs) };

function go$apply$1_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int($clo, a, cs) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (cs.$) {
        case "Nil": {
          return a;
          break;
        }
        case "Cons": {
          const $f7996 = cs._0;
          const $f7997 = cs._1;
          {
            const rest = $f7997;
            {
              const child = $f7996;
              {
                const $t7995 = (() => {
                  return Array$trie_fold$List_Int$TrieNode_Int$Fn_List_Int_Int_List_Int(a, child, f);
                })();
                return go$apply$1_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int(go, $t7995, rest);
              }
            }
          }
          break;
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$1_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int$clo = { _0: ($_, $clo, a, cs) => go$apply$1_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int($clo, a, cs) };

function rev_onto$apply$0_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int($clo, rev_xs, ys) {
  {
    const rev_onto = $clo;
    switch (rev_xs.$) {
      case "Nil": {
        return ys;
        break;
      }
      case "Cons": {
        const $f7874 = rev_xs._0;
        const $f7875 = rev_xs._1;
        {
          const rest = $f7875;
          {
            const a = $f7874;
            {
              const $t7873 = { $: "Cons", _0: a, _1: ys };
              return rev_onto$apply$0_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int($clo, rest, $t7873);
            }
          }
        }
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const rev_onto$apply$0_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int$clo = { _0: ($_, $clo, rev_xs, ys) => rev_onto$apply$0_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int($clo, rev_xs, ys) };

function go$apply$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int($clo, xs, i, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const node = $clo._1;
      {
        const rev_onto = $clo._2;
        switch (xs.$) {
          case "Nil": {
            {
              const go_i8996 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
              {
                const $t7798_i8997 = { $: "Nil" };
                return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i8996, acc, $t7798_i8997);
              }
            }
            break;
          }
          case "Cons": {
            const $f7884 = xs._0;
            const $f7885 = xs._1;
            {
              const t = $f7885;
              {
                const h = $f7884;
                {
                  const $t7880 = (i === 0);
                  if ($t7880 === true) {
                    return (() => {
                      {
                        const $t7881 = (() => {
                          return { $: "Cons", _0: node, _1: t };
                        })();
                        return rev_onto._0(rev_onto, acc, $t7881);
                      }
                    })();
                  } else {
                    return (() => {
                      {
                        const $t7882 = (i - 1);
                        {
                          const $t7883 = { $: "Cons", _0: h, _1: acc };
                          return go$apply$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int(go, t, $t7882, $t7883);
                        }
                      }
                    })();
                  }
                }
              }
            }
            break;
          }
          default: {
            return (() => { throw new Error("non-exhaustive pattern match"); })();
          }
        }
      }
    }
  }
}
const go$apply$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int$clo = { _0: ($_, $clo, xs, i, acc) => go$apply$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int($clo, xs, i, acc) };

export { main };
main();
//# sourceMappingURL=tetris.mjs.map
