import { march_float_round, march_float_to_string, march_int_and, march_int_div, march_int_div_euclid, march_int_mod, march_int_mod_euclid, march_int_not, march_int_or, march_int_popcount, march_int_shl, march_int_shr, march_int_xor, march_print, march_string_byte_length, march_string_join, march_string_split, march_string_to_int, march_unix_time } from "./march_runtime.mjs";

import { march_dom_request_animation_frame as dom_request_animation_frame, march_dom_window_size as dom_window_size, march_dom_pointer_pos as dom_pointer_pos, march_dom_store_set as dom_store_set, march_dom_store_get as dom_store_get, march_dom_key_presses as dom_key_presses, march_dom_taps as dom_taps, march_dom_set_attribute as dom_set_attribute, march_dom_get_element_by_id as dom_get_element_by_id } from "./march_dom.mjs";
import { march_audio_noise_burst as audio_noise_burst, march_audio_sweep as audio_sweep, march_audio_beep as audio_beep, march_audio_resume as audio_resume, march_audio_create as audio_create } from "./march_audio.mjs";
import { march_canvas_set_text_align as canvas_set_text_align, march_canvas_fill_text as canvas_fill_text, march_canvas_fill_noise_circle as canvas_fill_noise_circle, march_canvas_stroke as canvas_stroke, march_canvas_fill as canvas_fill, march_canvas_arc as canvas_arc, march_canvas_line_to as canvas_line_to, march_canvas_move_to as canvas_move_to, march_canvas_close_path as canvas_close_path, march_canvas_begin_path as canvas_begin_path, march_canvas_stroke_rect as canvas_stroke_rect, march_canvas_fill_rect as canvas_fill_rect, march_canvas_set_font as canvas_set_font, march_canvas_set_global_alpha as canvas_set_global_alpha, march_canvas_set_line_width as canvas_set_line_width, march_canvas_set_stroke_style as canvas_set_stroke_style, march_canvas_set_fill_style as canvas_set_fill_style, march_canvas_rotate as canvas_rotate, march_canvas_translate as canvas_translate, march_canvas_restore as canvas_restore, march_canvas_save as canvas_save, march_canvas_get_context as canvas_get_context } from "./march_canvas.mjs";


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
const canvas_stroke_rect$clo = { _0: ($_, p0, p1, p2, p3, p4) => canvas_stroke_rect(p0, p1, p2, p3, p4) };
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
  if (a.homing !== b.homing) return false;
  if (a.star_killer !== b.star_killer) return false;
  if (a.target_x !== b.target_x) return false;
  if (a.target_y !== b.target_y) return false;
  return true;
}

function __eq_Perihelion$Combat$Pickup(a, b) {
  if (a.x !== b.x) return false;
  if (a.y !== b.y) return false;
  if (a.ttl !== b.ttl) return false;
  if (!__eq_Perihelion$Upgrades$UpgradeKind(a.kind, b.kind)) return false;
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
    case "Milestone": {
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
  if (!__eq_List(a.owned_weapons, b.owned_weapons)) return false;
  if (a.active_weapon_idx !== b.active_weapon_idx) return false;
  if (a.fire_rate_stacks !== b.fire_rate_stacks) return false;
  if (a.bullet_ward !== b.bullet_ward) return false;
  if (a.deflector_plating !== b.deflector_plating) return false;
  if (a.shield_reinforced !== b.shield_reinforced) return false;
  if (!__eq_Option(a.special, b.special)) return false;
  if (a.special_charges !== b.special_charges) return false;
  if (a.starkiller_target_offset !== b.starkiller_target_offset) return false;
  if (a.starkiller_cooldown !== b.starkiller_cooldown) return false;
  if (!__eq_List(a.milestone_choices, b.milestone_choices)) return false;
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

function __eq_Perihelion$Upgrades$WeaponKind(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "Base": {
      return true;
    }
    case "Homing": {
      return true;
    }
    case "Spread": {
      return true;
    }
    case "StarKiller": {
      return true;
    }
  }
  return true;
}

function __eq_Perihelion$Upgrades$SpecialKind(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "StarThrust": {
      return true;
    }
    case "StarJump": {
      return true;
    }
    case "TrajectoryPreview": {
      return true;
    }
  }
  return true;
}

function __eq_Perihelion$Upgrades$UpgradeKind(a, b) {
  if (a.$ !== b.$) return false;
  switch (a.$) {
    case "OffenseWeapon": {
      if (!__eq_WeaponKind(a._0, b._0)) return false;
      return true;
    }
    case "OffenseFireRate": {
      return true;
    }
    case "DefenseBulletWard": {
      return true;
    }
    case "DefenseDeflector": {
      return true;
    }
    case "DefenseShield": {
      return true;
    }
    case "SpecialItem": {
      if (!__eq_SpecialKind(a._0, b._0)) return false;
      return true;
    }
  }
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
        const $t15536 = (x + 2654435769);
        return march_int_and($t15536, 4294967295);
      }
    })();
    {
      const x$sh2 = (() => {
        {
          const $t15538 = (() => {
            {
              const $t15537 = march_int_shr(x$sh1, 16);
              return march_int_xor(x$sh1, $t15537);
            }
          })();
          {
            const xh_i9834 = march_int_shr($t15538, 16);
            {
              const xl_i9835 = march_int_and($t15538, 65535);
              {
                const $t15527_i9840 = (() => {
                  {
                    const $t15525_i9838 = (() => {
                      {
                        const $t15524_i9837 = (() => {
                          {
                            const $t15523_i9836 = (xh_i9834 * 569420461);
                            return march_int_and($t15523_i9836, 65535);
                          }
                        })();
                        return ($t15524_i9837 * 65536);
                      }
                    })();
                    {
                      const $t15526_i9839 = (xl_i9835 * 569420461);
                      return ($t15525_i9838 + $t15526_i9839);
                    }
                  }
                })();
                return march_int_and($t15527_i9840, 4294967295);
              }
            }
          }
        }
      })();
      {
        const x$sh3 = (() => {
          {
            const $t15540 = (() => {
              {
                const $t15539 = march_int_shr(x$sh2, 15);
                return march_int_xor(x$sh2, $t15539);
              }
            })();
            {
              const xh_i9823 = march_int_shr($t15540, 16);
              {
                const xl_i9824 = march_int_and($t15540, 65535);
                {
                  const $t15527_i9829 = (() => {
                    {
                      const $t15525_i9827 = (() => {
                        {
                          const $t15524_i9826 = (() => {
                            {
                              const $t15523_i9825 = (xh_i9823 * 1935289751);
                              return march_int_and($t15523_i9825, 65535);
                            }
                          })();
                          return ($t15524_i9826 * 65536);
                        }
                      })();
                      {
                        const $t15526_i9828 = (xl_i9824 * 1935289751);
                        return ($t15525_i9827 + $t15526_i9828);
                      }
                    }
                  })();
                  return march_int_and($t15527_i9829, 4294967295);
                }
              }
            }
          }
        })();
        {
          const $t15541 = march_int_shr(x$sh3, 15);
          return march_int_xor(x$sh3, $t15541);
        }
      }
    }
  }
}
const Random$mix32$clo = { _0: ($_, x) => Random$mix32(x) };

function Random$warmup(rng, k) {
  {
    const $t15542 = (k <= 0);
    if ($t15542 === true) {
      return rng;
    } else {
      return (() => {
        {
          const $p15544 = Random$next_raw(rng);
          {
            const r2 = $p15544._1;
            {
              const $t15543 = (k - 1);
              return Random$warmup(r2, $t15543);
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
          const $t15547 = (() => {
            {
              const $t15545 = (n - lo);
              return ($t15545 / 4294967296);
            }
          })();
          return march_int_and($t15547, 4294967295);
        }
      })();
      {
        const a = Random$mix32(lo);
        {
          const b = (() => {
            {
              const $t15548 = march_int_xor(hi, a);
              return Random$mix32($t15548);
            }
          })();
          {
            const c = (() => {
              {
                const $t15549 = march_int_xor(lo, b);
                return Random$mix32($t15549);
              }
            })();
            {
              const $t15550 = ({ s0: a, s1: b, s2: c, s3: 1 });
              return Random$warmup($t15550, 12);
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
        const $t15555 = (() => {
          {
            const $t15553 = (() => {
              {
                const $t15551 = rng.s0;
                {
                  const $t15552 = rng.s1;
                  return ($t15551 + $t15552);
                }
              }
            })();
            {
              const $t15554 = rng.s3;
              return ($t15553 + $t15554);
            }
          }
        })();
        return march_int_and($t15555, 4294967295);
      }
    })();
    {
      const a = (() => {
        {
          const $t15556 = rng.s1;
          {
            const $t15558 = (() => {
              {
                const $t15557 = rng.s1;
                return march_int_shr($t15557, 9);
              }
            })();
            return march_int_xor($t15556, $t15558);
          }
        }
      })();
      {
        const b = (() => {
          {
            const $t15563 = (() => {
              {
                const $t15559 = rng.s2;
                {
                  const $t15562 = (() => {
                    {
                      const $t15561 = (() => {
                        {
                          const $t15560 = rng.s2;
                          return march_int_shl($t15560, 3);
                        }
                      })();
                      return march_int_and($t15561, 4294967295);
                    }
                  })();
                  return ($t15559 + $t15562);
                }
              }
            })();
            return march_int_and($t15563, 4294967295);
          }
        })();
        {
          const c = (() => {
            {
              const $t15566 = (() => {
                {
                  const $t15565 = (() => {
                    {
                      const $t15564 = rng.s2;
                      {
                        const keep_i1518 = (() => {
                          {
                            const $t15530_i1517 = march_int_shr(4294967295, 21);
                            return march_int_and($t15564, $t15530_i1517);
                          }
                        })();
                        {
                          const $t15531_i1519 = march_int_shl(keep_i1518, 21);
                          {
                            const $t15533_i1521 = march_int_shr($t15564, 11);
                            return march_int_or($t15531_i1519, $t15533_i1521);
                          }
                        }
                      }
                    }
                  })();
                  return ($t15565 + t);
                }
              })();
              return march_int_and($t15566, 4294967295);
            }
          })();
          {
            const $t15570 = (() => {
              {
                const $t15569 = (() => {
                  {
                    const $t15568 = (() => {
                      {
                        const $t15567 = rng.s3;
                        return ($t15567 + 1);
                      }
                    })();
                    return march_int_and($t15568, 4294967295);
                  }
                })();
                return ({ s0: a, s1: b, s2: c, s3: $t15569 });
              }
            })();
            return { _0: t, _1: $t15570 };
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

function Canvas$stroke_rect(ctx, x, y, w, h) {
  {
    const $rc_800 = canvas_stroke_rect$clo._0(canvas_stroke_rect$clo, ctx, x, y, w, h);
    return $rc_800;
  }
}
const Canvas$stroke_rect$clo = { _0: ($_, ctx, x, y, w, h) => Canvas$stroke_rect(ctx, x, y, w, h) };

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

function Perihelion$Combat$starkiller_target_idx(game) {
  {
    const raw = (() => {
      {
        const $t27350 = (() => {
          {
            const $t27349 = game.current;
            return ($t27349 + 1);
          }
        })();
        {
          const $t27351 = game.starkiller_target_offset;
          return ($t27350 + $t27351);
        }
      }
    })();
    {
      const max_idx = (() => {
        {
          const $t27353 = (() => {
            {
              const $t27352 = game.stars;
              {
                const go_i3627 = { $: "$Clo_go$4747", _0: go$apply$4747 };
                return go$apply$4747(go_i3627, $t27352, 0);
              }
            }
          })();
          return ($t27353 - 1);
        }
      })();
      {
        const $t27354 = (raw > max_idx);
        if ($t27354 === true) {
          return max_idx;
        } else {
          return raw;
        }
      }
    }
  }
}
const Perihelion$Combat$starkiller_target_idx$clo = { _0: ($_, game) => Perihelion$Combat$starkiller_target_idx(game) };

function Perihelion$Combat$step_spawn(game, dt_s) {
  {
    const t = (() => {
      {
        const $t27363 = game.spawn_timer;
        return ($t27363 - dt_s);
      }
    })();
    {
      const $t27364 = (t > 0.);
      if ($t27364 === true) {
        return ({ ...game, spawn_timer: t });
      } else {
        return (() => {
          {
            const $p27390 = (() => {
              {
                const $t27365 = game.rng;
                {
                  const $p29016_i10423_i10722_i10897 = (() => {
                    {
                      const $p15579_i10148_i10418_i10717_i10892 = (() => {
                        {
                          const $p15576_i1532_i10138_i10409_i10708_i10883 = Random$next_raw($t27365);
                          {
                            const hi_i1533_i10139_i10410_i10709_i10884 = $p15576_i1532_i10138_i10409_i10708_i10883._0;
                            {
                              const rng2_i1534_i10140_i10411_i10710_i10885 = $p15576_i1532_i10138_i10409_i10708_i10883._1;
                              {
                                const $p15575_i1535_i10141_i10412_i10711_i10886 = Random$next_raw(rng2_i1534_i10140_i10411_i10710_i10885);
                                {
                                  const lo_i1536_i10142_i10413_i10712_i10887 = $p15575_i1535_i10141_i10412_i10711_i10886._0;
                                  {
                                    const rng3_i1537_i10143_i10414_i10713_i10888 = $p15575_i1535_i10141_i10412_i10711_i10886._1;
                                    {
                                      const $t15574_i1541_i10147_i10417_i10716_i10891 = (() => {
                                        {
                                          const $t15573_i1540_i10146_i10416_i10715_i10890 = (() => {
                                            {
                                              const $t15571_i1538_i10144_i10415_i10714_i10889 = march_int_and(hi_i1533_i10139_i10410_i10709_i10884, 1048575);
                                              return ($t15571_i1538_i10144_i10415_i10714_i10889 * 4294967296);
                                            }
                                          })();
                                          return ($t15573_i1540_i10146_i10416_i10715_i10890 + lo_i1536_i10142_i10413_i10712_i10887);
                                        }
                                      })();
                                      return { _0: $t15574_i1541_i10147_i10417_i10716_i10891, _1: rng3_i1537_i10143_i10414_i10713_i10888 };
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      })();
                      {
                        const bits_i10149_i10419_i10718_i10893 = $p15579_i10148_i10418_i10717_i10892._0;
                        {
                          const rng2_i10150_i10420_i10719_i10894 = $p15579_i10148_i10418_i10717_i10892._1;
                          {
                            const $t15578_i10152_i10422_i10721_i10896 = (() => {
                              {
                                const $t15577_i10151_i10421_i10720_i10895 = bits_i10149_i10419_i10718_i10893;
                                return ($t15577_i10151_i10421_i10720_i10895 / 4.50359962737e+15);
                              }
                            })();
                            return { _0: $t15578_i10152_i10422_i10721_i10896, _1: rng2_i10150_i10420_i10719_i10894 };
                          }
                        }
                      }
                    }
                  })();
                  {
                    const t_i10424_i10723_i10898 = $p29016_i10423_i10722_i10897._0;
                    {
                      const rng2_i10425_i10724_i10899 = $p29016_i10423_i10722_i10897._1;
                      {
                        const out_i10426_i10725_i10900 = { _0: rng2_i10425_i10724_i10899, _1: t_i10424_i10723_i10898 };
                        return out_i10426_i10725_i10900;
                      }
                    }
                  }
                }
              }
            })();
            {
              const r1 = $p27390._0;
              {
                const side_f = $p27390._1;
                {
                  const $p27389 = (() => {
                    {
                      const $p29016_i10423_i10722_i10878 = (() => {
                        {
                          const $p15579_i10148_i10418_i10717_i10873 = (() => {
                            {
                              const $p15576_i1532_i10138_i10409_i10708_i10864 = Random$next_raw(r1);
                              {
                                const hi_i1533_i10139_i10410_i10709_i10865 = $p15576_i1532_i10138_i10409_i10708_i10864._0;
                                {
                                  const rng2_i1534_i10140_i10411_i10710_i10866 = $p15576_i1532_i10138_i10409_i10708_i10864._1;
                                  {
                                    const $p15575_i1535_i10141_i10412_i10711_i10867 = Random$next_raw(rng2_i1534_i10140_i10411_i10710_i10866);
                                    {
                                      const lo_i1536_i10142_i10413_i10712_i10868 = $p15575_i1535_i10141_i10412_i10711_i10867._0;
                                      {
                                        const rng3_i1537_i10143_i10414_i10713_i10869 = $p15575_i1535_i10141_i10412_i10711_i10867._1;
                                        {
                                          const $t15574_i1541_i10147_i10417_i10716_i10872 = (() => {
                                            {
                                              const $t15573_i1540_i10146_i10416_i10715_i10871 = (() => {
                                                {
                                                  const $t15571_i1538_i10144_i10415_i10714_i10870 = march_int_and(hi_i1533_i10139_i10410_i10709_i10865, 1048575);
                                                  return ($t15571_i1538_i10144_i10415_i10714_i10870 * 4294967296);
                                                }
                                              })();
                                              return ($t15573_i1540_i10146_i10416_i10715_i10871 + lo_i1536_i10142_i10413_i10712_i10868);
                                            }
                                          })();
                                          return { _0: $t15574_i1541_i10147_i10417_i10716_i10872, _1: rng3_i1537_i10143_i10414_i10713_i10869 };
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          })();
                          {
                            const bits_i10149_i10419_i10718_i10874 = $p15579_i10148_i10418_i10717_i10873._0;
                            {
                              const rng2_i10150_i10420_i10719_i10875 = $p15579_i10148_i10418_i10717_i10873._1;
                              {
                                const $t15578_i10152_i10422_i10721_i10877 = (() => {
                                  {
                                    const $t15577_i10151_i10421_i10720_i10876 = bits_i10149_i10419_i10718_i10874;
                                    return ($t15577_i10151_i10421_i10720_i10876 / 4.50359962737e+15);
                                  }
                                })();
                                return { _0: $t15578_i10152_i10422_i10721_i10877, _1: rng2_i10150_i10420_i10719_i10875 };
                              }
                            }
                          }
                        }
                      })();
                      {
                        const t_i10424_i10723_i10879 = $p29016_i10423_i10722_i10878._0;
                        {
                          const rng2_i10425_i10724_i10880 = $p29016_i10423_i10722_i10878._1;
                          {
                            const out_i10426_i10725_i10881 = { _0: rng2_i10425_i10724_i10880, _1: t_i10424_i10723_i10879 };
                            return out_i10426_i10725_i10881;
                          }
                        }
                      }
                    }
                  })();
                  {
                    const r2 = $p27389._0;
                    {
                      const y_f = $p27389._1;
                      {
                        const $p27388 = (() => {
                          {
                            const $p29016_i10423_i10722_i10859 = (() => {
                              {
                                const $p15579_i10148_i10418_i10717_i10854 = (() => {
                                  {
                                    const $p15576_i1532_i10138_i10409_i10708_i10845 = Random$next_raw(r2);
                                    {
                                      const hi_i1533_i10139_i10410_i10709_i10846 = $p15576_i1532_i10138_i10409_i10708_i10845._0;
                                      {
                                        const rng2_i1534_i10140_i10411_i10710_i10847 = $p15576_i1532_i10138_i10409_i10708_i10845._1;
                                        {
                                          const $p15575_i1535_i10141_i10412_i10711_i10848 = Random$next_raw(rng2_i1534_i10140_i10411_i10710_i10847);
                                          {
                                            const lo_i1536_i10142_i10413_i10712_i10849 = $p15575_i1535_i10141_i10412_i10711_i10848._0;
                                            {
                                              const rng3_i1537_i10143_i10414_i10713_i10850 = $p15575_i1535_i10141_i10412_i10711_i10848._1;
                                              {
                                                const $t15574_i1541_i10147_i10417_i10716_i10853 = (() => {
                                                  {
                                                    const $t15573_i1540_i10146_i10416_i10715_i10852 = (() => {
                                                      {
                                                        const $t15571_i1538_i10144_i10415_i10714_i10851 = march_int_and(hi_i1533_i10139_i10410_i10709_i10846, 1048575);
                                                        return ($t15571_i1538_i10144_i10415_i10714_i10851 * 4294967296);
                                                      }
                                                    })();
                                                    return ($t15573_i1540_i10146_i10416_i10715_i10852 + lo_i1536_i10142_i10413_i10712_i10849);
                                                  }
                                                })();
                                                return { _0: $t15574_i1541_i10147_i10417_i10716_i10853, _1: rng3_i1537_i10143_i10414_i10713_i10850 };
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                })();
                                {
                                  const bits_i10149_i10419_i10718_i10855 = $p15579_i10148_i10418_i10717_i10854._0;
                                  {
                                    const rng2_i10150_i10420_i10719_i10856 = $p15579_i10148_i10418_i10717_i10854._1;
                                    {
                                      const $t15578_i10152_i10422_i10721_i10858 = (() => {
                                        {
                                          const $t15577_i10151_i10421_i10720_i10857 = bits_i10149_i10419_i10718_i10855;
                                          return ($t15577_i10151_i10421_i10720_i10857 / 4.50359962737e+15);
                                        }
                                      })();
                                      return { _0: $t15578_i10152_i10422_i10721_i10858, _1: rng2_i10150_i10420_i10719_i10856 };
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const t_i10424_i10723_i10860 = $p29016_i10423_i10722_i10859._0;
                              {
                                const rng2_i10425_i10724_i10861 = $p29016_i10423_i10722_i10859._1;
                                {
                                  const out_i10426_i10725_i10862 = { _0: rng2_i10425_i10724_i10861, _1: t_i10424_i10723_i10860 };
                                  return out_i10426_i10725_i10862;
                                }
                              }
                            }
                          }
                        })();
                        {
                          const r3 = $p27388._0;
                          {
                            const ang_f = $p27388._1;
                            {
                              const $p27387 = (() => {
                                {
                                  const $p29016_i10423_i10722_i10840 = (() => {
                                    {
                                      const $p15579_i10148_i10418_i10717_i10835 = (() => {
                                        {
                                          const $p15576_i1532_i10138_i10409_i10708_i10826 = Random$next_raw(r3);
                                          {
                                            const hi_i1533_i10139_i10410_i10709_i10827 = $p15576_i1532_i10138_i10409_i10708_i10826._0;
                                            {
                                              const rng2_i1534_i10140_i10411_i10710_i10828 = $p15576_i1532_i10138_i10409_i10708_i10826._1;
                                              {
                                                const $p15575_i1535_i10141_i10412_i10711_i10829 = Random$next_raw(rng2_i1534_i10140_i10411_i10710_i10828);
                                                {
                                                  const lo_i1536_i10142_i10413_i10712_i10830 = $p15575_i1535_i10141_i10412_i10711_i10829._0;
                                                  {
                                                    const rng3_i1537_i10143_i10414_i10713_i10831 = $p15575_i1535_i10141_i10412_i10711_i10829._1;
                                                    {
                                                      const $t15574_i1541_i10147_i10417_i10716_i10834 = (() => {
                                                        {
                                                          const $t15573_i1540_i10146_i10416_i10715_i10833 = (() => {
                                                            {
                                                              const $t15571_i1538_i10144_i10415_i10714_i10832 = march_int_and(hi_i1533_i10139_i10410_i10709_i10827, 1048575);
                                                              return ($t15571_i1538_i10144_i10415_i10714_i10832 * 4294967296);
                                                            }
                                                          })();
                                                          return ($t15573_i1540_i10146_i10416_i10715_i10833 + lo_i1536_i10142_i10413_i10712_i10830);
                                                        }
                                                      })();
                                                      return { _0: $t15574_i1541_i10147_i10417_i10716_i10834, _1: rng3_i1537_i10143_i10414_i10713_i10831 };
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      })();
                                      {
                                        const bits_i10149_i10419_i10718_i10836 = $p15579_i10148_i10418_i10717_i10835._0;
                                        {
                                          const rng2_i10150_i10420_i10719_i10837 = $p15579_i10148_i10418_i10717_i10835._1;
                                          {
                                            const $t15578_i10152_i10422_i10721_i10839 = (() => {
                                              {
                                                const $t15577_i10151_i10421_i10720_i10838 = bits_i10149_i10419_i10718_i10836;
                                                return ($t15577_i10151_i10421_i10720_i10838 / 4.50359962737e+15);
                                              }
                                            })();
                                            return { _0: $t15578_i10152_i10422_i10721_i10839, _1: rng2_i10150_i10420_i10719_i10837 };
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const t_i10424_i10723_i10841 = $p29016_i10423_i10722_i10840._0;
                                    {
                                      const rng2_i10425_i10724_i10842 = $p29016_i10423_i10722_i10840._1;
                                      {
                                        const out_i10426_i10725_i10843 = { _0: rng2_i10425_i10724_i10842, _1: t_i10424_i10723_i10841 };
                                        return out_i10426_i10725_i10843;
                                      }
                                    }
                                  }
                                }
                              })();
                              {
                                const r4 = $p27387._0;
                                {
                                  const next_f = $p27387._1;
                                  {
                                    const $p27386 = (() => {
                                      {
                                        const $p29016_i10423_i10722_i10821 = (() => {
                                          {
                                            const $p15579_i10148_i10418_i10717_i10816 = (() => {
                                              {
                                                const $p15576_i1532_i10138_i10409_i10708_i10807 = Random$next_raw(r4);
                                                {
                                                  const hi_i1533_i10139_i10410_i10709_i10808 = $p15576_i1532_i10138_i10409_i10708_i10807._0;
                                                  {
                                                    const rng2_i1534_i10140_i10411_i10710_i10809 = $p15576_i1532_i10138_i10409_i10708_i10807._1;
                                                    {
                                                      const $p15575_i1535_i10141_i10412_i10711_i10810 = Random$next_raw(rng2_i1534_i10140_i10411_i10710_i10809);
                                                      {
                                                        const lo_i1536_i10142_i10413_i10712_i10811 = $p15575_i1535_i10141_i10412_i10711_i10810._0;
                                                        {
                                                          const rng3_i1537_i10143_i10414_i10713_i10812 = $p15575_i1535_i10141_i10412_i10711_i10810._1;
                                                          {
                                                            const $t15574_i1541_i10147_i10417_i10716_i10815 = (() => {
                                                              {
                                                                const $t15573_i1540_i10146_i10416_i10715_i10814 = (() => {
                                                                  {
                                                                    const $t15571_i1538_i10144_i10415_i10714_i10813 = march_int_and(hi_i1533_i10139_i10410_i10709_i10808, 1048575);
                                                                    return ($t15571_i1538_i10144_i10415_i10714_i10813 * 4294967296);
                                                                  }
                                                                })();
                                                                return ($t15573_i1540_i10146_i10416_i10715_i10814 + lo_i1536_i10142_i10413_i10712_i10811);
                                                              }
                                                            })();
                                                            return { _0: $t15574_i1541_i10147_i10417_i10716_i10815, _1: rng3_i1537_i10143_i10414_i10713_i10812 };
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            })();
                                            {
                                              const bits_i10149_i10419_i10718_i10817 = $p15579_i10148_i10418_i10717_i10816._0;
                                              {
                                                const rng2_i10150_i10420_i10719_i10818 = $p15579_i10148_i10418_i10717_i10816._1;
                                                {
                                                  const $t15578_i10152_i10422_i10721_i10820 = (() => {
                                                    {
                                                      const $t15577_i10151_i10421_i10720_i10819 = bits_i10149_i10419_i10718_i10817;
                                                      return ($t15577_i10151_i10421_i10720_i10819 / 4.50359962737e+15);
                                                    }
                                                  })();
                                                  return { _0: $t15578_i10152_i10422_i10721_i10820, _1: rng2_i10150_i10420_i10719_i10818 };
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        {
                                          const t_i10424_i10723_i10822 = $p29016_i10423_i10722_i10821._0;
                                          {
                                            const rng2_i10425_i10724_i10823 = $p29016_i10423_i10722_i10821._1;
                                            {
                                              const out_i10426_i10725_i10824 = { _0: rng2_i10425_i10724_i10823, _1: t_i10424_i10723_i10822 };
                                              return out_i10426_i10725_i10824;
                                            }
                                          }
                                        }
                                      }
                                    })();
                                    {
                                      const r5 = $p27386._0;
                                      {
                                        const shape_f = $p27386._1;
                                        {
                                          const from_left = (side_f < 0.5);
                                          {
                                            let x;
                                            if (from_left === true) {
                                              x = (0. - 20.);
                                            } else {
                                              x = (() => {
                                                {
                                                  const $t27366 = game.view_w;
                                                  return ($t27366 + 20.);
                                                }
                                              })();
                                            }
                                            {
                                              const y = (() => {
                                                {
                                                  const $t27367 = game.camera_y;
                                                  {
                                                    const $t27369 = (() => {
                                                      {
                                                        const $t27368 = game.view_h;
                                                        return (y_f * $t27368);
                                                      }
                                                    })();
                                                    return ($t27367 + $t27369);
                                                  }
                                                }
                                              })();
                                              {
                                                const jitter = (() => {
                                                  {
                                                    const $t27370 = (ang_f - 0.5);
                                                    return ($t27370 * 1.0472);
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
                                                        const $t27372 = (dir_x * 90.);
                                                        {
                                                          const $t27373 = Math.cos(jitter);
                                                          return ($t27372 * $t27373);
                                                        }
                                                      }
                                                    })();
                                                    {
                                                      const vy = (() => {
                                                        {
                                                          const $t27375 = Math.sin(jitter);
                                                          return (90. * $t27375);
                                                        }
                                                      })();
                                                      {
                                                        const a = (() => {
                                                          {
                                                            const $t27377 = { $: "AsteroidDrifting" };
                                                            return ({ x: x, y: y, vx: vx, vy: vy, radius: 10., shape_seed: shape_f, mode: $t27377 });
                                                          }
                                                        })();
                                                        {
                                                          const $t27378 = game.asteroids;
                                                          {
                                                            const $t27379 = (() => {
                                                              return { $: "Cons", _0: a, _1: $t27378 };
                                                            })();
                                                            {
                                                              const $t27385 = (() => {
                                                                {
                                                                  const $t27384 = (() => {
                                                                    {
                                                                      const $t27382 = (() => {
                                                                        {
                                                                          const $t27381 = (next_f - 0.5);
                                                                          return ($t27381 * 2.);
                                                                        }
                                                                      })();
                                                                      return ($t27382 * 1.);
                                                                    }
                                                                  })();
                                                                  return (4. + $t27384);
                                                                }
                                                              })();
                                                              return ({ ...game, asteroids: $t27379, rng: r5, spawn_timer: $t27385 });
                                                            }
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
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
    const $t27402 = (() => {
      {
        const $t27399 = (() => {
          {
            const $t27393 = (() => {
              {
                const $t27392 = (() => {
                  {
                    const $t27391 = game.camera_y;
                    return ($t27391 - 100.);
                  }
                })();
                return (y > $t27392);
              }
            })();
            {
              const $t27398 = (() => {
                {
                  const $t27397 = (() => {
                    {
                      const $t27396 = (() => {
                        {
                          const $t27394 = game.camera_y;
                          {
                            const $t27395 = game.view_h;
                            return ($t27394 + $t27395);
                          }
                        }
                      })();
                      return ($t27396 + 100.);
                    }
                  })();
                  return (y < $t27397);
                }
              })();
              return ($t27393 && $t27398);
            }
          }
        })();
        {
          const $t27401 = (() => {
            {
              const $t27400 = (0. - 100.);
              return (x > $t27400);
            }
          })();
          return ($t27399 && $t27401);
        }
      }
    })();
    {
      const $t27405 = (() => {
        {
          const $t27404 = (() => {
            {
              const $t27403 = game.view_w;
              return ($t27403 + 100.);
            }
          })();
          return (x < $t27404);
        }
      })();
      return ($t27402 && $t27405);
    }
  }
}
const Perihelion$Combat$in_band$clo = { _0: ($_, game, x, y) => Perihelion$Combat$in_band(game, x, y) };

function Perihelion$Combat$nearest_in_list_ast(x, y, asteroids, best_d2, best) {
  switch (asteroids.$) {
    case "Nil": {
      return { _0: best_d2, _1: best };
      break;
    }
    case "Cons": {
      const $f27415 = asteroids._0;
      const $f27416 = asteroids._1;
      {
        const rest = (() => {
          return $f27416;
        })();
        {
          const a = (() => {
            return $f27415;
          })();
          {
            const dx = (() => {
              {
                const $t27406 = a.x;
                return ($t27406 - x);
              }
            })();
            {
              const dy = (() => {
                {
                  const $t27407 = a.y;
                  return ($t27407 - y);
                }
              })();
              {
                const d2 = (() => {
                  {
                    const $t27408 = (dx * dx);
                    {
                      const $t27409 = (dy * dy);
                      return ($t27408 + $t27409);
                    }
                  }
                })();
                {
                  const $t27410 = (d2 < best_d2);
                  if ($t27410 === true) {
                    return (() => {
                      {
                        const $t27414 = (() => {
                          {
                            const $t27413 = (() => {
                              {
                                const $t27411 = a.x;
                                {
                                  const $t27412 = a.y;
                                  return { _0: $t27411, _1: $t27412 };
                                }
                              }
                            })();
                            return { $: "Some", _0: $t27413 };
                          }
                        })();
                        return Perihelion$Combat$nearest_in_list_ast(x, y, rest, d2, $t27414);
                      }
                    })();
                  } else {
                    return (() => {
                      return Perihelion$Combat$nearest_in_list_ast(x, y, rest, best_d2, best);
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
const Perihelion$Combat$nearest_in_list_ast$clo = { _0: ($_, x, y, asteroids, best_d2, best) => Perihelion$Combat$nearest_in_list_ast(x, y, asteroids, best_d2, best) };

function Perihelion$Combat$nearest_in_list_ship(x, y, ships, best_d2, best) {
  switch (ships.$) {
    case "Nil": {
      return { _0: best_d2, _1: best };
      break;
    }
    case "Cons": {
      const $f27427 = ships._0;
      const $f27428 = ships._1;
      {
        const rest = (() => {
          return $f27428;
        })();
        {
          const sh = (() => {
            return $f27427;
          })();
          {
            const pos = (() => {
              {
                const pos_i3643 = (() => {
                  {
                    const $t27355_i3641 = sh.x;
                    {
                      const $t27356_i3642 = sh.y;
                      return { _0: $t27355_i3641, _1: $t27356_i3642 };
                    }
                  }
                })();
                return pos_i3643;
              }
            })();
            {
              const sx = pos._0;
              {
                const sy = pos._1;
                {
                  const dx = (sx - x);
                  {
                    const dy = (sy - y);
                    {
                      const d2 = (() => {
                        {
                          const $t27421 = (dx * dx);
                          {
                            const $t27422 = (dy * dy);
                            return ($t27421 + $t27422);
                          }
                        }
                      })();
                      {
                        const $t27423 = (d2 < best_d2);
                        if ($t27423 === true) {
                          return (() => {
                            {
                              const $t27425 = (() => {
                                {
                                  const $t27424 = { _0: sx, _1: sy };
                                  return { $: "Some", _0: $t27424 };
                                }
                              })();
                              return Perihelion$Combat$nearest_in_list_ship(x, y, rest, d2, $t27425);
                            }
                          })();
                        } else {
                          return (() => {
                            return Perihelion$Combat$nearest_in_list_ship(x, y, rest, best_d2, best);
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
      }
      break;
    }
    default: {
      return (() => { throw new Error("non-exhaustive pattern match"); })();
    }
  }
}
const Perihelion$Combat$nearest_in_list_ship$clo = { _0: ($_, x, y, ships, best_d2, best) => Perihelion$Combat$nearest_in_list_ship(x, y, ships, best_d2, best) };

function Perihelion$Combat$nearest_hazard_dir(x, y, asteroids, ships) {
  {
    const $p27447 = (() => {
      {
        const $t27435 = (220. * 220.);
        {
          const $t27436 = { $: "None" };
          return Perihelion$Combat$nearest_in_list_ast(x, y, asteroids, $t27435, $t27436);
        }
      }
    })();
    {
      const d2a = $p27447._0;
      {
        const besta = $p27447._1;
        {
          const $p27446 = (() => {
            return Perihelion$Combat$nearest_in_list_ship(x, y, ships, d2a, besta);
          })();
          {
            const bests = $p27446._1;
            switch (bests.$) {
              case "None": {
                return { $: "None" };
                break;
              }
              case "Some": {
                const $f27445 = bests._0;
                {
                  const pair = (() => {
                    return $f27445;
                  })();
                  {
                    const tx = pair._0;
                    {
                      const ty = pair._1;
                      {
                        const dx = (tx - x);
                        {
                          const dy = (ty - y);
                          {
                            const d = (() => {
                              {
                                const $t27439 = (() => {
                                  {
                                    const $t27437 = (dx * dx);
                                    {
                                      const $t27438 = (dy * dy);
                                      return ($t27437 + $t27438);
                                    }
                                  }
                                })();
                                return Math.sqrt($t27439);
                              }
                            })();
                            {
                              const $t27440 = (d > 0.);
                              if ($t27440 === true) {
                                return (() => {
                                  {
                                    const $t27443 = (() => {
                                      {
                                        const $t27441 = (dx / d);
                                        {
                                          const $t27442 = (dy / d);
                                          return { _0: $t27441, _1: $t27442 };
                                        }
                                      }
                                    })();
                                    return { $: "Some", _0: $t27443 };
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
const Perihelion$Combat$nearest_hazard_dir$clo = { _0: ($_, x, y, asteroids, ships) => Perihelion$Combat$nearest_hazard_dir(x, y, asteroids, ships) };

function Perihelion$Combat$age_shot(s, dt_s, asteroids, ships) {
  {
    const moved = (() => {
      {
        const $t27451 = (() => {
          {
            const $t27448 = s.x;
            {
              const $t27450 = (() => {
                {
                  const $t27449 = s.vx;
                  return ($t27449 * dt_s);
                }
              })();
              return ($t27448 + $t27450);
            }
          }
        })();
        {
          const $t27455 = (() => {
            {
              const $t27452 = s.y;
              {
                const $t27454 = (() => {
                  {
                    const $t27453 = s.vy;
                    return ($t27453 * dt_s);
                  }
                })();
                return ($t27452 + $t27454);
              }
            }
          })();
          {
            const $t27457 = (() => {
              {
                const $t27456 = s.ttl;
                return ($t27456 - dt_s);
              }
            })();
            return ({ ...s, x: $t27451, y: $t27455, ttl: $t27457 });
          }
        }
      }
    })();
    {
      const $t27459 = (() => {
        {
          const $t27458 = s.homing;
          return (!$t27458);
        }
      })();
      if ($t27459 === true) {
        return moved;
      } else {
        return (() => {
          {
            const $t27462 = (() => {
              {
                const $t27460 = s.x;
                {
                  const $t27461 = s.y;
                  return Perihelion$Combat$nearest_hazard_dir($t27460, $t27461, asteroids, ships);
                }
              }
            })();
            switch ($t27462.$) {
              case "None": {
                return moved;
                break;
              }
              case "Some": {
                const $f27488 = $t27462._0;
                {
                  const pair = $f27488;
                  {
                    const tx = pair._0;
                    {
                      const ty = pair._1;
                      {
                        const speed = (() => {
                          {
                            const $t27469 = (() => {
                              {
                                const $t27465 = (() => {
                                  {
                                    const $t27463 = s.vx;
                                    {
                                      const $t27464 = s.vx;
                                      return ($t27463 * $t27464);
                                    }
                                  }
                                })();
                                {
                                  const $t27468 = (() => {
                                    {
                                      const $t27466 = s.vy;
                                      {
                                        const $t27467 = s.vy;
                                        return ($t27466 * $t27467);
                                      }
                                    }
                                  })();
                                  return ($t27465 + $t27468);
                                }
                              }
                            })();
                            return Math.sqrt($t27469);
                          }
                        })();
                        {
                          const cur_ax = (() => {
                            {
                              const $t27470 = s.vx;
                              return ($t27470 / speed);
                            }
                          })();
                          {
                            const cur_ay = (() => {
                              {
                                const $t27471 = s.vy;
                                return ($t27471 / speed);
                              }
                            })();
                            {
                              const turned_ax = (() => {
                                {
                                  const $t27475 = (() => {
                                    {
                                      const $t27474 = (() => {
                                        {
                                          const $t27472 = (tx - cur_ax);
                                          return ($t27472 * 3.);
                                        }
                                      })();
                                      return ($t27474 * dt_s);
                                    }
                                  })();
                                  return (cur_ax + $t27475);
                                }
                              })();
                              {
                                const turned_ay = (() => {
                                  {
                                    const $t27479 = (() => {
                                      {
                                        const $t27478 = (() => {
                                          {
                                            const $t27476 = (ty - cur_ay);
                                            return ($t27476 * 3.);
                                          }
                                        })();
                                        return ($t27478 * dt_s);
                                      }
                                    })();
                                    return (cur_ay + $t27479);
                                  }
                                })();
                                {
                                  const norm = (() => {
                                    {
                                      const $t27482 = (() => {
                                        {
                                          const $t27480 = (turned_ax * turned_ax);
                                          {
                                            const $t27481 = (turned_ay * turned_ay);
                                            return ($t27480 + $t27481);
                                          }
                                        }
                                      })();
                                      return Math.sqrt($t27482);
                                    }
                                  })();
                                  {
                                    const $t27484 = (() => {
                                      {
                                        const $t27483 = (turned_ax / norm);
                                        return ($t27483 * speed);
                                      }
                                    })();
                                    {
                                      const $t27486 = (() => {
                                        {
                                          const $t27485 = (turned_ay / norm);
                                          return ($t27485 * speed);
                                        }
                                      })();
                                      return ({ ...moved, vx: $t27484, vy: $t27486 });
                                    }
                                  }
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
        })();
      }
    }
  }
}
const Perihelion$Combat$age_shot$clo = { _0: ($_, s, dt_s, asteroids, ships) => Perihelion$Combat$age_shot(s, dt_s, asteroids, ships) };

function Perihelion$Combat$step_entities(game, dt_s) {
  {
    const g1 = Perihelion$Combat$step_asteroids(game, dt_s);
    {
      const $t27489 = g1.player_shots;
      {
        const $t27493 = { $: "$Clo_$lam27490$3672", _0: $lam27490$apply$3672, _1: dt_s, _2: g1 };
        {
          const $t27494 = (() => {
            {
              const f_i3670 = $t27493;
              {
                const go_i3671 = { $: "$Clo_go$4755", _0: go$apply$4755, _1: f_i3670 };
                {
                  const $t270_i3672 = { $: "Nil" };
                  return go$apply$4755(go_i3671, $t27489, $t270_i3672);
                }
              }
            }
          })();
          {
            const $t27501 = { $: "$Clo_$lam27495$3673", _0: $lam27495$apply$3673, _1: g1 };
            {
              const p_shots = (() => {
                {
                  const pred_i3666 = $t27501;
                  {
                    const go_i3667 = { $: "$Clo_go$4753", _0: go$apply$4753, _1: pred_i3666 };
                    {
                      const $t302_i3668 = { $: "Nil" };
                      return go$apply$4753(go_i3667, $t27494, $t302_i3668);
                    }
                  }
                }
              })();
              {
                const $t27502 = g1.enemy_shots;
                {
                  const $t27506 = { $: "$Clo_$lam27503$3674", _0: $lam27503$apply$3674, _1: dt_s, _2: g1 };
                  {
                    const $t27507 = (() => {
                      {
                        const f_i3662 = $t27506;
                        {
                          const go_i3663 = { $: "$Clo_go$4755", _0: go$apply$4755, _1: f_i3662 };
                          {
                            const $t270_i3664 = { $: "Nil" };
                            return go$apply$4755(go_i3663, $t27502, $t270_i3664);
                          }
                        }
                      }
                    })();
                    {
                      const $t27514 = { $: "$Clo_$lam27508$3675", _0: $lam27508$apply$3675, _1: g1 };
                      {
                        const e_shots = (() => {
                          {
                            const pred_i3658 = $t27514;
                            {
                              const go_i3659 = { $: "$Clo_go$4753", _0: go$apply$4753, _1: pred_i3658 };
                              {
                                const $t302_i3660 = { $: "Nil" };
                                return go$apply$4753(go_i3659, $t27507, $t302_i3660);
                              }
                            }
                          }
                        })();
                        {
                          const $t27515 = g1.pickups;
                          {
                            const $t27519 = { $: "$Clo_$lam27516$3676", _0: $lam27516$apply$3676, _1: dt_s };
                            {
                              const $t27520 = (() => {
                                {
                                  const f_i3654 = $t27519;
                                  {
                                    const go_i3655 = { $: "$Clo_go$4751", _0: go$apply$4751, _1: f_i3654 };
                                    {
                                      const $t270_i3656 = { $: "Nil" };
                                      return go$apply$4751(go_i3655, $t27515, $t270_i3656);
                                    }
                                  }
                                }
                              })();
                              {
                                const $t27523 = { $: "$Clo_$lam27521$3677", _0: $lam27521$apply$3677 };
                                {
                                  const pickups = (() => {
                                    {
                                      const pred_i3650 = $t27523;
                                      {
                                        const go_i3651 = { $: "$Clo_go$4749", _0: go$apply$4749, _1: pred_i3650 };
                                        {
                                          const $t302_i3652 = { $: "Nil" };
                                          return go$apply$4749(go_i3651, $t27520, $t302_i3652);
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t27527 = (() => {
                                      {
                                        const $t27525 = (() => {
                                          {
                                            const $t27524 = g1.fire_cooldown;
                                            return ($t27524 > 0.);
                                          }
                                        })();
                                        if ($t27525 === true) {
                                          return (() => {
                                            {
                                              const $t27526 = g1.fire_cooldown;
                                              return ($t27526 - dt_s);
                                            }
                                          })();
                                        } else {
                                          return 0.;
                                        }
                                      }
                                    })();
                                    {
                                      const $t27531 = (() => {
                                        {
                                          const $t27529 = (() => {
                                            {
                                              const $t27528 = g1.starkiller_cooldown;
                                              return ($t27528 > 0.);
                                            }
                                          })();
                                          if ($t27529 === true) {
                                            return (() => {
                                              {
                                                const $t27530 = g1.starkiller_cooldown;
                                                return ($t27530 - dt_s);
                                              }
                                            })();
                                          } else {
                                            return 0.;
                                          }
                                        }
                                      })();
                                      return ({ ...g1, player_shots: p_shots, enemy_shots: e_shots, pickups: pickups, fire_cooldown: $t27527, starkiller_cooldown: $t27531 });
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
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
      const $f27538 = stars._0;
      const $f27539 = stars._1;
      {
        const rest = $f27539;
        {
          const s = $f27538;
          {
            const dx = (() => {
              {
                const $t27532 = s.x;
                return ($t27532 - x);
              }
            })();
            {
              const dy = (() => {
                {
                  const $t27533 = s.y;
                  return ($t27533 - y);
                }
              })();
              {
                const d = (() => {
                  {
                    const $t27534 = (dx * dx);
                    {
                      const $t27535 = (dy * dy);
                      return ($t27534 + $t27535);
                    }
                  }
                })();
                {
                  const $t27536 = (d < best_d);
                  if ($t27536 === true) {
                    return (() => {
                      {
                        const $t27537 = { $: "Some", _0: s };
                        return Perihelion$Combat$nearest_star_for_asteroid(x, y, rest, $t27537, d);
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
    const $t27546 = (() => {
      {
        const $t27544 = { $: "None" };
        {
          const $t27545 = (240. * 240.);
          return Perihelion$Combat$nearest_star_for_asteroid(x, y, stars, $t27544, $t27545);
        }
      }
    })();
    switch ($t27546.$) {
      case "None": {
        {
          const out = { _0: vx, _1: vy };
          return out;
        }
        break;
      }
      case "Some": {
        const $f27572 = $t27546._0;
        {
          const s = $f27572;
          {
            const dx = (() => {
              {
                const $t27547 = s.x;
                return ($t27547 - x);
              }
            })();
            {
              const dy = (() => {
                {
                  const $t27548 = s.y;
                  return ($t27548 - y);
                }
              })();
              {
                const dist = (() => {
                  {
                    const $t27551 = (() => {
                      {
                        const $t27549 = (dx * dx);
                        {
                          const $t27550 = (dy * dy);
                          return ($t27549 + $t27550);
                        }
                      }
                    })();
                    return Math.sqrt($t27551);
                  }
                })();
                {
                  const $t27552 = (dist > 0.);
                  if ($t27552 === true) {
                    return (() => {
                      {
                        const speed = (() => {
                          {
                            const $t27555 = (() => {
                              {
                                const $t27553 = (vx * vx);
                                {
                                  const $t27554 = (vy * vy);
                                  return ($t27553 + $t27554);
                                }
                              }
                            })();
                            return Math.sqrt($t27555);
                          }
                        })();
                        {
                          const nvx = (() => {
                            {
                              const $t27559 = (() => {
                                {
                                  const $t27558 = (() => {
                                    {
                                      const $t27556 = (dx / dist);
                                      return ($t27556 * 500.);
                                    }
                                  })();
                                  return ($t27558 * dt_s);
                                }
                              })();
                              return (vx + $t27559);
                            }
                          })();
                          {
                            const nvy = (() => {
                              {
                                const $t27563 = (() => {
                                  {
                                    const $t27562 = (() => {
                                      {
                                        const $t27560 = (dy / dist);
                                        return ($t27560 * 500.);
                                      }
                                    })();
                                    return ($t27562 * dt_s);
                                  }
                                })();
                                return (vy + $t27563);
                              }
                            })();
                            {
                              const nspeed = (() => {
                                {
                                  const $t27566 = (() => {
                                    {
                                      const $t27564 = (nvx * nvx);
                                      {
                                        const $t27565 = (nvy * nvy);
                                        return ($t27564 + $t27565);
                                      }
                                    }
                                  })();
                                  return Math.sqrt($t27566);
                                }
                              })();
                              {
                                const $t27567 = (nspeed > 0.);
                                if ($t27567 === true) {
                                  return (() => {
                                    {
                                      const $t27569 = (() => {
                                        {
                                          const $t27568 = (nvx / nspeed);
                                          return ($t27568 * speed);
                                        }
                                      })();
                                      {
                                        const $t27571 = (() => {
                                          {
                                            const $t27570 = (nvy / nspeed);
                                            return ($t27570 * speed);
                                          }
                                        })();
                                        return { _0: $t27569, _1: $t27571 };
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
        const $t27573 = (() => {
          {
            const go_i3680 = { $: "$Clo_go$4757", _0: go$apply$4757 };
            {
              const $t253_i3681 = { $: "Nil" };
              return go$apply$4757(go_i3680, acc, $t253_i3681);
            }
          }
        })();
        return ({ ...game, asteroids: $t27573 });
      }
      break;
    }
    case "Cons": {
      const $f27637 = asteroids._0;
      const $f27638 = asteroids._1;
      {
        const rest = $f27638;
        {
          const a = $f27637;
          {
            const $t27574 = a.mode;
            switch ($t27574.$) {
              case "AsteroidOrbiting": {
                const $f27631 = $t27574._0;
                const $f27632 = $t27574._1;
                {
                  const angle = (() => {
                    return $f27632;
                  })();
                  {
                    const idx = (() => {
                      return $f27631;
                    })();
                    {
                      const $t27575 = Perihelion$Core$star_at(game, idx);
                      switch ($t27575.$) {
                        case "None": {
                          return Perihelion$Combat$step_asteroids_go(game, rest, acc, dt_s);
                          break;
                        }
                        case "Some": {
                          const $f27590 = $t27575._0;
                          {
                            const s = $f27590;
                            {
                              const angle2 = (() => {
                                {
                                  const $t27577 = (1. * dt_s);
                                  return (angle + $t27577);
                                }
                              })();
                              {
                                const r = (() => {
                                  {
                                    const $t27578 = s.capture_radius;
                                    return ($t27578 * 0.8);
                                  }
                                })();
                                {
                                  const a2 = (() => {
                                    {
                                      const $t27583 = (() => {
                                        {
                                          const $t27580 = s.x;
                                          {
                                            const $t27582 = (() => {
                                              {
                                                const $t27581 = Math.cos(angle2);
                                                return ($t27581 * r);
                                              }
                                            })();
                                            return ($t27580 + $t27582);
                                          }
                                        }
                                      })();
                                      {
                                        const $t27587 = (() => {
                                          {
                                            const $t27584 = s.y;
                                            {
                                              const $t27586 = (() => {
                                                {
                                                  const $t27585 = Math.sin(angle2);
                                                  return ($t27585 * r);
                                                }
                                              })();
                                              return ($t27584 + $t27586);
                                            }
                                          }
                                        })();
                                        {
                                          const $t27588 = { $: "AsteroidOrbiting", _0: idx, _1: angle2 };
                                          return ({ ...a, x: $t27583, y: $t27587, mode: $t27588 });
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t27589 = { $: "Cons", _0: a2, _1: acc };
                                    return Perihelion$Combat$step_asteroids_go(game, rest, $t27589, dt_s);
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
                      const $t27591 = a.x;
                      {
                        const $t27592 = a.y;
                        {
                          const $t27593 = a.vx;
                          {
                            const $t27594 = a.vy;
                            {
                              const $t27595 = game.stars;
                              return Perihelion$Combat$arc_velocity($t27591, $t27592, $t27593, $t27594, $t27595, dt_s);
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
                            const $t27596 = a.x;
                            {
                              const $t27597 = (vx2 * dt_s);
                              return ($t27596 + $t27597);
                            }
                          }
                        })();
                        {
                          const y2 = (() => {
                            {
                              const $t27598 = a.y;
                              {
                                const $t27599 = (vy2 * dt_s);
                                return ($t27598 + $t27599);
                              }
                            }
                          })();
                          {
                            const $t27601 = (() => {
                              {
                                const $t27600 = Perihelion$Combat$in_band(game, x2, y2);
                                return (!$t27600);
                              }
                            })();
                            if ($t27601 === true) {
                              return Perihelion$Combat$step_asteroids_go(game, rest, acc, dt_s);
                            } else {
                              return (() => {
                                {
                                  const $t27603 = (() => {
                                    {
                                      const $t27602 = game.stars;
                                      return Perihelion$Combat$arrived_star($t27602, x2, y2, 0);
                                    }
                                  })();
                                  switch ($t27603.$) {
                                    case "None": {
                                      {
                                        const a2 = ({ ...a, x: x2, y: y2, vx: vx2, vy: vy2 });
                                        {
                                          const $t27604 = { $: "Cons", _0: a2, _1: acc };
                                          return Perihelion$Combat$step_asteroids_go(game, rest, $t27604, dt_s);
                                        }
                                      }
                                      break;
                                    }
                                    case "Some": {
                                      const $f27629 = $t27603._0;
                                      {
                                        const pair = $f27629;
                                        {
                                          const idx = pair._0;
                                          {
                                            const s = pair._1;
                                            {
                                              const $p27627 = (() => {
                                                {
                                                  const $t27605 = game.rng;
                                                  {
                                                    const $p29016_i10423_i10722_i10916 = (() => {
                                                      {
                                                        const $p15579_i10148_i10418_i10717_i10911 = (() => {
                                                          {
                                                            const $p15576_i1532_i10138_i10409_i10708_i10902 = Random$next_raw($t27605);
                                                            {
                                                              const hi_i1533_i10139_i10410_i10709_i10903 = $p15576_i1532_i10138_i10409_i10708_i10902._0;
                                                              {
                                                                const rng2_i1534_i10140_i10411_i10710_i10904 = $p15576_i1532_i10138_i10409_i10708_i10902._1;
                                                                {
                                                                  const $p15575_i1535_i10141_i10412_i10711_i10905 = Random$next_raw(rng2_i1534_i10140_i10411_i10710_i10904);
                                                                  {
                                                                    const lo_i1536_i10142_i10413_i10712_i10906 = $p15575_i1535_i10141_i10412_i10711_i10905._0;
                                                                    {
                                                                      const rng3_i1537_i10143_i10414_i10713_i10907 = $p15575_i1535_i10141_i10412_i10711_i10905._1;
                                                                      {
                                                                        const $t15574_i1541_i10147_i10417_i10716_i10910 = (() => {
                                                                          {
                                                                            const $t15573_i1540_i10146_i10416_i10715_i10909 = (() => {
                                                                              {
                                                                                const $t15571_i1538_i10144_i10415_i10714_i10908 = march_int_and(hi_i1533_i10139_i10410_i10709_i10903, 1048575);
                                                                                return ($t15571_i1538_i10144_i10415_i10714_i10908 * 4294967296);
                                                                              }
                                                                            })();
                                                                            return ($t15573_i1540_i10146_i10416_i10715_i10909 + lo_i1536_i10142_i10413_i10712_i10906);
                                                                          }
                                                                        })();
                                                                        return { _0: $t15574_i1541_i10147_i10417_i10716_i10910, _1: rng3_i1537_i10143_i10414_i10713_i10907 };
                                                                      }
                                                                    }
                                                                  }
                                                                }
                                                              }
                                                            }
                                                          }
                                                        })();
                                                        {
                                                          const bits_i10149_i10419_i10718_i10912 = $p15579_i10148_i10418_i10717_i10911._0;
                                                          {
                                                            const rng2_i10150_i10420_i10719_i10913 = $p15579_i10148_i10418_i10717_i10911._1;
                                                            {
                                                              const $t15578_i10152_i10422_i10721_i10915 = (() => {
                                                                {
                                                                  const $t15577_i10151_i10421_i10720_i10914 = bits_i10149_i10419_i10718_i10912;
                                                                  return ($t15577_i10151_i10421_i10720_i10914 / 4.50359962737e+15);
                                                                }
                                                              })();
                                                              return { _0: $t15578_i10152_i10422_i10721_i10915, _1: rng2_i10150_i10420_i10719_i10913 };
                                                            }
                                                          }
                                                        }
                                                      }
                                                    })();
                                                    {
                                                      const t_i10424_i10723_i10917 = $p29016_i10423_i10722_i10916._0;
                                                      {
                                                        const rng2_i10425_i10724_i10918 = $p29016_i10423_i10722_i10916._1;
                                                        {
                                                          const out_i10426_i10725_i10919 = { _0: rng2_i10425_i10724_i10918, _1: t_i10424_i10723_i10917 };
                                                          return out_i10426_i10725_i10919;
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              })();
                                              {
                                                const rng2 = $p27627._0;
                                                {
                                                  const roll = $p27627._1;
                                                  {
                                                    const $t27607 = (roll < 0.35);
                                                    if ($t27607 === true) {
                                                      return (() => {
                                                        {
                                                          const angle = (() => {
                                                            {
                                                              const $t27609 = (() => {
                                                                {
                                                                  const $t27608 = s.y;
                                                                  return (y2 - $t27608);
                                                                }
                                                              })();
                                                              {
                                                                const $t27611 = (() => {
                                                                  {
                                                                    const $t27610 = s.x;
                                                                    return (x2 - $t27610);
                                                                  }
                                                                })();
                                                                return Math.atan2($t27609, $t27611);
                                                              }
                                                            }
                                                          })();
                                                          {
                                                            const r = (() => {
                                                              {
                                                                const $t27612 = s.capture_radius;
                                                                return ($t27612 * 0.8);
                                                              }
                                                            })();
                                                            {
                                                              const a2 = (() => {
                                                                {
                                                                  const $t27617 = (() => {
                                                                    {
                                                                      const $t27614 = s.x;
                                                                      {
                                                                        const $t27616 = (() => {
                                                                          {
                                                                            const $t27615 = Math.cos(angle);
                                                                            return ($t27615 * r);
                                                                          }
                                                                        })();
                                                                        return ($t27614 + $t27616);
                                                                      }
                                                                    }
                                                                  })();
                                                                  {
                                                                    const $t27621 = (() => {
                                                                      {
                                                                        const $t27618 = s.y;
                                                                        {
                                                                          const $t27620 = (() => {
                                                                            {
                                                                              const $t27619 = Math.sin(angle);
                                                                              return ($t27619 * r);
                                                                            }
                                                                          })();
                                                                          return ($t27618 + $t27620);
                                                                        }
                                                                      }
                                                                    })();
                                                                    {
                                                                      const $t27622 = { $: "AsteroidOrbiting", _0: idx, _1: angle };
                                                                      return ({ ...a, x: $t27617, y: $t27621, mode: $t27622 });
                                                                    }
                                                                  }
                                                                }
                                                              })();
                                                              {
                                                                const $t27623 = ({ ...game, rng: rng2 });
                                                                {
                                                                  const $t27624 = { $: "Cons", _0: a2, _1: acc };
                                                                  return Perihelion$Combat$step_asteroids_go($t27623, rest, $t27624, dt_s);
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
                                                            const $t27625 = ({ ...game, rng: rng2 });
                                                            {
                                                              const $t27626 = { $: "Cons", _0: a2, _1: acc };
                                                              return Perihelion$Combat$step_asteroids_go($t27625, rest, $t27626, dt_s);
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
    const $t27643 = game.asteroids;
    {
      const $t27644 = { $: "Nil" };
      return Perihelion$Combat$step_asteroids_go(game, $t27643, $t27644, dt_s);
    }
  }
}
const Perihelion$Combat$step_asteroids$clo = { _0: ($_, game, dt_s) => Perihelion$Combat$step_asteroids(game, dt_s) };

function Perihelion$Combat$step_ships(game, dt_s) {
  {
    const $t27645 = game.ships;
    {
      const $t27646 = { $: "Nil" };
      {
        const $t27647 = { $: "Nil" };
        return Perihelion$Combat$step_ships_go(game, $t27645, $t27646, $t27647, dt_s);
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
      const $f27658 = stars._0;
      const $f27659 = stars._1;
      {
        const rest = (() => {
          return $f27659;
        })();
        {
          const s = (() => {
            return $f27658;
          })();
          {
            const $t27648 = (i === skip_idx);
            if ($t27648 === true) {
              return (() => {
                {
                  const $t27649 = (i + 1);
                  return Perihelion$Combat$nearest_other_star(from_x, from_y, skip_idx, rest, $t27649, best, best_d);
                }
              })();
            } else {
              return (() => {
                {
                  const dx = (() => {
                    {
                      const $t27650 = s.x;
                      return ($t27650 - from_x);
                    }
                  })();
                  {
                    const dy = (() => {
                      {
                        const $t27651 = s.y;
                        return ($t27651 - from_y);
                      }
                    })();
                    {
                      const d = (() => {
                        {
                          const $t27652 = (dx * dx);
                          {
                            const $t27653 = (dy * dy);
                            return ($t27652 + $t27653);
                          }
                        }
                      })();
                      {
                        const $t27654 = (d < best_d);
                        {
                          const $jp997_$t27655 = (i + 1);
                          if ($t27654 === true) {
                            return (() => {
                              {
                                const $t27656 = { $: "Some", _0: i };
                                return Perihelion$Combat$nearest_other_star(from_x, from_y, skip_idx, rest, $jp997_$t27655, $t27656, d);
                              }
                            })();
                          } else {
                            return (() => {
                              return Perihelion$Combat$nearest_other_star(from_x, from_y, skip_idx, rest, $jp997_$t27655, best, best_d);
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
      const $f27674 = stars._0;
      const $f27675 = stars._1;
      {
        const rest = $f27675;
        {
          const s = $f27674;
          {
            const dx = (() => {
              {
                const $t27664 = s.x;
                return ($t27664 - x);
              }
            })();
            {
              const dy = (() => {
                {
                  const $t27665 = s.y;
                  return ($t27665 - y);
                }
              })();
              {
                const $t27671 = (() => {
                  {
                    const $t27669 = (() => {
                      {
                        const $t27668 = (() => {
                          {
                            const $t27666 = (dx * dx);
                            {
                              const $t27667 = (dy * dy);
                              return ($t27666 + $t27667);
                            }
                          }
                        })();
                        return Math.sqrt($t27668);
                      }
                    })();
                    {
                      const $t27670 = s.capture_radius;
                      return ($t27669 <= $t27670);
                    }
                  }
                })();
                if ($t27671 === true) {
                  return (() => {
                    {
                      const $t27672 = { _0: i, _1: s };
                      return { $: "Some", _0: $t27672 };
                    }
                  })();
                } else {
                  return (() => {
                    {
                      const $t27673 = (i + 1);
                      return Perihelion$Combat$arrived_star(rest, x, y, $t27673);
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
        const $t27680 = game.ball_x;
        return ($t27680 - sx);
      }
    })();
    {
      const dy = (() => {
        {
          const $t27681 = game.ball_y;
          return ($t27681 - sy);
        }
      })();
      {
        const dist = (() => {
          {
            const $t27684 = (() => {
              {
                const $t27682 = (dx * dx);
                {
                  const $t27683 = (dy * dy);
                  return ($t27682 + $t27683);
                }
              }
            })();
            return Math.sqrt($t27684);
          }
        })();
        {
          const $t27685 = (dist > 0.);
          if ($t27685 === true) {
            return (() => {
              {
                const $t27688 = (() => {
                  {
                    const $t27686 = (dx / dist);
                    return ($t27686 * 150.);
                  }
                })();
                {
                  const $t27691 = (() => {
                    {
                      const $t27689 = (dy / dist);
                      return ($t27689 * 150.);
                    }
                  })();
                  return ({ x: sx, y: sy, vx: $t27688, vy: $t27691, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                }
              }
            })();
          } else {
            return ({ x: sx, y: sy, vx: 0., vy: 150., ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
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
        const $t27695 = (() => {
          {
            const go_i3697 = { $: "$Clo_go$4761", _0: go$apply$4761 };
            {
              const $t253_i3698 = { $: "Nil" };
              return go$apply$4761(go_i3697, acc, $t253_i3698);
            }
          }
        })();
        {
          const $t27696 = game.enemy_shots;
          {
            const $t27697 = (() => {
              {
                const go_i9845 = { $: "$Clo_go$4759", _0: go$apply$4759 };
                {
                  const $t261_i9848 = (() => {
                    {
                      const go_i4478_i9846 = { $: "$Clo_go$5242", _0: go$apply$5242 };
                      {
                        const $t253_i4479_i9847 = { $: "Nil" };
                        return go$apply$5242(go_i4478_i9846, new_shots, $t253_i4479_i9847);
                      }
                    }
                  })();
                  return go$apply$4759(go_i9845, $t261_i9848, $t27696);
                }
              }
            })();
            return ({ ...game, ships: $t27695, enemy_shots: $t27697 });
          }
        }
      }
      break;
    }
    case "Cons": {
      const $f27808 = ships._0;
      const $f27809 = ships._1;
      {
        const rest = $f27809;
        {
          const sh = $f27808;
          {
            const $t27698 = sh.mode;
            switch ($t27698.$) {
              case "ShipOrbiting": {
                const $f27801 = $t27698._0;
                {
                  const angle = (() => {
                    return $f27801;
                  })();
                  {
                    const $t27700 = (() => {
                      {
                        const $t27699 = sh.star_idx;
                        return Perihelion$Core$star_at(game, $t27699);
                      }
                    })();
                    switch ($t27700.$) {
                      case "None": {
                        return Perihelion$Combat$step_ships_go(game, rest, acc, new_shots, dt_s);
                        break;
                      }
                      case "Some": {
                        const $f27766 = $t27700._0;
                        {
                          const s = $f27766;
                          {
                            const idle2 = (() => {
                              {
                                const $t27701 = sh.idle_timer;
                                return ($t27701 - dt_s);
                              }
                            })();
                            {
                              const $t27702 = (idle2 <= 0.);
                              if ($t27702 === true) {
                                return (() => {
                                  {
                                    const $p27737 = (() => {
                                      {
                                        const $t27703 = sh.hunter;
                                        if ($t27703 === true) {
                                          return (() => {
                                            {
                                              const $t27704 = game.ball_x;
                                              {
                                                const $t27705 = game.ball_y;
                                                return { _0: $t27704, _1: $t27705 };
                                              }
                                            }
                                          })();
                                        } else {
                                          return (() => {
                                            {
                                              const $t27706 = sh.x;
                                              {
                                                const $t27707 = sh.y;
                                                return { _0: $t27706, _1: $t27707 };
                                              }
                                            }
                                          })();
                                        }
                                      }
                                    })();
                                    {
                                      const tx = $p27737._0;
                                      {
                                        const ty = $p27737._1;
                                        {
                                          const $t27711 = (() => {
                                            {
                                              const $t27708 = sh.star_idx;
                                              {
                                                const $t27709 = game.stars;
                                                {
                                                  const $t27710 = { $: "None" };
                                                  return Perihelion$Combat$nearest_other_star(tx, ty, $t27708, $t27709, 0, $t27710, 999999999.);
                                                }
                                              }
                                            }
                                          })();
                                          switch ($t27711.$) {
                                            case "None": {
                                              {
                                                const sh2 = ({ ...sh, idle_timer: 6. });
                                                {
                                                  const $t27713 = { $: "Cons", _0: sh2, _1: acc };
                                                  return Perihelion$Combat$step_ships_go(game, rest, $t27713, new_shots, dt_s);
                                                }
                                              }
                                              break;
                                            }
                                            case "Some": {
                                              const $f27736 = $t27711._0;
                                              {
                                                const target_idx = $f27736;
                                                {
                                                  const $t27714 = Perihelion$Core$star_at(game, target_idx);
                                                  switch ($t27714.$) {
                                                    case "None": {
                                                      {
                                                        const sh2 = ({ ...sh, idle_timer: 6. });
                                                        {
                                                          const $t27716 = { $: "Cons", _0: sh2, _1: acc };
                                                          return Perihelion$Combat$step_ships_go(game, rest, $t27716, new_shots, dt_s);
                                                        }
                                                      }
                                                      break;
                                                    }
                                                    case "Some": {
                                                      const $f27735 = $t27714._0;
                                                      {
                                                        const t = $f27735;
                                                        {
                                                          const dx = (() => {
                                                            {
                                                              const $t27717 = t.x;
                                                              {
                                                                const $t27718 = sh.x;
                                                                return ($t27717 - $t27718);
                                                              }
                                                            }
                                                          })();
                                                          {
                                                            const dy = (() => {
                                                              {
                                                                const $t27719 = t.y;
                                                                {
                                                                  const $t27720 = sh.y;
                                                                  return ($t27719 - $t27720);
                                                                }
                                                              }
                                                            })();
                                                            {
                                                              const dist = (() => {
                                                                {
                                                                  const $t27723 = (() => {
                                                                    {
                                                                      const $t27721 = (dx * dx);
                                                                      {
                                                                        const $t27722 = (dy * dy);
                                                                        return ($t27721 + $t27722);
                                                                      }
                                                                    }
                                                                  })();
                                                                  return Math.sqrt($t27723);
                                                                }
                                                              })();
                                                              {
                                                                const vel = (() => {
                                                                  {
                                                                    const $t27724 = (dist > 0.);
                                                                    if ($t27724 === true) {
                                                                      return (() => {
                                                                        {
                                                                          const $t27727 = (() => {
                                                                            {
                                                                              const $t27725 = (dx / dist);
                                                                              return ($t27725 * 180.);
                                                                            }
                                                                          })();
                                                                          {
                                                                            const $t27730 = (() => {
                                                                              {
                                                                                const $t27728 = (dy / dist);
                                                                                return ($t27728 * 180.);
                                                                              }
                                                                            })();
                                                                            return { _0: $t27727, _1: $t27730 };
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
                                                                          const $t27732 = { $: "ShipFlying", _0: vx, _1: vy };
                                                                          return ({ ...sh, mode: $t27732 });
                                                                        }
                                                                      })();
                                                                      {
                                                                        const $t27733 = { $: "Cons", _0: sh2, _1: acc };
                                                                        return Perihelion$Combat$step_ships_go(game, rest, $t27733, new_shots, dt_s);
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
                                          const $t27742 = (() => {
                                            {
                                              const $t27741 = (d * 1.4);
                                              return ($t27741 * dt_s);
                                            }
                                          })();
                                          return (angle + $t27742);
                                        }
                                      })();
                                      {
                                        const r = (() => {
                                          {
                                            const $t27743 = s.capture_radius;
                                            return ($t27743 * 1.6);
                                          }
                                        })();
                                        {
                                          const sx = (() => {
                                            {
                                              const $t27745 = s.x;
                                              {
                                                const $t27747 = (() => {
                                                  {
                                                    const $t27746 = Math.cos(angle2);
                                                    return ($t27746 * r);
                                                  }
                                                })();
                                                return ($t27745 + $t27747);
                                              }
                                            }
                                          })();
                                          {
                                            const sy = (() => {
                                              {
                                                const $t27748 = s.y;
                                                {
                                                  const $t27750 = (() => {
                                                    {
                                                      const $t27749 = Math.sin(angle2);
                                                      return ($t27749 * r);
                                                    }
                                                  })();
                                                  return ($t27748 + $t27750);
                                                }
                                              }
                                            })();
                                            {
                                              const cd2 = (() => {
                                                {
                                                  const $t27751 = sh.fire_cooldown;
                                                  return ($t27751 - dt_s);
                                                }
                                              })();
                                              {
                                                const in_range = (() => {
                                                  {
                                                    const $t27754 = (() => {
                                                      {
                                                        const $t27752 = game.ball_x;
                                                        {
                                                          const $t27753 = game.ball_y;
                                                          {
                                                            const dx_i3705 = ($t27752 - sx);
                                                            {
                                                              const dy_i3706 = ($t27753 - sy);
                                                              {
                                                                const $t27357_i3707 = (dx_i3705 * dx_i3705);
                                                                {
                                                                  const $t27358_i3708 = (dy_i3706 * dy_i3706);
                                                                  return ($t27357_i3707 + $t27358_i3708);
                                                                }
                                                              }
                                                            }
                                                          }
                                                        }
                                                      }
                                                    })();
                                                    {
                                                      const $t27757 = (380. * 380.);
                                                      return ($t27754 <= $t27757);
                                                    }
                                                  }
                                                })();
                                                {
                                                  const $t27759 = (() => {
                                                    {
                                                      const $t27758 = (cd2 <= 0.);
                                                      return ($t27758 && in_range);
                                                    }
                                                  })();
                                                  if ($t27759 === true) {
                                                    return (() => {
                                                      {
                                                        const shot = Perihelion$Combat$ship_fire_shot(sx, sy, game);
                                                        {
                                                          const sh2 = (() => {
                                                            {
                                                              const $t27760 = { $: "ShipOrbiting", _0: angle2 };
                                                              return ({ ...sh, x: sx, y: sy, mode: $t27760, idle_timer: idle2, fire_cooldown: 2.5 });
                                                            }
                                                          })();
                                                          {
                                                            const $t27762 = { $: "Cons", _0: sh2, _1: acc };
                                                            {
                                                              const $t27763 = { $: "Cons", _0: shot, _1: new_shots };
                                                              return Perihelion$Combat$step_ships_go(game, rest, $t27762, $t27763, dt_s);
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
                                                            const $t27764 = { $: "ShipOrbiting", _0: angle2 };
                                                            return ({ ...sh, x: sx, y: sy, mode: $t27764, idle_timer: idle2, fire_cooldown: cd2 });
                                                          }
                                                        })();
                                                        {
                                                          const $t27765 = { $: "Cons", _0: sh2, _1: acc };
                                                          return Perihelion$Combat$step_ships_go(game, rest, $t27765, new_shots, dt_s);
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
                const $f27802 = $t27698._0;
                const $f27803 = $t27698._1;
                {
                  const vy = (() => {
                    return $f27803;
                  })();
                  {
                    const vx = (() => {
                      return $f27802;
                    })();
                    {
                      const x2 = (() => {
                        {
                          const $t27767 = sh.x;
                          {
                            const $t27768 = (vx * dt_s);
                            return ($t27767 + $t27768);
                          }
                        }
                      })();
                      {
                        const y2 = (() => {
                          {
                            const $t27769 = sh.y;
                            {
                              const $t27770 = (vy * dt_s);
                              return ($t27769 + $t27770);
                            }
                          }
                        })();
                        {
                          const $t27772 = (() => {
                            {
                              const $t27771 = game.stars;
                              return Perihelion$Combat$arrived_star($t27771, x2, y2, 0);
                            }
                          })();
                          switch ($t27772.$) {
                            case "Some": {
                              const $f27800 = $t27772._0;
                              {
                                const pair = $f27800;
                                {
                                  const idx = pair._0;
                                  {
                                    const t = pair._1;
                                    {
                                      const angle = (() => {
                                        {
                                          const $t27774 = (() => {
                                            {
                                              const $t27773 = t.y;
                                              return (y2 - $t27773);
                                            }
                                          })();
                                          {
                                            const $t27776 = (() => {
                                              {
                                                const $t27775 = t.x;
                                                return (x2 - $t27775);
                                              }
                                            })();
                                            return Math.atan2($t27774, $t27776);
                                          }
                                        }
                                      })();
                                      {
                                        const $p27796 = (() => {
                                          {
                                            const $t27777 = game.rng;
                                            {
                                              const $p29016_i10423_i10722_i10935 = (() => {
                                                {
                                                  const $p15579_i10148_i10418_i10717_i10930 = (() => {
                                                    {
                                                      const $p15576_i1532_i10138_i10409_i10708_i10921 = Random$next_raw($t27777);
                                                      {
                                                        const hi_i1533_i10139_i10410_i10709_i10922 = $p15576_i1532_i10138_i10409_i10708_i10921._0;
                                                        {
                                                          const rng2_i1534_i10140_i10411_i10710_i10923 = $p15576_i1532_i10138_i10409_i10708_i10921._1;
                                                          {
                                                            const $p15575_i1535_i10141_i10412_i10711_i10924 = Random$next_raw(rng2_i1534_i10140_i10411_i10710_i10923);
                                                            {
                                                              const lo_i1536_i10142_i10413_i10712_i10925 = $p15575_i1535_i10141_i10412_i10711_i10924._0;
                                                              {
                                                                const rng3_i1537_i10143_i10414_i10713_i10926 = $p15575_i1535_i10141_i10412_i10711_i10924._1;
                                                                {
                                                                  const $t15574_i1541_i10147_i10417_i10716_i10929 = (() => {
                                                                    {
                                                                      const $t15573_i1540_i10146_i10416_i10715_i10928 = (() => {
                                                                        {
                                                                          const $t15571_i1538_i10144_i10415_i10714_i10927 = march_int_and(hi_i1533_i10139_i10410_i10709_i10922, 1048575);
                                                                          return ($t15571_i1538_i10144_i10415_i10714_i10927 * 4294967296);
                                                                        }
                                                                      })();
                                                                      return ($t15573_i1540_i10146_i10416_i10715_i10928 + lo_i1536_i10142_i10413_i10712_i10925);
                                                                    }
                                                                  })();
                                                                  return { _0: $t15574_i1541_i10147_i10417_i10716_i10929, _1: rng3_i1537_i10143_i10414_i10713_i10926 };
                                                                }
                                                              }
                                                            }
                                                          }
                                                        }
                                                      }
                                                    }
                                                  })();
                                                  {
                                                    const bits_i10149_i10419_i10718_i10931 = $p15579_i10148_i10418_i10717_i10930._0;
                                                    {
                                                      const rng2_i10150_i10420_i10719_i10932 = $p15579_i10148_i10418_i10717_i10930._1;
                                                      {
                                                        const $t15578_i10152_i10422_i10721_i10934 = (() => {
                                                          {
                                                            const $t15577_i10151_i10421_i10720_i10933 = bits_i10149_i10419_i10718_i10931;
                                                            return ($t15577_i10151_i10421_i10720_i10933 / 4.50359962737e+15);
                                                          }
                                                        })();
                                                        return { _0: $t15578_i10152_i10422_i10721_i10934, _1: rng2_i10150_i10420_i10719_i10932 };
                                                      }
                                                    }
                                                  }
                                                }
                                              })();
                                              {
                                                const t_i10424_i10723_i10936 = $p29016_i10423_i10722_i10935._0;
                                                {
                                                  const rng2_i10425_i10724_i10937 = $p29016_i10423_i10722_i10935._1;
                                                  {
                                                    const out_i10426_i10725_i10938 = { _0: rng2_i10425_i10724_i10937, _1: t_i10424_i10723_i10936 };
                                                    return out_i10426_i10725_i10938;
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        {
                                          const rng2 = $p27796._0;
                                          {
                                            const idle_f = $p27796._1;
                                            {
                                              const idle = (() => {
                                                {
                                                  const $t27782 = (() => {
                                                    {
                                                      const $t27781 = (6. - 3.);
                                                      return (idle_f * $t27781);
                                                    }
                                                  })();
                                                  return (3. + $t27782);
                                                }
                                              })();
                                              {
                                                const r = (() => {
                                                  {
                                                    const $t27783 = t.capture_radius;
                                                    return ($t27783 * 1.6);
                                                  }
                                                })();
                                                {
                                                  const sh2 = (() => {
                                                    {
                                                      const $t27788 = (() => {
                                                        {
                                                          const $t27785 = t.x;
                                                          {
                                                            const $t27787 = (() => {
                                                              {
                                                                const $t27786 = Math.cos(angle);
                                                                return ($t27786 * r);
                                                              }
                                                            })();
                                                            return ($t27785 + $t27787);
                                                          }
                                                        }
                                                      })();
                                                      {
                                                        const $t27792 = (() => {
                                                          {
                                                            const $t27789 = t.y;
                                                            {
                                                              const $t27791 = (() => {
                                                                {
                                                                  const $t27790 = Math.sin(angle);
                                                                  return ($t27790 * r);
                                                                }
                                                              })();
                                                              return ($t27789 + $t27791);
                                                            }
                                                          }
                                                        })();
                                                        {
                                                          const $t27793 = { $: "ShipOrbiting", _0: angle };
                                                          return ({ ...sh, x: $t27788, y: $t27792, star_idx: idx, mode: $t27793, idle_timer: idle });
                                                        }
                                                      }
                                                    }
                                                  })();
                                                  {
                                                    const $t27794 = ({ ...game, rng: rng2 });
                                                    {
                                                      const $t27795 = { $: "Cons", _0: sh2, _1: acc };
                                                      return Perihelion$Combat$step_ships_go($t27794, rest, $t27795, new_shots, dt_s);
                                                    }
                                                  }
                                                }
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
                                const $t27798 = Perihelion$Combat$in_band(game, x2, y2);
                                if ($t27798 === true) {
                                  return (() => {
                                    {
                                      const sh2 = ({ ...sh, x: x2, y: y2 });
                                      {
                                        const $t27799 = { $: "Cons", _0: sh2, _1: acc };
                                        return Perihelion$Combat$step_ships_go(game, rest, $t27799, new_shots, dt_s);
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
    const $t27814 = game.mode;
    switch ($t27814.$) {
      case "Orbiting": {
        const $f27835 = $t27814._0;
        const $f27836 = $t27814._1;
        const $f27837 = $t27814._2;
        {
          const idx = (() => {
            return $f27835;
          })();
          {
            const $t27815 = Perihelion$Core$star_at(game, idx);
            switch ($t27815.$) {
              case "None": {
                return { $: "None" };
                break;
              }
              case "Some": {
                const $f27827 = $t27815._0;
                {
                  const s = $f27827;
                  {
                    const rdx = (() => {
                      {
                        const $t27816 = game.ball_x;
                        {
                          const $t27817 = s.x;
                          return ($t27816 - $t27817);
                        }
                      }
                    })();
                    {
                      const rdy = (() => {
                        {
                          const $t27818 = game.ball_y;
                          {
                            const $t27819 = s.y;
                            return ($t27818 - $t27819);
                          }
                        }
                      })();
                      {
                        const rdist = (() => {
                          {
                            const $t27822 = (() => {
                              {
                                const $t27820 = (rdx * rdx);
                                {
                                  const $t27821 = (rdy * rdy);
                                  return ($t27820 + $t27821);
                                }
                              }
                            })();
                            return Math.sqrt($t27822);
                          }
                        })();
                        {
                          const $t27823 = (rdist > 0.);
                          if ($t27823 === true) {
                            return (() => {
                              {
                                const $t27826 = (() => {
                                  {
                                    const $t27824 = (rdx / rdist);
                                    {
                                      const $t27825 = (rdy / rdist);
                                      return { _0: $t27824, _1: $t27825 };
                                    }
                                  }
                                })();
                                return { $: "Some", _0: $t27826 };
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
        const $f27846 = $t27814._0;
        const $f27847 = $t27814._1;
        {
          const vy = (() => {
            return $f27847;
          })();
          {
            const vx = (() => {
              return $f27846;
            })();
            {
              const speed = (() => {
                {
                  const $t27830 = (() => {
                    {
                      const $t27828 = (vx * vx);
                      {
                        const $t27829 = (vy * vy);
                        return ($t27828 + $t27829);
                      }
                    }
                  })();
                  return Math.sqrt($t27830);
                }
              })();
              {
                const $t27831 = (speed > 0.);
                if ($t27831 === true) {
                  return (() => {
                    {
                      const $t27834 = (() => {
                        {
                          const $t27832 = (vx / speed);
                          {
                            const $t27833 = (vy / speed);
                            return { _0: $t27832, _1: $t27833 };
                          }
                        }
                      })();
                      return { $: "Some", _0: $t27834 };
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
    const $t27852 = game.mode;
    switch ($t27852.$) {
      case "Orbiting": {
        const $f27860 = $t27852._0;
        const $f27861 = $t27852._1;
        const $f27862 = $t27852._2;
        return game;
        break;
      }
      case "Flying": {
        const $f27871 = $t27852._0;
        const $f27872 = $t27852._1;
        {
          const vy = (() => {
            return $f27872;
          })();
          {
            const vx = (() => {
              return $f27871;
            })();
            {
              const $t27859 = (() => {
                {
                  const $t27855 = (() => {
                    {
                      const $t27854 = (ax * 14.);
                      return (vx - $t27854);
                    }
                  })();
                  {
                    const $t27858 = (() => {
                      {
                        const $t27857 = (ay * 14.);
                        return (vy - $t27857);
                      }
                    })();
                    return { $: "Flying", _0: $t27855, _1: $t27858 };
                  }
                }
              })();
              return ({ ...game, mode: $t27859 });
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

function Perihelion$Combat$spread_shots(x, y, ax, ay) {
  {
    const $p27918 = (() => {
      {
        const $t27898 = (0. - 0.5236);
        {
          const $t27891_i9925 = (() => {
            {
              const $t27888_i9922 = (() => {
                {
                  const $t27887_i9921 = Math.cos($t27898);
                  return (ax * $t27887_i9921);
                }
              })();
              {
                const $t27890_i9924 = (() => {
                  {
                    const $t27889_i9923 = Math.sin($t27898);
                    return (ay * $t27889_i9923);
                  }
                })();
                return ($t27888_i9922 - $t27890_i9924);
              }
            }
          })();
          {
            const $t27896_i9930 = (() => {
              {
                const $t27893_i9927 = (() => {
                  {
                    const $t27892_i9926 = Math.sin($t27898);
                    return (ax * $t27892_i9926);
                  }
                })();
                {
                  const $t27895_i9929 = (() => {
                    {
                      const $t27894_i9928 = Math.cos($t27898);
                      return (ay * $t27894_i9928);
                    }
                  })();
                  return ($t27893_i9927 + $t27895_i9929);
                }
              }
            })();
            return { _0: $t27891_i9925, _1: $t27896_i9930 };
          }
        }
      }
    })();
    {
      const a1x = $p27918._0;
      {
        const a1y = $p27918._1;
        {
          const $p27917 = (() => {
            {
              const $t27901 = (() => {
                {
                  const $t27900 = (0.5236 / 2.);
                  return (0. - $t27900);
                }
              })();
              {
                const $t27891_i9912 = (() => {
                  {
                    const $t27888_i9909 = (() => {
                      {
                        const $t27887_i9908 = Math.cos($t27901);
                        return (ax * $t27887_i9908);
                      }
                    })();
                    {
                      const $t27890_i9911 = (() => {
                        {
                          const $t27889_i9910 = Math.sin($t27901);
                          return (ay * $t27889_i9910);
                        }
                      })();
                      return ($t27888_i9909 - $t27890_i9911);
                    }
                  }
                })();
                {
                  const $t27896_i9917 = (() => {
                    {
                      const $t27893_i9914 = (() => {
                        {
                          const $t27892_i9913 = Math.sin($t27901);
                          return (ax * $t27892_i9913);
                        }
                      })();
                      {
                        const $t27895_i9916 = (() => {
                          {
                            const $t27894_i9915 = Math.cos($t27901);
                            return (ay * $t27894_i9915);
                          }
                        })();
                        return ($t27893_i9914 + $t27895_i9916);
                      }
                    }
                  })();
                  return { _0: $t27891_i9912, _1: $t27896_i9917 };
                }
              }
            }
          })();
          {
            const a2x = $p27917._0;
            {
              const a2y = $p27917._1;
              {
                const $p27916 = (() => {
                  {
                    const $t27903 = (0.5236 / 2.);
                    {
                      const $t27891_i9899 = (() => {
                        {
                          const $t27888_i9896 = (() => {
                            {
                              const $t27887_i9895 = Math.cos($t27903);
                              return (ax * $t27887_i9895);
                            }
                          })();
                          {
                            const $t27890_i9898 = (() => {
                              {
                                const $t27889_i9897 = Math.sin($t27903);
                                return (ay * $t27889_i9897);
                              }
                            })();
                            return ($t27888_i9896 - $t27890_i9898);
                          }
                        }
                      })();
                      {
                        const $t27896_i9904 = (() => {
                          {
                            const $t27893_i9901 = (() => {
                              {
                                const $t27892_i9900 = Math.sin($t27903);
                                return (ax * $t27892_i9900);
                              }
                            })();
                            {
                              const $t27895_i9903 = (() => {
                                {
                                  const $t27894_i9902 = Math.cos($t27903);
                                  return (ay * $t27894_i9902);
                                }
                              })();
                              return ($t27893_i9901 + $t27895_i9903);
                            }
                          }
                        })();
                        return { _0: $t27891_i9899, _1: $t27896_i9904 };
                      }
                    }
                  }
                })();
                {
                  const a3x = $p27916._0;
                  {
                    const a3y = $p27916._1;
                    {
                      const $p27915 = (() => {
                        {
                          const $t27891_i9886 = (() => {
                            {
                              const $t27888_i9883 = (() => {
                                {
                                  const $t27887_i9882 = Math.cos(0.5236);
                                  return (ax * $t27887_i9882);
                                }
                              })();
                              {
                                const $t27890_i9885 = (() => {
                                  {
                                    const $t27889_i9884 = Math.sin(0.5236);
                                    return (ay * $t27889_i9884);
                                  }
                                })();
                                return ($t27888_i9883 - $t27890_i9885);
                              }
                            }
                          })();
                          {
                            const $t27896_i9891 = (() => {
                              {
                                const $t27893_i9888 = (() => {
                                  {
                                    const $t27892_i9887 = Math.sin(0.5236);
                                    return (ax * $t27892_i9887);
                                  }
                                })();
                                {
                                  const $t27895_i9890 = (() => {
                                    {
                                      const $t27894_i9889 = Math.cos(0.5236);
                                      return (ay * $t27894_i9889);
                                    }
                                  })();
                                  return ($t27893_i9888 + $t27895_i9890);
                                }
                              }
                            })();
                            return { _0: $t27891_i9886, _1: $t27896_i9891 };
                          }
                        }
                      })();
                      {
                        const a4x = $p27915._0;
                        {
                          const a4y = $p27915._1;
                          {
                            const $t27905 = (() => {
                              {
                                const $t27878_i9877 = (ax * 420.);
                                {
                                  const $t27880_i9878 = (ay * 420.);
                                  return ({ x: x, y: y, vx: $t27878_i9877, vy: $t27880_i9878, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                }
                              }
                            })();
                            {
                              const $t27906 = (() => {
                                {
                                  const $t27878_i9871 = (a1x * 420.);
                                  {
                                    const $t27880_i9872 = (a1y * 420.);
                                    return ({ x: x, y: y, vx: $t27878_i9871, vy: $t27880_i9872, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                  }
                                }
                              })();
                              {
                                const $t27907 = (() => {
                                  {
                                    const $t27878_i9865 = (a2x * 420.);
                                    {
                                      const $t27880_i9866 = (a2y * 420.);
                                      return ({ x: x, y: y, vx: $t27878_i9865, vy: $t27880_i9866, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                    }
                                  }
                                })();
                                {
                                  const $t27908 = (() => {
                                    {
                                      const $t27878_i9859 = (a3x * 420.);
                                      {
                                        const $t27880_i9860 = (a3y * 420.);
                                        return ({ x: x, y: y, vx: $t27878_i9859, vy: $t27880_i9860, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                      }
                                    }
                                  })();
                                  {
                                    const $t27909 = (() => {
                                      {
                                        const $t27878_i9853 = (a4x * 420.);
                                        {
                                          const $t27880_i9854 = (a4y * 420.);
                                          return ({ x: x, y: y, vx: $t27878_i9853, vy: $t27880_i9854, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                        }
                                      }
                                    })();
                                    {
                                      const $t27910 = { $: "Nil" };
                                      {
                                        const $t27911 = { $: "Cons", _0: $t27909, _1: $t27910 };
                                        {
                                          const $t27912 = { $: "Cons", _0: $t27908, _1: $t27911 };
                                          {
                                            const $t27913 = { $: "Cons", _0: $t27907, _1: $t27912 };
                                            {
                                              const $t27914 = { $: "Cons", _0: $t27906, _1: $t27913 };
                                              return { $: "Cons", _0: $t27905, _1: $t27914 };
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
const Perihelion$Combat$spread_shots$clo = { _0: ($_, x, y, ax, ay) => Perihelion$Combat$spread_shots(x, y, ax, ay) };

function Perihelion$Combat$starkiller_on_cooldown(game) {
  {
    const $t27919 = Perihelion$Core$active_weapon(game);
    switch ($t27919.$) {
      case "StarKiller": {
        {
          const $t27920 = game.starkiller_cooldown;
          return ($t27920 > 0.);
        }
        break;
      }
      default: {
        return false;
      }
    }
  }
}
const Perihelion$Combat$starkiller_on_cooldown$clo = { _0: ($_, game) => Perihelion$Combat$starkiller_on_cooldown(game) };

function Perihelion$Combat$fire(game, keys, cursor, _dt_s) {
  {
    const pressed = (() => {
      {
        const $t27922 = { $: "$Clo_$lam27921$3693", _0: $lam27921$apply$3693 };
        return List$any$List_String$Fn_String_Bool(keys, $t27922);
      }
    })();
    {
      const $t27928 = (() => {
        {
          const $t27926 = (() => {
            {
              const $t27923 = (!pressed);
              {
                const $t27925 = (() => {
                  {
                    const $t27924 = game.fire_cooldown;
                    return ($t27924 > 0.);
                  }
                })();
                return ($t27923 || $t27925);
              }
            }
          })();
          {
            const $t27927 = Perihelion$Combat$starkiller_on_cooldown(game);
            return ($t27926 || $t27927);
          }
        }
      })();
      if ($t27928 === true) {
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
                    const $t27929 = cy;
                    {
                      const $t27930 = game.camera_y;
                      return ($t27929 + $t27930);
                    }
                  }
                })();
                {
                  const dx = (() => {
                    {
                      const $t27931 = cx;
                      {
                        const $t27932 = game.ball_x;
                        return ($t27931 - $t27932);
                      }
                    }
                  })();
                  {
                    const dy = (() => {
                      {
                        const $t27933 = game.ball_y;
                        return (cursor_world_y - $t27933);
                      }
                    })();
                    {
                      const dist = (() => {
                        {
                          const $t27936 = (() => {
                            {
                              const $t27934 = (dx * dx);
                              {
                                const $t27935 = (dy * dy);
                                return ($t27934 + $t27935);
                              }
                            }
                          })();
                          return Math.sqrt($t27936);
                        }
                      })();
                      {
                        const aim = (() => {
                          {
                            const $t27937 = (dist > 0.);
                            if ($t27937 === true) {
                              return (() => {
                                {
                                  const $t27940 = (() => {
                                    {
                                      const $t27938 = (dx / dist);
                                      {
                                        const $t27939 = (dy / dist);
                                        return { _0: $t27938, _1: $t27939 };
                                      }
                                    }
                                  })();
                                  return { $: "Some", _0: $t27940 };
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
                            const $f27987 = aim._0;
                            {
                              const pair = $f27987;
                              {
                                const ax = pair._0;
                                {
                                  const ay = pair._1;
                                  {
                                    const g2 = Perihelion$Combat$apply_recoil(game, ax, ay);
                                    {
                                      const $t27941 = Perihelion$Core$active_weapon(game);
                                      {
                                        let new_shots;
                                        switch ($t27941.$) {
                                          case "Base": {
                                            new_shots = (() => {
                                              {
                                                const $t27944 = (() => {
                                                  {
                                                    const $t27942 = game.ball_x;
                                                    {
                                                      const $t27943 = game.ball_y;
                                                      {
                                                        const $t27878_i9947 = (ax * 420.);
                                                        {
                                                          const $t27880_i9948 = (ay * 420.);
                                                          return ({ x: $t27942, y: $t27943, vx: $t27878_i9947, vy: $t27880_i9948, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                                        }
                                                      }
                                                    }
                                                  }
                                                })();
                                                {
                                                  const $t27945 = { $: "Nil" };
                                                  return { $: "Cons", _0: $t27944, _1: $t27945 };
                                                }
                                              }
                                            })();
                                            break;
                                          }
                                          case "Homing": {
                                            new_shots = (() => {
                                              {
                                                const $t27948 = (() => {
                                                  {
                                                    const $t27946 = game.ball_x;
                                                    {
                                                      const $t27947 = game.ball_y;
                                                      {
                                                        const $t27883_i9953 = (ax * 420.);
                                                        {
                                                          const $t27885_i9954 = (ay * 420.);
                                                          return ({ x: $t27946, y: $t27947, vx: $t27883_i9953, vy: $t27885_i9954, ttl: 3., homing: true, star_killer: false, target_x: 0., target_y: 0. });
                                                        }
                                                      }
                                                    }
                                                  }
                                                })();
                                                {
                                                  const $t27949 = { $: "Nil" };
                                                  return { $: "Cons", _0: $t27948, _1: $t27949 };
                                                }
                                              }
                                            })();
                                            break;
                                          }
                                          case "Spread": {
                                            new_shots = (() => {
                                              {
                                                const $t27950 = game.ball_x;
                                                {
                                                  const $t27951 = game.ball_y;
                                                  return Perihelion$Combat$spread_shots($t27950, $t27951, ax, ay);
                                                }
                                              }
                                            })();
                                            break;
                                          }
                                          case "StarKiller": {
                                            new_shots = (() => {
                                              {
                                                const $t27953 = (() => {
                                                  {
                                                    const $t27952 = Perihelion$Combat$starkiller_target_idx(game);
                                                    return Perihelion$Core$star_at(game, $t27952);
                                                  }
                                                })();
                                                switch ($t27953.$) {
                                                  case "None": {
                                                    return { $: "Nil" };
                                                    break;
                                                  }
                                                  case "Some": {
                                                    const $f27976 = $t27953._0;
                                                    {
                                                      const target = $f27976;
                                                      {
                                                        const tdx = (() => {
                                                          {
                                                            const $t27954 = target.x;
                                                            {
                                                              const $t27955 = game.ball_x;
                                                              return ($t27954 - $t27955);
                                                            }
                                                          }
                                                        })();
                                                        {
                                                          const tdy = (() => {
                                                            {
                                                              const $t27956 = target.y;
                                                              {
                                                                const $t27957 = game.ball_y;
                                                                return ($t27956 - $t27957);
                                                              }
                                                            }
                                                          })();
                                                          {
                                                            const tdist = (() => {
                                                              {
                                                                const $t27960 = (() => {
                                                                  {
                                                                    const $t27958 = (tdx * tdx);
                                                                    {
                                                                      const $t27959 = (tdy * tdy);
                                                                      return ($t27958 + $t27959);
                                                                    }
                                                                  }
                                                                })();
                                                                return Math.sqrt($t27960);
                                                              }
                                                            })();
                                                            {
                                                              const $t27961 = (tdist <= 0.);
                                                              if ($t27961 === true) {
                                                                return { $: "Nil" };
                                                              } else {
                                                                return (() => {
                                                                  {
                                                                    const $t27974 = (() => {
                                                                      {
                                                                        const $t27962 = game.ball_x;
                                                                        {
                                                                          const $t27963 = game.ball_y;
                                                                          {
                                                                            const $t27966 = (() => {
                                                                              {
                                                                                const $t27964 = (tdx / tdist);
                                                                                return ($t27964 * 420.);
                                                                              }
                                                                            })();
                                                                            {
                                                                              const $t27969 = (() => {
                                                                                {
                                                                                  const $t27967 = (tdy / tdist);
                                                                                  return ($t27967 * 420.);
                                                                                }
                                                                              })();
                                                                              {
                                                                                const $t27971 = (3. * 3.);
                                                                                {
                                                                                  const $t27972 = target.x;
                                                                                  {
                                                                                    const $t27973 = target.y;
                                                                                    return ({ x: $t27962, y: $t27963, vx: $t27966, vy: $t27969, ttl: $t27971, homing: false, star_killer: true, target_x: $t27972, target_y: $t27973 });
                                                                                  }
                                                                                }
                                                                              }
                                                                            }
                                                                          }
                                                                        }
                                                                      }
                                                                    })();
                                                                    {
                                                                      const $t27975 = { $: "Nil" };
                                                                      return { $: "Cons", _0: $t27974, _1: $t27975 };
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
                                            })();
                                            break;
                                          }
                                          default: {
                                            new_shots = (() => {
                                              return (() => { throw new Error("non-exhaustive pattern match"); })();
                                            })();
                                            break;
                                          }
                                        }
                                        {
                                          const cooldown2 = (() => {
                                            {
                                              const $t27977 = Perihelion$Core$active_weapon(game);
                                              switch ($t27977.$) {
                                                case "StarKiller": {
                                                  return game.fire_cooldown;
                                                  break;
                                                }
                                                default: {
                                                  {
                                                    const reduced_i9941 = (() => {
                                                      {
                                                        const $t27346_i9940 = (() => {
                                                          {
                                                            const $t27344_i9939 = (() => {
                                                              {
                                                                const $t27343_i9938 = game.fire_rate_stacks;
                                                                return $t27343_i9938;
                                                              }
                                                            })();
                                                            return ($t27344_i9939 * 0.05);
                                                          }
                                                        })();
                                                        return (0.4 - $t27346_i9940);
                                                      }
                                                    })();
                                                    {
                                                      const $t27348_i9942 = (reduced_i9941 < 0.15);
                                                      if ($t27348_i9942 === true) {
                                                        return 0.15;
                                                      } else {
                                                        return reduced_i9941;
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          })();
                                          {
                                            const starkiller_cd2 = (() => {
                                              {
                                                const $t27980 = Perihelion$Core$active_weapon(game);
                                                switch ($t27980.$) {
                                                  case "StarKiller": {
                                                    {
                                                      let $t27981;
                                                      switch (new_shots.$) {
                                                        case "Nil": {
                                                          $t27981 = true;
                                                          break;
                                                        }
                                                        default: {
                                                          $t27981 = false;
                                                          break;
                                                        }
                                                      }
                                                      if ($t27981 === true) {
                                                        return game.starkiller_cooldown;
                                                      } else {
                                                        return 12.;
                                                      }
                                                    }
                                                    break;
                                                  }
                                                  default: {
                                                    return game.starkiller_cooldown;
                                                  }
                                                }
                                              }
                                            })();
                                            {
                                              const $t27984 = g2.player_shots;
                                              {
                                                const $t27985 = (() => {
                                                  {
                                                    const go_i9933 = { $: "$Clo_go$4759", _0: go$apply$4759 };
                                                    {
                                                      const $t261_i9936 = (() => {
                                                        {
                                                          const go_i4478_i9934 = { $: "$Clo_go$5242", _0: go$apply$5242 };
                                                          {
                                                            const $t253_i4479_i9935 = { $: "Nil" };
                                                            return go$apply$5242(go_i4478_i9934, $t27984, $t253_i4479_i9935);
                                                          }
                                                        }
                                                      })();
                                                      return go$apply$4759(go_i9933, $t261_i9936, new_shots);
                                                    }
                                                  }
                                                })();
                                                return ({ ...g2, player_shots: $t27985, fire_cooldown: cooldown2, starkiller_cooldown: starkiller_cd2 });
                                              }
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
            }
          }
        })();
      }
    }
  }
}
const Perihelion$Combat$fire$clo = { _0: ($_, game, keys, cursor, _dt_s) => Perihelion$Combat$fire(game, keys, cursor, _dt_s) };

function Perihelion$Combat$find_star_by_pos(stars, tx, ty, i) {
  switch (stars.$) {
    case "Nil": {
      return { $: "None" };
      break;
    }
    case "Cons": {
      const $f28003 = stars._0;
      const $f28004 = stars._1;
      {
        const rest = (() => {
          return $f28004;
        })();
        {
          const s = (() => {
            return $f28003;
          })();
          {
            const $t28001 = (() => {
              {
                const $t27999 = s.x;
                {
                  const $t28000 = s.y;
                  {
                    const $t27359_i9965 = (() => {
                      {
                        const dx_i3632_i9961 = (tx - $t27999);
                        {
                          const dy_i3633_i9962 = (ty - $t28000);
                          {
                            const $t27357_i3634_i9963 = (dx_i3632_i9961 * dx_i3632_i9961);
                            {
                              const $t27358_i3635_i9964 = (dy_i3633_i9962 * dy_i3633_i9962);
                              return ($t27357_i3634_i9963 + $t27358_i3635_i9964);
                            }
                          }
                        }
                      }
                    })();
                    {
                      const $t27362_i9968 = (() => {
                        {
                          const $t27360_i9966 = (0.001 + 0.);
                          {
                            const $t27361_i9967 = (0.001 + 0.);
                            return ($t27360_i9966 * $t27361_i9967);
                          }
                        }
                      })();
                      return ($t27359_i9965 <= $t27362_i9968);
                    }
                  }
                }
              }
            })();
            if ($t28001 === true) {
              return { $: "Some", _0: i };
            } else {
              return (() => {
                {
                  const $t28002 = (i + 1);
                  return Perihelion$Combat$find_star_by_pos(rest, tx, ty, $t28002);
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
const Perihelion$Combat$find_star_by_pos$clo = { _0: ($_, stars, tx, ty, i) => Perihelion$Combat$find_star_by_pos(stars, tx, ty, i) };

function Perihelion$Combat$collide_shots_stars(game) {
  {
    const $t28009 = game.player_shots;
    {
      const $t28011 = { $: "$Clo_$lam28010$3699", _0: $lam28010$apply$3699 };
      {
        const sk_shots = (() => {
          {
            const pred_i3755 = $t28011;
            {
              const go_i3756 = { $: "$Clo_go$4753", _0: go$apply$4753, _1: pred_i3755 };
              {
                const $t302_i3757 = { $: "Nil" };
                return go$apply$4753(go_i3756, $t28009, $t302_i3757);
              }
            }
          }
        })();
        switch (sk_shots.$) {
          case "Nil": {
            return game;
            break;
          }
          case "Cons": {
            const $f28035 = sk_shots._0;
            const $f28036 = sk_shots._1;
            {
              const s = $f28035;
              {
                const $t28017 = (() => {
                  {
                    const $t28012 = s.x;
                    {
                      const $t28013 = s.y;
                      {
                        const $t28015 = s.target_x;
                        {
                          const $t28016 = s.target_y;
                          {
                            const $t27359_i9990 = (() => {
                              {
                                const dx_i3632_i9986 = ($t28015 - $t28012);
                                {
                                  const dy_i3633_i9987 = ($t28016 - $t28013);
                                  {
                                    const $t27357_i3634_i9988 = (dx_i3632_i9986 * dx_i3632_i9986);
                                    {
                                      const $t27358_i3635_i9989 = (dy_i3633_i9987 * dy_i3633_i9987);
                                      return ($t27357_i3634_i9988 + $t27358_i3635_i9989);
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const $t27362_i9993 = (() => {
                                {
                                  const $t27360_i9991 = (20. + 0.);
                                  {
                                    const $t27361_i9992 = (20. + 0.);
                                    return ($t27360_i9991 * $t27361_i9992);
                                  }
                                }
                              })();
                              return ($t27359_i9990 <= $t27362_i9993);
                            }
                          }
                        }
                      }
                    }
                  }
                })();
                if ($t28017 === true) {
                  return (() => {
                    {
                      const $t28021 = (() => {
                        {
                          const $t28018 = game.stars;
                          {
                            const $t28019 = s.target_x;
                            {
                              const $t28020 = s.target_y;
                              return Perihelion$Combat$find_star_by_pos($t28018, $t28019, $t28020, 0);
                            }
                          }
                        }
                      })();
                      switch ($t28021.$) {
                        case "None": {
                          {
                            const $t28022 = game.player_shots;
                            {
                              const $t28025 = { $: "$Clo_$lam28023$3701", _0: $lam28023$apply$3701 };
                              {
                                const $t28026 = (() => {
                                  {
                                    const pred_i3747 = $t28025;
                                    {
                                      const go_i3748 = { $: "$Clo_go$4753", _0: go$apply$4753, _1: pred_i3747 };
                                      {
                                        const $t302_i3749 = { $: "Nil" };
                                        return go$apply$4753(go_i3748, $t28022, $t302_i3749);
                                      }
                                    }
                                  }
                                })();
                                return ({ ...game, player_shots: $t28026 });
                              }
                            }
                          }
                          break;
                        }
                        case "Some": {
                          const $f28034 = $t28021._0;
                          {
                            const tidx = $f28034;
                            {
                              const g2 = Perihelion$Core$remove_star(game, tidx);
                              {
                                const $t28027 = g2.ships;
                                {
                                  const $t28028 = (() => {
                                    {
                                      const $t27991_i9971 = { $: "$Clo_$lam27989$3696", _0: $lam27989$apply$3696, _1: tidx };
                                      {
                                        const $t27992_i9975 = (() => {
                                          {
                                            const pred_i3740_i9972 = $t27991_i9971;
                                            {
                                              const go_i3741_i9973 = { $: "$Clo_go$4765", _0: go$apply$4765, _1: pred_i3740_i9972 };
                                              {
                                                const $t302_i3742_i9974 = { $: "Nil" };
                                                return go$apply$4765(go_i3741_i9973, $t28027, $t302_i3742_i9974);
                                              }
                                            }
                                          }
                                        })();
                                        {
                                          const $t27998_i9976 = { $: "$Clo_$lam27993$3697", _0: $lam27993$apply$3697, _1: tidx };
                                          {
                                            const f_i3736_i9977 = $t27998_i9976;
                                            {
                                              const go_i3737_i9978 = { $: "$Clo_go$4763", _0: go$apply$4763, _1: f_i3736_i9977 };
                                              {
                                                const $t270_i3738_i9979 = { $: "Nil" };
                                                return go$apply$4763(go_i3737_i9978, $t27992_i9975, $t270_i3738_i9979);
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t28029 = game.player_shots;
                                    {
                                      const $t28032 = { $: "$Clo_$lam28030$3702", _0: $lam28030$apply$3702 };
                                      {
                                        const $t28033 = (() => {
                                          {
                                            const pred_i3751 = $t28032;
                                            {
                                              const go_i3752 = { $: "$Clo_go$4753", _0: go$apply$4753, _1: pred_i3751 };
                                              {
                                                const $t302_i3753 = { $: "Nil" };
                                                return go$apply$4753(go_i3752, $t28029, $t302_i3753);
                                              }
                                            }
                                          }
                                        })();
                                        return ({ ...g2, ships: $t28028, player_shots: $t28033 });
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
                } else {
                  return game;
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
const Perihelion$Combat$collide_shots_stars$clo = { _0: ($_, game) => Perihelion$Combat$collide_shots_stars(game) };

function Perihelion$Combat$collide_shots_asteroids(game) {
  {
    const $p28073 = (() => {
      {
        const $t28048 = game.asteroids;
        {
          const $t28056 = { $: "$Clo_$lam28049$3704", _0: $lam28049$apply$3704, _1: game };
          {
            const pred_i3769 = $t28056;
            {
              const go_i3770 = { $: "$Clo_go$4772", _0: go$apply$4772, _1: pred_i3769 };
              {
                const $t557_i3771 = { $: "Nil" };
                {
                  const $t558_i3772 = { $: "Nil" };
                  return go$apply$4772(go_i3770, $t28048, $t557_i3771, $t558_i3772);
                }
              }
            }
          }
        }
      }
    })();
    {
      const dead = $p28073._0;
      {
        const alive = $p28073._1;
        {
          const $t28057 = game.player_shots;
          {
            const $t28066 = { $: "$Clo_$lam28058$3706", _0: $lam28058$apply$3706, _1: game };
            {
              const shots = (() => {
                {
                  const pred_i3765 = $t28066;
                  {
                    const go_i3766 = { $: "$Clo_go$4753", _0: go$apply$4753, _1: pred_i3765 };
                    {
                      const $t302_i3767 = { $: "Nil" };
                      return go$apply$4753(go_i3766, $t28057, $t302_i3767);
                    }
                  }
                }
              })();
              {
                const $t28071 = (() => {
                  {
                    const $t28067 = game.score;
                    {
                      const $t28070 = (() => {
                        {
                          const $t28068 = (() => {
                            {
                              const go_i3763 = { $: "$Clo_go$4769", _0: go$apply$4769 };
                              return go$apply$4769(go_i3763, dead, 0);
                            }
                          })();
                          {
                            const $t28069 = game.multiplier;
                            return ($t28068 * $t28069);
                          }
                        }
                      })();
                      return ($t28067 + $t28070);
                    }
                  }
                })();
                {
                  const $t28072 = (() => {
                    {
                      const $t28047_i10009 = { $: "$Clo_$lam28044$3703", _0: $lam28044$apply$3703 };
                      {
                        const f_i3759_i10010 = $t28047_i10009;
                        {
                          const go_i3760_i10011 = { $: "$Clo_go$4767", _0: go$apply$4767, _1: f_i3759_i10010 };
                          {
                            const $t270_i3761_i10012 = { $: "Nil" };
                            return go$apply$4767(go_i3760_i10011, dead, $t270_i3761_i10012);
                          }
                        }
                      }
                    }
                  })();
                  return ({ ...game, asteroids: alive, player_shots: shots, score: $t28071, fx_bursts: $t28072 });
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
        const pos_i3776 = (() => {
          {
            const $t27355_i3774 = sh.x;
            {
              const $t27356_i3775 = sh.y;
              return { _0: $t27355_i3774, _1: $t27356_i3775 };
            }
          }
        })();
        return pos_i3776;
      }
    })();
    {
      const sx = pos._0;
      {
        const sy = pos._1;
        {
          const $t28041_i10384 = s.x;
          {
            const $t28042_i10385 = s.y;
            {
              const $t27359_i10004_i10390 = (() => {
                {
                  const dx_i3632_i10000_i10386 = (sx - $t28041_i10384);
                  {
                    const dy_i3633_i10001_i10387 = (sy - $t28042_i10385);
                    {
                      const $t27357_i3634_i10002_i10388 = (dx_i3632_i10000_i10386 * dx_i3632_i10000_i10386);
                      {
                        const $t27358_i3635_i10003_i10389 = (dy_i3633_i10001_i10387 * dy_i3633_i10001_i10387);
                        return ($t27357_i3634_i10002_i10388 + $t27358_i3635_i10003_i10389);
                      }
                    }
                  }
                }
              })();
              {
                const $t27362_i10007_i10393 = (() => {
                  {
                    const $t27360_i10005_i10391 = (3. + 10.);
                    {
                      const $t27361_i10006_i10392 = (3. + 10.);
                      return ($t27360_i10005_i10391 * $t27361_i10006_i10392);
                    }
                  }
                })();
                return ($t27359_i10004_i10390 <= $t27362_i10007_i10393);
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
    const $p28095 = (() => {
      {
        const $t28076 = game.ships;
        {
          const $t28081 = { $: "$Clo_$lam28077$3708", _0: $lam28077$apply$3708, _1: game };
          {
            const pred_i3784 = $t28081;
            {
              const go_i3785 = { $: "$Clo_go$4778", _0: go$apply$4778, _1: pred_i3784 };
              {
                const $t557_i3786 = { $: "Nil" };
                {
                  const $t558_i3787 = { $: "Nil" };
                  return go$apply$4778(go_i3785, $t28076, $t557_i3786, $t558_i3787);
                }
              }
            }
          }
        }
      }
    })();
    {
      const dead = $p28095._0;
      {
        const alive = $p28095._1;
        {
          const $t28082 = game.player_shots;
          {
            const $t28088 = { $: "$Clo_$lam28083$3710", _0: $lam28083$apply$3710, _1: game };
            {
              const shots = (() => {
                {
                  const pred_i3780 = $t28088;
                  {
                    const go_i3781 = { $: "$Clo_go$4753", _0: go$apply$4753, _1: pred_i3780 };
                    {
                      const $t302_i3782 = { $: "Nil" };
                      return go$apply$4753(go_i3781, $t28082, $t302_i3782);
                    }
                  }
                }
              })();
              {
                const g2 = (() => {
                  {
                    const $t28094 = (() => {
                      {
                        const $t28089 = game.score;
                        {
                          const $t28093 = (() => {
                            {
                              const $t28091 = (() => {
                                {
                                  const $t28090 = (() => {
                                    {
                                      const go_i3778 = { $: "$Clo_go$4775", _0: go$apply$4775 };
                                      return go$apply$4775(go_i3778, dead, 0);
                                    }
                                  })();
                                  {
                                    const sr_s1 = ($t28090 + $t28090);
                                    return sr_s1;
                                  }
                                }
                              })();
                              {
                                const $t28092 = game.multiplier;
                                return ($t28091 * $t28092);
                              }
                            }
                          })();
                          return ($t28089 + $t28093);
                        }
                      }
                    })();
                    return ({ ...game, ships: alive, player_shots: shots, score: $t28094 });
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
      const $f28121 = dead._0;
      const $f28122 = dead._1;
      {
        const rest = $f28122;
        {
          const sh = $f28121;
          {
            const pos = (() => {
              {
                const pos_i3795 = (() => {
                  {
                    const $t27355_i3793 = sh.x;
                    {
                      const $t27356_i3794 = sh.y;
                      return { _0: $t27355_i3793, _1: $t27356_i3794 };
                    }
                  }
                })();
                return pos_i3795;
              }
            })();
            {
              const sx = pos._0;
              {
                const sy = pos._1;
                {
                  const $p28119 = (() => {
                    {
                      const $t28096 = game.rng;
                      {
                        const $p29016_i10423_i10722_i10973 = (() => {
                          {
                            const $p15579_i10148_i10418_i10717_i10968 = (() => {
                              {
                                const $p15576_i1532_i10138_i10409_i10708_i10959 = Random$next_raw($t28096);
                                {
                                  const hi_i1533_i10139_i10410_i10709_i10960 = $p15576_i1532_i10138_i10409_i10708_i10959._0;
                                  {
                                    const rng2_i1534_i10140_i10411_i10710_i10961 = $p15576_i1532_i10138_i10409_i10708_i10959._1;
                                    {
                                      const $p15575_i1535_i10141_i10412_i10711_i10962 = Random$next_raw(rng2_i1534_i10140_i10411_i10710_i10961);
                                      {
                                        const lo_i1536_i10142_i10413_i10712_i10963 = $p15575_i1535_i10141_i10412_i10711_i10962._0;
                                        {
                                          const rng3_i1537_i10143_i10414_i10713_i10964 = $p15575_i1535_i10141_i10412_i10711_i10962._1;
                                          {
                                            const $t15574_i1541_i10147_i10417_i10716_i10967 = (() => {
                                              {
                                                const $t15573_i1540_i10146_i10416_i10715_i10966 = (() => {
                                                  {
                                                    const $t15571_i1538_i10144_i10415_i10714_i10965 = march_int_and(hi_i1533_i10139_i10410_i10709_i10960, 1048575);
                                                    return ($t15571_i1538_i10144_i10415_i10714_i10965 * 4294967296);
                                                  }
                                                })();
                                                return ($t15573_i1540_i10146_i10416_i10715_i10966 + lo_i1536_i10142_i10413_i10712_i10963);
                                              }
                                            })();
                                            return { _0: $t15574_i1541_i10147_i10417_i10716_i10967, _1: rng3_i1537_i10143_i10414_i10713_i10964 };
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const bits_i10149_i10419_i10718_i10969 = $p15579_i10148_i10418_i10717_i10968._0;
                              {
                                const rng2_i10150_i10420_i10719_i10970 = $p15579_i10148_i10418_i10717_i10968._1;
                                {
                                  const $t15578_i10152_i10422_i10721_i10972 = (() => {
                                    {
                                      const $t15577_i10151_i10421_i10720_i10971 = bits_i10149_i10419_i10718_i10969;
                                      return ($t15577_i10151_i10421_i10720_i10971 / 4.50359962737e+15);
                                    }
                                  })();
                                  return { _0: $t15578_i10152_i10422_i10721_i10972, _1: rng2_i10150_i10420_i10719_i10970 };
                                }
                              }
                            }
                          }
                        })();
                        {
                          const t_i10424_i10723_i10974 = $p29016_i10423_i10722_i10973._0;
                          {
                            const rng2_i10425_i10724_i10975 = $p29016_i10423_i10722_i10973._1;
                            {
                              const out_i10426_i10725_i10976 = { _0: rng2_i10425_i10724_i10975, _1: t_i10424_i10723_i10974 };
                              return out_i10426_i10725_i10976;
                            }
                          }
                        }
                      }
                    }
                  })();
                  {
                    const rng2 = $p28119._0;
                    {
                      const roll = $p28119._1;
                      {
                        const g2 = (() => {
                          {
                            const $t28098 = (roll < 0.25);
                            if ($t28098 === true) {
                              return (() => {
                                {
                                  const owns_starkiller = (() => {
                                    {
                                      const $t28099 = game.owned_weapons;
                                      {
                                        const $t28100 = { $: "StarKiller" };
                                        {
                                          const $t669_i3791 = { $: "$Clo_$lam668$4780", _0: $lam668$apply$4780, _1: $t28100 };
                                          return List$any$List_WeaponKind$Fn_WeaponKind_Bool($t28099, $t669_i3791);
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $p28118 = (() => {
                                      {
                                        const $p29016_i10423_i10722_i10954 = (() => {
                                          {
                                            const $p15579_i10148_i10418_i10717_i10949 = (() => {
                                              {
                                                const $p15576_i1532_i10138_i10409_i10708_i10940 = Random$next_raw(rng2);
                                                {
                                                  const hi_i1533_i10139_i10410_i10709_i10941 = $p15576_i1532_i10138_i10409_i10708_i10940._0;
                                                  {
                                                    const rng2_i1534_i10140_i10411_i10710_i10942 = $p15576_i1532_i10138_i10409_i10708_i10940._1;
                                                    {
                                                      const $p15575_i1535_i10141_i10412_i10711_i10943 = Random$next_raw(rng2_i1534_i10140_i10411_i10710_i10942);
                                                      {
                                                        const lo_i1536_i10142_i10413_i10712_i10944 = $p15575_i1535_i10141_i10412_i10711_i10943._0;
                                                        {
                                                          const rng3_i1537_i10143_i10414_i10713_i10945 = $p15575_i1535_i10141_i10412_i10711_i10943._1;
                                                          {
                                                            const $t15574_i1541_i10147_i10417_i10716_i10948 = (() => {
                                                              {
                                                                const $t15573_i1540_i10146_i10416_i10715_i10947 = (() => {
                                                                  {
                                                                    const $t15571_i1538_i10144_i10415_i10714_i10946 = march_int_and(hi_i1533_i10139_i10410_i10709_i10941, 1048575);
                                                                    return ($t15571_i1538_i10144_i10415_i10714_i10946 * 4294967296);
                                                                  }
                                                                })();
                                                                return ($t15573_i1540_i10146_i10416_i10715_i10947 + lo_i1536_i10142_i10413_i10712_i10944);
                                                              }
                                                            })();
                                                            return { _0: $t15574_i1541_i10147_i10417_i10716_i10948, _1: rng3_i1537_i10143_i10414_i10713_i10945 };
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            })();
                                            {
                                              const bits_i10149_i10419_i10718_i10950 = $p15579_i10148_i10418_i10717_i10949._0;
                                              {
                                                const rng2_i10150_i10420_i10719_i10951 = $p15579_i10148_i10418_i10717_i10949._1;
                                                {
                                                  const $t15578_i10152_i10422_i10721_i10953 = (() => {
                                                    {
                                                      const $t15577_i10151_i10421_i10720_i10952 = bits_i10149_i10419_i10718_i10950;
                                                      return ($t15577_i10151_i10421_i10720_i10952 / 4.50359962737e+15);
                                                    }
                                                  })();
                                                  return { _0: $t15578_i10152_i10422_i10721_i10953, _1: rng2_i10150_i10420_i10719_i10951 };
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        {
                                          const t_i10424_i10723_i10955 = $p29016_i10423_i10722_i10954._0;
                                          {
                                            const rng2_i10425_i10724_i10956 = $p29016_i10423_i10722_i10954._1;
                                            {
                                              const out_i10426_i10725_i10957 = { _0: rng2_i10425_i10724_i10956, _1: t_i10424_i10723_i10955 };
                                              return out_i10426_i10725_i10957;
                                            }
                                          }
                                        }
                                      }
                                    })();
                                    {
                                      const rng3 = $p28118._0;
                                      {
                                        const sk_roll = $p28118._1;
                                        {
                                          const $t28104 = (() => {
                                            {
                                              const $t28101 = (!owns_starkiller);
                                              {
                                                const $t28103 = (sk_roll < 0.08);
                                                return ($t28101 && $t28103);
                                              }
                                            }
                                          })();
                                          if ($t28104 === true) {
                                            return (() => {
                                              {
                                                const $t28108 = (() => {
                                                  {
                                                    const $t28107 = (() => {
                                                      {
                                                        const $t28106 = { $: "StarKiller" };
                                                        return { $: "OffenseWeapon", _0: $t28106 };
                                                      }
                                                    })();
                                                    return ({ x: sx, y: sy, ttl: 8., kind: $t28107 });
                                                  }
                                                })();
                                                {
                                                  const $t28109 = game.pickups;
                                                  {
                                                    const $t28110 = (() => {
                                                      return { $: "Cons", _0: $t28108, _1: $t28109 };
                                                    })();
                                                    return ({ ...game, rng: rng3, pickups: $t28110 });
                                                  }
                                                }
                                              }
                                            })();
                                          } else {
                                            return (() => {
                                              {
                                                const $p28117 = (() => {
                                                  {
                                                    const $t28111 = game.owned_weapons;
                                                    {
                                                      const $t28112 = game.special;
                                                      return Perihelion$Upgrades$roll_one(rng3, $t28111, $t28112);
                                                    }
                                                  }
                                                })();
                                                {
                                                  const rng4 = $p28117._0;
                                                  {
                                                    const upgrade = $p28117._1;
                                                    {
                                                      const $t28114 = (() => {
                                                        return ({ x: sx, y: sy, ttl: 8., kind: upgrade });
                                                      })();
                                                      {
                                                        const $t28115 = game.pickups;
                                                        {
                                                          const $t28116 = (() => {
                                                            return { $: "Cons", _0: $t28114, _1: $t28115 };
                                                          })();
                                                          return ({ ...game, rng: rng4, pickups: $t28116 });
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
    const $t28136 = (() => {
      {
        const $t28133 = game.pickups;
        {
          const $t28135 = { $: "$Clo_$lam28134$3713", _0: $lam28134$apply$3713, _1: game };
          return List$find$List_R_kind_UpgradeKind_ttl_Float_x_Float_y_Float$Fn_R_kind_UpgradeKind_ttl_Float_x_Float_y_Float_Bool($t28133, $t28135);
        }
      }
    })();
    switch ($t28136.$) {
      case "None": {
        return game;
        break;
      }
      case "Some": {
        const $f28162 = $t28136._0;
        {
          const p = $f28162;
          {
            const $t28137 = game.pickups;
            {
              const $t28140 = { $: "$Clo_$lam28138$3714", _0: $lam28138$apply$3714, _1: game };
              {
                const remaining = (() => {
                  {
                    const pred_i3799 = $t28140;
                    {
                      const go_i3800 = { $: "$Clo_go$4749", _0: go$apply$4749, _1: pred_i3799 };
                      {
                        const $t302_i3801 = { $: "Nil" };
                        return go$apply$4749(go_i3800, $t28137, $t302_i3801);
                      }
                    }
                  }
                })();
                {
                  const $t28141 = p.kind;
                  switch ($t28141.$) {
                    case "SpecialItem": {
                      const $f28155 = $t28141._0;
                      {
                        const $jp_clo28157 = (() => {
                          return { $: "$Clo_$jp28156$3715", _0: $jp28156$apply$3715, _1: game, _2: p, _3: remaining };
                        })();
                        {
                          const $t28142 = game.special;
                          switch ($t28142.$) {
                            case "None": {
                              {
                                const $t28144 = (() => {
                                  {
                                    const $t28143 = p.kind;
                                    return Perihelion$Core$apply_upgrade(game, $t28143);
                                  }
                                })();
                                return ({ ...$t28144, pickups: remaining });
                              }
                              break;
                            }
                            case "Some": {
                              const $f28149 = $t28142._0;
                              {
                                const $t28145 = { $: "Milestone" };
                                {
                                  const $t28146 = p.kind;
                                  {
                                    const $t28147 = { $: "Nil" };
                                    {
                                      const $t28148 = (() => {
                                        return { $: "Cons", _0: $t28146, _1: $t28147 };
                                      })();
                                      return ({ ...game, pickups: remaining, phase: $t28145, milestone_choices: $t28148 });
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
                    case "DefenseShield": {
                      {
                        const $jp_clo28161 = (() => {
                          return { $: "$Clo_$jp28160$3716", _0: $jp28160$apply$3716, _1: game, _2: p, _3: remaining };
                        })();
                        {
                          const grant = (() => {
                            {
                              const $t28150 = game.shield_reinforced;
                              if ($t28150 === true) {
                                return 2;
                              } else {
                                return 1;
                              }
                            }
                          })();
                          {
                            const $t28152 = (() => {
                              {
                                const $t28151 = game.shield;
                                return ($t28151 + grant);
                              }
                            })();
                            return ({ ...game, shield: $t28152, pickups: remaining });
                          }
                        }
                      }
                      break;
                    }
                    default: {
                      {
                        const $t28154 = (() => {
                          {
                            const $t28153 = p.kind;
                            return Perihelion$Core$apply_upgrade(game, $t28153);
                          }
                        })();
                        return ({ ...$t28154, pickups: remaining });
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
const Perihelion$Combat$collide_ball_pickups$clo = { _0: ($_, game) => Perihelion$Combat$collide_ball_pickups(game) };

function Perihelion$Combat$ball_hits_ship(game, sh) {
  {
    const pos = (() => {
      {
        const pos_i3805 = (() => {
          {
            const $t27355_i3803 = sh.x;
            {
              const $t27356_i3804 = sh.y;
              return { _0: $t27355_i3803, _1: $t27356_i3804 };
            }
          }
        })();
        return pos_i3805;
      }
    })();
    {
      const sx = pos._0;
      {
        const sy = pos._1;
        {
          const $t28164 = game.ball_x;
          {
            const $t28165 = game.ball_y;
            {
              const $t27359_i10037 = (() => {
                {
                  const dx_i3632_i10033 = ($t28164 - sx);
                  {
                    const dy_i3633_i10034 = ($t28165 - sy);
                    {
                      const $t27357_i3634_i10035 = (dx_i3632_i10033 * dx_i3632_i10033);
                      {
                        const $t27358_i3635_i10036 = (dy_i3633_i10034 * dy_i3633_i10034);
                        return ($t27357_i3634_i10035 + $t27358_i3635_i10036);
                      }
                    }
                  }
                }
              })();
              {
                const $t27362_i10040 = (() => {
                  {
                    const $t27360_i10038 = (10. + 6.);
                    {
                      const $t27361_i10039 = (10. + 6.);
                      return ($t27360_i10038 * $t27361_i10039);
                    }
                  }
                })();
                return ($t27359_i10037 <= $t27362_i10040);
              }
            }
          }
        }
      }
    }
  }
}
const Perihelion$Combat$ball_hits_ship$clo = { _0: ($_, game, sh) => Perihelion$Combat$ball_hits_ship(game, sh) };

function Perihelion$Combat$deflector_roll(game) {
  {
    const $p28179 = (() => {
      {
        const $t28177 = game.rng;
        {
          const $p29016_i10423_i10722_i10992 = (() => {
            {
              const $p15579_i10148_i10418_i10717_i10987 = (() => {
                {
                  const $p15576_i1532_i10138_i10409_i10708_i10978 = Random$next_raw($t28177);
                  {
                    const hi_i1533_i10139_i10410_i10709_i10979 = $p15576_i1532_i10138_i10409_i10708_i10978._0;
                    {
                      const rng2_i1534_i10140_i10411_i10710_i10980 = $p15576_i1532_i10138_i10409_i10708_i10978._1;
                      {
                        const $p15575_i1535_i10141_i10412_i10711_i10981 = Random$next_raw(rng2_i1534_i10140_i10411_i10710_i10980);
                        {
                          const lo_i1536_i10142_i10413_i10712_i10982 = $p15575_i1535_i10141_i10412_i10711_i10981._0;
                          {
                            const rng3_i1537_i10143_i10414_i10713_i10983 = $p15575_i1535_i10141_i10412_i10711_i10981._1;
                            {
                              const $t15574_i1541_i10147_i10417_i10716_i10986 = (() => {
                                {
                                  const $t15573_i1540_i10146_i10416_i10715_i10985 = (() => {
                                    {
                                      const $t15571_i1538_i10144_i10415_i10714_i10984 = march_int_and(hi_i1533_i10139_i10410_i10709_i10979, 1048575);
                                      return ($t15571_i1538_i10144_i10415_i10714_i10984 * 4294967296);
                                    }
                                  })();
                                  return ($t15573_i1540_i10146_i10416_i10715_i10985 + lo_i1536_i10142_i10413_i10712_i10982);
                                }
                              })();
                              return { _0: $t15574_i1541_i10147_i10417_i10716_i10986, _1: rng3_i1537_i10143_i10414_i10713_i10983 };
                            }
                          }
                        }
                      }
                    }
                  }
                }
              })();
              {
                const bits_i10149_i10419_i10718_i10988 = $p15579_i10148_i10418_i10717_i10987._0;
                {
                  const rng2_i10150_i10420_i10719_i10989 = $p15579_i10148_i10418_i10717_i10987._1;
                  {
                    const $t15578_i10152_i10422_i10721_i10991 = (() => {
                      {
                        const $t15577_i10151_i10421_i10720_i10990 = bits_i10149_i10419_i10718_i10988;
                        return ($t15577_i10151_i10421_i10720_i10990 / 4.50359962737e+15);
                      }
                    })();
                    return { _0: $t15578_i10152_i10422_i10721_i10991, _1: rng2_i10150_i10420_i10719_i10989 };
                  }
                }
              }
            }
          })();
          {
            const t_i10424_i10723_i10993 = $p29016_i10423_i10722_i10992._0;
            {
              const rng2_i10425_i10724_i10994 = $p29016_i10423_i10722_i10992._1;
              {
                const out_i10426_i10725_i10995 = { _0: rng2_i10425_i10724_i10994, _1: t_i10424_i10723_i10993 };
                return out_i10426_i10725_i10995;
              }
            }
          }
        }
      }
    })();
    {
      const rng2 = $p28179._0;
      {
        const t = $p28179._1;
        {
          const $t28178 = (t < 0.5);
          return { _0: rng2, _1: $t28178 };
        }
      }
    }
  }
}
const Perihelion$Combat$deflector_roll$clo = { _0: ($_, game) => Perihelion$Combat$deflector_roll(game) };

function Perihelion$Combat$collide_ball_hazards(game) {
  {
    const shot_hit = (() => {
      {
        const $t28180 = game.enemy_shots;
        {
          const $t28182 = { $: "$Clo_$lam28181$3717", _0: $lam28181$apply$3717, _1: game };
          return List$any$List_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28180, $t28182);
        }
      }
    })();
    {
      const $t28184 = (() => {
        {
          const $t28183 = game.bullet_ward;
          return (shot_hit && $t28183);
        }
      })();
      if ($t28184 === true) {
        return (() => {
          {
            const $t28185 = game.enemy_shots;
            {
              const $t28188 = { $: "$Clo_$lam28186$3718", _0: $lam28186$apply$3718, _1: game };
              {
                const $t28189 = (() => {
                  {
                    const pred_i3807 = $t28188;
                    {
                      const go_i3808 = { $: "$Clo_go$4753", _0: go$apply$4753, _1: pred_i3807 };
                      {
                        const $t302_i3809 = { $: "Nil" };
                        return go$apply$4753(go_i3808, $t28185, $t302_i3809);
                      }
                    }
                  }
                })();
                return ({ ...game, bullet_ward: false, enemy_shots: $t28189 });
              }
            }
          }
        })();
      } else {
        return (() => {
          {
            const ast_hit = (() => {
              {
                const $t28190 = game.asteroids;
                {
                  const $t28192 = { $: "$Clo_$lam28191$3719", _0: $lam28191$apply$3719, _1: game };
                  return List$any$List_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28190, $t28192);
                }
              }
            })();
            {
              const ship_hit = (() => {
                {
                  const $t28193 = game.ships;
                  {
                    const $t28195 = { $: "$Clo_$lam28194$3720", _0: $lam28194$apply$3720, _1: game };
                    return List$any$List_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float$Fn_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float_Bool($t28193, $t28195);
                  }
                }
              })();
              {
                const $t28198 = (() => {
                  {
                    const $t28197 = (() => {
                      {
                        const $t28196 = (ast_hit || shot_hit);
                        return ($t28196 || ship_hit);
                      }
                    })();
                    return (!$t28197);
                  }
                })();
                if ($t28198 === true) {
                  return game;
                } else {
                  return (() => {
                    {
                      const $t28204 = (() => {
                        {
                          const $t28202 = (() => {
                            {
                              const $t28200 = (() => {
                                {
                                  const $t28199 = (!shot_hit);
                                  return (ast_hit && $t28199);
                                }
                              })();
                              {
                                const $t28201 = (!ship_hit);
                                return ($t28200 && $t28201);
                              }
                            }
                          })();
                          {
                            const $t28203 = game.deflector_plating;
                            return ($t28202 && $t28203);
                          }
                        }
                      })();
                      if ($t28204 === true) {
                        return (() => {
                          {
                            const $p28206 = Perihelion$Combat$deflector_roll(game);
                            {
                              const rng2 = $p28206._0;
                              {
                                const deflected = $p28206._1;
                                if (deflected === true) {
                                  return ({ ...game, rng: rng2 });
                                } else {
                                  return (() => {
                                    {
                                      const $t28205 = ({ ...game, rng: rng2 });
                                      return Perihelion$Combat$collide_ball_hazards_shield_or_die($t28205);
                                    }
                                  })();
                                }
                              }
                            }
                          }
                        })();
                      } else {
                        return Perihelion$Combat$collide_ball_hazards_shield_or_die(game);
                      }
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
const Perihelion$Combat$collide_ball_hazards$clo = { _0: ($_, game) => Perihelion$Combat$collide_ball_hazards(game) };

function Perihelion$Combat$collide_ball_hazards_shield_or_die(game) {
  {
    const $t28208 = (() => {
      {
        const $t28207 = game.shield;
        return ($t28207 > 0);
      }
    })();
    if ($t28208 === true) {
      return (() => {
        {
          const $t28209 = game.asteroids;
          {
            const $t28211 = { $: "$Clo_$lam28210$3721", _0: $lam28210$apply$3721, _1: game };
            {
              const dead_ast = (() => {
                {
                  const pred_i3823 = $t28211;
                  {
                    const go_i3824 = { $: "$Clo_go$4784", _0: go$apply$4784, _1: pred_i3823 };
                    {
                      const $t302_i3825 = { $: "Nil" };
                      return go$apply$4784(go_i3824, $t28209, $t302_i3825);
                    }
                  }
                }
              })();
              {
                const $t28213 = (() => {
                  {
                    const $t28212 = game.shield;
                    return ($t28212 - 1);
                  }
                })();
                {
                  const $t28214 = game.asteroids;
                  {
                    const $t28217 = { $: "$Clo_$lam28215$3722", _0: $lam28215$apply$3722, _1: game };
                    {
                      const $t28218 = (() => {
                        {
                          const pred_i3819 = $t28217;
                          {
                            const go_i3820 = { $: "$Clo_go$4784", _0: go$apply$4784, _1: pred_i3819 };
                            {
                              const $t302_i3821 = { $: "Nil" };
                              return go$apply$4784(go_i3820, $t28214, $t302_i3821);
                            }
                          }
                        }
                      })();
                      {
                        const $t28219 = game.enemy_shots;
                        {
                          const $t28222 = { $: "$Clo_$lam28220$3723", _0: $lam28220$apply$3723, _1: game };
                          {
                            const $t28223 = (() => {
                              {
                                const pred_i3815 = $t28222;
                                {
                                  const go_i3816 = { $: "$Clo_go$4753", _0: go$apply$4753, _1: pred_i3815 };
                                  {
                                    const $t302_i3817 = { $: "Nil" };
                                    return go$apply$4753(go_i3816, $t28219, $t302_i3817);
                                  }
                                }
                              }
                            })();
                            {
                              const $t28224 = game.ships;
                              {
                                const $t28227 = { $: "$Clo_$lam28225$3724", _0: $lam28225$apply$3724, _1: game };
                                {
                                  const $t28228 = (() => {
                                    {
                                      const pred_i3811 = $t28227;
                                      {
                                        const go_i3812 = { $: "$Clo_go$4765", _0: go$apply$4765, _1: pred_i3811 };
                                        {
                                          const $t302_i3813 = { $: "Nil" };
                                          return go$apply$4765(go_i3812, $t28224, $t302_i3813);
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t28229 = game.fx_bursts;
                                    {
                                      const $t28230 = (() => {
                                        {
                                          const $t28047_i10062 = { $: "$Clo_$lam28044$3703", _0: $lam28044$apply$3703 };
                                          {
                                            const f_i3759_i10063 = $t28047_i10062;
                                            {
                                              const go_i3760_i10064 = { $: "$Clo_go$4767", _0: go$apply$4767, _1: f_i3759_i10063 };
                                              {
                                                const $t270_i3761_i10065 = { $: "Nil" };
                                                return go$apply$4767(go_i3760_i10064, dead_ast, $t270_i3761_i10065);
                                              }
                                            }
                                          }
                                        }
                                      })();
                                      {
                                        const $t28231 = (() => {
                                          {
                                            const go_i10057 = { $: "$Clo_go$4782", _0: go$apply$4782 };
                                            {
                                              const $t261_i10060 = (() => {
                                                {
                                                  const go_i4485_i10058 = { $: "$Clo_go$4307", _0: go$apply$4307 };
                                                  {
                                                    const $t253_i4486_i10059 = { $: "Nil" };
                                                    return go$apply$4307(go_i4485_i10058, $t28229, $t253_i4486_i10059);
                                                  }
                                                }
                                              })();
                                              return go$apply$4782(go_i10057, $t261_i10060, $t28230);
                                            }
                                          }
                                        })();
                                        return ({ ...game, shield: $t28213, asteroids: $t28218, enemy_shots: $t28223, ships: $t28228, fx_bursts: $t28231 });
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
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
}
const Perihelion$Combat$collide_ball_hazards_shield_or_die$clo = { _0: ($_, game) => Perihelion$Combat$collide_ball_hazards_shield_or_die(game) };

function Perihelion$Combat$spawn_star_turret(game, star_idx, rng) {
  {
    const $t28232 = Perihelion$Core$star_at(game, star_idx);
    switch ($t28232.$) {
      case "None": {
        return ({ ...game, rng: rng });
        break;
      }
      case "Some": {
        const $f28253 = $t28232._0;
        {
          const s = $f28253;
          {
            const $p28252 = (() => {
              {
                const $p29016_i10423_i10722_i11011 = (() => {
                  {
                    const $p15579_i10148_i10418_i10717_i11006 = (() => {
                      {
                        const $p15576_i1532_i10138_i10409_i10708_i10997 = Random$next_raw(rng);
                        {
                          const hi_i1533_i10139_i10410_i10709_i10998 = $p15576_i1532_i10138_i10409_i10708_i10997._0;
                          {
                            const rng2_i1534_i10140_i10411_i10710_i10999 = $p15576_i1532_i10138_i10409_i10708_i10997._1;
                            {
                              const $p15575_i1535_i10141_i10412_i10711_i11000 = Random$next_raw(rng2_i1534_i10140_i10411_i10710_i10999);
                              {
                                const lo_i1536_i10142_i10413_i10712_i11001 = $p15575_i1535_i10141_i10412_i10711_i11000._0;
                                {
                                  const rng3_i1537_i10143_i10414_i10713_i11002 = $p15575_i1535_i10141_i10412_i10711_i11000._1;
                                  {
                                    const $t15574_i1541_i10147_i10417_i10716_i11005 = (() => {
                                      {
                                        const $t15573_i1540_i10146_i10416_i10715_i11004 = (() => {
                                          {
                                            const $t15571_i1538_i10144_i10415_i10714_i11003 = march_int_and(hi_i1533_i10139_i10410_i10709_i10998, 1048575);
                                            return ($t15571_i1538_i10144_i10415_i10714_i11003 * 4294967296);
                                          }
                                        })();
                                        return ($t15573_i1540_i10146_i10416_i10715_i11004 + lo_i1536_i10142_i10413_i10712_i11001);
                                      }
                                    })();
                                    return { _0: $t15574_i1541_i10147_i10417_i10716_i11005, _1: rng3_i1537_i10143_i10414_i10713_i11002 };
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    })();
                    {
                      const bits_i10149_i10419_i10718_i11007 = $p15579_i10148_i10418_i10717_i11006._0;
                      {
                        const rng2_i10150_i10420_i10719_i11008 = $p15579_i10148_i10418_i10717_i11006._1;
                        {
                          const $t15578_i10152_i10422_i10721_i11010 = (() => {
                            {
                              const $t15577_i10151_i10421_i10720_i11009 = bits_i10149_i10419_i10718_i11007;
                              return ($t15577_i10151_i10421_i10720_i11009 / 4.50359962737e+15);
                            }
                          })();
                          return { _0: $t15578_i10152_i10422_i10721_i11010, _1: rng2_i10150_i10420_i10719_i11008 };
                        }
                      }
                    }
                  }
                })();
                {
                  const t_i10424_i10723_i11012 = $p29016_i10423_i10722_i11011._0;
                  {
                    const rng2_i10425_i10724_i11013 = $p29016_i10423_i10722_i11011._1;
                    {
                      const out_i10426_i10725_i11014 = { _0: rng2_i10425_i10724_i11013, _1: t_i10424_i10723_i11012 };
                      return out_i10426_i10725_i11014;
                    }
                  }
                }
              }
            })();
            {
              const rng2 = $p28252._0;
              {
                const idle_f = $p28252._1;
                {
                  const r = (() => {
                    {
                      const $t28233 = s.capture_radius;
                      return ($t28233 * 1.6);
                    }
                  })();
                  {
                    const idle = (() => {
                      {
                        const $t28239 = (() => {
                          {
                            const $t28238 = (6. - 3.);
                            return (idle_f * $t28238);
                          }
                        })();
                        return (3. + $t28239);
                      }
                    })();
                    {
                      const ship = (() => {
                        {
                          const $t28243 = (() => {
                            {
                              const $t28240 = s.x;
                              {
                                const $t28242 = (() => {
                                  {
                                    const $t28241 = Math.cos(0.);
                                    return ($t28241 * r);
                                  }
                                })();
                                return ($t28240 + $t28242);
                              }
                            }
                          })();
                          {
                            const $t28247 = (() => {
                              {
                                const $t28244 = s.y;
                                {
                                  const $t28246 = (() => {
                                    {
                                      const $t28245 = Math.sin(0.);
                                      return ($t28245 * r);
                                    }
                                  })();
                                  return ($t28244 + $t28246);
                                }
                              }
                            })();
                            {
                              const $t28248 = { $: "ShipOrbiting", _0: 0. };
                              return ({ star_idx: star_idx, x: $t28243, y: $t28247, mode: $t28248, fire_cooldown: 2.5, idle_timer: idle, hunter: false });
                            }
                          }
                        }
                      })();
                      {
                        const $t28250 = game.ships;
                        {
                          const $t28251 = (() => {
                            return { $: "Cons", _0: ship, _1: $t28250 };
                          })();
                          return ({ ...game, rng: rng2, ships: $t28251 });
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
        const $t28255 = (() => {
          {
            const $t28254 = game.current;
            return ($t28254 > 0);
          }
        })();
        if ($t28255 === true) {
          return (() => {
            {
              const $t28256 = game.current;
              return ($t28256 - 1);
            }
          })();
        } else {
          return 0;
        }
      }
    })();
    {
      const $t28257 = Perihelion$Core$star_at(game, idx);
      switch ($t28257.$) {
        case "None": {
          return ({ ...game, rng: rng });
          break;
        }
        case "Some": {
          const $f28278 = $t28257._0;
          {
            const s = $f28278;
            {
              const $p28277 = (() => {
                {
                  const $p29016_i10423_i10722_i11030 = (() => {
                    {
                      const $p15579_i10148_i10418_i10717_i11025 = (() => {
                        {
                          const $p15576_i1532_i10138_i10409_i10708_i11016 = Random$next_raw(rng);
                          {
                            const hi_i1533_i10139_i10410_i10709_i11017 = $p15576_i1532_i10138_i10409_i10708_i11016._0;
                            {
                              const rng2_i1534_i10140_i10411_i10710_i11018 = $p15576_i1532_i10138_i10409_i10708_i11016._1;
                              {
                                const $p15575_i1535_i10141_i10412_i10711_i11019 = Random$next_raw(rng2_i1534_i10140_i10411_i10710_i11018);
                                {
                                  const lo_i1536_i10142_i10413_i10712_i11020 = $p15575_i1535_i10141_i10412_i10711_i11019._0;
                                  {
                                    const rng3_i1537_i10143_i10414_i10713_i11021 = $p15575_i1535_i10141_i10412_i10711_i11019._1;
                                    {
                                      const $t15574_i1541_i10147_i10417_i10716_i11024 = (() => {
                                        {
                                          const $t15573_i1540_i10146_i10416_i10715_i11023 = (() => {
                                            {
                                              const $t15571_i1538_i10144_i10415_i10714_i11022 = march_int_and(hi_i1533_i10139_i10410_i10709_i11017, 1048575);
                                              return ($t15571_i1538_i10144_i10415_i10714_i11022 * 4294967296);
                                            }
                                          })();
                                          return ($t15573_i1540_i10146_i10416_i10715_i11023 + lo_i1536_i10142_i10413_i10712_i11020);
                                        }
                                      })();
                                      return { _0: $t15574_i1541_i10147_i10417_i10716_i11024, _1: rng3_i1537_i10143_i10414_i10713_i11021 };
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      })();
                      {
                        const bits_i10149_i10419_i10718_i11026 = $p15579_i10148_i10418_i10717_i11025._0;
                        {
                          const rng2_i10150_i10420_i10719_i11027 = $p15579_i10148_i10418_i10717_i11025._1;
                          {
                            const $t15578_i10152_i10422_i10721_i11029 = (() => {
                              {
                                const $t15577_i10151_i10421_i10720_i11028 = bits_i10149_i10419_i10718_i11026;
                                return ($t15577_i10151_i10421_i10720_i11028 / 4.50359962737e+15);
                              }
                            })();
                            return { _0: $t15578_i10152_i10422_i10721_i11029, _1: rng2_i10150_i10420_i10719_i11027 };
                          }
                        }
                      }
                    }
                  })();
                  {
                    const t_i10424_i10723_i11031 = $p29016_i10423_i10722_i11030._0;
                    {
                      const rng2_i10425_i10724_i11032 = $p29016_i10423_i10722_i11030._1;
                      {
                        const out_i10426_i10725_i11033 = { _0: rng2_i10425_i10724_i11032, _1: t_i10424_i10723_i11031 };
                        return out_i10426_i10725_i11033;
                      }
                    }
                  }
                }
              })();
              {
                const rng2 = $p28277._0;
                {
                  const idle_f = $p28277._1;
                  {
                    const r = (() => {
                      {
                        const $t28258 = s.capture_radius;
                        return ($t28258 * 1.6);
                      }
                    })();
                    {
                      const idle = (() => {
                        {
                          const $t28264 = (() => {
                            {
                              const $t28263 = (6. - 3.);
                              return (idle_f * $t28263);
                            }
                          })();
                          return (3. + $t28264);
                        }
                      })();
                      {
                        const ship = (() => {
                          {
                            const $t28268 = (() => {
                              {
                                const $t28265 = s.x;
                                {
                                  const $t28267 = (() => {
                                    {
                                      const $t28266 = Math.cos(0.);
                                      return ($t28266 * r);
                                    }
                                  })();
                                  return ($t28265 + $t28267);
                                }
                              }
                            })();
                            {
                              const $t28272 = (() => {
                                {
                                  const $t28269 = s.y;
                                  {
                                    const $t28271 = (() => {
                                      {
                                        const $t28270 = Math.sin(0.);
                                        return ($t28270 * r);
                                      }
                                    })();
                                    return ($t28269 + $t28271);
                                  }
                                }
                              })();
                              {
                                const $t28273 = { $: "ShipOrbiting", _0: 0. };
                                return ({ star_idx: idx, x: $t28268, y: $t28272, mode: $t28273, fire_cooldown: 2.5, idle_timer: idle, hunter: true });
                              }
                            }
                          }
                        })();
                        {
                          const $t28275 = game.ships;
                          {
                            const $t28276 = (() => {
                              return { $: "Cons", _0: ship, _1: $t28275 };
                            })();
                            return ({ ...game, rng: rng2, ships: $t28276 });
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
    const $t28281 = (() => {
      {
        const $t28279 = game.score;
        return ($t28279 < 4);
      }
    })();
    if ($t28281 === true) {
      return game;
    } else {
      return (() => {
        {
          const $p28293 = (() => {
            {
              const $t28282 = game.rng;
              {
                const $p29016_i10423_i10722_i11068 = (() => {
                  {
                    const $p15579_i10148_i10418_i10717_i11063 = (() => {
                      {
                        const $p15576_i1532_i10138_i10409_i10708_i11054 = Random$next_raw($t28282);
                        {
                          const hi_i1533_i10139_i10410_i10709_i11055 = $p15576_i1532_i10138_i10409_i10708_i11054._0;
                          {
                            const rng2_i1534_i10140_i10411_i10710_i11056 = $p15576_i1532_i10138_i10409_i10708_i11054._1;
                            {
                              const $p15575_i1535_i10141_i10412_i10711_i11057 = Random$next_raw(rng2_i1534_i10140_i10411_i10710_i11056);
                              {
                                const lo_i1536_i10142_i10413_i10712_i11058 = $p15575_i1535_i10141_i10412_i10711_i11057._0;
                                {
                                  const rng3_i1537_i10143_i10414_i10713_i11059 = $p15575_i1535_i10141_i10412_i10711_i11057._1;
                                  {
                                    const $t15574_i1541_i10147_i10417_i10716_i11062 = (() => {
                                      {
                                        const $t15573_i1540_i10146_i10416_i10715_i11061 = (() => {
                                          {
                                            const $t15571_i1538_i10144_i10415_i10714_i11060 = march_int_and(hi_i1533_i10139_i10410_i10709_i11055, 1048575);
                                            return ($t15571_i1538_i10144_i10415_i10714_i11060 * 4294967296);
                                          }
                                        })();
                                        return ($t15573_i1540_i10146_i10416_i10715_i11061 + lo_i1536_i10142_i10413_i10712_i11058);
                                      }
                                    })();
                                    return { _0: $t15574_i1541_i10147_i10417_i10716_i11062, _1: rng3_i1537_i10143_i10414_i10713_i11059 };
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    })();
                    {
                      const bits_i10149_i10419_i10718_i11064 = $p15579_i10148_i10418_i10717_i11063._0;
                      {
                        const rng2_i10150_i10420_i10719_i11065 = $p15579_i10148_i10418_i10717_i11063._1;
                        {
                          const $t15578_i10152_i10422_i10721_i11067 = (() => {
                            {
                              const $t15577_i10151_i10421_i10720_i11066 = bits_i10149_i10419_i10718_i11064;
                              return ($t15577_i10151_i10421_i10720_i11066 / 4.50359962737e+15);
                            }
                          })();
                          return { _0: $t15578_i10152_i10422_i10721_i11067, _1: rng2_i10150_i10420_i10719_i11065 };
                        }
                      }
                    }
                  }
                })();
                {
                  const t_i10424_i10723_i11069 = $p29016_i10423_i10722_i11068._0;
                  {
                    const rng2_i10425_i10724_i11070 = $p29016_i10423_i10722_i11068._1;
                    {
                      const out_i10426_i10725_i11071 = { _0: rng2_i10425_i10724_i11070, _1: t_i10424_i10723_i11069 };
                      return out_i10426_i10725_i11071;
                    }
                  }
                }
              }
            }
          })();
          {
            const rng2 = $p28293._0;
            {
              const roll = $p28293._1;
              {
                const chance_raw = (() => {
                  {
                    const $t28287 = (() => {
                      {
                        const $t28286 = (() => {
                          {
                            const $t28285 = (() => {
                              {
                                const $t28283 = game.score;
                                return ($t28283 - 4);
                              }
                            })();
                            return $t28285;
                          }
                        })();
                        return (0.04 * $t28286);
                      }
                    })();
                    return (0.16 + $t28287);
                  }
                })();
                {
                  const chance = (() => {
                    {
                      const $t28288 = (chance_raw > 0.45);
                      if ($t28288 === true) {
                        return 0.45;
                      } else {
                        return chance_raw;
                      }
                    }
                  })();
                  {
                    const $t28289 = (roll < chance);
                    if ($t28289 === true) {
                      return (() => {
                        {
                          const $p28292 = (() => {
                            {
                              const $p29016_i10423_i10722_i11049 = (() => {
                                {
                                  const $p15579_i10148_i10418_i10717_i11044 = (() => {
                                    {
                                      const $p15576_i1532_i10138_i10409_i10708_i11035 = Random$next_raw(rng2);
                                      {
                                        const hi_i1533_i10139_i10410_i10709_i11036 = $p15576_i1532_i10138_i10409_i10708_i11035._0;
                                        {
                                          const rng2_i1534_i10140_i10411_i10710_i11037 = $p15576_i1532_i10138_i10409_i10708_i11035._1;
                                          {
                                            const $p15575_i1535_i10141_i10412_i10711_i11038 = Random$next_raw(rng2_i1534_i10140_i10411_i10710_i11037);
                                            {
                                              const lo_i1536_i10142_i10413_i10712_i11039 = $p15575_i1535_i10141_i10412_i10711_i11038._0;
                                              {
                                                const rng3_i1537_i10143_i10414_i10713_i11040 = $p15575_i1535_i10141_i10412_i10711_i11038._1;
                                                {
                                                  const $t15574_i1541_i10147_i10417_i10716_i11043 = (() => {
                                                    {
                                                      const $t15573_i1540_i10146_i10416_i10715_i11042 = (() => {
                                                        {
                                                          const $t15571_i1538_i10144_i10415_i10714_i11041 = march_int_and(hi_i1533_i10139_i10410_i10709_i11036, 1048575);
                                                          return ($t15571_i1538_i10144_i10415_i10714_i11041 * 4294967296);
                                                        }
                                                      })();
                                                      return ($t15573_i1540_i10146_i10416_i10715_i11042 + lo_i1536_i10142_i10413_i10712_i11039);
                                                    }
                                                  })();
                                                  return { _0: $t15574_i1541_i10147_i10417_i10716_i11043, _1: rng3_i1537_i10143_i10414_i10713_i11040 };
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const bits_i10149_i10419_i10718_i11045 = $p15579_i10148_i10418_i10717_i11044._0;
                                    {
                                      const rng2_i10150_i10420_i10719_i11046 = $p15579_i10148_i10418_i10717_i11044._1;
                                      {
                                        const $t15578_i10152_i10422_i10721_i11048 = (() => {
                                          {
                                            const $t15577_i10151_i10421_i10720_i11047 = bits_i10149_i10419_i10718_i11045;
                                            return ($t15577_i10151_i10421_i10720_i11047 / 4.50359962737e+15);
                                          }
                                        })();
                                        return { _0: $t15578_i10152_i10422_i10721_i11048, _1: rng2_i10150_i10420_i10719_i11046 };
                                      }
                                    }
                                  }
                                }
                              })();
                              {
                                const t_i10424_i10723_i11050 = $p29016_i10423_i10722_i11049._0;
                                {
                                  const rng2_i10425_i10724_i11051 = $p29016_i10423_i10722_i11049._1;
                                  {
                                    const out_i10426_i10725_i11052 = { _0: rng2_i10425_i10724_i11051, _1: t_i10424_i10723_i11050 };
                                    return out_i10426_i10725_i11052;
                                  }
                                }
                              }
                            }
                          })();
                          {
                            const rng3 = $p28292._0;
                            {
                              const kind_roll = $p28292._1;
                              {
                                const $t28291 = (kind_roll < 0.5);
                                if ($t28291 === true) {
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
    const $t28294 = game.stars;
    return List$nth_opt$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int($t28294, i);
  }
}
const Perihelion$Core$star_at$clo = { _0: ($_, game, i) => Perihelion$Core$star_at(game, i) };

function Perihelion$Core$remove_at(xs, idx) {
  {
    const $t28295 = (() => {
      {
        const go_i3834 = { $: "$Clo_go$4790", _0: go$apply$4790 };
        {
          const $t508_i3835 = { $: "Nil" };
          return go$apply$4790(go_i3834, xs, idx, $t508_i3835);
        }
      }
    })();
    {
      const $t28296 = (idx + 1);
      {
        const $t28297 = List$drop$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int(xs, $t28296);
        {
          const go_i10068 = { $: "$Clo_go$4787", _0: go$apply$4787 };
          {
            const $t261_i10071 = (() => {
              {
                const go_i4489_i10069 = { $: "$Clo_go$5245", _0: go$apply$5245 };
                {
                  const $t253_i4490_i10070 = { $: "Nil" };
                  return go$apply$5245(go_i4489_i10069, $t28295, $t253_i4490_i10070);
                }
              }
            })();
            return go$apply$4787(go_i10068, $t261_i10071, $t28297);
          }
        }
      }
    }
  }
}
const Perihelion$Core$remove_at$clo = { _0: ($_, xs, idx) => Perihelion$Core$remove_at(xs, idx) };

function Perihelion$Core$remove_star(game, idx) {
  {
    const $t28298 = game.stars;
    {
      const $t28299 = (() => {
        return Perihelion$Core$remove_at($t28298, idx);
      })();
      return ({ ...game, stars: $t28299 });
    }
  }
}
const Perihelion$Core$remove_star$clo = { _0: ($_, game, idx) => Perihelion$Core$remove_star(game, idx) };

function Perihelion$Core$ring_count(s) {
  {
    const $t28300 = s.orbits;
    {
      const go_i3837 = { $: "$Clo_go$4792", _0: go$apply$4792 };
      return go$apply$4792(go_i3837, $t28300, 0);
    }
  }
}
const Perihelion$Core$ring_count$clo = { _0: ($_, s) => Perihelion$Core$ring_count(s) };

function Perihelion$Core$ring_at(s, i) {
  {
    const $t28302 = (() => {
      {
        const $t28301 = s.orbits;
        return List$nth_opt$List_R_radius_Float_speed_mult_Float$Int($t28301, i);
      }
    })();
    switch ($t28302.$) {
      case "Some": {
        const $f28305 = $t28302._0;
        {
          const o = $f28305;
          return o;
        }
        break;
      }
      case "None": {
        {
          const $t28303 = s.capture_radius;
          {
            const $t28304 = s.speed_mult;
            return ({ radius: $t28303, speed_mult: $t28304 });
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
        const $t28310 = { $: "$Clo_$lam28307$3725", _0: $lam28307$apply$3725 };
        return List$any$List_String$Fn_String_Bool(keys, $t28310);
      }
    })();
    {
      const inn = (() => {
        {
          const $t28314 = { $: "$Clo_$lam28311$3726", _0: $lam28311$apply$3726 };
          return List$any$List_String$Fn_String_Bool(keys, $t28314);
        }
      })();
      {
        const delta = (() => {
          {
            let $t28315;
            if (out === true) {
              $t28315 = 1;
            } else {
              $t28315 = 0;
            }
            {
              let $t28316;
              if (inn === true) {
                $t28316 = 1;
              } else {
                $t28316 = 0;
              }
              return ($t28315 - $t28316);
            }
          }
        })();
        {
          const target = (ring_idx + delta);
          {
            const $t28317 = (target < 0);
            if ($t28317 === true) {
              return 0;
            } else {
              return (() => {
                {
                  const $t28319 = (() => {
                    {
                      const $t28318 = (n - 1);
                      return (target > $t28318);
                    }
                  })();
                  if ($t28319 === true) {
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

function Perihelion$Core$active_weapon(game) {
  {
    const n = (() => {
      {
        const $t28320 = game.owned_weapons;
        {
          const go_i3841 = { $: "$Clo_go$4796", _0: go$apply$4796 };
          return go$apply$4796(go_i3841, $t28320, 0);
        }
      }
    })();
    {
      const idx = (() => {
        {
          const $t28322 = (() => {
            {
              const $t28321 = game.active_weapon_idx;
              return ($t28321 >= n);
            }
          })();
          if ($t28322 === true) {
            return 0;
          } else {
            return game.active_weapon_idx;
          }
        }
      })();
      {
        const $t28324 = (() => {
          {
            const $t28323 = game.owned_weapons;
            return List$nth_opt$List_WeaponKind$Int($t28323, idx);
          }
        })();
        switch ($t28324.$) {
          case "Some": {
            const $f28325 = $t28324._0;
            {
              const w = $f28325;
              return w;
            }
            break;
          }
          case "None": {
            return { $: "Base" };
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
const Perihelion$Core$active_weapon$clo = { _0: ($_, game) => Perihelion$Core$active_weapon(game) };

function Perihelion$Core$adjust_weapon(idx, keys, n) {
  {
    const next = (() => {
      {
        const $t28329 = { $: "$Clo_$lam28326$3727", _0: $lam28326$apply$3727 };
        return List$any$List_String$Fn_String_Bool(keys, $t28329);
      }
    })();
    {
      const prev = (() => {
        {
          const $t28333 = { $: "$Clo_$lam28330$3728", _0: $lam28330$apply$3728 };
          return List$any$List_String$Fn_String_Bool(keys, $t28333);
        }
      })();
      {
        const delta = (() => {
          {
            let $t28334;
            if (next === true) {
              $t28334 = 1;
            } else {
              $t28334 = 0;
            }
            {
              let $t28335;
              if (prev === true) {
                $t28335 = 1;
              } else {
                $t28335 = 0;
              }
              return ($t28334 - $t28335);
            }
          }
        })();
        {
          const raw = (() => {
            {
              const $t28336 = (idx + delta);
              return march_int_mod($t28336, n);
            }
          })();
          {
            const $t28337 = (raw < 0);
            if ($t28337 === true) {
              return (raw + n);
            } else {
              return raw;
            }
          }
        }
      }
    }
  }
}
const Perihelion$Core$adjust_weapon$clo = { _0: ($_, idx, keys, n) => Perihelion$Core$adjust_weapon(idx, keys, n) };

function Perihelion$Core$adjust_starkiller_target(offset, keys) {
  {
    const dn = (() => {
      {
        const $t28341 = { $: "$Clo_$lam28338$3729", _0: $lam28338$apply$3729 };
        return List$any$List_String$Fn_String_Bool(keys, $t28341);
      }
    })();
    {
      const up = (() => {
        {
          const $t28345 = { $: "$Clo_$lam28342$3730", _0: $lam28342$apply$3730 };
          return List$any$List_String$Fn_String_Bool(keys, $t28345);
        }
      })();
      {
        const delta = (() => {
          {
            let $t28346;
            if (dn === true) {
              $t28346 = 1;
            } else {
              $t28346 = 0;
            }
            {
              let $t28347;
              if (up === true) {
                $t28347 = 1;
              } else {
                $t28347 = 0;
              }
              return ($t28346 - $t28347);
            }
          }
        })();
        {
          const $t28349 = (() => {
            {
              const $t28348 = (offset + delta);
              return ($t28348 + 3);
            }
          })();
          return march_int_mod($t28349, 3);
        }
      }
    }
  }
}
const Perihelion$Core$adjust_starkiller_target$clo = { _0: ($_, offset, keys) => Perihelion$Core$adjust_starkiller_target(offset, keys) };

function Perihelion$Core$nearest_star_dir_go(game, stars, best, best_d2) {
  switch (stars.$) {
    case "Nil": {
      {
        const dx = (() => {
          {
            const $t28352 = best.x;
            {
              const $t28353 = game.ball_x;
              return ($t28352 - $t28353);
            }
          }
        })();
        {
          const dy = (() => {
            {
              const $t28354 = best.y;
              {
                const $t28355 = game.ball_y;
                return ($t28354 - $t28355);
              }
            }
          })();
          {
            const d = Math.sqrt(best_d2);
            {
              const $t28356 = (d > 0.);
              if ($t28356 === true) {
                return (() => {
                  {
                    const $t28359 = (() => {
                      {
                        const $t28357 = (dx / d);
                        {
                          const $t28358 = (dy / d);
                          return { _0: $t28357, _1: $t28358 };
                        }
                      }
                    })();
                    return { $: "Some", _0: $t28359 };
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
    case "Cons": {
      const $f28365 = stars._0;
      const $f28366 = stars._1;
      {
        const rest = (() => {
          return $f28366;
        })();
        {
          const s = (() => {
            return $f28365;
          })();
          {
            const d2 = (() => {
              {
                const $t28360 = game.ball_x;
                {
                  const $t28361 = game.ball_y;
                  {
                    const $t28362 = s.x;
                    {
                      const $t28363 = s.y;
                      {
                        const dx_i3848 = ($t28360 - $t28362);
                        {
                          const dy_i3849 = ($t28361 - $t28363);
                          {
                            const $t28350_i3850 = (dx_i3848 * dx_i3848);
                            {
                              const $t28351_i3851 = (dy_i3849 * dy_i3849);
                              return ($t28350_i3850 + $t28351_i3851);
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
              const $t28364 = (d2 < best_d2);
              if ($t28364 === true) {
                return (() => {
                  return Perihelion$Core$nearest_star_dir_go(game, rest, s, d2);
                })();
              } else {
                return (() => {
                  return Perihelion$Core$nearest_star_dir_go(game, rest, best, best_d2);
                })();
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
const Perihelion$Core$nearest_star_dir_go$clo = { _0: ($_, game, stars, best, best_d2) => Perihelion$Core$nearest_star_dir_go(game, stars, best, best_d2) };

function Perihelion$Core$nearest_star_dir(game) {
  {
    const $t28371 = game.stars;
    switch ($t28371.$) {
      case "Nil": {
        return { $: "None" };
        break;
      }
      case "Cons": {
        const $f28377 = $t28371._0;
        const $f28378 = $t28371._1;
        {
          const rest = (() => {
            return $f28378;
          })();
          {
            const s0 = (() => {
              return $f28377;
            })();
            {
              const $t28376 = (() => {
                {
                  const $t28372 = game.ball_x;
                  {
                    const $t28373 = game.ball_y;
                    {
                      const $t28374 = s0.x;
                      {
                        const $t28375 = s0.y;
                        {
                          const dx_i3857 = ($t28372 - $t28374);
                          {
                            const dy_i3858 = ($t28373 - $t28375);
                            {
                              const $t28350_i3859 = (dx_i3857 * dx_i3857);
                              {
                                const $t28351_i3860 = (dy_i3858 * dy_i3858);
                                return ($t28350_i3859 + $t28351_i3860);
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
                const $rc_822 = Perihelion$Core$nearest_star_dir_go(game, rest, s0, $t28376);
                return $rc_822;
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
const Perihelion$Core$nearest_star_dir$clo = { _0: ($_, game) => Perihelion$Core$nearest_star_dir(game) };

function Perihelion$Core$apply_star_jump(game) {
  {
    const $p28394 = (() => {
      {
        const $t28383 = game.rng;
        {
          const $p29016_i10423_i10741 = (() => {
            {
              const $p15579_i10148_i10418_i10736 = (() => {
                {
                  const $p15576_i1532_i10138_i10409_i10727 = Random$next_raw($t28383);
                  {
                    const hi_i1533_i10139_i10410_i10728 = $p15576_i1532_i10138_i10409_i10727._0;
                    {
                      const rng2_i1534_i10140_i10411_i10729 = $p15576_i1532_i10138_i10409_i10727._1;
                      {
                        const $p15575_i1535_i10141_i10412_i10730 = Random$next_raw(rng2_i1534_i10140_i10411_i10729);
                        {
                          const lo_i1536_i10142_i10413_i10731 = $p15575_i1535_i10141_i10412_i10730._0;
                          {
                            const rng3_i1537_i10143_i10414_i10732 = $p15575_i1535_i10141_i10412_i10730._1;
                            {
                              const $t15574_i1541_i10147_i10417_i10735 = (() => {
                                {
                                  const $t15573_i1540_i10146_i10416_i10734 = (() => {
                                    {
                                      const $t15571_i1538_i10144_i10415_i10733 = march_int_and(hi_i1533_i10139_i10410_i10728, 1048575);
                                      return ($t15571_i1538_i10144_i10415_i10733 * 4294967296);
                                    }
                                  })();
                                  return ($t15573_i1540_i10146_i10416_i10734 + lo_i1536_i10142_i10413_i10731);
                                }
                              })();
                              return { _0: $t15574_i1541_i10147_i10417_i10735, _1: rng3_i1537_i10143_i10414_i10732 };
                            }
                          }
                        }
                      }
                    }
                  }
                }
              })();
              {
                const bits_i10149_i10419_i10737 = $p15579_i10148_i10418_i10736._0;
                {
                  const rng2_i10150_i10420_i10738 = $p15579_i10148_i10418_i10736._1;
                  {
                    const $t15578_i10152_i10422_i10740 = (() => {
                      {
                        const $t15577_i10151_i10421_i10739 = bits_i10149_i10419_i10737;
                        return ($t15577_i10151_i10421_i10739 / 4.50359962737e+15);
                      }
                    })();
                    return { _0: $t15578_i10152_i10422_i10740, _1: rng2_i10150_i10420_i10738 };
                  }
                }
              }
            }
          })();
          {
            const t_i10424_i10742 = $p29016_i10423_i10741._0;
            {
              const rng2_i10425_i10743 = $p29016_i10423_i10741._1;
              {
                const out_i10426_i10744 = { _0: rng2_i10425_i10743, _1: t_i10424_i10742 };
                return out_i10426_i10744;
              }
            }
          }
        }
      }
    })();
    {
      const rng2 = $p28394._0;
      {
        const t = $p28394._1;
        {
          const jump = (() => {
            {
              const $t28387 = (() => {
                {
                  const $t28386 = (() => {
                    {
                      const $t28385 = 4;
                      return (t * $t28385);
                    }
                  })();
                  return Math.trunc($t28386);
                }
              })();
              return (1 + $t28387);
            }
          })();
          {
            const target_idx = (() => {
              {
                const $t28388 = game.current;
                return ($t28388 + jump);
              }
            })();
            {
              const $t28389 = Perihelion$Core$star_at(game, target_idx);
              switch ($t28389.$) {
                case "None": {
                  return ({ ...game, rng: rng2 });
                  break;
                }
                case "Some": {
                  const $f28393 = $t28389._0;
                  {
                    const target = $f28393;
                    {
                      const $t28392 = (() => {
                        {
                          const $t28391 = (() => {
                            {
                              const $t28390 = game.special_charges;
                              return ($t28390 - 1);
                            }
                          })();
                          return ({ ...game, rng: rng2, special_charges: $t28391 });
                        }
                      })();
                      return Perihelion$Core$on_capture($t28392, target, target_idx);
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
const Perihelion$Core$apply_star_jump$clo = { _0: ($_, game) => Perihelion$Core$apply_star_jump(game) };

function Perihelion$Core$apply_special(game, keys) {
  {
    const pressed = (() => {
      {
        const $t28398 = { $: "$Clo_$lam28395$3733", _0: $lam28395$apply$3733 };
        return List$any$List_String$Fn_String_Bool(keys, $t28398);
      }
    })();
    {
      const $t28402 = (() => {
        {
          const $t28399 = (!pressed);
          {
            const $t28401 = (() => {
              {
                const $t28400 = game.special_charges;
                return ($t28400 <= 0);
              }
            })();
            return ($t28399 || $t28401);
          }
        }
      })();
      if ($t28402 === true) {
        return game;
      } else {
        return (() => {
          {
            const $t28403 = game.special;
            switch ($t28403.$) {
              case "None": {
                return game;
                break;
              }
              case "Some": {
                const $f28434 = $t28403._0;
                switch ($f28434.$) {
                  case "StarThrust": {
                    {
                      const $t28404 = Perihelion$Core$nearest_star_dir(game);
                      switch ($t28404.$) {
                        case "None": {
                          return game;
                          break;
                        }
                        case "Some": {
                          const $f28433 = $t28404._0;
                          {
                            const pair = $f28433;
                            {
                              const dx = pair._0;
                              {
                                const dy = pair._1;
                                {
                                  const $t28405 = game.mode;
                                  switch ($t28405.$) {
                                    case "Flying": {
                                      const $f28415 = $t28405._0;
                                      const $f28416 = $t28405._1;
                                      {
                                        const vy = (() => {
                                          return $f28416;
                                        })();
                                        {
                                          const vx = (() => {
                                            return $f28415;
                                          })();
                                          {
                                            const $t28412 = (() => {
                                              {
                                                const $t28408 = (() => {
                                                  {
                                                    const $t28407 = (dx * 60.);
                                                    return (vx + $t28407);
                                                  }
                                                })();
                                                {
                                                  const $t28411 = (() => {
                                                    {
                                                      const $t28410 = (dy * 60.);
                                                      return (vy + $t28410);
                                                    }
                                                  })();
                                                  return { $: "Flying", _0: $t28408, _1: $t28411 };
                                                }
                                              }
                                            })();
                                            {
                                              const $t28414 = (() => {
                                                {
                                                  const $t28413 = game.special_charges;
                                                  return ($t28413 - 1);
                                                }
                                              })();
                                              return ({ ...game, mode: $t28412, special_charges: $t28414 });
                                            }
                                          }
                                        }
                                      }
                                      break;
                                    }
                                    case "Orbiting": {
                                      const $f28421 = $t28405._0;
                                      const $f28422 = $t28405._1;
                                      const $f28423 = $t28405._2;
                                      return game;
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
                          return (() => { throw new Error("non-exhaustive pattern match"); })();
                        }
                      }
                    }
                    break;
                  }
                  case "StarJump": {
                    return Perihelion$Core$apply_star_jump(game);
                    break;
                  }
                  case "TrajectoryPreview": {
                    return game;
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
        })();
      }
    }
  }
}
const Perihelion$Core$apply_special$clo = { _0: ($_, game, keys) => Perihelion$Core$apply_special(game, keys) };

function Perihelion$Core$update(game, taps, keys, cursor, view_w, view_h, dt_s) {
  {
    const g0 = (() => {
      {
        const $t28439 = { $: "Nil" };
        {
          const $t28440 = { $: "None" };
          return ({ ...game, view_w: view_w, view_h: view_h, fx_bursts: $t28439, capture_flash: $t28440 });
        }
      }
    })();
    {
      const $t28441 = (() => {
        {
          const $t28438_i3870 = { $: "$Clo_$lam28435$3738", _0: $lam28435$apply$3738 };
          return List$any$List_String$Fn_String_Bool(keys, $t28438_i3870);
        }
      })();
      if ($t28441 === true) {
        return Perihelion$Core$reset(g0);
      } else {
        return (() => {
          {
            const tapped = (() => {
              {
                let $t28442;
                switch (taps.$) {
                  case "Nil": {
                    $t28442 = true;
                    break;
                  }
                  default: {
                    $t28442 = false;
                    break;
                  }
                }
                return (!$t28442);
              }
            })();
            {
              const $t28443 = g0.phase;
              switch ($t28443.$) {
                case "Ready": {
                  if (tapped === true) {
                    return (() => {
                      {
                        const $t28444 = { $: "Playing" };
                        return ({ ...g0, phase: $t28444 });
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
                case "Milestone": {
                  if (tapped === true) {
                    return (() => {
                      {
                        const $t28446 = (() => {
                          {
                            const $t28445 = g0.milestone_choices;
                            return List$nth_opt$List_UpgradeKind$Int($t28445, 0);
                          }
                        })();
                        switch ($t28446.$) {
                          case "None": {
                            return g0;
                            break;
                          }
                          case "Some": {
                            const $f28451 = $t28446._0;
                            {
                              const choice = $f28451;
                              {
                                const $t28450 = (() => {
                                  {
                                    const $t28447 = Perihelion$Core$apply_upgrade(g0, choice);
                                    {
                                      const $t28448 = { $: "Playing" };
                                      {
                                        const $t28449 = { $: "Nil" };
                                        return ({ ...$t28447, phase: $t28448, milestone_choices: $t28449 });
                                      }
                                    }
                                  }
                                })();
                                return Perihelion$Core$top_up($t28450);
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
                  } else {
                    return g0;
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
      }
    }
  }
}
const Perihelion$Core$update$clo = { _0: ($_, game, taps, keys, cursor, view_w, view_h, dt_s) => Perihelion$Core$update(game, taps, keys, cursor, view_w, view_h, dt_s) };

function Perihelion$Core$step_playing(game, tapped, keys, cursor, dt_s) {
  {
    const g0 = (() => {
      {
        const $t28452 = game.mode;
        switch ($t28452.$) {
          case "Orbiting": {
            const $f28453 = $t28452._0;
            const $f28454 = $t28452._1;
            const $f28455 = $t28452._2;
            {
              const angle = (() => {
                return $f28455;
              })();
              {
                const ring = (() => {
                  return $f28454;
                })();
                {
                  const idx = (() => {
                    return $f28453;
                  })();
                  return Perihelion$Core$step_orbit(game, idx, ring, angle, tapped, keys, dt_s);
                }
              }
            }
            break;
          }
          case "Flying": {
            const $f28464 = $t28452._0;
            const $f28465 = $t28452._1;
            {
              const vy = (() => {
                return $f28465;
              })();
              {
                const vx = (() => {
                  return $f28464;
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
      const n = (() => {
        {
          const $t28470 = g0.owned_weapons;
          {
            const go_i3881 = { $: "$Clo_go$4796", _0: go$apply$4796 };
            return go$apply$4796(go_i3881, $t28470, 0);
          }
        }
      })();
      {
        const g1a = (() => {
          {
            const $t28472 = (() => {
              {
                const $t28471 = g0.active_weapon_idx;
                return Perihelion$Core$adjust_weapon($t28471, keys, n);
              }
            })();
            return ({ ...g0, active_weapon_idx: $t28472 });
          }
        })();
        {
          const g1 = (() => {
            {
              const $t28474 = (() => {
                {
                  const $t28473 = g1a.starkiller_target_offset;
                  return Perihelion$Core$adjust_starkiller_target($t28473, keys);
                }
              })();
              return ({ ...g1a, starkiller_target_offset: $t28474 });
            }
          })();
          {
            const g1x = (() => {
              return Perihelion$Core$apply_special(g1, keys);
            })();
            {
              const $t28475 = g1x.phase;
              switch ($t28475.$) {
                case "Playing": {
                  {
                    const g2 = (() => {
                      {
                        const g1_i3878 = Perihelion$Combat$step_spawn(g1x, dt_s);
                        {
                          const g2_i3879 = Perihelion$Combat$step_entities(g1_i3878, dt_s);
                          return Perihelion$Combat$step_ships(g2_i3879, dt_s);
                        }
                      }
                    })();
                    {
                      const g3 = Perihelion$Combat$fire(g2, keys, cursor, dt_s);
                      {
                        const g4 = (() => {
                          {
                            const g0_i3872 = Perihelion$Combat$collide_shots_stars(g3);
                            {
                              const g1_i3873 = Perihelion$Combat$collide_shots_asteroids(g0_i3872);
                              {
                                const g2_i3874 = Perihelion$Combat$collide_shots_ships(g1_i3873);
                                {
                                  const g3_i3875 = Perihelion$Combat$collide_ball_pickups(g2_i3874);
                                  return Perihelion$Combat$collide_ball_hazards(g3_i3875);
                                }
                              }
                            }
                          }
                        })();
                        {
                          const $t28476 = (() => {
                            return g4.phase;
                          })();
                          switch ($t28476.$) {
                            case "Playing": {
                              {
                                const $t28477 = (() => {
                                  {
                                    const $rc_823 = Perihelion$Core$step_camera(g4, dt_s);
                                    return $rc_823;
                                  }
                                })();
                                return Perihelion$Core$top_up($t28477);
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
                  return g1x;
                }
              }
            }
          }
        }
      }
    }
  }
}
const Perihelion$Core$step_playing$clo = { _0: ($_, game, tapped, keys, cursor, dt_s) => Perihelion$Core$step_playing(game, tapped, keys, cursor, dt_s) };

function Perihelion$Core$step_orbit(game, idx, ring, angle, tapped, keys, dt_s) {
  {
    const $t28478 = Perihelion$Core$star_at(game, idx);
    switch ($t28478.$) {
      case "None": {
        return game;
        break;
      }
      case "Some": {
        const $f28501 = $t28478._0;
        {
          const s = $f28501;
          if (tapped === true) {
            return (() => {
              {
                const vx_i10079 = (() => {
                  {
                    const $t28505_i10078 = (() => {
                      {
                        const $t28503_i10076 = (1. * 340.);
                        {
                          const $t28504_i10077 = Math.sin(angle);
                          return ($t28503_i10076 * $t28504_i10077);
                        }
                      }
                    })();
                    return (0. - $t28505_i10078);
                  }
                })();
                {
                  const vy_i10082 = (() => {
                    {
                      const $t28507_i10080 = (1. * 340.);
                      {
                        const $t28508_i10081 = Math.cos(angle);
                        return ($t28507_i10080 * $t28508_i10081);
                      }
                    }
                  })();
                  {
                    const $t28509_i10083 = { $: "Flying", _0: vx_i10079, _1: vy_i10082 };
                    return ({ ...game, mode: $t28509_i10083 });
                  }
                }
              }
            })();
          } else {
            return (() => {
              {
                const ring2 = (() => {
                  {
                    const $t28479 = Perihelion$Core$ring_count(s);
                    return Perihelion$Core$adjust_ring(ring, keys, $t28479);
                  }
                })();
                {
                  const o = Perihelion$Core$ring_at(s, ring2);
                  {
                    const a2 = (() => {
                      {
                        const $t28485 = (() => {
                          {
                            const $t28484 = (() => {
                              {
                                const $t28482 = (1. * 1.8);
                                {
                                  const $t28483 = o.speed_mult;
                                  return ($t28482 * $t28483);
                                }
                              }
                            })();
                            return ($t28484 * dt_s);
                          }
                        })();
                        return (angle + $t28485);
                      }
                    })();
                    {
                      const r = o.radius;
                      {
                        const $t28486 = { $: "Orbiting", _0: idx, _1: ring2, _2: a2 };
                        {
                          const $t28492 = (() => {
                            {
                              const $t28487 = game.loop_angle;
                              {
                                const $t28491 = (() => {
                                  {
                                    const $t28490 = (() => {
                                      {
                                        const $t28489 = o.speed_mult;
                                        return (1.8 * $t28489);
                                      }
                                    })();
                                    return ($t28490 * dt_s);
                                  }
                                })();
                                return ($t28487 + $t28491);
                              }
                            }
                          })();
                          {
                            const $t28496 = (() => {
                              {
                                const $t28493 = s.x;
                                {
                                  const $t28495 = (() => {
                                    {
                                      const $t28494 = Math.cos(a2);
                                      return ($t28494 * r);
                                    }
                                  })();
                                  return ($t28493 + $t28495);
                                }
                              }
                            })();
                            {
                              const $t28500 = (() => {
                                {
                                  const $t28497 = s.y;
                                  {
                                    const $t28499 = (() => {
                                      {
                                        const $t28498 = Math.sin(a2);
                                        return ($t28498 * r);
                                      }
                                    })();
                                    return ($t28497 + $t28499);
                                  }
                                }
                              })();
                              return ({ ...game, mode: $t28486, loop_angle: $t28492, ball_x: $t28496, ball_y: $t28500 });
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
        const $t28512 = (() => {
          {
            const $t28510 = (vx * vx);
            {
              const $t28511 = (vy * vy);
              return ($t28510 + $t28511);
            }
          }
        })();
        return Math.sqrt($t28512);
      }
    })();
    {
      const $t28513 = (m > 0.);
      if ($t28513 === true) {
        return (() => {
          {
            const out = (() => {
              {
                const $t28516 = (() => {
                  {
                    const $t28514 = (vx / m);
                    return ($t28514 * 340.);
                  }
                })();
                {
                  const $t28519 = (() => {
                    {
                      const $t28517 = (vy / m);
                      return ($t28517 * 340.);
                    }
                  })();
                  return { _0: $t28516, _1: $t28519 };
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
      const $f28538 = stars._0;
      const $f28539 = stars._1;
      {
        const rest = $f28539;
        {
          const s = $f28538;
          {
            const dx = (() => {
              {
                const $t28520 = s.x;
                {
                  const $t28521 = game.ball_x;
                  return ($t28520 - $t28521);
                }
              }
            })();
            {
              const dy = (() => {
                {
                  const $t28522 = s.y;
                  {
                    const $t28523 = game.ball_y;
                    return ($t28522 - $t28523);
                  }
                }
              })();
              {
                const d = (() => {
                  {
                    const $t28526 = (() => {
                      {
                        const $t28524 = (dx * dx);
                        {
                          const $t28525 = (dy * dy);
                          return ($t28524 + $t28525);
                        }
                      }
                    })();
                    return Math.sqrt($t28526);
                  }
                })();
                {
                  const approaching = (() => {
                    {
                      const $t28529 = (() => {
                        {
                          const $t28527 = (vx * dx);
                          {
                            const $t28528 = (vy * dy);
                            return ($t28527 + $t28528);
                          }
                        }
                      })();
                      return ($t28529 > 0.);
                    }
                  })();
                  {
                    const $t28536 = (() => {
                      {
                        const $t28534 = (() => {
                          {
                            const $t28533 = (() => {
                              {
                                const $t28532 = (() => {
                                  {
                                    const $t28531 = s.capture_radius;
                                    return (2.4 * $t28531);
                                  }
                                })();
                                return (d < $t28532);
                              }
                            })();
                            return (approaching && $t28533);
                          }
                        })();
                        {
                          const $t28535 = (d < best_d);
                          return ($t28534 && $t28535);
                        }
                      }
                    })();
                    if ($t28536 === true) {
                      return (() => {
                        {
                          const $t28537 = { $: "Some", _0: s };
                          return Perihelion$Core$nearest_assist_target(game, vx, vy, rest, $t28537, d);
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
    const $t28546 = (() => {
      {
        const $t28544 = game.stars;
        {
          const $t28545 = { $: "None" };
          return Perihelion$Core$nearest_assist_target(game, vx, vy, $t28544, $t28545, 999999.);
        }
      }
    })();
    switch ($t28546.$) {
      case "None": {
        {
          const out = { _0: vx, _1: vy };
          return out;
        }
        break;
      }
      case "Some": {
        const $f28565 = $t28546._0;
        {
          const t = $f28565;
          {
            const dx = (() => {
              {
                const $t28547 = t.x;
                {
                  const $t28548 = game.ball_x;
                  return ($t28547 - $t28548);
                }
              }
            })();
            {
              const dy = (() => {
                {
                  const $t28549 = t.y;
                  {
                    const $t28550 = game.ball_y;
                    return ($t28549 - $t28550);
                  }
                }
              })();
              {
                const dist = (() => {
                  {
                    const $t28553 = (() => {
                      {
                        const $t28551 = (dx * dx);
                        {
                          const $t28552 = (dy * dy);
                          return ($t28551 + $t28552);
                        }
                      }
                    })();
                    return Math.sqrt($t28553);
                  }
                })();
                {
                  const $t28554 = (dist > 0.);
                  if ($t28554 === true) {
                    return (() => {
                      {
                        const $t28559 = (() => {
                          {
                            const $t28558 = (() => {
                              {
                                const $t28557 = (() => {
                                  {
                                    const $t28555 = (dx / dist);
                                    return ($t28555 * 1600.);
                                  }
                                })();
                                return ($t28557 * dt_s);
                              }
                            })();
                            return (vx + $t28558);
                          }
                        })();
                        {
                          const $t28564 = (() => {
                            {
                              const $t28563 = (() => {
                                {
                                  const $t28562 = (() => {
                                    {
                                      const $t28560 = (dy / dist);
                                      return ($t28560 * 1600.);
                                    }
                                  })();
                                  return ($t28562 * dt_s);
                                }
                              })();
                              return (vy + $t28563);
                            }
                          })();
                          return Perihelion$Core$renormalize($t28559, $t28564);
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

function Perihelion$Core$predict_trajectory_go(game, x, y, vx, vy, n, acc) {
  {
    const $t28566 = (n === 0);
    if ($t28566 === true) {
      return (() => {
        {
          const go_i3896 = { $: "$Clo_go$4307", _0: go$apply$4307 };
          {
            const $t253_i3897 = { $: "Nil" };
            return go$apply$4307(go_i3896, acc, $t253_i3897);
          }
        }
      })();
    } else {
      return (() => {
        {
          const simmed = ({ ...game, ball_x: x, ball_y: y });
          {
            const $p28575 = Perihelion$Core$assisted_velocity(simmed, vx, vy, 0.05);
            {
              const vx2 = $p28575._0;
              {
                const vy2 = $p28575._1;
                {
                  const x2 = (() => {
                    {
                      const $t28569 = (vx2 * 0.05);
                      return (x + $t28569);
                    }
                  })();
                  {
                    const y2 = (() => {
                      {
                        const $t28571 = (vy2 * 0.05);
                        return (y + $t28571);
                      }
                    })();
                    {
                      const $t28572 = (n - 1);
                      {
                        const $t28573 = { _0: x2, _1: y2 };
                        {
                          const $t28574 = { $: "Cons", _0: $t28573, _1: acc };
                          return Perihelion$Core$predict_trajectory_go(game, x2, y2, vx2, vy2, $t28572, $t28574);
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
const Perihelion$Core$predict_trajectory_go$clo = { _0: ($_, game, x, y, vx, vy, n, acc) => Perihelion$Core$predict_trajectory_go(game, x, y, vx, vy, n, acc) };

function Perihelion$Core$predict_trajectory(game, idx, ring, angle) {
  {
    const $t28576 = Perihelion$Core$star_at(game, idx);
    switch ($t28576.$) {
      case "None": {
        return { $: "Nil" };
        break;
      }
      case "Some": {
        const $f28606 = $t28576._0;
        {
          const s = $f28606;
          {
            const o = Perihelion$Core$ring_at(s, ring);
            {
              const start_x = (() => {
                {
                  const $t28577 = s.x;
                  {
                    const $t28580 = (() => {
                      {
                        const $t28578 = Math.cos(angle);
                        {
                          const $t28579 = o.radius;
                          return ($t28578 * $t28579);
                        }
                      }
                    })();
                    return ($t28577 + $t28580);
                  }
                }
              })();
              {
                const start_y = (() => {
                  {
                    const $t28581 = s.y;
                    {
                      const $t28584 = (() => {
                        {
                          const $t28582 = Math.sin(angle);
                          {
                            const $t28583 = o.radius;
                            return ($t28582 * $t28583);
                          }
                        }
                      })();
                      return ($t28581 + $t28584);
                    }
                  }
                })();
                {
                  const $t28586 = (() => {
                    {
                      const $t28585 = (() => {
                        {
                          const vx_i10091 = (() => {
                            {
                              const $t28505_i10090 = (() => {
                                {
                                  const $t28503_i10088 = (1. * 340.);
                                  {
                                    const $t28504_i10089 = Math.sin(angle);
                                    return ($t28503_i10088 * $t28504_i10089);
                                  }
                                }
                              })();
                              return (0. - $t28505_i10090);
                            }
                          })();
                          {
                            const vy_i10094 = (() => {
                              {
                                const $t28507_i10092 = (1. * 340.);
                                {
                                  const $t28508_i10093 = Math.cos(angle);
                                  return ($t28507_i10092 * $t28508_i10093);
                                }
                              }
                            })();
                            {
                              const $t28509_i10095 = { $: "Flying", _0: vx_i10091, _1: vy_i10094 };
                              return ({ ...game, mode: $t28509_i10095 });
                            }
                          }
                        }
                      })();
                      return $t28585.mode;
                    }
                  })();
                  switch ($t28586.$) {
                    case "Flying": {
                      const $f28589 = $t28586._0;
                      const $f28590 = $t28586._1;
                      {
                        const vy0 = $f28590;
                        {
                          const vx0 = $f28589;
                          {
                            const $t28588 = { $: "Nil" };
                            return Perihelion$Core$predict_trajectory_go(game, start_x, start_y, vx0, vy0, 24, $t28588);
                          }
                        }
                      }
                      break;
                    }
                    case "Orbiting": {
                      const $f28595 = $t28586._0;
                      const $f28596 = $t28586._1;
                      const $f28597 = $t28586._2;
                      return { $: "Nil" };
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
const Perihelion$Core$predict_trajectory$clo = { _0: ($_, game, idx, ring, angle) => Perihelion$Core$predict_trajectory(game, idx, ring, angle) };

function Perihelion$Core$find_capture(game, vx, vy, stars, i) {
  switch (stars.$) {
    case "Nil": {
      return { $: "None" };
      break;
    }
    case "Cons": {
      const $f28627 = stars._0;
      const $f28628 = stars._1;
      {
        const rest = $f28628;
        {
          const s = $f28627;
          {
            const dx = (() => {
              {
                const $t28607 = s.x;
                {
                  const $t28608 = game.ball_x;
                  return ($t28607 - $t28608);
                }
              }
            })();
            {
              const dy = (() => {
                {
                  const $t28609 = s.y;
                  {
                    const $t28610 = game.ball_y;
                    return ($t28609 - $t28610);
                  }
                }
              })();
              {
                const grace = (() => {
                  {
                    const $t28611 = s.capture_radius;
                    return ($t28611 + 6.);
                  }
                })();
                {
                  const approaching = (() => {
                    {
                      const $t28615 = (() => {
                        {
                          const $t28613 = (vx * dx);
                          {
                            const $t28614 = (vy * dy);
                            return ($t28613 + $t28614);
                          }
                        }
                      })();
                      return ($t28615 > 0.);
                    }
                  })();
                  {
                    const $t28624 = (() => {
                      {
                        const $t28618 = (() => {
                          {
                            const $t28617 = (() => {
                              {
                                const $t28616 = game.current;
                                return (i !== $t28616);
                              }
                            })();
                            return ($t28617 && approaching);
                          }
                        })();
                        {
                          const $t28623 = (() => {
                            {
                              const $t28622 = (() => {
                                {
                                  const $t28621 = (() => {
                                    {
                                      const $t28619 = (dx * dx);
                                      {
                                        const $t28620 = (dy * dy);
                                        return ($t28619 + $t28620);
                                      }
                                    }
                                  })();
                                  return Math.sqrt($t28621);
                                }
                              })();
                              return ($t28622 <= grace);
                            }
                          })();
                          return ($t28618 && $t28623);
                        }
                      }
                    })();
                    if ($t28624 === true) {
                      return (() => {
                        {
                          const $t28625 = { _0: i, _1: s };
                          return { $: "Some", _0: $t28625 };
                        }
                      })();
                    } else {
                      return (() => {
                        {
                          const $t28626 = (i + 1);
                          return Perihelion$Core$find_capture(game, vx, vy, rest, $t28626);
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
    const $p28649 = Perihelion$Core$assisted_velocity(game, vx, vy, dt_s);
    {
      const vx2 = $p28649._0;
      {
        const vy2 = $p28649._1;
        {
          const g = (() => {
            {
              const $t28635 = (() => {
                {
                  const $t28633 = game.ball_x;
                  {
                    const $t28634 = (vx2 * dt_s);
                    return ($t28633 + $t28634);
                  }
                }
              })();
              {
                const $t28638 = (() => {
                  {
                    const $t28636 = game.ball_y;
                    {
                      const $t28637 = (vy2 * dt_s);
                      return ($t28636 + $t28637);
                    }
                  }
                })();
                {
                  const $t28639 = { $: "Flying", _0: vx2, _1: vy2 };
                  return ({ ...game, ball_x: $t28635, ball_y: $t28638, mode: $t28639 });
                }
              }
            }
          })();
          {
            const $t28641 = (() => {
              {
                const $t28640 = g.stars;
                return Perihelion$Core$find_capture(g, vx2, vy2, $t28640, 0);
              }
            })();
            switch ($t28641.$) {
              case "None": {
                return Perihelion$Core$check_death(g);
                break;
              }
              case "Some": {
                const $f28642 = $t28641._0;
                const $f28643 = $f28642._0;
                const $f28644 = $f28642._1;
                {
                  const t = $f28644;
                  {
                    const idx = $f28643;
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
        const $t28652 = (() => {
          {
            const $t28650 = game.ball_y;
            {
              const $t28651 = captured.y;
              return ($t28650 - $t28651);
            }
          }
        })();
        {
          const $t28655 = (() => {
            {
              const $t28653 = game.ball_x;
              {
                const $t28654 = captured.x;
                return ($t28653 - $t28654);
              }
            }
          })();
          return Math.atan2($t28652, $t28655);
        }
      }
    })();
    {
      const snapped = (() => {
        {
          const $t28657 = (() => {
            {
              const $t28656 = (() => {
                {
                  const $t28306_i3912 = Perihelion$Core$ring_count(captured);
                  return ($t28306_i3912 - 1);
                }
              })();
              return { $: "Orbiting", _0: idx, _1: $t28656, _2: angle };
            }
          })();
          {
            const $t28662 = (() => {
              {
                const $t28658 = captured.x;
                {
                  const $t28661 = (() => {
                    {
                      const $t28659 = Math.cos(angle);
                      {
                        const $t28660 = captured.capture_radius;
                        return ($t28659 * $t28660);
                      }
                    }
                  })();
                  return ($t28658 + $t28661);
                }
              }
            })();
            {
              const $t28667 = (() => {
                {
                  const $t28663 = captured.y;
                  {
                    const $t28666 = (() => {
                      {
                        const $t28664 = Math.sin(angle);
                        {
                          const $t28665 = captured.capture_radius;
                          return ($t28664 * $t28665);
                        }
                      }
                    })();
                    return ($t28663 + $t28666);
                  }
                }
              })();
              return ({ ...game, mode: $t28657, loop_angle: 0., ball_x: $t28662, ball_y: $t28667 });
            }
          }
        }
      })();
      {
        const $t28669 = (() => {
          {
            const $t28668 = game.current;
            return (idx > $t28668);
          }
        })();
        if ($t28669 === true) {
          return (() => {
            {
              const new_mult = (() => {
                {
                  const $t28672 = (() => {
                    {
                      const $t28670 = game.loop_angle;
                      return ($t28670 < 6.28318530718);
                    }
                  })();
                  if ($t28672 === true) {
                    return (() => {
                      {
                        const $t28676 = (() => {
                          {
                            const $t28674 = (() => {
                              {
                                const $t28673 = game.multiplier;
                                return ($t28673 + 1);
                              }
                            })();
                            return ($t28674 > 5);
                          }
                        })();
                        if ($t28676 === true) {
                          return 5;
                        } else {
                          return (() => {
                            {
                              const $t28677 = game.multiplier;
                              return ($t28677 + 1);
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
                const new_chained = (() => {
                  {
                    const $t28678 = game.stars_chained;
                    return ($t28678 + 1);
                  }
                })();
                {
                  const captured_game = (() => {
                    {
                      const $t28680 = (() => {
                        {
                          const $t28679 = game.score;
                          return ($t28679 + new_mult);
                        }
                      })();
                      {
                        const $t28682 = (() => {
                          {
                            const $t28681 = game.max_mult;
                            {
                              const $t28752_i3908 = ($t28681 > new_mult);
                              if ($t28752_i3908 === true) {
                                return $t28681;
                              } else {
                                return new_mult;
                              }
                            }
                          }
                        })();
                        {
                          const $t28686 = (() => {
                            {
                              const $t28685 = (() => {
                                {
                                  const $t28683 = captured.x;
                                  {
                                    const $t28684 = captured.y;
                                    return { _0: $t28683, _1: $t28684 };
                                  }
                                }
                              })();
                              return { $: "Some", _0: $t28685 };
                            }
                          })();
                          return ({ ...snapped, current: idx, score: $t28680, stars_chained: new_chained, multiplier: new_mult, max_mult: $t28682, capture_flash: $t28686 });
                        }
                      }
                    }
                  })();
                  {
                    const $t28687 = Perihelion$Upgrades$is_milestone(new_chained);
                    if ($t28687 === true) {
                      return (() => {
                        {
                          const $p28693 = (() => {
                            {
                              const $t28688 = captured_game.rng;
                              {
                                const $t28689 = captured_game.owned_weapons;
                                {
                                  const $t28690 = captured_game.special;
                                  return Perihelion$Upgrades$draw_choices($t28688, $t28689, $t28690);
                                }
                              }
                            }
                          })();
                          {
                            const rng2 = $p28693._0;
                            {
                              const choices = $p28693._1;
                              {
                                const $t28692 = (() => {
                                  {
                                    const $t28691 = { $: "Milestone" };
                                    return ({ ...captured_game, phase: $t28691, rng: rng2, milestone_choices: choices });
                                  }
                                })();
                                return Perihelion$Core$top_up($t28692);
                              }
                            }
                          }
                        }
                      })();
                    } else {
                      return Perihelion$Core$top_up(captured_game);
                    }
                  }
                }
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

function Perihelion$Core$pick_milestone(game, choice_idx) {
  {
    const g0 = (() => {
      {
        const $t28694 = { $: "Nil" };
        {
          const $t28695 = { $: "None" };
          return ({ ...game, fx_bursts: $t28694, capture_flash: $t28695 });
        }
      }
    })();
    switch (choice_idx.$) {
      case "None": {
        return g0;
        break;
      }
      case "Some": {
        const $f28703 = choice_idx._0;
        {
          const i = $f28703;
          {
            const $t28697 = (() => {
              {
                const $t28696 = g0.milestone_choices;
                return List$nth_opt$List_UpgradeKind$Int($t28696, i);
              }
            })();
            switch ($t28697.$) {
              case "None": {
                return g0;
                break;
              }
              case "Some": {
                const $f28702 = $t28697._0;
                {
                  const choice = $f28702;
                  {
                    const $t28701 = (() => {
                      {
                        const $t28698 = Perihelion$Core$apply_upgrade(g0, choice);
                        {
                          const $t28699 = { $: "Playing" };
                          {
                            const $t28700 = { $: "Nil" };
                            return ({ ...$t28698, phase: $t28699, milestone_choices: $t28700 });
                          }
                        }
                      }
                    })();
                    return Perihelion$Core$top_up($t28701);
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
const Perihelion$Core$pick_milestone$clo = { _0: ($_, game, choice_idx) => Perihelion$Core$pick_milestone(game, choice_idx) };

function Perihelion$Core$apply_upgrade(game, u) {
  switch (u.$) {
    case "OffenseWeapon": {
      const $f28716 = u._0;
      {
        const k = $f28716;
        {
          const $t28705 = (() => {
            {
              const $t28704 = game.owned_weapons;
              {
                const $t669_i3920 = { $: "$Clo_$lam668$4780", _0: $lam668$apply$4780, _1: k };
                return List$any$List_WeaponKind$Fn_WeaponKind_Bool($t28704, $t669_i3920);
              }
            }
          })();
          if ($t28705 === true) {
            return game;
          } else {
            return (() => {
              {
                const $t28706 = game.owned_weapons;
                {
                  const $t28707 = { $: "Nil" };
                  {
                    const $t28708 = { $: "Cons", _0: k, _1: $t28707 };
                    {
                      const $t28709 = (() => {
                        {
                          const go_i10098 = { $: "$Clo_go$4799", _0: go$apply$4799 };
                          {
                            const $t261_i10101 = (() => {
                              {
                                const go_i4496_i10099 = { $: "$Clo_go$5247", _0: go$apply$5247 };
                                {
                                  const $t253_i4497_i10100 = { $: "Nil" };
                                  return go$apply$5247(go_i4496_i10099, $t28706, $t253_i4497_i10100);
                                }
                              }
                            })();
                            return go$apply$4799(go_i10098, $t261_i10101, $t28708);
                          }
                        }
                      })();
                      return ({ ...game, owned_weapons: $t28709 });
                    }
                  }
                }
              }
            })();
          }
        }
      }
      break;
    }
    case "OffenseFireRate": {
      {
        const $t28711 = (() => {
          {
            const $t28710 = game.fire_rate_stacks;
            return ($t28710 + 1);
          }
        })();
        return ({ ...game, fire_rate_stacks: $t28711 });
      }
      break;
    }
    case "DefenseBulletWard": {
      return ({ ...game, bullet_ward: true });
      break;
    }
    case "DefenseDeflector": {
      return ({ ...game, deflector_plating: true });
      break;
    }
    case "DefenseShield": {
      {
        const $t28713 = (() => {
          {
            const $t28712 = game.shield;
            return ($t28712 + 1);
          }
        })();
        return ({ ...game, shield: $t28713, shield_reinforced: true });
      }
      break;
    }
    case "SpecialItem": {
      const $f28717 = u._0;
      {
        const k = $f28717;
        {
          const $t28714 = (() => {
            return { $: "Some", _0: k };
          })();
          {
            const $t28715 = (() => {
              {
                let $rc_824;
                switch (k.$) {
                  case "StarThrust": {
                    $rc_824 = 3;
                    break;
                  }
                  case "StarJump": {
                    $rc_824 = 1;
                    break;
                  }
                  case "TrajectoryPreview": {
                    $rc_824 = 0;
                    break;
                  }
                  default: {
                    $rc_824 = (() => { throw new Error("non-exhaustive pattern match"); })();
                    break;
                  }
                }
                return $rc_824;
              }
            })();
            return ({ ...game, special: $t28714, special_charges: $t28715 });
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
const Perihelion$Core$apply_upgrade$clo = { _0: ($_, game, u) => Perihelion$Core$apply_upgrade(game, u) };

function Perihelion$Core$top_up(game) {
  {
    const fallback = (() => {
      {
        const $t28719 = (() => {
          {
            const $t28718 = game.view_w;
            return ($t28718 / 2.);
          }
        })();
        {
          const $t28720 = ({ radius: 54., speed_mult: 1. });
          {
            const $t28721 = { $: "Nil" };
            {
              const $t28722 = { $: "Cons", _0: $t28720, _1: $t28721 };
              return ({ x: $t28719, y: 520., radius: 18., capture_radius: 54., speed_mult: 1., orbits: $t28722 });
            }
          }
        }
      }
    })();
    {
      const top = (() => {
        {
          const $t28723 = game.stars;
          return Perihelion$Core$top_star($t28723, fallback);
        }
      })();
      {
        const $t28730 = (() => {
          {
            const $t28724 = top.y;
            {
              const $t28729 = (() => {
                {
                  const $t28725 = game.camera_y;
                  {
                    const $t28728 = (() => {
                      {
                        const $t28726 = game.view_h;
                        return ($t28726 * 1.5);
                      }
                    })();
                    return ($t28725 - $t28728);
                  }
                }
              })();
              return ($t28724 > $t28729);
            }
          }
        })();
        if ($t28730 === true) {
          return (() => {
            {
              const $p28741 = (() => {
                {
                  const $t28731 = game.rng;
                  {
                    const $t28732 = game.view_w;
                    return Perihelion$Level$next_star($t28731, top, $t28732);
                  }
                }
              })();
              {
                const fresh = $p28741._0;
                {
                  const rng2 = $p28741._1;
                  {
                    const g2 = (() => {
                      {
                        const $t28733 = game.stars;
                        {
                          const $t28734 = { $: "Nil" };
                          {
                            const $t28735 = { $: "Cons", _0: fresh, _1: $t28734 };
                            {
                              const $t28736 = (() => {
                                {
                                  const go_i10105 = { $: "$Clo_go$4787", _0: go$apply$4787 };
                                  {
                                    const $t261_i10108 = (() => {
                                      {
                                        const go_i4489_i10106 = { $: "$Clo_go$5245", _0: go$apply$5245 };
                                        {
                                          const $t253_i4490_i10107 = { $: "Nil" };
                                          return go$apply$5245(go_i4489_i10106, $t28733, $t253_i4490_i10107);
                                        }
                                      }
                                    })();
                                    return go$apply$4787(go_i10105, $t261_i10108, $t28735);
                                  }
                                }
                              })();
                              return ({ ...game, stars: $t28736, rng: rng2 });
                            }
                          }
                        }
                      }
                    })();
                    {
                      const $t28740 = (() => {
                        {
                          const $t28739 = (() => {
                            {
                              const $t28738 = (() => {
                                {
                                  const $t28737 = g2.stars;
                                  {
                                    const go_i3923 = { $: "$Clo_go$4747", _0: go$apply$4747 };
                                    return go$apply$4747(go_i3923, $t28737, 0);
                                  }
                                }
                              })();
                              return ($t28738 - 1);
                            }
                          })();
                          return Perihelion$Combat$maybe_spawn_ship(g2, $t28739);
                        }
                      })();
                      return Perihelion$Core$top_up($t28740);
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
      const $f28742 = stars._0;
      const $f28743 = stars._1;
      {
        const $jp_clo28749 = (() => {
          return { $: "$Clo_$jp28748$3750", _0: $jp28748$apply$3750, _1: $f28743, _2: fallback };
        })();
        switch ($f28743.$) {
          case "Nil": {
            {
              const s = $f28742;
              return s;
            }
            break;
          }
          default: {
            return $jp28748$apply$3750($jp_clo28749);
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
        const $t28753 = game.score;
        {
          const $t28754 = game.stars_chained;
          {
            const $t28755 = game.max_mult;
            return ({ score: $t28753, stars: $t28754, max_mult: $t28755 });
          }
        }
      }
    })();
    {
      const $t28756 = { $: "Over" };
      {
        const $t28759 = (() => {
          {
            const $t28757 = game.best;
            {
              const $t28758 = game.score;
              {
                const $t28752_i3931 = ($t28757 > $t28758);
                if ($t28752_i3931 === true) {
                  return $t28757;
                } else {
                  return $t28758;
                }
              }
            }
          }
        })();
        {
          const $t28760 = game.runs;
          {
            const $t28761 = (() => {
              return { $: "Cons", _0: rec, _1: $t28760 };
            })();
            {
              const $t28762 = (() => {
                {
                  const go_i3927 = { $: "$Clo_go$4801", _0: go$apply$4801 };
                  {
                    const $t508_i3928 = { $: "Nil" };
                    return go$apply$4801(go_i3927, $t28761, 10, $t508_i3928);
                  }
                }
              })();
              return ({ ...game, phase: $t28756, best: $t28759, runs: $t28762 });
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
        const $t28763 = game.ball_y;
        {
          const $t28768 = (() => {
            {
              const $t28766 = (() => {
                {
                  const $t28764 = game.camera_y;
                  {
                    const $t28765 = game.view_h;
                    return ($t28764 + $t28765);
                  }
                }
              })();
              return ($t28766 + 40.);
            }
          })();
          return ($t28763 > $t28768);
        }
      }
    })();
    {
      const off_side = (() => {
        {
          const $t28772 = (() => {
            {
              const $t28769 = game.ball_x;
              {
                const $t28771 = (0. - 40.);
                return ($t28769 < $t28771);
              }
            }
          })();
          {
            const $t28777 = (() => {
              {
                const $t28773 = game.ball_x;
                {
                  const $t28776 = (() => {
                    {
                      const $t28774 = game.view_w;
                      return ($t28774 + 40.);
                    }
                  })();
                  return ($t28773 > $t28776);
                }
              }
            })();
            return ($t28772 || $t28777);
          }
        }
      })();
      {
        const fallback = (() => {
          {
            const $t28779 = (() => {
              {
                const $t28778 = game.view_w;
                return ($t28778 / 2.);
              }
            })();
            {
              const $t28780 = ({ radius: 54., speed_mult: 1. });
              {
                const $t28781 = { $: "Nil" };
                {
                  const $t28782 = { $: "Cons", _0: $t28780, _1: $t28781 };
                  return ({ x: $t28779, y: 520., radius: 18., capture_radius: 54., speed_mult: 1., orbits: $t28782 });
                }
              }
            }
          }
        })();
        {
          const topmost = (() => {
            {
              const $t28783 = game.stars;
              return Perihelion$Core$top_star($t28783, fallback);
            }
          })();
          {
            const overshot = (() => {
              {
                const $t28784 = game.ball_y;
                {
                  const $t28787 = (() => {
                    {
                      const $t28785 = topmost.y;
                      return ($t28785 - 150.);
                    }
                  })();
                  return ($t28784 < $t28787);
                }
              }
            })();
            {
              const fallen = (() => {
                {
                  const $t28788 = Perihelion$Core$star_at(game, 0);
                  switch ($t28788.$) {
                    case "None": {
                      return false;
                      break;
                    }
                    case "Some": {
                      const $f28793 = $t28788._0;
                      {
                        const c = $f28793;
                        {
                          const $t28789 = game.ball_y;
                          {
                            const $t28792 = (() => {
                              {
                                const $t28790 = c.y;
                                return ($t28790 + 200.);
                              }
                            })();
                            return ($t28789 > $t28792);
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
                const $t28796 = (() => {
                  {
                    const $t28795 = (() => {
                      {
                        const $t28794 = (below || off_side);
                        return ($t28794 || overshot);
                      }
                    })();
                    return ($t28795 || fallen);
                  }
                })();
                if ($t28796 === true) {
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
        const $t28797 = game.mode;
        switch ($t28797.$) {
          case "Flying": {
            const $f28804 = $t28797._0;
            const $f28805 = $t28797._1;
            (() => {
              return $f28804;
            })();
            return game.ball_x;
            break;
          }
          case "Orbiting": {
            const $f28810 = $t28797._0;
            const $f28811 = $t28797._1;
            const $f28812 = $t28797._2;
            {
              const $t28799 = (() => {
                {
                  const $t28798 = game.current;
                  return Perihelion$Core$star_at(game, $t28798);
                }
              })();
              switch ($t28799.$) {
                case "None": {
                  {
                    const $t28800 = game.camera_x;
                    {
                      const $t28802 = (() => {
                        {
                          const $t28801 = game.view_w;
                          return ($t28801 / 2.);
                        }
                      })();
                      return ($t28800 + $t28802);
                    }
                  }
                  break;
                }
                case "Some": {
                  const $f28803 = $t28799._0;
                  {
                    const s = $f28803;
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
          const $t28821 = game.mode;
          switch ($t28821.$) {
            case "Flying": {
              const $f28833 = $t28821._0;
              const $f28834 = $t28821._1;
              {
                const $t28822 = game.ball_y;
                {
                  const $t28825 = (() => {
                    {
                      const $t28824 = game.view_h;
                      return (0.6 * $t28824);
                    }
                  })();
                  return ($t28822 - $t28825);
                }
              }
              break;
            }
            case "Orbiting": {
              const $f28839 = $t28821._0;
              const $f28840 = $t28821._1;
              const $f28841 = $t28821._2;
              {
                const $t28827 = (() => {
                  {
                    const $t28826 = game.current;
                    return Perihelion$Core$star_at(game, $t28826);
                  }
                })();
                switch ($t28827.$) {
                  case "None": {
                    return game.camera_y;
                    break;
                  }
                  case "Some": {
                    const $f28832 = $t28827._0;
                    {
                      const s = $f28832;
                      {
                        const $t28828 = s.y;
                        {
                          const $t28831 = (() => {
                            {
                              const $t28830 = game.view_h;
                              return (0.6 * $t28830);
                            }
                          })();
                          return ($t28828 - $t28831);
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
            const $t28850 = game.view_w;
            return ($t28850 * 0.25);
          }
        })();
        {
          const right_edge = (() => {
            {
              const $t28852 = game.view_w;
              {
                const $t28854 = (1. - 0.25);
                return ($t28852 * $t28854);
              }
            }
          })();
          {
            const screen_x = (() => {
              {
                const $t28855 = game.camera_x;
                return (focus_x - $t28855);
              }
            })();
            {
              const target_x = (() => {
                {
                  const $t28856 = (screen_x < left_edge);
                  if ($t28856 === true) {
                    return (focus_x - left_edge);
                  } else {
                    return (() => {
                      {
                        const $t28857 = (screen_x > right_edge);
                        if ($t28857 === true) {
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
                const $t28864 = (() => {
                  {
                    const $t28858 = game.camera_y;
                    {
                      const $t28863 = (() => {
                        {
                          const $t28862 = (() => {
                            {
                              const $t28860 = (() => {
                                {
                                  const $t28859 = game.camera_y;
                                  return (target_y - $t28859);
                                }
                              })();
                              return ($t28860 * 3.);
                            }
                          })();
                          return ($t28862 * dt_s);
                        }
                      })();
                      return ($t28858 + $t28863);
                    }
                  }
                })();
                {
                  const $t28871 = (() => {
                    {
                      const $t28865 = game.camera_x;
                      {
                        const $t28870 = (() => {
                          {
                            const $t28869 = (() => {
                              {
                                const $t28867 = (() => {
                                  {
                                    const $t28866 = game.camera_x;
                                    return (target_x - $t28866);
                                  }
                                })();
                                return ($t28867 * 3.);
                              }
                            })();
                            return ($t28869 * dt_s);
                          }
                        })();
                        return ($t28865 + $t28870);
                      }
                    }
                  })();
                  return ({ ...game, camera_y: $t28864, camera_x: $t28871 });
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
    const $p28925 = (() => {
      {
        const $t28872 = Random$seed(seed);
        return Perihelion$Level$initial_stars($t28872, view_w);
      }
    })();
    {
      const stars = $p28925._0;
      {
        const rng2 = $p28925._1;
        {
          const start_angle = (3.14159265359 / 2.);
          switch (stars.$) {
            case "Nil": {
              {
                const $t28874 = { $: "Ready" };
                {
                  const $t28875 = { $: "Orbiting", _0: 0, _1: 0, _2: start_angle };
                  {
                    const $t28876 = { $: "Nil" };
                    {
                      const $t28877 = { $: "Nil" };
                      {
                        const $t28878 = { $: "Nil" };
                        {
                          const $t28879 = { $: "Nil" };
                          {
                            const $t28880 = { $: "Nil" };
                            {
                              const $t28881 = { $: "Nil" };
                              {
                                const $t28882 = { $: "Base" };
                                {
                                  const $t28883 = { $: "Nil" };
                                  {
                                    const $t28884 = { $: "Cons", _0: $t28882, _1: $t28883 };
                                    {
                                      const $t28885 = { $: "None" };
                                      {
                                        const $t28886 = { $: "Nil" };
                                        {
                                          const $t28888 = { $: "Nil" };
                                          {
                                            const $t28889 = { $: "None" };
                                            return ({ seed: seed, phase: $t28874, ball_x: 0., ball_y: 0., mode: $t28875, stars: $t28876, current: 0, score: 0, best: best, camera_y: 0., camera_x: 0., rng: rng2, asteroids: $t28877, ships: $t28878, player_shots: $t28879, enemy_shots: $t28880, pickups: $t28881, shield: 0, multiplier: 1, max_mult: 1, owned_weapons: $t28884, active_weapon_idx: 0, fire_rate_stacks: 0, bullet_ward: false, deflector_plating: false, shield_reinforced: false, special: $t28885, special_charges: 0, starkiller_target_offset: 0, starkiller_cooldown: 0., milestone_choices: $t28886, stars_chained: 0, loop_angle: 0., fire_cooldown: 0., spawn_timer: 4., runs: runs, view_w: view_w, view_h: view_h, fx_bursts: $t28888, capture_flash: $t28889 });
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
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
              const $f28919 = stars._0;
              const $f28920 = stars._1;
              {
                const s0 = (() => {
                  return $f28919;
                })();
                {
                  const $t28890 = { $: "Ready" };
                  {
                    const $t28895 = (() => {
                      {
                        const $t28891 = s0.x;
                        {
                          const $t28894 = (() => {
                            {
                              const $t28892 = Math.cos(start_angle);
                              {
                                const $t28893 = s0.capture_radius;
                                return ($t28892 * $t28893);
                              }
                            }
                          })();
                          return ($t28891 + $t28894);
                        }
                      }
                    })();
                    {
                      const $t28900 = (() => {
                        {
                          const $t28896 = s0.y;
                          {
                            const $t28899 = (() => {
                              {
                                const $t28897 = Math.sin(start_angle);
                                {
                                  const $t28898 = s0.capture_radius;
                                  return ($t28897 * $t28898);
                                }
                              }
                            })();
                            return ($t28896 + $t28899);
                          }
                        }
                      })();
                      {
                        const $t28901 = { $: "Orbiting", _0: 0, _1: 0, _2: start_angle };
                        {
                          const $t28905 = (() => {
                            {
                              const $t28902 = s0.y;
                              {
                                const $t28904 = (0.6 * view_h);
                                return ($t28902 - $t28904);
                              }
                            }
                          })();
                          {
                            const $t28906 = { $: "Nil" };
                            {
                              const $t28907 = { $: "Nil" };
                              {
                                const $t28908 = { $: "Nil" };
                                {
                                  const $t28909 = { $: "Nil" };
                                  {
                                    const $t28910 = { $: "Nil" };
                                    {
                                      const $t28911 = { $: "Base" };
                                      {
                                        const $t28912 = { $: "Nil" };
                                        {
                                          const $t28913 = { $: "Cons", _0: $t28911, _1: $t28912 };
                                          {
                                            const $t28914 = { $: "None" };
                                            {
                                              const $t28915 = { $: "Nil" };
                                              {
                                                const $t28917 = { $: "Nil" };
                                                {
                                                  const $t28918 = { $: "None" };
                                                  return ({ seed: seed, phase: $t28890, ball_x: $t28895, ball_y: $t28900, mode: $t28901, stars: stars, current: 0, score: 0, best: best, camera_y: $t28905, camera_x: 0., rng: rng2, asteroids: $t28906, ships: $t28907, player_shots: $t28908, enemy_shots: $t28909, pickups: $t28910, shield: 0, multiplier: 1, max_mult: 1, owned_weapons: $t28913, active_weapon_idx: 0, fire_rate_stacks: 0, bullet_ward: false, deflector_plating: false, shield_reinforced: false, special: $t28914, special_charges: 0, starkiller_target_offset: 0, starkiller_cooldown: 0., milestone_choices: $t28915, stars_chained: 0, loop_angle: 0., fire_cooldown: 0., spawn_timer: 4., runs: runs, view_w: view_w, view_h: view_h, fx_bursts: $t28917, capture_flash: $t28918 });
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
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
        const $t28931 = (() => {
          {
            const $p28930_i10121 = (() => {
              {
                const $t28929_i10110 = game.rng;
                {
                  const $p15576_i3946_i10111 = Random$next_raw($t28929_i10110);
                  {
                    const hi_i3947_i10112 = $p15576_i3946_i10111._0;
                    {
                      const rng2_i3948_i10113 = $p15576_i3946_i10111._1;
                      {
                        const $p15575_i3949_i10114 = Random$next_raw(rng2_i3948_i10113);
                        {
                          const lo_i3950_i10115 = $p15575_i3949_i10114._0;
                          {
                            const rng3_i3951_i10116 = $p15575_i3949_i10114._1;
                            {
                              const $t15574_i3955_i10120 = (() => {
                                {
                                  const $t15573_i3954_i10119 = (() => {
                                    {
                                      const $t15571_i3952_i10117 = march_int_and(hi_i3947_i10112, 1048575);
                                      return ($t15571_i3952_i10117 * 4294967296);
                                    }
                                  })();
                                  return ($t15573_i3954_i10119 + lo_i3950_i10115);
                                }
                              })();
                              return { _0: $t15574_i3955_i10120, _1: rng3_i3951_i10116 };
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
              const s_i10122 = $p28930_i10121._0;
              return s_i10122;
            }
          }
        })();
        {
          const $t28932 = game.best;
          {
            const $t28933 = game.runs;
            {
              const $t28934 = game.view_w;
              {
                const $t28935 = game.view_h;
                return Perihelion$Core$fresh_run($t28931, $t28932, $t28933, $t28934, $t28935);
              }
            }
          }
        }
      }
    })();
    {
      const $t28936 = { $: "Playing" };
      return ({ ...g, phase: $t28936 });
    }
  }
}
const Perihelion$Core$restart$clo = { _0: ($_, game) => Perihelion$Core$restart(game) };

function Perihelion$Core$reset(game) {
  {
    const $t28937 = (() => {
      {
        const $p28930_i10135 = (() => {
          {
            const $t28929_i10124 = game.rng;
            {
              const $p15576_i3946_i10125 = Random$next_raw($t28929_i10124);
              {
                const hi_i3947_i10126 = $p15576_i3946_i10125._0;
                {
                  const rng2_i3948_i10127 = $p15576_i3946_i10125._1;
                  {
                    const $p15575_i3949_i10128 = Random$next_raw(rng2_i3948_i10127);
                    {
                      const lo_i3950_i10129 = $p15575_i3949_i10128._0;
                      {
                        const rng3_i3951_i10130 = $p15575_i3949_i10128._1;
                        {
                          const $t15574_i3955_i10134 = (() => {
                            {
                              const $t15573_i3954_i10133 = (() => {
                                {
                                  const $t15571_i3952_i10131 = march_int_and(hi_i3947_i10126, 1048575);
                                  return ($t15571_i3952_i10131 * 4294967296);
                                }
                              })();
                              return ($t15573_i3954_i10133 + lo_i3950_i10129);
                            }
                          })();
                          return { _0: $t15574_i3955_i10134, _1: rng3_i3951_i10130 };
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
          const s_i10136 = $p28930_i10135._0;
          return s_i10136;
        }
      }
    })();
    {
      const $t28938 = game.best;
      {
        const $t28939 = game.runs;
        {
          const $t28940 = game.view_w;
          {
            const $t28941 = game.view_h;
            return Perihelion$Core$fresh_run($t28937, $t28938, $t28939, $t28940, $t28941);
          }
        }
      }
    }
  }
}
const Perihelion$Core$reset$clo = { _0: ($_, game) => Perihelion$Core$reset(game) };

function Perihelion$Core$encode_run(r) {
  {
    const $t28948 = (() => {
      {
        const $t28947 = (() => {
          {
            const $t28944 = (() => {
              {
                const $t28943 = (() => {
                  {
                    const $t28942 = r.score;
                    return String($t28942);
                  }
                })();
                {
                  const $rc_828 = ($t28943 + ":");
                  return $rc_828;
                }
              }
            })();
            {
              const $t28946 = (() => {
                {
                  const $t28945 = r.stars;
                  return String($t28945);
                }
              })();
              {
                const $rc_827 = ($t28944 + $t28946);
                return $rc_827;
              }
            }
          }
        })();
        {
          const $rc_826 = ($t28947 + ":");
          return $rc_826;
        }
      }
    })();
    {
      const $t28950 = (() => {
        {
          const $t28949 = r.max_mult;
          return String($t28949);
        }
      })();
      {
        const $rc_825 = ($t28948 + $t28950);
        return $rc_825;
      }
    }
  }
}
const Perihelion$Core$encode_run$clo = { _0: ($_, r) => Perihelion$Core$encode_run(r) };

function Perihelion$Core$encode_save(best, runs) {
  {
    const $t28952 = (() => {
      {
        const $t28951 = String(best);
        {
          const $rc_830 = ($t28951 + "|");
          return $rc_830;
        }
      }
    })();
    {
      const $t28956 = (() => {
        {
          const $t28954 = { $: "$Clo_$lam28953$3762", _0: $lam28953$apply$3762 };
          {
            const $t28955 = (() => {
              {
                const f_i3959 = $t28954;
                {
                  const go_i3960 = { $: "$Clo_go$4803", _0: go$apply$4803, _1: f_i3959 };
                  {
                    const $t270_i3961 = { $: "Nil" };
                    return go$apply$4803(go_i3960, runs, $t270_i3961);
                  }
                }
              }
            })();
            return march_string_join($t28955, ";");
          }
        }
      })();
      {
        const $rc_829 = ($t28952 + $t28956);
        return $rc_829;
      }
    }
  }
}
const Perihelion$Core$encode_save$clo = { _0: ($_, best, runs) => Perihelion$Core$encode_save(best, runs) };

function Perihelion$Core$decode_run(s) {
  {
    const $t28957 = march_string_split(s, ":");
    switch ($t28957.$) {
      case "Cons": {
        const $f28965 = $t28957._0;
        const $f28966 = $t28957._1;
        {
          const $jp_clo28968 = { $: "$Clo_$jp28967$3763", _0: $jp28967$apply$3763 };
          {
            const $jp_clo28972 = { $: "$Clo_$jp28971$3764", _0: $jp28971$apply$3764$clo, _1: $jp_clo28968 };
            switch ($f28966.$) {
              case "Cons": {
                const $f28973 = $f28966._0;
                const $f28974 = $f28966._1;
                {
                  const $jp_clo28976 = { $: "$Clo_$jp28975$3766", _0: $jp28975$apply$3766, _1: $jp_clo28972 };
                  {
                    const $jp_clo28980 = { $: "$Clo_$jp28979$3767", _0: $jp28979$apply$3767, _1: $jp_clo28976 };
                    switch ($f28974.$) {
                      case "Cons": {
                        const $f28981 = $f28974._0;
                        const $f28982 = $f28974._1;
                        {
                          const $jp_clo28984 = { $: "$Clo_$jp28983$3769", _0: $jp28983$apply$3769, _1: $jp_clo28980 };
                          {
                            const $jp_clo28988 = { $: "$Clo_$jp28987$3770", _0: $jp28987$apply$3770, _1: $jp_clo28984 };
                            switch ($f28982.$) {
                              case "Nil": {
                                {
                                  const c = $f28981;
                                  {
                                    const b = $f28973;
                                    {
                                      const a = $f28965;
                                      {
                                        const $t28958 = (() => {
                                          {
                                            const $rc_833 = march_string_to_int(a);
                                            return $rc_833;
                                          }
                                        })();
                                        switch ($t28958.$) {
                                          case "None": {
                                            return { $: "None" };
                                            break;
                                          }
                                          case "Some": {
                                            const $f28964 = $t28958._0;
                                            {
                                              const score = $f28964;
                                              {
                                                const $t28959 = (() => {
                                                  {
                                                    const $rc_832 = march_string_to_int(b);
                                                    return $rc_832;
                                                  }
                                                })();
                                                switch ($t28959.$) {
                                                  case "None": {
                                                    return { $: "None" };
                                                    break;
                                                  }
                                                  case "Some": {
                                                    const $f28963 = $t28959._0;
                                                    {
                                                      const stars = $f28963;
                                                      {
                                                        const $t28960 = (() => {
                                                          {
                                                            const $rc_831 = march_string_to_int(c);
                                                            return $rc_831;
                                                          }
                                                        })();
                                                        switch ($t28960.$) {
                                                          case "None": {
                                                            return { $: "None" };
                                                            break;
                                                          }
                                                          case "Some": {
                                                            const $f28962 = $t28960._0;
                                                            {
                                                              const mm = $f28962;
                                                              {
                                                                const $t28961 = ({ score: score, stars: stars, max_mult: mm });
                                                                return { $: "Some", _0: $t28961 };
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
                                return $jp28987$apply$3770($jp_clo28988);
                              }
                            }
                          }
                        }
                        break;
                      }
                      default: {
                        return $jp28979$apply$3767($jp_clo28980);
                      }
                    }
                  }
                }
                break;
              }
              default: {
                return $jp28971$apply$3764($jp_clo28972);
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
        const $t28991 = (() => {
          {
            const go_i3969 = { $: "$Clo_go$4805", _0: go$apply$4805 };
            {
              const $t253_i3970 = { $: "Nil" };
              return go$apply$4805(go_i3969, acc, $t253_i3970);
            }
          }
        })();
        return { $: "Some", _0: $t28991 };
      }
      break;
    }
    case "Cons": {
      const $f28995 = parts._0;
      const $f28996 = parts._1;
      {
        const rest = $f28996;
        {
          const p = $f28995;
          {
            const $t28992 = (() => {
              {
                const $rc_834 = Perihelion$Core$decode_run(p);
                return $rc_834;
              }
            })();
            switch ($t28992.$) {
              case "None": {
                return { $: "None" };
                break;
              }
              case "Some": {
                const $f28994 = $t28992._0;
                {
                  const r = $f28994;
                  {
                    const $t28993 = { $: "Cons", _0: r, _1: acc };
                    return Perihelion$Core$decode_runs(rest, $t28993);
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
        const $t29001 = { $: "Nil" };
        return { _0: 0, _1: $t29001 };
      }
    })();
    {
      const $t29002 = march_string_split(s, "|");
      switch ($t29002.$) {
        case "Cons": {
          const $f29012 = $t29002._0;
          const $f29013 = $t29002._1;
          switch ($f29013.$) {
            case "Cons": {
              const $f29014 = $f29013._0;
              const $f29015 = $f29013._1;
              switch ($f29015.$) {
                case "Nil": {
                  {
                    const runs_s = $f29014;
                    {
                      const best_s = $f29012;
                      {
                        const $t29003 = (() => {
                          {
                            const $rc_836 = march_string_to_int(best_s);
                            return $rc_836;
                          }
                        })();
                        switch ($t29003.$) {
                          case "None": {
                            return zero;
                            break;
                          }
                          case "Some": {
                            const $f29011 = $t29003._0;
                            {
                              const best = $f29011;
                              if (runs_s === "") {
                                return (() => {
                                  {
                                    const $t29004 = { $: "Nil" };
                                    return { _0: best, _1: $t29004 };
                                  }
                                })();
                              } else {
                                return (() => {
                                  {
                                    const $t29007 = (() => {
                                      {
                                        const $t29005 = (() => {
                                          {
                                            const $rc_835 = march_string_split(runs_s, ";");
                                            return $rc_835;
                                          }
                                        })();
                                        {
                                          const $t29006 = { $: "Nil" };
                                          return Perihelion$Core$decode_runs($t29005, $t29006);
                                        }
                                      }
                                    })();
                                    switch ($t29007.$) {
                                      case "None": {
                                        return zero;
                                        break;
                                      }
                                      case "Some": {
                                        const $f29008 = $t29007._0;
                                        {
                                          const rs = $f29008;
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
        const $t29021 = ({ radius: outer_r, speed_mult: outer_sp });
        {
          const $t29022 = { $: "Nil" };
          return { $: "Cons", _0: $t29021, _1: $t29022 };
        }
      }
    })();
  } else if (n === 2) {
    return (() => {
      {
        const $t29025 = (() => {
          {
            const $t29023 = (outer_r * 0.6);
            {
              const $t29024 = (outer_sp * 1.5);
              return ({ radius: $t29023, speed_mult: $t29024 });
            }
          }
        })();
        {
          const $t29026 = ({ radius: outer_r, speed_mult: outer_sp });
          {
            const $t29027 = { $: "Nil" };
            {
              const $t29028 = { $: "Cons", _0: $t29026, _1: $t29027 };
              return { $: "Cons", _0: $t29025, _1: $t29028 };
            }
          }
        }
      }
    })();
  } else {
    return (() => {
      {
        const $t29031 = (() => {
          {
            const $t29029 = (outer_r * 0.5);
            {
              const $t29030 = (outer_sp * 1.8);
              return ({ radius: $t29029, speed_mult: $t29030 });
            }
          }
        })();
        {
          const $t29034 = (() => {
            {
              const $t29032 = (outer_r * 0.75);
              {
                const $t29033 = (outer_sp * 1.35);
                return ({ radius: $t29032, speed_mult: $t29033 });
              }
            }
          })();
          {
            const $t29035 = ({ radius: outer_r, speed_mult: outer_sp });
            {
              const $t29036 = { $: "Nil" };
              {
                const $t29037 = { $: "Cons", _0: $t29035, _1: $t29036 };
                {
                  const $t29038 = { $: "Cons", _0: $t29034, _1: $t29037 };
                  return { $: "Cons", _0: $t29031, _1: $t29038 };
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
    const $p29068 = (() => {
      {
        const $p29016_i10537 = (() => {
          {
            const $p15579_i10148_i10532 = (() => {
              {
                const $p15576_i1532_i10138_i10523 = Random$next_raw(rng);
                {
                  const hi_i1533_i10139_i10524 = $p15576_i1532_i10138_i10523._0;
                  {
                    const rng2_i1534_i10140_i10525 = $p15576_i1532_i10138_i10523._1;
                    {
                      const $p15575_i1535_i10141_i10526 = Random$next_raw(rng2_i1534_i10140_i10525);
                      {
                        const lo_i1536_i10142_i10527 = $p15575_i1535_i10141_i10526._0;
                        {
                          const rng3_i1537_i10143_i10528 = $p15575_i1535_i10141_i10526._1;
                          {
                            const $t15574_i1541_i10147_i10531 = (() => {
                              {
                                const $t15573_i1540_i10146_i10530 = (() => {
                                  {
                                    const $t15571_i1538_i10144_i10529 = march_int_and(hi_i1533_i10139_i10524, 1048575);
                                    return ($t15571_i1538_i10144_i10529 * 4294967296);
                                  }
                                })();
                                return ($t15573_i1540_i10146_i10530 + lo_i1536_i10142_i10527);
                              }
                            })();
                            return { _0: $t15574_i1541_i10147_i10531, _1: rng3_i1537_i10143_i10528 };
                          }
                        }
                      }
                    }
                  }
                }
              }
            })();
            {
              const bits_i10149_i10533 = $p15579_i10148_i10532._0;
              {
                const rng2_i10150_i10534 = $p15579_i10148_i10532._1;
                {
                  const $t15578_i10152_i10536 = (() => {
                    {
                      const $t15577_i10151_i10535 = bits_i10149_i10533;
                      return ($t15577_i10151_i10535 / 4.50359962737e+15);
                    }
                  })();
                  return { _0: $t15578_i10152_i10536, _1: rng2_i10150_i10534 };
                }
              }
            }
          }
        })();
        {
          const t_i10538 = $p29016_i10537._0;
          {
            const rng2_i10539 = $p29016_i10537._1;
            {
              const out_i10540 = { _0: rng2_i10539, _1: t_i10538 };
              return out_i10540;
            }
          }
        }
      }
    })();
    {
      const r1 = $p29068._0;
      {
        const ty = $p29068._1;
        {
          const $p29067 = (() => {
            {
              const $p29016_i10518 = (() => {
                {
                  const $p15579_i10148_i10513 = (() => {
                    {
                      const $p15576_i1532_i10138_i10504 = Random$next_raw(r1);
                      {
                        const hi_i1533_i10139_i10505 = $p15576_i1532_i10138_i10504._0;
                        {
                          const rng2_i1534_i10140_i10506 = $p15576_i1532_i10138_i10504._1;
                          {
                            const $p15575_i1535_i10141_i10507 = Random$next_raw(rng2_i1534_i10140_i10506);
                            {
                              const lo_i1536_i10142_i10508 = $p15575_i1535_i10141_i10507._0;
                              {
                                const rng3_i1537_i10143_i10509 = $p15575_i1535_i10141_i10507._1;
                                {
                                  const $t15574_i1541_i10147_i10512 = (() => {
                                    {
                                      const $t15573_i1540_i10146_i10511 = (() => {
                                        {
                                          const $t15571_i1538_i10144_i10510 = march_int_and(hi_i1533_i10139_i10505, 1048575);
                                          return ($t15571_i1538_i10144_i10510 * 4294967296);
                                        }
                                      })();
                                      return ($t15573_i1540_i10146_i10511 + lo_i1536_i10142_i10508);
                                    }
                                  })();
                                  return { _0: $t15574_i1541_i10147_i10512, _1: rng3_i1537_i10143_i10509 };
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  })();
                  {
                    const bits_i10149_i10514 = $p15579_i10148_i10513._0;
                    {
                      const rng2_i10150_i10515 = $p15579_i10148_i10513._1;
                      {
                        const $t15578_i10152_i10517 = (() => {
                          {
                            const $t15577_i10151_i10516 = bits_i10149_i10514;
                            return ($t15577_i10151_i10516 / 4.50359962737e+15);
                          }
                        })();
                        return { _0: $t15578_i10152_i10517, _1: rng2_i10150_i10515 };
                      }
                    }
                  }
                }
              })();
              {
                const t_i10519 = $p29016_i10518._0;
                {
                  const rng2_i10520 = $p29016_i10518._1;
                  {
                    const out_i10521 = { _0: rng2_i10520, _1: t_i10519 };
                    return out_i10521;
                  }
                }
              }
            }
          })();
          {
            const r2 = $p29067._0;
            {
              const tx = $p29067._1;
              {
                const $p29066 = (() => {
                  {
                    const $p29016_i10499 = (() => {
                      {
                        const $p15579_i10148_i10494 = (() => {
                          {
                            const $p15576_i1532_i10138_i10485 = Random$next_raw(r2);
                            {
                              const hi_i1533_i10139_i10486 = $p15576_i1532_i10138_i10485._0;
                              {
                                const rng2_i1534_i10140_i10487 = $p15576_i1532_i10138_i10485._1;
                                {
                                  const $p15575_i1535_i10141_i10488 = Random$next_raw(rng2_i1534_i10140_i10487);
                                  {
                                    const lo_i1536_i10142_i10489 = $p15575_i1535_i10141_i10488._0;
                                    {
                                      const rng3_i1537_i10143_i10490 = $p15575_i1535_i10141_i10488._1;
                                      {
                                        const $t15574_i1541_i10147_i10493 = (() => {
                                          {
                                            const $t15573_i1540_i10146_i10492 = (() => {
                                              {
                                                const $t15571_i1538_i10144_i10491 = march_int_and(hi_i1533_i10139_i10486, 1048575);
                                                return ($t15571_i1538_i10144_i10491 * 4294967296);
                                              }
                                            })();
                                            return ($t15573_i1540_i10146_i10492 + lo_i1536_i10142_i10489);
                                          }
                                        })();
                                        return { _0: $t15574_i1541_i10147_i10493, _1: rng3_i1537_i10143_i10490 };
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        })();
                        {
                          const bits_i10149_i10495 = $p15579_i10148_i10494._0;
                          {
                            const rng2_i10150_i10496 = $p15579_i10148_i10494._1;
                            {
                              const $t15578_i10152_i10498 = (() => {
                                {
                                  const $t15577_i10151_i10497 = bits_i10149_i10495;
                                  return ($t15577_i10151_i10497 / 4.50359962737e+15);
                                }
                              })();
                              return { _0: $t15578_i10152_i10498, _1: rng2_i10150_i10496 };
                            }
                          }
                        }
                      }
                    })();
                    {
                      const t_i10500 = $p29016_i10499._0;
                      {
                        const rng2_i10501 = $p29016_i10499._1;
                        {
                          const out_i10502 = { _0: rng2_i10501, _1: t_i10500 };
                          return out_i10502;
                        }
                      }
                    }
                  }
                })();
                {
                  const r3 = $p29066._0;
                  {
                    const tr = $p29066._1;
                    {
                      const $p29065 = (() => {
                        {
                          const $p29016_i10480 = (() => {
                            {
                              const $p15579_i10148_i10475 = (() => {
                                {
                                  const $p15576_i1532_i10138_i10466 = Random$next_raw(r3);
                                  {
                                    const hi_i1533_i10139_i10467 = $p15576_i1532_i10138_i10466._0;
                                    {
                                      const rng2_i1534_i10140_i10468 = $p15576_i1532_i10138_i10466._1;
                                      {
                                        const $p15575_i1535_i10141_i10469 = Random$next_raw(rng2_i1534_i10140_i10468);
                                        {
                                          const lo_i1536_i10142_i10470 = $p15575_i1535_i10141_i10469._0;
                                          {
                                            const rng3_i1537_i10143_i10471 = $p15575_i1535_i10141_i10469._1;
                                            {
                                              const $t15574_i1541_i10147_i10474 = (() => {
                                                {
                                                  const $t15573_i1540_i10146_i10473 = (() => {
                                                    {
                                                      const $t15571_i1538_i10144_i10472 = march_int_and(hi_i1533_i10139_i10467, 1048575);
                                                      return ($t15571_i1538_i10144_i10472 * 4294967296);
                                                    }
                                                  })();
                                                  return ($t15573_i1540_i10146_i10473 + lo_i1536_i10142_i10470);
                                                }
                                              })();
                                              return { _0: $t15574_i1541_i10147_i10474, _1: rng3_i1537_i10143_i10471 };
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              })();
                              {
                                const bits_i10149_i10476 = $p15579_i10148_i10475._0;
                                {
                                  const rng2_i10150_i10477 = $p15579_i10148_i10475._1;
                                  {
                                    const $t15578_i10152_i10479 = (() => {
                                      {
                                        const $t15577_i10151_i10478 = bits_i10149_i10476;
                                        return ($t15577_i10151_i10478 / 4.50359962737e+15);
                                      }
                                    })();
                                    return { _0: $t15578_i10152_i10479, _1: rng2_i10150_i10477 };
                                  }
                                }
                              }
                            }
                          })();
                          {
                            const t_i10481 = $p29016_i10480._0;
                            {
                              const rng2_i10482 = $p29016_i10480._1;
                              {
                                const out_i10483 = { _0: rng2_i10482, _1: t_i10481 };
                                return out_i10483;
                              }
                            }
                          }
                        }
                      })();
                      {
                        const r4 = $p29065._0;
                        {
                          const tcm = $p29065._1;
                          {
                            const $p29064 = (() => {
                              {
                                const $p29016_i10461 = (() => {
                                  {
                                    const $p15579_i10148_i10456 = (() => {
                                      {
                                        const $p15576_i1532_i10138_i10447 = Random$next_raw(r4);
                                        {
                                          const hi_i1533_i10139_i10448 = $p15576_i1532_i10138_i10447._0;
                                          {
                                            const rng2_i1534_i10140_i10449 = $p15576_i1532_i10138_i10447._1;
                                            {
                                              const $p15575_i1535_i10141_i10450 = Random$next_raw(rng2_i1534_i10140_i10449);
                                              {
                                                const lo_i1536_i10142_i10451 = $p15575_i1535_i10141_i10450._0;
                                                {
                                                  const rng3_i1537_i10143_i10452 = $p15575_i1535_i10141_i10450._1;
                                                  {
                                                    const $t15574_i1541_i10147_i10455 = (() => {
                                                      {
                                                        const $t15573_i1540_i10146_i10454 = (() => {
                                                          {
                                                            const $t15571_i1538_i10144_i10453 = march_int_and(hi_i1533_i10139_i10448, 1048575);
                                                            return ($t15571_i1538_i10144_i10453 * 4294967296);
                                                          }
                                                        })();
                                                        return ($t15573_i1540_i10146_i10454 + lo_i1536_i10142_i10451);
                                                      }
                                                    })();
                                                    return { _0: $t15574_i1541_i10147_i10455, _1: rng3_i1537_i10143_i10452 };
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    })();
                                    {
                                      const bits_i10149_i10457 = $p15579_i10148_i10456._0;
                                      {
                                        const rng2_i10150_i10458 = $p15579_i10148_i10456._1;
                                        {
                                          const $t15578_i10152_i10460 = (() => {
                                            {
                                              const $t15577_i10151_i10459 = bits_i10149_i10457;
                                              return ($t15577_i10151_i10459 / 4.50359962737e+15);
                                            }
                                          })();
                                          return { _0: $t15578_i10152_i10460, _1: rng2_i10150_i10458 };
                                        }
                                      }
                                    }
                                  }
                                })();
                                {
                                  const t_i10462 = $p29016_i10461._0;
                                  {
                                    const rng2_i10463 = $p29016_i10461._1;
                                    {
                                      const out_i10464 = { _0: rng2_i10463, _1: t_i10462 };
                                      return out_i10464;
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const r5 = $p29064._0;
                              {
                                const tsm = $p29064._1;
                                {
                                  const $p29063 = (() => {
                                    {
                                      const $p29016_i10442 = (() => {
                                        {
                                          const $p15579_i10148_i10437 = (() => {
                                            {
                                              const $p15576_i1532_i10138_i10428 = Random$next_raw(r5);
                                              {
                                                const hi_i1533_i10139_i10429 = $p15576_i1532_i10138_i10428._0;
                                                {
                                                  const rng2_i1534_i10140_i10430 = $p15576_i1532_i10138_i10428._1;
                                                  {
                                                    const $p15575_i1535_i10141_i10431 = Random$next_raw(rng2_i1534_i10140_i10430);
                                                    {
                                                      const lo_i1536_i10142_i10432 = $p15575_i1535_i10141_i10431._0;
                                                      {
                                                        const rng3_i1537_i10143_i10433 = $p15575_i1535_i10141_i10431._1;
                                                        {
                                                          const $t15574_i1541_i10147_i10436 = (() => {
                                                            {
                                                              const $t15573_i1540_i10146_i10435 = (() => {
                                                                {
                                                                  const $t15571_i1538_i10144_i10434 = march_int_and(hi_i1533_i10139_i10429, 1048575);
                                                                  return ($t15571_i1538_i10144_i10434 * 4294967296);
                                                                }
                                                              })();
                                                              return ($t15573_i1540_i10146_i10435 + lo_i1536_i10142_i10432);
                                                            }
                                                          })();
                                                          return { _0: $t15574_i1541_i10147_i10436, _1: rng3_i1537_i10143_i10433 };
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          })();
                                          {
                                            const bits_i10149_i10438 = $p15579_i10148_i10437._0;
                                            {
                                              const rng2_i10150_i10439 = $p15579_i10148_i10437._1;
                                              {
                                                const $t15578_i10152_i10441 = (() => {
                                                  {
                                                    const $t15577_i10151_i10440 = bits_i10149_i10438;
                                                    return ($t15577_i10151_i10440 / 4.50359962737e+15);
                                                  }
                                                })();
                                                return { _0: $t15578_i10152_i10441, _1: rng2_i10150_i10439 };
                                              }
                                            }
                                          }
                                        }
                                      })();
                                      {
                                        const t_i10443 = $p29016_i10442._0;
                                        {
                                          const rng2_i10444 = $p29016_i10442._1;
                                          {
                                            const out_i10445 = { _0: rng2_i10444, _1: t_i10443 };
                                            return out_i10445;
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const r6 = $p29063._0;
                                    {
                                      const trings = $p29063._1;
                                      {
                                        const gap = (() => {
                                          {
                                            const $t29018_i4010 = (() => {
                                              {
                                                const $t29017_i4009 = (260. - 160.);
                                                return (ty * $t29017_i4009);
                                              }
                                            })();
                                            return (160. + $t29018_i4010);
                                          }
                                        })();
                                        {
                                          const dx = (() => {
                                            {
                                              const $t29046 = (0. - 220.);
                                              {
                                                const $t29018_i4005 = (() => {
                                                  {
                                                    const $t29017_i4004 = (220. - $t29046);
                                                    return (tx * $t29017_i4004);
                                                  }
                                                })();
                                                return ($t29046 + $t29018_i4005);
                                              }
                                            }
                                          })();
                                          {
                                            const x = (() => {
                                              {
                                                const $t29049 = (() => {
                                                  {
                                                    const $t29048 = prev.x;
                                                    return ($t29048 + dx);
                                                  }
                                                })();
                                                {
                                                  const $t29052 = (view_w - 60.);
                                                  {
                                                    const $t1580_i3999 = ($t29049 < 60.);
                                                    if ($t1580_i3999 === true) {
                                                      return 60.;
                                                    } else {
                                                      return (() => {
                                                        {
                                                          const $t1581_i4000 = ($t29049 > $t29052);
                                                          if ($t1581_i4000 === true) {
                                                            return $t29052;
                                                          } else {
                                                            return $t29049;
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
                                                  const $t29055 = (tr * tr);
                                                  {
                                                    const $t29018_i3995 = (() => {
                                                      {
                                                        const $t29017_i3994 = (20. - 8.);
                                                        return ($t29055 * $t29017_i3994);
                                                      }
                                                    })();
                                                    return (8. + $t29018_i3995);
                                                  }
                                                }
                                              })();
                                              {
                                                const cm = (() => {
                                                  {
                                                    const $t29018_i3990 = (() => {
                                                      {
                                                        const $t29017_i3989 = (5.2 - 2.8);
                                                        return (tcm * $t29017_i3989);
                                                      }
                                                    })();
                                                    return (2.8 + $t29018_i3990);
                                                  }
                                                })();
                                                {
                                                  const sm = (() => {
                                                    {
                                                      const $t29018_i3985 = (() => {
                                                        {
                                                          const $t29017_i3984 = (1.6 - 0.7);
                                                          return (tsm * $t29017_i3984);
                                                        }
                                                      })();
                                                      return (0.7 + $t29018_i3985);
                                                    }
                                                  })();
                                                  {
                                                    const cap = (r * cm);
                                                    {
                                                      const $t29060 = (() => {
                                                        {
                                                          const $t29019_i3979 = (trings < 0.55);
                                                          if ($t29019_i3979 === true) {
                                                            return 1;
                                                          } else {
                                                            return (() => {
                                                              {
                                                                const $t29020_i3980 = (trings < 0.85);
                                                                if ($t29020_i3980 === true) {
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
                                                        const orbits = Perihelion$Level$make_orbits(cap, sm, $t29060);
                                                        {
                                                          const s = (() => {
                                                            {
                                                              const $t29062 = (() => {
                                                                {
                                                                  const $t29061 = prev.y;
                                                                  return ($t29061 - gap);
                                                                }
                                                              })();
                                                              return ({ x: x, y: $t29062, radius: r, capture_radius: cap, speed_mult: sm, orbits: orbits });
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
        const $t29069 = (view_w / 2.);
        {
          const $t29070 = ({ radius: 54., speed_mult: 1. });
          {
            const $t29071 = { $: "Nil" };
            {
              const $t29072 = { $: "Cons", _0: $t29070, _1: $t29071 };
              return ({ x: $t29069, y: 520., radius: 18., capture_radius: 54., speed_mult: 1., orbits: $t29072 });
            }
          }
        }
      }
    })();
    {
      const $p29077 = Perihelion$Level$next_star(rng, first, view_w);
      {
        const s2 = $p29077._0;
        {
          const rng2 = $p29077._1;
          {
            const $p29076 = Perihelion$Level$next_star(rng2, s2, view_w);
            {
              const s3 = $p29076._0;
              {
                const rng3 = $p29076._1;
                {
                  const $t29073 = { $: "Nil" };
                  {
                    const $t29074 = { $: "Cons", _0: s3, _1: $t29073 };
                    {
                      const $t29075 = { $: "Cons", _0: s2, _1: $t29074 };
                      {
                        const stars = { $: "Cons", _0: first, _1: $t29075 };
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
    const $t29089 = (() => {
      {
        const $t29087 = (() => {
          {
            const x_i10210 = (() => {
              {
                const $t29083_i10209 = (() => {
                  {
                    const $t29082_i10208 = (() => {
                      {
                        const $t29080_i10206 = (() => {
                          {
                            const $t29078_i10204 = (sx * 12.9898);
                            {
                              const $t29079_i10205 = (sy * 78.233);
                              return ($t29078_i10204 + $t29079_i10205);
                            }
                          }
                        })();
                        {
                          const $t29081_i10207 = (seed * 37.719);
                          return ($t29080_i10206 + $t29081_i10207);
                        }
                      }
                    })();
                    return Math.sin($t29082_i10208);
                  }
                })();
                return ($t29083_i10209 * 43758.5453);
              }
            })();
            {
              const $t29084_i10212 = (() => {
                {
                  const $t1582_i4012_i10211 = Math.floor(x_i10210);
                  return $t1582_i4012_i10211;
                }
              })();
              return (x_i10210 - $t29084_i10212);
            }
          }
        })();
        return ($t29087 > 0.55);
      }
    })();
    if ($t29089 === true) {
      return { $: "None" };
    } else {
      return (() => {
        {
          const jx = (() => {
            {
              const $t29093 = (() => {
                {
                  const $t29092 = (() => {
                    {
                      const $t29091 = (() => {
                        {
                          const $t29090 = (sx + 1.);
                          {
                            const x_i10198 = (() => {
                              {
                                const $t29083_i10197 = (() => {
                                  {
                                    const $t29082_i10196 = (() => {
                                      {
                                        const $t29080_i10194 = (() => {
                                          {
                                            const $t29078_i10192 = ($t29090 * 12.9898);
                                            {
                                              const $t29079_i10193 = (sy * 78.233);
                                              return ($t29078_i10192 + $t29079_i10193);
                                            }
                                          }
                                        })();
                                        {
                                          const $t29081_i10195 = (seed * 37.719);
                                          return ($t29080_i10194 + $t29081_i10195);
                                        }
                                      }
                                    })();
                                    return Math.sin($t29082_i10196);
                                  }
                                })();
                                return ($t29083_i10197 * 43758.5453);
                              }
                            })();
                            {
                              const $t29084_i10200 = (() => {
                                {
                                  const $t1582_i4012_i10199 = Math.floor(x_i10198);
                                  return $t1582_i4012_i10199;
                                }
                              })();
                              return (x_i10198 - $t29084_i10200);
                            }
                          }
                        }
                      })();
                      return ($t29091 - 0.5);
                    }
                  })();
                  return ($t29092 * 2.);
                }
              })();
              return ($t29093 * 90.);
            }
          })();
          {
            const jy = (() => {
              {
                const $t29098 = (() => {
                  {
                    const $t29097 = (() => {
                      {
                        const $t29096 = (() => {
                          {
                            const $t29095 = (sy + 1.);
                            {
                              const x_i10186 = (() => {
                                {
                                  const $t29083_i10185 = (() => {
                                    {
                                      const $t29082_i10184 = (() => {
                                        {
                                          const $t29080_i10182 = (() => {
                                            {
                                              const $t29078_i10180 = (sx * 12.9898);
                                              {
                                                const $t29079_i10181 = ($t29095 * 78.233);
                                                return ($t29078_i10180 + $t29079_i10181);
                                              }
                                            }
                                          })();
                                          {
                                            const $t29081_i10183 = (seed * 37.719);
                                            return ($t29080_i10182 + $t29081_i10183);
                                          }
                                        }
                                      })();
                                      return Math.sin($t29082_i10184);
                                    }
                                  })();
                                  return ($t29083_i10185 * 43758.5453);
                                }
                              })();
                              {
                                const $t29084_i10188 = (() => {
                                  {
                                    const $t1582_i4012_i10187 = Math.floor(x_i10186);
                                    return $t1582_i4012_i10187;
                                  }
                                })();
                                return (x_i10186 - $t29084_i10188);
                              }
                            }
                          }
                        })();
                        return ($t29096 - 0.5);
                      }
                    })();
                    return ($t29097 * 2.);
                  }
                })();
                return ($t29098 * 90.);
              }
            })();
            {
              const rt = (() => {
                {
                  const $t29100 = (sx + 2.);
                  {
                    const x_i10174 = (() => {
                      {
                        const $t29083_i10173 = (() => {
                          {
                            const $t29082_i10172 = (() => {
                              {
                                const $t29080_i10170 = (() => {
                                  {
                                    const $t29078_i10168 = ($t29100 * 12.9898);
                                    {
                                      const $t29079_i10169 = (sy * 78.233);
                                      return ($t29078_i10168 + $t29079_i10169);
                                    }
                                  }
                                })();
                                {
                                  const $t29081_i10171 = (seed * 37.719);
                                  return ($t29080_i10170 + $t29081_i10171);
                                }
                              }
                            })();
                            return Math.sin($t29082_i10172);
                          }
                        })();
                        return ($t29083_i10173 * 43758.5453);
                      }
                    })();
                    {
                      const $t29084_i10176 = (() => {
                        {
                          const $t1582_i4012_i10175 = Math.floor(x_i10174);
                          return $t1582_i4012_i10175;
                        }
                      })();
                      return (x_i10174 - $t29084_i10176);
                    }
                  }
                }
              })();
              {
                const r = (() => {
                  {
                    const $t29103 = (rt * rt);
                    {
                      const $t29086_i4018 = (() => {
                        {
                          const $t29085_i4017 = (700. - 240.);
                          return ($t29103 * $t29085_i4017);
                        }
                      })();
                      return (240. + $t29086_i4018);
                    }
                  }
                })();
                {
                  const strength = (() => {
                    {
                      const $t29106 = (() => {
                        {
                          const $t29105 = (() => {
                            {
                              const $t29104 = (sy + 2.);
                              {
                                const x_i10162 = (() => {
                                  {
                                    const $t29083_i10161 = (() => {
                                      {
                                        const $t29082_i10160 = (() => {
                                          {
                                            const $t29080_i10158 = (() => {
                                              {
                                                const $t29078_i10156 = (sx * 12.9898);
                                                {
                                                  const $t29079_i10157 = ($t29104 * 78.233);
                                                  return ($t29078_i10156 + $t29079_i10157);
                                                }
                                              }
                                            })();
                                            {
                                              const $t29081_i10159 = (seed * 37.719);
                                              return ($t29080_i10158 + $t29081_i10159);
                                            }
                                          }
                                        })();
                                        return Math.sin($t29082_i10160);
                                      }
                                    })();
                                    return ($t29083_i10161 * 43758.5453);
                                  }
                                })();
                                {
                                  const $t29084_i10164 = (() => {
                                    {
                                      const $t1582_i4012_i10163 = Math.floor(x_i10162);
                                      return $t1582_i4012_i10163;
                                    }
                                  })();
                                  return (x_i10162 - $t29084_i10164);
                                }
                              }
                            }
                          })();
                          return (0.65 * $t29105);
                        }
                      })();
                      return (0.35 + $t29106);
                    }
                  })();
                  {
                    const $t29109 = (() => {
                      {
                        const $t29107 = (sx + jx);
                        {
                          const $t29108 = (sy + jy);
                          return ({ x: $t29107, y: $t29108, radius: r, strength: strength });
                        }
                      }
                    })();
                    return { $: "Some", _0: $t29109 };
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
      const $f29142 = stars._0;
      const $f29143 = stars._1;
      {
        const rest = $f29143;
        {
          const s = $f29142;
          {
            const $t29140 = (() => {
              {
                const $t29138 = s.x;
                {
                  const $t29139 = s.y;
                  return Perihelion$Nebula$star_cloud($t29138, $t29139, seed);
                }
              }
            })();
            {
              let acc2;
              switch ($t29140.$) {
                case "None": {
                  acc2 = acc;
                  break;
                }
                case "Some": {
                  const $f29141 = $t29140._0;
                  acc2 = (() => {
                    {
                      const c = $f29141;
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
      const $f29156 = stars._0;
      const $f29157 = stars._1;
      {
        const rest = $f29157;
        {
          const s = $f29156;
          {
            const $t29155 = (() => {
              {
                const $t29150_i4037 = (() => {
                  {
                    const $t29148_i4035 = s.y;
                    {
                      const $t29149_i4036 = (cam_y - margin);
                      return ($t29148_i4035 >= $t29149_i4036);
                    }
                  }
                })();
                {
                  const $t29154_i4041 = (() => {
                    {
                      const $t29151_i4038 = s.y;
                      {
                        const $t29153_i4040 = (() => {
                          {
                            const $t29152_i4039 = (cam_y + view_h);
                            return ($t29152_i4039 + margin);
                          }
                        })();
                        return ($t29151_i4038 <= $t29153_i4040);
                      }
                    }
                  })();
                  return ($t29150_i4037 && $t29154_i4041);
                }
              }
            })();
            {
              let acc2;
              if ($t29155 === true) {
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

function Perihelion$Upgrades$is_milestone(stars_chained) {
  {
    const $t29167 = (stars_chained > 0);
    {
      const $t29170 = (() => {
        {
          const $t29169 = march_int_mod(stars_chained, 10);
          return ($t29169 === 0);
        }
      })();
      return ($t29167 && $t29170);
    }
  }
}
const Perihelion$Upgrades$is_milestone$clo = { _0: ($_, stars_chained) => Perihelion$Upgrades$is_milestone(stars_chained) };

function Perihelion$Upgrades$milestone_pool(owned) {
  {
    const $t29172 = (() => {
      {
        const $t29171 = { $: "Homing" };
        return { $: "OffenseWeapon", _0: $t29171 };
      }
    })();
    {
      const $t29174 = (() => {
        {
          const $t29173 = { $: "Spread" };
          return { $: "OffenseWeapon", _0: $t29173 };
        }
      })();
      {
        const $t29175 = { $: "Nil" };
        {
          const $t29176 = { $: "Cons", _0: $t29174, _1: $t29175 };
          {
            const all_weapons = { $: "Cons", _0: $t29172, _1: $t29176 };
            {
              const $t29180 = { $: "$Clo_$lam29177$3780", _0: $lam29177$apply$3780, _1: owned };
              {
                const unowned_weapons = (() => {
                  {
                    const pred_i4043 = $t29180;
                    {
                      const go_i4044 = { $: "$Clo_go$4809", _0: go$apply$4809, _1: pred_i4043 };
                      {
                        const $t302_i4045 = { $: "Nil" };
                        return go$apply$4809(go_i4044, all_weapons, $t302_i4045);
                      }
                    }
                  }
                })();
                {
                  const $t29181 = { $: "OffenseFireRate" };
                  {
                    const $t29182 = { $: "DefenseBulletWard" };
                    {
                      const $t29183 = { $: "DefenseDeflector" };
                      {
                        const $t29184 = { $: "DefenseShield" };
                        {
                          const $t29186 = (() => {
                            {
                              const $t29185 = { $: "StarThrust" };
                              return { $: "SpecialItem", _0: $t29185 };
                            }
                          })();
                          {
                            const $t29188 = (() => {
                              {
                                const $t29187 = { $: "StarJump" };
                                return { $: "SpecialItem", _0: $t29187 };
                              }
                            })();
                            {
                              const $t29190 = (() => {
                                {
                                  const $t29189 = { $: "TrajectoryPreview" };
                                  return { $: "SpecialItem", _0: $t29189 };
                                }
                              })();
                              {
                                const $t29191 = { $: "Nil" };
                                {
                                  const $t29192 = { $: "Cons", _0: $t29190, _1: $t29191 };
                                  {
                                    const $t29193 = { $: "Cons", _0: $t29188, _1: $t29192 };
                                    {
                                      const $t29194 = { $: "Cons", _0: $t29186, _1: $t29193 };
                                      {
                                        const $t29195 = { $: "Cons", _0: $t29184, _1: $t29194 };
                                        {
                                          const $t29196 = { $: "Cons", _0: $t29183, _1: $t29195 };
                                          {
                                            const $t29197 = { $: "Cons", _0: $t29182, _1: $t29196 };
                                            {
                                              const $t29198 = { $: "Cons", _0: $t29181, _1: $t29197 };
                                              {
                                                const go_i10215 = { $: "$Clo_go$4807", _0: go$apply$4807 };
                                                {
                                                  const $t261_i10218 = (() => {
                                                    {
                                                      const go_i4499_i10216 = { $: "$Clo_go$5249", _0: go$apply$5249 };
                                                      {
                                                        const $t253_i4500_i10217 = { $: "Nil" };
                                                        return go$apply$5249(go_i4499_i10216, unowned_weapons, $t253_i4500_i10217);
                                                      }
                                                    }
                                                  })();
                                                  return go$apply$4807(go_i10215, $t261_i10218, $t29198);
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
const Perihelion$Upgrades$milestone_pool$clo = { _0: ($_, owned) => Perihelion$Upgrades$milestone_pool(owned) };

function Perihelion$Upgrades$remove_upgrade_at(xs, idx) {
  {
    const $t29199 = (() => {
      {
        const go_i4048 = { $: "$Clo_go$4812", _0: go$apply$4812 };
        {
          const $t508_i4049 = { $: "Nil" };
          return go$apply$4812(go_i4048, xs, idx, $t508_i4049);
        }
      }
    })();
    {
      const $t29200 = (idx + 1);
      {
        const $t29201 = List$drop$List_UpgradeKind$Int(xs, $t29200);
        {
          const go_i10221 = { $: "$Clo_go$4807", _0: go$apply$4807 };
          {
            const $t261_i10224 = (() => {
              {
                const go_i4499_i10222 = { $: "$Clo_go$5249", _0: go$apply$5249 };
                {
                  const $t253_i4500_i10223 = { $: "Nil" };
                  return go$apply$5249(go_i4499_i10222, $t29199, $t253_i4500_i10223);
                }
              }
            })();
            return go$apply$4807(go_i10221, $t261_i10224, $t29201);
          }
        }
      }
    }
  }
}
const Perihelion$Upgrades$remove_upgrade_at$clo = { _0: ($_, xs, idx) => Perihelion$Upgrades$remove_upgrade_at(xs, idx) };

function Perihelion$Upgrades$pick_and_remove(rng, pool) {
  {
    const $p29205 = (() => {
      {
        const $p29016_i10423_i10760_i11087 = (() => {
          {
            const $p15579_i10148_i10418_i10755_i11082 = (() => {
              {
                const $p15576_i1532_i10138_i10409_i10746_i11073 = Random$next_raw(rng);
                {
                  const hi_i1533_i10139_i10410_i10747_i11074 = $p15576_i1532_i10138_i10409_i10746_i11073._0;
                  {
                    const rng2_i1534_i10140_i10411_i10748_i11075 = $p15576_i1532_i10138_i10409_i10746_i11073._1;
                    {
                      const $p15575_i1535_i10141_i10412_i10749_i11076 = Random$next_raw(rng2_i1534_i10140_i10411_i10748_i11075);
                      {
                        const lo_i1536_i10142_i10413_i10750_i11077 = $p15575_i1535_i10141_i10412_i10749_i11076._0;
                        {
                          const rng3_i1537_i10143_i10414_i10751_i11078 = $p15575_i1535_i10141_i10412_i10749_i11076._1;
                          {
                            const $t15574_i1541_i10147_i10417_i10754_i11081 = (() => {
                              {
                                const $t15573_i1540_i10146_i10416_i10753_i11080 = (() => {
                                  {
                                    const $t15571_i1538_i10144_i10415_i10752_i11079 = march_int_and(hi_i1533_i10139_i10410_i10747_i11074, 1048575);
                                    return ($t15571_i1538_i10144_i10415_i10752_i11079 * 4294967296);
                                  }
                                })();
                                return ($t15573_i1540_i10146_i10416_i10753_i11080 + lo_i1536_i10142_i10413_i10750_i11077);
                              }
                            })();
                            return { _0: $t15574_i1541_i10147_i10417_i10754_i11081, _1: rng3_i1537_i10143_i10414_i10751_i11078 };
                          }
                        }
                      }
                    }
                  }
                }
              }
            })();
            {
              const bits_i10149_i10419_i10756_i11083 = $p15579_i10148_i10418_i10755_i11082._0;
              {
                const rng2_i10150_i10420_i10757_i11084 = $p15579_i10148_i10418_i10755_i11082._1;
                {
                  const $t15578_i10152_i10422_i10759_i11086 = (() => {
                    {
                      const $t15577_i10151_i10421_i10758_i11085 = bits_i10149_i10419_i10756_i11083;
                      return ($t15577_i10151_i10421_i10758_i11085 / 4.50359962737e+15);
                    }
                  })();
                  return { _0: $t15578_i10152_i10422_i10759_i11086, _1: rng2_i10150_i10420_i10757_i11084 };
                }
              }
            }
          }
        })();
        {
          const t_i10424_i10761_i11088 = $p29016_i10423_i10760_i11087._0;
          {
            const rng2_i10425_i10762_i11089 = $p29016_i10423_i10760_i11087._1;
            {
              const out_i10426_i10763_i11090 = { _0: rng2_i10425_i10762_i11089, _1: t_i10424_i10761_i11088 };
              return out_i10426_i10763_i11090;
            }
          }
        }
      }
    })();
    {
      const rng2 = $p29205._0;
      {
        const t = $p29205._1;
        {
          const n = (() => {
            {
              const go_i4051 = { $: "$Clo_go$4815", _0: go$apply$4815 };
              return go$apply$4815(go_i4051, pool, 0);
            }
          })();
          {
            const idx = (() => {
              {
                const $t29203 = (() => {
                  {
                    const $t29202 = n;
                    return (t * $t29202);
                  }
                })();
                return Math.trunc($t29203);
              }
            })();
            {
              const clamped = (() => {
                {
                  const $t29204 = (idx >= n);
                  if ($t29204 === true) {
                    return (n - 1);
                  } else {
                    return idx;
                  }
                }
              })();
              {
                const picked = (() => {
                  return List$nth$List_UpgradeKind$Int(pool, clamped);
                })();
                {
                  const rest = Perihelion$Upgrades$remove_upgrade_at(pool, clamped);
                  return { _0: rng2, _1: picked, _2: rest };
                }
              }
            }
          }
        }
      }
    }
  }
}
const Perihelion$Upgrades$pick_and_remove$clo = { _0: ($_, rng, pool) => Perihelion$Upgrades$pick_and_remove(rng, pool) };

function Perihelion$Upgrades$draw_n(rng, pool, n, acc) {
  {
    const $t29208 = (() => {
      {
        const $t29206 = (n === 0);
        {
          let $t29207;
          switch (pool.$) {
            case "Nil": {
              $t29207 = true;
              break;
            }
            default: {
              $t29207 = false;
              break;
            }
          }
          return ($t29206 || $t29207);
        }
      }
    })();
    if ($t29208 === true) {
      return { _0: rng, _1: acc };
    } else {
      return (() => {
        {
          const $p29211 = Perihelion$Upgrades$pick_and_remove(rng, pool);
          {
            const rng2 = $p29211._0;
            {
              const picked = $p29211._1;
              {
                const rest = $p29211._2;
                {
                  const $t29209 = (n - 1);
                  {
                    const $t29210 = (() => {
                      return { $: "Cons", _0: picked, _1: acc };
                    })();
                    return Perihelion$Upgrades$draw_n(rng2, rest, $t29209, $t29210);
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
const Perihelion$Upgrades$draw_n$clo = { _0: ($_, rng, pool, n, acc) => Perihelion$Upgrades$draw_n(rng, pool, n, acc) };

function Perihelion$Upgrades$draw_choices(rng, owned_weapons, current_special) {
  switch (current_special.$) {
    case "None": {
      {
        const $t29212 = Perihelion$Upgrades$milestone_pool(owned_weapons);
        {
          const $t29213 = { $: "Nil" };
          return Perihelion$Upgrades$draw_n(rng, $t29212, 3, $t29213);
        }
      }
      break;
    }
    case "Some": {
      const $f29222 = current_special._0;
      {
        const k = $f29222;
        {
          const $t29214 = Perihelion$Upgrades$milestone_pool(owned_weapons);
          {
            const $t29217 = (() => {
              return { $: "$Clo_$lam29215$3781", _0: $lam29215$apply$3781, _1: k };
            })();
            {
              const pool = (() => {
                {
                  const pred_i4055 = $t29217;
                  {
                    const go_i4056 = { $: "$Clo_go$4809", _0: go$apply$4809, _1: pred_i4055 };
                    {
                      const $t302_i4057 = { $: "Nil" };
                      return go$apply$4809(go_i4056, $t29214, $t302_i4057);
                    }
                  }
                }
              })();
              {
                const $p29221 = (() => {
                  {
                    const $t29218 = { $: "Nil" };
                    return Perihelion$Upgrades$draw_n(rng, pool, 2, $t29218);
                  }
                })();
                {
                  const rng2 = $p29221._0;
                  {
                    const two = $p29221._1;
                    {
                      const $t29219 = { $: "SpecialItem", _0: k };
                      {
                        const $t29220 = (() => {
                          return { $: "Cons", _0: $t29219, _1: two };
                        })();
                        return { _0: rng2, _1: $t29220 };
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
const Perihelion$Upgrades$draw_choices$clo = { _0: ($_, rng, owned_weapons, current_special) => Perihelion$Upgrades$draw_choices(rng, owned_weapons, current_special) };

function Perihelion$Upgrades$roll_one(rng, owned_weapons, current_special) {
  {
    const $p29224 = (() => {
      {
        const $t29223 = Perihelion$Upgrades$milestone_pool(owned_weapons);
        return Perihelion$Upgrades$pick_and_remove(rng, $t29223);
      }
    })();
    {
      const rng2 = $p29224._0;
      {
        const picked = $p29224._1;
        return { _0: rng2, _1: picked };
      }
    }
  }
}
const Perihelion$Upgrades$roll_one$clo = { _0: ($_, rng, owned_weapons, current_special) => Perihelion$Upgrades$roll_one(rng, owned_weapons, current_special) };

function boot_seed() {
  {
    const $t29227 = (() => {
      {
        const $t29226 = (() => {
          {
            const $t29225 = {  };
            return march_unix_time();
          }
        })();
        return ($t29226 * 1000000.);
      }
    })();
    return Math.trunc($t29227);
  }
}
const boot_seed$clo = { _0: ($_) => boot_seed() };

function spawn_burst_particles(x, y, t, i, acc) {
  {
    const $t29238 = (i >= 10);
    if ($t29238 === true) {
      return acc;
    } else {
      return (() => {
        {
          const seed = (() => {
            {
              const $t29240 = (() => {
                {
                  const $t29239 = i;
                  return ($t29239 * 7.);
                }
              })();
              return (t + $t29240);
            }
          })();
          {
            const a = (() => {
              {
                const $t29241 = (() => {
                  {
                    const x_i10249 = (() => {
                      {
                        const $t29235_i10248 = (() => {
                          {
                            const $t29234_i10247 = (() => {
                              {
                                const $t29232_i10245 = (seed * 12.9898);
                                {
                                  const $t29233_i10246 = (1. * 78.233);
                                  return ($t29232_i10245 + $t29233_i10246);
                                }
                              }
                            })();
                            return Math.sin($t29234_i10247);
                          }
                        })();
                        return ($t29235_i10248 * 43758.5453);
                      }
                    })();
                    {
                      const $t29236_i10251 = (() => {
                        {
                          const $t1582_i4059_i10250 = Math.floor(x_i10249);
                          return $t1582_i4059_i10250;
                        }
                      })();
                      return (x_i10249 - $t29236_i10251);
                    }
                  }
                })();
                return ($t29241 * 6.28318530718);
              }
            })();
            {
              const speed = (() => {
                {
                  const $t29244 = (() => {
                    {
                      const $t29243 = (() => {
                        {
                          const x_i10240 = (() => {
                            {
                              const $t29235_i10239 = (() => {
                                {
                                  const $t29234_i10238 = (() => {
                                    {
                                      const $t29232_i10236 = (seed * 12.9898);
                                      {
                                        const $t29233_i10237 = (2. * 78.233);
                                        return ($t29232_i10236 + $t29233_i10237);
                                      }
                                    }
                                  })();
                                  return Math.sin($t29234_i10238);
                                }
                              })();
                              return ($t29235_i10239 * 43758.5453);
                            }
                          })();
                          {
                            const $t29236_i10242 = (() => {
                              {
                                const $t1582_i4059_i10241 = Math.floor(x_i10240);
                                return $t1582_i4059_i10241;
                              }
                            })();
                            return (x_i10240 - $t29236_i10242);
                          }
                        }
                      })();
                      return ($t29243 * 90.);
                    }
                  })();
                  return (40. + $t29244);
                }
              })();
              {
                const life = (() => {
                  {
                    const $t29248 = (() => {
                      {
                        const $t29247 = (() => {
                          {
                            const $t29246 = (() => {
                              {
                                const x_i10231 = (() => {
                                  {
                                    const $t29235_i10230 = (() => {
                                      {
                                        const $t29234_i10229 = (() => {
                                          {
                                            const $t29232_i10227 = (seed * 12.9898);
                                            {
                                              const $t29233_i10228 = (3. * 78.233);
                                              return ($t29232_i10227 + $t29233_i10228);
                                            }
                                          }
                                        })();
                                        return Math.sin($t29234_i10229);
                                      }
                                    })();
                                    return ($t29235_i10230 * 43758.5453);
                                  }
                                })();
                                {
                                  const $t29236_i10233 = (() => {
                                    {
                                      const $t1582_i4059_i10232 = Math.floor(x_i10231);
                                      return $t1582_i4059_i10232;
                                    }
                                  })();
                                  return (x_i10231 - $t29236_i10233);
                                }
                              }
                            })();
                            return (0.4 * $t29246);
                          }
                        })();
                        return (0.6 + $t29247);
                      }
                    })();
                    return (0.5 * $t29248);
                  }
                })();
                {
                  const p = (() => {
                    {
                      const $t29250 = (() => {
                        {
                          const $t29249 = Math.cos(a);
                          return ($t29249 * speed);
                        }
                      })();
                      {
                        const $t29252 = (() => {
                          {
                            const $t29251 = Math.sin(a);
                            return ($t29251 * speed);
                          }
                        })();
                        return ({ x: x, y: y, vx: $t29250, vy: $t29252, life: life, max_life: life });
                      }
                    }
                  })();
                  {
                    const $t29253 = (i + 1);
                    {
                      const $t29254 = { $: "Cons", _0: p, _1: acc };
                      return spawn_burst_particles(x, y, t, $t29253, $t29254);
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
      const $f29257 = bursts._0;
      const $f29258 = bursts._1;
      {
        const rest = (() => {
          return $f29258;
        })();
        {
          const pt = (() => {
            return $f29257;
          })();
          {
            const x = pt._0;
            {
              const y = pt._1;
              {
                const $t29255 = spawn_burst_particles(x, y, t, 0, acc);
                return spawn_bursts(rest, t, $t29255);
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
      const $f29284 = flash._0;
      {
        const f = $f29284;
        {
          const x = f._0;
          {
            const y = f._1;
            {
              const tr = f._2;
              {
                const tr2 = (tr - dt_s);
                {
                  const $t29281 = (tr2 > 0.);
                  if ($t29281 === true) {
                    return (() => {
                      {
                        const $t29282 = { _0: x, _1: y, _2: tr2 };
                        return { $: "Some", _0: $t29282 };
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
        const $t29285 = fx.t;
        return ($t29285 + dt_s);
      }
    })();
    {
      const $t29286 = (() => {
        {
          const $t29860_i4079 = game.phase;
          switch ($t29860_i4079.$) {
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
        if ($t29286 === true) {
          trail2 = (() => {
            {
              const $t29287 = fx.trail;
              {
                const $t29290 = (() => {
                  {
                    const $t29288 = game.ball_x;
                    {
                      const $t29289 = game.ball_y;
                      return { _0: $t29288, _1: $t29289 };
                    }
                  }
                })();
                {
                  const $t29279_i10265 = { $: "Cons", _0: $t29290, _1: $t29287 };
                  {
                    const go_i4074_i10266 = { $: "$Clo_go$4821", _0: go$apply$4821 };
                    {
                      const $t508_i4075_i10267 = { $: "Nil" };
                      return go$apply$4821(go_i4074_i10266, $t29279_i10265, 14, $t508_i4075_i10267);
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
          const $t29291 = game.fx_bursts;
          {
            const $t29292 = fx.particles;
            {
              const $t29293 = (() => {
                return spawn_bursts($t29291, t2, $t29292);
              })();
              {
                const particles2 = (() => {
                  {
                    const $t29274_i10254 = { $: "$Clo_$lam29273$3783", _0: $lam29273$apply$3783, _1: dt_s };
                    {
                      const $t29275_i10258 = (() => {
                        {
                          const f_i4069_i10255 = $t29274_i10254;
                          {
                            const go_i4070_i10256 = { $: "$Clo_go$4819", _0: go$apply$4819, _1: f_i4069_i10255 };
                            {
                              const $t270_i4071_i10257 = { $: "Nil" };
                              return go$apply$4819(go_i4070_i10256, $t29293, $t270_i4071_i10257);
                            }
                          }
                        }
                      })();
                      {
                        const $t29278_i10259 = { $: "$Clo_$lam29276$3784", _0: $lam29276$apply$3784 };
                        {
                          const pred_i4065_i10260 = $t29278_i10259;
                          {
                            const go_i4066_i10261 = { $: "$Clo_go$4817", _0: go$apply$4817, _1: pred_i4065_i10260 };
                            {
                              const $t302_i4067_i10262 = { $: "Nil" };
                              return go$apply$4817(go_i4066_i10261, $t29275_i10258, $t302_i4067_i10262);
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
                      const $t29294 = fx.flash;
                      return step_flash($t29294, dt_s);
                    }
                  })();
                  {
                    const flash2 = (() => {
                      {
                        const $t29295 = game.capture_flash;
                        switch ($t29295.$) {
                          case "None": {
                            return flash1;
                            break;
                          }
                          case "Some": {
                            const $f29299 = $t29295._0;
                            {
                              const pt = (() => {
                                return $f29299;
                              })();
                              {
                                const x = pt._0;
                                {
                                  const y = pt._1;
                                  {
                                    const $t29297 = { _0: x, _1: y, _2: 0.45 };
                                    return { $: "Some", _0: $t29297 };
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
      const $f29309 = trail._0;
      const $f29310 = trail._1;
      {
        const rest = (() => {
          return $f29310;
        })();
        {
          const pt = (() => {
            return $f29309;
          })();
          {
            const x = pt._0;
            {
              const y = pt._1;
              {
                const f = (() => {
                  {
                    const $t29302 = (() => {
                      {
                        const $t29300 = i;
                        {
                          const $t29301 = n;
                          return ($t29300 / $t29301);
                        }
                      }
                    })();
                    return (1. - $t29302);
                  }
                })();
                (() => {
                  {
                    const $t29303 = (f * 0.28);
                    return Canvas$set_global_alpha(ctx, $t29303);
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
                    const $t29305 = (() => {
                      {
                        const $t29304 = (2.5 * f);
                        return (1. + $t29304);
                      }
                    })();
                    return Canvas$arc(ctx, x, y, $t29305, 0., 6.28318530718);
                  }
                })();
                (() => {
                  return Canvas$fill(ctx);
                })();
                {
                  const $t29307 = (i + 1);
                  return draw_trail(ctx, rest, $t29307, n);
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
      const $f29322 = particles._0;
      const $f29323 = particles._1;
      {
        const rest = (() => {
          return $f29323;
        })();
        {
          const p = (() => {
            return $f29322;
          })();
          {
            const f = (() => {
              {
                const $t29315 = p.life;
                {
                  const $t29316 = p.max_life;
                  return ($t29315 / $t29316);
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
                const $t29317 = p.x;
                {
                  const $t29318 = p.y;
                  {
                    const $t29320 = (() => {
                      {
                        const $t29319 = (1.5 * f);
                        return (0.5 + $t29319);
                      }
                    })();
                    return Canvas$arc(ctx, $t29317, $t29318, $t29320, 0., 6.28318530718);
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
      const $f29338 = flash._0;
      {
        const f = (() => {
          return $f29338;
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
                    const $t29329 = (tr / 0.45);
                    return (1. - $t29329);
                  }
                })();
                {
                  const r = (() => {
                    {
                      const $t29330 = (prog * 60.);
                      return (8. + $t29330);
                    }
                  })();
                  (() => {
                    {
                      const $t29332 = (() => {
                        {
                          const $t29331 = (1. - prog);
                          return ($t29331 * 0.7);
                        }
                      })();
                      return Canvas$set_global_alpha(ctx, $t29332);
                    }
                  })();
                  (() => {
                    return Canvas$set_stroke_style(ctx, "#ffffff");
                  })();
                  (() => {
                    {
                      const $t29335 = (() => {
                        {
                          const $t29334 = (() => {
                            {
                              const $t29333 = (1. - prog);
                              return (2.5 * $t29333);
                            }
                          })();
                          return ($t29334 + 0.5);
                        }
                      })();
                      return Canvas$set_line_width(ctx, $t29335);
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
        const $t29343 = (() => {
          {
            const $t29342 = s.x;
            return ($t29342 + 1.);
          }
        })();
        {
          const $t29345 = (() => {
            {
              const $t29344 = s.y;
              return ($t29344 + 1.);
            }
          })();
          {
            const x_i10283 = (() => {
              {
                const $t29235_i10282 = (() => {
                  {
                    const $t29234_i10281 = (() => {
                      {
                        const $t29232_i10279 = ($t29343 * 12.9898);
                        {
                          const $t29233_i10280 = ($t29345 * 78.233);
                          return ($t29232_i10279 + $t29233_i10280);
                        }
                      }
                    })();
                    return Math.sin($t29234_i10281);
                  }
                })();
                return ($t29235_i10282 * 43758.5453);
              }
            })();
            {
              const $t29236_i10285 = (() => {
                {
                  const $t1582_i4059_i10284 = Math.floor(x_i10283);
                  return $t1582_i4059_i10284;
                }
              })();
              return (x_i10283 - $t29236_i10285);
            }
          }
        }
      }
    })();
    {
      const $t29346 = (r < 0.34);
      if ($t29346 === true) {
        return 0;
      } else {
        return (() => {
          {
            const $t29347 = (r < 0.67);
            if ($t29347 === true) {
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
    const $t29366 = (() => {
      {
        const $t29365 = (() => {
          {
            const $t29364 = (() => {
              {
                const $t29361 = (() => {
                  {
                    const $t29360 = s.x;
                    return ($t29360 + 4.);
                  }
                })();
                {
                  const $t29363 = (() => {
                    {
                      const $t29362 = s.y;
                      return ($t29362 + 4.);
                    }
                  })();
                  {
                    const x_i10310 = (() => {
                      {
                        const $t29235_i10309 = (() => {
                          {
                            const $t29234_i10308 = (() => {
                              {
                                const $t29232_i10306 = ($t29361 * 12.9898);
                                {
                                  const $t29233_i10307 = ($t29363 * 78.233);
                                  return ($t29232_i10306 + $t29233_i10307);
                                }
                              }
                            })();
                            return Math.sin($t29234_i10308);
                          }
                        })();
                        return ($t29235_i10309 * 43758.5453);
                      }
                    })();
                    {
                      const $t29236_i10312 = (() => {
                        {
                          const $t1582_i4059_i10311 = Math.floor(x_i10310);
                          return $t1582_i4059_i10311;
                        }
                      })();
                      return (x_i10310 - $t29236_i10312);
                    }
                  }
                }
              }
            })();
            return ($t29364 * 4.);
          }
        })();
        return Math.trunc($t29365);
      }
    })();
    return (2 + $t29366);
  }
}
const dot_count$clo = { _0: ($_, s) => dot_count(s) };

function draw_pulse_ring(ctx, s, pulse) {
  (() => {
    {
      const $t29373 = (0.1 * pulse);
      return Canvas$set_global_alpha(ctx, $t29373);
    }
  })();
  (() => {
    return Canvas$set_stroke_style(ctx, "#cfcfcf");
  })();
  (() => {
    {
      const $t29375 = (() => {
        {
          const $t29374 = (0.6 * pulse);
          return (1. + $t29374);
        }
      })();
      return Canvas$set_line_width(ctx, $t29375);
    }
  })();
  (() => {
    return Canvas$begin_path(ctx);
  })();
  (() => {
    {
      const $t29376 = s.x;
      {
        const $t29377 = s.y;
        {
          const $t29378 = s.capture_radius;
          return Canvas$arc(ctx, $t29376, $t29377, $t29378, 0., 6.28318530718);
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
      const $t29381 = (() => {
        {
          const $t29380 = (0.035 * pulse);
          return (0.025 + $t29380);
        }
      })();
      return Canvas$set_global_alpha(ctx, $t29381);
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
      const $t29382 = s.x;
      {
        const $t29383 = s.y;
        {
          const $t29387 = (() => {
            {
              const $t29384 = s.radius;
              {
                const $t29386 = (() => {
                  {
                    const $t29385 = (0.9 * pulse);
                    return (1.6 + $t29385);
                  }
                })();
                return ($t29384 * $t29386);
              }
            }
          })();
          return Canvas$arc(ctx, $t29382, $t29383, $t29387, 0., 6.28318530718);
        }
      }
    }
  })();
  return Canvas$fill(ctx);
}
const draw_pulse_halo$clo = { _0: ($_, ctx, s, pulse) => draw_pulse_halo(ctx, s, pulse) };

function draw_pulse_particle(ctx, s, t, n, i) {
  {
    const $t29389 = (i >= n);
    if ($t29389 === true) {
      return {  };
    } else {
      return (() => {
        {
          const a = (() => {
            {
              const $t29393 = (() => {
                {
                  const $t29391 = (() => {
                    {
                      const $t29390 = (() => {
                        {
                          const $t29372_i10567 = (() => {
                            {
                              const $t29371_i10566 = (() => {
                                {
                                  const $t29368_i10556 = (() => {
                                    {
                                      const $t29367_i10555 = s.x;
                                      return ($t29367_i10555 + 5.);
                                    }
                                  })();
                                  {
                                    const $t29370_i10558 = (() => {
                                      {
                                        const $t29369_i10557 = s.y;
                                        return ($t29369_i10557 + 5.);
                                      }
                                    })();
                                    {
                                      const x_i10319_i10563 = (() => {
                                        {
                                          const $t29235_i10318_i10562 = (() => {
                                            {
                                              const $t29234_i10317_i10561 = (() => {
                                                {
                                                  const $t29232_i10315_i10559 = ($t29368_i10556 * 12.9898);
                                                  {
                                                    const $t29233_i10316_i10560 = ($t29370_i10558 * 78.233);
                                                    return ($t29232_i10315_i10559 + $t29233_i10316_i10560);
                                                  }
                                                }
                                              })();
                                              return Math.sin($t29234_i10317_i10561);
                                            }
                                          })();
                                          return ($t29235_i10318_i10562 * 43758.5453);
                                        }
                                      })();
                                      {
                                        const $t29236_i10321_i10565 = (() => {
                                          {
                                            const $t1582_i4059_i10320_i10564 = Math.floor(x_i10319_i10563);
                                            return $t1582_i4059_i10320_i10564;
                                          }
                                        })();
                                        return (x_i10319_i10563 - $t29236_i10321_i10565);
                                      }
                                    }
                                  }
                                }
                              })();
                              return ($t29371_i10566 * 2.4);
                            }
                          })();
                          return (0.4 + $t29372_i10567);
                        }
                      })();
                      return (t * $t29390);
                    }
                  })();
                  {
                    const $t29392 = (() => {
                      {
                        const $t29358_i10553 = (() => {
                          {
                            const $t29355_i10543 = (() => {
                              {
                                const $t29354_i10542 = s.x;
                                return ($t29354_i10542 + 3.);
                              }
                            })();
                            {
                              const $t29357_i10545 = (() => {
                                {
                                  const $t29356_i10544 = s.y;
                                  return ($t29356_i10544 + 3.);
                                }
                              })();
                              {
                                const x_i10301_i10550 = (() => {
                                  {
                                    const $t29235_i10300_i10549 = (() => {
                                      {
                                        const $t29234_i10299_i10548 = (() => {
                                          {
                                            const $t29232_i10297_i10546 = ($t29355_i10543 * 12.9898);
                                            {
                                              const $t29233_i10298_i10547 = ($t29357_i10545 * 78.233);
                                              return ($t29232_i10297_i10546 + $t29233_i10298_i10547);
                                            }
                                          }
                                        })();
                                        return Math.sin($t29234_i10299_i10548);
                                      }
                                    })();
                                    return ($t29235_i10300_i10549 * 43758.5453);
                                  }
                                })();
                                {
                                  const $t29236_i10303_i10552 = (() => {
                                    {
                                      const $t1582_i4059_i10302_i10551 = Math.floor(x_i10301_i10550);
                                      return $t1582_i4059_i10302_i10551;
                                    }
                                  })();
                                  return (x_i10301_i10550 - $t29236_i10303_i10552);
                                }
                              }
                            }
                          }
                        })();
                        return ($t29358_i10553 * 6.28318530718);
                      }
                    })();
                    return ($t29391 + $t29392);
                  }
                }
              })();
              {
                const $t29398 = (() => {
                  {
                    const $t29394 = i;
                    {
                      const $t29397 = (() => {
                        {
                          const $t29396 = n;
                          return (6.28318530718 / $t29396);
                        }
                      })();
                      return ($t29394 * $t29397);
                    }
                  }
                })();
                return ($t29393 + $t29398);
              }
            }
          })();
          {
            const r = (() => {
              {
                const $t29399 = s.radius;
                return ($t29399 * 1.8);
              }
            })();
            {
              const px = (() => {
                {
                  const $t29400 = s.x;
                  {
                    const $t29402 = (() => {
                      {
                        const $t29401 = Math.cos(a);
                        return ($t29401 * r);
                      }
                    })();
                    return ($t29400 + $t29402);
                  }
                }
              })();
              {
                const py = (() => {
                  {
                    const $t29403 = s.y;
                    {
                      const $t29405 = (() => {
                        {
                          const $t29404 = Math.sin(a);
                          return ($t29404 * r);
                        }
                      })();
                      return ($t29403 + $t29405);
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
                  const $t29407 = (i + 1);
                  return draw_pulse_particle(ctx, s, t, n, $t29407);
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
      const $f29416 = orbits._0;
      const $f29417 = orbits._1;
      {
        const $jp_clo29423 = (() => {
          return { $: "$Clo_$jp29422$3787", _0: $jp29422$apply$3787, _1: $f29416, _2: $f29417, _3: ctx, _4: s };
        })();
        switch ($f29417.$) {
          case "Nil": {
            {
              const o = $f29416;
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
                  const $t29408 = s.x;
                  {
                    const $t29409 = s.y;
                    {
                      const $t29410 = o.radius;
                      return Canvas$arc(ctx, $t29408, $t29409, $t29410, 0., 6.28318530718);
                    }
                  }
                }
              })();
              return Canvas$stroke(ctx);
            }
            break;
          }
          default: {
            return $jp29422$apply$3787($jp_clo29423);
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
      const $f29439 = aim._0;
      {
        const a = (() => {
          return $f29439;
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
                      const $t29426 = s.x;
                      return ($t29426 - px);
                    }
                  })();
                  {
                    const dy = (() => {
                      {
                        const $t29427 = s.y;
                        return ($t29427 - py);
                      }
                    })();
                    {
                      const range = (() => {
                        {
                          const $t29428 = s.capture_radius;
                          return ($t29428 * 4.);
                        }
                      })();
                      {
                        const $t29432 = (() => {
                          {
                            const $t29431 = (() => {
                              {
                                const $t29429 = (vx * dx);
                                {
                                  const $t29430 = (vy * dy);
                                  return ($t29429 + $t29430);
                                }
                              }
                            })();
                            return ($t29431 > 0.);
                          }
                        })();
                        {
                          const $t29437 = (() => {
                            {
                              const $t29435 = (() => {
                                {
                                  const $t29433 = (dx * dx);
                                  {
                                    const $t29434 = (dy * dy);
                                    return ($t29433 + $t29434);
                                  }
                                }
                              })();
                              {
                                const $t29436 = (range * range);
                                return ($t29435 < $t29436);
                              }
                            }
                          })();
                          return ($t29432 && $t29437);
                        }
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
        const $t29442 = (() => {
          {
            const $t29441 = (() => {
              {
                const $t29440 = (t * 6.);
                return Math.sin($t29440);
              }
            })();
            return (0.5 * $t29441);
          }
        })();
        return (0.5 + $t29442);
      }
    })();
    (() => {
      {
        const $t29444 = (() => {
          {
            const $t29443 = (0.45 * pulse);
            return (0.3 + $t29443);
          }
        })();
        return Canvas$set_global_alpha(ctx, $t29444);
      }
    })();
    (() => {
      return Canvas$set_stroke_style(ctx, "#ffffff");
    })();
    (() => {
      {
        const $t29446 = (() => {
          {
            const $t29445 = (1.6 * pulse);
            return (1.2 + $t29445);
          }
        })();
        return Canvas$set_line_width(ctx, $t29446);
      }
    })();
    (() => {
      return Canvas$begin_path(ctx);
    })();
    (() => {
      {
        const $t29447 = s.x;
        {
          const $t29448 = s.y;
          {
            const $t29449 = s.capture_radius;
            return Canvas$arc(ctx, $t29447, $t29448, $t29449, 0., 6.28318530718);
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
      const $t29451 = s.orbits;
      return draw_orbit_rings(ctx, s, $t29451);
    }
  })();
  (() => {
    {
      const $t29452 = (() => {
        {
          const $t29341_i10605 = (() => {
            {
              const $t29339_i10596 = s.x;
              {
                const $t29340_i10597 = s.y;
                {
                  const x_i10274_i10602 = (() => {
                    {
                      const $t29235_i10273_i10601 = (() => {
                        {
                          const $t29234_i10272_i10600 = (() => {
                            {
                              const $t29232_i10270_i10598 = ($t29339_i10596 * 12.9898);
                              {
                                const $t29233_i10271_i10599 = ($t29340_i10597 * 78.233);
                                return ($t29232_i10270_i10598 + $t29233_i10271_i10599);
                              }
                            }
                          })();
                          return Math.sin($t29234_i10272_i10600);
                        }
                      })();
                      return ($t29235_i10273_i10601 * 43758.5453);
                    }
                  })();
                  {
                    const $t29236_i10276_i10604 = (() => {
                      {
                        const $t1582_i4059_i10275_i10603 = Math.floor(x_i10274_i10602);
                        return $t1582_i4059_i10275_i10603;
                      }
                    })();
                    return (x_i10274_i10602 - $t29236_i10276_i10604);
                  }
                }
              }
            }
          })();
          return ($t29341_i10605 < 0.8);
        }
      })();
      if ($t29452 === true) {
        return (() => {
          {
            const pulse = (() => {
              {
                const $t29458 = (() => {
                  {
                    const $t29457 = (() => {
                      {
                        const $t29456 = (() => {
                          {
                            const $t29454 = (() => {
                              {
                                const $t29453 = (() => {
                                  {
                                    const $t29353_i10594 = (() => {
                                      {
                                        const $t29352_i10593 = (() => {
                                          {
                                            const $t29349_i10583 = (() => {
                                              {
                                                const $t29348_i10582 = s.x;
                                                return ($t29348_i10582 + 2.);
                                              }
                                            })();
                                            {
                                              const $t29351_i10585 = (() => {
                                                {
                                                  const $t29350_i10584 = s.y;
                                                  return ($t29350_i10584 + 2.);
                                                }
                                              })();
                                              {
                                                const x_i10292_i10590 = (() => {
                                                  {
                                                    const $t29235_i10291_i10589 = (() => {
                                                      {
                                                        const $t29234_i10290_i10588 = (() => {
                                                          {
                                                            const $t29232_i10288_i10586 = ($t29349_i10583 * 12.9898);
                                                            {
                                                              const $t29233_i10289_i10587 = ($t29351_i10585 * 78.233);
                                                              return ($t29232_i10288_i10586 + $t29233_i10289_i10587);
                                                            }
                                                          }
                                                        })();
                                                        return Math.sin($t29234_i10290_i10588);
                                                      }
                                                    })();
                                                    return ($t29235_i10291_i10589 * 43758.5453);
                                                  }
                                                })();
                                                {
                                                  const $t29236_i10294_i10592 = (() => {
                                                    {
                                                      const $t1582_i4059_i10293_i10591 = Math.floor(x_i10292_i10590);
                                                      return $t1582_i4059_i10293_i10591;
                                                    }
                                                  })();
                                                  return (x_i10292_i10590 - $t29236_i10294_i10592);
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        return ($t29352_i10593 * 1.8);
                                      }
                                    })();
                                    return (0.6 + $t29353_i10594);
                                  }
                                })();
                                return (t * $t29453);
                              }
                            })();
                            {
                              const $t29455 = (() => {
                                {
                                  const $t29358_i10580 = (() => {
                                    {
                                      const $t29355_i10570 = (() => {
                                        {
                                          const $t29354_i10569 = s.x;
                                          return ($t29354_i10569 + 3.);
                                        }
                                      })();
                                      {
                                        const $t29357_i10572 = (() => {
                                          {
                                            const $t29356_i10571 = s.y;
                                            return ($t29356_i10571 + 3.);
                                          }
                                        })();
                                        {
                                          const x_i10301_i10577 = (() => {
                                            {
                                              const $t29235_i10300_i10576 = (() => {
                                                {
                                                  const $t29234_i10299_i10575 = (() => {
                                                    {
                                                      const $t29232_i10297_i10573 = ($t29355_i10570 * 12.9898);
                                                      {
                                                        const $t29233_i10298_i10574 = ($t29357_i10572 * 78.233);
                                                        return ($t29232_i10297_i10573 + $t29233_i10298_i10574);
                                                      }
                                                    }
                                                  })();
                                                  return Math.sin($t29234_i10299_i10575);
                                                }
                                              })();
                                              return ($t29235_i10300_i10576 * 43758.5453);
                                            }
                                          })();
                                          {
                                            const $t29236_i10303_i10579 = (() => {
                                              {
                                                const $t1582_i4059_i10302_i10578 = Math.floor(x_i10301_i10577);
                                                return $t1582_i4059_i10302_i10578;
                                              }
                                            })();
                                            return (x_i10301_i10577 - $t29236_i10303_i10579);
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  return ($t29358_i10580 * 6.28318530718);
                                }
                              })();
                              return ($t29454 + $t29455);
                            }
                          }
                        })();
                        return Math.sin($t29456);
                      }
                    })();
                    return (0.5 * $t29457);
                  }
                })();
                return (0.5 + $t29458);
              }
            })();
            {
              const $t29459 = pulse_style(s);
              if ($t29459 === 0) {
                return (() => {
                  {
                    const $jp_clo29462 = (() => {
                      return { $: "$Clo_$jp29461$3790", _0: $jp29461$apply$3790, _1: ctx, _2: s, _3: t };
                    })();
                    return draw_pulse_ring(ctx, s, pulse);
                  }
                })();
              } else if ($t29459 === 1) {
                return (() => {
                  {
                    const $jp_clo29464 = (() => {
                      return { $: "$Clo_$jp29463$3791", _0: $jp29463$apply$3791, _1: ctx, _2: s, _3: t };
                    })();
                    return draw_pulse_halo(ctx, s, pulse);
                  }
                })();
              } else {
                return (() => {
                  {
                    const $t29460 = dot_count(s);
                    return draw_pulse_particle(ctx, s, t, $t29460, 0);
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
      const $t29465 = star_targeted(s, aim);
      if ($t29465 === true) {
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
      const $t29466 = s.x;
      {
        const $t29467 = s.y;
        {
          const $t29468 = s.radius;
          return Canvas$arc(ctx, $t29466, $t29467, $t29468, 0., 6.28318530718);
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
            const $t29476 = (() => {
              {
                const $t29475 = (seed * 37.719);
                return (fx + $t29475);
              }
            })();
            {
              const $t29478 = (() => {
                {
                  const $t29477 = (seed * 12.9898);
                  return (fy - $t29477);
                }
              })();
              {
                const x_i10346 = (() => {
                  {
                    const $t29473_i10345 = (() => {
                      {
                        const $t29472_i10344 = (() => {
                          {
                            const $t29470_i10342 = ($t29476 * 12.9898);
                            {
                              const $t29471_i10343 = ($t29478 * 78.233);
                              return ($t29470_i10342 + $t29471_i10343);
                            }
                          }
                        })();
                        return Math.sin($t29472_i10344);
                      }
                    })();
                    return ($t29473_i10345 * 43758.5453);
                  }
                })();
                {
                  const $t29474_i10348 = (() => {
                    {
                      const $t1582_i4090_i10347 = Math.floor(x_i10346);
                      return $t1582_i4090_i10347;
                    }
                  })();
                  return (x_i10346 - $t29474_i10348);
                }
              }
            }
          }
        })();
        {
          const h2 = (() => {
            {
              const $t29481 = (() => {
                {
                  const $t29479 = (fy * 3.271);
                  {
                    const $t29480 = (seed * 71.238);
                    return ($t29479 - $t29480);
                  }
                }
              })();
              {
                const $t29484 = (() => {
                  {
                    const $t29482 = (fx * 1.373);
                    {
                      const $t29483 = (seed * 5.113);
                      return ($t29482 + $t29483);
                    }
                  }
                })();
                {
                  const x_i10337 = (() => {
                    {
                      const $t29473_i10336 = (() => {
                        {
                          const $t29472_i10335 = (() => {
                            {
                              const $t29470_i10333 = ($t29481 * 12.9898);
                              {
                                const $t29471_i10334 = ($t29484 * 78.233);
                                return ($t29470_i10333 + $t29471_i10334);
                              }
                            }
                          })();
                          return Math.sin($t29472_i10335);
                        }
                      })();
                      return ($t29473_i10336 * 43758.5453);
                    }
                  })();
                  {
                    const $t29474_i10339 = (() => {
                      {
                        const $t1582_i4090_i10338 = Math.floor(x_i10337);
                        return $t1582_i4090_i10338;
                      }
                    })();
                    return (x_i10337 - $t29474_i10339);
                  }
                }
              }
            }
          })();
          {
            const $t29487 = (() => {
              {
                const $t29485 = (h1 * 269.5);
                {
                  const $t29486 = (h2 * 183.3);
                  return ($t29485 + $t29486);
                }
              }
            })();
            {
              const $t29491 = (() => {
                {
                  const $t29490 = (() => {
                    {
                      const $t29488 = (fx * 0.618);
                      {
                        const $t29489 = (fy * 0.573);
                        return ($t29488 + $t29489);
                      }
                    }
                  })();
                  return ($t29490 + seed);
                }
              })();
              {
                const x_i10328 = (() => {
                  {
                    const $t29473_i10327 = (() => {
                      {
                        const $t29472_i10326 = (() => {
                          {
                            const $t29470_i10324 = ($t29487 * 12.9898);
                            {
                              const $t29471_i10325 = ($t29491 * 78.233);
                              return ($t29470_i10324 + $t29471_i10325);
                            }
                          }
                        })();
                        return Math.sin($t29472_i10326);
                      }
                    })();
                    return ($t29473_i10327 * 43758.5453);
                  }
                })();
                {
                  const $t29474_i10330 = (() => {
                    {
                      const $t1582_i4090_i10329 = Math.floor(x_i10328);
                      return $t1582_i4090_i10329;
                    }
                  })();
                  return (x_i10328 - $t29474_i10330);
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
      const $t29493 = (h > 0.5);
      if ($t29493 === true) {
        return {  };
      } else {
        return (() => {
          {
            const jx = (() => {
              {
                const $t29494 = (gy + 1000);
                return bg_hash(gx, $t29494, seed);
              }
            })();
            {
              const jy = (() => {
                {
                  const $t29495 = (gx + 1000);
                  return bg_hash($t29495, gy, seed);
                }
              })();
              {
                const x = (() => {
                  {
                    const $t29497 = (() => {
                      {
                        const $t29496 = gx;
                        return ($t29496 * cell);
                      }
                    })();
                    {
                      const $t29498 = (jx * cell);
                      return ($t29497 + $t29498);
                    }
                  }
                })();
                {
                  const y = (() => {
                    {
                      const $t29500 = (() => {
                        {
                          const $t29499 = gy;
                          return ($t29499 * cell);
                        }
                      })();
                      {
                        const $t29501 = (jy * cell);
                        return ($t29500 + $t29501);
                      }
                    }
                  })();
                  {
                    const br = (() => {
                      {
                        const $t29505 = (() => {
                          {
                            const $t29504 = (() => {
                              {
                                const $t29502 = (gx + 2000);
                                {
                                  const $t29503 = (gy + 2000);
                                  return bg_hash($t29502, $t29503, seed);
                                }
                              }
                            })();
                            return (0.45 * $t29504);
                          }
                        })();
                        return (0.12 + $t29505);
                      }
                    })();
                    {
                      const st = (() => {
                        {
                          const $t29506 = (gx - 2000);
                          {
                            const $t29507 = (gy - 2000);
                            return bg_hash($t29506, $t29507, seed);
                          }
                        }
                      })();
                      {
                        const sz = (() => {
                          {
                            const $t29509 = (() => {
                              {
                                const $t29508 = (1.8 * st);
                                return ($t29508 * st);
                              }
                            })();
                            return (1. + $t29509);
                          }
                        })();
                        {
                          const is_pulsing = (() => {
                            {
                              const $t29512 = (() => {
                                {
                                  const $t29510 = (gx + 3000);
                                  {
                                    const $t29511 = (gy + 3000);
                                    return bg_hash($t29510, $t29511, seed);
                                  }
                                }
                              })();
                              return ($t29512 < 0.04);
                            }
                          })();
                          {
                            let pulse;
                            if (is_pulsing === true) {
                              pulse = (() => {
                                {
                                  const speed = (() => {
                                    {
                                      const $t29516 = (() => {
                                        {
                                          const $t29515 = (() => {
                                            {
                                              const $t29514 = (gx + 4000);
                                              return bg_hash($t29514, gy, seed);
                                            }
                                          })();
                                          return (0.45 * $t29515);
                                        }
                                      })();
                                      return (0.35 + $t29516);
                                    }
                                  })();
                                  {
                                    const phase = (() => {
                                      {
                                        const $t29518 = (() => {
                                          {
                                            const $t29517 = (gy + 4000);
                                            return bg_hash(gx, $t29517, seed);
                                          }
                                        })();
                                        return ($t29518 * 6.28318530718);
                                      }
                                    })();
                                    {
                                      const $t29523 = (() => {
                                        {
                                          const $t29522 = (() => {
                                            {
                                              const $t29521 = (() => {
                                                {
                                                  const $t29520 = (t * speed);
                                                  return ($t29520 + phase);
                                                }
                                              })();
                                              return Math.sin($t29521);
                                            }
                                          })();
                                          return (0.5 * $t29522);
                                        }
                                      })();
                                      return (0.5 + $t29523);
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
                                    const $t29526 = (() => {
                                      {
                                        const $t29525 = (() => {
                                          {
                                            const $t29524 = (1. - br);
                                            return ($t29524 * 0.6);
                                          }
                                        })();
                                        return ($t29525 * pulse);
                                      }
                                    })();
                                    return (br + $t29526);
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
                                      const $t29528 = (() => {
                                        {
                                          const $t29527 = (0.35 * pulse);
                                          return (1. + $t29527);
                                        }
                                      })();
                                      return (sz * $t29528);
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
    const $t29530 = (gx > gx_max);
    if ($t29530 === true) {
      return {  };
    } else {
      return (() => {
        (() => {
          return draw_bg_cell(ctx, gx, gy, cell, seed, t);
        })();
        {
          const $t29531 = (gx + 1);
          return draw_bg_row(ctx, $t29531, gx_max, gy, cell, seed, t);
        }
      })();
    }
  }
}
const draw_bg_row$clo = { _0: ($_, ctx, gx, gx_max, gy, cell, seed, t) => draw_bg_row(ctx, gx, gx_max, gy, cell, seed, t) };

function draw_bg_rows(ctx, gx0, gx1, gy, gy_max, cell, seed, t) {
  {
    const $t29532 = (gy > gy_max);
    if ($t29532 === true) {
      return {  };
    } else {
      return (() => {
        (() => {
          return draw_bg_row(ctx, gx0, gx1, gy, cell, seed, t);
        })();
        {
          const $t29533 = (gy + 1);
          return draw_bg_rows(ctx, gx0, gx1, $t29533, gy_max, cell, seed, t);
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
        const $t29536 = (() => {
          {
            const $t29535 = (() => {
              {
                const $t29534 = (cam_x / 70.);
                {
                  const $t1582_i4100 = Math.floor($t29534);
                  return $t1582_i4100;
                }
              }
            })();
            return Math.trunc($t29535);
          }
        })();
        return ($t29536 - 1);
      }
    })();
    {
      const gx1 = (() => {
        {
          const $t29540 = (() => {
            {
              const $t29539 = (() => {
                {
                  const $t29538 = (() => {
                    {
                      const $t29537 = (cam_x + view_w);
                      return ($t29537 / 70.);
                    }
                  })();
                  {
                    const $t1582_i4098 = Math.floor($t29538);
                    return $t1582_i4098;
                  }
                }
              })();
              return Math.trunc($t29539);
            }
          })();
          return ($t29540 + 1);
        }
      })();
      {
        const gy0 = (() => {
          {
            const $t29543 = (() => {
              {
                const $t29542 = (() => {
                  {
                    const $t29541 = (cam / 70.);
                    {
                      const $t1582_i4096 = Math.floor($t29541);
                      return $t1582_i4096;
                    }
                  }
                })();
                return Math.trunc($t29542);
              }
            })();
            return ($t29543 - 1);
          }
        })();
        {
          const gy1 = (() => {
            {
              const $t29547 = (() => {
                {
                  const $t29546 = (() => {
                    {
                      const $t29545 = (() => {
                        {
                          const $t29544 = (cam + view_h);
                          return ($t29544 / 70.);
                        }
                      })();
                      {
                        const $t1582_i4094 = Math.floor($t29545);
                        return $t1582_i4094;
                      }
                    }
                  })();
                  return Math.trunc($t29546);
                }
              })();
              return ($t29547 + 1);
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
      const $f29554 = clouds._0;
      const $f29555 = clouds._1;
      {
        const rest = (() => {
          return $f29555;
        })();
        {
          const c = (() => {
            return $f29554;
          })();
          (() => {
            {
              const $t29548 = c.x;
              {
                const $t29549 = c.y;
                {
                  const $t29550 = c.radius;
                  {
                    const $t29553 = (() => {
                      {
                        const $t29552 = c.strength;
                        return (0.16 * $t29552);
                      }
                    })();
                    return Canvas$fill_noise_circle(ctx, $t29548, $t29549, $t29550, $t29553);
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
    const $t29560 = (() => {
      {
        const margin_i10353 = (700. + 90.);
        {
          const $t29164_i10354 = { $: "Nil" };
          {
            const $t29165_i10355 = Perihelion$Nebula$filter_visible(stars, cam, view_h, margin_i10353, $t29164_i10354);
            {
              const $t29166_i10356 = { $: "Nil" };
              return Perihelion$Nebula$collect_star_clouds($t29165_i10355, seed, $t29166_i10356);
            }
          }
        }
      }
    })();
    {
      const $rc_837 = draw_nebula_clouds(ctx, $t29560);
      return $rc_837;
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
      const $f29569 = stars._0;
      const $f29570 = stars._1;
      {
        const rest = $f29570;
        {
          const s = $f29569;
          (() => {
            {
              const $t29568 = (() => {
                {
                  const $t29564 = (() => {
                    {
                      const $t29561 = s.y;
                      {
                        const $t29563 = (() => {
                          {
                            const $t29562 = (cam + view_h);
                            return ($t29562 + 100.);
                          }
                        })();
                        return ($t29561 < $t29563);
                      }
                    }
                  })();
                  {
                    const $t29567 = (() => {
                      {
                        const $t29565 = s.y;
                        {
                          const $t29566 = (cam - 100.);
                          return ($t29565 > $t29566);
                        }
                      }
                    })();
                    return ($t29564 && $t29567);
                  }
                }
              })();
              if ($t29568 === true) {
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
        const $t29581 = i;
        {
          const $t29583 = (6.28318530718 / 8.);
          return ($t29581 * $t29583);
        }
      }
    })();
    {
      const jitter = (() => {
        {
          const $t29586 = (() => {
            {
              const $t29585 = (() => {
                {
                  const $t29584 = a.shape_seed;
                  {
                    const x_i10364 = (() => {
                      {
                        const $t29579_i10363 = (() => {
                          {
                            const $t29578_i10362 = (() => {
                              {
                                const $t29575_i10359 = ($t29584 * 12.9898);
                                {
                                  const $t29577_i10361 = (() => {
                                    {
                                      const $t29576_i10360 = i;
                                      return ($t29576_i10360 * 78.233);
                                    }
                                  })();
                                  return ($t29575_i10359 + $t29577_i10361);
                                }
                              }
                            })();
                            return Math.sin($t29578_i10362);
                          }
                        })();
                        return ($t29579_i10363 * 43758.5453);
                      }
                    })();
                    {
                      const $t29580_i10366 = (() => {
                        {
                          const $t1582_i4104_i10365 = Math.floor(x_i10364);
                          return $t1582_i4104_i10365;
                        }
                      })();
                      return (x_i10364 - $t29580_i10366);
                    }
                  }
                }
              })();
              return (0.6 * $t29585);
            }
          })();
          return (0.7 + $t29586);
        }
      })();
      {
        const r = (() => {
          {
            const $t29587 = a.radius;
            return ($t29587 * jitter);
          }
        })();
        {
          const pt = (() => {
            {
              const $t29591 = (() => {
                {
                  const $t29588 = a.x;
                  {
                    const $t29590 = (() => {
                      {
                        const $t29589 = Math.cos(angle);
                        return ($t29589 * r);
                      }
                    })();
                    return ($t29588 + $t29590);
                  }
                }
              })();
              {
                const $t29595 = (() => {
                  {
                    const $t29592 = a.y;
                    {
                      const $t29594 = (() => {
                        {
                          const $t29593 = Math.sin(angle);
                          return ($t29593 * r);
                        }
                      })();
                      return ($t29592 + $t29594);
                    }
                  }
                })();
                return { _0: $t29591, _1: $t29595 };
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
    const $t29596 = (i > 7);
    if ($t29596 === true) {
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
                      const $jp_clo29598 = (() => {
                        return { $: "$Clo_$jp29597$3794", _0: $jp29597$apply$3794, _1: ctx, _2: px, _3: py };
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
                const $t29599 = (i + 1);
                return draw_asteroid_edges(ctx, a, $t29599);
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
      const $f29608 = asteroids._0;
      const $f29609 = asteroids._1;
      {
        const rest = (() => {
          return $f29609;
        })();
        {
          const a = (() => {
            return $f29608;
          })();
          {
            const color = (() => {
              {
                const $t29601 = a.mode;
                switch ($t29601.$) {
                  case "AsteroidDrifting": {
                    return "#8a8a94";
                    break;
                  }
                  case "AsteroidOrbiting": {
                    const $f29602 = $t29601._0;
                    const $f29603 = $t29601._1;
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
      const $f29617 = shots._0;
      const $f29618 = shots._1;
      {
        const rest = (() => {
          return $f29618;
        })();
        {
          const s = (() => {
            return $f29617;
          })();
          (() => {
            return Canvas$set_fill_style(ctx, color);
          })();
          (() => {
            return Canvas$begin_path(ctx);
          })();
          (() => {
            {
              const $t29614 = s.x;
              {
                const $t29615 = s.y;
                return Canvas$arc(ctx, $t29614, $t29615, r, 0., 6.28318530718);
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
    const $t29623 = sh.mode;
    switch ($t29623.$) {
      case "ShipOrbiting": {
        const $f29627 = $t29623._0;
        {
          const angle = (() => {
            return $f29627;
          })();
          {
            const d = (0. - 1.);
            {
              const $t29626 = (d * 1.5707963);
              return (angle + $t29626);
            }
          }
        }
        break;
      }
      case "ShipFlying": {
        const $f29628 = $t29623._0;
        const $f29629 = $t29623._1;
        {
          const vy = (() => {
            return $f29629;
          })();
          {
            const vx = (() => {
              return $f29628;
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
      const $f29638 = ships._0;
      const $f29639 = ships._1;
      {
        const rest = (() => {
          return $f29639;
        })();
        {
          const sh = (() => {
            return $f29638;
          })();
          {
            const pos = (() => {
              {
                const pos_i4119 = (() => {
                  {
                    const $t27355_i4117 = sh.x;
                    {
                      const $t27356_i4118 = sh.y;
                      return { _0: $t27355_i4117, _1: $t27356_i4118 };
                    }
                  }
                })();
                return pos_i4119;
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
                      const $t29634 = (0. - 6.);
                      return Canvas$line_to(ctx, $t29634, 5.);
                    }
                  })();
                  (() => {
                    {
                      const $t29635 = (0. - 6.);
                      {
                        const $t29636 = (0. - 5.);
                        return Canvas$line_to(ctx, $t29635, $t29636);
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
      const $f29647 = pickups._0;
      const $f29648 = pickups._1;
      {
        const rest = (() => {
          return $f29648;
        })();
        {
          const pk = (() => {
            return $f29647;
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
              const $t29644 = pk.x;
              {
                const $t29645 = pk.y;
                return Canvas$arc(ctx, $t29644, $t29645, 8., 0., 6.28318530718);
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
    const $t29653 = (i >= 5);
    if ($t29653 === true) {
      return {  };
    } else {
      return (() => {
        switch (runs.$) {
          case "Nil": {
            return {  };
            break;
          }
          case "Cons": {
            const $f29668 = runs._0;
            const $f29669 = runs._1;
            {
              const rest = (() => {
                return $f29669;
              })();
              {
                const r = (() => {
                  return $f29668;
                })();
                (() => {
                  return Canvas$set_font(ctx, "14px sans-serif");
                })();
                (() => {
                  {
                    const $t29664 = (() => {
                      {
                        const $t29663 = (() => {
                          {
                            const $t29660 = (() => {
                              {
                                const $t29659 = (() => {
                                  {
                                    const $t29656 = (() => {
                                      {
                                        const $t29655 = (() => {
                                          {
                                            const $t29654 = r.score;
                                            return String($t29654);
                                          }
                                        })();
                                        {
                                          const $rc_842 = ($t29655 + " x");
                                          return $rc_842;
                                        }
                                      }
                                    })();
                                    {
                                      const $t29658 = (() => {
                                        {
                                          const $t29657 = r.max_mult;
                                          return String($t29657);
                                        }
                                      })();
                                      {
                                        const $rc_841 = ($t29656 + $t29658);
                                        return $rc_841;
                                      }
                                    }
                                  }
                                })();
                                {
                                  const $rc_840 = ($t29659 + " · ");
                                  return $rc_840;
                                }
                              }
                            })();
                            {
                              const $t29662 = (() => {
                                {
                                  const $t29661 = r.stars;
                                  return String($t29661);
                                }
                              })();
                              {
                                const $rc_839 = ($t29660 + $t29662);
                                return $rc_839;
                              }
                            }
                          }
                        })();
                        {
                          const $rc_838 = ($t29663 + " stars");
                          return $rc_838;
                        }
                      }
                    })();
                    {
                      const $t29665 = (view_w / 2.);
                      return Canvas$fill_text(ctx, $t29664, $t29665, y);
                    }
                  }
                })();
                {
                  const $t29666 = (y + 20.);
                  {
                    const $t29667 = (i + 1);
                    return draw_runs(ctx, rest, view_w, $t29666, $t29667);
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
      const $t29674 = game.ball_x;
      {
        const $t29675 = game.ball_y;
        return Canvas$arc(ctx, $t29674, $t29675, 6., 0., 6.28318530718);
      }
    }
  })();
  (() => {
    return Canvas$fill(ctx);
  })();
  {
    const $t29678 = (() => {
      {
        const $t29677 = game.shield;
        return ($t29677 > 0);
      }
    })();
    if ($t29678 === true) {
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
            const $t29679 = game.ball_x;
            {
              const $t29680 = game.ball_y;
              return Canvas$arc(ctx, $t29679, $t29680, 10., 0., 6.28318530718);
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

function draw_milestone_card(ctx, u, cx, view_h) {
  (() => {
    return Canvas$set_stroke_style(ctx, "#ffffff");
  })();
  (() => {
    return Canvas$set_line_width(ctx, 2.);
  })();
  (() => {
    {
      const $t29684 = (cx - 60.);
      {
        const $t29686 = (() => {
          {
            const $t29685 = (view_h / 2.);
            return ($t29685 - 60.);
          }
        })();
        return Canvas$stroke_rect(ctx, $t29684, $t29686, 120., 120.);
      }
    }
  })();
  (() => {
    return Canvas$set_text_align(ctx, "center");
  })();
  (() => {
    return Canvas$set_font(ctx, "14px sans-serif");
  })();
  {
    let $t29687;
    switch (u.$) {
      case "OffenseWeapon": {
        const $f29682_i10368 = u._0;
        $t29687 = (() => {
          switch ($f29682_i10368.$) {
            case "Homing": {
              return "Homing Missiles";
              break;
            }
            case "Spread": {
              return "Spread Fire";
              break;
            }
            case "StarKiller": {
              return "Star Killer";
              break;
            }
            case "Base": {
              return "Base Weapon";
              break;
            }
            default: {
              return (() => { throw new Error("non-exhaustive pattern match"); })();
            }
          }
        })();
        break;
      }
      case "OffenseFireRate": {
        $t29687 = "Faster Fire";
        break;
      }
      case "DefenseBulletWard": {
        $t29687 = "Bullet Ward";
        break;
      }
      case "DefenseDeflector": {
        $t29687 = "Deflector Plating";
        break;
      }
      case "DefenseShield": {
        $t29687 = "Reinforced Shield";
        break;
      }
      case "SpecialItem": {
        const $f29683_i10369 = u._0;
        $t29687 = (() => {
          switch ($f29683_i10369.$) {
            case "StarThrust": {
              return "Star Thrust";
              break;
            }
            case "StarJump": {
              return "Star Jump";
              break;
            }
            case "TrajectoryPreview": {
              return "Trajectory Preview";
              break;
            }
            default: {
              return (() => { throw new Error("non-exhaustive pattern match"); })();
            }
          }
        })();
        break;
      }
      default: {
        $t29687 = (() => { throw new Error("non-exhaustive pattern match"); })();
        break;
      }
    }
    {
      const $t29688 = (view_h / 2.);
      return Canvas$fill_text(ctx, $t29687, cx, $t29688);
    }
  }
}
const draw_milestone_card$clo = { _0: ($_, ctx, u, cx, view_h) => draw_milestone_card(ctx, u, cx, view_h) };

function draw_milestone_cards(ctx, choices, view_w, view_h, i) {
  switch (choices.$) {
    case "Nil": {
      return {  };
      break;
    }
    case "Cons": {
      const $f29693 = choices._0;
      const $f29694 = choices._1;
      {
        const rest = (() => {
          return $f29694;
        })();
        {
          const u = (() => {
            return $f29693;
          })();
          {
            const col_w = (view_w / 3.);
            (() => {
              {
                const $t29691 = (() => {
                  {
                    const $t29690 = (() => {
                      {
                        const $t29689 = i;
                        return ($t29689 + 0.5);
                      }
                    })();
                    return (col_w * $t29690);
                  }
                })();
                {
                  const $rc_843 = (() => {
                    return draw_milestone_card(ctx, u, $t29691, view_h);
                  })();
                  return $rc_843;
                }
              }
            })();
            {
              const $t29692 = (i + 1);
              return draw_milestone_cards(ctx, rest, view_w, view_h, $t29692);
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
const draw_milestone_cards$clo = { _0: ($_, ctx, choices, view_w, view_h, i) => draw_milestone_cards(ctx, choices, view_w, view_h, i) };

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
      const $t29700 = (() => {
        {
          const $t29699 = game.score;
          return String($t29699);
        }
      })();
      return Canvas$fill_text(ctx, $t29700, 14., 28.);
    }
  })();
  (() => {
    return Canvas$set_text_align(ctx, "right");
  })();
  (() => {
    {
      const $t29703 = (() => {
        {
          const $t29702 = (() => {
            {
              const $t29701 = game.best;
              return String($t29701);
            }
          })();
          {
            const $rc_854 = ("best " + $t29702);
            return $rc_854;
          }
        }
      })();
      {
        const $t29705 = (() => {
          {
            const $t29704 = game.view_w;
            return ($t29704 - 14.);
          }
        })();
        return Canvas$fill_text(ctx, $t29703, $t29705, 28.);
      }
    }
  })();
  (() => {
    {
      const $t29707 = (() => {
        {
          const $t29706 = game.multiplier;
          return ($t29706 > 1);
        }
      })();
      if ($t29707 === true) {
        return (() => {
          (() => {
            return Canvas$set_text_align(ctx, "left");
          })();
          {
            const $t29710 = (() => {
              {
                const $t29709 = (() => {
                  {
                    const $t29708 = game.multiplier;
                    return String($t29708);
                  }
                })();
                {
                  const $rc_853 = ("x" + $t29709);
                  return $rc_853;
                }
              }
            })();
            return Canvas$fill_text(ctx, $t29710, 14., 52.);
          }
        })();
      } else {
        return {  };
      }
    }
  })();
  (() => {
    return Canvas$set_text_align(ctx, "left");
  })();
  (() => {
    return Canvas$set_font(ctx, "13px sans-serif");
  })();
  (() => {
    {
      const $t29713 = (() => {
        {
          const $t29712 = (() => {
            {
              const $t29711 = Perihelion$Core$active_weapon(game);
              return { $: "OffenseWeapon", _0: $t29711 };
            }
          })();
          {
            let $rc_852;
            switch ($t29712.$) {
              case "OffenseWeapon": {
                const $f29682_i10374 = $t29712._0;
                $rc_852 = (() => {
                  switch ($f29682_i10374.$) {
                    case "Homing": {
                      return "Homing Missiles";
                      break;
                    }
                    case "Spread": {
                      return "Spread Fire";
                      break;
                    }
                    case "StarKiller": {
                      return "Star Killer";
                      break;
                    }
                    case "Base": {
                      return "Base Weapon";
                      break;
                    }
                    default: {
                      return (() => { throw new Error("non-exhaustive pattern match"); })();
                    }
                  }
                })();
                break;
              }
              case "OffenseFireRate": {
                $rc_852 = "Faster Fire";
                break;
              }
              case "DefenseBulletWard": {
                $rc_852 = "Bullet Ward";
                break;
              }
              case "DefenseDeflector": {
                $rc_852 = "Deflector Plating";
                break;
              }
              case "DefenseShield": {
                $rc_852 = "Reinforced Shield";
                break;
              }
              case "SpecialItem": {
                const $f29683_i10375 = $t29712._0;
                $rc_852 = (() => {
                  switch ($f29683_i10375.$) {
                    case "StarThrust": {
                      return "Star Thrust";
                      break;
                    }
                    case "StarJump": {
                      return "Star Jump";
                      break;
                    }
                    case "TrajectoryPreview": {
                      return "Trajectory Preview";
                      break;
                    }
                    default: {
                      return (() => { throw new Error("non-exhaustive pattern match"); })();
                    }
                  }
                })();
                break;
              }
              default: {
                $rc_852 = (() => { throw new Error("non-exhaustive pattern match"); })();
                break;
              }
            }
            return $rc_852;
          }
        }
      })();
      {
        const $t29715 = (() => {
          {
            const $t29714 = game.view_h;
            return ($t29714 - 60.);
          }
        })();
        return Canvas$fill_text(ctx, $t29713, 14., $t29715);
      }
    }
  })();
  (() => {
    {
      const $t29716 = game.special;
      switch ($t29716.$) {
        case "None": {
          return {  };
          break;
        }
        case "Some": {
          const $f29725 = $t29716._0;
          {
            const k = (() => {
              return $f29725;
            })();
            {
              const $t29722 = (() => {
                {
                  const $t29719 = (() => {
                    {
                      const $t29718 = (() => {
                        {
                          const $t29717 = { $: "SpecialItem", _0: k };
                          {
                            let $rc_851;
                            switch ($t29717.$) {
                              case "OffenseWeapon": {
                                const $f29682_i10371 = $t29717._0;
                                $rc_851 = (() => {
                                  switch ($f29682_i10371.$) {
                                    case "Homing": {
                                      return "Homing Missiles";
                                      break;
                                    }
                                    case "Spread": {
                                      return "Spread Fire";
                                      break;
                                    }
                                    case "StarKiller": {
                                      return "Star Killer";
                                      break;
                                    }
                                    case "Base": {
                                      return "Base Weapon";
                                      break;
                                    }
                                    default: {
                                      return (() => { throw new Error("non-exhaustive pattern match"); })();
                                    }
                                  }
                                })();
                                break;
                              }
                              case "OffenseFireRate": {
                                $rc_851 = "Faster Fire";
                                break;
                              }
                              case "DefenseBulletWard": {
                                $rc_851 = "Bullet Ward";
                                break;
                              }
                              case "DefenseDeflector": {
                                $rc_851 = "Deflector Plating";
                                break;
                              }
                              case "DefenseShield": {
                                $rc_851 = "Reinforced Shield";
                                break;
                              }
                              case "SpecialItem": {
                                const $f29683_i10372 = $t29717._0;
                                $rc_851 = (() => {
                                  switch ($f29683_i10372.$) {
                                    case "StarThrust": {
                                      return "Star Thrust";
                                      break;
                                    }
                                    case "StarJump": {
                                      return "Star Jump";
                                      break;
                                    }
                                    case "TrajectoryPreview": {
                                      return "Trajectory Preview";
                                      break;
                                    }
                                    default: {
                                      return (() => { throw new Error("non-exhaustive pattern match"); })();
                                    }
                                  }
                                })();
                                break;
                              }
                              default: {
                                $rc_851 = (() => { throw new Error("non-exhaustive pattern match"); })();
                                break;
                              }
                            }
                            return $rc_851;
                          }
                        }
                      })();
                      {
                        const $rc_850 = ($t29718 + " x");
                        return $rc_850;
                      }
                    }
                  })();
                  {
                    const $t29721 = (() => {
                      {
                        const $t29720 = game.special_charges;
                        return String($t29720);
                      }
                    })();
                    {
                      const $rc_849 = ($t29719 + $t29721);
                      return $rc_849;
                    }
                  }
                }
              })();
              {
                const $t29724 = (() => {
                  {
                    const $t29723 = game.view_h;
                    return ($t29723 - 40.);
                  }
                })();
                return Canvas$fill_text(ctx, $t29722, 14., $t29724);
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
    const defense_tags = (() => {
      {
        const $t29730 = (() => {
          {
            const $t29727 = (() => {
              {
                const $t29726 = game.bullet_ward;
                if ($t29726 === true) {
                  return "ward ";
                } else {
                  return "";
                }
              }
            })();
            {
              const $t29729 = (() => {
                {
                  const $t29728 = game.deflector_plating;
                  if ($t29728 === true) {
                    return "deflect ";
                  } else {
                    return "";
                  }
                }
              })();
              {
                const $rc_848 = ($t29727 + $t29729);
                return $rc_848;
              }
            }
          }
        })();
        {
          const $t29735 = (() => {
            {
              const $t29732 = (() => {
                {
                  const $t29731 = game.shield;
                  return ($t29731 > 0);
                }
              })();
              if ($t29732 === true) {
                return (() => {
                  {
                    const $t29734 = (() => {
                      {
                        const $t29733 = game.shield;
                        return String($t29733);
                      }
                    })();
                    {
                      const $rc_847 = ("shield x" + $t29734);
                      return $rc_847;
                    }
                  }
                })();
              } else {
                return "";
              }
            }
          })();
          {
            const $rc_846 = ($t29730 + $t29735);
            return $rc_846;
          }
        }
      }
    })();
    (() => {
      {
        const $t29737 = (() => {
          {
            const $t29736 = game.view_h;
            return ($t29736 - 20.);
          }
        })();
        return Canvas$fill_text(ctx, defense_tags, 14., $t29737);
      }
    })();
    (() => {
      return Canvas$set_text_align(ctx, "center");
    })();
    {
      const $t29738 = game.phase;
      switch ($t29738.$) {
        case "Ready": {
          (() => {
            return Canvas$set_font(ctx, "22px sans-serif");
          })();
          {
            const $t29740 = (() => {
              {
                const $t29739 = game.view_w;
                return ($t29739 / 2.);
              }
            })();
            {
              const $t29742 = (() => {
                {
                  const $t29741 = game.view_h;
                  return ($t29741 / 2.);
                }
              })();
              return Canvas$fill_text(ctx, "tap to start", $t29740, $t29742);
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
              const $t29746 = (() => {
                {
                  const $t29745 = (() => {
                    {
                      const $t29744 = (() => {
                        {
                          const $t29743 = game.score;
                          return String($t29743);
                        }
                      })();
                      {
                        const $rc_845 = ("score " + $t29744);
                        return $rc_845;
                      }
                    }
                  })();
                  {
                    const $rc_844 = ($t29745 + " — tap to retry");
                    return $rc_844;
                  }
                }
              })();
              {
                const $t29748 = (() => {
                  {
                    const $t29747 = game.view_w;
                    return ($t29747 / 2.);
                  }
                })();
                {
                  const $t29750 = (() => {
                    {
                      const $t29749 = game.view_h;
                      return ($t29749 / 2.);
                    }
                  })();
                  return Canvas$fill_text(ctx, $t29746, $t29748, $t29750);
                }
              }
            }
          })();
          {
            const $t29751 = game.runs;
            {
              const $t29752 = game.view_w;
              {
                const $t29755 = (() => {
                  {
                    const $t29754 = (() => {
                      {
                        const $t29753 = game.view_h;
                        return ($t29753 / 2.);
                      }
                    })();
                    return ($t29754 + 36.);
                  }
                })();
                return draw_runs(ctx, $t29751, $t29752, $t29755, 0);
              }
            }
          }
          break;
        }
        case "Playing": {
          return {  };
          break;
        }
        case "Milestone": {
          (() => {
            return Canvas$set_font(ctx, "20px sans-serif");
          })();
          (() => {
            {
              const $t29757 = (() => {
                {
                  const $t29756 = game.view_w;
                  return ($t29756 / 2.);
                }
              })();
              {
                const $t29760 = (() => {
                  {
                    const $t29759 = (() => {
                      {
                        const $t29758 = game.view_h;
                        return ($t29758 / 2.);
                      }
                    })();
                    return ($t29759 - 90.);
                  }
                })();
                return Canvas$fill_text(ctx, "Choose an upgrade", $t29757, $t29760);
              }
            }
          })();
          {
            const $t29761 = game.milestone_choices;
            {
              const $t29762 = game.view_w;
              {
                const $t29763 = game.view_h;
                return draw_milestone_cards(ctx, $t29761, $t29762, $t29763, 0);
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
      const $t29764 = game.view_w;
      {
        const $t29765 = game.view_h;
        return Canvas$fill_rect(ctx, 0., 0., $t29764, $t29765);
      }
    }
  })();
  (() => {
    return Canvas$save(ctx);
  })();
  (() => {
    {
      const $t29767 = (() => {
        {
          const $t29766 = game.camera_x;
          return (0. - $t29766);
        }
      })();
      {
        const $t29769 = (() => {
          {
            const $t29768 = game.camera_y;
            return (0. - $t29768);
          }
        })();
        return Canvas$translate(ctx, $t29767, $t29769);
      }
    }
  })();
  {
    const seedf = (() => {
      {
        const $t29770 = game.seed;
        return $t29770;
      }
    })();
    (() => {
      {
        const $t29771 = game.camera_x;
        {
          const $t29772 = game.camera_y;
          {
            const $t29773 = game.view_w;
            {
              const $t29774 = game.view_h;
              {
                const $t29775 = fx.t;
                return draw_starfield(ctx, $t29771, $t29772, $t29773, $t29774, seedf, $t29775);
              }
            }
          }
        }
      }
    })();
    (() => {
      {
        const $t29776 = game.stars;
        {
          const $t29777 = game.camera_y;
          {
            const $t29778 = game.view_h;
            return draw_nebula(ctx, $t29776, $t29777, $t29778, seedf);
          }
        }
      }
    })();
    {
      const aim = (() => {
        {
          const $t29779 = game.mode;
          switch ($t29779.$) {
            case "Flying": {
              const $f29783 = $t29779._0;
              const $f29784 = $t29779._1;
              {
                const vy = (() => {
                  return $f29784;
                })();
                {
                  const vx = (() => {
                    return $f29783;
                  })();
                  {
                    const $t29782 = (() => {
                      {
                        const $t29780 = game.ball_x;
                        {
                          const $t29781 = game.ball_y;
                          return { _0: $t29780, _1: $t29781, _2: vx, _3: vy };
                        }
                      }
                    })();
                    return { $: "Some", _0: $t29782 };
                  }
                }
              }
              break;
            }
            case "Orbiting": {
              const $f29789 = $t29779._0;
              const $f29790 = $t29779._1;
              const $f29791 = $t29779._2;
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
          const $t29800 = game.stars;
          {
            const $t29801 = game.camera_y;
            {
              const $t29802 = game.view_h;
              {
                const $t29803 = fx.t;
                {
                  const $rc_856 = (() => {
                    return draw_stars(ctx, $t29800, $t29801, $t29802, $t29803, aim);
                  })();
                  return $rc_856;
                }
              }
            }
          }
        }
      })();
      (() => {
        {
          const $t29804 = Perihelion$Core$active_weapon(game);
          switch ($t29804.$) {
            case "StarKiller": {
              return draw_starkiller_reticle(ctx, game);
              break;
            }
            default: {
              return {  };
            }
          }
        }
      })();
      (() => {
        {
          const $t29807 = game.mode;
          switch ($t29807.$) {
            case "Orbiting": {
              const $f29815 = $t29807._0;
              const $f29816 = $t29807._1;
              const $f29817 = $t29807._2;
              {
                const angle = (() => {
                  return $f29817;
                })();
                {
                  const ring = (() => {
                    return $f29816;
                  })();
                  {
                    const idx = (() => {
                      return $f29815;
                    })();
                    {
                      const $t29808 = game.special;
                      switch ($t29808.$) {
                        case "Some": {
                          const $f29810 = $t29808._0;
                          switch ($f29810.$) {
                            case "TrajectoryPreview": {
                              {
                                const $t29809 = Perihelion$Core$predict_trajectory(game, idx, ring, angle);
                                {
                                  const $rc_855 = (() => {
                                    return draw_trajectory_preview(ctx, $t29809);
                                  })();
                                  return $rc_855;
                                }
                              }
                              break;
                            }
                            default: {
                              return {  };
                            }
                          }
                          break;
                        }
                        default: {
                          return {  };
                        }
                      }
                    }
                  }
                }
              }
              break;
            }
            case "Flying": {
              const $f29826 = $t29807._0;
              const $f29827 = $t29807._1;
              return {  };
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
          const $t29832 = fx.flash;
          return draw_flash(ctx, $t29832);
        }
      })();
      (() => {
        {
          const $t29833 = game.asteroids;
          return draw_asteroids(ctx, $t29833);
        }
      })();
      (() => {
        {
          const $t29834 = game.ships;
          return draw_ships(ctx, $t29834);
        }
      })();
      (() => {
        {
          const $t29835 = game.player_shots;
          return draw_shots(ctx, $t29835, "#ffffff", 3.);
        }
      })();
      (() => {
        {
          const $t29836 = game.enemy_shots;
          return draw_shots(ctx, $t29836, "#8a8a94", 2.5);
        }
      })();
      (() => {
        {
          const $t29837 = game.pickups;
          return draw_pickups(ctx, $t29837);
        }
      })();
      (() => {
        {
          const $t29838 = fx.trail;
          return draw_trail(ctx, $t29838, 0, 14);
        }
      })();
      (() => {
        {
          const $t29840 = fx.particles;
          return draw_particles(ctx, $t29840);
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

function draw_starkiller_reticle(ctx, game) {
  {
    const $t29842 = (() => {
      {
        const $t29841 = Perihelion$Combat$starkiller_target_idx(game);
        return Perihelion$Core$star_at(game, $t29841);
      }
    })();
    switch ($t29842.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f29848 = $t29842._0;
        {
          const s = $f29848;
          (() => {
            return Canvas$set_stroke_style(ctx, "#ff5555");
          })();
          (() => {
            return Canvas$set_line_width(ctx, 2.);
          })();
          (() => {
            return Canvas$begin_path(ctx);
          })();
          (() => {
            {
              const $t29843 = s.x;
              {
                const $t29844 = s.y;
                {
                  const $t29846 = (() => {
                    {
                      const $t29845 = s.capture_radius;
                      return ($t29845 + 12.);
                    }
                  })();
                  return Canvas$arc(ctx, $t29843, $t29844, $t29846, 0., 6.28318530718);
                }
              }
            }
          })();
          return Canvas$stroke(ctx);
        }
        break;
      }
      default: {
        return (() => { throw new Error("non-exhaustive pattern match"); })();
      }
    }
  }
}
const draw_starkiller_reticle$clo = { _0: ($_, ctx, game) => draw_starkiller_reticle(ctx, game) };

function draw_trajectory_preview(ctx, points) {
  (() => {
    return Canvas$set_fill_style(ctx, "#888888");
  })();
  return draw_trajectory_dots(ctx, points, 0);
}
const draw_trajectory_preview$clo = { _0: ($_, ctx, points) => draw_trajectory_preview(ctx, points) };

function draw_trajectory_dots(ctx, points, i) {
  switch (points.$) {
    case "Nil": {
      return {  };
      break;
    }
    case "Cons": {
      const $f29854 = points._0;
      const $f29855 = points._1;
      {
        const rest = (() => {
          return $f29855;
        })();
        {
          const pt = (() => {
            return $f29854;
          })();
          {
            const x = pt._0;
            {
              const y = pt._1;
              (() => {
                {
                  const $t29850 = (() => {
                    {
                      const $t29849 = march_int_mod(i, 3);
                      return ($t29849 === 0);
                    }
                  })();
                  if ($t29850 === true) {
                    return (() => {
                      (() => {
                        return Canvas$begin_path(ctx);
                      })();
                      (() => {
                        return Canvas$arc(ctx, x, y, 2., 0., 6.28318530718);
                      })();
                      return Canvas$fill(ctx);
                    })();
                  } else {
                    return {  };
                  }
                }
              })();
              {
                const $t29852 = (i + 1);
                return draw_trajectory_dots(ctx, rest, $t29852);
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
const draw_trajectory_dots$clo = { _0: ($_, ctx, points, i) => draw_trajectory_dots(ctx, points, i) };

function resize_canvas(el, game, w, h) {
  {
    const $t29866 = (() => {
      {
        const $t29863 = (() => {
          {
            const $t29862 = game.view_w;
            return (w === $t29862);
          }
        })();
        {
          const $t29865 = (() => {
            {
              const $t29864 = game.view_h;
              return (h === $t29864);
            }
          })();
          return ($t29863 && $t29865);
        }
      }
    })();
    if ($t29866 === true) {
      return {  };
    } else {
      return (() => {
        (() => {
          {
            const $t29868 = (() => {
              {
                const $t29867 = Math.trunc(w);
                return String($t29867);
              }
            })();
            return Dom$set_attr(el, "width", $t29868);
          }
        })();
        {
          const $t29870 = (() => {
            {
              const $t29869 = Math.trunc(h);
              return String($t29869);
            }
          })();
          return Dom$set_attr(el, "height", $t29870);
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
          const $t29884 = (() => {
            {
              const $t29882 = (() => {
                {
                  const $t29881 = game.phase;
                  switch ($t29881.$) {
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
                const $t29883 = (() => {
                  {
                    const $t29860_i4159 = g2.phase;
                    switch ($t29860_i4159.$) {
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
                return ($t29882 && $t29883);
              }
            }
          })();
          if ($t29884 === true) {
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
          const $t29889 = (() => {
            {
              const $t29886 = (() => {
                {
                  const $t29885 = game.mode;
                  switch ($t29885.$) {
                    case "Orbiting": {
                      const $f29871_i4155 = $t29885._0;
                      const $f29872_i4156 = $t29885._1;
                      const $f29873_i4157 = $t29885._2;
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
                const $t29888 = (() => {
                  {
                    const $t29887 = g2.mode;
                    switch ($t29887.$) {
                      case "Flying": {
                        const $f29874_i4152 = $t29887._0;
                        const $f29875_i4153 = $t29887._1;
                        return true;
                        break;
                      }
                      default: {
                        return false;
                      }
                    }
                  }
                })();
                return ($t29886 && $t29888);
              }
            }
          })();
          if ($t29889 === true) {
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
          const $t29890 = g2.capture_flash;
          switch ($t29890.$) {
            case "None": {
              return {  };
              break;
            }
            case "Some": {
              const $f29891 = $t29890._0;
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
          const $t29896 = (() => {
            {
              const $t29893 = (() => {
                {
                  const $t29892 = g2.player_shots;
                  {
                    const go_i4149 = { $: "$Clo_go$4823", _0: go$apply$4823 };
                    return go$apply$4823(go_i4149, $t29892, 0);
                  }
                }
              })();
              {
                const $t29895 = (() => {
                  {
                    const $t29894 = game.player_shots;
                    {
                      const go_i4147 = { $: "$Clo_go$4823", _0: go$apply$4823 };
                      return go$apply$4823(go_i4147, $t29894, 0);
                    }
                  }
                })();
                return ($t29893 > $t29895);
              }
            }
          })();
          if ($t29896 === true) {
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
          const $t29901 = (() => {
            {
              const $t29898 = (() => {
                {
                  const $t29897 = g2.enemy_shots;
                  {
                    const go_i4145 = { $: "$Clo_go$4823", _0: go$apply$4823 };
                    return go$apply$4823(go_i4145, $t29897, 0);
                  }
                }
              })();
              {
                const $t29900 = (() => {
                  {
                    const $t29899 = game.enemy_shots;
                    {
                      const go_i4143 = { $: "$Clo_go$4823", _0: go$apply$4823 };
                      return go$apply$4823(go_i4143, $t29899, 0);
                    }
                  }
                })();
                return ($t29898 > $t29900);
              }
            }
          })();
          if ($t29901 === true) {
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
          const $t29904 = (() => {
            {
              const $t29903 = (() => {
                {
                  const $t29902 = g2.fx_bursts;
                  switch ($t29902.$) {
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
              return (!$t29903);
            }
          })();
          if ($t29904 === true) {
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
          const $t29909 = (() => {
            {
              const $t29906 = (() => {
                {
                  const $t29905 = g2.ships;
                  {
                    const go_i4140 = { $: "$Clo_go$4775", _0: go$apply$4775 };
                    return go$apply$4775(go_i4140, $t29905, 0);
                  }
                }
              })();
              {
                const $t29908 = (() => {
                  {
                    const $t29907 = game.ships;
                    {
                      const go_i4138 = { $: "$Clo_go$4775", _0: go$apply$4775 };
                      return go$apply$4775(go_i4138, $t29907, 0);
                    }
                  }
                })();
                return ($t29906 < $t29908);
              }
            }
          })();
          if ($t29909 === true) {
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
          const $t29914 = (() => {
            {
              const $t29911 = (() => {
                {
                  const $t29910 = game.shield;
                  return ($t29910 === 0);
                }
              })();
              {
                const $t29913 = (() => {
                  {
                    const $t29912 = g2.shield;
                    return ($t29912 > 0);
                  }
                })();
                return ($t29911 && $t29913);
              }
            }
          })();
          if ($t29914 === true) {
            return (() => {
              return Audio$beep(actx, 700., 0.06, "sine");
            })();
          } else {
            return {  };
          }
        }
      })();
      {
        const $t29917 = (() => {
          {
            const $t29915 = (() => {
              {
                const $t29860_i4136 = game.phase;
                switch ($t29860_i4136.$) {
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
              const $t29916 = (() => {
                {
                  const $t29861_i4134 = g2.phase;
                  switch ($t29861_i4134.$) {
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
              return ($t29915 && $t29916);
            }
          }
        })();
        if ($t29917 === true) {
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

function milestone_tap_choice(taps, view_w, _view_h) {
  switch (taps.$) {
    case "Nil": {
      return { $: "None" };
      break;
    }
    case "Cons": {
      const $f29923 = taps._0;
      const $f29924 = taps._1;
      {
        const tap = (() => {
          return $f29923;
        })();
        {
          const tx = tap._0;
          {
            const col_w = (view_w / 3.);
            {
              const idx = (() => {
                {
                  const $t29919 = (() => {
                    {
                      const $t29918 = tx;
                      return ($t29918 / col_w);
                    }
                  })();
                  return Math.trunc($t29919);
                }
              })();
              {
                const $t29921 = (() => {
                  {
                    const $t29920 = (idx > 2);
                    if ($t29920 === true) {
                      return 2;
                    } else {
                      return idx;
                    }
                  }
                })();
                return { $: "Some", _0: $t29921 };
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
const milestone_tap_choice$clo = { _0: ($_, taps, view_w, _view_h) => milestone_tap_choice(taps, view_w, _view_h) };

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
          const $p29947 = dom_window_size();
          {
            const win_w = $p29947._0;
            {
              const win_h = $p29947._1;
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
                        const $t29929 = game.phase;
                        switch ($t29929.$) {
                          case "Milestone": {
                            {
                              const $jp_clo29935 = (() => {
                                return { $: "$Clo_$jp29934$3817", _0: $jp29934$apply$3817, _1: cursor, _2: game, _3: keys, _4: taps, _5: view_h, _6: view_w };
                              })();
                              {
                                const $t29930 = (() => {
                                  {
                                    const $t28438_i4171 = { $: "$Clo_$lam28435$3738", _0: $lam28435$apply$3738 };
                                    return List$any$List_String$Fn_String_Bool(keys, $t28438_i4171);
                                  }
                                })();
                                if ($t29930 === true) {
                                  return (() => {
                                    {
                                      const $rc_857 = (() => {
                                        return Perihelion$Core$update(game, taps, keys, cursor, view_w, view_h, 0.0166667);
                                      })();
                                      return $rc_857;
                                    }
                                  })();
                                } else {
                                  return (() => {
                                    {
                                      const $t29932 = (() => {
                                        {
                                          const $rc_858 = milestone_tap_choice(taps, view_w, view_h);
                                          return $rc_858;
                                        }
                                      })();
                                      return Perihelion$Core$pick_milestone(game, $t29932);
                                    }
                                  })();
                                }
                              }
                            }
                            break;
                          }
                          default: {
                            {
                              const $rc_859 = (() => {
                                return Perihelion$Core$update(game, taps, keys, cursor, view_w, view_h, 0.0166667);
                              })();
                              return $rc_859;
                            }
                          }
                        }
                      }
                    })();
                    {
                      const muted2 = (() => {
                        {
                          const $t29936 = fx.muted;
                          {
                            const $t29880_i4169 = (() => {
                              {
                                const $t29879_i4168 = { $: "$Clo_$lam29876$3815", _0: $lam29876$apply$3815 };
                                return List$any$List_String$Fn_String_Bool(keys, $t29879_i4168);
                              }
                            })();
                            if ($t29880_i4169 === true) {
                              return (!$t29936);
                            } else {
                              return $t29936;
                            }
                          }
                        }
                      })();
                      (() => {
                        {
                          const $t29937 = fx.actx;
                          return play_sfx($t29937, muted2, game, g2);
                        }
                      })();
                      {
                        const fx1 = step_fx(fx, g2, 0.0166667);
                        {
                          const fx2 = ({ ...fx1, muted: muted2 });
                          (() => {
                            {
                              const $t29941 = (() => {
                                {
                                  const $t29939 = (() => {
                                    {
                                      const $t29860_i4165 = game.phase;
                                      switch ($t29860_i4165.$) {
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
                                    const $t29940 = (() => {
                                      {
                                        const $t29861_i4163 = g2.phase;
                                        switch ($t29861_i4163.$) {
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
                                    return ($t29939 && $t29940);
                                  }
                                }
                              })();
                              if ($t29941 === true) {
                                return (() => {
                                  {
                                    const $t29944 = (() => {
                                      {
                                        const $t29942 = g2.best;
                                        {
                                          const $t29943 = g2.runs;
                                          return Perihelion$Core$encode_save($t29942, $t29943);
                                        }
                                      }
                                    })();
                                    return Dom$store_set("perihelion.v1", $t29944);
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
                            const $t29946 = { $: "$Clo_$lam29945$3818", _0: $lam29945$apply$3818, _1: ctx, _2: el, _3: fx2, _4: g2 };
                            return Dom$on_frame($t29946);
                          }
                        }
                      }
                    }
                  }
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
    const $p29953 = dom_window_size();
    {
      const win_w = $p29953._0;
      {
        const win_h = $p29953._1;
        {
          const view_w = win_w;
          {
            const view_h = win_h;
            (() => {
              {
                const $t29948 = String(win_w);
                return Dom$set_attr(node, "width", $t29948);
              }
            })();
            (() => {
              {
                const $t29949 = String(win_h);
                return Dom$set_attr(node, "height", $t29949);
              }
            })();
            {
              const $t29951 = (() => {
                {
                  const $t29950 = boot_seed();
                  return Perihelion$Core$fresh_run($t29950, best, runs, view_w, view_h);
                }
              })();
              {
                const $t29952 = (() => {
                  {
                    const $t29228_i10376 = { $: "Nil" };
                    {
                      const $t29229_i10377 = { $: "Nil" };
                      {
                        const $t29230_i10378 = { $: "None" };
                        {
                          const $t29231_i10379 = audio_create();
                          return ({ trail: $t29228_i10376, t: 0., particles: $t29229_i10377, flash: $t29230_i10378, actx: $t29231_i10379, muted: false });
                        }
                      }
                    }
                  }
                })();
                return tick(ctx, node, $t29951, $t29952);
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
    const $t29954 = Dom$find("game-canvas");
    switch ($t29954.$) {
      case "None": {
        return println$String("no #game-canvas found");
        break;
      }
      case "Some": {
        const $f29962 = $t29954._0;
        {
          const node = $f29962;
          {
            const $t29955 = (() => {
              return Canvas$get_context(node);
            })();
            switch ($t29955.$) {
              case "None": {
                return println$String("2d context unavailable");
                break;
              }
              case "Some": {
                const $f29961 = $t29955._0;
                {
                  const ctx = $f29961;
                  {
                    const saved = (() => {
                      {
                        const $t29956 = Dom$store_get("perihelion.v1");
                        switch ($t29956.$) {
                          case "None": {
                            return "";
                            break;
                          }
                          case "Some": {
                            const $f29957 = $t29956._0;
                            {
                              const sv = $f29957;
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
                      const $p29960 = (() => {
                        {
                          const $rc_860 = Perihelion$Core$decode_save(saved);
                          return $rc_860;
                        }
                      })();
                      {
                        const best = $p29960._0;
                        {
                          const runs = $p29960._1;
                          {
                            const $t29959 = (() => {
                              return { $: "$Clo_$lam29958$3819", _0: $lam29958$apply$3819, _1: best, _2: ctx, _3: node, _4: runs };
                            })();
                            return Dom$on_frame($t29959);
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
      const $t107 = x;
      {
        const $rc_867 = march_print(x);
        return $rc_867;
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
      const $f417 = xs._0;
      const $f418 = xs._1;
      {
        const t = $f418;
        {
          const h = $f417;
          {
            const $t416 = (() => {
              return pred._0(pred, h);
            })();
            if ($t416 === true) {
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
      const $f417 = xs._0;
      const $f418 = xs._1;
      {
        const t = $f418;
        {
          const h = $f417;
          {
            const $t416 = (() => {
              return pred._0(pred, h);
            })();
            if ($t416 === true) {
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

function List$any$List_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool(xs, pred) {
  switch (xs.$) {
    case "Nil": {
      return false;
      break;
    }
    case "Cons": {
      const $f417 = xs._0;
      const $f418 = xs._1;
      {
        const t = $f418;
        {
          const h = $f417;
          {
            const $t416 = (() => {
              return pred._0(pred, h);
            })();
            if ($t416 === true) {
              return true;
            } else {
              return List$any$List_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool(t, pred);
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
const List$any$List_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool$clo = { _0: ($_, xs, pred) => List$any$List_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool(xs, pred) };

function List$any$List_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float$Fn_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float_Bool(xs, pred) {
  switch (xs.$) {
    case "Nil": {
      return false;
      break;
    }
    case "Cons": {
      const $f417 = xs._0;
      const $f418 = xs._1;
      {
        const t = $f418;
        {
          const h = $f417;
          {
            const $t416 = (() => {
              return pred._0(pred, h);
            })();
            if ($t416 === true) {
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

function List$find$List_R_kind_UpgradeKind_ttl_Float_x_Float_y_Float$Fn_R_kind_UpgradeKind_ttl_Float_x_Float_y_Float_Bool(xs, pred) {
  switch (xs.$) {
    case "Nil": {
      return { $: "None" };
      break;
    }
    case "Cons": {
      const $f402 = xs._0;
      const $f403 = xs._1;
      {
        const t = $f403;
        {
          const h = $f402;
          {
            const $t401 = (() => {
              return pred._0(pred, h);
            })();
            if ($t401 === true) {
              return { $: "Some", _0: h };
            } else {
              return List$find$List_R_kind_UpgradeKind_ttl_Float_x_Float_y_Float$Fn_R_kind_UpgradeKind_ttl_Float_x_Float_y_Float_Bool(t, pred);
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
const List$find$List_R_kind_UpgradeKind_ttl_Float_x_Float_y_Float$Fn_R_kind_UpgradeKind_ttl_Float_x_Float_y_Float_Bool$clo = { _0: ($_, xs, pred) => List$find$List_R_kind_UpgradeKind_ttl_Float_x_Float_y_Float$Fn_R_kind_UpgradeKind_ttl_Float_x_Float_y_Float_Bool(xs, pred) };

function List$nth_opt$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int(xs, n) {
  switch (xs.$) {
    case "Nil": {
      return { $: "None" };
      break;
    }
    case "Cons": {
      const $f233 = xs._0;
      const $f234 = xs._1;
      {
        const t = $f234;
        {
          const h = $f233;
          {
            const $t231 = (n === 0);
            if ($t231 === true) {
              return { $: "Some", _0: h };
            } else {
              return (() => {
                {
                  const $t232 = (n - 1);
                  return List$nth_opt$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int(t, $t232);
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

function List$drop$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int(xs, n) {
  {
    const $t509 = (n <= 0);
    if ($t509 === true) {
      return xs;
    } else {
      return (() => {
        switch (xs.$) {
          case "Nil": {
            return { $: "Nil" };
            break;
          }
          case "Cons": {
            const $f511 = xs._0;
            const $f512 = xs._1;
            {
              const t = $f512;
              {
                const $t510 = (n - 1);
                return List$drop$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int(t, $t510);
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
const List$drop$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int$clo = { _0: ($_, xs, n) => List$drop$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int(xs, n) };

function List$nth_opt$List_R_radius_Float_speed_mult_Float$Int(xs, n) {
  switch (xs.$) {
    case "Nil": {
      return { $: "None" };
      break;
    }
    case "Cons": {
      const $f233 = xs._0;
      const $f234 = xs._1;
      {
        const t = $f234;
        {
          const h = $f233;
          {
            const $t231 = (n === 0);
            if ($t231 === true) {
              return { $: "Some", _0: h };
            } else {
              return (() => {
                {
                  const $t232 = (n - 1);
                  return List$nth_opt$List_R_radius_Float_speed_mult_Float$Int(t, $t232);
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

function List$nth_opt$List_WeaponKind$Int(xs, n) {
  switch (xs.$) {
    case "Nil": {
      return { $: "None" };
      break;
    }
    case "Cons": {
      const $f233 = xs._0;
      const $f234 = xs._1;
      {
        const t = $f234;
        {
          const h = $f233;
          {
            const $t231 = (n === 0);
            if ($t231 === true) {
              return { $: "Some", _0: h };
            } else {
              return (() => {
                {
                  const $t232 = (n - 1);
                  return List$nth_opt$List_WeaponKind$Int(t, $t232);
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
const List$nth_opt$List_WeaponKind$Int$clo = { _0: ($_, xs, n) => List$nth_opt$List_WeaponKind$Int(xs, n) };

function List$nth_opt$List_UpgradeKind$Int(xs, n) {
  switch (xs.$) {
    case "Nil": {
      return { $: "None" };
      break;
    }
    case "Cons": {
      const $f233 = xs._0;
      const $f234 = xs._1;
      {
        const t = $f234;
        {
          const h = $f233;
          {
            const $t231 = (n === 0);
            if ($t231 === true) {
              return { $: "Some", _0: h };
            } else {
              return (() => {
                {
                  const $t232 = (n - 1);
                  return List$nth_opt$List_UpgradeKind$Int(t, $t232);
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
const List$nth_opt$List_UpgradeKind$Int$clo = { _0: ($_, xs, n) => List$nth_opt$List_UpgradeKind$Int(xs, n) };

function List$drop$List_UpgradeKind$Int(xs, n) {
  {
    const $t509 = (n <= 0);
    if ($t509 === true) {
      return xs;
    } else {
      return (() => {
        switch (xs.$) {
          case "Nil": {
            return { $: "Nil" };
            break;
          }
          case "Cons": {
            const $f511 = xs._0;
            const $f512 = xs._1;
            {
              const t = $f512;
              {
                const $t510 = (n - 1);
                return List$drop$List_UpgradeKind$Int(t, $t510);
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
const List$drop$List_UpgradeKind$Int$clo = { _0: ($_, xs, n) => List$drop$List_UpgradeKind$Int(xs, n) };

function List$nth$List_UpgradeKind$Int(xs, n) {
  switch (xs.$) {
    case "Nil": {
      return (() => { throw new Error("List.nth: index out of bounds"); })();
      break;
    }
    case "Cons": {
      const $f225 = xs._0;
      const $f226 = xs._1;
      {
        const t = $f226;
        {
          const h = $f225;
          {
            const $t223 = (n === 0);
            if ($t223 === true) {
              return h;
            } else {
              return (() => {
                {
                  const $t224 = (n - 1);
                  return List$nth$List_UpgradeKind$Int(t, $t224);
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
const List$nth$List_UpgradeKind$Int$clo = { _0: ($_, xs, n) => List$nth$List_UpgradeKind$Int(xs, n) };

function List$any$List_WeaponKind$Fn_WeaponKind_Bool(xs, pred) {
  switch (xs.$) {
    case "Nil": {
      return false;
      break;
    }
    case "Cons": {
      const $f417 = xs._0;
      const $f418 = xs._1;
      {
        const t = $f418;
        {
          const h = $f417;
          {
            const $t416 = (() => {
              return pred._0(pred, h);
            })();
            if ($t416 === true) {
              return true;
            } else {
              return List$any$List_WeaponKind$Fn_WeaponKind_Bool(t, pred);
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
const List$any$List_WeaponKind$Fn_WeaponKind_Bool$clo = { _0: ($_, xs, pred) => List$any$List_WeaponKind$Fn_WeaponKind_Bool(xs, pred) };

function $lam27490$apply$3672($clo, s) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const g1 = (() => {
        return $clo._2;
      })();
      {
        const $t27491 = g1.asteroids;
        {
          const $t27492 = g1.ships;
          return Perihelion$Combat$age_shot(s, dt_s, $t27491, $t27492);
        }
      }
    }
  }
}
const $lam27490$apply$3672$clo = { _0: ($_, $clo, s) => $lam27490$apply$3672($clo, s) };

function $lam27495$apply$3673($clo, s) {
  {
    const g1 = (() => {
      return $clo._1;
    })();
    {
      const $t27497 = (() => {
        {
          const $t27496 = s.ttl;
          return ($t27496 > 0.);
        }
      })();
      {
        const $t27500 = (() => {
          {
            const $t27498 = s.x;
            {
              const $t27499 = s.y;
              return Perihelion$Combat$in_band(g1, $t27498, $t27499);
            }
          }
        })();
        return ($t27497 && $t27500);
      }
    }
  }
}
const $lam27495$apply$3673$clo = { _0: ($_, $clo, s) => $lam27495$apply$3673($clo, s) };

function $lam27503$apply$3674($clo, s) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const g1 = (() => {
        return $clo._2;
      })();
      {
        const $t27504 = g1.asteroids;
        {
          const $t27505 = g1.ships;
          return Perihelion$Combat$age_shot(s, dt_s, $t27504, $t27505);
        }
      }
    }
  }
}
const $lam27503$apply$3674$clo = { _0: ($_, $clo, s) => $lam27503$apply$3674($clo, s) };

function $lam27508$apply$3675($clo, s) {
  {
    const g1 = (() => {
      return $clo._1;
    })();
    {
      const $t27510 = (() => {
        {
          const $t27509 = s.ttl;
          return ($t27509 > 0.);
        }
      })();
      {
        const $t27513 = (() => {
          {
            const $t27511 = s.x;
            {
              const $t27512 = s.y;
              return Perihelion$Combat$in_band(g1, $t27511, $t27512);
            }
          }
        })();
        return ($t27510 && $t27513);
      }
    }
  }
}
const $lam27508$apply$3675$clo = { _0: ($_, $clo, s) => $lam27508$apply$3675($clo, s) };

function $lam27516$apply$3676($clo, p) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const $t27518 = (() => {
        {
          const $t27517 = p.ttl;
          return ($t27517 - dt_s);
        }
      })();
      return ({ ...p, ttl: $t27518 });
    }
  }
}
const $lam27516$apply$3676$clo = { _0: ($_, $clo, p) => $lam27516$apply$3676($clo, p) };

function $lam27521$apply$3677($clo, p) {
  {
    const $t27522 = p.ttl;
    return ($t27522 > 0.);
  }
}
const $lam27521$apply$3677$clo = { _0: ($_, $clo, p) => $lam27521$apply$3677($clo, p) };

function $lam27921$apply$3693($clo, k) {
  return (k === " ");
}
const $lam27921$apply$3693$clo = { _0: ($_, $clo, k) => $lam27921$apply$3693($clo, k) };

function $lam27989$apply$3696($clo, sh) {
  {
    const tidx = (() => {
      return $clo._1;
    })();
    {
      const $t27990 = sh.star_idx;
      return ($t27990 !== tidx);
    }
  }
}
const $lam27989$apply$3696$clo = { _0: ($_, $clo, sh) => $lam27989$apply$3696($clo, sh) };

function $lam27993$apply$3697($clo, sh) {
  {
    const tidx = (() => {
      return $clo._1;
    })();
    {
      const $t27995 = (() => {
        {
          const $t27994 = sh.star_idx;
          return ($t27994 > tidx);
        }
      })();
      if ($t27995 === true) {
        return (() => {
          {
            const $t27997 = (() => {
              {
                const $t27996 = sh.star_idx;
                return ($t27996 - 1);
              }
            })();
            return ({ ...sh, star_idx: $t27997 });
          }
        })();
      } else {
        return sh;
      }
    }
  }
}
const $lam27993$apply$3697$clo = { _0: ($_, $clo, sh) => $lam27993$apply$3697($clo, sh) };

function $lam28010$apply$3699($clo, s) {
  return s.star_killer;
}
const $lam28010$apply$3699$clo = { _0: ($_, $clo, s) => $lam28010$apply$3699($clo, s) };

function $lam28023$apply$3701($clo, sh) {
  {
    const $t28024 = sh.star_killer;
    return (!$t28024);
  }
}
const $lam28023$apply$3701$clo = { _0: ($_, $clo, sh) => $lam28023$apply$3701($clo, sh) };

function $lam28030$apply$3702($clo, sh) {
  {
    const $t28031 = sh.star_killer;
    return (!$t28031);
  }
}
const $lam28030$apply$3702$clo = { _0: ($_, $clo, sh) => $lam28030$apply$3702($clo, sh) };

function $lam28044$apply$3703($clo, a) {
  {
    const $t28045 = a.x;
    {
      const $t28046 = a.y;
      return { _0: $t28045, _1: $t28046 };
    }
  }
}
const $lam28044$apply$3703$clo = { _0: ($_, $clo, a) => $lam28044$apply$3703($clo, a) };

function $lam28049$apply$3704($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28050 = game.player_shots;
      {
        const $t28055 = { $: "$Clo_$lam28051$3705", _0: $lam28051$apply$3705, _1: a };
        return List$any$List_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28050, $t28055);
      }
    }
  }
}
const $lam28049$apply$3704$clo = { _0: ($_, $clo, a) => $lam28049$apply$3704($clo, a) };

function $lam28051$apply$3705($clo, s) {
  {
    const a = (() => {
      return $clo._1;
    })();
    {
      const $t28052 = a.x;
      {
        const $t28053 = a.y;
        {
          const $t28054 = a.radius;
          {
            const $t28041_i10610 = s.x;
            {
              const $t28042_i10611 = s.y;
              {
                const $t27359_i10004_i10616 = (() => {
                  {
                    const dx_i3632_i10000_i10612 = ($t28052 - $t28041_i10610);
                    {
                      const dy_i3633_i10001_i10613 = ($t28053 - $t28042_i10611);
                      {
                        const $t27357_i3634_i10002_i10614 = (dx_i3632_i10000_i10612 * dx_i3632_i10000_i10612);
                        {
                          const $t27358_i3635_i10003_i10615 = (dy_i3633_i10001_i10613 * dy_i3633_i10001_i10613);
                          return ($t27357_i3634_i10002_i10614 + $t27358_i3635_i10003_i10615);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27362_i10007_i10619 = (() => {
                    {
                      const $t27360_i10005_i10617 = (3. + $t28054);
                      {
                        const $t27361_i10006_i10618 = (3. + $t28054);
                        return ($t27360_i10005_i10617 * $t27361_i10006_i10618);
                      }
                    }
                  })();
                  return ($t27359_i10004_i10616 <= $t27362_i10007_i10619);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28051$apply$3705$clo = { _0: ($_, $clo, s) => $lam28051$apply$3705($clo, s) };

function $lam28058$apply$3706($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28065 = (() => {
        {
          const $t28059 = game.asteroids;
          {
            const $t28064 = { $: "$Clo_$lam28060$3707", _0: $lam28060$apply$3707, _1: s };
            return List$any$List_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28059, $t28064);
          }
        }
      })();
      return (!$t28065);
    }
  }
}
const $lam28058$apply$3706$clo = { _0: ($_, $clo, s) => $lam28058$apply$3706($clo, s) };

function $lam28060$apply$3707($clo, a) {
  {
    const s = (() => {
      return $clo._1;
    })();
    {
      const $t28061 = a.x;
      {
        const $t28062 = a.y;
        {
          const $t28063 = a.radius;
          {
            const $t28041_i10624 = s.x;
            {
              const $t28042_i10625 = s.y;
              {
                const $t27359_i10004_i10630 = (() => {
                  {
                    const dx_i3632_i10000_i10626 = ($t28061 - $t28041_i10624);
                    {
                      const dy_i3633_i10001_i10627 = ($t28062 - $t28042_i10625);
                      {
                        const $t27357_i3634_i10002_i10628 = (dx_i3632_i10000_i10626 * dx_i3632_i10000_i10626);
                        {
                          const $t27358_i3635_i10003_i10629 = (dy_i3633_i10001_i10627 * dy_i3633_i10001_i10627);
                          return ($t27357_i3634_i10002_i10628 + $t27358_i3635_i10003_i10629);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27362_i10007_i10633 = (() => {
                    {
                      const $t27360_i10005_i10631 = (3. + $t28063);
                      {
                        const $t27361_i10006_i10632 = (3. + $t28063);
                        return ($t27360_i10005_i10631 * $t27361_i10006_i10632);
                      }
                    }
                  })();
                  return ($t27359_i10004_i10630 <= $t27362_i10007_i10633);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28060$apply$3707$clo = { _0: ($_, $clo, a) => $lam28060$apply$3707($clo, a) };

function $lam28077$apply$3708($clo, sh) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28078 = game.player_shots;
      {
        const $t28080 = { $: "$Clo_$lam28079$3709", _0: $lam28079$apply$3709, _1: sh };
        return List$any$List_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28078, $t28080);
      }
    }
  }
}
const $lam28077$apply$3708$clo = { _0: ($_, $clo, sh) => $lam28077$apply$3708($clo, sh) };

function $lam28079$apply$3709($clo, s) {
  {
    const sh = (() => {
      return $clo._1;
    })();
    return Perihelion$Combat$ship_shot_hit(sh, s);
  }
}
const $lam28079$apply$3709$clo = { _0: ($_, $clo, s) => $lam28079$apply$3709($clo, s) };

function $lam28083$apply$3710($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28087 = (() => {
        {
          const $t28084 = game.ships;
          {
            const $t28086 = { $: "$Clo_$lam28085$3711", _0: $lam28085$apply$3711, _1: s };
            return List$any$List_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float$Fn_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float_Bool($t28084, $t28086);
          }
        }
      })();
      return (!$t28087);
    }
  }
}
const $lam28083$apply$3710$clo = { _0: ($_, $clo, s) => $lam28083$apply$3710($clo, s) };

function $lam28085$apply$3711($clo, sh) {
  {
    const s = (() => {
      return $clo._1;
    })();
    return Perihelion$Combat$ship_shot_hit(sh, s);
  }
}
const $lam28085$apply$3711$clo = { _0: ($_, $clo, sh) => $lam28085$apply$3711($clo, sh) };

function $lam28134$apply$3713($clo, p) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28127_i10636 = p.x;
      {
        const $t28128_i10637 = p.y;
        {
          const $t28130_i10638 = game.ball_x;
          {
            const $t28131_i10639 = game.ball_y;
            {
              const $t27359_i10023_i10644 = (() => {
                {
                  const dx_i3632_i10019_i10640 = ($t28130_i10638 - $t28127_i10636);
                  {
                    const dy_i3633_i10020_i10641 = ($t28131_i10639 - $t28128_i10637);
                    {
                      const $t27357_i3634_i10021_i10642 = (dx_i3632_i10019_i10640 * dx_i3632_i10019_i10640);
                      {
                        const $t27358_i3635_i10022_i10643 = (dy_i3633_i10020_i10641 * dy_i3633_i10020_i10641);
                        return ($t27357_i3634_i10021_i10642 + $t27358_i3635_i10022_i10643);
                      }
                    }
                  }
                }
              })();
              {
                const $t27362_i10026_i10647 = (() => {
                  {
                    const $t27360_i10024_i10645 = (12. + 6.);
                    {
                      const $t27361_i10025_i10646 = (12. + 6.);
                      return ($t27360_i10024_i10645 * $t27361_i10025_i10646);
                    }
                  }
                })();
                return ($t27359_i10023_i10644 <= $t27362_i10026_i10647);
              }
            }
          }
        }
      }
    }
  }
}
const $lam28134$apply$3713$clo = { _0: ($_, $clo, p) => $lam28134$apply$3713($clo, p) };

function $lam28138$apply$3714($clo, q) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28139 = (() => {
        {
          const $t28127_i10650 = q.x;
          {
            const $t28128_i10651 = q.y;
            {
              const $t28130_i10652 = game.ball_x;
              {
                const $t28131_i10653 = game.ball_y;
                {
                  const $t27359_i10023_i10658 = (() => {
                    {
                      const dx_i3632_i10019_i10654 = ($t28130_i10652 - $t28127_i10650);
                      {
                        const dy_i3633_i10020_i10655 = ($t28131_i10653 - $t28128_i10651);
                        {
                          const $t27357_i3634_i10021_i10656 = (dx_i3632_i10019_i10654 * dx_i3632_i10019_i10654);
                          {
                            const $t27358_i3635_i10022_i10657 = (dy_i3633_i10020_i10655 * dy_i3633_i10020_i10655);
                            return ($t27357_i3634_i10021_i10656 + $t27358_i3635_i10022_i10657);
                          }
                        }
                      }
                    }
                  })();
                  {
                    const $t27362_i10026_i10661 = (() => {
                      {
                        const $t27360_i10024_i10659 = (12. + 6.);
                        {
                          const $t27361_i10025_i10660 = (12. + 6.);
                          return ($t27360_i10024_i10659 * $t27361_i10025_i10660);
                        }
                      }
                    })();
                    return ($t27359_i10023_i10658 <= $t27362_i10026_i10661);
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t28139);
    }
  }
}
const $lam28138$apply$3714$clo = { _0: ($_, $clo, q) => $lam28138$apply$3714($clo, q) };

function $jp28156$apply$3715($clo) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const p = (() => {
        return $clo._2;
      })();
      {
        const remaining = (() => {
          return $clo._3;
        })();
        {
          const $t28154 = (() => {
            {
              const $t28153 = p.kind;
              return Perihelion$Core$apply_upgrade(game, $t28153);
            }
          })();
          return ({ ...$t28154, pickups: remaining });
        }
      }
    }
  }
}
const $jp28156$apply$3715$clo = { _0: ($_, $clo) => $jp28156$apply$3715($clo) };

function $jp28160$apply$3716($clo) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const p = (() => {
        return $clo._2;
      })();
      {
        const remaining = (() => {
          return $clo._3;
        })();
        {
          const $t28154 = (() => {
            {
              const $t28153 = p.kind;
              return Perihelion$Core$apply_upgrade(game, $t28153);
            }
          })();
          return ({ ...$t28154, pickups: remaining });
        }
      }
    }
  }
}
const $jp28160$apply$3716$clo = { _0: ($_, $clo) => $jp28160$apply$3716($clo) };

function $lam28181$apply$3717($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28174_i10766 = game.ball_x;
      {
        const $t28175_i10767 = game.ball_y;
        {
          const $t28041_i10398_i10768 = s.x;
          {
            const $t28042_i10399_i10769 = s.y;
            {
              const $t27359_i10004_i10404_i10774 = (() => {
                {
                  const dx_i3632_i10000_i10400_i10770 = ($t28174_i10766 - $t28041_i10398_i10768);
                  {
                    const dy_i3633_i10001_i10401_i10771 = ($t28175_i10767 - $t28042_i10399_i10769);
                    {
                      const $t27357_i3634_i10002_i10402_i10772 = (dx_i3632_i10000_i10400_i10770 * dx_i3632_i10000_i10400_i10770);
                      {
                        const $t27358_i3635_i10003_i10403_i10773 = (dy_i3633_i10001_i10401_i10771 * dy_i3633_i10001_i10401_i10771);
                        return ($t27357_i3634_i10002_i10402_i10772 + $t27358_i3635_i10003_i10403_i10773);
                      }
                    }
                  }
                }
              })();
              {
                const $t27362_i10007_i10407_i10777 = (() => {
                  {
                    const $t27360_i10005_i10405_i10775 = (3. + 6.);
                    {
                      const $t27361_i10006_i10406_i10776 = (3. + 6.);
                      return ($t27360_i10005_i10405_i10775 * $t27361_i10006_i10406_i10776);
                    }
                  }
                })();
                return ($t27359_i10004_i10404_i10774 <= $t27362_i10007_i10407_i10777);
              }
            }
          }
        }
      }
    }
  }
}
const $lam28181$apply$3717$clo = { _0: ($_, $clo, s) => $lam28181$apply$3717($clo, s) };

function $lam28186$apply$3718($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28187 = (() => {
        {
          const $t28174_i10780 = game.ball_x;
          {
            const $t28175_i10781 = game.ball_y;
            {
              const $t28041_i10398_i10782 = s.x;
              {
                const $t28042_i10399_i10783 = s.y;
                {
                  const $t27359_i10004_i10404_i10788 = (() => {
                    {
                      const dx_i3632_i10000_i10400_i10784 = ($t28174_i10780 - $t28041_i10398_i10782);
                      {
                        const dy_i3633_i10001_i10401_i10785 = ($t28175_i10781 - $t28042_i10399_i10783);
                        {
                          const $t27357_i3634_i10002_i10402_i10786 = (dx_i3632_i10000_i10400_i10784 * dx_i3632_i10000_i10400_i10784);
                          {
                            const $t27358_i3635_i10003_i10403_i10787 = (dy_i3633_i10001_i10401_i10785 * dy_i3633_i10001_i10401_i10785);
                            return ($t27357_i3634_i10002_i10402_i10786 + $t27358_i3635_i10003_i10403_i10787);
                          }
                        }
                      }
                    }
                  })();
                  {
                    const $t27362_i10007_i10407_i10791 = (() => {
                      {
                        const $t27360_i10005_i10405_i10789 = (3. + 6.);
                        {
                          const $t27361_i10006_i10406_i10790 = (3. + 6.);
                          return ($t27360_i10005_i10405_i10789 * $t27361_i10006_i10406_i10790);
                        }
                      }
                    })();
                    return ($t27359_i10004_i10404_i10788 <= $t27362_i10007_i10407_i10791);
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t28187);
    }
  }
}
const $lam28186$apply$3718$clo = { _0: ($_, $clo, s) => $lam28186$apply$3718($clo, s) };

function $lam28191$apply$3719($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28168_i10664 = a.x;
      {
        const $t28169_i10665 = a.y;
        {
          const $t28170_i10666 = a.radius;
          {
            const $t28171_i10667 = game.ball_x;
            {
              const $t28172_i10668 = game.ball_y;
              {
                const $t27359_i10051_i10673 = (() => {
                  {
                    const dx_i3632_i10047_i10669 = ($t28171_i10667 - $t28168_i10664);
                    {
                      const dy_i3633_i10048_i10670 = ($t28172_i10668 - $t28169_i10665);
                      {
                        const $t27357_i3634_i10049_i10671 = (dx_i3632_i10047_i10669 * dx_i3632_i10047_i10669);
                        {
                          const $t27358_i3635_i10050_i10672 = (dy_i3633_i10048_i10670 * dy_i3633_i10048_i10670);
                          return ($t27357_i3634_i10049_i10671 + $t27358_i3635_i10050_i10672);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27362_i10054_i10676 = (() => {
                    {
                      const $t27360_i10052_i10674 = ($t28170_i10666 + 6.);
                      {
                        const $t27361_i10053_i10675 = ($t28170_i10666 + 6.);
                        return ($t27360_i10052_i10674 * $t27361_i10053_i10675);
                      }
                    }
                  })();
                  return ($t27359_i10051_i10673 <= $t27362_i10054_i10676);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28191$apply$3719$clo = { _0: ($_, $clo, a) => $lam28191$apply$3719($clo, a) };

function $lam28194$apply$3720($clo, sh) {
  {
    const game = (() => {
      return $clo._1;
    })();
    return Perihelion$Combat$ball_hits_ship(game, sh);
  }
}
const $lam28194$apply$3720$clo = { _0: ($_, $clo, sh) => $lam28194$apply$3720($clo, sh) };

function $lam28210$apply$3721($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28168_i10679 = a.x;
      {
        const $t28169_i10680 = a.y;
        {
          const $t28170_i10681 = a.radius;
          {
            const $t28171_i10682 = game.ball_x;
            {
              const $t28172_i10683 = game.ball_y;
              {
                const $t27359_i10051_i10688 = (() => {
                  {
                    const dx_i3632_i10047_i10684 = ($t28171_i10682 - $t28168_i10679);
                    {
                      const dy_i3633_i10048_i10685 = ($t28172_i10683 - $t28169_i10680);
                      {
                        const $t27357_i3634_i10049_i10686 = (dx_i3632_i10047_i10684 * dx_i3632_i10047_i10684);
                        {
                          const $t27358_i3635_i10050_i10687 = (dy_i3633_i10048_i10685 * dy_i3633_i10048_i10685);
                          return ($t27357_i3634_i10049_i10686 + $t27358_i3635_i10050_i10687);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27362_i10054_i10691 = (() => {
                    {
                      const $t27360_i10052_i10689 = ($t28170_i10681 + 6.);
                      {
                        const $t27361_i10053_i10690 = ($t28170_i10681 + 6.);
                        return ($t27360_i10052_i10689 * $t27361_i10053_i10690);
                      }
                    }
                  })();
                  return ($t27359_i10051_i10688 <= $t27362_i10054_i10691);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28210$apply$3721$clo = { _0: ($_, $clo, a) => $lam28210$apply$3721($clo, a) };

function $lam28215$apply$3722($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28216 = (() => {
        {
          const $t28168_i10694 = a.x;
          {
            const $t28169_i10695 = a.y;
            {
              const $t28170_i10696 = a.radius;
              {
                const $t28171_i10697 = game.ball_x;
                {
                  const $t28172_i10698 = game.ball_y;
                  {
                    const $t27359_i10051_i10703 = (() => {
                      {
                        const dx_i3632_i10047_i10699 = ($t28171_i10697 - $t28168_i10694);
                        {
                          const dy_i3633_i10048_i10700 = ($t28172_i10698 - $t28169_i10695);
                          {
                            const $t27357_i3634_i10049_i10701 = (dx_i3632_i10047_i10699 * dx_i3632_i10047_i10699);
                            {
                              const $t27358_i3635_i10050_i10702 = (dy_i3633_i10048_i10700 * dy_i3633_i10048_i10700);
                              return ($t27357_i3634_i10049_i10701 + $t27358_i3635_i10050_i10702);
                            }
                          }
                        }
                      }
                    })();
                    {
                      const $t27362_i10054_i10706 = (() => {
                        {
                          const $t27360_i10052_i10704 = ($t28170_i10696 + 6.);
                          {
                            const $t27361_i10053_i10705 = ($t28170_i10696 + 6.);
                            return ($t27360_i10052_i10704 * $t27361_i10053_i10705);
                          }
                        }
                      })();
                      return ($t27359_i10051_i10703 <= $t27362_i10054_i10706);
                    }
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t28216);
    }
  }
}
const $lam28215$apply$3722$clo = { _0: ($_, $clo, a) => $lam28215$apply$3722($clo, a) };

function $lam28220$apply$3723($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28221 = (() => {
        {
          const $t28174_i10794 = game.ball_x;
          {
            const $t28175_i10795 = game.ball_y;
            {
              const $t28041_i10398_i10796 = s.x;
              {
                const $t28042_i10399_i10797 = s.y;
                {
                  const $t27359_i10004_i10404_i10802 = (() => {
                    {
                      const dx_i3632_i10000_i10400_i10798 = ($t28174_i10794 - $t28041_i10398_i10796);
                      {
                        const dy_i3633_i10001_i10401_i10799 = ($t28175_i10795 - $t28042_i10399_i10797);
                        {
                          const $t27357_i3634_i10002_i10402_i10800 = (dx_i3632_i10000_i10400_i10798 * dx_i3632_i10000_i10400_i10798);
                          {
                            const $t27358_i3635_i10003_i10403_i10801 = (dy_i3633_i10001_i10401_i10799 * dy_i3633_i10001_i10401_i10799);
                            return ($t27357_i3634_i10002_i10402_i10800 + $t27358_i3635_i10003_i10403_i10801);
                          }
                        }
                      }
                    }
                  })();
                  {
                    const $t27362_i10007_i10407_i10805 = (() => {
                      {
                        const $t27360_i10005_i10405_i10803 = (3. + 6.);
                        {
                          const $t27361_i10006_i10406_i10804 = (3. + 6.);
                          return ($t27360_i10005_i10405_i10803 * $t27361_i10006_i10406_i10804);
                        }
                      }
                    })();
                    return ($t27359_i10004_i10404_i10802 <= $t27362_i10007_i10407_i10805);
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t28221);
    }
  }
}
const $lam28220$apply$3723$clo = { _0: ($_, $clo, s) => $lam28220$apply$3723($clo, s) };

function $lam28225$apply$3724($clo, sh) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28226 = Perihelion$Combat$ball_hits_ship(game, sh);
      return (!$t28226);
    }
  }
}
const $lam28225$apply$3724$clo = { _0: ($_, $clo, sh) => $lam28225$apply$3724($clo, sh) };

function $lam28307$apply$3725($clo, k) {
  {
    const $t28308 = (() => {
      return (k === "w");
    })();
    {
      const $t28309 = (k === "W");
      return ($t28308 || $t28309);
    }
  }
}
const $lam28307$apply$3725$clo = { _0: ($_, $clo, k) => $lam28307$apply$3725($clo, k) };

function $lam28311$apply$3726($clo, k) {
  {
    const $t28312 = (() => {
      return (k === "s");
    })();
    {
      const $t28313 = (k === "S");
      return ($t28312 || $t28313);
    }
  }
}
const $lam28311$apply$3726$clo = { _0: ($_, $clo, k) => $lam28311$apply$3726($clo, k) };

function $lam28326$apply$3727($clo, k) {
  {
    const $t28327 = (() => {
      return (k === "e");
    })();
    {
      const $t28328 = (k === "E");
      return ($t28327 || $t28328);
    }
  }
}
const $lam28326$apply$3727$clo = { _0: ($_, $clo, k) => $lam28326$apply$3727($clo, k) };

function $lam28330$apply$3728($clo, k) {
  {
    const $t28331 = (() => {
      return (k === "q");
    })();
    {
      const $t28332 = (k === "Q");
      return ($t28331 || $t28332);
    }
  }
}
const $lam28330$apply$3728$clo = { _0: ($_, $clo, k) => $lam28330$apply$3728($clo, k) };

function $lam28338$apply$3729($clo, k) {
  {
    const $t28339 = (() => {
      return (k === "d");
    })();
    {
      const $t28340 = (k === "D");
      return ($t28339 || $t28340);
    }
  }
}
const $lam28338$apply$3729$clo = { _0: ($_, $clo, k) => $lam28338$apply$3729($clo, k) };

function $lam28342$apply$3730($clo, k) {
  {
    const $t28343 = (() => {
      return (k === "w");
    })();
    {
      const $t28344 = (k === "W");
      return ($t28343 || $t28344);
    }
  }
}
const $lam28342$apply$3730$clo = { _0: ($_, $clo, k) => $lam28342$apply$3730($clo, k) };

function $lam28395$apply$3733($clo, k) {
  {
    const $t28396 = (() => {
      return (k === "x");
    })();
    {
      const $t28397 = (k === "X");
      return ($t28396 || $t28397);
    }
  }
}
const $lam28395$apply$3733$clo = { _0: ($_, $clo, k) => $lam28395$apply$3733($clo, k) };

function $lam28435$apply$3738($clo, k) {
  {
    const $t28436 = (() => {
      return (k === "r");
    })();
    {
      const $t28437 = (k === "R");
      return ($t28436 || $t28437);
    }
  }
}
const $lam28435$apply$3738$clo = { _0: ($_, $clo, k) => $lam28435$apply$3738($clo, k) };

function $jp28748$apply$3750($clo) {
  {
    const $f28743 = (() => {
      return $clo._1;
    })();
    {
      const fallback = (() => {
        return $clo._2;
      })();
      {
        const rest = (() => {
          return $f28743;
        })();
        return Perihelion$Core$top_star(rest, fallback);
      }
    }
  }
}
const $jp28748$apply$3750$clo = { _0: ($_, $clo) => $jp28748$apply$3750($clo) };

function $lam28953$apply$3762($clo, r) {
  return Perihelion$Core$encode_run(r);
}
const $lam28953$apply$3762$clo = { _0: ($_, $clo, r) => $lam28953$apply$3762($clo, r) };

function $jp28967$apply$3763($clo) {
  return { $: "None" };
}
const $jp28967$apply$3763$clo = { _0: ($_, $clo) => $jp28967$apply$3763($clo) };

function $jp28971$apply$3764($clo) {
  {
    const $jp_clo28968 = (() => {
      return $clo._1;
    })();
    {
      const $jp_clo28970 = (() => {
        return { $: "$Clo_$jp28969$3765", _0: $jp28969$apply$3765, _1: $jp_clo28968 };
      })();
      return $jp28969$apply$3765($jp_clo28970);
    }
  }
}
const $jp28971$apply$3764$clo = { _0: ($_, $clo) => $jp28971$apply$3764($clo) };

function $jp28969$apply$3765($clo) {
  {
    const $jp_clo28968 = (() => {
      return $clo._1;
    })();
    return $jp_clo28968._0($jp_clo28968);
  }
}
const $jp28969$apply$3765$clo = { _0: ($_, $clo) => $jp28969$apply$3765($clo) };

function $jp28975$apply$3766($clo) {
  {
    const $jp_clo28972 = (() => {
      return $clo._1;
    })();
    return $jp_clo28972._0($jp_clo28972);
  }
}
const $jp28975$apply$3766$clo = { _0: ($_, $clo) => $jp28975$apply$3766($clo) };

function $jp28979$apply$3767($clo) {
  {
    const $jp_clo28976 = (() => {
      return $clo._1;
    })();
    {
      const $jp_clo28978 = (() => {
        return { $: "$Clo_$jp28977$3768", _0: $jp28977$apply$3768, _1: $jp_clo28976 };
      })();
      return $jp28977$apply$3768($jp_clo28978);
    }
  }
}
const $jp28979$apply$3767$clo = { _0: ($_, $clo) => $jp28979$apply$3767($clo) };

function $jp28977$apply$3768($clo) {
  {
    const $jp_clo28976 = (() => {
      return $clo._1;
    })();
    return $jp_clo28976._0($jp_clo28976);
  }
}
const $jp28977$apply$3768$clo = { _0: ($_, $clo) => $jp28977$apply$3768($clo) };

function $jp28983$apply$3769($clo) {
  {
    const $jp_clo28980 = (() => {
      return $clo._1;
    })();
    return $jp_clo28980._0($jp_clo28980);
  }
}
const $jp28983$apply$3769$clo = { _0: ($_, $clo) => $jp28983$apply$3769($clo) };

function $jp28987$apply$3770($clo) {
  {
    const $jp_clo28984 = (() => {
      return $clo._1;
    })();
    {
      const $jp_clo28986 = (() => {
        return { $: "$Clo_$jp28985$3771", _0: $jp28985$apply$3771, _1: $jp_clo28984 };
      })();
      return $jp28985$apply$3771($jp_clo28986);
    }
  }
}
const $jp28987$apply$3770$clo = { _0: ($_, $clo) => $jp28987$apply$3770($clo) };

function $jp28985$apply$3771($clo) {
  {
    const $jp_clo28984 = (() => {
      return $clo._1;
    })();
    return $jp_clo28984._0($jp_clo28984);
  }
}
const $jp28985$apply$3771$clo = { _0: ($_, $clo) => $jp28985$apply$3771($clo) };

function $lam29177$apply$3780($clo, u) {
  {
    const owned = (() => {
      return $clo._1;
    })();
    switch (u.$) {
      case "OffenseWeapon": {
        const $f29179 = u._0;
        {
          const k = $f29179;
          {
            const $t29178 = (() => {
              {
                const $t669_i7716 = { $: "$Clo_$lam668$4780", _0: $lam668$apply$4780, _1: k };
                return List$any$List_WeaponKind$Fn_WeaponKind_Bool(owned, $t669_i7716);
              }
            })();
            return (!$t29178);
          }
        }
        break;
      }
      default: {
        return true;
      }
    }
  }
}
const $lam29177$apply$3780$clo = { _0: ($_, $clo, u) => $lam29177$apply$3780($clo, u) };

function $lam29215$apply$3781($clo, u) {
  {
    const k = (() => {
      return $clo._1;
    })();
    switch (u.$) {
      case "SpecialItem": {
        const $f29216 = u._0;
        {
          const sk = $f29216;
          return (sk !== k);
        }
        break;
      }
      default: {
        return true;
      }
    }
  }
}
const $lam29215$apply$3781$clo = { _0: ($_, $clo, u) => $lam29215$apply$3781($clo, u) };

function $lam29273$apply$3783($clo, p) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const $t29266_i7723 = (() => {
        {
          const $t29263_i7720 = p.x;
          {
            const $t29265_i7722 = (() => {
              {
                const $t29264_i7721 = p.vx;
                return ($t29264_i7721 * dt_s);
              }
            })();
            return ($t29263_i7720 + $t29265_i7722);
          }
        }
      })();
      {
        const $t29270_i7727 = (() => {
          {
            const $t29267_i7724 = p.y;
            {
              const $t29269_i7726 = (() => {
                {
                  const $t29268_i7725 = p.vy;
                  return ($t29268_i7725 * dt_s);
                }
              })();
              return ($t29267_i7724 + $t29269_i7726);
            }
          }
        })();
        {
          const $t29272_i7729 = (() => {
            {
              const $t29271_i7728 = p.life;
              return ($t29271_i7728 - dt_s);
            }
          })();
          return ({ ...p, x: $t29266_i7723, y: $t29270_i7727, life: $t29272_i7729 });
        }
      }
    }
  }
}
const $lam29273$apply$3783$clo = { _0: ($_, $clo, p) => $lam29273$apply$3783($clo, p) };

function $lam29276$apply$3784($clo, p) {
  {
    const $t29277 = p.life;
    return ($t29277 > 0.);
  }
}
const $lam29276$apply$3784$clo = { _0: ($_, $clo, p) => $lam29276$apply$3784($clo, p) };

function $jp29422$apply$3787($clo) {
  {
    const $f29416 = (() => {
      return $clo._1;
    })();
    {
      const $f29417 = (() => {
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
              return $f29417;
            })();
            {
              const o = (() => {
                return $f29416;
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
                  const $t29412 = s.x;
                  {
                    const $t29413 = s.y;
                    {
                      const $t29414 = o.radius;
                      return Canvas$arc(ctx, $t29412, $t29413, $t29414, 0., 6.28318530718);
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
const $jp29422$apply$3787$clo = { _0: ($_, $clo) => $jp29422$apply$3787($clo) };

function $jp29461$apply$3790($clo) {
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
          const $t29460 = dot_count(s);
          return draw_pulse_particle(ctx, s, t, $t29460, 0);
        }
      }
    }
  }
}
const $jp29461$apply$3790$clo = { _0: ($_, $clo) => $jp29461$apply$3790($clo) };

function $jp29463$apply$3791($clo) {
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
          const $t29460 = dot_count(s);
          return draw_pulse_particle(ctx, s, t, $t29460, 0);
        }
      }
    }
  }
}
const $jp29463$apply$3791$clo = { _0: ($_, $clo) => $jp29463$apply$3791($clo) };

function $jp29597$apply$3794($clo) {
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
const $jp29597$apply$3794$clo = { _0: ($_, $clo) => $jp29597$apply$3794($clo) };

function $lam29876$apply$3815($clo, k) {
  {
    const $t29877 = (() => {
      return (k === "m");
    })();
    {
      const $t29878 = (k === "M");
      return ($t29877 || $t29878);
    }
  }
}
const $lam29876$apply$3815$clo = { _0: ($_, $clo, k) => $lam29876$apply$3815($clo, k) };

function $jp29934$apply$3817($clo) {
  {
    const cursor = (() => {
      return $clo._1;
    })();
    {
      const game = (() => {
        return $clo._2;
      })();
      {
        const keys = (() => {
          return $clo._3;
        })();
        {
          const taps = (() => {
            return $clo._4;
          })();
          {
            const view_h = (() => {
              return $clo._5;
            })();
            {
              const view_w = (() => {
                return $clo._6;
              })();
              return Perihelion$Core$update(game, taps, keys, cursor, view_w, view_h, 0.0166667);
            }
          }
        }
      }
    }
  }
}
const $jp29934$apply$3817$clo = { _0: ($_, $clo) => $jp29934$apply$3817($clo) };

function $lam29945$apply$3818($clo, _) {
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
const $lam29945$apply$3818$clo = { _0: ($_, $clo, _) => $lam29945$apply$3818($clo, _) };

function $lam29958$apply$3819($clo, _) {
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
const $lam29958$apply$3819$clo = { _0: ($_, $clo, _) => $lam29958$apply$3819($clo, _) };

function go$apply$4080($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f247 = lst._0;
        const $f248 = lst._1;
        {
          const t = $f248;
          {
            const h = $f247;
            {
              const $t246 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t246);
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
const go$apply$4080$clo = { _0: ($_, $clo, lst, acc) => go$apply$4080($clo, lst, acc) };

function go$apply$4307($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f247 = lst._0;
        const $f248 = lst._1;
        {
          const t = $f248;
          {
            const h = $f247;
            {
              const $t246 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t246);
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
const go$apply$4307$clo = { _0: ($_, $clo, lst, acc) => go$apply$4307($clo, lst, acc) };

function go$apply$4747($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f240 = lst._0;
        const $f241 = lst._1;
        {
          const t = $f241;
          {
            const $t239 = (acc + 1);
            return go._0(go, t, $t239);
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
const go$apply$4747$clo = { _0: ($_, $clo, lst, acc) => go$apply$4747($clo, lst, acc) };

function go$apply$4749($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8772 = { $: "$Clo_go$5240", _0: go$apply$5240 };
            {
              const $t253_i8773 = { $: "Nil" };
              return go$apply$5240(go_i8772, acc, $t253_i8773);
            }
          }
          break;
        }
        case "Cons": {
          const $f296 = lst._0;
          const $f297 = lst._1;
          {
            const t = $f297;
            {
              const h = $f296;
              {
                const $t294 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t294 === true) {
                  return (() => {
                    {
                      const $t295 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t295);
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
const go$apply$4749$clo = { _0: ($_, $clo, lst, acc) => go$apply$4749($clo, lst, acc) };

function go$apply$4751($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8777 = { $: "$Clo_go$5240", _0: go$apply$5240 };
            {
              const $t253_i8778 = { $: "Nil" };
              return go$apply$5240(go_i8777, acc, $t253_i8778);
            }
          }
          break;
        }
        case "Cons": {
          const $f264 = lst._0;
          const $f265 = lst._1;
          {
            const t = $f265;
            {
              const h = $f264;
              {
                const $t262 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t263 = { $: "Cons", _0: $t262, _1: acc };
                  return go._0(go, t, $t263);
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
            const go_i8782 = { $: "$Clo_go$5242", _0: go$apply$5242 };
            {
              const $t253_i8783 = { $: "Nil" };
              return go$apply$5242(go_i8782, acc, $t253_i8783);
            }
          }
          break;
        }
        case "Cons": {
          const $f296 = lst._0;
          const $f297 = lst._1;
          {
            const t = $f297;
            {
              const h = $f296;
              {
                const $t294 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t294 === true) {
                  return (() => {
                    {
                      const $t295 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t295);
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
            const go_i8787 = { $: "$Clo_go$5242", _0: go$apply$5242 };
            {
              const $t253_i8788 = { $: "Nil" };
              return go$apply$5242(go_i8787, acc, $t253_i8788);
            }
          }
          break;
        }
        case "Cons": {
          const $f264 = lst._0;
          const $f265 = lst._1;
          {
            const t = $f265;
            {
              const h = $f264;
              {
                const $t262 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t263 = { $: "Cons", _0: $t262, _1: acc };
                  return go._0(go, t, $t263);
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

function go$apply$4757($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f247 = lst._0;
        const $f248 = lst._1;
        {
          const t = $f248;
          {
            const h = $f247;
            {
              const $t246 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t246);
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
const go$apply$4757$clo = { _0: ($_, $clo, lst, acc) => go$apply$4757($clo, lst, acc) };

function go$apply$4759($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f255 = lst._0;
        const $f256 = lst._1;
        {
          const t = $f256;
          {
            const h = $f255;
            {
              const $t254 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t254);
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
const go$apply$4759$clo = { _0: ($_, $clo, lst, acc) => go$apply$4759($clo, lst, acc) };

function go$apply$4761($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f247 = lst._0;
        const $f248 = lst._1;
        {
          const t = $f248;
          {
            const h = $f247;
            {
              const $t246 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t246);
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
const go$apply$4761$clo = { _0: ($_, $clo, lst, acc) => go$apply$4761($clo, lst, acc) };

function go$apply$4763($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8798 = { $: "$Clo_go$4761", _0: go$apply$4761 };
            {
              const $t253_i8799 = { $: "Nil" };
              return go$apply$4761(go_i8798, acc, $t253_i8799);
            }
          }
          break;
        }
        case "Cons": {
          const $f264 = lst._0;
          const $f265 = lst._1;
          {
            const t = $f265;
            {
              const h = $f264;
              {
                const $t262 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t263 = { $: "Cons", _0: $t262, _1: acc };
                  return go._0(go, t, $t263);
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
const go$apply$4763$clo = { _0: ($_, $clo, lst, acc) => go$apply$4763($clo, lst, acc) };

function go$apply$4765($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8803 = { $: "$Clo_go$4761", _0: go$apply$4761 };
            {
              const $t253_i8804 = { $: "Nil" };
              return go$apply$4761(go_i8803, acc, $t253_i8804);
            }
          }
          break;
        }
        case "Cons": {
          const $f296 = lst._0;
          const $f297 = lst._1;
          {
            const t = $f297;
            {
              const h = $f296;
              {
                const $t294 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t294 === true) {
                  return (() => {
                    {
                      const $t295 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t295);
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
const go$apply$4765$clo = { _0: ($_, $clo, lst, acc) => go$apply$4765($clo, lst, acc) };

function go$apply$4767($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8808 = { $: "$Clo_go$4307", _0: go$apply$4307 };
            {
              const $t253_i8809 = { $: "Nil" };
              return go$apply$4307(go_i8808, acc, $t253_i8809);
            }
          }
          break;
        }
        case "Cons": {
          const $f264 = lst._0;
          const $f265 = lst._1;
          {
            const t = $f265;
            {
              const h = $f264;
              {
                const $t262 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t263 = { $: "Cons", _0: $t262, _1: acc };
                  return go._0(go, t, $t263);
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
const go$apply$4767$clo = { _0: ($_, $clo, lst, acc) => go$apply$4767($clo, lst, acc) };

function go$apply$4769($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f240 = lst._0;
        const $f241 = lst._1;
        {
          const t = $f241;
          {
            const $t239 = (acc + 1);
            return go._0(go, t, $t239);
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
const go$apply$4769$clo = { _0: ($_, $clo, lst, acc) => go$apply$4769($clo, lst, acc) };

function go$apply$4772($clo, lst, yes, no) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const $t546 = (() => {
              {
                const go_i8819 = { $: "$Clo_go$4757", _0: go$apply$4757 };
                {
                  const $t253_i8820 = { $: "Nil" };
                  return go$apply$4757(go_i8819, yes, $t253_i8820);
                }
              }
            })();
            {
              const $t547 = (() => {
                {
                  const go_i8816 = { $: "$Clo_go$4757", _0: go$apply$4757 };
                  {
                    const $t253_i8817 = { $: "Nil" };
                    return go$apply$4757(go_i8816, no, $t253_i8817);
                  }
                }
              })();
              return { _0: $t546, _1: $t547 };
            }
          }
          break;
        }
        case "Cons": {
          const $f551 = lst._0;
          const $f552 = lst._1;
          {
            const t = $f552;
            {
              const h = $f551;
              {
                const $t548 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t548 === true) {
                  return (() => {
                    {
                      const $t549 = { $: "Cons", _0: h, _1: yes };
                      return go._0(go, t, $t549, no);
                    }
                  })();
                } else {
                  return (() => {
                    {
                      const $t550 = { $: "Cons", _0: h, _1: no };
                      return go._0(go, t, yes, $t550);
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
const go$apply$4772$clo = { _0: ($_, $clo, lst, yes, no) => go$apply$4772($clo, lst, yes, no) };

function go$apply$4775($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f240 = lst._0;
        const $f241 = lst._1;
        {
          const t = $f241;
          {
            const $t239 = (acc + 1);
            return go._0(go, t, $t239);
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
const go$apply$4775$clo = { _0: ($_, $clo, lst, acc) => go$apply$4775($clo, lst, acc) };

function go$apply$4778($clo, lst, yes, no) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const $t546 = (() => {
              {
                const go_i8831 = { $: "$Clo_go$4761", _0: go$apply$4761 };
                {
                  const $t253_i8832 = { $: "Nil" };
                  return go$apply$4761(go_i8831, yes, $t253_i8832);
                }
              }
            })();
            {
              const $t547 = (() => {
                {
                  const go_i8828 = { $: "$Clo_go$4761", _0: go$apply$4761 };
                  {
                    const $t253_i8829 = { $: "Nil" };
                    return go$apply$4761(go_i8828, no, $t253_i8829);
                  }
                }
              })();
              return { _0: $t546, _1: $t547 };
            }
          }
          break;
        }
        case "Cons": {
          const $f551 = lst._0;
          const $f552 = lst._1;
          {
            const t = $f552;
            {
              const h = $f551;
              {
                const $t548 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t548 === true) {
                  return (() => {
                    {
                      const $t549 = { $: "Cons", _0: h, _1: yes };
                      return go._0(go, t, $t549, no);
                    }
                  })();
                } else {
                  return (() => {
                    {
                      const $t550 = { $: "Cons", _0: h, _1: no };
                      return go._0(go, t, yes, $t550);
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
const go$apply$4778$clo = { _0: ($_, $clo, lst, yes, no) => go$apply$4778($clo, lst, yes, no) };

function $lam668$apply$4780($clo, y) {
  {
    const x = (() => {
      return $clo._1;
    })();
    return (y === x);
  }
}
const $lam668$apply$4780$clo = { _0: ($_, $clo, y) => $lam668$apply$4780($clo, y) };

function go$apply$4782($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f255 = lst._0;
        const $f256 = lst._1;
        {
          const t = $f256;
          {
            const h = $f255;
            {
              const $t254 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t254);
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
const go$apply$4782$clo = { _0: ($_, $clo, lst, acc) => go$apply$4782($clo, lst, acc) };

function go$apply$4784($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8839 = { $: "$Clo_go$4757", _0: go$apply$4757 };
            {
              const $t253_i8840 = { $: "Nil" };
              return go$apply$4757(go_i8839, acc, $t253_i8840);
            }
          }
          break;
        }
        case "Cons": {
          const $f296 = lst._0;
          const $f297 = lst._1;
          {
            const t = $f297;
            {
              const h = $f296;
              {
                const $t294 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t294 === true) {
                  return (() => {
                    {
                      const $t295 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t295);
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
const go$apply$4784$clo = { _0: ($_, $clo, lst, acc) => go$apply$4784($clo, lst, acc) };

function go$apply$4787($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f255 = lst._0;
        const $f256 = lst._1;
        {
          const t = $f256;
          {
            const h = $f255;
            {
              const $t254 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t254);
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
const go$apply$4787$clo = { _0: ($_, $clo, lst, acc) => go$apply$4787($clo, lst, acc) };

function go$apply$4790($clo, lst, k, acc) {
  {
    const go = $clo;
    {
      const $t499 = (k <= 0);
      if ($t499 === true) {
        return (() => {
          {
            const go_i8851 = { $: "$Clo_go$5089", _0: go$apply$5089 };
            {
              const $t253_i8852 = { $: "Nil" };
              return go$apply$5089(go_i8851, acc, $t253_i8852);
            }
          }
        })();
      } else {
        return (() => {
          switch (lst.$) {
            case "Nil": {
              {
                const go_i8848 = { $: "$Clo_go$5089", _0: go$apply$5089 };
                {
                  const $t253_i8849 = { $: "Nil" };
                  return go$apply$5089(go_i8848, acc, $t253_i8849);
                }
              }
              break;
            }
            case "Cons": {
              const $f502 = lst._0;
              const $f503 = lst._1;
              {
                const t = $f503;
                {
                  const h = $f502;
                  {
                    const $t500 = (k - 1);
                    {
                      const $t501 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t500, $t501);
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
const go$apply$4790$clo = { _0: ($_, $clo, lst, k, acc) => go$apply$4790($clo, lst, k, acc) };

function go$apply$4792($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f240 = lst._0;
        const $f241 = lst._1;
        {
          const t = $f241;
          {
            const $t239 = (acc + 1);
            return go._0(go, t, $t239);
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
const go$apply$4792$clo = { _0: ($_, $clo, lst, acc) => go$apply$4792($clo, lst, acc) };

function go$apply$4796($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f240 = lst._0;
        const $f241 = lst._1;
        {
          const t = $f241;
          {
            const $t239 = (acc + 1);
            return go._0(go, t, $t239);
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
const go$apply$4796$clo = { _0: ($_, $clo, lst, acc) => go$apply$4796($clo, lst, acc) };

function go$apply$4799($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f255 = lst._0;
        const $f256 = lst._1;
        {
          const t = $f256;
          {
            const h = $f255;
            {
              const $t254 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t254);
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
const go$apply$4799$clo = { _0: ($_, $clo, lst, acc) => go$apply$4799($clo, lst, acc) };

function go$apply$4801($clo, lst, k, acc) {
  {
    const go = $clo;
    {
      const $t499 = (k <= 0);
      if ($t499 === true) {
        return (() => {
          {
            const go_i8868 = { $: "$Clo_go$5089", _0: go$apply$5089 };
            {
              const $t253_i8869 = { $: "Nil" };
              return go$apply$5089(go_i8868, acc, $t253_i8869);
            }
          }
        })();
      } else {
        return (() => {
          switch (lst.$) {
            case "Nil": {
              {
                const go_i8865 = { $: "$Clo_go$5089", _0: go$apply$5089 };
                {
                  const $t253_i8866 = { $: "Nil" };
                  return go$apply$5089(go_i8865, acc, $t253_i8866);
                }
              }
              break;
            }
            case "Cons": {
              const $f502 = lst._0;
              const $f503 = lst._1;
              {
                const t = $f503;
                {
                  const h = $f502;
                  {
                    const $t500 = (k - 1);
                    {
                      const $t501 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t500, $t501);
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
const go$apply$4801$clo = { _0: ($_, $clo, lst, k, acc) => go$apply$4801($clo, lst, k, acc) };

function go$apply$4803($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8873 = { $: "$Clo_go$4080", _0: go$apply$4080 };
            {
              const $t253_i8874 = { $: "Nil" };
              return go$apply$4080(go_i8873, acc, $t253_i8874);
            }
          }
          break;
        }
        case "Cons": {
          const $f264 = lst._0;
          const $f265 = lst._1;
          {
            const t = $f265;
            {
              const h = $f264;
              {
                const $t262 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t263 = { $: "Cons", _0: $t262, _1: acc };
                  return go._0(go, t, $t263);
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
const go$apply$4803$clo = { _0: ($_, $clo, lst, acc) => go$apply$4803($clo, lst, acc) };

function go$apply$4805($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f247 = lst._0;
        const $f248 = lst._1;
        {
          const t = $f248;
          {
            const h = $f247;
            {
              const $t246 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t246);
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
const go$apply$4805$clo = { _0: ($_, $clo, lst, acc) => go$apply$4805($clo, lst, acc) };

function go$apply$4807($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f255 = lst._0;
        const $f256 = lst._1;
        {
          const t = $f256;
          {
            const h = $f255;
            {
              const $t254 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t254);
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
const go$apply$4807$clo = { _0: ($_, $clo, lst, acc) => go$apply$4807($clo, lst, acc) };

function go$apply$4809($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8882 = { $: "$Clo_go$5249", _0: go$apply$5249 };
            {
              const $t253_i8883 = { $: "Nil" };
              return go$apply$5249(go_i8882, acc, $t253_i8883);
            }
          }
          break;
        }
        case "Cons": {
          const $f296 = lst._0;
          const $f297 = lst._1;
          {
            const t = $f297;
            {
              const h = $f296;
              {
                const $t294 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t294 === true) {
                  return (() => {
                    {
                      const $t295 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t295);
                    }
                  })();
                } else {
                  return (() => {
                    return go._0(go, t, acc);
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
const go$apply$4809$clo = { _0: ($_, $clo, lst, acc) => go$apply$4809($clo, lst, acc) };

function go$apply$4812($clo, lst, k, acc) {
  {
    const go = $clo;
    {
      const $t499 = (k <= 0);
      if ($t499 === true) {
        return (() => {
          {
            const go_i8891 = { $: "$Clo_go$5089", _0: go$apply$5089 };
            {
              const $t253_i8892 = { $: "Nil" };
              return go$apply$5089(go_i8891, acc, $t253_i8892);
            }
          }
        })();
      } else {
        return (() => {
          switch (lst.$) {
            case "Nil": {
              {
                const go_i8888 = { $: "$Clo_go$5089", _0: go$apply$5089 };
                {
                  const $t253_i8889 = { $: "Nil" };
                  return go$apply$5089(go_i8888, acc, $t253_i8889);
                }
              }
              break;
            }
            case "Cons": {
              const $f502 = lst._0;
              const $f503 = lst._1;
              {
                const t = $f503;
                {
                  const h = $f502;
                  {
                    const $t500 = (k - 1);
                    {
                      const $t501 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t500, $t501);
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
const go$apply$4812$clo = { _0: ($_, $clo, lst, k, acc) => go$apply$4812($clo, lst, k, acc) };

function go$apply$4815($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f240 = lst._0;
        const $f241 = lst._1;
        {
          const t = $f241;
          {
            const $t239 = (acc + 1);
            return go._0(go, t, $t239);
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
const go$apply$4815$clo = { _0: ($_, $clo, lst, acc) => go$apply$4815($clo, lst, acc) };

function go$apply$4817($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8899 = { $: "$Clo_go$5251", _0: go$apply$5251 };
            {
              const $t253_i8900 = { $: "Nil" };
              return go$apply$5251(go_i8899, acc, $t253_i8900);
            }
          }
          break;
        }
        case "Cons": {
          const $f296 = lst._0;
          const $f297 = lst._1;
          {
            const t = $f297;
            {
              const h = $f296;
              {
                const $t294 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t294 === true) {
                  return (() => {
                    {
                      const $t295 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t295);
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
const go$apply$4817$clo = { _0: ($_, $clo, lst, acc) => go$apply$4817($clo, lst, acc) };

function go$apply$4819($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8904 = { $: "$Clo_go$5251", _0: go$apply$5251 };
            {
              const $t253_i8905 = { $: "Nil" };
              return go$apply$5251(go_i8904, acc, $t253_i8905);
            }
          }
          break;
        }
        case "Cons": {
          const $f264 = lst._0;
          const $f265 = lst._1;
          {
            const t = $f265;
            {
              const h = $f264;
              {
                const $t262 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t263 = { $: "Cons", _0: $t262, _1: acc };
                  return go._0(go, t, $t263);
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
const go$apply$4819$clo = { _0: ($_, $clo, lst, acc) => go$apply$4819($clo, lst, acc) };

function go$apply$4821($clo, lst, k, acc) {
  {
    const go = $clo;
    {
      const $t499 = (k <= 0);
      if ($t499 === true) {
        return (() => {
          {
            const go_i8912 = { $: "$Clo_go$5089", _0: go$apply$5089 };
            {
              const $t253_i8913 = { $: "Nil" };
              return go$apply$5089(go_i8912, acc, $t253_i8913);
            }
          }
        })();
      } else {
        return (() => {
          switch (lst.$) {
            case "Nil": {
              {
                const go_i8909 = { $: "$Clo_go$5089", _0: go$apply$5089 };
                {
                  const $t253_i8910 = { $: "Nil" };
                  return go$apply$5089(go_i8909, acc, $t253_i8910);
                }
              }
              break;
            }
            case "Cons": {
              const $f502 = lst._0;
              const $f503 = lst._1;
              {
                const t = $f503;
                {
                  const h = $f502;
                  {
                    const $t500 = (k - 1);
                    {
                      const $t501 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t500, $t501);
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
const go$apply$4821$clo = { _0: ($_, $clo, lst, k, acc) => go$apply$4821($clo, lst, k, acc) };

function go$apply$4823($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f240 = lst._0;
        const $f241 = lst._1;
        {
          const t = $f241;
          {
            const $t239 = (acc + 1);
            return go._0(go, t, $t239);
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
const go$apply$4823$clo = { _0: ($_, $clo, lst, acc) => go$apply$4823($clo, lst, acc) };

function go$apply$5089($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f247 = lst._0;
        const $f248 = lst._1;
        {
          const t = $f248;
          {
            const h = $f247;
            {
              const $t246 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t246);
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
const go$apply$5089$clo = { _0: ($_, $clo, lst, acc) => go$apply$5089($clo, lst, acc) };

function go$apply$5240($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f247 = lst._0;
        const $f248 = lst._1;
        {
          const t = $f248;
          {
            const h = $f247;
            {
              const $t246 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t246);
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
const go$apply$5240$clo = { _0: ($_, $clo, lst, acc) => go$apply$5240($clo, lst, acc) };

function go$apply$5242($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f247 = lst._0;
        const $f248 = lst._1;
        {
          const t = $f248;
          {
            const h = $f247;
            {
              const $t246 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t246);
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
const go$apply$5242$clo = { _0: ($_, $clo, lst, acc) => go$apply$5242($clo, lst, acc) };

function go$apply$5245($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f247 = lst._0;
        const $f248 = lst._1;
        {
          const t = $f248;
          {
            const h = $f247;
            {
              const $t246 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t246);
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
const go$apply$5245$clo = { _0: ($_, $clo, lst, acc) => go$apply$5245($clo, lst, acc) };

function go$apply$5247($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f247 = lst._0;
        const $f248 = lst._1;
        {
          const t = $f248;
          {
            const h = $f247;
            {
              const $t246 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t246);
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
const go$apply$5247$clo = { _0: ($_, $clo, lst, acc) => go$apply$5247($clo, lst, acc) };

function go$apply$5249($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f247 = lst._0;
        const $f248 = lst._1;
        {
          const t = $f248;
          {
            const h = $f247;
            {
              const $t246 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t246);
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
const go$apply$5249$clo = { _0: ($_, $clo, lst, acc) => go$apply$5249($clo, lst, acc) };

function go$apply$5251($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f247 = lst._0;
        const $f248 = lst._1;
        {
          const t = $f248;
          {
            const h = $f247;
            {
              const $t246 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t246);
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
const go$apply$5251$clo = { _0: ($_, $clo, lst, acc) => go$apply$5251($clo, lst, acc) };

export { main };
main();
