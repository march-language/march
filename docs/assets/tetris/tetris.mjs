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
        const max_v_i1539 = (() => {
          {
            const $t15521_i1538 = {  };
            return 9223372036854775807;
          }
        })();
        {
          const x_i1542 = (() => {
            {
              const $t15523_i1541 = (() => {
                {
                  const $t15522_i1540 = (n & max_v_i1539);
                  return ($t15522_i1540 >> 30);
                }
              })();
              return (n ^ $t15523_i1541);
            }
          })();
          {
            const x_i1543 = (x_i1542 * 1234567891011);
            {
              const x_i1546 = (() => {
                {
                  const $t15525_i1545 = (() => {
                    {
                      const $t15524_i1544 = (x_i1543 & max_v_i1539);
                      return ($t15524_i1544 >> 27);
                    }
                  })();
                  return (x_i1543 ^ $t15525_i1545);
                }
              })();
              {
                const x_i1547 = (x_i1546 * 987654321);
                {
                  const x_i1550 = (() => {
                    {
                      const $t15527_i1549 = (() => {
                        {
                          const $t15526_i1548 = (x_i1547 & max_v_i1539);
                          return ($t15526_i1548 >> 31);
                        }
                      })();
                      return (x_i1547 ^ $t15527_i1549);
                    }
                  })();
                  return x_i1550;
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
          const $t15528 = (n + 1);
          {
            const max_v_i1525 = (() => {
              {
                const $t15521_i1524 = {  };
                return 9223372036854775807;
              }
            })();
            {
              const x_i1528 = (() => {
                {
                  const $t15523_i1527 = (() => {
                    {
                      const $t15522_i1526 = ($t15528 & max_v_i1525);
                      return ($t15522_i1526 >> 30);
                    }
                  })();
                  return ($t15528 ^ $t15523_i1527);
                }
              })();
              {
                const x_i1529 = (x_i1528 * 1234567891011);
                {
                  const x_i1532 = (() => {
                    {
                      const $t15525_i1531 = (() => {
                        {
                          const $t15524_i1530 = (x_i1529 & max_v_i1525);
                          return ($t15524_i1530 >> 27);
                        }
                      })();
                      return (x_i1529 ^ $t15525_i1531);
                    }
                  })();
                  {
                    const x_i1533 = (x_i1532 * 987654321);
                    {
                      const x_i1536 = (() => {
                        {
                          const $t15527_i1535 = (() => {
                            {
                              const $t15526_i1534 = (x_i1533 & max_v_i1525);
                              return ($t15526_i1534 >> 31);
                            }
                          })();
                          return (x_i1533 ^ $t15527_i1535);
                        }
                      })();
                      return x_i1536;
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
            const $t15529 = (n + 2);
            {
              const max_v_i1511 = (() => {
                {
                  const $t15521_i1510 = {  };
                  return 9223372036854775807;
                }
              })();
              {
                const x_i1514 = (() => {
                  {
                    const $t15523_i1513 = (() => {
                      {
                        const $t15522_i1512 = ($t15529 & max_v_i1511);
                        return ($t15522_i1512 >> 30);
                      }
                    })();
                    return ($t15529 ^ $t15523_i1513);
                  }
                })();
                {
                  const x_i1515 = (x_i1514 * 1234567891011);
                  {
                    const x_i1518 = (() => {
                      {
                        const $t15525_i1517 = (() => {
                          {
                            const $t15524_i1516 = (x_i1515 & max_v_i1511);
                            return ($t15524_i1516 >> 27);
                          }
                        })();
                        return (x_i1515 ^ $t15525_i1517);
                      }
                    })();
                    {
                      const x_i1519 = (x_i1518 * 987654321);
                      {
                        const x_i1522 = (() => {
                          {
                            const $t15527_i1521 = (() => {
                              {
                                const $t15526_i1520 = (x_i1519 & max_v_i1511);
                                return ($t15526_i1520 >> 31);
                              }
                            })();
                            return (x_i1519 ^ $t15527_i1521);
                          }
                        })();
                        return x_i1522;
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
              const $t15530 = (n + 3);
              {
                const max_v_i1497 = (() => {
                  {
                    const $t15521_i1496 = {  };
                    return 9223372036854775807;
                  }
                })();
                {
                  const x_i1500 = (() => {
                    {
                      const $t15523_i1499 = (() => {
                        {
                          const $t15522_i1498 = ($t15530 & max_v_i1497);
                          return ($t15522_i1498 >> 30);
                        }
                      })();
                      return ($t15530 ^ $t15523_i1499);
                    }
                  })();
                  {
                    const x_i1501 = (x_i1500 * 1234567891011);
                    {
                      const x_i1504 = (() => {
                        {
                          const $t15525_i1503 = (() => {
                            {
                              const $t15524_i1502 = (x_i1501 & max_v_i1497);
                              return ($t15524_i1502 >> 27);
                            }
                          })();
                          return (x_i1501 ^ $t15525_i1503);
                        }
                      })();
                      {
                        const x_i1505 = (x_i1504 * 987654321);
                        {
                          const x_i1508 = (() => {
                            {
                              const $t15527_i1507 = (() => {
                                {
                                  const $t15526_i1506 = (x_i1505 & max_v_i1497);
                                  return ($t15526_i1506 >> 31);
                                }
                              })();
                              return (x_i1505 ^ $t15527_i1507);
                            }
                          })();
                          return x_i1508;
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
                const $t15537 = (() => {
                  {
                    const $t15535 = (() => {
                      {
                        const $t15533 = (() => {
                          {
                            const $t15531 = (s0 === 0);
                            {
                              const $t15532 = (s1 === 0);
                              return ($t15531 && $t15532);
                            }
                          }
                        })();
                        {
                          const $t15534 = (s2 === 0);
                          return ($t15533 && $t15534);
                        }
                      }
                    })();
                    {
                      const $t15536 = (s3 === 0);
                      return ($t15535 && $t15536);
                    }
                  }
                })();
                if ($t15537 === true) {
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
        const $t15540 = (() => {
          {
            const $t15539 = (() => {
              {
                const $t15538 = rng.s1;
                return ($t15538 * 5);
              }
            })();
            {
              const $t15518_i1558 = ($t15539 << 7);
              {
                const $t15520_i1560 = ($t15539 >> 56);
                return ($t15518_i1558 | $t15520_i1560);
              }
            }
          }
        })();
        return ($t15540 * 9);
      }
    })();
    {
      const t = (() => {
        {
          const $t15541 = rng.s1;
          return ($t15541 << 17);
        }
      })();
      {
        const s2 = (() => {
          {
            const $t15542 = rng.s2;
            {
              const $t15543 = rng.s0;
              return ($t15542 ^ $t15543);
            }
          }
        })();
        {
          const s3 = (() => {
            {
              const $t15544 = rng.s3;
              {
                const $t15545 = rng.s1;
                return ($t15544 ^ $t15545);
              }
            }
          })();
          {
            const s1 = (() => {
              {
                const $t15546 = rng.s1;
                return ($t15546 ^ s2);
              }
            })();
            {
              const s0 = (() => {
                {
                  const $t15547 = rng.s0;
                  return ($t15547 ^ s3);
                }
              })();
              {
                const s2b = (s2 ^ t);
                {
                  const s3b = (() => {
                    {
                      const $t15518_i1553 = (s3 << 45);
                      {
                        const $t15520_i1555 = (s3 >> 18);
                        return ($t15518_i1553 | $t15520_i1555);
                      }
                    }
                  })();
                  {
                    const $t15548 = ({ s0: s0, s1: s1, s2: s2b, s3: s3b });
                    return { _0: result, _1: $t15548 };
                  }
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
    const $p15559 = Random$next_raw(rng);
    {
      const raw = $p15559._0;
      {
        const rng2 = $p15559._1;
        {
          const max_v = (() => {
            {
              const $t15554 = {  };
              return 9223372036854775807;
            }
          })();
          {
            const pos = (raw & max_v);
            {
              const $t15558 = (() => {
                {
                  const $t15557 = (() => {
                    {
                      const $t15556 = (() => {
                        {
                          const $t15555 = (hi - lo);
                          return ($t15555 + 1);
                        }
                      })();
                      return march_int_mod(pos, $t15556);
                    }
                  })();
                  return (lo + $t15557);
                }
              })();
              return { _0: $t15558, _1: rng2 };
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
        const $t15562 = (() => {
          {
            const $t15561 = (() => {
              {
                const $t15560 = {  };
                return march_unix_time();
              }
            })();
            return Math.trunc($t15561);
          }
        })();
        return Random$seed($t15562);
      }
    })();
    {
      const $p15563 = Random$range(rng, lo, hi);
      {
        const n = $p15563._0;
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
        const $t27323 = { _0: 0, _1: 1 };
        {
          const $t27324 = { _0: 1, _1: 1 };
          {
            const $t27325 = { _0: 2, _1: 1 };
            {
              const $t27326 = { _0: 3, _1: 1 };
              {
                const $t27327 = { $: "Nil" };
                {
                  const $t27328 = { $: "Cons", _0: $t27326, _1: $t27327 };
                  {
                    const $t27329 = { $: "Cons", _0: $t27325, _1: $t27328 };
                    {
                      const $t27330 = { $: "Cons", _0: $t27324, _1: $t27329 };
                      return { $: "Cons", _0: $t27323, _1: $t27330 };
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
        const $t27331 = { _0: 1, _1: 1 };
        {
          const $t27332 = { _0: 2, _1: 1 };
          {
            const $t27333 = { _0: 1, _1: 2 };
            {
              const $t27334 = { _0: 2, _1: 2 };
              {
                const $t27335 = { $: "Nil" };
                {
                  const $t27336 = { $: "Cons", _0: $t27334, _1: $t27335 };
                  {
                    const $t27337 = { $: "Cons", _0: $t27333, _1: $t27336 };
                    {
                      const $t27338 = { $: "Cons", _0: $t27332, _1: $t27337 };
                      return { $: "Cons", _0: $t27331, _1: $t27338 };
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
        const $t27339 = { _0: 1, _1: 1 };
        {
          const $t27340 = { _0: 0, _1: 2 };
          {
            const $t27341 = { _0: 1, _1: 2 };
            {
              const $t27342 = { _0: 2, _1: 2 };
              {
                const $t27343 = { $: "Nil" };
                {
                  const $t27344 = { $: "Cons", _0: $t27342, _1: $t27343 };
                  {
                    const $t27345 = { $: "Cons", _0: $t27341, _1: $t27344 };
                    {
                      const $t27346 = { $: "Cons", _0: $t27340, _1: $t27345 };
                      return { $: "Cons", _0: $t27339, _1: $t27346 };
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
        const $t27347 = { _0: 1, _1: 1 };
        {
          const $t27348 = { _0: 2, _1: 1 };
          {
            const $t27349 = { _0: 0, _1: 2 };
            {
              const $t27350 = { _0: 1, _1: 2 };
              {
                const $t27351 = { $: "Nil" };
                {
                  const $t27352 = { $: "Cons", _0: $t27350, _1: $t27351 };
                  {
                    const $t27353 = { $: "Cons", _0: $t27349, _1: $t27352 };
                    {
                      const $t27354 = { $: "Cons", _0: $t27348, _1: $t27353 };
                      return { $: "Cons", _0: $t27347, _1: $t27354 };
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
        const $t27355 = { _0: 0, _1: 1 };
        {
          const $t27356 = { _0: 1, _1: 1 };
          {
            const $t27357 = { _0: 1, _1: 2 };
            {
              const $t27358 = { _0: 2, _1: 2 };
              {
                const $t27359 = { $: "Nil" };
                {
                  const $t27360 = { $: "Cons", _0: $t27358, _1: $t27359 };
                  {
                    const $t27361 = { $: "Cons", _0: $t27357, _1: $t27360 };
                    {
                      const $t27362 = { $: "Cons", _0: $t27356, _1: $t27361 };
                      return { $: "Cons", _0: $t27355, _1: $t27362 };
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
        const $t27363 = { _0: 0, _1: 1 };
        {
          const $t27364 = { _0: 0, _1: 2 };
          {
            const $t27365 = { _0: 1, _1: 2 };
            {
              const $t27366 = { _0: 2, _1: 2 };
              {
                const $t27367 = { $: "Nil" };
                {
                  const $t27368 = { $: "Cons", _0: $t27366, _1: $t27367 };
                  {
                    const $t27369 = { $: "Cons", _0: $t27365, _1: $t27368 };
                    {
                      const $t27370 = { $: "Cons", _0: $t27364, _1: $t27369 };
                      return { $: "Cons", _0: $t27363, _1: $t27370 };
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
        const $t27371 = { _0: 2, _1: 1 };
        {
          const $t27372 = { _0: 0, _1: 2 };
          {
            const $t27373 = { _0: 1, _1: 2 };
            {
              const $t27374 = { _0: 2, _1: 2 };
              {
                const $t27375 = { $: "Nil" };
                {
                  const $t27376 = { $: "Cons", _0: $t27374, _1: $t27375 };
                  {
                    const $t27377 = { $: "Cons", _0: $t27373, _1: $t27376 };
                    {
                      const $t27378 = { $: "Cons", _0: $t27372, _1: $t27377 };
                      return { $: "Cons", _0: $t27371, _1: $t27378 };
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
  const $f27380 = c._0;
  const $f27381 = c._1;
  {
    const y = (() => {
      return $f27381;
    })();
    {
      const x = (() => {
        return $f27380;
      })();
      {
        const $t27379 = (3 - y);
        return { _0: $t27379, _1: x };
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
        const go_i3701 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
        {
          const $t177_i3703 = { $: "Nil" };
          return go$apply$0(go_i3701, 19, $t177_i3703);
        }
      }
    })();
    {
      const $t27430 = (() => {
        return { $: "$Clo_$lam27428$3677", _0: $lam27428$apply$3677, _1: board };
      })();
      {
        const kept_rows = (() => {
          {
            const pred_i3696 = $t27430;
            {
              const go_i3697 = { $: "$Clo_go$4561", _0: go$apply$4561, _1: pred_i3696 };
              {
                const $t299_i3698 = { $: "Nil" };
                return go$apply$4561(go_i3697, rows, $t299_i3698);
              }
            }
          }
        })();
        {
          const cleared = (() => {
            {
              const $t27432 = (() => {
                {
                  const go_i3694 = { $: "$Clo_go$4589", _0: go$apply$4589 };
                  return go$apply$4589(go_i3694, kept_rows, 0);
                }
              })();
              return (20 - $t27432);
            }
          })();
          {
            const $t27434 = { $: "$Clo_$lam27433$3678", _0: $lam27433$apply$3678, _1: board };
            {
              const kept_cells = (() => {
                {
                  const f_i3689 = $t27434;
                  {
                    const prepend_reversed_i3690 = { $: "$Clo_prepend_reversed$4676", _0: prepend_reversed$apply$4676 };
                    {
                      const go_i3691 = { $: "$Clo_go$4678", _0: go$apply$4678, _1: f_i3689, _2: prepend_reversed_i3690 };
                      {
                        const $t290_i3692 = { $: "Nil" };
                        return go$apply$4678(go_i3691, kept_rows, $t290_i3692);
                      }
                    }
                  }
                }
              })();
              {
                const $t27436 = (cleared * 10);
                {
                  const blank_cells = (() => {
                    {
                      const go_i3686 = { $: "$Clo_go$4267", _0: go$apply$4267, _1: 0 };
                      {
                        const $t172_i3687 = { $: "Nil" };
                        return go$apply$4267(go_i3686, $t27436, $t172_i3687);
                      }
                    }
                  })();
                  {
                    const new_board = (() => {
                      {
                        const $t27437 = (() => {
                          {
                            const go_i9375 = { $: "$Clo_go$4455", _0: go$apply$4455 };
                            {
                              const $t258_i9378 = (() => {
                                {
                                  const go_i4015_i9376 = { $: "$Clo_go$3740", _0: go$apply$3740 };
                                  {
                                    const $t250_i4016_i9377 = { $: "Nil" };
                                    return go$apply$3740(go_i4015_i9376, blank_cells, $t250_i4016_i9377);
                                  }
                                }
                              })();
                              return go$apply$4455(go_i9375, $t258_i9378, kept_cells);
                            }
                          }
                        })();
                        {
                          const go_i9369 = { $: "$Clo_go$4666", _0: go$apply$4666 };
                          {
                            const $t7129_i9372 = (() => {
                              {
                                const $t6923_i4114_i9370 = { $: "TrieEmpty" };
                                {
                                  const $t6924_i4115_i9371 = { $: "Nil" };
                                  return { $: "PVec", _0: 0, _1: 0, _2: $t6923_i4114_i9370, _3: $t6924_i4115_i9371 };
                                }
                              }
                            })();
                            return go$apply$4666(go_i9369, $t27437, $t7129_i9372);
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
    const $t27474 = Dom$find("game-state");
    switch ($t27474.$) {
      case "Some": {
        const $f27475 = $t27474._0;
        {
          const el = $f27475;
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
    const $t27476 = Dom$get_attr(el, name);
    switch ($t27476.$) {
      case "Some": {
        const $f27478 = $t27476._0;
        {
          const s = $f27478;
          {
            const $t27477 = (() => {
              {
                const $rc_781 = march_string_to_int(s);
                return $rc_781;
              }
            })();
            return Option$unwrap_or$Option_Int$Int($t27477, _default);
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
    const $t27479 = Dom$get_attr(el, name);
    switch ($t27479.$) {
      case "Some": {
        const $f27480 = $t27479._0;
        {
          const s = $f27480;
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
    const $t27481 = (n <= 0);
    if ($t27481 === true) {
      return cells;
    } else {
      return (() => {
        {
          const $t27482 = (() => {
            {
              const f_i3667_i9380 = TetrisLogic$rotate_cell$clo;
              {
                const go_i3668_i9381 = { $: "$Clo_go$4668", _0: go$apply$4668, _1: f_i3667_i9380 };
                {
                  const $t267_i3669_i9382 = { $: "Nil" };
                  return go$apply$4668(go_i3668_i9381, cells, $t267_i3669_i9382);
                }
              }
            }
          })();
          {
            const $t27483 = (n - 1);
            return rotate_n($t27482, $t27483);
          }
        }
      })();
    }
  }
}
const rotate_n$clo = { _0: ($_, cells, n) => rotate_n(cells, n) };

function set_text_if_found(id, text) {
  {
    const $t27525 = Dom$find(id);
    switch ($t27525.$) {
      case "None": {
        return {  };
      }
      case "Some": {
        const $f27526 = $t27525._0;
        {
          const el = $f27526;
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
          const $t27527 = (() => {
            return get_str_attr(el, "data-over", "false");
          })();
          return ($t27527 === "true");
        }
      })();
      if (over === true) {
        return {  };
      } else {
        return (() => {
          {
            const board = (() => {
              {
                const $t27528 = (() => {
                  return get_str_attr(el, "data-board", "");
                })();
                {
                  const $t27529 = (() => {
                    {
                      const $rc_789 = (() => {
                        {
                          const $t27443_i9421 = march_string_split($t27528, ",");
                          {
                            const $t27446_i9422 = { $: "$Clo_$lam27444$3680", _0: $lam27444$apply$3680 };
                            {
                              const f_i3711_i9423 = $t27446_i9422;
                              {
                                const go_i3712_i9424 = { $: "$Clo_go$4680", _0: go$apply$4680, _1: f_i3711_i9423 };
                                {
                                  const $t267_i3713_i9425 = { $: "Nil" };
                                  return go$apply$4680(go_i3712_i9424, $t27443_i9421, $t267_i3713_i9425);
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
                    const go_i9416 = { $: "$Clo_go$4666", _0: go$apply$4666 };
                    {
                      const $t7129_i9419 = (() => {
                        {
                          const $t6923_i4114_i9417 = { $: "TrieEmpty" };
                          {
                            const $t6924_i4115_i9418 = { $: "Nil" };
                            return { $: "PVec", _0: 0, _1: 0, _2: $t6923_i4114_i9417, _3: $t6924_i4115_i9418 };
                          }
                        }
                      })();
                      return go$apply$4666(go_i9416, $t27529, $t7129_i9419);
                    }
                  }
                }
              }
            })();
            {
              const piece = (() => {
                {
                  const $t27530 = (() => {
                    return get_str_attr(el, "data-piece", "I");
                  })();
                  {
                    let $rc_788;
                    if ($t27530 === "I") {
                      $rc_788 = { $: "I" };
                    } else if ($t27530 === "O") {
                      $rc_788 = { $: "O" };
                    } else if ($t27530 === "T") {
                      $rc_788 = { $: "T" };
                    } else if ($t27530 === "S") {
                      $rc_788 = { $: "S" };
                    } else if ($t27530 === "Z") {
                      $rc_788 = { $: "Z" };
                    } else if ($t27530 === "J") {
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
                          const $t27531 = (() => {
                            return get_str_attr(el, "data-next", "O");
                          })();
                          {
                            let $rc_787;
                            if ($t27531 === "I") {
                              $rc_787 = { $: "I" };
                            } else if ($t27531 === "O") {
                              $rc_787 = { $: "O" };
                            } else if ($t27531 === "T") {
                              $rc_787 = { $: "T" };
                            } else if ($t27531 === "S") {
                              $rc_787 = { $: "S" };
                            } else if ($t27531 === "Z") {
                              $rc_787 = { $: "Z" };
                            } else if ($t27531 === "J") {
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
                            const $t27532 = f._0(f, board, piece, rot, x, y, next, score, lines);
                            const $f27551 = $t27532._0;
                            const $f27552 = $t27532._1;
                            const $f27553 = $t27532._2;
                            const $f27554 = $t27532._3;
                            const $f27555 = $t27532._4;
                            const $f27556 = $t27532._5;
                            const $f27557 = $t27532._6;
                            const $f27558 = $t27532._7;
                            const $f27559 = $t27532._8;
                            {
                              const over2 = (() => {
                                return $f27559;
                              })();
                              {
                                const lines2 = (() => {
                                  return $f27558;
                                })();
                                {
                                  const score2 = (() => {
                                    return $f27557;
                                  })();
                                  {
                                    const next2 = (() => {
                                      return $f27556;
                                    })();
                                    {
                                      const y2 = (() => {
                                        return $f27555;
                                      })();
                                      {
                                        const x2 = (() => {
                                          return $f27554;
                                        })();
                                        {
                                          const rot2 = (() => {
                                            return $f27553;
                                          })();
                                          {
                                            const piece2 = (() => {
                                              return $f27552;
                                            })();
                                            {
                                              const board2 = (() => {
                                                return $f27551;
                                              })();
                                              (() => {
                                                {
                                                  const $t27486_i9411 = (() => {
                                                    {
                                                      const go_i3747_i9408 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
                                                      {
                                                        const $t177_i3749_i9410 = { $: "Nil" };
                                                        return go$apply$0(go_i3747_i9408, 19, $t177_i3749_i9410);
                                                      }
                                                    }
                                                  })();
                                                  {
                                                    const $t27500_i9412 = { $: "$Clo_$lam27487$3687", _0: $lam27487$apply$3687, _1: board2 };
                                                    {
                                                      const f_i3743_i9413 = $t27500_i9412;
                                                      {
                                                        const go_i3744_i9414 = { $: "$Clo_go$4683", _0: go$apply$4683, _1: f_i3743_i9413 };
                                                        return go$apply$4683(go_i3744_i9414, $t27486_i9411);
                                                      }
                                                    }
                                                  }
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27533 = (!over2);
                                                  if ($t27533 === true) {
                                                    return (() => {
                                                      {
                                                        const base_cells_i9402 = TetrisLogic$piece_cells(piece2);
                                                        {
                                                          const rotated_i9403 = rotate_n(base_cells_i9402, rot2);
                                                          {
                                                            const $t27524_i9404 = { $: "$Clo_$lam27501$3689", _0: $lam27501$apply$3689, _1: x2, _2: y2, _3: piece2 };
                                                            {
                                                              const f_i3751_i9405 = $t27524_i9404;
                                                              {
                                                                const go_i3752_i9406 = { $: "$Clo_go$4685", _0: go$apply$4685, _1: f_i3751_i9405 };
                                                                return go$apply$4685(go_i3752_i9406, rotated_i9403);
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
                                                  const $t27535 = (() => {
                                                    {
                                                      const $t27534 = String(score2);
                                                      {
                                                        const $rc_786 = ("Score: " + $t27534);
                                                        return $rc_786;
                                                      }
                                                    }
                                                  })();
                                                  return set_text_if_found("score", $t27535);
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27538 = (() => {
                                                    {
                                                      const $t27537 = (() => {
                                                        {
                                                          const $t27536 = TetrisLogic$level_for_lines(lines2);
                                                          return String($t27536);
                                                        }
                                                      })();
                                                      {
                                                        const $rc_785 = ("Level: " + $t27537);
                                                        return $rc_785;
                                                      }
                                                    }
                                                  })();
                                                  return set_text_if_found("level", $t27538);
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27540 = (() => {
                                                    {
                                                      let $t27539;
                                                      switch (next2.$) {
                                                        case "I": {
                                                          $t27539 = "I";
                                                          break;
                                                        }
                                                        case "O": {
                                                          $t27539 = "O";
                                                          break;
                                                        }
                                                        case "T": {
                                                          $t27539 = "T";
                                                          break;
                                                        }
                                                        case "S": {
                                                          $t27539 = "S";
                                                          break;
                                                        }
                                                        case "Z": {
                                                          $t27539 = "Z";
                                                          break;
                                                        }
                                                        case "J": {
                                                          $t27539 = "J";
                                                          break;
                                                        }
                                                        case "L": {
                                                          $t27539 = "L";
                                                          break;
                                                        }
                                                        default: {
                                                          $t27539 = (() => { throw new Error("non-exhaustive pattern match"); })();
                                                          break;
                                                        }
                                                      }
                                                      {
                                                        const $rc_784 = ("Next: " + $t27539);
                                                        return $rc_784;
                                                      }
                                                    }
                                                  })();
                                                  return set_text_if_found("next", $t27540);
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
                                                  const $t27542 = (() => {
                                                    {
                                                      const $t27541 = (() => {
                                                        {
                                                          const $t7119_i9392 = { $: "Nil" };
                                                          {
                                                            const $t7121_i9393 = { $: "$Clo_$lam7120$4687", _0: $lam7120$apply$4687 };
                                                            {
                                                              const rev_i9394 = Array$fold_left$PVec_Int$List_V__22334$Fn_List_V__22335_V__22335_List_V__22335(board2, $t7119_i9392, $t7121_i9393);
                                                              {
                                                                const go_i4125_i9395 = { $: "$Clo_go$5110", _0: go$apply$5110 };
                                                                {
                                                                  const $t6726_i4126_i9396 = { $: "Nil" };
                                                                  return go$apply$5110(go_i4125_i9395, rev_i9394, $t6726_i4126_i9396);
                                                                }
                                                              }
                                                            }
                                                          }
                                                        }
                                                      })();
                                                      {
                                                        const $t27441_i9386 = { $: "$Clo_$lam27440$3679", _0: $lam27440$apply$3679 };
                                                        {
                                                          const $t27442_i9390 = (() => {
                                                            {
                                                              const f_i3707_i9387 = $t27441_i9386;
                                                              {
                                                                const go_i3708_i9388 = { $: "$Clo_go$4101", _0: go$apply$4101, _1: f_i3707_i9387 };
                                                                {
                                                                  const $t267_i3709_i9389 = { $: "Nil" };
                                                                  return go$apply$4101(go_i3708_i9388, $t27541, $t267_i3709_i9389);
                                                                }
                                                              }
                                                            }
                                                          })();
                                                          return march_string_join($t27442_i9390, ",");
                                                        }
                                                      }
                                                    }
                                                  })();
                                                  return Dom$set_attr(el, "data-board", $t27542);
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27543 = (() => {
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
                                                  return Dom$set_attr(el, "data-piece", $t27543);
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27544 = String(rot2);
                                                  return Dom$set_attr(el, "data-rot", $t27544);
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27545 = String(x2);
                                                  return Dom$set_attr(el, "data-x", $t27545);
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27546 = String(y2);
                                                  return Dom$set_attr(el, "data-y", $t27546);
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27547 = (() => {
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
                                                  return Dom$set_attr(el, "data-next", $t27547);
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27548 = String(score2);
                                                  return Dom$set_attr(el, "data-score", $t27548);
                                                }
                                              })();
                                              (() => {
                                                {
                                                  const $t27549 = String(lines2);
                                                  return Dom$set_attr(el, "data-lines", $t27549);
                                                }
                                              })();
                                              {
                                                let $t27550;
                                                if (over2 === true) {
                                                  $t27550 = "true";
                                                } else {
                                                  $t27550 = "false";
                                                }
                                                return Dom$set_attr(el, "data-over", $t27550);
                                              }
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
    const $t27592 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t27592, rot);
      {
        const locked = (() => {
          {
            let $t27593;
            switch (piece.$) {
              case "I": {
                $t27593 = 1;
                break;
              }
              case "O": {
                $t27593 = 2;
                break;
              }
              case "T": {
                $t27593 = 3;
                break;
              }
              case "S": {
                $t27593 = 4;
                break;
              }
              case "Z": {
                $t27593 = 5;
                break;
              }
              case "J": {
                $t27593 = 6;
                break;
              }
              case "L": {
                $t27593 = 7;
                break;
              }
              default: {
                $t27593 = (() => { throw new Error("non-exhaustive pattern match"); })();
                break;
              }
            }
            {
              const $t27415_i3777 = { $: "$Clo_$lam27406$4688", _0: $lam27406$apply$4688, _1: $t27593, _2: x, _3: y };
              return List$fold_left$List_T_Int_Int$PVec_Int$Fn_PVec_Int_T_Int_Int_PVec_Int(cells, board, $t27415_i3777);
            }
          }
        })();
        {
          const $t27594 = TetrisLogic$clear_lines(locked);
          const $f27623 = $t27594._0;
          const $f27624 = $t27594._1;
          {
            const n = (() => {
              return $f27624;
            })();
            {
              const cleared_board = (() => {
                return $f27623;
              })();
              {
                const new_score = (() => {
                  {
                    let $t27595;
                    if (n === 1) {
                      $t27595 = 100;
                    } else if (n === 2) {
                      $t27595 = 300;
                    } else if (n === 3) {
                      $t27595 = 500;
                    } else if (n === 4) {
                      $t27595 = 800;
                    } else {
                      $t27595 = 0;
                    }
                    return (score + $t27595);
                  }
                })();
                {
                  const new_lines = (lines + n);
                  {
                    const $t27596 = (() => {
                      {
                        const cells_i9428 = TetrisLogic$piece_cells(next);
                        {
                          const over_i9430 = (() => {
                            {
                              const $t27405_i3741_i9429 = { $: "$Clo_$lam27394$3673", _0: $lam27394$apply$3673, _1: cleared_board, _2: 3, _3: 0 };
                              return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells_i9428, $t27405_i3741_i9429);
                            }
                          })();
                          {
                            const $t27484_i9447 = (() => {
                              {
                                const $t27459_i3721_i9431 = { $: "I" };
                                {
                                  const $t27460_i3722_i9432 = { $: "O" };
                                  {
                                    const $t27461_i3723_i9433 = { $: "T" };
                                    {
                                      const $t27462_i3724_i9434 = { $: "S" };
                                      {
                                        const $t27463_i3725_i9435 = { $: "Z" };
                                        {
                                          const $t27464_i3726_i9436 = { $: "J" };
                                          {
                                            const $t27465_i3727_i9437 = { $: "L" };
                                            {
                                              const $t27466_i3728_i9438 = { $: "Nil" };
                                              {
                                                const $t27467_i3729_i9439 = { $: "Cons", _0: $t27465_i3727_i9437, _1: $t27466_i3728_i9438 };
                                                {
                                                  const $t27468_i3730_i9440 = { $: "Cons", _0: $t27464_i3726_i9436, _1: $t27467_i3729_i9439 };
                                                  {
                                                    const $t27469_i3731_i9441 = { $: "Cons", _0: $t27463_i3725_i9435, _1: $t27468_i3730_i9440 };
                                                    {
                                                      const $t27470_i3732_i9442 = { $: "Cons", _0: $t27462_i3724_i9434, _1: $t27469_i3731_i9441 };
                                                      {
                                                        const $t27471_i3733_i9443 = { $: "Cons", _0: $t27461_i3723_i9433, _1: $t27470_i3732_i9442 };
                                                        {
                                                          const $t27472_i3734_i9444 = { $: "Cons", _0: $t27460_i3722_i9432, _1: $t27471_i3733_i9443 };
                                                          {
                                                            const pieces_i3735_i9445 = { $: "Cons", _0: $t27459_i3721_i9431, _1: $t27472_i3734_i9444 };
                                                            {
                                                              const $t27473_i3736_i9446 = Random$int(0, 7);
                                                              return List$nth$List_Piece$Int(pieces_i3735_i9445, $t27473_i3736_i9446);
                                                            }
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
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
                            return { _0: next, _1: 0, _2: 3, _3: 0, _4: $t27484_i9447, _5: over_i9430 };
                          }
                        }
                      }
                    })();
                    const $f27597 = $t27596._0;
                    const $f27598 = $t27596._1;
                    const $f27599 = $t27596._2;
                    const $f27600 = $t27596._3;
                    const $f27601 = $t27596._4;
                    const $f27602 = $t27596._5;
                    {
                      const over = (() => {
                        return $f27602;
                      })();
                      {
                        const next2 = (() => {
                          return $f27601;
                        })();
                        {
                          const y2 = (() => {
                            return $f27600;
                          })();
                          {
                            const x2 = (() => {
                              return $f27599;
                            })();
                            {
                              const rot2 = (() => {
                                return $f27598;
                              })();
                              {
                                const piece2 = (() => {
                                  return $f27597;
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
    const $t27649 = (() => {
      {
        const $t27648 = (cur_y + 1);
        {
          const $t27405_i3782 = { $: "$Clo_$lam27394$3673", _0: $lam27394$apply$3673, _1: board, _2: x, _3: $t27648 };
          return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t27405_i3782);
        }
      }
    })();
    if ($t27649 === true) {
      return cur_y;
    } else {
      return (() => {
        {
          const $t27650 = (cur_y + 1);
          return fall_from(board, cells, x, $t27650);
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
          const $t27322_i9562 = (() => {
            {
              const go_i3660_i9560 = { $: "$Clo_go$4267", _0: go$apply$4267, _1: 0 };
              {
                const $t172_i3661_i9561 = { $: "Nil" };
                return go$apply$4267(go_i3660_i9560, 200, $t172_i3661_i9561);
              }
            }
          })();
          {
            const go_i9364_i9563 = { $: "$Clo_go$4666", _0: go$apply$4666 };
            {
              const $t7129_i9367_i9566 = (() => {
                {
                  const $t6923_i4114_i9365_i9564 = { $: "TrieEmpty" };
                  {
                    const $t6924_i4115_i9366_i9565 = { $: "Nil" };
                    return { $: "PVec", _0: 0, _1: 0, _2: $t6923_i4114_i9365_i9564, _3: $t6924_i4115_i9366_i9565 };
                  }
                }
              })();
              return go$apply$4666(go_i9364_i9563, $t27322_i9562, $t7129_i9367_i9566);
            }
          }
        }
      })();
      {
        const $t27655 = (() => {
          {
            const $t27654 = (() => {
              {
                const $t27459_i3784 = { $: "I" };
                {
                  const $t27460_i3785 = { $: "O" };
                  {
                    const $t27461_i3786 = { $: "T" };
                    {
                      const $t27462_i3787 = { $: "S" };
                      {
                        const $t27463_i3788 = { $: "Z" };
                        {
                          const $t27464_i3789 = { $: "J" };
                          {
                            const $t27465_i3790 = { $: "L" };
                            {
                              const $t27466_i3791 = { $: "Nil" };
                              {
                                const $t27467_i3792 = { $: "Cons", _0: $t27465_i3790, _1: $t27466_i3791 };
                                {
                                  const $t27468_i3793 = { $: "Cons", _0: $t27464_i3789, _1: $t27467_i3792 };
                                  {
                                    const $t27469_i3794 = { $: "Cons", _0: $t27463_i3788, _1: $t27468_i3793 };
                                    {
                                      const $t27470_i3795 = { $: "Cons", _0: $t27462_i3787, _1: $t27469_i3794 };
                                      {
                                        const $t27471_i3796 = { $: "Cons", _0: $t27461_i3786, _1: $t27470_i3795 };
                                        {
                                          const $t27472_i3797 = { $: "Cons", _0: $t27460_i3785, _1: $t27471_i3796 };
                                          {
                                            const pieces_i3798 = { $: "Cons", _0: $t27459_i3784, _1: $t27472_i3797 };
                                            {
                                              const $t27473_i3799 = Random$int(0, 7);
                                              return List$nth$List_Piece$Int(pieces_i3798, $t27473_i3799);
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
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
              const cells_i9483 = TetrisLogic$piece_cells($t27654);
              {
                const over_i9485 = (() => {
                  {
                    const $t27405_i3741_i9484 = { $: "$Clo_$lam27394$3673", _0: $lam27394$apply$3673, _1: board, _2: 3, _3: 0 };
                    return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells_i9483, $t27405_i3741_i9484);
                  }
                })();
                {
                  const $t27484_i9502 = (() => {
                    {
                      const $t27459_i3721_i9486 = { $: "I" };
                      {
                        const $t27460_i3722_i9487 = { $: "O" };
                        {
                          const $t27461_i3723_i9488 = { $: "T" };
                          {
                            const $t27462_i3724_i9489 = { $: "S" };
                            {
                              const $t27463_i3725_i9490 = { $: "Z" };
                              {
                                const $t27464_i3726_i9491 = { $: "J" };
                                {
                                  const $t27465_i3727_i9492 = { $: "L" };
                                  {
                                    const $t27466_i3728_i9493 = { $: "Nil" };
                                    {
                                      const $t27467_i3729_i9494 = { $: "Cons", _0: $t27465_i3727_i9492, _1: $t27466_i3728_i9493 };
                                      {
                                        const $t27468_i3730_i9495 = { $: "Cons", _0: $t27464_i3726_i9491, _1: $t27467_i3729_i9494 };
                                        {
                                          const $t27469_i3731_i9496 = { $: "Cons", _0: $t27463_i3725_i9490, _1: $t27468_i3730_i9495 };
                                          {
                                            const $t27470_i3732_i9497 = { $: "Cons", _0: $t27462_i3724_i9489, _1: $t27469_i3731_i9496 };
                                            {
                                              const $t27471_i3733_i9498 = { $: "Cons", _0: $t27461_i3723_i9488, _1: $t27470_i3732_i9497 };
                                              {
                                                const $t27472_i3734_i9499 = { $: "Cons", _0: $t27460_i3722_i9487, _1: $t27471_i3733_i9498 };
                                                {
                                                  const pieces_i3735_i9500 = { $: "Cons", _0: $t27459_i3721_i9486, _1: $t27472_i3734_i9499 };
                                                  {
                                                    const $t27473_i3736_i9501 = Random$int(0, 7);
                                                    return List$nth$List_Piece$Int(pieces_i3735_i9500, $t27473_i3736_i9501);
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
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
                  return { _0: $t27654, _1: 0, _2: 3, _3: 0, _4: $t27484_i9502, _5: over_i9485 };
                }
              }
            }
          }
        })();
        const $f27665 = $t27655._0;
        const $f27666 = $t27655._1;
        const $f27667 = $t27655._2;
        const $f27668 = $t27655._3;
        const $f27669 = $t27655._4;
        const $f27670 = $t27655._5;
        (() => {
          return $f27670;
        })();
        {
          const next = (() => {
            return $f27669;
          })();
          {
            const y = (() => {
              return $f27668;
            })();
            {
              const x = (() => {
                return $f27667;
              })();
              {
                const rot = (() => {
                  return $f27666;
                })();
                {
                  const piece = (() => {
                    return $f27665;
                  })();
                  (() => {
                    {
                      const $t27486_i9477 = (() => {
                        {
                          const go_i3747_i9474 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
                          {
                            const $t177_i3749_i9476 = { $: "Nil" };
                            return go$apply$0(go_i3747_i9474, 19, $t177_i3749_i9476);
                          }
                        }
                      })();
                      {
                        const $t27500_i9478 = { $: "$Clo_$lam27487$3687", _0: $lam27487$apply$3687, _1: board };
                        {
                          const f_i3743_i9479 = $t27500_i9478;
                          {
                            const go_i3744_i9480 = { $: "$Clo_go$4683", _0: go$apply$4683, _1: f_i3743_i9479 };
                            return go$apply$4683(go_i3744_i9480, $t27486_i9477);
                          }
                        }
                      }
                    }
                  })();
                  (() => {
                    {
                      const base_cells_i9468 = TetrisLogic$piece_cells(piece);
                      {
                        const rotated_i9469 = rotate_n(base_cells_i9468, rot);
                        {
                          const $t27524_i9470 = { $: "$Clo_$lam27501$3689", _0: $lam27501$apply$3689, _1: x, _2: y, _3: piece };
                          {
                            const f_i3751_i9471 = $t27524_i9470;
                            {
                              const go_i3752_i9472 = { $: "$Clo_go$4685", _0: go$apply$4685, _1: f_i3751_i9471 };
                              return go$apply$4685(go_i3752_i9472, rotated_i9469);
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
                      const $t27657 = (() => {
                        {
                          let $t27656;
                          switch (next.$) {
                            case "I": {
                              $t27656 = "I";
                              break;
                            }
                            case "O": {
                              $t27656 = "O";
                              break;
                            }
                            case "T": {
                              $t27656 = "T";
                              break;
                            }
                            case "S": {
                              $t27656 = "S";
                              break;
                            }
                            case "Z": {
                              $t27656 = "Z";
                              break;
                            }
                            case "J": {
                              $t27656 = "J";
                              break;
                            }
                            case "L": {
                              $t27656 = "L";
                              break;
                            }
                            default: {
                              $t27656 = (() => { throw new Error("non-exhaustive pattern match"); })();
                              break;
                            }
                          }
                          {
                            const $rc_792 = ("Next: " + $t27656);
                            return $rc_792;
                          }
                        }
                      })();
                      return set_text_if_found("next", $t27657);
                    }
                  })();
                  set_text_if_found("game-over", "");
                  (() => {
                    {
                      const $t27659 = (() => {
                        {
                          const $t27658 = (() => {
                            {
                              const $t7119_i9458 = { $: "Nil" };
                              {
                                const $t7121_i9459 = { $: "$Clo_$lam7120$4687", _0: $lam7120$apply$4687 };
                                {
                                  const rev_i9460 = Array$fold_left$PVec_Int$List_V__22334$Fn_List_V__22335_V__22335_List_V__22335(board, $t7119_i9458, $t7121_i9459);
                                  {
                                    const go_i4125_i9461 = { $: "$Clo_go$5110", _0: go$apply$5110 };
                                    {
                                      const $t6726_i4126_i9462 = { $: "Nil" };
                                      return go$apply$5110(go_i4125_i9461, rev_i9460, $t6726_i4126_i9462);
                                    }
                                  }
                                }
                              }
                            }
                          })();
                          {
                            const $t27441_i9452 = { $: "$Clo_$lam27440$3679", _0: $lam27440$apply$3679 };
                            {
                              const $t27442_i9456 = (() => {
                                {
                                  const f_i3707_i9453 = $t27441_i9452;
                                  {
                                    const go_i3708_i9454 = { $: "$Clo_go$4101", _0: go$apply$4101, _1: f_i3707_i9453 };
                                    {
                                      const $t267_i3709_i9455 = { $: "Nil" };
                                      return go$apply$4101(go_i3708_i9454, $t27658, $t267_i3709_i9455);
                                    }
                                  }
                                }
                              })();
                              return march_string_join($t27442_i9456, ",");
                            }
                          }
                        }
                      })();
                      return Dom$set_attr(el, "data-board", $t27659);
                    }
                  })();
                  (() => {
                    {
                      const $t27660 = (() => {
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
                      return Dom$set_attr(el, "data-piece", $t27660);
                    }
                  })();
                  (() => {
                    {
                      const $t27661 = String(rot);
                      return Dom$set_attr(el, "data-rot", $t27661);
                    }
                  })();
                  (() => {
                    {
                      const $t27662 = String(x);
                      return Dom$set_attr(el, "data-x", $t27662);
                    }
                  })();
                  (() => {
                    {
                      const $t27663 = String(y);
                      return Dom$set_attr(el, "data-y", $t27663);
                    }
                  })();
                  (() => {
                    {
                      const $t27664 = (() => {
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
                      return Dom$set_attr(el, "data-next", $t27664);
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
    const $t27704 = Dom$event_key(ev);
    if ($t27704 === "ArrowLeft") {
      return (() => {
        {
          const $t27705 = (-1);
          {
            const $t27642_i3810 = { $: "$Clo_$lam27635$3717", _0: $lam27635$apply$3717, _1: $t27705, _2: 0 };
            return with_state($t27642_i3810);
          }
        }
      })();
    } else if ($t27704 === "ArrowRight") {
      return (() => {
        {
          const $t27642_i3813 = { $: "$Clo_$lam27635$3717", _0: $lam27635$apply$3717, _1: 1, _2: 0 };
          return with_state($t27642_i3813);
        }
      })();
    } else if ($t27704 === "ArrowDown") {
      return (() => {
        {
          const $t27642_i3816 = { $: "$Clo_$lam27635$3717", _0: $lam27635$apply$3717, _1: 0, _2: 1 };
          return with_state($t27642_i3816);
        }
      })();
    } else if ($t27704 === "ArrowUp") {
      return (() => {
        {
          const $t27647_i3817 = { $: "$Clo_$lam27643$3718", _0: $lam27643$apply$3718 };
          return with_state($t27647_i3817);
        }
      })();
    } else if ($t27704 === " ") {
      return (() => {
        {
          const $t27653_i3818 = { $: "$Clo_$lam27651$3719", _0: $lam27651$apply$3719 };
          return with_state($t27653_i3818);
        }
      })();
    } else if ($t27704 === "r") {
      return (() => {
        return restart();
      })();
    } else if ($t27704 === "R") {
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
    const $t27720 = Dom$find("board");
    switch ($t27720.$) {
      case "None": {
        return {  };
      }
      case "Some": {
        const $f27726 = $t27720._0;
        {
          const board_el = $f27726;
          (() => {
            {
              const $t27692_i9507 = (() => {
                {
                  const go_i3805_i9504 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
                  {
                    const $t177_i3807_i9506 = { $: "Nil" };
                    return go$apply$0(go_i3805_i9504, 19, $t177_i3807_i9506);
                  }
                }
              })();
              {
                const $t27703_i9508 = { $: "$Clo_$lam27693$3729", _0: $lam27693$apply$3729, _1: board_el };
                {
                  const f_i3801_i9509 = $t27703_i9508;
                  {
                    const go_i3802_i9510 = { $: "$Clo_go$4683", _0: go$apply$4683, _1: f_i3801_i9509 };
                    return go$apply$4683(go_i3802_i9510, $t27692_i9507);
                  }
                }
              }
            }
          })();
          restart();
          (() => {
            {
              const $t27721 = dom_body();
              {
                const $t27723 = { $: "$Clo_$lam27722$3738", _0: $lam27722$apply$3738 };
                return Dom$listen($t27721, "keydown", $t27723);
              }
            }
          })();
          {
            const $t27725 = { $: "$Clo_$lam27724$3739", _0: $lam27724$apply$3739 };
            return Dom$set_interval(500, $t27725);
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
                          const go_i4119 = { $: "$Clo_go$5108", _0: go$apply$5108 };
                          return go$apply$5108(go_i4119, tail, 0);
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
                    const go_i4595 = { $: "$Clo_go$5108", _0: go$apply$5108 };
                    return go$apply$5108(go_i4595, tail, 0);
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
                              const go_i4592 = { $: "$Clo_go$5258", _0: go$apply$5258, _1: elem };
                              {
                                const $t6768_i4593 = { $: "Nil" };
                                return go$apply$5258(go_i4592, tail, $t6768_i4593);
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
              const $t6809_i4976 = (idx >> shift);
              return ($t6809_i4976 & 31);
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
                          const go_i4994 = { $: "$Clo_go$5108", _0: go$apply$5108 };
                          return go$apply$5108(go_i4994, tail, 0);
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
                                      const rev_onto_i4990 = { $: "$Clo_rev_onto$5420", _0: rev_onto$apply$5420 };
                                      {
                                        const go_i4991 = { $: "$Clo_go$5422", _0: go$apply$5422, _1: rev_onto_i4990, _2: val };
                                        {
                                          const $t6752_i4992 = { $: "Nil" };
                                          return go$apply$5422(go_i4991, tail, $t6982, $t6752_i4992);
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
                                    const ascend_i4984 = { $: "$Clo_ascend$5424", _0: ascend$apply$5424 };
                                    {
                                      const descend_i4985 = { $: "$Clo_descend$5426", _0: descend$apply$5426, _1: ascend_i4984, _2: idx, _3: val };
                                      {
                                        const $t6832_i4986 = { $: "Nil" };
                                        return descend$apply$5426(descend_i4985, root, shift, $t6832_i4986);
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
                        const go_i5041 = { $: "$Clo_go$5451", _0: go$apply$5451 };
                        {
                          const $t6838_i5042 = { $: "TrieLeaf", _0: leaf_values };
                          return go$apply$5451(go_i5041, shift, $t6838_i5042);
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

function $lam27394$apply$3673($clo, c) {
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
        const $f27399 = c._0;
        const $f27400 = c._1;
        {
          const dy = (() => {
            return $f27400;
          })();
          {
            const dx = (() => {
              return $f27399;
            })();
            {
              const x = (origin_x + dx);
              {
                const y = (origin_y + dy);
                {
                  const $t27396 = (() => {
                    {
                      const $t27395 = (() => {
                        {
                          const $t27391_i9520 = (() => {
                            {
                              const $t27389_i9518 = (() => {
                                {
                                  const $t27386_i9516 = (x >= 0);
                                  {
                                    const $t27388_i9517 = (x < 10);
                                    return ($t27386_i9516 && $t27388_i9517);
                                  }
                                }
                              })();
                              {
                                const $t27390_i9519 = (y >= 0);
                                return ($t27389_i9518 && $t27390_i9519);
                              }
                            }
                          })();
                          {
                            const $t27393_i9521 = (y < 20);
                            return ($t27391_i9520 && $t27393_i9521);
                          }
                        }
                      })();
                      return (!$t27395);
                    }
                  })();
                  if ($t27396 === true) {
                    return true;
                  } else {
                    return (() => {
                      {
                        const $t27398 = (() => {
                          {
                            const $t27397 = (() => {
                              {
                                const $t27318_i9513 = (y * 10);
                                return ($t27318_i9513 + x);
                              }
                            })();
                            return Array$get$PVec_Int$Int(board, $t27397);
                          }
                        })();
                        return ($t27398 !== 0);
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
const $lam27394$apply$3673$clo = { _0: ($_, $clo, c) => $lam27394$apply$3673($clo, c) };

function $lam27418$apply$3675($clo, x) {
  {
    const board = (() => {
      return $clo._1;
    })();
    {
      const y = (() => {
        return $clo._2;
      })();
      {
        const $t27420 = (() => {
          {
            const $t27419 = (() => {
              {
                const $t27318_i9524 = (y * 10);
                return ($t27318_i9524 + x);
              }
            })();
            return Array$get$PVec_Int$Int(board, $t27419);
          }
        })();
        return ($t27420 !== 0);
      }
    }
  }
}
const $lam27418$apply$3675$clo = { _0: ($_, $clo, x) => $lam27418$apply$3675($clo, x) };

function $lam27424$apply$3676($clo, x) {
  {
    const board = (() => {
      return $clo._1;
    })();
    {
      const y = (() => {
        return $clo._2;
      })();
      {
        const $t27425 = (() => {
          {
            const $t27318_i9527 = (y * 10);
            return ($t27318_i9527 + x);
          }
        })();
        return Array$get$PVec_Int$Int(board, $t27425);
      }
    }
  }
}
const $lam27424$apply$3676$clo = { _0: ($_, $clo, x) => $lam27424$apply$3676($clo, x) };

function $lam27428$apply$3677($clo, y) {
  {
    const board = (() => {
      return $clo._1;
    })();
    {
      const $t27429 = (() => {
        {
          const $t27417_i9533 = (() => {
            {
              const go_i3672_i9530 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
              {
                const $t177_i3674_i9532 = { $: "Nil" };
                return go$apply$0(go_i3672_i9530, 9, $t177_i3674_i9532);
              }
            }
          })();
          {
            const $t27421_i9534 = { $: "$Clo_$lam27418$3675", _0: $lam27418$apply$3675, _1: board, _2: y };
            return List$all$List_Int$Fn_Int_Bool($t27417_i9533, $t27421_i9534);
          }
        }
      })();
      return (!$t27429);
    }
  }
}
const $lam27428$apply$3677$clo = { _0: ($_, $clo, y) => $lam27428$apply$3677($clo, y) };

function $lam27433$apply$3678($clo, y) {
  {
    const board = (() => {
      return $clo._1;
    })();
    {
      const $t27423_i9540 = (() => {
        {
          const go_i3681_i9537 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
          {
            const $t177_i3683_i9539 = { $: "Nil" };
            return go$apply$0(go_i3681_i9537, 9, $t177_i3683_i9539);
          }
        }
      })();
      {
        const $t27426_i9541 = { $: "$Clo_$lam27424$3676", _0: $lam27424$apply$3676, _1: board, _2: y };
        {
          const f_i3676_i9542 = $t27426_i9541;
          {
            const go_i3677_i9543 = { $: "$Clo_go$4256", _0: go$apply$4256, _1: f_i3676_i9542 };
            {
              const $t267_i3678_i9544 = { $: "Nil" };
              return go$apply$4256(go_i3677_i9543, $t27423_i9540, $t267_i3678_i9544);
            }
          }
        }
      }
    }
  }
}
const $lam27433$apply$3678$clo = { _0: ($_, $clo, y) => $lam27433$apply$3678($clo, y) };

function $lam27440$apply$3679($clo, x) {
  return String(x);
}
const $lam27440$apply$3679$clo = { _0: ($_, $clo, x) => $lam27440$apply$3679($clo, x) };

function $lam27444$apply$3680($clo, x) {
  {
    const $t27445 = march_string_to_int(x);
    return Option$unwrap_or$Option_Int$Int($t27445, 0);
  }
}
const $lam27444$apply$3680$clo = { _0: ($_, $clo, x) => $lam27444$apply$3680($clo, x) };

function $lam27487$apply$3687($clo, y) {
  {
    const board = (() => {
      return $clo._1;
    })();
    {
      const $t27489 = (() => {
        {
          const go_i7340 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
          {
            const $t177_i7342 = { $: "Nil" };
            return go$apply$0(go_i7340, 9, $t177_i7342);
          }
        }
      })();
      {
        const $t27499 = (() => {
          return { $: "$Clo_$lam27490$3688", _0: $lam27490$apply$3688, _1: board, _2: y };
        })();
        {
          const f_i7336 = $t27499;
          {
            const go_i7337 = { $: "$Clo_go$4683", _0: go$apply$4683, _1: f_i7336 };
            return go$apply$4683(go_i7337, $t27489);
          }
        }
      }
    }
  }
}
const $lam27487$apply$3687$clo = { _0: ($_, $clo, y) => $lam27487$apply$3687($clo, y) };

function $lam27490$apply$3688($clo, x) {
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
            const $t27318_i9547 = (y * 10);
            return ($t27318_i9547 + x);
          }
        })();
        {
          const v = (() => {
            return Array$get$PVec_Int$Int(board, idx);
          })();
          {
            const id = (() => {
              {
                const $t27493 = (() => {
                  {
                    const $t27492 = (() => {
                      {
                        const $t27491 = String(x);
                        {
                          const $rc_1168 = ("cell-" + $t27491);
                          return $rc_1168;
                        }
                      }
                    })();
                    {
                      const $rc_1167 = ($t27492 + "-");
                      return $rc_1167;
                    }
                  }
                })();
                {
                  const $t27494 = String(y);
                  {
                    const $rc_1166 = ($t27493 + $t27494);
                    return $rc_1166;
                  }
                }
              }
            })();
            {
              const $t27495 = Dom$find(id);
              switch ($t27495.$) {
                case "None": {
                  return {  };
                }
                case "Some": {
                  const $f27498 = $t27495._0;
                  {
                    const cell = $f27498;
                    {
                      const $t27496 = (v === 0);
                      if ($t27496 === true) {
                        return Dom$set_style(cell, "background", "#111");
                      } else {
                        return (() => {
                          {
                            let $t27497;
                            if (v === 1) {
                              $t27497 = "#00CED1";
                            } else if (v === 2) {
                              $t27497 = "#FFD700";
                            } else if (v === 3) {
                              $t27497 = "#9B59B6";
                            } else if (v === 4) {
                              $t27497 = "#2ECC71";
                            } else if (v === 5) {
                              $t27497 = "#E74C3C";
                            } else if (v === 6) {
                              $t27497 = "#3498DB";
                            } else if (v === 7) {
                              $t27497 = "#F39C12";
                            } else {
                              $t27497 = "";
                            }
                            return Dom$set_style(cell, "background", $t27497);
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
const $lam27490$apply$3688$clo = { _0: ($_, $clo, x) => $lam27490$apply$3688($clo, x) };

function $lam27501$apply$3689($clo, c) {
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
        const $f27518 = c._0;
        const $f27519 = c._1;
        {
          const dy = (() => {
            return $f27519;
          })();
          {
            const dx = (() => {
              return $f27518;
            })();
            {
              const x = (ox + dx);
              {
                const y = (oy + dy);
                {
                  const $t27510 = (() => {
                    {
                      const $t27507 = (() => {
                        {
                          const $t27505 = (() => {
                            {
                              const $t27502 = (x >= 0);
                              {
                                const $t27504 = (x < 10);
                                return ($t27502 && $t27504);
                              }
                            }
                          })();
                          {
                            const $t27506 = (y >= 0);
                            return ($t27505 && $t27506);
                          }
                        }
                      })();
                      {
                        const $t27509 = (y < 20);
                        return ($t27507 && $t27509);
                      }
                    }
                  })();
                  if ($t27510 === true) {
                    return (() => {
                      {
                        const id = (() => {
                          {
                            const $t27513 = (() => {
                              {
                                const $t27512 = (() => {
                                  {
                                    const $t27511 = String(x);
                                    {
                                      const $rc_1171 = ("cell-" + $t27511);
                                      return $rc_1171;
                                    }
                                  }
                                })();
                                {
                                  const $rc_1170 = ($t27512 + "-");
                                  return $rc_1170;
                                }
                              }
                            })();
                            {
                              const $t27514 = String(y);
                              {
                                const $rc_1169 = ($t27513 + $t27514);
                                return $rc_1169;
                              }
                            }
                          }
                        })();
                        {
                          const $t27515 = Dom$find(id);
                          switch ($t27515.$) {
                            case "None": {
                              return {  };
                            }
                            case "Some": {
                              const $f27517 = $t27515._0;
                              {
                                const cell = $f27517;
                                {
                                  let $t27516;
                                  switch (piece.$) {
                                    case "I": {
                                      $t27516 = "#00CED1";
                                      break;
                                    }
                                    case "O": {
                                      $t27516 = "#FFD700";
                                      break;
                                    }
                                    case "T": {
                                      $t27516 = "#9B59B6";
                                      break;
                                    }
                                    case "S": {
                                      $t27516 = "#2ECC71";
                                      break;
                                    }
                                    case "Z": {
                                      $t27516 = "#E74C3C";
                                      break;
                                    }
                                    case "J": {
                                      $t27516 = "#3498DB";
                                      break;
                                    }
                                    case "L": {
                                      $t27516 = "#F39C12";
                                      break;
                                    }
                                    default: {
                                      $t27516 = (() => { throw new Error("non-exhaustive pattern match"); })();
                                      break;
                                    }
                                  }
                                  return Dom$set_style(cell, "background", $t27516);
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
const $lam27501$apply$3689$clo = { _0: ($_, $clo, c) => $lam27501$apply$3689($clo, c) };

function $lam27629$apply$3716($clo, board, piece, rot, x, y, next, score, lines) {
  {
    const $t27630 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t27630, rot);
      {
        const $t27632 = (() => {
          {
            const $t27631 = (y + 1);
            {
              const $t27405_i7355 = { $: "$Clo_$lam27394$3673", _0: $lam27394$apply$3673, _1: board, _2: x, _3: $t27631 };
              return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t27405_i7355);
            }
          }
        })();
        if ($t27632 === true) {
          return (() => {
            {
              const $rc_1172 = lock_and_advance(board, piece, rot, x, y, next, score, lines);
              return $rc_1172;
            }
          })();
        } else {
          return (() => {
            {
              const $t27633 = (y + 1);
              return { _0: board, _1: piece, _2: rot, _3: x, _4: $t27633, _5: next, _6: score, _7: lines, _8: false };
            }
          })();
        }
      }
    }
  }
}
const $lam27629$apply$3716$clo = { _0: ($_, $clo, board, piece, rot, x, y, next, score, lines) => $lam27629$apply$3716($clo, board, piece, rot, x, y, next, score, lines) };

function $lam27635$apply$3717($clo, board, piece, rot, x, y, next, score, lines) {
  {
    const dx = (() => {
      return $clo._1;
    })();
    {
      const dy = (() => {
        return $clo._2;
      })();
      {
        const $t27636 = TetrisLogic$piece_cells(piece);
        {
          const cells = rotate_n($t27636, rot);
          {
            const $t27639 = (() => {
              {
                const $t27637 = (x + dx);
                {
                  const $t27638 = (y + dy);
                  {
                    const $t27405_i7360 = { $: "$Clo_$lam27394$3673", _0: $lam27394$apply$3673, _1: board, _2: $t27637, _3: $t27638 };
                    return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t27405_i7360);
                  }
                }
              }
            })();
            if ($t27639 === true) {
              return { _0: board, _1: piece, _2: rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: false };
            } else {
              return (() => {
                {
                  const $t27640 = (x + dx);
                  {
                    const $t27641 = (y + dy);
                    return { _0: board, _1: piece, _2: rot, _3: $t27640, _4: $t27641, _5: next, _6: score, _7: lines, _8: false };
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
const $lam27635$apply$3717$clo = { _0: ($_, $clo, board, piece, rot, x, y, next, score, lines) => $lam27635$apply$3717($clo, board, piece, rot, x, y, next, score, lines) };

function $lam27643$apply$3718($clo, board, piece, rot, x, y, next, score, lines) {
  {
    const new_rot = (() => {
      {
        const $t27644 = (rot + 1);
        return ($t27644 % 4);
      }
    })();
    {
      const $t27645 = TetrisLogic$piece_cells(piece);
      {
        const cells = rotate_n($t27645, new_rot);
        {
          const $t27646 = (() => {
            {
              const $t27405_i7365 = { $: "$Clo_$lam27394$3673", _0: $lam27394$apply$3673, _1: board, _2: x, _3: y };
              return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t27405_i7365);
            }
          })();
          if ($t27646 === true) {
            return { _0: board, _1: piece, _2: rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: false };
          } else {
            return { _0: board, _1: piece, _2: new_rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: false };
          }
        }
      }
    }
  }
}
const $lam27643$apply$3718$clo = { _0: ($_, $clo, board, piece, rot, x, y, next, score, lines) => $lam27643$apply$3718($clo, board, piece, rot, x, y, next, score, lines) };

function $lam27651$apply$3719($clo, board, piece, rot, x, y, next, score, lines) {
  {
    const $t27652 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t27652, rot);
      {
        const final_y = (() => {
          return fall_from(board, cells, x, y);
        })();
        return lock_and_advance(board, piece, rot, x, final_y, next, score, lines);
      }
    }
  }
}
const $lam27651$apply$3719$clo = { _0: ($_, $clo, board, piece, rot, x, y, next, score, lines) => $lam27651$apply$3719($clo, board, piece, rot, x, y, next, score, lines) };

function $lam27693$apply$3729($clo, y) {
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
          const $t27695 = (() => {
            {
              const go_i7372 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
              {
                const $t177_i7374 = { $: "Nil" };
                return go$apply$0(go_i7372, 9, $t177_i7374);
              }
            }
          })();
          {
            const $t27702 = (() => {
              return { $: "$Clo_$lam27696$3730", _0: $lam27696$apply$3730, _1: row, _2: y };
            })();
            {
              const f_i7368 = $t27702;
              {
                const go_i7369 = { $: "$Clo_go$4683", _0: go$apply$4683, _1: f_i7368 };
                return go$apply$4683(go_i7369, $t27695);
              }
            }
          }
        }
      })();
      return Dom$append(container, row);
    }
  }
}
const $lam27693$apply$3729$clo = { _0: ($_, $clo, y) => $lam27693$apply$3729($clo, y) };

function $lam27696$apply$3730($clo, x) {
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
            const $t27701 = (() => {
              {
                const $t27699 = (() => {
                  {
                    const $t27698 = (() => {
                      {
                        const $t27697 = String(x);
                        {
                          const $rc_1175 = ("cell-" + $t27697);
                          return $rc_1175;
                        }
                      }
                    })();
                    {
                      const $rc_1174 = ($t27698 + "-");
                      return $rc_1174;
                    }
                  }
                })();
                {
                  const $t27700 = String(y);
                  {
                    const $rc_1173 = ($t27699 + $t27700);
                    return $rc_1173;
                  }
                }
              }
            })();
            return Dom$set_attr(cell, "id", $t27701);
          }
        })();
        return Dom$append(row, cell);
      }
    }
  }
}
const $lam27696$apply$3730$clo = { _0: ($_, $clo, x) => $lam27696$apply$3730($clo, x) };

function $lam27722$apply$3738($clo, ev) {
  return handle_key(ev);
}
const $lam27722$apply$3738$clo = { _0: ($_, $clo, ev) => $lam27722$apply$3738($clo, ev) };

function $lam27724$apply$3739($clo, _) {
  {
    const $t27634_i7375 = { $: "$Clo_$lam27629$3716", _0: $lam27629$apply$3716 };
    return with_state($t27634_i7375);
  }
}
const $lam27724$apply$3739$clo = { _0: ($_, $clo, _) => $lam27724$apply$3739($clo, _) };

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
            const go_i7505 = { $: "$Clo_go$4000", _0: go$apply$4000 };
            {
              const $t250_i7506 = { $: "Nil" };
              return go$apply$4000(go_i7505, acc, $t250_i7506);
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
            const go_i7732 = { $: "$Clo_go$3740", _0: go$apply$3740 };
            {
              const $t250_i7733 = { $: "Nil" };
              return go$apply$3740(go_i7732, acc, $t250_i7733);
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
            const go_i8271 = { $: "$Clo_go$3740", _0: go$apply$3740 };
            {
              const $t250_i8272 = { $: "Nil" };
              return go$apply$3740(go_i8271, acc, $t250_i8272);
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
            const go_i8400 = { $: "$Clo_go$5104", _0: go$apply$5104 };
            {
              const $t250_i8401 = { $: "Nil" };
              return go$apply$5104(go_i8400, acc, $t250_i8401);
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
              const go_i8409 = { $: "$Clo_go$3740", _0: go$apply$3740 };
              {
                const $t250_i8410 = { $: "Nil" };
                return go$apply$3740(go_i8409, acc, $t250_i8410);
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
            const go_i8414 = { $: "$Clo_go$3740", _0: go$apply$3740 };
            {
              const $t250_i8415 = { $: "Nil" };
              return go$apply$3740(go_i8414, acc, $t250_i8415);
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

function $lam27406$apply$4688($clo, b, c) {
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
        const $f27409 = c._0;
        const $f27410 = c._1;
        {
          const dy = (() => {
            return $f27410;
          })();
          {
            const dx = (() => {
              return $f27409;
            })();
            {
              const x = (origin_x + dx);
              {
                const y = (origin_y + dy);
                {
                  const $t27407 = (() => {
                    {
                      const $t27391_i9558 = (() => {
                        {
                          const $t27389_i9556 = (() => {
                            {
                              const $t27386_i9554 = (x >= 0);
                              {
                                const $t27388_i9555 = (x < 10);
                                return ($t27386_i9554 && $t27388_i9555);
                              }
                            }
                          })();
                          {
                            const $t27390_i9557 = (y >= 0);
                            return ($t27389_i9556 && $t27390_i9557);
                          }
                        }
                      })();
                      {
                        const $t27393_i9559 = (y < 20);
                        return ($t27391_i9558 && $t27393_i9559);
                      }
                    }
                  })();
                  if ($t27407 === true) {
                    return (() => {
                      {
                        const $t27408 = (() => {
                          {
                            const $t27318_i9551 = (y * 10);
                            return ($t27318_i9551 + x);
                          }
                        })();
                        return Array$set$PVec_Int$Int$Int(b, $t27408, color_idx);
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
const $lam27406$apply$4688$clo = { _0: ($_, $clo, b, c) => $lam27406$apply$4688($clo, b, c) };

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
              const go_i8973 = { $: "$Clo_go$5449", _0: go$apply$5449 };
              {
                const $t6726_i8974 = { $: "Nil" };
                return go$apply$5449(go_i8973, $t6760, $t6726_i8974);
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
                          const rev_onto_i8980 = { $: "$Clo_rev_onto$5452", _0: rev_onto$apply$5452 };
                          {
                            const go_i8981 = { $: "$Clo_go$5454", _0: go$apply$5454, _1: nd, _2: rev_onto_i8980 };
                            {
                              const $t6808_i8982 = { $: "Nil" };
                              return go$apply$5454(go_i8981, children, slot_i, $t6808_i8982);
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
                          const $t6809_i9000 = (leaf_idx >> $t6860);
                          return ($t6809_i9000 & 31);
                        }
                      }
                    })();
                    {
                      const n = (() => {
                        {
                          const go_i8997 = { $: "$Clo_go$5458", _0: go$apply$5458 };
                          return go$apply$5458(go_i8997, children, 0);
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
                                        const go_i8994 = { $: "$Clo_go$5451", _0: go$apply$5451 };
                                        {
                                          const $t6838_i8995 = { $: "TrieLeaf", _0: leaf_values };
                                          return go$apply$5451(go_i8994, $t6862, $t6838_i8995);
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t6864 = (() => {
                                      {
                                        const go_i8990 = { $: "$Clo_go$5456", _0: go$apply$5456, _1: $t6863 };
                                        {
                                          const $t6768_i8991 = { $: "Nil" };
                                          return go$apply$5456(go_i8990, children, $t6768_i8991);
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
                      const go_i8986 = { $: "$Clo_go$5451", _0: go$apply$5451 };
                      {
                        const $t6838_i8987 = { $: "TrieLeaf", _0: leaf_values };
                        return go$apply$5451(go_i8986, $t6872, $t6838_i8987);
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
                  const go_i9003 = { $: "$Clo_go$5451", _0: go$apply$5451 };
                  {
                    const $t6838_i9004 = { $: "TrieLeaf", _0: leaf_values };
                    return go$apply$5451(go_i9003, $t6872, $t6838_i9004);
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
              const go_i9245 = { $: "$Clo_go$5449", _0: go$apply$5449 };
              {
                const $t6726_i9246 = { $: "Nil" };
                return go$apply$5449(go_i9245, acc, $t6726_i9246);
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
                          const rev_onto_i9252 = { $: "$Clo_rev_onto$5464", _0: rev_onto$apply$5464 };
                          {
                            const go_i9253 = { $: "$Clo_go$5466", _0: go$apply$5466, _1: nd, _2: rev_onto_i9252 };
                            {
                              const $t6808_i9254 = { $: "Nil" };
                              return go$apply$5466(go_i9253, children, slot, $t6808_i9254);
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
                            const rev_onto_i9261 = { $: "$Clo_rev_onto$5420", _0: rev_onto$apply$5420 };
                            {
                              const go_i9262 = { $: "$Clo_go$5422", _0: go$apply$5422, _1: rev_onto_i9261, _2: val };
                              {
                                const $t6752_i9263 = { $: "Nil" };
                                return go$apply$5422(go_i9262, values, $t6824, $t6752_i9263);
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
                      const $t6809_i9266 = (idx >> s);
                      return ($t6809_i9266 & 31);
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
              const go_i9304 = { $: "$Clo_go$5484", _0: go$apply$5484 };
              {
                const $t6726_i9305 = { $: "Nil" };
                return go$apply$5484(go_i9304, acc, $t6726_i9305);
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
              const go_i9309 = { $: "$Clo_go$5486", _0: go$apply$5486 };
              {
                const $t6726_i9310 = { $: "Nil" };
                return go$apply$5486(go_i9309, $t6760, $t6726_i9310);
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
              const go_i9322 = { $: "$Clo_go$5488", _0: go$apply$5488 };
              {
                const $t6726_i9323 = { $: "Nil" };
                return go$apply$5488(go_i9322, acc, $t6726_i9323);
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
