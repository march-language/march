import { march_float_round, march_float_to_string, march_int_and, march_int_div, march_int_div_euclid, march_int_mod, march_int_mod_euclid, march_int_not, march_int_or, march_int_popcount, march_int_shl, march_int_shr, march_int_xor, march_print, march_string_byte_length, march_string_join, march_string_split, march_string_to_int, march_unix_time } from "./march_runtime.mjs";

import { march_dom_request_animation_frame as dom_request_animation_frame, march_dom_window_size as dom_window_size, march_dom_pointer_pos as dom_pointer_pos, march_dom_store_set as dom_store_set, march_dom_store_get as dom_store_get, march_dom_key_presses as dom_key_presses, march_dom_taps as dom_taps, march_dom_set_attribute as dom_set_attribute, march_dom_get_element_by_id as dom_get_element_by_id } from "./march_dom.mjs";
import { march_audio_noise_burst as audio_noise_burst, march_audio_sweep as audio_sweep, march_audio_beep as audio_beep, march_audio_resume as audio_resume, march_audio_create as audio_create } from "./march_audio.mjs";
import { march_canvas_set_text_align as canvas_set_text_align, march_canvas_fill_text as canvas_fill_text, march_canvas_fill_noise_circle as canvas_fill_noise_circle, march_canvas_stroke as canvas_stroke, march_canvas_fill as canvas_fill, march_canvas_arc as canvas_arc, march_canvas_line_to as canvas_line_to, march_canvas_move_to as canvas_move_to, march_canvas_close_path as canvas_close_path, march_canvas_begin_path as canvas_begin_path, march_canvas_fill_rect as canvas_fill_rect, march_canvas_set_font as canvas_set_font, march_canvas_set_global_alpha as canvas_set_global_alpha, march_canvas_set_line_width as canvas_set_line_width, march_canvas_set_stroke_style as canvas_set_stroke_style, march_canvas_set_fill_style as canvas_set_fill_style, march_canvas_rotate as canvas_rotate, march_canvas_translate as canvas_translate, march_canvas_restore as canvas_restore, march_canvas_save as canvas_save, march_canvas_get_context as canvas_get_context } from "./march_canvas.mjs";


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
const float_round = { _0: ($_, a) => march_float_round(a) };
const dom_get_element_by_id$clo = { _0: ($_, p0) => dom_get_element_by_id(p0) };
const dom_set_attribute$clo = { _0: ($_, p0, p1, p2) => dom_set_attribute(p0, p1, p2) };
const dom_taps$clo = { _0: ($_, p0) => dom_taps(p0) };
const dom_key_presses$clo = { _0: ($_, ) => dom_key_presses() };
const dom_store_get$clo = { _0: ($_, p0) => dom_store_get(p0) };
const dom_store_set$clo = { _0: ($_, p0, p1) => dom_store_set(p0, p1) };
const dom_pointer_pos$clo = { _0: ($_, p0) => dom_pointer_pos(p0) };
const dom_window_size$clo = { _0: ($_, ) => dom_window_size() };
const dom_request_animation_frame$clo = { _0: ($_, p0) => dom_request_animation_frame(p0) };
const canvas_get_context$clo = { _0: ($_, p0) => canvas_get_context(p0) };
const canvas_save$clo = { _0: ($_, p0) => canvas_save(p0) };
const canvas_restore$clo = { _0: ($_, p0) => canvas_restore(p0) };
const canvas_translate$clo = { _0: ($_, p0, p1, p2) => canvas_translate(p0, p1, p2) };
const canvas_rotate$clo = { _0: ($_, p0, p1) => canvas_rotate(p0, p1) };
const canvas_set_fill_style$clo = { _0: ($_, p0, p1) => canvas_set_fill_style(p0, p1) };
const canvas_set_stroke_style$clo = { _0: ($_, p0, p1) => canvas_set_stroke_style(p0, p1) };
const canvas_set_line_width$clo = { _0: ($_, p0, p1) => canvas_set_line_width(p0, p1) };
const canvas_set_global_alpha$clo = { _0: ($_, p0, p1) => canvas_set_global_alpha(p0, p1) };
const canvas_set_font$clo = { _0: ($_, p0, p1) => canvas_set_font(p0, p1) };
const canvas_fill_rect$clo = { _0: ($_, p0, p1, p2, p3, p4) => canvas_fill_rect(p0, p1, p2, p3, p4) };
const canvas_begin_path$clo = { _0: ($_, p0) => canvas_begin_path(p0) };
const canvas_close_path$clo = { _0: ($_, p0) => canvas_close_path(p0) };
const canvas_move_to$clo = { _0: ($_, p0, p1, p2) => canvas_move_to(p0, p1, p2) };
const canvas_line_to$clo = { _0: ($_, p0, p1, p2) => canvas_line_to(p0, p1, p2) };
const canvas_arc$clo = { _0: ($_, p0, p1, p2, p3, p4, p5) => canvas_arc(p0, p1, p2, p3, p4, p5) };
const canvas_fill$clo = { _0: ($_, p0) => canvas_fill(p0) };
const canvas_stroke$clo = { _0: ($_, p0) => canvas_stroke(p0) };
const canvas_fill_noise_circle$clo = { _0: ($_, p0, p1, p2, p3, p4) => canvas_fill_noise_circle(p0, p1, p2, p3, p4) };
const canvas_fill_text$clo = { _0: ($_, p0, p1, p2, p3) => canvas_fill_text(p0, p1, p2, p3) };
const canvas_set_text_align$clo = { _0: ($_, p0, p1) => canvas_set_text_align(p0, p1) };
const audio_create$clo = { _0: ($_, ) => audio_create() };
const audio_resume$clo = { _0: ($_, p0) => audio_resume(p0) };
const audio_beep$clo = { _0: ($_, p0, p1, p2, p3) => audio_beep(p0, p1, p2, p3) };
const audio_sweep$clo = { _0: ($_, p0, p1, p2, p3, p4) => audio_sweep(p0, p1, p2, p3, p4) };
const audio_noise_burst$clo = { _0: ($_, p0, p1, p2) => audio_noise_burst(p0, p1, p2) };

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

function __eq_Canvas$Context(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
  }
  return true;
}

function __eq_Canvas$Image(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
  }
  return true;
}

function __eq_Audio$Ctx(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
  }
  return true;
}

function __eq_Perihelion$Combat$AsteroidMode(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "AsteroidDrifting": {
      return true;
    }
    case "AsteroidOrbiting": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_Perihelion$Combat$Asteroid(a, b) {
  if (a.x !== b.x) return false;
  if (a.y !== b.y) return false;
  if (a.vx !== b.vx) return false;
  if (a.vy !== b.vy) return false;
  if (a.radius !== b.radius) return false;
  if (a.shape_seed !== b.shape_seed) return false;
  if (!__eq_AsteroidMode(a.mode, b.mode)) return false;
  return true;
}

function __eq_Perihelion$Combat$ShipMode(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "ShipOrbiting": {
      if (a._0 !== b._0) return false;
      return true;
    }
    case "ShipFlying": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_Perihelion$Combat$Ship(a, b) {
  if (a.star_idx !== b.star_idx) return false;
  if (a.x !== b.x) return false;
  if (a.y !== b.y) return false;
  if (!__eq_ShipMode(a.mode, b.mode)) return false;
  if (a.fire_cooldown !== b.fire_cooldown) return false;
  if (a.idle_timer !== b.idle_timer) return false;
  if (a.hunter !== b.hunter) return false;
  return true;
}

function __eq_Perihelion$Combat$Shot(a, b) {
  if (a.x !== b.x) return false;
  if (a.y !== b.y) return false;
  if (a.vx !== b.vx) return false;
  if (a.vy !== b.vy) return false;
  if (a.ttl !== b.ttl) return false;
  return true;
}

function __eq_Perihelion$Combat$Pickup(a, b) {
  if (a.x !== b.x) return false;
  if (a.y !== b.y) return false;
  if (a.ttl !== b.ttl) return false;
  return true;
}

function __eq_Perihelion$Core$Orbit(a, b) {
  if (a.radius !== b.radius) return false;
  if (a.speed_mult !== b.speed_mult) return false;
  return true;
}

function __eq_Perihelion$Core$Star(a, b) {
  if (a.x !== b.x) return false;
  if (a.y !== b.y) return false;
  if (a.radius !== b.radius) return false;
  if (a.capture_radius !== b.capture_radius) return false;
  if (a.speed_mult !== b.speed_mult) return false;
  if (!__eq_List(a.orbits, b.orbits)) return false;
  return true;
}

function __eq_Perihelion$Core$BallMode(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Orbiting": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      if (a._2 !== b._2) return false;
      return true;
    }
    case "Flying": {
      if (a._0 !== b._0) return false;
      if (a._1 !== b._1) return false;
      return true;
    }
  }
  return true;
}

function __eq_Perihelion$Core$Phase(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Ready": {
      return true;
    }
    case "Playing": {
      return true;
    }
    case "Over": {
      return true;
    }
  }
  return true;
}

function __eq_Perihelion$Core$RunRecord(a, b) {
  if (a.score !== b.score) return false;
  if (a.stars !== b.stars) return false;
  if (a.max_mult !== b.max_mult) return false;
  return true;
}

function __eq_Perihelion$Core$Game(a, b) {
  if (a.seed !== b.seed) return false;
  if (!__eq_Phase(a.phase, b.phase)) return false;
  if (a.ball_x !== b.ball_x) return false;
  if (a.ball_y !== b.ball_y) return false;
  if (!__eq_BallMode(a.mode, b.mode)) return false;
  if (!__eq_List(a.stars, b.stars)) return false;
  if (a.current !== b.current) return false;
  if (a.score !== b.score) return false;
  if (a.best !== b.best) return false;
  if (a.camera_y !== b.camera_y) return false;
  if (a.camera_x !== b.camera_x) return false;
  if (!__eq_Random$Rng(a.rng, b.rng)) return false;
  if (!__eq_List(a.asteroids, b.asteroids)) return false;
  if (!__eq_List(a.ships, b.ships)) return false;
  if (!__eq_List(a.player_shots, b.player_shots)) return false;
  if (!__eq_List(a.enemy_shots, b.enemy_shots)) return false;
  if (!__eq_List(a.pickups, b.pickups)) return false;
  if (a.shield !== b.shield) return false;
  if (a.multiplier !== b.multiplier) return false;
  if (a.max_mult !== b.max_mult) return false;
  if (a.stars_chained !== b.stars_chained) return false;
  if (a.loop_angle !== b.loop_angle) return false;
  if (a.fire_cooldown !== b.fire_cooldown) return false;
  if (a.spawn_timer !== b.spawn_timer) return false;
  if (!__eq_List(a.runs, b.runs)) return false;
  if (a.view_w !== b.view_w) return false;
  if (a.view_h !== b.view_h) return false;
  if (!__eq_List(a.fx_bursts, b.fx_bursts)) return false;
  if (!__eq_Option(a.capture_flash, b.capture_flash)) return false;
  return true;
}

function __eq_Perihelion$Nebula$Cloud(a, b) {
  if (a.x !== b.x) return false;
  if (a.y !== b.y) return false;
  if (a.radius !== b.radius) return false;
  if (a.strength !== b.strength) return false;
  return true;
}

function __eq_Particle(a, b) {
  if (a.x !== b.x) return false;
  if (a.y !== b.y) return false;
  if (a.vx !== b.vx) return false;
  if (a.vy !== b.vy) return false;
  if (a.life !== b.life) return false;
  if (a.max_life !== b.max_life) return false;
  return true;
}

function __eq_Fx(a, b) {
  if (!__eq_List(a.trail, b.trail)) return false;
  if (a.t !== b.t) return false;
  if (!__eq_List(a.particles, b.particles)) return false;
  if (!__eq_Option(a.flash, b.flash)) return false;
  if (!__eq_Audio$Ctx(a.actx, b.actx)) return false;
  if (a.muted !== b.muted) return false;
  return true;
}

function Random$mix32(x) {
  {
    const x$sh1 = (() => {
      {
        const $t15533 = (x + 2654435769);
        return march_int_and($t15533, 4294967295);
      }
    })();
    {
      const x$sh2 = (() => {
        {
          const $t15535 = (() => {
            {
              const $t15534 = march_int_shr(x$sh1, 16);
              return march_int_xor(x$sh1, $t15534);
            }
          })();
          {
            const xh_i9651 = march_int_shr($t15535, 16);
            {
              const xl_i9652 = march_int_and($t15535, 65535);
              {
                const $t15524_i9657 = (() => {
                  {
                    const $t15522_i9655 = (() => {
                      {
                        const $t15521_i9654 = (() => {
                          {
                            const $t15520_i9653 = (xh_i9651 * 569420461);
                            return march_int_and($t15520_i9653, 65535);
                          }
                        })();
                        return ($t15521_i9654 * 65536);
                      }
                    })();
                    {
                      const $t15523_i9656 = (xl_i9652 * 569420461);
                      return ($t15522_i9655 + $t15523_i9656);
                    }
                  }
                })();
                return march_int_and($t15524_i9657, 4294967295);
              }
            }
          }
        }
      })();
      {
        const x$sh3 = (() => {
          {
            const $t15537 = (() => {
              {
                const $t15536 = march_int_shr(x$sh2, 15);
                return march_int_xor(x$sh2, $t15536);
              }
            })();
            {
              const xh_i9640 = march_int_shr($t15537, 16);
              {
                const xl_i9641 = march_int_and($t15537, 65535);
                {
                  const $t15524_i9646 = (() => {
                    {
                      const $t15522_i9644 = (() => {
                        {
                          const $t15521_i9643 = (() => {
                            {
                              const $t15520_i9642 = (xh_i9640 * 1935289751);
                              return march_int_and($t15520_i9642, 65535);
                            }
                          })();
                          return ($t15521_i9643 * 65536);
                        }
                      })();
                      {
                        const $t15523_i9645 = (xl_i9641 * 1935289751);
                        return ($t15522_i9644 + $t15523_i9645);
                      }
                    }
                  })();
                  return march_int_and($t15524_i9646, 4294967295);
                }
              }
            }
          }
        })();
        {
          const $t15538 = march_int_shr(x$sh3, 15);
          return march_int_xor(x$sh3, $t15538);
        }
      }
    }
  }
}
const Random$mix32$clo = { _0: ($_, x) => Random$mix32(x) };

function Random$warmup(rng, k) {
  {
    const $t15539 = (k <= 0);
    if ($t15539 === true) {
      return rng;
    } else {
      return (() => {
        {
          const $p15541 = Random$next_raw(rng);
          {
            const r2 = $p15541._1;
            {
              const $t15540 = (k - 1);
              return Random$warmup(r2, $t15540);
            }
          }
        }
      })();
    }
  }
}
const Random$warmup$clo = { _0: ($_, rng, k) => Random$warmup(rng, k) };

function Random$seed(n) {
  {
    const lo = march_int_and(n, 4294967295);
    {
      const hi = (() => {
        {
          const $t15544 = (() => {
            {
              const $t15542 = (n - lo);
              return ($t15542 / 4294967296);
            }
          })();
          return march_int_and($t15544, 4294967295);
        }
      })();
      {
        const a = Random$mix32(lo);
        {
          const b = (() => {
            {
              const $t15545 = march_int_xor(hi, a);
              return Random$mix32($t15545);
            }
          })();
          {
            const c = (() => {
              {
                const $t15546 = march_int_xor(lo, b);
                return Random$mix32($t15546);
              }
            })();
            {
              const $t15547 = ({ s0: a, s1: b, s2: c, s3: 1 });
              return Random$warmup($t15547, 12);
            }
          }
        }
      }
    }
  }
}
const Random$seed$clo = { _0: ($_, n) => Random$seed(n) };

function Random$next_raw(rng) {
  {
    const t = (() => {
      {
        const $t15552 = (() => {
          {
            const $t15550 = (() => {
              {
                const $t15548 = rng.s0;
                {
                  const $t15549 = rng.s1;
                  return ($t15548 + $t15549);
                }
              }
            })();
            {
              const $t15551 = rng.s3;
              return ($t15550 + $t15551);
            }
          }
        })();
        return march_int_and($t15552, 4294967295);
      }
    })();
    {
      const a = (() => {
        {
          const $t15553 = rng.s1;
          {
            const $t15555 = (() => {
              {
                const $t15554 = rng.s1;
                return march_int_shr($t15554, 9);
              }
            })();
            return march_int_xor($t15553, $t15555);
          }
        }
      })();
      {
        const b = (() => {
          {
            const $t15560 = (() => {
              {
                const $t15556 = rng.s2;
                {
                  const $t15559 = (() => {
                    {
                      const $t15558 = (() => {
                        {
                          const $t15557 = rng.s2;
                          return march_int_shl($t15557, 3);
                        }
                      })();
                      return march_int_and($t15558, 4294967295);
                    }
                  })();
                  return ($t15556 + $t15559);
                }
              }
            })();
            return march_int_and($t15560, 4294967295);
          }
        })();
        {
          const c = (() => {
            {
              const $t15563 = (() => {
                {
                  const $t15562 = (() => {
                    {
                      const $t15561 = rng.s2;
                      {
                        const keep_i1518 = (() => {
                          {
                            const $t15527_i1517 = march_int_shr(4294967295, 21);
                            return march_int_and($t15561, $t15527_i1517);
                          }
                        })();
                        {
                          const $t15528_i1519 = march_int_shl(keep_i1518, 21);
                          {
                            const $t15530_i1521 = march_int_shr($t15561, 11);
                            return march_int_or($t15528_i1519, $t15530_i1521);
                          }
                        }
                      }
                    }
                  })();
                  return ($t15562 + t);
                }
              })();
              return march_int_and($t15563, 4294967295);
            }
          })();
          {
            const $t15567 = (() => {
              {
                const $t15566 = (() => {
                  {
                    const $t15565 = (() => {
                      {
                        const $t15564 = rng.s3;
                        return ($t15564 + 1);
                      }
                    })();
                    return march_int_and($t15565, 4294967295);
                  }
                })();
                return ({ s0: a, s1: b, s2: c, s3: $t15566 });
              }
            })();
            return { _0: t, _1: $t15567 };
          }
        }
      }
    }
  }
}
const Random$next_raw$clo = { _0: ($_, rng) => Random$next_raw(rng) };

function Dom$find(id) {
  {
    const $rc_744 = dom_get_element_by_id$clo._0(dom_get_element_by_id$clo, id);
    return $rc_744;
  }
}
const Dom$find$clo = { _0: ($_, id) => Dom$find(id) };

function Dom$set_attr(el, name, val) {
  {
    const $rc_761 = dom_set_attribute$clo._0(dom_set_attribute$clo, el, name, val);
    return $rc_761;
  }
}
const Dom$set_attr$clo = { _0: ($_, el, name, val) => Dom$set_attr(el, name, val) };

function Dom$taps(el) {
  {
    const $rc_781 = dom_taps$clo._0(dom_taps$clo, el);
    return $rc_781;
  }
}
const Dom$taps$clo = { _0: ($_, el) => Dom$taps(el) };

function Dom$store_get(key) {
  {
    const $rc_782 = dom_store_get$clo._0(dom_store_get$clo, key);
    return $rc_782;
  }
}
const Dom$store_get$clo = { _0: ($_, key) => Dom$store_get(key) };

function Dom$store_set(key, val) {
  {
    const $rc_783 = dom_store_set$clo._0(dom_store_set$clo, key, val);
    return $rc_783;
  }
}
const Dom$store_set$clo = { _0: ($_, key, val) => Dom$store_set(key, val) };

function Dom$pointer_pos(el) {
  {
    const $rc_784 = dom_pointer_pos$clo._0(dom_pointer_pos$clo, el);
    return $rc_784;
  }
}
const Dom$pointer_pos$clo = { _0: ($_, el) => Dom$pointer_pos(el) };

function Dom$on_frame(cb) {
  return dom_request_animation_frame$clo._0(dom_request_animation_frame$clo, cb);
}
const Dom$on_frame$clo = { _0: ($_, cb) => Dom$on_frame(cb) };

function Canvas$get_context(node) {
  {
    const $rc_787 = canvas_get_context$clo._0(canvas_get_context$clo, node);
    return $rc_787;
  }
}
const Canvas$get_context$clo = { _0: ($_, node) => Canvas$get_context(node) };

function Canvas$save(ctx) {
  {
    const $rc_788 = canvas_save$clo._0(canvas_save$clo, ctx);
    return $rc_788;
  }
}
const Canvas$save$clo = { _0: ($_, ctx) => Canvas$save(ctx) };

function Canvas$restore(ctx) {
  {
    const $rc_789 = canvas_restore$clo._0(canvas_restore$clo, ctx);
    return $rc_789;
  }
}
const Canvas$restore$clo = { _0: ($_, ctx) => Canvas$restore(ctx) };

function Canvas$translate(ctx, x, y) {
  {
    const $rc_790 = canvas_translate$clo._0(canvas_translate$clo, ctx, x, y);
    return $rc_790;
  }
}
const Canvas$translate$clo = { _0: ($_, ctx, x, y) => Canvas$translate(ctx, x, y) };

function Canvas$rotate(ctx, angle) {
  {
    const $rc_791 = canvas_rotate$clo._0(canvas_rotate$clo, ctx, angle);
    return $rc_791;
  }
}
const Canvas$rotate$clo = { _0: ($_, ctx, angle) => Canvas$rotate(ctx, angle) };

function Canvas$set_fill_style(ctx, color) {
  {
    const $rc_793 = canvas_set_fill_style$clo._0(canvas_set_fill_style$clo, ctx, color);
    return $rc_793;
  }
}
const Canvas$set_fill_style$clo = { _0: ($_, ctx, color) => Canvas$set_fill_style(ctx, color) };

function Canvas$set_stroke_style(ctx, color) {
  {
    const $rc_794 = canvas_set_stroke_style$clo._0(canvas_set_stroke_style$clo, ctx, color);
    return $rc_794;
  }
}
const Canvas$set_stroke_style$clo = { _0: ($_, ctx, color) => Canvas$set_stroke_style(ctx, color) };

function Canvas$set_line_width(ctx, w) {
  {
    const $rc_795 = canvas_set_line_width$clo._0(canvas_set_line_width$clo, ctx, w);
    return $rc_795;
  }
}
const Canvas$set_line_width$clo = { _0: ($_, ctx, w) => Canvas$set_line_width(ctx, w) };

function Canvas$set_global_alpha(ctx, a) {
  {
    const $rc_796 = canvas_set_global_alpha$clo._0(canvas_set_global_alpha$clo, ctx, a);
    return $rc_796;
  }
}
const Canvas$set_global_alpha$clo = { _0: ($_, ctx, a) => Canvas$set_global_alpha(ctx, a) };

function Canvas$set_font(ctx, font) {
  {
    const $rc_797 = canvas_set_font$clo._0(canvas_set_font$clo, ctx, font);
    return $rc_797;
  }
}
const Canvas$set_font$clo = { _0: ($_, ctx, font) => Canvas$set_font(ctx, font) };

function Canvas$fill_rect(ctx, x, y, w, h) {
  {
    const $rc_799 = canvas_fill_rect$clo._0(canvas_fill_rect$clo, ctx, x, y, w, h);
    return $rc_799;
  }
}
const Canvas$fill_rect$clo = { _0: ($_, ctx, x, y, w, h) => Canvas$fill_rect(ctx, x, y, w, h) };

function Canvas$begin_path(ctx) {
  {
    const $rc_801 = canvas_begin_path$clo._0(canvas_begin_path$clo, ctx);
    return $rc_801;
  }
}
const Canvas$begin_path$clo = { _0: ($_, ctx) => Canvas$begin_path(ctx) };

function Canvas$close_path(ctx) {
  {
    const $rc_802 = canvas_close_path$clo._0(canvas_close_path$clo, ctx);
    return $rc_802;
  }
}
const Canvas$close_path$clo = { _0: ($_, ctx) => Canvas$close_path(ctx) };

function Canvas$move_to(ctx, x, y) {
  {
    const $rc_803 = canvas_move_to$clo._0(canvas_move_to$clo, ctx, x, y);
    return $rc_803;
  }
}
const Canvas$move_to$clo = { _0: ($_, ctx, x, y) => Canvas$move_to(ctx, x, y) };

function Canvas$line_to(ctx, x, y) {
  {
    const $rc_804 = canvas_line_to$clo._0(canvas_line_to$clo, ctx, x, y);
    return $rc_804;
  }
}
const Canvas$line_to$clo = { _0: ($_, ctx, x, y) => Canvas$line_to(ctx, x, y) };

function Canvas$arc(ctx, x, y, radius, start_angle, end_angle) {
  {
    const $rc_805 = canvas_arc$clo._0(canvas_arc$clo, ctx, x, y, radius, start_angle, end_angle);
    return $rc_805;
  }
}
const Canvas$arc$clo = { _0: ($_, ctx, x, y, radius, start_angle, end_angle) => Canvas$arc(ctx, x, y, radius, start_angle, end_angle) };

function Canvas$fill(ctx) {
  {
    const $rc_808 = canvas_fill$clo._0(canvas_fill$clo, ctx);
    return $rc_808;
  }
}
const Canvas$fill$clo = { _0: ($_, ctx) => Canvas$fill(ctx) };

function Canvas$stroke(ctx) {
  {
    const $rc_809 = canvas_stroke$clo._0(canvas_stroke$clo, ctx);
    return $rc_809;
  }
}
const Canvas$stroke$clo = { _0: ($_, ctx) => Canvas$stroke(ctx) };

function Canvas$fill_noise_circle(ctx, cx, cy, radius, alpha) {
  {
    const $rc_810 = canvas_fill_noise_circle$clo._0(canvas_fill_noise_circle$clo, ctx, cx, cy, radius, alpha);
    return $rc_810;
  }
}
const Canvas$fill_noise_circle$clo = { _0: ($_, ctx, cx, cy, radius, alpha) => Canvas$fill_noise_circle(ctx, cx, cy, radius, alpha) };

function Canvas$fill_text(ctx, text, x, y) {
  {
    const $rc_811 = canvas_fill_text$clo._0(canvas_fill_text$clo, ctx, text, x, y);
    return $rc_811;
  }
}
const Canvas$fill_text$clo = { _0: ($_, ctx, text, x, y) => Canvas$fill_text(ctx, text, x, y) };

function Canvas$set_text_align(ctx, align) {
  {
    const $rc_813 = canvas_set_text_align$clo._0(canvas_set_text_align$clo, ctx, align);
    return $rc_813;
  }
}
const Canvas$set_text_align$clo = { _0: ($_, ctx, align) => Canvas$set_text_align(ctx, align) };

function Audio$resume(actx) {
  {
    const $rc_817 = audio_resume$clo._0(audio_resume$clo, actx);
    return $rc_817;
  }
}
const Audio$resume$clo = { _0: ($_, actx) => Audio$resume(actx) };

function Audio$beep(actx, freq, duration, wave) {
  {
    const $rc_818 = audio_beep$clo._0(audio_beep$clo, actx, freq, duration, wave);
    return $rc_818;
  }
}
const Audio$beep$clo = { _0: ($_, actx, freq, duration, wave) => Audio$beep(actx, freq, duration, wave) };

function Audio$sweep(actx, freq_from, freq_to, duration, wave) {
  {
    const $rc_819 = audio_sweep$clo._0(audio_sweep$clo, actx, freq_from, freq_to, duration, wave);
    return $rc_819;
  }
}
const Audio$sweep$clo = { _0: ($_, actx, freq_from, freq_to, duration, wave) => Audio$sweep(actx, freq_from, freq_to, duration, wave) };

function Audio$noise_burst(actx, duration, filter_freq) {
  {
    const $rc_820 = audio_noise_burst$clo._0(audio_noise_burst$clo, actx, duration, filter_freq);
    return $rc_820;
  }
}
const Audio$noise_burst$clo = { _0: ($_, actx, duration, filter_freq) => Audio$noise_burst(actx, duration, filter_freq) };

function Perihelion$Combat$step_spawn(game, dt_s) {
  {
    const t = (() => {
      {
        const $t27347 = game.spawn_timer;
        return ($t27347 - dt_s);
      }
    })();
    {
      const $t27348 = (t > 0.);
      if ($t27348 === true) {
        return ({ ...game, spawn_timer: t });
      } else {
        return (() => {
          {
            const $p27374 = (() => {
              {
                const $t27349 = game.rng;
                {
                  const $p28516_i10049_i10348_i10471 = (() => {
                    {
                      const $p15576_i9795_i10044_i10343_i10466 = (() => {
                        {
                          const $p15573_i1532_i9785_i10035_i10334_i10457 = Random$next_raw($t27349);
                          {
                            const hi_i1533_i9786_i10036_i10335_i10458 = $p15573_i1532_i9785_i10035_i10334_i10457._0;
                            {
                              const rng2_i1534_i9787_i10037_i10336_i10459 = $p15573_i1532_i9785_i10035_i10334_i10457._1;
                              {
                                const $p15572_i1535_i9788_i10038_i10337_i10460 = Random$next_raw(rng2_i1534_i9787_i10037_i10336_i10459);
                                {
                                  const lo_i1536_i9789_i10039_i10338_i10461 = $p15572_i1535_i9788_i10038_i10337_i10460._0;
                                  {
                                    const rng3_i1537_i9790_i10040_i10339_i10462 = $p15572_i1535_i9788_i10038_i10337_i10460._1;
                                    {
                                      const $t15571_i1541_i9794_i10043_i10342_i10465 = (() => {
                                        {
                                          const $t15570_i1540_i9793_i10042_i10341_i10464 = (() => {
                                            {
                                              const $t15568_i1538_i9791_i10041_i10340_i10463 = march_int_and(hi_i1533_i9786_i10036_i10335_i10458, 1048575);
                                              return ($t15568_i1538_i9791_i10041_i10340_i10463 * 4294967296);
                                            }
                                          })();
                                          return ($t15570_i1540_i9793_i10042_i10341_i10464 + lo_i1536_i9789_i10039_i10338_i10461);
                                        }
                                      })();
                                      return { _0: $t15571_i1541_i9794_i10043_i10342_i10465, _1: rng3_i1537_i9790_i10040_i10339_i10462 };
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      })();
                      {
                        const bits_i9796_i10045_i10344_i10467 = $p15576_i9795_i10044_i10343_i10466._0;
                        {
                          const rng2_i9797_i10046_i10345_i10468 = $p15576_i9795_i10044_i10343_i10466._1;
                          {
                            const $t15575_i9799_i10048_i10347_i10470 = (() => {
                              {
                                const $t15574_i9798_i10047_i10346_i10469 = bits_i9796_i10045_i10344_i10467;
                                return ($t15574_i9798_i10047_i10346_i10469 / 4.50359962737e+15);
                              }
                            })();
                            return { _0: $t15575_i9799_i10048_i10347_i10470, _1: rng2_i9797_i10046_i10345_i10468 };
                          }
                        }
                      }
                    }
                  })();
                  {
                    const t_i10050_i10349_i10472 = $p28516_i10049_i10348_i10471._0;
                    {
                      const rng2_i10051_i10350_i10473 = $p28516_i10049_i10348_i10471._1;
                      {
                        const out_i10052_i10351_i10474 = { _0: rng2_i10051_i10350_i10473, _1: t_i10050_i10349_i10472 };
                        return out_i10052_i10351_i10474;
                      }
                    }
                  }
                }
              }
            })();
            {
              const r1 = $p27374._0;
              {
                const side_f = $p27374._1;
                {
                  const $p27373 = (() => {
                    {
                      const $p28516_i10049_i10348_i10452 = (() => {
                        {
                          const $p15576_i9795_i10044_i10343_i10447 = (() => {
                            {
                              const $p15573_i1532_i9785_i10035_i10334_i10438 = Random$next_raw(r1);
                              {
                                const hi_i1533_i9786_i10036_i10335_i10439 = $p15573_i1532_i9785_i10035_i10334_i10438._0;
                                {
                                  const rng2_i1534_i9787_i10037_i10336_i10440 = $p15573_i1532_i9785_i10035_i10334_i10438._1;
                                  {
                                    const $p15572_i1535_i9788_i10038_i10337_i10441 = Random$next_raw(rng2_i1534_i9787_i10037_i10336_i10440);
                                    {
                                      const lo_i1536_i9789_i10039_i10338_i10442 = $p15572_i1535_i9788_i10038_i10337_i10441._0;
                                      {
                                        const rng3_i1537_i9790_i10040_i10339_i10443 = $p15572_i1535_i9788_i10038_i10337_i10441._1;
                                        {
                                          const $t15571_i1541_i9794_i10043_i10342_i10446 = (() => {
                                            {
                                              const $t15570_i1540_i9793_i10042_i10341_i10445 = (() => {
                                                {
                                                  const $t15568_i1538_i9791_i10041_i10340_i10444 = march_int_and(hi_i1533_i9786_i10036_i10335_i10439, 1048575);
                                                  return ($t15568_i1538_i9791_i10041_i10340_i10444 * 4294967296);
                                                }
                                              })();
                                              return ($t15570_i1540_i9793_i10042_i10341_i10445 + lo_i1536_i9789_i10039_i10338_i10442);
                                            }
                                          })();
                                          return { _0: $t15571_i1541_i9794_i10043_i10342_i10446, _1: rng3_i1537_i9790_i10040_i10339_i10443 };
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          })();
                          {
                            const bits_i9796_i10045_i10344_i10448 = $p15576_i9795_i10044_i10343_i10447._0;
                            {
                              const rng2_i9797_i10046_i10345_i10449 = $p15576_i9795_i10044_i10343_i10447._1;
                              {
                                const $t15575_i9799_i10048_i10347_i10451 = (() => {
                                  {
                                    const $t15574_i9798_i10047_i10346_i10450 = bits_i9796_i10045_i10344_i10448;
                                    return ($t15574_i9798_i10047_i10346_i10450 / 4.50359962737e+15);
                                  }
                                })();
                                return { _0: $t15575_i9799_i10048_i10347_i10451, _1: rng2_i9797_i10046_i10345_i10449 };
                              }
                            }
                          }
                        }
                      })();
                      {
                        const t_i10050_i10349_i10453 = $p28516_i10049_i10348_i10452._0;
                        {
                          const rng2_i10051_i10350_i10454 = $p28516_i10049_i10348_i10452._1;
                          {
                            const out_i10052_i10351_i10455 = { _0: rng2_i10051_i10350_i10454, _1: t_i10050_i10349_i10453 };
                            return out_i10052_i10351_i10455;
                          }
                        }
                      }
                    }
                  })();
                  {
                    const r2 = $p27373._0;
                    {
                      const y_f = $p27373._1;
                      {
                        const $p27372 = (() => {
                          {
                            const $p28516_i10049_i10348_i10433 = (() => {
                              {
                                const $p15576_i9795_i10044_i10343_i10428 = (() => {
                                  {
                                    const $p15573_i1532_i9785_i10035_i10334_i10419 = Random$next_raw(r2);
                                    {
                                      const hi_i1533_i9786_i10036_i10335_i10420 = $p15573_i1532_i9785_i10035_i10334_i10419._0;
                                      {
                                        const rng2_i1534_i9787_i10037_i10336_i10421 = $p15573_i1532_i9785_i10035_i10334_i10419._1;
                                        {
                                          const $p15572_i1535_i9788_i10038_i10337_i10422 = Random$next_raw(rng2_i1534_i9787_i10037_i10336_i10421);
                                          {
                                            const lo_i1536_i9789_i10039_i10338_i10423 = $p15572_i1535_i9788_i10038_i10337_i10422._0;
                                            {
                                              const rng3_i1537_i9790_i10040_i10339_i10424 = $p15572_i1535_i9788_i10038_i10337_i10422._1;
                                              {
                                                const $t15571_i1541_i9794_i10043_i10342_i10427 = (() => {
                                                  {
                                                    const $t15570_i1540_i9793_i10042_i10341_i10426 = (() => {
                                                      {
                                                        const $t15568_i1538_i9791_i10041_i10340_i10425 = march_int_and(hi_i1533_i9786_i10036_i10335_i10420, 1048575);
                                                        return ($t15568_i1538_i9791_i10041_i10340_i10425 * 4294967296);
                                                      }
                                                    })();
                                                    return ($t15570_i1540_i9793_i10042_i10341_i10426 + lo_i1536_i9789_i10039_i10338_i10423);
                                                  }
                                                })();
                                                return { _0: $t15571_i1541_i9794_i10043_i10342_i10427, _1: rng3_i1537_i9790_i10040_i10339_i10424 };
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                })();
                                {
                                  const bits_i9796_i10045_i10344_i10429 = $p15576_i9795_i10044_i10343_i10428._0;
                                  {
                                    const rng2_i9797_i10046_i10345_i10430 = $p15576_i9795_i10044_i10343_i10428._1;
                                    {
                                      const $t15575_i9799_i10048_i10347_i10432 = (() => {
                                        {
                                          const $t15574_i9798_i10047_i10346_i10431 = bits_i9796_i10045_i10344_i10429;
                                          return ($t15574_i9798_i10047_i10346_i10431 / 4.50359962737e+15);
                                        }
                                      })();
                                      return { _0: $t15575_i9799_i10048_i10347_i10432, _1: rng2_i9797_i10046_i10345_i10430 };
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const t_i10050_i10349_i10434 = $p28516_i10049_i10348_i10433._0;
                              {
                                const rng2_i10051_i10350_i10435 = $p28516_i10049_i10348_i10433._1;
                                {
                                  const out_i10052_i10351_i10436 = { _0: rng2_i10051_i10350_i10435, _1: t_i10050_i10349_i10434 };
                                  return out_i10052_i10351_i10436;
                                }
                              }
                            }
                          }
                        })();
                        {
                          const r3 = $p27372._0;
                          {
                            const ang_f = $p27372._1;
                            {
                              const $p27371 = (() => {
                                {
                                  const $p28516_i10049_i10348_i10414 = (() => {
                                    {
                                      const $p15576_i9795_i10044_i10343_i10409 = (() => {
                                        {
                                          const $p15573_i1532_i9785_i10035_i10334_i10400 = Random$next_raw(r3);
                                          {
                                            const hi_i1533_i9786_i10036_i10335_i10401 = $p15573_i1532_i9785_i10035_i10334_i10400._0;
                                            {
                                              const rng2_i1534_i9787_i10037_i10336_i10402 = $p15573_i1532_i9785_i10035_i10334_i10400._1;
                                              {
                                                const $p15572_i1535_i9788_i10038_i10337_i10403 = Random$next_raw(rng2_i1534_i9787_i10037_i10336_i10402);
                                                {
                                                  const lo_i1536_i9789_i10039_i10338_i10404 = $p15572_i1535_i9788_i10038_i10337_i10403._0;
                                                  {
                                                    const rng3_i1537_i9790_i10040_i10339_i10405 = $p15572_i1535_i9788_i10038_i10337_i10403._1;
                                                    {
                                                      const $t15571_i1541_i9794_i10043_i10342_i10408 = (() => {
                                                        {
                                                          const $t15570_i1540_i9793_i10042_i10341_i10407 = (() => {
                                                            {
                                                              const $t15568_i1538_i9791_i10041_i10340_i10406 = march_int_and(hi_i1533_i9786_i10036_i10335_i10401, 1048575);
                                                              return ($t15568_i1538_i9791_i10041_i10340_i10406 * 4294967296);
                                                            }
                                                          })();
                                                          return ($t15570_i1540_i9793_i10042_i10341_i10407 + lo_i1536_i9789_i10039_i10338_i10404);
                                                        }
                                                      })();
                                                      return { _0: $t15571_i1541_i9794_i10043_i10342_i10408, _1: rng3_i1537_i9790_i10040_i10339_i10405 };
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      })();
                                      {
                                        const bits_i9796_i10045_i10344_i10410 = $p15576_i9795_i10044_i10343_i10409._0;
                                        {
                                          const rng2_i9797_i10046_i10345_i10411 = $p15576_i9795_i10044_i10343_i10409._1;
                                          {
                                            const $t15575_i9799_i10048_i10347_i10413 = (() => {
                                              {
                                                const $t15574_i9798_i10047_i10346_i10412 = bits_i9796_i10045_i10344_i10410;
                                                return ($t15574_i9798_i10047_i10346_i10412 / 4.50359962737e+15);
                                              }
                                            })();
                                            return { _0: $t15575_i9799_i10048_i10347_i10413, _1: rng2_i9797_i10046_i10345_i10411 };
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const t_i10050_i10349_i10415 = $p28516_i10049_i10348_i10414._0;
                                    {
                                      const rng2_i10051_i10350_i10416 = $p28516_i10049_i10348_i10414._1;
                                      {
                                        const out_i10052_i10351_i10417 = { _0: rng2_i10051_i10350_i10416, _1: t_i10050_i10349_i10415 };
                                        return out_i10052_i10351_i10417;
                                      }
                                    }
                                  }
                                }
                              })();
                              {
                                const r4 = $p27371._0;
                                {
                                  const next_f = $p27371._1;
                                  {
                                    const $p27370 = (() => {
                                      {
                                        const $p28516_i10049_i10348_i10395 = (() => {
                                          {
                                            const $p15576_i9795_i10044_i10343_i10390 = (() => {
                                              {
                                                const $p15573_i1532_i9785_i10035_i10334_i10381 = Random$next_raw(r4);
                                                {
                                                  const hi_i1533_i9786_i10036_i10335_i10382 = $p15573_i1532_i9785_i10035_i10334_i10381._0;
                                                  {
                                                    const rng2_i1534_i9787_i10037_i10336_i10383 = $p15573_i1532_i9785_i10035_i10334_i10381._1;
                                                    {
                                                      const $p15572_i1535_i9788_i10038_i10337_i10384 = Random$next_raw(rng2_i1534_i9787_i10037_i10336_i10383);
                                                      {
                                                        const lo_i1536_i9789_i10039_i10338_i10385 = $p15572_i1535_i9788_i10038_i10337_i10384._0;
                                                        {
                                                          const rng3_i1537_i9790_i10040_i10339_i10386 = $p15572_i1535_i9788_i10038_i10337_i10384._1;
                                                          {
                                                            const $t15571_i1541_i9794_i10043_i10342_i10389 = (() => {
                                                              {
                                                                const $t15570_i1540_i9793_i10042_i10341_i10388 = (() => {
                                                                  {
                                                                    const $t15568_i1538_i9791_i10041_i10340_i10387 = march_int_and(hi_i1533_i9786_i10036_i10335_i10382, 1048575);
                                                                    return ($t15568_i1538_i9791_i10041_i10340_i10387 * 4294967296);
                                                                  }
                                                                })();
                                                                return ($t15570_i1540_i9793_i10042_i10341_i10388 + lo_i1536_i9789_i10039_i10338_i10385);
                                                              }
                                                            })();
                                                            return { _0: $t15571_i1541_i9794_i10043_i10342_i10389, _1: rng3_i1537_i9790_i10040_i10339_i10386 };
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            })();
                                            {
                                              const bits_i9796_i10045_i10344_i10391 = $p15576_i9795_i10044_i10343_i10390._0;
                                              {
                                                const rng2_i9797_i10046_i10345_i10392 = $p15576_i9795_i10044_i10343_i10390._1;
                                                {
                                                  const $t15575_i9799_i10048_i10347_i10394 = (() => {
                                                    {
                                                      const $t15574_i9798_i10047_i10346_i10393 = bits_i9796_i10045_i10344_i10391;
                                                      return ($t15574_i9798_i10047_i10346_i10393 / 4.50359962737e+15);
                                                    }
                                                  })();
                                                  return { _0: $t15575_i9799_i10048_i10347_i10394, _1: rng2_i9797_i10046_i10345_i10392 };
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        {
                                          const t_i10050_i10349_i10396 = $p28516_i10049_i10348_i10395._0;
                                          {
                                            const rng2_i10051_i10350_i10397 = $p28516_i10049_i10348_i10395._1;
                                            {
                                              const out_i10052_i10351_i10398 = { _0: rng2_i10051_i10350_i10397, _1: t_i10050_i10349_i10396 };
                                              return out_i10052_i10351_i10398;
                                            }
                                          }
                                        }
                                      }
                                    })();
                                    {
                                      const r5 = $p27370._0;
                                      {
                                        const shape_f = $p27370._1;
                                        {
                                          const from_left = (side_f < 0.5);
                                          {
                                            let x;
                                            if (from_left === true) {
                                              x = (0. - 20.);
                                            } else {
                                              x = (() => {
                                                {
                                                  const $t27350 = game.view_w;
                                                  return ($t27350 + 20.);
                                                }
                                              })();
                                            }
                                            {
                                              const y = (() => {
                                                {
                                                  const $t27351 = game.camera_y;
                                                  {
                                                    const $t27353 = (() => {
                                                      {
                                                        const $t27352 = game.view_h;
                                                        return (y_f * $t27352);
                                                      }
                                                    })();
                                                    return ($t27351 + $t27353);
                                                  }
                                                }
                                              })();
                                              {
                                                const jitter = (() => {
                                                  {
                                                    const $t27354 = (ang_f - 0.5);
                                                    return ($t27354 * 1.0472);
                                                  }
                                                })();
                                                {
                                                  let dir_x;
                                                  if (from_left === true) {
                                                    dir_x = 1.;
                                                  } else {
                                                    dir_x = (0. - 1.);
                                                  }
                                                  {
                                                    const vx = (() => {
                                                      {
                                                        const $t27356 = (dir_x * 90.);
                                                        {
                                                          const $t27357 = Math.cos(jitter);
                                                          return ($t27356 * $t27357);
                                                        }
                                                      }
                                                    })();
                                                    {
                                                      const vy = (() => {
                                                        {
                                                          const $t27359 = Math.sin(jitter);
                                                          return (90. * $t27359);
                                                        }
                                                      })();
                                                      {
                                                        const a = (() => {
                                                          {
                                                            const $t27361 = { $: "AsteroidDrifting" };
                                                            return ({ x: x, y: y, vx: vx, vy: vy, radius: 10., shape_seed: shape_f, mode: $t27361 });
                                                          }
                                                        })();
                                                        {
                                                          const $t27362 = game.asteroids;
                                                          {
                                                            const $t27363 = (() => {
                                                              return { $: "Cons", _0: a, _1: $t27362 };
                                                            })();
                                                            {
                                                              const $t27369 = (() => {
                                                                {
                                                                  const $t27368 = (() => {
                                                                    {
                                                                      const $t27366 = (() => {
                                                                        {
                                                                          const $t27365 = (next_f - 0.5);
                                                                          return ($t27365 * 2.);
                                                                        }
                                                                      })();
                                                                      return ($t27366 * 1.);
                                                                    }
                                                                  })();
                                                                  return (4. + $t27368);
                                                                }
                                                              })();
                                                              return ({ ...game, asteroids: $t27363, rng: r5, spawn_timer: $t27369 });
                                                            }
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
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
const Perihelion$Combat$step_spawn$clo = { _0: ($_, game, dt_s) => Perihelion$Combat$step_spawn(game, dt_s) };

function Perihelion$Combat$in_band(game, x, y) {
  {
    const $t27386 = (() => {
      {
        const $t27383 = (() => {
          {
            const $t27377 = (() => {
              {
                const $t27376 = (() => {
                  {
                    const $t27375 = game.camera_y;
                    return ($t27375 - 100.);
                  }
                })();
                return (y > $t27376);
              }
            })();
            {
              const $t27382 = (() => {
                {
                  const $t27381 = (() => {
                    {
                      const $t27380 = (() => {
                        {
                          const $t27378 = game.camera_y;
                          {
                            const $t27379 = game.view_h;
                            return ($t27378 + $t27379);
                          }
                        }
                      })();
                      return ($t27380 + 100.);
                    }
                  })();
                  return (y < $t27381);
                }
              })();
              return ($t27377 && $t27382);
            }
          }
        })();
        {
          const $t27385 = (() => {
            {
              const $t27384 = (0. - 100.);
              return (x > $t27384);
            }
          })();
          return ($t27383 && $t27385);
        }
      }
    })();
    {
      const $t27389 = (() => {
        {
          const $t27388 = (() => {
            {
              const $t27387 = game.view_w;
              return ($t27387 + 100.);
            }
          })();
          return (x < $t27388);
        }
      })();
      return ($t27386 && $t27389);
    }
  }
}
const Perihelion$Combat$in_band$clo = { _0: ($_, game, x, y) => Perihelion$Combat$in_band(game, x, y) };

function Perihelion$Combat$step_entities(game, dt_s) {
  {
    const g1 = Perihelion$Combat$step_asteroids(game, dt_s);
    {
      const $t27400 = g1.player_shots;
      {
        const $t27402 = { $: "$Clo_$lam27401$3670", _0: $lam27401$apply$3670, _1: dt_s };
        {
          const $t27403 = (() => {
            {
              const f_i3657 = $t27402;
              {
                const go_i3658 = { $: "$Clo_go$4711", _0: go$apply$4711, _1: f_i3657 };
                {
                  const $t267_i3659 = { $: "Nil" };
                  return go$apply$4711(go_i3658, $t27400, $t267_i3659);
                }
              }
            }
          })();
          {
            const $t27410 = { $: "$Clo_$lam27404$3671", _0: $lam27404$apply$3671, _1: g1 };
            {
              const p_shots = (() => {
                {
                  const pred_i3653 = $t27410;
                  {
                    const go_i3654 = { $: "$Clo_go$4709", _0: go$apply$4709, _1: pred_i3653 };
                    {
                      const $t299_i3655 = { $: "Nil" };
                      return go$apply$4709(go_i3654, $t27403, $t299_i3655);
                    }
                  }
                }
              })();
              {
                const $t27411 = g1.enemy_shots;
                {
                  const $t27413 = { $: "$Clo_$lam27412$3672", _0: $lam27412$apply$3672, _1: dt_s };
                  {
                    const $t27414 = (() => {
                      {
                        const f_i3649 = $t27413;
                        {
                          const go_i3650 = { $: "$Clo_go$4711", _0: go$apply$4711, _1: f_i3649 };
                          {
                            const $t267_i3651 = { $: "Nil" };
                            return go$apply$4711(go_i3650, $t27411, $t267_i3651);
                          }
                        }
                      }
                    })();
                    {
                      const $t27421 = { $: "$Clo_$lam27415$3673", _0: $lam27415$apply$3673, _1: g1 };
                      {
                        const e_shots = (() => {
                          {
                            const pred_i3645 = $t27421;
                            {
                              const go_i3646 = { $: "$Clo_go$4709", _0: go$apply$4709, _1: pred_i3645 };
                              {
                                const $t299_i3647 = { $: "Nil" };
                                return go$apply$4709(go_i3646, $t27414, $t299_i3647);
                              }
                            }
                          }
                        })();
                        {
                          const $t27422 = g1.pickups;
                          {
                            const $t27426 = { $: "$Clo_$lam27423$3674", _0: $lam27423$apply$3674, _1: dt_s };
                            {
                              const $t27427 = (() => {
                                {
                                  const f_i3641 = $t27426;
                                  {
                                    const go_i3642 = { $: "$Clo_go$4707", _0: go$apply$4707, _1: f_i3641 };
                                    {
                                      const $t267_i3643 = { $: "Nil" };
                                      return go$apply$4707(go_i3642, $t27422, $t267_i3643);
                                    }
                                  }
                                }
                              })();
                              {
                                const $t27430 = { $: "$Clo_$lam27428$3675", _0: $lam27428$apply$3675 };
                                {
                                  const pickups = (() => {
                                    {
                                      const pred_i3637 = $t27430;
                                      {
                                        const go_i3638 = { $: "$Clo_go$4705", _0: go$apply$4705, _1: pred_i3637 };
                                        {
                                          const $t299_i3639 = { $: "Nil" };
                                          return go$apply$4705(go_i3638, $t27427, $t299_i3639);
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t27434 = (() => {
                                      {
                                        const $t27432 = (() => {
                                          {
                                            const $t27431 = g1.fire_cooldown;
                                            return ($t27431 > 0.);
                                          }
                                        })();
                                        if ($t27432 === true) {
                                          return (() => {
                                            {
                                              const $t27433 = g1.fire_cooldown;
                                              return ($t27433 - dt_s);
                                            }
                                          })();
                                        } else {
                                          return 0.;
                                        }
                                      }
                                    })();
                                    return ({ ...g1, player_shots: p_shots, enemy_shots: e_shots, pickups: pickups, fire_cooldown: $t27434 });
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
const Perihelion$Combat$step_entities$clo = { _0: ($_, game, dt_s) => Perihelion$Combat$step_entities(game, dt_s) };

function Perihelion$Combat$nearest_star_for_asteroid(x, y, stars, best, best_d) {
  switch (stars.$) {
    case "Nil": {
      return best;
      break;
    }
    case "Cons": {
      const $f27441 = stars._0;
      const $f27442 = stars._1;
      {
        const rest = $f27442;
        {
          const s = $f27441;
          {
            const dx = (() => {
              {
                const $t27435 = s.x;
                return ($t27435 - x);
              }
            })();
            {
              const dy = (() => {
                {
                  const $t27436 = s.y;
                  return ($t27436 - y);
                }
              })();
              {
                const d = (() => {
                  {
                    const $t27437 = (dx * dx);
                    {
                      const $t27438 = (dy * dy);
                      return ($t27437 + $t27438);
                    }
                  }
                })();
                {
                  const $t27439 = (d < best_d);
                  if ($t27439 === true) {
                    return (() => {
                      {
                        const $t27440 = { $: "Some", _0: s };
                        return Perihelion$Combat$nearest_star_for_asteroid(x, y, rest, $t27440, d);
                      }
                    })();
                  } else {
                    return Perihelion$Combat$nearest_star_for_asteroid(x, y, rest, best, best_d);
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
const Perihelion$Combat$nearest_star_for_asteroid$clo = { _0: ($_, x, y, stars, best, best_d) => Perihelion$Combat$nearest_star_for_asteroid(x, y, stars, best, best_d) };

function Perihelion$Combat$arc_velocity(x, y, vx, vy, stars, dt_s) {
  {
    const $t27449 = (() => {
      {
        const $t27447 = { $: "None" };
        {
          const $t27448 = (240. * 240.);
          return Perihelion$Combat$nearest_star_for_asteroid(x, y, stars, $t27447, $t27448);
        }
      }
    })();
    switch ($t27449.$) {
      case "None": {
        {
          const out = { _0: vx, _1: vy };
          return out;
        }
        break;
      }
      case "Some": {
        const $f27475 = $t27449._0;
        {
          const s = $f27475;
          {
            const dx = (() => {
              {
                const $t27450 = s.x;
                return ($t27450 - x);
              }
            })();
            {
              const dy = (() => {
                {
                  const $t27451 = s.y;
                  return ($t27451 - y);
                }
              })();
              {
                const dist = (() => {
                  {
                    const $t27454 = (() => {
                      {
                        const $t27452 = (dx * dx);
                        {
                          const $t27453 = (dy * dy);
                          return ($t27452 + $t27453);
                        }
                      }
                    })();
                    return Math.sqrt($t27454);
                  }
                })();
                {
                  const $t27455 = (dist > 0.);
                  if ($t27455 === true) {
                    return (() => {
                      {
                        const speed = (() => {
                          {
                            const $t27458 = (() => {
                              {
                                const $t27456 = (vx * vx);
                                {
                                  const $t27457 = (vy * vy);
                                  return ($t27456 + $t27457);
                                }
                              }
                            })();
                            return Math.sqrt($t27458);
                          }
                        })();
                        {
                          const nvx = (() => {
                            {
                              const $t27462 = (() => {
                                {
                                  const $t27461 = (() => {
                                    {
                                      const $t27459 = (dx / dist);
                                      return ($t27459 * 500.);
                                    }
                                  })();
                                  return ($t27461 * dt_s);
                                }
                              })();
                              return (vx + $t27462);
                            }
                          })();
                          {
                            const nvy = (() => {
                              {
                                const $t27466 = (() => {
                                  {
                                    const $t27465 = (() => {
                                      {
                                        const $t27463 = (dy / dist);
                                        return ($t27463 * 500.);
                                      }
                                    })();
                                    return ($t27465 * dt_s);
                                  }
                                })();
                                return (vy + $t27466);
                              }
                            })();
                            {
                              const nspeed = (() => {
                                {
                                  const $t27469 = (() => {
                                    {
                                      const $t27467 = (nvx * nvx);
                                      {
                                        const $t27468 = (nvy * nvy);
                                        return ($t27467 + $t27468);
                                      }
                                    }
                                  })();
                                  return Math.sqrt($t27469);
                                }
                              })();
                              {
                                const $t27470 = (nspeed > 0.);
                                if ($t27470 === true) {
                                  return (() => {
                                    {
                                      const $t27472 = (() => {
                                        {
                                          const $t27471 = (nvx / nspeed);
                                          return ($t27471 * speed);
                                        }
                                      })();
                                      {
                                        const $t27474 = (() => {
                                          {
                                            const $t27473 = (nvy / nspeed);
                                            return ($t27473 * speed);
                                          }
                                        })();
                                        return { _0: $t27472, _1: $t27474 };
                                      }
                                    }
                                  })();
                                } else {
                                  return { _0: vx, _1: vy };
                                }
                              }
                            }
                          }
                        }
                      }
                    })();
                  } else {
                    return (() => {
                      {
                        const out = { _0: vx, _1: vy };
                        return out;
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
}
const Perihelion$Combat$arc_velocity$clo = { _0: ($_, x, y, vx, vy, stars, dt_s) => Perihelion$Combat$arc_velocity(x, y, vx, vy, stars, dt_s) };

function Perihelion$Combat$step_asteroids_go(game, asteroids, acc, dt_s) {
  switch (asteroids.$) {
    case "Nil": {
      {
        const $t27476 = (() => {
          {
            const go_i3667 = { $: "$Clo_go$4713", _0: go$apply$4713 };
            {
              const $t250_i3668 = { $: "Nil" };
              return go$apply$4713(go_i3667, acc, $t250_i3668);
            }
          }
        })();
        return ({ ...game, asteroids: $t27476 });
      }
      break;
    }
    case "Cons": {
      const $f27540 = asteroids._0;
      const $f27541 = asteroids._1;
      {
        const rest = $f27541;
        {
          const a = $f27540;
          {
            const $t27477 = a.mode;
            switch ($t27477.$) {
              case "AsteroidOrbiting": {
                const $f27534 = $t27477._0;
                const $f27535 = $t27477._1;
                {
                  const angle = (() => {
                    return $f27535;
                  })();
                  {
                    const idx = (() => {
                      return $f27534;
                    })();
                    {
                      const $t27478 = Perihelion$Core$star_at(game, idx);
                      switch ($t27478.$) {
                        case "None": {
                          return Perihelion$Combat$step_asteroids_go(game, rest, acc, dt_s);
                          break;
                        }
                        case "Some": {
                          const $f27493 = $t27478._0;
                          {
                            const s = $f27493;
                            {
                              const angle2 = (() => {
                                {
                                  const $t27480 = (1. * dt_s);
                                  return (angle + $t27480);
                                }
                              })();
                              {
                                const r = (() => {
                                  {
                                    const $t27481 = s.capture_radius;
                                    return ($t27481 * 0.8);
                                  }
                                })();
                                {
                                  const a2 = (() => {
                                    {
                                      const $t27486 = (() => {
                                        {
                                          const $t27483 = s.x;
                                          {
                                            const $t27485 = (() => {
                                              {
                                                const $t27484 = Math.cos(angle2);
                                                return ($t27484 * r);
                                              }
                                            })();
                                            return ($t27483 + $t27485);
                                          }
                                        }
                                      })();
                                      {
                                        const $t27490 = (() => {
                                          {
                                            const $t27487 = s.y;
                                            {
                                              const $t27489 = (() => {
                                                {
                                                  const $t27488 = Math.sin(angle2);
                                                  return ($t27488 * r);
                                                }
                                              })();
                                              return ($t27487 + $t27489);
                                            }
                                          }
                                        })();
                                        {
                                          const $t27491 = { $: "AsteroidOrbiting", _0: idx, _1: angle2 };
                                          return ({ ...a, x: $t27486, y: $t27490, mode: $t27491 });
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t27492 = { $: "Cons", _0: a2, _1: acc };
                                    return Perihelion$Combat$step_asteroids_go(game, rest, $t27492, dt_s);
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
                }
                break;
              }
              case "AsteroidDrifting": {
                {
                  const vel = (() => {
                    {
                      const $t27494 = a.x;
                      {
                        const $t27495 = a.y;
                        {
                          const $t27496 = a.vx;
                          {
                            const $t27497 = a.vy;
                            {
                              const $t27498 = game.stars;
                              return Perihelion$Combat$arc_velocity($t27494, $t27495, $t27496, $t27497, $t27498, dt_s);
                            }
                          }
                        }
                      }
                    }
                  })();
                  {
                    const vx2 = vel._0;
                    {
                      const vy2 = vel._1;
                      {
                        const x2 = (() => {
                          {
                            const $t27499 = a.x;
                            {
                              const $t27500 = (vx2 * dt_s);
                              return ($t27499 + $t27500);
                            }
                          }
                        })();
                        {
                          const y2 = (() => {
                            {
                              const $t27501 = a.y;
                              {
                                const $t27502 = (vy2 * dt_s);
                                return ($t27501 + $t27502);
                              }
                            }
                          })();
                          {
                            const $t27504 = (() => {
                              {
                                const $t27503 = Perihelion$Combat$in_band(game, x2, y2);
                                return (!$t27503);
                              }
                            })();
                            if ($t27504 === true) {
                              return Perihelion$Combat$step_asteroids_go(game, rest, acc, dt_s);
                            } else {
                              return (() => {
                                {
                                  const $t27506 = (() => {
                                    {
                                      const $t27505 = game.stars;
                                      return Perihelion$Combat$arrived_star($t27505, x2, y2, 0);
                                    }
                                  })();
                                  switch ($t27506.$) {
                                    case "None": {
                                      {
                                        const a2 = ({ ...a, x: x2, y: y2, vx: vx2, vy: vy2 });
                                        {
                                          const $t27507 = { $: "Cons", _0: a2, _1: acc };
                                          return Perihelion$Combat$step_asteroids_go(game, rest, $t27507, dt_s);
                                        }
                                      }
                                      break;
                                    }
                                    case "Some": {
                                      const $f27532 = $t27506._0;
                                      {
                                        const pair = $f27532;
                                        {
                                          const idx = pair._0;
                                          {
                                            const s = pair._1;
                                            {
                                              const $p27530 = (() => {
                                                {
                                                  const $t27508 = game.rng;
                                                  {
                                                    const $p28516_i10049_i10348_i10490 = (() => {
                                                      {
                                                        const $p15576_i9795_i10044_i10343_i10485 = (() => {
                                                          {
                                                            const $p15573_i1532_i9785_i10035_i10334_i10476 = Random$next_raw($t27508);
                                                            {
                                                              const hi_i1533_i9786_i10036_i10335_i10477 = $p15573_i1532_i9785_i10035_i10334_i10476._0;
                                                              {
                                                                const rng2_i1534_i9787_i10037_i10336_i10478 = $p15573_i1532_i9785_i10035_i10334_i10476._1;
                                                                {
                                                                  const $p15572_i1535_i9788_i10038_i10337_i10479 = Random$next_raw(rng2_i1534_i9787_i10037_i10336_i10478);
                                                                  {
                                                                    const lo_i1536_i9789_i10039_i10338_i10480 = $p15572_i1535_i9788_i10038_i10337_i10479._0;
                                                                    {
                                                                      const rng3_i1537_i9790_i10040_i10339_i10481 = $p15572_i1535_i9788_i10038_i10337_i10479._1;
                                                                      {
                                                                        const $t15571_i1541_i9794_i10043_i10342_i10484 = (() => {
                                                                          {
                                                                            const $t15570_i1540_i9793_i10042_i10341_i10483 = (() => {
                                                                              {
                                                                                const $t15568_i1538_i9791_i10041_i10340_i10482 = march_int_and(hi_i1533_i9786_i10036_i10335_i10477, 1048575);
                                                                                return ($t15568_i1538_i9791_i10041_i10340_i10482 * 4294967296);
                                                                              }
                                                                            })();
                                                                            return ($t15570_i1540_i9793_i10042_i10341_i10483 + lo_i1536_i9789_i10039_i10338_i10480);
                                                                          }
                                                                        })();
                                                                        return { _0: $t15571_i1541_i9794_i10043_i10342_i10484, _1: rng3_i1537_i9790_i10040_i10339_i10481 };
                                                                      }
                                                                    }
                                                                  }
                                                                }
                                                              }
                                                            }
                                                          }
                                                        })();
                                                        {
                                                          const bits_i9796_i10045_i10344_i10486 = $p15576_i9795_i10044_i10343_i10485._0;
                                                          {
                                                            const rng2_i9797_i10046_i10345_i10487 = $p15576_i9795_i10044_i10343_i10485._1;
                                                            {
                                                              const $t15575_i9799_i10048_i10347_i10489 = (() => {
                                                                {
                                                                  const $t15574_i9798_i10047_i10346_i10488 = bits_i9796_i10045_i10344_i10486;
                                                                  return ($t15574_i9798_i10047_i10346_i10488 / 4.50359962737e+15);
                                                                }
                                                              })();
                                                              return { _0: $t15575_i9799_i10048_i10347_i10489, _1: rng2_i9797_i10046_i10345_i10487 };
                                                            }
                                                          }
                                                        }
                                                      }
                                                    })();
                                                    {
                                                      const t_i10050_i10349_i10491 = $p28516_i10049_i10348_i10490._0;
                                                      {
                                                        const rng2_i10051_i10350_i10492 = $p28516_i10049_i10348_i10490._1;
                                                        {
                                                          const out_i10052_i10351_i10493 = { _0: rng2_i10051_i10350_i10492, _1: t_i10050_i10349_i10491 };
                                                          return out_i10052_i10351_i10493;
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              })();
                                              {
                                                const rng2 = $p27530._0;
                                                {
                                                  const roll = $p27530._1;
                                                  {
                                                    const $t27510 = (roll < 0.35);
                                                    if ($t27510 === true) {
                                                      return (() => {
                                                        {
                                                          const angle = (() => {
                                                            {
                                                              const $t27512 = (() => {
                                                                {
                                                                  const $t27511 = s.y;
                                                                  return (y2 - $t27511);
                                                                }
                                                              })();
                                                              {
                                                                const $t27514 = (() => {
                                                                  {
                                                                    const $t27513 = s.x;
                                                                    return (x2 - $t27513);
                                                                  }
                                                                })();
                                                                return Math.atan2($t27512, $t27514);
                                                              }
                                                            }
                                                          })();
                                                          {
                                                            const r = (() => {
                                                              {
                                                                const $t27515 = s.capture_radius;
                                                                return ($t27515 * 0.8);
                                                              }
                                                            })();
                                                            {
                                                              const a2 = (() => {
                                                                {
                                                                  const $t27520 = (() => {
                                                                    {
                                                                      const $t27517 = s.x;
                                                                      {
                                                                        const $t27519 = (() => {
                                                                          {
                                                                            const $t27518 = Math.cos(angle);
                                                                            return ($t27518 * r);
                                                                          }
                                                                        })();
                                                                        return ($t27517 + $t27519);
                                                                      }
                                                                    }
                                                                  })();
                                                                  {
                                                                    const $t27524 = (() => {
                                                                      {
                                                                        const $t27521 = s.y;
                                                                        {
                                                                          const $t27523 = (() => {
                                                                            {
                                                                              const $t27522 = Math.sin(angle);
                                                                              return ($t27522 * r);
                                                                            }
                                                                          })();
                                                                          return ($t27521 + $t27523);
                                                                        }
                                                                      }
                                                                    })();
                                                                    {
                                                                      const $t27525 = { $: "AsteroidOrbiting", _0: idx, _1: angle };
                                                                      return ({ ...a, x: $t27520, y: $t27524, mode: $t27525 });
                                                                    }
                                                                  }
                                                                }
                                                              })();
                                                              {
                                                                const $t27526 = ({ ...game, rng: rng2 });
                                                                {
                                                                  const $t27527 = { $: "Cons", _0: a2, _1: acc };
                                                                  return Perihelion$Combat$step_asteroids_go($t27526, rest, $t27527, dt_s);
                                                                }
                                                              }
                                                            }
                                                          }
                                                        }
                                                      })();
                                                    } else {
                                                      return (() => {
                                                        {
                                                          const a2 = ({ ...a, x: x2, y: y2, vx: vx2, vy: vy2 });
                                                          {
                                                            const $t27528 = ({ ...game, rng: rng2 });
                                                            {
                                                              const $t27529 = { $: "Cons", _0: a2, _1: acc };
                                                              return Perihelion$Combat$step_asteroids_go($t27528, rest, $t27529, dt_s);
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
                                      break;
                                    }
                                    default: {
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
                break;
              }
              default: {
                return (() => { throw new Error("non-exhaustive pattern match"); })();
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
const Perihelion$Combat$step_asteroids_go$clo = { _0: ($_, game, asteroids, acc, dt_s) => Perihelion$Combat$step_asteroids_go(game, asteroids, acc, dt_s) };

function Perihelion$Combat$step_asteroids(game, dt_s) {
  {
    const $t27546 = game.asteroids;
    {
      const $t27547 = { $: "Nil" };
      return Perihelion$Combat$step_asteroids_go(game, $t27546, $t27547, dt_s);
    }
  }
}
const Perihelion$Combat$step_asteroids$clo = { _0: ($_, game, dt_s) => Perihelion$Combat$step_asteroids(game, dt_s) };

function Perihelion$Combat$step_ships(game, dt_s) {
  {
    const $t27548 = game.ships;
    {
      const $t27549 = { $: "Nil" };
      {
        const $t27550 = { $: "Nil" };
        return Perihelion$Combat$step_ships_go(game, $t27548, $t27549, $t27550, dt_s);
      }
    }
  }
}
const Perihelion$Combat$step_ships$clo = { _0: ($_, game, dt_s) => Perihelion$Combat$step_ships(game, dt_s) };

function Perihelion$Combat$nearest_other_star(from_x, from_y, skip_idx, stars, i, best, best_d) {
  switch (stars.$) {
    case "Nil": {
      return best;
      break;
    }
    case "Cons": {
      const $f27561 = stars._0;
      const $f27562 = stars._1;
      {
        const rest = (() => {
          return $f27562;
        })();
        {
          const s = (() => {
            return $f27561;
          })();
          {
            const $t27551 = (i === skip_idx);
            if ($t27551 === true) {
              return (() => {
                {
                  const $t27552 = (i + 1);
                  return Perihelion$Combat$nearest_other_star(from_x, from_y, skip_idx, rest, $t27552, best, best_d);
                }
              })();
            } else {
              return (() => {
                {
                  const dx = (() => {
                    {
                      const $t27553 = s.x;
                      return ($t27553 - from_x);
                    }
                  })();
                  {
                    const dy = (() => {
                      {
                        const $t27554 = s.y;
                        return ($t27554 - from_y);
                      }
                    })();
                    {
                      const d = (() => {
                        {
                          const $t27555 = (dx * dx);
                          {
                            const $t27556 = (dy * dy);
                            return ($t27555 + $t27556);
                          }
                        }
                      })();
                      {
                        const $t27557 = (d < best_d);
                        {
                          const $jp993_$t27558 = (i + 1);
                          if ($t27557 === true) {
                            return (() => {
                              {
                                const $t27559 = { $: "Some", _0: i };
                                return Perihelion$Combat$nearest_other_star(from_x, from_y, skip_idx, rest, $jp993_$t27558, $t27559, d);
                              }
                            })();
                          } else {
                            return (() => {
                              return Perihelion$Combat$nearest_other_star(from_x, from_y, skip_idx, rest, $jp993_$t27558, best, best_d);
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
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Perihelion$Combat$nearest_other_star$clo = { _0: ($_, from_x, from_y, skip_idx, stars, i, best, best_d) => Perihelion$Combat$nearest_other_star(from_x, from_y, skip_idx, stars, i, best, best_d) };

function Perihelion$Combat$arrived_star(stars, x, y, i) {
  switch (stars.$) {
    case "Nil": {
      return { $: "None" };
      break;
    }
    case "Cons": {
      const $f27577 = stars._0;
      const $f27578 = stars._1;
      {
        const rest = $f27578;
        {
          const s = $f27577;
          {
            const dx = (() => {
              {
                const $t27567 = s.x;
                return ($t27567 - x);
              }
            })();
            {
              const dy = (() => {
                {
                  const $t27568 = s.y;
                  return ($t27568 - y);
                }
              })();
              {
                const $t27574 = (() => {
                  {
                    const $t27572 = (() => {
                      {
                        const $t27571 = (() => {
                          {
                            const $t27569 = (dx * dx);
                            {
                              const $t27570 = (dy * dy);
                              return ($t27569 + $t27570);
                            }
                          }
                        })();
                        return Math.sqrt($t27571);
                      }
                    })();
                    {
                      const $t27573 = s.capture_radius;
                      return ($t27572 <= $t27573);
                    }
                  }
                })();
                if ($t27574 === true) {
                  return (() => {
                    {
                      const $t27575 = { _0: i, _1: s };
                      return { $: "Some", _0: $t27575 };
                    }
                  })();
                } else {
                  return (() => {
                    {
                      const $t27576 = (i + 1);
                      return Perihelion$Combat$arrived_star(rest, x, y, $t27576);
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
const Perihelion$Combat$arrived_star$clo = { _0: ($_, stars, x, y, i) => Perihelion$Combat$arrived_star(stars, x, y, i) };

function Perihelion$Combat$ship_fire_shot(sx, sy, game) {
  {
    const dx = (() => {
      {
        const $t27583 = game.ball_x;
        return ($t27583 - sx);
      }
    })();
    {
      const dy = (() => {
        {
          const $t27584 = game.ball_y;
          return ($t27584 - sy);
        }
      })();
      {
        const dist = (() => {
          {
            const $t27587 = (() => {
              {
                const $t27585 = (dx * dx);
                {
                  const $t27586 = (dy * dy);
                  return ($t27585 + $t27586);
                }
              }
            })();
            return Math.sqrt($t27587);
          }
        })();
        {
          const $t27588 = (dist > 0.);
          if ($t27588 === true) {
            return (() => {
              {
                const $t27591 = (() => {
                  {
                    const $t27589 = (dx / dist);
                    return ($t27589 * 150.);
                  }
                })();
                {
                  const $t27594 = (() => {
                    {
                      const $t27592 = (dy / dist);
                      return ($t27592 * 150.);
                    }
                  })();
                  return ({ x: sx, y: sy, vx: $t27591, vy: $t27594, ttl: 3. });
                }
              }
            })();
          } else {
            return ({ x: sx, y: sy, vx: 0., vy: 150., ttl: 3. });
          }
        }
      }
    }
  }
}
const Perihelion$Combat$ship_fire_shot$clo = { _0: ($_, sx, sy, game) => Perihelion$Combat$ship_fire_shot(sx, sy, game) };

function Perihelion$Combat$step_ships_go(game, ships, acc, new_shots, dt_s) {
  switch (ships.$) {
    case "Nil": {
      {
        const $t27598 = (() => {
          {
            const go_i3684 = { $: "$Clo_go$4717", _0: go$apply$4717 };
            {
              const $t250_i3685 = { $: "Nil" };
              return go$apply$4717(go_i3684, acc, $t250_i3685);
            }
          }
        })();
        {
          const $t27599 = game.enemy_shots;
          {
            const $t27600 = (() => {
              {
                const go_i9662 = { $: "$Clo_go$4715", _0: go$apply$4715 };
                {
                  const $t258_i9665 = (() => {
                    {
                      const go_i4346_i9663 = { $: "$Clo_go$5178", _0: go$apply$5178 };
                      {
                        const $t250_i4347_i9664 = { $: "Nil" };
                        return go$apply$5178(go_i4346_i9663, new_shots, $t250_i4347_i9664);
                      }
                    }
                  })();
                  return go$apply$4715(go_i9662, $t258_i9665, $t27599);
                }
              }
            })();
            return ({ ...game, ships: $t27598, enemy_shots: $t27600 });
          }
        }
      }
      break;
    }
    case "Cons": {
      const $f27711 = ships._0;
      const $f27712 = ships._1;
      {
        const rest = $f27712;
        {
          const sh = $f27711;
          {
            const $t27601 = sh.mode;
            switch ($t27601.$) {
              case "ShipOrbiting": {
                const $f27704 = $t27601._0;
                {
                  const angle = (() => {
                    return $f27704;
                  })();
                  {
                    const $t27603 = (() => {
                      {
                        const $t27602 = sh.star_idx;
                        return Perihelion$Core$star_at(game, $t27602);
                      }
                    })();
                    switch ($t27603.$) {
                      case "None": {
                        return Perihelion$Combat$step_ships_go(game, rest, acc, new_shots, dt_s);
                        break;
                      }
                      case "Some": {
                        const $f27669 = $t27603._0;
                        {
                          const s = $f27669;
                          {
                            const idle2 = (() => {
                              {
                                const $t27604 = sh.idle_timer;
                                return ($t27604 - dt_s);
                              }
                            })();
                            {
                              const $t27605 = (idle2 <= 0.);
                              if ($t27605 === true) {
                                return (() => {
                                  {
                                    const $p27640 = (() => {
                                      {
                                        const $t27606 = sh.hunter;
                                        if ($t27606 === true) {
                                          return (() => {
                                            {
                                              const $t27607 = game.ball_x;
                                              {
                                                const $t27608 = game.ball_y;
                                                return { _0: $t27607, _1: $t27608 };
                                              }
                                            }
                                          })();
                                        } else {
                                          return (() => {
                                            {
                                              const $t27609 = sh.x;
                                              {
                                                const $t27610 = sh.y;
                                                return { _0: $t27609, _1: $t27610 };
                                              }
                                            }
                                          })();
                                        }
                                      }
                                    })();
                                    {
                                      const tx = $p27640._0;
                                      {
                                        const ty = $p27640._1;
                                        {
                                          const $t27614 = (() => {
                                            {
                                              const $t27611 = sh.star_idx;
                                              {
                                                const $t27612 = game.stars;
                                                {
                                                  const $t27613 = { $: "None" };
                                                  return Perihelion$Combat$nearest_other_star(tx, ty, $t27611, $t27612, 0, $t27613, 999999999.);
                                                }
                                              }
                                            }
                                          })();
                                          switch ($t27614.$) {
                                            case "None": {
                                              {
                                                const sh2 = ({ ...sh, idle_timer: 6. });
                                                {
                                                  const $t27616 = { $: "Cons", _0: sh2, _1: acc };
                                                  return Perihelion$Combat$step_ships_go(game, rest, $t27616, new_shots, dt_s);
                                                }
                                              }
                                              break;
                                            }
                                            case "Some": {
                                              const $f27639 = $t27614._0;
                                              {
                                                const target_idx = $f27639;
                                                {
                                                  const $t27617 = Perihelion$Core$star_at(game, target_idx);
                                                  switch ($t27617.$) {
                                                    case "None": {
                                                      {
                                                        const sh2 = ({ ...sh, idle_timer: 6. });
                                                        {
                                                          const $t27619 = { $: "Cons", _0: sh2, _1: acc };
                                                          return Perihelion$Combat$step_ships_go(game, rest, $t27619, new_shots, dt_s);
                                                        }
                                                      }
                                                      break;
                                                    }
                                                    case "Some": {
                                                      const $f27638 = $t27617._0;
                                                      {
                                                        const t = $f27638;
                                                        {
                                                          const dx = (() => {
                                                            {
                                                              const $t27620 = t.x;
                                                              {
                                                                const $t27621 = sh.x;
                                                                return ($t27620 - $t27621);
                                                              }
                                                            }
                                                          })();
                                                          {
                                                            const dy = (() => {
                                                              {
                                                                const $t27622 = t.y;
                                                                {
                                                                  const $t27623 = sh.y;
                                                                  return ($t27622 - $t27623);
                                                                }
                                                              }
                                                            })();
                                                            {
                                                              const dist = (() => {
                                                                {
                                                                  const $t27626 = (() => {
                                                                    {
                                                                      const $t27624 = (dx * dx);
                                                                      {
                                                                        const $t27625 = (dy * dy);
                                                                        return ($t27624 + $t27625);
                                                                      }
                                                                    }
                                                                  })();
                                                                  return Math.sqrt($t27626);
                                                                }
                                                              })();
                                                              {
                                                                const vel = (() => {
                                                                  {
                                                                    const $t27627 = (dist > 0.);
                                                                    if ($t27627 === true) {
                                                                      return (() => {
                                                                        {
                                                                          const $t27630 = (() => {
                                                                            {
                                                                              const $t27628 = (dx / dist);
                                                                              return ($t27628 * 180.);
                                                                            }
                                                                          })();
                                                                          {
                                                                            const $t27633 = (() => {
                                                                              {
                                                                                const $t27631 = (dy / dist);
                                                                                return ($t27631 * 180.);
                                                                              }
                                                                            })();
                                                                            return { _0: $t27630, _1: $t27633 };
                                                                          }
                                                                        }
                                                                      })();
                                                                    } else {
                                                                      return { _0: 0., _1: 180. };
                                                                    }
                                                                  }
                                                                })();
                                                                {
                                                                  const vx = vel._0;
                                                                  {
                                                                    const vy = vel._1;
                                                                    {
                                                                      const sh2 = (() => {
                                                                        {
                                                                          const $t27635 = { $: "ShipFlying", _0: vx, _1: vy };
                                                                          return ({ ...sh, mode: $t27635 });
                                                                        }
                                                                      })();
                                                                      {
                                                                        const $t27636 = { $: "Cons", _0: sh2, _1: acc };
                                                                        return Perihelion$Combat$step_ships_go(game, rest, $t27636, new_shots, dt_s);
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
                                })();
                              } else {
                                return (() => {
                                  {
                                    const d = (0. - 1.);
                                    {
                                      const angle2 = (() => {
                                        {
                                          const $t27645 = (() => {
                                            {
                                              const $t27644 = (d * 1.4);
                                              return ($t27644 * dt_s);
                                            }
                                          })();
                                          return (angle + $t27645);
                                        }
                                      })();
                                      {
                                        const r = (() => {
                                          {
                                            const $t27646 = s.capture_radius;
                                            return ($t27646 * 1.6);
                                          }
                                        })();
                                        {
                                          const sx = (() => {
                                            {
                                              const $t27648 = s.x;
                                              {
                                                const $t27650 = (() => {
                                                  {
                                                    const $t27649 = Math.cos(angle2);
                                                    return ($t27649 * r);
                                                  }
                                                })();
                                                return ($t27648 + $t27650);
                                              }
                                            }
                                          })();
                                          {
                                            const sy = (() => {
                                              {
                                                const $t27651 = s.y;
                                                {
                                                  const $t27653 = (() => {
                                                    {
                                                      const $t27652 = Math.sin(angle2);
                                                      return ($t27652 * r);
                                                    }
                                                  })();
                                                  return ($t27651 + $t27653);
                                                }
                                              }
                                            })();
                                            {
                                              const cd2 = (() => {
                                                {
                                                  const $t27654 = sh.fire_cooldown;
                                                  return ($t27654 - dt_s);
                                                }
                                              })();
                                              {
                                                const in_range = (() => {
                                                  {
                                                    const $t27657 = (() => {
                                                      {
                                                        const $t27655 = game.ball_x;
                                                        {
                                                          const $t27656 = game.ball_y;
                                                          {
                                                            const dx_i3692 = ($t27655 - sx);
                                                            {
                                                              const dy_i3693 = ($t27656 - sy);
                                                              {
                                                                const $t27341_i3694 = (dx_i3692 * dx_i3692);
                                                                {
                                                                  const $t27342_i3695 = (dy_i3693 * dy_i3693);
                                                                  return ($t27341_i3694 + $t27342_i3695);
                                                                }
                                                              }
                                                            }
                                                          }
                                                        }
                                                      }
                                                    })();
                                                    {
                                                      const $t27660 = (380. * 380.);
                                                      return ($t27657 <= $t27660);
                                                    }
                                                  }
                                                })();
                                                {
                                                  const $t27662 = (() => {
                                                    {
                                                      const $t27661 = (cd2 <= 0.);
                                                      return ($t27661 && in_range);
                                                    }
                                                  })();
                                                  if ($t27662 === true) {
                                                    return (() => {
                                                      {
                                                        const shot = Perihelion$Combat$ship_fire_shot(sx, sy, game);
                                                        {
                                                          const sh2 = (() => {
                                                            {
                                                              const $t27663 = { $: "ShipOrbiting", _0: angle2 };
                                                              return ({ ...sh, x: sx, y: sy, mode: $t27663, idle_timer: idle2, fire_cooldown: 2.5 });
                                                            }
                                                          })();
                                                          {
                                                            const $t27665 = { $: "Cons", _0: sh2, _1: acc };
                                                            {
                                                              const $t27666 = { $: "Cons", _0: shot, _1: new_shots };
                                                              return Perihelion$Combat$step_ships_go(game, rest, $t27665, $t27666, dt_s);
                                                            }
                                                          }
                                                        }
                                                      }
                                                    })();
                                                  } else {
                                                    return (() => {
                                                      {
                                                        const sh2 = (() => {
                                                          {
                                                            const $t27667 = { $: "ShipOrbiting", _0: angle2 };
                                                            return ({ ...sh, x: sx, y: sy, mode: $t27667, idle_timer: idle2, fire_cooldown: cd2 });
                                                          }
                                                        })();
                                                        {
                                                          const $t27668 = { $: "Cons", _0: sh2, _1: acc };
                                                          return Perihelion$Combat$step_ships_go(game, rest, $t27668, new_shots, dt_s);
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
                break;
              }
              case "ShipFlying": {
                const $f27705 = $t27601._0;
                const $f27706 = $t27601._1;
                {
                  const vy = (() => {
                    return $f27706;
                  })();
                  {
                    const vx = (() => {
                      return $f27705;
                    })();
                    {
                      const x2 = (() => {
                        {
                          const $t27670 = sh.x;
                          {
                            const $t27671 = (vx * dt_s);
                            return ($t27670 + $t27671);
                          }
                        }
                      })();
                      {
                        const y2 = (() => {
                          {
                            const $t27672 = sh.y;
                            {
                              const $t27673 = (vy * dt_s);
                              return ($t27672 + $t27673);
                            }
                          }
                        })();
                        {
                          const $t27675 = (() => {
                            {
                              const $t27674 = game.stars;
                              return Perihelion$Combat$arrived_star($t27674, x2, y2, 0);
                            }
                          })();
                          switch ($t27675.$) {
                            case "Some": {
                              const $f27703 = $t27675._0;
                              {
                                const pair = $f27703;
                                {
                                  const idx = pair._0;
                                  {
                                    const t = pair._1;
                                    {
                                      const angle = (() => {
                                        {
                                          const $t27677 = (() => {
                                            {
                                              const $t27676 = t.y;
                                              return (y2 - $t27676);
                                            }
                                          })();
                                          {
                                            const $t27679 = (() => {
                                              {
                                                const $t27678 = t.x;
                                                return (x2 - $t27678);
                                              }
                                            })();
                                            return Math.atan2($t27677, $t27679);
                                          }
                                        }
                                      })();
                                      {
                                        const $p27699 = (() => {
                                          {
                                            const $t27680 = game.rng;
                                            {
                                              const $p28516_i10049_i10348_i10509 = (() => {
                                                {
                                                  const $p15576_i9795_i10044_i10343_i10504 = (() => {
                                                    {
                                                      const $p15573_i1532_i9785_i10035_i10334_i10495 = Random$next_raw($t27680);
                                                      {
                                                        const hi_i1533_i9786_i10036_i10335_i10496 = $p15573_i1532_i9785_i10035_i10334_i10495._0;
                                                        {
                                                          const rng2_i1534_i9787_i10037_i10336_i10497 = $p15573_i1532_i9785_i10035_i10334_i10495._1;
                                                          {
                                                            const $p15572_i1535_i9788_i10038_i10337_i10498 = Random$next_raw(rng2_i1534_i9787_i10037_i10336_i10497);
                                                            {
                                                              const lo_i1536_i9789_i10039_i10338_i10499 = $p15572_i1535_i9788_i10038_i10337_i10498._0;
                                                              {
                                                                const rng3_i1537_i9790_i10040_i10339_i10500 = $p15572_i1535_i9788_i10038_i10337_i10498._1;
                                                                {
                                                                  const $t15571_i1541_i9794_i10043_i10342_i10503 = (() => {
                                                                    {
                                                                      const $t15570_i1540_i9793_i10042_i10341_i10502 = (() => {
                                                                        {
                                                                          const $t15568_i1538_i9791_i10041_i10340_i10501 = march_int_and(hi_i1533_i9786_i10036_i10335_i10496, 1048575);
                                                                          return ($t15568_i1538_i9791_i10041_i10340_i10501 * 4294967296);
                                                                        }
                                                                      })();
                                                                      return ($t15570_i1540_i9793_i10042_i10341_i10502 + lo_i1536_i9789_i10039_i10338_i10499);
                                                                    }
                                                                  })();
                                                                  return { _0: $t15571_i1541_i9794_i10043_i10342_i10503, _1: rng3_i1537_i9790_i10040_i10339_i10500 };
                                                                }
                                                              }
                                                            }
                                                          }
                                                        }
                                                      }
                                                    }
                                                  })();
                                                  {
                                                    const bits_i9796_i10045_i10344_i10505 = $p15576_i9795_i10044_i10343_i10504._0;
                                                    {
                                                      const rng2_i9797_i10046_i10345_i10506 = $p15576_i9795_i10044_i10343_i10504._1;
                                                      {
                                                        const $t15575_i9799_i10048_i10347_i10508 = (() => {
                                                          {
                                                            const $t15574_i9798_i10047_i10346_i10507 = bits_i9796_i10045_i10344_i10505;
                                                            return ($t15574_i9798_i10047_i10346_i10507 / 4.50359962737e+15);
                                                          }
                                                        })();
                                                        return { _0: $t15575_i9799_i10048_i10347_i10508, _1: rng2_i9797_i10046_i10345_i10506 };
                                                      }
                                                    }
                                                  }
                                                }
                                              })();
                                              {
                                                const t_i10050_i10349_i10510 = $p28516_i10049_i10348_i10509._0;
                                                {
                                                  const rng2_i10051_i10350_i10511 = $p28516_i10049_i10348_i10509._1;
                                                  {
                                                    const out_i10052_i10351_i10512 = { _0: rng2_i10051_i10350_i10511, _1: t_i10050_i10349_i10510 };
                                                    return out_i10052_i10351_i10512;
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        {
                                          const rng2 = $p27699._0;
                                          {
                                            const idle_f = $p27699._1;
                                            {
                                              const idle = (() => {
                                                {
                                                  const $t27685 = (() => {
                                                    {
                                                      const $t27684 = (6. - 3.);
                                                      return (idle_f * $t27684);
                                                    }
                                                  })();
                                                  return (3. + $t27685);
                                                }
                                              })();
                                              {
                                                const r = (() => {
                                                  {
                                                    const $t27686 = t.capture_radius;
                                                    return ($t27686 * 1.6);
                                                  }
                                                })();
                                                {
                                                  const sh2 = (() => {
                                                    {
                                                      const $t27691 = (() => {
                                                        {
                                                          const $t27688 = t.x;
                                                          {
                                                            const $t27690 = (() => {
                                                              {
                                                                const $t27689 = Math.cos(angle);
                                                                return ($t27689 * r);
                                                              }
                                                            })();
                                                            return ($t27688 + $t27690);
                                                          }
                                                        }
                                                      })();
                                                      {
                                                        const $t27695 = (() => {
                                                          {
                                                            const $t27692 = t.y;
                                                            {
                                                              const $t27694 = (() => {
                                                                {
                                                                  const $t27693 = Math.sin(angle);
                                                                  return ($t27693 * r);
                                                                }
                                                              })();
                                                              return ($t27692 + $t27694);
                                                            }
                                                          }
                                                        })();
                                                        {
                                                          const $t27696 = { $: "ShipOrbiting", _0: angle };
                                                          return ({ ...sh, x: $t27691, y: $t27695, star_idx: idx, mode: $t27696, idle_timer: idle });
                                                        }
                                                      }
                                                    }
                                                  })();
                                                  {
                                                    const $t27697 = ({ ...game, rng: rng2 });
                                                    {
                                                      const $t27698 = { $: "Cons", _0: sh2, _1: acc };
                                                      return Perihelion$Combat$step_ships_go($t27697, rest, $t27698, new_shots, dt_s);
                                                    }
                                                  }
                                                }
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
                            case "None": {
                              {
                                const $t27701 = Perihelion$Combat$in_band(game, x2, y2);
                                if ($t27701 === true) {
                                  return (() => {
                                    {
                                      const sh2 = ({ ...sh, x: x2, y: y2 });
                                      {
                                        const $t27702 = { $: "Cons", _0: sh2, _1: acc };
                                        return Perihelion$Combat$step_ships_go(game, rest, $t27702, new_shots, dt_s);
                                      }
                                    }
                                  })();
                                } else {
                                  return Perihelion$Combat$step_ships_go(game, rest, acc, new_shots, dt_s);
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
                break;
              }
              default: {
                return (() => { throw new Error("non-exhaustive pattern match"); })();
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
const Perihelion$Combat$step_ships_go$clo = { _0: ($_, game, ships, acc, new_shots, dt_s) => Perihelion$Combat$step_ships_go(game, ships, acc, new_shots, dt_s) };

function Perihelion$Combat$fire_fallback_aim(game) {
  {
    const $t27717 = game.mode;
    switch ($t27717.$) {
      case "Orbiting": {
        const $f27738 = $t27717._0;
        const $f27739 = $t27717._1;
        const $f27740 = $t27717._2;
        {
          const idx = (() => {
            return $f27738;
          })();
          {
            const $t27718 = Perihelion$Core$star_at(game, idx);
            switch ($t27718.$) {
              case "None": {
                return { $: "None" };
                break;
              }
              case "Some": {
                const $f27730 = $t27718._0;
                {
                  const s = $f27730;
                  {
                    const rdx = (() => {
                      {
                        const $t27719 = game.ball_x;
                        {
                          const $t27720 = s.x;
                          return ($t27719 - $t27720);
                        }
                      }
                    })();
                    {
                      const rdy = (() => {
                        {
                          const $t27721 = game.ball_y;
                          {
                            const $t27722 = s.y;
                            return ($t27721 - $t27722);
                          }
                        }
                      })();
                      {
                        const rdist = (() => {
                          {
                            const $t27725 = (() => {
                              {
                                const $t27723 = (rdx * rdx);
                                {
                                  const $t27724 = (rdy * rdy);
                                  return ($t27723 + $t27724);
                                }
                              }
                            })();
                            return Math.sqrt($t27725);
                          }
                        })();
                        {
                          const $t27726 = (rdist > 0.);
                          if ($t27726 === true) {
                            return (() => {
                              {
                                const $t27729 = (() => {
                                  {
                                    const $t27727 = (rdx / rdist);
                                    {
                                      const $t27728 = (rdy / rdist);
                                      return { _0: $t27727, _1: $t27728 };
                                    }
                                  }
                                })();
                                return { $: "Some", _0: $t27729 };
                              }
                            })();
                          } else {
                            return { $: "None" };
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
        break;
      }
      case "Flying": {
        const $f27749 = $t27717._0;
        const $f27750 = $t27717._1;
        {
          const vy = (() => {
            return $f27750;
          })();
          {
            const vx = (() => {
              return $f27749;
            })();
            {
              const speed = (() => {
                {
                  const $t27733 = (() => {
                    {
                      const $t27731 = (vx * vx);
                      {
                        const $t27732 = (vy * vy);
                        return ($t27731 + $t27732);
                      }
                    }
                  })();
                  return Math.sqrt($t27733);
                }
              })();
              {
                const $t27734 = (speed > 0.);
                if ($t27734 === true) {
                  return (() => {
                    {
                      const $t27737 = (() => {
                        {
                          const $t27735 = (vx / speed);
                          {
                            const $t27736 = (vy / speed);
                            return { _0: $t27735, _1: $t27736 };
                          }
                        }
                      })();
                      return { $: "Some", _0: $t27737 };
                    }
                  })();
                } else {
                  return { $: "None" };
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
const Perihelion$Combat$fire_fallback_aim$clo = { _0: ($_, game) => Perihelion$Combat$fire_fallback_aim(game) };

function Perihelion$Combat$apply_recoil(game, ax, ay) {
  {
    const $t27755 = game.mode;
    switch ($t27755.$) {
      case "Orbiting": {
        const $f27763 = $t27755._0;
        const $f27764 = $t27755._1;
        const $f27765 = $t27755._2;
        return game;
        break;
      }
      case "Flying": {
        const $f27774 = $t27755._0;
        const $f27775 = $t27755._1;
        {
          const vy = (() => {
            return $f27775;
          })();
          {
            const vx = (() => {
              return $f27774;
            })();
            {
              const $t27762 = (() => {
                {
                  const $t27758 = (() => {
                    {
                      const $t27757 = (ax * 14.);
                      return (vx - $t27757);
                    }
                  })();
                  {
                    const $t27761 = (() => {
                      {
                        const $t27760 = (ay * 14.);
                        return (vy - $t27760);
                      }
                    })();
                    return { $: "Flying", _0: $t27758, _1: $t27761 };
                  }
                }
              })();
              return ({ ...game, mode: $t27762 });
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
const Perihelion$Combat$apply_recoil$clo = { _0: ($_, game, ax, ay) => Perihelion$Combat$apply_recoil(game, ax, ay) };

function Perihelion$Combat$fire(game, keys, cursor, _dt_s) {
  {
    const pressed = (() => {
      {
        const $t27781 = { $: "$Clo_$lam27780$3691", _0: $lam27780$apply$3691 };
        return List$any$List_String$Fn_String_Bool(keys, $t27781);
      }
    })();
    {
      const $t27785 = (() => {
        {
          const $t27782 = (!pressed);
          {
            const $t27784 = (() => {
              {
                const $t27783 = game.fire_cooldown;
                return ($t27783 > 0.);
              }
            })();
            return ($t27782 || $t27784);
          }
        }
      })();
      if ($t27785 === true) {
        return game;
      } else {
        return (() => {
          {
            const cx = cursor._0;
            {
              const cy = cursor._1;
              {
                const cursor_world_y = (() => {
                  {
                    const $t27786 = cy;
                    {
                      const $t27787 = game.camera_y;
                      return ($t27786 + $t27787);
                    }
                  }
                })();
                {
                  const dx = (() => {
                    {
                      const $t27788 = cx;
                      {
                        const $t27789 = game.ball_x;
                        return ($t27788 - $t27789);
                      }
                    }
                  })();
                  {
                    const dy = (() => {
                      {
                        const $t27790 = game.ball_y;
                        return (cursor_world_y - $t27790);
                      }
                    })();
                    {
                      const dist = (() => {
                        {
                          const $t27793 = (() => {
                            {
                              const $t27791 = (dx * dx);
                              {
                                const $t27792 = (dy * dy);
                                return ($t27791 + $t27792);
                              }
                            }
                          })();
                          return Math.sqrt($t27793);
                        }
                      })();
                      {
                        const aim = (() => {
                          {
                            const $t27794 = (dist > 0.);
                            if ($t27794 === true) {
                              return (() => {
                                {
                                  const $t27797 = (() => {
                                    {
                                      const $t27795 = (dx / dist);
                                      {
                                        const $t27796 = (dy / dist);
                                        return { _0: $t27795, _1: $t27796 };
                                      }
                                    }
                                  })();
                                  return { $: "Some", _0: $t27797 };
                                }
                              })();
                            } else {
                              return Perihelion$Combat$fire_fallback_aim(game);
                            }
                          }
                        })();
                        switch (aim.$) {
                          case "None": {
                            return game;
                            break;
                          }
                          case "Some": {
                            const $f27809 = aim._0;
                            {
                              const pair = $f27809;
                              {
                                const ax = pair._0;
                                {
                                  const ay = pair._1;
                                  {
                                    const shot = (() => {
                                      {
                                        const $t27798 = game.ball_x;
                                        {
                                          const $t27799 = game.ball_y;
                                          {
                                            const $t27801 = (ax * 420.);
                                            {
                                              const $t27803 = (ay * 420.);
                                              return ({ x: $t27798, y: $t27799, vx: $t27801, vy: $t27803, ttl: 3. });
                                            }
                                          }
                                        }
                                      }
                                    })();
                                    {
                                      const g2 = Perihelion$Combat$apply_recoil(game, ax, ay);
                                      {
                                        const $t27805 = g2.player_shots;
                                        {
                                          const $t27806 = (() => {
                                            return { $: "Cons", _0: shot, _1: $t27805 };
                                          })();
                                          return ({ ...g2, player_shots: $t27806, fire_cooldown: 0.4 });
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
const Perihelion$Combat$fire$clo = { _0: ($_, game, keys, cursor, _dt_s) => Perihelion$Combat$fire(game, keys, cursor, _dt_s) };

function Perihelion$Combat$collide_shots_asteroids(game) {
  {
    const $p27843 = (() => {
      {
        const $t27818 = game.asteroids;
        {
          const $t27826 = { $: "$Clo_$lam27819$3693", _0: $lam27819$apply$3693, _1: game };
          {
            const pred_i3725 = $t27826;
            {
              const go_i3726 = { $: "$Clo_go$4724", _0: go$apply$4724, _1: pred_i3725 };
              {
                const $t554_i3727 = { $: "Nil" };
                {
                  const $t555_i3728 = { $: "Nil" };
                  return go$apply$4724(go_i3726, $t27818, $t554_i3727, $t555_i3728);
                }
              }
            }
          }
        }
      }
    })();
    {
      const dead = $p27843._0;
      {
        const alive = $p27843._1;
        {
          const $t27827 = game.player_shots;
          {
            const $t27836 = { $: "$Clo_$lam27828$3695", _0: $lam27828$apply$3695, _1: game };
            {
              const shots = (() => {
                {
                  const pred_i3721 = $t27836;
                  {
                    const go_i3722 = { $: "$Clo_go$4709", _0: go$apply$4709, _1: pred_i3721 };
                    {
                      const $t299_i3723 = { $: "Nil" };
                      return go$apply$4709(go_i3722, $t27827, $t299_i3723);
                    }
                  }
                }
              })();
              {
                const $t27841 = (() => {
                  {
                    const $t27837 = game.score;
                    {
                      const $t27840 = (() => {
                        {
                          const $t27838 = (() => {
                            {
                              const go_i3719 = { $: "$Clo_go$4721", _0: go$apply$4721 };
                              return go$apply$4721(go_i3719, dead, 0);
                            }
                          })();
                          {
                            const $t27839 = game.multiplier;
                            return ($t27838 * $t27839);
                          }
                        }
                      })();
                      return ($t27837 + $t27840);
                    }
                  }
                })();
                {
                  const $t27842 = (() => {
                    {
                      const $t27817_i9681 = { $: "$Clo_$lam27814$3692", _0: $lam27814$apply$3692 };
                      {
                        const f_i3715_i9682 = $t27817_i9681;
                        {
                          const go_i3716_i9683 = { $: "$Clo_go$4719", _0: go$apply$4719, _1: f_i3715_i9682 };
                          {
                            const $t267_i3717_i9684 = { $: "Nil" };
                            return go$apply$4719(go_i3716_i9683, dead, $t267_i3717_i9684);
                          }
                        }
                      }
                    }
                  })();
                  return ({ ...game, asteroids: alive, player_shots: shots, score: $t27841, fx_bursts: $t27842 });
                }
              }
            }
          }
        }
      }
    }
  }
}
const Perihelion$Combat$collide_shots_asteroids$clo = { _0: ($_, game) => Perihelion$Combat$collide_shots_asteroids(game) };

function Perihelion$Combat$ship_shot_hit(sh, s) {
  {
    const pos = (() => {
      {
        const pos_i3732 = (() => {
          {
            const $t27339_i3730 = sh.x;
            {
              const $t27340_i3731 = sh.y;
              return { _0: $t27339_i3730, _1: $t27340_i3731 };
            }
          }
        })();
        return pos_i3732;
      }
    })();
    {
      const sx = pos._0;
      {
        const sy = pos._1;
        {
          const $t27811_i10010 = s.x;
          {
            const $t27812_i10011 = s.y;
            {
              const $t27343_i9676_i10016 = (() => {
                {
                  const dx_i3630_i9672_i10012 = (sx - $t27811_i10010);
                  {
                    const dy_i3631_i9673_i10013 = (sy - $t27812_i10011);
                    {
                      const $t27341_i3632_i9674_i10014 = (dx_i3630_i9672_i10012 * dx_i3630_i9672_i10012);
                      {
                        const $t27342_i3633_i9675_i10015 = (dy_i3631_i9673_i10013 * dy_i3631_i9673_i10013);
                        return ($t27341_i3632_i9674_i10014 + $t27342_i3633_i9675_i10015);
                      }
                    }
                  }
                }
              })();
              {
                const $t27346_i9679_i10019 = (() => {
                  {
                    const $t27344_i9677_i10017 = (3. + 10.);
                    {
                      const $t27345_i9678_i10018 = (3. + 10.);
                      return ($t27344_i9677_i10017 * $t27345_i9678_i10018);
                    }
                  }
                })();
                return ($t27343_i9676_i10016 <= $t27346_i9679_i10019);
              }
            }
          }
        }
      }
    }
  }
}
const Perihelion$Combat$ship_shot_hit$clo = { _0: ($_, sh, s) => Perihelion$Combat$ship_shot_hit(sh, s) };

function Perihelion$Combat$collide_shots_ships(game) {
  {
    const $p27865 = (() => {
      {
        const $t27846 = game.ships;
        {
          const $t27851 = { $: "$Clo_$lam27847$3697", _0: $lam27847$apply$3697, _1: game };
          {
            const pred_i3740 = $t27851;
            {
              const go_i3741 = { $: "$Clo_go$4730", _0: go$apply$4730, _1: pred_i3740 };
              {
                const $t554_i3742 = { $: "Nil" };
                {
                  const $t555_i3743 = { $: "Nil" };
                  return go$apply$4730(go_i3741, $t27846, $t554_i3742, $t555_i3743);
                }
              }
            }
          }
        }
      }
    })();
    {
      const dead = $p27865._0;
      {
        const alive = $p27865._1;
        {
          const $t27852 = game.player_shots;
          {
            const $t27858 = { $: "$Clo_$lam27853$3699", _0: $lam27853$apply$3699, _1: game };
            {
              const shots = (() => {
                {
                  const pred_i3736 = $t27858;
                  {
                    const go_i3737 = { $: "$Clo_go$4709", _0: go$apply$4709, _1: pred_i3736 };
                    {
                      const $t299_i3738 = { $: "Nil" };
                      return go$apply$4709(go_i3737, $t27852, $t299_i3738);
                    }
                  }
                }
              })();
              {
                const g2 = (() => {
                  {
                    const $t27864 = (() => {
                      {
                        const $t27859 = game.score;
                        {
                          const $t27863 = (() => {
                            {
                              const $t27861 = (() => {
                                {
                                  const $t27860 = (() => {
                                    {
                                      const go_i3734 = { $: "$Clo_go$4727", _0: go$apply$4727 };
                                      return go$apply$4727(go_i3734, dead, 0);
                                    }
                                  })();
                                  {
                                    const sr_s1 = ($t27860 + $t27860);
                                    return sr_s1;
                                  }
                                }
                              })();
                              {
                                const $t27862 = game.multiplier;
                                return ($t27861 * $t27862);
                              }
                            }
                          })();
                          return ($t27859 + $t27863);
                        }
                      }
                    })();
                    return ({ ...game, ships: alive, player_shots: shots, score: $t27864 });
                  }
                })();
                return Perihelion$Combat$roll_drops(g2, dead);
              }
            }
          }
        }
      }
    }
  }
}
const Perihelion$Combat$collide_shots_ships$clo = { _0: ($_, game) => Perihelion$Combat$collide_shots_ships(game) };

function Perihelion$Combat$roll_drops(game, dead) {
  switch (dead.$) {
    case "Nil": {
      return game;
      break;
    }
    case "Cons": {
      const $f27875 = dead._0;
      const $f27876 = dead._1;
      {
        const rest = $f27876;
        {
          const sh = $f27875;
          {
            const pos = (() => {
              {
                const pos_i3748 = (() => {
                  {
                    const $t27339_i3746 = sh.x;
                    {
                      const $t27340_i3747 = sh.y;
                      return { _0: $t27339_i3746, _1: $t27340_i3747 };
                    }
                  }
                })();
                return pos_i3748;
              }
            })();
            {
              const sx = pos._0;
              {
                const sy = pos._1;
                {
                  const $p27873 = (() => {
                    {
                      const $t27866 = game.rng;
                      {
                        const $p28516_i10049_i10348_i10528 = (() => {
                          {
                            const $p15576_i9795_i10044_i10343_i10523 = (() => {
                              {
                                const $p15573_i1532_i9785_i10035_i10334_i10514 = Random$next_raw($t27866);
                                {
                                  const hi_i1533_i9786_i10036_i10335_i10515 = $p15573_i1532_i9785_i10035_i10334_i10514._0;
                                  {
                                    const rng2_i1534_i9787_i10037_i10336_i10516 = $p15573_i1532_i9785_i10035_i10334_i10514._1;
                                    {
                                      const $p15572_i1535_i9788_i10038_i10337_i10517 = Random$next_raw(rng2_i1534_i9787_i10037_i10336_i10516);
                                      {
                                        const lo_i1536_i9789_i10039_i10338_i10518 = $p15572_i1535_i9788_i10038_i10337_i10517._0;
                                        {
                                          const rng3_i1537_i9790_i10040_i10339_i10519 = $p15572_i1535_i9788_i10038_i10337_i10517._1;
                                          {
                                            const $t15571_i1541_i9794_i10043_i10342_i10522 = (() => {
                                              {
                                                const $t15570_i1540_i9793_i10042_i10341_i10521 = (() => {
                                                  {
                                                    const $t15568_i1538_i9791_i10041_i10340_i10520 = march_int_and(hi_i1533_i9786_i10036_i10335_i10515, 1048575);
                                                    return ($t15568_i1538_i9791_i10041_i10340_i10520 * 4294967296);
                                                  }
                                                })();
                                                return ($t15570_i1540_i9793_i10042_i10341_i10521 + lo_i1536_i9789_i10039_i10338_i10518);
                                              }
                                            })();
                                            return { _0: $t15571_i1541_i9794_i10043_i10342_i10522, _1: rng3_i1537_i9790_i10040_i10339_i10519 };
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const bits_i9796_i10045_i10344_i10524 = $p15576_i9795_i10044_i10343_i10523._0;
                              {
                                const rng2_i9797_i10046_i10345_i10525 = $p15576_i9795_i10044_i10343_i10523._1;
                                {
                                  const $t15575_i9799_i10048_i10347_i10527 = (() => {
                                    {
                                      const $t15574_i9798_i10047_i10346_i10526 = bits_i9796_i10045_i10344_i10524;
                                      return ($t15574_i9798_i10047_i10346_i10526 / 4.50359962737e+15);
                                    }
                                  })();
                                  return { _0: $t15575_i9799_i10048_i10347_i10527, _1: rng2_i9797_i10046_i10345_i10525 };
                                }
                              }
                            }
                          }
                        })();
                        {
                          const t_i10050_i10349_i10529 = $p28516_i10049_i10348_i10528._0;
                          {
                            const rng2_i10051_i10350_i10530 = $p28516_i10049_i10348_i10528._1;
                            {
                              const out_i10052_i10351_i10531 = { _0: rng2_i10051_i10350_i10530, _1: t_i10050_i10349_i10529 };
                              return out_i10052_i10351_i10531;
                            }
                          }
                        }
                      }
                    }
                  })();
                  {
                    const rng2 = $p27873._0;
                    {
                      const roll = $p27873._1;
                      {
                        const g2 = (() => {
                          {
                            const $t27868 = (roll < 0.25);
                            if ($t27868 === true) {
                              return (() => {
                                {
                                  const $t27870 = ({ x: sx, y: sy, ttl: 8. });
                                  {
                                    const $t27871 = game.pickups;
                                    {
                                      const $t27872 = (() => {
                                        return { $: "Cons", _0: $t27870, _1: $t27871 };
                                      })();
                                      return ({ ...game, rng: rng2, pickups: $t27872 });
                                    }
                                  }
                                }
                              })();
                            } else {
                              return ({ ...game, rng: rng2 });
                            }
                          }
                        })();
                        return Perihelion$Combat$roll_drops(g2, rest);
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
const Perihelion$Combat$roll_drops$clo = { _0: ($_, game, dead) => Perihelion$Combat$roll_drops(game, dead) };

function Perihelion$Combat$collide_ball_pickups(game) {
  {
    const $t27887 = game.shield;
    if ($t27887 === true) {
      return game;
    } else {
      return (() => {
        {
          const hit = (() => {
            {
              const $t27888 = game.pickups;
              {
                const $t27890 = { $: "$Clo_$lam27889$3702", _0: $lam27889$apply$3702, _1: game };
                return List$any$List_R_ttl_Float_x_Float_y_Float$Fn_R_ttl_Float_x_Float_y_Float_Bool($t27888, $t27890);
              }
            }
          })();
          if (hit === true) {
            return (() => {
              {
                const $t27891 = game.pickups;
                {
                  const $t27894 = { $: "$Clo_$lam27892$3703", _0: $lam27892$apply$3703, _1: game };
                  {
                    const $t27895 = (() => {
                      {
                        const pred_i3750 = $t27894;
                        {
                          const go_i3751 = { $: "$Clo_go$4705", _0: go$apply$4705, _1: pred_i3750 };
                          {
                            const $t299_i3752 = { $: "Nil" };
                            return go$apply$4705(go_i3751, $t27891, $t299_i3752);
                          }
                        }
                      }
                    })();
                    return ({ ...game, shield: true, pickups: $t27895 });
                  }
                }
              }
            })();
          } else {
            return game;
          }
        }
      })();
    }
  }
}
const Perihelion$Combat$collide_ball_pickups$clo = { _0: ($_, game) => Perihelion$Combat$collide_ball_pickups(game) };

function Perihelion$Combat$ball_hits_ship(game, sh) {
  {
    const pos = (() => {
      {
        const pos_i3756 = (() => {
          {
            const $t27339_i3754 = sh.x;
            {
              const $t27340_i3755 = sh.y;
              return { _0: $t27339_i3754, _1: $t27340_i3755 };
            }
          }
        })();
        return pos_i3756;
      }
    })();
    {
      const sx = pos._0;
      {
        const sy = pos._1;
        {
          const $t27897 = game.ball_x;
          {
            const $t27898 = game.ball_y;
            {
              const $t27343_i9709 = (() => {
                {
                  const dx_i3630_i9705 = ($t27897 - sx);
                  {
                    const dy_i3631_i9706 = ($t27898 - sy);
                    {
                      const $t27341_i3632_i9707 = (dx_i3630_i9705 * dx_i3630_i9705);
                      {
                        const $t27342_i3633_i9708 = (dy_i3631_i9706 * dy_i3631_i9706);
                        return ($t27341_i3632_i9707 + $t27342_i3633_i9708);
                      }
                    }
                  }
                }
              })();
              {
                const $t27346_i9712 = (() => {
                  {
                    const $t27344_i9710 = (10. + 6.);
                    {
                      const $t27345_i9711 = (10. + 6.);
                      return ($t27344_i9710 * $t27345_i9711);
                    }
                  }
                })();
                return ($t27343_i9709 <= $t27346_i9712);
              }
            }
          }
        }
      }
    }
  }
}
const Perihelion$Combat$ball_hits_ship$clo = { _0: ($_, game, sh) => Perihelion$Combat$ball_hits_ship(game, sh) };

function Perihelion$Combat$collide_ball_hazards(game) {
  {
    const ast_hit = (() => {
      {
        const $t27910 = game.asteroids;
        {
          const $t27912 = { $: "$Clo_$lam27911$3704", _0: $lam27911$apply$3704, _1: game };
          return List$any$List_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t27910, $t27912);
        }
      }
    })();
    {
      const shot_hit = (() => {
        {
          const $t27913 = game.enemy_shots;
          {
            const $t27915 = { $: "$Clo_$lam27914$3705", _0: $lam27914$apply$3705, _1: game };
            return List$any$List_R_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t27913, $t27915);
          }
        }
      })();
      {
        const ship_hit = (() => {
          {
            const $t27916 = game.ships;
            {
              const $t27918 = { $: "$Clo_$lam27917$3706", _0: $lam27917$apply$3706, _1: game };
              return List$any$List_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float$Fn_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float_Bool($t27916, $t27918);
            }
          }
        })();
        {
          const $t27921 = (() => {
            {
              const $t27920 = (() => {
                {
                  const $t27919 = (ast_hit || shot_hit);
                  return ($t27919 || ship_hit);
                }
              })();
              return (!$t27920);
            }
          })();
          if ($t27921 === true) {
            return game;
          } else {
            return (() => {
              {
                const $t27922 = game.shield;
                if ($t27922 === true) {
                  return (() => {
                    {
                      const $t27923 = game.asteroids;
                      {
                        const $t27925 = { $: "$Clo_$lam27924$3707", _0: $lam27924$apply$3707, _1: game };
                        {
                          const dead_ast = (() => {
                            {
                              const pred_i3770 = $t27925;
                              {
                                const go_i3771 = { $: "$Clo_go$4737", _0: go$apply$4737, _1: pred_i3770 };
                                {
                                  const $t299_i3772 = { $: "Nil" };
                                  return go$apply$4737(go_i3771, $t27923, $t299_i3772);
                                }
                              }
                            }
                          })();
                          {
                            const $t27926 = game.asteroids;
                            {
                              const $t27929 = { $: "$Clo_$lam27927$3708", _0: $lam27927$apply$3708, _1: game };
                              {
                                const $t27930 = (() => {
                                  {
                                    const pred_i3766 = $t27929;
                                    {
                                      const go_i3767 = { $: "$Clo_go$4737", _0: go$apply$4737, _1: pred_i3766 };
                                      {
                                        const $t299_i3768 = { $: "Nil" };
                                        return go$apply$4737(go_i3767, $t27926, $t299_i3768);
                                      }
                                    }
                                  }
                                })();
                                {
                                  const $t27931 = game.enemy_shots;
                                  {
                                    const $t27934 = { $: "$Clo_$lam27932$3709", _0: $lam27932$apply$3709, _1: game };
                                    {
                                      const $t27935 = (() => {
                                        {
                                          const pred_i3762 = $t27934;
                                          {
                                            const go_i3763 = { $: "$Clo_go$4709", _0: go$apply$4709, _1: pred_i3762 };
                                            {
                                              const $t299_i3764 = { $: "Nil" };
                                              return go$apply$4709(go_i3763, $t27931, $t299_i3764);
                                            }
                                          }
                                        }
                                      })();
                                      {
                                        const $t27936 = game.ships;
                                        {
                                          const $t27939 = { $: "$Clo_$lam27937$3710", _0: $lam27937$apply$3710, _1: game };
                                          {
                                            const $t27940 = (() => {
                                              {
                                                const pred_i3758 = $t27939;
                                                {
                                                  const go_i3759 = { $: "$Clo_go$4735", _0: go$apply$4735, _1: pred_i3758 };
                                                  {
                                                    const $t299_i3760 = { $: "Nil" };
                                                    return go$apply$4735(go_i3759, $t27936, $t299_i3760);
                                                  }
                                                }
                                              }
                                            })();
                                            {
                                              const $t27941 = game.fx_bursts;
                                              {
                                                const $t27942 = (() => {
                                                  {
                                                    const $t27817_i9734 = { $: "$Clo_$lam27814$3692", _0: $lam27814$apply$3692 };
                                                    {
                                                      const f_i3715_i9735 = $t27817_i9734;
                                                      {
                                                        const go_i3716_i9736 = { $: "$Clo_go$4719", _0: go$apply$4719, _1: f_i3715_i9735 };
                                                        {
                                                          const $t267_i3717_i9737 = { $: "Nil" };
                                                          return go$apply$4719(go_i3716_i9736, dead_ast, $t267_i3717_i9737);
                                                        }
                                                      }
                                                    }
                                                  }
                                                })();
                                                {
                                                  const $t27943 = (() => {
                                                    {
                                                      const go_i9729 = { $: "$Clo_go$4733", _0: go$apply$4733 };
                                                      {
                                                        const $t258_i9732 = (() => {
                                                          {
                                                            const go_i4353_i9730 = { $: "$Clo_go$4265", _0: go$apply$4265 };
                                                            {
                                                              const $t250_i4354_i9731 = { $: "Nil" };
                                                              return go$apply$4265(go_i4353_i9730, $t27941, $t250_i4354_i9731);
                                                            }
                                                          }
                                                        })();
                                                        return go$apply$4733(go_i9729, $t258_i9732, $t27942);
                                                      }
                                                    }
                                                  })();
                                                  return ({ ...game, shield: false, asteroids: $t27930, enemy_shots: $t27935, ships: $t27940, fx_bursts: $t27943 });
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
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
                  return Perihelion$Core$end_run(game);
                }
              }
            })();
          }
        }
      }
    }
  }
}
const Perihelion$Combat$collide_ball_hazards$clo = { _0: ($_, game) => Perihelion$Combat$collide_ball_hazards(game) };

function Perihelion$Combat$spawn_star_turret(game, star_idx, rng) {
  {
    const $t27944 = Perihelion$Core$star_at(game, star_idx);
    switch ($t27944.$) {
      case "None": {
        return ({ ...game, rng: rng });
        break;
      }
      case "Some": {
        const $f27965 = $t27944._0;
        {
          const s = $f27965;
          {
            const $p27964 = (() => {
              {
                const $p28516_i10049_i10348_i10547 = (() => {
                  {
                    const $p15576_i9795_i10044_i10343_i10542 = (() => {
                      {
                        const $p15573_i1532_i9785_i10035_i10334_i10533 = Random$next_raw(rng);
                        {
                          const hi_i1533_i9786_i10036_i10335_i10534 = $p15573_i1532_i9785_i10035_i10334_i10533._0;
                          {
                            const rng2_i1534_i9787_i10037_i10336_i10535 = $p15573_i1532_i9785_i10035_i10334_i10533._1;
                            {
                              const $p15572_i1535_i9788_i10038_i10337_i10536 = Random$next_raw(rng2_i1534_i9787_i10037_i10336_i10535);
                              {
                                const lo_i1536_i9789_i10039_i10338_i10537 = $p15572_i1535_i9788_i10038_i10337_i10536._0;
                                {
                                  const rng3_i1537_i9790_i10040_i10339_i10538 = $p15572_i1535_i9788_i10038_i10337_i10536._1;
                                  {
                                    const $t15571_i1541_i9794_i10043_i10342_i10541 = (() => {
                                      {
                                        const $t15570_i1540_i9793_i10042_i10341_i10540 = (() => {
                                          {
                                            const $t15568_i1538_i9791_i10041_i10340_i10539 = march_int_and(hi_i1533_i9786_i10036_i10335_i10534, 1048575);
                                            return ($t15568_i1538_i9791_i10041_i10340_i10539 * 4294967296);
                                          }
                                        })();
                                        return ($t15570_i1540_i9793_i10042_i10341_i10540 + lo_i1536_i9789_i10039_i10338_i10537);
                                      }
                                    })();
                                    return { _0: $t15571_i1541_i9794_i10043_i10342_i10541, _1: rng3_i1537_i9790_i10040_i10339_i10538 };
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    })();
                    {
                      const bits_i9796_i10045_i10344_i10543 = $p15576_i9795_i10044_i10343_i10542._0;
                      {
                        const rng2_i9797_i10046_i10345_i10544 = $p15576_i9795_i10044_i10343_i10542._1;
                        {
                          const $t15575_i9799_i10048_i10347_i10546 = (() => {
                            {
                              const $t15574_i9798_i10047_i10346_i10545 = bits_i9796_i10045_i10344_i10543;
                              return ($t15574_i9798_i10047_i10346_i10545 / 4.50359962737e+15);
                            }
                          })();
                          return { _0: $t15575_i9799_i10048_i10347_i10546, _1: rng2_i9797_i10046_i10345_i10544 };
                        }
                      }
                    }
                  }
                })();
                {
                  const t_i10050_i10349_i10548 = $p28516_i10049_i10348_i10547._0;
                  {
                    const rng2_i10051_i10350_i10549 = $p28516_i10049_i10348_i10547._1;
                    {
                      const out_i10052_i10351_i10550 = { _0: rng2_i10051_i10350_i10549, _1: t_i10050_i10349_i10548 };
                      return out_i10052_i10351_i10550;
                    }
                  }
                }
              }
            })();
            {
              const rng2 = $p27964._0;
              {
                const idle_f = $p27964._1;
                {
                  const r = (() => {
                    {
                      const $t27945 = s.capture_radius;
                      return ($t27945 * 1.6);
                    }
                  })();
                  {
                    const idle = (() => {
                      {
                        const $t27951 = (() => {
                          {
                            const $t27950 = (6. - 3.);
                            return (idle_f * $t27950);
                          }
                        })();
                        return (3. + $t27951);
                      }
                    })();
                    {
                      const ship = (() => {
                        {
                          const $t27955 = (() => {
                            {
                              const $t27952 = s.x;
                              {
                                const $t27954 = (() => {
                                  {
                                    const $t27953 = Math.cos(0.);
                                    return ($t27953 * r);
                                  }
                                })();
                                return ($t27952 + $t27954);
                              }
                            }
                          })();
                          {
                            const $t27959 = (() => {
                              {
                                const $t27956 = s.y;
                                {
                                  const $t27958 = (() => {
                                    {
                                      const $t27957 = Math.sin(0.);
                                      return ($t27957 * r);
                                    }
                                  })();
                                  return ($t27956 + $t27958);
                                }
                              }
                            })();
                            {
                              const $t27960 = { $: "ShipOrbiting", _0: 0. };
                              return ({ star_idx: star_idx, x: $t27955, y: $t27959, mode: $t27960, fire_cooldown: 2.5, idle_timer: idle, hunter: false });
                            }
                          }
                        }
                      })();
                      {
                        const $t27962 = game.ships;
                        {
                          const $t27963 = (() => {
                            return { $: "Cons", _0: ship, _1: $t27962 };
                          })();
                          return ({ ...game, rng: rng2, ships: $t27963 });
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
const Perihelion$Combat$spawn_star_turret$clo = { _0: ($_, game, star_idx, rng) => Perihelion$Combat$spawn_star_turret(game, star_idx, rng) };

function Perihelion$Combat$spawn_hunter(game, rng) {
  {
    const idx = (() => {
      {
        const $t27967 = (() => {
          {
            const $t27966 = game.current;
            return ($t27966 > 0);
          }
        })();
        if ($t27967 === true) {
          return (() => {
            {
              const $t27968 = game.current;
              return ($t27968 - 1);
            }
          })();
        } else {
          return 0;
        }
      }
    })();
    {
      const $t27969 = Perihelion$Core$star_at(game, idx);
      switch ($t27969.$) {
        case "None": {
          return ({ ...game, rng: rng });
          break;
        }
        case "Some": {
          const $f27990 = $t27969._0;
          {
            const s = $f27990;
            {
              const $p27989 = (() => {
                {
                  const $p28516_i10049_i10348_i10566 = (() => {
                    {
                      const $p15576_i9795_i10044_i10343_i10561 = (() => {
                        {
                          const $p15573_i1532_i9785_i10035_i10334_i10552 = Random$next_raw(rng);
                          {
                            const hi_i1533_i9786_i10036_i10335_i10553 = $p15573_i1532_i9785_i10035_i10334_i10552._0;
                            {
                              const rng2_i1534_i9787_i10037_i10336_i10554 = $p15573_i1532_i9785_i10035_i10334_i10552._1;
                              {
                                const $p15572_i1535_i9788_i10038_i10337_i10555 = Random$next_raw(rng2_i1534_i9787_i10037_i10336_i10554);
                                {
                                  const lo_i1536_i9789_i10039_i10338_i10556 = $p15572_i1535_i9788_i10038_i10337_i10555._0;
                                  {
                                    const rng3_i1537_i9790_i10040_i10339_i10557 = $p15572_i1535_i9788_i10038_i10337_i10555._1;
                                    {
                                      const $t15571_i1541_i9794_i10043_i10342_i10560 = (() => {
                                        {
                                          const $t15570_i1540_i9793_i10042_i10341_i10559 = (() => {
                                            {
                                              const $t15568_i1538_i9791_i10041_i10340_i10558 = march_int_and(hi_i1533_i9786_i10036_i10335_i10553, 1048575);
                                              return ($t15568_i1538_i9791_i10041_i10340_i10558 * 4294967296);
                                            }
                                          })();
                                          return ($t15570_i1540_i9793_i10042_i10341_i10559 + lo_i1536_i9789_i10039_i10338_i10556);
                                        }
                                      })();
                                      return { _0: $t15571_i1541_i9794_i10043_i10342_i10560, _1: rng3_i1537_i9790_i10040_i10339_i10557 };
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      })();
                      {
                        const bits_i9796_i10045_i10344_i10562 = $p15576_i9795_i10044_i10343_i10561._0;
                        {
                          const rng2_i9797_i10046_i10345_i10563 = $p15576_i9795_i10044_i10343_i10561._1;
                          {
                            const $t15575_i9799_i10048_i10347_i10565 = (() => {
                              {
                                const $t15574_i9798_i10047_i10346_i10564 = bits_i9796_i10045_i10344_i10562;
                                return ($t15574_i9798_i10047_i10346_i10564 / 4.50359962737e+15);
                              }
                            })();
                            return { _0: $t15575_i9799_i10048_i10347_i10565, _1: rng2_i9797_i10046_i10345_i10563 };
                          }
                        }
                      }
                    }
                  })();
                  {
                    const t_i10050_i10349_i10567 = $p28516_i10049_i10348_i10566._0;
                    {
                      const rng2_i10051_i10350_i10568 = $p28516_i10049_i10348_i10566._1;
                      {
                        const out_i10052_i10351_i10569 = { _0: rng2_i10051_i10350_i10568, _1: t_i10050_i10349_i10567 };
                        return out_i10052_i10351_i10569;
                      }
                    }
                  }
                }
              })();
              {
                const rng2 = $p27989._0;
                {
                  const idle_f = $p27989._1;
                  {
                    const r = (() => {
                      {
                        const $t27970 = s.capture_radius;
                        return ($t27970 * 1.6);
                      }
                    })();
                    {
                      const idle = (() => {
                        {
                          const $t27976 = (() => {
                            {
                              const $t27975 = (6. - 3.);
                              return (idle_f * $t27975);
                            }
                          })();
                          return (3. + $t27976);
                        }
                      })();
                      {
                        const ship = (() => {
                          {
                            const $t27980 = (() => {
                              {
                                const $t27977 = s.x;
                                {
                                  const $t27979 = (() => {
                                    {
                                      const $t27978 = Math.cos(0.);
                                      return ($t27978 * r);
                                    }
                                  })();
                                  return ($t27977 + $t27979);
                                }
                              }
                            })();
                            {
                              const $t27984 = (() => {
                                {
                                  const $t27981 = s.y;
                                  {
                                    const $t27983 = (() => {
                                      {
                                        const $t27982 = Math.sin(0.);
                                        return ($t27982 * r);
                                      }
                                    })();
                                    return ($t27981 + $t27983);
                                  }
                                }
                              })();
                              {
                                const $t27985 = { $: "ShipOrbiting", _0: 0. };
                                return ({ star_idx: idx, x: $t27980, y: $t27984, mode: $t27985, fire_cooldown: 2.5, idle_timer: idle, hunter: true });
                              }
                            }
                          }
                        })();
                        {
                          const $t27987 = game.ships;
                          {
                            const $t27988 = (() => {
                              return { $: "Cons", _0: ship, _1: $t27987 };
                            })();
                            return ({ ...game, rng: rng2, ships: $t27988 });
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
}
const Perihelion$Combat$spawn_hunter$clo = { _0: ($_, game, rng) => Perihelion$Combat$spawn_hunter(game, rng) };

function Perihelion$Combat$maybe_spawn_ship(game, star_idx) {
  {
    const $t27993 = (() => {
      {
        const $t27991 = game.score;
        return ($t27991 < 4);
      }
    })();
    if ($t27993 === true) {
      return game;
    } else {
      return (() => {
        {
          const $p28005 = (() => {
            {
              const $t27994 = game.rng;
              {
                const $p28516_i10049_i10348_i10604 = (() => {
                  {
                    const $p15576_i9795_i10044_i10343_i10599 = (() => {
                      {
                        const $p15573_i1532_i9785_i10035_i10334_i10590 = Random$next_raw($t27994);
                        {
                          const hi_i1533_i9786_i10036_i10335_i10591 = $p15573_i1532_i9785_i10035_i10334_i10590._0;
                          {
                            const rng2_i1534_i9787_i10037_i10336_i10592 = $p15573_i1532_i9785_i10035_i10334_i10590._1;
                            {
                              const $p15572_i1535_i9788_i10038_i10337_i10593 = Random$next_raw(rng2_i1534_i9787_i10037_i10336_i10592);
                              {
                                const lo_i1536_i9789_i10039_i10338_i10594 = $p15572_i1535_i9788_i10038_i10337_i10593._0;
                                {
                                  const rng3_i1537_i9790_i10040_i10339_i10595 = $p15572_i1535_i9788_i10038_i10337_i10593._1;
                                  {
                                    const $t15571_i1541_i9794_i10043_i10342_i10598 = (() => {
                                      {
                                        const $t15570_i1540_i9793_i10042_i10341_i10597 = (() => {
                                          {
                                            const $t15568_i1538_i9791_i10041_i10340_i10596 = march_int_and(hi_i1533_i9786_i10036_i10335_i10591, 1048575);
                                            return ($t15568_i1538_i9791_i10041_i10340_i10596 * 4294967296);
                                          }
                                        })();
                                        return ($t15570_i1540_i9793_i10042_i10341_i10597 + lo_i1536_i9789_i10039_i10338_i10594);
                                      }
                                    })();
                                    return { _0: $t15571_i1541_i9794_i10043_i10342_i10598, _1: rng3_i1537_i9790_i10040_i10339_i10595 };
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    })();
                    {
                      const bits_i9796_i10045_i10344_i10600 = $p15576_i9795_i10044_i10343_i10599._0;
                      {
                        const rng2_i9797_i10046_i10345_i10601 = $p15576_i9795_i10044_i10343_i10599._1;
                        {
                          const $t15575_i9799_i10048_i10347_i10603 = (() => {
                            {
                              const $t15574_i9798_i10047_i10346_i10602 = bits_i9796_i10045_i10344_i10600;
                              return ($t15574_i9798_i10047_i10346_i10602 / 4.50359962737e+15);
                            }
                          })();
                          return { _0: $t15575_i9799_i10048_i10347_i10603, _1: rng2_i9797_i10046_i10345_i10601 };
                        }
                      }
                    }
                  }
                })();
                {
                  const t_i10050_i10349_i10605 = $p28516_i10049_i10348_i10604._0;
                  {
                    const rng2_i10051_i10350_i10606 = $p28516_i10049_i10348_i10604._1;
                    {
                      const out_i10052_i10351_i10607 = { _0: rng2_i10051_i10350_i10606, _1: t_i10050_i10349_i10605 };
                      return out_i10052_i10351_i10607;
                    }
                  }
                }
              }
            }
          })();
          {
            const rng2 = $p28005._0;
            {
              const roll = $p28005._1;
              {
                const chance_raw = (() => {
                  {
                    const $t27999 = (() => {
                      {
                        const $t27998 = (() => {
                          {
                            const $t27997 = (() => {
                              {
                                const $t27995 = game.score;
                                return ($t27995 - 4);
                              }
                            })();
                            return $t27997;
                          }
                        })();
                        return (0.04 * $t27998);
                      }
                    })();
                    return (0.16 + $t27999);
                  }
                })();
                {
                  const chance = (() => {
                    {
                      const $t28000 = (chance_raw > 0.45);
                      if ($t28000 === true) {
                        return 0.45;
                      } else {
                        return chance_raw;
                      }
                    }
                  })();
                  {
                    const $t28001 = (roll < chance);
                    if ($t28001 === true) {
                      return (() => {
                        {
                          const $p28004 = (() => {
                            {
                              const $p28516_i10049_i10348_i10585 = (() => {
                                {
                                  const $p15576_i9795_i10044_i10343_i10580 = (() => {
                                    {
                                      const $p15573_i1532_i9785_i10035_i10334_i10571 = Random$next_raw(rng2);
                                      {
                                        const hi_i1533_i9786_i10036_i10335_i10572 = $p15573_i1532_i9785_i10035_i10334_i10571._0;
                                        {
                                          const rng2_i1534_i9787_i10037_i10336_i10573 = $p15573_i1532_i9785_i10035_i10334_i10571._1;
                                          {
                                            const $p15572_i1535_i9788_i10038_i10337_i10574 = Random$next_raw(rng2_i1534_i9787_i10037_i10336_i10573);
                                            {
                                              const lo_i1536_i9789_i10039_i10338_i10575 = $p15572_i1535_i9788_i10038_i10337_i10574._0;
                                              {
                                                const rng3_i1537_i9790_i10040_i10339_i10576 = $p15572_i1535_i9788_i10038_i10337_i10574._1;
                                                {
                                                  const $t15571_i1541_i9794_i10043_i10342_i10579 = (() => {
                                                    {
                                                      const $t15570_i1540_i9793_i10042_i10341_i10578 = (() => {
                                                        {
                                                          const $t15568_i1538_i9791_i10041_i10340_i10577 = march_int_and(hi_i1533_i9786_i10036_i10335_i10572, 1048575);
                                                          return ($t15568_i1538_i9791_i10041_i10340_i10577 * 4294967296);
                                                        }
                                                      })();
                                                      return ($t15570_i1540_i9793_i10042_i10341_i10578 + lo_i1536_i9789_i10039_i10338_i10575);
                                                    }
                                                  })();
                                                  return { _0: $t15571_i1541_i9794_i10043_i10342_i10579, _1: rng3_i1537_i9790_i10040_i10339_i10576 };
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const bits_i9796_i10045_i10344_i10581 = $p15576_i9795_i10044_i10343_i10580._0;
                                    {
                                      const rng2_i9797_i10046_i10345_i10582 = $p15576_i9795_i10044_i10343_i10580._1;
                                      {
                                        const $t15575_i9799_i10048_i10347_i10584 = (() => {
                                          {
                                            const $t15574_i9798_i10047_i10346_i10583 = bits_i9796_i10045_i10344_i10581;
                                            return ($t15574_i9798_i10047_i10346_i10583 / 4.50359962737e+15);
                                          }
                                        })();
                                        return { _0: $t15575_i9799_i10048_i10347_i10584, _1: rng2_i9797_i10046_i10345_i10582 };
                                      }
                                    }
                                  }
                                }
                              })();
                              {
                                const t_i10050_i10349_i10586 = $p28516_i10049_i10348_i10585._0;
                                {
                                  const rng2_i10051_i10350_i10587 = $p28516_i10049_i10348_i10585._1;
                                  {
                                    const out_i10052_i10351_i10588 = { _0: rng2_i10051_i10350_i10587, _1: t_i10050_i10349_i10586 };
                                    return out_i10052_i10351_i10588;
                                  }
                                }
                              }
                            }
                          })();
                          {
                            const rng3 = $p28004._0;
                            {
                              const kind_roll = $p28004._1;
                              {
                                const $t28003 = (kind_roll < 0.5);
                                if ($t28003 === true) {
                                  return Perihelion$Combat$spawn_hunter(game, rng3);
                                } else {
                                  return Perihelion$Combat$spawn_star_turret(game, star_idx, rng3);
                                }
                              }
                            }
                          }
                        }
                      })();
                    } else {
                      return ({ ...game, rng: rng2 });
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
const Perihelion$Combat$maybe_spawn_ship$clo = { _0: ($_, game, star_idx) => Perihelion$Combat$maybe_spawn_ship(game, star_idx) };

function Perihelion$Core$star_at(game, i) {
  {
    const $t28006 = game.stars;
    return List$nth_opt$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int($t28006, i);
  }
}
const Perihelion$Core$star_at$clo = { _0: ($_, game, i) => Perihelion$Core$star_at(game, i) };

function Perihelion$Core$ring_count(s) {
  {
    const $t28007 = s.orbits;
    {
      const go_i3780 = { $: "$Clo_go$4740", _0: go$apply$4740 };
      return go$apply$4740(go_i3780, $t28007, 0);
    }
  }
}
const Perihelion$Core$ring_count$clo = { _0: ($_, s) => Perihelion$Core$ring_count(s) };

function Perihelion$Core$ring_at(s, i) {
  {
    const $t28009 = (() => {
      {
        const $t28008 = s.orbits;
        return List$nth_opt$List_R_radius_Float_speed_mult_Float$Int($t28008, i);
      }
    })();
    switch ($t28009.$) {
      case "Some": {
        const $f28012 = $t28009._0;
        {
          const o = $f28012;
          return o;
        }
        break;
      }
      case "None": {
        {
          const $t28010 = s.capture_radius;
          {
            const $t28011 = s.speed_mult;
            return ({ radius: $t28010, speed_mult: $t28011 });
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
const Perihelion$Core$ring_at$clo = { _0: ($_, s, i) => Perihelion$Core$ring_at(s, i) };

function Perihelion$Core$adjust_ring(ring_idx, keys, n) {
  {
    const out = (() => {
      {
        const $t28017 = { $: "$Clo_$lam28014$3711", _0: $lam28014$apply$3711 };
        return List$any$List_String$Fn_String_Bool(keys, $t28017);
      }
    })();
    {
      const inn = (() => {
        {
          const $t28021 = { $: "$Clo_$lam28018$3712", _0: $lam28018$apply$3712 };
          return List$any$List_String$Fn_String_Bool(keys, $t28021);
        }
      })();
      {
        const delta = (() => {
          {
            let $t28022;
            if (out === true) {
              $t28022 = 1;
            } else {
              $t28022 = 0;
            }
            {
              let $t28023;
              if (inn === true) {
                $t28023 = 1;
              } else {
                $t28023 = 0;
              }
              return ($t28022 - $t28023);
            }
          }
        })();
        {
          const target = (ring_idx + delta);
          {
            const $t28024 = (target < 0);
            if ($t28024 === true) {
              return 0;
            } else {
              return (() => {
                {
                  const $t28026 = (() => {
                    {
                      const $t28025 = (n - 1);
                      return (target > $t28025);
                    }
                  })();
                  if ($t28026 === true) {
                    return (n - 1);
                  } else {
                    return target;
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
const Perihelion$Core$adjust_ring$clo = { _0: ($_, ring_idx, keys, n) => Perihelion$Core$adjust_ring(ring_idx, keys, n) };

function Perihelion$Core$update(game, taps, keys, cursor, view_w, view_h, dt_s) {
  {
    const g0 = (() => {
      {
        const $t28027 = { $: "Nil" };
        {
          const $t28028 = { $: "None" };
          return ({ ...game, view_w: view_w, view_h: view_h, fx_bursts: $t28027, capture_flash: $t28028 });
        }
      }
    })();
    {
      const $t28033 = (() => {
        {
          const $t28032 = { $: "$Clo_$lam28029$3713", _0: $lam28029$apply$3713 };
          return List$any$List_String$Fn_String_Bool(keys, $t28032);
        }
      })();
      if ($t28033 === true) {
        return Perihelion$Core$reset(g0);
      } else {
        return (() => {
          {
            const tapped = (() => {
              {
                let $t28034;
                switch (taps.$) {
                  case "Nil": {
                    $t28034 = true;
                    break;
                  }
                  default: {
                    $t28034 = false;
                    break;
                  }
                }
                return (!$t28034);
              }
            })();
            {
              const $t28035 = g0.phase;
              switch ($t28035.$) {
                case "Ready": {
                  if (tapped === true) {
                    return (() => {
                      {
                        const $t28036 = { $: "Playing" };
                        return ({ ...g0, phase: $t28036 });
                      }
                    })();
                  } else {
                    return g0;
                  }
                  break;
                }
                case "Over": {
                  if (tapped === true) {
                    return Perihelion$Core$restart(g0);
                  } else {
                    return g0;
                  }
                  break;
                }
                case "Playing": {
                  return Perihelion$Core$step_playing(g0, tapped, keys, cursor, dt_s);
                  break;
                }
                default: {
                  return (() => { throw new Error("non-exhaustive pattern match"); })();
                }
              }
            }
          }
        })();
      }
    }
  }
}
const Perihelion$Core$update$clo = { _0: ($_, game, taps, keys, cursor, view_w, view_h, dt_s) => Perihelion$Core$update(game, taps, keys, cursor, view_w, view_h, dt_s) };

function Perihelion$Core$step_playing(game, tapped, keys, cursor, dt_s) {
  {
    const g1 = (() => {
      {
        const $t28037 = game.mode;
        switch ($t28037.$) {
          case "Orbiting": {
            const $f28038 = $t28037._0;
            const $f28039 = $t28037._1;
            const $f28040 = $t28037._2;
            {
              const angle = (() => {
                return $f28040;
              })();
              {
                const ring = (() => {
                  return $f28039;
                })();
                {
                  const idx = (() => {
                    return $f28038;
                  })();
                  return Perihelion$Core$step_orbit(game, idx, ring, angle, tapped, keys, dt_s);
                }
              }
            }
            break;
          }
          case "Flying": {
            const $f28049 = $t28037._0;
            const $f28050 = $t28037._1;
            {
              const vy = (() => {
                return $f28050;
              })();
              {
                const vx = (() => {
                  return $f28049;
                })();
                return Perihelion$Core$step_flight(game, vx, vy, dt_s);
              }
            }
            break;
          }
          default: {
            return (() => { throw new Error("non-exhaustive pattern match"); })();
          }
        }
      }
    })();
    {
      const $t28055 = g1.phase;
      switch ($t28055.$) {
        case "Playing": {
          {
            const g2 = (() => {
              {
                const g1_i3790 = Perihelion$Combat$step_spawn(g1, dt_s);
                {
                  const g2_i3791 = Perihelion$Combat$step_entities(g1_i3790, dt_s);
                  return Perihelion$Combat$step_ships(g2_i3791, dt_s);
                }
              }
            })();
            {
              const g3 = Perihelion$Combat$fire(g2, keys, cursor, dt_s);
              {
                const g4 = (() => {
                  {
                    const g1_i3785 = Perihelion$Combat$collide_shots_asteroids(g3);
                    {
                      const g2_i3786 = Perihelion$Combat$collide_shots_ships(g1_i3785);
                      {
                        const g3_i3787 = Perihelion$Combat$collide_ball_pickups(g2_i3786);
                        return Perihelion$Combat$collide_ball_hazards(g3_i3787);
                      }
                    }
                  }
                })();
                {
                  const $t28056 = (() => {
                    return g4.phase;
                  })();
                  switch ($t28056.$) {
                    case "Playing": {
                      {
                        const $t28057 = (() => {
                          {
                            const $rc_822 = Perihelion$Core$step_camera(g4, dt_s);
                            return $rc_822;
                          }
                        })();
                        return Perihelion$Core$top_up($t28057);
                      }
                      break;
                    }
                    default: {
                      return g4;
                    }
                  }
                }
              }
            }
          }
          break;
        }
        default: {
          return g1;
        }
      }
    }
  }
}
const Perihelion$Core$step_playing$clo = { _0: ($_, game, tapped, keys, cursor, dt_s) => Perihelion$Core$step_playing(game, tapped, keys, cursor, dt_s) };

function Perihelion$Core$step_orbit(game, idx, ring, angle, tapped, keys, dt_s) {
  {
    const $t28058 = Perihelion$Core$star_at(game, idx);
    switch ($t28058.$) {
      case "None": {
        return game;
        break;
      }
      case "Some": {
        const $f28081 = $t28058._0;
        {
          const s = $f28081;
          if (tapped === true) {
            return (() => {
              {
                const vx_i9745 = (() => {
                  {
                    const $t28085_i9744 = (() => {
                      {
                        const $t28083_i9742 = (1. * 340.);
                        {
                          const $t28084_i9743 = Math.sin(angle);
                          return ($t28083_i9742 * $t28084_i9743);
                        }
                      }
                    })();
                    return (0. - $t28085_i9744);
                  }
                })();
                {
                  const vy_i9748 = (() => {
                    {
                      const $t28087_i9746 = (1. * 340.);
                      {
                        const $t28088_i9747 = Math.cos(angle);
                        return ($t28087_i9746 * $t28088_i9747);
                      }
                    }
                  })();
                  {
                    const $t28089_i9749 = { $: "Flying", _0: vx_i9745, _1: vy_i9748 };
                    return ({ ...game, mode: $t28089_i9749 });
                  }
                }
              }
            })();
          } else {
            return (() => {
              {
                const ring2 = (() => {
                  {
                    const $t28059 = Perihelion$Core$ring_count(s);
                    return Perihelion$Core$adjust_ring(ring, keys, $t28059);
                  }
                })();
                {
                  const o = Perihelion$Core$ring_at(s, ring2);
                  {
                    const a2 = (() => {
                      {
                        const $t28065 = (() => {
                          {
                            const $t28064 = (() => {
                              {
                                const $t28062 = (1. * 1.8);
                                {
                                  const $t28063 = o.speed_mult;
                                  return ($t28062 * $t28063);
                                }
                              }
                            })();
                            return ($t28064 * dt_s);
                          }
                        })();
                        return (angle + $t28065);
                      }
                    })();
                    {
                      const r = o.radius;
                      {
                        const $t28066 = { $: "Orbiting", _0: idx, _1: ring2, _2: a2 };
                        {
                          const $t28072 = (() => {
                            {
                              const $t28067 = game.loop_angle;
                              {
                                const $t28071 = (() => {
                                  {
                                    const $t28070 = (() => {
                                      {
                                        const $t28069 = o.speed_mult;
                                        return (1.8 * $t28069);
                                      }
                                    })();
                                    return ($t28070 * dt_s);
                                  }
                                })();
                                return ($t28067 + $t28071);
                              }
                            }
                          })();
                          {
                            const $t28076 = (() => {
                              {
                                const $t28073 = s.x;
                                {
                                  const $t28075 = (() => {
                                    {
                                      const $t28074 = Math.cos(a2);
                                      return ($t28074 * r);
                                    }
                                  })();
                                  return ($t28073 + $t28075);
                                }
                              }
                            })();
                            {
                              const $t28080 = (() => {
                                {
                                  const $t28077 = s.y;
                                  {
                                    const $t28079 = (() => {
                                      {
                                        const $t28078 = Math.sin(a2);
                                        return ($t28078 * r);
                                      }
                                    })();
                                    return ($t28077 + $t28079);
                                  }
                                }
                              })();
                              return ({ ...game, mode: $t28066, loop_angle: $t28072, ball_x: $t28076, ball_y: $t28080 });
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const Perihelion$Core$step_orbit$clo = { _0: ($_, game, idx, ring, angle, tapped, keys, dt_s) => Perihelion$Core$step_orbit(game, idx, ring, angle, tapped, keys, dt_s) };

function Perihelion$Core$renormalize(vx, vy) {
  {
    const m = (() => {
      {
        const $t28092 = (() => {
          {
            const $t28090 = (vx * vx);
            {
              const $t28091 = (vy * vy);
              return ($t28090 + $t28091);
            }
          }
        })();
        return Math.sqrt($t28092);
      }
    })();
    {
      const $t28093 = (m > 0.);
      if ($t28093 === true) {
        return (() => {
          {
            const out = (() => {
              {
                const $t28096 = (() => {
                  {
                    const $t28094 = (vx / m);
                    return ($t28094 * 340.);
                  }
                })();
                {
                  const $t28099 = (() => {
                    {
                      const $t28097 = (vy / m);
                      return ($t28097 * 340.);
                    }
                  })();
                  return { _0: $t28096, _1: $t28099 };
                }
              }
            })();
            return out;
          }
        })();
      } else {
        return (() => {
          {
            const out = { _0: vx, _1: vy };
            return out;
          }
        })();
      }
    }
  }
}
const Perihelion$Core$renormalize$clo = { _0: ($_, vx, vy) => Perihelion$Core$renormalize(vx, vy) };

function Perihelion$Core$nearest_assist_target(game, vx, vy, stars, best, best_d) {
  switch (stars.$) {
    case "Nil": {
      return best;
      break;
    }
    case "Cons": {
      const $f28118 = stars._0;
      const $f28119 = stars._1;
      {
        const rest = $f28119;
        {
          const s = $f28118;
          {
            const dx = (() => {
              {
                const $t28100 = s.x;
                {
                  const $t28101 = game.ball_x;
                  return ($t28100 - $t28101);
                }
              }
            })();
            {
              const dy = (() => {
                {
                  const $t28102 = s.y;
                  {
                    const $t28103 = game.ball_y;
                    return ($t28102 - $t28103);
                  }
                }
              })();
              {
                const d = (() => {
                  {
                    const $t28106 = (() => {
                      {
                        const $t28104 = (dx * dx);
                        {
                          const $t28105 = (dy * dy);
                          return ($t28104 + $t28105);
                        }
                      }
                    })();
                    return Math.sqrt($t28106);
                  }
                })();
                {
                  const approaching = (() => {
                    {
                      const $t28109 = (() => {
                        {
                          const $t28107 = (vx * dx);
                          {
                            const $t28108 = (vy * dy);
                            return ($t28107 + $t28108);
                          }
                        }
                      })();
                      return ($t28109 > 0.);
                    }
                  })();
                  {
                    const $t28116 = (() => {
                      {
                        const $t28114 = (() => {
                          {
                            const $t28113 = (() => {
                              {
                                const $t28112 = (() => {
                                  {
                                    const $t28111 = s.capture_radius;
                                    return (2.4 * $t28111);
                                  }
                                })();
                                return (d < $t28112);
                              }
                            })();
                            return (approaching && $t28113);
                          }
                        })();
                        {
                          const $t28115 = (d < best_d);
                          return ($t28114 && $t28115);
                        }
                      }
                    })();
                    if ($t28116 === true) {
                      return (() => {
                        {
                          const $t28117 = { $: "Some", _0: s };
                          return Perihelion$Core$nearest_assist_target(game, vx, vy, rest, $t28117, d);
                        }
                      })();
                    } else {
                      return Perihelion$Core$nearest_assist_target(game, vx, vy, rest, best, best_d);
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
const Perihelion$Core$nearest_assist_target$clo = { _0: ($_, game, vx, vy, stars, best, best_d) => Perihelion$Core$nearest_assist_target(game, vx, vy, stars, best, best_d) };

function Perihelion$Core$assisted_velocity(game, vx, vy, dt_s) {
  {
    const $t28126 = (() => {
      {
        const $t28124 = game.stars;
        {
          const $t28125 = { $: "None" };
          return Perihelion$Core$nearest_assist_target(game, vx, vy, $t28124, $t28125, 999999.);
        }
      }
    })();
    switch ($t28126.$) {
      case "None": {
        {
          const out = { _0: vx, _1: vy };
          return out;
        }
        break;
      }
      case "Some": {
        const $f28145 = $t28126._0;
        {
          const t = $f28145;
          {
            const dx = (() => {
              {
                const $t28127 = t.x;
                {
                  const $t28128 = game.ball_x;
                  return ($t28127 - $t28128);
                }
              }
            })();
            {
              const dy = (() => {
                {
                  const $t28129 = t.y;
                  {
                    const $t28130 = game.ball_y;
                    return ($t28129 - $t28130);
                  }
                }
              })();
              {
                const dist = (() => {
                  {
                    const $t28133 = (() => {
                      {
                        const $t28131 = (dx * dx);
                        {
                          const $t28132 = (dy * dy);
                          return ($t28131 + $t28132);
                        }
                      }
                    })();
                    return Math.sqrt($t28133);
                  }
                })();
                {
                  const $t28134 = (dist > 0.);
                  if ($t28134 === true) {
                    return (() => {
                      {
                        const $t28139 = (() => {
                          {
                            const $t28138 = (() => {
                              {
                                const $t28137 = (() => {
                                  {
                                    const $t28135 = (dx / dist);
                                    return ($t28135 * 1600.);
                                  }
                                })();
                                return ($t28137 * dt_s);
                              }
                            })();
                            return (vx + $t28138);
                          }
                        })();
                        {
                          const $t28144 = (() => {
                            {
                              const $t28143 = (() => {
                                {
                                  const $t28142 = (() => {
                                    {
                                      const $t28140 = (dy / dist);
                                      return ($t28140 * 1600.);
                                    }
                                  })();
                                  return ($t28142 * dt_s);
                                }
                              })();
                              return (vy + $t28143);
                            }
                          })();
                          return Perihelion$Core$renormalize($t28139, $t28144);
                        }
                      }
                    })();
                  } else {
                    return (() => {
                      {
                        const out = { _0: vx, _1: vy };
                        return out;
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
}
const Perihelion$Core$assisted_velocity$clo = { _0: ($_, game, vx, vy, dt_s) => Perihelion$Core$assisted_velocity(game, vx, vy, dt_s) };

function Perihelion$Core$find_capture(game, vx, vy, stars, i) {
  switch (stars.$) {
    case "Nil": {
      return { $: "None" };
      break;
    }
    case "Cons": {
      const $f28166 = stars._0;
      const $f28167 = stars._1;
      {
        const rest = $f28167;
        {
          const s = $f28166;
          {
            const dx = (() => {
              {
                const $t28146 = s.x;
                {
                  const $t28147 = game.ball_x;
                  return ($t28146 - $t28147);
                }
              }
            })();
            {
              const dy = (() => {
                {
                  const $t28148 = s.y;
                  {
                    const $t28149 = game.ball_y;
                    return ($t28148 - $t28149);
                  }
                }
              })();
              {
                const grace = (() => {
                  {
                    const $t28150 = s.capture_radius;
                    return ($t28150 + 6.);
                  }
                })();
                {
                  const approaching = (() => {
                    {
                      const $t28154 = (() => {
                        {
                          const $t28152 = (vx * dx);
                          {
                            const $t28153 = (vy * dy);
                            return ($t28152 + $t28153);
                          }
                        }
                      })();
                      return ($t28154 > 0.);
                    }
                  })();
                  {
                    const $t28163 = (() => {
                      {
                        const $t28157 = (() => {
                          {
                            const $t28156 = (() => {
                              {
                                const $t28155 = game.current;
                                return (i !== $t28155);
                              }
                            })();
                            return ($t28156 && approaching);
                          }
                        })();
                        {
                          const $t28162 = (() => {
                            {
                              const $t28161 = (() => {
                                {
                                  const $t28160 = (() => {
                                    {
                                      const $t28158 = (dx * dx);
                                      {
                                        const $t28159 = (dy * dy);
                                        return ($t28158 + $t28159);
                                      }
                                    }
                                  })();
                                  return Math.sqrt($t28160);
                                }
                              })();
                              return ($t28161 <= grace);
                            }
                          })();
                          return ($t28157 && $t28162);
                        }
                      }
                    })();
                    if ($t28163 === true) {
                      return (() => {
                        {
                          const $t28164 = { _0: i, _1: s };
                          return { $: "Some", _0: $t28164 };
                        }
                      })();
                    } else {
                      return (() => {
                        {
                          const $t28165 = (i + 1);
                          return Perihelion$Core$find_capture(game, vx, vy, rest, $t28165);
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
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Perihelion$Core$find_capture$clo = { _0: ($_, game, vx, vy, stars, i) => Perihelion$Core$find_capture(game, vx, vy, stars, i) };

function Perihelion$Core$step_flight(game, vx, vy, dt_s) {
  {
    const $p28188 = Perihelion$Core$assisted_velocity(game, vx, vy, dt_s);
    {
      const vx2 = $p28188._0;
      {
        const vy2 = $p28188._1;
        {
          const g = (() => {
            {
              const $t28174 = (() => {
                {
                  const $t28172 = game.ball_x;
                  {
                    const $t28173 = (vx2 * dt_s);
                    return ($t28172 + $t28173);
                  }
                }
              })();
              {
                const $t28177 = (() => {
                  {
                    const $t28175 = game.ball_y;
                    {
                      const $t28176 = (vy2 * dt_s);
                      return ($t28175 + $t28176);
                    }
                  }
                })();
                {
                  const $t28178 = { $: "Flying", _0: vx2, _1: vy2 };
                  return ({ ...game, ball_x: $t28174, ball_y: $t28177, mode: $t28178 });
                }
              }
            }
          })();
          {
            const $t28180 = (() => {
              {
                const $t28179 = g.stars;
                return Perihelion$Core$find_capture(g, vx2, vy2, $t28179, 0);
              }
            })();
            switch ($t28180.$) {
              case "None": {
                return Perihelion$Core$check_death(g);
                break;
              }
              case "Some": {
                const $f28181 = $t28180._0;
                const $f28182 = $f28181._0;
                const $f28183 = $f28181._1;
                {
                  const t = $f28183;
                  {
                    const idx = $f28182;
                    return Perihelion$Core$on_capture(g, t, idx);
                  }
                }
                return (() => { throw new Error("non-exhaustive pattern match"); })();
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
const Perihelion$Core$step_flight$clo = { _0: ($_, game, vx, vy, dt_s) => Perihelion$Core$step_flight(game, vx, vy, dt_s) };

function Perihelion$Core$on_capture(game, captured, idx) {
  {
    const angle = (() => {
      {
        const $t28191 = (() => {
          {
            const $t28189 = game.ball_y;
            {
              const $t28190 = captured.y;
              return ($t28189 - $t28190);
            }
          }
        })();
        {
          const $t28194 = (() => {
            {
              const $t28192 = game.ball_x;
              {
                const $t28193 = captured.x;
                return ($t28192 - $t28193);
              }
            }
          })();
          return Math.atan2($t28191, $t28194);
        }
      }
    })();
    {
      const snapped = (() => {
        {
          const $t28196 = (() => {
            {
              const $t28195 = (() => {
                {
                  const $t28013_i3815 = Perihelion$Core$ring_count(captured);
                  return ($t28013_i3815 - 1);
                }
              })();
              return { $: "Orbiting", _0: idx, _1: $t28195, _2: angle };
            }
          })();
          {
            const $t28201 = (() => {
              {
                const $t28197 = captured.x;
                {
                  const $t28200 = (() => {
                    {
                      const $t28198 = Math.cos(angle);
                      {
                        const $t28199 = captured.capture_radius;
                        return ($t28198 * $t28199);
                      }
                    }
                  })();
                  return ($t28197 + $t28200);
                }
              }
            })();
            {
              const $t28206 = (() => {
                {
                  const $t28202 = captured.y;
                  {
                    const $t28205 = (() => {
                      {
                        const $t28203 = Math.sin(angle);
                        {
                          const $t28204 = captured.capture_radius;
                          return ($t28203 * $t28204);
                        }
                      }
                    })();
                    return ($t28202 + $t28205);
                  }
                }
              })();
              return ({ ...game, mode: $t28196, loop_angle: 0., ball_x: $t28201, ball_y: $t28206 });
            }
          }
        }
      })();
      {
        const $t28208 = (() => {
          {
            const $t28207 = game.current;
            return (idx > $t28207);
          }
        })();
        if ($t28208 === true) {
          return (() => {
            {
              const new_mult = (() => {
                {
                  const $t28211 = (() => {
                    {
                      const $t28209 = game.loop_angle;
                      return ($t28209 < 6.28318530718);
                    }
                  })();
                  if ($t28211 === true) {
                    return (() => {
                      {
                        const $t28215 = (() => {
                          {
                            const $t28213 = (() => {
                              {
                                const $t28212 = game.multiplier;
                                return ($t28212 + 1);
                              }
                            })();
                            return ($t28213 > 5);
                          }
                        })();
                        if ($t28215 === true) {
                          return 5;
                        } else {
                          return (() => {
                            {
                              const $t28216 = game.multiplier;
                              return ($t28216 + 1);
                            }
                          })();
                        }
                      }
                    })();
                  } else {
                    return 1;
                  }
                }
              })();
              {
                const $t28227 = (() => {
                  {
                    const $t28218 = (() => {
                      {
                        const $t28217 = game.score;
                        return ($t28217 + new_mult);
                      }
                    })();
                    {
                      const $t28220 = (() => {
                        {
                          const $t28219 = game.stars_chained;
                          return ($t28219 + 1);
                        }
                      })();
                      {
                        const $t28222 = (() => {
                          {
                            const $t28221 = game.max_mult;
                            {
                              const $t28262_i3811 = ($t28221 > new_mult);
                              if ($t28262_i3811 === true) {
                                return $t28221;
                              } else {
                                return new_mult;
                              }
                            }
                          }
                        })();
                        {
                          const $t28226 = (() => {
                            {
                              const $t28225 = (() => {
                                {
                                  const $t28223 = captured.x;
                                  {
                                    const $t28224 = captured.y;
                                    return { _0: $t28223, _1: $t28224 };
                                  }
                                }
                              })();
                              return { $: "Some", _0: $t28225 };
                            }
                          })();
                          return ({ ...snapped, current: idx, score: $t28218, stars_chained: $t28220, multiplier: new_mult, max_mult: $t28222, capture_flash: $t28226 });
                        }
                      }
                    }
                  }
                })();
                return Perihelion$Core$top_up($t28227);
              }
            }
          })();
        } else {
          return ({ ...snapped, current: idx, multiplier: 1 });
        }
      }
    }
  }
}
const Perihelion$Core$on_capture$clo = { _0: ($_, game, captured, idx) => Perihelion$Core$on_capture(game, captured, idx) };

function Perihelion$Core$top_up(game) {
  {
    const fallback = (() => {
      {
        const $t28229 = (() => {
          {
            const $t28228 = game.view_w;
            return ($t28228 / 2.);
          }
        })();
        {
          const $t28230 = ({ radius: 54., speed_mult: 1. });
          {
            const $t28231 = { $: "Nil" };
            {
              const $t28232 = { $: "Cons", _0: $t28230, _1: $t28231 };
              return ({ x: $t28229, y: 520., radius: 18., capture_radius: 54., speed_mult: 1., orbits: $t28232 });
            }
          }
        }
      }
    })();
    {
      const top = (() => {
        {
          const $t28233 = game.stars;
          return Perihelion$Core$top_star($t28233, fallback);
        }
      })();
      {
        const $t28240 = (() => {
          {
            const $t28234 = top.y;
            {
              const $t28239 = (() => {
                {
                  const $t28235 = game.camera_y;
                  {
                    const $t28238 = (() => {
                      {
                        const $t28236 = game.view_h;
                        return ($t28236 * 1.5);
                      }
                    })();
                    return ($t28235 - $t28238);
                  }
                }
              })();
              return ($t28234 > $t28239);
            }
          }
        })();
        if ($t28240 === true) {
          return (() => {
            {
              const $p28251 = (() => {
                {
                  const $t28241 = game.rng;
                  {
                    const $t28242 = game.view_w;
                    return Perihelion$Level$next_star($t28241, top, $t28242);
                  }
                }
              })();
              {
                const fresh = $p28251._0;
                {
                  const rng2 = $p28251._1;
                  {
                    const g2 = (() => {
                      {
                        const $t28243 = game.stars;
                        {
                          const $t28244 = { $: "Nil" };
                          {
                            const $t28245 = { $: "Cons", _0: fresh, _1: $t28244 };
                            {
                              const $t28246 = (() => {
                                {
                                  const go_i9752 = { $: "$Clo_go$4745", _0: go$apply$4745 };
                                  {
                                    const $t258_i9755 = (() => {
                                      {
                                        const go_i4358_i9753 = { $: "$Clo_go$5180", _0: go$apply$5180 };
                                        {
                                          const $t250_i4359_i9754 = { $: "Nil" };
                                          return go$apply$5180(go_i4358_i9753, $t28243, $t250_i4359_i9754);
                                        }
                                      }
                                    })();
                                    return go$apply$4745(go_i9752, $t258_i9755, $t28245);
                                  }
                                }
                              })();
                              return ({ ...game, stars: $t28246, rng: rng2 });
                            }
                          }
                        }
                      }
                    })();
                    {
                      const $t28250 = (() => {
                        {
                          const $t28249 = (() => {
                            {
                              const $t28248 = (() => {
                                {
                                  const $t28247 = g2.stars;
                                  {
                                    const go_i3819 = { $: "$Clo_go$4743", _0: go$apply$4743 };
                                    return go$apply$4743(go_i3819, $t28247, 0);
                                  }
                                }
                              })();
                              return ($t28248 - 1);
                            }
                          })();
                          return Perihelion$Combat$maybe_spawn_ship(g2, $t28249);
                        }
                      })();
                      return Perihelion$Core$top_up($t28250);
                    }
                  }
                }
              }
            }
          })();
        } else {
          return game;
        }
      }
    }
  }
}
const Perihelion$Core$top_up$clo = { _0: ($_, game) => Perihelion$Core$top_up(game) };

function Perihelion$Core$top_star(stars, fallback) {
  switch (stars.$) {
    case "Nil": {
      return fallback;
      break;
    }
    case "Cons": {
      const $f28252 = stars._0;
      const $f28253 = stars._1;
      {
        const $jp_clo28259 = (() => {
          return { $: "$Clo_$jp28258$3721", _0: $jp28258$apply$3721, _1: $f28253, _2: fallback };
        })();
        switch ($f28253.$) {
          case "Nil": {
            {
              const s = $f28252;
              return s;
            }
            break;
          }
          default: {
            return $jp28258$apply$3721($jp_clo28259);
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
const Perihelion$Core$top_star$clo = { _0: ($_, stars, fallback) => Perihelion$Core$top_star(stars, fallback) };

function Perihelion$Core$end_run(game) {
  {
    const rec = (() => {
      {
        const $t28263 = game.score;
        {
          const $t28264 = game.stars_chained;
          {
            const $t28265 = game.max_mult;
            return ({ score: $t28263, stars: $t28264, max_mult: $t28265 });
          }
        }
      }
    })();
    {
      const $t28266 = { $: "Over" };
      {
        const $t28269 = (() => {
          {
            const $t28267 = game.best;
            {
              const $t28268 = game.score;
              {
                const $t28262_i3827 = ($t28267 > $t28268);
                if ($t28262_i3827 === true) {
                  return $t28267;
                } else {
                  return $t28268;
                }
              }
            }
          }
        })();
        {
          const $t28270 = game.runs;
          {
            const $t28271 = (() => {
              return { $: "Cons", _0: rec, _1: $t28270 };
            })();
            {
              const $t28272 = (() => {
                {
                  const go_i3823 = { $: "$Clo_go$4747", _0: go$apply$4747 };
                  {
                    const $t505_i3824 = { $: "Nil" };
                    return go$apply$4747(go_i3823, $t28271, 10, $t505_i3824);
                  }
                }
              })();
              return ({ ...game, phase: $t28266, best: $t28269, runs: $t28272 });
            }
          }
        }
      }
    }
  }
}
const Perihelion$Core$end_run$clo = { _0: ($_, game) => Perihelion$Core$end_run(game) };

function Perihelion$Core$check_death(game) {
  {
    const below = (() => {
      {
        const $t28273 = game.ball_y;
        {
          const $t28278 = (() => {
            {
              const $t28276 = (() => {
                {
                  const $t28274 = game.camera_y;
                  {
                    const $t28275 = game.view_h;
                    return ($t28274 + $t28275);
                  }
                }
              })();
              return ($t28276 + 40.);
            }
          })();
          return ($t28273 > $t28278);
        }
      }
    })();
    {
      const off_side = (() => {
        {
          const $t28282 = (() => {
            {
              const $t28279 = game.ball_x;
              {
                const $t28281 = (0. - 40.);
                return ($t28279 < $t28281);
              }
            }
          })();
          {
            const $t28287 = (() => {
              {
                const $t28283 = game.ball_x;
                {
                  const $t28286 = (() => {
                    {
                      const $t28284 = game.view_w;
                      return ($t28284 + 40.);
                    }
                  })();
                  return ($t28283 > $t28286);
                }
              }
            })();
            return ($t28282 || $t28287);
          }
        }
      })();
      {
        const fallback = (() => {
          {
            const $t28289 = (() => {
              {
                const $t28288 = game.view_w;
                return ($t28288 / 2.);
              }
            })();
            {
              const $t28290 = ({ radius: 54., speed_mult: 1. });
              {
                const $t28291 = { $: "Nil" };
                {
                  const $t28292 = { $: "Cons", _0: $t28290, _1: $t28291 };
                  return ({ x: $t28289, y: 520., radius: 18., capture_radius: 54., speed_mult: 1., orbits: $t28292 });
                }
              }
            }
          }
        })();
        {
          const topmost = (() => {
            {
              const $t28293 = game.stars;
              return Perihelion$Core$top_star($t28293, fallback);
            }
          })();
          {
            const overshot = (() => {
              {
                const $t28294 = game.ball_y;
                {
                  const $t28297 = (() => {
                    {
                      const $t28295 = topmost.y;
                      return ($t28295 - 150.);
                    }
                  })();
                  return ($t28294 < $t28297);
                }
              }
            })();
            {
              const fallen = (() => {
                {
                  const $t28298 = Perihelion$Core$star_at(game, 0);
                  switch ($t28298.$) {
                    case "None": {
                      return false;
                      break;
                    }
                    case "Some": {
                      const $f28303 = $t28298._0;
                      {
                        const c = $f28303;
                        {
                          const $t28299 = game.ball_y;
                          {
                            const $t28302 = (() => {
                              {
                                const $t28300 = c.y;
                                return ($t28300 + 200.);
                              }
                            })();
                            return ($t28299 > $t28302);
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
              })();
              {
                const $t28306 = (() => {
                  {
                    const $t28305 = (() => {
                      {
                        const $t28304 = (below || off_side);
                        return ($t28304 || overshot);
                      }
                    })();
                    return ($t28305 || fallen);
                  }
                })();
                if ($t28306 === true) {
                  return Perihelion$Core$end_run(game);
                } else {
                  return game;
                }
              }
            }
          }
        }
      }
    }
  }
}
const Perihelion$Core$check_death$clo = { _0: ($_, game) => Perihelion$Core$check_death(game) };

function Perihelion$Core$step_camera(game, dt_s) {
  {
    const focus_x = (() => {
      {
        const $t28307 = game.mode;
        switch ($t28307.$) {
          case "Flying": {
            const $f28314 = $t28307._0;
            const $f28315 = $t28307._1;
            (() => {
              return $f28314;
            })();
            return game.ball_x;
            break;
          }
          case "Orbiting": {
            const $f28320 = $t28307._0;
            const $f28321 = $t28307._1;
            const $f28322 = $t28307._2;
            {
              const $t28309 = (() => {
                {
                  const $t28308 = game.current;
                  return Perihelion$Core$star_at(game, $t28308);
                }
              })();
              switch ($t28309.$) {
                case "None": {
                  {
                    const $t28310 = game.camera_x;
                    {
                      const $t28312 = (() => {
                        {
                          const $t28311 = game.view_w;
                          return ($t28311 / 2.);
                        }
                      })();
                      return ($t28310 + $t28312);
                    }
                  }
                  break;
                }
                case "Some": {
                  const $f28313 = $t28309._0;
                  {
                    const s = $f28313;
                    return s.x;
                  }
                  break;
                }
                default: {
                  return (() => { throw new Error("non-exhaustive pattern match"); })();
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
    })();
    {
      const target_y = (() => {
        {
          const $t28331 = game.mode;
          switch ($t28331.$) {
            case "Flying": {
              const $f28343 = $t28331._0;
              const $f28344 = $t28331._1;
              {
                const $t28332 = game.ball_y;
                {
                  const $t28335 = (() => {
                    {
                      const $t28334 = game.view_h;
                      return (0.6 * $t28334);
                    }
                  })();
                  return ($t28332 - $t28335);
                }
              }
              break;
            }
            case "Orbiting": {
              const $f28349 = $t28331._0;
              const $f28350 = $t28331._1;
              const $f28351 = $t28331._2;
              {
                const $t28337 = (() => {
                  {
                    const $t28336 = game.current;
                    return Perihelion$Core$star_at(game, $t28336);
                  }
                })();
                switch ($t28337.$) {
                  case "None": {
                    return game.camera_y;
                    break;
                  }
                  case "Some": {
                    const $f28342 = $t28337._0;
                    {
                      const s = $f28342;
                      {
                        const $t28338 = s.y;
                        {
                          const $t28341 = (() => {
                            {
                              const $t28340 = game.view_h;
                              return (0.6 * $t28340);
                            }
                          })();
                          return ($t28338 - $t28341);
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
              break;
            }
            default: {
              return (() => { throw new Error("non-exhaustive pattern match"); })();
            }
          }
        }
      })();
      {
        const left_edge = (() => {
          {
            const $t28360 = game.view_w;
            return ($t28360 * 0.25);
          }
        })();
        {
          const right_edge = (() => {
            {
              const $t28362 = game.view_w;
              {
                const $t28364 = (1. - 0.25);
                return ($t28362 * $t28364);
              }
            }
          })();
          {
            const screen_x = (() => {
              {
                const $t28365 = game.camera_x;
                return (focus_x - $t28365);
              }
            })();
            {
              const target_x = (() => {
                {
                  const $t28366 = (screen_x < left_edge);
                  if ($t28366 === true) {
                    return (focus_x - left_edge);
                  } else {
                    return (() => {
                      {
                        const $t28367 = (screen_x > right_edge);
                        if ($t28367 === true) {
                          return (focus_x - right_edge);
                        } else {
                          return game.camera_x;
                        }
                      }
                    })();
                  }
                }
              })();
              {
                const $t28374 = (() => {
                  {
                    const $t28368 = game.camera_y;
                    {
                      const $t28373 = (() => {
                        {
                          const $t28372 = (() => {
                            {
                              const $t28370 = (() => {
                                {
                                  const $t28369 = game.camera_y;
                                  return (target_y - $t28369);
                                }
                              })();
                              return ($t28370 * 3.);
                            }
                          })();
                          return ($t28372 * dt_s);
                        }
                      })();
                      return ($t28368 + $t28373);
                    }
                  }
                })();
                {
                  const $t28381 = (() => {
                    {
                      const $t28375 = game.camera_x;
                      {
                        const $t28380 = (() => {
                          {
                            const $t28379 = (() => {
                              {
                                const $t28377 = (() => {
                                  {
                                    const $t28376 = game.camera_x;
                                    return (target_x - $t28376);
                                  }
                                })();
                                return ($t28377 * 3.);
                              }
                            })();
                            return ($t28379 * dt_s);
                          }
                        })();
                        return ($t28375 + $t28380);
                      }
                    }
                  })();
                  return ({ ...game, camera_y: $t28374, camera_x: $t28381 });
                }
              }
            }
          }
        }
      }
    }
  }
}
const Perihelion$Core$step_camera$clo = { _0: ($_, game, dt_s) => Perihelion$Core$step_camera(game, dt_s) };

function Perihelion$Core$fresh_run(seed, best, runs, view_w, view_h) {
  {
    const $p28425 = (() => {
      {
        const $t28382 = Random$seed(seed);
        return Perihelion$Level$initial_stars($t28382, view_w);
      }
    })();
    {
      const stars = $p28425._0;
      {
        const rng2 = $p28425._1;
        {
          const start_angle = (3.14159265359 / 2.);
          switch (stars.$) {
            case "Nil": {
              {
                const $t28384 = { $: "Ready" };
                {
                  const $t28385 = { $: "Orbiting", _0: 0, _1: 0, _2: start_angle };
                  {
                    const $t28386 = { $: "Nil" };
                    {
                      const $t28387 = { $: "Nil" };
                      {
                        const $t28388 = { $: "Nil" };
                        {
                          const $t28389 = { $: "Nil" };
                          {
                            const $t28390 = { $: "Nil" };
                            {
                              const $t28391 = { $: "Nil" };
                              {
                                const $t28393 = { $: "Nil" };
                                {
                                  const $t28394 = { $: "None" };
                                  return ({ seed: seed, phase: $t28384, ball_x: 0., ball_y: 0., mode: $t28385, stars: $t28386, current: 0, score: 0, best: best, camera_y: 0., camera_x: 0., rng: rng2, asteroids: $t28387, ships: $t28388, player_shots: $t28389, enemy_shots: $t28390, pickups: $t28391, shield: false, multiplier: 1, max_mult: 1, stars_chained: 0, loop_angle: 0., fire_cooldown: 0., spawn_timer: 4., runs: runs, view_w: view_w, view_h: view_h, fx_bursts: $t28393, capture_flash: $t28394 });
                                }
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
            case "Cons": {
              const $f28419 = stars._0;
              const $f28420 = stars._1;
              {
                const s0 = (() => {
                  return $f28419;
                })();
                {
                  const $t28395 = { $: "Ready" };
                  {
                    const $t28400 = (() => {
                      {
                        const $t28396 = s0.x;
                        {
                          const $t28399 = (() => {
                            {
                              const $t28397 = Math.cos(start_angle);
                              {
                                const $t28398 = s0.capture_radius;
                                return ($t28397 * $t28398);
                              }
                            }
                          })();
                          return ($t28396 + $t28399);
                        }
                      }
                    })();
                    {
                      const $t28405 = (() => {
                        {
                          const $t28401 = s0.y;
                          {
                            const $t28404 = (() => {
                              {
                                const $t28402 = Math.sin(start_angle);
                                {
                                  const $t28403 = s0.capture_radius;
                                  return ($t28402 * $t28403);
                                }
                              }
                            })();
                            return ($t28401 + $t28404);
                          }
                        }
                      })();
                      {
                        const $t28406 = { $: "Orbiting", _0: 0, _1: 0, _2: start_angle };
                        {
                          const $t28410 = (() => {
                            {
                              const $t28407 = s0.y;
                              {
                                const $t28409 = (0.6 * view_h);
                                return ($t28407 - $t28409);
                              }
                            }
                          })();
                          {
                            const $t28411 = { $: "Nil" };
                            {
                              const $t28412 = { $: "Nil" };
                              {
                                const $t28413 = { $: "Nil" };
                                {
                                  const $t28414 = { $: "Nil" };
                                  {
                                    const $t28415 = { $: "Nil" };
                                    {
                                      const $t28417 = { $: "Nil" };
                                      {
                                        const $t28418 = { $: "None" };
                                        return ({ seed: seed, phase: $t28395, ball_x: $t28400, ball_y: $t28405, mode: $t28406, stars: stars, current: 0, score: 0, best: best, camera_y: $t28410, camera_x: 0., rng: rng2, asteroids: $t28411, ships: $t28412, player_shots: $t28413, enemy_shots: $t28414, pickups: $t28415, shield: false, multiplier: 1, max_mult: 1, stars_chained: 0, loop_angle: 0., fire_cooldown: 0., spawn_timer: 4., runs: runs, view_w: view_w, view_h: view_h, fx_bursts: $t28417, capture_flash: $t28418 });
                                      }
                                    }
                                  }
                                }
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
    }
  }
}
const Perihelion$Core$fresh_run$clo = { _0: ($_, seed, best, runs, view_w, view_h) => Perihelion$Core$fresh_run(seed, best, runs, view_w, view_h) };

function Perihelion$Core$restart(game) {
  {
    const g = (() => {
      {
        const $t28431 = (() => {
          {
            const $p28430_i9768 = (() => {
              {
                const $t28429_i9757 = game.rng;
                {
                  const $p15573_i3842_i9758 = Random$next_raw($t28429_i9757);
                  {
                    const hi_i3843_i9759 = $p15573_i3842_i9758._0;
                    {
                      const rng2_i3844_i9760 = $p15573_i3842_i9758._1;
                      {
                        const $p15572_i3845_i9761 = Random$next_raw(rng2_i3844_i9760);
                        {
                          const lo_i3846_i9762 = $p15572_i3845_i9761._0;
                          {
                            const rng3_i3847_i9763 = $p15572_i3845_i9761._1;
                            {
                              const $t15571_i3851_i9767 = (() => {
                                {
                                  const $t15570_i3850_i9766 = (() => {
                                    {
                                      const $t15568_i3848_i9764 = march_int_and(hi_i3843_i9759, 1048575);
                                      return ($t15568_i3848_i9764 * 4294967296);
                                    }
                                  })();
                                  return ($t15570_i3850_i9766 + lo_i3846_i9762);
                                }
                              })();
                              return { _0: $t15571_i3851_i9767, _1: rng3_i3847_i9763 };
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
              const s_i9769 = $p28430_i9768._0;
              return s_i9769;
            }
          }
        })();
        {
          const $t28432 = game.best;
          {
            const $t28433 = game.runs;
            {
              const $t28434 = game.view_w;
              {
                const $t28435 = game.view_h;
                return Perihelion$Core$fresh_run($t28431, $t28432, $t28433, $t28434, $t28435);
              }
            }
          }
        }
      }
    })();
    {
      const $t28436 = { $: "Playing" };
      return ({ ...g, phase: $t28436 });
    }
  }
}
const Perihelion$Core$restart$clo = { _0: ($_, game) => Perihelion$Core$restart(game) };

function Perihelion$Core$reset(game) {
  {
    const $t28437 = (() => {
      {
        const $p28430_i9782 = (() => {
          {
            const $t28429_i9771 = game.rng;
            {
              const $p15573_i3842_i9772 = Random$next_raw($t28429_i9771);
              {
                const hi_i3843_i9773 = $p15573_i3842_i9772._0;
                {
                  const rng2_i3844_i9774 = $p15573_i3842_i9772._1;
                  {
                    const $p15572_i3845_i9775 = Random$next_raw(rng2_i3844_i9774);
                    {
                      const lo_i3846_i9776 = $p15572_i3845_i9775._0;
                      {
                        const rng3_i3847_i9777 = $p15572_i3845_i9775._1;
                        {
                          const $t15571_i3851_i9781 = (() => {
                            {
                              const $t15570_i3850_i9780 = (() => {
                                {
                                  const $t15568_i3848_i9778 = march_int_and(hi_i3843_i9773, 1048575);
                                  return ($t15568_i3848_i9778 * 4294967296);
                                }
                              })();
                              return ($t15570_i3850_i9780 + lo_i3846_i9776);
                            }
                          })();
                          return { _0: $t15571_i3851_i9781, _1: rng3_i3847_i9777 };
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
          const s_i9783 = $p28430_i9782._0;
          return s_i9783;
        }
      }
    })();
    {
      const $t28438 = game.best;
      {
        const $t28439 = game.runs;
        {
          const $t28440 = game.view_w;
          {
            const $t28441 = game.view_h;
            return Perihelion$Core$fresh_run($t28437, $t28438, $t28439, $t28440, $t28441);
          }
        }
      }
    }
  }
}
const Perihelion$Core$reset$clo = { _0: ($_, game) => Perihelion$Core$reset(game) };

function Perihelion$Core$encode_run(r) {
  {
    const $t28448 = (() => {
      {
        const $t28447 = (() => {
          {
            const $t28444 = (() => {
              {
                const $t28443 = (() => {
                  {
                    const $t28442 = r.score;
                    return String($t28442);
                  }
                })();
                {
                  const $rc_826 = ($t28443 + ":");
                  return $rc_826;
                }
              }
            })();
            {
              const $t28446 = (() => {
                {
                  const $t28445 = r.stars;
                  return String($t28445);
                }
              })();
              {
                const $rc_825 = ($t28444 + $t28446);
                return $rc_825;
              }
            }
          }
        })();
        {
          const $rc_824 = ($t28447 + ":");
          return $rc_824;
        }
      }
    })();
    {
      const $t28450 = (() => {
        {
          const $t28449 = r.max_mult;
          return String($t28449);
        }
      })();
      {
        const $rc_823 = ($t28448 + $t28450);
        return $rc_823;
      }
    }
  }
}
const Perihelion$Core$encode_run$clo = { _0: ($_, r) => Perihelion$Core$encode_run(r) };

function Perihelion$Core$encode_save(best, runs) {
  {
    const $t28452 = (() => {
      {
        const $t28451 = String(best);
        {
          const $rc_828 = ($t28451 + "|");
          return $rc_828;
        }
      }
    })();
    {
      const $t28456 = (() => {
        {
          const $t28454 = { $: "$Clo_$lam28453$3733", _0: $lam28453$apply$3733 };
          {
            const $t28455 = (() => {
              {
                const f_i3855 = $t28454;
                {
                  const go_i3856 = { $: "$Clo_go$4749", _0: go$apply$4749, _1: f_i3855 };
                  {
                    const $t267_i3857 = { $: "Nil" };
                    return go$apply$4749(go_i3856, runs, $t267_i3857);
                  }
                }
              }
            })();
            return march_string_join($t28455, ";");
          }
        }
      })();
      {
        const $rc_827 = ($t28452 + $t28456);
        return $rc_827;
      }
    }
  }
}
const Perihelion$Core$encode_save$clo = { _0: ($_, best, runs) => Perihelion$Core$encode_save(best, runs) };

function Perihelion$Core$decode_run(s) {
  {
    const $t28457 = march_string_split(s, ":");
    switch ($t28457.$) {
      case "Cons": {
        const $f28465 = $t28457._0;
        const $f28466 = $t28457._1;
        {
          const $jp_clo28468 = { $: "$Clo_$jp28467$3734", _0: $jp28467$apply$3734 };
          {
            const $jp_clo28472 = { $: "$Clo_$jp28471$3735", _0: $jp28471$apply$3735$clo, _1: $jp_clo28468 };
            switch ($f28466.$) {
              case "Cons": {
                const $f28473 = $f28466._0;
                const $f28474 = $f28466._1;
                {
                  const $jp_clo28476 = { $: "$Clo_$jp28475$3737", _0: $jp28475$apply$3737, _1: $jp_clo28472 };
                  {
                    const $jp_clo28480 = { $: "$Clo_$jp28479$3738", _0: $jp28479$apply$3738, _1: $jp_clo28476 };
                    switch ($f28474.$) {
                      case "Cons": {
                        const $f28481 = $f28474._0;
                        const $f28482 = $f28474._1;
                        {
                          const $jp_clo28484 = { $: "$Clo_$jp28483$3740", _0: $jp28483$apply$3740, _1: $jp_clo28480 };
                          {
                            const $jp_clo28488 = { $: "$Clo_$jp28487$3741", _0: $jp28487$apply$3741, _1: $jp_clo28484 };
                            switch ($f28482.$) {
                              case "Nil": {
                                {
                                  const c = $f28481;
                                  {
                                    const b = $f28473;
                                    {
                                      const a = $f28465;
                                      {
                                        const $t28458 = (() => {
                                          {
                                            const $rc_831 = march_string_to_int(a);
                                            return $rc_831;
                                          }
                                        })();
                                        switch ($t28458.$) {
                                          case "None": {
                                            return { $: "None" };
                                            break;
                                          }
                                          case "Some": {
                                            const $f28464 = $t28458._0;
                                            {
                                              const score = $f28464;
                                              {
                                                const $t28459 = (() => {
                                                  {
                                                    const $rc_830 = march_string_to_int(b);
                                                    return $rc_830;
                                                  }
                                                })();
                                                switch ($t28459.$) {
                                                  case "None": {
                                                    return { $: "None" };
                                                    break;
                                                  }
                                                  case "Some": {
                                                    const $f28463 = $t28459._0;
                                                    {
                                                      const stars = $f28463;
                                                      {
                                                        const $t28460 = (() => {
                                                          {
                                                            const $rc_829 = march_string_to_int(c);
                                                            return $rc_829;
                                                          }
                                                        })();
                                                        switch ($t28460.$) {
                                                          case "None": {
                                                            return { $: "None" };
                                                            break;
                                                          }
                                                          case "Some": {
                                                            const $f28462 = $t28460._0;
                                                            {
                                                              const mm = $f28462;
                                                              {
                                                                const $t28461 = ({ score: score, stars: stars, max_mult: mm });
                                                                return { $: "Some", _0: $t28461 };
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
                                break;
                              }
                              default: {
                                return $jp28487$apply$3741($jp_clo28488);
                              }
                            }
                          }
                        }
                        break;
                      }
                      default: {
                        return $jp28479$apply$3738($jp_clo28480);
                      }
                    }
                  }
                }
                break;
              }
              default: {
                return $jp28471$apply$3735($jp_clo28472);
              }
            }
          }
        }
        break;
      }
      default: {
        return { $: "None" };
      }
    }
  }
}
const Perihelion$Core$decode_run$clo = { _0: ($_, s) => Perihelion$Core$decode_run(s) };

function Perihelion$Core$decode_runs(parts, acc) {
  switch (parts.$) {
    case "Nil": {
      {
        const $t28491 = (() => {
          {
            const go_i3865 = { $: "$Clo_go$4751", _0: go$apply$4751 };
            {
              const $t250_i3866 = { $: "Nil" };
              return go$apply$4751(go_i3865, acc, $t250_i3866);
            }
          }
        })();
        return { $: "Some", _0: $t28491 };
      }
      break;
    }
    case "Cons": {
      const $f28495 = parts._0;
      const $f28496 = parts._1;
      {
        const rest = $f28496;
        {
          const p = $f28495;
          {
            const $t28492 = (() => {
              {
                const $rc_832 = Perihelion$Core$decode_run(p);
                return $rc_832;
              }
            })();
            switch ($t28492.$) {
              case "None": {
                return { $: "None" };
                break;
              }
              case "Some": {
                const $f28494 = $t28492._0;
                {
                  const r = $f28494;
                  {
                    const $t28493 = { $: "Cons", _0: r, _1: acc };
                    return Perihelion$Core$decode_runs(rest, $t28493);
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
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Perihelion$Core$decode_runs$clo = { _0: ($_, parts, acc) => Perihelion$Core$decode_runs(parts, acc) };

function Perihelion$Core$decode_save(s) {
  {
    const zero = (() => {
      {
        const $t28501 = { $: "Nil" };
        return { _0: 0, _1: $t28501 };
      }
    })();
    {
      const $t28502 = march_string_split(s, "|");
      switch ($t28502.$) {
        case "Cons": {
          const $f28512 = $t28502._0;
          const $f28513 = $t28502._1;
          switch ($f28513.$) {
            case "Cons": {
              const $f28514 = $f28513._0;
              const $f28515 = $f28513._1;
              switch ($f28515.$) {
                case "Nil": {
                  {
                    const runs_s = $f28514;
                    {
                      const best_s = $f28512;
                      {
                        const $t28503 = (() => {
                          {
                            const $rc_834 = march_string_to_int(best_s);
                            return $rc_834;
                          }
                        })();
                        switch ($t28503.$) {
                          case "None": {
                            return zero;
                            break;
                          }
                          case "Some": {
                            const $f28511 = $t28503._0;
                            {
                              const best = $f28511;
                              if (runs_s === "") {
                                return (() => {
                                  {
                                    const $t28504 = { $: "Nil" };
                                    return { _0: best, _1: $t28504 };
                                  }
                                })();
                              } else {
                                return (() => {
                                  {
                                    const $t28507 = (() => {
                                      {
                                        const $t28505 = (() => {
                                          {
                                            const $rc_833 = march_string_split(runs_s, ";");
                                            return $rc_833;
                                          }
                                        })();
                                        {
                                          const $t28506 = { $: "Nil" };
                                          return Perihelion$Core$decode_runs($t28505, $t28506);
                                        }
                                      }
                                    })();
                                    switch ($t28507.$) {
                                      case "None": {
                                        return zero;
                                        break;
                                      }
                                      case "Some": {
                                        const $f28508 = $t28507._0;
                                        {
                                          const rs = $f28508;
                                          return { _0: best, _1: rs };
                                        }
                                        break;
                                      }
                                      default: {
                                        return (() => { throw new Error("non-exhaustive pattern match"); })();
                                      }
                                    }
                                  }
                                })();
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
                  break;
                }
                default: {
                  return zero;
                }
              }
              break;
            }
            default: {
              return zero;
            }
          }
          break;
        }
        default: {
          return zero;
        }
      }
    }
  }
}
const Perihelion$Core$decode_save$clo = { _0: ($_, s) => Perihelion$Core$decode_save(s) };

function Perihelion$Level$make_orbits(outer_r, outer_sp, n) {
  if (n === 1) {
    return (() => {
      {
        const $t28521 = ({ radius: outer_r, speed_mult: outer_sp });
        {
          const $t28522 = { $: "Nil" };
          return { $: "Cons", _0: $t28521, _1: $t28522 };
        }
      }
    })();
  } else if (n === 2) {
    return (() => {
      {
        const $t28525 = (() => {
          {
            const $t28523 = (outer_r * 0.6);
            {
              const $t28524 = (outer_sp * 1.5);
              return ({ radius: $t28523, speed_mult: $t28524 });
            }
          }
        })();
        {
          const $t28526 = ({ radius: outer_r, speed_mult: outer_sp });
          {
            const $t28527 = { $: "Nil" };
            {
              const $t28528 = { $: "Cons", _0: $t28526, _1: $t28527 };
              return { $: "Cons", _0: $t28525, _1: $t28528 };
            }
          }
        }
      }
    })();
  } else {
    return (() => {
      {
        const $t28531 = (() => {
          {
            const $t28529 = (outer_r * 0.5);
            {
              const $t28530 = (outer_sp * 1.8);
              return ({ radius: $t28529, speed_mult: $t28530 });
            }
          }
        })();
        {
          const $t28534 = (() => {
            {
              const $t28532 = (outer_r * 0.75);
              {
                const $t28533 = (outer_sp * 1.35);
                return ({ radius: $t28532, speed_mult: $t28533 });
              }
            }
          })();
          {
            const $t28535 = ({ radius: outer_r, speed_mult: outer_sp });
            {
              const $t28536 = { $: "Nil" };
              {
                const $t28537 = { $: "Cons", _0: $t28535, _1: $t28536 };
                {
                  const $t28538 = { $: "Cons", _0: $t28534, _1: $t28537 };
                  return { $: "Cons", _0: $t28531, _1: $t28538 };
                }
              }
            }
          }
        }
      }
    })();
  }
}
const Perihelion$Level$make_orbits$clo = { _0: ($_, outer_r, outer_sp, n) => Perihelion$Level$make_orbits(outer_r, outer_sp, n) };

function Perihelion$Level$next_star(rng, prev, view_w) {
  {
    const $p28568 = (() => {
      {
        const $p28516_i10163 = (() => {
          {
            const $p15576_i9795_i10158 = (() => {
              {
                const $p15573_i1532_i9785_i10149 = Random$next_raw(rng);
                {
                  const hi_i1533_i9786_i10150 = $p15573_i1532_i9785_i10149._0;
                  {
                    const rng2_i1534_i9787_i10151 = $p15573_i1532_i9785_i10149._1;
                    {
                      const $p15572_i1535_i9788_i10152 = Random$next_raw(rng2_i1534_i9787_i10151);
                      {
                        const lo_i1536_i9789_i10153 = $p15572_i1535_i9788_i10152._0;
                        {
                          const rng3_i1537_i9790_i10154 = $p15572_i1535_i9788_i10152._1;
                          {
                            const $t15571_i1541_i9794_i10157 = (() => {
                              {
                                const $t15570_i1540_i9793_i10156 = (() => {
                                  {
                                    const $t15568_i1538_i9791_i10155 = march_int_and(hi_i1533_i9786_i10150, 1048575);
                                    return ($t15568_i1538_i9791_i10155 * 4294967296);
                                  }
                                })();
                                return ($t15570_i1540_i9793_i10156 + lo_i1536_i9789_i10153);
                              }
                            })();
                            return { _0: $t15571_i1541_i9794_i10157, _1: rng3_i1537_i9790_i10154 };
                          }
                        }
                      }
                    }
                  }
                }
              }
            })();
            {
              const bits_i9796_i10159 = $p15576_i9795_i10158._0;
              {
                const rng2_i9797_i10160 = $p15576_i9795_i10158._1;
                {
                  const $t15575_i9799_i10162 = (() => {
                    {
                      const $t15574_i9798_i10161 = bits_i9796_i10159;
                      return ($t15574_i9798_i10161 / 4.50359962737e+15);
                    }
                  })();
                  return { _0: $t15575_i9799_i10162, _1: rng2_i9797_i10160 };
                }
              }
            }
          }
        })();
        {
          const t_i10164 = $p28516_i10163._0;
          {
            const rng2_i10165 = $p28516_i10163._1;
            {
              const out_i10166 = { _0: rng2_i10165, _1: t_i10164 };
              return out_i10166;
            }
          }
        }
      }
    })();
    {
      const r1 = $p28568._0;
      {
        const ty = $p28568._1;
        {
          const $p28567 = (() => {
            {
              const $p28516_i10144 = (() => {
                {
                  const $p15576_i9795_i10139 = (() => {
                    {
                      const $p15573_i1532_i9785_i10130 = Random$next_raw(r1);
                      {
                        const hi_i1533_i9786_i10131 = $p15573_i1532_i9785_i10130._0;
                        {
                          const rng2_i1534_i9787_i10132 = $p15573_i1532_i9785_i10130._1;
                          {
                            const $p15572_i1535_i9788_i10133 = Random$next_raw(rng2_i1534_i9787_i10132);
                            {
                              const lo_i1536_i9789_i10134 = $p15572_i1535_i9788_i10133._0;
                              {
                                const rng3_i1537_i9790_i10135 = $p15572_i1535_i9788_i10133._1;
                                {
                                  const $t15571_i1541_i9794_i10138 = (() => {
                                    {
                                      const $t15570_i1540_i9793_i10137 = (() => {
                                        {
                                          const $t15568_i1538_i9791_i10136 = march_int_and(hi_i1533_i9786_i10131, 1048575);
                                          return ($t15568_i1538_i9791_i10136 * 4294967296);
                                        }
                                      })();
                                      return ($t15570_i1540_i9793_i10137 + lo_i1536_i9789_i10134);
                                    }
                                  })();
                                  return { _0: $t15571_i1541_i9794_i10138, _1: rng3_i1537_i9790_i10135 };
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  })();
                  {
                    const bits_i9796_i10140 = $p15576_i9795_i10139._0;
                    {
                      const rng2_i9797_i10141 = $p15576_i9795_i10139._1;
                      {
                        const $t15575_i9799_i10143 = (() => {
                          {
                            const $t15574_i9798_i10142 = bits_i9796_i10140;
                            return ($t15574_i9798_i10142 / 4.50359962737e+15);
                          }
                        })();
                        return { _0: $t15575_i9799_i10143, _1: rng2_i9797_i10141 };
                      }
                    }
                  }
                }
              })();
              {
                const t_i10145 = $p28516_i10144._0;
                {
                  const rng2_i10146 = $p28516_i10144._1;
                  {
                    const out_i10147 = { _0: rng2_i10146, _1: t_i10145 };
                    return out_i10147;
                  }
                }
              }
            }
          })();
          {
            const r2 = $p28567._0;
            {
              const tx = $p28567._1;
              {
                const $p28566 = (() => {
                  {
                    const $p28516_i10125 = (() => {
                      {
                        const $p15576_i9795_i10120 = (() => {
                          {
                            const $p15573_i1532_i9785_i10111 = Random$next_raw(r2);
                            {
                              const hi_i1533_i9786_i10112 = $p15573_i1532_i9785_i10111._0;
                              {
                                const rng2_i1534_i9787_i10113 = $p15573_i1532_i9785_i10111._1;
                                {
                                  const $p15572_i1535_i9788_i10114 = Random$next_raw(rng2_i1534_i9787_i10113);
                                  {
                                    const lo_i1536_i9789_i10115 = $p15572_i1535_i9788_i10114._0;
                                    {
                                      const rng3_i1537_i9790_i10116 = $p15572_i1535_i9788_i10114._1;
                                      {
                                        const $t15571_i1541_i9794_i10119 = (() => {
                                          {
                                            const $t15570_i1540_i9793_i10118 = (() => {
                                              {
                                                const $t15568_i1538_i9791_i10117 = march_int_and(hi_i1533_i9786_i10112, 1048575);
                                                return ($t15568_i1538_i9791_i10117 * 4294967296);
                                              }
                                            })();
                                            return ($t15570_i1540_i9793_i10118 + lo_i1536_i9789_i10115);
                                          }
                                        })();
                                        return { _0: $t15571_i1541_i9794_i10119, _1: rng3_i1537_i9790_i10116 };
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        })();
                        {
                          const bits_i9796_i10121 = $p15576_i9795_i10120._0;
                          {
                            const rng2_i9797_i10122 = $p15576_i9795_i10120._1;
                            {
                              const $t15575_i9799_i10124 = (() => {
                                {
                                  const $t15574_i9798_i10123 = bits_i9796_i10121;
                                  return ($t15574_i9798_i10123 / 4.50359962737e+15);
                                }
                              })();
                              return { _0: $t15575_i9799_i10124, _1: rng2_i9797_i10122 };
                            }
                          }
                        }
                      }
                    })();
                    {
                      const t_i10126 = $p28516_i10125._0;
                      {
                        const rng2_i10127 = $p28516_i10125._1;
                        {
                          const out_i10128 = { _0: rng2_i10127, _1: t_i10126 };
                          return out_i10128;
                        }
                      }
                    }
                  }
                })();
                {
                  const r3 = $p28566._0;
                  {
                    const tr = $p28566._1;
                    {
                      const $p28565 = (() => {
                        {
                          const $p28516_i10106 = (() => {
                            {
                              const $p15576_i9795_i10101 = (() => {
                                {
                                  const $p15573_i1532_i9785_i10092 = Random$next_raw(r3);
                                  {
                                    const hi_i1533_i9786_i10093 = $p15573_i1532_i9785_i10092._0;
                                    {
                                      const rng2_i1534_i9787_i10094 = $p15573_i1532_i9785_i10092._1;
                                      {
                                        const $p15572_i1535_i9788_i10095 = Random$next_raw(rng2_i1534_i9787_i10094);
                                        {
                                          const lo_i1536_i9789_i10096 = $p15572_i1535_i9788_i10095._0;
                                          {
                                            const rng3_i1537_i9790_i10097 = $p15572_i1535_i9788_i10095._1;
                                            {
                                              const $t15571_i1541_i9794_i10100 = (() => {
                                                {
                                                  const $t15570_i1540_i9793_i10099 = (() => {
                                                    {
                                                      const $t15568_i1538_i9791_i10098 = march_int_and(hi_i1533_i9786_i10093, 1048575);
                                                      return ($t15568_i1538_i9791_i10098 * 4294967296);
                                                    }
                                                  })();
                                                  return ($t15570_i1540_i9793_i10099 + lo_i1536_i9789_i10096);
                                                }
                                              })();
                                              return { _0: $t15571_i1541_i9794_i10100, _1: rng3_i1537_i9790_i10097 };
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              })();
                              {
                                const bits_i9796_i10102 = $p15576_i9795_i10101._0;
                                {
                                  const rng2_i9797_i10103 = $p15576_i9795_i10101._1;
                                  {
                                    const $t15575_i9799_i10105 = (() => {
                                      {
                                        const $t15574_i9798_i10104 = bits_i9796_i10102;
                                        return ($t15574_i9798_i10104 / 4.50359962737e+15);
                                      }
                                    })();
                                    return { _0: $t15575_i9799_i10105, _1: rng2_i9797_i10103 };
                                  }
                                }
                              }
                            }
                          })();
                          {
                            const t_i10107 = $p28516_i10106._0;
                            {
                              const rng2_i10108 = $p28516_i10106._1;
                              {
                                const out_i10109 = { _0: rng2_i10108, _1: t_i10107 };
                                return out_i10109;
                              }
                            }
                          }
                        }
                      })();
                      {
                        const r4 = $p28565._0;
                        {
                          const tcm = $p28565._1;
                          {
                            const $p28564 = (() => {
                              {
                                const $p28516_i10087 = (() => {
                                  {
                                    const $p15576_i9795_i10082 = (() => {
                                      {
                                        const $p15573_i1532_i9785_i10073 = Random$next_raw(r4);
                                        {
                                          const hi_i1533_i9786_i10074 = $p15573_i1532_i9785_i10073._0;
                                          {
                                            const rng2_i1534_i9787_i10075 = $p15573_i1532_i9785_i10073._1;
                                            {
                                              const $p15572_i1535_i9788_i10076 = Random$next_raw(rng2_i1534_i9787_i10075);
                                              {
                                                const lo_i1536_i9789_i10077 = $p15572_i1535_i9788_i10076._0;
                                                {
                                                  const rng3_i1537_i9790_i10078 = $p15572_i1535_i9788_i10076._1;
                                                  {
                                                    const $t15571_i1541_i9794_i10081 = (() => {
                                                      {
                                                        const $t15570_i1540_i9793_i10080 = (() => {
                                                          {
                                                            const $t15568_i1538_i9791_i10079 = march_int_and(hi_i1533_i9786_i10074, 1048575);
                                                            return ($t15568_i1538_i9791_i10079 * 4294967296);
                                                          }
                                                        })();
                                                        return ($t15570_i1540_i9793_i10080 + lo_i1536_i9789_i10077);
                                                      }
                                                    })();
                                                    return { _0: $t15571_i1541_i9794_i10081, _1: rng3_i1537_i9790_i10078 };
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    })();
                                    {
                                      const bits_i9796_i10083 = $p15576_i9795_i10082._0;
                                      {
                                        const rng2_i9797_i10084 = $p15576_i9795_i10082._1;
                                        {
                                          const $t15575_i9799_i10086 = (() => {
                                            {
                                              const $t15574_i9798_i10085 = bits_i9796_i10083;
                                              return ($t15574_i9798_i10085 / 4.50359962737e+15);
                                            }
                                          })();
                                          return { _0: $t15575_i9799_i10086, _1: rng2_i9797_i10084 };
                                        }
                                      }
                                    }
                                  }
                                })();
                                {
                                  const t_i10088 = $p28516_i10087._0;
                                  {
                                    const rng2_i10089 = $p28516_i10087._1;
                                    {
                                      const out_i10090 = { _0: rng2_i10089, _1: t_i10088 };
                                      return out_i10090;
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const r5 = $p28564._0;
                              {
                                const tsm = $p28564._1;
                                {
                                  const $p28563 = (() => {
                                    {
                                      const $p28516_i10068 = (() => {
                                        {
                                          const $p15576_i9795_i10063 = (() => {
                                            {
                                              const $p15573_i1532_i9785_i10054 = Random$next_raw(r5);
                                              {
                                                const hi_i1533_i9786_i10055 = $p15573_i1532_i9785_i10054._0;
                                                {
                                                  const rng2_i1534_i9787_i10056 = $p15573_i1532_i9785_i10054._1;
                                                  {
                                                    const $p15572_i1535_i9788_i10057 = Random$next_raw(rng2_i1534_i9787_i10056);
                                                    {
                                                      const lo_i1536_i9789_i10058 = $p15572_i1535_i9788_i10057._0;
                                                      {
                                                        const rng3_i1537_i9790_i10059 = $p15572_i1535_i9788_i10057._1;
                                                        {
                                                          const $t15571_i1541_i9794_i10062 = (() => {
                                                            {
                                                              const $t15570_i1540_i9793_i10061 = (() => {
                                                                {
                                                                  const $t15568_i1538_i9791_i10060 = march_int_and(hi_i1533_i9786_i10055, 1048575);
                                                                  return ($t15568_i1538_i9791_i10060 * 4294967296);
                                                                }
                                                              })();
                                                              return ($t15570_i1540_i9793_i10061 + lo_i1536_i9789_i10058);
                                                            }
                                                          })();
                                                          return { _0: $t15571_i1541_i9794_i10062, _1: rng3_i1537_i9790_i10059 };
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          })();
                                          {
                                            const bits_i9796_i10064 = $p15576_i9795_i10063._0;
                                            {
                                              const rng2_i9797_i10065 = $p15576_i9795_i10063._1;
                                              {
                                                const $t15575_i9799_i10067 = (() => {
                                                  {
                                                    const $t15574_i9798_i10066 = bits_i9796_i10064;
                                                    return ($t15574_i9798_i10066 / 4.50359962737e+15);
                                                  }
                                                })();
                                                return { _0: $t15575_i9799_i10067, _1: rng2_i9797_i10065 };
                                              }
                                            }
                                          }
                                        }
                                      })();
                                      {
                                        const t_i10069 = $p28516_i10068._0;
                                        {
                                          const rng2_i10070 = $p28516_i10068._1;
                                          {
                                            const out_i10071 = { _0: rng2_i10070, _1: t_i10069 };
                                            return out_i10071;
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const r6 = $p28563._0;
                                    {
                                      const trings = $p28563._1;
                                      {
                                        const gap = (() => {
                                          {
                                            const $t28518_i3906 = (() => {
                                              {
                                                const $t28517_i3905 = (260. - 160.);
                                                return (ty * $t28517_i3905);
                                              }
                                            })();
                                            return (160. + $t28518_i3906);
                                          }
                                        })();
                                        {
                                          const dx = (() => {
                                            {
                                              const $t28546 = (0. - 220.);
                                              {
                                                const $t28518_i3901 = (() => {
                                                  {
                                                    const $t28517_i3900 = (220. - $t28546);
                                                    return (tx * $t28517_i3900);
                                                  }
                                                })();
                                                return ($t28546 + $t28518_i3901);
                                              }
                                            }
                                          })();
                                          {
                                            const x = (() => {
                                              {
                                                const $t28549 = (() => {
                                                  {
                                                    const $t28548 = prev.x;
                                                    return ($t28548 + dx);
                                                  }
                                                })();
                                                {
                                                  const $t28552 = (view_w - 60.);
                                                  {
                                                    const $t1577_i3895 = ($t28549 < 60.);
                                                    if ($t1577_i3895 === true) {
                                                      return 60.;
                                                    } else {
                                                      return (() => {
                                                        {
                                                          const $t1578_i3896 = ($t28549 > $t28552);
                                                          if ($t1578_i3896 === true) {
                                                            return $t28552;
                                                          } else {
                                                            return $t28549;
                                                          }
                                                        }
                                                      })();
                                                    }
                                                  }
                                                }
                                              }
                                            })();
                                            {
                                              const r = (() => {
                                                {
                                                  const $t28555 = (tr * tr);
                                                  {
                                                    const $t28518_i3891 = (() => {
                                                      {
                                                        const $t28517_i3890 = (20. - 8.);
                                                        return ($t28555 * $t28517_i3890);
                                                      }
                                                    })();
                                                    return (8. + $t28518_i3891);
                                                  }
                                                }
                                              })();
                                              {
                                                const cm = (() => {
                                                  {
                                                    const $t28518_i3886 = (() => {
                                                      {
                                                        const $t28517_i3885 = (5.2 - 2.8);
                                                        return (tcm * $t28517_i3885);
                                                      }
                                                    })();
                                                    return (2.8 + $t28518_i3886);
                                                  }
                                                })();
                                                {
                                                  const sm = (() => {
                                                    {
                                                      const $t28518_i3881 = (() => {
                                                        {
                                                          const $t28517_i3880 = (1.6 - 0.7);
                                                          return (tsm * $t28517_i3880);
                                                        }
                                                      })();
                                                      return (0.7 + $t28518_i3881);
                                                    }
                                                  })();
                                                  {
                                                    const cap = (r * cm);
                                                    {
                                                      const $t28560 = (() => {
                                                        {
                                                          const $t28519_i3875 = (trings < 0.55);
                                                          if ($t28519_i3875 === true) {
                                                            return 1;
                                                          } else {
                                                            return (() => {
                                                              {
                                                                const $t28520_i3876 = (trings < 0.85);
                                                                if ($t28520_i3876 === true) {
                                                                  return 2;
                                                                } else {
                                                                  return 3;
                                                                }
                                                              }
                                                            })();
                                                          }
                                                        }
                                                      })();
                                                      {
                                                        const orbits = Perihelion$Level$make_orbits(cap, sm, $t28560);
                                                        {
                                                          const s = (() => {
                                                            {
                                                              const $t28562 = (() => {
                                                                {
                                                                  const $t28561 = prev.y;
                                                                  return ($t28561 - gap);
                                                                }
                                                              })();
                                                              return ({ x: x, y: $t28562, radius: r, capture_radius: cap, speed_mult: sm, orbits: orbits });
                                                            }
                                                          })();
                                                          {
                                                            const result = { _0: s, _1: r6 };
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
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
const Perihelion$Level$next_star$clo = { _0: ($_, rng, prev, view_w) => Perihelion$Level$next_star(rng, prev, view_w) };

function Perihelion$Level$initial_stars(rng, view_w) {
  {
    const first = (() => {
      {
        const $t28569 = (view_w / 2.);
        {
          const $t28570 = ({ radius: 54., speed_mult: 1. });
          {
            const $t28571 = { $: "Nil" };
            {
              const $t28572 = { $: "Cons", _0: $t28570, _1: $t28571 };
              return ({ x: $t28569, y: 520., radius: 18., capture_radius: 54., speed_mult: 1., orbits: $t28572 });
            }
          }
        }
      }
    })();
    {
      const $p28577 = Perihelion$Level$next_star(rng, first, view_w);
      {
        const s2 = $p28577._0;
        {
          const rng2 = $p28577._1;
          {
            const $p28576 = Perihelion$Level$next_star(rng2, s2, view_w);
            {
              const s3 = $p28576._0;
              {
                const rng3 = $p28576._1;
                {
                  const $t28573 = { $: "Nil" };
                  {
                    const $t28574 = { $: "Cons", _0: s3, _1: $t28573 };
                    {
                      const $t28575 = { $: "Cons", _0: s2, _1: $t28574 };
                      {
                        const stars = { $: "Cons", _0: first, _1: $t28575 };
                        {
                          const result = { _0: stars, _1: rng3 };
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
const Perihelion$Level$initial_stars$clo = { _0: ($_, rng, view_w) => Perihelion$Level$initial_stars(rng, view_w) };

function Perihelion$Nebula$star_cloud(sx, sy, seed) {
  {
    const $t28589 = (() => {
      {
        const $t28587 = (() => {
          {
            const x_i9857 = (() => {
              {
                const $t28583_i9856 = (() => {
                  {
                    const $t28582_i9855 = (() => {
                      {
                        const $t28580_i9853 = (() => {
                          {
                            const $t28578_i9851 = (sx * 12.9898);
                            {
                              const $t28579_i9852 = (sy * 78.233);
                              return ($t28578_i9851 + $t28579_i9852);
                            }
                          }
                        })();
                        {
                          const $t28581_i9854 = (seed * 37.719);
                          return ($t28580_i9853 + $t28581_i9854);
                        }
                      }
                    })();
                    return Math.sin($t28582_i9855);
                  }
                })();
                return ($t28583_i9856 * 43758.5453);
              }
            })();
            {
              const $t28584_i9859 = (() => {
                {
                  const $t1579_i3908_i9858 = Math.floor(x_i9857);
                  return $t1579_i3908_i9858;
                }
              })();
              return (x_i9857 - $t28584_i9859);
            }
          }
        })();
        return ($t28587 > 0.55);
      }
    })();
    if ($t28589 === true) {
      return { $: "None" };
    } else {
      return (() => {
        {
          const jx = (() => {
            {
              const $t28593 = (() => {
                {
                  const $t28592 = (() => {
                    {
                      const $t28591 = (() => {
                        {
                          const $t28590 = (sx + 1.);
                          {
                            const x_i9845 = (() => {
                              {
                                const $t28583_i9844 = (() => {
                                  {
                                    const $t28582_i9843 = (() => {
                                      {
                                        const $t28580_i9841 = (() => {
                                          {
                                            const $t28578_i9839 = ($t28590 * 12.9898);
                                            {
                                              const $t28579_i9840 = (sy * 78.233);
                                              return ($t28578_i9839 + $t28579_i9840);
                                            }
                                          }
                                        })();
                                        {
                                          const $t28581_i9842 = (seed * 37.719);
                                          return ($t28580_i9841 + $t28581_i9842);
                                        }
                                      }
                                    })();
                                    return Math.sin($t28582_i9843);
                                  }
                                })();
                                return ($t28583_i9844 * 43758.5453);
                              }
                            })();
                            {
                              const $t28584_i9847 = (() => {
                                {
                                  const $t1579_i3908_i9846 = Math.floor(x_i9845);
                                  return $t1579_i3908_i9846;
                                }
                              })();
                              return (x_i9845 - $t28584_i9847);
                            }
                          }
                        }
                      })();
                      return ($t28591 - 0.5);
                    }
                  })();
                  return ($t28592 * 2.);
                }
              })();
              return ($t28593 * 90.);
            }
          })();
          {
            const jy = (() => {
              {
                const $t28598 = (() => {
                  {
                    const $t28597 = (() => {
                      {
                        const $t28596 = (() => {
                          {
                            const $t28595 = (sy + 1.);
                            {
                              const x_i9833 = (() => {
                                {
                                  const $t28583_i9832 = (() => {
                                    {
                                      const $t28582_i9831 = (() => {
                                        {
                                          const $t28580_i9829 = (() => {
                                            {
                                              const $t28578_i9827 = (sx * 12.9898);
                                              {
                                                const $t28579_i9828 = ($t28595 * 78.233);
                                                return ($t28578_i9827 + $t28579_i9828);
                                              }
                                            }
                                          })();
                                          {
                                            const $t28581_i9830 = (seed * 37.719);
                                            return ($t28580_i9829 + $t28581_i9830);
                                          }
                                        }
                                      })();
                                      return Math.sin($t28582_i9831);
                                    }
                                  })();
                                  return ($t28583_i9832 * 43758.5453);
                                }
                              })();
                              {
                                const $t28584_i9835 = (() => {
                                  {
                                    const $t1579_i3908_i9834 = Math.floor(x_i9833);
                                    return $t1579_i3908_i9834;
                                  }
                                })();
                                return (x_i9833 - $t28584_i9835);
                              }
                            }
                          }
                        })();
                        return ($t28596 - 0.5);
                      }
                    })();
                    return ($t28597 * 2.);
                  }
                })();
                return ($t28598 * 90.);
              }
            })();
            {
              const rt = (() => {
                {
                  const $t28600 = (sx + 2.);
                  {
                    const x_i9821 = (() => {
                      {
                        const $t28583_i9820 = (() => {
                          {
                            const $t28582_i9819 = (() => {
                              {
                                const $t28580_i9817 = (() => {
                                  {
                                    const $t28578_i9815 = ($t28600 * 12.9898);
                                    {
                                      const $t28579_i9816 = (sy * 78.233);
                                      return ($t28578_i9815 + $t28579_i9816);
                                    }
                                  }
                                })();
                                {
                                  const $t28581_i9818 = (seed * 37.719);
                                  return ($t28580_i9817 + $t28581_i9818);
                                }
                              }
                            })();
                            return Math.sin($t28582_i9819);
                          }
                        })();
                        return ($t28583_i9820 * 43758.5453);
                      }
                    })();
                    {
                      const $t28584_i9823 = (() => {
                        {
                          const $t1579_i3908_i9822 = Math.floor(x_i9821);
                          return $t1579_i3908_i9822;
                        }
                      })();
                      return (x_i9821 - $t28584_i9823);
                    }
                  }
                }
              })();
              {
                const r = (() => {
                  {
                    const $t28603 = (rt * rt);
                    {
                      const $t28586_i3914 = (() => {
                        {
                          const $t28585_i3913 = (700. - 240.);
                          return ($t28603 * $t28585_i3913);
                        }
                      })();
                      return (240. + $t28586_i3914);
                    }
                  }
                })();
                {
                  const strength = (() => {
                    {
                      const $t28606 = (() => {
                        {
                          const $t28605 = (() => {
                            {
                              const $t28604 = (sy + 2.);
                              {
                                const x_i9809 = (() => {
                                  {
                                    const $t28583_i9808 = (() => {
                                      {
                                        const $t28582_i9807 = (() => {
                                          {
                                            const $t28580_i9805 = (() => {
                                              {
                                                const $t28578_i9803 = (sx * 12.9898);
                                                {
                                                  const $t28579_i9804 = ($t28604 * 78.233);
                                                  return ($t28578_i9803 + $t28579_i9804);
                                                }
                                              }
                                            })();
                                            {
                                              const $t28581_i9806 = (seed * 37.719);
                                              return ($t28580_i9805 + $t28581_i9806);
                                            }
                                          }
                                        })();
                                        return Math.sin($t28582_i9807);
                                      }
                                    })();
                                    return ($t28583_i9808 * 43758.5453);
                                  }
                                })();
                                {
                                  const $t28584_i9811 = (() => {
                                    {
                                      const $t1579_i3908_i9810 = Math.floor(x_i9809);
                                      return $t1579_i3908_i9810;
                                    }
                                  })();
                                  return (x_i9809 - $t28584_i9811);
                                }
                              }
                            }
                          })();
                          return (0.65 * $t28605);
                        }
                      })();
                      return (0.35 + $t28606);
                    }
                  })();
                  {
                    const $t28609 = (() => {
                      {
                        const $t28607 = (sx + jx);
                        {
                          const $t28608 = (sy + jy);
                          return ({ x: $t28607, y: $t28608, radius: r, strength: strength });
                        }
                      }
                    })();
                    return { $: "Some", _0: $t28609 };
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
const Perihelion$Nebula$star_cloud$clo = { _0: ($_, sx, sy, seed) => Perihelion$Nebula$star_cloud(sx, sy, seed) };

function Perihelion$Nebula$collect_star_clouds(stars, seed, acc) {
  switch (stars.$) {
    case "Nil": {
      return acc;
      break;
    }
    case "Cons": {
      const $f28642 = stars._0;
      const $f28643 = stars._1;
      {
        const rest = $f28643;
        {
          const s = $f28642;
          {
            const $t28640 = (() => {
              {
                const $t28638 = s.x;
                {
                  const $t28639 = s.y;
                  return Perihelion$Nebula$star_cloud($t28638, $t28639, seed);
                }
              }
            })();
            {
              let acc2;
              switch ($t28640.$) {
                case "None": {
                  acc2 = acc;
                  break;
                }
                case "Some": {
                  const $f28641 = $t28640._0;
                  acc2 = (() => {
                    {
                      const c = $f28641;
                      return { $: "Cons", _0: c, _1: acc };
                    }
                  })();
                  break;
                }
                default: {
                  acc2 = (() => {
                    return (() => { throw new Error("non-exhaustive pattern match"); })();
                  })();
                  break;
                }
              }
              return Perihelion$Nebula$collect_star_clouds(rest, seed, acc2);
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
const Perihelion$Nebula$collect_star_clouds$clo = { _0: ($_, stars, seed, acc) => Perihelion$Nebula$collect_star_clouds(stars, seed, acc) };

function Perihelion$Nebula$filter_visible(stars, cam_y, view_h, margin, acc) {
  switch (stars.$) {
    case "Nil": {
      return acc;
      break;
    }
    case "Cons": {
      const $f28656 = stars._0;
      const $f28657 = stars._1;
      {
        const rest = $f28657;
        {
          const s = $f28656;
          {
            const $t28655 = (() => {
              {
                const $t28650_i3933 = (() => {
                  {
                    const $t28648_i3931 = s.y;
                    {
                      const $t28649_i3932 = (cam_y - margin);
                      return ($t28648_i3931 >= $t28649_i3932);
                    }
                  }
                })();
                {
                  const $t28654_i3937 = (() => {
                    {
                      const $t28651_i3934 = s.y;
                      {
                        const $t28653_i3936 = (() => {
                          {
                            const $t28652_i3935 = (cam_y + view_h);
                            return ($t28652_i3935 + margin);
                          }
                        })();
                        return ($t28651_i3934 <= $t28653_i3936);
                      }
                    }
                  })();
                  return ($t28650_i3933 && $t28654_i3937);
                }
              }
            })();
            {
              let acc2;
              if ($t28655 === true) {
                acc2 = { $: "Cons", _0: s, _1: acc };
              } else {
                acc2 = acc;
              }
              return Perihelion$Nebula$filter_visible(rest, cam_y, view_h, margin, acc2);
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
const Perihelion$Nebula$filter_visible$clo = { _0: ($_, stars, cam_y, view_h, margin, acc) => Perihelion$Nebula$filter_visible(stars, cam_y, view_h, margin, acc) };

function boot_seed() {
  {
    const $t28669 = (() => {
      {
        const $t28668 = (() => {
          {
            const $t28667 = {  };
            return march_unix_time();
          }
        })();
        return ($t28668 * 1000000.);
      }
    })();
    return Math.trunc($t28669);
  }
}
const boot_seed$clo = { _0: ($_) => boot_seed() };

function spawn_burst_particles(x, y, t, i, acc) {
  {
    const $t28680 = (i >= 10);
    if ($t28680 === true) {
      return acc;
    } else {
      return (() => {
        {
          const seed = (() => {
            {
              const $t28682 = (() => {
                {
                  const $t28681 = i;
                  return ($t28681 * 7.);
                }
              })();
              return (t + $t28682);
            }
          })();
          {
            const a = (() => {
              {
                const $t28683 = (() => {
                  {
                    const x_i9884 = (() => {
                      {
                        const $t28677_i9883 = (() => {
                          {
                            const $t28676_i9882 = (() => {
                              {
                                const $t28674_i9880 = (seed * 12.9898);
                                {
                                  const $t28675_i9881 = (1. * 78.233);
                                  return ($t28674_i9880 + $t28675_i9881);
                                }
                              }
                            })();
                            return Math.sin($t28676_i9882);
                          }
                        })();
                        return ($t28677_i9883 * 43758.5453);
                      }
                    })();
                    {
                      const $t28678_i9886 = (() => {
                        {
                          const $t1579_i3939_i9885 = Math.floor(x_i9884);
                          return $t1579_i3939_i9885;
                        }
                      })();
                      return (x_i9884 - $t28678_i9886);
                    }
                  }
                })();
                return ($t28683 * 6.28318530718);
              }
            })();
            {
              const speed = (() => {
                {
                  const $t28686 = (() => {
                    {
                      const $t28685 = (() => {
                        {
                          const x_i9875 = (() => {
                            {
                              const $t28677_i9874 = (() => {
                                {
                                  const $t28676_i9873 = (() => {
                                    {
                                      const $t28674_i9871 = (seed * 12.9898);
                                      {
                                        const $t28675_i9872 = (2. * 78.233);
                                        return ($t28674_i9871 + $t28675_i9872);
                                      }
                                    }
                                  })();
                                  return Math.sin($t28676_i9873);
                                }
                              })();
                              return ($t28677_i9874 * 43758.5453);
                            }
                          })();
                          {
                            const $t28678_i9877 = (() => {
                              {
                                const $t1579_i3939_i9876 = Math.floor(x_i9875);
                                return $t1579_i3939_i9876;
                              }
                            })();
                            return (x_i9875 - $t28678_i9877);
                          }
                        }
                      })();
                      return ($t28685 * 90.);
                    }
                  })();
                  return (40. + $t28686);
                }
              })();
              {
                const life = (() => {
                  {
                    const $t28690 = (() => {
                      {
                        const $t28689 = (() => {
                          {
                            const $t28688 = (() => {
                              {
                                const x_i9866 = (() => {
                                  {
                                    const $t28677_i9865 = (() => {
                                      {
                                        const $t28676_i9864 = (() => {
                                          {
                                            const $t28674_i9862 = (seed * 12.9898);
                                            {
                                              const $t28675_i9863 = (3. * 78.233);
                                              return ($t28674_i9862 + $t28675_i9863);
                                            }
                                          }
                                        })();
                                        return Math.sin($t28676_i9864);
                                      }
                                    })();
                                    return ($t28677_i9865 * 43758.5453);
                                  }
                                })();
                                {
                                  const $t28678_i9868 = (() => {
                                    {
                                      const $t1579_i3939_i9867 = Math.floor(x_i9866);
                                      return $t1579_i3939_i9867;
                                    }
                                  })();
                                  return (x_i9866 - $t28678_i9868);
                                }
                              }
                            })();
                            return (0.4 * $t28688);
                          }
                        })();
                        return (0.6 + $t28689);
                      }
                    })();
                    return (0.5 * $t28690);
                  }
                })();
                {
                  const p = (() => {
                    {
                      const $t28692 = (() => {
                        {
                          const $t28691 = Math.cos(a);
                          return ($t28691 * speed);
                        }
                      })();
                      {
                        const $t28694 = (() => {
                          {
                            const $t28693 = Math.sin(a);
                            return ($t28693 * speed);
                          }
                        })();
                        return ({ x: x, y: y, vx: $t28692, vy: $t28694, life: life, max_life: life });
                      }
                    }
                  })();
                  {
                    const $t28695 = (i + 1);
                    {
                      const $t28696 = { $: "Cons", _0: p, _1: acc };
                      return spawn_burst_particles(x, y, t, $t28695, $t28696);
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
const spawn_burst_particles$clo = { _0: ($_, x, y, t, i, acc) => spawn_burst_particles(x, y, t, i, acc) };

function spawn_bursts(bursts, t, acc) {
  switch (bursts.$) {
    case "Nil": {
      return acc;
      break;
    }
    case "Cons": {
      const $f28699 = bursts._0;
      const $f28700 = bursts._1;
      {
        const rest = (() => {
          return $f28700;
        })();
        {
          const pt = (() => {
            return $f28699;
          })();
          {
            const x = pt._0;
            {
              const y = pt._1;
              {
                const $t28697 = spawn_burst_particles(x, y, t, 0, acc);
                return spawn_bursts(rest, t, $t28697);
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
const spawn_bursts$clo = { _0: ($_, bursts, t, acc) => spawn_bursts(bursts, t, acc) };

function step_flash(flash, dt_s) {
  switch (flash.$) {
    case "None": {
      return { $: "None" };
      break;
    }
    case "Some": {
      const $f28726 = flash._0;
      {
        const f = $f28726;
        {
          const x = f._0;
          {
            const y = f._1;
            {
              const tr = f._2;
              {
                const tr2 = (tr - dt_s);
                {
                  const $t28723 = (tr2 > 0.);
                  if ($t28723 === true) {
                    return (() => {
                      {
                        const $t28724 = { _0: x, _1: y, _2: tr2 };
                        return { $: "Some", _0: $t28724 };
                      }
                    })();
                  } else {
                    return { $: "None" };
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
const step_flash$clo = { _0: ($_, flash, dt_s) => step_flash(flash, dt_s) };

function step_fx(fx, game, dt_s) {
  {
    const t2 = (() => {
      {
        const $t28727 = fx.t;
        return ($t28727 + dt_s);
      }
    })();
    {
      const $t28728 = (() => {
        {
          const $t29202_i3959 = game.phase;
          switch ($t29202_i3959.$) {
            case "Playing": {
              return true;
              break;
            }
            default: {
              return false;
            }
          }
        }
      })();
      {
        let trail2;
        if ($t28728 === true) {
          trail2 = (() => {
            {
              const $t28729 = fx.trail;
              {
                const $t28732 = (() => {
                  {
                    const $t28730 = game.ball_x;
                    {
                      const $t28731 = game.ball_y;
                      return { _0: $t28730, _1: $t28731 };
                    }
                  }
                })();
                {
                  const $t28721_i9900 = { $: "Cons", _0: $t28732, _1: $t28729 };
                  {
                    const go_i3954_i9901 = { $: "$Clo_go$4757", _0: go$apply$4757 };
                    {
                      const $t505_i3955_i9902 = { $: "Nil" };
                      return go$apply$4757(go_i3954_i9901, $t28721_i9900, 14, $t505_i3955_i9902);
                    }
                  }
                }
              }
            }
          })();
        } else {
          trail2 = fx.trail;
        }
        {
          const $t28733 = game.fx_bursts;
          {
            const $t28734 = fx.particles;
            {
              const $t28735 = (() => {
                return spawn_bursts($t28733, t2, $t28734);
              })();
              {
                const particles2 = (() => {
                  {
                    const $t28716_i9889 = { $: "$Clo_$lam28715$3752", _0: $lam28715$apply$3752, _1: dt_s };
                    {
                      const $t28717_i9893 = (() => {
                        {
                          const f_i3949_i9890 = $t28716_i9889;
                          {
                            const go_i3950_i9891 = { $: "$Clo_go$4755", _0: go$apply$4755, _1: f_i3949_i9890 };
                            {
                              const $t267_i3951_i9892 = { $: "Nil" };
                              return go$apply$4755(go_i3950_i9891, $t28735, $t267_i3951_i9892);
                            }
                          }
                        }
                      })();
                      {
                        const $t28720_i9894 = { $: "$Clo_$lam28718$3753", _0: $lam28718$apply$3753 };
                        {
                          const pred_i3945_i9895 = $t28720_i9894;
                          {
                            const go_i3946_i9896 = { $: "$Clo_go$4753", _0: go$apply$4753, _1: pred_i3945_i9895 };
                            {
                              const $t299_i3947_i9897 = { $: "Nil" };
                              return go$apply$4753(go_i3946_i9896, $t28717_i9893, $t299_i3947_i9897);
                            }
                          }
                        }
                      }
                    }
                  }
                })();
                {
                  const flash1 = (() => {
                    {
                      const $t28736 = fx.flash;
                      return step_flash($t28736, dt_s);
                    }
                  })();
                  {
                    const flash2 = (() => {
                      {
                        const $t28737 = game.capture_flash;
                        switch ($t28737.$) {
                          case "None": {
                            return flash1;
                            break;
                          }
                          case "Some": {
                            const $f28741 = $t28737._0;
                            {
                              const pt = (() => {
                                return $f28741;
                              })();
                              {
                                const x = pt._0;
                                {
                                  const y = pt._1;
                                  {
                                    const $t28739 = { _0: x, _1: y, _2: 0.45 };
                                    return { $: "Some", _0: $t28739 };
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
                    })();
                    return ({ ...fx, trail: trail2, t: t2, particles: particles2, flash: flash2 });
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
const step_fx$clo = { _0: ($_, fx, game, dt_s) => step_fx(fx, game, dt_s) };

function draw_trail(ctx, trail, i, n) {
  switch (trail.$) {
    case "Nil": {
      return {  };
      break;
    }
    case "Cons": {
      const $f28751 = trail._0;
      const $f28752 = trail._1;
      {
        const rest = (() => {
          return $f28752;
        })();
        {
          const pt = (() => {
            return $f28751;
          })();
          {
            const x = pt._0;
            {
              const y = pt._1;
              {
                const f = (() => {
                  {
                    const $t28744 = (() => {
                      {
                        const $t28742 = i;
                        {
                          const $t28743 = n;
                          return ($t28742 / $t28743);
                        }
                      }
                    })();
                    return (1. - $t28744);
                  }
                })();
                (() => {
                  {
                    const $t28745 = (f * 0.28);
                    return Canvas$set_global_alpha(ctx, $t28745);
                  }
                })();
                (() => {
                  return Canvas$set_fill_style(ctx, "#ffffff");
                })();
                (() => {
                  return Canvas$begin_path(ctx);
                })();
                (() => {
                  {
                    const $t28747 = (() => {
                      {
                        const $t28746 = (2.5 * f);
                        return (1. + $t28746);
                      }
                    })();
                    return Canvas$arc(ctx, x, y, $t28747, 0., 6.28318530718);
                  }
                })();
                (() => {
                  return Canvas$fill(ctx);
                })();
                {
                  const $t28749 = (i + 1);
                  return draw_trail(ctx, rest, $t28749, n);
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
const draw_trail$clo = { _0: ($_, ctx, trail, i, n) => draw_trail(ctx, trail, i, n) };

function draw_particles(ctx, particles) {
  switch (particles.$) {
    case "Nil": {
      return {  };
      break;
    }
    case "Cons": {
      const $f28764 = particles._0;
      const $f28765 = particles._1;
      {
        const rest = (() => {
          return $f28765;
        })();
        {
          const p = (() => {
            return $f28764;
          })();
          {
            const f = (() => {
              {
                const $t28757 = p.life;
                {
                  const $t28758 = p.max_life;
                  return ($t28757 / $t28758);
                }
              }
            })();
            (() => {
              return Canvas$set_global_alpha(ctx, f);
            })();
            (() => {
              return Canvas$set_fill_style(ctx, "#e8e8e8");
            })();
            (() => {
              return Canvas$begin_path(ctx);
            })();
            (() => {
              {
                const $t28759 = p.x;
                {
                  const $t28760 = p.y;
                  {
                    const $t28762 = (() => {
                      {
                        const $t28761 = (1.5 * f);
                        return (0.5 + $t28761);
                      }
                    })();
                    return Canvas$arc(ctx, $t28759, $t28760, $t28762, 0., 6.28318530718);
                  }
                }
              }
            })();
            (() => {
              return Canvas$fill(ctx);
            })();
            return draw_particles(ctx, rest);
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
const draw_particles$clo = { _0: ($_, ctx, particles) => draw_particles(ctx, particles) };

function draw_flash(ctx, flash) {
  switch (flash.$) {
    case "None": {
      return {  };
      break;
    }
    case "Some": {
      const $f28780 = flash._0;
      {
        const f = (() => {
          return $f28780;
        })();
        {
          const x = f._0;
          {
            const y = f._1;
            {
              const tr = f._2;
              {
                const prog = (() => {
                  {
                    const $t28771 = (tr / 0.45);
                    return (1. - $t28771);
                  }
                })();
                {
                  const r = (() => {
                    {
                      const $t28772 = (prog * 60.);
                      return (8. + $t28772);
                    }
                  })();
                  (() => {
                    {
                      const $t28774 = (() => {
                        {
                          const $t28773 = (1. - prog);
                          return ($t28773 * 0.7);
                        }
                      })();
                      return Canvas$set_global_alpha(ctx, $t28774);
                    }
                  })();
                  (() => {
                    return Canvas$set_stroke_style(ctx, "#ffffff");
                  })();
                  (() => {
                    {
                      const $t28777 = (() => {
                        {
                          const $t28776 = (() => {
                            {
                              const $t28775 = (1. - prog);
                              return (2.5 * $t28775);
                            }
                          })();
                          return ($t28776 + 0.5);
                        }
                      })();
                      return Canvas$set_line_width(ctx, $t28777);
                    }
                  })();
                  (() => {
                    return Canvas$begin_path(ctx);
                  })();
                  (() => {
                    return Canvas$arc(ctx, x, y, r, 0., 6.28318530718);
                  })();
                  return Canvas$stroke(ctx);
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
const draw_flash$clo = { _0: ($_, ctx, flash) => draw_flash(ctx, flash) };

function pulse_style(s) {
  {
    const r = (() => {
      {
        const $t28785 = (() => {
          {
            const $t28784 = s.x;
            return ($t28784 + 1.);
          }
        })();
        {
          const $t28787 = (() => {
            {
              const $t28786 = s.y;
              return ($t28786 + 1.);
            }
          })();
          {
            const x_i9918 = (() => {
              {
                const $t28677_i9917 = (() => {
                  {
                    const $t28676_i9916 = (() => {
                      {
                        const $t28674_i9914 = ($t28785 * 12.9898);
                        {
                          const $t28675_i9915 = ($t28787 * 78.233);
                          return ($t28674_i9914 + $t28675_i9915);
                        }
                      }
                    })();
                    return Math.sin($t28676_i9916);
                  }
                })();
                return ($t28677_i9917 * 43758.5453);
              }
            })();
            {
              const $t28678_i9920 = (() => {
                {
                  const $t1579_i3939_i9919 = Math.floor(x_i9918);
                  return $t1579_i3939_i9919;
                }
              })();
              return (x_i9918 - $t28678_i9920);
            }
          }
        }
      }
    })();
    {
      const $t28788 = (r < 0.34);
      if ($t28788 === true) {
        return 0;
      } else {
        return (() => {
          {
            const $t28789 = (r < 0.67);
            if ($t28789 === true) {
              return 1;
            } else {
              return 2;
            }
          }
        })();
      }
    }
  }
}
const pulse_style$clo = { _0: ($_, s) => pulse_style(s) };

function dot_count(s) {
  {
    const $t28808 = (() => {
      {
        const $t28807 = (() => {
          {
            const $t28806 = (() => {
              {
                const $t28803 = (() => {
                  {
                    const $t28802 = s.x;
                    return ($t28802 + 4.);
                  }
                })();
                {
                  const $t28805 = (() => {
                    {
                      const $t28804 = s.y;
                      return ($t28804 + 4.);
                    }
                  })();
                  {
                    const x_i9945 = (() => {
                      {
                        const $t28677_i9944 = (() => {
                          {
                            const $t28676_i9943 = (() => {
                              {
                                const $t28674_i9941 = ($t28803 * 12.9898);
                                {
                                  const $t28675_i9942 = ($t28805 * 78.233);
                                  return ($t28674_i9941 + $t28675_i9942);
                                }
                              }
                            })();
                            return Math.sin($t28676_i9943);
                          }
                        })();
                        return ($t28677_i9944 * 43758.5453);
                      }
                    })();
                    {
                      const $t28678_i9947 = (() => {
                        {
                          const $t1579_i3939_i9946 = Math.floor(x_i9945);
                          return $t1579_i3939_i9946;
                        }
                      })();
                      return (x_i9945 - $t28678_i9947);
                    }
                  }
                }
              }
            })();
            return ($t28806 * 4.);
          }
        })();
        return Math.trunc($t28807);
      }
    })();
    return (2 + $t28808);
  }
}
const dot_count$clo = { _0: ($_, s) => dot_count(s) };

function draw_pulse_ring(ctx, s, pulse) {
  (() => {
    {
      const $t28815 = (0.1 * pulse);
      return Canvas$set_global_alpha(ctx, $t28815);
    }
  })();
  (() => {
    return Canvas$set_stroke_style(ctx, "#cfcfcf");
  })();
  (() => {
    {
      const $t28817 = (() => {
        {
          const $t28816 = (0.6 * pulse);
          return (1. + $t28816);
        }
      })();
      return Canvas$set_line_width(ctx, $t28817);
    }
  })();
  (() => {
    return Canvas$begin_path(ctx);
  })();
  (() => {
    {
      const $t28818 = s.x;
      {
        const $t28819 = s.y;
        {
          const $t28820 = s.capture_radius;
          return Canvas$arc(ctx, $t28818, $t28819, $t28820, 0., 6.28318530718);
        }
      }
    }
  })();
  return Canvas$stroke(ctx);
}
const draw_pulse_ring$clo = { _0: ($_, ctx, s, pulse) => draw_pulse_ring(ctx, s, pulse) };

function draw_pulse_halo(ctx, s, pulse) {
  (() => {
    {
      const $t28823 = (() => {
        {
          const $t28822 = (0.035 * pulse);
          return (0.025 + $t28822);
        }
      })();
      return Canvas$set_global_alpha(ctx, $t28823);
    }
  })();
  (() => {
    return Canvas$set_fill_style(ctx, "#ffffff");
  })();
  (() => {
    return Canvas$begin_path(ctx);
  })();
  (() => {
    {
      const $t28824 = s.x;
      {
        const $t28825 = s.y;
        {
          const $t28829 = (() => {
            {
              const $t28826 = s.radius;
              {
                const $t28828 = (() => {
                  {
                    const $t28827 = (0.9 * pulse);
                    return (1.6 + $t28827);
                  }
                })();
                return ($t28826 * $t28828);
              }
            }
          })();
          return Canvas$arc(ctx, $t28824, $t28825, $t28829, 0., 6.28318530718);
        }
      }
    }
  })();
  return Canvas$fill(ctx);
}
const draw_pulse_halo$clo = { _0: ($_, ctx, s, pulse) => draw_pulse_halo(ctx, s, pulse) };

function draw_pulse_particle(ctx, s, t, n, i) {
  {
    const $t28831 = (i >= n);
    if ($t28831 === true) {
      return {  };
    } else {
      return (() => {
        {
          const a = (() => {
            {
              const $t28835 = (() => {
                {
                  const $t28833 = (() => {
                    {
                      const $t28832 = (() => {
                        {
                          const $t28814_i10193 = (() => {
                            {
                              const $t28813_i10192 = (() => {
                                {
                                  const $t28810_i10182 = (() => {
                                    {
                                      const $t28809_i10181 = s.x;
                                      return ($t28809_i10181 + 5.);
                                    }
                                  })();
                                  {
                                    const $t28812_i10184 = (() => {
                                      {
                                        const $t28811_i10183 = s.y;
                                        return ($t28811_i10183 + 5.);
                                      }
                                    })();
                                    {
                                      const x_i9954_i10189 = (() => {
                                        {
                                          const $t28677_i9953_i10188 = (() => {
                                            {
                                              const $t28676_i9952_i10187 = (() => {
                                                {
                                                  const $t28674_i9950_i10185 = ($t28810_i10182 * 12.9898);
                                                  {
                                                    const $t28675_i9951_i10186 = ($t28812_i10184 * 78.233);
                                                    return ($t28674_i9950_i10185 + $t28675_i9951_i10186);
                                                  }
                                                }
                                              })();
                                              return Math.sin($t28676_i9952_i10187);
                                            }
                                          })();
                                          return ($t28677_i9953_i10188 * 43758.5453);
                                        }
                                      })();
                                      {
                                        const $t28678_i9956_i10191 = (() => {
                                          {
                                            const $t1579_i3939_i9955_i10190 = Math.floor(x_i9954_i10189);
                                            return $t1579_i3939_i9955_i10190;
                                          }
                                        })();
                                        return (x_i9954_i10189 - $t28678_i9956_i10191);
                                      }
                                    }
                                  }
                                }
                              })();
                              return ($t28813_i10192 * 2.4);
                            }
                          })();
                          return (0.4 + $t28814_i10193);
                        }
                      })();
                      return (t * $t28832);
                    }
                  })();
                  {
                    const $t28834 = (() => {
                      {
                        const $t28800_i10179 = (() => {
                          {
                            const $t28797_i10169 = (() => {
                              {
                                const $t28796_i10168 = s.x;
                                return ($t28796_i10168 + 3.);
                              }
                            })();
                            {
                              const $t28799_i10171 = (() => {
                                {
                                  const $t28798_i10170 = s.y;
                                  return ($t28798_i10170 + 3.);
                                }
                              })();
                              {
                                const x_i9936_i10176 = (() => {
                                  {
                                    const $t28677_i9935_i10175 = (() => {
                                      {
                                        const $t28676_i9934_i10174 = (() => {
                                          {
                                            const $t28674_i9932_i10172 = ($t28797_i10169 * 12.9898);
                                            {
                                              const $t28675_i9933_i10173 = ($t28799_i10171 * 78.233);
                                              return ($t28674_i9932_i10172 + $t28675_i9933_i10173);
                                            }
                                          }
                                        })();
                                        return Math.sin($t28676_i9934_i10174);
                                      }
                                    })();
                                    return ($t28677_i9935_i10175 * 43758.5453);
                                  }
                                })();
                                {
                                  const $t28678_i9938_i10178 = (() => {
                                    {
                                      const $t1579_i3939_i9937_i10177 = Math.floor(x_i9936_i10176);
                                      return $t1579_i3939_i9937_i10177;
                                    }
                                  })();
                                  return (x_i9936_i10176 - $t28678_i9938_i10178);
                                }
                              }
                            }
                          }
                        })();
                        return ($t28800_i10179 * 6.28318530718);
                      }
                    })();
                    return ($t28833 + $t28834);
                  }
                }
              })();
              {
                const $t28840 = (() => {
                  {
                    const $t28836 = i;
                    {
                      const $t28839 = (() => {
                        {
                          const $t28838 = n;
                          return (6.28318530718 / $t28838);
                        }
                      })();
                      return ($t28836 * $t28839);
                    }
                  }
                })();
                return ($t28835 + $t28840);
              }
            }
          })();
          {
            const r = (() => {
              {
                const $t28841 = s.radius;
                return ($t28841 * 1.8);
              }
            })();
            {
              const px = (() => {
                {
                  const $t28842 = s.x;
                  {
                    const $t28844 = (() => {
                      {
                        const $t28843 = Math.cos(a);
                        return ($t28843 * r);
                      }
                    })();
                    return ($t28842 + $t28844);
                  }
                }
              })();
              {
                const py = (() => {
                  {
                    const $t28845 = s.y;
                    {
                      const $t28847 = (() => {
                        {
                          const $t28846 = Math.sin(a);
                          return ($t28846 * r);
                        }
                      })();
                      return ($t28845 + $t28847);
                    }
                  }
                })();
                (() => {
                  return Canvas$set_global_alpha(ctx, 0.14);
                })();
                (() => {
                  return Canvas$set_fill_style(ctx, "#cfcfcf");
                })();
                (() => {
                  return Canvas$begin_path(ctx);
                })();
                (() => {
                  return Canvas$arc(ctx, px, py, 1.3, 0., 6.28318530718);
                })();
                (() => {
                  return Canvas$fill(ctx);
                })();
                {
                  const $t28849 = (i + 1);
                  return draw_pulse_particle(ctx, s, t, n, $t28849);
                }
              }
            }
          }
        }
      })();
    }
  }
}
const draw_pulse_particle$clo = { _0: ($_, ctx, s, t, n, i) => draw_pulse_particle(ctx, s, t, n, i) };

function draw_orbit_rings(ctx, s, orbits) {
  switch (orbits.$) {
    case "Nil": {
      return {  };
      break;
    }
    case "Cons": {
      const $f28858 = orbits._0;
      const $f28859 = orbits._1;
      {
        const $jp_clo28865 = (() => {
          return { $: "$Clo_$jp28864$3756", _0: $jp28864$apply$3756, _1: $f28858, _2: $f28859, _3: ctx, _4: s };
        })();
        switch ($f28859.$) {
          case "Nil": {
            {
              const o = $f28858;
              (() => {
                return Canvas$set_global_alpha(ctx, 0.28);
              })();
              (() => {
                return Canvas$set_stroke_style(ctx, "#9a9a9a");
              })();
              (() => {
                return Canvas$set_line_width(ctx, 1.);
              })();
              (() => {
                return Canvas$begin_path(ctx);
              })();
              (() => {
                {
                  const $t28850 = s.x;
                  {
                    const $t28851 = s.y;
                    {
                      const $t28852 = o.radius;
                      return Canvas$arc(ctx, $t28850, $t28851, $t28852, 0., 6.28318530718);
                    }
                  }
                }
              })();
              return Canvas$stroke(ctx);
            }
            break;
          }
          default: {
            return $jp28864$apply$3756($jp_clo28865);
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
const draw_orbit_rings$clo = { _0: ($_, ctx, s, orbits) => draw_orbit_rings(ctx, s, orbits) };

function star_targeted(s, aim) {
  switch (aim.$) {
    case "None": {
      return false;
      break;
    }
    case "Some": {
      const $f28881 = aim._0;
      {
        const a = (() => {
          return $f28881;
        })();
        {
          const px = a._0;
          {
            const py = a._1;
            {
              const vx = a._2;
              {
                const vy = a._3;
                {
                  const dx = (() => {
                    {
                      const $t28868 = s.x;
                      return ($t28868 - px);
                    }
                  })();
                  {
                    const dy = (() => {
                      {
                        const $t28869 = s.y;
                        return ($t28869 - py);
                      }
                    })();
                    {
                      const range = (() => {
                        {
                          const $t28870 = s.capture_radius;
                          return ($t28870 * 4.);
                        }
                      })();
                      {
                        const $t28874 = (() => {
                          {
                            const $t28873 = (() => {
                              {
                                const $t28871 = (vx * dx);
                                {
                                  const $t28872 = (vy * dy);
                                  return ($t28871 + $t28872);
                                }
                              }
                            })();
                            return ($t28873 > 0.);
                          }
                        })();
                        {
                          const $t28879 = (() => {
                            {
                              const $t28877 = (() => {
                                {
                                  const $t28875 = (dx * dx);
                                  {
                                    const $t28876 = (dy * dy);
                                    return ($t28875 + $t28876);
                                  }
                                }
                              })();
                              {
                                const $t28878 = (range * range);
                                return ($t28877 < $t28878);
                              }
                            }
                          })();
                          return ($t28874 && $t28879);
                        }
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
const star_targeted$clo = { _0: ($_, s, aim) => star_targeted(s, aim) };

function draw_target_pulse(ctx, s, t) {
  {
    const pulse = (() => {
      {
        const $t28884 = (() => {
          {
            const $t28883 = (() => {
              {
                const $t28882 = (t * 6.);
                return Math.sin($t28882);
              }
            })();
            return (0.5 * $t28883);
          }
        })();
        return (0.5 + $t28884);
      }
    })();
    (() => {
      {
        const $t28886 = (() => {
          {
            const $t28885 = (0.45 * pulse);
            return (0.3 + $t28885);
          }
        })();
        return Canvas$set_global_alpha(ctx, $t28886);
      }
    })();
    (() => {
      return Canvas$set_stroke_style(ctx, "#ffffff");
    })();
    (() => {
      {
        const $t28888 = (() => {
          {
            const $t28887 = (1.6 * pulse);
            return (1.2 + $t28887);
          }
        })();
        return Canvas$set_line_width(ctx, $t28888);
      }
    })();
    (() => {
      return Canvas$begin_path(ctx);
    })();
    (() => {
      {
        const $t28889 = s.x;
        {
          const $t28890 = s.y;
          {
            const $t28891 = s.capture_radius;
            return Canvas$arc(ctx, $t28889, $t28890, $t28891, 0., 6.28318530718);
          }
        }
      }
    })();
    return Canvas$stroke(ctx);
  }
}
const draw_target_pulse$clo = { _0: ($_, ctx, s, t) => draw_target_pulse(ctx, s, t) };

function draw_star(ctx, s, t, aim) {
  (() => {
    {
      const $t28893 = s.orbits;
      return draw_orbit_rings(ctx, s, $t28893);
    }
  })();
  (() => {
    {
      const $t28894 = (() => {
        {
          const $t28783_i10231 = (() => {
            {
              const $t28781_i10222 = s.x;
              {
                const $t28782_i10223 = s.y;
                {
                  const x_i9909_i10228 = (() => {
                    {
                      const $t28677_i9908_i10227 = (() => {
                        {
                          const $t28676_i9907_i10226 = (() => {
                            {
                              const $t28674_i9905_i10224 = ($t28781_i10222 * 12.9898);
                              {
                                const $t28675_i9906_i10225 = ($t28782_i10223 * 78.233);
                                return ($t28674_i9905_i10224 + $t28675_i9906_i10225);
                              }
                            }
                          })();
                          return Math.sin($t28676_i9907_i10226);
                        }
                      })();
                      return ($t28677_i9908_i10227 * 43758.5453);
                    }
                  })();
                  {
                    const $t28678_i9911_i10230 = (() => {
                      {
                        const $t1579_i3939_i9910_i10229 = Math.floor(x_i9909_i10228);
                        return $t1579_i3939_i9910_i10229;
                      }
                    })();
                    return (x_i9909_i10228 - $t28678_i9911_i10230);
                  }
                }
              }
            }
          })();
          return ($t28783_i10231 < 0.8);
        }
      })();
      if ($t28894 === true) {
        return (() => {
          {
            const pulse = (() => {
              {
                const $t28900 = (() => {
                  {
                    const $t28899 = (() => {
                      {
                        const $t28898 = (() => {
                          {
                            const $t28896 = (() => {
                              {
                                const $t28895 = (() => {
                                  {
                                    const $t28795_i10220 = (() => {
                                      {
                                        const $t28794_i10219 = (() => {
                                          {
                                            const $t28791_i10209 = (() => {
                                              {
                                                const $t28790_i10208 = s.x;
                                                return ($t28790_i10208 + 2.);
                                              }
                                            })();
                                            {
                                              const $t28793_i10211 = (() => {
                                                {
                                                  const $t28792_i10210 = s.y;
                                                  return ($t28792_i10210 + 2.);
                                                }
                                              })();
                                              {
                                                const x_i9927_i10216 = (() => {
                                                  {
                                                    const $t28677_i9926_i10215 = (() => {
                                                      {
                                                        const $t28676_i9925_i10214 = (() => {
                                                          {
                                                            const $t28674_i9923_i10212 = ($t28791_i10209 * 12.9898);
                                                            {
                                                              const $t28675_i9924_i10213 = ($t28793_i10211 * 78.233);
                                                              return ($t28674_i9923_i10212 + $t28675_i9924_i10213);
                                                            }
                                                          }
                                                        })();
                                                        return Math.sin($t28676_i9925_i10214);
                                                      }
                                                    })();
                                                    return ($t28677_i9926_i10215 * 43758.5453);
                                                  }
                                                })();
                                                {
                                                  const $t28678_i9929_i10218 = (() => {
                                                    {
                                                      const $t1579_i3939_i9928_i10217 = Math.floor(x_i9927_i10216);
                                                      return $t1579_i3939_i9928_i10217;
                                                    }
                                                  })();
                                                  return (x_i9927_i10216 - $t28678_i9929_i10218);
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        return ($t28794_i10219 * 1.8);
                                      }
                                    })();
                                    return (0.6 + $t28795_i10220);
                                  }
                                })();
                                return (t * $t28895);
                              }
                            })();
                            {
                              const $t28897 = (() => {
                                {
                                  const $t28800_i10206 = (() => {
                                    {
                                      const $t28797_i10196 = (() => {
                                        {
                                          const $t28796_i10195 = s.x;
                                          return ($t28796_i10195 + 3.);
                                        }
                                      })();
                                      {
                                        const $t28799_i10198 = (() => {
                                          {
                                            const $t28798_i10197 = s.y;
                                            return ($t28798_i10197 + 3.);
                                          }
                                        })();
                                        {
                                          const x_i9936_i10203 = (() => {
                                            {
                                              const $t28677_i9935_i10202 = (() => {
                                                {
                                                  const $t28676_i9934_i10201 = (() => {
                                                    {
                                                      const $t28674_i9932_i10199 = ($t28797_i10196 * 12.9898);
                                                      {
                                                        const $t28675_i9933_i10200 = ($t28799_i10198 * 78.233);
                                                        return ($t28674_i9932_i10199 + $t28675_i9933_i10200);
                                                      }
                                                    }
                                                  })();
                                                  return Math.sin($t28676_i9934_i10201);
                                                }
                                              })();
                                              return ($t28677_i9935_i10202 * 43758.5453);
                                            }
                                          })();
                                          {
                                            const $t28678_i9938_i10205 = (() => {
                                              {
                                                const $t1579_i3939_i9937_i10204 = Math.floor(x_i9936_i10203);
                                                return $t1579_i3939_i9937_i10204;
                                              }
                                            })();
                                            return (x_i9936_i10203 - $t28678_i9938_i10205);
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  return ($t28800_i10206 * 6.28318530718);
                                }
                              })();
                              return ($t28896 + $t28897);
                            }
                          }
                        })();
                        return Math.sin($t28898);
                      }
                    })();
                    return (0.5 * $t28899);
                  }
                })();
                return (0.5 + $t28900);
              }
            })();
            {
              const $t28901 = pulse_style(s);
              if ($t28901 === 0) {
                return (() => {
                  {
                    const $jp_clo28904 = (() => {
                      return { $: "$Clo_$jp28903$3759", _0: $jp28903$apply$3759, _1: ctx, _2: s, _3: t };
                    })();
                    return draw_pulse_ring(ctx, s, pulse);
                  }
                })();
              } else if ($t28901 === 1) {
                return (() => {
                  {
                    const $jp_clo28906 = (() => {
                      return { $: "$Clo_$jp28905$3760", _0: $jp28905$apply$3760, _1: ctx, _2: s, _3: t };
                    })();
                    return draw_pulse_halo(ctx, s, pulse);
                  }
                })();
              } else {
                return (() => {
                  {
                    const $t28902 = dot_count(s);
                    return draw_pulse_particle(ctx, s, t, $t28902, 0);
                  }
                })();
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
      const $t28907 = star_targeted(s, aim);
      if ($t28907 === true) {
        return (() => {
          return draw_target_pulse(ctx, s, t);
        })();
      } else {
        return {  };
      }
    }
  })();
  (() => {
    return Canvas$set_global_alpha(ctx, 1.);
  })();
  (() => {
    return Canvas$set_fill_style(ctx, "#f2f2f2");
  })();
  (() => {
    return Canvas$begin_path(ctx);
  })();
  (() => {
    {
      const $t28908 = s.x;
      {
        const $t28909 = s.y;
        {
          const $t28910 = s.radius;
          return Canvas$arc(ctx, $t28908, $t28909, $t28910, 0., 6.28318530718);
        }
      }
    }
  })();
  return Canvas$fill(ctx);
}
const draw_star$clo = { _0: ($_, ctx, s, t, aim) => draw_star(ctx, s, t, aim) };

function bg_hash(gx, gy, seed) {
  {
    const fx = gx;
    {
      const fy = gy;
      {
        const h1 = (() => {
          {
            const $t28918 = (() => {
              {
                const $t28917 = (seed * 37.719);
                return (fx + $t28917);
              }
            })();
            {
              const $t28920 = (() => {
                {
                  const $t28919 = (seed * 12.9898);
                  return (fy - $t28919);
                }
              })();
              {
                const x_i9981 = (() => {
                  {
                    const $t28915_i9980 = (() => {
                      {
                        const $t28914_i9979 = (() => {
                          {
                            const $t28912_i9977 = ($t28918 * 12.9898);
                            {
                              const $t28913_i9978 = ($t28920 * 78.233);
                              return ($t28912_i9977 + $t28913_i9978);
                            }
                          }
                        })();
                        return Math.sin($t28914_i9979);
                      }
                    })();
                    return ($t28915_i9980 * 43758.5453);
                  }
                })();
                {
                  const $t28916_i9983 = (() => {
                    {
                      const $t1579_i3970_i9982 = Math.floor(x_i9981);
                      return $t1579_i3970_i9982;
                    }
                  })();
                  return (x_i9981 - $t28916_i9983);
                }
              }
            }
          }
        })();
        {
          const h2 = (() => {
            {
              const $t28923 = (() => {
                {
                  const $t28921 = (fy * 3.271);
                  {
                    const $t28922 = (seed * 71.238);
                    return ($t28921 - $t28922);
                  }
                }
              })();
              {
                const $t28926 = (() => {
                  {
                    const $t28924 = (fx * 1.373);
                    {
                      const $t28925 = (seed * 5.113);
                      return ($t28924 + $t28925);
                    }
                  }
                })();
                {
                  const x_i9972 = (() => {
                    {
                      const $t28915_i9971 = (() => {
                        {
                          const $t28914_i9970 = (() => {
                            {
                              const $t28912_i9968 = ($t28923 * 12.9898);
                              {
                                const $t28913_i9969 = ($t28926 * 78.233);
                                return ($t28912_i9968 + $t28913_i9969);
                              }
                            }
                          })();
                          return Math.sin($t28914_i9970);
                        }
                      })();
                      return ($t28915_i9971 * 43758.5453);
                    }
                  })();
                  {
                    const $t28916_i9974 = (() => {
                      {
                        const $t1579_i3970_i9973 = Math.floor(x_i9972);
                        return $t1579_i3970_i9973;
                      }
                    })();
                    return (x_i9972 - $t28916_i9974);
                  }
                }
              }
            }
          })();
          {
            const $t28929 = (() => {
              {
                const $t28927 = (h1 * 269.5);
                {
                  const $t28928 = (h2 * 183.3);
                  return ($t28927 + $t28928);
                }
              }
            })();
            {
              const $t28933 = (() => {
                {
                  const $t28932 = (() => {
                    {
                      const $t28930 = (fx * 0.618);
                      {
                        const $t28931 = (fy * 0.573);
                        return ($t28930 + $t28931);
                      }
                    }
                  })();
                  return ($t28932 + seed);
                }
              })();
              {
                const x_i9963 = (() => {
                  {
                    const $t28915_i9962 = (() => {
                      {
                        const $t28914_i9961 = (() => {
                          {
                            const $t28912_i9959 = ($t28929 * 12.9898);
                            {
                              const $t28913_i9960 = ($t28933 * 78.233);
                              return ($t28912_i9959 + $t28913_i9960);
                            }
                          }
                        })();
                        return Math.sin($t28914_i9961);
                      }
                    })();
                    return ($t28915_i9962 * 43758.5453);
                  }
                })();
                {
                  const $t28916_i9965 = (() => {
                    {
                      const $t1579_i3970_i9964 = Math.floor(x_i9963);
                      return $t1579_i3970_i9964;
                    }
                  })();
                  return (x_i9963 - $t28916_i9965);
                }
              }
            }
          }
        }
      }
    }
  }
}
const bg_hash$clo = { _0: ($_, gx, gy, seed) => bg_hash(gx, gy, seed) };

function draw_bg_cell(ctx, gx, gy, cell, seed, t) {
  {
    const h = bg_hash(gx, gy, seed);
    {
      const $t28935 = (h > 0.5);
      if ($t28935 === true) {
        return {  };
      } else {
        return (() => {
          {
            const jx = (() => {
              {
                const $t28936 = (gy + 1000);
                return bg_hash(gx, $t28936, seed);
              }
            })();
            {
              const jy = (() => {
                {
                  const $t28937 = (gx + 1000);
                  return bg_hash($t28937, gy, seed);
                }
              })();
              {
                const x = (() => {
                  {
                    const $t28939 = (() => {
                      {
                        const $t28938 = gx;
                        return ($t28938 * cell);
                      }
                    })();
                    {
                      const $t28940 = (jx * cell);
                      return ($t28939 + $t28940);
                    }
                  }
                })();
                {
                  const y = (() => {
                    {
                      const $t28942 = (() => {
                        {
                          const $t28941 = gy;
                          return ($t28941 * cell);
                        }
                      })();
                      {
                        const $t28943 = (jy * cell);
                        return ($t28942 + $t28943);
                      }
                    }
                  })();
                  {
                    const br = (() => {
                      {
                        const $t28947 = (() => {
                          {
                            const $t28946 = (() => {
                              {
                                const $t28944 = (gx + 2000);
                                {
                                  const $t28945 = (gy + 2000);
                                  return bg_hash($t28944, $t28945, seed);
                                }
                              }
                            })();
                            return (0.45 * $t28946);
                          }
                        })();
                        return (0.12 + $t28947);
                      }
                    })();
                    {
                      const st = (() => {
                        {
                          const $t28948 = (gx - 2000);
                          {
                            const $t28949 = (gy - 2000);
                            return bg_hash($t28948, $t28949, seed);
                          }
                        }
                      })();
                      {
                        const sz = (() => {
                          {
                            const $t28951 = (() => {
                              {
                                const $t28950 = (1.8 * st);
                                return ($t28950 * st);
                              }
                            })();
                            return (1. + $t28951);
                          }
                        })();
                        {
                          const is_pulsing = (() => {
                            {
                              const $t28954 = (() => {
                                {
                                  const $t28952 = (gx + 3000);
                                  {
                                    const $t28953 = (gy + 3000);
                                    return bg_hash($t28952, $t28953, seed);
                                  }
                                }
                              })();
                              return ($t28954 < 0.04);
                            }
                          })();
                          {
                            let pulse;
                            if (is_pulsing === true) {
                              pulse = (() => {
                                {
                                  const speed = (() => {
                                    {
                                      const $t28958 = (() => {
                                        {
                                          const $t28957 = (() => {
                                            {
                                              const $t28956 = (gx + 4000);
                                              return bg_hash($t28956, gy, seed);
                                            }
                                          })();
                                          return (0.45 * $t28957);
                                        }
                                      })();
                                      return (0.35 + $t28958);
                                    }
                                  })();
                                  {
                                    const phase = (() => {
                                      {
                                        const $t28960 = (() => {
                                          {
                                            const $t28959 = (gy + 4000);
                                            return bg_hash(gx, $t28959, seed);
                                          }
                                        })();
                                        return ($t28960 * 6.28318530718);
                                      }
                                    })();
                                    {
                                      const $t28965 = (() => {
                                        {
                                          const $t28964 = (() => {
                                            {
                                              const $t28963 = (() => {
                                                {
                                                  const $t28962 = (t * speed);
                                                  return ($t28962 + phase);
                                                }
                                              })();
                                              return Math.sin($t28963);
                                            }
                                          })();
                                          return (0.5 * $t28964);
                                        }
                                      })();
                                      return (0.5 + $t28965);
                                    }
                                  }
                                }
                              })();
                            } else {
                              pulse = 0.;
                            }
                            {
                              let br2;
                              if (is_pulsing === true) {
                                br2 = (() => {
                                  {
                                    const $t28968 = (() => {
                                      {
                                        const $t28967 = (() => {
                                          {
                                            const $t28966 = (1. - br);
                                            return ($t28966 * 0.6);
                                          }
                                        })();
                                        return ($t28967 * pulse);
                                      }
                                    })();
                                    return (br + $t28968);
                                  }
                                })();
                              } else {
                                br2 = br;
                              }
                              {
                                let sz2;
                                if (is_pulsing === true) {
                                  sz2 = (() => {
                                    {
                                      const $t28970 = (() => {
                                        {
                                          const $t28969 = (0.35 * pulse);
                                          return (1. + $t28969);
                                        }
                                      })();
                                      return (sz * $t28970);
                                    }
                                  })();
                                } else {
                                  sz2 = sz;
                                }
                                (() => {
                                  return Canvas$set_global_alpha(ctx, br2);
                                })();
                                (() => {
                                  return Canvas$begin_path(ctx);
                                })();
                                (() => {
                                  return Canvas$arc(ctx, x, y, sz2, 0., 6.28318530718);
                                })();
                                return Canvas$fill(ctx);
                              }
                            }
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
const draw_bg_cell$clo = { _0: ($_, ctx, gx, gy, cell, seed, t) => draw_bg_cell(ctx, gx, gy, cell, seed, t) };

function draw_bg_row(ctx, gx, gx_max, gy, cell, seed, t) {
  {
    const $t28972 = (gx > gx_max);
    if ($t28972 === true) {
      return {  };
    } else {
      return (() => {
        (() => {
          return draw_bg_cell(ctx, gx, gy, cell, seed, t);
        })();
        {
          const $t28973 = (gx + 1);
          return draw_bg_row(ctx, $t28973, gx_max, gy, cell, seed, t);
        }
      })();
    }
  }
}
const draw_bg_row$clo = { _0: ($_, ctx, gx, gx_max, gy, cell, seed, t) => draw_bg_row(ctx, gx, gx_max, gy, cell, seed, t) };

function draw_bg_rows(ctx, gx0, gx1, gy, gy_max, cell, seed, t) {
  {
    const $t28974 = (gy > gy_max);
    if ($t28974 === true) {
      return {  };
    } else {
      return (() => {
        (() => {
          return draw_bg_row(ctx, gx0, gx1, gy, cell, seed, t);
        })();
        {
          const $t28975 = (gy + 1);
          return draw_bg_rows(ctx, gx0, gx1, $t28975, gy_max, cell, seed, t);
        }
      })();
    }
  }
}
const draw_bg_rows$clo = { _0: ($_, ctx, gx0, gx1, gy, gy_max, cell, seed, t) => draw_bg_rows(ctx, gx0, gx1, gy, gy_max, cell, seed, t) };

function draw_starfield(ctx, cam_x, cam, view_w, view_h, seed, t) {
  {
    const gx0 = (() => {
      {
        const $t28978 = (() => {
          {
            const $t28977 = (() => {
              {
                const $t28976 = (cam_x / 70.);
                {
                  const $t1579_i3980 = Math.floor($t28976);
                  return $t1579_i3980;
                }
              }
            })();
            return Math.trunc($t28977);
          }
        })();
        return ($t28978 - 1);
      }
    })();
    {
      const gx1 = (() => {
        {
          const $t28982 = (() => {
            {
              const $t28981 = (() => {
                {
                  const $t28980 = (() => {
                    {
                      const $t28979 = (cam_x + view_w);
                      return ($t28979 / 70.);
                    }
                  })();
                  {
                    const $t1579_i3978 = Math.floor($t28980);
                    return $t1579_i3978;
                  }
                }
              })();
              return Math.trunc($t28981);
            }
          })();
          return ($t28982 + 1);
        }
      })();
      {
        const gy0 = (() => {
          {
            const $t28985 = (() => {
              {
                const $t28984 = (() => {
                  {
                    const $t28983 = (cam / 70.);
                    {
                      const $t1579_i3976 = Math.floor($t28983);
                      return $t1579_i3976;
                    }
                  }
                })();
                return Math.trunc($t28984);
              }
            })();
            return ($t28985 - 1);
          }
        })();
        {
          const gy1 = (() => {
            {
              const $t28989 = (() => {
                {
                  const $t28988 = (() => {
                    {
                      const $t28987 = (() => {
                        {
                          const $t28986 = (cam + view_h);
                          return ($t28986 / 70.);
                        }
                      })();
                      {
                        const $t1579_i3974 = Math.floor($t28987);
                        return $t1579_i3974;
                      }
                    }
                  })();
                  return Math.trunc($t28988);
                }
              })();
              return ($t28989 + 1);
            }
          })();
          (() => {
            return Canvas$set_fill_style(ctx, "#ffffff");
          })();
          (() => {
            return draw_bg_rows(ctx, gx0, gx1, gy0, gy1, 70., seed, t);
          })();
          return Canvas$set_global_alpha(ctx, 1.);
        }
      }
    }
  }
}
const draw_starfield$clo = { _0: ($_, ctx, cam_x, cam, view_w, view_h, seed, t) => draw_starfield(ctx, cam_x, cam, view_w, view_h, seed, t) };

function draw_nebula_clouds(ctx, clouds) {
  switch (clouds.$) {
    case "Nil": {
      return {  };
      break;
    }
    case "Cons": {
      const $f28996 = clouds._0;
      const $f28997 = clouds._1;
      {
        const rest = (() => {
          return $f28997;
        })();
        {
          const c = (() => {
            return $f28996;
          })();
          (() => {
            {
              const $t28990 = c.x;
              {
                const $t28991 = c.y;
                {
                  const $t28992 = c.radius;
                  {
                    const $t28995 = (() => {
                      {
                        const $t28994 = c.strength;
                        return (0.16 * $t28994);
                      }
                    })();
                    return Canvas$fill_noise_circle(ctx, $t28990, $t28991, $t28992, $t28995);
                  }
                }
              }
            }
          })();
          return draw_nebula_clouds(ctx, rest);
        }
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const draw_nebula_clouds$clo = { _0: ($_, ctx, clouds) => draw_nebula_clouds(ctx, clouds) };

function draw_nebula(ctx, stars, cam, view_h, seed) {
  {
    const $t29002 = (() => {
      {
        const margin_i9988 = (700. + 90.);
        {
          const $t28664_i9989 = { $: "Nil" };
          {
            const $t28665_i9990 = Perihelion$Nebula$filter_visible(stars, cam, view_h, margin_i9988, $t28664_i9989);
            {
              const $t28666_i9991 = { $: "Nil" };
              return Perihelion$Nebula$collect_star_clouds($t28665_i9990, seed, $t28666_i9991);
            }
          }
        }
      }
    })();
    {
      const $rc_835 = draw_nebula_clouds(ctx, $t29002);
      return $rc_835;
    }
  }
}
const draw_nebula$clo = { _0: ($_, ctx, stars, cam, view_h, seed) => draw_nebula(ctx, stars, cam, view_h, seed) };

function draw_stars(ctx, stars, cam, view_h, t, aim) {
  switch (stars.$) {
    case "Nil": {
      return {  };
      break;
    }
    case "Cons": {
      const $f29011 = stars._0;
      const $f29012 = stars._1;
      {
        const rest = $f29012;
        {
          const s = $f29011;
          (() => {
            {
              const $t29010 = (() => {
                {
                  const $t29006 = (() => {
                    {
                      const $t29003 = s.y;
                      {
                        const $t29005 = (() => {
                          {
                            const $t29004 = (cam + view_h);
                            return ($t29004 + 100.);
                          }
                        })();
                        return ($t29003 < $t29005);
                      }
                    }
                  })();
                  {
                    const $t29009 = (() => {
                      {
                        const $t29007 = s.y;
                        {
                          const $t29008 = (cam - 100.);
                          return ($t29007 > $t29008);
                        }
                      }
                    })();
                    return ($t29006 && $t29009);
                  }
                }
              })();
              if ($t29010 === true) {
                return (() => {
                  return draw_star(ctx, s, t, aim);
                })();
              } else {
                return {  };
              }
            }
          })();
          return draw_stars(ctx, rest, cam, view_h, t, aim);
        }
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const draw_stars$clo = { _0: ($_, ctx, stars, cam, view_h, t, aim) => draw_stars(ctx, stars, cam, view_h, t, aim) };

function asteroid_vertex(a, i) {
  {
    const angle = (() => {
      {
        const $t29023 = i;
        {
          const $t29025 = (6.28318530718 / 8.);
          return ($t29023 * $t29025);
        }
      }
    })();
    {
      const jitter = (() => {
        {
          const $t29028 = (() => {
            {
              const $t29027 = (() => {
                {
                  const $t29026 = a.shape_seed;
                  {
                    const x_i9999 = (() => {
                      {
                        const $t29021_i9998 = (() => {
                          {
                            const $t29020_i9997 = (() => {
                              {
                                const $t29017_i9994 = ($t29026 * 12.9898);
                                {
                                  const $t29019_i9996 = (() => {
                                    {
                                      const $t29018_i9995 = i;
                                      return ($t29018_i9995 * 78.233);
                                    }
                                  })();
                                  return ($t29017_i9994 + $t29019_i9996);
                                }
                              }
                            })();
                            return Math.sin($t29020_i9997);
                          }
                        })();
                        return ($t29021_i9998 * 43758.5453);
                      }
                    })();
                    {
                      const $t29022_i10001 = (() => {
                        {
                          const $t1579_i3984_i10000 = Math.floor(x_i9999);
                          return $t1579_i3984_i10000;
                        }
                      })();
                      return (x_i9999 - $t29022_i10001);
                    }
                  }
                }
              })();
              return (0.6 * $t29027);
            }
          })();
          return (0.7 + $t29028);
        }
      })();
      {
        const r = (() => {
          {
            const $t29029 = a.radius;
            return ($t29029 * jitter);
          }
        })();
        {
          const pt = (() => {
            {
              const $t29033 = (() => {
                {
                  const $t29030 = a.x;
                  {
                    const $t29032 = (() => {
                      {
                        const $t29031 = Math.cos(angle);
                        return ($t29031 * r);
                      }
                    })();
                    return ($t29030 + $t29032);
                  }
                }
              })();
              {
                const $t29037 = (() => {
                  {
                    const $t29034 = a.y;
                    {
                      const $t29036 = (() => {
                        {
                          const $t29035 = Math.sin(angle);
                          return ($t29035 * r);
                        }
                      })();
                      return ($t29034 + $t29036);
                    }
                  }
                })();
                return { _0: $t29033, _1: $t29037 };
              }
            }
          })();
          return pt;
        }
      }
    }
  }
}
const asteroid_vertex$clo = { _0: ($_, a, i) => asteroid_vertex(a, i) };

function draw_asteroid_edges(ctx, a, i) {
  {
    const $t29038 = (i > 7);
    if ($t29038 === true) {
      return (() => {
        (() => {
          return Canvas$close_path(ctx);
        })();
        return Canvas$fill(ctx);
      })();
    } else {
      return (() => {
        {
          const pt = asteroid_vertex(a, i);
          {
            const px = pt._0;
            {
              const py = pt._1;
              (() => {
                if (i === 0) {
                  return (() => {
                    {
                      const $jp_clo29040 = (() => {
                        return { $: "$Clo_$jp29039$3763", _0: $jp29039$apply$3763, _1: ctx, _2: px, _3: py };
                      })();
                      return Canvas$move_to(ctx, px, py);
                    }
                  })();
                } else {
                  return (() => {
                    return Canvas$line_to(ctx, px, py);
                  })();
                }
              })();
              {
                const $t29041 = (i + 1);
                return draw_asteroid_edges(ctx, a, $t29041);
              }
            }
          }
        }
      })();
    }
  }
}
const draw_asteroid_edges$clo = { _0: ($_, ctx, a, i) => draw_asteroid_edges(ctx, a, i) };

function draw_asteroids(ctx, asteroids) {
  switch (asteroids.$) {
    case "Nil": {
      return {  };
      break;
    }
    case "Cons": {
      const $f29050 = asteroids._0;
      const $f29051 = asteroids._1;
      {
        const rest = (() => {
          return $f29051;
        })();
        {
          const a = (() => {
            return $f29050;
          })();
          {
            const color = (() => {
              {
                const $t29043 = a.mode;
                switch ($t29043.$) {
                  case "AsteroidDrifting": {
                    return "#8a8a94";
                    break;
                  }
                  case "AsteroidOrbiting": {
                    const $f29044 = $t29043._0;
                    const $f29045 = $t29043._1;
                    return "#e8e8e8";
                    break;
                  }
                  default: {
                    return (() => { throw new Error("non-exhaustive pattern match"); })();
                  }
                }
              }
            })();
            (() => {
              return Canvas$set_fill_style(ctx, color);
            })();
            (() => {
              return Canvas$begin_path(ctx);
            })();
            (() => {
              return draw_asteroid_edges(ctx, a, 0);
            })();
            return draw_asteroids(ctx, rest);
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
const draw_asteroids$clo = { _0: ($_, ctx, asteroids) => draw_asteroids(ctx, asteroids) };

function draw_shots(ctx, shots, color, r) {
  switch (shots.$) {
    case "Nil": {
      return {  };
      break;
    }
    case "Cons": {
      const $f29059 = shots._0;
      const $f29060 = shots._1;
      {
        const rest = (() => {
          return $f29060;
        })();
        {
          const s = (() => {
            return $f29059;
          })();
          (() => {
            return Canvas$set_fill_style(ctx, color);
          })();
          (() => {
            return Canvas$begin_path(ctx);
          })();
          (() => {
            {
              const $t29056 = s.x;
              {
                const $t29057 = s.y;
                return Canvas$arc(ctx, $t29056, $t29057, r, 0., 6.28318530718);
              }
            }
          })();
          (() => {
            return Canvas$fill(ctx);
          })();
          return draw_shots(ctx, rest, color, r);
        }
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const draw_shots$clo = { _0: ($_, ctx, shots, color, r) => draw_shots(ctx, shots, color, r) };

function ship_heading(sh) {
  {
    const $t29065 = sh.mode;
    switch ($t29065.$) {
      case "ShipOrbiting": {
        const $f29069 = $t29065._0;
        {
          const angle = (() => {
            return $f29069;
          })();
          {
            const d = (0. - 1.);
            {
              const $t29068 = (d * 1.5707963);
              return (angle + $t29068);
            }
          }
        }
        break;
      }
      case "ShipFlying": {
        const $f29070 = $t29065._0;
        const $f29071 = $t29065._1;
        {
          const vy = (() => {
            return $f29071;
          })();
          {
            const vx = (() => {
              return $f29070;
            })();
            return Math.atan2(vy, vx);
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
const ship_heading$clo = { _0: ($_, sh) => ship_heading(sh) };

function draw_ships(ctx, ships) {
  switch (ships.$) {
    case "Nil": {
      return {  };
      break;
    }
    case "Cons": {
      const $f29080 = ships._0;
      const $f29081 = ships._1;
      {
        const rest = (() => {
          return $f29081;
        })();
        {
          const sh = (() => {
            return $f29080;
          })();
          {
            const pos = (() => {
              {
                const pos_i3999 = (() => {
                  {
                    const $t27339_i3997 = sh.x;
                    {
                      const $t27340_i3998 = sh.y;
                      return { _0: $t27339_i3997, _1: $t27340_i3998 };
                    }
                  }
                })();
                return pos_i3999;
              }
            })();
            {
              const sx = pos._0;
              {
                const sy = pos._1;
                {
                  const heading = ship_heading(sh);
                  (() => {
                    return Canvas$save(ctx);
                  })();
                  (() => {
                    return Canvas$translate(ctx, sx, sy);
                  })();
                  (() => {
                    return Canvas$rotate(ctx, heading);
                  })();
                  (() => {
                    return Canvas$set_fill_style(ctx, "#e2e2e2");
                  })();
                  (() => {
                    return Canvas$set_stroke_style(ctx, "#333333");
                  })();
                  (() => {
                    return Canvas$set_line_width(ctx, 1.2);
                  })();
                  (() => {
                    return Canvas$begin_path(ctx);
                  })();
                  (() => {
                    return Canvas$move_to(ctx, 9., 0.);
                  })();
                  (() => {
                    {
                      const $t29076 = (0. - 6.);
                      return Canvas$line_to(ctx, $t29076, 5.);
                    }
                  })();
                  (() => {
                    {
                      const $t29077 = (0. - 6.);
                      {
                        const $t29078 = (0. - 5.);
                        return Canvas$line_to(ctx, $t29077, $t29078);
                      }
                    }
                  })();
                  (() => {
                    return Canvas$close_path(ctx);
                  })();
                  (() => {
                    return Canvas$fill(ctx);
                  })();
                  (() => {
                    return Canvas$stroke(ctx);
                  })();
                  (() => {
                    return Canvas$restore(ctx);
                  })();
                  return draw_ships(ctx, rest);
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
const draw_ships$clo = { _0: ($_, ctx, ships) => draw_ships(ctx, ships) };

function draw_pickups(ctx, pickups) {
  switch (pickups.$) {
    case "Nil": {
      return {  };
      break;
    }
    case "Cons": {
      const $f29089 = pickups._0;
      const $f29090 = pickups._1;
      {
        const rest = (() => {
          return $f29090;
        })();
        {
          const pk = (() => {
            return $f29089;
          })();
          (() => {
            return Canvas$set_stroke_style(ctx, "#ffffff");
          })();
          (() => {
            return Canvas$set_line_width(ctx, 2.);
          })();
          (() => {
            return Canvas$begin_path(ctx);
          })();
          (() => {
            {
              const $t29086 = pk.x;
              {
                const $t29087 = pk.y;
                return Canvas$arc(ctx, $t29086, $t29087, 8., 0., 6.28318530718);
              }
            }
          })();
          (() => {
            return Canvas$stroke(ctx);
          })();
          return draw_pickups(ctx, rest);
        }
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const draw_pickups$clo = { _0: ($_, ctx, pickups) => draw_pickups(ctx, pickups) };

function draw_runs(ctx, runs, view_w, y, i) {
  {
    const $t29095 = (i >= 5);
    if ($t29095 === true) {
      return {  };
    } else {
      return (() => {
        switch (runs.$) {
          case "Nil": {
            return {  };
            break;
          }
          case "Cons": {
            const $f29110 = runs._0;
            const $f29111 = runs._1;
            {
              const rest = (() => {
                return $f29111;
              })();
              {
                const r = (() => {
                  return $f29110;
                })();
                (() => {
                  return Canvas$set_font(ctx, "14px sans-serif");
                })();
                (() => {
                  {
                    const $t29106 = (() => {
                      {
                        const $t29105 = (() => {
                          {
                            const $t29102 = (() => {
                              {
                                const $t29101 = (() => {
                                  {
                                    const $t29098 = (() => {
                                      {
                                        const $t29097 = (() => {
                                          {
                                            const $t29096 = r.score;
                                            return String($t29096);
                                          }
                                        })();
                                        {
                                          const $rc_840 = ($t29097 + " x");
                                          return $rc_840;
                                        }
                                      }
                                    })();
                                    {
                                      const $t29100 = (() => {
                                        {
                                          const $t29099 = r.max_mult;
                                          return String($t29099);
                                        }
                                      })();
                                      {
                                        const $rc_839 = ($t29098 + $t29100);
                                        return $rc_839;
                                      }
                                    }
                                  }
                                })();
                                {
                                  const $rc_838 = ($t29101 + " · ");
                                  return $rc_838;
                                }
                              }
                            })();
                            {
                              const $t29104 = (() => {
                                {
                                  const $t29103 = r.stars;
                                  return String($t29103);
                                }
                              })();
                              {
                                const $rc_837 = ($t29102 + $t29104);
                                return $rc_837;
                              }
                            }
                          }
                        })();
                        {
                          const $rc_836 = ($t29105 + " stars");
                          return $rc_836;
                        }
                      }
                    })();
                    {
                      const $t29107 = (view_w / 2.);
                      return Canvas$fill_text(ctx, $t29106, $t29107, y);
                    }
                  }
                })();
                {
                  const $t29108 = (y + 20.);
                  {
                    const $t29109 = (i + 1);
                    return draw_runs(ctx, rest, view_w, $t29108, $t29109);
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
const draw_runs$clo = { _0: ($_, ctx, runs, view_w, y, i) => draw_runs(ctx, runs, view_w, y, i) };

function draw_ball(ctx, game) {
  (() => {
    return Canvas$set_fill_style(ctx, "#ffffff");
  })();
  (() => {
    return Canvas$begin_path(ctx);
  })();
  (() => {
    {
      const $t29116 = game.ball_x;
      {
        const $t29117 = game.ball_y;
        return Canvas$arc(ctx, $t29116, $t29117, 6., 0., 6.28318530718);
      }
    }
  })();
  (() => {
    return Canvas$fill(ctx);
  })();
  {
    const $t29119 = game.shield;
    if ($t29119 === true) {
      return (() => {
        (() => {
          return Canvas$set_stroke_style(ctx, "#cccccc");
        })();
        (() => {
          return Canvas$set_line_width(ctx, 2.);
        })();
        (() => {
          return Canvas$begin_path(ctx);
        })();
        (() => {
          {
            const $t29120 = game.ball_x;
            {
              const $t29121 = game.ball_y;
              return Canvas$arc(ctx, $t29120, $t29121, 10., 0., 6.28318530718);
            }
          }
        })();
        return Canvas$stroke(ctx);
      })();
    } else {
      return (() => {
        return {  };
      })();
    }
  }
}
const draw_ball$clo = { _0: ($_, ctx, game) => draw_ball(ctx, game) };

function draw_hud(ctx, game) {
  (() => {
    return Canvas$set_fill_style(ctx, "#eeeeee");
  })();
  (() => {
    return Canvas$set_font(ctx, "18px sans-serif");
  })();
  (() => {
    return Canvas$set_text_align(ctx, "left");
  })();
  (() => {
    {
      const $t29124 = (() => {
        {
          const $t29123 = game.score;
          return String($t29123);
        }
      })();
      return Canvas$fill_text(ctx, $t29124, 14., 28.);
    }
  })();
  (() => {
    return Canvas$set_text_align(ctx, "right");
  })();
  (() => {
    {
      const $t29127 = (() => {
        {
          const $t29126 = (() => {
            {
              const $t29125 = game.best;
              return String($t29125);
            }
          })();
          {
            const $rc_844 = ("best " + $t29126);
            return $rc_844;
          }
        }
      })();
      {
        const $t29129 = (() => {
          {
            const $t29128 = game.view_w;
            return ($t29128 - 14.);
          }
        })();
        return Canvas$fill_text(ctx, $t29127, $t29129, 28.);
      }
    }
  })();
  (() => {
    {
      const $t29131 = (() => {
        {
          const $t29130 = game.multiplier;
          return ($t29130 > 1);
        }
      })();
      if ($t29131 === true) {
        return (() => {
          (() => {
            return Canvas$set_text_align(ctx, "left");
          })();
          {
            const $t29134 = (() => {
              {
                const $t29133 = (() => {
                  {
                    const $t29132 = game.multiplier;
                    return String($t29132);
                  }
                })();
                {
                  const $rc_843 = ("x" + $t29133);
                  return $rc_843;
                }
              }
            })();
            return Canvas$fill_text(ctx, $t29134, 14., 52.);
          }
        })();
      } else {
        return {  };
      }
    }
  })();
  (() => {
    return Canvas$set_text_align(ctx, "center");
  })();
  {
    const $t29135 = game.phase;
    switch ($t29135.$) {
      case "Ready": {
        (() => {
          return Canvas$set_font(ctx, "22px sans-serif");
        })();
        {
          const $t29137 = (() => {
            {
              const $t29136 = game.view_w;
              return ($t29136 / 2.);
            }
          })();
          {
            const $t29139 = (() => {
              {
                const $t29138 = game.view_h;
                return ($t29138 / 2.);
              }
            })();
            return Canvas$fill_text(ctx, "tap to start", $t29137, $t29139);
          }
        }
        break;
      }
      case "Over": {
        (() => {
          return Canvas$set_font(ctx, "22px sans-serif");
        })();
        (() => {
          {
            const $t29143 = (() => {
              {
                const $t29142 = (() => {
                  {
                    const $t29141 = (() => {
                      {
                        const $t29140 = game.score;
                        return String($t29140);
                      }
                    })();
                    {
                      const $rc_842 = ("score " + $t29141);
                      return $rc_842;
                    }
                  }
                })();
                {
                  const $rc_841 = ($t29142 + " — tap to retry");
                  return $rc_841;
                }
              }
            })();
            {
              const $t29145 = (() => {
                {
                  const $t29144 = game.view_w;
                  return ($t29144 / 2.);
                }
              })();
              {
                const $t29147 = (() => {
                  {
                    const $t29146 = game.view_h;
                    return ($t29146 / 2.);
                  }
                })();
                return Canvas$fill_text(ctx, $t29143, $t29145, $t29147);
              }
            }
          }
        })();
        {
          const $t29148 = game.runs;
          {
            const $t29149 = game.view_w;
            {
              const $t29152 = (() => {
                {
                  const $t29151 = (() => {
                    {
                      const $t29150 = game.view_h;
                      return ($t29150 / 2.);
                    }
                  })();
                  return ($t29151 + 36.);
                }
              })();
              return draw_runs(ctx, $t29148, $t29149, $t29152, 0);
            }
          }
        }
        break;
      }
      case "Playing": {
        return {  };
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const draw_hud$clo = { _0: ($_, ctx, game) => draw_hud(ctx, game) };

function draw(ctx, game, fx) {
  (() => {
    return Canvas$set_global_alpha(ctx, 1.);
  })();
  (() => {
    return Canvas$set_fill_style(ctx, "#0a0a0a");
  })();
  (() => {
    {
      const $t29153 = game.view_w;
      {
        const $t29154 = game.view_h;
        return Canvas$fill_rect(ctx, 0., 0., $t29153, $t29154);
      }
    }
  })();
  (() => {
    return Canvas$save(ctx);
  })();
  (() => {
    {
      const $t29156 = (() => {
        {
          const $t29155 = game.camera_x;
          return (0. - $t29155);
        }
      })();
      {
        const $t29158 = (() => {
          {
            const $t29157 = game.camera_y;
            return (0. - $t29157);
          }
        })();
        return Canvas$translate(ctx, $t29156, $t29158);
      }
    }
  })();
  {
    const seedf = (() => {
      {
        const $t29159 = game.seed;
        return $t29159;
      }
    })();
    (() => {
      {
        const $t29160 = game.camera_x;
        {
          const $t29161 = game.camera_y;
          {
            const $t29162 = game.view_w;
            {
              const $t29163 = game.view_h;
              {
                const $t29164 = fx.t;
                return draw_starfield(ctx, $t29160, $t29161, $t29162, $t29163, seedf, $t29164);
              }
            }
          }
        }
      }
    })();
    (() => {
      {
        const $t29165 = game.stars;
        {
          const $t29166 = game.camera_y;
          {
            const $t29167 = game.view_h;
            return draw_nebula(ctx, $t29165, $t29166, $t29167, seedf);
          }
        }
      }
    })();
    {
      const aim = (() => {
        {
          const $t29168 = game.mode;
          switch ($t29168.$) {
            case "Flying": {
              const $f29172 = $t29168._0;
              const $f29173 = $t29168._1;
              {
                const vy = (() => {
                  return $f29173;
                })();
                {
                  const vx = (() => {
                    return $f29172;
                  })();
                  {
                    const $t29171 = (() => {
                      {
                        const $t29169 = game.ball_x;
                        {
                          const $t29170 = game.ball_y;
                          return { _0: $t29169, _1: $t29170, _2: vx, _3: vy };
                        }
                      }
                    })();
                    return { $: "Some", _0: $t29171 };
                  }
                }
              }
              break;
            }
            case "Orbiting": {
              const $f29178 = $t29168._0;
              const $f29179 = $t29168._1;
              const $f29180 = $t29168._2;
              return { $: "None" };
              break;
            }
            default: {
              return (() => { throw new Error("non-exhaustive pattern match"); })();
            }
          }
        }
      })();
      (() => {
        {
          const $t29189 = game.stars;
          {
            const $t29190 = game.camera_y;
            {
              const $t29191 = game.view_h;
              {
                const $t29192 = fx.t;
                {
                  const $rc_845 = (() => {
                    return draw_stars(ctx, $t29189, $t29190, $t29191, $t29192, aim);
                  })();
                  return $rc_845;
                }
              }
            }
          }
        }
      })();
      (() => {
        {
          const $t29193 = fx.flash;
          return draw_flash(ctx, $t29193);
        }
      })();
      (() => {
        {
          const $t29194 = game.asteroids;
          return draw_asteroids(ctx, $t29194);
        }
      })();
      (() => {
        {
          const $t29195 = game.ships;
          return draw_ships(ctx, $t29195);
        }
      })();
      (() => {
        {
          const $t29196 = game.player_shots;
          return draw_shots(ctx, $t29196, "#ffffff", 3.);
        }
      })();
      (() => {
        {
          const $t29197 = game.enemy_shots;
          return draw_shots(ctx, $t29197, "#8a8a94", 2.5);
        }
      })();
      (() => {
        {
          const $t29198 = game.pickups;
          return draw_pickups(ctx, $t29198);
        }
      })();
      (() => {
        {
          const $t29199 = fx.trail;
          return draw_trail(ctx, $t29199, 0, 14);
        }
      })();
      (() => {
        {
          const $t29201 = fx.particles;
          return draw_particles(ctx, $t29201);
        }
      })();
      (() => {
        return Canvas$set_global_alpha(ctx, 1.);
      })();
      (() => {
        return draw_ball(ctx, game);
      })();
      (() => {
        return Canvas$restore(ctx);
      })();
      return draw_hud(ctx, game);
    }
  }
}
const draw$clo = { _0: ($_, ctx, game, fx) => draw(ctx, game, fx) };

function resize_canvas(el, game, w, h) {
  {
    const $t29208 = (() => {
      {
        const $t29205 = (() => {
          {
            const $t29204 = game.view_w;
            return (w === $t29204);
          }
        })();
        {
          const $t29207 = (() => {
            {
              const $t29206 = game.view_h;
              return (h === $t29206);
            }
          })();
          return ($t29205 && $t29207);
        }
      }
    })();
    if ($t29208 === true) {
      return {  };
    } else {
      return (() => {
        (() => {
          {
            const $t29210 = (() => {
              {
                const $t29209 = Math.trunc(w);
                return String($t29209);
              }
            })();
            return Dom$set_attr(el, "width", $t29210);
          }
        })();
        {
          const $t29212 = (() => {
            {
              const $t29211 = Math.trunc(h);
              return String($t29211);
            }
          })();
          return Dom$set_attr(el, "height", $t29212);
        }
      })();
    }
  }
}
const resize_canvas$clo = { _0: ($_, el, game, w, h) => resize_canvas(el, game, w, h) };

function play_sfx(actx, muted, game, g2) {
  if (muted === true) {
    return {  };
  } else {
    return (() => {
      (() => {
        {
          const $t29226 = (() => {
            {
              const $t29224 = (() => {
                {
                  const $t29223 = game.phase;
                  switch ($t29223.$) {
                    case "Ready": {
                      return true;
                      break;
                    }
                    default: {
                      return false;
                    }
                  }
                }
              })();
              {
                const $t29225 = (() => {
                  {
                    const $t29202_i4030 = g2.phase;
                    switch ($t29202_i4030.$) {
                      case "Playing": {
                        return true;
                        break;
                      }
                      default: {
                        return false;
                      }
                    }
                  }
                })();
                return ($t29224 && $t29225);
              }
            }
          })();
          if ($t29226 === true) {
            return (() => {
              return Audio$resume(actx);
            })();
          } else {
            return {  };
          }
        }
      })();
      (() => {
        {
          const $t29231 = (() => {
            {
              const $t29228 = (() => {
                {
                  const $t29227 = game.mode;
                  switch ($t29227.$) {
                    case "Orbiting": {
                      const $f29213_i4026 = $t29227._0;
                      const $f29214_i4027 = $t29227._1;
                      const $f29215_i4028 = $t29227._2;
                      return true;
                      break;
                    }
                    default: {
                      return false;
                    }
                  }
                }
              })();
              {
                const $t29230 = (() => {
                  {
                    const $t29229 = g2.mode;
                    switch ($t29229.$) {
                      case "Flying": {
                        const $f29216_i4023 = $t29229._0;
                        const $f29217_i4024 = $t29229._1;
                        return true;
                        break;
                      }
                      default: {
                        return false;
                      }
                    }
                  }
                })();
                return ($t29228 && $t29230);
              }
            }
          })();
          if ($t29231 === true) {
            return (() => {
              return Audio$beep(actx, 500., 0.04, "square");
            })();
          } else {
            return {  };
          }
        }
      })();
      (() => {
        {
          const $t29232 = g2.capture_flash;
          switch ($t29232.$) {
            case "None": {
              return {  };
              break;
            }
            case "Some": {
              const $f29233 = $t29232._0;
              return Audio$sweep(actx, 400., 900., 0.12, "sine");
              break;
            }
            default: {
              return (() => { throw new Error("non-exhaustive pattern match"); })();
            }
          }
        }
      })();
      (() => {
        {
          const $t29238 = (() => {
            {
              const $t29235 = (() => {
                {
                  const $t29234 = g2.player_shots;
                  {
                    const go_i4020 = { $: "$Clo_go$4759", _0: go$apply$4759 };
                    return go$apply$4759(go_i4020, $t29234, 0);
                  }
                }
              })();
              {
                const $t29237 = (() => {
                  {
                    const $t29236 = game.player_shots;
                    {
                      const go_i4018 = { $: "$Clo_go$4759", _0: go$apply$4759 };
                      return go$apply$4759(go_i4018, $t29236, 0);
                    }
                  }
                })();
                return ($t29235 > $t29237);
              }
            }
          })();
          if ($t29238 === true) {
            return (() => {
              return Audio$beep(actx, 900., 0.05, "square");
            })();
          } else {
            return {  };
          }
        }
      })();
      (() => {
        {
          const $t29243 = (() => {
            {
              const $t29240 = (() => {
                {
                  const $t29239 = g2.enemy_shots;
                  {
                    const go_i4016 = { $: "$Clo_go$4759", _0: go$apply$4759 };
                    return go$apply$4759(go_i4016, $t29239, 0);
                  }
                }
              })();
              {
                const $t29242 = (() => {
                  {
                    const $t29241 = game.enemy_shots;
                    {
                      const go_i4014 = { $: "$Clo_go$4759", _0: go$apply$4759 };
                      return go$apply$4759(go_i4014, $t29241, 0);
                    }
                  }
                })();
                return ($t29240 > $t29242);
              }
            }
          })();
          if ($t29243 === true) {
            return (() => {
              return Audio$beep(actx, 500., 0.05, "sawtooth");
            })();
          } else {
            return {  };
          }
        }
      })();
      (() => {
        {
          const $t29246 = (() => {
            {
              const $t29245 = (() => {
                {
                  const $t29244 = g2.fx_bursts;
                  switch ($t29244.$) {
                    case "Nil": {
                      return true;
                      break;
                    }
                    default: {
                      return false;
                    }
                  }
                }
              })();
              return (!$t29245);
            }
          })();
          if ($t29246 === true) {
            return (() => {
              return Audio$noise_burst(actx, 0.2, 900.);
            })();
          } else {
            return {  };
          }
        }
      })();
      (() => {
        {
          const $t29251 = (() => {
            {
              const $t29248 = (() => {
                {
                  const $t29247 = g2.ships;
                  {
                    const go_i4011 = { $: "$Clo_go$4727", _0: go$apply$4727 };
                    return go$apply$4727(go_i4011, $t29247, 0);
                  }
                }
              })();
              {
                const $t29250 = (() => {
                  {
                    const $t29249 = game.ships;
                    {
                      const go_i4009 = { $: "$Clo_go$4727", _0: go$apply$4727 };
                      return go$apply$4727(go_i4009, $t29249, 0);
                    }
                  }
                })();
                return ($t29248 < $t29250);
              }
            }
          })();
          if ($t29251 === true) {
            return (() => {
              return Audio$noise_burst(actx, 0.3, 400.);
            })();
          } else {
            return {  };
          }
        }
      })();
      (() => {
        {
          const $t29255 = (() => {
            {
              const $t29253 = (() => {
                {
                  const $t29252 = game.shield;
                  return (!$t29252);
                }
              })();
              {
                const $t29254 = g2.shield;
                return ($t29253 && $t29254);
              }
            }
          })();
          if ($t29255 === true) {
            return (() => {
              return Audio$beep(actx, 700., 0.06, "sine");
            })();
          } else {
            return {  };
          }
        }
      })();
      {
        const $t29258 = (() => {
          {
            const $t29256 = (() => {
              {
                const $t29202_i4007 = game.phase;
                switch ($t29202_i4007.$) {
                  case "Playing": {
                    return true;
                    break;
                  }
                  default: {
                    return false;
                  }
                }
              }
            })();
            {
              const $t29257 = (() => {
                {
                  const $t29203_i4005 = g2.phase;
                  switch ($t29203_i4005.$) {
                    case "Over": {
                      return true;
                      break;
                    }
                    default: {
                      return false;
                    }
                  }
                }
              })();
              return ($t29256 && $t29257);
            }
          }
        })();
        if ($t29258 === true) {
          return Audio$sweep(actx, 300., 60., 0.5, "sawtooth");
        } else {
          return (() => {
            return {  };
          })();
        }
      }
    })();
  }
}
const play_sfx$clo = { _0: ($_, actx, muted, game, g2) => play_sfx(actx, muted, game, g2) };

function tick(ctx, el, game, fx) {
  {
    const taps = (() => {
      return Dom$taps(el);
    })();
    {
      const keys = dom_key_presses();
      {
        const cursor = (() => {
          return Dom$pointer_pos(el);
        })();
        {
          const $p29271 = dom_window_size();
          {
            const win_w = $p29271._0;
            {
              const win_h = $p29271._1;
              {
                const view_w = win_w;
                {
                  const view_h = win_h;
                  (() => {
                    return resize_canvas(el, game, view_w, view_h);
                  })();
                  {
                    const g2 = (() => {
                      {
                        const $rc_846 = (() => {
                          return Perihelion$Core$update(game, taps, keys, cursor, view_w, view_h, 0.0166667);
                        })();
                        return $rc_846;
                      }
                    })();
                    {
                      const muted2 = (() => {
                        {
                          const $t29260 = fx.muted;
                          {
                            const $t29222_i4039 = (() => {
                              {
                                const $t29221_i4038 = { $: "$Clo_$lam29218$3775", _0: $lam29218$apply$3775 };
                                return List$any$List_String$Fn_String_Bool(keys, $t29221_i4038);
                              }
                            })();
                            if ($t29222_i4039 === true) {
                              return (!$t29260);
                            } else {
                              return $t29260;
                            }
                          }
                        }
                      })();
                      (() => {
                        {
                          const $t29261 = fx.actx;
                          return play_sfx($t29261, muted2, game, g2);
                        }
                      })();
                      {
                        const fx1 = step_fx(fx, g2, 0.0166667);
                        {
                          const fx2 = ({ ...fx1, muted: muted2 });
                          (() => {
                            {
                              const $t29265 = (() => {
                                {
                                  const $t29263 = (() => {
                                    {
                                      const $t29202_i4035 = game.phase;
                                      switch ($t29202_i4035.$) {
                                        case "Playing": {
                                          return true;
                                          break;
                                        }
                                        default: {
                                          return false;
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t29264 = (() => {
                                      {
                                        const $t29203_i4033 = g2.phase;
                                        switch ($t29203_i4033.$) {
                                          case "Over": {
                                            return true;
                                            break;
                                          }
                                          default: {
                                            return false;
                                          }
                                        }
                                      }
                                    })();
                                    return ($t29263 && $t29264);
                                  }
                                }
                              })();
                              if ($t29265 === true) {
                                return (() => {
                                  {
                                    const $t29268 = (() => {
                                      {
                                        const $t29266 = g2.best;
                                        {
                                          const $t29267 = g2.runs;
                                          return Perihelion$Core$encode_save($t29266, $t29267);
                                        }
                                      }
                                    })();
                                    return Dom$store_set("perihelion.v1", $t29268);
                                  }
                                })();
                              } else {
                                return {  };
                              }
                            }
                          })();
                          (() => {
                            return draw(ctx, g2, fx2);
                          })();
                          {
                            const $t29270 = { $: "$Clo_$lam29269$3776", _0: $lam29269$apply$3776, _1: ctx, _2: el, _3: fx2, _4: g2 };
                            return Dom$on_frame($t29270);
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
const tick$clo = { _0: ($_, ctx, el, game, fx) => tick(ctx, el, game, fx) };

function boot(ctx, node, best, runs) {
  {
    const $p29277 = dom_window_size();
    {
      const win_w = $p29277._0;
      {
        const win_h = $p29277._1;
        {
          const view_w = win_w;
          {
            const view_h = win_h;
            (() => {
              {
                const $t29272 = String(win_w);
                return Dom$set_attr(node, "width", $t29272);
              }
            })();
            (() => {
              {
                const $t29273 = String(win_h);
                return Dom$set_attr(node, "height", $t29273);
              }
            })();
            {
              const $t29275 = (() => {
                {
                  const $t29274 = boot_seed();
                  return Perihelion$Core$fresh_run($t29274, best, runs, view_w, view_h);
                }
              })();
              {
                const $t29276 = (() => {
                  {
                    const $t28670_i10002 = { $: "Nil" };
                    {
                      const $t28671_i10003 = { $: "Nil" };
                      {
                        const $t28672_i10004 = { $: "None" };
                        {
                          const $t28673_i10005 = audio_create();
                          return ({ trail: $t28670_i10002, t: 0., particles: $t28671_i10003, flash: $t28672_i10004, actx: $t28673_i10005, muted: false });
                        }
                      }
                    }
                  }
                })();
                return tick(ctx, node, $t29275, $t29276);
              }
            }
          }
        }
      }
    }
  }
}
const boot$clo = { _0: ($_, ctx, node, best, runs) => boot(ctx, node, best, runs) };

function main() {
  {
    const $t29278 = Dom$find("game-canvas");
    switch ($t29278.$) {
      case "None": {
        return println$String("no #game-canvas found");
        break;
      }
      case "Some": {
        const $f29286 = $t29278._0;
        {
          const node = $f29286;
          {
            const $t29279 = (() => {
              return Canvas$get_context(node);
            })();
            switch ($t29279.$) {
              case "None": {
                return println$String("2d context unavailable");
                break;
              }
              case "Some": {
                const $f29285 = $t29279._0;
                {
                  const ctx = $f29285;
                  {
                    const saved = (() => {
                      {
                        const $t29280 = Dom$store_get("perihelion.v1");
                        switch ($t29280.$) {
                          case "None": {
                            return "";
                            break;
                          }
                          case "Some": {
                            const $f29281 = $t29280._0;
                            {
                              const sv = $f29281;
                              return sv;
                            }
                            break;
                          }
                          default: {
                            return (() => { throw new Error("non-exhaustive pattern match"); })();
                          }
                        }
                      }
                    })();
                    {
                      const $p29284 = (() => {
                        {
                          const $rc_847 = Perihelion$Core$decode_save(saved);
                          return $rc_847;
                        }
                      })();
                      {
                        const best = $p29284._0;
                        {
                          const runs = $p29284._1;
                          {
                            const $t29283 = (() => {
                              return { $: "$Clo_$lam29282$3777", _0: $lam29282$apply$3777, _1: best, _2: ctx, _3: node, _4: runs };
                            })();
                            return Dom$on_frame($t29283);
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const main$clo = { _0: ($_) => main() };

function println$String(x) {
  (() => {
    {
      const $t104 = x;
      {
        const $rc_854 = march_print(x);
        return $rc_854;
      }
    }
  })();
  return march_print("\n");
}
const println$String$clo = { _0: ($_, x) => println$String(x) };

function List$any$List_String$Fn_String_Bool(xs, pred) {
  switch (xs.$) {
    case "Nil": {
      return false;
      break;
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
              return List$any$List_String$Fn_String_Bool(t, pred);
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
const List$any$List_String$Fn_String_Bool$clo = { _0: ($_, xs, pred) => List$any$List_String$Fn_String_Bool(xs, pred) };

function List$any$List_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float_Bool(xs, pred) {
  switch (xs.$) {
    case "Nil": {
      return false;
      break;
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
              return List$any$List_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float_Bool(t, pred);
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
const List$any$List_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float_Bool$clo = { _0: ($_, xs, pred) => List$any$List_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float_Bool(xs, pred) };

function List$any$List_R_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool(xs, pred) {
  switch (xs.$) {
    case "Nil": {
      return false;
      break;
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
              return List$any$List_R_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool(t, pred);
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
const List$any$List_R_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool$clo = { _0: ($_, xs, pred) => List$any$List_R_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool(xs, pred) };

function List$any$List_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float$Fn_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float_Bool(xs, pred) {
  switch (xs.$) {
    case "Nil": {
      return false;
      break;
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
              return List$any$List_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float$Fn_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float_Bool(t, pred);
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
const List$any$List_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float$Fn_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float_Bool$clo = { _0: ($_, xs, pred) => List$any$List_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float$Fn_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float_Bool(xs, pred) };

function List$any$List_R_ttl_Float_x_Float_y_Float$Fn_R_ttl_Float_x_Float_y_Float_Bool(xs, pred) {
  switch (xs.$) {
    case "Nil": {
      return false;
      break;
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
              return List$any$List_R_ttl_Float_x_Float_y_Float$Fn_R_ttl_Float_x_Float_y_Float_Bool(t, pred);
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
const List$any$List_R_ttl_Float_x_Float_y_Float$Fn_R_ttl_Float_x_Float_y_Float_Bool$clo = { _0: ($_, xs, pred) => List$any$List_R_ttl_Float_x_Float_y_Float$Fn_R_ttl_Float_x_Float_y_Float_Bool(xs, pred) };

function List$nth_opt$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int(xs, n) {
  switch (xs.$) {
    case "Nil": {
      return { $: "None" };
      break;
    }
    case "Cons": {
      const $f230 = xs._0;
      const $f231 = xs._1;
      {
        const t = $f231;
        {
          const h = $f230;
          {
            const $t228 = (n === 0);
            if ($t228 === true) {
              return { $: "Some", _0: h };
            } else {
              return (() => {
                {
                  const $t229 = (n - 1);
                  return List$nth_opt$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int(t, $t229);
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
const List$nth_opt$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int$clo = { _0: ($_, xs, n) => List$nth_opt$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int(xs, n) };

function List$nth_opt$List_R_radius_Float_speed_mult_Float$Int(xs, n) {
  switch (xs.$) {
    case "Nil": {
      return { $: "None" };
      break;
    }
    case "Cons": {
      const $f230 = xs._0;
      const $f231 = xs._1;
      {
        const t = $f231;
        {
          const h = $f230;
          {
            const $t228 = (n === 0);
            if ($t228 === true) {
              return { $: "Some", _0: h };
            } else {
              return (() => {
                {
                  const $t229 = (n - 1);
                  return List$nth_opt$List_R_radius_Float_speed_mult_Float$Int(t, $t229);
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
const List$nth_opt$List_R_radius_Float_speed_mult_Float$Int$clo = { _0: ($_, xs, n) => List$nth_opt$List_R_radius_Float_speed_mult_Float$Int(xs, n) };

function $lam27401$apply$3670($clo, s) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const $t27393_i7534 = (() => {
        {
          const $t27390_i7531 = s.x;
          {
            const $t27392_i7533 = (() => {
              {
                const $t27391_i7532 = s.vx;
                return ($t27391_i7532 * dt_s);
              }
            })();
            return ($t27390_i7531 + $t27392_i7533);
          }
        }
      })();
      {
        const $t27397_i7538 = (() => {
          {
            const $t27394_i7535 = s.y;
            {
              const $t27396_i7537 = (() => {
                {
                  const $t27395_i7536 = s.vy;
                  return ($t27395_i7536 * dt_s);
                }
              })();
              return ($t27394_i7535 + $t27396_i7537);
            }
          }
        })();
        {
          const $t27399_i7540 = (() => {
            {
              const $t27398_i7539 = s.ttl;
              return ($t27398_i7539 - dt_s);
            }
          })();
          return ({ ...s, x: $t27393_i7534, y: $t27397_i7538, ttl: $t27399_i7540 });
        }
      }
    }
  }
}
const $lam27401$apply$3670$clo = { _0: ($_, $clo, s) => $lam27401$apply$3670($clo, s) };

function $lam27404$apply$3671($clo, s) {
  {
    const g1 = (() => {
      return $clo._1;
    })();
    {
      const $t27406 = (() => {
        {
          const $t27405 = s.ttl;
          return ($t27405 > 0.);
        }
      })();
      {
        const $t27409 = (() => {
          {
            const $t27407 = s.x;
            {
              const $t27408 = s.y;
              return Perihelion$Combat$in_band(g1, $t27407, $t27408);
            }
          }
        })();
        return ($t27406 && $t27409);
      }
    }
  }
}
const $lam27404$apply$3671$clo = { _0: ($_, $clo, s) => $lam27404$apply$3671($clo, s) };

function $lam27412$apply$3672($clo, s) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const $t27393_i7546 = (() => {
        {
          const $t27390_i7543 = s.x;
          {
            const $t27392_i7545 = (() => {
              {
                const $t27391_i7544 = s.vx;
                return ($t27391_i7544 * dt_s);
              }
            })();
            return ($t27390_i7543 + $t27392_i7545);
          }
        }
      })();
      {
        const $t27397_i7550 = (() => {
          {
            const $t27394_i7547 = s.y;
            {
              const $t27396_i7549 = (() => {
                {
                  const $t27395_i7548 = s.vy;
                  return ($t27395_i7548 * dt_s);
                }
              })();
              return ($t27394_i7547 + $t27396_i7549);
            }
          }
        })();
        {
          const $t27399_i7552 = (() => {
            {
              const $t27398_i7551 = s.ttl;
              return ($t27398_i7551 - dt_s);
            }
          })();
          return ({ ...s, x: $t27393_i7546, y: $t27397_i7550, ttl: $t27399_i7552 });
        }
      }
    }
  }
}
const $lam27412$apply$3672$clo = { _0: ($_, $clo, s) => $lam27412$apply$3672($clo, s) };

function $lam27415$apply$3673($clo, s) {
  {
    const g1 = (() => {
      return $clo._1;
    })();
    {
      const $t27417 = (() => {
        {
          const $t27416 = s.ttl;
          return ($t27416 > 0.);
        }
      })();
      {
        const $t27420 = (() => {
          {
            const $t27418 = s.x;
            {
              const $t27419 = s.y;
              return Perihelion$Combat$in_band(g1, $t27418, $t27419);
            }
          }
        })();
        return ($t27417 && $t27420);
      }
    }
  }
}
const $lam27415$apply$3673$clo = { _0: ($_, $clo, s) => $lam27415$apply$3673($clo, s) };

function $lam27423$apply$3674($clo, p) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const $t27425 = (() => {
        {
          const $t27424 = p.ttl;
          return ($t27424 - dt_s);
        }
      })();
      return ({ ...p, ttl: $t27425 });
    }
  }
}
const $lam27423$apply$3674$clo = { _0: ($_, $clo, p) => $lam27423$apply$3674($clo, p) };

function $lam27428$apply$3675($clo, p) {
  {
    const $t27429 = p.ttl;
    return ($t27429 > 0.);
  }
}
const $lam27428$apply$3675$clo = { _0: ($_, $clo, p) => $lam27428$apply$3675($clo, p) };

function $lam27780$apply$3691($clo, k) {
  return (k === " ");
}
const $lam27780$apply$3691$clo = { _0: ($_, $clo, k) => $lam27780$apply$3691($clo, k) };

function $lam27814$apply$3692($clo, a) {
  {
    const $t27815 = a.x;
    {
      const $t27816 = a.y;
      return { _0: $t27815, _1: $t27816 };
    }
  }
}
const $lam27814$apply$3692$clo = { _0: ($_, $clo, a) => $lam27814$apply$3692($clo, a) };

function $lam27819$apply$3693($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t27820 = game.player_shots;
      {
        const $t27825 = { $: "$Clo_$lam27821$3694", _0: $lam27821$apply$3694, _1: a };
        return List$any$List_R_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t27820, $t27825);
      }
    }
  }
}
const $lam27819$apply$3693$clo = { _0: ($_, $clo, a) => $lam27819$apply$3693($clo, a) };

function $lam27821$apply$3694($clo, s) {
  {
    const a = (() => {
      return $clo._1;
    })();
    {
      const $t27822 = a.x;
      {
        const $t27823 = a.y;
        {
          const $t27824 = a.radius;
          {
            const $t27811_i10236 = s.x;
            {
              const $t27812_i10237 = s.y;
              {
                const $t27343_i9676_i10242 = (() => {
                  {
                    const dx_i3630_i9672_i10238 = ($t27822 - $t27811_i10236);
                    {
                      const dy_i3631_i9673_i10239 = ($t27823 - $t27812_i10237);
                      {
                        const $t27341_i3632_i9674_i10240 = (dx_i3630_i9672_i10238 * dx_i3630_i9672_i10238);
                        {
                          const $t27342_i3633_i9675_i10241 = (dy_i3631_i9673_i10239 * dy_i3631_i9673_i10239);
                          return ($t27341_i3632_i9674_i10240 + $t27342_i3633_i9675_i10241);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27346_i9679_i10245 = (() => {
                    {
                      const $t27344_i9677_i10243 = (3. + $t27824);
                      {
                        const $t27345_i9678_i10244 = (3. + $t27824);
                        return ($t27344_i9677_i10243 * $t27345_i9678_i10244);
                      }
                    }
                  })();
                  return ($t27343_i9676_i10242 <= $t27346_i9679_i10245);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam27821$apply$3694$clo = { _0: ($_, $clo, s) => $lam27821$apply$3694($clo, s) };

function $lam27828$apply$3695($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t27835 = (() => {
        {
          const $t27829 = game.asteroids;
          {
            const $t27834 = { $: "$Clo_$lam27830$3696", _0: $lam27830$apply$3696, _1: s };
            return List$any$List_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t27829, $t27834);
          }
        }
      })();
      return (!$t27835);
    }
  }
}
const $lam27828$apply$3695$clo = { _0: ($_, $clo, s) => $lam27828$apply$3695($clo, s) };

function $lam27830$apply$3696($clo, a) {
  {
    const s = (() => {
      return $clo._1;
    })();
    {
      const $t27831 = a.x;
      {
        const $t27832 = a.y;
        {
          const $t27833 = a.radius;
          {
            const $t27811_i10250 = s.x;
            {
              const $t27812_i10251 = s.y;
              {
                const $t27343_i9676_i10256 = (() => {
                  {
                    const dx_i3630_i9672_i10252 = ($t27831 - $t27811_i10250);
                    {
                      const dy_i3631_i9673_i10253 = ($t27832 - $t27812_i10251);
                      {
                        const $t27341_i3632_i9674_i10254 = (dx_i3630_i9672_i10252 * dx_i3630_i9672_i10252);
                        {
                          const $t27342_i3633_i9675_i10255 = (dy_i3631_i9673_i10253 * dy_i3631_i9673_i10253);
                          return ($t27341_i3632_i9674_i10254 + $t27342_i3633_i9675_i10255);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27346_i9679_i10259 = (() => {
                    {
                      const $t27344_i9677_i10257 = (3. + $t27833);
                      {
                        const $t27345_i9678_i10258 = (3. + $t27833);
                        return ($t27344_i9677_i10257 * $t27345_i9678_i10258);
                      }
                    }
                  })();
                  return ($t27343_i9676_i10256 <= $t27346_i9679_i10259);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam27830$apply$3696$clo = { _0: ($_, $clo, a) => $lam27830$apply$3696($clo, a) };

function $lam27847$apply$3697($clo, sh) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t27848 = game.player_shots;
      {
        const $t27850 = { $: "$Clo_$lam27849$3698", _0: $lam27849$apply$3698, _1: sh };
        return List$any$List_R_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t27848, $t27850);
      }
    }
  }
}
const $lam27847$apply$3697$clo = { _0: ($_, $clo, sh) => $lam27847$apply$3697($clo, sh) };

function $lam27849$apply$3698($clo, s) {
  {
    const sh = (() => {
      return $clo._1;
    })();
    return Perihelion$Combat$ship_shot_hit(sh, s);
  }
}
const $lam27849$apply$3698$clo = { _0: ($_, $clo, s) => $lam27849$apply$3698($clo, s) };

function $lam27853$apply$3699($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t27857 = (() => {
        {
          const $t27854 = game.ships;
          {
            const $t27856 = { $: "$Clo_$lam27855$3700", _0: $lam27855$apply$3700, _1: s };
            return List$any$List_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float$Fn_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float_Bool($t27854, $t27856);
          }
        }
      })();
      return (!$t27857);
    }
  }
}
const $lam27853$apply$3699$clo = { _0: ($_, $clo, s) => $lam27853$apply$3699($clo, s) };

function $lam27855$apply$3700($clo, sh) {
  {
    const s = (() => {
      return $clo._1;
    })();
    return Perihelion$Combat$ship_shot_hit(sh, s);
  }
}
const $lam27855$apply$3700$clo = { _0: ($_, $clo, sh) => $lam27855$apply$3700($clo, sh) };

function $lam27889$apply$3702($clo, p) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t27881_i10262 = p.x;
      {
        const $t27882_i10263 = p.y;
        {
          const $t27884_i10264 = game.ball_x;
          {
            const $t27885_i10265 = game.ball_y;
            {
              const $t27343_i9695_i10270 = (() => {
                {
                  const dx_i3630_i9691_i10266 = ($t27884_i10264 - $t27881_i10262);
                  {
                    const dy_i3631_i9692_i10267 = ($t27885_i10265 - $t27882_i10263);
                    {
                      const $t27341_i3632_i9693_i10268 = (dx_i3630_i9691_i10266 * dx_i3630_i9691_i10266);
                      {
                        const $t27342_i3633_i9694_i10269 = (dy_i3631_i9692_i10267 * dy_i3631_i9692_i10267);
                        return ($t27341_i3632_i9693_i10268 + $t27342_i3633_i9694_i10269);
                      }
                    }
                  }
                }
              })();
              {
                const $t27346_i9698_i10273 = (() => {
                  {
                    const $t27344_i9696_i10271 = (12. + 6.);
                    {
                      const $t27345_i9697_i10272 = (12. + 6.);
                      return ($t27344_i9696_i10271 * $t27345_i9697_i10272);
                    }
                  }
                })();
                return ($t27343_i9695_i10270 <= $t27346_i9698_i10273);
              }
            }
          }
        }
      }
    }
  }
}
const $lam27889$apply$3702$clo = { _0: ($_, $clo, p) => $lam27889$apply$3702($clo, p) };

function $lam27892$apply$3703($clo, p) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t27893 = (() => {
        {
          const $t27881_i10276 = p.x;
          {
            const $t27882_i10277 = p.y;
            {
              const $t27884_i10278 = game.ball_x;
              {
                const $t27885_i10279 = game.ball_y;
                {
                  const $t27343_i9695_i10284 = (() => {
                    {
                      const dx_i3630_i9691_i10280 = ($t27884_i10278 - $t27881_i10276);
                      {
                        const dy_i3631_i9692_i10281 = ($t27885_i10279 - $t27882_i10277);
                        {
                          const $t27341_i3632_i9693_i10282 = (dx_i3630_i9691_i10280 * dx_i3630_i9691_i10280);
                          {
                            const $t27342_i3633_i9694_i10283 = (dy_i3631_i9692_i10281 * dy_i3631_i9692_i10281);
                            return ($t27341_i3632_i9693_i10282 + $t27342_i3633_i9694_i10283);
                          }
                        }
                      }
                    }
                  })();
                  {
                    const $t27346_i9698_i10287 = (() => {
                      {
                        const $t27344_i9696_i10285 = (12. + 6.);
                        {
                          const $t27345_i9697_i10286 = (12. + 6.);
                          return ($t27344_i9696_i10285 * $t27345_i9697_i10286);
                        }
                      }
                    })();
                    return ($t27343_i9695_i10284 <= $t27346_i9698_i10287);
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t27893);
    }
  }
}
const $lam27892$apply$3703$clo = { _0: ($_, $clo, p) => $lam27892$apply$3703($clo, p) };

function $lam27911$apply$3704($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t27901_i10290 = a.x;
      {
        const $t27902_i10291 = a.y;
        {
          const $t27903_i10292 = a.radius;
          {
            const $t27904_i10293 = game.ball_x;
            {
              const $t27905_i10294 = game.ball_y;
              {
                const $t27343_i9723_i10299 = (() => {
                  {
                    const dx_i3630_i9719_i10295 = ($t27904_i10293 - $t27901_i10290);
                    {
                      const dy_i3631_i9720_i10296 = ($t27905_i10294 - $t27902_i10291);
                      {
                        const $t27341_i3632_i9721_i10297 = (dx_i3630_i9719_i10295 * dx_i3630_i9719_i10295);
                        {
                          const $t27342_i3633_i9722_i10298 = (dy_i3631_i9720_i10296 * dy_i3631_i9720_i10296);
                          return ($t27341_i3632_i9721_i10297 + $t27342_i3633_i9722_i10298);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27346_i9726_i10302 = (() => {
                    {
                      const $t27344_i9724_i10300 = ($t27903_i10292 + 6.);
                      {
                        const $t27345_i9725_i10301 = ($t27903_i10292 + 6.);
                        return ($t27344_i9724_i10300 * $t27345_i9725_i10301);
                      }
                    }
                  })();
                  return ($t27343_i9723_i10299 <= $t27346_i9726_i10302);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam27911$apply$3704$clo = { _0: ($_, $clo, a) => $lam27911$apply$3704($clo, a) };

function $lam27914$apply$3705($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t27907_i10354 = game.ball_x;
      {
        const $t27908_i10355 = game.ball_y;
        {
          const $t27811_i10024_i10356 = s.x;
          {
            const $t27812_i10025_i10357 = s.y;
            {
              const $t27343_i9676_i10030_i10362 = (() => {
                {
                  const dx_i3630_i9672_i10026_i10358 = ($t27907_i10354 - $t27811_i10024_i10356);
                  {
                    const dy_i3631_i9673_i10027_i10359 = ($t27908_i10355 - $t27812_i10025_i10357);
                    {
                      const $t27341_i3632_i9674_i10028_i10360 = (dx_i3630_i9672_i10026_i10358 * dx_i3630_i9672_i10026_i10358);
                      {
                        const $t27342_i3633_i9675_i10029_i10361 = (dy_i3631_i9673_i10027_i10359 * dy_i3631_i9673_i10027_i10359);
                        return ($t27341_i3632_i9674_i10028_i10360 + $t27342_i3633_i9675_i10029_i10361);
                      }
                    }
                  }
                }
              })();
              {
                const $t27346_i9679_i10033_i10365 = (() => {
                  {
                    const $t27344_i9677_i10031_i10363 = (3. + 6.);
                    {
                      const $t27345_i9678_i10032_i10364 = (3. + 6.);
                      return ($t27344_i9677_i10031_i10363 * $t27345_i9678_i10032_i10364);
                    }
                  }
                })();
                return ($t27343_i9676_i10030_i10362 <= $t27346_i9679_i10033_i10365);
              }
            }
          }
        }
      }
    }
  }
}
const $lam27914$apply$3705$clo = { _0: ($_, $clo, s) => $lam27914$apply$3705($clo, s) };

function $lam27917$apply$3706($clo, sh) {
  {
    const game = (() => {
      return $clo._1;
    })();
    return Perihelion$Combat$ball_hits_ship(game, sh);
  }
}
const $lam27917$apply$3706$clo = { _0: ($_, $clo, sh) => $lam27917$apply$3706($clo, sh) };

function $lam27924$apply$3707($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t27901_i10305 = a.x;
      {
        const $t27902_i10306 = a.y;
        {
          const $t27903_i10307 = a.radius;
          {
            const $t27904_i10308 = game.ball_x;
            {
              const $t27905_i10309 = game.ball_y;
              {
                const $t27343_i9723_i10314 = (() => {
                  {
                    const dx_i3630_i9719_i10310 = ($t27904_i10308 - $t27901_i10305);
                    {
                      const dy_i3631_i9720_i10311 = ($t27905_i10309 - $t27902_i10306);
                      {
                        const $t27341_i3632_i9721_i10312 = (dx_i3630_i9719_i10310 * dx_i3630_i9719_i10310);
                        {
                          const $t27342_i3633_i9722_i10313 = (dy_i3631_i9720_i10311 * dy_i3631_i9720_i10311);
                          return ($t27341_i3632_i9721_i10312 + $t27342_i3633_i9722_i10313);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27346_i9726_i10317 = (() => {
                    {
                      const $t27344_i9724_i10315 = ($t27903_i10307 + 6.);
                      {
                        const $t27345_i9725_i10316 = ($t27903_i10307 + 6.);
                        return ($t27344_i9724_i10315 * $t27345_i9725_i10316);
                      }
                    }
                  })();
                  return ($t27343_i9723_i10314 <= $t27346_i9726_i10317);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam27924$apply$3707$clo = { _0: ($_, $clo, a) => $lam27924$apply$3707($clo, a) };

function $lam27927$apply$3708($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t27928 = (() => {
        {
          const $t27901_i10320 = a.x;
          {
            const $t27902_i10321 = a.y;
            {
              const $t27903_i10322 = a.radius;
              {
                const $t27904_i10323 = game.ball_x;
                {
                  const $t27905_i10324 = game.ball_y;
                  {
                    const $t27343_i9723_i10329 = (() => {
                      {
                        const dx_i3630_i9719_i10325 = ($t27904_i10323 - $t27901_i10320);
                        {
                          const dy_i3631_i9720_i10326 = ($t27905_i10324 - $t27902_i10321);
                          {
                            const $t27341_i3632_i9721_i10327 = (dx_i3630_i9719_i10325 * dx_i3630_i9719_i10325);
                            {
                              const $t27342_i3633_i9722_i10328 = (dy_i3631_i9720_i10326 * dy_i3631_i9720_i10326);
                              return ($t27341_i3632_i9721_i10327 + $t27342_i3633_i9722_i10328);
                            }
                          }
                        }
                      }
                    })();
                    {
                      const $t27346_i9726_i10332 = (() => {
                        {
                          const $t27344_i9724_i10330 = ($t27903_i10322 + 6.);
                          {
                            const $t27345_i9725_i10331 = ($t27903_i10322 + 6.);
                            return ($t27344_i9724_i10330 * $t27345_i9725_i10331);
                          }
                        }
                      })();
                      return ($t27343_i9723_i10329 <= $t27346_i9726_i10332);
                    }
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t27928);
    }
  }
}
const $lam27927$apply$3708$clo = { _0: ($_, $clo, a) => $lam27927$apply$3708($clo, a) };

function $lam27932$apply$3709($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t27933 = (() => {
        {
          const $t27907_i10368 = game.ball_x;
          {
            const $t27908_i10369 = game.ball_y;
            {
              const $t27811_i10024_i10370 = s.x;
              {
                const $t27812_i10025_i10371 = s.y;
                {
                  const $t27343_i9676_i10030_i10376 = (() => {
                    {
                      const dx_i3630_i9672_i10026_i10372 = ($t27907_i10368 - $t27811_i10024_i10370);
                      {
                        const dy_i3631_i9673_i10027_i10373 = ($t27908_i10369 - $t27812_i10025_i10371);
                        {
                          const $t27341_i3632_i9674_i10028_i10374 = (dx_i3630_i9672_i10026_i10372 * dx_i3630_i9672_i10026_i10372);
                          {
                            const $t27342_i3633_i9675_i10029_i10375 = (dy_i3631_i9673_i10027_i10373 * dy_i3631_i9673_i10027_i10373);
                            return ($t27341_i3632_i9674_i10028_i10374 + $t27342_i3633_i9675_i10029_i10375);
                          }
                        }
                      }
                    }
                  })();
                  {
                    const $t27346_i9679_i10033_i10379 = (() => {
                      {
                        const $t27344_i9677_i10031_i10377 = (3. + 6.);
                        {
                          const $t27345_i9678_i10032_i10378 = (3. + 6.);
                          return ($t27344_i9677_i10031_i10377 * $t27345_i9678_i10032_i10378);
                        }
                      }
                    })();
                    return ($t27343_i9676_i10030_i10376 <= $t27346_i9679_i10033_i10379);
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t27933);
    }
  }
}
const $lam27932$apply$3709$clo = { _0: ($_, $clo, s) => $lam27932$apply$3709($clo, s) };

function $lam27937$apply$3710($clo, sh) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t27938 = Perihelion$Combat$ball_hits_ship(game, sh);
      return (!$t27938);
    }
  }
}
const $lam27937$apply$3710$clo = { _0: ($_, $clo, sh) => $lam27937$apply$3710($clo, sh) };

function $lam28014$apply$3711($clo, k) {
  {
    const $t28015 = (() => {
      return (k === "w");
    })();
    {
      const $t28016 = (k === "W");
      return ($t28015 || $t28016);
    }
  }
}
const $lam28014$apply$3711$clo = { _0: ($_, $clo, k) => $lam28014$apply$3711($clo, k) };

function $lam28018$apply$3712($clo, k) {
  {
    const $t28019 = (() => {
      return (k === "s");
    })();
    {
      const $t28020 = (k === "S");
      return ($t28019 || $t28020);
    }
  }
}
const $lam28018$apply$3712$clo = { _0: ($_, $clo, k) => $lam28018$apply$3712($clo, k) };

function $lam28029$apply$3713($clo, k) {
  {
    const $t28030 = (() => {
      return (k === "r");
    })();
    {
      const $t28031 = (k === "R");
      return ($t28030 || $t28031);
    }
  }
}
const $lam28029$apply$3713$clo = { _0: ($_, $clo, k) => $lam28029$apply$3713($clo, k) };

function $jp28258$apply$3721($clo) {
  {
    const $f28253 = (() => {
      return $clo._1;
    })();
    {
      const fallback = (() => {
        return $clo._2;
      })();
      {
        const rest = (() => {
          return $f28253;
        })();
        return Perihelion$Core$top_star(rest, fallback);
      }
    }
  }
}
const $jp28258$apply$3721$clo = { _0: ($_, $clo) => $jp28258$apply$3721($clo) };

function $lam28453$apply$3733($clo, r) {
  return Perihelion$Core$encode_run(r);
}
const $lam28453$apply$3733$clo = { _0: ($_, $clo, r) => $lam28453$apply$3733($clo, r) };

function $jp28467$apply$3734($clo) {
  return { $: "None" };
}
const $jp28467$apply$3734$clo = { _0: ($_, $clo) => $jp28467$apply$3734($clo) };

function $jp28471$apply$3735($clo) {
  {
    const $jp_clo28468 = (() => {
      return $clo._1;
    })();
    {
      const $jp_clo28470 = (() => {
        return { $: "$Clo_$jp28469$3736", _0: $jp28469$apply$3736, _1: $jp_clo28468 };
      })();
      return $jp28469$apply$3736($jp_clo28470);
    }
  }
}
const $jp28471$apply$3735$clo = { _0: ($_, $clo) => $jp28471$apply$3735($clo) };

function $jp28469$apply$3736($clo) {
  {
    const $jp_clo28468 = (() => {
      return $clo._1;
    })();
    return $jp_clo28468._0($jp_clo28468);
  }
}
const $jp28469$apply$3736$clo = { _0: ($_, $clo) => $jp28469$apply$3736($clo) };

function $jp28475$apply$3737($clo) {
  {
    const $jp_clo28472 = (() => {
      return $clo._1;
    })();
    return $jp_clo28472._0($jp_clo28472);
  }
}
const $jp28475$apply$3737$clo = { _0: ($_, $clo) => $jp28475$apply$3737($clo) };

function $jp28479$apply$3738($clo) {
  {
    const $jp_clo28476 = (() => {
      return $clo._1;
    })();
    {
      const $jp_clo28478 = (() => {
        return { $: "$Clo_$jp28477$3739", _0: $jp28477$apply$3739, _1: $jp_clo28476 };
      })();
      return $jp28477$apply$3739($jp_clo28478);
    }
  }
}
const $jp28479$apply$3738$clo = { _0: ($_, $clo) => $jp28479$apply$3738($clo) };

function $jp28477$apply$3739($clo) {
  {
    const $jp_clo28476 = (() => {
      return $clo._1;
    })();
    return $jp_clo28476._0($jp_clo28476);
  }
}
const $jp28477$apply$3739$clo = { _0: ($_, $clo) => $jp28477$apply$3739($clo) };

function $jp28483$apply$3740($clo) {
  {
    const $jp_clo28480 = (() => {
      return $clo._1;
    })();
    return $jp_clo28480._0($jp_clo28480);
  }
}
const $jp28483$apply$3740$clo = { _0: ($_, $clo) => $jp28483$apply$3740($clo) };

function $jp28487$apply$3741($clo) {
  {
    const $jp_clo28484 = (() => {
      return $clo._1;
    })();
    {
      const $jp_clo28486 = (() => {
        return { $: "$Clo_$jp28485$3742", _0: $jp28485$apply$3742, _1: $jp_clo28484 };
      })();
      return $jp28485$apply$3742($jp_clo28486);
    }
  }
}
const $jp28487$apply$3741$clo = { _0: ($_, $clo) => $jp28487$apply$3741($clo) };

function $jp28485$apply$3742($clo) {
  {
    const $jp_clo28484 = (() => {
      return $clo._1;
    })();
    return $jp_clo28484._0($jp_clo28484);
  }
}
const $jp28485$apply$3742$clo = { _0: ($_, $clo) => $jp28485$apply$3742($clo) };

function $lam28715$apply$3752($clo, p) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const $t28708_i7589 = (() => {
        {
          const $t28705_i7586 = p.x;
          {
            const $t28707_i7588 = (() => {
              {
                const $t28706_i7587 = p.vx;
                return ($t28706_i7587 * dt_s);
              }
            })();
            return ($t28705_i7586 + $t28707_i7588);
          }
        }
      })();
      {
        const $t28712_i7593 = (() => {
          {
            const $t28709_i7590 = p.y;
            {
              const $t28711_i7592 = (() => {
                {
                  const $t28710_i7591 = p.vy;
                  return ($t28710_i7591 * dt_s);
                }
              })();
              return ($t28709_i7590 + $t28711_i7592);
            }
          }
        })();
        {
          const $t28714_i7595 = (() => {
            {
              const $t28713_i7594 = p.life;
              return ($t28713_i7594 - dt_s);
            }
          })();
          return ({ ...p, x: $t28708_i7589, y: $t28712_i7593, life: $t28714_i7595 });
        }
      }
    }
  }
}
const $lam28715$apply$3752$clo = { _0: ($_, $clo, p) => $lam28715$apply$3752($clo, p) };

function $lam28718$apply$3753($clo, p) {
  {
    const $t28719 = p.life;
    return ($t28719 > 0.);
  }
}
const $lam28718$apply$3753$clo = { _0: ($_, $clo, p) => $lam28718$apply$3753($clo, p) };

function $jp28864$apply$3756($clo) {
  {
    const $f28858 = (() => {
      return $clo._1;
    })();
    {
      const $f28859 = (() => {
        return $clo._2;
      })();
      {
        const ctx = (() => {
          return $clo._3;
        })();
        {
          const s = (() => {
            return $clo._4;
          })();
          {
            const rest = (() => {
              return $f28859;
            })();
            {
              const o = (() => {
                return $f28858;
              })();
              (() => {
                return Canvas$set_global_alpha(ctx, 0.16);
              })();
              (() => {
                return Canvas$set_stroke_style(ctx, "#8a8a8a");
              })();
              (() => {
                return Canvas$set_line_width(ctx, 1.);
              })();
              (() => {
                return Canvas$begin_path(ctx);
              })();
              (() => {
                {
                  const $t28854 = s.x;
                  {
                    const $t28855 = s.y;
                    {
                      const $t28856 = o.radius;
                      return Canvas$arc(ctx, $t28854, $t28855, $t28856, 0., 6.28318530718);
                    }
                  }
                }
              })();
              (() => {
                return Canvas$stroke(ctx);
              })();
              return draw_orbit_rings(ctx, s, rest);
            }
          }
        }
      }
    }
  }
}
const $jp28864$apply$3756$clo = { _0: ($_, $clo) => $jp28864$apply$3756($clo) };

function $jp28903$apply$3759($clo) {
  {
    const ctx = (() => {
      return $clo._1;
    })();
    {
      const s = (() => {
        return $clo._2;
      })();
      {
        const t = (() => {
          return $clo._3;
        })();
        {
          const $t28902 = dot_count(s);
          return draw_pulse_particle(ctx, s, t, $t28902, 0);
        }
      }
    }
  }
}
const $jp28903$apply$3759$clo = { _0: ($_, $clo) => $jp28903$apply$3759($clo) };

function $jp28905$apply$3760($clo) {
  {
    const ctx = (() => {
      return $clo._1;
    })();
    {
      const s = (() => {
        return $clo._2;
      })();
      {
        const t = (() => {
          return $clo._3;
        })();
        {
          const $t28902 = dot_count(s);
          return draw_pulse_particle(ctx, s, t, $t28902, 0);
        }
      }
    }
  }
}
const $jp28905$apply$3760$clo = { _0: ($_, $clo) => $jp28905$apply$3760($clo) };

function $jp29039$apply$3763($clo) {
  {
    const ctx = (() => {
      return $clo._1;
    })();
    {
      const px = (() => {
        return $clo._2;
      })();
      {
        const py = (() => {
          return $clo._3;
        })();
        return Canvas$line_to(ctx, px, py);
      }
    }
  }
}
const $jp29039$apply$3763$clo = { _0: ($_, $clo) => $jp29039$apply$3763($clo) };

function $lam29218$apply$3775($clo, k) {
  {
    const $t29219 = (() => {
      return (k === "m");
    })();
    {
      const $t29220 = (k === "M");
      return ($t29219 || $t29220);
    }
  }
}
const $lam29218$apply$3775$clo = { _0: ($_, $clo, k) => $lam29218$apply$3775($clo, k) };

function $lam29269$apply$3776($clo, _) {
  {
    const ctx = (() => {
      return $clo._1;
    })();
    {
      const el = (() => {
        return $clo._2;
      })();
      {
        const fx2 = (() => {
          return $clo._3;
        })();
        {
          const g2 = (() => {
            return $clo._4;
          })();
          return tick(ctx, el, g2, fx2);
        }
      }
    }
  }
}
const $lam29269$apply$3776$clo = { _0: ($_, $clo, _) => $lam29269$apply$3776($clo, _) };

function $lam29282$apply$3777($clo, _) {
  {
    const best = (() => {
      return $clo._1;
    })();
    {
      const ctx = (() => {
        return $clo._2;
      })();
      {
        const node = (() => {
          return $clo._3;
        })();
        {
          const runs = (() => {
            return $clo._4;
          })();
          return boot(ctx, node, best, runs);
        }
      }
    }
  }
}
const $lam29282$apply$3777$clo = { _0: ($_, $clo, _) => $lam29282$apply$3777($clo, _) };

function go$apply$4038($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$4038$clo = { _0: ($_, $clo, lst, acc) => go$apply$4038($clo, lst, acc) };

function go$apply$4265($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$4265$clo = { _0: ($_, $clo, lst, acc) => go$apply$4265($clo, lst, acc) };

function go$apply$4705($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8631 = { $: "$Clo_go$5176", _0: go$apply$5176 };
            {
              const $t250_i8632 = { $: "Nil" };
              return go$apply$5176(go_i8631, acc, $t250_i8632);
            }
          }
          break;
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
          break;
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$4705$clo = { _0: ($_, $clo, lst, acc) => go$apply$4705($clo, lst, acc) };

function go$apply$4707($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8636 = { $: "$Clo_go$5176", _0: go$apply$5176 };
            {
              const $t250_i8637 = { $: "Nil" };
              return go$apply$5176(go_i8636, acc, $t250_i8637);
            }
          }
          break;
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
          break;
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$4707$clo = { _0: ($_, $clo, lst, acc) => go$apply$4707($clo, lst, acc) };

function go$apply$4709($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8641 = { $: "$Clo_go$5178", _0: go$apply$5178 };
            {
              const $t250_i8642 = { $: "Nil" };
              return go$apply$5178(go_i8641, acc, $t250_i8642);
            }
          }
          break;
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
          break;
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$4709$clo = { _0: ($_, $clo, lst, acc) => go$apply$4709($clo, lst, acc) };

function go$apply$4711($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8646 = { $: "$Clo_go$5178", _0: go$apply$5178 };
            {
              const $t250_i8647 = { $: "Nil" };
              return go$apply$5178(go_i8646, acc, $t250_i8647);
            }
          }
          break;
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
          break;
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$4711$clo = { _0: ($_, $clo, lst, acc) => go$apply$4711($clo, lst, acc) };

function go$apply$4713($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$4713$clo = { _0: ($_, $clo, lst, acc) => go$apply$4713($clo, lst, acc) };

function go$apply$4715($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$4715$clo = { _0: ($_, $clo, lst, acc) => go$apply$4715($clo, lst, acc) };

function go$apply$4717($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$4717$clo = { _0: ($_, $clo, lst, acc) => go$apply$4717($clo, lst, acc) };

function go$apply$4719($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8657 = { $: "$Clo_go$4265", _0: go$apply$4265 };
            {
              const $t250_i8658 = { $: "Nil" };
              return go$apply$4265(go_i8657, acc, $t250_i8658);
            }
          }
          break;
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
          break;
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$4719$clo = { _0: ($_, $clo, lst, acc) => go$apply$4719($clo, lst, acc) };

function go$apply$4721($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$4721$clo = { _0: ($_, $clo, lst, acc) => go$apply$4721($clo, lst, acc) };

function go$apply$4724($clo, lst, yes, no) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const $t543 = (() => {
              {
                const go_i8668 = { $: "$Clo_go$4713", _0: go$apply$4713 };
                {
                  const $t250_i8669 = { $: "Nil" };
                  return go$apply$4713(go_i8668, yes, $t250_i8669);
                }
              }
            })();
            {
              const $t544 = (() => {
                {
                  const go_i8665 = { $: "$Clo_go$4713", _0: go$apply$4713 };
                  {
                    const $t250_i8666 = { $: "Nil" };
                    return go$apply$4713(go_i8665, no, $t250_i8666);
                  }
                }
              })();
              return { _0: $t543, _1: $t544 };
            }
          }
          break;
        }
        case "Cons": {
          const $f548 = lst._0;
          const $f549 = lst._1;
          {
            const t = $f549;
            {
              const h = $f548;
              {
                const $t545 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t545 === true) {
                  return (() => {
                    {
                      const $t546 = { $: "Cons", _0: h, _1: yes };
                      return go._0(go, t, $t546, no);
                    }
                  })();
                } else {
                  return (() => {
                    {
                      const $t547 = { $: "Cons", _0: h, _1: no };
                      return go._0(go, t, yes, $t547);
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
const go$apply$4724$clo = { _0: ($_, $clo, lst, yes, no) => go$apply$4724($clo, lst, yes, no) };

function go$apply$4727($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$4727$clo = { _0: ($_, $clo, lst, acc) => go$apply$4727($clo, lst, acc) };

function go$apply$4730($clo, lst, yes, no) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const $t543 = (() => {
              {
                const go_i8680 = { $: "$Clo_go$4717", _0: go$apply$4717 };
                {
                  const $t250_i8681 = { $: "Nil" };
                  return go$apply$4717(go_i8680, yes, $t250_i8681);
                }
              }
            })();
            {
              const $t544 = (() => {
                {
                  const go_i8677 = { $: "$Clo_go$4717", _0: go$apply$4717 };
                  {
                    const $t250_i8678 = { $: "Nil" };
                    return go$apply$4717(go_i8677, no, $t250_i8678);
                  }
                }
              })();
              return { _0: $t543, _1: $t544 };
            }
          }
          break;
        }
        case "Cons": {
          const $f548 = lst._0;
          const $f549 = lst._1;
          {
            const t = $f549;
            {
              const h = $f548;
              {
                const $t545 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t545 === true) {
                  return (() => {
                    {
                      const $t546 = { $: "Cons", _0: h, _1: yes };
                      return go._0(go, t, $t546, no);
                    }
                  })();
                } else {
                  return (() => {
                    {
                      const $t547 = { $: "Cons", _0: h, _1: no };
                      return go._0(go, t, yes, $t547);
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
const go$apply$4730$clo = { _0: ($_, $clo, lst, yes, no) => go$apply$4730($clo, lst, yes, no) };

function go$apply$4733($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$4733$clo = { _0: ($_, $clo, lst, acc) => go$apply$4733($clo, lst, acc) };

function go$apply$4735($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8688 = { $: "$Clo_go$4717", _0: go$apply$4717 };
            {
              const $t250_i8689 = { $: "Nil" };
              return go$apply$4717(go_i8688, acc, $t250_i8689);
            }
          }
          break;
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
          break;
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$4735$clo = { _0: ($_, $clo, lst, acc) => go$apply$4735($clo, lst, acc) };

function go$apply$4737($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8693 = { $: "$Clo_go$4713", _0: go$apply$4713 };
            {
              const $t250_i8694 = { $: "Nil" };
              return go$apply$4713(go_i8693, acc, $t250_i8694);
            }
          }
          break;
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
          break;
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$4737$clo = { _0: ($_, $clo, lst, acc) => go$apply$4737($clo, lst, acc) };

function go$apply$4740($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$4740$clo = { _0: ($_, $clo, lst, acc) => go$apply$4740($clo, lst, acc) };

function go$apply$4743($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$4743$clo = { _0: ($_, $clo, lst, acc) => go$apply$4743($clo, lst, acc) };

function go$apply$4745($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$4745$clo = { _0: ($_, $clo, lst, acc) => go$apply$4745($clo, lst, acc) };

function go$apply$4747($clo, lst, k, acc) {
  {
    const go = $clo;
    {
      const $t496 = (k <= 0);
      if ($t496 === true) {
        return (() => {
          {
            const go_i8709 = { $: "$Clo_go$5025", _0: go$apply$5025 };
            {
              const $t250_i8710 = { $: "Nil" };
              return go$apply$5025(go_i8709, acc, $t250_i8710);
            }
          }
        })();
      } else {
        return (() => {
          switch (lst.$) {
            case "Nil": {
              {
                const go_i8706 = { $: "$Clo_go$5025", _0: go$apply$5025 };
                {
                  const $t250_i8707 = { $: "Nil" };
                  return go$apply$5025(go_i8706, acc, $t250_i8707);
                }
              }
              break;
            }
            case "Cons": {
              const $f499 = lst._0;
              const $f500 = lst._1;
              {
                const t = $f500;
                {
                  const h = $f499;
                  {
                    const $t497 = (k - 1);
                    {
                      const $t498 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t497, $t498);
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
const go$apply$4747$clo = { _0: ($_, $clo, lst, k, acc) => go$apply$4747($clo, lst, k, acc) };

function go$apply$4749($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8714 = { $: "$Clo_go$4038", _0: go$apply$4038 };
            {
              const $t250_i8715 = { $: "Nil" };
              return go$apply$4038(go_i8714, acc, $t250_i8715);
            }
          }
          break;
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
          break;
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$4749$clo = { _0: ($_, $clo, lst, acc) => go$apply$4749($clo, lst, acc) };

function go$apply$4751($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$4751$clo = { _0: ($_, $clo, lst, acc) => go$apply$4751($clo, lst, acc) };

function go$apply$4753($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8721 = { $: "$Clo_go$5182", _0: go$apply$5182 };
            {
              const $t250_i8722 = { $: "Nil" };
              return go$apply$5182(go_i8721, acc, $t250_i8722);
            }
          }
          break;
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
          break;
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$4753$clo = { _0: ($_, $clo, lst, acc) => go$apply$4753($clo, lst, acc) };

function go$apply$4755($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8726 = { $: "$Clo_go$5182", _0: go$apply$5182 };
            {
              const $t250_i8727 = { $: "Nil" };
              return go$apply$5182(go_i8726, acc, $t250_i8727);
            }
          }
          break;
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
          break;
        }
        default: {
          return (() => { throw new Error("non-exhaustive pattern match"); })();
        }
      }
    }
  }
}
const go$apply$4755$clo = { _0: ($_, $clo, lst, acc) => go$apply$4755($clo, lst, acc) };

function go$apply$4757($clo, lst, k, acc) {
  {
    const go = $clo;
    {
      const $t496 = (k <= 0);
      if ($t496 === true) {
        return (() => {
          {
            const go_i8734 = { $: "$Clo_go$5025", _0: go$apply$5025 };
            {
              const $t250_i8735 = { $: "Nil" };
              return go$apply$5025(go_i8734, acc, $t250_i8735);
            }
          }
        })();
      } else {
        return (() => {
          switch (lst.$) {
            case "Nil": {
              {
                const go_i8731 = { $: "$Clo_go$5025", _0: go$apply$5025 };
                {
                  const $t250_i8732 = { $: "Nil" };
                  return go$apply$5025(go_i8731, acc, $t250_i8732);
                }
              }
              break;
            }
            case "Cons": {
              const $f499 = lst._0;
              const $f500 = lst._1;
              {
                const t = $f500;
                {
                  const h = $f499;
                  {
                    const $t497 = (k - 1);
                    {
                      const $t498 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t497, $t498);
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
const go$apply$4757$clo = { _0: ($_, $clo, lst, k, acc) => go$apply$4757($clo, lst, k, acc) };

function go$apply$4759($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$4759$clo = { _0: ($_, $clo, lst, acc) => go$apply$4759($clo, lst, acc) };

function go$apply$5025($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$5025$clo = { _0: ($_, $clo, lst, acc) => go$apply$5025($clo, lst, acc) };

function go$apply$5176($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$5176$clo = { _0: ($_, $clo, lst, acc) => go$apply$5176($clo, lst, acc) };

function go$apply$5178($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$5178$clo = { _0: ($_, $clo, lst, acc) => go$apply$5178($clo, lst, acc) };

function go$apply$5180($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$5180$clo = { _0: ($_, $clo, lst, acc) => go$apply$5180($clo, lst, acc) };

function go$apply$5182($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
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
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const go$apply$5182$clo = { _0: ($_, $clo, lst, acc) => go$apply$5182($clo, lst, acc) };

export { main };
main();
