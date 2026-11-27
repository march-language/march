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
      const $f3 = e._0;
      const $f4 = e._1;
      const $f5 = e._2;
      const $f6 = e._3;
      {
        const scope = $f6;
        {
          const limit = $f5;
          {
            const target = $f4;
            {
              const kind = $f3;
              {
                let o_pre;
                {
                  const $t1 = (target === "");
                  if ($t1 === true) {
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
                        const $f1_i9666 = limit._0;
                        {
                          const f_i9667 = $f1_i9666;
                          $rc_65 = march_string_concat3("function ", f_i9667, "'s needs");
                        }
                        break;
                      }
                      case "ByModNeeds": {
                        const $f2_i9668 = limit._0;
                        {
                          const m_i9669 = $f2_i9668;
                          $rc_65 = march_string_concat3("module ", m_i9669, "'s needs");
                        }
                        break;
                      }
                      case "ByRestrict": {
                        const $f3_i9670 = limit._0;
                        {
                          const w_i9671 = $f3_i9670;
                          $rc_65 = ("the restrict at " + w_i9671);
                        }
                        break;
                      }
                      case "ByGrant": {
                        const $f4_i9672 = limit._0;
                        {
                          const p_i9673 = $f4_i9672;
                          $rc_65 = ("the grant to package " + p_i9673);
                        }
                        break;
                      }
                      case "ByMock": {
                        const $f5_i9674 = limit._0;
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
                      const $t2 = (scope === "");
                      if ($t2 === true) {
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
      const $t1 = (r === 0);
      if ($t1 === true) {
        {
          const $t2 = {  };
          return { $: "Ok", _0: $t2 };
        }
      } else {
        {
          const $t1_i9678 = march_cap_layers();
          {
            const kind_i14791 = kind;
            {
              let cwd_i14799;
              {
                let $t3_i14798;
                {
                  let $t1_i14796;
                  {
                    let $t2_i59_i14795;
                    {
                      const $t1_i58_i14794 = (kind === "IO.FileRead");
                      if ($t1_i58_i14794 === true) {
                        $t2_i59_i14795 = true;
                      } else {
                        $t2_i59_i14795 = (kind === "IO.FileWrite");
                      }
                    }
                    if ($t2_i59_i14795 === true) {
                      $t1_i14796 = true;
                    } else {
                      $t1_i14796 = (kind === "IO.FileSystem");
                    }
                  }
                  if ($t1_i14796 === true) {
                    {
                      const $t2_i14797 = march_string_starts_with(target, "/");
                      $t3_i14798 = (!$t2_i14797);
                    }
                  } else {
                    $t3_i14798 = false;
                  }
                }
                if ($t3_i14798 === true) {
                  cwd_i14799 = march_cap_cwd();
                } else {
                  cwd_i14799 = "/";
                }
              }
              {
                let $t4_i14800;
                {
                  let p_i14859;
                  if (kind === "IO.Console") {
                    p_i14859 = "IO";
                  } else if (kind === "IO.FileSystem") {
                    p_i14859 = "IO";
                  } else if (kind === "IO.FileRead") {
                    p_i14859 = "IO.FileSystem";
                  } else if (kind === "IO.FileWrite") {
                    p_i14859 = "IO.FileSystem";
                  } else if (kind === "IO.Network") {
                    p_i14859 = "IO";
                  } else if (kind === "IO.NetConnect") {
                    p_i14859 = "IO.Network";
                  } else if (kind === "IO.NetListen") {
                    p_i14859 = "IO.Network";
                  } else if (kind === "IO.Process") {
                    p_i14859 = "IO";
                  } else if (kind === "IO.Clock") {
                    p_i14859 = "IO";
                  } else if (kind === "IO.Random") {
                    p_i14859 = "IO";
                  } else if (kind === "IO.Signal") {
                    p_i14859 = "IO";
                  } else if (kind === "IO.Database") {
                    p_i14859 = "IO.NetConnect";
                  } else if (kind === "IO.Spawn") {
                    p_i14859 = "IO";
                  } else if (kind === "IO.Mut") {
                    p_i14859 = "IO";
                  } else if (kind === "IO.Telemetry") {
                    p_i14859 = "IO";
                  } else if (kind === "IO.NetConnect.TLS") {
                    p_i14859 = "IO.NetConnect";
                  } else if (kind === "IO.WebSocket") {
                    p_i14859 = "IO.NetConnect";
                  } else if (kind === "IO.Foreign") {
                    p_i14859 = "IO";
                  } else if (kind === "IO.Foreign.Blocking") {
                    p_i14859 = "IO.Foreign";
                  } else if (kind === "IO.Registry") {
                    p_i14859 = "IO";
                  } else if (kind === "IO.Cluster") {
                    p_i14859 = "IO";
                  } else {
                    p_i14859 = "";
                  }
                  {
                    const $t1_i14860 = (p_i14859 === "");
                    if ($t1_i14860 === true) {
                      {
                        const $t2_i14861 = { $: "Nil" };
                        $t4_i14800 = { $: "Cons", _0: kind, _1: $t2_i14861 };
                      }
                    } else {
                      {
                        const $trmc3_i14862 = { $: "Cons", _0: kind, _1: null };
                        Authority$kind_chain$dps(p_i14859, $trmc3_i14862);
                        $t4_i14800 = $trmc3_i14862;
                      }
                    }
                  }
                }
                {
                  const $rc_67_i14801 = Authority$first_refusal(kind, $t4_i14800, target, cwd_i14799, $t1_i9678);
                  return $rc_67_i14801;
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
          const $t1 = {  };
          return { $: "Ok", _0: $t1 };
        }
        break;
      }
      case "Cons": {
        const $f6 = layers._0;
        const $f7 = layers._1;
        switch ($f6.$) {
          case "Layer": {
            const $f8 = $f6._0;
            const $f9 = $f6._1;
            const $f10 = $f6._2;
            {
              const $jp37_rest = $f7;
              {
                const $jp39_scopes = $f10;
                switch ($f8.$) {
                  case "ByMock": {
                    const $f17 = $f8._0;
                    {
                      let $t2;
                      $t2 = Authority$mock_covers($jp39_scopes, kind, target, cwd);
                      if ($t2 === true) {
                        {
                          const $t3 = {  };
                          return { $: "Ok", _0: $t3 };
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
                      const text = $f9;
                      {
                        const limit = $f8;
                        {
                          let $t4;
                          $t4 = Authority$admits_in($jp39_scopes, chain, kind, target, cwd);
                          if ($t4 === true) {
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
                              const $t5 = { $: "CapError", _0: kind, _1: target, _2: limit, _3: text };
                              return { $: "Err", _0: $t5 };
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
      let $t2;
      {
        const $t1 = (!scoped);
        if ($t1 === true) {
          $t2 = (grant === "");
        } else {
          $t2 = false;
        }
      }
      if ($t2 === true) {
        return {  };
      } else {
        {
          const $t3 = Authority$parse(request);
          switch ($t3.$) {
            case "Err": {
              const $f22 = $t3._0;
              {
                const e = $f22;
                march_panic_site("stdlib/authority.march", 192, 16, 76);
                {
                  let $t4;
                  {
                    const $rc_68 = ("internal: main's request is not a scope list: " + e);
                    $t4 = $rc_68;
                  }
                  return (() => { throw march_panic_error("panic: ", $t4); })();
                }
              }
              break;
            }
            case "Ok": {
              const $f23 = $t3._0;
              {
                const req = $f23;
                {
                  const $t5 = (grant === "");
                  if ($t5 === true) {
                    {
                      let $t7;
                      {
                        const $t6 = { $: "ByLaunch" };
                        $t7 = { $: "Layer", _0: $t6, _1: request, _2: req };
                      }
                      {
                        const $t8 = { $: "Nil" };
                        {
                          const $t9 = { $: "Cons", _0: $t7, _1: $t8 };
                          return march_cap_set_launch($t9);
                        }
                      }
                    }
                  } else {
                    {
                      const $t10 = Authority$parse(grant);
                      switch ($t10.$) {
                        case "Err": {
                          const $f20 = $t10._0;
                          {
                            const e = $f20;
                            {
                              let $t11;
                              {
                                const $rc_70 = ("march: MARCH_GRANT is not a scope list: " + e);
                                $t11 = $rc_70;
                              }
                              {
                                const $rc_69 = Authority$launch_error($t11);
                                return $rc_69;
                              }
                            }
                          }
                          break;
                        }
                        case "Ok": {
                          const $f21 = $t10._0;
                          {
                            const g = $f21;
                            {
                              let $t12;
                              {
                                let $rc_73;
                                $rc_73 = Authority$first_outside(g, req);
                                $t12 = $rc_73;
                              }
                              switch ($t12.$) {
                                case "Some": {
                                  const $f19 = $t12._0;
                                  {
                                    const s = $f19;
                                    {
                                      let $t14;
                                      {
                                        const $t13 = Authority$scope_text(s);
                                        {
                                          const $rc_72 = march_string_concat_n("march: MARCH_GRANT grants ", $t13, ", which main does not request (main requests: ", request, ")");
                                          $t14 = $rc_72;
                                        }
                                      }
                                      {
                                        const $rc_71 = Authority$launch_error($t14);
                                        return $rc_71;
                                      }
                                    }
                                  }
                                  break;
                                }
                                case "None": {
                                  {
                                    let $t16;
                                    {
                                      const $t15 = { $: "ByLaunch" };
                                      $t16 = { $: "Layer", _0: $t15, _1: grant, _2: g };
                                    }
                                    {
                                      const $t17 = { $: "Nil" };
                                      {
                                        const $t18 = { $: "Cons", _0: $t16, _1: $t17 };
                                        return march_cap_set_launch($t18);
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
    const $t1 = (msg + "\n");
    {
      const $rc_74 = march_cap_launch_fail($t1);
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
        const $f2 = a._0;
        const $f3 = a._1;
        {
          const rest = $f3;
          {
            const s = $f2;
            {
              let $t1;
              $t1 = Authority$covered(s, b);
              if ($t1 === true) {
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
        const $f3 = scopes._0;
        const $f4 = scopes._1;
        switch ($f3.$) {
          case "CapEntry": {
            const $f5 = $f3._0;
            const $f6 = $f3._1;
            {
              const rest = $f4;
              {
                const arg = $f6;
                {
                  const k = $f5;
                  {
                    let $t2;
                    {
                      let $t1;
                      {
                        const $rc_79 = Authority$member(chain, k);
                        $t1 = $rc_79;
                      }
                      if ($t1 === true) {
                        $t2 = Authority$arg_admits(arg, kind, target, cwd);
                      } else {
                        $t2 = false;
                      }
                    }
                    if ($t2 === true) {
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
      const $f23 = arg._0;
      {
        const ps = $f23;
        {
          let $t2;
          {
            let $t1;
            {
              let $t2_i62;
              {
                const $t1_i61 = (kind === "IO.FileRead");
                if ($t1_i61 === true) {
                  $t2_i62 = true;
                } else {
                  $t2_i62 = (kind === "IO.FileWrite");
                }
              }
              if ($t2_i62 === true) {
                $t1 = true;
              } else {
                $t1 = (kind === "IO.FileSystem");
              }
            }
            $t2 = (!$t1);
          }
          if ($t2 === true) {
            return false;
          } else {
            {
              let $t5;
              {
                const $t3 = (cwd === "");
                if ($t3 === true) {
                  {
                    const $t4 = march_string_starts_with(target, "/");
                    $t5 = (!$t4);
                  }
                } else {
                  $t5 = false;
                }
              }
              if ($t5 === true) {
                return false;
              } else {
                {
                  const $t6 = Authority$resolve(cwd, target);
                  {
                    let $rc_80;
                    {
                      const $t1_i9696 = march_string_starts_with($t6, "/");
                      {
                        let $t2_i9702;
                        {
                          const $t1_i75_i9698 = march_string_split($t6, "/");
                          {
                            const $t2_i76_i9699 = { $: "Nil" };
                            {
                              const $t3_i77_i9700 = Authority$fold_segments($t1_i75_i9698, $t2_i76_i9699);
                              {
                                const $t4_i78_i9701 = { $: "Nil" };
                                $t2_i9702 = Authority$rev($t3_i77_i9700, $t4_i78_i9701);
                              }
                            }
                          }
                        }
                        {
                          const $rc_88_i9703 = Authority$any_within_segs(ps, $t1_i9696, $t2_i9702);
                          $rc_80 = $rc_88_i9703;
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
      const $f24 = arg._0;
      {
        const spec = $f24;
        {
          const $t7 = (kind === "IO.NetConnect");
          if ($t7 === true) {
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
      const $f25 = arg._0;
      const $f26 = arg._1;
      {
        const pre = $f26;
        {
          const ns = $f25;
          {
            let $t8;
            {
              const $t1_i69 = (kind === "IO.Mut");
              if ($t1_i69 === true) {
                $t8 = true;
              } else {
                $t8 = (kind === "IO.Registry");
              }
            }
            if ($t8 === true) {
              {
                let $rc_82;
                {
                  const $t1_i67 = Authority$member(ns, target);
                  if ($t1_i67 === true) {
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
      const $f29 = arg._0;
      const $f30 = arg._1;
      const $f31 = arg._2;
      const $f32 = arg._3;
      {
        const port = $f32;
        {
          const wild = $f31;
          {
            const h = $f30;
            {
              const $t9 = (kind === "IO.NetConnect");
              if ($t9 === true) {
                {
                  const $t10 = (h === "");
                  if ($t10 === true) {
                    return true;
                  } else {
                    {
                      const $t11 = Authority$split_target(target);
                      const $f12 = $t11._0;
                      const $f13 = $t11._1;
                      {
                        const tp = $f13;
                        {
                          const th = $f12;
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
      const $f39 = arg._0;
      {
        const ps = $f39;
        {
          let $t17;
          {
            let $t16;
            {
              let $t2_i73;
              {
                const $t1_i72 = (kind === "IO.FileRead");
                if ($t1_i72 === true) {
                  $t2_i73 = true;
                } else {
                  $t2_i73 = (kind === "IO.FileWrite");
                }
              }
              if ($t2_i73 === true) {
                $t16 = true;
              } else {
                $t16 = (kind === "IO.FileSystem");
              }
            }
            $t17 = (!$t16);
          }
          if ($t17 === true) {
            return false;
          } else {
            {
              let $t20;
              {
                const $t18 = (cwd === "");
                if ($t18 === true) {
                  {
                    const $t19 = march_string_starts_with(target, "/");
                    $t20 = (!$t19);
                  }
                } else {
                  $t20 = false;
                }
              }
              if ($t20 === true) {
                return false;
              } else {
                {
                  let $t22;
                  {
                    const $t21 = Authority$resolve(cwd, target);
                    {
                      const $rc_86 = Authority$normalize($t21);
                      $t22 = $rc_86;
                    }
                  }
                  {
                    const $rc_85 = Authority$any_normal_within(ps, $t22);
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
        const $f7 = ps._0;
        const $f8 = ps._1;
        {
          const rest = $f8;
          {
            const p = $f7;
            {
              let $t6;
              {
                let $t2;
                {
                  const $t1 = (p === "/");
                  if ($t1 === true) {
                    $t2 = true;
                  } else {
                    $t2 = (n === p);
                  }
                }
                if ($t2 === true) {
                  $t6 = true;
                } else {
                  {
                    const $t3 = march_string_starts_with(n, p);
                    if ($t3 === true) {
                      {
                        let $t5;
                        {
                          const $t4 = march_string_byte_length(p);
                          $t5 = march_string_slice(n, $t4, 1);
                        }
                        {
                          const $rc_87 = ($t5 === "/");
                          $t6 = $rc_87;
                        }
                      }
                    } else {
                      $t6 = false;
                    }
                  }
                }
              }
              if ($t6 === true) {
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
        const $f5 = ps._0;
        const $f6 = ps._1;
        {
          const rest = $f6;
          {
            const s = $f5;
            {
              let $t4;
              {
                let $t2;
                {
                  const $t1 = march_string_starts_with(s, "/");
                  $t2 = ($t1 === abs);
                }
                if ($t2 === true) {
                  {
                    let $t3;
                    {
                      const $t1_i80 = march_string_split(s, "/");
                      {
                        const $t2_i81 = { $: "Nil" };
                        {
                          const $t3_i82 = Authority$fold_segments($t1_i80, $t2_i81);
                          {
                            const $t4_i83 = { $: "Nil" };
                            $t3 = Authority$rev($t3_i82, $t4_i83);
                          }
                        }
                      }
                    }
                    {
                      const $rc_89 = Authority$segs_prefix($t3, segs);
                      $t4 = $rc_89;
                    }
                  }
                } else {
                  $t4 = false;
                }
              }
              if ($t4 === true) {
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
        const $f7 = b._0;
        const $f8 = b._1;
        switch ($f7.$) {
          case "CapEntry": {
            const $f9 = $f7._0;
            const $f10 = $f7._1;
            {
              const rest = $f8;
              {
                const outer = $f10;
                {
                  const k = $f9;
                  switch (s.$) {
                    case "CapEntry": {
                      const $f3 = s._0;
                      const $f4 = s._1;
                      {
                        const inner = $f4;
                        {
                          const ik = $f3;
                          {
                            let $t2;
                            {
                              let $t1;
                              {
                                const $rc_90 = Authority$kind_subsumes(k, ik);
                                $t1 = $rc_90;
                              }
                              if ($t1 === true) {
                                $t2 = Authority$arg_subsumes(outer, inner);
                              } else {
                                $t2 = false;
                              }
                            }
                            if ($t2 === true) {
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
      const $f12 = outer._0;
      {
        const o_paths = $f12;
        {
          const $t1 = Authority$path_list(inner);
          switch ($t1.$) {
            case "Some": {
              const $f2 = $t1._0;
              {
                const i_paths = $f2;
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
      const $f13 = outer._0;
      {
        const o_paths = $f13;
        {
          const $t3 = Authority$path_list(inner);
          switch ($t3.$) {
            case "Some": {
              const $f4 = $t3._0;
              {
                const i_paths = $f4;
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
      const $f14 = outer._0;
      const $f15 = outer._1;
      {
        const o_pre = $f15;
        {
          const o_names = $f14;
          switch (inner.$) {
            case "Names": {
              const $f6 = inner._0;
              const $f7 = inner._1;
              {
                const i_pre = $f7;
                {
                  const i_names = $f6;
                  {
                    let $t5;
                    {
                      const $rc_94 = Authority$all_names_admitted(i_names, o_names, o_pre);
                      $t5 = $rc_94;
                    }
                    if ($t5 === true) {
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
      const $f18 = outer._0;
      {
        const o = $f18;
        {
          const $t8 = Authority$host_spec(inner);
          switch ($t8.$) {
            case "Some": {
              const $f9 = $t8._0;
              {
                const i = $f9;
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
      const $f19 = outer._0;
      const $f20 = outer._1;
      const $f21 = outer._2;
      const $f22 = outer._3;
      {
        const o = $f19;
        {
          const $t10 = Authority$host_spec(inner);
          switch ($t10.$) {
            case "Some": {
              const $f11 = $t10._0;
              {
                const i = $f11;
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
      const $f1 = a._0;
      {
        const ps = $f1;
        return { $: "Some", _0: ps };
      }
      break;
    }
    case "PathsAt": {
      const $f4 = a._0;
      {
        const ps = $f4;
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
      const $f1 = a._0;
      {
        const s = $f1;
        return { $: "Some", _0: s };
      }
      break;
    }
    case "HostAt": {
      const $f4 = a._0;
      const $f5 = a._1;
      const $f6 = a._2;
      const $f7 = a._3;
      {
        const s = $f4;
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
        const $f2 = i_paths._0;
        const $f3 = i_paths._1;
        {
          const rest = $f3;
          {
            const p = $f2;
            {
              const $t1 = Authority$path_in_any(p, o_paths);
              if ($t1 === true) {
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
        const $f2 = o_paths._0;
        const $f3 = o_paths._1;
        {
          const rest = $f3;
          {
            const o = $f2;
            {
              const $t1 = Authority$path_within(o, p);
              if ($t1 === true) {
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
        const $f2 = ns._0;
        const $f3 = ns._1;
        {
          const rest = $f3;
          {
            const n = $f2;
            {
              let $t1;
              {
                const $t1_i87 = Authority$member(o_names, n);
                if ($t1_i87 === true) {
                  $t1 = true;
                } else {
                  $t1 = Authority$starts_with_any(n, o_pre);
                }
              }
              if ($t1 === true) {
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
        const $f2 = i_pre._0;
        const $f3 = i_pre._1;
        {
          const rest = $f3;
          {
            const p = $f2;
            {
              const $t1 = Authority$starts_with_any(p, o_pre);
              if ($t1 === true) {
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
        const $t1 = (p === "");
        if ($t1 === true) {
          {
            const $t2 = { $: "Nil" };
            {
              const $trmc2 = { $: "Cons", _0: kind, _1: $t2 };
              return ($dst._1 = $trmc2, undefined);
            }
          }
        } else {
          {
            const $trmc1 = { $: "Cons", _0: kind, _1: null };
            ($dst._1 = $trmc1, undefined);
            {
              $tco_a0 = p;
              $tco_a1 = $trmc1;
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
      const $t1 = (parent === child);
      if ($t1 === true) {
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
            const $t2 = (p === "");
            if ($t2 === true) {
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
    const $t1 = march_string_starts_with(p, "/");
    if ($t1 === true) {
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
        const $f10 = parts._0;
        const $f11 = parts._1;
        {
          const rest = $f11;
          {
            const s = $f10;
            {
              let $t2;
              {
                const $t1 = (s === "");
                if ($t1 === true) {
                  $t2 = true;
                } else {
                  $t2 = (s === ".");
                }
              }
              if ($t2 === true) {
                {
                  $tco_a0 = rest;
                  $tco_a1 = acc;
                  continue __tco;
                }
              } else {
                {
                  const $t3 = (s === "..");
                  if ($t3 === true) {
                    switch (acc.$) {
                      case "Nil": {
                        {
                          const $t4 = { $: "Nil" };
                          {
                            $tco_a0 = rest;
                            $tco_a1 = $t4;
                            continue __tco;
                          }
                        }
                        break;
                      }
                      case "Cons": {
                        const $f5 = acc._0;
                        const $f6 = acc._1;
                        {
                          const up = $f6;
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
                      const $t9 = { $: "Cons", _0: s, _1: acc };
                      {
                        $tco_a0 = rest;
                        $tco_a1 = $t9;
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
      let $t1;
      {
        const $t1_i92 = march_string_split(p, "/");
        {
          const $t2_i93 = { $: "Nil" };
          {
            const $t3_i94 = Authority$fold_segments($t1_i92, $t2_i93);
            {
              const $t4_i95 = { $: "Nil" };
              $t1 = Authority$rev($t3_i94, $t4_i95);
            }
          }
        }
      }
      {
        const $rc_99 = march_string_join($t1, "/");
        body = $rc_99;
      }
    }
    {
      const $t2 = march_string_starts_with(p, "/");
      if ($t2 === true) {
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
    let $t3;
    {
      const $t1 = march_string_starts_with(scope, "/");
      {
        const $t2 = march_string_starts_with(p, "/");
        $t3 = ($t1 === $t2);
      }
    }
    if ($t3 === true) {
      {
        let $t4;
        {
          const $t1_i102 = march_string_split(scope, "/");
          {
            const $t2_i103 = { $: "Nil" };
            {
              const $t3_i104 = Authority$fold_segments($t1_i102, $t2_i103);
              {
                const $t4_i105 = { $: "Nil" };
                $t4 = Authority$rev($t3_i104, $t4_i105);
              }
            }
          }
        }
        {
          let $t5;
          {
            const $t1_i97 = march_string_split(p, "/");
            {
              const $t2_i98 = { $: "Nil" };
              {
                const $t3_i99 = Authority$fold_segments($t1_i97, $t2_i98);
                {
                  const $t4_i100 = { $: "Nil" };
                  $t5 = Authority$rev($t3_i99, $t4_i100);
                }
              }
            }
          }
          {
            const $rc_100 = Authority$segs_prefix($t4, $t5);
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
        const $f6 = pre._0;
        const $f7 = pre._1;
        {
          const pt = $f7;
          {
            const a = $f6;
            switch (segs.$) {
              case "Nil": {
                return false;
                break;
              }
              case "Cons": {
                const $f2 = segs._0;
                const $f3 = segs._1;
                {
                  const st = $f3;
                  {
                    const b = $f2;
                    {
                      const $t1 = (a === b);
                      if ($t1 === true) {
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
        const $f2 = pre._0;
        const $f3 = pre._1;
        {
          const rest = $f3;
          {
            const p = $f2;
            {
              const $t1 = march_string_starts_with(n, p);
              if ($t1 === true) {
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
      const spec_i9704 = spec;
      {
        const $t1_i9705 = march_string_index_of(spec, ";");
        switch ($t1_i9705.$) {
          case "None": {
            raw = spec;
            break;
          }
          case "Some": {
            const $f2_i9706 = $t1_i9705._0;
            {
              const i_i9707 = $f2_i9706;
              {
                const $rc_102_i9708 = march_string_slice(spec, 0, i_i9707);
                raw = $rc_102_i9708;
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
      const $t1 = (raw === "");
      if ($t1 === true) {
        return true;
      } else {
        {
          const $t2 = Authority$parse_host_pattern(raw);
          switch ($t2.$) {
            case "Err": {
              const $f8 = $t2._0;
              return false;
              break;
            }
            case "Ok": {
              const $f9 = $t2._0;
              const $f10 = $f9._0;
              const $f11 = $f9._1;
              const $f12 = $f9._2;
              const $f13 = $f9._3;
              {
                const port = $f12;
                {
                  const wild = $f11;
                  {
                    const h = $f10;
                    {
                      const $t3 = Authority$split_target(target);
                      const $f4 = $t3._0;
                      const $f5 = $t3._1;
                      {
                        const tp = $f5;
                        {
                          const th = $f4;
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
    const $t1 = march_string_last_index_of(t, ":");
    switch ($t1.$) {
      case "None": {
        return { _0: t, _1: 0 };
        break;
      }
      case "Some": {
        const $f9 = $t1._0;
        {
          const i = $f9;
          {
            const $t2 = march_string_slice(t, 0, i);
            {
              let $t8;
              {
                let $t7;
                {
                  const $t3 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                  {
                    let $t6;
                    {
                      let $t5;
                      {
                        const $t4 = march_string_byte_length(t);
                        $t5 = (($t4 - i) < 4611686018427387904 && ($t4 - i) >= -4611686018427387904 ? ($t4 - i) : march_int_ovf(($t4 - i), 1));
                      }
                      $t6 = (($t5 - 1) < 4611686018427387904 && ($t5 - 1) >= -4611686018427387904 ? ($t5 - 1) : march_int_ovf(($t5 - 1), 1));
                    }
                    {
                      const $rc_104 = march_string_slice(t, $t3, $t6);
                      $t7 = $rc_104;
                    }
                  }
                }
                {
                  const $rc_103 = Authority$port_or_zero($t7);
                  $t8 = $rc_103;
                }
              }
              return { _0: $t2, _1: $t8 };
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
      let $t3;
      {
        const $t1 = (port !== 0);
        {
          const $t2 = (port !== tport);
          $t3 = ($t1 && $t2);
        }
      }
      if ($t3 === true) {
        return false;
      } else {
        if (wild === true) {
          {
            const suffix = ("." + h);
            {
              let $t6;
              {
                const $t4 = march_string_byte_length(th);
                {
                  const $t5 = march_string_byte_length(suffix);
                  $t6 = ($t4 > $t5);
                }
              }
              if ($t6 === true) {
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
      const $t1 = march_string_ends_with(l, ".");
      if ($t1 === true) {
        {
          let $t3;
          {
            const $t2 = march_string_byte_length(l);
            $t3 = (($t2 - 1) < 4611686018427387904 && ($t2 - 1) >= -4611686018427387904 ? ($t2 - 1) : march_int_ovf(($t2 - 1), 1));
          }
          {
            const $rc_107 = march_string_slice(l, 0, $t3);
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
    let $t5;
    {
      let $t3;
      {
        const $t1 = (s === "");
        if ($t1 === true) {
          $t3 = true;
        } else {
          {
            const $t2 = march_string_byte_length(s);
            $t3 = ($t2 > 5);
          }
        }
      }
      if ($t3 === true) {
        $t5 = true;
      } else {
        {
          const $t4 = Authority$all_chars(s, "0123456789", 0);
          $t5 = (!$t4);
        }
      }
    }
    if ($t5 === true) {
      return 0;
    } else {
      {
        const $t6 = march_string_to_int(s);
        switch ($t6.$) {
          case "Some": {
            const $f10 = $t6._0;
            {
              const n = $f10;
              {
                let $t9;
                {
                  const $t7 = (n >= 1);
                  {
                    const $t8 = (n <= 65535);
                    $t9 = ($t7 && $t8);
                  }
                }
                if ($t9 === true) {
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
      let $t2;
      {
        const $t1 = march_string_byte_length(s);
        $t2 = (i >= $t1);
      }
      if ($t2 === true) {
        return true;
      } else {
        {
          let $t4;
          {
            const $t3 = march_string_slice(s, i, 1);
            {
              const $rc_108 = march_string_contains(allowed, $t3);
              $t4 = $rc_108;
            }
          }
          if ($t4 === true) {
            {
              const $t5 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
              {
                $tco_a0 = s;
                $tco_a1 = allowed;
                $tco_a2 = $t5;
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
    const $t1 = (raw === "");
    if ($t1 === true) {
      return { $: "Err", _0: "a host scope cannot be empty" };
    } else {
      {
        const $t2 = march_string_contains(raw, "://");
        if ($t2 === true) {
          return { $: "Err", _0: "a host scope names a host, not a URL: drop the scheme (`https://`)" };
        } else {
          {
            let $p15;
            {
              const $t3 = march_string_index_of(raw, "/");
              switch ($t3.$) {
                case "None": {
                  {
                    let $t5;
                    {
                      const $t4 = { $: "None" };
                      $t5 = { $: "Ok", _0: $t4 };
                    }
                    $p15 = { _0: raw, _1: $t5 };
                  }
                  break;
                }
                case "Some": {
                  const $f11 = $t3._0;
                  {
                    const i = $f11;
                    {
                      const $t6 = march_string_slice(raw, 0, i);
                      {
                        let $t10;
                        {
                          let $t9;
                          {
                            let $t8;
                            {
                              const $t7 = march_string_byte_length(raw);
                              $t8 = (($t7 - i) < 4611686018427387904 && ($t7 - i) >= -4611686018427387904 ? ($t7 - i) : march_int_ovf(($t7 - i), 1));
                            }
                            {
                              const $rc_112 = march_string_slice(raw, i, $t8);
                              $t9 = $rc_112;
                            }
                          }
                          {
                            const $rc_111 = Authority$parse_scope_path($t9);
                            $t10 = $rc_111;
                          }
                        }
                        $p15 = { _0: $t6, _1: $t10 };
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
              const host_raw = $p15._0;
              {
                const path_r = $p15._1;
                switch (path_r.$) {
                  case "Err": {
                    const $f13 = path_r._0;
                    {
                      const e = $f13;
                      {
                        const $rc_110 = { $: "Err", _0: e };
                        return $rc_110;
                      }
                    }
                    break;
                  }
                  case "Ok": {
                    const $f14 = path_r._0;
                    {
                      const path = $f14;
                      {
                        const $t12 = march_string_to_lowercase(host_raw);
                        return Authority$host_part_pattern($t12, path);
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
    const $t1 = (s === "");
    if ($t1 === true) {
      return { $: "Err", _0: "a host scope needs a host before its path" };
    } else {
      {
        const $t2 = march_string_contains(s, "@");
        if ($t2 === true) {
          return { $: "Err", _0: "a host scope cannot carry userinfo (`user@`)" };
        } else {
          {
            const $p27 = Authority$split_host_port(s);
            {
              const host_part = $p27._0;
              {
                const port_text = $p27._1;
                {
                  let port;
                  {
                    const $t3 = (port_text === "");
                    if ($t3 === true) {
                      port = 0;
                    } else {
                      port = Authority$port_or_zero(port_text);
                    }
                  }
                  {
                    let $t6;
                    {
                      const $t4 = (port_text !== "");
                      {
                        const $t5 = (port === 0);
                        $t6 = ($t4 && $t5);
                      }
                    }
                    if ($t6 === true) {
                      {
                        const $t7 = march_string_concat3("`", port_text, "` is not a port (1-65535)");
                        {
                          const $rc_126 = { $: "Err", _0: $t7 };
                          return $rc_126;
                        }
                      }
                    } else {
                      {
                        const $t8 = march_string_starts_with(host_part, "[");
                        if ($t8 === true) {
                          {
                            const n = march_string_byte_length(host_part);
                            {
                              let $t13;
                              {
                                let $t10;
                                {
                                  const $t9 = (n >= 2);
                                  if ($t9 === true) {
                                    $t10 = march_string_ends_with(host_part, "]");
                                  } else {
                                    $t10 = false;
                                  }
                                }
                                if ($t10 === true) {
                                  {
                                    let $t12;
                                    {
                                      const $t11 = ((n - 2) < 4611686018427387904 && (n - 2) >= -4611686018427387904 ? (n - 2) : march_int_ovf((n - 2), 1));
                                      $t12 = march_string_slice(host_part, 1, $t11);
                                    }
                                    {
                                      let $rc_113;
                                      {
                                        const $t1_i107 = ($t12 !== "");
                                        if ($t1_i107 === true) {
                                          $rc_113 = Authority$all_chars($t12, "0123456789abcdef:.", 0);
                                        } else {
                                          $rc_113 = false;
                                        }
                                      }
                                      $t13 = $rc_113;
                                    }
                                  }
                                } else {
                                  $t13 = false;
                                }
                              }
                              if ($t13 === true) {
                                {
                                  let $t14;
                                  $t14 = { _0: host_part, _1: false, _2: port, _3: path };
                                  {
                                    const $rc_125 = { $: "Ok", _0: $t14 };
                                    return $rc_125;
                                  }
                                }
                              } else {
                                {
                                  const $t15 = march_string_concat3("`", host_part, "` is not an IPv6 literal");
                                  {
                                    const $rc_124 = { $: "Err", _0: $t15 };
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
                              let $t17;
                              {
                                const $t16 = march_string_byte_length(host_part);
                                $t17 = ($t16 >= 2);
                              }
                              if ($t17 === true) {
                                wild = march_string_starts_with(host_part, "*.");
                              } else {
                                wild = false;
                              }
                            }
                            {
                              let name;
                              {
                                let $t20;
                                if (wild === true) {
                                  {
                                    let $t19;
                                    {
                                      const $t18 = march_string_byte_length(host_part);
                                      $t19 = (($t18 - 2) < 4611686018427387904 && ($t18 - 2) >= -4611686018427387904 ? ($t18 - 2) : march_int_ovf(($t18 - 2), 1));
                                    }
                                    $t20 = march_string_slice(host_part, 2, $t19);
                                  }
                                } else {
                                  $t20 = host_part;
                                }
                                {
                                  const $rc_114 = Authority$normalize_host($t20);
                                  name = $rc_114;
                                }
                              }
                              {
                                let $t22;
                                {
                                  const $t21 = march_string_contains(name, "*");
                                  if ($t21 === true) {
                                    $t22 = true;
                                  } else {
                                    $t22 = (host_part === "*");
                                  }
                                }
                                if ($t22 === true) {
                                  {
                                    const $rc_123 = { $: "Err", _0: "a wildcard must be the whole leftmost label (`*.example.com`)" };
                                    return $rc_123;
                                  }
                                } else {
                                  {
                                    let $t24;
                                    {
                                      let $t23;
                                      {
                                        const $t1_i9710 = (name !== "");
                                        if ($t1_i9710 === true) {
                                          {
                                            const $t2_i9711 = march_string_split(name, ".");
                                            {
                                              const $rc_131_i9712 = Authority$labels_ok($t2_i9711);
                                              $t23 = $rc_131_i9712;
                                            }
                                          }
                                        } else {
                                          $t23 = false;
                                        }
                                      }
                                      $t24 = (!$t23);
                                    }
                                    if ($t24 === true) {
                                      {
                                        const $t25 = march_string_concat3("`", host_part, "` is not a host name: labels are letters, digits and `-`, separated by single dots");
                                        {
                                          const $rc_122 = { $: "Err", _0: $t25 };
                                          return $rc_122;
                                        }
                                      }
                                    } else {
                                      {
                                        const $t26 = { _0: name, _1: wild, _2: port, _3: path };
                                        {
                                          const $rc_121 = { $: "Ok", _0: $t26 };
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
    const $t1 = march_string_starts_with(s, "[");
    if ($t1 === true) {
      {
        const $t2 = march_string_index_of(s, "]");
        switch ($t2.$) {
          case "None": {
            return { _0: s, _1: "" };
            break;
          }
          case "Some": {
            const $f17 = $t2._0;
            {
              const i = $f17;
              {
                let rest;
                {
                  const $t3 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                  {
                    let $t6;
                    {
                      let $t5;
                      {
                        const $t4 = march_string_byte_length(s);
                        $t5 = (($t4 - i) < 4611686018427387904 && ($t4 - i) >= -4611686018427387904 ? ($t4 - i) : march_int_ovf(($t4 - i), 1));
                      }
                      $t6 = (($t5 - 1) < 4611686018427387904 && ($t5 - 1) >= -4611686018427387904 ? ($t5 - 1) : march_int_ovf(($t5 - 1), 1));
                    }
                    rest = march_string_slice(s, $t3, $t6);
                  }
                }
                {
                  const $t7 = (rest === "");
                  if ($t7 === true) {
                    {
                      let $t9;
                      {
                        const $t8 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                        {
                          const $rc_127 = march_string_slice(s, 0, $t8);
                          $t9 = $rc_127;
                        }
                      }
                      return { _0: $t9, _1: "" };
                    }
                  } else {
                    {
                      const $t10 = march_string_starts_with(rest, ":");
                      if ($t10 === true) {
                        {
                          let $t12;
                          {
                            const $t11 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                            {
                              const $rc_129 = march_string_slice(s, 0, $t11);
                              $t12 = $rc_129;
                            }
                          }
                          {
                            let $t16;
                            {
                              let $t15;
                              {
                                let $t14;
                                {
                                  const $t13 = march_string_byte_length(rest);
                                  $t14 = (($t13 - 1) < 4611686018427387904 && ($t13 - 1) >= -4611686018427387904 ? ($t13 - 1) : march_int_ovf(($t13 - 1), 1));
                                }
                                {
                                  const $rc_128 = march_string_slice(rest, 1, $t14);
                                  $t15 = $rc_128;
                                }
                              }
                              $t16 = Authority$port_text_of($t15);
                            }
                            return { _0: $t12, _1: $t16 };
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
        const $t18 = march_string_last_index_of(s, ":");
        switch ($t18.$) {
          case "None": {
            return { _0: s, _1: "" };
            break;
          }
          case "Some": {
            const $f26 = $t18._0;
            {
              const i = $f26;
              {
                const $t19 = march_string_slice(s, 0, i);
                {
                  let $t25;
                  {
                    let $t24;
                    {
                      const $t20 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                      {
                        let $t23;
                        {
                          let $t22;
                          {
                            const $t21 = march_string_byte_length(s);
                            $t22 = (($t21 - i) < 4611686018427387904 && ($t21 - i) >= -4611686018427387904 ? ($t21 - i) : march_int_ovf(($t21 - i), 1));
                          }
                          $t23 = (($t22 - 1) < 4611686018427387904 && ($t22 - 1) >= -4611686018427387904 ? ($t22 - 1) : march_int_ovf(($t22 - 1), 1));
                        }
                        {
                          const $rc_130 = march_string_slice(s, $t20, $t23);
                          $t24 = $rc_130;
                        }
                      }
                    }
                    $t25 = Authority$port_text_of($t24);
                  }
                  return { _0: $t19, _1: $t25 };
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
    const $t1 = (p === "");
    if ($t1 === true) {
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
        const $f3 = ls._0;
        const $f4 = ls._1;
        {
          const rest = $f4;
          {
            const l = $f3;
            {
              let $t2;
              {
                const $t1 = (l !== "");
                if ($t1 === true) {
                  $t2 = Authority$all_chars(l, "abcdefghijklmnopqrstuvwxyz0123456789-", 0);
                } else {
                  $t2 = false;
                }
              }
              if ($t2 === true) {
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
    const $t1 = march_string_split(p, "/");
    {
      let $t2;
      {
        const l_i9720 = $t1;
        switch (l_i9720.$) {
          case "Cons": {
            const $f1_i9721 = l_i9720._0;
            const $f2_i9722 = l_i9720._1;
            {
              const rest_i9723 = $f2_i9722;
              $t2 = rest_i9723;
            }
            break;
          }
          case "Nil": {
            $t2 = { $: "Nil" };
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
          const l_i9713 = $t2;
          {
            const $t1_i9714 = { $: "Nil" };
            {
              let $t2_i9715;
              $t2_i9715 = Authority$rev($t2, $t1_i9714);
              switch ($t2_i9715.$) {
                case "Cons": {
                  const $f4_i9716 = $t2_i9715._0;
                  const $f5_i9717 = $t2_i9715._1;
                  if ($f4_i9716 === "") {
                    {
                      const r_i9718 = $f5_i9717;
                      {
                        const $t3_i9719 = { $: "Nil" };
                        parts = Authority$rev(r_i9718, $t3_i9719);
                      }
                    }
                  } else {
                    parts = $t2;
                  }
                  break;
                }
                default: {
                  parts = $t2;
                  break;
                }
              }
            }
          }
        }
        {
          let $t3;
          $t3 = Authority$bad_scope_segment(parts);
          switch ($t3.$) {
            case "None": {
              {
                const $t4 = { $: "Some", _0: parts };
                return { $: "Ok", _0: $t4 };
              }
              break;
            }
            case "Some": {
              const $f9 = $t3._0;
              if ($f9 === "") {
                return { $: "Err", _0: "a path scope cannot contain `//`" };
              } else {
                {
                  const seg = $f9;
                  {
                    let $t6;
                    {
                      const $t5 = (seg === ".");
                      if ($t5 === true) {
                        $t6 = true;
                      } else {
                        $t6 = (seg === "..");
                      }
                    }
                    if ($t6 === true) {
                      {
                        let $t7;
                        {
                          const $rc_132 = march_string_concat3("a path scope cannot contain a `", seg, "` segment");
                          $t7 = $rc_132;
                        }
                        return { $: "Err", _0: $t7 };
                      }
                    } else {
                      {
                        let $t8;
                        {
                          const $rc_133 = march_string_concat3("the path segment `", seg, "` may contain only letters, digits, `-`, `_`, `.` and `~` (no `%`, `?`, `#` or `\\`)");
                          $t8 = $rc_133;
                        }
                        return { $: "Err", _0: $t8 };
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
        const $f6 = segs._0;
        const $f7 = segs._1;
        {
          const rest = $f7;
          {
            const s = $f6;
            {
              let $t5;
              {
                let $t3;
                {
                  let $t2;
                  {
                    const $t1 = (s === "");
                    if ($t1 === true) {
                      $t2 = true;
                    } else {
                      $t2 = (s === ".");
                    }
                  }
                  if ($t2 === true) {
                    $t3 = true;
                  } else {
                    $t3 = (s === "..");
                  }
                }
                if ($t3 === true) {
                  $t5 = true;
                } else {
                  {
                    const $t4 = Authority$all_chars(s, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~", 0);
                    $t5 = (!$t4);
                  }
                }
              }
              if ($t5 === true) {
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
          const $t1 = { _0: nr, _1: mg, _2: ms };
          return { $: "Ok", _0: $t1 };
        }
        break;
      }
      case "Cons": {
        const $f13 = opts._0;
        const $f14 = opts._1;
        {
          const rest = $f14;
          {
            const o = $f13;
            {
              const $t2 = (o === "no_redirects");
              if ($t2 === true) {
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
                  const $t3 = march_string_starts_with(o, "methods=");
                  if ($t3 === true) {
                    if (mg === true) {
                      return { $: "Err", _0: "`methods(...)` is given twice" };
                    } else {
                      {
                        let v;
                        {
                          let $t5;
                          {
                            const $t4 = march_string_byte_length(o);
                            $t5 = (($t4 - 8) < 4611686018427387904 && ($t4 - 8) >= -4611686018427387904 ? ($t4 - 8) : march_int_ovf(($t4 - 8), 1));
                          }
                          v = march_string_slice(o, 8, $t5);
                        }
                        {
                          let $t7;
                          {
                            const $t6 = march_string_split(v, ",");
                            $t7 = Authority$bad_method($t6);
                          }
                          switch ($t7.$) {
                            case "None": {
                              {
                                const $t8 = (v === "");
                                if ($t8 === true) {
                                  return { $: "Err", _0: "`methods(...)` needs at least one method" };
                                } else {
                                  {
                                    let $t9;
                                    {
                                      const $rc_134 = march_string_split(v, ",");
                                      $t9 = $rc_134;
                                    }
                                    {
                                      $tco_a0 = rest;
                                      $tco_a1 = nr;
                                      $tco_a2 = true;
                                      $tco_a3 = $t9;
                                      continue __tco;
                                    }
                                  }
                                }
                              }
                              break;
                            }
                            case "Some": {
                              const $f11 = $t7._0;
                              {
                                const m = $f11;
                                {
                                  let $t10;
                                  {
                                    const $rc_135 = march_string_concat3("`", m, "` is not an HTTP method a scope can name; use `get`, `head`, `post`, `put`, `patch`, `delete`, `options`");
                                    $t10 = $rc_135;
                                  }
                                  return { $: "Err", _0: $t10 };
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
                      const $t12 = march_string_concat3("unknown option `", o, "`: the options are `no_redirects` and `methods(...)`");
                      return { $: "Err", _0: $t12 };
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
        const $f10 = ms._0;
        const $f11 = ms._1;
        {
          const rest = $f11;
          {
            const m = $f10;
            {
              let $t9;
              {
                const $t1 = { $: "Nil" };
                {
                  const $t2 = { $: "Cons", _0: "options", _1: $t1 };
                  {
                    const $t3 = { $: "Cons", _0: "delete", _1: $t2 };
                    {
                      const $t4 = { $: "Cons", _0: "patch", _1: $t3 };
                      {
                        const $t5 = { $: "Cons", _0: "put", _1: $t4 };
                        {
                          const $t6 = { $: "Cons", _0: "post", _1: $t5 };
                          {
                            const $t7 = { $: "Cons", _0: "head", _1: $t6 };
                            {
                              const $t8 = { $: "Cons", _0: "get", _1: $t7 };
                              {
                                const $rc_136 = Authority$member($t8, m);
                                $t9 = $rc_136;
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
              if ($t9 === true) {
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
    const $t1 = march_string_split(spec, ";");
    switch ($t1.$) {
      case "Nil": {
        return { $: "Err", _0: "a host scope cannot be empty" };
        break;
      }
      case "Cons": {
        const $f24 = $t1._0;
        const $f25 = $t1._1;
        {
          const opts = $f25;
          {
            const p = $f24;
            {
              let $t3;
              {
                const $t2 = (p === "");
                if ($t2 === true) {
                  switch (opts.$) {
                    case "Nil": {
                      $t3 = true;
                      break;
                    }
                    default: {
                      $t3 = false;
                      break;
                    }
                  }
                } else {
                  $t3 = false;
                }
              }
              if ($t3 === true) {
                return { $: "Err", _0: "a host scope cannot be empty" };
              } else {
                {
                  let pat_ok;
                  {
                    const $t4 = (p === "");
                    if ($t4 === true) {
                      {
                        const $t5 = {  };
                        pat_ok = { $: "Ok", _0: $t5 };
                      }
                    } else {
                      {
                        let $t6;
                        $t6 = Authority$parse_host_pattern(p);
                        switch ($t6.$) {
                          case "Ok": {
                            const $f8 = $t6._0;
                            {
                              const $t7 = {  };
                              pat_ok = { $: "Ok", _0: $t7 };
                            }
                            break;
                          }
                          case "Err": {
                            const $f9 = $t6._0;
                            {
                              const e = $f9;
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
                      const $f22 = pat_ok._0;
                      {
                        const e = $f22;
                        return { $: "Err", _0: e };
                      }
                      break;
                    }
                    case "Ok": {
                      const $f23 = pat_ok._0;
                      {
                        let $t11;
                        {
                          const $t10 = { $: "Nil" };
                          {
                            const $rc_137 = Authority$host_options(opts, false, false, $t10);
                            $t11 = $rc_137;
                          }
                        }
                        switch ($t11.$) {
                          case "Err": {
                            const $f13 = $t11._0;
                            {
                              const e = $f13;
                              return { $: "Err", _0: e };
                            }
                            break;
                          }
                          case "Ok": {
                            const $f14 = $t11._0;
                            const $f15 = $f14._0;
                            const $f16 = $f14._1;
                            const $f17 = $f14._2;
                            {
                              const ms = $f17;
                              {
                                const mg = $f16;
                                {
                                  const nr = $f15;
                                  {
                                    const $t12 = { _0: p, _1: nr, _2: mg, _3: ms };
                                    return { $: "Ok", _0: $t12 };
                                  }
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
    const $t1 = Authority$host_decl(o);
    {
      const $t2 = Authority$host_decl(i);
      {
        const $t3 = { _0: $t1, _1: $t2 };
        const $f10 = $t3._0;
        const $f11 = $t3._1;
        switch ($f10.$) {
          case "Ok": {
            const $f12 = $f10._0;
            const $f13 = $f12._0;
            const $f14 = $f12._1;
            const $f15 = $f12._2;
            const $f16 = $f12._3;
            switch ($f11.$) {
              case "Ok": {
                const $f17 = $f11._0;
                const $f18 = $f17._0;
                const $f19 = $f17._1;
                const $f20 = $f17._2;
                const $f21 = $f17._3;
                {
                  const ims = $f21;
                  {
                    const img = $f20;
                    {
                      const inr = $f19;
                      {
                        const i_pre = $f18;
                        {
                          const oms = $f16;
                          {
                            const omg = $f15;
                            {
                              const onr = $f14;
                              {
                                const o_pre = $f13;
                                {
                                  let $t7;
                                  {
                                    let $t5;
                                    {
                                      const $t4 = (!onr);
                                      $t5 = ($t4 || inr);
                                    }
                                    if ($t5 === true) {
                                      {
                                        const $t6 = (!omg);
                                        if ($t6 === true) {
                                          $t7 = true;
                                        } else {
                                          if (img === true) {
                                            {
                                              const $rc_138 = Authority$all_member(ims, oms);
                                              $t7 = $rc_138;
                                            }
                                          } else {
                                            $t7 = false;
                                          }
                                        }
                                      }
                                    } else {
                                      $t7 = false;
                                    }
                                  }
                                  if ($t7 === true) {
                                    {
                                      const $t8 = (o_pre === "");
                                      if ($t8 === true) {
                                        return true;
                                      } else {
                                        {
                                          const $t9 = (i_pre !== "");
                                          if ($t9 === true) {
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
    const $t1 = Authority$parse_host_pattern(o);
    {
      const $t2 = Authority$parse_host_pattern(i);
      {
        const $t3 = { _0: $t1, _1: $t2 };
        const $f12 = $t3._0;
        const $f13 = $t3._1;
        switch ($f12.$) {
          case "Ok": {
            const $f14 = $f12._0;
            const $f15 = $f14._0;
            const $f16 = $f14._1;
            const $f17 = $f14._2;
            const $f18 = $f14._3;
            switch ($f13.$) {
              case "Ok": {
                const $f19 = $f13._0;
                const $f20 = $f19._0;
                const $f21 = $f19._1;
                const $f22 = $f19._2;
                const $f23 = $f19._3;
                {
                  const ipath = $f23;
                  {
                    const iport = $f22;
                    {
                      const iw = $f21;
                      {
                        const ih = $f20;
                        {
                          const opath = $f18;
                          {
                            const oport = $f17;
                            {
                              const ow = $f16;
                              {
                                const oh = $f15;
                                {
                                  let host_ok;
                                  if (ow === true) {
                                    {
                                      let $t4;
                                      if (iw === true) {
                                        $t4 = (ih === oh);
                                      } else {
                                        $t4 = false;
                                      }
                                      if ($t4 === true) {
                                        host_ok = true;
                                      } else {
                                        {
                                          let $t5;
                                          {
                                            const $rc_141 = ("." + oh);
                                            $t5 = $rc_141;
                                          }
                                          {
                                            const $rc_140 = march_string_ends_with(ih, $t5);
                                            host_ok = $rc_140;
                                          }
                                        }
                                      }
                                    }
                                  } else {
                                    {
                                      const $t6 = (!iw);
                                      if ($t6 === true) {
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
                                      const $t7 = (oport === 0);
                                      {
                                        const $t8 = (oport === iport);
                                        port_ok = ($t7 || $t8);
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
                                          const $f10 = opath._0;
                                          {
                                            const o_paths = $f10;
                                            switch (ipath.$) {
                                              case "None": {
                                                path_ok = false;
                                                break;
                                              }
                                              case "Some": {
                                                const $f9 = ipath._0;
                                                {
                                                  const i_paths = $f9;
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
                                        const $t11 = (host_ok && port_ok);
                                        return ($t11 && path_ok);
                                      }
                                    }
                                  }
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
    let $t3;
    {
      const $t1 = march_string_byte_length(text);
      {
        const $t2 = { $: "Nil" };
        $t3 = Authority$tokenize(text, 0, $t1, $t2);
      }
    }
    switch ($t3.$) {
      case "Err": {
        const $f17 = $t3._0;
        {
          const e = $f17;
          return { $: "Err", _0: e };
        }
        break;
      }
      case "Ok": {
        const $f18 = $t3._0;
        {
          const toks = $f18;
          switch (toks.$) {
            case "Nil": {
              {
                const $t4 = { $: "Nil" };
                return { $: "Ok", _0: $t4 };
              }
              break;
            }
            case "Cons": {
              const $f8 = toks._0;
              const $f9 = toks._1;
              {
                const $jp_clo10 = { $: "$Clo_$jp1_Authority_parse$0_Authority_parse", _0: $jp1_Authority_parse$apply$0_Authority_parse, _1: toks };
                if ($f8 === "(") {
                  {
                    const $jp_clo11 = { $: "$Clo_$jp2_Authority_parse$1_Authority_parse", _0: $jp2_Authority_parse$apply$1_Authority_parse, _1: $jp_clo10 };
                    switch ($f9.$) {
                      case "Cons": {
                        const $f12 = $f9._0;
                        const $f13 = $f9._1;
                        {
                          const $jp_clo14 = { $: "$Clo_$jp3_Authority_parse$2_Authority_parse", _0: $jp3_Authority_parse$apply$2_Authority_parse, _1: $jp_clo11 };
                          if ($f12 === ")") {
                            switch ($f13.$) {
                              case "Nil": {
                                {
                                  const $t5 = { $: "Nil" };
                                  return { $: "Ok", _0: $t5 };
                                }
                                break;
                              }
                              default: {
                                return $jp3_Authority_parse$apply$2_Authority_parse($jp_clo14);
                              }
                            }
                          } else {
                            return $jp3_Authority_parse$apply$2_Authority_parse($jp_clo14);
                          }
                        }
                        break;
                      }
                      default: {
                        return $jp2_Authority_parse$apply$1_Authority_parse($jp_clo11);
                      }
                    }
                  }
                } else {
                  return $jp1_Authority_parse$apply$0_Authority_parse($jp_clo10);
                }
              }
              break;
            }
            default: {
              {
                const $t6 = { $: "Nil" };
                return Authority$parse_entries(toks, $t6);
              }
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
      const $t1 = (i >= n);
      if ($t1 === true) {
        {
          const $t2 = { $: "Nil" };
          {
            const $t3 = Authority$rev(acc, $t2);
            return { $: "Ok", _0: $t3 };
          }
        }
      } else {
        {
          const c = march_string_slice(s, i, 1);
          {
            let $t7;
            {
              let $t6;
              {
                let $t5;
                {
                  const $t4 = (c === " ");
                  if ($t4 === true) {
                    $t5 = true;
                  } else {
                    $t5 = (c === "\t");
                  }
                }
                if ($t5 === true) {
                  $t6 = true;
                } else {
                  $t6 = (c === "\n");
                }
              }
              if ($t6 === true) {
                $t7 = true;
              } else {
                $t7 = (c === "\r");
              }
            }
            if ($t7 === true) {
              {
                const $t8 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                {
                  $tco_a0 = s;
                  $tco_a1 = $t8;
                  $tco_a2 = n;
                  $tco_a3 = acc;
                  continue __tco;
                }
              }
            } else {
              {
                let $t11;
                {
                  let $t10;
                  {
                    const $t9 = (c === "(");
                    if ($t9 === true) {
                      $t10 = true;
                    } else {
                      $t10 = (c === ")");
                    }
                  }
                  if ($t10 === true) {
                    $t11 = true;
                  } else {
                    $t11 = (c === ",");
                  }
                }
                if ($t11 === true) {
                  {
                    const $t12 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                    {
                      const $t13 = { $: "Cons", _0: c, _1: acc };
                      {
                        $tco_a0 = s;
                        $tco_a1 = $t12;
                        $tco_a2 = n;
                        $tco_a3 = $t13;
                        continue __tco;
                      }
                    }
                  }
                } else {
                  {
                    const $t14 = (c === "\"");
                    if ($t14 === true) {
                      {
                        let $t16;
                        {
                          const $t15 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                          $t16 = Authority$read_string(s, $t15, n, "");
                        }
                        switch ($t16.$) {
                          case "Err": {
                            const $f19 = $t16._0;
                            {
                              const e = $f19;
                              return { $: "Err", _0: e };
                            }
                            break;
                          }
                          case "Ok": {
                            const $f20 = $t16._0;
                            const $f21 = $f20._0;
                            const $f22 = $f20._1;
                            {
                              const j = $f22;
                              {
                                const str = $f21;
                                {
                                  let $t17;
                                  {
                                    const $rc_143 = ("\"" + str);
                                    $t17 = $rc_143;
                                  }
                                  {
                                    const $t18 = { $: "Cons", _0: $t17, _1: acc };
                                    {
                                      $tco_a0 = s;
                                      $tco_a1 = j;
                                      $tco_a2 = n;
                                      $tco_a3 = $t18;
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
                        let $t25;
                        {
                          const $t1_i110 = (c !== "");
                          if ($t1_i110 === true) {
                            $t25 = march_string_contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.", c);
                          } else {
                            $t25 = false;
                          }
                        }
                        if ($t25 === true) {
                          {
                            const j = Authority$word_end(s, i, n);
                            {
                              let $t27;
                              {
                                const $t26 = ((j - i) < 4611686018427387904 && (j - i) >= -4611686018427387904 ? (j - i) : march_int_ovf((j - i), 1));
                                $t27 = march_string_slice(s, i, $t26);
                              }
                              {
                                const $t28 = { $: "Cons", _0: $t27, _1: acc };
                                {
                                  $tco_a0 = s;
                                  $tco_a1 = j;
                                  $tco_a2 = n;
                                  $tco_a3 = $t28;
                                  continue __tco;
                                }
                              }
                            }
                          }
                        } else {
                          {
                            let $t29;
                            {
                              const $rc_144 = march_string_concat3("unexpected `", c, "`");
                              $t29 = $rc_144;
                            }
                            return { $: "Err", _0: $t29 };
                          }
                        }
                      }
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
      let $t3;
      {
        const $t1 = (i < n);
        if ($t1 === true) {
          {
            const $t2 = march_string_slice(s, i, 1);
            {
              let $rc_145;
              {
                const $t1_i112 = ($t2 !== "");
                if ($t1_i112 === true) {
                  $rc_145 = march_string_contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.", $t2);
                } else {
                  $rc_145 = false;
                }
              }
              $t3 = $rc_145;
            }
          }
        } else {
          $t3 = false;
        }
      }
      if ($t3 === true) {
        {
          const $t4 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
          {
            $tco_a0 = s;
            $tco_a1 = $t4;
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
      const $t1 = (i >= n);
      if ($t1 === true) {
        return { $: "Err", _0: "a string is not closed" };
      } else {
        {
          const c = march_string_slice(s, i, 1);
          {
            const $t2 = (c === "\"");
            if ($t2 === true) {
              {
                const $t3 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                {
                  const $t4 = { _0: acc, _1: $t3 };
                  return { $: "Ok", _0: $t4 };
                }
              }
            } else {
              {
                const $t5 = (c === "\\");
                if ($t5 === true) {
                  {
                    let $t7;
                    {
                      const $t6 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                      $t7 = ($t6 >= n);
                    }
                    if ($t7 === true) {
                      return { $: "Err", _0: "a string is not closed" };
                    } else {
                      {
                        let e;
                        {
                          const $t8 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                          e = march_string_slice(s, $t8, 1);
                        }
                        {
                          let d;
                          {
                            const $t9 = (e === "n");
                            if ($t9 === true) {
                              d = "\n";
                            } else {
                              {
                                const $t10 = (e === "t");
                                if ($t10 === true) {
                                  d = "\t";
                                } else {
                                  {
                                    const $t11 = (e === "r");
                                    if ($t11 === true) {
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
                            const $t12 = ((i + 2) < 4611686018427387904 && (i + 2) >= -4611686018427387904 ? (i + 2) : march_int_ovf((i + 2), 0));
                            {
                              let $t13;
                              {
                                const $rc_146 = (acc + d);
                                $t13 = $rc_146;
                              }
                              {
                                $tco_a0 = s;
                                $tco_a1 = $t12;
                                $tco_a2 = n;
                                $tco_a3 = $t13;
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
                    const $t14 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                    {
                      let $t15;
                      {
                        const $rc_147 = (acc + c);
                        $t15 = $rc_147;
                      }
                      {
                        $tco_a0 = s;
                        $tco_a1 = $t14;
                        $tco_a2 = n;
                        $tco_a3 = $t15;
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
      const $t1 = Authority$parse_entry(toks);
      switch ($t1.$) {
        case "Err": {
          const $f14 = $t1._0;
          {
            const e = $f14;
            return { $: "Err", _0: e };
          }
          break;
        }
        case "Ok": {
          const $f15 = $t1._0;
          const $f16 = $f15._0;
          const $f17 = $f15._1;
          {
            const rest = $f17;
            {
              const scope = $f16;
              switch (rest.$) {
                case "Nil": {
                  {
                    const $t2 = { $: "Cons", _0: scope, _1: acc };
                    {
                      const $t3 = { $: "Nil" };
                      {
                        const $t4 = Authority$rev_scopes($t2, $t3);
                        return { $: "Ok", _0: $t4 };
                      }
                    }
                  }
                  break;
                }
                case "Cons": {
                  const $f8 = rest._0;
                  const $f9 = rest._1;
                  if ($f8 === ",") {
                    {
                      const more = $f9;
                      {
                        const $t5 = { $: "Cons", _0: scope, _1: acc };
                        {
                          $tco_a0 = more;
                          $tco_a1 = $t5;
                          continue __tco;
                        }
                      }
                    }
                  } else {
                    {
                      const t = $f8;
                      {
                        let $t7;
                        {
                          let $t6;
                          {
                            let $rc_149;
                            {
                              const $t1_i115 = march_string_starts_with(t, "\"");
                              if ($t1_i115 === true) {
                                $rc_149 = "a string";
                              } else {
                                $rc_149 = march_string_concat3("`", t, "`");
                              }
                            }
                            $t6 = $rc_149;
                          }
                          {
                            const $rc_148 = ("expected `,` between capabilities, found " + $t6);
                            $t7 = $rc_148;
                          }
                        }
                        return { $: "Err", _0: $t7 };
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
      const $f36 = toks._0;
      const $f37 = toks._1;
      {
        const rest = $f37;
        {
          const k = $f36;
          {
            let $t2;
            {
              let $t1;
              {
                let $t5_i9730;
                {
                  let $t4_i9729;
                  {
                    let $t3_i9728;
                    {
                      let $t2_i9727;
                      {
                        const $t1_i9726 = march_string_starts_with(k, "\"");
                        $t2_i9727 = (!$t1_i9726);
                      }
                      if ($t2_i9727 === true) {
                        $t3_i9728 = (k !== "(");
                      } else {
                        $t3_i9728 = false;
                      }
                    }
                    if ($t3_i9728 === true) {
                      $t4_i9729 = (k !== ")");
                    } else {
                      $t4_i9729 = false;
                    }
                  }
                  if ($t4_i9729 === true) {
                    $t5_i9730 = (k !== ",");
                  } else {
                    $t5_i9730 = false;
                  }
                }
                if ($t5_i9730 === true) {
                  {
                    const $t6_i9731 = march_string_split(k, ".");
                    {
                      const $rc_153_i9732 = Authority$kind_parts_ok($t6_i9731);
                      $t1 = $rc_153_i9732;
                    }
                  }
                } else {
                  $t1 = false;
                }
              }
              $t2 = (!$t1);
            }
            if ($t2 === true) {
              {
                let $t4;
                {
                  let $t3;
                  {
                    let $rc_151;
                    {
                      const $t1_i117 = march_string_starts_with(k, "\"");
                      if ($t1_i117 === true) {
                        $rc_151 = "a string";
                      } else {
                        $rc_151 = march_string_concat3("`", k, "`");
                      }
                    }
                    $t3 = $rc_151;
                  }
                  {
                    const $rc_150 = ("expected a capability such as `IO.Console`, found " + $t3);
                    $t4 = $rc_150;
                  }
                }
                return { $: "Err", _0: $t4 };
              }
            } else {
              switch (rest.$) {
                case "Cons": {
                  const $f31 = rest._0;
                  const $f32 = rest._1;
                  if ($f31 === "(") {
                    {
                      const after = $f32;
                      switch (after.$) {
                        case "Cons": {
                          const $f23 = after._0;
                          const $f24 = after._1;
                          if ($f23 === ")") {
                            {
                              let $t5;
                              {
                                const $rc_152 = march_string_concat_n("`", k, "()` names no scope: write `", k, "` for any target");
                                $t5 = $rc_152;
                              }
                              return { $: "Err", _0: $t5 };
                            }
                          } else {
                            {
                              let $t8;
                              {
                                const $t6 = { $: "Nil" };
                                {
                                  const $t7 = { $: "Nil" };
                                  $t8 = Authority$parse_items(after, $t6, $t7);
                                }
                              }
                              switch ($t8.$) {
                                case "Err": {
                                  const $f14 = $t8._0;
                                  {
                                    const e = $f14;
                                    return { $: "Err", _0: e };
                                  }
                                  break;
                                }
                                case "Ok": {
                                  const $f15 = $t8._0;
                                  const $f16 = $f15._0;
                                  const $f17 = $f15._1;
                                  const $f18 = $f15._2;
                                  {
                                    const more = $f18;
                                    {
                                      const opts = $f17;
                                      {
                                        const strs = $f16;
                                        {
                                          const $t9 = Authority$scope_arg(k, strs, opts);
                                          switch ($t9.$) {
                                            case "Err": {
                                              const $f12 = $t9._0;
                                              {
                                                const e = $f12;
                                                return { $: "Err", _0: e };
                                              }
                                              break;
                                            }
                                            case "Ok": {
                                              const $f13 = $t9._0;
                                              {
                                                const arg = $f13;
                                                {
                                                  const $t10 = { $: "CapEntry", _0: k, _1: arg };
                                                  {
                                                    const $t11 = { _0: $t10, _1: more };
                                                    return { $: "Ok", _0: $t11 };
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
                            let $t8;
                            {
                              const $t6 = { $: "Nil" };
                              {
                                const $t7 = { $: "Nil" };
                                $t8 = Authority$parse_items(after, $t6, $t7);
                              }
                            }
                            switch ($t8.$) {
                              case "Err": {
                                const $f14 = $t8._0;
                                {
                                  const e = $f14;
                                  return { $: "Err", _0: e };
                                }
                                break;
                              }
                              case "Ok": {
                                const $f15 = $t8._0;
                                const $f16 = $f15._0;
                                const $f17 = $f15._1;
                                const $f18 = $f15._2;
                                {
                                  const more = $f18;
                                  {
                                    const opts = $f17;
                                    {
                                      const strs = $f16;
                                      {
                                        const $t9 = Authority$scope_arg(k, strs, opts);
                                        switch ($t9.$) {
                                          case "Err": {
                                            const $f12 = $t9._0;
                                            {
                                              const e = $f12;
                                              return { $: "Err", _0: e };
                                            }
                                            break;
                                          }
                                          case "Ok": {
                                            const $f13 = $t9._0;
                                            {
                                              const arg = $f13;
                                              {
                                                const $t10 = { $: "CapEntry", _0: k, _1: arg };
                                                {
                                                  const $t11 = { _0: $t10, _1: more };
                                                  return { $: "Ok", _0: $t11 };
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
                      let $t29;
                      {
                        const $t28 = { $: "Any" };
                        $t29 = { $: "CapEntry", _0: k, _1: $t28 };
                      }
                      {
                        const $t30 = { _0: $t29, _1: rest };
                        return { $: "Ok", _0: $t30 };
                      }
                    }
                  }
                  break;
                }
                default: {
                  {
                    let $t29;
                    {
                      const $t28 = { $: "Any" };
                      $t29 = { $: "CapEntry", _0: k, _1: $t28 };
                    }
                    {
                      const $t30 = { _0: $t29, _1: rest };
                      return { $: "Ok", _0: $t30 };
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
        const $f4 = ps._0;
        const $f5 = ps._1;
        {
          const rest = $f5;
          {
            const p = $f4;
            {
              let $t3;
              {
                const $t1 = (p !== "");
                if ($t1 === true) {
                  {
                    const $t2 = march_string_slice(p, 0, 1);
                    {
                      const $rc_154 = march_string_contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ", $t2);
                      $t3 = $rc_154;
                    }
                  }
                } else {
                  $t3 = false;
                }
              }
              if ($t3 === true) {
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
        const $f42 = toks._0;
        const $f43 = toks._1;
        {
          const rest = $f43;
          {
            const t = $f42;
            {
              let item;
              {
                const $t1 = march_string_starts_with(t, "\"");
                if ($t1 === true) {
                  {
                    let $t2;
                    switch (opts.$) {
                      case "Nil": {
                        $t2 = true;
                        break;
                      }
                      default: {
                        $t2 = false;
                        break;
                      }
                    }
                    if ($t2 === true) {
                      {
                        let $t3;
                        {
                          let $rc_157;
                          {
                            let $t2_i127;
                            {
                              const $t1_i126 = march_string_byte_length(t);
                              $t2_i127 = (($t1_i126 - 1) < 4611686018427387904 && ($t1_i126 - 1) >= -4611686018427387904 ? ($t1_i126 - 1) : march_int_ovf(($t1_i126 - 1), 1));
                            }
                            $rc_157 = march_string_slice(t, 1, $t2_i127);
                          }
                          $t3 = $rc_157;
                        }
                        {
                          const $t4 = { $: "Cons", _0: $t3, _1: strs };
                          {
                            const $t5 = { _0: $t4, _1: opts, _2: rest };
                            item = { $: "Ok", _0: $t5 };
                          }
                        }
                      }
                    } else {
                      item = { $: "Err", _0: "a string cannot follow an option in a scope" };
                    }
                  }
                } else {
                  {
                    let $t6;
                    {
                      const $t1_i124 = (t !== "");
                      if ($t1_i124 === true) {
                        $t6 = Authority$all_chars(t, "abcdefghijklmnopqrstuvwxyz_", 0);
                      } else {
                        $t6 = false;
                      }
                    }
                    if ($t6 === true) {
                      {
                        const $t7 = Authority$parse_option(t, rest);
                        switch ($t7.$) {
                          case "Err": {
                            const $f10 = $t7._0;
                            {
                              const e = $f10;
                              item = { $: "Err", _0: e };
                            }
                            break;
                          }
                          case "Ok": {
                            const $f11 = $t7._0;
                            const $f12 = $f11._0;
                            const $f13 = $f11._1;
                            {
                              const more = $f13;
                              {
                                const o = $f12;
                                {
                                  const $t8 = { $: "Cons", _0: o, _1: opts };
                                  {
                                    const $t9 = { _0: strs, _1: $t8, _2: more };
                                    item = { $: "Ok", _0: $t9 };
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
                        let $t17;
                        {
                          let $t16;
                          {
                            let $rc_159;
                            {
                              const $t1_i122 = march_string_starts_with(t, "\"");
                              if ($t1_i122 === true) {
                                $rc_159 = "a string";
                              } else {
                                $rc_159 = march_string_concat3("`", t, "`");
                              }
                            }
                            $t16 = $rc_159;
                          }
                          {
                            const $rc_158 = ("expected a string or an option in a scope, found " + $t16);
                            $t17 = $rc_158;
                          }
                        }
                        item = { $: "Err", _0: $t17 };
                      }
                    }
                  }
                }
              }
              switch (item.$) {
                case "Err": {
                  const $f33 = item._0;
                  {
                    const e = $f33;
                    return { $: "Err", _0: e };
                  }
                  break;
                }
                case "Ok": {
                  const $f34 = item._0;
                  const $f35 = $f34._0;
                  const $f36 = $f34._1;
                  const $f37 = $f34._2;
                  {
                    const more = $f37;
                    {
                      const o2 = $f36;
                      {
                        const s2 = $f35;
                        switch (more.$) {
                          case "Cons": {
                            const $f25 = more._0;
                            const $f26 = more._1;
                            if ($f25 === ")") {
                              {
                                const after = $f26;
                                {
                                  const $t18 = { $: "Nil" };
                                  {
                                    const $t19 = Authority$rev(s2, $t18);
                                    {
                                      const $t20 = { $: "Nil" };
                                      {
                                        const $t21 = Authority$rev(o2, $t20);
                                        {
                                          const $t22 = { _0: $t19, _1: $t21, _2: after };
                                          return { $: "Ok", _0: $t22 };
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            } else if ($f25 === ",") {
                              {
                                const after = $f26;
                                {
                                  $tco_a0 = after;
                                  $tco_a1 = s2;
                                  $tco_a2 = o2;
                                  continue __tco;
                                }
                              }
                            } else {
                              {
                                const x = $f25;
                                {
                                  let $t24;
                                  {
                                    let $t23;
                                    {
                                      let $rc_156;
                                      {
                                        const $t1_i120 = march_string_starts_with(x, "\"");
                                        if ($t1_i120 === true) {
                                          $rc_156 = "a string";
                                        } else {
                                          $rc_156 = march_string_concat3("`", x, "`");
                                        }
                                      }
                                      $t23 = $rc_156;
                                    }
                                    {
                                      const $rc_155 = ("expected `,` or `)` in a scope, found " + $t23);
                                      $t24 = $rc_155;
                                    }
                                  }
                                  return { $: "Err", _0: $t24 };
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
      const $f25 = toks._0;
      const $f26 = toks._1;
      if ($f25 === "(") {
        switch ($f26.$) {
          case "Cons": {
            const $f30 = $f26._0;
            const $f31 = $f26._1;
            {
              let $jp_clo34;
              $jp_clo34 = { $: "$Clo_$jp7_Authority_parse_option$0_Authority_parse_option", _0: $jp7_Authority_parse_option$apply$0_Authority_parse_option, _1: $f26, _2: name };
              switch ($f31.$) {
                case "Cons": {
                  const $f35 = $f31._0;
                  const $f36 = $f31._1;
                  if ($f35 === ")") {
                    {
                      const rest = $f36;
                      {
                        const v = $f30;
                        {
                          const $t1 = march_string_starts_with(v, "\"");
                          if ($t1 === true) {
                            {
                              const $t2 = (name === "methods");
                              if ($t2 === true) {
                                return { $: "Err", _0: "`methods(...)` takes HTTP method names, not a string" };
                              } else {
                                {
                                  let $t4;
                                  {
                                    let $t3;
                                    {
                                      let $rc_161;
                                      {
                                        let $t2_i134;
                                        {
                                          const $t1_i133 = march_string_byte_length(v);
                                          $t2_i134 = (($t1_i133 - 1) < 4611686018427387904 && ($t1_i133 - 1) >= -4611686018427387904 ? ($t1_i133 - 1) : march_int_ovf(($t1_i133 - 1), 1));
                                        }
                                        $rc_161 = march_string_slice(v, 1, $t2_i134);
                                      }
                                      $t3 = $rc_161;
                                    }
                                    {
                                      const $rc_160 = march_string_concat3(name, "=", $t3);
                                      $t4 = $rc_160;
                                    }
                                  }
                                  {
                                    const $t5 = { _0: $t4, _1: rest };
                                    return { $: "Ok", _0: $t5 };
                                  }
                                }
                              }
                            }
                          } else {
                            {
                              let $t7;
                              {
                                const $t6 = (name === "methods");
                                if ($t6 === true) {
                                  {
                                    const $t1_i131 = (v !== "");
                                    if ($t1_i131 === true) {
                                      $t7 = Authority$all_chars(v, "abcdefghijklmnopqrstuvwxyz_", 0);
                                    } else {
                                      $t7 = false;
                                    }
                                  }
                                } else {
                                  $t7 = false;
                                }
                              }
                              if ($t7 === true) {
                                {
                                  let $t8;
                                  {
                                    const $rc_162 = ("methods=" + v);
                                    $t8 = $rc_162;
                                  }
                                  {
                                    const $t9 = { _0: $t8, _1: rest };
                                    return { $: "Ok", _0: $t9 };
                                  }
                                }
                              } else {
                                {
                                  let $t10;
                                  {
                                    const $rc_163 = march_string_concat3("`", name, "(...)` takes a quoted string");
                                    $t10 = $rc_163;
                                  }
                                  return { $: "Err", _0: $t10 };
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  } else {
                    return $jp7_Authority_parse_option$apply$0_Authority_parse_option($jp_clo34);
                  }
                  break;
                }
                default: {
                  return $jp7_Authority_parse_option$apply$0_Authority_parse_option($jp_clo34);
                }
              }
            }
            break;
          }
          default: {
            {
              const more = $f26;
              {
                const $t11 = (name === "methods");
                if ($t11 === true) {
                  {
                    let $t13;
                    {
                      const $t12 = { $: "Nil" };
                      $t13 = Authority$method_words(more, $t12);
                    }
                    switch ($t13.$) {
                      case "Err": {
                        const $f17 = $t13._0;
                        {
                          const e = $f17;
                          return { $: "Err", _0: e };
                        }
                        break;
                      }
                      case "Ok": {
                        const $f18 = $t13._0;
                        const $f19 = $f18._0;
                        const $f20 = $f18._1;
                        {
                          const rest = $f20;
                          {
                            const ms = $f19;
                            {
                              let $t15;
                              {
                                let $t14;
                                {
                                  const $rc_165 = march_string_join(ms, ",");
                                  $t14 = $rc_165;
                                }
                                {
                                  const $rc_164 = ("methods=" + $t14);
                                  $t15 = $rc_164;
                                }
                              }
                              {
                                const $t16 = { _0: $t15, _1: rest };
                                return { $: "Ok", _0: $t16 };
                              }
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
                    let $t23;
                    {
                      const $rc_166 = march_string_concat3("`", name, "(...)` takes one quoted string");
                      $t23 = $rc_166;
                    }
                    return { $: "Err", _0: $t23 };
                  }
                }
              }
            }
          }
        }
      } else {
        {
          const $t24 = { _0: name, _1: toks };
          return { $: "Ok", _0: $t24 };
        }
      }
      break;
    }
    default: {
      {
        const $t24 = { _0: name, _1: toks };
        return { $: "Ok", _0: $t24 };
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
        const $f8 = toks._0;
        const $f9 = toks._1;
        {
          let $jp_clo19;
          $jp_clo19 = { $: "$Clo_$jp7_Authority_method_words$0_Authority_method_words", _0: $jp7_Authority_method_words$apply$0_Authority_method_words, _1: $f8, _2: $f9, _3: acc };
          switch ($f9.$) {
            case "Cons": {
              const $f20 = $f9._0;
              const $f21 = $f9._1;
              if ($f20 === ",") {
                {
                  const rest = $f21;
                  {
                    const m = $f8;
                    {
                      let $t1;
                      {
                        const $t1_i137 = (m !== "");
                        if ($t1_i137 === true) {
                          $t1 = Authority$all_chars(m, "abcdefghijklmnopqrstuvwxyz_", 0);
                        } else {
                          $t1 = false;
                        }
                      }
                      if ($t1 === true) {
                        {
                          const $t2 = { $: "Cons", _0: m, _1: acc };
                          {
                            $tco_a0 = rest;
                            $tco_a1 = $t2;
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
                return $jp7_Authority_method_words$apply$0_Authority_method_words($jp_clo19);
              }
              break;
            }
            default: {
              return $jp7_Authority_method_words$apply$0_Authority_method_words($jp_clo19);
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
    let $t1;
    {
      let $t2_i148;
      {
        const $t1_i147 = (k === "IO.FileRead");
        if ($t1_i147 === true) {
          $t2_i148 = true;
        } else {
          $t2_i148 = (k === "IO.FileWrite");
        }
      }
      if ($t2_i148 === true) {
        $t1 = true;
      } else {
        $t1 = (k === "IO.FileSystem");
      }
    }
    if ($t1 === true) {
      {
        let $t3;
        {
          let $t2;
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
            $t2 = $rc_168;
          }
          $t3 = (!$t2);
        }
        if ($t3 === true) {
          {
            const $t4 = march_string_concat3("a path scope on `", k, "` takes only paths");
            return { $: "Err", _0: $t4 };
          }
        } else {
          {
            const $t5 = Authority$member(strs, "");
            if ($t5 === true) {
              return { $: "Err", _0: "a path scope cannot be empty" };
            } else {
              {
                let $t6;
                $t6 = Authority$first_relative(strs);
                switch ($t6.$) {
                  case "Some": {
                    const $f10 = $t6._0;
                    {
                      const p = $f10;
                      {
                        let $t7;
                        {
                          const $rc_167 = march_string_concat_n("the scope `", p, "` on `", k, "` is a relative path; give an absolute path, one starting with `/`");
                          $t7 = $rc_167;
                        }
                        return { $: "Err", _0: $t7 };
                      }
                    }
                    break;
                  }
                  case "None": {
                    {
                      let $t9;
                      {
                        let $t8;
                        {
                          const l_i9742 = strs;
                          switch (l_i9742.$) {
                            case "Nil": {
                              $t8 = { $: "Nil" };
                              break;
                            }
                            case "Cons": {
                              const $f3_i9743 = l_i9742._0;
                              const $f4_i9744 = l_i9742._1;
                              {
                                const rest_i9745 = $f4_i9744;
                                {
                                  const x_i9746 = $f3_i9743;
                                  {
                                    let $t1_i9748;
                                    {
                                      const $rc_207_i9747 = Authority$normalize(x_i9746);
                                      $t1_i9748 = $rc_207_i9747;
                                    }
                                    {
                                      const $trmc4_i9749 = { $: "Cons", _0: $t1_i9748, _1: null };
                                      Authority$map_normalize$dps(rest_i9745, $trmc4_i9749);
                                      $t8 = $trmc4_i9749;
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
                        $t9 = { $: "PathsAt", _0: $t8 };
                      }
                      return { $: "Ok", _0: $t9 };
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
        const $t11 = (k === "IO.NetConnect");
        if ($t11 === true) {
          {
            let spec;
            switch (strs.$) {
              case "Nil": {
                {
                  let $t12;
                  {
                    const $rc_170 = march_string_join(opts, ";");
                    $t12 = $rc_170;
                  }
                  {
                    const $rc_169 = (";" + $t12);
                    spec = $rc_169;
                  }
                }
                break;
              }
              case "Cons": {
                const $f16 = strs._0;
                const $f17 = strs._1;
                {
                  const more = $f17;
                  {
                    const first = $f16;
                    {
                      let $t13;
                      {
                        const l_i9733 = more;
                        switch (l_i9733.$) {
                          case "Nil": {
                            $t13 = { $: "Nil" };
                            break;
                          }
                          case "Cons": {
                            const $f3_i9735 = l_i9733._0;
                            const $f4_i9736 = l_i9733._1;
                            {
                              const rest_i9737 = $f4_i9736;
                              {
                                const x_i9738 = $f3_i9735;
                                {
                                  let $t1_i9740;
                                  {
                                    const $rc_205_i9739 = ("name=" + x_i9738);
                                    $t1_i9740 = $rc_205_i9739;
                                  }
                                  {
                                    const $trmc4_i9741 = { $: "Cons", _0: $t1_i9740, _1: null };
                                    Authority$prefix_all$dps(rest_i9737, "name=", $trmc4_i9741);
                                    $t13 = $trmc4_i9741;
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
                        let $t14;
                        {
                          const $t1_i142 = { $: "Nil" };
                          {
                            const $t2_i143 = Authority$rev($t13, $t1_i142);
                            $t14 = Authority$rev($t2_i143, opts);
                          }
                        }
                        {
                          const $t15 = { $: "Cons", _0: first, _1: $t14 };
                          {
                            const $rc_171 = march_string_join($t15, ";");
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
              const $t20 = Authority$host_decl(spec);
              switch ($t20.$) {
                case "Err": {
                  const $f37 = $t20._0;
                  {
                    const e = $f37;
                    return { $: "Err", _0: e };
                  }
                  break;
                }
                case "Ok": {
                  const $f38 = $t20._0;
                  const $f39 = $f38._0;
                  const $f40 = $f38._1;
                  const $f41 = $f38._2;
                  const $f42 = $f38._3;
                  {
                    const p = $f39;
                    {
                      const $t21 = (p === "");
                      if ($t21 === true) {
                        {
                          const $t22 = { $: "HostAt", _0: spec, _1: "", _2: false, _3: 0 };
                          return { $: "Ok", _0: $t22 };
                        }
                      } else {
                        {
                          const $t23 = Authority$parse_host_pattern(p);
                          switch ($t23.$) {
                            case "Ok": {
                              const $f25 = $t23._0;
                              const $f26 = $f25._0;
                              const $f27 = $f25._1;
                              const $f28 = $f25._2;
                              const $f29 = $f25._3;
                              {
                                const port = $f28;
                                {
                                  const wild = $f27;
                                  {
                                    const h = $f26;
                                    {
                                      const $t24 = { $: "HostAt", _0: spec, _1: h, _2: wild, _3: port };
                                      return { $: "Ok", _0: $t24 };
                                    }
                                  }
                                }
                              }
                              break;
                            }
                            case "Err": {
                              const $f36 = $t23._0;
                              {
                                const e = $f36;
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
            let $t49;
            {
              const $t1_i139 = (k === "IO.Mut");
              if ($t1_i139 === true) {
                $t49 = true;
              } else {
                $t49 = (k === "IO.Registry");
              }
            }
            if ($t49 === true) {
              {
                let $t51;
                {
                  const $t50 = { $: "Nil" };
                  $t51 = Authority$name_options(opts, $t50);
                }
                switch ($t51.$) {
                  case "Err": {
                    const $f57 = $t51._0;
                    {
                      const e = $f57;
                      return { $: "Err", _0: e };
                    }
                    break;
                  }
                  case "Ok": {
                    const $f58 = $t51._0;
                    {
                      const prefixes = $f58;
                      {
                        const $t52 = Authority$bad_name_text(strs, "a name");
                        switch ($t52.$) {
                          case "Some": {
                            const $f56 = $t52._0;
                            {
                              const e = $f56;
                              return { $: "Err", _0: e };
                            }
                            break;
                          }
                          case "None": {
                            {
                              const $t53 = Authority$bad_name_text(prefixes, "a prefix");
                              switch ($t53.$) {
                                case "Some": {
                                  const $f55 = $t53._0;
                                  {
                                    const e = $f55;
                                    return { $: "Err", _0: e };
                                  }
                                  break;
                                }
                                case "None": {
                                  {
                                    const $t54 = { $: "Names", _0: strs, _1: prefixes };
                                    return { $: "Ok", _0: $t54 };
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
                const $t59 = march_string_concat3("`", k, "` takes no scope");
                return { $: "Err", _0: $t59 };
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
        const $f2 = ps._0;
        const $f3 = ps._1;
        {
          const rest = $f3;
          {
            const p = $f2;
            {
              const $t1 = march_string_starts_with(p, "/");
              if ($t1 === true) {
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
          const $t1 = { $: "Nil" };
          {
            const $t2 = Authority$rev(acc, $t1);
            return { $: "Ok", _0: $t2 };
          }
        }
        break;
      }
      case "Cons": {
        const $f9 = opts._0;
        const $f10 = opts._1;
        {
          const rest = $f10;
          {
            const o = $f9;
            {
              const $t3 = march_string_starts_with(o, "prefix=");
              if ($t3 === true) {
                {
                  let $t6;
                  {
                    let $t5;
                    {
                      const $t4 = march_string_byte_length(o);
                      $t5 = (($t4 - 7) < 4611686018427387904 && ($t4 - 7) >= -4611686018427387904 ? ($t4 - 7) : march_int_ovf(($t4 - 7), 1));
                    }
                    {
                      const $rc_172 = march_string_slice(o, 7, $t5);
                      $t6 = $rc_172;
                    }
                  }
                  {
                    const $t7 = { $: "Cons", _0: $t6, _1: acc };
                    {
                      $tco_a0 = rest;
                      $tco_a1 = $t7;
                      continue __tco;
                    }
                  }
                }
              } else {
                {
                  let $t8;
                  {
                    const $rc_173 = march_string_concat3("`", o, "` is not an option a name scope takes; it takes names and `prefix(\"...\")`");
                    $t8 = $rc_173;
                  }
                  return { $: "Err", _0: $t8 };
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
        const $f7 = ns._0;
        const $f8 = ns._1;
        {
          const rest = $f8;
          {
            const n = $f7;
            {
              const $t1 = (n === "");
              if ($t1 === true) {
                {
                  const $t2 = (what + " cannot be empty");
                  return { $: "Some", _0: $t2 };
                }
              } else {
                {
                  let $t5;
                  {
                    let $t4;
                    {
                      const $t3 = march_string_contains(n, ";");
                      if ($t3 === true) {
                        $t4 = true;
                      } else {
                        $t4 = march_string_contains(n, "=");
                      }
                    }
                    if ($t4 === true) {
                      $t5 = true;
                    } else {
                      $t5 = march_string_contains(n, ",");
                    }
                  }
                  if ($t5 === true) {
                    {
                      const $t6 = march_string_concat_n(what, " `", n, "` contains `;`, `=` or `,`");
                      return { $: "Some", _0: $t6 };
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
      const $f10 = s._0;
      const $f11 = s._1;
      switch ($f11.$) {
        case "Any": {
          {
            const k = $f10;
            return k;
          }
          break;
        }
        default: {
          switch ($f11.$) {
            case "Paths": {
              const $f41 = $f11._0;
              {
                const ps = $f41;
                {
                  const k = $f10;
                  {
                    let $t2;
                    {
                      const $t1 = Authority$quote_all(ps);
                      {
                        const $rc_175 = march_string_join($t1, ", ");
                        $t2 = $rc_175;
                      }
                    }
                    {
                      const $rc_174 = march_string_concat_n(k, "(", $t2, ")");
                      return $rc_174;
                    }
                  }
                }
              }
              break;
            }
            default: {
              switch ($f11.$) {
                case "PathsAt": {
                  const $f37 = $f11._0;
                  {
                    const ps = $f37;
                    {
                      const k = $f10;
                      {
                        let $t4;
                        {
                          const $t3 = Authority$quote_all(ps);
                          {
                            const $rc_177 = march_string_join($t3, ", ");
                            $t4 = $rc_177;
                          }
                        }
                        {
                          const $rc_176 = march_string_concat_n(k, "(", $t4, ")");
                          return $rc_176;
                        }
                      }
                    }
                  }
                  break;
                }
                default: {
                  switch ($f11.$) {
                    case "Names": {
                      const $f30 = $f11._0;
                      const $f31 = $f11._1;
                      {
                        const pre = $f31;
                        {
                          const ns = $f30;
                          {
                            const k = $f10;
                            {
                              let $t9;
                              {
                                const $t5 = Authority$quote_all(ns);
                                {
                                  const $t6 = Authority$quote_all(pre);
                                  {
                                    let $t7;
                                    {
                                      const l_i9750 = $t6;
                                      switch (l_i9750.$) {
                                        case "Nil": {
                                          $t7 = { $: "Nil" };
                                          break;
                                        }
                                        case "Cons": {
                                          const $f3_i9752 = l_i9750._0;
                                          const $f4_i9753 = l_i9750._1;
                                          {
                                            const rest_i9754 = $f4_i9753;
                                            {
                                              const x_i9755 = $f3_i9752;
                                              {
                                                let $t1_i9757;
                                                {
                                                  const $rc_203_i9756 = march_string_concat3("prefix(", x_i9755, ")");
                                                  $t1_i9757 = $rc_203_i9756;
                                                }
                                                {
                                                  const $trmc4_i9758 = { $: "Cons", _0: $t1_i9757, _1: null };
                                                  Authority$wrap_all$dps(rest_i9754, "prefix(", $trmc4_i9758);
                                                  $t7 = $trmc4_i9758;
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
                                      let $t8;
                                      {
                                        const $t1_i151 = { $: "Nil" };
                                        {
                                          const $t2_i152 = Authority$rev($t5, $t1_i151);
                                          $t8 = Authority$rev($t2_i152, $t7);
                                        }
                                      }
                                      {
                                        const $rc_179 = march_string_join($t8, ", ");
                                        $t9 = $rc_179;
                                      }
                                    }
                                  }
                                }
                              }
                              {
                                const $rc_178 = march_string_concat_n(k, "(", $t9, ")");
                                return $rc_178;
                              }
                            }
                          }
                        }
                      }
                      break;
                    }
                    default: {
                      switch ($f11.$) {
                        case "Hosts": {
                          const $f26 = $f11._0;
                          {
                            const spec = $f26;
                            {
                              const k = $f10;
                              {
                                const $rc_180 = Authority$host_scope_text(k, spec);
                                return $rc_180;
                              }
                            }
                          }
                          break;
                        }
                        default: {
                          switch ($f11.$) {
                            case "HostAt": {
                              const $f13 = $f11._0;
                              const $f14 = $f11._1;
                              const $f15 = $f11._2;
                              const $f16 = $f11._3;
                              {
                                const spec = $f13;
                                {
                                  const k = $f10;
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
    const $t1 = march_string_split(spec, ";");
    switch ($t1.$) {
      case "Nil": {
        return k;
        break;
      }
      case "Cons": {
        const $f8 = $t1._0;
        const $f9 = $t1._1;
        {
          const opts = $f9;
          {
            const first = $f8;
            {
              const $t2 = (first === "");
              {
                let head;
                if ($t2 === true) {
                  head = { $: "Nil" };
                } else {
                  {
                    let $t3;
                    {
                      const $rc_184 = Authority$quote(first);
                      $t3 = $rc_184;
                    }
                    {
                      const $t4 = { $: "Nil" };
                      head = { $: "Cons", _0: $t3, _1: $t4 };
                    }
                  }
                }
                {
                  let $t7;
                  {
                    const $t5 = Authority$option_texts(opts);
                    {
                      let $t6;
                      {
                        const $t1_i155 = { $: "Nil" };
                        {
                          const $t2_i156 = Authority$rev(head, $t1_i155);
                          $t6 = Authority$rev($t2_i156, $t5);
                        }
                      }
                      {
                        const $rc_183 = march_string_join($t6, ", ");
                        $t7 = $rc_183;
                      }
                    }
                  }
                  {
                    const $rc_182 = march_string_concat_n(k, "(", $t7, ")");
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
      const $f13 = opts._0;
      const $f14 = opts._1;
      {
        const rest = $f14;
        {
          const o = $f13;
          {
            let t;
            {
              const $t1 = march_string_index_of(o, "=");
              switch ($t1.$) {
                case "None": {
                  t = o;
                  break;
                }
                case "Some": {
                  const $f11 = $t1._0;
                  {
                    const i = $f11;
                    {
                      const name = march_string_slice(o, 0, i);
                      {
                        let v;
                        {
                          const $t2 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                          {
                            let $t5;
                            {
                              let $t4;
                              {
                                const $t3 = march_string_byte_length(o);
                                $t4 = (($t3 - i) < 4611686018427387904 && ($t3 - i) >= -4611686018427387904 ? ($t3 - i) : march_int_ovf(($t3 - i), 1));
                              }
                              $t5 = (($t4 - 1) < 4611686018427387904 && ($t4 - 1) >= -4611686018427387904 ? ($t4 - 1) : march_int_ovf(($t4 - 1), 1));
                            }
                            {
                              const $rc_191 = march_string_slice(o, $t2, $t5);
                              v = $rc_191;
                            }
                          }
                        }
                        {
                          const $t6 = (name === "name");
                          if ($t6 === true) {
                            {
                              const $rc_185 = Authority$quote(v);
                              t = $rc_185;
                            }
                          } else {
                            {
                              const $t7 = (name === "methods");
                              if ($t7 === true) {
                                {
                                  let $t9;
                                  {
                                    let $t8;
                                    {
                                      const $rc_188 = march_string_split(v, ",");
                                      $t8 = $rc_188;
                                    }
                                    {
                                      const $rc_187 = march_string_join($t8, ", ");
                                      $t9 = $rc_187;
                                    }
                                  }
                                  {
                                    const $rc_186 = march_string_concat3("methods(", $t9, ")");
                                    t = $rc_186;
                                  }
                                }
                              } else {
                                {
                                  let $t10;
                                  {
                                    const $rc_190 = Authority$quote(v);
                                    $t10 = $rc_190;
                                  }
                                  {
                                    const $rc_189 = march_string_concat_n(name, "(", $t10, ")");
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
              const $trmc4 = { $: "Cons", _0: t, _1: null };
              Authority$option_texts$dps(rest, $trmc4);
              return $trmc4;
            }
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
          const $trmc2 = { $: "Nil" };
          return ($dst._1 = $trmc2, undefined);
        }
        break;
      }
      case "Cons": {
        const $f13 = opts._0;
        const $f14 = opts._1;
        {
          const rest = $f14;
          {
            const o = $f13;
            {
              let t;
              {
                const $t1 = march_string_index_of(o, "=");
                switch ($t1.$) {
                  case "None": {
                    t = o;
                    break;
                  }
                  case "Some": {
                    const $f11 = $t1._0;
                    {
                      const i = $f11;
                      {
                        const name = march_string_slice(o, 0, i);
                        {
                          let v;
                          {
                            const $t2 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                            {
                              let $t5;
                              {
                                let $t4;
                                {
                                  const $t3 = march_string_byte_length(o);
                                  $t4 = (($t3 - i) < 4611686018427387904 && ($t3 - i) >= -4611686018427387904 ? ($t3 - i) : march_int_ovf(($t3 - i), 1));
                                }
                                $t5 = (($t4 - 1) < 4611686018427387904 && ($t4 - 1) >= -4611686018427387904 ? ($t4 - 1) : march_int_ovf(($t4 - 1), 1));
                              }
                              {
                                const $rc_198 = march_string_slice(o, $t2, $t5);
                                v = $rc_198;
                              }
                            }
                          }
                          {
                            const $t6 = (name === "name");
                            if ($t6 === true) {
                              {
                                const $rc_192 = Authority$quote(v);
                                t = $rc_192;
                              }
                            } else {
                              {
                                const $t7 = (name === "methods");
                                if ($t7 === true) {
                                  {
                                    let $t9;
                                    {
                                      let $t8;
                                      {
                                        const $rc_195 = march_string_split(v, ",");
                                        $t8 = $rc_195;
                                      }
                                      {
                                        const $rc_194 = march_string_join($t8, ", ");
                                        $t9 = $rc_194;
                                      }
                                    }
                                    {
                                      const $rc_193 = march_string_concat3("methods(", $t9, ")");
                                      t = $rc_193;
                                    }
                                  }
                                } else {
                                  {
                                    let $t10;
                                    {
                                      const $rc_197 = Authority$quote(v);
                                      $t10 = $rc_197;
                                    }
                                    {
                                      const $rc_196 = march_string_concat_n(name, "(", $t10, ")");
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
                const $trmc3 = { $: "Cons", _0: t, _1: null };
                ($dst._1 = $trmc3, undefined);
                {
                  $tco_a0 = rest;
                  $tco_a1 = $trmc3;
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
          const $trmc1 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc1, undefined);
        }
      }
    }
    return undefined;
  }
}
const Authority$option_texts$dps$clo = { _0: ($_, opts, $dst) => Authority$option_texts$dps(opts, $dst) };

function Authority$quote(s) {
  {
    let $t2;
    {
      const $t1 = march_string_replace_all(s, "\\", "\\\\");
      {
        const $rc_200 = march_string_replace_all($t1, "\"", "\\\"");
        $t2 = $rc_200;
      }
    }
    {
      const $rc_199 = march_string_concat3("\"", $t2, "\"");
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
      const $f3 = l._0;
      const $f4 = l._1;
      {
        const rest = $f4;
        {
          const x = $f3;
          {
            let $t1;
            {
              const $rc_201 = Authority$quote(x);
              $t1 = $rc_201;
            }
            {
              const $trmc4 = { $: "Cons", _0: $t1, _1: null };
              Authority$quote_all$dps(rest, $trmc4);
              return $trmc4;
            }
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
          const $trmc2 = { $: "Nil" };
          return ($dst._1 = $trmc2, undefined);
        }
        break;
      }
      case "Cons": {
        const $f3 = l._0;
        const $f4 = l._1;
        {
          const rest = $f4;
          {
            const x = $f3;
            {
              let $t1;
              {
                const $rc_202 = Authority$quote(x);
                $t1 = $rc_202;
              }
              {
                const $trmc3 = { $: "Cons", _0: $t1, _1: null };
                ($dst._1 = $trmc3, undefined);
                {
                  $tco_a0 = rest;
                  $tco_a1 = $trmc3;
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
          const $trmc1 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc1, undefined);
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
          const $trmc2 = { $: "Nil" };
          return ($dst._1 = $trmc2, undefined);
        }
        break;
      }
      case "Cons": {
        const $f3 = l._0;
        const $f4 = l._1;
        {
          const rest = $f4;
          {
            const x = $f3;
            {
              let $t1;
              {
                const $rc_204 = march_string_concat3(pre, x, ")");
                $t1 = $rc_204;
              }
              {
                const $trmc3 = { $: "Cons", _0: $t1, _1: null };
                ($dst._1 = $trmc3, undefined);
                {
                  $tco_a0 = rest;
                  $tco_a1 = pre;
                  $tco_a2 = $trmc3;
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
          const $trmc1 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc1, undefined);
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
        const $f2 = l._0;
        const $f3 = l._1;
        {
          const rest = $f3;
          {
            const x = $f2;
            {
              const $t1 = { $: "Cons", _0: x, _1: acc };
              {
                $tco_a0 = rest;
                $tco_a1 = $t1;
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
        const $f2 = l._0;
        const $f3 = l._1;
        {
          const rest = $f3;
          {
            const x = $f2;
            {
              const $t1 = { $: "Cons", _0: x, _1: acc };
              {
                $tco_a0 = rest;
                $tco_a1 = $t1;
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
        const $f2 = l._0;
        const $f3 = l._1;
        {
          const rest = $f3;
          {
            const y = $f2;
            {
              const $t1 = (y === x);
              if ($t1 === true) {
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
        const $f2 = xs._0;
        const $f3 = xs._1;
        {
          const rest = $f3;
          {
            const x = $f2;
            {
              const $t1 = Authority$member(l, x);
              if ($t1 === true) {
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
          const $trmc2 = { $: "Nil" };
          return ($dst._1 = $trmc2, undefined);
        }
        break;
      }
      case "Cons": {
        const $f3 = l._0;
        const $f4 = l._1;
        {
          const rest = $f4;
          {
            const x = $f3;
            {
              let $t1;
              {
                const $rc_206 = (pre + x);
                $t1 = $rc_206;
              }
              {
                const $trmc3 = { $: "Cons", _0: $t1, _1: null };
                ($dst._1 = $trmc3, undefined);
                {
                  $tco_a0 = rest;
                  $tco_a1 = pre;
                  $tco_a2 = $trmc3;
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
          const $trmc1 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc1, undefined);
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
          const $trmc2 = { $: "Nil" };
          return ($dst._1 = $trmc2, undefined);
        }
        break;
      }
      case "Cons": {
        const $f3 = l._0;
        const $f4 = l._1;
        {
          const rest = $f4;
          {
            const x = $f3;
            {
              let $t1;
              {
                const $rc_208 = Authority$normalize(x);
                $t1 = $rc_208;
              }
              {
                const $trmc3 = { $: "Cons", _0: $t1, _1: null };
                ($dst._1 = $trmc3, undefined);
                {
                  $tco_a0 = rest;
                  $tco_a1 = $trmc3;
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
          const $trmc1 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc1, undefined);
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
        const $f3 = scopes._0;
        const $f4 = scopes._1;
        switch ($f3.$) {
          case "CapEntry": {
            const $f5 = $f3._0;
            const $f6 = $f3._1;
            {
              const rest = $f4;
              {
                const arg = $f6;
                {
                  const k = $f5;
                  {
                    let $t2;
                    {
                      let $t1;
                      {
                        const $rc_215 = (k === kind);
                        $t1 = $rc_215;
                      }
                      if ($t1 === true) {
                        $t2 = Authority$arg_admits(arg, kind, target, cwd);
                      } else {
                        $t2 = false;
                      }
                    }
                    if ($t2 === true) {
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
    const $rc_2749 = dom_get_element_by_id$clo._0(dom_get_element_by_id$clo, id);
    return $rc_2749;
  }
}
const Js$Dom$find$clo = { _0: ($_, id) => Js$Dom$find(id) };

function Js$Dom$create(tag) {
  {
    const $rc_2752 = dom_create_element$clo._0(dom_create_element$clo, tag);
    return $rc_2752;
  }
}
const Js$Dom$create$clo = { _0: ($_, tag) => Js$Dom$create(tag) };

function Js$Dom$append(parent, child) {
  {
    const $rc_2755 = dom_append_child$clo._0(dom_append_child$clo, parent, child);
    return $rc_2755;
  }
}
const Js$Dom$append$clo = { _0: ($_, parent, child) => Js$Dom$append(parent, child) };

function Js$Dom$get_attr(el, name) {
  {
    const $rc_2768 = dom_get_attribute$clo._0(dom_get_attribute$clo, el, name);
    return $rc_2768;
  }
}
const Js$Dom$get_attr$clo = { _0: ($_, el, name) => Js$Dom$get_attr(el, name) };

function Js$Dom$set_attr(el, name, val) {
  {
    const $rc_2769 = dom_set_attribute$clo._0(dom_set_attribute$clo, el, name, val);
    return $rc_2769;
  }
}
const Js$Dom$set_attr$clo = { _0: ($_, el, name, val) => Js$Dom$set_attr(el, name, val) };

function Js$Dom$add_class(el, cls) {
  {
    const $rc_2772 = dom_class_add$clo._0(dom_class_add$clo, el, cls);
    return $rc_2772;
  }
}
const Js$Dom$add_class$clo = { _0: ($_, el, cls) => Js$Dom$add_class(el, cls) };

function Js$Dom$set_style(el, prop, val) {
  {
    const $rc_2776 = dom_set_style$clo._0(dom_set_style$clo, el, prop, val);
    return $rc_2776;
  }
}
const Js$Dom$set_style$clo = { _0: ($_, el, prop, val) => Js$Dom$set_style(el, prop, val) };

function Js$Dom$listen(el, event, handler) {
  {
    const $rc_2780 = dom_add_event_listener$clo._0(dom_add_event_listener$clo, el, event, handler);
    return $rc_2780;
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
        const $t1 = { _0: 0, _1: 1 };
        {
          const $t2 = { _0: 1, _1: 1 };
          {
            const $t3 = { _0: 2, _1: 1 };
            {
              const $t4 = { _0: 3, _1: 1 };
              {
                const $t5 = { $: "Nil" };
                {
                  const $t6 = { $: "Cons", _0: $t4, _1: $t5 };
                  {
                    const $t7 = { $: "Cons", _0: $t3, _1: $t6 };
                    {
                      const $t8 = { $: "Cons", _0: $t2, _1: $t7 };
                      return { $: "Cons", _0: $t1, _1: $t8 };
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
        const $t9 = { _0: 1, _1: 1 };
        {
          const $t10 = { _0: 2, _1: 1 };
          {
            const $t11 = { _0: 1, _1: 2 };
            {
              const $t12 = { _0: 2, _1: 2 };
              {
                const $t13 = { $: "Nil" };
                {
                  const $t14 = { $: "Cons", _0: $t12, _1: $t13 };
                  {
                    const $t15 = { $: "Cons", _0: $t11, _1: $t14 };
                    {
                      const $t16 = { $: "Cons", _0: $t10, _1: $t15 };
                      return { $: "Cons", _0: $t9, _1: $t16 };
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
        const $t17 = { _0: 1, _1: 1 };
        {
          const $t18 = { _0: 0, _1: 2 };
          {
            const $t19 = { _0: 1, _1: 2 };
            {
              const $t20 = { _0: 2, _1: 2 };
              {
                const $t21 = { $: "Nil" };
                {
                  const $t22 = { $: "Cons", _0: $t20, _1: $t21 };
                  {
                    const $t23 = { $: "Cons", _0: $t19, _1: $t22 };
                    {
                      const $t24 = { $: "Cons", _0: $t18, _1: $t23 };
                      return { $: "Cons", _0: $t17, _1: $t24 };
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
        const $t25 = { _0: 1, _1: 1 };
        {
          const $t26 = { _0: 2, _1: 1 };
          {
            const $t27 = { _0: 0, _1: 2 };
            {
              const $t28 = { _0: 1, _1: 2 };
              {
                const $t29 = { $: "Nil" };
                {
                  const $t30 = { $: "Cons", _0: $t28, _1: $t29 };
                  {
                    const $t31 = { $: "Cons", _0: $t27, _1: $t30 };
                    {
                      const $t32 = { $: "Cons", _0: $t26, _1: $t31 };
                      return { $: "Cons", _0: $t25, _1: $t32 };
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
        const $t33 = { _0: 0, _1: 1 };
        {
          const $t34 = { _0: 1, _1: 1 };
          {
            const $t35 = { _0: 1, _1: 2 };
            {
              const $t36 = { _0: 2, _1: 2 };
              {
                const $t37 = { $: "Nil" };
                {
                  const $t38 = { $: "Cons", _0: $t36, _1: $t37 };
                  {
                    const $t39 = { $: "Cons", _0: $t35, _1: $t38 };
                    {
                      const $t40 = { $: "Cons", _0: $t34, _1: $t39 };
                      return { $: "Cons", _0: $t33, _1: $t40 };
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
        const $t41 = { _0: 0, _1: 1 };
        {
          const $t42 = { _0: 0, _1: 2 };
          {
            const $t43 = { _0: 1, _1: 2 };
            {
              const $t44 = { _0: 2, _1: 2 };
              {
                const $t45 = { $: "Nil" };
                {
                  const $t46 = { $: "Cons", _0: $t44, _1: $t45 };
                  {
                    const $t47 = { $: "Cons", _0: $t43, _1: $t46 };
                    {
                      const $t48 = { $: "Cons", _0: $t42, _1: $t47 };
                      return { $: "Cons", _0: $t41, _1: $t48 };
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
        const $t49 = { _0: 2, _1: 1 };
        {
          const $t50 = { _0: 0, _1: 2 };
          {
            const $t51 = { _0: 1, _1: 2 };
            {
              const $t52 = { _0: 2, _1: 2 };
              {
                const $t53 = { $: "Nil" };
                {
                  const $t54 = { $: "Cons", _0: $t52, _1: $t53 };
                  {
                    const $t55 = { $: "Cons", _0: $t51, _1: $t54 };
                    {
                      const $t56 = { $: "Cons", _0: $t50, _1: $t55 };
                      return { $: "Cons", _0: $t49, _1: $t56 };
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
  const $f2 = c._0;
  const $f3 = c._1;
  {
    const y = $f3;
    {
      const x = $f2;
      {
        const $t1 = ((3 - y) < 4611686018427387904 && (3 - y) >= -4611686018427387904 ? (3 - y) : march_int_ovf((3 - y), 1));
        return { _0: $t1, _1: x };
      }
    }
  }
}
const TetrisLogic$rotate_cell$clo = { _0: ($_, c) => TetrisLogic$rotate_cell(c) };

function TetrisLogic$clear_lines(board) {
  {
    let rows;
    {
      const go_i5874 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
      {
        const $t5_i5876 = { $: "Nil" };
        rows = go$apply$0_List_range(go_i5874, 19, $t5_i5876);
      }
    }
    {
      let $t3;
      $t3 = { $: "$Clo_$lam0_TetrisLogic_clear_lines$0_TetrisLogic_clear_lines", _0: $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines, _1: board };
      {
        const kept_rows = List$filter$List_Int$Fn_Int_Bool(rows, $t3);
        {
          let cleared;
          {
            let $t5;
            {  };
            $t5 = List$length_onto$List_Int$Int(kept_rows, 0);
            cleared = ((20 - $t5) < 4611686018427387904 && (20 - $t5) >= -4611686018427387904 ? (20 - $t5) : march_int_ovf((20 - $t5), 1));
          }
          {
            const $t6 = { $: "$Clo_$lam1_TetrisLogic_clear_lines$1_TetrisLogic_clear_lines", _0: $lam1_TetrisLogic_clear_lines$apply$1_TetrisLogic_clear_lines, _1: board };
            {
              let kept_cells;
              {
                const f_i5869 = $t6;
                {
                  const $t1_i5870 = { $: "Nil" };
                  kept_cells = List$flat_map_go$List_Int$List_Int$Fn_Int_List_Int($t1_i5870, kept_rows, f_i5869);
                }
              }
              {
                const $t8 = ((cleared * 10) < 4611686018427387904 && (cleared * 10) >= -4611686018427387904 ? (cleared * 10) : march_int_ovf((cleared * 10), 2));
                {
                  let blank_cells;
                  {
                    const go_i5866 = { $: "$Clo_go$0_List_repeat_Int_Int", _0: go$apply$0_List_repeat_Int_Int, _1: 0 };
                    {
                      const $t4_i5867 = { $: "Nil" };
                      blank_cells = go$apply$0_List_repeat_Int_Int(go_i5866, $t8, $t4_i5867);
                    }
                  }
                  {
                    let new_board;
                    {
                      let $t9;
                      {
                        const xs_i14813 = blank_cells;
                        {
                          const ys_i14814 = kept_cells;
                          switch (xs_i14813.$) {
                            case "Nil": {
                              $t9 = kept_cells;
                              break;
                            }
                            case "Cons": {
                              const $f2_i14815 = xs_i14813._0;
                              const $f3_i14816 = xs_i14813._1;
                              {
                                const t_i14817 = $f3_i14816;
                                {
                                  const h_i14818 = $f2_i14815;
                                  {
                                    const $trmc4_i14819 = { $: "Cons", _0: h_i14818, _1: null };
                                    List$append$dps$List_Int$List_Int$List_Int(t_i14817, kept_cells, $trmc4_i14819);
                                    $t9 = $trmc4_i14819;
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
                      new_board = Array$from_list$List_Int($t9);
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
    const $t1 = { $: "$Clo_$lam0_int_list_to_string$0_int_list_to_string", _0: $lam0_int_list_to_string$apply$0_int_list_to_string };
    {
      let $t2;
      {
        const xs_i14820 = xs;
        {
          const f_i14821 = $t1;
          switch (xs_i14820.$) {
            case "Nil": {
              $t2 = { $: "Nil" };
              break;
            }
            case "Cons": {
              const $f3_i14822 = xs_i14820._0;
              const $f4_i14823 = xs_i14820._1;
              {
                const t_i14824 = $f4_i14823;
                {
                  const h_i14825 = $f3_i14822;
                  {
                    let $t1_i14826;
                    $t1_i14826 = f_i14821._0(f_i14821, h_i14825);
                    {
                      const $trmc4_i14827 = { $: "Cons", _0: $t1_i14826, _1: null };
                      List$map$dps$List_Int$Fn_Int_String$List_String(t_i14824, f_i14821, $trmc4_i14827);
                      $t2 = $trmc4_i14827;
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
        const $rc_2831 = march_string_join($t2, ",");
        return $rc_2831;
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
    const $t1 = { $: "I" };
    {
      const $t2 = { $: "O" };
      {
        const $t3 = { $: "T" };
        {
          const $t4 = { $: "S" };
          {
            const $t5 = { $: "Z" };
            {
              const $t6 = { $: "J" };
              {
                const $t7 = { $: "L" };
                {
                  const $t8 = { $: "Nil" };
                  {
                    const $t9 = { $: "Cons", _0: $t7, _1: $t8 };
                    {
                      const $t10 = { $: "Cons", _0: $t6, _1: $t9 };
                      {
                        const $t11 = { $: "Cons", _0: $t5, _1: $t10 };
                        {
                          const $t12 = { $: "Cons", _0: $t4, _1: $t11 };
                          {
                            const $t13 = { $: "Cons", _0: $t3, _1: $t12 };
                            {
                              const $t14 = { $: "Cons", _0: $t2, _1: $t13 };
                              {
                                const pieces = { $: "Cons", _0: $t1, _1: $t14 };
                                {
                                  let rng2;
                                  {
                                    const $t1_i13553 = ((rng * 16807) < 4611686018427387904 && (rng * 16807) >= -4611686018427387904 ? (rng * 16807) : march_int_ovf((rng * 16807), 2));
                                    rng2 = (2147483647 === 0 ? march_mod_zero() : $t1_i13553 % 2147483647);
                                  }
                                  {
                                    const idx = (7 === 0 ? march_mod_zero() : rng2 % 7);
                                    {
                                      let result;
                                      {
                                        const $t15 = List$nth$List_Piece$Int(pieces, idx);
                                        result = { _0: $t15, _1: rng2 };
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
    const $t1 = Js$Dom$find("game-state");
    switch ($t1.$) {
      case "Some": {
        const $f2 = $t1._0;
        {
          const el = $f2;
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
    const $t1 = Js$Dom$get_attr(el, name);
    switch ($t1.$) {
      case "Some": {
        const $f3 = $t1._0;
        {
          const s = $f3;
          {
            let $t2;
            {
              const $rc_2833 = march_string_to_int(s);
              $t2 = $rc_2833;
            }
            {
              const $rc_2832 = Option$unwrap_or$Option_Int$Int($t2, _default);
              return $rc_2832;
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
    const $t1 = Js$Dom$get_attr(el, name);
    switch ($t1.$) {
      case "Some": {
        const $f2 = $t1._0;
        {
          const s = $f2;
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
        let $t1;
        {
          const xs_i14828 = cells;
          {
            const f_i14829 = TetrisLogic$rotate_cell$clo;
            switch (xs_i14828.$) {
              case "Nil": {
                $t1 = { $: "Nil" };
                break;
              }
              case "Cons": {
                const $f3_i14830 = xs_i14828._0;
                const $f4_i14831 = xs_i14828._1;
                {
                  const t_i14832 = $f4_i14831;
                  {
                    const h_i14833 = $f3_i14830;
                    {
                      let $t1_i14834;
                      $t1_i14834 = f_i14829._0(f_i14829, h_i14833);
                      {
                        const $trmc4_i14835 = { $: "Cons", _0: $t1_i14834, _1: null };
                        List$map$dps$List_T_Int_Int$Fn_T_Int_Int_T_Int_Int$List_T_Int_Int(t_i14832, f_i14829, $trmc4_i14835);
                        $t1 = $trmc4_i14835;
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
          const $t2 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
          {
            $tco_a0 = $t1;
            $tco_a1 = $t2;
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
        const $t8_i5886 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: 3, _3: 0 };
        over = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t8_i5886);
      }
      {
        const $t1 = next_piece(rng);
        const $f2 = $t1._0;
        const $f3 = $t1._1;
        {
          const rng2 = $f3;
          {
            const next2 = $f2;
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
    const $t1 = Js$Dom$find(id);
    switch ($t1.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f2 = $t1._0;
        {
          const el = $f2;
          {
            const el_i13554 = el;
            {
              const text_i13555 = text;
              {
                const $rc_2765_i13556 = dom_set_text$clo._0(dom_set_text$clo, el, text);
                return $rc_2765_i13556;
              }
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
        let $t1;
        $t1 = get_str_attr(el, "data-over", "false");
        {
          const $rc_2842 = ($t1 === "true");
          over = $rc_2842;
        }
      }
      if (over === true) {
        return {  };
      } else if (over === false) {
        {
          let board;
          {
            let $t2;
            $t2 = get_str_attr(el, "data-board", "");
            {
              let $t3;
              {
                let $rc_2841;
                {
                  const $t1_i5916 = march_string_split($t2, ",");
                  {
                    const $t3_i5917 = { $: "$Clo_$lam0_string_to_int_list$0_string_to_int_list", _0: $lam0_string_to_int_list$apply$0_string_to_int_list };
                    $rc_2841 = List$map$List_String$Fn_String_Int($t1_i5916, $t3_i5917);
                  }
                }
                $t3 = $rc_2841;
              }
              board = Array$from_list$List_Int($t3);
            }
          }
          {
            let piece;
            {
              let $t4;
              $t4 = get_str_attr(el, "data-piece", "I");
              {
                let $rc_2840;
                if ($t4 === "I") {
                  $rc_2840 = { $: "I" };
                } else if ($t4 === "O") {
                  $rc_2840 = { $: "O" };
                } else if ($t4 === "T") {
                  $rc_2840 = { $: "T" };
                } else if ($t4 === "S") {
                  $rc_2840 = { $: "S" };
                } else if ($t4 === "Z") {
                  $rc_2840 = { $: "Z" };
                } else if ($t4 === "J") {
                  $rc_2840 = { $: "J" };
                } else {
                  $rc_2840 = { $: "L" };
                }
                piece = $rc_2840;
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
                      let $t5;
                      $t5 = get_str_attr(el, "data-next", "O");
                      {
                        let $rc_2839;
                        if ($t5 === "I") {
                          $rc_2839 = { $: "I" };
                        } else if ($t5 === "O") {
                          $rc_2839 = { $: "O" };
                        } else if ($t5 === "T") {
                          $rc_2839 = { $: "T" };
                        } else if ($t5 === "S") {
                          $rc_2839 = { $: "S" };
                        } else if ($t5 === "Z") {
                          $rc_2839 = { $: "Z" };
                        } else if ($t5 === "J") {
                          $rc_2839 = { $: "J" };
                        } else {
                          $rc_2839 = { $: "L" };
                        }
                        next = $rc_2839;
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
                              const $t6 = f._0(f, board, piece, rot, x, y, next, score, lines, rng);
                              const $f26 = $t6._0;
                              const $f27 = $t6._1;
                              const $f28 = $t6._2;
                              const $f29 = $t6._3;
                              const $f30 = $t6._4;
                              const $f31 = $t6._5;
                              const $f32 = $t6._6;
                              const $f33 = $t6._7;
                              const $f34 = $t6._8;
                              const $f35 = $t6._9;
                              {
                                const over2 = $f35;
                                {
                                  const rng2 = $f34;
                                  {
                                    const lines2 = $f33;
                                    {
                                      const score2 = $f32;
                                      {
                                        const next2 = $f31;
                                        {
                                          const y2 = $f30;
                                          {
                                            const x2 = $f29;
                                            {
                                              const rot2 = $f28;
                                              {
                                                const piece2 = $f27;
                                                {
                                                  const board2 = $f26;
                                                  {
                                                    let $eff;
                                                    {
                                                      let $t2_i5911;
                                                      {
                                                        const go_i14734 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                                                        {
                                                          const $t5_i14736 = { $: "Nil" };
                                                          $t2_i5911 = go$apply$0_List_range(go_i14734, 19, $t5_i14736);
                                                        }
                                                      }
                                                      {
                                                        const $t12_i5912 = { $: "$Clo_$lam0_render_board$0_render_board", _0: $lam0_render_board$apply$0_render_board, _1: board2 };
                                                        {
                                                          const f_i14730 = $t12_i5912;
                                                          {
                                                            const go_i14731 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i14730 };
                                                            $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i14731, $t2_i5911);
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                  {
                                                    let $eff;
                                                    if (over2 === false) {
                                                      {
                                                        const base_cells_i5906 = TetrisLogic$piece_cells(piece2);
                                                        {
                                                          const rotated_i5907 = rotate_n(base_cells_i5906, rot2);
                                                          {
                                                            const $t17_i5908 = { $: "$Clo_$lam0_render_falling$0_render_falling", _0: $lam0_render_falling$apply$0_render_falling, _1: x2, _2: y2, _3: piece2 };
                                                            {
                                                              const f_i14727 = $t17_i5908;
                                                              {
                                                                const go_i14728 = { $: "$Clo_go$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_", _0: go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_, _1: f_i14727 };
                                                                $eff = go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_(go_i14728, rotated_i5907);
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
                                                      let $t8;
                                                      {
                                                        const $t7 = String(score2);
                                                        {
                                                          const $rc_2838 = ("Score: " + $t7);
                                                          $t8 = $rc_2838;
                                                        }
                                                      }
                                                      $eff = set_text_if_found("score", $t8);
                                                    }
                                                  }
                                                  {
                                                    let $eff;
                                                    {
                                                      let $t11;
                                                      {
                                                        let $t10;
                                                        {
                                                          const $t9 = TetrisLogic$level_for_lines(lines2);
                                                          $t10 = String($t9);
                                                        }
                                                        {
                                                          const $rc_2837 = ("Level: " + $t10);
                                                          $t11 = $rc_2837;
                                                        }
                                                      }
                                                      $eff = set_text_if_found("level", $t11);
                                                    }
                                                  }
                                                  {
                                                    let $eff;
                                                    {
                                                      let $t13;
                                                      {
                                                        const $t12 = piece_to_string(next2);
                                                        {
                                                          const $rc_2836 = ("Next: " + $t12);
                                                          $t13 = $rc_2836;
                                                        }
                                                      }
                                                      $eff = set_text_if_found("next", $t13);
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
                                                        let $t15;
                                                        {
                                                          let $t14;
                                                          {
                                                            const $t1_i5899 = { $: "Nil" };
                                                            {
                                                              const $t2_i5900 = { $: "$Clo_$lam0_Array_to_list$0_Array_to_list_PVec_Int", _0: $lam0_Array_to_list$apply$0_Array_to_list_PVec_Int };
                                                              {
                                                                const rev_i5901 = Array$fold_left$PVec_Int$List_Int$Fn_List_Int_Int_List_Int(board2, $t1_i5899, $t2_i5900);
                                                                {
                                                                  const go_i14724 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                                                                  {
                                                                    const $t6_i14725 = { $: "Nil" };
                                                                    $t14 = go$apply$0_Array_lst_rev_List_Int(go_i14724, rev_i5901, $t6_i14725);
                                                                  }
                                                                }
                                                              }
                                                            }
                                                          }
                                                          $t15 = int_list_to_string($t14);
                                                        }
                                                        $eff = Js$Dom$set_attr(el, "data-board", $t15);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        let $t16;
                                                        {
                                                          const $rc_2835 = piece_to_string(piece2);
                                                          $t16 = $rc_2835;
                                                        }
                                                        $eff = Js$Dom$set_attr(el, "data-piece", $t16);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t17 = String(rot2);
                                                        $eff = Js$Dom$set_attr(el, "data-rot", $t17);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t18 = String(x2);
                                                        $eff = Js$Dom$set_attr(el, "data-x", $t18);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t19 = String(y2);
                                                        $eff = Js$Dom$set_attr(el, "data-y", $t19);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        let $t20;
                                                        {
                                                          const $rc_2834 = piece_to_string(next2);
                                                          $t20 = $rc_2834;
                                                        }
                                                        $eff = Js$Dom$set_attr(el, "data-next", $t20);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t21 = String(score2);
                                                        $eff = Js$Dom$set_attr(el, "data-score", $t21);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t22 = String(lines2);
                                                        $eff = Js$Dom$set_attr(el, "data-lines", $t22);
                                                      }
                                                    }
                                                    {
                                                      let $eff;
                                                      {
                                                        const $t23 = String(rng2);
                                                        $eff = Js$Dom$set_attr(el, "data-rng", $t23);
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
                                                        let $t25;
                                                        {
                                                          const $t24 = ((seq + 1) < 4611686018427387904 && (seq + 1) >= -4611686018427387904 ? (seq + 1) : march_int_ovf((seq + 1), 0));
                                                          $t25 = String($t24);
                                                        }
                                                        return Js$Dom$set_attr(el, "data-seq", $t25);
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
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
    const $t1 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t1, rot);
      {
        let locked;
        {
          let $t2;
          switch (piece.$) {
            case "I": {
              $t2 = 1;
              break;
            }
            case "O": {
              $t2 = 2;
              break;
            }
            case "T": {
              $t2 = 3;
              break;
            }
            case "S": {
              $t2 = 4;
              break;
            }
            case "Z": {
              $t2 = 5;
              break;
            }
            case "J": {
              $t2 = 6;
              break;
            }
            case "L": {
              $t2 = 7;
              break;
            }
            default: {
              throw march_panic_error("panic: ", "non-exhaustive pattern match");
              break;
            }
          }
          {
            const $t7_i5924 = { $: "$Clo_$lam0_TetrisLogic_lock_piece$0_TetrisLogic_lock_piece", _0: $lam0_TetrisLogic_lock_piece$apply$0_TetrisLogic_lock_piece, _1: $t2, _2: x, _3: y };
            locked = List$fold_left$List_T_Int_Int$PVec_Int$Fn_PVec_Int_T_Int_Int_PVec_Int(cells, board, $t7_i5924);
          }
        }
        {
          const $t3 = TetrisLogic$clear_lines(locked);
          const $f25 = $t3._0;
          const $f26 = $t3._1;
          {
            const n = $f26;
            {
              const cleared_board = $f25;
              {
                let new_score;
                {
                  let $t4;
                  if (n === 1) {
                    $t4 = 100;
                  } else if (n === 2) {
                    $t4 = 300;
                  } else if (n === 3) {
                    $t4 = 500;
                  } else if (n === 4) {
                    $t4 = 800;
                  } else {
                    $t4 = 0;
                  }
                  new_score = ((score + $t4) < 4611686018427387904 && (score + $t4) >= -4611686018427387904 ? (score + $t4) : march_int_ovf((score + $t4), 0));
                }
                {
                  const new_lines = ((lines + n) < 4611686018427387904 && (lines + n) >= -4611686018427387904 ? (lines + n) : march_int_ovf((lines + n), 0));
                  {
                    let $t5;
                    $t5 = spawn_piece(next, cleared_board, rng);
                    const $f6 = $t5._0;
                    const $f7 = $t5._1;
                    const $f8 = $t5._2;
                    const $f9 = $t5._3;
                    const $f10 = $t5._4;
                    const $f11 = $t5._5;
                    const $f12 = $t5._6;
                    {
                      const over = $f12;
                      {
                        const rng2 = $f11;
                        {
                          const next2 = $f10;
                          {
                            const y2 = $f9;
                            {
                              const x2 = $f8;
                              {
                                const rot2 = $f7;
                                {
                                  const piece2 = $f6;
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
    let $t2;
    {
      const $t1 = state_el();
      $t2 = get_str_attr($t1, "data-paused", "false");
    }
    {
      const $rc_2843 = ($t2 === "true");
      return $rc_2843;
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
        let $t1;
        $t1 = get_str_attr(el, "data-over", "false");
        {
          const $rc_2844 = ($t1 === "true");
          over = $rc_2844;
        }
      }
      if (over === true) {
        return {  };
      } else if (over === false) {
        {
          let $t3;
          {
            const $t2 = is_paused();
            $t3 = (!$t2);
          }
          return set_paused(el, $t3);
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
      let $t2;
      {
        const $t1 = ((cur_y + 1) < 4611686018427387904 && (cur_y + 1) >= -4611686018427387904 ? (cur_y + 1) : march_int_ovf((cur_y + 1), 0));
        {
          const $t8_i5932 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: x, _3: $t1 };
          $t2 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t8_i5932);
        }
      }
      if ($t2 === true) {
        return cur_y;
      } else if ($t2 === false) {
        {
          const $t3 = ((cur_y + 1) < 4611686018427387904 && (cur_y + 1) >= -4611686018427387904 ? (cur_y + 1) : march_int_ovf((cur_y + 1), 0));
          {
            $tco_a0 = board;
            $tco_a1 = cells;
            $tco_a2 = x;
            $tco_a3 = $t3;
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
        let $t4_i5951;
        {
          const go_i14755 = { $: "$Clo_go$0_List_repeat_Int_Int", _0: go$apply$0_List_repeat_Int_Int, _1: 0 };
          {
            const $t4_i14756 = { $: "Nil" };
            $t4_i5951 = go$apply$0_List_repeat_Int_Int(go_i14755, 200, $t4_i14756);
          }
        }
        board = Array$from_list$List_Int($t4_i5951);
      }
      {
        let rng0;
        {
          let raw_i13562;
          {
            let $t4_i13561;
            {
              let $t3_i13560;
              {
                let $t2_i13559;
                {
                  let $t1_i13558;
                  {
                    const $t1_i14844 = Authority$check("IO.Clock", "");
                    switch ($t1_i14844.$) {
                      case "Ok": {
                        const $f4_i14845 = $t1_i14844._0;
                        {
                          let $t3_i14847;
                          {
                            const $t2_i14846 = {  };
                            $t3_i14847 = march_unix_time();
                          }
                          $t1_i13558 = { $: "Ok", _0: $t3_i14847 };
                        }
                        break;
                      }
                      case "Err": {
                        const $f5_i14848 = $t1_i14844._0;
                        {
                          const $letq_err_i14849 = $f5_i14848;
                          $t1_i13558 = { $: "Err", _0: $letq_err_i14849 };
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
                    const r_i14836 = $t1_i13558;
                    switch (r_i14836.$) {
                      case "Ok": {
                        const $f3_i14837 = r_i14836._0;
                        {
                          const v_i14838 = $f3_i14837;
                          $t2_i13559 = v_i14838;
                        }
                        break;
                      }
                      case "Err": {
                        const $f4_i14839 = r_i14836._0;
                        {
                          const e_i14840 = $f4_i14839;
                          march_panic_site("stdlib/authority.march", 98, 14, 58);
                          {
                            let $t2_i14843;
                            {
                              const $t1_i14841 = Authority$describe(e_i14840);
                              {
                                const $rc_3041_i14842 = ("capability refused: " + $t1_i14841);
                                $t2_i14843 = $rc_3041_i14842;
                              }
                            }
                            throw march_panic_error("panic: ", $t2_i14843);
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
                $t3_i13560 = ($t2_i13559 * 1000000.0);
              }
              $t4_i13561 = march_float_to_int($t3_i13560);
            }
            raw_i13562 = march_int_mod($t4_i13561, 2147483646);
          }
          {
            const $t5_i13563 = (raw_i13562 <= 0);
            if ($t5_i13563 === true) {
              rng0 = ((raw_i13562 + 2147483646) < 4611686018427387904 && (raw_i13562 + 2147483646) >= -4611686018427387904 ? (raw_i13562 + 2147483646) : march_int_ovf((raw_i13562 + 2147483646), 0));
            } else if ($t5_i13563 === false) {
              rng0 = raw_i13562;
            } else {
              throw march_panic_error("panic: ", "non-exhaustive pattern match");
            }
          }
        }
        {
          const $t1 = next_piece(rng0);
          const $f35 = $t1._0;
          const $f36 = $t1._1;
          {
            const rng1 = $f36;
            {
              const first = $f35;
              {
                let $t2;
                $t2 = spawn_piece(first, board, rng1);
                const $f16 = $t2._0;
                const $f17 = $t2._1;
                const $f18 = $t2._2;
                const $f19 = $t2._3;
                const $f20 = $t2._4;
                const $f21 = $t2._5;
                const $f22 = $t2._6;
                {
                  const rng2 = $f21;
                  {
                    const next = $f20;
                    {
                      const y = $f19;
                      {
                        const x = $f18;
                        {
                          const rot = $f17;
                          {
                            const piece = $f16;
                            {
                              let $eff;
                              {
                                let $t2_i5946;
                                {
                                  const go_i14750 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                                  {
                                    const $t5_i14752 = { $: "Nil" };
                                    $t2_i5946 = go$apply$0_List_range(go_i14750, 19, $t5_i14752);
                                  }
                                }
                                {
                                  const $t12_i5947 = { $: "$Clo_$lam0_render_board$0_render_board", _0: $lam0_render_board$apply$0_render_board, _1: board };
                                  {
                                    const f_i14746 = $t12_i5947;
                                    {
                                      const go_i14747 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i14746 };
                                      $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i14747, $t2_i5946);
                                    }
                                  }
                                }
                              }
                            }
                            {
                              let $eff;
                              {
                                const base_cells_i5941 = TetrisLogic$piece_cells(piece);
                                {
                                  const rotated_i5942 = rotate_n(base_cells_i5941, rot);
                                  {
                                    const $t17_i5943 = { $: "$Clo_$lam0_render_falling$0_render_falling", _0: $lam0_render_falling$apply$0_render_falling, _1: x, _2: y, _3: piece };
                                    {
                                      const f_i14743 = $t17_i5943;
                                      {
                                        const go_i14744 = { $: "$Clo_go$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_", _0: go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_, _1: f_i14743 };
                                        $eff = go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_(go_i14744, rotated_i5942);
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
                                let $t4;
                                {
                                  const $t3 = piece_to_string(next);
                                  {
                                    const $rc_2847 = ("Next: " + $t3);
                                    $t4 = $rc_2847;
                                  }
                                }
                                $eff = set_text_if_found("next", $t4);
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
                                let $t6;
                                {
                                  let $t5;
                                  {
                                    const $t1_i5934 = { $: "Nil" };
                                    {
                                      const $t2_i5935 = { $: "$Clo_$lam0_Array_to_list$0_Array_to_list_PVec_Int", _0: $lam0_Array_to_list$apply$0_Array_to_list_PVec_Int };
                                      {
                                        const rev_i5936 = Array$fold_left$PVec_Int$List_Int$Fn_List_Int_Int_List_Int(board, $t1_i5934, $t2_i5935);
                                        {
                                          const go_i14740 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                                          {
                                            const $t6_i14741 = { $: "Nil" };
                                            $t5 = go$apply$0_Array_lst_rev_List_Int(go_i14740, rev_i5936, $t6_i14741);
                                          }
                                        }
                                      }
                                    }
                                  }
                                  $t6 = int_list_to_string($t5);
                                }
                                $eff = Js$Dom$set_attr(el, "data-board", $t6);
                              }
                            }
                            {
                              let $eff;
                              {
                                let $t7;
                                {
                                  const $rc_2846 = piece_to_string(piece);
                                  $t7 = $rc_2846;
                                }
                                $eff = Js$Dom$set_attr(el, "data-piece", $t7);
                              }
                            }
                            {
                              let $eff;
                              {
                                const $t8 = String(rot);
                                $eff = Js$Dom$set_attr(el, "data-rot", $t8);
                              }
                            }
                            {
                              let $eff;
                              {
                                const $t9 = String(x);
                                $eff = Js$Dom$set_attr(el, "data-x", $t9);
                              }
                            }
                            {
                              let $eff;
                              {
                                const $t10 = String(y);
                                $eff = Js$Dom$set_attr(el, "data-y", $t10);
                              }
                            }
                            {
                              let $eff;
                              {
                                let $t11;
                                {
                                  const $rc_2845 = piece_to_string(next);
                                  $t11 = $rc_2845;
                                }
                                $eff = Js$Dom$set_attr(el, "data-next", $t11);
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
                                const $t12 = String(rng2);
                                $eff = Js$Dom$set_attr(el, "data-rng", $t12);
                              }
                            }
                            {
                              let $eff;
                              $eff = Js$Dom$set_attr(el, "data-over", "false");
                            }
                            {
                              let $t15;
                              {
                                let $t14;
                                {
                                  let $t13;
                                  $t13 = get_int_attr(el, "data-seq", 0);
                                  $t14 = (($t13 + 1) < 4611686018427387904 && ($t13 + 1) >= -4611686018427387904 ? ($t13 + 1) : march_int_ovf(($t13 + 1), 0));
                                }
                                $t15 = String($t14);
                              }
                              return Js$Dom$set_attr(el, "data-seq", $t15);
                            }
                          }
                        }
                      }
                    }
                  }
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
    const $t1 = Js$Dom$find("restore-request");
    switch ($t1.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f17 = $t1._0;
        {
          const req = $f17;
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
                                  let $t2;
                                  $t2 = get_str_attr(req, "data-over", "false");
                                  {
                                    const $rc_2853 = ($t2 === "true");
                                    over = $rc_2853;
                                  }
                                }
                                {
                                  let paused;
                                  {
                                    const $t3 = get_str_attr(req, "data-paused", "false");
                                    {
                                      const $rc_2852 = ($t3 === "true");
                                      paused = $rc_2852;
                                    }
                                  }
                                  {
                                    let board;
                                    {
                                      let $t4;
                                      {
                                        const $t1_i5966 = march_string_split(board_s, ",");
                                        {
                                          const $t3_i5967 = { $: "$Clo_$lam0_string_to_int_list$0_string_to_int_list", _0: $lam0_string_to_int_list$apply$0_string_to_int_list };
                                          $t4 = List$map$List_String$Fn_String_Int($t1_i5966, $t3_i5967);
                                        }
                                      }
                                      board = Array$from_list$List_Int($t4);
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
                                            let $t2_i5961;
                                            {
                                              const go_i14765 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                                              {
                                                const $t5_i14767 = { $: "Nil" };
                                                $t2_i5961 = go$apply$0_List_range(go_i14765, 19, $t5_i14767);
                                              }
                                            }
                                            {
                                              const $t12_i5962 = { $: "$Clo_$lam0_render_board$0_render_board", _0: $lam0_render_board$apply$0_render_board, _1: board };
                                              {
                                                const f_i14761 = $t12_i5962;
                                                {
                                                  const go_i14762 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i14761 };
                                                  $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i14762, $t2_i5961);
                                                }
                                              }
                                            }
                                          }
                                        }
                                        {
                                          let $eff;
                                          if (over === false) {
                                            {
                                              const base_cells_i5956 = TetrisLogic$piece_cells(piece);
                                              {
                                                const rotated_i5957 = rotate_n(base_cells_i5956, rot);
                                                {
                                                  const $t17_i5958 = { $: "$Clo_$lam0_render_falling$0_render_falling", _0: $lam0_render_falling$apply$0_render_falling, _1: x, _2: y, _3: piece };
                                                  {
                                                    const f_i14758 = $t17_i5958;
                                                    {
                                                      const go_i14759 = { $: "$Clo_go$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_", _0: go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_, _1: f_i14758 };
                                                      $eff = go$apply$0_List_each_List_T_Int_Int_Fn_T_Int_Int_T_(go_i14759, rotated_i5957);
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
                                            let $t6;
                                            {
                                              const $t5 = String(score);
                                              {
                                                const $rc_2851 = ("Score: " + $t5);
                                                $t6 = $rc_2851;
                                              }
                                            }
                                            $eff = set_text_if_found("score", $t6);
                                          }
                                        }
                                        {
                                          let $eff;
                                          {
                                            let $t9;
                                            {
                                              let $t8;
                                              {
                                                const $t7 = TetrisLogic$level_for_lines(lines);
                                                $t8 = String($t7);
                                              }
                                              {
                                                const $rc_2850 = ("Level: " + $t8);
                                                $t9 = $rc_2850;
                                              }
                                            }
                                            $eff = set_text_if_found("level", $t9);
                                          }
                                        }
                                        {
                                          let $eff;
                                          {
                                            let $t11;
                                            {
                                              let $t10;
                                              {
                                                const $rc_2849 = piece_to_string(next);
                                                $t10 = $rc_2849;
                                              }
                                              {
                                                const $rc_2848 = ("Next: " + $t10);
                                                $t11 = $rc_2848;
                                              }
                                            }
                                            $eff = set_text_if_found("next", $t11);
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
                                              const $t12 = String(rot);
                                              $eff = Js$Dom$set_attr(el, "data-rot", $t12);
                                            }
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t13 = String(x);
                                              $eff = Js$Dom$set_attr(el, "data-x", $t13);
                                            }
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t14 = String(y);
                                              $eff = Js$Dom$set_attr(el, "data-y", $t14);
                                            }
                                          }
                                          {
                                            let $eff;
                                            $eff = Js$Dom$set_attr(el, "data-next", next_s);
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t15 = String(score);
                                              $eff = Js$Dom$set_attr(el, "data-score", $t15);
                                            }
                                          }
                                          {
                                            let $eff;
                                            {
                                              const $t16 = String(lines);
                                              $eff = Js$Dom$set_attr(el, "data-lines", $t16);
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
      const ev_i13566 = ev;
      {
        const $rc_2784_i13567 = dom_event_key$clo._0(dom_event_key$clo, ev);
        key = $rc_2784_i13567;
      }
    }
    {
      let $eff;
      {
        let $t1;
        if (key === "ArrowLeft") {
          $t1 = true;
        } else if (key === "ArrowRight") {
          $t1 = true;
        } else if (key === "ArrowDown") {
          $t1 = true;
        } else if (key === "ArrowUp") {
          $t1 = true;
        } else if (key === " ") {
          $t1 = true;
        } else {
          $t1 = false;
        }
        if ($t1 === true) {
          {
            const ev_i13564 = ev;
            {
              const $rc_2785_i13565 = dom_prevent_default$clo._0(dom_prevent_default$clo, ev);
              $eff = $rc_2785_i13565;
            }
          }
        } else if ($t1 === false) {
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
          const $t2 = is_paused();
          if ($t2 === true) {
            return {  };
          } else if ($t2 === false) {
            if (k === "ArrowLeft") {
              {
                const $t3 = march_int_ovf(-(1), 3);
                {
                  const $t7_i5978 = { $: "$Clo_$lam0_try_move$0_try_move", _0: $lam0_try_move$apply$0_try_move, _1: $t3, _2: 0 };
                  return with_state($t7_i5978);
                }
              }
            } else if (k === "ArrowRight") {
              {
                const $t7_i5981 = { $: "$Clo_$lam0_try_move$0_try_move", _0: $lam0_try_move$apply$0_try_move, _1: 1, _2: 0 };
                return with_state($t7_i5981);
              }
            } else if (k === "ArrowDown") {
              {
                const $t7_i5984 = { $: "$Clo_$lam0_try_move$0_try_move", _0: $lam0_try_move$apply$0_try_move, _1: 0, _2: 1 };
                return with_state($t7_i5984);
              }
            } else if (k === "ArrowUp") {
              {
                const $t4_i5985 = { $: "$Clo_$lam0_try_rotate$0_try_rotate", _0: $lam0_try_rotate$apply$0_try_rotate };
                return with_state($t4_i5985);
              }
            } else if (k === " ") {
              {
                const $t2_i5986 = { $: "$Clo_$lam0_hard_drop$0_hard_drop", _0: $lam0_hard_drop$apply$0_hard_drop };
                return with_state($t2_i5986);
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
    const $t1 = Js$Dom$find("board");
    switch ($t1.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f7 = $t1._0;
        {
          const board_el = $f7;
          {
            let $eff;
            {
              let $t2_i5995;
              {
                const go_i14779 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
                {
                  const $t5_i14781 = { $: "Nil" };
                  $t2_i5995 = go$apply$0_List_range(go_i14779, 19, $t5_i14781);
                }
              }
              {
                const $t9_i5996 = { $: "$Clo_$lam0_build_board_dom$0_build_board_dom", _0: $lam0_build_board_dom$apply$0_build_board_dom, _1: board_el };
                {
                  const f_i14775 = $t9_i5996;
                  {
                    const go_i14776 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i14775 };
                    $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i14776, $t2_i5995);
                  }
                }
              }
            }
          }
          restart();
          {
            let $eff;
            {
              const $t2 = dom_body();
              {
                const $t3 = { $: "$Clo_$lam0_main$0_main", _0: $lam0_main$apply$0_main };
                $eff = Js$Dom$listen($t2, "keydown", $t3);
              }
            }
          }
          {
            let $eff;
            {
              let level_i5990;
              {
                let $t2_i5989;
                {
                  const $t1_i5988 = state_el();
                  $t2_i5989 = get_int_attr($t1_i5988, "data-lines", 0);
                }
                level_i5990 = TetrisLogic$level_for_lines($t2_i5989);
              }
              {
                let $t3_i5991;
                {
                  let $t2_i14772;
                  {
                    const $t1_i14771 = ((level_i5990 * 40) < 4611686018427387904 && (level_i5990 * 40) >= -4611686018427387904 ? (level_i5990 * 40) : march_int_ovf((level_i5990 * 40), 2));
                    $t2_i14772 = ((500 - $t1_i14771) < 4611686018427387904 && (500 - $t1_i14771) >= -4611686018427387904 ? (500 - $t1_i14771) : march_int_ovf((500 - $t1_i14771), 1));
                  }
                  {
                    const $t1_i5849_i14773 = ($t2_i14772 > 100);
                    if ($t1_i5849_i14773 === true) {
                      $t3_i5991 = $t2_i14772;
                    } else {
                      $t3_i5991 = 100;
                    }
                  }
                }
                {
                  const $t4_i5992 = { $: "$Clo_$lam0_schedule_tick$0_schedule_tick", _0: $lam0_schedule_tick$apply$0_schedule_tick };
                  $eff = Js$Dom$set_timeout($t3_i5991, $t4_i5992);
                }
              }
            }
          }
          {
            const $t4 = Js$Dom$find("restore-trigger");
            switch ($t4.$) {
              case "None": {
                return {  };
                break;
              }
              case "Some": {
                const $f6 = $t4._0;
                {
                  const trigger = $f6;
                  {
                    const $t5 = { $: "$Clo_$lam1_main$1_main", _0: $lam1_main$apply$1_main };
                    return Js$Dom$listen(trigger, "click", $t5);
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
        const $f2 = xs._0;
        const $f3 = xs._1;
        {
          const t = $f3;
          {
            let h;
            h = $f2;
            {
              let $t1;
              $t1 = pred._0(pred, h);
              if ($t1 === true) {
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
        const $f3 = xs._0;
        const $f4 = xs._1;
        {
          const t = $f4;
          {
            const h = $f3;
            {
              let $t1;
              $t1 = pred._0(pred, h);
              if ($t1 === true) {
                {
                  const $trmc4 = { $: "Cons", _0: h, _1: null };
                  List$filter$dps$List_Int$Fn_Int_Bool$List_Int(t, pred, $trmc4);
                  return $trmc4;
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
      const $f1 = opt._0;
      {
        let x;
        x = $f1;
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
      const go_i6313 = { $: "$Clo_go$0_Array_lst_len_List_Int", _0: go$apply$0_Array_lst_len_List_Int };
      n = go$apply$0_Array_lst_len_List_Int(go_i6313, xs, 0);
    }
    {
      const $t1 = (n === 0);
      if ($t1 === true) {
        {
          const $t1_i6310 = { $: "TrieEmpty" };
          {
            const $t2_i6311 = { $: "Nil" };
            return { $: "PVec", _0: 0, _1: 0, _2: $t1_i6310, _3: $t2_i6311 };
          }
        }
      } else {
        {
          let tail_len;
          {
            let $t4;
            {
              let $t3;
              {
                const $t2 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                $t3 = (32 === 0 ? march_div_zero() : ($t2 - $t2 % 32) / 32);
              }
              $t4 = ((32 * $t3) < 4611686018427387904 && (32 * $t3) >= -4611686018427387904 ? (32 * $t3) : march_int_ovf((32 * $t3), 2));
            }
            tail_len = ((n - $t4) < 4611686018427387904 && (n - $t4) >= -4611686018427387904 ? (n - $t4) : march_int_ovf((n - $t4), 1));
          }
          {
            let $p22;
            {
              const $t5 = ((n - tail_len) < 4611686018427387904 && (n - tail_len) >= -4611686018427387904 ? (n - tail_len) : march_int_ovf((n - tail_len), 1));
              {
                const go_i6308 = { $: "$Clo_go$0_Array_lst_split_List_Int_Int", _0: go$apply$0_Array_lst_split_List_Int_Int };
                {
                  const $t11_i6309 = { $: "Nil" };
                  $p22 = go$apply$0_Array_lst_split_List_Int_Int(go_i6308, xs, $t5, $t11_i6309);
                }
              }
            }
            {
              const front = $p22._0;
              {
                const tail = $p22._1;
                {
                  const $t6 = (n === tail_len);
                  if ($t6 === true) {
                    {
                      const $t7 = { $: "TrieEmpty" };
                      {
                        const $rc_3039 = { $: "PVec", _0: n, _1: 0, _2: $t7, _3: tail };
                        return $rc_3039;
                      }
                    }
                  } else {
                    {
                      const up = { $: "$Clo_up$0_Array_from_list_List_Int", _0: up$apply$0_Array_from_list_List_Int };
                      {
                        let $p21;
                        {
                          const $t19 = { $: "$Clo_$lam0_Array_from_list$2_Array_from_list_List_Int", _0: $lam0_Array_from_list$apply$2_Array_from_list_List_Int };
                          {
                            let $t20;
                            {
                              const wrap_i6302 = $t19;
                              {
                                const chunk_i6303 = { $: "$Clo_chunk$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int", _0: chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int, _1: wrap_i6302 };
                                {
                                  const $t17_i6304 = { $: "Nil" };
                                  {
                                    const $t18_i6305 = { $: "Nil" };
                                    $t20 = chunk$apply$0_Array_group32_List_Int_Fn_List_Int_TrieNode_Int(chunk_i6303, front, 0, $t17_i6304, $t18_i6305);
                                  }
                                }
                              }
                            }
                            $p21 = up$apply$0_Array_from_list_List_Int(up, $t20, 0);
                          }
                        }
                        {
                          const root = $p21._0;
                          {
                            const shift = $p21._1;
                            {
                              const $rc_3035 = { $: "PVec", _0: n, _1: shift, _2: root, _3: tail };
                              return $rc_3035;
                            }
                          }
                        }
                      }
                    }
                  }
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
        const $f2 = xs._0;
        const $f3 = xs._1;
        {
          const t = $f3;
          {
            const h = $f2;
            {
              let $t1;
              $t1 = pred._0(pred, h);
              if ($t1 === true) {
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
      const $f6 = v._0;
      const $f7 = v._1;
      const $f8 = v._2;
      const $f9 = v._3;
      {
        const tail = $f9;
        {
          const root = $f8;
          {
            const shift = $f7;
            {
              const n = $f6;
              {
                let $t3;
                {
                  const $t1 = (idx < 0);
                  {
                    const $t2 = (idx >= n);
                    $t3 = ($t1 || $t2);
                  }
                }
                if ($t3 === true) {
                  march_panic_site("stdlib/array.march", 432, 32, 70);
                  return (() => { throw march_panic_error("panic: ", "Array.get: index out of range"); })();
                } else {
                  {
                    let tail_len;
                    {
                      const go_i6315 = { $: "$Clo_go$0_Array_lst_len_List_Int", _0: go$apply$0_Array_lst_len_List_Int };
                      tail_len = go$apply$0_Array_lst_len_List_Int(go_i6315, tail, 0);
                    }
                    {
                      const tail_offset = ((n - tail_len) < 4611686018427387904 && (n - tail_len) >= -4611686018427387904 ? (n - tail_len) : march_int_ovf((n - tail_len), 1));
                      {
                        const $t4 = (idx >= tail_offset);
                        if ($t4 === true) {
                          {
                            const $t5 = ((idx - tail_offset) < 4611686018427387904 && (idx - tail_offset) >= -4611686018427387904 ? (idx - tail_offset) : march_int_ovf((idx - tail_offset), 1));
                            {
                              const $rc_3040 = Array$lst_nth$List_Int$Int(tail, $t5);
                              return $rc_3040;
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
        const $f2 = xs._0;
        const $f3 = xs._1;
        {
          const t = $f3;
          {
            const h = $f2;
            {
              let $t1;
              $t1 = f._0(f, acc, h);
              {
                $tco_a0 = t;
                $tco_a1 = $t1;
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
      const $f8 = v._0;
      const $f9 = v._1;
      const $f10 = v._2;
      const $f11 = v._3;
      {
        const tail = $f11;
        {
          const root = $f10;
          {
            const shift = $f9;
            {
              const n = $f8;
              {
                let $t3;
                {
                  const $t1 = (idx < 0);
                  {
                    const $t2 = (idx >= n);
                    $t3 = ($t1 || $t2);
                  }
                }
                if ($t3 === true) {
                  march_panic_site("stdlib/array.march", 463, 32, 70);
                  return (() => { throw march_panic_error("panic: ", "Array.set: index out of range"); })();
                } else {
                  {
                    let tail_len;
                    {
                      const go_i6328 = { $: "$Clo_go$0_Array_lst_len_List_Int", _0: go$apply$0_Array_lst_len_List_Int };
                      tail_len = go$apply$0_Array_lst_len_List_Int(go_i6328, tail, 0);
                    }
                    {
                      const tail_offset = ((n - tail_len) < 4611686018427387904 && (n - tail_len) >= -4611686018427387904 ? (n - tail_len) : march_int_ovf((n - tail_len), 1));
                      {
                        const $t4 = (idx >= tail_offset);
                        if ($t4 === true) {
                          {
                            const $t5 = ((idx - tail_offset) < 4611686018427387904 && (idx - tail_offset) >= -4611686018427387904 ? (idx - tail_offset) : march_int_ovf((idx - tail_offset), 1));
                            {
                              let $t6;
                              {
                                const rev_onto_i6324 = { $: "$Clo_rev_onto$0_Array_lst_set_List_Int_Int_Int", _0: rev_onto$apply$0_Array_lst_set_List_Int_Int_Int };
                                {
                                  const go_i6325 = { $: "$Clo_go$1_Array_lst_set_List_Int_Int_Int", _0: go$apply$1_Array_lst_set_List_Int_Int_Int, _1: rev_onto_i6324, _2: val };
                                  {
                                    const $t18_i6326 = { $: "Nil" };
                                    $t6 = go$apply$1_Array_lst_set_List_Int_Int_Int(go_i6325, tail, $t5, $t18_i6326);
                                  }
                                }
                              }
                              return { $: "PVec", _0: n, _1: shift, _2: root, _3: $t6 };
                            }
                          }
                        } else {
                          {
                            let $t7;
                            {
                              const $t1_i6320 = { $: "Nil" };
                              $t7 = Array$trie_update_down$TrieNode_Int$Int$List_T_List_TrieNode_Int_Int$Int$Int(root, shift, $t1_i6320, idx, val);
                            }
                            return { $: "PVec", _0: n, _1: shift, _2: $t7, _3: tail };
                          }
                        }
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
      const $f3 = xs._0;
      const $f4 = xs._1;
      {
        const t = $f4;
        {
          const h = $f3;
          {
            let $t1;
            $t1 = f._0(f, h);
            {
              const $trmc4 = { $: "Cons", _0: $t1, _1: null };
              List$map$dps$List_String$Fn_String_Int$List_Int(t, f, $trmc4);
              return $trmc4;
            }
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
        const $f3 = xs._0;
        const $f4 = xs._1;
        {
          const t = $f4;
          {
            const h = $f3;
            {
              const $t1 = (n === 0);
              if ($t1 === true) {
                return h;
              } else {
                {
                  const $t2 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                  {
                    $tco_a0 = t;
                    $tco_a1 = $t2;
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
          const $trmc2 = { $: "Nil" };
          return ($dst._1 = $trmc2, undefined);
        }
        break;
      }
      case "Cons": {
        const $f3 = xs._0;
        const $f4 = xs._1;
        {
          const t = $f4;
          {
            const h = $f3;
            {
              let $t1;
              $t1 = f._0(f, h);
              {
                const $trmc3 = { $: "Cons", _0: $t1, _1: null };
                ($dst._1 = $trmc3, undefined);
                {
                  $tco_a0 = t;
                  $tco_a1 = f;
                  $tco_a2 = $trmc3;
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
          const $trmc1 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc1, undefined);
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
          const $trmc2 = { $: "Nil" };
          return ($dst._1 = $trmc2, undefined);
        }
        break;
      }
      case "Cons": {
        const $f3 = xs._0;
        const $f4 = xs._1;
        {
          const t = $f4;
          {
            const h = $f3;
            {
              let $t1;
              $t1 = f._0(f, h);
              {
                const $trmc3 = { $: "Cons", _0: $t1, _1: null };
                ($dst._1 = $trmc3, undefined);
                {
                  $tco_a0 = t;
                  $tco_a1 = f;
                  $tco_a2 = $trmc3;
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
          const $trmc1 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc1, undefined);
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
        const $f2 = xs._0;
        const $f3 = xs._1;
        {
          const t = $f3;
          {
            const h = $f2;
            {
              const $trmc3 = { $: "Cons", _0: h, _1: null };
              ($dst._1 = $trmc3, undefined);
              {
                $tco_a0 = t;
                $tco_a1 = ys;
                $tco_a2 = $trmc3;
                continue __tco;
              }
            }
          }
        }
        break;
      }
      default: {
        {
          const $trmc1 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc1, undefined);
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
        const $f2 = lst._0;
        const $f3 = lst._1;
        {
          const t = $f3;
          {
            const $t1 = ((acc + 1) < 4611686018427387904 && (acc + 1) >= -4611686018427387904 ? (acc + 1) : march_int_ovf((acc + 1), 0));
            {
              $tco_a0 = t;
              $tco_a1 = $t1;
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
          const $trmc2 = { $: "Nil" };
          return ($dst._1 = $trmc2, undefined);
        }
        break;
      }
      case "Cons": {
        const $f3 = xs._0;
        const $f4 = xs._1;
        {
          const t = $f4;
          {
            const h = $f3;
            {
              let $t1;
              $t1 = pred._0(pred, h);
              if ($t1 === true) {
                {
                  const $trmc3 = { $: "Cons", _0: h, _1: null };
                  ($dst._1 = $trmc3, undefined);
                  {
                    $tco_a0 = t;
                    $tco_a1 = pred;
                    $tco_a2 = $trmc3;
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
          const $trmc1 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc1, undefined);
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
          const $trmc2 = { $: "Nil" };
          return ($dst._1 = $trmc2, undefined);
        }
        break;
      }
      case "Cons": {
        const $f3 = xs._0;
        const $f4 = xs._1;
        {
          const t = $f4;
          {
            const h = $f3;
            {
              let $t1;
              $t1 = f._0(f, h);
              {
                const $trmc3 = { $: "Cons", _0: $t1, _1: null };
                ($dst._1 = $trmc3, undefined);
                {
                  $tco_a0 = t;
                  $tco_a1 = f;
                  $tco_a2 = $trmc3;
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
          const $trmc1 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc1, undefined);
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
        const $f3 = lst._0;
        const $f4 = lst._1;
        {
          const t = $f4;
          {
            let h;
            h = $f3;
            {
              const $t1 = (n === 0);
              if ($t1 === true) {
                return h;
              } else {
                {
                  const $t2 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                  {
                    $tco_a0 = t;
                    $tco_a1 = $t2;
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
        const $f4 = node._0;
        {
          const values = $f4;
          {
            const $t1 = ((idx | 0) === idx && (31 | 0) === 31 ? (idx & 31) : march_int_and(idx, 31));
            {
              const $rc_3110 = Array$lst_nth$List_Int$Int(values, $t1);
              return $rc_3110;
            }
          }
        }
        break;
      }
      case "TrieBranch": {
        const $f5 = node._0;
        {
          const children = $f5;
          {
            let slot;
            {
              const $t1_i7876 = ((idx | 0) === idx && shift >= 0 && shift < 32 ? (idx >> shift) : march_int_shr(idx, shift));
              slot = (($t1_i7876 | 0) === $t1_i7876 && (31 | 0) === 31 ? ($t1_i7876 & 31) : march_int_and($t1_i7876, 31));
            }
            {
              const $t2 = Array$lst_nth$List_TrieNode_Int$Int(children, slot);
              {
                const $t3 = ((shift - 5) < 4611686018427387904 && (shift - 5) >= -4611686018427387904 ? (shift - 5) : march_int_ovf((shift - 5), 1));
                {
                  $tco_a0 = $t2;
                  $tco_a1 = idx;
                  $tco_a2 = $t3;
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
        const $f7 = sub._0;
        const $f8 = sub._1;
        {
          const rest = $f8;
          {
            const x = $f7;
            {
              const $trmc5 = { $: "Cons", _0: x, _1: null };
              List$flat_map_go$dps$List_Int$List_Int$Fn_Int_List_Int$List_Int(rest, lst, f, $trmc5);
              return $trmc5;
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
            const $f3 = lst._0;
            const $f4 = lst._1;
            {
              const t = $f4;
              {
                const h = $f3;
                {
                  let $t2;
                  $t2 = f._0(f, h);
                  {
                    $tco_a0 = $t2;
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
          const $trmc2 = { $: "Nil" };
          return ($dst._1 = $trmc2, undefined);
        }
        break;
      }
      case "Cons": {
        const $f3 = xs._0;
        const $f4 = xs._1;
        {
          const t = $f4;
          {
            const h = $f3;
            {
              let $t1;
              $t1 = f._0(f, h);
              {
                const $trmc3 = { $: "Cons", _0: $t1, _1: null };
                ($dst._1 = $trmc3, undefined);
                {
                  $tco_a0 = t;
                  $tco_a1 = f;
                  $tco_a2 = $trmc3;
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
          const $trmc1 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc1, undefined);
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
      const $f6 = v._0;
      const $f7 = v._1;
      const $f8 = v._2;
      const $f9 = v._3;
      {
        const tail = $f9;
        {
          const root = $f8;
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
        const $f3 = lst._0;
        const $f4 = lst._1;
        {
          const t = $f4;
          {
            const h = $f3;
            {
              const $t1 = (n === 0);
              if ($t1 === true) {
                return h;
              } else {
                {
                  const $t2 = ((n - 1) < 4611686018427387904 && (n - 1) >= -4611686018427387904 ? (n - 1) : march_int_ovf((n - 1), 1));
                  {
                    $tco_a0 = t;
                    $tco_a1 = $t2;
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
        const $f7 = n._0;
        {
          const values = $f7;
          {
            let $t3;
            {
              const $t1 = ((idx | 0) === idx && (31 | 0) === 31 ? (idx & 31) : march_int_and(idx, 31));
              {
                let $t2;
                {
                  const rev_onto_i7942 = { $: "$Clo_rev_onto$0_Array_lst_set_List_Int_Int_Int", _0: rev_onto$apply$0_Array_lst_set_List_Int_Int_Int };
                  {
                    const go_i7943 = { $: "$Clo_go$1_Array_lst_set_List_Int_Int_Int", _0: go$apply$1_Array_lst_set_List_Int_Int_Int, _1: rev_onto_i7942, _2: val };
                    {
                      const $t18_i7944 = { $: "Nil" };
                      $t2 = go$apply$1_Array_lst_set_List_Int_Int_Int(go_i7943, values, $t1, $t18_i7944);
                    }
                  }
                }
                $t3 = { $: "TrieLeaf", _0: $t2 };
              }
            }
            {
              const $rc_3130 = Array$trie_update_up$TrieNode_Int$List_T_List_TrieNode_Int_Int($t3, path);
              return $rc_3130;
            }
          }
        }
        break;
      }
      case "TrieBranch": {
        const $f8 = n._0;
        {
          const children = $f8;
          {
            let slot;
            {
              const $t1_i7947 = ((idx | 0) === idx && s >= 0 && s < 32 ? (idx >> s) : march_int_shr(idx, s));
              slot = (($t1_i7947 | 0) === $t1_i7947 && (31 | 0) === 31 ? ($t1_i7947 & 31) : march_int_and($t1_i7947, 31));
            }
            {
              let child;
              child = Array$lst_nth$List_TrieNode_Int$Int(children, slot);
              {
                const $t4 = ((s - 5) < 4611686018427387904 && (s - 5) >= -4611686018427387904 ? (s - 5) : march_int_ovf((s - 5), 1));
                {
                  const $t5 = { _0: children, _1: slot };
                  {
                    const $t6 = { $: "Cons", _0: $t5, _1: path };
                    {
                      $tco_a0 = child;
                      $tco_a1 = $t4;
                      $tco_a2 = $t6;
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
        const $f7 = sub._0;
        const $f8 = sub._1;
        {
          const rest = $f8;
          {
            const x = $f7;
            {
              const $trmc2 = { $: "Cons", _0: x, _1: null };
              ($dst._1 = $trmc2, undefined);
              {
                $tco_a0 = rest;
                $tco_a1 = lst;
                $tco_a2 = f;
                $tco_a3 = $trmc2;
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
              const $trmc4 = { $: "Nil" };
              return ($dst._1 = $trmc4, undefined);
            }
            break;
          }
          case "Cons": {
            const $f3 = lst._0;
            const $f4 = lst._1;
            {
              const t = $f4;
              {
                const h = $f3;
                {
                  let $t2;
                  $t2 = f._0(f, h);
                  {
                    $tco_a0 = $t2;
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
              const $trmc3 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
              return ($dst._1 = $trmc3, undefined);
            }
          }
        }
        break;
      }
      default: {
        {
          const $trmc1 = (() => { throw march_panic_error("panic: ", "non-exhaustive pattern match"); })();
          return ($dst._1 = $trmc1, undefined);
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
      const $f11 = node._0;
      {
        const values = $f11;
        {
          const go = { $: "$Clo_go$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int", _0: go$apply$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int, _1: f };
          return go$apply$0_Array_trie_fold_List_Int_TrieNode_Int_Fn_List_Int_Int_List_Int(go, acc, values);
        }
      }
      break;
    }
    case "TrieBranch": {
      const $f12 = node._0;
      {
        const children = $f12;
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
        const $f4 = stk._0;
        const $f5 = stk._1;
        {
          const rest = $f5;
          {
            const frame = $f4;
            {
              const children = frame._0;
              {
                const slot = frame._1;
                {
                  let $t2;
                  {
                    let $t1;
                    {
                      const rev_onto_i8016 = { $: "$Clo_rev_onto$0_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int", _0: rev_onto$apply$0_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int };
                      {
                        const go_i8017 = { $: "$Clo_go$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int", _0: go$apply$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int, _1: nd, _2: rev_onto_i8016 };
                        {
                          const $t14_i8018 = { $: "Nil" };
                          $t1 = go$apply$1_Array_lst_replace_nth_List_TrieNode_Int_Int_TrieNode_Int(go_i8017, children, slot, $t14_i8018);
                        }
                      }
                    }
                    $t2 = { $: "TrieBranch", _0: $t1 };
                  }
                  {
                    $tco_a0 = $t2;
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
      const $t6 = { $: "Nil" };
      return Authority$parse_entries(toks, $t6);
    }
  }
}
const $jp1_Authority_parse$apply$0_Authority_parse$clo = { _0: ($_, $clo) => $jp1_Authority_parse$apply$0_Authority_parse($clo) };

function $jp2_Authority_parse$apply$1_Authority_parse($clo) {
  {
    const $jp_clo10 = $clo._1;
    return $jp_clo10._0($jp_clo10);
  }
}
const $jp2_Authority_parse$apply$1_Authority_parse$clo = { _0: ($_, $clo) => $jp2_Authority_parse$apply$1_Authority_parse($clo) };

function $jp3_Authority_parse$apply$2_Authority_parse($clo) {
  {
    const $jp_clo11 = $clo._1;
    return $jp_clo11._0($jp_clo11);
  }
}
const $jp3_Authority_parse$apply$2_Authority_parse$clo = { _0: ($_, $clo) => $jp3_Authority_parse$apply$2_Authority_parse($clo) };

function $jp7_Authority_parse_option$apply$0_Authority_parse_option($clo) {
  {
    const $f26 = $clo._1;
    {
      const name = $clo._2;
      {
        let more;
        more = $f26;
        {
          const $t11 = (name === "methods");
          if ($t11 === true) {
            {
              let $t13;
              {
                const $t12 = { $: "Nil" };
                $t13 = Authority$method_words(more, $t12);
              }
              switch ($t13.$) {
                case "Err": {
                  const $f17 = $t13._0;
                  {
                    const e = $f17;
                    return { $: "Err", _0: e };
                  }
                  break;
                }
                case "Ok": {
                  const $f18 = $t13._0;
                  const $f19 = $f18._0;
                  const $f20 = $f18._1;
                  {
                    const rest = $f20;
                    {
                      const ms = $f19;
                      {
                        let $t15;
                        {
                          let $t14;
                          {
                            const $rc_3150 = march_string_join(ms, ",");
                            $t14 = $rc_3150;
                          }
                          {
                            const $rc_3149 = ("methods=" + $t14);
                            $t15 = $rc_3149;
                          }
                        }
                        {
                          const $t16 = { _0: $t15, _1: rest };
                          return { $: "Ok", _0: $t16 };
                        }
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
              const $t23 = march_string_concat3("`", name, "(...)` takes one quoted string");
              return { $: "Err", _0: $t23 };
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
    const $f8 = $clo._1;
    {
      const $f9 = $clo._2;
      {
        const acc = $clo._3;
        {
          const $jp_clo13 = { $: "$Clo_$jp3_Authority_method_words$1_Authority_method_words", _0: $jp3_Authority_method_words$apply$1_Authority_method_words };
          switch ($f9.$) {
            case "Cons": {
              const $f14 = $f9._0;
              const $f15 = $f9._1;
              if ($f14 === ")") {
                {
                  const rest = $f15;
                  {
                    let m;
                    m = $f8;
                    {
                      let $t3;
                      {
                        const $t1_i8037 = (m !== "");
                        if ($t1_i8037 === true) {
                          $t3 = Authority$all_chars(m, "abcdefghijklmnopqrstuvwxyz_", 0);
                        } else {
                          $t3 = false;
                        }
                      }
                      if ($t3 === true) {
                        {
                          let $t4;
                          $t4 = { $: "Cons", _0: m, _1: acc };
                          {
                            const $t5 = { $: "Nil" };
                            {
                              const $t6 = Authority$rev($t4, $t5);
                              {
                                let $t7;
                                $t7 = { _0: $t6, _1: rest };
                                return { $: "Ok", _0: $t7 };
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
          const $t1 = (i < start);
          if ($t1 === true) {
            return acc;
          } else {
            {
              const $t2 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
              {
                const $t3 = { $: "Cons", _0: i, _1: acc };
                {
                  $tco_a0 = go;
                  $tco_a1 = $t2;
                  $tco_a2 = $t3;
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
        const $f4 = c._0;
        const $f5 = c._1;
        {
          const dy = $f5;
          {
            const dx = $f4;
            {
              const x = ((origin_x + dx) < 4611686018427387904 && (origin_x + dx) >= -4611686018427387904 ? (origin_x + dx) : march_int_ovf((origin_x + dx), 0));
              {
                const y = ((origin_y + dy) < 4611686018427387904 && (origin_y + dy) >= -4611686018427387904 ? (origin_y + dy) : march_int_ovf((origin_y + dy), 0));
                {
                  let $t1;
                  {
                    let $t5_i8937;
                    {
                      let $t3_i8935;
                      {
                        const $t1_i8933 = (x >= 0);
                        if ($t1_i8933 === true) {
                          $t3_i8935 = (x < 10);
                        } else {
                          $t3_i8935 = false;
                        }
                      }
                      {
                        const $t4_i8936 = (y >= 0);
                        $t5_i8937 = ($t3_i8935 && $t4_i8936);
                      }
                    }
                    if ($t5_i8937 === true) {
                      $t1 = (y < 20);
                    } else {
                      $t1 = false;
                    }
                  }
                  if ($t1 === false) {
                    return true;
                  } else if ($t1 === true) {
                    {
                      let $t3;
                      {
                        let $t2;
                        {
                          const $t2_i8930 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
                          $t2 = (($t2_i8930 + x) < 4611686018427387904 && ($t2_i8930 + x) >= -4611686018427387904 ? ($t2_i8930 + x) : march_int_ovf(($t2_i8930 + x), 0));
                        }
                        $t3 = Array$get$PVec_Int$Int(board, $t2);
                      }
                      return ($t3 !== 0);
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
        const $f3 = c._0;
        const $f4 = c._1;
        {
          const dy = $f4;
          {
            const dx = $f3;
            {
              const x = ((origin_x + dx) < 4611686018427387904 && (origin_x + dx) >= -4611686018427387904 ? (origin_x + dx) : march_int_ovf((origin_x + dx), 0));
              {
                const y = ((origin_y + dy) < 4611686018427387904 && (origin_y + dy) >= -4611686018427387904 ? (origin_y + dy) : march_int_ovf((origin_y + dy), 0));
                {
                  let $t1;
                  {
                    let $t5_i8949;
                    {
                      let $t3_i8947;
                      {
                        const $t1_i8945 = (x >= 0);
                        if ($t1_i8945 === true) {
                          $t3_i8947 = (x < 10);
                        } else {
                          $t3_i8947 = false;
                        }
                      }
                      {
                        const $t4_i8948 = (y >= 0);
                        $t5_i8949 = ($t3_i8947 && $t4_i8948);
                      }
                    }
                    if ($t5_i8949 === true) {
                      $t1 = (y < 20);
                    } else {
                      $t1 = false;
                    }
                  }
                  if ($t1 === true) {
                    {
                      let $t2;
                      {
                        const $t2_i8942 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
                        $t2 = (($t2_i8942 + x) < 4611686018427387904 && ($t2_i8942 + x) >= -4611686018427387904 ? ($t2_i8942 + x) : march_int_ovf(($t2_i8942 + x), 0));
                      }
                      return Array$set$PVec_Int$Int$Int(b, $t2, color_idx);
                    }
                  } else if ($t1 === false) {
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
        let $t4;
        {
          let $t3;
          {
            const $t2_i8954 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
            $t3 = (($t2_i8954 + x) < 4611686018427387904 && ($t2_i8954 + x) >= -4611686018427387904 ? ($t2_i8954 + x) : march_int_ovf(($t2_i8954 + x), 0));
          }
          $t4 = Array$get$PVec_Int$Int(board, $t3);
        }
        return ($t4 !== 0);
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
        let $t3;
        {
          const $t2_i8958 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
          $t3 = (($t2_i8958 + x) < 4611686018427387904 && ($t2_i8958 + x) >= -4611686018427387904 ? ($t2_i8958 + x) : march_int_ovf(($t2_i8958 + x), 0));
        }
        return Array$get$PVec_Int$Int(board, $t3);
      }
    }
  }
}
const $lam0_TetrisLogic_row_cells$apply$0_TetrisLogic_row_cells$clo = { _0: ($_, $clo, x) => $lam0_TetrisLogic_row_cells$apply$0_TetrisLogic_row_cells($clo, x) };

function $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines($clo, y) {
  {
    const board = $clo._1;
    {
      let $t2;
      {
        let $t2_i14615;
        {
          const go_i5856_i14612 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
          {
            const $t5_i5858_i14614 = { $: "Nil" };
            $t2_i14615 = go$apply$0_List_range(go_i5856_i14612, 9, $t5_i5858_i14614);
          }
        }
        {
          const $t5_i14616 = { $: "$Clo_$lam0_TetrisLogic_row_full$0_TetrisLogic_row_full", _0: $lam0_TetrisLogic_row_full$apply$0_TetrisLogic_row_full, _1: board, _2: y };
          {
            const $rc_2830_i14617 = List$all$List_Int$Fn_Int_Bool($t2_i14615, $t5_i14616);
            $t2 = $rc_2830_i14617;
          }
        }
      }
      return (!$t2);
    }
  }
}
const $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines$clo = { _0: ($_, $clo, y) => $lam0_TetrisLogic_clear_lines$apply$0_TetrisLogic_clear_lines($clo, y) };

function $lam1_TetrisLogic_clear_lines$apply$1_TetrisLogic_clear_lines($clo, y) {
  {
    const board = $clo._1;
    {
      let $t2_i8962;
      {
        const go_i14784 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
        {
          const $t5_i14786 = { $: "Nil" };
          $t2_i8962 = go$apply$0_List_range(go_i14784, 9, $t5_i14786);
        }
      }
      {
        const $t4_i8963 = { $: "$Clo_$lam0_TetrisLogic_row_cells$0_TetrisLogic_row_cells", _0: $lam0_TetrisLogic_row_cells$apply$0_TetrisLogic_row_cells, _1: board, _2: y };
        {
          const xs_i14850 = $t2_i8962;
          {
            const f_i14851 = $t4_i8963;
            switch (xs_i14850.$) {
              case "Nil": {
                return { $: "Nil" };
                break;
              }
              case "Cons": {
                const $f3_i14852 = xs_i14850._0;
                const $f4_i14853 = xs_i14850._1;
                {
                  const t_i14854 = $f4_i14853;
                  {
                    const h_i14855 = $f3_i14852;
                    {
                      let $t1_i14856;
                      $t1_i14856 = f_i14851._0(f_i14851, h_i14855);
                      {
                        const $trmc4_i14857 = { $: "Cons", _0: $t1_i14856, _1: null };
                        List$map$dps$List_Int$Fn_Int_Int$List_Int(t_i14854, f_i14851, $trmc4_i14857);
                        return $trmc4_i14857;
                      }
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
    let $t2;
    {
      const $rc_3725 = march_string_to_int(x);
      $t2 = $rc_3725;
    }
    {
      const $rc_3724 = Option$unwrap_or$Option_Int$Int($t2, 0);
      return $rc_3724;
    }
  }
}
const $lam0_string_to_int_list$apply$0_string_to_int_list$clo = { _0: ($_, $clo, x) => $lam0_string_to_int_list$apply$0_string_to_int_list($clo, x) };

function $lam0_render_board$apply$0_render_board($clo, y) {
  {
    const board = $clo._1;
    {
      let $t4;
      {
        const go_i8969 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
        {
          const $t5_i8971 = { $: "Nil" };
          $t4 = go$apply$0_List_range(go_i8969, 9, $t5_i8971);
        }
      }
      {
        let $t11;
        $t11 = { $: "$Clo_$lam0__lam0_render_board$1_render_board", _0: $lam0__lam0_render_board$apply$1_render_board, _1: board, _2: y };
        {
          const f_i8965 = $t11;
          {
            const go_i8966 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i8965 };
            return go$apply$0_List_each_List_Int_Fn_Int_T_(go_i8966, $t4);
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
          const $t2_i8976 = ((y * 10) < 4611686018427387904 && (y * 10) >= -4611686018427387904 ? (y * 10) : march_int_ovf((y * 10), 2));
          idx = (($t2_i8976 + x) < 4611686018427387904 && ($t2_i8976 + x) >= -4611686018427387904 ? ($t2_i8976 + x) : march_int_ovf(($t2_i8976 + x), 0));
        }
        {
          let v;
          v = Array$get$PVec_Int$Int(board, idx);
          {
            let id;
            {
              const $t5 = String(x);
              {
                const $t6 = String(y);
                {
                  const $rc_3726 = march_string_concat_n("cell-", $t5, "-", $t6);
                  id = $rc_3726;
                }
              }
            }
            {
              const $t7 = Js$Dom$find(id);
              switch ($t7.$) {
                case "None": {
                  return {  };
                  break;
                }
                case "Some": {
                  const $f10 = $t7._0;
                  {
                    const cell = $f10;
                    {
                      const $t8 = (v === 0);
                      if ($t8 === true) {
                        return Js$Dom$set_style(cell, "background", "");
                      } else if ($t8 === false) {
                        {
                          let $t9;
                          if (v === 1) {
                            $t9 = "#00CED1";
                          } else if (v === 2) {
                            $t9 = "#FFD700";
                          } else if (v === 3) {
                            $t9 = "#9B59B6";
                          } else if (v === 4) {
                            $t9 = "#2ECC71";
                          } else if (v === 5) {
                            $t9 = "#E74C3C";
                          } else if (v === 6) {
                            $t9 = "#3498DB";
                          } else if (v === 7) {
                            $t9 = "#F39C12";
                          } else {
                            $t9 = "";
                          }
                          return Js$Dom$set_style(cell, "background", $t9);
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
        const $f13 = c._0;
        const $f14 = c._1;
        {
          const dy = $f14;
          {
            const dx = $f13;
            {
              const x = ((ox + dx) < 4611686018427387904 && (ox + dx) >= -4611686018427387904 ? (ox + dx) : march_int_ovf((ox + dx), 0));
              {
                const y = ((oy + dy) < 4611686018427387904 && (oy + dy) >= -4611686018427387904 ? (oy + dy) : march_int_ovf((oy + dy), 0));
                {
                  let $t7;
                  {
                    let $t5;
                    {
                      let $t3;
                      {
                        const $t1 = (x >= 0);
                        if ($t1 === true) {
                          $t3 = (x < 10);
                        } else {
                          $t3 = false;
                        }
                      }
                      {
                        const $t4 = (y >= 0);
                        $t5 = ($t3 && $t4);
                      }
                    }
                    if ($t5 === true) {
                      $t7 = (y < 20);
                    } else {
                      $t7 = false;
                    }
                  }
                  if ($t7 === false) {
                    return {  };
                  } else if ($t7 === true) {
                    {
                      let id;
                      {
                        const $t8 = String(x);
                        {
                          const $t9 = String(y);
                          {
                            const $rc_3727 = march_string_concat_n("cell-", $t8, "-", $t9);
                            id = $rc_3727;
                          }
                        }
                      }
                      {
                        const $t10 = Js$Dom$find(id);
                        switch ($t10.$) {
                          case "None": {
                            return {  };
                            break;
                          }
                          case "Some": {
                            const $f12 = $t10._0;
                            {
                              const cell = $f12;
                              {
                                let $t11;
                                switch (piece.$) {
                                  case "I": {
                                    $t11 = "#00CED1";
                                    break;
                                  }
                                  case "O": {
                                    $t11 = "#FFD700";
                                    break;
                                  }
                                  case "T": {
                                    $t11 = "#9B59B6";
                                    break;
                                  }
                                  case "S": {
                                    $t11 = "#2ECC71";
                                    break;
                                  }
                                  case "Z": {
                                    $t11 = "#E74C3C";
                                    break;
                                  }
                                  case "J": {
                                    $t11 = "#3498DB";
                                    break;
                                  }
                                  case "L": {
                                    $t11 = "#F39C12";
                                    break;
                                  }
                                  default: {
                                    throw march_panic_error("panic: ", "non-exhaustive pattern match");
                                    break;
                                  }
                                }
                                return Js$Dom$set_style(cell, "background", $t11);
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
    const $t2 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t2, rot);
      {
        let $t4;
        {
          const $t3 = ((y + 1) < 4611686018427387904 && (y + 1) >= -4611686018427387904 ? (y + 1) : march_int_ovf((y + 1), 0));
          {
            const $t8_i8981 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: x, _3: $t3 };
            $t4 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t8_i8981);
          }
        }
        if ($t4 === true) {
          {
            const $rc_3728 = lock_and_advance(board, piece, rot, x, y, next, score, lines, rng);
            return $rc_3728;
          }
        } else if ($t4 === false) {
          {
            const $t5 = ((y + 1) < 4611686018427387904 && (y + 1) >= -4611686018427387904 ? (y + 1) : march_int_ovf((y + 1), 0));
            return { _0: board, _1: piece, _2: rot, _3: x, _4: $t5, _5: next, _6: score, _7: lines, _8: rng, _9: false };
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
      const $t1_i14619 = is_paused();
      if ($t1_i14619 === true) {
        $eff = {  };
      } else if ($t1_i14619 === false) {
        {
          const $t6_i14620 = { $: "$Clo_$lam0_tick$0_tick", _0: $lam0_tick$apply$0_tick };
          $eff = with_state($t6_i14620);
        }
      } else {
        throw march_panic_error("panic: ", "non-exhaustive pattern match");
      }
    }
  }
  {
    let level_i8984;
    {
      let $t2_i8983;
      {
        const $t1_i8982 = state_el();
        $t2_i8983 = get_int_attr($t1_i8982, "data-lines", 0);
      }
      level_i8984 = TetrisLogic$level_for_lines($t2_i8983);
    }
    {
      let $t3_i8985;
      {
        let $t2_i14789;
        {
          const $t1_i14788 = ((level_i8984 * 40) < 4611686018427387904 && (level_i8984 * 40) >= -4611686018427387904 ? (level_i8984 * 40) : march_int_ovf((level_i8984 * 40), 2));
          $t2_i14789 = ((500 - $t1_i14788) < 4611686018427387904 && (500 - $t1_i14788) >= -4611686018427387904 ? (500 - $t1_i14788) : march_int_ovf((500 - $t1_i14788), 1));
        }
        {
          const $t1_i5849_i14790 = ($t2_i14789 > 100);
          if ($t1_i5849_i14790 === true) {
            $t3_i8985 = $t2_i14789;
          } else {
            $t3_i8985 = 100;
          }
        }
      }
      {
        const $t4_i8986 = { $: "$Clo_$lam0_schedule_tick$0_schedule_tick", _0: $lam0_schedule_tick$apply$0_schedule_tick };
        return Js$Dom$set_timeout($t3_i8985, $t4_i8986);
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
        const $t1 = TetrisLogic$piece_cells(piece);
        {
          const cells = rotate_n($t1, rot);
          {
            let $t4;
            {
              const $t2 = ((x + dx) < 4611686018427387904 && (x + dx) >= -4611686018427387904 ? (x + dx) : march_int_ovf((x + dx), 0));
              {
                const $t3 = ((y + dy) < 4611686018427387904 && (y + dy) >= -4611686018427387904 ? (y + dy) : march_int_ovf((y + dy), 0));
                {
                  const $t8_i8991 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: $t2, _3: $t3 };
                  $t4 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t8_i8991);
                }
              }
            }
            if ($t4 === true) {
              return { _0: board, _1: piece, _2: rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: rng, _9: false };
            } else if ($t4 === false) {
              {
                const $t5 = ((x + dx) < 4611686018427387904 && (x + dx) >= -4611686018427387904 ? (x + dx) : march_int_ovf((x + dx), 0));
                {
                  const $t6 = ((y + dy) < 4611686018427387904 && (y + dy) >= -4611686018427387904 ? (y + dy) : march_int_ovf((y + dy), 0));
                  return { _0: board, _1: piece, _2: rot, _3: $t5, _4: $t6, _5: next, _6: score, _7: lines, _8: rng, _9: false };
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
      const $t1 = ((rot + 1) < 4611686018427387904 && (rot + 1) >= -4611686018427387904 ? (rot + 1) : march_int_ovf((rot + 1), 0));
      new_rot = (4 === 0 ? march_mod_zero() : $t1 % 4);
    }
    {
      const $t2 = TetrisLogic$piece_cells(piece);
      {
        const cells = rotate_n($t2, new_rot);
        {
          let $t3;
          {
            const $t8_i8996 = { $: "$Clo_$lam0_TetrisLogic_collides$0_TetrisLogic_collides", _0: $lam0_TetrisLogic_collides$apply$0_TetrisLogic_collides, _1: board, _2: x, _3: y };
            $t3 = List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t8_i8996);
          }
          if ($t3 === true) {
            return { _0: board, _1: piece, _2: rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: rng, _9: false };
          } else if ($t3 === false) {
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
    const $t1 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t1, rot);
      {
        let final_y;
        final_y = fall_from(board, cells, x, y);
        {
          const $rc_3729 = lock_and_advance(board, piece, rot, x, final_y, next, score, lines, rng);
          return $rc_3729;
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
          let $t4;
          {
            const go_i9002 = { $: "$Clo_go$0_List_range", _0: go$apply$0_List_range, _1: 0 };
            {
              const $t5_i9004 = { $: "Nil" };
              $t4 = go$apply$0_List_range(go_i9002, 9, $t5_i9004);
            }
          }
          {
            let $t8;
            $t8 = { $: "$Clo_$lam0__lam0_build_board_dom$1_build_board_dom", _0: $lam0__lam0_build_board_dom$apply$1_build_board_dom, _1: row, _2: y };
            {
              const f_i8998 = $t8;
              {
                const go_i8999 = { $: "$Clo_go$0_List_each_List_Int_Fn_Int_T_", _0: go$apply$0_List_each_List_Int_Fn_Int_T_, _1: f_i8998 };
                $eff = go$apply$0_List_each_List_Int_Fn_Int_T_(go_i8999, $t4);
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
            let $t7;
            {
              const $t5 = String(x);
              {
                const $t6 = String(y);
                {
                  const $rc_3730 = march_string_concat_n("cell-", $t5, "-", $t6);
                  $t7 = $rc_3730;
                }
              }
            }
            $eff = Js$Dom$set_attr(cell, "id", $t7);
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
          const $t1 = (i <= 0);
          if ($t1 === true) {
            return acc;
          } else {
            {
              const $t2 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
              {
                const $t3 = { $: "Cons", _0: x, _1: acc };
                {
                  $tco_a0 = go;
                  $tco_a1 = $t2;
                  $tco_a2 = $t3;
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
        const $t8 = { $: "$Clo_$lam0_Array_from_list_up$1_Array_from_list_List_Int", _0: $lam0_Array_from_list_up$apply$1_Array_from_list_List_Int };
        {
          let parents;
          {
            const wrap_i9140 = $t8;
            {
              const chunk_i9141 = { $: "$Clo_chunk$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int", _0: chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int, _1: wrap_i9140 };
              {
                const $t17_i9142 = { $: "Nil" };
                {
                  const $t18_i9143 = { $: "Nil" };
                  parents = chunk$apply$0_Array_group32_List_TrieNode_Int_Fn_List_TrieNode_Int_TrieNode_Int(chunk_i9141, nodes, 0, $t17_i9142, $t18_i9143);
                }
              }
            }
          }
          {
            let $t10;
            {
              let $t9;
              {
                const go_i9138 = { $: "$Clo_go$0_Array_lst_len_List_TrieNode_Int", _0: go$apply$0_Array_lst_len_List_TrieNode_Int };
                $t9 = go$apply$0_Array_lst_len_List_TrieNode_Int(go_i9138, parents, 0);
              }
              $t10 = ($t9 === 1);
            }
            if ($t10 === true) {
              switch (parents.$) {
                case "Cons": {
                  const $f14 = parents._0;
                  const $f15 = parents._1;
                  {
                    const root = $f14;
                    {
                      const $t11 = ((shift + 5) < 4611686018427387904 && (shift + 5) >= -4611686018427387904 ? (shift + 5) : march_int_ovf((shift + 5), 0));
                      return { _0: root, _1: $t11 };
                    }
                  }
                  break;
                }
                case "Nil": {
                  {
                    const $t12 = { $: "TrieEmpty" };
                    {
                      const $t13 = ((shift + 5) < 4611686018427387904 && (shift + 5) >= -4611686018427387904 ? (shift + 5) : march_int_ovf((shift + 5), 0));
                      return { _0: $t12, _1: $t13 };
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
                const $t18 = ((shift + 5) < 4611686018427387904 && (shift + 5) >= -4611686018427387904 ? (shift + 5) : march_int_ovf((shift + 5), 0));
                {
                  $tco_a0 = $clo;
                  $tco_a1 = parents;
                  $tco_a2 = $t18;
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
            const $f2 = lst._0;
            const $f3 = lst._1;
            {
              const t = $f3;
              {
                const h = $f2;
                {
                  let $p1;
                  $p1 = f._0(f, h);
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
            const $f2 = lst._0;
            const $f3 = lst._1;
            {
              const t = $f3;
              {
                const h = $f2;
                {
                  let $p1;
                  $p1 = f._0(f, h);
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
          const $f2 = xs._0;
          const $f3 = xs._1;
          {
            const t = $f3;
            {
              const $t1 = ((acc + 1) < 4611686018427387904 && (acc + 1) >= -4611686018427387904 ? (acc + 1) : march_int_ovf((acc + 1), 0));
              {
                $tco_a0 = $clo;
                $tco_a1 = t;
                $tco_a2 = $t1;
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
                  const go_i9223 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                  {
                    const $t6_i9224 = { $: "Nil" };
                    return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9223, out, $t6_i9224);
                  }
                }
                break;
              }
              default: {
                {
                  let $t2;
                  {
                    let $t1;
                    {
                      const go_i9220 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                      {
                        const $t6_i9221 = { $: "Nil" };
                        $t1 = go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9220, cur, $t6_i9221);
                      }
                    }
                    $t2 = wrap._0(wrap, $t1);
                  }
                  {
                    const $t3 = { $: "Cons", _0: $t2, _1: out };
                    {
                      const go_i9217 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                      {
                        const $t6_i9218 = { $: "Nil" };
                        return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9217, $t3, $t6_i9218);
                      }
                    }
                  }
                }
              }
            }
            break;
          }
          case "Cons": {
            const $f13 = ys._0;
            const $f14 = ys._1;
            {
              const t = $f14;
              {
                const h = $f13;
                {
                  const $t5 = (i === 31);
                  if ($t5 === true) {
                    {
                      const $t6 = { $: "Nil" };
                      {
                        let $t9;
                        {
                          const $t7 = { $: "Cons", _0: h, _1: cur };
                          {
                            let $t8;
                            {
                              const go_i9226 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                              {
                                const $t6_i9227 = { $: "Nil" };
                                $t8 = go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9226, $t7, $t6_i9227);
                              }
                            }
                            $t9 = wrap._0(wrap, $t8);
                          }
                        }
                        {
                          const $t10 = { $: "Cons", _0: $t9, _1: out };
                          {
                            $tco_a0 = chunk;
                            $tco_a1 = t;
                            $tco_a2 = 0;
                            $tco_a3 = $t6;
                            $tco_a4 = $t10;
                            continue __tco;
                          }
                        }
                      }
                    }
                  } else {
                    {
                      const $t11 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                      {
                        const $t12 = { $: "Cons", _0: h, _1: cur };
                        {
                          $tco_a0 = chunk;
                          $tco_a1 = t;
                          $tco_a2 = $t11;
                          $tco_a3 = $t12;
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
                  const go_i9235 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                  {
                    const $t6_i9236 = { $: "Nil" };
                    return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9235, out, $t6_i9236);
                  }
                }
                break;
              }
              default: {
                {
                  let $t2;
                  {
                    let $t1;
                    {
                      const go_i9232 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                      {
                        const $t6_i9233 = { $: "Nil" };
                        $t1 = go$apply$0_Array_lst_rev_List_Int(go_i9232, cur, $t6_i9233);
                      }
                    }
                    $t2 = wrap._0(wrap, $t1);
                  }
                  {
                    const $t3 = { $: "Cons", _0: $t2, _1: out };
                    {
                      const go_i9229 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                      {
                        const $t6_i9230 = { $: "Nil" };
                        return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9229, $t3, $t6_i9230);
                      }
                    }
                  }
                }
              }
            }
            break;
          }
          case "Cons": {
            const $f13 = ys._0;
            const $f14 = ys._1;
            {
              const t = $f14;
              {
                const h = $f13;
                {
                  const $t5 = (i === 31);
                  if ($t5 === true) {
                    {
                      const $t6 = { $: "Nil" };
                      {
                        let $t9;
                        {
                          const $t7 = { $: "Cons", _0: h, _1: cur };
                          {
                            let $t8;
                            {
                              const go_i9238 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                              {
                                const $t6_i9239 = { $: "Nil" };
                                $t8 = go$apply$0_Array_lst_rev_List_Int(go_i9238, $t7, $t6_i9239);
                              }
                            }
                            $t9 = wrap._0(wrap, $t8);
                          }
                        }
                        {
                          const $t10 = { $: "Cons", _0: $t9, _1: out };
                          {
                            $tco_a0 = chunk;
                            $tco_a1 = t;
                            $tco_a2 = 0;
                            $tco_a3 = $t6;
                            $tco_a4 = $t10;
                            continue __tco;
                          }
                        }
                      }
                    }
                  } else {
                    {
                      const $t11 = ((i + 1) < 4611686018427387904 && (i + 1) >= -4611686018427387904 ? (i + 1) : march_int_ovf((i + 1), 0));
                      {
                        const $t12 = { $: "Cons", _0: h, _1: cur };
                        {
                          $tco_a0 = chunk;
                          $tco_a1 = t;
                          $tco_a2 = $t11;
                          $tco_a3 = $t12;
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
        const $t1 = (i === 0);
        if ($t1 === true) {
          {
            let $t2;
            {
              const go_i9244 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
              {
                const $t6_i9245 = { $: "Nil" };
                $t2 = go$apply$0_Array_lst_rev_List_Int(go_i9244, acc, $t6_i9245);
              }
            }
            return { _0: $t2, _1: ys };
          }
        } else {
          switch (ys.$) {
            case "Nil": {
              {
                let $t3;
                {
                  const go_i9241 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                  {
                    const $t6_i9242 = { $: "Nil" };
                    $t3 = go$apply$0_Array_lst_rev_List_Int(go_i9241, acc, $t6_i9242);
                  }
                }
                {
                  const $t4 = { $: "Nil" };
                  return { _0: $t3, _1: $t4 };
                }
              }
              break;
            }
            case "Cons": {
              const $f7 = ys._0;
              const $f8 = ys._1;
              {
                const t = $f8;
                {
                  const h = $f7;
                  {
                    const $t5 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
                    {
                      const $t6 = { $: "Cons", _0: h, _1: acc };
                      {
                        $tco_a0 = $clo;
                        $tco_a1 = t;
                        $tco_a2 = $t5;
                        $tco_a3 = $t6;
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
          const $f2 = xs._0;
          const $f3 = xs._1;
          {
            const t = $f3;
            {
              const $t1 = ((acc + 1) < 4611686018427387904 && (acc + 1) >= -4611686018427387904 ? (acc + 1) : march_int_ovf((acc + 1), 0));
              {
                $tco_a0 = $clo;
                $tco_a1 = t;
                $tco_a2 = $t1;
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
          const $f2 = rev_xs._0;
          const $f3 = rev_xs._1;
          {
            const rest = $f3;
            {
              const a = $f2;
              {
                const $t1 = { $: "Cons", _0: a, _1: ys };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = rest;
                  $tco_a2 = $t1;
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
            const $t6 = (i === 0);
            if ($t6 === true) {
              switch (xs.$) {
                case "Nil": {
                  {
                    const go_i9250 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                    {
                      const $t6_i9251 = { $: "Nil" };
                      return go$apply$0_Array_lst_rev_List_Int(go_i9250, acc, $t6_i9251);
                    }
                  }
                  break;
                }
                case "Cons": {
                  const $f8 = xs._0;
                  const $f9 = xs._1;
                  {
                    const t = $f9;
                    {
                      const $t7 = { $: "Cons", _0: v, _1: t };
                      return rev_onto._0(rev_onto, acc, $t7);
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
                    const go_i9247 = { $: "$Clo_go$0_Array_lst_rev_List_Int", _0: go$apply$0_Array_lst_rev_List_Int };
                    {
                      const $t6_i9248 = { $: "Nil" };
                      return go$apply$0_Array_lst_rev_List_Int(go_i9247, acc, $t6_i9248);
                    }
                  }
                  break;
                }
                case "Cons": {
                  const $f14 = xs._0;
                  const $f15 = xs._1;
                  {
                    const t = $f15;
                    {
                      const h = $f14;
                      {
                        const $t12 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
                        {
                          const $t13 = { $: "Cons", _0: h, _1: acc };
                          {
                            $tco_a0 = go;
                            $tco_a1 = t;
                            $tco_a2 = $t12;
                            $tco_a3 = $t13;
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
          const $f2 = xs._0;
          const $f3 = xs._1;
          {
            const t = $f3;
            {
              const h = $f2;
              {
                const $t1 = { $: "Cons", _0: h, _1: acc };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = t;
                  $tco_a2 = $t1;
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
            const $f2 = xs._0;
            const $f3 = xs._1;
            {
              const rest = $f3;
              {
                const x = $f2;
                {
                  let $t1;
                  $t1 = f._0(f, a, x);
                  {
                    $tco_a0 = go;
                    $tco_a1 = $t1;
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
          const $f2 = xs._0;
          const $f3 = xs._1;
          {
            const t = $f3;
            {
              const h = $f2;
              {
                const $t1 = { $: "Cons", _0: h, _1: acc };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = t;
                  $tco_a2 = $t1;
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
            const $f2 = vs._0;
            const $f3 = vs._1;
            {
              const rest = $f3;
              {
                const v = $f2;
                {
                  let $t1;
                  $t1 = f._0(f, a, v);
                  {
                    $tco_a0 = go;
                    $tco_a1 = $t1;
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
            const $f7 = cs._0;
            const $f8 = cs._1;
            {
              const rest = $f8;
              {
                const child = $f7;
                {
                  let $t6;
                  $t6 = Array$trie_fold$List_Int$TrieNode_Int$Fn_List_Int_Int_List_Int(a, child, f);
                  {
                    $tco_a0 = go;
                    $tco_a1 = $t6;
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
          const $f2 = rev_xs._0;
          const $f3 = rev_xs._1;
          {
            const rest = $f3;
            {
              const a = $f2;
              {
                const $t1 = { $: "Cons", _0: a, _1: ys };
                {
                  $tco_a0 = $clo;
                  $tco_a1 = rest;
                  $tco_a2 = $t1;
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
                const go_i9663 = { $: "$Clo_go$0_Array_lst_rev_List_TrieNode_Int", _0: go$apply$0_Array_lst_rev_List_TrieNode_Int };
                {
                  const $t6_i9664 = { $: "Nil" };
                  return go$apply$0_Array_lst_rev_List_TrieNode_Int(go_i9663, acc, $t6_i9664);
                }
              }
              break;
            }
            case "Cons": {
              const $f10 = xs._0;
              const $f11 = xs._1;
              {
                const t = $f11;
                {
                  const h = $f10;
                  {
                    const $t6 = (i === 0);
                    if ($t6 === true) {
                      {
                        let $t7;
                        $t7 = { $: "Cons", _0: node, _1: t };
                        return rev_onto._0(rev_onto, acc, $t7);
                      }
                    } else {
                      {
                        const $t8 = ((i - 1) < 4611686018427387904 && (i - 1) >= -4611686018427387904 ? (i - 1) : march_int_ovf((i - 1), 1));
                        {
                          const $t9 = { $: "Cons", _0: h, _1: acc };
                          {
                            $tco_a0 = go;
                            $tco_a1 = t;
                            $tco_a2 = $t8;
                            $tco_a3 = $t9;
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
