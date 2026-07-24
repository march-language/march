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
        const $t15576 = (x + 2654435769);
        return march_int_and($t15576, 4294967295);
      }
    })();
    {
      const x$sh2 = (() => {
        {
          const $t15578 = (() => {
            {
              const $t15577 = march_int_shr(x$sh1, 16);
              return march_int_xor(x$sh1, $t15577);
            }
          })();
          {
            const xh_i9824 = march_int_shr($t15578, 16);
            {
              const xl_i9825 = march_int_and($t15578, 65535);
              {
                const $t15567_i9830 = (() => {
                  {
                    const $t15565_i9828 = (() => {
                      {
                        const $t15564_i9827 = (() => {
                          {
                            const $t15563_i9826 = (xh_i9824 * 569420461);
                            return march_int_and($t15563_i9826, 65535);
                          }
                        })();
                        return ($t15564_i9827 * 65536);
                      }
                    })();
                    {
                      const $t15566_i9829 = (xl_i9825 * 569420461);
                      return ($t15565_i9828 + $t15566_i9829);
                    }
                  }
                })();
                return march_int_and($t15567_i9830, 4294967295);
              }
            }
          }
        }
      })();
      {
        const x$sh3 = (() => {
          {
            const $t15580 = (() => {
              {
                const $t15579 = march_int_shr(x$sh2, 15);
                return march_int_xor(x$sh2, $t15579);
              }
            })();
            {
              const xh_i9813 = march_int_shr($t15580, 16);
              {
                const xl_i9814 = march_int_and($t15580, 65535);
                {
                  const $t15567_i9819 = (() => {
                    {
                      const $t15565_i9817 = (() => {
                        {
                          const $t15564_i9816 = (() => {
                            {
                              const $t15563_i9815 = (xh_i9813 * 1935289751);
                              return march_int_and($t15563_i9815, 65535);
                            }
                          })();
                          return ($t15564_i9816 * 65536);
                        }
                      })();
                      {
                        const $t15566_i9818 = (xl_i9814 * 1935289751);
                        return ($t15565_i9817 + $t15566_i9818);
                      }
                    }
                  })();
                  return march_int_and($t15567_i9819, 4294967295);
                }
              }
            }
          }
        })();
        {
          const $t15581 = march_int_shr(x$sh3, 15);
          return march_int_xor(x$sh3, $t15581);
        }
      }
    }
  }
}
const Random$mix32$clo = { _0: ($_, x) => Random$mix32(x) };

function Random$warmup(rng, k) {
  {
    const $t15582 = (k <= 0);
    if ($t15582 === true) {
      return rng;
    } else {
      return (() => {
        {
          const $p15584 = Random$next_raw(rng);
          {
            const r2 = $p15584._1;
            {
              const $t15583 = (k - 1);
              return Random$warmup(r2, $t15583);
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
          const $t15587 = (() => {
            {
              const $t15585 = (n - lo);
              return ($t15585 / 4294967296);
            }
          })();
          return march_int_and($t15587, 4294967295);
        }
      })();
      {
        const a = Random$mix32(lo);
        {
          const b = (() => {
            {
              const $t15588 = march_int_xor(hi, a);
              return Random$mix32($t15588);
            }
          })();
          {
            const c = (() => {
              {
                const $t15589 = march_int_xor(lo, b);
                return Random$mix32($t15589);
              }
            })();
            {
              const $t15590 = ({ s0: a, s1: b, s2: c, s3: 1 });
              return Random$warmup($t15590, 12);
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
        const $t15595 = (() => {
          {
            const $t15593 = (() => {
              {
                const $t15591 = rng.s0;
                {
                  const $t15592 = rng.s1;
                  return ($t15591 + $t15592);
                }
              }
            })();
            {
              const $t15594 = rng.s3;
              return ($t15593 + $t15594);
            }
          }
        })();
        return march_int_and($t15595, 4294967295);
      }
    })();
    {
      const a = (() => {
        {
          const $t15596 = rng.s1;
          {
            const $t15598 = (() => {
              {
                const $t15597 = rng.s1;
                return march_int_shr($t15597, 9);
              }
            })();
            return march_int_xor($t15596, $t15598);
          }
        }
      })();
      {
        const b = (() => {
          {
            const $t15603 = (() => {
              {
                const $t15599 = rng.s2;
                {
                  const $t15602 = (() => {
                    {
                      const $t15601 = (() => {
                        {
                          const $t15600 = rng.s2;
                          return march_int_shl($t15600, 3);
                        }
                      })();
                      return march_int_and($t15601, 4294967295);
                    }
                  })();
                  return ($t15599 + $t15602);
                }
              }
            })();
            return march_int_and($t15603, 4294967295);
          }
        })();
        {
          const c = (() => {
            {
              const $t15606 = (() => {
                {
                  const $t15605 = (() => {
                    {
                      const $t15604 = rng.s2;
                      {
                        const keep_i1530 = (() => {
                          {
                            const $t15570_i1529 = march_int_shr(4294967295, 21);
                            return march_int_and($t15604, $t15570_i1529);
                          }
                        })();
                        {
                          const $t15571_i1531 = march_int_shl(keep_i1530, 21);
                          {
                            const $t15573_i1533 = march_int_shr($t15604, 11);
                            return march_int_or($t15571_i1531, $t15573_i1533);
                          }
                        }
                      }
                    }
                  })();
                  return ($t15605 + t);
                }
              })();
              return march_int_and($t15606, 4294967295);
            }
          })();
          {
            const $t15610 = (() => {
              {
                const $t15609 = (() => {
                  {
                    const $t15608 = (() => {
                      {
                        const $t15607 = rng.s3;
                        return ($t15607 + 1);
                      }
                    })();
                    return march_int_and($t15608, 4294967295);
                  }
                })();
                return ({ s0: a, s1: b, s2: c, s3: $t15609 });
              }
            })();
            return { _0: t, _1: $t15610 };
          }
        }
      }
    }
  }
}
const Random$next_raw$clo = { _0: ($_, rng) => Random$next_raw(rng) };

function Dom$find(id) {
  {
    const $rc_747 = dom_get_element_by_id$clo._0(dom_get_element_by_id$clo, id);
    return $rc_747;
  }
}
const Dom$find$clo = { _0: ($_, id) => Dom$find(id) };

function Dom$set_attr(el, name, val) {
  {
    const $rc_767 = dom_set_attribute$clo._0(dom_set_attribute$clo, el, name, val);
    return $rc_767;
  }
}
const Dom$set_attr$clo = { _0: ($_, el, name, val) => Dom$set_attr(el, name, val) };

function Dom$taps(el) {
  {
    const $rc_787 = dom_taps$clo._0(dom_taps$clo, el);
    return $rc_787;
  }
}
const Dom$taps$clo = { _0: ($_, el) => Dom$taps(el) };

function Dom$store_get(key) {
  {
    const $rc_788 = dom_store_get$clo._0(dom_store_get$clo, key);
    return $rc_788;
  }
}
const Dom$store_get$clo = { _0: ($_, key) => Dom$store_get(key) };

function Dom$store_set(key, val) {
  {
    const $rc_789 = dom_store_set$clo._0(dom_store_set$clo, key, val);
    return $rc_789;
  }
}
const Dom$store_set$clo = { _0: ($_, key, val) => Dom$store_set(key, val) };

function Dom$pointer_pos(el) {
  {
    const $rc_790 = dom_pointer_pos$clo._0(dom_pointer_pos$clo, el);
    return $rc_790;
  }
}
const Dom$pointer_pos$clo = { _0: ($_, el) => Dom$pointer_pos(el) };

function Dom$on_frame(cb) {
  return dom_request_animation_frame$clo._0(dom_request_animation_frame$clo, cb);
}
const Dom$on_frame$clo = { _0: ($_, cb) => Dom$on_frame(cb) };

function Canvas$get_context(node) {
  {
    const $rc_793 = canvas_get_context$clo._0(canvas_get_context$clo, node);
    return $rc_793;
  }
}
const Canvas$get_context$clo = { _0: ($_, node) => Canvas$get_context(node) };

function Canvas$save(ctx) {
  {
    const $rc_794 = canvas_save$clo._0(canvas_save$clo, ctx);
    return $rc_794;
  }
}
const Canvas$save$clo = { _0: ($_, ctx) => Canvas$save(ctx) };

function Canvas$restore(ctx) {
  {
    const $rc_795 = canvas_restore$clo._0(canvas_restore$clo, ctx);
    return $rc_795;
  }
}
const Canvas$restore$clo = { _0: ($_, ctx) => Canvas$restore(ctx) };

function Canvas$translate(ctx, x, y) {
  {
    const $rc_796 = canvas_translate$clo._0(canvas_translate$clo, ctx, x, y);
    return $rc_796;
  }
}
const Canvas$translate$clo = { _0: ($_, ctx, x, y) => Canvas$translate(ctx, x, y) };

function Canvas$rotate(ctx, angle) {
  {
    const $rc_797 = canvas_rotate$clo._0(canvas_rotate$clo, ctx, angle);
    return $rc_797;
  }
}
const Canvas$rotate$clo = { _0: ($_, ctx, angle) => Canvas$rotate(ctx, angle) };

function Canvas$set_fill_style(ctx, color) {
  {
    const $rc_799 = canvas_set_fill_style$clo._0(canvas_set_fill_style$clo, ctx, color);
    return $rc_799;
  }
}
const Canvas$set_fill_style$clo = { _0: ($_, ctx, color) => Canvas$set_fill_style(ctx, color) };

function Canvas$set_stroke_style(ctx, color) {
  {
    const $rc_800 = canvas_set_stroke_style$clo._0(canvas_set_stroke_style$clo, ctx, color);
    return $rc_800;
  }
}
const Canvas$set_stroke_style$clo = { _0: ($_, ctx, color) => Canvas$set_stroke_style(ctx, color) };

function Canvas$set_line_width(ctx, w) {
  {
    const $rc_801 = canvas_set_line_width$clo._0(canvas_set_line_width$clo, ctx, w);
    return $rc_801;
  }
}
const Canvas$set_line_width$clo = { _0: ($_, ctx, w) => Canvas$set_line_width(ctx, w) };

function Canvas$set_global_alpha(ctx, a) {
  {
    const $rc_802 = canvas_set_global_alpha$clo._0(canvas_set_global_alpha$clo, ctx, a);
    return $rc_802;
  }
}
const Canvas$set_global_alpha$clo = { _0: ($_, ctx, a) => Canvas$set_global_alpha(ctx, a) };

function Canvas$set_font(ctx, font) {
  {
    const $rc_803 = canvas_set_font$clo._0(canvas_set_font$clo, ctx, font);
    return $rc_803;
  }
}
const Canvas$set_font$clo = { _0: ($_, ctx, font) => Canvas$set_font(ctx, font) };

function Canvas$fill_rect(ctx, x, y, w, h) {
  {
    const $rc_805 = canvas_fill_rect$clo._0(canvas_fill_rect$clo, ctx, x, y, w, h);
    return $rc_805;
  }
}
const Canvas$fill_rect$clo = { _0: ($_, ctx, x, y, w, h) => Canvas$fill_rect(ctx, x, y, w, h) };

function Canvas$stroke_rect(ctx, x, y, w, h) {
  {
    const $rc_806 = canvas_stroke_rect$clo._0(canvas_stroke_rect$clo, ctx, x, y, w, h);
    return $rc_806;
  }
}
const Canvas$stroke_rect$clo = { _0: ($_, ctx, x, y, w, h) => Canvas$stroke_rect(ctx, x, y, w, h) };

function Canvas$begin_path(ctx) {
  {
    const $rc_807 = canvas_begin_path$clo._0(canvas_begin_path$clo, ctx);
    return $rc_807;
  }
}
const Canvas$begin_path$clo = { _0: ($_, ctx) => Canvas$begin_path(ctx) };

function Canvas$close_path(ctx) {
  {
    const $rc_808 = canvas_close_path$clo._0(canvas_close_path$clo, ctx);
    return $rc_808;
  }
}
const Canvas$close_path$clo = { _0: ($_, ctx) => Canvas$close_path(ctx) };

function Canvas$move_to(ctx, x, y) {
  {
    const $rc_809 = canvas_move_to$clo._0(canvas_move_to$clo, ctx, x, y);
    return $rc_809;
  }
}
const Canvas$move_to$clo = { _0: ($_, ctx, x, y) => Canvas$move_to(ctx, x, y) };

function Canvas$line_to(ctx, x, y) {
  {
    const $rc_810 = canvas_line_to$clo._0(canvas_line_to$clo, ctx, x, y);
    return $rc_810;
  }
}
const Canvas$line_to$clo = { _0: ($_, ctx, x, y) => Canvas$line_to(ctx, x, y) };

function Canvas$arc(ctx, x, y, radius, start_angle, end_angle) {
  {
    const $rc_811 = canvas_arc$clo._0(canvas_arc$clo, ctx, x, y, radius, start_angle, end_angle);
    return $rc_811;
  }
}
const Canvas$arc$clo = { _0: ($_, ctx, x, y, radius, start_angle, end_angle) => Canvas$arc(ctx, x, y, radius, start_angle, end_angle) };

function Canvas$fill(ctx) {
  {
    const $rc_814 = canvas_fill$clo._0(canvas_fill$clo, ctx);
    return $rc_814;
  }
}
const Canvas$fill$clo = { _0: ($_, ctx) => Canvas$fill(ctx) };

function Canvas$stroke(ctx) {
  {
    const $rc_815 = canvas_stroke$clo._0(canvas_stroke$clo, ctx);
    return $rc_815;
  }
}
const Canvas$stroke$clo = { _0: ($_, ctx) => Canvas$stroke(ctx) };

function Canvas$fill_noise_circle(ctx, cx, cy, radius, alpha) {
  {
    const $rc_816 = canvas_fill_noise_circle$clo._0(canvas_fill_noise_circle$clo, ctx, cx, cy, radius, alpha);
    return $rc_816;
  }
}
const Canvas$fill_noise_circle$clo = { _0: ($_, ctx, cx, cy, radius, alpha) => Canvas$fill_noise_circle(ctx, cx, cy, radius, alpha) };

function Canvas$fill_text(ctx, text, x, y) {
  {
    const $rc_817 = canvas_fill_text$clo._0(canvas_fill_text$clo, ctx, text, x, y);
    return $rc_817;
  }
}
const Canvas$fill_text$clo = { _0: ($_, ctx, text, x, y) => Canvas$fill_text(ctx, text, x, y) };

function Canvas$set_text_align(ctx, align) {
  {
    const $rc_819 = canvas_set_text_align$clo._0(canvas_set_text_align$clo, ctx, align);
    return $rc_819;
  }
}
const Canvas$set_text_align$clo = { _0: ($_, ctx, align) => Canvas$set_text_align(ctx, align) };

function Audio$resume(actx) {
  {
    const $rc_823 = audio_resume$clo._0(audio_resume$clo, actx);
    return $rc_823;
  }
}
const Audio$resume$clo = { _0: ($_, actx) => Audio$resume(actx) };

function Audio$beep(actx, freq, duration, wave) {
  {
    const $rc_824 = audio_beep$clo._0(audio_beep$clo, actx, freq, duration, wave);
    return $rc_824;
  }
}
const Audio$beep$clo = { _0: ($_, actx, freq, duration, wave) => Audio$beep(actx, freq, duration, wave) };

function Audio$sweep(actx, freq_from, freq_to, duration, wave) {
  {
    const $rc_825 = audio_sweep$clo._0(audio_sweep$clo, actx, freq_from, freq_to, duration, wave);
    return $rc_825;
  }
}
const Audio$sweep$clo = { _0: ($_, actx, freq_from, freq_to, duration, wave) => Audio$sweep(actx, freq_from, freq_to, duration, wave) };

function Audio$noise_burst(actx, duration, filter_freq) {
  {
    const $rc_826 = audio_noise_burst$clo._0(audio_noise_burst$clo, actx, duration, filter_freq);
    return $rc_826;
  }
}
const Audio$noise_burst$clo = { _0: ($_, actx, duration, filter_freq) => Audio$noise_burst(actx, duration, filter_freq) };

function Perihelion$Combat$starkiller_target_idx(game) {
  {
    const raw = (() => {
      {
        const $t27395 = (() => {
          {
            const $t27394 = game.current;
            return ($t27394 + 1);
          }
        })();
        {
          const $t27396 = game.starkiller_target_offset;
          return ($t27395 + $t27396);
        }
      }
    })();
    {
      const max_idx = (() => {
        {
          const $t27398 = (() => {
            {
              const $t27397 = game.stars;
              {
                const go_i3640 = { $: "$Clo_go$4754", _0: go$apply$4754 };
                return go$apply$4754(go_i3640, $t27397, 0);
              }
            }
          })();
          return ($t27398 - 1);
        }
      })();
      {
        const $t27399 = (raw > max_idx);
        if ($t27399 === true) {
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
        const $t27408 = game.spawn_timer;
        return ($t27408 - dt_s);
      }
    })();
    {
      const $t27409 = (t > 0.);
      if ($t27409 === true) {
        return ({ ...game, spawn_timer: t });
      } else {
        return (() => {
          {
            const $p27435 = (() => {
              {
                const $t27410 = game.rng;
                {
                  const $p29061_i10413_i10712_i10887 = (() => {
                    {
                      const $p15619_i10138_i10408_i10707_i10882 = (() => {
                        {
                          const $p15616_i1544_i10128_i10399_i10698_i10873 = Random$next_raw($t27410);
                          {
                            const hi_i1545_i10129_i10400_i10699_i10874 = $p15616_i1544_i10128_i10399_i10698_i10873._0;
                            {
                              const rng2_i1546_i10130_i10401_i10700_i10875 = $p15616_i1544_i10128_i10399_i10698_i10873._1;
                              {
                                const $p15615_i1547_i10131_i10402_i10701_i10876 = Random$next_raw(rng2_i1546_i10130_i10401_i10700_i10875);
                                {
                                  const lo_i1548_i10132_i10403_i10702_i10877 = $p15615_i1547_i10131_i10402_i10701_i10876._0;
                                  {
                                    const rng3_i1549_i10133_i10404_i10703_i10878 = $p15615_i1547_i10131_i10402_i10701_i10876._1;
                                    {
                                      const $t15614_i1553_i10137_i10407_i10706_i10881 = (() => {
                                        {
                                          const $t15613_i1552_i10136_i10406_i10705_i10880 = (() => {
                                            {
                                              const $t15611_i1550_i10134_i10405_i10704_i10879 = march_int_and(hi_i1545_i10129_i10400_i10699_i10874, 1048575);
                                              return ($t15611_i1550_i10134_i10405_i10704_i10879 * 4294967296);
                                            }
                                          })();
                                          return ($t15613_i1552_i10136_i10406_i10705_i10880 + lo_i1548_i10132_i10403_i10702_i10877);
                                        }
                                      })();
                                      return { _0: $t15614_i1553_i10137_i10407_i10706_i10881, _1: rng3_i1549_i10133_i10404_i10703_i10878 };
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      })();
                      {
                        const bits_i10139_i10409_i10708_i10883 = $p15619_i10138_i10408_i10707_i10882._0;
                        {
                          const rng2_i10140_i10410_i10709_i10884 = $p15619_i10138_i10408_i10707_i10882._1;
                          {
                            const $t15618_i10142_i10412_i10711_i10886 = (() => {
                              {
                                const $t15617_i10141_i10411_i10710_i10885 = bits_i10139_i10409_i10708_i10883;
                                return ($t15617_i10141_i10411_i10710_i10885 / 4.50359962737e+15);
                              }
                            })();
                            return { _0: $t15618_i10142_i10412_i10711_i10886, _1: rng2_i10140_i10410_i10709_i10884 };
                          }
                        }
                      }
                    }
                  })();
                  {
                    const t_i10414_i10713_i10888 = $p29061_i10413_i10712_i10887._0;
                    {
                      const rng2_i10415_i10714_i10889 = $p29061_i10413_i10712_i10887._1;
                      {
                        const out_i10416_i10715_i10890 = { _0: rng2_i10415_i10714_i10889, _1: t_i10414_i10713_i10888 };
                        return out_i10416_i10715_i10890;
                      }
                    }
                  }
                }
              }
            })();
            {
              const r1 = $p27435._0;
              {
                const side_f = $p27435._1;
                {
                  const $p27434 = (() => {
                    {
                      const $p29061_i10413_i10712_i10868 = (() => {
                        {
                          const $p15619_i10138_i10408_i10707_i10863 = (() => {
                            {
                              const $p15616_i1544_i10128_i10399_i10698_i10854 = Random$next_raw(r1);
                              {
                                const hi_i1545_i10129_i10400_i10699_i10855 = $p15616_i1544_i10128_i10399_i10698_i10854._0;
                                {
                                  const rng2_i1546_i10130_i10401_i10700_i10856 = $p15616_i1544_i10128_i10399_i10698_i10854._1;
                                  {
                                    const $p15615_i1547_i10131_i10402_i10701_i10857 = Random$next_raw(rng2_i1546_i10130_i10401_i10700_i10856);
                                    {
                                      const lo_i1548_i10132_i10403_i10702_i10858 = $p15615_i1547_i10131_i10402_i10701_i10857._0;
                                      {
                                        const rng3_i1549_i10133_i10404_i10703_i10859 = $p15615_i1547_i10131_i10402_i10701_i10857._1;
                                        {
                                          const $t15614_i1553_i10137_i10407_i10706_i10862 = (() => {
                                            {
                                              const $t15613_i1552_i10136_i10406_i10705_i10861 = (() => {
                                                {
                                                  const $t15611_i1550_i10134_i10405_i10704_i10860 = march_int_and(hi_i1545_i10129_i10400_i10699_i10855, 1048575);
                                                  return ($t15611_i1550_i10134_i10405_i10704_i10860 * 4294967296);
                                                }
                                              })();
                                              return ($t15613_i1552_i10136_i10406_i10705_i10861 + lo_i1548_i10132_i10403_i10702_i10858);
                                            }
                                          })();
                                          return { _0: $t15614_i1553_i10137_i10407_i10706_i10862, _1: rng3_i1549_i10133_i10404_i10703_i10859 };
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          })();
                          {
                            const bits_i10139_i10409_i10708_i10864 = $p15619_i10138_i10408_i10707_i10863._0;
                            {
                              const rng2_i10140_i10410_i10709_i10865 = $p15619_i10138_i10408_i10707_i10863._1;
                              {
                                const $t15618_i10142_i10412_i10711_i10867 = (() => {
                                  {
                                    const $t15617_i10141_i10411_i10710_i10866 = bits_i10139_i10409_i10708_i10864;
                                    return ($t15617_i10141_i10411_i10710_i10866 / 4.50359962737e+15);
                                  }
                                })();
                                return { _0: $t15618_i10142_i10412_i10711_i10867, _1: rng2_i10140_i10410_i10709_i10865 };
                              }
                            }
                          }
                        }
                      })();
                      {
                        const t_i10414_i10713_i10869 = $p29061_i10413_i10712_i10868._0;
                        {
                          const rng2_i10415_i10714_i10870 = $p29061_i10413_i10712_i10868._1;
                          {
                            const out_i10416_i10715_i10871 = { _0: rng2_i10415_i10714_i10870, _1: t_i10414_i10713_i10869 };
                            return out_i10416_i10715_i10871;
                          }
                        }
                      }
                    }
                  })();
                  {
                    const r2 = $p27434._0;
                    {
                      const y_f = $p27434._1;
                      {
                        const $p27433 = (() => {
                          {
                            const $p29061_i10413_i10712_i10849 = (() => {
                              {
                                const $p15619_i10138_i10408_i10707_i10844 = (() => {
                                  {
                                    const $p15616_i1544_i10128_i10399_i10698_i10835 = Random$next_raw(r2);
                                    {
                                      const hi_i1545_i10129_i10400_i10699_i10836 = $p15616_i1544_i10128_i10399_i10698_i10835._0;
                                      {
                                        const rng2_i1546_i10130_i10401_i10700_i10837 = $p15616_i1544_i10128_i10399_i10698_i10835._1;
                                        {
                                          const $p15615_i1547_i10131_i10402_i10701_i10838 = Random$next_raw(rng2_i1546_i10130_i10401_i10700_i10837);
                                          {
                                            const lo_i1548_i10132_i10403_i10702_i10839 = $p15615_i1547_i10131_i10402_i10701_i10838._0;
                                            {
                                              const rng3_i1549_i10133_i10404_i10703_i10840 = $p15615_i1547_i10131_i10402_i10701_i10838._1;
                                              {
                                                const $t15614_i1553_i10137_i10407_i10706_i10843 = (() => {
                                                  {
                                                    const $t15613_i1552_i10136_i10406_i10705_i10842 = (() => {
                                                      {
                                                        const $t15611_i1550_i10134_i10405_i10704_i10841 = march_int_and(hi_i1545_i10129_i10400_i10699_i10836, 1048575);
                                                        return ($t15611_i1550_i10134_i10405_i10704_i10841 * 4294967296);
                                                      }
                                                    })();
                                                    return ($t15613_i1552_i10136_i10406_i10705_i10842 + lo_i1548_i10132_i10403_i10702_i10839);
                                                  }
                                                })();
                                                return { _0: $t15614_i1553_i10137_i10407_i10706_i10843, _1: rng3_i1549_i10133_i10404_i10703_i10840 };
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                })();
                                {
                                  const bits_i10139_i10409_i10708_i10845 = $p15619_i10138_i10408_i10707_i10844._0;
                                  {
                                    const rng2_i10140_i10410_i10709_i10846 = $p15619_i10138_i10408_i10707_i10844._1;
                                    {
                                      const $t15618_i10142_i10412_i10711_i10848 = (() => {
                                        {
                                          const $t15617_i10141_i10411_i10710_i10847 = bits_i10139_i10409_i10708_i10845;
                                          return ($t15617_i10141_i10411_i10710_i10847 / 4.50359962737e+15);
                                        }
                                      })();
                                      return { _0: $t15618_i10142_i10412_i10711_i10848, _1: rng2_i10140_i10410_i10709_i10846 };
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const t_i10414_i10713_i10850 = $p29061_i10413_i10712_i10849._0;
                              {
                                const rng2_i10415_i10714_i10851 = $p29061_i10413_i10712_i10849._1;
                                {
                                  const out_i10416_i10715_i10852 = { _0: rng2_i10415_i10714_i10851, _1: t_i10414_i10713_i10850 };
                                  return out_i10416_i10715_i10852;
                                }
                              }
                            }
                          }
                        })();
                        {
                          const r3 = $p27433._0;
                          {
                            const ang_f = $p27433._1;
                            {
                              const $p27432 = (() => {
                                {
                                  const $p29061_i10413_i10712_i10830 = (() => {
                                    {
                                      const $p15619_i10138_i10408_i10707_i10825 = (() => {
                                        {
                                          const $p15616_i1544_i10128_i10399_i10698_i10816 = Random$next_raw(r3);
                                          {
                                            const hi_i1545_i10129_i10400_i10699_i10817 = $p15616_i1544_i10128_i10399_i10698_i10816._0;
                                            {
                                              const rng2_i1546_i10130_i10401_i10700_i10818 = $p15616_i1544_i10128_i10399_i10698_i10816._1;
                                              {
                                                const $p15615_i1547_i10131_i10402_i10701_i10819 = Random$next_raw(rng2_i1546_i10130_i10401_i10700_i10818);
                                                {
                                                  const lo_i1548_i10132_i10403_i10702_i10820 = $p15615_i1547_i10131_i10402_i10701_i10819._0;
                                                  {
                                                    const rng3_i1549_i10133_i10404_i10703_i10821 = $p15615_i1547_i10131_i10402_i10701_i10819._1;
                                                    {
                                                      const $t15614_i1553_i10137_i10407_i10706_i10824 = (() => {
                                                        {
                                                          const $t15613_i1552_i10136_i10406_i10705_i10823 = (() => {
                                                            {
                                                              const $t15611_i1550_i10134_i10405_i10704_i10822 = march_int_and(hi_i1545_i10129_i10400_i10699_i10817, 1048575);
                                                              return ($t15611_i1550_i10134_i10405_i10704_i10822 * 4294967296);
                                                            }
                                                          })();
                                                          return ($t15613_i1552_i10136_i10406_i10705_i10823 + lo_i1548_i10132_i10403_i10702_i10820);
                                                        }
                                                      })();
                                                      return { _0: $t15614_i1553_i10137_i10407_i10706_i10824, _1: rng3_i1549_i10133_i10404_i10703_i10821 };
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      })();
                                      {
                                        const bits_i10139_i10409_i10708_i10826 = $p15619_i10138_i10408_i10707_i10825._0;
                                        {
                                          const rng2_i10140_i10410_i10709_i10827 = $p15619_i10138_i10408_i10707_i10825._1;
                                          {
                                            const $t15618_i10142_i10412_i10711_i10829 = (() => {
                                              {
                                                const $t15617_i10141_i10411_i10710_i10828 = bits_i10139_i10409_i10708_i10826;
                                                return ($t15617_i10141_i10411_i10710_i10828 / 4.50359962737e+15);
                                              }
                                            })();
                                            return { _0: $t15618_i10142_i10412_i10711_i10829, _1: rng2_i10140_i10410_i10709_i10827 };
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const t_i10414_i10713_i10831 = $p29061_i10413_i10712_i10830._0;
                                    {
                                      const rng2_i10415_i10714_i10832 = $p29061_i10413_i10712_i10830._1;
                                      {
                                        const out_i10416_i10715_i10833 = { _0: rng2_i10415_i10714_i10832, _1: t_i10414_i10713_i10831 };
                                        return out_i10416_i10715_i10833;
                                      }
                                    }
                                  }
                                }
                              })();
                              {
                                const r4 = $p27432._0;
                                {
                                  const next_f = $p27432._1;
                                  {
                                    const $p27431 = (() => {
                                      {
                                        const $p29061_i10413_i10712_i10811 = (() => {
                                          {
                                            const $p15619_i10138_i10408_i10707_i10806 = (() => {
                                              {
                                                const $p15616_i1544_i10128_i10399_i10698_i10797 = Random$next_raw(r4);
                                                {
                                                  const hi_i1545_i10129_i10400_i10699_i10798 = $p15616_i1544_i10128_i10399_i10698_i10797._0;
                                                  {
                                                    const rng2_i1546_i10130_i10401_i10700_i10799 = $p15616_i1544_i10128_i10399_i10698_i10797._1;
                                                    {
                                                      const $p15615_i1547_i10131_i10402_i10701_i10800 = Random$next_raw(rng2_i1546_i10130_i10401_i10700_i10799);
                                                      {
                                                        const lo_i1548_i10132_i10403_i10702_i10801 = $p15615_i1547_i10131_i10402_i10701_i10800._0;
                                                        {
                                                          const rng3_i1549_i10133_i10404_i10703_i10802 = $p15615_i1547_i10131_i10402_i10701_i10800._1;
                                                          {
                                                            const $t15614_i1553_i10137_i10407_i10706_i10805 = (() => {
                                                              {
                                                                const $t15613_i1552_i10136_i10406_i10705_i10804 = (() => {
                                                                  {
                                                                    const $t15611_i1550_i10134_i10405_i10704_i10803 = march_int_and(hi_i1545_i10129_i10400_i10699_i10798, 1048575);
                                                                    return ($t15611_i1550_i10134_i10405_i10704_i10803 * 4294967296);
                                                                  }
                                                                })();
                                                                return ($t15613_i1552_i10136_i10406_i10705_i10804 + lo_i1548_i10132_i10403_i10702_i10801);
                                                              }
                                                            })();
                                                            return { _0: $t15614_i1553_i10137_i10407_i10706_i10805, _1: rng3_i1549_i10133_i10404_i10703_i10802 };
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            })();
                                            {
                                              const bits_i10139_i10409_i10708_i10807 = $p15619_i10138_i10408_i10707_i10806._0;
                                              {
                                                const rng2_i10140_i10410_i10709_i10808 = $p15619_i10138_i10408_i10707_i10806._1;
                                                {
                                                  const $t15618_i10142_i10412_i10711_i10810 = (() => {
                                                    {
                                                      const $t15617_i10141_i10411_i10710_i10809 = bits_i10139_i10409_i10708_i10807;
                                                      return ($t15617_i10141_i10411_i10710_i10809 / 4.50359962737e+15);
                                                    }
                                                  })();
                                                  return { _0: $t15618_i10142_i10412_i10711_i10810, _1: rng2_i10140_i10410_i10709_i10808 };
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        {
                                          const t_i10414_i10713_i10812 = $p29061_i10413_i10712_i10811._0;
                                          {
                                            const rng2_i10415_i10714_i10813 = $p29061_i10413_i10712_i10811._1;
                                            {
                                              const out_i10416_i10715_i10814 = { _0: rng2_i10415_i10714_i10813, _1: t_i10414_i10713_i10812 };
                                              return out_i10416_i10715_i10814;
                                            }
                                          }
                                        }
                                      }
                                    })();
                                    {
                                      const r5 = $p27431._0;
                                      {
                                        const shape_f = $p27431._1;
                                        {
                                          const from_left = (side_f < 0.5);
                                          {
                                            let x;
                                            if (from_left === true) {
                                              x = (0. - 20.);
                                            } else {
                                              x = (() => {
                                                {
                                                  const $t27411 = game.view_w;
                                                  return ($t27411 + 20.);
                                                }
                                              })();
                                            }
                                            {
                                              const y = (() => {
                                                {
                                                  const $t27412 = game.camera_y;
                                                  {
                                                    const $t27414 = (() => {
                                                      {
                                                        const $t27413 = game.view_h;
                                                        return (y_f * $t27413);
                                                      }
                                                    })();
                                                    return ($t27412 + $t27414);
                                                  }
                                                }
                                              })();
                                              {
                                                const jitter = (() => {
                                                  {
                                                    const $t27415 = (ang_f - 0.5);
                                                    return ($t27415 * 1.0472);
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
                                                        const $t27417 = (dir_x * 90.);
                                                        {
                                                          const $t27418 = Math.cos(jitter);
                                                          return ($t27417 * $t27418);
                                                        }
                                                      }
                                                    })();
                                                    {
                                                      const vy = (() => {
                                                        {
                                                          const $t27420 = Math.sin(jitter);
                                                          return (90. * $t27420);
                                                        }
                                                      })();
                                                      {
                                                        const a = (() => {
                                                          {
                                                            const $t27422 = { $: "AsteroidDrifting" };
                                                            return ({ x: x, y: y, vx: vx, vy: vy, radius: 10., shape_seed: shape_f, mode: $t27422 });
                                                          }
                                                        })();
                                                        {
                                                          const $t27423 = game.asteroids;
                                                          {
                                                            const $t27424 = (() => {
                                                              return { $: "Cons", _0: a, _1: $t27423 };
                                                            })();
                                                            {
                                                              const $t27430 = (() => {
                                                                {
                                                                  const $t27429 = (() => {
                                                                    {
                                                                      const $t27427 = (() => {
                                                                        {
                                                                          const $t27426 = (next_f - 0.5);
                                                                          return ($t27426 * 2.);
                                                                        }
                                                                      })();
                                                                      return ($t27427 * 1.);
                                                                    }
                                                                  })();
                                                                  return (4. + $t27429);
                                                                }
                                                              })();
                                                              return ({ ...game, asteroids: $t27424, rng: r5, spawn_timer: $t27430 });
                                                            }
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
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
    const $t27447 = (() => {
      {
        const $t27444 = (() => {
          {
            const $t27438 = (() => {
              {
                const $t27437 = (() => {
                  {
                    const $t27436 = game.camera_y;
                    return ($t27436 - 100.);
                  }
                })();
                return (y > $t27437);
              }
            })();
            {
              const $t27443 = (() => {
                {
                  const $t27442 = (() => {
                    {
                      const $t27441 = (() => {
                        {
                          const $t27439 = game.camera_y;
                          {
                            const $t27440 = game.view_h;
                            return ($t27439 + $t27440);
                          }
                        }
                      })();
                      return ($t27441 + 100.);
                    }
                  })();
                  return (y < $t27442);
                }
              })();
              return ($t27438 && $t27443);
            }
          }
        })();
        {
          const $t27446 = (() => {
            {
              const $t27445 = (0. - 100.);
              return (x > $t27445);
            }
          })();
          return ($t27444 && $t27446);
        }
      }
    })();
    {
      const $t27450 = (() => {
        {
          const $t27449 = (() => {
            {
              const $t27448 = game.view_w;
              return ($t27448 + 100.);
            }
          })();
          return (x < $t27449);
        }
      })();
      return ($t27447 && $t27450);
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
      const $f27460 = asteroids._0;
      const $f27461 = asteroids._1;
      {
        const rest = (() => {
          return $f27461;
        })();
        {
          const a = (() => {
            return $f27460;
          })();
          {
            const dx = (() => {
              {
                const $t27451 = a.x;
                return ($t27451 - x);
              }
            })();
            {
              const dy = (() => {
                {
                  const $t27452 = a.y;
                  return ($t27452 - y);
                }
              })();
              {
                const d2 = (() => {
                  {
                    const $t27453 = (dx * dx);
                    {
                      const $t27454 = (dy * dy);
                      return ($t27453 + $t27454);
                    }
                  }
                })();
                {
                  const $t27455 = (d2 < best_d2);
                  if ($t27455 === true) {
                    return (() => {
                      {
                        const $t27459 = (() => {
                          {
                            const $t27456 = a.x;
                            {
                              const $t27457 = a.y;
                              {
                                const $t27458 = { _0: $t27456, _1: $t27457 };
                                return { $: "Some", _0: $t27458 };
                              }
                            }
                          }
                        })();
                        return Perihelion$Combat$nearest_in_list_ast(x, y, rest, d2, $t27459);
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
      const $f27472 = ships._0;
      const $f27473 = ships._1;
      {
        const rest = (() => {
          return $f27473;
        })();
        {
          const sh = (() => {
            return $f27472;
          })();
          {
            const pos = (() => {
              {
                const pos_i3656 = (() => {
                  {
                    const $t27400_i3654 = sh.x;
                    {
                      const $t27401_i3655 = sh.y;
                      return { _0: $t27400_i3654, _1: $t27401_i3655 };
                    }
                  }
                })();
                return pos_i3656;
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
                          const $t27466 = (dx * dx);
                          {
                            const $t27467 = (dy * dy);
                            return ($t27466 + $t27467);
                          }
                        }
                      })();
                      {
                        const $t27468 = (d2 < best_d2);
                        if ($t27468 === true) {
                          return (() => {
                            {
                              const $t27470 = (() => {
                                {
                                  const $t27469 = { _0: sx, _1: sy };
                                  return { $: "Some", _0: $t27469 };
                                }
                              })();
                              return Perihelion$Combat$nearest_in_list_ship(x, y, rest, d2, $t27470);
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
    const $p27492 = (() => {
      {
        const $t27480 = (220. * 220.);
        {
          const $t27481 = { $: "None" };
          return Perihelion$Combat$nearest_in_list_ast(x, y, asteroids, $t27480, $t27481);
        }
      }
    })();
    {
      const d2a = $p27492._0;
      {
        const besta = $p27492._1;
        {
          const $p27491 = (() => {
            return Perihelion$Combat$nearest_in_list_ship(x, y, ships, d2a, besta);
          })();
          {
            const bests = $p27491._1;
            switch (bests.$) {
              case "None": {
                return { $: "None" };
                break;
              }
              case "Some": {
                const $f27490 = bests._0;
                {
                  const pair = (() => {
                    return $f27490;
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
                                const $t27484 = (() => {
                                  {
                                    const $t27482 = (dx * dx);
                                    {
                                      const $t27483 = (dy * dy);
                                      return ($t27482 + $t27483);
                                    }
                                  }
                                })();
                                return Math.sqrt($t27484);
                              }
                            })();
                            {
                              const $t27485 = (d > 0.);
                              if ($t27485 === true) {
                                return (() => {
                                  {
                                    const $t27486 = (dx / d);
                                    {
                                      const $t27487 = (dy / d);
                                      {
                                        const $t27488 = { _0: $t27486, _1: $t27487 };
                                        return { $: "Some", _0: $t27488 };
                                      }
                                    }
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
        const $t27496 = (() => {
          {
            const $t27493 = s.x;
            {
              const $t27495 = (() => {
                {
                  const $t27494 = s.vx;
                  return ($t27494 * dt_s);
                }
              })();
              return ($t27493 + $t27495);
            }
          }
        })();
        {
          const $t27500 = (() => {
            {
              const $t27497 = s.y;
              {
                const $t27499 = (() => {
                  {
                    const $t27498 = s.vy;
                    return ($t27498 * dt_s);
                  }
                })();
                return ($t27497 + $t27499);
              }
            }
          })();
          {
            const $t27502 = (() => {
              {
                const $t27501 = s.ttl;
                return ($t27501 - dt_s);
              }
            })();
            return ({ ...s, x: $t27496, y: $t27500, ttl: $t27502 });
          }
        }
      }
    })();
    {
      const $t27504 = (() => {
        {
          const $t27503 = s.homing;
          return (!$t27503);
        }
      })();
      if ($t27504 === true) {
        return moved;
      } else {
        return (() => {
          {
            const $t27507 = (() => {
              {
                const $t27505 = s.x;
                {
                  const $t27506 = s.y;
                  return Perihelion$Combat$nearest_hazard_dir($t27505, $t27506, asteroids, ships);
                }
              }
            })();
            switch ($t27507.$) {
              case "None": {
                return moved;
                break;
              }
              case "Some": {
                const $f27533 = $t27507._0;
                {
                  const pair = $f27533;
                  {
                    const tx = pair._0;
                    {
                      const ty = pair._1;
                      {
                        const speed = (() => {
                          {
                            const $t27514 = (() => {
                              {
                                const $t27510 = (() => {
                                  {
                                    const $t27508 = s.vx;
                                    {
                                      const $t27509 = s.vx;
                                      return ($t27508 * $t27509);
                                    }
                                  }
                                })();
                                {
                                  const $t27513 = (() => {
                                    {
                                      const $t27511 = s.vy;
                                      {
                                        const $t27512 = s.vy;
                                        return ($t27511 * $t27512);
                                      }
                                    }
                                  })();
                                  return ($t27510 + $t27513);
                                }
                              }
                            })();
                            return Math.sqrt($t27514);
                          }
                        })();
                        {
                          const cur_ax = (() => {
                            {
                              const $t27515 = s.vx;
                              return ($t27515 / speed);
                            }
                          })();
                          {
                            const cur_ay = (() => {
                              {
                                const $t27516 = s.vy;
                                return ($t27516 / speed);
                              }
                            })();
                            {
                              const turned_ax = (() => {
                                {
                                  const $t27520 = (() => {
                                    {
                                      const $t27519 = (() => {
                                        {
                                          const $t27517 = (tx - cur_ax);
                                          return ($t27517 * 3.);
                                        }
                                      })();
                                      return ($t27519 * dt_s);
                                    }
                                  })();
                                  return (cur_ax + $t27520);
                                }
                              })();
                              {
                                const turned_ay = (() => {
                                  {
                                    const $t27524 = (() => {
                                      {
                                        const $t27523 = (() => {
                                          {
                                            const $t27521 = (ty - cur_ay);
                                            return ($t27521 * 3.);
                                          }
                                        })();
                                        return ($t27523 * dt_s);
                                      }
                                    })();
                                    return (cur_ay + $t27524);
                                  }
                                })();
                                {
                                  const norm = (() => {
                                    {
                                      const $t27527 = (() => {
                                        {
                                          const $t27525 = (turned_ax * turned_ax);
                                          {
                                            const $t27526 = (turned_ay * turned_ay);
                                            return ($t27525 + $t27526);
                                          }
                                        }
                                      })();
                                      return Math.sqrt($t27527);
                                    }
                                  })();
                                  {
                                    const $t27529 = (() => {
                                      {
                                        const $t27528 = (turned_ax / norm);
                                        return ($t27528 * speed);
                                      }
                                    })();
                                    {
                                      const $t27531 = (() => {
                                        {
                                          const $t27530 = (turned_ay / norm);
                                          return ($t27530 * speed);
                                        }
                                      })();
                                      return ({ ...moved, vx: $t27529, vy: $t27531 });
                                    }
                                  }
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
      const $t27534 = g1.player_shots;
      {
        const $t27538 = { $: "$Clo_$lam27535$3687", _0: $lam27535$apply$3687, _1: dt_s, _2: g1 };
        {
          const $t27539 = (() => {
            {
              const f_i3683 = $t27538;
              {
                const go_i3684 = { $: "$Clo_go$4762", _0: go$apply$4762, _1: f_i3683 };
                {
                  const $t310_i3685 = { $: "Nil" };
                  return go$apply$4762(go_i3684, $t27534, $t310_i3685);
                }
              }
            }
          })();
          {
            const $t27546 = { $: "$Clo_$lam27540$3688", _0: $lam27540$apply$3688, _1: g1 };
            {
              const p_shots = (() => {
                {
                  const pred_i3679 = $t27546;
                  {
                    const go_i3680 = { $: "$Clo_go$4760", _0: go$apply$4760, _1: pred_i3679 };
                    {
                      const $t342_i3681 = { $: "Nil" };
                      return go$apply$4760(go_i3680, $t27539, $t342_i3681);
                    }
                  }
                }
              })();
              {
                const $t27547 = g1.enemy_shots;
                {
                  const $t27551 = { $: "$Clo_$lam27548$3689", _0: $lam27548$apply$3689, _1: dt_s, _2: g1 };
                  {
                    const $t27552 = (() => {
                      {
                        const f_i3675 = $t27551;
                        {
                          const go_i3676 = { $: "$Clo_go$4762", _0: go$apply$4762, _1: f_i3675 };
                          {
                            const $t310_i3677 = { $: "Nil" };
                            return go$apply$4762(go_i3676, $t27547, $t310_i3677);
                          }
                        }
                      }
                    })();
                    {
                      const $t27559 = { $: "$Clo_$lam27553$3690", _0: $lam27553$apply$3690, _1: g1 };
                      {
                        const e_shots = (() => {
                          {
                            const pred_i3671 = $t27559;
                            {
                              const go_i3672 = { $: "$Clo_go$4760", _0: go$apply$4760, _1: pred_i3671 };
                              {
                                const $t342_i3673 = { $: "Nil" };
                                return go$apply$4760(go_i3672, $t27552, $t342_i3673);
                              }
                            }
                          }
                        })();
                        {
                          const $t27560 = g1.pickups;
                          {
                            const $t27564 = { $: "$Clo_$lam27561$3691", _0: $lam27561$apply$3691, _1: dt_s };
                            {
                              const $t27565 = (() => {
                                {
                                  const f_i3667 = $t27564;
                                  {
                                    const go_i3668 = { $: "$Clo_go$4758", _0: go$apply$4758, _1: f_i3667 };
                                    {
                                      const $t310_i3669 = { $: "Nil" };
                                      return go$apply$4758(go_i3668, $t27560, $t310_i3669);
                                    }
                                  }
                                }
                              })();
                              {
                                const $t27568 = { $: "$Clo_$lam27566$3692", _0: $lam27566$apply$3692 };
                                {
                                  const pickups = (() => {
                                    {
                                      const pred_i3663 = $t27568;
                                      {
                                        const go_i3664 = { $: "$Clo_go$4756", _0: go$apply$4756, _1: pred_i3663 };
                                        {
                                          const $t342_i3665 = { $: "Nil" };
                                          return go$apply$4756(go_i3664, $t27565, $t342_i3665);
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t27572 = (() => {
                                      {
                                        const $t27570 = (() => {
                                          {
                                            const $t27569 = g1.fire_cooldown;
                                            return ($t27569 > 0.);
                                          }
                                        })();
                                        if ($t27570 === true) {
                                          return (() => {
                                            {
                                              const $t27571 = g1.fire_cooldown;
                                              return ($t27571 - dt_s);
                                            }
                                          })();
                                        } else {
                                          return 0.;
                                        }
                                      }
                                    })();
                                    {
                                      const $t27576 = (() => {
                                        {
                                          const $t27574 = (() => {
                                            {
                                              const $t27573 = g1.starkiller_cooldown;
                                              return ($t27573 > 0.);
                                            }
                                          })();
                                          if ($t27574 === true) {
                                            return (() => {
                                              {
                                                const $t27575 = g1.starkiller_cooldown;
                                                return ($t27575 - dt_s);
                                              }
                                            })();
                                          } else {
                                            return 0.;
                                          }
                                        }
                                      })();
                                      return ({ ...g1, player_shots: p_shots, enemy_shots: e_shots, pickups: pickups, fire_cooldown: $t27572, starkiller_cooldown: $t27576 });
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
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
      const $f27583 = stars._0;
      const $f27584 = stars._1;
      {
        const rest = $f27584;
        {
          const s = $f27583;
          {
            const dx = (() => {
              {
                const $t27577 = s.x;
                return ($t27577 - x);
              }
            })();
            {
              const dy = (() => {
                {
                  const $t27578 = s.y;
                  return ($t27578 - y);
                }
              })();
              {
                const d = (() => {
                  {
                    const $t27579 = (dx * dx);
                    {
                      const $t27580 = (dy * dy);
                      return ($t27579 + $t27580);
                    }
                  }
                })();
                {
                  const $t27581 = (d < best_d);
                  if ($t27581 === true) {
                    return (() => {
                      {
                        const $t27582 = { $: "Some", _0: s };
                        return Perihelion$Combat$nearest_star_for_asteroid(x, y, rest, $t27582, d);
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
    const $t27591 = (() => {
      {
        const $t27589 = { $: "None" };
        {
          const $t27590 = (240. * 240.);
          return Perihelion$Combat$nearest_star_for_asteroid(x, y, stars, $t27589, $t27590);
        }
      }
    })();
    switch ($t27591.$) {
      case "None": {
        {
          const out = { _0: vx, _1: vy };
          return out;
        }
        break;
      }
      case "Some": {
        const $f27617 = $t27591._0;
        {
          const s = $f27617;
          {
            const dx = (() => {
              {
                const $t27592 = s.x;
                return ($t27592 - x);
              }
            })();
            {
              const dy = (() => {
                {
                  const $t27593 = s.y;
                  return ($t27593 - y);
                }
              })();
              {
                const dist = (() => {
                  {
                    const $t27596 = (() => {
                      {
                        const $t27594 = (dx * dx);
                        {
                          const $t27595 = (dy * dy);
                          return ($t27594 + $t27595);
                        }
                      }
                    })();
                    return Math.sqrt($t27596);
                  }
                })();
                {
                  const $t27597 = (dist > 0.);
                  if ($t27597 === true) {
                    return (() => {
                      {
                        const speed = (() => {
                          {
                            const $t27600 = (() => {
                              {
                                const $t27598 = (vx * vx);
                                {
                                  const $t27599 = (vy * vy);
                                  return ($t27598 + $t27599);
                                }
                              }
                            })();
                            return Math.sqrt($t27600);
                          }
                        })();
                        {
                          const nvx = (() => {
                            {
                              const $t27604 = (() => {
                                {
                                  const $t27603 = (() => {
                                    {
                                      const $t27601 = (dx / dist);
                                      return ($t27601 * 500.);
                                    }
                                  })();
                                  return ($t27603 * dt_s);
                                }
                              })();
                              return (vx + $t27604);
                            }
                          })();
                          {
                            const nvy = (() => {
                              {
                                const $t27608 = (() => {
                                  {
                                    const $t27607 = (() => {
                                      {
                                        const $t27605 = (dy / dist);
                                        return ($t27605 * 500.);
                                      }
                                    })();
                                    return ($t27607 * dt_s);
                                  }
                                })();
                                return (vy + $t27608);
                              }
                            })();
                            {
                              const nspeed = (() => {
                                {
                                  const $t27611 = (() => {
                                    {
                                      const $t27609 = (nvx * nvx);
                                      {
                                        const $t27610 = (nvy * nvy);
                                        return ($t27609 + $t27610);
                                      }
                                    }
                                  })();
                                  return Math.sqrt($t27611);
                                }
                              })();
                              {
                                const $t27612 = (nspeed > 0.);
                                if ($t27612 === true) {
                                  return (() => {
                                    {
                                      const $t27614 = (() => {
                                        {
                                          const $t27613 = (nvx / nspeed);
                                          return ($t27613 * speed);
                                        }
                                      })();
                                      {
                                        const $t27616 = (() => {
                                          {
                                            const $t27615 = (nvy / nspeed);
                                            return ($t27615 * speed);
                                          }
                                        })();
                                        return { _0: $t27614, _1: $t27616 };
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
        const $t27618 = (() => {
          {
            const go_i3693 = { $: "$Clo_go$4764", _0: go$apply$4764 };
            {
              const $t293_i3694 = { $: "Nil" };
              return go$apply$4764(go_i3693, acc, $t293_i3694);
            }
          }
        })();
        return ({ ...game, asteroids: $t27618 });
      }
      break;
    }
    case "Cons": {
      const $f27682 = asteroids._0;
      const $f27683 = asteroids._1;
      {
        const rest = $f27683;
        {
          const a = $f27682;
          {
            const $t27619 = a.mode;
            switch ($t27619.$) {
              case "AsteroidOrbiting": {
                const $f27676 = $t27619._0;
                const $f27677 = $t27619._1;
                {
                  const angle = (() => {
                    return $f27677;
                  })();
                  {
                    const idx = (() => {
                      return $f27676;
                    })();
                    {
                      const $t27620 = Perihelion$Core$star_at(game, idx);
                      switch ($t27620.$) {
                        case "None": {
                          return Perihelion$Combat$step_asteroids_go(game, rest, acc, dt_s);
                          break;
                        }
                        case "Some": {
                          const $f27635 = $t27620._0;
                          {
                            const s = $f27635;
                            {
                              const angle2 = (() => {
                                {
                                  const $t27622 = (1. * dt_s);
                                  return (angle + $t27622);
                                }
                              })();
                              {
                                const r = (() => {
                                  {
                                    const $t27623 = s.capture_radius;
                                    return ($t27623 * 0.8);
                                  }
                                })();
                                {
                                  const a2 = (() => {
                                    {
                                      const $t27628 = (() => {
                                        {
                                          const $t27625 = s.x;
                                          {
                                            const $t27627 = (() => {
                                              {
                                                const $t27626 = Math.cos(angle2);
                                                return ($t27626 * r);
                                              }
                                            })();
                                            return ($t27625 + $t27627);
                                          }
                                        }
                                      })();
                                      {
                                        const $t27632 = (() => {
                                          {
                                            const $t27629 = s.y;
                                            {
                                              const $t27631 = (() => {
                                                {
                                                  const $t27630 = Math.sin(angle2);
                                                  return ($t27630 * r);
                                                }
                                              })();
                                              return ($t27629 + $t27631);
                                            }
                                          }
                                        })();
                                        {
                                          const $t27633 = { $: "AsteroidOrbiting", _0: idx, _1: angle2 };
                                          return ({ ...a, x: $t27628, y: $t27632, mode: $t27633 });
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t27634 = { $: "Cons", _0: a2, _1: acc };
                                    return Perihelion$Combat$step_asteroids_go(game, rest, $t27634, dt_s);
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
                      const $t27636 = a.x;
                      {
                        const $t27637 = a.y;
                        {
                          const $t27638 = a.vx;
                          {
                            const $t27639 = a.vy;
                            {
                              const $t27640 = game.stars;
                              return Perihelion$Combat$arc_velocity($t27636, $t27637, $t27638, $t27639, $t27640, dt_s);
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
                            const $t27641 = a.x;
                            {
                              const $t27642 = (vx2 * dt_s);
                              return ($t27641 + $t27642);
                            }
                          }
                        })();
                        {
                          const y2 = (() => {
                            {
                              const $t27643 = a.y;
                              {
                                const $t27644 = (vy2 * dt_s);
                                return ($t27643 + $t27644);
                              }
                            }
                          })();
                          {
                            const $t27646 = (() => {
                              {
                                const $t27645 = Perihelion$Combat$in_band(game, x2, y2);
                                return (!$t27645);
                              }
                            })();
                            if ($t27646 === true) {
                              return Perihelion$Combat$step_asteroids_go(game, rest, acc, dt_s);
                            } else {
                              return (() => {
                                {
                                  const $t27648 = (() => {
                                    {
                                      const $t27647 = game.stars;
                                      return Perihelion$Combat$arrived_star($t27647, x2, y2, 0);
                                    }
                                  })();
                                  switch ($t27648.$) {
                                    case "None": {
                                      {
                                        const a2 = ({ ...a, x: x2, y: y2, vx: vx2, vy: vy2 });
                                        {
                                          const $t27649 = { $: "Cons", _0: a2, _1: acc };
                                          return Perihelion$Combat$step_asteroids_go(game, rest, $t27649, dt_s);
                                        }
                                      }
                                      break;
                                    }
                                    case "Some": {
                                      const $f27674 = $t27648._0;
                                      {
                                        const pair = $f27674;
                                        {
                                          const idx = pair._0;
                                          {
                                            const s = pair._1;
                                            {
                                              const $p27672 = (() => {
                                                {
                                                  const $t27650 = game.rng;
                                                  {
                                                    const $p29061_i10413_i10712_i10906 = (() => {
                                                      {
                                                        const $p15619_i10138_i10408_i10707_i10901 = (() => {
                                                          {
                                                            const $p15616_i1544_i10128_i10399_i10698_i10892 = Random$next_raw($t27650);
                                                            {
                                                              const hi_i1545_i10129_i10400_i10699_i10893 = $p15616_i1544_i10128_i10399_i10698_i10892._0;
                                                              {
                                                                const rng2_i1546_i10130_i10401_i10700_i10894 = $p15616_i1544_i10128_i10399_i10698_i10892._1;
                                                                {
                                                                  const $p15615_i1547_i10131_i10402_i10701_i10895 = Random$next_raw(rng2_i1546_i10130_i10401_i10700_i10894);
                                                                  {
                                                                    const lo_i1548_i10132_i10403_i10702_i10896 = $p15615_i1547_i10131_i10402_i10701_i10895._0;
                                                                    {
                                                                      const rng3_i1549_i10133_i10404_i10703_i10897 = $p15615_i1547_i10131_i10402_i10701_i10895._1;
                                                                      {
                                                                        const $t15614_i1553_i10137_i10407_i10706_i10900 = (() => {
                                                                          {
                                                                            const $t15613_i1552_i10136_i10406_i10705_i10899 = (() => {
                                                                              {
                                                                                const $t15611_i1550_i10134_i10405_i10704_i10898 = march_int_and(hi_i1545_i10129_i10400_i10699_i10893, 1048575);
                                                                                return ($t15611_i1550_i10134_i10405_i10704_i10898 * 4294967296);
                                                                              }
                                                                            })();
                                                                            return ($t15613_i1552_i10136_i10406_i10705_i10899 + lo_i1548_i10132_i10403_i10702_i10896);
                                                                          }
                                                                        })();
                                                                        return { _0: $t15614_i1553_i10137_i10407_i10706_i10900, _1: rng3_i1549_i10133_i10404_i10703_i10897 };
                                                                      }
                                                                    }
                                                                  }
                                                                }
                                                              }
                                                            }
                                                          }
                                                        })();
                                                        {
                                                          const bits_i10139_i10409_i10708_i10902 = $p15619_i10138_i10408_i10707_i10901._0;
                                                          {
                                                            const rng2_i10140_i10410_i10709_i10903 = $p15619_i10138_i10408_i10707_i10901._1;
                                                            {
                                                              const $t15618_i10142_i10412_i10711_i10905 = (() => {
                                                                {
                                                                  const $t15617_i10141_i10411_i10710_i10904 = bits_i10139_i10409_i10708_i10902;
                                                                  return ($t15617_i10141_i10411_i10710_i10904 / 4.50359962737e+15);
                                                                }
                                                              })();
                                                              return { _0: $t15618_i10142_i10412_i10711_i10905, _1: rng2_i10140_i10410_i10709_i10903 };
                                                            }
                                                          }
                                                        }
                                                      }
                                                    })();
                                                    {
                                                      const t_i10414_i10713_i10907 = $p29061_i10413_i10712_i10906._0;
                                                      {
                                                        const rng2_i10415_i10714_i10908 = $p29061_i10413_i10712_i10906._1;
                                                        {
                                                          const out_i10416_i10715_i10909 = { _0: rng2_i10415_i10714_i10908, _1: t_i10414_i10713_i10907 };
                                                          return out_i10416_i10715_i10909;
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              })();
                                              {
                                                const rng2 = $p27672._0;
                                                {
                                                  const roll = $p27672._1;
                                                  {
                                                    const $t27652 = (roll < 0.35);
                                                    if ($t27652 === true) {
                                                      return (() => {
                                                        {
                                                          const angle = (() => {
                                                            {
                                                              const $t27654 = (() => {
                                                                {
                                                                  const $t27653 = s.y;
                                                                  return (y2 - $t27653);
                                                                }
                                                              })();
                                                              {
                                                                const $t27656 = (() => {
                                                                  {
                                                                    const $t27655 = s.x;
                                                                    return (x2 - $t27655);
                                                                  }
                                                                })();
                                                                return Math.atan2($t27654, $t27656);
                                                              }
                                                            }
                                                          })();
                                                          {
                                                            const r = (() => {
                                                              {
                                                                const $t27657 = s.capture_radius;
                                                                return ($t27657 * 0.8);
                                                              }
                                                            })();
                                                            {
                                                              const a2 = (() => {
                                                                {
                                                                  const $t27662 = (() => {
                                                                    {
                                                                      const $t27659 = s.x;
                                                                      {
                                                                        const $t27661 = (() => {
                                                                          {
                                                                            const $t27660 = Math.cos(angle);
                                                                            return ($t27660 * r);
                                                                          }
                                                                        })();
                                                                        return ($t27659 + $t27661);
                                                                      }
                                                                    }
                                                                  })();
                                                                  {
                                                                    const $t27666 = (() => {
                                                                      {
                                                                        const $t27663 = s.y;
                                                                        {
                                                                          const $t27665 = (() => {
                                                                            {
                                                                              const $t27664 = Math.sin(angle);
                                                                              return ($t27664 * r);
                                                                            }
                                                                          })();
                                                                          return ($t27663 + $t27665);
                                                                        }
                                                                      }
                                                                    })();
                                                                    {
                                                                      const $t27667 = { $: "AsteroidOrbiting", _0: idx, _1: angle };
                                                                      return ({ ...a, x: $t27662, y: $t27666, mode: $t27667 });
                                                                    }
                                                                  }
                                                                }
                                                              })();
                                                              {
                                                                const $t27668 = ({ ...game, rng: rng2 });
                                                                {
                                                                  const $t27669 = { $: "Cons", _0: a2, _1: acc };
                                                                  return Perihelion$Combat$step_asteroids_go($t27668, rest, $t27669, dt_s);
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
                                                            const $t27670 = ({ ...game, rng: rng2 });
                                                            {
                                                              const $t27671 = { $: "Cons", _0: a2, _1: acc };
                                                              return Perihelion$Combat$step_asteroids_go($t27670, rest, $t27671, dt_s);
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
    const $t27688 = game.asteroids;
    {
      const $t27689 = { $: "Nil" };
      return Perihelion$Combat$step_asteroids_go(game, $t27688, $t27689, dt_s);
    }
  }
}
const Perihelion$Combat$step_asteroids$clo = { _0: ($_, game, dt_s) => Perihelion$Combat$step_asteroids(game, dt_s) };

function Perihelion$Combat$step_ships(game, dt_s) {
  {
    const $t27690 = game.ships;
    {
      const $t27691 = { $: "Nil" };
      {
        const $t27692 = { $: "Nil" };
        return Perihelion$Combat$step_ships_go(game, $t27690, $t27691, $t27692, dt_s);
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
      const $f27703 = stars._0;
      const $f27704 = stars._1;
      {
        const rest = (() => {
          return $f27704;
        })();
        {
          const s = (() => {
            return $f27703;
          })();
          {
            const $t27693 = (i === skip_idx);
            if ($t27693 === true) {
              return (() => {
                {
                  const $t27694 = (i + 1);
                  return Perihelion$Combat$nearest_other_star(from_x, from_y, skip_idx, rest, $t27694, best, best_d);
                }
              })();
            } else {
              return (() => {
                {
                  const dx = (() => {
                    {
                      const $t27695 = s.x;
                      return ($t27695 - from_x);
                    }
                  })();
                  {
                    const dy = (() => {
                      {
                        const $t27696 = s.y;
                        return ($t27696 - from_y);
                      }
                    })();
                    {
                      const d = (() => {
                        {
                          const $t27697 = (dx * dx);
                          {
                            const $t27698 = (dy * dy);
                            return ($t27697 + $t27698);
                          }
                        }
                      })();
                      {
                        const $t27699 = (d < best_d);
                        {
                          const $jp999_$t27700 = (i + 1);
                          if ($t27699 === true) {
                            return (() => {
                              {
                                const $t27701 = { $: "Some", _0: i };
                                return Perihelion$Combat$nearest_other_star(from_x, from_y, skip_idx, rest, $jp999_$t27700, $t27701, d);
                              }
                            })();
                          } else {
                            return (() => {
                              return Perihelion$Combat$nearest_other_star(from_x, from_y, skip_idx, rest, $jp999_$t27700, best, best_d);
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
      const $f27719 = stars._0;
      const $f27720 = stars._1;
      {
        const rest = $f27720;
        {
          const s = $f27719;
          {
            const dx = (() => {
              {
                const $t27709 = s.x;
                return ($t27709 - x);
              }
            })();
            {
              const dy = (() => {
                {
                  const $t27710 = s.y;
                  return ($t27710 - y);
                }
              })();
              {
                const $t27716 = (() => {
                  {
                    const $t27714 = (() => {
                      {
                        const $t27713 = (() => {
                          {
                            const $t27711 = (dx * dx);
                            {
                              const $t27712 = (dy * dy);
                              return ($t27711 + $t27712);
                            }
                          }
                        })();
                        return Math.sqrt($t27713);
                      }
                    })();
                    {
                      const $t27715 = s.capture_radius;
                      return ($t27714 <= $t27715);
                    }
                  }
                })();
                if ($t27716 === true) {
                  return (() => {
                    {
                      const $t27717 = { _0: i, _1: s };
                      return { $: "Some", _0: $t27717 };
                    }
                  })();
                } else {
                  return (() => {
                    {
                      const $t27718 = (i + 1);
                      return Perihelion$Combat$arrived_star(rest, x, y, $t27718);
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
        const $t27725 = game.ball_x;
        return ($t27725 - sx);
      }
    })();
    {
      const dy = (() => {
        {
          const $t27726 = game.ball_y;
          return ($t27726 - sy);
        }
      })();
      {
        const dist = (() => {
          {
            const $t27729 = (() => {
              {
                const $t27727 = (dx * dx);
                {
                  const $t27728 = (dy * dy);
                  return ($t27727 + $t27728);
                }
              }
            })();
            return Math.sqrt($t27729);
          }
        })();
        {
          const $t27730 = (dist > 0.);
          if ($t27730 === true) {
            return (() => {
              {
                const $t27733 = (() => {
                  {
                    const $t27731 = (dx / dist);
                    return ($t27731 * 150.);
                  }
                })();
                {
                  const $t27736 = (() => {
                    {
                      const $t27734 = (dy / dist);
                      return ($t27734 * 150.);
                    }
                  })();
                  return ({ x: sx, y: sy, vx: $t27733, vy: $t27736, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
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
        const $t27740 = (() => {
          {
            const go_i3710 = { $: "$Clo_go$4768", _0: go$apply$4768 };
            {
              const $t293_i3711 = { $: "Nil" };
              return go$apply$4768(go_i3710, acc, $t293_i3711);
            }
          }
        })();
        {
          const $t27741 = game.enemy_shots;
          {
            const $t27742 = (() => {
              {
                const go_i9835 = { $: "$Clo_go$4766", _0: go$apply$4766 };
                {
                  const $t301_i9838 = (() => {
                    {
                      const go_i4489_i9836 = { $: "$Clo_go$5241", _0: go$apply$5241 };
                      {
                        const $t293_i4490_i9837 = { $: "Nil" };
                        return go$apply$5241(go_i4489_i9836, new_shots, $t293_i4490_i9837);
                      }
                    }
                  })();
                  return go$apply$4766(go_i9835, $t301_i9838, $t27741);
                }
              }
            })();
            return ({ ...game, ships: $t27740, enemy_shots: $t27742 });
          }
        }
      }
      break;
    }
    case "Cons": {
      const $f27853 = ships._0;
      const $f27854 = ships._1;
      {
        const rest = $f27854;
        {
          const sh = $f27853;
          {
            const $t27743 = sh.mode;
            switch ($t27743.$) {
              case "ShipOrbiting": {
                const $f27846 = $t27743._0;
                {
                  const angle = (() => {
                    return $f27846;
                  })();
                  {
                    const $t27745 = (() => {
                      {
                        const $t27744 = sh.star_idx;
                        return Perihelion$Core$star_at(game, $t27744);
                      }
                    })();
                    switch ($t27745.$) {
                      case "None": {
                        return Perihelion$Combat$step_ships_go(game, rest, acc, new_shots, dt_s);
                        break;
                      }
                      case "Some": {
                        const $f27811 = $t27745._0;
                        {
                          const s = $f27811;
                          {
                            const idle2 = (() => {
                              {
                                const $t27746 = sh.idle_timer;
                                return ($t27746 - dt_s);
                              }
                            })();
                            {
                              const $t27747 = (idle2 <= 0.);
                              if ($t27747 === true) {
                                return (() => {
                                  {
                                    const $p27782 = (() => {
                                      {
                                        const $t27748 = sh.hunter;
                                        if ($t27748 === true) {
                                          return (() => {
                                            {
                                              const $t27749 = game.ball_x;
                                              {
                                                const $t27750 = game.ball_y;
                                                return { _0: $t27749, _1: $t27750 };
                                              }
                                            }
                                          })();
                                        } else {
                                          return (() => {
                                            {
                                              const $t27751 = sh.x;
                                              {
                                                const $t27752 = sh.y;
                                                return { _0: $t27751, _1: $t27752 };
                                              }
                                            }
                                          })();
                                        }
                                      }
                                    })();
                                    {
                                      const tx = $p27782._0;
                                      {
                                        const ty = $p27782._1;
                                        {
                                          const $t27756 = (() => {
                                            {
                                              const $t27753 = sh.star_idx;
                                              {
                                                const $t27754 = game.stars;
                                                {
                                                  const $t27755 = { $: "None" };
                                                  return Perihelion$Combat$nearest_other_star(tx, ty, $t27753, $t27754, 0, $t27755, 999999999.);
                                                }
                                              }
                                            }
                                          })();
                                          switch ($t27756.$) {
                                            case "None": {
                                              {
                                                const sh2 = ({ ...sh, idle_timer: 6. });
                                                {
                                                  const $t27758 = { $: "Cons", _0: sh2, _1: acc };
                                                  return Perihelion$Combat$step_ships_go(game, rest, $t27758, new_shots, dt_s);
                                                }
                                              }
                                              break;
                                            }
                                            case "Some": {
                                              const $f27781 = $t27756._0;
                                              {
                                                const target_idx = $f27781;
                                                {
                                                  const $t27759 = Perihelion$Core$star_at(game, target_idx);
                                                  switch ($t27759.$) {
                                                    case "None": {
                                                      {
                                                        const sh2 = ({ ...sh, idle_timer: 6. });
                                                        {
                                                          const $t27761 = { $: "Cons", _0: sh2, _1: acc };
                                                          return Perihelion$Combat$step_ships_go(game, rest, $t27761, new_shots, dt_s);
                                                        }
                                                      }
                                                      break;
                                                    }
                                                    case "Some": {
                                                      const $f27780 = $t27759._0;
                                                      {
                                                        const t = $f27780;
                                                        {
                                                          const dx = (() => {
                                                            {
                                                              const $t27762 = t.x;
                                                              {
                                                                const $t27763 = sh.x;
                                                                return ($t27762 - $t27763);
                                                              }
                                                            }
                                                          })();
                                                          {
                                                            const dy = (() => {
                                                              {
                                                                const $t27764 = t.y;
                                                                {
                                                                  const $t27765 = sh.y;
                                                                  return ($t27764 - $t27765);
                                                                }
                                                              }
                                                            })();
                                                            {
                                                              const dist = (() => {
                                                                {
                                                                  const $t27768 = (() => {
                                                                    {
                                                                      const $t27766 = (dx * dx);
                                                                      {
                                                                        const $t27767 = (dy * dy);
                                                                        return ($t27766 + $t27767);
                                                                      }
                                                                    }
                                                                  })();
                                                                  return Math.sqrt($t27768);
                                                                }
                                                              })();
                                                              {
                                                                const vel = (() => {
                                                                  {
                                                                    const $t27769 = (dist > 0.);
                                                                    if ($t27769 === true) {
                                                                      return (() => {
                                                                        {
                                                                          const $t27772 = (() => {
                                                                            {
                                                                              const $t27770 = (dx / dist);
                                                                              return ($t27770 * 180.);
                                                                            }
                                                                          })();
                                                                          {
                                                                            const $t27775 = (() => {
                                                                              {
                                                                                const $t27773 = (dy / dist);
                                                                                return ($t27773 * 180.);
                                                                              }
                                                                            })();
                                                                            return { _0: $t27772, _1: $t27775 };
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
                                                                          const $t27777 = { $: "ShipFlying", _0: vx, _1: vy };
                                                                          return ({ ...sh, mode: $t27777 });
                                                                        }
                                                                      })();
                                                                      {
                                                                        const $t27778 = { $: "Cons", _0: sh2, _1: acc };
                                                                        return Perihelion$Combat$step_ships_go(game, rest, $t27778, new_shots, dt_s);
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
                                          const $t27787 = (() => {
                                            {
                                              const $t27786 = (d * 1.4);
                                              return ($t27786 * dt_s);
                                            }
                                          })();
                                          return (angle + $t27787);
                                        }
                                      })();
                                      {
                                        const r = (() => {
                                          {
                                            const $t27788 = s.capture_radius;
                                            return ($t27788 * 1.6);
                                          }
                                        })();
                                        {
                                          const sx = (() => {
                                            {
                                              const $t27790 = s.x;
                                              {
                                                const $t27792 = (() => {
                                                  {
                                                    const $t27791 = Math.cos(angle2);
                                                    return ($t27791 * r);
                                                  }
                                                })();
                                                return ($t27790 + $t27792);
                                              }
                                            }
                                          })();
                                          {
                                            const sy = (() => {
                                              {
                                                const $t27793 = s.y;
                                                {
                                                  const $t27795 = (() => {
                                                    {
                                                      const $t27794 = Math.sin(angle2);
                                                      return ($t27794 * r);
                                                    }
                                                  })();
                                                  return ($t27793 + $t27795);
                                                }
                                              }
                                            })();
                                            {
                                              const cd2 = (() => {
                                                {
                                                  const $t27796 = sh.fire_cooldown;
                                                  return ($t27796 - dt_s);
                                                }
                                              })();
                                              {
                                                const in_range = (() => {
                                                  {
                                                    const $t27799 = (() => {
                                                      {
                                                        const $t27797 = game.ball_x;
                                                        {
                                                          const $t27798 = game.ball_y;
                                                          {
                                                            const dx_i3718 = ($t27797 - sx);
                                                            {
                                                              const dy_i3719 = ($t27798 - sy);
                                                              {
                                                                const $t27402_i3720 = (dx_i3718 * dx_i3718);
                                                                {
                                                                  const $t27403_i3721 = (dy_i3719 * dy_i3719);
                                                                  return ($t27402_i3720 + $t27403_i3721);
                                                                }
                                                              }
                                                            }
                                                          }
                                                        }
                                                      }
                                                    })();
                                                    {
                                                      const $t27802 = (380. * 380.);
                                                      return ($t27799 <= $t27802);
                                                    }
                                                  }
                                                })();
                                                {
                                                  const $t27804 = (() => {
                                                    {
                                                      const $t27803 = (cd2 <= 0.);
                                                      return ($t27803 && in_range);
                                                    }
                                                  })();
                                                  if ($t27804 === true) {
                                                    return (() => {
                                                      {
                                                        const shot = Perihelion$Combat$ship_fire_shot(sx, sy, game);
                                                        {
                                                          const sh2 = (() => {
                                                            {
                                                              const $t27805 = { $: "ShipOrbiting", _0: angle2 };
                                                              return ({ ...sh, x: sx, y: sy, mode: $t27805, idle_timer: idle2, fire_cooldown: 2.5 });
                                                            }
                                                          })();
                                                          {
                                                            const $t27807 = { $: "Cons", _0: sh2, _1: acc };
                                                            {
                                                              const $t27808 = { $: "Cons", _0: shot, _1: new_shots };
                                                              return Perihelion$Combat$step_ships_go(game, rest, $t27807, $t27808, dt_s);
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
                                                            const $t27809 = { $: "ShipOrbiting", _0: angle2 };
                                                            return ({ ...sh, x: sx, y: sy, mode: $t27809, idle_timer: idle2, fire_cooldown: cd2 });
                                                          }
                                                        })();
                                                        {
                                                          const $t27810 = { $: "Cons", _0: sh2, _1: acc };
                                                          return Perihelion$Combat$step_ships_go(game, rest, $t27810, new_shots, dt_s);
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
                const $f27847 = $t27743._0;
                const $f27848 = $t27743._1;
                {
                  const vy = (() => {
                    return $f27848;
                  })();
                  {
                    const vx = (() => {
                      return $f27847;
                    })();
                    {
                      const x2 = (() => {
                        {
                          const $t27812 = sh.x;
                          {
                            const $t27813 = (vx * dt_s);
                            return ($t27812 + $t27813);
                          }
                        }
                      })();
                      {
                        const y2 = (() => {
                          {
                            const $t27814 = sh.y;
                            {
                              const $t27815 = (vy * dt_s);
                              return ($t27814 + $t27815);
                            }
                          }
                        })();
                        {
                          const $t27817 = (() => {
                            {
                              const $t27816 = game.stars;
                              return Perihelion$Combat$arrived_star($t27816, x2, y2, 0);
                            }
                          })();
                          switch ($t27817.$) {
                            case "Some": {
                              const $f27845 = $t27817._0;
                              {
                                const pair = $f27845;
                                {
                                  const idx = pair._0;
                                  {
                                    const t = pair._1;
                                    {
                                      const angle = (() => {
                                        {
                                          const $t27819 = (() => {
                                            {
                                              const $t27818 = t.y;
                                              return (y2 - $t27818);
                                            }
                                          })();
                                          {
                                            const $t27821 = (() => {
                                              {
                                                const $t27820 = t.x;
                                                return (x2 - $t27820);
                                              }
                                            })();
                                            return Math.atan2($t27819, $t27821);
                                          }
                                        }
                                      })();
                                      {
                                        const $p27841 = (() => {
                                          {
                                            const $t27822 = game.rng;
                                            {
                                              const $p29061_i10413_i10712_i10925 = (() => {
                                                {
                                                  const $p15619_i10138_i10408_i10707_i10920 = (() => {
                                                    {
                                                      const $p15616_i1544_i10128_i10399_i10698_i10911 = Random$next_raw($t27822);
                                                      {
                                                        const hi_i1545_i10129_i10400_i10699_i10912 = $p15616_i1544_i10128_i10399_i10698_i10911._0;
                                                        {
                                                          const rng2_i1546_i10130_i10401_i10700_i10913 = $p15616_i1544_i10128_i10399_i10698_i10911._1;
                                                          {
                                                            const $p15615_i1547_i10131_i10402_i10701_i10914 = Random$next_raw(rng2_i1546_i10130_i10401_i10700_i10913);
                                                            {
                                                              const lo_i1548_i10132_i10403_i10702_i10915 = $p15615_i1547_i10131_i10402_i10701_i10914._0;
                                                              {
                                                                const rng3_i1549_i10133_i10404_i10703_i10916 = $p15615_i1547_i10131_i10402_i10701_i10914._1;
                                                                {
                                                                  const $t15614_i1553_i10137_i10407_i10706_i10919 = (() => {
                                                                    {
                                                                      const $t15613_i1552_i10136_i10406_i10705_i10918 = (() => {
                                                                        {
                                                                          const $t15611_i1550_i10134_i10405_i10704_i10917 = march_int_and(hi_i1545_i10129_i10400_i10699_i10912, 1048575);
                                                                          return ($t15611_i1550_i10134_i10405_i10704_i10917 * 4294967296);
                                                                        }
                                                                      })();
                                                                      return ($t15613_i1552_i10136_i10406_i10705_i10918 + lo_i1548_i10132_i10403_i10702_i10915);
                                                                    }
                                                                  })();
                                                                  return { _0: $t15614_i1553_i10137_i10407_i10706_i10919, _1: rng3_i1549_i10133_i10404_i10703_i10916 };
                                                                }
                                                              }
                                                            }
                                                          }
                                                        }
                                                      }
                                                    }
                                                  })();
                                                  {
                                                    const bits_i10139_i10409_i10708_i10921 = $p15619_i10138_i10408_i10707_i10920._0;
                                                    {
                                                      const rng2_i10140_i10410_i10709_i10922 = $p15619_i10138_i10408_i10707_i10920._1;
                                                      {
                                                        const $t15618_i10142_i10412_i10711_i10924 = (() => {
                                                          {
                                                            const $t15617_i10141_i10411_i10710_i10923 = bits_i10139_i10409_i10708_i10921;
                                                            return ($t15617_i10141_i10411_i10710_i10923 / 4.50359962737e+15);
                                                          }
                                                        })();
                                                        return { _0: $t15618_i10142_i10412_i10711_i10924, _1: rng2_i10140_i10410_i10709_i10922 };
                                                      }
                                                    }
                                                  }
                                                }
                                              })();
                                              {
                                                const t_i10414_i10713_i10926 = $p29061_i10413_i10712_i10925._0;
                                                {
                                                  const rng2_i10415_i10714_i10927 = $p29061_i10413_i10712_i10925._1;
                                                  {
                                                    const out_i10416_i10715_i10928 = { _0: rng2_i10415_i10714_i10927, _1: t_i10414_i10713_i10926 };
                                                    return out_i10416_i10715_i10928;
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        {
                                          const rng2 = $p27841._0;
                                          {
                                            const idle_f = $p27841._1;
                                            {
                                              const idle = (() => {
                                                {
                                                  const $t27827 = (() => {
                                                    {
                                                      const $t27826 = (6. - 3.);
                                                      return (idle_f * $t27826);
                                                    }
                                                  })();
                                                  return (3. + $t27827);
                                                }
                                              })();
                                              {
                                                const r = (() => {
                                                  {
                                                    const $t27828 = t.capture_radius;
                                                    return ($t27828 * 1.6);
                                                  }
                                                })();
                                                {
                                                  const sh2 = (() => {
                                                    {
                                                      const $t27833 = (() => {
                                                        {
                                                          const $t27830 = t.x;
                                                          {
                                                            const $t27832 = (() => {
                                                              {
                                                                const $t27831 = Math.cos(angle);
                                                                return ($t27831 * r);
                                                              }
                                                            })();
                                                            return ($t27830 + $t27832);
                                                          }
                                                        }
                                                      })();
                                                      {
                                                        const $t27837 = (() => {
                                                          {
                                                            const $t27834 = t.y;
                                                            {
                                                              const $t27836 = (() => {
                                                                {
                                                                  const $t27835 = Math.sin(angle);
                                                                  return ($t27835 * r);
                                                                }
                                                              })();
                                                              return ($t27834 + $t27836);
                                                            }
                                                          }
                                                        })();
                                                        {
                                                          const $t27838 = { $: "ShipOrbiting", _0: angle };
                                                          return ({ ...sh, x: $t27833, y: $t27837, star_idx: idx, mode: $t27838, idle_timer: idle });
                                                        }
                                                      }
                                                    }
                                                  })();
                                                  {
                                                    const $t27839 = ({ ...game, rng: rng2 });
                                                    {
                                                      const $t27840 = { $: "Cons", _0: sh2, _1: acc };
                                                      return Perihelion$Combat$step_ships_go($t27839, rest, $t27840, new_shots, dt_s);
                                                    }
                                                  }
                                                }
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
                                const $t27843 = Perihelion$Combat$in_band(game, x2, y2);
                                if ($t27843 === true) {
                                  return (() => {
                                    {
                                      const sh2 = ({ ...sh, x: x2, y: y2 });
                                      {
                                        const $t27844 = { $: "Cons", _0: sh2, _1: acc };
                                        return Perihelion$Combat$step_ships_go(game, rest, $t27844, new_shots, dt_s);
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
    const $t27859 = game.mode;
    switch ($t27859.$) {
      case "Orbiting": {
        const $f27880 = $t27859._0;
        const $f27881 = $t27859._1;
        const $f27882 = $t27859._2;
        {
          const idx = (() => {
            return $f27880;
          })();
          {
            const $t27860 = Perihelion$Core$star_at(game, idx);
            switch ($t27860.$) {
              case "None": {
                return { $: "None" };
                break;
              }
              case "Some": {
                const $f27872 = $t27860._0;
                {
                  const s = $f27872;
                  {
                    const rdx = (() => {
                      {
                        const $t27861 = game.ball_x;
                        {
                          const $t27862 = s.x;
                          return ($t27861 - $t27862);
                        }
                      }
                    })();
                    {
                      const rdy = (() => {
                        {
                          const $t27863 = game.ball_y;
                          {
                            const $t27864 = s.y;
                            return ($t27863 - $t27864);
                          }
                        }
                      })();
                      {
                        const rdist = (() => {
                          {
                            const $t27867 = (() => {
                              {
                                const $t27865 = (rdx * rdx);
                                {
                                  const $t27866 = (rdy * rdy);
                                  return ($t27865 + $t27866);
                                }
                              }
                            })();
                            return Math.sqrt($t27867);
                          }
                        })();
                        {
                          const $t27868 = (rdist > 0.);
                          if ($t27868 === true) {
                            return (() => {
                              {
                                const $t27869 = (rdx / rdist);
                                {
                                  const $t27870 = (rdy / rdist);
                                  {
                                    const $t27871 = { _0: $t27869, _1: $t27870 };
                                    return { $: "Some", _0: $t27871 };
                                  }
                                }
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
        const $f27891 = $t27859._0;
        const $f27892 = $t27859._1;
        {
          const vy = (() => {
            return $f27892;
          })();
          {
            const vx = (() => {
              return $f27891;
            })();
            {
              const speed = (() => {
                {
                  const $t27875 = (() => {
                    {
                      const $t27873 = (vx * vx);
                      {
                        const $t27874 = (vy * vy);
                        return ($t27873 + $t27874);
                      }
                    }
                  })();
                  return Math.sqrt($t27875);
                }
              })();
              {
                const $t27876 = (speed > 0.);
                if ($t27876 === true) {
                  return (() => {
                    {
                      const $t27877 = (vx / speed);
                      {
                        const $t27878 = (vy / speed);
                        {
                          const $t27879 = { _0: $t27877, _1: $t27878 };
                          return { $: "Some", _0: $t27879 };
                        }
                      }
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
    const $t27897 = game.mode;
    switch ($t27897.$) {
      case "Orbiting": {
        const $f27905 = $t27897._0;
        const $f27906 = $t27897._1;
        const $f27907 = $t27897._2;
        return game;
        break;
      }
      case "Flying": {
        const $f27916 = $t27897._0;
        const $f27917 = $t27897._1;
        {
          const vy = (() => {
            return $f27917;
          })();
          {
            const vx = (() => {
              return $f27916;
            })();
            {
              const $t27904 = (() => {
                {
                  const $t27900 = (() => {
                    {
                      const $t27899 = (ax * 14.);
                      return (vx - $t27899);
                    }
                  })();
                  {
                    const $t27903 = (() => {
                      {
                        const $t27902 = (ay * 14.);
                        return (vy - $t27902);
                      }
                    })();
                    return { $: "Flying", _0: $t27900, _1: $t27903 };
                  }
                }
              })();
              return ({ ...game, mode: $t27904 });
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
    const $p27963 = (() => {
      {
        const $t27943 = (0. - 0.5236);
        {
          const $t27936_i9915 = (() => {
            {
              const $t27933_i9912 = (() => {
                {
                  const $t27932_i9911 = Math.cos($t27943);
                  return (ax * $t27932_i9911);
                }
              })();
              {
                const $t27935_i9914 = (() => {
                  {
                    const $t27934_i9913 = Math.sin($t27943);
                    return (ay * $t27934_i9913);
                  }
                })();
                return ($t27933_i9912 - $t27935_i9914);
              }
            }
          })();
          {
            const $t27941_i9920 = (() => {
              {
                const $t27938_i9917 = (() => {
                  {
                    const $t27937_i9916 = Math.sin($t27943);
                    return (ax * $t27937_i9916);
                  }
                })();
                {
                  const $t27940_i9919 = (() => {
                    {
                      const $t27939_i9918 = Math.cos($t27943);
                      return (ay * $t27939_i9918);
                    }
                  })();
                  return ($t27938_i9917 + $t27940_i9919);
                }
              }
            })();
            return { _0: $t27936_i9915, _1: $t27941_i9920 };
          }
        }
      }
    })();
    {
      const a1x = $p27963._0;
      {
        const a1y = $p27963._1;
        {
          const $p27962 = (() => {
            {
              const $t27946 = (() => {
                {
                  const $t27945 = (0.5236 / 2.);
                  return (0. - $t27945);
                }
              })();
              {
                const $t27936_i9902 = (() => {
                  {
                    const $t27933_i9899 = (() => {
                      {
                        const $t27932_i9898 = Math.cos($t27946);
                        return (ax * $t27932_i9898);
                      }
                    })();
                    {
                      const $t27935_i9901 = (() => {
                        {
                          const $t27934_i9900 = Math.sin($t27946);
                          return (ay * $t27934_i9900);
                        }
                      })();
                      return ($t27933_i9899 - $t27935_i9901);
                    }
                  }
                })();
                {
                  const $t27941_i9907 = (() => {
                    {
                      const $t27938_i9904 = (() => {
                        {
                          const $t27937_i9903 = Math.sin($t27946);
                          return (ax * $t27937_i9903);
                        }
                      })();
                      {
                        const $t27940_i9906 = (() => {
                          {
                            const $t27939_i9905 = Math.cos($t27946);
                            return (ay * $t27939_i9905);
                          }
                        })();
                        return ($t27938_i9904 + $t27940_i9906);
                      }
                    }
                  })();
                  return { _0: $t27936_i9902, _1: $t27941_i9907 };
                }
              }
            }
          })();
          {
            const a2x = $p27962._0;
            {
              const a2y = $p27962._1;
              {
                const $p27961 = (() => {
                  {
                    const $t27948 = (0.5236 / 2.);
                    {
                      const $t27936_i9889 = (() => {
                        {
                          const $t27933_i9886 = (() => {
                            {
                              const $t27932_i9885 = Math.cos($t27948);
                              return (ax * $t27932_i9885);
                            }
                          })();
                          {
                            const $t27935_i9888 = (() => {
                              {
                                const $t27934_i9887 = Math.sin($t27948);
                                return (ay * $t27934_i9887);
                              }
                            })();
                            return ($t27933_i9886 - $t27935_i9888);
                          }
                        }
                      })();
                      {
                        const $t27941_i9894 = (() => {
                          {
                            const $t27938_i9891 = (() => {
                              {
                                const $t27937_i9890 = Math.sin($t27948);
                                return (ax * $t27937_i9890);
                              }
                            })();
                            {
                              const $t27940_i9893 = (() => {
                                {
                                  const $t27939_i9892 = Math.cos($t27948);
                                  return (ay * $t27939_i9892);
                                }
                              })();
                              return ($t27938_i9891 + $t27940_i9893);
                            }
                          }
                        })();
                        return { _0: $t27936_i9889, _1: $t27941_i9894 };
                      }
                    }
                  }
                })();
                {
                  const a3x = $p27961._0;
                  {
                    const a3y = $p27961._1;
                    {
                      const $p27960 = (() => {
                        {
                          const $t27936_i9876 = (() => {
                            {
                              const $t27933_i9873 = (() => {
                                {
                                  const $t27932_i9872 = Math.cos(0.5236);
                                  return (ax * $t27932_i9872);
                                }
                              })();
                              {
                                const $t27935_i9875 = (() => {
                                  {
                                    const $t27934_i9874 = Math.sin(0.5236);
                                    return (ay * $t27934_i9874);
                                  }
                                })();
                                return ($t27933_i9873 - $t27935_i9875);
                              }
                            }
                          })();
                          {
                            const $t27941_i9881 = (() => {
                              {
                                const $t27938_i9878 = (() => {
                                  {
                                    const $t27937_i9877 = Math.sin(0.5236);
                                    return (ax * $t27937_i9877);
                                  }
                                })();
                                {
                                  const $t27940_i9880 = (() => {
                                    {
                                      const $t27939_i9879 = Math.cos(0.5236);
                                      return (ay * $t27939_i9879);
                                    }
                                  })();
                                  return ($t27938_i9878 + $t27940_i9880);
                                }
                              }
                            })();
                            return { _0: $t27936_i9876, _1: $t27941_i9881 };
                          }
                        }
                      })();
                      {
                        const a4x = $p27960._0;
                        {
                          const a4y = $p27960._1;
                          {
                            const $t27950 = (() => {
                              {
                                const $t27923_i9867 = (ax * 420.);
                                {
                                  const $t27925_i9868 = (ay * 420.);
                                  return ({ x: x, y: y, vx: $t27923_i9867, vy: $t27925_i9868, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                }
                              }
                            })();
                            {
                              const $t27951 = (() => {
                                {
                                  const $t27923_i9861 = (a1x * 420.);
                                  {
                                    const $t27925_i9862 = (a1y * 420.);
                                    return ({ x: x, y: y, vx: $t27923_i9861, vy: $t27925_i9862, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                  }
                                }
                              })();
                              {
                                const $t27952 = (() => {
                                  {
                                    const $t27923_i9855 = (a2x * 420.);
                                    {
                                      const $t27925_i9856 = (a2y * 420.);
                                      return ({ x: x, y: y, vx: $t27923_i9855, vy: $t27925_i9856, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                    }
                                  }
                                })();
                                {
                                  const $t27953 = (() => {
                                    {
                                      const $t27923_i9849 = (a3x * 420.);
                                      {
                                        const $t27925_i9850 = (a3y * 420.);
                                        return ({ x: x, y: y, vx: $t27923_i9849, vy: $t27925_i9850, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                      }
                                    }
                                  })();
                                  {
                                    const $t27954 = (() => {
                                      {
                                        const $t27923_i9843 = (a4x * 420.);
                                        {
                                          const $t27925_i9844 = (a4y * 420.);
                                          return ({ x: x, y: y, vx: $t27923_i9843, vy: $t27925_i9844, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                        }
                                      }
                                    })();
                                    {
                                      const $t27955 = { $: "Nil" };
                                      {
                                        const $t27956 = { $: "Cons", _0: $t27954, _1: $t27955 };
                                        {
                                          const $t27957 = { $: "Cons", _0: $t27953, _1: $t27956 };
                                          {
                                            const $t27958 = { $: "Cons", _0: $t27952, _1: $t27957 };
                                            {
                                              const $t27959 = { $: "Cons", _0: $t27951, _1: $t27958 };
                                              return { $: "Cons", _0: $t27950, _1: $t27959 };
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
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
    const $t27964 = Perihelion$Core$active_weapon(game);
    switch ($t27964.$) {
      case "StarKiller": {
        {
          const $t27965 = game.starkiller_cooldown;
          return ($t27965 > 0.);
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
        const $t27967 = { $: "$Clo_$lam27966$3708", _0: $lam27966$apply$3708 };
        return List$any$List_String$Fn_String_Bool(keys, $t27967);
      }
    })();
    {
      const $t27973 = (() => {
        {
          const $t27971 = (() => {
            {
              const $t27968 = (!pressed);
              {
                const $t27970 = (() => {
                  {
                    const $t27969 = game.fire_cooldown;
                    return ($t27969 > 0.);
                  }
                })();
                return ($t27968 || $t27970);
              }
            }
          })();
          {
            const $t27972 = Perihelion$Combat$starkiller_on_cooldown(game);
            return ($t27971 || $t27972);
          }
        }
      })();
      if ($t27973 === true) {
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
                    const $t27974 = cy;
                    {
                      const $t27975 = game.camera_y;
                      return ($t27974 + $t27975);
                    }
                  }
                })();
                {
                  const dx = (() => {
                    {
                      const $t27976 = cx;
                      {
                        const $t27977 = game.ball_x;
                        return ($t27976 - $t27977);
                      }
                    }
                  })();
                  {
                    const dy = (() => {
                      {
                        const $t27978 = game.ball_y;
                        return (cursor_world_y - $t27978);
                      }
                    })();
                    {
                      const dist = (() => {
                        {
                          const $t27981 = (() => {
                            {
                              const $t27979 = (dx * dx);
                              {
                                const $t27980 = (dy * dy);
                                return ($t27979 + $t27980);
                              }
                            }
                          })();
                          return Math.sqrt($t27981);
                        }
                      })();
                      {
                        const aim = (() => {
                          {
                            const $t27982 = (dist > 0.);
                            if ($t27982 === true) {
                              return (() => {
                                {
                                  const $t27983 = (dx / dist);
                                  {
                                    const $t27984 = (dy / dist);
                                    {
                                      const $t27985 = { _0: $t27983, _1: $t27984 };
                                      return { $: "Some", _0: $t27985 };
                                    }
                                  }
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
                            const $f28032 = aim._0;
                            {
                              const pair = $f28032;
                              {
                                const ax = pair._0;
                                {
                                  const ay = pair._1;
                                  {
                                    const g2 = Perihelion$Combat$apply_recoil(game, ax, ay);
                                    {
                                      const $t27986 = Perihelion$Core$active_weapon(game);
                                      {
                                        let new_shots;
                                        switch ($t27986.$) {
                                          case "Base": {
                                            new_shots = (() => {
                                              {
                                                const $t27989 = (() => {
                                                  {
                                                    const $t27987 = game.ball_x;
                                                    {
                                                      const $t27988 = game.ball_y;
                                                      {
                                                        const $t27923_i9937 = (ax * 420.);
                                                        {
                                                          const $t27925_i9938 = (ay * 420.);
                                                          return ({ x: $t27987, y: $t27988, vx: $t27923_i9937, vy: $t27925_i9938, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                                        }
                                                      }
                                                    }
                                                  }
                                                })();
                                                {
                                                  const $t27990 = { $: "Nil" };
                                                  return { $: "Cons", _0: $t27989, _1: $t27990 };
                                                }
                                              }
                                            })();
                                            break;
                                          }
                                          case "Homing": {
                                            new_shots = (() => {
                                              {
                                                const $t27993 = (() => {
                                                  {
                                                    const $t27991 = game.ball_x;
                                                    {
                                                      const $t27992 = game.ball_y;
                                                      {
                                                        const $t27928_i9943 = (ax * 420.);
                                                        {
                                                          const $t27930_i9944 = (ay * 420.);
                                                          return ({ x: $t27991, y: $t27992, vx: $t27928_i9943, vy: $t27930_i9944, ttl: 3., homing: true, star_killer: false, target_x: 0., target_y: 0. });
                                                        }
                                                      }
                                                    }
                                                  }
                                                })();
                                                {
                                                  const $t27994 = { $: "Nil" };
                                                  return { $: "Cons", _0: $t27993, _1: $t27994 };
                                                }
                                              }
                                            })();
                                            break;
                                          }
                                          case "Spread": {
                                            new_shots = (() => {
                                              {
                                                const $t27995 = game.ball_x;
                                                {
                                                  const $t27996 = game.ball_y;
                                                  return Perihelion$Combat$spread_shots($t27995, $t27996, ax, ay);
                                                }
                                              }
                                            })();
                                            break;
                                          }
                                          case "StarKiller": {
                                            new_shots = (() => {
                                              {
                                                const $t27998 = (() => {
                                                  {
                                                    const $t27997 = Perihelion$Combat$starkiller_target_idx(game);
                                                    return Perihelion$Core$star_at(game, $t27997);
                                                  }
                                                })();
                                                switch ($t27998.$) {
                                                  case "None": {
                                                    return { $: "Nil" };
                                                    break;
                                                  }
                                                  case "Some": {
                                                    const $f28021 = $t27998._0;
                                                    {
                                                      const target = $f28021;
                                                      {
                                                        const tdx = (() => {
                                                          {
                                                            const $t27999 = target.x;
                                                            {
                                                              const $t28000 = game.ball_x;
                                                              return ($t27999 - $t28000);
                                                            }
                                                          }
                                                        })();
                                                        {
                                                          const tdy = (() => {
                                                            {
                                                              const $t28001 = target.y;
                                                              {
                                                                const $t28002 = game.ball_y;
                                                                return ($t28001 - $t28002);
                                                              }
                                                            }
                                                          })();
                                                          {
                                                            const tdist = (() => {
                                                              {
                                                                const $t28005 = (() => {
                                                                  {
                                                                    const $t28003 = (tdx * tdx);
                                                                    {
                                                                      const $t28004 = (tdy * tdy);
                                                                      return ($t28003 + $t28004);
                                                                    }
                                                                  }
                                                                })();
                                                                return Math.sqrt($t28005);
                                                              }
                                                            })();
                                                            {
                                                              const $t28006 = (tdist <= 0.);
                                                              if ($t28006 === true) {
                                                                return { $: "Nil" };
                                                              } else {
                                                                return (() => {
                                                                  {
                                                                    const $t28019 = (() => {
                                                                      {
                                                                        const $t28007 = game.ball_x;
                                                                        {
                                                                          const $t28008 = game.ball_y;
                                                                          {
                                                                            const $t28011 = (() => {
                                                                              {
                                                                                const $t28009 = (tdx / tdist);
                                                                                return ($t28009 * 420.);
                                                                              }
                                                                            })();
                                                                            {
                                                                              const $t28014 = (() => {
                                                                                {
                                                                                  const $t28012 = (tdy / tdist);
                                                                                  return ($t28012 * 420.);
                                                                                }
                                                                              })();
                                                                              {
                                                                                const $t28016 = (3. * 3.);
                                                                                {
                                                                                  const $t28017 = target.x;
                                                                                  {
                                                                                    const $t28018 = target.y;
                                                                                    return ({ x: $t28007, y: $t28008, vx: $t28011, vy: $t28014, ttl: $t28016, homing: false, star_killer: true, target_x: $t28017, target_y: $t28018 });
                                                                                  }
                                                                                }
                                                                              }
                                                                            }
                                                                          }
                                                                        }
                                                                      }
                                                                    })();
                                                                    {
                                                                      const $t28020 = { $: "Nil" };
                                                                      return { $: "Cons", _0: $t28019, _1: $t28020 };
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
                                              const $t28022 = Perihelion$Core$active_weapon(game);
                                              switch ($t28022.$) {
                                                case "StarKiller": {
                                                  return game.fire_cooldown;
                                                  break;
                                                }
                                                default: {
                                                  {
                                                    const reduced_i9931 = (() => {
                                                      {
                                                        const $t27391_i9930 = (() => {
                                                          {
                                                            const $t27389_i9929 = (() => {
                                                              {
                                                                const $t27388_i9928 = game.fire_rate_stacks;
                                                                return $t27388_i9928;
                                                              }
                                                            })();
                                                            return ($t27389_i9929 * 0.05);
                                                          }
                                                        })();
                                                        return (0.4 - $t27391_i9930);
                                                      }
                                                    })();
                                                    {
                                                      const $t27393_i9932 = (reduced_i9931 < 0.15);
                                                      if ($t27393_i9932 === true) {
                                                        return 0.15;
                                                      } else {
                                                        return reduced_i9931;
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
                                                const $t28025 = Perihelion$Core$active_weapon(game);
                                                switch ($t28025.$) {
                                                  case "StarKiller": {
                                                    {
                                                      let $t28026;
                                                      switch (new_shots.$) {
                                                        case "Nil": {
                                                          $t28026 = true;
                                                          break;
                                                        }
                                                        default: {
                                                          $t28026 = false;
                                                          break;
                                                        }
                                                      }
                                                      if ($t28026 === true) {
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
                                              const $t28029 = g2.player_shots;
                                              {
                                                const $t28030 = (() => {
                                                  {
                                                    const go_i9923 = { $: "$Clo_go$4766", _0: go$apply$4766 };
                                                    {
                                                      const $t301_i9926 = (() => {
                                                        {
                                                          const go_i4489_i9924 = { $: "$Clo_go$5241", _0: go$apply$5241 };
                                                          {
                                                            const $t293_i4490_i9925 = { $: "Nil" };
                                                            return go$apply$5241(go_i4489_i9924, $t28029, $t293_i4490_i9925);
                                                          }
                                                        }
                                                      })();
                                                      return go$apply$4766(go_i9923, $t301_i9926, new_shots);
                                                    }
                                                  }
                                                })();
                                                return ({ ...g2, player_shots: $t28030, fire_cooldown: cooldown2, starkiller_cooldown: starkiller_cd2 });
                                              }
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
      const $f28048 = stars._0;
      const $f28049 = stars._1;
      {
        const rest = (() => {
          return $f28049;
        })();
        {
          const s = (() => {
            return $f28048;
          })();
          {
            const $t28046 = (() => {
              {
                const $t28044 = s.x;
                {
                  const $t28045 = s.y;
                  {
                    const $t27404_i9955 = (() => {
                      {
                        const dx_i3645_i9951 = (tx - $t28044);
                        {
                          const dy_i3646_i9952 = (ty - $t28045);
                          {
                            const $t27402_i3647_i9953 = (dx_i3645_i9951 * dx_i3645_i9951);
                            {
                              const $t27403_i3648_i9954 = (dy_i3646_i9952 * dy_i3646_i9952);
                              return ($t27402_i3647_i9953 + $t27403_i3648_i9954);
                            }
                          }
                        }
                      }
                    })();
                    {
                      const $t27407_i9958 = (() => {
                        {
                          const $t27405_i9956 = (0.001 + 0.);
                          {
                            const $t27406_i9957 = (0.001 + 0.);
                            return ($t27405_i9956 * $t27406_i9957);
                          }
                        }
                      })();
                      return ($t27404_i9955 <= $t27407_i9958);
                    }
                  }
                }
              }
            })();
            if ($t28046 === true) {
              return { $: "Some", _0: i };
            } else {
              return (() => {
                {
                  const $t28047 = (i + 1);
                  return Perihelion$Combat$find_star_by_pos(rest, tx, ty, $t28047);
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
    const $t28054 = game.player_shots;
    {
      const $t28056 = { $: "$Clo_$lam28055$3714", _0: $lam28055$apply$3714 };
      {
        const sk_shots = (() => {
          {
            const pred_i3768 = $t28056;
            {
              const go_i3769 = { $: "$Clo_go$4760", _0: go$apply$4760, _1: pred_i3768 };
              {
                const $t342_i3770 = { $: "Nil" };
                return go$apply$4760(go_i3769, $t28054, $t342_i3770);
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
            const $f28080 = sk_shots._0;
            const $f28081 = sk_shots._1;
            {
              const s = $f28080;
              {
                const $t28062 = (() => {
                  {
                    const $t28057 = s.x;
                    {
                      const $t28058 = s.y;
                      {
                        const $t28060 = s.target_x;
                        {
                          const $t28061 = s.target_y;
                          {
                            const $t27404_i9980 = (() => {
                              {
                                const dx_i3645_i9976 = ($t28060 - $t28057);
                                {
                                  const dy_i3646_i9977 = ($t28061 - $t28058);
                                  {
                                    const $t27402_i3647_i9978 = (dx_i3645_i9976 * dx_i3645_i9976);
                                    {
                                      const $t27403_i3648_i9979 = (dy_i3646_i9977 * dy_i3646_i9977);
                                      return ($t27402_i3647_i9978 + $t27403_i3648_i9979);
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const $t27407_i9983 = (() => {
                                {
                                  const $t27405_i9981 = (20. + 0.);
                                  {
                                    const $t27406_i9982 = (20. + 0.);
                                    return ($t27405_i9981 * $t27406_i9982);
                                  }
                                }
                              })();
                              return ($t27404_i9980 <= $t27407_i9983);
                            }
                          }
                        }
                      }
                    }
                  }
                })();
                if ($t28062 === true) {
                  return (() => {
                    {
                      const $t28066 = (() => {
                        {
                          const $t28063 = game.stars;
                          {
                            const $t28064 = s.target_x;
                            {
                              const $t28065 = s.target_y;
                              return Perihelion$Combat$find_star_by_pos($t28063, $t28064, $t28065, 0);
                            }
                          }
                        }
                      })();
                      switch ($t28066.$) {
                        case "None": {
                          {
                            const $t28067 = game.player_shots;
                            {
                              const $t28070 = { $: "$Clo_$lam28068$3716", _0: $lam28068$apply$3716 };
                              {
                                const $t28071 = (() => {
                                  {
                                    const pred_i3760 = $t28070;
                                    {
                                      const go_i3761 = { $: "$Clo_go$4760", _0: go$apply$4760, _1: pred_i3760 };
                                      {
                                        const $t342_i3762 = { $: "Nil" };
                                        return go$apply$4760(go_i3761, $t28067, $t342_i3762);
                                      }
                                    }
                                  }
                                })();
                                return ({ ...game, player_shots: $t28071 });
                              }
                            }
                          }
                          break;
                        }
                        case "Some": {
                          const $f28079 = $t28066._0;
                          {
                            const tidx = $f28079;
                            {
                              const g2 = Perihelion$Core$remove_star(game, tidx);
                              {
                                const $t28072 = g2.ships;
                                {
                                  const $t28073 = (() => {
                                    {
                                      const $t28036_i9961 = { $: "$Clo_$lam28034$3711", _0: $lam28034$apply$3711, _1: tidx };
                                      {
                                        const $t28037_i9965 = (() => {
                                          {
                                            const pred_i3753_i9962 = $t28036_i9961;
                                            {
                                              const go_i3754_i9963 = { $: "$Clo_go$4772", _0: go$apply$4772, _1: pred_i3753_i9962 };
                                              {
                                                const $t342_i3755_i9964 = { $: "Nil" };
                                                return go$apply$4772(go_i3754_i9963, $t28072, $t342_i3755_i9964);
                                              }
                                            }
                                          }
                                        })();
                                        {
                                          const $t28043_i9966 = { $: "$Clo_$lam28038$3712", _0: $lam28038$apply$3712, _1: tidx };
                                          {
                                            const f_i3749_i9967 = $t28043_i9966;
                                            {
                                              const go_i3750_i9968 = { $: "$Clo_go$4770", _0: go$apply$4770, _1: f_i3749_i9967 };
                                              {
                                                const $t310_i3751_i9969 = { $: "Nil" };
                                                return go$apply$4770(go_i3750_i9968, $t28037_i9965, $t310_i3751_i9969);
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t28074 = game.player_shots;
                                    {
                                      const $t28077 = { $: "$Clo_$lam28075$3717", _0: $lam28075$apply$3717 };
                                      {
                                        const $t28078 = (() => {
                                          {
                                            const pred_i3764 = $t28077;
                                            {
                                              const go_i3765 = { $: "$Clo_go$4760", _0: go$apply$4760, _1: pred_i3764 };
                                              {
                                                const $t342_i3766 = { $: "Nil" };
                                                return go$apply$4760(go_i3765, $t28074, $t342_i3766);
                                              }
                                            }
                                          }
                                        })();
                                        return ({ ...g2, ships: $t28073, player_shots: $t28078 });
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
    const $p28118 = (() => {
      {
        const $t28093 = game.asteroids;
        {
          const $t28101 = { $: "$Clo_$lam28094$3719", _0: $lam28094$apply$3719, _1: game };
          {
            const pred_i3782 = $t28101;
            {
              const go_i3783 = { $: "$Clo_go$4779", _0: go$apply$4779, _1: pred_i3782 };
              {
                const $t597_i3784 = { $: "Nil" };
                {
                  const $t598_i3785 = { $: "Nil" };
                  return go$apply$4779(go_i3783, $t28093, $t597_i3784, $t598_i3785);
                }
              }
            }
          }
        }
      }
    })();
    {
      const dead = $p28118._0;
      {
        const alive = $p28118._1;
        {
          const $t28102 = game.player_shots;
          {
            const $t28111 = { $: "$Clo_$lam28103$3721", _0: $lam28103$apply$3721, _1: game };
            {
              const shots = (() => {
                {
                  const pred_i3778 = $t28111;
                  {
                    const go_i3779 = { $: "$Clo_go$4760", _0: go$apply$4760, _1: pred_i3778 };
                    {
                      const $t342_i3780 = { $: "Nil" };
                      return go$apply$4760(go_i3779, $t28102, $t342_i3780);
                    }
                  }
                }
              })();
              {
                const $t28116 = (() => {
                  {
                    const $t28112 = game.score;
                    {
                      const $t28115 = (() => {
                        {
                          const $t28113 = (() => {
                            {
                              const go_i3776 = { $: "$Clo_go$4776", _0: go$apply$4776 };
                              return go$apply$4776(go_i3776, dead, 0);
                            }
                          })();
                          {
                            const $t28114 = game.multiplier;
                            return ($t28113 * $t28114);
                          }
                        }
                      })();
                      return ($t28112 + $t28115);
                    }
                  }
                })();
                {
                  const $t28117 = (() => {
                    {
                      const $t28092_i9999 = { $: "$Clo_$lam28089$3718", _0: $lam28089$apply$3718 };
                      {
                        const f_i3772_i10000 = $t28092_i9999;
                        {
                          const go_i3773_i10001 = { $: "$Clo_go$4774", _0: go$apply$4774, _1: f_i3772_i10000 };
                          {
                            const $t310_i3774_i10002 = { $: "Nil" };
                            return go$apply$4774(go_i3773_i10001, dead, $t310_i3774_i10002);
                          }
                        }
                      }
                    }
                  })();
                  return ({ ...game, asteroids: alive, player_shots: shots, score: $t28116, fx_bursts: $t28117 });
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
        const pos_i3789 = (() => {
          {
            const $t27400_i3787 = sh.x;
            {
              const $t27401_i3788 = sh.y;
              return { _0: $t27400_i3787, _1: $t27401_i3788 };
            }
          }
        })();
        return pos_i3789;
      }
    })();
    {
      const sx = pos._0;
      {
        const sy = pos._1;
        {
          const $t28086_i10374 = s.x;
          {
            const $t28087_i10375 = s.y;
            {
              const $t27404_i9994_i10380 = (() => {
                {
                  const dx_i3645_i9990_i10376 = (sx - $t28086_i10374);
                  {
                    const dy_i3646_i9991_i10377 = (sy - $t28087_i10375);
                    {
                      const $t27402_i3647_i9992_i10378 = (dx_i3645_i9990_i10376 * dx_i3645_i9990_i10376);
                      {
                        const $t27403_i3648_i9993_i10379 = (dy_i3646_i9991_i10377 * dy_i3646_i9991_i10377);
                        return ($t27402_i3647_i9992_i10378 + $t27403_i3648_i9993_i10379);
                      }
                    }
                  }
                }
              })();
              {
                const $t27407_i9997_i10383 = (() => {
                  {
                    const $t27405_i9995_i10381 = (3. + 10.);
                    {
                      const $t27406_i9996_i10382 = (3. + 10.);
                      return ($t27405_i9995_i10381 * $t27406_i9996_i10382);
                    }
                  }
                })();
                return ($t27404_i9994_i10380 <= $t27407_i9997_i10383);
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
    const $p28140 = (() => {
      {
        const $t28121 = game.ships;
        {
          const $t28126 = { $: "$Clo_$lam28122$3723", _0: $lam28122$apply$3723, _1: game };
          {
            const pred_i3797 = $t28126;
            {
              const go_i3798 = { $: "$Clo_go$4785", _0: go$apply$4785, _1: pred_i3797 };
              {
                const $t597_i3799 = { $: "Nil" };
                {
                  const $t598_i3800 = { $: "Nil" };
                  return go$apply$4785(go_i3798, $t28121, $t597_i3799, $t598_i3800);
                }
              }
            }
          }
        }
      }
    })();
    {
      const dead = $p28140._0;
      {
        const alive = $p28140._1;
        {
          const $t28127 = game.player_shots;
          {
            const $t28133 = { $: "$Clo_$lam28128$3725", _0: $lam28128$apply$3725, _1: game };
            {
              const shots = (() => {
                {
                  const pred_i3793 = $t28133;
                  {
                    const go_i3794 = { $: "$Clo_go$4760", _0: go$apply$4760, _1: pred_i3793 };
                    {
                      const $t342_i3795 = { $: "Nil" };
                      return go$apply$4760(go_i3794, $t28127, $t342_i3795);
                    }
                  }
                }
              })();
              {
                const g2 = (() => {
                  {
                    const $t28139 = (() => {
                      {
                        const $t28134 = game.score;
                        {
                          const $t28138 = (() => {
                            {
                              const $t28136 = (() => {
                                {
                                  const $t28135 = (() => {
                                    {
                                      const go_i3791 = { $: "$Clo_go$4782", _0: go$apply$4782 };
                                      return go$apply$4782(go_i3791, dead, 0);
                                    }
                                  })();
                                  {
                                    const sr_s1 = ($t28135 + $t28135);
                                    return sr_s1;
                                  }
                                }
                              })();
                              {
                                const $t28137 = game.multiplier;
                                return ($t28136 * $t28137);
                              }
                            }
                          })();
                          return ($t28134 + $t28138);
                        }
                      }
                    })();
                    return ({ ...game, ships: alive, player_shots: shots, score: $t28139 });
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
      const $f28166 = dead._0;
      const $f28167 = dead._1;
      {
        const rest = $f28167;
        {
          const sh = $f28166;
          {
            const pos = (() => {
              {
                const pos_i3808 = (() => {
                  {
                    const $t27400_i3806 = sh.x;
                    {
                      const $t27401_i3807 = sh.y;
                      return { _0: $t27400_i3806, _1: $t27401_i3807 };
                    }
                  }
                })();
                return pos_i3808;
              }
            })();
            {
              const sx = pos._0;
              {
                const sy = pos._1;
                {
                  const $p28164 = (() => {
                    {
                      const $t28141 = game.rng;
                      {
                        const $p29061_i10413_i10712_i10963 = (() => {
                          {
                            const $p15619_i10138_i10408_i10707_i10958 = (() => {
                              {
                                const $p15616_i1544_i10128_i10399_i10698_i10949 = Random$next_raw($t28141);
                                {
                                  const hi_i1545_i10129_i10400_i10699_i10950 = $p15616_i1544_i10128_i10399_i10698_i10949._0;
                                  {
                                    const rng2_i1546_i10130_i10401_i10700_i10951 = $p15616_i1544_i10128_i10399_i10698_i10949._1;
                                    {
                                      const $p15615_i1547_i10131_i10402_i10701_i10952 = Random$next_raw(rng2_i1546_i10130_i10401_i10700_i10951);
                                      {
                                        const lo_i1548_i10132_i10403_i10702_i10953 = $p15615_i1547_i10131_i10402_i10701_i10952._0;
                                        {
                                          const rng3_i1549_i10133_i10404_i10703_i10954 = $p15615_i1547_i10131_i10402_i10701_i10952._1;
                                          {
                                            const $t15614_i1553_i10137_i10407_i10706_i10957 = (() => {
                                              {
                                                const $t15613_i1552_i10136_i10406_i10705_i10956 = (() => {
                                                  {
                                                    const $t15611_i1550_i10134_i10405_i10704_i10955 = march_int_and(hi_i1545_i10129_i10400_i10699_i10950, 1048575);
                                                    return ($t15611_i1550_i10134_i10405_i10704_i10955 * 4294967296);
                                                  }
                                                })();
                                                return ($t15613_i1552_i10136_i10406_i10705_i10956 + lo_i1548_i10132_i10403_i10702_i10953);
                                              }
                                            })();
                                            return { _0: $t15614_i1553_i10137_i10407_i10706_i10957, _1: rng3_i1549_i10133_i10404_i10703_i10954 };
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const bits_i10139_i10409_i10708_i10959 = $p15619_i10138_i10408_i10707_i10958._0;
                              {
                                const rng2_i10140_i10410_i10709_i10960 = $p15619_i10138_i10408_i10707_i10958._1;
                                {
                                  const $t15618_i10142_i10412_i10711_i10962 = (() => {
                                    {
                                      const $t15617_i10141_i10411_i10710_i10961 = bits_i10139_i10409_i10708_i10959;
                                      return ($t15617_i10141_i10411_i10710_i10961 / 4.50359962737e+15);
                                    }
                                  })();
                                  return { _0: $t15618_i10142_i10412_i10711_i10962, _1: rng2_i10140_i10410_i10709_i10960 };
                                }
                              }
                            }
                          }
                        })();
                        {
                          const t_i10414_i10713_i10964 = $p29061_i10413_i10712_i10963._0;
                          {
                            const rng2_i10415_i10714_i10965 = $p29061_i10413_i10712_i10963._1;
                            {
                              const out_i10416_i10715_i10966 = { _0: rng2_i10415_i10714_i10965, _1: t_i10414_i10713_i10964 };
                              return out_i10416_i10715_i10966;
                            }
                          }
                        }
                      }
                    }
                  })();
                  {
                    const rng2 = $p28164._0;
                    {
                      const roll = $p28164._1;
                      {
                        const g2 = (() => {
                          {
                            const $t28143 = (roll < 0.25);
                            if ($t28143 === true) {
                              return (() => {
                                {
                                  const owns_starkiller = (() => {
                                    {
                                      const $t28144 = game.owned_weapons;
                                      {
                                        const $t28145 = { $: "StarKiller" };
                                        {
                                          const $t709_i3804 = { $: "$Clo_$lam708$4787", _0: $lam708$apply$4787, _1: $t28145 };
                                          return List$any$List_WeaponKind$Fn_WeaponKind_Bool($t28144, $t709_i3804);
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $p28163 = (() => {
                                      {
                                        const $p29061_i10413_i10712_i10944 = (() => {
                                          {
                                            const $p15619_i10138_i10408_i10707_i10939 = (() => {
                                              {
                                                const $p15616_i1544_i10128_i10399_i10698_i10930 = Random$next_raw(rng2);
                                                {
                                                  const hi_i1545_i10129_i10400_i10699_i10931 = $p15616_i1544_i10128_i10399_i10698_i10930._0;
                                                  {
                                                    const rng2_i1546_i10130_i10401_i10700_i10932 = $p15616_i1544_i10128_i10399_i10698_i10930._1;
                                                    {
                                                      const $p15615_i1547_i10131_i10402_i10701_i10933 = Random$next_raw(rng2_i1546_i10130_i10401_i10700_i10932);
                                                      {
                                                        const lo_i1548_i10132_i10403_i10702_i10934 = $p15615_i1547_i10131_i10402_i10701_i10933._0;
                                                        {
                                                          const rng3_i1549_i10133_i10404_i10703_i10935 = $p15615_i1547_i10131_i10402_i10701_i10933._1;
                                                          {
                                                            const $t15614_i1553_i10137_i10407_i10706_i10938 = (() => {
                                                              {
                                                                const $t15613_i1552_i10136_i10406_i10705_i10937 = (() => {
                                                                  {
                                                                    const $t15611_i1550_i10134_i10405_i10704_i10936 = march_int_and(hi_i1545_i10129_i10400_i10699_i10931, 1048575);
                                                                    return ($t15611_i1550_i10134_i10405_i10704_i10936 * 4294967296);
                                                                  }
                                                                })();
                                                                return ($t15613_i1552_i10136_i10406_i10705_i10937 + lo_i1548_i10132_i10403_i10702_i10934);
                                                              }
                                                            })();
                                                            return { _0: $t15614_i1553_i10137_i10407_i10706_i10938, _1: rng3_i1549_i10133_i10404_i10703_i10935 };
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            })();
                                            {
                                              const bits_i10139_i10409_i10708_i10940 = $p15619_i10138_i10408_i10707_i10939._0;
                                              {
                                                const rng2_i10140_i10410_i10709_i10941 = $p15619_i10138_i10408_i10707_i10939._1;
                                                {
                                                  const $t15618_i10142_i10412_i10711_i10943 = (() => {
                                                    {
                                                      const $t15617_i10141_i10411_i10710_i10942 = bits_i10139_i10409_i10708_i10940;
                                                      return ($t15617_i10141_i10411_i10710_i10942 / 4.50359962737e+15);
                                                    }
                                                  })();
                                                  return { _0: $t15618_i10142_i10412_i10711_i10943, _1: rng2_i10140_i10410_i10709_i10941 };
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        {
                                          const t_i10414_i10713_i10945 = $p29061_i10413_i10712_i10944._0;
                                          {
                                            const rng2_i10415_i10714_i10946 = $p29061_i10413_i10712_i10944._1;
                                            {
                                              const out_i10416_i10715_i10947 = { _0: rng2_i10415_i10714_i10946, _1: t_i10414_i10713_i10945 };
                                              return out_i10416_i10715_i10947;
                                            }
                                          }
                                        }
                                      }
                                    })();
                                    {
                                      const rng3 = $p28163._0;
                                      {
                                        const sk_roll = $p28163._1;
                                        {
                                          const $t28149 = (() => {
                                            {
                                              const $t28146 = (!owns_starkiller);
                                              {
                                                const $t28148 = (sk_roll < 0.08);
                                                return ($t28146 && $t28148);
                                              }
                                            }
                                          })();
                                          if ($t28149 === true) {
                                            return (() => {
                                              {
                                                const $t28153 = (() => {
                                                  {
                                                    const $t28152 = (() => {
                                                      {
                                                        const $t28151 = { $: "StarKiller" };
                                                        return { $: "OffenseWeapon", _0: $t28151 };
                                                      }
                                                    })();
                                                    return ({ x: sx, y: sy, ttl: 8., kind: $t28152 });
                                                  }
                                                })();
                                                {
                                                  const $t28154 = game.pickups;
                                                  {
                                                    const $t28155 = (() => {
                                                      return { $: "Cons", _0: $t28153, _1: $t28154 };
                                                    })();
                                                    return ({ ...game, rng: rng3, pickups: $t28155 });
                                                  }
                                                }
                                              }
                                            })();
                                          } else {
                                            return (() => {
                                              {
                                                const $p28162 = (() => {
                                                  {
                                                    const $t28156 = game.owned_weapons;
                                                    {
                                                      const $t28157 = game.special;
                                                      return Perihelion$Upgrades$roll_one(rng3, $t28156, $t28157);
                                                    }
                                                  }
                                                })();
                                                {
                                                  const rng4 = $p28162._0;
                                                  {
                                                    const upgrade = $p28162._1;
                                                    {
                                                      const $t28159 = (() => {
                                                        return ({ x: sx, y: sy, ttl: 8., kind: upgrade });
                                                      })();
                                                      {
                                                        const $t28160 = game.pickups;
                                                        {
                                                          const $t28161 = (() => {
                                                            return { $: "Cons", _0: $t28159, _1: $t28160 };
                                                          })();
                                                          return ({ ...game, rng: rng4, pickups: $t28161 });
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
    const $t28181 = (() => {
      {
        const $t28178 = game.pickups;
        {
          const $t28180 = { $: "$Clo_$lam28179$3728", _0: $lam28179$apply$3728, _1: game };
          return List$find$List_R_kind_UpgradeKind_ttl_Float_x_Float_y_Float$Fn_R_kind_UpgradeKind_ttl_Float_x_Float_y_Float_Bool($t28178, $t28180);
        }
      }
    })();
    switch ($t28181.$) {
      case "None": {
        return game;
        break;
      }
      case "Some": {
        const $f28207 = $t28181._0;
        {
          const p = $f28207;
          {
            const $t28182 = game.pickups;
            {
              const $t28185 = { $: "$Clo_$lam28183$3729", _0: $lam28183$apply$3729, _1: game };
              {
                const remaining = (() => {
                  {
                    const pred_i3812 = $t28185;
                    {
                      const go_i3813 = { $: "$Clo_go$4756", _0: go$apply$4756, _1: pred_i3812 };
                      {
                        const $t342_i3814 = { $: "Nil" };
                        return go$apply$4756(go_i3813, $t28182, $t342_i3814);
                      }
                    }
                  }
                })();
                {
                  const $t28186 = p.kind;
                  switch ($t28186.$) {
                    case "SpecialItem": {
                      const $f28200 = $t28186._0;
                      {
                        const $jp_clo28202 = (() => {
                          return { $: "$Clo_$jp28201$3730", _0: $jp28201$apply$3730, _1: game, _2: p, _3: remaining };
                        })();
                        {
                          const $t28187 = game.special;
                          switch ($t28187.$) {
                            case "None": {
                              {
                                const $t28189 = (() => {
                                  {
                                    const $t28188 = p.kind;
                                    return Perihelion$Core$apply_upgrade(game, $t28188);
                                  }
                                })();
                                return ({ ...$t28189, pickups: remaining });
                              }
                              break;
                            }
                            case "Some": {
                              const $f28194 = $t28187._0;
                              {
                                const $t28190 = { $: "Milestone" };
                                {
                                  const $t28191 = p.kind;
                                  {
                                    const $t28192 = { $: "Nil" };
                                    {
                                      const $t28193 = (() => {
                                        return { $: "Cons", _0: $t28191, _1: $t28192 };
                                      })();
                                      return ({ ...game, pickups: remaining, phase: $t28190, milestone_choices: $t28193 });
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
                        const $jp_clo28206 = (() => {
                          return { $: "$Clo_$jp28205$3731", _0: $jp28205$apply$3731, _1: game, _2: p, _3: remaining };
                        })();
                        {
                          const grant = (() => {
                            {
                              const $t28195 = game.shield_reinforced;
                              if ($t28195 === true) {
                                return 2;
                              } else {
                                return 1;
                              }
                            }
                          })();
                          {
                            const $t28197 = (() => {
                              {
                                const $t28196 = game.shield;
                                return ($t28196 + grant);
                              }
                            })();
                            return ({ ...game, shield: $t28197, pickups: remaining });
                          }
                        }
                      }
                      break;
                    }
                    default: {
                      {
                        const $t28199 = (() => {
                          {
                            const $t28198 = p.kind;
                            return Perihelion$Core$apply_upgrade(game, $t28198);
                          }
                        })();
                        return ({ ...$t28199, pickups: remaining });
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
        const pos_i3818 = (() => {
          {
            const $t27400_i3816 = sh.x;
            {
              const $t27401_i3817 = sh.y;
              return { _0: $t27400_i3816, _1: $t27401_i3817 };
            }
          }
        })();
        return pos_i3818;
      }
    })();
    {
      const sx = pos._0;
      {
        const sy = pos._1;
        {
          const $t28209 = game.ball_x;
          {
            const $t28210 = game.ball_y;
            {
              const $t27404_i10027 = (() => {
                {
                  const dx_i3645_i10023 = ($t28209 - sx);
                  {
                    const dy_i3646_i10024 = ($t28210 - sy);
                    {
                      const $t27402_i3647_i10025 = (dx_i3645_i10023 * dx_i3645_i10023);
                      {
                        const $t27403_i3648_i10026 = (dy_i3646_i10024 * dy_i3646_i10024);
                        return ($t27402_i3647_i10025 + $t27403_i3648_i10026);
                      }
                    }
                  }
                }
              })();
              {
                const $t27407_i10030 = (() => {
                  {
                    const $t27405_i10028 = (10. + 6.);
                    {
                      const $t27406_i10029 = (10. + 6.);
                      return ($t27405_i10028 * $t27406_i10029);
                    }
                  }
                })();
                return ($t27404_i10027 <= $t27407_i10030);
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
    const $p28224 = (() => {
      {
        const $t28222 = game.rng;
        {
          const $p29061_i10413_i10712_i10982 = (() => {
            {
              const $p15619_i10138_i10408_i10707_i10977 = (() => {
                {
                  const $p15616_i1544_i10128_i10399_i10698_i10968 = Random$next_raw($t28222);
                  {
                    const hi_i1545_i10129_i10400_i10699_i10969 = $p15616_i1544_i10128_i10399_i10698_i10968._0;
                    {
                      const rng2_i1546_i10130_i10401_i10700_i10970 = $p15616_i1544_i10128_i10399_i10698_i10968._1;
                      {
                        const $p15615_i1547_i10131_i10402_i10701_i10971 = Random$next_raw(rng2_i1546_i10130_i10401_i10700_i10970);
                        {
                          const lo_i1548_i10132_i10403_i10702_i10972 = $p15615_i1547_i10131_i10402_i10701_i10971._0;
                          {
                            const rng3_i1549_i10133_i10404_i10703_i10973 = $p15615_i1547_i10131_i10402_i10701_i10971._1;
                            {
                              const $t15614_i1553_i10137_i10407_i10706_i10976 = (() => {
                                {
                                  const $t15613_i1552_i10136_i10406_i10705_i10975 = (() => {
                                    {
                                      const $t15611_i1550_i10134_i10405_i10704_i10974 = march_int_and(hi_i1545_i10129_i10400_i10699_i10969, 1048575);
                                      return ($t15611_i1550_i10134_i10405_i10704_i10974 * 4294967296);
                                    }
                                  })();
                                  return ($t15613_i1552_i10136_i10406_i10705_i10975 + lo_i1548_i10132_i10403_i10702_i10972);
                                }
                              })();
                              return { _0: $t15614_i1553_i10137_i10407_i10706_i10976, _1: rng3_i1549_i10133_i10404_i10703_i10973 };
                            }
                          }
                        }
                      }
                    }
                  }
                }
              })();
              {
                const bits_i10139_i10409_i10708_i10978 = $p15619_i10138_i10408_i10707_i10977._0;
                {
                  const rng2_i10140_i10410_i10709_i10979 = $p15619_i10138_i10408_i10707_i10977._1;
                  {
                    const $t15618_i10142_i10412_i10711_i10981 = (() => {
                      {
                        const $t15617_i10141_i10411_i10710_i10980 = bits_i10139_i10409_i10708_i10978;
                        return ($t15617_i10141_i10411_i10710_i10980 / 4.50359962737e+15);
                      }
                    })();
                    return { _0: $t15618_i10142_i10412_i10711_i10981, _1: rng2_i10140_i10410_i10709_i10979 };
                  }
                }
              }
            }
          })();
          {
            const t_i10414_i10713_i10983 = $p29061_i10413_i10712_i10982._0;
            {
              const rng2_i10415_i10714_i10984 = $p29061_i10413_i10712_i10982._1;
              {
                const out_i10416_i10715_i10985 = { _0: rng2_i10415_i10714_i10984, _1: t_i10414_i10713_i10983 };
                return out_i10416_i10715_i10985;
              }
            }
          }
        }
      }
    })();
    {
      const rng2 = $p28224._0;
      {
        const t = $p28224._1;
        {
          const $t28223 = (t < 0.5);
          return { _0: rng2, _1: $t28223 };
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
        const $t28225 = game.enemy_shots;
        {
          const $t28227 = { $: "$Clo_$lam28226$3732", _0: $lam28226$apply$3732, _1: game };
          return List$any$List_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28225, $t28227);
        }
      }
    })();
    {
      const $t28229 = (() => {
        {
          const $t28228 = game.bullet_ward;
          return (shot_hit && $t28228);
        }
      })();
      if ($t28229 === true) {
        return (() => {
          {
            const $t28230 = game.enemy_shots;
            {
              const $t28233 = { $: "$Clo_$lam28231$3733", _0: $lam28231$apply$3733, _1: game };
              {
                const $t28234 = (() => {
                  {
                    const pred_i3820 = $t28233;
                    {
                      const go_i3821 = { $: "$Clo_go$4760", _0: go$apply$4760, _1: pred_i3820 };
                      {
                        const $t342_i3822 = { $: "Nil" };
                        return go$apply$4760(go_i3821, $t28230, $t342_i3822);
                      }
                    }
                  }
                })();
                return ({ ...game, bullet_ward: false, enemy_shots: $t28234 });
              }
            }
          }
        })();
      } else {
        return (() => {
          {
            const ast_hit = (() => {
              {
                const $t28235 = game.asteroids;
                {
                  const $t28237 = { $: "$Clo_$lam28236$3734", _0: $lam28236$apply$3734, _1: game };
                  return List$any$List_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28235, $t28237);
                }
              }
            })();
            {
              const ship_hit = (() => {
                {
                  const $t28238 = game.ships;
                  {
                    const $t28240 = { $: "$Clo_$lam28239$3735", _0: $lam28239$apply$3735, _1: game };
                    return List$any$List_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float$Fn_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float_Bool($t28238, $t28240);
                  }
                }
              })();
              {
                const $t28243 = (() => {
                  {
                    const $t28242 = (() => {
                      {
                        const $t28241 = (ast_hit || shot_hit);
                        return ($t28241 || ship_hit);
                      }
                    })();
                    return (!$t28242);
                  }
                })();
                if ($t28243 === true) {
                  return game;
                } else {
                  return (() => {
                    {
                      const $t28249 = (() => {
                        {
                          const $t28247 = (() => {
                            {
                              const $t28245 = (() => {
                                {
                                  const $t28244 = (!shot_hit);
                                  return (ast_hit && $t28244);
                                }
                              })();
                              {
                                const $t28246 = (!ship_hit);
                                return ($t28245 && $t28246);
                              }
                            }
                          })();
                          {
                            const $t28248 = game.deflector_plating;
                            return ($t28247 && $t28248);
                          }
                        }
                      })();
                      if ($t28249 === true) {
                        return (() => {
                          {
                            const $p28251 = Perihelion$Combat$deflector_roll(game);
                            {
                              const rng2 = $p28251._0;
                              {
                                const deflected = $p28251._1;
                                if (deflected === true) {
                                  return ({ ...game, rng: rng2 });
                                } else {
                                  return (() => {
                                    {
                                      const $t28250 = ({ ...game, rng: rng2 });
                                      return Perihelion$Combat$collide_ball_hazards_shield_or_die($t28250);
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
    const $t28253 = (() => {
      {
        const $t28252 = game.shield;
        return ($t28252 > 0);
      }
    })();
    if ($t28253 === true) {
      return (() => {
        {
          const $t28254 = game.asteroids;
          {
            const $t28256 = { $: "$Clo_$lam28255$3736", _0: $lam28255$apply$3736, _1: game };
            {
              const dead_ast = (() => {
                {
                  const pred_i3836 = $t28256;
                  {
                    const go_i3837 = { $: "$Clo_go$4791", _0: go$apply$4791, _1: pred_i3836 };
                    {
                      const $t342_i3838 = { $: "Nil" };
                      return go$apply$4791(go_i3837, $t28254, $t342_i3838);
                    }
                  }
                }
              })();
              {
                const $t28258 = (() => {
                  {
                    const $t28257 = game.shield;
                    return ($t28257 - 1);
                  }
                })();
                {
                  const $t28259 = game.asteroids;
                  {
                    const $t28262 = { $: "$Clo_$lam28260$3737", _0: $lam28260$apply$3737, _1: game };
                    {
                      const $t28263 = (() => {
                        {
                          const pred_i3832 = $t28262;
                          {
                            const go_i3833 = { $: "$Clo_go$4791", _0: go$apply$4791, _1: pred_i3832 };
                            {
                              const $t342_i3834 = { $: "Nil" };
                              return go$apply$4791(go_i3833, $t28259, $t342_i3834);
                            }
                          }
                        }
                      })();
                      {
                        const $t28264 = game.enemy_shots;
                        {
                          const $t28267 = { $: "$Clo_$lam28265$3738", _0: $lam28265$apply$3738, _1: game };
                          {
                            const $t28268 = (() => {
                              {
                                const pred_i3828 = $t28267;
                                {
                                  const go_i3829 = { $: "$Clo_go$4760", _0: go$apply$4760, _1: pred_i3828 };
                                  {
                                    const $t342_i3830 = { $: "Nil" };
                                    return go$apply$4760(go_i3829, $t28264, $t342_i3830);
                                  }
                                }
                              }
                            })();
                            {
                              const $t28269 = game.ships;
                              {
                                const $t28272 = { $: "$Clo_$lam28270$3739", _0: $lam28270$apply$3739, _1: game };
                                {
                                  const $t28273 = (() => {
                                    {
                                      const pred_i3824 = $t28272;
                                      {
                                        const go_i3825 = { $: "$Clo_go$4772", _0: go$apply$4772, _1: pred_i3824 };
                                        {
                                          const $t342_i3826 = { $: "Nil" };
                                          return go$apply$4772(go_i3825, $t28269, $t342_i3826);
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t28274 = game.fx_bursts;
                                    {
                                      const $t28275 = (() => {
                                        {
                                          const $t28092_i10052 = { $: "$Clo_$lam28089$3718", _0: $lam28089$apply$3718 };
                                          {
                                            const f_i3772_i10053 = $t28092_i10052;
                                            {
                                              const go_i3773_i10054 = { $: "$Clo_go$4774", _0: go$apply$4774, _1: f_i3772_i10053 };
                                              {
                                                const $t310_i3774_i10055 = { $: "Nil" };
                                                return go$apply$4774(go_i3773_i10054, dead_ast, $t310_i3774_i10055);
                                              }
                                            }
                                          }
                                        }
                                      })();
                                      {
                                        const $t28276 = (() => {
                                          {
                                            const go_i10047 = { $: "$Clo_go$4789", _0: go$apply$4789 };
                                            {
                                              const $t301_i10050 = (() => {
                                                {
                                                  const go_i4496_i10048 = { $: "$Clo_go$4319", _0: go$apply$4319 };
                                                  {
                                                    const $t293_i4497_i10049 = { $: "Nil" };
                                                    return go$apply$4319(go_i4496_i10048, $t28274, $t293_i4497_i10049);
                                                  }
                                                }
                                              })();
                                              return go$apply$4789(go_i10047, $t301_i10050, $t28275);
                                            }
                                          }
                                        })();
                                        return ({ ...game, shield: $t28258, asteroids: $t28263, enemy_shots: $t28268, ships: $t28273, fx_bursts: $t28276 });
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
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
    const $t28277 = Perihelion$Core$star_at(game, star_idx);
    switch ($t28277.$) {
      case "None": {
        return ({ ...game, rng: rng });
        break;
      }
      case "Some": {
        const $f28298 = $t28277._0;
        {
          const s = $f28298;
          {
            const $p28297 = (() => {
              {
                const $p29061_i10413_i10712_i11001 = (() => {
                  {
                    const $p15619_i10138_i10408_i10707_i10996 = (() => {
                      {
                        const $p15616_i1544_i10128_i10399_i10698_i10987 = Random$next_raw(rng);
                        {
                          const hi_i1545_i10129_i10400_i10699_i10988 = $p15616_i1544_i10128_i10399_i10698_i10987._0;
                          {
                            const rng2_i1546_i10130_i10401_i10700_i10989 = $p15616_i1544_i10128_i10399_i10698_i10987._1;
                            {
                              const $p15615_i1547_i10131_i10402_i10701_i10990 = Random$next_raw(rng2_i1546_i10130_i10401_i10700_i10989);
                              {
                                const lo_i1548_i10132_i10403_i10702_i10991 = $p15615_i1547_i10131_i10402_i10701_i10990._0;
                                {
                                  const rng3_i1549_i10133_i10404_i10703_i10992 = $p15615_i1547_i10131_i10402_i10701_i10990._1;
                                  {
                                    const $t15614_i1553_i10137_i10407_i10706_i10995 = (() => {
                                      {
                                        const $t15613_i1552_i10136_i10406_i10705_i10994 = (() => {
                                          {
                                            const $t15611_i1550_i10134_i10405_i10704_i10993 = march_int_and(hi_i1545_i10129_i10400_i10699_i10988, 1048575);
                                            return ($t15611_i1550_i10134_i10405_i10704_i10993 * 4294967296);
                                          }
                                        })();
                                        return ($t15613_i1552_i10136_i10406_i10705_i10994 + lo_i1548_i10132_i10403_i10702_i10991);
                                      }
                                    })();
                                    return { _0: $t15614_i1553_i10137_i10407_i10706_i10995, _1: rng3_i1549_i10133_i10404_i10703_i10992 };
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    })();
                    {
                      const bits_i10139_i10409_i10708_i10997 = $p15619_i10138_i10408_i10707_i10996._0;
                      {
                        const rng2_i10140_i10410_i10709_i10998 = $p15619_i10138_i10408_i10707_i10996._1;
                        {
                          const $t15618_i10142_i10412_i10711_i11000 = (() => {
                            {
                              const $t15617_i10141_i10411_i10710_i10999 = bits_i10139_i10409_i10708_i10997;
                              return ($t15617_i10141_i10411_i10710_i10999 / 4.50359962737e+15);
                            }
                          })();
                          return { _0: $t15618_i10142_i10412_i10711_i11000, _1: rng2_i10140_i10410_i10709_i10998 };
                        }
                      }
                    }
                  }
                })();
                {
                  const t_i10414_i10713_i11002 = $p29061_i10413_i10712_i11001._0;
                  {
                    const rng2_i10415_i10714_i11003 = $p29061_i10413_i10712_i11001._1;
                    {
                      const out_i10416_i10715_i11004 = { _0: rng2_i10415_i10714_i11003, _1: t_i10414_i10713_i11002 };
                      return out_i10416_i10715_i11004;
                    }
                  }
                }
              }
            })();
            {
              const rng2 = $p28297._0;
              {
                const idle_f = $p28297._1;
                {
                  const r = (() => {
                    {
                      const $t28278 = s.capture_radius;
                      return ($t28278 * 1.6);
                    }
                  })();
                  {
                    const idle = (() => {
                      {
                        const $t28284 = (() => {
                          {
                            const $t28283 = (6. - 3.);
                            return (idle_f * $t28283);
                          }
                        })();
                        return (3. + $t28284);
                      }
                    })();
                    {
                      const ship = (() => {
                        {
                          const $t28288 = (() => {
                            {
                              const $t28285 = s.x;
                              {
                                const $t28287 = (() => {
                                  {
                                    const $t28286 = Math.cos(0.);
                                    return ($t28286 * r);
                                  }
                                })();
                                return ($t28285 + $t28287);
                              }
                            }
                          })();
                          {
                            const $t28292 = (() => {
                              {
                                const $t28289 = s.y;
                                {
                                  const $t28291 = (() => {
                                    {
                                      const $t28290 = Math.sin(0.);
                                      return ($t28290 * r);
                                    }
                                  })();
                                  return ($t28289 + $t28291);
                                }
                              }
                            })();
                            {
                              const $t28293 = { $: "ShipOrbiting", _0: 0. };
                              return ({ star_idx: star_idx, x: $t28288, y: $t28292, mode: $t28293, fire_cooldown: 2.5, idle_timer: idle, hunter: false });
                            }
                          }
                        }
                      })();
                      {
                        const $t28295 = game.ships;
                        {
                          const $t28296 = (() => {
                            return { $: "Cons", _0: ship, _1: $t28295 };
                          })();
                          return ({ ...game, rng: rng2, ships: $t28296 });
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
        const $t28300 = (() => {
          {
            const $t28299 = game.current;
            return ($t28299 > 0);
          }
        })();
        if ($t28300 === true) {
          return (() => {
            {
              const $t28301 = game.current;
              return ($t28301 - 1);
            }
          })();
        } else {
          return 0;
        }
      }
    })();
    {
      const $t28302 = Perihelion$Core$star_at(game, idx);
      switch ($t28302.$) {
        case "None": {
          return ({ ...game, rng: rng });
          break;
        }
        case "Some": {
          const $f28323 = $t28302._0;
          {
            const s = $f28323;
            {
              const $p28322 = (() => {
                {
                  const $p29061_i10413_i10712_i11020 = (() => {
                    {
                      const $p15619_i10138_i10408_i10707_i11015 = (() => {
                        {
                          const $p15616_i1544_i10128_i10399_i10698_i11006 = Random$next_raw(rng);
                          {
                            const hi_i1545_i10129_i10400_i10699_i11007 = $p15616_i1544_i10128_i10399_i10698_i11006._0;
                            {
                              const rng2_i1546_i10130_i10401_i10700_i11008 = $p15616_i1544_i10128_i10399_i10698_i11006._1;
                              {
                                const $p15615_i1547_i10131_i10402_i10701_i11009 = Random$next_raw(rng2_i1546_i10130_i10401_i10700_i11008);
                                {
                                  const lo_i1548_i10132_i10403_i10702_i11010 = $p15615_i1547_i10131_i10402_i10701_i11009._0;
                                  {
                                    const rng3_i1549_i10133_i10404_i10703_i11011 = $p15615_i1547_i10131_i10402_i10701_i11009._1;
                                    {
                                      const $t15614_i1553_i10137_i10407_i10706_i11014 = (() => {
                                        {
                                          const $t15613_i1552_i10136_i10406_i10705_i11013 = (() => {
                                            {
                                              const $t15611_i1550_i10134_i10405_i10704_i11012 = march_int_and(hi_i1545_i10129_i10400_i10699_i11007, 1048575);
                                              return ($t15611_i1550_i10134_i10405_i10704_i11012 * 4294967296);
                                            }
                                          })();
                                          return ($t15613_i1552_i10136_i10406_i10705_i11013 + lo_i1548_i10132_i10403_i10702_i11010);
                                        }
                                      })();
                                      return { _0: $t15614_i1553_i10137_i10407_i10706_i11014, _1: rng3_i1549_i10133_i10404_i10703_i11011 };
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      })();
                      {
                        const bits_i10139_i10409_i10708_i11016 = $p15619_i10138_i10408_i10707_i11015._0;
                        {
                          const rng2_i10140_i10410_i10709_i11017 = $p15619_i10138_i10408_i10707_i11015._1;
                          {
                            const $t15618_i10142_i10412_i10711_i11019 = (() => {
                              {
                                const $t15617_i10141_i10411_i10710_i11018 = bits_i10139_i10409_i10708_i11016;
                                return ($t15617_i10141_i10411_i10710_i11018 / 4.50359962737e+15);
                              }
                            })();
                            return { _0: $t15618_i10142_i10412_i10711_i11019, _1: rng2_i10140_i10410_i10709_i11017 };
                          }
                        }
                      }
                    }
                  })();
                  {
                    const t_i10414_i10713_i11021 = $p29061_i10413_i10712_i11020._0;
                    {
                      const rng2_i10415_i10714_i11022 = $p29061_i10413_i10712_i11020._1;
                      {
                        const out_i10416_i10715_i11023 = { _0: rng2_i10415_i10714_i11022, _1: t_i10414_i10713_i11021 };
                        return out_i10416_i10715_i11023;
                      }
                    }
                  }
                }
              })();
              {
                const rng2 = $p28322._0;
                {
                  const idle_f = $p28322._1;
                  {
                    const r = (() => {
                      {
                        const $t28303 = s.capture_radius;
                        return ($t28303 * 1.6);
                      }
                    })();
                    {
                      const idle = (() => {
                        {
                          const $t28309 = (() => {
                            {
                              const $t28308 = (6. - 3.);
                              return (idle_f * $t28308);
                            }
                          })();
                          return (3. + $t28309);
                        }
                      })();
                      {
                        const ship = (() => {
                          {
                            const $t28313 = (() => {
                              {
                                const $t28310 = s.x;
                                {
                                  const $t28312 = (() => {
                                    {
                                      const $t28311 = Math.cos(0.);
                                      return ($t28311 * r);
                                    }
                                  })();
                                  return ($t28310 + $t28312);
                                }
                              }
                            })();
                            {
                              const $t28317 = (() => {
                                {
                                  const $t28314 = s.y;
                                  {
                                    const $t28316 = (() => {
                                      {
                                        const $t28315 = Math.sin(0.);
                                        return ($t28315 * r);
                                      }
                                    })();
                                    return ($t28314 + $t28316);
                                  }
                                }
                              })();
                              {
                                const $t28318 = { $: "ShipOrbiting", _0: 0. };
                                return ({ star_idx: idx, x: $t28313, y: $t28317, mode: $t28318, fire_cooldown: 2.5, idle_timer: idle, hunter: true });
                              }
                            }
                          }
                        })();
                        {
                          const $t28320 = game.ships;
                          {
                            const $t28321 = (() => {
                              return { $: "Cons", _0: ship, _1: $t28320 };
                            })();
                            return ({ ...game, rng: rng2, ships: $t28321 });
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
    const $t28326 = (() => {
      {
        const $t28324 = game.score;
        return ($t28324 < 4);
      }
    })();
    if ($t28326 === true) {
      return game;
    } else {
      return (() => {
        {
          const $p28338 = (() => {
            {
              const $t28327 = game.rng;
              {
                const $p29061_i10413_i10712_i11058 = (() => {
                  {
                    const $p15619_i10138_i10408_i10707_i11053 = (() => {
                      {
                        const $p15616_i1544_i10128_i10399_i10698_i11044 = Random$next_raw($t28327);
                        {
                          const hi_i1545_i10129_i10400_i10699_i11045 = $p15616_i1544_i10128_i10399_i10698_i11044._0;
                          {
                            const rng2_i1546_i10130_i10401_i10700_i11046 = $p15616_i1544_i10128_i10399_i10698_i11044._1;
                            {
                              const $p15615_i1547_i10131_i10402_i10701_i11047 = Random$next_raw(rng2_i1546_i10130_i10401_i10700_i11046);
                              {
                                const lo_i1548_i10132_i10403_i10702_i11048 = $p15615_i1547_i10131_i10402_i10701_i11047._0;
                                {
                                  const rng3_i1549_i10133_i10404_i10703_i11049 = $p15615_i1547_i10131_i10402_i10701_i11047._1;
                                  {
                                    const $t15614_i1553_i10137_i10407_i10706_i11052 = (() => {
                                      {
                                        const $t15613_i1552_i10136_i10406_i10705_i11051 = (() => {
                                          {
                                            const $t15611_i1550_i10134_i10405_i10704_i11050 = march_int_and(hi_i1545_i10129_i10400_i10699_i11045, 1048575);
                                            return ($t15611_i1550_i10134_i10405_i10704_i11050 * 4294967296);
                                          }
                                        })();
                                        return ($t15613_i1552_i10136_i10406_i10705_i11051 + lo_i1548_i10132_i10403_i10702_i11048);
                                      }
                                    })();
                                    return { _0: $t15614_i1553_i10137_i10407_i10706_i11052, _1: rng3_i1549_i10133_i10404_i10703_i11049 };
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    })();
                    {
                      const bits_i10139_i10409_i10708_i11054 = $p15619_i10138_i10408_i10707_i11053._0;
                      {
                        const rng2_i10140_i10410_i10709_i11055 = $p15619_i10138_i10408_i10707_i11053._1;
                        {
                          const $t15618_i10142_i10412_i10711_i11057 = (() => {
                            {
                              const $t15617_i10141_i10411_i10710_i11056 = bits_i10139_i10409_i10708_i11054;
                              return ($t15617_i10141_i10411_i10710_i11056 / 4.50359962737e+15);
                            }
                          })();
                          return { _0: $t15618_i10142_i10412_i10711_i11057, _1: rng2_i10140_i10410_i10709_i11055 };
                        }
                      }
                    }
                  }
                })();
                {
                  const t_i10414_i10713_i11059 = $p29061_i10413_i10712_i11058._0;
                  {
                    const rng2_i10415_i10714_i11060 = $p29061_i10413_i10712_i11058._1;
                    {
                      const out_i10416_i10715_i11061 = { _0: rng2_i10415_i10714_i11060, _1: t_i10414_i10713_i11059 };
                      return out_i10416_i10715_i11061;
                    }
                  }
                }
              }
            }
          })();
          {
            const rng2 = $p28338._0;
            {
              const roll = $p28338._1;
              {
                const chance_raw = (() => {
                  {
                    const $t28332 = (() => {
                      {
                        const $t28331 = (() => {
                          {
                            const $t28330 = (() => {
                              {
                                const $t28328 = game.score;
                                return ($t28328 - 4);
                              }
                            })();
                            return $t28330;
                          }
                        })();
                        return (0.04 * $t28331);
                      }
                    })();
                    return (0.16 + $t28332);
                  }
                })();
                {
                  const chance = (() => {
                    {
                      const $t28333 = (chance_raw > 0.45);
                      if ($t28333 === true) {
                        return 0.45;
                      } else {
                        return chance_raw;
                      }
                    }
                  })();
                  {
                    const $t28334 = (roll < chance);
                    if ($t28334 === true) {
                      return (() => {
                        {
                          const $p28337 = (() => {
                            {
                              const $p29061_i10413_i10712_i11039 = (() => {
                                {
                                  const $p15619_i10138_i10408_i10707_i11034 = (() => {
                                    {
                                      const $p15616_i1544_i10128_i10399_i10698_i11025 = Random$next_raw(rng2);
                                      {
                                        const hi_i1545_i10129_i10400_i10699_i11026 = $p15616_i1544_i10128_i10399_i10698_i11025._0;
                                        {
                                          const rng2_i1546_i10130_i10401_i10700_i11027 = $p15616_i1544_i10128_i10399_i10698_i11025._1;
                                          {
                                            const $p15615_i1547_i10131_i10402_i10701_i11028 = Random$next_raw(rng2_i1546_i10130_i10401_i10700_i11027);
                                            {
                                              const lo_i1548_i10132_i10403_i10702_i11029 = $p15615_i1547_i10131_i10402_i10701_i11028._0;
                                              {
                                                const rng3_i1549_i10133_i10404_i10703_i11030 = $p15615_i1547_i10131_i10402_i10701_i11028._1;
                                                {
                                                  const $t15614_i1553_i10137_i10407_i10706_i11033 = (() => {
                                                    {
                                                      const $t15613_i1552_i10136_i10406_i10705_i11032 = (() => {
                                                        {
                                                          const $t15611_i1550_i10134_i10405_i10704_i11031 = march_int_and(hi_i1545_i10129_i10400_i10699_i11026, 1048575);
                                                          return ($t15611_i1550_i10134_i10405_i10704_i11031 * 4294967296);
                                                        }
                                                      })();
                                                      return ($t15613_i1552_i10136_i10406_i10705_i11032 + lo_i1548_i10132_i10403_i10702_i11029);
                                                    }
                                                  })();
                                                  return { _0: $t15614_i1553_i10137_i10407_i10706_i11033, _1: rng3_i1549_i10133_i10404_i10703_i11030 };
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const bits_i10139_i10409_i10708_i11035 = $p15619_i10138_i10408_i10707_i11034._0;
                                    {
                                      const rng2_i10140_i10410_i10709_i11036 = $p15619_i10138_i10408_i10707_i11034._1;
                                      {
                                        const $t15618_i10142_i10412_i10711_i11038 = (() => {
                                          {
                                            const $t15617_i10141_i10411_i10710_i11037 = bits_i10139_i10409_i10708_i11035;
                                            return ($t15617_i10141_i10411_i10710_i11037 / 4.50359962737e+15);
                                          }
                                        })();
                                        return { _0: $t15618_i10142_i10412_i10711_i11038, _1: rng2_i10140_i10410_i10709_i11036 };
                                      }
                                    }
                                  }
                                }
                              })();
                              {
                                const t_i10414_i10713_i11040 = $p29061_i10413_i10712_i11039._0;
                                {
                                  const rng2_i10415_i10714_i11041 = $p29061_i10413_i10712_i11039._1;
                                  {
                                    const out_i10416_i10715_i11042 = { _0: rng2_i10415_i10714_i11041, _1: t_i10414_i10713_i11040 };
                                    return out_i10416_i10715_i11042;
                                  }
                                }
                              }
                            }
                          })();
                          {
                            const rng3 = $p28337._0;
                            {
                              const kind_roll = $p28337._1;
                              {
                                const $t28336 = (kind_roll < 0.5);
                                if ($t28336 === true) {
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
    const $t28339 = game.stars;
    return List$nth_opt$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int($t28339, i);
  }
}
const Perihelion$Core$star_at$clo = { _0: ($_, game, i) => Perihelion$Core$star_at(game, i) };

function Perihelion$Core$remove_at(xs, idx) {
  {
    const $t28340 = (() => {
      {
        const go_i3847 = { $: "$Clo_go$4797", _0: go$apply$4797 };
        {
          const $t548_i3848 = { $: "Nil" };
          return go$apply$4797(go_i3847, xs, idx, $t548_i3848);
        }
      }
    })();
    {
      const $t28341 = (idx + 1);
      {
        const $t28342 = List$drop$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int(xs, $t28341);
        {
          const go_i10058 = { $: "$Clo_go$4794", _0: go$apply$4794 };
          {
            const $t301_i10061 = (() => {
              {
                const go_i4500_i10059 = { $: "$Clo_go$5244", _0: go$apply$5244 };
                {
                  const $t293_i4501_i10060 = { $: "Nil" };
                  return go$apply$5244(go_i4500_i10059, $t28340, $t293_i4501_i10060);
                }
              }
            })();
            return go$apply$4794(go_i10058, $t301_i10061, $t28342);
          }
        }
      }
    }
  }
}
const Perihelion$Core$remove_at$clo = { _0: ($_, xs, idx) => Perihelion$Core$remove_at(xs, idx) };

function Perihelion$Core$remove_star(game, idx) {
  {
    const $t28343 = game.stars;
    {
      const $t28344 = (() => {
        return Perihelion$Core$remove_at($t28343, idx);
      })();
      return ({ ...game, stars: $t28344 });
    }
  }
}
const Perihelion$Core$remove_star$clo = { _0: ($_, game, idx) => Perihelion$Core$remove_star(game, idx) };

function Perihelion$Core$ring_count(s) {
  {
    const $t28345 = s.orbits;
    {
      const go_i3850 = { $: "$Clo_go$4799", _0: go$apply$4799 };
      return go$apply$4799(go_i3850, $t28345, 0);
    }
  }
}
const Perihelion$Core$ring_count$clo = { _0: ($_, s) => Perihelion$Core$ring_count(s) };

function Perihelion$Core$ring_at(s, i) {
  {
    const $t28347 = (() => {
      {
        const $t28346 = s.orbits;
        return List$nth_opt$List_R_radius_Float_speed_mult_Float$Int($t28346, i);
      }
    })();
    switch ($t28347.$) {
      case "Some": {
        const $f28350 = $t28347._0;
        {
          const o = $f28350;
          return o;
        }
        break;
      }
      case "None": {
        {
          const $t28348 = s.capture_radius;
          {
            const $t28349 = s.speed_mult;
            return ({ radius: $t28348, speed_mult: $t28349 });
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
        const $t28355 = { $: "$Clo_$lam28352$3740", _0: $lam28352$apply$3740 };
        return List$any$List_String$Fn_String_Bool(keys, $t28355);
      }
    })();
    {
      const inn = (() => {
        {
          const $t28359 = { $: "$Clo_$lam28356$3741", _0: $lam28356$apply$3741 };
          return List$any$List_String$Fn_String_Bool(keys, $t28359);
        }
      })();
      {
        const delta = (() => {
          {
            let $t28360;
            if (out === true) {
              $t28360 = 1;
            } else {
              $t28360 = 0;
            }
            {
              let $t28361;
              if (inn === true) {
                $t28361 = 1;
              } else {
                $t28361 = 0;
              }
              return ($t28360 - $t28361);
            }
          }
        })();
        {
          const target = (ring_idx + delta);
          {
            const $t28362 = (target < 0);
            if ($t28362 === true) {
              return 0;
            } else {
              return (() => {
                {
                  const $t28364 = (() => {
                    {
                      const $t28363 = (n - 1);
                      return (target > $t28363);
                    }
                  })();
                  if ($t28364 === true) {
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
        const $t28365 = game.owned_weapons;
        {
          const go_i3854 = { $: "$Clo_go$4803", _0: go$apply$4803 };
          return go$apply$4803(go_i3854, $t28365, 0);
        }
      }
    })();
    {
      const idx = (() => {
        {
          const $t28367 = (() => {
            {
              const $t28366 = game.active_weapon_idx;
              return ($t28366 >= n);
            }
          })();
          if ($t28367 === true) {
            return 0;
          } else {
            return game.active_weapon_idx;
          }
        }
      })();
      {
        const $t28369 = (() => {
          {
            const $t28368 = game.owned_weapons;
            return List$nth_opt$List_WeaponKind$Int($t28368, idx);
          }
        })();
        switch ($t28369.$) {
          case "Some": {
            const $f28370 = $t28369._0;
            {
              const w = $f28370;
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
        const $t28374 = { $: "$Clo_$lam28371$3742", _0: $lam28371$apply$3742 };
        return List$any$List_String$Fn_String_Bool(keys, $t28374);
      }
    })();
    {
      const prev = (() => {
        {
          const $t28378 = { $: "$Clo_$lam28375$3743", _0: $lam28375$apply$3743 };
          return List$any$List_String$Fn_String_Bool(keys, $t28378);
        }
      })();
      {
        const delta = (() => {
          {
            let $t28379;
            if (next === true) {
              $t28379 = 1;
            } else {
              $t28379 = 0;
            }
            {
              let $t28380;
              if (prev === true) {
                $t28380 = 1;
              } else {
                $t28380 = 0;
              }
              return ($t28379 - $t28380);
            }
          }
        })();
        {
          const raw = (() => {
            {
              const $t28381 = (idx + delta);
              return march_int_mod($t28381, n);
            }
          })();
          {
            const $t28382 = (raw < 0);
            if ($t28382 === true) {
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
        const $t28386 = { $: "$Clo_$lam28383$3744", _0: $lam28383$apply$3744 };
        return List$any$List_String$Fn_String_Bool(keys, $t28386);
      }
    })();
    {
      const up = (() => {
        {
          const $t28390 = { $: "$Clo_$lam28387$3745", _0: $lam28387$apply$3745 };
          return List$any$List_String$Fn_String_Bool(keys, $t28390);
        }
      })();
      {
        const delta = (() => {
          {
            let $t28391;
            if (dn === true) {
              $t28391 = 1;
            } else {
              $t28391 = 0;
            }
            {
              let $t28392;
              if (up === true) {
                $t28392 = 1;
              } else {
                $t28392 = 0;
              }
              return ($t28391 - $t28392);
            }
          }
        })();
        {
          const $t28394 = (() => {
            {
              const $t28393 = (offset + delta);
              return ($t28393 + 3);
            }
          })();
          return march_int_mod($t28394, 3);
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
            const $t28397 = best.x;
            {
              const $t28398 = game.ball_x;
              return ($t28397 - $t28398);
            }
          }
        })();
        {
          const dy = (() => {
            {
              const $t28399 = best.y;
              {
                const $t28400 = game.ball_y;
                return ($t28399 - $t28400);
              }
            }
          })();
          {
            const d = Math.sqrt(best_d2);
            {
              const $t28401 = (d > 0.);
              if ($t28401 === true) {
                return (() => {
                  {
                    const $t28402 = (dx / d);
                    {
                      const $t28403 = (dy / d);
                      {
                        const $t28404 = { _0: $t28402, _1: $t28403 };
                        return { $: "Some", _0: $t28404 };
                      }
                    }
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
      const $f28410 = stars._0;
      const $f28411 = stars._1;
      {
        const rest = (() => {
          return $f28411;
        })();
        {
          const s = (() => {
            return $f28410;
          })();
          {
            const d2 = (() => {
              {
                const $t28405 = game.ball_x;
                {
                  const $t28406 = game.ball_y;
                  {
                    const $t28407 = s.x;
                    {
                      const $t28408 = s.y;
                      {
                        const dx_i3861 = ($t28405 - $t28407);
                        {
                          const dy_i3862 = ($t28406 - $t28408);
                          {
                            const $t28395_i3863 = (dx_i3861 * dx_i3861);
                            {
                              const $t28396_i3864 = (dy_i3862 * dy_i3862);
                              return ($t28395_i3863 + $t28396_i3864);
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
              const $t28409 = (d2 < best_d2);
              if ($t28409 === true) {
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
    const $t28416 = game.stars;
    switch ($t28416.$) {
      case "Nil": {
        return { $: "None" };
        break;
      }
      case "Cons": {
        const $f28422 = $t28416._0;
        const $f28423 = $t28416._1;
        {
          const rest = (() => {
            return $f28423;
          })();
          {
            const s0 = (() => {
              return $f28422;
            })();
            {
              const $t28421 = (() => {
                {
                  const $t28417 = game.ball_x;
                  {
                    const $t28418 = game.ball_y;
                    {
                      const $t28419 = s0.x;
                      {
                        const $t28420 = s0.y;
                        {
                          const dx_i3870 = ($t28417 - $t28419);
                          {
                            const dy_i3871 = ($t28418 - $t28420);
                            {
                              const $t28395_i3872 = (dx_i3870 * dx_i3870);
                              {
                                const $t28396_i3873 = (dy_i3871 * dy_i3871);
                                return ($t28395_i3872 + $t28396_i3873);
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
                const $rc_828 = Perihelion$Core$nearest_star_dir_go(game, rest, s0, $t28421);
                return $rc_828;
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
    const $p28439 = (() => {
      {
        const $t28428 = game.rng;
        {
          const $p29061_i10413_i10731 = (() => {
            {
              const $p15619_i10138_i10408_i10726 = (() => {
                {
                  const $p15616_i1544_i10128_i10399_i10717 = Random$next_raw($t28428);
                  {
                    const hi_i1545_i10129_i10400_i10718 = $p15616_i1544_i10128_i10399_i10717._0;
                    {
                      const rng2_i1546_i10130_i10401_i10719 = $p15616_i1544_i10128_i10399_i10717._1;
                      {
                        const $p15615_i1547_i10131_i10402_i10720 = Random$next_raw(rng2_i1546_i10130_i10401_i10719);
                        {
                          const lo_i1548_i10132_i10403_i10721 = $p15615_i1547_i10131_i10402_i10720._0;
                          {
                            const rng3_i1549_i10133_i10404_i10722 = $p15615_i1547_i10131_i10402_i10720._1;
                            {
                              const $t15614_i1553_i10137_i10407_i10725 = (() => {
                                {
                                  const $t15613_i1552_i10136_i10406_i10724 = (() => {
                                    {
                                      const $t15611_i1550_i10134_i10405_i10723 = march_int_and(hi_i1545_i10129_i10400_i10718, 1048575);
                                      return ($t15611_i1550_i10134_i10405_i10723 * 4294967296);
                                    }
                                  })();
                                  return ($t15613_i1552_i10136_i10406_i10724 + lo_i1548_i10132_i10403_i10721);
                                }
                              })();
                              return { _0: $t15614_i1553_i10137_i10407_i10725, _1: rng3_i1549_i10133_i10404_i10722 };
                            }
                          }
                        }
                      }
                    }
                  }
                }
              })();
              {
                const bits_i10139_i10409_i10727 = $p15619_i10138_i10408_i10726._0;
                {
                  const rng2_i10140_i10410_i10728 = $p15619_i10138_i10408_i10726._1;
                  {
                    const $t15618_i10142_i10412_i10730 = (() => {
                      {
                        const $t15617_i10141_i10411_i10729 = bits_i10139_i10409_i10727;
                        return ($t15617_i10141_i10411_i10729 / 4.50359962737e+15);
                      }
                    })();
                    return { _0: $t15618_i10142_i10412_i10730, _1: rng2_i10140_i10410_i10728 };
                  }
                }
              }
            }
          })();
          {
            const t_i10414_i10732 = $p29061_i10413_i10731._0;
            {
              const rng2_i10415_i10733 = $p29061_i10413_i10731._1;
              {
                const out_i10416_i10734 = { _0: rng2_i10415_i10733, _1: t_i10414_i10732 };
                return out_i10416_i10734;
              }
            }
          }
        }
      }
    })();
    {
      const rng2 = $p28439._0;
      {
        const t = $p28439._1;
        {
          const jump = (() => {
            {
              const $t28432 = (() => {
                {
                  const $t28431 = (t * 4.);
                  return Math.trunc($t28431);
                }
              })();
              return (1 + $t28432);
            }
          })();
          {
            const target_idx = (() => {
              {
                const $t28433 = game.current;
                return ($t28433 + jump);
              }
            })();
            {
              const $t28434 = Perihelion$Core$star_at(game, target_idx);
              switch ($t28434.$) {
                case "None": {
                  return ({ ...game, rng: rng2 });
                  break;
                }
                case "Some": {
                  const $f28438 = $t28434._0;
                  {
                    const target = $f28438;
                    {
                      const $t28437 = (() => {
                        {
                          const $t28436 = (() => {
                            {
                              const $t28435 = game.special_charges;
                              return ($t28435 - 1);
                            }
                          })();
                          return ({ ...game, rng: rng2, special_charges: $t28436 });
                        }
                      })();
                      return Perihelion$Core$on_capture($t28437, target, target_idx);
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
        const $t28443 = { $: "$Clo_$lam28440$3748", _0: $lam28440$apply$3748 };
        return List$any$List_String$Fn_String_Bool(keys, $t28443);
      }
    })();
    {
      const $t28447 = (() => {
        {
          const $t28444 = (!pressed);
          {
            const $t28446 = (() => {
              {
                const $t28445 = game.special_charges;
                return ($t28445 <= 0);
              }
            })();
            return ($t28444 || $t28446);
          }
        }
      })();
      if ($t28447 === true) {
        return game;
      } else {
        return (() => {
          {
            const $t28448 = game.special;
            switch ($t28448.$) {
              case "None": {
                return game;
                break;
              }
              case "Some": {
                const $f28479 = $t28448._0;
                switch ($f28479.$) {
                  case "StarThrust": {
                    {
                      const $t28449 = Perihelion$Core$nearest_star_dir(game);
                      switch ($t28449.$) {
                        case "None": {
                          return game;
                          break;
                        }
                        case "Some": {
                          const $f28478 = $t28449._0;
                          {
                            const pair = $f28478;
                            {
                              const dx = pair._0;
                              {
                                const dy = pair._1;
                                {
                                  const $t28450 = game.mode;
                                  switch ($t28450.$) {
                                    case "Flying": {
                                      const $f28460 = $t28450._0;
                                      const $f28461 = $t28450._1;
                                      {
                                        const vy = (() => {
                                          return $f28461;
                                        })();
                                        {
                                          const vx = (() => {
                                            return $f28460;
                                          })();
                                          {
                                            const $t28457 = (() => {
                                              {
                                                const $t28453 = (() => {
                                                  {
                                                    const $t28452 = (dx * 60.);
                                                    return (vx + $t28452);
                                                  }
                                                })();
                                                {
                                                  const $t28456 = (() => {
                                                    {
                                                      const $t28455 = (dy * 60.);
                                                      return (vy + $t28455);
                                                    }
                                                  })();
                                                  return { $: "Flying", _0: $t28453, _1: $t28456 };
                                                }
                                              }
                                            })();
                                            {
                                              const $t28459 = (() => {
                                                {
                                                  const $t28458 = game.special_charges;
                                                  return ($t28458 - 1);
                                                }
                                              })();
                                              return ({ ...game, mode: $t28457, special_charges: $t28459 });
                                            }
                                          }
                                        }
                                      }
                                      break;
                                    }
                                    case "Orbiting": {
                                      const $f28466 = $t28450._0;
                                      const $f28467 = $t28450._1;
                                      const $f28468 = $t28450._2;
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
        const $t28484 = { $: "Nil" };
        {
          const $t28485 = { $: "None" };
          return ({ ...game, view_w: view_w, view_h: view_h, fx_bursts: $t28484, capture_flash: $t28485 });
        }
      }
    })();
    {
      const $t28486 = (() => {
        {
          const $t28483_i3883 = { $: "$Clo_$lam28480$3753", _0: $lam28480$apply$3753 };
          return List$any$List_String$Fn_String_Bool(keys, $t28483_i3883);
        }
      })();
      if ($t28486 === true) {
        return Perihelion$Core$reset(g0);
      } else {
        return (() => {
          {
            const tapped = (() => {
              {
                let $t28487;
                switch (taps.$) {
                  case "Nil": {
                    $t28487 = true;
                    break;
                  }
                  default: {
                    $t28487 = false;
                    break;
                  }
                }
                return (!$t28487);
              }
            })();
            {
              const $t28488 = g0.phase;
              switch ($t28488.$) {
                case "Ready": {
                  if (tapped === true) {
                    return (() => {
                      {
                        const $t28489 = { $: "Playing" };
                        return ({ ...g0, phase: $t28489 });
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
                        const $t28491 = (() => {
                          {
                            const $t28490 = g0.milestone_choices;
                            return List$nth_opt$List_UpgradeKind$Int($t28490, 0);
                          }
                        })();
                        switch ($t28491.$) {
                          case "None": {
                            return g0;
                            break;
                          }
                          case "Some": {
                            const $f28496 = $t28491._0;
                            {
                              const choice = $f28496;
                              {
                                const $t28495 = (() => {
                                  {
                                    const $t28492 = Perihelion$Core$apply_upgrade(g0, choice);
                                    {
                                      const $t28493 = { $: "Playing" };
                                      {
                                        const $t28494 = { $: "Nil" };
                                        return ({ ...$t28492, phase: $t28493, milestone_choices: $t28494 });
                                      }
                                    }
                                  }
                                })();
                                return Perihelion$Core$top_up($t28495);
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
        const $t28497 = game.mode;
        switch ($t28497.$) {
          case "Orbiting": {
            const $f28498 = $t28497._0;
            const $f28499 = $t28497._1;
            const $f28500 = $t28497._2;
            {
              const angle = (() => {
                return $f28500;
              })();
              {
                const ring = (() => {
                  return $f28499;
                })();
                {
                  const idx = (() => {
                    return $f28498;
                  })();
                  return Perihelion$Core$step_orbit(game, idx, ring, angle, tapped, keys, dt_s);
                }
              }
            }
            break;
          }
          case "Flying": {
            const $f28509 = $t28497._0;
            const $f28510 = $t28497._1;
            {
              const vy = (() => {
                return $f28510;
              })();
              {
                const vx = (() => {
                  return $f28509;
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
          const $t28515 = g0.owned_weapons;
          {
            const go_i3894 = { $: "$Clo_go$4803", _0: go$apply$4803 };
            return go$apply$4803(go_i3894, $t28515, 0);
          }
        }
      })();
      {
        const g1a = (() => {
          {
            const $t28517 = (() => {
              {
                const $t28516 = g0.active_weapon_idx;
                return Perihelion$Core$adjust_weapon($t28516, keys, n);
              }
            })();
            return ({ ...g0, active_weapon_idx: $t28517 });
          }
        })();
        {
          const g1 = (() => {
            {
              const $t28519 = (() => {
                {
                  const $t28518 = g1a.starkiller_target_offset;
                  return Perihelion$Core$adjust_starkiller_target($t28518, keys);
                }
              })();
              return ({ ...g1a, starkiller_target_offset: $t28519 });
            }
          })();
          {
            const g1x = (() => {
              return Perihelion$Core$apply_special(g1, keys);
            })();
            {
              const $t28520 = g1x.phase;
              switch ($t28520.$) {
                case "Playing": {
                  {
                    const g2 = (() => {
                      {
                        const g1_i3891 = Perihelion$Combat$step_spawn(g1x, dt_s);
                        {
                          const g2_i3892 = Perihelion$Combat$step_entities(g1_i3891, dt_s);
                          return Perihelion$Combat$step_ships(g2_i3892, dt_s);
                        }
                      }
                    })();
                    {
                      const g3 = Perihelion$Combat$fire(g2, keys, cursor, dt_s);
                      {
                        const g4 = (() => {
                          {
                            const g0_i3885 = Perihelion$Combat$collide_shots_stars(g3);
                            {
                              const g1_i3886 = Perihelion$Combat$collide_shots_asteroids(g0_i3885);
                              {
                                const g2_i3887 = Perihelion$Combat$collide_shots_ships(g1_i3886);
                                {
                                  const g3_i3888 = Perihelion$Combat$collide_ball_pickups(g2_i3887);
                                  return Perihelion$Combat$collide_ball_hazards(g3_i3888);
                                }
                              }
                            }
                          }
                        })();
                        {
                          const $t28521 = (() => {
                            return g4.phase;
                          })();
                          switch ($t28521.$) {
                            case "Playing": {
                              {
                                const $t28522 = (() => {
                                  {
                                    const $rc_829 = Perihelion$Core$step_camera(g4, dt_s);
                                    return $rc_829;
                                  }
                                })();
                                return Perihelion$Core$top_up($t28522);
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
    const $t28523 = Perihelion$Core$star_at(game, idx);
    switch ($t28523.$) {
      case "None": {
        return game;
        break;
      }
      case "Some": {
        const $f28546 = $t28523._0;
        {
          const s = $f28546;
          if (tapped === true) {
            return (() => {
              {
                const vx_i10069 = (() => {
                  {
                    const $t28550_i10068 = (() => {
                      {
                        const $t28548_i10066 = (1. * 340.);
                        {
                          const $t28549_i10067 = Math.sin(angle);
                          return ($t28548_i10066 * $t28549_i10067);
                        }
                      }
                    })();
                    return (0. - $t28550_i10068);
                  }
                })();
                {
                  const vy_i10072 = (() => {
                    {
                      const $t28552_i10070 = (1. * 340.);
                      {
                        const $t28553_i10071 = Math.cos(angle);
                        return ($t28552_i10070 * $t28553_i10071);
                      }
                    }
                  })();
                  {
                    const $t28554_i10073 = { $: "Flying", _0: vx_i10069, _1: vy_i10072 };
                    return ({ ...game, mode: $t28554_i10073 });
                  }
                }
              }
            })();
          } else {
            return (() => {
              {
                const ring2 = (() => {
                  {
                    const $t28524 = Perihelion$Core$ring_count(s);
                    return Perihelion$Core$adjust_ring(ring, keys, $t28524);
                  }
                })();
                {
                  const o = Perihelion$Core$ring_at(s, ring2);
                  {
                    const a2 = (() => {
                      {
                        const $t28530 = (() => {
                          {
                            const $t28529 = (() => {
                              {
                                const $t28527 = (1. * 1.8);
                                {
                                  const $t28528 = o.speed_mult;
                                  return ($t28527 * $t28528);
                                }
                              }
                            })();
                            return ($t28529 * dt_s);
                          }
                        })();
                        return (angle + $t28530);
                      }
                    })();
                    {
                      const r = o.radius;
                      {
                        const $t28531 = { $: "Orbiting", _0: idx, _1: ring2, _2: a2 };
                        {
                          const $t28537 = (() => {
                            {
                              const $t28532 = game.loop_angle;
                              {
                                const $t28536 = (() => {
                                  {
                                    const $t28535 = (() => {
                                      {
                                        const $t28534 = o.speed_mult;
                                        return (1.8 * $t28534);
                                      }
                                    })();
                                    return ($t28535 * dt_s);
                                  }
                                })();
                                return ($t28532 + $t28536);
                              }
                            }
                          })();
                          {
                            const $t28541 = (() => {
                              {
                                const $t28538 = s.x;
                                {
                                  const $t28540 = (() => {
                                    {
                                      const $t28539 = Math.cos(a2);
                                      return ($t28539 * r);
                                    }
                                  })();
                                  return ($t28538 + $t28540);
                                }
                              }
                            })();
                            {
                              const $t28545 = (() => {
                                {
                                  const $t28542 = s.y;
                                  {
                                    const $t28544 = (() => {
                                      {
                                        const $t28543 = Math.sin(a2);
                                        return ($t28543 * r);
                                      }
                                    })();
                                    return ($t28542 + $t28544);
                                  }
                                }
                              })();
                              return ({ ...game, mode: $t28531, loop_angle: $t28537, ball_x: $t28541, ball_y: $t28545 });
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
        const $t28557 = (() => {
          {
            const $t28555 = (vx * vx);
            {
              const $t28556 = (vy * vy);
              return ($t28555 + $t28556);
            }
          }
        })();
        return Math.sqrt($t28557);
      }
    })();
    {
      const $t28558 = (m > 0.);
      if ($t28558 === true) {
        return (() => {
          {
            const out = (() => {
              {
                const $t28561 = (() => {
                  {
                    const $t28559 = (vx / m);
                    return ($t28559 * 340.);
                  }
                })();
                {
                  const $t28564 = (() => {
                    {
                      const $t28562 = (vy / m);
                      return ($t28562 * 340.);
                    }
                  })();
                  return { _0: $t28561, _1: $t28564 };
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
      const $f28583 = stars._0;
      const $f28584 = stars._1;
      {
        const rest = $f28584;
        {
          const s = $f28583;
          {
            const dx = (() => {
              {
                const $t28565 = s.x;
                {
                  const $t28566 = game.ball_x;
                  return ($t28565 - $t28566);
                }
              }
            })();
            {
              const dy = (() => {
                {
                  const $t28567 = s.y;
                  {
                    const $t28568 = game.ball_y;
                    return ($t28567 - $t28568);
                  }
                }
              })();
              {
                const d = (() => {
                  {
                    const $t28571 = (() => {
                      {
                        const $t28569 = (dx * dx);
                        {
                          const $t28570 = (dy * dy);
                          return ($t28569 + $t28570);
                        }
                      }
                    })();
                    return Math.sqrt($t28571);
                  }
                })();
                {
                  const approaching = (() => {
                    {
                      const $t28574 = (() => {
                        {
                          const $t28572 = (vx * dx);
                          {
                            const $t28573 = (vy * dy);
                            return ($t28572 + $t28573);
                          }
                        }
                      })();
                      return ($t28574 > 0.);
                    }
                  })();
                  {
                    const $t28581 = (() => {
                      {
                        const $t28579 = (() => {
                          {
                            const $t28578 = (() => {
                              {
                                const $t28577 = (() => {
                                  {
                                    const $t28576 = s.capture_radius;
                                    return (2.4 * $t28576);
                                  }
                                })();
                                return (d < $t28577);
                              }
                            })();
                            return (approaching && $t28578);
                          }
                        })();
                        {
                          const $t28580 = (d < best_d);
                          return ($t28579 && $t28580);
                        }
                      }
                    })();
                    if ($t28581 === true) {
                      return (() => {
                        {
                          const $t28582 = { $: "Some", _0: s };
                          return Perihelion$Core$nearest_assist_target(game, vx, vy, rest, $t28582, d);
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
    const $t28591 = (() => {
      {
        const $t28589 = game.stars;
        {
          const $t28590 = { $: "None" };
          return Perihelion$Core$nearest_assist_target(game, vx, vy, $t28589, $t28590, 999999.);
        }
      }
    })();
    switch ($t28591.$) {
      case "None": {
        {
          const out = { _0: vx, _1: vy };
          return out;
        }
        break;
      }
      case "Some": {
        const $f28610 = $t28591._0;
        {
          const t = $f28610;
          {
            const dx = (() => {
              {
                const $t28592 = t.x;
                {
                  const $t28593 = game.ball_x;
                  return ($t28592 - $t28593);
                }
              }
            })();
            {
              const dy = (() => {
                {
                  const $t28594 = t.y;
                  {
                    const $t28595 = game.ball_y;
                    return ($t28594 - $t28595);
                  }
                }
              })();
              {
                const dist = (() => {
                  {
                    const $t28598 = (() => {
                      {
                        const $t28596 = (dx * dx);
                        {
                          const $t28597 = (dy * dy);
                          return ($t28596 + $t28597);
                        }
                      }
                    })();
                    return Math.sqrt($t28598);
                  }
                })();
                {
                  const $t28599 = (dist > 0.);
                  if ($t28599 === true) {
                    return (() => {
                      {
                        const $t28604 = (() => {
                          {
                            const $t28603 = (() => {
                              {
                                const $t28602 = (() => {
                                  {
                                    const $t28600 = (dx / dist);
                                    return ($t28600 * 1600.);
                                  }
                                })();
                                return ($t28602 * dt_s);
                              }
                            })();
                            return (vx + $t28603);
                          }
                        })();
                        {
                          const $t28609 = (() => {
                            {
                              const $t28608 = (() => {
                                {
                                  const $t28607 = (() => {
                                    {
                                      const $t28605 = (dy / dist);
                                      return ($t28605 * 1600.);
                                    }
                                  })();
                                  return ($t28607 * dt_s);
                                }
                              })();
                              return (vy + $t28608);
                            }
                          })();
                          return Perihelion$Core$renormalize($t28604, $t28609);
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
    const $t28611 = (n === 0);
    if ($t28611 === true) {
      return (() => {
        {
          const go_i3909 = { $: "$Clo_go$4319", _0: go$apply$4319 };
          {
            const $t293_i3910 = { $: "Nil" };
            return go$apply$4319(go_i3909, acc, $t293_i3910);
          }
        }
      })();
    } else {
      return (() => {
        {
          const simmed = ({ ...game, ball_x: x, ball_y: y });
          {
            const $p28620 = Perihelion$Core$assisted_velocity(simmed, vx, vy, 0.05);
            {
              const vx2 = $p28620._0;
              {
                const vy2 = $p28620._1;
                {
                  const x2 = (() => {
                    {
                      const $t28614 = (vx2 * 0.05);
                      return (x + $t28614);
                    }
                  })();
                  {
                    const y2 = (() => {
                      {
                        const $t28616 = (vy2 * 0.05);
                        return (y + $t28616);
                      }
                    })();
                    {
                      const $t28617 = (n - 1);
                      {
                        const $t28618 = { _0: x2, _1: y2 };
                        {
                          const $t28619 = { $: "Cons", _0: $t28618, _1: acc };
                          return Perihelion$Core$predict_trajectory_go(game, x2, y2, vx2, vy2, $t28617, $t28619);
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
    const $t28621 = Perihelion$Core$star_at(game, idx);
    switch ($t28621.$) {
      case "None": {
        return { $: "Nil" };
        break;
      }
      case "Some": {
        const $f28651 = $t28621._0;
        {
          const s = $f28651;
          {
            const o = Perihelion$Core$ring_at(s, ring);
            {
              const start_x = (() => {
                {
                  const $t28622 = s.x;
                  {
                    const $t28625 = (() => {
                      {
                        const $t28623 = Math.cos(angle);
                        {
                          const $t28624 = o.radius;
                          return ($t28623 * $t28624);
                        }
                      }
                    })();
                    return ($t28622 + $t28625);
                  }
                }
              })();
              {
                const start_y = (() => {
                  {
                    const $t28626 = s.y;
                    {
                      const $t28629 = (() => {
                        {
                          const $t28627 = Math.sin(angle);
                          {
                            const $t28628 = o.radius;
                            return ($t28627 * $t28628);
                          }
                        }
                      })();
                      return ($t28626 + $t28629);
                    }
                  }
                })();
                {
                  const $t28631 = (() => {
                    {
                      const $t28630 = (() => {
                        {
                          const vx_i10081 = (() => {
                            {
                              const $t28550_i10080 = (() => {
                                {
                                  const $t28548_i10078 = (1. * 340.);
                                  {
                                    const $t28549_i10079 = Math.sin(angle);
                                    return ($t28548_i10078 * $t28549_i10079);
                                  }
                                }
                              })();
                              return (0. - $t28550_i10080);
                            }
                          })();
                          {
                            const vy_i10084 = (() => {
                              {
                                const $t28552_i10082 = (1. * 340.);
                                {
                                  const $t28553_i10083 = Math.cos(angle);
                                  return ($t28552_i10082 * $t28553_i10083);
                                }
                              }
                            })();
                            {
                              const $t28554_i10085 = { $: "Flying", _0: vx_i10081, _1: vy_i10084 };
                              return ({ ...game, mode: $t28554_i10085 });
                            }
                          }
                        }
                      })();
                      return $t28630.mode;
                    }
                  })();
                  switch ($t28631.$) {
                    case "Flying": {
                      const $f28634 = $t28631._0;
                      const $f28635 = $t28631._1;
                      {
                        const vy0 = $f28635;
                        {
                          const vx0 = $f28634;
                          {
                            const $t28633 = { $: "Nil" };
                            return Perihelion$Core$predict_trajectory_go(game, start_x, start_y, vx0, vy0, 24, $t28633);
                          }
                        }
                      }
                      break;
                    }
                    case "Orbiting": {
                      const $f28640 = $t28631._0;
                      const $f28641 = $t28631._1;
                      const $f28642 = $t28631._2;
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
      const $f28672 = stars._0;
      const $f28673 = stars._1;
      {
        const rest = $f28673;
        {
          const s = $f28672;
          {
            const dx = (() => {
              {
                const $t28652 = s.x;
                {
                  const $t28653 = game.ball_x;
                  return ($t28652 - $t28653);
                }
              }
            })();
            {
              const dy = (() => {
                {
                  const $t28654 = s.y;
                  {
                    const $t28655 = game.ball_y;
                    return ($t28654 - $t28655);
                  }
                }
              })();
              {
                const grace = (() => {
                  {
                    const $t28656 = s.capture_radius;
                    return ($t28656 + 6.);
                  }
                })();
                {
                  const approaching = (() => {
                    {
                      const $t28660 = (() => {
                        {
                          const $t28658 = (vx * dx);
                          {
                            const $t28659 = (vy * dy);
                            return ($t28658 + $t28659);
                          }
                        }
                      })();
                      return ($t28660 > 0.);
                    }
                  })();
                  {
                    const $t28669 = (() => {
                      {
                        const $t28663 = (() => {
                          {
                            const $t28662 = (() => {
                              {
                                const $t28661 = game.current;
                                return (i !== $t28661);
                              }
                            })();
                            return ($t28662 && approaching);
                          }
                        })();
                        {
                          const $t28668 = (() => {
                            {
                              const $t28667 = (() => {
                                {
                                  const $t28666 = (() => {
                                    {
                                      const $t28664 = (dx * dx);
                                      {
                                        const $t28665 = (dy * dy);
                                        return ($t28664 + $t28665);
                                      }
                                    }
                                  })();
                                  return Math.sqrt($t28666);
                                }
                              })();
                              return ($t28667 <= grace);
                            }
                          })();
                          return ($t28663 && $t28668);
                        }
                      }
                    })();
                    if ($t28669 === true) {
                      return (() => {
                        {
                          const $t28670 = { _0: i, _1: s };
                          return { $: "Some", _0: $t28670 };
                        }
                      })();
                    } else {
                      return (() => {
                        {
                          const $t28671 = (i + 1);
                          return Perihelion$Core$find_capture(game, vx, vy, rest, $t28671);
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
    const $p28694 = Perihelion$Core$assisted_velocity(game, vx, vy, dt_s);
    {
      const vx2 = $p28694._0;
      {
        const vy2 = $p28694._1;
        {
          const g = (() => {
            {
              const $t28680 = (() => {
                {
                  const $t28678 = game.ball_x;
                  {
                    const $t28679 = (vx2 * dt_s);
                    return ($t28678 + $t28679);
                  }
                }
              })();
              {
                const $t28683 = (() => {
                  {
                    const $t28681 = game.ball_y;
                    {
                      const $t28682 = (vy2 * dt_s);
                      return ($t28681 + $t28682);
                    }
                  }
                })();
                {
                  const $t28684 = { $: "Flying", _0: vx2, _1: vy2 };
                  return ({ ...game, ball_x: $t28680, ball_y: $t28683, mode: $t28684 });
                }
              }
            }
          })();
          {
            const $t28686 = (() => {
              {
                const $t28685 = g.stars;
                return Perihelion$Core$find_capture(g, vx2, vy2, $t28685, 0);
              }
            })();
            switch ($t28686.$) {
              case "None": {
                return Perihelion$Core$check_death(g);
                break;
              }
              case "Some": {
                const $f28687 = $t28686._0;
                const $f28688 = $f28687._0;
                const $f28689 = $f28687._1;
                {
                  const t = $f28689;
                  {
                    const idx = $f28688;
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
        const $t28697 = (() => {
          {
            const $t28695 = game.ball_y;
            {
              const $t28696 = captured.y;
              return ($t28695 - $t28696);
            }
          }
        })();
        {
          const $t28700 = (() => {
            {
              const $t28698 = game.ball_x;
              {
                const $t28699 = captured.x;
                return ($t28698 - $t28699);
              }
            }
          })();
          return Math.atan2($t28697, $t28700);
        }
      }
    })();
    {
      const snapped = (() => {
        {
          const $t28702 = (() => {
            {
              const $t28701 = (() => {
                {
                  const $t28351_i3925 = Perihelion$Core$ring_count(captured);
                  return ($t28351_i3925 - 1);
                }
              })();
              return { $: "Orbiting", _0: idx, _1: $t28701, _2: angle };
            }
          })();
          {
            const $t28707 = (() => {
              {
                const $t28703 = captured.x;
                {
                  const $t28706 = (() => {
                    {
                      const $t28704 = Math.cos(angle);
                      {
                        const $t28705 = captured.capture_radius;
                        return ($t28704 * $t28705);
                      }
                    }
                  })();
                  return ($t28703 + $t28706);
                }
              }
            })();
            {
              const $t28712 = (() => {
                {
                  const $t28708 = captured.y;
                  {
                    const $t28711 = (() => {
                      {
                        const $t28709 = Math.sin(angle);
                        {
                          const $t28710 = captured.capture_radius;
                          return ($t28709 * $t28710);
                        }
                      }
                    })();
                    return ($t28708 + $t28711);
                  }
                }
              })();
              return ({ ...game, mode: $t28702, loop_angle: 0., ball_x: $t28707, ball_y: $t28712 });
            }
          }
        }
      })();
      {
        const $t28714 = (() => {
          {
            const $t28713 = game.current;
            return (idx > $t28713);
          }
        })();
        if ($t28714 === true) {
          return (() => {
            {
              const new_mult = (() => {
                {
                  const $t28717 = (() => {
                    {
                      const $t28715 = game.loop_angle;
                      return ($t28715 < 6.28318530718);
                    }
                  })();
                  if ($t28717 === true) {
                    return (() => {
                      {
                        const $t28721 = (() => {
                          {
                            const $t28719 = (() => {
                              {
                                const $t28718 = game.multiplier;
                                return ($t28718 + 1);
                              }
                            })();
                            return ($t28719 > 5);
                          }
                        })();
                        if ($t28721 === true) {
                          return 5;
                        } else {
                          return (() => {
                            {
                              const $t28722 = game.multiplier;
                              return ($t28722 + 1);
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
                    const $t28723 = game.stars_chained;
                    return ($t28723 + 1);
                  }
                })();
                {
                  const captured_game = (() => {
                    {
                      const $t28725 = (() => {
                        {
                          const $t28724 = game.score;
                          return ($t28724 + new_mult);
                        }
                      })();
                      {
                        const $t28727 = (() => {
                          {
                            const $t28726 = game.max_mult;
                            {
                              const $t28797_i3921 = ($t28726 > new_mult);
                              if ($t28797_i3921 === true) {
                                return $t28726;
                              } else {
                                return new_mult;
                              }
                            }
                          }
                        })();
                        {
                          const $t28731 = (() => {
                            {
                              const $t28728 = captured.x;
                              {
                                const $t28729 = captured.y;
                                {
                                  const $t28730 = { _0: $t28728, _1: $t28729 };
                                  return { $: "Some", _0: $t28730 };
                                }
                              }
                            }
                          })();
                          return ({ ...snapped, current: idx, score: $t28725, stars_chained: new_chained, multiplier: new_mult, max_mult: $t28727, capture_flash: $t28731 });
                        }
                      }
                    }
                  })();
                  {
                    const $t28732 = Perihelion$Upgrades$is_milestone(new_chained);
                    if ($t28732 === true) {
                      return (() => {
                        {
                          const $p28738 = (() => {
                            {
                              const $t28733 = captured_game.rng;
                              {
                                const $t28734 = captured_game.owned_weapons;
                                {
                                  const $t28735 = captured_game.special;
                                  return Perihelion$Upgrades$draw_choices($t28733, $t28734, $t28735);
                                }
                              }
                            }
                          })();
                          {
                            const rng2 = $p28738._0;
                            {
                              const choices = $p28738._1;
                              {
                                const $t28737 = (() => {
                                  {
                                    const $t28736 = { $: "Milestone" };
                                    return ({ ...captured_game, phase: $t28736, rng: rng2, milestone_choices: choices });
                                  }
                                })();
                                return Perihelion$Core$top_up($t28737);
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
        const $t28739 = { $: "Nil" };
        {
          const $t28740 = { $: "None" };
          return ({ ...game, fx_bursts: $t28739, capture_flash: $t28740 });
        }
      }
    })();
    switch (choice_idx.$) {
      case "None": {
        return g0;
        break;
      }
      case "Some": {
        const $f28748 = choice_idx._0;
        {
          const i = $f28748;
          {
            const $t28742 = (() => {
              {
                const $t28741 = g0.milestone_choices;
                return List$nth_opt$List_UpgradeKind$Int($t28741, i);
              }
            })();
            switch ($t28742.$) {
              case "None": {
                return g0;
                break;
              }
              case "Some": {
                const $f28747 = $t28742._0;
                {
                  const choice = $f28747;
                  {
                    const $t28746 = (() => {
                      {
                        const $t28743 = Perihelion$Core$apply_upgrade(g0, choice);
                        {
                          const $t28744 = { $: "Playing" };
                          {
                            const $t28745 = { $: "Nil" };
                            return ({ ...$t28743, phase: $t28744, milestone_choices: $t28745 });
                          }
                        }
                      }
                    })();
                    return Perihelion$Core$top_up($t28746);
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
      const $f28761 = u._0;
      {
        const k = $f28761;
        {
          const $t28750 = (() => {
            {
              const $t28749 = game.owned_weapons;
              {
                const $t709_i3933 = { $: "$Clo_$lam708$4787", _0: $lam708$apply$4787, _1: k };
                return List$any$List_WeaponKind$Fn_WeaponKind_Bool($t28749, $t709_i3933);
              }
            }
          })();
          if ($t28750 === true) {
            return game;
          } else {
            return (() => {
              {
                const $t28751 = game.owned_weapons;
                {
                  const $t28752 = { $: "Nil" };
                  {
                    const $t28753 = { $: "Cons", _0: k, _1: $t28752 };
                    {
                      const $t28754 = (() => {
                        {
                          const go_i10088 = { $: "$Clo_go$4806", _0: go$apply$4806 };
                          {
                            const $t301_i10091 = (() => {
                              {
                                const go_i4507_i10089 = { $: "$Clo_go$5246", _0: go$apply$5246 };
                                {
                                  const $t293_i4508_i10090 = { $: "Nil" };
                                  return go$apply$5246(go_i4507_i10089, $t28751, $t293_i4508_i10090);
                                }
                              }
                            })();
                            return go$apply$4806(go_i10088, $t301_i10091, $t28753);
                          }
                        }
                      })();
                      return ({ ...game, owned_weapons: $t28754 });
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
        const $t28756 = (() => {
          {
            const $t28755 = game.fire_rate_stacks;
            return ($t28755 + 1);
          }
        })();
        return ({ ...game, fire_rate_stacks: $t28756 });
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
        const $t28758 = (() => {
          {
            const $t28757 = game.shield;
            return ($t28757 + 1);
          }
        })();
        return ({ ...game, shield: $t28758, shield_reinforced: true });
      }
      break;
    }
    case "SpecialItem": {
      const $f28762 = u._0;
      {
        const k = $f28762;
        {
          const $t28759 = (() => {
            return { $: "Some", _0: k };
          })();
          {
            const $t28760 = (() => {
              {
                let $rc_830;
                switch (k.$) {
                  case "StarThrust": {
                    $rc_830 = 3;
                    break;
                  }
                  case "StarJump": {
                    $rc_830 = 1;
                    break;
                  }
                  case "TrajectoryPreview": {
                    $rc_830 = 0;
                    break;
                  }
                  default: {
                    $rc_830 = (() => { throw new Error("non-exhaustive pattern match"); })();
                    break;
                  }
                }
                return $rc_830;
              }
            })();
            return ({ ...game, special: $t28759, special_charges: $t28760 });
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
        const $t28764 = (() => {
          {
            const $t28763 = game.view_w;
            return ($t28763 / 2.);
          }
        })();
        {
          const $t28765 = ({ radius: 54., speed_mult: 1. });
          {
            const $t28766 = { $: "Nil" };
            {
              const $t28767 = { $: "Cons", _0: $t28765, _1: $t28766 };
              return ({ x: $t28764, y: 520., radius: 18., capture_radius: 54., speed_mult: 1., orbits: $t28767 });
            }
          }
        }
      }
    })();
    {
      const top = (() => {
        {
          const $t28768 = game.stars;
          return Perihelion$Core$top_star($t28768, fallback);
        }
      })();
      {
        const $t28775 = (() => {
          {
            const $t28769 = top.y;
            {
              const $t28774 = (() => {
                {
                  const $t28770 = game.camera_y;
                  {
                    const $t28773 = (() => {
                      {
                        const $t28771 = game.view_h;
                        return ($t28771 * 1.5);
                      }
                    })();
                    return ($t28770 - $t28773);
                  }
                }
              })();
              return ($t28769 > $t28774);
            }
          }
        })();
        if ($t28775 === true) {
          return (() => {
            {
              const $p28786 = (() => {
                {
                  const $t28776 = game.rng;
                  {
                    const $t28777 = game.view_w;
                    return Perihelion$Level$next_star($t28776, top, $t28777);
                  }
                }
              })();
              {
                const fresh = $p28786._0;
                {
                  const rng2 = $p28786._1;
                  {
                    const g2 = (() => {
                      {
                        const $t28778 = game.stars;
                        {
                          const $t28779 = { $: "Nil" };
                          {
                            const $t28780 = { $: "Cons", _0: fresh, _1: $t28779 };
                            {
                              const $t28781 = (() => {
                                {
                                  const go_i10095 = { $: "$Clo_go$4794", _0: go$apply$4794 };
                                  {
                                    const $t301_i10098 = (() => {
                                      {
                                        const go_i4500_i10096 = { $: "$Clo_go$5244", _0: go$apply$5244 };
                                        {
                                          const $t293_i4501_i10097 = { $: "Nil" };
                                          return go$apply$5244(go_i4500_i10096, $t28778, $t293_i4501_i10097);
                                        }
                                      }
                                    })();
                                    return go$apply$4794(go_i10095, $t301_i10098, $t28780);
                                  }
                                }
                              })();
                              return ({ ...game, stars: $t28781, rng: rng2 });
                            }
                          }
                        }
                      }
                    })();
                    {
                      const $t28785 = (() => {
                        {
                          const $t28784 = (() => {
                            {
                              const $t28783 = (() => {
                                {
                                  const $t28782 = g2.stars;
                                  {
                                    const go_i3936 = { $: "$Clo_go$4754", _0: go$apply$4754 };
                                    return go$apply$4754(go_i3936, $t28782, 0);
                                  }
                                }
                              })();
                              return ($t28783 - 1);
                            }
                          })();
                          return Perihelion$Combat$maybe_spawn_ship(g2, $t28784);
                        }
                      })();
                      return Perihelion$Core$top_up($t28785);
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
      const $f28787 = stars._0;
      const $f28788 = stars._1;
      {
        const $jp_clo28794 = (() => {
          return { $: "$Clo_$jp28793$3765", _0: $jp28793$apply$3765, _1: $f28788, _2: fallback };
        })();
        switch ($f28788.$) {
          case "Nil": {
            {
              const s = $f28787;
              return s;
            }
            break;
          }
          default: {
            return $jp28793$apply$3765($jp_clo28794);
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
        const $t28798 = game.score;
        {
          const $t28799 = game.stars_chained;
          {
            const $t28800 = game.max_mult;
            return ({ score: $t28798, stars: $t28799, max_mult: $t28800 });
          }
        }
      }
    })();
    {
      const $t28801 = { $: "Over" };
      {
        const $t28804 = (() => {
          {
            const $t28802 = game.best;
            {
              const $t28803 = game.score;
              {
                const $t28797_i3944 = ($t28802 > $t28803);
                if ($t28797_i3944 === true) {
                  return $t28802;
                } else {
                  return $t28803;
                }
              }
            }
          }
        })();
        {
          const $t28805 = game.runs;
          {
            const $t28806 = (() => {
              return { $: "Cons", _0: rec, _1: $t28805 };
            })();
            {
              const $t28807 = (() => {
                {
                  const go_i3940 = { $: "$Clo_go$4808", _0: go$apply$4808 };
                  {
                    const $t548_i3941 = { $: "Nil" };
                    return go$apply$4808(go_i3940, $t28806, 10, $t548_i3941);
                  }
                }
              })();
              return ({ ...game, phase: $t28801, best: $t28804, runs: $t28807 });
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
        const $t28808 = game.ball_y;
        {
          const $t28813 = (() => {
            {
              const $t28811 = (() => {
                {
                  const $t28809 = game.camera_y;
                  {
                    const $t28810 = game.view_h;
                    return ($t28809 + $t28810);
                  }
                }
              })();
              return ($t28811 + 40.);
            }
          })();
          return ($t28808 > $t28813);
        }
      }
    })();
    {
      const off_side = (() => {
        {
          const $t28817 = (() => {
            {
              const $t28814 = game.ball_x;
              {
                const $t28816 = (0. - 40.);
                return ($t28814 < $t28816);
              }
            }
          })();
          {
            const $t28822 = (() => {
              {
                const $t28818 = game.ball_x;
                {
                  const $t28821 = (() => {
                    {
                      const $t28819 = game.view_w;
                      return ($t28819 + 40.);
                    }
                  })();
                  return ($t28818 > $t28821);
                }
              }
            })();
            return ($t28817 || $t28822);
          }
        }
      })();
      {
        const fallback = (() => {
          {
            const $t28824 = (() => {
              {
                const $t28823 = game.view_w;
                return ($t28823 / 2.);
              }
            })();
            {
              const $t28825 = ({ radius: 54., speed_mult: 1. });
              {
                const $t28826 = { $: "Nil" };
                {
                  const $t28827 = { $: "Cons", _0: $t28825, _1: $t28826 };
                  return ({ x: $t28824, y: 520., radius: 18., capture_radius: 54., speed_mult: 1., orbits: $t28827 });
                }
              }
            }
          }
        })();
        {
          const topmost = (() => {
            {
              const $t28828 = game.stars;
              return Perihelion$Core$top_star($t28828, fallback);
            }
          })();
          {
            const overshot = (() => {
              {
                const $t28829 = game.ball_y;
                {
                  const $t28832 = (() => {
                    {
                      const $t28830 = topmost.y;
                      return ($t28830 - 150.);
                    }
                  })();
                  return ($t28829 < $t28832);
                }
              }
            })();
            {
              const fallen = (() => {
                {
                  const $t28833 = Perihelion$Core$star_at(game, 0);
                  switch ($t28833.$) {
                    case "None": {
                      return false;
                      break;
                    }
                    case "Some": {
                      const $f28838 = $t28833._0;
                      {
                        const c = $f28838;
                        {
                          const $t28834 = game.ball_y;
                          {
                            const $t28837 = (() => {
                              {
                                const $t28835 = c.y;
                                return ($t28835 + 200.);
                              }
                            })();
                            return ($t28834 > $t28837);
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
                const $t28841 = (() => {
                  {
                    const $t28840 = (() => {
                      {
                        const $t28839 = (below || off_side);
                        return ($t28839 || overshot);
                      }
                    })();
                    return ($t28840 || fallen);
                  }
                })();
                if ($t28841 === true) {
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
        const $t28842 = game.mode;
        switch ($t28842.$) {
          case "Flying": {
            const $f28849 = $t28842._0;
            const $f28850 = $t28842._1;
            (() => {
              return $f28849;
            })();
            return game.ball_x;
            break;
          }
          case "Orbiting": {
            const $f28855 = $t28842._0;
            const $f28856 = $t28842._1;
            const $f28857 = $t28842._2;
            {
              const $t28844 = (() => {
                {
                  const $t28843 = game.current;
                  return Perihelion$Core$star_at(game, $t28843);
                }
              })();
              switch ($t28844.$) {
                case "None": {
                  {
                    const $t28845 = game.camera_x;
                    {
                      const $t28847 = (() => {
                        {
                          const $t28846 = game.view_w;
                          return ($t28846 / 2.);
                        }
                      })();
                      return ($t28845 + $t28847);
                    }
                  }
                  break;
                }
                case "Some": {
                  const $f28848 = $t28844._0;
                  {
                    const s = $f28848;
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
          const $t28866 = game.mode;
          switch ($t28866.$) {
            case "Flying": {
              const $f28878 = $t28866._0;
              const $f28879 = $t28866._1;
              {
                const $t28867 = game.ball_y;
                {
                  const $t28870 = (() => {
                    {
                      const $t28869 = game.view_h;
                      return (0.6 * $t28869);
                    }
                  })();
                  return ($t28867 - $t28870);
                }
              }
              break;
            }
            case "Orbiting": {
              const $f28884 = $t28866._0;
              const $f28885 = $t28866._1;
              const $f28886 = $t28866._2;
              {
                const $t28872 = (() => {
                  {
                    const $t28871 = game.current;
                    return Perihelion$Core$star_at(game, $t28871);
                  }
                })();
                switch ($t28872.$) {
                  case "None": {
                    return game.camera_y;
                    break;
                  }
                  case "Some": {
                    const $f28877 = $t28872._0;
                    {
                      const s = $f28877;
                      {
                        const $t28873 = s.y;
                        {
                          const $t28876 = (() => {
                            {
                              const $t28875 = game.view_h;
                              return (0.6 * $t28875);
                            }
                          })();
                          return ($t28873 - $t28876);
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
            const $t28895 = game.view_w;
            return ($t28895 * 0.25);
          }
        })();
        {
          const right_edge = (() => {
            {
              const $t28897 = game.view_w;
              {
                const $t28899 = (1. - 0.25);
                return ($t28897 * $t28899);
              }
            }
          })();
          {
            const screen_x = (() => {
              {
                const $t28900 = game.camera_x;
                return (focus_x - $t28900);
              }
            })();
            {
              const target_x = (() => {
                {
                  const $t28901 = (screen_x < left_edge);
                  if ($t28901 === true) {
                    return (focus_x - left_edge);
                  } else {
                    return (() => {
                      {
                        const $t28902 = (screen_x > right_edge);
                        if ($t28902 === true) {
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
                const $t28909 = (() => {
                  {
                    const $t28903 = game.camera_y;
                    {
                      const $t28908 = (() => {
                        {
                          const $t28907 = (() => {
                            {
                              const $t28905 = (() => {
                                {
                                  const $t28904 = game.camera_y;
                                  return (target_y - $t28904);
                                }
                              })();
                              return ($t28905 * 3.);
                            }
                          })();
                          return ($t28907 * dt_s);
                        }
                      })();
                      return ($t28903 + $t28908);
                    }
                  }
                })();
                {
                  const $t28916 = (() => {
                    {
                      const $t28910 = game.camera_x;
                      {
                        const $t28915 = (() => {
                          {
                            const $t28914 = (() => {
                              {
                                const $t28912 = (() => {
                                  {
                                    const $t28911 = game.camera_x;
                                    return (target_x - $t28911);
                                  }
                                })();
                                return ($t28912 * 3.);
                              }
                            })();
                            return ($t28914 * dt_s);
                          }
                        })();
                        return ($t28910 + $t28915);
                      }
                    }
                  })();
                  return ({ ...game, camera_y: $t28909, camera_x: $t28916 });
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
    const $p28970 = (() => {
      {
        const $t28917 = Random$seed(seed);
        return Perihelion$Level$initial_stars($t28917, view_w);
      }
    })();
    {
      const stars = $p28970._0;
      {
        const rng2 = $p28970._1;
        {
          const start_angle = (3.14159265359 / 2.);
          switch (stars.$) {
            case "Nil": {
              {
                const $t28919 = { $: "Ready" };
                {
                  const $t28920 = { $: "Orbiting", _0: 0, _1: 0, _2: start_angle };
                  {
                    const $t28921 = { $: "Nil" };
                    {
                      const $t28922 = { $: "Nil" };
                      {
                        const $t28923 = { $: "Nil" };
                        {
                          const $t28924 = { $: "Nil" };
                          {
                            const $t28925 = { $: "Nil" };
                            {
                              const $t28926 = { $: "Nil" };
                              {
                                const $t28927 = { $: "Base" };
                                {
                                  const $t28928 = { $: "Nil" };
                                  {
                                    const $t28929 = { $: "Cons", _0: $t28927, _1: $t28928 };
                                    {
                                      const $t28930 = { $: "None" };
                                      {
                                        const $t28931 = { $: "Nil" };
                                        {
                                          const $t28933 = { $: "Nil" };
                                          {
                                            const $t28934 = { $: "None" };
                                            return ({ seed: seed, phase: $t28919, ball_x: 0., ball_y: 0., mode: $t28920, stars: $t28921, current: 0, score: 0, best: best, camera_y: 0., camera_x: 0., rng: rng2, asteroids: $t28922, ships: $t28923, player_shots: $t28924, enemy_shots: $t28925, pickups: $t28926, shield: 0, multiplier: 1, max_mult: 1, owned_weapons: $t28929, active_weapon_idx: 0, fire_rate_stacks: 0, bullet_ward: false, deflector_plating: false, shield_reinforced: false, special: $t28930, special_charges: 0, starkiller_target_offset: 0, starkiller_cooldown: 0., milestone_choices: $t28931, stars_chained: 0, loop_angle: 0., fire_cooldown: 0., spawn_timer: 4., runs: runs, view_w: view_w, view_h: view_h, fx_bursts: $t28933, capture_flash: $t28934 });
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
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
              const $f28964 = stars._0;
              const $f28965 = stars._1;
              {
                const s0 = (() => {
                  return $f28964;
                })();
                {
                  const $t28935 = { $: "Ready" };
                  {
                    const $t28940 = (() => {
                      {
                        const $t28936 = s0.x;
                        {
                          const $t28939 = (() => {
                            {
                              const $t28937 = Math.cos(start_angle);
                              {
                                const $t28938 = s0.capture_radius;
                                return ($t28937 * $t28938);
                              }
                            }
                          })();
                          return ($t28936 + $t28939);
                        }
                      }
                    })();
                    {
                      const $t28945 = (() => {
                        {
                          const $t28941 = s0.y;
                          {
                            const $t28944 = (() => {
                              {
                                const $t28942 = Math.sin(start_angle);
                                {
                                  const $t28943 = s0.capture_radius;
                                  return ($t28942 * $t28943);
                                }
                              }
                            })();
                            return ($t28941 + $t28944);
                          }
                        }
                      })();
                      {
                        const $t28946 = { $: "Orbiting", _0: 0, _1: 0, _2: start_angle };
                        {
                          const $t28950 = (() => {
                            {
                              const $t28947 = s0.y;
                              {
                                const $t28949 = (0.6 * view_h);
                                return ($t28947 - $t28949);
                              }
                            }
                          })();
                          {
                            const $t28951 = { $: "Nil" };
                            {
                              const $t28952 = { $: "Nil" };
                              {
                                const $t28953 = { $: "Nil" };
                                {
                                  const $t28954 = { $: "Nil" };
                                  {
                                    const $t28955 = { $: "Nil" };
                                    {
                                      const $t28956 = { $: "Base" };
                                      {
                                        const $t28957 = { $: "Nil" };
                                        {
                                          const $t28958 = { $: "Cons", _0: $t28956, _1: $t28957 };
                                          {
                                            const $t28959 = { $: "None" };
                                            {
                                              const $t28960 = { $: "Nil" };
                                              {
                                                const $t28962 = { $: "Nil" };
                                                {
                                                  const $t28963 = { $: "None" };
                                                  return ({ seed: seed, phase: $t28935, ball_x: $t28940, ball_y: $t28945, mode: $t28946, stars: stars, current: 0, score: 0, best: best, camera_y: $t28950, camera_x: 0., rng: rng2, asteroids: $t28951, ships: $t28952, player_shots: $t28953, enemy_shots: $t28954, pickups: $t28955, shield: 0, multiplier: 1, max_mult: 1, owned_weapons: $t28958, active_weapon_idx: 0, fire_rate_stacks: 0, bullet_ward: false, deflector_plating: false, shield_reinforced: false, special: $t28959, special_charges: 0, starkiller_target_offset: 0, starkiller_cooldown: 0., milestone_choices: $t28960, stars_chained: 0, loop_angle: 0., fire_cooldown: 0., spawn_timer: 4., runs: runs, view_w: view_w, view_h: view_h, fx_bursts: $t28962, capture_flash: $t28963 });
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
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
        const $t28976 = (() => {
          {
            const $p28975_i10111 = (() => {
              {
                const $t28974_i10100 = game.rng;
                {
                  const $p15616_i3959_i10101 = Random$next_raw($t28974_i10100);
                  {
                    const hi_i3960_i10102 = $p15616_i3959_i10101._0;
                    {
                      const rng2_i3961_i10103 = $p15616_i3959_i10101._1;
                      {
                        const $p15615_i3962_i10104 = Random$next_raw(rng2_i3961_i10103);
                        {
                          const lo_i3963_i10105 = $p15615_i3962_i10104._0;
                          {
                            const rng3_i3964_i10106 = $p15615_i3962_i10104._1;
                            {
                              const $t15614_i3968_i10110 = (() => {
                                {
                                  const $t15613_i3967_i10109 = (() => {
                                    {
                                      const $t15611_i3965_i10107 = march_int_and(hi_i3960_i10102, 1048575);
                                      return ($t15611_i3965_i10107 * 4294967296);
                                    }
                                  })();
                                  return ($t15613_i3967_i10109 + lo_i3963_i10105);
                                }
                              })();
                              return { _0: $t15614_i3968_i10110, _1: rng3_i3964_i10106 };
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
              const s_i10112 = $p28975_i10111._0;
              return s_i10112;
            }
          }
        })();
        {
          const $t28977 = game.best;
          {
            const $t28978 = game.runs;
            {
              const $t28979 = game.view_w;
              {
                const $t28980 = game.view_h;
                return Perihelion$Core$fresh_run($t28976, $t28977, $t28978, $t28979, $t28980);
              }
            }
          }
        }
      }
    })();
    {
      const $t28981 = { $: "Playing" };
      return ({ ...g, phase: $t28981 });
    }
  }
}
const Perihelion$Core$restart$clo = { _0: ($_, game) => Perihelion$Core$restart(game) };

function Perihelion$Core$reset(game) {
  {
    const $t28982 = (() => {
      {
        const $p28975_i10125 = (() => {
          {
            const $t28974_i10114 = game.rng;
            {
              const $p15616_i3959_i10115 = Random$next_raw($t28974_i10114);
              {
                const hi_i3960_i10116 = $p15616_i3959_i10115._0;
                {
                  const rng2_i3961_i10117 = $p15616_i3959_i10115._1;
                  {
                    const $p15615_i3962_i10118 = Random$next_raw(rng2_i3961_i10117);
                    {
                      const lo_i3963_i10119 = $p15615_i3962_i10118._0;
                      {
                        const rng3_i3964_i10120 = $p15615_i3962_i10118._1;
                        {
                          const $t15614_i3968_i10124 = (() => {
                            {
                              const $t15613_i3967_i10123 = (() => {
                                {
                                  const $t15611_i3965_i10121 = march_int_and(hi_i3960_i10116, 1048575);
                                  return ($t15611_i3965_i10121 * 4294967296);
                                }
                              })();
                              return ($t15613_i3967_i10123 + lo_i3963_i10119);
                            }
                          })();
                          return { _0: $t15614_i3968_i10124, _1: rng3_i3964_i10120 };
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
          const s_i10126 = $p28975_i10125._0;
          return s_i10126;
        }
      }
    })();
    {
      const $t28983 = game.best;
      {
        const $t28984 = game.runs;
        {
          const $t28985 = game.view_w;
          {
            const $t28986 = game.view_h;
            return Perihelion$Core$fresh_run($t28982, $t28983, $t28984, $t28985, $t28986);
          }
        }
      }
    }
  }
}
const Perihelion$Core$reset$clo = { _0: ($_, game) => Perihelion$Core$reset(game) };

function Perihelion$Core$encode_run(r) {
  {
    const $t28993 = (() => {
      {
        const $t28992 = (() => {
          {
            const $t28989 = (() => {
              {
                const $t28988 = (() => {
                  {
                    const $t28987 = r.score;
                    return String($t28987);
                  }
                })();
                {
                  const $rc_834 = ($t28988 + ":");
                  return $rc_834;
                }
              }
            })();
            {
              const $t28991 = (() => {
                {
                  const $t28990 = r.stars;
                  return String($t28990);
                }
              })();
              {
                const $rc_833 = ($t28989 + $t28991);
                return $rc_833;
              }
            }
          }
        })();
        {
          const $rc_832 = ($t28992 + ":");
          return $rc_832;
        }
      }
    })();
    {
      const $t28995 = (() => {
        {
          const $t28994 = r.max_mult;
          return String($t28994);
        }
      })();
      {
        const $rc_831 = ($t28993 + $t28995);
        return $rc_831;
      }
    }
  }
}
const Perihelion$Core$encode_run$clo = { _0: ($_, r) => Perihelion$Core$encode_run(r) };

function Perihelion$Core$encode_save(best, runs) {
  {
    const $t28997 = (() => {
      {
        const $t28996 = String(best);
        {
          const $rc_836 = ($t28996 + "|");
          return $rc_836;
        }
      }
    })();
    {
      const $t29001 = (() => {
        {
          const $t28999 = { $: "$Clo_$lam28998$3777", _0: $lam28998$apply$3777 };
          {
            const $t29000 = (() => {
              {
                const f_i3972 = $t28999;
                {
                  const go_i3973 = { $: "$Clo_go$4810", _0: go$apply$4810, _1: f_i3972 };
                  {
                    const $t310_i3974 = { $: "Nil" };
                    return go$apply$4810(go_i3973, runs, $t310_i3974);
                  }
                }
              }
            })();
            return march_string_join($t29000, ";");
          }
        }
      })();
      {
        const $rc_835 = ($t28997 + $t29001);
        return $rc_835;
      }
    }
  }
}
const Perihelion$Core$encode_save$clo = { _0: ($_, best, runs) => Perihelion$Core$encode_save(best, runs) };

function Perihelion$Core$decode_run(s) {
  {
    const $t29002 = march_string_split(s, ":");
    switch ($t29002.$) {
      case "Cons": {
        const $f29010 = $t29002._0;
        const $f29011 = $t29002._1;
        {
          const $jp_clo29013 = { $: "$Clo_$jp29012$3778", _0: $jp29012$apply$3778 };
          {
            const $jp_clo29017 = { $: "$Clo_$jp29016$3779", _0: $jp29016$apply$3779$clo, _1: $jp_clo29013 };
            switch ($f29011.$) {
              case "Cons": {
                const $f29018 = $f29011._0;
                const $f29019 = $f29011._1;
                {
                  const $jp_clo29021 = { $: "$Clo_$jp29020$3781", _0: $jp29020$apply$3781, _1: $jp_clo29017 };
                  {
                    const $jp_clo29025 = { $: "$Clo_$jp29024$3782", _0: $jp29024$apply$3782, _1: $jp_clo29021 };
                    switch ($f29019.$) {
                      case "Cons": {
                        const $f29026 = $f29019._0;
                        const $f29027 = $f29019._1;
                        {
                          const $jp_clo29029 = { $: "$Clo_$jp29028$3784", _0: $jp29028$apply$3784, _1: $jp_clo29025 };
                          {
                            const $jp_clo29033 = { $: "$Clo_$jp29032$3785", _0: $jp29032$apply$3785, _1: $jp_clo29029 };
                            switch ($f29027.$) {
                              case "Nil": {
                                {
                                  const c = $f29026;
                                  {
                                    const b = $f29018;
                                    {
                                      const a = $f29010;
                                      {
                                        const $t29003 = (() => {
                                          {
                                            const $rc_839 = march_string_to_int(a);
                                            return $rc_839;
                                          }
                                        })();
                                        switch ($t29003.$) {
                                          case "None": {
                                            return { $: "None" };
                                            break;
                                          }
                                          case "Some": {
                                            const $f29009 = $t29003._0;
                                            {
                                              const score = $f29009;
                                              {
                                                const $t29004 = (() => {
                                                  {
                                                    const $rc_838 = march_string_to_int(b);
                                                    return $rc_838;
                                                  }
                                                })();
                                                switch ($t29004.$) {
                                                  case "None": {
                                                    return { $: "None" };
                                                    break;
                                                  }
                                                  case "Some": {
                                                    const $f29008 = $t29004._0;
                                                    {
                                                      const stars = $f29008;
                                                      {
                                                        const $t29005 = (() => {
                                                          {
                                                            const $rc_837 = march_string_to_int(c);
                                                            return $rc_837;
                                                          }
                                                        })();
                                                        switch ($t29005.$) {
                                                          case "None": {
                                                            return { $: "None" };
                                                            break;
                                                          }
                                                          case "Some": {
                                                            const $f29007 = $t29005._0;
                                                            {
                                                              const mm = $f29007;
                                                              {
                                                                const $t29006 = ({ score: score, stars: stars, max_mult: mm });
                                                                return { $: "Some", _0: $t29006 };
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
                                return $jp29032$apply$3785($jp_clo29033);
                              }
                            }
                          }
                        }
                        break;
                      }
                      default: {
                        return $jp29024$apply$3782($jp_clo29025);
                      }
                    }
                  }
                }
                break;
              }
              default: {
                return $jp29016$apply$3779($jp_clo29017);
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
        const $t29036 = (() => {
          {
            const go_i3982 = { $: "$Clo_go$4812", _0: go$apply$4812 };
            {
              const $t293_i3983 = { $: "Nil" };
              return go$apply$4812(go_i3982, acc, $t293_i3983);
            }
          }
        })();
        return { $: "Some", _0: $t29036 };
      }
      break;
    }
    case "Cons": {
      const $f29040 = parts._0;
      const $f29041 = parts._1;
      {
        const rest = $f29041;
        {
          const p = $f29040;
          {
            const $t29037 = (() => {
              {
                const $rc_840 = Perihelion$Core$decode_run(p);
                return $rc_840;
              }
            })();
            switch ($t29037.$) {
              case "None": {
                return { $: "None" };
                break;
              }
              case "Some": {
                const $f29039 = $t29037._0;
                {
                  const r = $f29039;
                  {
                    const $t29038 = { $: "Cons", _0: r, _1: acc };
                    return Perihelion$Core$decode_runs(rest, $t29038);
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
        const $t29046 = { $: "Nil" };
        return { _0: 0, _1: $t29046 };
      }
    })();
    {
      const $t29047 = march_string_split(s, "|");
      switch ($t29047.$) {
        case "Cons": {
          const $f29057 = $t29047._0;
          const $f29058 = $t29047._1;
          switch ($f29058.$) {
            case "Cons": {
              const $f29059 = $f29058._0;
              const $f29060 = $f29058._1;
              switch ($f29060.$) {
                case "Nil": {
                  {
                    const runs_s = $f29059;
                    {
                      const best_s = $f29057;
                      {
                        const $t29048 = (() => {
                          {
                            const $rc_842 = march_string_to_int(best_s);
                            return $rc_842;
                          }
                        })();
                        switch ($t29048.$) {
                          case "None": {
                            return zero;
                            break;
                          }
                          case "Some": {
                            const $f29056 = $t29048._0;
                            {
                              const best = $f29056;
                              if (runs_s === "") {
                                return (() => {
                                  {
                                    const $t29049 = { $: "Nil" };
                                    return { _0: best, _1: $t29049 };
                                  }
                                })();
                              } else {
                                return (() => {
                                  {
                                    const $t29052 = (() => {
                                      {
                                        const $t29050 = (() => {
                                          {
                                            const $rc_841 = march_string_split(runs_s, ";");
                                            return $rc_841;
                                          }
                                        })();
                                        {
                                          const $t29051 = { $: "Nil" };
                                          return Perihelion$Core$decode_runs($t29050, $t29051);
                                        }
                                      }
                                    })();
                                    switch ($t29052.$) {
                                      case "None": {
                                        return zero;
                                        break;
                                      }
                                      case "Some": {
                                        const $f29053 = $t29052._0;
                                        {
                                          const rs = $f29053;
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
        const $t29066 = ({ radius: outer_r, speed_mult: outer_sp });
        {
          const $t29067 = { $: "Nil" };
          return { $: "Cons", _0: $t29066, _1: $t29067 };
        }
      }
    })();
  } else if (n === 2) {
    return (() => {
      {
        const $t29070 = (() => {
          {
            const $t29068 = (outer_r * 0.6);
            {
              const $t29069 = (outer_sp * 1.5);
              return ({ radius: $t29068, speed_mult: $t29069 });
            }
          }
        })();
        {
          const $t29071 = ({ radius: outer_r, speed_mult: outer_sp });
          {
            const $t29072 = { $: "Nil" };
            {
              const $t29073 = { $: "Cons", _0: $t29071, _1: $t29072 };
              return { $: "Cons", _0: $t29070, _1: $t29073 };
            }
          }
        }
      }
    })();
  } else {
    return (() => {
      {
        const $t29076 = (() => {
          {
            const $t29074 = (outer_r * 0.5);
            {
              const $t29075 = (outer_sp * 1.8);
              return ({ radius: $t29074, speed_mult: $t29075 });
            }
          }
        })();
        {
          const $t29079 = (() => {
            {
              const $t29077 = (outer_r * 0.75);
              {
                const $t29078 = (outer_sp * 1.35);
                return ({ radius: $t29077, speed_mult: $t29078 });
              }
            }
          })();
          {
            const $t29080 = ({ radius: outer_r, speed_mult: outer_sp });
            {
              const $t29081 = { $: "Nil" };
              {
                const $t29082 = { $: "Cons", _0: $t29080, _1: $t29081 };
                {
                  const $t29083 = { $: "Cons", _0: $t29079, _1: $t29082 };
                  return { $: "Cons", _0: $t29076, _1: $t29083 };
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
    const $p29113 = (() => {
      {
        const $p29061_i10527 = (() => {
          {
            const $p15619_i10138_i10522 = (() => {
              {
                const $p15616_i1544_i10128_i10513 = Random$next_raw(rng);
                {
                  const hi_i1545_i10129_i10514 = $p15616_i1544_i10128_i10513._0;
                  {
                    const rng2_i1546_i10130_i10515 = $p15616_i1544_i10128_i10513._1;
                    {
                      const $p15615_i1547_i10131_i10516 = Random$next_raw(rng2_i1546_i10130_i10515);
                      {
                        const lo_i1548_i10132_i10517 = $p15615_i1547_i10131_i10516._0;
                        {
                          const rng3_i1549_i10133_i10518 = $p15615_i1547_i10131_i10516._1;
                          {
                            const $t15614_i1553_i10137_i10521 = (() => {
                              {
                                const $t15613_i1552_i10136_i10520 = (() => {
                                  {
                                    const $t15611_i1550_i10134_i10519 = march_int_and(hi_i1545_i10129_i10514, 1048575);
                                    return ($t15611_i1550_i10134_i10519 * 4294967296);
                                  }
                                })();
                                return ($t15613_i1552_i10136_i10520 + lo_i1548_i10132_i10517);
                              }
                            })();
                            return { _0: $t15614_i1553_i10137_i10521, _1: rng3_i1549_i10133_i10518 };
                          }
                        }
                      }
                    }
                  }
                }
              }
            })();
            {
              const bits_i10139_i10523 = $p15619_i10138_i10522._0;
              {
                const rng2_i10140_i10524 = $p15619_i10138_i10522._1;
                {
                  const $t15618_i10142_i10526 = (() => {
                    {
                      const $t15617_i10141_i10525 = bits_i10139_i10523;
                      return ($t15617_i10141_i10525 / 4.50359962737e+15);
                    }
                  })();
                  return { _0: $t15618_i10142_i10526, _1: rng2_i10140_i10524 };
                }
              }
            }
          }
        })();
        {
          const t_i10528 = $p29061_i10527._0;
          {
            const rng2_i10529 = $p29061_i10527._1;
            {
              const out_i10530 = { _0: rng2_i10529, _1: t_i10528 };
              return out_i10530;
            }
          }
        }
      }
    })();
    {
      const r1 = $p29113._0;
      {
        const ty = $p29113._1;
        {
          const $p29112 = (() => {
            {
              const $p29061_i10508 = (() => {
                {
                  const $p15619_i10138_i10503 = (() => {
                    {
                      const $p15616_i1544_i10128_i10494 = Random$next_raw(r1);
                      {
                        const hi_i1545_i10129_i10495 = $p15616_i1544_i10128_i10494._0;
                        {
                          const rng2_i1546_i10130_i10496 = $p15616_i1544_i10128_i10494._1;
                          {
                            const $p15615_i1547_i10131_i10497 = Random$next_raw(rng2_i1546_i10130_i10496);
                            {
                              const lo_i1548_i10132_i10498 = $p15615_i1547_i10131_i10497._0;
                              {
                                const rng3_i1549_i10133_i10499 = $p15615_i1547_i10131_i10497._1;
                                {
                                  const $t15614_i1553_i10137_i10502 = (() => {
                                    {
                                      const $t15613_i1552_i10136_i10501 = (() => {
                                        {
                                          const $t15611_i1550_i10134_i10500 = march_int_and(hi_i1545_i10129_i10495, 1048575);
                                          return ($t15611_i1550_i10134_i10500 * 4294967296);
                                        }
                                      })();
                                      return ($t15613_i1552_i10136_i10501 + lo_i1548_i10132_i10498);
                                    }
                                  })();
                                  return { _0: $t15614_i1553_i10137_i10502, _1: rng3_i1549_i10133_i10499 };
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  })();
                  {
                    const bits_i10139_i10504 = $p15619_i10138_i10503._0;
                    {
                      const rng2_i10140_i10505 = $p15619_i10138_i10503._1;
                      {
                        const $t15618_i10142_i10507 = (() => {
                          {
                            const $t15617_i10141_i10506 = bits_i10139_i10504;
                            return ($t15617_i10141_i10506 / 4.50359962737e+15);
                          }
                        })();
                        return { _0: $t15618_i10142_i10507, _1: rng2_i10140_i10505 };
                      }
                    }
                  }
                }
              })();
              {
                const t_i10509 = $p29061_i10508._0;
                {
                  const rng2_i10510 = $p29061_i10508._1;
                  {
                    const out_i10511 = { _0: rng2_i10510, _1: t_i10509 };
                    return out_i10511;
                  }
                }
              }
            }
          })();
          {
            const r2 = $p29112._0;
            {
              const tx = $p29112._1;
              {
                const $p29111 = (() => {
                  {
                    const $p29061_i10489 = (() => {
                      {
                        const $p15619_i10138_i10484 = (() => {
                          {
                            const $p15616_i1544_i10128_i10475 = Random$next_raw(r2);
                            {
                              const hi_i1545_i10129_i10476 = $p15616_i1544_i10128_i10475._0;
                              {
                                const rng2_i1546_i10130_i10477 = $p15616_i1544_i10128_i10475._1;
                                {
                                  const $p15615_i1547_i10131_i10478 = Random$next_raw(rng2_i1546_i10130_i10477);
                                  {
                                    const lo_i1548_i10132_i10479 = $p15615_i1547_i10131_i10478._0;
                                    {
                                      const rng3_i1549_i10133_i10480 = $p15615_i1547_i10131_i10478._1;
                                      {
                                        const $t15614_i1553_i10137_i10483 = (() => {
                                          {
                                            const $t15613_i1552_i10136_i10482 = (() => {
                                              {
                                                const $t15611_i1550_i10134_i10481 = march_int_and(hi_i1545_i10129_i10476, 1048575);
                                                return ($t15611_i1550_i10134_i10481 * 4294967296);
                                              }
                                            })();
                                            return ($t15613_i1552_i10136_i10482 + lo_i1548_i10132_i10479);
                                          }
                                        })();
                                        return { _0: $t15614_i1553_i10137_i10483, _1: rng3_i1549_i10133_i10480 };
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        })();
                        {
                          const bits_i10139_i10485 = $p15619_i10138_i10484._0;
                          {
                            const rng2_i10140_i10486 = $p15619_i10138_i10484._1;
                            {
                              const $t15618_i10142_i10488 = (() => {
                                {
                                  const $t15617_i10141_i10487 = bits_i10139_i10485;
                                  return ($t15617_i10141_i10487 / 4.50359962737e+15);
                                }
                              })();
                              return { _0: $t15618_i10142_i10488, _1: rng2_i10140_i10486 };
                            }
                          }
                        }
                      }
                    })();
                    {
                      const t_i10490 = $p29061_i10489._0;
                      {
                        const rng2_i10491 = $p29061_i10489._1;
                        {
                          const out_i10492 = { _0: rng2_i10491, _1: t_i10490 };
                          return out_i10492;
                        }
                      }
                    }
                  }
                })();
                {
                  const r3 = $p29111._0;
                  {
                    const tr = $p29111._1;
                    {
                      const $p29110 = (() => {
                        {
                          const $p29061_i10470 = (() => {
                            {
                              const $p15619_i10138_i10465 = (() => {
                                {
                                  const $p15616_i1544_i10128_i10456 = Random$next_raw(r3);
                                  {
                                    const hi_i1545_i10129_i10457 = $p15616_i1544_i10128_i10456._0;
                                    {
                                      const rng2_i1546_i10130_i10458 = $p15616_i1544_i10128_i10456._1;
                                      {
                                        const $p15615_i1547_i10131_i10459 = Random$next_raw(rng2_i1546_i10130_i10458);
                                        {
                                          const lo_i1548_i10132_i10460 = $p15615_i1547_i10131_i10459._0;
                                          {
                                            const rng3_i1549_i10133_i10461 = $p15615_i1547_i10131_i10459._1;
                                            {
                                              const $t15614_i1553_i10137_i10464 = (() => {
                                                {
                                                  const $t15613_i1552_i10136_i10463 = (() => {
                                                    {
                                                      const $t15611_i1550_i10134_i10462 = march_int_and(hi_i1545_i10129_i10457, 1048575);
                                                      return ($t15611_i1550_i10134_i10462 * 4294967296);
                                                    }
                                                  })();
                                                  return ($t15613_i1552_i10136_i10463 + lo_i1548_i10132_i10460);
                                                }
                                              })();
                                              return { _0: $t15614_i1553_i10137_i10464, _1: rng3_i1549_i10133_i10461 };
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              })();
                              {
                                const bits_i10139_i10466 = $p15619_i10138_i10465._0;
                                {
                                  const rng2_i10140_i10467 = $p15619_i10138_i10465._1;
                                  {
                                    const $t15618_i10142_i10469 = (() => {
                                      {
                                        const $t15617_i10141_i10468 = bits_i10139_i10466;
                                        return ($t15617_i10141_i10468 / 4.50359962737e+15);
                                      }
                                    })();
                                    return { _0: $t15618_i10142_i10469, _1: rng2_i10140_i10467 };
                                  }
                                }
                              }
                            }
                          })();
                          {
                            const t_i10471 = $p29061_i10470._0;
                            {
                              const rng2_i10472 = $p29061_i10470._1;
                              {
                                const out_i10473 = { _0: rng2_i10472, _1: t_i10471 };
                                return out_i10473;
                              }
                            }
                          }
                        }
                      })();
                      {
                        const r4 = $p29110._0;
                        {
                          const tcm = $p29110._1;
                          {
                            const $p29109 = (() => {
                              {
                                const $p29061_i10451 = (() => {
                                  {
                                    const $p15619_i10138_i10446 = (() => {
                                      {
                                        const $p15616_i1544_i10128_i10437 = Random$next_raw(r4);
                                        {
                                          const hi_i1545_i10129_i10438 = $p15616_i1544_i10128_i10437._0;
                                          {
                                            const rng2_i1546_i10130_i10439 = $p15616_i1544_i10128_i10437._1;
                                            {
                                              const $p15615_i1547_i10131_i10440 = Random$next_raw(rng2_i1546_i10130_i10439);
                                              {
                                                const lo_i1548_i10132_i10441 = $p15615_i1547_i10131_i10440._0;
                                                {
                                                  const rng3_i1549_i10133_i10442 = $p15615_i1547_i10131_i10440._1;
                                                  {
                                                    const $t15614_i1553_i10137_i10445 = (() => {
                                                      {
                                                        const $t15613_i1552_i10136_i10444 = (() => {
                                                          {
                                                            const $t15611_i1550_i10134_i10443 = march_int_and(hi_i1545_i10129_i10438, 1048575);
                                                            return ($t15611_i1550_i10134_i10443 * 4294967296);
                                                          }
                                                        })();
                                                        return ($t15613_i1552_i10136_i10444 + lo_i1548_i10132_i10441);
                                                      }
                                                    })();
                                                    return { _0: $t15614_i1553_i10137_i10445, _1: rng3_i1549_i10133_i10442 };
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    })();
                                    {
                                      const bits_i10139_i10447 = $p15619_i10138_i10446._0;
                                      {
                                        const rng2_i10140_i10448 = $p15619_i10138_i10446._1;
                                        {
                                          const $t15618_i10142_i10450 = (() => {
                                            {
                                              const $t15617_i10141_i10449 = bits_i10139_i10447;
                                              return ($t15617_i10141_i10449 / 4.50359962737e+15);
                                            }
                                          })();
                                          return { _0: $t15618_i10142_i10450, _1: rng2_i10140_i10448 };
                                        }
                                      }
                                    }
                                  }
                                })();
                                {
                                  const t_i10452 = $p29061_i10451._0;
                                  {
                                    const rng2_i10453 = $p29061_i10451._1;
                                    {
                                      const out_i10454 = { _0: rng2_i10453, _1: t_i10452 };
                                      return out_i10454;
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const r5 = $p29109._0;
                              {
                                const tsm = $p29109._1;
                                {
                                  const $p29108 = (() => {
                                    {
                                      const $p29061_i10432 = (() => {
                                        {
                                          const $p15619_i10138_i10427 = (() => {
                                            {
                                              const $p15616_i1544_i10128_i10418 = Random$next_raw(r5);
                                              {
                                                const hi_i1545_i10129_i10419 = $p15616_i1544_i10128_i10418._0;
                                                {
                                                  const rng2_i1546_i10130_i10420 = $p15616_i1544_i10128_i10418._1;
                                                  {
                                                    const $p15615_i1547_i10131_i10421 = Random$next_raw(rng2_i1546_i10130_i10420);
                                                    {
                                                      const lo_i1548_i10132_i10422 = $p15615_i1547_i10131_i10421._0;
                                                      {
                                                        const rng3_i1549_i10133_i10423 = $p15615_i1547_i10131_i10421._1;
                                                        {
                                                          const $t15614_i1553_i10137_i10426 = (() => {
                                                            {
                                                              const $t15613_i1552_i10136_i10425 = (() => {
                                                                {
                                                                  const $t15611_i1550_i10134_i10424 = march_int_and(hi_i1545_i10129_i10419, 1048575);
                                                                  return ($t15611_i1550_i10134_i10424 * 4294967296);
                                                                }
                                                              })();
                                                              return ($t15613_i1552_i10136_i10425 + lo_i1548_i10132_i10422);
                                                            }
                                                          })();
                                                          return { _0: $t15614_i1553_i10137_i10426, _1: rng3_i1549_i10133_i10423 };
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          })();
                                          {
                                            const bits_i10139_i10428 = $p15619_i10138_i10427._0;
                                            {
                                              const rng2_i10140_i10429 = $p15619_i10138_i10427._1;
                                              {
                                                const $t15618_i10142_i10431 = (() => {
                                                  {
                                                    const $t15617_i10141_i10430 = bits_i10139_i10428;
                                                    return ($t15617_i10141_i10430 / 4.50359962737e+15);
                                                  }
                                                })();
                                                return { _0: $t15618_i10142_i10431, _1: rng2_i10140_i10429 };
                                              }
                                            }
                                          }
                                        }
                                      })();
                                      {
                                        const t_i10433 = $p29061_i10432._0;
                                        {
                                          const rng2_i10434 = $p29061_i10432._1;
                                          {
                                            const out_i10435 = { _0: rng2_i10434, _1: t_i10433 };
                                            return out_i10435;
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const r6 = $p29108._0;
                                    {
                                      const trings = $p29108._1;
                                      {
                                        const gap = (() => {
                                          {
                                            const $t29063_i4023 = (() => {
                                              {
                                                const $t29062_i4022 = (260. - 160.);
                                                return (ty * $t29062_i4022);
                                              }
                                            })();
                                            return (160. + $t29063_i4023);
                                          }
                                        })();
                                        {
                                          const dx = (() => {
                                            {
                                              const $t29091 = (0. - 220.);
                                              {
                                                const $t29063_i4018 = (() => {
                                                  {
                                                    const $t29062_i4017 = (220. - $t29091);
                                                    return (tx * $t29062_i4017);
                                                  }
                                                })();
                                                return ($t29091 + $t29063_i4018);
                                              }
                                            }
                                          })();
                                          {
                                            const x = (() => {
                                              {
                                                const $t29094 = (() => {
                                                  {
                                                    const $t29093 = prev.x;
                                                    return ($t29093 + dx);
                                                  }
                                                })();
                                                {
                                                  const $t29097 = (view_w - 60.);
                                                  {
                                                    const $t1620_i4012 = ($t29094 < 60.);
                                                    if ($t1620_i4012 === true) {
                                                      return 60.;
                                                    } else {
                                                      return (() => {
                                                        {
                                                          const $t1621_i4013 = ($t29094 > $t29097);
                                                          if ($t1621_i4013 === true) {
                                                            return $t29097;
                                                          } else {
                                                            return $t29094;
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
                                                  const $t29100 = (tr * tr);
                                                  {
                                                    const $t29063_i4008 = (() => {
                                                      {
                                                        const $t29062_i4007 = (20. - 8.);
                                                        return ($t29100 * $t29062_i4007);
                                                      }
                                                    })();
                                                    return (8. + $t29063_i4008);
                                                  }
                                                }
                                              })();
                                              {
                                                const cm = (() => {
                                                  {
                                                    const $t29063_i4003 = (() => {
                                                      {
                                                        const $t29062_i4002 = (5.2 - 2.8);
                                                        return (tcm * $t29062_i4002);
                                                      }
                                                    })();
                                                    return (2.8 + $t29063_i4003);
                                                  }
                                                })();
                                                {
                                                  const sm = (() => {
                                                    {
                                                      const $t29063_i3998 = (() => {
                                                        {
                                                          const $t29062_i3997 = (1.6 - 0.7);
                                                          return (tsm * $t29062_i3997);
                                                        }
                                                      })();
                                                      return (0.7 + $t29063_i3998);
                                                    }
                                                  })();
                                                  {
                                                    const cap = (r * cm);
                                                    {
                                                      const $t29105 = (() => {
                                                        {
                                                          const $t29064_i3992 = (trings < 0.55);
                                                          if ($t29064_i3992 === true) {
                                                            return 1;
                                                          } else {
                                                            return (() => {
                                                              {
                                                                const $t29065_i3993 = (trings < 0.85);
                                                                if ($t29065_i3993 === true) {
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
                                                        const orbits = Perihelion$Level$make_orbits(cap, sm, $t29105);
                                                        {
                                                          const s = (() => {
                                                            {
                                                              const $t29107 = (() => {
                                                                {
                                                                  const $t29106 = prev.y;
                                                                  return ($t29106 - gap);
                                                                }
                                                              })();
                                                              return ({ x: x, y: $t29107, radius: r, capture_radius: cap, speed_mult: sm, orbits: orbits });
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
        const $t29114 = (view_w / 2.);
        {
          const $t29115 = ({ radius: 54., speed_mult: 1. });
          {
            const $t29116 = { $: "Nil" };
            {
              const $t29117 = { $: "Cons", _0: $t29115, _1: $t29116 };
              return ({ x: $t29114, y: 520., radius: 18., capture_radius: 54., speed_mult: 1., orbits: $t29117 });
            }
          }
        }
      }
    })();
    {
      const $p29122 = Perihelion$Level$next_star(rng, first, view_w);
      {
        const s2 = $p29122._0;
        {
          const rng2 = $p29122._1;
          {
            const $p29121 = Perihelion$Level$next_star(rng2, s2, view_w);
            {
              const s3 = $p29121._0;
              {
                const rng3 = $p29121._1;
                {
                  const $t29118 = { $: "Nil" };
                  {
                    const $t29119 = { $: "Cons", _0: s3, _1: $t29118 };
                    {
                      const $t29120 = { $: "Cons", _0: s2, _1: $t29119 };
                      {
                        const stars = { $: "Cons", _0: first, _1: $t29120 };
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
    const $t29134 = (() => {
      {
        const $t29132 = (() => {
          {
            const x_i10200 = (() => {
              {
                const $t29128_i10199 = (() => {
                  {
                    const $t29127_i10198 = (() => {
                      {
                        const $t29125_i10196 = (() => {
                          {
                            const $t29123_i10194 = (sx * 12.9898);
                            {
                              const $t29124_i10195 = (sy * 78.233);
                              return ($t29123_i10194 + $t29124_i10195);
                            }
                          }
                        })();
                        {
                          const $t29126_i10197 = (seed * 37.719);
                          return ($t29125_i10196 + $t29126_i10197);
                        }
                      }
                    })();
                    return Math.sin($t29127_i10198);
                  }
                })();
                return ($t29128_i10199 * 43758.5453);
              }
            })();
            {
              const $t29129_i10202 = (() => {
                {
                  const $t1622_i4025_i10201 = Math.floor(x_i10200);
                  return $t1622_i4025_i10201;
                }
              })();
              return (x_i10200 - $t29129_i10202);
            }
          }
        })();
        return ($t29132 > 0.55);
      }
    })();
    if ($t29134 === true) {
      return { $: "None" };
    } else {
      return (() => {
        {
          const jx = (() => {
            {
              const $t29138 = (() => {
                {
                  const $t29137 = (() => {
                    {
                      const $t29136 = (() => {
                        {
                          const $t29135 = (sx + 1.);
                          {
                            const x_i10188 = (() => {
                              {
                                const $t29128_i10187 = (() => {
                                  {
                                    const $t29127_i10186 = (() => {
                                      {
                                        const $t29125_i10184 = (() => {
                                          {
                                            const $t29123_i10182 = ($t29135 * 12.9898);
                                            {
                                              const $t29124_i10183 = (sy * 78.233);
                                              return ($t29123_i10182 + $t29124_i10183);
                                            }
                                          }
                                        })();
                                        {
                                          const $t29126_i10185 = (seed * 37.719);
                                          return ($t29125_i10184 + $t29126_i10185);
                                        }
                                      }
                                    })();
                                    return Math.sin($t29127_i10186);
                                  }
                                })();
                                return ($t29128_i10187 * 43758.5453);
                              }
                            })();
                            {
                              const $t29129_i10190 = (() => {
                                {
                                  const $t1622_i4025_i10189 = Math.floor(x_i10188);
                                  return $t1622_i4025_i10189;
                                }
                              })();
                              return (x_i10188 - $t29129_i10190);
                            }
                          }
                        }
                      })();
                      return ($t29136 - 0.5);
                    }
                  })();
                  return ($t29137 * 2.);
                }
              })();
              return ($t29138 * 90.);
            }
          })();
          {
            const jy = (() => {
              {
                const $t29143 = (() => {
                  {
                    const $t29142 = (() => {
                      {
                        const $t29141 = (() => {
                          {
                            const $t29140 = (sy + 1.);
                            {
                              const x_i10176 = (() => {
                                {
                                  const $t29128_i10175 = (() => {
                                    {
                                      const $t29127_i10174 = (() => {
                                        {
                                          const $t29125_i10172 = (() => {
                                            {
                                              const $t29123_i10170 = (sx * 12.9898);
                                              {
                                                const $t29124_i10171 = ($t29140 * 78.233);
                                                return ($t29123_i10170 + $t29124_i10171);
                                              }
                                            }
                                          })();
                                          {
                                            const $t29126_i10173 = (seed * 37.719);
                                            return ($t29125_i10172 + $t29126_i10173);
                                          }
                                        }
                                      })();
                                      return Math.sin($t29127_i10174);
                                    }
                                  })();
                                  return ($t29128_i10175 * 43758.5453);
                                }
                              })();
                              {
                                const $t29129_i10178 = (() => {
                                  {
                                    const $t1622_i4025_i10177 = Math.floor(x_i10176);
                                    return $t1622_i4025_i10177;
                                  }
                                })();
                                return (x_i10176 - $t29129_i10178);
                              }
                            }
                          }
                        })();
                        return ($t29141 - 0.5);
                      }
                    })();
                    return ($t29142 * 2.);
                  }
                })();
                return ($t29143 * 90.);
              }
            })();
            {
              const rt = (() => {
                {
                  const $t29145 = (sx + 2.);
                  {
                    const x_i10164 = (() => {
                      {
                        const $t29128_i10163 = (() => {
                          {
                            const $t29127_i10162 = (() => {
                              {
                                const $t29125_i10160 = (() => {
                                  {
                                    const $t29123_i10158 = ($t29145 * 12.9898);
                                    {
                                      const $t29124_i10159 = (sy * 78.233);
                                      return ($t29123_i10158 + $t29124_i10159);
                                    }
                                  }
                                })();
                                {
                                  const $t29126_i10161 = (seed * 37.719);
                                  return ($t29125_i10160 + $t29126_i10161);
                                }
                              }
                            })();
                            return Math.sin($t29127_i10162);
                          }
                        })();
                        return ($t29128_i10163 * 43758.5453);
                      }
                    })();
                    {
                      const $t29129_i10166 = (() => {
                        {
                          const $t1622_i4025_i10165 = Math.floor(x_i10164);
                          return $t1622_i4025_i10165;
                        }
                      })();
                      return (x_i10164 - $t29129_i10166);
                    }
                  }
                }
              })();
              {
                const r = (() => {
                  {
                    const $t29148 = (rt * rt);
                    {
                      const $t29131_i4031 = (() => {
                        {
                          const $t29130_i4030 = (700. - 240.);
                          return ($t29148 * $t29130_i4030);
                        }
                      })();
                      return (240. + $t29131_i4031);
                    }
                  }
                })();
                {
                  const strength = (() => {
                    {
                      const $t29151 = (() => {
                        {
                          const $t29150 = (() => {
                            {
                              const $t29149 = (sy + 2.);
                              {
                                const x_i10152 = (() => {
                                  {
                                    const $t29128_i10151 = (() => {
                                      {
                                        const $t29127_i10150 = (() => {
                                          {
                                            const $t29125_i10148 = (() => {
                                              {
                                                const $t29123_i10146 = (sx * 12.9898);
                                                {
                                                  const $t29124_i10147 = ($t29149 * 78.233);
                                                  return ($t29123_i10146 + $t29124_i10147);
                                                }
                                              }
                                            })();
                                            {
                                              const $t29126_i10149 = (seed * 37.719);
                                              return ($t29125_i10148 + $t29126_i10149);
                                            }
                                          }
                                        })();
                                        return Math.sin($t29127_i10150);
                                      }
                                    })();
                                    return ($t29128_i10151 * 43758.5453);
                                  }
                                })();
                                {
                                  const $t29129_i10154 = (() => {
                                    {
                                      const $t1622_i4025_i10153 = Math.floor(x_i10152);
                                      return $t1622_i4025_i10153;
                                    }
                                  })();
                                  return (x_i10152 - $t29129_i10154);
                                }
                              }
                            }
                          })();
                          return (0.65 * $t29150);
                        }
                      })();
                      return (0.35 + $t29151);
                    }
                  })();
                  {
                    const $t29154 = (() => {
                      {
                        const $t29152 = (sx + jx);
                        {
                          const $t29153 = (sy + jy);
                          return ({ x: $t29152, y: $t29153, radius: r, strength: strength });
                        }
                      }
                    })();
                    return { $: "Some", _0: $t29154 };
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
      const $f29187 = stars._0;
      const $f29188 = stars._1;
      {
        const rest = $f29188;
        {
          const s = $f29187;
          {
            const $t29185 = (() => {
              {
                const $t29183 = s.x;
                {
                  const $t29184 = s.y;
                  return Perihelion$Nebula$star_cloud($t29183, $t29184, seed);
                }
              }
            })();
            {
              let acc2;
              switch ($t29185.$) {
                case "None": {
                  acc2 = acc;
                  break;
                }
                case "Some": {
                  const $f29186 = $t29185._0;
                  acc2 = (() => {
                    {
                      const c = $f29186;
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
      const $f29201 = stars._0;
      const $f29202 = stars._1;
      {
        const rest = $f29202;
        {
          const s = $f29201;
          {
            const $t29200 = (() => {
              {
                const $t29195_i4050 = (() => {
                  {
                    const $t29193_i4048 = s.y;
                    {
                      const $t29194_i4049 = (cam_y - margin);
                      return ($t29193_i4048 >= $t29194_i4049);
                    }
                  }
                })();
                {
                  const $t29199_i4054 = (() => {
                    {
                      const $t29196_i4051 = s.y;
                      {
                        const $t29198_i4053 = (() => {
                          {
                            const $t29197_i4052 = (cam_y + view_h);
                            return ($t29197_i4052 + margin);
                          }
                        })();
                        return ($t29196_i4051 <= $t29198_i4053);
                      }
                    }
                  })();
                  return ($t29195_i4050 && $t29199_i4054);
                }
              }
            })();
            {
              let acc2;
              if ($t29200 === true) {
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
    const $t29212 = (stars_chained > 0);
    {
      const $t29215 = (() => {
        {
          const $t29214 = march_int_mod(stars_chained, 10);
          return ($t29214 === 0);
        }
      })();
      return ($t29212 && $t29215);
    }
  }
}
const Perihelion$Upgrades$is_milestone$clo = { _0: ($_, stars_chained) => Perihelion$Upgrades$is_milestone(stars_chained) };

function Perihelion$Upgrades$milestone_pool(owned) {
  {
    const $t29217 = (() => {
      {
        const $t29216 = { $: "Homing" };
        return { $: "OffenseWeapon", _0: $t29216 };
      }
    })();
    {
      const $t29219 = (() => {
        {
          const $t29218 = { $: "Spread" };
          return { $: "OffenseWeapon", _0: $t29218 };
        }
      })();
      {
        const $t29220 = { $: "Nil" };
        {
          const $t29221 = { $: "Cons", _0: $t29219, _1: $t29220 };
          {
            const all_weapons = { $: "Cons", _0: $t29217, _1: $t29221 };
            {
              const $t29225 = { $: "$Clo_$lam29222$3795", _0: $lam29222$apply$3795, _1: owned };
              {
                const unowned_weapons = (() => {
                  {
                    const pred_i4056 = $t29225;
                    {
                      const go_i4057 = { $: "$Clo_go$4816", _0: go$apply$4816, _1: pred_i4056 };
                      {
                        const $t342_i4058 = { $: "Nil" };
                        return go$apply$4816(go_i4057, all_weapons, $t342_i4058);
                      }
                    }
                  }
                })();
                {
                  const $t29226 = { $: "OffenseFireRate" };
                  {
                    const $t29227 = { $: "DefenseBulletWard" };
                    {
                      const $t29228 = { $: "DefenseDeflector" };
                      {
                        const $t29229 = { $: "DefenseShield" };
                        {
                          const $t29231 = (() => {
                            {
                              const $t29230 = { $: "StarThrust" };
                              return { $: "SpecialItem", _0: $t29230 };
                            }
                          })();
                          {
                            const $t29233 = (() => {
                              {
                                const $t29232 = { $: "StarJump" };
                                return { $: "SpecialItem", _0: $t29232 };
                              }
                            })();
                            {
                              const $t29235 = (() => {
                                {
                                  const $t29234 = { $: "TrajectoryPreview" };
                                  return { $: "SpecialItem", _0: $t29234 };
                                }
                              })();
                              {
                                const $t29236 = { $: "Nil" };
                                {
                                  const $t29237 = { $: "Cons", _0: $t29235, _1: $t29236 };
                                  {
                                    const $t29238 = { $: "Cons", _0: $t29233, _1: $t29237 };
                                    {
                                      const $t29239 = { $: "Cons", _0: $t29231, _1: $t29238 };
                                      {
                                        const $t29240 = { $: "Cons", _0: $t29229, _1: $t29239 };
                                        {
                                          const $t29241 = { $: "Cons", _0: $t29228, _1: $t29240 };
                                          {
                                            const $t29242 = { $: "Cons", _0: $t29227, _1: $t29241 };
                                            {
                                              const $t29243 = { $: "Cons", _0: $t29226, _1: $t29242 };
                                              {
                                                const go_i10205 = { $: "$Clo_go$4814", _0: go$apply$4814 };
                                                {
                                                  const $t301_i10208 = (() => {
                                                    {
                                                      const go_i4510_i10206 = { $: "$Clo_go$5248", _0: go$apply$5248 };
                                                      {
                                                        const $t293_i4511_i10207 = { $: "Nil" };
                                                        return go$apply$5248(go_i4510_i10206, unowned_weapons, $t293_i4511_i10207);
                                                      }
                                                    }
                                                  })();
                                                  return go$apply$4814(go_i10205, $t301_i10208, $t29243);
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
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
    const $t29244 = (() => {
      {
        const go_i4061 = { $: "$Clo_go$4819", _0: go$apply$4819 };
        {
          const $t548_i4062 = { $: "Nil" };
          return go$apply$4819(go_i4061, xs, idx, $t548_i4062);
        }
      }
    })();
    {
      const $t29245 = (idx + 1);
      {
        const $t29246 = List$drop$List_UpgradeKind$Int(xs, $t29245);
        {
          const go_i10211 = { $: "$Clo_go$4814", _0: go$apply$4814 };
          {
            const $t301_i10214 = (() => {
              {
                const go_i4510_i10212 = { $: "$Clo_go$5248", _0: go$apply$5248 };
                {
                  const $t293_i4511_i10213 = { $: "Nil" };
                  return go$apply$5248(go_i4510_i10212, $t29244, $t293_i4511_i10213);
                }
              }
            })();
            return go$apply$4814(go_i10211, $t301_i10214, $t29246);
          }
        }
      }
    }
  }
}
const Perihelion$Upgrades$remove_upgrade_at$clo = { _0: ($_, xs, idx) => Perihelion$Upgrades$remove_upgrade_at(xs, idx) };

function Perihelion$Upgrades$pick_and_remove(rng, pool) {
  {
    const $p29250 = (() => {
      {
        const $p29061_i10413_i10750_i11077 = (() => {
          {
            const $p15619_i10138_i10408_i10745_i11072 = (() => {
              {
                const $p15616_i1544_i10128_i10399_i10736_i11063 = Random$next_raw(rng);
                {
                  const hi_i1545_i10129_i10400_i10737_i11064 = $p15616_i1544_i10128_i10399_i10736_i11063._0;
                  {
                    const rng2_i1546_i10130_i10401_i10738_i11065 = $p15616_i1544_i10128_i10399_i10736_i11063._1;
                    {
                      const $p15615_i1547_i10131_i10402_i10739_i11066 = Random$next_raw(rng2_i1546_i10130_i10401_i10738_i11065);
                      {
                        const lo_i1548_i10132_i10403_i10740_i11067 = $p15615_i1547_i10131_i10402_i10739_i11066._0;
                        {
                          const rng3_i1549_i10133_i10404_i10741_i11068 = $p15615_i1547_i10131_i10402_i10739_i11066._1;
                          {
                            const $t15614_i1553_i10137_i10407_i10744_i11071 = (() => {
                              {
                                const $t15613_i1552_i10136_i10406_i10743_i11070 = (() => {
                                  {
                                    const $t15611_i1550_i10134_i10405_i10742_i11069 = march_int_and(hi_i1545_i10129_i10400_i10737_i11064, 1048575);
                                    return ($t15611_i1550_i10134_i10405_i10742_i11069 * 4294967296);
                                  }
                                })();
                                return ($t15613_i1552_i10136_i10406_i10743_i11070 + lo_i1548_i10132_i10403_i10740_i11067);
                              }
                            })();
                            return { _0: $t15614_i1553_i10137_i10407_i10744_i11071, _1: rng3_i1549_i10133_i10404_i10741_i11068 };
                          }
                        }
                      }
                    }
                  }
                }
              }
            })();
            {
              const bits_i10139_i10409_i10746_i11073 = $p15619_i10138_i10408_i10745_i11072._0;
              {
                const rng2_i10140_i10410_i10747_i11074 = $p15619_i10138_i10408_i10745_i11072._1;
                {
                  const $t15618_i10142_i10412_i10749_i11076 = (() => {
                    {
                      const $t15617_i10141_i10411_i10748_i11075 = bits_i10139_i10409_i10746_i11073;
                      return ($t15617_i10141_i10411_i10748_i11075 / 4.50359962737e+15);
                    }
                  })();
                  return { _0: $t15618_i10142_i10412_i10749_i11076, _1: rng2_i10140_i10410_i10747_i11074 };
                }
              }
            }
          }
        })();
        {
          const t_i10414_i10751_i11078 = $p29061_i10413_i10750_i11077._0;
          {
            const rng2_i10415_i10752_i11079 = $p29061_i10413_i10750_i11077._1;
            {
              const out_i10416_i10753_i11080 = { _0: rng2_i10415_i10752_i11079, _1: t_i10414_i10751_i11078 };
              return out_i10416_i10753_i11080;
            }
          }
        }
      }
    })();
    {
      const rng2 = $p29250._0;
      {
        const t = $p29250._1;
        {
          const n = (() => {
            {
              const go_i4064 = { $: "$Clo_go$4822", _0: go$apply$4822 };
              return go$apply$4822(go_i4064, pool, 0);
            }
          })();
          {
            const idx = (() => {
              {
                const $t29248 = (() => {
                  {
                    const $t29247 = n;
                    return (t * $t29247);
                  }
                })();
                return Math.trunc($t29248);
              }
            })();
            {
              const clamped = (() => {
                {
                  const $t29249 = (idx >= n);
                  if ($t29249 === true) {
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
    const $t29253 = (() => {
      {
        const $t29251 = (n === 0);
        {
          let $t29252;
          switch (pool.$) {
            case "Nil": {
              $t29252 = true;
              break;
            }
            default: {
              $t29252 = false;
              break;
            }
          }
          return ($t29251 || $t29252);
        }
      }
    })();
    if ($t29253 === true) {
      return { _0: rng, _1: acc };
    } else {
      return (() => {
        {
          const $p29256 = Perihelion$Upgrades$pick_and_remove(rng, pool);
          {
            const rng2 = $p29256._0;
            {
              const picked = $p29256._1;
              {
                const rest = $p29256._2;
                {
                  const $t29254 = (n - 1);
                  {
                    const $t29255 = (() => {
                      return { $: "Cons", _0: picked, _1: acc };
                    })();
                    return Perihelion$Upgrades$draw_n(rng2, rest, $t29254, $t29255);
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
        const $t29257 = Perihelion$Upgrades$milestone_pool(owned_weapons);
        {
          const $t29258 = { $: "Nil" };
          return Perihelion$Upgrades$draw_n(rng, $t29257, 3, $t29258);
        }
      }
      break;
    }
    case "Some": {
      const $f29267 = current_special._0;
      {
        const k = $f29267;
        {
          const $t29259 = Perihelion$Upgrades$milestone_pool(owned_weapons);
          {
            const $t29262 = (() => {
              return { $: "$Clo_$lam29260$3796", _0: $lam29260$apply$3796, _1: k };
            })();
            {
              const pool = (() => {
                {
                  const pred_i4068 = $t29262;
                  {
                    const go_i4069 = { $: "$Clo_go$4816", _0: go$apply$4816, _1: pred_i4068 };
                    {
                      const $t342_i4070 = { $: "Nil" };
                      return go$apply$4816(go_i4069, $t29259, $t342_i4070);
                    }
                  }
                }
              })();
              {
                const $p29266 = (() => {
                  {
                    const $t29263 = { $: "Nil" };
                    return Perihelion$Upgrades$draw_n(rng, pool, 2, $t29263);
                  }
                })();
                {
                  const rng2 = $p29266._0;
                  {
                    const two = $p29266._1;
                    {
                      const $t29264 = { $: "SpecialItem", _0: k };
                      {
                        const $t29265 = (() => {
                          return { $: "Cons", _0: $t29264, _1: two };
                        })();
                        return { _0: rng2, _1: $t29265 };
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
    const $p29269 = (() => {
      {
        const $t29268 = Perihelion$Upgrades$milestone_pool(owned_weapons);
        return Perihelion$Upgrades$pick_and_remove(rng, $t29268);
      }
    })();
    {
      const rng2 = $p29269._0;
      {
        const picked = $p29269._1;
        return { _0: rng2, _1: picked };
      }
    }
  }
}
const Perihelion$Upgrades$roll_one$clo = { _0: ($_, rng, owned_weapons, current_special) => Perihelion$Upgrades$roll_one(rng, owned_weapons, current_special) };

function boot_seed() {
  {
    const $t29272 = (() => {
      {
        const $t29271 = (() => {
          {
            const $t29270 = {  };
            return march_unix_time();
          }
        })();
        return ($t29271 * 1000000.);
      }
    })();
    return Math.trunc($t29272);
  }
}
const boot_seed$clo = { _0: ($_) => boot_seed() };

function spawn_burst_particles(x, y, t, i, acc) {
  {
    const $t29283 = (i >= 10);
    if ($t29283 === true) {
      return acc;
    } else {
      return (() => {
        {
          const seed = (() => {
            {
              const $t29285 = (() => {
                {
                  const $t29284 = i;
                  return ($t29284 * 7.);
                }
              })();
              return (t + $t29285);
            }
          })();
          {
            const a = (() => {
              {
                const $t29286 = (() => {
                  {
                    const x_i10239 = (() => {
                      {
                        const $t29280_i10238 = (() => {
                          {
                            const $t29279_i10237 = (() => {
                              {
                                const $t29277_i10235 = (seed * 12.9898);
                                {
                                  const $t29278_i10236 = (1. * 78.233);
                                  return ($t29277_i10235 + $t29278_i10236);
                                }
                              }
                            })();
                            return Math.sin($t29279_i10237);
                          }
                        })();
                        return ($t29280_i10238 * 43758.5453);
                      }
                    })();
                    {
                      const $t29281_i10241 = (() => {
                        {
                          const $t1622_i4072_i10240 = Math.floor(x_i10239);
                          return $t1622_i4072_i10240;
                        }
                      })();
                      return (x_i10239 - $t29281_i10241);
                    }
                  }
                })();
                return ($t29286 * 6.28318530718);
              }
            })();
            {
              const speed = (() => {
                {
                  const $t29289 = (() => {
                    {
                      const $t29288 = (() => {
                        {
                          const x_i10230 = (() => {
                            {
                              const $t29280_i10229 = (() => {
                                {
                                  const $t29279_i10228 = (() => {
                                    {
                                      const $t29277_i10226 = (seed * 12.9898);
                                      {
                                        const $t29278_i10227 = (2. * 78.233);
                                        return ($t29277_i10226 + $t29278_i10227);
                                      }
                                    }
                                  })();
                                  return Math.sin($t29279_i10228);
                                }
                              })();
                              return ($t29280_i10229 * 43758.5453);
                            }
                          })();
                          {
                            const $t29281_i10232 = (() => {
                              {
                                const $t1622_i4072_i10231 = Math.floor(x_i10230);
                                return $t1622_i4072_i10231;
                              }
                            })();
                            return (x_i10230 - $t29281_i10232);
                          }
                        }
                      })();
                      return ($t29288 * 90.);
                    }
                  })();
                  return (40. + $t29289);
                }
              })();
              {
                const life = (() => {
                  {
                    const $t29293 = (() => {
                      {
                        const $t29292 = (() => {
                          {
                            const $t29291 = (() => {
                              {
                                const x_i10221 = (() => {
                                  {
                                    const $t29280_i10220 = (() => {
                                      {
                                        const $t29279_i10219 = (() => {
                                          {
                                            const $t29277_i10217 = (seed * 12.9898);
                                            {
                                              const $t29278_i10218 = (3. * 78.233);
                                              return ($t29277_i10217 + $t29278_i10218);
                                            }
                                          }
                                        })();
                                        return Math.sin($t29279_i10219);
                                      }
                                    })();
                                    return ($t29280_i10220 * 43758.5453);
                                  }
                                })();
                                {
                                  const $t29281_i10223 = (() => {
                                    {
                                      const $t1622_i4072_i10222 = Math.floor(x_i10221);
                                      return $t1622_i4072_i10222;
                                    }
                                  })();
                                  return (x_i10221 - $t29281_i10223);
                                }
                              }
                            })();
                            return (0.4 * $t29291);
                          }
                        })();
                        return (0.6 + $t29292);
                      }
                    })();
                    return (0.5 * $t29293);
                  }
                })();
                {
                  const p = (() => {
                    {
                      const $t29295 = (() => {
                        {
                          const $t29294 = Math.cos(a);
                          return ($t29294 * speed);
                        }
                      })();
                      {
                        const $t29297 = (() => {
                          {
                            const $t29296 = Math.sin(a);
                            return ($t29296 * speed);
                          }
                        })();
                        return ({ x: x, y: y, vx: $t29295, vy: $t29297, life: life, max_life: life });
                      }
                    }
                  })();
                  {
                    const $t29298 = (i + 1);
                    {
                      const $t29299 = { $: "Cons", _0: p, _1: acc };
                      return spawn_burst_particles(x, y, t, $t29298, $t29299);
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
      const $f29302 = bursts._0;
      const $f29303 = bursts._1;
      {
        const rest = (() => {
          return $f29303;
        })();
        {
          const pt = (() => {
            return $f29302;
          })();
          {
            const x = pt._0;
            {
              const y = pt._1;
              {
                const $t29300 = spawn_burst_particles(x, y, t, 0, acc);
                return spawn_bursts(rest, t, $t29300);
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
      const $f29329 = flash._0;
      {
        const f = $f29329;
        {
          const x = f._0;
          {
            const y = f._1;
            {
              const tr = f._2;
              {
                const tr2 = (tr - dt_s);
                {
                  const $t29326 = (tr2 > 0.);
                  if ($t29326 === true) {
                    return (() => {
                      {
                        const $t29327 = { _0: x, _1: y, _2: tr2 };
                        return { $: "Some", _0: $t29327 };
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
        const $t29330 = fx.t;
        return ($t29330 + dt_s);
      }
    })();
    {
      const $t29331 = (() => {
        {
          const $t29905_i4092 = game.phase;
          switch ($t29905_i4092.$) {
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
        if ($t29331 === true) {
          trail2 = (() => {
            {
              const $t29332 = fx.trail;
              {
                const $t29333 = game.ball_x;
                {
                  const $t29334 = game.ball_y;
                  {
                    const $t29335 = { _0: $t29333, _1: $t29334 };
                    {
                      const $t29324_i10255 = { $: "Cons", _0: $t29335, _1: $t29332 };
                      {
                        const go_i4087_i10256 = { $: "$Clo_go$4828", _0: go$apply$4828 };
                        {
                          const $t548_i4088_i10257 = { $: "Nil" };
                          return go$apply$4828(go_i4087_i10256, $t29324_i10255, 14, $t548_i4088_i10257);
                        }
                      }
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
          const $t29336 = game.fx_bursts;
          {
            const $t29337 = fx.particles;
            {
              const $t29338 = (() => {
                return spawn_bursts($t29336, t2, $t29337);
              })();
              {
                const particles2 = (() => {
                  {
                    const $t29319_i10244 = { $: "$Clo_$lam29318$3798", _0: $lam29318$apply$3798, _1: dt_s };
                    {
                      const $t29320_i10248 = (() => {
                        {
                          const f_i4082_i10245 = $t29319_i10244;
                          {
                            const go_i4083_i10246 = { $: "$Clo_go$4826", _0: go$apply$4826, _1: f_i4082_i10245 };
                            {
                              const $t310_i4084_i10247 = { $: "Nil" };
                              return go$apply$4826(go_i4083_i10246, $t29338, $t310_i4084_i10247);
                            }
                          }
                        }
                      })();
                      {
                        const $t29323_i10249 = { $: "$Clo_$lam29321$3799", _0: $lam29321$apply$3799 };
                        {
                          const pred_i4078_i10250 = $t29323_i10249;
                          {
                            const go_i4079_i10251 = { $: "$Clo_go$4824", _0: go$apply$4824, _1: pred_i4078_i10250 };
                            {
                              const $t342_i4080_i10252 = { $: "Nil" };
                              return go$apply$4824(go_i4079_i10251, $t29320_i10248, $t342_i4080_i10252);
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
                      const $t29339 = fx.flash;
                      return step_flash($t29339, dt_s);
                    }
                  })();
                  {
                    const flash2 = (() => {
                      {
                        const $t29340 = game.capture_flash;
                        switch ($t29340.$) {
                          case "None": {
                            return flash1;
                            break;
                          }
                          case "Some": {
                            const $f29344 = $t29340._0;
                            {
                              const pt = (() => {
                                return $f29344;
                              })();
                              {
                                const x = pt._0;
                                {
                                  const y = pt._1;
                                  {
                                    const $t29342 = { _0: x, _1: y, _2: 0.45 };
                                    return { $: "Some", _0: $t29342 };
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
      const $f29354 = trail._0;
      const $f29355 = trail._1;
      {
        const rest = (() => {
          return $f29355;
        })();
        {
          const pt = (() => {
            return $f29354;
          })();
          {
            const x = pt._0;
            {
              const y = pt._1;
              {
                const f = (() => {
                  {
                    const $t29347 = (() => {
                      {
                        const $t29345 = i;
                        {
                          const $t29346 = n;
                          return ($t29345 / $t29346);
                        }
                      }
                    })();
                    return (1. - $t29347);
                  }
                })();
                (() => {
                  {
                    const $t29348 = (f * 0.28);
                    return Canvas$set_global_alpha(ctx, $t29348);
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
                    const $t29350 = (() => {
                      {
                        const $t29349 = (2.5 * f);
                        return (1. + $t29349);
                      }
                    })();
                    return Canvas$arc(ctx, x, y, $t29350, 0., 6.28318530718);
                  }
                })();
                (() => {
                  return Canvas$fill(ctx);
                })();
                {
                  const $t29352 = (i + 1);
                  return draw_trail(ctx, rest, $t29352, n);
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
      const $f29367 = particles._0;
      const $f29368 = particles._1;
      {
        const rest = (() => {
          return $f29368;
        })();
        {
          const p = (() => {
            return $f29367;
          })();
          {
            const f = (() => {
              {
                const $t29360 = p.life;
                {
                  const $t29361 = p.max_life;
                  return ($t29360 / $t29361);
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
                const $t29362 = p.x;
                {
                  const $t29363 = p.y;
                  {
                    const $t29365 = (() => {
                      {
                        const $t29364 = (1.5 * f);
                        return (0.5 + $t29364);
                      }
                    })();
                    return Canvas$arc(ctx, $t29362, $t29363, $t29365, 0., 6.28318530718);
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
      const $f29383 = flash._0;
      {
        const f = (() => {
          return $f29383;
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
                    const $t29374 = (tr / 0.45);
                    return (1. - $t29374);
                  }
                })();
                {
                  const r = (() => {
                    {
                      const $t29375 = (prog * 60.);
                      return (8. + $t29375);
                    }
                  })();
                  (() => {
                    {
                      const $t29377 = (() => {
                        {
                          const $t29376 = (1. - prog);
                          return ($t29376 * 0.7);
                        }
                      })();
                      return Canvas$set_global_alpha(ctx, $t29377);
                    }
                  })();
                  (() => {
                    return Canvas$set_stroke_style(ctx, "#ffffff");
                  })();
                  (() => {
                    {
                      const $t29380 = (() => {
                        {
                          const $t29379 = (() => {
                            {
                              const $t29378 = (1. - prog);
                              return (2.5 * $t29378);
                            }
                          })();
                          return ($t29379 + 0.5);
                        }
                      })();
                      return Canvas$set_line_width(ctx, $t29380);
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
        const $t29388 = (() => {
          {
            const $t29387 = s.x;
            return ($t29387 + 1.);
          }
        })();
        {
          const $t29390 = (() => {
            {
              const $t29389 = s.y;
              return ($t29389 + 1.);
            }
          })();
          {
            const x_i10273 = (() => {
              {
                const $t29280_i10272 = (() => {
                  {
                    const $t29279_i10271 = (() => {
                      {
                        const $t29277_i10269 = ($t29388 * 12.9898);
                        {
                          const $t29278_i10270 = ($t29390 * 78.233);
                          return ($t29277_i10269 + $t29278_i10270);
                        }
                      }
                    })();
                    return Math.sin($t29279_i10271);
                  }
                })();
                return ($t29280_i10272 * 43758.5453);
              }
            })();
            {
              const $t29281_i10275 = (() => {
                {
                  const $t1622_i4072_i10274 = Math.floor(x_i10273);
                  return $t1622_i4072_i10274;
                }
              })();
              return (x_i10273 - $t29281_i10275);
            }
          }
        }
      }
    })();
    {
      const $t29391 = (r < 0.34);
      if ($t29391 === true) {
        return 0;
      } else {
        return (() => {
          {
            const $t29392 = (r < 0.67);
            if ($t29392 === true) {
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
    const $t29411 = (() => {
      {
        const $t29410 = (() => {
          {
            const $t29409 = (() => {
              {
                const $t29406 = (() => {
                  {
                    const $t29405 = s.x;
                    return ($t29405 + 4.);
                  }
                })();
                {
                  const $t29408 = (() => {
                    {
                      const $t29407 = s.y;
                      return ($t29407 + 4.);
                    }
                  })();
                  {
                    const x_i10300 = (() => {
                      {
                        const $t29280_i10299 = (() => {
                          {
                            const $t29279_i10298 = (() => {
                              {
                                const $t29277_i10296 = ($t29406 * 12.9898);
                                {
                                  const $t29278_i10297 = ($t29408 * 78.233);
                                  return ($t29277_i10296 + $t29278_i10297);
                                }
                              }
                            })();
                            return Math.sin($t29279_i10298);
                          }
                        })();
                        return ($t29280_i10299 * 43758.5453);
                      }
                    })();
                    {
                      const $t29281_i10302 = (() => {
                        {
                          const $t1622_i4072_i10301 = Math.floor(x_i10300);
                          return $t1622_i4072_i10301;
                        }
                      })();
                      return (x_i10300 - $t29281_i10302);
                    }
                  }
                }
              }
            })();
            return ($t29409 * 4.);
          }
        })();
        return Math.trunc($t29410);
      }
    })();
    return (2 + $t29411);
  }
}
const dot_count$clo = { _0: ($_, s) => dot_count(s) };

function draw_pulse_ring(ctx, s, pulse) {
  (() => {
    {
      const $t29418 = (0.1 * pulse);
      return Canvas$set_global_alpha(ctx, $t29418);
    }
  })();
  (() => {
    return Canvas$set_stroke_style(ctx, "#cfcfcf");
  })();
  (() => {
    {
      const $t29420 = (() => {
        {
          const $t29419 = (0.6 * pulse);
          return (1. + $t29419);
        }
      })();
      return Canvas$set_line_width(ctx, $t29420);
    }
  })();
  (() => {
    return Canvas$begin_path(ctx);
  })();
  (() => {
    {
      const $t29421 = s.x;
      {
        const $t29422 = s.y;
        {
          const $t29423 = s.capture_radius;
          return Canvas$arc(ctx, $t29421, $t29422, $t29423, 0., 6.28318530718);
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
      const $t29426 = (() => {
        {
          const $t29425 = (0.035 * pulse);
          return (0.025 + $t29425);
        }
      })();
      return Canvas$set_global_alpha(ctx, $t29426);
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
      const $t29427 = s.x;
      {
        const $t29428 = s.y;
        {
          const $t29432 = (() => {
            {
              const $t29429 = s.radius;
              {
                const $t29431 = (() => {
                  {
                    const $t29430 = (0.9 * pulse);
                    return (1.6 + $t29430);
                  }
                })();
                return ($t29429 * $t29431);
              }
            }
          })();
          return Canvas$arc(ctx, $t29427, $t29428, $t29432, 0., 6.28318530718);
        }
      }
    }
  })();
  return Canvas$fill(ctx);
}
const draw_pulse_halo$clo = { _0: ($_, ctx, s, pulse) => draw_pulse_halo(ctx, s, pulse) };

function draw_pulse_particle(ctx, s, t, n, i) {
  {
    const $t29434 = (i >= n);
    if ($t29434 === true) {
      return {  };
    } else {
      return (() => {
        {
          const a = (() => {
            {
              const $t29438 = (() => {
                {
                  const $t29436 = (() => {
                    {
                      const $t29435 = (() => {
                        {
                          const $t29417_i10557 = (() => {
                            {
                              const $t29416_i10556 = (() => {
                                {
                                  const $t29413_i10546 = (() => {
                                    {
                                      const $t29412_i10545 = s.x;
                                      return ($t29412_i10545 + 5.);
                                    }
                                  })();
                                  {
                                    const $t29415_i10548 = (() => {
                                      {
                                        const $t29414_i10547 = s.y;
                                        return ($t29414_i10547 + 5.);
                                      }
                                    })();
                                    {
                                      const x_i10309_i10553 = (() => {
                                        {
                                          const $t29280_i10308_i10552 = (() => {
                                            {
                                              const $t29279_i10307_i10551 = (() => {
                                                {
                                                  const $t29277_i10305_i10549 = ($t29413_i10546 * 12.9898);
                                                  {
                                                    const $t29278_i10306_i10550 = ($t29415_i10548 * 78.233);
                                                    return ($t29277_i10305_i10549 + $t29278_i10306_i10550);
                                                  }
                                                }
                                              })();
                                              return Math.sin($t29279_i10307_i10551);
                                            }
                                          })();
                                          return ($t29280_i10308_i10552 * 43758.5453);
                                        }
                                      })();
                                      {
                                        const $t29281_i10311_i10555 = (() => {
                                          {
                                            const $t1622_i4072_i10310_i10554 = Math.floor(x_i10309_i10553);
                                            return $t1622_i4072_i10310_i10554;
                                          }
                                        })();
                                        return (x_i10309_i10553 - $t29281_i10311_i10555);
                                      }
                                    }
                                  }
                                }
                              })();
                              return ($t29416_i10556 * 2.4);
                            }
                          })();
                          return (0.4 + $t29417_i10557);
                        }
                      })();
                      return (t * $t29435);
                    }
                  })();
                  {
                    const $t29437 = (() => {
                      {
                        const $t29403_i10543 = (() => {
                          {
                            const $t29400_i10533 = (() => {
                              {
                                const $t29399_i10532 = s.x;
                                return ($t29399_i10532 + 3.);
                              }
                            })();
                            {
                              const $t29402_i10535 = (() => {
                                {
                                  const $t29401_i10534 = s.y;
                                  return ($t29401_i10534 + 3.);
                                }
                              })();
                              {
                                const x_i10291_i10540 = (() => {
                                  {
                                    const $t29280_i10290_i10539 = (() => {
                                      {
                                        const $t29279_i10289_i10538 = (() => {
                                          {
                                            const $t29277_i10287_i10536 = ($t29400_i10533 * 12.9898);
                                            {
                                              const $t29278_i10288_i10537 = ($t29402_i10535 * 78.233);
                                              return ($t29277_i10287_i10536 + $t29278_i10288_i10537);
                                            }
                                          }
                                        })();
                                        return Math.sin($t29279_i10289_i10538);
                                      }
                                    })();
                                    return ($t29280_i10290_i10539 * 43758.5453);
                                  }
                                })();
                                {
                                  const $t29281_i10293_i10542 = (() => {
                                    {
                                      const $t1622_i4072_i10292_i10541 = Math.floor(x_i10291_i10540);
                                      return $t1622_i4072_i10292_i10541;
                                    }
                                  })();
                                  return (x_i10291_i10540 - $t29281_i10293_i10542);
                                }
                              }
                            }
                          }
                        })();
                        return ($t29403_i10543 * 6.28318530718);
                      }
                    })();
                    return ($t29436 + $t29437);
                  }
                }
              })();
              {
                const $t29443 = (() => {
                  {
                    const $t29439 = i;
                    {
                      const $t29442 = (() => {
                        {
                          const $t29441 = n;
                          return (6.28318530718 / $t29441);
                        }
                      })();
                      return ($t29439 * $t29442);
                    }
                  }
                })();
                return ($t29438 + $t29443);
              }
            }
          })();
          {
            const r = (() => {
              {
                const $t29444 = s.radius;
                return ($t29444 * 1.8);
              }
            })();
            {
              const px = (() => {
                {
                  const $t29445 = s.x;
                  {
                    const $t29447 = (() => {
                      {
                        const $t29446 = Math.cos(a);
                        return ($t29446 * r);
                      }
                    })();
                    return ($t29445 + $t29447);
                  }
                }
              })();
              {
                const py = (() => {
                  {
                    const $t29448 = s.y;
                    {
                      const $t29450 = (() => {
                        {
                          const $t29449 = Math.sin(a);
                          return ($t29449 * r);
                        }
                      })();
                      return ($t29448 + $t29450);
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
                  const $t29452 = (i + 1);
                  return draw_pulse_particle(ctx, s, t, n, $t29452);
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
      const $f29461 = orbits._0;
      const $f29462 = orbits._1;
      {
        const $jp_clo29468 = (() => {
          return { $: "$Clo_$jp29467$3802", _0: $jp29467$apply$3802, _1: $f29461, _2: $f29462, _3: ctx, _4: s };
        })();
        switch ($f29462.$) {
          case "Nil": {
            {
              const o = $f29461;
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
                  const $t29453 = s.x;
                  {
                    const $t29454 = s.y;
                    {
                      const $t29455 = o.radius;
                      return Canvas$arc(ctx, $t29453, $t29454, $t29455, 0., 6.28318530718);
                    }
                  }
                }
              })();
              return Canvas$stroke(ctx);
            }
            break;
          }
          default: {
            return $jp29467$apply$3802($jp_clo29468);
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
      const $f29484 = aim._0;
      {
        const a = (() => {
          return $f29484;
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
                      const $t29471 = s.x;
                      return ($t29471 - px);
                    }
                  })();
                  {
                    const dy = (() => {
                      {
                        const $t29472 = s.y;
                        return ($t29472 - py);
                      }
                    })();
                    {
                      const range = (() => {
                        {
                          const $t29473 = s.capture_radius;
                          return ($t29473 * 4.);
                        }
                      })();
                      {
                        const $t29477 = (() => {
                          {
                            const $t29476 = (() => {
                              {
                                const $t29474 = (vx * dx);
                                {
                                  const $t29475 = (vy * dy);
                                  return ($t29474 + $t29475);
                                }
                              }
                            })();
                            return ($t29476 > 0.);
                          }
                        })();
                        {
                          const $t29482 = (() => {
                            {
                              const $t29480 = (() => {
                                {
                                  const $t29478 = (dx * dx);
                                  {
                                    const $t29479 = (dy * dy);
                                    return ($t29478 + $t29479);
                                  }
                                }
                              })();
                              {
                                const $t29481 = (range * range);
                                return ($t29480 < $t29481);
                              }
                            }
                          })();
                          return ($t29477 && $t29482);
                        }
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
        const $t29487 = (() => {
          {
            const $t29486 = (() => {
              {
                const $t29485 = (t * 6.);
                return Math.sin($t29485);
              }
            })();
            return (0.5 * $t29486);
          }
        })();
        return (0.5 + $t29487);
      }
    })();
    (() => {
      {
        const $t29489 = (() => {
          {
            const $t29488 = (0.45 * pulse);
            return (0.3 + $t29488);
          }
        })();
        return Canvas$set_global_alpha(ctx, $t29489);
      }
    })();
    (() => {
      return Canvas$set_stroke_style(ctx, "#ffffff");
    })();
    (() => {
      {
        const $t29491 = (() => {
          {
            const $t29490 = (1.6 * pulse);
            return (1.2 + $t29490);
          }
        })();
        return Canvas$set_line_width(ctx, $t29491);
      }
    })();
    (() => {
      return Canvas$begin_path(ctx);
    })();
    (() => {
      {
        const $t29492 = s.x;
        {
          const $t29493 = s.y;
          {
            const $t29494 = s.capture_radius;
            return Canvas$arc(ctx, $t29492, $t29493, $t29494, 0., 6.28318530718);
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
      const $t29496 = s.orbits;
      return draw_orbit_rings(ctx, s, $t29496);
    }
  })();
  (() => {
    {
      const $t29497 = (() => {
        {
          const $t29386_i10595 = (() => {
            {
              const $t29384_i10586 = s.x;
              {
                const $t29385_i10587 = s.y;
                {
                  const x_i10264_i10592 = (() => {
                    {
                      const $t29280_i10263_i10591 = (() => {
                        {
                          const $t29279_i10262_i10590 = (() => {
                            {
                              const $t29277_i10260_i10588 = ($t29384_i10586 * 12.9898);
                              {
                                const $t29278_i10261_i10589 = ($t29385_i10587 * 78.233);
                                return ($t29277_i10260_i10588 + $t29278_i10261_i10589);
                              }
                            }
                          })();
                          return Math.sin($t29279_i10262_i10590);
                        }
                      })();
                      return ($t29280_i10263_i10591 * 43758.5453);
                    }
                  })();
                  {
                    const $t29281_i10266_i10594 = (() => {
                      {
                        const $t1622_i4072_i10265_i10593 = Math.floor(x_i10264_i10592);
                        return $t1622_i4072_i10265_i10593;
                      }
                    })();
                    return (x_i10264_i10592 - $t29281_i10266_i10594);
                  }
                }
              }
            }
          })();
          return ($t29386_i10595 < 0.8);
        }
      })();
      if ($t29497 === true) {
        return (() => {
          {
            const pulse = (() => {
              {
                const $t29503 = (() => {
                  {
                    const $t29502 = (() => {
                      {
                        const $t29501 = (() => {
                          {
                            const $t29499 = (() => {
                              {
                                const $t29498 = (() => {
                                  {
                                    const $t29398_i10584 = (() => {
                                      {
                                        const $t29397_i10583 = (() => {
                                          {
                                            const $t29394_i10573 = (() => {
                                              {
                                                const $t29393_i10572 = s.x;
                                                return ($t29393_i10572 + 2.);
                                              }
                                            })();
                                            {
                                              const $t29396_i10575 = (() => {
                                                {
                                                  const $t29395_i10574 = s.y;
                                                  return ($t29395_i10574 + 2.);
                                                }
                                              })();
                                              {
                                                const x_i10282_i10580 = (() => {
                                                  {
                                                    const $t29280_i10281_i10579 = (() => {
                                                      {
                                                        const $t29279_i10280_i10578 = (() => {
                                                          {
                                                            const $t29277_i10278_i10576 = ($t29394_i10573 * 12.9898);
                                                            {
                                                              const $t29278_i10279_i10577 = ($t29396_i10575 * 78.233);
                                                              return ($t29277_i10278_i10576 + $t29278_i10279_i10577);
                                                            }
                                                          }
                                                        })();
                                                        return Math.sin($t29279_i10280_i10578);
                                                      }
                                                    })();
                                                    return ($t29280_i10281_i10579 * 43758.5453);
                                                  }
                                                })();
                                                {
                                                  const $t29281_i10284_i10582 = (() => {
                                                    {
                                                      const $t1622_i4072_i10283_i10581 = Math.floor(x_i10282_i10580);
                                                      return $t1622_i4072_i10283_i10581;
                                                    }
                                                  })();
                                                  return (x_i10282_i10580 - $t29281_i10284_i10582);
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        return ($t29397_i10583 * 1.8);
                                      }
                                    })();
                                    return (0.6 + $t29398_i10584);
                                  }
                                })();
                                return (t * $t29498);
                              }
                            })();
                            {
                              const $t29500 = (() => {
                                {
                                  const $t29403_i10570 = (() => {
                                    {
                                      const $t29400_i10560 = (() => {
                                        {
                                          const $t29399_i10559 = s.x;
                                          return ($t29399_i10559 + 3.);
                                        }
                                      })();
                                      {
                                        const $t29402_i10562 = (() => {
                                          {
                                            const $t29401_i10561 = s.y;
                                            return ($t29401_i10561 + 3.);
                                          }
                                        })();
                                        {
                                          const x_i10291_i10567 = (() => {
                                            {
                                              const $t29280_i10290_i10566 = (() => {
                                                {
                                                  const $t29279_i10289_i10565 = (() => {
                                                    {
                                                      const $t29277_i10287_i10563 = ($t29400_i10560 * 12.9898);
                                                      {
                                                        const $t29278_i10288_i10564 = ($t29402_i10562 * 78.233);
                                                        return ($t29277_i10287_i10563 + $t29278_i10288_i10564);
                                                      }
                                                    }
                                                  })();
                                                  return Math.sin($t29279_i10289_i10565);
                                                }
                                              })();
                                              return ($t29280_i10290_i10566 * 43758.5453);
                                            }
                                          })();
                                          {
                                            const $t29281_i10293_i10569 = (() => {
                                              {
                                                const $t1622_i4072_i10292_i10568 = Math.floor(x_i10291_i10567);
                                                return $t1622_i4072_i10292_i10568;
                                              }
                                            })();
                                            return (x_i10291_i10567 - $t29281_i10293_i10569);
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  return ($t29403_i10570 * 6.28318530718);
                                }
                              })();
                              return ($t29499 + $t29500);
                            }
                          }
                        })();
                        return Math.sin($t29501);
                      }
                    })();
                    return (0.5 * $t29502);
                  }
                })();
                return (0.5 + $t29503);
              }
            })();
            {
              const $t29504 = pulse_style(s);
              if ($t29504 === 0) {
                return (() => {
                  {
                    const $jp_clo29507 = (() => {
                      return { $: "$Clo_$jp29506$3805", _0: $jp29506$apply$3805, _1: ctx, _2: s, _3: t };
                    })();
                    return draw_pulse_ring(ctx, s, pulse);
                  }
                })();
              } else if ($t29504 === 1) {
                return (() => {
                  {
                    const $jp_clo29509 = (() => {
                      return { $: "$Clo_$jp29508$3806", _0: $jp29508$apply$3806, _1: ctx, _2: s, _3: t };
                    })();
                    return draw_pulse_halo(ctx, s, pulse);
                  }
                })();
              } else {
                return (() => {
                  {
                    const $t29505 = dot_count(s);
                    return draw_pulse_particle(ctx, s, t, $t29505, 0);
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
      const $t29510 = star_targeted(s, aim);
      if ($t29510 === true) {
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
      const $t29511 = s.x;
      {
        const $t29512 = s.y;
        {
          const $t29513 = s.radius;
          return Canvas$arc(ctx, $t29511, $t29512, $t29513, 0., 6.28318530718);
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
            const $t29521 = (() => {
              {
                const $t29520 = (seed * 37.719);
                return (fx + $t29520);
              }
            })();
            {
              const $t29523 = (() => {
                {
                  const $t29522 = (seed * 12.9898);
                  return (fy - $t29522);
                }
              })();
              {
                const x_i10336 = (() => {
                  {
                    const $t29518_i10335 = (() => {
                      {
                        const $t29517_i10334 = (() => {
                          {
                            const $t29515_i10332 = ($t29521 * 12.9898);
                            {
                              const $t29516_i10333 = ($t29523 * 78.233);
                              return ($t29515_i10332 + $t29516_i10333);
                            }
                          }
                        })();
                        return Math.sin($t29517_i10334);
                      }
                    })();
                    return ($t29518_i10335 * 43758.5453);
                  }
                })();
                {
                  const $t29519_i10338 = (() => {
                    {
                      const $t1622_i4103_i10337 = Math.floor(x_i10336);
                      return $t1622_i4103_i10337;
                    }
                  })();
                  return (x_i10336 - $t29519_i10338);
                }
              }
            }
          }
        })();
        {
          const h2 = (() => {
            {
              const $t29526 = (() => {
                {
                  const $t29524 = (fy * 3.271);
                  {
                    const $t29525 = (seed * 71.238);
                    return ($t29524 - $t29525);
                  }
                }
              })();
              {
                const $t29529 = (() => {
                  {
                    const $t29527 = (fx * 1.373);
                    {
                      const $t29528 = (seed * 5.113);
                      return ($t29527 + $t29528);
                    }
                  }
                })();
                {
                  const x_i10327 = (() => {
                    {
                      const $t29518_i10326 = (() => {
                        {
                          const $t29517_i10325 = (() => {
                            {
                              const $t29515_i10323 = ($t29526 * 12.9898);
                              {
                                const $t29516_i10324 = ($t29529 * 78.233);
                                return ($t29515_i10323 + $t29516_i10324);
                              }
                            }
                          })();
                          return Math.sin($t29517_i10325);
                        }
                      })();
                      return ($t29518_i10326 * 43758.5453);
                    }
                  })();
                  {
                    const $t29519_i10329 = (() => {
                      {
                        const $t1622_i4103_i10328 = Math.floor(x_i10327);
                        return $t1622_i4103_i10328;
                      }
                    })();
                    return (x_i10327 - $t29519_i10329);
                  }
                }
              }
            }
          })();
          {
            const $t29532 = (() => {
              {
                const $t29530 = (h1 * 269.5);
                {
                  const $t29531 = (h2 * 183.3);
                  return ($t29530 + $t29531);
                }
              }
            })();
            {
              const $t29536 = (() => {
                {
                  const $t29535 = (() => {
                    {
                      const $t29533 = (fx * 0.618);
                      {
                        const $t29534 = (fy * 0.573);
                        return ($t29533 + $t29534);
                      }
                    }
                  })();
                  return ($t29535 + seed);
                }
              })();
              {
                const x_i10318 = (() => {
                  {
                    const $t29518_i10317 = (() => {
                      {
                        const $t29517_i10316 = (() => {
                          {
                            const $t29515_i10314 = ($t29532 * 12.9898);
                            {
                              const $t29516_i10315 = ($t29536 * 78.233);
                              return ($t29515_i10314 + $t29516_i10315);
                            }
                          }
                        })();
                        return Math.sin($t29517_i10316);
                      }
                    })();
                    return ($t29518_i10317 * 43758.5453);
                  }
                })();
                {
                  const $t29519_i10320 = (() => {
                    {
                      const $t1622_i4103_i10319 = Math.floor(x_i10318);
                      return $t1622_i4103_i10319;
                    }
                  })();
                  return (x_i10318 - $t29519_i10320);
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
      const $t29538 = (h > 0.5);
      if ($t29538 === true) {
        return {  };
      } else {
        return (() => {
          {
            const jx = (() => {
              {
                const $t29539 = (gy + 1000);
                return bg_hash(gx, $t29539, seed);
              }
            })();
            {
              const jy = (() => {
                {
                  const $t29540 = (gx + 1000);
                  return bg_hash($t29540, gy, seed);
                }
              })();
              {
                const x = (() => {
                  {
                    const $t29542 = (() => {
                      {
                        const $t29541 = gx;
                        return ($t29541 * cell);
                      }
                    })();
                    {
                      const $t29543 = (jx * cell);
                      return ($t29542 + $t29543);
                    }
                  }
                })();
                {
                  const y = (() => {
                    {
                      const $t29545 = (() => {
                        {
                          const $t29544 = gy;
                          return ($t29544 * cell);
                        }
                      })();
                      {
                        const $t29546 = (jy * cell);
                        return ($t29545 + $t29546);
                      }
                    }
                  })();
                  {
                    const br = (() => {
                      {
                        const $t29550 = (() => {
                          {
                            const $t29549 = (() => {
                              {
                                const $t29547 = (gx + 2000);
                                {
                                  const $t29548 = (gy + 2000);
                                  return bg_hash($t29547, $t29548, seed);
                                }
                              }
                            })();
                            return (0.45 * $t29549);
                          }
                        })();
                        return (0.12 + $t29550);
                      }
                    })();
                    {
                      const st = (() => {
                        {
                          const $t29551 = (gx - 2000);
                          {
                            const $t29552 = (gy - 2000);
                            return bg_hash($t29551, $t29552, seed);
                          }
                        }
                      })();
                      {
                        const sz = (() => {
                          {
                            const $t29554 = (() => {
                              {
                                const $t29553 = (1.8 * st);
                                return ($t29553 * st);
                              }
                            })();
                            return (1. + $t29554);
                          }
                        })();
                        {
                          const is_pulsing = (() => {
                            {
                              const $t29557 = (() => {
                                {
                                  const $t29555 = (gx + 3000);
                                  {
                                    const $t29556 = (gy + 3000);
                                    return bg_hash($t29555, $t29556, seed);
                                  }
                                }
                              })();
                              return ($t29557 < 0.04);
                            }
                          })();
                          {
                            let pulse;
                            if (is_pulsing === true) {
                              pulse = (() => {
                                {
                                  const speed = (() => {
                                    {
                                      const $t29561 = (() => {
                                        {
                                          const $t29560 = (() => {
                                            {
                                              const $t29559 = (gx + 4000);
                                              return bg_hash($t29559, gy, seed);
                                            }
                                          })();
                                          return (0.45 * $t29560);
                                        }
                                      })();
                                      return (0.35 + $t29561);
                                    }
                                  })();
                                  {
                                    const phase = (() => {
                                      {
                                        const $t29563 = (() => {
                                          {
                                            const $t29562 = (gy + 4000);
                                            return bg_hash(gx, $t29562, seed);
                                          }
                                        })();
                                        return ($t29563 * 6.28318530718);
                                      }
                                    })();
                                    {
                                      const $t29568 = (() => {
                                        {
                                          const $t29567 = (() => {
                                            {
                                              const $t29566 = (() => {
                                                {
                                                  const $t29565 = (t * speed);
                                                  return ($t29565 + phase);
                                                }
                                              })();
                                              return Math.sin($t29566);
                                            }
                                          })();
                                          return (0.5 * $t29567);
                                        }
                                      })();
                                      return (0.5 + $t29568);
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
                                    const $t29571 = (() => {
                                      {
                                        const $t29570 = (() => {
                                          {
                                            const $t29569 = (1. - br);
                                            return ($t29569 * 0.6);
                                          }
                                        })();
                                        return ($t29570 * pulse);
                                      }
                                    })();
                                    return (br + $t29571);
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
                                      const $t29573 = (() => {
                                        {
                                          const $t29572 = (0.35 * pulse);
                                          return (1. + $t29572);
                                        }
                                      })();
                                      return (sz * $t29573);
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
    const $t29575 = (gx > gx_max);
    if ($t29575 === true) {
      return {  };
    } else {
      return (() => {
        (() => {
          return draw_bg_cell(ctx, gx, gy, cell, seed, t);
        })();
        {
          const $t29576 = (gx + 1);
          return draw_bg_row(ctx, $t29576, gx_max, gy, cell, seed, t);
        }
      })();
    }
  }
}
const draw_bg_row$clo = { _0: ($_, ctx, gx, gx_max, gy, cell, seed, t) => draw_bg_row(ctx, gx, gx_max, gy, cell, seed, t) };

function draw_bg_rows(ctx, gx0, gx1, gy, gy_max, cell, seed, t) {
  {
    const $t29577 = (gy > gy_max);
    if ($t29577 === true) {
      return {  };
    } else {
      return (() => {
        (() => {
          return draw_bg_row(ctx, gx0, gx1, gy, cell, seed, t);
        })();
        {
          const $t29578 = (gy + 1);
          return draw_bg_rows(ctx, gx0, gx1, $t29578, gy_max, cell, seed, t);
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
        const $t29581 = (() => {
          {
            const $t29580 = (() => {
              {
                const $t29579 = (cam_x / 70.);
                {
                  const $t1622_i4113 = Math.floor($t29579);
                  return $t1622_i4113;
                }
              }
            })();
            return Math.trunc($t29580);
          }
        })();
        return ($t29581 - 1);
      }
    })();
    {
      const gx1 = (() => {
        {
          const $t29585 = (() => {
            {
              const $t29584 = (() => {
                {
                  const $t29583 = (() => {
                    {
                      const $t29582 = (cam_x + view_w);
                      return ($t29582 / 70.);
                    }
                  })();
                  {
                    const $t1622_i4111 = Math.floor($t29583);
                    return $t1622_i4111;
                  }
                }
              })();
              return Math.trunc($t29584);
            }
          })();
          return ($t29585 + 1);
        }
      })();
      {
        const gy0 = (() => {
          {
            const $t29588 = (() => {
              {
                const $t29587 = (() => {
                  {
                    const $t29586 = (cam / 70.);
                    {
                      const $t1622_i4109 = Math.floor($t29586);
                      return $t1622_i4109;
                    }
                  }
                })();
                return Math.trunc($t29587);
              }
            })();
            return ($t29588 - 1);
          }
        })();
        {
          const gy1 = (() => {
            {
              const $t29592 = (() => {
                {
                  const $t29591 = (() => {
                    {
                      const $t29590 = (() => {
                        {
                          const $t29589 = (cam + view_h);
                          return ($t29589 / 70.);
                        }
                      })();
                      {
                        const $t1622_i4107 = Math.floor($t29590);
                        return $t1622_i4107;
                      }
                    }
                  })();
                  return Math.trunc($t29591);
                }
              })();
              return ($t29592 + 1);
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
      const $f29599 = clouds._0;
      const $f29600 = clouds._1;
      {
        const rest = (() => {
          return $f29600;
        })();
        {
          const c = (() => {
            return $f29599;
          })();
          (() => {
            {
              const $t29593 = c.x;
              {
                const $t29594 = c.y;
                {
                  const $t29595 = c.radius;
                  {
                    const $t29598 = (() => {
                      {
                        const $t29597 = c.strength;
                        return (0.16 * $t29597);
                      }
                    })();
                    return Canvas$fill_noise_circle(ctx, $t29593, $t29594, $t29595, $t29598);
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
    const $t29605 = (() => {
      {
        const margin_i10343 = (700. + 90.);
        {
          const $t29209_i10344 = { $: "Nil" };
          {
            const $t29210_i10345 = Perihelion$Nebula$filter_visible(stars, cam, view_h, margin_i10343, $t29209_i10344);
            {
              const $t29211_i10346 = { $: "Nil" };
              return Perihelion$Nebula$collect_star_clouds($t29210_i10345, seed, $t29211_i10346);
            }
          }
        }
      }
    })();
    {
      const $rc_843 = draw_nebula_clouds(ctx, $t29605);
      return $rc_843;
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
      const $f29614 = stars._0;
      const $f29615 = stars._1;
      {
        const rest = $f29615;
        {
          const s = $f29614;
          (() => {
            {
              const $t29613 = (() => {
                {
                  const $t29609 = (() => {
                    {
                      const $t29606 = s.y;
                      {
                        const $t29608 = (() => {
                          {
                            const $t29607 = (cam + view_h);
                            return ($t29607 + 100.);
                          }
                        })();
                        return ($t29606 < $t29608);
                      }
                    }
                  })();
                  {
                    const $t29612 = (() => {
                      {
                        const $t29610 = s.y;
                        {
                          const $t29611 = (cam - 100.);
                          return ($t29610 > $t29611);
                        }
                      }
                    })();
                    return ($t29609 && $t29612);
                  }
                }
              })();
              if ($t29613 === true) {
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
        const $t29626 = i;
        {
          const $t29628 = (6.28318530718 / 8.);
          return ($t29626 * $t29628);
        }
      }
    })();
    {
      const jitter = (() => {
        {
          const $t29631 = (() => {
            {
              const $t29630 = (() => {
                {
                  const $t29629 = a.shape_seed;
                  {
                    const x_i10354 = (() => {
                      {
                        const $t29624_i10353 = (() => {
                          {
                            const $t29623_i10352 = (() => {
                              {
                                const $t29620_i10349 = ($t29629 * 12.9898);
                                {
                                  const $t29622_i10351 = (() => {
                                    {
                                      const $t29621_i10350 = i;
                                      return ($t29621_i10350 * 78.233);
                                    }
                                  })();
                                  return ($t29620_i10349 + $t29622_i10351);
                                }
                              }
                            })();
                            return Math.sin($t29623_i10352);
                          }
                        })();
                        return ($t29624_i10353 * 43758.5453);
                      }
                    })();
                    {
                      const $t29625_i10356 = (() => {
                        {
                          const $t1622_i4117_i10355 = Math.floor(x_i10354);
                          return $t1622_i4117_i10355;
                        }
                      })();
                      return (x_i10354 - $t29625_i10356);
                    }
                  }
                }
              })();
              return (0.6 * $t29630);
            }
          })();
          return (0.7 + $t29631);
        }
      })();
      {
        const r = (() => {
          {
            const $t29632 = a.radius;
            return ($t29632 * jitter);
          }
        })();
        {
          const pt = (() => {
            {
              const $t29636 = (() => {
                {
                  const $t29633 = a.x;
                  {
                    const $t29635 = (() => {
                      {
                        const $t29634 = Math.cos(angle);
                        return ($t29634 * r);
                      }
                    })();
                    return ($t29633 + $t29635);
                  }
                }
              })();
              {
                const $t29640 = (() => {
                  {
                    const $t29637 = a.y;
                    {
                      const $t29639 = (() => {
                        {
                          const $t29638 = Math.sin(angle);
                          return ($t29638 * r);
                        }
                      })();
                      return ($t29637 + $t29639);
                    }
                  }
                })();
                return { _0: $t29636, _1: $t29640 };
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
    const $t29641 = (i > 7);
    if ($t29641 === true) {
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
                      const $jp_clo29643 = (() => {
                        return { $: "$Clo_$jp29642$3809", _0: $jp29642$apply$3809, _1: ctx, _2: px, _3: py };
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
                const $t29644 = (i + 1);
                return draw_asteroid_edges(ctx, a, $t29644);
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
      const $f29653 = asteroids._0;
      const $f29654 = asteroids._1;
      {
        const rest = (() => {
          return $f29654;
        })();
        {
          const a = (() => {
            return $f29653;
          })();
          {
            const color = (() => {
              {
                const $t29646 = a.mode;
                switch ($t29646.$) {
                  case "AsteroidDrifting": {
                    return "#8a8a94";
                    break;
                  }
                  case "AsteroidOrbiting": {
                    const $f29647 = $t29646._0;
                    const $f29648 = $t29646._1;
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
      const $f29662 = shots._0;
      const $f29663 = shots._1;
      {
        const rest = (() => {
          return $f29663;
        })();
        {
          const s = (() => {
            return $f29662;
          })();
          (() => {
            return Canvas$set_fill_style(ctx, color);
          })();
          (() => {
            return Canvas$begin_path(ctx);
          })();
          (() => {
            {
              const $t29659 = s.x;
              {
                const $t29660 = s.y;
                return Canvas$arc(ctx, $t29659, $t29660, r, 0., 6.28318530718);
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
    const $t29668 = sh.mode;
    switch ($t29668.$) {
      case "ShipOrbiting": {
        const $f29672 = $t29668._0;
        {
          const angle = (() => {
            return $f29672;
          })();
          {
            const d = (0. - 1.);
            {
              const $t29671 = (d * 1.5707963);
              return (angle + $t29671);
            }
          }
        }
        break;
      }
      case "ShipFlying": {
        const $f29673 = $t29668._0;
        const $f29674 = $t29668._1;
        {
          const vy = (() => {
            return $f29674;
          })();
          {
            const vx = (() => {
              return $f29673;
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
      const $f29683 = ships._0;
      const $f29684 = ships._1;
      {
        const rest = (() => {
          return $f29684;
        })();
        {
          const sh = (() => {
            return $f29683;
          })();
          {
            const pos = (() => {
              {
                const pos_i4132 = (() => {
                  {
                    const $t27400_i4130 = sh.x;
                    {
                      const $t27401_i4131 = sh.y;
                      return { _0: $t27400_i4130, _1: $t27401_i4131 };
                    }
                  }
                })();
                return pos_i4132;
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
                      const $t29679 = (0. - 6.);
                      return Canvas$line_to(ctx, $t29679, 5.);
                    }
                  })();
                  (() => {
                    {
                      const $t29680 = (0. - 6.);
                      {
                        const $t29681 = (0. - 5.);
                        return Canvas$line_to(ctx, $t29680, $t29681);
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
      const $f29692 = pickups._0;
      const $f29693 = pickups._1;
      {
        const rest = (() => {
          return $f29693;
        })();
        {
          const pk = (() => {
            return $f29692;
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
              const $t29689 = pk.x;
              {
                const $t29690 = pk.y;
                return Canvas$arc(ctx, $t29689, $t29690, 8., 0., 6.28318530718);
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
    const $t29698 = (i >= 5);
    if ($t29698 === true) {
      return {  };
    } else {
      return (() => {
        switch (runs.$) {
          case "Nil": {
            return {  };
            break;
          }
          case "Cons": {
            const $f29713 = runs._0;
            const $f29714 = runs._1;
            {
              const rest = (() => {
                return $f29714;
              })();
              {
                const r = (() => {
                  return $f29713;
                })();
                (() => {
                  return Canvas$set_font(ctx, "14px sans-serif");
                })();
                (() => {
                  {
                    const $t29709 = (() => {
                      {
                        const $t29708 = (() => {
                          {
                            const $t29705 = (() => {
                              {
                                const $t29704 = (() => {
                                  {
                                    const $t29701 = (() => {
                                      {
                                        const $t29700 = (() => {
                                          {
                                            const $t29699 = r.score;
                                            return String($t29699);
                                          }
                                        })();
                                        {
                                          const $rc_848 = ($t29700 + " x");
                                          return $rc_848;
                                        }
                                      }
                                    })();
                                    {
                                      const $t29703 = (() => {
                                        {
                                          const $t29702 = r.max_mult;
                                          return String($t29702);
                                        }
                                      })();
                                      {
                                        const $rc_847 = ($t29701 + $t29703);
                                        return $rc_847;
                                      }
                                    }
                                  }
                                })();
                                {
                                  const $rc_846 = ($t29704 + " · ");
                                  return $rc_846;
                                }
                              }
                            })();
                            {
                              const $t29707 = (() => {
                                {
                                  const $t29706 = r.stars;
                                  return String($t29706);
                                }
                              })();
                              {
                                const $rc_845 = ($t29705 + $t29707);
                                return $rc_845;
                              }
                            }
                          }
                        })();
                        {
                          const $rc_844 = ($t29708 + " stars");
                          return $rc_844;
                        }
                      }
                    })();
                    {
                      const $t29710 = (view_w / 2.);
                      return Canvas$fill_text(ctx, $t29709, $t29710, y);
                    }
                  }
                })();
                {
                  const $t29711 = (y + 20.);
                  {
                    const $t29712 = (i + 1);
                    return draw_runs(ctx, rest, view_w, $t29711, $t29712);
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
      const $t29719 = game.ball_x;
      {
        const $t29720 = game.ball_y;
        return Canvas$arc(ctx, $t29719, $t29720, 6., 0., 6.28318530718);
      }
    }
  })();
  (() => {
    return Canvas$fill(ctx);
  })();
  {
    const $t29723 = (() => {
      {
        const $t29722 = game.shield;
        return ($t29722 > 0);
      }
    })();
    if ($t29723 === true) {
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
            const $t29724 = game.ball_x;
            {
              const $t29725 = game.ball_y;
              return Canvas$arc(ctx, $t29724, $t29725, 10., 0., 6.28318530718);
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
      const $t29729 = (cx - 60.);
      {
        const $t29731 = (() => {
          {
            const $t29730 = (view_h / 2.);
            return ($t29730 - 60.);
          }
        })();
        return Canvas$stroke_rect(ctx, $t29729, $t29731, 120., 120.);
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
    let $t29732;
    switch (u.$) {
      case "OffenseWeapon": {
        const $f29727_i10358 = u._0;
        $t29732 = (() => {
          switch ($f29727_i10358.$) {
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
        $t29732 = "Faster Fire";
        break;
      }
      case "DefenseBulletWard": {
        $t29732 = "Bullet Ward";
        break;
      }
      case "DefenseDeflector": {
        $t29732 = "Deflector Plating";
        break;
      }
      case "DefenseShield": {
        $t29732 = "Reinforced Shield";
        break;
      }
      case "SpecialItem": {
        const $f29728_i10359 = u._0;
        $t29732 = (() => {
          switch ($f29728_i10359.$) {
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
        $t29732 = (() => { throw new Error("non-exhaustive pattern match"); })();
        break;
      }
    }
    {
      const $t29733 = (view_h / 2.);
      return Canvas$fill_text(ctx, $t29732, cx, $t29733);
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
      const $f29738 = choices._0;
      const $f29739 = choices._1;
      {
        const rest = (() => {
          return $f29739;
        })();
        {
          const u = (() => {
            return $f29738;
          })();
          {
            const col_w = (view_w / 3.);
            (() => {
              {
                const $t29736 = (() => {
                  {
                    const $t29735 = (() => {
                      {
                        const $t29734 = i;
                        return ($t29734 + 0.5);
                      }
                    })();
                    return (col_w * $t29735);
                  }
                })();
                {
                  const $rc_849 = (() => {
                    return draw_milestone_card(ctx, u, $t29736, view_h);
                  })();
                  return $rc_849;
                }
              }
            })();
            {
              const $t29737 = (i + 1);
              return draw_milestone_cards(ctx, rest, view_w, view_h, $t29737);
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
      const $t29745 = (() => {
        {
          const $t29744 = game.score;
          return String($t29744);
        }
      })();
      return Canvas$fill_text(ctx, $t29745, 14., 28.);
    }
  })();
  (() => {
    return Canvas$set_text_align(ctx, "right");
  })();
  (() => {
    {
      const $t29748 = (() => {
        {
          const $t29747 = (() => {
            {
              const $t29746 = game.best;
              return String($t29746);
            }
          })();
          {
            const $rc_860 = ("best " + $t29747);
            return $rc_860;
          }
        }
      })();
      {
        const $t29750 = (() => {
          {
            const $t29749 = game.view_w;
            return ($t29749 - 14.);
          }
        })();
        return Canvas$fill_text(ctx, $t29748, $t29750, 28.);
      }
    }
  })();
  (() => {
    {
      const $t29752 = (() => {
        {
          const $t29751 = game.multiplier;
          return ($t29751 > 1);
        }
      })();
      if ($t29752 === true) {
        return (() => {
          (() => {
            return Canvas$set_text_align(ctx, "left");
          })();
          {
            const $t29755 = (() => {
              {
                const $t29754 = (() => {
                  {
                    const $t29753 = game.multiplier;
                    return String($t29753);
                  }
                })();
                {
                  const $rc_859 = ("x" + $t29754);
                  return $rc_859;
                }
              }
            })();
            return Canvas$fill_text(ctx, $t29755, 14., 52.);
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
      const $t29758 = (() => {
        {
          const $t29757 = (() => {
            {
              const $t29756 = Perihelion$Core$active_weapon(game);
              return { $: "OffenseWeapon", _0: $t29756 };
            }
          })();
          {
            let $rc_858;
            switch ($t29757.$) {
              case "OffenseWeapon": {
                const $f29727_i10364 = $t29757._0;
                $rc_858 = (() => {
                  switch ($f29727_i10364.$) {
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
                $rc_858 = "Faster Fire";
                break;
              }
              case "DefenseBulletWard": {
                $rc_858 = "Bullet Ward";
                break;
              }
              case "DefenseDeflector": {
                $rc_858 = "Deflector Plating";
                break;
              }
              case "DefenseShield": {
                $rc_858 = "Reinforced Shield";
                break;
              }
              case "SpecialItem": {
                const $f29728_i10365 = $t29757._0;
                $rc_858 = (() => {
                  switch ($f29728_i10365.$) {
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
                $rc_858 = (() => { throw new Error("non-exhaustive pattern match"); })();
                break;
              }
            }
            return $rc_858;
          }
        }
      })();
      {
        const $t29760 = (() => {
          {
            const $t29759 = game.view_h;
            return ($t29759 - 60.);
          }
        })();
        return Canvas$fill_text(ctx, $t29758, 14., $t29760);
      }
    }
  })();
  (() => {
    {
      const $t29761 = game.special;
      switch ($t29761.$) {
        case "None": {
          return {  };
          break;
        }
        case "Some": {
          const $f29770 = $t29761._0;
          {
            const k = (() => {
              return $f29770;
            })();
            {
              const $t29767 = (() => {
                {
                  const $t29764 = (() => {
                    {
                      const $t29763 = (() => {
                        {
                          const $t29762 = { $: "SpecialItem", _0: k };
                          {
                            let $rc_857;
                            switch ($t29762.$) {
                              case "OffenseWeapon": {
                                const $f29727_i10361 = $t29762._0;
                                $rc_857 = (() => {
                                  switch ($f29727_i10361.$) {
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
                                $rc_857 = "Faster Fire";
                                break;
                              }
                              case "DefenseBulletWard": {
                                $rc_857 = "Bullet Ward";
                                break;
                              }
                              case "DefenseDeflector": {
                                $rc_857 = "Deflector Plating";
                                break;
                              }
                              case "DefenseShield": {
                                $rc_857 = "Reinforced Shield";
                                break;
                              }
                              case "SpecialItem": {
                                const $f29728_i10362 = $t29762._0;
                                $rc_857 = (() => {
                                  switch ($f29728_i10362.$) {
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
                                $rc_857 = (() => { throw new Error("non-exhaustive pattern match"); })();
                                break;
                              }
                            }
                            return $rc_857;
                          }
                        }
                      })();
                      {
                        const $rc_856 = ($t29763 + " x");
                        return $rc_856;
                      }
                    }
                  })();
                  {
                    const $t29766 = (() => {
                      {
                        const $t29765 = game.special_charges;
                        return String($t29765);
                      }
                    })();
                    {
                      const $rc_855 = ($t29764 + $t29766);
                      return $rc_855;
                    }
                  }
                }
              })();
              {
                const $t29769 = (() => {
                  {
                    const $t29768 = game.view_h;
                    return ($t29768 - 40.);
                  }
                })();
                return Canvas$fill_text(ctx, $t29767, 14., $t29769);
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
        const $t29775 = (() => {
          {
            const $t29772 = (() => {
              {
                const $t29771 = game.bullet_ward;
                if ($t29771 === true) {
                  return "ward ";
                } else {
                  return "";
                }
              }
            })();
            {
              const $t29774 = (() => {
                {
                  const $t29773 = game.deflector_plating;
                  if ($t29773 === true) {
                    return "deflect ";
                  } else {
                    return "";
                  }
                }
              })();
              {
                const $rc_854 = ($t29772 + $t29774);
                return $rc_854;
              }
            }
          }
        })();
        {
          const $t29780 = (() => {
            {
              const $t29777 = (() => {
                {
                  const $t29776 = game.shield;
                  return ($t29776 > 0);
                }
              })();
              if ($t29777 === true) {
                return (() => {
                  {
                    const $t29779 = (() => {
                      {
                        const $t29778 = game.shield;
                        return String($t29778);
                      }
                    })();
                    {
                      const $rc_853 = ("shield x" + $t29779);
                      return $rc_853;
                    }
                  }
                })();
              } else {
                return "";
              }
            }
          })();
          {
            const $rc_852 = ($t29775 + $t29780);
            return $rc_852;
          }
        }
      }
    })();
    (() => {
      {
        const $t29782 = (() => {
          {
            const $t29781 = game.view_h;
            return ($t29781 - 20.);
          }
        })();
        return Canvas$fill_text(ctx, defense_tags, 14., $t29782);
      }
    })();
    (() => {
      return Canvas$set_text_align(ctx, "center");
    })();
    {
      const $t29783 = game.phase;
      switch ($t29783.$) {
        case "Ready": {
          (() => {
            return Canvas$set_font(ctx, "22px sans-serif");
          })();
          {
            const $t29785 = (() => {
              {
                const $t29784 = game.view_w;
                return ($t29784 / 2.);
              }
            })();
            {
              const $t29787 = (() => {
                {
                  const $t29786 = game.view_h;
                  return ($t29786 / 2.);
                }
              })();
              return Canvas$fill_text(ctx, "tap to start", $t29785, $t29787);
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
              const $t29791 = (() => {
                {
                  const $t29790 = (() => {
                    {
                      const $t29789 = (() => {
                        {
                          const $t29788 = game.score;
                          return String($t29788);
                        }
                      })();
                      {
                        const $rc_851 = ("score " + $t29789);
                        return $rc_851;
                      }
                    }
                  })();
                  {
                    const $rc_850 = ($t29790 + " — tap to retry");
                    return $rc_850;
                  }
                }
              })();
              {
                const $t29793 = (() => {
                  {
                    const $t29792 = game.view_w;
                    return ($t29792 / 2.);
                  }
                })();
                {
                  const $t29795 = (() => {
                    {
                      const $t29794 = game.view_h;
                      return ($t29794 / 2.);
                    }
                  })();
                  return Canvas$fill_text(ctx, $t29791, $t29793, $t29795);
                }
              }
            }
          })();
          {
            const $t29796 = game.runs;
            {
              const $t29797 = game.view_w;
              {
                const $t29800 = (() => {
                  {
                    const $t29799 = (() => {
                      {
                        const $t29798 = game.view_h;
                        return ($t29798 / 2.);
                      }
                    })();
                    return ($t29799 + 36.);
                  }
                })();
                return draw_runs(ctx, $t29796, $t29797, $t29800, 0);
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
              const $t29802 = (() => {
                {
                  const $t29801 = game.view_w;
                  return ($t29801 / 2.);
                }
              })();
              {
                const $t29805 = (() => {
                  {
                    const $t29804 = (() => {
                      {
                        const $t29803 = game.view_h;
                        return ($t29803 / 2.);
                      }
                    })();
                    return ($t29804 - 90.);
                  }
                })();
                return Canvas$fill_text(ctx, "Choose an upgrade", $t29802, $t29805);
              }
            }
          })();
          {
            const $t29806 = game.milestone_choices;
            {
              const $t29807 = game.view_w;
              {
                const $t29808 = game.view_h;
                return draw_milestone_cards(ctx, $t29806, $t29807, $t29808, 0);
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
      const $t29809 = game.view_w;
      {
        const $t29810 = game.view_h;
        return Canvas$fill_rect(ctx, 0., 0., $t29809, $t29810);
      }
    }
  })();
  (() => {
    return Canvas$save(ctx);
  })();
  (() => {
    {
      const $t29812 = (() => {
        {
          const $t29811 = game.camera_x;
          return (0. - $t29811);
        }
      })();
      {
        const $t29814 = (() => {
          {
            const $t29813 = game.camera_y;
            return (0. - $t29813);
          }
        })();
        return Canvas$translate(ctx, $t29812, $t29814);
      }
    }
  })();
  {
    const seedf = (() => {
      {
        const $t29815 = game.seed;
        return $t29815;
      }
    })();
    (() => {
      {
        const $t29816 = game.camera_x;
        {
          const $t29817 = game.camera_y;
          {
            const $t29818 = game.view_w;
            {
              const $t29819 = game.view_h;
              {
                const $t29820 = fx.t;
                return draw_starfield(ctx, $t29816, $t29817, $t29818, $t29819, seedf, $t29820);
              }
            }
          }
        }
      }
    })();
    (() => {
      {
        const $t29821 = game.stars;
        {
          const $t29822 = game.camera_y;
          {
            const $t29823 = game.view_h;
            return draw_nebula(ctx, $t29821, $t29822, $t29823, seedf);
          }
        }
      }
    })();
    {
      const aim = (() => {
        {
          const $t29824 = game.mode;
          switch ($t29824.$) {
            case "Flying": {
              const $f29828 = $t29824._0;
              const $f29829 = $t29824._1;
              {
                const vy = (() => {
                  return $f29829;
                })();
                {
                  const vx = (() => {
                    return $f29828;
                  })();
                  {
                    const $t29825 = game.ball_x;
                    {
                      const $t29826 = game.ball_y;
                      {
                        const $t29827 = { _0: $t29825, _1: $t29826, _2: vx, _3: vy };
                        return { $: "Some", _0: $t29827 };
                      }
                    }
                  }
                }
              }
              break;
            }
            case "Orbiting": {
              const $f29834 = $t29824._0;
              const $f29835 = $t29824._1;
              const $f29836 = $t29824._2;
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
          const $t29845 = game.stars;
          {
            const $t29846 = game.camera_y;
            {
              const $t29847 = game.view_h;
              {
                const $t29848 = fx.t;
                {
                  const $rc_862 = (() => {
                    return draw_stars(ctx, $t29845, $t29846, $t29847, $t29848, aim);
                  })();
                  return $rc_862;
                }
              }
            }
          }
        }
      })();
      (() => {
        {
          const $t29849 = Perihelion$Core$active_weapon(game);
          switch ($t29849.$) {
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
          const $t29852 = game.mode;
          switch ($t29852.$) {
            case "Orbiting": {
              const $f29860 = $t29852._0;
              const $f29861 = $t29852._1;
              const $f29862 = $t29852._2;
              {
                const angle = (() => {
                  return $f29862;
                })();
                {
                  const ring = (() => {
                    return $f29861;
                  })();
                  {
                    const idx = (() => {
                      return $f29860;
                    })();
                    {
                      const $t29853 = game.special;
                      switch ($t29853.$) {
                        case "Some": {
                          const $f29855 = $t29853._0;
                          switch ($f29855.$) {
                            case "TrajectoryPreview": {
                              {
                                const $t29854 = Perihelion$Core$predict_trajectory(game, idx, ring, angle);
                                {
                                  const $rc_861 = (() => {
                                    return draw_trajectory_preview(ctx, $t29854);
                                  })();
                                  return $rc_861;
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
              const $f29871 = $t29852._0;
              const $f29872 = $t29852._1;
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
          const $t29877 = fx.flash;
          return draw_flash(ctx, $t29877);
        }
      })();
      (() => {
        {
          const $t29878 = game.asteroids;
          return draw_asteroids(ctx, $t29878);
        }
      })();
      (() => {
        {
          const $t29879 = game.ships;
          return draw_ships(ctx, $t29879);
        }
      })();
      (() => {
        {
          const $t29880 = game.player_shots;
          return draw_shots(ctx, $t29880, "#ffffff", 3.);
        }
      })();
      (() => {
        {
          const $t29881 = game.enemy_shots;
          return draw_shots(ctx, $t29881, "#8a8a94", 2.5);
        }
      })();
      (() => {
        {
          const $t29882 = game.pickups;
          return draw_pickups(ctx, $t29882);
        }
      })();
      (() => {
        {
          const $t29883 = fx.trail;
          return draw_trail(ctx, $t29883, 0, 14);
        }
      })();
      (() => {
        {
          const $t29885 = fx.particles;
          return draw_particles(ctx, $t29885);
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
    const $t29887 = (() => {
      {
        const $t29886 = Perihelion$Combat$starkiller_target_idx(game);
        return Perihelion$Core$star_at(game, $t29886);
      }
    })();
    switch ($t29887.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f29893 = $t29887._0;
        {
          const s = $f29893;
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
              const $t29888 = s.x;
              {
                const $t29889 = s.y;
                {
                  const $t29891 = (() => {
                    {
                      const $t29890 = s.capture_radius;
                      return ($t29890 + 12.);
                    }
                  })();
                  return Canvas$arc(ctx, $t29888, $t29889, $t29891, 0., 6.28318530718);
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
      const $f29899 = points._0;
      const $f29900 = points._1;
      {
        const rest = (() => {
          return $f29900;
        })();
        {
          const pt = (() => {
            return $f29899;
          })();
          {
            const x = pt._0;
            {
              const y = pt._1;
              (() => {
                {
                  const $t29895 = (() => {
                    {
                      const $t29894 = march_int_mod(i, 3);
                      return ($t29894 === 0);
                    }
                  })();
                  if ($t29895 === true) {
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
                const $t29897 = (i + 1);
                return draw_trajectory_dots(ctx, rest, $t29897);
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
    const $t29911 = (() => {
      {
        const $t29908 = (() => {
          {
            const $t29907 = game.view_w;
            return (w === $t29907);
          }
        })();
        {
          const $t29910 = (() => {
            {
              const $t29909 = game.view_h;
              return (h === $t29909);
            }
          })();
          return ($t29908 && $t29910);
        }
      }
    })();
    if ($t29911 === true) {
      return {  };
    } else {
      return (() => {
        (() => {
          {
            const $t29913 = (() => {
              {
                const $t29912 = Math.trunc(w);
                return String($t29912);
              }
            })();
            return Dom$set_attr(el, "width", $t29913);
          }
        })();
        {
          const $t29915 = (() => {
            {
              const $t29914 = Math.trunc(h);
              return String($t29914);
            }
          })();
          return Dom$set_attr(el, "height", $t29915);
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
          const $t29929 = (() => {
            {
              const $t29927 = (() => {
                {
                  const $t29926 = game.phase;
                  switch ($t29926.$) {
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
                const $t29928 = (() => {
                  {
                    const $t29905_i4172 = g2.phase;
                    switch ($t29905_i4172.$) {
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
                return ($t29927 && $t29928);
              }
            }
          })();
          if ($t29929 === true) {
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
          const $t29934 = (() => {
            {
              const $t29931 = (() => {
                {
                  const $t29930 = game.mode;
                  switch ($t29930.$) {
                    case "Orbiting": {
                      const $f29916_i4168 = $t29930._0;
                      const $f29917_i4169 = $t29930._1;
                      const $f29918_i4170 = $t29930._2;
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
                const $t29933 = (() => {
                  {
                    const $t29932 = g2.mode;
                    switch ($t29932.$) {
                      case "Flying": {
                        const $f29919_i4165 = $t29932._0;
                        const $f29920_i4166 = $t29932._1;
                        return true;
                        break;
                      }
                      default: {
                        return false;
                      }
                    }
                  }
                })();
                return ($t29931 && $t29933);
              }
            }
          })();
          if ($t29934 === true) {
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
          const $t29935 = g2.capture_flash;
          switch ($t29935.$) {
            case "None": {
              return {  };
              break;
            }
            case "Some": {
              const $f29936 = $t29935._0;
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
          const $t29941 = (() => {
            {
              const $t29938 = (() => {
                {
                  const $t29937 = g2.player_shots;
                  {
                    const go_i4162 = { $: "$Clo_go$4830", _0: go$apply$4830 };
                    return go$apply$4830(go_i4162, $t29937, 0);
                  }
                }
              })();
              {
                const $t29940 = (() => {
                  {
                    const $t29939 = game.player_shots;
                    {
                      const go_i4160 = { $: "$Clo_go$4830", _0: go$apply$4830 };
                      return go$apply$4830(go_i4160, $t29939, 0);
                    }
                  }
                })();
                return ($t29938 > $t29940);
              }
            }
          })();
          if ($t29941 === true) {
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
          const $t29946 = (() => {
            {
              const $t29943 = (() => {
                {
                  const $t29942 = g2.enemy_shots;
                  {
                    const go_i4158 = { $: "$Clo_go$4830", _0: go$apply$4830 };
                    return go$apply$4830(go_i4158, $t29942, 0);
                  }
                }
              })();
              {
                const $t29945 = (() => {
                  {
                    const $t29944 = game.enemy_shots;
                    {
                      const go_i4156 = { $: "$Clo_go$4830", _0: go$apply$4830 };
                      return go$apply$4830(go_i4156, $t29944, 0);
                    }
                  }
                })();
                return ($t29943 > $t29945);
              }
            }
          })();
          if ($t29946 === true) {
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
          const $t29949 = (() => {
            {
              const $t29948 = (() => {
                {
                  const $t29947 = g2.fx_bursts;
                  switch ($t29947.$) {
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
              return (!$t29948);
            }
          })();
          if ($t29949 === true) {
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
          const $t29954 = (() => {
            {
              const $t29951 = (() => {
                {
                  const $t29950 = g2.ships;
                  {
                    const go_i4153 = { $: "$Clo_go$4782", _0: go$apply$4782 };
                    return go$apply$4782(go_i4153, $t29950, 0);
                  }
                }
              })();
              {
                const $t29953 = (() => {
                  {
                    const $t29952 = game.ships;
                    {
                      const go_i4151 = { $: "$Clo_go$4782", _0: go$apply$4782 };
                      return go$apply$4782(go_i4151, $t29952, 0);
                    }
                  }
                })();
                return ($t29951 < $t29953);
              }
            }
          })();
          if ($t29954 === true) {
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
          const $t29959 = (() => {
            {
              const $t29956 = (() => {
                {
                  const $t29955 = game.shield;
                  return ($t29955 === 0);
                }
              })();
              {
                const $t29958 = (() => {
                  {
                    const $t29957 = g2.shield;
                    return ($t29957 > 0);
                  }
                })();
                return ($t29956 && $t29958);
              }
            }
          })();
          if ($t29959 === true) {
            return (() => {
              return Audio$beep(actx, 700., 0.06, "sine");
            })();
          } else {
            return {  };
          }
        }
      })();
      {
        const $t29962 = (() => {
          {
            const $t29960 = (() => {
              {
                const $t29905_i4149 = game.phase;
                switch ($t29905_i4149.$) {
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
              const $t29961 = (() => {
                {
                  const $t29906_i4147 = g2.phase;
                  switch ($t29906_i4147.$) {
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
              return ($t29960 && $t29961);
            }
          }
        })();
        if ($t29962 === true) {
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
      const $f29968 = taps._0;
      const $f29969 = taps._1;
      {
        const tap = (() => {
          return $f29968;
        })();
        {
          const tx = tap._0;
          {
            const col_w = (view_w / 3.);
            {
              const idx = (() => {
                {
                  const $t29964 = (() => {
                    {
                      const $t29963 = tx;
                      return ($t29963 / col_w);
                    }
                  })();
                  return Math.trunc($t29964);
                }
              })();
              {
                const $t29966 = (() => {
                  {
                    const $t29965 = (idx > 2);
                    if ($t29965 === true) {
                      return 2;
                    } else {
                      return idx;
                    }
                  }
                })();
                return { $: "Some", _0: $t29966 };
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
          const $p29992 = dom_window_size();
          {
            const win_w = $p29992._0;
            {
              const win_h = $p29992._1;
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
                        const $t29974 = game.phase;
                        switch ($t29974.$) {
                          case "Milestone": {
                            {
                              const $jp_clo29980 = (() => {
                                return { $: "$Clo_$jp29979$3832", _0: $jp29979$apply$3832, _1: cursor, _2: game, _3: keys, _4: taps, _5: view_h, _6: view_w };
                              })();
                              {
                                const $t29975 = (() => {
                                  {
                                    const $t28483_i4184 = { $: "$Clo_$lam28480$3753", _0: $lam28480$apply$3753 };
                                    return List$any$List_String$Fn_String_Bool(keys, $t28483_i4184);
                                  }
                                })();
                                if ($t29975 === true) {
                                  return (() => {
                                    {
                                      const $rc_863 = (() => {
                                        return Perihelion$Core$update(game, taps, keys, cursor, view_w, view_h, 0.0166667);
                                      })();
                                      return $rc_863;
                                    }
                                  })();
                                } else {
                                  return (() => {
                                    {
                                      const $t29977 = (() => {
                                        {
                                          const $rc_864 = milestone_tap_choice(taps, view_w, view_h);
                                          return $rc_864;
                                        }
                                      })();
                                      return Perihelion$Core$pick_milestone(game, $t29977);
                                    }
                                  })();
                                }
                              }
                            }
                            break;
                          }
                          default: {
                            {
                              const $rc_865 = (() => {
                                return Perihelion$Core$update(game, taps, keys, cursor, view_w, view_h, 0.0166667);
                              })();
                              return $rc_865;
                            }
                          }
                        }
                      }
                    })();
                    {
                      const muted2 = (() => {
                        {
                          const $t29981 = fx.muted;
                          {
                            const $t29925_i4182 = (() => {
                              {
                                const $t29924_i4181 = { $: "$Clo_$lam29921$3830", _0: $lam29921$apply$3830 };
                                return List$any$List_String$Fn_String_Bool(keys, $t29924_i4181);
                              }
                            })();
                            if ($t29925_i4182 === true) {
                              return (!$t29981);
                            } else {
                              return $t29981;
                            }
                          }
                        }
                      })();
                      (() => {
                        {
                          const $t29982 = fx.actx;
                          return play_sfx($t29982, muted2, game, g2);
                        }
                      })();
                      {
                        const fx1 = step_fx(fx, g2, 0.0166667);
                        {
                          const fx2 = ({ ...fx1, muted: muted2 });
                          (() => {
                            {
                              const $t29986 = (() => {
                                {
                                  const $t29984 = (() => {
                                    {
                                      const $t29905_i4178 = game.phase;
                                      switch ($t29905_i4178.$) {
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
                                    const $t29985 = (() => {
                                      {
                                        const $t29906_i4176 = g2.phase;
                                        switch ($t29906_i4176.$) {
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
                                    return ($t29984 && $t29985);
                                  }
                                }
                              })();
                              if ($t29986 === true) {
                                return (() => {
                                  {
                                    const $t29989 = (() => {
                                      {
                                        const $t29987 = g2.best;
                                        {
                                          const $t29988 = g2.runs;
                                          return Perihelion$Core$encode_save($t29987, $t29988);
                                        }
                                      }
                                    })();
                                    return Dom$store_set("perihelion.v1", $t29989);
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
                            const $t29991 = { $: "$Clo_$lam29990$3833", _0: $lam29990$apply$3833, _1: ctx, _2: el, _3: fx2, _4: g2 };
                            return Dom$on_frame($t29991);
                          }
                        }
                      }
                    }
                  }
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
    const $p29998 = dom_window_size();
    {
      const win_w = $p29998._0;
      {
        const win_h = $p29998._1;
        {
          const view_w = win_w;
          {
            const view_h = win_h;
            (() => {
              {
                const $t29993 = String(win_w);
                return Dom$set_attr(node, "width", $t29993);
              }
            })();
            (() => {
              {
                const $t29994 = String(win_h);
                return Dom$set_attr(node, "height", $t29994);
              }
            })();
            {
              const $t29996 = (() => {
                {
                  const $t29995 = boot_seed();
                  return Perihelion$Core$fresh_run($t29995, best, runs, view_w, view_h);
                }
              })();
              {
                const $t29997 = (() => {
                  {
                    const $t29273_i10366 = { $: "Nil" };
                    {
                      const $t29274_i10367 = { $: "Nil" };
                      {
                        const $t29275_i10368 = { $: "None" };
                        {
                          const $t29276_i10369 = audio_create();
                          return ({ trail: $t29273_i10366, t: 0., particles: $t29274_i10367, flash: $t29275_i10368, actx: $t29276_i10369, muted: false });
                        }
                      }
                    }
                  }
                })();
                return tick(ctx, node, $t29996, $t29997);
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
    const $t29999 = Dom$find("game-canvas");
    switch ($t29999.$) {
      case "None": {
        return println$String("no #game-canvas found");
        break;
      }
      case "Some": {
        const $f30007 = $t29999._0;
        {
          const node = $f30007;
          {
            const $t30000 = (() => {
              return Canvas$get_context(node);
            })();
            switch ($t30000.$) {
              case "None": {
                return println$String("2d context unavailable");
                break;
              }
              case "Some": {
                const $f30006 = $t30000._0;
                {
                  const ctx = $f30006;
                  {
                    const saved = (() => {
                      {
                        const $t30001 = Dom$store_get("perihelion.v1");
                        switch ($t30001.$) {
                          case "None": {
                            return "";
                            break;
                          }
                          case "Some": {
                            const $f30002 = $t30001._0;
                            {
                              const sv = $f30002;
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
                      const $p30005 = (() => {
                        {
                          const $rc_866 = Perihelion$Core$decode_save(saved);
                          return $rc_866;
                        }
                      })();
                      {
                        const best = $p30005._0;
                        {
                          const runs = $p30005._1;
                          {
                            const $t30004 = (() => {
                              return { $: "$Clo_$lam30003$3834", _0: $lam30003$apply$3834, _1: best, _2: ctx, _3: node, _4: runs };
                            })();
                            return Dom$on_frame($t30004);
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
      const $t149 = x;
      {
        const $rc_880 = march_print(x);
        return $rc_880;
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
      const $f457 = xs._0;
      const $f458 = xs._1;
      {
        const t = $f458;
        {
          const h = $f457;
          {
            const $t456 = (() => {
              return pred._0(pred, h);
            })();
            if ($t456 === true) {
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
      const $f457 = xs._0;
      const $f458 = xs._1;
      {
        const t = $f458;
        {
          const h = $f457;
          {
            const $t456 = (() => {
              return pred._0(pred, h);
            })();
            if ($t456 === true) {
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
      const $f457 = xs._0;
      const $f458 = xs._1;
      {
        const t = $f458;
        {
          const h = $f457;
          {
            const $t456 = (() => {
              return pred._0(pred, h);
            })();
            if ($t456 === true) {
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
      const $f457 = xs._0;
      const $f458 = xs._1;
      {
        const t = $f458;
        {
          const h = $f457;
          {
            const $t456 = (() => {
              return pred._0(pred, h);
            })();
            if ($t456 === true) {
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
      const $f442 = xs._0;
      const $f443 = xs._1;
      {
        const t = $f443;
        {
          const h = $f442;
          {
            const $t441 = (() => {
              return pred._0(pred, h);
            })();
            if ($t441 === true) {
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
      const $f273 = xs._0;
      const $f274 = xs._1;
      {
        const t = $f274;
        {
          const h = $f273;
          {
            const $t271 = (n === 0);
            if ($t271 === true) {
              return { $: "Some", _0: h };
            } else {
              return (() => {
                {
                  const $t272 = (n - 1);
                  return List$nth_opt$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int(t, $t272);
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
    const $t549 = (n <= 0);
    if ($t549 === true) {
      return xs;
    } else {
      return (() => {
        switch (xs.$) {
          case "Nil": {
            return { $: "Nil" };
            break;
          }
          case "Cons": {
            const $f551 = xs._0;
            const $f552 = xs._1;
            {
              const t = $f552;
              {
                const $t550 = (n - 1);
                return List$drop$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int(t, $t550);
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
      const $f273 = xs._0;
      const $f274 = xs._1;
      {
        const t = $f274;
        {
          const h = $f273;
          {
            const $t271 = (n === 0);
            if ($t271 === true) {
              return { $: "Some", _0: h };
            } else {
              return (() => {
                {
                  const $t272 = (n - 1);
                  return List$nth_opt$List_R_radius_Float_speed_mult_Float$Int(t, $t272);
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
      const $f273 = xs._0;
      const $f274 = xs._1;
      {
        const t = $f274;
        {
          const h = $f273;
          {
            const $t271 = (n === 0);
            if ($t271 === true) {
              return { $: "Some", _0: h };
            } else {
              return (() => {
                {
                  const $t272 = (n - 1);
                  return List$nth_opt$List_WeaponKind$Int(t, $t272);
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
      const $f273 = xs._0;
      const $f274 = xs._1;
      {
        const t = $f274;
        {
          const h = $f273;
          {
            const $t271 = (n === 0);
            if ($t271 === true) {
              return { $: "Some", _0: h };
            } else {
              return (() => {
                {
                  const $t272 = (n - 1);
                  return List$nth_opt$List_UpgradeKind$Int(t, $t272);
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
    const $t549 = (n <= 0);
    if ($t549 === true) {
      return xs;
    } else {
      return (() => {
        switch (xs.$) {
          case "Nil": {
            return { $: "Nil" };
            break;
          }
          case "Cons": {
            const $f551 = xs._0;
            const $f552 = xs._1;
            {
              const t = $f552;
              {
                const $t550 = (n - 1);
                return List$drop$List_UpgradeKind$Int(t, $t550);
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
      const $f265 = xs._0;
      const $f266 = xs._1;
      {
        const t = $f266;
        {
          const h = $f265;
          {
            const $t263 = (n === 0);
            if ($t263 === true) {
              return h;
            } else {
              return (() => {
                {
                  const $t264 = (n - 1);
                  return List$nth$List_UpgradeKind$Int(t, $t264);
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
      const $f457 = xs._0;
      const $f458 = xs._1;
      {
        const t = $f458;
        {
          const h = $f457;
          {
            const $t456 = (() => {
              return pred._0(pred, h);
            })();
            if ($t456 === true) {
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

function $lam27535$apply$3687($clo, s) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const g1 = (() => {
        return $clo._2;
      })();
      {
        const $t27536 = g1.asteroids;
        {
          const $t27537 = g1.ships;
          return Perihelion$Combat$age_shot(s, dt_s, $t27536, $t27537);
        }
      }
    }
  }
}
const $lam27535$apply$3687$clo = { _0: ($_, $clo, s) => $lam27535$apply$3687($clo, s) };

function $lam27540$apply$3688($clo, s) {
  {
    const g1 = (() => {
      return $clo._1;
    })();
    {
      const $t27542 = (() => {
        {
          const $t27541 = s.ttl;
          return ($t27541 > 0.);
        }
      })();
      {
        const $t27545 = (() => {
          {
            const $t27543 = s.x;
            {
              const $t27544 = s.y;
              return Perihelion$Combat$in_band(g1, $t27543, $t27544);
            }
          }
        })();
        return ($t27542 && $t27545);
      }
    }
  }
}
const $lam27540$apply$3688$clo = { _0: ($_, $clo, s) => $lam27540$apply$3688($clo, s) };

function $lam27548$apply$3689($clo, s) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const g1 = (() => {
        return $clo._2;
      })();
      {
        const $t27549 = g1.asteroids;
        {
          const $t27550 = g1.ships;
          return Perihelion$Combat$age_shot(s, dt_s, $t27549, $t27550);
        }
      }
    }
  }
}
const $lam27548$apply$3689$clo = { _0: ($_, $clo, s) => $lam27548$apply$3689($clo, s) };

function $lam27553$apply$3690($clo, s) {
  {
    const g1 = (() => {
      return $clo._1;
    })();
    {
      const $t27555 = (() => {
        {
          const $t27554 = s.ttl;
          return ($t27554 > 0.);
        }
      })();
      {
        const $t27558 = (() => {
          {
            const $t27556 = s.x;
            {
              const $t27557 = s.y;
              return Perihelion$Combat$in_band(g1, $t27556, $t27557);
            }
          }
        })();
        return ($t27555 && $t27558);
      }
    }
  }
}
const $lam27553$apply$3690$clo = { _0: ($_, $clo, s) => $lam27553$apply$3690($clo, s) };

function $lam27561$apply$3691($clo, p) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const $t27563 = (() => {
        {
          const $t27562 = p.ttl;
          return ($t27562 - dt_s);
        }
      })();
      return ({ ...p, ttl: $t27563 });
    }
  }
}
const $lam27561$apply$3691$clo = { _0: ($_, $clo, p) => $lam27561$apply$3691($clo, p) };

function $lam27566$apply$3692($clo, p) {
  {
    const $t27567 = p.ttl;
    return ($t27567 > 0.);
  }
}
const $lam27566$apply$3692$clo = { _0: ($_, $clo, p) => $lam27566$apply$3692($clo, p) };

function $lam27966$apply$3708($clo, k) {
  return (k === " ");
}
const $lam27966$apply$3708$clo = { _0: ($_, $clo, k) => $lam27966$apply$3708($clo, k) };

function $lam28034$apply$3711($clo, sh) {
  {
    const tidx = (() => {
      return $clo._1;
    })();
    {
      const $t28035 = sh.star_idx;
      return ($t28035 !== tidx);
    }
  }
}
const $lam28034$apply$3711$clo = { _0: ($_, $clo, sh) => $lam28034$apply$3711($clo, sh) };

function $lam28038$apply$3712($clo, sh) {
  {
    const tidx = (() => {
      return $clo._1;
    })();
    {
      const $t28040 = (() => {
        {
          const $t28039 = sh.star_idx;
          return ($t28039 > tidx);
        }
      })();
      if ($t28040 === true) {
        return (() => {
          {
            const $t28042 = (() => {
              {
                const $t28041 = sh.star_idx;
                return ($t28041 - 1);
              }
            })();
            return ({ ...sh, star_idx: $t28042 });
          }
        })();
      } else {
        return sh;
      }
    }
  }
}
const $lam28038$apply$3712$clo = { _0: ($_, $clo, sh) => $lam28038$apply$3712($clo, sh) };

function $lam28055$apply$3714($clo, s) {
  return s.star_killer;
}
const $lam28055$apply$3714$clo = { _0: ($_, $clo, s) => $lam28055$apply$3714($clo, s) };

function $lam28068$apply$3716($clo, sh) {
  {
    const $t28069 = sh.star_killer;
    return (!$t28069);
  }
}
const $lam28068$apply$3716$clo = { _0: ($_, $clo, sh) => $lam28068$apply$3716($clo, sh) };

function $lam28075$apply$3717($clo, sh) {
  {
    const $t28076 = sh.star_killer;
    return (!$t28076);
  }
}
const $lam28075$apply$3717$clo = { _0: ($_, $clo, sh) => $lam28075$apply$3717($clo, sh) };

function $lam28089$apply$3718($clo, a) {
  {
    const $t28090 = a.x;
    {
      const $t28091 = a.y;
      return { _0: $t28090, _1: $t28091 };
    }
  }
}
const $lam28089$apply$3718$clo = { _0: ($_, $clo, a) => $lam28089$apply$3718($clo, a) };

function $lam28094$apply$3719($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28095 = game.player_shots;
      {
        const $t28100 = { $: "$Clo_$lam28096$3720", _0: $lam28096$apply$3720, _1: a };
        return List$any$List_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28095, $t28100);
      }
    }
  }
}
const $lam28094$apply$3719$clo = { _0: ($_, $clo, a) => $lam28094$apply$3719($clo, a) };

function $lam28096$apply$3720($clo, s) {
  {
    const a = (() => {
      return $clo._1;
    })();
    {
      const $t28097 = a.x;
      {
        const $t28098 = a.y;
        {
          const $t28099 = a.radius;
          {
            const $t28086_i10600 = s.x;
            {
              const $t28087_i10601 = s.y;
              {
                const $t27404_i9994_i10606 = (() => {
                  {
                    const dx_i3645_i9990_i10602 = ($t28097 - $t28086_i10600);
                    {
                      const dy_i3646_i9991_i10603 = ($t28098 - $t28087_i10601);
                      {
                        const $t27402_i3647_i9992_i10604 = (dx_i3645_i9990_i10602 * dx_i3645_i9990_i10602);
                        {
                          const $t27403_i3648_i9993_i10605 = (dy_i3646_i9991_i10603 * dy_i3646_i9991_i10603);
                          return ($t27402_i3647_i9992_i10604 + $t27403_i3648_i9993_i10605);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27407_i9997_i10609 = (() => {
                    {
                      const $t27405_i9995_i10607 = (3. + $t28099);
                      {
                        const $t27406_i9996_i10608 = (3. + $t28099);
                        return ($t27405_i9995_i10607 * $t27406_i9996_i10608);
                      }
                    }
                  })();
                  return ($t27404_i9994_i10606 <= $t27407_i9997_i10609);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28096$apply$3720$clo = { _0: ($_, $clo, s) => $lam28096$apply$3720($clo, s) };

function $lam28103$apply$3721($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28110 = (() => {
        {
          const $t28104 = game.asteroids;
          {
            const $t28109 = { $: "$Clo_$lam28105$3722", _0: $lam28105$apply$3722, _1: s };
            return List$any$List_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28104, $t28109);
          }
        }
      })();
      return (!$t28110);
    }
  }
}
const $lam28103$apply$3721$clo = { _0: ($_, $clo, s) => $lam28103$apply$3721($clo, s) };

function $lam28105$apply$3722($clo, a) {
  {
    const s = (() => {
      return $clo._1;
    })();
    {
      const $t28106 = a.x;
      {
        const $t28107 = a.y;
        {
          const $t28108 = a.radius;
          {
            const $t28086_i10614 = s.x;
            {
              const $t28087_i10615 = s.y;
              {
                const $t27404_i9994_i10620 = (() => {
                  {
                    const dx_i3645_i9990_i10616 = ($t28106 - $t28086_i10614);
                    {
                      const dy_i3646_i9991_i10617 = ($t28107 - $t28087_i10615);
                      {
                        const $t27402_i3647_i9992_i10618 = (dx_i3645_i9990_i10616 * dx_i3645_i9990_i10616);
                        {
                          const $t27403_i3648_i9993_i10619 = (dy_i3646_i9991_i10617 * dy_i3646_i9991_i10617);
                          return ($t27402_i3647_i9992_i10618 + $t27403_i3648_i9993_i10619);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27407_i9997_i10623 = (() => {
                    {
                      const $t27405_i9995_i10621 = (3. + $t28108);
                      {
                        const $t27406_i9996_i10622 = (3. + $t28108);
                        return ($t27405_i9995_i10621 * $t27406_i9996_i10622);
                      }
                    }
                  })();
                  return ($t27404_i9994_i10620 <= $t27407_i9997_i10623);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28105$apply$3722$clo = { _0: ($_, $clo, a) => $lam28105$apply$3722($clo, a) };

function $lam28122$apply$3723($clo, sh) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28123 = game.player_shots;
      {
        const $t28125 = { $: "$Clo_$lam28124$3724", _0: $lam28124$apply$3724, _1: sh };
        return List$any$List_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28123, $t28125);
      }
    }
  }
}
const $lam28122$apply$3723$clo = { _0: ($_, $clo, sh) => $lam28122$apply$3723($clo, sh) };

function $lam28124$apply$3724($clo, s) {
  {
    const sh = (() => {
      return $clo._1;
    })();
    return Perihelion$Combat$ship_shot_hit(sh, s);
  }
}
const $lam28124$apply$3724$clo = { _0: ($_, $clo, s) => $lam28124$apply$3724($clo, s) };

function $lam28128$apply$3725($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28132 = (() => {
        {
          const $t28129 = game.ships;
          {
            const $t28131 = { $: "$Clo_$lam28130$3726", _0: $lam28130$apply$3726, _1: s };
            return List$any$List_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float$Fn_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float_Bool($t28129, $t28131);
          }
        }
      })();
      return (!$t28132);
    }
  }
}
const $lam28128$apply$3725$clo = { _0: ($_, $clo, s) => $lam28128$apply$3725($clo, s) };

function $lam28130$apply$3726($clo, sh) {
  {
    const s = (() => {
      return $clo._1;
    })();
    return Perihelion$Combat$ship_shot_hit(sh, s);
  }
}
const $lam28130$apply$3726$clo = { _0: ($_, $clo, sh) => $lam28130$apply$3726($clo, sh) };

function $lam28179$apply$3728($clo, p) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28172_i10626 = p.x;
      {
        const $t28173_i10627 = p.y;
        {
          const $t28175_i10628 = game.ball_x;
          {
            const $t28176_i10629 = game.ball_y;
            {
              const $t27404_i10013_i10634 = (() => {
                {
                  const dx_i3645_i10009_i10630 = ($t28175_i10628 - $t28172_i10626);
                  {
                    const dy_i3646_i10010_i10631 = ($t28176_i10629 - $t28173_i10627);
                    {
                      const $t27402_i3647_i10011_i10632 = (dx_i3645_i10009_i10630 * dx_i3645_i10009_i10630);
                      {
                        const $t27403_i3648_i10012_i10633 = (dy_i3646_i10010_i10631 * dy_i3646_i10010_i10631);
                        return ($t27402_i3647_i10011_i10632 + $t27403_i3648_i10012_i10633);
                      }
                    }
                  }
                }
              })();
              {
                const $t27407_i10016_i10637 = (() => {
                  {
                    const $t27405_i10014_i10635 = (12. + 6.);
                    {
                      const $t27406_i10015_i10636 = (12. + 6.);
                      return ($t27405_i10014_i10635 * $t27406_i10015_i10636);
                    }
                  }
                })();
                return ($t27404_i10013_i10634 <= $t27407_i10016_i10637);
              }
            }
          }
        }
      }
    }
  }
}
const $lam28179$apply$3728$clo = { _0: ($_, $clo, p) => $lam28179$apply$3728($clo, p) };

function $lam28183$apply$3729($clo, q) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28184 = (() => {
        {
          const $t28172_i10640 = q.x;
          {
            const $t28173_i10641 = q.y;
            {
              const $t28175_i10642 = game.ball_x;
              {
                const $t28176_i10643 = game.ball_y;
                {
                  const $t27404_i10013_i10648 = (() => {
                    {
                      const dx_i3645_i10009_i10644 = ($t28175_i10642 - $t28172_i10640);
                      {
                        const dy_i3646_i10010_i10645 = ($t28176_i10643 - $t28173_i10641);
                        {
                          const $t27402_i3647_i10011_i10646 = (dx_i3645_i10009_i10644 * dx_i3645_i10009_i10644);
                          {
                            const $t27403_i3648_i10012_i10647 = (dy_i3646_i10010_i10645 * dy_i3646_i10010_i10645);
                            return ($t27402_i3647_i10011_i10646 + $t27403_i3648_i10012_i10647);
                          }
                        }
                      }
                    }
                  })();
                  {
                    const $t27407_i10016_i10651 = (() => {
                      {
                        const $t27405_i10014_i10649 = (12. + 6.);
                        {
                          const $t27406_i10015_i10650 = (12. + 6.);
                          return ($t27405_i10014_i10649 * $t27406_i10015_i10650);
                        }
                      }
                    })();
                    return ($t27404_i10013_i10648 <= $t27407_i10016_i10651);
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t28184);
    }
  }
}
const $lam28183$apply$3729$clo = { _0: ($_, $clo, q) => $lam28183$apply$3729($clo, q) };

function $jp28201$apply$3730($clo) {
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
          const $t28199 = (() => {
            {
              const $t28198 = p.kind;
              return Perihelion$Core$apply_upgrade(game, $t28198);
            }
          })();
          return ({ ...$t28199, pickups: remaining });
        }
      }
    }
  }
}
const $jp28201$apply$3730$clo = { _0: ($_, $clo) => $jp28201$apply$3730($clo) };

function $jp28205$apply$3731($clo) {
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
          const $t28199 = (() => {
            {
              const $t28198 = p.kind;
              return Perihelion$Core$apply_upgrade(game, $t28198);
            }
          })();
          return ({ ...$t28199, pickups: remaining });
        }
      }
    }
  }
}
const $jp28205$apply$3731$clo = { _0: ($_, $clo) => $jp28205$apply$3731($clo) };

function $lam28226$apply$3732($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28219_i10756 = game.ball_x;
      {
        const $t28220_i10757 = game.ball_y;
        {
          const $t28086_i10388_i10758 = s.x;
          {
            const $t28087_i10389_i10759 = s.y;
            {
              const $t27404_i9994_i10394_i10764 = (() => {
                {
                  const dx_i3645_i9990_i10390_i10760 = ($t28219_i10756 - $t28086_i10388_i10758);
                  {
                    const dy_i3646_i9991_i10391_i10761 = ($t28220_i10757 - $t28087_i10389_i10759);
                    {
                      const $t27402_i3647_i9992_i10392_i10762 = (dx_i3645_i9990_i10390_i10760 * dx_i3645_i9990_i10390_i10760);
                      {
                        const $t27403_i3648_i9993_i10393_i10763 = (dy_i3646_i9991_i10391_i10761 * dy_i3646_i9991_i10391_i10761);
                        return ($t27402_i3647_i9992_i10392_i10762 + $t27403_i3648_i9993_i10393_i10763);
                      }
                    }
                  }
                }
              })();
              {
                const $t27407_i9997_i10397_i10767 = (() => {
                  {
                    const $t27405_i9995_i10395_i10765 = (3. + 6.);
                    {
                      const $t27406_i9996_i10396_i10766 = (3. + 6.);
                      return ($t27405_i9995_i10395_i10765 * $t27406_i9996_i10396_i10766);
                    }
                  }
                })();
                return ($t27404_i9994_i10394_i10764 <= $t27407_i9997_i10397_i10767);
              }
            }
          }
        }
      }
    }
  }
}
const $lam28226$apply$3732$clo = { _0: ($_, $clo, s) => $lam28226$apply$3732($clo, s) };

function $lam28231$apply$3733($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28232 = (() => {
        {
          const $t28219_i10770 = game.ball_x;
          {
            const $t28220_i10771 = game.ball_y;
            {
              const $t28086_i10388_i10772 = s.x;
              {
                const $t28087_i10389_i10773 = s.y;
                {
                  const $t27404_i9994_i10394_i10778 = (() => {
                    {
                      const dx_i3645_i9990_i10390_i10774 = ($t28219_i10770 - $t28086_i10388_i10772);
                      {
                        const dy_i3646_i9991_i10391_i10775 = ($t28220_i10771 - $t28087_i10389_i10773);
                        {
                          const $t27402_i3647_i9992_i10392_i10776 = (dx_i3645_i9990_i10390_i10774 * dx_i3645_i9990_i10390_i10774);
                          {
                            const $t27403_i3648_i9993_i10393_i10777 = (dy_i3646_i9991_i10391_i10775 * dy_i3646_i9991_i10391_i10775);
                            return ($t27402_i3647_i9992_i10392_i10776 + $t27403_i3648_i9993_i10393_i10777);
                          }
                        }
                      }
                    }
                  })();
                  {
                    const $t27407_i9997_i10397_i10781 = (() => {
                      {
                        const $t27405_i9995_i10395_i10779 = (3. + 6.);
                        {
                          const $t27406_i9996_i10396_i10780 = (3. + 6.);
                          return ($t27405_i9995_i10395_i10779 * $t27406_i9996_i10396_i10780);
                        }
                      }
                    })();
                    return ($t27404_i9994_i10394_i10778 <= $t27407_i9997_i10397_i10781);
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t28232);
    }
  }
}
const $lam28231$apply$3733$clo = { _0: ($_, $clo, s) => $lam28231$apply$3733($clo, s) };

function $lam28236$apply$3734($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28213_i10654 = a.x;
      {
        const $t28214_i10655 = a.y;
        {
          const $t28215_i10656 = a.radius;
          {
            const $t28216_i10657 = game.ball_x;
            {
              const $t28217_i10658 = game.ball_y;
              {
                const $t27404_i10041_i10663 = (() => {
                  {
                    const dx_i3645_i10037_i10659 = ($t28216_i10657 - $t28213_i10654);
                    {
                      const dy_i3646_i10038_i10660 = ($t28217_i10658 - $t28214_i10655);
                      {
                        const $t27402_i3647_i10039_i10661 = (dx_i3645_i10037_i10659 * dx_i3645_i10037_i10659);
                        {
                          const $t27403_i3648_i10040_i10662 = (dy_i3646_i10038_i10660 * dy_i3646_i10038_i10660);
                          return ($t27402_i3647_i10039_i10661 + $t27403_i3648_i10040_i10662);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27407_i10044_i10666 = (() => {
                    {
                      const $t27405_i10042_i10664 = ($t28215_i10656 + 6.);
                      {
                        const $t27406_i10043_i10665 = ($t28215_i10656 + 6.);
                        return ($t27405_i10042_i10664 * $t27406_i10043_i10665);
                      }
                    }
                  })();
                  return ($t27404_i10041_i10663 <= $t27407_i10044_i10666);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28236$apply$3734$clo = { _0: ($_, $clo, a) => $lam28236$apply$3734($clo, a) };

function $lam28239$apply$3735($clo, sh) {
  {
    const game = (() => {
      return $clo._1;
    })();
    return Perihelion$Combat$ball_hits_ship(game, sh);
  }
}
const $lam28239$apply$3735$clo = { _0: ($_, $clo, sh) => $lam28239$apply$3735($clo, sh) };

function $lam28255$apply$3736($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28213_i10669 = a.x;
      {
        const $t28214_i10670 = a.y;
        {
          const $t28215_i10671 = a.radius;
          {
            const $t28216_i10672 = game.ball_x;
            {
              const $t28217_i10673 = game.ball_y;
              {
                const $t27404_i10041_i10678 = (() => {
                  {
                    const dx_i3645_i10037_i10674 = ($t28216_i10672 - $t28213_i10669);
                    {
                      const dy_i3646_i10038_i10675 = ($t28217_i10673 - $t28214_i10670);
                      {
                        const $t27402_i3647_i10039_i10676 = (dx_i3645_i10037_i10674 * dx_i3645_i10037_i10674);
                        {
                          const $t27403_i3648_i10040_i10677 = (dy_i3646_i10038_i10675 * dy_i3646_i10038_i10675);
                          return ($t27402_i3647_i10039_i10676 + $t27403_i3648_i10040_i10677);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27407_i10044_i10681 = (() => {
                    {
                      const $t27405_i10042_i10679 = ($t28215_i10671 + 6.);
                      {
                        const $t27406_i10043_i10680 = ($t28215_i10671 + 6.);
                        return ($t27405_i10042_i10679 * $t27406_i10043_i10680);
                      }
                    }
                  })();
                  return ($t27404_i10041_i10678 <= $t27407_i10044_i10681);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28255$apply$3736$clo = { _0: ($_, $clo, a) => $lam28255$apply$3736($clo, a) };

function $lam28260$apply$3737($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28261 = (() => {
        {
          const $t28213_i10684 = a.x;
          {
            const $t28214_i10685 = a.y;
            {
              const $t28215_i10686 = a.radius;
              {
                const $t28216_i10687 = game.ball_x;
                {
                  const $t28217_i10688 = game.ball_y;
                  {
                    const $t27404_i10041_i10693 = (() => {
                      {
                        const dx_i3645_i10037_i10689 = ($t28216_i10687 - $t28213_i10684);
                        {
                          const dy_i3646_i10038_i10690 = ($t28217_i10688 - $t28214_i10685);
                          {
                            const $t27402_i3647_i10039_i10691 = (dx_i3645_i10037_i10689 * dx_i3645_i10037_i10689);
                            {
                              const $t27403_i3648_i10040_i10692 = (dy_i3646_i10038_i10690 * dy_i3646_i10038_i10690);
                              return ($t27402_i3647_i10039_i10691 + $t27403_i3648_i10040_i10692);
                            }
                          }
                        }
                      }
                    })();
                    {
                      const $t27407_i10044_i10696 = (() => {
                        {
                          const $t27405_i10042_i10694 = ($t28215_i10686 + 6.);
                          {
                            const $t27406_i10043_i10695 = ($t28215_i10686 + 6.);
                            return ($t27405_i10042_i10694 * $t27406_i10043_i10695);
                          }
                        }
                      })();
                      return ($t27404_i10041_i10693 <= $t27407_i10044_i10696);
                    }
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t28261);
    }
  }
}
const $lam28260$apply$3737$clo = { _0: ($_, $clo, a) => $lam28260$apply$3737($clo, a) };

function $lam28265$apply$3738($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28266 = (() => {
        {
          const $t28219_i10784 = game.ball_x;
          {
            const $t28220_i10785 = game.ball_y;
            {
              const $t28086_i10388_i10786 = s.x;
              {
                const $t28087_i10389_i10787 = s.y;
                {
                  const $t27404_i9994_i10394_i10792 = (() => {
                    {
                      const dx_i3645_i9990_i10390_i10788 = ($t28219_i10784 - $t28086_i10388_i10786);
                      {
                        const dy_i3646_i9991_i10391_i10789 = ($t28220_i10785 - $t28087_i10389_i10787);
                        {
                          const $t27402_i3647_i9992_i10392_i10790 = (dx_i3645_i9990_i10390_i10788 * dx_i3645_i9990_i10390_i10788);
                          {
                            const $t27403_i3648_i9993_i10393_i10791 = (dy_i3646_i9991_i10391_i10789 * dy_i3646_i9991_i10391_i10789);
                            return ($t27402_i3647_i9992_i10392_i10790 + $t27403_i3648_i9993_i10393_i10791);
                          }
                        }
                      }
                    }
                  })();
                  {
                    const $t27407_i9997_i10397_i10795 = (() => {
                      {
                        const $t27405_i9995_i10395_i10793 = (3. + 6.);
                        {
                          const $t27406_i9996_i10396_i10794 = (3. + 6.);
                          return ($t27405_i9995_i10395_i10793 * $t27406_i9996_i10396_i10794);
                        }
                      }
                    })();
                    return ($t27404_i9994_i10394_i10792 <= $t27407_i9997_i10397_i10795);
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t28266);
    }
  }
}
const $lam28265$apply$3738$clo = { _0: ($_, $clo, s) => $lam28265$apply$3738($clo, s) };

function $lam28270$apply$3739($clo, sh) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28271 = Perihelion$Combat$ball_hits_ship(game, sh);
      return (!$t28271);
    }
  }
}
const $lam28270$apply$3739$clo = { _0: ($_, $clo, sh) => $lam28270$apply$3739($clo, sh) };

function $lam28352$apply$3740($clo, k) {
  {
    const $t28353 = (() => {
      return (k === "w");
    })();
    {
      const $t28354 = (k === "W");
      return ($t28353 || $t28354);
    }
  }
}
const $lam28352$apply$3740$clo = { _0: ($_, $clo, k) => $lam28352$apply$3740($clo, k) };

function $lam28356$apply$3741($clo, k) {
  {
    const $t28357 = (() => {
      return (k === "s");
    })();
    {
      const $t28358 = (k === "S");
      return ($t28357 || $t28358);
    }
  }
}
const $lam28356$apply$3741$clo = { _0: ($_, $clo, k) => $lam28356$apply$3741($clo, k) };

function $lam28371$apply$3742($clo, k) {
  {
    const $t28372 = (() => {
      return (k === "e");
    })();
    {
      const $t28373 = (k === "E");
      return ($t28372 || $t28373);
    }
  }
}
const $lam28371$apply$3742$clo = { _0: ($_, $clo, k) => $lam28371$apply$3742($clo, k) };

function $lam28375$apply$3743($clo, k) {
  {
    const $t28376 = (() => {
      return (k === "q");
    })();
    {
      const $t28377 = (k === "Q");
      return ($t28376 || $t28377);
    }
  }
}
const $lam28375$apply$3743$clo = { _0: ($_, $clo, k) => $lam28375$apply$3743($clo, k) };

function $lam28383$apply$3744($clo, k) {
  {
    const $t28384 = (() => {
      return (k === "d");
    })();
    {
      const $t28385 = (k === "D");
      return ($t28384 || $t28385);
    }
  }
}
const $lam28383$apply$3744$clo = { _0: ($_, $clo, k) => $lam28383$apply$3744($clo, k) };

function $lam28387$apply$3745($clo, k) {
  {
    const $t28388 = (() => {
      return (k === "w");
    })();
    {
      const $t28389 = (k === "W");
      return ($t28388 || $t28389);
    }
  }
}
const $lam28387$apply$3745$clo = { _0: ($_, $clo, k) => $lam28387$apply$3745($clo, k) };

function $lam28440$apply$3748($clo, k) {
  {
    const $t28441 = (() => {
      return (k === "x");
    })();
    {
      const $t28442 = (k === "X");
      return ($t28441 || $t28442);
    }
  }
}
const $lam28440$apply$3748$clo = { _0: ($_, $clo, k) => $lam28440$apply$3748($clo, k) };

function $lam28480$apply$3753($clo, k) {
  {
    const $t28481 = (() => {
      return (k === "r");
    })();
    {
      const $t28482 = (k === "R");
      return ($t28481 || $t28482);
    }
  }
}
const $lam28480$apply$3753$clo = { _0: ($_, $clo, k) => $lam28480$apply$3753($clo, k) };

function $jp28793$apply$3765($clo) {
  {
    const $f28788 = (() => {
      return $clo._1;
    })();
    {
      const fallback = (() => {
        return $clo._2;
      })();
      {
        const rest = (() => {
          return $f28788;
        })();
        return Perihelion$Core$top_star(rest, fallback);
      }
    }
  }
}
const $jp28793$apply$3765$clo = { _0: ($_, $clo) => $jp28793$apply$3765($clo) };

function $lam28998$apply$3777($clo, r) {
  return Perihelion$Core$encode_run(r);
}
const $lam28998$apply$3777$clo = { _0: ($_, $clo, r) => $lam28998$apply$3777($clo, r) };

function $jp29012$apply$3778($clo) {
  return { $: "None" };
}
const $jp29012$apply$3778$clo = { _0: ($_, $clo) => $jp29012$apply$3778($clo) };

function $jp29016$apply$3779($clo) {
  {
    const $jp_clo29013 = (() => {
      return $clo._1;
    })();
    {
      const $jp_clo29015 = (() => {
        return { $: "$Clo_$jp29014$3780", _0: $jp29014$apply$3780, _1: $jp_clo29013 };
      })();
      return $jp29014$apply$3780($jp_clo29015);
    }
  }
}
const $jp29016$apply$3779$clo = { _0: ($_, $clo) => $jp29016$apply$3779($clo) };

function $jp29014$apply$3780($clo) {
  {
    const $jp_clo29013 = (() => {
      return $clo._1;
    })();
    return $jp_clo29013._0($jp_clo29013);
  }
}
const $jp29014$apply$3780$clo = { _0: ($_, $clo) => $jp29014$apply$3780($clo) };

function $jp29020$apply$3781($clo) {
  {
    const $jp_clo29017 = (() => {
      return $clo._1;
    })();
    return $jp_clo29017._0($jp_clo29017);
  }
}
const $jp29020$apply$3781$clo = { _0: ($_, $clo) => $jp29020$apply$3781($clo) };

function $jp29024$apply$3782($clo) {
  {
    const $jp_clo29021 = (() => {
      return $clo._1;
    })();
    {
      const $jp_clo29023 = (() => {
        return { $: "$Clo_$jp29022$3783", _0: $jp29022$apply$3783, _1: $jp_clo29021 };
      })();
      return $jp29022$apply$3783($jp_clo29023);
    }
  }
}
const $jp29024$apply$3782$clo = { _0: ($_, $clo) => $jp29024$apply$3782($clo) };

function $jp29022$apply$3783($clo) {
  {
    const $jp_clo29021 = (() => {
      return $clo._1;
    })();
    return $jp_clo29021._0($jp_clo29021);
  }
}
const $jp29022$apply$3783$clo = { _0: ($_, $clo) => $jp29022$apply$3783($clo) };

function $jp29028$apply$3784($clo) {
  {
    const $jp_clo29025 = (() => {
      return $clo._1;
    })();
    return $jp_clo29025._0($jp_clo29025);
  }
}
const $jp29028$apply$3784$clo = { _0: ($_, $clo) => $jp29028$apply$3784($clo) };

function $jp29032$apply$3785($clo) {
  {
    const $jp_clo29029 = (() => {
      return $clo._1;
    })();
    {
      const $jp_clo29031 = (() => {
        return { $: "$Clo_$jp29030$3786", _0: $jp29030$apply$3786, _1: $jp_clo29029 };
      })();
      return $jp29030$apply$3786($jp_clo29031);
    }
  }
}
const $jp29032$apply$3785$clo = { _0: ($_, $clo) => $jp29032$apply$3785($clo) };

function $jp29030$apply$3786($clo) {
  {
    const $jp_clo29029 = (() => {
      return $clo._1;
    })();
    return $jp_clo29029._0($jp_clo29029);
  }
}
const $jp29030$apply$3786$clo = { _0: ($_, $clo) => $jp29030$apply$3786($clo) };

function $lam29222$apply$3795($clo, u) {
  {
    const owned = (() => {
      return $clo._1;
    })();
    switch (u.$) {
      case "OffenseWeapon": {
        const $f29224 = u._0;
        {
          const k = $f29224;
          {
            const $t29223 = (() => {
              {
                const $t709_i7732 = { $: "$Clo_$lam708$4787", _0: $lam708$apply$4787, _1: k };
                return List$any$List_WeaponKind$Fn_WeaponKind_Bool(owned, $t709_i7732);
              }
            })();
            return (!$t29223);
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
const $lam29222$apply$3795$clo = { _0: ($_, $clo, u) => $lam29222$apply$3795($clo, u) };

function $lam29260$apply$3796($clo, u) {
  {
    const k = (() => {
      return $clo._1;
    })();
    switch (u.$) {
      case "SpecialItem": {
        const $f29261 = u._0;
        {
          const sk = $f29261;
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
const $lam29260$apply$3796$clo = { _0: ($_, $clo, u) => $lam29260$apply$3796($clo, u) };

function $lam29318$apply$3798($clo, p) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const $t29311_i7739 = (() => {
        {
          const $t29308_i7736 = p.x;
          {
            const $t29310_i7738 = (() => {
              {
                const $t29309_i7737 = p.vx;
                return ($t29309_i7737 * dt_s);
              }
            })();
            return ($t29308_i7736 + $t29310_i7738);
          }
        }
      })();
      {
        const $t29315_i7743 = (() => {
          {
            const $t29312_i7740 = p.y;
            {
              const $t29314_i7742 = (() => {
                {
                  const $t29313_i7741 = p.vy;
                  return ($t29313_i7741 * dt_s);
                }
              })();
              return ($t29312_i7740 + $t29314_i7742);
            }
          }
        })();
        {
          const $t29317_i7745 = (() => {
            {
              const $t29316_i7744 = p.life;
              return ($t29316_i7744 - dt_s);
            }
          })();
          return ({ ...p, x: $t29311_i7739, y: $t29315_i7743, life: $t29317_i7745 });
        }
      }
    }
  }
}
const $lam29318$apply$3798$clo = { _0: ($_, $clo, p) => $lam29318$apply$3798($clo, p) };

function $lam29321$apply$3799($clo, p) {
  {
    const $t29322 = p.life;
    return ($t29322 > 0.);
  }
}
const $lam29321$apply$3799$clo = { _0: ($_, $clo, p) => $lam29321$apply$3799($clo, p) };

function $jp29467$apply$3802($clo) {
  {
    const $f29461 = (() => {
      return $clo._1;
    })();
    {
      const $f29462 = (() => {
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
              return $f29462;
            })();
            {
              const o = (() => {
                return $f29461;
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
                  const $t29457 = s.x;
                  {
                    const $t29458 = s.y;
                    {
                      const $t29459 = o.radius;
                      return Canvas$arc(ctx, $t29457, $t29458, $t29459, 0., 6.28318530718);
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
const $jp29467$apply$3802$clo = { _0: ($_, $clo) => $jp29467$apply$3802($clo) };

function $jp29506$apply$3805($clo) {
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
          const $t29505 = dot_count(s);
          return draw_pulse_particle(ctx, s, t, $t29505, 0);
        }
      }
    }
  }
}
const $jp29506$apply$3805$clo = { _0: ($_, $clo) => $jp29506$apply$3805($clo) };

function $jp29508$apply$3806($clo) {
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
          const $t29505 = dot_count(s);
          return draw_pulse_particle(ctx, s, t, $t29505, 0);
        }
      }
    }
  }
}
const $jp29508$apply$3806$clo = { _0: ($_, $clo) => $jp29508$apply$3806($clo) };

function $jp29642$apply$3809($clo) {
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
const $jp29642$apply$3809$clo = { _0: ($_, $clo) => $jp29642$apply$3809($clo) };

function $lam29921$apply$3830($clo, k) {
  {
    const $t29922 = (() => {
      return (k === "m");
    })();
    {
      const $t29923 = (k === "M");
      return ($t29922 || $t29923);
    }
  }
}
const $lam29921$apply$3830$clo = { _0: ($_, $clo, k) => $lam29921$apply$3830($clo, k) };

function $jp29979$apply$3832($clo) {
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
const $jp29979$apply$3832$clo = { _0: ($_, $clo) => $jp29979$apply$3832($clo) };

function $lam29990$apply$3833($clo, _) {
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
const $lam29990$apply$3833$clo = { _0: ($_, $clo, _) => $lam29990$apply$3833($clo, _) };

function $lam30003$apply$3834($clo, _) {
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
const $lam30003$apply$3834$clo = { _0: ($_, $clo, _) => $lam30003$apply$3834($clo, _) };

function go$apply$4092($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f287 = lst._0;
        const $f288 = lst._1;
        {
          const t = $f288;
          {
            const h = $f287;
            {
              const $t286 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t286);
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
const go$apply$4092$clo = { _0: ($_, $clo, lst, acc) => go$apply$4092($clo, lst, acc) };

function go$apply$4319($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f287 = lst._0;
        const $f288 = lst._1;
        {
          const t = $f288;
          {
            const h = $f287;
            {
              const $t286 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t286);
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
const go$apply$4319$clo = { _0: ($_, $clo, lst, acc) => go$apply$4319($clo, lst, acc) };

function go$apply$4754($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f280 = lst._0;
        const $f281 = lst._1;
        {
          const t = $f281;
          {
            const $t279 = (acc + 1);
            return go._0(go, t, $t279);
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
const go$apply$4754$clo = { _0: ($_, $clo, lst, acc) => go$apply$4754($clo, lst, acc) };

function go$apply$4756($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8780 = { $: "$Clo_go$5239", _0: go$apply$5239 };
            {
              const $t293_i8781 = { $: "Nil" };
              return go$apply$5239(go_i8780, acc, $t293_i8781);
            }
          }
          break;
        }
        case "Cons": {
          const $f336 = lst._0;
          const $f337 = lst._1;
          {
            const t = $f337;
            {
              const h = $f336;
              {
                const $t334 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t334 === true) {
                  return (() => {
                    {
                      const $t335 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t335);
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
const go$apply$4756$clo = { _0: ($_, $clo, lst, acc) => go$apply$4756($clo, lst, acc) };

function go$apply$4758($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8785 = { $: "$Clo_go$5239", _0: go$apply$5239 };
            {
              const $t293_i8786 = { $: "Nil" };
              return go$apply$5239(go_i8785, acc, $t293_i8786);
            }
          }
          break;
        }
        case "Cons": {
          const $f304 = lst._0;
          const $f305 = lst._1;
          {
            const t = $f305;
            {
              const h = $f304;
              {
                const $t302 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t303 = { $: "Cons", _0: $t302, _1: acc };
                  return go._0(go, t, $t303);
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
const go$apply$4758$clo = { _0: ($_, $clo, lst, acc) => go$apply$4758($clo, lst, acc) };

function go$apply$4760($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8790 = { $: "$Clo_go$5241", _0: go$apply$5241 };
            {
              const $t293_i8791 = { $: "Nil" };
              return go$apply$5241(go_i8790, acc, $t293_i8791);
            }
          }
          break;
        }
        case "Cons": {
          const $f336 = lst._0;
          const $f337 = lst._1;
          {
            const t = $f337;
            {
              const h = $f336;
              {
                const $t334 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t334 === true) {
                  return (() => {
                    {
                      const $t335 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t335);
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
const go$apply$4760$clo = { _0: ($_, $clo, lst, acc) => go$apply$4760($clo, lst, acc) };

function go$apply$4762($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8795 = { $: "$Clo_go$5241", _0: go$apply$5241 };
            {
              const $t293_i8796 = { $: "Nil" };
              return go$apply$5241(go_i8795, acc, $t293_i8796);
            }
          }
          break;
        }
        case "Cons": {
          const $f304 = lst._0;
          const $f305 = lst._1;
          {
            const t = $f305;
            {
              const h = $f304;
              {
                const $t302 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t303 = { $: "Cons", _0: $t302, _1: acc };
                  return go._0(go, t, $t303);
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
const go$apply$4762$clo = { _0: ($_, $clo, lst, acc) => go$apply$4762($clo, lst, acc) };

function go$apply$4764($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f287 = lst._0;
        const $f288 = lst._1;
        {
          const t = $f288;
          {
            const h = $f287;
            {
              const $t286 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t286);
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
const go$apply$4764$clo = { _0: ($_, $clo, lst, acc) => go$apply$4764($clo, lst, acc) };

function go$apply$4766($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f295 = lst._0;
        const $f296 = lst._1;
        {
          const t = $f296;
          {
            const h = $f295;
            {
              const $t294 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t294);
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
const go$apply$4766$clo = { _0: ($_, $clo, lst, acc) => go$apply$4766($clo, lst, acc) };

function go$apply$4768($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f287 = lst._0;
        const $f288 = lst._1;
        {
          const t = $f288;
          {
            const h = $f287;
            {
              const $t286 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t286);
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
const go$apply$4768$clo = { _0: ($_, $clo, lst, acc) => go$apply$4768($clo, lst, acc) };

function go$apply$4770($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8806 = { $: "$Clo_go$4768", _0: go$apply$4768 };
            {
              const $t293_i8807 = { $: "Nil" };
              return go$apply$4768(go_i8806, acc, $t293_i8807);
            }
          }
          break;
        }
        case "Cons": {
          const $f304 = lst._0;
          const $f305 = lst._1;
          {
            const t = $f305;
            {
              const h = $f304;
              {
                const $t302 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t303 = { $: "Cons", _0: $t302, _1: acc };
                  return go._0(go, t, $t303);
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
const go$apply$4770$clo = { _0: ($_, $clo, lst, acc) => go$apply$4770($clo, lst, acc) };

function go$apply$4772($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8811 = { $: "$Clo_go$4768", _0: go$apply$4768 };
            {
              const $t293_i8812 = { $: "Nil" };
              return go$apply$4768(go_i8811, acc, $t293_i8812);
            }
          }
          break;
        }
        case "Cons": {
          const $f336 = lst._0;
          const $f337 = lst._1;
          {
            const t = $f337;
            {
              const h = $f336;
              {
                const $t334 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t334 === true) {
                  return (() => {
                    {
                      const $t335 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t335);
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
const go$apply$4772$clo = { _0: ($_, $clo, lst, acc) => go$apply$4772($clo, lst, acc) };

function go$apply$4774($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8816 = { $: "$Clo_go$4319", _0: go$apply$4319 };
            {
              const $t293_i8817 = { $: "Nil" };
              return go$apply$4319(go_i8816, acc, $t293_i8817);
            }
          }
          break;
        }
        case "Cons": {
          const $f304 = lst._0;
          const $f305 = lst._1;
          {
            const t = $f305;
            {
              const h = $f304;
              {
                const $t302 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t303 = { $: "Cons", _0: $t302, _1: acc };
                  return go._0(go, t, $t303);
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
const go$apply$4774$clo = { _0: ($_, $clo, lst, acc) => go$apply$4774($clo, lst, acc) };

function go$apply$4776($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f280 = lst._0;
        const $f281 = lst._1;
        {
          const t = $f281;
          {
            const $t279 = (acc + 1);
            return go._0(go, t, $t279);
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
const go$apply$4776$clo = { _0: ($_, $clo, lst, acc) => go$apply$4776($clo, lst, acc) };

function go$apply$4779($clo, lst, yes, no) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const $t586 = (() => {
              {
                const go_i8827 = { $: "$Clo_go$4764", _0: go$apply$4764 };
                {
                  const $t293_i8828 = { $: "Nil" };
                  return go$apply$4764(go_i8827, yes, $t293_i8828);
                }
              }
            })();
            {
              const $t587 = (() => {
                {
                  const go_i8824 = { $: "$Clo_go$4764", _0: go$apply$4764 };
                  {
                    const $t293_i8825 = { $: "Nil" };
                    return go$apply$4764(go_i8824, no, $t293_i8825);
                  }
                }
              })();
              return { _0: $t586, _1: $t587 };
            }
          }
          break;
        }
        case "Cons": {
          const $f591 = lst._0;
          const $f592 = lst._1;
          {
            const t = $f592;
            {
              const h = $f591;
              {
                const $t588 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t588 === true) {
                  return (() => {
                    {
                      const $t589 = { $: "Cons", _0: h, _1: yes };
                      return go._0(go, t, $t589, no);
                    }
                  })();
                } else {
                  return (() => {
                    {
                      const $t590 = { $: "Cons", _0: h, _1: no };
                      return go._0(go, t, yes, $t590);
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
const go$apply$4779$clo = { _0: ($_, $clo, lst, yes, no) => go$apply$4779($clo, lst, yes, no) };

function go$apply$4782($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f280 = lst._0;
        const $f281 = lst._1;
        {
          const t = $f281;
          {
            const $t279 = (acc + 1);
            return go._0(go, t, $t279);
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

function go$apply$4785($clo, lst, yes, no) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const $t586 = (() => {
              {
                const go_i8839 = { $: "$Clo_go$4768", _0: go$apply$4768 };
                {
                  const $t293_i8840 = { $: "Nil" };
                  return go$apply$4768(go_i8839, yes, $t293_i8840);
                }
              }
            })();
            {
              const $t587 = (() => {
                {
                  const go_i8836 = { $: "$Clo_go$4768", _0: go$apply$4768 };
                  {
                    const $t293_i8837 = { $: "Nil" };
                    return go$apply$4768(go_i8836, no, $t293_i8837);
                  }
                }
              })();
              return { _0: $t586, _1: $t587 };
            }
          }
          break;
        }
        case "Cons": {
          const $f591 = lst._0;
          const $f592 = lst._1;
          {
            const t = $f592;
            {
              const h = $f591;
              {
                const $t588 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t588 === true) {
                  return (() => {
                    {
                      const $t589 = { $: "Cons", _0: h, _1: yes };
                      return go._0(go, t, $t589, no);
                    }
                  })();
                } else {
                  return (() => {
                    {
                      const $t590 = { $: "Cons", _0: h, _1: no };
                      return go._0(go, t, yes, $t590);
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
const go$apply$4785$clo = { _0: ($_, $clo, lst, yes, no) => go$apply$4785($clo, lst, yes, no) };

function $lam708$apply$4787($clo, y) {
  {
    const x = (() => {
      return $clo._1;
    })();
    return (y === x);
  }
}
const $lam708$apply$4787$clo = { _0: ($_, $clo, y) => $lam708$apply$4787($clo, y) };

function go$apply$4789($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f295 = lst._0;
        const $f296 = lst._1;
        {
          const t = $f296;
          {
            const h = $f295;
            {
              const $t294 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t294);
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
const go$apply$4789$clo = { _0: ($_, $clo, lst, acc) => go$apply$4789($clo, lst, acc) };

function go$apply$4791($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8847 = { $: "$Clo_go$4764", _0: go$apply$4764 };
            {
              const $t293_i8848 = { $: "Nil" };
              return go$apply$4764(go_i8847, acc, $t293_i8848);
            }
          }
          break;
        }
        case "Cons": {
          const $f336 = lst._0;
          const $f337 = lst._1;
          {
            const t = $f337;
            {
              const h = $f336;
              {
                const $t334 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t334 === true) {
                  return (() => {
                    {
                      const $t335 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t335);
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
const go$apply$4791$clo = { _0: ($_, $clo, lst, acc) => go$apply$4791($clo, lst, acc) };

function go$apply$4794($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f295 = lst._0;
        const $f296 = lst._1;
        {
          const t = $f296;
          {
            const h = $f295;
            {
              const $t294 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t294);
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
const go$apply$4794$clo = { _0: ($_, $clo, lst, acc) => go$apply$4794($clo, lst, acc) };

function go$apply$4797($clo, lst, k, acc) {
  {
    const go = $clo;
    {
      const $t539 = (k <= 0);
      if ($t539 === true) {
        return (() => {
          {
            const go_i8859 = { $: "$Clo_go$4092", _0: go$apply$4092 };
            {
              const $t293_i8860 = { $: "Nil" };
              return go$apply$4092(go_i8859, acc, $t293_i8860);
            }
          }
        })();
      } else {
        return (() => {
          switch (lst.$) {
            case "Nil": {
              {
                const go_i8856 = { $: "$Clo_go$4092", _0: go$apply$4092 };
                {
                  const $t293_i8857 = { $: "Nil" };
                  return go$apply$4092(go_i8856, acc, $t293_i8857);
                }
              }
              break;
            }
            case "Cons": {
              const $f542 = lst._0;
              const $f543 = lst._1;
              {
                const t = $f543;
                {
                  const h = $f542;
                  {
                    const $t540 = (k - 1);
                    {
                      const $t541 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t540, $t541);
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
const go$apply$4797$clo = { _0: ($_, $clo, lst, k, acc) => go$apply$4797($clo, lst, k, acc) };

function go$apply$4799($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f280 = lst._0;
        const $f281 = lst._1;
        {
          const t = $f281;
          {
            const $t279 = (acc + 1);
            return go._0(go, t, $t279);
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

function go$apply$4803($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f280 = lst._0;
        const $f281 = lst._1;
        {
          const t = $f281;
          {
            const $t279 = (acc + 1);
            return go._0(go, t, $t279);
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
const go$apply$4803$clo = { _0: ($_, $clo, lst, acc) => go$apply$4803($clo, lst, acc) };

function go$apply$4806($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f295 = lst._0;
        const $f296 = lst._1;
        {
          const t = $f296;
          {
            const h = $f295;
            {
              const $t294 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t294);
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
const go$apply$4806$clo = { _0: ($_, $clo, lst, acc) => go$apply$4806($clo, lst, acc) };

function go$apply$4808($clo, lst, k, acc) {
  {
    const go = $clo;
    {
      const $t539 = (k <= 0);
      if ($t539 === true) {
        return (() => {
          {
            const go_i8876 = { $: "$Clo_go$4092", _0: go$apply$4092 };
            {
              const $t293_i8877 = { $: "Nil" };
              return go$apply$4092(go_i8876, acc, $t293_i8877);
            }
          }
        })();
      } else {
        return (() => {
          switch (lst.$) {
            case "Nil": {
              {
                const go_i8873 = { $: "$Clo_go$4092", _0: go$apply$4092 };
                {
                  const $t293_i8874 = { $: "Nil" };
                  return go$apply$4092(go_i8873, acc, $t293_i8874);
                }
              }
              break;
            }
            case "Cons": {
              const $f542 = lst._0;
              const $f543 = lst._1;
              {
                const t = $f543;
                {
                  const h = $f542;
                  {
                    const $t540 = (k - 1);
                    {
                      const $t541 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t540, $t541);
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
const go$apply$4808$clo = { _0: ($_, $clo, lst, k, acc) => go$apply$4808($clo, lst, k, acc) };

function go$apply$4810($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8881 = { $: "$Clo_go$4092", _0: go$apply$4092 };
            {
              const $t293_i8882 = { $: "Nil" };
              return go$apply$4092(go_i8881, acc, $t293_i8882);
            }
          }
          break;
        }
        case "Cons": {
          const $f304 = lst._0;
          const $f305 = lst._1;
          {
            const t = $f305;
            {
              const h = $f304;
              {
                const $t302 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t303 = { $: "Cons", _0: $t302, _1: acc };
                  return go._0(go, t, $t303);
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
const go$apply$4810$clo = { _0: ($_, $clo, lst, acc) => go$apply$4810($clo, lst, acc) };

function go$apply$4812($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f287 = lst._0;
        const $f288 = lst._1;
        {
          const t = $f288;
          {
            const h = $f287;
            {
              const $t286 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t286);
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
const go$apply$4812$clo = { _0: ($_, $clo, lst, acc) => go$apply$4812($clo, lst, acc) };

function go$apply$4814($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f295 = lst._0;
        const $f296 = lst._1;
        {
          const t = $f296;
          {
            const h = $f295;
            {
              const $t294 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t294);
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
const go$apply$4814$clo = { _0: ($_, $clo, lst, acc) => go$apply$4814($clo, lst, acc) };

function go$apply$4816($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8890 = { $: "$Clo_go$5248", _0: go$apply$5248 };
            {
              const $t293_i8891 = { $: "Nil" };
              return go$apply$5248(go_i8890, acc, $t293_i8891);
            }
          }
          break;
        }
        case "Cons": {
          const $f336 = lst._0;
          const $f337 = lst._1;
          {
            const t = $f337;
            {
              const h = $f336;
              {
                const $t334 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t334 === true) {
                  return (() => {
                    {
                      const $t335 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t335);
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
const go$apply$4816$clo = { _0: ($_, $clo, lst, acc) => go$apply$4816($clo, lst, acc) };

function go$apply$4819($clo, lst, k, acc) {
  {
    const go = $clo;
    {
      const $t539 = (k <= 0);
      if ($t539 === true) {
        return (() => {
          {
            const go_i8899 = { $: "$Clo_go$4092", _0: go$apply$4092 };
            {
              const $t293_i8900 = { $: "Nil" };
              return go$apply$4092(go_i8899, acc, $t293_i8900);
            }
          }
        })();
      } else {
        return (() => {
          switch (lst.$) {
            case "Nil": {
              {
                const go_i8896 = { $: "$Clo_go$4092", _0: go$apply$4092 };
                {
                  const $t293_i8897 = { $: "Nil" };
                  return go$apply$4092(go_i8896, acc, $t293_i8897);
                }
              }
              break;
            }
            case "Cons": {
              const $f542 = lst._0;
              const $f543 = lst._1;
              {
                const t = $f543;
                {
                  const h = $f542;
                  {
                    const $t540 = (k - 1);
                    {
                      const $t541 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t540, $t541);
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
const go$apply$4819$clo = { _0: ($_, $clo, lst, k, acc) => go$apply$4819($clo, lst, k, acc) };

function go$apply$4822($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f280 = lst._0;
        const $f281 = lst._1;
        {
          const t = $f281;
          {
            const $t279 = (acc + 1);
            return go._0(go, t, $t279);
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
const go$apply$4822$clo = { _0: ($_, $clo, lst, acc) => go$apply$4822($clo, lst, acc) };

function go$apply$4824($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8907 = { $: "$Clo_go$5250", _0: go$apply$5250 };
            {
              const $t293_i8908 = { $: "Nil" };
              return go$apply$5250(go_i8907, acc, $t293_i8908);
            }
          }
          break;
        }
        case "Cons": {
          const $f336 = lst._0;
          const $f337 = lst._1;
          {
            const t = $f337;
            {
              const h = $f336;
              {
                const $t334 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t334 === true) {
                  return (() => {
                    {
                      const $t335 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t335);
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
const go$apply$4824$clo = { _0: ($_, $clo, lst, acc) => go$apply$4824($clo, lst, acc) };

function go$apply$4826($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i8912 = { $: "$Clo_go$5250", _0: go$apply$5250 };
            {
              const $t293_i8913 = { $: "Nil" };
              return go$apply$5250(go_i8912, acc, $t293_i8913);
            }
          }
          break;
        }
        case "Cons": {
          const $f304 = lst._0;
          const $f305 = lst._1;
          {
            const t = $f305;
            {
              const h = $f304;
              {
                const $t302 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t303 = { $: "Cons", _0: $t302, _1: acc };
                  return go._0(go, t, $t303);
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
const go$apply$4826$clo = { _0: ($_, $clo, lst, acc) => go$apply$4826($clo, lst, acc) };

function go$apply$4828($clo, lst, k, acc) {
  {
    const go = $clo;
    {
      const $t539 = (k <= 0);
      if ($t539 === true) {
        return (() => {
          {
            const go_i8920 = { $: "$Clo_go$4092", _0: go$apply$4092 };
            {
              const $t293_i8921 = { $: "Nil" };
              return go$apply$4092(go_i8920, acc, $t293_i8921);
            }
          }
        })();
      } else {
        return (() => {
          switch (lst.$) {
            case "Nil": {
              {
                const go_i8917 = { $: "$Clo_go$4092", _0: go$apply$4092 };
                {
                  const $t293_i8918 = { $: "Nil" };
                  return go$apply$4092(go_i8917, acc, $t293_i8918);
                }
              }
              break;
            }
            case "Cons": {
              const $f542 = lst._0;
              const $f543 = lst._1;
              {
                const t = $f543;
                {
                  const h = $f542;
                  {
                    const $t540 = (k - 1);
                    {
                      const $t541 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t540, $t541);
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
const go$apply$4828$clo = { _0: ($_, $clo, lst, k, acc) => go$apply$4828($clo, lst, k, acc) };

function go$apply$4830($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f280 = lst._0;
        const $f281 = lst._1;
        {
          const t = $f281;
          {
            const $t279 = (acc + 1);
            return go._0(go, t, $t279);
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
const go$apply$4830$clo = { _0: ($_, $clo, lst, acc) => go$apply$4830($clo, lst, acc) };

function go$apply$5239($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f287 = lst._0;
        const $f288 = lst._1;
        {
          const t = $f288;
          {
            const h = $f287;
            {
              const $t286 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t286);
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
const go$apply$5239$clo = { _0: ($_, $clo, lst, acc) => go$apply$5239($clo, lst, acc) };

function go$apply$5241($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f287 = lst._0;
        const $f288 = lst._1;
        {
          const t = $f288;
          {
            const h = $f287;
            {
              const $t286 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t286);
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
const go$apply$5241$clo = { _0: ($_, $clo, lst, acc) => go$apply$5241($clo, lst, acc) };

function go$apply$5244($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f287 = lst._0;
        const $f288 = lst._1;
        {
          const t = $f288;
          {
            const h = $f287;
            {
              const $t286 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t286);
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
const go$apply$5244$clo = { _0: ($_, $clo, lst, acc) => go$apply$5244($clo, lst, acc) };

function go$apply$5246($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f287 = lst._0;
        const $f288 = lst._1;
        {
          const t = $f288;
          {
            const h = $f287;
            {
              const $t286 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t286);
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
const go$apply$5246$clo = { _0: ($_, $clo, lst, acc) => go$apply$5246($clo, lst, acc) };

function go$apply$5248($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f287 = lst._0;
        const $f288 = lst._1;
        {
          const t = $f288;
          {
            const h = $f287;
            {
              const $t286 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t286);
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
const go$apply$5248$clo = { _0: ($_, $clo, lst, acc) => go$apply$5248($clo, lst, acc) };

function go$apply$5250($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f287 = lst._0;
        const $f288 = lst._1;
        {
          const t = $f288;
          {
            const h = $f287;
            {
              const $t286 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t286);
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
const go$apply$5250$clo = { _0: ($_, $clo, lst, acc) => go$apply$5250($clo, lst, acc) };

export { main };
main();
