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
    case "ByMock": {
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
      const $f782 = e._0;
      const $f783 = e._1;
      const $f784 = e._2;
      const $f785 = e._3;
      {
        const scope = $f785;
        {
          const limit = $f784;
          {
            const target = $f783;
            {
              const kind = $f782;
              {
                let o_pre;
                {
                  const $t780 = (target === "");
                  if ($t780 === true) {
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
                        const $f798_i9649 = limit._0;
                        {
                          const f_i9650 = $f798_i9649;
                          $rc_65 = march_string_concat3("function ", f_i9650, "'s needs");
                        }
                        break;
                      }
                      case "ByModNeeds": {
                        const $f799_i9651 = limit._0;
                        {
                          const m_i9652 = $f799_i9651;
                          $rc_65 = march_string_concat3("module ", m_i9652, "'s needs");
                        }
                        break;
                      }
                      case "ByRestrict": {
                        const $f800_i9653 = limit._0;
                        {
                          const w_i9654 = $f800_i9653;
                          $rc_65 = ("the restrict at " + w_i9654);
                        }
                        break;
                      }
                      case "ByGrant": {
                        const $f801_i9655 = limit._0;
                        {
                          const p_i9656 = $f801_i9655;
                          $rc_65 = ("the grant to package " + p_i9656);
                        }
                        break;
                      }
                      case "ByMock": {
                        const $f802_i9657 = limit._0;
                        $rc_65 = "a mock";
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
                      const $t781 = (scope === "");
                      if ($t781 === true) {
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
      const $t807 = (r === 0);
      if ($t807 === true) {
        {
          const $t808 = {  };
          return { $: "Ok", _0: $t808 };
        }
      } else {
        {
          const $t809_i9661 = march_cap_layers();
          {
            const kind_i14774 = kind;
            {
              let cwd_i14782;
              {
                let $t812_i14781;
                {
                  let $t810_i14779;
                  {
                    let $t1123_i59_i14778;
                    {
                      const $t1122_i58_i14777 = (kind === "IO.FileRead");
                      if ($t1122_i58_i14777 === true) {
                        $t1123_i59_i14778 = true;
                      } else {
                        $t1123_i59_i14778 = (kind === "IO.FileWrite");
                      }
                    }
                    if ($t1123_i59_i14778 === true) {
                      $t810_i14779 = true;
                    } else {
                      $t810_i14779 = (kind === "IO.FileSystem");
                    }
                  }
                  if ($t810_i14779 === true) {
                    {
                      const $t811_i14780 = march_string_starts_with(target, "/");
                      $t812_i14781 = (!$t811_i14780);
                    }
                  } else {
                    $t812_i14781 = false;
                  }
                }
                if ($t812_i14781 === true) {
                  cwd_i14782 = march_cap_cwd();
                } else {
                  cwd_i14782 = "/";
                }
              }
              {
                let $t813_i14783;
                {
                  let p_i14842;
                  if (kind === "IO.Console") {
                    p_i14842 = "IO";
                  } else if (kind === "IO.FileSystem") {
                    p_i14842 = "IO";
                  } else if (kind === "IO.FileRead") {
                    p_i14842 = "IO.FileSystem";
                  } else if (kind === "IO.FileWrite") {
                    p_i14842 = "IO.FileSystem";
                  } else if (kind === "IO.Network") {
                    p_i14842 = "IO";
                  } else if (kind === "IO.NetConnect") {
                    p_i14842 = "IO.Network";
                  } else if (kind === "IO.NetListen") {
                    p_i14842 = "IO.Network";
                  } else if (kind === "IO.Process") {
                    p_i14842 = "IO";
                  } else if (kind === "IO.Clock") {
                    p_i14842 = "IO";
                  } else if (kind === "IO.Random") {
                    p_i14842 = "IO";
                  } else if (kind === "IO.Signal") {
                    p_i14842 = "IO";
                  } else if (kind === "IO.Database") {
                    p_i14842 = "IO.NetConnect";
                  } else if (kind === "IO.Spawn") {
                    p_i14842 = "IO";
                  } else if (kind === "IO.Mut") {
                    p_i14842 = "IO";
                  } else if (kind === "IO.Telemetry") {
                    p_i14842 = "IO";
                  } else if (kind === "IO.NetConnect.TLS") {
                    p_i14842 = "IO.NetConnect";
                  } else if (kind === "IO.WebSocket") {
                    p_i14842 = "IO.NetConnect";
                  } else if (kind === "IO.Foreign") {
                    p_i14842 = "IO";
                  } else if (kind === "IO.Foreign.Blocking") {
                    p_i14842 = "IO.Foreign";
                  } else if (kind === "IO.Registry") {
                    p_i14842 = "IO";
                  } else if (kind === "IO.Cluster") {
                    p_i14842 = "IO";
                  } else {
                    p_i14842 = "";
                  }
                  {
                    const $t1117_i14843 = (p_i14842 === "");
                    if ($t1117_i14843 === true) {
                      {
                        const $t1118_i14844 = { $: "Nil" };
                        $t813_i14783 = { $: "Cons", _0: kind, _1: $t1118_i14844 };
                      }
                    } else {
                      {
                        const $trmc7_i14845 = { $: "Cons", _0: kind, _1: null };
                        Authority$kind_chain$dps(p_i14842, $trmc7_i14845);
                        $t813_i14783 = $trmc7_i14845;
                      }
                    }
                  }
                }
                {
                  const $rc_67_i14784 = Authority$first_refusal(kind, $t813_i14783, target, cwd_i14782, $t809_i9661);
                  return $rc_67_i14784;
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
          const $t814 = {  };
          return { $: "Ok", _0: $t814 };
        }
        break;
      }
      case "Cons": {
        const $f819 = layers._0;
        const $f820 = layers._1;
        switch ($f819.$) {
          case "Layer": {
            const $f821 = $f819._0;
            const $f822 = $f819._1;
            const $f823 = $f819._2;
            {
              const $jp37_rest = $f820;
              {
                const $jp39_scopes = $f823;
                switch ($f821.$) {
                  case "ByMock": {
                    const $f836 = $f821._0;
                    {
                      let $t815;
                      $t815 = Authority$mock_covers($jp39_scopes, kind, target, cwd);
                      if ($t815 === true) {
                        {
                          const $t816 = {  };
                          return { $: "Ok", _0: $t816 };
                        }
                      } else {
                        {
                          $tco_a0 = kind;
                          $tco_a1 = chain;
                          $tco_a2 = target;
                          $tco_a3 = cwd;
                          $tco_a4 = $jp37_rest;
                          continue __tco;
                        }
                      }
                    }
                    break;
                  }
                  default: {
                    {
                      const text = $f822;
                      {
                        const limit = $f821;
                        {
                          let $t817;
                          $t817 = Authority$admits_in($jp39_scopes, chain, kind, target, cwd);
                          if ($t817 === true) {
                            {
                              $tco_a0 = kind;
                              $tco_a1 = chain;
                              $tco_a2 = target;
                              $tco_a3 = cwd;
                              $tco_a4 = $jp37_rest;
                              continue __tco;
                            }
                          } else {
                            {
                              const $t818 = { $: "CapError", _0: kind, _1: target, _2: limit, _3: text };
                              return { $: "Err", _0: $t818 };
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
      let $t854;
      {
        const $t853 = (!scoped);
        if ($t853 === true) {
          $t854 = (grant === "");
        } else {
          $t854 = false;
        }
      }
      if ($t854 === true) {
        return {  };
      } else {
        {
          const $t855 = Authority$parse(request);
          switch ($t855.$) {
            case "Err": {
              const $f874 = $t855._0;
              {
                const e = $f874;
                march_panic_site("stdlib/authority.march", 192, 16, 76);
                {
                  let $t856;
                  {
                    const $rc_68 = ("internal: main's request is not a scope list: " + e);
                    $t856 = $rc_68;
                  }
                  return (() => { throw march_panic_error("panic: ", $t856); })();
                }
              }
              break;
            }
            case "Ok": {
              const $f875 = $t855._0;
              {
                const req = $f875;
                {
                  const $t857 = (grant === "");
                  if ($t857 === true) {
                    {
                      let $t859;
                      {
                        const $t858 = { $: "ByLaunch" };
                        $t859 = { $: "Layer", _0: $t858, _1: request, _2: req };
                      }
                      {
                        const $t860 = { $: "Nil" };
                        {
                          const $t861 = { $: "Cons", _0: $t859, _1: $t860 };
                          return march_cap_set_launch($t861);
                        }
                      }
                    }
                  } else {
                    {
                      const $t862 = Authority$parse(grant);
                      switch ($t862.$) {
                        case "Err": {
                          const $f872 = $t862._0;
                          {
                            const e = $f872;
                            {
                              let $t863;
                              {
                                const $rc_70 = ("march: MARCH_GRANT is not a scope list: " + e);
                                $t863 = $rc_70;
                              }
                              {
                                const $rc_69 = Authority$launch_error($t863);
                                return $rc_69;
                              }
                            }
                          }
                          break;
                        }
                        case "Ok": {
                          const $f873 = $t862._0;
                          {
                            const g = $f873;
                            {
                              let $t864;
                              {
                                let $rc_73;
                                $rc_73 = Authority$first_outside(g, req);
                                $t864 = $rc_73;
                              }
                              switch ($t864.$) {
                                case "Some": {
                                  const $f871 = $t864._0;
                                  {
                                    const s = $f871;
                                    {
                                      let $t866;
                                      {
                                        const $t865 = Authority$scope_text(s);
                                        {
                                          const $rc_72 = march_string_concat_n("march: MARCH_GRANT grants ", $t865, ", which main does not request (main requests: ", request, ")");
                                          $t866 = $rc_72;
                                        }
                                      }
                                      {
                                        const $rc_71 = Authority$launch_error($t866);
                                        return $rc_71;
                                      }
                                    }
                                  }
                                  break;
                                }
                                case "None": {
                                  {
                                    let $t868;
                                    {
                                      const $t867 = { $: "ByLaunch" };
                                      $t868 = { $: "Layer", _0: $t867, _1: grant, _2: g };
                                    }
                                    {
                                      const $t869 = { $: "Nil" };
                                      {
                                        const $t870 = { $: "Cons", _0: $t868, _1: $t869 };
                                        return march_cap_set_launch($t870);
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
    const $t876 = (msg + "\n");
    {
      const $rc_74 = march_cap_launch_fail($t876);
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
        const $f878 = a._0;
        const $f879 = a._1;
        {
          const rest = $f879;
          {
            const s = $f878;
            {
              let $t877;
              $t877 = Authority$covered(s, b);
              if ($t877 === true) {
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
        const $f911 = scopes._0;
        const $f912 = scopes._1;
        switch ($f911.$) {
          case "CapEntry": {
            const $f913 = $f911._0;
            const $f914 = $f911._1;
            {
              const rest = $f912;
              {
                const arg = $f914;
                {
                  const k = $f913;
                  {
                    let $t910;
                    {
                      let $t909;
                      {
                        const $rc_79 = Authority$member(chain, k);
                        $t909 = $rc_79;
                      }
                      if ($t909 === true) {
                        $t910 = Authority$arg_admits(arg, kind, target, cwd);
                      } else {
                        $t910 = false;
                      }
                    }
                    if ($t910 === true) {
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
      const $f947 = arg._0;
      {
        const ps = $f947;
        {
          let $t924;
          {
            let $t923;
            {
              let $t1123_i62;
              {
                const $t1122_i61 = (kind === "IO.FileRead");
                if ($t1122_i61 === true) {
                  $t1123_i62 = true;
                } else {
                  $t1123_i62 = (kind === "IO.FileWrite");
                }
              }
              if ($t1123_i62 === true) {
                $t923 = true;
              } else {
                $t923 = (kind === "IO.FileSystem");
              }
            }
            $t924 = (!$t923);
          }
          if ($t924 === true) {
            return false;
          } else {
            {
              let $t927;
              {
                const $t925 = (cwd === "");
                if ($t925 === true) {
                  {
                    const $t926 = march_string_starts_with(target, "/");
                    $t927 = (!$t926);
                  }
                } else {
                  $t927 = false;
                }
              }
              if ($t927 === true) {
                return false;
              } else {
                {
                  const $t928 = Authority$resolve(cwd, target);
                  {
                    let $rc_80;
                    {
                      const $t984_i9679 = march_string_starts_with($t928, "/");
                      {
                        let $t985_i9685;
                        {
                          const $t1126_i75_i9681 = march_string_split($t928, "/");
                          {
                            const $t1127_i76_i9682 = { $: "Nil" };
                            {
                              const $t1128_i77_i9683 = Authority$fold_segments($t1126_i75_i9681, $t1127_i76_i9682);
                              {
                                const $t1129_i78_i9684 = { $: "Nil" };
                                $t985_i9685 = Authority$rev($t1128_i77_i9683, $t1129_i78_i9684);
                              }
                            }
                          }
                        }
                        {
                          const $rc_88_i9686 = Authority$any_within_segs(ps, $t984_i9679, $t985_i9685);
                          $rc_80 = $rc_88_i9686;
                        }
                      }
                    }
                    return $rc_80;
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
      const $f948 = arg._0;
      {
        const spec = $f948;
        {
          const $t929 = (kind === "IO.NetConnect");
          if ($t929 === true) {
            return Authority$host_permits(spec, target);
          } else {
            {
              const $rc_81 = (target === "");
              return $rc_81;
            }
          }
        }
      }
      break;
    }
    case "Names": {
      const $f949 = arg._0;
      const $f950 = arg._1;
      {
        const pre = $f950;
        {
          const ns = $f949;
          {
            let $t930;
            {
              const $t1124_i69 = (kind === "IO.Mut");
              if ($t1124_i69 === true) {
                $t930 = true;
              } else {
                $t930 = (kind === "IO.Registry");
              }
            }
            if ($t930 === true) {
              {
                let $rc_82;
                {
                  const $t1167_i67 = Authority$member(ns, target);
                  if ($t1167_i67 === true) {
                    $rc_82 = true;
                  } else {
                    $rc_82 = Authority$starts_with_any(target, pre);
                  }
                }
                return $rc_82;
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
      const $f955 = arg._0;
      const $f956 = arg._1;
      const $f957 = arg._2;
      const $f958 = arg._3;
      {
        const port = $f958;
        {
          const wild = $f957;
          {
            const h = $f956;
            {
              const $t931 = (kind === "IO.NetConnect");
              if ($t931 === true) {
                {
                  const $t932 = (h === "");
                  if ($t932 === true) {
                    return true;
                  } else {
                    {
                      const $t933 = Authority$split_target(target);
                      const $f934 = $t933._0;
                      const $f935 = $t933._1;
                      {
                        const tp = $f935;
                        {
                          const th = $f934;
                          {
                            const $rc_83 = Authority$host_matches(h, wild, port, th, tp);
                            return $rc_83;
                          }
                        }
                      }
                    }
                  }
                }
              } else {
                {
                  const $rc_84 = (target === "");
                  return $rc_84;
                }
              }
            }
          }
        }
      }
      break;
    }
    case "PathsAt": {
      const $f971 = arg._0;
      {
        const ps = $f971;
        {
          let $t941;
          {
            let $t940;
            {
              let $t1123_i73;
              {
                const $t1122_i72 = (kind === "IO.FileRead");
                if ($t1122_i72 === true) {
                  $t1123_i73 = true;
                } else {
                  $t1123_i73 = (kind === "IO.FileWrite");
                }
              }
              if ($t1123_i73 === true) {
                $t940 = true;
              } else {
                $t940 = (kind === "IO.FileSystem");
              }
            }
            $t941 = (!$t940);
          }
          if ($t941 === true) {
            return false;
          } else {
            {
              let $t944;
              {
                const $t942 = (cwd === "");
                if ($t942 === true) {
                  {
                    const $t943 = march_string_starts_with(target, "/");
                    $t944 = (!$t943);
                  }
                } else {
                  $t944 = false;
                }
              }
              if ($t944 === true) {
                return false;
              } else {
                {
                  let $t946;
                  {
                    const $t945 = Authority$resolve(cwd, target);
                    {
                      const $rc_86 = Authority$normalize($t945);
                      $t946 = $rc_86;
                    }
                  }
                  {
                    const $rc_85 = Authority$any_normal_within(ps, $t946);
                    return $rc_85;
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
        const $f978 = ps._0;
        const $f979 = ps._1;
        {
          const rest = $f979;
          {
            const p = $f978;
            {
              let $t977;
              {
                let $t973;
                {
                  const $t972 = (p === "/");
                  if ($t972 === true) {
                    $t973 = true;
                  } else {
                    $t973 = (n === p);
                  }
                }
                if ($t973 === true) {
                  $t977 = true;
                } else {
                  {
                    const $t974 = march_string_starts_with(n, p);
                    if ($t974 === true) {
                      {
                        let $t976;
                        {
                          const $t975 = march_string_byte_length(p);
                          $t976 = march_string_slice(n, $t975, 1);
                        }
                        {
                          const $rc_87 = ($t976 === "/");
                          $t977 = $rc_87;
                        }
                      }
                    } else {
                      $t977 = false;
                    }
                  }
                }
              }
              if ($t977 === true) {
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
        const $f990 = ps._0;
        const $f991 = ps._1;
        {
          const rest = $f991;
          {
            const s = $f990;
            {
              let $t989;
              {
                let $t987;
                {
                  const $t986 = march_string_starts_with(s, "/");
                  $t987 = ($t986 === abs);
                }
                if ($t987 === true) {
                  {
                    let $t988;
                    {
                      const $t1126_i80 = march_string_split(s, "/");
                      {
                        const $t1127_i81 = { $: "Nil" };
                        {
                          const $t1128_i82 = Authority$fold_segments($t1126_i80, $t1127_i81);
                          {
                            const $t1129_i83 = { $: "Nil" };
                            $t988 = Authority$rev($t1128_i82, $t1129_i83);
                          }
                        }
                      }
                    }
                    {
                      const $rc_89 = Authority$segs_prefix($t988, segs);
                      $t989 = $rc_89;
                    }
                  }
                } else {
                  $t989 = false;
                }
              }
              if ($t989 === true) {
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
        const $f1006 = b._0;
        const $f1007 = b._1;
        switch ($f1006.$) {
          case "CapEntry": {
            const $f1008 = $f1006._0;
            const $f1009 = $f1006._1;
            {
              const rest = $f1007;
              {
                const outer = $f1009;
                {
                  const k = $f1008;
                  switch (s.$) {
                    case "CapEntry": {
                      const $f1000 = s._0;
                      const $f1001 = s._1;
                      {
                        const inner = $f1001;
                        {
                          const ik = $f1000;
                          {
                            let $t999;
                            {
                              let $t998;
                              {
                                const $rc_90 = Authority$kind_subsumes(k, ik);
                                $t998 = $rc_90;
                              }
                              if ($t998 === true) {
                                $t999 = Authority$arg_subsumes(outer, inner);
                              } else {
                                $t999 = false;
                              }
                            }
                            if ($t999 === true) {
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
      const $f1029 = outer._0;
      {
        const o_paths = $f1029;
        {
          const $t1018 = Authority$path_list(inner);
          switch ($t1018.$) {
            case "Some": {
              const $f1019 = $t1018._0;
              {
                const i_paths = $f1019;
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
    case "PathsAt": {
      const $f1030 = outer._0;
      {
        const o_paths = $f1030;
        {
          const $t1020 = Authority$path_list(inner);
          switch ($t1020.$) {
            case "Some": {
              const $f1021 = $t1020._0;
              {
                const i_paths = $f1021;
                {
                  const $rc_92 = Authority$all_paths_within(i_paths, o_paths);
                  return $rc_92;
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
      const $f1031 = outer._0;
      const $f1032 = outer._1;
      {
        const o_pre = $f1032;
        {
          const o_names = $f1031;
          switch (inner.$) {
            case "Names": {
              const $f1023 = inner._0;
              const $f1024 = inner._1;
              {
                const i_pre = $f1024;
                {
                  const i_names = $f1023;
                  {
                    let $t1022;
                    {
                      const $rc_94 = Authority$all_names_admitted(i_names, o_names, o_pre);
                      $t1022 = $rc_94;
                    }
                    if ($t1022 === true) {
                      {
                        const $rc_93 = Authority$all_prefixes_under(i_pre, o_pre);
                        return $rc_93;
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
      const $f1037 = outer._0;
      {
        const o = $f1037;
        {
          const $t1025 = Authority$host_spec(inner);
          switch ($t1025.$) {
            case "Some": {
              const $f1026 = $t1025._0;
              {
                const i = $f1026;
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
    case "HostAt": {
      const $f1038 = outer._0;
      const $f1039 = outer._1;
      const $f1040 = outer._2;
      const $f1041 = outer._3;
      {
        const o = $f1038;
        {
          const $t1027 = Authority$host_spec(inner);
          switch ($t1027.$) {
            case "Some": {
              const $f1028 = $t1027._0;
              {
                const i = $f1028;
                {
                  const $rc_96 = Authority$host_subsumes(o, i);
                  return $rc_96;
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
      const $f1054 = a._0;
      {
        const ps = $f1054;
        return { $: "Some", _0: ps };
      }
      break;
    }
    case "PathsAt": {
      const $f1059 = a._0;
      {
        const ps = $f1059;
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
      const $f1064 = a._0;
      {
        const s = $f1064;
        return { $: "Some", _0: s };
      }
      break;
    }
    case "HostAt": {
      const $f1069 = a._0;
      const $f1070 = a._1;
      const $f1071 = a._2;
      const $f1072 = a._3;
      {
        const s = $f1069;
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
        const $f1090 = i_paths._0;
        const $f1091 = i_paths._1;
        {
          const rest = $f1091;
          {
            const p = $f1090;
            {
              const $t1089 = Authority$path_in_any(p, o_paths);
              if ($t1089 === true) {
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
        const $f1097 = o_paths._0;
        const $f1098 = o_paths._1;
        {
          const rest = $f1098;
          {
            const o = $f1097;
            {
              const $t1096 = Authority$path_within(o, p);
              if ($t1096 === true) {
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
        const $f1104 = ns._0;
        const $f1105 = ns._1;
        {
          const rest = $f1105;
          {
            const n = $f1104;
            {
              let $t1103;
              {
                const $t1167_i87 = Authority$member(o_names, n);
                if ($t1167_i87 === true) {
                  $t1103 = true;
                } else {
                  $t1103 = Authority$starts_with_any(n, o_pre);
                }
              }
              if ($t1103 === true) {
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
        const $f1111 = i_pre._0;
        const $f1112 = i_pre._1;
        {
          const rest = $f1112;
          {
            const p = $f1111;
            {
              const $t1110 = Authority$starts_with_any(p, o_pre);
              if ($t1110 === true) {
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
      } else if (kind === "IO.Cluster") {
        p = "IO";
      } else {
        p = "";
      }
      {
        const $t1117 = (p === "");
        if ($t1117 === true) {
          {
            const $t1118 = { $: "Nil" };
            {
              const $trmc6 = { $: "Cons", _0: kind, _1: $t1118 };
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
      const $t1120 = (parent === child);
      if ($t1120 === true) {
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
          } else if (child === "IO.Cluster") {
            p = "IO";
          } else {
            p = "";
          }
          {
            const $t1121 = (p === "");
            if ($t1121 === true) {
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
    const $t1125 = march_string_starts_with(p, "/");
    if ($t1125 === true) {
      return p;
    } else {
      {
        const $rc_97 = march_string_concat3(cwd, "/", p);
        return $rc_97;
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
        const $f1141 = parts._0;
        const $f1142 = parts._1;
        {
          const rest = $f1142;
          {
            const s = $f1141;
            {
              let $t1131;
              {
                const $t1130 = (s === "");
                if ($t1130 === true) {
                  $t1131 = true;
                } else {
                  $t1131 = (s === ".");
                }
              }
              if ($t1131 === true) {
                {
                  $tco_a0 = rest;
                  $tco_a1 = acc;
                  continue __tco;
                }
              } else {
                {
                  const $t1132 = (s === "..");
                  if ($t1132 === true) {
                    switch (acc.$) {
                      case "Nil": {
                        {
                          const $t1133 = { $: "Nil" };
                          {
                            $tco_a0 = rest;
                            $tco_a1 = $t1133;
                            continue __tco;
                          }
                        }
                        break;
                      }
                      case "Cons": {
                        const $f1134 = acc._0;
                        const $f1135 = acc._1;
                        {
                          const up = $f1135;
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
                      const $t1140 = { $: "Cons", _0: s, _1: acc };
                      {
                        $tco_a0 = rest;
                        $tco_a1 = $t1140;
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
      let $t1147;
      {
        const $t1126_i92 = march_string_split(p, "/");
        {
          const $t1127_i93 = { $: "Nil" };
          {
            const $t1128_i94 = Authority$fold_segments($t1126_i92, $t1127_i93);
            {
              const $t1129_i95 = { $: "Nil" };
              $t1147 = Authority$rev($t1128_i94, $t1129_i95);
            }
          }
        }
      }
      {
        const $rc_99 = march_string_join($t1147, "/");
        body = $rc_99;
      }
    }
    {
      const $t1148 = march_string_starts_with(p, "/");
      if ($t1148 === true) {
        {
          const $rc_98 = ("/" + body);
          return $rc_98;
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
    let $t1151;
    {
      const $t1149 = march_string_starts_with(scope, "/");
      {
        const $t1150 = march_string_starts_with(p, "/");
        $t1151 = ($t1149 === $t1150);
      }
    }
    if ($t1151 === true) {
      {
        let $t1152;
        {
          const $t1126_i102 = march_string_split(scope, "/");
          {
            const $t1127_i103 = { $: "Nil" };
            {
              const $t1128_i104 = Authority$fold_segments($t1126_i102, $t1127_i103);
              {
                const $t1129_i105 = { $: "Nil" };
                $t1152 = Authority$rev($t1128_i104, $t1129_i105);
              }
            }
          }
        }
        {
          let $t1153;
          {
            const $t1126_i97 = march_string_split(p, "/");
            {
              const $t1127_i98 = { $: "Nil" };
              {
                const $t1128_i99 = Authority$fold_segments($t1126_i97, $t1127_i98);
                {
                  const $t1129_i100 = { $: "Nil" };
                  $t1153 = Authority$rev($t1128_i99, $t1129_i100);
                }
              }
            }
          }
          {
            const $rc_100 = Authority$segs_prefix($t1152, $t1153);
            return $rc_100;
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
        const $f1161 = pre._0;
        const $f1162 = pre._1;
        {
          const pt = $f1162;
          {
            const a = $f1161;
            switch (segs.$) {
              case "Nil": {
                return false;
                break;
              }
              case "Cons": {
                const $f1155 = segs._0;
                const $f1156 = segs._1;
                {
                  const st = $f1156;
                  {
                    const b = $f1155;
                    {
                      const $t1154 = (a === b);
                      if ($t1154 === true) {
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
        const $f1169 = pre._0;
        const $f1170 = pre._1;
        {
          const rest = $f1170;
          {
            const p = $f1169;
            {
              const $t1168 = march_string_starts_with(n, p);
              if ($t1168 === true) {
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
      const spec_i9687 = spec;
      {
        const $t1202_i9688 = march_string_index_of(spec, ";");
        switch ($t1202_i9688.$) {
          case "None": {
            raw = spec;
            break;
          }
          case "Some": {
            const $f1203_i9689 = $t1202_i9688._0;
            {
              const i_i9690 = $f1203_i9689;
              {
                const $rc_102_i9691 = march_string_slice(spec, 0, i_i9690);
                raw = $rc_102_i9691;
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
      const $t1175 = (raw === "");
      if ($t1175 === true) {
        return true;
      } else {
        {
          const $t1176 = Authority$parse_host_pattern(raw);
          switch ($t1176.$) {
            case "Err": {
              const $f1184 = $t1176._0;
              return false;
              break;
            }
            case "Ok": {
              const $f1185 = $t1176._0;
              const $f1186 = $f1185._0;
              const $f1187 = $f1185._1;
              const $f1188 = $f1185._2;
              const $f1189 = $f1185._3;
              {
                const port = $f1188;
                {
                  const wild = $f1187;
                  {
                    const h = $f1186;
                    {
                      const $t1177 = Authority$split_target(target);
                      const $f1178 = $t1177._0;
                      const $f1179 = $t1177._1;
                      {
                        const tp = $f1179;
                        {
                          const th = $f1178;
                          {
                            const $rc_101 = Authority$host_matches(h, wild, port, th, tp);
                            return $rc_101;
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
    const $t1204 = march_string_last_index_of(t, ":");
    switch ($t1204.$) {
      case "None": {
        return { _0: t, _1: 0 };
        break;
      }
      case "Some": {
        const $f1212 = $t1204._0;
        {
          const i = $f1212;
          {
            const $t1205 = march_string_slice(t, 0, i);
            {
              let $t1211;
              {
                let $t1210;
                {
                  const $t1206 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                  {
                    let $t1209;
                    {
                      let $t1208;
                      {
                        const $t1207 = march_string_byte_length(t);
                        $t1208 = (($t1207 - i) < 4611686018427387904 && ($t1207 - i) >= -4611686018427387904 ? ($t1207 - i) : march_int_ovf(($t1207 - i), 1));
                      }
                      $t1209 = (($t1208 - 1) < 4611686018427387904 && ($t1208 - 1) >= -4611686018427387904 ? ($t1208 - 1) : march_int_ovf(($t1208 - 1), 1));
                    }
                    {
                      const $rc_104 = march_string_slice(t, $t1206, $t1209);
                      $t1210 = $rc_104;
                    }
                  }
                }
                {
                  const $rc_103 = Authority$port_or_zero($t1210);
                  $t1211 = $rc_103;
                }
              }
              return { _0: $t1205, _1: $t1211 };
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
      let $t1215;
      {
        const $t1213 = (port !== 0);
        {
          const $t1214 = (port !== tport);
          $t1215 = ($t1213 && $t1214);
        }
      }
      if ($t1215 === true) {
        return false;
      } else {
        if (wild === true) {
          {
            const suffix = ("." + h);
            {
              let $t1218;
              {
                const $t1216 = march_string_byte_length(th);
                {
                  const $t1217 = march_string_byte_length(suffix);
                  $t1218 = ($t1216 > $t1217);
                }
              }
              if ($t1218 === true) {
                {
                  const $rc_105 = march_string_ends_with(th, suffix);
                  return $rc_105;
                }
              } else {
                return false;
              }
            }
          }
        } else {
          {
            const $rc_106 = (th === h);
            return $rc_106;
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
      const $t1219 = march_string_ends_with(l, ".");
      if ($t1219 === true) {
        {
          let $t1221;
          {
            const $t1220 = march_string_byte_length(l);
            $t1221 = (($t1220 - 1) < 4611686018427387904 && ($t1220 - 1) >= -4611686018427387904 ? ($t1220 - 1) : march_int_ovf(($t1220 - 1), 1));
          }
          {
            const $rc_107 = march_string_slice(l, 0, $t1221);
            return $rc_107;
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
    let $t1226;
    {
      let $t1224;
      {
        const $t1222 = (s === "");
        if ($t1222 === true) {
          $t1224 = true;
        } else {
          {
            const $t1223 = march_string_byte_length(s);
            $t1224 = ($t1223 > 5);
          }
        }
      }
      if ($t1224 === true) {
        $t1226 = true;
      } else {
        {
          const $t1225 = Authority$all_chars(s, "0123456789", 0);
          $t1226 = (!$t1225);
        }
      }
    }
    if ($t1226 === true) {
      return 0;
    } else {
      {
        const $t1227 = march_string_to_int(s);
        switch ($t1227.$) {
          case "Some": {
            const $f1231 = $t1227._0;
            {
              const n = $f1231;
              {
                let $t1230;
                {
                  const $t1228 = (n >= 1);
                  {
                    const $t1229 = (n <= 65535);
                    $t1230 = ($t1228 && $t1229);
                  }
                }
                if ($t1230 === true) {
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
      let $t1233;
      {
        const $t1232 = march_string_byte_length(s);
        $t1233 = (i >= $t1232);
      }
      if ($t1233 === true) {
        return true;
      } else {
        {
          let $t1235;
          {
            const $t1234 = march_string_slice(s, i, 1);
            {
              const $rc_108 = march_string_contains(allowed, $t1234);
              $t1235 = $rc_108;
            }
          }
          if ($t1235 === true) {
            {
              const $t1236 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
              {
                $tco_a0 = s;
                $tco_a1 = allowed;
                $tco_a2 = $t1236;
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
    const $t1237 = (raw === "");
    if ($t1237 === true) {
      return { $: "Err", _0: "a host scope cannot be empty" };
    } else {
      {
        const $t1238 = march_string_contains(raw, "://");
        if ($t1238 === true) {
          return { $: "Err", _0: "a host scope names a host, not a URL: drop the scheme (`https://`)" };
        } else {
          {
            let $p1251;
            {
              const $t1239 = march_string_index_of(raw, "/");
              switch ($t1239.$) {
                case "None": {
                  {
                    let $t1241;
                    {
                      const $t1240 = { $: "None" };
                      $t1241 = { $: "Ok", _0: $t1240 };
                    }
                    $p1251 = { _0: raw, _1: $t1241 };
                  }
                  break;
                }
                case "Some": {
                  const $f1247 = $t1239._0;
                  {
                    const i = $f1247;
                    {
                      const $t1242 = march_string_slice(raw, 0, i);
                      {
                        let $t1246;
                        {
                          let $t1245;
                          {
                            let $t1244;
                            {
                              const $t1243 = march_string_byte_length(raw);
                              $t1244 = (($t1243 - i) < 4611686018427387904 && ($t1243 - i) >= -4611686018427387904 ? ($t1243 - i) : march_int_ovf(($t1243 - i), 1));
                            }
                            {
                              const $rc_112 = march_string_slice(raw, i, $t1244);
                              $t1245 = $rc_112;
                            }
                          }
                          {
                            const $rc_111 = Authority$parse_scope_path($t1245);
                            $t1246 = $rc_111;
                          }
                        }
                        $p1251 = { _0: $t1242, _1: $t1246 };
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
              const host_raw = $p1251._0;
              {
                const path_r = $p1251._1;
                switch (path_r.$) {
                  case "Err": {
                    const $f1249 = path_r._0;
                    {
                      const e = $f1249;
                      {
                        const $rc_110 = { $: "Err", _0: e };
                        return $rc_110;
                      }
                    }
                    break;
                  }
                  case "Ok": {
                    const $f1250 = path_r._0;
                    {
                      const path = $f1250;
                      {
                        const $t1248 = march_string_to_lowercase(host_raw);
                        return Authority$host_part_pattern($t1248, path);
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
    const $t1252 = (s === "");
    if ($t1252 === true) {
      return { $: "Err", _0: "a host scope needs a host before its path" };
    } else {
      {
        const $t1253 = march_string_contains(s, "@");
        if ($t1253 === true) {
          return { $: "Err", _0: "a host scope cannot carry userinfo (`user@`)" };
        } else {
          {
            const $p1278 = Authority$split_host_port(s);
            {
              const host_part = $p1278._0;
              {
                const port_text = $p1278._1;
                {
                  let port;
                  {
                    const $t1254 = (port_text === "");
                    if ($t1254 === true) {
                      port = 0;
                    } else {
                      port = Authority$port_or_zero(port_text);
                    }
                  }
                  {
                    let $t1257;
                    {
                      const $t1255 = (port_text !== "");
                      {
                        const $t1256 = (port === 0);
                        $t1257 = ($t1255 && $t1256);
                      }
                    }
                    if ($t1257 === true) {
                      {
                        const $t1258 = march_string_concat3("`", port_text, "` is not a port (1-65535)");
                        {
                          const $rc_126 = { $: "Err", _0: $t1258 };
                          return $rc_126;
                        }
                      }
                    } else {
                      {
                        const $t1259 = march_string_starts_with(host_part, "[");
                        if ($t1259 === true) {
                          {
                            const n = march_string_byte_length(host_part);
                            {
                              let $t1264;
                              {
                                let $t1261;
                                {
                                  const $t1260 = (n >= 2);
                                  if ($t1260 === true) {
                                    $t1261 = march_string_ends_with(host_part, "]");
                                  } else {
                                    $t1261 = false;
                                  }
                                }
                                if ($t1261 === true) {
                                  {
                                    let $t1263;
                                    {
                                      const $t1262 = ((n - 2) < 4611686018427387904 && (n - 2) >= -4611686018427387904 ? (n - 2) : march_int_ovf((n - 2), 1));
                                      $t1263 = march_string_slice(host_part, 1, $t1262);
                                    }
                                    {
                                      let $rc_113;
                                      {
                                        const $t1306_i107 = ($t1263 !== "");
                                        if ($t1306_i107 === true) {
                                          $rc_113 = Authority$all_chars($t1263, "0123456789abcdef:.", 0);
                                        } else {
                                          $rc_113 = false;
                                        }
                                      }
                                      $t1264 = $rc_113;
                                    }
                                  }
                                } else {
                                  $t1264 = false;
                                }
                              }
                              if ($t1264 === true) {
                                {
                                  let $t1265;
                                  $t1265 = { _0: host_part, _1: false, _2: port, _3: path };
                                  {
                                    const $rc_125 = { $: "Ok", _0: $t1265 };
                                    return $rc_125;
                                  }
                                }
                              } else {
                                {
                                  const $t1266 = march_string_concat3("`", host_part, "` is not an IPv6 literal");
                                  {
                                    const $rc_124 = { $: "Err", _0: $t1266 };
                                    return $rc_124;
                                  }
                                }
                              }
                            }
                          }
                        } else {
                          {
                            let wild;
                            {
                              let $t1268;
                              {
                                const $t1267 = march_string_byte_length(host_part);
                                $t1268 = ($t1267 >= 2);
                              }
                              if ($t1268 === true) {
                                wild = march_string_starts_with(host_part, "*.");
                              } else {
                                wild = false;
                              }
                            }
                            {
                              let name;
                              {
                                let $t1271;
                                if (wild === true) {
                                  {
                                    let $t1270;
                                    {
                                      const $t1269 = march_string_byte_length(host_part);
                                      $t1270 = (($t1269 - 2) < 4611686018427387904 && ($t1269 - 2) >= -4611686018427387904 ? ($t1269 - 2) : march_int_ovf(($t1269 - 2), 1));
                                    }
                                    $t1271 = march_string_slice(host_part, 2, $t1270);
                                  }
                                } else {
                                  $t1271 = host_part;
                                }
                                {
                                  const $rc_114 = Authority$normalize_host($t1271);
                                  name = $rc_114;
                                }
                              }
                              {
                                let $t1273;
                                {
                                  const $t1272 = march_string_contains(name, "*");
                                  if ($t1272 === true) {
                                    $t1273 = true;
                                  } else {
                                    $t1273 = (host_part === "*");
                                  }
                                }
                                if ($t1273 === true) {
                                  {
                                    const $rc_123 = { $: "Err", _0: "a wildcard must be the whole leftmost label (`*.example.com`)" };
                                    return $rc_123;
                                  }
                                } else {
                                  {
                                    let $t1275;
                                    {
                                      let $t1274;
                                      {
                                        const $t1307_i9693 = (name !== "");
                                        if ($t1307_i9693 === true) {
                                          {
                                            const $t1308_i9694 = march_string_split(name, ".");
                                            {
                                              const $rc_131_i9695 = Authority$labels_ok($t1308_i9694);
                                              $t1274 = $rc_131_i9695;
                                            }
                                          }
                                        } else {
                                          $t1274 = false;
                                        }
                                      }
                                      $t1275 = (!$t1274);
                                    }
                                    if ($t1275 === true) {
                                      {
                                        const $t1276 = march_string_concat3("`", host_part, "` is not a host name: labels are letters, digits and `-`, separated by single dots");
                                        {
                                          const $rc_122 = { $: "Err", _0: $t1276 };
                                          return $rc_122;
                                        }
                                      }
                                    } else {
                                      {
                                        const $t1277 = { _0: name, _1: wild, _2: port, _3: path };
                                        {
                                          const $rc_121 = { $: "Ok", _0: $t1277 };
                                          return $rc_121;
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
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
    const $t1279 = march_string_starts_with(s, "[");
    if ($t1279 === true) {
      {
        const $t1280 = march_string_index_of(s, "]");
        switch ($t1280.$) {
          case "None": {
            return { _0: s, _1: "" };
            break;
          }
          case "Some": {
            const $f1295 = $t1280._0;
            {
              const i = $f1295;
              {
                let rest;
                {
                  const $t1281 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                  {
                    let $t1284;
                    {
                      let $t1283;
                      {
                        const $t1282 = march_string_byte_length(s);
                        $t1283 = (($t1282 - i) < 4611686018427387904 && ($t1282 - i) >= -4611686018427387904 ? ($t1282 - i) : march_int_ovf(($t1282 - i), 1));
                      }
                      $t1284 = (($t1283 - 1) < 4611686018427387904 && ($t1283 - 1) >= -4611686018427387904 ? ($t1283 - 1) : march_int_ovf(($t1283 - 1), 1));
                    }
                    rest = march_string_slice(s, $t1281, $t1284);
                  }
                }
                {
                  const $t1285 = (rest === "");
                  if ($t1285 === true) {
                    {
                      let $t1287;
                      {
                        const $t1286 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                        {
                          const $rc_127 = march_string_slice(s, 0, $t1286);
                          $t1287 = $rc_127;
                        }
                      }
                      return { _0: $t1287, _1: "" };
                    }
                  } else {
                    {
                      const $t1288 = march_string_starts_with(rest, ":");
                      if ($t1288 === true) {
                        {
                          let $t1290;
                          {
                            const $t1289 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                            {
                              const $rc_129 = march_string_slice(s, 0, $t1289);
                              $t1290 = $rc_129;
                            }
                          }
                          {
                            let $t1294;
                            {
                              let $t1293;
                              {
                                let $t1292;
                                {
                                  const $t1291 = march_string_byte_length(rest);
                                  $t1292 = (($t1291 - 1) < 4611686018427387904 && ($t1291 - 1) >= -4611686018427387904 ? ($t1291 - 1) : march_int_ovf(($t1291 - 1), 1));
                                }
                                {
                                  const $rc_128 = march_string_slice(rest, 1, $t1292);
                                  $t1293 = $rc_128;
                                }
                              }
                              $t1294 = Authority$port_text_of($t1293);
                            }
                            return { _0: $t1290, _1: $t1294 };
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
        const $t1296 = march_string_last_index_of(s, ":");
        switch ($t1296.$) {
          case "None": {
            return { _0: s, _1: "" };
            break;
          }
          case "Some": {
            const $f1304 = $t1296._0;
            {
              const i = $f1304;
              {
                const $t1297 = march_string_slice(s, 0, i);
                {
                  let $t1303;
                  {
                    let $t1302;
                    {
                      const $t1298 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                      {
                        let $t1301;
                        {
                          let $t1300;
                          {
                            const $t1299 = march_string_byte_length(s);
                            $t1300 = (($t1299 - i) < 4611686018427387904 && ($t1299 - i) >= -4611686018427387904 ? ($t1299 - i) : march_int_ovf(($t1299 - i), 1));
                          }
                          $t1301 = (($t1300 - 1) < 4611686018427387904 && ($t1300 - 1) >= -4611686018427387904 ? ($t1300 - 1) : march_int_ovf(($t1300 - 1), 1));
                        }
                        {
                          const $rc_130 = march_string_slice(s, $t1298, $t1301);
                          $t1302 = $rc_130;
                        }
                      }
                    }
                    $t1303 = Authority$port_text_of($t1302);
                  }
                  return { _0: $t1297, _1: $t1303 };
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
    const $t1305 = (p === "");
    if ($t1305 === true) {
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
        const $f1311 = ls._0;
        const $f1312 = ls._1;
        {
          const rest = $f1312;
          {
            const l = $f1311;
            {
              let $t1310;
              {
                const $t1309 = (l !== "");
                if ($t1309 === true) {
                  $t1310 = Authority$all_chars(l, "abcdefghijklmnopqrstuvwxyz0123456789-", 0);
                } else {
                  $t1310 = false;
                }
              }
              if ($t1310 === true) {
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
    const $t1317 = march_string_split(p, "/");
    {
      let $t1318;
      {
        const l_i9703 = $t1317;
        switch (l_i9703.$) {
          case "Cons": {
            const $f1328_i9704 = l_i9703._0;
            const $f1329_i9705 = l_i9703._1;
            {
              const rest_i9706 = $f1329_i9705;
              $t1318 = rest_i9706;
            }
            break;
          }
          case "Nil": {
            $t1318 = { $: "Nil" };
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
          const l_i9696 = $t1318;
          {
            const $t1334_i9697 = { $: "Nil" };
            {
              let $t1335_i9698;
              $t1335_i9698 = Authority$rev($t1318, $t1334_i9697);
              switch ($t1335_i9698.$) {
                case "Cons": {
                  const $f1337_i9699 = $t1335_i9698._0;
                  const $f1338_i9700 = $t1335_i9698._1;
                  if ($f1337_i9699 === "") {
                    {
                      const r_i9701 = $f1338_i9700;
                      {
                        const $t1336_i9702 = { $: "Nil" };
                        parts = Authority$rev(r_i9701, $t1336_i9702);
                      }
                    }
                  } else {
                    parts = $t1318;
                  }
                  break;
                }
                default: {
                  parts = $t1318;
                  break;
                }
              }
            }
          }
        }
        {
          let $t1319;
          $t1319 = Authority$bad_scope_segment(parts);
          switch ($t1319.$) {
            case "None": {
              {
                const $t1320 = { $: "Some", _0: parts };
                return { $: "Ok", _0: $t1320 };
              }
              break;
            }
            case "Some": {
              const $f1325 = $t1319._0;
              if ($f1325 === "") {
                return { $: "Err", _0: "a path scope cannot contain `//`" };
              } else {
                {
                  const seg = $f1325;
                  {
                    let $t1322;
                    {
                      const $t1321 = (seg === ".");
                      if ($t1321 === true) {
                        $t1322 = true;
                      } else {
                        $t1322 = (seg === "..");
                      }
                    }
                    if ($t1322 === true) {
                      {
                        let $t1323;
                        {
                          const $rc_132 = march_string_concat3("a path scope cannot contain a `", seg, "` segment");
                          $t1323 = $rc_132;
                        }
                        return { $: "Err", _0: $t1323 };
                      }
                    } else {
                      {
                        let $t1324;
                        {
                          const $rc_133 = march_string_concat3("the path segment `", seg, "` may contain only letters, digits, `-`, `_`, `.` and `~` (no `%`, `?`, `#` or `\\`)");
                          $t1324 = $rc_133;
                        }
                        return { $: "Err", _0: $t1324 };
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
        const $f1344 = segs._0;
        const $f1345 = segs._1;
        {
          const rest = $f1345;
          {
            const s = $f1344;
            {
              let $t1343;
              {
                let $t1341;
                {
                  let $t1340;
                  {
                    const $t1339 = (s === "");
                    if ($t1339 === true) {
                      $t1340 = true;
                    } else {
                      $t1340 = (s === ".");
                    }
                  }
                  if ($t1340 === true) {
                    $t1341 = true;
                  } else {
                    $t1341 = (s === "..");
                  }
                }
                if ($t1341 === true) {
                  $t1343 = true;
                } else {
                  {
                    const $t1342 = Authority$all_chars(s, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~", 0);
                    $t1343 = (!$t1342);
                  }
                }
              }
              if ($t1343 === true) {
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
          const $t1350 = { _0: nr, _1: mg, _2: ms };
          return { $: "Ok", _0: $t1350 };
        }
        break;
      }
      case "Cons": {
        const $f1362 = opts._0;
        const $f1363 = opts._1;
        {
          const rest = $f1363;
          {
            const o = $f1362;
            {
              const $t1351 = (o === "no_redirects");
              if ($t1351 === true) {
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
                  const $t1352 = march_string_starts_with(o, "methods=");
                  if ($t1352 === true) {
                    if (mg === true) {
                      return { $: "Err", _0: "`methods(...)` is given twice" };
                    } else {
                      {
                        let v;
                        {
                          let $t1354;
                          {
                            const $t1353 = march_string_byte_length(o);
                            $t1354 = (($t1353 - 8) < 4611686018427387904 && ($t1353 - 8) >= -4611686018427387904 ? ($t1353 - 8) : march_int_ovf(($t1353 - 8), 1));
                          }
                          v = march_string_slice(o, 8, $t1354);
                        }
                        {
                          let $t1356;
                          {
                            const $t1355 = march_string_split(v, ",");
                            $t1356 = Authority$bad_method($t1355);
                          }
                          switch ($t1356.$) {
                            case "None": {
                              {
                                const $t1357 = (v === "");
                                if ($t1357 === true) {
                                  return { $: "Err", _0: "`methods(...)` needs at least one method" };
                                } else {
                                  {
                                    let $t1358;
                                    {
                                      const $rc_134 = march_string_split(v, ",");
                                      $t1358 = $rc_134;
                                    }
                                    {
                                      $tco_a0 = rest;
                                      $tco_a1 = nr;
                                      $tco_a2 = true;
                                      $tco_a3 = $t1358;
                                      continue __tco;
                                    }
                                  }
                                }
                              }
                              break;
                            }
                            case "Some": {
                              const $f1360 = $t1356._0;
                              {
                                const m = $f1360;
                                {
                                  let $t1359;
                                  {
                                    const $rc_135 = march_string_concat3("`", m, "` is not an HTTP method a scope can name; use `get`, `head`, `post`, `put`, `patch`, `delete`, `options`");
                                    $t1359 = $rc_135;
                                  }
                                  return { $: "Err", _0: $t1359 };
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
                      const $t1361 = march_string_concat3("unknown option `", o, "`: the options are `no_redirects` and `methods(...)`");
                      return { $: "Err", _0: $t1361 };
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
        const $f1377 = ms._0;
        const $f1378 = ms._1;
        {
          const rest = $f1378;
          {
            const m = $f1377;
            {
              let $t1376;
              {
                const $t1368 = { $: "Nil" };
                {
                  const $t1369 = { $: "Cons", _0: "options", _1: $t1368 };
                  {
                    const $t1370 = { $: "Cons", _0: "delete", _1: $t1369 };
                    {
                      const $t1371 = { $: "Cons", _0: "patch", _1: $t1370 };
                      {
                        const $t1372 = { $: "Cons", _0: "put", _1: $t1371 };
                        {
                          const $t1373 = { $: "Cons", _0: "post", _1: $t1372 };
                          {
                            const $t1374 = { $: "Cons", _0: "head", _1: $t1373 };
                            {
                              const $t1375 = { $: "Cons", _0: "get", _1: $t1374 };
                              {
                                const $rc_136 = Authority$member($t1375, m);
                                $t1376 = $rc_136;
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              if ($t1376 === true) {
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
    const $t1383 = march_string_split(spec, ";");
    switch ($t1383.$) {
      case "Nil": {
        return { $: "Err", _0: "a host scope cannot be empty" };
        break;
      }
      case "Cons": {
        const $f1410 = $t1383._0;
        const $f1411 = $t1383._1;
        {
          const opts = $f1411;
          {
            const p = $f1410;
            {
              let $t1385;
              {
                const $t1384 = (p === "");
                if ($t1384 === true) {
                  switch (opts.$) {
                    case "Nil": {
                      $t1385 = true;
                      break;
                    }
                    default: {
                      $t1385 = false;
                      break;
                    }
                  }
                } else {
                  $t1385 = false;
                }
              }
              if ($t1385 === true) {
                return { $: "Err", _0: "a host scope cannot be empty" };
              } else {
                {
                  let pat_ok;
                  {
                    const $t1386 = (p === "");
                    if ($t1386 === true) {
                      {
                        const $t1387 = {  };
                        pat_ok = { $: "Ok", _0: $t1387 };
                      }
                    } else {
                      {
                        let $t1388;
                        $t1388 = Authority$parse_host_pattern(p);
                        switch ($t1388.$) {
                          case "Ok": {
                            const $f1390 = $t1388._0;
                            {
                              const $t1389 = {  };
                              pat_ok = { $: "Ok", _0: $t1389 };
                            }
                            break;
                          }
                          case "Err": {
                            const $f1391 = $t1388._0;
                            {
                              const e = $f1391;
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
                      const $f1408 = pat_ok._0;
                      {
                        const e = $f1408;
                        return { $: "Err", _0: e };
                      }
                      break;
                    }
                    case "Ok": {
                      const $f1409 = pat_ok._0;
                      {
                        let $t1393;
                        {
                          const $t1392 = { $: "Nil" };
                          {
                            const $rc_137 = Authority$host_options(opts, false, false, $t1392);
                            $t1393 = $rc_137;
                          }
                        }
                        switch ($t1393.$) {
                          case "Err": {
                            const $f1395 = $t1393._0;
                            {
                              const e = $f1395;
                              return { $: "Err", _0: e };
                            }
                            break;
                          }
                          case "Ok": {
                            const $f1396 = $t1393._0;
                            const $f1397 = $f1396._0;
                            const $f1398 = $f1396._1;
                            const $f1399 = $f1396._2;
                            {
                              const ms = $f1399;
                              {
                                const mg = $f1398;
                                {
                                  const nr = $f1397;
                                  {
                                    const $t1394 = { _0: p, _1: nr, _2: mg, _3: ms };
                                    return { $: "Ok", _0: $t1394 };
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
    const $t1416 = Authority$host_decl(o);
    {
      const $t1417 = Authority$host_decl(i);
      {
        const $t1418 = { _0: $t1416, _1: $t1417 };
        const $f1425 = $t1418._0;
        const $f1426 = $t1418._1;
        switch ($f1425.$) {
          case "Ok": {
            const $f1427 = $f1425._0;
            const $f1428 = $f1427._0;
            const $f1429 = $f1427._1;
            const $f1430 = $f1427._2;
            const $f1431 = $f1427._3;
            switch ($f1426.$) {
              case "Ok": {
                const $f1432 = $f1426._0;
                const $f1433 = $f1432._0;
                const $f1434 = $f1432._1;
                const $f1435 = $f1432._2;
                const $f1436 = $f1432._3;
                {
                  const ims = $f1436;
                  {
                    const img = $f1435;
                    {
                      const inr = $f1434;
                      {
                        const i_pre = $f1433;
                        {
                          const oms = $f1431;
                          {
                            const omg = $f1430;
                            {
                              const onr = $f1429;
                              {
                                const o_pre = $f1428;
                                {
                                  let $t1422;
                                  {
                                    let $t1420;
                                    {
                                      const $t1419 = (!onr);
                                      $t1420 = ($t1419 || inr);
                                    }
                                    if ($t1420 === true) {
                                      {
                                        const $t1421 = (!omg);
                                        if ($t1421 === true) {
                                          $t1422 = true;
                                        } else {
                                          if (img === true) {
                                            {
                                              const $rc_138 = Authority$all_member(ims, oms);
                                              $t1422 = $rc_138;
                                            }
                                          } else {
                                            $t1422 = false;
                                          }
                                        }
                                      }
                                    } else {
                                      $t1422 = false;
                                    }
                                  }
                                  if ($t1422 === true) {
                                    {
                                      const $t1423 = (o_pre === "");
                                      if ($t1423 === true) {
                                        return true;
                                      } else {
                                        {
                                          const $t1424 = (i_pre !== "");
                                          if ($t1424 === true) {
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
    const $t1437 = Authority$parse_host_pattern(o);
    {
      const $t1438 = Authority$parse_host_pattern(i);
      {
        const $t1439 = { _0: $t1437, _1: $t1438 };
        const $f1448 = $t1439._0;
        const $f1449 = $t1439._1;
        switch ($f1448.$) {
          case "Ok": {
            const $f1450 = $f1448._0;
            const $f1451 = $f1450._0;
            const $f1452 = $f1450._1;
            const $f1453 = $f1450._2;
            const $f1454 = $f1450._3;
            switch ($f1449.$) {
              case "Ok": {
                const $f1455 = $f1449._0;
                const $f1456 = $f1455._0;
                const $f1457 = $f1455._1;
                const $f1458 = $f1455._2;
                const $f1459 = $f1455._3;
                {
                  const ipath = $f1459;
                  {
                    const iport = $f1458;
                    {
                      const iw = $f1457;
                      {
                        const ih = $f1456;
                        {
                          const opath = $f1454;
                          {
                            const oport = $f1453;
                            {
                              const ow = $f1452;
                              {
                                const oh = $f1451;
                                {
                                  let host_ok;
                                  if (ow === true) {
                                    {
                                      let $t1440;
                                      if (iw === true) {
                                        $t1440 = (ih === oh);
                                      } else {
                                        $t1440 = false;
                                      }
                                      if ($t1440 === true) {
                                        host_ok = true;
                                      } else {
                                        {
                                          let $t1441;
                                          {
                                            const $rc_141 = ("." + oh);
                                            $t1441 = $rc_141;
                                          }
                                          {
                                            const $rc_140 = march_string_ends_with(ih, $t1441);
                                            host_ok = $rc_140;
                                          }
                                        }
                                      }
                                    }
                                  } else {
                                    {
                                      const $t1442 = (!iw);
                                      if ($t1442 === true) {
                                        {
                                          const $rc_142 = (ih === oh);
                                          host_ok = $rc_142;
                                        }
                                      } else {
                                        host_ok = false;
                                      }
                                    }
                                  }
                                  {
                                    let port_ok;
                                    {
                                      const $t1443 = (oport === 0);
                                      {
                                        const $t1444 = (oport === iport);
                                        port_ok = ($t1443 || $t1444);
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
                                          const $f1446 = opath._0;
                                          {
                                            const o_paths = $f1446;
                                            switch (ipath.$) {
                                              case "None": {
                                                path_ok = false;
                                                break;
                                              }
                                              case "Some": {
                                                const $f1445 = ipath._0;
                                                {
                                                  const i_paths = $f1445;
                                                  {
                                                    const $rc_139 = Authority$segs_prefix(o_paths, i_paths);
                                                    path_ok = $rc_139;
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
                                        const $t1447 = (host_ok && port_ok);
                                        return ($t1447 && path_ok);
                                      }
                                    }
                                  }
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
    let $t1462;
    {
      const $t1460 = march_string_byte_length(text);
      {
        const $t1461 = { $: "Nil" };
        $t1462 = Authority$tokenize(text, 0, $t1460, $t1461);
      }
    }
    switch ($t1462.$) {
      case "Err": {
        const $f1482 = $t1462._0;
        {
          const e = $f1482;
          return { $: "Err", _0: e };
        }
        break;
      }
      case "Ok": {
        const $f1483 = $t1462._0;
        {
          const toks = $f1483;
          switch (toks.$) {
            case "Nil": {
              {
                const $t1463 = { $: "Nil" };
                return { $: "Ok", _0: $t1463 };
              }
              break;
            }
            case "Cons": {
              const $f1468 = toks._0;
              const $f1469 = toks._1;
              {
                const $jp_clo1471 = { $: "$Clo_$jp1_Authority_parse$0_Authority_parse", _0: $jp1_Authority_parse$apply$0_Authority_parse, _1: toks };
                if ($f1468 === "(") {
                  {
                    const $jp_clo1473 = { $: "$Clo_$jp2_Authority_parse$1_Authority_parse", _0: $jp2_Authority_parse$apply$1_Authority_parse, _1: $jp_clo1471 };
                    switch ($f1469.$) {
                      case "Cons": {
                        const $f1474 = $f1469._0;
                        const $f1475 = $f1469._1;
                        {
                          const $jp_clo1477 = { $: "$Clo_$jp3_Authority_parse$2_Authority_parse", _0: $jp3_Authority_parse$apply$2_Authority_parse, _1: $jp_clo1473 };
                          if ($f1474 === ")") {
                            switch ($f1475.$) {
                              case "Nil": {
                                {
                                  const $t1464 = { $: "Nil" };
                                  return { $: "Ok", _0: $t1464 };
                                }
                                break;
                              }
                              default: {
                                return $jp3_Authority_parse$apply$2_Authority_parse($jp_clo1477);
                              }
                            }
                          } else {
                            return $jp3_Authority_parse$apply$2_Authority_parse($jp_clo1477);
                          }
                        }
                        break;
                      }
                      default: {
                        return $jp2_Authority_parse$apply$1_Authority_parse($jp_clo1473);
                      }
                    }
                  }
                } else {
                  return $jp1_Authority_parse$apply$0_Authority_parse($jp_clo1471);
                }
              }
              break;
            }
            default: {
              {
                const $t1465 = { $: "Nil" };
                return Authority$parse_entries(toks, $t1465);
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
      const $t1484 = (i >= n);
      if ($t1484 === true) {
        {
          const $t1485 = { $: "Nil" };
          {
            const $t1486 = Authority$rev(acc, $t1485);
            return { $: "Ok", _0: $t1486 };
          }
        }
      } else {
        {
          const c = march_string_slice(s, i, 1);
          {
            let $t1490;
            {
              let $t1489;
              {
                let $t1488;
                {
                  const $t1487 = (c === " ");
                  if ($t1487 === true) {
                    $t1488 = true;
                  } else {
                    $t1488 = (c === "\t");
                  }
                }
                if ($t1488 === true) {
                  $t1489 = true;
                } else {
                  $t1489 = (c === "\n");
                }
              }
              if ($t1489 === true) {
                $t1490 = true;
              } else {
                $t1490 = (c === "\r");
              }
            }
            if ($t1490 === true) {
              {
                const $t1491 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                {
                  $tco_a0 = s;
                  $tco_a1 = $t1491;
                  $tco_a2 = n;
                  $tco_a3 = acc;
                  continue __tco;
                }
              }
            } else {
              {
                let $t1494;
                {
                  let $t1493;
                  {
                    const $t1492 = (c === "(");
                    if ($t1492 === true) {
                      $t1493 = true;
                    } else {
                      $t1493 = (c === ")");
                    }
                  }
                  if ($t1493 === true) {
                    $t1494 = true;
                  } else {
                    $t1494 = (c === ",");
                  }
                }
                if ($t1494 === true) {
                  {
                    const $t1495 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                    {
                      const $t1496 = { $: "Cons", _0: c, _1: acc };
                      {
                        $tco_a0 = s;
                        $tco_a1 = $t1495;
                        $tco_a2 = n;
                        $tco_a3 = $t1496;
                        continue __tco;
                      }
                    }
                  }
                } else {
                  {
                    const $t1497 = (c === "\"");
                    if ($t1497 === true) {
                      {
                        let $t1499;
                        {
                          const $t1498 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                          $t1499 = Authority$read_string(s, $t1498, n, "");
                        }
                        switch ($t1499.$) {
                          case "Err": {
                            const $f1502 = $t1499._0;
                            {
                              const e = $f1502;
                              return { $: "Err", _0: e };
                            }
                            break;
                          }
                          case "Ok": {
                            const $f1503 = $t1499._0;
                            const $f1504 = $f1503._0;
                            const $f1505 = $f1503._1;
                            {
                              const j = $f1505;
                              {
                                const str = $f1504;
                                {
                                  let $t1500;
                                  {
                                    const $rc_143 = ("\"" + str);
                                    $t1500 = $rc_143;
                                  }
                                  {
                                    const $t1501 = { $: "Cons", _0: $t1500, _1: acc };
                                    {
                                      $tco_a0 = s;
                                      $tco_a1 = j;
                                      $tco_a2 = n;
                                      $tco_a3 = $t1501;
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
                        let $t1510;
                        {
                          const $t1515_i110 = (c !== "");
                          if ($t1515_i110 === true) {
                            $t1510 = march_string_contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.", c);
                          } else {
                            $t1510 = false;
                          }
                        }
                        if ($t1510 === true) {
                          {
                            const j = Authority$word_end(s, i, n);
                            {
                              let $t1512;
                              {
                                const $t1511 = ((j - i) < 4611686018427387904 && (j - i) >= -4611686018427387904 ? (j - i) : march_int_ovf((j - i), 1));
                                $t1512 = march_string_slice(s, i, $t1511);
                              }
                              {
                                const $t1513 = { $: "Cons", _0: $t1512, _1: acc };
                                {
                                  $tco_a0 = s;
                                  $tco_a1 = j;
                                  $tco_a2 = n;
                                  $tco_a3 = $t1513;
                                  continue __tco;
                                }
                              }
                            }
                          }
                        } else {
                          {
                            let $t1514;
                            {
                              const $rc_144 = march_string_concat3("unexpected `", c, "`");
                              $t1514 = $rc_144;
                            }
                            return { $: "Err", _0: $t1514 };
                          }
                        }
                      }
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
      let $t1518;
      {
        const $t1516 = (i < n);
        if ($t1516 === true) {
          {
            const $t1517 = march_string_slice(s, i, 1);
            {
              let $rc_145;
              {
                const $t1515_i112 = ($t1517 !== "");
                if ($t1515_i112 === true) {
                  $rc_145 = march_string_contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.", $t1517);
                } else {
                  $rc_145 = false;
                }
              }
              $t1518 = $rc_145;
            }
          }
        } else {
          $t1518 = false;
        }
      }
      if ($t1518 === true) {
        {
          const $t1519 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
          {
            $tco_a0 = s;
            $tco_a1 = $t1519;
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
      const $t1520 = (i >= n);
      if ($t1520 === true) {
        return { $: "Err", _0: "a string is not closed" };
      } else {
        {
          const c = march_string_slice(s, i, 1);
          {
            const $t1521 = (c === "\"");
            if ($t1521 === true) {
              {
                const $t1522 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                {
                  const $t1523 = { _0: acc, _1: $t1522 };
                  return { $: "Ok", _0: $t1523 };
                }
              }
            } else {
              {
                const $t1524 = (c === "\\");
                if ($t1524 === true) {
                  {
                    let $t1526;
                    {
                      const $t1525 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                      $t1526 = ($t1525 >= n);
                    }
                    if ($t1526 === true) {
                      return { $: "Err", _0: "a string is not closed" };
                    } else {
                      {
                        let e;
                        {
                          const $t1527 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                          e = march_string_slice(s, $t1527, 1);
                        }
                        {
                          let d;
                          {
                            const $t1528 = (e === "n");
                            if ($t1528 === true) {
                              d = "\n";
                            } else {
                              {
                                const $t1529 = (e === "t");
                                if ($t1529 === true) {
                                  d = "\t";
                                } else {
                                  {
                                    const $t1530 = (e === "r");
                                    if ($t1530 === true) {
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
                            const $t1531 = ((i + 2) < 4611686018427387904 && (i + 2) >= -4611686018427387904 ? (i + 2) : march_int_ovf((i + 2), 0));
                            {
                              let $t1532;
                              {
                                const $rc_146 = (acc + d);
                                $t1532 = $rc_146;
                              }
                              {
                                $tco_a0 = s;
                                $tco_a1 = $t1531;
                                $tco_a2 = n;
                                $tco_a3 = $t1532;
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
                    const $t1533 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                    {
                      let $t1534;
                      {
                        const $rc_147 = (acc + c);
                        $t1534 = $rc_147;
                      }
                      {
                        $tco_a0 = s;
                        $tco_a1 = $t1533;
                        $tco_a2 = n;
                        $tco_a3 = $t1534;
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
      const $t1538 = Authority$parse_entry(toks);
      switch ($t1538.$) {
        case "Err": {
          const $f1555 = $t1538._0;
          {
            const e = $f1555;
            return { $: "Err", _0: e };
          }
          break;
        }
        case "Ok": {
          const $f1556 = $t1538._0;
          const $f1557 = $f1556._0;
          const $f1558 = $f1556._1;
          {
            const rest = $f1558;
            {
              const scope = $f1557;
              switch (rest.$) {
                case "Nil": {
                  {
                    const $t1539 = { $: "Cons", _0: scope, _1: acc };
                    {
                      const $t1540 = { $: "Nil" };
                      {
                        const $t1541 = Authority$rev_scopes($t1539, $t1540);
                        return { $: "Ok", _0: $t1541 };
                      }
                    }
                  }
                  break;
                }
                case "Cons": {
                  const $f1545 = rest._0;
                  const $f1546 = rest._1;
                  if ($f1545 === ",") {
                    {
                      const more = $f1546;
                      {
                        const $t1542 = { $: "Cons", _0: scope, _1: acc };
                        {
                          $tco_a0 = more;
                          $tco_a1 = $t1542;
                          continue __tco;
                        }
                      }
                    }
                  } else {
                    {
                      const t = $f1545;
                      {
                        let $t1544;
                        {
                          let $t1543;
                          {
                            let $rc_149;
                            {
                              const $t1537_i115 = march_string_starts_with(t, "\"");
                              if ($t1537_i115 === true) {
                                $rc_149 = "a string";
                              } else {
                                $rc_149 = march_string_concat3("`", t, "`");
                              }
                            }
                            $t1543 = $rc_149;
                          }
                          {
                            const $rc_148 = ("expected `,` between capabilities, found " + $t1543);
                            $t1544 = $rc_148;
                          }
                        }
                        return { $: "Err", _0: $t1544 };
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
      const $f1608 = toks._0;
      const $f1609 = toks._1;
      {
        const rest = $f1609;
        {
          const k = $f1608;
          {
            let $t1564;
            {
              let $t1563;
              {
                let $t1618_i9713;
                {
                  let $t1617_i9712;
                  {
                    let $t1616_i9711;
                    {
                      let $t1615_i9710;
                      {
                        const $t1614_i9709 = march_string_starts_with(k, "\"");
                        $t1615_i9710 = (!$t1614_i9709);
                      }
                      if ($t1615_i9710 === true) {
                        $t1616_i9711 = (k !== "(");
                      } else {
                        $t1616_i9711 = false;
                      }
                    }
                    if ($t1616_i9711 === true) {
                      $t1617_i9712 = (k !== ")");
                    } else {
                      $t1617_i9712 = false;
                    }
                  }
                  if ($t1617_i9712 === true) {
                    $t1618_i9713 = (k !== ",");
                  } else {
                    $t1618_i9713 = false;
                  }
                }
                if ($t1618_i9713 === true) {
                  {
                    const $t1619_i9714 = march_string_split(k, ".");
                    {
                      const $rc_153_i9715 = Authority$kind_parts_ok($t1619_i9714);
                      $t1563 = $rc_153_i9715;
                    }
                  }
                } else {
                  $t1563 = false;
                }
              }
              $t1564 = (!$t1563);
            }
            if ($t1564 === true) {
              {
                let $t1566;
                {
                  let $t1565;
                  {
                    let $rc_151;
                    {
                      const $t1537_i117 = march_string_starts_with(k, "\"");
                      if ($t1537_i117 === true) {
                        $rc_151 = "a string";
                      } else {
                        $rc_151 = march_string_concat3("`", k, "`");
                      }
                    }
                    $t1565 = $rc_151;
                  }
                  {
                    const $rc_150 = ("expected a capability such as `IO.Console`, found " + $t1565);
                    $t1566 = $rc_150;
                  }
                }
                return { $: "Err", _0: $t1566 };
              }
            } else {
              switch (rest.$) {
                case "Cons": {
                  const $f1600 = rest._0;
                  const $f1601 = rest._1;
                  if ($f1600 === "(") {
                    {
                      const after = $f1601;
                      switch (after.$) {
                        case "Cons": {
                          const $f1589 = after._0;
                          const $f1590 = after._1;
                          if ($f1589 === ")") {
                            {
                              let $t1567;
                              {
                                const $rc_152 = march_string_concat_n("`", k, "()` names no scope: write `", k, "` for any target");
                                $t1567 = $rc_152;
                              }
                              return { $: "Err", _0: $t1567 };
                            }
                          } else {
                            {
                              let $t1570;
                              {
                                const $t1568 = { $: "Nil" };
                                {
                                  const $t1569 = { $: "Nil" };
                                  $t1570 = Authority$parse_items(after, $t1568, $t1569);
                                }
                              }
                              switch ($t1570.$) {
                                case "Err": {
                                  const $f1576 = $t1570._0;
                                  {
                                    const e = $f1576;
                                    return { $: "Err", _0: e };
                                  }
                                  break;
                                }
                                case "Ok": {
                                  const $f1577 = $t1570._0;
                                  const $f1578 = $f1577._0;
                                  const $f1579 = $f1577._1;
                                  const $f1580 = $f1577._2;
                                  {
                                    const more = $f1580;
                                    {
                                      const opts = $f1579;
                                      {
                                        const strs = $f1578;
                                        {
                                          const $t1571 = Authority$scope_arg(k, strs, opts);
                                          switch ($t1571.$) {
                                            case "Err": {
                                              const $f1574 = $t1571._0;
                                              {
                                                const e = $f1574;
                                                return { $: "Err", _0: e };
                                              }
                                              break;
                                            }
                                            case "Ok": {
                                              const $f1575 = $t1571._0;
                                              {
                                                const arg = $f1575;
                                                {
                                                  const $t1572 = { $: "CapEntry", _0: k, _1: arg };
                                                  {
                                                    const $t1573 = { _0: $t1572, _1: more };
                                                    return { $: "Ok", _0: $t1573 };
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
                            let $t1570;
                            {
                              const $t1568 = { $: "Nil" };
                              {
                                const $t1569 = { $: "Nil" };
                                $t1570 = Authority$parse_items(after, $t1568, $t1569);
                              }
                            }
                            switch ($t1570.$) {
                              case "Err": {
                                const $f1576 = $t1570._0;
                                {
                                  const e = $f1576;
                                  return { $: "Err", _0: e };
                                }
                                break;
                              }
                              case "Ok": {
                                const $f1577 = $t1570._0;
                                const $f1578 = $f1577._0;
                                const $f1579 = $f1577._1;
                                const $f1580 = $f1577._2;
                                {
                                  const more = $f1580;
                                  {
                                    const opts = $f1579;
                                    {
                                      const strs = $f1578;
                                      {
                                        const $t1571 = Authority$scope_arg(k, strs, opts);
                                        switch ($t1571.$) {
                                          case "Err": {
                                            const $f1574 = $t1571._0;
                                            {
                                              const e = $f1574;
                                              return { $: "Err", _0: e };
                                            }
                                            break;
                                          }
                                          case "Ok": {
                                            const $f1575 = $t1571._0;
                                            {
                                              const arg = $f1575;
                                              {
                                                const $t1572 = { $: "CapEntry", _0: k, _1: arg };
                                                {
                                                  const $t1573 = { _0: $t1572, _1: more };
                                                  return { $: "Ok", _0: $t1573 };
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
                      let $t1598;
                      {
                        const $t1597 = { $: "Any" };
                        $t1598 = { $: "CapEntry", _0: k, _1: $t1597 };
                      }
                      {
                        const $t1599 = { _0: $t1598, _1: rest };
                        return { $: "Ok", _0: $t1599 };
                      }
                    }
                  }
                  break;
                }
                default: {
                  {
                    let $t1598;
                    {
                      const $t1597 = { $: "Any" };
                      $t1598 = { $: "CapEntry", _0: k, _1: $t1597 };
                    }
                    {
                      const $t1599 = { _0: $t1598, _1: rest };
                      return { $: "Ok", _0: $t1599 };
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
        const $f1623 = ps._0;
        const $f1624 = ps._1;
        {
          const rest = $f1624;
          {
            const p = $f1623;
            {
              let $t1622;
              {
                const $t1620 = (p !== "");
                if ($t1620 === true) {
                  {
                    const $t1621 = march_string_slice(p, 0, 1);
                    {
                      const $rc_154 = march_string_contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ", $t1621);
                      $t1622 = $rc_154;
                    }
                  }
                } else {
                  $t1622 = false;
                }
              }
              if ($t1622 === true) {
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
        const $f1683 = toks._0;
        const $f1684 = toks._1;
        {
          const rest = $f1684;
          {
            const t = $f1683;
            {
              let item;
              {
                const $t1630 = march_string_starts_with(t, "\"");
                if ($t1630 === true) {
                  {
                    let $t1631;
                    switch (opts.$) {
                      case "Nil": {
                        $t1631 = true;
                        break;
                      }
                      default: {
                        $t1631 = false;
                        break;
                      }
                    }
                    if ($t1631 === true) {
                      {
                        let $t1632;
                        {
                          let $rc_157;
                          {
                            let $t1536_i127;
                            {
                              const $t1535_i126 = march_string_byte_length(t);
                              $t1536_i127 = (($t1535_i126 - 1) < 4611686018427387904 && ($t1535_i126 - 1) >= -4611686018427387904 ? ($t1535_i126 - 1) : march_int_ovf(($t1535_i126 - 1), 1));
                            }
                            $rc_157 = march_string_slice(t, 1, $t1536_i127);
                          }
                          $t1632 = $rc_157;
                        }
                        {
                          const $t1633 = { $: "Cons", _0: $t1632, _1: strs };
                          {
                            const $t1634 = { _0: $t1633, _1: opts, _2: rest };
                            item = { $: "Ok", _0: $t1634 };
                          }
                        }
                      }
                    } else {
                      item = { $: "Err", _0: "a string cannot follow an option in a scope" };
                    }
                  }
                } else {
                  {
                    let $t1635;
                    {
                      const $t1629_i124 = (t !== "");
                      if ($t1629_i124 === true) {
                        $t1635 = Authority$all_chars(t, "abcdefghijklmnopqrstuvwxyz_", 0);
                      } else {
                        $t1635 = false;
                      }
                    }
                    if ($t1635 === true) {
                      {
                        const $t1636 = Authority$parse_option(t, rest);
                        switch ($t1636.$) {
                          case "Err": {
                            const $f1639 = $t1636._0;
                            {
                              const e = $f1639;
                              item = { $: "Err", _0: e };
                            }
                            break;
                          }
                          case "Ok": {
                            const $f1640 = $t1636._0;
                            const $f1641 = $f1640._0;
                            const $f1642 = $f1640._1;
                            {
                              const more = $f1642;
                              {
                                const o = $f1641;
                                {
                                  const $t1637 = { $: "Cons", _0: o, _1: opts };
                                  {
                                    const $t1638 = { _0: strs, _1: $t1637, _2: more };
                                    item = { $: "Ok", _0: $t1638 };
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
                        let $t1648;
                        {
                          let $t1647;
                          {
                            let $rc_159;
                            {
                              const $t1537_i122 = march_string_starts_with(t, "\"");
                              if ($t1537_i122 === true) {
                                $rc_159 = "a string";
                              } else {
                                $rc_159 = march_string_concat3("`", t, "`");
                              }
                            }
                            $t1647 = $rc_159;
                          }
                          {
                            const $rc_158 = ("expected a string or an option in a scope, found " + $t1647);
                            $t1648 = $rc_158;
                          }
                        }
                        item = { $: "Err", _0: $t1648 };
                      }
                    }
                  }
                }
              }
              switch (item.$) {
                case "Err": {
                  const $f1670 = item._0;
                  {
                    const e = $f1670;
                    return { $: "Err", _0: e };
                  }
                  break;
                }
                case "Ok": {
                  const $f1671 = item._0;
                  const $f1672 = $f1671._0;
                  const $f1673 = $f1671._1;
                  const $f1674 = $f1671._2;
                  {
                    const more = $f1674;
                    {
                      const o2 = $f1673;
                      {
                        const s2 = $f1672;
                        switch (more.$) {
                          case "Cons": {
                            const $f1656 = more._0;
                            const $f1657 = more._1;
                            if ($f1656 === ")") {
                              {
                                const after = $f1657;
                                {
                                  const $t1649 = { $: "Nil" };
                                  {
                                    const $t1650 = Authority$rev(s2, $t1649);
                                    {
                                      const $t1651 = { $: "Nil" };
                                      {
                                        const $t1652 = Authority$rev(o2, $t1651);
                                        {
                                          const $t1653 = { _0: $t1650, _1: $t1652, _2: after };
                                          return { $: "Ok", _0: $t1653 };
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            } else if ($f1656 === ",") {
                              {
                                const after = $f1657;
                                {
                                  $tco_a0 = after;
                                  $tco_a1 = s2;
                                  $tco_a2 = o2;
                                  continue __tco;
                                }
                              }
                            } else {
                              {
                                const x = $f1656;
                                {
                                  let $t1655;
                                  {
                                    let $t1654;
                                    {
                                      let $rc_156;
                                      {
                                        const $t1537_i120 = march_string_starts_with(x, "\"");
                                        if ($t1537_i120 === true) {
                                          $rc_156 = "a string";
                                        } else {
                                          $rc_156 = march_string_concat3("`", x, "`");
                                        }
                                      }
                                      $t1654 = $rc_156;
                                    }
                                    {
                                      const $rc_155 = ("expected `,` or `)` in a scope, found " + $t1654);
                                      $t1655 = $rc_155;
                                    }
                                  }
                                  return { $: "Err", _0: $t1655 };
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
      const $f1715 = toks._0;
      const $f1716 = toks._1;
      if ($f1715 === "(") {
        switch ($f1716.$) {
          case "Cons": {
            const $f1723 = $f1716._0;
            const $f1724 = $f1716._1;
            {
              let $jp_clo1730;
              $jp_clo1730 = { $: "$Clo_$jp7_Authority_parse_option$0_Authority_parse_option", _0: $jp7_Authority_parse_option$apply$0_Authority_parse_option, _1: $f1716, _2: name };
              switch ($f1724.$) {
                case "Cons": {
                  const $f1731 = $f1724._0;
                  const $f1732 = $f1724._1;
                  if ($f1731 === ")") {
                    {
                      const rest = $f1732;
                      {
                        const v = $f1723;
                        {
                          const $t1689 = march_string_starts_with(v, "\"");
                          if ($t1689 === true) {
                            {
                              const $t1690 = (name === "methods");
                              if ($t1690 === true) {
                                return { $: "Err", _0: "`methods(...)` takes HTTP method names, not a string" };
                              } else {
                                {
                                  let $t1692;
                                  {
                                    let $t1691;
                                    {
                                      let $rc_161;
                                      {
                                        let $t1536_i134;
                                        {
                                          const $t1535_i133 = march_string_byte_length(v);
                                          $t1536_i134 = (($t1535_i133 - 1) < 4611686018427387904 && ($t1535_i133 - 1) >= -4611686018427387904 ? ($t1535_i133 - 1) : march_int_ovf(($t1535_i133 - 1), 1));
                                        }
                                        $rc_161 = march_string_slice(v, 1, $t1536_i134);
                                      }
                                      $t1691 = $rc_161;
                                    }
                                    {
                                      const $rc_160 = march_string_concat3(name, "=", $t1691);
                                      $t1692 = $rc_160;
                                    }
                                  }
                                  {
                                    const $t1693 = { _0: $t1692, _1: rest };
                                    return { $: "Ok", _0: $t1693 };
                                  }
                                }
                              }
                            }
                          } else {
                            {
                              let $t1695;
                              {
                                const $t1694 = (name === "methods");
                                if ($t1694 === true) {
                                  {
                                    const $t1629_i131 = (v !== "");
                                    if ($t1629_i131 === true) {
                                      $t1695 = Authority$all_chars(v, "abcdefghijklmnopqrstuvwxyz_", 0);
                                    } else {
                                      $t1695 = false;
                                    }
                                  }
                                } else {
                                  $t1695 = false;
                                }
                              }
                              if ($t1695 === true) {
                                {
                                  let $t1696;
                                  {
                                    const $rc_162 = ("methods=" + v);
                                    $t1696 = $rc_162;
                                  }
                                  {
                                    const $t1697 = { _0: $t1696, _1: rest };
                                    return { $: "Ok", _0: $t1697 };
                                  }
                                }
                              } else {
                                {
                                  let $t1698;
                                  {
                                    const $rc_163 = march_string_concat3("`", name, "(...)` takes a quoted string");
                                    $t1698 = $rc_163;
                                  }
                                  return { $: "Err", _0: $t1698 };
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  } else {
                    return $jp7_Authority_parse_option$apply$0_Authority_parse_option($jp_clo1730);
                  }
                  break;
                }
                default: {
                  return $jp7_Authority_parse_option$apply$0_Authority_parse_option($jp_clo1730);
                }
              }
            }
            break;
          }
          default: {
            {
              const more = $f1716;
              {
                const $t1699 = (name === "methods");
                if ($t1699 === true) {
                  {
                    let $t1701;
                    {
                      const $t1700 = { $: "Nil" };
                      $t1701 = Authority$method_words(more, $t1700);
                    }
                    switch ($t1701.$) {
                      case "Err": {
                        const $f1705 = $t1701._0;
                        {
                          const e = $f1705;
                          return { $: "Err", _0: e };
                        }
                        break;
                      }
                      case "Ok": {
                        const $f1706 = $t1701._0;
                        const $f1707 = $f1706._0;
                        const $f1708 = $f1706._1;
                        {
                          const rest = $f1708;
                          {
                            const ms = $f1707;
                            {
                              let $t1703;
                              {
                                let $t1702;
                                {
                                  const $rc_165 = march_string_join(ms, ",");
                                  $t1702 = $rc_165;
                                }
                                {
                                  const $rc_164 = ("methods=" + $t1702);
                                  $t1703 = $rc_164;
                                }
                              }
                              {
                                const $t1704 = { _0: $t1703, _1: rest };
                                return { $: "Ok", _0: $t1704 };
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
                    let $t1713;
                    {
                      const $rc_166 = march_string_concat3("`", name, "(...)` takes one quoted string");
                      $t1713 = $rc_166;
                    }
                    return { $: "Err", _0: $t1713 };
                  }
                }
              }
            }
          }
        }
      } else {
        {
          const $t1714 = { _0: name, _1: toks };
          return { $: "Ok", _0: $t1714 };
        }
      }
      break;
    }
    default: {
      {
        const $t1714 = { _0: name, _1: toks };
        return { $: "Ok", _0: $t1714 };
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
        const $f1746 = toks._0;
        const $f1747 = toks._1;
        {
          let $jp_clo1765;
          $jp_clo1765 = { $: "$Clo_$jp7_Authority_method_words$0_Authority_method_words", _0: $jp7_Authority_method_words$apply$0_Authority_method_words, _1: $f1746, _2: $f1747, _3: acc };
          switch ($f1747.$) {
            case "Cons": {
              const $f1766 = $f1747._0;
              const $f1767 = $f1747._1;
              if ($f1766 === ",") {
                {
                  const rest = $f1767;
                  {
                    const m = $f1746;
                    {
                      let $t1739;
                      {
                        const $t1629_i137 = (m !== "");
                        if ($t1629_i137 === true) {
                          $t1739 = Authority$all_chars(m, "abcdefghijklmnopqrstuvwxyz_", 0);
                        } else {
                          $t1739 = false;
                        }
                      }
                      if ($t1739 === true) {
                        {
                          const $t1740 = { $: "Cons", _0: m, _1: acc };
                          {
                            $tco_a0 = rest;
                            $tco_a1 = $t1740;
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
                return $jp7_Authority_method_words$apply$0_Authority_method_words($jp_clo1765);
              }
              break;
            }
            default: {
              return $jp7_Authority_method_words$apply$0_Authority_method_words($jp_clo1765);
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
    let $t1774;
    {
      let $t1123_i148;
      {
        const $t1122_i147 = (k === "IO.FileRead");
        if ($t1122_i147 === true) {
          $t1123_i148 = true;
        } else {
          $t1123_i148 = (k === "IO.FileWrite");
        }
      }
      if ($t1123_i148 === true) {
        $t1774 = true;
      } else {
        $t1774 = (k === "IO.FileSystem");
      }
    }
    if ($t1774 === true) {
      {
        let $t1776;
        {
          let $t1775;
          {
            let $rc_168;
            switch (opts.$) {
              case "Nil": {
                $rc_168 = true;
                break;
              }
              default: {
                $rc_168 = false;
                break;
              }
            }
            $t1775 = $rc_168;
          }
          $t1776 = (!$t1775);
        }
        if ($t1776 === true) {
          {
            const $t1777 = march_string_concat3("a path scope on `", k, "` takes only paths");
            return { $: "Err", _0: $t1777 };
          }
        } else {
          {
            const $t1778 = Authority$member(strs, "");
            if ($t1778 === true) {
              return { $: "Err", _0: "a path scope cannot be empty" };
            } else {
              {
                let $t1779;
                $t1779 = Authority$first_relative(strs);
                switch ($t1779.$) {
                  case "Some": {
                    const $f1783 = $t1779._0;
                    {
                      const p = $f1783;
                      {
                        let $t1780;
                        {
                          const $rc_167 = march_string_concat_n("the scope `", p, "` on `", k, "` is a relative path; give an absolute path, one starting with `/`");
                          $t1780 = $rc_167;
                        }
                        return { $: "Err", _0: $t1780 };
                      }
                    }
                    break;
                  }
                  case "None": {
                    {
                      let $t1782;
                      {
                        let $t1781;
                        {
                          const l_i9725 = strs;
                          switch (l_i9725.$) {
                            case "Nil": {
                              $t1781 = { $: "Nil" };
                              break;
                            }
                            case "Cons": {
                              const $f2039_i9726 = l_i9725._0;
                              const $f2040_i9727 = l_i9725._1;
                              {
                                const rest_i9728 = $f2040_i9727;
                                {
                                  const x_i9729 = $f2039_i9726;
                                  {
                                    let $t2037_i9731;
                                    {
                                      const $rc_207_i9730 = Authority$normalize(x_i9729);
                                      $t2037_i9731 = $rc_207_i9730;
                                    }
                                    {
                                      const $trmc27_i9732 = { $: "Cons", _0: $t2037_i9731, _1: null };
                                      Authority$map_normalize$dps(rest_i9728, $trmc27_i9732);
                                      $t1781 = $trmc27_i9732;
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
                        $t1782 = { $: "PathsAt", _0: $t1781 };
                      }
                      return { $: "Ok", _0: $t1782 };
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
        const $t1784 = (k === "IO.NetConnect");
        if ($t1784 === true) {
          {
            let spec;
            switch (strs.$) {
              case "Nil": {
                {
                  let $t1785;
                  {
                    const $rc_170 = march_string_join(opts, ";");
                    $t1785 = $rc_170;
                  }
                  {
                    const $rc_169 = (";" + $t1785);
                    spec = $rc_169;
                  }
                }
                break;
              }
              case "Cons": {
                const $f1789 = strs._0;
                const $f1790 = strs._1;
                {
                  const more = $f1790;
                  {
                    const first = $f1789;
                    {
                      let $t1786;
                      {
                        const l_i9716 = more;
                        switch (l_i9716.$) {
                          case "Nil": {
                            $t1786 = { $: "Nil" };
                            break;
                          }
                          case "Cons": {
                            const $f2031_i9718 = l_i9716._0;
                            const $f2032_i9719 = l_i9716._1;
                            {
                              const rest_i9720 = $f2032_i9719;
                              {
                                const x_i9721 = $f2031_i9718;
                                {
                                  let $t2029_i9723;
                                  {
                                    const $rc_205_i9722 = ("name=" + x_i9721);
                                    $t2029_i9723 = $rc_205_i9722;
                                  }
                                  {
                                    const $trmc23_i9724 = { $: "Cons", _0: $t2029_i9723, _1: null };
                                    Authority$prefix_all$dps(rest_i9720, "name=", $trmc23_i9724);
                                    $t1786 = $trmc23_i9724;
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
                        let $t1787;
                        {
                          const $t2013_i142 = { $: "Nil" };
                          {
                            const $t2014_i143 = Authority$rev($t1786, $t2013_i142);
                            $t1787 = Authority$rev($t2014_i143, opts);
                          }
                        }
                        {
                          const $t1788 = { $: "Cons", _0: first, _1: $t1787 };
                          {
                            const $rc_171 = march_string_join($t1788, ";");
                            spec = $rc_171;
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
              const $t1795 = Authority$host_decl(spec);
              switch ($t1795.$) {
                case "Err": {
                  const $f1818 = $t1795._0;
                  {
                    const e = $f1818;
                    return { $: "Err", _0: e };
                  }
                  break;
                }
                case "Ok": {
                  const $f1819 = $t1795._0;
                  const $f1820 = $f1819._0;
                  const $f1821 = $f1819._1;
                  const $f1822 = $f1819._2;
                  const $f1823 = $f1819._3;
                  {
                    const p = $f1820;
                    {
                      const $t1796 = (p === "");
                      if ($t1796 === true) {
                        {
                          const $t1797 = { $: "HostAt", _0: spec, _1: "", _2: false, _3: 0 };
                          return { $: "Ok", _0: $t1797 };
                        }
                      } else {
                        {
                          const $t1798 = Authority$parse_host_pattern(p);
                          switch ($t1798.$) {
                            case "Ok": {
                              const $f1800 = $t1798._0;
                              const $f1801 = $f1800._0;
                              const $f1802 = $f1800._1;
                              const $f1803 = $f1800._2;
                              const $f1804 = $f1800._3;
                              {
                                const port = $f1803;
                                {
                                  const wild = $f1802;
                                  {
                                    const h = $f1801;
                                    {
                                      const $t1799 = { $: "HostAt", _0: spec, _1: h, _2: wild, _3: port };
                                      return { $: "Ok", _0: $t1799 };
                                    }
                                  }
                                }
                              }
                              break;
                            }
                            case "Err": {
                              const $f1817 = $t1798._0;
                              {
                                const e = $f1817;
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
            let $t1836;
            {
              const $t1124_i139 = (k === "IO.Mut");
              if ($t1124_i139 === true) {
                $t1836 = true;
              } else {
                $t1836 = (k === "IO.Registry");
              }
            }
            if ($t1836 === true) {
              {
                let $t1838;
                {
                  const $t1837 = { $: "Nil" };
                  $t1838 = Authority$name_options(opts, $t1837);
                }
                switch ($t1838.$) {
                  case "Err": {
                    const $f1844 = $t1838._0;
                    {
                      const e = $f1844;
                      return { $: "Err", _0: e };
                    }
                    break;
                  }
                  case "Ok": {
                    const $f1845 = $t1838._0;
                    {
                      const prefixes = $f1845;
                      {
                        const $t1839 = Authority$bad_name_text(strs, "a name");
                        switch ($t1839.$) {
                          case "Some": {
                            const $f1843 = $t1839._0;
                            {
                              const e = $f1843;
                              return { $: "Err", _0: e };
                            }
                            break;
                          }
                          case "None": {
                            {
                              const $t1840 = Authority$bad_name_text(prefixes, "a prefix");
                              switch ($t1840.$) {
                                case "Some": {
                                  const $f1842 = $t1840._0;
                                  {
                                    const e = $f1842;
                                    return { $: "Err", _0: e };
                                  }
                                  break;
                                }
                                case "None": {
                                  {
                                    const $t1841 = { $: "Names", _0: strs, _1: prefixes };
                                    return { $: "Ok", _0: $t1841 };
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
                const $t1846 = march_string_concat3("`", k, "` takes no scope");
                return { $: "Err", _0: $t1846 };
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
        const $f1848 = ps._0;
        const $f1849 = ps._1;
        {
          const rest = $f1849;
          {
            const p = $f1848;
            {
              const $t1847 = march_string_starts_with(p, "/");
              if ($t1847 === true) {
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
          const $t1854 = { $: "Nil" };
          {
            const $t1855 = Authority$rev(acc, $t1854);
            return { $: "Ok", _0: $t1855 };
          }
        }
        break;
      }
      case "Cons": {
        const $f1862 = opts._0;
        const $f1863 = opts._1;
        {
          const rest = $f1863;
          {
            const o = $f1862;
            {
              const $t1856 = march_string_starts_with(o, "prefix=");
              if ($t1856 === true) {
                {
                  let $t1859;
                  {
                    let $t1858;
                    {
                      const $t1857 = march_string_byte_length(o);
                      $t1858 = (($t1857 - 7) < 4611686018427387904 && ($t1857 - 7) >= -4611686018427387904 ? ($t1857 - 7) : march_int_ovf(($t1857 - 7), 1));
                    }
                    {
                      const $rc_172 = march_string_slice(o, 7, $t1858);
                      $t1859 = $rc_172;
                    }
                  }
                  {
                    const $t1860 = { $: "Cons", _0: $t1859, _1: acc };
                    {
                      $tco_a0 = rest;
                      $tco_a1 = $t1860;
                      continue __tco;
                    }
                  }
                }
              } else {
                {
                  let $t1861;
                  {
                    const $rc_173 = march_string_concat3("`", o, "` is not an option a name scope takes; it takes names and `prefix(\"...\")`");
                    $t1861 = $rc_173;
                  }
                  return { $: "Err", _0: $t1861 };
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
        const $f1874 = ns._0;
        const $f1875 = ns._1;
        {
          const rest = $f1875;
          {
            const n = $f1874;
            {
              const $t1868 = (n === "");
              if ($t1868 === true) {
                {
                  const $t1869 = (what + " cannot be empty");
                  return { $: "Some", _0: $t1869 };
                }
              } else {
                {
                  let $t1872;
                  {
                    let $t1871;
                    {
                      const $t1870 = march_string_contains(n, ";");
                      if ($t1870 === true) {
                        $t1871 = true;
                      } else {
                        $t1871 = march_string_contains(n, "=");
                      }
                    }
                    if ($t1871 === true) {
                      $t1872 = true;
                    } else {
                      $t1872 = march_string_contains(n, ",");
                    }
                  }
                  if ($t1872 === true) {
                    {
                      const $t1873 = march_string_concat_n(what, " `", n, "` contains `;`, `=` or `,`");
                      return { $: "Some", _0: $t1873 };
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
      const $f1889 = s._0;
      const $f1890 = s._1;
      switch ($f1890.$) {
        case "Any": {
          {
            const k = $f1889;
            return k;
          }
          break;
        }
        default: {
          switch ($f1890.$) {
            case "Paths": {
              const $f1941 = $f1890._0;
              {
                const ps = $f1941;
                {
                  const k = $f1889;
                  {
                    let $t1881;
                    {
                      const $t1880 = Authority$quote_all(ps);
                      {
                        const $rc_175 = march_string_join($t1880, ", ");
                        $t1881 = $rc_175;
                      }
                    }
                    {
                      const $rc_174 = march_string_concat_n(k, "(", $t1881, ")");
                      return $rc_174;
                    }
                  }
                }
              }
              break;
            }
            default: {
              switch ($f1890.$) {
                case "PathsAt": {
                  const $f1934 = $f1890._0;
                  {
                    const ps = $f1934;
                    {
                      const k = $f1889;
                      {
                        let $t1883;
                        {
                          const $t1882 = Authority$quote_all(ps);
                          {
                            const $rc_177 = march_string_join($t1882, ", ");
                            $t1883 = $rc_177;
                          }
                        }
                        {
                          const $rc_176 = march_string_concat_n(k, "(", $t1883, ")");
                          return $rc_176;
                        }
                      }
                    }
                  }
                  break;
                }
                default: {
                  switch ($f1890.$) {
                    case "Names": {
                      const $f1922 = $f1890._0;
                      const $f1923 = $f1890._1;
                      {
                        const pre = $f1923;
                        {
                          const ns = $f1922;
                          {
                            const k = $f1889;
                            {
                              let $t1888;
                              {
                                const $t1884 = Authority$quote_all(ns);
                                {
                                  const $t1885 = Authority$quote_all(pre);
                                  {
                                    let $t1886;
                                    {
                                      const l_i9733 = $t1885;
                                      switch (l_i9733.$) {
                                        case "Nil": {
                                          $t1886 = { $: "Nil" };
                                          break;
                                        }
                                        case "Cons": {
                                          const $f1993_i9735 = l_i9733._0;
                                          const $f1994_i9736 = l_i9733._1;
                                          {
                                            const rest_i9737 = $f1994_i9736;
                                            {
                                              const x_i9738 = $f1993_i9735;
                                              {
                                                let $t1991_i9740;
                                                {
                                                  const $rc_203_i9739 = march_string_concat3("prefix(", x_i9738, ")");
                                                  $t1991_i9740 = $rc_203_i9739;
                                                }
                                                {
                                                  const $trmc19_i9741 = { $: "Cons", _0: $t1991_i9740, _1: null };
                                                  Authority$wrap_all$dps(rest_i9737, "prefix(", $trmc19_i9741);
                                                  $t1886 = $trmc19_i9741;
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
                                      let $t1887;
                                      {
                                        const $t2013_i151 = { $: "Nil" };
                                        {
                                          const $t2014_i152 = Authority$rev($t1884, $t2013_i151);
                                          $t1887 = Authority$rev($t2014_i152, $t1886);
                                        }
                                      }
                                      {
                                        const $rc_179 = march_string_join($t1887, ", ");
                                        $t1888 = $rc_179;
                                      }
                                    }
                                  }
                                }
                              }
                              {
                                const $rc_178 = march_string_concat_n(k, "(", $t1888, ")");
                                return $rc_178;
                              }
                            }
                          }
                        }
                      }
                      break;
                    }
                    default: {
                      switch ($f1890.$) {
                        case "Hosts": {
                          const $f1915 = $f1890._0;
                          {
                            const spec = $f1915;
                            {
                              const k = $f1889;
                              {
                                const $rc_180 = Authority$host_scope_text(k, spec);
                                return $rc_180;
                              }
                            }
                          }
                          break;
                        }
                        default: {
                          switch ($f1890.$) {
                            case "HostAt": {
                              const $f1893 = $f1890._0;
                              const $f1894 = $f1890._1;
                              const $f1895 = $f1890._2;
                              const $f1896 = $f1890._3;
                              {
                                const spec = $f1893;
                                {
                                  const k = $f1889;
                                  {
                                    const $rc_181 = Authority$host_scope_text(k, spec);
                                    return $rc_181;
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
    const $t1950 = march_string_split(spec, ";");
    switch ($t1950.$) {
      case "Nil": {
        return k;
        break;
      }
      case "Cons": {
        const $f1957 = $t1950._0;
        const $f1958 = $t1950._1;
        {
          const opts = $f1958;
          {
            const first = $f1957;
            {
              const $t1951 = (first === "");
              {
                let head;
                if ($t1951 === true) {
                  head = { $: "Nil" };
                } else {
                  {
                    let $t1952;
                    {
                      const $rc_184 = Authority$quote(first);
                      $t1952 = $rc_184;
                    }
                    {
                      const $t1953 = { $: "Nil" };
                      head = { $: "Cons", _0: $t1952, _1: $t1953 };
                    }
                  }
                }
                {
                  let $t1956;
                  {
                    const $t1954 = Authority$option_texts(opts);
                    {
                      let $t1955;
                      {
                        const $t2013_i155 = { $: "Nil" };
                        {
                          const $t2014_i156 = Authority$rev(head, $t2013_i155);
                          $t1955 = Authority$rev($t2014_i156, $t1954);
                        }
                      }
                      {
                        const $rc_183 = march_string_join($t1955, ", ");
                        $t1956 = $rc_183;
                      }
                    }
                  }
                  {
                    const $rc_182 = march_string_concat_n(k, "(", $t1956, ")");
                    return $rc_182;
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
      const $f1975 = opts._0;
      const $f1976 = opts._1;
      {
        const rest = $f1976;
        {
          const o = $f1975;
          {
            let t;
            {
              const $t1963 = march_string_index_of(o, "=");
              switch ($t1963.$) {
                case "None": {
                  t = o;
                  break;
                }
                case "Some": {
                  const $f1973 = $t1963._0;
                  {
                    const i = $f1973;
                    {
                      const name = march_string_slice(o, 0, i);
                      {
                        let v;
                        {
                          const $t1964 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                          {
                            let $t1967;
                            {
                              let $t1966;
                              {
                                const $t1965 = march_string_byte_length(o);
                                $t1966 = (($t1965 - i) < 4611686018427387904 && ($t1965 - i) >= -4611686018427387904 ? ($t1965 - i) : march_int_ovf(($t1965 - i), 1));
                              }
                              $t1967 = (($t1966 - 1) < 4611686018427387904 && ($t1966 - 1) >= -4611686018427387904 ? ($t1966 - 1) : march_int_ovf(($t1966 - 1), 1));
                            }
                            {
                              const $rc_191 = march_string_slice(o, $t1964, $t1967);
                              v = $rc_191;
                            }
                          }
                        }
                        {
                          const $t1968 = (name === "name");
                          if ($t1968 === true) {
                            {
                              const $rc_185 = Authority$quote(v);
                              t = $rc_185;
                            }
                          } else {
                            {
                              const $t1969 = (name === "methods");
                              if ($t1969 === true) {
                                {
                                  let $t1971;
                                  {
                                    let $t1970;
                                    {
                                      const $rc_188 = march_string_split(v, ",");
                                      $t1970 = $rc_188;
                                    }
                                    {
                                      const $rc_187 = march_string_join($t1970, ", ");
                                      $t1971 = $rc_187;
                                    }
                                  }
                                  {
                                    const $rc_186 = march_string_concat3("methods(", $t1971, ")");
                                    t = $rc_186;
                                  }
                                }
                              } else {
                                {
                                  let $t1972;
                                  {
                                    const $rc_190 = Authority$quote(v);
                                    $t1972 = $rc_190;
                                  }
                                  {
                                    const $rc_189 = march_string_concat_n(name, "(", $t1972, ")");
                                    t = $rc_189;
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
        const $f1975 = opts._0;
        const $f1976 = opts._1;
        {
          const rest = $f1976;
          {
            const o = $f1975;
            {
              let t;
              {
                const $t1963 = march_string_index_of(o, "=");
                switch ($t1963.$) {
                  case "None": {
                    t = o;
                    break;
                  }
                  case "Some": {
                    const $f1973 = $t1963._0;
                    {
                      const i = $f1973;
                      {
                        const name = march_string_slice(o, 0, i);
                        {
                          let v;
                          {
                            const $t1964 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                            {
                              let $t1967;
                              {
                                let $t1966;
                                {
                                  const $t1965 = march_string_byte_length(o);
                                  $t1966 = (($t1965 - i) < 4611686018427387904 && ($t1965 - i) >= -4611686018427387904 ? ($t1965 - i) : march_int_ovf(($t1965 - i), 1));
                                }
                                $t1967 = (($t1966 - 1) < 4611686018427387904 && ($t1966 - 1) >= -4611686018427387904 ? ($t1966 - 1) : march_int_ovf(($t1966 - 1), 1));
                              }
                              {
                                const $rc_198 = march_string_slice(o, $t1964, $t1967);
                                v = $rc_198;
                              }
                            }
                          }
                          {
                            const $t1968 = (name === "name");
                            if ($t1968 === true) {
                              {
                                const $rc_192 = Authority$quote(v);
                                t = $rc_192;
                              }
                            } else {
                              {
                                const $t1969 = (name === "methods");
                                if ($t1969 === true) {
                                  {
                                    let $t1971;
                                    {
                                      let $t1970;
                                      {
                                        const $rc_195 = march_string_split(v, ",");
                                        $t1970 = $rc_195;
                                      }
                                      {
                                        const $rc_194 = march_string_join($t1970, ", ");
                                        $t1971 = $rc_194;
                                      }
                                    }
                                    {
                                      const $rc_193 = march_string_concat3("methods(", $t1971, ")");
                                      t = $rc_193;
                                    }
                                  }
                                } else {
                                  {
                                    let $t1972;
                                    {
                                      const $rc_197 = Authority$quote(v);
                                      $t1972 = $rc_197;
                                    }
                                    {
                                      const $rc_196 = march_string_concat_n(name, "(", $t1972, ")");
                                      t = $rc_196;
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
    let $t1982;
    {
      const $t1981 = march_string_replace_all(s, "\\", "\\\\");
      {
        const $rc_200 = march_string_replace_all($t1981, "\"", "\\\"");
        $t1982 = $rc_200;
      }
    }
    {
      const $rc_199 = march_string_concat3("\"", $t1982, "\"");
      return $rc_199;
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
      const $f1985 = l._0;
      const $f1986 = l._1;
      {
        const rest = $f1986;
        {
          const x = $f1985;
          {
            let $t1983;
            {
              const $rc_201 = Authority$quote(x);
              $t1983 = $rc_201;
            }
            {
              const $trmc15 = { $: "Cons", _0: $t1983, _1: null };
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
        const $f1985 = l._0;
        const $f1986 = l._1;
        {
          const rest = $f1986;
          {
            const x = $f1985;
            {
              let $t1983;
              {
                const $rc_202 = Authority$quote(x);
                $t1983 = $rc_202;
              }
              {
                const $trmc14 = { $: "Cons", _0: $t1983, _1: null };
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
        const $f1993 = l._0;
        const $f1994 = l._1;
        {
          const rest = $f1994;
          {
            const x = $f1993;
            {
              let $t1991;
              {
                const $rc_204 = march_string_concat3(pre, x, ")");
                $t1991 = $rc_204;
              }
              {
                const $trmc18 = { $: "Cons", _0: $t1991, _1: null };
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
        const $f2000 = l._0;
        const $f2001 = l._1;
        {
          const rest = $f2001;
          {
            const x = $f2000;
            {
              const $t1999 = { $: "Cons", _0: x, _1: acc };
              {
                $tco_a0 = rest;
                $tco_a1 = $t1999;
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
        const $f2007 = l._0;
        const $f2008 = l._1;
        {
          const rest = $f2008;
          {
            const x = $f2007;
            {
              const $t2006 = { $: "Cons", _0: x, _1: acc };
              {
                $tco_a0 = rest;
                $tco_a1 = $t2006;
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
        const $f2016 = l._0;
        const $f2017 = l._1;
        {
          const rest = $f2017;
          {
            const y = $f2016;
            {
              const $t2015 = (y === x);
              if ($t2015 === true) {
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
        const $f2023 = xs._0;
        const $f2024 = xs._1;
        {
          const rest = $f2024;
          {
            const x = $f2023;
            {
              const $t2022 = Authority$member(l, x);
              if ($t2022 === true) {
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
        const $f2031 = l._0;
        const $f2032 = l._1;
        {
          const rest = $f2032;
          {
            const x = $f2031;
            {
              let $t2029;
              {
                const $rc_206 = (pre + x);
                $t2029 = $rc_206;
              }
              {
                const $trmc22 = { $: "Cons", _0: $t2029, _1: null };
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
        const $f2039 = l._0;
        const $f2040 = l._1;
        {
          const rest = $f2040;
          {
            const x = $f2039;
            {
              let $t2037;
              {
                const $rc_208 = Authority$normalize(x);
                $t2037 = $rc_208;
              }
              {
                const $trmc26 = { $: "Cons", _0: $t2037, _1: null };
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

function Authority$mock_covers($tco_a0, $tco_a1, $tco_a2, $tco_a3) {
  __tco: for (;;) {
    const scopes = $tco_a0;
    const kind = $tco_a1;
    const target = $tco_a2;
    const cwd = $tco_a3;
    switch (scopes.$) {
      case "Nil": {
        return false;
        break;
      }
      case "Cons": {
        const $f2175 = scopes._0;
        const $f2176 = scopes._1;
        switch ($f2175.$) {
          case "CapEntry": {
            const $f2177 = $f2175._0;
            const $f2178 = $f2175._1;
            {
              const rest = $f2176;
              {
                const arg = $f2178;
                {
                  const k = $f2177;
                  {
                    let $t2174;
                    {
                      let $t2173;
                      {
                        const $rc_215 = (k === kind);
                        $t2173 = $rc_215;
                      }
                      if ($t2173 === true) {
                        $t2174 = Authority$arg_admits(arg, kind, target, cwd);
                      } else {
                        $t2174 = false;
                      }
                    }
                    if ($t2174 === true) {
                      return true;
                    } else {
                      {
                        $tco_a0 = rest;
                        $tco_a1 = kind;
                        $tco_a2 = target;
                        $tco_a3 = cwd;
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
const Authority$mock_covers$clo = { _0: ($_, scopes, kind, target, cwd) => Authority$mock_covers(scopes, kind, target, cwd) };

function Js$Dom$find(id) {
  {
    const $rc_2748 = dom_get_element_by_id$clo._0(dom_get_element_by_id$clo, id);
    return $rc_2748;
  }
}
const Js$Dom$find$clo = { _0: ($_, id) => Js$Dom$find(id) };

function Js$Dom$create(tag) {
  {
    const $rc_2751 = dom_create_element$clo._0(dom_create_element$clo, tag);
    return $rc_2751;
  }
}
const Js$Dom$create$clo = { _0: ($_, tag) => Js$Dom$create(tag) };

function Js$Dom$append(parent, child) {
  {
    const $rc_2754 = dom_append_child$clo._0(dom_append_child$clo, parent, child);
    return $rc_2754;
  }
}
const Js$Dom$append$clo = { _0: ($_, parent, child) => Js$Dom$append(parent, child) };

function Js$Dom$get_attr(el, name) {
  {
    const $rc_2767 = dom_get_attribute$clo._0(dom_get_attribute$clo, el, name);
    return $rc_2767;
  }
}
const Js$Dom$get_attr$clo = { _0: ($_, el, name) => Js$Dom$get_attr(el, name) };

function Js$Dom$set_attr(el, name, val) {
  {
    const $rc_2768 = dom_set_attribute$clo._0(dom_set_attribute$clo, el, name, val);
    return $rc_2768;
  }
}
const Js$Dom$set_attr$clo = { _0: ($_, el, name, val) => Js$Dom$set_attr(el, name, val) };

function Js$Dom$add_class(el, cls) {
  {
    const $rc_2771 = dom_class_add$clo._0(dom_class_add$clo, el, cls);
    return $rc_2771;
  }
}
const Js$Dom$add_class$clo = { _0: ($_, el, cls) => Js$Dom$add_class(el, cls) };

function Js$Dom$set_style(el, prop, val) {
  {
    const $rc_2775 = dom_set_style$clo._0(dom_set_style$clo, el, prop, val);
    return $rc_2775;
  }
}
const Js$Dom$set_style$clo = { _0: ($_, el, prop, val) => Js$Dom$set_style(el, prop, val) };

function Js$Dom$listen(el, event, handler) {
  {
    const $rc_2779 = dom_add_event_listener$clo._0(dom_add_event_listener$clo, el, event, handler);
    return $rc_2779;
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
        const $t49670 = { _0: 0, _1: 1 };
        {
          const $t49671 = { _0: 1, _1: 1 };
          {
            const $t49672 = { _0: 2, _1: 1 };
            {
              const $t49673 = { _0: 3, _1: 1 };
              {
                const $t49674 = { $: "Nil" };
                {
                  const $t49675 = { $: "Cons", _0: $t49673, _1: $t49674 };
                  {
                    const $t49676 = { $: "Cons", _0: $t49672, _1: $t49675 };
                    {
                      const $t49677 = { $: "Cons", _0: $t49671, _1: $t49676 };
                      return { $: "Cons", _0: $t49670, _1: $t49677 };
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
        const $t49678 = { _0: 1, _1: 1 };
        {
          const $t49679 = { _0: 2, _1: 1 };
          {
            const $t49680 = { _0: 1, _1: 2 };
            {
              const $t49681 = { _0: 2, _1: 2 };
              {
                const $t49682 = { $: "Nil" };
                {
                  const $t49683 = { $: "Cons", _0: $t49681, _1: $t49682 };
                  {
                    const $t49684 = { $: "Cons", _0: $t49680, _1: $t49683 };
                    {
                      const $t49685 = { $: "Cons", _0: $t49679, _1: $t49684 };
                      return { $: "Cons", _0: $t49678, _1: $t49685 };
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
        const $t49686 = { _0: 1, _1: 1 };
        {
          const $t49687 = { _0: 0, _1: 2 };
          {
            const $t49688 = { _0: 1, _1: 2 };
            {
              const $t49689 = { _0: 2, _1: 2 };
              {
                const $t49690 = { $: "Nil" };
                {
                  const $t49691 = { $: "Cons", _0: $t49689, _1: $t49690 };
                  {
                    const $t49692 = { $: "Cons", _0: $t49688, _1: $t49691 };
                    {
                      const $t49693 = { $: "Cons", _0: $t49687, _1: $t49692 };
                      return { $: "Cons", _0: $t49686, _1: $t49693 };
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
        const $t49694 = { _0: 1, _1: 1 };
        {
          const $t49695 = { _0: 2, _1: 1 };
          {
            const $t49696 = { _0: 0, _1: 2 };
            {
              const $t49697 = { _0: 1, _1: 2 };
              {
                const $t49698 = { $: "Nil" };
                {
                  const $t49699 = { $: "Cons", _0: $t49697, _1: $t49698 };
                  {
                    const $t49700 = { $: "Cons", _0: $t49696, _1: $t49699 };
                    {
                      const $t49701 = { $: "Cons", _0: $t49695, _1: $t49700 };
                      return { $: "Cons", _0: $t49694, _1: $t49701 };
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
        const $t49702 = { _0: 0, _1: 1 };
        {
          const $t49703 = { _0: 1, _1: 1 };
          {
            const $t49704 = { _0: 1, _1: 2 };
            {
              const $t49705 = { _0: 2, _1: 2 };
              {
                const $t49706 = { $: "Nil" };
                {
                  const $t49707 = { $: "Cons", _0: $t49705, _1: $t49706 };
                  {
                    const $t49708 = { $: "Cons", _0: $t49704, _1: $t49707 };
                    {
                      const $t49709 = { $: "Cons", _0: $t49703, _1: $t49708 };
                      return { $: "Cons", _0: $t49702, _1: $t49709 };
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
        const $t49710 = { _0: 0, _1: 1 };
        {
          const $t49711 = { _0: 0, _1: 2 };
          {
            const $t49712 = { _0: 1, _1: 2 };
            {
              const $t49713 = { _0: 2, _1: 2 };
              {
                const $t49714 = { $: "Nil" };
                {
                  const $t49715 = { $: "Cons", _0: $t49713, _1: $t49714 };
                  {
                    const $t49716 = { $: "Cons", _0: $t49712, _1: $t49715 };
                    {
                      const $t49717 = { $: "Cons", _0: $t49711, _1: $t49716 };
                      return { $: "Cons", _0: $t49710, _1: $t49717 };
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
        const $t49718 = { _0: 2, _1: 1 };
        {
          const $t49719 = { _0: 0, _1: 2 };
          {
            const $t49720 = { _0: 1, _1: 2 };
            {
              const $t49721 = { _0: 2, _1: 2 };
              {
                const $t49722 = { $: "Nil" };
                {
                  const $t49723 = { $: "Cons", _0: $t49721, _1: $t49722 };
                  {
                    const $t49724 = { $: "Cons", _0: $t49720, _1: $t49723 };
                    {
                      const $t49725 = { $: "Cons", _0: $t49719, _1: $t49724 };
                      return { $: "Cons", _0: $t49718, _1: $t49725 };
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
  const $f49735 = c._0;
  const $f49736 = c._1;
  {
    const y = $f49736;
    {
      const x = $f49735;
      {
        const $t49734 = ((3 - y) < 4611686018427387904 && (3 - y) >= -4611686018427387904 ? (3 - y) : march_int_ovf((3 - y), 1));
        return { _0: $t49734, _1: x };
      }
    }
  }
}
const TetrisLogic$rotate_cell$clo = { _0: ($_, c) => TetrisLogic$rotate_cell(c) };

function TetrisLogic$clear_lines(board) {
  {
    let rows;
    {
      const go_i5875 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
      {
        const $t2290_i5877 = { $: "Nil" };
        rows = go$apply$0_List_range(go_i5875, 19, $t2290_i5877);
      }
    }
    {
      let $t49782;
      $t49782 = { $: "$Clo_$lam0_TetrisLogic_clear_lines$0_TetrisLogic_clear_lines", _0: $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines, _1: board };
      {
        const kept_rows = List$filter$List_Int$Fn_Int_Bool(rows, $t49782);
        {
          let cleared;
          {
            let $t49784;
            {  };
            $t49784 = List$length_onto$List_Int$Int(kept_rows, 0);
            cleared = ((20 - $t49784) < 4611686018427387904 && (20 - $t49784) >= -4611686018427387904 ? (20 - $t49784) : march_int_ovf((20 - $t49784), 1));
          }
          {
            const $t49786 = { $: "$Clo_$lam1_TetrisLogic_clear_lines$1_TetrisLogic_clear_lines", _0: $lam1_TetrisLogic_clear_lines$apply$1_TetrisLogic_clear_lines, _1: board };
            {
              let kept_cells;
              {
                const f_i5870 = $t49786;
                {
                  const $t2382_i5871 = { $: "Nil" };
                  kept_cells = List$flat_map_go$List_Int$List_Int$Fn_Int_List_Int($t2382_i5871, kept_rows, f_i5870);
                }
              }
              {
                const $t49788 = ((cleared * 10) < 4611686018427387904 && (cleared * 10) >= -4611686018427387904 ? (cleared * 10) : march_int_ovf((cleared * 10), 2));
                {
                  let blank_cells;
                  {
                    const go_i5867 = { $: "$Clo_go$0_List_repeat_Int_Int", _0: go$apply$0_List_repeat_Int_Int, _1: 0 };
                    {
                      const $t2285_i5868 = { $: "Nil" };
                      blank_cells = go$apply$0_List_repeat_Int_Int(go_i5867, $t49788, $t2285_i5868);
                    }
                  }
                  {
                    let new_board;
                    {
                      let $t49789;
                      {
                        const xs_i14796 = blank_cells;
                        {
                          const ys_i14797 = kept_cells;
                          switch (xs_i14796.$) {
                            case "Nil": {
                              $t49789 = kept_cells;
                              break;
                            }
                            case "Cons": {
                              const $f2361_i14798 = xs_i14796._0;
                              const $f2362_i14799 = xs_i14796._1;
                              {
                                const t_i14800 = $f2362_i14799;
                                {
                                  const h_i14801 = $f2361_i14798;
                                  {
                                    const $trmc34_i14802 = { $: "Cons", _0: h_i14801, _1: null };
                                    List$append$dps$List_Int$List_Int$List_Int(t_i14800, kept_cells, $trmc34_i14802);
                                    $t49789 = $trmc34_i14802;
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
                      new_board = Array$from_list$List_Int($t49789);
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
    const $t49791 = { $: "$Clo_$lam0_int_list_to_string$0_int_list_to_string", _0: $lam0_int_list_to_string$apply$0_int_list_to_string };
    {
      let $t49792;
      {
        const xs_i14803 = xs;
        {
          const f_i14804 = $t49791;
          switch (xs_i14803.$) {
            case "Nil": {
              $t49792 = { $: "Nil" };
              break;
            }
            case "Cons": {
              const $f2369_i14805 = xs_i14803._0;
              const $f2370_i14806 = xs_i14803._1;
              {
                const t_i14807 = $f2370_i14806;
                {
                  const h_i14808 = $f2369_i14805;
                  {
                    let $t2367_i14809;
                    $t2367_i14809 = f_i14804._0(f_i14804, h_i14808);
                    {
                      const $trmc38_i14810 = { $: "Cons", _0: $t2367_i14809, _1: null };
                      List$map$dps$List_Int$Fn_Int_String$List_String(t_i14807, f_i14804, $trmc38_i14810);
                      $t49792 = $trmc38_i14810;
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
        const $rc_2830 = march_string_join($t49792, ",");
        return $rc_2830;
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
    const $t49815 = { $: "I" };
    {
      const $t49816 = { $: "O" };
      {
        const $t49817 = { $: "T" };
        {
          const $t49818 = { $: "S" };
          {
            const $t49819 = { $: "Z" };
            {
              const $t49820 = { $: "J" };
              {
                const $t49821 = { $: "L" };
                {
                  const $t49822 = { $: "Nil" };
                  {
                    const $t49823 = { $: "Cons", _0: $t49821, _1: $t49822 };
                    {
                      const $t49824 = { $: "Cons", _0: $t49820, _1: $t49823 };
                      {
                        const $t49825 = { $: "Cons", _0: $t49819, _1: $t49824 };
                        {
                          const $t49826 = { $: "Cons", _0: $t49818, _1: $t49825 };
                          {
                            const $t49827 = { $: "Cons", _0: $t49817, _1: $t49826 };
                            {
                              const $t49828 = { $: "Cons", _0: $t49816, _1: $t49827 };
                              {
                                const pieces = { $: "Cons", _0: $t49815, _1: $t49828 };
                                {
                                  let rng2;
                                  {
                                    const $t49797_i13536 = ((rng * 16807) < 4611686018427387904 && (rng * 16807) >= -4611686018427387904 ? (rng * 16807) : march_int_ovf((rng * 16807), 2));
                                    rng2 = (2147483647 === 0 ? march_mod_zero() : $t49797_i13536 % 2147483647);
                                  }
                                  {
                                    const idx = (7 === 0 ? march_mod_zero() : rng2 % 7);
                                    {
                                      let result;
                                      {
                                        const $t49829 = List$nth$List_Piece$Int(pieces, idx);
                                        result = { _0: $t49829, _1: rng2 };
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
    const $t49830 = Js$Dom$find("game-state");
    switch ($t49830.$) {
      case "Some": {
        const $f49831 = $t49830._0;
        {
          const el = $f49831;
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
    const $t49832 = Js$Dom$get_attr(el, name);
    switch ($t49832.$) {
      case "Some": {
        const $f49834 = $t49832._0;
        {
          const s = $f49834;
          {
            let $t49833;
            {
              const $rc_2832 = march_string_to_int(s);
              $t49833 = $rc_2832;
            }
            {
              const $rc_2831 = Option$unwrap_or$Option_Int$Int($t49833, _default);
              return $rc_2831;
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
    const $t49835 = Js$Dom$get_attr(el, name);
    switch ($t49835.$) {
      case "Some": {
        const $f49836 = $t49835._0;
        {
          const s = $f49836;
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
        let $t49837;
        {
          const xs_i14811 = cells;
          {
            const f_i14812 = TetrisLogic$rotate_cell$clo;
            switch (xs_i14811.$) {
              case "Nil": {
                $t49837 = { $: "Nil" };
                break;
              }
              case "Cons": {
                const $f2369_i14813 = xs_i14811._0;
                const $f2370_i14814 = xs_i14811._1;
                {
                  const t_i14815 = $f2370_i14814;
                  {
                    const h_i14816 = $f2369_i14813;
                    {
                      let $t2367_i14817;
                      $t2367_i14817 = f_i14812._0(f_i14812, h_i14816);
                      {
                        const $trmc38_i14818 = { $: "Cons", _0: $t2367_i14817, _1: null };
                        List$map$dps$List_T_Int_Int$Fn_T_Int_Int_T_Int_Int$List_T_Int_Int(t_i14815, f_i14812, $trmc38_i14818);
                        $t49837 = $trmc38_i14818;
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
          const $t49838 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
          {
            $tco_a0 = $t49837;
            $tco_a1 = $t49838;
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
        const $t49757_i5887 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: 3, _3: 0 };
        over = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t49757_i5887);
      }
      {
        const $t49841 = next_piece(rng);
        const $f49842 = $t49841._0;
        const $f49843 = $t49841._1;
        {
          const rng2 = $f49843;
          {
            const next2 = $f49842;
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
    const $t49882 = Js$Dom$find(id);
    switch ($t49882.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f49883 = $t49882._0;
        {
          const el = $f49883;
          {
            const el_i13537 = el;
            {
              const text_i13538 = text;
              {
                const $rc_2764_i13539 = dom_set_text$clo._0(dom_set_text$clo, el, text);
                return $rc_2764_i13539;
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
        let $t49884;
        $t49884 = get_str_attr(el, "data-over", "false");
        {
          const $rc_2841 = ($t49884 === "true");
          over = $rc_2841;
        }
      }
      if (over === true) {
        return {  };
      } else if (over === false) {
        {
          let board;
          {
            let $t49885;
            $t49885 = get_str_attr(el, "data-board", "");
            {
              let $t49886;
              {
                let $rc_2840;
                {
                  const $t49793_i5917 = march_string_split($t49885, ",");
                  {
                    const $t49796_i5918 = { $: "$Clo_$lam0_string_to_int_list$0_string_to_int_list", _0: $lam0_string_to_int_list$apply$0_string_to_int_list };
                    $rc_2840 = List$map$List_String$Fn_String_Int($t49793_i5917, $t49796_i5918);
                  }
                }
                $t49886 = $rc_2840;
              }
              board = Array$from_list$List_Int($t49886);
            }
          }
          {
            let piece;
            {
              let $t49887;
              $t49887 = get_str_attr(el, "data-piece", "I");
              {
                let $rc_2839;
                if ($t49887 === "I") {
                  $rc_2839 = { $: "I" };
                } else if ($t49887 === "O") {
                  $rc_2839 = { $: "O" };
                } else if ($t49887 === "T") {
                  $rc_2839 = { $: "T" };
                } else if ($t49887 === "S") {
                  $rc_2839 = { $: "S" };
                } else if ($t49887 === "Z") {
                  $rc_2839 = { $: "Z" };
                } else if ($t49887 === "J") {
                  $rc_2839 = { $: "J" };
                } else {
                  $rc_2839 = { $: "L" };
                }
                piece = $rc_2839;
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
                      let $t49888;
                      $t49888 = get_str_attr(el, "data-next", "O");
                      {
                        let $rc_2838;
                        if ($t49888 === "I") {
                          $rc_2838 = { $: "I" };
                        } else if ($t49888 === "O") {
                          $rc_2838 = { $: "O" };
                        } else if ($t49888 === "T") {
                          $rc_2838 = { $: "T" };
                        } else if ($t49888 === "S") {
                          $rc_2838 = { $: "S" };
                        } else if ($t49888 === "Z") {
                          $rc_2838 = { $: "Z" };
                        } else if ($t49888 === "J") {
                          $rc_2838 = { $: "J" };
                        } else {
                          $rc_2838 = { $: "L" };
                        }
                        next = $rc_2838;
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
                              const $t49889 = f._0(f, board, piece, rot, x, y, next, score, lines, rng);
                              const $f49909 = $t49889._0;
                              const $f49910 = $t49889._1;
                              const $f49911 = $t49889._2;
                              const $f49912 = $t49889._3;
                              const $f49913 = $t49889._4;
                              const $f49914 = $t49889._5;
                              const $f49915 = $t49889._6;
                              const $f49916 = $t49889._7;
                              const $f49917 = $t49889._8;
                              const $f49918 = $t49889._9;
                              {
                                const over2 = $f49918;
                                {
                                  const rng2 = $f49917;
                                  {
                                    const lines2 = $f49916;
                                    {
                                      const score2 = $f49915;
                                      {
                                        const next2 = $f49914;
                                        {
                                          const y2 = $f49913;
                                          {
                                            const x2 = $f49912;
                                            {
                                              const rot2 = $f49911;
                                              {
                                                const piece2 = $f49910;
                                                {
                                                  const board2 = $f49909;
                                                  {
                                                    let $eff;
                                                    {
                                                      let $t49849_i5912;
                                                      {
                                                        const go_i14717 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                                                        {
                                                          const $t2290_i14719 = { $: "Nil" };
                                                          $t49849_i5912 = go$apply$0_List_range(go_i14717, 19, $t2290_i14719);
                                                        }
                                                      }
                                                      {
                                                        const $t49861_i5913 = { $: "$Clo_$lam0_render_board$0_render_board", _0: $lam0_render_board$apply$0_render_board, _1: board2 };
                                                        {
                                                          const f_i14713 = $t49861_i5913;
                                                          {
                                                            const go_i14714 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i14713 };
                                                            $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i14714, $t49849_i5912);
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                  {
                                                    let $eff;
                                                    if (over2 === false) {
                                                      {
                                                        const base_cells_i5907 = TetrisLogic$piece_cells(piece2);
                                                        {
                                                          const rotated_i5908 = rotate_n(base_cells_i5907, rot2);
                                                          {
                                                            const $t49881_i5909 = { $: "$Clo_$lam0_render_falling$0_render_falling", _0: $lam0_render_falling$apply$0_render_falling, _1: x2, _2: y2, _3: piece2 };
                                                            {
                                                              const f_i14710 = $t49881_i5909;
                                                              {
                                                                const go_i14711 = { $: "$Clo_go$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_", _0: go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_, _1: f_i14710 };
                                                                $eff = go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_(go_i14711, rotated_i5908);
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
                                                      let $t49891;
                                                      {
                                                        const $t49890 = String(score2);
                                                        {
                                                          const $rc_2837 = ("Score: " + $t49890);
                                                          $t49891 = $rc_2837;
                                                        }
                                                      }
                                                      $eff = set_text_if_found("score", $t49891);
                                                    }
                                                  }
                                                  {
                                                    let $eff;
                                                    {
                                                      let $t49894;
                                                      {
                                                        let $t49893;
                                                        {
                                                          const $t49892 = TetrisLogic$level_for_lines(lines2);
                                                          $t49893 = String($t49892);
                                                        }
                                                        {
                                                          const $rc_2836 = ("Level: " + $t49893);
                                                          $t49894 = $rc_2836;
                                                        }
                                                      }
                                                      $eff = set_text_if_found("level", $t49894);
                                                    }
                                                  }
                                                  {
                                                    let $eff;
                                                    {
                                                      let $t49896;
                                                      {
                                                        const $t49895 = piece_to_string(next2);
                                                        {
                                                          const $rc_2835 = ("Next: " + $t49895);
                                                          $t49896 = $rc_2835;
                                                        }
                                                      }
                                                      $eff = set_text_if_found("next", $t49896);
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
                                                        let $t49898;
                                                        {
                                                          let $t49897;
                                                          {
                                                            const $t11132_i5900 = { $: "Nil" };
                                                            {
                                                              const $t11134_i5901 = { $: "$Clo_$lam0_Array_to_list$0_Array_to_list_PVec_Int", _0: $lam0_Array_to_list$apply$0_Array_to_list_PVec_Int };
                                                              {
                                                                const rev_i5902 = Array$fold_left$PVec_Int$List_Int$Fn_List_Int_Int_List_Int(board2, $t11132_i5900, $t11134_i5901);
                                                                {
                                                                  const go_i14707 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                                                                  {
                                                                    const $t10718_i14708 = { $: "Nil" };
                                                                    $t49897 = go$apply$0_Array_lst_rev_List_Int(go_i14707, rev_i5902, $t10718_i14708);
                                                                  }
                                                                }
                                                              }
                                                            }
                                                          }
                                                          $t49898 = int_list_to_string($t49897);
                                                        }
                                                        $eff = Js$Dom$set_attr(el, "data-board", $t49898);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        let $t49899;
                                                        {
                                                          const $rc_2834 = piece_to_string(piece2);
                                                          $t49899 = $rc_2834;
                                                        }
                                                        $eff = Js$Dom$set_attr(el, "data-piece", $t49899);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t49900 = String(rot2);
                                                        $eff = Js$Dom$set_attr(el, "data-rot", $t49900);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t49901 = String(x2);
                                                        $eff = Js$Dom$set_attr(el, "data-x", $t49901);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t49902 = String(y2);
                                                        $eff = Js$Dom$set_attr(el, "data-y", $t49902);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        let $t49903;
                                                        {
                                                          const $rc_2833 = piece_to_string(next2);
                                                          $t49903 = $rc_2833;
                                                        }
                                                        $eff = Js$Dom$set_attr(el, "data-next", $t49903);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t49904 = String(score2);
                                                        $eff = Js$Dom$set_attr(el, "data-score", $t49904);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t49905 = String(lines2);
                                                        $eff = Js$Dom$set_attr(el, "data-lines", $t49905);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t49906 = String(rng2);
                                                        $eff = Js$Dom$set_attr(el, "data-rng", $t49906);
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
                                                        let $t49908;
                                                        {
                                                          const $t49907 = ((seq + 1) < 4611686018427387904 && (seq + 1) >= -4611686018427387904 ? (seq + 1) : march_int_ovf((seq + 1), 0));
                                                          $t49908 = String($t49907);
                                                        }
                                                        return Js$Dom$set_attr(el, "data-seq", $t49908);
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
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
    const $t49955 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t49955, rot);
      {
        let locked;
        {
          let $t49956;
          switch (piece.$) {
            case "I": {
              $t49956 = 1;
              break;
            }
            case "O": {
              $t49956 = 2;
              break;
            }
            case "T": {
              $t49956 = 3;
              break;
            }
            case "S": {
              $t49956 = 4;
              break;
            }
            case "Z": {
              $t49956 = 5;
              break;
            }
            case "J": {
              $t49956 = 6;
              break;
            }
            case "L": {
              $t49956 = 7;
              break;
            }
            default: {
              throw march_panic_error("panic: ", "non-exhaustive pattern match");
              break;
            }
          }
          {
            const $t49767_i5925 = { $: "$Clo_$lam0_TetrisLogic_lock_piece$0_TetrisLogic_lock_piece", _0: $lam0_TetrisLogic_lock_piece$apply$0_TetrisLogic_lock_piece, _1: $t49956, _2: x, _3: y };
            locked = List$fold_left$List_T_Int_Int$PVec_Int$Fn_PVec_Int_T_Int_Int_PVec_Int(cells, board, $t49767_i5925);
          }
        }
        {
          const $t49957 = TetrisLogic$clear_lines(locked);
          const $f49991 = $t49957._0;
          const $f49992 = $t49957._1;
          {
            const n = $f49992;
            {
              const cleared_board = $f49991;
              {
                let new_score;
                {
                  let $t49958;
                  if (n === 1) {
                    $t49958 = 100;
                  } else if (n === 2) {
                    $t49958 = 300;
                  } else if (n === 3) {
                    $t49958 = 500;
                  } else if (n === 4) {
                    $t49958 = 800;
                  } else {
                    $t49958 = 0;
                  }
                  new_score = ((score + $t49958) < 4611686018427387904 && (score + $t49958) >= -4611686018427387904 ? (score + $t49958) : march_int_ovf((score + $t49958), 0));
                }
                {
                  const new_lines = ((lines + n) < 4611686018427387904 && (lines + n) >= -4611686018427387904 ? (lines + n) : march_int_ovf((lines + n), 0));
                  {
                    let $t49959;
                    $t49959 = spawn_piece(next, cleared_board, rng);
                    const $f49960 = $t49959._0;
                    const $f49961 = $t49959._1;
                    const $f49962 = $t49959._2;
                    const $f49963 = $t49959._3;
                    const $f49964 = $t49959._4;
                    const $f49965 = $t49959._5;
                    const $f49966 = $t49959._6;
                    {
                      const over = $f49966;
                      {
                        const rng2 = $f49965;
                        {
                          const next2 = $f49964;
                          {
                            const y2 = $f49963;
                            {
                              const x2 = $f49962;
                              {
                                const rot2 = $f49961;
                                {
                                  const piece2 = $f49960;
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
    let $t49998;
    {
      const $t49997 = state_el();
      $t49998 = get_str_attr($t49997, "data-paused", "false");
    }
    {
      const $rc_2842 = ($t49998 === "true");
      return $rc_2842;
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
        let $t49999;
        $t49999 = get_str_attr(el, "data-over", "false");
        {
          const $rc_2843 = ($t49999 === "true");
          over = $rc_2843;
        }
      }
      if (over === true) {
        return {  };
      } else if (over === false) {
        {
          let $t50001;
          {
            const $t50000 = is_paused();
            $t50001 = (!$t50000);
          }
          return set_paused(el, $t50001);
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
      let $t50028;
      {
        const $t50027 = ((cur_y + 1) < 4611686018427387904 && (cur_y + 1) >= -4611686018427387904 ? (cur_y + 1) : march_int_ovf((cur_y + 1), 0));
        {
          const $t49757_i5933 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: x, _3: $t50027 };
          $t50028 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t49757_i5933);
        }
      }
      if ($t50028 === true) {
        return cur_y;
      } else if ($t50028 === false) {
        {
          const $t50029 = ((cur_y + 1) < 4611686018427387904 && (cur_y + 1) >= -4611686018427387904 ? (cur_y + 1) : march_int_ovf((cur_y + 1), 0));
          {
            $tco_a0 = board;
            $tco_a1 = cells;
            $tco_a2 = x;
            $tco_a3 = $t50029;
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
        let $t49733_i5952;
        {
          const go_i14738 = { $: "$Clo_go$0_List_repeat_Int_Int", _0: go$apply$0_List_repeat_Int_Int, _1: 0 };
          {
            const $t2285_i14739 = { $: "Nil" };
            $t49733_i5952 = go$apply$0_List_repeat_Int_Int(go_i14738, 200, $t2285_i14739);
          }
        }
        board = Array$from_list$List_Int($t49733_i5952);
      }
      {
        let rng0;
        {
          let raw_i13545;
          {
            let $t49801_i13544;
            {
              let $t49800_i13543;
              {
                let $t49799_i13542;
                {
                  let $t49798_i13541;
                  {
                    const $t17791_i14827 = Authority$check("IO.Clock", "");
                    switch ($t17791_i14827.$) {
                      case "Ok": {
                        const $f17794_i14828 = $t17791_i14827._0;
                        {
                          let $t17793_i14830;
                          {
                            const $t17792_i14829 = {  };
                            $t17793_i14830 = march_unix_time();
                          }
                          $t49798_i13541 = { $: "Ok", _0: $t17793_i14830 };
                        }
                        break;
                      }
                      case "Err": {
                        const $f17795_i14831 = $t17791_i14827._0;
                        {
                          const $letq_err_i14832 = $f17795_i14831;
                          $t49798_i13541 = { $: "Err", _0: $letq_err_i14832 };
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
                    const r_i14819 = $t49798_i13541;
                    switch (r_i14819.$) {
                      case "Ok": {
                        const $f805_i14820 = r_i14819._0;
                        {
                          const v_i14821 = $f805_i14820;
                          $t49799_i13542 = v_i14821;
                        }
                        break;
                      }
                      case "Err": {
                        const $f806_i14822 = r_i14819._0;
                        {
                          const e_i14823 = $f806_i14822;
                          march_panic_site("stdlib/authority.march", 98, 14, 58);
                          {
                            let $t804_i14826;
                            {
                              const $t803_i14824 = Authority$describe(e_i14823);
                              {
                                const $rc_3040_i14825 = ("capability refused: " + $t803_i14824);
                                $t804_i14826 = $rc_3040_i14825;
                              }
                            }
                            throw march_panic_error("panic: ", $t804_i14826);
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
                $t49800_i13543 = ($t49799_i13542 * 1000000.0);
              }
              $t49801_i13544 = march_float_to_int($t49800_i13543);
            }
            raw_i13545 = march_int_mod($t49801_i13544, 2147483646);
          }
          {
            const $t49802_i13546 = (raw_i13545 <= 0);
            if ($t49802_i13546 === true) {
              rng0 = ((raw_i13545 + 2147483646) < 4611686018427387904 && (raw_i13545 + 2147483646) >= -4611686018427387904 ? (raw_i13545 + 2147483646) : march_int_ovf((raw_i13545 + 2147483646), 0));
            } else if ($t49802_i13546 === false) {
              rng0 = raw_i13545;
            } else {
              throw march_panic_error("panic: ", "non-exhaustive pattern match");
            }
          }
        }
        {
          const $t50033 = next_piece(rng0);
          const $f50079 = $t50033._0;
          const $f50080 = $t50033._1;
          {
            const rng1 = $f50080;
            {
              const first = $f50079;
              {
                let $t50034;
                $t50034 = spawn_piece(first, board, rng1);
                const $f50048 = $t50034._0;
                const $f50049 = $t50034._1;
                const $f50050 = $t50034._2;
                const $f50051 = $t50034._3;
                const $f50052 = $t50034._4;
                const $f50053 = $t50034._5;
                const $f50054 = $t50034._6;
                {
                  const rng2 = $f50053;
                  {
                    const next = $f50052;
                    {
                      const y = $f50051;
                      {
                        const x = $f50050;
                        {
                          const rot = $f50049;
                          {
                            const piece = $f50048;
                            {
                              let $eff;
                              {
                                let $t49849_i5947;
                                {
                                  const go_i14733 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                                  {
                                    const $t2290_i14735 = { $: "Nil" };
                                    $t49849_i5947 = go$apply$0_List_range(go_i14733, 19, $t2290_i14735);
                                  }
                                }
                                {
                                  const $t49861_i5948 = { $: "$Clo_$lam0_render_board$0_render_board", _0: $lam0_render_board$apply$0_render_board, _1: board };
                                  {
                                    const f_i14729 = $t49861_i5948;
                                    {
                                      const go_i14730 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i14729 };
                                      $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i14730, $t49849_i5947);
                                    }
                                  }
                                }
                              }
                            }
                            {
                              let $eff;
                              {
                                const base_cells_i5942 = TetrisLogic$piece_cells(piece);
                                {
                                  const rotated_i5943 = rotate_n(base_cells_i5942, rot);
                                  {
                                    const $t49881_i5944 = { $: "$Clo_$lam0_render_falling$0_render_falling", _0: $lam0_render_falling$apply$0_render_falling, _1: x, _2: y, _3: piece };
                                    {
                                      const f_i14726 = $t49881_i5944;
                                      {
                                        const go_i14727 = { $: "$Clo_go$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_", _0: go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_, _1: f_i14726 };
                                        $eff = go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_(go_i14727, rotated_i5943);
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
                                let $t50036;
                                {
                                  const $t50035 = piece_to_string(next);
                                  {
                                    const $rc_2846 = ("Next: " + $t50035);
                                    $t50036 = $rc_2846;
                                  }
                                }
                                $eff = set_text_if_found("next", $t50036);
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
                                let $t50038;
                                {
                                  let $t50037;
                                  {
                                    const $t11132_i5935 = { $: "Nil" };
                                    {
                                      const $t11134_i5936 = { $: "$Clo_$lam0_Array_to_list$0_Array_to_list_PVec_Int", _0: $lam0_Array_to_list$apply$0_Array_to_list_PVec_Int };
                                      {
                                        const rev_i5937 = Array$fold_left$PVec_Int$List_Int$Fn_List_Int_Int_List_Int(board, $t11132_i5935, $t11134_i5936);
                                        {
                                          const go_i14723 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                                          {
                                            const $t10718_i14724 = { $: "Nil" };
                                            $t50037 = go$apply$0_Array_lst_rev_List_Int(go_i14723, rev_i5937, $t10718_i14724);
                                          }
                                        }
                                      }
                                    }
                                  }
                                  $t50038 = int_list_to_string($t50037);
                                }
                                $eff = Js$Dom$set_attr(el, "data-board", $t50038);
                              }
                            }
                            {
                              let $eff;
                              {
                                let $t50039;
                                {
                                  const $rc_2845 = piece_to_string(piece);
                                  $t50039 = $rc_2845;
                                }
                                $eff = Js$Dom$set_attr(el, "data-piece", $t50039);
                              }
                            }
                            {
                              let $eff;
                              {
                                const $t50040 = String(rot);
                                $eff = Js$Dom$set_attr(el, "data-rot", $t50040);
                              }
                            }
                            {
                              let $eff;
                              {
                                const $t50041 = String(x);
                                $eff = Js$Dom$set_attr(el, "data-x", $t50041);
                              }
                            }
                            {
                              let $eff;
                              {
                                const $t50042 = String(y);
                                $eff = Js$Dom$set_attr(el, "data-y", $t50042);
                              }
                            }
                            {
                              let $eff;
                              {
                                let $t50043;
                                {
                                  const $rc_2844 = piece_to_string(next);
                                  $t50043 = $rc_2844;
                                }
                                $eff = Js$Dom$set_attr(el, "data-next", $t50043);
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
                                const $t50044 = String(rng2);
                                $eff = Js$Dom$set_attr(el, "data-rng", $t50044);
                              }
                            }
                            {
                              let $eff;
                              $eff = Js$Dom$set_attr(el, "data-over", "false");
                            }
                            {
                              let $t50047;
                              {
                                let $t50046;
                                {
                                  let $t50045;
                                  $t50045 = get_int_attr(el, "data-seq", 0);
                                  $t50046 = (($t50045 + 1) < 4611686018427387904 && ($t50045 + 1) >= -4611686018427387904 ? ($t50045 + 1) : march_int_ovf(($t50045 + 1), 0));
                                }
                                $t50047 = String($t50046);
                              }
                              return Js$Dom$set_attr(el, "data-seq", $t50047);
                            }
                          }
                        }
                      }
                    }
                  }
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
    const $t50085 = Js$Dom$find("restore-request");
    switch ($t50085.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f50101 = $t50085._0;
        {
          const req = $f50101;
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
                                  let $t50086;
                                  $t50086 = get_str_attr(req, "data-over", "false");
                                  {
                                    const $rc_2852 = ($t50086 === "true");
                                    over = $rc_2852;
                                  }
                                }
                                {
                                  let paused;
                                  {
                                    const $t50087 = get_str_attr(req, "data-paused", "false");
                                    {
                                      const $rc_2851 = ($t50087 === "true");
                                      paused = $rc_2851;
                                    }
                                  }
                                  {
                                    let board;
                                    {
                                      let $t50088;
                                      {
                                        const $t49793_i5967 = march_string_split(board_s, ",");
                                        {
                                          const $t49796_i5968 = { $: "$Clo_$lam0_string_to_int_list$0_string_to_int_list", _0: $lam0_string_to_int_list$apply$0_string_to_int_list };
                                          $t50088 = List$map$List_String$Fn_String_Int($t49793_i5967, $t49796_i5968);
                                        }
                                      }
                                      board = Array$from_list$List_Int($t50088);
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
                                            let $t49849_i5962;
                                            {
                                              const go_i14748 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                                              {
                                                const $t2290_i14750 = { $: "Nil" };
                                                $t49849_i5962 = go$apply$0_List_range(go_i14748, 19, $t2290_i14750);
                                              }
                                            }
                                            {
                                              const $t49861_i5963 = { $: "$Clo_$lam0_render_board$0_render_board", _0: $lam0_render_board$apply$0_render_board, _1: board };
                                              {
                                                const f_i14744 = $t49861_i5963;
                                                {
                                                  const go_i14745 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i14744 };
                                                  $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i14745, $t49849_i5962);
                                                }
                                              }
                                            }
                                          }
                                        }
                                        {
                                          let $eff;
                                          if (over === false) {
                                            {
                                              const base_cells_i5957 = TetrisLogic$piece_cells(piece);
                                              {
                                                const rotated_i5958 = rotate_n(base_cells_i5957, rot);
                                                {
                                                  const $t49881_i5959 = { $: "$Clo_$lam0_render_falling$0_render_falling", _0: $lam0_render_falling$apply$0_render_falling, _1: x, _2: y, _3: piece };
                                                  {
                                                    const f_i14741 = $t49881_i5959;
                                                    {
                                                      const go_i14742 = { $: "$Clo_go$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_", _0: go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_, _1: f_i14741 };
                                                      $eff = go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_(go_i14742, rotated_i5958);
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
                                            let $t50090;
                                            {
                                              const $t50089 = String(score);
                                              {
                                                const $rc_2850 = ("Score: " + $t50089);
                                                $t50090 = $rc_2850;
                                              }
                                            }
                                            $eff = set_text_if_found("score", $t50090);
                                          }
                                        }
                                        {
                                          let $eff;
                                          {
                                            let $t50093;
                                            {
                                              let $t50092;
                                              {
                                                const $t50091 = TetrisLogic$level_for_lines(lines);
                                                $t50092 = String($t50091);
                                              }
                                              {
                                                const $rc_2849 = ("Level: " + $t50092);
                                                $t50093 = $rc_2849;
                                              }
                                            }
                                            $eff = set_text_if_found("level", $t50093);
                                          }
                                        }
                                        {
                                          let $eff;
                                          {
                                            let $t50095;
                                            {
                                              let $t50094;
                                              {
                                                const $rc_2848 = piece_to_string(next);
                                                $t50094 = $rc_2848;
                                              }
                                              {
                                                const $rc_2847 = ("Next: " + $t50094);
                                                $t50095 = $rc_2847;
                                              }
                                            }
                                            $eff = set_text_if_found("next", $t50095);
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
                                              const $t50096 = String(rot);
                                              $eff = Js$Dom$set_attr(el, "data-rot", $t50096);
                                            }
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t50097 = String(x);
                                              $eff = Js$Dom$set_attr(el, "data-x", $t50097);
                                            }
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t50098 = String(y);
                                              $eff = Js$Dom$set_attr(el, "data-y", $t50098);
                                            }
                                          }
                                          {
                                            let $eff;
                                            $eff = Js$Dom$set_attr(el, "data-next", next_s);
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t50099 = String(score);
                                              $eff = Js$Dom$set_attr(el, "data-score", $t50099);
                                            }
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t50100 = String(lines);
                                              $eff = Js$Dom$set_attr(el, "data-lines", $t50100);
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
      const ev_i13549 = ev;
      {
        const $rc_2783_i13550 = dom_event_key$clo._0(dom_event_key$clo, ev);
        key = $rc_2783_i13550;
      }
    }
    {
      let $eff;
      {
        let $t50113;
        if (key === "ArrowLeft") {
          $t50113 = true;
        } else if (key === "ArrowRight") {
          $t50113 = true;
        } else if (key === "ArrowDown") {
          $t50113 = true;
        } else if (key === "ArrowUp") {
          $t50113 = true;
        } else if (key === " ") {
          $t50113 = true;
        } else {
          $t50113 = false;
        }
        if ($t50113 === true) {
          {
            const ev_i13547 = ev;
            {
              const $rc_2784_i13548 = dom_prevent_default$clo._0(dom_prevent_default$clo, ev);
              $eff = $rc_2784_i13548;
            }
          }
        } else if ($t50113 === false) {
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
          const $t50114 = is_paused();
          if ($t50114 === true) {
            return {  };
          } else if ($t50114 === false) {
            if (k === "ArrowLeft") {
              {
                const $t50115 = march_int_ovf(-(1), 3);
                {
                  const $t50021_i5979 = { $: "$Clo_$lam0_try_move$0_try_move", _0: $lam0_try_move$apply$0_try_move, _1: $t50115, _2: 0 };
                  return with_state($t50021_i5979);
                }
              }
            } else if (k === "ArrowRight") {
              {
                const $t50021_i5982 = { $: "$Clo_$lam0_try_move$0_try_move", _0: $lam0_try_move$apply$0_try_move, _1: 1, _2: 0 };
                return with_state($t50021_i5982);
              }
            } else if (k === "ArrowDown") {
              {
                const $t50021_i5985 = { $: "$Clo_$lam0_try_move$0_try_move", _0: $lam0_try_move$apply$0_try_move, _1: 0, _2: 1 };
                return with_state($t50021_i5985);
              }
            } else if (k === "ArrowUp") {
              {
                const $t50026_i5986 = { $: "$Clo_$lam0_try_rotate$0_try_rotate", _0: $lam0_try_rotate$apply$0_try_rotate };
                return with_state($t50026_i5986);
              }
            } else if (k === " ") {
              {
                const $t50032_i5987 = { $: "$Clo_$lam0_hard_drop$0_hard_drop", _0: $lam0_hard_drop$apply$0_hard_drop };
                return with_state($t50032_i5987);
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
    const $t50134 = Js$Dom$find("board");
    switch ($t50134.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f50142 = $t50134._0;
        {
          const board_el = $f50142;
          {
            let $eff;
            {
              let $t50103_i5996;
              {
                const go_i14762 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                {
                  const $t2290_i14764 = { $: "Nil" };
                  $t50103_i5996 = go$apply$0_List_range(go_i14762, 19, $t2290_i14764);
                }
              }
              {
                const $t50112_i5997 = { $: "$Clo_$lam0_build_board_dom$0_build_board_dom", _0: $lam0_build_board_dom$apply$0_build_board_dom, _1: board_el };
                {
                  const f_i14758 = $t50112_i5997;
                  {
                    const go_i14759 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i14758 };
                    $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i14759, $t50103_i5996);
                  }
                }
              }
            }
          }
          restart();
          {
            let $eff;
            {
              const $t50135 = dom_body();
              {
                const $t50137 = { $: "$Clo_$lam0_main$0_main", _0: $lam0_main$apply$0_main };
                $eff = Js$Dom$listen($t50135, "keydown", $t50137);
              }
            }
          }
          {
            let $eff;
            {
              let level_i5991;
              {
                let $t50010_i5990;
                {
                  const $t50009_i5989 = state_el();
                  $t50010_i5990 = get_int_attr($t50009_i5989, "data-lines", 0);
                }
                level_i5991 = TetrisLogic$level_for_lines($t50010_i5990);
              }
              {
                let $t50011_i5992;
                {
                  let $t49727_i14755;
                  {
                    const $t49726_i14754 = ((level_i5991 * 40) < 4611686018427387904 && (level_i5991 * 40) >= -4611686018427387904 ? (level_i5991 * 40) : march_int_ovf((level_i5991 * 40), 2));
                    $t49727_i14755 = ((500 - $t49726_i14754) < 4611686018427387904 && (500 - $t49726_i14754) >= -4611686018427387904 ? (500 - $t49726_i14754) : march_int_ovf((500 - $t49726_i14754), 1));
                  }
                  {
                    const $t3911_i5850_i14756 = ($t49727_i14755 > 100);
                    if ($t3911_i5850_i14756 === true) {
                      $t50011_i5992 = $t49727_i14755;
                    } else {
                      $t50011_i5992 = 100;
                    }
                  }
                }
                {
                  const $t50013_i5993 = { $: "$Clo_$lam0_schedule_tick$0_schedule_tick", _0: $lam0_schedule_tick$apply$0_schedule_tick };
                  $eff = Js$Dom$set_timeout($t50011_i5992, $t50013_i5993);
                }
              }
            }
          }
          {
            const $t50138 = Js$Dom$find("restore-trigger");
            switch ($t50138.$) {
              case "None": {
                return {  };
                break;
              }
              case "Some": {
                const $f50141 = $t50138._0;
                {
                  const trigger = $f50141;
                  {
                    const $t50140 = { $: "$Clo_$lam1_main$1_main", _0: $lam1_main$apply$1_main };
                    return Js$Dom$listen(trigger, "click", $t50140);
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
        const $f2536 = xs._0;
        const $f2537 = xs._1;
        {
          const t = $f2537;
          {
            let h;
            h = $f2536;
            {
              let $t2535;
              $t2535 = pred._0(pred, h);
              if ($t2535 === true) {
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
        const $f2399 = xs._0;
        const $f2400 = xs._1;
        {
          const t = $f2400;
          {
            const h = $f2399;
            {
              let $t2397;
              $t2397 = pred._0(pred, h);
              if ($t2397 === true) {
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
      const $f2228 = opt._0;
      {
        let x;
        x = $f2228;
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
      const go_i6314 = { $: "$Clo_go$0_Array_lst_len_List_Int", _0: go$apply$0_Array_lst_len_List_Int };
      n = go$apply$0_Array_lst_len_List_Int(go_i6314, xs, 0);
    }
    {
      const $t11237 = (n === 0);
      if ($t11237 === true) {
        {
          const $t10924_i6311 = { $: "TrieEmpty" };
          {
            const $t10925_i6312 = { $: "Nil" };
            return { $: "PVec", _0: 0, _1: 0, _2: $t10924_i6311, _3: $t10925_i6312 };
          }
        }
      } else {
        {
          let tail_len;
          {
            let $t11240;
            {
              let $t11239;
              {
                const $t11238 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                $t11239 = (32 === 0 ? march_div_zero() : ($t11238 - $t11238 % 32) / 32);
              }
              $t11240 = ((32 * $t11239) < 4611686018427387904 && (32 * $t11239) >= -4611686018427387904 ? (32 * $t11239) : march_int_ovf((32 * $t11239), 2));
            }
            tail_len = ((n - $t11240) < 4611686018427387904 && (n - $t11240) >= -4611686018427387904 ? (n - $t11240) : march_int_ovf((n - $t11240), 1));
          }
          {
            let $p11262;
            {
              const $t11241 = ((n - tail_len) < 4611686018427387904 && (n - tail_len) >= -4611686018427387904 ? (n - tail_len) : march_int_ovf((n - tail_len), 1));
              {
                const go_i6309 = { $: "$Clo_go$0_Array_lst_split_List_Int_Int", _0: go$apply$0_Array_lst_split_List_Int_Int };
                {
                  const $t11151_i6310 = { $: "Nil" };
                  $p11262 = go$apply$0_Array_lst_split_List_Int_Int(go_i6309, xs, $t11241, $t11151_i6310);
                }
              }
            }
            {
              const front = $p11262._0;
              {
                const tail = $p11262._1;
                {
                  const $t11242 = (n === tail_len);
                  if ($t11242 === true) {
                    {
                      const $t11243 = { $: "TrieEmpty" };
                      {
                        const $rc_3038 = { $: "PVec", _0: n, _1: 0, _2: $t11243, _3: tail };
                        return $rc_3038;
                      }
                    }
                  } else {
                    {
                      const up = { $: "$Clo_up$0_Array_from_list_List_Int", _0: up$apply$0_Array_from_list_List_Int };
                      {
                        let $p11261;
                        {
                          const $t11259 = { $: "$Clo_$lam0_Array_from_list$2_Array_from_list_List_Int", _0: $lam0_Array_from_list$apply$2_Array_from_list_List_Int };
                          {
                            let $t11260;
                            {
                              const wrap_i6303 = $t11259;
                              {
                                const chunk_i6304 = { $: "$Clo_chunk$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int", _0: chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int, _1: wrap_i6303 };
                                {
                                  const $t11171_i6305 = { $: "Nil" };
                                  {
                                    const $t11172_i6306 = { $: "Nil" };
                                    $t11260 = chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int(chunk_i6304, front, 0, $t11171_i6305, $t11172_i6306);
                                  }
                                }
                              }
                            }
                            $p11261 = up$apply$0_Array_from_list_List_Int(up, $t11260, 0);
                          }
                        }
                        {
                          const root = $p11261._0;
                          {
                            const shift = $p11261._1;
                            {
                              const $rc_3034 = { $: "PVec", _0: n, _1: shift, _2: root, _3: tail };
                              return $rc_3034;
                            }
                          }
                        }
                      }
                    }
                  }
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
        const $f2529 = xs._0;
        const $f2530 = xs._1;
        {
          const t = $f2530;
          {
            const h = $f2529;
            {
              let $t2528;
              $t2528 = pred._0(pred, h);
              if ($t2528 === true) {
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
      const $f10979 = v._0;
      const $f10980 = v._1;
      const $f10981 = v._2;
      const $f10982 = v._3;
      {
        const tail = $f10982;
        {
          const root = $f10981;
          {
            const shift = $f10980;
            {
              const n = $f10979;
              {
                let $t10976;
                {
                  const $t10974 = (idx < 0);
                  {
                    const $t10975 = (idx >= n);
                    $t10976 = ($t10974 || $t10975);
                  }
                }
                if ($t10976 === true) {
                  march_panic_site("stdlib/array.march", 432, 32, 70);
                  return (() => { throw march_panic_error("panic: ", "Array.get: index out of range"); })();
                } else {
                  {
                    let tail_len;
                    {
                      const go_i6316 = { $: "$Clo_go$0_Array_lst_len_List_Int", _0: go$apply$0_Array_lst_len_List_Int };
                      tail_len = go$apply$0_Array_lst_len_List_Int(go_i6316, tail, 0);
                    }
                    {
                      const tail_offset = ((n - tail_len) < 4611686018427387904 && (n - tail_len) >= -4611686018427387904 ? (n - tail_len) : march_int_ovf((n - tail_len), 1));
                      {
                        const $t10977 = (idx >= tail_offset);
                        if ($t10977 === true) {
                          {
                            const $t10978 = ((idx - tail_offset) < 4611686018427387904 && (idx - tail_offset) >= -4611686018427387904 ? (idx - tail_offset) : march_int_ovf((idx - tail_offset), 1));
                            {
                              const $rc_3039 = Array$lst_nth$List_Int$Int(tail, $t10978);
                              return $rc_3039;
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
        const $f2466 = xs._0;
        const $f2467 = xs._1;
        {
          const t = $f2467;
          {
            const h = $f2466;
            {
              let $t2465;
              $t2465 = f._0(f, acc, h);
              {
                $tco_a0 = t;
                $tco_a1 = $t2465;
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
      const $f11002 = v._0;
      const $f11003 = v._1;
      const $f11004 = v._2;
      const $f11005 = v._3;
      {
        const tail = $f11005;
        {
          const root = $f11004;
          {
            const shift = $f11003;
            {
              const n = $f11002;
              {
                let $t10997;
                {
                  const $t10995 = (idx < 0);
                  {
                    const $t10996 = (idx >= n);
                    $t10997 = ($t10995 || $t10996);
                  }
                }
                if ($t10997 === true) {
                  march_panic_site("stdlib/array.march", 463, 32, 70);
                  return (() => { throw march_panic_error("panic: ", "Array.set: index out of range"); })();
                } else {
                  {
                    let tail_len;
                    {
                      const go_i6329 = { $: "$Clo_go$0_Array_lst_len_List_Int", _0: go$apply$0_Array_lst_len_List_Int };
                      tail_len = go$apply$0_Array_lst_len_List_Int(go_i6329, tail, 0);
                    }
                    {
                      const tail_offset = ((n - tail_len) < 4611686018427387904 && (n - tail_len) >= -4611686018427387904 ? (n - tail_len) : march_int_ovf((n - tail_len), 1));
                      {
                        const $t10998 = (idx >= tail_offset);
                        if ($t10998 === true) {
                          {
                            const $t10999 = ((idx - tail_offset) < 4611686018427387904 && (idx - tail_offset) >= -4611686018427387904 ? (idx - tail_offset) : march_int_ovf((idx - tail_offset), 1));
                            {
                              let $t11000;
                              {
                                const rev_onto_i6325 = { $: "$Clo_rev_onto$0_Array_lst_set_List_Int_Int_Int", _0: rev_onto$apply$0_Array_lst_set_List_Int_Int_Int };
                                {
                                  const go_i6326 = { $: "$Clo_go$1_Array_lst_set_List_Int_Int_Int", _0: go$apply$1_Array_lst_set_List_Int_Int_Int, _1: rev_onto_i6325, _2: val };
                                  {
                                    const $t10750_i6327 = { $: "Nil" };
                                    $t11000 = go$apply$1_Array_lst_set_List_Int_Int_Int(go_i6326, tail, $t10999, $t10750_i6327);
                                  }
                                }
                              }
                              return { $: "PVec", _0: n, _1: shift, _2: root, _3: $t11000 };
                            }
                          }
                        } else {
                          {
                            let $t11001;
                            {
                              const $t10834_i6321 = { $: "Nil" };
                              $t11001 = Array$trie_update_down$TrieNode_Int$Int$List_T_List_TrieNode_Int_Int$Int$Int(root, shift, $t10834_i6321, idx, val);
                            }
                            return { $: "PVec", _0: n, _1: shift, _2: $t11001, _3: tail };
                          }
                        }
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
      const $f2369 = xs._0;
      const $f2370 = xs._1;
      {
        const t = $f2370;
        {
          const h = $f2369;
          {
            let $t2367;
            $t2367 = f._0(f, h);
            {
              const $trmc38 = { $: "Cons", _0: $t2367, _1: null };
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
        const $f2331 = xs._0;
        const $f2332 = xs._1;
        {
          const t = $f2332;
          {
            const h = $f2331;
            {
              const $t2329 = (n === 0);
              if ($t2329 === true) {
                return h;
              } else {
                {
                  const $t2330 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                  {
                    $tco_a0 = t;
                    $tco_a1 = $t2330;
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
        const $f2369 = xs._0;
        const $f2370 = xs._1;
        {
          const t = $f2370;
          {
            const h = $f2369;
            {
              let $t2367;
              $t2367 = f._0(f, h);
              {
                const $trmc37 = { $: "Cons", _0: $t2367, _1: null };
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
        const $f2369 = xs._0;
        const $f2370 = xs._1;
        {
          const t = $f2370;
          {
            const h = $f2369;
            {
              let $t2367;
              $t2367 = f._0(f, h);
              {
                const $trmc37 = { $: "Cons", _0: $t2367, _1: null };
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
        const $f2361 = xs._0;
        const $f2362 = xs._1;
        {
          const t = $f2362;
          {
            const h = $f2361;
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
        const $f2346 = lst._0;
        const $f2347 = lst._1;
        {
          const t = $f2347;
          {
            const $t2345 = ((acc + 1) < 4611686018427387904 && (acc + 1) >= -4611686018427387904 ? (acc + 1) : march_int_ovf((acc + 1), 0));
            {
              $tco_a0 = t;
              $tco_a1 = $t2345;
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
        const $f2399 = xs._0;
        const $f2400 = xs._1;
        {
          const t = $f2400;
          {
            const h = $f2399;
            {
              let $t2397;
              $t2397 = pred._0(pred, h);
              if ($t2397 === true) {
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
        const $f2369 = xs._0;
        const $f2370 = xs._1;
        {
          const t = $f2370;
          {
            const h = $f2369;
            {
              let $t2367;
              $t2367 = f._0(f, h);
              {
                const $trmc37 = { $: "Cons", _0: $t2367, _1: null };
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
        const $f10721 = lst._0;
        const $f10722 = lst._1;
        {
          const t = $f10722;
          {
            let h;
            h = $f10721;
            {
              const $t10719 = (n === 0);
              if ($t10719 === true) {
                return h;
              } else {
                {
                  const $t10720 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                  {
                    $tco_a0 = t;
                    $tco_a1 = $t10720;
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
        const $f10815 = node._0;
        {
          const values = $f10815;
          {
            const $t10812 = ((idx | 0) === idx && (31 | 0) === 31 ? (idx & 31) : march_int_and(idx, 31));
            {
              const $rc_3109 = Array$lst_nth$List_Int$Int(values, $t10812);
              return $rc_3109;
            }
          }
        }
        break;
      }
      case "TrieBranch": {
        const $f10816 = node._0;
        {
          const children = $f10816;
          {
            let slot;
            {
              const $t10811_i7859 = ((idx | 0) === idx && shift >= 0 && shift < 32 ? (idx >> shift) : march_int_shr(idx, shift));
              slot = (($t10811_i7859 | 0) === $t10811_i7859 && (31 | 0) === 31 ? ($t10811_i7859 & 31) : march_int_and($t10811_i7859, 31));
            }
            {
              const $t10813 = Array$lst_nth$List_TrieNode_Int$Int(children, slot);
              {
                const $t10814 = ((shift - 5) < 4611686018427387904 && (shift - 5) >= -4611686018427387904 ? (shift - 5) : march_int_ovf((shift - 5), 1));
                {
                  $tco_a0 = $t10813;
                  $tco_a1 = idx;
                  $tco_a2 = $t10814;
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
        const $f2391 = sub._0;
        const $f2392 = sub._1;
        {
          const rest = $f2392;
          {
            const x = $f2391;
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
            const $f2385 = lst._0;
            const $f2386 = lst._1;
            {
              const t = $f2386;
              {
                const h = $f2385;
                {
                  let $t2384;
                  $t2384 = f._0(f, h);
                  {
                    $tco_a0 = $t2384;
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
        const $f2369 = xs._0;
        const $f2370 = xs._1;
        {
          const t = $f2370;
          {
            const h = $f2369;
            {
              let $t2367;
              $t2367 = f._0(f, h);
              {
                const $trmc37 = { $: "Cons", _0: $t2367, _1: null };
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
      const $f11116 = v._0;
      const $f11117 = v._1;
      const $f11118 = v._2;
      const $f11119 = v._3;
      {
        const tail = $f11119;
        {
          const root = $f11118;
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
        const $f10721 = lst._0;
        const $f10722 = lst._1;
        {
          const t = $f10722;
          {
            const h = $f10721;
            {
              const $t10719 = (n === 0);
              if ($t10719 === true) {
                return h;
              } else {
                {
                  const $t10720 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                  {
                    $tco_a0 = t;
                    $tco_a1 = $t10720;
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
        const $f10832 = n._0;
        {
          const values = $f10832;
          {
            let $t10828;
            {
              const $t10826 = ((idx | 0) === idx && (31 | 0) === 31 ? (idx & 31) : march_int_and(idx, 31));
              {
                let $t10827;
                {
                  const rev_onto_i7925 = { $: "$Clo_rev_onto$0_Array_lst_set_List_Int_Int_Int", _0: rev_onto$apply$0_Array_lst_set_List_Int_Int_Int };
                  {
                    const go_i7926 = { $: "$Clo_go$1_Array_lst_set_List_Int_Int_Int", _0: go$apply$1_Array_lst_set_List_Int_Int_Int, _1: rev_onto_i7925, _2: val };
                    {
                      const $t10750_i7927 = { $: "Nil" };
                      $t10827 = go$apply$1_Array_lst_set_List_Int_Int_Int(go_i7926, values, $t10826, $t10750_i7927);
                    }
                  }
                }
                $t10828 = { $: "TrieLeaf", _0: $t10827 };
              }
            }
            {
              const $rc_3129 = Array$trie_update_up$TrieNode_Int$List_T_List_TrieNode_Int_Int($t10828, path);
              return $rc_3129;
            }
          }
        }
        break;
      }
      case "TrieBranch": {
        const $f10833 = n._0;
        {
          const children = $f10833;
          {
            let slot;
            {
              const $t10811_i7930 = ((idx | 0) === idx && s >= 0 && s < 32 ? (idx >> s) : march_int_shr(idx, s));
              slot = (($t10811_i7930 | 0) === $t10811_i7930 && (31 | 0) === 31 ? ($t10811_i7930 & 31) : march_int_and($t10811_i7930, 31));
            }
            {
              let child;
              child = Array$lst_nth$List_TrieNode_Int$Int(children, slot);
              {
                const $t10829 = ((s - 5) < 4611686018427387904 && (s - 5) >= -4611686018427387904 ? (s - 5) : march_int_ovf((s - 5), 1));
                {
                  const $t10830 = { _0: children, _1: slot };
                  {
                    const $t10831 = { $: "Cons", _0: $t10830, _1: path };
                    {
                      $tco_a0 = child;
                      $tco_a1 = $t10829;
                      $tco_a2 = $t10831;
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
        const $f2391 = sub._0;
        const $f2392 = sub._1;
        {
          const rest = $f2392;
          {
            const x = $f2391;
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
            const $f2385 = lst._0;
            const $f2386 = lst._1;
            {
              const t = $f2386;
              {
                const h = $f2385;
                {
                  let $t2384;
                  $t2384 = f._0(f, h);
                  {
                    $tco_a0 = $t2384;
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
      const $f10922 = node._0;
      {
        const values = $f10922;
        {
          const go = { $: "$Clo_go$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int", _0: go$apply$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int, _1: f };
          return go$apply$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int(go, acc, values);
        }
      }
      break;
    }
    case "TrieBranch": {
      const $f10923 = node._0;
      {
        const children = $f10923;
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
        const $f10820 = stk._0;
        const $f10821 = stk._1;
        {
          const rest = $f10821;
          {
            const frame = $f10820;
            {
              const children = frame._0;
              {
                const slot = frame._1;
                {
                  let $t10818;
                  {
                    let $t10817;
                    {
                      const rev_onto_i7999 = { $: "$Clo_rev_onto$0_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int", _0: rev_onto$apply$0_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int };
                      {
                        const go_i8000 = { $: "$Clo_go$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int", _0: go$apply$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int, _1: nd, _2: rev_onto_i7999 };
                        {
                          const $t10810_i8001 = { $: "Nil" };
                          $t10817 = go$apply$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int(go_i8000, children, slot, $t10810_i8001);
                        }
                      }
                    }
                    $t10818 = { $: "TrieBranch", _0: $t10817 };
                  }
                  {
                    $tco_a0 = $t10818;
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
      const $t1465 = { $: "Nil" };
      return Authority$parse_entries(toks, $t1465);
    }
  }
}
const $jp1_Authority_parse$apply$0_Authority_parse$clo = { _0: ($_, $clo) => $jp1_Authority_parse$apply$0_Authority_parse($clo) };

function $jp2_Authority_parse$apply$1_Authority_parse($clo) {
  {
    const $jp_clo1471 = $clo._1;
    return $jp_clo1471._0($jp_clo1471);
  }
}
const $jp2_Authority_parse$apply$1_Authority_parse$clo = { _0: ($_, $clo) => $jp2_Authority_parse$apply$1_Authority_parse($clo) };

function $jp3_Authority_parse$apply$2_Authority_parse($clo) {
  {
    const $jp_clo1473 = $clo._1;
    return $jp_clo1473._0($jp_clo1473);
  }
}
const $jp3_Authority_parse$apply$2_Authority_parse$clo = { _0: ($_, $clo) => $jp3_Authority_parse$apply$2_Authority_parse($clo) };

function $jp7_Authority_parse_option$apply$0_Authority_parse_option($clo) {
  {
    const $f1716 = $clo._1;
    {
      const name = $clo._2;
      {
        let more;
        more = $f1716;
        {
          const $t1699 = (name === "methods");
          if ($t1699 === true) {
            {
              let $t1701;
              {
                const $t1700 = { $: "Nil" };
                $t1701 = Authority$method_words(more, $t1700);
              }
              switch ($t1701.$) {
                case "Err": {
                  const $f1705 = $t1701._0;
                  {
                    const e = $f1705;
                    return { $: "Err", _0: e };
                  }
                  break;
                }
                case "Ok": {
                  const $f1706 = $t1701._0;
                  const $f1707 = $f1706._0;
                  const $f1708 = $f1706._1;
                  {
                    const rest = $f1708;
                    {
                      const ms = $f1707;
                      {
                        let $t1703;
                        {
                          let $t1702;
                          {
                            const $rc_3149 = march_string_join(ms, ",");
                            $t1702 = $rc_3149;
                          }
                          {
                            const $rc_3148 = ("methods=" + $t1702);
                            $t1703 = $rc_3148;
                          }
                        }
                        {
                          const $t1704 = { _0: $t1703, _1: rest };
                          return { $: "Ok", _0: $t1704 };
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
              const $t1713 = march_string_concat3("`", name, "(...)` takes one quoted string");
              return { $: "Err", _0: $t1713 };
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
    const $f1746 = $clo._1;
    {
      const $f1747 = $clo._2;
      {
        const acc = $clo._3;
        {
          const $jp_clo1755 = { $: "$Clo_$jp3_Authority_method_words$1_Authority_method_words", _0: $jp3_Authority_method_words$apply$1_Authority_method_words };
          switch ($f1747.$) {
            case "Cons": {
              const $f1756 = $f1747._0;
              const $f1757 = $f1747._1;
              if ($f1756 === ")") {
                {
                  const rest = $f1757;
                  {
                    let m;
                    m = $f1746;
                    {
                      let $t1741;
                      {
                        const $t1629_i8020 = (m !== "");
                        if ($t1629_i8020 === true) {
                          $t1741 = Authority$all_chars(m, "abcdefghijklmnopqrstuvwxyz_", 0);
                        } else {
                          $t1741 = false;
                        }
                      }
                      if ($t1741 === true) {
                        {
                          let $t1742;
                          $t1742 = { $: "Cons", _0: m, _1: acc };
                          {
                            const $t1743 = { $: "Nil" };
                            {
                              const $t1744 = Authority$rev($t1742, $t1743);
                              {
                                let $t1745;
                                $t1745 = { _0: $t1744, _1: rest };
                                return { $: "Ok", _0: $t1745 };
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
          const $t2286 = (i < start);
          if ($t2286 === true) {
            return acc;
          } else {
            {
              const $t2287 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
              {
                const $t2288 = { $: "Cons", _0: i, _1: acc };
                {
                  $tco_a0 = go;
                  $tco_a1 = $t2287;
                  $tco_a2 = $t2288;
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
        const $f49751 = c._0;
        const $f49752 = c._1;
        {
          const dy = $f49752;
          {
            const dx = $f49751;
            {
              const x = ((origin_x + dx) < 4611686018427387904 && (origin_x + dx) >= -4611686018427387904 ? (origin_x + dx) : march_int_ovf((origin_x + dx), 0));
              {
                const y = ((origin_y + dy) < 4611686018427387904 && (origin_y + dy) >= -4611686018427387904 ? (origin_y + dy) : march_int_ovf((origin_y + dy), 0));
                {
                  let $t49748;
                  {
                    let $t49745_i8920;
                    {
                      let $t49743_i8918;
                      {
                        const $t49741_i8916 = (x >= 0);
                        if ($t49741_i8916 === true) {
                          $t49743_i8918 = (x < 10);
                        } else {
                          $t49743_i8918 = false;
                        }
                      }
                      {
                        const $t49744_i8919 = (y >= 0);
                        $t49745_i8920 = ($t49743_i8918 && $t49744_i8919);
                      }
                    }
                    if ($t49745_i8920 === true) {
                      $t49748 = (y < 20);
                    } else {
                      $t49748 = false;
                    }
                  }
                  if ($t49748 === false) {
                    return true;
                  } else if ($t49748 === true) {
                    {
                      let $t49750;
                      {
                        let $t49749;
                        {
                          const $t49729_i8913 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
                          $t49749 = (($t49729_i8913 + x) < 4611686018427387904 && ($t49729_i8913 + x) >= -4611686018427387904 ? ($t49729_i8913 + x) : march_int_ovf(($t49729_i8913 + x), 0));
                        }
                        $t49750 = Array$get$PVec_Int$Int(board, $t49749);
                      }
                      return ($t49750 !== 0);
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
        const $f49761 = c._0;
        const $f49762 = c._1;
        {
          const dy = $f49762;
          {
            const dx = $f49761;
            {
              const x = ((origin_x + dx) < 4611686018427387904 && (origin_x + dx) >= -4611686018427387904 ? (origin_x + dx) : march_int_ovf((origin_x + dx), 0));
              {
                const y = ((origin_y + dy) < 4611686018427387904 && (origin_y + dy) >= -4611686018427387904 ? (origin_y + dy) : march_int_ovf((origin_y + dy), 0));
                {
                  let $t49759;
                  {
                    let $t49745_i8932;
                    {
                      let $t49743_i8930;
                      {
                        const $t49741_i8928 = (x >= 0);
                        if ($t49741_i8928 === true) {
                          $t49743_i8930 = (x < 10);
                        } else {
                          $t49743_i8930 = false;
                        }
                      }
                      {
                        const $t49744_i8931 = (y >= 0);
                        $t49745_i8932 = ($t49743_i8930 && $t49744_i8931);
                      }
                    }
                    if ($t49745_i8932 === true) {
                      $t49759 = (y < 20);
                    } else {
                      $t49759 = false;
                    }
                  }
                  if ($t49759 === true) {
                    {
                      let $t49760;
                      {
                        const $t49729_i8925 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
                        $t49760 = (($t49729_i8925 + x) < 4611686018427387904 && ($t49729_i8925 + x) >= -4611686018427387904 ? ($t49729_i8925 + x) : march_int_ovf(($t49729_i8925 + x), 0));
                      }
                      return Array$set$PVec_Int$Int$Int(b, $t49760, color_idx);
                    }
                  } else if ($t49759 === false) {
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
        let $t49772;
        {
          let $t49771;
          {
            const $t49729_i8937 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
            $t49771 = (($t49729_i8937 + x) < 4611686018427387904 && ($t49729_i8937 + x) >= -4611686018427387904 ? ($t49729_i8937 + x) : march_int_ovf(($t49729_i8937 + x), 0));
          }
          $t49772 = Array$get$PVec_Int$Int(board, $t49771);
        }
        return ($t49772 !== 0);
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
        let $t49777;
        {
          const $t49729_i8941 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
          $t49777 = (($t49729_i8941 + x) < 4611686018427387904 && ($t49729_i8941 + x) >= -4611686018427387904 ? ($t49729_i8941 + x) : march_int_ovf(($t49729_i8941 + x), 0));
        }
        return Array$get$PVec_Int$Int(board, $t49777);
      }
    }
  }
}
const $lam0_TetrisLogic_row_cells$apply$0_TetrisLogic_row_cells$clo = { _0: ($_, $clo, x) => $lam0_TetrisLogic_row_cells$apply$0_TetrisLogic_row_cells($clo, x) };

function $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines($clo, y) {
  {
    const board = $clo._1;
    {
      let $t49781;
      {
        let $t49769_i14598;
        {
          const go_i5857_i14595 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
          {
            const $t2290_i5859_i14597 = { $: "Nil" };
            $t49769_i14598 = go$apply$0_List_range(go_i5857_i14595, 9, $t2290_i5859_i14597);
          }
        }
        {
          const $t49773_i14599 = { $: "$Clo_$lam0_TetrisLogic_row_full$0_TetrisLogic_row_full", _0: $lam0_TetrisLogic_row_full$apply$0_TetrisLogic_row_full, _1: board, _2: y };
          {
            const $rc_2829_i14600 = List$all$List_Int$Fn_Int_Bool($t49769_i14598, $t49773_i14599);
            $t49781 = $rc_2829_i14600;
          }
        }
      }
      return (!$t49781);
    }
  }
}
const $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines$clo = { _0: ($_, $clo, y) => $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines($clo, y) };

function $lam1_TetrisLogic_clear_lines$apply$1_TetrisLogic_clear_lines($clo, y) {
  {
    const board = $clo._1;
    {
      let $t49775_i8945;
      {
        const go_i14767 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
        {
          const $t2290_i14769 = { $: "Nil" };
          $t49775_i8945 = go$apply$0_List_range(go_i14767, 9, $t2290_i14769);
        }
      }
      {
        const $t49778_i8946 = { $: "$Clo_$lam0_TetrisLogic_row_cells$0_TetrisLogic_row_cells", _0: $lam0_TetrisLogic_row_cells$apply$0_TetrisLogic_row_cells, _1: board, _2: y };
        {
          const xs_i14833 = $t49775_i8945;
          {
            const f_i14834 = $t49778_i8946;
            switch (xs_i14833.$) {
              case "Nil": {
                return { $: "Nil" };
                break;
              }
              case "Cons": {
                const $f2369_i14835 = xs_i14833._0;
                const $f2370_i14836 = xs_i14833._1;
                {
                  const t_i14837 = $f2370_i14836;
                  {
                    const h_i14838 = $f2369_i14835;
                    {
                      let $t2367_i14839;
                      $t2367_i14839 = f_i14834._0(f_i14834, h_i14838);
                      {
                        const $trmc38_i14840 = { $: "Cons", _0: $t2367_i14839, _1: null };
                        List$map$dps$List_Int$Fn_Int_Int$List_Int(t_i14837, f_i14834, $trmc38_i14840);
                        return $trmc38_i14840;
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
    let $t49795;
    {
      const $rc_3724 = march_string_to_int(x);
      $t49795 = $rc_3724;
    }
    {
      const $rc_3723 = Option$unwrap_or$Option_Int$Int($t49795, 0);
      return $rc_3723;
    }
  }
}
const $lam0_string_to_int_list$apply$0_string_to_int_list$clo = { _0: ($_, $clo, x) => $lam0_string_to_int_list$apply$0_string_to_int_list($clo, x) };

function $lam0_render_board$apply$0_render_board($clo, y) {
  {
    const board = $clo._1;
    {
      let $t49852;
      {
        const go_i8952 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
        {
          const $t2290_i8954 = { $: "Nil" };
          $t49852 = go$apply$0_List_range(go_i8952, 9, $t2290_i8954);
        }
      }
      {
        let $t49860;
        $t49860 = { $: "$Clo_$lam0__lam0_render_board$1_render_board", _0: $lam0__lam0_render_board$apply$1_render_board, _1: board, _2: y };
        {
          const f_i8948 = $t49860;
          {
            const go_i8949 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i8948 };
            return go$apply$0_List_each_List_Int_Fn_Int_T_(go_i8949, $t49852);
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
          const $t49729_i8959 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
          idx = (($t49729_i8959 + x) < 4611686018427387904 && ($t49729_i8959 + x) >= -4611686018427387904 ? ($t49729_i8959 + x) : march_int_ovf(($t49729_i8959 + x), 0));
        }
        {
          let v;
          v = Array$get$PVec_Int$Int(board, idx);
          {
            let id;
            {
              const $t49854 = String(x);
              {
                const $t49855 = String(y);
                {
                  const $rc_3725 = march_string_concat_n("cell-", $t49854, "-", $t49855);
                  id = $rc_3725;
                }
              }
            }
            {
              const $t49856 = Js$Dom$find(id);
              switch ($t49856.$) {
                case "None": {
                  return {  };
                  break;
                }
                case "Some": {
                  const $f49859 = $t49856._0;
                  {
                    const cell = $f49859;
                    {
                      const $t49857 = (v === 0);
                      if ($t49857 === true) {
                        return Js$Dom$set_style(cell, "background", "");
                      } else if ($t49857 === false) {
                        {
                          let $t49858;
                          if (v === 1) {
                            $t49858 = "#00CED1";
                          } else if (v === 2) {
                            $t49858 = "#FFD700";
                          } else if (v === 3) {
                            $t49858 = "#9B59B6";
                          } else if (v === 4) {
                            $t49858 = "#2ECC71";
                          } else if (v === 5) {
                            $t49858 = "#E74C3C";
                          } else if (v === 6) {
                            $t49858 = "#3498DB";
                          } else if (v === 7) {
                            $t49858 = "#F39C12";
                          } else {
                            $t49858 = "";
                          }
                          return Js$Dom$set_style(cell, "background", $t49858);
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
        const $f49875 = c._0;
        const $f49876 = c._1;
        {
          const dy = $f49876;
          {
            const dx = $f49875;
            {
              const x = ((ox + dx) < 4611686018427387904 && (ox + dx) >= -4611686018427387904 ? (ox + dx) : march_int_ovf((ox + dx), 0));
              {
                const y = ((oy + dy) < 4611686018427387904 && (oy + dy) >= -4611686018427387904 ? (oy + dy) : march_int_ovf((oy + dy), 0));
                {
                  let $t49869;
                  {
                    let $t49867;
                    {
                      let $t49865;
                      {
                        const $t49863 = (x >= 0);
                        if ($t49863 === true) {
                          $t49865 = (x < 10);
                        } else {
                          $t49865 = false;
                        }
                      }
                      {
                        const $t49866 = (y >= 0);
                        $t49867 = ($t49865 && $t49866);
                      }
                    }
                    if ($t49867 === true) {
                      $t49869 = (y < 20);
                    } else {
                      $t49869 = false;
                    }
                  }
                  if ($t49869 === false) {
                    return {  };
                  } else if ($t49869 === true) {
                    {
                      let id;
                      {
                        const $t49870 = String(x);
                        {
                          const $t49871 = String(y);
                          {
                            const $rc_3726 = march_string_concat_n("cell-", $t49870, "-", $t49871);
                            id = $rc_3726;
                          }
                        }
                      }
                      {
                        const $t49872 = Js$Dom$find(id);
                        switch ($t49872.$) {
                          case "None": {
                            return {  };
                            break;
                          }
                          case "Some": {
                            const $f49874 = $t49872._0;
                            {
                              const cell = $f49874;
                              {
                                let $t49873;
                                switch (piece.$) {
                                  case "I": {
                                    $t49873 = "#00CED1";
                                    break;
                                  }
                                  case "O": {
                                    $t49873 = "#FFD700";
                                    break;
                                  }
                                  case "T": {
                                    $t49873 = "#9B59B6";
                                    break;
                                  }
                                  case "S": {
                                    $t49873 = "#2ECC71";
                                    break;
                                  }
                                  case "Z": {
                                    $t49873 = "#E74C3C";
                                    break;
                                  }
                                  case "J": {
                                    $t49873 = "#3498DB";
                                    break;
                                  }
                                  case "L": {
                                    $t49873 = "#F39C12";
                                    break;
                                  }
                                  default: {
                                    throw march_panic_error("panic: ", "non-exhaustive pattern match");
                                    break;
                                  }
                                }
                                return Js$Dom$set_style(cell, "background", $t49873);
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
    const $t50004 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t50004, rot);
      {
        let $t50006;
        {
          const $t50005 = ((y + 1) < 4611686018427387904 && (y + 1) >= -4611686018427387904 ? (y + 1) : march_int_ovf((y + 1), 0));
          {
            const $t49757_i8964 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: x, _3: $t50005 };
            $t50006 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t49757_i8964);
          }
        }
        if ($t50006 === true) {
          {
            const $rc_3727 = lock_and_advance(board, piece, rot, x, y, next, score, lines, rng);
            return $rc_3727;
          }
        } else if ($t50006 === false) {
          {
            const $t50007 = ((y + 1) < 4611686018427387904 && (y + 1) >= -4611686018427387904 ? (y + 1) : march_int_ovf((y + 1), 0));
            return { _0: board, _1: piece, _2: rot, _3: x, _4: $t50007, _5: next, _6: score, _7: lines, _8: rng, _9: false };
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
      const $t50002_i14602 = is_paused();
      if ($t50002_i14602 === true) {
        $eff = {  };
      } else if ($t50002_i14602 === false) {
        {
          const $t50008_i14603 = { $: "$Clo_$lam0_tick$0_tick", _0: $lam0_tick$apply$0_tick };
          $eff = with_state($t50008_i14603);
        }
      } else {
        throw march_panic_error("panic: ", "non-exhaustive pattern match");
      }
    }
  }
  {
    let level_i8967;
    {
      let $t50010_i8966;
      {
        const $t50009_i8965 = state_el();
        $t50010_i8966 = get_int_attr($t50009_i8965, "data-lines", 0);
      }
      level_i8967 = TetrisLogic$level_for_lines($t50010_i8966);
    }
    {
      let $t50011_i8968;
      {
        let $t49727_i14772;
        {
          const $t49726_i14771 = ((level_i8967 * 40) < 4611686018427387904 && (level_i8967 * 40) >= -4611686018427387904 ? (level_i8967 * 40) : march_int_ovf((level_i8967 * 40), 2));
          $t49727_i14772 = ((500 - $t49726_i14771) < 4611686018427387904 && (500 - $t49726_i14771) >= -4611686018427387904 ? (500 - $t49726_i14771) : march_int_ovf((500 - $t49726_i14771), 1));
        }
        {
          const $t3911_i5850_i14773 = ($t49727_i14772 > 100);
          if ($t3911_i5850_i14773 === true) {
            $t50011_i8968 = $t49727_i14772;
          } else {
            $t50011_i8968 = 100;
          }
        }
      }
      {
        const $t50013_i8969 = { $: "$Clo_$lam0_schedule_tick$0_schedule_tick", _0: $lam0_schedule_tick$apply$0_schedule_tick };
        return Js$Dom$set_timeout($t50011_i8968, $t50013_i8969);
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
        const $t50015 = TetrisLogic$piece_cells(piece);
        {
          const cells = rotate_n($t50015, rot);
          {
            let $t50018;
            {
              const $t50016 = ((x + dx) < 4611686018427387904 && (x + dx) >= -4611686018427387904 ? (x + dx) : march_int_ovf((x + dx), 0));
              {
                const $t50017 = ((y + dy) < 4611686018427387904 && (y + dy) >= -4611686018427387904 ? (y + dy) : march_int_ovf((y + dy), 0));
                {
                  const $t49757_i8974 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: $t50016, _3: $t50017 };
                  $t50018 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t49757_i8974);
                }
              }
            }
            if ($t50018 === true) {
              return { _0: board, _1: piece, _2: rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: rng, _9: false };
            } else if ($t50018 === false) {
              {
                const $t50019 = ((x + dx) < 4611686018427387904 && (x + dx) >= -4611686018427387904 ? (x + dx) : march_int_ovf((x + dx), 0));
                {
                  const $t50020 = ((y + dy) < 4611686018427387904 && (y + dy) >= -4611686018427387904 ? (y + dy) : march_int_ovf((y + dy), 0));
                  return { _0: board, _1: piece, _2: rot, _3: $t50019, _4: $t50020, _5: next, _6: score, _7: lines, _8: rng, _9: false };
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
      const $t50023 = ((rot + 1) < 4611686018427387904 && (rot + 1) >= -4611686018427387904 ? (rot + 1) : march_int_ovf((rot + 1), 0));
      new_rot = (4 === 0 ? march_mod_zero() : $t50023 % 4);
    }
    {
      const $t50024 = TetrisLogic$piece_cells(piece);
      {
        const cells = rotate_n($t50024, new_rot);
        {
          let $t50025;
          {
            const $t49757_i8979 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: x, _3: y };
            $t50025 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t49757_i8979);
          }
          if ($t50025 === true) {
            return { _0: board, _1: piece, _2: rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: rng, _9: false };
          } else if ($t50025 === false) {
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
    const $t50031 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t50031, rot);
      {
        let final_y;
        final_y = fall_from(board, cells, x, y);
        {
          const $rc_3728 = lock_and_advance(board, piece, rot, x, final_y, next, score, lines, rng);
          return $rc_3728;
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
          let $t50106;
          {
            const go_i8985 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
            {
              const $t2290_i8987 = { $: "Nil" };
              $t50106 = go$apply$0_List_range(go_i8985, 9, $t2290_i8987);
            }
          }
          {
            let $t50111;
            $t50111 = { $: "$Clo_$lam0__lam0_build_board_dom$1_build_board_dom", _0: $lam0__lam0_build_board_dom$apply$1_build_board_dom, _1: row, _2: y };
            {
              const f_i8981 = $t50111;
              {
                const go_i8982 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i8981 };
                $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i8982, $t50106);
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
            let $t50110;
            {
              const $t50108 = String(x);
              {
                const $t50109 = String(y);
                {
                  const $rc_3729 = march_string_concat_n("cell-", $t50108, "-", $t50109);
                  $t50110 = $rc_3729;
                }
              }
            }
            $eff = Js$Dom$set_attr(cell, "id", $t50110);
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
          const $t2282 = (i <= 0);
          if ($t2282 === true) {
            return acc;
          } else {
            {
              const $t2283 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
              {
                const $t2284 = { $: "Cons", _0: x, _1: acc };
                {
                  $tco_a0 = go;
                  $tco_a1 = $t2283;
                  $tco_a2 = $t2284;
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
        const $t11245 = { $: "$Clo_$lam0_Array_from_list_up$1_Array_from_list_List_Int", _0: $lam0_Array_from_list_up$apply$1_Array_from_list_List_Int };
        {
          let parents;
          {
            const wrap_i9123 = $t11245;
            {
              const chunk_i9124 = { $: "$Clo_chunk$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int", _0: chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int, _1: wrap_i9123 };
              {
                const $t11171_i9125 = { $: "Nil" };
                {
                  const $t11172_i9126 = { $: "Nil" };
                  parents = chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int(chunk_i9124, nodes, 0, $t11171_i9125, $t11172_i9126);
                }
              }
            }
          }
          {
            let $t11247;
            {
              let $t11246;
              {
                const go_i9121 = { $: "$Clo_go$0_Array_lst_len_List_TrieNode_Int", _0: go$apply$0_Array_lst_len_List_TrieNode_Int };
                $t11246 = go$apply$0_Array_lst_len_List_TrieNode_Int(go_i9121, parents, 0);
              }
              $t11247 = ($t11246 === 1);
            }
            if ($t11247 === true) {
              switch (parents.$) {
                case "Cons": {
                  const $f11251 = parents._0;
                  const $f11252 = parents._1;
                  {
                    const root = $f11251;
                    {
                      const $t11248 = ((shift + 5) < 4611686018427387904 && (shift + 5) >= -4611686018427387904 ? (shift + 5) : march_int_ovf((shift + 5), 0));
                      return { _0: root, _1: $t11248 };
                    }
                  }
                  break;
                }
                case "Nil": {
                  {
                    const $t11249 = { $: "TrieEmpty" };
                    {
                      const $t11250 = ((shift + 5) < 4611686018427387904 && (shift + 5) >= -4611686018427387904 ? (shift + 5) : march_int_ovf((shift + 5), 0));
                      return { _0: $t11249, _1: $t11250 };
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
                const $t11257 = ((shift + 5) < 4611686018427387904 && (shift + 5) >= -4611686018427387904 ? (shift + 5) : march_int_ovf((shift + 5), 0));
                {
                  $tco_a0 = $clo;
                  $tco_a1 = parents;
                  $tco_a2 = $t11257;
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
            const $f2376 = lst._0;
            const $f2377 = lst._1;
            {
              const t = $f2377;
              {
                const h = $f2376;
                {
                  let $p2375;
                  $p2375 = f._0(f, h);
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
            const $f2376 = lst._0;
            const $f2377 = lst._1;
            {
              const t = $f2377;
              {
                const h = $f2376;
                {
                  let $p2375;
                  $p2375 = f._0(f, h);
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
          const $f10752 = xs._0;
          const $f10753 = xs._1;
          {
            const t = $f10753;
            {
              const $t10751 = ((acc + 1) < 4611686018427387904 && (acc + 1) >= -4611686018427387904 ? (acc + 1) : march_int_ovf((acc + 1), 0));
              {
                $tco_a0 = $clo;
                $tco_a1 = t;
                $tco_a2 = $t10751;
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
                  const go_i9206 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                  {
                    const $t10718_i9207 = { $: "Nil" };
                    return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9206, out, $t10718_i9207);
                  }
                }
                break;
              }
              default: {
                {
                  let $t11153;
                  {
                    let $t11152;
                    {
                      const go_i9203 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                      {
                        const $t10718_i9204 = { $: "Nil" };
                        $t11152 = go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9203, cur, $t10718_i9204);
                      }
                    }
                    $t11153 = wrap._0(wrap, $t11152);
                  }
                  {
                    const $t11154 = { $: "Cons", _0: $t11153, _1: out };
                    {
                      const go_i9200 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                      {
                        const $t10718_i9201 = { $: "Nil" };
                        return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9200, $t11154, $t10718_i9201);
                      }
                    }
                  }
                }
              }
            }
            break;
          }
          case "Cons": {
            const $f11165 = ys._0;
            const $f11166 = ys._1;
            {
              const t = $f11166;
              {
                const h = $f11165;
                {
                  const $t11157 = (i === 31);
                  if ($t11157 === true) {
                    {
                      const $t11158 = { $: "Nil" };
                      {
                        let $t11161;
                        {
                          const $t11159 = { $: "Cons", _0: h, _1: cur };
                          {
                            let $t11160;
                            {
                              const go_i9209 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                              {
                                const $t10718_i9210 = { $: "Nil" };
                                $t11160 = go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9209, $t11159, $t10718_i9210);
                              }
                            }
                            $t11161 = wrap._0(wrap, $t11160);
                          }
                        }
                        {
                          const $t11162 = { $: "Cons", _0: $t11161, _1: out };
                          {
                            $tco_a0 = chunk;
                            $tco_a1 = t;
                            $tco_a2 = 0;
                            $tco_a3 = $t11158;
                            $tco_a4 = $t11162;
                            continue __tco;
                          }
                        }
                      }
                    }
                  } else {
                    {
                      const $t11163 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                      {
                        const $t11164 = { $: "Cons", _0: h, _1: cur };
                        {
                          $tco_a0 = chunk;
                          $tco_a1 = t;
                          $tco_a2 = $t11163;
                          $tco_a3 = $t11164;
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
                  const go_i9218 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                  {
                    const $t10718_i9219 = { $: "Nil" };
                    return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9218, out, $t10718_i9219);
                  }
                }
                break;
              }
              default: {
                {
                  let $t11153;
                  {
                    let $t11152;
                    {
                      const go_i9215 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                      {
                        const $t10718_i9216 = { $: "Nil" };
                        $t11152 = go$apply$0_Array_lst_rev_List_Int(go_i9215, cur, $t10718_i9216);
                      }
                    }
                    $t11153 = wrap._0(wrap, $t11152);
                  }
                  {
                    const $t11154 = { $: "Cons", _0: $t11153, _1: out };
                    {
                      const go_i9212 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                      {
                        const $t10718_i9213 = { $: "Nil" };
                        return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9212, $t11154, $t10718_i9213);
                      }
                    }
                  }
                }
              }
            }
            break;
          }
          case "Cons": {
            const $f11165 = ys._0;
            const $f11166 = ys._1;
            {
              const t = $f11166;
              {
                const h = $f11165;
                {
                  const $t11157 = (i === 31);
                  if ($t11157 === true) {
                    {
                      const $t11158 = { $: "Nil" };
                      {
                        let $t11161;
                        {
                          const $t11159 = { $: "Cons", _0: h, _1: cur };
                          {
                            let $t11160;
                            {
                              const go_i9221 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                              {
                                const $t10718_i9222 = { $: "Nil" };
                                $t11160 = go$apply$0_Array_lst_rev_List_Int(go_i9221, $t11159, $t10718_i9222);
                              }
                            }
                            $t11161 = wrap._0(wrap, $t11160);
                          }
                        }
                        {
                          const $t11162 = { $: "Cons", _0: $t11161, _1: out };
                          {
                            $tco_a0 = chunk;
                            $tco_a1 = t;
                            $tco_a2 = 0;
                            $tco_a3 = $t11158;
                            $tco_a4 = $t11162;
                            continue __tco;
                          }
                        }
                      }
                    }
                  } else {
                    {
                      const $t11163 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                      {
                        const $t11164 = { $: "Cons", _0: h, _1: cur };
                        {
                          $tco_a0 = chunk;
                          $tco_a1 = t;
                          $tco_a2 = $t11163;
                          $tco_a3 = $t11164;
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
        const $t11139 = (i === 0);
        if ($t11139 === true) {
          {
            let $t11140;
            {
              const go_i9227 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
              {
                const $t10718_i9228 = { $: "Nil" };
                $t11140 = go$apply$0_Array_lst_rev_List_Int(go_i9227, acc, $t10718_i9228);
              }
            }
            return { _0: $t11140, _1: ys };
          }
        } else {
          switch (ys.$) {
            case "Nil": {
              {
                let $t11141;
                {
                  const go_i9224 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                  {
                    const $t10718_i9225 = { $: "Nil" };
                    $t11141 = go$apply$0_Array_lst_rev_List_Int(go_i9224, acc, $t10718_i9225);
                  }
                }
                {
                  const $t11142 = { $: "Nil" };
                  return { _0: $t11141, _1: $t11142 };
                }
              }
              break;
            }
            case "Cons": {
              const $f11145 = ys._0;
              const $f11146 = ys._1;
              {
                const t = $f11146;
                {
                  const h = $f11145;
                  {
                    const $t11143 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
                    {
                      const $t11144 = { $: "Cons", _0: h, _1: acc };
                      {
                        $tco_a0 = $clo;
                        $tco_a1 = t;
                        $tco_a2 = $t11143;
                        $tco_a3 = $t11144;
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
          const $f10752 = xs._0;
          const $f10753 = xs._1;
          {
            const t = $f10753;
            {
              const $t10751 = ((acc + 1) < 4611686018427387904 && (acc + 1) >= -4611686018427387904 ? (acc + 1) : march_int_ovf((acc + 1), 0));
              {
                $tco_a0 = $clo;
                $tco_a1 = t;
                $tco_a2 = $t10751;
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
          const $f10728 = rev_xs._0;
          const $f10729 = rev_xs._1;
          {
            const rest = $f10729;
            {
              const a = $f10728;
              {
                const $t10727 = { $: "Cons", _0: a, _1: ys };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = rest;
                  $tco_a2 = $t10727;
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
            const $t10734 = (i === 0);
            if ($t10734 === true) {
              switch (xs.$) {
                case "Nil": {
                  {
                    const go_i9233 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                    {
                      const $t10718_i9234 = { $: "Nil" };
                      return go$apply$0_Array_lst_rev_List_Int(go_i9233, acc, $t10718_i9234);
                    }
                  }
                  break;
                }
                case "Cons": {
                  const $f10736 = xs._0;
                  const $f10737 = xs._1;
                  {
                    const t = $f10737;
                    {
                      const $t10735 = { $: "Cons", _0: v, _1: t };
                      return rev_onto._0(rev_onto, acc, $t10735);
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
                    const go_i9230 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                    {
                      const $t10718_i9231 = { $: "Nil" };
                      return go$apply$0_Array_lst_rev_List_Int(go_i9230, acc, $t10718_i9231);
                    }
                  }
                  break;
                }
                case "Cons": {
                  const $f10744 = xs._0;
                  const $f10745 = xs._1;
                  {
                    const t = $f10745;
                    {
                      const h = $f10744;
                      {
                        const $t10742 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
                        {
                          const $t10743 = { $: "Cons", _0: h, _1: acc };
                          {
                            $tco_a0 = go;
                            $tco_a1 = t;
                            $tco_a2 = $t10742;
                            $tco_a3 = $t10743;
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
          const $f10712 = xs._0;
          const $f10713 = xs._1;
          {
            const t = $f10713;
            {
              const h = $f10712;
              {
                const $t10711 = { $: "Cons", _0: h, _1: acc };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = t;
                  $tco_a2 = $t10711;
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
            const $f11110 = xs._0;
            const $f11111 = xs._1;
            {
              const rest = $f11111;
              {
                const x = $f11110;
                {
                  let $t11109;
                  $t11109 = f._0(f, a, x);
                  {
                    $tco_a0 = go;
                    $tco_a1 = $t11109;
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
          const $f10712 = xs._0;
          const $f10713 = xs._1;
          {
            const t = $f10713;
            {
              const h = $f10712;
              {
                const $t10711 = { $: "Cons", _0: h, _1: acc };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = t;
                  $tco_a2 = $t10711;
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
            const $f10909 = vs._0;
            const $f10910 = vs._1;
            {
              const rest = $f10910;
              {
                const v = $f10909;
                {
                  let $t10908;
                  $t10908 = f._0(f, a, v);
                  {
                    $tco_a0 = go;
                    $tco_a1 = $t10908;
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
            const $f10916 = cs._0;
            const $f10917 = cs._1;
            {
              const rest = $f10917;
              {
                const child = $f10916;
                {
                  let $t10915;
                  $t10915 = Array$trie_fold$List_Int$TrieNode_Int$Fn_List_Int_Int_List_Int(a, child, f);
                  {
                    $tco_a0 = go;
                    $tco_a1 = $t10915;
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
          const $f10794 = rev_xs._0;
          const $f10795 = rev_xs._1;
          {
            const rest = $f10795;
            {
              const a = $f10794;
              {
                const $t10793 = { $: "Cons", _0: a, _1: ys };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = rest;
                  $tco_a2 = $t10793;
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
                const go_i9646 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                {
                  const $t10718_i9647 = { $: "Nil" };
                  return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9646, acc, $t10718_i9647);
                }
              }
              break;
            }
            case "Cons": {
              const $f10804 = xs._0;
              const $f10805 = xs._1;
              {
                const t = $f10805;
                {
                  const h = $f10804;
                  {
                    const $t10800 = (i === 0);
                    if ($t10800 === true) {
                      {
                        let $t10801;
                        $t10801 = { $: "Cons", _0: node, _1: t };
                        return rev_onto._0(rev_onto, acc, $t10801);
                      }
                    } else {
                      {
                        const $t10802 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
                        {
                          const $t10803 = { $: "Cons", _0: h, _1: acc };
                          {
                            $tco_a0 = go;
                            $tco_a1 = t;
                            $tco_a2 = $t10802;
                            $tco_a3 = $t10803;
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
