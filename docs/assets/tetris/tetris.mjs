import { march_cap_check_raw, march_cap_cwd, march_cap_grant_text, march_cap_launch_fail, march_cap_layers, march_cap_set_launch, march_div_zero, march_float_ceil, march_float_floor, march_float_round, march_float_to_int, march_float_to_string, march_float_truncate, march_int_and, march_int_div, march_int_div_euclid, march_int_div_floor, march_int_mod, march_int_mod_euclid, march_int_mod_floor, march_int_not, march_int_or, march_int_ovf, march_int_popcount, march_int_shl, march_int_shr, march_int_wrapping_add, march_int_wrapping_mul, march_int_wrapping_sub, march_int_xor, march_mod_zero, march_panic_error, march_panic_site, march_string_byte_length, march_string_concat3, march_string_concat_n, march_string_contains, march_string_ends_with, march_string_index_of, march_string_join, march_string_last_index_of, march_string_replace_all, march_string_slice, march_string_split, march_string_starts_with, march_string_to_int, march_string_to_lowercase, march_try_finally, march_unix_time, march_unix_time_ms } from "./march_runtime.mjs";

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

function __eq_ScopeError(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ScopeError": {
      if (a._0 !== b._0) return false;
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

function __eq_Authority$CapEntry(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "CapEntry": {
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

function __eq_Scope$Scope(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ScopeText": {
      if (a._0 !== b._0) return false;
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

function Authority$describe(e) {
  switch (e.$) {
    case "CapError": {
      const $f781 = e._0;
      const $f782 = e._1;
      const $f783 = e._2;
      const $f784 = e._3;
      {
        const scope = $f784;
        {
          const limit = $f783;
          {
            const target = $f782;
            {
              const kind = $f781;
              {
                let o_pre;
                {
                  const $t779 = (target === "");
                  if ($t779 === true) {
                    o_pre = kind;
                  } else {
                    {
                      const $rc_66 = march_string_concat_n(kind, "(\"", target, "\")");
                      o_pre = $rc_66;
                    }
                  }
                }
                {
                  let who;
                  {
                    let $rc_65;
                    switch (limit.$) {
                      case "ByLaunch": {
                        $rc_65 = "the launch grant";
                        break;
                      }
                      case "ByFnNeeds": {
                        const $f797_i9646 = limit._0;
                        {
                          const f_i9647 = $f797_i9646;
                          $rc_65 = march_string_concat3("function ", f_i9647, "'s needs");
                        }
                        break;
                      }
                      case "ByModNeeds": {
                        const $f798_i9648 = limit._0;
                        {
                          const m_i9649 = $f798_i9648;
                          $rc_65 = march_string_concat3("module ", m_i9649, "'s needs");
                        }
                        break;
                      }
                      case "ByRestrict": {
                        const $f799_i9650 = limit._0;
                        {
                          const w_i9651 = $f799_i9650;
                          $rc_65 = ("the restrict at " + w_i9651);
                        }
                        break;
                      }
                      case "ByGrant": {
                        const $f800_i9652 = limit._0;
                        {
                          const p_i9653 = $f800_i9652;
                          $rc_65 = ("the grant to package " + p_i9653);
                        }
                        break;
                      }
                      default: {
                        throw march_panic_error("panic: ", "non-exhaustive pattern match");
                        break;
                      }
                    }
                    who = $rc_65;
                  }
                  {
                    let allowed;
                    {
                      const $t780 = (scope === "");
                      if ($t780 === true) {
                        allowed = "nothing";
                      } else {
                        allowed = scope;
                      }
                    }
                    {
                      const $rc_64 = march_string_concat_n(o_pre, " refused by ", who, " (", allowed, ")");
                      return $rc_64;
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
const Authority$describe$clo = { _0: ($_, e) => Authority$describe(e) };

function Authority$check(kind, target) {
  {
    const r = march_cap_check_raw(kind, target);
    {
      const $t805 = (r === 0);
      if ($t805 === true) {
        {
          const $t806 = {  };
          return { $: "Ok", _0: $t806 };
        }
      } else {
        {
          const $t807_i9657 = march_cap_layers();
          {
            const kind_i14772 = kind;
            {
              let cwd_i14780;
              {
                let $t810_i14779;
                {
                  let $t808_i14777;
                  {
                    let $t1102_i59_i14776;
                    {
                      const $t1101_i58_i14775 = (kind === "IO.FileRead");
                      if ($t1101_i58_i14775 === true) {
                        $t1102_i59_i14776 = true;
                      } else {
                        $t1102_i59_i14776 = (kind === "IO.FileWrite");
                      }
                    }
                    if ($t1102_i59_i14776 === true) {
                      $t808_i14777 = true;
                    } else {
                      $t808_i14777 = (kind === "IO.FileSystem");
                    }
                  }
                  if ($t808_i14777 === true) {
                    {
                      const $t809_i14778 = march_string_starts_with(target, "/");
                      $t810_i14779 = (!$t809_i14778);
                    }
                  } else {
                    $t810_i14779 = false;
                  }
                }
                if ($t810_i14779 === true) {
                  cwd_i14780 = march_cap_cwd();
                } else {
                  cwd_i14780 = "/";
                }
              }
              {
                let $t811_i14781;
                {
                  let p_i14840;
                  if (kind === "IO.Console") {
                    p_i14840 = "IO";
                  } else if (kind === "IO.FileSystem") {
                    p_i14840 = "IO";
                  } else if (kind === "IO.FileRead") {
                    p_i14840 = "IO.FileSystem";
                  } else if (kind === "IO.FileWrite") {
                    p_i14840 = "IO.FileSystem";
                  } else if (kind === "IO.Network") {
                    p_i14840 = "IO";
                  } else if (kind === "IO.NetConnect") {
                    p_i14840 = "IO.Network";
                  } else if (kind === "IO.NetListen") {
                    p_i14840 = "IO.Network";
                  } else if (kind === "IO.Process") {
                    p_i14840 = "IO";
                  } else if (kind === "IO.Clock") {
                    p_i14840 = "IO";
                  } else if (kind === "IO.Random") {
                    p_i14840 = "IO";
                  } else if (kind === "IO.Signal") {
                    p_i14840 = "IO";
                  } else if (kind === "IO.Database") {
                    p_i14840 = "IO.NetConnect";
                  } else if (kind === "IO.Spawn") {
                    p_i14840 = "IO";
                  } else if (kind === "IO.Mut") {
                    p_i14840 = "IO";
                  } else if (kind === "IO.Telemetry") {
                    p_i14840 = "IO";
                  } else if (kind === "IO.NetConnect.TLS") {
                    p_i14840 = "IO.NetConnect";
                  } else if (kind === "IO.WebSocket") {
                    p_i14840 = "IO.NetConnect";
                  } else if (kind === "IO.Foreign") {
                    p_i14840 = "IO";
                  } else if (kind === "IO.Foreign.Blocking") {
                    p_i14840 = "IO.Foreign";
                  } else if (kind === "IO.Registry") {
                    p_i14840 = "IO";
                  } else {
                    p_i14840 = "";
                  }
                  {
                    const $t1096_i14841 = (p_i14840 === "");
                    if ($t1096_i14841 === true) {
                      {
                        const $t1097_i14842 = { $: "Nil" };
                        $t811_i14781 = { $: "Cons", _0: kind, _1: $t1097_i14842 };
                      }
                    } else {
                      {
                        const $trmc7_i14843 = { $: "Cons", _0: kind, _1: null };
                        Authority$kind_chain$dps(p_i14840, $trmc7_i14843);
                        $t811_i14781 = $trmc7_i14843;
                      }
                    }
                  }
                }
                {
                  const $rc_67_i14782 = Authority$first_refusal(kind, $t811_i14781, target, cwd_i14780, $t807_i9657);
                  return $rc_67_i14782;
                }
              }
            }
          }
        }
      }
    }
  }
}
const Authority$check$clo = { _0: ($_, kind, target) => Authority$check(kind, target) };

function Authority$first_refusal($tco_a0, $tco_a1, $tco_a2, $tco_a3, $tco_a4) {
  __tco: for (;;) {
    const kind = $tco_a0;
    const chain = $tco_a1;
    const target = $tco_a2;
    const cwd = $tco_a3;
    const layers = $tco_a4;
    switch (layers.$) {
      case "Nil": {
        {
          const $t812 = {  };
          return { $: "Ok", _0: $t812 };
        }
        break;
      }
      case "Cons": {
        const $f815 = layers._0;
        const $f816 = layers._1;
        switch ($f815.$) {
          case "Layer": {
            const $f817 = $f815._0;
            const $f818 = $f815._1;
            const $f819 = $f815._2;
            {
              const rest = $f816;
              {
                const scopes = $f819;
                {
                  const text = $f818;
                  {
                    const limit = $f817;
                    {
                      let $t813;
                      $t813 = Authority$admits_in(scopes, chain, kind, target, cwd);
                      if ($t813 === true) {
                        {
                          $tco_a0 = kind;
                          $tco_a1 = chain;
                          $tco_a2 = target;
                          $tco_a3 = cwd;
                          $tco_a4 = rest;
                          continue __tco;
                        }
                      } else {
                        {
                          const $t814 = { $: "CapError", _0: kind, _1: target, _2: limit, _3: text };
                          return { $: "Err", _0: $t814 };
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
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
    return undefined;
  }
}
const Authority$first_refusal$clo = { _0: ($_, kind, chain, target, cwd, layers) => Authority$first_refusal(kind, chain, target, cwd, layers) };

function Authority$launch_init(request, scoped) {
  {
    const grant = march_cap_grant_text();
    {
      let $t833;
      {
        const $t832 = (!scoped);
        if ($t832 === true) {
          $t833 = (grant === "");
        } else {
          $t833 = false;
        }
      }
      if ($t833 === true) {
        return {  };
      } else {
        {
          const $t834 = Authority$parse(request);
          switch ($t834.$) {
            case "Err": {
              const $f853 = $t834._0;
              {
                const e = $f853;
                march_panic_site("stdlib/authority.march", 186, 16, 76);
                {
                  let $t835;
                  {
                    const $rc_68 = ("internal: main's request is not a scope list: " + e);
                    $t835 = $rc_68;
                  }
                  return (() => { throw march_panic_error("panic: ", $t835); })();
                }
              }
              break;
            }
            case "Ok": {
              const $f854 = $t834._0;
              {
                const req = $f854;
                {
                  const $t836 = (grant === "");
                  if ($t836 === true) {
                    {
                      let $t838;
                      {
                        const $t837 = { $: "ByLaunch" };
                        $t838 = { $: "Layer", _0: $t837, _1: request, _2: req };
                      }
                      {
                        const $t839 = { $: "Nil" };
                        {
                          const $t840 = { $: "Cons", _0: $t838, _1: $t839 };
                          return march_cap_set_launch($t840);
                        }
                      }
                    }
                  } else {
                    {
                      const $t841 = Authority$parse(grant);
                      switch ($t841.$) {
                        case "Err": {
                          const $f851 = $t841._0;
                          {
                            const e = $f851;
                            {
                              let $t842;
                              {
                                const $rc_70 = ("march: MARCH_GRANT is not a scope list: " + e);
                                $t842 = $rc_70;
                              }
                              {
                                const $rc_69 = Authority$launch_error($t842);
                                return $rc_69;
                              }
                            }
                          }
                          break;
                        }
                        case "Ok": {
                          const $f852 = $t841._0;
                          {
                            const g = $f852;
                            {
                              let $t843;
                              {
                                let $rc_73;
                                $rc_73 = Authority$first_outside(g, req);
                                $t843 = $rc_73;
                              }
                              switch ($t843.$) {
                                case "Some": {
                                  const $f850 = $t843._0;
                                  {
                                    const s = $f850;
                                    {
                                      let $t845;
                                      {
                                        const $t844 = Authority$scope_text(s);
                                        {
                                          const $rc_72 = march_string_concat_n("march: MARCH_GRANT grants ", $t844, ", which main does not request (main requests: ", request, ")");
                                          $t845 = $rc_72;
                                        }
                                      }
                                      {
                                        const $rc_71 = Authority$launch_error($t845);
                                        return $rc_71;
                                      }
                                    }
                                  }
                                  break;
                                }
                                case "None": {
                                  {
                                    let $t847;
                                    {
                                      const $t846 = { $: "ByLaunch" };
                                      $t847 = { $: "Layer", _0: $t846, _1: grant, _2: g };
                                    }
                                    {
                                      const $t848 = { $: "Nil" };
                                      {
                                        const $t849 = { $: "Cons", _0: $t847, _1: $t848 };
                                        return march_cap_set_launch($t849);
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
    const $t855 = (msg + "\n");
    {
      const $rc_74 = march_cap_launch_fail($t855);
      return $rc_74;
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
        const $f857 = a._0;
        const $f858 = a._1;
        {
          const rest = $f858;
          {
            const s = $f857;
            {
              let $t856;
              $t856 = Authority$covered(s, b);
              if ($t856 === true) {
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

function Authority$admits_in($tco_a0, $tco_a1, $tco_a2, $tco_a3, $tco_a4) {
  __tco: for (;;) {
    const scopes = $tco_a0;
    const chain = $tco_a1;
    const kind = $tco_a2;
    const target = $tco_a3;
    const cwd = $tco_a4;
    switch (scopes.$) {
      case "Nil": {
        return false;
        break;
      }
      case "Cons": {
        const $f890 = scopes._0;
        const $f891 = scopes._1;
        switch ($f890.$) {
          case "CapEntry": {
            const $f892 = $f890._0;
            const $f893 = $f890._1;
            {
              const rest = $f891;
              {
                const arg = $f893;
                {
                  const k = $f892;
                  {
                    let $t889;
                    {
                      let $t888;
                      {
                        const $rc_78 = Authority$member(chain, k);
                        $t888 = $rc_78;
                      }
                      if ($t888 === true) {
                        $t889 = Authority$arg_admits(arg, kind, target, cwd);
                      } else {
                        $t889 = false;
                      }
                    }
                    if ($t889 === true) {
                      return true;
                    } else {
                      {
                        $tco_a0 = rest;
                        $tco_a1 = chain;
                        $tco_a2 = kind;
                        $tco_a3 = target;
                        $tco_a4 = cwd;
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
        break;
      }
      default: {
        return (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
      }
    }
    return undefined;
  }
}
const Authority$admits_in$clo = { _0: ($_, scopes, chain, kind, target, cwd) => Authority$admits_in(scopes, chain, kind, target, cwd) };

function Authority$arg_admits(arg, kind, target, cwd) {
  switch (arg.$) {
    case "Any": {
      return true;
      break;
    }
    case "Paths": {
      const $f926 = arg._0;
      {
        const ps = $f926;
        {
          let $t903;
          {
            let $t902;
            {
              let $t1102_i62;
              {
                const $t1101_i61 = (kind === "IO.FileRead");
                if ($t1101_i61 === true) {
                  $t1102_i62 = true;
                } else {
                  $t1102_i62 = (kind === "IO.FileWrite");
                }
              }
              if ($t1102_i62 === true) {
                $t902 = true;
              } else {
                $t902 = (kind === "IO.FileSystem");
              }
            }
            $t903 = (!$t902);
          }
          if ($t903 === true) {
            return false;
          } else {
            {
              let $t906;
              {
                const $t904 = (cwd === "");
                if ($t904 === true) {
                  {
                    const $t905 = march_string_starts_with(target, "/");
                    $t906 = (!$t905);
                  }
                } else {
                  $t906 = false;
                }
              }
              if ($t906 === true) {
                return false;
              } else {
                {
                  const $t907 = Authority$resolve(cwd, target);
                  {
                    let $rc_79;
                    {
                      const $t963_i9687 = march_string_starts_with($t907, "/");
                      {
                        let $t964_i9693;
                        {
                          const $t1105_i75_i9689 = march_string_split($t907, "/");
                          {
                            const $t1106_i76_i9690 = { $: "Nil" };
                            {
                              const $t1107_i77_i9691 = Authority$fold_segments($t1105_i75_i9689, $t1106_i76_i9690);
                              {
                                const $t1108_i78_i9692 = { $: "Nil" };
                                $t964_i9693 = Authority$rev($t1107_i77_i9691, $t1108_i78_i9692);
                              }
                            }
                          }
                        }
                        {
                          const $rc_87_i9694 = Authority$any_within_segs(ps, $t963_i9687, $t964_i9693);
                          $rc_79 = $rc_87_i9694;
                        }
                      }
                    }
                    return $rc_79;
                  }
                }
              }
            }
          }
        }
      }
      break;
    }
    case "Hosts": {
      const $f927 = arg._0;
      {
        const spec = $f927;
        {
          const $t908 = (kind === "IO.NetConnect");
          if ($t908 === true) {
            return Authority$host_permits(spec, target);
          } else {
            {
              const $rc_80 = (target === "");
              return $rc_80;
            }
          }
        }
      }
      break;
    }
    case "Names": {
      const $f928 = arg._0;
      const $f929 = arg._1;
      {
        const pre = $f929;
        {
          const ns = $f928;
          {
            let $t909;
            {
              const $t1103_i69 = (kind === "IO.Mut");
              if ($t1103_i69 === true) {
                $t909 = true;
              } else {
                $t909 = (kind === "IO.Registry");
              }
            }
            if ($t909 === true) {
              {
                let $rc_81;
                {
                  const $t1146_i67 = Authority$member(ns, target);
                  if ($t1146_i67 === true) {
                    $rc_81 = true;
                  } else {
                    $rc_81 = Authority$starts_with_any(target, pre);
                  }
                }
                return $rc_81;
              }
            } else {
              return false;
            }
          }
        }
      }
      break;
    }
    case "HostAt": {
      const $f934 = arg._0;
      const $f935 = arg._1;
      const $f936 = arg._2;
      const $f937 = arg._3;
      {
        const port = $f937;
        {
          const wild = $f936;
          {
            const h = $f935;
            {
              const $t910 = (kind === "IO.NetConnect");
              if ($t910 === true) {
                {
                  const $t911 = (h === "");
                  if ($t911 === true) {
                    return true;
                  } else {
                    {
                      const $t912 = Authority$split_target(target);
                      const $f913 = $t912._0;
                      const $f914 = $t912._1;
                      {
                        const tp = $f914;
                        {
                          const th = $f913;
                          {
                            const $rc_82 = Authority$host_matches(h, wild, port, th, tp);
                            return $rc_82;
                          }
                        }
                      }
                    }
                  }
                }
              } else {
                {
                  const $rc_83 = (target === "");
                  return $rc_83;
                }
              }
            }
          }
        }
      }
      break;
    }
    case "PathsAt": {
      const $f950 = arg._0;
      {
        const ps = $f950;
        {
          let $t920;
          {
            let $t919;
            {
              let $t1102_i73;
              {
                const $t1101_i72 = (kind === "IO.FileRead");
                if ($t1101_i72 === true) {
                  $t1102_i73 = true;
                } else {
                  $t1102_i73 = (kind === "IO.FileWrite");
                }
              }
              if ($t1102_i73 === true) {
                $t919 = true;
              } else {
                $t919 = (kind === "IO.FileSystem");
              }
            }
            $t920 = (!$t919);
          }
          if ($t920 === true) {
            return false;
          } else {
            {
              let $t923;
              {
                const $t921 = (cwd === "");
                if ($t921 === true) {
                  {
                    const $t922 = march_string_starts_with(target, "/");
                    $t923 = (!$t922);
                  }
                } else {
                  $t923 = false;
                }
              }
              if ($t923 === true) {
                return false;
              } else {
                {
                  let $t925;
                  {
                    const $t924 = Authority$resolve(cwd, target);
                    {
                      const $rc_85 = Authority$normalize($t924);
                      $t925 = $rc_85;
                    }
                  }
                  {
                    const $rc_84 = Authority$any_normal_within(ps, $t925);
                    return $rc_84;
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
const Authority$arg_admits$clo = { _0: ($_, arg, kind, target, cwd) => Authority$arg_admits(arg, kind, target, cwd) };

function Authority$any_normal_within($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const ps = $tco_a0;
    const n = $tco_a1;
    switch (ps.$) {
      case "Nil": {
        return false;
        break;
      }
      case "Cons": {
        const $f957 = ps._0;
        const $f958 = ps._1;
        {
          const rest = $f958;
          {
            const p = $f957;
            {
              let $t956;
              {
                let $t952;
                {
                  const $t951 = (p === "/");
                  if ($t951 === true) {
                    $t952 = true;
                  } else {
                    $t952 = (n === p);
                  }
                }
                if ($t952 === true) {
                  $t956 = true;
                } else {
                  {
                    const $t953 = march_string_starts_with(n, p);
                    if ($t953 === true) {
                      {
                        let $t955;
                        {
                          const $t954 = march_string_byte_length(p);
                          $t955 = march_string_slice(n, $t954, 1);
                        }
                        {
                          const $rc_86 = ($t955 === "/");
                          $t956 = $rc_86;
                        }
                      }
                    } else {
                      $t956 = false;
                    }
                  }
                }
              }
              if ($t956 === true) {
                return true;
              } else {
                {
                  $tco_a0 = rest;
                  $tco_a1 = n;
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
const Authority$any_normal_within$clo = { _0: ($_, ps, n) => Authority$any_normal_within(ps, n) };

function Authority$any_within_segs($tco_a0, $tco_a1, $tco_a2) {
  __tco: for (;;) {
    const ps = $tco_a0;
    const abs = $tco_a1;
    const segs = $tco_a2;
    switch (ps.$) {
      case "Nil": {
        return false;
        break;
      }
      case "Cons": {
        const $f969 = ps._0;
        const $f970 = ps._1;
        {
          const rest = $f970;
          {
            const s = $f969;
            {
              let $t968;
              {
                let $t966;
                {
                  const $t965 = march_string_starts_with(s, "/");
                  $t966 = ($t965 === abs);
                }
                if ($t966 === true) {
                  {
                    let $t967;
                    {
                      const $t1105_i80 = march_string_split(s, "/");
                      {
                        const $t1106_i81 = { $: "Nil" };
                        {
                          const $t1107_i82 = Authority$fold_segments($t1105_i80, $t1106_i81);
                          {
                            const $t1108_i83 = { $: "Nil" };
                            $t967 = Authority$rev($t1107_i82, $t1108_i83);
                          }
                        }
                      }
                    }
                    {
                      const $rc_88 = Authority$segs_prefix($t967, segs);
                      $t968 = $rc_88;
                    }
                  }
                } else {
                  $t968 = false;
                }
              }
              if ($t968 === true) {
                return true;
              } else {
                {
                  $tco_a0 = rest;
                  $tco_a1 = abs;
                  $tco_a2 = segs;
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
const Authority$any_within_segs$clo = { _0: ($_, ps, abs, segs) => Authority$any_within_segs(ps, abs, segs) };

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
        const $f985 = b._0;
        const $f986 = b._1;
        switch ($f985.$) {
          case "CapEntry": {
            const $f987 = $f985._0;
            const $f988 = $f985._1;
            {
              const rest = $f986;
              {
                const outer = $f988;
                {
                  const k = $f987;
                  switch (s.$) {
                    case "CapEntry": {
                      const $f979 = s._0;
                      const $f980 = s._1;
                      {
                        const inner = $f980;
                        {
                          const ik = $f979;
                          {
                            let $t978;
                            {
                              let $t977;
                              {
                                const $rc_89 = Authority$kind_subsumes(k, ik);
                                $t977 = $rc_89;
                              }
                              if ($t977 === true) {
                                $t978 = Authority$arg_subsumes(outer, inner);
                              } else {
                                $t978 = false;
                              }
                            }
                            if ($t978 === true) {
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
      const $f1008 = outer._0;
      {
        const o_paths = $f1008;
        {
          const $t997 = Authority$path_list(inner);
          switch ($t997.$) {
            case "Some": {
              const $f998 = $t997._0;
              {
                const i_paths = $f998;
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
    case "PathsAt": {
      const $f1009 = outer._0;
      {
        const o_paths = $f1009;
        {
          const $t999 = Authority$path_list(inner);
          switch ($t999.$) {
            case "Some": {
              const $f1000 = $t999._0;
              {
                const i_paths = $f1000;
                {
                  const $rc_91 = Authority$all_paths_within(i_paths, o_paths);
                  return $rc_91;
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
      const $f1010 = outer._0;
      const $f1011 = outer._1;
      {
        const o_pre = $f1011;
        {
          const o_names = $f1010;
          switch (inner.$) {
            case "Names": {
              const $f1002 = inner._0;
              const $f1003 = inner._1;
              {
                const i_pre = $f1003;
                {
                  const i_names = $f1002;
                  {
                    let $t1001;
                    {
                      const $rc_93 = Authority$all_names_admitted(i_names, o_names, o_pre);
                      $t1001 = $rc_93;
                    }
                    if ($t1001 === true) {
                      {
                        const $rc_92 = Authority$all_prefixes_under(i_pre, o_pre);
                        return $rc_92;
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
      const $f1016 = outer._0;
      {
        const o = $f1016;
        {
          const $t1004 = Authority$host_spec(inner);
          switch ($t1004.$) {
            case "Some": {
              const $f1005 = $t1004._0;
              {
                const i = $f1005;
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
    case "HostAt": {
      const $f1017 = outer._0;
      const $f1018 = outer._1;
      const $f1019 = outer._2;
      const $f1020 = outer._3;
      {
        const o = $f1017;
        {
          const $t1006 = Authority$host_spec(inner);
          switch ($t1006.$) {
            case "Some": {
              const $f1007 = $t1006._0;
              {
                const i = $f1007;
                {
                  const $rc_95 = Authority$host_subsumes(o, i);
                  return $rc_95;
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
      const $f1033 = a._0;
      {
        const ps = $f1033;
        return { $: "Some", _0: ps };
      }
      break;
    }
    case "PathsAt": {
      const $f1038 = a._0;
      {
        const ps = $f1038;
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
      const $f1043 = a._0;
      {
        const s = $f1043;
        return { $: "Some", _0: s };
      }
      break;
    }
    case "HostAt": {
      const $f1048 = a._0;
      const $f1049 = a._1;
      const $f1050 = a._2;
      const $f1051 = a._3;
      {
        const s = $f1048;
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
        const $f1069 = i_paths._0;
        const $f1070 = i_paths._1;
        {
          const rest = $f1070;
          {
            const p = $f1069;
            {
              const $t1068 = Authority$path_in_any(p, o_paths);
              if ($t1068 === true) {
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
        const $f1076 = o_paths._0;
        const $f1077 = o_paths._1;
        {
          const rest = $f1077;
          {
            const o = $f1076;
            {
              const $t1075 = Authority$path_within(o, p);
              if ($t1075 === true) {
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
        const $f1083 = ns._0;
        const $f1084 = ns._1;
        {
          const rest = $f1084;
          {
            const n = $f1083;
            {
              let $t1082;
              {
                const $t1146_i87 = Authority$member(o_names, n);
                if ($t1146_i87 === true) {
                  $t1082 = true;
                } else {
                  $t1082 = Authority$starts_with_any(n, o_pre);
                }
              }
              if ($t1082 === true) {
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
        const $f1090 = i_pre._0;
        const $f1091 = i_pre._1;
        {
          const rest = $f1091;
          {
            const p = $f1090;
            {
              const $t1089 = Authority$starts_with_any(p, o_pre);
              if ($t1089 === true) {
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

function Authority$kind_chain$dps($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const kind = $tco_a0;
    const $dst = $tco_a1;
    {
      let p;
      if (kind === "IO.Console") {
        p = "IO";
      } else if (kind === "IO.FileSystem") {
        p = "IO";
      } else if (kind === "IO.FileRead") {
        p = "IO.FileSystem";
      } else if (kind === "IO.FileWrite") {
        p = "IO.FileSystem";
      } else if (kind === "IO.Network") {
        p = "IO";
      } else if (kind === "IO.NetConnect") {
        p = "IO.Network";
      } else if (kind === "IO.NetListen") {
        p = "IO.Network";
      } else if (kind === "IO.Process") {
        p = "IO";
      } else if (kind === "IO.Clock") {
        p = "IO";
      } else if (kind === "IO.Random") {
        p = "IO";
      } else if (kind === "IO.Signal") {
        p = "IO";
      } else if (kind === "IO.Database") {
        p = "IO.NetConnect";
      } else if (kind === "IO.Spawn") {
        p = "IO";
      } else if (kind === "IO.Mut") {
        p = "IO";
      } else if (kind === "IO.Telemetry") {
        p = "IO";
      } else if (kind === "IO.NetConnect.TLS") {
        p = "IO.NetConnect";
      } else if (kind === "IO.WebSocket") {
        p = "IO.NetConnect";
      } else if (kind === "IO.Foreign") {
        p = "IO";
      } else if (kind === "IO.Foreign.Blocking") {
        p = "IO.Foreign";
      } else if (kind === "IO.Registry") {
        p = "IO";
      } else {
        p = "";
      }
      {
        const $t1096 = (p === "");
        if ($t1096 === true) {
          {
            const $t1097 = { $: "Nil" };
            {
              const $trmc6 = { $: "Cons", _0: kind, _1: $t1097 };
              return ($dst._1 = $trmc6, undefined);
            }
          }
        } else {
          {
            const $trmc5 = { $: "Cons", _0: kind, _1: null };
            ($dst._1 = $trmc5, undefined);
            {
              $tco_a0 = p;
              $tco_a1 = $trmc5;
              continue __tco;
            }
          }
        }
      }
    }
    return undefined;
  }
}
const Authority$kind_chain$dps$clo = { _0: ($_, kind, $dst) => Authority$kind_chain$dps(kind, $dst) };

function Authority$kind_subsumes($tco_a0, $tco_a1) {
  __tco: for (;;) {
    const parent = $tco_a0;
    const child = $tco_a1;
    {
      const $t1099 = (parent === child);
      if ($t1099 === true) {
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
            const $t1100 = (p === "");
            if ($t1100 === true) {
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

function Authority$resolve(cwd, p) {
  {
    const $t1104 = march_string_starts_with(p, "/");
    if ($t1104 === true) {
      return p;
    } else {
      {
        const $rc_96 = march_string_concat3(cwd, "/", p);
        return $rc_96;
      }
    }
  }
}
const Authority$resolve$clo = { _0: ($_, cwd, p) => Authority$resolve(cwd, p) };

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
        const $f1120 = parts._0;
        const $f1121 = parts._1;
        {
          const rest = $f1121;
          {
            const s = $f1120;
            {
              let $t1110;
              {
                const $t1109 = (s === "");
                if ($t1109 === true) {
                  $t1110 = true;
                } else {
                  $t1110 = (s === ".");
                }
              }
              if ($t1110 === true) {
                {
                  $tco_a0 = rest;
                  $tco_a1 = acc;
                  continue __tco;
                }
              } else {
                {
                  const $t1111 = (s === "..");
                  if ($t1111 === true) {
                    switch (acc.$) {
                      case "Nil": {
                        {
                          const $t1112 = { $: "Nil" };
                          {
                            $tco_a0 = rest;
                            $tco_a1 = $t1112;
                            continue __tco;
                          }
                        }
                        break;
                      }
                      case "Cons": {
                        const $f1113 = acc._0;
                        const $f1114 = acc._1;
                        {
                          const up = $f1114;
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
                      const $t1119 = { $: "Cons", _0: s, _1: acc };
                      {
                        $tco_a0 = rest;
                        $tco_a1 = $t1119;
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
      let $t1126;
      {
        const $t1105_i92 = march_string_split(p, "/");
        {
          const $t1106_i93 = { $: "Nil" };
          {
            const $t1107_i94 = Authority$fold_segments($t1105_i92, $t1106_i93);
            {
              const $t1108_i95 = { $: "Nil" };
              $t1126 = Authority$rev($t1107_i94, $t1108_i95);
            }
          }
        }
      }
      {
        const $rc_98 = march_string_join($t1126, "/");
        body = $rc_98;
      }
    }
    {
      const $t1127 = march_string_starts_with(p, "/");
      if ($t1127 === true) {
        {
          const $rc_97 = ("/" + body);
          return $rc_97;
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
    let $t1130;
    {
      const $t1128 = march_string_starts_with(scope, "/");
      {
        const $t1129 = march_string_starts_with(p, "/");
        $t1130 = ($t1128 === $t1129);
      }
    }
    if ($t1130 === true) {
      {
        let $t1131;
        {
          const $t1105_i102 = march_string_split(scope, "/");
          {
            const $t1106_i103 = { $: "Nil" };
            {
              const $t1107_i104 = Authority$fold_segments($t1105_i102, $t1106_i103);
              {
                const $t1108_i105 = { $: "Nil" };
                $t1131 = Authority$rev($t1107_i104, $t1108_i105);
              }
            }
          }
        }
        {
          let $t1132;
          {
            const $t1105_i97 = march_string_split(p, "/");
            {
              const $t1106_i98 = { $: "Nil" };
              {
                const $t1107_i99 = Authority$fold_segments($t1105_i97, $t1106_i98);
                {
                  const $t1108_i100 = { $: "Nil" };
                  $t1132 = Authority$rev($t1107_i99, $t1108_i100);
                }
              }
            }
          }
          {
            const $rc_99 = Authority$segs_prefix($t1131, $t1132);
            return $rc_99;
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
        const $f1140 = pre._0;
        const $f1141 = pre._1;
        {
          const pt = $f1141;
          {
            const a = $f1140;
            switch (segs.$) {
              case "Nil": {
                return false;
                break;
              }
              case "Cons": {
                const $f1134 = segs._0;
                const $f1135 = segs._1;
                {
                  const st = $f1135;
                  {
                    const b = $f1134;
                    {
                      const $t1133 = (a === b);
                      if ($t1133 === true) {
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
        const $f1148 = pre._0;
        const $f1149 = pre._1;
        {
          const rest = $f1149;
          {
            const p = $f1148;
            {
              const $t1147 = march_string_starts_with(n, p);
              if ($t1147 === true) {
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

function Authority$host_permits(spec, target) {
  {
    let raw;
    {
      const spec_i9695 = spec;
      {
        const $t1181_i9696 = march_string_index_of(spec, ";");
        switch ($t1181_i9696.$) {
          case "None": {
            raw = spec;
            break;
          }
          case "Some": {
            const $f1182_i9697 = $t1181_i9696._0;
            {
              const i_i9698 = $f1182_i9697;
              {
                const $rc_101_i9699 = march_string_slice(spec, 0, i_i9698);
                raw = $rc_101_i9699;
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
      const $t1154 = (raw === "");
      if ($t1154 === true) {
        return true;
      } else {
        {
          const $t1155 = Authority$parse_host_pattern(raw);
          switch ($t1155.$) {
            case "Err": {
              const $f1163 = $t1155._0;
              return false;
              break;
            }
            case "Ok": {
              const $f1164 = $t1155._0;
              const $f1165 = $f1164._0;
              const $f1166 = $f1164._1;
              const $f1167 = $f1164._2;
              const $f1168 = $f1164._3;
              {
                const port = $f1167;
                {
                  const wild = $f1166;
                  {
                    const h = $f1165;
                    {
                      const $t1156 = Authority$split_target(target);
                      const $f1157 = $t1156._0;
                      const $f1158 = $t1156._1;
                      {
                        const tp = $f1158;
                        {
                          const th = $f1157;
                          {
                            const $rc_100 = Authority$host_matches(h, wild, port, th, tp);
                            return $rc_100;
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
  }
}
const Authority$host_permits$clo = { _0: ($_, spec, target) => Authority$host_permits(spec, target) };

function Authority$split_target(t) {
  {
    const $t1183 = march_string_last_index_of(t, ":");
    switch ($t1183.$) {
      case "None": {
        return { _0: t, _1: 0 };
        break;
      }
      case "Some": {
        const $f1191 = $t1183._0;
        {
          const i = $f1191;
          {
            const $t1184 = march_string_slice(t, 0, i);
            {
              let $t1190;
              {
                let $t1189;
                {
                  const $t1185 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                  {
                    let $t1188;
                    {
                      let $t1187;
                      {
                        const $t1186 = march_string_byte_length(t);
                        $t1187 = (($t1186 - i) < 4611686018427387904 && ($t1186 - i) >= -4611686018427387904 ? ($t1186 - i) : march_int_ovf(($t1186 - i), 1));
                      }
                      $t1188 = (($t1187 - 1) < 4611686018427387904 && ($t1187 - 1) >= -4611686018427387904 ? ($t1187 - 1) : march_int_ovf(($t1187 - 1), 1));
                    }
                    {
                      const $rc_103 = march_string_slice(t, $t1185, $t1188);
                      $t1189 = $rc_103;
                    }
                  }
                }
                {
                  const $rc_102 = Authority$port_or_zero($t1189);
                  $t1190 = $rc_102;
                }
              }
              return { _0: $t1184, _1: $t1190 };
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
const Authority$split_target$clo = { _0: ($_, t) => Authority$split_target(t) };

function Authority$host_matches(h, wild, port, host, tport) {
  {
    const th = Authority$normalize_host(host);
    {
      let $t1194;
      {
        const $t1192 = (port !== 0);
        {
          const $t1193 = (port !== tport);
          $t1194 = ($t1192 && $t1193);
        }
      }
      if ($t1194 === true) {
        return false;
      } else {
        if (wild === true) {
          {
            const suffix = ("." + h);
            {
              let $t1197;
              {
                const $t1195 = march_string_byte_length(th);
                {
                  const $t1196 = march_string_byte_length(suffix);
                  $t1197 = ($t1195 > $t1196);
                }
              }
              if ($t1197 === true) {
                {
                  const $rc_104 = march_string_ends_with(th, suffix);
                  return $rc_104;
                }
              } else {
                return false;
              }
            }
          }
        } else {
          {
            const $rc_105 = (th === h);
            return $rc_105;
          }
        }
      }
    }
  }
}
const Authority$host_matches$clo = { _0: ($_, h, wild, port, host, tport) => Authority$host_matches(h, wild, port, host, tport) };

function Authority$normalize_host(h) {
  {
    const l = march_string_to_lowercase(h);
    {
      const $t1198 = march_string_ends_with(l, ".");
      if ($t1198 === true) {
        {
          let $t1200;
          {
            const $t1199 = march_string_byte_length(l);
            $t1200 = (($t1199 - 1) < 4611686018427387904 && ($t1199 - 1) >= -4611686018427387904 ? ($t1199 - 1) : march_int_ovf(($t1199 - 1), 1));
          }
          {
            const $rc_106 = march_string_slice(l, 0, $t1200);
            return $rc_106;
          }
        }
      } else {
        return l;
      }
    }
  }
}
const Authority$normalize_host$clo = { _0: ($_, h) => Authority$normalize_host(h) };

function Authority$port_or_zero(s) {
  {
    let $t1205;
    {
      let $t1203;
      {
        const $t1201 = (s === "");
        if ($t1201 === true) {
          $t1203 = true;
        } else {
          {
            const $t1202 = march_string_byte_length(s);
            $t1203 = ($t1202 > 5);
          }
        }
      }
      if ($t1203 === true) {
        $t1205 = true;
      } else {
        {
          const $t1204 = Authority$all_chars(s, "0123456789", 0);
          $t1205 = (!$t1204);
        }
      }
    }
    if ($t1205 === true) {
      return 0;
    } else {
      {
        const $t1206 = march_string_to_int(s);
        switch ($t1206.$) {
          case "Some": {
            const $f1210 = $t1206._0;
            {
              const n = $f1210;
              {
                let $t1209;
                {
                  const $t1207 = (n >= 1);
                  {
                    const $t1208 = (n <= 65535);
                    $t1209 = ($t1207 && $t1208);
                  }
                }
                if ($t1209 === true) {
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
      let $t1212;
      {
        const $t1211 = march_string_byte_length(s);
        $t1212 = (i >= $t1211);
      }
      if ($t1212 === true) {
        return true;
      } else {
        {
          let $t1214;
          {
            const $t1213 = march_string_slice(s, i, 1);
            {
              const $rc_107 = march_string_contains(allowed, $t1213);
              $t1214 = $rc_107;
            }
          }
          if ($t1214 === true) {
            {
              const $t1215 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
              {
                $tco_a0 = s;
                $tco_a1 = allowed;
                $tco_a2 = $t1215;
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
    const $t1216 = (raw === "");
    if ($t1216 === true) {
      return { $: "Err", _0: "a host scope cannot be empty" };
    } else {
      {
        const $t1217 = march_string_contains(raw, "://");
        if ($t1217 === true) {
          return { $: "Err", _0: "a host scope names a host, not a URL: drop the scheme (`https://`)" };
        } else {
          {
            let $p1230;
            {
              const $t1218 = march_string_index_of(raw, "/");
              switch ($t1218.$) {
                case "None": {
                  {
                    let $t1220;
                    {
                      const $t1219 = { $: "None" };
                      $t1220 = { $: "Ok", _0: $t1219 };
                    }
                    $p1230 = { _0: raw, _1: $t1220 };
                  }
                  break;
                }
                case "Some": {
                  const $f1226 = $t1218._0;
                  {
                    const i = $f1226;
                    {
                      const $t1221 = march_string_slice(raw, 0, i);
                      {
                        let $t1225;
                        {
                          let $t1224;
                          {
                            let $t1223;
                            {
                              const $t1222 = march_string_byte_length(raw);
                              $t1223 = (($t1222 - i) < 4611686018427387904 && ($t1222 - i) >= -4611686018427387904 ? ($t1222 - i) : march_int_ovf(($t1222 - i), 1));
                            }
                            {
                              const $rc_111 = march_string_slice(raw, i, $t1223);
                              $t1224 = $rc_111;
                            }
                          }
                          {
                            const $rc_110 = Authority$parse_scope_path($t1224);
                            $t1225 = $rc_110;
                          }
                        }
                        $p1230 = { _0: $t1221, _1: $t1225 };
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
              const host_raw = $p1230._0;
              {
                const path_r = $p1230._1;
                switch (path_r.$) {
                  case "Err": {
                    const $f1228 = path_r._0;
                    {
                      const e = $f1228;
                      {
                        const $rc_109 = { $: "Err", _0: e };
                        return $rc_109;
                      }
                    }
                    break;
                  }
                  case "Ok": {
                    const $f1229 = path_r._0;
                    {
                      const path = $f1229;
                      {
                        const $t1227 = march_string_to_lowercase(host_raw);
                        return Authority$host_part_pattern($t1227, path);
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
    const $t1231 = (s === "");
    if ($t1231 === true) {
      return { $: "Err", _0: "a host scope needs a host before its path" };
    } else {
      {
        const $t1232 = march_string_contains(s, "@");
        if ($t1232 === true) {
          return { $: "Err", _0: "a host scope cannot carry userinfo (`user@`)" };
        } else {
          {
            const $p1257 = Authority$split_host_port(s);
            {
              const host_part = $p1257._0;
              {
                const port_text = $p1257._1;
                {
                  let port;
                  {
                    const $t1233 = (port_text === "");
                    if ($t1233 === true) {
                      port = 0;
                    } else {
                      port = Authority$port_or_zero(port_text);
                    }
                  }
                  {
                    let $t1236;
                    {
                      const $t1234 = (port_text !== "");
                      {
                        const $t1235 = (port === 0);
                        $t1236 = ($t1234 && $t1235);
                      }
                    }
                    if ($t1236 === true) {
                      {
                        const $t1237 = march_string_concat3("`", port_text, "` is not a port (1-65535)");
                        {
                          const $rc_125 = { $: "Err", _0: $t1237 };
                          return $rc_125;
                        }
                      }
                    } else {
                      {
                        const $t1238 = march_string_starts_with(host_part, "[");
                        if ($t1238 === true) {
                          {
                            const n = march_string_byte_length(host_part);
                            {
                              let $t1243;
                              {
                                let $t1240;
                                {
                                  const $t1239 = (n >= 2);
                                  if ($t1239 === true) {
                                    $t1240 = march_string_ends_with(host_part, "]");
                                  } else {
                                    $t1240 = false;
                                  }
                                }
                                if ($t1240 === true) {
                                  {
                                    let $t1242;
                                    {
                                      const $t1241 = ((n - 2) < 4611686018427387904 && (n - 2) >= -4611686018427387904 ? (n - 2) : march_int_ovf((n - 2), 1));
                                      $t1242 = march_string_slice(host_part, 1, $t1241);
                                    }
                                    {
                                      let $rc_112;
                                      {
                                        const $t1285_i107 = ($t1242 !== "");
                                        if ($t1285_i107 === true) {
                                          $rc_112 = Authority$all_chars($t1242, "0123456789abcdef:.", 0);
                                        } else {
                                          $rc_112 = false;
                                        }
                                      }
                                      $t1243 = $rc_112;
                                    }
                                  }
                                } else {
                                  $t1243 = false;
                                }
                              }
                              if ($t1243 === true) {
                                {
                                  let $t1244;
                                  $t1244 = { _0: host_part, _1: false, _2: port, _3: path };
                                  {
                                    const $rc_124 = { $: "Ok", _0: $t1244 };
                                    return $rc_124;
                                  }
                                }
                              } else {
                                {
                                  const $t1245 = march_string_concat3("`", host_part, "` is not an IPv6 literal");
                                  {
                                    const $rc_123 = { $: "Err", _0: $t1245 };
                                    return $rc_123;
                                  }
                                }
                              }
                            }
                          }
                        } else {
                          {
                            let wild;
                            {
                              let $t1247;
                              {
                                const $t1246 = march_string_byte_length(host_part);
                                $t1247 = ($t1246 >= 2);
                              }
                              if ($t1247 === true) {
                                wild = march_string_starts_with(host_part, "*.");
                              } else {
                                wild = false;
                              }
                            }
                            {
                              let name;
                              {
                                let $t1250;
                                if (wild === true) {
                                  {
                                    let $t1249;
                                    {
                                      const $t1248 = march_string_byte_length(host_part);
                                      $t1249 = (($t1248 - 2) < 4611686018427387904 && ($t1248 - 2) >= -4611686018427387904 ? ($t1248 - 2) : march_int_ovf(($t1248 - 2), 1));
                                    }
                                    $t1250 = march_string_slice(host_part, 2, $t1249);
                                  }
                                } else {
                                  $t1250 = host_part;
                                }
                                {
                                  const $rc_113 = Authority$normalize_host($t1250);
                                  name = $rc_113;
                                }
                              }
                              {
                                let $t1252;
                                {
                                  const $t1251 = march_string_contains(name, "*");
                                  if ($t1251 === true) {
                                    $t1252 = true;
                                  } else {
                                    $t1252 = (host_part === "*");
                                  }
                                }
                                if ($t1252 === true) {
                                  {
                                    const $rc_122 = { $: "Err", _0: "a wildcard must be the whole leftmost label (`*.example.com`)" };
                                    return $rc_122;
                                  }
                                } else {
                                  {
                                    let $t1254;
                                    {
                                      let $t1253;
                                      {
                                        const $t1286_i9701 = (name !== "");
                                        if ($t1286_i9701 === true) {
                                          {
                                            const $t1287_i9702 = march_string_split(name, ".");
                                            {
                                              const $rc_130_i9703 = Authority$labels_ok($t1287_i9702);
                                              $t1253 = $rc_130_i9703;
                                            }
                                          }
                                        } else {
                                          $t1253 = false;
                                        }
                                      }
                                      $t1254 = (!$t1253);
                                    }
                                    if ($t1254 === true) {
                                      {
                                        const $t1255 = march_string_concat3("`", host_part, "` is not a host name: labels are letters, digits and `-`, separated by single dots");
                                        {
                                          const $rc_121 = { $: "Err", _0: $t1255 };
                                          return $rc_121;
                                        }
                                      }
                                    } else {
                                      {
                                        const $t1256 = { _0: name, _1: wild, _2: port, _3: path };
                                        {
                                          const $rc_120 = { $: "Ok", _0: $t1256 };
                                          return $rc_120;
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
    const $t1258 = march_string_starts_with(s, "[");
    if ($t1258 === true) {
      {
        const $t1259 = march_string_index_of(s, "]");
        switch ($t1259.$) {
          case "None": {
            return { _0: s, _1: "" };
            break;
          }
          case "Some": {
            const $f1274 = $t1259._0;
            {
              const i = $f1274;
              {
                let rest;
                {
                  const $t1260 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                  {
                    let $t1263;
                    {
                      let $t1262;
                      {
                        const $t1261 = march_string_byte_length(s);
                        $t1262 = (($t1261 - i) < 4611686018427387904 && ($t1261 - i) >= -4611686018427387904 ? ($t1261 - i) : march_int_ovf(($t1261 - i), 1));
                      }
                      $t1263 = (($t1262 - 1) < 4611686018427387904 && ($t1262 - 1) >= -4611686018427387904 ? ($t1262 - 1) : march_int_ovf(($t1262 - 1), 1));
                    }
                    rest = march_string_slice(s, $t1260, $t1263);
                  }
                }
                {
                  const $t1264 = (rest === "");
                  if ($t1264 === true) {
                    {
                      let $t1266;
                      {
                        const $t1265 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                        {
                          const $rc_126 = march_string_slice(s, 0, $t1265);
                          $t1266 = $rc_126;
                        }
                      }
                      return { _0: $t1266, _1: "" };
                    }
                  } else {
                    {
                      const $t1267 = march_string_starts_with(rest, ":");
                      if ($t1267 === true) {
                        {
                          let $t1269;
                          {
                            const $t1268 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                            {
                              const $rc_128 = march_string_slice(s, 0, $t1268);
                              $t1269 = $rc_128;
                            }
                          }
                          {
                            let $t1273;
                            {
                              let $t1272;
                              {
                                let $t1271;
                                {
                                  const $t1270 = march_string_byte_length(rest);
                                  $t1271 = (($t1270 - 1) < 4611686018427387904 && ($t1270 - 1) >= -4611686018427387904 ? ($t1270 - 1) : march_int_ovf(($t1270 - 1), 1));
                                }
                                {
                                  const $rc_127 = march_string_slice(rest, 1, $t1271);
                                  $t1272 = $rc_127;
                                }
                              }
                              $t1273 = Authority$port_text_of($t1272);
                            }
                            return { _0: $t1269, _1: $t1273 };
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
        const $t1275 = march_string_last_index_of(s, ":");
        switch ($t1275.$) {
          case "None": {
            return { _0: s, _1: "" };
            break;
          }
          case "Some": {
            const $f1283 = $t1275._0;
            {
              const i = $f1283;
              {
                const $t1276 = march_string_slice(s, 0, i);
                {
                  let $t1282;
                  {
                    let $t1281;
                    {
                      const $t1277 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                      {
                        let $t1280;
                        {
                          let $t1279;
                          {
                            const $t1278 = march_string_byte_length(s);
                            $t1279 = (($t1278 - i) < 4611686018427387904 && ($t1278 - i) >= -4611686018427387904 ? ($t1278 - i) : march_int_ovf(($t1278 - i), 1));
                          }
                          $t1280 = (($t1279 - 1) < 4611686018427387904 && ($t1279 - 1) >= -4611686018427387904 ? ($t1279 - 1) : march_int_ovf(($t1279 - 1), 1));
                        }
                        {
                          const $rc_129 = march_string_slice(s, $t1277, $t1280);
                          $t1281 = $rc_129;
                        }
                      }
                    }
                    $t1282 = Authority$port_text_of($t1281);
                  }
                  return { _0: $t1276, _1: $t1282 };
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
    const $t1284 = (p === "");
    if ($t1284 === true) {
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
        const $f1290 = ls._0;
        const $f1291 = ls._1;
        {
          const rest = $f1291;
          {
            const l = $f1290;
            {
              let $t1289;
              {
                const $t1288 = (l !== "");
                if ($t1288 === true) {
                  $t1289 = Authority$all_chars(l, "abcdefghijklmnopqrstuvwxyz0123456789-", 0);
                } else {
                  $t1289 = false;
                }
              }
              if ($t1289 === true) {
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
    const $t1296 = march_string_split(p, "/");
    {
      let $t1297;
      {
        const l_i9711 = $t1296;
        switch (l_i9711.$) {
          case "Cons": {
            const $f1307_i9712 = l_i9711._0;
            const $f1308_i9713 = l_i9711._1;
            {
              const rest_i9714 = $f1308_i9713;
              $t1297 = rest_i9714;
            }
            break;
          }
          case "Nil": {
            $t1297 = { $: "Nil" };
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
          const l_i9704 = $t1297;
          {
            const $t1313_i9705 = { $: "Nil" };
            {
              let $t1314_i9706;
              $t1314_i9706 = Authority$rev($t1297, $t1313_i9705);
              switch ($t1314_i9706.$) {
                case "Cons": {
                  const $f1316_i9707 = $t1314_i9706._0;
                  const $f1317_i9708 = $t1314_i9706._1;
                  if ($f1316_i9707 === "") {
                    {
                      const r_i9709 = $f1317_i9708;
                      {
                        const $t1315_i9710 = { $: "Nil" };
                        parts = Authority$rev(r_i9709, $t1315_i9710);
                      }
                    }
                  } else {
                    parts = $t1297;
                  }
                  break;
                }
                default: {
                  parts = $t1297;
                  break;
                }
              }
            }
          }
        }
        {
          let $t1298;
          $t1298 = Authority$bad_scope_segment(parts);
          switch ($t1298.$) {
            case "None": {
              {
                const $t1299 = { $: "Some", _0: parts };
                return { $: "Ok", _0: $t1299 };
              }
              break;
            }
            case "Some": {
              const $f1304 = $t1298._0;
              if ($f1304 === "") {
                return { $: "Err", _0: "a path scope cannot contain `//`" };
              } else {
                {
                  const seg = $f1304;
                  {
                    let $t1301;
                    {
                      const $t1300 = (seg === ".");
                      if ($t1300 === true) {
                        $t1301 = true;
                      } else {
                        $t1301 = (seg === "..");
                      }
                    }
                    if ($t1301 === true) {
                      {
                        let $t1302;
                        {
                          const $rc_131 = march_string_concat3("a path scope cannot contain a `", seg, "` segment");
                          $t1302 = $rc_131;
                        }
                        return { $: "Err", _0: $t1302 };
                      }
                    } else {
                      {
                        let $t1303;
                        {
                          const $rc_132 = march_string_concat3("the path segment `", seg, "` may contain only letters, digits, `-`, `_`, `.` and `~` (no `%`, `?`, `#` or `\\`)");
                          $t1303 = $rc_132;
                        }
                        return { $: "Err", _0: $t1303 };
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
        const $f1323 = segs._0;
        const $f1324 = segs._1;
        {
          const rest = $f1324;
          {
            const s = $f1323;
            {
              let $t1322;
              {
                let $t1320;
                {
                  let $t1319;
                  {
                    const $t1318 = (s === "");
                    if ($t1318 === true) {
                      $t1319 = true;
                    } else {
                      $t1319 = (s === ".");
                    }
                  }
                  if ($t1319 === true) {
                    $t1320 = true;
                  } else {
                    $t1320 = (s === "..");
                  }
                }
                if ($t1320 === true) {
                  $t1322 = true;
                } else {
                  {
                    const $t1321 = Authority$all_chars(s, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~", 0);
                    $t1322 = (!$t1321);
                  }
                }
              }
              if ($t1322 === true) {
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
          const $t1329 = { _0: nr, _1: mg, _2: ms };
          return { $: "Ok", _0: $t1329 };
        }
        break;
      }
      case "Cons": {
        const $f1341 = opts._0;
        const $f1342 = opts._1;
        {
          const rest = $f1342;
          {
            const o = $f1341;
            {
              const $t1330 = (o === "no_redirects");
              if ($t1330 === true) {
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
                  const $t1331 = march_string_starts_with(o, "methods=");
                  if ($t1331 === true) {
                    if (mg === true) {
                      return { $: "Err", _0: "`methods(...)` is given twice" };
                    } else {
                      {
                        let v;
                        {
                          let $t1333;
                          {
                            const $t1332 = march_string_byte_length(o);
                            $t1333 = (($t1332 - 8) < 4611686018427387904 && ($t1332 - 8) >= -4611686018427387904 ? ($t1332 - 8) : march_int_ovf(($t1332 - 8), 1));
                          }
                          v = march_string_slice(o, 8, $t1333);
                        }
                        {
                          let $t1335;
                          {
                            const $t1334 = march_string_split(v, ",");
                            $t1335 = Authority$bad_method($t1334);
                          }
                          switch ($t1335.$) {
                            case "None": {
                              {
                                const $t1336 = (v === "");
                                if ($t1336 === true) {
                                  return { $: "Err", _0: "`methods(...)` needs at least one method" };
                                } else {
                                  {
                                    let $t1337;
                                    {
                                      const $rc_133 = march_string_split(v, ",");
                                      $t1337 = $rc_133;
                                    }
                                    {
                                      $tco_a0 = rest;
                                      $tco_a1 = nr;
                                      $tco_a2 = true;
                                      $tco_a3 = $t1337;
                                      continue __tco;
                                    }
                                  }
                                }
                              }
                              break;
                            }
                            case "Some": {
                              const $f1339 = $t1335._0;
                              {
                                const m = $f1339;
                                {
                                  let $t1338;
                                  {
                                    const $rc_134 = march_string_concat3("`", m, "` is not an HTTP method a scope can name; use `get`, `head`, `post`, `put`, `patch`, `delete`, `options`");
                                    $t1338 = $rc_134;
                                  }
                                  return { $: "Err", _0: $t1338 };
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
                      const $t1340 = march_string_concat3("unknown option `", o, "`: the options are `no_redirects` and `methods(...)`");
                      return { $: "Err", _0: $t1340 };
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
        const $f1356 = ms._0;
        const $f1357 = ms._1;
        {
          const rest = $f1357;
          {
            const m = $f1356;
            {
              let $t1355;
              {
                const $t1347 = { $: "Nil" };
                {
                  const $t1348 = { $: "Cons", _0: "options", _1: $t1347 };
                  {
                    const $t1349 = { $: "Cons", _0: "delete", _1: $t1348 };
                    {
                      const $t1350 = { $: "Cons", _0: "patch", _1: $t1349 };
                      {
                        const $t1351 = { $: "Cons", _0: "put", _1: $t1350 };
                        {
                          const $t1352 = { $: "Cons", _0: "post", _1: $t1351 };
                          {
                            const $t1353 = { $: "Cons", _0: "head", _1: $t1352 };
                            {
                              const $t1354 = { $: "Cons", _0: "get", _1: $t1353 };
                              {
                                const $rc_135 = Authority$member($t1354, m);
                                $t1355 = $rc_135;
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              if ($t1355 === true) {
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
    const $t1362 = march_string_split(spec, ";");
    switch ($t1362.$) {
      case "Nil": {
        return { $: "Err", _0: "a host scope cannot be empty" };
        break;
      }
      case "Cons": {
        const $f1389 = $t1362._0;
        const $f1390 = $t1362._1;
        {
          const opts = $f1390;
          {
            const p = $f1389;
            {
              let $t1364;
              {
                const $t1363 = (p === "");
                if ($t1363 === true) {
                  switch (opts.$) {
                    case "Nil": {
                      $t1364 = true;
                      break;
                    }
                    default: {
                      $t1364 = false;
                      break;
                    }
                  }
                } else {
                  $t1364 = false;
                }
              }
              if ($t1364 === true) {
                return { $: "Err", _0: "a host scope cannot be empty" };
              } else {
                {
                  let pat_ok;
                  {
                    const $t1365 = (p === "");
                    if ($t1365 === true) {
                      {
                        const $t1366 = {  };
                        pat_ok = { $: "Ok", _0: $t1366 };
                      }
                    } else {
                      {
                        let $t1367;
                        $t1367 = Authority$parse_host_pattern(p);
                        switch ($t1367.$) {
                          case "Ok": {
                            const $f1369 = $t1367._0;
                            {
                              const $t1368 = {  };
                              pat_ok = { $: "Ok", _0: $t1368 };
                            }
                            break;
                          }
                          case "Err": {
                            const $f1370 = $t1367._0;
                            {
                              const e = $f1370;
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
                      const $f1387 = pat_ok._0;
                      {
                        const e = $f1387;
                        return { $: "Err", _0: e };
                      }
                      break;
                    }
                    case "Ok": {
                      const $f1388 = pat_ok._0;
                      {
                        let $t1372;
                        {
                          const $t1371 = { $: "Nil" };
                          {
                            const $rc_136 = Authority$host_options(opts, false, false, $t1371);
                            $t1372 = $rc_136;
                          }
                        }
                        switch ($t1372.$) {
                          case "Err": {
                            const $f1374 = $t1372._0;
                            {
                              const e = $f1374;
                              return { $: "Err", _0: e };
                            }
                            break;
                          }
                          case "Ok": {
                            const $f1375 = $t1372._0;
                            const $f1376 = $f1375._0;
                            const $f1377 = $f1375._1;
                            const $f1378 = $f1375._2;
                            {
                              const ms = $f1378;
                              {
                                const mg = $f1377;
                                {
                                  const nr = $f1376;
                                  {
                                    const $t1373 = { _0: p, _1: nr, _2: mg, _3: ms };
                                    return { $: "Ok", _0: $t1373 };
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
    const $t1395 = Authority$host_decl(o);
    {
      const $t1396 = Authority$host_decl(i);
      {
        const $t1397 = { _0: $t1395, _1: $t1396 };
        const $f1404 = $t1397._0;
        const $f1405 = $t1397._1;
        switch ($f1404.$) {
          case "Ok": {
            const $f1406 = $f1404._0;
            const $f1407 = $f1406._0;
            const $f1408 = $f1406._1;
            const $f1409 = $f1406._2;
            const $f1410 = $f1406._3;
            switch ($f1405.$) {
              case "Ok": {
                const $f1411 = $f1405._0;
                const $f1412 = $f1411._0;
                const $f1413 = $f1411._1;
                const $f1414 = $f1411._2;
                const $f1415 = $f1411._3;
                {
                  const ims = $f1415;
                  {
                    const img = $f1414;
                    {
                      const inr = $f1413;
                      {
                        const i_pre = $f1412;
                        {
                          const oms = $f1410;
                          {
                            const omg = $f1409;
                            {
                              const onr = $f1408;
                              {
                                const o_pre = $f1407;
                                {
                                  let $t1401;
                                  {
                                    let $t1399;
                                    {
                                      const $t1398 = (!onr);
                                      $t1399 = ($t1398 || inr);
                                    }
                                    if ($t1399 === true) {
                                      {
                                        const $t1400 = (!omg);
                                        if ($t1400 === true) {
                                          $t1401 = true;
                                        } else {
                                          if (img === true) {
                                            {
                                              const $rc_137 = Authority$all_member(ims, oms);
                                              $t1401 = $rc_137;
                                            }
                                          } else {
                                            $t1401 = false;
                                          }
                                        }
                                      }
                                    } else {
                                      $t1401 = false;
                                    }
                                  }
                                  if ($t1401 === true) {
                                    {
                                      const $t1402 = (o_pre === "");
                                      if ($t1402 === true) {
                                        return true;
                                      } else {
                                        {
                                          const $t1403 = (i_pre !== "");
                                          if ($t1403 === true) {
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
    const $t1416 = Authority$parse_host_pattern(o);
    {
      const $t1417 = Authority$parse_host_pattern(i);
      {
        const $t1418 = { _0: $t1416, _1: $t1417 };
        const $f1427 = $t1418._0;
        const $f1428 = $t1418._1;
        switch ($f1427.$) {
          case "Ok": {
            const $f1429 = $f1427._0;
            const $f1430 = $f1429._0;
            const $f1431 = $f1429._1;
            const $f1432 = $f1429._2;
            const $f1433 = $f1429._3;
            switch ($f1428.$) {
              case "Ok": {
                const $f1434 = $f1428._0;
                const $f1435 = $f1434._0;
                const $f1436 = $f1434._1;
                const $f1437 = $f1434._2;
                const $f1438 = $f1434._3;
                {
                  const ipath = $f1438;
                  {
                    const iport = $f1437;
                    {
                      const iw = $f1436;
                      {
                        const ih = $f1435;
                        {
                          const opath = $f1433;
                          {
                            const oport = $f1432;
                            {
                              const ow = $f1431;
                              {
                                const oh = $f1430;
                                {
                                  let host_ok;
                                  if (ow === true) {
                                    {
                                      let $t1419;
                                      if (iw === true) {
                                        $t1419 = (ih === oh);
                                      } else {
                                        $t1419 = false;
                                      }
                                      if ($t1419 === true) {
                                        host_ok = true;
                                      } else {
                                        {
                                          let $t1420;
                                          {
                                            const $rc_140 = ("." + oh);
                                            $t1420 = $rc_140;
                                          }
                                          {
                                            const $rc_139 = march_string_ends_with(ih, $t1420);
                                            host_ok = $rc_139;
                                          }
                                        }
                                      }
                                    }
                                  } else {
                                    {
                                      const $t1421 = (!iw);
                                      if ($t1421 === true) {
                                        {
                                          const $rc_141 = (ih === oh);
                                          host_ok = $rc_141;
                                        }
                                      } else {
                                        host_ok = false;
                                      }
                                    }
                                  }
                                  {
                                    let port_ok;
                                    {
                                      const $t1422 = (oport === 0);
                                      {
                                        const $t1423 = (oport === iport);
                                        port_ok = ($t1422 || $t1423);
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
                                          const $f1425 = opath._0;
                                          {
                                            const o_paths = $f1425;
                                            switch (ipath.$) {
                                              case "None": {
                                                path_ok = false;
                                                break;
                                              }
                                              case "Some": {
                                                const $f1424 = ipath._0;
                                                {
                                                  const i_paths = $f1424;
                                                  {
                                                    const $rc_138 = Authority$segs_prefix(o_paths, i_paths);
                                                    path_ok = $rc_138;
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
                                        const $t1426 = (host_ok && port_ok);
                                        return ($t1426 && path_ok);
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
    let $t1441;
    {
      const $t1439 = march_string_byte_length(text);
      {
        const $t1440 = { $: "Nil" };
        $t1441 = Authority$tokenize(text, 0, $t1439, $t1440);
      }
    }
    switch ($t1441.$) {
      case "Err": {
        const $f1461 = $t1441._0;
        {
          const e = $f1461;
          return { $: "Err", _0: e };
        }
        break;
      }
      case "Ok": {
        const $f1462 = $t1441._0;
        {
          const toks = $f1462;
          switch (toks.$) {
            case "Nil": {
              {
                const $t1442 = { $: "Nil" };
                return { $: "Ok", _0: $t1442 };
              }
              break;
            }
            case "Cons": {
              const $f1447 = toks._0;
              const $f1448 = toks._1;
              {
                const $jp_clo1450 = { $: "$Clo_$jp1_Authority_parse$0_Authority_parse", _0: $jp1_Authority_parse$apply$0_Authority_parse, _1: toks };
                if ($f1447 === "(") {
                  {
                    const $jp_clo1452 = { $: "$Clo_$jp2_Authority_parse$1_Authority_parse", _0: $jp2_Authority_parse$apply$1_Authority_parse, _1: $jp_clo1450 };
                    switch ($f1448.$) {
                      case "Cons": {
                        const $f1453 = $f1448._0;
                        const $f1454 = $f1448._1;
                        {
                          const $jp_clo1456 = { $: "$Clo_$jp3_Authority_parse$2_Authority_parse", _0: $jp3_Authority_parse$apply$2_Authority_parse, _1: $jp_clo1452 };
                          if ($f1453 === ")") {
                            switch ($f1454.$) {
                              case "Nil": {
                                {
                                  const $t1443 = { $: "Nil" };
                                  return { $: "Ok", _0: $t1443 };
                                }
                                break;
                              }
                              default: {
                                return $jp3_Authority_parse$apply$2_Authority_parse($jp_clo1456);
                              }
                            }
                          } else {
                            return $jp3_Authority_parse$apply$2_Authority_parse($jp_clo1456);
                          }
                        }
                        break;
                      }
                      default: {
                        return $jp2_Authority_parse$apply$1_Authority_parse($jp_clo1452);
                      }
                    }
                  }
                } else {
                  return $jp1_Authority_parse$apply$0_Authority_parse($jp_clo1450);
                }
              }
              break;
            }
            default: {
              {
                const $t1444 = { $: "Nil" };
                return Authority$parse_entries(toks, $t1444);
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
      const $t1463 = (i >= n);
      if ($t1463 === true) {
        {
          const $t1464 = { $: "Nil" };
          {
            const $t1465 = Authority$rev(acc, $t1464);
            return { $: "Ok", _0: $t1465 };
          }
        }
      } else {
        {
          const c = march_string_slice(s, i, 1);
          {
            let $t1469;
            {
              let $t1468;
              {
                let $t1467;
                {
                  const $t1466 = (c === " ");
                  if ($t1466 === true) {
                    $t1467 = true;
                  } else {
                    $t1467 = (c === "\t");
                  }
                }
                if ($t1467 === true) {
                  $t1468 = true;
                } else {
                  $t1468 = (c === "\n");
                }
              }
              if ($t1468 === true) {
                $t1469 = true;
              } else {
                $t1469 = (c === "\r");
              }
            }
            if ($t1469 === true) {
              {
                const $t1470 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                {
                  $tco_a0 = s;
                  $tco_a1 = $t1470;
                  $tco_a2 = n;
                  $tco_a3 = acc;
                  continue __tco;
                }
              }
            } else {
              {
                let $t1473;
                {
                  let $t1472;
                  {
                    const $t1471 = (c === "(");
                    if ($t1471 === true) {
                      $t1472 = true;
                    } else {
                      $t1472 = (c === ")");
                    }
                  }
                  if ($t1472 === true) {
                    $t1473 = true;
                  } else {
                    $t1473 = (c === ",");
                  }
                }
                if ($t1473 === true) {
                  {
                    const $t1474 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                    {
                      const $t1475 = { $: "Cons", _0: c, _1: acc };
                      {
                        $tco_a0 = s;
                        $tco_a1 = $t1474;
                        $tco_a2 = n;
                        $tco_a3 = $t1475;
                        continue __tco;
                      }
                    }
                  }
                } else {
                  {
                    const $t1476 = (c === "\"");
                    if ($t1476 === true) {
                      {
                        let $t1478;
                        {
                          const $t1477 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                          $t1478 = Authority$read_string(s, $t1477, n, "");
                        }
                        switch ($t1478.$) {
                          case "Err": {
                            const $f1481 = $t1478._0;
                            {
                              const e = $f1481;
                              return { $: "Err", _0: e };
                            }
                            break;
                          }
                          case "Ok": {
                            const $f1482 = $t1478._0;
                            const $f1483 = $f1482._0;
                            const $f1484 = $f1482._1;
                            {
                              const j = $f1484;
                              {
                                const str = $f1483;
                                {
                                  let $t1479;
                                  {
                                    const $rc_142 = ("\"" + str);
                                    $t1479 = $rc_142;
                                  }
                                  {
                                    const $t1480 = { $: "Cons", _0: $t1479, _1: acc };
                                    {
                                      $tco_a0 = s;
                                      $tco_a1 = j;
                                      $tco_a2 = n;
                                      $tco_a3 = $t1480;
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
                        let $t1489;
                        {
                          const $t1494_i110 = (c !== "");
                          if ($t1494_i110 === true) {
                            $t1489 = march_string_contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.", c);
                          } else {
                            $t1489 = false;
                          }
                        }
                        if ($t1489 === true) {
                          {
                            const j = Authority$word_end(s, i, n);
                            {
                              let $t1491;
                              {
                                const $t1490 = ((j - i) < 4611686018427387904 && (j - i) >= -4611686018427387904 ? (j - i) : march_int_ovf((j - i), 1));
                                $t1491 = march_string_slice(s, i, $t1490);
                              }
                              {
                                const $t1492 = { $: "Cons", _0: $t1491, _1: acc };
                                {
                                  $tco_a0 = s;
                                  $tco_a1 = j;
                                  $tco_a2 = n;
                                  $tco_a3 = $t1492;
                                  continue __tco;
                                }
                              }
                            }
                          }
                        } else {
                          {
                            let $t1493;
                            {
                              const $rc_143 = march_string_concat3("unexpected `", c, "`");
                              $t1493 = $rc_143;
                            }
                            return { $: "Err", _0: $t1493 };
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
      let $t1497;
      {
        const $t1495 = (i < n);
        if ($t1495 === true) {
          {
            const $t1496 = march_string_slice(s, i, 1);
            {
              let $rc_144;
              {
                const $t1494_i112 = ($t1496 !== "");
                if ($t1494_i112 === true) {
                  $rc_144 = march_string_contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.", $t1496);
                } else {
                  $rc_144 = false;
                }
              }
              $t1497 = $rc_144;
            }
          }
        } else {
          $t1497 = false;
        }
      }
      if ($t1497 === true) {
        {
          const $t1498 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
          {
            $tco_a0 = s;
            $tco_a1 = $t1498;
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
      const $t1499 = (i >= n);
      if ($t1499 === true) {
        return { $: "Err", _0: "a string is not closed" };
      } else {
        {
          const c = march_string_slice(s, i, 1);
          {
            const $t1500 = (c === "\"");
            if ($t1500 === true) {
              {
                const $t1501 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                {
                  const $t1502 = { _0: acc, _1: $t1501 };
                  return { $: "Ok", _0: $t1502 };
                }
              }
            } else {
              {
                const $t1503 = (c === "\\");
                if ($t1503 === true) {
                  {
                    let $t1505;
                    {
                      const $t1504 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                      $t1505 = ($t1504 >= n);
                    }
                    if ($t1505 === true) {
                      return { $: "Err", _0: "a string is not closed" };
                    } else {
                      {
                        let e;
                        {
                          const $t1506 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                          e = march_string_slice(s, $t1506, 1);
                        }
                        {
                          let d;
                          {
                            const $t1507 = (e === "n");
                            if ($t1507 === true) {
                              d = "\n";
                            } else {
                              {
                                const $t1508 = (e === "t");
                                if ($t1508 === true) {
                                  d = "\t";
                                } else {
                                  {
                                    const $t1509 = (e === "r");
                                    if ($t1509 === true) {
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
                            const $t1510 = ((i + 2) < 4611686018427387904 && (i + 2) >= -4611686018427387904 ? (i + 2) : march_int_ovf((i + 2), 0));
                            {
                              let $t1511;
                              {
                                const $rc_145 = (acc + d);
                                $t1511 = $rc_145;
                              }
                              {
                                $tco_a0 = s;
                                $tco_a1 = $t1510;
                                $tco_a2 = n;
                                $tco_a3 = $t1511;
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
                    const $t1512 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                    {
                      let $t1513;
                      {
                        const $rc_146 = (acc + c);
                        $t1513 = $rc_146;
                      }
                      {
                        $tco_a0 = s;
                        $tco_a1 = $t1512;
                        $tco_a2 = n;
                        $tco_a3 = $t1513;
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
      const $t1517 = Authority$parse_entry(toks);
      switch ($t1517.$) {
        case "Err": {
          const $f1534 = $t1517._0;
          {
            const e = $f1534;
            return { $: "Err", _0: e };
          }
          break;
        }
        case "Ok": {
          const $f1535 = $t1517._0;
          const $f1536 = $f1535._0;
          const $f1537 = $f1535._1;
          {
            const rest = $f1537;
            {
              const scope = $f1536;
              switch (rest.$) {
                case "Nil": {
                  {
                    const $t1518 = { $: "Cons", _0: scope, _1: acc };
                    {
                      const $t1519 = { $: "Nil" };
                      {
                        const $t1520 = Authority$rev_scopes($t1518, $t1519);
                        return { $: "Ok", _0: $t1520 };
                      }
                    }
                  }
                  break;
                }
                case "Cons": {
                  const $f1524 = rest._0;
                  const $f1525 = rest._1;
                  if ($f1524 === ",") {
                    {
                      const more = $f1525;
                      {
                        const $t1521 = { $: "Cons", _0: scope, _1: acc };
                        {
                          $tco_a0 = more;
                          $tco_a1 = $t1521;
                          continue __tco;
                        }
                      }
                    }
                  } else {
                    {
                      const t = $f1524;
                      {
                        let $t1523;
                        {
                          let $t1522;
                          {
                            let $rc_148;
                            {
                              const $t1516_i115 = march_string_starts_with(t, "\"");
                              if ($t1516_i115 === true) {
                                $rc_148 = "a string";
                              } else {
                                $rc_148 = march_string_concat3("`", t, "`");
                              }
                            }
                            $t1522 = $rc_148;
                          }
                          {
                            const $rc_147 = ("expected `,` between capabilities, found " + $t1522);
                            $t1523 = $rc_147;
                          }
                        }
                        return { $: "Err", _0: $t1523 };
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
      const $f1587 = toks._0;
      const $f1588 = toks._1;
      {
        const rest = $f1588;
        {
          const k = $f1587;
          {
            let $t1543;
            {
              let $t1542;
              {
                let $t1597_i9721;
                {
                  let $t1596_i9720;
                  {
                    let $t1595_i9719;
                    {
                      let $t1594_i9718;
                      {
                        const $t1593_i9717 = march_string_starts_with(k, "\"");
                        $t1594_i9718 = (!$t1593_i9717);
                      }
                      if ($t1594_i9718 === true) {
                        $t1595_i9719 = (k !== "(");
                      } else {
                        $t1595_i9719 = false;
                      }
                    }
                    if ($t1595_i9719 === true) {
                      $t1596_i9720 = (k !== ")");
                    } else {
                      $t1596_i9720 = false;
                    }
                  }
                  if ($t1596_i9720 === true) {
                    $t1597_i9721 = (k !== ",");
                  } else {
                    $t1597_i9721 = false;
                  }
                }
                if ($t1597_i9721 === true) {
                  {
                    const $t1598_i9722 = march_string_split(k, ".");
                    {
                      const $rc_152_i9723 = Authority$kind_parts_ok($t1598_i9722);
                      $t1542 = $rc_152_i9723;
                    }
                  }
                } else {
                  $t1542 = false;
                }
              }
              $t1543 = (!$t1542);
            }
            if ($t1543 === true) {
              {
                let $t1545;
                {
                  let $t1544;
                  {
                    let $rc_150;
                    {
                      const $t1516_i117 = march_string_starts_with(k, "\"");
                      if ($t1516_i117 === true) {
                        $rc_150 = "a string";
                      } else {
                        $rc_150 = march_string_concat3("`", k, "`");
                      }
                    }
                    $t1544 = $rc_150;
                  }
                  {
                    const $rc_149 = ("expected a capability such as `IO.Console`, found " + $t1544);
                    $t1545 = $rc_149;
                  }
                }
                return { $: "Err", _0: $t1545 };
              }
            } else {
              switch (rest.$) {
                case "Cons": {
                  const $f1579 = rest._0;
                  const $f1580 = rest._1;
                  if ($f1579 === "(") {
                    {
                      const after = $f1580;
                      switch (after.$) {
                        case "Cons": {
                          const $f1568 = after._0;
                          const $f1569 = after._1;
                          if ($f1568 === ")") {
                            {
                              let $t1546;
                              {
                                const $rc_151 = march_string_concat_n("`", k, "()` names no scope: write `", k, "` for any target");
                                $t1546 = $rc_151;
                              }
                              return { $: "Err", _0: $t1546 };
                            }
                          } else {
                            {
                              let $t1549;
                              {
                                const $t1547 = { $: "Nil" };
                                {
                                  const $t1548 = { $: "Nil" };
                                  $t1549 = Authority$parse_items(after, $t1547, $t1548);
                                }
                              }
                              switch ($t1549.$) {
                                case "Err": {
                                  const $f1555 = $t1549._0;
                                  {
                                    const e = $f1555;
                                    return { $: "Err", _0: e };
                                  }
                                  break;
                                }
                                case "Ok": {
                                  const $f1556 = $t1549._0;
                                  const $f1557 = $f1556._0;
                                  const $f1558 = $f1556._1;
                                  const $f1559 = $f1556._2;
                                  {
                                    const more = $f1559;
                                    {
                                      const opts = $f1558;
                                      {
                                        const strs = $f1557;
                                        {
                                          const $t1550 = Authority$scope_arg(k, strs, opts);
                                          switch ($t1550.$) {
                                            case "Err": {
                                              const $f1553 = $t1550._0;
                                              {
                                                const e = $f1553;
                                                return { $: "Err", _0: e };
                                              }
                                              break;
                                            }
                                            case "Ok": {
                                              const $f1554 = $t1550._0;
                                              {
                                                const arg = $f1554;
                                                {
                                                  const $t1551 = { $: "CapEntry", _0: k, _1: arg };
                                                  {
                                                    const $t1552 = { _0: $t1551, _1: more };
                                                    return { $: "Ok", _0: $t1552 };
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
                            let $t1549;
                            {
                              const $t1547 = { $: "Nil" };
                              {
                                const $t1548 = { $: "Nil" };
                                $t1549 = Authority$parse_items(after, $t1547, $t1548);
                              }
                            }
                            switch ($t1549.$) {
                              case "Err": {
                                const $f1555 = $t1549._0;
                                {
                                  const e = $f1555;
                                  return { $: "Err", _0: e };
                                }
                                break;
                              }
                              case "Ok": {
                                const $f1556 = $t1549._0;
                                const $f1557 = $f1556._0;
                                const $f1558 = $f1556._1;
                                const $f1559 = $f1556._2;
                                {
                                  const more = $f1559;
                                  {
                                    const opts = $f1558;
                                    {
                                      const strs = $f1557;
                                      {
                                        const $t1550 = Authority$scope_arg(k, strs, opts);
                                        switch ($t1550.$) {
                                          case "Err": {
                                            const $f1553 = $t1550._0;
                                            {
                                              const e = $f1553;
                                              return { $: "Err", _0: e };
                                            }
                                            break;
                                          }
                                          case "Ok": {
                                            const $f1554 = $t1550._0;
                                            {
                                              const arg = $f1554;
                                              {
                                                const $t1551 = { $: "CapEntry", _0: k, _1: arg };
                                                {
                                                  const $t1552 = { _0: $t1551, _1: more };
                                                  return { $: "Ok", _0: $t1552 };
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
                      let $t1577;
                      {
                        const $t1576 = { $: "Any" };
                        $t1577 = { $: "CapEntry", _0: k, _1: $t1576 };
                      }
                      {
                        const $t1578 = { _0: $t1577, _1: rest };
                        return { $: "Ok", _0: $t1578 };
                      }
                    }
                  }
                  break;
                }
                default: {
                  {
                    let $t1577;
                    {
                      const $t1576 = { $: "Any" };
                      $t1577 = { $: "CapEntry", _0: k, _1: $t1576 };
                    }
                    {
                      const $t1578 = { _0: $t1577, _1: rest };
                      return { $: "Ok", _0: $t1578 };
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
        const $f1602 = ps._0;
        const $f1603 = ps._1;
        {
          const rest = $f1603;
          {
            const p = $f1602;
            {
              let $t1601;
              {
                const $t1599 = (p !== "");
                if ($t1599 === true) {
                  {
                    const $t1600 = march_string_slice(p, 0, 1);
                    {
                      const $rc_153 = march_string_contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ", $t1600);
                      $t1601 = $rc_153;
                    }
                  }
                } else {
                  $t1601 = false;
                }
              }
              if ($t1601 === true) {
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
        const $f1662 = toks._0;
        const $f1663 = toks._1;
        {
          const rest = $f1663;
          {
            const t = $f1662;
            {
              let item;
              {
                const $t1609 = march_string_starts_with(t, "\"");
                if ($t1609 === true) {
                  {
                    let $t1610;
                    switch (opts.$) {
                      case "Nil": {
                        $t1610 = true;
                        break;
                      }
                      default: {
                        $t1610 = false;
                        break;
                      }
                    }
                    if ($t1610 === true) {
                      {
                        let $t1611;
                        {
                          let $rc_156;
                          {
                            let $t1515_i127;
                            {
                              const $t1514_i126 = march_string_byte_length(t);
                              $t1515_i127 = (($t1514_i126 - 1) < 4611686018427387904 && ($t1514_i126 - 1) >= -4611686018427387904 ? ($t1514_i126 - 1) : march_int_ovf(($t1514_i126 - 1), 1));
                            }
                            $rc_156 = march_string_slice(t, 1, $t1515_i127);
                          }
                          $t1611 = $rc_156;
                        }
                        {
                          const $t1612 = { $: "Cons", _0: $t1611, _1: strs };
                          {
                            const $t1613 = { _0: $t1612, _1: opts, _2: rest };
                            item = { $: "Ok", _0: $t1613 };
                          }
                        }
                      }
                    } else {
                      item = { $: "Err", _0: "a string cannot follow an option in a scope" };
                    }
                  }
                } else {
                  {
                    let $t1614;
                    {
                      const $t1608_i124 = (t !== "");
                      if ($t1608_i124 === true) {
                        $t1614 = Authority$all_chars(t, "abcdefghijklmnopqrstuvwxyz_", 0);
                      } else {
                        $t1614 = false;
                      }
                    }
                    if ($t1614 === true) {
                      {
                        const $t1615 = Authority$parse_option(t, rest);
                        switch ($t1615.$) {
                          case "Err": {
                            const $f1618 = $t1615._0;
                            {
                              const e = $f1618;
                              item = { $: "Err", _0: e };
                            }
                            break;
                          }
                          case "Ok": {
                            const $f1619 = $t1615._0;
                            const $f1620 = $f1619._0;
                            const $f1621 = $f1619._1;
                            {
                              const more = $f1621;
                              {
                                const o = $f1620;
                                {
                                  const $t1616 = { $: "Cons", _0: o, _1: opts };
                                  {
                                    const $t1617 = { _0: strs, _1: $t1616, _2: more };
                                    item = { $: "Ok", _0: $t1617 };
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
                        let $t1627;
                        {
                          let $t1626;
                          {
                            let $rc_158;
                            {
                              const $t1516_i122 = march_string_starts_with(t, "\"");
                              if ($t1516_i122 === true) {
                                $rc_158 = "a string";
                              } else {
                                $rc_158 = march_string_concat3("`", t, "`");
                              }
                            }
                            $t1626 = $rc_158;
                          }
                          {
                            const $rc_157 = ("expected a string or an option in a scope, found " + $t1626);
                            $t1627 = $rc_157;
                          }
                        }
                        item = { $: "Err", _0: $t1627 };
                      }
                    }
                  }
                }
              }
              switch (item.$) {
                case "Err": {
                  const $f1649 = item._0;
                  {
                    const e = $f1649;
                    return { $: "Err", _0: e };
                  }
                  break;
                }
                case "Ok": {
                  const $f1650 = item._0;
                  const $f1651 = $f1650._0;
                  const $f1652 = $f1650._1;
                  const $f1653 = $f1650._2;
                  {
                    const more = $f1653;
                    {
                      const o2 = $f1652;
                      {
                        const s2 = $f1651;
                        switch (more.$) {
                          case "Cons": {
                            const $f1635 = more._0;
                            const $f1636 = more._1;
                            if ($f1635 === ")") {
                              {
                                const after = $f1636;
                                {
                                  const $t1628 = { $: "Nil" };
                                  {
                                    const $t1629 = Authority$rev(s2, $t1628);
                                    {
                                      const $t1630 = { $: "Nil" };
                                      {
                                        const $t1631 = Authority$rev(o2, $t1630);
                                        {
                                          const $t1632 = { _0: $t1629, _1: $t1631, _2: after };
                                          return { $: "Ok", _0: $t1632 };
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            } else if ($f1635 === ",") {
                              {
                                const after = $f1636;
                                {
                                  $tco_a0 = after;
                                  $tco_a1 = s2;
                                  $tco_a2 = o2;
                                  continue __tco;
                                }
                              }
                            } else {
                              {
                                const x = $f1635;
                                {
                                  let $t1634;
                                  {
                                    let $t1633;
                                    {
                                      let $rc_155;
                                      {
                                        const $t1516_i120 = march_string_starts_with(x, "\"");
                                        if ($t1516_i120 === true) {
                                          $rc_155 = "a string";
                                        } else {
                                          $rc_155 = march_string_concat3("`", x, "`");
                                        }
                                      }
                                      $t1633 = $rc_155;
                                    }
                                    {
                                      const $rc_154 = ("expected `,` or `)` in a scope, found " + $t1633);
                                      $t1634 = $rc_154;
                                    }
                                  }
                                  return { $: "Err", _0: $t1634 };
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
      const $f1694 = toks._0;
      const $f1695 = toks._1;
      if ($f1694 === "(") {
        switch ($f1695.$) {
          case "Cons": {
            const $f1702 = $f1695._0;
            const $f1703 = $f1695._1;
            {
              let $jp_clo1709;
              $jp_clo1709 = { $: "$Clo_$jp7_Authority_parse_option$0_Authority_parse_option", _0: $jp7_Authority_parse_option$apply$0_Authority_parse_option, _1: $f1695, _2: name };
              switch ($f1703.$) {
                case "Cons": {
                  const $f1710 = $f1703._0;
                  const $f1711 = $f1703._1;
                  if ($f1710 === ")") {
                    {
                      const rest = $f1711;
                      {
                        const v = $f1702;
                        {
                          const $t1668 = march_string_starts_with(v, "\"");
                          if ($t1668 === true) {
                            {
                              const $t1669 = (name === "methods");
                              if ($t1669 === true) {
                                return { $: "Err", _0: "`methods(...)` takes HTTP method names, not a string" };
                              } else {
                                {
                                  let $t1671;
                                  {
                                    let $t1670;
                                    {
                                      let $rc_160;
                                      {
                                        let $t1515_i134;
                                        {
                                          const $t1514_i133 = march_string_byte_length(v);
                                          $t1515_i134 = (($t1514_i133 - 1) < 4611686018427387904 && ($t1514_i133 - 1) >= -4611686018427387904 ? ($t1514_i133 - 1) : march_int_ovf(($t1514_i133 - 1), 1));
                                        }
                                        $rc_160 = march_string_slice(v, 1, $t1515_i134);
                                      }
                                      $t1670 = $rc_160;
                                    }
                                    {
                                      const $rc_159 = march_string_concat3(name, "=", $t1670);
                                      $t1671 = $rc_159;
                                    }
                                  }
                                  {
                                    const $t1672 = { _0: $t1671, _1: rest };
                                    return { $: "Ok", _0: $t1672 };
                                  }
                                }
                              }
                            }
                          } else {
                            {
                              let $t1674;
                              {
                                const $t1673 = (name === "methods");
                                if ($t1673 === true) {
                                  {
                                    const $t1608_i131 = (v !== "");
                                    if ($t1608_i131 === true) {
                                      $t1674 = Authority$all_chars(v, "abcdefghijklmnopqrstuvwxyz_", 0);
                                    } else {
                                      $t1674 = false;
                                    }
                                  }
                                } else {
                                  $t1674 = false;
                                }
                              }
                              if ($t1674 === true) {
                                {
                                  let $t1675;
                                  {
                                    const $rc_161 = ("methods=" + v);
                                    $t1675 = $rc_161;
                                  }
                                  {
                                    const $t1676 = { _0: $t1675, _1: rest };
                                    return { $: "Ok", _0: $t1676 };
                                  }
                                }
                              } else {
                                {
                                  let $t1677;
                                  {
                                    const $rc_162 = march_string_concat3("`", name, "(...)` takes a quoted string");
                                    $t1677 = $rc_162;
                                  }
                                  return { $: "Err", _0: $t1677 };
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  } else {
                    return $jp7_Authority_parse_option$apply$0_Authority_parse_option($jp_clo1709);
                  }
                  break;
                }
                default: {
                  return $jp7_Authority_parse_option$apply$0_Authority_parse_option($jp_clo1709);
                }
              }
            }
            break;
          }
          default: {
            {
              const more = $f1695;
              {
                const $t1678 = (name === "methods");
                if ($t1678 === true) {
                  {
                    let $t1680;
                    {
                      const $t1679 = { $: "Nil" };
                      $t1680 = Authority$method_words(more, $t1679);
                    }
                    switch ($t1680.$) {
                      case "Err": {
                        const $f1684 = $t1680._0;
                        {
                          const e = $f1684;
                          return { $: "Err", _0: e };
                        }
                        break;
                      }
                      case "Ok": {
                        const $f1685 = $t1680._0;
                        const $f1686 = $f1685._0;
                        const $f1687 = $f1685._1;
                        {
                          const rest = $f1687;
                          {
                            const ms = $f1686;
                            {
                              let $t1682;
                              {
                                let $t1681;
                                {
                                  const $rc_164 = march_string_join(ms, ",");
                                  $t1681 = $rc_164;
                                }
                                {
                                  const $rc_163 = ("methods=" + $t1681);
                                  $t1682 = $rc_163;
                                }
                              }
                              {
                                const $t1683 = { _0: $t1682, _1: rest };
                                return { $: "Ok", _0: $t1683 };
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
                    let $t1692;
                    {
                      const $rc_165 = march_string_concat3("`", name, "(...)` takes one quoted string");
                      $t1692 = $rc_165;
                    }
                    return { $: "Err", _0: $t1692 };
                  }
                }
              }
            }
          }
        }
      } else {
        {
          const $t1693 = { _0: name, _1: toks };
          return { $: "Ok", _0: $t1693 };
        }
      }
      break;
    }
    default: {
      {
        const $t1693 = { _0: name, _1: toks };
        return { $: "Ok", _0: $t1693 };
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
        const $f1725 = toks._0;
        const $f1726 = toks._1;
        {
          let $jp_clo1744;
          $jp_clo1744 = { $: "$Clo_$jp7_Authority_method_words$0_Authority_method_words", _0: $jp7_Authority_method_words$apply$0_Authority_method_words, _1: $f1725, _2: $f1726, _3: acc };
          switch ($f1726.$) {
            case "Cons": {
              const $f1745 = $f1726._0;
              const $f1746 = $f1726._1;
              if ($f1745 === ",") {
                {
                  const rest = $f1746;
                  {
                    const m = $f1725;
                    {
                      let $t1718;
                      {
                        const $t1608_i137 = (m !== "");
                        if ($t1608_i137 === true) {
                          $t1718 = Authority$all_chars(m, "abcdefghijklmnopqrstuvwxyz_", 0);
                        } else {
                          $t1718 = false;
                        }
                      }
                      if ($t1718 === true) {
                        {
                          const $t1719 = { $: "Cons", _0: m, _1: acc };
                          {
                            $tco_a0 = rest;
                            $tco_a1 = $t1719;
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
                return $jp7_Authority_method_words$apply$0_Authority_method_words($jp_clo1744);
              }
              break;
            }
            default: {
              return $jp7_Authority_method_words$apply$0_Authority_method_words($jp_clo1744);
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
    let $t1753;
    {
      let $t1102_i148;
      {
        const $t1101_i147 = (k === "IO.FileRead");
        if ($t1101_i147 === true) {
          $t1102_i148 = true;
        } else {
          $t1102_i148 = (k === "IO.FileWrite");
        }
      }
      if ($t1102_i148 === true) {
        $t1753 = true;
      } else {
        $t1753 = (k === "IO.FileSystem");
      }
    }
    if ($t1753 === true) {
      {
        let $t1755;
        {
          let $t1754;
          {
            let $rc_167;
            switch (opts.$) {
              case "Nil": {
                $rc_167 = true;
                break;
              }
              default: {
                $rc_167 = false;
                break;
              }
            }
            $t1754 = $rc_167;
          }
          $t1755 = (!$t1754);
        }
        if ($t1755 === true) {
          {
            const $t1756 = march_string_concat3("a path scope on `", k, "` takes only paths");
            return { $: "Err", _0: $t1756 };
          }
        } else {
          {
            const $t1757 = Authority$member(strs, "");
            if ($t1757 === true) {
              return { $: "Err", _0: "a path scope cannot be empty" };
            } else {
              {
                let $t1758;
                $t1758 = Authority$first_relative(strs);
                switch ($t1758.$) {
                  case "Some": {
                    const $f1762 = $t1758._0;
                    {
                      const p = $f1762;
                      {
                        let $t1759;
                        {
                          const $rc_166 = march_string_concat_n("the scope `", p, "` on `", k, "` is a relative path; give an absolute path, one starting with `/`");
                          $t1759 = $rc_166;
                        }
                        return { $: "Err", _0: $t1759 };
                      }
                    }
                    break;
                  }
                  case "None": {
                    {
                      let $t1761;
                      {
                        let $t1760;
                        {
                          const l_i9733 = strs;
                          switch (l_i9733.$) {
                            case "Nil": {
                              $t1760 = { $: "Nil" };
                              break;
                            }
                            case "Cons": {
                              const $f2018_i9734 = l_i9733._0;
                              const $f2019_i9735 = l_i9733._1;
                              {
                                const rest_i9736 = $f2019_i9735;
                                {
                                  const x_i9737 = $f2018_i9734;
                                  {
                                    let $t2016_i9739;
                                    {
                                      const $rc_206_i9738 = Authority$normalize(x_i9737);
                                      $t2016_i9739 = $rc_206_i9738;
                                    }
                                    {
                                      const $trmc27_i9740 = { $: "Cons", _0: $t2016_i9739, _1: null };
                                      Authority$map_normalize$dps(rest_i9736, $trmc27_i9740);
                                      $t1760 = $trmc27_i9740;
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
                        $t1761 = { $: "PathsAt", _0: $t1760 };
                      }
                      return { $: "Ok", _0: $t1761 };
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
        const $t1763 = (k === "IO.NetConnect");
        if ($t1763 === true) {
          {
            let spec;
            switch (strs.$) {
              case "Nil": {
                {
                  let $t1764;
                  {
                    const $rc_169 = march_string_join(opts, ";");
                    $t1764 = $rc_169;
                  }
                  {
                    const $rc_168 = (";" + $t1764);
                    spec = $rc_168;
                  }
                }
                break;
              }
              case "Cons": {
                const $f1768 = strs._0;
                const $f1769 = strs._1;
                {
                  const more = $f1769;
                  {
                    const first = $f1768;
                    {
                      let $t1765;
                      {
                        const l_i9724 = more;
                        switch (l_i9724.$) {
                          case "Nil": {
                            $t1765 = { $: "Nil" };
                            break;
                          }
                          case "Cons": {
                            const $f2010_i9726 = l_i9724._0;
                            const $f2011_i9727 = l_i9724._1;
                            {
                              const rest_i9728 = $f2011_i9727;
                              {
                                const x_i9729 = $f2010_i9726;
                                {
                                  let $t2008_i9731;
                                  {
                                    const $rc_204_i9730 = ("name=" + x_i9729);
                                    $t2008_i9731 = $rc_204_i9730;
                                  }
                                  {
                                    const $trmc23_i9732 = { $: "Cons", _0: $t2008_i9731, _1: null };
                                    Authority$prefix_all$dps(rest_i9728, "name=", $trmc23_i9732);
                                    $t1765 = $trmc23_i9732;
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
                        let $t1766;
                        {
                          const $t1992_i142 = { $: "Nil" };
                          {
                            const $t1993_i143 = Authority$rev($t1765, $t1992_i142);
                            $t1766 = Authority$rev($t1993_i143, opts);
                          }
                        }
                        {
                          const $t1767 = { $: "Cons", _0: first, _1: $t1766 };
                          {
                            const $rc_170 = march_string_join($t1767, ";");
                            spec = $rc_170;
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
              const $t1774 = Authority$host_decl(spec);
              switch ($t1774.$) {
                case "Err": {
                  const $f1797 = $t1774._0;
                  {
                    const e = $f1797;
                    return { $: "Err", _0: e };
                  }
                  break;
                }
                case "Ok": {
                  const $f1798 = $t1774._0;
                  const $f1799 = $f1798._0;
                  const $f1800 = $f1798._1;
                  const $f1801 = $f1798._2;
                  const $f1802 = $f1798._3;
                  {
                    const p = $f1799;
                    {
                      const $t1775 = (p === "");
                      if ($t1775 === true) {
                        {
                          const $t1776 = { $: "HostAt", _0: spec, _1: "", _2: false, _3: 0 };
                          return { $: "Ok", _0: $t1776 };
                        }
                      } else {
                        {
                          const $t1777 = Authority$parse_host_pattern(p);
                          switch ($t1777.$) {
                            case "Ok": {
                              const $f1779 = $t1777._0;
                              const $f1780 = $f1779._0;
                              const $f1781 = $f1779._1;
                              const $f1782 = $f1779._2;
                              const $f1783 = $f1779._3;
                              {
                                const port = $f1782;
                                {
                                  const wild = $f1781;
                                  {
                                    const h = $f1780;
                                    {
                                      const $t1778 = { $: "HostAt", _0: spec, _1: h, _2: wild, _3: port };
                                      return { $: "Ok", _0: $t1778 };
                                    }
                                  }
                                }
                              }
                              break;
                            }
                            case "Err": {
                              const $f1796 = $t1777._0;
                              {
                                const e = $f1796;
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
            let $t1815;
            {
              const $t1103_i139 = (k === "IO.Mut");
              if ($t1103_i139 === true) {
                $t1815 = true;
              } else {
                $t1815 = (k === "IO.Registry");
              }
            }
            if ($t1815 === true) {
              {
                let $t1817;
                {
                  const $t1816 = { $: "Nil" };
                  $t1817 = Authority$name_options(opts, $t1816);
                }
                switch ($t1817.$) {
                  case "Err": {
                    const $f1823 = $t1817._0;
                    {
                      const e = $f1823;
                      return { $: "Err", _0: e };
                    }
                    break;
                  }
                  case "Ok": {
                    const $f1824 = $t1817._0;
                    {
                      const prefixes = $f1824;
                      {
                        const $t1818 = Authority$bad_name_text(strs, "a name");
                        switch ($t1818.$) {
                          case "Some": {
                            const $f1822 = $t1818._0;
                            {
                              const e = $f1822;
                              return { $: "Err", _0: e };
                            }
                            break;
                          }
                          case "None": {
                            {
                              const $t1819 = Authority$bad_name_text(prefixes, "a prefix");
                              switch ($t1819.$) {
                                case "Some": {
                                  const $f1821 = $t1819._0;
                                  {
                                    const e = $f1821;
                                    return { $: "Err", _0: e };
                                  }
                                  break;
                                }
                                case "None": {
                                  {
                                    const $t1820 = { $: "Names", _0: strs, _1: prefixes };
                                    return { $: "Ok", _0: $t1820 };
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
                const $t1825 = march_string_concat3("`", k, "` takes no scope");
                return { $: "Err", _0: $t1825 };
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
        const $f1827 = ps._0;
        const $f1828 = ps._1;
        {
          const rest = $f1828;
          {
            const p = $f1827;
            {
              const $t1826 = march_string_starts_with(p, "/");
              if ($t1826 === true) {
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
          const $t1833 = { $: "Nil" };
          {
            const $t1834 = Authority$rev(acc, $t1833);
            return { $: "Ok", _0: $t1834 };
          }
        }
        break;
      }
      case "Cons": {
        const $f1841 = opts._0;
        const $f1842 = opts._1;
        {
          const rest = $f1842;
          {
            const o = $f1841;
            {
              const $t1835 = march_string_starts_with(o, "prefix=");
              if ($t1835 === true) {
                {
                  let $t1838;
                  {
                    let $t1837;
                    {
                      const $t1836 = march_string_byte_length(o);
                      $t1837 = (($t1836 - 7) < 4611686018427387904 && ($t1836 - 7) >= -4611686018427387904 ? ($t1836 - 7) : march_int_ovf(($t1836 - 7), 1));
                    }
                    {
                      const $rc_171 = march_string_slice(o, 7, $t1837);
                      $t1838 = $rc_171;
                    }
                  }
                  {
                    const $t1839 = { $: "Cons", _0: $t1838, _1: acc };
                    {
                      $tco_a0 = rest;
                      $tco_a1 = $t1839;
                      continue __tco;
                    }
                  }
                }
              } else {
                {
                  let $t1840;
                  {
                    const $rc_172 = march_string_concat3("`", o, "` is not an option a name scope takes; it takes names and `prefix(\"...\")`");
                    $t1840 = $rc_172;
                  }
                  return { $: "Err", _0: $t1840 };
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
        const $f1853 = ns._0;
        const $f1854 = ns._1;
        {
          const rest = $f1854;
          {
            const n = $f1853;
            {
              const $t1847 = (n === "");
              if ($t1847 === true) {
                {
                  const $t1848 = (what + " cannot be empty");
                  return { $: "Some", _0: $t1848 };
                }
              } else {
                {
                  let $t1851;
                  {
                    let $t1850;
                    {
                      const $t1849 = march_string_contains(n, ";");
                      if ($t1849 === true) {
                        $t1850 = true;
                      } else {
                        $t1850 = march_string_contains(n, "=");
                      }
                    }
                    if ($t1850 === true) {
                      $t1851 = true;
                    } else {
                      $t1851 = march_string_contains(n, ",");
                    }
                  }
                  if ($t1851 === true) {
                    {
                      const $t1852 = march_string_concat_n(what, " `", n, "` contains `;`, `=` or `,`");
                      return { $: "Some", _0: $t1852 };
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
    case "CapEntry": {
      const $f1868 = s._0;
      const $f1869 = s._1;
      switch ($f1869.$) {
        case "Any": {
          {
            const k = $f1868;
            return k;
          }
          break;
        }
        default: {
          switch ($f1869.$) {
            case "Paths": {
              const $f1920 = $f1869._0;
              {
                const ps = $f1920;
                {
                  const k = $f1868;
                  {
                    let $t1860;
                    {
                      const $t1859 = Authority$quote_all(ps);
                      {
                        const $rc_174 = march_string_join($t1859, ", ");
                        $t1860 = $rc_174;
                      }
                    }
                    {
                      const $rc_173 = march_string_concat_n(k, "(", $t1860, ")");
                      return $rc_173;
                    }
                  }
                }
              }
              break;
            }
            default: {
              switch ($f1869.$) {
                case "PathsAt": {
                  const $f1913 = $f1869._0;
                  {
                    const ps = $f1913;
                    {
                      const k = $f1868;
                      {
                        let $t1862;
                        {
                          const $t1861 = Authority$quote_all(ps);
                          {
                            const $rc_176 = march_string_join($t1861, ", ");
                            $t1862 = $rc_176;
                          }
                        }
                        {
                          const $rc_175 = march_string_concat_n(k, "(", $t1862, ")");
                          return $rc_175;
                        }
                      }
                    }
                  }
                  break;
                }
                default: {
                  switch ($f1869.$) {
                    case "Names": {
                      const $f1901 = $f1869._0;
                      const $f1902 = $f1869._1;
                      {
                        const pre = $f1902;
                        {
                          const ns = $f1901;
                          {
                            const k = $f1868;
                            {
                              let $t1867;
                              {
                                const $t1863 = Authority$quote_all(ns);
                                {
                                  const $t1864 = Authority$quote_all(pre);
                                  {
                                    let $t1865;
                                    {
                                      const l_i9741 = $t1864;
                                      switch (l_i9741.$) {
                                        case "Nil": {
                                          $t1865 = { $: "Nil" };
                                          break;
                                        }
                                        case "Cons": {
                                          const $f1972_i9743 = l_i9741._0;
                                          const $f1973_i9744 = l_i9741._1;
                                          {
                                            const rest_i9745 = $f1973_i9744;
                                            {
                                              const x_i9746 = $f1972_i9743;
                                              {
                                                let $t1970_i9748;
                                                {
                                                  const $rc_202_i9747 = march_string_concat3("prefix(", x_i9746, ")");
                                                  $t1970_i9748 = $rc_202_i9747;
                                                }
                                                {
                                                  const $trmc19_i9749 = { $: "Cons", _0: $t1970_i9748, _1: null };
                                                  Authority$wrap_all$dps(rest_i9745, "prefix(", $trmc19_i9749);
                                                  $t1865 = $trmc19_i9749;
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
                                      let $t1866;
                                      {
                                        const $t1992_i151 = { $: "Nil" };
                                        {
                                          const $t1993_i152 = Authority$rev($t1863, $t1992_i151);
                                          $t1866 = Authority$rev($t1993_i152, $t1865);
                                        }
                                      }
                                      {
                                        const $rc_178 = march_string_join($t1866, ", ");
                                        $t1867 = $rc_178;
                                      }
                                    }
                                  }
                                }
                              }
                              {
                                const $rc_177 = march_string_concat_n(k, "(", $t1867, ")");
                                return $rc_177;
                              }
                            }
                          }
                        }
                      }
                      break;
                    }
                    default: {
                      switch ($f1869.$) {
                        case "Hosts": {
                          const $f1894 = $f1869._0;
                          {
                            const spec = $f1894;
                            {
                              const k = $f1868;
                              {
                                const $rc_179 = Authority$host_scope_text(k, spec);
                                return $rc_179;
                              }
                            }
                          }
                          break;
                        }
                        default: {
                          switch ($f1869.$) {
                            case "HostAt": {
                              const $f1872 = $f1869._0;
                              const $f1873 = $f1869._1;
                              const $f1874 = $f1869._2;
                              const $f1875 = $f1869._3;
                              {
                                const spec = $f1872;
                                {
                                  const k = $f1868;
                                  {
                                    const $rc_180 = Authority$host_scope_text(k, spec);
                                    return $rc_180;
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
    const $t1929 = march_string_split(spec, ";");
    switch ($t1929.$) {
      case "Nil": {
        return k;
        break;
      }
      case "Cons": {
        const $f1936 = $t1929._0;
        const $f1937 = $t1929._1;
        {
          const opts = $f1937;
          {
            const first = $f1936;
            {
              const $t1930 = (first === "");
              {
                let head;
                if ($t1930 === true) {
                  head = { $: "Nil" };
                } else {
                  {
                    let $t1931;
                    {
                      const $rc_183 = Authority$quote(first);
                      $t1931 = $rc_183;
                    }
                    {
                      const $t1932 = { $: "Nil" };
                      head = { $: "Cons", _0: $t1931, _1: $t1932 };
                    }
                  }
                }
                {
                  let $t1935;
                  {
                    const $t1933 = Authority$option_texts(opts);
                    {
                      let $t1934;
                      {
                        const $t1992_i155 = { $: "Nil" };
                        {
                          const $t1993_i156 = Authority$rev(head, $t1992_i155);
                          $t1934 = Authority$rev($t1993_i156, $t1933);
                        }
                      }
                      {
                        const $rc_182 = march_string_join($t1934, ", ");
                        $t1935 = $rc_182;
                      }
                    }
                  }
                  {
                    const $rc_181 = march_string_concat_n(k, "(", $t1935, ")");
                    return $rc_181;
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
      const $f1954 = opts._0;
      const $f1955 = opts._1;
      {
        const rest = $f1955;
        {
          const o = $f1954;
          {
            let t;
            {
              const $t1942 = march_string_index_of(o, "=");
              switch ($t1942.$) {
                case "None": {
                  t = o;
                  break;
                }
                case "Some": {
                  const $f1952 = $t1942._0;
                  {
                    const i = $f1952;
                    {
                      const name = march_string_slice(o, 0, i);
                      {
                        let v;
                        {
                          const $t1943 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                          {
                            let $t1946;
                            {
                              let $t1945;
                              {
                                const $t1944 = march_string_byte_length(o);
                                $t1945 = (($t1944 - i) < 4611686018427387904 && ($t1944 - i) >= -4611686018427387904 ? ($t1944 - i) : march_int_ovf(($t1944 - i), 1));
                              }
                              $t1946 = (($t1945 - 1) < 4611686018427387904 && ($t1945 - 1) >= -4611686018427387904 ? ($t1945 - 1) : march_int_ovf(($t1945 - 1), 1));
                            }
                            {
                              const $rc_190 = march_string_slice(o, $t1943, $t1946);
                              v = $rc_190;
                            }
                          }
                        }
                        {
                          const $t1947 = (name === "name");
                          if ($t1947 === true) {
                            {
                              const $rc_184 = Authority$quote(v);
                              t = $rc_184;
                            }
                          } else {
                            {
                              const $t1948 = (name === "methods");
                              if ($t1948 === true) {
                                {
                                  let $t1950;
                                  {
                                    let $t1949;
                                    {
                                      const $rc_187 = march_string_split(v, ",");
                                      $t1949 = $rc_187;
                                    }
                                    {
                                      const $rc_186 = march_string_join($t1949, ", ");
                                      $t1950 = $rc_186;
                                    }
                                  }
                                  {
                                    const $rc_185 = march_string_concat3("methods(", $t1950, ")");
                                    t = $rc_185;
                                  }
                                }
                              } else {
                                {
                                  let $t1951;
                                  {
                                    const $rc_189 = Authority$quote(v);
                                    $t1951 = $rc_189;
                                  }
                                  {
                                    const $rc_188 = march_string_concat_n(name, "(", $t1951, ")");
                                    t = $rc_188;
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
        const $f1954 = opts._0;
        const $f1955 = opts._1;
        {
          const rest = $f1955;
          {
            const o = $f1954;
            {
              let t;
              {
                const $t1942 = march_string_index_of(o, "=");
                switch ($t1942.$) {
                  case "None": {
                    t = o;
                    break;
                  }
                  case "Some": {
                    const $f1952 = $t1942._0;
                    {
                      const i = $f1952;
                      {
                        const name = march_string_slice(o, 0, i);
                        {
                          let v;
                          {
                            const $t1943 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                            {
                              let $t1946;
                              {
                                let $t1945;
                                {
                                  const $t1944 = march_string_byte_length(o);
                                  $t1945 = (($t1944 - i) < 4611686018427387904 && ($t1944 - i) >= -4611686018427387904 ? ($t1944 - i) : march_int_ovf(($t1944 - i), 1));
                                }
                                $t1946 = (($t1945 - 1) < 4611686018427387904 && ($t1945 - 1) >= -4611686018427387904 ? ($t1945 - 1) : march_int_ovf(($t1945 - 1), 1));
                              }
                              {
                                const $rc_197 = march_string_slice(o, $t1943, $t1946);
                                v = $rc_197;
                              }
                            }
                          }
                          {
                            const $t1947 = (name === "name");
                            if ($t1947 === true) {
                              {
                                const $rc_191 = Authority$quote(v);
                                t = $rc_191;
                              }
                            } else {
                              {
                                const $t1948 = (name === "methods");
                                if ($t1948 === true) {
                                  {
                                    let $t1950;
                                    {
                                      let $t1949;
                                      {
                                        const $rc_194 = march_string_split(v, ",");
                                        $t1949 = $rc_194;
                                      }
                                      {
                                        const $rc_193 = march_string_join($t1949, ", ");
                                        $t1950 = $rc_193;
                                      }
                                    }
                                    {
                                      const $rc_192 = march_string_concat3("methods(", $t1950, ")");
                                      t = $rc_192;
                                    }
                                  }
                                } else {
                                  {
                                    let $t1951;
                                    {
                                      const $rc_196 = Authority$quote(v);
                                      $t1951 = $rc_196;
                                    }
                                    {
                                      const $rc_195 = march_string_concat_n(name, "(", $t1951, ")");
                                      t = $rc_195;
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
    let $t1961;
    {
      const $t1960 = march_string_replace_all(s, "\\", "\\\\");
      {
        const $rc_199 = march_string_replace_all($t1960, "\"", "\\\"");
        $t1961 = $rc_199;
      }
    }
    {
      const $rc_198 = march_string_concat3("\"", $t1961, "\"");
      return $rc_198;
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
      const $f1964 = l._0;
      const $f1965 = l._1;
      {
        const rest = $f1965;
        {
          const x = $f1964;
          {
            let $t1962;
            {
              const $rc_200 = Authority$quote(x);
              $t1962 = $rc_200;
            }
            {
              const $trmc15 = { $: "Cons", _0: $t1962, _1: null };
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
        const $f1964 = l._0;
        const $f1965 = l._1;
        {
          const rest = $f1965;
          {
            const x = $f1964;
            {
              let $t1962;
              {
                const $rc_201 = Authority$quote(x);
                $t1962 = $rc_201;
              }
              {
                const $trmc14 = { $: "Cons", _0: $t1962, _1: null };
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
        const $f1972 = l._0;
        const $f1973 = l._1;
        {
          const rest = $f1973;
          {
            const x = $f1972;
            {
              let $t1970;
              {
                const $rc_203 = march_string_concat3(pre, x, ")");
                $t1970 = $rc_203;
              }
              {
                const $trmc18 = { $: "Cons", _0: $t1970, _1: null };
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
        const $f1979 = l._0;
        const $f1980 = l._1;
        {
          const rest = $f1980;
          {
            const x = $f1979;
            {
              const $t1978 = { $: "Cons", _0: x, _1: acc };
              {
                $tco_a0 = rest;
                $tco_a1 = $t1978;
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
        const $f1986 = l._0;
        const $f1987 = l._1;
        {
          const rest = $f1987;
          {
            const x = $f1986;
            {
              const $t1985 = { $: "Cons", _0: x, _1: acc };
              {
                $tco_a0 = rest;
                $tco_a1 = $t1985;
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
        const $f1995 = l._0;
        const $f1996 = l._1;
        {
          const rest = $f1996;
          {
            const y = $f1995;
            {
              const $t1994 = (y === x);
              if ($t1994 === true) {
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
        const $f2002 = xs._0;
        const $f2003 = xs._1;
        {
          const rest = $f2003;
          {
            const x = $f2002;
            {
              const $t2001 = Authority$member(l, x);
              if ($t2001 === true) {
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
        const $f2010 = l._0;
        const $f2011 = l._1;
        {
          const rest = $f2011;
          {
            const x = $f2010;
            {
              let $t2008;
              {
                const $rc_205 = (pre + x);
                $t2008 = $rc_205;
              }
              {
                const $trmc22 = { $: "Cons", _0: $t2008, _1: null };
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
        const $f2018 = l._0;
        const $f2019 = l._1;
        {
          const rest = $f2019;
          {
            const x = $f2018;
            {
              let $t2016;
              {
                const $rc_207 = Authority$normalize(x);
                $t2016 = $rc_207;
              }
              {
                const $trmc26 = { $: "Cons", _0: $t2016, _1: null };
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
    const $rc_2736 = dom_get_element_by_id$clo._0(dom_get_element_by_id$clo, id);
    return $rc_2736;
  }
}
const Js$Dom$find$clo = { _0: ($_, id) => Js$Dom$find(id) };

function Js$Dom$create(tag) {
  {
    const $rc_2739 = dom_create_element$clo._0(dom_create_element$clo, tag);
    return $rc_2739;
  }
}
const Js$Dom$create$clo = { _0: ($_, tag) => Js$Dom$create(tag) };

function Js$Dom$append(parent, child) {
  {
    const $rc_2742 = dom_append_child$clo._0(dom_append_child$clo, parent, child);
    return $rc_2742;
  }
}
const Js$Dom$append$clo = { _0: ($_, parent, child) => Js$Dom$append(parent, child) };

function Js$Dom$get_attr(el, name) {
  {
    const $rc_2755 = dom_get_attribute$clo._0(dom_get_attribute$clo, el, name);
    return $rc_2755;
  }
}
const Js$Dom$get_attr$clo = { _0: ($_, el, name) => Js$Dom$get_attr(el, name) };

function Js$Dom$set_attr(el, name, val) {
  {
    const $rc_2756 = dom_set_attribute$clo._0(dom_set_attribute$clo, el, name, val);
    return $rc_2756;
  }
}
const Js$Dom$set_attr$clo = { _0: ($_, el, name, val) => Js$Dom$set_attr(el, name, val) };

function Js$Dom$add_class(el, cls) {
  {
    const $rc_2759 = dom_class_add$clo._0(dom_class_add$clo, el, cls);
    return $rc_2759;
  }
}
const Js$Dom$add_class$clo = { _0: ($_, el, cls) => Js$Dom$add_class(el, cls) };

function Js$Dom$set_style(el, prop, val) {
  {
    const $rc_2763 = dom_set_style$clo._0(dom_set_style$clo, el, prop, val);
    return $rc_2763;
  }
}
const Js$Dom$set_style$clo = { _0: ($_, el, prop, val) => Js$Dom$set_style(el, prop, val) };

function Js$Dom$listen(el, event, handler) {
  {
    const $rc_2767 = dom_add_event_listener$clo._0(dom_add_event_listener$clo, el, event, handler);
    return $rc_2767;
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
        const $t49482 = { _0: 0, _1: 1 };
        {
          const $t49483 = { _0: 1, _1: 1 };
          {
            const $t49484 = { _0: 2, _1: 1 };
            {
              const $t49485 = { _0: 3, _1: 1 };
              {
                const $t49486 = { $: "Nil" };
                {
                  const $t49487 = { $: "Cons", _0: $t49485, _1: $t49486 };
                  {
                    const $t49488 = { $: "Cons", _0: $t49484, _1: $t49487 };
                    {
                      const $t49489 = { $: "Cons", _0: $t49483, _1: $t49488 };
                      return { $: "Cons", _0: $t49482, _1: $t49489 };
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
        const $t49490 = { _0: 1, _1: 1 };
        {
          const $t49491 = { _0: 2, _1: 1 };
          {
            const $t49492 = { _0: 1, _1: 2 };
            {
              const $t49493 = { _0: 2, _1: 2 };
              {
                const $t49494 = { $: "Nil" };
                {
                  const $t49495 = { $: "Cons", _0: $t49493, _1: $t49494 };
                  {
                    const $t49496 = { $: "Cons", _0: $t49492, _1: $t49495 };
                    {
                      const $t49497 = { $: "Cons", _0: $t49491, _1: $t49496 };
                      return { $: "Cons", _0: $t49490, _1: $t49497 };
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
        const $t49498 = { _0: 1, _1: 1 };
        {
          const $t49499 = { _0: 0, _1: 2 };
          {
            const $t49500 = { _0: 1, _1: 2 };
            {
              const $t49501 = { _0: 2, _1: 2 };
              {
                const $t49502 = { $: "Nil" };
                {
                  const $t49503 = { $: "Cons", _0: $t49501, _1: $t49502 };
                  {
                    const $t49504 = { $: "Cons", _0: $t49500, _1: $t49503 };
                    {
                      const $t49505 = { $: "Cons", _0: $t49499, _1: $t49504 };
                      return { $: "Cons", _0: $t49498, _1: $t49505 };
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
        const $t49506 = { _0: 1, _1: 1 };
        {
          const $t49507 = { _0: 2, _1: 1 };
          {
            const $t49508 = { _0: 0, _1: 2 };
            {
              const $t49509 = { _0: 1, _1: 2 };
              {
                const $t49510 = { $: "Nil" };
                {
                  const $t49511 = { $: "Cons", _0: $t49509, _1: $t49510 };
                  {
                    const $t49512 = { $: "Cons", _0: $t49508, _1: $t49511 };
                    {
                      const $t49513 = { $: "Cons", _0: $t49507, _1: $t49512 };
                      return { $: "Cons", _0: $t49506, _1: $t49513 };
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
        const $t49514 = { _0: 0, _1: 1 };
        {
          const $t49515 = { _0: 1, _1: 1 };
          {
            const $t49516 = { _0: 1, _1: 2 };
            {
              const $t49517 = { _0: 2, _1: 2 };
              {
                const $t49518 = { $: "Nil" };
                {
                  const $t49519 = { $: "Cons", _0: $t49517, _1: $t49518 };
                  {
                    const $t49520 = { $: "Cons", _0: $t49516, _1: $t49519 };
                    {
                      const $t49521 = { $: "Cons", _0: $t49515, _1: $t49520 };
                      return { $: "Cons", _0: $t49514, _1: $t49521 };
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
        const $t49522 = { _0: 0, _1: 1 };
        {
          const $t49523 = { _0: 0, _1: 2 };
          {
            const $t49524 = { _0: 1, _1: 2 };
            {
              const $t49525 = { _0: 2, _1: 2 };
              {
                const $t49526 = { $: "Nil" };
                {
                  const $t49527 = { $: "Cons", _0: $t49525, _1: $t49526 };
                  {
                    const $t49528 = { $: "Cons", _0: $t49524, _1: $t49527 };
                    {
                      const $t49529 = { $: "Cons", _0: $t49523, _1: $t49528 };
                      return { $: "Cons", _0: $t49522, _1: $t49529 };
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
        const $t49530 = { _0: 2, _1: 1 };
        {
          const $t49531 = { _0: 0, _1: 2 };
          {
            const $t49532 = { _0: 1, _1: 2 };
            {
              const $t49533 = { _0: 2, _1: 2 };
              {
                const $t49534 = { $: "Nil" };
                {
                  const $t49535 = { $: "Cons", _0: $t49533, _1: $t49534 };
                  {
                    const $t49536 = { $: "Cons", _0: $t49532, _1: $t49535 };
                    {
                      const $t49537 = { $: "Cons", _0: $t49531, _1: $t49536 };
                      return { $: "Cons", _0: $t49530, _1: $t49537 };
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
  const $f49547 = c._0;
  const $f49548 = c._1;
  {
    const y = $f49548;
    {
      const x = $f49547;
      {
        const $t49546 = ((3 - y) < 4611686018427387904 && (3 - y) >= -4611686018427387904 ? (3 - y) : march_int_ovf((3 - y), 1));
        return { _0: $t49546, _1: x };
      }
    }
  }
}
const TetrisLogic$rotate_cell$clo = { _0: ($_, c) => TetrisLogic$rotate_cell(c) };

function TetrisLogic$clear_lines(board) {
  {
    let rows;
    {
      const go_i5872 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
      {
        const $t2171_i5874 = { $: "Nil" };
        rows = go$apply$0_List_range(go_i5872, 19, $t2171_i5874);
      }
    }
    {
      let $t49594;
      $t49594 = { $: "$Clo_$lam0_TetrisLogic_clear_lines$0_TetrisLogic_clear_lines", _0: $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines, _1: board };
      {
        const kept_rows = List$filter$List_Int$Fn_Int_Bool(rows, $t49594);
        {
          let cleared;
          {
            let $t49596;
            {  };
            $t49596 = List$length_onto$List_Int$Int(kept_rows, 0);
            cleared = ((20 - $t49596) < 4611686018427387904 && (20 - $t49596) >= -4611686018427387904 ? (20 - $t49596) : march_int_ovf((20 - $t49596), 1));
          }
          {
            const $t49598 = { $: "$Clo_$lam1_TetrisLogic_clear_lines$1_TetrisLogic_clear_lines", _0: $lam1_TetrisLogic_clear_lines$apply$1_TetrisLogic_clear_lines, _1: board };
            {
              let kept_cells;
              {
                const f_i5867 = $t49598;
                {
                  const $t2263_i5868 = { $: "Nil" };
                  kept_cells = List$flat_map_go$List_Int$List_Int$Fn_Int_List_Int($t2263_i5868, kept_rows, f_i5867);
                }
              }
              {
                const $t49600 = ((cleared * 10) < 4611686018427387904 && (cleared * 10) >= -4611686018427387904 ? (cleared * 10) : march_int_ovf((cleared * 10), 2));
                {
                  let blank_cells;
                  {
                    const go_i5864 = { $: "$Clo_go$0_List_repeat_Int_Int", _0: go$apply$0_List_repeat_Int_Int, _1: 0 };
                    {
                      const $t2166_i5865 = { $: "Nil" };
                      blank_cells = go$apply$0_List_repeat_Int_Int(go_i5864, $t49600, $t2166_i5865);
                    }
                  }
                  {
                    let new_board;
                    {
                      let $t49601;
                      {
                        const xs_i14794 = blank_cells;
                        {
                          const ys_i14795 = kept_cells;
                          switch (xs_i14794.$) {
                            case "Nil": {
                              $t49601 = kept_cells;
                              break;
                            }
                            case "Cons": {
                              const $f2242_i14796 = xs_i14794._0;
                              const $f2243_i14797 = xs_i14794._1;
                              {
                                const t_i14798 = $f2243_i14797;
                                {
                                  const h_i14799 = $f2242_i14796;
                                  {
                                    const $trmc34_i14800 = { $: "Cons", _0: h_i14799, _1: null };
                                    List$append$dps$List_Int$List_Int$List_Int(t_i14798, kept_cells, $trmc34_i14800);
                                    $t49601 = $trmc34_i14800;
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
                      new_board = Array$from_list$List_Int($t49601);
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
    const $t49603 = { $: "$Clo_$lam0_int_list_to_string$0_int_list_to_string", _0: $lam0_int_list_to_string$apply$0_int_list_to_string };
    {
      let $t49604;
      {
        const xs_i14801 = xs;
        {
          const f_i14802 = $t49603;
          switch (xs_i14801.$) {
            case "Nil": {
              $t49604 = { $: "Nil" };
              break;
            }
            case "Cons": {
              const $f2250_i14803 = xs_i14801._0;
              const $f2251_i14804 = xs_i14801._1;
              {
                const t_i14805 = $f2251_i14804;
                {
                  const h_i14806 = $f2250_i14803;
                  {
                    let $t2248_i14807;
                    $t2248_i14807 = f_i14802._0(f_i14802, h_i14806);
                    {
                      const $trmc38_i14808 = { $: "Cons", _0: $t2248_i14807, _1: null };
                      List$map$dps$List_Int$Fn_Int_String$List_String(t_i14805, f_i14802, $trmc38_i14808);
                      $t49604 = $trmc38_i14808;
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
        const $rc_2818 = march_string_join($t49604, ",");
        return $rc_2818;
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
    const $t49627 = { $: "I" };
    {
      const $t49628 = { $: "O" };
      {
        const $t49629 = { $: "T" };
        {
          const $t49630 = { $: "S" };
          {
            const $t49631 = { $: "Z" };
            {
              const $t49632 = { $: "J" };
              {
                const $t49633 = { $: "L" };
                {
                  const $t49634 = { $: "Nil" };
                  {
                    const $t49635 = { $: "Cons", _0: $t49633, _1: $t49634 };
                    {
                      const $t49636 = { $: "Cons", _0: $t49632, _1: $t49635 };
                      {
                        const $t49637 = { $: "Cons", _0: $t49631, _1: $t49636 };
                        {
                          const $t49638 = { $: "Cons", _0: $t49630, _1: $t49637 };
                          {
                            const $t49639 = { $: "Cons", _0: $t49629, _1: $t49638 };
                            {
                              const $t49640 = { $: "Cons", _0: $t49628, _1: $t49639 };
                              {
                                const pieces = { $: "Cons", _0: $t49627, _1: $t49640 };
                                {
                                  let rng2;
                                  {
                                    const $t49609_i13534 = ((rng * 16807) < 4611686018427387904 && (rng * 16807) >= -4611686018427387904 ? (rng * 16807) : march_int_ovf((rng * 16807), 2));
                                    rng2 = (2147483647 === 0 ? march_mod_zero() : $t49609_i13534 % 2147483647);
                                  }
                                  {
                                    const idx = (7 === 0 ? march_mod_zero() : rng2 % 7);
                                    {
                                      let result;
                                      {
                                        const $t49641 = List$nth$List_Piece$Int(pieces, idx);
                                        result = { _0: $t49641, _1: rng2 };
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
    const $t49642 = Js$Dom$find("game-state");
    switch ($t49642.$) {
      case "Some": {
        const $f49643 = $t49642._0;
        {
          const el = $f49643;
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
    const $t49644 = Js$Dom$get_attr(el, name);
    switch ($t49644.$) {
      case "Some": {
        const $f49646 = $t49644._0;
        {
          const s = $f49646;
          {
            let $t49645;
            {
              const $rc_2820 = march_string_to_int(s);
              $t49645 = $rc_2820;
            }
            {
              const $rc_2819 = Option$unwrap_or$Option_Int$Int($t49645, _default);
              return $rc_2819;
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
    const $t49647 = Js$Dom$get_attr(el, name);
    switch ($t49647.$) {
      case "Some": {
        const $f49648 = $t49647._0;
        {
          const s = $f49648;
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
        let $t49649;
        {
          const xs_i14809 = cells;
          {
            const f_i14810 = TetrisLogic$rotate_cell$clo;
            switch (xs_i14809.$) {
              case "Nil": {
                $t49649 = { $: "Nil" };
                break;
              }
              case "Cons": {
                const $f2250_i14811 = xs_i14809._0;
                const $f2251_i14812 = xs_i14809._1;
                {
                  const t_i14813 = $f2251_i14812;
                  {
                    const h_i14814 = $f2250_i14811;
                    {
                      let $t2248_i14815;
                      $t2248_i14815 = f_i14810._0(f_i14810, h_i14814);
                      {
                        const $trmc38_i14816 = { $: "Cons", _0: $t2248_i14815, _1: null };
                        List$map$dps$List_T_Int_Int$Fn_T_Int_Int_T_Int_Int$List_T_Int_Int(t_i14813, f_i14810, $trmc38_i14816);
                        $t49649 = $trmc38_i14816;
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
          const $t49650 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
          {
            $tco_a0 = $t49649;
            $tco_a1 = $t49650;
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
        const $t49569_i5884 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: 3, _3: 0 };
        over = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t49569_i5884);
      }
      {
        const $t49653 = next_piece(rng);
        const $f49654 = $t49653._0;
        const $f49655 = $t49653._1;
        {
          const rng2 = $f49655;
          {
            const next2 = $f49654;
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
    const $t49694 = Js$Dom$find(id);
    switch ($t49694.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f49695 = $t49694._0;
        {
          const el = $f49695;
          {
            const el_i13535 = el;
            {
              const text_i13536 = text;
              {
                const $rc_2752_i13537 = dom_set_text$clo._0(dom_set_text$clo, el, text);
                return $rc_2752_i13537;
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
        let $t49696;
        $t49696 = get_str_attr(el, "data-over", "false");
        {
          const $rc_2829 = ($t49696 === "true");
          over = $rc_2829;
        }
      }
      if (over === true) {
        return {  };
      } else if (over === false) {
        {
          let board;
          {
            let $t49697;
            $t49697 = get_str_attr(el, "data-board", "");
            {
              let $t49698;
              {
                let $rc_2828;
                {
                  const $t49605_i5914 = march_string_split($t49697, ",");
                  {
                    const $t49608_i5915 = { $: "$Clo_$lam0_string_to_int_list$0_string_to_int_list", _0: $lam0_string_to_int_list$apply$0_string_to_int_list };
                    $rc_2828 = List$map$List_String$Fn_String_Int($t49605_i5914, $t49608_i5915);
                  }
                }
                $t49698 = $rc_2828;
              }
              board = Array$from_list$List_Int($t49698);
            }
          }
          {
            let piece;
            {
              let $t49699;
              $t49699 = get_str_attr(el, "data-piece", "I");
              {
                let $rc_2827;
                if ($t49699 === "I") {
                  $rc_2827 = { $: "I" };
                } else if ($t49699 === "O") {
                  $rc_2827 = { $: "O" };
                } else if ($t49699 === "T") {
                  $rc_2827 = { $: "T" };
                } else if ($t49699 === "S") {
                  $rc_2827 = { $: "S" };
                } else if ($t49699 === "Z") {
                  $rc_2827 = { $: "Z" };
                } else if ($t49699 === "J") {
                  $rc_2827 = { $: "J" };
                } else {
                  $rc_2827 = { $: "L" };
                }
                piece = $rc_2827;
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
                      let $t49700;
                      $t49700 = get_str_attr(el, "data-next", "O");
                      {
                        let $rc_2826;
                        if ($t49700 === "I") {
                          $rc_2826 = { $: "I" };
                        } else if ($t49700 === "O") {
                          $rc_2826 = { $: "O" };
                        } else if ($t49700 === "T") {
                          $rc_2826 = { $: "T" };
                        } else if ($t49700 === "S") {
                          $rc_2826 = { $: "S" };
                        } else if ($t49700 === "Z") {
                          $rc_2826 = { $: "Z" };
                        } else if ($t49700 === "J") {
                          $rc_2826 = { $: "J" };
                        } else {
                          $rc_2826 = { $: "L" };
                        }
                        next = $rc_2826;
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
                              const $t49701 = f._0(f, board, piece, rot, x, y, next, score, lines, rng);
                              const $f49721 = $t49701._0;
                              const $f49722 = $t49701._1;
                              const $f49723 = $t49701._2;
                              const $f49724 = $t49701._3;
                              const $f49725 = $t49701._4;
                              const $f49726 = $t49701._5;
                              const $f49727 = $t49701._6;
                              const $f49728 = $t49701._7;
                              const $f49729 = $t49701._8;
                              const $f49730 = $t49701._9;
                              {
                                const over2 = $f49730;
                                {
                                  const rng2 = $f49729;
                                  {
                                    const lines2 = $f49728;
                                    {
                                      const score2 = $f49727;
                                      {
                                        const next2 = $f49726;
                                        {
                                          const y2 = $f49725;
                                          {
                                            const x2 = $f49724;
                                            {
                                              const rot2 = $f49723;
                                              {
                                                const piece2 = $f49722;
                                                {
                                                  const board2 = $f49721;
                                                  {
                                                    let $eff;
                                                    {
                                                      let $t49661_i5909;
                                                      {
                                                        const go_i14715 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                                                        {
                                                          const $t2171_i14717 = { $: "Nil" };
                                                          $t49661_i5909 = go$apply$0_List_range(go_i14715, 19, $t2171_i14717);
                                                        }
                                                      }
                                                      {
                                                        const $t49673_i5910 = { $: "$Clo_$lam0_render_board$0_render_board", _0: $lam0_render_board$apply$0_render_board, _1: board2 };
                                                        {
                                                          const f_i14711 = $t49673_i5910;
                                                          {
                                                            const go_i14712 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i14711 };
                                                            $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i14712, $t49661_i5909);
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                  {
                                                    let $eff;
                                                    if (over2 === false) {
                                                      {
                                                        const base_cells_i5904 = TetrisLogic$piece_cells(piece2);
                                                        {
                                                          const rotated_i5905 = rotate_n(base_cells_i5904, rot2);
                                                          {
                                                            const $t49693_i5906 = { $: "$Clo_$lam0_render_falling$0_render_falling", _0: $lam0_render_falling$apply$0_render_falling, _1: x2, _2: y2, _3: piece2 };
                                                            {
                                                              const f_i14708 = $t49693_i5906;
                                                              {
                                                                const go_i14709 = { $: "$Clo_go$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_", _0: go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_, _1: f_i14708 };
                                                                $eff = go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_(go_i14709, rotated_i5905);
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
                                                      let $t49703;
                                                      {
                                                        const $t49702 = String(score2);
                                                        {
                                                          const $rc_2825 = ("Score: " + $t49702);
                                                          $t49703 = $rc_2825;
                                                        }
                                                      }
                                                      $eff = set_text_if_found("score", $t49703);
                                                    }
                                                  }
                                                  {
                                                    let $eff;
                                                    {
                                                      let $t49706;
                                                      {
                                                        let $t49705;
                                                        {
                                                          const $t49704 = TetrisLogic$level_for_lines(lines2);
                                                          $t49705 = String($t49704);
                                                        }
                                                        {
                                                          const $rc_2824 = ("Level: " + $t49705);
                                                          $t49706 = $rc_2824;
                                                        }
                                                      }
                                                      $eff = set_text_if_found("level", $t49706);
                                                    }
                                                  }
                                                  {
                                                    let $eff;
                                                    {
                                                      let $t49708;
                                                      {
                                                        const $t49707 = piece_to_string(next2);
                                                        {
                                                          const $rc_2823 = ("Next: " + $t49707);
                                                          $t49708 = $rc_2823;
                                                        }
                                                      }
                                                      $eff = set_text_if_found("next", $t49708);
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
                                                        let $t49710;
                                                        {
                                                          let $t49709;
                                                          {
                                                            const $t11001_i5897 = { $: "Nil" };
                                                            {
                                                              const $t11003_i5898 = { $: "$Clo_$lam0_Array_to_list$0_Array_to_list_PVec_Int", _0: $lam0_Array_to_list$apply$0_Array_to_list_PVec_Int };
                                                              {
                                                                const rev_i5899 = Array$fold_left$PVec_Int$List_Int$Fn_List_Int_Int_List_Int(board2, $t11001_i5897, $t11003_i5898);
                                                                {
                                                                  const go_i14705 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                                                                  {
                                                                    const $t10587_i14706 = { $: "Nil" };
                                                                    $t49709 = go$apply$0_Array_lst_rev_List_Int(go_i14705, rev_i5899, $t10587_i14706);
                                                                  }
                                                                }
                                                              }
                                                            }
                                                          }
                                                          $t49710 = int_list_to_string($t49709);
                                                        }
                                                        $eff = Js$Dom$set_attr(el, "data-board", $t49710);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        let $t49711;
                                                        {
                                                          const $rc_2822 = piece_to_string(piece2);
                                                          $t49711 = $rc_2822;
                                                        }
                                                        $eff = Js$Dom$set_attr(el, "data-piece", $t49711);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t49712 = String(rot2);
                                                        $eff = Js$Dom$set_attr(el, "data-rot", $t49712);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t49713 = String(x2);
                                                        $eff = Js$Dom$set_attr(el, "data-x", $t49713);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t49714 = String(y2);
                                                        $eff = Js$Dom$set_attr(el, "data-y", $t49714);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        let $t49715;
                                                        {
                                                          const $rc_2821 = piece_to_string(next2);
                                                          $t49715 = $rc_2821;
                                                        }
                                                        $eff = Js$Dom$set_attr(el, "data-next", $t49715);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t49716 = String(score2);
                                                        $eff = Js$Dom$set_attr(el, "data-score", $t49716);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t49717 = String(lines2);
                                                        $eff = Js$Dom$set_attr(el, "data-lines", $t49717);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t49718 = String(rng2);
                                                        $eff = Js$Dom$set_attr(el, "data-rng", $t49718);
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
                                                        let $t49720;
                                                        {
                                                          const $t49719 = ((seq + 1) < 4611686018427387904 && (seq + 1) >= -4611686018427387904 ? (seq + 1) : march_int_ovf((seq + 1), 0));
                                                          $t49720 = String($t49719);
                                                        }
                                                        return Js$Dom$set_attr(el, "data-seq", $t49720);
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
    const $t49767 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t49767, rot);
      {
        let locked;
        {
          let $t49768;
          switch (piece.$) {
            case "I": {
              $t49768 = 1;
              break;
            }
            case "O": {
              $t49768 = 2;
              break;
            }
            case "T": {
              $t49768 = 3;
              break;
            }
            case "S": {
              $t49768 = 4;
              break;
            }
            case "Z": {
              $t49768 = 5;
              break;
            }
            case "J": {
              $t49768 = 6;
              break;
            }
            case "L": {
              $t49768 = 7;
              break;
            }
            default: {
              throw march_panic_error("panic: ", "non-exhaustive pattern match");
              break;
            }
          }
          {
            const $t49579_i5922 = { $: "$Clo_$lam0_TetrisLogic_lock_piece$0_TetrisLogic_lock_piece", _0: $lam0_TetrisLogic_lock_piece$apply$0_TetrisLogic_lock_piece, _1: $t49768, _2: x, _3: y };
            locked = List$fold_left$List_T_Int_Int$PVec_Int$Fn_PVec_Int_T_Int_Int_PVec_Int(cells, board, $t49579_i5922);
          }
        }
        {
          const $t49769 = TetrisLogic$clear_lines(locked);
          const $f49803 = $t49769._0;
          const $f49804 = $t49769._1;
          {
            const n = $f49804;
            {
              const cleared_board = $f49803;
              {
                let new_score;
                {
                  let $t49770;
                  if (n === 1) {
                    $t49770 = 100;
                  } else if (n === 2) {
                    $t49770 = 300;
                  } else if (n === 3) {
                    $t49770 = 500;
                  } else if (n === 4) {
                    $t49770 = 800;
                  } else {
                    $t49770 = 0;
                  }
                  new_score = ((score + $t49770) < 4611686018427387904 && (score + $t49770) >= -4611686018427387904 ? (score + $t49770) : march_int_ovf((score + $t49770), 0));
                }
                {
                  const new_lines = ((lines + n) < 4611686018427387904 && (lines + n) >= -4611686018427387904 ? (lines + n) : march_int_ovf((lines + n), 0));
                  {
                    let $t49771;
                    $t49771 = spawn_piece(next, cleared_board, rng);
                    const $f49772 = $t49771._0;
                    const $f49773 = $t49771._1;
                    const $f49774 = $t49771._2;
                    const $f49775 = $t49771._3;
                    const $f49776 = $t49771._4;
                    const $f49777 = $t49771._5;
                    const $f49778 = $t49771._6;
                    {
                      const over = $f49778;
                      {
                        const rng2 = $f49777;
                        {
                          const next2 = $f49776;
                          {
                            const y2 = $f49775;
                            {
                              const x2 = $f49774;
                              {
                                const rot2 = $f49773;
                                {
                                  const piece2 = $f49772;
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
    let $t49810;
    {
      const $t49809 = state_el();
      $t49810 = get_str_attr($t49809, "data-paused", "false");
    }
    {
      const $rc_2830 = ($t49810 === "true");
      return $rc_2830;
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
        let $t49811;
        $t49811 = get_str_attr(el, "data-over", "false");
        {
          const $rc_2831 = ($t49811 === "true");
          over = $rc_2831;
        }
      }
      if (over === true) {
        return {  };
      } else if (over === false) {
        {
          let $t49813;
          {
            const $t49812 = is_paused();
            $t49813 = (!$t49812);
          }
          return set_paused(el, $t49813);
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
      let $t49840;
      {
        const $t49839 = ((cur_y + 1) < 4611686018427387904 && (cur_y + 1) >= -4611686018427387904 ? (cur_y + 1) : march_int_ovf((cur_y + 1), 0));
        {
          const $t49569_i5930 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: x, _3: $t49839 };
          $t49840 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t49569_i5930);
        }
      }
      if ($t49840 === true) {
        return cur_y;
      } else if ($t49840 === false) {
        {
          const $t49841 = ((cur_y + 1) < 4611686018427387904 && (cur_y + 1) >= -4611686018427387904 ? (cur_y + 1) : march_int_ovf((cur_y + 1), 0));
          {
            $tco_a0 = board;
            $tco_a1 = cells;
            $tco_a2 = x;
            $tco_a3 = $t49841;
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
        let $t49545_i5949;
        {
          const go_i14736 = { $: "$Clo_go$0_List_repeat_Int_Int", _0: go$apply$0_List_repeat_Int_Int, _1: 0 };
          {
            const $t2166_i14737 = { $: "Nil" };
            $t49545_i5949 = go$apply$0_List_repeat_Int_Int(go_i14736, 200, $t2166_i14737);
          }
        }
        board = Array$from_list$List_Int($t49545_i5949);
      }
      {
        let rng0;
        {
          let raw_i13543;
          {
            let $t49613_i13542;
            {
              let $t49612_i13541;
              {
                let $t49611_i13540;
                {
                  let $t49610_i13539;
                  {
                    const $t17657_i14825 = Authority$check("IO.Clock", "");
                    switch ($t17657_i14825.$) {
                      case "Ok": {
                        const $f17660_i14826 = $t17657_i14825._0;
                        {
                          let $t17659_i14828;
                          {
                            const $t17658_i14827 = {  };
                            $t17659_i14828 = march_unix_time();
                          }
                          $t49610_i13539 = { $: "Ok", _0: $t17659_i14828 };
                        }
                        break;
                      }
                      case "Err": {
                        const $f17661_i14829 = $t17657_i14825._0;
                        {
                          const $letq_err_i14830 = $f17661_i14829;
                          $t49610_i13539 = { $: "Err", _0: $letq_err_i14830 };
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
                    const r_i14817 = $t49610_i13539;
                    switch (r_i14817.$) {
                      case "Ok": {
                        const $f803_i14818 = r_i14817._0;
                        {
                          const v_i14819 = $f803_i14818;
                          $t49611_i13540 = v_i14819;
                        }
                        break;
                      }
                      case "Err": {
                        const $f804_i14820 = r_i14817._0;
                        {
                          const e_i14821 = $f804_i14820;
                          march_panic_site("stdlib/authority.march", 97, 14, 58);
                          {
                            let $t802_i14824;
                            {
                              const $t801_i14822 = Authority$describe(e_i14821);
                              {
                                const $rc_3027_i14823 = ("capability refused: " + $t801_i14822);
                                $t802_i14824 = $rc_3027_i14823;
                              }
                            }
                            throw march_panic_error("panic: ", $t802_i14824);
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
                $t49612_i13541 = ($t49611_i13540 * 1000000.0);
              }
              $t49613_i13542 = march_float_to_int($t49612_i13541);
            }
            raw_i13543 = march_int_mod($t49613_i13542, 2147483646);
          }
          {
            const $t49614_i13544 = (raw_i13543 <= 0);
            if ($t49614_i13544 === true) {
              rng0 = ((raw_i13543 + 2147483646) < 4611686018427387904 && (raw_i13543 + 2147483646) >= -4611686018427387904 ? (raw_i13543 + 2147483646) : march_int_ovf((raw_i13543 + 2147483646), 0));
            } else if ($t49614_i13544 === false) {
              rng0 = raw_i13543;
            } else {
              throw march_panic_error("panic: ", "non-exhaustive pattern match");
            }
          }
        }
        {
          const $t49845 = next_piece(rng0);
          const $f49891 = $t49845._0;
          const $f49892 = $t49845._1;
          {
            const rng1 = $f49892;
            {
              const first = $f49891;
              {
                let $t49846;
                $t49846 = spawn_piece(first, board, rng1);
                const $f49860 = $t49846._0;
                const $f49861 = $t49846._1;
                const $f49862 = $t49846._2;
                const $f49863 = $t49846._3;
                const $f49864 = $t49846._4;
                const $f49865 = $t49846._5;
                const $f49866 = $t49846._6;
                {
                  const rng2 = $f49865;
                  {
                    const next = $f49864;
                    {
                      const y = $f49863;
                      {
                        const x = $f49862;
                        {
                          const rot = $f49861;
                          {
                            const piece = $f49860;
                            {
                              let $eff;
                              {
                                let $t49661_i5944;
                                {
                                  const go_i14731 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                                  {
                                    const $t2171_i14733 = { $: "Nil" };
                                    $t49661_i5944 = go$apply$0_List_range(go_i14731, 19, $t2171_i14733);
                                  }
                                }
                                {
                                  const $t49673_i5945 = { $: "$Clo_$lam0_render_board$0_render_board", _0: $lam0_render_board$apply$0_render_board, _1: board };
                                  {
                                    const f_i14727 = $t49673_i5945;
                                    {
                                      const go_i14728 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i14727 };
                                      $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i14728, $t49661_i5944);
                                    }
                                  }
                                }
                              }
                            }
                            {
                              let $eff;
                              {
                                const base_cells_i5939 = TetrisLogic$piece_cells(piece);
                                {
                                  const rotated_i5940 = rotate_n(base_cells_i5939, rot);
                                  {
                                    const $t49693_i5941 = { $: "$Clo_$lam0_render_falling$0_render_falling", _0: $lam0_render_falling$apply$0_render_falling, _1: x, _2: y, _3: piece };
                                    {
                                      const f_i14724 = $t49693_i5941;
                                      {
                                        const go_i14725 = { $: "$Clo_go$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_", _0: go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_, _1: f_i14724 };
                                        $eff = go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_(go_i14725, rotated_i5940);
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
                                let $t49848;
                                {
                                  const $t49847 = piece_to_string(next);
                                  {
                                    const $rc_2834 = ("Next: " + $t49847);
                                    $t49848 = $rc_2834;
                                  }
                                }
                                $eff = set_text_if_found("next", $t49848);
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
                                let $t49850;
                                {
                                  let $t49849;
                                  {
                                    const $t11001_i5932 = { $: "Nil" };
                                    {
                                      const $t11003_i5933 = { $: "$Clo_$lam0_Array_to_list$0_Array_to_list_PVec_Int", _0: $lam0_Array_to_list$apply$0_Array_to_list_PVec_Int };
                                      {
                                        const rev_i5934 = Array$fold_left$PVec_Int$List_Int$Fn_List_Int_Int_List_Int(board, $t11001_i5932, $t11003_i5933);
                                        {
                                          const go_i14721 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                                          {
                                            const $t10587_i14722 = { $: "Nil" };
                                            $t49849 = go$apply$0_Array_lst_rev_List_Int(go_i14721, rev_i5934, $t10587_i14722);
                                          }
                                        }
                                      }
                                    }
                                  }
                                  $t49850 = int_list_to_string($t49849);
                                }
                                $eff = Js$Dom$set_attr(el, "data-board", $t49850);
                              }
                            }
                            {
                              let $eff;
                              {
                                let $t49851;
                                {
                                  const $rc_2833 = piece_to_string(piece);
                                  $t49851 = $rc_2833;
                                }
                                $eff = Js$Dom$set_attr(el, "data-piece", $t49851);
                              }
                            }
                            {
                              let $eff;
                              {
                                const $t49852 = String(rot);
                                $eff = Js$Dom$set_attr(el, "data-rot", $t49852);
                              }
                            }
                            {
                              let $eff;
                              {
                                const $t49853 = String(x);
                                $eff = Js$Dom$set_attr(el, "data-x", $t49853);
                              }
                            }
                            {
                              let $eff;
                              {
                                const $t49854 = String(y);
                                $eff = Js$Dom$set_attr(el, "data-y", $t49854);
                              }
                            }
                            {
                              let $eff;
                              {
                                let $t49855;
                                {
                                  const $rc_2832 = piece_to_string(next);
                                  $t49855 = $rc_2832;
                                }
                                $eff = Js$Dom$set_attr(el, "data-next", $t49855);
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
                                const $t49856 = String(rng2);
                                $eff = Js$Dom$set_attr(el, "data-rng", $t49856);
                              }
                            }
                            {
                              let $eff;
                              $eff = Js$Dom$set_attr(el, "data-over", "false");
                            }
                            {
                              let $t49859;
                              {
                                let $t49858;
                                {
                                  let $t49857;
                                  $t49857 = get_int_attr(el, "data-seq", 0);
                                  $t49858 = (($t49857 + 1) < 4611686018427387904 && ($t49857 + 1) >= -4611686018427387904 ? ($t49857 + 1) : march_int_ovf(($t49857 + 1), 0));
                                }
                                $t49859 = String($t49858);
                              }
                              return Js$Dom$set_attr(el, "data-seq", $t49859);
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
    const $t49897 = Js$Dom$find("restore-request");
    switch ($t49897.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f49913 = $t49897._0;
        {
          const req = $f49913;
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
                                  let $t49898;
                                  $t49898 = get_str_attr(req, "data-over", "false");
                                  {
                                    const $rc_2840 = ($t49898 === "true");
                                    over = $rc_2840;
                                  }
                                }
                                {
                                  let paused;
                                  {
                                    const $t49899 = get_str_attr(req, "data-paused", "false");
                                    {
                                      const $rc_2839 = ($t49899 === "true");
                                      paused = $rc_2839;
                                    }
                                  }
                                  {
                                    let board;
                                    {
                                      let $t49900;
                                      {
                                        const $t49605_i5964 = march_string_split(board_s, ",");
                                        {
                                          const $t49608_i5965 = { $: "$Clo_$lam0_string_to_int_list$0_string_to_int_list", _0: $lam0_string_to_int_list$apply$0_string_to_int_list };
                                          $t49900 = List$map$List_String$Fn_String_Int($t49605_i5964, $t49608_i5965);
                                        }
                                      }
                                      board = Array$from_list$List_Int($t49900);
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
                                            let $t49661_i5959;
                                            {
                                              const go_i14746 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                                              {
                                                const $t2171_i14748 = { $: "Nil" };
                                                $t49661_i5959 = go$apply$0_List_range(go_i14746, 19, $t2171_i14748);
                                              }
                                            }
                                            {
                                              const $t49673_i5960 = { $: "$Clo_$lam0_render_board$0_render_board", _0: $lam0_render_board$apply$0_render_board, _1: board };
                                              {
                                                const f_i14742 = $t49673_i5960;
                                                {
                                                  const go_i14743 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i14742 };
                                                  $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i14743, $t49661_i5959);
                                                }
                                              }
                                            }
                                          }
                                        }
                                        {
                                          let $eff;
                                          if (over === false) {
                                            {
                                              const base_cells_i5954 = TetrisLogic$piece_cells(piece);
                                              {
                                                const rotated_i5955 = rotate_n(base_cells_i5954, rot);
                                                {
                                                  const $t49693_i5956 = { $: "$Clo_$lam0_render_falling$0_render_falling", _0: $lam0_render_falling$apply$0_render_falling, _1: x, _2: y, _3: piece };
                                                  {
                                                    const f_i14739 = $t49693_i5956;
                                                    {
                                                      const go_i14740 = { $: "$Clo_go$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_", _0: go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_, _1: f_i14739 };
                                                      $eff = go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_(go_i14740, rotated_i5955);
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
                                            let $t49902;
                                            {
                                              const $t49901 = String(score);
                                              {
                                                const $rc_2838 = ("Score: " + $t49901);
                                                $t49902 = $rc_2838;
                                              }
                                            }
                                            $eff = set_text_if_found("score", $t49902);
                                          }
                                        }
                                        {
                                          let $eff;
                                          {
                                            let $t49905;
                                            {
                                              let $t49904;
                                              {
                                                const $t49903 = TetrisLogic$level_for_lines(lines);
                                                $t49904 = String($t49903);
                                              }
                                              {
                                                const $rc_2837 = ("Level: " + $t49904);
                                                $t49905 = $rc_2837;
                                              }
                                            }
                                            $eff = set_text_if_found("level", $t49905);
                                          }
                                        }
                                        {
                                          let $eff;
                                          {
                                            let $t49907;
                                            {
                                              let $t49906;
                                              {
                                                const $rc_2836 = piece_to_string(next);
                                                $t49906 = $rc_2836;
                                              }
                                              {
                                                const $rc_2835 = ("Next: " + $t49906);
                                                $t49907 = $rc_2835;
                                              }
                                            }
                                            $eff = set_text_if_found("next", $t49907);
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
                                              const $t49908 = String(rot);
                                              $eff = Js$Dom$set_attr(el, "data-rot", $t49908);
                                            }
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t49909 = String(x);
                                              $eff = Js$Dom$set_attr(el, "data-x", $t49909);
                                            }
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t49910 = String(y);
                                              $eff = Js$Dom$set_attr(el, "data-y", $t49910);
                                            }
                                          }
                                          {
                                            let $eff;
                                            $eff = Js$Dom$set_attr(el, "data-next", next_s);
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t49911 = String(score);
                                              $eff = Js$Dom$set_attr(el, "data-score", $t49911);
                                            }
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t49912 = String(lines);
                                              $eff = Js$Dom$set_attr(el, "data-lines", $t49912);
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
      const ev_i13547 = ev;
      {
        const $rc_2771_i13548 = dom_event_key$clo._0(dom_event_key$clo, ev);
        key = $rc_2771_i13548;
      }
    }
    {
      let $eff;
      {
        let $t49925;
        if (key === "ArrowLeft") {
          $t49925 = true;
        } else if (key === "ArrowRight") {
          $t49925 = true;
        } else if (key === "ArrowDown") {
          $t49925 = true;
        } else if (key === "ArrowUp") {
          $t49925 = true;
        } else if (key === " ") {
          $t49925 = true;
        } else {
          $t49925 = false;
        }
        if ($t49925 === true) {
          {
            const ev_i13545 = ev;
            {
              const $rc_2772_i13546 = dom_prevent_default$clo._0(dom_prevent_default$clo, ev);
              $eff = $rc_2772_i13546;
            }
          }
        } else if ($t49925 === false) {
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
          const $t49926 = is_paused();
          if ($t49926 === true) {
            return {  };
          } else if ($t49926 === false) {
            if (k === "ArrowLeft") {
              {
                const $t49927 = march_int_ovf(-(1), 3);
                {
                  const $t49833_i5976 = { $: "$Clo_$lam0_try_move$0_try_move", _0: $lam0_try_move$apply$0_try_move, _1: $t49927, _2: 0 };
                  return with_state($t49833_i5976);
                }
              }
            } else if (k === "ArrowRight") {
              {
                const $t49833_i5979 = { $: "$Clo_$lam0_try_move$0_try_move", _0: $lam0_try_move$apply$0_try_move, _1: 1, _2: 0 };
                return with_state($t49833_i5979);
              }
            } else if (k === "ArrowDown") {
              {
                const $t49833_i5982 = { $: "$Clo_$lam0_try_move$0_try_move", _0: $lam0_try_move$apply$0_try_move, _1: 0, _2: 1 };
                return with_state($t49833_i5982);
              }
            } else if (k === "ArrowUp") {
              {
                const $t49838_i5983 = { $: "$Clo_$lam0_try_rotate$0_try_rotate", _0: $lam0_try_rotate$apply$0_try_rotate };
                return with_state($t49838_i5983);
              }
            } else if (k === " ") {
              {
                const $t49844_i5984 = { $: "$Clo_$lam0_hard_drop$0_hard_drop", _0: $lam0_hard_drop$apply$0_hard_drop };
                return with_state($t49844_i5984);
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
    const $t49946 = Js$Dom$find("board");
    switch ($t49946.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f49954 = $t49946._0;
        {
          const board_el = $f49954;
          {
            let $eff;
            {
              let $t49915_i5993;
              {
                const go_i14760 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                {
                  const $t2171_i14762 = { $: "Nil" };
                  $t49915_i5993 = go$apply$0_List_range(go_i14760, 19, $t2171_i14762);
                }
              }
              {
                const $t49924_i5994 = { $: "$Clo_$lam0_build_board_dom$0_build_board_dom", _0: $lam0_build_board_dom$apply$0_build_board_dom, _1: board_el };
                {
                  const f_i14756 = $t49924_i5994;
                  {
                    const go_i14757 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i14756 };
                    $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i14757, $t49915_i5993);
                  }
                }
              }
            }
          }
          restart();
          {
            let $eff;
            {
              const $t49947 = dom_body();
              {
                const $t49949 = { $: "$Clo_$lam0_main$0_main", _0: $lam0_main$apply$0_main };
                $eff = Js$Dom$listen($t49947, "keydown", $t49949);
              }
            }
          }
          {
            let $eff;
            {
              let level_i5988;
              {
                let $t49822_i5987;
                {
                  const $t49821_i5986 = state_el();
                  $t49822_i5987 = get_int_attr($t49821_i5986, "data-lines", 0);
                }
                level_i5988 = TetrisLogic$level_for_lines($t49822_i5987);
              }
              {
                let $t49823_i5989;
                {
                  let $t49539_i14753;
                  {
                    const $t49538_i14752 = ((level_i5988 * 40) < 4611686018427387904 && (level_i5988 * 40) >= -4611686018427387904 ? (level_i5988 * 40) : march_int_ovf((level_i5988 * 40), 2));
                    $t49539_i14753 = ((500 - $t49538_i14752) < 4611686018427387904 && (500 - $t49538_i14752) >= -4611686018427387904 ? (500 - $t49538_i14752) : march_int_ovf((500 - $t49538_i14752), 1));
                  }
                  {
                    const $t3792_i5847_i14754 = ($t49539_i14753 > 100);
                    if ($t3792_i5847_i14754 === true) {
                      $t49823_i5989 = $t49539_i14753;
                    } else {
                      $t49823_i5989 = 100;
                    }
                  }
                }
                {
                  const $t49825_i5990 = { $: "$Clo_$lam0_schedule_tick$0_schedule_tick", _0: $lam0_schedule_tick$apply$0_schedule_tick };
                  $eff = Js$Dom$set_timeout($t49823_i5989, $t49825_i5990);
                }
              }
            }
          }
          {
            const $t49950 = Js$Dom$find("restore-trigger");
            switch ($t49950.$) {
              case "None": {
                return {  };
                break;
              }
              case "Some": {
                const $f49953 = $t49950._0;
                {
                  const trigger = $f49953;
                  {
                    const $t49952 = { $: "$Clo_$lam1_main$1_main", _0: $lam1_main$apply$1_main };
                    return Js$Dom$listen(trigger, "click", $t49952);
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
        const $f2417 = xs._0;
        const $f2418 = xs._1;
        {
          const t = $f2418;
          {
            let h;
            h = $f2417;
            {
              let $t2416;
              $t2416 = pred._0(pred, h);
              if ($t2416 === true) {
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
        const $f2280 = xs._0;
        const $f2281 = xs._1;
        {
          const t = $f2281;
          {
            const h = $f2280;
            {
              let $t2278;
              $t2278 = pred._0(pred, h);
              if ($t2278 === true) {
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
      const $f2109 = opt._0;
      {
        let x;
        x = $f2109;
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
      const go_i6311 = { $: "$Clo_go$0_Array_lst_len_List_Int", _0: go$apply$0_Array_lst_len_List_Int };
      n = go$apply$0_Array_lst_len_List_Int(go_i6311, xs, 0);
    }
    {
      const $t11106 = (n === 0);
      if ($t11106 === true) {
        {
          const $t10793_i6308 = { $: "TrieEmpty" };
          {
            const $t10794_i6309 = { $: "Nil" };
            return { $: "PVec", _0: 0, _1: 0, _2: $t10793_i6308, _3: $t10794_i6309 };
          }
        }
      } else {
        {
          let tail_len;
          {
            let $t11109;
            {
              let $t11108;
              {
                const $t11107 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                $t11108 = (32 === 0 ? march_div_zero() : ($t11107 - $t11107 % 32) / 32);
              }
              $t11109 = ((32 * $t11108) < 4611686018427387904 && (32 * $t11108) >= -4611686018427387904 ? (32 * $t11108) : march_int_ovf((32 * $t11108), 2));
            }
            tail_len = ((n - $t11109) < 4611686018427387904 && (n - $t11109) >= -4611686018427387904 ? (n - $t11109) : march_int_ovf((n - $t11109), 1));
          }
          {
            let $p11131;
            {
              const $t11110 = ((n - tail_len) < 4611686018427387904 && (n - tail_len) >= -4611686018427387904 ? (n - tail_len) : march_int_ovf((n - tail_len), 1));
              {
                const go_i6306 = { $: "$Clo_go$0_Array_lst_split_List_Int_Int", _0: go$apply$0_Array_lst_split_List_Int_Int };
                {
                  const $t11020_i6307 = { $: "Nil" };
                  $p11131 = go$apply$0_Array_lst_split_List_Int_Int(go_i6306, xs, $t11110, $t11020_i6307);
                }
              }
            }
            {
              const front = $p11131._0;
              {
                const tail = $p11131._1;
                {
                  const $t11111 = (n === tail_len);
                  if ($t11111 === true) {
                    {
                      const $t11112 = { $: "TrieEmpty" };
                      {
                        const $rc_3025 = { $: "PVec", _0: n, _1: 0, _2: $t11112, _3: tail };
                        return $rc_3025;
                      }
                    }
                  } else {
                    {
                      const up = { $: "$Clo_up$0_Array_from_list_List_Int", _0: up$apply$0_Array_from_list_List_Int };
                      {
                        let $p11130;
                        {
                          const $t11128 = { $: "$Clo_$lam0_Array_from_list$2_Array_from_list_List_Int", _0: $lam0_Array_from_list$apply$2_Array_from_list_List_Int };
                          {
                            let $t11129;
                            {
                              const wrap_i6300 = $t11128;
                              {
                                const chunk_i6301 = { $: "$Clo_chunk$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int", _0: chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int, _1: wrap_i6300 };
                                {
                                  const $t11040_i6302 = { $: "Nil" };
                                  {
                                    const $t11041_i6303 = { $: "Nil" };
                                    $t11129 = chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int(chunk_i6301, front, 0, $t11040_i6302, $t11041_i6303);
                                  }
                                }
                              }
                            }
                            $p11130 = up$apply$0_Array_from_list_List_Int(up, $t11129, 0);
                          }
                        }
                        {
                          const root = $p11130._0;
                          {
                            const shift = $p11130._1;
                            {
                              const $rc_3021 = { $: "PVec", _0: n, _1: shift, _2: root, _3: tail };
                              return $rc_3021;
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
        const $f2410 = xs._0;
        const $f2411 = xs._1;
        {
          const t = $f2411;
          {
            const h = $f2410;
            {
              let $t2409;
              $t2409 = pred._0(pred, h);
              if ($t2409 === true) {
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
      const $f10848 = v._0;
      const $f10849 = v._1;
      const $f10850 = v._2;
      const $f10851 = v._3;
      {
        const tail = $f10851;
        {
          const root = $f10850;
          {
            const shift = $f10849;
            {
              const n = $f10848;
              {
                let $t10845;
                {
                  const $t10843 = (idx < 0);
                  {
                    const $t10844 = (idx >= n);
                    $t10845 = ($t10843 || $t10844);
                  }
                }
                if ($t10845 === true) {
                  march_panic_site("stdlib/array.march", 432, 32, 70);
                  return (() => { throw march_panic_error("panic: ", "Array.get: index out of range"); })();
                } else {
                  {
                    let tail_len;
                    {
                      const go_i6313 = { $: "$Clo_go$0_Array_lst_len_List_Int", _0: go$apply$0_Array_lst_len_List_Int };
                      tail_len = go$apply$0_Array_lst_len_List_Int(go_i6313, tail, 0);
                    }
                    {
                      const tail_offset = ((n - tail_len) < 4611686018427387904 && (n - tail_len) >= -4611686018427387904 ? (n - tail_len) : march_int_ovf((n - tail_len), 1));
                      {
                        const $t10846 = (idx >= tail_offset);
                        if ($t10846 === true) {
                          {
                            const $t10847 = ((idx - tail_offset) < 4611686018427387904 && (idx - tail_offset) >= -4611686018427387904 ? (idx - tail_offset) : march_int_ovf((idx - tail_offset), 1));
                            {
                              const $rc_3026 = Array$lst_nth$List_Int$Int(tail, $t10847);
                              return $rc_3026;
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
        const $f2347 = xs._0;
        const $f2348 = xs._1;
        {
          const t = $f2348;
          {
            const h = $f2347;
            {
              let $t2346;
              $t2346 = f._0(f, acc, h);
              {
                $tco_a0 = t;
                $tco_a1 = $t2346;
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
      const $f10871 = v._0;
      const $f10872 = v._1;
      const $f10873 = v._2;
      const $f10874 = v._3;
      {
        const tail = $f10874;
        {
          const root = $f10873;
          {
            const shift = $f10872;
            {
              const n = $f10871;
              {
                let $t10866;
                {
                  const $t10864 = (idx < 0);
                  {
                    const $t10865 = (idx >= n);
                    $t10866 = ($t10864 || $t10865);
                  }
                }
                if ($t10866 === true) {
                  march_panic_site("stdlib/array.march", 463, 32, 70);
                  return (() => { throw march_panic_error("panic: ", "Array.set: index out of range"); })();
                } else {
                  {
                    let tail_len;
                    {
                      const go_i6326 = { $: "$Clo_go$0_Array_lst_len_List_Int", _0: go$apply$0_Array_lst_len_List_Int };
                      tail_len = go$apply$0_Array_lst_len_List_Int(go_i6326, tail, 0);
                    }
                    {
                      const tail_offset = ((n - tail_len) < 4611686018427387904 && (n - tail_len) >= -4611686018427387904 ? (n - tail_len) : march_int_ovf((n - tail_len), 1));
                      {
                        const $t10867 = (idx >= tail_offset);
                        if ($t10867 === true) {
                          {
                            const $t10868 = ((idx - tail_offset) < 4611686018427387904 && (idx - tail_offset) >= -4611686018427387904 ? (idx - tail_offset) : march_int_ovf((idx - tail_offset), 1));
                            {
                              let $t10869;
                              {
                                const rev_onto_i6322 = { $: "$Clo_rev_onto$0_Array_lst_set_List_Int_Int_Int", _0: rev_onto$apply$0_Array_lst_set_List_Int_Int_Int };
                                {
                                  const go_i6323 = { $: "$Clo_go$1_Array_lst_set_List_Int_Int_Int", _0: go$apply$1_Array_lst_set_List_Int_Int_Int, _1: rev_onto_i6322, _2: val };
                                  {
                                    const $t10619_i6324 = { $: "Nil" };
                                    $t10869 = go$apply$1_Array_lst_set_List_Int_Int_Int(go_i6323, tail, $t10868, $t10619_i6324);
                                  }
                                }
                              }
                              return { $: "PVec", _0: n, _1: shift, _2: root, _3: $t10869 };
                            }
                          }
                        } else {
                          {
                            let $t10870;
                            {
                              const $t10703_i6318 = { $: "Nil" };
                              $t10870 = Array$trie_update_down$TrieNode_Int$Int$List_T_List_TrieNode_Int_Int$Int$Int(root, shift, $t10703_i6318, idx, val);
                            }
                            return { $: "PVec", _0: n, _1: shift, _2: $t10870, _3: tail };
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
      const $f2250 = xs._0;
      const $f2251 = xs._1;
      {
        const t = $f2251;
        {
          const h = $f2250;
          {
            let $t2248;
            $t2248 = f._0(f, h);
            {
              const $trmc38 = { $: "Cons", _0: $t2248, _1: null };
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
        const $f2212 = xs._0;
        const $f2213 = xs._1;
        {
          const t = $f2213;
          {
            const h = $f2212;
            {
              const $t2210 = (n === 0);
              if ($t2210 === true) {
                return h;
              } else {
                {
                  const $t2211 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                  {
                    $tco_a0 = t;
                    $tco_a1 = $t2211;
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
        const $f2250 = xs._0;
        const $f2251 = xs._1;
        {
          const t = $f2251;
          {
            const h = $f2250;
            {
              let $t2248;
              $t2248 = f._0(f, h);
              {
                const $trmc37 = { $: "Cons", _0: $t2248, _1: null };
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
        const $f2250 = xs._0;
        const $f2251 = xs._1;
        {
          const t = $f2251;
          {
            const h = $f2250;
            {
              let $t2248;
              $t2248 = f._0(f, h);
              {
                const $trmc37 = { $: "Cons", _0: $t2248, _1: null };
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
        const $f2242 = xs._0;
        const $f2243 = xs._1;
        {
          const t = $f2243;
          {
            const h = $f2242;
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
        const $f2227 = lst._0;
        const $f2228 = lst._1;
        {
          const t = $f2228;
          {
            const $t2226 = ((acc + 1) < 4611686018427387904 && (acc + 1) >= -4611686018427387904 ? (acc + 1) : march_int_ovf((acc + 1), 0));
            {
              $tco_a0 = t;
              $tco_a1 = $t2226;
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
        const $f2280 = xs._0;
        const $f2281 = xs._1;
        {
          const t = $f2281;
          {
            const h = $f2280;
            {
              let $t2278;
              $t2278 = pred._0(pred, h);
              if ($t2278 === true) {
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
        const $f2250 = xs._0;
        const $f2251 = xs._1;
        {
          const t = $f2251;
          {
            const h = $f2250;
            {
              let $t2248;
              $t2248 = f._0(f, h);
              {
                const $trmc37 = { $: "Cons", _0: $t2248, _1: null };
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
        const $f10590 = lst._0;
        const $f10591 = lst._1;
        {
          const t = $f10591;
          {
            let h;
            h = $f10590;
            {
              const $t10588 = (n === 0);
              if ($t10588 === true) {
                return h;
              } else {
                {
                  const $t10589 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                  {
                    $tco_a0 = t;
                    $tco_a1 = $t10589;
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
        const $f10684 = node._0;
        {
          const values = $f10684;
          {
            const $t10681 = ((idx | 0) === idx && (31 | 0) === 31 ? (idx & 31) : march_int_and(idx, 31));
            {
              const $rc_3096 = Array$lst_nth$List_Int$Int(values, $t10681);
              return $rc_3096;
            }
          }
        }
        break;
      }
      case "TrieBranch": {
        const $f10685 = node._0;
        {
          const children = $f10685;
          {
            let slot;
            {
              const $t10680_i7856 = ((idx | 0) === idx && shift >= 0 && shift < 32 ? (idx >> shift) : march_int_shr(idx, shift));
              slot = (($t10680_i7856 | 0) === $t10680_i7856 && (31 | 0) === 31 ? ($t10680_i7856 & 31) : march_int_and($t10680_i7856, 31));
            }
            {
              const $t10682 = Array$lst_nth$List_TrieNode_Int$Int(children, slot);
              {
                const $t10683 = ((shift - 5) < 4611686018427387904 && (shift - 5) >= -4611686018427387904 ? (shift - 5) : march_int_ovf((shift - 5), 1));
                {
                  $tco_a0 = $t10682;
                  $tco_a1 = idx;
                  $tco_a2 = $t10683;
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
        const $f2272 = sub._0;
        const $f2273 = sub._1;
        {
          const rest = $f2273;
          {
            const x = $f2272;
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
            const $f2266 = lst._0;
            const $f2267 = lst._1;
            {
              const t = $f2267;
              {
                const h = $f2266;
                {
                  let $t2265;
                  $t2265 = f._0(f, h);
                  {
                    $tco_a0 = $t2265;
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
        const $f2250 = xs._0;
        const $f2251 = xs._1;
        {
          const t = $f2251;
          {
            const h = $f2250;
            {
              let $t2248;
              $t2248 = f._0(f, h);
              {
                const $trmc37 = { $: "Cons", _0: $t2248, _1: null };
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
      const $f10985 = v._0;
      const $f10986 = v._1;
      const $f10987 = v._2;
      const $f10988 = v._3;
      {
        const tail = $f10988;
        {
          const root = $f10987;
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
        const $f10590 = lst._0;
        const $f10591 = lst._1;
        {
          const t = $f10591;
          {
            const h = $f10590;
            {
              const $t10588 = (n === 0);
              if ($t10588 === true) {
                return h;
              } else {
                {
                  const $t10589 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                  {
                    $tco_a0 = t;
                    $tco_a1 = $t10589;
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
        const $f10701 = n._0;
        {
          const values = $f10701;
          {
            let $t10697;
            {
              const $t10695 = ((idx | 0) === idx && (31 | 0) === 31 ? (idx & 31) : march_int_and(idx, 31));
              {
                let $t10696;
                {
                  const rev_onto_i7922 = { $: "$Clo_rev_onto$0_Array_lst_set_List_Int_Int_Int", _0: rev_onto$apply$0_Array_lst_set_List_Int_Int_Int };
                  {
                    const go_i7923 = { $: "$Clo_go$1_Array_lst_set_List_Int_Int_Int", _0: go$apply$1_Array_lst_set_List_Int_Int_Int, _1: rev_onto_i7922, _2: val };
                    {
                      const $t10619_i7924 = { $: "Nil" };
                      $t10696 = go$apply$1_Array_lst_set_List_Int_Int_Int(go_i7923, values, $t10695, $t10619_i7924);
                    }
                  }
                }
                $t10697 = { $: "TrieLeaf", _0: $t10696 };
              }
            }
            {
              const $rc_3116 = Array$trie_update_up$TrieNode_Int$List_T_List_TrieNode_Int_Int($t10697, path);
              return $rc_3116;
            }
          }
        }
        break;
      }
      case "TrieBranch": {
        const $f10702 = n._0;
        {
          const children = $f10702;
          {
            let slot;
            {
              const $t10680_i7927 = ((idx | 0) === idx && s >= 0 && s < 32 ? (idx >> s) : march_int_shr(idx, s));
              slot = (($t10680_i7927 | 0) === $t10680_i7927 && (31 | 0) === 31 ? ($t10680_i7927 & 31) : march_int_and($t10680_i7927, 31));
            }
            {
              let child;
              child = Array$lst_nth$List_TrieNode_Int$Int(children, slot);
              {
                const $t10698 = ((s - 5) < 4611686018427387904 && (s - 5) >= -4611686018427387904 ? (s - 5) : march_int_ovf((s - 5), 1));
                {
                  const $t10699 = { _0: children, _1: slot };
                  {
                    const $t10700 = { $: "Cons", _0: $t10699, _1: path };
                    {
                      $tco_a0 = child;
                      $tco_a1 = $t10698;
                      $tco_a2 = $t10700;
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
        const $f2272 = sub._0;
        const $f2273 = sub._1;
        {
          const rest = $f2273;
          {
            const x = $f2272;
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
            const $f2266 = lst._0;
            const $f2267 = lst._1;
            {
              const t = $f2267;
              {
                const h = $f2266;
                {
                  let $t2265;
                  $t2265 = f._0(f, h);
                  {
                    $tco_a0 = $t2265;
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
      const $f10791 = node._0;
      {
        const values = $f10791;
        {
          const go = { $: "$Clo_go$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int", _0: go$apply$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int, _1: f };
          return go$apply$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int(go, acc, values);
        }
      }
      break;
    }
    case "TrieBranch": {
      const $f10792 = node._0;
      {
        const children = $f10792;
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
        const $f10689 = stk._0;
        const $f10690 = stk._1;
        {
          const rest = $f10690;
          {
            const frame = $f10689;
            {
              const children = frame._0;
              {
                const slot = frame._1;
                {
                  let $t10687;
                  {
                    let $t10686;
                    {
                      const rev_onto_i7996 = { $: "$Clo_rev_onto$0_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int", _0: rev_onto$apply$0_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int };
                      {
                        const go_i7997 = { $: "$Clo_go$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int", _0: go$apply$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int, _1: nd, _2: rev_onto_i7996 };
                        {
                          const $t10679_i7998 = { $: "Nil" };
                          $t10686 = go$apply$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int(go_i7997, children, slot, $t10679_i7998);
                        }
                      }
                    }
                    $t10687 = { $: "TrieBranch", _0: $t10686 };
                  }
                  {
                    $tco_a0 = $t10687;
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
      const $t1444 = { $: "Nil" };
      return Authority$parse_entries(toks, $t1444);
    }
  }
}
const $jp1_Authority_parse$apply$0_Authority_parse$clo = { _0: ($_, $clo) => $jp1_Authority_parse$apply$0_Authority_parse($clo) };

function $jp2_Authority_parse$apply$1_Authority_parse($clo) {
  {
    const $jp_clo1450 = $clo._1;
    return $jp_clo1450._0($jp_clo1450);
  }
}
const $jp2_Authority_parse$apply$1_Authority_parse$clo = { _0: ($_, $clo) => $jp2_Authority_parse$apply$1_Authority_parse($clo) };

function $jp3_Authority_parse$apply$2_Authority_parse($clo) {
  {
    const $jp_clo1452 = $clo._1;
    return $jp_clo1452._0($jp_clo1452);
  }
}
const $jp3_Authority_parse$apply$2_Authority_parse$clo = { _0: ($_, $clo) => $jp3_Authority_parse$apply$2_Authority_parse($clo) };

function $jp7_Authority_parse_option$apply$0_Authority_parse_option($clo) {
  {
    const $f1695 = $clo._1;
    {
      const name = $clo._2;
      {
        let more;
        more = $f1695;
        {
          const $t1678 = (name === "methods");
          if ($t1678 === true) {
            {
              let $t1680;
              {
                const $t1679 = { $: "Nil" };
                $t1680 = Authority$method_words(more, $t1679);
              }
              switch ($t1680.$) {
                case "Err": {
                  const $f1684 = $t1680._0;
                  {
                    const e = $f1684;
                    return { $: "Err", _0: e };
                  }
                  break;
                }
                case "Ok": {
                  const $f1685 = $t1680._0;
                  const $f1686 = $f1685._0;
                  const $f1687 = $f1685._1;
                  {
                    const rest = $f1687;
                    {
                      const ms = $f1686;
                      {
                        let $t1682;
                        {
                          let $t1681;
                          {
                            const $rc_3136 = march_string_join(ms, ",");
                            $t1681 = $rc_3136;
                          }
                          {
                            const $rc_3135 = ("methods=" + $t1681);
                            $t1682 = $rc_3135;
                          }
                        }
                        {
                          const $t1683 = { _0: $t1682, _1: rest };
                          return { $: "Ok", _0: $t1683 };
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
              const $t1692 = march_string_concat3("`", name, "(...)` takes one quoted string");
              return { $: "Err", _0: $t1692 };
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
    const $f1725 = $clo._1;
    {
      const $f1726 = $clo._2;
      {
        const acc = $clo._3;
        {
          const $jp_clo1734 = { $: "$Clo_$jp3_Authority_method_words$1_Authority_method_words", _0: $jp3_Authority_method_words$apply$1_Authority_method_words };
          switch ($f1726.$) {
            case "Cons": {
              const $f1735 = $f1726._0;
              const $f1736 = $f1726._1;
              if ($f1735 === ")") {
                {
                  const rest = $f1736;
                  {
                    let m;
                    m = $f1725;
                    {
                      let $t1720;
                      {
                        const $t1608_i8017 = (m !== "");
                        if ($t1608_i8017 === true) {
                          $t1720 = Authority$all_chars(m, "abcdefghijklmnopqrstuvwxyz_", 0);
                        } else {
                          $t1720 = false;
                        }
                      }
                      if ($t1720 === true) {
                        {
                          let $t1721;
                          $t1721 = { $: "Cons", _0: m, _1: acc };
                          {
                            const $t1722 = { $: "Nil" };
                            {
                              const $t1723 = Authority$rev($t1721, $t1722);
                              {
                                let $t1724;
                                $t1724 = { _0: $t1723, _1: rest };
                                return { $: "Ok", _0: $t1724 };
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
          const $t2167 = (i < start);
          if ($t2167 === true) {
            return acc;
          } else {
            {
              const $t2168 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
              {
                const $t2169 = { $: "Cons", _0: i, _1: acc };
                {
                  $tco_a0 = go;
                  $tco_a1 = $t2168;
                  $tco_a2 = $t2169;
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
        const $f49563 = c._0;
        const $f49564 = c._1;
        {
          const dy = $f49564;
          {
            const dx = $f49563;
            {
              const x = ((origin_x + dx) < 4611686018427387904 && (origin_x + dx) >= -4611686018427387904 ? (origin_x + dx) : march_int_ovf((origin_x + dx), 0));
              {
                const y = ((origin_y + dy) < 4611686018427387904 && (origin_y + dy) >= -4611686018427387904 ? (origin_y + dy) : march_int_ovf((origin_y + dy), 0));
                {
                  let $t49560;
                  {
                    let $t49557_i8917;
                    {
                      let $t49555_i8915;
                      {
                        const $t49553_i8913 = (x >= 0);
                        if ($t49553_i8913 === true) {
                          $t49555_i8915 = (x < 10);
                        } else {
                          $t49555_i8915 = false;
                        }
                      }
                      {
                        const $t49556_i8916 = (y >= 0);
                        $t49557_i8917 = ($t49555_i8915 && $t49556_i8916);
                      }
                    }
                    if ($t49557_i8917 === true) {
                      $t49560 = (y < 20);
                    } else {
                      $t49560 = false;
                    }
                  }
                  if ($t49560 === false) {
                    return true;
                  } else if ($t49560 === true) {
                    {
                      let $t49562;
                      {
                        let $t49561;
                        {
                          const $t49541_i8910 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
                          $t49561 = (($t49541_i8910 + x) < 4611686018427387904 && ($t49541_i8910 + x) >= -4611686018427387904 ? ($t49541_i8910 + x) : march_int_ovf(($t49541_i8910 + x), 0));
                        }
                        $t49562 = Array$get$PVec_Int$Int(board, $t49561);
                      }
                      return ($t49562 !== 0);
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
        const $f49573 = c._0;
        const $f49574 = c._1;
        {
          const dy = $f49574;
          {
            const dx = $f49573;
            {
              const x = ((origin_x + dx) < 4611686018427387904 && (origin_x + dx) >= -4611686018427387904 ? (origin_x + dx) : march_int_ovf((origin_x + dx), 0));
              {
                const y = ((origin_y + dy) < 4611686018427387904 && (origin_y + dy) >= -4611686018427387904 ? (origin_y + dy) : march_int_ovf((origin_y + dy), 0));
                {
                  let $t49571;
                  {
                    let $t49557_i8929;
                    {
                      let $t49555_i8927;
                      {
                        const $t49553_i8925 = (x >= 0);
                        if ($t49553_i8925 === true) {
                          $t49555_i8927 = (x < 10);
                        } else {
                          $t49555_i8927 = false;
                        }
                      }
                      {
                        const $t49556_i8928 = (y >= 0);
                        $t49557_i8929 = ($t49555_i8927 && $t49556_i8928);
                      }
                    }
                    if ($t49557_i8929 === true) {
                      $t49571 = (y < 20);
                    } else {
                      $t49571 = false;
                    }
                  }
                  if ($t49571 === true) {
                    {
                      let $t49572;
                      {
                        const $t49541_i8922 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
                        $t49572 = (($t49541_i8922 + x) < 4611686018427387904 && ($t49541_i8922 + x) >= -4611686018427387904 ? ($t49541_i8922 + x) : march_int_ovf(($t49541_i8922 + x), 0));
                      }
                      return Array$set$PVec_Int$Int$Int(b, $t49572, color_idx);
                    }
                  } else if ($t49571 === false) {
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
        let $t49584;
        {
          let $t49583;
          {
            const $t49541_i8934 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
            $t49583 = (($t49541_i8934 + x) < 4611686018427387904 && ($t49541_i8934 + x) >= -4611686018427387904 ? ($t49541_i8934 + x) : march_int_ovf(($t49541_i8934 + x), 0));
          }
          $t49584 = Array$get$PVec_Int$Int(board, $t49583);
        }
        return ($t49584 !== 0);
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
        let $t49589;
        {
          const $t49541_i8938 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
          $t49589 = (($t49541_i8938 + x) < 4611686018427387904 && ($t49541_i8938 + x) >= -4611686018427387904 ? ($t49541_i8938 + x) : march_int_ovf(($t49541_i8938 + x), 0));
        }
        return Array$get$PVec_Int$Int(board, $t49589);
      }
    }
  }
}
const $lam0_TetrisLogic_row_cells$apply$0_TetrisLogic_row_cells$clo = { _0: ($_, $clo, x) => $lam0_TetrisLogic_row_cells$apply$0_TetrisLogic_row_cells($clo, x) };

function $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines($clo, y) {
  {
    const board = $clo._1;
    {
      let $t49593;
      {
        let $t49581_i14596;
        {
          const go_i5854_i14593 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
          {
            const $t2171_i5856_i14595 = { $: "Nil" };
            $t49581_i14596 = go$apply$0_List_range(go_i5854_i14593, 9, $t2171_i5856_i14595);
          }
        }
        {
          const $t49585_i14597 = { $: "$Clo_$lam0_TetrisLogic_row_full$0_TetrisLogic_row_full", _0: $lam0_TetrisLogic_row_full$apply$0_TetrisLogic_row_full, _1: board, _2: y };
          {
            const $rc_2817_i14598 = List$all$List_Int$Fn_Int_Bool($t49581_i14596, $t49585_i14597);
            $t49593 = $rc_2817_i14598;
          }
        }
      }
      return (!$t49593);
    }
  }
}
const $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines$clo = { _0: ($_, $clo, y) => $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines($clo, y) };

function $lam1_TetrisLogic_clear_lines$apply$1_TetrisLogic_clear_lines($clo, y) {
  {
    const board = $clo._1;
    {
      let $t49587_i8942;
      {
        const go_i14765 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
        {
          const $t2171_i14767 = { $: "Nil" };
          $t49587_i8942 = go$apply$0_List_range(go_i14765, 9, $t2171_i14767);
        }
      }
      {
        const $t49590_i8943 = { $: "$Clo_$lam0_TetrisLogic_row_cells$0_TetrisLogic_row_cells", _0: $lam0_TetrisLogic_row_cells$apply$0_TetrisLogic_row_cells, _1: board, _2: y };
        {
          const xs_i14831 = $t49587_i8942;
          {
            const f_i14832 = $t49590_i8943;
            switch (xs_i14831.$) {
              case "Nil": {
                return { $: "Nil" };
                break;
              }
              case "Cons": {
                const $f2250_i14833 = xs_i14831._0;
                const $f2251_i14834 = xs_i14831._1;
                {
                  const t_i14835 = $f2251_i14834;
                  {
                    const h_i14836 = $f2250_i14833;
                    {
                      let $t2248_i14837;
                      $t2248_i14837 = f_i14832._0(f_i14832, h_i14836);
                      {
                        const $trmc38_i14838 = { $: "Cons", _0: $t2248_i14837, _1: null };
                        List$map$dps$List_Int$Fn_Int_Int$List_Int(t_i14835, f_i14832, $trmc38_i14838);
                        return $trmc38_i14838;
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
    let $t49607;
    {
      const $rc_3711 = march_string_to_int(x);
      $t49607 = $rc_3711;
    }
    {
      const $rc_3710 = Option$unwrap_or$Option_Int$Int($t49607, 0);
      return $rc_3710;
    }
  }
}
const $lam0_string_to_int_list$apply$0_string_to_int_list$clo = { _0: ($_, $clo, x) => $lam0_string_to_int_list$apply$0_string_to_int_list($clo, x) };

function $lam0_render_board$apply$0_render_board($clo, y) {
  {
    const board = $clo._1;
    {
      let $t49664;
      {
        const go_i8949 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
        {
          const $t2171_i8951 = { $: "Nil" };
          $t49664 = go$apply$0_List_range(go_i8949, 9, $t2171_i8951);
        }
      }
      {
        let $t49672;
        $t49672 = { $: "$Clo_$lam0__lam0_render_board$1_render_board", _0: $lam0__lam0_render_board$apply$1_render_board, _1: board, _2: y };
        {
          const f_i8945 = $t49672;
          {
            const go_i8946 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i8945 };
            return go$apply$0_List_each_List_Int_Fn_Int_T_(go_i8946, $t49664);
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
          const $t49541_i8956 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
          idx = (($t49541_i8956 + x) < 4611686018427387904 && ($t49541_i8956 + x) >= -4611686018427387904 ? ($t49541_i8956 + x) : march_int_ovf(($t49541_i8956 + x), 0));
        }
        {
          let v;
          v = Array$get$PVec_Int$Int(board, idx);
          {
            let id;
            {
              const $t49666 = String(x);
              {
                const $t49667 = String(y);
                {
                  const $rc_3712 = march_string_concat_n("cell-", $t49666, "-", $t49667);
                  id = $rc_3712;
                }
              }
            }
            {
              const $t49668 = Js$Dom$find(id);
              switch ($t49668.$) {
                case "None": {
                  return {  };
                  break;
                }
                case "Some": {
                  const $f49671 = $t49668._0;
                  {
                    const cell = $f49671;
                    {
                      const $t49669 = (v === 0);
                      if ($t49669 === true) {
                        return Js$Dom$set_style(cell, "background", "");
                      } else if ($t49669 === false) {
                        {
                          let $t49670;
                          if (v === 1) {
                            $t49670 = "#00CED1";
                          } else if (v === 2) {
                            $t49670 = "#FFD700";
                          } else if (v === 3) {
                            $t49670 = "#9B59B6";
                          } else if (v === 4) {
                            $t49670 = "#2ECC71";
                          } else if (v === 5) {
                            $t49670 = "#E74C3C";
                          } else if (v === 6) {
                            $t49670 = "#3498DB";
                          } else if (v === 7) {
                            $t49670 = "#F39C12";
                          } else {
                            $t49670 = "";
                          }
                          return Js$Dom$set_style(cell, "background", $t49670);
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
        const $f49687 = c._0;
        const $f49688 = c._1;
        {
          const dy = $f49688;
          {
            const dx = $f49687;
            {
              const x = ((ox + dx) < 4611686018427387904 && (ox + dx) >= -4611686018427387904 ? (ox + dx) : march_int_ovf((ox + dx), 0));
              {
                const y = ((oy + dy) < 4611686018427387904 && (oy + dy) >= -4611686018427387904 ? (oy + dy) : march_int_ovf((oy + dy), 0));
                {
                  let $t49681;
                  {
                    let $t49679;
                    {
                      let $t49677;
                      {
                        const $t49675 = (x >= 0);
                        if ($t49675 === true) {
                          $t49677 = (x < 10);
                        } else {
                          $t49677 = false;
                        }
                      }
                      {
                        const $t49678 = (y >= 0);
                        $t49679 = ($t49677 && $t49678);
                      }
                    }
                    if ($t49679 === true) {
                      $t49681 = (y < 20);
                    } else {
                      $t49681 = false;
                    }
                  }
                  if ($t49681 === false) {
                    return {  };
                  } else if ($t49681 === true) {
                    {
                      let id;
                      {
                        const $t49682 = String(x);
                        {
                          const $t49683 = String(y);
                          {
                            const $rc_3713 = march_string_concat_n("cell-", $t49682, "-", $t49683);
                            id = $rc_3713;
                          }
                        }
                      }
                      {
                        const $t49684 = Js$Dom$find(id);
                        switch ($t49684.$) {
                          case "None": {
                            return {  };
                            break;
                          }
                          case "Some": {
                            const $f49686 = $t49684._0;
                            {
                              const cell = $f49686;
                              {
                                let $t49685;
                                switch (piece.$) {
                                  case "I": {
                                    $t49685 = "#00CED1";
                                    break;
                                  }
                                  case "O": {
                                    $t49685 = "#FFD700";
                                    break;
                                  }
                                  case "T": {
                                    $t49685 = "#9B59B6";
                                    break;
                                  }
                                  case "S": {
                                    $t49685 = "#2ECC71";
                                    break;
                                  }
                                  case "Z": {
                                    $t49685 = "#E74C3C";
                                    break;
                                  }
                                  case "J": {
                                    $t49685 = "#3498DB";
                                    break;
                                  }
                                  case "L": {
                                    $t49685 = "#F39C12";
                                    break;
                                  }
                                  default: {
                                    throw march_panic_error("panic: ", "non-exhaustive pattern match");
                                    break;
                                  }
                                }
                                return Js$Dom$set_style(cell, "background", $t49685);
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
    const $t49816 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t49816, rot);
      {
        let $t49818;
        {
          const $t49817 = ((y + 1) < 4611686018427387904 && (y + 1) >= -4611686018427387904 ? (y + 1) : march_int_ovf((y + 1), 0));
          {
            const $t49569_i8961 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: x, _3: $t49817 };
            $t49818 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t49569_i8961);
          }
        }
        if ($t49818 === true) {
          {
            const $rc_3714 = lock_and_advance(board, piece, rot, x, y, next, score, lines, rng);
            return $rc_3714;
          }
        } else if ($t49818 === false) {
          {
            const $t49819 = ((y + 1) < 4611686018427387904 && (y + 1) >= -4611686018427387904 ? (y + 1) : march_int_ovf((y + 1), 0));
            return { _0: board, _1: piece, _2: rot, _3: x, _4: $t49819, _5: next, _6: score, _7: lines, _8: rng, _9: false };
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
      const $t49814_i14600 = is_paused();
      if ($t49814_i14600 === true) {
        $eff = {  };
      } else if ($t49814_i14600 === false) {
        {
          const $t49820_i14601 = { $: "$Clo_$lam0_tick$0_tick", _0: $lam0_tick$apply$0_tick };
          $eff = with_state($t49820_i14601);
        }
      } else {
        throw march_panic_error("panic: ", "non-exhaustive pattern match");
      }
    }
  }
  {
    let level_i8964;
    {
      let $t49822_i8963;
      {
        const $t49821_i8962 = state_el();
        $t49822_i8963 = get_int_attr($t49821_i8962, "data-lines", 0);
      }
      level_i8964 = TetrisLogic$level_for_lines($t49822_i8963);
    }
    {
      let $t49823_i8965;
      {
        let $t49539_i14770;
        {
          const $t49538_i14769 = ((level_i8964 * 40) < 4611686018427387904 && (level_i8964 * 40) >= -4611686018427387904 ? (level_i8964 * 40) : march_int_ovf((level_i8964 * 40), 2));
          $t49539_i14770 = ((500 - $t49538_i14769) < 4611686018427387904 && (500 - $t49538_i14769) >= -4611686018427387904 ? (500 - $t49538_i14769) : march_int_ovf((500 - $t49538_i14769), 1));
        }
        {
          const $t3792_i5847_i14771 = ($t49539_i14770 > 100);
          if ($t3792_i5847_i14771 === true) {
            $t49823_i8965 = $t49539_i14770;
          } else {
            $t49823_i8965 = 100;
          }
        }
      }
      {
        const $t49825_i8966 = { $: "$Clo_$lam0_schedule_tick$0_schedule_tick", _0: $lam0_schedule_tick$apply$0_schedule_tick };
        return Js$Dom$set_timeout($t49823_i8965, $t49825_i8966);
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
        const $t49827 = TetrisLogic$piece_cells(piece);
        {
          const cells = rotate_n($t49827, rot);
          {
            let $t49830;
            {
              const $t49828 = ((x + dx) < 4611686018427387904 && (x + dx) >= -4611686018427387904 ? (x + dx) : march_int_ovf((x + dx), 0));
              {
                const $t49829 = ((y + dy) < 4611686018427387904 && (y + dy) >= -4611686018427387904 ? (y + dy) : march_int_ovf((y + dy), 0));
                {
                  const $t49569_i8971 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: $t49828, _3: $t49829 };
                  $t49830 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t49569_i8971);
                }
              }
            }
            if ($t49830 === true) {
              return { _0: board, _1: piece, _2: rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: rng, _9: false };
            } else if ($t49830 === false) {
              {
                const $t49831 = ((x + dx) < 4611686018427387904 && (x + dx) >= -4611686018427387904 ? (x + dx) : march_int_ovf((x + dx), 0));
                {
                  const $t49832 = ((y + dy) < 4611686018427387904 && (y + dy) >= -4611686018427387904 ? (y + dy) : march_int_ovf((y + dy), 0));
                  return { _0: board, _1: piece, _2: rot, _3: $t49831, _4: $t49832, _5: next, _6: score, _7: lines, _8: rng, _9: false };
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
      const $t49835 = ((rot + 1) < 4611686018427387904 && (rot + 1) >= -4611686018427387904 ? (rot + 1) : march_int_ovf((rot + 1), 0));
      new_rot = (4 === 0 ? march_mod_zero() : $t49835 % 4);
    }
    {
      const $t49836 = TetrisLogic$piece_cells(piece);
      {
        const cells = rotate_n($t49836, new_rot);
        {
          let $t49837;
          {
            const $t49569_i8976 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: x, _3: y };
            $t49837 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t49569_i8976);
          }
          if ($t49837 === true) {
            return { _0: board, _1: piece, _2: rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: rng, _9: false };
          } else if ($t49837 === false) {
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
    const $t49843 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t49843, rot);
      {
        let final_y;
        final_y = fall_from(board, cells, x, y);
        {
          const $rc_3715 = lock_and_advance(board, piece, rot, x, final_y, next, score, lines, rng);
          return $rc_3715;
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
          let $t49918;
          {
            const go_i8982 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
            {
              const $t2171_i8984 = { $: "Nil" };
              $t49918 = go$apply$0_List_range(go_i8982, 9, $t2171_i8984);
            }
          }
          {
            let $t49923;
            $t49923 = { $: "$Clo_$lam0__lam0_build_board_dom$1_build_board_dom", _0: $lam0__lam0_build_board_dom$apply$1_build_board_dom, _1: row, _2: y };
            {
              const f_i8978 = $t49923;
              {
                const go_i8979 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i8978 };
                $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i8979, $t49918);
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
            let $t49922;
            {
              const $t49920 = String(x);
              {
                const $t49921 = String(y);
                {
                  const $rc_3716 = march_string_concat_n("cell-", $t49920, "-", $t49921);
                  $t49922 = $rc_3716;
                }
              }
            }
            $eff = Js$Dom$set_attr(cell, "id", $t49922);
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
          const $t2163 = (i <= 0);
          if ($t2163 === true) {
            return acc;
          } else {
            {
              const $t2164 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
              {
                const $t2165 = { $: "Cons", _0: x, _1: acc };
                {
                  $tco_a0 = go;
                  $tco_a1 = $t2164;
                  $tco_a2 = $t2165;
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
        const $t11114 = { $: "$Clo_$lam0_Array_from_list_up$1_Array_from_list_List_Int", _0: $lam0_Array_from_list_up$apply$1_Array_from_list_List_Int };
        {
          let parents;
          {
            const wrap_i9120 = $t11114;
            {
              const chunk_i9121 = { $: "$Clo_chunk$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int", _0: chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int, _1: wrap_i9120 };
              {
                const $t11040_i9122 = { $: "Nil" };
                {
                  const $t11041_i9123 = { $: "Nil" };
                  parents = chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int(chunk_i9121, nodes, 0, $t11040_i9122, $t11041_i9123);
                }
              }
            }
          }
          {
            let $t11116;
            {
              let $t11115;
              {
                const go_i9118 = { $: "$Clo_go$0_Array_lst_len_List_TrieNode_Int", _0: go$apply$0_Array_lst_len_List_TrieNode_Int };
                $t11115 = go$apply$0_Array_lst_len_List_TrieNode_Int(go_i9118, parents, 0);
              }
              $t11116 = ($t11115 === 1);
            }
            if ($t11116 === true) {
              switch (parents.$) {
                case "Cons": {
                  const $f11120 = parents._0;
                  const $f11121 = parents._1;
                  {
                    const root = $f11120;
                    {
                      const $t11117 = ((shift + 5) < 4611686018427387904 && (shift + 5) >= -4611686018427387904 ? (shift + 5) : march_int_ovf((shift + 5), 0));
                      return { _0: root, _1: $t11117 };
                    }
                  }
                  break;
                }
                case "Nil": {
                  {
                    const $t11118 = { $: "TrieEmpty" };
                    {
                      const $t11119 = ((shift + 5) < 4611686018427387904 && (shift + 5) >= -4611686018427387904 ? (shift + 5) : march_int_ovf((shift + 5), 0));
                      return { _0: $t11118, _1: $t11119 };
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
                const $t11126 = ((shift + 5) < 4611686018427387904 && (shift + 5) >= -4611686018427387904 ? (shift + 5) : march_int_ovf((shift + 5), 0));
                {
                  $tco_a0 = $clo;
                  $tco_a1 = parents;
                  $tco_a2 = $t11126;
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
            const $f2257 = lst._0;
            const $f2258 = lst._1;
            {
              const t = $f2258;
              {
                const h = $f2257;
                {
                  let $p2256;
                  $p2256 = f._0(f, h);
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
            const $f2257 = lst._0;
            const $f2258 = lst._1;
            {
              const t = $f2258;
              {
                const h = $f2257;
                {
                  let $p2256;
                  $p2256 = f._0(f, h);
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
          const $f10621 = xs._0;
          const $f10622 = xs._1;
          {
            const t = $f10622;
            {
              const $t10620 = ((acc + 1) < 4611686018427387904 && (acc + 1) >= -4611686018427387904 ? (acc + 1) : march_int_ovf((acc + 1), 0));
              {
                $tco_a0 = $clo;
                $tco_a1 = t;
                $tco_a2 = $t10620;
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
                  const go_i9203 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                  {
                    const $t10587_i9204 = { $: "Nil" };
                    return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9203, out, $t10587_i9204);
                  }
                }
                break;
              }
              default: {
                {
                  let $t11022;
                  {
                    let $t11021;
                    {
                      const go_i9200 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                      {
                        const $t10587_i9201 = { $: "Nil" };
                        $t11021 = go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9200, cur, $t10587_i9201);
                      }
                    }
                    $t11022 = wrap._0(wrap, $t11021);
                  }
                  {
                    const $t11023 = { $: "Cons", _0: $t11022, _1: out };
                    {
                      const go_i9197 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                      {
                        const $t10587_i9198 = { $: "Nil" };
                        return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9197, $t11023, $t10587_i9198);
                      }
                    }
                  }
                }
              }
            }
            break;
          }
          case "Cons": {
            const $f11034 = ys._0;
            const $f11035 = ys._1;
            {
              const t = $f11035;
              {
                const h = $f11034;
                {
                  const $t11026 = (i === 31);
                  if ($t11026 === true) {
                    {
                      const $t11027 = { $: "Nil" };
                      {
                        let $t11030;
                        {
                          const $t11028 = { $: "Cons", _0: h, _1: cur };
                          {
                            let $t11029;
                            {
                              const go_i9206 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                              {
                                const $t10587_i9207 = { $: "Nil" };
                                $t11029 = go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9206, $t11028, $t10587_i9207);
                              }
                            }
                            $t11030 = wrap._0(wrap, $t11029);
                          }
                        }
                        {
                          const $t11031 = { $: "Cons", _0: $t11030, _1: out };
                          {
                            $tco_a0 = chunk;
                            $tco_a1 = t;
                            $tco_a2 = 0;
                            $tco_a3 = $t11027;
                            $tco_a4 = $t11031;
                            continue __tco;
                          }
                        }
                      }
                    }
                  } else {
                    {
                      const $t11032 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                      {
                        const $t11033 = { $: "Cons", _0: h, _1: cur };
                        {
                          $tco_a0 = chunk;
                          $tco_a1 = t;
                          $tco_a2 = $t11032;
                          $tco_a3 = $t11033;
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
                  const go_i9215 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                  {
                    const $t10587_i9216 = { $: "Nil" };
                    return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9215, out, $t10587_i9216);
                  }
                }
                break;
              }
              default: {
                {
                  let $t11022;
                  {
                    let $t11021;
                    {
                      const go_i9212 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                      {
                        const $t10587_i9213 = { $: "Nil" };
                        $t11021 = go$apply$0_Array_lst_rev_List_Int(go_i9212, cur, $t10587_i9213);
                      }
                    }
                    $t11022 = wrap._0(wrap, $t11021);
                  }
                  {
                    const $t11023 = { $: "Cons", _0: $t11022, _1: out };
                    {
                      const go_i9209 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                      {
                        const $t10587_i9210 = { $: "Nil" };
                        return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9209, $t11023, $t10587_i9210);
                      }
                    }
                  }
                }
              }
            }
            break;
          }
          case "Cons": {
            const $f11034 = ys._0;
            const $f11035 = ys._1;
            {
              const t = $f11035;
              {
                const h = $f11034;
                {
                  const $t11026 = (i === 31);
                  if ($t11026 === true) {
                    {
                      const $t11027 = { $: "Nil" };
                      {
                        let $t11030;
                        {
                          const $t11028 = { $: "Cons", _0: h, _1: cur };
                          {
                            let $t11029;
                            {
                              const go_i9218 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                              {
                                const $t10587_i9219 = { $: "Nil" };
                                $t11029 = go$apply$0_Array_lst_rev_List_Int(go_i9218, $t11028, $t10587_i9219);
                              }
                            }
                            $t11030 = wrap._0(wrap, $t11029);
                          }
                        }
                        {
                          const $t11031 = { $: "Cons", _0: $t11030, _1: out };
                          {
                            $tco_a0 = chunk;
                            $tco_a1 = t;
                            $tco_a2 = 0;
                            $tco_a3 = $t11027;
                            $tco_a4 = $t11031;
                            continue __tco;
                          }
                        }
                      }
                    }
                  } else {
                    {
                      const $t11032 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                      {
                        const $t11033 = { $: "Cons", _0: h, _1: cur };
                        {
                          $tco_a0 = chunk;
                          $tco_a1 = t;
                          $tco_a2 = $t11032;
                          $tco_a3 = $t11033;
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
        const $t11008 = (i === 0);
        if ($t11008 === true) {
          {
            let $t11009;
            {
              const go_i9224 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
              {
                const $t10587_i9225 = { $: "Nil" };
                $t11009 = go$apply$0_Array_lst_rev_List_Int(go_i9224, acc, $t10587_i9225);
              }
            }
            return { _0: $t11009, _1: ys };
          }
        } else {
          switch (ys.$) {
            case "Nil": {
              {
                let $t11010;
                {
                  const go_i9221 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                  {
                    const $t10587_i9222 = { $: "Nil" };
                    $t11010 = go$apply$0_Array_lst_rev_List_Int(go_i9221, acc, $t10587_i9222);
                  }
                }
                {
                  const $t11011 = { $: "Nil" };
                  return { _0: $t11010, _1: $t11011 };
                }
              }
              break;
            }
            case "Cons": {
              const $f11014 = ys._0;
              const $f11015 = ys._1;
              {
                const t = $f11015;
                {
                  const h = $f11014;
                  {
                    const $t11012 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
                    {
                      const $t11013 = { $: "Cons", _0: h, _1: acc };
                      {
                        $tco_a0 = $clo;
                        $tco_a1 = t;
                        $tco_a2 = $t11012;
                        $tco_a3 = $t11013;
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
          const $f10621 = xs._0;
          const $f10622 = xs._1;
          {
            const t = $f10622;
            {
              const $t10620 = ((acc + 1) < 4611686018427387904 && (acc + 1) >= -4611686018427387904 ? (acc + 1) : march_int_ovf((acc + 1), 0));
              {
                $tco_a0 = $clo;
                $tco_a1 = t;
                $tco_a2 = $t10620;
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
          const $f10597 = rev_xs._0;
          const $f10598 = rev_xs._1;
          {
            const rest = $f10598;
            {
              const a = $f10597;
              {
                const $t10596 = { $: "Cons", _0: a, _1: ys };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = rest;
                  $tco_a2 = $t10596;
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
            const $t10603 = (i === 0);
            if ($t10603 === true) {
              switch (xs.$) {
                case "Nil": {
                  {
                    const go_i9230 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                    {
                      const $t10587_i9231 = { $: "Nil" };
                      return go$apply$0_Array_lst_rev_List_Int(go_i9230, acc, $t10587_i9231);
                    }
                  }
                  break;
                }
                case "Cons": {
                  const $f10605 = xs._0;
                  const $f10606 = xs._1;
                  {
                    const t = $f10606;
                    {
                      const $t10604 = { $: "Cons", _0: v, _1: t };
                      return rev_onto._0(rev_onto, acc, $t10604);
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
                    const go_i9227 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                    {
                      const $t10587_i9228 = { $: "Nil" };
                      return go$apply$0_Array_lst_rev_List_Int(go_i9227, acc, $t10587_i9228);
                    }
                  }
                  break;
                }
                case "Cons": {
                  const $f10613 = xs._0;
                  const $f10614 = xs._1;
                  {
                    const t = $f10614;
                    {
                      const h = $f10613;
                      {
                        const $t10611 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
                        {
                          const $t10612 = { $: "Cons", _0: h, _1: acc };
                          {
                            $tco_a0 = go;
                            $tco_a1 = t;
                            $tco_a2 = $t10611;
                            $tco_a3 = $t10612;
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
          const $f10581 = xs._0;
          const $f10582 = xs._1;
          {
            const t = $f10582;
            {
              const h = $f10581;
              {
                const $t10580 = { $: "Cons", _0: h, _1: acc };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = t;
                  $tco_a2 = $t10580;
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
            const $f10979 = xs._0;
            const $f10980 = xs._1;
            {
              const rest = $f10980;
              {
                const x = $f10979;
                {
                  let $t10978;
                  $t10978 = f._0(f, a, x);
                  {
                    $tco_a0 = go;
                    $tco_a1 = $t10978;
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
          const $f10581 = xs._0;
          const $f10582 = xs._1;
          {
            const t = $f10582;
            {
              const h = $f10581;
              {
                const $t10580 = { $: "Cons", _0: h, _1: acc };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = t;
                  $tco_a2 = $t10580;
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
            const $f10778 = vs._0;
            const $f10779 = vs._1;
            {
              const rest = $f10779;
              {
                const v = $f10778;
                {
                  let $t10777;
                  $t10777 = f._0(f, a, v);
                  {
                    $tco_a0 = go;
                    $tco_a1 = $t10777;
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
            const $f10785 = cs._0;
            const $f10786 = cs._1;
            {
              const rest = $f10786;
              {
                const child = $f10785;
                {
                  let $t10784;
                  $t10784 = Array$trie_fold$List_Int$TrieNode_Int$Fn_List_Int_Int_List_Int(a, child, f);
                  {
                    $tco_a0 = go;
                    $tco_a1 = $t10784;
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
          const $f10663 = rev_xs._0;
          const $f10664 = rev_xs._1;
          {
            const rest = $f10664;
            {
              const a = $f10663;
              {
                const $t10662 = { $: "Cons", _0: a, _1: ys };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = rest;
                  $tco_a2 = $t10662;
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
                const go_i9643 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                {
                  const $t10587_i9644 = { $: "Nil" };
                  return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9643, acc, $t10587_i9644);
                }
              }
              break;
            }
            case "Cons": {
              const $f10673 = xs._0;
              const $f10674 = xs._1;
              {
                const t = $f10674;
                {
                  const h = $f10673;
                  {
                    const $t10669 = (i === 0);
                    if ($t10669 === true) {
                      {
                        let $t10670;
                        $t10670 = { $: "Cons", _0: node, _1: t };
                        return rev_onto._0(rev_onto, acc, $t10670);
                      }
                    } else {
                      {
                        const $t10671 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
                        {
                          const $t10672 = { $: "Cons", _0: h, _1: acc };
                          {
                            $tco_a0 = go;
                            $tco_a1 = t;
                            $tco_a2 = $t10671;
                            $tco_a3 = $t10672;
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
