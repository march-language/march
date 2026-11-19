import { march_cap_grant_text, march_cap_launch_fail, march_cap_set_launch, march_div_zero, march_float_ceil, march_float_floor, march_float_round, march_float_to_int, march_float_to_string, march_float_truncate, march_int_and, march_int_div, march_int_div_euclid, march_int_div_floor, march_int_mod, march_int_mod_euclid, march_int_mod_floor, march_int_not, march_int_or, march_int_ovf, march_int_popcount, march_int_shl, march_int_shr, march_int_wrapping_add, march_int_wrapping_mul, march_int_wrapping_sub, march_int_xor, march_mod_zero, march_panic_error, march_panic_site, march_string_byte_length, march_string_concat3, march_string_concat_n, march_string_contains, march_string_ends_with, march_string_index_of, march_string_join, march_string_last_index_of, march_string_replace_all, march_string_slice, march_string_split, march_string_starts_with, march_string_to_int, march_string_to_lowercase, march_try_finally, march_unix_time, march_unix_time_ms } from "./march_runtime.mjs";

import { march_dom_set_timeout as dom_set_timeout, march_dom_prevent_default as dom_prevent_default, march_dom_event_key as dom_event_key, march_dom_add_event_listener as dom_add_event_listener, march_dom_set_style as dom_set_style, march_dom_class_add as dom_class_add, march_dom_set_attribute as dom_set_attribute, march_dom_get_attribute as dom_get_attribute, march_dom_set_text as dom_set_text, march_dom_append_child as dom_append_child, march_dom_create_element as dom_create_element, march_dom_body as dom_body, march_dom_get_element_by_id as dom_get_element_by_id } from "./march_dom.mjs";


const int_to_string   = { _0: ($_, x) => String(x) };
const bool_to_string  = { _0: ($_, x) => String(x) };
const int_to_float    = { _0: ($_, x) => x };
const string_is_empty = { _0: ($_, x) => x === "" };
const not_bool        = { _0: ($_, x) => !x };
const negate_int      = { _0: ($_, x) => march_int_ovf(-x, 3) };
const negate_float    = { _0: ($_, x) => -x };
const float_abs       = { _0: ($_, x) => Math.abs(x) };
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
const float_to_int = { _0: ($_, a) => march_float_to_int(a) };
const float_truncate = { _0: ($_, a) => march_float_truncate(a) };
const float_floor = { _0: ($_, a) => march_float_floor(a) };
const float_ceil = { _0: ($_, a) => march_float_ceil(a) };
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

function __eq_CapLimit(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ByLaunch": {
      return true;
    }
    case "ByFnNeeds": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "ByModNeeds": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "ByRestrict": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "ByGrant": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_CapError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "CapError": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (!__eq_CapLimit(a._2, b._2)) return false;
      if (a._3 !== b._3) return false;
      return true;
    }
  }
  return true;
}

