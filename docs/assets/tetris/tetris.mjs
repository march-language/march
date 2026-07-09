import { march_float_to_string, march_int_div, march_int_mod, march_string_byte_length, march_string_join, march_string_split, march_string_to_int, march_unix_time } from "./march_runtime.mjs";

import { march_dom_set_interval as dom_set_interval, march_dom_event_key as dom_event_key, march_dom_add_event_listener as dom_add_event_listener, march_dom_set_style as dom_set_style, march_dom_class_add as dom_class_add, march_dom_set_attribute as dom_set_attribute, march_dom_get_attribute as dom_get_attribute, march_dom_set_text as dom_set_text, march_dom_append_child as dom_append_child, march_dom_create_element as dom_create_element, march_dom_body as dom_body, march_dom_get_element_by_id as dom_get_element_by_id } from "./march_dom.mjs";


const int_to_string   = { _0: ($_, x) => String(x) };
const bool_to_string  = { _0: ($_, x) => String(x) };
const int_to_float    = { _0: ($_, x) => x };
const float_to_int    = { _0: ($_, x) => Math.trunc(x) };
const float_truncate  = { _0: ($_, x) => Math.trunc(x) };
const string_is_empty = { _0: ($_, x) => x === "" };
const not_bool        = { _0: ($_, x) => !x };
const negate_int      = { _0: ($_, x) => -x };
const negate_float    = { _0: ($_, x) => -x };
const float_to_string    = { _0: ($_, x) => march_float_to_string(x) };
const string_length      = { _0: ($_, x) => march_string_byte_length(x) };
const string_byte_length = { _0: ($_, x) => march_string_byte_length(x) };
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
const dom_set_interval$clo = { _0: ($_, p0, p1) => dom_set_interval(p0, p1) };

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

function __eq_WebSocket$Header(a, b) {
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

function __eq_WebSocket$Upgrade(a, b) {
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

function __eq_WebSocket$Conn(a, b) {
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
      if (!__eq_List(a._0, b._0)) return false;
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

function __eq_System$ProcessResult(a, b) {
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

function __eq_SortedSet$Tree(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Leaf": {
      return true;
    }
    case "Node": {
      if (!__eq_Tree(a._0, b._0)) return false;
      if (a._1 !== b._1) return false;
      if (!__eq_Tree(a._2, b._2)) return false;
      if (a._3 !== b._3) return false;
      return true;
    }
  }
  return true;
}

function __eq_RRB$Vec(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Vec": {
      if (!__eq_Array(a._0, b._0)) return false;
      return true;
    }
  }
  return true;
}

