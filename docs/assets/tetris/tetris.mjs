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
        const $t27326 = { _0: 0, _1: 1 };
        {
          const $t27327 = { _0: 1, _1: 1 };
          {
            const $t27328 = { _0: 2, _1: 1 };
            {
              const $t27329 = { _0: 3, _1: 1 };
              {
                const $t27330 = { $: "Nil" };
                {
                  const $t27331 = { $: "Cons", _0: $t27329, _1: $t27330 };
                  {
                    const $t27332 = { $: "Cons", _0: $t27328, _1: $t27331 };
                    {
                      const $t27333 = { $: "Cons", _0: $t27327, _1: $t27332 };
                      return { $: "Cons", _0: $t27326, _1: $t27333 };
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
        const $t27334 = { _0: 1, _1: 1 };
        {
          const $t27335 = { _0: 2, _1: 1 };
          {
            const $t27336 = { _0: 1, _1: 2 };
            {
              const $t27337 = { _0: 2, _1: 2 };
              {
                const $t27338 = { $: "Nil" };
                {
                  const $t27339 = { $: "Cons", _0: $t27337, _1: $t27338 };
                  {
                    const $t27340 = { $: "Cons", _0: $t27336, _1: $t27339 };
                    {
                      const $t27341 = { $: "Cons", _0: $t27335, _1: $t27340 };
                      return { $: "Cons", _0: $t27334, _1: $t27341 };
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
        const $t27342 = { _0: 1, _1: 1 };
        {
          const $t27343 = { _0: 0, _1: 2 };
          {
            const $t27344 = { _0: 1, _1: 2 };
            {
              const $t27345 = { _0: 2, _1: 2 };
              {
                const $t27346 = { $: "Nil" };
                {
                  const $t27347 = { $: "Cons", _0: $t27345, _1: $t27346 };
                  {
                    const $t27348 = { $: "Cons", _0: $t27344, _1: $t27347 };
                    {
                      const $t27349 = { $: "Cons", _0: $t27343, _1: $t27348 };
                      return { $: "Cons", _0: $t27342, _1: $t27349 };
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
        const $t27350 = { _0: 1, _1: 1 };
        {
          const $t27351 = { _0: 2, _1: 1 };
          {
            const $t27352 = { _0: 0, _1: 2 };
            {
              const $t27353 = { _0: 1, _1: 2 };
              {
                const $t27354 = { $: "Nil" };
                {
                  const $t27355 = { $: "Cons", _0: $t27353, _1: $t27354 };
                  {
                    const $t27356 = { $: "Cons", _0: $t27352, _1: $t27355 };
                    {
                      const $t27357 = { $: "Cons", _0: $t27351, _1: $t27356 };
                      return { $: "Cons", _0: $t27350, _1: $t27357 };
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
        const $t27358 = { _0: 0, _1: 1 };
        {
          const $t27359 = { _0: 1, _1: 1 };
          {
            const $t27360 = { _0: 1, _1: 2 };
            {
              const $t27361 = { _0: 2, _1: 2 };
              {
                const $t27362 = { $: "Nil" };
                {
                  const $t27363 = { $: "Cons", _0: $t27361, _1: $t27362 };
                  {
                    const $t27364 = { $: "Cons", _0: $t27360, _1: $t27363 };
                    {
                      const $t27365 = { $: "Cons", _0: $t27359, _1: $t27364 };
                      return { $: "Cons", _0: $t27358, _1: $t27365 };
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
        const $t27366 = { _0: 0, _1: 1 };
        {
          const $t27367 = { _0: 0, _1: 2 };
          {
            const $t27368 = { _0: 1, _1: 2 };
            {
              const $t27369 = { _0: 2, _1: 2 };
              {
                const $t27370 = { $: "Nil" };
                {
                  const $t27371 = { $: "Cons", _0: $t27369, _1: $t27370 };
                  {
                    const $t27372 = { $: "Cons", _0: $t27368, _1: $t27371 };
                    {
                      const $t27373 = { $: "Cons", _0: $t27367, _1: $t27372 };
                      return { $: "Cons", _0: $t27366, _1: $t27373 };
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
        const $t27374 = { _0: 2, _1: 1 };
        {
          const $t27375 = { _0: 0, _1: 2 };
          {
            const $t27376 = { _0: 1, _1: 2 };
            {
              const $t27377 = { _0: 2, _1: 2 };
              {
                const $t27378 = { $: "Nil" };
                {
                  const $t27379 = { $: "Cons", _0: $t27377, _1: $t27378 };
                  {
                    const $t27380 = { $: "Cons", _0: $t27376, _1: $t27379 };
                    {
                      const $t27381 = { $: "Cons", _0: $t27375, _1: $t27380 };
                      return { $: "Cons", _0: $t27374, _1: $t27381 };
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
  const $f27383 = c._0;
  const $f27384 = c._1;
  {
    const y = (() => {
      return $f27384;
    })();
    {
      const x = (() => {
        return $f27383;
      })();
      {
        const $t27382 = (3 - y);
        return { _0: $t27382, _1: x };
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
      const $t27433 = (() => {
        return { $: "$Clo_$lam27431$3677", _0: $lam27431$apply$3677, _1: board };
      })();
      {
        const kept_rows = (() => {
          {
            const pred_i3640 = $t27433;
            {
              const go_i3641 = { $: "$Clo_go$4591", _0: go$apply$4591, _1: pred_i3640 };
              {
                const $t299_i3642 = { $: "Nil" };
                return go$apply$4591(go_i3641, rows, $t299_i3642);
              }
            }
          }
        })();
        {
          const cleared = (() => {
            {
              const $t27435 = (() => {
                {
                  const go_i3638 = { $: "$Clo_go$4619", _0: go$apply$4619 };
                  return go$apply$4619(go_i3638, kept_rows, 0);
                }
              })();
              return (20 - $t27435);
            }
          })();
          {
            const $t27437 = { $: "$Clo_$lam27436$3678", _0: $lam27436$apply$3678, _1: board };
            {
              const kept_cells = (() => {
                {
                  const f_i3633 = $t27437;
                  {
                    const prepend_reversed_i3634 = { $: "$Clo_prepend_reversed$4706", _0: prepend_reversed$apply$4706 };
                    {
                      const go_i3635 = { $: "$Clo_go$4708", _0: go$apply$4708, _1: f_i3633, _2: prepend_reversed_i3634 };
                      {
                        const $t290_i3636 = { $: "Nil" };
                        return go$apply$4708(go_i3635, kept_rows, $t290_i3636);
                      }
                    }
                  }
                }
              })();
              {
                const $t27439 = (cleared * 10);
                {
                  const blank_cells = (() => {
                    {
                      const go_i3630 = { $: "$Clo_go$4297", _0: go$apply$4297, _1: 0 };
                      {
                        const $t172_i3631 = { $: "Nil" };
                        return go$apply$4297(go_i3630, $t27439, $t172_i3631);
                      }
                    }
                  })();
                  {
                    const new_board = (() => {
                      {
                        const $t27440 = (() => {
                          {
                            const go_i9356 = { $: "$Clo_go$4485", _0: go$apply$4485 };
                            {
                              const $t258_i9359 = (() => {
                                {
                                  const go_i3943_i9357 = { $: "$Clo_go$3770", _0: go$apply$3770 };
                                  {
                                    const $t250_i3944_i9358 = { $: "Nil" };
                                    return go$apply$3770(go_i3943_i9357, blank_cells, $t250_i3944_i9358);
                                  }
                                }
                              })();
                              return go$apply$4485(go_i9356, $t258_i9359, kept_cells);
                            }
                          }
                        })();
                        {
                          const go_i9350 = { $: "$Clo_go$4696", _0: go$apply$4696 };
                          {
                            const $t7129_i9353 = (() => {
                              {
                                const $t6923_i4042_i9351 = { $: "TrieEmpty" };
                                {
                                  const $t6924_i4043_i9352 = { $: "Nil" };
                                  return { $: "PVec", _0: 0, _1: 0, _2: $t6923_i4042_i9351, _3: $t6924_i4043_i9352 };
                                }
                              }
                            })();
                            return go$apply$4696(go_i9350, $t27440, $t7129_i9353);
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

function lcg_next(state) {
  {
    const $t27450 = (state * 16807);
    return ($t27450 % 2147483647);
  }
}
const lcg_next$clo = { _0: ($_, state) => lcg_next(state) };

function lcg_seed() {
  {
    const raw = (() => {
      {
        const $t27454 = (() => {
          {
            const $t27453 = (() => {
              {
                const $t27452 = (() => {
                  {
                    const $t27451 = {  };
                    return march_unix_time();
                  }
                })();
                return ($t27452 * 1000000.);
              }
            })();
            return Math.trunc($t27453);
          }
        })();
        return march_int_mod($t27454, 2147483646);
      }
    })();
    {
      const $t27455 = (raw <= 0);
      if ($t27455 === true) {
        return (raw + 2147483646);
      } else {
        return raw;
      }
    }
  }
}
const lcg_seed$clo = { _0: ($_) => lcg_seed() };

function next_piece(rng) {
  {
    const $t27468 = { $: "I" };
    {
      const $t27469 = { $: "O" };
      {
        const $t27470 = { $: "T" };
        {
          const $t27471 = { $: "S" };
          {
            const $t27472 = { $: "Z" };
            {
              const $t27473 = { $: "J" };
              {
                const $t27474 = { $: "L" };
                {
                  const $t27475 = { $: "Nil" };
                  {
                    const $t27476 = { $: "Cons", _0: $t27474, _1: $t27475 };
                    {
                      const $t27477 = { $: "Cons", _0: $t27473, _1: $t27476 };
                      {
                        const $t27478 = { $: "Cons", _0: $t27472, _1: $t27477 };
                        {
                          const $t27479 = { $: "Cons", _0: $t27471, _1: $t27478 };
                          {
                            const $t27480 = { $: "Cons", _0: $t27470, _1: $t27479 };
                            {
                              const $t27481 = { $: "Cons", _0: $t27469, _1: $t27480 };
                              {
                                const pieces = { $: "Cons", _0: $t27468, _1: $t27481 };
                                {
                                  const rng2 = lcg_next(rng);
                                  {
                                    const idx = (rng2 % 7);
                                    {
                                      const result = (() => {
                                        {
                                          const $t27482 = List$nth$List_Piece$Int(pieces, idx);
                                          return { _0: $t27482, _1: rng2 };
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
    const $t27483 = Dom$find("game-state");
    switch ($t27483.$) {
      case "Some": {
        const $f27484 = $t27483._0;
        {
          const el = $f27484;
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
    const $t27485 = Dom$get_attr(el, name);
    switch ($t27485.$) {
      case "Some": {
        const $f27487 = $t27485._0;
        {
          const s = $f27487;
          {
            const $t27486 = (() => {
              {
                const $rc_781 = march_string_to_int(s);
                return $rc_781;
              }
            })();
            return Option$unwrap_or$Option_Int$Int($t27486, _default);
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
    const $t27488 = Dom$get_attr(el, name);
    switch ($t27488.$) {
      case "Some": {
        const $f27489 = $t27488._0;
        {
          const s = $f27489;
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
    const $t27490 = (n <= 0);
    if ($t27490 === true) {
      return cells;
    } else {
      return (() => {
        {
          const $t27491 = (() => {
            {
              const f_i3611_i9361 = TetrisLogic$rotate_cell$clo;
              {
                const go_i3612_i9362 = { $: "$Clo_go$4698", _0: go$apply$4698, _1: f_i3611_i9361 };
                {
                  const $t267_i3613_i9363 = { $: "Nil" };
                  return go$apply$4698(go_i3612_i9362, cells, $t267_i3613_i9363);
                }
              }
            }
          })();
          {
            const $t27492 = (n - 1);
            return rotate_n($t27491, $t27492);
          }
        }
      })();
    }
  }
}
const rotate_n$clo = { _0: ($_, cells, n) => rotate_n(cells, n) };

function spawn_piece(next, board, rng) {
  {
    const cells = TetrisLogic$piece_cells(next);
    {
      const over = (() => {
        {
          const $t27408_i3670 = { $: "$Clo_$lam27397$3673", _0: $lam27397$apply$3673, _1: board, _2: 3, _3: 0 };
          return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t27408_i3670);
        }
      })();
      {
        const $t27493 = next_piece(rng);
        const $f27494 = $t27493._0;
        const $f27495 = $t27493._1;
        {
          const rng2 = (() => {
            return $f27495;
          })();
          {
            const next2 = (() => {
              return $f27494;
            })();
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
    const $t27540 = Dom$find(id);
    switch ($t27540.$) {
      case "None": {
        return {  };
      }
      case "Some": {
        const $f27541 = $t27540._0;
        {
          const el = $f27541;
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
          const $t27542 = (() => {
            return get_str_attr(el, "data-over", "false");
          })();
          return ($t27542 === "true");
        }
      })();
      if (over === true) {
        return {  };
      } else {
        return (() => {
          {
            const board = (() => {
              {
                const $t27543 = (() => {
                  return get_str_attr(el, "data-board", "");
                })();
                {
                  const $t27544 = (() => {
                    {
                      const $rc_789 = (() => {
                        {
                          const $t27446_i9402 = march_string_split($t27543, ",");
                          {
                            const $t27449_i9403 = { $: "$Clo_$lam27447$3680", _0: $lam27447$apply$3680 };
                            {
                              const f_i3655_i9404 = $t27449_i9403;
                              {
                                const go_i3656_i9405 = { $: "$Clo_go$4710", _0: go$apply$4710, _1: f_i3655_i9404 };
                                {
                                  const $t267_i3657_i9406 = { $: "Nil" };
                                  return go$apply$4710(go_i3656_i9405, $t27446_i9402, $t267_i3657_i9406);
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
                    const go_i9397 = { $: "$Clo_go$4696", _0: go$apply$4696 };
                    {
                      const $t7129_i9400 = (() => {
                        {
                          const $t6923_i4042_i9398 = { $: "TrieEmpty" };
                          {
                            const $t6924_i4043_i9399 = { $: "Nil" };
                            return { $: "PVec", _0: 0, _1: 0, _2: $t6923_i4042_i9398, _3: $t6924_i4043_i9399 };
                          }
                        }
                      })();
                      return go$apply$4696(go_i9397, $t27544, $t7129_i9400);
                    }
                  }
                }
              }
            })();
            {
              const piece = (() => {
                {
                  const $t27545 = (() => {
                    return get_str_attr(el, "data-piece", "I");
                  })();
                  {
                    let $rc_788;
                    if ($t27545 === "I") {
                      $rc_788 = { $: "I" };
                    } else if ($t27545 === "O") {
                      $rc_788 = { $: "O" };
                    } else if ($t27545 === "T") {
                      $rc_788 = { $: "T" };
                    } else if ($t27545 === "S") {
                      $rc_788 = { $: "S" };
                    } else if ($t27545 === "Z") {
                      $rc_788 = { $: "Z" };
                    } else if ($t27545 === "J") {
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
                          const $t27546 = (() => {
                            return get_str_attr(el, "data-next", "O");
                          })();
                          {
                            let $rc_787;
                            if ($t27546 === "I") {
                              $rc_787 = { $: "I" };
                            } else if ($t27546 === "O") {
                              $rc_787 = { $: "O" };
                            } else if ($t27546 === "T") {
                              $rc_787 = { $: "T" };
                            } else if ($t27546 === "S") {
                              $rc_787 = { $: "S" };
                            } else if ($t27546 === "Z") {
                              $rc_787 = { $: "Z" };
                            } else if ($t27546 === "J") {
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
                            const rng = (() => {
                              return get_int_attr(el, "data-rng", 1);
                            })();
                            {
                              const $t27547 = f._0(f, board, piece, rot, x, y, next, score, lines, rng);
                              const $f27567 = $t27547._0;
                              const $f27568 = $t27547._1;
                              const $f27569 = $t27547._2;
                              const $f27570 = $t27547._3;
                              const $f27571 = $t27547._4;
                              const $f27572 = $t27547._5;
                              const $f27573 = $t27547._6;
                              const $f27574 = $t27547._7;
                              const $f27575 = $t27547._8;
                              const $f27576 = $t27547._9;
                              {
                                const over2 = (() => {
                                  return $f27576;
                                })();
                                {
                                  const rng2 = (() => {
                                    return $f27575;
                                  })();
                                  {
                                    const lines2 = (() => {
                                      return $f27574;
                                    })();
                                    {
                                      const score2 = (() => {
                                        return $f27573;
                                      })();
                                      {
                                        const next2 = (() => {
                                          return $f27572;
                                        })();
                                        {
                                          const y2 = (() => {
                                            return $f27571;
                                          })();
                                          {
                                            const x2 = (() => {
                                              return $f27570;
                                            })();
                                            {
                                              const rot2 = (() => {
                                                return $f27569;
                                              })();
                                              {
                                                const piece2 = (() => {
                                                  return $f27568;
                                                })();
                                                {
                                                  const board2 = (() => {
                                                    return $f27567;
                                                  })();
                                                  (() => {
                                                    {
                                                      const $t27501_i9392 = (() => {
                                                        {
                                                          const go_i3676_i9389 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
                                                          {
                                                            const $t177_i3678_i9391 = { $: "Nil" };
                                                            return go$apply$0(go_i3676_i9389, 19, $t177_i3678_i9391);
                                                          }
                                                        }
                                                      })();
                                                      {
                                                        const $t27515_i9393 = { $: "$Clo_$lam27502$3688", _0: $lam27502$apply$3688, _1: board2 };
                                                        {
                                                          const f_i3672_i9394 = $t27515_i9393;
                                                          {
                                                            const go_i3673_i9395 = { $: "$Clo_go$4713", _0: go$apply$4713, _1: f_i3672_i9394 };
                                                            return go$apply$4713(go_i3673_i9395, $t27501_i9392);
                                                          }
                                                        }
                                                      }
                                                    }
                                                  })();
                                                  (() => {
                                                    {
                                                      const $t27548 = (!over2);
                                                      if ($t27548 === true) {
                                                        return (() => {
                                                          {
                                                            const base_cells_i9383 = TetrisLogic$piece_cells(piece2);
                                                            {
                                                              const rotated_i9384 = rotate_n(base_cells_i9383, rot2);
                                                              {
                                                                const $t27539_i9385 = { $: "$Clo_$lam27516$3690", _0: $lam27516$apply$3690, _1: x2, _2: y2, _3: piece2 };
                                                                {
                                                                  const f_i3680_i9386 = $t27539_i9385;
                                                                  {
                                                                    const go_i3681_i9387 = { $: "$Clo_go$4715", _0: go$apply$4715, _1: f_i3680_i9386 };
                                                                    return go$apply$4715(go_i3681_i9387, rotated_i9384);
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
                                                      const $t27550 = (() => {
                                                        {
                                                          const $t27549 = String(score2);
                                                          {
                                                            const $rc_786 = ("Score: " + $t27549);
                                                            return $rc_786;
                                                          }
                                                        }
                                                      })();
                                                      return set_text_if_found("score", $t27550);
                                                    }
                                                  })();
                                                  (() => {
                                                    {
                                                      const $t27553 = (() => {
                                                        {
                                                          const $t27552 = (() => {
                                                            {
                                                              const $t27551 = TetrisLogic$level_for_lines(lines2);
                                                              return String($t27551);
                                                            }
                                                          })();
                                                          {
                                                            const $rc_785 = ("Level: " + $t27552);
                                                            return $rc_785;
                                                          }
                                                        }
                                                      })();
                                                      return set_text_if_found("level", $t27553);
                                                    }
                                                  })();
                                                  (() => {
                                                    {
                                                      const $t27555 = (() => {
                                                        {
                                                          let $t27554;
                                                          switch (next2.$) {
                                                            case "I": {
                                                              $t27554 = "I";
                                                              break;
                                                            }
                                                            case "O": {
                                                              $t27554 = "O";
                                                              break;
                                                            }
                                                            case "T": {
                                                              $t27554 = "T";
                                                              break;
                                                            }
                                                            case "S": {
                                                              $t27554 = "S";
                                                              break;
                                                            }
                                                            case "Z": {
                                                              $t27554 = "Z";
                                                              break;
                                                            }
                                                            case "J": {
                                                              $t27554 = "J";
                                                              break;
                                                            }
                                                            case "L": {
                                                              $t27554 = "L";
                                                              break;
                                                            }
                                                            default: {
                                                              $t27554 = (() => { throw new Error("non-exhaustive pattern match"); })();
                                                              break;
                                                            }
                                                          }
                                                          {
                                                            const $rc_784 = ("Next: " + $t27554);
                                                            return $rc_784;
                                                          }
                                                        }
                                                      })();
                                                      return set_text_if_found("next", $t27555);
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
                                                      const $t27557 = (() => {
                                                        {
                                                          const $t27556 = (() => {
                                                            {
                                                              const $t7119_i9373 = { $: "Nil" };
                                                              {
                                                                const $t7121_i9374 = { $: "$Clo_$lam7120$4717", _0: $lam7120$apply$4717 };
                                                                {
                                                                  const rev_i9375 = Array$fold_left$PVec_Int$List_V__22342$Fn_List_V__22343_V__22343_List_V__22343(board2, $t7119_i9373, $t7121_i9374);
                                                                  {
                                                                    const go_i4053_i9376 = { $: "$Clo_go$5140", _0: go$apply$5140 };
                                                                    {
                                                                      const $t6726_i4054_i9377 = { $: "Nil" };
                                                                      return go$apply$5140(go_i4053_i9376, rev_i9375, $t6726_i4054_i9377);
                                                                    }
                                                                  }
                                                                }
                                                              }
                                                            }
                                                          })();
                                                          {
                                                            const $t27444_i9367 = { $: "$Clo_$lam27443$3679", _0: $lam27443$apply$3679 };
                                                            {
                                                              const $t27445_i9371 = (() => {
                                                                {
                                                                  const f_i3651_i9368 = $t27444_i9367;
                                                                  {
                                                                    const go_i3652_i9369 = { $: "$Clo_go$4131", _0: go$apply$4131, _1: f_i3651_i9368 };
                                                                    {
                                                                      const $t267_i3653_i9370 = { $: "Nil" };
                                                                      return go$apply$4131(go_i3652_i9369, $t27556, $t267_i3653_i9370);
                                                                    }
                                                                  }
                                                                }
                                                              })();
                                                              return march_string_join($t27445_i9371, ",");
                                                            }
                                                          }
                                                        }
                                                      })();
                                                      return Dom$set_attr(el, "data-board", $t27557);
                                                    }
                                                  })();
                                                  (() => {
                                                    {
                                                      const $t27558 = (() => {
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
                                                      return Dom$set_attr(el, "data-piece", $t27558);
                                                    }
                                                  })();
                                                  (() => {
                                                    {
                                                      const $t27559 = String(rot2);
                                                      return Dom$set_attr(el, "data-rot", $t27559);
                                                    }
                                                  })();
                                                  (() => {
                                                    {
                                                      const $t27560 = String(x2);
                                                      return Dom$set_attr(el, "data-x", $t27560);
                                                    }
                                                  })();
                                                  (() => {
                                                    {
                                                      const $t27561 = String(y2);
                                                      return Dom$set_attr(el, "data-y", $t27561);
                                                    }
                                                  })();
                                                  (() => {
                                                    {
                                                      const $t27562 = (() => {
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
                                                      return Dom$set_attr(el, "data-next", $t27562);
                                                    }
                                                  })();
                                                  (() => {
                                                    {
                                                      const $t27563 = String(score2);
                                                      return Dom$set_attr(el, "data-score", $t27563);
                                                    }
                                                  })();
                                                  (() => {
                                                    {
                                                      const $t27564 = String(lines2);
                                                      return Dom$set_attr(el, "data-lines", $t27564);
                                                    }
                                                  })();
                                                  (() => {
                                                    {
                                                      const $t27565 = String(rng2);
                                                      return Dom$set_attr(el, "data-rng", $t27565);
                                                    }
                                                  })();
                                                  {
                                                    let $t27566;
                                                    if (over2 === true) {
                                                      $t27566 = "true";
                                                    } else {
                                                      $t27566 = "false";
                                                    }
                                                    return Dom$set_attr(el, "data-over", $t27566);
                                                  }
                                                }
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
        })();
      }
    }
  }
}
const with_state$clo = { _0: ($_, f) => with_state(f) };

function lock_and_advance(board, piece, rot, x, y, next, score, lines, rng) {
  {
    const $t27613 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t27613, rot);
      {
        const locked = (() => {
          {
            let $t27614;
            switch (piece.$) {
              case "I": {
                $t27614 = 1;
                break;
              }
              case "O": {
                $t27614 = 2;
                break;
              }
              case "T": {
                $t27614 = 3;
                break;
              }
              case "S": {
                $t27614 = 4;
                break;
              }
              case "Z": {
                $t27614 = 5;
                break;
              }
              case "J": {
                $t27614 = 6;
                break;
              }
              case "L": {
                $t27614 = 7;
                break;
              }
              default: {
                $t27614 = (() => { throw new Error("non-exhaustive pattern match"); })();
                break;
              }
            }
            {
              const $t27418_i3706 = { $: "$Clo_$lam27409$4718", _0: $lam27409$apply$4718, _1: $t27614, _2: x, _3: y };
              return List$fold_left$List_T_Int_Int$PVec_Int$Fn_PVec_Int_T_Int_Int_PVec_Int(cells, board, $t27418_i3706);
            }
          }
        })();
        {
          const $t27615 = TetrisLogic$clear_lines(locked);
          const $f27649 = $t27615._0;
          const $f27650 = $t27615._1;
          {
            const n = (() => {
              return $f27650;
            })();
            {
              const cleared_board = (() => {
                return $f27649;
              })();
              {
                const new_score = (() => {
                  {
                    let $t27616;
                    if (n === 1) {
                      $t27616 = 100;
                    } else if (n === 2) {
                      $t27616 = 300;
                    } else if (n === 3) {
                      $t27616 = 500;
                    } else if (n === 4) {
                      $t27616 = 800;
                    } else {
                      $t27616 = 0;
                    }
                    return (score + $t27616);
                  }
                })();
                {
                  const new_lines = (lines + n);
                  {
                    const $t27617 = (() => {
                      return spawn_piece(next, cleared_board, rng);
                    })();
                    const $f27618 = $t27617._0;
                    const $f27619 = $t27617._1;
                    const $f27620 = $t27617._2;
                    const $f27621 = $t27617._3;
                    const $f27622 = $t27617._4;
                    const $f27623 = $t27617._5;
                    const $f27624 = $t27617._6;
                    {
                      const over = (() => {
                        return $f27624;
                      })();
                      {
                        const rng2 = (() => {
                          return $f27623;
                        })();
                        {
                          const next2 = (() => {
                            return $f27622;
                          })();
                          {
                            const y2 = (() => {
                              return $f27621;
                            })();
                            {
                              const x2 = (() => {
                                return $f27620;
                              })();
                              {
                                const rot2 = (() => {
                                  return $f27619;
                                })();
                                {
                                  const piece2 = (() => {
                                    return $f27618;
                                  })();
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

function toggle_pause() {
  {
    const el = state_el();
    {
      const over = (() => {
        {
          const $t27659 = (() => {
            return get_str_attr(el, "data-over", "false");
          })();
          return ($t27659 === "true");
        }
      })();
      if (over === true) {
        return {  };
      } else {
        return (() => {
          {
            const $t27661 = (() => {
              {
                const $t27660 = (() => {
                  {
                    const $t27656_i3712 = (() => {
                      {
                        const $t27655_i3711 = state_el();
                        return get_str_attr($t27655_i3711, "data-paused", "false");
                      }
                    })();
                    return ($t27656_i3712 === "true");
                  }
                })();
                return (!$t27660);
              }
            })();
            (() => {
              {
                let $t27657_i3710;
                if ($t27661 === true) {
                  $t27657_i3710 = "true";
                } else {
                  $t27657_i3710 = "false";
                }
                return Dom$set_attr(el, "data-paused", $t27657_i3710);
              }
            })();
            {
              let $t27658_i3709;
              if ($t27661 === true) {
                $t27658_i3709 = "Paused — press P to resume";
              } else {
                $t27658_i3709 = "";
              }
              return set_text_if_found("pause-status", $t27658_i3709);
            }
          }
        })();
      }
    }
  }
}
const toggle_pause$clo = { _0: ($_) => toggle_pause() };

function fall_from(board, cells, x, cur_y) {
  {
    const $t27683 = (() => {
      {
        const $t27682 = (cur_y + 1);
        {
          const $t27408_i3719 = { $: "$Clo_$lam27397$3673", _0: $lam27397$apply$3673, _1: board, _2: x, _3: $t27682 };
          return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t27408_i3719);
        }
      }
    })();
    if ($t27683 === true) {
      return cur_y;
    } else {
      return (() => {
        {
          const $t27684 = (cur_y + 1);
          return fall_from(board, cells, x, $t27684);
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
          const $t27325_i9503 = (() => {
            {
              const go_i3604_i9501 = { $: "$Clo_go$4297", _0: go$apply$4297, _1: 0 };
              {
                const $t172_i3605_i9502 = { $: "Nil" };
                return go$apply$4297(go_i3604_i9501, 200, $t172_i3605_i9502);
              }
            }
          })();
          {
            const go_i9345_i9504 = { $: "$Clo_go$4696", _0: go$apply$4696 };
            {
              const $t7129_i9348_i9507 = (() => {
                {
                  const $t6923_i4042_i9346_i9505 = { $: "TrieEmpty" };
                  {
                    const $t6924_i4043_i9347_i9506 = { $: "Nil" };
                    return { $: "PVec", _0: 0, _1: 0, _2: $t6923_i4042_i9346_i9505, _3: $t6924_i4043_i9347_i9506 };
                  }
                }
              })();
              return go$apply$4696(go_i9345_i9504, $t27325_i9503, $t7129_i9348_i9507);
            }
          }
        }
      })();
      {
        const rng0 = lcg_seed();
        {
          const $t27688 = next_piece(rng0);
          const $f27731 = $t27688._0;
          const $f27732 = $t27688._1;
          {
            const rng1 = (() => {
              return $f27732;
            })();
            {
              const first = (() => {
                return $f27731;
              })();
              {
                const $t27689 = (() => {
                  return spawn_piece(first, board, rng1);
                })();
                const $f27700 = $t27689._0;
                const $f27701 = $t27689._1;
                const $f27702 = $t27689._2;
                const $f27703 = $t27689._3;
                const $f27704 = $t27689._4;
                const $f27705 = $t27689._5;
                const $f27706 = $t27689._6;
                (() => {
                  return $f27706;
                })();
                {
                  const rng2 = (() => {
                    return $f27705;
                  })();
                  {
                    const next = (() => {
                      return $f27704;
                    })();
                    {
                      const y = (() => {
                        return $f27703;
                      })();
                      {
                        const x = (() => {
                          return $f27702;
                        })();
                        {
                          const rot = (() => {
                            return $f27701;
                          })();
                          {
                            const piece = (() => {
                              return $f27700;
                            })();
                            (() => {
                              {
                                const $t27501_i9436 = (() => {
                                  {
                                    const go_i3676_i9433 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
                                    {
                                      const $t177_i3678_i9435 = { $: "Nil" };
                                      return go$apply$0(go_i3676_i9433, 19, $t177_i3678_i9435);
                                    }
                                  }
                                })();
                                {
                                  const $t27515_i9437 = { $: "$Clo_$lam27502$3688", _0: $lam27502$apply$3688, _1: board };
                                  {
                                    const f_i3672_i9438 = $t27515_i9437;
                                    {
                                      const go_i3673_i9439 = { $: "$Clo_go$4713", _0: go$apply$4713, _1: f_i3672_i9438 };
                                      return go$apply$4713(go_i3673_i9439, $t27501_i9436);
                                    }
                                  }
                                }
                              }
                            })();
                            (() => {
                              {
                                const base_cells_i9427 = TetrisLogic$piece_cells(piece);
                                {
                                  const rotated_i9428 = rotate_n(base_cells_i9427, rot);
                                  {
                                    const $t27539_i9429 = { $: "$Clo_$lam27516$3690", _0: $lam27516$apply$3690, _1: x, _2: y, _3: piece };
                                    {
                                      const f_i3680_i9430 = $t27539_i9429;
                                      {
                                        const go_i3681_i9431 = { $: "$Clo_go$4715", _0: go$apply$4715, _1: f_i3680_i9430 };
                                        return go$apply$4715(go_i3681_i9431, rotated_i9428);
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
                                const $t27691 = (() => {
                                  {
                                    let $t27690;
                                    switch (next.$) {
                                      case "I": {
                                        $t27690 = "I";
                                        break;
                                      }
                                      case "O": {
                                        $t27690 = "O";
                                        break;
                                      }
                                      case "T": {
                                        $t27690 = "T";
                                        break;
                                      }
                                      case "S": {
                                        $t27690 = "S";
                                        break;
                                      }
                                      case "Z": {
                                        $t27690 = "Z";
                                        break;
                                      }
                                      case "J": {
                                        $t27690 = "J";
                                        break;
                                      }
                                      case "L": {
                                        $t27690 = "L";
                                        break;
                                      }
                                      default: {
                                        $t27690 = (() => { throw new Error("non-exhaustive pattern match"); })();
                                        break;
                                      }
                                    }
                                    {
                                      const $rc_792 = ("Next: " + $t27690);
                                      return $rc_792;
                                    }
                                  }
                                })();
                                return set_text_if_found("next", $t27691);
                              }
                            })();
                            set_text_if_found("game-over", "");
                            (() => {
                              Dom$set_attr(el, "data-paused", "false");
                              return set_text_if_found("pause-status", "");
                            })();
                            (() => {
                              {
                                const $t27693 = (() => {
                                  {
                                    const $t27692 = (() => {
                                      {
                                        const $t7119_i9417 = { $: "Nil" };
                                        {
                                          const $t7121_i9418 = { $: "$Clo_$lam7120$4717", _0: $lam7120$apply$4717 };
                                          {
                                            const rev_i9419 = Array$fold_left$PVec_Int$List_V__22342$Fn_List_V__22343_V__22343_List_V__22343(board, $t7119_i9417, $t7121_i9418);
                                            {
                                              const go_i4053_i9420 = { $: "$Clo_go$5140", _0: go$apply$5140 };
                                              {
                                                const $t6726_i4054_i9421 = { $: "Nil" };
                                                return go$apply$5140(go_i4053_i9420, rev_i9419, $t6726_i4054_i9421);
                                              }
                                            }
                                          }
                                        }
                                      }
                                    })();
                                    {
                                      const $t27444_i9411 = { $: "$Clo_$lam27443$3679", _0: $lam27443$apply$3679 };
                                      {
                                        const $t27445_i9415 = (() => {
                                          {
                                            const f_i3651_i9412 = $t27444_i9411;
                                            {
                                              const go_i3652_i9413 = { $: "$Clo_go$4131", _0: go$apply$4131, _1: f_i3651_i9412 };
                                              {
                                                const $t267_i3653_i9414 = { $: "Nil" };
                                                return go$apply$4131(go_i3652_i9413, $t27692, $t267_i3653_i9414);
                                              }
                                            }
                                          }
                                        })();
                                        return march_string_join($t27445_i9415, ",");
                                      }
                                    }
                                  }
                                })();
                                return Dom$set_attr(el, "data-board", $t27693);
                              }
                            })();
                            (() => {
                              {
                                const $t27694 = (() => {
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
                                return Dom$set_attr(el, "data-piece", $t27694);
                              }
                            })();
                            (() => {
                              {
                                const $t27695 = String(rot);
                                return Dom$set_attr(el, "data-rot", $t27695);
                              }
                            })();
                            (() => {
                              {
                                const $t27696 = String(x);
                                return Dom$set_attr(el, "data-x", $t27696);
                              }
                            })();
                            (() => {
                              {
                                const $t27697 = String(y);
                                return Dom$set_attr(el, "data-y", $t27697);
                              }
                            })();
                            (() => {
                              {
                                const $t27698 = (() => {
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
                                return Dom$set_attr(el, "data-next", $t27698);
                              }
                            })();
                            (() => {
                              return Dom$set_attr(el, "data-score", "0");
                            })();
                            (() => {
                              return Dom$set_attr(el, "data-lines", "0");
                            })();
                            (() => {
                              {
                                const $t27699 = String(rng2);
                                return Dom$set_attr(el, "data-rng", $t27699);
                              }
                            })();
                            return Dom$set_attr(el, "data-over", "false");
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

function handle_key(ev) {
  {
    const $t27750 = Dom$event_key(ev);
    if ($t27750 === "r") {
      return restart();
    } else if ($t27750 === "R") {
      return restart();
    } else if ($t27750 === "p") {
      return toggle_pause();
    } else if ($t27750 === "P") {
      return toggle_pause();
    } else {
      return (() => {
        {
          const key = $t27750;
          {
            const $t27751 = (() => {
              {
                const $t27656_i3746 = (() => {
                  {
                    const $t27655_i3745 = state_el();
                    return get_str_attr($t27655_i3745, "data-paused", "false");
                  }
                })();
                return ($t27656_i3746 === "true");
              }
            })();
            if ($t27751 === true) {
              return {  };
            } else {
              return (() => {
                if ($t27750 === "ArrowLeft") {
                  return (() => {
                    {
                      const $t27752 = (-1);
                      {
                        const $t27676_i3736 = { $: "$Clo_$lam27669$3722", _0: $lam27669$apply$3722, _1: $t27752, _2: 0 };
                        return with_state($t27676_i3736);
                      }
                    }
                  })();
                } else if ($t27750 === "ArrowRight") {
                  return (() => {
                    {
                      const $t27676_i3739 = { $: "$Clo_$lam27669$3722", _0: $lam27669$apply$3722, _1: 1, _2: 0 };
                      return with_state($t27676_i3739);
                    }
                  })();
                } else if ($t27750 === "ArrowDown") {
                  return (() => {
                    {
                      const $t27676_i3742 = { $: "$Clo_$lam27669$3722", _0: $lam27669$apply$3722, _1: 0, _2: 1 };
                      return with_state($t27676_i3742);
                    }
                  })();
                } else if ($t27750 === "ArrowUp") {
                  return (() => {
                    {
                      const $t27681_i3743 = { $: "$Clo_$lam27677$3723", _0: $lam27677$apply$3723 };
                      return with_state($t27681_i3743);
                    }
                  })();
                } else if ($t27750 === " ") {
                  return (() => {
                    {
                      const $t27687_i3744 = { $: "$Clo_$lam27685$3724", _0: $lam27685$apply$3724 };
                      return with_state($t27687_i3744);
                    }
                  })();
                } else {
                  return (() => {
                    return {  };
                  })();
                }
              })();
            }
          }
        }
      })();
    }
  }
}
const handle_key$clo = { _0: ($_, ev) => handle_key(ev) };

function main() {
  {
    const $t27771 = Dom$find("board");
    switch ($t27771.$) {
      case "None": {
        return {  };
      }
      case "Some": {
        const $f27777 = $t27771._0;
        {
          const board_el = $f27777;
          (() => {
            {
              const $t27738_i9444 = (() => {
                {
                  const go_i3731_i9441 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
                  {
                    const $t177_i3733_i9443 = { $: "Nil" };
                    return go$apply$0(go_i3731_i9441, 19, $t177_i3733_i9443);
                  }
                }
              })();
              {
                const $t27749_i9445 = { $: "$Clo_$lam27739$3737", _0: $lam27739$apply$3737, _1: board_el };
                {
                  const f_i3727_i9446 = $t27749_i9445;
                  {
                    const go_i3728_i9447 = { $: "$Clo_go$4713", _0: go$apply$4713, _1: f_i3727_i9446 };
                    return go$apply$4713(go_i3728_i9447, $t27738_i9444);
                  }
                }
              }
            }
          })();
          restart();
          (() => {
            {
              const $t27772 = dom_body();
              {
                const $t27774 = { $: "$Clo_$lam27773$3768", _0: $lam27773$apply$3768 };
                return Dom$listen($t27772, "keydown", $t27774);
              }
            }
          })();
          {
            const $t27776 = { $: "$Clo_$lam27775$3769", _0: $lam27775$apply$3769 };
            return Dom$set_interval(500, $t27776);
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
                          const go_i4047 = { $: "$Clo_go$5138", _0: go$apply$5138 };
                          return go$apply$5138(go_i4047, tail, 0);
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
                    const go_i4523 = { $: "$Clo_go$5138", _0: go$apply$5138 };
                    return go$apply$5138(go_i4523, tail, 0);
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
                              const go_i4520 = { $: "$Clo_go$5288", _0: go$apply$5288, _1: elem };
                              {
                                const $t6768_i4521 = { $: "Nil" };
                                return go$apply$5288(go_i4520, tail, $t6768_i4521);
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
              const $t6809_i4904 = (idx >> shift);
              return ($t6809_i4904 & 31);
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

function Array$fold_left$PVec_Int$List_V__22342$Fn_List_V__22343_V__22343_List_V__22343(v, acc, f) {
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
              return Array$trie_fold$List_V__22342$TrieNode_Int$Fn_List_V__22343_V__22343_List_V__22343(acc, root, f);
            })();
            {
              const go = { $: "$Clo_go$5147", _0: go$apply$5147, _1: f };
              return go$apply$5147(go, acc2, tail);
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
const Array$fold_left$PVec_Int$List_V__22342$Fn_List_V__22343_V__22343_List_V__22343$clo = { _0: ($_, v, acc, f) => Array$fold_left$PVec_Int$List_V__22342$Fn_List_V__22343_V__22343_List_V__22343(v, acc, f) };

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
                          const go_i4922 = { $: "$Clo_go$5138", _0: go$apply$5138 };
                          return go$apply$5138(go_i4922, tail, 0);
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
                                      const rev_onto_i4918 = { $: "$Clo_rev_onto$5450", _0: rev_onto$apply$5450 };
                                      {
                                        const go_i4919 = { $: "$Clo_go$5452", _0: go$apply$5452, _1: rev_onto_i4918, _2: val };
                                        {
                                          const $t6752_i4920 = { $: "Nil" };
                                          return go$apply$5452(go_i4919, tail, $t6982, $t6752_i4920);
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
                                    const ascend_i4912 = { $: "$Clo_ascend$5454", _0: ascend$apply$5454 };
                                    {
                                      const descend_i4913 = { $: "$Clo_descend$5456", _0: descend$apply$5456, _1: ascend_i4912, _2: idx, _3: val };
                                      {
                                        const $t6832_i4914 = { $: "Nil" };
                                        return descend$apply$5456(descend_i4913, root, shift, $t6832_i4914);
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
                        const go_i4969 = { $: "$Clo_go$5481", _0: go$apply$5481 };
                        {
                          const $t6838_i4970 = { $: "TrieLeaf", _0: leaf_values };
                          return go$apply$5481(go_i4969, shift, $t6838_i4970);
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
                const insert = { $: "$Clo_insert$5290", _0: insert$apply$5290, _1: leaf_values };
                {
                  const $t6880 = insert$apply$5290(insert, root, trie_leaf_count, shift);
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

function Array$trie_fold$List_V__22342$TrieNode_Int$Fn_List_V__22343_V__22343_List_V__22343(acc, node, f) {
  switch (node.$) {
    case "TrieEmpty": {
      return acc;
    }
    case "TrieLeaf": {
      const $f6921 = node._0;
      {
        const values = $f6921;
        {
          const go = { $: "$Clo_go$5446", _0: go$apply$5446, _1: f };
          return go$apply$5446(go, acc, values);
        }
      }
    }
    case "TrieBranch": {
      const $f6922 = node._0;
      {
        const children = $f6922;
        {
          const go = { $: "$Clo_go$5448", _0: go$apply$5448, _1: f };
          return go$apply$5448(go, acc, children);
        }
      }
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Array$trie_fold$List_V__22342$TrieNode_Int$Fn_List_V__22343_V__22343_List_V__22343$clo = { _0: ($_, acc, node, f) => Array$trie_fold$List_V__22342$TrieNode_Int$Fn_List_V__22343_V__22343_List_V__22343(acc, node, f) };

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

function $lam27397$apply$3673($clo, c) {
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
        const $f27402 = c._0;
        const $f27403 = c._1;
        {
          const dy = (() => {
            return $f27403;
          })();
          {
            const dx = (() => {
              return $f27402;
            })();
            {
              const x = (origin_x + dx);
              {
                const y = (origin_y + dy);
                {
                  const $t27399 = (() => {
                    {
                      const $t27398 = (() => {
                        {
                          const $t27394_i9457 = (() => {
                            {
                              const $t27392_i9455 = (() => {
                                {
                                  const $t27389_i9453 = (x >= 0);
                                  {
                                    const $t27391_i9454 = (x < 10);
                                    return ($t27389_i9453 && $t27391_i9454);
                                  }
                                }
                              })();
                              {
                                const $t27393_i9456 = (y >= 0);
                                return ($t27392_i9455 && $t27393_i9456);
                              }
                            }
                          })();
                          {
                            const $t27396_i9458 = (y < 20);
                            return ($t27394_i9457 && $t27396_i9458);
                          }
                        }
                      })();
                      return (!$t27398);
                    }
                  })();
                  if ($t27399 === true) {
                    return true;
                  } else {
                    return (() => {
                      {
                        const $t27401 = (() => {
                          {
                            const $t27400 = (() => {
                              {
                                const $t27321_i9450 = (y * 10);
                                return ($t27321_i9450 + x);
                              }
                            })();
                            return Array$get$PVec_Int$Int(board, $t27400);
                          }
                        })();
                        return ($t27401 !== 0);
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
const $lam27397$apply$3673$clo = { _0: ($_, $clo, c) => $lam27397$apply$3673($clo, c) };

function $lam27421$apply$3675($clo, x) {
  {
    const board = (() => {
      return $clo._1;
    })();
    {
      const y = (() => {
        return $clo._2;
      })();
      {
        const $t27423 = (() => {
          {
            const $t27422 = (() => {
              {
                const $t27321_i9461 = (y * 10);
                return ($t27321_i9461 + x);
              }
            })();
            return Array$get$PVec_Int$Int(board, $t27422);
          }
        })();
        return ($t27423 !== 0);
      }
    }
  }
}
const $lam27421$apply$3675$clo = { _0: ($_, $clo, x) => $lam27421$apply$3675($clo, x) };

function $lam27427$apply$3676($clo, x) {
  {
    const board = (() => {
      return $clo._1;
    })();
    {
      const y = (() => {
        return $clo._2;
      })();
      {
        const $t27428 = (() => {
          {
            const $t27321_i9464 = (y * 10);
            return ($t27321_i9464 + x);
          }
        })();
        return Array$get$PVec_Int$Int(board, $t27428);
      }
    }
  }
}
const $lam27427$apply$3676$clo = { _0: ($_, $clo, x) => $lam27427$apply$3676($clo, x) };

function $lam27431$apply$3677($clo, y) {
  {
    const board = (() => {
      return $clo._1;
    })();
    {
      const $t27432 = (() => {
        {
          const $t27420_i9470 = (() => {
            {
              const go_i3616_i9467 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
              {
                const $t177_i3618_i9469 = { $: "Nil" };
                return go$apply$0(go_i3616_i9467, 9, $t177_i3618_i9469);
              }
            }
          })();
          {
            const $t27424_i9471 = { $: "$Clo_$lam27421$3675", _0: $lam27421$apply$3675, _1: board, _2: y };
            return List$all$List_Int$Fn_Int_Bool($t27420_i9470, $t27424_i9471);
          }
        }
      })();
      return (!$t27432);
    }
  }
}
const $lam27431$apply$3677$clo = { _0: ($_, $clo, y) => $lam27431$apply$3677($clo, y) };

function $lam27436$apply$3678($clo, y) {
  {
    const board = (() => {
      return $clo._1;
    })();
    {
      const $t27426_i9477 = (() => {
        {
          const go_i3625_i9474 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
          {
            const $t177_i3627_i9476 = { $: "Nil" };
            return go$apply$0(go_i3625_i9474, 9, $t177_i3627_i9476);
          }
        }
      })();
      {
        const $t27429_i9478 = { $: "$Clo_$lam27427$3676", _0: $lam27427$apply$3676, _1: board, _2: y };
        {
          const f_i3620_i9479 = $t27429_i9478;
          {
            const go_i3621_i9480 = { $: "$Clo_go$4286", _0: go$apply$4286, _1: f_i3620_i9479 };
            {
              const $t267_i3622_i9481 = { $: "Nil" };
              return go$apply$4286(go_i3621_i9480, $t27426_i9477, $t267_i3622_i9481);
            }
          }
        }
      }
    }
  }
}
const $lam27436$apply$3678$clo = { _0: ($_, $clo, y) => $lam27436$apply$3678($clo, y) };

function $lam27443$apply$3679($clo, x) {
  return String(x);
}
const $lam27443$apply$3679$clo = { _0: ($_, $clo, x) => $lam27443$apply$3679($clo, x) };

function $lam27447$apply$3680($clo, x) {
  {
    const $t27448 = march_string_to_int(x);
    return Option$unwrap_or$Option_Int$Int($t27448, 0);
  }
}
const $lam27447$apply$3680$clo = { _0: ($_, $clo, x) => $lam27447$apply$3680($clo, x) };

function $lam27502$apply$3688($clo, y) {
  {
    const board = (() => {
      return $clo._1;
    })();
    {
      const $t27504 = (() => {
        {
          const go_i7269 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
          {
            const $t177_i7271 = { $: "Nil" };
            return go$apply$0(go_i7269, 9, $t177_i7271);
          }
        }
      })();
      {
        const $t27514 = (() => {
          return { $: "$Clo_$lam27505$3689", _0: $lam27505$apply$3689, _1: board, _2: y };
        })();
        {
          const f_i7265 = $t27514;
          {
            const go_i7266 = { $: "$Clo_go$4713", _0: go$apply$4713, _1: f_i7265 };
            return go$apply$4713(go_i7266, $t27504);
          }
        }
      }
    }
  }
}
const $lam27502$apply$3688$clo = { _0: ($_, $clo, y) => $lam27502$apply$3688($clo, y) };

function $lam27505$apply$3689($clo, x) {
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
            const $t27321_i9484 = (y * 10);
            return ($t27321_i9484 + x);
          }
        })();
        {
          const v = (() => {
            return Array$get$PVec_Int$Int(board, idx);
          })();
          {
            const id = (() => {
              {
                const $t27508 = (() => {
                  {
                    const $t27507 = (() => {
                      {
                        const $t27506 = String(x);
                        {
                          const $rc_1168 = ("cell-" + $t27506);
                          return $rc_1168;
                        }
                      }
                    })();
                    {
                      const $rc_1167 = ($t27507 + "-");
                      return $rc_1167;
                    }
                  }
                })();
                {
                  const $t27509 = String(y);
                  {
                    const $rc_1166 = ($t27508 + $t27509);
                    return $rc_1166;
                  }
                }
              }
            })();
            {
              const $t27510 = Dom$find(id);
              switch ($t27510.$) {
                case "None": {
                  return {  };
                }
                case "Some": {
                  const $f27513 = $t27510._0;
                  {
                    const cell = $f27513;
                    {
                      const $t27511 = (v === 0);
                      if ($t27511 === true) {
                        return Dom$set_style(cell, "background", "");
                      } else {
                        return (() => {
                          {
                            let $t27512;
                            if (v === 1) {
                              $t27512 = "#00CED1";
                            } else if (v === 2) {
                              $t27512 = "#FFD700";
                            } else if (v === 3) {
                              $t27512 = "#9B59B6";
                            } else if (v === 4) {
                              $t27512 = "#2ECC71";
                            } else if (v === 5) {
                              $t27512 = "#E74C3C";
                            } else if (v === 6) {
                              $t27512 = "#3498DB";
                            } else if (v === 7) {
                              $t27512 = "#F39C12";
                            } else {
                              $t27512 = "";
                            }
                            return Dom$set_style(cell, "background", $t27512);
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
const $lam27505$apply$3689$clo = { _0: ($_, $clo, x) => $lam27505$apply$3689($clo, x) };

function $lam27516$apply$3690($clo, c) {
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
        const $f27533 = c._0;
        const $f27534 = c._1;
        {
          const dy = (() => {
            return $f27534;
          })();
          {
            const dx = (() => {
              return $f27533;
            })();
            {
              const x = (ox + dx);
              {
                const y = (oy + dy);
                {
                  const $t27525 = (() => {
                    {
                      const $t27522 = (() => {
                        {
                          const $t27520 = (() => {
                            {
                              const $t27517 = (x >= 0);
                              {
                                const $t27519 = (x < 10);
                                return ($t27517 && $t27519);
                              }
                            }
                          })();
                          {
                            const $t27521 = (y >= 0);
                            return ($t27520 && $t27521);
                          }
                        }
                      })();
                      {
                        const $t27524 = (y < 20);
                        return ($t27522 && $t27524);
                      }
                    }
                  })();
                  if ($t27525 === true) {
                    return (() => {
                      {
                        const id = (() => {
                          {
                            const $t27528 = (() => {
                              {
                                const $t27527 = (() => {
                                  {
                                    const $t27526 = String(x);
                                    {
                                      const $rc_1171 = ("cell-" + $t27526);
                                      return $rc_1171;
                                    }
                                  }
                                })();
                                {
                                  const $rc_1170 = ($t27527 + "-");
                                  return $rc_1170;
                                }
                              }
                            })();
                            {
                              const $t27529 = String(y);
                              {
                                const $rc_1169 = ($t27528 + $t27529);
                                return $rc_1169;
                              }
                            }
                          }
                        })();
                        {
                          const $t27530 = Dom$find(id);
                          switch ($t27530.$) {
                            case "None": {
                              return {  };
                            }
                            case "Some": {
                              const $f27532 = $t27530._0;
                              {
                                const cell = $f27532;
                                {
                                  let $t27531;
                                  switch (piece.$) {
                                    case "I": {
                                      $t27531 = "#00CED1";
                                      break;
                                    }
                                    case "O": {
                                      $t27531 = "#FFD700";
                                      break;
                                    }
                                    case "T": {
                                      $t27531 = "#9B59B6";
                                      break;
                                    }
                                    case "S": {
                                      $t27531 = "#2ECC71";
                                      break;
                                    }
                                    case "Z": {
                                      $t27531 = "#E74C3C";
                                      break;
                                    }
                                    case "J": {
                                      $t27531 = "#3498DB";
                                      break;
                                    }
                                    case "L": {
                                      $t27531 = "#F39C12";
                                      break;
                                    }
                                    default: {
                                      $t27531 = (() => { throw new Error("non-exhaustive pattern match"); })();
                                      break;
                                    }
                                  }
                                  return Dom$set_style(cell, "background", $t27531);
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
const $lam27516$apply$3690$clo = { _0: ($_, $clo, c) => $lam27516$apply$3690($clo, c) };

function $lam27663$apply$3721($clo, board, piece, rot, x, y, next, score, lines, rng) {
  {
    const $t27664 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t27664, rot);
      {
        const $t27666 = (() => {
          {
            const $t27665 = (y + 1);
            {
              const $t27408_i7284 = { $: "$Clo_$lam27397$3673", _0: $lam27397$apply$3673, _1: board, _2: x, _3: $t27665 };
              return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t27408_i7284);
            }
          }
        })();
        if ($t27666 === true) {
          return (() => {
            {
              const $rc_1172 = lock_and_advance(board, piece, rot, x, y, next, score, lines, rng);
              return $rc_1172;
            }
          })();
        } else {
          return (() => {
            {
              const $t27667 = (y + 1);
              return { _0: board, _1: piece, _2: rot, _3: x, _4: $t27667, _5: next, _6: score, _7: lines, _8: rng, _9: false };
            }
          })();
        }
      }
    }
  }
}
const $lam27663$apply$3721$clo = { _0: ($_, $clo, board, piece, rot, x, y, next, score, lines, rng) => $lam27663$apply$3721($clo, board, piece, rot, x, y, next, score, lines, rng) };

function $lam27669$apply$3722($clo, board, piece, rot, x, y, next, score, lines, rng) {
  {
    const dx = (() => {
      return $clo._1;
    })();
    {
      const dy = (() => {
        return $clo._2;
      })();
      {
        const $t27670 = TetrisLogic$piece_cells(piece);
        {
          const cells = rotate_n($t27670, rot);
          {
            const $t27673 = (() => {
              {
                const $t27671 = (x + dx);
                {
                  const $t27672 = (y + dy);
                  {
                    const $t27408_i7289 = { $: "$Clo_$lam27397$3673", _0: $lam27397$apply$3673, _1: board, _2: $t27671, _3: $t27672 };
                    return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t27408_i7289);
                  }
                }
              }
            })();
            if ($t27673 === true) {
              return { _0: board, _1: piece, _2: rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: rng, _9: false };
            } else {
              return (() => {
                {
                  const $t27674 = (x + dx);
                  {
                    const $t27675 = (y + dy);
                    return { _0: board, _1: piece, _2: rot, _3: $t27674, _4: $t27675, _5: next, _6: score, _7: lines, _8: rng, _9: false };
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
const $lam27669$apply$3722$clo = { _0: ($_, $clo, board, piece, rot, x, y, next, score, lines, rng) => $lam27669$apply$3722($clo, board, piece, rot, x, y, next, score, lines, rng) };

function $lam27677$apply$3723($clo, board, piece, rot, x, y, next, score, lines, rng) {
  {
    const new_rot = (() => {
      {
        const $t27678 = (rot + 1);
        return ($t27678 % 4);
      }
    })();
    {
      const $t27679 = TetrisLogic$piece_cells(piece);
      {
        const cells = rotate_n($t27679, new_rot);
        {
          const $t27680 = (() => {
            {
              const $t27408_i7294 = { $: "$Clo_$lam27397$3673", _0: $lam27397$apply$3673, _1: board, _2: x, _3: y };
              return List$any$List_T_Int_Int$Fn_T_Int_Int_Bool(cells, $t27408_i7294);
            }
          })();
          if ($t27680 === true) {
            return { _0: board, _1: piece, _2: rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: rng, _9: false };
          } else {
            return { _0: board, _1: piece, _2: new_rot, _3: x, _4: y, _5: next, _6: score, _7: lines, _8: rng, _9: false };
          }
        }
      }
    }
  }
}
const $lam27677$apply$3723$clo = { _0: ($_, $clo, board, piece, rot, x, y, next, score, lines, rng) => $lam27677$apply$3723($clo, board, piece, rot, x, y, next, score, lines, rng) };

function $lam27685$apply$3724($clo, board, piece, rot, x, y, next, score, lines, rng) {
  {
    const $t27686 = TetrisLogic$piece_cells(piece);
    {
      const cells = rotate_n($t27686, rot);
      {
        const final_y = (() => {
          return fall_from(board, cells, x, y);
        })();
        return lock_and_advance(board, piece, rot, x, final_y, next, score, lines, rng);
      }
    }
  }
}
const $lam27685$apply$3724$clo = { _0: ($_, $clo, board, piece, rot, x, y, next, score, lines, rng) => $lam27685$apply$3724($clo, board, piece, rot, x, y, next, score, lines, rng) };

function $lam27739$apply$3737($clo, y) {
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
          const $t27741 = (() => {
            {
              const go_i7302 = { $: "$Clo_go$0", _0: go$apply$0, _1: 0 };
              {
                const $t177_i7304 = { $: "Nil" };
                return go$apply$0(go_i7302, 9, $t177_i7304);
              }
            }
          })();
          {
            const $t27748 = (() => {
              return { $: "$Clo_$lam27742$3738", _0: $lam27742$apply$3738, _1: row, _2: y };
            })();
            {
              const f_i7298 = $t27748;
              {
                const go_i7299 = { $: "$Clo_go$4713", _0: go$apply$4713, _1: f_i7298 };
                return go$apply$4713(go_i7299, $t27741);
              }
            }
          }
        }
      })();
      return Dom$append(container, row);
    }
  }
}
const $lam27739$apply$3737$clo = { _0: ($_, $clo, y) => $lam27739$apply$3737($clo, y) };

function $lam27742$apply$3738($clo, x) {
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
            const $t27747 = (() => {
              {
                const $t27745 = (() => {
                  {
                    const $t27744 = (() => {
                      {
                        const $t27743 = String(x);
                        {
                          const $rc_1175 = ("cell-" + $t27743);
                          return $rc_1175;
                        }
                      }
                    })();
                    {
                      const $rc_1174 = ($t27744 + "-");
                      return $rc_1174;
                    }
                  }
                })();
                {
                  const $t27746 = String(y);
                  {
                    const $rc_1173 = ($t27745 + $t27746);
                    return $rc_1173;
                  }
                }
              }
            })();
            return Dom$set_attr(cell, "id", $t27747);
          }
        })();
        return Dom$append(row, cell);
      }
    }
  }
}
const $lam27742$apply$3738$clo = { _0: ($_, $clo, x) => $lam27742$apply$3738($clo, x) };

function $lam27773$apply$3768($clo, ev) {
  return handle_key(ev);
}
const $lam27773$apply$3768$clo = { _0: ($_, $clo, ev) => $lam27773$apply$3768($clo, ev) };

function $lam27775$apply$3769($clo, _) {
  {
    const $t27662_i9488 = (() => {
      {
        const $t27656_i3714_i9487 = (() => {
          {
            const $t27655_i3713_i9486 = state_el();
            return get_str_attr($t27655_i3713_i9486, "data-paused", "false");
          }
        })();
        return ($t27656_i3714_i9487 === "true");
      }
    })();
    if ($t27662_i9488 === true) {
      return {  };
    } else {
      return (() => {
        {
          const $t27668_i9489 = { $: "$Clo_$lam27663$3721", _0: $lam27663$apply$3721 };
          return with_state($t27668_i9489);
        }
      })();
    }
  }
}
const $lam27775$apply$3769$clo = { _0: ($_, $clo, _) => $lam27775$apply$3769($clo, _) };

function go$apply$3770($clo, lst, acc) {
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
const go$apply$3770$clo = { _0: ($_, $clo, lst, acc) => go$apply$3770($clo, lst, acc) };

function go$apply$4030($clo, lst, acc) {
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
const go$apply$4030$clo = { _0: ($_, $clo, lst, acc) => go$apply$4030($clo, lst, acc) };

function go$apply$4131($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i7486 = { $: "$Clo_go$4030", _0: go$apply$4030 };
            {
              const $t250_i7487 = { $: "Nil" };
              return go$apply$4030(go_i7486, acc, $t250_i7487);
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
const go$apply$4131$clo = { _0: ($_, $clo, lst, acc) => go$apply$4131($clo, lst, acc) };

function go$apply$4286($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i7713 = { $: "$Clo_go$3770", _0: go$apply$3770 };
            {
              const $t250_i7714 = { $: "Nil" };
              return go$apply$3770(go_i7713, acc, $t250_i7714);
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
const go$apply$4286$clo = { _0: ($_, $clo, lst, acc) => go$apply$4286($clo, lst, acc) };

function go$apply$4297($clo, i, acc) {
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
const go$apply$4297$clo = { _0: ($_, $clo, i, acc) => go$apply$4297($clo, i, acc) };

function go$apply$4485($clo, lst, acc) {
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
const go$apply$4485$clo = { _0: ($_, $clo, lst, acc) => go$apply$4485($clo, lst, acc) };

function go$apply$4591($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8252 = { $: "$Clo_go$3770", _0: go$apply$3770 };
            {
              const $t250_i8253 = { $: "Nil" };
              return go$apply$3770(go_i8252, acc, $t250_i8253);
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
const go$apply$4591$clo = { _0: ($_, $clo, lst, acc) => go$apply$4591($clo, lst, acc) };

function go$apply$4619($clo, lst, acc) {
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
const go$apply$4619$clo = { _0: ($_, $clo, lst, acc) => go$apply$4619($clo, lst, acc) };

function go$apply$4696($clo, lst, acc) {
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
const go$apply$4696$clo = { _0: ($_, $clo, lst, acc) => go$apply$4696($clo, lst, acc) };

function go$apply$4698($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8381 = { $: "$Clo_go$5134", _0: go$apply$5134 };
            {
              const $t250_i8382 = { $: "Nil" };
              return go$apply$5134(go_i8381, acc, $t250_i8382);
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
const go$apply$4698$clo = { _0: ($_, $clo, lst, acc) => go$apply$4698($clo, lst, acc) };

function prepend_reversed$apply$4706($clo, sub, acc) {
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
const prepend_reversed$apply$4706$clo = { _0: ($_, $clo, sub, acc) => prepend_reversed$apply$4706($clo, sub, acc) };

function go$apply$4708($clo, lst, acc) {
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
              const go_i8390 = { $: "$Clo_go$3770", _0: go$apply$3770 };
              {
                const $t250_i8391 = { $: "Nil" };
                return go$apply$3770(go_i8390, acc, $t250_i8391);
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
const go$apply$4708$clo = { _0: ($_, $clo, lst, acc) => go$apply$4708($clo, lst, acc) };

function go$apply$4710($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8395 = { $: "$Clo_go$3770", _0: go$apply$3770 };
            {
              const $t250_i8396 = { $: "Nil" };
              return go$apply$3770(go_i8395, acc, $t250_i8396);
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
const go$apply$4710$clo = { _0: ($_, $clo, lst, acc) => go$apply$4710($clo, lst, acc) };

function go$apply$4713($clo, lst) {
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
const go$apply$4713$clo = { _0: ($_, $clo, lst) => go$apply$4713($clo, lst) };

function go$apply$4715($clo, lst) {
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
const go$apply$4715$clo = { _0: ($_, $clo, lst) => go$apply$4715($clo, lst) };

function $lam7120$apply$4717($clo, acc, x) {
  return { $: "Cons", _0: x, _1: acc };
}
const $lam7120$apply$4717$clo = { _0: ($_, $clo, acc, x) => $lam7120$apply$4717($clo, acc, x) };

function $lam27409$apply$4718($clo, b, c) {
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
        const $f27412 = c._0;
        const $f27413 = c._1;
        {
          const dy = (() => {
            return $f27413;
          })();
          {
            const dx = (() => {
              return $f27412;
            })();
            {
              const x = (origin_x + dx);
              {
                const y = (origin_y + dy);
                {
                  const $t27410 = (() => {
                    {
                      const $t27394_i9499 = (() => {
                        {
                          const $t27392_i9497 = (() => {
                            {
                              const $t27389_i9495 = (x >= 0);
                              {
                                const $t27391_i9496 = (x < 10);
                                return ($t27389_i9495 && $t27391_i9496);
                              }
                            }
                          })();
                          {
                            const $t27393_i9498 = (y >= 0);
                            return ($t27392_i9497 && $t27393_i9498);
                          }
                        }
                      })();
                      {
                        const $t27396_i9500 = (y < 20);
                        return ($t27394_i9499 && $t27396_i9500);
                      }
                    }
                  })();
                  if ($t27410 === true) {
                    return (() => {
                      {
                        const $t27411 = (() => {
                          {
                            const $t27321_i9492 = (y * 10);
                            return ($t27321_i9492 + x);
                          }
                        })();
                        return Array$set$PVec_Int$Int$Int(b, $t27411, color_idx);
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
const $lam27409$apply$4718$clo = { _0: ($_, $clo, b, c) => $lam27409$apply$4718($clo, b, c) };

function go$apply$5134($clo, lst, acc) {
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
const go$apply$5134$clo = { _0: ($_, $clo, lst, acc) => go$apply$5134($clo, lst, acc) };

function go$apply$5138($clo, xs, acc) {
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
const go$apply$5138$clo = { _0: ($_, $clo, xs, acc) => go$apply$5138($clo, xs, acc) };

function go$apply$5140($clo, xs, acc) {
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
const go$apply$5140$clo = { _0: ($_, $clo, xs, acc) => go$apply$5140($clo, xs, acc) };

function go$apply$5147($clo, a, xs) {
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
const go$apply$5147$clo = { _0: ($_, $clo, a, xs) => go$apply$5147($clo, a, xs) };

function go$apply$5288($clo, xs, acc) {
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
              const go_i8954 = { $: "$Clo_go$5479", _0: go$apply$5479 };
              {
                const $t6726_i8955 = { $: "Nil" };
                return go$apply$5479(go_i8954, $t6760, $t6726_i8955);
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
const go$apply$5288$clo = { _0: ($_, $clo, xs, acc) => go$apply$5288($clo, xs, acc) };

function insert$apply$5290($clo, node, leaf_idx, s) {
  {
    const leaf_values = (() => {
      return $clo._1;
    })();
    {
      const ascend = { $: "$Clo_ascend$5291", _0: ascend$apply$5291 };
      {
        const descend = (() => {
          return { $: "$Clo_descend$5293", _0: descend$apply$5293, _1: ascend, _2: leaf_idx, _3: leaf_values };
        })();
        {
          const $t6879 = { $: "Nil" };
          return descend$apply$5293(descend, node, s, $t6879);
        }
      }
    }
  }
}
const insert$apply$5290$clo = { _0: ($_, $clo, node, leaf_idx, s) => insert$apply$5290($clo, node, leaf_idx, s) };

function ascend$apply$5291($clo, nd, stk) {
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
                          const rev_onto_i8961 = { $: "$Clo_rev_onto$5482", _0: rev_onto$apply$5482 };
                          {
                            const go_i8962 = { $: "$Clo_go$5484", _0: go$apply$5484, _1: nd, _2: rev_onto_i8961 };
                            {
                              const $t6808_i8963 = { $: "Nil" };
                              return go$apply$5484(go_i8962, children, slot_i, $t6808_i8963);
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
const ascend$apply$5291$clo = { _0: ($_, $clo, nd, stk) => ascend$apply$5291($clo, nd, stk) };

function descend$apply$5293($clo, nd, s, path) {
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
                  return { $: "$Clo_$jp6875$5294", _0: $jp6875$apply$5294, _1: ascend, _2: leaf_values, _3: path, _4: s };
                })();
                {
                  const children = $f6874;
                  {
                    const slot = (() => {
                      {
                        const $t6860 = (s - 5);
                        {
                          const $t6809_i8981 = (leaf_idx >> $t6860);
                          return ($t6809_i8981 & 31);
                        }
                      }
                    })();
                    {
                      const n = (() => {
                        {
                          const go_i8978 = { $: "$Clo_go$5488", _0: go$apply$5488 };
                          return go$apply$5488(go_i8978, children, 0);
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
                                        const go_i8975 = { $: "$Clo_go$5481", _0: go$apply$5481 };
                                        {
                                          const $t6838_i8976 = { $: "TrieLeaf", _0: leaf_values };
                                          return go$apply$5481(go_i8975, $t6862, $t6838_i8976);
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t6864 = (() => {
                                      {
                                        const go_i8971 = { $: "$Clo_go$5486", _0: go$apply$5486, _1: $t6863 };
                                        {
                                          const $t6768_i8972 = { $: "Nil" };
                                          return go$apply$5486(go_i8971, children, $t6768_i8972);
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
                      const go_i8967 = { $: "$Clo_go$5481", _0: go$apply$5481 };
                      {
                        const $t6838_i8968 = { $: "TrieLeaf", _0: leaf_values };
                        return go$apply$5481(go_i8967, $t6872, $t6838_i8968);
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
const descend$apply$5293$clo = { _0: ($_, $clo, nd, s, path) => descend$apply$5293($clo, nd, s, path) };

function $jp6875$apply$5294($clo) {
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
                  const go_i8984 = { $: "$Clo_go$5481", _0: go$apply$5481 };
                  {
                    const $t6838_i8985 = { $: "TrieLeaf", _0: leaf_values };
                    return go$apply$5481(go_i8984, $t6872, $t6838_i8985);
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
const $jp6875$apply$5294$clo = { _0: ($_, $clo) => $jp6875$apply$5294($clo) };

function go$apply$5446($clo, a, vs) {
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
const go$apply$5446$clo = { _0: ($_, $clo, a, vs) => go$apply$5446($clo, a, vs) };

function go$apply$5448($clo, a, cs) {
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
                  return Array$trie_fold$List_V__22342$TrieNode_Int$Fn_List_V__22343_V__22343_List_V__22343(a, child, f);
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
const go$apply$5448$clo = { _0: ($_, $clo, a, cs) => go$apply$5448($clo, a, cs) };

function rev_onto$apply$5450($clo, rev_xs, ys) {
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
const rev_onto$apply$5450$clo = { _0: ($_, $clo, rev_xs, ys) => rev_onto$apply$5450($clo, rev_xs, ys) };

function go$apply$5452($clo, xs, i, acc) {
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
              const go_i9226 = { $: "$Clo_go$5479", _0: go$apply$5479 };
              {
                const $t6726_i9227 = { $: "Nil" };
                return go$apply$5479(go_i9226, acc, $t6726_i9227);
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
const go$apply$5452$clo = { _0: ($_, $clo, xs, i, acc) => go$apply$5452($clo, xs, i, acc) };

function ascend$apply$5454($clo, nd, stk) {
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
                          const rev_onto_i9233 = { $: "$Clo_rev_onto$5494", _0: rev_onto$apply$5494 };
                          {
                            const go_i9234 = { $: "$Clo_go$5496", _0: go$apply$5496, _1: nd, _2: rev_onto_i9233 };
                            {
                              const $t6808_i9235 = { $: "Nil" };
                              return go$apply$5496(go_i9234, children, slot, $t6808_i9235);
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
const ascend$apply$5454$clo = { _0: ($_, $clo, nd, stk) => ascend$apply$5454($clo, nd, stk) };

function descend$apply$5456($clo, n, s, path) {
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
                            const rev_onto_i9242 = { $: "$Clo_rev_onto$5450", _0: rev_onto$apply$5450 };
                            {
                              const go_i9243 = { $: "$Clo_go$5452", _0: go$apply$5452, _1: rev_onto_i9242, _2: val };
                              {
                                const $t6752_i9244 = { $: "Nil" };
                                return go$apply$5452(go_i9243, values, $t6824, $t6752_i9244);
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
                      const $t6809_i9247 = (idx >> s);
                      return ($t6809_i9247 & 31);
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
const descend$apply$5456$clo = { _0: ($_, $clo, n, s, path) => descend$apply$5456($clo, n, s, path) };

function go$apply$5479($clo, xs, acc) {
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
const go$apply$5479$clo = { _0: ($_, $clo, xs, acc) => go$apply$5479($clo, xs, acc) };

function go$apply$5481($clo, s, node) {
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
const go$apply$5481$clo = { _0: ($_, $clo, s, node) => go$apply$5481($clo, s, node) };

function rev_onto$apply$5482($clo, rev_xs, ys) {
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
const rev_onto$apply$5482$clo = { _0: ($_, $clo, rev_xs, ys) => rev_onto$apply$5482($clo, rev_xs, ys) };

function go$apply$5484($clo, xs, i, acc) {
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
              const go_i9285 = { $: "$Clo_go$5514", _0: go$apply$5514 };
              {
                const $t6726_i9286 = { $: "Nil" };
                return go$apply$5514(go_i9285, acc, $t6726_i9286);
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
const go$apply$5484$clo = { _0: ($_, $clo, xs, i, acc) => go$apply$5484($clo, xs, i, acc) };

function go$apply$5486($clo, xs, acc) {
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
              const go_i9290 = { $: "$Clo_go$5516", _0: go$apply$5516 };
              {
                const $t6726_i9291 = { $: "Nil" };
                return go$apply$5516(go_i9290, $t6760, $t6726_i9291);
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
const go$apply$5486$clo = { _0: ($_, $clo, xs, acc) => go$apply$5486($clo, xs, acc) };

function go$apply$5488($clo, xs, acc) {
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
const go$apply$5488$clo = { _0: ($_, $clo, xs, acc) => go$apply$5488($clo, xs, acc) };

function rev_onto$apply$5494($clo, rev_xs, ys) {
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
const rev_onto$apply$5494$clo = { _0: ($_, $clo, rev_xs, ys) => rev_onto$apply$5494($clo, rev_xs, ys) };

function go$apply$5496($clo, xs, i, acc) {
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
              const go_i9303 = { $: "$Clo_go$5518", _0: go$apply$5518 };
              {
                const $t6726_i9304 = { $: "Nil" };
                return go$apply$5518(go_i9303, acc, $t6726_i9304);
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
const go$apply$5496$clo = { _0: ($_, $clo, xs, i, acc) => go$apply$5496($clo, xs, i, acc) };

function go$apply$5514($clo, xs, acc) {
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
const go$apply$5514$clo = { _0: ($_, $clo, xs, acc) => go$apply$5514($clo, xs, acc) };

function go$apply$5516($clo, xs, acc) {
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
const go$apply$5516$clo = { _0: ($_, $clo, xs, acc) => go$apply$5516($clo, xs, acc) };

function go$apply$5518($clo, xs, acc) {
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
const go$apply$5518$clo = { _0: ($_, $clo, xs, acc) => go$apply$5518($clo, xs, acc) };

export { main };
main();
//# sourceMappingURL=tetris.mjs.map