function __eq_Authority$Arg(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Any": {
      return true;
    }
    case "Paths": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
    case "Hosts": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Names": {
      if (!__eq_List(a._0, b._0)) return false;
      if (!__eq_List(a._1, b._1)) return false;
      return true;
    }
    case "HostAt": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (a._3 !== b._3) return false;
      return true;
    }
    case "PathsAt": {
      if (!__eq_List(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Authority$Scope(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Scope": {
      if (a._0 !== b._0) return false;
      if (!__eq_Arg(a._1, b._1)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Authority$Layer(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Layer": {
      if (!__eq_CapLimit(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      if (!__eq_List(a._2, b._2)) return false;
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

function __eq_Http$ScopeRefusal(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "HostRefused": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "MethodNotAllowed": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "PathNotAllowed": {
      if (a._0 !== b._0) return false;
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
    case "Refused": {
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
    case "Refused": {
      if (a._0 !== b._0) return false;
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
    case "PathRefused": {
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
    case "Closed": {
      return true;
    }
    case "Escapes": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_File$WriteMode(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Truncate": {
      return true;
    }
    case "Append": {
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
      if (!__eq_$Handle(a._0, b._0)) return false;
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
      if (!__eq_$Handle(a._0, b._0)) return false;
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

function __eq_HttpServer$TlsSource(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "TlsFiles": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
    case "TlsPem": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_HttpServer$ServerOpts(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ServerOpts": {
      if (!__eq_Option(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      if (a._3 !== b._3) return false;
      if (a._4 !== b._4) return false;
      if (a._5 !== b._5) return false;
      if (a._6 !== b._6) return false;
      if (!__eq_List(a._7, b._7)) return false;
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
      if (!__eq_ServerOpts(a._4, b._4)) return false;
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
    case "ListenFailed": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "AcceptFailed": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "Closed": {
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
    case "Closed": {
      return true;
    }
  }
  return true;
}

function __eq_Udp$UdpSocket(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "UdpSocket": {
      if (!__eq_$Handle(a._0, b._0)) return false;
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

function __eq_Process$ProcessError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Closed": {
      return true;
    }
    case "ProcessFailed": {
      if (a._0 !== b._0) return false;
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
    case "Closed": {
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
      if (!__eq_$Handle(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_Tls$TlsConn(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "TlsConn": {
      if (!__eq_$Handle(a._0, b._0)) return false;
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

function __eq_Channel$ChannelSocket(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ChannelSocket": {
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

function __eq_PeerRegistry$Fd(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Fd": {
      if (a._0 !== b._0) return false;
      return true;
    }
  }
  return true;
}

function __eq_PeerRegistry$Peer(a, b) {
  if (a.node_id !== b.node_id) return false;
  if (!__eq_NodeIdentity$Identity(a.identity, b.identity)) return false;
  if (!__eq_Fd(a.fd, b.fd)) return false;
  if (!__eq_Fd(a.data_fd, b.data_fd)) return false;
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
  if (!__eq_PeerRegistry$Fd(a.data_fd, b.data_fd)) return false;
  if (!__eq_PeerRegistry$Fd(a.control_fd, b.control_fd)) return false;
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

function Authority$launch_init(request, scoped) {
  {
    const grant = march_cap_grant_text();
    {
      let $t821;
      {
        const $t820 = (!scoped);
        if ($t820 === true) {
          $t821 = (grant === "");
        } else {
          $t821 = false;
        }
      }
      if ($t821 === true) {
        return {  };
      } else {
        {
          const $t822 = Authority$parse(request);
          switch ($t822.$) {
            case "Err": {
              const $f841 = $t822._0;
              {
                const e = $f841;
                march_panic_site("stdlib/authority.march", 186, 16, 76);
                {
                  let $t823;
                  {
                    const $rc_67 = ("internal: main's request is not a scope list: " + e);
                    $t823 = $rc_67;
                  }
                  return (() => { throw march_panic_error("panic: ", $t823); })();
                }
              }
              break;
            }
            case "Ok": {
              const $f842 = $t822._0;
              {
                const req = $f842;
                {
                  const $t824 = (grant === "");
                  if ($t824 === true) {
                    {
                      let $t826;
                      {
                        const $t825 = { $: "ByLaunch" };
                        $t826 = { $: "Layer", _0: $t825, _1: request, _2: req };
                      }
                      {
                        const $t827 = { $: "Nil" };
                        {
                          const $t828 = { $: "Cons", _0: $t826, _1: $t827 };
                          return march_cap_set_launch($t828);
                        }
                      }
                    }
                  } else {
                    {
                      const $t829 = Authority$parse(grant);
                      switch ($t829.$) {
                        case "Err": {
                          const $f839 = $t829._0;
                          {
                            const e = $f839;
                            {
                              let $t830;
                              {
                                const $rc_69 = ("march: MARCH_GRANT is not a scope list: " + e);
                                $t830 = $rc_69;
                              }
                              {
                                const $rc_68 = Authority$launch_error($t830);
                                return $rc_68;
                              }
                            }
                          }
                          break;
                        }
                        case "Ok": {
                          const $f840 = $t829._0;
                          {
                            const g = $f840;
                            {
                              let $t831;
                              {
                                let $rc_72;
                                $rc_72 = Authority$first_outside(g, req);
                                $t831 = $rc_72;
                              }
                              switch ($t831.$) {
                                case "Some": {
                                  const $f838 = $t831._0;
                                  {
                                    const s = $f838;
                                    {
                                      let $t833;
                                      {
                                        const $t832 = Authority$scope_text(s);
                                        {
                                          const $rc_71 = march_string_concat_n("march: MARCH_GRANT grants ", $t832, ", which main does not request (main requests: ", request, ")");
                                          $t833 = $rc_71;
                                        }
                                      }
                                      {
                                        const $rc_70 = Authority$launch_error($t833);
                                        return $rc_70;
                                      }
                                    }
                                  }
                                  break;
                                }
                                case "None": {
                                  {
                                    let $t835;
                                    {
                                      const $t834 = { $: "ByLaunch" };
                                      $t835 = { $: "Layer", _0: $t834, _1: grant, _2: g };
                                    }
                                    {
                                      const $t836 = { $: "Nil" };
                                      {
                                        const $t837 = { $: "Cons", _0: $t835, _1: $t836 };
                                        return march_cap_set_launch($t837);
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
const Authority$launch_init$clo = { _0: ($_, request, scoped) => Authority$launch_init(request, scoped) };

function Authority$launch_error(msg) {
  {
    const $t843 = (msg + "\n");
    {
      const $rc_73 = march_cap_launch_fail($t843);
      return $rc_73;
    }
  }
}
const Authority$launch_error$clo = { _0: ($_, msg) => Authority$launch_error(msg) };

function Authority$first_outside($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const a = $tco_a0;
    const b = $tco_a1;
    switch (a.$) {
      case "Nil": {
        return { $: "None" };
        break;
      }
      case "Cons": {
        const $f845 = a._0;
        const $f846 = a._1;
        {
          const rest = $f846;
          {
            const s = $f845;
            {
              let $t844;
              $t844 = Authority$covered(s, b);
              if ($t844 === true) {
                {
                  $tco_a0 = rest;
                  $tco_a1 = b;
                  continue __tco;
                }
              } else {
                return { $: "Some", _0: s };
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
const Authority$first_outside$clo = { _0: ($_, a, b) => Authority$first_outside(a, b) };

function Authority$covered($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const s = $tco_a0;
    const b = $tco_a1;
    switch (b.$) {
      case "Nil": {
        return false;
        break;
      }
      case "Cons": {
        const $f967 = b._0;
        const $f968 = b._1;
        switch ($f967.$) {
          case "Scope": {
            const $f969 = $f967._0;
            const $f970 = $f967._1;
            {
              const rest = $f968;
              {
                const outer = $f970;
                {
                  const k = $f969;
                  switch (s.$) {
                    case "Scope": {
                      const $f961 = s._0;
                      const $f962 = s._1;
                      {
                        const inner = $f962;
                        {
                          const ik = $f961;
                          {
                            let $t960;
                            {
                              let $t959;
                              {
                                const $rc_88 = Authority$kind_subsumes(k, ik);
                                $t959 = $rc_88;
                              }
                              if ($t959 === true) {
                                $t960 = Authority$arg_subsumes(outer, inner);
                              } else {
                                $t960 = false;
                              }
                            }
                            if ($t960 === true) {
                              return true;
                            } else {
                              {
                                $tco_a0 = s;
                                $tco_a1 = rest;
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
const Authority$covered$clo = { _0: ($_, s, b) => Authority$covered(s, b) };

function Authority$arg_subsumes(outer, inner) {
  switch (outer.$) {
    case "Any": {
      return true;
      break;
    }
    case "Paths": {
      const $f990 = outer._0;
      {
        const o_paths = $f990;
        {
          const $t979 = Authority$path_list(inner);
          switch ($t979.$) {
            case "Some": {
              const $f980 = $t979._0;
              {
                const i_paths = $f980;
                {
                  const $rc_89 = Authority$all_paths_within(i_paths, o_paths);
                  return $rc_89;
                }
              }
              break;
            }
            case "None": {
              return false;
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
    case "PathsAt": {
      const $f991 = outer._0;
      {
        const o_paths = $f991;
        {
          const $t981 = Authority$path_list(inner);
          switch ($t981.$) {
            case "Some": {
              const $f982 = $t981._0;
              {
                const i_paths = $f982;
                {
                  const $rc_90 = Authority$all_paths_within(i_paths, o_paths);
                  return $rc_90;
                }
              }
              break;
            }
            case "None": {
              return false;
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
    case "Names": {
      const $f992 = outer._0;
      const $f993 = outer._1;
      {
        const o_pre = $f993;
        {
          const o_names = $f992;
          switch (inner.$) {
            case "Names": {
              const $f984 = inner._0;
              const $f985 = inner._1;
              {
                const i_pre = $f985;
                {
                  const i_names = $f984;
                  {
                    let $t983;
                    {
                      const $rc_92 = Authority$all_names_admitted(i_names, o_names, o_pre);
                      $t983 = $rc_92;
                    }
                    if ($t983 === true) {
                      {
                        const $rc_91 = Authority$all_prefixes_under(i_pre, o_pre);
                        return $rc_91;
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
              return false;
            }
          }
        }
      }
      break;
    }
    case "Hosts": {
      const $f998 = outer._0;
      {
        const o = $f998;
        {
          const $t986 = Authority$host_spec(inner);
          switch ($t986.$) {
            case "Some": {
              const $f987 = $t986._0;
              {
                const i = $f987;
                {
                  const $rc_93 = Authority$host_subsumes(o, i);
                  return $rc_93;
                }
              }
              break;
            }
            case "None": {
              return false;
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
    case "HostAt": {
      const $f999 = outer._0;
      const $f1000 = outer._1;
      const $f1001 = outer._2;
      const $f1002 = outer._3;
      {
        const o = $f999;
        {
          const $t988 = Authority$host_spec(inner);
          switch ($t988.$) {
            case "Some": {
              const $f989 = $t988._0;
              {
                const i = $f989;
                {
                  const $rc_94 = Authority$host_subsumes(o, i);
                  return $rc_94;
                }
              }
              break;
            }
            case "None": {
              return false;
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
const Authority$arg_subsumes$clo = { _0: ($_, outer, inner) => Authority$arg_subsumes(outer, inner) };

function Authority$path_list(a) {
  switch (a.$) {
    case "Paths": {
      const $f1015 = a._0;
      {
        const ps = $f1015;
        return { $: "Some", _0: ps };
      }
      break;
    }
    case "PathsAt": {
      const $f1020 = a._0;
      {
        const ps = $f1020;
        return { $: "Some", _0: ps };
      }
      break;
    }
    default: {
      return { $: "None" };
    }
  }
}
const Authority$path_list$clo = { _0: ($_, a) => Authority$path_list(a) };

function Authority$host_spec(a) {
  switch (a.$) {
    case "Hosts": {
      const $f1025 = a._0;
      {
        const s = $f1025;
        return { $: "Some", _0: s };
      }
      break;
    }
    case "HostAt": {
      const $f1030 = a._0;
      const $f1031 = a._1;
      const $f1032 = a._2;
      const $f1033 = a._3;
      {
        const s = $f1030;
        return { $: "Some", _0: s };
      }
      break;
    }
    default: {
      return { $: "None" };
    }
  }
}
const Authority$host_spec$clo = { _0: ($_, a) => Authority$host_spec(a) };

function Authority$all_paths_within($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const i_paths = $tco_a0;
    const o_paths = $tco_a1;
    switch (i_paths.$) {
      case "Nil": {
        return true;
        break;
      }
      case "Cons": {
        const $f1051 = i_paths._0;
        const $f1052 = i_paths._1;
        {
          const rest = $f1052;
          {
            const p = $f1051;
            {
              const $t1050 = Authority$path_in_any(p, o_paths);
              if ($t1050 === true) {
                {
                  $tco_a0 = rest;
                  $tco_a1 = o_paths;
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
const Authority$all_paths_within$clo = { _0: ($_, i_paths, o_paths) => Authority$all_paths_within(i_paths, o_paths) };

function Authority$path_in_any($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const p = $tco_a0;
    const o_paths = $tco_a1;
    switch (o_paths.$) {
      case "Nil": {
        return false;
        break;
      }
      case "Cons": {
        const $f1058 = o_paths._0;
        const $f1059 = o_paths._1;
        {
          const rest = $f1059;
          {
            const o = $f1058;
            {
              const $t1057 = Authority$path_within(o, p);
              if ($t1057 === true) {
                return true;
              } else {
                {
                  $tco_a0 = p;
                  $tco_a1 = rest;
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
const Authority$path_in_any$clo = { _0: ($_, p, o_paths) => Authority$path_in_any(p, o_paths) };

function Authority$all_names_admitted($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const ns = $tco_a0;
    const o_names = $tco_a1;
    const o_pre = $tco_a2;
    switch (ns.$) {
      case "Nil": {
        return true;
        break;
      }
      case "Cons": {
        const $f1065 = ns._0;
        const $f1066 = ns._1;
        {
          const rest = $f1066;
          {
            const n = $f1065;
            {
              let $t1064;
              {
                const $t1128_i104 = Authority$member(o_names, n);
                if ($t1128_i104 === true) {
                  $t1064 = true;
                } else {
                  $t1064 = Authority$starts_with_any(n, o_pre);
                }
              }
              if ($t1064 === true) {
                {
                  $tco_a0 = rest;
                  $tco_a1 = o_names;
                  $tco_a2 = o_pre;
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
const Authority$all_names_admitted$clo = { _0: ($_, ns, o_names, o_pre) => Authority$all_names_admitted(ns, o_names, o_pre) };

function Authority$all_prefixes_under($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const i_pre = $tco_a0;
    const o_pre = $tco_a1;
    switch (i_pre.$) {
      case "Nil": {
        return true;
        break;
      }
      case "Cons": {
        const $f1072 = i_pre._0;
        const $f1073 = i_pre._1;
        {
          const rest = $f1073;
          {
            const p = $f1072;
            {
              const $t1071 = Authority$starts_with_any(p, o_pre);
              if ($t1071 === true) {
                {
                  $tco_a0 = rest;
                  $tco_a1 = o_pre;
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
const Authority$all_prefixes_under$clo = { _0: ($_, i_pre, o_pre) => Authority$all_prefixes_under(i_pre, o_pre) };

function Authority$kind_subsumes($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const parent = $tco_a0;
    const child = $tco_a1;
    {
      const $t1081 = (parent === child);
      if ($t1081 === true) {
        return true;
      } else {
        {
          let p;
          if (child === "IO.Console") {
            p = "IO";
          } else if (child === "IO.FileSystem") {
            p = "IO";
          } else if (child === "IO.FileRead") {
            p = "IO.FileSystem";
          } else if (child === "IO.FileWrite") {
            p = "IO.FileSystem";
          } else if (child === "IO.Network") {
            p = "IO";
          } else if (child === "IO.NetConnect") {
            p = "IO.Network";
          } else if (child === "IO.NetListen") {
            p = "IO.Network";
          } else if (child === "IO.Process") {
            p = "IO";
          } else if (child === "IO.Clock") {
            p = "IO";
          } else if (child === "IO.Random") {
            p = "IO";
          } else if (child === "IO.Signal") {
            p = "IO";
          } else if (child === "IO.Database") {
            p = "IO.NetConnect";
          } else if (child === "IO.Spawn") {
            p = "IO";
          } else if (child === "IO.Mut") {
            p = "IO";
          } else if (child === "IO.Telemetry") {
            p = "IO";
          } else if (child === "IO.NetConnect.TLS") {
            p = "IO.NetConnect";
          } else if (child === "IO.WebSocket") {
            p = "IO.NetConnect";
          } else if (child === "IO.Foreign") {
            p = "IO";
          } else if (child === "IO.Foreign.Blocking") {
            p = "IO.Foreign";
          } else if (child === "IO.Registry") {
            p = "IO";
          } else {
            p = "";
          }
          {
            const $t1082 = (p === "");
            if ($t1082 === true) {
              return false;
            } else {
              {
                $tco_a0 = parent;
                $tco_a1 = p;
                continue __tco;
              }
            }
          }
        }
      }
    }
    return undefined;
  }
}
const Authority$kind_subsumes$clo = { _0: ($_, parent, child) => Authority$kind_subsumes(parent, child) };

function Authority$fold_segments($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const parts = $tco_a0;
    const acc = $tco_a1;
    switch (parts.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f1102 = parts._0;
        const $f1103 = parts._1;
        {
          const rest = $f1103;
          {
            const s = $f1102;
            {
              let $t1092;
              {
                const $t1091 = (s === "");
                if ($t1091 === true) {
                  $t1092 = true;
                } else {
                  $t1092 = (s === ".");
                }
              }
              if ($t1092 === true) {
                {
                  $tco_a0 = rest;
                  $tco_a1 = acc;
                  continue __tco;
                }
              } else {
                {
                  const $t1093 = (s === "..");
                  if ($t1093 === true) {
                    switch (acc.$) {
                      case "Nil": {
                        {
                          const $t1094 = { $: "Nil" };
                          {
                            $tco_a0 = rest;
                            $tco_a1 = $t1094;
                            continue __tco;
                          }
                        }
                        break;
                      }
                      case "Cons": {
                        const $f1095 = acc._0;
                        const $f1096 = acc._1;
                        {
                          const up = $f1096;
                          {
                            $tco_a0 = rest;
                            $tco_a1 = up;
                            continue __tco;
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
                      const $t1101 = { $: "Cons", _0: s, _1: acc };
                      {
                        $tco_a0 = rest;
                        $tco_a1 = $t1101;
                        continue __tco;
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
    return undefined;
  }
}
const Authority$fold_segments$clo = { _0: ($_, parts, acc) => Authority$fold_segments(parts, acc) };

function Authority$normalize(p) {
  {
    let body;
    {
      let $t1108;
      {
        const $t1087_i109 = march_string_split(p, "/");
        {
          const $t1088_i110 = { $: "Nil" };
          {
            const $t1089_i111 = Authority$fold_segments($t1087_i109, $t1088_i110);
            {
              const $t1090_i112 = { $: "Nil" };
              $t1108 = Authority$rev($t1089_i111, $t1090_i112);
            }
          }
        }
      }
      {
        const $rc_97 = march_string_join($t1108, "/");
        body = $rc_97;
      }
    }
    {
      const $t1109 = march_string_starts_with(p, "/");
      if ($t1109 === true) {
        {
          const $rc_96 = ("/" + body);
          return $rc_96;
        }
      } else {
        return body;
      }
    }
  }
}
const Authority$normalize$clo = { _0: ($_, p) => Authority$normalize(p) };

function Authority$path_within(scope, p) {
  {
    let $t1112;
    {
      const $t1110 = march_string_starts_with(scope, "/");
      {
        const $t1111 = march_string_starts_with(p, "/");
        $t1112 = ($t1110 === $t1111);
      }
    }
    if ($t1112 === true) {
      {
        let $t1113;
        {
          const $t1087_i119 = march_string_split(scope, "/");
          {
            const $t1088_i120 = { $: "Nil" };
            {
              const $t1089_i121 = Authority$fold_segments($t1087_i119, $t1088_i120);
              {
                const $t1090_i122 = { $: "Nil" };
                $t1113 = Authority$rev($t1089_i121, $t1090_i122);
              }
            }
          }
        }
        {
          let $t1114;
          {
            const $t1087_i114 = march_string_split(p, "/");
            {
              const $t1088_i115 = { $: "Nil" };
              {
                const $t1089_i116 = Authority$fold_segments($t1087_i114, $t1088_i115);
                {
                  const $t1090_i117 = { $: "Nil" };
                  $t1114 = Authority$rev($t1089_i116, $t1090_i117);
                }
              }
            }
          }
          {
            const $rc_98 = Authority$segs_prefix($t1113, $t1114);
            return $rc_98;
          }
        }
      }
    } else {
      return false;
    }
  }
}
const Authority$path_within$clo = { _0: ($_, scope, p) => Authority$path_within(scope, p) };

function Authority$segs_prefix($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const pre = $tco_a0;
    const segs = $tco_a1;
    switch (pre.$) {
      case "Nil": {
        return true;
        break;
      }
      case "Cons": {
        const $f1122 = pre._0;
        const $f1123 = pre._1;
        {
          const pt = $f1123;
          {
            const a = $f1122;
            switch (segs.$) {
              case "Nil": {
                return false;
                break;
              }
              case "Cons": {
                const $f1116 = segs._0;
                const $f1117 = segs._1;
                {
                  const st = $f1117;
                  {
                    const b = $f1116;
                    {
                      const $t1115 = (a === b);
                      if ($t1115 === true) {
                        {
                          $tco_a0 = pt;
                          $tco_a1 = st;
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
const Authority$segs_prefix$clo = { _0: ($_, pre, segs) => Authority$segs_prefix(pre, segs) };

function Authority$starts_with_any($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const n = $tco_a0;
    const pre = $tco_a1;
    switch (pre.$) {
      case "Nil": {
        return false;
        break;
      }
      case "Cons": {
        const $f1130 = pre._0;
        const $f1131 = pre._1;
        {
          const rest = $f1131;
          {
            const p = $f1130;
            {
              const $t1129 = march_string_starts_with(n, p);
              if ($t1129 === true) {
                return true;
              } else {
                {
                  $tco_a0 = n;
                  $tco_a1 = rest;
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
const Authority$starts_with_any$clo = { _0: ($_, n, pre) => Authority$starts_with_any(n, pre) };

function Authority$port_or_zero(s) {
  {
    let $t1187;
    {
      let $t1185;
      {
        const $t1183 = (s === "");
        if ($t1183 === true) {
          $t1185 = true;
        } else {
          {
            const $t1184 = march_string_byte_length(s);
            $t1185 = ($t1184 > 5);
          }
        }
      }
      if ($t1185 === true) {
        $t1187 = true;
      } else {
        {
          const $t1186 = Authority$all_chars(s, "0123456789", 0);
          $t1187 = (!$t1186);
        }
      }
    }
    if ($t1187 === true) {
      return 0;
    } else {
      {
        const $t1188 = march_string_to_int(s);
        switch ($t1188.$) {
          case "Some": {
            const $f1192 = $t1188._0;
            {
              const n = $f1192;
              {
                let $t1191;
                {
                  const $t1189 = (n >= 1);
                  {
                    const $t1190 = (n <= 65535);
                    $t1191 = ($t1189 && $t1190);
                  }
                }
                if ($t1191 === true) {
                  return n;
                } else {
                  return 0;
                }
              }
            }
            break;
          }
          case "None": {
            return 0;
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
const Authority$port_or_zero$clo = { _0: ($_, s) => Authority$port_or_zero(s) };

function Authority$all_chars($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const s = $tco_a0;
    const allowed = $tco_a1;
    const i = $tco_a2;
    {
      let $t1194;
      {
        const $t1193 = march_string_byte_length(s);
        $t1194 = (i >= $t1193);
      }
      if ($t1194 === true) {
        return true;
      } else {
        {
          let $t1196;
          {
            const $t1195 = march_string_slice(s, i, 1);
            {
              const $rc_106 = march_string_contains(allowed, $t1195);
              $t1196 = $rc_106;
            }
          }
          if ($t1196 === true) {
            {
              const $t1197 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
              {
                $tco_a0 = s;
                $tco_a1 = allowed;
                $tco_a2 = $t1197;
                continue __tco;
              }
            }
          } else {
            return false;
          }
        }
      }
    }
    return undefined;
  }
}
const Authority$all_chars$clo = { _0: ($_, s, allowed, i) => Authority$all_chars(s, allowed, i) };

function Authority$parse_host_pattern(raw) {
  {
    const $t1198 = (raw === "");
    if ($t1198 === true) {
      return { $: "Err", _0: "a host scope cannot be empty" };
    } else {
      {
        const $t1199 = march_string_contains(raw, "://");
        if ($t1199 === true) {
          return { $: "Err", _0: "a host scope names a host, not a URL: drop the scheme (`https://`)" };
        } else {
          {
            let $p1212;
            {
              const $t1200 = march_string_index_of(raw, "/");
              switch ($t1200.$) {
                case "None": {
                  {
                    let $t1202;
                    {
                      const $t1201 = { $: "None" };
                      $t1202 = { $: "Ok", _0: $t1201 };
                    }
                    $p1212 = { _0: raw, _1: $t1202 };
                  }
                  break;
                }
                case "Some": {
                  const $f1208 = $t1200._0;
                  {
                    const i = $f1208;
                    {
                      const $t1203 = march_string_slice(raw, 0, i);
                      {
                        let $t1207;
                        {
                          let $t1206;
                          {
                            let $t1205;
                            {
                              const $t1204 = march_string_byte_length(raw);
                              $t1205 = (($t1204 - i) < 4611686018427387904 && ($t1204 - i) >= -4611686018427387904 ? ($t1204 - i) : march_int_ovf(($t1204 - i), 1));
                            }
                            {
                              const $rc_110 = march_string_slice(raw, i, $t1205);
                              $t1206 = $rc_110;
                            }
                          }
                          {
                            const $rc_109 = Authority$parse_scope_path($t1206);
                            $t1207 = $rc_109;
                          }
                        }
                        $p1212 = { _0: $t1203, _1: $t1207 };
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
            {
              const host_raw = $p1212._0;
              {
                const path_r = $p1212._1;
                switch (path_r.$) {
                  case "Err": {
                    const $f1210 = path_r._0;
                    {
                      const e = $f1210;
                      {
                        const $rc_108 = { $: "Err", _0: e };
                        return $rc_108;
                      }
                    }
                    break;
                  }
                  case "Ok": {
                    const $f1211 = path_r._0;
                    {
                      const path = $f1211;
                      {
                        const $t1209 = march_string_to_lowercase(host_raw);
                        return Authority$host_part_pattern($t1209, path);
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
}
const Authority$parse_host_pattern$clo = { _0: ($_, raw) => Authority$parse_host_pattern(raw) };

function Authority$host_part_pattern(s, path) {
  {
    const $t1213 = (s === "");
    if ($t1213 === true) {
      return { $: "Err", _0: "a host scope needs a host before its path" };
    } else {
      {
        const $t1214 = march_string_contains(s, "@");
        if ($t1214 === true) {
          return { $: "Err", _0: "a host scope cannot carry userinfo (`user@`)" };
        } else {
          {
            const $p1239 = Authority$split_host_port(s);
            {
              const host_part = $p1239._0;
              {
                const port_text = $p1239._1;
                {
                  let port;
                  {
                    const $t1215 = (port_text === "");
                    if ($t1215 === true) {
                      port = 0;
                    } else {
                      port = Authority$port_or_zero(port_text);
                    }
                  }
                  {
                    let $t1218;
                    {
                      const $t1216 = (port_text !== "");
                      {
                        const $t1217 = (port === 0);
                        $t1218 = ($t1216 && $t1217);
                      }
                    }
                    if ($t1218 === true) {
                      {
                        const $t1219 = march_string_concat3("`", port_text, "` is not a port (1-65535)");
                        {
                          const $rc_124 = { $: "Err", _0: $t1219 };
                          return $rc_124;
                        }
                      }
                    } else {
                      {
                        const $t1220 = march_string_starts_with(host_part, "[");
                        if ($t1220 === true) {
                          {
                            const n = march_string_byte_length(host_part);
                            {
                              let $t1225;
                              {
                                let $t1222;
                                {
                                  const $t1221 = (n >= 2);
                                  if ($t1221 === true) {
                                    $t1222 = march_string_ends_with(host_part, "]");
                                  } else {
                                    $t1222 = false;
                                  }
                                }
                                if ($t1222 === true) {
                                  {
                                    let $t1224;
                                    {
                                      const $t1223 = ((n - 2) < 4611686018427387904 && (n - 2) >= -4611686018427387904 ? (n - 2) : march_int_ovf((n - 2), 1));
                                      $t1224 = march_string_slice(host_part, 1, $t1223);
                                    }
                                    {
                                      let $rc_111;
                                      {
                                        const $t1267_i124 = ($t1224 !== "");
                                        if ($t1267_i124 === true) {
                                          $rc_111 = Authority$all_chars($t1224, "0123456789abcdef:.", 0);
                                        } else {
                                          $rc_111 = false;
                                        }
                                      }
                                      $t1225 = $rc_111;
                                    }
                                  }
                                } else {
                                  $t1225 = false;
                                }
                              }
                              if ($t1225 === true) {
                                {
                                  let $t1226;
                                  $t1226 = { _0: host_part, _1: false, _2: port, _3: path };
                                  {
                                    const $rc_123 = { $: "Ok", _0: $t1226 };
                                    return $rc_123;
                                  }
                                }
                              } else {
                                {
                                  const $t1227 = march_string_concat3("`", host_part, "` is not an IPv6 literal");
                                  {
                                    const $rc_122 = { $: "Err", _0: $t1227 };
                                    return $rc_122;
                                  }
                                }
                              }
                            }
                          }
                        } else {
                          {
                            let wild;
                            {
                              let $t1229;
                              {
                                const $t1228 = march_string_byte_length(host_part);
                                $t1229 = ($t1228 >= 2);
                              }
                              if ($t1229 === true) {
                                wild = march_string_starts_with(host_part, "*.");
                              } else {
                                wild = false;
                              }
                            }
                            {
                              let name;
                              {
                                let $t1232;
                                if (wild === true) {
                                  {
                                    let $t1231;
                                    {
                                      const $t1230 = march_string_byte_length(host_part);
                                      $t1231 = (($t1230 - 2) < 4611686018427387904 && ($t1230 - 2) >= -4611686018427387904 ? ($t1230 - 2) : march_int_ovf(($t1230 - 2), 1));
                                    }
                                    $t1232 = march_string_slice(host_part, 2, $t1231);
                                  }
                                } else {
                                  $t1232 = host_part;
                                }
                                {
                                  let $rc_112;
                                  {
                                    const l_i14745 = march_string_to_lowercase($t1232);
                                    {
                                      const $t1180_i14746 = march_string_ends_with(l_i14745, ".");
                                      if ($t1180_i14746 === true) {
                                        {
                                          let $t1182_i14748;
                                          {
                                            const $t1181_i14747 = march_string_byte_length(l_i14745);
                                            $t1182_i14748 = (($t1181_i14747 - 1) < 4611686018427387904 && ($t1181_i14747 - 1) >= -4611686018427387904 ? ($t1181_i14747 - 1) : march_int_ovf(($t1181_i14747 - 1), 1));
                                          }
                                          {
                                            const $rc_105_i14749 = march_string_slice(l_i14745, 0, $t1182_i14748);
                                            $rc_112 = $rc_105_i14749;
                                          }
                                        }
                                      } else {
                                        $rc_112 = l_i14745;
                                      }
                                    }
                                  }
                                  name = $rc_112;
                                }
                              }
                              {
                                let $t1234;
                                {
                                  const $t1233 = march_string_contains(name, "*");
                                  if ($t1233 === true) {
                                    $t1234 = true;
                                  } else {
                                    $t1234 = (host_part === "*");
                                  }
                                }
                                if ($t1234 === true) {
                                  {
                                    const $rc_121 = { $: "Err", _0: "a wildcard must be the whole leftmost label (`*.example.com`)" };
                                    return $rc_121;
                                  }
                                } else {
                                  {
                                    let $t1236;
                                    {
                                      let $t1235;
                                      {
                                        const $t1268_i9703 = (name !== "");
                                        if ($t1268_i9703 === true) {
                                          {
                                            const $t1269_i9704 = march_string_split(name, ".");
                                            {
                                              const $rc_129_i9705 = Authority$labels_ok($t1269_i9704);
                                              $t1235 = $rc_129_i9705;
                                            }
                                          }
                                        } else {
                                          $t1235 = false;
                                        }
                                      }
                                      $t1236 = (!$t1235);
                                    }
                                    if ($t1236 === true) {
                                      {
                                        const $t1237 = march_string_concat3("`", host_part, "` is not a host name: labels are letters, digits and `-`, separated by single dots");
                                        {
                                          const $rc_120 = { $: "Err", _0: $t1237 };
                                          return $rc_120;
                                        }
                                      }
                                    } else {
                                      {
                                        const $t1238 = { _0: name, _1: wild, _2: port, _3: path };
                                        {
                                          const $rc_119 = { $: "Ok", _0: $t1238 };
                                          return $rc_119;
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
const Authority$host_part_pattern$clo = { _0: ($_, s, path) => Authority$host_part_pattern(s, path) };

function Authority$split_host_port(s) {
  {
    const $t1240 = march_string_starts_with(s, "[");
    if ($t1240 === true) {
      {
        const $t1241 = march_string_index_of(s, "]");
        switch ($t1241.$) {
          case "None": {
            return { _0: s, _1: "" };
            break;
          }
          case "Some": {
            const $f1256 = $t1241._0;
            {
              const i = $f1256;
              {
                let rest;
                {
                  const $t1242 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                  {
                    let $t1245;
                    {
                      let $t1244;
                      {
                        const $t1243 = march_string_byte_length(s);
                        $t1244 = (($t1243 - i) < 4611686018427387904 && ($t1243 - i) >= -4611686018427387904 ? ($t1243 - i) : march_int_ovf(($t1243 - i), 1));
                      }
                      $t1245 = (($t1244 - 1) < 4611686018427387904 && ($t1244 - 1) >= -4611686018427387904 ? ($t1244 - 1) : march_int_ovf(($t1244 - 1), 1));
                    }
                    rest = march_string_slice(s, $t1242, $t1245);
                  }
                }
                {
                  const $t1246 = (rest === "");
                  if ($t1246 === true) {
                    {
                      let $t1248;
                      {
                        const $t1247 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                        {
                          const $rc_125 = march_string_slice(s, 0, $t1247);
                          $t1248 = $rc_125;
                        }
                      }
                      return { _0: $t1248, _1: "" };
                    }
                  } else {
                    {
                      const $t1249 = march_string_starts_with(rest, ":");
                      if ($t1249 === true) {
                        {
                          let $t1251;
                          {
                            const $t1250 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                            {
                              const $rc_127 = march_string_slice(s, 0, $t1250);
                              $t1251 = $rc_127;
                            }
                          }
                          {
                            let $t1255;
                            {
                              let $t1254;
                              {
                                let $t1253;
                                {
                                  const $t1252 = march_string_byte_length(rest);
                                  $t1253 = (($t1252 - 1) < 4611686018427387904 && ($t1252 - 1) >= -4611686018427387904 ? ($t1252 - 1) : march_int_ovf(($t1252 - 1), 1));
                                }
                                {
                                  const $rc_126 = march_string_slice(rest, 1, $t1253);
                                  $t1254 = $rc_126;
                                }
                              }
                              $t1255 = Authority$port_text_of($t1254);
                            }
                            return { _0: $t1251, _1: $t1255 };
                          }
                        }
                      } else {
                        return { _0: s, _1: "" };
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
    } else {
      {
        const $t1257 = march_string_last_index_of(s, ":");
        switch ($t1257.$) {
          case "None": {
            return { _0: s, _1: "" };
            break;
          }
          case "Some": {
            const $f1265 = $t1257._0;
            {
              const i = $f1265;
              {
                const $t1258 = march_string_slice(s, 0, i);
                {
                  let $t1264;
                  {
                    let $t1263;
                    {
                      const $t1259 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                      {
                        let $t1262;
                        {
                          let $t1261;
                          {
                            const $t1260 = march_string_byte_length(s);
                            $t1261 = (($t1260 - i) < 4611686018427387904 && ($t1260 - i) >= -4611686018427387904 ? ($t1260 - i) : march_int_ovf(($t1260 - i), 1));
                          }
                          $t1262 = (($t1261 - 1) < 4611686018427387904 && ($t1261 - 1) >= -4611686018427387904 ? ($t1261 - 1) : march_int_ovf(($t1261 - 1), 1));
                        }
                        {
                          const $rc_128 = march_string_slice(s, $t1259, $t1262);
                          $t1263 = $rc_128;
                        }
                      }
                    }
                    $t1264 = Authority$port_text_of($t1263);
                  }
                  return { _0: $t1258, _1: $t1264 };
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
const Authority$split_host_port$clo = { _0: ($_, s) => Authority$split_host_port(s) };

function Authority$port_text_of(p) {
  {
    const $t1266 = (p === "");
    if ($t1266 === true) {
      return ":";
    } else {
      return p;
    }
  }
}
const Authority$port_text_of$clo = { _0: ($_, p) => Authority$port_text_of(p) };

function Authority$labels_ok($tco_a0) {
  __tco: for (;;) {
    const ls = $tco_a0;
    switch (ls.$) {
      case "Nil": {
        return true;
        break;
      }
      case "Cons": {
        const $f1272 = ls._0;
        const $f1273 = ls._1;
        {
          const rest = $f1273;
          {
            const l = $f1272;
            {
              let $t1271;
              {
                const $t1270 = (l !== "");
                if ($t1270 === true) {
                  $t1271 = Authority$all_chars(l, "abcdefghijklmnopqrstuvwxyz0123456789-", 0);
                } else {
                  $t1271 = false;
                }
              }
              if ($t1271 === true) {
                {
                  $tco_a0 = rest;
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
const Authority$labels_ok$clo = { _0: ($_, ls) => Authority$labels_ok(ls) };

function Authority$parse_scope_path(p) {
  {
    const $t1278 = march_string_split(p, "/");
    {
      let $t1279;
      {
        const l_i9713 = $t1278;
        switch (l_i9713.$) {
          case "Cons": {
            const $f1289_i9714 = l_i9713._0;
            const $f1290_i9715 = l_i9713._1;
            {
              const rest_i9716 = $f1290_i9715;
              $t1279 = rest_i9716;
            }
            break;
          }
          case "Nil": {
            $t1279 = { $: "Nil" };
            break;
          }
          default: {
            throw march_panic_error("panic: ", "non-exhaustive pattern match");
            break;
          }
        }
      }
      {
        let parts;
        {
          const l_i9706 = $t1279;
          {
            const $t1295_i9707 = { $: "Nil" };
            {
              let $t1296_i9708;
              $t1296_i9708 = Authority$rev($t1279, $t1295_i9707);
              switch ($t1296_i9708.$) {
                case "Cons": {
                  const $f1298_i9709 = $t1296_i9708._0;
                  const $f1299_i9710 = $t1296_i9708._1;
                  if ($f1298_i9709 === "") {
                    {
                      const r_i9711 = $f1299_i9710;
                      {
                        const $t1297_i9712 = { $: "Nil" };
                        parts = Authority$rev(r_i9711, $t1297_i9712);
                      }
                    }
                  } else {
                    parts = $t1279;
                  }
                  break;
                }
                default: {
                  parts = $t1279;
                  break;
                }
              }
            }
          }
        }
        {
          let $t1280;
          $t1280 = Authority$bad_scope_segment(parts);
          switch ($t1280.$) {
            case "None": {
              {
                const $t1281 = { $: "Some", _0: parts };
                return { $: "Ok", _0: $t1281 };
              }
              break;
            }
            case "Some": {
              const $f1286 = $t1280._0;
              if ($f1286 === "") {
                return { $: "Err", _0: "a path scope cannot contain `//`" };
              } else {
                {
                  const seg = $f1286;
                  {
                    let $t1283;
                    {
                      const $t1282 = (seg === ".");
                      if ($t1282 === true) {
                        $t1283 = true;
                      } else {
                        $t1283 = (seg === "..");
                      }
                    }
                    if ($t1283 === true) {
                      {
                        let $t1284;
                        {
                          const $rc_130 = march_string_concat3("a path scope cannot contain a `", seg, "` segment");
                          $t1284 = $rc_130;
                        }
                        return { $: "Err", _0: $t1284 };
                      }
                    } else {
                      {
                        let $t1285;
                        {
                          const $rc_131 = march_string_concat3("the path segment `", seg, "` may contain only letters, digits, `-`, `_`, `.` and `~` (no `%`, `?`, `#` or `\\`)");
                          $t1285 = $rc_131;
                        }
                        return { $: "Err", _0: $t1285 };
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
const Authority$parse_scope_path$clo = { _0: ($_, p) => Authority$parse_scope_path(p) };

function Authority$bad_scope_segment($tco_a0) {
  __tco: for (;;) {
    const segs = $tco_a0;
    switch (segs.$) {
      case "Nil": {
        return { $: "None" };
        break;
      }
      case "Cons": {
        const $f1305 = segs._0;
        const $f1306 = segs._1;
        {
          const rest = $f1306;
          {
            const s = $f1305;
            {
              let $t1304;
              {
                let $t1302;
                {
                  let $t1301;
                  {
                    const $t1300 = (s === "");
                    if ($t1300 === true) {
                      $t1301 = true;
                    } else {
                      $t1301 = (s === ".");
                    }
                  }
                  if ($t1301 === true) {
                    $t1302 = true;
                  } else {
                    $t1302 = (s === "..");
                  }
                }
                if ($t1302 === true) {
                  $t1304 = true;
                } else {
                  {
                    const $t1303 = Authority$all_chars(s, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~", 0);
                    $t1304 = (!$t1303);
                  }
                }
              }
              if ($t1304 === true) {
                return { $: "Some", _0: s };
              } else {
                {
                  $tco_a0 = rest;
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
const Authority$bad_scope_segment$clo = { _0: ($_, segs) => Authority$bad_scope_segment(segs) };

function Authority$host_options($tco_a0, $tco_a1, $tco_a2, $tco_a3) {
  __tco: for (;;) {
    const opts = $tco_a0;
    const nr = $tco_a1;
    const mg = $tco_a2;
    const ms = $tco_a3;
    switch (opts.$) {
      case "Nil": {
        {
          const $t1311 = { _0: nr, _1: mg, _2: ms };
          return { $: "Ok", _0: $t1311 };
        }
        break;
      }
      case "Cons": {
        const $f1323 = opts._0;
        const $f1324 = opts._1;
        {
          const rest = $f1324;
          {
            const o = $f1323;
            {
              const $t1312 = (o === "no_redirects");
              if ($t1312 === true) {
                if (nr === true) {
                  return { $: "Err", _0: "`no_redirects` is given twice" };
                } else {
                  {
                    $tco_a0 = rest;
                    $tco_a1 = true;
                    $tco_a2 = mg;
                    $tco_a3 = ms;
                    continue __tco;
                  }
                }
              } else {
                {
                  const $t1313 = march_string_starts_with(o, "methods=");
                  if ($t1313 === true) {
                    if (mg === true) {
                      return { $: "Err", _0: "`methods(...)` is given twice" };
                    } else {
                      {
                        let v;
                        {
                          let $t1315;
                          {
                            const $t1314 = march_string_byte_length(o);
                            $t1315 = (($t1314 - 8) < 4611686018427387904 && ($t1314 - 8) >= -4611686018427387904 ? ($t1314 - 8) : march_int_ovf(($t1314 - 8), 1));
                          }
                          v = march_string_slice(o, 8, $t1315);
                        }
                        {
                          let $t1317;
                          {
                            const $t1316 = march_string_split(v, ",");
                            $t1317 = Authority$bad_method($t1316);
                          }
                          switch ($t1317.$) {
                            case "None": {
                              {
                                const $t1318 = (v === "");
                                if ($t1318 === true) {
                                  return { $: "Err", _0: "`methods(...)` needs at least one method" };
                                } else {
                                  {
                                    let $t1319;
                                    {
                                      const $rc_132 = march_string_split(v, ",");
                                      $t1319 = $rc_132;
                                    }
                                    {
                                      $tco_a0 = rest;
                                      $tco_a1 = nr;
                                      $tco_a2 = true;
                                      $tco_a3 = $t1319;
                                      continue __tco;
                                    }
                                  }
                                }
                              }
                              break;
                            }
                            case "Some": {
                              const $f1321 = $t1317._0;
                              {
                                const m = $f1321;
                                {
                                  let $t1320;
                                  {
                                    const $rc_133 = march_string_concat3("`", m, "` is not an HTTP method a scope can name; use `get`, `head`, `post`, `put`, `patch`, `delete`, `options`");
                                    $t1320 = $rc_133;
                                  }
                                  return { $: "Err", _0: $t1320 };
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
                  } else {
                    {
                      const $t1322 = march_string_concat3("unknown option `", o, "`: the options are `no_redirects` and `methods(...)`");
                      return { $: "Err", _0: $t1322 };
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
const Authority$host_options$clo = { _0: ($_, opts, nr, mg, ms) => Authority$host_options(opts, nr, mg, ms) };

function Authority$bad_method($tco_a0) {
  __tco: for (;;) {
    const ms = $tco_a0;
    switch (ms.$) {
      case "Nil": {
        return { $: "None" };
        break;
      }
      case "Cons": {
        const $f1338 = ms._0;
        const $f1339 = ms._1;
        {
          const rest = $f1339;
          {
            const m = $f1338;
            {
              let $t1337;
              {
                const $t1329 = { $: "Nil" };
                {
                  const $t1330 = { $: "Cons", _0: "options", _1: $t1329 };
                  {
                    const $t1331 = { $: "Cons", _0: "delete", _1: $t1330 };
                    {
                      const $t1332 = { $: "Cons", _0: "patch", _1: $t1331 };
                      {
                        const $t1333 = { $: "Cons", _0: "put", _1: $t1332 };
                        {
                          const $t1334 = { $: "Cons", _0: "post", _1: $t1333 };
                          {
                            const $t1335 = { $: "Cons", _0: "head", _1: $t1334 };
                            {
                              const $t1336 = { $: "Cons", _0: "get", _1: $t1335 };
                              {
                                const $rc_134 = Authority$member($t1336, m);
                                $t1337 = $rc_134;
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              if ($t1337 === true) {
                {
                  $tco_a0 = rest;
                  continue __tco;
                }
              } else {
                return { $: "Some", _0: m };
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
const Authority$bad_method$clo = { _0: ($_, ms) => Authority$bad_method(ms) };

function Authority$host_decl(spec) {
  {
    const $t1344 = march_string_split(spec, ";");
    switch ($t1344.$) {
      case "Nil": {
        return { $: "Err", _0: "a host scope cannot be empty" };
        break;
      }
      case "Cons": {
        const $f1371 = $t1344._0;
        const $f1372 = $t1344._1;
        {
          const opts = $f1372;
          {
            const p = $f1371;
            {
              let $t1346;
              {
                const $t1345 = (p === "");
                if ($t1345 === true) {
                  switch (opts.$) {
                    case "Nil": {
                      $t1346 = true;
                      break;
                    }
                    default: {
                      $t1346 = false;
                      break;
                    }
                  }
                } else {
                  $t1346 = false;
                }
              }
              if ($t1346 === true) {
                return { $: "Err", _0: "a host scope cannot be empty" };
              } else {
                {
                  let pat_ok;
                  {
                    const $t1347 = (p === "");
                    if ($t1347 === true) {
                      {
                        const $t1348 = {  };
                        pat_ok = { $: "Ok", _0: $t1348 };
                      }
                    } else {
                      {
                        let $t1349;
                        $t1349 = Authority$parse_host_pattern(p);
                        switch ($t1349.$) {
                          case "Ok": {
                            const $f1351 = $t1349._0;
                            {
                              const $t1350 = {  };
                              pat_ok = { $: "Ok", _0: $t1350 };
                            }
                            break;
                          }
                          case "Err": {
                            const $f1352 = $t1349._0;
                            {
                              const e = $f1352;
                              pat_ok = { $: "Err", _0: e };
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
                  }
                  switch (pat_ok.$) {
                    case "Err": {
                      const $f1369 = pat_ok._0;
                      {
                        const e = $f1369;
                        return { $: "Err", _0: e };
                      }
                      break;
                    }
                    case "Ok": {
                      const $f1370 = pat_ok._0;
                      {
                        let $t1354;
                        {
                          const $t1353 = { $: "Nil" };
                          {
                            const $rc_135 = Authority$host_options(opts, false, false, $t1353);
                            $t1354 = $rc_135;
                          }
                        }
                        switch ($t1354.$) {
                          case "Err": {
                            const $f1356 = $t1354._0;
                            {
                              const e = $f1356;
                              return { $: "Err", _0: e };
                            }
                            break;
                          }
                          case "Ok": {
                            const $f1357 = $t1354._0;
                            const $f1358 = $f1357._0;
                            const $f1359 = $f1357._1;
                            const $f1360 = $f1357._2;
                            {
                              const ms = $f1360;
                              {
                                const mg = $f1359;
                                {
                                  const nr = $f1358;
                                  {
                                    const $t1355 = { _0: p, _1: nr, _2: mg, _3: ms };
                                    return { $: "Ok", _0: $t1355 };
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
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
  }
}
const Authority$host_decl$clo = { _0: ($_, spec) => Authority$host_decl(spec) };

function Authority$host_subsumes(o, i) {
  {
    const $t1377 = Authority$host_decl(o);
    {
      const $t1378 = Authority$host_decl(i);
      {
        const $t1379 = { _0: $t1377, _1: $t1378 };
        const $f1386 = $t1379._0;
        const $f1387 = $t1379._1;
        switch ($f1386.$) {
          case "Ok": {
            const $f1388 = $f1386._0;
            const $f1389 = $f1388._0;
            const $f1390 = $f1388._1;
            const $f1391 = $f1388._2;
            const $f1392 = $f1388._3;
            switch ($f1387.$) {
              case "Ok": {
                const $f1393 = $f1387._0;
                const $f1394 = $f1393._0;
                const $f1395 = $f1393._1;
                const $f1396 = $f1393._2;
                const $f1397 = $f1393._3;
                {
                  const ims = $f1397;
                  {
                    const img = $f1396;
                    {
                      const inr = $f1395;
                      {
                        const i_pre = $f1394;
                        {
                          const oms = $f1392;
                          {
                            const omg = $f1391;
                            {
                              const onr = $f1390;
                              {
                                const o_pre = $f1389;
                                {
                                  let $t1383;
                                  {
                                    let $t1381;
                                    {
                                      const $t1380 = (!onr);
                                      $t1381 = ($t1380 || inr);
                                    }
                                    if ($t1381 === true) {
                                      {
                                        const $t1382 = (!omg);
                                        if ($t1382 === true) {
                                          $t1383 = true;
                                        } else {
                                          if (img === true) {
                                            {
                                              const $rc_136 = Authority$all_member(ims, oms);
                                              $t1383 = $rc_136;
                                            }
                                          } else {
                                            $t1383 = false;
                                          }
                                        }
                                      }
                                    } else {
                                      $t1383 = false;
                                    }
                                  }
                                  if ($t1383 === true) {
                                    {
                                      const $t1384 = (o_pre === "");
                                      if ($t1384 === true) {
                                        return true;
                                      } else {
                                        {
                                          const $t1385 = (i_pre !== "");
                                          if ($t1385 === true) {
                                            return Authority$pattern_subsumes(o_pre, i_pre);
                                          } else {
                                            return false;
                                          }
                                        }
                                      }
                                    }
                                  } else {
                                    return false;
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
                return false;
              }
            }
            break;
          }
          default: {
            return false;
          }
        }
      }
    }
  }
}
const Authority$host_subsumes$clo = { _0: ($_, o, i) => Authority$host_subsumes(o, i) };

function Authority$pattern_subsumes(o, i) {
  {
    const $t1398 = Authority$parse_host_pattern(o);
    {
      const $t1399 = Authority$parse_host_pattern(i);
      {
        const $t1400 = { _0: $t1398, _1: $t1399 };
        const $f1409 = $t1400._0;
        const $f1410 = $t1400._1;
        switch ($f1409.$) {
          case "Ok": {
            const $f1411 = $f1409._0;
            const $f1412 = $f1411._0;
            const $f1413 = $f1411._1;
            const $f1414 = $f1411._2;
            const $f1415 = $f1411._3;
            switch ($f1410.$) {
              case "Ok": {
                const $f1416 = $f1410._0;
                const $f1417 = $f1416._0;
                const $f1418 = $f1416._1;
                const $f1419 = $f1416._2;
                const $f1420 = $f1416._3;
                {
                  const ipath = $f1420;
                  {
                    const iport = $f1419;
                    {
                      const iw = $f1418;
                      {
                        const ih = $f1417;
                        {
                          const opath = $f1415;
                          {
                            const oport = $f1414;
                            {
                              const ow = $f1413;
                              {
                                const oh = $f1412;
                                {
                                  let host_ok;
                                  if (ow === true) {
                                    {
                                      let $t1401;
                                      if (iw === true) {
                                        $t1401 = (ih === oh);
                                      } else {
                                        $t1401 = false;
                                      }
                                      if ($t1401 === true) {
                                        host_ok = true;
                                      } else {
                                        {
                                          let $t1402;
                                          {
                                            const $rc_139 = ("." + oh);
                                            $t1402 = $rc_139;
                                          }
                                          {
                                            const $rc_138 = march_string_ends_with(ih, $t1402);
                                            host_ok = $rc_138;
                                          }
                                        }
                                      }
                                    }
                                  } else {
                                    {
                                      const $t1403 = (!iw);
                                      if ($t1403 === true) {
                                        {
                                          const $rc_140 = (ih === oh);
                                          host_ok = $rc_140;
                                        }
                                      } else {
                                        host_ok = false;
                                      }
                                    }
                                  }
                                  {
                                    let port_ok;
                                    {
                                      const $t1404 = (oport === 0);
                                      {
                                        const $t1405 = (oport === iport);
                                        port_ok = ($t1404 || $t1405);
                                      }
                                    }
                                    {
                                      let path_ok;
                                      switch (opath.$) {
                                        case "None": {
                                          path_ok = true;
                                          break;
                                        }
                                        case "Some": {
                                          const $f1407 = opath._0;
                                          {
                                            const o_paths = $f1407;
                                            switch (ipath.$) {
                                              case "None": {
                                                path_ok = false;
                                                break;
                                              }
                                              case "Some": {
                                                const $f1406 = ipath._0;
                                                {
                                                  const i_paths = $f1406;
                                                  {
                                                    const $rc_137 = Authority$segs_prefix(o_paths, i_paths);
                                                    path_ok = $rc_137;
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
                                          break;
                                        }
                                        default: {
                                          throw march_panic_error("panic: ", "non-exhaustive pattern match");
                                          break;
                                        }
                                      }
                                      {
                                        const $t1408 = (host_ok && port_ok);
                                        return ($t1408 && path_ok);
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
                return false;
              }
            }
            break;
          }
          default: {
            return false;
          }
        }
      }
    }
  }
}
const Authority$pattern_subsumes$clo = { _0: ($_, o, i) => Authority$pattern_subsumes(o, i) };

function Authority$parse(text) {
  {
    let $t1423;
    {
      const $t1421 = march_string_byte_length(text);
      {
        const $t1422 = { $: "Nil" };
        $t1423 = Authority$tokenize(text, 0, $t1421, $t1422);
      }
    }
    switch ($t1423.$) {
      case "Err": {
        const $f1443 = $t1423._0;
        {
          const e = $f1443;
          return { $: "Err", _0: e };
        }
        break;
      }
      case "Ok": {
        const $f1444 = $t1423._0;
        {
          const toks = $f1444;
          switch (toks.$) {
            case "Nil": {
              {
                const $t1424 = { $: "Nil" };
                return { $: "Ok", _0: $t1424 };
              }
              break;
            }
            case "Cons": {
              const $f1429 = toks._0;
              const $f1430 = toks._1;
              {
                const $jp_clo1432 = { $: "$Clo_$jp1_Authority_parse$0_Authority_parse", _0: $jp1_Authority_parse$apply$0_Authority_parse, _1: toks };
                if ($f1429 === "(") {
                  {
                    const $jp_clo1434 = { $: "$Clo_$jp2_Authority_parse$1_Authority_parse", _0: $jp2_Authority_parse$apply$1_Authority_parse, _1: $jp_clo1432 };
                    switch ($f1430.$) {
                      case "Cons": {
                        const $f1435 = $f1430._0;
                        const $f1436 = $f1430._1;
                        {
                          const $jp_clo1438 = { $: "$Clo_$jp3_Authority_parse$2_Authority_parse", _0: $jp3_Authority_parse$apply$2_Authority_parse, _1: $jp_clo1434 };
                          if ($f1435 === ")") {
                            switch ($f1436.$) {
                              case "Nil": {
                                {
                                  const $t1425 = { $: "Nil" };
                                  return { $: "Ok", _0: $t1425 };
                                }
                                break;
                              }
                              default: {
                                return $jp3_Authority_parse$apply$2_Authority_parse($jp_clo1438);
                              }
                            }
                          } else {
                            return $jp3_Authority_parse$apply$2_Authority_parse($jp_clo1438);
                          }
                        }
                        break;
                      }
                      default: {
                        return $jp2_Authority_parse$apply$1_Authority_parse($jp_clo1434);
                      }
                    }
                  }
                } else {
                  return $jp1_Authority_parse$apply$0_Authority_parse($jp_clo1432);
                }
              }
              break;
            }
            default: {
              {
                const $t1426 = { $: "Nil" };
                return Authority$parse_entries(toks, $t1426);
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
const Authority$parse$clo = { _0: ($_, text) => Authority$parse(text) };

function Authority$tokenize($tco_a0, $tco_a1, $tco_a2, $tco_a3) {
  __tco: for (;;) {
    const s = $tco_a0;
    const i = $tco_a1;
    const n = $tco_a2;
    const acc = $tco_a3;
    {
      const $t1445 = (i >= n);
      if ($t1445 === true) {
        {
          const $t1446 = { $: "Nil" };
          {
            const $t1447 = Authority$rev(acc, $t1446);
            return { $: "Ok", _0: $t1447 };
          }
        }
      } else {
        {
          const c = march_string_slice(s, i, 1);
          {
            let $t1451;
            {
              let $t1450;
              {
                let $t1449;
                {
                  const $t1448 = (c === " ");
                  if ($t1448 === true) {
                    $t1449 = true;
                  } else {
                    $t1449 = (c === "\t");
                  }
                }
                if ($t1449 === true) {
                  $t1450 = true;
                } else {
                  $t1450 = (c === "\n");
                }
              }
              if ($t1450 === true) {
                $t1451 = true;
              } else {
                $t1451 = (c === "\r");
              }
            }
            if ($t1451 === true) {
              {
                const $t1452 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                {
                  $tco_a0 = s;
                  $tco_a1 = $t1452;
                  $tco_a2 = n;
                  $tco_a3 = acc;
                  continue __tco;
                }
              }
            } else {
              {
                let $t1455;
                {
                  let $t1454;
                  {
                    const $t1453 = (c === "(");
                    if ($t1453 === true) {
                      $t1454 = true;
                    } else {
                      $t1454 = (c === ")");
                    }
                  }
                  if ($t1454 === true) {
                    $t1455 = true;
                  } else {
                    $t1455 = (c === ",");
                  }
                }
                if ($t1455 === true) {
                  {
                    const $t1456 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                    {
                      const $t1457 = { $: "Cons", _0: c, _1: acc };
                      {
                        $tco_a0 = s;
                        $tco_a1 = $t1456;
                        $tco_a2 = n;
                        $tco_a3 = $t1457;
                        continue __tco;
                      }
                    }
                  }
                } else {
                  {
                    const $t1458 = (c === "\"");
                    if ($t1458 === true) {
                      {
                        let $t1460;
                        {
                          const $t1459 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                          $t1460 = Authority$read_string(s, $t1459, n, "");
                        }
                        switch ($t1460.$) {
                          case "Err": {
                            const $f1463 = $t1460._0;
                            {
                              const e = $f1463;
                              return { $: "Err", _0: e };
                            }
                            break;
                          }
                          case "Ok": {
                            const $f1464 = $t1460._0;
                            const $f1465 = $f1464._0;
                            const $f1466 = $f1464._1;
                            {
                              const j = $f1466;
                              {
                                const str = $f1465;
                                {
                                  let $t1461;
                                  {
                                    const $rc_141 = ("\"" + str);
                                    $t1461 = $rc_141;
                                  }
                                  {
                                    const $t1462 = { $: "Cons", _0: $t1461, _1: acc };
                                    {
                                      $tco_a0 = s;
                                      $tco_a1 = j;
                                      $tco_a2 = n;
                                      $tco_a3 = $t1462;
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
                    } else {
                      {
                        let $t1471;
                        {
                          const $t1476_i127 = (c !== "");
                          if ($t1476_i127 === true) {
                            $t1471 = march_string_contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.", c);
                          } else {
                            $t1471 = false;
                          }
                        }
                        if ($t1471 === true) {
                          {
                            const j = Authority$word_end(s, i, n);
                            {
                              let $t1473;
                              {
                                const $t1472 = ((j - i) < 4611686018427387904 && (j - i) >= -4611686018427387904 ? (j - i) : march_int_ovf((j - i), 1));
                                $t1473 = march_string_slice(s, i, $t1472);
                              }
                              {
                                const $t1474 = { $: "Cons", _0: $t1473, _1: acc };
                                {
                                  $tco_a0 = s;
                                  $tco_a1 = j;
                                  $tco_a2 = n;
                                  $tco_a3 = $t1474;
                                  continue __tco;
                                }
                              }
                            }
                          }
                        } else {
                          {
                            let $t1475;
                            {
                              const $rc_142 = march_string_concat3("unexpected `", c, "`");
                              $t1475 = $rc_142;
                            }
                            return { $: "Err", _0: $t1475 };
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
    return undefined;
  }
}
const Authority$tokenize$clo = { _0: ($_, s, i, n, acc) => Authority$tokenize(s, i, n, acc) };

function Authority$word_end($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const s = $tco_a0;
    const i = $tco_a1;
    const n = $tco_a2;
    {
      let $t1479;
      {
        const $t1477 = (i < n);
        if ($t1477 === true) {
          {
            const $t1478 = march_string_slice(s, i, 1);
            {
              let $rc_143;
              {
                const $t1476_i129 = ($t1478 !== "");
                if ($t1476_i129 === true) {
                  $rc_143 = march_string_contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.", $t1478);
                } else {
                  $rc_143 = false;
                }
              }
              $t1479 = $rc_143;
            }
          }
        } else {
          $t1479 = false;
        }
      }
      if ($t1479 === true) {
        {
          const $t1480 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
          {
            $tco_a0 = s;
            $tco_a1 = $t1480;
            $tco_a2 = n;
            continue __tco;
          }
        }
      } else {
        return i;
      }
    }
    return undefined;
  }
}
const Authority$word_end$clo = { _0: ($_, s, i, n) => Authority$word_end(s, i, n) };

function Authority$read_string($tco_a0, $tco_a1, $tco_a2, $tco_a3) {
  __tco: for (;;) {
    const s = $tco_a0;
    const i = $tco_a1;
    const n = $tco_a2;
    const acc = $tco_a3;
    {
      const $t1481 = (i >= n);
      if ($t1481 === true) {
        return { $: "Err", _0: "a string is not closed" };
      } else {
        {
          const c = march_string_slice(s, i, 1);
          {
            const $t1482 = (c === "\"");
            if ($t1482 === true) {
              {
                const $t1483 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                {
                  const $t1484 = { _0: acc, _1: $t1483 };
                  return { $: "Ok", _0: $t1484 };
                }
              }
            } else {
              {
                const $t1485 = (c === "\\");
                if ($t1485 === true) {
                  {
                    let $t1487;
                    {
                      const $t1486 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                      $t1487 = ($t1486 >= n);
                    }
                    if ($t1487 === true) {
                      return { $: "Err", _0: "a string is not closed" };
                    } else {
                      {
                        let e;
                        {
                          const $t1488 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                          e = march_string_slice(s, $t1488, 1);
                        }
                        {
                          let d;
                          {
                            const $t1489 = (e === "n");
                            if ($t1489 === true) {
                              d = "\n";
                            } else {
                              {
                                const $t1490 = (e === "t");
                                if ($t1490 === true) {
                                  d = "\t";
                                } else {
                                  {
                                    const $t1491 = (e === "r");
                                    if ($t1491 === true) {
                                      d = "\r";
                                    } else {
                                      d = e;
                                    }
                                  }
                                }
                              }
                            }
                          }
                          {
                            const $t1492 = ((i + 2) < 4611686018427387904 && (i + 2) >= -4611686018427387904 ? (i + 2) : march_int_ovf((i + 2), 0));
                            {
                              let $t1493;
                              {
                                const $rc_144 = (acc + d);
                                $t1493 = $rc_144;
                              }
                              {
                                $tco_a0 = s;
                                $tco_a1 = $t1492;
                                $tco_a2 = n;
                                $tco_a3 = $t1493;
                                continue __tco;
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                } else {
                  {
                    const $t1494 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                    {
                      let $t1495;
                      {
                        const $rc_145 = (acc + c);
                        $t1495 = $rc_145;
                      }
                      {
                        $tco_a0 = s;
                        $tco_a1 = $t1494;
                        $tco_a2 = n;
                        $tco_a3 = $t1495;
                        continue __tco;
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
    return undefined;
  }
}
const Authority$read_string$clo = { _0: ($_, s, i, n, acc) => Authority$read_string(s, i, n, acc) };

function Authority$parse_entries($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const toks = $tco_a0;
    const acc = $tco_a1;
    {
      const $t1499 = Authority$parse_entry(toks);
      switch ($t1499.$) {
        case "Err": {
          const $f1516 = $t1499._0;
          {
            const e = $f1516;
            return { $: "Err", _0: e };
          }
          break;
        }
        case "Ok": {
          const $f1517 = $t1499._0;
          const $f1518 = $f1517._0;
          const $f1519 = $f1517._1;
          {
            const rest = $f1519;
            {
              const scope = $f1518;
              switch (rest.$) {
                case "Nil": {
                  {
                    const $t1500 = { $: "Cons", _0: scope, _1: acc };
                    {
                      const $t1501 = { $: "Nil" };
                      {
                        const $t1502 = Authority$rev_scopes($t1500, $t1501);
                        return { $: "Ok", _0: $t1502 };
                      }
                    }
                  }
                  break;
                }
                case "Cons": {
                  const $f1506 = rest._0;
                  const $f1507 = rest._1;
                  if ($f1506 === ",") {
                    {
                      const more = $f1507;
                      {
                        const $t1503 = { $: "Cons", _0: scope, _1: acc };
                        {
                          $tco_a0 = more;
                          $tco_a1 = $t1503;
                          continue __tco;
                        }
                      }
                    }
                  } else {
                    {
                      const t = $f1506;
                      {
                        let $t1505;
                        {
                          let $t1504;
                          {
                            let $rc_147;
                            {
                              const $t1498_i132 = march_string_starts_with(t, "\"");
                              if ($t1498_i132 === true) {
                                $rc_147 = "a string";
                              } else {
                                $rc_147 = march_string_concat3("`", t, "`");
                              }
                            }
                            $t1504 = $rc_147;
                          }
                          {
                            const $rc_146 = ("expected `,` between capabilities, found " + $t1504);
                            $t1505 = $rc_146;
                          }
                        }
                        return { $: "Err", _0: $t1505 };
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
const Authority$parse_entries$clo = { _0: ($_, toks, acc) => Authority$parse_entries(toks, acc) };

function Authority$parse_entry(toks) {
  switch (toks.$) {
    case "Nil": {
      return { $: "Err", _0: "expected a capability at the end" };
      break;
    }
    case "Cons": {
      const $f1569 = toks._0;
      const $f1570 = toks._1;
      {
        const rest = $f1570;
        {
          const k = $f1569;
          {
            let $t1525;
            {
              let $t1524;
              {
                let $t1579_i9723;
                {
                  let $t1578_i9722;
                  {
                    let $t1577_i9721;
                    {
                      let $t1576_i9720;
                      {
                        const $t1575_i9719 = march_string_starts_with(k, "\"");
                        $t1576_i9720 = (!$t1575_i9719);
                      }
                      if ($t1576_i9720 === true) {
                        $t1577_i9721 = (k !== "(");
                      } else {
                        $t1577_i9721 = false;
                      }
                    }
                    if ($t1577_i9721 === true) {
                      $t1578_i9722 = (k !== ")");
                    } else {
                      $t1578_i9722 = false;
                    }
                  }
                  if ($t1578_i9722 === true) {
                    $t1579_i9723 = (k !== ",");
                  } else {
                    $t1579_i9723 = false;
                  }
                }
                if ($t1579_i9723 === true) {
                  {
                    const $t1580_i9724 = march_string_split(k, ".");
                    {
                      const $rc_151_i9725 = Authority$kind_parts_ok($t1580_i9724);
                      $t1524 = $rc_151_i9725;
                    }
                  }
                } else {
                  $t1524 = false;
                }
              }
              $t1525 = (!$t1524);
            }
            if ($t1525 === true) {
              {
                let $t1527;
                {
                  let $t1526;
                  {
                    let $rc_149;
                    {
                      const $t1498_i134 = march_string_starts_with(k, "\"");
                      if ($t1498_i134 === true) {
                        $rc_149 = "a string";
                      } else {
                        $rc_149 = march_string_concat3("`", k, "`");
                      }
                    }
                    $t1526 = $rc_149;
                  }
                  {
                    const $rc_148 = ("expected a capability such as `IO.Console`, found " + $t1526);
                    $t1527 = $rc_148;
                  }
                }
                return { $: "Err", _0: $t1527 };
              }
            } else {
              switch (rest.$) {
                case "Cons": {
                  const $f1561 = rest._0;
                  const $f1562 = rest._1;
                  if ($f1561 === "(") {
                    {
                      const after = $f1562;
                      switch (after.$) {
                        case "Cons": {
                          const $f1550 = after._0;
                          const $f1551 = after._1;
                          if ($f1550 === ")") {
                            {
                              let $t1528;
                              {
                                const $rc_150 = march_string_concat_n("`", k, "()` names no scope: write `", k, "` for any target");
                                $t1528 = $rc_150;
                              }
                              return { $: "Err", _0: $t1528 };
                            }
                          } else {
                            {
                              let $t1531;
                              {
                                const $t1529 = { $: "Nil" };
                                {
                                  const $t1530 = { $: "Nil" };
                                  $t1531 = Authority$parse_items(after, $t1529, $t1530);
                                }
                              }
                              switch ($t1531.$) {
                                case "Err": {
                                  const $f1537 = $t1531._0;
                                  {
                                    const e = $f1537;
                                    return { $: "Err", _0: e };
                                  }
                                  break;
                                }
                                case "Ok": {
                                  const $f1538 = $t1531._0;
                                  const $f1539 = $f1538._0;
                                  const $f1540 = $f1538._1;
                                  const $f1541 = $f1538._2;
                                  {
                                    const more = $f1541;
                                    {
                                      const opts = $f1540;
                                      {
                                        const strs = $f1539;
                                        {
                                          const $t1532 = Authority$scope_arg(k, strs, opts);
                                          switch ($t1532.$) {
                                            case "Err": {
                                              const $f1535 = $t1532._0;
                                              {
                                                const e = $f1535;
                                                return { $: "Err", _0: e };
                                              }
                                              break;
                                            }
                                            case "Ok": {
                                              const $f1536 = $t1532._0;
                                              {
                                                const arg = $f1536;
                                                {
                                                  const $t1533 = { $: "Scope", _0: k, _1: arg };
                                                  {
                                                    const $t1534 = { _0: $t1533, _1: more };
                                                    return { $: "Ok", _0: $t1534 };
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
                          {
                            let $t1531;
                            {
                              const $t1529 = { $: "Nil" };
                              {
                                const $t1530 = { $: "Nil" };
                                $t1531 = Authority$parse_items(after, $t1529, $t1530);
                              }
                            }
                            switch ($t1531.$) {
                              case "Err": {
                                const $f1537 = $t1531._0;
                                {
                                  const e = $f1537;
                                  return { $: "Err", _0: e };
                                }
                                break;
                              }
                              case "Ok": {
                                const $f1538 = $t1531._0;
                                const $f1539 = $f1538._0;
                                const $f1540 = $f1538._1;
                                const $f1541 = $f1538._2;
                                {
                                  const more = $f1541;
                                  {
                                    const opts = $f1540;
                                    {
                                      const strs = $f1539;
                                      {
                                        const $t1532 = Authority$scope_arg(k, strs, opts);
                                        switch ($t1532.$) {
                                          case "Err": {
                                            const $f1535 = $t1532._0;
                                            {
                                              const e = $f1535;
                                              return { $: "Err", _0: e };
                                            }
                                            break;
                                          }
                                          case "Ok": {
                                            const $f1536 = $t1532._0;
                                            {
                                              const arg = $f1536;
                                              {
                                                const $t1533 = { $: "Scope", _0: k, _1: arg };
                                                {
                                                  const $t1534 = { _0: $t1533, _1: more };
                                                  return { $: "Ok", _0: $t1534 };
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
                  } else {
                    {
                      let $t1559;
                      {
                        const $t1558 = { $: "Any" };
                        $t1559 = { $: "Scope", _0: k, _1: $t1558 };
                      }
                      {
                        const $t1560 = { _0: $t1559, _1: rest };
                        return { $: "Ok", _0: $t1560 };
                      }
                    }
                  }
                  break;
                }
                default: {
                  {
                    let $t1559;
                    {
                      const $t1558 = { $: "Any" };
                      $t1559 = { $: "Scope", _0: k, _1: $t1558 };
                    }
                    {
                      const $t1560 = { _0: $t1559, _1: rest };
                      return { $: "Ok", _0: $t1560 };
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
const Authority$parse_entry$clo = { _0: ($_, toks) => Authority$parse_entry(toks) };

function Authority$kind_parts_ok($tco_a0) {
  __tco: for (;;) {
    const ps = $tco_a0;
    switch (ps.$) {
      case "Nil": {
        return true;
        break;
      }
      case "Cons": {
        const $f1584 = ps._0;
        const $f1585 = ps._1;
        {
          const rest = $f1585;
          {
            const p = $f1584;
            {
              let $t1583;
              {
                const $t1581 = (p !== "");
                if ($t1581 === true) {
                  {
                    const $t1582 = march_string_slice(p, 0, 1);
                    {
                      const $rc_152 = march_string_contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ", $t1582);
                      $t1583 = $rc_152;
                    }
                  }
                } else {
                  $t1583 = false;
                }
              }
              if ($t1583 === true) {
                {
                  $tco_a0 = rest;
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
const Authority$kind_parts_ok$clo = { _0: ($_, ps) => Authority$kind_parts_ok(ps) };

function Authority$parse_items($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const toks = $tco_a0;
    const strs = $tco_a1;
    const opts = $tco_a2;
    switch (toks.$) {
      case "Nil": {
        return { $: "Err", _0: "a scope is not closed: expected `)`" };
        break;
      }
      case "Cons": {
        const $f1644 = toks._0;
        const $f1645 = toks._1;
        {
          const rest = $f1645;
          {
            const t = $f1644;
            {
              let item;
              {
                const $t1591 = march_string_starts_with(t, "\"");
                if ($t1591 === true) {
                  {
                    let $t1592;
                    switch (opts.$) {
                      case "Nil": {
                        $t1592 = true;
                        break;
                      }
                      default: {
                        $t1592 = false;
                        break;
                      }
                    }
                    if ($t1592 === true) {
                      {
                        let $t1593;
                        {
                          let $rc_155;
                          {
                            let $t1497_i144;
                            {
                              const $t1496_i143 = march_string_byte_length(t);
                              $t1497_i144 = (($t1496_i143 - 1) < 4611686018427387904 && ($t1496_i143 - 1) >= -4611686018427387904 ? ($t1496_i143 - 1) : march_int_ovf(($t1496_i143 - 1), 1));
                            }
                            $rc_155 = march_string_slice(t, 1, $t1497_i144);
                          }
                          $t1593 = $rc_155;
                        }
                        {
                          const $t1594 = { $: "Cons", _0: $t1593, _1: strs };
                          {
                            const $t1595 = { _0: $t1594, _1: opts, _2: rest };
                            item = { $: "Ok", _0: $t1595 };
                          }
                        }
                      }
                    } else {
                      item = { $: "Err", _0: "a string cannot follow an option in a scope" };
                    }
                  }
                } else {
                  {
                    let $t1596;
                    {
                      const $t1590_i141 = (t !== "");
                      if ($t1590_i141 === true) {
                        $t1596 = Authority$all_chars(t, "abcdefghijklmnopqrstuvwxyz_", 0);
                      } else {
                        $t1596 = false;
                      }
                    }
                    if ($t1596 === true) {
                      {
                        const $t1597 = Authority$parse_option(t, rest);
                        switch ($t1597.$) {
                          case "Err": {
                            const $f1600 = $t1597._0;
                            {
                              const e = $f1600;
                              item = { $: "Err", _0: e };
                            }
                            break;
                          }
                          case "Ok": {
                            const $f1601 = $t1597._0;
                            const $f1602 = $f1601._0;
                            const $f1603 = $f1601._1;
                            {
                              const more = $f1603;
                              {
                                const o = $f1602;
                                {
                                  const $t1598 = { $: "Cons", _0: o, _1: opts };
                                  {
                                    const $t1599 = { _0: strs, _1: $t1598, _2: more };
                                    item = { $: "Ok", _0: $t1599 };
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
                    } else {
                      {
                        let $t1609;
                        {
                          let $t1608;
                          {
                            let $rc_157;
                            {
                              const $t1498_i139 = march_string_starts_with(t, "\"");
                              if ($t1498_i139 === true) {
                                $rc_157 = "a string";
                              } else {
                                $rc_157 = march_string_concat3("`", t, "`");
                              }
                            }
                            $t1608 = $rc_157;
                          }
                          {
                            const $rc_156 = ("expected a string or an option in a scope, found " + $t1608);
                            $t1609 = $rc_156;
                          }
                        }
                        item = { $: "Err", _0: $t1609 };
                      }
                    }
                  }
                }
              }
              switch (item.$) {
                case "Err": {
                  const $f1631 = item._0;
                  {
                    const e = $f1631;
                    return { $: "Err", _0: e };
                  }
                  break;
                }
                case "Ok": {
                  const $f1632 = item._0;
                  const $f1633 = $f1632._0;
                  const $f1634 = $f1632._1;
                  const $f1635 = $f1632._2;
                  {
                    const more = $f1635;
                    {
                      const o2 = $f1634;
                      {
                        const s2 = $f1633;
                        switch (more.$) {
                          case "Cons": {
                            const $f1617 = more._0;
                            const $f1618 = more._1;
                            if ($f1617 === ")") {
                              {
                                const after = $f1618;
                                {
                                  const $t1610 = { $: "Nil" };
                                  {
                                    const $t1611 = Authority$rev(s2, $t1610);
                                    {
                                      const $t1612 = { $: "Nil" };
                                      {
                                        const $t1613 = Authority$rev(o2, $t1612);
                                        {
                                          const $t1614 = { _0: $t1611, _1: $t1613, _2: after };
                                          return { $: "Ok", _0: $t1614 };
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            } else if ($f1617 === ",") {
                              {
                                const after = $f1618;
                                {
                                  $tco_a0 = after;
                                  $tco_a1 = s2;
                                  $tco_a2 = o2;
                                  continue __tco;
                                }
                              }
                            } else {
                              {
                                const x = $f1617;
                                {
                                  let $t1616;
                                  {
                                    let $t1615;
                                    {
                                      let $rc_154;
                                      {
                                        const $t1498_i137 = march_string_starts_with(x, "\"");
                                        if ($t1498_i137 === true) {
                                          $rc_154 = "a string";
                                        } else {
                                          $rc_154 = march_string_concat3("`", x, "`");
                                        }
                                      }
                                      $t1615 = $rc_154;
                                    }
                                    {
                                      const $rc_153 = ("expected `,` or `)` in a scope, found " + $t1615);
                                      $t1616 = $rc_153;
                                    }
                                  }
                                  return { $: "Err", _0: $t1616 };
                                }
                              }
                            }
                            break;
                          }
                          case "Nil": {
                            return { $: "Err", _0: "a scope is not closed: expected `)`" };
                            break;
                          }
                          default: {
                            return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
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
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
    return undefined;
  }
}
const Authority$parse_items$clo = { _0: ($_, toks, strs, opts) => Authority$parse_items(toks, strs, opts) };

function Authority$parse_option(name, toks) {
  switch (toks.$) {
    case "Cons": {
      const $f1676 = toks._0;
      const $f1677 = toks._1;
      if ($f1676 === "(") {
        switch ($f1677.$) {
          case "Cons": {
            const $f1684 = $f1677._0;
            const $f1685 = $f1677._1;
            {
              let $jp_clo1691;
              $jp_clo1691 = { $: "$Clo_$jp7_Authority_parse_option$0_Authority_parse_option", _0: $jp7_Authority_parse_option$apply$0_Authority_parse_option, _1: $f1677, _2: name };
              switch ($f1685.$) {
                case "Cons": {
                  const $f1692 = $f1685._0;
                  const $f1693 = $f1685._1;
                  if ($f1692 === ")") {
                    {
                      const rest = $f1693;
                      {
                        const v = $f1684;
                        {
                          const $t1650 = march_string_starts_with(v, "\"");
                          if ($t1650 === true) {
                            {
                              const $t1651 = (name === "methods");
                              if ($t1651 === true) {
                                return { $: "Err", _0: "`methods(...)` takes HTTP method names, not a string" };
                              } else {
                                {
                                  let $t1653;
                                  {
                                    let $t1652;
                                    {
                                      let $rc_159;
                                      {
                                        let $t1497_i151;
                                        {
                                          const $t1496_i150 = march_string_byte_length(v);
                                          $t1497_i151 = (($t1496_i150 - 1) < 4611686018427387904 && ($t1496_i150 - 1) >= -4611686018427387904 ? ($t1496_i150 - 1) : march_int_ovf(($t1496_i150 - 1), 1));
                                        }
                                        $rc_159 = march_string_slice(v, 1, $t1497_i151);
                                      }
                                      $t1652 = $rc_159;
                                    }
                                    {
                                      const $rc_158 = march_string_concat3(name, "=", $t1652);
                                      $t1653 = $rc_158;
                                    }
                                  }
                                  {
                                    const $t1654 = { _0: $t1653, _1: rest };
                                    return { $: "Ok", _0: $t1654 };
                                  }
                                }
                              }
                            }
                          } else {
                            {
                              let $t1656;
                              {
                                const $t1655 = (name === "methods");
                                if ($t1655 === true) {
                                  {
                                    const $t1590_i148 = (v !== "");
                                    if ($t1590_i148 === true) {
                                      $t1656 = Authority$all_chars(v, "abcdefghijklmnopqrstuvwxyz_", 0);
                                    } else {
                                      $t1656 = false;
                                    }
                                  }
                                } else {
                                  $t1656 = false;
                                }
                              }
                              if ($t1656 === true) {
                                {
                                  let $t1657;
                                  {
                                    const $rc_160 = ("methods=" + v);
                                    $t1657 = $rc_160;
                                  }
                                  {
                                    const $t1658 = { _0: $t1657, _1: rest };
                                    return { $: "Ok", _0: $t1658 };
                                  }
                                }
                              } else {
                                {
                                  let $t1659;
                                  {
                                    const $rc_161 = march_string_concat3("`", name, "(...)` takes a quoted string");
                                    $t1659 = $rc_161;
                                  }
                                  return { $: "Err", _0: $t1659 };
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  } else {
                    return $jp7_Authority_parse_option$apply$0_Authority_parse_option($jp_clo1691);
                  }
                  break;
                }
                default: {
                  return $jp7_Authority_parse_option$apply$0_Authority_parse_option($jp_clo1691);
                }
              }
            }
            break;
          }
          default: {
            {
              const more = $f1677;
              {
                const $t1660 = (name === "methods");
                if ($t1660 === true) {
                  {
                    let $t1662;
                    {
                      const $t1661 = { $: "Nil" };
                      $t1662 = Authority$method_words(more, $t1661);
                    }
                    switch ($t1662.$) {
                      case "Err": {
                        const $f1666 = $t1662._0;
                        {
                          const e = $f1666;
                          return { $: "Err", _0: e };
                        }
                        break;
                      }
                      case "Ok": {
                        const $f1667 = $t1662._0;
                        const $f1668 = $f1667._0;
                        const $f1669 = $f1667._1;
                        {
                          const rest = $f1669;
                          {
                            const ms = $f1668;
                            {
                              let $t1664;
                              {
                                let $t1663;
                                {
                                  const $rc_163 = march_string_join(ms, ",");
                                  $t1663 = $rc_163;
                                }
                                {
                                  const $rc_162 = ("methods=" + $t1663);
                                  $t1664 = $rc_162;
                                }
                              }
                              {
                                const $t1665 = { _0: $t1664, _1: rest };
                                return { $: "Ok", _0: $t1665 };
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
                } else {
                  {
                    let $t1674;
                    {
                      const $rc_164 = march_string_concat3("`", name, "(...)` takes one quoted string");
                      $t1674 = $rc_164;
                    }
                    return { $: "Err", _0: $t1674 };
                  }
                }
              }
            }
          }
        }
      } else {
        {
          const $t1675 = { _0: name, _1: toks };
          return { $: "Ok", _0: $t1675 };
        }
      }
      break;
    }
    default: {
      {
        const $t1675 = { _0: name, _1: toks };
        return { $: "Ok", _0: $t1675 };
      }
    }
  }
}
const Authority$parse_option$clo = { _0: ($_, name, toks) => Authority$parse_option(name, toks) };

function Authority$method_words($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const toks = $tco_a0;
    const acc = $tco_a1;
    switch (toks.$) {
      case "Cons": {
        const $f1707 = toks._0;
        const $f1708 = toks._1;
        {
          let $jp_clo1726;
          $jp_clo1726 = { $: "$Clo_$jp7_Authority_method_words$0_Authority_method_words", _0: $jp7_Authority_method_words$apply$0_Authority_method_words, _1: $f1707, _2: $f1708, _3: acc };
          switch ($f1708.$) {
            case "Cons": {
              const $f1727 = $f1708._0;
              const $f1728 = $f1708._1;
              if ($f1727 === ",") {
                {
                  const rest = $f1728;
                  {
                    const m = $f1707;
                    {
                      let $t1700;
                      {
                        const $t1590_i154 = (m !== "");
                        if ($t1590_i154 === true) {
                          $t1700 = Authority$all_chars(m, "abcdefghijklmnopqrstuvwxyz_", 0);
                        } else {
                          $t1700 = false;
                        }
                      }
                      if ($t1700 === true) {
                        {
                          const $t1701 = { $: "Cons", _0: m, _1: acc };
                          {
                            $tco_a0 = rest;
                            $tco_a1 = $t1701;
                            continue __tco;
                          }
                        }
                      } else {
                        return { $: "Err", _0: "`methods(...)` takes HTTP method names" };
                      }
                    }
                  }
                }
              } else {
                return $jp7_Authority_method_words$apply$0_Authority_method_words($jp_clo1726);
              }
              break;
            }
            default: {
              return $jp7_Authority_method_words$apply$0_Authority_method_words($jp_clo1726);
            }
          }
        }
        break;
      }
      default: {
        return { $: "Err", _0: "`methods(...)` is not closed" };
      }
    }
    return undefined;
  }
}
const Authority$method_words$clo = { _0: ($_, toks, acc) => Authority$method_words(toks, acc) };

function Authority$scope_arg(k, strs, opts) {
  {
    let $t1735;
    {
      let $t1084_i165;
      {
        const $t1083_i164 = (k === "IO.FileRead");
        if ($t1083_i164 === true) {
          $t1084_i165 = true;
        } else {
          $t1084_i165 = (k === "IO.FileWrite");
        }
      }
      if ($t1084_i165 === true) {
        $t1735 = true;
      } else {
        $t1735 = (k === "IO.FileSystem");
      }
    }
    if ($t1735 === true) {
      {
        let $t1737;
        {
          let $t1736;
          {
            let $rc_166;
            switch (opts.$) {
              case "Nil": {
                $rc_166 = true;
                break;
              }
              default: {
                $rc_166 = false;
                break;
              }
            }
            $t1736 = $rc_166;
          }
          $t1737 = (!$t1736);
        }
        if ($t1737 === true) {
          {
            const $t1738 = march_string_concat3("a path scope on `", k, "` takes only paths");
            return { $: "Err", _0: $t1738 };
          }
        } else {
          {
            const $t1739 = Authority$member(strs, "");
            if ($t1739 === true) {
              return { $: "Err", _0: "a path scope cannot be empty" };
            } else {
              {
                let $t1740;
                $t1740 = Authority$first_relative(strs);
                switch ($t1740.$) {
                  case "Some": {
                    const $f1744 = $t1740._0;
                    {
                      const p = $f1744;
                      {
                        let $t1741;
                        {
                          const $rc_165 = march_string_concat_n("the scope `", p, "` on `", k, "` is a relative path; give an absolute path, one starting with `/`");
                          $t1741 = $rc_165;
                        }
                        return { $: "Err", _0: $t1741 };
                      }
                    }
                    break;
                  }
                  case "None": {
                    {
                      let $t1743;
                      {
                        let $t1742;
                        {
                          const l_i9735 = strs;
                          switch (l_i9735.$) {
                            case "Nil": {
                              $t1742 = { $: "Nil" };
                              break;
                            }
                            case "Cons": {
                              const $f2000_i9736 = l_i9735._0;
                              const $f2001_i9737 = l_i9735._1;
                              {
                                const rest_i9738 = $f2001_i9737;
                                {
                                  const x_i9739 = $f2000_i9736;
                                  {
                                    let $t1998_i9741;
                                    {
                                      const $rc_205_i9740 = Authority$normalize(x_i9739);
                                      $t1998_i9741 = $rc_205_i9740;
                                    }
                                    {
                                      const $trmc27_i9742 = { $: "Cons", _0: $t1998_i9741, _1: null };
                                      Authority$map_normalize$dps(rest_i9738, $trmc27_i9742);
                                      $t1742 = $trmc27_i9742;
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
                        $t1743 = { $: "PathsAt", _0: $t1742 };
                      }
                      return { $: "Ok", _0: $t1743 };
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
    } else {
      {
        const $t1745 = (k === "IO.NetConnect");
        if ($t1745 === true) {
          {
            let spec;
            switch (strs.$) {
              case "Nil": {
                {
                  let $t1746;
                  {
                    const $rc_168 = march_string_join(opts, ";");
                    $t1746 = $rc_168;
                  }
                  {
                    const $rc_167 = (";" + $t1746);
                    spec = $rc_167;
                  }
                }
                break;
              }
              case "Cons": {
                const $f1750 = strs._0;
                const $f1751 = strs._1;
                {
                  const more = $f1751;
                  {
                    const first = $f1750;
                    {
                      let $t1747;
                      {
                        const l_i9726 = more;
                        switch (l_i9726.$) {
                          case "Nil": {
                            $t1747 = { $: "Nil" };
                            break;
                          }
                          case "Cons": {
                            const $f1992_i9728 = l_i9726._0;
                            const $f1993_i9729 = l_i9726._1;
                            {
                              const rest_i9730 = $f1993_i9729;
                              {
                                const x_i9731 = $f1992_i9728;
                                {
                                  let $t1990_i9733;
                                  {
                                    const $rc_203_i9732 = ("name=" + x_i9731);
                                    $t1990_i9733 = $rc_203_i9732;
                                  }
                                  {
                                    const $trmc23_i9734 = { $: "Cons", _0: $t1990_i9733, _1: null };
                                    Authority$prefix_all$dps(rest_i9730, "name=", $trmc23_i9734);
                                    $t1747 = $trmc23_i9734;
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
                      {
                        let $t1748;
                        {
                          const $t1974_i159 = { $: "Nil" };
                          {
                            const $t1975_i160 = Authority$rev($t1747, $t1974_i159);
                            $t1748 = Authority$rev($t1975_i160, opts);
                          }
                        }
                        {
                          const $t1749 = { $: "Cons", _0: first, _1: $t1748 };
                          {
                            const $rc_169 = march_string_join($t1749, ";");
                            spec = $rc_169;
                          }
                        }
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
            {
              const $t1756 = Authority$host_decl(spec);
              switch ($t1756.$) {
                case "Err": {
                  const $f1779 = $t1756._0;
                  {
                    const e = $f1779;
                    return { $: "Err", _0: e };
                  }
                  break;
                }
                case "Ok": {
                  const $f1780 = $t1756._0;
                  const $f1781 = $f1780._0;
                  const $f1782 = $f1780._1;
                  const $f1783 = $f1780._2;
                  const $f1784 = $f1780._3;
                  {
                    const p = $f1781;
                    {
                      const $t1757 = (p === "");
                      if ($t1757 === true) {
                        {
                          const $t1758 = { $: "HostAt", _0: spec, _1: "", _2: false, _3: 0 };
                          return { $: "Ok", _0: $t1758 };
                        }
                      } else {
                        {
                          const $t1759 = Authority$parse_host_pattern(p);
                          switch ($t1759.$) {
                            case "Ok": {
                              const $f1761 = $t1759._0;
                              const $f1762 = $f1761._0;
                              const $f1763 = $f1761._1;
                              const $f1764 = $f1761._2;
                              const $f1765 = $f1761._3;
                              {
                                const port = $f1764;
                                {
                                  const wild = $f1763;
                                  {
                                    const h = $f1762;
                                    {
                                      const $t1760 = { $: "HostAt", _0: spec, _1: h, _2: wild, _3: port };
                                      return { $: "Ok", _0: $t1760 };
                                    }
                                  }
                                }
                              }
                              break;
                            }
                            case "Err": {
                              const $f1778 = $t1759._0;
                              {
                                const e = $f1778;
                                return { $: "Err", _0: e };
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
                  break;
                }
                default: {
                  return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
                }
              }
            }
          }
        } else {
          {
            let $t1797;
            {
              const $t1085_i156 = (k === "IO.Mut");
              if ($t1085_i156 === true) {
                $t1797 = true;
              } else {
                $t1797 = (k === "IO.Registry");
              }
            }
            if ($t1797 === true) {
              {
                let $t1799;
                {
                  const $t1798 = { $: "Nil" };
                  $t1799 = Authority$name_options(opts, $t1798);
                }
                switch ($t1799.$) {
                  case "Err": {
                    const $f1805 = $t1799._0;
                    {
                      const e = $f1805;
                      return { $: "Err", _0: e };
                    }
                    break;
                  }
                  case "Ok": {
                    const $f1806 = $t1799._0;
                    {
                      const prefixes = $f1806;
                      {
                        const $t1800 = Authority$bad_name_text(strs, "a name");
                        switch ($t1800.$) {
                          case "Some": {
                            const $f1804 = $t1800._0;
                            {
                              const e = $f1804;
                              return { $: "Err", _0: e };
                            }
                            break;
                          }
                          case "None": {
                            {
                              const $t1801 = Authority$bad_name_text(prefixes, "a prefix");
                              switch ($t1801.$) {
                                case "Some": {
                                  const $f1803 = $t1801._0;
                                  {
                                    const e = $f1803;
                                    return { $: "Err", _0: e };
                                  }
                                  break;
                                }
                                case "None": {
                                  {
                                    const $t1802 = { $: "Names", _0: strs, _1: prefixes };
                                    return { $: "Ok", _0: $t1802 };
                                  }
                                  break;
                                }
                                default: {
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
                    break;
                  }
                  default: {
                    return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
                  }
                }
              }
            } else {
              {
                const $t1807 = march_string_concat3("`", k, "` takes no scope");
                return { $: "Err", _0: $t1807 };
              }
            }
          }
        }
      }
    }
  }
}
const Authority$scope_arg$clo = { _0: ($_, k, strs, opts) => Authority$scope_arg(k, strs, opts) };

function Authority$first_relative($tco_a0) {
  __tco: for (;;) {
    const ps = $tco_a0;
    switch (ps.$) {
      case "Nil": {
        return { $: "None" };
        break;
      }
      case "Cons": {
        const $f1809 = ps._0;
        const $f1810 = ps._1;
        {
          const rest = $f1810;
          {
            const p = $f1809;
            {
              const $t1808 = march_string_starts_with(p, "/");
              if ($t1808 === true) {
                {
                  $tco_a0 = rest;
                  continue __tco;
                }
              } else {
                return { $: "Some", _0: p };
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
const Authority$first_relative$clo = { _0: ($_, ps) => Authority$first_relative(ps) };

function Authority$name_options($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const opts = $tco_a0;
    const acc = $tco_a1;
    switch (opts.$) {
      case "Nil": {
        {
          const $t1815 = { $: "Nil" };
          {
            const $t1816 = Authority$rev(acc, $t1815);
            return { $: "Ok", _0: $t1816 };
          }
        }
        break;
      }
      case "Cons": {
        const $f1823 = opts._0;
        const $f1824 = opts._1;
        {
          const rest = $f1824;
          {
            const o = $f1823;
            {
              const $t1817 = march_string_starts_with(o, "prefix=");
              if ($t1817 === true) {
                {
                  let $t1820;
                  {
                    let $t1819;
                    {
                      const $t1818 = march_string_byte_length(o);
                      $t1819 = (($t1818 - 7) < 4611686018427387904 && ($t1818 - 7) >= -4611686018427387904 ? ($t1818 - 7) : march_int_ovf(($t1818 - 7), 1));
                    }
                    {
                      const $rc_170 = march_string_slice(o, 7, $t1819);
                      $t1820 = $rc_170;
                    }
                  }
                  {
                    const $t1821 = { $: "Cons", _0: $t1820, _1: acc };
                    {
                      $tco_a0 = rest;
                      $tco_a1 = $t1821;
                      continue __tco;
                    }
                  }
                }
              } else {
                {
                  let $t1822;
                  {
                    const $rc_171 = march_string_concat3("`", o, "` is not an option a name scope takes; it takes names and `prefix(\"...\")`");
                    $t1822 = $rc_171;
                  }
                  return { $: "Err", _0: $t1822 };
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
const Authority$name_options$clo = { _0: ($_, opts, acc) => Authority$name_options(opts, acc) };

function Authority$bad_name_text($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const ns = $tco_a0;
    const what = $tco_a1;
    switch (ns.$) {
      case "Nil": {
        return { $: "None" };
        break;
      }
      case "Cons": {
        const $f1835 = ns._0;
        const $f1836 = ns._1;
        {
          const rest = $f1836;
          {
            const n = $f1835;
            {
              const $t1829 = (n === "");
              if ($t1829 === true) {
                {
                  const $t1830 = (what + " cannot be empty");
                  return { $: "Some", _0: $t1830 };
                }
              } else {
                {
                  let $t1833;
                  {
                    let $t1832;
                    {
                      const $t1831 = march_string_contains(n, ";");
                      if ($t1831 === true) {
                        $t1832 = true;
                      } else {
                        $t1832 = march_string_contains(n, "=");
                      }
                    }
                    if ($t1832 === true) {
                      $t1833 = true;
                    } else {
                      $t1833 = march_string_contains(n, ",");
                    }
                  }
                  if ($t1833 === true) {
                    {
                      const $t1834 = march_string_concat_n(what, " `", n, "` contains `;`, `=` or `,`");
                      return { $: "Some", _0: $t1834 };
                    }
                  } else {
                    {
                      $tco_a0 = rest;
                      $tco_a1 = what;
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
const Authority$bad_name_text$clo = { _0: ($_, ns, what) => Authority$bad_name_text(ns, what) };

function Authority$scope_text(s) {
  switch (s.$) {
    case "Scope": {
      const $f1850 = s._0;
      const $f1851 = s._1;
      switch ($f1851.$) {
        case "Any": {
          {
            const k = $f1850;
            return k;
          }
          break;
        }
        default: {
          switch ($f1851.$) {
            case "Paths": {
              const $f1902 = $f1851._0;
              {
                const ps = $f1902;
                {
                  const k = $f1850;
                  {
                    let $t1842;
                    {
                      const $t1841 = Authority$quote_all(ps);
                      {
                        const $rc_173 = march_string_join($t1841, ", ");
                        $t1842 = $rc_173;
                      }
                    }
                    {
                      const $rc_172 = march_string_concat_n(k, "(", $t1842, ")");
                      return $rc_172;
                    }
                  }
                }
              }
              break;
            }
            default: {
              switch ($f1851.$) {
                case "PathsAt": {
                  const $f1895 = $f1851._0;
                  {
                    const ps = $f1895;
                    {
                      const k = $f1850;
                      {
                        let $t1844;
                        {
                          const $t1843 = Authority$quote_all(ps);
                          {
                            const $rc_175 = march_string_join($t1843, ", ");
                            $t1844 = $rc_175;
                          }
                        }
                        {
                          const $rc_174 = march_string_concat_n(k, "(", $t1844, ")");
                          return $rc_174;
                        }
                      }
                    }
                  }
                  break;
                }
                default: {
                  switch ($f1851.$) {
                    case "Names": {
                      const $f1883 = $f1851._0;
                      const $f1884 = $f1851._1;
                      {
                        const pre = $f1884;
                        {
                          const ns = $f1883;
                          {
                            const k = $f1850;
                            {
                              let $t1849;
                              {
                                const $t1845 = Authority$quote_all(ns);
                                {
                                  const $t1846 = Authority$quote_all(pre);
                                  {
                                    let $t1847;
                                    {
                                      const l_i9743 = $t1846;
                                      switch (l_i9743.$) {
                                        case "Nil": {
                                          $t1847 = { $: "Nil" };
                                          break;
                                        }
                                        case "Cons": {
                                          const $f1954_i9745 = l_i9743._0;
                                          const $f1955_i9746 = l_i9743._1;
                                          {
                                            const rest_i9747 = $f1955_i9746;
                                            {
                                              const x_i9748 = $f1954_i9745;
                                              {
                                                let $t1952_i9750;
                                                {
                                                  const $rc_201_i9749 = march_string_concat3("prefix(", x_i9748, ")");
                                                  $t1952_i9750 = $rc_201_i9749;
                                                }
                                                {
                                                  const $trmc19_i9751 = { $: "Cons", _0: $t1952_i9750, _1: null };
                                                  Authority$wrap_all$dps(rest_i9747, "prefix(", $trmc19_i9751);
                                                  $t1847 = $trmc19_i9751;
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
                                    {
                                      let $t1848;
                                      {
                                        const $t1974_i168 = { $: "Nil" };
                                        {
                                          const $t1975_i169 = Authority$rev($t1845, $t1974_i168);
                                          $t1848 = Authority$rev($t1975_i169, $t1847);
                                        }
                                      }
                                      {
                                        const $rc_177 = march_string_join($t1848, ", ");
                                        $t1849 = $rc_177;
                                      }
                                    }
                                  }
                                }
                              }
                              {
                                const $rc_176 = march_string_concat_n(k, "(", $t1849, ")");
                                return $rc_176;
                              }
                            }
                          }
                        }
                      }
                      break;
                    }
                    default: {
                      switch ($f1851.$) {
                        case "Hosts": {
                          const $f1876 = $f1851._0;
                          {
                            const spec = $f1876;
                            {
                              const k = $f1850;
                              {
                                const $rc_178 = Authority$host_scope_text(k, spec);
                                return $rc_178;
                              }
                            }
                          }
                          break;
                        }
                        default: {
                          switch ($f1851.$) {
                            case "HostAt": {
                              const $f1854 = $f1851._0;
                              const $f1855 = $f1851._1;
                              const $f1856 = $f1851._2;
                              const $f1857 = $f1851._3;
                              {
                                const spec = $f1854;
                                {
                                  const k = $f1850;
                                  {
                                    const $rc_179 = Authority$host_scope_text(k, spec);
                                    return $rc_179;
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
const Authority$scope_text$clo = { _0: ($_, s) => Authority$scope_text(s) };

function Authority$host_scope_text(k, spec) {
  {
    const $t1911 = march_string_split(spec, ";");
    switch ($t1911.$) {
      case "Nil": {
        return k;
        break;
      }
      case "Cons": {
        const $f1918 = $t1911._0;
        const $f1919 = $t1911._1;
        {
          const opts = $f1919;
          {
            const first = $f1918;
            {
              const $t1912 = (first === "");
              {
                let head;
                if ($t1912 === true) {
                  head = { $: "Nil" };
                } else {
                  {
                    let $t1913;
                    {
                      const $rc_182 = Authority$quote(first);
                      $t1913 = $rc_182;
                    }
                    {
                      const $t1914 = { $: "Nil" };
                      head = { $: "Cons", _0: $t1913, _1: $t1914 };
                    }
                  }
                }
                {
                  let $t1917;
                  {
                    const $t1915 = Authority$option_texts(opts);
                    {
                      let $t1916;
                      {
                        const $t1974_i172 = { $: "Nil" };
                        {
                          const $t1975_i173 = Authority$rev(head, $t1974_i172);
                          $t1916 = Authority$rev($t1975_i173, $t1915);
                        }
                      }
                      {
                        const $rc_181 = march_string_join($t1916, ", ");
                        $t1917 = $rc_181;
                      }
                    }
                  }
                  {
                    const $rc_180 = march_string_concat_n(k, "(", $t1917, ")");
                    return $rc_180;
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
const Authority$host_scope_text$clo = { _0: ($_, k, spec) => Authority$host_scope_text(k, spec) };

function Authority$option_texts(opts) {
  switch (opts.$) {
    case "Nil": {
      return { $: "Nil" };
      break;
    }
    case "Cons": {
      const $f1936 = opts._0;
      const $f1937 = opts._1;
      {
        const rest = $f1937;
        {
          const o = $f1936;
          {
            let t;
            {
              const $t1924 = march_string_index_of(o, "=");
              switch ($t1924.$) {
                case "None": {
                  t = o;
                  break;
                }
                case "Some": {
                  const $f1934 = $t1924._0;
                  {
                    const i = $f1934;
                    {
                      const name = march_string_slice(o, 0, i);
                      {
                        let v;
                        {
                          const $t1925 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                          {
                            let $t1928;
                            {
                              let $t1927;
                              {
                                const $t1926 = march_string_byte_length(o);
                                $t1927 = (($t1926 - i) < 4611686018427387904 && ($t1926 - i) >= -4611686018427387904 ? ($t1926 - i) : march_int_ovf(($t1926 - i), 1));
                              }
                              $t1928 = (($t1927 - 1) < 4611686018427387904 && ($t1927 - 1) >= -4611686018427387904 ? ($t1927 - 1) : march_int_ovf(($t1927 - 1), 1));
                            }
                            {
                              const $rc_189 = march_string_slice(o, $t1925, $t1928);
                              v = $rc_189;
                            }
                          }
                        }
                        {
                          const $t1929 = (name === "name");
                          if ($t1929 === true) {
                            {
                              const $rc_183 = Authority$quote(v);
                              t = $rc_183;
                            }
                          } else {
                            {
                              const $t1930 = (name === "methods");
                              if ($t1930 === true) {
                                {
                                  let $t1932;
                                  {
                                    let $t1931;
                                    {
                                      const $rc_186 = march_string_split(v, ",");
                                      $t1931 = $rc_186;
                                    }
                                    {
                                      const $rc_185 = march_string_join($t1931, ", ");
                                      $t1932 = $rc_185;
                                    }
                                  }
                                  {
                                    const $rc_184 = march_string_concat3("methods(", $t1932, ")");
                                    t = $rc_184;
                                  }
                                }
                              } else {
                                {
                                  let $t1933;
                                  {
                                    const $rc_188 = Authority$quote(v);
                                    $t1933 = $rc_188;
                                  }
                                  {
                                    const $rc_187 = march_string_concat_n(name, "(", $t1933, ")");
                                    t = $rc_187;
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
                  throw march_panic_error("panic: ", "non-exhaustive pattern match");
                  break;
                }
              }
            }
            {
              const $trmc11 = { $: "Cons", _0: t, _1: null };
              Authority$option_texts$dps(rest, $trmc11);
              return $trmc11;
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
const Authority$option_texts$clo = { _0: ($_, opts) => Authority$option_texts(opts) };

function Authority$option_texts$dps($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const opts = $tco_a0;
    const $dst = $tco_a1;
    switch (opts.$) {
      case "Nil": {
        {
          const $trmc9 = { $: "Nil" };
          return ($dst._1 = $trmc9, undefined);
        }
        break;
      }
      case "Cons": {
        const $f1936 = opts._0;
        const $f1937 = opts._1;
        {
          const rest = $f1937;
          {
            const o = $f1936;
            {
              let t;
              {
                const $t1924 = march_string_index_of(o, "=");
                switch ($t1924.$) {
                  case "None": {
                    t = o;
                    break;
                  }
                  case "Some": {
                    const $f1934 = $t1924._0;
                    {
                      const i = $f1934;
                      {
                        const name = march_string_slice(o, 0, i);
                        {
                          let v;
                          {
                            const $t1925 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                            {
                              let $t1928;
                              {
                                let $t1927;
                                {
                                  const $t1926 = march_string_byte_length(o);
                                  $t1927 = (($t1926 - i) < 4611686018427387904 && ($t1926 - i) >= -4611686018427387904 ? ($t1926 - i) : march_int_ovf(($t1926 - i), 1));
                                }
                                $t1928 = (($t1927 - 1) < 4611686018427387904 && ($t1927 - 1) >= -4611686018427387904 ? ($t1927 - 1) : march_int_ovf(($t1927 - 1), 1));
                              }
                              {
                                const $rc_196 = march_string_slice(o, $t1925, $t1928);
                                v = $rc_196;
                              }
                            }
                          }
                          {
                            const $t1929 = (name === "name");
                            if ($t1929 === true) {
                              {
                                const $rc_190 = Authority$quote(v);
                                t = $rc_190;
                              }
                            } else {
                              {
                                const $t1930 = (name === "methods");
                                if ($t1930 === true) {
                                  {
                                    let $t1932;
                                    {
                                      let $t1931;
                                      {
                                        const $rc_193 = march_string_split(v, ",");
                                        $t1931 = $rc_193;
                                      }
                                      {
                                        const $rc_192 = march_string_join($t1931, ", ");
                                        $t1932 = $rc_192;
                                      }
                                    }
                                    {
                                      const $rc_191 = march_string_concat3("methods(", $t1932, ")");
                                      t = $rc_191;
                                    }
                                  }
                                } else {
                                  {
                                    let $t1933;
                                    {
                                      const $rc_195 = Authority$quote(v);
                                      $t1933 = $rc_195;
                                    }
                                    {
                                      const $rc_194 = march_string_concat_n(name, "(", $t1933, ")");
                                      t = $rc_194;
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
                    throw march_panic_error("panic: ", "non-exhaustive pattern match");
                    break;
                  }
                }
              }
              {
                const $trmc10 = { $: "Cons", _0: t, _1: null };
                ($dst._1 = $trmc10, undefined);
                {
                  $tco_a0 = rest;
                  $tco_a1 = $trmc10;
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
          const $trmc8 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc8, undefined);
        }
      }
    }
    return undefined;
  }
}
const Authority$option_texts$dps$clo = { _0: ($_, opts, $dst) => Authority$option_texts$dps(opts, $dst) };

function Authority$quote(s) {
  {
    let $t1943;
    {
      const $t1942 = march_string_replace_all(s, "\\", "\\\\");
      {
        const $rc_198 = march_string_replace_all($t1942, "\"", "\\\"");
        $t1943 = $rc_198;
      }
    }
    {
      const $rc_197 = march_string_concat3("\"", $t1943, "\"");
      return $rc_197;
    }
  }
}
const Authority$quote$clo = { _0: ($_, s) => Authority$quote(s) };

function Authority$quote_all(l) {
  switch (l.$) {
    case "Nil": {
      return { $: "Nil" };
      break;
    }
    case "Cons": {
      const $f1946 = l._0;
      const $f1947 = l._1;
      {
        const rest = $f1947;
        {
          const x = $f1946;
          {
            let $t1944;
            {
              const $rc_199 = Authority$quote(x);
              $t1944 = $rc_199;
            }
            {
              const $trmc15 = { $: "Cons", _0: $t1944, _1: null };
              Authority$quote_all$dps(rest, $trmc15);
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
const Authority$quote_all$clo = { _0: ($_, l) => Authority$quote_all(l) };

function Authority$quote_all$dps($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const l = $tco_a0;
    const $dst = $tco_a1;
    switch (l.$) {
      case "Nil": {
        {
          const $trmc13 = { $: "Nil" };
          return ($dst._1 = $trmc13, undefined);
        }
        break;
      }
      case "Cons": {
        const $f1946 = l._0;
        const $f1947 = l._1;
        {
          const rest = $f1947;
          {
            const x = $f1946;
            {
              let $t1944;
              {
                const $rc_200 = Authority$quote(x);
                $t1944 = $rc_200;
              }
              {
                const $trmc14 = { $: "Cons", _0: $t1944, _1: null };
                ($dst._1 = $trmc14, undefined);
                {
                  $tco_a0 = rest;
                  $tco_a1 = $trmc14;
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
const Authority$quote_all$dps$clo = { _0: ($_, l, $dst) => Authority$quote_all$dps(l, $dst) };

function Authority$wrap_all$dps($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const l = $tco_a0;
    const pre = $tco_a1;
    const $dst = $tco_a2;
    switch (l.$) {
      case "Nil": {
        {
          const $trmc17 = { $: "Nil" };
          return ($dst._1 = $trmc17, undefined);
        }
        break;
      }
      case "Cons": {
        const $f1954 = l._0;
        const $f1955 = l._1;
        {
          const rest = $f1955;
          {
            const x = $f1954;
            {
              let $t1952;
              {
                const $rc_202 = march_string_concat3(pre, x, ")");
                $t1952 = $rc_202;
              }
              {
                const $trmc18 = { $: "Cons", _0: $t1952, _1: null };
                ($dst._1 = $trmc18, undefined);
                {
                  $tco_a0 = rest;
                  $tco_a1 = pre;
                  $tco_a2 = $trmc18;
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
          const $trmc16 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc16, undefined);
        }
      }
    }
    return undefined;
  }
}
const Authority$wrap_all$dps$clo = { _0: ($_, l, pre, $dst) => Authority$wrap_all$dps(l, pre, $dst) };

function Authority$rev($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const l = $tco_a0;
    const acc = $tco_a1;
    switch (l.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f1961 = l._0;
        const $f1962 = l._1;
        {
          const rest = $f1962;
          {
            const x = $f1961;
            {
              const $t1960 = { $: "Cons", _0: x, _1: acc };
              {
                $tco_a0 = rest;
                $tco_a1 = $t1960;
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
const Authority$rev$clo = { _0: ($_, l, acc) => Authority$rev(l, acc) };

function Authority$rev_scopes($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const l = $tco_a0;
    const acc = $tco_a1;
    switch (l.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f1968 = l._0;
        const $f1969 = l._1;
        {
          const rest = $f1969;
          {
            const x = $f1968;
            {
              const $t1967 = { $: "Cons", _0: x, _1: acc };
              {
                $tco_a0 = rest;
                $tco_a1 = $t1967;
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
const Authority$rev_scopes$clo = { _0: ($_, l, acc) => Authority$rev_scopes(l, acc) };

function Authority$member($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const l = $tco_a0;
    const x = $tco_a1;
    switch (l.$) {
      case "Nil": {
        return false;
        break;
      }
      case "Cons": {
        const $f1977 = l._0;
        const $f1978 = l._1;
        {
          const rest = $f1978;
          {
            const y = $f1977;
            {
              const $t1976 = (y === x);
              if ($t1976 === true) {
                return true;
              } else {
                {
                  $tco_a0 = rest;
                  $tco_a1 = x;
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
const Authority$member$clo = { _0: ($_, l, x) => Authority$member(l, x) };

function Authority$all_member($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const xs = $tco_a0;
    const l = $tco_a1;
    switch (xs.$) {
      case "Nil": {
        return true;
        break;
      }
      case "Cons": {
        const $f1984 = xs._0;
        const $f1985 = xs._1;
        {
          const rest = $f1985;
          {
            const x = $f1984;
            {
              const $t1983 = Authority$member(l, x);
              if ($t1983 === true) {
                {
                  $tco_a0 = rest;
                  $tco_a1 = l;
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
const Authority$all_member$clo = { _0: ($_, xs, l) => Authority$all_member(xs, l) };

function Authority$prefix_all$dps($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const l = $tco_a0;
    const pre = $tco_a1;
    const $dst = $tco_a2;
    switch (l.$) {
      case "Nil": {
        {
          const $trmc21 = { $: "Nil" };
          return ($dst._1 = $trmc21, undefined);
        }
        break;
      }
      case "Cons": {
        const $f1992 = l._0;
        const $f1993 = l._1;
        {
          const rest = $f1993;
          {
            const x = $f1992;
            {
              let $t1990;
              {
                const $rc_204 = (pre + x);
                $t1990 = $rc_204;
              }
              {
                const $trmc22 = { $: "Cons", _0: $t1990, _1: null };
                ($dst._1 = $trmc22, undefined);
                {
                  $tco_a0 = rest;
                  $tco_a1 = pre;
                  $tco_a2 = $trmc22;
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
          const $trmc20 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc20, undefined);
        }
      }
    }
    return undefined;
  }
}
const Authority$prefix_all$dps$clo = { _0: ($_, l, pre, $dst) => Authority$prefix_all$dps(l, pre, $dst) };

function Authority$map_normalize$dps($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const l = $tco_a0;
    const $dst = $tco_a1;
    switch (l.$) {
      case "Nil": {
        {
          const $trmc25 = { $: "Nil" };
          return ($dst._1 = $trmc25, undefined);
        }
        break;
      }
      case "Cons": {
        const $f2000 = l._0;
        const $f2001 = l._1;
        {
          const rest = $f2001;
          {
            const x = $f2000;
            {
              let $t1998;
              {
                const $rc_206 = Authority$normalize(x);
                $t1998 = $rc_206;
              }
              {
                const $trmc26 = { $: "Cons", _0: $t1998, _1: null };
                ($dst._1 = $trmc26, undefined);
                {
                  $tco_a0 = rest;
                  $tco_a1 = $trmc26;
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
          const $trmc24 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc24, undefined);
        }
      }
    }
    return undefined;
  }
}
const Authority$map_normalize$dps$clo = { _0: ($_, l, $dst) => Authority$map_normalize$dps(l, $dst) };

function Js$Dom$find(id) {
  {
    const $rc_2723 = dom_get_element_by_id$clo._0(dom_get_element_by_id$clo, id);
    return $rc_2723;
  }
}
const Js$Dom$find$clo = { _0: ($_, id) => Js$Dom$find(id) };

function Js$Dom$create(tag) {
  {
    const $rc_2726 = dom_create_element$clo._0(dom_create_element$clo, tag);
    return $rc_2726;
  }
}
const Js$Dom$create$clo = { _0: ($_, tag) => Js$Dom$create(tag) };

function Js$Dom$append(parent, child) {
  {
    const $rc_2729 = dom_append_child$clo._0(dom_append_child$clo, parent, child);
    return $rc_2729;
  }
}
const Js$Dom$append$clo = { _0: ($_, parent, child) => Js$Dom$append(parent, child) };

function Js$Dom$get_attr(el, name) {
  {
    const $rc_2742 = dom_get_attribute$clo._0(dom_get_attribute$clo, el, name);
    return $rc_2742;
  }
}
const Js$Dom$get_attr$clo = { _0: ($_, el, name) => Js$Dom$get_attr(el, name) };

function Js$Dom$set_attr(el, name, val) {
  {
    const $rc_2743 = dom_set_attribute$clo._0(dom_set_attribute$clo, el, name, val);
    return $rc_2743;
  }
}
const Js$Dom$set_attr$clo = { _0: ($_, el, name, val) => Js$Dom$set_attr(el, name, val) };

function Js$Dom$add_class(el, cls) {
  {
    const $rc_2746 = dom_class_add$clo._0(dom_class_add$clo, el, cls);
    return $rc_2746;
  }
}
const Js$Dom$add_class$clo = { _0: ($_, el, cls) => Js$Dom$add_class(el, cls) };

function Js$Dom$set_style(el, prop, val) {
  {
    const $rc_2750 = dom_set_style$clo._0(dom_set_style$clo, el, prop, val);
    return $rc_2750;
  }
}
const Js$Dom$set_style$clo = { _0: ($_, el, prop, val) => Js$Dom$set_style(el, prop, val) };

function Js$Dom$listen(el, event, handler) {
  {
    const $rc_2754 = dom_add_event_listener$clo._0(dom_add_event_listener$clo, el, event, handler);
    return $rc_2754;
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
        const $t49266 = { _0: 0, _1: 1 };
        {
          const $t49267 = { _0: 1, _1: 1 };
          {
            const $t49268 = { _0: 2, _1: 1 };
            {
              const $t49269 = { _0: 3, _1: 1 };
              {
                const $t49270 = { $: "Nil" };
                {
                  const $t49271 = { $: "Cons", _0: $t49269, _1: $t49270 };
                  {
                    const $t49272 = { $: "Cons", _0: $t49268, _1: $t49271 };
                    {
                      const $t49273 = { $: "Cons", _0: $t49267, _1: $t49272 };
                      return { $: "Cons", _0: $t49266, _1: $t49273 };
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
        const $t49274 = { _0: 1, _1: 1 };
        {
          const $t49275 = { _0: 2, _1: 1 };
          {
            const $t49276 = { _0: 1, _1: 2 };
            {
              const $t49277 = { _0: 2, _1: 2 };
              {
                const $t49278 = { $: "Nil" };
                {
                  const $t49279 = { $: "Cons", _0: $t49277, _1: $t49278 };
                  {
                    const $t49280 = { $: "Cons", _0: $t49276, _1: $t49279 };
                    {
                      const $t49281 = { $: "Cons", _0: $t49275, _1: $t49280 };
                      return { $: "Cons", _0: $t49274, _1: $t49281 };
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
        const $t49282 = { _0: 1, _1: 1 };
        {
          const $t49283 = { _0: 0, _1: 2 };
          {
            const $t49284 = { _0: 1, _1: 2 };
            {
              const $t49285 = { _0: 2, _1: 2 };
              {
                const $t49286 = { $: "Nil" };
                {
                  const $t49287 = { $: "Cons", _0: $t49285, _1: $t49286 };
                  {
                    const $t49288 = { $: "Cons", _0: $t49284, _1: $t49287 };
                    {
                      const $t49289 = { $: "Cons", _0: $t49283, _1: $t49288 };
                      return { $: "Cons", _0: $t49282, _1: $t49289 };
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
        const $t49290 = { _0: 1, _1: 1 };
        {
          const $t49291 = { _0: 2, _1: 1 };
          {
            const $t49292 = { _0: 0, _1: 2 };
            {
              const $t49293 = { _0: 1, _1: 2 };
              {
                const $t49294 = { $: "Nil" };
                {
                  const $t49295 = { $: "Cons", _0: $t49293, _1: $t49294 };
                  {
                    const $t49296 = { $: "Cons", _0: $t49292, _1: $t49295 };
                    {
                      const $t49297 = { $: "Cons", _0: $t49291, _1: $t49296 };
                      return { $: "Cons", _0: $t49290, _1: $t49297 };
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
        const $t49298 = { _0: 0, _1: 1 };
        {
          const $t49299 = { _0: 1, _1: 1 };
          {
            const $t49300 = { _0: 1, _1: 2 };
            {
              const $t49301 = { _0: 2, _1: 2 };
              {
                const $t49302 = { $: "Nil" };
                {
                  const $t49303 = { $: "Cons", _0: $t49301, _1: $t49302 };
                  {
                    const $t49304 = { $: "Cons", _0: $t49300, _1: $t49303 };
                    {
                      const $t49305 = { $: "Cons", _0: $t49299, _1: $t49304 };
                      return { $: "Cons", _0: $t49298, _1: $t49305 };
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
        const $t49306 = { _0: 0, _1: 1 };
        {
          const $t49307 = { _0: 0, _1: 2 };
          {
            const $t49308 = { _0: 1, _1: 2 };
            {
              const $t49309 = { _0: 2, _1: 2 };
              {
                const $t49310 = { $: "Nil" };
                {
                  const $t49311 = { $: "Cons", _0: $t49309, _1: $t49310 };
                  {
                    const $t49312 = { $: "Cons", _0: $t49308, _1: $t49311 };
                    {
                      const $t49313 = { $: "Cons", _0: $t49307, _1: $t49312 };
                      return { $: "Cons", _0: $t49306, _1: $t49313 };
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
        const $t49314 = { _0: 2, _1: 1 };
        {
          const $t49315 = { _0: 0, _1: 2 };
          {
            const $t49316 = { _0: 1, _1: 2 };
            {
              const $t49317 = { _0: 2, _1: 2 };
              {
                const $t49318 = { $: "Nil" };
                {
                  const $t49319 = { $: "Cons", _0: $t49317, _1: $t49318 };
                  {
                    const $t49320 = { $: "Cons", _0: $t49316, _1: $t49319 };
                    {
                      const $t49321 = { $: "Cons", _0: $t49315, _1: $t49320 };
                      return { $: "Cons", _0: $t49314, _1: $t49321 };
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
  const $f49331 = c._0;
  const $f49332 = c._1;
  {
    const y = $f49332;
    {
      const x = $f49331;
      {
        const $t49330 = ((3 - y) < 4611686018427387904 && (3 - y) >= -4611686018427387904 ? (3 - y) : march_int_ovf((3 - y), 1));
        return { _0: $t49330, _1: x };
      }
    }
  }
}
const TetrisLogic$rotate_cell$clo = { _0: ($_, c) => TetrisLogic$rotate_cell(c) };

function TetrisLogic$clear_lines(board) {
  {
    let rows;
    {
      const go_i5889 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
      {
        const $t2073_i5891 = { $: "Nil" };
        rows = go$apply$0_List_range(go_i5889, 19, $t2073_i5891);
      }
    }
    {
      let $t49378;
      $t49378 = { $: "$Clo_$lam0_TetrisLogic_clear_lines$0_TetrisLogic_clear_lines", _0: $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines, _1: board };
      {
        const kept_rows = List$filter$List_Int$Fn_Int_Bool(rows, $t49378);
        {
          let cleared;
          {
            let $t49380;
            {  };
            $t49380 = List$length_onto$List_Int$Int(kept_rows, 0);
            cleared = ((20 - $t49380) < 4611686018427387904 && (20 - $t49380) >= -4611686018427387904 ? (20 - $t49380) : march_int_ovf((20 - $t49380), 1));
          }
          {
            const $t49382 = { $: "$Clo_$lam1_TetrisLogic_clear_lines$1_TetrisLogic_clear_lines", _0: $lam1_TetrisLogic_clear_lines$apply$1_TetrisLogic_clear_lines, _1: board };
            {
              let kept_cells;
              {
                const f_i5884 = $t49382;
                {
                  const $t2165_i5885 = { $: "Nil" };
                  kept_cells = List$flat_map_go$List_Int$List_Int$Fn_Int_List_Int($t2165_i5885, kept_rows, f_i5884);
                }
              }
              {
                const $t49384 = ((cleared * 10) < 4611686018427387904 && (cleared * 10) >= -4611686018427387904 ? (cleared * 10) : march_int_ovf((cleared * 10), 2));
                {
                  let blank_cells;
                  {
                    const go_i5881 = { $: "$Clo_go$0_List_repeat_Int_Int", _0: go$apply$0_List_repeat_Int_Int, _1: 0 };
                    {
                      const $t2068_i5882 = { $: "Nil" };
                      blank_cells = go$apply$0_List_repeat_Int_Int(go_i5881, $t49384, $t2068_i5882);
                    }
                  }
                  {
                    let new_board;
                    {
                      let $t49385;
                      {
                        const xs_i14750 = blank_cells;
                        {
                          const ys_i14751 = kept_cells;
                          switch (xs_i14750.$) {
                            case "Nil": {
                              $t49385 = kept_cells;
                              break;
                            }
                            case "Cons": {
                              const $f2144_i14752 = xs_i14750._0;
                              const $f2145_i14753 = xs_i14750._1;
                              {
                                const t_i14754 = $f2145_i14753;
                                {
                                  const h_i14755 = $f2144_i14752;
                                  {
                                    const $trmc34_i14756 = { $: "Cons", _0: h_i14755, _1: null };
                                    List$append$dps$List_Int$List_Int$List_Int(t_i14754, kept_cells, $trmc34_i14756);
                                    $t49385 = $trmc34_i14756;
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
                      new_board = Array$from_list$List_Int($t49385);
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
    const $t49387 = { $: "$Clo_$lam0_int_list_to_string$0_int_list_to_string", _0: $lam0_int_list_to_string$apply$0_int_list_to_string };
    {
      let $t49388;
      {
        const xs_i14757 = xs;
        {
          const f_i14758 = $t49387;
          switch (xs_i14757.$) {
            case "Nil": {
              $t49388 = { $: "Nil" };
              break;
            }
            case "Cons": {
              const $f2152_i14759 = xs_i14757._0;
              const $f2153_i14760 = xs_i14757._1;
              {
                const t_i14761 = $f2153_i14760;
                {
                  const h_i14762 = $f2152_i14759;
                  {
                    let $t2150_i14763;
                    $t2150_i14763 = f_i14758._0(f_i14758, h_i14762);
                    {
                      const $trmc38_i14764 = { $: "Cons", _0: $t2150_i14763, _1: null };
                      List$map$dps$List_Int$Fn_Int_String$List_String(t_i14761, f_i14758, $trmc38_i14764);
                      $t49388 = $trmc38_i14764;
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
        const $rc_2805 = march_string_join($t49388, ",");
        return $rc_2805;
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
    const $t49411 = { $: "I" };
    {
      const $t49412 = { $: "O" };
      {
        const $t49413 = { $: "T" };
        {
          const $t49414 = { $: "S" };
          {
            const $t49415 = { $: "Z" };
            {
              const $t49416 = { $: "J" };
              {
                const $t49417 = { $: "L" };
                {
                  const $t49418 = { $: "Nil" };
                  {
                    const $t49419 = { $: "Cons", _0: $t49417, _1: $t49418 };
                    {
                      const $t49420 = { $: "Cons", _0: $t49416, _1: $t49419 };
                      {
                        const $t49421 = { $: "Cons", _0: $t49415, _1: $t49420 };
                        {
                          const $t49422 = { $: "Cons", _0: $t49414, _1: $t49421 };
                          {
                            const $t49423 = { $: "Cons", _0: $t49413, _1: $t49422 };
                            {
                              const $t49424 = { $: "Cons", _0: $t49412, _1: $t49423 };
                              {
                                const pieces = { $: "Cons", _0: $t49411, _1: $t49424 };
                                {
                                  let rng2;
                                  {
                                    const $t49393_i13506 = ((rng * 16807) < 4611686018427387904 && (rng * 16807) >= -4611686018427387904 ? (rng * 16807) : march_int_ovf((rng * 16807), 2));
                                    rng2 = (2147483647 === 0 ? march_mod_zero() : $t49393_i13506 % 2147483647);
                                  }
                                  {
                                    const idx = (7 === 0 ? march_mod_zero() : rng2 % 7);
                                    {
                                      let result;
                                      {
                                        const $t49425 = List$nth$List_Piece$Int(pieces, idx);
                                        result = { _0: $t49425, _1: rng2 };
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
    const $t49426 = Js$Dom$find("game-state");
    switch ($t49426.$) {
      case "Some": {
        const $f49427 = $t49426._0;
        {
          const el = $f49427;
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
    const $t49428 = Js$Dom$get_attr(el, name);
    switch ($t49428.$) {
      case "Some": {
        const $f49430 = $t49428._0;
        {
          const s = $f49430;
          {
            let $t49429;
            {
              const $rc_2807 = march_string_to_int(s);
              $t49429 = $rc_2807;
            }
            {
              const $rc_2806 = Option$unwrap_or$Option_Int$Int($t49429, _default);
              return $rc_2806;
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
    const $t49431 = Js$Dom$get_attr(el, name);
    switch ($t49431.$) {
      case "Some": {
        const $f49432 = $t49431._0;
        {
          const s = $f49432;
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
        let $t49433;
        {
          const xs_i14765 = cells;
          {
            const f_i14766 = TetrisLogic$rotate_cell$clo;
            switch (xs_i14765.$) {
              case "Nil": {
                $t49433 = { $: "Nil" };
                break;
              }
              case "Cons": {
                const $f2152_i14767 = xs_i14765._0;
                const $f2153_i14768 = xs_i14765._1;
                {
                  const t_i14769 = $f2153_i14768;
                  {
                    const h_i14770 = $f2152_i14767;
                    {
                      let $t2150_i14771;
                      $t2150_i14771 = f_i14766._0(f_i14766, h_i14770);
                      {
                        const $trmc38_i14772 = { $: "Cons", _0: $t2150_i14771, _1: null };
                        List$map$dps$List_T_Int_Int$Fn_T_Int_Int_T_Int_Int$List_T_Int_Int(t_i14769, f_i14766, $trmc38_i14772);
                        $t49433 = $trmc38_i14772;
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
          const $t49434 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
          {
            $tco_a0 = $t49433;
            $tco_a1 = $t49434;
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
        const $t49353_i5901 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: 3, _3: 0 };
        over = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t49353_i5901);
      }
      {
        const $t49437 = next_piece(rng);
        const $f49438 = $t49437._0;
        const $f49439 = $t49437._1;
        {
          const rng2 = $f49439;
          {
            const next2 = $f49438;
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
    const $t49478 = Js$Dom$find(id);
    switch ($t49478.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f49479 = $t49478._0;
        {
          const el = $f49479;
          {
            const el_i13507 = el;
            {
              const text_i13508 = text;
              {
                const $rc_2739_i13509 = dom_set_text$clo._0(dom_set_text$clo, el, text);
                return $rc_2739_i13509;
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
        let $t49480;
        $t49480 = get_str_attr(el, "data-over", "false");
        {
          const $rc_2816 = ($t49480 === "true");
          over = $rc_2816;
        }
      }
      if (over === true) {
        return {  };
      } else if (over === false) {
        {
          let board;
          {
            let $t49481;
            $t49481 = get_str_attr(el, "data-board", "");
            {
              let $t49482;
              {
                let $rc_2815;
                {
                  const $t49389_i5931 = march_string_split($t49481, ",");
                  {
                    const $t49392_i5932 = { $: "$Clo_$lam0_string_to_int_list$0_string_to_int_list", _0: $lam0_string_to_int_list$apply$0_string_to_int_list };
                    $rc_2815 = List$map$List_String$Fn_String_Int($t49389_i5931, $t49392_i5932);
                  }
                }
                $t49482 = $rc_2815;
              }
              board = Array$from_list$List_Int($t49482);
            }
          }
          {
            let piece;
            {
              let $t49483;
              $t49483 = get_str_attr(el, "data-piece", "I");
              {
                let $rc_2814;
                if ($t49483 === "I") {
                  $rc_2814 = { $: "I" };
                } else if ($t49483 === "O") {
                  $rc_2814 = { $: "O" };
                } else if ($t49483 === "T") {
                  $rc_2814 = { $: "T" };
                } else if ($t49483 === "S") {
                  $rc_2814 = { $: "S" };
                } else if ($t49483 === "Z") {
                  $rc_2814 = { $: "Z" };
                } else if ($t49483 === "J") {
                  $rc_2814 = { $: "J" };
                } else {
                  $rc_2814 = { $: "L" };
                }
                piece = $rc_2814;
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
                      let $t49484;
                      $t49484 = get_str_attr(el, "data-next", "O");
                      {
                        let $rc_2813;
                        if ($t49484 === "I") {
                          $rc_2813 = { $: "I" };
                        } else if ($t49484 === "O") {
                          $rc_2813 = { $: "O" };
                        } else if ($t49484 === "T") {
                          $rc_2813 = { $: "T" };
                        } else if ($t49484 === "S") {
                          $rc_2813 = { $: "S" };
                        } else if ($t49484 === "Z") {
                          $rc_2813 = { $: "Z" };
                        } else if ($t49484 === "J") {
                          $rc_2813 = { $: "J" };
                        } else {
                          $rc_2813 = { $: "L" };
                        }
                        next = $rc_2813;
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
                              const $t49485 = f._0(f, board, piece, rot, x, y, next, score, lines, rng);
                              const $f49505 = $t49485._0;
                              const $f49506 = $t49485._1;
                              const $f49507 = $t49485._2;
                              const $f49508 = $t49485._3;
                              const $f49509 = $t49485._4;
                              const $f49510 = $t49485._5;
                              const $f49511 = $t49485._6;
                              const $f49512 = $t49485._7;
                              const $f49513 = $t49485._8;
                              const $f49514 = $t49485._9;
                              {
                                const over2 = $f49514;
                                {
                                  const rng2 = $f49513;
                                  {
                                    const lines2 = $f49512;
                                    {
                                      const score2 = $f49511;
                                      {
                                        const next2 = $f49510;
                                        {
                                          const y2 = $f49509;
                                          {
                                            const x2 = $f49508;
                                            {
                                              const rot2 = $f49507;
                                              {
                                                const piece2 = $f49506;
                                                {
                                                  const board2 = $f49505;
                                                  {
                                                    let $eff;
                                                    {
                                                      let $t49445_i5926;
                                                      {
                                                        const go_i14687 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                                                        {
                                                          const $t2073_i14689 = { $: "Nil" };
                                                          $t49445_i5926 = go$apply$0_List_range(go_i14687, 19, $t2073_i14689);
                                                        }
                                                      }
                                                      {
                                                        const $t49457_i5927 = { $: "$Clo_$lam0_render_board$0_render_board", _0: $lam0_render_board$apply$0_render_board, _1: board2 };
                                                        {
                                                          const f_i14683 = $t49457_i5927;
                                                          {
                                                            const go_i14684 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i14683 };
                                                            $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i14684, $t49445_i5926);
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                  {
                                                    let $eff;
                                                    if (over2 === false) {
                                                      {
                                                        const base_cells_i5921 = TetrisLogic$piece_cells(piece2);
                                                        {
                                                          const rotated_i5922 = rotate_n(base_cells_i5921, rot2);
                                                          {
                                                            const $t49477_i5923 = { $: "$Clo_$lam0_render_falling$0_render_falling", _0: $lam0_render_falling$apply$0_render_falling, _1: x2, _2: y2, _3: piece2 };
                                                            {
                                                              const f_i14680 = $t49477_i5923;
                                                              {
                                                                const go_i14681 = { $: "$Clo_go$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_", _0: go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_, _1: f_i14680 };
                                                                $eff = go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_(go_i14681, rotated_i5922);
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
                                                      let $t49487;
                                                      {
                                                        const $t49486 = String(score2);
                                                        {
                                                          const $rc_2812 = ("Score: " + $t49486);
                                                          $t49487 = $rc_2812;
                                                        }
                                                      }
                                                      $eff = set_text_if_found("score", $t49487);
                                                    }
                                                  }
                                                  {
                                                    let $eff;
                                                    {
                                                      let $t49490;
                                                      {
                                                        let $t49489;
                                                        {
                                                          const $t49488 = TetrisLogic$level_for_lines(lines2);
                                                          $t49489 = String($t49488);
                                                        }
                                                        {
                                                          const $rc_2811 = ("Level: " + $t49489);
                                                          $t49490 = $rc_2811;
                                                        }
                                                      }
                                                      $eff = set_text_if_found("level", $t49490);
                                                    }
                                                  }
                                                  {
                                                    let $eff;
                                                    {
                                                      let $t49492;
                                                      {
                                                        const $t49491 = piece_to_string(next2);
                                                        {
                                                          const $rc_2810 = ("Next: " + $t49491);
                                                          $t49492 = $rc_2810;
                                                        }
                                                      }
                                                      $eff = set_text_if_found("next", $t49492);
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
                                                        let $t49494;
                                                        {
                                                          let $t49493;
                                                          {
                                                            const $t10804_i5914 = { $: "Nil" };
                                                            {
                                                              const $t10806_i5915 = { $: "$Clo_$lam0_Array_to_list$0_Array_to_list_PVec_Int", _0: $lam0_Array_to_list$apply$0_Array_to_list_PVec_Int };
                                                              {
                                                                const rev_i5916 = Array$fold_left$PVec_Int$List_Int$Fn_List_Int_Int_List_Int(board2, $t10804_i5914, $t10806_i5915);
                                                                {
                                                                  const go_i14677 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                                                                  {
                                                                    const $t10390_i14678 = { $: "Nil" };
                                                                    $t49493 = go$apply$0_Array_lst_rev_List_Int(go_i14677, rev_i5916, $t10390_i14678);
                                                                  }
                                                                }
                                                              }
                                                            }
                                                          }
                                                          $t49494 = int_list_to_string($t49493);
                                                        }
                                                        $eff = Js$Dom$set_attr(el, "data-board", $t49494);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        let $t49495;
                                                        {
                                                          const $rc_2809 = piece_to_string(piece2);
                                                          $t49495 = $rc_2809;
                                                        }
                                                        $eff = Js$Dom$set_attr(el, "data-piece", $t49495);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t49496 = String(rot2);
                                                        $eff = Js$Dom$set_attr(el, "data-rot", $t49496);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t49497 = String(x2);
                                                        $eff = Js$Dom$set_attr(el, "data-x", $t49497);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t49498 = String(y2);
                                                        $eff = Js$Dom$set_attr(el, "data-y", $t49498);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        let $t49499;
                                                        {
                                                          const $rc_2808 = piece_to_string(next2);
                                                          $t49499 = $rc_2808;
                                                        }
                                                        $eff = Js$Dom$set_attr(el, "data-next", $t49499);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t49500 = String(score2);
                                                        $eff = Js$Dom$set_attr(el, "data-score", $t49500);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t49501 = String(lines2);
                                                        $eff = Js$Dom$set_attr(el, "data-lines", $t49501);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t49502 = String(rng2);
                                                        $eff = Js$Dom$set_attr(el, "data-rng", $t49502);
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
                                                        let $t49504;
                                                        {
                                                          const $t49503 = ((seq + 1) < 4611686018427387904 && (seq + 1) >= -4611686018427387904 ? (seq + 1) : march_int_ovf((seq + 1), 0));
                                                          $t49504 = String($t49503);
                                                        }
                                                        return Js$Dom$set_attr(el, "data-seq", $t49504);
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
    const $t49551 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t49551, rot);
      {
        let locked;
        {
          let $t49552;
          switch (piece.$) {
            case "I": {
              $t49552 = 1;
              break;
            }
            case "O": {
              $t49552 = 2;
              break;
            }
            case "T": {
              $t49552 = 3;
              break;
            }
            case "S": {
              $t49552 = 4;
              break;
            }
            case "Z": {
              $t49552 = 5;
              break;
            }
            case "J": {
              $t49552 = 6;
              break;
            }
            case "L": {
              $t49552 = 7;
              break;
            }
            default: {
              throw march_panic_error("panic: ", "non-exhaustive pattern match");
              break;
            }
          }
          {
            const $t49363_i5939 = { $: "$Clo_$lam0_TetrisLogic_lock_piece$0_TetrisLogic_lock_piece", _0: $lam0_TetrisLogic_lock_piece$apply$0_TetrisLogic_lock_piece, _1: $t49552, _2: x, _3: y };
            locked = List$fold_left$List_T_Int_Int$PVec_Int$Fn_PVec_Int_T_Int_Int_PVec_Int(cells, board, $t49363_i5939);
          }
        }
        {
          const $t49553 = TetrisLogic$clear_lines(locked);
          const $f49587 = $t49553._0;
          const $f49588 = $t49553._1;
          {
            const n = $f49588;
            {
              const cleared_board = $f49587;
              {
                let new_score;
                {
                  let $t49554;
                  if (n === 1) {
                    $t49554 = 100;
                  } else if (n === 2) {
                    $t49554 = 300;
                  } else if (n === 3) {
                    $t49554 = 500;
                  } else if (n === 4) {
                    $t49554 = 800;
                  } else {
                    $t49554 = 0;
                  }
                  new_score = ((score + $t49554) < 4611686018427387904 && (score + $t49554) >= -4611686018427387904 ? (score + $t49554) : march_int_ovf((score + $t49554), 0));
                }
                {
                  const new_lines = ((lines + n) < 4611686018427387904 && (lines + n) >= -4611686018427387904 ? (lines + n) : march_int_ovf((lines + n), 0));
                  {
                    let $t49555;
                    $t49555 = spawn_piece(next, cleared_board, rng);
                    const $f49556 = $t49555._0;
                    const $f49557 = $t49555._1;
                    const $f49558 = $t49555._2;
                    const $f49559 = $t49555._3;
                    const $f49560 = $t49555._4;
                    const $f49561 = $t49555._5;
                    const $f49562 = $t49555._6;
                    {
                      const over = $f49562;
                      {
                        const rng2 = $f49561;
                        {
                          const next2 = $f49560;
                          {
                            const y2 = $f49559;
                            {
                              const x2 = $f49558;
                              {
                                const rot2 = $f49557;
                                {
                                  const piece2 = $f49556;
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
    let $t49594;
    {
      const $t49593 = state_el();
      $t49594 = get_str_attr($t49593, "data-paused", "false");
    }
    {
      const $rc_2817 = ($t49594 === "true");
      return $rc_2817;
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
        let $t49595;
        $t49595 = get_str_attr(el, "data-over", "false");
        {
          const $rc_2818 = ($t49595 === "true");
          over = $rc_2818;
        }
      }
      if (over === true) {
        return {  };
      } else if (over === false) {
        {
          let $t49597;
          {
            const $t49596 = is_paused();
            $t49597 = (!$t49596);
          }
          return set_paused(el, $t49597);
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
      let $t49624;
      {
        const $t49623 = ((cur_y + 1) < 4611686018427387904 && (cur_y + 1) >= -4611686018427387904 ? (cur_y + 1) : march_int_ovf((cur_y + 1), 0));
        {
          const $t49353_i5947 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: x, _3: $t49623 };
          $t49624 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t49353_i5947);
        }
      }
      if ($t49624 === true) {
        return cur_y;
      } else if ($t49624 === false) {
        {
          const $t49625 = ((cur_y + 1) < 4611686018427387904 && (cur_y + 1) >= -4611686018427387904 ? (cur_y + 1) : march_int_ovf((cur_y + 1), 0));
          {
            $tco_a0 = board;
            $tco_a1 = cells;
            $tco_a2 = x;
            $tco_a3 = $t49625;
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
        let $t49329_i5966;
        {
          const go_i14708 = { $: "$Clo_go$0_List_repeat_Int_Int", _0: go$apply$0_List_repeat_Int_Int, _1: 0 };
          {
            const $t2068_i14709 = { $: "Nil" };
            $t49329_i5966 = go$apply$0_List_repeat_Int_Int(go_i14708, 200, $t2068_i14709);
          }
        }
        board = Array$from_list$List_Int($t49329_i5966);
      }
      {
        let rng0;
        {
          let raw_i13515;
          {
            let $t49397_i13514;
            {
              let $t49396_i13513;
              {
                let $t49395_i13512;
                {
                  const $t49394_i13511 = {  };
                  $t49395_i13512 = march_unix_time();
                }
                $t49396_i13513 = ($t49395_i13512 * 1000000.0);
              }
              $t49397_i13514 = march_float_to_int($t49396_i13513);
            }
            raw_i13515 = march_int_mod($t49397_i13514, 2147483646);
          }
          {
            const $t49398_i13516 = (raw_i13515 <= 0);
            if ($t49398_i13516 === true) {
              rng0 = ((raw_i13515 + 2147483646) < 4611686018427387904 && (raw_i13515 + 2147483646) >= -4611686018427387904 ? (raw_i13515 + 2147483646) : march_int_ovf((raw_i13515 + 2147483646), 0));
            } else if ($t49398_i13516 === false) {
              rng0 = raw_i13515;
            } else {
              throw march_panic_error("panic: ", "non-exhaustive pattern match");
            }
          }
        }
        {
          const $t49629 = next_piece(rng0);
          const $f49675 = $t49629._0;
          const $f49676 = $t49629._1;
          {
            const rng1 = $f49676;
            {
              const first = $f49675;
              {
                let $t49630;
                $t49630 = spawn_piece(first, board, rng1);
                const $f49644 = $t49630._0;
                const $f49645 = $t49630._1;
                const $f49646 = $t49630._2;
                const $f49647 = $t49630._3;
                const $f49648 = $t49630._4;
                const $f49649 = $t49630._5;
                const $f49650 = $t49630._6;
                {
                  const rng2 = $f49649;
                  {
                    const next = $f49648;
                    {
                      const y = $f49647;
                      {
                        const x = $f49646;
                        {
                          const rot = $f49645;
                          {
                            const piece = $f49644;
                            {
                              let $eff;
                              {
                                let $t49445_i5961;
                                {
                                  const go_i14703 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                                  {
                                    const $t2073_i14705 = { $: "Nil" };
                                    $t49445_i5961 = go$apply$0_List_range(go_i14703, 19, $t2073_i14705);
                                  }
                                }
                                {
                                  const $t49457_i5962 = { $: "$Clo_$lam0_render_board$0_render_board", _0: $lam0_render_board$apply$0_render_board, _1: board };
                                  {
                                    const f_i14699 = $t49457_i5962;
                                    {
                                      const go_i14700 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i14699 };
                                      $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i14700, $t49445_i5961);
                                    }
                                  }
                                }
                              }
                            }
                            {
                              let $eff;
                              {
                                const base_cells_i5956 = TetrisLogic$piece_cells(piece);
                                {
                                  const rotated_i5957 = rotate_n(base_cells_i5956, rot);
                                  {
                                    const $t49477_i5958 = { $: "$Clo_$lam0_render_falling$0_render_falling", _0: $lam0_render_falling$apply$0_render_falling, _1: x, _2: y, _3: piece };
                                    {
                                      const f_i14696 = $t49477_i5958;
                                      {
                                        const go_i14697 = { $: "$Clo_go$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_", _0: go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_, _1: f_i14696 };
                                        $eff = go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_(go_i14697, rotated_i5957);
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
                                let $t49632;
                                {
                                  const $t49631 = piece_to_string(next);
                                  {
                                    const $rc_2821 = ("Next: " + $t49631);
                                    $t49632 = $rc_2821;
                                  }
                                }
                                $eff = set_text_if_found("next", $t49632);
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
                                let $t49634;
                                {
                                  let $t49633;
                                  {
                                    const $t10804_i5949 = { $: "Nil" };
                                    {
                                      const $t10806_i5950 = { $: "$Clo_$lam0_Array_to_list$0_Array_to_list_PVec_Int", _0: $lam0_Array_to_list$apply$0_Array_to_list_PVec_Int };
                                      {
                                        const rev_i5951 = Array$fold_left$PVec_Int$List_Int$Fn_List_Int_Int_List_Int(board, $t10804_i5949, $t10806_i5950);
                                        {
                                          const go_i14693 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                                          {
                                            const $t10390_i14694 = { $: "Nil" };
                                            $t49633 = go$apply$0_Array_lst_rev_List_Int(go_i14693, rev_i5951, $t10390_i14694);
                                          }
                                        }
                                      }
                                    }
                                  }
                                  $t49634 = int_list_to_string($t49633);
                                }
                                $eff = Js$Dom$set_attr(el, "data-board", $t49634);
                              }
                            }
                            {
                              let $eff;
                              {
                                let $t49635;
                                {
                                  const $rc_2820 = piece_to_string(piece);
                                  $t49635 = $rc_2820;
                                }
                                $eff = Js$Dom$set_attr(el, "data-piece", $t49635);
                              }
                            }
                            {
                              let $eff;
                              {
                                const $t49636 = String(rot);
                                $eff = Js$Dom$set_attr(el, "data-rot", $t49636);
                              }
                            }
                            {
                              let $eff;
                              {
                                const $t49637 = String(x);
                                $eff = Js$Dom$set_attr(el, "data-x", $t49637);
                              }
                            }
                            {
                              let $eff;
                              {
                                const $t49638 = String(y);
                                $eff = Js$Dom$set_attr(el, "data-y", $t49638);
                              }
                            }
                            {
                              let $eff;
                              {
                                let $t49639;
                                {
                                  const $rc_2819 = piece_to_string(next);
                                  $t49639 = $rc_2819;
                                }
                                $eff = Js$Dom$set_attr(el, "data-next", $t49639);
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
                                const $t49640 = String(rng2);
                                $eff = Js$Dom$set_attr(el, "data-rng", $t49640);
                              }
                            }
                            {
                              let $eff;
                              $eff = Js$Dom$set_attr(el, "data-over", "false");
                            }
                            {
                              let $t49643;
                              {
                                let $t49642;
                                {
                                  let $t49641;
                                  $t49641 = get_int_attr(el, "data-seq", 0);
                                  $t49642 = (($t49641 + 1) < 4611686018427387904 && ($t49641 + 1) >= -4611686018427387904 ? ($t49641 + 1) : march_int_ovf(($t49641 + 1), 0));
                                }
                                $t49643 = String($t49642);
                              }
                              return Js$Dom$set_attr(el, "data-seq", $t49643);
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
    const $t49681 = Js$Dom$find("restore-request");
    switch ($t49681.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f49697 = $t49681._0;
        {
          const req = $f49697;
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
                                  let $t49682;
                                  $t49682 = get_str_attr(req, "data-over", "false");
                                  {
                                    const $rc_2827 = ($t49682 === "true");
                                    over = $rc_2827;
                                  }
                                }
                                {
                                  let paused;
                                  {
                                    const $t49683 = get_str_attr(req, "data-paused", "false");
                                    {
                                      const $rc_2826 = ($t49683 === "true");
                                      paused = $rc_2826;
                                    }
                                  }
                                  {
                                    let board;
                                    {
                                      let $t49684;
                                      {
                                        const $t49389_i5981 = march_string_split(board_s, ",");
                                        {
                                          const $t49392_i5982 = { $: "$Clo_$lam0_string_to_int_list$0_string_to_int_list", _0: $lam0_string_to_int_list$apply$0_string_to_int_list };
                                          $t49684 = List$map$List_String$Fn_String_Int($t49389_i5981, $t49392_i5982);
                                        }
                                      }
                                      board = Array$from_list$List_Int($t49684);
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
                                            let $t49445_i5976;
                                            {
                                              const go_i14718 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                                              {
                                                const $t2073_i14720 = { $: "Nil" };
                                                $t49445_i5976 = go$apply$0_List_range(go_i14718, 19, $t2073_i14720);
                                              }
                                            }
                                            {
                                              const $t49457_i5977 = { $: "$Clo_$lam0_render_board$0_render_board", _0: $lam0_render_board$apply$0_render_board, _1: board };
                                              {
                                                const f_i14714 = $t49457_i5977;
                                                {
                                                  const go_i14715 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i14714 };
                                                  $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i14715, $t49445_i5976);
                                                }
                                              }
                                            }
                                          }
                                        }
                                        {
                                          let $eff;
                                          if (over === false) {
                                            {
                                              const base_cells_i5971 = TetrisLogic$piece_cells(piece);
                                              {
                                                const rotated_i5972 = rotate_n(base_cells_i5971, rot);
                                                {
                                                  const $t49477_i5973 = { $: "$Clo_$lam0_render_falling$0_render_falling", _0: $lam0_render_falling$apply$0_render_falling, _1: x, _2: y, _3: piece };
                                                  {
                                                    const f_i14711 = $t49477_i5973;
                                                    {
                                                      const go_i14712 = { $: "$Clo_go$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_", _0: go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_, _1: f_i14711 };
                                                      $eff = go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_(go_i14712, rotated_i5972);
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
                                            let $t49686;
                                            {
                                              const $t49685 = String(score);
                                              {
                                                const $rc_2825 = ("Score: " + $t49685);
                                                $t49686 = $rc_2825;
                                              }
                                            }
                                            $eff = set_text_if_found("score", $t49686);
                                          }
                                        }
                                        {
                                          let $eff;
                                          {
                                            let $t49689;
                                            {
                                              let $t49688;
                                              {
                                                const $t49687 = TetrisLogic$level_for_lines(lines);
                                                $t49688 = String($t49687);
                                              }
                                              {
                                                const $rc_2824 = ("Level: " + $t49688);
                                                $t49689 = $rc_2824;
                                              }
                                            }
                                            $eff = set_text_if_found("level", $t49689);
                                          }
                                        }
                                        {
                                          let $eff;
                                          {
                                            let $t49691;
                                            {
                                              let $t49690;
                                              {
                                                const $rc_2823 = piece_to_string(next);
                                                $t49690 = $rc_2823;
                                              }
                                              {
                                                const $rc_2822 = ("Next: " + $t49690);
                                                $t49691 = $rc_2822;
                                              }
                                            }
                                            $eff = set_text_if_found("next", $t49691);
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
                                              const $t49692 = String(rot);
                                              $eff = Js$Dom$set_attr(el, "data-rot", $t49692);
                                            }
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t49693 = String(x);
                                              $eff = Js$Dom$set_attr(el, "data-x", $t49693);
                                            }
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t49694 = String(y);
                                              $eff = Js$Dom$set_attr(el, "data-y", $t49694);
                                            }
                                          }
                                          {
                                            let $eff;
                                            $eff = Js$Dom$set_attr(el, "data-next", next_s);
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t49695 = String(score);
                                              $eff = Js$Dom$set_attr(el, "data-score", $t49695);
                                            }
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t49696 = String(lines);
                                              $eff = Js$Dom$set_attr(el, "data-lines", $t49696);
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
      const ev_i13519 = ev;
      {
        const $rc_2758_i13520 = dom_event_key$clo._0(dom_event_key$clo, ev);
        key = $rc_2758_i13520;
      }
    }
    {
      let $eff;
      {
        let $t49709;
        if (key === "ArrowLeft") {
          $t49709 = true;
        } else if (key === "ArrowRight") {
          $t49709 = true;
        } else if (key === "ArrowDown") {
          $t49709 = true;
        } else if (key === "ArrowUp") {
          $t49709 = true;
        } else if (key === " ") {
          $t49709 = true;
        } else {
          $t49709 = false;
        }
        if ($t49709 === true) {
          {
            const ev_i13517 = ev;
            {
              const $rc_2759_i13518 = dom_prevent_default$clo._0(dom_prevent_default$clo, ev);
              $eff = $rc_2759_i13518;
            }
          }
        } else if ($t49709 === false) {
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
          const $t49710 = is_paused();
          if ($t49710 === true) {
            return {  };
          } else if ($t49710 === false) {
            if (k === "ArrowLeft") {
              {
                const $t49711 = march_int_ovf(-(1), 3);
                {
                  const $t49617_i5993 = { $: "$Clo_$lam0_try_move$0_try_move", _0: $lam0_try_move$apply$0_try_move, _1: $t49711, _2: 0 };
                  return with_state($t49617_i5993);
                }
              }
            } else if (k === "ArrowRight") {
              {
                const $t49617_i5996 = { $: "$Clo_$lam0_try_move$0_try_move", _0: $lam0_try_move$apply$0_try_move, _1: 1, _2: 0 };
                return with_state($t49617_i5996);
              }
            } else if (k === "ArrowDown") {
              {
                const $t49617_i5999 = { $: "$Clo_$lam0_try_move$0_try_move", _0: $lam0_try_move$apply$0_try_move, _1: 0, _2: 1 };
                return with_state($t49617_i5999);
              }
            } else if (k === "ArrowUp") {
              {
                const $t49622_i6000 = { $: "$Clo_$lam0_try_rotate$0_try_rotate", _0: $lam0_try_rotate$apply$0_try_rotate };
                return with_state($t49622_i6000);
              }
            } else if (k === " ") {
              {
                const $t49628_i6001 = { $: "$Clo_$lam0_hard_drop$0_hard_drop", _0: $lam0_hard_drop$apply$0_hard_drop };
                return with_state($t49628_i6001);
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
  Authority$launch_init("IO.Clock, IO.Foreign", false);
  {
    const $t49730 = Js$Dom$find("board");
    switch ($t49730.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f49738 = $t49730._0;
        {
          const board_el = $f49738;
          {
            let $eff;
            {
              let $t49699_i6010;
              {
                const go_i14732 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                {
                  const $t2073_i14734 = { $: "Nil" };
                  $t49699_i6010 = go$apply$0_List_range(go_i14732, 19, $t2073_i14734);
                }
              }
              {
                const $t49708_i6011 = { $: "$Clo_$lam0_build_board_dom$0_build_board_dom", _0: $lam0_build_board_dom$apply$0_build_board_dom, _1: board_el };
                {
                  const f_i14728 = $t49708_i6011;
                  {
                    const go_i14729 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i14728 };
                    $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i14729, $t49699_i6010);
                  }
                }
              }
            }
          }
          restart();
          {
            let $eff;
            {
              const $t49731 = dom_body();
              {
                const $t49733 = { $: "$Clo_$lam0_main$0_main", _0: $lam0_main$apply$0_main };
                $eff = Js$Dom$listen($t49731, "keydown", $t49733);
              }
            }
          }
          {
            let $eff;
            {
              let level_i6005;
              {
                let $t49606_i6004;
                {
                  const $t49605_i6003 = state_el();
                  $t49606_i6004 = get_int_attr($t49605_i6003, "data-lines", 0);
                }
                level_i6005 = TetrisLogic$level_for_lines($t49606_i6004);
              }
              {
                let $t49607_i6006;
                {
                  let $t49323_i14725;
                  {
                    const $t49322_i14724 = ((level_i6005 * 40) < 4611686018427387904 && (level_i6005 * 40) >= -4611686018427387904 ? (level_i6005 * 40) : march_int_ovf((level_i6005 * 40), 2));
                    $t49323_i14725 = ((500 - $t49322_i14724) < 4611686018427387904 && (500 - $t49322_i14724) >= -4611686018427387904 ? (500 - $t49322_i14724) : march_int_ovf((500 - $t49322_i14724), 1));
                  }
                  {
                    const $t3631_i5864_i14726 = ($t49323_i14725 > 100);
                    if ($t3631_i5864_i14726 === true) {
                      $t49607_i6006 = $t49323_i14725;
                    } else {
                      $t49607_i6006 = 100;
                    }
                  }
                }
                {
                  const $t49609_i6007 = { $: "$Clo_$lam0_schedule_tick$0_schedule_tick", _0: $lam0_schedule_tick$apply$0_schedule_tick };
                  $eff = Js$Dom$set_timeout($t49607_i6006, $t49609_i6007);
                }
              }
            }
          }
          {
            const $t49734 = Js$Dom$find("restore-trigger");
            switch ($t49734.$) {
              case "None": {
                return {  };
                break;
              }
              case "Some": {
                const $f49737 = $t49734._0;
                {
                  const trigger = $f49737;
                  {
                    const $t49736 = { $: "$Clo_$lam1_main$1_main", _0: $lam1_main$apply$1_main };
                    return Js$Dom$listen(trigger, "click", $t49736);
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
        const $f2319 = xs._0;
        const $f2320 = xs._1;
        {
          const t = $f2320;
          {
            let h;
            h = $f2319;
            {
              let $t2318;
              $t2318 = pred._0(pred, h);
              if ($t2318 === true) {
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
        const $f2182 = xs._0;
        const $f2183 = xs._1;
        {
          const t = $f2183;
          {
            const h = $f2182;
            {
              let $t2180;
              $t2180 = pred._0(pred, h);
              if ($t2180 === true) {
                {
                  const $trmc47 = { $: "Cons", _0: h, _1: null };
                  List$filter$dps$List_Int$Fn_Int_Bool$List_Int(t, pred, $trmc47);
                  return $trmc47;
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
      const $f2011 = opt._0;
      {
        let x;
        x = $f2011;
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
      const go_i6328 = { $: "$Clo_go$0_Array_lst_len_List_Int", _0: go$apply$0_Array_lst_len_List_Int };
      n = go$apply$0_Array_lst_len_List_Int(go_i6328, xs, 0);
    }
    {
      const $t10909 = (n === 0);
      if ($t10909 === true) {
        {
          const $t10596_i6325 = { $: "TrieEmpty" };
          {
            const $t10597_i6326 = { $: "Nil" };
            return { $: "PVec", _0: 0, _1: 0, _2: $t10596_i6325, _3: $t10597_i6326 };
          }
        }
      } else {
        {
          let tail_len;
          {
            let $t10912;
            {
              let $t10911;
              {
                const $t10910 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                $t10911 = (32 === 0 ? march_div_zero() : ($t10910 - $t10910 % 32) / 32);
              }
              $t10912 = ((32 * $t10911) < 4611686018427387904 && (32 * $t10911) >= -4611686018427387904 ? (32 * $t10911) : march_int_ovf((32 * $t10911), 2));
            }
            tail_len = ((n - $t10912) < 4611686018427387904 && (n - $t10912) >= -4611686018427387904 ? (n - $t10912) : march_int_ovf((n - $t10912), 1));
          }
          {
            let $p10934;
            {
              const $t10913 = ((n - tail_len) < 4611686018427387904 && (n - tail_len) >= -4611686018427387904 ? (n - tail_len) : march_int_ovf((n - tail_len), 1));
              {
                const go_i6323 = { $: "$Clo_go$0_Array_lst_split_List_Int_Int", _0: go$apply$0_Array_lst_split_List_Int_Int };
                {
                  const $t10823_i6324 = { $: "Nil" };
                  $p10934 = go$apply$0_Array_lst_split_List_Int_Int(go_i6323, xs, $t10913, $t10823_i6324);
                }
              }
            }
            {
              const front = $p10934._0;
              {
                const tail = $p10934._1;
                {
                  const $t10914 = (n === tail_len);
                  if ($t10914 === true) {
                    {
                      const $t10915 = { $: "TrieEmpty" };
                      {
                        const $rc_3012 = { $: "PVec", _0: n, _1: 0, _2: $t10915, _3: tail };
                        return $rc_3012;
                      }
                    }
                  } else {
                    {
                      const up = { $: "$Clo_up$0_Array_from_list_List_Int", _0: up$apply$0_Array_from_list_List_Int };
                      {
                        let $p10933;
                        {
                          const $t10931 = { $: "$Clo_$lam0_Array_from_list$2_Array_from_list_List_Int", _0: $lam0_Array_from_list$apply$2_Array_from_list_List_Int };
                          {
                            let $t10932;
                            {
                              const wrap_i6317 = $t10931;
                              {
                                const chunk_i6318 = { $: "$Clo_chunk$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int", _0: chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int, _1: wrap_i6317 };
                                {
                                  const $t10843_i6319 = { $: "Nil" };
                                  {
                                    const $t10844_i6320 = { $: "Nil" };
                                    $t10932 = chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int(chunk_i6318, front, 0, $t10843_i6319, $t10844_i6320);
                                  }
                                }
                              }
                            }
                            $p10933 = up$apply$0_Array_from_list_List_Int(up, $t10932, 0);
                          }
                        }
                        {
                          const root = $p10933._0;
                          {
                            const shift = $p10933._1;
                            {
                              const $rc_3008 = { $: "PVec", _0: n, _1: shift, _2: root, _3: tail };
                              return $rc_3008;
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
        const $f2312 = xs._0;
        const $f2313 = xs._1;
        {
          const t = $f2313;
          {
            const h = $f2312;
            {
              let $t2311;
              $t2311 = pred._0(pred, h);
              if ($t2311 === true) {
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
      const $f10651 = v._0;
      const $f10652 = v._1;
      const $f10653 = v._2;
      const $f10654 = v._3;
      {
        const tail = $f10654;
        {
          const root = $f10653;
          {
            const shift = $f10652;
            {
              const n = $f10651;
              {
                let $t10648;
                {
                  const $t10646 = (idx < 0);
                  {
                    const $t10647 = (idx >= n);
                    $t10648 = ($t10646 || $t10647);
                  }
                }
                if ($t10648 === true) {
                  march_panic_site("stdlib/array.march", 432, 32, 70);
                  return (() => { throw march_panic_error("panic: ", "Array.get: index out of range"); })();
                } else {
                  {
                    let tail_len;
                    {
                      const go_i6330 = { $: "$Clo_go$0_Array_lst_len_List_Int", _0: go$apply$0_Array_lst_len_List_Int };
                      tail_len = go$apply$0_Array_lst_len_List_Int(go_i6330, tail, 0);
                    }
                    {
                      const tail_offset = ((n - tail_len) < 4611686018427387904 && (n - tail_len) >= -4611686018427387904 ? (n - tail_len) : march_int_ovf((n - tail_len), 1));
                      {
                        const $t10649 = (idx >= tail_offset);
                        if ($t10649 === true) {
                          {
                            const $t10650 = ((idx - tail_offset) < 4611686018427387904 && (idx - tail_offset) >= -4611686018427387904 ? (idx - tail_offset) : march_int_ovf((idx - tail_offset), 1));
                            {
                              const $rc_3013 = Array$lst_nth$List_Int$Int(tail, $t10650);
                              return $rc_3013;
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
        const $f2249 = xs._0;
        const $f2250 = xs._1;
        {
          const t = $f2250;
          {
            const h = $f2249;
            {
              let $t2248;
              $t2248 = f._0(f, acc, h);
              {
                $tco_a0 = t;
                $tco_a1 = $t2248;
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
      const $f10674 = v._0;
      const $f10675 = v._1;
      const $f10676 = v._2;
      const $f10677 = v._3;
      {
        const tail = $f10677;
        {
          const root = $f10676;
          {
            const shift = $f10675;
            {
              const n = $f10674;
              {
                let $t10669;
                {
                  const $t10667 = (idx < 0);
                  {
                    const $t10668 = (idx >= n);
                    $t10669 = ($t10667 || $t10668);
                  }
                }
                if ($t10669 === true) {
                  march_panic_site("stdlib/array.march", 463, 32, 70);
                  return (() => { throw march_panic_error("panic: ", "Array.set: index out of range"); })();
                } else {
                  {
                    let tail_len;
                    {
                      const go_i6343 = { $: "$Clo_go$0_Array_lst_len_List_Int", _0: go$apply$0_Array_lst_len_List_Int };
                      tail_len = go$apply$0_Array_lst_len_List_Int(go_i6343, tail, 0);
                    }
                    {
                      const tail_offset = ((n - tail_len) < 4611686018427387904 && (n - tail_len) >= -4611686018427387904 ? (n - tail_len) : march_int_ovf((n - tail_len), 1));
                      {
                        const $t10670 = (idx >= tail_offset);
                        if ($t10670 === true) {
                          {
                            const $t10671 = ((idx - tail_offset) < 4611686018427387904 && (idx - tail_offset) >= -4611686018427387904 ? (idx - tail_offset) : march_int_ovf((idx - tail_offset), 1));
                            {
                              let $t10672;
                              {
                                const rev_onto_i6339 = { $: "$Clo_rev_onto$0_Array_lst_set_List_Int_Int_Int", _0: rev_onto$apply$0_Array_lst_set_List_Int_Int_Int };
                                {
                                  const go_i6340 = { $: "$Clo_go$1_Array_lst_set_List_Int_Int_Int", _0: go$apply$1_Array_lst_set_List_Int_Int_Int, _1: rev_onto_i6339, _2: val };
                                  {
                                    const $t10422_i6341 = { $: "Nil" };
                                    $t10672 = go$apply$1_Array_lst_set_List_Int_Int_Int(go_i6340, tail, $t10671, $t10422_i6341);
                                  }
                                }
                              }
                              return { $: "PVec", _0: n, _1: shift, _2: root, _3: $t10672 };
                            }
                          }
                        } else {
                          {
                            let $t10673;
                            {
                              const $t10506_i6335 = { $: "Nil" };
                              $t10673 = Array$trie_update_down$TrieNode_Int$Int$List_T_List_TrieNode_Int_Int$Int$Int(root, shift, $t10506_i6335, idx, val);
                            }
                            return { $: "PVec", _0: n, _1: shift, _2: $t10673, _3: tail };
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
      const $f2152 = xs._0;
      const $f2153 = xs._1;
      {
        const t = $f2153;
        {
          const h = $f2152;
          {
            let $t2150;
            $t2150 = f._0(f, h);
            {
              const $trmc38 = { $: "Cons", _0: $t2150, _1: null };
              List$map$dps$List_String$Fn_String_Int$List_Int(t, f, $trmc38);
              return $trmc38;
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
        const $f2114 = xs._0;
        const $f2115 = xs._1;
        {
          const t = $f2115;
          {
            const h = $f2114;
            {
              const $t2112 = (n === 0);
              if ($t2112 === true) {
                return h;
              } else {
                {
                  const $t2113 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                  {
                    $tco_a0 = t;
                    $tco_a1 = $t2113;
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
          const $trmc36 = { $: "Nil" };
          return ($dst._1 = $trmc36, undefined);
        }
        break;
      }
      case "Cons": {
        const $f2152 = xs._0;
        const $f2153 = xs._1;
        {
          const t = $f2153;
          {
            const h = $f2152;
            {
              let $t2150;
              $t2150 = f._0(f, h);
              {
                const $trmc37 = { $: "Cons", _0: $t2150, _1: null };
                ($dst._1 = $trmc37, undefined);
                {
                  $tco_a0 = t;
                  $tco_a1 = f;
                  $tco_a2 = $trmc37;
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
          const $trmc35 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc35, undefined);
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
          const $trmc36 = { $: "Nil" };
          return ($dst._1 = $trmc36, undefined);
        }
        break;
      }
      case "Cons": {
        const $f2152 = xs._0;
        const $f2153 = xs._1;
        {
          const t = $f2153;
          {
            const h = $f2152;
            {
              let $t2150;
              $t2150 = f._0(f, h);
              {
                const $trmc37 = { $: "Cons", _0: $t2150, _1: null };
                ($dst._1 = $trmc37, undefined);
                {
                  $tco_a0 = t;
                  $tco_a1 = f;
                  $tco_a2 = $trmc37;
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
          const $trmc35 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc35, undefined);
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
        const $f2144 = xs._0;
        const $f2145 = xs._1;
        {
          const t = $f2145;
          {
            const h = $f2144;
            {
              const $trmc33 = { $: "Cons", _0: h, _1: null };
              ($dst._1 = $trmc33, undefined);
              {
                $tco_a0 = t;
                $tco_a1 = ys;
                $tco_a2 = $trmc33;
                continue __tco;
              }
            }
          }
        }
        break;
      }
      default: {
        {
          const $trmc31 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc31, undefined);
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
        const $f2129 = lst._0;
        const $f2130 = lst._1;
        {
          const t = $f2130;
          {
            const $t2128 = ((acc + 1) < 4611686018427387904 && (acc + 1) >= -4611686018427387904 ? (acc + 1) : march_int_ovf((acc + 1), 0));
            {
              $tco_a0 = t;
              $tco_a1 = $t2128;
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
          const $trmc45 = { $: "Nil" };
          return ($dst._1 = $trmc45, undefined);
        }
        break;
      }
      case "Cons": {
        const $f2182 = xs._0;
        const $f2183 = xs._1;
        {
          const t = $f2183;
          {
            const h = $f2182;
            {
              let $t2180;
              $t2180 = pred._0(pred, h);
              if ($t2180 === true) {
                {
                  const $trmc46 = { $: "Cons", _0: h, _1: null };
                  ($dst._1 = $trmc46, undefined);
                  {
                    $tco_a0 = t;
                    $tco_a1 = pred;
                    $tco_a2 = $trmc46;
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
          const $trmc44 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc44, undefined);
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
          const $trmc36 = { $: "Nil" };
          return ($dst._1 = $trmc36, undefined);
        }
        break;
      }
      case "Cons": {
        const $f2152 = xs._0;
        const $f2153 = xs._1;
        {
          const t = $f2153;
          {
            const h = $f2152;
            {
              let $t2150;
              $t2150 = f._0(f, h);
              {
                const $trmc37 = { $: "Cons", _0: $t2150, _1: null };
                ($dst._1 = $trmc37, undefined);
                {
                  $tco_a0 = t;
                  $tco_a1 = f;
                  $tco_a2 = $trmc37;
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
          const $trmc35 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc35, undefined);
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
        const $f10393 = lst._0;
        const $f10394 = lst._1;
        {
          const t = $f10394;
          {
            let h;
            h = $f10393;
            {
              const $t10391 = (n === 0);
              if ($t10391 === true) {
                return h;
              } else {
                {
                  const $t10392 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                  {
                    $tco_a0 = t;
                    $tco_a1 = $t10392;
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
        const $f10487 = node._0;
        {
          const values = $f10487;
          {
            const $t10484 = ((idx | 0) === idx && (31 | 0) === 31 ? (idx & 31) : march_int_and(idx, 31));
            {
              const $rc_3082 = Array$lst_nth$List_Int$Int(values, $t10484);
              return $rc_3082;
            }
          }
        }
        break;
      }
      case "TrieBranch": {
        const $f10488 = node._0;
        {
          const children = $f10488;
          {
            let slot;
            {
              const $t10483_i7873 = ((idx | 0) === idx && shift >= 0 && shift < 32 ? (idx >> shift) : march_int_shr(idx, shift));
              slot = (($t10483_i7873 | 0) === $t10483_i7873 && (31 | 0) === 31 ? ($t10483_i7873 & 31) : march_int_and($t10483_i7873, 31));
            }
            {
              const $t10485 = Array$lst_nth$List_TrieNode_Int$Int(children, slot);
              {
                const $t10486 = ((shift - 5) < 4611686018427387904 && (shift - 5) >= -4611686018427387904 ? (shift - 5) : march_int_ovf((shift - 5), 1));
                {
                  $tco_a0 = $t10485;
                  $tco_a1 = idx;
                  $tco_a2 = $t10486;
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
        const $f2174 = sub._0;
        const $f2175 = sub._1;
        {
          const rest = $f2175;
          {
            const x = $f2174;
            {
              const $trmc43 = { $: "Cons", _0: x, _1: null };
              List$flat_map_go$dps$List_Int$List_Int$Fn_Int_List_Int$List_Int(rest, lst, f, $trmc43);
              return $trmc43;
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
            const $f2168 = lst._0;
            const $f2169 = lst._1;
            {
              const t = $f2169;
              {
                const h = $f2168;
                {
                  let $t2167;
                  $t2167 = f._0(f, h);
                  {
                    $tco_a0 = $t2167;
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
          const $trmc36 = { $: "Nil" };
          return ($dst._1 = $trmc36, undefined);
        }
        break;
      }
      case "Cons": {
        const $f2152 = xs._0;
        const $f2153 = xs._1;
        {
          const t = $f2153;
          {
            const h = $f2152;
            {
              let $t2150;
              $t2150 = f._0(f, h);
              {
                const $trmc37 = { $: "Cons", _0: $t2150, _1: null };
                ($dst._1 = $trmc37, undefined);
                {
                  $tco_a0 = t;
                  $tco_a1 = f;
                  $tco_a2 = $trmc37;
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
          const $trmc35 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc35, undefined);
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
      const $f10788 = v._0;
      const $f10789 = v._1;
      const $f10790 = v._2;
      const $f10791 = v._3;
      {
        const tail = $f10791;
        {
          const root = $f10790;
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
        const $f10393 = lst._0;
        const $f10394 = lst._1;
        {
          const t = $f10394;
          {
            const h = $f10393;
            {
              const $t10391 = (n === 0);
              if ($t10391 === true) {
                return h;
              } else {
                {
                  const $t10392 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                  {
                    $tco_a0 = t;
                    $tco_a1 = $t10392;
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
        const $f10504 = n._0;
        {
          const values = $f10504;
          {
            let $t10500;
            {
              const $t10498 = ((idx | 0) === idx && (31 | 0) === 31 ? (idx & 31) : march_int_and(idx, 31));
              {
                let $t10499;
                {
                  const rev_onto_i7939 = { $: "$Clo_rev_onto$0_Array_lst_set_List_Int_Int_Int", _0: rev_onto$apply$0_Array_lst_set_List_Int_Int_Int };
                  {
                    const go_i7940 = { $: "$Clo_go$1_Array_lst_set_List_Int_Int_Int", _0: go$apply$1_Array_lst_set_List_Int_Int_Int, _1: rev_onto_i7939, _2: val };
                    {
                      const $t10422_i7941 = { $: "Nil" };
                      $t10499 = go$apply$1_Array_lst_set_List_Int_Int_Int(go_i7940, values, $t10498, $t10422_i7941);
                    }
                  }
                }
                $t10500 = { $: "TrieLeaf", _0: $t10499 };
              }
            }
            {
              const $rc_3102 = Array$trie_update_up$TrieNode_Int$List_T_List_TrieNode_Int_Int($t10500, path);
              return $rc_3102;
            }
          }
        }
        break;
      }
      case "TrieBranch": {
        const $f10505 = n._0;
        {
          const children = $f10505;
          {
            let slot;
            {
              const $t10483_i7944 = ((idx | 0) === idx && s >= 0 && s < 32 ? (idx >> s) : march_int_shr(idx, s));
              slot = (($t10483_i7944 | 0) === $t10483_i7944 && (31 | 0) === 31 ? ($t10483_i7944 & 31) : march_int_and($t10483_i7944, 31));
            }
            {
              let child;
              child = Array$lst_nth$List_TrieNode_Int$Int(children, slot);
              {
                const $t10501 = ((s - 5) < 4611686018427387904 && (s - 5) >= -4611686018427387904 ? (s - 5) : march_int_ovf((s - 5), 1));
                {
                  const $t10502 = { _0: children, _1: slot };
                  {
                    const $t10503 = { $: "Cons", _0: $t10502, _1: path };
                    {
                      $tco_a0 = child;
                      $tco_a1 = $t10501;
                      $tco_a2 = $t10503;
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
        const $f2174 = sub._0;
        const $f2175 = sub._1;
        {
          const rest = $f2175;
          {
            const x = $f2174;
            {
              const $trmc40 = { $: "Cons", _0: x, _1: null };
              ($dst._1 = $trmc40, undefined);
              {
                $tco_a0 = rest;
                $tco_a1 = lst;
                $tco_a2 = f;
                $tco_a3 = $trmc40;
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
              const $trmc42 = { $: "Nil" };
              return ($dst._1 = $trmc42, undefined);
            }
            break;
          }
          case "Cons": {
            const $f2168 = lst._0;
            const $f2169 = lst._1;
            {
              const t = $f2169;
              {
                const h = $f2168;
                {
                  let $t2167;
                  $t2167 = f._0(f, h);
                  {
                    $tco_a0 = $t2167;
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
              const $trmc41 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
              return ($dst._1 = $trmc41, undefined);
            }
          }
        }
        break;
      }
      default: {
        {
          const $trmc39 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc39, undefined);
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
      const $f10594 = node._0;
      {
        const values = $f10594;
        {
          const go = { $: "$Clo_go$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int", _0: go$apply$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int, _1: f };
          return go$apply$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int(go, acc, values);
        }
      }
      break;
    }
    case "TrieBranch": {
      const $f10595 = node._0;
      {
        const children = $f10595;
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
        const $f10492 = stk._0;
        const $f10493 = stk._1;
        {
          const rest = $f10493;
          {
            const frame = $f10492;
            {
              const children = frame._0;
              {
                const slot = frame._1;
                {
                  let $t10490;
                  {
                    let $t10489;
                    {
                      const rev_onto_i8013 = { $: "$Clo_rev_onto$0_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int", _0: rev_onto$apply$0_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int };
                      {
                        const go_i8014 = { $: "$Clo_go$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int", _0: go$apply$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int, _1: nd, _2: rev_onto_i8013 };
                        {
                          const $t10482_i8015 = { $: "Nil" };
                          $t10489 = go$apply$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int(go_i8014, children, slot, $t10482_i8015);
                        }
                      }
                    }
                    $t10490 = { $: "TrieBranch", _0: $t10489 };
                  }
                  {
                    $tco_a0 = $t10490;
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

function $jp1_Authority_parse$apply$0_Authority_parse($clo) {
  {
    const toks = $clo._1;
    {
      const $t1426 = { $: "Nil" };
      return Authority$parse_entries(toks, $t1426);
    }
  }
}
const $jp1_Authority_parse$apply$0_Authority_parse$clo = { _0: ($_, $clo) => $jp1_Authority_parse$apply$0_Authority_parse($clo) };

function $jp2_Authority_parse$apply$1_Authority_parse($clo) {
  {
    const $jp_clo1432 = $clo._1;
    return $jp_clo1432._0($jp_clo1432);
  }
}
const $jp2_Authority_parse$apply$1_Authority_parse$clo = { _0: ($_, $clo) => $jp2_Authority_parse$apply$1_Authority_parse($clo) };

function $jp3_Authority_parse$apply$2_Authority_parse($clo) {
  {
    const $jp_clo1434 = $clo._1;
    return $jp_clo1434._0($jp_clo1434);
  }
}
const $jp3_Authority_parse$apply$2_Authority_parse$clo = { _0: ($_, $clo) => $jp3_Authority_parse$apply$2_Authority_parse($clo) };

function $jp7_Authority_parse_option$apply$0_Authority_parse_option($clo) {
  {
    const $f1677 = $clo._1;
    {
      const name = $clo._2;
      {
        let more;
        more = $f1677;
        {
          const $t1660 = (name === "methods");
          if ($t1660 === true) {
            {
              let $t1662;
              {
                const $t1661 = { $: "Nil" };
                $t1662 = Authority$method_words(more, $t1661);
              }
              switch ($t1662.$) {
                case "Err": {
                  const $f1666 = $t1662._0;
                  {
                    const e = $f1666;
                    return { $: "Err", _0: e };
                  }
                  break;
                }
                case "Ok": {
                  const $f1667 = $t1662._0;
                  const $f1668 = $f1667._0;
                  const $f1669 = $f1667._1;
                  {
                    const rest = $f1669;
                    {
                      const ms = $f1668;
                      {
                        let $t1664;
                        {
                          let $t1663;
                          {
                            const $rc_3122 = march_string_join(ms, ",");
                            $t1663 = $rc_3122;
                          }
                          {
                            const $rc_3121 = ("methods=" + $t1663);
                            $t1664 = $rc_3121;
                          }
                        }
                        {
                          const $t1665 = { _0: $t1664, _1: rest };
                          return { $: "Ok", _0: $t1665 };
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
          } else {
            {
              const $t1674 = march_string_concat3("`", name, "(...)` takes one quoted string");
              return { $: "Err", _0: $t1674 };
            }
          }
        }
      }
    }
  }
}
const $jp7_Authority_parse_option$apply$0_Authority_parse_option$clo = { _0: ($_, $clo) => $jp7_Authority_parse_option$apply$0_Authority_parse_option($clo) };

function $jp7_Authority_method_words$apply$0_Authority_method_words($clo) {
  {
    const $f1707 = $clo._1;
    {
      const $f1708 = $clo._2;
      {
        const acc = $clo._3;
        {
          const $jp_clo1716 = { $: "$Clo_$jp3_Authority_method_words$1_Authority_method_words", _0: $jp3_Authority_method_words$apply$1_Authority_method_words };
          switch ($f1708.$) {
            case "Cons": {
              const $f1717 = $f1708._0;
              const $f1718 = $f1708._1;
              if ($f1717 === ")") {
                {
                  const rest = $f1718;
                  {
                    let m;
                    m = $f1707;
                    {
                      let $t1702;
                      {
                        const $t1590_i8034 = (m !== "");
                        if ($t1590_i8034 === true) {
                          $t1702 = Authority$all_chars(m, "abcdefghijklmnopqrstuvwxyz_", 0);
                        } else {
                          $t1702 = false;
                        }
                      }
                      if ($t1702 === true) {
                        {
                          let $t1703;
                          $t1703 = { $: "Cons", _0: m, _1: acc };
                          {
                            const $t1704 = { $: "Nil" };
                            {
                              const $t1705 = Authority$rev($t1703, $t1704);
                              {
                                let $t1706;
                                $t1706 = { _0: $t1705, _1: rest };
                                return { $: "Ok", _0: $t1706 };
                              }
                            }
                          }
                        }
                      } else {
                        return { $: "Err", _0: "`methods(...)` takes HTTP method names" };
                      }
                    }
                  }
                }
              } else {
                return { $: "Err", _0: "`methods(...)` is not closed" };
              }
              break;
            }
            default: {
              return { $: "Err", _0: "`methods(...)` is not closed" };
            }
          }
        }
      }
    }
  }
}
const $jp7_Authority_method_words$apply$0_Authority_method_words$clo = { _0: ($_, $clo) => $jp7_Authority_method_words$apply$0_Authority_method_words($clo) };

function $jp3_Authority_method_words$apply$1_Authority_method_words($clo) {
  return { $: "Err", _0: "`methods(...)` is not closed" };
}
const $jp3_Authority_method_words$apply$1_Authority_method_words$clo = { _0: ($_, $clo) => $jp3_Authority_method_words$apply$1_Authority_method_words($clo) };

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
          const $t2069 = (i < start);
          if ($t2069 === true) {
            return acc;
          } else {
            {
              const $t2070 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
              {
                const $t2071 = { $: "Cons", _0: i, _1: acc };
                {
                  $tco_a0 = go;
                  $tco_a1 = $t2070;
                  $tco_a2 = $t2071;
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
        const $f49347 = c._0;
        const $f49348 = c._1;
        {
          const dy = $f49348;
          {
            const dx = $f49347;
            {
              const x = ((origin_x + dx) < 4611686018427387904 && (origin_x + dx) >= -4611686018427387904 ? (origin_x + dx) : march_int_ovf((origin_x + dx), 0));
              {
                const y = ((origin_y + dy) < 4611686018427387904 && (origin_y + dy) >= -4611686018427387904 ? (origin_y + dy) : march_int_ovf((origin_y + dy), 0));
                {
                  let $t49344;
                  {
                    let $t49341_i8934;
                    {
                      let $t49339_i8932;
                      {
                        const $t49337_i8930 = (x >= 0);
                        if ($t49337_i8930 === true) {
                          $t49339_i8932 = (x < 10);
                        } else {
                          $t49339_i8932 = false;
                        }
                      }
                      {
                        const $t49340_i8933 = (y >= 0);
                        $t49341_i8934 = ($t49339_i8932 && $t49340_i8933);
                      }
                    }
                    if ($t49341_i8934 === true) {
                      $t49344 = (y < 20);
                    } else {
                      $t49344 = false;
                    }
                  }
                  if ($t49344 === false) {
                    return true;
                  } else if ($t49344 === true) {
                    {
                      let $t49346;
                      {
                        let $t49345;
                        {
                          const $t49325_i8927 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
                          $t49345 = (($t49325_i8927 + x) < 4611686018427387904 && ($t49325_i8927 + x) >= -4611686018427387904 ? ($t49325_i8927 + x) : march_int_ovf(($t49325_i8927 + x), 0));
                        }
                        $t49346 = Array$get$PVec_Int$Int(board, $t49345);
                      }
                      return ($t49346 !== 0);
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
        const $f49357 = c._0;
        const $f49358 = c._1;
        {
          const dy = $f49358;
          {
            const dx = $f49357;
            {
              const x = ((origin_x + dx) < 4611686018427387904 && (origin_x + dx) >= -4611686018427387904 ? (origin_x + dx) : march_int_ovf((origin_x + dx), 0));
              {
                const y = ((origin_y + dy) < 4611686018427387904 && (origin_y + dy) >= -4611686018427387904 ? (origin_y + dy) : march_int_ovf((origin_y + dy), 0));
                {
                  let $t49355;
                  {
                    let $t49341_i8946;
                    {
                      let $t49339_i8944;
                      {
                        const $t49337_i8942 = (x >= 0);
                        if ($t49337_i8942 === true) {
                          $t49339_i8944 = (x < 10);
                        } else {
                          $t49339_i8944 = false;
                        }
                      }
                      {
                        const $t49340_i8945 = (y >= 0);
                        $t49341_i8946 = ($t49339_i8944 && $t49340_i8945);
                      }
                    }
                    if ($t49341_i8946 === true) {
                      $t49355 = (y < 20);
                    } else {
                      $t49355 = false;
                    }
                  }
                  if ($t49355 === true) {
                    {
                      let $t49356;
                      {
                        const $t49325_i8939 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
                        $t49356 = (($t49325_i8939 + x) < 4611686018427387904 && ($t49325_i8939 + x) >= -4611686018427387904 ? ($t49325_i8939 + x) : march_int_ovf(($t49325_i8939 + x), 0));
                      }
                      return Array$set$PVec_Int$Int$Int(b, $t49356, color_idx);
                    }
                  } else if ($t49355 === false) {
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
        let $t49368;
        {
          let $t49367;
          {
            const $t49325_i8951 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
            $t49367 = (($t49325_i8951 + x) < 4611686018427387904 && ($t49325_i8951 + x) >= -4611686018427387904 ? ($t49325_i8951 + x) : march_int_ovf(($t49325_i8951 + x), 0));
          }
          $t49368 = Array$get$PVec_Int$Int(board, $t49367);
        }
        return ($t49368 !== 0);
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
        let $t49373;
        {
          const $t49325_i8955 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
          $t49373 = (($t49325_i8955 + x) < 4611686018427387904 && ($t49325_i8955 + x) >= -4611686018427387904 ? ($t49325_i8955 + x) : march_int_ovf(($t49325_i8955 + x), 0));
        }
        return Array$get$PVec_Int$Int(board, $t49373);
      }
    }
  }
}
const $lam0_TetrisLogic_row_cells$apply$0_TetrisLogic_row_cells$clo = { _0: ($_, $clo, x) => $lam0_TetrisLogic_row_cells$apply$0_TetrisLogic_row_cells($clo, x) };

function $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines($clo, y) {
  {
    const board = $clo._1;
    {
      let $t49377;
      {
        let $t49365_i14568;
        {
          const go_i5871_i14565 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
          {
            const $t2073_i5873_i14567 = { $: "Nil" };
            $t49365_i14568 = go$apply$0_List_range(go_i5871_i14565, 9, $t2073_i5873_i14567);
          }
        }
        {
          const $t49369_i14569 = { $: "$Clo_$lam0_TetrisLogic_row_full$0_TetrisLogic_row_full", _0: $lam0_TetrisLogic_row_full$apply$0_TetrisLogic_row_full, _1: board, _2: y };
          {
            const $rc_2804_i14570 = List$all$List_Int$Fn_Int_Bool($t49365_i14568, $t49369_i14569);
            $t49377 = $rc_2804_i14570;
          }
        }
      }
      return (!$t49377);
    }
  }
}
const $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines$clo = { _0: ($_, $clo, y) => $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines($clo, y) };

function $lam1_TetrisLogic_clear_lines$apply$1_TetrisLogic_clear_lines($clo, y) {
  {
    const board = $clo._1;
    {
      let $t49371_i8959;
      {
        const go_i14737 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
        {
          const $t2073_i14739 = { $: "Nil" };
          $t49371_i8959 = go$apply$0_List_range(go_i14737, 9, $t2073_i14739);
        }
      }
      {
        const $t49374_i8960 = { $: "$Clo_$lam0_TetrisLogic_row_cells$0_TetrisLogic_row_cells", _0: $lam0_TetrisLogic_row_cells$apply$0_TetrisLogic_row_cells, _1: board, _2: y };
        {
          const xs_i14773 = $t49371_i8959;
          {
            const f_i14774 = $t49374_i8960;
            switch (xs_i14773.$) {
              case "Nil": {
                return { $: "Nil" };
                break;
              }
              case "Cons": {
                const $f2152_i14775 = xs_i14773._0;
                const $f2153_i14776 = xs_i14773._1;
                {
                  const t_i14777 = $f2153_i14776;
                  {
                    const h_i14778 = $f2152_i14775;
                    {
                      let $t2150_i14779;
                      $t2150_i14779 = f_i14774._0(f_i14774, h_i14778);
                      {
                        const $trmc38_i14780 = { $: "Cons", _0: $t2150_i14779, _1: null };
                        List$map$dps$List_Int$Fn_Int_Int$List_Int(t_i14777, f_i14774, $trmc38_i14780);
                        return $trmc38_i14780;
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
    let $t49391;
    {
      const $rc_3694 = march_string_to_int(x);
      $t49391 = $rc_3694;
    }
    {
      const $rc_3693 = Option$unwrap_or$Option_Int$Int($t49391, 0);
      return $rc_3693;
    }
  }
}
const $lam0_string_to_int_list$apply$0_string_to_int_list$clo = { _0: ($_, $clo, x) => $lam0_string_to_int_list$apply$0_string_to_int_list($clo, x) };

function $lam0_render_board$apply$0_render_board($clo, y) {
  {
    const board = $clo._1;
    {
      let $t49448;
      {
        const go_i8966 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
        {
          const $t2073_i8968 = { $: "Nil" };
          $t49448 = go$apply$0_List_range(go_i8966, 9, $t2073_i8968);
        }
      }
      {
        let $t49456;
        $t49456 = { $: "$Clo_$lam0__lam0_render_board$1_render_board", _0: $lam0__lam0_render_board$apply$1_render_board, _1: board, _2: y };
        {
          const f_i8962 = $t49456;
          {
            const go_i8963 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i8962 };
            return go$apply$0_List_each_List_Int_Fn_Int_T_(go_i8963, $t49448);
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
          const $t49325_i8973 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
          idx = (($t49325_i8973 + x) < 4611686018427387904 && ($t49325_i8973 + x) >= -4611686018427387904 ? ($t49325_i8973 + x) : march_int_ovf(($t49325_i8973 + x), 0));
        }
        {
          let v;
          v = Array$get$PVec_Int$Int(board, idx);
          {
            let id;
            {
              const $t49450 = String(x);
              {
                const $t49451 = String(y);
                {
                  const $rc_3695 = march_string_concat_n("cell-", $t49450, "-", $t49451);
                  id = $rc_3695;
                }
              }
            }
            {
              const $t49452 = Js$Dom$find(id);
              switch ($t49452.$) {
                case "None": {
                  return {  };
                  break;
                }
                case "Some": {
                  const $f49455 = $t49452._0;
                  {
                    const cell = $f49455;
                    {
                      const $t49453 = (v === 0);
                      if ($t49453 === true) {
                        return Js$Dom$set_style(cell, "background", "");
                      } else if ($t49453 === false) {
                        {
                          let $t49454;
                          if (v === 1) {
                            $t49454 = "#00CED1";
                          } else if (v === 2) {
                            $t49454 = "#FFD700";
                          } else if (v === 3) {
                            $t49454 = "#9B59B6";
                          } else if (v === 4) {
                            $t49454 = "#2ECC71";
                          } else if (v === 5) {
                            $t49454 = "#E74C3C";
                          } else if (v === 6) {
                            $t49454 = "#3498DB";
                          } else if (v === 7) {
                            $t49454 = "#F39C12";
                          } else {
                            $t49454 = "";
                          }
                          return Js$Dom$set_style(cell, "background", $t49454);
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
        const $f49471 = c._0;
        const $f49472 = c._1;
        {
          const dy = $f49472;
          {
            const dx = $f49471;
            {
              const x = ((ox + dx) < 4611686018427387904 && (ox + dx) >= -4611686018427387904 ? (ox + dx) : march_int_ovf((ox + dx), 0));
              {
                const y = ((oy + dy) < 4611686018427387904 && (oy + dy) >= -4611686018427387904 ? (oy + dy) : march_int_ovf((oy + dy), 0));
                {
                  let $t49465;
                  {
                    let $t49463;
                    {
                      let $t49461;
                      {
                        const $t49459 = (x >= 0);
                        if ($t49459 === true) {
                          $t49461 = (x < 10);
                        } else {
                          $t49461 = false;
                        }
                      }
                      {
                        const $t49462 = (y >= 0);
                        $t49463 = ($t49461 && $t49462);
                      }
                    }
                    if ($t49463 === true) {
                      $t49465 = (y < 20);
                    } else {
                      $t49465 = false;
                    }
                  }
                  if ($t49465 === false) {
                    return {  };
                  } else if ($t49465 === true) {
                    {
                      let id;
                      {
                        const $t49466 = String(x);
                        {
                          const $t49467 = String(y);
                          {
                            const $rc_3696 = march_string_concat_n("cell-", $t49466, "-", $t49467);
                            id = $rc_3696;
                          }
                        }
                      }
                      {
                        const $t49468 = Js$Dom$find(id);
                        switch ($t49468.$) {
                          case "None": {
                            return {  };
                            break;
                          }
                          case "Some": {
                            const $f49470 = $t49468._0;
                            {
                              const cell = $f49470;
                              {
                                let $t49469;
                                switch (piece.$) {
                                  case "I": {
                                    $t49469 = "#00CED1";
                                    break;
                                  }
                                  case "O": {
                                    $t49469 = "#FFD700";
                                    break;
                                  }
                                  case "T": {
                                    $t49469 = "#9B59B6";
                                    break;
                                  }
                                  case "S": {
                                    $t49469 = "#2ECC71";
                                    break;
                                  }
                                  case "Z": {
                                    $t49469 = "#E74C3C";
                                    break;
                                  }
                                  case "J": {
                                    $t49469 = "#3498DB";
                                    break;
                                  }
                                  case "L": {
                                    $t49469 = "#F39C12";
                                    break;
                                  }
                                  default: {
                                    throw march_panic_error("panic: ", "non-exhaustive pattern match");
                                    break;
                                  }
                                }
                                return Js$Dom$set_style(cell, "background", $t49469);
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
    const $t49600 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t49600, rot);
      {
        let $t49602;
        {
          const $t49601 = ((y + 1) < 4611686018427387904 && (y + 1) >= -4611686018427387904 ? (y + 1) : march_int_ovf((y + 1), 0));
          {
            const $t49353_i8978 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: x, _3: $t49601 };
            $t49602 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t49353_i8978);
          }
        }
        if ($t49602 === true) {
          {
            const $rc_3697 = lock_and_advance(board, piece, rot, x, y, next, score, lines, rng);
            return $rc_3697;
          }
        } else if ($t49602 === false) {
          {
            const $t49603 = ((y + 1) < 4611686018427387904 && (y + 1) >= -4611686018427387904 ? (y + 1) : march_int_ovf((y + 1), 0));
            return { _0: board, _1: piece, _2: rot, _3: x, _4: $t49603, _5: next, _6: score, _7: lines, _8: rng, _9: false };
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
      const $t49598_i14572 = is_paused();
      if ($t49598_i14572 === true) {
        $eff = {  };
      } else if ($t49598_i14572 === false) {
        {
          const $t49604_i14573 = { $: "$Clo_$lam0_tick$0_tick", _0: $lam0_tick$apply$0_tick };
          $eff = with_state($t49604_i14573);
        }
      } else {
        throw march_panic_error("panic: ", "non-exhaustive pattern match");
      }
    }
  }
  {
    let level_i8981;
    {
      let $t49606_i8980;
      {
        const $t49605_i8979 = state_el();
        $t49606_i8980 = get_int_attr($t49605_i8979, "data-lines", 0);
      }
      level_i8981 = TetrisLogic$level_for_lines($t49606_i8980);
    }
    {
      let $t49607_i8982;
      {
        let $t49323_i14742;
        {
          const $t49322_i14741 = ((level_i8981 * 40) < 4611686018427387904 && (level_i8981 * 40) >= -4611686018427387904 ? (level_i8981 * 40) : march_int_ovf((level_i8981 * 40), 2));
          $t49323_i14742 = ((500 - $t49322_i14741) < 4611686018427387904 && (500 - $t49322_i14741) >= -4611686018427387904 ? (500 - $t49322_i14741) : march_int_ovf((500 - $t49322_i14741), 1));
        }
        {
          const $t3631_i5864_i14743 = ($t49323_i14742 > 100);
          if ($t3631_i5864_i14743 === true) {
            $t49607_i8982 = $t49323_i14742;
          } else {
            $t49607_i8982 = 100;
          }
        }
      }
      {
        const $t49609_i8983 = { $: "$Clo_$lam0_schedule_tick$0_schedule_tick", _0: $lam0_schedule_tick$apply$0_schedule_tick };
        return Js$Dom$set_timeout($t49607_i8982, $t49609_i8983);
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
        const $t49611 = TetrisLogic$piece_cells(piece);
        {
          const cells = rotate_n($t49611, rot);
          {
            let $t49614;
            {
              const $t49612 = ((x + dx) < 4611686018427387904 && (x + dx) >= -4611686018427387904 ? (x + dx) : march_int_ovf((x + dx), 0));
              {
                const $t49613 = ((y + dy) < 4611686018427387904 && (y + dy) >= -4611686018427387904 ? (y + dy) : march_int_ovf((y + dy), 0));
                {
                  const $t49353_i8988 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: $t49612, _3: $t49613 };
                  $t49614 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t49353_i8988);
                }
              }
            }
            if ($t49614 === true) {
              return { _0: board, _1: piece, _2: rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: rng, _9: false };
            } else if ($t49614 === false) {
              {
                const $t49615 = ((x + dx) < 4611686018427387904 && (x + dx) >= -4611686018427387904 ? (x + dx) : march_int_ovf((x + dx), 0));
                {
                  const $t49616 = ((y + dy) < 4611686018427387904 && (y + dy) >= -4611686018427387904 ? (y + dy) : march_int_ovf((y + dy), 0));
                  return { _0: board, _1: piece, _2: rot, _3: $t49615, _4: $t49616, _5: next, _6: score, _7: lines, _8: rng, _9: false };
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
      const $t49619 = ((rot + 1) < 4611686018427387904 && (rot + 1) >= -4611686018427387904 ? (rot + 1) : march_int_ovf((rot + 1), 0));
      new_rot = (4 === 0 ? march_mod_zero() : $t49619 % 4);
    }
    {
      const $t49620 = TetrisLogic$piece_cells(piece);
      {
        const cells = rotate_n($t49620, new_rot);
        {
          let $t49621;
          {
            const $t49353_i8993 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: x, _3: y };
            $t49621 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t49353_i8993);
          }
          if ($t49621 === true) {
            return { _0: board, _1: piece, _2: rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: rng, _9: false };
          } else if ($t49621 === false) {
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
    const $t49627 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t49627, rot);
      {
        let final_y;
        final_y = fall_from(board, cells, x, y);
        {
          const $rc_3698 = lock_and_advance(board, piece, rot, x, final_y, next, score, lines, rng);
          return $rc_3698;
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
          let $t49702;
          {
            const go_i8999 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
            {
              const $t2073_i9001 = { $: "Nil" };
              $t49702 = go$apply$0_List_range(go_i8999, 9, $t2073_i9001);
            }
          }
          {
            let $t49707;
            $t49707 = { $: "$Clo_$lam0__lam0_build_board_dom$1_build_board_dom", _0: $lam0__lam0_build_board_dom$apply$1_build_board_dom, _1: row, _2: y };
            {
              const f_i8995 = $t49707;
              {
                const go_i8996 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i8995 };
                $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i8996, $t49702);
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
            let $t49706;
            {
              const $t49704 = String(x);
              {
                const $t49705 = String(y);
                {
                  const $rc_3699 = march_string_concat_n("cell-", $t49704, "-", $t49705);
                  $t49706 = $rc_3699;
                }
              }
            }
            $eff = Js$Dom$set_attr(cell, "id", $t49706);
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
          const $t2065 = (i <= 0);
          if ($t2065 === true) {
            return acc;
          } else {
            {
              const $t2066 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
              {
                const $t2067 = { $: "Cons", _0: x, _1: acc };
                {
                  $tco_a0 = go;
                  $tco_a1 = $t2066;
                  $tco_a2 = $t2067;
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
        const $t10917 = { $: "$Clo_$lam0_Array_from_list_up$1_Array_from_list_List_Int", _0: $lam0_Array_from_list_up$apply$1_Array_from_list_List_Int };
        {
          let parents;
          {
            const wrap_i9137 = $t10917;
            {
              const chunk_i9138 = { $: "$Clo_chunk$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int", _0: chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int, _1: wrap_i9137 };
              {
                const $t10843_i9139 = { $: "Nil" };
                {
                  const $t10844_i9140 = { $: "Nil" };
                  parents = chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int(chunk_i9138, nodes, 0, $t10843_i9139, $t10844_i9140);
                }
              }
            }
          }
          {
            let $t10919;
            {
              let $t10918;
              {
                const go_i9135 = { $: "$Clo_go$0_Array_lst_len_List_TrieNode_Int", _0: go$apply$0_Array_lst_len_List_TrieNode_Int };
                $t10918 = go$apply$0_Array_lst_len_List_TrieNode_Int(go_i9135, parents, 0);
              }
              $t10919 = ($t10918 === 1);
            }
            if ($t10919 === true) {
              switch (parents.$) {
                case "Cons": {
                  const $f10923 = parents._0;
                  const $f10924 = parents._1;
                  {
                    const root = $f10923;
                    {
                      const $t10920 = ((shift + 5) < 4611686018427387904 && (shift + 5) >= -4611686018427387904 ? (shift + 5) : march_int_ovf((shift + 5), 0));
                      return { _0: root, _1: $t10920 };
                    }
                  }
                  break;
                }
                case "Nil": {
                  {
                    const $t10921 = { $: "TrieEmpty" };
                    {
                      const $t10922 = ((shift + 5) < 4611686018427387904 && (shift + 5) >= -4611686018427387904 ? (shift + 5) : march_int_ovf((shift + 5), 0));
                      return { _0: $t10921, _1: $t10922 };
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
                const $t10929 = ((shift + 5) < 4611686018427387904 && (shift + 5) >= -4611686018427387904 ? (shift + 5) : march_int_ovf((shift + 5), 0));
                {
                  $tco_a0 = $clo;
                  $tco_a1 = parents;
                  $tco_a2 = $t10929;
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
            const $f2159 = lst._0;
            const $f2160 = lst._1;
            {
              const t = $f2160;
              {
                const h = $f2159;
                {
                  let $p2158;
                  $p2158 = f._0(f, h);
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
            const $f2159 = lst._0;
            const $f2160 = lst._1;
            {
              const t = $f2160;
              {
                const h = $f2159;
                {
                  let $p2158;
                  $p2158 = f._0(f, h);
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
          const $f10424 = xs._0;
          const $f10425 = xs._1;
          {
            const t = $f10425;
            {
              const $t10423 = ((acc + 1) < 4611686018427387904 && (acc + 1) >= -4611686018427387904 ? (acc + 1) : march_int_ovf((acc + 1), 0));
              {
                $tco_a0 = $clo;
                $tco_a1 = t;
                $tco_a2 = $t10423;
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
                  const go_i9220 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                  {
                    const $t10390_i9221 = { $: "Nil" };
                    return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9220, out, $t10390_i9221);
                  }
                }
                break;
              }
              default: {
                {
                  let $t10825;
                  {
                    let $t10824;
                    {
                      const go_i9217 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                      {
                        const $t10390_i9218 = { $: "Nil" };
                        $t10824 = go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9217, cur, $t10390_i9218);
                      }
                    }
                    $t10825 = wrap._0(wrap, $t10824);
                  }
                  {
                    const $t10826 = { $: "Cons", _0: $t10825, _1: out };
                    {
                      const go_i9214 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                      {
                        const $t10390_i9215 = { $: "Nil" };
                        return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9214, $t10826, $t10390_i9215);
                      }
                    }
                  }
                }
              }
            }
            break;
          }
          case "Cons": {
            const $f10837 = ys._0;
            const $f10838 = ys._1;
            {
              const t = $f10838;
              {
                const h = $f10837;
                {
                  const $t10829 = (i === 31);
                  if ($t10829 === true) {
                    {
                      const $t10830 = { $: "Nil" };
                      {
                        let $t10833;
                        {
                          const $t10831 = { $: "Cons", _0: h, _1: cur };
                          {
                            let $t10832;
                            {
                              const go_i9223 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                              {
                                const $t10390_i9224 = { $: "Nil" };
                                $t10832 = go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9223, $t10831, $t10390_i9224);
                              }
                            }
                            $t10833 = wrap._0(wrap, $t10832);
                          }
                        }
                        {
                          const $t10834 = { $: "Cons", _0: $t10833, _1: out };
                          {
                            $tco_a0 = chunk;
                            $tco_a1 = t;
                            $tco_a2 = 0;
                            $tco_a3 = $t10830;
                            $tco_a4 = $t10834;
                            continue __tco;
                          }
                        }
                      }
                    }
                  } else {
                    {
                      const $t10835 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                      {
                        const $t10836 = { $: "Cons", _0: h, _1: cur };
                        {
                          $tco_a0 = chunk;
                          $tco_a1 = t;
                          $tco_a2 = $t10835;
                          $tco_a3 = $t10836;
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
                  const go_i9232 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                  {
                    const $t10390_i9233 = { $: "Nil" };
                    return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9232, out, $t10390_i9233);
                  }
                }
                break;
              }
              default: {
                {
                  let $t10825;
                  {
                    let $t10824;
                    {
                      const go_i9229 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                      {
                        const $t10390_i9230 = { $: "Nil" };
                        $t10824 = go$apply$0_Array_lst_rev_List_Int(go_i9229, cur, $t10390_i9230);
                      }
                    }
                    $t10825 = wrap._0(wrap, $t10824);
                  }
                  {
                    const $t10826 = { $: "Cons", _0: $t10825, _1: out };
                    {
                      const go_i9226 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                      {
                        const $t10390_i9227 = { $: "Nil" };
                        return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9226, $t10826, $t10390_i9227);
                      }
                    }
                  }
                }
              }
            }
            break;
          }
          case "Cons": {
            const $f10837 = ys._0;
            const $f10838 = ys._1;
            {
              const t = $f10838;
              {
                const h = $f10837;
                {
                  const $t10829 = (i === 31);
                  if ($t10829 === true) {
                    {
                      const $t10830 = { $: "Nil" };
                      {
                        let $t10833;
                        {
                          const $t10831 = { $: "Cons", _0: h, _1: cur };
                          {
                            let $t10832;
                            {
                              const go_i9235 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                              {
                                const $t10390_i9236 = { $: "Nil" };
                                $t10832 = go$apply$0_Array_lst_rev_List_Int(go_i9235, $t10831, $t10390_i9236);
                              }
                            }
                            $t10833 = wrap._0(wrap, $t10832);
                          }
                        }
                        {
                          const $t10834 = { $: "Cons", _0: $t10833, _1: out };
                          {
                            $tco_a0 = chunk;
                            $tco_a1 = t;
                            $tco_a2 = 0;
                            $tco_a3 = $t10830;
                            $tco_a4 = $t10834;
                            continue __tco;
                          }
                        }
                      }
                    }
                  } else {
                    {
                      const $t10835 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                      {
                        const $t10836 = { $: "Cons", _0: h, _1: cur };
                        {
                          $tco_a0 = chunk;
                          $tco_a1 = t;
                          $tco_a2 = $t10835;
                          $tco_a3 = $t10836;
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
        const $t10811 = (i === 0);
        if ($t10811 === true) {
          {
            let $t10812;
            {
              const go_i9241 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
              {
                const $t10390_i9242 = { $: "Nil" };
                $t10812 = go$apply$0_Array_lst_rev_List_Int(go_i9241, acc, $t10390_i9242);
              }
            }
            return { _0: $t10812, _1: ys };
          }
        } else {
          switch (ys.$) {
            case "Nil": {
              {
                let $t10813;
                {
                  const go_i9238 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                  {
                    const $t10390_i9239 = { $: "Nil" };
                    $t10813 = go$apply$0_Array_lst_rev_List_Int(go_i9238, acc, $t10390_i9239);
                  }
                }
                {
                  const $t10814 = { $: "Nil" };
                  return { _0: $t10813, _1: $t10814 };
                }
              }
              break;
            }
            case "Cons": {
              const $f10817 = ys._0;
              const $f10818 = ys._1;
              {
                const t = $f10818;
                {
                  const h = $f10817;
                  {
                    const $t10815 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
                    {
                      const $t10816 = { $: "Cons", _0: h, _1: acc };
                      {
                        $tco_a0 = $clo;
                        $tco_a1 = t;
                        $tco_a2 = $t10815;
                        $tco_a3 = $t10816;
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
          const $f10424 = xs._0;
          const $f10425 = xs._1;
          {
            const t = $f10425;
            {
              const $t10423 = ((acc + 1) < 4611686018427387904 && (acc + 1) >= -4611686018427387904 ? (acc + 1) : march_int_ovf((acc + 1), 0));
              {
                $tco_a0 = $clo;
                $tco_a1 = t;
                $tco_a2 = $t10423;
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
          const $f10400 = rev_xs._0;
          const $f10401 = rev_xs._1;
          {
            const rest = $f10401;
            {
              const a = $f10400;
              {
                const $t10399 = { $: "Cons", _0: a, _1: ys };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = rest;
                  $tco_a2 = $t10399;
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
            const $t10406 = (i === 0);
            if ($t10406 === true) {
              switch (xs.$) {
                case "Nil": {
                  {
                    const go_i9247 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                    {
                      const $t10390_i9248 = { $: "Nil" };
                      return go$apply$0_Array_lst_rev_List_Int(go_i9247, acc, $t10390_i9248);
                    }
                  }
                  break;
                }
                case "Cons": {
                  const $f10408 = xs._0;
                  const $f10409 = xs._1;
                  {
                    const t = $f10409;
                    {
                      const $t10407 = { $: "Cons", _0: v, _1: t };
                      return rev_onto._0(rev_onto, acc, $t10407);
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
                    const go_i9244 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                    {
                      const $t10390_i9245 = { $: "Nil" };
                      return go$apply$0_Array_lst_rev_List_Int(go_i9244, acc, $t10390_i9245);
                    }
                  }
                  break;
                }
                case "Cons": {
                  const $f10416 = xs._0;
                  const $f10417 = xs._1;
                  {
                    const t = $f10417;
                    {
                      const h = $f10416;
                      {
                        const $t10414 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
                        {
                          const $t10415 = { $: "Cons", _0: h, _1: acc };
                          {
                            $tco_a0 = go;
                            $tco_a1 = t;
                            $tco_a2 = $t10414;
                            $tco_a3 = $t10415;
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
          const $f10384 = xs._0;
          const $f10385 = xs._1;
          {
            const t = $f10385;
            {
              const h = $f10384;
              {
                const $t10383 = { $: "Cons", _0: h, _1: acc };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = t;
                  $tco_a2 = $t10383;
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
            const $f10782 = xs._0;
            const $f10783 = xs._1;
            {
              const rest = $f10783;
              {
                const x = $f10782;
                {
                  let $t10781;
                  $t10781 = f._0(f, a, x);
                  {
                    $tco_a0 = go;
                    $tco_a1 = $t10781;
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
          const $f10384 = xs._0;
          const $f10385 = xs._1;
          {
            const t = $f10385;
            {
              const h = $f10384;
              {
                const $t10383 = { $: "Cons", _0: h, _1: acc };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = t;
                  $tco_a2 = $t10383;
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
            const $f10581 = vs._0;
            const $f10582 = vs._1;
            {
              const rest = $f10582;
              {
                const v = $f10581;
                {
                  let $t10580;
                  $t10580 = f._0(f, a, v);
                  {
                    $tco_a0 = go;
                    $tco_a1 = $t10580;
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
            const $f10588 = cs._0;
            const $f10589 = cs._1;
            {
              const rest = $f10589;
              {
                const child = $f10588;
                {
                  let $t10587;
                  $t10587 = Array$trie_fold$List_Int$TrieNode_Int$Fn_List_Int_Int_List_Int(a, child, f);
                  {
                    $tco_a0 = go;
                    $tco_a1 = $t10587;
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
          const $f10466 = rev_xs._0;
          const $f10467 = rev_xs._1;
          {
            const rest = $f10467;
            {
              const a = $f10466;
              {
                const $t10465 = { $: "Cons", _0: a, _1: ys };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = rest;
                  $tco_a2 = $t10465;
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
                const go_i9660 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                {
                  const $t10390_i9661 = { $: "Nil" };
                  return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9660, acc, $t10390_i9661);
                }
              }
              break;
            }
            case "Cons": {
              const $f10476 = xs._0;
              const $f10477 = xs._1;
              {
                const t = $f10477;
                {
                  const h = $f10476;
                  {
                    const $t10472 = (i === 0);
                    if ($t10472 === true) {
                      {
                        let $t10473;
                        $t10473 = { $: "Cons", _0: node, _1: t };
                        return rev_onto._0(rev_onto, acc, $t10473);
                      }
                    } else {
                      {
                        const $t10474 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
                        {
                          const $t10475 = { $: "Cons", _0: h, _1: acc };
                          {
                            $tco_a0 = go;
                            $tco_a1 = t;
                            $tco_a2 = $t10474;
                            $tco_a3 = $t10475;
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