function __eq_RRB$Slice(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Slice": {
      if (!__eq_Array(a._0, b._0)) return false;
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

function __eq_NodeIdentity$Identity(a, b) {
  if (a.name !== b.name) return false;
  if (a.node_id !== b.node_id) return false;
  if (a.incarnation !== b.incarnation) return false;
  return true;
}

function __eq_Handshake$Hello(a, b) {
  if (!__eq_NodeIdentity$Identity(a.identity, b.identity)) return false;
  if (a.nonce !== b.nonce) return false;
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

function __eq_Dom$Node(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
  }
  return true;
}

function __eq_Dom$Event(a, b) {
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

function Random$seed(n) {
  {
    const s0 = (() => {
      {
        const max_v_i9555 = (() => {
          {
            const $t15521_i9554 = {  };
            return 9223372036854775807;
          }
        })();
        {
          const x_i9558 = (() => {
            {
              const $t15523_i9557 = (() => {
                {
                  const $t15522_i9556 = (n & max_v_i9555);
                  return ($t15522_i9556 >> 30);
                }
              })();
              return (n ^ $t15523_i9557);
            }
          })();
          {
            const x_i9559 = (x_i9558 * 1234567891011);
            {
              const x_i9562 = (() => {
                {
                  const $t15527_i9561 = (() => {
                    {
                      const $t15526_i9560 = (x_i9559 & max_v_i9555);
                      return ($t15526_i9560 >> 27);
                    }
                  })();
                  return (x_i9559 ^ $t15527_i9561);
                }
              })();
              {
                const x_i9563 = (x_i9562 * 987654321);
                {
                  const x_i9566 = (() => {
                    {
                      const $t15529_i9565 = (() => {
                        {
                          const $t15528_i9564 = (x_i9563 & max_v_i9555);
                          return ($t15528_i9564 >> 31);
                        }
                      })();
                      return (x_i9563 ^ $t15529_i9565);
                    }
                  })();
                  return x_i9566;
                }
              }
            }
          }
        }
      }
    })();
    {
      const s1 = (() => {
        {
          const $t15530 = (n + 1);
          {
            const max_v_i9541 = (() => {
              {
                const $t15521_i9540 = {  };
                return 9223372036854775807;
              }
            })();
            {
              const x_i9544 = (() => {
                {
                  const $t15523_i9543 = (() => {
                    {
                      const $t15522_i9542 = ($t15530 & max_v_i9541);
                      return ($t15522_i9542 >> 30);
                    }
                  })();
                  return ($t15530 ^ $t15523_i9543);
                }
              })();
              {
                const x_i9545 = (x_i9544 * 1234567891011);
                {
                  const x_i9548 = (() => {
                    {
                      const $t15527_i9547 = (() => {
                        {
                          const $t15526_i9546 = (x_i9545 & max_v_i9541);
                          return ($t15526_i9546 >> 27);
                        }
                      })();
                      return (x_i9545 ^ $t15527_i9547);
                    }
                  })();
                  {
                    const x_i9549 = (x_i9548 * 987654321);
                    {
                      const x_i9552 = (() => {
                        {
                          const $t15529_i9551 = (() => {
                            {
                              const $t15528_i9550 = (x_i9549 & max_v_i9541);
                              return ($t15528_i9550 >> 31);
                            }
                          })();
                          return (x_i9549 ^ $t15529_i9551);
                        }
                      })();
                      return x_i9552;
                    }
                  }
                }
              }
            }
          }
        }
      })();
      {
        const s2 = (() => {
          {
            const $t15531 = (n + 2);
            {
              const max_v_i9527 = (() => {
                {
                  const $t15521_i9526 = {  };
                  return 9223372036854775807;
                }
              })();
              {
                const x_i9530 = (() => {
                  {
                    const $t15523_i9529 = (() => {
                      {
                        const $t15522_i9528 = ($t15531 & max_v_i9527);
                        return ($t15522_i9528 >> 30);
                      }
                    })();
                    return ($t15531 ^ $t15523_i9529);
                  }
                })();
                {
                  const x_i9531 = (x_i9530 * 1234567891011);
                  {
                    const x_i9534 = (() => {
                      {
                        const $t15527_i9533 = (() => {
                          {
                            const $t15526_i9532 = (x_i9531 & max_v_i9527);
                            return ($t15526_i9532 >> 27);
                          }
                        })();
                        return (x_i9531 ^ $t15527_i9533);
                      }
                    })();
                    {
                      const x_i9535 = (x_i9534 * 987654321);
                      {
                        const x_i9538 = (() => {
                          {
                            const $t15529_i9537 = (() => {
                              {
                                const $t15528_i9536 = (x_i9535 & max_v_i9527);
                                return ($t15528_i9536 >> 31);
                              }
                            })();
                            return (x_i9535 ^ $t15529_i9537);
                          }
                        })();
                        return x_i9538;
                      }
                    }
                  }
                }
              }
            }
          }
        })();
        {
          const s3 = (() => {
            {
              const $t15532 = (n + 3);
              {
                const max_v_i9513 = (() => {
                  {
                    const $t15521_i9512 = {  };
                    return 9223372036854775807;
                  }
                })();
                {
                  const x_i9516 = (() => {
                    {
                      const $t15523_i9515 = (() => {
                        {
                          const $t15522_i9514 = ($t15532 & max_v_i9513);
                          return ($t15522_i9514 >> 30);
                        }
                      })();
                      return ($t15532 ^ $t15523_i9515);
                    }
                  })();
                  {
                    const x_i9517 = (x_i9516 * 1234567891011);
                    {
                      const x_i9520 = (() => {
                        {
                          const $t15527_i9519 = (() => {
                            {
                              const $t15526_i9518 = (x_i9517 & max_v_i9513);
                              return ($t15526_i9518 >> 27);
                            }
                          })();
                          return (x_i9517 ^ $t15527_i9519);
                        }
                      })();
                      {
                        const x_i9521 = (x_i9520 * 987654321);
                        {
                          const x_i9524 = (() => {
                            {
                              const $t15529_i9523 = (() => {
                                {
                                  const $t15528_i9522 = (x_i9521 & max_v_i9513);
                                  return ($t15528_i9522 >> 31);
                                }
                              })();
                              return (x_i9521 ^ $t15529_i9523);
                            }
                          })();
                          return x_i9524;
                        }
                      }
                    }
                  }
                }
              }
            }
          })();
          {
            const s0_nz = (() => {
              {
                const $t15539 = (() => {
                  {
                    const $t15537 = (() => {
                      {
                        const $t15535 = (() => {
                          {
                            const $t15533 = (s0 === 0);
                            {
                              const $t15534 = (s1 === 0);
                              return ($t15533 && $t15534);
                            }
                          }
                        })();
                        {
                          const $t15536 = (s2 === 0);
                          return ($t15535 && $t15536);
                        }
                      }
                    })();
                    {
                      const $t15538 = (s3 === 0);
                      return ($t15537 && $t15538);
                    }
                  }
                })();
                if ($t15539 === true) {
                  return 1;
                } else {
                  return s0;
                }
              }
            })();
            return ({ s0: s0_nz, s1: s1, s2: s2, s3: s3 });
          }
        }
      }
    }
  }
}
const Random$seed$clo = { _0: ($_, n) => Random$seed(n) };

function Random$next_raw(rng) {
  {
    const result = (() => {
      {
        const $t15542 = (() => {
          {
            const $t15541 = (() => {
              {
                const $t15540 = rng.s1;
                return ($t15540 * 5);
              }
            })();
            {
              const $t15518_i1502 = ($t15541 << 7);
              {
                const $t15520_i1504 = ($t15541 >> 56);
                return ($t15518_i1502 | $t15520_i1504);
              }
            }
          }
        })();
        return ($t15542 * 9);
      }
    })();
    {
      const t = (() => {
        {
          const $t15543 = rng.s1;
          return ($t15543 << 17);
        }
      })();
      {
        const s2 = (() => {
          {
            const $t15544 = rng.s2;
            {
              const $t15545 = rng.s0;
              return ($t15544 ^ $t15545);
            }
          }
        })();
        {
          const s3 = (() => {
            {
              const $t15546 = rng.s3;
              {
                const $t15547 = rng.s1;
                return ($t15546 ^ $t15547);
              }
            }
          })();
          {
            const s1 = (() => {
              {
                const $t15548 = rng.s1;
                return ($t15548 ^ s2);
              }
            })();
            {
              const s0 = (() => {
                {
                  const $t15549 = rng.s0;
                  return ($t15549 ^ s3);
                }
              })();
              {
                const s2b = (s2 ^ t);
                {
                  const s3b = (() => {
                    {
                      const $t15518_i1497 = (s3 << 45);
                      {
                        const $t15520_i1499 = (s3 >> 18);
                        return ($t15518_i1497 | $t15520_i1499);
                      }
                    }
                  })();
                  {
                    const $t15550 = ({ s0: s0, s1: s1, s2: s2b, s3: s3b });
                    return { _0: result, _1: $t15550 };
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
const Random$next_raw$clo = { _0: ($_, rng) => Random$next_raw(rng) };

function Random$range(rng, lo, hi) {
  {
    const $p15561 = Random$next_raw(rng);
    {
      const raw = $p15561._0;
      {
        const rng2 = $p15561._1;
        {
          const max_v = (() => {
            {
              const $t15556 = {  };
              return 9223372036854775807;
            }
          })();
          {
            const pos = (raw & max_v);
            {
              const $t15560 = (() => {
                {
                  const $t15559 = (() => {
                    {
                      const $t15558 = (() => {
                        {
                          const $t15557 = (hi - lo);
                          return ($t15557 + 1);
                        }
                      })();
                      return march_int_mod(pos, $t15558);
                    }
                  })();
                  return (lo + $t15559);
                }
              })();
              return { _0: $t15560, _1: rng2 };
            }
          }
        }
      }
    }
  }
}
const Random$range$clo = { _0: ($_, rng, lo, hi) => Random$range(rng, lo, hi) };

function Random$int(lo, hi) {
  {
    const rng = (() => {
      {
        const $t15564 = (() => {
          {
            const $t15563 = (() => {
              {
                const $t15562 = {  };
                return march_unix_time();
              }
            })();
            return Math.trunc($t15563);
          }
        })();
        return Random$seed($t15564);
      }
    })();
    {
      const $p15565 = Random$range(rng, lo, hi);
      {
        const n = $p15565._0;
        return n;
      }
    }
  }
}
const Random$int$clo = { _0: ($_, lo, hi) => Random$int(lo, hi) };

function Dom$find(id) {
  {
    const $rc_744 = dom_get_element_by_id$clo._0(dom_get_element_by_id$clo, id);
    return $rc_744;
  }
}
const Dom$find$clo = { _0: ($_, id) => Dom$find(id) };

function Dom$create(tag) {
  {
    const $rc_747 = dom_create_element$clo._0(dom_create_element$clo, tag);
    return $rc_747;
  }
}
const Dom$create$clo = { _0: ($_, tag) => Dom$create(tag) };

function Dom$append(parent, child) {
  {
    const $rc_749 = dom_append_child$clo._0(dom_append_child$clo, parent, child);
    return $rc_749;
  }
}
const Dom$append$clo = { _0: ($_, parent, child) => Dom$append(parent, child) };

function Dom$set_text(el, text) {
  {
    const $rc_757 = dom_set_text$clo._0(dom_set_text$clo, el, text);
    return $rc_757;
  }
}
const Dom$set_text$clo = { _0: ($_, el, text) => Dom$set_text(el, text) };

function Dom$get_attr(el, name) {
  {
    const $rc_760 = dom_get_attribute$clo._0(dom_get_attribute$clo, el, name);
    return $rc_760;
  }
}
const Dom$get_attr$clo = { _0: ($_, el, name) => Dom$get_attr(el, name) };

function Dom$set_attr(el, name, val) {
  {
    const $rc_761 = dom_set_attribute$clo._0(dom_set_attribute$clo, el, name, val);
    return $rc_761;
  }
}
const Dom$set_attr$clo = { _0: ($_, el, name, val) => Dom$set_attr(el, name, val) };

function Dom$add_class(el, cls) {
  {
    const $rc_764 = dom_class_add$clo._0(dom_class_add$clo, el, cls);
    return $rc_764;
  }
}
const Dom$add_class$clo = { _0: ($_, el, cls) => Dom$add_class(el, cls) };

function Dom$set_style(el, prop, val) {
  {
    const $rc_768 = dom_set_style$clo._0(dom_set_style$clo, el, prop, val);
    return $rc_768;
  }
}
const Dom$set_style$clo = { _0: ($_, el, prop, val) => Dom$set_style(el, prop, val) };

function Dom$listen(el, event, handler) {
  {
    const $rc_772 = dom_add_event_listener$clo._0(dom_add_event_listener$clo, el, event, handler);
    return $rc_772;
  }
}
const Dom$listen$clo = { _0: ($_, el, event, handler) => Dom$listen(el, event, handler) };

function Dom$event_key(ev) {
  {
    const $rc_776 = dom_event_key$clo._0(dom_event_key$clo, ev);
    return $rc_776;
  }
}
const Dom$event_key$clo = { _0: ($_, ev) => Dom$event_key(ev) };

function Dom$set_interval(ms, cb) {
  return dom_set_interval$clo._0(dom_set_interval$clo, ms, cb);
}
const Dom$set_interval$clo = { _0: ($_, ms, cb) => Dom$set_interval(ms, cb) };

function TetrisLogic$piece_cells(p) {
  switch (p.$) {
    case "I": {
      {
        const $t27325 = { _0: 0, _1: 1 };
        {
          const $t27326 = { _0: 1, _1: 1 };
          {
            const $t27327 = { _0: 2, _1: 1 };
            {
              const $t27328 = { _0: 3, _1: 1 };
              {
                const $t27329 = { $: "Nil" };
                {
                  const $t27330 = { $: "Cons", _0: $t27328, _1: $t27329 };
                  {
                    const $t27331 = { $: "Cons", _0: $t27327, _1: $t27330 };
                    {
                      const $t27332 = { $: "Cons", _0: $t27326, _1: $t27331 };
                      return { $: "Cons", _0: $t27325, _1: $t27332 };
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    case "O": {
      {
        const $t27333 = { _0: 1, _1: 1 };
        {
          const $t27334 = { _0: 2, _1: 1 };
          {
            const $t27335 = { _0: 1, _1: 2 };
            {
              const $t27336 = { _0: 2, _1: 2 };
              {
                const $t27337 = { $: "Nil" };
                {
                  const $t27338 = { $: "Cons", _0: $t27336, _1: $t27337 };
                  {
                    const $t27339 = { $: "Cons", _0: $t27335, _1: $t27338 };
                    {
                      const $t27340 = { $: "Cons", _0: $t27334, _1: $t27339 };
                      return { $: "Cons", _0: $t27333, _1: $t27340 };
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    case "T": {
      {
        const $t27341 = { _0: 1, _1: 1 };
        {
          const $t27342 = { _0: 0, _1: 2 };
          {
            const $t27343 = { _0: 1, _1: 2 };
            {
              const $t27344 = { _0: 2, _1: 2 };
              {
                const $t27345 = { $: "Nil" };
                {
                  const $t27346 = { $: "Cons", _0: $t27344, _1: $t27345 };
                  {
                    const $t27347 = { $: "Cons", _0: $t27343, _1: $t27346 };
                    {
                      const $t27348 = { $: "Cons", _0: $t27342, _1: $t27347 };
                      return { $: "Cons", _0: $t27341, _1: $t27348 };
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    case "S": {
      {
        const $t27349 = { _0: 1, _1: 1 };
        {
          const $t27350 = { _0: 2, _1: 1 };
          {
            const $t27351 = { _0: 0, _1: 2 };
            {
              const $t27352 = { _0: 1, _1: 2 };
              {
                const $t27353 = { $: "Nil" };
                {
                  const $t27354 = { $: "Cons", _0: $t27352, _1: $t27353 };
                  {
                    const $t27355 = { $: "Cons", _0: $t27351, _1: $t27354 };
                    {
                      const $t27356 = { $: "Cons", _0: $t27350, _1: $t27355 };
                      return { $: "Cons", _0: $t27349, _1: $t27356 };
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    case "Z": {
      {
        const $t27357 = { _0: 0, _1: 1 };
        {
          const $t27358 = { _0: 1, _1: 1 };
          {
            const $t27359 = { _0: 1, _1: 2 };
            {
              const $t27360 = { _0: 2, _1: 2 };
              {
                const $t27361 = { $: "Nil" };
                {
                  const $t27362 = { $: "Cons", _0: $t27360, _1: $t27361 };
                  {
                    const $t27363 = { $: "Cons", _0: $t27359, _1: $t27362 };
                    {
                      const $t27364 = { $: "Cons", _0: $t27358, _1: $t27363 };
                      return { $: "Cons", _0: $t27357, _1: $t27364 };
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    case "J": {
      {
        const $t27365 = { _0: 0, _1: 1 };
        {
          const $t27366 = { _0: 0, _1: 2 };
          {
            const $t27367 = { _0: 1, _1: 2 };
            {
              const $t27368 = { _0: 2, _1: 2 };
              {
                const $t27369 = { $: "Nil" };
                {
                  const $t27370 = { $: "Cons", _0: $t27368, _1: $t27369 };
                  {
                    const $t27371 = { $: "Cons", _0: $t27367, _1: $t27370 };
                    {
                      const $t27372 = { $: "Cons", _0: $t27366, _1: $t27371 };
                      return { $: "Cons", _0: $t27365, _1: $t27372 };
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    case "L": {
      {
        const $t27373 = { _0: 2, _1: 1 };
        {
          const $t27374 = { _0: 0, _1: 2 };
          {
            const $t27375 = { _0: 1, _1: 2 };
            {
              const $t27376 = { _0: 2, _1: 2 };
              {
                const $t27377 = { $: "Nil" };
                {
                  const $t27378 = { $: "Cons", _0: $t27376, _1: $t27377 };
                  {
                    const $t27379 = { $: "Cons", _0: $t27375, _1: $t27378 };
                    {
                      const $t27380 = { $: "Cons", _0: $t27374, _1: $t27379 };
                      return { $: "Cons", _0: $t27373, _1: $t27380 };
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const TetrisLogic$piece_cells$clo = { _0: ($_, p) => TetrisLogic$piece_cells(p) };

function TetrisLogic$rotate_cell(c) {
  const $f27382 = c._0;
  const $f27383 = c._1;
  {
    const y = (() => {
      return $f27383;
    })();
    {
      const x = (() => {
        return $f27382;
      })();
      {
        const $t27381 = (3 - y);
        return { _0: $t27381, _1: x };
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
        const go_i3645 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
        {
          const $t177_i3647 = { $: "Nil" };
          return go$apply$0(go_i3645, 19, $t177_i3647);
        }
      }
    })();
    {
      const $t27432 = (() => {
        return { $: "$Clo_$lam27430$3677", _0: $lam27430$apply$3677, _1: board };
      })();
      {
        const kept_rows = (() => {
          {
            const pred_i3640 = $t27432;
            {
              const go_i3641 = { $: "$Clo_go$4561", _0: go$apply$4561, _1: pred_i3640 };
              {
                const $t299_i3642 = { $: "Nil" };
                return go$apply$4561(go_i3641, rows, $t299_i3642);
              }
            }
          }
        })();
        {
          const cleared = (() => {
            {
              const $t27434 = (() => {
                {
                  const go_i3638 = { $: "$Clo_go$4589", _0: go$apply$4589 };
                  return go$apply$4589(go_i3638, kept_rows, 0);
                }
              })();
              return (20 - $t27434);
            }
          })();
          {
            const $t27436 = { $: "$Clo_$lam27435$3678", _0: $lam27435$apply$3678, _1: board };
            {
              const kept_cells = (() => {
                {
                  const f_i3633 = $t27436;
                  {
                    const prepend_reversed_i3634 = { $: "$Clo_prepend_reversed$4676", _0: prepend_reversed$apply$4676 };
                    {
                      const go_i3635 = { $: "$Clo_go$4678", _0: go$apply$4678, _1: f_i3633, _2: prepend_reversed_i3634 };
                      {
                        const $t290_i3636 = { $: "Nil" };
                        return go$apply$4678(go_i3635, kept_rows, $t290_i3636);
                      }
                    }
                  }
                }
              })();
              {
                const $t27438 = (cleared * 10);
                {
                  const blank_cells = (() => {
                    {
                      const go_i3630 = { $: "$Clo_go$4267", _0: go$apply$4267, _1: 0 };
                      {
                        const $t172_i3631 = { $: "Nil" };
                        return go$apply$4267(go_i3630, $t27438, $t172_i3631);
                      }
                    }
                  })();
                  {
                    const new_board = (() => {
                      {
                        const $t27439 = (() => {
                          {
                            const go_i9319 = { $: "$Clo_go$4455", _0: go$apply$4455 };
                            {
                              const $t258_i9322 = (() => {
                                {
                                  const go_i3959_i9320 = { $: "$Clo_go$3740", _0: go$apply$3740 };
                                  {
                                    const $t250_i3960_i9321 = { $: "Nil" };
                                    return go$apply$3740(go_i3959_i9320, blank_cells, $t250_i3960_i9321);
                                  }
                                }
                              })();
                              return go$apply$4455(go_i9319, $t258_i9322, kept_cells);
                            }
                          }
                        })();
                        {
                          const go_i9313 = { $: "$Clo_go$4666", _0: go$apply$4666 };
                          {
                            const $t7129_i9316 = (() => {
                              {
                                const $t6923_i4058_i9314 = { $: "TrieEmpty" };
                                {
                                  const $t6924_i4059_i9315 = { $: "Nil" };
                                  return { $: "PVec", _0: 0, _1: 0, _2: $t6923_i4058_i9314, _3: $t6924_i4059_i9315 };
                                }
                              }
                            })();
                            return go$apply$4666(go_i9313, $t27439, $t7129_i9316);
                          }
                        }
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

function TetrisLogic$level_for_lines(total_lines) {
  return (total_lines / 10);
}
const TetrisLogic$level_for_lines$clo = { _0: ($_, total_lines) => TetrisLogic$level_for_lines(total_lines) };

function state_el() {
  {
    const $t27476 = Dom$find("game-state");
    switch ($t27476.$) {
      case "Some": {
        const $f27477 = $t27476._0;
        {
          const el = $f27477;
          return el;
        }
      }
      case "None": {
        return (() => { throw new Error("Tetris: #game-state element missing"); })();
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
    const $t27478 = Dom$get_attr(el, name);
    switch ($t27478.$) {
      case "Some": {
        const $f27480 = $t27478._0;
        {
          const s = $f27480;
          {
            const $t27479 = (() => {
              {
                const $rc_781 = march_string_to_int(s);
                return $rc_781;
              }
            })();
            return Option$unwrap_or$Option_Int$Int($t27479, _default);
          }
        }
      }
      case "None": {
        return _default;
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
    const $t27481 = Dom$get_attr(el, name);
    switch ($t27481.$) {
      case "Some": {
        const $f27482 = $t27481._0;
        {
          const s = $f27482;
          return s;
        }
      }
      case "None": {
        return _default;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const get_str_attr$clo = { _0: ($_, el, name, _default) => get_str_attr(el, name, _default) };

function rotate_n(cells, n) {
  {
    const $t27483 = (n <= 0);
    if ($t27483 === true) {
      return cells;
    } else {
      return (() => {
        {
          const $t27484 = (() => {
            {
              const f_i3611_i9324 = TetrisLogic$rotate_cell$clo;
              {
                const go_i3612_i9325 = { $: "$Clo_go$4668", _0: go$apply$4668, _1: f_i3611_i9324 };
                {
                  const $t267_i3613_i9326 = { $: "Nil" };
                  return go$apply$4668(go_i3612_i9325, cells, $t267_i3613_i9326);
                }
              }
            }
          })();
          {
            const $t27485 = (n - 1);
            return rotate_n($t27484, $t27485);
          }
        }
      })();
    }
  }
}
const rotate_n$clo = { _0: ($_, cells, n) => rotate_n(cells, n) };

function set_text_if_found(id, text) {
  {
    const $t27527 = Dom$find(id);
    switch ($t27527.$) {
      case "None": {
        return {  };
      }
      case "Some": {
        const $f27528 = $t27527._0;
        {
          const el = $f27528;
          return Dom$set_text(el, text);
        }
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
          const $t27529 = (() => {
            return get_str_attr(el, "data-over", "false");
          })();
          return ($t27529 === "true");
        }
      })();
      if (over === true) {
        return {  };
      } else {
        return (() => {
          {
            const board = (() => {
              {
                const $t27530 = (() => {
                  return get_str_attr(el, "data-board", "");
                })();
                {
                  const $t27531 = (() => {
                    {
                      const $rc_789 = (() => {
                        {
                          const $t27445_i9365 = march_string_split($t27530, ",");
                          {
                            const $t27448_i9366 = { $: "$Clo_$lam27446$3680", _0: $lam27446$apply$3680 };
                            {
                              const f_i3655_i9367 = $t27448_i9366;
                              {
                                const go_i3656_i9368 = { $: "$Clo_go$4680", _0: go$apply$4680, _1: f_i3655_i9367 };
                                {
                                  const $t267_i3657_i9369 = { $: "Nil" };
                                  return go$apply$4680(go_i3656_i9368, $t27445_i9365, $t267_i3657_i9369);
                                }
                              }
                            }
                          }
                        }
                      })();
                      return $rc_789;
                    }
                  })();
                  {
                    const go_i9360 = { $: "$Clo_go$4666", _0: go$apply$4666 };
                    {
                      const $t7129_i9363 = (() => {
                        {
                          const $t6923_i4058_i9361 = { $: "TrieEmpty" };
                          {
                            const $t6924_i4059_i9362 = { $: "Nil" };
                            return { $: "PVec", _0: 0, _1: 0, _2: $t6923_i4058_i9361, _3: $t6924_i4059_i9362 };
                          }
                        }
                      })();
                      return go$apply$4666(go_i9360, $t27531, $t7129_i9363);
                    }
                  }
                }
              }
            })();
            {
              const piece = (() => {
                {
                  const $t27532 = (() => {
                    return get_str_attr(el, "data-piece", "I");
                  })();
                  {
                    let $rc_788;
                    if ($t27532 === "I") {
                      $rc_788 = { $: "I" };
                    } else if ($t27532 === "O") {
                      $rc_788 = { $: "O" };
                    } else if ($t27532 === "T") {
                      $rc_788 = { $: "T" };
                    } else if ($t27532 === "S") {
                      $rc_788 = { $: "S" };
                    } else if ($t27532 === "Z") {
                      $rc_788 = { $: "Z" };
                    } else if ($t27532 === "J") {
                      $rc_788 = { $: "J" };
                    } else {
                      $rc_788 = { $: "L" };
                    }
                    return $rc_788;
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
                          const $t27533 = (() => {
                            return get_str_attr(el, "data-next", "O");
                          })();
                          {
                            let $rc_787;
                            if ($t27533 === "I") {
                              $rc_787 = { $: "I" };
                            } else if ($t27533 === "O") {
                              $rc_787 = { $: "O" };
                            } else if ($t27533 === "T") {
                              $rc_787 = { $: "T" };
                            } else if ($t27533 === "S") {
                              $rc_787 = { $: "S" };
                            } else if ($t27533 === "Z") {
                              $rc_787 = { $: "Z" };
                            } else if ($t27533 === "J") {
                              $rc_787 = { $: "J" };
                            } else {
                              $rc_787 = { $: "L" };
                            }
                            return $rc_787;
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
                            const $t27534 = f._0(f, board, piece, rot, x, y, next, score, lines);
                            const $f27553 = $t27534._0;
                            const $f27554 = $t27534._1;
                            const $f27555 = $t27534._2;
                            const $f27556 = $t27534._3;
                            const $f27557 = $t27534._4;
                            const $f27558 = $t27534._5;
                            const $f27559 = $t27534._6;
                            const $f27560 = $t27534._7;
                            const $f27561 = $t27534._8;
                            {
                              const over2 = (() => {
                                return $f27561;
                              })();
                              {
                                const lines2 = (() => {
                                  return $f27560;
                                })();
                                {
                                  const score2 = (() => {
                                    return $f27559;
                                  })();
                                  {
                                    const next2 = (() => {
                                      return $f27558;
                                    })();
                                    {
                                      const y2 = (() => {
                                        return $f27557;
                                      })();
                                      {
                                        const x2 = (() => {
                                          return $f27556;
                                        })();
                                        {
                                          const rot2 = (() => {
                                            return $f27555;
                                          })();
                                          {
                                            const piece2 = (() => {
                                              return $f27554;
                                            })();
                                            {
                                              const board2 = (() => {
                                                return $f27553;
                                              })();
                                              (() => {
                                                {
                                                  const $t27488_i9355 = (() => {
                                                    {
                                                      const go_i3691_i9352 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
                                                      {
                                                        const $t177_i3693_i9354 = { $: "Nil" };
                                                        return go$apply$0(go_i3691_i9352, 19, $t177_i3693_i9354);
                                                      }
                                                    }
                                                  })();
                                                  {
                                                    const $t27502_i9356 = { $: "$Clo_$lam27489$3687", _0: $lam27489$apply$3687, _1: board2 };
                                                    {
                                                      const f_i3687_i9357 = $t27502_i9356;
                                                      {
                                                        const go_i3688_i9358 = { $: "$Clo_go$4683", _0: go$apply$4683, _1: f_i3687_i9357 };
                                                        return go$apply$4683(go_i3688_i9358, $t27488_i9355);
                                                      }
                                                    }
                                                  }
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27535 = (!over2);
                                                  if ($t27535 === true) {
                                                    return (() => {
                                                      {
                                                        const base_cells_i9346 = TetrisLogic$piece_cells(piece2);
                                                        {
                                                          const rotated_i9347 = rotate_n(base_cells_i9346, rot2);
                                                          {
                                                            const $t27526_i9348 = { $: "$Clo_$lam27503$3689", _0: $lam27503$apply$3689, _1: x2, _2: y2, _3: piece2 };
                                                            {
                                                              const f_i3695_i9349 = $t27526_i9348;
                                                              {
                                                                const go_i3696_i9350 = { $: "$Clo_go$4685", _0: go$apply$4685, _1: f_i3695_i9349 };
                                                                return go$apply$4685(go_i3696_i9350, rotated_i9347);
                                                              }
                                                            }
                                                          }
                                                        }
                                                      }
                                                    })();
                                                  } else {
                                                    return {  };
                                                  }
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27537 = (() => {
                                                    {
                                                      const $t27536 = String(score2);
                                                      {
                                                        const $rc_786 = ("Score: " + $t27536);
                                                        return $rc_786;
                                                      }
                                                    }
                                                  })();
                                                  return set_text_if_found("score", $t27537);
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27540 = (() => {
                                                    {
                                                      const $t27539 = (() => {
                                                        {
                                                          const $t27538 = TetrisLogic$level_for_lines(lines2);
                                                          return String($t27538);
                                                        }
                                                      })();
                                                      {
                                                        const $rc_785 = ("Level: " + $t27539);
                                                        return $rc_785;
                                                      }
                                                    }
                                                  })();
                                                  return set_text_if_found("level", $t27540);
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27542 = (() => {
                                                    {
                                                      let $t27541;
                                                      switch (next2.$) {
                                                        case "I": {
                                                          $t27541 = "I";
                                                          break;
                                                        }
                                                        case "O": {
                                                          $t27541 = "O";
                                                          break;
                                                        }
                                                        case "T": {
                                                          $t27541 = "T";
                                                          break;
                                                        }
                                                        case "S": {
                                                          $t27541 = "S";
                                                          break;
                                                        }
                                                        case "Z": {
                                                          $t27541 = "Z";
                                                          break;
                                                        }
                                                        case "J": {
                                                          $t27541 = "J";
                                                          break;
                                                        }
                                                        case "L": {
                                                          $t27541 = "L";
                                                          break;
                                                        }
                                                        default: {
                                                          $t27541 = (() => { throw new Error("non-exhaustive pattern match"); })();
                                                          break;
                                                        }
                                                      }
                                                      {
                                                        const $rc_784 = ("Next: " + $t27541);
                                                        return $rc_784;
                                                      }
                                                    }
                                                  })();
                                                  return set_text_if_found("next", $t27542);
                                                }
                                              })();
                                              (() => {
                                                if (over2 === true) {
                                                  return set_text_if_found("game-over", "Game Over — press R to restart");
                                                } else {
                                                  return set_text_if_found("game-over", "");
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27544 = (() => {
                                                    {
                                                      const $t27543 = (() => {
                                                        {
                                                          const $t7119_i9336 = { $: "Nil" };
                                                          {
                                                            const $t7121_i9337 = { $: "$Clo_$lam7120$4687", _0: $lam7120$apply$4687 };
                                                            {
                                                              const rev_i9338 = Array$fold_left$PVec_Int$List_V__22334$Fn_List_V__22335_V__22335_List_V__22335(board2, $t7119_i9336, $t7121_i9337);
                                                              {
                                                                const go_i4069_i9339 = { $: "$Clo_go$5110", _0: go$apply$5110 };
                                                                {
                                                                  const $t6726_i4070_i9340 = { $: "Nil" };
                                                                  return go$apply$5110(go_i4069_i9339, rev_i9338, $t6726_i4070_i9340);
                                                                }
                                                              }
                                                            }
                                                          }
                                                        }
                                                      })();
                                                      {
                                                        const $t27443_i9330 = { $: "$Clo_$lam27442$3679", _0: $lam27442$apply$3679 };
                                                        {
                                                          const $t27444_i9334 = (() => {
                                                            {
                                                              const f_i3651_i9331 = $t27443_i9330;
                                                              {
                                                                const go_i3652_i9332 = { $: "$Clo_go$4101", _0: go$apply$4101, _1: f_i3651_i9331 };
                                                                {
                                                                  const $t267_i3653_i9333 = { $: "Nil" };
                                                                  return go$apply$4101(go_i3652_i9332, $t27543, $t267_i3653_i9333);
                                                                }
                                                              }
                                                            }
                                                          })();
                                                          return march_string_join($t27444_i9334, ",");
                                                        }
                                                      }
                                                    }
                                                  })();
                                                  return Dom$set_attr(el, "data-board", $t27544);
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27545 = (() => {
                                                    {
                                                      let $rc_783;
                                                      switch (piece2.$) {
                                                        case "I": {
                                                          $rc_783 = "I";
                                                          break;
                                                        }
                                                        case "O": {
                                                          $rc_783 = "O";
                                                          break;
                                                        }
                                                        case "T": {
                                                          $rc_783 = "T";
                                                          break;
                                                        }
                                                        case "S": {
                                                          $rc_783 = "S";
                                                          break;
                                                        }
                                                        case "Z": {
                                                          $rc_783 = "Z";
                                                          break;
                                                        }
                                                        case "J": {
                                                          $rc_783 = "J";
                                                          break;
                                                        }
                                                        case "L": {
                                                          $rc_783 = "L";
                                                          break;
                                                        }
                                                        default: {
                                                          $rc_783 = (() => { throw new Error("non-exhaustive pattern match"); })();
                                                          break;
                                                        }
                                                      }
                                                      return $rc_783;
                                                    }
                                                  })();
                                                  return Dom$set_attr(el, "data-piece", $t27545);
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27546 = String(rot2);
                                                  return Dom$set_attr(el, "data-rot", $t27546);
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27547 = String(x2);
                                                  return Dom$set_attr(el, "data-x", $t27547);
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27548 = String(y2);
                                                  return Dom$set_attr(el, "data-y", $t27548);
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27549 = (() => {
                                                    {
                                                      let $rc_782;
                                                      switch (next2.$) {
                                                        case "I": {
                                                          $rc_782 = "I";
                                                          break;
                                                        }
                                                        case "O": {
                                                          $rc_782 = "O";
                                                          break;
                                                        }
                                                        case "T": {
                                                          $rc_782 = "T";
                                                          break;
                                                        }
                                                        case "S": {
                                                          $rc_782 = "S";
                                                          break;
                                                        }
                                                        case "Z": {
                                                          $rc_782 = "Z";
                                                          break;
                                                        }
                                                        case "J": {
                                                          $rc_782 = "J";
                                                          break;
                                                        }
                                                        case "L": {
                                                          $rc_782 = "L";
                                                          break;
                                                        }
                                                        default: {
                                                          $rc_782 = (() => { throw new Error("non-exhaustive pattern match"); })();
                                                          break;
                                                        }
                                                      }
                                                      return $rc_782;
                                                    }
                                                  })();
                                                  return Dom$set_attr(el, "data-next", $t27549);
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27550 = String(score2);
                                                  return Dom$set_attr(el, "data-score", $t27550);
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27551 = String(lines2);
                                                  return Dom$set_attr(el, "data-lines", $t27551);
                                                }
                                              })();
                                              {
                                                let $t27552;
                                                if (over2 === true) {
                                                  $t27552 = "true";
                                                } else {
                                                  $t27552 = "false";
                                                }
                                                return Dom$set_attr(el, "data-over", $t27552);
                                              }
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
        })();
      }
    }
  }
}
const with_state$clo = { _0: ($_, f) => with_state(f) };

function lock_and_advance(board, piece, rot, x, y, next, score, lines) {
  {
    const $t27594 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t27594, rot);
      {
        const locked = (() => {
          {
            let $t27595;
            switch (piece.$) {
              case "I": {
                $t27595 = 1;
                break;
              }
              case "O": {
                $t27595 = 2;
                break;
              }
              case "T": {
                $t27595 = 3;
                break;
              }
              case "S": {
                $t27595 = 4;
                break;
              }
              case "Z": {
                $t27595 = 5;
                break;
              }
              case "J": {
                $t27595 = 6;
                break;
              }
              case "L": {
                $t27595 = 7;
                break;
              }
              default: {
                $t27595 = (() => { throw new Error("non-exhaustive pattern match"); })();
                break;
              }
            }
            {
              const $t27417_i3721 = { $: "$Clo_$lam27408$4688", _0: $lam27408$apply$4688, _1: $t27595, _2: x, _3: y };
              return List$fold_left$List_T_Int_Int$PVec_Int$Fn_PVec_Int_T_Int_Int_PVec_Int(cells, board, $t27417_i3721);
            }
          }
        })();
        {
          const $t27596 = TetrisLogic$clear_lines(locked);
          const $f27625 = $t27596._0;
          const $f27626 = $t27596._1;
          {
            const n = (() => {
              return $f27626;
            })();
            {
              const cleared_board = (() => {
                return $f27625;
              })();
              {
                const new_score = (() => {
                  {
                    let $t27597;
                    if (n === 1) {
                      $t27597 = 100;
                    } else if (n === 2) {
                      $t27597 = 300;
                    } else if (n === 3) {
                      $t27597 = 500;
                    } else if (n === 4) {
                      $t27597 = 800;
                    } else {
                      $t27597 = 0;
                    }
                    return (score + $t27597);
                  }
                })();
                {
                  const new_lines = (lines + n);
                  {
                    const $t27598 = (() => {
                      {
                        const cells_i9372 = TetrisLogic$piece_cells(next);
                        {
                          const over_i9374 = (() => {
                            {
                              const $t27407_i3685_i9373 = { $: "$Clo_$lam27396$3673", _0: $lam27396$apply$3673, _1: cleared_board, _2: 3, _3: 0 };
                              return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells_i9372, $t27407_i3685_i9373);
                            }
                          })();
                          {
                            const $t27486_i9391 = (() => {
                              {
                                const $t27461_i3665_i9375 = { $: "I" };
                                {
                                  const $t27462_i3666_i9376 = { $: "O" };
                                  {
                                    const $t27463_i3667_i9377 = { $: "T" };
                                    {
                                      const $t27464_i3668_i9378 = { $: "S" };
                                      {
                                        const $t27465_i3669_i9379 = { $: "Z" };
                                        {
                                          const $t27466_i3670_i9380 = { $: "J" };
                                          {
                                            const $t27467_i3671_i9381 = { $: "L" };
                                            {
                                              const $t27468_i3672_i9382 = { $: "Nil" };
                                              {
                                                const $t27469_i3673_i9383 = { $: "Cons", _0: $t27467_i3671_i9381, _1: $t27468_i3672_i9382 };
                                                {
                                                  const $t27470_i3674_i9384 = { $: "Cons", _0: $t27466_i3670_i9380, _1: $t27469_i3673_i9383 };
                                                  {
                                                    const $t27471_i3675_i9385 = { $: "Cons", _0: $t27465_i3669_i9379, _1: $t27470_i3674_i9384 };
                                                    {
                                                      const $t27472_i3676_i9386 = { $: "Cons", _0: $t27464_i3668_i9378, _1: $t27471_i3675_i9385 };
                                                      {
                                                        const $t27473_i3677_i9387 = { $: "Cons", _0: $t27463_i3667_i9377, _1: $t27472_i3676_i9386 };
                                                        {
                                                          const $t27474_i3678_i9388 = { $: "Cons", _0: $t27462_i3666_i9376, _1: $t27473_i3677_i9387 };
                                                          {
                                                            const pieces_i3679_i9389 = { $: "Cons", _0: $t27461_i3665_i9375, _1: $t27474_i3678_i9388 };
                                                            {
                                                              const $t27475_i3680_i9390 = Random$int(0, 7);
                                                              return List$nth$List_Piece$Int(pieces_i3679_i9389, $t27475_i3680_i9390);
                                                            }
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
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
                            return { _0: next, _1: 0, _2: 3, _3: 0, _4: $t27486_i9391, _5: over_i9374 };
                          }
                        }
                      }
                    })();
                    const $f27599 = $t27598._0;
                    const $f27600 = $t27598._1;
                    const $f27601 = $t27598._2;
                    const $f27602 = $t27598._3;
                    const $f27603 = $t27598._4;
                    const $f27604 = $t27598._5;
                    {
                      const over = (() => {
                        return $f27604;
                      })();
                      {
                        const next2 = (() => {
                          return $f27603;
                        })();
                        {
                          const y2 = (() => {
                            return $f27602;
                          })();
                          {
                            const x2 = (() => {
                              return $f27601;
                            })();
                            {
                              const rot2 = (() => {
                                return $f27600;
                              })();
                              {
                                const piece2 = (() => {
                                  return $f27599;
                                })();
                                return { _0: cleared_board, _1: piece2, _2: rot2, _3: x2, _4: y2, _5: next2, _6: new_score, _7: new_lines, _8: over };
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
const lock_and_advance$clo = { _0: ($_, board, piece, rot, x, y, next, score, lines) => lock_and_advance(board, piece, rot, x, y, next, score, lines) };

function fall_from(board, cells, x, cur_y) {
  {
    const $t27651 = (() => {
      {
        const $t27650 = (cur_y + 1);
        {
          const $t27407_i3726 = { $: "$Clo_$lam27396$3673", _0: $lam27396$apply$3673, _1: board, _2: x, _3: $t27650 };
          return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t27407_i3726);
        }
      }
    })();
    if ($t27651 === true) {
      return cur_y;
    } else {
      return (() => {
        {
          const $t27652 = (cur_y + 1);
          return fall_from(board, cells, x, $t27652);
        }
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
          const $t27324_i9506 = (() => {
            {
              const go_i3604_i9504 = { $: "$Clo_go$4267", _0: go$apply$4267, _1: 0 };
              {
                const $t172_i3605_i9505 = { $: "Nil" };
                return go$apply$4267(go_i3604_i9504, 200, $t172_i3605_i9505);
              }
            }
          })();
          {
            const go_i9308_i9507 = { $: "$Clo_go$4666", _0: go$apply$4666 };
            {
              const $t7129_i9311_i9510 = (() => {
                {
                  const $t6923_i4058_i9309_i9508 = { $: "TrieEmpty" };
                  {
                    const $t6924_i4059_i9310_i9509 = { $: "Nil" };
                    return { $: "PVec", _0: 0, _1: 0, _2: $t6923_i4058_i9309_i9508, _3: $t6924_i4059_i9310_i9509 };
                  }
                }
              })();
              return go$apply$4666(go_i9308_i9507, $t27324_i9506, $t7129_i9311_i9510);
            }
          }
        }
      })();
      {
        const $t27657 = (() => {
          {
            const $t27656 = (() => {
              {
                const $t27461_i3728 = { $: "I" };
                {
                  const $t27462_i3729 = { $: "O" };
                  {
                    const $t27463_i3730 = { $: "T" };
                    {
                      const $t27464_i3731 = { $: "S" };
                      {
                        const $t27465_i3732 = { $: "Z" };
                        {
                          const $t27466_i3733 = { $: "J" };
                          {
                            const $t27467_i3734 = { $: "L" };
                            {
                              const $t27468_i3735 = { $: "Nil" };
                              {
                                const $t27469_i3736 = { $: "Cons", _0: $t27467_i3734, _1: $t27468_i3735 };
                                {
                                  const $t27470_i3737 = { $: "Cons", _0: $t27466_i3733, _1: $t27469_i3736 };
                                  {
                                    const $t27471_i3738 = { $: "Cons", _0: $t27465_i3732, _1: $t27470_i3737 };
                                    {
                                      const $t27472_i3739 = { $: "Cons", _0: $t27464_i3731, _1: $t27471_i3738 };
                                      {
                                        const $t27473_i3740 = { $: "Cons", _0: $t27463_i3730, _1: $t27472_i3739 };
                                        {
                                          const $t27474_i3741 = { $: "Cons", _0: $t27462_i3729, _1: $t27473_i3740 };
                                          {
                                            const pieces_i3742 = { $: "Cons", _0: $t27461_i3728, _1: $t27474_i3741 };
                                            {
                                              const $t27475_i3743 = Random$int(0, 7);
                                              return List$nth$List_Piece$Int(pieces_i3742, $t27475_i3743);
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
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
            {
              const cells_i9427 = TetrisLogic$piece_cells($t27656);
              {
                const over_i9429 = (() => {
                  {
                    const $t27407_i3685_i9428 = { $: "$Clo_$lam27396$3673", _0: $lam27396$apply$3673, _1: board, _2: 3, _3: 0 };
                    return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells_i9427, $t27407_i3685_i9428);
                  }
                })();
                {
                  const $t27486_i9446 = (() => {
                    {
                      const $t27461_i3665_i9430 = { $: "I" };
                      {
                        const $t27462_i3666_i9431 = { $: "O" };
                        {
                          const $t27463_i3667_i9432 = { $: "T" };
                          {
                            const $t27464_i3668_i9433 = { $: "S" };
                            {
                              const $t27465_i3669_i9434 = { $: "Z" };
                              {
                                const $t27466_i3670_i9435 = { $: "J" };
                                {
                                  const $t27467_i3671_i9436 = { $: "L" };
                                  {
                                    const $t27468_i3672_i9437 = { $: "Nil" };
                                    {
                                      const $t27469_i3673_i9438 = { $: "Cons", _0: $t27467_i3671_i9436, _1: $t27468_i3672_i9437 };
                                      {
                                        const $t27470_i3674_i9439 = { $: "Cons", _0: $t27466_i3670_i9435, _1: $t27469_i3673_i9438 };
                                        {
                                          const $t27471_i3675_i9440 = { $: "Cons", _0: $t27465_i3669_i9434, _1: $t27470_i3674_i9439 };
                                          {
                                            const $t27472_i3676_i9441 = { $: "Cons", _0: $t27464_i3668_i9433, _1: $t27471_i3675_i9440 };
                                            {
                                              const $t27473_i3677_i9442 = { $: "Cons", _0: $t27463_i3667_i9432, _1: $t27472_i3676_i9441 };
                                              {
                                                const $t27474_i3678_i9443 = { $: "Cons", _0: $t27462_i3666_i9431, _1: $t27473_i3677_i9442 };
                                                {
                                                  const pieces_i3679_i9444 = { $: "Cons", _0: $t27461_i3665_i9430, _1: $t27474_i3678_i9443 };
                                                  {
                                                    const $t27475_i3680_i9445 = Random$int(0, 7);
                                                    return List$nth$List_Piece$Int(pieces_i3679_i9444, $t27475_i3680_i9445);
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
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
                  return { _0: $t27656, _1: 0, _2: 3, _3: 0, _4: $t27486_i9446, _5: over_i9429 };
                }
              }
            }
          }
        })();
        const $f27667 = $t27657._0;
        const $f27668 = $t27657._1;
        const $f27669 = $t27657._2;
        const $f27670 = $t27657._3;
        const $f27671 = $t27657._4;
        const $f27672 = $t27657._5;
        (() => {
          return $f27672;
        })();
        {
          const next = (() => {
            return $f27671;
          })();
          {
            const y = (() => {
              return $f27670;
            })();
            {
              const x = (() => {
                return $f27669;
              })();
              {
                const rot = (() => {
                  return $f27668;
                })();
                {
                  const piece = (() => {
                    return $f27667;
                  })();
                  (() => {
                    {
                      const $t27488_i9421 = (() => {
                        {
                          const go_i3691_i9418 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
                          {
                            const $t177_i3693_i9420 = { $: "Nil" };
                            return go$apply$0(go_i3691_i9418, 19, $t177_i3693_i9420);
                          }
                        }
                      })();
                      {
                        const $t27502_i9422 = { $: "$Clo_$lam27489$3687", _0: $lam27489$apply$3687, _1: board };
                        {
                          const f_i3687_i9423 = $t27502_i9422;
                          {
                            const go_i3688_i9424 = { $: "$Clo_go$4683", _0: go$apply$4683, _1: f_i3687_i9423 };
                            return go$apply$4683(go_i3688_i9424, $t27488_i9421);
                          }
                        }
                      }
                    }
                  })();
                  (() => {
                    {
                      const base_cells_i9412 = TetrisLogic$piece_cells(piece);
                      {
                        const rotated_i9413 = rotate_n(base_cells_i9412, rot);
                        {
                          const $t27526_i9414 = { $: "$Clo_$lam27503$3689", _0: $lam27503$apply$3689, _1: x, _2: y, _3: piece };
                          {
                            const f_i3695_i9415 = $t27526_i9414;
                            {
                              const go_i3696_i9416 = { $: "$Clo_go$4685", _0: go$apply$4685, _1: f_i3695_i9415 };
                              return go$apply$4685(go_i3696_i9416, rotated_i9413);
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
                      const $t27659 = (() => {
                        {
                          let $t27658;
                          switch (next.$) {
                            case "I": {
                              $t27658 = "I";
                              break;
                            }
                            case "O": {
                              $t27658 = "O";
                              break;
                            }
                            case "T": {
                              $t27658 = "T";
                              break;
                            }
                            case "S": {
                              $t27658 = "S";
                              break;
                            }
                            case "Z": {
                              $t27658 = "Z";
                              break;
                            }
                            case "J": {
                              $t27658 = "J";
                              break;
                            }
                            case "L": {
                              $t27658 = "L";
                              break;
                            }
                            default: {
                              $t27658 = (() => { throw new Error("non-exhaustive pattern match"); })();
                              break;
                            }
                          }
                          {
                            const $rc_792 = ("Next: " + $t27658);
                            return $rc_792;
                          }
                        }
                      })();
                      return set_text_if_found("next", $t27659);
                    }
                  })();
                  set_text_if_found("game-over", "");
                  (() => {
                    {
                      const $t27661 = (() => {
                        {
                          const $t27660 = (() => {
                            {
                              const $t7119_i9402 = { $: "Nil" };
                              {
                                const $t7121_i9403 = { $: "$Clo_$lam7120$4687", _0: $lam7120$apply$4687 };
                                {
                                  const rev_i9404 = Array$fold_left$PVec_Int$List_V__22334$Fn_List_V__22335_V__22335_List_V__22335(board, $t7119_i9402, $t7121_i9403);
                                  {
                                    const go_i4069_i9405 = { $: "$Clo_go$5110", _0: go$apply$5110 };
                                    {
                                      const $t6726_i4070_i9406 = { $: "Nil" };
                                      return go$apply$5110(go_i4069_i9405, rev_i9404, $t6726_i4070_i9406);
                                    }
                                  }
                                }
                              }
                            }
                          })();
                          {
                            const $t27443_i9396 = { $: "$Clo_$lam27442$3679", _0: $lam27442$apply$3679 };
                            {
                              const $t27444_i9400 = (() => {
                                {
                                  const f_i3651_i9397 = $t27443_i9396;
                                  {
                                    const go_i3652_i9398 = { $: "$Clo_go$4101", _0: go$apply$4101, _1: f_i3651_i9397 };
                                    {
                                      const $t267_i3653_i9399 = { $: "Nil" };
                                      return go$apply$4101(go_i3652_i9398, $t27660, $t267_i3653_i9399);
                                    }
                                  }
                                }
                              })();
                              return march_string_join($t27444_i9400, ",");
                            }
                          }
                        }
                      })();
                      return Dom$set_attr(el, "data-board", $t27661);
                    }
                  })();
                  (() => {
                    {
                      const $t27662 = (() => {
                        {
                          let $rc_791;
                          switch (piece.$) {
                            case "I": {
                              $rc_791 = "I";
                              break;
                            }
                            case "O": {
                              $rc_791 = "O";
                              break;
                            }
                            case "T": {
                              $rc_791 = "T";
                              break;
                            }
                            case "S": {
                              $rc_791 = "S";
                              break;
                            }
                            case "Z": {
                              $rc_791 = "Z";
                              break;
                            }
                            case "J": {
                              $rc_791 = "J";
                              break;
                            }
                            case "L": {
                              $rc_791 = "L";
                              break;
                            }
                            default: {
                              $rc_791 = (() => { throw new Error("non-exhaustive pattern match"); })();
                              break;
                            }
                          }
                          return $rc_791;
                        }
                      })();
                      return Dom$set_attr(el, "data-piece", $t27662);
                    }
                  })();
                  (() => {
                    {
                      const $t27663 = String(rot);
                      return Dom$set_attr(el, "data-rot", $t27663);
                    }
                  })();
                  (() => {
                    {
                      const $t27664 = String(x);
                      return Dom$set_attr(el, "data-x", $t27664);
                    }
                  })();
                  (() => {
                    {
                      const $t27665 = String(y);
                      return Dom$set_attr(el, "data-y", $t27665);
                    }
                  })();
                  (() => {
                    {
                      const $t27666 = (() => {
                        {
                          let $rc_790;
                          switch (next.$) {
                            case "I": {
                              $rc_790 = "I";
                              break;
                            }
                            case "O": {
                              $rc_790 = "O";
                              break;
                            }
                            case "T": {
                              $rc_790 = "T";
                              break;
                            }
                            case "S": {
                              $rc_790 = "S";
                              break;
                            }
                            case "Z": {
                              $rc_790 = "Z";
                              break;
                            }
                            case "J": {
                              $rc_790 = "J";
                              break;
                            }
                            case "L": {
                              $rc_790 = "L";
                              break;
                            }
                            default: {
                              $rc_790 = (() => { throw new Error("non-exhaustive pattern match"); })();
                              break;
                            }
                          }
                          return $rc_790;
                        }
                      })();
                      return Dom$set_attr(el, "data-next", $t27666);
                    }
                  })();
                  (() => {
                    return Dom$set_attr(el, "data-score", "0");
                  })();
                  (() => {
                    return Dom$set_attr(el, "data-lines", "0");
                  })();
                  return Dom$set_attr(el, "data-over", "false");
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
const restart$clo = { _0: ($_) => restart() };

function handle_key(ev) {
  {
    const $t27706 = Dom$event_key(ev);
    if ($t27706 === "ArrowLeft") {
      return (() => {
        {
          const $t27707 = (-1);
          {
            const $t27644_i3754 = { $: "$Clo_$lam27637$3717", _0: $lam27637$apply$3717, _1: $t27707, _2: 0 };
            return with_state($t27644_i3754);
          }
        }
      })();
    } else if ($t27706 === "ArrowRight") {
      return (() => {
        {
          const $t27644_i3757 = { $: "$Clo_$lam27637$3717", _0: $lam27637$apply$3717, _1: 1, _2: 0 };
          return with_state($t27644_i3757);
        }
      })();
    } else if ($t27706 === "ArrowDown") {
      return (() => {
        {
          const $t27644_i3760 = { $: "$Clo_$lam27637$3717", _0: $lam27637$apply$3717, _1: 0, _2: 1 };
          return with_state($t27644_i3760);
        }
      })();
    } else if ($t27706 === "ArrowUp") {
      return (() => {
        {
          const $t27649_i3761 = { $: "$Clo_$lam27645$3718", _0: $lam27645$apply$3718 };
          return with_state($t27649_i3761);
        }
      })();
    } else if ($t27706 === " ") {
      return (() => {
        {
          const $t27655_i3762 = { $: "$Clo_$lam27653$3719", _0: $lam27653$apply$3719 };
          return with_state($t27655_i3762);
        }
      })();
    } else if ($t27706 === "r") {
      return (() => {
        return restart();
      })();
    } else if ($t27706 === "R") {
      return (() => {
        return restart();
      })();
    } else {
      return (() => {
        return {  };
      })();
    }
  }
}
const handle_key$clo = { _0: ($_, ev) => handle_key(ev) };

function main() {
  {
    const $t27722 = Dom$find("board");
    switch ($t27722.$) {
      case "None": {
        return {  };
      }
      case "Some": {
        const $f27728 = $t27722._0;
        {
          const board_el = $f27728;
          (() => {
            {
              const $t27694_i9451 = (() => {
                {
                  const go_i3749_i9448 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
                  {
                    const $t177_i3751_i9450 = { $: "Nil" };
                    return go$apply$0(go_i3749_i9448, 19, $t177_i3751_i9450);
                  }
                }
              })();
              {
                const $t27705_i9452 = { $: "$Clo_$lam27695$3729", _0: $lam27695$apply$3729, _1: board_el };
                {
                  const f_i3745_i9453 = $t27705_i9452;
                  {
                    const go_i3746_i9454 = { $: "$Clo_go$4683", _0: go$apply$4683, _1: f_i3745_i9453 };
                    return go$apply$4683(go_i3746_i9454, $t27694_i9451);
                  }
                }
              }
            }
          })();
          restart();
          (() => {
            {
              const $t27723 = dom_body();
              {
                const $t27725 = { $: "$Clo_$lam27724$3738", _0: $lam27724$apply$3738 };
                return Dom$listen($t27723, "keydown", $t27725);
              }
            }
          })();
          {
            const $t27727 = { $: "$Clo_$lam27726$3739", _0: $lam27726$apply$3739 };
            return Dom$set_interval(500, $t27727);
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const main$clo = { _0: ($_) => main() };

function List$all$List_Int$Fn_Int_Bool(xs, pred) {
  switch (xs.$) {
    case "Nil": {
      return true;
    }
    case "Cons": {
      const $f421 = xs._0;
      const $f422 = xs._1;
      {
        const t = $f422;
        {
          const h = $f421;
          {
            const $t420 = (() => {
              return pred._0(pred, h);
            })();
            if ($t420 === true) {
              return List$all$List_Int$Fn_Int_Bool(t, pred);
            } else {
              return (() => {
                return false;
              })();
            }
          }
        }
      }
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const List$all$List_Int$Fn_Int_Bool$clo = { _0: ($_, xs, pred) => List$all$List_Int$Fn_Int_Bool(xs, pred) };

function List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(xs, pred) {
  switch (xs.$) {
    case "Nil": {
      return false;
    }
    case "Cons": {
      const $f414 = xs._0;
      const $f415 = xs._1;
      {
        const t = $f415;
        {
          const h = $f414;
          {
            const $t413 = (() => {
              return pred._0(pred, h);
            })();
            if ($t413 === true) {
              return true;
            } else {
              return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(t, pred);
            }
          }
        }
      }
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
      const $f6962 = v._0;
      const $f6963 = v._1;
      const $f6964 = v._2;
      const $f6965 = v._3;
      {
        const tail = $f6965;
        {
          const root = $f6964;
          {
            const shift = $f6963;
            {
              const n = $f6962;
              {
                const $t6959 = (() => {
                  {
                    const $t6957 = (idx < 0);
                    {
                      const $t6958 = (idx >= n);
                      return ($t6957 || $t6958);
                    }
                  }
                })();
                if ($t6959 === true) {
                  return (() => { throw new Error("Array.get: index out of range"); })();
                } else {
                  return (() => {
                    {
                      const tail_len = (() => {
                        {
                          const go_i4063 = { $: "$Clo_go$5108", _0: go$apply$5108 };
                          return go$apply$5108(go_i4063, tail, 0);
                        }
                      })();
                      {
                        const tail_offset = (n - tail_len);
                        {
                          const $t6960 = (idx >= tail_offset);
                          if ($t6960 === true) {
                            return (() => {
                              {
                                const $t6961 = (idx - tail_offset);
                                return Array$lst_nth$List_Int$Int(tail, $t6961);
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
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Array$get$PVec_Int$Int$clo = { _0: ($_, v, idx) => Array$get$PVec_Int$Int(v, idx) };

function Option$unwrap_or$Option_Int$Int(opt, _default) {
  switch (opt.$) {
    case "Some": {
      const $f111 = opt._0;
      {
        const x = $f111;
        return x;
      }
    }
    case "None": {
      return _default;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Option$unwrap_or$Option_Int$Int$clo = { _0: ($_, opt, _default) => Option$unwrap_or$Option_Int$Int(opt, _default) };

function List$nth$List_Piece$Int(xs, n) {
  switch (xs.$) {
    case "Nil": {
      return (() => { throw new Error("List.nth: index out of bounds"); })();
    }
    case "Cons": {
      const $f222 = xs._0;
      const $f223 = xs._1;
      {
        const t = $f223;
        {
          const h = $f222;
          {
            const $t220 = (n === 0);
            if ($t220 === true) {
              return h;
            } else {
              return (() => {
                {
                  const $t221 = (n - 1);
                  return List$nth$List_Piece$Int(t, $t221);
                }
              })();
            }
          }
        }
      }
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const List$nth$List_Piece$Int$clo = { _0: ($_, xs, n) => List$nth$List_Piece$Int(xs, n) };

function Array$push$PVec_Int$Int(v, elem) {
  switch (v.$) {
    case "PVec": {
      const $f7014 = v._0;
      const $f7015 = v._1;
      const $f7016 = v._2;
      const $f7017 = v._3;
      {
        const tail = $f7017;
        {
          const root = $f7016;
          {
            const shift = $f7015;
            {
              const n = $f7014;
              {
                const tail_len = (() => {
                  {
                    const go_i4539 = { $: "$Clo_go$5108", _0: go$apply$5108 };
                    return go$apply$5108(go_i4539, tail, 0);
                  }
                })();
                {
                  const $t7001 = (tail_len < 32);
                  if ($t7001 === true) {
                    return (() => {
                      {
                        const $t7002 = (n + 1);
                        {
                          const $t7003 = (() => {
                            {
                              const go_i4536 = { $: "$Clo_go$5258", _0: go$apply$5258, _1: elem };
                              {
                                const $t6768_i4537 = { $: "Nil" };
                                return go$apply$5258(go_i4536, tail, $t6768_i4537);
                              }
                            }
                          })();
                          return { $: "PVec", _0: $t7002, _1: shift, _2: root, _3: $t7003 };
                        }
                      }
                    })();
                  } else {
                    return (() => {
                      {
                        const trie_elems = (n - tail_len);
                        {
                          const leaf_count = march_int_div(trie_elems, 32);
                          {
                            const $t7004 = Array$push_leaf$TrieNode_Int$List_Int$Int$Int(root, tail, leaf_count, shift);
                            const $f7008 = $t7004._0;
                            const $f7009 = $t7004._1;
                            {
                              const new_shift = (() => {
                                return $f7009;
                              })();
                              {
                                const new_root = (() => {
                                  return $f7008;
                                })();
                                {
                                  const $t7005 = (n + 1);
                                  {
                                    const $t7006 = { $: "Nil" };
                                    {
                                      const $t7007 = { $: "Cons", _0: elem, _1: $t7006 };
                                      return { $: "PVec", _0: $t7005, _1: new_shift, _2: new_root, _3: $t7007 };
                                    }
                                  }
                                }
                              }
                            }
                            return (() => { throw new Error("non-exhaustive pattern match"); })();
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
      }
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Array$push$PVec_Int$Int$clo = { _0: ($_, v, elem) => Array$push$PVec_Int$Int(v, elem) };

function Array$lst_nth$List_Int$Int(lst, n) {
  switch (lst.$) {
    case "Nil": {
      return (() => { throw new Error("Array: index out of bounds"); })();
    }
    case "Cons": {
      const $f6729 = lst._0;
      const $f6730 = lst._1;
      {
        const t = $f6730;
        {
          const h = $f6729;
          {
            const $t6727 = (n === 0);
            if ($t6727 === true) {
              return h;
            } else {
              return (() => {
                {
                  const $t6728 = (n - 1);
                  return Array$lst_nth$List_Int$Int(t, $t6728);
                }
              })();
            }
          }
        }
      }
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
      return (() => { throw new Error("Array.get: missing node"); })();
    }
    case "TrieLeaf": {
      const $f6813 = node._0;
      {
        const values = $f6813;
        {
          const $t6810 = (idx & 31);
          return Array$lst_nth$List_Int$Int(values, $t6810);
        }
      }
    }
    case "TrieBranch": {
      const $f6814 = node._0;
      {
        const children = $f6814;
        {
          const slot = (() => {
            {
              const $t6809_i4920 = (idx >> shift);
              return ($t6809_i4920 & 31);
            }
          })();
          {
            const $t6811 = Array$lst_nth$List_TrieNode_Int$Int(children, slot);
            {
              const $t6812 = (shift - 5);
              return Array$trie_get$TrieNode_Int$Int$Int($t6811, idx, $t6812);
            }
          }
        }
      }
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Array$trie_get$TrieNode_Int$Int$Int$clo = { _0: ($_, node, idx, shift) => Array$trie_get$TrieNode_Int$Int$Int(node, idx, shift) };

function Array$fold_left$PVec_Int$List_V__22334$Fn_List_V__22335_V__22335_List_V__22335(v, acc, f) {
  switch (v.$) {
    case "PVec": {
      const $f7103 = v._0;
      const $f7104 = v._1;
      const $f7105 = v._2;
      const $f7106 = v._3;
      {
        const tail = $f7106;
        {
          const root = $f7105;
          {
            const acc2 = (() => {
              return Array$trie_fold$List_V__22334$TrieNode_Int$Fn_List_V__22335_V__22335_List_V__22335(acc, root, f);
            })();
            {
              const go = { $: "$Clo_go$5117", _0: go$apply$5117, _1: f };
              return go$apply$5117(go, acc2, tail);
            }
          }
        }
      }
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Array$fold_left$PVec_Int$List_V__22334$Fn_List_V__22335_V__22335_List_V__22335$clo = { _0: ($_, v, acc, f) => Array$fold_left$PVec_Int$List_V__22334$Fn_List_V__22335_V__22335_List_V__22335(v, acc, f) };

function List$fold_left$List_T_Int_Int$PVec_Int$Fn_PVec_Int_T_Int_Int_PVec_Int(xs, acc, f) {
  switch (xs.$) {
    case "Nil": {
      return acc;
    }
    case "Cons": {
      const $f351 = xs._0;
      const $f352 = xs._1;
      {
        const t = $f352;
        {
          const h = $f351;
          {
            const $t350 = (() => {
              return f._0(f, acc, h);
            })();
            return List$fold_left$List_T_Int_Int$PVec_Int$Fn_PVec_Int_T_Int_Int_PVec_Int(t, $t350, f);
          }
        }
      }
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
      const $f6985 = v._0;
      const $f6986 = v._1;
      const $f6987 = v._2;
      const $f6988 = v._3;
      {
        const tail = $f6988;
        {
          const root = $f6987;
          {
            const shift = $f6986;
            {
              const n = $f6985;
              {
                const $t6980 = (() => {
                  {
                    const $t6978 = (idx < 0);
                    {
                      const $t6979 = (idx >= n);
                      return ($t6978 || $t6979);
                    }
                  }
                })();
                if ($t6980 === true) {
                  return (() => { throw new Error("Array.set: index out of range"); })();
                } else {
                  return (() => {
                    {
                      const tail_len = (() => {
                        {
                          const go_i4938 = { $: "$Clo_go$5108", _0: go$apply$5108 };
                          return go$apply$5108(go_i4938, tail, 0);
                        }
                      })();
                      {
                        const tail_offset = (n - tail_len);
                        {
                          const $t6981 = (idx >= tail_offset);
                          if ($t6981 === true) {
                            return (() => {
                              {
                                const $t6982 = (idx - tail_offset);
                                {
                                  const $t6983 = (() => {
                                    {
                                      const rev_onto_i4934 = { $: "$Clo_rev_onto$5420", _0: rev_onto$apply$5420 };
                                      {
                                        const go_i4935 = { $: "$Clo_go$5422", _0: go$apply$5422, _1: rev_onto_i4934, _2: val };
                                        {
                                          const $t6752_i4936 = { $: "Nil" };
                                          return go$apply$5422(go_i4935, tail, $t6982, $t6752_i4936);
                                        }
                                      }
                                    }
                                  })();
                                  return { $: "PVec", _0: n, _1: shift, _2: root, _3: $t6983 };
                                }
                              }
                            })();
                          } else {
                            return (() => {
                              {
                                const $t6984 = (() => {
                                  {
                                    const ascend_i4928 = { $: "$Clo_ascend$5424", _0: ascend$apply$5424 };
                                    {
                                      const descend_i4929 = { $: "$Clo_descend$5426", _0: descend$apply$5426, _1: ascend_i4928, _2: idx, _3: val };
                                      {
                                        const $t6832_i4930 = { $: "Nil" };
                                        return descend$apply$5426(descend_i4929, root, shift, $t6832_i4930);
                                      }
                                    }
                                  }
                                })();
                                return { $: "PVec", _0: n, _1: shift, _2: $t6984, _3: tail };
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
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Array$set$PVec_Int$Int$Int$clo = { _0: ($_, v, idx, val) => Array$set$PVec_Int$Int$Int(v, idx, val) };

function Array$push_leaf$TrieNode_Int$List_Int$Int$Int(root, leaf_values, trie_leaf_count, shift) {
  {
    const $t6839 = (trie_leaf_count === 0);
    if ($t6839 === true) {
      return (() => {
        {
          const $t6843 = (() => {
            {
              const $t6840 = { $: "TrieLeaf", _0: leaf_values };
              {
                const $t6841 = { $: "Nil" };
                {
                  const $t6842 = { $: "Cons", _0: $t6840, _1: $t6841 };
                  return { $: "TrieBranch", _0: $t6842 };
                }
              }
            }
          })();
          return { _0: $t6843, _1: 5 };
        }
      })();
    } else {
      return (() => {
        {
          const $t6845 = (() => {
            {
              const $t6844 = (1 << shift);
              return (trie_leaf_count >= $t6844);
            }
          })();
          if ($t6845 === true) {
            return (() => {
              {
                const new_root = (() => {
                  {
                    const $t6846 = (() => {
                      {
                        const go_i4985 = { $: "$Clo_go$5451", _0: go$apply$5451 };
                        {
                          const $t6838_i4986 = { $: "TrieLeaf", _0: leaf_values };
                          return go$apply$5451(go_i4985, shift, $t6838_i4986);
                        }
                      }
                    })();
                    {
                      const $t6847 = { $: "Nil" };
                      {
                        const $t6848 = { $: "Cons", _0: $t6846, _1: $t6847 };
                        {
                          const $t6849 = { $: "Cons", _0: root, _1: $t6848 };
                          return { $: "TrieBranch", _0: $t6849 };
                        }
                      }
                    }
                  }
                })();
                {
                  const $t6850 = (shift + 5);
                  return { _0: new_root, _1: $t6850 };
                }
              }
            })();
          } else {
            return (() => {
              {
                const insert = { $: "$Clo_insert$5260", _0: insert$apply$5260, _1: leaf_values };
                {
                  const $t6880 = insert$apply$5260(insert, root, trie_leaf_count, shift);
                  return { _0: $t6880, _1: shift };
                }
              }
            })();
          }
        }
      })();
    }
  }
}
const Array$push_leaf$TrieNode_Int$List_Int$Int$Int$clo = { _0: ($_, root, leaf_values, trie_leaf_count, shift) => Array$push_leaf$TrieNode_Int$List_Int$Int$Int(root, leaf_values, trie_leaf_count, shift) };

function Array$lst_nth$List_TrieNode_Int$Int(lst, n) {
  switch (lst.$) {
    case "Nil": {
      return (() => { throw new Error("Array: index out of bounds"); })();
    }
    case "Cons": {
      const $f6729 = lst._0;
      const $f6730 = lst._1;
      {
        const t = $f6730;
        {
          const h = $f6729;
          {
            const $t6727 = (n === 0);
            if ($t6727 === true) {
              return h;
            } else {
              return (() => {
                {
                  const $t6728 = (n - 1);
                  return Array$lst_nth$List_TrieNode_Int$Int(t, $t6728);
                }
              })();
            }
          }
        }
      }
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Array$lst_nth$List_TrieNode_Int$Int$clo = { _0: ($_, lst, n) => Array$lst_nth$List_TrieNode_Int$Int(lst, n) };

function Array$trie_fold$List_V__22334$TrieNode_Int$Fn_List_V__22335_V__22335_List_V__22335(acc, node, f) {
  switch (node.$) {
    case "TrieEmpty": {
      return acc;
    }
    case "TrieLeaf": {
      const $f6921 = node._0;
      {
        const values = $f6921;
        {
          const go = { $: "$Clo_go$5416", _0: go$apply$5416, _1: f };
          return go$apply$5416(go, acc, values);
        }
      }
    }
    case "TrieBranch": {
      const $f6922 = node._0;
      {
        const children = $f6922;
        {
          const go = { $: "$Clo_go$5418", _0: go$apply$5418, _1: f };
          return go$apply$5418(go, acc, children);
        }
      }
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Array$trie_fold$List_V__22334$TrieNode_Int$Fn_List_V__22335_V__22335_List_V__22335$clo = { _0: ($_, acc, node, f) => Array$trie_fold$List_V__22334$TrieNode_Int$Fn_List_V__22335_V__22335_List_V__22335(acc, node, f) };

function go$apply$0($clo, i, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const start = $clo._1;
      {
        const $t173 = (i < start);
        if ($t173 === true) {
          return acc;
        } else {
          return (() => {
            {
              const $t174 = (i - 1);
              {
                const $t175 = { $: "Cons", _0: i, _1: acc };
                return go._0(go, $t174, $t175);
              }
            }
          })();
        }
      }
    }
  }
}
const go$apply$0$clo = { _0: ($_, $clo, i, acc) => go$apply$0($clo, i, acc) };

function $lam27396$apply$3673($clo, c) {
  {
    const board = (() => {
      return $clo._1;
    })();
    {
      const origin_x = (() => {
        return $clo._2;
      })();
      {
        const origin_y = (() => {
          return $clo._3;
        })();
        const $f27401 = c._0;
        const $f27402 = c._1;
        {
          const dy = (() => {
            return $f27402;
          })();
          {
            const dx = (() => {
              return $f27401;
            })();
            {
              const x = (origin_x + dx);
              {
                const y = (origin_y + dy);
                {
                  const $t27398 = (() => {
                    {
                      const $t27397 = (() => {
                        {
                          const $t27393_i9464 = (() => {
                            {
                              const $t27391_i9462 = (() => {
                                {
                                  const $t27388_i9460 = (x >= 0);
                                  {
                                    const $t27390_i9461 = (x < 10);
                                    return ($t27388_i9460 && $t27390_i9461);
                                  }
                                }
                              })();
                              {
                                const $t27392_i9463 = (y >= 0);
                                return ($t27391_i9462 && $t27392_i9463);
                              }
                            }
                          })();
                          {
                            const $t27395_i9465 = (y < 20);
                            return ($t27393_i9464 && $t27395_i9465);
                          }
                        }
                      })();
                      return (!$t27397);
                    }
                  })();
                  if ($t27398 === true) {
                    return true;
                  } else {
                    return (() => {
                      {
                        const $t27400 = (() => {
                          {
                            const $t27399 = (() => {
                              {
                                const $t27320_i9457 = (y * 10);
                                return ($t27320_i9457 + x);
                              }
                            })();
                            return Array$get$PVec_Int$Int(board, $t27399);
                          }
                        })();
                        return ($t27400 !== 0);
                      }
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
const $lam27396$apply$3673$clo = { _0: ($_, $clo, c) => $lam27396$apply$3673($clo, c) };

function $lam27420$apply$3675($clo, x) {
  {
    const board = (() => {
      return $clo._1;
    })();
    {
      const y = (() => {
        return $clo._2;
      })();
      {
        const $t27422 = (() => {
          {
            const $t27421 = (() => {
              {
                const $t27320_i9468 = (y * 10);
                return ($t27320_i9468 + x);
              }
            })();
            return Array$get$PVec_Int$Int(board, $t27421);
          }
        })();
        return ($t27422 !== 0);
      }
    }
  }
}
const $lam27420$apply$3675$clo = { _0: ($_, $clo, x) => $lam27420$apply$3675($clo, x) };

function $lam27426$apply$3676($clo, x) {
  {
    const board = (() => {
      return $clo._1;
    })();
    {
      const y = (() => {
        return $clo._2;
      })();
      {
        const $t27427 = (() => {
          {
            const $t27320_i9471 = (y * 10);
            return ($t27320_i9471 + x);
          }
        })();
        return Array$get$PVec_Int$Int(board, $t27427);
      }
    }
  }
}
const $lam27426$apply$3676$clo = { _0: ($_, $clo, x) => $lam27426$apply$3676($clo, x) };

function $lam27430$apply$3677($clo, y) {
  {
    const board = (() => {
      return $clo._1;
    })();
    {
      const $t27431 = (() => {
        {
          const $t27419_i9477 = (() => {
            {
              const go_i3616_i9474 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
              {
                const $t177_i3618_i9476 = { $: "Nil" };
                return go$apply$0(go_i3616_i9474, 9, $t177_i3618_i9476);
              }
            }
          })();
          {
            const $t27423_i9478 = { $: "$Clo_$lam27420$3675", _0: $lam27420$apply$3675, _1: board, _2: y };
            return List$all$List_Int$Fn_Int_Bool($t27419_i9477, $t27423_i9478);
          }
        }
      })();
      return (!$t27431);
    }
  }
}
const $lam27430$apply$3677$clo = { _0: ($_, $clo, y) => $lam27430$apply$3677($clo, y) };

function $lam27435$apply$3678($clo, y) {
  {
    const board = (() => {
      return $clo._1;
    })();
    {
      const $t27425_i9484 = (() => {
        {
          const go_i3625_i9481 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
          {
            const $t177_i3627_i9483 = { $: "Nil" };
            return go$apply$0(go_i3625_i9481, 9, $t177_i3627_i9483);
          }
        }
      })();
      {
        const $t27428_i9485 = { $: "$Clo_$lam27426$3676", _0: $lam27426$apply$3676, _1: board, _2: y };
        {
          const f_i3620_i9486 = $t27428_i9485;
          {
            const go_i3621_i9487 = { $: "$Clo_go$4256", _0: go$apply$4256, _1: f_i3620_i9486 };
            {
              const $t267_i3622_i9488 = { $: "Nil" };
              return go$apply$4256(go_i3621_i9487, $t27425_i9484, $t267_i3622_i9488);
            }
          }
        }
      }
    }
  }
}
const $lam27435$apply$3678$clo = { _0: ($_, $clo, y) => $lam27435$apply$3678($clo, y) };

function $lam27442$apply$3679($clo, x) {
  return String(x);
}
const $lam27442$apply$3679$clo = { _0: ($_, $clo, x) => $lam27442$apply$3679($clo, x) };

function $lam27446$apply$3680($clo, x) {
  {
    const $t27447 = march_string_to_int(x);
    return Option$unwrap_or$Option_Int$Int($t27447, 0);
  }
}
const $lam27446$apply$3680$clo = { _0: ($_, $clo, x) => $lam27446$apply$3680($clo, x) };

function $lam27489$apply$3687($clo, y) {
  {
    const board = (() => {
      return $clo._1;
    })();
    {
      const $t27491 = (() => {
        {
          const go_i7284 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
          {
            const $t177_i7286 = { $: "Nil" };
            return go$apply$0(go_i7284, 9, $t177_i7286);
          }
        }
      })();
      {
        const $t27501 = (() => {
          return { $: "$Clo_$lam27492$3688", _0: $lam27492$apply$3688, _1: board, _2: y };
        })();
        {
          const f_i7280 = $t27501;
          {
            const go_i7281 = { $: "$Clo_go$4683", _0: go$apply$4683, _1: f_i7280 };
            return go$apply$4683(go_i7281, $t27491);
          }
        }
      }
    }
  }
}
const $lam27489$apply$3687$clo = { _0: ($_, $clo, y) => $lam27489$apply$3687($clo, y) };

function $lam27492$apply$3688($clo, x) {
  {
    const board = (() => {
      return $clo._1;
    })();
    {
      const y = (() => {
        return $clo._2;
      })();
      {
        const idx = (() => {
          {
            const $t27320_i9491 = (y * 10);
            return ($t27320_i9491 + x);
          }
        })();
        {
          const v = (() => {
            return Array$get$PVec_Int$Int(board, idx);
          })();
          {
            const id = (() => {
              {
                const $t27495 = (() => {
                  {
                    const $t27494 = (() => {
                      {
                        const $t27493 = String(x);
                        {
                          const $rc_1168 = ("cell-" + $t27493);
                          return $rc_1168;
                        }
                      }
                    })();
                    {
                      const $rc_1167 = ($t27494 + "-");
                      return $rc_1167;
                    }
                  }
                })();
                {
                  const $t27496 = String(y);
                  {
                    const $rc_1166 = ($t27495 + $t27496);
                    return $rc_1166;
                  }
                }
              }
            })();
            {
              const $t27497 = Dom$find(id);
              switch ($t27497.$) {
                case "None": {
                  return {  };
                }
                case "Some": {
                  const $f27500 = $t27497._0;
                  {
                    const cell = $f27500;
                    {
                      const $t27498 = (v === 0);
                      if ($t27498 === true) {
                        return Dom$set_style(cell, "background", "#111");
                      } else {
                        return (() => {
                          {
                            let $t27499;
                            if (v === 1) {
                              $t27499 = "#00CED1";
                            } else if (v === 2) {
                              $t27499 = "#FFD700";
                            } else if (v === 3) {
                              $t27499 = "#9B59B6";
                            } else if (v === 4) {
                              $t27499 = "#2ECC71";
                            } else if (v === 5) {
                              $t27499 = "#E74C3C";
                            } else if (v === 6) {
                              $t27499 = "#3498DB";
                            } else if (v === 7) {
                              $t27499 = "#F39C12";
                            } else {
                              $t27499 = "";
                            }
                            return Dom$set_style(cell, "background", $t27499);
                          }
                        })();
                      }
                    }
                  }
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
const $lam27492$apply$3688$clo = { _0: ($_, $clo, x) => $lam27492$apply$3688($clo, x) };

function $lam27503$apply$3689($clo, c) {
  {
    const ox = (() => {
      return $clo._1;
    })();
    {
      const oy = (() => {
        return $clo._2;
      })();
      {
        const piece = (() => {
          return $clo._3;
        })();
        const $f27520 = c._0;
        const $f27521 = c._1;
        {
          const dy = (() => {
            return $f27521;
          })();
          {
            const dx = (() => {
              return $f27520;
            })();
            {
              const x = (ox + dx);
              {
                const y = (oy + dy);
                {
                  const $t27512 = (() => {
                    {
                      const $t27509 = (() => {
                        {
                          const $t27507 = (() => {
                            {
                              const $t27504 = (x >= 0);
                              {
                                const $t27506 = (x < 10);
                                return ($t27504 && $t27506);
                              }
                            }
                          })();
                          {
                            const $t27508 = (y >= 0);
                            return ($t27507 && $t27508);
                          }
                        }
                      })();
                      {
                        const $t27511 = (y < 20);
                        return ($t27509 && $t27511);
                      }
                    }
                  })();
                  if ($t27512 === true) {
                    return (() => {
                      {
                        const id = (() => {
                          {
                            const $t27515 = (() => {
                              {
                                const $t27514 = (() => {
                                  {
                                    const $t27513 = String(x);
                                    {
                                      const $rc_1171 = ("cell-" + $t27513);
                                      return $rc_1171;
                                    }
                                  }
                                })();
                                {
                                  const $rc_1170 = ($t27514 + "-");
                                  return $rc_1170;
                                }
                              }
                            })();
                            {
                              const $t27516 = String(y);
                              {
                                const $rc_1169 = ($t27515 + $t27516);
                                return $rc_1169;
                              }
                            }
                          }
                        })();
                        {
                          const $t27517 = Dom$find(id);
                          switch ($t27517.$) {
                            case "None": {
                              return {  };
                            }
                            case "Some": {
                              const $f27519 = $t27517._0;
                              {
                                const cell = $f27519;
                                {
                                  let $t27518;
                                  switch (piece.$) {
                                    case "I": {
                                      $t27518 = "#00CED1";
                                      break;
                                    }
                                    case "O": {
                                      $t27518 = "#FFD700";
                                      break;
                                    }
                                    case "T": {
                                      $t27518 = "#9B59B6";
                                      break;
                                    }
                                    case "S": {
                                      $t27518 = "#2ECC71";
                                      break;
                                    }
                                    case "Z": {
                                      $t27518 = "#E74C3C";
                                      break;
                                    }
                                    case "J": {
                                      $t27518 = "#3498DB";
                                      break;
                                    }
                                    case "L": {
                                      $t27518 = "#F39C12";
                                      break;
                                    }
                                    default: {
                                      $t27518 = (() => { throw new Error("non-exhaustive pattern match"); })();
                                      break;
                                    }
                                  }
                                  return Dom$set_style(cell, "background", $t27518);
                                }
                              }
                            }
                            default: {
                              return (() => { throw new Error("non-exhaustive pattern match"); })();
                            }
                          }
                        }
                      }
                    })();
                  } else {
                    return {  };
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
const $lam27503$apply$3689$clo = { _0: ($_, $clo, c) => $lam27503$apply$3689($clo, c) };

function $lam27631$apply$3716($clo, board, piece, rot, x, y, next, score, lines) {
  {
    const $t27632 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t27632, rot);
      {
        const $t27634 = (() => {
          {
            const $t27633 = (y + 1);
            {
              const $t27407_i7299 = { $: "$Clo_$lam27396$3673", _0: $lam27396$apply$3673, _1: board, _2: x, _3: $t27633 };
              return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t27407_i7299);
            }
          }
        })();
        if ($t27634 === true) {
          return (() => {
            {
              const $rc_1172 = lock_and_advance(board, piece, rot, x, y, next, score, lines);
              return $rc_1172;
            }
          })();
        } else {
          return (() => {
            {
              const $t27635 = (y + 1);
              return { _0: board, _1: piece, _2: rot, _3: x, _4: $t27635, _5: next, _6: score, _7: lines, _8: false };
            }
          })();
        }
      }
    }
  }
}
const $lam27631$apply$3716$clo = { _0: ($_, $clo, board, piece, rot, x, y, next, score, lines) => $lam27631$apply$3716($clo, board, piece, rot, x, y, next, score, lines) };

function $lam27637$apply$3717($clo, board, piece, rot, x, y, next, score, lines) {
  {
    const dx = (() => {
      return $clo._1;
    })();
    {
      const dy = (() => {
        return $clo._2;
      })();
      {
        const $t27638 = TetrisLogic$piece_cells(piece);
        {
          const cells = rotate_n($t27638, rot);
          {
            const $t27641 = (() => {
              {
                const $t27639 = (x + dx);
                {
                  const $t27640 = (y + dy);
                  {
                    const $t27407_i7304 = { $: "$Clo_$lam27396$3673", _0: $lam27396$apply$3673, _1: board, _2: $t27639, _3: $t27640 };
                    return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t27407_i7304);
                  }
                }
              }
            })();
            if ($t27641 === true) {
              return { _0: board, _1: piece, _2: rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: false };
            } else {
              return (() => {
                {
                  const $t27642 = (x + dx);
                  {
                    const $t27643 = (y + dy);
                    return { _0: board, _1: piece, _2: rot, _3: $t27642, _4: $t27643, _5: next, _6: score, _7: lines, _8: false };
                  }
                }
              })();
            }
          }
        }
      }
    }
  }
}
const $lam27637$apply$3717$clo = { _0: ($_, $clo, board, piece, rot, x, y, next, score, lines) => $lam27637$apply$3717($clo, board, piece, rot, x, y, next, score, lines) };

function $lam27645$apply$3718($clo, board, piece, rot, x, y, next, score, lines) {
  {
    const new_rot = (() => {
      {
        const $t27646 = (rot + 1);
        return ($t27646 % 4);
      }
    })();
    {
      const $t27647 = TetrisLogic$piece_cells(piece);
      {
        const cells = rotate_n($t27647, new_rot);
        {
          const $t27648 = (() => {
            {
              const $t27407_i7309 = { $: "$Clo_$lam27396$3673", _0: $lam27396$apply$3673, _1: board, _2: x, _3: y };
              return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t27407_i7309);
            }
          })();
          if ($t27648 === true) {
            return { _0: board, _1: piece, _2: rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: false };
          } else {
            return { _0: board, _1: piece, _2: new_rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: false };
          }
        }
      }
    }
  }
}
const $lam27645$apply$3718$clo = { _0: ($_, $clo, board, piece, rot, x, y, next, score, lines) => $lam27645$apply$3718($clo, board, piece, rot, x, y, next, score, lines) };

function $lam27653$apply$3719($clo, board, piece, rot, x, y, next, score, lines) {
  {
    const $t27654 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t27654, rot);
      {
        const final_y = (() => {
          return fall_from(board, cells, x, y);
        })();
        return lock_and_advance(board, piece, rot, x, final_y, next, score, lines);
      }
    }
  }
}
const $lam27653$apply$3719$clo = { _0: ($_, $clo, board, piece, rot, x, y, next, score, lines) => $lam27653$apply$3719($clo, board, piece, rot, x, y, next, score, lines) };

function $lam27695$apply$3729($clo, y) {
  {
    const container = (() => {
      return $clo._1;
    })();
    {
      const row = Dom$create("div");
      (() => {
        return Dom$add_class(row, "tetris-row");
      })();
      (() => {
        {
          const $t27697 = (() => {
            {
              const go_i7316 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
              {
                const $t177_i7318 = { $: "Nil" };
                return go$apply$0(go_i7316, 9, $t177_i7318);
              }
            }
          })();
          {
            const $t27704 = (() => {
              return { $: "$Clo_$lam27698$3730", _0: $lam27698$apply$3730, _1: row, _2: y };
            })();
            {
              const f_i7312 = $t27704;
              {
                const go_i7313 = { $: "$Clo_go$4683", _0: go$apply$4683, _1: f_i7312 };
                return go$apply$4683(go_i7313, $t27697);
              }
            }
          }
        }
      })();
      return Dom$append(container, row);
    }
  }
}
const $lam27695$apply$3729$clo = { _0: ($_, $clo, y) => $lam27695$apply$3729($clo, y) };

function $lam27698$apply$3730($clo, x) {
  {
    const row = (() => {
      return $clo._1;
    })();
    {
      const y = (() => {
        return $clo._2;
      })();
      {
        const cell = Dom$create("div");
        (() => {
          return Dom$add_class(cell, "tetris-cell");
        })();
        (() => {
          {
            const $t27703 = (() => {
              {
                const $t27701 = (() => {
                  {
                    const $t27700 = (() => {
                      {
                        const $t27699 = String(x);
                        {
                          const $rc_1175 = ("cell-" + $t27699);
                          return $rc_1175;
                        }
                      }
                    })();
                    {
                      const $rc_1174 = ($t27700 + "-");
                      return $rc_1174;
                    }
                  }
                })();
                {
                  const $t27702 = String(y);
                  {
                    const $rc_1173 = ($t27701 + $t27702);
                    return $rc_1173;
                  }
                }
              }
            })();
            return Dom$set_attr(cell, "id", $t27703);
          }
        })();
        return Dom$append(row, cell);
      }
    }
  }
}
const $lam27698$apply$3730$clo = { _0: ($_, $clo, x) => $lam27698$apply$3730($clo, x) };

function $lam27724$apply$3738($clo, ev) {
  return handle_key(ev);
}
const $lam27724$apply$3738$clo = { _0: ($_, $clo, ev) => $lam27724$apply$3738($clo, ev) };

function $lam27726$apply$3739($clo, _) {
  {
    const $t27636_i7319 = { $: "$Clo_$lam27631$3716", _0: $lam27631$apply$3716 };
    return with_state($t27636_i7319);
  }
}
const $lam27726$apply$3739$clo = { _0: ($_, $clo, _) => $lam27726$apply$3739($clo, _) };

function go$apply$3740($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
      }
      case "Cons": {
        const $f244 = lst._0;
        const $f245 = lst._1;
        {
          const t = $f245;
          {
            const h = $f244;
            {
              const $t243 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t243);
            }
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$3740$clo = { _0: ($_, $clo, lst, acc) => go$apply$3740($clo, lst, acc) };

function go$apply$4000($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
      }
      case "Cons": {
        const $f244 = lst._0;
        const $f245 = lst._1;
        {
          const t = $f245;
          {
            const h = $f244;
            {
              const $t243 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t243);
            }
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$4000$clo = { _0: ($_, $clo, lst, acc) => go$apply$4000($clo, lst, acc) };

function go$apply$4101($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i7449 = { $: "$Clo_go$4000", _0: go$apply$4000 };
            {
              const $t250_i7450 = { $: "Nil" };
              return go$apply$4000(go_i7449, acc, $t250_i7450);
            }
          }
        }
        case "Cons": {
          const $f261 = lst._0;
          const $f262 = lst._1;
          {
            const t = $f262;
            {
              const h = $f261;
              {
                const $t259 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t260 = { $: "Cons", _0: $t259, _1: acc };
                  return go._0(go, t, $t260);
                }
              }
            }
          }
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$4101$clo = { _0: ($_, $clo, lst, acc) => go$apply$4101($clo, lst, acc) };

function go$apply$4256($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i7676 = { $: "$Clo_go$3740", _0: go$apply$3740 };
            {
              const $t250_i7677 = { $: "Nil" };
              return go$apply$3740(go_i7676, acc, $t250_i7677);
            }
          }
        }
        case "Cons": {
          const $f261 = lst._0;
          const $f262 = lst._1;
          {
            const t = $f262;
            {
              const h = $f261;
              {
                const $t259 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t260 = { $: "Cons", _0: $t259, _1: acc };
                  return go._0(go, t, $t260);
                }
              }
            }
          }
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$4256$clo = { _0: ($_, $clo, lst, acc) => go$apply$4256($clo, lst, acc) };

function go$apply$4267($clo, i, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const x = $clo._1;
      {
        const $t169 = (i <= 0);
        if ($t169 === true) {
          return acc;
        } else {
          return (() => {
            {
              const $t170 = (i - 1);
              {
                const $t171 = { $: "Cons", _0: x, _1: acc };
                return go._0(go, $t170, $t171);
              }
            }
          })();
        }
      }
    }
  }
}
const go$apply$4267$clo = { _0: ($_, $clo, i, acc) => go$apply$4267($clo, i, acc) };

function go$apply$4455($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
      }
      case "Cons": {
        const $f252 = lst._0;
        const $f253 = lst._1;
        {
          const t = $f253;
          {
            const h = $f252;
            {
              const $t251 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t251);
            }
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$4455$clo = { _0: ($_, $clo, lst, acc) => go$apply$4455($clo, lst, acc) };

function go$apply$4561($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8215 = { $: "$Clo_go$3740", _0: go$apply$3740 };
            {
              const $t250_i8216 = { $: "Nil" };
              return go$apply$3740(go_i8215, acc, $t250_i8216);
            }
          }
        }
        case "Cons": {
          const $f293 = lst._0;
          const $f294 = lst._1;
          {
            const t = $f294;
            {
              const h = $f293;
              {
                const $t291 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t291 === true) {
                  return (() => {
                    {
                      const $t292 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t292);
                    }
                  })();
                } else {
                  return go._0(go, t, acc);
                }
              }
            }
          }
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$4561$clo = { _0: ($_, $clo, lst, acc) => go$apply$4561($clo, lst, acc) };

function go$apply$4589($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
      }
      case "Cons": {
        const $f237 = lst._0;
        const $f238 = lst._1;
        {
          const t = $f238;
          {
            const $t236 = (acc + 1);
            return go._0(go, t, $t236);
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$4589$clo = { _0: ($_, $clo, lst, acc) => go$apply$4589($clo, lst, acc) };

function go$apply$4666($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
      }
      case "Cons": {
        const $f7123 = lst._0;
        const $f7124 = lst._1;
        {
          const rest = $f7124;
          {
            const x = $f7123;
            {
              const $t7122 = Array$push$PVec_Int$Int(acc, x);
              return go._0(go, rest, $t7122);
            }
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$4666$clo = { _0: ($_, $clo, lst, acc) => go$apply$4666($clo, lst, acc) };

function go$apply$4668($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8344 = { $: "$Clo_go$5104", _0: go$apply$5104 };
            {
              const $t250_i8345 = { $: "Nil" };
              return go$apply$5104(go_i8344, acc, $t250_i8345);
            }
          }
        }
        case "Cons": {
          const $f261 = lst._0;
          const $f262 = lst._1;
          {
            const t = $f262;
            {
              const h = $f261;
              {
                const $t259 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t260 = { $: "Cons", _0: $t259, _1: acc };
                  return go._0(go, t, $t260);
                }
              }
            }
          }
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$4668$clo = { _0: ($_, $clo, lst, acc) => go$apply$4668($clo, lst, acc) };

function prepend_reversed$apply$4676($clo, sub, acc) {
  {
    const prepend_reversed = $clo;
    switch (sub.$) {
      case "Nil": {
        return acc;
      }
      case "Cons": {
        const $f276 = sub._0;
        const $f277 = sub._1;
        {
          const rest = $f277;
          {
            const x = $f276;
            {
              const $t275 = { $: "Cons", _0: x, _1: acc };
              return prepend_reversed._0(prepend_reversed, rest, $t275);
            }
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const prepend_reversed$apply$4676$clo = { _0: ($_, $clo, sub, acc) => prepend_reversed$apply$4676($clo, sub, acc) };

function go$apply$4678($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = (() => {
        return $clo._1;
      })();
      {
        const prepend_reversed = $clo._2;
        switch (lst.$) {
          case "Nil": {
            {
              const go_i8353 = { $: "$Clo_go$3740", _0: go$apply$3740 };
              {
                const $t250_i8354 = { $: "Nil" };
                return go$apply$3740(go_i8353, acc, $t250_i8354);
              }
            }
          }
          case "Cons": {
            const $f284 = lst._0;
            const $f285 = lst._1;
            {
              const t = $f285;
              {
                const h = $f284;
                {
                  const $t282 = (() => {
                    return f._0(f, h);
                  })();
                  {
                    const $t283 = (() => {
                      return prepend_reversed._0(prepend_reversed, $t282, acc);
                    })();
                    return go._0(go, t, $t283);
                  }
                }
              }
            }
          }
          default: {
            return (() => { throw new Error("non-exhaustive pattern match"); })();
          }
        }
      }
    }
  }
}
const go$apply$4678$clo = { _0: ($_, $clo, lst, acc) => go$apply$4678($clo, lst, acc) };

function go$apply$4680($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8358 = { $: "$Clo_go$3740", _0: go$apply$3740 };
            {
              const $t250_i8359 = { $: "Nil" };
              return go$apply$3740(go_i8358, acc, $t250_i8359);
            }
          }
        }
        case "Cons": {
          const $f261 = lst._0;
          const $f262 = lst._1;
          {
            const t = $f262;
            {
              const h = $f261;
              {
                const $t259 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t260 = { $: "Cons", _0: $t259, _1: acc };
                  return go._0(go, t, $t260);
                }
              }
            }
          }
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$4680$clo = { _0: ($_, $clo, lst, acc) => go$apply$4680($clo, lst, acc) };

function go$apply$4683($clo, lst) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          return {  };
        }
        case "Cons": {
          const $f269 = lst._0;
          const $f270 = lst._1;
          {
            const t = $f270;
            {
              const h = $f269;
              (() => {
                return f._0(f, h);
              })();
              return go._0(go, t);
            }
          }
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$4683$clo = { _0: ($_, $clo, lst) => go$apply$4683($clo, lst) };

function go$apply$4685($clo, lst) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          return {  };
        }
        case "Cons": {
          const $f269 = lst._0;
          const $f270 = lst._1;
          {
            const t = $f270;
            {
              const h = $f269;
              (() => {
                return f._0(f, h);
              })();
              return go._0(go, t);
            }
          }
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$4685$clo = { _0: ($_, $clo, lst) => go$apply$4685($clo, lst) };

function $lam7120$apply$4687($clo, acc, x) {
  return { $: "Cons", _0: x, _1: acc };
}
const $lam7120$apply$4687$clo = { _0: ($_, $clo, acc, x) => $lam7120$apply$4687($clo, acc, x) };

function $lam27408$apply$4688($clo, b, c) {
  {
    const color_idx = (() => {
      return $clo._1;
    })();
    {
      const origin_x = (() => {
        return $clo._2;
      })();
      {
        const origin_y = (() => {
          return $clo._3;
        })();
        const $f27411 = c._0;
        const $f27412 = c._1;
        {
          const dy = (() => {
            return $f27412;
          })();
          {
            const dx = (() => {
              return $f27411;
            })();
            {
              const x = (origin_x + dx);
              {
                const y = (origin_y + dy);
                {
                  const $t27409 = (() => {
                    {
                      const $t27393_i9502 = (() => {
                        {
                          const $t27391_i9500 = (() => {
                            {
                              const $t27388_i9498 = (x >= 0);
                              {
                                const $t27390_i9499 = (x < 10);
                                return ($t27388_i9498 && $t27390_i9499);
                              }
                            }
                          })();
                          {
                            const $t27392_i9501 = (y >= 0);
                            return ($t27391_i9500 && $t27392_i9501);
                          }
                        }
                      })();
                      {
                        const $t27395_i9503 = (y < 20);
                        return ($t27393_i9502 && $t27395_i9503);
                      }
                    }
                  })();
                  if ($t27409 === true) {
                    return (() => {
                      {
                        const $t27410 = (() => {
                          {
                            const $t27320_i9495 = (y * 10);
                            return ($t27320_i9495 + x);
                          }
                        })();
                        return Array$set$PVec_Int$Int$Int(b, $t27410, color_idx);
                      }
                    })();
                  } else {
                    return b;
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
const $lam27408$apply$4688$clo = { _0: ($_, $clo, b, c) => $lam27408$apply$4688($clo, b, c) };

function go$apply$5104($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
      }
      case "Cons": {
        const $f244 = lst._0;
        const $f245 = lst._1;
        {
          const t = $f245;
          {
            const h = $f244;
            {
              const $t243 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t243);
            }
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$5104$clo = { _0: ($_, $clo, lst, acc) => go$apply$5104($clo, lst, acc) };

function go$apply$5108($clo, xs, acc) {
  {
    const go = $clo;
    switch (xs.$) {
      case "Nil": {
        return acc;
      }
      case "Cons": {
        const $f6754 = xs._0;
        const $f6755 = xs._1;
        {
          const t = $f6755;
          {
            const $t6753 = (acc + 1);
            return go._0(go, t, $t6753);
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$5108$clo = { _0: ($_, $clo, xs, acc) => go$apply$5108($clo, xs, acc) };

function go$apply$5110($clo, xs, acc) {
  {
    const go = $clo;
    switch (xs.$) {
      case "Nil": {
        return acc;
      }
      case "Cons": {
        const $f6720 = xs._0;
        const $f6721 = xs._1;
        {
          const t = $f6721;
          {
            const h = $f6720;
            {
              const $t6719 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t6719);
            }
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$5110$clo = { _0: ($_, $clo, xs, acc) => go$apply$5110($clo, xs, acc) };

function go$apply$5117($clo, a, xs) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (xs.$) {
        case "Nil": {
          return a;
        }
        case "Cons": {
          const $f7097 = xs._0;
          const $f7098 = xs._1;
          {
            const rest = $f7098;
            {
              const x = $f7097;
              {
                const $t7096 = (() => {
                  return f._0(f, a, x);
                })();
                return go._0(go, $t7096, rest);
              }
            }
          }
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$5117$clo = { _0: ($_, $clo, a, xs) => go$apply$5117($clo, a, xs) };

function go$apply$5258($clo, xs, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const x = $clo._1;
      switch (xs.$) {
        case "Nil": {
          {
            const $t6760 = { $: "Cons", _0: x, _1: acc };
            {
              const go_i8917 = { $: "$Clo_go$5449", _0: go$apply$5449 };
              {
                const $t6726_i8918 = { $: "Nil" };
                return go$apply$5449(go_i8917, $t6760, $t6726_i8918);
              }
            }
          }
        }
        case "Cons": {
          const $f6762 = xs._0;
          const $f6763 = xs._1;
          {
            const t = $f6763;
            {
              const h = $f6762;
              {
                const $t6761 = { $: "Cons", _0: h, _1: acc };
                return go._0(go, t, $t6761);
              }
            }
          }
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$5258$clo = { _0: ($_, $clo, xs, acc) => go$apply$5258($clo, xs, acc) };

function insert$apply$5260($clo, node, leaf_idx, s) {
  {
    const leaf_values = (() => {
      return $clo._1;
    })();
    {
      const ascend = { $: "$Clo_ascend$5261", _0: ascend$apply$5261 };
      {
        const descend = (() => {
          return { $: "$Clo_descend$5263", _0: descend$apply$5263, _1: ascend, _2: leaf_idx, _3: leaf_values };
        })();
        {
          const $t6879 = { $: "Nil" };
          return descend$apply$5263(descend, node, s, $t6879);
        }
      }
    }
  }
}
const insert$apply$5260$clo = { _0: ($_, $clo, node, leaf_idx, s) => insert$apply$5260($clo, node, leaf_idx, s) };

function ascend$apply$5261($clo, nd, stk) {
  {
    const ascend = $clo;
    switch (stk.$) {
      case "Nil": {
        return nd;
      }
      case "Cons": {
        const $f6854 = stk._0;
        const $f6855 = stk._1;
        {
          const rest = $f6855;
          {
            const frame = $f6854;
            {
              const children = frame._0;
              {
                const slot_i = frame._1;
                {
                  const $t6852 = (() => {
                    {
                      const $t6851 = (() => {
                        {
                          const rev_onto_i8924 = { $: "$Clo_rev_onto$5452", _0: rev_onto$apply$5452 };
                          {
                            const go_i8925 = { $: "$Clo_go$5454", _0: go$apply$5454, _1: nd, _2: rev_onto_i8924 };
                            {
                              const $t6808_i8926 = { $: "Nil" };
                              return go$apply$5454(go_i8925, children, slot_i, $t6808_i8926);
                            }
                          }
                        }
                      })();
                      return { $: "TrieBranch", _0: $t6851 };
                    }
                  })();
                  return ascend._0(ascend, $t6852, rest);
                }
              }
            }
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const ascend$apply$5261$clo = { _0: ($_, $clo, nd, stk) => ascend$apply$5261($clo, nd, stk) };

function descend$apply$5263($clo, nd, s, path) {
  {
    const descend = (() => {
      return $clo;
    })();
    {
      const ascend = (() => {
        return $clo._1;
      })();
      {
        const leaf_idx = (() => {
          return $clo._2;
        })();
        {
          const leaf_values = $clo._3;
          switch (nd.$) {
            case "TrieBranch": {
              const $f6874 = nd._0;
              {
                const $jp_clo6876 = (() => {
                  return { $: "$Clo_$jp6875$5264", _0: $jp6875$apply$5264, _1: ascend, _2: leaf_values, _3: path, _4: s };
                })();
                {
                  const children = $f6874;
                  {
                    const slot = (() => {
                      {
                        const $t6860 = (s - 5);
                        {
                          const $t6809_i8944 = (leaf_idx >> $t6860);
                          return ($t6809_i8944 & 31);
                        }
                      }
                    })();
                    {
                      const n = (() => {
                        {
                          const go_i8941 = { $: "$Clo_go$5458", _0: go$apply$5458 };
                          return go$apply$5458(go_i8941, children, 0);
                        }
                      })();
                      {
                        const $t6861 = (slot === n);
                        if ($t6861 === true) {
                          return (() => {
                            {
                              const $t6865 = (() => {
                                {
                                  const $t6863 = (() => {
                                    {
                                      const $t6862 = (s - 5);
                                      {
                                        const go_i8938 = { $: "$Clo_go$5451", _0: go$apply$5451 };
                                        {
                                          const $t6838_i8939 = { $: "TrieLeaf", _0: leaf_values };
                                          return go$apply$5451(go_i8938, $t6862, $t6838_i8939);
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t6864 = (() => {
                                      {
                                        const go_i8934 = { $: "$Clo_go$5456", _0: go$apply$5456, _1: $t6863 };
                                        {
                                          const $t6768_i8935 = { $: "Nil" };
                                          return go$apply$5456(go_i8934, children, $t6768_i8935);
                                        }
                                      }
                                    })();
                                    return { $: "TrieBranch", _0: $t6864 };
                                  }
                                }
                              })();
                              return ascend._0(ascend, $t6865, path);
                            }
                          })();
                        } else {
                          return (() => {
                            {
                              const $t6867 = (() => {
                                {
                                  const $t6866 = (n - 1);
                                  return Array$lst_nth$List_TrieNode_Int$Int(children, $t6866);
                                }
                              })();
                              {
                                const $t6868 = (s - 5);
                                {
                                  const $t6870 = (() => {
                                    {
                                      const $t6869 = (n - 1);
                                      return { _0: children, _1: $t6869 };
                                    }
                                  })();
                                  {
                                    const $t6871 = { $: "Cons", _0: $t6870, _1: path };
                                    return descend._0(descend, $t6867, $t6868, $t6871);
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
            }
            default: {
              {
                const $t6873 = (() => {
                  {
                    const $t6872 = (s - 5);
                    {
                      const go_i8930 = { $: "$Clo_go$5451", _0: go$apply$5451 };
                      {
                        const $t6838_i8931 = { $: "TrieLeaf", _0: leaf_values };
                        return go$apply$5451(go_i8930, $t6872, $t6838_i8931);
                      }
                    }
                  }
                })();
                return ascend._0(ascend, $t6873, path);
              }
            }
          }
        }
      }
    }
  }
}
const descend$apply$5263$clo = { _0: ($_, $clo, nd, s, path) => descend$apply$5263($clo, nd, s, path) };

function $jp6875$apply$5264($clo) {
  {
    const ascend = (() => {
      return $clo._1;
    })();
    {
      const leaf_values = (() => {
        return $clo._2;
      })();
      {
        const path = (() => {
          return $clo._3;
        })();
        {
          const s = (() => {
            return $clo._4;
          })();
          {
            const $t6873 = (() => {
              {
                const $t6872 = (s - 5);
                {
                  const go_i8947 = { $: "$Clo_go$5451", _0: go$apply$5451 };
                  {
                    const $t6838_i8948 = { $: "TrieLeaf", _0: leaf_values };
                    return go$apply$5451(go_i8947, $t6872, $t6838_i8948);
                  }
                }
              }
            })();
            return ascend._0(ascend, $t6873, path);
          }
        }
      }
    }
  }
}
const $jp6875$apply$5264$clo = { _0: ($_, $clo) => $jp6875$apply$5264($clo) };

function go$apply$5416($clo, a, vs) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (vs.$) {
        case "Nil": {
          return a;
        }
        case "Cons": {
          const $f6908 = vs._0;
          const $f6909 = vs._1;
          {
            const rest = $f6909;
            {
              const v = $f6908;
              {
                const $t6907 = (() => {
                  return f._0(f, a, v);
                })();
                return go._0(go, $t6907, rest);
              }
            }
          }
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$5416$clo = { _0: ($_, $clo, a, vs) => go$apply$5416($clo, a, vs) };

function go$apply$5418($clo, a, cs) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (cs.$) {
        case "Nil": {
          return a;
        }
        case "Cons": {
          const $f6915 = cs._0;
          const $f6916 = cs._1;
          {
            const rest = $f6916;
            {
              const child = $f6915;
              {
                const $t6914 = (() => {
                  return Array$trie_fold$List_V__22334$TrieNode_Int$Fn_List_V__22335_V__22335_List_V__22335(a, child, f);
                })();
                return go._0(go, $t6914, rest);
              }
            }
          }
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$5418$clo = { _0: ($_, $clo, a, cs) => go$apply$5418($clo, a, cs) };

function rev_onto$apply$5420($clo, rev_xs, ys) {
  {
    const rev_onto = $clo;
    switch (rev_xs.$) {
      case "Nil": {
        return ys;
      }
      case "Cons": {
        const $f6736 = rev_xs._0;
        const $f6737 = rev_xs._1;
        {
          const rest = $f6737;
          {
            const a = $f6736;
            {
              const $t6735 = { $: "Cons", _0: a, _1: ys };
              return rev_onto._0(rev_onto, rest, $t6735);
            }
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const rev_onto$apply$5420$clo = { _0: ($_, $clo, rev_xs, ys) => rev_onto$apply$5420($clo, rev_xs, ys) };

function go$apply$5422($clo, xs, i, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const rev_onto = (() => {
        return $clo._1;
      })();
      {
        const v = $clo._2;
        switch (xs.$) {
          case "Nil": {
            {
              const go_i9189 = { $: "$Clo_go$5449", _0: go$apply$5449 };
              {
                const $t6726_i9190 = { $: "Nil" };
                return go$apply$5449(go_i9189, acc, $t6726_i9190);
              }
            }
          }
          case "Cons": {
            const $f6746 = xs._0;
            const $f6747 = xs._1;
            {
              const t = $f6747;
              {
                const h = $f6746;
                {
                  const $t6742 = (i === 0);
                  if ($t6742 === true) {
                    return (() => {
                      {
                        const $t6743 = { $: "Cons", _0: v, _1: t };
                        return rev_onto._0(rev_onto, acc, $t6743);
                      }
                    })();
                  } else {
                    return (() => {
                      {
                        const $t6744 = (i - 1);
                        {
                          const $t6745 = { $: "Cons", _0: h, _1: acc };
                          return go._0(go, t, $t6744, $t6745);
                        }
                      }
                    })();
                  }
                }
              }
            }
          }
          default: {
            return (() => { throw new Error("non-exhaustive pattern match"); })();
          }
        }
      }
    }
  }
}
const go$apply$5422$clo = { _0: ($_, $clo, xs, i, acc) => go$apply$5422($clo, xs, i, acc) };

function ascend$apply$5424($clo, nd, stk) {
  {
    const ascend = $clo;
    switch (stk.$) {
      case "Nil": {
        return nd;
      }
      case "Cons": {
        const $f6818 = stk._0;
        const $f6819 = stk._1;
        {
          const rest = $f6819;
          {
            const frame = $f6818;
            {
              const children = frame._0;
              {
                const slot = frame._1;
                {
                  const $t6816 = (() => {
                    {
                      const $t6815 = (() => {
                        {
                          const rev_onto_i9196 = { $: "$Clo_rev_onto$5464", _0: rev_onto$apply$5464 };
                          {
                            const go_i9197 = { $: "$Clo_go$5466", _0: go$apply$5466, _1: nd, _2: rev_onto_i9196 };
                            {
                              const $t6808_i9198 = { $: "Nil" };
                              return go$apply$5466(go_i9197, children, slot, $t6808_i9198);
                            }
                          }
                        }
                      })();
                      return { $: "TrieBranch", _0: $t6815 };
                    }
                  })();
                  return ascend._0(ascend, $t6816, rest);
                }
              }
            }
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const ascend$apply$5424$clo = { _0: ($_, $clo, nd, stk) => ascend$apply$5424($clo, nd, stk) };

function descend$apply$5426($clo, n, s, path) {
  {
    const descend = (() => {
      return $clo;
    })();
    {
      const ascend = (() => {
        return $clo._1;
      })();
      {
        const idx = (() => {
          return $clo._2;
        })();
        {
          const val = $clo._3;
          switch (n.$) {
            case "TrieEmpty": {
              return (() => { throw new Error("Array.set: missing node"); })();
            }
            case "TrieLeaf": {
              const $f6830 = n._0;
              {
                const values = $f6830;
                {
                  const $t6826 = (() => {
                    {
                      const $t6824 = (idx & 31);
                      {
                        const $t6825 = (() => {
                          {
                            const rev_onto_i9205 = { $: "$Clo_rev_onto$5420", _0: rev_onto$apply$5420 };
                            {
                              const go_i9206 = { $: "$Clo_go$5422", _0: go$apply$5422, _1: rev_onto_i9205, _2: val };
                              {
                                const $t6752_i9207 = { $: "Nil" };
                                return go$apply$5422(go_i9206, values, $t6824, $t6752_i9207);
                              }
                            }
                          }
                        })();
                        return { $: "TrieLeaf", _0: $t6825 };
                      }
                    }
                  })();
                  return ascend._0(ascend, $t6826, path);
                }
              }
            }
            case "TrieBranch": {
              const $f6831 = n._0;
              {
                const children = $f6831;
                {
                  const slot = (() => {
                    {
                      const $t6809_i9210 = (idx >> s);
                      return ($t6809_i9210 & 31);
                    }
                  })();
                  {
                    const child = (() => {
                      return Array$lst_nth$List_TrieNode_Int$Int(children, slot);
                    })();
                    {
                      const $t6827 = (s - 5);
                      {
                        const $t6828 = { _0: children, _1: slot };
                        {
                          const $t6829 = { $: "Cons", _0: $t6828, _1: path };
                          return descend._0(descend, child, $t6827, $t6829);
                        }
                      }
                    }
                  }
                }
              }
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
const descend$apply$5426$clo = { _0: ($_, $clo, n, s, path) => descend$apply$5426($clo, n, s, path) };

function go$apply$5449($clo, xs, acc) {
  {
    const go = $clo;
    switch (xs.$) {
      case "Nil": {
        return acc;
      }
      case "Cons": {
        const $f6720 = xs._0;
        const $f6721 = xs._1;
        {
          const t = $f6721;
          {
            const h = $f6720;
            {
              const $t6719 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t6719);
            }
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$5449$clo = { _0: ($_, $clo, xs, acc) => go$apply$5449($clo, xs, acc) };

function go$apply$5451($clo, s, node) {
  {
    const go = $clo;
    {
      const $t6833 = (s === 0);
      if ($t6833 === true) {
        return node;
      } else {
        return (() => {
          {
            const $t6834 = (s - 5);
            {
              const $t6837 = (() => {
                {
                  const $t6835 = { $: "Nil" };
                  {
                    const $t6836 = { $: "Cons", _0: node, _1: $t6835 };
                    return { $: "TrieBranch", _0: $t6836 };
                  }
                }
              })();
              return go._0(go, $t6834, $t6837);
            }
          }
        })();
      }
    }
  }
}
const go$apply$5451$clo = { _0: ($_, $clo, s, node) => go$apply$5451($clo, s, node) };

function rev_onto$apply$5452($clo, rev_xs, ys) {
  {
    const rev_onto = $clo;
    switch (rev_xs.$) {
      case "Nil": {
        return ys;
      }
      case "Cons": {
        const $f6792 = rev_xs._0;
        const $f6793 = rev_xs._1;
        {
          const rest = $f6793;
          {
            const a = $f6792;
            {
              const $t6791 = { $: "Cons", _0: a, _1: ys };
              return rev_onto._0(rev_onto, rest, $t6791);
            }
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const rev_onto$apply$5452$clo = { _0: ($_, $clo, rev_xs, ys) => rev_onto$apply$5452($clo, rev_xs, ys) };

function go$apply$5454($clo, xs, i, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const node = (() => {
        return $clo._1;
      })();
      {
        const rev_onto = $clo._2;
        switch (xs.$) {
          case "Nil": {
            {
              const go_i9248 = { $: "$Clo_go$5484", _0: go$apply$5484 };
              {
                const $t6726_i9249 = { $: "Nil" };
                return go$apply$5484(go_i9248, acc, $t6726_i9249);
              }
            }
          }
          case "Cons": {
            const $f6802 = xs._0;
            const $f6803 = xs._1;
            {
              const t = $f6803;
              {
                const h = $f6802;
                {
                  const $t6798 = (i === 0);
                  if ($t6798 === true) {
                    return (() => {
                      {
                        const $t6799 = (() => {
                          return { $: "Cons", _0: node, _1: t };
                        })();
                        return rev_onto._0(rev_onto, acc, $t6799);
                      }
                    })();
                  } else {
                    return (() => {
                      {
                        const $t6800 = (i - 1);
                        {
                          const $t6801 = { $: "Cons", _0: h, _1: acc };
                          return go._0(go, t, $t6800, $t6801);
                        }
                      }
                    })();
                  }
                }
              }
            }
          }
          default: {
            return (() => { throw new Error("non-exhaustive pattern match"); })();
          }
        }
      }
    }
  }
}
const go$apply$5454$clo = { _0: ($_, $clo, xs, i, acc) => go$apply$5454($clo, xs, i, acc) };

function go$apply$5456($clo, xs, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const x = $clo._1;
      switch (xs.$) {
        case "Nil": {
          {
            const $t6760 = (() => {
              return { $: "Cons", _0: x, _1: acc };
            })();
            {
              const go_i9253 = { $: "$Clo_go$5486", _0: go$apply$5486 };
              {
                const $t6726_i9254 = { $: "Nil" };
                return go$apply$5486(go_i9253, $t6760, $t6726_i9254);
              }
            }
          }
        }
        case "Cons": {
          const $f6762 = xs._0;
          const $f6763 = xs._1;
          {
            const t = $f6763;
            {
              const h = $f6762;
              {
                const $t6761 = { $: "Cons", _0: h, _1: acc };
                return go._0(go, t, $t6761);
              }
            }
          }
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$5456$clo = { _0: ($_, $clo, xs, acc) => go$apply$5456($clo, xs, acc) };

function go$apply$5458($clo, xs, acc) {
  {
    const go = $clo;
    switch (xs.$) {
      case "Nil": {
        return acc;
      }
      case "Cons": {
        const $f6754 = xs._0;
        const $f6755 = xs._1;
        {
          const t = $f6755;
          {
            const $t6753 = (acc + 1);
            return go._0(go, t, $t6753);
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$5458$clo = { _0: ($_, $clo, xs, acc) => go$apply$5458($clo, xs, acc) };

function rev_onto$apply$5464($clo, rev_xs, ys) {
  {
    const rev_onto = $clo;
    switch (rev_xs.$) {
      case "Nil": {
        return ys;
      }
      case "Cons": {
        const $f6792 = rev_xs._0;
        const $f6793 = rev_xs._1;
        {
          const rest = $f6793;
          {
            const a = $f6792;
            {
              const $t6791 = { $: "Cons", _0: a, _1: ys };
              return rev_onto._0(rev_onto, rest, $t6791);
            }
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const rev_onto$apply$5464$clo = { _0: ($_, $clo, rev_xs, ys) => rev_onto$apply$5464($clo, rev_xs, ys) };

function go$apply$5466($clo, xs, i, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const node = (() => {
        return $clo._1;
      })();
      {
        const rev_onto = $clo._2;
        switch (xs.$) {
          case "Nil": {
            {
              const go_i9266 = { $: "$Clo_go$5488", _0: go$apply$5488 };
              {
                const $t6726_i9267 = { $: "Nil" };
                return go$apply$5488(go_i9266, acc, $t6726_i9267);
              }
            }
          }
          case "Cons": {
            const $f6802 = xs._0;
            const $f6803 = xs._1;
            {
              const t = $f6803;
              {
                const h = $f6802;
                {
                  const $t6798 = (i === 0);
                  if ($t6798 === true) {
                    return (() => {
                      {
                        const $t6799 = (() => {
                          return { $: "Cons", _0: node, _1: t };
                        })();
                        return rev_onto._0(rev_onto, acc, $t6799);
                      }
                    })();
                  } else {
                    return (() => {
                      {
                        const $t6800 = (i - 1);
                        {
                          const $t6801 = { $: "Cons", _0: h, _1: acc };
                          return go._0(go, t, $t6800, $t6801);
                        }
                      }
                    })();
                  }
                }
              }
            }
          }
          default: {
            return (() => { throw new Error("non-exhaustive pattern match"); })();
          }
        }
      }
    }
  }
}
const go$apply$5466$clo = { _0: ($_, $clo, xs, i, acc) => go$apply$5466($clo, xs, i, acc) };

function go$apply$5484($clo, xs, acc) {
  {
    const go = $clo;
    switch (xs.$) {
      case "Nil": {
        return acc;
      }
      case "Cons": {
        const $f6720 = xs._0;
        const $f6721 = xs._1;
        {
          const t = $f6721;
          {
            const h = $f6720;
            {
              const $t6719 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t6719);
            }
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$5484$clo = { _0: ($_, $clo, xs, acc) => go$apply$5484($clo, xs, acc) };

function go$apply$5486($clo, xs, acc) {
  {
    const go = $clo;
    switch (xs.$) {
      case "Nil": {
        return acc;
      }
      case "Cons": {
        const $f6720 = xs._0;
        const $f6721 = xs._1;
        {
          const t = $f6721;
          {
            const h = $f6720;
            {
              const $t6719 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t6719);
            }
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$5486$clo = { _0: ($_, $clo, xs, acc) => go$apply$5486($clo, xs, acc) };

function go$apply$5488($clo, xs, acc) {
  {
    const go = $clo;
    switch (xs.$) {
      case "Nil": {
        return acc;
      }
      case "Cons": {
        const $f6720 = xs._0;
        const $f6721 = xs._1;
        {
          const t = $f6721;
          {
            const h = $f6720;
            {
              const $t6719 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t6719);
            }
          }
        }
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$5488$clo = { _0: ($_, $clo, xs, acc) => go$apply$5488($clo, xs, acc) };

export { main };
main();
//# sourceMappingURL=tetris.mjs.map
